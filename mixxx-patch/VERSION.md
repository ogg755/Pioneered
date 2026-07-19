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
7. `usb-force-eject.patch` (added 2026-07-12) — two-tier USB hold: at 5s a
   locked stick shows the explanatory banner and the hold continues; at 10s
   playing decks on that stick are stopped and the eject runs regardless.
   Also adds `[Library],load_blocked`, set by WTrackTableView when a load is
   silently rejected because the target deck is playing (skin shows
   "PAUSE DECK TO LOAD"). Touches `src/library/librarycontrol.{h,cpp}`,
   `src/widget/wtracktableview.cpp`.
8. `rekordbox-import-fixes.patch` (added 2026-07-17) — two upstream backports:
   (a) ANLZ cue/loop comments decoded as UTF-16**BE** (they were decoded LE,
   turning ASCII labels into CJK mojibake on the waveform; upstream
   d96cae92ca, fixes mixxx#14789); (b) PDB page header's row count is really
   a 13-bit `num_rows` + 11-bit `num_rows_valid` bitfield — the old
   `num_rows_small`/`num_rows_large` heuristic undercounted rows on pages
   with many small rows, so playlists imported with most/all entries missing
   (upstream 2144bf9075, PR mixxx#15745). Touches
   `src/library/rekordbox/rekordboxfeature.cpp`,
   `lib/rekordbox-metadata/rekordbox_pdb.{cpp,h}`.
9. `banner-overlay-transparency.patch` (added 2026-07-19, r20) — skin parser
   gains an optional `<TransparentForMouseEvents>true</...>` node on any
   widget, setting `Qt::WA_TransparentForMouseEvents`. The full-screen popup
   banner overlays use it so that showing a banner over the held USB button
   no longer sends the button a Leave event (WPushButton fakes a mouse
   release on Leave, which cancelled the 5-10s force-eject hold), and so
   visible banners don't swallow touches. Also bumps the banner clear timer
   2s -> 3s for readability. Touches `src/skin/legacy/legacyskinparser.cpp`,
   `src/library/librarycontrol.cpp`.
10. `headphone-gain-ceiling.patch` (added 2026-07-19) — raises the cue/PFL
    headphone gain ceiling from +14 dB to +30 dB (`[Master],headGain`). The
    DDJ-400 cue out (ch 3-4) maxed out far too quiet on the Pi; an aplay
    -6 dBFS bypass tone straight to hw ch 3-4 (Mixxx out of the loop) was
    loud and clean, exonerating the DAC/ALSA/format/PortAudio path and
    proving ~20 dB of clean headroom the +14 dB stage could not reach.
    Audio-taper pot, so unity stays at knob centre; only the top extends.
    Touches `src/engine/enginemixer.cpp`. If the physical HEADPHONES LEVEL
    knob is re-mapped to headGain, scale it to the new x31.6 max.
11. `hold-to-restart.patch` (added 2026-07-19) — keyboard-free recovery:
    holding either on-screen LOAD button for 7 s restarts Mixxx. The skin's
    LOAD buttons press `[Library],restart_hold_1/2` alongside
    `LoadSelectedTrack` (which still loads on press, unchanged);
    `LibraryControl` runs the hold with the same accelerating 250→80 ms
    flash as the USB eject hold (display control `[Library],load_flash_1/2`,
    0 normal / 1 flash-white), shows a `[Library],restarting` banner
    ("RESTARTING MIXXX…"), then `QProcess::startDetached`s a `/bin/sh`
    helper that survives the kill: `killall mixxx` (SIGTERM, clean library
    flush), up to 10 s wait, `killall -9` fallback, then relaunches with
    the original binary path + argv (quoted), exporting `DISPLAY=:0` if
    unset. Releasing before 7 s cancels; the first 600 ms never flash so
    normal load taps don't flicker. Only recovers *soft* hangs — if the Qt
    event loop is fully wedged the button can't fire (an external watchdog
    would be needed for that). Touches `src/library/librarycontrol.{h,cpp}`.
    Skin side (same release): `templates/load_button.xml` (2 states + new
    connections), `style.qss` (white flash + banner style), `skin.xml`
    (RestartingBanner overlay).
