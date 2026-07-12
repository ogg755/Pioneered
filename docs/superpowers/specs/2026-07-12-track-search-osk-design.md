# Track search + on-screen keyboard — design spec

**Date:** 2026-07-12
**Status:** Approved by user (pre-implementation)
**Delivery:** Skin changes in the Pioneered repo (topbar, new Search page + keyboard, `style.qss`) plus a new `mixxx-patch/search-osk.patch` (6th patch in the CI series). Built and deployed through the existing GitHub Actions → pi-deploy pipeline.

## Problem

The Pioneered skin has no way to search for a track on the console's touch display. A DJ browsing a large USB folder must scroll the whole list. Mixxx has a capable native search box (filters the currently selected library view), but it is not surfaced in this skin and cannot be driven without a physical keyboard. The console is touch-only, so we need an on-screen keyboard, themed to match the OEM Pioneer look.

## Behaviour

- The topbar's third tab, currently **Sampler**, becomes **Search**.
- Tapping **Search** switches to a new Search page with the on-screen keyboard already visible.
- Keys drive Mixxx's **native search box**, which filters whatever folder the sidebar had selected in the Browse tab (USB A/B, playlist, etc.). This is exactly "search the selected folder" — no new search logic.
- Results filter live as the user types.
- A **Done** key collapses the keyboard so the results list gets full height; tapping the search field re-shows the keyboard.
- Select a row and press **LOAD 1 / LOAD 2** to load to a deck — the same `[ChannelN],LoadSelectedTrack` mechanism the Browse tab uses.

## Scope

Two deliverables, mirroring the established skin + patch-via-CI pattern.

### A. Skin (Pioneered repo)

- **`topbar.xml`** — replace the Sampler tab template instance with a Search tab (`tab_name` → `Search`, `config_key` → `search`).
- **`skin.xml`** — in the `WidgetStack`, replace the Samplers `SingletonContainer` (trigger `[Tab],samplers`) with a new Search singleton triggered by `[Tab],search`. The 16 samplers still exist internally (`[Master],num_samplers` unchanged) — they simply lose their topbar tab, per the user's "replace the Sampler button" request. The `Samplers_Singleton` definition and `samplers.xml` may remain in the tree unused, or be removed; removal is preferred if nothing else references them.
- **New `search.xml`** — the Search page (layout below). Contains the native `<SearchBox>` widget (this is what binds `WSearchLineEdit` to `LibraryControl` so the patch controls have a target), a native `<Library>` results table, LOAD 1 / LOAD 2 buttons, and an embedded `keyboard.xml`.
- **New `keyboard.xml`** — the QWERTY + numbers on-screen keyboard, one `PushButton` per key.
- **`style.qss`** — OEM theming for the keys, search field, and Done/space/backspace, reusing the existing Pioneer palette (accent `#b6294c`, dark `#32323c`).

### B. Mixxx patch (`mixxx-patch/search-osk.patch`, 6th in CI order)

- `LibraryControl` already owns `m_pSearchbox` (a `WSearchLineEdit*`, bound automatically by `LibraryControl::bindSearchboxWidget()` when the skin contains a `<SearchBox>`). `WSearchLineEdit` exposes `QString getSearchText() const` and `void slotRestoreSearch(const QString& text)` (sets text **and** triggers the search).
- Add `[Library]` `ControlPushButton`s, one per typed character: `search_key_a` … `search_key_z` and `search_key_0` … `search_key_9`, plus `search_space` and `search_backspace`.
- Each key handler: read `m_pSearchbox->getSearchText()`, append the mapped character (or `" "` for space, or chop the last character for backspace), call `m_pSearchbox->slotRestoreSearch(newText)`.
- **Clear** reuses the existing `[Library],clear_search` control — no new control needed.
- Register the character controls via a loop over a character list (~15 lines) rather than 38 hand-written blocks. Guard every handler with `VERIFY_OR_DEBUG_ASSERT(m_pSearchbox)`, matching the existing search-history handlers.

## Search page layout (min screen 480×420; topbar is 50f, leaving ~370f)

```
┌────────────────────────────────────────────┐
│ [ Overview ] [ Browse ] [ Search* ]        │ topbar 50f
├────────────────────────────────────────────┤
│  🔍 [ search text field (SearchBox) ][ X ] │ ~40f
├────────────────────────────────────────────┤
│  Track results (native Library table,      │
│  filtered live; tap a row to select)       │ flex
├────────────────────────────────────────────┤
│ [ LOAD 1 ]                        [ LOAD 2 ]│ ~44f
├────────────────────────────────────────────┤
│  1 2 3 4 5 6 7 8 9 0                        │
│  Q W E R T Y U I O P                        │ keyboard
│  A S D F G H J K L                          │ ~150f
│  Z X C V B N M  [⌫]  [ space ]  [ Done ]   │ (toggles)
└────────────────────────────────────────────┘
```

- Keyboard visibility is a **skin-only** toggle: a `[Skin],show_keyboard` control (default 1 on the Search page) bound to the keyboard group's `visible` property. **Done** sets it to 0; tapping the search field sets it to 1. No C++ for the toggle.
- At ~480px width the 10-key rows put keys around ~40px wide — tappable but snug. This is the accepted tradeoff for full OEM (QWERTY) fidelity over a letters-only layout.

## Non-goals

- No new search *logic* — we reuse Mixxx's native search, which already scopes to the selected sidebar item.
- No folder switching on the Search page (no USB A/B buttons there) — search operates on whatever was selected in Browse. Maximises room for results + keyboard.
- No symbol/punctuation keys beyond space (letters, digits, space, backspace, clear only). Track search rarely needs punctuation; can be added later if a field need appears.
- No changes to the samplers feature itself — only its topbar tab is removed.
- No shift/caps: search is case-insensitive, so a single (lower) case set is sufficient.

## Architecture / files expected to change

- **Skin (Pioneered repo):** `topbar.xml`, `skin.xml`, new `search.xml`, new `keyboard.xml`, `style.qss`. Optional removal of `samplers.xml` / `sampler.xml` and the samplers singleton if unreferenced.
- **Mixxx source (`mixxx-src/mixxx-2.5.0`):** `src/library/librarycontrol.cpp` and `src/library/librarycontrol.h` — new key controls and their handlers, stored in a container member (e.g. `std::vector<std::unique_ptr<ControlPushButton>>`) plus dedicated space/backspace members.
- **Patch generation:** same baseline-snapshot workflow as the existing patches — snapshot the to-be-edited files to a baseline dir, edit the canonical tree, `git diff --no-index` with `a/`,`b/` path rewrite, verify with `patch -p1` dry-run against the baseline copy. Source tree is LF; normalise CRLF before local `git apply`.
- **CI:** append `search-osk.patch` to the patch list in `.github/workflows/build-mixxx-deb.yml` (order: usb-browse → pdb-corruption-hardening → xdj-behavior → library-ui → xdj-hardware → **search-osk**) and record it in `mixxx-patch/VERSION.md`. Version auto-bumps `+usbbrowse.r<N>` as usual.

## Error handling / edge cases

- **Unpatched Mixxx must still load the skin.** The key `PushButton`s bind to `[Library],search_*` controls that won't exist without the patch; Mixxx treats unknown skin control connections as inert (no crash), so the Search page still renders and the keyboard is simply non-functional. The keyboard-visibility toggle is pure skin and always works.
- **Empty search text:** `getSearchText()` may return placeholder/disabled text when the box is empty (`kDisabledText`). Backspace on an empty string must be a no-op; appending to an empty box must start a real query, not concatenate onto the placeholder. Handle explicitly in the patch and cover with tests.
- **Backspace at length 0:** no-op.
- **No searchbox bound** (defensive): handlers assert `m_pSearchbox` and return, as the existing history/clear handlers do.

## Testing / verification

- **Patch unit logic (TDD):** append, space, backspace, clear, empty-string start, backspace-at-zero, and placeholder-text handling for the text-mutation helper.
- **Skin/layout (dev machine):** run patched Mixxx 2.5 on Windows — verify the topbar shows Search (not Sampler); tapping it opens the Search page with the keyboard up; typing filters the list live; Done hides the keyboard and the list expands; tapping the field restores it; LOAD 1/2 load the selected row; Clear empties the box.
- **Patch apply:** `patch -p1` dry-run against the baseline copy passes cleanly.
- **Build/deploy:** `build-mixxx-deb.yml` on ogg755/Pioneered (`--ref master`); stage debs in `Code\pi-deploy\`; install per `docs/pi-deploy.md`.
- **Field checks on the Pi:**
  1. Topbar third tab reads **Search**; Sampler tab is gone.
  2. Select a USB folder in Browse, switch to Search, type — the list filters to matches within that folder.
  3. Load a searched track to each deck via LOAD 1 / LOAD 2.
  4. Done/reshow keyboard toggle works; Clear resets the search.
