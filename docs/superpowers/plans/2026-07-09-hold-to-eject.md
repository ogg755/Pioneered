# Hold-to-Eject USB Buttons Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Hold a USB button 5 s to safely eject that stick (accelerating red/white flash, "USB LOCKED" refusal when a deck uses it); short press keeps the v1 browse toggle; Tkinter overlay retired.

**Architecture:** All timing/eject logic goes into the existing Mixxx patch (`mixxx-patch/usb-browse.patch`, regenerated against the same 2.5.0 tree): the `goto_usb_*` controls become plain PUSH (press=1/release=0 events), a 40 ms tick timer drives an accelerating flash on new display controls `usb_*_state`, `PlayerInfo` supplies the lock check, and QProcess runs `sudo umount` asynchronously. The skin gains a third (white) button state and two banner labels driven by new banner controls.

**Tech Stack:** C++/Qt6 (Mixxx 2.5.0 `LibraryControl`), Mixxx legacy skin XML + QSS, Debian packaging via the existing GitHub Actions workflow, manual Pi deployment.

**Spec:** `docs/superpowers/specs/2026-07-09-hold-to-eject-design.md`

## Global Constraints

- Branch `touch-browse`; base = current head (includes usb-browse patch v1 with toggle-mode, lazy-population, and device-activation fixes).
- Patch target: pristine Debian source `mixxx_2.5.0+dfsg-3` (extracted tree `..\mixxx-src\mixxx-2.5.0` already carries the v1 edits — v2 edits go on top; the shipped patch is always ONE cumulative diff vs pristine).
- Control names, exact: `[Library],goto_usb_a`, `goto_usb_b` (emit), `usb_a_state`, `usb_b_state` (display: 0 idle / 1 red / 2 white), `usb_locked`, `usb_eject_failed` (banners).
- Timing, exact: short-press threshold 600 ms; eject at 5000 ms; flash toggle interval shrinks linearly 250 ms → 80 ms across 600–5000 ms; banners auto-clear after 2000 ms.
- Lock rule: refuse eject if `PlayerInfo::instance().getTrackInfo(group)` for `[Channel1]` or `[Channel2]` returns a track whose `getLocation()` starts with `/media/USBA/` resp. `/media/USBB/`.
- Eject = async `sudo umount /media/USBX` (QProcess), `#ifdef Q_OS_LINUX`; on success re-trigger the Rekordbox feature scan; not-mounted at 5 s = silent no-op; failure = EJECT FAILED banner.
- Skin must still load on unpatched Mixxx (buttons inert, banners never visible).
- Only one hold sequence at a time; a second button press during a hold is ignored.
- Verification limits: no local compile (CI is the compile gate); skin behavior partially verifiable on Windows stock Mixxx (layout only); full behavior on the Pi (manual, user-assisted — no SSH).
- Do NOT touch the segfault-investigation surface: no changes beyond what this plan specifies (backtrace evidence still pending).
- Commit after every task. Windows dev machine. gh CLI at `"C:\Program Files\GitHub CLI\gh.exe"`, repo fork remote `fork` → ogg755/Pioneered.

---

### Task 1: Patch v2 — hold state machine, flash, lock check, eject

**Files:**
- Modify: `..\mixxx-src\mixxx-2.5.0\src\library\librarycontrol.h` and `.cpp` (then regenerate `mixxx-patch/usb-browse.patch`)

**Interfaces:**
- Consumes: v1 members already in the edited tree: `slotGotoUsb(int, double)`, `findRekordboxDeviceIndex(const QString&)`, `restoreSidebarRoot()`, `validateSidebarRoot()`, `m_rootedDeviceIndex`, `m_rootedUsb`, `m_pGotoUsbA/B`, `Library::sidebarModel()`.
- Produces: controls `usb_a_state`/`usb_b_state` (values 0/1/2) and `usb_locked`/`usb_eject_failed` (0/1) consumed by Task 2's skin; `browseToggleUsb(int)` replacing the old toggle semantics.

- [ ] **Step 1: Rework the header members** (`librarycontrol.h`, in the existing "Pioneered touch-browse" private section — replace the v1 block)

```cpp
    // Pioneered touch-browse: USB A/B buttons.
    // Short press (<600ms) toggles browse-rooting at the Rekordbox device;
    // holding 5s ejects the stick (with accelerating red/white flash).
    void slotGotoUsb(int usbIndex, double v);
    void slotUsbButtonPress(int usbIndex);
    void slotUsbButtonRelease(int usbIndex);
    void slotHoldFlashTick();
    void finishHoldEject(int usbIndex);
    void browseToggleUsb(int usbIndex);
    void startEject(int usbIndex);
    bool isUsbInUse(int usbIndex) const;
    void showBanner(ControlPushButton* pBanner);
    void clearBanners();
    void updateUsbStateControls();
    void refreshRekordboxDevices();
    static QString usbMountPath(int usbIndex);
    QModelIndex findRekordboxDeviceIndex(const QString& deviceName);
    void restoreSidebarRoot();
    void validateSidebarRoot();

    std::unique_ptr<ControlPushButton> m_pGotoUsbA;
    std::unique_ptr<ControlPushButton> m_pGotoUsbB;
    std::unique_ptr<ControlPushButton> m_pUsbStateA;
    std::unique_ptr<ControlPushButton> m_pUsbStateB;
    std::unique_ptr<ControlPushButton> m_pUsbLocked;
    std::unique_ptr<ControlPushButton> m_pUsbEjectFailed;
    QTimer m_holdFlashTimer;
    QTimer m_bannerClearTimer;
    QElapsedTimer m_holdElapsed;
    qint64 m_lastFlashToggleMs = 0;
    int m_holdUsb = 0;  // 0 = no hold in progress, 1 = USBA, 2 = USBB
    bool m_flashOn = false;
    bool m_ejectRunning = false;
    QPersistentModelIndex m_rootedDeviceIndex;
    int m_rootedUsb = 0; // 0 = full tree, 1 = USBA, 2 = USBB
```

Add to the header's includes: `#include <QElapsedTimer>`, `#include <QTimer>` (keep the existing `#include <QPersistentModelIndex>`).

- [ ] **Step 2: Rework the constructor block** (`librarycontrol.cpp`, replace the v1 "Pioneered touch-browse controls" block)

```cpp
    // Pioneered touch-browse: USB A/B buttons. The goto_usb_* controls are
    // plain push buttons (1 on press, 0 on release); all gesture logic
    // (short press = browse toggle, 5s hold = eject) lives here. The skin
    // displays usb_*_state (0 idle / 1 red / 2 flash-white) and the two
    // banner controls.
    m_pGotoUsbA = std::make_unique<ControlPushButton>(
            ConfigKey("[Library]", "goto_usb_a"));
    m_pGotoUsbA->connectValueChangeRequest(this,
            [this](double value) {
                m_pGotoUsbA->setAndConfirm(value);
                slotGotoUsb(1, value);
            });
    m_pGotoUsbB = std::make_unique<ControlPushButton>(
            ConfigKey("[Library]", "goto_usb_b"));
    m_pGotoUsbB->connectValueChangeRequest(this,
            [this](double value) {
                m_pGotoUsbB->setAndConfirm(value);
                slotGotoUsb(2, value);
            });
    m_pUsbStateA = std::make_unique<ControlPushButton>(
            ConfigKey("[Library]", "usb_a_state"));
    m_pUsbStateA->setStates(3);
    m_pUsbStateB = std::make_unique<ControlPushButton>(
            ConfigKey("[Library]", "usb_b_state"));
    m_pUsbStateB->setStates(3);
    m_pUsbLocked = std::make_unique<ControlPushButton>(
            ConfigKey("[Library]", "usb_locked"));
    m_pUsbEjectFailed = std::make_unique<ControlPushButton>(
            ConfigKey("[Library]", "usb_eject_failed"));

    m_holdFlashTimer.setInterval(40);
    connect(&m_holdFlashTimer,
            &QTimer::timeout,
            this,
            &LibraryControl::slotHoldFlashTick);
    m_bannerClearTimer.setSingleShot(true);
    m_bannerClearTimer.setInterval(2000);
    connect(&m_bannerClearTimer,
            &QTimer::timeout,
            this,
            &LibraryControl::clearBanners);
```

Add to the cpp includes: `#include <QProcess>`, `#include <QStorageInfo>`, and `#include "mixer/playerinfo.h"` (keep `#include "library/sidebarmodel.h"`).

- [ ] **Step 3: Replace `slotGotoUsb` and add the new methods** (place after `slotGoToItem`; `findRekordboxDeviceIndex`, `restoreSidebarRoot`, `validateSidebarRoot` stay as in v1 except noted)

```cpp
void LibraryControl::slotGotoUsb(int usbIndex, double v) {
    if (v > 0) {
        slotUsbButtonPress(usbIndex);
    } else {
        slotUsbButtonRelease(usbIndex);
    }
}

void LibraryControl::slotUsbButtonPress(int usbIndex) {
    if (m_holdUsb != 0 || m_ejectRunning) {
        return; // one hold/eject at a time
    }
    m_holdUsb = usbIndex;
    m_flashOn = false;
    m_lastFlashToggleMs = 0;
    m_holdElapsed.start();
    m_holdFlashTimer.start();
}

void LibraryControl::slotUsbButtonRelease(int usbIndex) {
    if (m_holdUsb != usbIndex) {
        return; // eject already fired at 5s, or stray release
    }
    const qint64 elapsed = m_holdElapsed.elapsed();
    m_holdFlashTimer.stop();
    m_holdUsb = 0;
    m_flashOn = false;
    updateUsbStateControls();
    if (elapsed < 600) {
        browseToggleUsb(usbIndex);
    }
    // 600ms..5s: cancelled hold, no action
}

void LibraryControl::slotHoldFlashTick() {
    if (m_holdUsb == 0) {
        m_holdFlashTimer.stop();
        return;
    }
    const qint64 elapsed = m_holdElapsed.elapsed();
    if (elapsed >= 5000) {
        m_holdFlashTimer.stop();
        const int usbIndex = m_holdUsb;
        m_holdUsb = 0;
        m_flashOn = false;
        updateUsbStateControls();
        finishHoldEject(usbIndex);
        return;
    }
    if (elapsed < 600) {
        return;
    }
    // Flash toggle interval shrinks linearly 250ms -> 80ms over the hold
    const qint64 interval = 250 - (250 - 80) * (elapsed - 600) / (5000 - 600);
    if (m_lastFlashToggleMs == 0 || elapsed - m_lastFlashToggleMs >= interval) {
        m_flashOn = !m_flashOn;
        m_lastFlashToggleMs = elapsed;
        updateUsbStateControls();
    }
}

void LibraryControl::finishHoldEject(int usbIndex) {
    if (isUsbInUse(usbIndex)) {
        showBanner(m_pUsbLocked.get());
        return;
    }
    startEject(usbIndex);
}

bool LibraryControl::isUsbInUse(int usbIndex) const {
    const QString prefix = usbMountPath(usbIndex) + QStringLiteral("/");
    const QStringList groups = {QStringLiteral("[Channel1]"),
            QStringLiteral("[Channel2]")};
    for (const QString& group : groups) {
        const TrackPointer pTrack = PlayerInfo::instance().getTrackInfo(group);
        if (pTrack && pTrack->getLocation().startsWith(prefix)) {
            return true;
        }
    }
    return false;
}

void LibraryControl::startEject(int usbIndex) {
    const QString mountPath = usbMountPath(usbIndex);
    const QStorageInfo storage(mountPath);
    if (!storage.isValid() || !storage.isReady() ||
            storage.rootPath() != mountPath) {
        // Not mounted: treat as already ejected
        if (m_rootedUsb == usbIndex) {
            restoreSidebarRoot();
        }
        return;
    }
#ifdef Q_OS_LINUX
    if (m_rootedUsb == usbIndex) {
        restoreSidebarRoot();
    }
    m_ejectRunning = true;
    auto* pProcess = new QProcess(this);
    connect(pProcess,
            QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
            this,
            [this, usbIndex, pProcess](int exitCode, QProcess::ExitStatus) {
                pProcess->deleteLater();
                m_ejectRunning = false;
                if (exitCode == 0) {
                    // Device gone: refresh the Rekordbox device list so the
                    // sidebar row (and its playlists/tracks) disappears
                    refreshRekordboxDevices();
                } else {
                    showBanner(m_pUsbEjectFailed.get());
                }
                updateUsbStateControls();
            });
    pProcess->start(QStringLiteral("sudo"),
            {QStringLiteral("umount"), mountPath});
#else
    Q_UNUSED(usbIndex);
    // No umount on this platform; signal the failure visibly
    showBanner(m_pUsbEjectFailed.get());
#endif
}

void LibraryControl::refreshRekordboxDevices() {
    SidebarModel* pSidebarModel = m_pLibrary->sidebarModel();
    VERIFY_OR_DEBUG_ASSERT(pSidebarModel) {
        return;
    }
    for (int i = 0; i < pSidebarModel->rowCount(); ++i) {
        const QModelIndex featureIndex = pSidebarModel->index(i, 0);
        const QString featureTitle =
                pSidebarModel->data(featureIndex, Qt::DisplayRole).toString();
        if (featureTitle.endsWith(QStringLiteral("Rekordbox"),
                    Qt::CaseInsensitive)) {
            pSidebarModel->clicked(featureIndex); // triggers device rescan
            return;
        }
    }
}

void LibraryControl::showBanner(ControlPushButton* pBanner) {
    clearBanners();
    pBanner->setAndConfirm(1.0);
    m_bannerClearTimer.start();
}

void LibraryControl::clearBanners() {
    m_pUsbLocked->setAndConfirm(0.0);
    m_pUsbEjectFailed->setAndConfirm(0.0);
}

void LibraryControl::updateUsbStateControls() {
    auto stateFor = [this](int usbIndex) -> double {
        if (m_holdUsb == usbIndex) {
            return m_flashOn ? 2.0 : 1.0;
        }
        return (m_rootedUsb == usbIndex) ? 1.0 : 0.0;
    };
    m_pUsbStateA->setAndConfirm(stateFor(1));
    m_pUsbStateB->setAndConfirm(stateFor(2));
}

// static
QString LibraryControl::usbMountPath(int usbIndex) {
    return (usbIndex == 1) ? QStringLiteral("/media/USBA")
                           : QStringLiteral("/media/USBB");
}

void LibraryControl::browseToggleUsb(int usbIndex) {
    if (!m_pSidebarWidget) {
        return;
    }
    if (m_rootedUsb == usbIndex) {
        restoreSidebarRoot();
        return;
    }
    const QString deviceName = (usbIndex == 1)
            ? QStringLiteral("USBA")
            : QStringLiteral("USBB");
    const QModelIndex deviceIndex = findRekordboxDeviceIndex(deviceName);
    if (!deviceIndex.isValid()) {
        return; // not mounted / not scanned yet: no-op (retry primes scan)
    }
    m_pSidebarWidget->setRootIndex(deviceIndex);
    m_rootedDeviceIndex = QPersistentModelIndex(deviceIndex);
    m_rootedUsb = usbIndex;
    SidebarModel* pSidebarModel = m_pLibrary->sidebarModel();
    connect(pSidebarModel,
            &QAbstractItemModel::rowsRemoved,
            this,
            &LibraryControl::validateSidebarRoot,
            Qt::UniqueConnection);
    connect(pSidebarModel,
            &QAbstractItemModel::modelReset,
            this,
            &LibraryControl::validateSidebarRoot,
            Qt::UniqueConnection);
    if (pSidebarModel->rowCount(deviceIndex) == 0) {
        // Playlists parse lazily on first activation (async)
        pSidebarModel->clicked(deviceIndex);
    }
    const QModelIndex firstChild = pSidebarModel->index(0, 0, deviceIndex);
    if (firstChild.isValid()) {
        m_pSidebarWidget->selectIndex(firstChild);
    }
    setLibraryFocus(FocusWidget::Sidebar);
    updateUsbStateControls();
}
```

And update the two v1 leftovers:
- `restoreSidebarRoot()`: delete the two `m_pGotoUsbA/B->setAndConfirm(0.0)` lines and append `updateUsbStateControls();` at the end.
- Delete the whole v1 `slotGotoUsb` body (replaced above) and the v1 `setStates(2)` / `setButtonMode(ControlPushButton::TOGGLE)` lines on `m_pGotoUsbA/B` (now plain PUSH-mode event carriers).

- [ ] **Step 4: Regenerate and verify the cumulative patch**

Same mechanics as v1 (pristine extraction of the three files from `mixxx_2.5.0+dfsg.orig.tar.xz`; `git diff --no-index` → `a/`,`b/` paths; pure LF):
```
git apply --check mixxx-patch/usb-browse.patch   # from pristine tree: exit 0
patch -p1 --dry-run < .../usb-browse.patch        # no fuzz, no offsets
```
Pedantic compile re-read of every hunk (no local compiler; CI is the gate): declarations vs definitions, includes present (`QTimer`, `QElapsedTimer`, `QProcess`, `QStorageInfo`, `playerinfo.h`), `TrackPointer` available via playerinfo.h, lambda captures, `QOverload` connect form.

- [ ] **Step 5: Commit**

```bash
git add mixxx-patch/usb-browse.patch
git commit -m "feat: hold-to-eject USB buttons in Mixxx patch (flash, lock check, async umount)"
```

---

### Task 2: Skin — 3-state USB buttons and banner labels

**Files:**
- Modify: `library.xml` (USB button blocks; banner group in the Decks strip)
- Modify: `style.qss` (state-2 style; banner styles)

**Interfaces:**
- Consumes: controls from Task 1: `[Library],goto_usb_a/b` (emit-only), `usb_a_state`/`usb_b_state` (display), `usb_locked`/`usb_eject_failed` (visibility).
- Produces: ObjectNames `UsbBanners`, `UsbLockedBanner`, `UsbEjectFailedBanner` styled in this same task.

- [ ] **Step 1: Replace both USB PushButtons in `library.xml`** (shown for A; B is identical with `B`/`goto_usb_b`/`usb_b_state`)

```xml
                  <PushButton>
                    <ObjectName>UsbButtonA</ObjectName>
                    <Size>0me,0me</Size>
                    <NumberStates>3</NumberStates>
                    <State>
                      <Number>0</Number>
                      <Text>USB A</Text>
                    </State>
                    <State>
                      <Number>1</Number>
                      <Text>USB A</Text>
                    </State>
                    <State>
                      <Number>2</Number>
                      <Text>USB A</Text>
                    </State>
                    <Connection>
                      <ConfigKey persist="false">[Library],goto_usb_a</ConfigKey>
                      <ConnectValueToWidget>false</ConnectValueToWidget>
                      <EmitOnPressAndRelease>true</EmitOnPressAndRelease>
                      <ButtonState>LeftButton</ButtonState>
                    </Connection>
                    <Connection>
                      <ConfigKey persist="false">[Library],usb_a_state</ConfigKey>
                      <ConnectValueFromWidget>false</ConnectValueFromWidget>
                    </Connection>
                  </PushButton>
```

- [ ] **Step 2: Insert the banner group in the Decks strip** in `library.xml`, between the two `skin:deck.xml` templates:

```xml
          <WidgetGroup>
            <ObjectName>UsbBanners</ObjectName>
            <Layout>vertical</Layout>
            <Size>150f,0me</Size>
            <Children>
              <Label>
                <ObjectName>UsbLockedBanner</ObjectName>
                <Text>USB LOCKED</Text>
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
            </Children>
          </WidgetGroup>
```

- [ ] **Step 3: Append QSS** (end of the Library section of `style.qss`):

```css
#UsbButtonA[value="2"], #UsbButtonB[value="2"] {
  background-color: white;
  border: 1px solid white;
  color: #b6294c;
}

#UsbLockedBanner, #UsbEjectFailedBanner {
  background-color: #b6294c;
  border-radius: 4px;
  color: white;
  font-size: 16px;
  font-weight: bold;
  margin: 6px;
  qproperty-alignment: AlignCenter;
}
```

- [ ] **Step 4: XML well-formedness check**

```powershell
[xml](Get-Content library.xml) | Out-Null; "XML OK"
```
Expected: `XML OK`.

- [ ] **Step 5: Windows smoke test** — copy skin to `$env:LOCALAPPDATA\Mixxx\skins\Pioneered` (robocopy `/XD .git`), launch stock Mixxx: skin loads, USB buttons render dark (state 0), no banners visible, short click still toggles the (inert) style-free look without errors in `%LOCALAPPDATA%\Mixxx\mixxx.log`. Kill Mixxx.

- [ ] **Step 6: Commit**

```bash
git add library.xml style.qss
git commit -m "feat: 3-state USB buttons and eject banners in skin"
```

---

### Task 3: CI build with everything

**Files:** none (workflow already uploads mixxx, mixxx-data, mixxx-dbgsym since commits 3ddc45e/9a21a20).

- [ ] **Step 1: Push and trigger**

```powershell
git push fork touch-browse
& "C:\Program Files\GitHub CLI\gh.exe" workflow run build-mixxx-deb.yml --repo ogg755/Pioneered --ref touch-browse
```

- [ ] **Step 2: Poll to completion** (background poll every 240 s as in prior runs). Expected: success in 30–60 min. A compile error = Task 1 defect: fix the patch, recommit, re-trigger.

- [ ] **Step 3: Download artifacts**

```powershell
& "C:\Program Files\GitHub CLI\gh.exe" run download <RUN_ID> --repo ogg755/Pioneered --name mixxx-deb --dir ..\mixxx-deb-v2
```
Expected files: `mixxx_2.5.0+dfsg-3+usbbrowse1_arm64.deb`, `mixxx-data_..._all.deb`, `mixxx-dbgsym_..._arm64.deb` (dbgsym may be `.ddeb`).

---

### Task 4: Deployment docs update

**Files:**
- Modify: `docs/pi-deploy.md`

- [ ] **Step 1: Add three sections to `docs/pi-deploy.md`**

Append after the "Behavior contract" section:

```markdown
## Ejecting USB sticks (hold-to-eject)
- Hold USB A/USB B ~5 s: the button flashes red/white, speeding up; at 5 s the
  stick is unmounted and its playlists/tracks disappear. Safe to pull.
- "USB LOCKED" (2 s banner): a deck still has a track from that stick loaded
  (playing or paused). Load something else on that deck, then retry.
- "EJECT FAILED" (2 s banner): unmount failed; the stick is still mounted.
- Short press is unchanged (browse toggle). Releasing mid-hold cancels.
- The old Tkinter overlay (usb-control.py) is retired: remove its line from
  the Openbox autostart file (~/.config/openbox/autostart) after the eject
  feature passes testing.

## Crash diagnostics
One-time setup:  sudo apt install -y systemd-coredump gdb
Install the debug symbols with the other packages:
  sudo apt install -y /tmp/mixxx-dbgsym_*.deb   (or .ddeb)
After any Mixxx crash:
  coredumpctl list mixxx
  DEBUGINFOD_URLS="https://debuginfod.debian.net" coredumpctl gdb mixxx
  (gdb) bt
Copy the backtrace into the session for diagnosis.
```

Also update the "Patched Mixxx" install command to include the dbgsym package and note that the artifact now contains three packages.

- [ ] **Step 2: Commit**

```bash
git add docs/pi-deploy.md
git commit -m "docs: hold-to-eject usage, overlay retirement, crash diagnostics"
```

---

### Task 5: Pi deployment + end-to-end test (manual, user-assisted)

**Files:** none.

- [ ] **Step 1: Stage the bundle** — `git archive` the skin to `..\pi-deploy\Pioneered-skin.tar.gz`, copy the three `.deb`s from `..\mixxx-deb-v2\` alongside.

- [ ] **Step 2: Hand the user the copy-paste commands** (same shape as v1: scp all four files to `/tmp/`, then on the Pi):

```bash
sudo apt install -y /tmp/mixxx_*_arm64.deb /tmp/mixxx-data_*_all.deb /tmp/mixxx-dbgsym_*.deb
sudo apt-mark hold mixxx mixxx-data
sudo apt install -y systemd-coredump gdb
rm -rf ~/.mixxx/skins/Pioneered && mkdir -p ~/.mixxx/skins/Pioneered
tar xzf /tmp/Pioneered-skin.tar.gz -C ~/.mixxx/skins/Pioneered
```
Restart Mixxx.

- [ ] **Step 3: E2E checklist (user on the touchscreen, both sticks in)**

1. Short press USB A (twice on fresh boot — first primes the scan) → playlists appear; all v1 browse behaviors intact (playlist tap, LOAD 1/2, switch stick, press-again for full tree, DDJ knob).
2. Hold USB A: flashing starts ~0.6 s in, visibly speeds up.
3. Release at ~2 s: flash stops, nothing else happens.
4. Load a USBA track on deck 1 (leave paused), hold USB A to 5 s → "USB LOCKED" banner ~2 s, stick still browsable. Repeat while playing → same.
5. Clear both decks (load USBB tracks or eject tracks), hold USB A to 5 s → flash ends, USBA's playlists/tracks vanish from the pane, button dims. Pull the stick.
6. Re-insert USBA, wait ~2 s, press USB A (possibly twice) → playlists back.
7. Hold USB B with no stick inserted → nothing (no banner, no crash).
8. Overview/Sampler tabs unchanged; overlay removed from autostart and no longer appears.
9. Coredump capture works: `sleep 60 & kill -SEGV $!` then `coredumpctl list` shows the sleep crash (verifies the pipeline without touching Mixxx).

- [ ] **Step 4: Record pass/fail per item; failures loop back to Task 1/2 fixes + Task 3 rebuild.**
