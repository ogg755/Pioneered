# Force eject, Search waveforms, lock feedback — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 10s USB-button hold force-ejects (stopping playing decks), the Search page regains deck waveform overviews, and both silent locks (load-on-playing-deck, eject-while-playing) show explanatory banners.

**Architecture:** New `mixxx-patch/usb-force-eject.patch` (7th in CI order) extends the existing hold-to-eject state machine in `LibraryControl` with a second 10s tier and adds a `[Library],load_blocked` banner control set by `WTrackTableView` at its existing silent-reject point (single source of truth for the load guard; the banner clear timer is reused via a `valueChanged` connection). Skin: the Browse tab's bottom deck row is extracted to a shared `templates/decks_row.xml` used by both Browse and Search pages; banner labels reworded/added.

**Tech Stack:** C++/Qt (Mixxx 2.5.0), Mixxx legacy XML skins + QSS, `git diff --no-index` patch generation, GitHub Actions, `gh` CLI.

## Global Constraints

- **Mixxx source tree:** `../mixxx-src/mixxx-2.5.0` (canonical, all 6 existing patches incl. search-osk applied). Files are **LF**.
- **Patch generation:** snapshot to-be-edited files to a baseline dir *before* editing; `git diff --no-index baseline/ tree/` with `a/` prefix rewrite; verify `patch -p1 --dry-run` against a fresh baseline copy.
- **No local Mixxx build** — compilation gated by CI; runtime verified on the Pi. Watch for private-member access (r15 lesson: text logic belongs on the widget that owns the private getter).
- **Backward compatibility:** skin must load on unpatched Mixxx; `LoadBlockedBanner` binds to a control that won't exist → never shows, never fatal.
- **CI patch order (fixed):** … → library-ui → xdj-hardware → search-osk → **usb-force-eject** (new, last).
- **Hold tiers (exact):** <600ms browse toggle; 600ms–5s release = cancel; 5s stick free = eject; 5s stick in use = banner + hold continues (flash at 80ms cap); 10s = force (stop playing decks from stick, then eject); release 5–10s = cancel.
- **Banner texts (exact):** eject lock = `PLAYING FROM USB — PAUSE TO EJECT, KEEP HOLDING TO FORCE`; load block = `PAUSE DECK TO LOAD`.
- **`gh` CLI:** `C:\Program Files\GitHub CLI\gh.exe`, push remote is `fork` (ogg755/Pioneered), workflow runs need `--ref master`.

---

## File map

**Mixxx source (patched into `usb-force-eject.patch`):**
- `src/library/librarycontrol.h` — new members `m_holdLockedBannerShown`, `m_pLoadBlocked`; helper decl `stopDecksPlayingFromUsb(int)`; remove `finishHoldEject(int)` decl.
- `src/library/librarycontrol.cpp` — two-tier `slotHoldFlashTick()`; flag reset in `slotUsbButtonPress()`; `stopDecksPlayingFromUsb()`; remove `finishHoldEject()`; `m_pLoadBlocked` registration + timer connection; `clearBanners()` clears it.
- `src/widget/wtracktableview.cpp` — one `ControlObject::set` at the silent-reject point in `loadSelectedTrackToGroup()`.

**Skin (this repo):**
- `templates/decks_row.xml` — NEW: shared bottom deck row (LOAD 1 | deck 1 | banners | deck 2 | LOAD 2) with reworded lock banner + new load-blocked banner.
- `library.xml` — replace inline `Decks` group with the template (modify).
- `search.xml` — replace `SearchLoadRow` with the template (modify).
- `style.qss` — word-wrap + sizing for the long banner; style the new banner (modify).

**CI/docs:** `.github/workflows/build-mixxx-deb.yml`, `mixxx-patch/VERSION.md` (modify).

---

### Task 1: Patch — two-tier hold / force eject

**Files:**
- Modify: `../mixxx-src/mixxx-2.5.0/src/library/librarycontrol.h`
- Modify: `../mixxx-src/mixxx-2.5.0/src/library/librarycontrol.cpp`

**Interfaces:**
- Consumes: existing `isUsbInUse(int)`, `startEject(int)`, `showBanner(ControlPushButton*)`, `updateUsbStateControls()`, `usbMountPath(int)`, members `m_holdUsb`, `m_holdElapsed`, `m_holdFlashTimer`, `m_flashOn`, `m_lastFlashToggleMs`, `m_pUsbLocked`.
- Produces: `void stopDecksPlayingFromUsb(int usbIndex)`; member `bool m_holdLockedBannerShown`. `finishHoldEject` is removed.

- [ ] **Step 1: Snapshot baseline (BEFORE any edit)**

```bash
cd "../mixxx-src/mixxx-2.5.0"
rm -rf /c/tmp/fe-baseline
mkdir -p /c/tmp/fe-baseline/src/library /c/tmp/fe-baseline/src/widget
cp src/library/librarycontrol.h src/library/librarycontrol.cpp /c/tmp/fe-baseline/src/library/
cp src/widget/wtracktableview.cpp /c/tmp/fe-baseline/src/widget/
```

- [ ] **Step 2: Header edits**

In `src/library/librarycontrol.h`: delete the line `void finishHoldEject(int usbIndex);` and, in the same private-helpers area, add:

```cpp
    void stopDecksPlayingFromUsb(int usbIndex);
```

After the member `bool m_ejectRunning = false;` add:

```cpp
    // True once the "locked" banner fired at the 5s tier of the current
    // hold, so it only shows once while the hold continues toward force.
    bool m_holdLockedBannerShown = false;
```

- [ ] **Step 3: Rework `slotHoldFlashTick()` in `librarycontrol.cpp`**

Replace the entire existing `slotHoldFlashTick()` body with:

```cpp
void LibraryControl::slotHoldFlashTick() {
    if (m_holdUsb == 0) {
        m_holdFlashTimer.stop();
        return;
    }
    const qint64 elapsed = m_holdElapsed.elapsed();
    if (elapsed >= 10000) {
        // Force tier: stop any deck still playing from this stick, then
        // run the normal eject path (it unloads the now-paused decks and
        // retries umount while the caching reader closes files).
        m_holdFlashTimer.stop();
        const int usbIndex = m_holdUsb;
        m_holdUsb = 0;
        m_flashOn = false;
        updateUsbStateControls();
        stopDecksPlayingFromUsb(usbIndex);
        startEject(usbIndex);
        return;
    }
    if (elapsed >= 5000) {
        if (!isUsbInUse(m_holdUsb)) {
            // Stick free (or the blocking deck stopped mid-hold): eject now.
            m_holdFlashTimer.stop();
            const int usbIndex = m_holdUsb;
            m_holdUsb = 0;
            m_flashOn = false;
            updateUsbStateControls();
            startEject(usbIndex);
            return;
        }
        // Locked: tell the operator once, keep the hold alive toward force.
        if (!m_holdLockedBannerShown) {
            m_holdLockedBannerShown = true;
            showBanner(m_pUsbLocked.get());
        }
    }
    if (elapsed < 600) {
        return;
    }
    // Flash toggle interval shrinks linearly 250ms -> 80ms over the first
    // 5s of the hold, then stays at the 80ms cap through the force tier.
    const qint64 interval = qMax<qint64>(80,
            250 - (250 - 80) * (elapsed - 600) / (5000 - 600));
    if (m_lastFlashToggleMs == 0 || elapsed - m_lastFlashToggleMs >= interval) {
        m_flashOn = !m_flashOn;
        m_lastFlashToggleMs = elapsed;
        updateUsbStateControls();
    }
}
```

- [ ] **Step 4: Reset the flag on press; remove `finishHoldEject`; add the stop helper**

In `slotUsbButtonPress()` add `m_holdLockedBannerShown = false;` next to `m_flashOn = false;`.

Delete the whole `LibraryControl::finishHoldEject(int usbIndex)` function. In its place add:

```cpp
void LibraryControl::stopDecksPlayingFromUsb(int usbIndex) {
    const QString prefix = usbMountPath(usbIndex) + QStringLiteral("/");
    const QStringList groups = {QStringLiteral("[Channel1]"),
            QStringLiteral("[Channel2]")};
    for (const QString& group : groups) {
        const TrackPointer pTrack = PlayerInfo::instance().getTrackInfo(group);
        if (pTrack && pTrack->getLocation().startsWith(prefix) &&
                ControlObject::get(ConfigKey(group, QStringLiteral("play"))) > 0.0) {
            ControlObject::set(ConfigKey(group, QStringLiteral("play")), 0.0);
        }
    }
}
```

- [ ] **Step 5: Logic review (no local build)**

Confirm by reading: `qMax<qint64>` is fine (`QtGlobal` in scope); release in 5–10s hits `slotUsbButtonRelease` whose `elapsed < 600` check is false → no action, timer stopped, state cleared (no change needed there); no remaining reference to `finishHoldEject` (`grep -n finishHoldEject src/library/*.cpp src/library/*.h` → no matches); `stopDecksPlayingFromUsb` mirrors `isUsbInUse`'s matching logic; `play` set is synchronous so `startEject`→`unloadDecksFromUsb` sees `play==0`.

---

### Task 2: Patch — load-blocked banner

**Files:**
- Modify: `../mixxx-src/mixxx-2.5.0/src/library/librarycontrol.h`
- Modify: `../mixxx-src/mixxx-2.5.0/src/library/librarycontrol.cpp`
- Modify: `../mixxx-src/mixxx-2.5.0/src/widget/wtracktableview.cpp`

**Interfaces:**
- Produces: control `[Library],load_blocked` (skin binds label visibility to it, Task 4).
- Consumes: `m_bannerClearTimer` (2s single-shot → `clearBanners()`), `showBanner` pattern.

- [ ] **Step 1: Header — new member**

In `src/library/librarycontrol.h`, after `std::unique_ptr<ControlPushButton> m_pUsbEjectFailed;` add:

```cpp
    std::unique_ptr<ControlPushButton> m_pLoadBlocked;
```

- [ ] **Step 2: Register the control + timer hookup in the constructor**

In `librarycontrol.cpp`, immediately after the `m_pUsbEjectFailed = std::make_unique<...>` statement, add:

```cpp
    m_pLoadBlocked = std::make_unique<ControlPushButton>(
            ConfigKey("[Library]", "load_blocked"));
    // Set from WTrackTableView when a load is rejected because the target
    // deck is playing. Start the banner clear timer as showBanner() would.
    connect(m_pLoadBlocked.get(),
            &ControlPushButton::valueChanged,
            this,
            [this](double value) {
                if (value > 0.0) {
                    m_bannerClearTimer.start();
                }
            });
```

- [ ] **Step 3: Clear it with the other banners**

In `clearBanners()` add:

```cpp
    m_pLoadBlocked->setAndConfirm(0.0);
```

- [ ] **Step 4: Fire it at the silent-reject point**

In `src/widget/wtracktableview.cpp`, `loadSelectedTrackToGroup()`, change:

```cpp
    if (!allowLoadTrackIntoPlayingDeck &&
            !PlayerManager::isPreviewDeckGroup(group) &&
            ControlObject::get(ConfigKey(group, "play")) > 0.0) {
        return;
    }
```

to:

```cpp
    if (!allowLoadTrackIntoPlayingDeck &&
            !PlayerManager::isPreviewDeckGroup(group) &&
            ControlObject::get(ConfigKey(group, "play")) > 0.0) {
        // Surface the silent rejection; the Pioneered skin shows a
        // "PAUSE DECK TO LOAD" banner bound to this control.
        ControlObject::set(ConfigKey("[Library]", "load_blocked"), 1.0);
        return;
    }
```

- [ ] **Step 5: Logic review**

Confirm: `ControlObject::set` on a nonexistent CO is a warning no-op in release (safe if patch order ever changed); `valueChanged` fires on external set; `clearBanners()` (2s later) resets it; `showBanner()` for USB banners calls `clearBanners()` first, which also hides a lingering load banner — acceptable last-writer-wins. `wtracktableview.cpp` already includes `control/controlobject.h` (it calls `ControlObject::get` in this function) — no include change.

---

### Task 3: Generate & verify `usb-force-eject.patch`

**Files:**
- Create: `mixxx-patch/usb-force-eject.patch`

- [ ] **Step 1: Generate**

```bash
cd "../mixxx-src/mixxx-2.5.0"
OUT=/c/tmp/usb-force-eject.patch; : > "$OUT"
for f in src/library/librarycontrol.h src/library/librarycontrol.cpp src/widget/wtracktableview.cpp; do
  git diff --no-index "/c/tmp/fe-baseline/$f" "$f" | sed 's#a/C:/tmp/fe-baseline/#a/#g' >> "$OUT"
done
grep -n "^diff --git\|^--- \|^+++ " "$OUT"   # expect a/src/... b/src/... for all 3 files
```

- [ ] **Step 2: Copy to repo, dry-run against fresh baseline**

```bash
cp /c/tmp/usb-force-eject.patch "<repo>/mixxx-patch/usb-force-eject.patch"
rm -rf /c/tmp/fe-verify && mkdir -p /c/tmp/fe-verify && cp -r /c/tmp/fe-baseline/src /c/tmp/fe-verify/
cd /c/tmp/fe-verify && patch -p1 --dry-run < "<repo>/mixxx-patch/usb-force-eject.patch"
```
Expected: `checking file ...` ×3, all succeed.

- [ ] **Step 3: Commit**

```bash
git add mixxx-patch/usb-force-eject.patch
git commit -m "feat(patch): usb-force-eject — 10s force tier + load-blocked banner"
```

---

### Task 4: Skin — shared decks row + banners

**Files:**
- Create: `templates/decks_row.xml`
- Modify: `library.xml` (replace the `Decks` WidgetGroup)
- Modify: `search.xml` (replace the `SearchLoadRow` WidgetGroup)
- Modify: `style.qss`

**Interfaces:**
- Consumes: `[Library],load_blocked` (Task 2), existing `[Library],usb_locked` / `usb_eject_failed`, `skin:deck.xml`, `skin:templates/load_button.xml`.

- [ ] **Step 1: Create `templates/decks_row.xml`** (the exact `Decks` group from `library.xml` with the reworded lock banner and the new load banner):

```xml
<Template>
  <WidgetGroup>
    <ObjectName>Decks</ObjectName>
    <Layout>horizontal</Layout>
    <Size>0me,90f</Size>
    <Children>
      <Template src="skin:templates/load_button.xml">
        <SetVariable name="channel">1</SetVariable>
      </Template>
      <Template src="skin:deck.xml">
        <SetVariable name="channel">1</SetVariable>
      </Template>
      <WidgetGroup>
        <ObjectName>UsbBanners</ObjectName>
        <Layout>vertical</Layout>
        <Size>150f,0me</Size>
        <Children>
          <Label>
            <ObjectName>UsbLockedBanner</ObjectName>
            <Text>PLAYING FROM USB — PAUSE TO EJECT, KEEP HOLDING TO FORCE</Text>
            <SizePolicy>me,me</SizePolicy>
            <Connection>
              <ConfigKey persist="false">[Library],usb_locked</ConfigKey>
              <BindProperty>visible</BindProperty>
            </Connection>
          </Label>
          <Label>
            <ObjectName>UsbEjectFailedBanner</ObjectName>
            <Text>EJECT FAILED</Text>
            <SizePolicy>me,me</SizePolicy>
            <Connection>
              <ConfigKey persist="false">[Library],usb_eject_failed</ConfigKey>
              <BindProperty>visible</BindProperty>
            </Connection>
          </Label>
          <Label>
            <ObjectName>LoadBlockedBanner</ObjectName>
            <Text>PAUSE DECK TO LOAD</Text>
            <SizePolicy>me,me</SizePolicy>
            <Connection>
              <ConfigKey persist="false">[Library],load_blocked</ConfigKey>
              <BindProperty>visible</BindProperty>
            </Connection>
          </Label>
        </Children>
      </WidgetGroup>
      <Template src="skin:deck.xml">
        <SetVariable name="channel">2</SetVariable>
      </Template>
      <Template src="skin:templates/load_button.xml">
        <SetVariable name="channel">2</SetVariable>
      </Template>
    </Children>
  </WidgetGroup>
</Template>
```

- [ ] **Step 2: `library.xml`** — replace the whole `Decks` WidgetGroup (from `<WidgetGroup>` with `<ObjectName>Decks</ObjectName>` through its closing `</WidgetGroup>`) with:

```xml
      <Template src="skin:templates/decks_row.xml"/>
```

- [ ] **Step 3: `search.xml`** — replace the whole `SearchLoadRow` WidgetGroup with:

```xml
      <Template src="skin:templates/decks_row.xml"/>
```

- [ ] **Step 4: `style.qss`** — in the existing banner rule, add the new banner to the selector list and word-wrap the long one. Replace:

```css
#UsbLockedBanner, #UsbEjectFailedBanner {
```

with:

```css
#UsbLockedBanner, #UsbEjectFailedBanner, #LoadBlockedBanner {
```

and append after that block:

```css
#UsbLockedBanner {
  font-size: 11px;
  qproperty-wordWrap: true;
}
```

- [ ] **Step 5: Validate + commit**

```bash
python -c "import xml.dom.minidom
for f in ['templates/decks_row.xml','library.xml','search.xml']:
    xml.dom.minidom.parse(f); print('OK',f)"
git add templates/decks_row.xml library.xml search.xml style.qss
git commit -m "feat(skin): shared decks row on Search page + lock feedback banners"
```

---

### Task 5: CI wiring

**Files:**
- Modify: `.github/workflows/build-mixxx-deb.yml`
- Modify: `mixxx-patch/VERSION.md`

- [ ] **Step 1:** After the `search-osk.patch` apply line add:

```yaml
          patch -p1 < "$GITHUB_WORKSPACE/mixxx-patch/usb-force-eject.patch"
```

- [ ] **Step 2:** Append to the VERSION.md patch series:

```markdown
7. `usb-force-eject.patch` (added 2026-07-12) — two-tier USB hold: at 5s a
   locked stick shows the explanatory banner and the hold continues; at 10s
   playing decks on that stick are stopped and the eject runs regardless.
   Also adds `[Library],load_blocked`, set by WTrackTableView when a load is
   silently rejected because the target deck is playing (skin shows
   "PAUSE DECK TO LOAD"). Touches `src/library/librarycontrol.{h,cpp}`,
   `src/widget/wtracktableview.cpp`.
```

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/build-mixxx-deb.yml mixxx-patch/VERSION.md
git commit -m "ci: apply usb-force-eject.patch in the build series"
```

---

### Task 6: Build, stage, release r17

- [ ] **Step 1:** `git push fork master`
- [ ] **Step 2:** Trigger + watch:

```bash
"/c/Program Files/GitHub CLI/gh.exe" workflow run build-mixxx-deb.yml --ref master -R ogg755/Pioneered
"/c/Program Files/GitHub CLI/gh.exe" run watch <run-id> -R ogg755/Pioneered --exit-status
```
Expected: success. On patch/compile failure: read `--log-failed`, fix in the canonical tree, regenerate the patch from the same baseline, commit, re-push, re-run.

- [ ] **Step 3:** Download debs into `../pi-deploy/` (flatten, keep `r<N>.1` names):

```bash
"/c/Program Files/GitHub CLI/gh.exe" run download <run-id> -R ogg755/Pioneered -D ../pi-deploy/rNN
mv ../pi-deploy/rNN/mixxx-deb/*.deb ../pi-deploy/ && rm -rf ../pi-deploy/rNN
```

- [ ] **Step 4:** Publish release `v2.5.0-r<N>` titled "Pioneered v2.5.0-r<N> — force eject, Search waveforms, lock feedback" with the three debs attached (same `gh release create` pattern as v2.5.0-r16).
- [ ] **Step 5:** Hand the user the scp/apt install commands (r16 pattern) and the field checklist from the spec's Testing section. Field test is the user's step — do not claim runtime verification.

---

## Self-Review

**Spec coverage:** force tier + 5s continue + release-cancel (T1); stop-then-eject (T1 `stopDecksPlayingFromUsb`); track-ends-mid-hold ejects when free (T1 5s branch re-check each tick); load-blocked banner honouring Mixxx's own guard incl. preview-deck exclusion (T2 — hook is *inside* the guard, no duplication); banner reword + word-wrap (T4); shared decks row on both pages (T4); CI + VERSION (T5); build/release/field-handoff (T6). No gaps.

**Placeholder scan:** `<repo>`, `<run-id>`, `rNN`/`r<N>` are execution-time values; no TBDs.

**Type consistency:** `stopDecksPlayingFromUsb(int)` declared T1 Step 2, defined T1 Step 4, called T1 Step 3. `m_pLoadBlocked` declared T2 Step 1, used T2 Steps 2–3. `[Library],load_blocked` name identical in T2 Step 4 and T4 Step 1. `finishHoldEject` removed in both decl and def (T1 Steps 2, 4).
