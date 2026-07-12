# Pi Mixxx build facts (source of truth for the patch + CI)

- Installed package: mixxx 2.5.0 (Debian source package `mixxx_2.5.0+dfsg-3`; arm64 binary in the archive is the binNMU `2.5.0+dfsg-3+b1`)
- OS: Raspberry Pi OS 64-bit, Debian codename: trixie
- Arch: arm64
- Source pool: http://deb.debian.org/debian/pool/main/m/mixxx/
  - Files: `mixxx_2.5.0+dfsg-3.dsc`, `mixxx_2.5.0+dfsg.orig.tar.xz`, `mixxx_2.5.0+dfsg-3.debian.tar.xz` (SHA256 of both tarballs verified against the .dsc)
- Package origin: Debian archive (deb.debian.org), not the Raspberry Pi archive — Raspberry Pi OS arm64 pulls `mixxx` from Debian; archive.raspberrypi.com does not carry it.
- Debian packaging patches (`debian/patches/series`): `0001-disable_soundsourcem4a.patch`, `0002-desktop_file.patch`, `0004-remove_inappropriate_arm_flags.patch`, `0005-disable_soundproxy_test.patch` — **none touch `src/library`**, so our patch applies cleanly on top of them.
- Source tree verified after extraction (in `..\mixxx-src\mixxx-2.5.0`): `src/library/librarycontrol.cpp`, `src/library/librarycontrol.h`, `src/library/library.h` all present.
- Queried: 2026-07-08

> **Caveat:** Installed version 2.5.0 confirmed by user (SSH to the Pi was
> unavailable); Debian codename **trixie** inferred from archive contents —
> packages.debian.org/trixie/mixxx shows `2.5.0+dfsg-3`, and it is the only
> Debian release shipping a 2.5.0 build (bookworm has 2.3.3, sid/forky have
> 2.5.6). **Re-verify with `apt policy mixxx` on the Pi at deploy time
> (Task 7) before installing the built .deb.**

## Patch series (applied in this order by CI)

1. `usb-browse.patch` — touch browse + hold-to-eject (field-verified r8.1)
2. `pdb-corruption-hardening.patch` — PDB segfault fixes (field-verified r8.1)
3. `xdj-behavior.patch` — waveform EQ decoupling, loop from cue, Filter curve
   (shipped r9.1, awaiting field test)
4. `library-ui.patch` (added 2026-07-11) — "Tracks visible in list" zoom
   preference (`[Library] VisibleRows`, default 8), rekordbox lists always
   open sorted by # ascending, Pioneer-style key traffic light vs the master
   deck (master = playing deck that started most recently; green = Camelot
   compatible; keys shown as note names), fixed rekordbox column set
   (#, Title, Artist, Key, Duration) with proportional widths filling the
   viewport (r13).
5. `xdj-hardware.patch` (added 2026-07-11, r14) — rekordbox-style red bar
   markers on the waveform beatgrid (importer anchors the grid on the first
   beat numbered "1"); controller auto-reconnect watchdog (PortMidi error
   counting + 5 s rescan/reopen of enabled devices, incl. plug-in after
   startup); DDJ-400 mapping jumps deck tempo to the physical fader position
   on track load (200 ms after load, then soft takeover resumes).
6. `search-osk.patch` (added 2026-07-12) — track Search tab replacing the
   Sampler tab. Adds `WSearchLineEdit::slotSetSearchText()` (sets text and
   re-runs the search, which `slotRestoreSearch()` does not) and
   `[Library],search_key_a..z` / `search_key_0..9` / `search_space` /
   `search_backspace` push controls, so the skin's on-screen QWERTY keyboard
   drives the native search box over the selected folder. Clearing reuses the
   existing `[Library],clear_search`. Touches `src/widget/wsearchlineedit.{h,cpp}`
   and `src/library/librarycontrol.{h,cpp}`.
