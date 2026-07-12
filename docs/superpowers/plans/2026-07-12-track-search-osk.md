# Track search + on-screen keyboard — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Sampler topbar tab with a Search tab whose OEM-themed on-screen QWERTY keyboard drives Mixxx's native search box to filter the selected folder.

**Architecture:** A new `mixxx-patch/search-osk.patch` adds a `WSearchLineEdit::slotSetSearchText()` slot plus `[Library],search_key_*`/`search_space`/`search_backspace` push controls that mutate the bound search box and re-run the search. The Pioneered skin gains a Search page that shares the single `WLibrary` table with the Browse page via a new `LibraryTable_Singleton`, hosts the native `<SearchBox>`, LOAD buttons, and a keyboard whose visibility is a skin-only `[Skin],show_keyboard` toggle. Built and released through the existing GitHub Actions → pi-deploy pipeline.

**Tech Stack:** C++/Qt (Mixxx 2.5.0), Mixxx legacy XML skins + QSS, `patch`/`git diff` patch generation, GitHub Actions (`build-mixxx-deb.yml`), `gh` CLI.

## Global Constraints

- **Mixxx source tree:** `../mixxx-src/mixxx-2.5.0` (canonical, all 5 existing patches already applied). Files are **LF**.
- **Skin repo:** this repo (`Pioneered/`), branch `master`.
- **Patch generation method:** snapshot each to-be-edited file to a baseline dir *before* editing, edit the canonical tree, `git diff --no-index baseline/ tree/` with `a/`,`b/` path rewrite, verify with `patch -p1 --dry-run` against a fresh baseline copy. Normalise CRLF→LF before any local `git apply`.
- **Backward compatibility:** the skin MUST still load on unpatched Mixxx — skin buttons bound to not-yet-existing `[Library],search_*` controls are inert, never fatal.
- **No local Mixxx build.** Compilation is gated by CI; the patch's runtime behaviour is verified on the dev-machine Mixxx run (Task 8) and Pi field test (Task 9). The C++ verification gate in Tasks 1–2 is a clean `patch -p1 --dry-run` + fresh-eyes logic review.
- **CI patch order (fixed):** usb-browse → pdb-corruption-hardening → xdj-behavior → library-ui → xdj-hardware → **search-osk** (new, last).
- **`gh` CLI:** `C:\Program Files\GitHub CLI\gh.exe` (not on PATH), authed as ogg755. Fork `ogg755/Pioneered`. `gh workflow run` MUST pass `--ref master`.
- **Character set for keys:** letters `a`–`z` (lowercase; search is case-insensitive) and digits `0`–`9`, plus space and backspace. Clear reuses existing `[Library],clear_search`. No shift, no punctuation.

---

## File map

**Mixxx source (patched into `search-osk.patch`):**
- `src/widget/wsearchlineedit.h` — declare `public slot slotSetSearchText(const QString&)`.
- `src/widget/wsearchlineedit.cpp` — implement it.
- `src/library/librarycontrol.h` — add `#include <vector>`; add key-control members + two helper method decls.
- `src/library/librarycontrol.cpp` — register key controls in ctor; implement helpers.

**Skin (this repo):**
- `topbar.xml` — Sampler tab → Search tab (modify).
- `skin.xml` — add `LibraryTable_Singleton` + `Search_Singleton` defs, swap stack page, add `[Skin],show_keyboard` manifest attribute (modify).
- `library.xml` — replace inline `<Library>` with a `SingletonContainer` for `LibraryTable_Singleton` (modify).
- `library_table.xml` — NEW: the shared `<Library>` table.
- `search.xml` — NEW: the Search page.
- `keyboard.xml` — NEW: the on-screen keyboard rows.
- `templates/kb_key.xml` — NEW: one-key template.
- `style.qss` — OEM theming for keyboard + search field (modify).

**CI/docs:**
- `.github/workflows/build-mixxx-deb.yml` — append the patch apply line (modify).
- `mixxx-patch/VERSION.md` — document patch #6 (modify).

---

### Task 1: Patch — `WSearchLineEdit::slotSetSearchText()`

**Files:**
- Modify: `../mixxx-src/mixxx-2.5.0/src/widget/wsearchlineedit.h`
- Modify: `../mixxx-src/mixxx-2.5.0/src/widget/wsearchlineedit.cpp`

**Interfaces:**
- Produces: `void WSearchLineEdit::slotSetSearchText(const QString& text)` — public slot. Enables the box if disabled, sets the edit text without re-emitting `textChanged`, then schedules the debounced live search and the history save-timer (same tail as `slotTextChanged`).
- Consumes: existing private `updateEditBox(const QString&)`, `triggerSearchDebounced()`, member `m_saveTimer`, constant `kSaveTimeoutMillis`, `getSearchText()`.

- [ ] **Step 1: Snapshot baseline**

```bash
cd "../mixxx-src/mixxx-2.5.0"
mkdir -p /c/tmp/osk-baseline/src/widget /c/tmp/osk-baseline/src/library
cp src/widget/wsearchlineedit.h src/widget/wsearchlineedit.cpp /c/tmp/osk-baseline/src/widget/
cp src/library/librarycontrol.h src/library/librarycontrol.cpp /c/tmp/osk-baseline/src/library/
```

- [ ] **Step 2: Declare the slot in the header**

In `src/widget/wsearchlineedit.h`, in the existing `public slots:` block, add after the `slotRestoreSearch(const QString& text);` line:

```cpp
    void slotRestoreSearch(const QString& text);
    /// Set the search text programmatically (e.g. from an on-screen keyboard)
    /// and run the search live, as if the user had typed it.
    void slotSetSearchText(const QString& text);
    void slotDisableSearch();
```

- [ ] **Step 3: Implement the slot**

In `src/widget/wsearchlineedit.cpp`, immediately after the closing brace of `WSearchLineEdit::slotRestoreSearch(...)`, add:

```cpp
void WSearchLineEdit::slotSetSearchText(const QString& text) {
    // Programmatic entry point for the on-screen keyboard. Unlike
    // slotRestoreSearch(), this re-runs the search: updateEditBox() sets the
    // text with signals blocked (no double-trigger), so we schedule the same
    // debounced search + history-save that slotTextChanged() does for typing.
    if (!isEnabled()) {
        setEnabled(true);
    }
    updateEditBox(text);
    triggerSearchDebounced();
    m_saveTimer.start(kSaveTimeoutMillis);
}
```

- [ ] **Step 4: Logic review (no local build)**

Confirm by reading: `updateEditBox` requires `isEnabled()` (we set it first); it calls `setTextBlockSignals` (signals blocked → no recursive `slotTextChanged`); `triggerSearchDebounced` starts `m_debouncingTimer` whose timeout calls `slotTriggerSearch` → `emit search(getSearchText())`. Empty `text` yields an empty query (clears the filter) — acceptable.
Expected: logic matches `slotTextChanged`'s enabled-path tail.

- [ ] **Step 5: Commit checkpoint (tree edit only; patch generated in Task 3)**

No commit yet — the Mixxx tree is not under this repo. Proceed to Task 2.

---

### Task 2: Patch — `LibraryControl` key controls

**Files:**
- Modify: `../mixxx-src/mixxx-2.5.0/src/library/librarycontrol.h`
- Modify: `../mixxx-src/mixxx-2.5.0/src/library/librarycontrol.cpp`

**Interfaces:**
- Consumes: `WSearchLineEdit::slotSetSearchText()` and `getSearchText()` (Task 1); existing `m_pSearchbox`, `ControlPushButton`, `ConfigKey`, `VERIFY_OR_DEBUG_ASSERT`.
- Produces: control objects `[Library],search_key_a` … `search_key_z`, `search_key_0` … `search_key_9`, `[Library],search_space`, `[Library],search_backspace`. Private helpers `appendToSearch(const QString&)`, `backspaceSearch()`.

- [ ] **Step 1: Header — include + members + helper decls**

In `src/library/librarycontrol.h`: add `#include <vector>` alongside the existing `#include <memory>` (line ~7).

Then, immediately after the member line `std::unique_ptr<ControlPushButton> m_pDeleteSearchQuery;`, add:

```cpp
    std::unique_ptr<ControlPushButton> m_pDeleteSearchQuery;

    // On-screen-keyboard search input: one push control per typeable
    // character, plus space and backspace. Clearing reuses clear_search.
    std::vector<std::unique_ptr<ControlPushButton>> m_searchKeys;
    std::unique_ptr<ControlPushButton> m_pSearchSpace;
    std::unique_ptr<ControlPushButton> m_pSearchBackspace;
```

In the `private:` methods area of the class (near the other private helpers), add declarations:

```cpp
    void appendToSearch(const QString& text);
    void backspaceSearch();
```

- [ ] **Step 2: Register the controls in the constructor**

In `src/library/librarycontrol.cpp`, immediately after the `m_pDeleteSearchQuery = std::make_unique<ControlPushButton>(...)` connect block ends (just before the `// Show the track context menu` comment), insert:

```cpp
    // On-screen-keyboard search controls (drive the bound searchbox). Guard
    // like the other search handlers; act only on the press edge (value > 0).
    const QString kSearchKeyChars =
            QStringLiteral("abcdefghijklmnopqrstuvwxyz0123456789");
    for (const QChar& ch : kSearchKeyChars) {
        auto pKey = std::make_unique<ControlPushButton>(
                ConfigKey(QStringLiteral("[Library]"),
                        QStringLiteral("search_key_%1").arg(ch)));
        const QString s(ch);
        connect(pKey.get(),
                &ControlPushButton::valueChanged,
                this,
                [this, s](double value) {
                    if (value > 0.0) {
                        appendToSearch(s);
                    }
                });
        m_searchKeys.push_back(std::move(pKey));
    }
    m_pSearchSpace = std::make_unique<ControlPushButton>(
            ConfigKey(QStringLiteral("[Library]"), QStringLiteral("search_space")));
    connect(m_pSearchSpace.get(),
            &ControlPushButton::valueChanged,
            this,
            [this](double value) {
                if (value > 0.0) {
                    appendToSearch(QStringLiteral(" "));
                }
            });
    m_pSearchBackspace = std::make_unique<ControlPushButton>(
            ConfigKey(QStringLiteral("[Library]"), QStringLiteral("search_backspace")));
    connect(m_pSearchBackspace.get(),
            &ControlPushButton::valueChanged,
            this,
            [this](double value) {
                if (value > 0.0) {
                    backspaceSearch();
                }
            });
```

- [ ] **Step 3: Implement the helpers**

In `src/library/librarycontrol.cpp`, after the closing brace of the constructor `LibraryControl::LibraryControl(...) { ... }` (before the next method), add:

```cpp
void LibraryControl::appendToSearch(const QString& text) {
    VERIFY_OR_DEBUG_ASSERT(m_pSearchbox) {
        return;
    }
    // getSearchText() returns "" when the box is disabled/empty (never the
    // placeholder), so appending is always safe.
    m_pSearchbox->slotSetSearchText(m_pSearchbox->getSearchText() + text);
}

void LibraryControl::backspaceSearch() {
    VERIFY_OR_DEBUG_ASSERT(m_pSearchbox) {
        return;
    }
    QString text = m_pSearchbox->getSearchText();
    if (text.isEmpty()) {
        return;
    }
    text.chop(1);
    m_pSearchbox->slotSetSearchText(text);
}
```

- [ ] **Step 4: Logic review**

Verify: empty-box append starts a real query (enabled by `slotSetSearchText`); backspace at length 0 is a no-op; both guard `m_pSearchbox`. `QChar`→`QString s(ch)` captures one char per key. `ConfigKey` names match `search_key_<char>` used by the skin (Task 6).
Expected: consistent with the `[Library],search_*` names in `keyboard.xml`.

---

### Task 3: Generate & verify `search-osk.patch`

**Files:**
- Create: `mixxx-patch/search-osk.patch`

- [ ] **Step 1: Generate the diff**

```bash
cd "../mixxx-src/mixxx-2.5.0"
for f in src/widget/wsearchlineedit.h src/widget/wsearchlineedit.cpp \
         src/library/librarycontrol.h src/library/librarycontrol.cpp; do
  git diff --no-index "/c/tmp/osk-baseline/$f" "$f" \
    | sed -e "s|/c/tmp/osk-baseline/|a/|" -e "s|$(pwd)/|b/|" \
    >> "/c/tmp/search-osk.raw.patch"
done
```

(Adjust the `sed` path rewrite so hunks read `--- a/src/...` / `+++ b/src/...` with `-p1` stripping. Confirm each hunk header before proceeding.)

- [ ] **Step 2: Copy into the repo and inspect**

Move the assembled patch to `mixxx-patch/search-osk.patch`. Read it top-to-bottom: four files, sane hunks, LF endings, no stray baseline paths.

- [ ] **Step 3: Dry-run apply against a fresh baseline**

```bash
cd "$(mktemp -d)"
# extract a clean copy of the 5-patch tree the same way CI does, or copy
# ../mixxx-src/mixxx-2.5.0 with the Task 1/2 edits reverted, then:
patch -p1 --dry-run < "<repo>/mixxx-patch/search-osk.patch"
```
Expected: `checking file src/widget/wsearchlineedit.h ... ` (×4) all **succeed**, no offsets rejected.

- [ ] **Step 4: Commit**

```bash
git add mixxx-patch/search-osk.patch
git commit -m "feat(patch): add search-osk.patch — on-screen-keyboard search controls"
```

---

### Task 4: Skin — extract shared library table singleton

**Files:**
- Create: `library_table.xml`
- Modify: `library.xml` (replace the inline `<Library>` block, lines ~83-89)
- Modify: `skin.xml` (add `LibraryTable_Singleton` definition before `Library_Singleton`)

**Interfaces:**
- Produces: singleton `LibraryTable_Singleton` wrapping the single `<Library>` table. Referenced by `library.xml` (Browse) and `search.xml` (Search, Task 6) via `<SingletonContainer>`.

- [ ] **Step 1: Create `library_table.xml`** (the exact `<Library>` block moved out of `library.xml`)

```xml
<Template>
  <Library>
    <ObjectName>Library</ObjectName>
    <SizePolicy>me,me</SizePolicy>
    <BgColor>#000</BgColor>
    <FgColor>#75001a</FgColor>
    <TrackTableBackgroundColorOpacity>0.4</TrackTableBackgroundColorOpacity>
  </Library>
</Template>
```

- [ ] **Step 2: Reference it from `library.xml`**

Replace the inline `<Library>…</Library>` block in `library.xml` with:

```xml
          <SingletonContainer>
            <ObjectName>LibraryTable_Singleton</ObjectName>
          </SingletonContainer>
```

- [ ] **Step 3: Define the singleton in `skin.xml`**

In `skin.xml`, add a new `SingletonDefinition` **before** `Library_Singleton` (so it exists when `library.xml` references it):

```xml
		<SingletonDefinition>
			<ObjectName>LibraryTable_Singleton</ObjectName>
			<Children>
				<Template src="skin:library_table.xml"/>
			</Children>
		</SingletonDefinition>
```

- [ ] **Step 4: XML well-formedness**

Run (if `xmllint` available): `xmllint --noout library_table.xml library.xml skin.xml`
Expected: no output (well-formed). If unavailable, visually confirm balanced tags.

- [ ] **Step 5: Commit**

```bash
git add library_table.xml library.xml skin.xml
git commit -m "refactor(skin): extract shared LibraryTable_Singleton for reuse"
```

---

### Task 5: Skin — key template + keyboard

**Files:**
- Create: `templates/kb_key.xml`
- Create: `keyboard.xml`

**Interfaces:**
- Consumes: controls `[Library],search_key_<char>`, `search_space`, `search_backspace` (Task 2); toggle control `[Skin],show_keyboard` (Task 7).
- Produces: `keyboard.xml` template (self-contained keyboard grid).

- [ ] **Step 1: Create `templates/kb_key.xml`** (one character key)

```xml
<Template>
  <PushButton>
    <ObjectName>KbKey</ObjectName>
    <SizePolicy>me,me</SizePolicy>
    <NumberStates>1</NumberStates>
    <State>
      <Number>0</Number>
      <Text><Variable name="key_label"/></Text>
    </State>
    <Connection>
      <ConfigKey persist="false">[Library],search_key_<Variable name="key_char"/></ConfigKey>
      <EmitOnPressAndRelease>true</EmitOnPressAndRelease>
      <ButtonState>LeftButton</ButtonState>
    </Connection>
  </PushButton>
</Template>
```

- [ ] **Step 2: Create `keyboard.xml`** (rows: digits, QWERTY, ASDF, ZXCV + controls)

```xml
<Template>
  <WidgetGroup>
    <ObjectName>Keyboard</ObjectName>
    <Layout>vertical</Layout>
    <SizePolicy>me,me</SizePolicy>
    <Children>
      <WidgetGroup><ObjectName>KbRow</ObjectName><Layout>horizontal</Layout><SizePolicy>me,me</SizePolicy><Children>
        <Template src="skin:templates/kb_key.xml"><SetVariable name="key_label">1</SetVariable><SetVariable name="key_char">1</SetVariable></Template>
        <Template src="skin:templates/kb_key.xml"><SetVariable name="key_label">2</SetVariable><SetVariable name="key_char">2</SetVariable></Template>
        <Template src="skin:templates/kb_key.xml"><SetVariable name="key_label">3</SetVariable><SetVariable name="key_char">3</SetVariable></Template>
        <Template src="skin:templates/kb_key.xml"><SetVariable name="key_label">4</SetVariable><SetVariable name="key_char">4</SetVariable></Template>
        <Template src="skin:templates/kb_key.xml"><SetVariable name="key_label">5</SetVariable><SetVariable name="key_char">5</SetVariable></Template>
        <Template src="skin:templates/kb_key.xml"><SetVariable name="key_label">6</SetVariable><SetVariable name="key_char">6</SetVariable></Template>
        <Template src="skin:templates/kb_key.xml"><SetVariable name="key_label">7</SetVariable><SetVariable name="key_char">7</SetVariable></Template>
        <Template src="skin:templates/kb_key.xml"><SetVariable name="key_label">8</SetVariable><SetVariable name="key_char">8</SetVariable></Template>
        <Template src="skin:templates/kb_key.xml"><SetVariable name="key_label">9</SetVariable><SetVariable name="key_char">9</SetVariable></Template>
        <Template src="skin:templates/kb_key.xml"><SetVariable name="key_label">0</SetVariable><SetVariable name="key_char">0</SetVariable></Template>
      </Children></WidgetGroup>
      <WidgetGroup><ObjectName>KbRow</ObjectName><Layout>horizontal</Layout><SizePolicy>me,me</SizePolicy><Children>
        <Template src="skin:templates/kb_key.xml"><SetVariable name="key_label">Q</SetVariable><SetVariable name="key_char">q</SetVariable></Template>
        <Template src="skin:templates/kb_key.xml"><SetVariable name="key_label">W</SetVariable><SetVariable name="key_char">w</SetVariable></Template>
        <Template src="skin:templates/kb_key.xml"><SetVariable name="key_label">E</SetVariable><SetVariable name="key_char">e</SetVariable></Template>
        <Template src="skin:templates/kb_key.xml"><SetVariable name="key_label">R</SetVariable><SetVariable name="key_char">r</SetVariable></Template>
        <Template src="skin:templates/kb_key.xml"><SetVariable name="key_label">T</SetVariable><SetVariable name="key_char">t</SetVariable></Template>
        <Template src="skin:templates/kb_key.xml"><SetVariable name="key_label">Y</SetVariable><SetVariable name="key_char">y</SetVariable></Template>
        <Template src="skin:templates/kb_key.xml"><SetVariable name="key_label">U</SetVariable><SetVariable name="key_char">u</SetVariable></Template>
        <Template src="skin:templates/kb_key.xml"><SetVariable name="key_label">I</SetVariable><SetVariable name="key_char">i</SetVariable></Template>
        <Template src="skin:templates/kb_key.xml"><SetVariable name="key_label">O</SetVariable><SetVariable name="key_char">o</SetVariable></Template>
        <Template src="skin:templates/kb_key.xml"><SetVariable name="key_label">P</SetVariable><SetVariable name="key_char">p</SetVariable></Template>
      </Children></WidgetGroup>
      <WidgetGroup><ObjectName>KbRow</ObjectName><Layout>horizontal</Layout><SizePolicy>me,me</SizePolicy><Children>
        <Template src="skin:templates/kb_key.xml"><SetVariable name="key_label">A</SetVariable><SetVariable name="key_char">a</SetVariable></Template>
        <Template src="skin:templates/kb_key.xml"><SetVariable name="key_label">S</SetVariable><SetVariable name="key_char">s</SetVariable></Template>
        <Template src="skin:templates/kb_key.xml"><SetVariable name="key_label">D</SetVariable><SetVariable name="key_char">d</SetVariable></Template>
        <Template src="skin:templates/kb_key.xml"><SetVariable name="key_label">F</SetVariable><SetVariable name="key_char">f</SetVariable></Template>
        <Template src="skin:templates/kb_key.xml"><SetVariable name="key_label">G</SetVariable><SetVariable name="key_char">g</SetVariable></Template>
        <Template src="skin:templates/kb_key.xml"><SetVariable name="key_label">H</SetVariable><SetVariable name="key_char">h</SetVariable></Template>
        <Template src="skin:templates/kb_key.xml"><SetVariable name="key_label">J</SetVariable><SetVariable name="key_char">j</SetVariable></Template>
        <Template src="skin:templates/kb_key.xml"><SetVariable name="key_label">K</SetVariable><SetVariable name="key_char">k</SetVariable></Template>
        <Template src="skin:templates/kb_key.xml"><SetVariable name="key_label">L</SetVariable><SetVariable name="key_char">l</SetVariable></Template>
      </Children></WidgetGroup>
      <WidgetGroup><ObjectName>KbRow</ObjectName><Layout>horizontal</Layout><SizePolicy>me,me</SizePolicy><Children>
        <Template src="skin:templates/kb_key.xml"><SetVariable name="key_label">Z</SetVariable><SetVariable name="key_char">z</SetVariable></Template>
        <Template src="skin:templates/kb_key.xml"><SetVariable name="key_label">X</SetVariable><SetVariable name="key_char">x</SetVariable></Template>
        <Template src="skin:templates/kb_key.xml"><SetVariable name="key_label">C</SetVariable><SetVariable name="key_char">c</SetVariable></Template>
        <Template src="skin:templates/kb_key.xml"><SetVariable name="key_label">V</SetVariable><SetVariable name="key_char">v</SetVariable></Template>
        <Template src="skin:templates/kb_key.xml"><SetVariable name="key_label">B</SetVariable><SetVariable name="key_char">b</SetVariable></Template>
        <Template src="skin:templates/kb_key.xml"><SetVariable name="key_label">N</SetVariable><SetVariable name="key_char">n</SetVariable></Template>
        <Template src="skin:templates/kb_key.xml"><SetVariable name="key_label">M</SetVariable><SetVariable name="key_char">m</SetVariable></Template>
        <PushButton>
          <ObjectName>KbBackspace</ObjectName>
          <SizePolicy>me,me</SizePolicy>
          <NumberStates>1</NumberStates>
          <State><Number>0</Number><Text>&#9003;</Text></State>
          <Connection>
            <ConfigKey persist="false">[Library],search_backspace</ConfigKey>
            <EmitOnPressAndRelease>true</EmitOnPressAndRelease>
            <ButtonState>LeftButton</ButtonState>
          </Connection>
        </PushButton>
        <PushButton>
          <ObjectName>KbSpace</ObjectName>
          <SizePolicy>me,me</SizePolicy>
          <NumberStates>1</NumberStates>
          <State><Number>0</Number><Text>space</Text></State>
          <Connection>
            <ConfigKey persist="false">[Library],search_space</ConfigKey>
            <EmitOnPressAndRelease>true</EmitOnPressAndRelease>
            <ButtonState>LeftButton</ButtonState>
          </Connection>
        </PushButton>
        <PushButton>
          <ObjectName>KbClear</ObjectName>
          <SizePolicy>me,me</SizePolicy>
          <NumberStates>1</NumberStates>
          <State><Number>0</Number><Text>clear</Text></State>
          <Connection>
            <ConfigKey persist="false">[Library],clear_search</ConfigKey>
            <EmitOnPressAndRelease>true</EmitOnPressAndRelease>
            <ButtonState>LeftButton</ButtonState>
          </Connection>
        </PushButton>
        <PushButton>
          <ObjectName>KbDone</ObjectName>
          <SizePolicy>me,me</SizePolicy>
          <NumberStates>2</NumberStates>
          <State><Number>0</Number><Text>Done</Text></State>
          <State><Number>1</Number><Text>Done</Text></State>
          <Connection>
            <ConfigKey persist="false">[Skin],show_keyboard</ConfigKey>
            <ButtonState>LeftButton</ButtonState>
          </Connection>
        </PushButton>
      </Children></WidgetGroup>
    </Children>
  </WidgetGroup>
</Template>
```

- [ ] **Step 2b: XML check**

`xmllint --noout templates/kb_key.xml keyboard.xml`
Expected: no output.

- [ ] **Step 3: Commit**

```bash
git add templates/kb_key.xml keyboard.xml
git commit -m "feat(skin): OEM on-screen QWERTY keyboard for track search"
```

---

### Task 6: Skin — Search page

**Files:**
- Create: `search.xml`

**Interfaces:**
- Consumes: `LibraryTable_Singleton` (Task 4); `keyboard.xml` (Task 5); native `<SearchBox>`; `templates/load_button.xml`; `[Skin],show_keyboard`.

- [ ] **Step 1: Create `search.xml`**

```xml
<Template>
  <WidgetGroup>
    <ObjectName>SearchPage</ObjectName>
    <Layout>vertical</Layout>
    <SizePolicy>me,me</SizePolicy>
    <Children>
      <WidgetGroup>
        <ObjectName>SearchFieldRow</ObjectName>
        <Layout>horizontal</Layout>
        <Size>0me,40f</Size>
        <Children>
          <PushButton>
            <ObjectName>KbShow</ObjectName>
            <Size>44f,0me</Size>
            <NumberStates>2</NumberStates>
            <State><Number>0</Number><Text>&#9000;</Text></State>
            <State><Number>1</Number><Text>&#9000;</Text></State>
            <Connection>
              <ConfigKey persist="false">[Skin],show_keyboard</ConfigKey>
              <ButtonState>LeftButton</ButtonState>
            </Connection>
          </PushButton>
          <SearchBox></SearchBox>
        </Children>
      </WidgetGroup>
      <SingletonContainer>
        <ObjectName>LibraryTable_Singleton</ObjectName>
      </SingletonContainer>
      <WidgetGroup>
        <ObjectName>SearchLoadRow</ObjectName>
        <Layout>horizontal</Layout>
        <Size>0me,44f</Size>
        <Children>
          <Template src="skin:templates/load_button.xml">
            <SetVariable name="channel">1</SetVariable>
          </Template>
          <Template src="skin:templates/load_button.xml">
            <SetVariable name="channel">2</SetVariable>
          </Template>
        </Children>
      </WidgetGroup>
      <WidgetGroup>
        <ObjectName>KeyboardWrap</ObjectName>
        <Layout>vertical</Layout>
        <Size>0me,160f</Size>
        <Children>
          <Template src="skin:keyboard.xml"/>
        </Children>
        <Connection>
          <ConfigKey persist="false">[Skin],show_keyboard</ConfigKey>
          <BindProperty>visible</BindProperty>
        </Connection>
      </WidgetGroup>
    </Children>
  </WidgetGroup>
</Template>
```

- [ ] **Step 2: XML check**

`xmllint --noout search.xml`
Expected: no output.

- [ ] **Step 3: Commit**

```bash
git add search.xml
git commit -m "feat(skin): Search page (search box + shared table + load + keyboard)"
```

---

### Task 7: Skin — wire topbar, stack, and keyboard-visibility default

**Files:**
- Modify: `topbar.xml`
- Modify: `skin.xml`

- [ ] **Step 1: Swap the topbar tab**

In `topbar.xml`, replace the Sampler tab template block:

```xml
          <Template src="skin:tab.xml">
            <SetVariable name="tab_name">Search</SetVariable>
            <SetVariable name="config_key">search</SetVariable>
          </Template>
```

- [ ] **Step 2: Add the Search singleton definition in `skin.xml`**

Replace the `Samplers_Singleton` `SingletonDefinition` with:

```xml
			<SingletonDefinition>
				<ObjectName>Search_Singleton</ObjectName>
				<Children>
					<Template src="skin:search.xml"/>
				</Children>
			</SingletonDefinition>
```

- [ ] **Step 3: Swap the stack page in `skin.xml`**

Replace the samplers `SingletonContainer` in the `WidgetStack` with:

```xml
									<SingletonContainer trigger="[Tab],search" on_hide_select="0">
										<ObjectName>Search_Singleton</ObjectName>
									</SingletonContainer>
```

- [ ] **Step 4: Default the keyboard visible**

In `skin.xml` `<manifest><attributes>`, add:

```xml
				<attribute persist="false" config_key="[Skin],show_keyboard">1</attribute>
```

- [ ] **Step 5: XML check + grep for stale sampler refs**

```bash
xmllint --noout topbar.xml skin.xml
grep -n "Sampler\|samplers" skin.xml topbar.xml   # expect no matches
```
Expected: well-formed; no remaining Sampler tab/stack references (the `[Master],num_samplers` manifest attribute may stay — samplers still exist internally).

- [ ] **Step 6: Commit**

```bash
git add topbar.xml skin.xml
git commit -m "feat(skin): replace Sampler tab with Search tab + wire stack page"
```

---

### Task 8: Skin — OEM theming

**Files:**
- Modify: `style.qss`

- [ ] **Step 1: Append keyboard/search QSS** (reuse the Pioneer palette: accent `#b6294c`, panel `#32323c`, near-black `#000`)

```css
/* --- Track search on-screen keyboard --- */
#SearchPage { background-color: #1a1a20; }
#SearchFieldRow { background-color: #26262e; }
#SearchFieldRow WSearchLineEdit {
    background-color: #0d0d10;
    color: #e6e6e6;
    border: 1px solid #45454f;
    border-radius: 3px;
    padding: 4px 8px;
    font-size: 16px;
}
#Keyboard { background-color: #26262e; }
#KbRow { }
#Keyboard WPushButton {
    background-color: #3a3a44;
    color: #f0f0f0;
    border: 1px solid #4d4d59;
    border-radius: 4px;
    margin: 2px;
    font-size: 15px;
    font-weight: bold;
}
#Keyboard WPushButton:pressed,
#Keyboard #KbKey:pressed { background-color: #b6294c; color: #fff; }
#KbSpace { }
#KbClear, #KbBackspace { color: #ffb3c0; }
#KbDone[value="1"], #KbShow { background-color: #b6294c; }
#SearchLoadRow WPushButton {
    background-color: #75001a; color: #fff; font-weight: bold; border-radius: 4px; margin: 2px;
}
#SearchLoadRow WPushButton:pressed { background-color: #b6294c; }
```

- [ ] **Step 2: Commit**

```bash
git add style.qss
git commit -m "style(skin): OEM theming for search keyboard, field and load row"
```

---

### Task 9: CI wiring

**Files:**
- Modify: `.github/workflows/build-mixxx-deb.yml`
- Modify: `mixxx-patch/VERSION.md`

- [ ] **Step 1: Append the patch apply line** after the `xdj-hardware.patch` line:

```yaml
          patch -p1 < "$GITHUB_WORKSPACE/mixxx-patch/xdj-hardware.patch"
          patch -p1 < "$GITHUB_WORKSPACE/mixxx-patch/search-osk.patch"
```

- [ ] **Step 2: Document patch #6 in `VERSION.md`** — add to the "Patch series" list:

```markdown
6. `search-osk.patch` (added 2026-07-12) — replaces the Sampler tab with a
   track Search tab: adds `WSearchLineEdit::slotSetSearchText()` and
   `[Library],search_key_*` / `search_space` / `search_backspace` push
   controls so the skin's on-screen QWERTY keyboard drives the native search
   box (scoped to the selected folder). Skin-side only otherwise.
```

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/build-mixxx-deb.yml mixxx-patch/VERSION.md
git commit -m "ci: apply search-osk.patch in the build series"
```

---

### Task 10: Build, verify on dev machine, deploy, publish

- [ ] **Step 1: Push master**

```bash
"/c/Program Files/GitHub CLI/gh.exe" repo view ogg755/Pioneered >/dev/null   # sanity/auth
git push origin master
```

- [ ] **Step 2: Trigger CI on the fork**

```bash
"/c/Program Files/GitHub CLI/gh.exe" workflow run build-mixxx-deb.yml --ref master -R ogg755/Pioneered
"/c/Program Files/GitHub CLI/gh.exe" run watch -R ogg755/Pioneered
```
Expected: green build; three debs (mixxx, mixxx-data, mixxx-dbgsym) as artifacts; version `+usbbrowse.r<N>`. If `patch` fails, the run logs name the failing hunk → fix patch, re-push.

- [ ] **Step 3: Dev-machine skin smoke test**

On the Windows dev machine, point Mixxx 2.5 at the reworked skin (copy `Pioneered/` into the Mixxx skins dir) and confirm: topbar shows **Search** (no Sampler); Search page renders with keyboard up; typing filters the list live; **Done**/**⌨** toggles the keyboard and the list reclaims the space; **LOAD 1/2** load the selected row; **clear** empties the box; switching Browse↔Search keeps the same table/selection.
Note: full search behaviour needs the patched build — if testing on stock Mixxx, verify only that the skin loads and keys are inert (no crash).

- [ ] **Step 4: Download debs & stage**

```bash
"/c/Program Files/GitHub CLI/gh.exe" run download <run-id> -R ogg755/Pioneered -D ../pi-deploy/
```

- [ ] **Step 5: Deploy to Pi** — per `docs/pi-deploy.md`: re-verify `apt policy mixxx` (still 2.5.0), copy skin to `~/.mixxx/skins/Pioneered`, `apt-mark unhold` → `apt install ./*.deb` (all three) → `apt-mark hold`. Restart Mixxx.

- [ ] **Step 6: Field checks on the Pi**
  1. Topbar third tab reads **Search**; Sampler gone.
  2. Select a USB folder in Browse; switch to Search; type — list filters to matches in that folder.
  3. Load a searched track to each deck via LOAD 1 / LOAD 2.
  4. Done/⌨ toggle works; clear resets; backspace deletes one char; space works.

- [ ] **Step 7: Publish GitHub release** (matches the r14 precedent)

```bash
"/c/Program Files/GitHub CLI/gh.exe" release create v2.5.0-r<N> \
  -R ogg755/Pioneered \
  --target master \
  --title "Pioneered v2.5.0-r<N> — track search + on-screen keyboard" \
  --notes "Adds a Search tab (replacing Sampler) with an OEM-themed on-screen QWERTY keyboard that drives Mixxx's native search over the selected folder. See docs/superpowers/specs/2026-07-12-track-search-osk-design.md." \
  ../pi-deploy/mixxx*.deb
```
Expected: release page live with the three arm64 debs attached.

---

## Self-Review

**Spec coverage:** topbar swap (T7) ✓; native search reuse via SearchBox + shared table (T4, T6) ✓; C++ append/backspace/space controls + slot (T1, T2) ✓; clear reuses `clear_search` (T5) ✓; keyboard QWERTY+numbers (T5) ✓; toggle visibility skin-only (T5, T6, T7) ✓; no folder switching on Search page (T6 — no sidebar) ✓; unpatched-load safety (all skin buttons `persist="false"` control connections, inert without patch) ✓; CI order + VERSION (T9) ✓; testing/build/deploy/publish (T10) ✓.

**Placeholder scan:** `<N>`/`<run-id>`/`<repo>` are runtime values resolved at execution, not unspecified design — acceptable. No TBD/TODO/"handle edge cases" left.

**Type consistency:** `slotSetSearchText(const QString&)` defined T1, called T2. Control names `search_key_<char>`/`search_space`/`search_backspace` defined T2, referenced identically in `kb_key.xml`/`keyboard.xml` T5. `LibraryTable_Singleton` defined T4, referenced T4 (library.xml) + T6 (search.xml). `[Skin],show_keyboard` bound T5/T6/T7, defaulted T7.
