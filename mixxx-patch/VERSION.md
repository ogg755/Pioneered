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
   (shipped r9.1, awaiting field test). r23 (2026-08-14) also pins the overall
   waveform amplitude: `WaveformWidgetRenderer::onPreRender` sets `m_gain = 1.0`
   instead of reading `[ChannelN],total_gain`, so the channel gain/trim knob and
   replaygain no longer scale the waveform height — it is drawn at a fixed scale
   reflecting the track's content, like Pioneer hardware. total_gain still drives
   the audio path; the /2 EnginePregain compensation via `getGain()` is retained.
   Touches `src/waveform/renderers/waveformwidgetrenderer.cpp`.
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
12. `system-menu.patch` (added 2026-08-04) — on-screen settings menu behind a
    cog in the topbar. `LibraryControl` gains `[Library],menu_power`,
    `menu_restart`, `menu_disarm` (push, 1 on press / 0 on release) and the
    display controls `arm_power` / `arm_restart`, which drive the skin's red
    "TAP AGAIN TO …" button faces. First press arms, second commits; arming
    one option disarms the other, BACK and the cog press `menu_disarm`, and a
    5 s single-shot timer disarms both so a menu left open never leaves a live
    one-tap kill on screen. Restart reuses `triggerRestart()` from
    `hold-to-restart.patch` — one implementation, two entry points. Power off
    runs `systemctl poweroff || sudo -n poweroff || sudo -n shutdown -h now`
    via `QProcess` (logind/polkit normally grants a local session this with no
    sudo rule; the fallback is the same passwordless sudo the USB eject uses),
    showing `[Library],powering_off` and, if every route is refused,
    `power_off_failed`. Note `systemctl` returns 0 as soon as the job is
    queued, so exit 0 means "accepted", not "finished". Touches
    `src/library/librarycontrol.{h,cpp}`.
    Skin side (same release): new `settings.xml` panel template, `topbar.xml`
    (expanding `TabSpacer` + `SettingsCog`, so the cog pins to the corner and
    the tabs keep their rendered width), `skin.xml` (`SettingsOverlay` — the
    one overlay deliberately *not* `TransparentForMouseEvents`, which is what
    makes it modal — plus the two new banners and the `[Skin],show_settings`
    attribute), `style.qss`.

    Both CI workflows apply the series above. `publish-release.yml` had
    silently drifted, applying only patches 1-9 — releases cut from it shipped
    without the headphone gain ceiling or hold-to-restart. Resynced with
    `build-mixxx-deb.yml` in the same commit as this patch.
13. `perf-render-repaint.patch` (added 2026-08-13) — responsiveness pass over
    the hot paths the patches above introduced. No controls, no config keys,
    no observable behaviour change:
    * Waveform bar markers: the downbeat X list becomes a reused member
      instead of a QVector reallocated on every `draw()`; the two
      `drawPolygon()` calls per downbeat collapse into one reused
      `QPainterPath` filled with a single `drawPath()`; and `it - firstMarker`
      is computed once before the loop rather than per beat —
      `mixxx::Beats::const_iterator` is not guaranteed random-access, so
      `operator-` can degrade to an O(n) `std::distance()`, making that loop
      O(n²) per frame. The allshader/QOpenGL renderer gets the same iterator
      fix plus a `reserve()` on its downbeat vertex buffer.
    * Key traffic light: the refresh emitted `dataChanged` over the whole
      `rowCount() × columnCount()` rectangle on every deck play/pause and
      master-deck track change — i.e. continuously during a mix, through the
      sort/filter proxy, over playlists of thousands of rows. Only the Key
      column is invalidated now.
    * `KeyUtils::guessKeyFromText()` ran once per Key cell per repaint, and a
      second time in `roleValue()` for the displayed note name. Both share a
      memoized text→`ChromaticKey` hash on `XdjMasterKeyTracker`.
    * The visible-rows zoom and the fixed column layout both re-applied their
      derived values from inside `resizeEvent()`, and `setFont()` /
      `setDefaultSectionSize()` / `setColumnWidth()` each relayout the header
      and repaint the viewport. Both early-out when the derived numbers are
      unchanged, with explicit invalidation where the guard cannot see the
      change (a new base font, a newly loaded model).
    * The controller reconnect watchdog rescanned PortMidi + HID every 5 s
      *forever* when a controller was enabled in the preferences but absent.
      The first three attempts stay at 5 s so replugging still reconnects
      promptly, then the interval doubles to a 60 s ceiling and resets once
      everything enabled is open. Touches
      `src/waveform/renderers/waveformrenderbeat.{h,cpp}`,
      `src/waveform/renderers/allshader/waveformrenderbeat.cpp`,
      `src/library/basetracktablemodel.cpp`,
      `src/widget/wlibrarytableview.{h,cpp}`,
      `src/widget/wtracktableview.{h,cpp}`,
      `src/controllers/controllermanager.{h,cpp}`.
14. `usb-browse-one-tap.patch` (added 2026-08-13) — USB A/B navigates on the
    **first** press. The rekordbox device list only refreshes on activation, so
    a press on a freshly inserted stick used to kick off the async
    `QtConcurrent` device scan, return empty-handed, and do nothing visible;
    only a second press found the device. A press that cannot find its device
    now records the slot in `m_pendingUsb` and completes itself from the
    sidebar model's `rowsInserted`/`modelReset` signal when the scan lands. The
    retry deliberately does **not** re-prime the scan (that would restart it on
    every batch of inserted rows); a new press, an eject or a root restore
    supersedes the pending request; a 10 s single-shot timeout drops a request
    for a stick that never appears; and a pending request whose slot is already
    rooted is discarded rather than toggling the sidebar back off.
    Also stops discarding the tap that lands while a PDB parse is in flight —
    `activateChild()` queued behind a running parse used to be dropped with
    only a warning, which on a slow stick is seconds of UI that ignores you.
    The activation is stored as a `QPersistentModelIndex` and re-dispatched
    from `onTracksFound()` through the event loop, taken out of the queue slot
    *before* the future result is unwrapped so a failed parse releases it
    instead of wedging it. Touches `src/library/librarycontrol.{h,cpp}` and
    `src/library/rekordbox/rekordboxfeature.{h,cpp}`.
    Skin side (same release): `style.qss` only — button modernisation
    (consistent 3/4/8px radius tiers, `qlineargradient` fills so buttons read
    as moulded hardware, a dimmed border/inactive-chrome ladder, and a
    `:pressed` face on every button so a touch is acknowledged on touch-down
    instead of when the action lands). The Pioneer palette, the tab strip's
    proportions and the CDJ notch on `#WaveformInfo_Header` are unchanged.
    Note the `:pressed` rules for the USB, LOAD and sampler buttons are scoped
    to `[value="0"]`: a bare `:pressed` stays active for a whole hold and
    would outrank the `[value]` rules that drive the eject and
    hold-to-restart flashes, hiding them.
15. `beatgrid-ticks.patch` (added 2026-08-15, r24) — restyles the rekordbox
    beatgrid overlay from `xdj-hardware.patch` to the Pioneer CDJ/XDJ look.
    Every-beat marks become short ticks at the top and bottom edges instead of
    full-height lines, and the bar-start (downbeat) markers become thin red
    vertical bars top and bottom instead of large red triangles/arrows. Both
    the software (QPainter) and allshader (QOpenGL) renderers are changed in
    lock-step. Software: the top tick stays in `m_beats`, a new `m_beatsBottom`
    holds the bottom tick, and the downbeat `QPainterPath` draws `addRect`
    bars rather than triangles. Allshader: the top tick stays in `m_vertices`
    (so its `reserved`/`DEBUG_ASSERT` vertex count is unchanged), a new
    `m_beatBottomVertices` buffer holds the bottom tick (own draw pass, beat
    colour), and the two downbeat triangles become two rectangles (downbeat
    reserve doubles, 6→12 vertices per bar). Size is controlled by two named
    constants per renderer: `kBeatTickFraction` (tick/bar height as a fraction
    of the waveform height) and `kBarHalfWidth` (red bar half-width, px).
    Applied after `perf-render-repaint.patch`, on top of its batched
    `QPainterPath` / reused-member draw path. Touches
    `src/waveform/renderers/waveformrenderbeat.{h,cpp}` and
    `src/waveform/renderers/allshader/waveformrenderbeat.{h,cpp}`.
