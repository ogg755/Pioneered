# Library UI rework — design spec

**Date:** 2026-07-11
**Status:** Approved by user (pre-implementation)
**Delivery:** New `mixxx-patch/library-ui.patch` (4th patch in CI series) + `style.qss` skin tweaks in the Pioneered repo. Built and deployed through the existing GitHub Actions → pi-deploy pipeline.

## Problem

The track list in the Pioneered skin is too small to use on the console's small touch display. Sorting defaults are wrong for USB browsing (user must tap the tiny `#` header), the column set is cluttered, and there is no Pioneer-style key compatibility ("traffic light") indication against the master deck.

## Scope

Four changes, all to Mixxx 2.5.0 (patched apt source at `mixxx-src/mixxx-2.5.0`) unless noted:

### 1. "Tracks visible in list" preference

- New spinner in Preferences → Library: **Tracks visible in list**, range 4–20, default 8, plus an "off" position (value below range / checkbox) that falls back to the existing manual `[Library] RowHeight` behaviour.
- Stored as `[Library] VisibleRows` in the config.
- When active, the library track table computes `rowHeight = viewportHeight / N` on every resize/show, applies it, and scales the table font to ~45% of the row height (true zoom: rows and text grow together).
- Changes apply live from the preferences dialog, matching the existing row-height control's live-preview behaviour.
- Guard: if the viewport reports zero/invalid height (first paint), skip and reapply on the next resize event.

### 2. Default sort: track number (#) ascending

- Root cause found: `RekordboxPlaylistModel` (used for **both** rekordbox device track lists and playlists — everything goes through `setPlaylist()`) declares POSITION as its default sort column via `setDefaultSort()` but never calls `setSort()`, so the view keeps whatever stale sort the saved header state has. (Compare `bansheeplaylistmodel.cpp:241-242`, which calls both.)
- Fix: apply position-ascending sort whenever a rekordbox playlist / device track list is activated.

### 3. Traffic-light key display

- **Master deck definition (user's rule):** the currently *playing* deck that started playing most recently, i.e. has been playing for the least wall-clock time. Implemented by a small tracker that watches each deck's `play` control and timestamps 0→1 transitions. If no deck is playing, there is **no master and no highlighting** (user's explicit choice — lights go out on full stop; nothing on startup).
- **Highlight rule:** in the track table, a row's **Key cell** gets a green background when its key is Camelot-compatible with the master track's key: same key, relative major/minor, or ±1 Camelot step — exactly `KeyUtils::getCompatibleKeys()`. Single tier: green or nothing (no amber).
- **Refresh:** the table repaints the key column when the master deck or its track/key changes.
- **Key display notation:** key text from the USB stick is parsed (`KeyUtils::guessKeyFromText`) and rendered as musical note names (Am, A♯m, D♯ …) — *not* Camelot numbers — regardless of the notation exported by rekordbox. Unparseable key strings display verbatim and never highlight.
- Green colour defined in `style.qss` where possible; hard fallback in code.

### 4. Column set

- The rekordbox track table shows exactly: **#, Title, Artist, Key, Duration**.
- Other columns are removed/hidden for `RekordboxPlaylistModel` (hard-coded for this appliance rather than relying on per-user saved header state; this also neutralises the stale header state from item 2).

## Non-goals

- No on-screen zoom buttons in the skin (considered, declined — preferences spinner only).
- No changes to Mixxx's local library views or other external library features; scope is the rekordbox/USB browsing path plus the shared table-view row-height machinery.
- No changes to Mixxx's sync-master/leader concept — "master" here is a new, independent notion used only for key highlighting.

## Architecture notes

- **Files expected to change (Mixxx source):**
  - `src/preferences/dialog/dlgpreflibrary.{h,cpp}` + `dlgpreflibrarydlg.ui` — new spinner, `[Library] VisibleRows` config plumbing.
  - `src/widget/wlibrarytableview.{h,cpp}` and/or `src/widget/wtracktableview.{h,cpp}` — visible-rows row-height computation on resize; key-cell repaint hook.
  - `src/library/rekordbox/rekordboxfeature.cpp` (`RekordboxPlaylistModel`) — apply default sort on activate; column set; key display notation.
  - `src/library/baseexternalplaylistmodel.cpp` / `src/library/basetracktablemodel.cpp` — Qt::BackgroundRole for the key column driven by the master-key tracker.
  - New small helper (e.g. `src/library/masterkeytracker.{h,cpp}` or equivalent) — watches deck `play` controls, exposes current master track key, emits change signal. Owned where `Library`/`PlayerManager` wiring allows.
- **Skin (Pioneered repo):** `style.qss` — green highlight colour, any row/padding adjustments.
- **Patch generation:** same gen-script/diff-against-2.5.0-baseline workflow as the existing three patches; LF line endings in the source tree, normalize CRLF before local `git apply`.
- **Patch order in CI:** usb-browse → pdb-corruption-hardening → xdj-behavior → **library-ui** (append to `build-mixxx-deb.yml`).

## Error handling

- Zero/invalid viewport height → defer row-height computation to next resize.
- Track with missing/unparseable key → display raw text, never highlighted.
- Master deck's own track lacking a valid key → no highlighting (equivalent to no master).
- `VisibleRows` off/absent → behaviour identical to stock Mixxx (existing RowHeight setting governs).

## Testing / verification

- Build via `build-mixxx-deb.yml` on the ogg755/Pioneered fork; version auto-bumps `+usbbrowse.r<N>`.
- Stage debs in `Code\pi-deploy\`, install per `docs/pi-deploy.md`.
- Field checks on the Pi:
  1. Preferences → Library shows the spinner; changing it visibly resizes rows+font live; persists across restart.
  2. Opening any USB playlist / device track list sorts by # ascending without touching the header.
  3. Columns are exactly #, Title, Artist, Key, Duration.
  4. Keys render as note names. Play deck 1 → its key's compatible rows go green; start deck 2 (later) → master switches to deck 2 and highlights update; pause both → all highlights clear.
