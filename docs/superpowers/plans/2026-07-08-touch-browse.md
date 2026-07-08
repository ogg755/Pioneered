# Touch-Friendly USB Browse Screen Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Pioneer-XDJ-style browse screen for the Pioneered Mixxx skin on a 1024×600 touchscreen: tap USB A/USB B → that stick's playlists, tap playlist → tracks, tap track + LOAD 1/LOAD 2 → deck.

**Architecture:** Two independent deliverables that meet at two control names. (1) Skin rework in this repo: `library.xml` becomes a two-pane layout with USB buttons and LOAD buttons, `style.qss` gets touch sizing. (2) A small patch to the apt-packaged Mixxx adding `[Library],goto_usb_a` / `goto_usb_b` controls that re-root the sidebar `QTreeView` at a Rekordbox USB device node; built as an arm64 `.deb` via GitHub Actions and installed on the Pi with `apt-mark hold`.

**Tech Stack:** Mixxx legacy skin XML + QSS; C++/Qt (Mixxx `LibraryControl`, `WLibrarySidebar`, `SidebarModel`); Debian packaging (`apt source`, `dpkg-buildpackage`); GitHub Actions `ubuntu-24.04-arm` runner.

**Spec:** `docs/superpowers/specs/2026-07-08-touch-browse-design.md`

## Global Constraints

- Target device: Raspberry Pi 4B, hostname `XDJ400`, user `rpims`, Raspberry Pi OS Lite 64-bit, X11 + Openbox, 1024×600 screen. Reachable as `rpims@XDJ400.local` (SSH assumed; x11vnc already runs).
- Mixxx installed from apt; user reports 2.5.x. **Task 4 verifies the exact version and OS release; the patch and CI container must match it.** Mixxx APIs used by the patch (`WLibrarySidebar::selectIndex`, `QTreeView::setRootIndex`, `connectValueChangeRequest`, `parented_ptr`) exist in 2.4+.
- USB sticks mount at `/media/USBA` and `/media/USBB` (guaranteed by the Pi's udev scripts). Mixxx's Rekordbox feature scans `/media` (verified in `src/library/rekordbox/rekordboxfeature.cpp:205-218` of the mixxx repo).
- Control names shared between skin and patch — exact strings: `[Library],goto_usb_a`, `[Library],goto_usb_b`.
- The skin MUST still load and function (minus USB buttons) on an **unpatched** Mixxx.
- Do not modify `deck.xml`, `overview.xml`, `samplers.xml`, `topbar.xml`, `tab.xml`, or the Overview/Sampler tabs.
- Skin repo: `Pioneered/` (git, branch `master`). Local Mixxx source reference: `../mixxx` (git checkout of 2.6-beta main — reference only; the shipped patch targets the apt source).
- Commit after every task. Windows dev machine; paths in tasks are relative to `Pioneered/` unless absolute.

---

### Task 1: Two-pane library.xml with USB and LOAD buttons

**Files:**
- Create: `templates/load_button.xml`
- Modify: `library.xml` (full rewrite of file contents)

**Interfaces:**
- Consumes: `[Library],goto_usb_a` / `goto_usb_b` (created by the Task 5 patch; auto-created-but-inert on unpatched Mixxx), `[ChannelN],LoadSelectedTrack` (stock Mixxx).
- Produces: ObjectNames styled by Task 2 QSS: `PlaylistPane`, `UsbButtonRow`, `UsbButtonA`, `UsbButtonB`, `LoadDeck1`, `LoadDeck2`, `LibraryWrapper` (kept — existing QSS rules target it).

- [ ] **Step 1: Create `templates/load_button.xml`**

```xml
<Template>
  <PushButton>
    <ObjectName>LoadDeck<Variable name="channel"/></ObjectName>
    <Size>110f,0me</Size>
    <NumberStates>1</NumberStates>
    <State>
      <Number>0</Number>
      <Text>LOAD <Variable name="channel"/></Text>
    </State>
    <Connection>
      <ConfigKey>[Channel<Variable name="channel"/>],LoadSelectedTrack</ConfigKey>
      <EmitOnPressAndRelease>true</EmitOnPressAndRelease>
      <ButtonState>LeftButton</ButtonState>
    </Connection>
  </PushButton>
</Template>
```

- [ ] **Step 2: Replace the entire contents of `library.xml`**

Replaces the old show/hide-toggled layout (search box, `SidebarButton`, `[Sidebar],sidebar_visible` connections all removed):

```xml
<Template>
  <WidgetGroup>
    <SizePolicy>me,me</SizePolicy>
    <Layout>vertical</Layout>
    <Children>
      <WidgetGroup>
        <ObjectName>LibraryWrapper</ObjectName>
        <Layout>horizontal</Layout>
        <SizePolicy>me,me</SizePolicy>
        <Children>
          <WidgetGroup>
            <ObjectName>PlaylistPane</ObjectName>
            <Layout>vertical</Layout>
            <Size>340f,0me</Size>
            <Children>
              <WidgetGroup>
                <ObjectName>UsbButtonRow</ObjectName>
                <Layout>horizontal</Layout>
                <Size>0me,56f</Size>
                <Children>
                  <PushButton>
                    <ObjectName>UsbButtonA</ObjectName>
                    <Size>0me,0me</Size>
                    <NumberStates>2</NumberStates>
                    <State>
                      <Number>0</Number>
                      <Text>USB A</Text>
                    </State>
                    <State>
                      <Number>1</Number>
                      <Text>USB A</Text>
                    </State>
                    <Connection>
                      <ConfigKey persist="false">[Library],goto_usb_a</ConfigKey>
                      <ButtonState>LeftButton</ButtonState>
                    </Connection>
                  </PushButton>
                  <PushButton>
                    <ObjectName>UsbButtonB</ObjectName>
                    <Size>0me,0me</Size>
                    <NumberStates>2</NumberStates>
                    <State>
                      <Number>0</Number>
                      <Text>USB B</Text>
                    </State>
                    <State>
                      <Number>1</Number>
                      <Text>USB B</Text>
                    </State>
                    <Connection>
                      <ConfigKey persist="false">[Library],goto_usb_b</ConfigKey>
                      <ButtonState>LeftButton</ButtonState>
                    </Connection>
                  </PushButton>
                </Children>
              </WidgetGroup>
              <LibrarySidebar>
                <ObjectName>LibrarySidebar</ObjectName>
                <SizePolicy>me,me</SizePolicy>
              </LibrarySidebar>
            </Children>
          </WidgetGroup>
          <Library>
            <ObjectName>Library</ObjectName>
            <SizePolicy>me,me</SizePolicy>
            <BgColor>#000</BgColor>
            <FgColor>#75001a</FgColor>
            <TrackTableBackgroundColorOpacity>0.4</TrackTableBackgroundColorOpacity>
          </Library>
        </Children>
      </WidgetGroup>
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
          <Template src="skin:deck.xml">
            <SetVariable name="channel">2</SetVariable>
          </Template>
          <Template src="skin:templates/load_button.xml">
            <SetVariable name="channel">2</SetVariable>
          </Template>
        </Children>
      </WidgetGroup>
    </Children>
  </WidgetGroup>
</Template>
```

Notes for the implementer:
- `LibraryWrapper` ObjectName is intentionally kept on the outer pane group — all existing `#LibraryWrapper …` QSS rules keep applying to the sidebar/table.
- `340f` left pane ≈ 1/3 of 1024, per the approved mockup.
- The 2-state USB buttons toggle their control 0→1→0 on successive presses; the Task 5 patch interprets "request 1" = root at that USB and "request 0 while rooted" = restore full tree. On unpatched Mixxx the control is auto-created and the button is inert (styling still toggles) — acceptable per spec.

- [ ] **Step 3: Sanity-check the XML is well-formed**

Run (PowerShell, from `Pioneered/`):
```powershell
[xml](Get-Content library.xml) | Out-Null; [xml](Get-Content templates\load_button.xml) | Out-Null; "XML OK"
```
Expected: `XML OK` (any parse error throws).

- [ ] **Step 4: Commit**

```bash
git add library.xml templates/load_button.xml
git commit -m "feat: two-pane touch browse layout with USB A/B and LOAD buttons"
```

---

### Task 2: Touch-sized QSS

**Files:**
- Modify: `style.qss`

**Interfaces:**
- Consumes: ObjectNames from Task 1 (`PlaylistPane`, `UsbButtonA/B`, `LoadDeck1/2`, `LibraryWrapper`).
- Produces: nothing consumed later.

- [ ] **Step 1: Widen the library scrollbar for touch**

In `style.qss`, replace:
```css
#LibraryWrapper QScrollBar:vertical {
  border: 0;
  width: 4px;
}
```
with:
```css
#LibraryWrapper QScrollBar:vertical {
  border: 0;
  width: 24px;
}

#LibraryWrapper QScrollBar::handle:vertical {
  background-color: #5f5f6a;
  border-radius: 6px;
  min-height: 48px;
}
```

- [ ] **Step 2: Enlarge sidebar rows**

In `style.qss`, replace:
```css
#LibraryWrapper WLibrarySidebar {
  background-color: #32323c;
  selection-background-color: #e5e6ea;
  border-left: 4px solid gray;
  color: #e5e6ea;
  font-weight: bold;
  selection-color: black;
  text-transform: uppercase;
}
```
with:
```css
#LibraryWrapper WLibrarySidebar {
  background-color: #16161a;
  selection-background-color: #112f5c;
  color: #d5d6da;
  font-size: 18px;
  font-weight: bold;
  selection-color: white;
}

#LibraryWrapper WLibrarySidebar::item {
  padding: 12px 6px;
}
```
(`border-left` and `text-transform: uppercase` dropped: the pane moved to the left edge, and Rekordbox playlist names should keep their case.)

- [ ] **Step 3: Remove dead SearchBox/SidebarButton rules, append new component styles**

Delete these now-unused blocks (their widgets were removed in Task 1):
```css
/* Library Search */
#SearchBox { ... }

/* Sidebar (hide/show) */
#SidebarContainer { ... }
#SidebarButton { ... }
```
Append at the end of the Library section:
```css
/* Touch browse pane */
#PlaylistPane {
  background-color: #16161a;
  border-right: 2px solid #32323c;
}

#UsbButtonA, #UsbButtonB {
  background-color: #1a1a20;
  border: 1px solid #444444;
  border-radius: 3px;
  color: #aaaaaa;
  font-size: 18px;
  font-weight: bold;
  margin: 4px;
}

#UsbButtonA[value="1"], #UsbButtonB[value="1"] {
  background-color: #b6294c;
  border: 1px solid #b6294c;
  color: white;
}

#LoadDeck1, #LoadDeck2 {
  border-radius: 4px;
  color: white;
  font-size: 16px;
  font-weight: bold;
  margin: 6px;
}

#LoadDeck1 {
  background-color: #112f5c;
  border: 2px solid #2d85cd;
}

#LoadDeck2 {
  background-color: #5c1120;
  border: 2px solid #d73535;
}
```

- [ ] **Step 4: Commit**

```bash
git add style.qss
git commit -m "feat: touch-sized sidebar, scrollbar, USB and LOAD button styles"
```

---

### Task 3: Verify the skin on the Windows dev machine

**Files:**
- Modify: none expected (fixups to `library.xml`/`style.qss` if verification fails).

**Interfaces:**
- Consumes: Tasks 1–2 output.
- Produces: a skin verified to load; screenshot evidence.

- [ ] **Step 1: Install Mixxx on Windows if missing**

```powershell
if (-not (Test-Path "$env:ProgramFiles\Mixxx\mixxx.exe")) { winget install Mixxx.Mixxx --accept-source-agreements --accept-package-agreements }
```

- [ ] **Step 2: Install the skin into the Mixxx user skins folder**

```powershell
New-Item -ItemType Directory -Force "$env:LOCALAPPDATA\Mixxx\skins" | Out-Null
Copy-Item -Recurse -Force .\ "$env:LOCALAPPDATA\Mixxx\skins\Pioneered"
```

- [ ] **Step 3: Launch Mixxx, select the skin, verify visually**

Launch `mixxx.exe`, Preferences → Interface → skin "Pioneered", resize window to 1024×600. Checklist (fail any item → fix in `library.xml`/`style.qss`, re-copy, re-check):
- Browse tab shows left pane (USB A/USB B buttons + sidebar tree) and track table simultaneously; no search box; no Show/Hide button.
- USB A/USB B press toggles the red active style (they do nothing else on stock Mixxx — expected).
- LOAD 1 / LOAD 2 visible at the outer edges of the bottom strip; selecting a track in the table and pressing LOAD 1 loads it into deck 1, LOAD 2 into deck 2.
- Sidebar rows are visibly taller (≈44px) and 18px text; vertical scrollbar is wide.
- Overview and Sampler tabs unchanged.
- No skin errors in the Mixxx log: check `%LOCALAPPDATA%\Mixxx\mixxx.log` for lines containing `SKIN ERROR` or `Failed to load skin`.

- [ ] **Step 4: Commit any fixups**

```bash
git add -A
git commit -m "fix: browse layout adjustments from desktop verification"
```
(Skip if no changes.)

---

### Task 4: Pin down the Pi's exact Mixxx version and fetch its source

**Files:**
- Create: `mixxx-patch/VERSION.md` (records the facts every later task depends on)

**Interfaces:**
- Produces: `mixxx-patch/VERSION.md` containing: exact `mixxx` package version string, Debian release codename, source package URL. Consumed by Tasks 5–7.

- [ ] **Step 1: Query the Pi**

```powershell
ssh rpims@XDJ400.local "apt policy mixxx; grep VERSION_CODENAME /etc/os-release; dpkg --print-architecture"
```
Expected output shape: an installed version like `2.5.x-y`, a codename like `trixie`, arch `arm64`. If SSH is unreachable, ask the user to run the same command via VNC terminal and paste the output.

- [ ] **Step 2: Download the matching Debian source package on the dev machine**

```powershell
New-Item -ItemType Directory -Force ..\mixxx-src | Out-Null
cd ..\mixxx-src
# Find the .dsc on https://packages.debian.org/source/<codename>/mixxx — download the
# .dsc, .orig.tar.*, and .debian.tar.* it lists, e.g.:
curl -LO http://deb.debian.org/debian/pool/main/m/mixxx/mixxx_<VERSION>.dsc
curl -LO http://deb.debian.org/debian/pool/main/m/mixxx/mixxx_<UPSTREAM>.orig.tar.xz
curl -LO http://deb.debian.org/debian/pool/main/m/mixxx/mixxx_<VERSION>.debian.tar.xz
tar xf mixxx_<UPSTREAM>.orig.tar.xz
```
(`<VERSION>`/`<UPSTREAM>` come from Step 1. If the Pi's package comes from a Raspberry Pi–specific archive instead of deb.debian.org — check the `apt policy` origin line — fetch from that pool URL instead.)

- [ ] **Step 3: Record the facts**

Write `mixxx-patch/VERSION.md`:
```markdown
# Pi Mixxx build facts (source of truth for the patch + CI)
- Installed package: mixxx <VERSION from apt policy>
- OS: Raspberry Pi OS, Debian codename: <CODENAME>
- Arch: arm64
- Source pool: <URL directory used in Step 2>
- Queried: 2026-07-08 via `apt policy mixxx`
```

- [ ] **Step 4: Commit**

```bash
git add mixxx-patch/VERSION.md
git commit -m "chore: record Pi Mixxx version facts for the patch build"
```

---

### Task 5: Write the Mixxx patch (goto_usb_a / goto_usb_b)

**Files:**
- Create: `mixxx-patch/usb-browse.patch` (unified diff against the apt source tree from Task 4)

**Interfaces:**
- Consumes: extracted apt source at `..\mixxx-src\mixxx-<UPSTREAM>\`; facts from `mixxx-patch/VERSION.md`.
- Produces: controls `[Library],goto_usb_a` / `[Library],goto_usb_b` (2-state; request 1 = root sidebar at USBA/USBB, request 0 while rooted = restore full tree); `Library::sidebarModel()` accessor. Consumed by the Task 1 skin buttons.

The code below was drafted against mixxx git main (2.6-beta) — line numbers and context WILL differ in the 2.5 apt source; adapt the hunks to the actual files, keeping the logic identical. All three touched files exist in 2.4+.

- [ ] **Step 1: Add a `SidebarModel` accessor to `src/library/library.h`**

In the public section of `class Library` (near the other getters):
```cpp
    SidebarModel* sidebarModel() const {
        return m_pSidebarModel.get();
    }
```
Add `class SidebarModel;` forward declaration if not present (it is in 2.6; verify in 2.5).

- [ ] **Step 2: Declare the new members in `src/library/librarycontrol.h`**

In `class LibraryControl`, private section:
```cpp
    // Pioneered touch-browse: jump the sidebar to a Rekordbox USB device
    void slotGotoUsb(int usbIndex, double v);
    QModelIndex findRekordboxDeviceIndex(const QString& deviceName);
    void restoreSidebarRoot();
    void validateSidebarRoot();

    std::unique_ptr<ControlPushButton> m_pGotoUsbA;
    std::unique_ptr<ControlPushButton> m_pGotoUsbB;
    QPersistentModelIndex m_rootedDeviceIndex;
    int m_rootedUsb = 0; // 0 = full tree, 1 = USBA, 2 = USBB
```
Add `#include <QPersistentModelIndex>` to the header's includes.

- [ ] **Step 3: Implement in `src/library/librarycontrol.cpp`**

Includes to add at the top:
```cpp
#include "library/sidebarmodel.h"
```
In the constructor (next to the other control setups, e.g. after the `m_pGoToItem` block):
```cpp
    // Pioneered touch-browse controls: jump to Rekordbox USB device A/B.
    // Request 1 => root the sidebar at that device; request 0 while rooted
    // at it => restore the full tree. No-op when the device is not mounted.
    m_pGotoUsbA = std::make_unique<ControlPushButton>(
            ConfigKey("[Library]", "goto_usb_a"));
    m_pGotoUsbA->setStates(2);
    m_pGotoUsbA->connectValueChangeRequest(this,
            [this](double value) { slotGotoUsb(1, value); });
    m_pGotoUsbB = std::make_unique<ControlPushButton>(
            ConfigKey("[Library]", "goto_usb_b"));
    m_pGotoUsbB->setStates(2);
    m_pGotoUsbB->connectValueChangeRequest(this,
            [this](double value) { slotGotoUsb(2, value); });
```
Implementations (place after `slotGoToItem`):
```cpp
void LibraryControl::slotGotoUsb(int usbIndex, double v) {
    if (!m_pSidebarWidget) {
        return;
    }
    if (v <= 0) {
        // Toggle-off request: only meaningful when rooted at this device
        if (m_rootedUsb == usbIndex) {
            restoreSidebarRoot();
        }
        return;
    }
    const QString deviceName = (usbIndex == 1)
            ? QStringLiteral("USBA")
            : QStringLiteral("USBB");
    const QModelIndex deviceIndex = findRekordboxDeviceIndex(deviceName);
    if (!deviceIndex.isValid()) {
        // Device not mounted (or Rekordbox feature empty): no-op
        return;
    }
    m_pSidebarWidget->setRootIndex(deviceIndex);
    m_rootedDeviceIndex = QPersistentModelIndex(deviceIndex);
    m_rootedUsb = usbIndex;
    SidebarModel* pSidebarModel = m_pLibrary->sidebarModel();
    // Watch for the device disappearing (USB unplugged while rooted)
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
    // Select the first playlist so the DDJ-400 browse knob works immediately
    const QModelIndex firstChild = pSidebarModel->index(0, 0, deviceIndex);
    if (firstChild.isValid()) {
        m_pSidebarWidget->selectIndex(firstChild);
    }
    setLibraryFocus(FocusWidget::Sidebar);
    m_pGotoUsbA->setAndConfirm(usbIndex == 1 ? 1.0 : 0.0);
    m_pGotoUsbB->setAndConfirm(usbIndex == 2 ? 1.0 : 0.0);
}

QModelIndex LibraryControl::findRekordboxDeviceIndex(const QString& deviceName) {
    SidebarModel* pSidebarModel = m_pLibrary->sidebarModel();
    VERIFY_OR_DEBUG_ASSERT(pSidebarModel) {
        return QModelIndex();
    }
    for (int i = 0; i < pSidebarModel->rowCount(); ++i) {
        const QModelIndex featureIndex = pSidebarModel->index(i, 0);
        const QString featureTitle =
                pSidebarModel->data(featureIndex, Qt::DisplayRole).toString();
        if (featureTitle.compare(QStringLiteral("Rekordbox"),
                    Qt::CaseInsensitive) != 0) {
            continue;
        }
        for (int j = 0; j < pSidebarModel->rowCount(featureIndex); ++j) {
            const QModelIndex deviceIndex =
                    pSidebarModel->index(j, 0, featureIndex);
            const QString name =
                    pSidebarModel->data(deviceIndex, Qt::DisplayRole).toString();
            if (name.compare(deviceName, Qt::CaseInsensitive) == 0) {
                return deviceIndex;
            }
        }
        return QModelIndex(); // Rekordbox found but device absent
    }
    return QModelIndex(); // no Rekordbox feature
}

void LibraryControl::restoreSidebarRoot() {
    m_rootedUsb = 0;
    m_rootedDeviceIndex = QPersistentModelIndex();
    if (m_pSidebarWidget) {
        m_pSidebarWidget->setRootIndex(QModelIndex());
    }
    m_pGotoUsbA->setAndConfirm(0.0);
    m_pGotoUsbB->setAndConfirm(0.0);
}

void LibraryControl::validateSidebarRoot() {
    if (m_rootedUsb != 0 && !m_rootedDeviceIndex.isValid()) {
        restoreSidebarRoot();
    }
}
```
Also declare `validateSidebarRoot` as a private **slot** (it is connected to signals): put it under `private slots:` in the header instead of the plain private section if the connect calls above are kept pointer-to-member (either placement compiles with pointer-to-member connects; keep it simple and leave it private non-slot).

Note on Rekordbox lazy population: in 2.5 the Rekordbox feature populates its device list on startup and on a filesystem timer. If on-Pi testing (Task 7) shows devices only appear after first clicking the Rekordbox node, extend `findRekordboxDeviceIndex` to call `pSidebarModel->clicked(featureIndex)` once before the child scan and retry. Do not add this speculatively.

- [ ] **Step 4: Produce the patch file**

Apply the edits to a pristine copy of the apt source, then:
```powershell
cd ..\mixxx-src
Copy-Item -Recurse mixxx-<UPSTREAM> mixxx-<UPSTREAM>.orig-copy   # BEFORE editing
# ...make the Step 1-3 edits inside mixxx-<UPSTREAM>...
git diff --no-index mixxx-<UPSTREAM>.orig-copy mixxx-<UPSTREAM> > ..\Code\Pioneered\mixxx-patch\usb-browse.patch
```
Then fix the paths in the header lines to `a/src/...` / `b/src/...` form (strip the directory prefixes) so `patch -p1` applies from the source root.

- [ ] **Step 5: Verify the patch applies cleanly to pristine source**

```powershell
cd ..\mixxx-src\mixxx-<UPSTREAM>.orig-copy
git apply --check ..\..\Code\Pioneered\mixxx-patch\usb-browse.patch
```
Expected: no output (clean). Errors → fix hunk context and repeat.

- [ ] **Step 6: Commit**

```bash
git add mixxx-patch/usb-browse.patch
git commit -m "feat: Mixxx patch adding [Library],goto_usb_a/goto_usb_b sidebar re-rooting"
```

---

### Task 6: GitHub Actions arm64 .deb build

**Files:**
- Create: `.github/workflows/build-mixxx-deb.yml`

**Interfaces:**
- Consumes: `mixxx-patch/usb-browse.patch`, facts from `mixxx-patch/VERSION.md` (substitute `<CODENAME>` below).
- Produces: workflow artifact `mixxx-deb` containing the patched `mixxx_*.deb` for arm64.

- [ ] **Step 1: Write the workflow**

```yaml
name: Build patched Mixxx .deb (arm64)

on:
  workflow_dispatch:

jobs:
  build:
    runs-on: ubuntu-24.04-arm
    container: debian:<CODENAME>
    steps:
      - uses: actions/checkout@v4

      - name: Enable source repos and install build tools
        run: |
          echo "deb-src http://deb.debian.org/debian <CODENAME> main" \
            > /etc/apt/sources.list.d/src.list
          apt-get update
          apt-get install -y --no-install-recommends \
            build-essential devscripts dpkg-dev quilt ca-certificates
          apt-get build-dep -y mixxx

      - name: Fetch and patch source
        run: |
          mkdir /build && cd /build
          apt-get source mixxx
          cd mixxx-*/
          patch -p1 < "$GITHUB_WORKSPACE/mixxx-patch/usb-browse.patch"
          DEBEMAIL=nonofordnonoford@gmail.com DEBFULLNAME=marco \
            dch --local +usbbrowse "Add [Library],goto_usb_a/goto_usb_b sidebar controls"

      - name: Build package
        run: |
          cd /build/mixxx-*/
          dpkg-buildpackage -b -uc -us

      - name: Upload .deb
        uses: actions/upload-artifact@v4
        with:
          name: mixxx-deb
          path: /build/mixxx_*.deb
```
Replace both `<CODENAME>` occurrences with the value from `VERSION.md`. If `VERSION.md` recorded a non-Debian origin (Raspberry Pi archive), add that repo's deb-src line instead.

- [ ] **Step 2: Commit and push**

```bash
git add .github/workflows/build-mixxx-deb.yml
git commit -m "ci: build patched Mixxx arm64 .deb"
git push origin master
```
Note: `origin` must be a GitHub remote for the workflow to run; verify with `git remote -v`. If the repo lives elsewhere, push a GitHub mirror first (ask the user which account/repo to use — do not create one silently).

- [ ] **Step 3: Run the workflow and fetch the artifact**

```bash
gh workflow run build-mixxx-deb.yml
gh run watch
gh run download --name mixxx-deb --dir ../mixxx-deb
```
Expected: build succeeds (30–60 min); `../mixxx-deb/` contains `mixxx_*+usbbrowse*_arm64.deb`. A compile failure here is the patch's smoke test — fix `usb-browse.patch` (Task 5 Step 5 loop) and re-run.

---

### Task 7: Deploy to the Pi and end-to-end test

**Files:**
- None in repo (deployment).

**Interfaces:**
- Consumes: `.deb` artifact from Task 6, skin from Tasks 1–3.

- [ ] **Step 1: Install the patched .deb and hold it**

```powershell
scp ..\mixxx-deb\mixxx_*_arm64.deb rpims@XDJ400.local:/tmp/
ssh rpims@XDJ400.local "sudo apt install -y /tmp/mixxx_*_arm64.deb && sudo apt-mark hold mixxx && mixxx --version"
```
Expected: install succeeds; version string shows the `+usbbrowse` local suffix.

- [ ] **Step 2: Deploy the skin**

```powershell
ssh rpims@XDJ400.local "mkdir -p ~/.mixxx/skins"
scp -r . rpims@XDJ400.local:~/.mixxx/skins/Pioneered
```

- [ ] **Step 3: Configure Mixxx preferences on the Pi**

Via VNC (or by editing `~/.mixxx/mixxx.cfg` while Mixxx is stopped): Preferences → Interface → skin "Pioneered"; Preferences → Library → row height **48 px**, library font size ≈ **14 pt**. Restart Mixxx.

- [ ] **Step 4: End-to-end checklist (over VNC, both USB sticks inserted)**

- USB A tap → left pane shows only USBA's playlist tree, first playlist selected, button turns red.
- Playlist tap → tracks fill the right pane.
- Track tap + LOAD 1 → loads deck 1; LOAD 2 → deck 2.
- USB B tap → pane switches to USBB's playlists; USB A button un-reds.
- Active USB button tapped again → full stock sidebar tree returns.
- USB button for an unplugged stick → nothing happens, no dialog.
- Unplug the rooted stick (use the eject overlay) → sidebar returns to full tree by itself, no crash.
- DDJ-400 browse knob scrolls the playlist pane right after a USB button tap; knob press / knob in table works as before.
- Overview and Sampler tabs render as before.

- [ ] **Step 5: Record any failures as fixup work**

Any failed item → diagnose (skin issue → Tasks 1–3 files; patch issue → Task 5 + rebuild via Task 6), fix, redeploy, re-run the checklist.

---

### Task 8: Deployment documentation

**Files:**
- Create: `docs/pi-deploy.md`
- Modify: `README.md`

**Interfaces:**
- Consumes: everything above.

- [ ] **Step 1: Write `docs/pi-deploy.md`**

Content (complete file):
```markdown
# XDJ400 Pi deployment notes

## Skin
scp -r Pioneered rpims@XDJ400.local:~/.mixxx/skins/
Select in Preferences > Interface. Required library prefs:
Preferences > Library > row height 48 px, font size ~14 pt.

## Patched Mixxx (USB A/B buttons)
The skin's USB A/USB B buttons need the patched Mixxx build
(controls `[Library],goto_usb_a` / `goto_usb_b`, patch in `mixxx-patch/`).

1. Run the "Build patched Mixxx .deb (arm64)" GitHub Actions workflow.
2. Download the `mixxx-deb` artifact.
3. scp the .deb to the Pi, then:
   sudo apt install -y /tmp/mixxx_*_arm64.deb
   sudo apt-mark hold mixxx        # stop apt upgrade replacing it
4. Verify: mixxx --version shows a "+usbbrowse" suffix.

## Upgrading Mixxx later
sudo apt-mark unhold mixxx, update `mixxx-patch/VERSION.md` facts,
re-check the patch applies to the new apt source, re-run the workflow,
reinstall, re-hold.

## Behavior contract
- USB sticks must mount at /media/USBA and /media/USBB (udev scripts).
- On an unpatched Mixxx the skin still works; USB buttons are inert.
```

- [ ] **Step 2: Update `README.md`**

Add under Features:
```markdown
* Touch-optimized Browse tab: two-pane playlist/track view, one-tap USB A / USB B
  source buttons (requires the small Mixxx patch in `mixxx-patch/`, see
  `docs/pi-deploy.md`), and LOAD 1 / LOAD 2 buttons.
```

- [ ] **Step 3: Commit**

```bash
git add docs/pi-deploy.md README.md
git commit -m "docs: Pi deployment notes for touch browse + patched Mixxx"
```
