# Hold-to-eject USB buttons — design

Date: 2026-07-09
Builds on: `2026-07-08-touch-browse-design.md` (implemented on branch `touch-browse`:
two-pane browse screen + Mixxx patch v1 `mixxx-patch/usb-browse.patch` with
`[Library],goto_usb_a/b`, CI pipeline on `ogg755/Pioneered`, deploy notes in
`docs/pi-deploy.md`). All v1 e2e checklist items passed on the Pi.

## Problem

Ejecting USB sticks currently requires the floating Tkinter overlay
(`~/usb-control.py`, plain `sudo umount`), which overlaps the skin and has no
awareness of what Mixxx is doing. One unexplained Mixxx segfault occurred during
v1 testing (no reproduction, no backtrace — evidence capture needed).

## Goal

Pioneer-style hold-to-eject on the skin's USB A/USB B buttons; retire the overlay.
Plus crash-evidence capture so any future segfault is diagnosable.

## Interaction (per button, identical for A/B)

- **Short press** (release < 0.6 s): browse toggle exactly as v1 (root at stick /
  restore full tree / switch stick) — now performed on *release*.
- **Hold ≥ 0.6 s**: button flashes red↔white, starting ≈2 Hz, accelerating
  smoothly to ≈6 Hz approaching 5 s.
- **Release between 0.6 s and 5 s**: cancel — no browse action, flash stops,
  button returns to its normal look.
- **At 5 s, stick in use** (either deck has a track whose path is under that
  mount, playing or paused): flash stops, red **"USB LOCKED"** banner centered in
  the deck strip for 2 s, no eject. (Chosen rule: block if loaded on any deck.)
- **At 5 s, stick free**: eject — unmount; on success the stick's device row
  disappears from the sidebar (playlists/tracks no longer visible), button dims
  to idle; safe to remove.
- **Unmount failure** (EBUSY etc.): red **"EJECT FAILED"** banner for 2 s; stick
  stays mounted and browsable.
- Only one button may be in a hold sequence at a time (second press ignored
  during a hold/eject).
- Re-inserted sticks auto-remount via the existing udev/systemd rule
  (`usb-mount@%k.service`) and reappear on the next USB-button press (v1
  behavior, unchanged).

## Architecture (patch v2 — extends mixxx-patch/usb-browse.patch)

Same three files as v1 (`library.h`, `librarycontrol.h`, `librarycontrol.cpp`),
roughly +170 lines. All logic in `LibraryControl`:

**Controls:**
- `[Library],goto_usb_a` / `goto_usb_b`: switched from TOGGLE back to **PUSH**
  mode so C++ receives press (1) and release (0). No longer used for display.
- `[Library],usb_a_state` / `usb_b_state` (new, set only by C++, skin
  display-only): 0 = idle/dark, 1 = active/red (sidebar rooted at this stick),
  2 = flash-white. Flashing = C++ QTimer alternating 1↔2 with shrinking
  toggle interval (250 ms → 80 ms over the 0.6–5 s window, i.e. ≈2 Hz → ≈6 Hz
  full red/white cycles).
- `[Library],usb_locked` / `usb_eject_failed` (new, set only by C++): 1 while
  the corresponding banner is shown; auto-cleared by a 2 s single-shot timer.

**Hold state machine:** per-button press timestamp + QTimers; release before
0.6 s dispatches the v1 browse-toggle logic; crossing 5 s runs the eject flow;
`usb_X_state` is the single source of truth for button visuals (kept in sync
with rooting changes from v1 paths too).

**Lock check:** `PlayerInfo::instance().getTrackInfo(group)` for `[Channel1]`,
`[Channel2]` (API verified present in 2.5.0); locked if a returned track's
`getLocation()` starts with `/media/USBA/` resp. `/media/USBB/` (trailing slash
prevents prefix collisions).

**Eject flow:** if the sidebar is rooted at the device, restore the full tree
first; run `sudo umount /media/USBX` via QProcess **asynchronously** (never
block the UI; identical command and passwordless-sudo mechanism the Tkinter
overlay already uses, so no sudoers changes). On exit 0: re-trigger the
Rekordbox feature scan (same `clicked(featureRoot)` mechanism as v1) so the
device row disappears; set state 0. On failure: `usb_eject_failed` banner,
state restored. Guarded to Linux only (`#ifdef Q_OS_LINUX`) so the patch stays
runnable on the Windows dev machine — non-Linux logs and shows EJECT FAILED.

## Skin changes

- USB buttons: `NumberStates` 2→3 (state 2 = white flash frame); connection 1 =
  `goto_usb_X` emit-only on press and release; connection 2 = `usb_X_state`
  display-only.
- Two banner labels centered in the deck strip (`UsbLockedBanner`,
  `UsbEjectFailedBanner`), text "USB LOCKED" / "EJECT FAILED", visible while
  their CO is 1; QSS: red background, white bold text; state-2 white button
  style added.
- Nothing else on the Browse screen moves.

## Pi-side changes (documented in docs/pi-deploy.md)

- Retire the Tkinter overlay from autostart after eject passes on-Pi testing.
- Crash evidence: `sudo apt install systemd-coredump gdb`; CI workflow
  additionally uploads the `mixxx-dbgsym` package it already builds, and the
  deploy doc gains a "getting a backtrace" section (`coredumpctl gdb mixxx`).
  No speculative code changes for the unreproduced v1 segfault.

## Error handling summary

Missing device / not mounted at 5 s → eject flow treats as already-ejected
no-op (state 0). Unmount failure → EJECT FAILED banner, no state loss. Unpatched
Mixxx → buttons inert as v1, skin still loads (banner labels simply never show).
Second button pressed during a hold → ignored. Mixxx quit mid-hold → timers die
with the object, no residue.

## Testing

- **Windows (dev)**: short-press browse regression; flash starts, accelerates,
  and cancels correctly; a full 5 s hold reaches the eject flow, which on
  non-Linux ends in the EJECT FAILED banner (exercising the failure branch and
  banner auto-clear). The lock path is Pi-only (no `/media/...` track paths
  exist on Windows).
- **Pi e2e**: eject with stick free (device row vanishes, pull stick, re-insert,
  press → reappears); USB LOCKED with a track loaded (paused and playing);
  cancel mid-hold; short-press regression of all v1 checklist items 1–9;
  overlay retired; coredump capture verified with a deliberate `kill -SEGV`
  of a test process (not Mixxx).
- CI build is the compile gate, as v1.

## Non-goals

- Fixing the unreproduced segfault (evidence capture only).
- Any change to mounting/udev, DDJ-400 mapping, or other skin screens.
- Multi-language banner text.
