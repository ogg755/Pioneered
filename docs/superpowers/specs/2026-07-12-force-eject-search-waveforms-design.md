# Force eject, Search-page waveforms, lock feedback — design spec

**Date:** 2026-07-12
**Status:** Approved by user (pre-implementation)
**Delivery:** New `mixxx-patch/usb-force-eject.patch` (7th patch in the CI series) + skin changes in the Pioneered repo. Built and deployed through the existing GitHub Actions → pi-deploy pipeline. Follows r16 (track search + OSK, field-verified).

## Problem

Three usability gaps found in field use of r16:

1. A stick with a deck playing from it cannot be ejected at all — the 5s hold just shows "USB LOCKED". There is no operator override for pulling a stick regardless.
2. The Search page has no deck waveform overviews (the Browse tab's bottom deck row was not carried over), so the operator loses sight of both decks while searching.
3. Two locks are silent or cryptic: pressing LOAD on a playing deck does nothing (Mixxx's guard silently rejects it), and the "USB LOCKED" eject banner doesn't say what to do about it.

## Scope

### 1. Force eject — hold 10s (C++, `src/library/librarycontrol.cpp` + `.h`)

Two-tier hold on the USB A/B buttons (existing machinery: `slotUsbButtonPress/Release`, `slotHoldFlashTick`, `finishHoldEject`, `m_holdElapsed`, `m_holdFlashTimer`):

- **600ms–5s released:** cancelled, no action (unchanged).
- **At 5s, stick not in use:** eject (unchanged).
- **At 5s, deck playing from stick:** show the locked banner, but **keep the hold alive** — do not stop the flash timer or clear `m_holdUsb`. Flash continues at the fast cap (80ms).
- **At 10s (still holding):** force eject. Set `[ChannelN],play = 0` for every deck playing a track from that stick, then run the existing `startEject()` path (it already unloads now-paused decks via `unloadDecksFromUsb()` and retries `umount` through EBUSY while the caching reader closes files asynchronously).
- **Released between 5s and 10s:** cancelled, no action (mirrors the 600ms–5s rule).

The playing-deck stop is a deliberate hard stop — audio on that channel goes silent. User accepted this ("stop deck, then eject").

### 2. Waveforms on the Search page (skin only)

- Extract the Browse tab's bottom row from `library.xml` (the 90f `Decks` WidgetGroup: `LOAD 1 | deck.xml ch1 | UsbBanners | deck.xml ch2 | LOAD 2`) into a new shared `templates/decks_row.xml`.
- `library.xml` references the template (structure unchanged, DRY).
- `search.xml` replaces its bare `SearchLoadRow` (44f, LOAD buttons only) with the same template. Search gains both deck overview waveforms and the banner stack. `deck.xml`/`<Overview>` widgets are plain templates (not singletons) — multiple instances per channel are normal in Mixxx skins (the Overview tab already duplicates them).
- Height cost when the keyboard is up: results list shrinks by ~46px. Accepted trade-off.

### 3. Lock feedback messages (C++ + skin)

- **Load block:** in `LibraryControl::slotLoadSelectedTrackToGroup`, when the target deck is playing and the effective config rejects loading onto a playing deck (Mixxx's own guard in `WTrackTableView::loadSelectedTrackToGroup` — honour the same settings: `[Controls],LoadWhenDeckPlaying` with fallback to legacy `[Controls],AllowTrackLoadToPlayingDeck`), fire a new banner control `[Library],load_blocked` through the existing 2s `showBanner()` machinery. If the config allows the load (Allow / AllowButStopDeck), no banner. Skin: new label in the banner stack, text **"PAUSE DECK TO LOAD"**.
- **Eject lock banner reword (skin text only):** `UsbLockedBanner` text becomes **"PLAYING FROM USB — PAUSE TO EJECT, KEEP HOLDING TO FORCE"**, word-wrapped in the 150f banner column (`qproperty-wordWrap: true` in `style.qss`; smaller font so three wrapped lines fit the 90f row).

## Non-goals

- No change to the short-press browse toggle or the 600ms/5s thresholds.
- No confirmation dialog for force eject — the 10s hold *is* the confirmation.
- No per-deck message text ("PAUSE DECK 1…"); the operator just pressed a specific LOAD button, context is obvious.
- No waveform scrolling/zoom on the Search page — the deck row is the same overview widget Browse uses.
- No change to Mixxx's load-guard behaviour itself — we only add feedback when it rejects.

## Architecture notes

- **Mixxx source (`mixxx-src/mixxx-2.5.0`):** `src/library/librarycontrol.{h,cpp}` only.
  - New member `std::unique_ptr<ControlPushButton> m_pLoadBlocked` (banner control, pattern of `m_pUsbLocked`).
  - New private helper `stopDecksPlayingFromUsb(int usbIndex)` (sets `play=0` on matching decks).
  - `slotHoldFlashTick()` gains the second tier: at ≥5s locked → banner once + continue; at ≥10s → `stopDecksPlayingFromUsb()` + `startEject()`. `slotUsbButtonRelease()` in the 5–10s window cancels (existing release path already stops the timer and clears state — verify it needs no change).
  - `slotLoadSelectedTrackToGroup()` gains the reject-detection + `showBanner(m_pLoadBlocked.get())`.
- **Skin (Pioneered repo):** new `templates/decks_row.xml`; `library.xml` and `search.xml` reference it; `UsbLockedBanner` text reword; new `LoadBlockedBanner` label bound visible to `[Library],load_blocked`; `style.qss` word-wrap + font sizing for the banner column.
- **Patch generation:** same baseline-snapshot → `git diff --no-index` → `patch -p1 --dry-run` workflow. Baseline for `librarycontrol.{h,cpp}` is the current canonical tree state (r16, all six patches applied).
- **CI:** append `usb-force-eject.patch` after `search-osk.patch` in `build-mixxx-deb.yml`; document as patch 7 in `VERSION.md`.
- **Backward compatibility:** on an unpatched Mixxx the skin still loads; `LoadBlockedBanner` binds to a nonexistent control and simply never shows; the reworded USB LOCKED text is inert.

## Error handling / edge cases

- **Release during 5–10s window:** no action (verify existing release path handles >5s elapsed without side effects).
- **Track ends naturally during the 5–10s window:** at the 10s tick the deck is no longer playing; `stopDecksPlayingFromUsb()` finds nothing to stop; normal eject path runs. Fine.
- **Force eject with umount still failing after retries:** existing "EJECT FAILED" banner shows (unchanged retry/backoff logic).
- **Load blocked while a banner is already showing:** `showBanner()` already replaces the current banner (verify; if it stacks oddly, last-writer-wins is acceptable).
- **`slotLoadSelectedTrackToGroup` on preview deck:** guard only applies to `[ChannelN]` decks (preview deck loads are always allowed by Mixxx) — banner logic must skip preview groups, matching `WTrackTableView`.

## Testing / verification

- **Patch:** `patch -p1 --dry-run` clean against baseline; CI build green.
- **Dev-machine smoke test:** skin loads; Search page shows both deck overviews + LOAD buttons + banner column; Browse unchanged.
- **Field checks on the Pi (r17):**
  1. Play a track from USB A, hold USB A: at 5s the reworded locked banner shows and flashing continues; keep holding — at 10s the deck stops and the stick ejects. Safe to pull.
  2. Same but release at ~7s: nothing ejects, deck keeps playing.
  3. Eject a stick with nothing playing: unchanged 5s behaviour.
  4. Press LOAD 1 while deck 1 is playing: "PAUSE DECK TO LOAD" banner for 2s, track not loaded. Pause deck 1, LOAD 1 again: loads.
  5. Search page shows live waveform overviews for both decks; banners appear there too.
