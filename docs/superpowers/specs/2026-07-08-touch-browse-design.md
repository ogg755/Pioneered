# Touch-friendly USB browse screen — design

Date: 2026-07-08
Target: Pioneered skin (this repo) + small Mixxx patch, running on the XDJ400 Raspberry Pi 4B
(Raspberry Pi OS, X11/Openbox, Mixxx 2.5.x from apt, 7" 1024×600 HDMI touchscreen,
Rekordbox-exported USB sticks auto-mounted at `/media/USBA` and `/media/USBB`).

## Problem

The skin's Browse tab embeds Mixxx's stock library browser, which is unusable on a small
touchscreen:

- The sidebar tree and the track list are **mutually exclusive** — the skin's Show/Hide
  button swaps between them, so you can never see playlists and tracks at once.
- Rows and controls are desktop-sized; playlists are easy to mis-tap.
- Reaching a USB stick means drilling Rekordbox → device → playlist every time, through
  a tree cluttered with unused features (Tracks, Auto DJ, Analysis, History, …).

## Goal

A Pioneer-XDJ-style browse flow: tap **USB A** or **USB B**, see that stick's playlists,
tap a playlist, see its tracks, tap a track, tap **LOAD 1** or **LOAD 2**.

## Approach (chosen: skin rework + small Mixxx patch)

Considered:

- **A. Skin-only rework** — two-pane layout with the stock sidebar. No fork to maintain,
  but no one-tap USB buttons and no way to hide unused sidebar features (skins cannot
  filter the sidebar or jump to a named node; `[Library]` controls are relative-only,
  verified in `mixxx/src/library/librarycontrol.cpp`).
- **B. Skin rework + patched Mixxx** — adds two controls that jump the sidebar straight
  to a USB device and re-root it there. Exact Pioneer UX; costs a small maintained patch
  and a custom arm64 build. **Chosen.**
- **C. Skin rework + xdotool click synthesis** — brittle (depends on pixel positions);
  rejected.

## Design

### Browse tab layout (1024×600)

```
topbar (existing tabs, 50px)
┌──────────────┬──────────────────────────────┐
│ USB A  USB B │ TITLE  ARTIST  BPM  KEY TIME │
│ (buttons)    │ track rows, ~48px tall       │
│──────────────│ wide (24px) touch scrollbar  │
│ playlist list│                              │
│ of selected  │                              │
│ USB only     │                              │
├──────┬───────┴───────┬──────────────┬───────┤
│LOAD 1│ deck 1 info   │ deck 2 info  │ LOAD 2│  (~90px strip)
└──────┴───────────────┴──────────────┴───────┘
```

- **Two panes always visible**: playlist pane left (~1/3 width, per approved mockup),
  track table right. The `[Sidebar],sidebar_visible` show/hide toggle is removed.
- **Left pane** = USB A / USB B buttons (~56px tall, Pioneer red active state) above the
  sidebar widget. After pressing a USB button the sidebar shows **only that stick's
  playlist tree** (see patch below) — no Tracks/Auto DJ/Rekordbox clutter.
- **Search box removed** (headless Pi has no keyboard).
- **Bottom strip**: existing mini deck displays retained; big LOAD 1 (deck-1 blue) and
  LOAD 2 (deck-2 red) buttons at the outer edges wired to
  `[Channel1],LoadSelectedTrack` / `[Channel2],LoadSelectedTrack`.
- **QSS**: sidebar font ~18px + padding for ≈44px rows; 24px touch scrollbars;
  Pioneer-blue selection highlight; track table styled to match.
- Track-table row height/font come from Mixxx *Preferences → Library* (skins cannot set
  them); the deploy notes document the recommended values (row height ≈ 48px).
- Overview and Sampler tabs unchanged. Skin minimum size stays compatible with the
  existing manifest.

### Interaction model

1. Tap **USB A** → left pane shows USBA's playlists (tree re-rooted at that device).
2. Tap a playlist → its tracks fill the right pane (stock sidebar-activation behavior).
3. Tap a track row → selects it. Tap **LOAD 1** / **LOAD 2** → loads onto that deck.
   Deliberate two-tap loading; no drag-and-drop needed.
4. Tap the *active* USB button again → sidebar returns to the full stock tree
   (escape hatch for Tracks/History/etc.).
5. DDJ-400 browse knob keeps working: it drives `[Library],MoveVertical` on the focused
   widget; the USB buttons focus the sidebar so the knob scrolls playlists immediately.

### Mixxx patch

Two new push-button controls, created in `LibraryControl`
(`src/library/librarycontrol.cpp`), acting on the bound `WLibrarySidebar`:

- `[Library],goto_usb_a` and `[Library],goto_usb_b`.
- On trigger: locate the Rekordbox feature's child device whose name matches the mount
  directory name (`USBA` / `USBB`, case-insensitive — guaranteed by the Pi's udev mount
  scripts; Mixxx's Rekordbox feature scans `/media`, verified in
  `src/library/rekordbox/rekordboxfeature.cpp`).
- Re-root the sidebar view at that device node (`QTreeView::setRootIndex`), expand it,
  select its first child playlist, and focus the sidebar.
- If the control fires for the device the sidebar is already rooted at, restore the
  full tree (root index reset) — this is the "press again to escape" behavior.
- If the device is not mounted / not found: do nothing (no dialog, no crash).
- Re-rooting must be re-validated when the model changes (USB unplugged while rooted →
  fall back to full tree automatically).

Error handling summary: missing device → no-op; unplug while rooted → auto-restore full
tree; controls absent (unpatched Mixxx) → skin buttons simply do nothing, rest of the
skin still works.

### Build & deploy

1. `apt policy mixxx` on the Pi → exact installed version; patch that source
   (`apt source mixxx`, quilt patch, `dpkg-buildpackage`).
2. Build the `.deb` in GitHub Actions on a free arm64 runner (`ubuntu-24.04-arm`) inside
   a Debian container matching the Pi's OS release; the Pi never compiles.
   Fallback: overnight on-Pi build with swap.
3. Install: `sudo apt install ./mixxx_*.deb`, then `sudo apt-mark hold mixxx` so routine
   upgrades don't replace the patched build. Upgrading Mixxx later = re-run the CI job
   against the new source (patch is small).
4. Skin deploy: copy the Pioneered folder to the Pi's Mixxx skins directory (existing
   `install.linux.sh` flow).

### Testing

- **Skin layout**: run Mixxx 2.5 on the Windows dev machine with the reworked skin;
  verify two-pane layout, row sizes, LOAD buttons (Rekordbox devices can be simulated
  with exported folders on a USB stick / removable drive).
- **Patch**: unit-level check that the controls exist and no-op safely with no device;
  end-to-end on the Pi over VNC: USB A/B jump, playlist tap → tracks, load to both
  decks, unplug-while-rooted recovery, DDJ-400 knob navigation after a USB button press.
- **Regression**: Overview/Sampler tabs unchanged; skin still loads on an *unpatched*
  Mixxx (buttons inert but nothing broken).

## Non-goals

- On-screen keyboard / search.
- Hiding stock sidebar features in the *full* tree view.
- Upstreaming the patch (personal fork; may be proposed upstream later).
- Any change to USB mounting, the Tkinter eject overlay, or the DDJ-400 mapping.
