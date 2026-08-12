# Epic 18 Issue 23 — 頁首/頁尾行為調整（5 項需求） 實作計劃

> **給執行者（agentic worker）的提示：** 建議使用 `superpowers:subagent-driven-development`（推薦）或 `superpowers:executing-plans` 逐工單執行本計劃。工單內的步驟以核取方塊（`- [x]`）追蹤完成狀態。

**目標：** 實作 5 項頁首/頁尾行為調整需求（`issues.md` Issue 23）：流式 EPUB 上邊界預設改 32、FXL 補齊頁首/頁尾開關、兩種格式（含 PDF）預設改為關閉、直排頁首移至右上角並與 FAB 互斥、頁首文字改顯示第一層章節名稱或書名。全部修改點已於 `/diagnose` 階段查證（`reviews/bugfix-repro-header-footer.md`），本計劃聚焦落實與測試更新。

**依賴：** 無。

**已查證的關鍵技術事實（避免計劃內容基於臆測，逐項對應 `issues.md` Issue 23 範圍）：**

- **項目 1**：`app/android/app/src/main/assets/foliate/main.js:222`，`const marginTopPx = typeof prefs.marginTop === 'number' ? prefs.marginTop : 64`——此行上方 `main.js:161` 明確標註「以下為流式（reflowable）書籍的既有邏輯」，FXL 不受影響。
- **項目 2**：`app/lib/screens/fxl_settings_sheet.dart` 目前完全沒有 `showHeader`/`showFooter` 控制項；`reader_settings_sheet.dart:306-318` 已有可直接比照的 `SwitchListTile` 寫法；`fxl_settings_sheet.dart` 現有的 `_fullscreen` 開關（同檔案 `:92-100`）是最貼近的既有模式（`late bool` 欄位 + `initState` 讀取 `?? 預設值` + `_notifyChanged()` 呼叫 `widget.prefs.copyWith(...)`）。
- **項目 3**：唯一正式預設值來源 `app/lib/reader/reader_prefs_manager_impl.dart:179-180`（`book.showHeader ?? true`／`book.showFooter ?? true`）；PDF 與 EPUB 共用同一個 `ResolvedPreferences.showFooter` 欄位與這一處解析點（`pdf_settings_sheet.dart:88` 直接讀寫同一個 `showFooter`，無獨立分支）。另有多個「`_resolved` 尚未載入完成前」的防呆用 `?? true` 站點：`reader_screen.dart:1235,1545,1553,1623`、`reader_settings_sheet.dart:90-91,120-121`。既有測試 `app/test/reader/reader_prefs_manager_test.dart:58-60`（預設值測試）目前斷言 `isTrue`，需改為 `isFalse`。
- **項目 4**：頁尾既有的直排寫法（`reader_screen.dart:1552-1569`）用 `RotatedBox(quarterTurns: 1)` + `Positioned(left: 16, bottom: 16)`，頁首應比照但改 `right: 16, top: 16, bottom: 16`（右上角，`bottom` 為計劃審查後新增）。**計劃審查發現**：頁尾的直排寫法只設 `left`/`bottom` 兩邊，因為頁尾內容永遠是 `"$currentPage/$totalPages"` 這種固定短字串，從未真正測試過長文字情境；頁首的章節名稱／書名（Task 5 回退情境）是任意長度的使用者/書籍內容字串，若只設 `right`/`top` 兩邊（未設 `bottom`），`RotatedBox` 交換寬高約束後 `Text` 拿到的有效寬度會是無界的，`maxLines: 1`／`overflow: TextOverflow.ellipsis`（`reader_screen.dart:1697-1701`）不會生效，故頁首的直排分支需額外加 `bottom: 16` 提供有界寬度（與橫排分支用 `left: 72, right: 72` 提供有界寬度是同一種機制），不是頁尾既有模式的單純複製。頁首目前的顯示條件（`reader_screen.dart:1545`）完全沒有 `_chromeVisible` 判斷。**此變更會反轉 `issues.md` Issue 13 的既有決策**（Issue 13 刻意移除頁首的 `_chromeVisible` 判斷，讓頁首「常駐顯示、不受沉浸模式影響」）——本次不是恢復 Issue 13 之前「只在 `_chromeVisible == true` 時顯示」的行為（那樣會跟 FAB 同時出現），而是新的第三種狀態「只在 `_chromeVisible == false` 時顯示」，與 FAB 完全互斥。**只改頁首，頁尾（進度文字）維持 Issue 13 的常駐顯示決策不變。** 既有測試 `app/test/screens/reader_screen_test.dart:3799`（`'流式 EPUB：沉浸模式收起選單（_chromeVisible=false）時，頁首文字仍常駐顯示...（Issue 13）'`）在新行為下**依然成立**（chrome 隱藏時頁首仍顯示），但 `reader_screen_test.dart:3757`（`'流式 EPUB：頁眉純顯示章節名稱...'`）目前用 `ReaderScreen` 預設初始狀態（`_chromeVisible` 預設 `true`，未主動切換）並斷言 `headerFinder findsOneWidget`——這個測試在新行為下會失敗（chrome 可見時頁首應改為 `findsNothing`），需要修正。
- **項目 5**：`_buildFoliateHeaderText()`（`reader_screen.dart:1684-1704`）用 `currentPath.last.title`（最深層章節），找不到時寫死 `'閱讀器'`。`ReaderScreen` 目前沒有管道取得書名，`library_screen.dart:402-412` 的 `_openBook(Book book)` 建構 `ReaderScreen` 時手上已有完整 `Book` 物件（`filePath`/`bookId` 正是從這裡取的），新增 `bookTitle` 建構參數直接傳入 `book.title` 即可，不需要新增 `LibraryRepository` 查詢方法。`_buildAppBarTitle()`（`reader_screen.dart:1234-1257`）雖有類似邏輯，但已查證 EPUB 格式的 `Scaffold.appBar` 恆為 `null`（`reader_screen.dart:1212-1220`），此方法實質只服務 PDF（PDF 走固定靜態文字分支），**不需要修改**。`CLAUDE.md`「`ReaderScreen` 對外的公開建構參數」段落需同步更新（新增性質，不影響既有參數相容性）。

## Global Constraints

- **項目 4 與項目 3 的變更會讓多個既有測試失敗，須逐一盤點修正，不得略過**（見上方已查證清單，`reader_prefs_manager_test.dart:58-60`、`reader_screen_test.dart:3757` 一帶）。
- **只改頁首，不動頁尾（進度文字）既有的 Issue 13 常駐顯示決策**——`reader_screen.dart:1552-1569`（頁尾 `Positioned`）本次不修改。
- **`_buildAppBarTitle()`（`reader_screen.dart:1234-1257`）不在本次修改範圍**（已查證只服務 PDF，PDF 走固定文字分支）。
- **項目 5 新增 `ReaderScreen.bookTitle` 建構參數為新增性質**，不得移除或變更既有 `filePath`／`bookId`／`prefsRepository` 等既有公開參數的簽章。
- **`CLAUDE.md` 為專案根目錄下的檢查點文件**，項目 5 完成後須同步更新其「`ReaderScreen` 對外的公開建構參數」段落，這是專案既有慣例（文件與程式碼同步）。
- 全部改動完成後跑 `flutter analyze`／`flutter test` 全數通過，缺一不可。

---

## 檔案結構

- Modify：`app/android/app/src/main/assets/foliate/main.js`（項目 1）
- Modify：`app/lib/screens/fxl_settings_sheet.dart`（項目 2）
- Modify：`app/lib/reader/reader_prefs_manager_impl.dart`、`app/lib/screens/reader_screen.dart`、`app/lib/screens/reader_settings_sheet.dart`（項目 3）
- Modify：`app/lib/screens/reader_screen.dart`（項目 4）
- Modify：`app/lib/screens/reader_screen.dart`、`app/lib/screens/library_screen.dart`、`CLAUDE.md`（項目 5）
- Modify：`app/test/reader/reader_prefs_manager_test.dart`、`app/test/screens/reader_screen_test.dart`、`app/test/screens/fxl_settings_sheet_test.dart`、`app/test/screens/library_screen_test.dart`（若有斷言 `ReaderScreen(...)` 建構參數的既有測試）

---

### Task 1：流式 EPUB 上邊界預設改 32

**Files:**
- Modify：`app/android/app/src/main/assets/foliate/main.js`

**Interfaces:**
- Consumes：`prefs.marginTop`（既有）
- Produces：無新介面，純常數值變更

- [x] **Step 1：修改預設值**

`main.js:222`：

```js
const marginTopPx = typeof prefs.marginTop === 'number' ? prefs.marginTop : 32
```

（原本 `64` 改為 `32`；同行註解上方 `main.js:218` 提到「未設定時的預設值（64px/16px）延續 Issue 4 當初為修正直排頂端裁切問題而定的數值」，此段註解需同步訂正為 `32px`，避免文件與程式碼不一致。）

- [x] **Step 2：確認無既有測試斷言這個數字**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
grep -rn "64" test/ | grep -i margin
```

若有斷言 `marginTop` 預設為 `64` 的既有測試，同步改為 `32`。

---

### Task 2：FXL 補齊頁首/頁尾開關

**Files:**
- Modify：`app/lib/screens/fxl_settings_sheet.dart`
- Modify：`app/test/screens/fxl_settings_sheet_test.dart`

**Interfaces:**
- Consumes：`BookReaderPrefs.showHeader`/`showFooter`（既有欄位）
- Produces：`FxlSettingsSheet` 新增兩個可切換的 `SwitchListTile`

- [x] **Step 1：`_FxlSettingsSheetState` 新增欄位與初始化**

比照既有 `_fullscreen` 欄位模式（`fxl_settings_sheet.dart:27,33,39`）：

```dart
late bool _showHeader;
late bool _showFooter;
```

`initState()` 新增：

```dart
_showHeader = widget.prefs.showHeader ?? false;  // 見 Task 3，預設改為 false
_showFooter = widget.prefs.showFooter ?? false;
```

- [x] **Step 2：`_notifyChanged()` 擴充**

```dart
void _notifyChanged() {
  widget.onChanged(widget.prefs.copyWith(
    dualPageMode: _dualPageMode,
    fullscreen: _fullscreen,
    showHeader: _showHeader,
    showFooter: _showFooter,
  ));
}
```

- [x] **Step 3：`build()` 新增兩個 `SwitchListTile`**

比照 `reader_settings_sheet.dart:306-318` 的文字與既有 `fxl_settings_fullscreen` 開關的 Key 命名慣例，加在既有 `全螢幕模式` 開關之後：

```dart
SwitchListTile(
  key: const Key('fxl_settings_show_header'),
  title: const Text('顯示頁首'),
  value: _showHeader,
  onChanged: (v) => setState(() {
    _showHeader = v;
    _notifyChanged();
  }),
),
SwitchListTile(
  key: const Key('fxl_settings_show_footer'),
  title: const Text('顯示頁尾'),
  value: _showFooter,
  onChanged: (v) => setState(() {
    _showFooter = v;
    _notifyChanged();
  }),
),
```

- [x] **Step 4：新增/調整測試**

`app/test/screens/fxl_settings_sheet_test.dart` 新增測試：驗證初始狀態依 `prefs.showHeader`/`showFooter` 正確顯示、切換後 `onChanged` 回呼收到正確的 `copyWith` 結果（比照既有 `fxl_settings_fullscreen` 測試案例的寫法）。

---

### Task 3：兩種格式（含 PDF）預設改為關閉

**Files:**
- Modify：`app/lib/reader/reader_prefs_manager_impl.dart`
- Modify：`app/lib/screens/reader_screen.dart`
- Modify：`app/lib/screens/reader_settings_sheet.dart`
- Modify：`app/test/reader/reader_prefs_manager_test.dart`

**Interfaces:**
- Consumes：`BookReaderPrefs.showHeader`/`showFooter`（可為 null 的每書覆寫值）
- Produces：`ResolvedPreferences.showHeader`/`showFooter` 預設值由 `true` 改為 `false`

- [x] **Step 1：修改正式預設值來源**

`reader_prefs_manager_impl.dart:179-180`：

```dart
showHeader: book.showHeader ?? false,
showFooter: book.showFooter ?? false,
```

- [x] **Step 2：修改防呆用初始展示值，避免載入瞬間閃爍**

`reader_screen.dart:1235,1545,1553,1623`（`_resolved?.showHeader ?? true` / `_resolved?.showFooter ?? true`）與 `reader_settings_sheet.dart:90-91,120-121`（`_showHeader = widget.prefs.showHeader ?? true` / `_showFooter = widget.prefs.showFooter ?? true`），全數改 `?? true` → `?? false`。

**逐一確認每一處改動不影響其餘邏輯**（例如 `reader_screen.dart:1235` 是 `_buildAppBarTitle` 的 `showHeader` 判斷，PDF 恆為 `false` 不受影響；`:1545` 是本計劃 Task 4 也會改動的同一行，注意兩個 Task 的改動疊加，實作順序建議先做本 Task 再做 Task 4，避免同一行改兩次互相覆蓋）。

- [x] **Step 3：確認 PDF 共用同一解析路徑**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
grep -n "showFooter" lib/screens/pdf_settings_sheet.dart lib/reader/reader_prefs_manager_impl.dart
```

確認 `pdf_settings_sheet.dart` 的 `showFooter` 讀寫確實共用 `reader_prefs_manager_impl.dart:180` 同一個解析點（無獨立的 PDF 專屬預設值分支）。若發現有獨立分支，一併修正為 `?? false`。

- [x] **Step 4：更新既有測試**

`app/test/reader/reader_prefs_manager_test.dart:58-60`：

```dart
expect(resolved.showHeader, isFalse);
expect(resolved.showFooter, isFalse);
```

（該測試案例本身標題為「預設值」測試，語意不變，只改期望值。）

- [x] **Step 5：盤點 `reader_screen_test.dart` 其餘依賴預設值的既有測試**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter test test/screens/reader_screen_test.dart 2>&1 | grep -i "fail\|expect"
```

先跑一次測試觀察哪些既有案例因預設值變更而失敗（多數既有測試已明確透過 `BookReaderPrefs(showHeader: ..., showFooter: ...)` 指定覆寫值，預期不受影響；只有測試「未指定覆寫時的預設行為」的案例才會失敗），逐一確認是否為預期內的行為變更並修正斷言（非略過或刪除測試）。

---

### Task 4：直排頁首移至右上角，與 FAB 互斥

**Files:**
- Modify：`app/lib/screens/reader_screen.dart`
- Modify：`app/test/screens/reader_screen_test.dart`

**Interfaces:**
- Consumes：`_chromeVisible`（既有欄位）、`_resolved?.writingMode`（既有欄位）
- Produces：頁首 `Positioned` 新增直排分支＋ `!_chromeVisible` 顯示條件

**建議在 Task 3 完成後再執行本 Task**（`reader_screen.dart:1545` 這一行兩個 Task 都會觸及，避免改動互相覆蓋，見 Task 3 Step 2 備註）。

- [x] **Step 1：頁首 `Positioned` 改為依 `writingMode` 分支，並加上 `!_chromeVisible`**

`reader_screen.dart:1545-1551` 原本：

```dart
if (format == BookFormat.epub && (_resolved?.showHeader ?? false))
  Positioned(
    top: 16,
    left: 72,
    right: 72,
    child: Center(child: _buildFoliateHeaderText()),
  ),
```

改為（比照頁尾 `:1552-1569` 既有的直排/橫排分支寫法）：

```dart
if (format == BookFormat.epub &&
    (_resolved?.showHeader ?? false) &&
    !_chromeVisible)
  (_resolved?.writingMode == WritingMode.vertical)
      ? Positioned(
          right: 16,
          top: 16,
          bottom: 16,
          child: RotatedBox(
            quarterTurns: 1,
            child: _buildFoliateHeaderText(),
          ),
        )
      : Positioned(
          top: 16,
          left: 72,
          right: 72,
          child: Center(child: _buildFoliateHeaderText()),
        ),
```

**計劃審查發現（2026-08-01，Minor）**：直排分支的長文字溢出風險——`_buildFoliateHeaderText()` 內的 `Text` 雖已有 `maxLines: 1`／`overflow: TextOverflow.ellipsis`（`reader_screen.dart:1697-1701`），但省略號能否生效取決於 `Text` 是否收到有界的寬度約束。橫排分支靠 `left: 72, right: 72` 提供這個約束（螢幕寬度扣掉左右各 72px），原本的直排分支只設 `right`/`top` 兩個邊、未設 `bottom`，`RotatedBox` 交換寬高約束後，`Text` 旋轉前的有效「寬度」（來自外層 `Positioned` 未設下限的「高度」）會是無界的——章節名稱或書名（Task 5 的回退情境）過長時，省略號不會生效，直排文字可能一路向下延伸到螢幕外。**已改為額外設定 `bottom: 16`**，讓 `RotatedBox` 交換後傳給 `Text` 的寬度約束改為「螢幕高度 − 32px」的有界值，與橫排分支「靠 `Positioned` 兩側邊界提供有界寬度」是同一種機制、只是換一組邊，不需要額外的 `ConstrainedBox`／`MediaQuery` 手動計算像素（避免引入需要另外考慮 safe-area/瀏海差異的魔術數字，且與既有橫排分支的寫法風格一致）。

- [x] **Step 2：修正既有測試 `reader_screen_test.dart:3757`**

`'流式 EPUB：頁眉純顯示章節名稱、不可點擊，showHeader=false 時不顯示（Issue 7）'` 目前用 `ReaderScreen` 初始狀態（`_chromeVisible` 預設 `true`）斷言 `headerFinder findsOneWidget`——新行為下 chrome 可見時頁首應隱藏，此測試需要先觸發一次沉浸模式切換（點擊選單熱區，比照 `reader_screen_test.dart:3070` 一帶既有測試觸發 `_chromeVisible` 切換的既有寫法）讓 `_chromeVisible` 變為 `false`，才能斷言 `headerFinder findsOneWidget`；並新增一個新案例斷言「`_chromeVisible == true`（初始狀態，未觸發沉浸模式）時頁首 `findsNothing`」，明確覆蓋新行為的兩種狀態。

- [x] **Step 3：確認既有測試 `reader_screen_test.dart:3799`（Issue 13）不受影響**

`'流式 EPUB：沉浸模式收起選單（_chromeVisible=false）時，頁首文字仍常駐顯示、6 顆浮動按鈕正確收合（Issue 13）'`——新行為下 `_chromeVisible == false` 時頁首依然顯示，此測試預期維持通過不需修改；執行後確認實際結果與預期一致，若不一致需重新檢視 Step 1 的條件式是否有誤。

- [x] **Step 4：新增直排模式的頁首位置測試**

新增測試：`writingMode: WritingMode.vertical` 且 `_chromeVisible == false` 且 `showHeader == true` 時，頁首以 `RotatedBox(quarterTurns: 1)` 包裹並位於右上角（比照頁尾既有的直排位置測試寫法，若存在的話，一併核對慣例）；`Positioned` 的 `bottom: 16` 亦應在測試中一併斷言（確認寬度約束確實有界，不只是視覺上「看起來對」）。

另新增一個長文字案例：`bookTitle` 使用一個明顯過長的字串（例如 20+ 字），直排模式下確認渲染出的 `Text` widget 沒有拋出 layout overflow 例外（`flutter test` 對 `RenderFlex` 等溢出會直接失敗並印出紅黑警告，可作為自動化訊號），驗證 Step 1 新增的 `bottom: 16` 確實讓省略號機制生效，不需要真機才能發現這個問題。

- [x] **Step 5：真機驗證直排頁首的實際旋轉視覺方向**

程式碼層級的 `quarterTurns: 1` 是否讓文字方向符合直排由右至左的閱讀直覺（文字應由上至下排列），需要真機（`3CEF42ECD491687`）實際開啟直排流式書籍、觸發沉浸模式收起後肉眼確認，不能只憑程式碼推斷（比照頁尾同樣寫法的既有視覺，理論上應一致，但仍需真機複核，因為頁首位置從左下角改為右上角，視覺對稱性未必與頁尾完全一致）。同時用一本目錄章節名稱較長的書籍（或暫時測試用超長書名）實際觀察 Step 1 的 `bottom: 16` 約束是否讓省略號正確生效、文字未溢出螢幕。

---

### Task 5：頁首文字改善——第一層章節名稱或書名

**Files:**
- Modify：`app/lib/screens/reader_screen.dart`
- Modify：`app/lib/screens/library_screen.dart`
- Modify：`CLAUDE.md`
- Modify：`app/test/screens/reader_screen_test.dart`
- Modify：`app/test/screens/library_screen_test.dart`（若有建構 `ReaderScreen` 的既有測試需要同步補上新參數）

**Interfaces:**
- Consumes：`Book.title`（既有欄位）
- Produces：`ReaderScreen` 新增 `required String bookTitle` 建構參數

- [x] **Step 1：`ReaderScreen` 新增 `bookTitle` 建構參數**

`reader_screen.dart` 的 `ReaderScreen` widget 類別新增：

```dart
final String bookTitle;
```

建構子新增 `required this.bookTitle`。

- [x] **Step 2：`_buildFoliateHeaderText()` 改用第一層章節與書名回退**

`reader_screen.dart:1684-1704`：

```dart
Widget _buildFoliateHeaderText() {
  final currentPath = TocNavigator.findCurrentPath(
    _tocEntries,
    _epubPositionInfo?.progression,
  );
  final chapterTitle =
      currentPath.isEmpty ? widget.bookTitle : currentPath.first.title;
  ...
}
```

（`currentPath.last` → `currentPath.first`；`'閱讀器'` → `widget.bookTitle`。）

- [x] **Step 3：`library_screen.dart` 傳入書名**

`library_screen.dart:406-412` 的 `ReaderScreen(...)` 建構呼叫新增：

```dart
bookTitle: book.title,
```

- [x] **Step 4：盤點所有既有建構 `ReaderScreen(...)` 的呼叫點與測試**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
grep -rln "ReaderScreen(" test/ lib/
```

`bookTitle` 為 `required` 參數，全部既有建構呼叫（含 `reader_screen_test.dart` 內大量既有測試）都需要補上這個參數才能通過編譯——逐一補上（測試用途可用固定字串如 `'測試書名'`，不需要真實書名）。

- [x] **Step 5：新增測試驗證書名回退行為**

新增測試：`_tocEntries` 為空或尚未載入完成時（`currentPath.isEmpty`），頁首文字顯示 `widget.bookTitle` 而非硬編碼「閱讀器」；另新增測試驗證有巢狀目錄時頁首顯示第一層（`currentPath.first.title`）而非最深層章節（`currentPath.last.title`）。

- [x] **Step 6：更新 `CLAUDE.md`**

「`ReaderScreen` 對外的公開建構參數」段落（目前記載「filePath／bookId／prefsRepository」），補上 `bookTitle`，並簡要說明用途（頁首找不到章節資訊時的回退顯示文字）。

---

### Task 6：最終驗證、文件更新、送出 PR

**Files:**
- Modify：`docs/epics/epic-18-reader-device-qa/issues.md`
- Modify：`docs/epics.md`（若 Epic 整體狀態因此有變動）
- Modify：本計畫檔

**Interfaces:**
- Consumes：Task 1-5 全部完成
- Produces：Issue 23 結案紀錄

- [x] **Step 1：全套測試與靜態分析**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter analyze
flutter test
```

Expected：`No issues found!`；全數 PASS。

- [x] **Step 2：真機建置安裝與 5 項需求逐一驗證**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter build apk --debug
adb -s 3CEF42ECD491687 install -r build/app/outputs/flutter-apk/app-debug.apk
```

依 `issues.md` Issue 23「驗收標準」逐項在真機驗證，截圖存 `tmp/epic-18/issue23_*.png`：
1. 流式書籍新書開啟，上邊界為 32px。
2. FXL 設定畫面可切換「顯示頁首」/「顯示頁尾」。
3. 全新書籍（流式/FXL/PDF）開啟時頁首/頁尾預設關閉。
4. 開啟「顯示頁首」，直排模式下頁首正確顯示於右上角、旋轉方向符合直排閱讀直覺；點擊熱區叫出 FAB 群組時頁首消失，收起 FAB 進入閱讀時頁首重新出現。
5. 開啟一本有巢狀目錄的書，頁首顯示第一層章節名稱（非最深層）；開啟一本目錄尚未載入完成或無目錄的書，頁首顯示書名（非「閱讀器」字樣）。

- [x] **Step 3：更新 `docs/epics/epic-18-reader-device-qa/issues.md`——Issue 23 完成說明**

把 Status 改為完成狀態，逐項記錄 Task 1-5 的驗證結果與真機截圖佐證。

- [x] **Step 4：更新 `docs/epics.md`（若需要）**

- [x] **Step 5：本計畫檔 Task 1-6 所有 Step 依實際完成進度勾選**

- [x] **Step 6：Commit**

```bash
cd "U:/MyDeveloper/AI/elinkBook"
git add -A  # 或明確列出本次異動檔案
git commit -m "fix(epic-18): Issue 23 頁首/頁尾行為調整——5 項需求"
```

- [x] **Step 7：送出 code review（`superpowers:requesting-code-review`），依審查結果修正後開 PR**

---

## 相關佐證

- `docs/epics/epic-18-reader-device-qa/issues.md` Issue 23 原始描述
- `docs/epics/epic-18-reader-device-qa/reviews/bugfix-repro-header-footer.md`（`/diagnose` 完整查證過程）
- `docs/epics/epic-18-reader-device-qa/issues.md` Issue 13（本計劃 Task 4 會反轉的既有決策，需對照理解）
- `app/lib/screens/reader_screen.dart:1208-1257,1430-1638,1678-1704`
- `app/lib/screens/fxl_settings_sheet.dart`／`reader_settings_sheet.dart:63-91,120-121,306-318`
- `app/lib/reader/reader_prefs_manager_impl.dart:177-180`
- `app/lib/library/library_repository.dart`／`app/lib/screens/library_screen.dart:402-412`
- `CLAUDE.md`「`ReaderScreen` 對外的公開建構參數」段落
- `app/test/reader/reader_prefs_manager_test.dart:39-64`
- `app/test/screens/reader_screen_test.dart:3757-3846`（Issue 7／Issue 13 既有測試）
