# 頁首/頁尾行為調整（5 項需求）——現況診斷（`/diagnose`）

**日期：** 2026-08-01
**性質：** 5 項使用者提出的頁首/頁尾行為調整需求，非典型「神秘 bug」，改用逐項程式碼查證取代假設/猜測，找出精確修改點與需要人類決策的架構分岔點。已與人類確認 3 個開放問題（見各項「已確認」段落）。

---

## 需求原文

1. 流式 EPUB，上邊界預設改為 32。
2. FXL EPUB 沒有地方可以設定開啟或關閉「顯示頁首」、「顯示頁尾」。
3. 不論哪一種格式，預設都改為關閉「顯示頁首」、關閉「顯示頁尾」。
4. 直排閱讀時，「頁首」請比照「頁尾」以直排方式顯示在右上角。如此一來等於 FAB 按鈕與「頁首」不可同時出現。閱讀時才顯示「頁首」。顯示 FAB 時就要隱藏頁首。
5. 改善頁首的文字。目前大多是以「閱讀器」顯示。請改為若能知道目前的第一層章節名稱，就顯示第一層章節名稱。反之，則改為顯示書名。

---

## 項目 1：流式 EPUB 上邊界預設改 32

**現況查證：** `app/android/app/src/main/assets/foliate/main.js:161` 明確標註「以下為流式（reflowable）書籍的既有邏輯，完全不變動」，其下 `main.js:222`：

```js
const marginTopPx = typeof prefs.marginTop === 'number' ? prefs.marginTop : 64
```

`prefs.marginTop` 未設定（`null`）時的預設值目前是 `64`。`app/lib/reader/foliate_epub_reader_view.dart:110` 確認 Dart 端 `marginTop == null` 時該欄位完全不會出現在送給 JS 的 preferences map 中，故這個 `64` 是唯一的真實預設值來源（不是 Dart 端另有預設再覆蓋）。

**修改點：** `main.js:222`，`64` → `32`。單行修改，無架構疑慮。

---

## 項目 2：FXL 沒有頁首/頁尾開關

**現況查證：** `app/lib/screens/fxl_settings_sheet.dart` 全文搜尋 `showHeader`/`showFooter` 零匹配。對照流式的 `app/lib/screens/reader_settings_sheet.dart:306-318`：

```dart
SwitchListTile(
  title: const Text('顯示頁首'),
  value: _showHeader,
  onChanged: (v) => setState(() { _showHeader = v; ... }),
),
SwitchListTile(
  title: const Text('顯示頁尾'),
  value: _showFooter,
  ...
),
```

**關鍵事實：底層資料模型與顯示邏輯已經對 FXL/流式一視同仁**，只是設定畫面忘了加開關：
- `app/lib/screens/reader_screen.dart:1235,1545,1552-1553,1633-1638` 的顯示條件皆是 `format == BookFormat.epub && ...`，不區分 `_isFixedLayout`。
- `book_reader_prefs.dart`／`resolved_preferences.dart` 的 `showHeader`/`showFooter` 欄位本身無格式限制。

**修改點：** 比照 `reader_settings_sheet.dart:306-318`，在 `fxl_settings_sheet.dart` 補上相同的兩個 `SwitchListTile`，接到既有的 `BookReaderPrefs.showHeader`/`showFooter` 儲存機制（`fxl_settings_sheet.dart` 現有的 `copyWith`/儲存呼叫模式可直接沿用，比照該檔案內其餘既有開關的寫法）。純 UI 補齊，無需新資料欄位或架構變動。

---

## 項目 3：兩種格式預設皆改為關閉

**現況查證：** 唯一的正式預設值解析點是 `app/lib/reader/reader_prefs_manager_impl.dart:179-180`：

```dart
showHeader: book.showHeader ?? true,
showFooter: book.showFooter ?? true,
```

這裡把可為 `null` 的每書覆寫值（`book.showHeader`/`showFooter`）解析為 `ResolvedPreferences` 的非 nullable `bool` 欄位，是整個 App 唯一「正式」的預設值來源。

**另外查到的防呆用 `?? true`（非正式預設值，是 `_resolved` 尚未載入完成前的安全展示值）：**
- `reader_screen.dart:1235,1545,1553,1623,1808`（PDF 用 `resolved.showFooter` 直傳，無 `?? true`）
- `reader_settings_sheet.dart:90-91,120-121`（Sheet 開啟當下的初始 UI 狀態）

這些站點語意上是「`_resolved` 還沒 ready 時暫時怎麼顯示」，跟「使用者從未設定過時的正式預設值」是兩個不同問題，但字面值目前碰巧一致（都是 `true`）——若只改 `reader_prefs_manager_impl.dart` 而不改這些防呆值，會出現「開書瞬間短暫顯示頁首/頁尾、`_resolved` load 完成後才消失」的畫面閃爍，需要一併檢視。

**PDF 範圍已與人類確認：`pdf_settings_sheet.dart` 的 `showFooter`（PDF 目前沒有 `showHeader` 概念，見 `reader_screen.dart:1235`「`format == BookFormat.epub`」的既有限制，頁首功能本來就是 EPUB 專屬，PDF 不受影響）也要一併改預設關閉。**

**修改點：**
1. `reader_prefs_manager_impl.dart:179-180`：兩個 `?? true` → `?? false`。
2. `reader_screen.dart`／`reader_settings_sheet.dart` 前述防呆用 `?? true` 站點，同步改 `?? false`（避免載入瞬間閃爍不一致）。
3. 確認 `pdf_settings_sheet.dart` 的 `showFooter` 預設解析點（初步查證在 `reader_prefs_manager_impl.dart` 同一處，PDF/EPUB 共用同一個 `ResolvedPreferences.showFooter` 欄位與同一行 `?? false`，不需要獨立第二個修改點——但需在實作階段重新確認 PDF 是否真的共用同一個解析路徑，而非另有獨立分支）。

---

## 項目 4：直排頁首移到右上角，與 FAB 互斥

**現況查證：**

頁尾既有的直排寫法（`reader_screen.dart:1552-1569`）已提供可直接複製的既有模式：

```dart
(_resolved?.writingMode == WritingMode.vertical)
    ? Positioned(
        left: 16,
        bottom: 16,
        child: RotatedBox(quarterTurns: 1, child: _buildFoliateProgressText()),
      )
    : Positioned(left: 0, right: 0, bottom: 16, child: Center(child: _buildFoliateProgressText())),
```

頁首目前（`reader_screen.dart:1545-1551`）完全沒有直排分支，永遠是水平置中：

```dart
if (format == BookFormat.epub && (_resolved?.showHeader ?? true))
  Positioned(top: 16, left: 72, right: 72, child: Center(child: _buildFoliateHeaderText())),
```

**關鍵事實：頁首目前完全沒有 `_chromeVisible` 判斷式，是全部浮動元素中唯一的例外。** 對照同一個 Stack 內其餘元素（`reader_screen.dart:1430,1446,1464,1483,1509,1529` 的返回/設定/書籤/筆記/目錄/跳頁按鈕）全部都是 `_chromeVisible &&` 開頭——只有 FAB 顯示、頁首才顯示會與 FAB 群組同時出現、視覺上可能與右側 FAB 直排時的位置衝突（尤其移到右上角後）。

**重要歷史脈絡（本項目會反轉既有明確決策，需在新 Issue 中清楚記載）**：`issues.md` Issue 13（已完成，PR #83）當初**刻意**把頁首/進度文字的顯示條件從 `_chromeVisible && showHeader` 改成單純 `showHeader`（移除 `_chromeVisible`），目的是讓頁首「跟內文常駐顯示、不受沉浸模式切換影響」。本項目要求的行為與 Issue 13 的決策方向相反——不是恢復 Issue 13 之前的「只在 `_chromeVisible == true` 時顯示」（那樣頁首會跟 FAB 同時出現，正是本項目要避免的），而是新的第三種狀態「只在 `_chromeVisible == false` 時顯示」（`!_chromeVisible && showHeader`）。三種狀態需要在新 Issue 描述中明確排比，避免未來維護者誤以為只是簡單復原 Issue 13。**注意：本項目只改頁首，不影響 Issue 13 對「進度文字」（頁尾）常駐顯示的既有決策——頁尾維持現狀，不受本次影響。**

**已與人類確認：不分直排/橫排，頁首一律改為「只在非沉浸模式（`_chromeVisible == false`）時顯示」，與 FAB 完全互斥（FAB 顯示時必隱藏）。**

**修改點：**
1. `reader_screen.dart:1545` 的顯示條件加上 `!_chromeVisible`（從「只要 `showHeader` 開啟就永遠顯示」改為「`showHeader` 開啟且非沉浸模式才顯示」）。
2. 直排時仿照頁尾模式，改為 `Positioned(right: 16, top: 16, child: RotatedBox(quarterTurns: 1, child: _buildFoliateHeaderText()))`（頁尾用 `quarterTurns: 1` 且置於左下，頁首右上角的正確旋轉方向需要真機實測確認視覺是否符合直排由右至左的閱讀直覺，不能只憑程式碼推斷抄對）。
3. 橫排維持水平置中不變，只補上 `!_chromeVisible` 條件。

**注意**：此變更會改變現有行為（目前頁首在 FAB 顯示時也會同時出現），需要盤點 `reader_screen_test.dart` 既有斷言「頁首在 `_chromeVisible == true` 時仍顯示」的測試（若存在）並同步修正，避免這次修法製造新的測試失敗。

---

## 項目 5：頁首文字改為第一層章節名稱／書名

**現況查證：**

真正被使用的是 `_buildFoliateHeaderText()`（`reader_screen.dart:1684-1704`，透過項目 4 提到的浮動疊加層顯示，橫排/直排皆用同一個 widget）：

```dart
Widget _buildFoliateHeaderText() {
  final currentPath = TocNavigator.findCurrentPath(_tocEntries, _epubPositionInfo?.progression);
  final chapterTitle = currentPath.isEmpty ? '閱讀器' : currentPath.last.title;
  ...
}
```

`currentPath.last` 是目錄巢狀路徑中最深層（最貼近目前位置）的項目，不是「第一層章節」；找不到章節時寫死顯示字串 `'閱讀器'`。

另有一個**已確認為死碼**的相似邏輯：`_buildAppBarTitle()`（`reader_screen.dart:1234-1257`）也有幾乎相同的 `currentPath.last.title` 邏輯，但查證 `appBar:` 建構條件（`reader_screen.dart:1212-1220`）後確認：`_isFixedLayout || !_chromeVisible || (format == epub && _dispatchedIsFixedLayout == false)` 三者只要有一個成立就 `appBar: null`——FXL 恆真（`_isFixedLayout`），流式 EPUB 也恆真（`_dispatchedIsFixedLayout == false`），故傳統 `Scaffold.appBar` **對 EPUB 格式而言永遠不會顯示**，`_buildAppBarTitle()` 實質上只服務 PDF（PDF 走此路徑時 `format != epub`，直接回傳固定的靜態「閱讀器」文字，不會走到 `currentPath` 分支）。**本項目的章節名稱邏輯不需要動 `_buildAppBarTitle()`。**

**架構缺口：`ReaderScreen` 目前沒有任何管道能拿到書名**。`LibraryRepository` 介面（`app/lib/library/library_repository.dart`）只有 `insertBook`/`updateBook`/`deleteBook`/`listBooks`/`detectAndCacheEpubLayout`，沒有 `getBook(id)` 這類單筆查詢方法。但呼叫端 `library_screen.dart:402-412` 的 `_openBook(Book book)` 在建構 `ReaderScreen` 當下，手上其實已經有完整的 `Book` 物件（`filePath`/`bookId` 正是從這個物件取的），只是沒有把 `book.title` 一併傳下去。

**已與人類確認：新增 `ReaderScreen` 建構參數 `bookTitle`**（由 `LibraryScreen._openBook()` 直接從既有 `Book` 物件傳入，不新增 `LibraryRepository` 方法、不在 `ReaderScreen` 內部另外非同步查詢）——這會改動 `CLAUDE.md` 明文記載的 `ReaderScreen` 公開建構參數清單（目前記載為「filePath／bookId／prefsRepository」），屬於新增性質（不影響既有參數），但文件需要同步更新。

**修改點：**
1. `ReaderScreen` 新增 `required String bookTitle`（或視既有慣例決定是否 nullable）建構參數。
2. `library_screen.dart:406-412` 建構 `ReaderScreen(...)` 時補上 `bookTitle: book.title`。
3. `_buildFoliateHeaderText()`：`currentPath.last.title` → `currentPath.first.title`；`currentPath.isEmpty` 分支的 `'閱讀器'` → `widget.bookTitle`。
4. `CLAUDE.md`「`ReaderScreen` 對外的公開建構參數」段落同步更新，補上 `bookTitle`。

---

## 總結：修改範圍一覽

| 項目 | 檔案 | 性質 |
|---|---|---|
| 1 | `main.js` | 常數值變更（1 行） |
| 2 | `fxl_settings_sheet.dart` | 新增 UI 控制項（複製既有模式） |
| 3 | `reader_prefs_manager_impl.dart` + `reader_screen.dart`/`reader_settings_sheet.dart` 防呆值 | 常數值變更（多處，需盤點一致性） |
| 4 | `reader_screen.dart` | 顯示條件＋直排分支邏輯（仿頁尾既有模式） |
| 5 | `reader_screen.dart` + `library_screen.dart` + `ReaderScreen` 建構參數 + `CLAUDE.md` | 新增建構參數（公開介面異動） |

**共同風險**：項目 4 的 `!_chromeVisible` 新增條件與項目 3 的預設值變更，皆可能讓既有 `reader_screen_test.dart` 中斷言頁首/頁尾預設可見或永遠顯示的既有測試失敗，需要在實作階段逐一盤點既有測試並同步修正（而非略過不管）。

## 相關佐證

- `app/android/app/src/main/assets/foliate/main.js:161,211-225`
- `app/lib/screens/fxl_settings_sheet.dart`／`reader_settings_sheet.dart:63-91,120-121,306-318`
- `app/lib/reader/reader_prefs_manager_impl.dart:177-180`
- `app/lib/screens/reader_screen.dart:1208-1257,1430-1638,1678-1704`
- `app/lib/library/library_repository.dart`／`app/lib/screens/library_screen.dart:402-412`
- `CLAUDE.md`「`ReaderScreen` 對外的公開建構參數」段落
