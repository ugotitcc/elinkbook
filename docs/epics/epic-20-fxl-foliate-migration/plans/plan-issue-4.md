# Epic 20 Issue 4 — `ReaderScreen` 浮動按鈕群組合併，移除 FXL/流式雙軌 UI 分支 實作計劃

> **給執行者（agentic worker）的提示：** 建議使用 `superpowers:subagent-driven-development`（推薦）或 `superpowers:executing-plans` 逐工單執行本計劃。工單內的步驟以核取方塊（`- [ ]`）追蹤完成狀態。

**目標：** `reader_fixed_layout_*`（4 顆，`epic-18` Issue 15 新增）與 `reader_foliate_*`（6 顆按鈕 + 2 個純顯示元件，既有）目前是兩組平行維護、依 FXL/流式分流建構的浮動 chrome，Issue 2/3 完成後 EPUB 一律經 `FoliateEpubReaderView` 渲染，這個分流已無意義——合併為一組，FXL 書籍藉此「免費」取得目錄／跳頁兩項既有缺少的功能。

**依賴：** Issue 2、3（皆已合併，`main`）。

**架構（`spec.md`「核心介面異動」第 3 節）：** 不新增元件、不新增資料模型，純粹是既有兩組 UI 分支的合併化簡，以及修正一個因分支未同步更新而產生的既有 bug（見下方）。

**已查證的關鍵技術事實（避免計劃內容基於臆測，皆已對照 `reader_screen.dart` 現況逐行確認）：**

- **兩組按鈕完整盤點**（`reader_screen.dart:1490-1726`）：
  - `reader_fixed_layout_*`（4 顆，皆 gated `_isFixedLayout && _chromeVisible`，2 顆另加 `widget.bookmarksRepository != null`）：`back_button`（16,左16）、`settings_button`（16,右16，呼叫 `_openFxlSettings`）、`notes_button`（72,右16）、`bookmark_toggle_button`（128,右16）。
  - `reader_foliate_*`（6 顆按鈕 + 2 個純顯示元件，皆 gated `format == BookFormat.epub && _dispatchedIsFixedLayout == false && _chromeVisible`，部分另加 `bookmarksRepository != null`）：`back_button`（16,左16）、`toc_button`（16,右16）、`settings_button`（72,右16，呼叫 `_openLayoutSettings`）、`bookmark_toggle_button`（128,右16）、`notes_button`（184,右16）、`progress_button`（240,右16，呼叫 `_openFoliateProgressSheet`）、`header_text`（頁首章節名稱）、`progress_text`（頁尾頁碼純顯示）。
  - 兩組的 `back`／`bookmark_toggle`／`notes` 按鈕圖示、tooltip、handler **完全相同**，只差 Key 名稱與（`notes`）垂直位置——`reader_foliate_*` 這組已經是「涵蓋 `reader_fixed_layout_*` 全部功能 + 額外 TOC/進度」的超集合，故合併策略是**直接刪除 `reader_fixed_layout_*` 整組、放寬 `reader_foliate_*` 的 gating 條件**，而非另建第三組或逐一比對合併。
- **settings 按鈕合併後仍需保留分流，不能整組去掉判斷式**：`_openFxlSettings()`（:590）開啟 `FxlSettingsSheet`（FXL 專屬，目前僅 `dualPageMode`），`_openLayoutSettings()`（:562）開啟 `ReaderSettingsSheet`（流式專屬的完整版面設定：字型/邊界/欄數等，對 FXL 書籍大多數欄位無意義）。合併後單一 settings 按鈕的 `onPressed` 必須依 `_isFixedLayout` 分流呼叫兩者之一，這是**唯一**需要保留條件判斷的按鈕；其餘 5 顆（`toc`／`bookmark_toggle`／`notes`／`progress`／2 個顯示元件）合併後行為對 FXL／流式完全一致，不需要分流。
- **TOC／進度跳頁對 FXL 書籍預期可直接運作，非未開發功能**：`_handleFoliateLayoutResolved`（`:861` 起，Issue 2 已確認此方法對 FXL／流式書籍皆會被呼叫）已無條件呼叫 `FoliateEpubReaderView.loadTableOfContents()` 背景抓取目錄；`_epubPositionInfo`（驅動 `_openFoliateProgressSheet`／`_buildFoliateProgressText` 的 `pageIndex`/`totalPages`）來自 `onLocatorChanged`（`main.js` relocate 事件的 `location.current`/`location.total`），與 Issue 2 審查發現的「頁尾字元數統計缺口」是**完全不同的機制**（那個缺口指的是另一條已死的舊路徑 `_buildEpubFooter`/`onCharacterCountReady`/`_totalCharacterCount`，僅 `!_isFixedLayout` 才會用到、且 `FoliateEpubReaderView` 從不呼叫 `onCharacterCountReady`，此路徑自 `epic-17` 起即已是死碼，與本 Issue 無關，不在本工單處理範圍——如需清理留給 Issue 5 或另立工單評估）。放寬 gating 後，TOC／跳頁按鈕預期能對 FXL 書籍直接生效，惟目錄內容對多數純圖片漫畫可能是空清單（書籍本身結構使然，非缺陷），仍需真機驗證確認按鈕可用性與跳頁互動本身正確。
- **`_sendDecorationsToNative()`（`:993-1018`）是本工單真正修正的既有 bug**：目前依 `_dispatchedIsFixedLayout == true` 呼叫 `EpubReaderView.setDecorations(_epubReaderViewKey, ...)`——但 `EpubReaderView` widget 自 Issue 2 起已無任何路徑建構，`_epubReaderViewKey.currentState` 恆為 `null`，此呼叫靜默無效（已於 Issue 2 審查報告記錄為已知落差，`reader_screen.dart` 內 `_handleFoliateLayoutResolved` 註解也已誠實記載此現況）。改為與 `_jumpToEpubLocator()`（`:660-663`，Issue 2 已修正的相同分派模式先例，直接可比照）一致，無條件呼叫 `FoliateEpubReaderView.setDecorations(_foliateEpubReaderViewKey, decorations)`——**這代表 FXL 書籍的劃線/備註疊圖，從本工單起才第一次真正生效**（先前一直靜默失敗），是本工單最具體的功能性修正，非純 UI 整併。
- **Scaffold 頂層 `appBar:` 三元判斷式（`:1278-1286`）不需要修改**：目前條件 `_isFixedLayout || !_chromeVisible || (format == BookFormat.epub && _dispatchedIsFixedLayout == false)` 已經讓 FXL（經 `_isFixedLayout`）與流式（經 `_dispatchedIsFixedLayout == false`）兩種 EPUB 都導出 `appBar: null`，兩個子句合併起來已涵蓋全部 EPUB 情況，不受本工單影響，不需簡化或合併（簡化風險大於效益，予以保留）。
- **既有測試現況**：`reader_screen_test.dart` 含 25 處 `reader_fixed_layout_*` 斷言、34 處 `reader_foliate_*` 斷言（`grep -c` 確認），需逐一審視：前者多數需整段移除（widget 不存在了），後者需檢查其中「FXL 書籍時斷言 `reader_foliate_*` 不存在」這類測試需要反轉為「存在」。

## Global Constraints

- `_isFixedLayout`（書本是否為 FXL，執行期由原生回報，Issue 2 後與引擎選擇脫鉤，純粹是版面事實）仍是合法、需要保留的判斷依據，本工單移除的是 `_dispatchedIsFixedLayout == false`／`_isFixedLayout` 拿來決定「建構哪一組按鈕」的**分流**，不是移除 `_isFixedLayout` 這個欄位或它在 settings 分流的合理使用。
- 不擴大範圍去清理 `_buildEpubFooter`／`onCharacterCountReady`／`_totalCharacterCount` 這條已死的舊路徑（見上方查證），如發現與本工單有衝突再回頭評估，預設維持現狀不動。
- 測試素材沿用 `tmp/一弦定音.epub`；真機固定使用 `3CEF42ECD491687`。

---

## 檔案結構

- Modify：`app/lib/screens/reader_screen.dart`
- Modify：`app/test/screens/reader_screen_test.dart`

---

### Task 1：刪除 `reader_fixed_layout_*` 按鈕群組，放寬 `reader_foliate_*` 群組 gating

**Files:**
- Modify：`app/lib/screens/reader_screen.dart`

**Interfaces:**
- Consumes：既有 `_isFixedLayout`／`_chromeVisible`／`widget.bookmarksRepository` 欄位，`_openFxlSettings`／`_openLayoutSettings` 既有方法
- Produces：FXL 書籍取得完整的 6 按鈕 + 2 顯示元件 chrome（含先前缺少的目錄／跳頁），移除重複的 4 按鈕群組

- [ ] **Step 1：刪除整段 `reader_fixed_layout_*` `Positioned` 區塊**

刪除 `reader_screen.dart:1490-1567`（`back_button`／`settings_button`／`bookmark_toggle_button`／`notes_button` 四個 `if (_isFixedLayout && _chromeVisible) Positioned(...)` 區塊，含 `bookmarksRepository != null` 那兩個變體）。

- [ ] **Step 2：`reader_foliate_*` 六個按鈕 + 2 個顯示元件的 gating 條件移除 `_dispatchedIsFixedLayout == false` 子句**

`reader_screen.dart:1574-1726` 範圍內，每一個 `if (format == BookFormat.epub && _dispatchedIsFixedLayout == false && ...)` 改為 `if (format == BookFormat.epub && ...)`（直接移除 `_dispatchedIsFixedLayout == false &&` 這個子句，其餘條件如 `_chromeVisible`／`widget.bookmarksRepository != null`／`showHeader`／`showFooter` 皆保留不動）。共 8 處（`back`／`toc`／`settings`／`bookmark_toggle`／`notes`／`progress`／`header_text` 顯示條件／`footer` 顯示條件）。

- [ ] **Step 3：`reader_foliate_settings_button` 的 `onPressed` 改為依 `_isFixedLayout` 分流**

```dart
onPressed: _isFixedLayout
    ? _openFxlSettings
    : (_autoDetectedWritingMode == null ? null : _openLayoutSettings),
```

（原本 `reader_foliate_settings_button` 的 `onPressed: _autoDetectedWritingMode == null ? null : _openLayoutSettings` 只覆蓋流式情境；FXL 情境呼叫 `_openFxlSettings` 不依賴 `_autoDetectedWritingMode`——比照原 `reader_fixed_layout_settings_button` 的既有寫法，該按鈕本來就無此前置條件。）

- [ ] **Step 4：確認 `reader_foliate_toc_button`／`reader_foliate_progress_button` 的既有 `onPressed`/enable 條件對 FXL 書籍語意仍然正確**

`toc_button` 現有條件 `(_autoDetectedWritingMode == null || !_tocLoaded) ? null : _openToc`——`_autoDetectedWritingMode` 與 `_tocLoaded` 皆由 `_handleFoliateLayoutResolved` 設定（已查證對 FXL/流式書籍皆會呼叫），理論上不需修改，本 Step 純粹是程式碼走讀確認，不預期產生程式碼異動；若走讀發現有 FXL 專屬的未覆蓋情況，於此處記錄並視情況新增條件。`progress_button` 同理（`onPressed: _openFoliateProgressSheet` 本身無 enable 條件，`_buildFoliateEpubFooter` 內部已有 `totalPages <= 0` 的空清單防呆）。

---

### Task 2：修正 `_sendDecorationsToNative()` 對 FXL 書籍的無效分派（既有 bug 修正）

**Files:**
- Modify：`app/lib/screens/reader_screen.dart`

**Interfaces:**
- Consumes：`_foliateEpubReaderViewKey`（既有欄位）
- Produces：FXL 書籍劃線/備註疊圖第一次真正生效（先前透過 `EpubReaderView.setDecorations` 靜默無效）

- [ ] **Step 1：`_sendDecorationsToNative()`（`:993-1018`）移除 `_dispatchedIsFixedLayout` 三元分派，改為無條件呼叫 `FoliateEpubReaderView.setDecorations`**

比照 `_jumpToEpubLocator()`（`:660-663`，Issue 2 已建立的相同修正先例）：

```dart
void _sendDecorationsToNative() {
  if (!mounted) return;
  // ...既有組裝 decorations 清單的邏輯不變...
  FoliateEpubReaderView.setDecorations(_foliateEpubReaderViewKey, decorations);
}
```

移除 `if (_dispatchedIsFixedLayout == true) { EpubReaderView.setDecorations(...) } else { ... }` 整個三元分派，`EpubReaderView` 相關 import 若因此變成未使用需一併檢查（`epub_reader_view.dart` 檔案本身留給 Issue 5 清理，此處僅確認 `reader_screen.dart` 內是否還有其他地方使用到該 import，避免誤刪）。

- [ ] **Step 2：`_handleFoliateLayoutResolved()` 的既有註解同步更新**

該方法目前的註解（Issue 2 審查回應新增）誠實記載了「`_sendDecorationsToNative` 目前仍依 `_dispatchedIsFixedLayout` 分派...FXL 書籍此刻實際上尚未取得真正生效的劃線/備註疊圖，這是已知、留待 Issue 4...解決的缺口」——本 Step 完成後這個缺口已解決，更新該段註解反映新現況（劃線/備註疊圖對 FXL 書籍已生效），避免文件與程式碼不同步。

---

### Task 3：測試盤點與改寫

**Files:**
- Modify：`app/test/screens/reader_screen_test.dart`

**Interfaces:**
- Consumes：Task 1/2 完成後的按鈕群組與分派邏輯
- Produces：測試覆蓋合併後的實際行為，不遺漏也不留下對已刪除 widget 的斷言

- [ ] **Step 1：移除或改寫全部 25 處 `reader_fixed_layout_*` 斷言**

`grep -n "reader_fixed_layout_" test/screens/reader_screen_test.dart` 逐一檢視：斷言「FXL 書籍時 `reader_fixed_layout_*` 存在」的測試案例，若同一案例情境（FXL 書籍、對應功能）在 `reader_foliate_*` 測試組已有等效覆蓋，直接移除該測試案例；若沒有等效覆蓋（例如某個互動情境只在 `reader_fixed_layout_*` 測試組出現過），改寫為斷言對應的 `reader_foliate_*` Key，不遺漏原本驗證的行為。

- [ ] **Step 2：檢視全部 34 處 `reader_foliate_*` 斷言，找出「FXL 書籍時斷言不存在」需反轉的案例**

`grep -n "reader_foliate_" test/screens/reader_screen_test.dart` 逐一檢視，特別留意 `findsNothing`／`isNull`／否定語意的斷言搭配 FXL 書籍情境（`isFixedLayout: true`）——這類測試在 Task 1 Step 2 之後語意會反轉（Task 1 完成後 FXL 書籍也會顯示這些按鈕），需改為 `findsOneWidget` 等正向斷言。

- [ ] **Step 3：新增 `reader_foliate_settings_button` 分流測試**

新增測試案例：FXL 書籍（`isFixedLayout: true`）點擊 `reader_foliate_settings_button` 開啟 `FxlSettingsSheet`（而非 `ReaderSettingsSheet`）；流式書籍點擊同一按鈕開啟 `ReaderSettingsSheet`。比照既有 `find.byType(FxlSettingsSheet)`／`find.byType(ReaderSettingsSheet)` 斷言模式（若既有測試檔已有類似寫法可直接參考）。

- [ ] **Step 4：新增/確認 `_sendDecorationsToNative` 對 FXL 書籍呼叫 `FoliateEpubReaderView.setDecorations` 的測試**

比照既有「流式 EPUB 開書後，自動載入既有劃線/備註並透過 `FoliateEpubReaderView.setDecorations` 送給原生端」測試案例（`test/screens/reader_screen_test.dart` 已有，Issue 2 引入），新增等效的 FXL 書籍版本（`isFixedLayout: true`），確認呼叫的是 `FoliateEpubReaderView.setDecorations(_foliateEpubReaderViewKey, ...)` 而非（已不存在路徑的）`EpubReaderView.setDecorations`。

執行 `flutter test test/screens/reader_screen_test.dart` 確認全部通過。

---

### Task 4：真機驗證、文件更新、送出 PR

**Files:**
- Modify：`docs/epics/epic-20-fxl-foliate-migration/design.md`、`issues.md`、`docs/epics.md`

**Interfaces:**
- Consumes：Task 1-3 已完成
- Produces：合併回 `main` 的統一 chrome

- [x] **Step 1：全套測試**（flutter analyze 0 issues, flutter test 730/730 通過）

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter analyze
flutter test
```

須為 0 issues／全部通過，且不得比 Issue 3 合併後的基準測試數少（回歸檢查）。

- [x] **Step 2：建置並安裝至真機（`3CEF42ECD491687`）**（APK built + installed）

```bash
flutter build apk --debug
adb -s 3CEF42ECD491687 install -r build/app/outputs/flutter-apk/app-debug.apk
```

- [x] **Step 3：真機驗證**（2026-07-31 人類確認通過，截圖佐證）

用 `tmp/一弦定音.epub`（FXL）：
1. 返回／版面設定（確認開啟 `FxlSettingsSheet`，不是流式版面設定）／書籤／筆記四項既有功能透過合併後的單一按鈕群組正常運作，行為與 Issue 2/3 之前的 `reader_fixed_layout_*` 版本一致。✅
2. **目錄按鈕**（先前 FXL 沒有）：確認可點擊開啟目錄（內容為空清單亦視為正常，取決於書籍本身結構），無例外。✅
3. **跳頁/進度按鈕**（先前 FXL 沒有）：確認可開啟跳頁 Bottom Sheet，頁碼顯示（20/93）與拖曳跳頁正確運作。✅
4. **劃線/備註疊圖驗證**（Task 2 的核心修正）：對此書新增至少一筆劃線與一筆備註，確認畫面上有疊加顯示（先前這一步應完全無視覺效果，此為驗證 bug 修正是否真的生效的關鍵判準）。✅

用一本流式 EPUB（沿用既有測試素材）：確認上述所有功能無回歸。✅

- [x] **Step 4：依結果更新 `design.md`／`issues.md`／`docs/epics.md`**（commit `ff48fc7`）

- [x] **Step 5：Commit（於獨立 feature branch，比照 Issue 2/3 branch 命名慣例 `feature/epic-20-issue-4-*`）**（4 commits `4db9b0d`→`4c13db3`→`f767ff9`→`ff48fc7`）

- [x] **Step 6：送出 code review（`superpowers:requesting-code-review`），依審查結果修正後開 PR**（PR 待建立）

---

## 相關佐證

- `docs/epics/epic-20-fxl-foliate-migration/spec.md`「核心介面異動」第 3 節
- `docs/adr/0017-fxl-migrate-to-foliate-js.md`
- `tmp/epic-20/issue2-implementation-review.md`（`_sendDecorationsToNative` 既有落差的原始發現）
- `app/lib/screens/reader_screen.dart:660-663`（`_jumpToEpubLocator`，Issue 2 已建立的相同修正先例）、`:848-884`（`_handleFoliateLayoutResolved`，含待同步更新的既有註解）、`:990-1018`（`_sendDecorationsToNative`）、`:1278-1286`（Scaffold `appBar:` 判斷式，查證後確認不需修改）、`:1490-1726`（兩組按鈕現況）、`:562-599`（`_openLayoutSettings`／`_openFxlSettings`）
