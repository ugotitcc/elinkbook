# Epic 11 Issue 2 — KF8 (AZW3) 匯入與閱讀 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 讓使用者能匯入並閱讀 KF8 (AZW3) 檔案，享有與 EPUB 完全一致的直排/避頭尾/CFI/劃線/書籤/目錄/同步能力；DRM 加密檔案在匯入時被友善攔截，不建立殘缺書籍記錄。

**Architecture:** `FoliateEpubReaderView` 泛化重構為 `FoliateReaderView`，服務全部 Foliate 格式；`view.js` 對 KF8 的格式偵測與渲染分派完全自動（已由 Issue 1 Spike 真機驗證），本 Issue 不需要新增任何原生 Kotlin 程式碼或 WebView 整合邏輯，工作集中在兩處：(1) `ReaderScreen`/`book_format.dart` 的格式分派範圍擴充，(2) 全新的純 Dart KF8 metadata/封面/DRM 位元組解析模組（`app/lib/library/kf8_metadata.dart`），供匯入管線在真正把檔案交給 WebView 之前完成 metadata 擷取與 DRM 攔截。

**Tech Stack:** Flutter/Dart（`dart:io` `RandomAccessFile` 隨機存取讀取、`dart:typed_data` `ByteData` 大端序位元組解析）、`readest/foliate-js`（釘定 commit `dd71f2be356563c16a23272686189fcfb45d0b82`，`mobi.js`／`vendor/fflate.js`）、既有 `kBookMetadataChannel`（`copyContentUriToFile` 原生方法，`content://` 來源時複製暫存檔用）。

**Spec:** `docs/epics/epic-11-multi-format-reader/spec.md`（「格式偵測與渲染分派」「KF8 (AZW3) 支援」章節）、`docs/epics/epic-11-multi-format-reader/issues.md`（Issue 2）、`docs/adr/0023-multi-format-foliate-pipeline-txt-route-reversal.md`。

## Global Constraints

- **DRM 偵測邏輯必須是純 Dart 實作，不呼叫 `mobi.js`／不新增原生 Kotlin 解析程式碼**（ADR 0023 決策 5；`mobi.js` 本身不會因加密欄位非 0 而拒絕開啟，見 Issue 1 Spike 查證）。
- **PALMDOC_HEADER.encryption 位於 MOBI record 0 內 offset 12、2 bytes、大端序**（`ByteData.getUint16(offset, Endian.big)`，Issue 1 Spike 已用 Python/Node 雙重驗證此邏輯）；非 0 即拋出 `DrmProtectedException`，中止匯入、不寫入 `Book` 記錄。
- **不引入任何原生 platform channel 依賴做 KF8 專屬解析**——`content://` 來源的隨機存取讀取須複製到暫存檔後用 `dart:io` 本機隨機存取，複用既有的、格式無關的 `copyContentUriToFile` 原生方法（`book_import_service_impl.dart` 現有 `_copyToLocalStorage()` 已使用同一方法，非本 Issue 新增依賴）。
- **`FoliateEpubReaderView` 泛化重構為 `FoliateReaderView` 只改名，不改變任何公開建構參數/callback 契約**——`ReaderScreen` 現有的呼叫方式維持不變，僅類別名稱與檔名改變。
- **`BookFormat`/`BookFileFormat` 兩個 enum 各自維持完整列舉值，不整併**（`design.md` 決策 #8）；新增值一律以副檔名命名（`azw3`，非 `kf8`）。
- **KF8 走既有 EPUB 相容渲染路徑，不新增格式專屬的閱讀功能程式碼**——`reader_screen.dart` 內所有「這是不是 EPUB」的判斷（switch case／equality 比較），只要語意是「這本書是否走 Foliate 流式管線」，皆須同步涵蓋 `azw3`；語意是「這本書是否為固定版面（`_isFixedLayout`）」的判斷維持不動（KF8 與 EPUB 共用同一套 `isFixedLayout` 機制，不需要另外分流）。
- **既有測試不可回歸**：`flutter test`／`flutter analyze` 全程保持 0 failures／0 issues。

---

## File Structure

| 檔案 | 異動類型 | 職責 |
|---|---|---|
| `app/lib/reader/foliate_reader_view.dart` | 新增（由 `foliate_epub_reader_view.dart` 改名） | 泛化後的 Foliate widget |
| `app/lib/reader/foliate_epub_reader_view.dart` | 刪除 | 已改名 |
| `app/test/reader/foliate_reader_view_test.dart` | 新增（由 `foliate_epub_reader_view_test.dart` 改名） | 對應測試 |
| `app/test/reader/foliate_epub_reader_view_test.dart` | 刪除 | 已改名 |
| `app/lib/reader/book_format.dart` | 修改 | 新增 `BookFormat.azw3`、`isFoliateFormat()` helper |
| `app/lib/library/models/library_enums.dart` | 修改 | 新增 `BookFileFormat.azw3` |
| `app/lib/screens/reader_screen.dart` | 修改 | `FoliateReaderView` 改名引用；`azw3` 格式分派 |
| `app/android/app/src/main/assets/foliate/mobi.js`／`vendor/fflate.js` | 新增（vendor，釘定 commit） | KF8 解析 |
| `app/test/fixtures/sample.azw3` | 新增（Standard Ebooks 公版樣本） | 測試 fixture |
| `app/pubspec.yaml` | 修改 | 新增 fixture 至 assets 清單 |
| `app/lib/library/kf8_metadata.dart` | 新增 | 純 Dart KF8 metadata／封面／DRM 擷取器 |
| `app/test/library/kf8_metadata_test.dart` | 新增 | 對應測試 |
| `app/lib/library/book_import_service_impl.dart` | 修改 | `azw3` 匯入分支接線 |
| `app/test/library/book_import_service_impl_test.dart` | 修改 | 新增 `azw3` 匯入情境測試（若既有檔案不存在則新建） |
| `app/integration_test/foliate_kf8_test.dart` | 新增 | 真機開書驗證 |
| `CLAUDE.md` | 修改 | `ReaderScreen`／`FoliateEpubReaderView` 架構描述同步更新 |

---

### Task 1：`FoliateEpubReaderView` → `FoliateReaderView` 改名

**Files:**
- Create（`git mv`）：`app/lib/reader/foliate_reader_view.dart`（由 `foliate_epub_reader_view.dart` 改名）
- Create（`git mv`）：`app/test/reader/foliate_reader_view_test.dart`（由 `foliate_epub_reader_view_test.dart` 改名）
- Modify：`app/lib/screens/reader_screen.dart`（import 路徑與所有 `FoliateEpubReaderView` 引用）
- Modify：`CLAUDE.md`（「`ReaderScreen`」架構小節）

**Interfaces:**
- Consumes：無（起始工單）
- Produces：`FoliateReaderView`（class 名稱），公開建構參數與 static helper（`nextPage`/`previousPage`/`jumpToProgression`/`jumpToLocator`/`loadTableOfContents`/`setDecorations`/`clearSelection`）簽章與改名前的 `FoliateEpubReaderView` **完全相同**，僅類別名稱不同——後續 Task 直接引用 `FoliateReaderView`

- [ ] **Step 1：確認目前測試基準線**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter test 2>&1 | tail -20
flutter analyze
```

Expected：全數通過、0 issues（記錄目前測試總數，供後續比對）。

- [ ] **Step 2：改名檔案**

```bash
git mv app/lib/reader/foliate_epub_reader_view.dart app/lib/reader/foliate_reader_view.dart
git mv app/test/reader/foliate_epub_reader_view_test.dart app/test/reader/foliate_reader_view_test.dart
```

- [ ] **Step 3：在兩個改名後的檔案內，把所有 `FoliateEpubReaderView` 字面替換為 `FoliateReaderView`**

```bash
cd "U:/MyDeveloper/AI/elinkBook"
sed -i 's/FoliateEpubReaderView/FoliateReaderView/g' \
  app/lib/reader/foliate_reader_view.dart \
  app/test/reader/foliate_reader_view_test.dart
grep -c "FoliateEpubReaderView" app/lib/reader/foliate_reader_view.dart app/test/reader/foliate_reader_view_test.dart
```

Expected：兩個檔案的 `grep -c` 皆回報 `0`（無殘留舊名稱）。**不要**修改這兩個檔案內其餘任何邏輯——本 Task 純改名。

- [ ] **Step 4：更新 `reader_screen.dart` 的所有引用**

```bash
grep -c "FoliateEpubReaderView" app/lib/screens/reader_screen.dart
```

記下這個數字（改名前的引用次數）。

```bash
sed -i 's/FoliateEpubReaderView/FoliateReaderView/g' app/lib/screens/reader_screen.dart
grep -c "FoliateEpubReaderView" app/lib/screens/reader_screen.dart
grep -c "FoliateReaderView" app/lib/screens/reader_screen.dart
```

Expected：改名後第一個 `grep -c` 回報 `0`；第二個 `grep -c` 回報的數字與改名前記下的數字相同（純文字替換，引用次數不變）。

- [ ] **Step 5：確認建置與測試通過**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter analyze
flutter test 2>&1 | tail -20
```

Expected：`flutter analyze` 0 issues；`flutter test` 總數與 Step 1 記錄的基準線相同（純改名不增減任何測試）。

- [ ] **Step 6：更新 `CLAUDE.md`「`ReaderScreen`」架構小節**

把 `CLAUDE.md` 內所有描述 `FoliateEpubReaderView`「所有 EPUB」職責的段落，改為描述 `FoliateReaderView`「所有 Foliate 格式（EPUB 流式與 FXL；本 Issue 起新增 KF8）」——具體異動：

```bash
grep -n "FoliateEpubReaderView" CLAUDE.md
```

逐一核對每處引用文字語意（是否明確寫著「所有 EPUB」），把類別名稱改為 `FoliateReaderView`，並把「所有 EPUB」措辭改為「所有 Foliate 格式（EPUB／KF8，本 Issue 起）」。

- [ ] **Step 7：Commit**

```bash
cd "U:/MyDeveloper/AI/elinkBook"
git add app/lib/reader/foliate_reader_view.dart app/lib/reader/foliate_epub_reader_view.dart \
  app/test/reader/foliate_reader_view_test.dart app/test/reader/foliate_epub_reader_view_test.dart \
  app/lib/screens/reader_screen.dart CLAUDE.md
git commit -m "refactor(epic-11): Issue 2——FoliateEpubReaderView 泛化改名為 FoliateReaderView"
```

---

### Task 2：`BookFormat.azw3`／`BookFileFormat.azw3`，`reader_screen.dart` 分派擴充

**Files:**
- Modify：`app/lib/reader/book_format.dart`
- Modify：`app/test/reader/book_format_test.dart`（若不存在則新建）
- Modify：`app/lib/library/models/library_enums.dart`
- Modify：`app/lib/screens/reader_screen.dart`

**Interfaces:**
- Consumes：Task 1 的 `FoliateReaderView`
- Produces：`BookFormat.azw3`、`isFoliateFormat(BookFormat format) → bool`（新增頂層函式，`app/lib/reader/book_format.dart`），供 `reader_screen.dart` 與後續 Issue 3-5 統一判斷「這是不是走 Foliate 管線的格式」

- [ ] **Step 1：寫 `book_format.dart` 的失敗測試**

在 `app/test/reader/book_format_test.dart` 新增（若檔案已存在則追加）：

```dart
test('.azw3 副檔名回傳 BookFormat.azw3', () {
  expect(detectBookFormat('book.azw3'), BookFormat.azw3);
  expect(detectBookFormat('BOOK.AZW3'), BookFormat.azw3);
});

group('isFoliateFormat', () {
  test('epub／azw3 回傳 true', () {
    expect(isFoliateFormat(BookFormat.epub), isTrue);
    expect(isFoliateFormat(BookFormat.azw3), isTrue);
  });

  test('pdf／unknown 回傳 false', () {
    expect(isFoliateFormat(BookFormat.pdf), isFalse);
    expect(isFoliateFormat(BookFormat.unknown), isFalse);
  });
});
```

- [ ] **Step 2：執行測試確認失敗**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter test test/reader/book_format_test.dart
```

Expected：因 `BookFormat.azw3`／`isFoliateFormat` 尚未定義而編譯失敗。

- [ ] **Step 3：實作 `book_format.dart`**

把 `app/lib/reader/book_format.dart` 改為：

```dart
/// 書籍檔案格式，依副檔名偵測。
enum BookFormat { epub, pdf, azw3, unknown }

/// 依檔案路徑的副檔名判斷書籍格式（不分大小寫）。無法識別的副檔名（含無副
/// 檔名、空字串）一律回傳 [BookFormat.unknown]，絕不拋出例外。
BookFormat detectBookFormat(String path) {
  final lowerPath = path.toLowerCase();
  if (lowerPath.endsWith('.epub')) return BookFormat.epub;
  if (lowerPath.endsWith('.pdf')) return BookFormat.pdf;
  if (lowerPath.endsWith('.azw3')) return BookFormat.azw3;
  return BookFormat.unknown;
}

/// 是否為經由 [FoliateReaderView]（`foliate-js`）渲染的格式——與
/// [BookFormat.pdf] 互斥，[BookFormat.unknown] 兩者皆非。`reader_screen.dart`
/// 內所有「這是不是走 Foliate 流式管線」的判斷皆應呼叫本函式，而非逐一列舉
/// 格式，避免未來新增格式（CBZ/TXT/MD）時遺漏更新（epic-11-multi-format-reader
/// Issue 2，spec.md「格式偵測與渲染分派」）。
bool isFoliateFormat(BookFormat format) =>
    format == BookFormat.epub || format == BookFormat.azw3;
```

- [ ] **Step 4：執行測試確認通過**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter test test/reader/book_format_test.dart
```

Expected：全數通過。

- [ ] **Step 5：新增 `BookFileFormat.azw3`**

在 `app/lib/library/models/library_enums.dart`，把：

```dart
enum BookFileFormat { epub, pdf, txt }
```

改為：

```dart
enum BookFileFormat { epub, pdf, txt, azw3 }
```

同時更新該 enum 上方的 doc 註解，新增一句反映 KF8 (AZW3) 由本 Issue 補上（沿用既有措辭風格，說明與 `reader/book_format.dart` 的 `BookFormat` 分工不同）。

- [ ] **Step 6：`detectBookFileFormat()` 新增 `.azw3` 判斷**

在 `app/lib/library/book_import_service_impl.dart` 的 `detectBookFileFormat()` 函式（頂層函式，非 class 方法）新增一行：

```dart
BookFileFormat? detectBookFileFormat(String uriOrPath) {
  final name = _lastPathComponent(uriOrPath).toLowerCase();
  if (name.endsWith('.epub')) return BookFileFormat.epub;
  if (name.endsWith('.pdf')) return BookFileFormat.pdf;
  if (name.endsWith('.txt')) return BookFileFormat.txt;
  if (name.endsWith('.azw3')) return BookFileFormat.azw3;
  return null;
}
```

- [ ] **Step 7：確認 `flutter analyze` 列出所有需要更新的 `reader_screen.dart` switch 陳述式**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter analyze 2>&1 | grep "reader_screen.dart"
```

Expected：Dart 對 enum 的 `switch` 陳述式具窮盡性檢查，新增 `BookFormat.azw3` 後，`reader_screen.dart` 內每一處缺少 `case BookFormat.azw3:` 的 `switch (format)`／`switch (widget.format)` 皆會被列為錯誤（`non_exhaustive_switch_statement` 或等效訊息），逐一記下報錯的行號，供下一步逐一修正——**不會有任何一處被靜默漏掉**，這是本 Task 依賴編譯器而非人工逐行核對的關鍵防呆。

- [ ] **Step 8：逐一修正編譯器列出的每個 switch 陳述式，新增 `case BookFormat.azw3:` 與緊鄰的 `case BookFormat.epub:` 合併為同一段落**

以下 3 處為已知會被列出、且改法完全相同（合併 case 標籤、body 逐字不動）的範例，其餘 Step 7 列出但未在此列出的位置，比照相同模式處理：

`_writeCurrentPosition()`（約行 512-556）：

```dart
switch (format) {
  case BookFormat.pdf:
    // ...不動...
    break;
  case BookFormat.epub:
  case BookFormat.azw3:
    // ...原 case BookFormat.epub: 內容逐字不動...
    break;
  case BookFormat.unknown:
    return;
}
```

`_buildAppBarActions()`（約行 1872-1939）：

```dart
switch (format) {
  case BookFormat.epub:
  case BookFormat.azw3:
    return [
      // ...原內容逐字不動...
    ];
  case BookFormat.pdf:
    return null;
  case BookFormat.unknown:
    return null;
}
```

`_buildNativeView()`（約行 2556-2642）：

```dart
switch (format) {
  case BookFormat.epub:
  case BookFormat.azw3:
    // Epic 11 Issue 2：KF8 (AZW3) 與 EPUB 共用同一個 FoliateReaderView，
    // 建構參數完全相同，不需要依格式分流。
    return FoliateReaderView(
      // ...原內容逐字不動...
    );
  case BookFormat.pdf:
    // ...不動...
  case BookFormat.unknown:
    return const SizedBox.shrink();
}
```

- [ ] **Step 9：`flutter analyze` 直到 0 issues**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter analyze
```

若仍有 `reader_screen.dart` 的錯誤，重複 Step 8 的模式處理，直到 0 issues。

- [ ] **Step 10：grep 找出所有 equality 比較式（不會被 switch 窮盡性檢查攔到），逐一改用 `isFoliateFormat()`**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
grep -n "format == BookFormat.epub\|format != BookFormat.epub" lib/screens/reader_screen.dart
```

逐一核對每一筆比對的語意：

- 若語意是「這是不是走 Foliate 流式管線」（例如判斷是否要建構 `FoliateReaderView`、是否顯示 EPUB 專屬工具列/熱區、是否套用 EPUB 專屬的頁尾/進度邏輯），改為 `isFoliateFormat(format)`（`==` 情況）或 `!isFoliateFormat(format)`（`!=` 情況）。
- 若語意是「這是不是固定版面（FXL）」（變數/欄位名稱含 `_isFixedLayout`／`isFixedLayoutHint`／`_dispatchedIsFixedLayout` 的判斷式），**不動**——KF8 與 EPUB 共用同一套固定版面判斷機制（皆讀取 `Book.isFixedLayout`），與格式本身無關。

以下為已確認需要修正的具體範例（`_buildBody()`，約行 1993-1996）：

```dart
// 修正前：
if (_resolved != null &&
    (format != BookFormat.epub ||
        (_dispatchedIsFixedLayout != null && _customFontsLoaded)))
  _buildNativeView(format, isLandscape),

// 修正後：
if (_resolved != null &&
    (!isFoliateFormat(format) ||
        (_dispatchedIsFixedLayout != null && _customFontsLoaded)))
  _buildNativeView(format, isLandscape),
```

**已知殘留風險（記錄供審查關注，非本 Task 必須解決）**：KF8 若透過 EXTH `fixedLayout` 標籤宣告為固定版面，其 `_dispatchedIsFixedLayout` 判斷時機與既有 EPUB FXL 邏輯共用同一套機制，但本 Issue 的驗收標準（`issues.md`）與測試 fixture（`sample.azw3`，reflowable）皆未涵蓋 KF8 FXL 這個子情境的真機驗證深度——若後續真機測試發現 KF8 FXL 書籍有分派時機問題，另立追蹤工單，不阻塞本 Issue 其餘驗收項目。

- [ ] **Step 11：`flutter analyze`／`flutter test` 全數通過**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter analyze
flutter test 2>&1 | tail -20
```

Expected：0 issues；測試總數與 Task 1 Step 5 記錄的基準線相同或更多（Step 1 新增的 `book_format_test.dart` 測試計入）。

- [ ] **Step 12：Commit**

```bash
cd "U:/MyDeveloper/AI/elinkBook"
git add app/lib/reader/book_format.dart app/test/reader/book_format_test.dart \
  app/lib/library/models/library_enums.dart app/lib/library/book_import_service_impl.dart \
  app/lib/screens/reader_screen.dart
git commit -m "feat(epic-11): Issue 2——BookFormat/BookFileFormat 新增 azw3，reader_screen.dart 格式分派擴充"
```

---

### Task 3：Vendor `mobi.js`／`vendor/fflate.js`，取得 AZW3 測試 fixture

**Files:**
- Create（下載，釘定 commit）：`app/android/app/src/main/assets/foliate/mobi.js`、`app/android/app/src/main/assets/foliate/vendor/fflate.js`
- Create（下載）：`app/test/fixtures/sample.azw3`
- Modify：`app/pubspec.yaml`

**Interfaces:**
- Consumes：無
- Produces：`app/test/fixtures/sample.azw3`（供 Task 5 測試使用）；production `mobi.js`／`vendor/fflate.js`（供真機開書，Task 7 使用）

- [ ] **Step 1：下載釘定 commit 的 vendor 資產**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app/android/app/src/main/assets/foliate"
FOLIATE_COMMIT=dd71f2be356563c16a23272686189fcfb45d0b82
curl -sS -m 30 "https://raw.githubusercontent.com/readest/foliate-js/$FOLIATE_COMMIT/mobi.js" -o mobi.js
curl -sS -m 30 "https://raw.githubusercontent.com/readest/foliate-js/$FOLIATE_COMMIT/vendor/fflate.js" -o vendor/fflate.js
wc -l mobi.js vendor/fflate.js
grep -c "export const readMobiMetadata" mobi.js
grep -c "unzlibSync" vendor/fflate.js
```

Expected：`mobi.js` 約 1279 行、`vendor/fflate.js` 為單行壓縮檔；兩個 `grep -c` 皆回報 `1`（確認抓到正確原始碼，非 404 頁面，比照 Issue 1 Spike 已驗證的下載流程）。

- [ ] **Step 2：下載 AZW3 測試 fixture**

```bash
mkdir -p "U:/MyDeveloper/AI/elinkBook/app/test/fixtures"
curl -sSL -o "U:/MyDeveloper/AI/elinkBook/app/test/fixtures/sample.azw3" \
  "https://standardebooks.org/ebooks/h-g-wells/the-time-machine/downloads/h-g-wells_the-time-machine.azw3?source=download"
ls -la "U:/MyDeveloper/AI/elinkBook/app/test/fixtures/sample.azw3"
xxd "U:/MyDeveloper/AI/elinkBook/app/test/fixtures/sample.azw3" | head -5
```

Expected：檔案大小約 545452 bytes；`xxd` 輸出 offset `0x3c`（60）起可辨識出 `424f4f4b 4d4f4249`（ASCII `BOOKMOBI`）——已於 Issue 1 Spike 驗證過此連結有效（`plans/plan-issue-1.md` Task 2 Step 2），本 Step 重新下載確認同一份內容仍可正常取得。

- [ ] **Step 3：新增至 `pubspec.yaml` assets 清單**

在 `app/pubspec.yaml` 的 `flutter: assets:` 清單，於 `- test/fixtures/sample.epub` 附近新增一行：

```yaml
    - test/fixtures/sample.azw3
```

- [ ] **Step 4：確認建置未受影響**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter pub get
flutter analyze
```

Expected：`flutter pub get` 成功、`flutter analyze` 0 issues。

- [ ] **Step 5：Commit**

```bash
cd "U:/MyDeveloper/AI/elinkBook"
git add app/android/app/src/main/assets/foliate/mobi.js app/android/app/src/main/assets/foliate/vendor/fflate.js \
  app/test/fixtures/sample.azw3 app/pubspec.yaml
git commit -m "feat(epic-11): Issue 2——vendor mobi.js/fflate.js，新增 AZW3 測試 fixture"
```

---

### Task 4：底層 PDB/MOBI 隨機存取讀取器

**Files:**
- Create：`app/lib/library/kf8_metadata.dart`
- Create：`app/test/library/kf8_metadata_test.dart`

**Interfaces:**
- Consumes：`app/test/fixtures/sample.azw3`（Task 3）
- Produces：`_MobiRecordReader`（私有 class，本檔案內部使用）；`_uint16(Uint8List, int) → int`／`_uint32(Uint8List, int) → int`（頂層私有函式）——Task 5 直接沿用這些函式名稱與簽章

- [ ] **Step 1：寫失敗測試——驗證能正確解析 PDB 標頭與 record 0 大小**

在 `app/test/library/kf8_metadata_test.dart` 新增：

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/library/kf8_metadata.dart';

void main() {
  group('extractKf8Metadata：真實 AZW3 樣本', () {
    test('可成功解析（不拋出例外）', () async {
      final result = await extractKf8Metadata('test/fixtures/sample.azw3');
      expect(result, isNotNull);
    });
  });
}
```

- [ ] **Step 2：執行測試確認失敗**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter test test/library/kf8_metadata_test.dart
```

Expected：因 `kf8_metadata.dart`／`extractKf8Metadata` 尚未定義而編譯失敗。

- [ ] **Step 3：實作 `kf8_metadata.dart`（底層讀取器部分）**

建立 `app/lib/library/kf8_metadata.dart`：

```dart
import 'dart:io';
import 'dart:typed_data';

int _uint16(Uint8List bytes, int offset) =>
    ByteData.sublistView(bytes, offset, offset + 2).getUint16(0, Endian.big);

int _uint32(Uint8List bytes, int offset) =>
    ByteData.sublistView(bytes, offset, offset + 4).getUint32(0, Endian.big);

Future<Uint8List> _readRange(RandomAccessFile raf, int start, int end) async {
  await raf.setPosition(start);
  return raf.read(end - start);
}

/// 對 PDB（Palm Database）容器格式的最小隨機存取讀取器，比照
/// `readest/foliate-js`（釘定 commit dd71f2be356563c16a23272686189fcfb45d0b82）
/// `mobi.js` 的 `class PDB` 邏輯：讀取 78 bytes 標頭取得 record 數量，讀取
/// record info list 取得每筆 record 的起訖 offset，供之後隨機讀取任一 record
/// （metadata 標頭在 record 0，封面圖片在 `resourceStart + coverOffset`）。
class _MobiRecordReader {
  _MobiRecordReader._(this._raf, this._offsets);

  final RandomAccessFile _raf;
  final List<List<int>> _offsets;

  static Future<_MobiRecordReader> open(File file) async {
    final raf = await file.open();
    final header = await _readRange(raf, 0, 78);
    final type = String.fromCharCodes(header.sublist(60, 64));
    final creator = String.fromCharCodes(header.sublist(64, 68));
    if (type != 'BOOK' || creator != 'MOBI') {
      await raf.close();
      throw const FormatException('不是有效的 MOBI/KF8 檔案：PDB type/creator 不符');
    }
    final numRecords = _uint16(header, 76);
    final infoList = await _readRange(raf, 78, 78 + numRecords * 8);
    final starts = [for (var i = 0; i < numRecords; i++) _uint32(infoList, i * 8)];
    final fileLength = await raf.length();
    final offsets = [
      for (var i = 0; i < starts.length; i++)
        [starts[i], i + 1 < starts.length ? starts[i + 1] : fileLength],
    ];
    return _MobiRecordReader._(raf, offsets);
  }

  Future<Uint8List> readRecord(int index) async {
    if (index < 0 || index >= _offsets.length) {
      throw RangeError('record index $index 超出範圍（共 ${_offsets.length} 筆）');
    }
    final range = _offsets[index];
    return _readRange(_raf, range[0], range[1]);
  }

  Future<void> close() => _raf.close();
}

/// 讀取 KF8 (AZW3) 檔案的 metadata。目前為最小實作，Task 5 會擴充回傳欄位。
Future<Map<String, Object?>> extractKf8Metadata(String filePath) async {
  final reader = await _MobiRecordReader.open(File(filePath));
  try {
    await reader.readRecord(0);
    return const {};
  } finally {
    await reader.close();
  }
}
```

- [ ] **Step 4：執行測試確認通過**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter test test/library/kf8_metadata_test.dart
```

Expected：通過（僅驗證不拋出例外，Task 5 補上欄位斷言）。

- [ ] **Step 5：新增邊界測試——PDB type/creator 不符時拋出 `FormatException`**

在 `app/test/library/kf8_metadata_test.dart` 追加：

```dart
import 'dart:typed_data';

test('PDB type/creator 不符時拋出 FormatException', () async {
  final bytes = Uint8List(90);
  bytes.setRange(60, 64, 'ZZZZ'.codeUnits);
  bytes.setRange(64, 68, 'ZZZZ'.codeUnits);
  final tempFile = File('${Directory.systemTemp.path}/kf8_test_invalid.azw3');
  await tempFile.writeAsBytes(bytes);
  addTearDown(() => tempFile.delete());

  expect(
    () => extractKf8Metadata(tempFile.path),
    throwsA(isA<FormatException>()),
  );
});
```

執行：

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter test test/library/kf8_metadata_test.dart
```

Expected：通過。

- [ ] **Step 6：Commit**

```bash
cd "U:/MyDeveloper/AI/elinkBook"
git add app/lib/library/kf8_metadata.dart app/test/library/kf8_metadata_test.dart
git commit -m "feat(epic-11): Issue 2——KF8 底層 PDB record 隨機存取讀取器"
```

---

### Task 5：KF8 metadata／封面／DRM 擷取

**Files:**
- Modify：`app/lib/library/kf8_metadata.dart`
- Modify：`app/test/library/kf8_metadata_test.dart`

**Interfaces:**
- Consumes：Task 4 的 `_MobiRecordReader`／`_uint16`／`_uint32`
- Produces：`extractKf8Metadata(String filePath) → Future<Map<String, Object?>>`（鍵：`title`／`author`／`isFixedLayout`／`coverBytes`，與既有 native `extractMetadata` channel 回傳格式一致）；`DrmProtectedException`（公開例外類別）

- [ ] **Step 1：寫失敗測試——DRM 加密偵測（合成緩衝區，不使用真實受保護檔案）**

在 `app/test/library/kf8_metadata_test.dart` 追加：

```dart
Uint8List _buildSyntheticPdb({required int encryption}) {
  // 最小合法 PDB + record 0（僅 PalmDoc header 16 bytes），足夠讓
  // extractKf8Metadata 在讀到 encryption 欄位後就能判定，不需要完整
  // MOBI/EXTH 標頭。比照 Issue 1 Spike（reviews/spike-issue1-kf8-cbz-drm.md
  // Task 5）驗證過的合成邏輯，從 Python 移植為 Dart。
  final bytes = Uint8List(78 + 8 + 16);
  bytes.setRange(60, 64, 'BOOK'.codeUnits);
  bytes.setRange(64, 68, 'MOBI'.codeUnits);
  ByteData.sublistView(bytes, 76, 78).setUint16(0, 1, Endian.big); // numRecords
  ByteData.sublistView(bytes, 78, 82).setUint32(0, 86, Endian.big); // record 0 offset
  ByteData.sublistView(bytes, 86 + 12, 86 + 14).setUint16(0, encryption, Endian.big);
  return bytes;
}

Future<String> _writeTempAzw3(Uint8List bytes, String name) async {
  final file = File('${Directory.systemTemp.path}/$name');
  await file.writeAsBytes(bytes);
  return file.path;
}

group('DRM 偵測', () {
  test('encryption=0（未加密）不拋出例外', () async {
    final path = await _writeTempAzw3(_buildSyntheticPdb(encryption: 0), 'kf8_test_unencrypted.azw3');
    addTearDown(() => File(path).delete());

    await expectLater(extractKf8Metadata(path), completes);
  });

  test('encryption=1（舊版 Mobipocket 加密）拋出 DrmProtectedException', () async {
    final path = await _writeTempAzw3(_buildSyntheticPdb(encryption: 1), 'kf8_test_legacy_drm.azw3');
    addTearDown(() => File(path).delete());

    expect(
      () => extractKf8Metadata(path),
      throwsA(isA<DrmProtectedException>()),
    );
  });

  test('encryption=2（Mobipocket 加密）拋出 DrmProtectedException', () async {
    final path = await _writeTempAzw3(_buildSyntheticPdb(encryption: 2), 'kf8_test_drm.azw3');
    addTearDown(() => File(path).delete());

    expect(
      () => extractKf8Metadata(path),
      throwsA(isA<DrmProtectedException>()),
    );
  });
});

group('metadata 欄位（真實 AZW3 樣本）', () {
  test('title 含 "Time Machine"', () async {
    final result = await extractKf8Metadata('test/fixtures/sample.azw3');
    expect(result['title'], contains('Time Machine'));
  });

  test('coverBytes 非空', () async {
    final result = await extractKf8Metadata('test/fixtures/sample.azw3');
    expect(result['coverBytes'], isA<Uint8List>());
    expect((result['coverBytes'] as Uint8List).isNotEmpty, isTrue);
  });
});
```

- [ ] **Step 2：執行測試確認失敗**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter test test/library/kf8_metadata_test.dart
```

Expected：DRM 與 metadata 欄位相關測試失敗（`DrmProtectedException` 未定義／`title`/`coverBytes` 欄位不存在，encryption=0 案例目前不會失敗但 title/cover 測試會失敗）。

- [ ] **Step 3：實作完整 metadata／封面／DRM 擷取邏輯**

把 `app/lib/library/kf8_metadata.dart` 的 `extractKf8Metadata` 與其上方內容改為：

```dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'library_repository.dart';

/// KF8 (AZW3) 檔案偵測到 DRM 加密內容時拋出，呼叫端須中止該書匯入、不寫入
/// `Book` 記錄（spec.md「KF8 (AZW3) 支援」）。
class DrmProtectedException implements Exception {
  final String message;
  const DrmProtectedException(this.message);

  @override
  String toString() => 'DrmProtectedException: $message';
}

int _uint16(Uint8List bytes, int offset) =>
    ByteData.sublistView(bytes, offset, offset + 2).getUint16(0, Endian.big);

int _uint32(Uint8List bytes, int offset) =>
    ByteData.sublistView(bytes, offset, offset + 4).getUint32(0, Endian.big);

Future<Uint8List> _readRange(RandomAccessFile raf, int start, int end) async {
  await raf.setPosition(start);
  return raf.read(end - start);
}

class _MobiRecordReader {
  _MobiRecordReader._(this._raf, this._offsets);

  final RandomAccessFile _raf;
  final List<List<int>> _offsets;

  static Future<_MobiRecordReader> open(File file) async {
    final raf = await file.open();
    final header = await _readRange(raf, 0, 78);
    final type = String.fromCharCodes(header.sublist(60, 64));
    final creator = String.fromCharCodes(header.sublist(64, 68));
    if (type != 'BOOK' || creator != 'MOBI') {
      await raf.close();
      throw const FormatException('不是有效的 MOBI/KF8 檔案：PDB type/creator 不符');
    }
    final numRecords = _uint16(header, 76);
    final infoList = await _readRange(raf, 78, 78 + numRecords * 8);
    final starts = [for (var i = 0; i < numRecords; i++) _uint32(infoList, i * 8)];
    final fileLength = await raf.length();
    final offsets = [
      for (var i = 0; i < starts.length; i++)
        [starts[i], i + 1 < starts.length ? starts[i + 1] : fileLength],
    ];
    return _MobiRecordReader._(raf, offsets);
  }

  Future<Uint8List> readRecord(int index) async {
    if (index < 0 || index >= _offsets.length) {
      throw RangeError('record index $index 超出範圍（共 ${_offsets.length} 筆）');
    }
    final range = _offsets[index];
    return _readRange(_raf, range[0], range[1]);
  }

  Future<void> close() => _raf.close();
}

/// CP1252（Windows-1252）0x80-0x9F 這 32 個位元組對應的 Unicode 碼點，與
/// ISO-8859-1（`dart:convert` 的 `latin1`）在此區段的定義不同（其餘
/// 0x00-0x7F／0xA0-0xFF 兩者相同）。舊版 MOBI（`encoding == 1252`）用此
/// 表解碼；未定義的位元組（Windows-1252 保留未使用）直接保留原碼位。
const _cp1252HighBytes = <int, int>{
  0x80: 0x20AC, 0x82: 0x201A, 0x83: 0x0192, 0x84: 0x201E, 0x85: 0x2026,
  0x86: 0x2020, 0x87: 0x2021, 0x88: 0x02C6, 0x89: 0x2030, 0x8A: 0x0160,
  0x8B: 0x2039, 0x8C: 0x0152, 0x8E: 0x017D, 0x91: 0x2018, 0x92: 0x2019,
  0x93: 0x201C, 0x94: 0x201D, 0x95: 0x2022, 0x96: 0x2013, 0x97: 0x2014,
  0x98: 0x02DC, 0x99: 0x2122, 0x9A: 0x0161, 0x9B: 0x203A, 0x9C: 0x0153,
  0x9E: 0x017E, 0x9F: 0x0178,
};

String _decodeText(Uint8List bytes, int encoding) {
  if (encoding == 65001) return utf8.decode(bytes, allowMalformed: true);
  return String.fromCharCodes(bytes.map((b) => _cp1252HighBytes[b] ?? b));
}

class _MobiHeaders {
  const _MobiHeaders({
    required this.mobiLength,
    required this.exthFlag,
    required this.titleOffset,
    required this.titleLength,
    required this.encoding,
    required this.resourceStart,
  });

  final int mobiLength;
  final int exthFlag;
  final int titleOffset;
  final int titleLength;
  final int encoding;
  final int resourceStart;
}

_MobiHeaders _parseMobiHeaders(Uint8List record0) {
  final magic = String.fromCharCodes(record0.sublist(16, 20));
  if (magic != 'MOBI') {
    throw const FormatException('不是有效的 MOBI/KF8 檔案：缺少 MOBI 標頭');
  }
  return _MobiHeaders(
    mobiLength: _uint32(record0, 20),
    exthFlag: _uint32(record0, 128),
    titleOffset: _uint32(record0, 84),
    titleLength: _uint32(record0, 88),
    encoding: _uint32(record0, 28),
    resourceStart: _uint32(record0, 108),
  );
}

/// 只解析本模組需要的 5 個 EXTH tag：100=creator（作者）、122=fixedLayout、
/// 201=coverOffset、202=thumbnailOffset、503=title——其餘 tag 略過。
Map<int, List<Object>> _parseExth(Uint8List record0, int exthOffset, int encoding) {
  if (exthOffset + 12 > record0.length) return {};
  final magic = String.fromCharCodes(record0.sublist(exthOffset, exthOffset + 4));
  if (magic != 'EXTH') return {};
  final count = _uint32(record0, exthOffset + 8);
  final results = <int, List<Object>>{};
  var offset = exthOffset + 12;
  for (var i = 0; i < count; i++) {
    final type = _uint32(record0, offset);
    final length = _uint32(record0, offset + 4);
    final data = record0.sublist(offset + 8, offset + length);
    if (type == 100 || type == 122 || type == 503) {
      results.putIfAbsent(type, () => []).add(_decodeText(data, encoding));
    } else if (type == 201 || type == 202) {
      results.putIfAbsent(type, () => []).add(_uint32(data, 0));
    }
    offset += length;
  }
  return results;
}

String? _firstString(List<Object>? values) =>
    (values == null || values.isEmpty) ? null : values.first as String;

int? _firstInt(List<Object>? values) =>
    (values == null || values.isEmpty) ? null : values.first as int;

/// 讀取 KF8 (AZW3) 檔案的 metadata（`title`／`author`／`isFixedLayout`／
/// `coverBytes`，鍵名與既有 native `extractMetadata` channel 回傳格式一致，
/// 供 `book_import_service_impl.dart` 以相同方式消費）。[filePath] 可為本機
/// 路徑或 `content://` URI——後者先透過既有、格式無關的 `copyContentUriToFile`
/// 原生方法複製到暫存檔（`dart:io` 無法對 `content://` URI 做隨機存取讀取，
/// 讀封面資源需要 range read，比照 ADR 0002 既有限制），完成後清除暫存檔。
///
/// `PALMDOC_HEADER.encryption`（record 0 內 offset 12，2 bytes 大端序）非 0
/// 時拋出 [DrmProtectedException]，不繼續解析（`mobi.js` 本身不會因此欄位
/// 拒絕開啟，偵測必須獨立於 `mobi.js` 之外，見 Issue 1 Spike 查證）。
Future<Map<String, Object?>> extractKf8Metadata(String filePath) async {
  if (filePath.contains('://')) {
    final tempDir = await getTemporaryDirectory();
    final tempPath = p.join(
      tempDir.path,
      'kf8_probe_${DateTime.now().microsecondsSinceEpoch}.azw3',
    );
    await kBookMetadataChannel.invokeMethod<void>(
      'copyContentUriToFile',
      {'uri': filePath, 'destinationPath': tempPath},
    );
    try {
      return await _extractFromLocalFile(tempPath);
    } finally {
      final tempFile = File(tempPath);
      if (tempFile.existsSync()) tempFile.deleteSync();
    }
  }
  return _extractFromLocalFile(filePath);
}

Future<Map<String, Object?>> _extractFromLocalFile(String filePath) async {
  final reader = await _MobiRecordReader.open(File(filePath));
  try {
    final record0 = await reader.readRecord(0);
    final encryption = _uint16(record0, 12);
    if (encryption != 0) {
      throw const DrmProtectedException('此檔案受 DRM 保護，暫不支援');
    }

    final headers = _parseMobiHeaders(record0);
    final exthOffset = headers.mobiLength + 16;
    final exth = (headers.exthFlag & 0x40) != 0
        ? _parseExth(record0, exthOffset, headers.encoding)
        : <int, List<Object>>{};

    final title = _firstString(exth[503]) ??
        _decodeText(
          record0.sublist(
            headers.titleOffset,
            headers.titleOffset + headers.titleLength,
          ),
          headers.encoding,
        );

    Uint8List? coverBytes;
    final coverOffset = _firstInt(exth[201]) ?? _firstInt(exth[202]);
    if (coverOffset != null) {
      coverBytes = await reader.readRecord(headers.resourceStart + coverOffset);
    }

    return {
      'title': title,
      'author': _firstString(exth[100]),
      'isFixedLayout': _firstString(exth[122]) == 'true',
      'coverBytes': coverBytes,
    };
  } finally {
    await reader.close();
  }
}
```

- [ ] **Step 4：執行測試確認通過**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter test test/library/kf8_metadata_test.dart
```

Expected：全數通過，包含 DRM 三種情境（`encryption=0/1/2`）與真實樣本的 `title`／`coverBytes` 斷言。

- [ ] **Step 5：`flutter analyze` 確認乾淨**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter analyze
```

Expected：0 issues。

- [ ] **Step 6：Commit**

```bash
cd "U:/MyDeveloper/AI/elinkBook"
git add app/lib/library/kf8_metadata.dart app/test/library/kf8_metadata_test.dart
git commit -m "feat(epic-11): Issue 2——KF8 metadata/封面擷取與 DRM 位元組偵測"
```

---

### Task 6：匯入管線接線（`book_import_service_impl.dart`）

**Files:**
- Modify：`app/lib/library/book_import_service_impl.dart`
- Modify：`app/test/library/book_import_service_impl_test.dart`（若不存在則新建，先執行 `ls app/test/library/` 確認實際檔名）

**Interfaces:**
- Consumes：`extractKf8Metadata`／`DrmProtectedException`（Task 5，`app/lib/library/kf8_metadata.dart`）
- Produces：`BookImportServiceImpl` 對 `BookFileFormat.azw3` 的匯入行為——成功時建立含 title/author/coverPath/isFixedLayout 的 `Book`；DRM 加密時回傳 `null`（不建立記錄）

- [ ] **Step 1：確認既有測試檔案位置與既有測試模式**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
ls test/library/ | grep import_service
```

若存在 `book_import_service_impl_test.dart`，開啟該檔閱讀既有 TXT 分支的測試寫法（`format == BookFileFormat.txt` 情境），以下 Step 2 的新測試比照其 mock/fixture 建立方式撰寫（例如既有測試如何建構 `BookImportServiceImpl` 實例、如何提供 `coversDirectory`/`importedBooksDirectory` 建構參數）。若檔案不存在，以 Task 3-5 已有的 `test/fixtures/sample.azw3` 與 `MethodChannel` mock 為基礎新建。

- [ ] **Step 2：寫失敗測試——匯入 AZW3 成功建立書籍、DRM 樣本被攔截**

在對應測試檔追加（若既有測試檔已有 `setUp`/`tearDown`/`MethodChannel` mock 樣板，比照其結構，不要重複定義）：

```dart
test('匯入 AZW3：title/coverPath 正確寫入 Book', () async {
  final repository = FakeLibraryRepository();
  final coversDir = await Directory.systemTemp.createTemp('covers_test');
  addTearDown(() => coversDir.delete(recursive: true));
  final service = BookImportServiceImpl(
    repository: repository,
    coversDirectory: coversDir,
  );

  final result = await service.importFiles(
    ['test/fixtures/sample.azw3'],
    displayNames: ['sample.azw3'],
  );

  expect(result.importedBooks, hasLength(1));
  final book = result.importedBooks.first;
  expect(book.title, contains('Time Machine'));
  expect(book.format, BookFileFormat.azw3);
  expect(book.coverPath, isNotNull);
  expect(File(book.coverPath!).existsSync(), isTrue);
});

test('匯入受 DRM 保護的 AZW3：不建立 Book 記錄', () async {
  final repository = FakeLibraryRepository();
  final service = BookImportServiceImpl(repository: repository);

  final bytes = Uint8List(78 + 8 + 16);
  bytes.setRange(60, 64, 'BOOK'.codeUnits);
  bytes.setRange(64, 68, 'MOBI'.codeUnits);
  ByteData.sublistView(bytes, 76, 78).setUint16(0, 1, Endian.big);
  ByteData.sublistView(bytes, 78, 82).setUint32(0, 86, Endian.big);
  ByteData.sublistView(bytes, 86 + 12, 86 + 14).setUint16(0, 2, Endian.big);
  final drmFile = File('${Directory.systemTemp.path}/import_test_drm.azw3');
  await drmFile.writeAsBytes(bytes);
  addTearDown(() => drmFile.delete());

  final result = await service.importFiles(
    [drmFile.path],
    displayNames: ['drm_sample.azw3'],
  );

  expect(result.importedBooks, isEmpty);
});
```

（`FakeLibraryRepository` 若既有測試檔已定義則直接沿用；`Uint8List`/`ByteData`/`Endian` 需要 `import 'dart:typed_data';`。）

- [ ] **Step 3：執行測試確認失敗**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter test test/library/<實際測試檔名>.dart
```

Expected：因 `book_import_service_impl.dart` 尚未處理 `BookFileFormat.azw3` 而失敗（目前會落入既有 `else` 分支呼叫不存在的原生 `extractMetadata` 對 `azw3` 格式，`PlatformException` 被吞掉，`title` 停留在檔名、`coverPath` 為 `null`，斷言失敗；DRM 案例則因為完全沒有攔截邏輯，直接建立一筆書籍記錄）。

- [ ] **Step 4：實作匯入分支**

在 `app/lib/library/book_import_service_impl.dart` 新增 import：

```dart
import 'kf8_metadata.dart';
```

把 `_importSingleFile()` 內原本的：

```dart
    if (format == BookFileFormat.txt) {
      final coverBytes = await generateTxtCover(fallbackTitle);
      coverPath = await _landCover(coverBytes, id);
    } else {
```

改為：

```dart
    if (format == BookFileFormat.txt) {
      final coverBytes = await generateTxtCover(fallbackTitle);
      coverPath = await _landCover(coverBytes, id);
    } else if (format == BookFileFormat.azw3) {
      try {
        final metadata = await extractKf8Metadata(resolvedUri);
        final extractedTitle = metadata['title'] as String?;
        if (extractedTitle != null && extractedTitle.isNotEmpty) {
          title = extractedTitle;
        }
        author = metadata['author'] as String?;
        isFixedLayout = metadata['isFixedLayout'] as bool?;
        final coverBytes = metadata['coverBytes'] as Uint8List?;
        if (coverBytes != null) {
          coverPath = await _landCover(coverBytes, id);
        }
      } on DrmProtectedException {
        // DRM 加密：明確不支援，不可比照下方 PlatformException 分支降級為
        // 「無封面/檔名為標題」繼續建立書籍記錄——中止本書匯入
        // （spec.md「KF8 (AZW3) 支援」）。
        return null;
      } catch (_) {
        // 其餘解析失敗（非 DRM，例如檔案損毀）：降級為「檔名為標題、無封面」，
        // 比照既有 PlatformException 分支慣例，不中斷整批匯入。
      }
    } else {
```

- [ ] **Step 5：執行測試確認通過**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter test test/library/<實際測試檔名>.dart
```

Expected：全數通過。

- [ ] **Step 6：全專案回歸測試**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter test 2>&1 | tail -20
flutter analyze
```

Expected：`flutter analyze` 0 issues；`flutter test` 全數通過，總數較 Task 1 Step 1 記錄的基準線增加（新增的 `book_format_test.dart`／`kf8_metadata_test.dart`／匯入服務測試皆計入）。

- [ ] **Step 7：Commit**

```bash
cd "U:/MyDeveloper/AI/elinkBook"
git add app/lib/library/book_import_service_impl.dart app/test/library/
git commit -m "feat(epic-11): Issue 2——匯入管線接上 KF8 metadata/DRM 擷取"
```

---

### Task 7：真機驗證與文件收尾

**Files:**
- Create：`app/integration_test/foliate_kf8_test.dart`
- Modify：`docs/epics/epic-11-multi-format-reader/issues.md`

**Interfaces:**
- Consumes：Task 1-6 全部完成
- Produces：真機驗證證據，供 Issue 2 收尾與 Issue 3（CBZ，依賴本 Issue 的 `FoliateReaderView` 泛化結果）開始

- [ ] **Step 1：寫真機整合測試**

在 `app/integration_test/foliate_kf8_test.dart` 新增（比照既有 `app/integration_test/foliate_epub_reader_view_test.dart` 的斷言方式——等待 `Key('reader_loading_indicator')` 消失且無 `Key('reader_error_text')`；若該既有檔案已隨 Task 1 改名為 `foliate_reader_view_test.dart` 等效檔案，以實際檔名為準參照其斷言寫法）：

```dart
import 'package:elinkbook/main.dart' as app;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('匯入並開啟真實 AZW3 檔案，成功渲染無錯誤', (tester) async {
    app.main();
    await tester.pumpAndSettle();

    // 匯入 test/fixtures/sample.azw3（實際匯入操作步驟依現有 LibraryScreen
    // 匯入流程 UI 撰寫，比照既有 EPUB/PDF 真機測試的檔案選擇器 mock 方式）。

    await tester.pumpUntil(
      () => find.byKey(const Key('reader_loading_indicator')).evaluate().isEmpty,
      timeout: const Duration(seconds: 15),
    );

    expect(find.byKey(const Key('reader_error_text')), findsNothing);
  });
}
```

**注意**：`pumpUntil` 若專案尚未有這個測試輔助函式，改用既有 `foliate_epub_reader_view_test.dart`（或改名後的等效檔案）已使用的等待模式（`tester.pump()` 迴圈或既有 helper），不要在本 Task 新造一個不存在的輔助函式。

- [ ] **Step 2：真機執行**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
adb devices -l
flutter test integration_test/foliate_kf8_test.dart -d <device-id>
```

Expected：測試通過；同時人工在真機上手動驗證：直排/避頭尾正確（可套用直排偏好觀察 `sample.azw3` 是否正確轉為 `vertical-rl`）、目錄按鈕可開啟、書籤可新增與跳轉、劃線/備註功能正常（皆繼承自既有 `FoliateReaderView` 機制，非新開發）。

- [ ] **Step 3：更新 `issues.md` Issue 2 狀態**

把 `docs/epics/epic-11-multi-format-reader/issues.md` 中 Issue 2 的 `**Status:**`（現為 `ready-for-agent`）改為完成狀態，內容涵蓋：`flutter test`／`flutter analyze` 結果、真機驗證結果、已知殘留風險（Task 2 Step 10 記錄的 KF8 FXL 分派時機這個子情境尚未深度驗證）。

- [ ] **Step 4：Commit**

```bash
cd "U:/MyDeveloper/AI/elinkBook"
git add app/integration_test/foliate_kf8_test.dart docs/epics/epic-11-multi-format-reader/issues.md
git commit -m "test(epic-11): Issue 2——真機整合測試與收尾"
```

---

## Self-Review（撰寫計劃時的自我檢查）

**Spec 覆蓋度**：`issues.md` Issue 2「範圍」1-6 逐項對應：
1. `FoliateEpubReaderView`→`FoliateReaderView` 泛化重構 → Task 1
2. Vendor `mobi.js`／`vendor/fflate.js` → Task 3
3. `BookFormat`/`BookFileFormat` 新增 `azw3`，`ReaderScreen` 分派 → Task 2
4. 純 Dart KF8 metadata／封面擷取器 → Task 4-5
5. KF8 DRM 位元組偵測＋`DrmProtectedException` → Task 5-6
6. `Book.isFixedLayout` 廣義化 KF8 分支 → Task 5（`isFixedLayout` 欄位來自 EXTH tag 122）＋ Task 6（寫入 `Book`）

**Placeholder 掃描**：全文無 TBD/待補字樣；Task 6 Step 1 的「若不存在則新建」與 Task 7 Step 1 的「以實際檔名為準參照」是刻意的條件式指引（既有測試檔實際內容需執行時查證，非可預先假設），比照本專案既有 plan 對這類情況的慣例處理方式（例如 `epic-24` spec.md 對「具體策略留給實作階段」的處理原則），不是缺漏規格。

**型別一致性**：`extractKf8Metadata()` 回傳的 `Map<String, Object?>` 鍵名（`title`／`author`／`isFixedLayout`／`coverBytes`）在 Task 4（初版）→ Task 5（完整版）→ Task 6（呼叫端消費）三處保持一致；`DrmProtectedException` 在 Task 5 定義、Task 6 捕捉，型別與 import 路徑（`package:elinkbook/library/kf8_metadata.dart`）一致；`_MobiRecordReader`／`_uint16`／`_uint32`／`_readRange` 為 Task 4 定義的私有符號，Task 5 直接在同一檔案內擴充（非跨檔案引用，不存在型別不一致風險）。

**API 依據來源（非憑空杜撰）**：本計畫所有 MOBI/EXTH 位元組偏移量（`PDB_HEADER`／`PALMDOC_HEADER`／`MOBI_HEADER`／`EXTH_HEADER`／`EXTH_RECORD_TYPE` 各欄位 offset）與演算法（`getMetadata()`／`getCover()`／`readMobiMetadata()`）皆直接讀取釘定 commit（`dd71f2be356563c16a23272686189fcfb45d0b82`）當下的 `mobi.js` 原始碼逐一核對得出（`readMobiMetadata()` 是 upstream 專為「platform-native pre-parser」設計的參考實作，其 doc comment 明確說明用途與本計畫的匯入時 metadata 擷取需求完全對應），非憑印象猜測；`reader_screen.dart` 的三處 switch 範例與一處 equality 比較範例皆已實際讀取現有原始碼確認行號與內容。CP1252 高位元組對照表為公開、穩定的標準編碼表，非本計畫自創。

**已知範圍邊界（非缺陷）**：EXTH「combo」格式（`mobi.version < 8` 但透過 `exth.boundary` 指向另一個 KF8 區塊的舊式相容檔案）未在 Task 5 實作——AZW3（KF8 專屬副檔名）之設計目的即排除這種相容性打包，真實 KF8 (AZW3) 樣本檔案版本恆 `>= 8`，此邊界情況留待真機測試若真的遇到相容性打包檔案再行評估，不阻塞本 Issue。

## Execution Handoff

Plan complete and saved to `docs/epics/epic-11-multi-format-reader/plans/plan-issue-2.md`。兩種執行方式：

1. **Subagent-Driven（推薦）**——每個 Task 交給一個全新 subagent 執行，Task 之間逐一審查，快速迭代。
2. **Inline Execution**——在本次會談中依 Task 順序批次執行，設檢查點逐一確認。

要採用哪一種方式？
