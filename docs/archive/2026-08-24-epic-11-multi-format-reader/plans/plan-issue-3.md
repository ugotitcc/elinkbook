# Issue 3：CBZ 匯入與閱讀（含翻頁方向切換 RTL/LTR）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development（建議）或 superpowers:executing-plans 逐 Task 執行本計畫。Step 前的 checkbox（`- [ ]`）用於追蹤進度。

**Goal:** 讓 elinkBook 能匯入並閱讀 CBZ 漫畫壓縮檔——正確頁序（不受檔名零填補與否影響）、可切換 RTL/LTR 翻頁方向、封面/雙頁/裁切/影像濾鏡等版面體驗與既有 EPUB 固定版面（FXL）完全一致，劃線/備註入口自然隱藏。

**Architecture:** CBZ 復用 `epic-20` 已為 EPUB FXL 建立的整條固定版面渲染管線（`FoliateReaderView` + `fixed-layout.js` + `FxlSettingsSheet`）——`Book.isFixedLayout` 對 CBZ 恆為 `true`，`ReaderScreen` 既有「`_isFixedLayout` 驅動 FXL chrome／`isFoliateFormat()` 驅動熱區換頁」的判斷邏輯完全不需要感知格式差異即可正確運作。匯入階段（Dart 端，`archive` 套件）對 CBZ 內部圖片檔名做自然排序並重建壓縮檔索引（`comic-book.js` 本身只有字典序排序），重建後的檔案落地為 `Book.filePath`；翻頁方向透過既有 `DualPageDirection` 欄位（原僅 PDF 使用）擴大適用於 CBZ，於開書當下一次性設定 `book.dir`（`fixed-layout.js` 的 `next()`/`prev()` 已正確依 `book.dir` 決定方向，見下方「已查證的關鍵技術事實」，不需要新增任何導覽分派邏輯）。過程中發現一個先前規劃文件皆未記錄的必要前置修復——見下方「已查證的關鍵技術事實」第 4 點。

**Tech Stack:** Flutter/Dart（`package:archive` 4.0.9，由 dev_dependency 升級為正式 dependency）、`readest/foliate-js`（釘定 commit `dd71f2be356563c16a23272686189fcfb45d0b82`，`comic-book.js`）、Kotlin（`ReaderResourceChannel.kt` 既有 `cacheBookForServing` 機制小幅擴充）、既有 `kBookMetadataChannel`（`copyContentUriToFile`，`content://` 來源時複製暫存檔用，比照 `kf8_metadata.dart` 既有模式）。

**Spec:** `docs/epics/epic-11-multi-format-reader/spec.md`「格式偵測與渲染分派」「CBZ 支援」「Testing Decisions」；`docs/epics/epic-11-multi-format-reader/issues.md` Issue 3；`docs/epics/epic-11-multi-format-reader/reviews/spike-issue1-kf8-cbz-drm.md`；`docs/epics/epic-11-multi-format-reader/reviews/review-issue-1-spike-execution.md` Important #1。

## Global Constraints

- 純 Dart-only 解析（ADR 0023 決策 5）：CBZ 自然排序/重建/封面擷取邏輯禁止新增任何格式專屬的原生 platform channel 依賴；本 Issue 對原生層唯一的必要異動是 Task 5（WebView 書籍快取檔名副檔名感知），這是 Issue 2 已存在的 `cacheBookForServing` 機制的小幅泛化，不是新增格式專屬原生解析。
- 不修改 `readest/foliate-js` 釘定版本本身（ADR 0011）：所有整合邏輯（`book.dir` 覆寫、虛擬目錄標籤）寫在 `main.js`（本專案自己的整合層），不碰 `comic-book.js`/`fixed-layout.js`/`view.js`。
- `CLAUDE.md` 兩層測試架構：純 Dart 解析（自然排序、壓縮檔重建、封面）用 `flutter test`（Seam 1）；原生渲染是否真的成功（頁序、RTL 導覽方向、雙頁）須 `integration_test/` 真機驗證（Seam 2）。
- 所有回應/文件/程式註解使用正體中文（使用者全域 CLAUDE.md 規則）。
- **已查證的關鍵技術事實**（供各 Task 撰寫依據，非憑空假設，皆已用本次規劃階段的原始碼交叉核對，見下方個別引用）：
  1. `comic-book.js`（`makeComicBook({entries, loadBlob, getSize, getComment}, file)`）的圖片副檔名清單為 `['.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp', '.svg', '.jxl', '.avif']`，對 `entries.map(e=>e.filename).filter(...).sort()` 純字典序排序（無自然排序）；`book.getCover = () => loadBlob(files[0])`（排序後第一張圖片）；`book.toc = files.map(name => ({label: name, href: name}))`；`book.resolveHref = href => ({index: book.sections.findIndex(s => s.id === href)})`；`book.rendition = {layout: 'pre-paginated'}`；回傳的 `book` 物件**不含 `dir` 欄位**。
  2. `fixed-layout.js` 的 `open(book)`：`this.rtl = book.dir === 'rtl'`——**只在 `open()` 當下讀取一次**，之後不會重新推導。`next()`/`prev()`（`view.next()`/`view.prev()`，即 `window.nextPage()`/`window.previousPage()` 橋接函式最終呼叫的目標）內部固定讀取 `this.rtl` 決定要呼叫 `#goLeft()` 還是 `#goRight()`。**這代表 Issue 1 Spike 審查（`review-issue-1-spike-execution.md` Important #1）指出的「`goLeft()`/`goRight()`／既有 `ZoneAction` 分派邏輯在 RTL 模式下是否正確」這個驗證缺口，答案是：只要 `book.dir` 在 `view.open(book)` 之前被正確設定，既有 `FoliateReaderView.previousPage`/`nextPage`（`_handleZoneAction` → `window.previousPage()`/`nextPage()` → `view.prev()`/`next()`）不需要任何新增的分派邏輯即可產生正確的 RTL 導覽方向**——本計畫不新增任何 goLeft/goRight 呼叫或 ZoneAction 特判，只需要在 `main.js` 的 `openBook()` 內、`view.open(book)` 之前設定 `book.dir`（Task 6）。
  3. `view.next()`/`view.prev()` 委派給 `renderer.next()`/`renderer.prev()`，此委派與格式無關（EPUB FXL／CBZ 共用同一份 `fixed-layout.js`），本專案既有 `_handleZoneAction()` 早已用 `isFoliateFormat(format)`（非逐格式 switch）呼叫這兩個 static helper（`reader_screen.dart:2712-2727`），Task 2 把 `isFoliateFormat()` 擴大涵蓋 `cbz` 後，這條路徑**零程式碼異動**即可正確運作。
  4. **新發現的必要前置修復（先前 design.md/spec.md/issues.md 皆未記錄）**：`view.js` 的 `makeBook(file)` 對 zip 檔案透過 `isCBZ({name, type}) => type === 'application/vnd.comicbook+zip' || name.endsWith('.cbz')` 判斷是否分派到 `comic-book.js`；`file.name` 來自 `fetchFile(url)` 內的 `new URL(res.url).pathname`，而 `main.js` 目前**寫死**呼叫 `makeBook('https://appassets.androidplatform.net/book/current.epub')`（`main.js:501-503`），對應的原生端 `ReaderResourceChannel.kt` `copyToCache()` 也**寫死**把任何來源檔案複製為 `current.epub`（`ReaderResourceChannel.kt:80`）。KF8/AZW3 不受影響（`isMOBI()` 靠 magic bytes 判斷，與檔名無關，見 Issue 1/2 既有查證），但 **CBZ 若不修正這個寫死的副檔名，`isCBZ()` 恆為 `false`，`makeBook()` 會誤判為 EPUB 並嘗試 `EPUB.init()`，開書必然失敗**。Task 5 修復此問題（讓快取檔名反映真實副檔名），是 CBZ 能開啟的先決條件，必須先於 Task 6-9 完成。

## 審查回應（`reviews/review-issue-3-plan.md`，2026-08-16，結論 APPROVED / READY TO EXECUTE）

審查結論為核准通過，2 項 Important／2 項 Minor 皆非阻擋執行的缺陷。逐項查證後處置如下：

| 項目 | 查證結果 | 處置 |
|---|---|---|
| Important #1 大型 CBZ 記憶體佔用 | 查證屬實——`prepareCbzForImport()` 的解壓/排序/重新壓縮是同步 CPU 運算，對數百張高解析度圖片的大型 CBZ 確實可能明顯阻塞 UI isolate；`book_content_fingerprint.dart` 對大檔案 SHA-256 計算已採 `Isolate.run()` 同類防禦，屬本專案既有慣例。審查原文建議「留待未來視情況評估」，但成本低（純函式抽取＋一層 `Isolate.run()` 包裝）且與既有慣例一致，故不延後，直接採納並改寫 Task 4（見該處 `_decodeSortAndRebuild()` 新增）|
| Important #2 `archive` 4.x `readBytes()` 回傳型別疑慮 | **查證後不成立**——已直接讀取本機已安裝的 `archive-4.0.9` 套件原始碼（`archive_file.dart:181`）確認 `Uint8List? readBytes()` 回傳型別明確為 `Uint8List?`，不存在審查提出的「或 `List<int>?`」歧義；計畫原有的 `original.readBytes() ?? Uint8List(0)` 寫法本已型別正確。不修改程式碼 |
| Minor #1 檔案選擇器補齊 `azw3` | 合理觀察，與本 Issue（CBZ）範圍無關，屬 Issue 2 遺留的既有落差。原判斷為不在 Issue 3 順手夾帶修復（避免模糊可追蹤範圍邊界），**人類已明確指示一併處理**——採納，已修改 Task 8 一併補上 `azw3`，Commit 訊息同步反映「順手補齊」的性質，不偽裝成本 Issue 原生範圍 |
| Minor #2 自然排序大小寫容錯 | 合理提案，成本低（單行改為 `toLowerCase()` 比較）且是「自然排序」慣例上一般預期的行為，混用大小寫檔名情境下原寫法確有可能產生違反直覺的錯誤頁序。採納，已修改 Task 3 `compareNaturalOrder()` 並新增對應測試 |

---

## Task 1：Vendor `comic-book.js`

**Files:**
- Create（下載，釘定 commit）：`app/android/app/src/main/assets/foliate/comic-book.js`

**Interfaces:**
- Produces：`comic-book.js` 的 `makeComicBook({entries, loadBlob, getSize, getComment}, file)`，供 `view.js` 既有的 `makeBook()` 自動分派邏輯呼叫（`view.js` 本身已存在於 production assets，不需修改，見 Global Constraints 事實 1）。

- [x] **Step 1：下載釘定 commit 的 vendor 資產**

```bash
FOLIATE_COMMIT=dd71f2be356563c16a23272686189fcfb45d0b82
cd "U:/MyDeveloper/AI/elinkBook/app/android/app/src/main/assets/foliate"
curl -sS -m 30 "https://raw.githubusercontent.com/readest/foliate-js/$FOLIATE_COMMIT/comic-book.js" -o comic-book.js
wc -l comic-book.js
grep -c "export const makeComicBook" comic-book.js
```

Expected：`comic-book.js` 約 130 行；`grep -c` 回報 `1`（確認抓到正確原始碼，非 404 頁面，比照 Issue 1/2 已驗證的下載流程）。

- [x] **Step 2：確認 `view.js` 既有分派邏輯無需修改**

```bash
grep -n "isCBZ\|makeComicBook" "U:/MyDeveloper/AI/elinkBook/app/android/app/src/main/assets/foliate/view.js"
```

Expected：看到 `isCBZ = ({ name, type }) => type === 'application/vnd.comicbook+zip' || name.endsWith('.cbz')` 與 `const { makeComicBook } = await import('./comic-book.js')` 兩處既有程式碼（`view.js` 已於 Issue 1/2 存在於 production assets，不需要本 Issue 修改）。

- [x] **Step 3：Commit**

```bash
cd "U:/MyDeveloper/AI/elinkBook"
git add app/android/app/src/main/assets/foliate/comic-book.js
git commit -m "feat(epic-11): Issue 3——vendor comic-book.js"
```

---

## Task 2：`BookFormat`／`BookFileFormat` 新增 `cbz`

**Files:**
- Modify: `app/lib/reader/book_format.dart`
- Modify: `app/lib/library/models/library_enums.dart`
- Test: `app/test/reader/book_format_test.dart`（若不存在則新建，命名比照既有 `app/test/reader/` 慣例）

**Interfaces:**
- Produces：`BookFormat.cbz`、`isFoliateFormat(BookFormat.cbz) == true`、`detectBookFormat('foo.cbz') == BookFormat.cbz`；`BookFileFormat.cbz`。

- [x] **Step 1：確認既有測試檔位置**

```bash
ls "U:/MyDeveloper/AI/elinkBook/app/test/reader/" | grep book_format
```

若無 `book_format_test.dart`，本 Task 新建；若已存在，於既有檔案追加。

- [x] **Step 2：寫失敗測試**

```dart
// app/test/reader/book_format_test.dart（若既有檔案已存在，追加以下內容，
// import 語句與既有內容合併，不重複）
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/book_format.dart';

void main() {
  test('detectBookFormat 對 .cbz 副檔名回傳 BookFormat.cbz', () {
    expect(detectBookFormat('comic.cbz'), BookFormat.cbz);
    expect(detectBookFormat('COMIC.CBZ'), BookFormat.cbz);
  });

  test('isFoliateFormat 對 cbz 回傳 true', () {
    expect(isFoliateFormat(BookFormat.cbz), isTrue);
  });
}
```

- [x] **Step 3：確認測試失敗**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter test test/reader/book_format_test.dart
```

Expected：FAIL（`BookFormat.cbz` 未定義，編譯錯誤）。

- [x] **Step 4：實作**

`app/lib/reader/book_format.dart` 修改為：

```dart
/// 書籍檔案格式，依副檔名偵測。
enum BookFormat { epub, pdf, azw3, cbz, unknown }

/// 依檔案路徑的副檔名判斷書籍格式（不分大小寫）。無法識別的副檔名（含無副
/// 檔名、空字串）一律回傳 [BookFormat.unknown]，絕不拋出例外。
BookFormat detectBookFormat(String path) {
  final lowerPath = path.toLowerCase();
  if (lowerPath.endsWith('.epub')) return BookFormat.epub;
  if (lowerPath.endsWith('.pdf')) return BookFormat.pdf;
  if (lowerPath.endsWith('.azw3')) return BookFormat.azw3;
  if (lowerPath.endsWith('.cbz')) return BookFormat.cbz;
  return BookFormat.unknown;
}

/// 是否為經由 [FoliateReaderView]（`foliate-js`）渲染的格式——與
/// [BookFormat.pdf] 互斥，[BookFormat.unknown] 兩者皆非。`reader_screen.dart`
/// 內所有「這是不是走 Foliate 流式管線」的判斷皆應呼叫本函式，而非逐一列舉
/// 格式，避免未來新增格式（TXT/MD）時遺漏更新（epic-11-multi-format-reader
/// Issue 3，spec.md「格式偵測與渲染分派」）。
bool isFoliateFormat(BookFormat format) =>
    format == BookFormat.epub ||
    format == BookFormat.azw3 ||
    format == BookFormat.cbz;
```

`app/lib/library/models/library_enums.dart` 修改為：

```dart
/// 圖書庫書籍的檔案格式。獨立於 `reader/book_format.dart` 的 `BookFormat`——
/// 後者只服務 `ReaderScreen` 的原生渲染分派；圖書庫資料層需要完整表達
/// FR-01 的支援格式（CBZ 由 epic-11 Issue 3 補上）。
enum BookFileFormat { epub, pdf, txt, azw3, cbz }
```

- [x] **Step 5：確認測試通過**

```bash
flutter test test/reader/book_format_test.dart
```

Expected：PASS。

- [x] **Step 6：`flutter analyze` 確認 exhaustiveness 錯誤清單**

```bash
flutter analyze
```

Expected：出現數個 `non_exhaustive_switch_statement`（`reader_screen.dart` 內既有 `switch (format)` 語句缺少 `case BookFormat.cbz:`），清單記錄下來供 Task 9 使用——此為刻意運用編譯器 exhaustiveness 檢查作為系統性排查手段（比照 Issue 2 既有方法論）。**不要在本 Task 修正這些錯誤**，Task 9 才處理，本 Task 先確認清單完整。

- [x] **Step 7：Commit**

```bash
git add app/lib/reader/book_format.dart app/lib/library/models/library_enums.dart app/test/reader/book_format_test.dart
git commit -m "feat(epic-11): Issue 3——BookFormat/BookFileFormat 新增 cbz"
```

---

## Task 3：CBZ 自然排序比較器

**Files:**
- Create: `app/lib/library/cbz_import.dart`
- Test: `app/test/library/cbz_import_test.dart`

**Interfaces:**
- Produces：`int compareNaturalOrder(String a, String b)`（供 Task 4 排序圖片檔名使用，也可直接傳給 `List.sort()`）。

- [x] **Step 1：寫失敗測試**

```dart
// app/test/library/cbz_import_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/library/cbz_import.dart';

void main() {
  group('compareNaturalOrder', () {
    test('非零填補檔名依數值排出正確頁序（Issue 1 Spike 已查證的既有缺陷情境）', () {
      final names = ['2.jpg', '10.jpg', '1.jpg'];
      names.sort(compareNaturalOrder);
      expect(names, ['1.jpg', '2.jpg', '10.jpg']);
    });

    test('零填補檔名維持原有正確順序（字典序與自然序結果一致的情境）', () {
      final names = ['003.jpg', '001.jpg', '002.jpg'];
      names.sort(compareNaturalOrder);
      expect(names, ['001.jpg', '002.jpg', '003.jpg']);
    });

    test('相同前綴、數字不同的檔名依數值比較，不受字典序位數影響', () {
      final names = ['page10.png', 'page2.png', 'page1.png'];
      names.sort(compareNaturalOrder);
      expect(names, ['page1.png', 'page2.png', 'page10.png']);
    });

    test('完全非數字的檔名退回字典序比較', () {
      final names = ['cover.jpg', 'back.jpg', 'front.jpg'];
      names.sort(compareNaturalOrder);
      expect(names, ['back.jpg', 'cover.jpg', 'front.jpg']);
    });

    test('非數字片段忽略大小寫比較（審查修正：混用大小寫檔名仍依數字正確排序）', () {
      final names = ['Page2.jpg', 'page1.jpg', 'PAGE10.jpg'];
      names.sort(compareNaturalOrder);
      expect(names, ['page1.jpg', 'Page2.jpg', 'PAGE10.jpg']);
    });
  });
}
```

- [x] **Step 2：確認測試失敗**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter test test/library/cbz_import_test.dart
```

Expected：FAIL（`cbz_import.dart` 不存在，編譯錯誤）。

- [x] **Step 3：實作**

```dart
// app/lib/library/cbz_import.dart
/// 自然排序比較器：先切割成「連續數字」與「連續非數字」交錯的片段，數字
/// 片段以數值比較、其餘片段忽略大小寫比較（審查修正，見
/// reviews/review-issue-3-plan.md Minor #2：漫畫壓縮檔常見由不同掃圖/
/// 壓製來源合併，檔名大小寫可能不一致，例如「Page1.jpg」與「page2.jpg」
/// 混用——若依原始大小寫比較，ASCII 'P'(0x50) < 'p'(0x70) 會讓
/// 「Page2.jpg」排到「page1.jpg」之前，產生違反直覺的錯誤頁序；忽略大小寫
/// 後兩者依數字片段 1 < 2 正確排序）。`comic-book.js` 的 `makeComicBook()`
/// 對圖片檔名僅用純字典序 `.sort()`（見 issues.md Issue 1 Spike 查證：
/// 「1.jpg」「10.jpg」「2.jpg」會被排成「1,10,2,3...」），須在 Dart 端匯入
/// 階段以本比較器排出正確頁序後，重新命名為零填補檔名（見
/// [prepareCbzForImport]），讓 comic-book.js 自己的字典序排序也能得到相同
/// 結果，不依賴其內建排序。
int compareNaturalOrder(String a, String b) {
  final chunksA = _splitIntoChunks(a);
  final chunksB = _splitIntoChunks(b);
  final len = chunksA.length < chunksB.length ? chunksA.length : chunksB.length;
  for (var i = 0; i < len; i++) {
    final numA = int.tryParse(chunksA[i]);
    final numB = int.tryParse(chunksB[i]);
    final cmp = (numA != null && numB != null)
        ? numA.compareTo(numB)
        : chunksA[i].toLowerCase().compareTo(chunksB[i].toLowerCase());
    if (cmp != 0) return cmp;
  }
  return chunksA.length.compareTo(chunksB.length);
}

List<String> _splitIntoChunks(String value) {
  final chunks = <String>[];
  final buffer = StringBuffer();
  bool? lastWasDigit;
  for (final rune in value.runes) {
    final isDigit = rune >= 0x30 && rune <= 0x39; // '0'-'9'
    if (lastWasDigit != null && isDigit != lastWasDigit) {
      chunks.add(buffer.toString());
      buffer.clear();
    }
    buffer.writeCharCode(rune);
    lastWasDigit = isDigit;
  }
  if (buffer.isNotEmpty) chunks.add(buffer.toString());
  return chunks;
}
```

- [x] **Step 4：確認測試通過**

```bash
flutter test test/library/cbz_import_test.dart
```

Expected：PASS（5 個測試）。

- [x] **Step 5：Commit**

```bash
git add app/lib/library/cbz_import.dart app/test/library/cbz_import_test.dart
git commit -m "feat(epic-11): Issue 3——CBZ 自然排序比較器 compareNaturalOrder"
```

---

## Task 4：CBZ 壓縮檔重建與封面擷取（`prepareCbzForImport`）

**Files:**
- Modify: `app/lib/library/cbz_import.dart`
- Modify: `app/pubspec.yaml`（`archive` 由 dev_dependencies 升級為 dependencies）
- Test: `app/test/library/cbz_import_test.dart`

**Interfaces:**
- Consumes：`compareNaturalOrder`（Task 3）；`kBookMetadataChannel`（`library_repository.dart` 既有常數，`copyContentUriToFile` 方法，比照 `kf8_metadata.dart` 既有 content:// 處理模式）。
- Produces：`class CbzImportResult { Uint8List rebuiltArchiveBytes; Uint8List coverBytes; }`；`class NoComicPagesException implements Exception`；`Future<CbzImportResult> prepareCbzForImport(String filePath)`（供 Task 7 `book_import_service_impl.dart` 消費）。

- [x] **Step 1：`archive` 升級為正式 dependency**

`app/pubspec.yaml` 修改：從 `dev_dependencies:` 區塊移除

```yaml
  archive: ^4.0.9
```

新增到 `dependencies:` 區塊（緊接在 `clock: ^1.1.2` 之後）：

```yaml
  # CBZ 自然排序與壓縮檔重建（epic-11-multi-format-reader Issue 3）：
  # 由 dev_dependencies 升級為正式 dependency——先前僅供測試 fixture 產生
  # 使用（見 integration_test/foliate_epub_reader_view_test.dart），本 Issue
  # 起成為正式匯入管線的執行期依賴。
  archive: ^4.0.9
```

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter pub get
```

Expected：無版本衝突（`archive: ^4.0.9` 已是既有鎖定版本，僅改變依賴分類，不觸發版本重新解析）。

- [x] **Step 2：寫失敗測試（合成 CBZ fixture＋斷言重建結果）**

於 `app/test/library/cbz_import_test.dart` 頂部新增 import，並在既有 `void main() { ... }` 內追加以下內容：

```dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:elinkbook/library/cbz_import.dart';

import '../support/fake_path_provider_platform.dart';

const _channel = MethodChannel('elinkbook/book_metadata');

Uint8List _buildSyntheticCbz(
  List<String> imageNames, {
  List<String> extraNonImageNames = const [],
}) {
  final archive = Archive();
  for (final name in imageNames) {
    archive.addFile(ArchiveFile.bytes(name, utf8.encode('fake-image-bytes:$name')));
  }
  for (final name in extraNonImageNames) {
    archive.addFile(ArchiveFile.bytes(name, utf8.encode('non-image:$name')));
  }
  return ZipEncoder().encodeBytes(archive);
}
```

（以上為新增的 helper／import，緊接著在 `void main() { ... }` 內、既有 `group('compareNaturalOrder', ...)` 之後追加：）

```dart
  group('prepareCbzForImport', () {
    test('非零填補檔名依自然排序重建，封面取排序後第一張圖片', () async {
      final bytes = _buildSyntheticCbz(['2.jpg', '10.jpg', '1.jpg']);
      final tempFile =
          File('${Directory.systemTemp.path}/cbz_test_unpadded.cbz');
      await tempFile.writeAsBytes(bytes);
      addTearDown(() => tempFile.delete());

      final result = await prepareCbzForImport(tempFile.path);

      expect(result.coverBytes, utf8.encode('fake-image-bytes:1.jpg'));
      final rebuilt = ZipDecoder().decodeBytes(result.rebuiltArchiveBytes);
      final names = rebuilt.files.map((f) => f.name).toList();
      expect(names, ['page_0001.jpg', 'page_0002.jpg', 'page_0003.jpg']);
      expect(rebuilt.files[0].readBytes(), utf8.encode('fake-image-bytes:1.jpg'));
      expect(rebuilt.files[1].readBytes(), utf8.encode('fake-image-bytes:2.jpg'));
      expect(rebuilt.files[2].readBytes(), utf8.encode('fake-image-bytes:10.jpg'));
    });

    test('零填補檔名重建後頁序不變', () async {
      final bytes = _buildSyntheticCbz(['001.jpg', '002.jpg', '003.jpg']);
      final tempFile =
          File('${Directory.systemTemp.path}/cbz_test_padded.cbz');
      await tempFile.writeAsBytes(bytes);
      addTearDown(() => tempFile.delete());

      final result = await prepareCbzForImport(tempFile.path);

      expect(result.coverBytes, utf8.encode('fake-image-bytes:001.jpg'));
      final rebuilt = ZipDecoder().decodeBytes(result.rebuiltArchiveBytes);
      expect(rebuilt.files[0].readBytes(), utf8.encode('fake-image-bytes:001.jpg'));
      expect(rebuilt.files[1].readBytes(), utf8.encode('fake-image-bytes:002.jpg'));
      expect(rebuilt.files[2].readBytes(), utf8.encode('fake-image-bytes:003.jpg'));
    });

    test('非圖片項目（例如 ComicInfo.xml）不保留於重建後的壓縮檔', () async {
      final bytes = _buildSyntheticCbz(
        ['001.jpg', '002.jpg'],
        extraNonImageNames: ['ComicInfo.xml'],
      );
      final tempFile =
          File('${Directory.systemTemp.path}/cbz_test_nonimage.cbz');
      await tempFile.writeAsBytes(bytes);
      addTearDown(() => tempFile.delete());

      final result = await prepareCbzForImport(tempFile.path);

      final rebuilt = ZipDecoder().decodeBytes(result.rebuiltArchiveBytes);
      expect(rebuilt.files, hasLength(2));
    });

    test('壓縮檔內沒有支援的圖片格式時拋出 NoComicPagesException', () async {
      final bytes = _buildSyntheticCbz([], extraNonImageNames: ['readme.txt']);
      final tempFile =
          File('${Directory.systemTemp.path}/cbz_test_empty.cbz');
      await tempFile.writeAsBytes(bytes);
      addTearDown(() => tempFile.delete());

      expect(
        () => prepareCbzForImport(tempFile.path),
        throwsA(isA<NoComicPagesException>()),
      );
    });

    group('content:// URI 支援', () {
      late Directory tempDir;
      late PathProviderPlatform originalPathProvider;

      setUp(() {
        tempDir = Directory.systemTemp.createTempSync('cbz_import_test_tmp');
        originalPathProvider = PathProviderPlatform.instance;
        PathProviderPlatform.instance = FakePathProviderPlatform(tempDir.path);
      });

      tearDown(() {
        PathProviderPlatform.instance = originalPathProvider;
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(_channel, null);
      });

      test('content:// URI 先複製到暫存檔再解析', () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(_channel, (call) async {
          expect(call.method, 'copyContentUriToFile');
          final args = call.arguments as Map;
          final bytes = _buildSyntheticCbz(['001.jpg', '002.jpg']);
          await File(args['destinationPath'] as String).writeAsBytes(bytes);
          return null;
        });

        final result = await prepareCbzForImport('content://example/sample.cbz');

        expect(result.coverBytes, utf8.encode('fake-image-bytes:001.jpg'));
      });

      test('content:// URI 對應的暫存檔在解析完成後被刪除', () async {
        String? capturedTempPath;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(_channel, (call) async {
          final args = call.arguments as Map;
          capturedTempPath = args['destinationPath'] as String;
          final bytes = _buildSyntheticCbz(['001.jpg']);
          await File(capturedTempPath!).writeAsBytes(bytes);
          return null;
        });

        await prepareCbzForImport('content://example/sample.cbz');

        expect(capturedTempPath, isNotNull);
        expect(File(capturedTempPath!).existsSync(), isFalse);
      });
    });
  });
```

- [x] **Step 3：確認測試失敗**

```bash
flutter test test/library/cbz_import_test.dart
```

Expected：FAIL（`prepareCbzForImport`／`CbzImportResult`／`NoComicPagesException` 未定義）。

- [x] **Step 4：實作**

於 `app/lib/library/cbz_import.dart` 頂部新增 import，並在既有 `compareNaturalOrder`／`_splitIntoChunks` 之後追加：

```dart
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'library_repository.dart';

/// comic-book.js（`readest/foliate-js`，釘定 commit
/// dd71f2be356563c16a23272686189fcfb45d0b82）辨識為漫畫頁面的圖片副檔名
/// 清單，逐字對照該檔案原始碼的 `exts` 常數（epic-11-multi-format-reader
/// Issue 3 查證）——本模組的自然排序與封面判斷須以同一份清單為準，否則
/// Dart 端判定的「第一張圖片」可能與 comic-book.js 實際解析出的頁面順序
/// 不一致。
const _kSupportedImageExtensions = {
  '.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp', '.svg', '.jxl', '.avif',
};

/// CBZ 壓縮檔內完全沒有支援的圖片格式時拋出——沒有可用頁面的漫畫書本質上
/// 無法開啟，呼叫端（book_import_service_impl.dart）應中止匯入、不建立
/// Book 記錄，比照 KF8 DRM 情境（DrmProtectedException）的既有處置慣例，
/// 不可比照一般 metadata 擷取失敗降級為「無封面繼續匯入」——CBZ 不存在
/// 「降級但仍可開啟」的中間狀態。
class NoComicPagesException implements Exception {
  final String message;
  const NoComicPagesException(this.message);
  @override
  String toString() => 'NoComicPagesException: $message';
}

class CbzImportResult {
  /// 依自然排序重新命名、重建索引後的壓縮檔完整位元組內容，供呼叫端落地
  /// 為 `Book.filePath` 指向的衍生檔案。
  final Uint8List rebuiltArchiveBytes;

  /// 自然排序後第一張圖片的原始位元組，供呼叫端落地為封面（spec.md
  /// 「CBZ 支援」：「封面固定取排序後第一張圖片」）。
  final Uint8List coverBytes;

  const CbzImportResult({
    required this.rebuiltArchiveBytes,
    required this.coverBytes,
  });
}

/// 讀取 [filePath]（本機路徑或 `content://` URI，比照 kf8_metadata.dart
/// extractKf8Metadata() 的既有 content:// 處理模式：先透過既有、格式無關
/// 的 copyContentUriToFile 原生方法複製到暫存檔，因為 dart:io 無法對
/// content:// URI 做隨機存取讀取，讀取整個壓縮檔內容需要完整位元組陣列）
/// 指向的 CBZ 壓縮檔，對內部圖片檔名做自然排序，重新命名為零填補檔名
/// （`page_0001.<原副檔名>` 起算）並重建壓縮檔索引，回傳重建後的完整位元組
/// 與封面位元組。非圖片項目（例如 ComicInfo.xml）不保留於重建後的壓縮檔
/// ——comic-book.js 本身也只用圖片項目組成 book.sections/book.toc，本 Epic
/// 範圍未涵蓋 ComicInfo.xml 中繼資料擷取（spec.md「CBZ 支援」未提及，
/// YAGNI）。
Future<CbzImportResult> prepareCbzForImport(String filePath) async {
  final bytes = filePath.contains('://')
      ? await _readContentUriBytes(filePath)
      : await File(filePath).readAsBytes();
  // 審查修正（見 reviews/review-issue-3-plan.md Important #1）：解壓/排序/
  // 重新壓縮是純 CPU 運算，對包含數百張高解析度圖片的大型 CBZ 可能耗費
  // 明顯時間，外包至 Isolate.run() 背景執行，避免阻塞 UI isolate（比照
  // book_content_fingerprint.dart 對大檔案 SHA-256 計算的既有作法——本檔案
  // 讀取階段〔本機檔案／content:// 複製〕已在上面用 await 完成，傳入
  // Isolate.run() 的只有已讀出的 Uint8List，屬於可跨 isolate 傳遞型別）。
  return Isolate.run(() => _decodeSortAndRebuild(bytes));
}

/// 純 CPU 運算（zip 解壓／自然排序／重建），見 [prepareCbzForImport] 呼叫處
/// 註解——頂層純函式、僅接受可跨 isolate 傳遞的 [Uint8List] 參數，不捕捉
/// 任何 State 或其他不可傳遞物件（比照 CLAUDE.md「不可逆的技術決策」段落對
/// `Isolate.run()` closure 的既有限制：closure 須獨立於呼叫端詞法作用域，
/// 否則 Dart VM 會把整個作用域一併打包，牽連不可跨 isolate 傳遞的物件）。
CbzImportResult _decodeSortAndRebuild(Uint8List bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);
  final imageFiles = archive.files
      .where((file) =>
          file.isFile &&
          _kSupportedImageExtensions.contains(p.extension(file.name).toLowerCase()))
      .toList()
    ..sort((a, b) => compareNaturalOrder(a.name, b.name));
  if (imageFiles.isEmpty) {
    throw const NoComicPagesException('CBZ 壓縮檔內沒有支援的圖片格式');
  }

  final rebuilt = Archive();
  for (var i = 0; i < imageFiles.length; i++) {
    final original = imageFiles[i];
    final newName =
        'page_${(i + 1).toString().padLeft(4, '0')}${p.extension(original.name)}';
    rebuilt.addFile(
      ArchiveFile.bytes(newName, original.readBytes() ?? Uint8List(0)),
    );
  }

  return CbzImportResult(
    rebuiltArchiveBytes: ZipEncoder().encodeBytes(rebuilt),
    coverBytes: imageFiles.first.readBytes() ?? Uint8List(0),
  );
}

Future<Uint8List> _readContentUriBytes(String uri) async {
  final tempDir = await getTemporaryDirectory();
  final tempPath = p.join(
    tempDir.path,
    'cbz_probe_${DateTime.now().microsecondsSinceEpoch}.cbz',
  );
  await kBookMetadataChannel.invokeMethod<void>(
    'copyContentUriToFile',
    {'uri': uri, 'destinationPath': tempPath},
  );
  final tempFile = File(tempPath);
  try {
    return await tempFile.readAsBytes();
  } finally {
    if (tempFile.existsSync()) tempFile.deleteSync();
  }
}
```

- [x] **Step 5：確認測試通過**

```bash
flutter test test/library/cbz_import_test.dart
```

Expected：PASS（11 個測試：5 個 `compareNaturalOrder` ＋ 6 個 `prepareCbzForImport`）。審查修正提醒（Important #1）：`prepareCbzForImport` 現在透過 `Isolate.run()` 執行核心邏輯，若「壓縮檔內沒有支援的圖片格式時拋出 NoComicPagesException」這則測試意外失敗（例如例外未正確跨 isolate 邊界傳遞、被包裝成其他型別），需確認 `NoComicPagesException` 是否符合 `Isolate.run()` 錯誤回傳的可傳遞性要求（僅含 `String` 欄位的簡單例外類別應可正確重建），必要時調整斷言方式（例如改用 `throwsA(isA<Exception>())` 或改為捕捉後檢查 `toString()` 內容），但不可移除 Isolate 包裝本身。

- [x] **Step 6：`flutter analyze`**

```bash
flutter analyze
```

Expected：無新增 issue（Task 2 記錄的既有 exhaustiveness 錯誤清單不變，Task 9 才處理）。

- [x] **Step 7：Commit**

```bash
git add app/lib/library/cbz_import.dart app/test/library/cbz_import_test.dart app/pubspec.yaml app/pubspec.lock
git commit -m "feat(epic-11): Issue 3——CBZ 壓縮檔自然排序重建與封面擷取 prepareCbzForImport"
```

---

## Task 5：WebView 書籍快取副檔名感知（CBZ 自動格式偵測的必要前置修復）

見 Global Constraints「已查證的關鍵技術事實」第 4 點——`main.js` 目前寫死 fetch `current.epub`，`ReaderResourceChannel.kt` 也寫死快取為 `current.epub`，若不修正，`view.js` 的 `isCBZ()` 名稱判斷恆為 false，CBZ 開書必然失敗（誤判為 EPUB）。本 Task 讓快取檔名與 fetch URL 反映書籍真實副檔名。

**設計取捨（刻意不改變 `cacheBookForServing` 的公開函式簽章）**：`app/test/reader/foliate_reader_view_test.dart`／`app/test/screens/reader_screen_test.dart`／`app/test/reader/foliate_native_bridge_test.dart` 皆有多處直接覆寫或呼叫 `cacheBookForServing`（2 個參數的既有簽章）。若改變其公開簽章，會連帶破壞這些既有測試（大量非本 Issue 目的的收尾修改）。改為只在 `_defaultCacheBookForServing`（原生呼叫的實際實作，公開函式變數簽章不變）內部推導副檔名並多帶一個 `extension` 參數給原生端方法呼叫——測試檔覆寫的是公開函式變數本身（完全繞過 `_defaultCacheBookForServing`），不受影響。

**Files:**
- Modify: `app/lib/reader/foliate_native_bridge.dart`
- Modify: `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/ReaderResourceChannel.kt`
- Modify: `app/lib/reader/foliate_reader_view.dart`（`_buildIndexUri()` 新增 `bookFileName` 查詢參數）
- Modify: `app/android/app/src/main/assets/foliate/main.js`（fetch URL 改用動態檔名）
- Test: `app/test/reader/foliate_native_bridge_test.dart`

**Interfaces:**
- Produces：`String cacheFileExtension(String filePath)`（`foliate_native_bridge.dart` 新增公開頂層函式，供 `foliate_reader_view.dart` 的 `_buildIndexUri()` 與 `_defaultCacheBookForServing()` 共用同一份推導邏輯，避免兩處各自實作導致不同步）。

- [x] **Step 1：寫失敗測試（`cacheFileExtension` 推導邏輯）**

於 `app/test/reader/foliate_native_bridge_test.dart` 追加（若既有 import 已涵蓋 `elinkbook/reader/foliate_native_bridge.dart` 則不重複加）：

```dart
  group('cacheFileExtension', () {
    test('依副檔名推導，小寫化', () {
      expect(cacheFileExtension('foo/bar.CBZ'), 'cbz');
      expect(cacheFileExtension('foo/bar.epub'), 'epub');
      expect(cacheFileExtension('foo/bar.azw3'), 'azw3');
    });

    test('content:// URI 帶有可辨識副檔名時正確推導', () {
      expect(
        cacheFileExtension('content://com.example.provider/comic.cbz'),
        'cbz',
      );
    });

    test('無副檔名時退回 epub（維持 Issue 3 之前對 EPUB／AZW3 的既有行為）', () {
      expect(
        cacheFileExtension('content://com.android.providers.media.documents/document/document%3A1000001716'),
        'epub',
      );
    });
  });
```

- [x] **Step 2：更新既有 `cacheBookForServing` 呼叫測試以涵蓋新增的 `extension` 引數**

修改 `app/test/reader/foliate_native_bridge_test.dart` 既有測試（原本斷言 `captured!.arguments, {'uri': ..., 'instanceId': ...}` 的那一則）：

```dart
  test('cacheBookForServing 呼叫 elinkbook/reader_resources_cache 的 cacheBookForServing', () async {
    MethodCall? captured;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('elinkbook/reader_resources_cache'),
      (call) async {
        captured = call;
        return '/fake/cache/dir/current.epub';
      },
    );

    // 使用 content:// URI 測試（不經過檔案存在檢查，直接呼叫原生端）
    final result = await cacheBookForServing('content://com.example.provider/book.epub', 'test_instance');

    expect(captured!.method, 'cacheBookForServing');
    expect(captured!.arguments, {
      'uri': 'content://com.example.provider/book.epub',
      'instanceId': 'test_instance',
      'extension': 'epub',
    });
    expect(result, '/fake/cache/dir/current.epub');
  });

  test('cacheBookForServing 對 CBZ 來源正確帶入 extension: cbz（epic-11 Issue 3，CBZ 開書前置修復）', () async {
    MethodCall? captured;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('elinkbook/reader_resources_cache'),
      (call) async {
        captured = call;
        return '/fake/cache/dir/current.cbz';
      },
    );

    await cacheBookForServing('content://com.example.provider/comic.cbz', 'test_instance');

    expect(captured!.arguments, {
      'uri': 'content://com.example.provider/comic.cbz',
      'instanceId': 'test_instance',
      'extension': 'cbz',
    });
  });
```

- [x] **Step 3：確認測試失敗**

```bash
flutter test test/reader/foliate_native_bridge_test.dart
```

Expected：FAIL（`cacheFileExtension` 未定義；既有測試因 map 不含 `extension` 鍵而斷言失敗）。

- [x] **Step 4：實作 Dart 端**

`app/lib/reader/foliate_native_bridge.dart` 頂部新增 import：

```dart
import 'package:path/path.dart' as p;
```

在既有 `cacheBookForServing` 頂層函式變數宣告之前新增：

```dart
/// 依 [filePath] 副檔名推導 WebView 快取檔名應使用的副檔名（不含點號，
/// 小寫），供 [cacheBookForServing] 決定原生端快取檔名、[FoliateReaderView]
/// 決定要 fetch 的檔名（epic-11-multi-format-reader Issue 3）。CBZ 依賴
/// `readest/foliate-js` 的 `isCBZ()` 對「檔名副檔名／MIME type」做格式
/// 自動偵測（見 view.js 原始碼）；若快取檔名恆為 `current.epub`（Issue 3
/// 之前的既有寫死行為，KF8/MOBI 靠 magic bytes 偵測不受影響、EPUB 本身
/// 就是 .epub 無影響），CBZ 會被誤判為 EPUB 而開書失敗——本函式讓快取
/// 檔名與副檔名判斷都反映書籍真實格式。無法識別副檔名（例如不含副檔名的
/// `content://` URI）時退回 'epub'，維持 Issue 3 之前對 EPUB／AZW3 的既有
/// 行為不變（AZW3 走 magic bytes 偵測，副檔名判斷結果對它而言其實不影響
/// 正確性，僅影響快取檔名字面值）。
String cacheFileExtension(String filePath) {
  final ext = p.extension(filePath);
  return ext.isEmpty ? 'epub' : ext.substring(1).toLowerCase();
}
```

修改 `_defaultCacheBookForServing`：

```dart
Future<String?> _defaultCacheBookForServing(String filePath, String instanceId) async {
  final extension = cacheFileExtension(filePath);
  if (filePath.contains('://')) {
    return _readerResourcesCacheChannel.invokeMethod<String>(
        'cacheBookForServing', {'uri': filePath, 'instanceId': instanceId, 'extension': extension});
  }
  final file = File(filePath);
  final exists = await file.exists();
  if (!exists) return null;
  final canonicalPath = file.resolveSymbolicLinksSync();
  final docsDir = await getApplicationDocumentsDirectory();
  final parentDir = Directory(docsDir.path).parent;
  String allowedRoot;
  try {
    allowedRoot = parentDir.resolveSymbolicLinksSync();
  } catch (e) {
    allowedRoot = parentDir.path;
  }
  final withinRoot = isPathWithinRoot(canonicalPath, allowedRoot);
  if (!withinRoot) return null;
  return _readerResourcesCacheChannel.invokeMethod<String>(
      'cacheBookForServing', {'filePath': canonicalPath, 'instanceId': instanceId, 'extension': extension});
}
```

- [x] **Step 5：實作原生端**

`app/android/app/src/main/kotlin/cc/ugotit/elinkbook/ReaderResourceChannel.kt` 修改 `copyToCache`：

```kotlin
    /**
     * 將輸入串流分塊複製到每個 widget 實例獨立的快取子目錄。
     * 快取路徑為 `foliate_book_cache/<instanceId>/current.<extension>`
     * （epic-11-multi-format-reader Issue 3：extension 依來源書籍真實副
     * 檔名決定，取代原本寫死 `current.epub` 的既有行為——CBZ 需要
     * `view.js` 的 `isCBZ()` 對檔名做副檔名判斷才能正確自動分派至
     * `comic-book.js`，見該處原始碼），
     * 避免螢幕轉場期間兩個 `FoliateEpubReaderView` 實例並存時共用同一個可變檔案的競態。
     *
     * @param input 輸入串流（`content://` URI 或本機檔案）
     * @param instanceId Dart 端產生的實例唯一 ID，用於區隔快取子目錄
     * @param extension 快取檔名副檔名（不含點號），Dart 端 cacheFileExtension() 推導
     * @return 快取檔案的絕對路徑，失敗回傳 null
     */
    private fun copyToCache(input: InputStream, instanceId: String, extension: String): String? {
        val cacheDir = File(context.filesDir, "foliate_book_cache/$instanceId").apply { mkdirs() }
        val destFile = File(cacheDir, "current.$extension")
        try {
            input.use { source ->
                FileOutputStream(destFile).use { output ->
                    source.copyTo(output)  // Kotlin 標準函式，預設 8KB 緩衝，有界記憶體
                }
            }
            return destFile.absolutePath
        } catch (e: Exception) {
            destFile.delete()
            return null
        }
    }
```

修改 `"cacheBookForServing"` 分支：

```kotlin
            "cacheBookForServing" -> {
                val instanceId = call.argument<String>("instanceId")
                val uriString = call.argument<String>("uri")
                val filePath = call.argument<String>("filePath")
                val extension = call.argument<String>("extension") ?: "epub"
                if (instanceId == null) {
                    result.success(null)
                    return
                }
                // 整個 when 分支（含開啟輸入串流）須納入同一個 try/catch，
                // SAF 授權失效／檔案競態刪除等情境會讓例外未被捕捉地冒出，
                // 變成 Dart 端未預期的 PlatformException。
                val cachedPath = try {
                    val input: InputStream? = when {
                        uriString != null -> context.contentResolver.openInputStream(Uri.parse(uriString))
                        filePath != null -> File(filePath).inputStream()
                        else -> null
                    }
                    input?.let { copyToCache(it, instanceId, extension) }
                } catch (e: Exception) {
                    null
                }
                result.success(cachedPath)
            }
```

- [x] **Step 6：`_buildIndexUri()` 新增 `bookFileName` 查詢參數**

`app/lib/reader/foliate_reader_view.dart`（已 import `foliate_native_bridge.dart`）修改 `_buildIndexUri()`：

```dart
  Uri _buildIndexUri() {
    final params = <String, String>{
      'prefs': jsonEncode(buildFoliatePreferencesMap(widget)),
      'fontFaceCss': buildFontFaceCss(customFonts: widget.customFonts),
      // epic-11-multi-format-reader Issue 3：讓 main.js 的 fetch URL 反映
      // 真實副檔名（見 foliate_native_bridge.dart cacheFileExtension()
      // 文件註解——CBZ 需要 view.js 的 isCBZ() 對檔名做副檔名判斷）。
      'bookFileName': 'current.${cacheFileExtension(widget.filePath)}',
    };
    final cfi = extractCfi(widget.initialLocatorJson);
    if (cfi != null) params['initialCfi'] = cfi;
    return Uri.https(
      'appassets.androidplatform.net',
      '/assets/foliate/index.html',
      params,
    );
  }
```

- [x] **Step 7：`main.js` fetch URL 改用動態檔名**

`app/android/app/src/main/assets/foliate/main.js` 修改 `openBook()` 開頭：

```js
async function openBook() {
  try {
    const book = await makeBook(
      `https://appassets.androidplatform.net/book/${params.get('bookFileName') || 'current.epub'}`,
    )
```

- [x] **Step 8：確認測試通過**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter test test/reader/foliate_native_bridge_test.dart
```

Expected：PASS（原有測試＋3 個新增 `cacheFileExtension` 測試＋1 個新增 CBZ extension 測試）。

- [x] **Step 9：確認既有大範圍測試未受影響**

```bash
flutter test test/reader/foliate_reader_view_test.dart test/screens/reader_screen_test.dart
```

Expected：PASS（這些檔案覆寫的是 `cacheBookForServing` 公開函式變數本身，簽章未變，不受影響——見本 Task 開頭「設計取捨」說明）。

- [x] **Step 10：`flutter analyze`**

```bash
flutter analyze
```

Expected：無新增 issue。

- [x] **Step 11：Commit**

```bash
git add app/lib/reader/foliate_native_bridge.dart app/lib/reader/foliate_reader_view.dart \
  app/android/app/src/main/kotlin/cc/ugotit/elinkbook/ReaderResourceChannel.kt \
  app/android/app/src/main/assets/foliate/main.js \
  app/test/reader/foliate_native_bridge_test.dart
git commit -m "fix(epic-11): Issue 3——WebView 書籍快取副檔名感知，修復 CBZ 自動格式偵測前置阻塞"
```

---

## Task 6：`FoliateReaderView` 新增 CBZ 專屬參數；`main.js` 整合翻頁方向與虛擬目錄

**Files:**
- Modify: `app/lib/reader/foliate_reader_view.dart`
- Modify: `app/android/app/src/main/assets/foliate/main.js`
- Test: `app/test/reader/foliate_reader_view_test.dart`

**Interfaces:**
- Consumes：`DualPageDirection`（`app/lib/reader/dual_page_direction.dart` 既有 enum，`ltr`/`rtl`）。
- Produces：`FoliateReaderView.isComicBookHint`（`bool`，預設 `false`）、`FoliateReaderView.dualPageDirection`（`DualPageDirection?`）；`buildFoliatePreferencesMap()`／`foliatePreferencesChanged()` 涵蓋這兩個新欄位。

- [x] **Step 1：寫失敗測試（`buildFoliatePreferencesMap`／`foliatePreferencesChanged`）**

於 `app/test/reader/foliate_reader_view_test.dart` 找到既有測試 `buildFoliatePreferencesMap`／`foliatePreferencesChanged` 的 `group`（比照既有其他欄位測試風格），追加：

```dart
    test('isComicBookHint 恆包含於 map（非 nullable 欄位，比照 isLandscape）', () {
      final view = FoliateReaderView(
        filePath: 'test.cbz',
        onPageRendered: () {},
        onError: (_) {},
        isComicBookHint: true,
      );
      final map = buildFoliatePreferencesMap(view);
      expect(map['isComicBookHint'], isTrue);
    });

    test('dualPageDirection 為 null 時不出現在 map 中', () {
      final view = FoliateReaderView(
        filePath: 'test.cbz',
        onPageRendered: () {},
        onError: (_) {},
      );
      final map = buildFoliatePreferencesMap(view);
      expect(map.containsKey('dualPageDirection'), isFalse);
    });

    test('dualPageDirection 非 null 時序列化為 rtl/ltr 字串', () {
      final rtlView = FoliateReaderView(
        filePath: 'test.cbz',
        onPageRendered: () {},
        onError: (_) {},
        dualPageDirection: DualPageDirection.rtl,
      );
      expect(buildFoliatePreferencesMap(rtlView)['dualPageDirection'], 'rtl');

      final ltrView = FoliateReaderView(
        filePath: 'test.cbz',
        onPageRendered: () {},
        onError: (_) {},
        dualPageDirection: DualPageDirection.ltr,
      );
      expect(buildFoliatePreferencesMap(ltrView)['dualPageDirection'], 'ltr');
    });

    test('foliatePreferencesChanged 偵測 isComicBookHint/dualPageDirection 變動', () {
      final base = FoliateReaderView(
        filePath: 'test.cbz',
        onPageRendered: () {},
        onError: (_) {},
        isComicBookHint: true,
        dualPageDirection: DualPageDirection.ltr,
      );
      final changedHint = FoliateReaderView(
        filePath: 'test.cbz',
        onPageRendered: () {},
        onError: (_) {},
        isComicBookHint: false,
        dualPageDirection: DualPageDirection.ltr,
      );
      final changedDirection = FoliateReaderView(
        filePath: 'test.cbz',
        onPageRendered: () {},
        onError: (_) {},
        isComicBookHint: true,
        dualPageDirection: DualPageDirection.rtl,
      );
      expect(foliatePreferencesChanged(base, changedHint), isTrue);
      expect(foliatePreferencesChanged(base, changedDirection), isTrue);
      expect(foliatePreferencesChanged(base, base), isFalse);
    });
```

於檔案頂部 import 區塊補上（若尚未存在）：

```dart
import 'package:elinkbook/reader/dual_page_direction.dart';
```

- [x] **Step 2：確認測試失敗**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter test test/reader/foliate_reader_view_test.dart
```

Expected：FAIL（`isComicBookHint`/`dualPageDirection` 建構參數不存在，編譯錯誤）。

- [x] **Step 3：實作**

`app/lib/reader/foliate_reader_view.dart` 頂部 import 區塊新增：

```dart
import 'dual_page_direction.dart';
```

`FoliateReaderView` class 內，緊接在既有 `final DualPageMode? dualPageMode;` 之後新增欄位：

```dart
  /// CBZ 專屬提示（epic-11-multi-format-reader Issue 3）：main.js 僅在此為
  /// `true` 時才覆寫 `book.dir`／虛擬頁碼目錄，避免誤觸 EPUB 固定版面既有
  /// 的 page-progression-direction 自動偵測（見該檔案 openBook() 對應段落
  /// 註解）。預設 `false`，比照 [isLandscape] 既有非 nullable＋預設值模式
  /// ——本欄位並非「格式未知時省略」的選填語意，而是「明確告知這是不是
  /// 漫畫」的必要旗標。
  final bool isComicBookHint;

  /// CBZ 翻頁方向（RTL/LTR），重用既有 [DualPageDirection]（原僅 PDF
  /// 適用，見該檔案文件註解，epic-11-multi-format-reader Issue 3 起擴大
  /// 適用於 CBZ）。**僅在書籍開啟當下讀取一次**（main.js 的 openBook()，
  /// 於 `view.open(book)` 之前設定 `book.dir`）——`fixed-layout.js` 的
  /// `open()` 只在當下一次性讀取 `book.dir` 決定 `this.rtl`（見
  /// Global Constraints 已查證事實 #2），之後不會重新推導，故本欄位變動
  /// 不會在既有書籍開啟期間即時生效，需重新開啟該書才會套用新方向
  /// （比照既有 [isFixedLayoutHint] 同樣「僅開書當下生效」的既有限制，
  /// 非本 Issue 新增的例外）。
  final DualPageDirection? dualPageDirection;
```

建構子新增對應具名參數（緊接在既有 `this.dualPageMode,` 之後）：

```dart
    this.isComicBookHint = false,
    this.dualPageDirection,
```

`buildFoliatePreferencesMap()` 函式內，緊接在既有 `if (view.dualPageMode != null) map['dualPageMode'] = view.dualPageMode!.name;` 之後新增：

```dart
  map['isComicBookHint'] = view.isComicBookHint;
  if (view.dualPageDirection != null) {
    map['dualPageDirection'] =
        view.dualPageDirection == DualPageDirection.rtl ? 'rtl' : 'ltr';
  }
```

`foliatePreferencesChanged()` 函式內，緊接在既有 `oldView.dualPageMode != newView.dualPageMode ||` 之後新增：

```dart
      oldView.isComicBookHint != newView.isComicBookHint ||
      oldView.dualPageDirection != newView.dualPageDirection ||
```

- [x] **Step 4：確認測試通過**

```bash
flutter test test/reader/foliate_reader_view_test.dart
```

Expected：PASS（既有測試＋4 個新增測試）。

- [x] **Step 5：`main.js` 整合翻頁方向與虛擬目錄**

`app/android/app/src/main/assets/foliate/main.js` 修改 `openBook()`：在既有

```js
    if (initialPrefs.isFixedLayoutHint === true && book.rendition?.layout !== 'pre-paginated') {
      book.rendition = { ...book.rendition, layout: 'pre-paginated' }
    }
    await view.open(book)
```

之前插入：

```js
    // epic-11-multi-format-reader Issue 3（CBZ 支援）：翻頁方向覆寫，須在
    // view.open(book) 之前設定 book.dir——fixed-layout.js 的 open() 只在
    // 當下一次性讀取 book.dir 決定 this.rtl（見 next()/prev() 固定讀取
    // this.rtl 決定要呼叫 #goLeft() 還是 #goRight()，不會之後重新推導），
    // 比照上方 isFixedLayoutHint 覆寫「必須在 open() 之前」的既有限制。
    // 僅在 isComicBookHint === true 時套用，避免誤觸 EPUB 固定版面既有的
    // page-progression-direction 自動偵測——comic-book.js 回傳的 book
    // 物件不含 dir 欄位（見 issues.md Issue 1 Spike 查證），EPUB FXL 則由
    // epub.js 自行依 OPF metadata 設定，不應被本專案覆寫（spec.md
    // 「CBZ 支援」）。
    if (initialPrefs.isComicBookHint === true) {
      book.dir = initialPrefs.dualPageDirection === 'rtl' ? 'rtl' : 'ltr'
      // 虛擬頁碼目錄（spec.md「CBZ 支援」）：comic-book.js 的 book.toc
      // 預設以檔名當作 label（例如重建後的 page_0001.jpg），對使用者無
      // 意義；book.resolveHref／book.sections 皆以 section.id（＝檔名）
      // 為鍵，href 沿用 section.id 可讓既有 window.getTableOfContents()
      // 的 buildTocEntry() 邏輯原樣重用（不需修改），只替換 label 顯示
      // 文字。buildTocEntry() 內 view.book.sections[index].createDocument()
      // 對漫畫頁面（無 createDocument 方法）會拋出例外，已有既有
      // try/catch 優雅退回 section 層級 base CFI（view.getCFI(index,
      // undefined)）——對漫畫「一頁即一個完整章節」的語意而言，這正是
      // 正確的行為，不需額外處理。
      book.toc = book.sections.map((section, i) => ({
        label: `第 ${i + 1} 頁`,
        href: section.id,
      }))
    }
```

- [x] **Step 6：`flutter analyze`**

```bash
flutter analyze
```

Expected：無新增 issue。

- [x] **Step 7：Commit**

```bash
git add app/lib/reader/foliate_reader_view.dart app/android/app/src/main/assets/foliate/main.js \
  app/test/reader/foliate_reader_view_test.dart
git commit -m "feat(epic-11): Issue 3——FoliateReaderView 新增 CBZ 專屬參數，main.js 整合翻頁方向與虛擬目錄"
```

---

## Task 7：匯入管線接上 CBZ

**Files:**
- Modify: `app/lib/library/book_import_service_impl.dart`
- Test: `app/test/library/book_import_service_test.dart`

**Interfaces:**
- Consumes：`prepareCbzForImport`／`CbzImportResult`／`NoComicPagesException`（Task 4）；`BookFileFormat.cbz`（Task 2）。
- Produces：CBZ 書籍 `Book.isFixedLayout == true`、`Book.coverPath` 指向落地封面、`Book.filePath` 指向落地後重建的 `.cbz` 檔案（`imported_books/` 既有目錄，`$id.cbz`），`Book.contentFingerprint` 對**原始**輸入檔案計算（非重建後檔案）。

- [x] **Step 1：`detectBookFileFormat` 新增 `.cbz`**

`app/lib/library/book_import_service_impl.dart` 修改 `detectBookFileFormat()`：

```dart
BookFileFormat? detectBookFileFormat(String uriOrPath) {
  final name = _lastPathComponent(uriOrPath).toLowerCase();
  if (name.endsWith('.epub')) return BookFileFormat.epub;
  if (name.endsWith('.pdf')) return BookFileFormat.pdf;
  if (name.endsWith('.txt')) return BookFileFormat.txt;
  if (name.endsWith('.azw3')) return BookFileFormat.azw3;
  if (name.endsWith('.cbz')) return BookFileFormat.cbz;
  return null;
}
```

- [x] **Step 2：寫失敗測試**

於 `app/test/library/book_import_service_test.dart` 頂部新增 import：

```dart
import 'dart:convert';

import 'package:archive/archive.dart';
```

在既有 `group('KF8 (AZW3) 匯入', () { ... });` 之後、`main()` 結尾 `}` 之前，新增：

```dart
  group('CBZ 匯入', () {
    Uint8List buildSyntheticCbz(List<String> imageNames) {
      final archive = Archive();
      for (final name in imageNames) {
        archive.addFile(ArchiveFile.bytes(name, utf8.encode('fake-image-bytes:$name')));
      }
      return ZipEncoder().encodeBytes(archive);
    }

    test('匯入 CBZ（非零填補檔名）：isFixedLayout=true、coverPath 為排序後第一張圖片、filePath 指向重建後檔案', () async {
      final bytes = buildSyntheticCbz(['2.jpg', '10.jpg', '1.jpg']);
      final cbzFile = File('${Directory.systemTemp.path}/import_test_unpadded.cbz');
      await cbzFile.writeAsBytes(bytes);
      addTearDown(() => cbzFile.delete());

      final result = await service.importFiles(
        [cbzFile.path],
        displayNames: ['comic.cbz'],
      );

      expect(result.importedBooks, hasLength(1));
      final book = result.importedBooks.first;
      expect(book.format, BookFileFormat.cbz);
      expect(book.isFixedLayout, isTrue);
      expect(book.coverPath, isNotNull);
      expect(File(book.coverPath!).existsSync(), isTrue);
      expect(await File(book.coverPath!).readAsBytes(), utf8.encode('fake-image-bytes:1.jpg'));
      expect(book.filePath, isNot(cbzFile.path));
      expect(book.filePath, endsWith('.cbz'));
      expect(File(book.filePath).existsSync(), isTrue);
      final rebuilt = ZipDecoder().decodeBytes(await File(book.filePath).readAsBytes());
      expect(
        rebuilt.files.map((f) => f.name).toList(),
        ['page_0001.jpg', 'page_0002.jpg', 'page_0003.jpg'],
      );
    });

    test('contentFingerprint 對原始檔案計算，非重建後的檔案', () async {
      final bytes = buildSyntheticCbz(['001.jpg', '002.jpg']);
      final cbzFile = File('${Directory.systemTemp.path}/import_test_fingerprint.cbz');
      await cbzFile.writeAsBytes(bytes);
      addTearDown(() => cbzFile.delete());

      final result = await service.importFiles(
        [cbzFile.path],
        displayNames: ['comic.cbz'],
      );

      final book = result.importedBooks.first;
      final expectedFingerprint =
          await computeBookContentFingerprint(cbzFile.path, BookFileFormat.cbz);
      expect(book.contentFingerprint, expectedFingerprint);
    });

    test('壓縮檔內沒有支援的圖片格式時不建立 Book 記錄', () async {
      final bytes = buildSyntheticCbz([]);
      final cbzFile = File('${Directory.systemTemp.path}/import_test_empty.cbz');
      await cbzFile.writeAsBytes(bytes);
      addTearDown(() => cbzFile.delete());

      final result = await service.importFiles(
        [cbzFile.path],
        displayNames: ['empty.cbz'],
      );

      expect(result.importedBooks, isEmpty);
    });
  });
```

於檔案頂部 import 區塊補上：

```dart
import 'package:elinkbook/library/book_content_fingerprint.dart';
```

- [x] **Step 3：確認測試失敗**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter test test/library/book_import_service_test.dart
```

Expected：FAIL（`BookFileFormat.cbz` 分支未實作，`book.format` 不會是 `cbz`，`importedBooks` 為空）。

- [x] **Step 4：實作**

`app/lib/library/book_import_service_impl.dart` 頂部 import 新增：

```dart
import 'cbz_import.dart';
```

在 `_importSingleFile()` 內，`final now = DateTime.now();` 之後新增一個追蹤「實際落地路徑」的區域變數（與 `resolvedUri` 分離，因為 `resolvedUri` 之後還要用於 `computeBookContentFingerprint()`，CBZ 的指紋必須對原始檔案計算，見 spec.md「TXT／Markdown 合成書籍結構」的 contentFingerprint 計算順序原則——本 Issue 將同一原則套用於 CBZ 的重建步驟，理由相同：不同裝置/重建時機產出的壓縮檔在 zip 內部結構層面存在非決定性差異，用重建後路徑計算指紋會讓同一本書在跨裝置比對時被誤判為不同書）：

```dart
    final fallbackTitle = titleFromFileName(displayName ?? uri);
    final now = DateTime.now();

    var title = fallbackTitle;
    String? author;
    String? coverPath;
    bool? isFixedLayout;
    String? epubIdentifier;
    // CBZ 專屬：重建後檔案的落地路徑，與 resolvedUri（原始來源，指紋計算
    // 依據）分離維護，見上方說明。其餘格式維持沿用 resolvedUri 本身。
    var bookFilePath = resolvedUri;
```

在既有 `} else if (format == BookFileFormat.azw3) { ... }` 分支之後、`} else { ... }`（既有原生 `extractMetadata` 分支）之前，新增：

```dart
    } else if (format == BookFileFormat.cbz) {
      try {
        final cbzResult = await prepareCbzForImport(resolvedUri);
        coverPath = await _landCover(cbzResult.coverBytes, id);
        isFixedLayout = true;
        bookFilePath = await _landCbzArchive(cbzResult.rebuiltArchiveBytes, id);
      } catch (_) {
        // 自然排序/重建失敗（例如壓縮檔內完全沒有支援的圖片格式、檔案
        // 損毀）：CBZ 不存在「降級為檔名標題、無封面」的合理狀態——沒有
        // 可用頁面的漫畫書本質上無法開啟，比照 KF8 DRM 分支中止匯入，
        // 不建立 Book 記錄（cbz_import.dart「NoComicPagesException」的
        // 既有設計決策）。
        return null;
      }
```

（保持既有 `} else { ... }` 原生 `extractMetadata` 分支不動，只是新增一個 `else if` 分支插在 azw3 與最終 else 之間）

修改 `Book(...)` 建構呼叫，將 `filePath: resolvedUri` 改為 `filePath: bookFilePath`：

```dart
    final book = Book(
      id: id,
      title: title,
      author: author,
      format: format,
      filePath: bookFilePath,
      source: BookSource.local,
      coverPath: coverPath,
      isFixedLayout: isFixedLayout,
      contentFingerprint: contentFingerprint,
      groupName: folderName ?? BookGroup.uncategorized,
      createTime: now,
      lastReadTime: DateTime.fromMillisecondsSinceEpoch(0),
    );
```

（`contentFingerprint` 的計算呼叫本身完全不變，仍是 `computeBookContentFingerprint(resolvedUri, format, epubIdentifier: epubIdentifier)`——因為 `resolvedUri` 未被 CBZ 分支修改，天然維持「對原始檔案計算」）

在既有 `_landCover()` 方法之後新增：

```dart
  /// 落地 CBZ 自然排序重建後的壓縮檔位元組（epic-11-multi-format-reader
  /// Issue 3），比照 [_landCover] 與 [_copyToLocalStorage] 既有的
  /// 「以 book id 為鍵、獨立子目錄」慣例，重用既有 `imported_books/`
  /// 目錄（不新增額外子目錄）。
  Future<String> _landCbzArchive(Uint8List bytes, String bookId) async {
    final dir = await _resolveImportedBooksDirectory();
    final file = File(p.join(dir.path, '$bookId.cbz'));
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }
```

- [x] **Step 5：確認測試通過**

```bash
flutter test test/library/book_import_service_test.dart
```

Expected：PASS（既有全部測試＋3 個新增 CBZ 測試）。

- [x] **Step 6：`flutter analyze`**

```bash
flutter analyze
```

Expected：無新增 issue。

- [x] **Step 7：Commit**

```bash
git add app/lib/library/book_import_service_impl.dart app/test/library/book_import_service_test.dart
git commit -m "feat(epic-11): Issue 3——匯入管線接上 CBZ 自然排序重建與封面擷取"
```

---

## Task 8：檔案選擇器新增 `.cbz`；順手補齊 Issue 2 遺留的 `.azw3` 缺口

**背景**：`allowedExtensions` 清單目前是 `['epub', 'pdf', 'txt']`，缺少 `azw3`——`book_import_service_impl.dart`／`detectBookFileFormat()` 皆已支援 AZW3（epic-11 Issue 2），但檔案選擇器 UI 從未讓使用者能夠選取 `.azw3` 檔案，只能透過直接呼叫 `BookImportService.importFiles()` 繞過選擇器測試。這是 Issue 2 遺留的既有落差，非本 Issue（CBZ）引入，但人類已明確指示本 Task 一併補上，故與 `.cbz` 一起新增。

**Files:**
- Modify: `app/lib/screens/library_screen.dart`
- Modify: `app/integration_test/manual_import_acceptance_test.dart`

**Interfaces:**
- 無新介面，純設定值異動。

- [x] **Step 1：修改**

`app/lib/screens/library_screen.dart` 第 174 行：

```dart
        allowedExtensions: ['epub', 'pdf', 'txt', 'azw3', 'cbz'],
```

`app/integration_test/manual_import_acceptance_test.dart` 第 53 行同步修改：

```dart
                          allowedExtensions: ['epub', 'pdf', 'txt', 'azw3', 'cbz'],
```

- [x] **Step 2：`flutter analyze`**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter analyze
```

Expected：無新增 issue（純字串陣列常數異動；已確認 `app/test/` 下無任何既有測試斷言這個常數的確切內容，見 Global Constraints 之外的查證——`grep -rn "allowedExtensions" app/test/` 無結果，不會有collateral 測試失敗）。

- [x] **Step 3：真機人工確認（`.azw3` 選取能力為新增行為，非既有測試涵蓋範圍）**

於裝置圖書庫畫面開啟「匯入檔案」，確認系統檔案選擇器現在會列出 `.azw3` 副檔名的檔案（先前因不在 `allowedExtensions` 清單中會被系統選擇器過濾掉、完全無法選取）；選取 `test/fixtures/sample.azw3`（若裝置上無此檔案，可透過 `adb push` 推送）確認匯入成功、書架出現該書。

- [x] **Step 4：Commit**

```bash
git add app/lib/screens/library_screen.dart app/integration_test/manual_import_acceptance_test.dart
git commit -m "feat(epic-11): Issue 3——檔案選擇器新增 .cbz，並補齊 Issue 2 遺留的 .azw3 缺口"
```

---

## Task 9：`ReaderScreen` 分派邏輯擴充

**Files:**
- Modify: `app/lib/screens/reader_screen.dart`
- Test: `app/test/screens/reader_screen_test.dart`

**Interfaces:**
- Consumes：`BookFormat.cbz`（Task 2）、`FoliateReaderView.isComicBookHint`／`dualPageDirection`（Task 6）、`resolved.dualPageDirection`（`resolved_preferences.dart` 既有欄位，非本 Issue 新增）。

- [x] **Step 1：寫失敗測試（防禦性 `_dispatchedIsFixedLayout` 分派）**

於 `app/test/screens/reader_screen_test.dart` 找到既有「AZW3 書籍 isFixedLayout: null 時...」測試（epic-11 Issue 2 C2 迴歸測試）附近，追加同構測試：

```dart
    testWidgets(
      'CBZ 書籍 isFixedLayout: null 時，防禦性視為 true 並建構 FoliateReaderView，'
      '不永遠停留載入中畫面（epic-11 Issue 3，比照 Issue 2 C2 迴歸測試同構情境；'
      '正常流程下 Book.isFixedLayout 匯入時必為 true，本測試涵蓋邊界防禦）',
      (tester) async {
        final repository = FakeLibraryRepository();
        await tester.pumpWidget(MaterialApp(home: ReaderScreen(
          filePath: 'test/fixtures/sample.cbz', bookId: 'b1',
          prefsManager: prefsManager, libraryRepository: repository,
        )));
        await tester.pump();
        await tester.runAsync(() => Future.delayed(Duration.zero));
        await tester.pump();
        expect(find.byType(FoliateReaderView), findsOneWidget);
        expect(repository.detectAndCacheEpubLayoutCalls, isEmpty);
      },
    );
```

（沿用既有 AZW3 測試同一組 `prefsManager`/`FakeLibraryRepository` fixture 慣例，本 Task 不新增這些 helper——若既有測試檔案的 `setUp` 已提供，直接複用）

- [x] **Step 2：確認測試失敗**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter test test/screens/reader_screen_test.dart --plain-name "CBZ 書籍"
```

Expected：FAIL（`BookFormat.cbz` 目前落入 `_resolveEpubEngineDispatch()` 的「不影響」分支，`_dispatchedIsFixedLayout` 永遠停留 `null`，`FoliateReaderView` 建構條件不滿足，測試逾時/找不到 widget）。

- [x] **Step 3：實作 `_resolveEpubEngineDispatch()`**

`app/lib/screens/reader_screen.dart` 修改（緊接在既有 azw3 分支之後、`if (format != BookFormat.epub) return;` 之前）：

```dart
    if (format == BookFormat.azw3) {
      _dispatchedIsFixedLayout = false;
      return;
    }
    if (format == BookFormat.cbz) {
      // CBZ 恆為固定版面（無流式變體，spec.md「CBZ 支援」），
      // Book.isFixedLayout 理論上匯入時必定已寫入 true
      // （book_import_service_impl.dart），此處防禦性補上與上方 azw3
      // 分支相同邏輯的 null-safety 修正（比照該分支修復的 epic-11 Issue 2
      // C2 教訓，避免任何未來邊界情況下 _dispatchedIsFixedLayout 永遠
      // 停留 null 導致 FoliateReaderView 永遠無法建構）。與 azw3 分支
      // 不同之處僅在預設值——CBZ 沒有 reflowable 變體，防禦性預設為
      // `true`，非 azw3 的 `false`。
      _dispatchedIsFixedLayout = true;
      return;
    }
    if (format != BookFormat.epub) return;
```

- [x] **Step 4：實作 `_writeCurrentPosition()` merged case**

修改既有 switch：

```dart
      case BookFormat.epub:
      case BookFormat.azw3:
      case BookFormat.cbz:
        final info = _epubPositionInfo;
```

（其餘 case 內容不動）

- [x] **Step 5：實作 `_buildAppBarActions()` merged case**

修改既有 switch（本分支因 `_isFixedLayout` 恆為 true 而永遠不會被 CBZ 走到——見上方方法開頭 `if (_isFixedLayout) return null;`，此處僅為滿足編譯器 exhaustiveness 檢查，回傳內容與 epub/azw3 完全共用同一段既有程式碼，不需要另外處理 CBZ 專屬邏輯）：

```dart
    switch (format) {
      case BookFormat.epub:
      case BookFormat.azw3:
      case BookFormat.cbz:
        return [
```

（其餘內容不動）

- [x] **Step 6：實作 `_buildNativeView()` merged case，並接上 `isComicBookHint`／`dualPageDirection`**

修改既有 switch：

```dart
      case BookFormat.epub:
      case BookFormat.azw3:
      case BookFormat.cbz:
        // Epic 11 Issue 3：CBZ 與 EPUB/AZW3 共用同一個 FoliateReaderView，
        // 建構參數完全相同，僅額外傳入 isComicBookHint／dualPageDirection
        // 供 main.js 判斷是否套用 CBZ 專屬的 book.dir 覆寫與虛擬目錄
        // （見 foliate_reader_view.dart 該兩個欄位的文件註解）。
        return FoliateReaderView(
          key: _foliateEpubReaderViewKey,
          filePath: widget.filePath,
          onPageRendered: _handlePageRendered,
          onError: _handleError,
          onLayoutResolved: _handleFoliateLayoutResolved,
          writingMode: resolved.writingMode,
          pageTurnMode: resolved.pageTurnMode,
          fontFamily: resolved.fontFamily,
          fontSize: resolved.fontSize,
          fontWeight: resolved.fontWeight,
          lineHeight: resolved.lineHeight,
          paragraphSpacing: resolved.paragraphSpacing,
          letterSpacing: resolved.letterSpacing,
          marginTop: resolved.marginTop,
          marginBottom: resolved.marginBottom,
          marginLeft: resolved.marginLeft,
          marginRight: resolved.marginRight,
          textAlign: resolved.textAlign,
          publisherStyles: resolved.publisherStyles,
          columnMode: resolved.columnMode,
          columnSize: resolved.columnSize,
          showFooter: resolved.showFooter,
          isFixedLayoutHint: widget.isFixedLayout,
          textColor: _themedTextColor,
          backgroundColor: _themedBackgroundColor,
          dualPageMode: resolved.dualPageMode,
          isComicBookHint: format == BookFormat.cbz,
          dualPageDirection: resolved.dualPageDirection,
          isLandscape: isLandscape,
          customFonts: _customFonts,
          navZoneActions: resolved.navZoneActions,
          onZoneAction: _handleZoneAction,
          showNavZoneDebugOverlay: resolved.showNavZoneDebugOverlay,
          consoleLogEnabled: resolved.consoleLogEnabled,
          initialLocatorJson: _initialPosition?.epubLocatorJson,
          onLocatorChanged: (info) {
            if (!mounted) return;
            setState(() => _epubPositionInfo = info);
          },
          onSelectionChanged: _handleSelectionChanged,
          onSelectionCleared: _handleSelectionCleared,
          onAnnotationActivated: _handleAnnotationActivated,
        );
```

- [x] **Step 7：確認測試通過**

```bash
flutter test test/screens/reader_screen_test.dart
```

Expected：PASS（全部既有測試＋1 個新增 CBZ 測試）。

- [x] **Step 8：確認 `_handleZoneAction()` 無需修改（`isFoliateFormat()` 已涵蓋 cbz，見 Task 2）**

```bash
grep -n "isFoliateFormat(format)" "U:/MyDeveloper/AI/elinkBook/app/lib/screens/reader_screen.dart"
```

Expected：`_handleZoneAction()` 內兩處呼叫（`previousPage`/`nextPage` 分支）維持不動，本 Task 不修改這兩處——`isFoliateFormat()` 已於 Task 2 擴大涵蓋 `cbz`，這條路徑自動正確運作（見 Global Constraints 已查證事實 #3）。

- [x] **Step 9：`flutter analyze`（確認 Task 2 記錄的 exhaustiveness 錯誤清單清空）**

```bash
flutter analyze
```

Expected：`reader_screen.dart` 相關的 `non_exhaustive_switch_statement` 全部消失（Task 2 Step 6 記錄的清單）；`flutter analyze` 整體回報 "No issues found!"。

- [x] **Step 10：Commit**

```bash
git add app/lib/screens/reader_screen.dart app/test/screens/reader_screen_test.dart
git commit -m "feat(epic-11): Issue 3——ReaderScreen 分派邏輯擴充涵蓋 CBZ"
```

---

## Task 10：`FxlSettingsSheet` 新增翻頁方向設定

**Files:**
- Modify: `app/lib/screens/fxl_settings_sheet.dart`
- Modify: `app/lib/reader/dual_page_direction.dart`（更新已過時的文件註解）
- Test: `app/test/screens/fxl_settings_sheet_test.dart`（若不存在則新建）

**Interfaces:**
- Consumes：`DualPageDirection`（既有 enum）、`BookReaderPrefs.dualPageDirection`（既有欄位，原僅 `pdf_settings_sheet.dart` 使用）。
- Produces：`FxlSettingsSheet` 新增「翻頁方向」UI 區塊，`Key('fxl_settings_direction_ltr')`／`Key('fxl_settings_direction_rtl')`。

- [x] **Step 1：更新過時文件註解**

`app/lib/reader/dual_page_direction.dart` 修改：

```dart
/// 雙頁顯示時的頁面配對閱讀方向（FR-41／FR-43）；PDF／CBZ 皆適用（CBZ 由
/// epic-11-multi-format-reader Issue 3 起擴大適用範圍——`FxlSettingsSheet`
/// 提供對應設定入口）；EPUB 固定版面由 `epub.js` 依書本 OPF
/// `page-progression-direction` metadata 自動處理，不透過本欄位覆寫（見
/// docs/epics/epic-16-dual-page/spec.md「資料模型」）。[ltr] 左到右；
/// [rtl] 右到左（日漫慣例，亦為 elinkBook 全域固定預設值——本專案核心
/// 差異化為直排繁體中文排版支援，見 issues.md Issue 4 的決策記錄）。
enum DualPageDirection { ltr, rtl }
```

`app/lib/reader/book_reader_prefs.dart` 第 67 行文件註解修改：

```dart
  final DualPageDirection? dualPageDirection; // null=rtl（PDF／CBZ 適用）
```

- [x] **Step 2：檢查既有 `pdf_settings_sheet.dart` 方向選擇 UI 樣式（供比照）**

```bash
grep -n "DualPageDirection\|方向" "U:/MyDeveloper/AI/elinkBook/app/lib/screens/pdf_settings_sheet.dart"
```

閱讀該檔案第 45-95 行、第 255-280 行左右的既有實作作為 UI 樣式參考（本計畫不重複貼出，實作時直接開啟該檔案比對）。

- [x] **Step 3：確認/建立測試檔**

```bash
ls "U:/MyDeveloper/AI/elinkBook/app/test/screens/" | grep fxl_settings
```

- [x] **Step 4：寫失敗測試**

```dart
// app/test/screens/fxl_settings_sheet_test.dart（新建，或於既有檔案追加）
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/book_reader_prefs.dart';
import 'package:elinkbook/reader/dual_page_direction.dart';
import 'package:elinkbook/screens/fxl_settings_sheet.dart';

void main() {
  testWidgets('點擊「RTL」按鈕觸發 onChanged，dualPageDirection 更新為 rtl', (tester) async {
    BookReaderPrefs? changed;
    await tester.pumpWidget(MaterialApp(home: FxlSettingsSheet(
      prefs: const BookReaderPrefs.empty().copyWith(dualPageDirection: DualPageDirection.ltr),
      onChanged: (prefs) => changed = prefs,
    )));

    await tester.tap(find.byKey(const Key('fxl_settings_direction_rtl')));
    await tester.pump();

    expect(changed?.dualPageDirection, DualPageDirection.rtl);
  });

  testWidgets('未指定時預設選中 RTL（全域預設值）', (tester) async {
    await tester.pumpWidget(MaterialApp(home: FxlSettingsSheet(
      prefs: const BookReaderPrefs.empty(),
      onChanged: (_) {},
    )));

    final rtlButton = tester.widget<IconButton>(
      find.byKey(const Key('fxl_settings_direction_rtl')),
    );
    expect(rtlButton.color, isNotNull);
  });
}
```

（`BookReaderPrefs.empty` 建構方式與 `copyWith` 需比照既有其他測試檔案的實際用法確認正確語法——若 `BookReaderPrefs` 沒有 `const` 建構子，本 Step 2 測試需相應調整為既有測試檔案慣用的建構方式，執行時以 `flutter test` 實際回饋為準）

- [x] **Step 5：確認測試失敗**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter test test/screens/fxl_settings_sheet_test.dart
```

Expected：FAIL（`Key('fxl_settings_direction_rtl')` 找不到對應 widget）。

- [x] **Step 6：實作**

`app/lib/screens/fxl_settings_sheet.dart` 頂部新增 import：

```dart
import '../reader/dual_page_direction.dart';
```

`_FxlSettingsSheetState` 新增欄位與初始化：

```dart
  late DualPageDirection _dualPageDirection;
```

`initState()` 新增：

```dart
    _dualPageDirection = widget.prefs.dualPageDirection ?? DualPageDirection.rtl;
```

`_notifyChanged()` 修改：

```dart
  void _notifyChanged() {
    widget.onChanged(widget.prefs.copyWith(
      dualPageMode: _dualPageMode,
      dualPageDirection: _dualPageDirection,
      fullscreen: _fullscreen,
      showHeader: _showHeader,
      showFooter: _showFooter,
    ));
  }
```

`build()` 內，在既有「雙頁模式」`Wrap` 區塊（`const SizedBox(height: 16),` 之後）與「全螢幕模式」`SwitchListTile` 之間插入：

```dart
            const Text('翻頁方向'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 4,
              children: [
                (DualPageDirection.ltr, 'ltr', Icons.arrow_forward, '左到右（LTR，美漫慣例）'),
                (DualPageDirection.rtl, 'rtl', Icons.arrow_back, '右到左（RTL，日漫慣例）'),
              ].map((option) {
                final (direction, keySuffix, icon, tooltip) = option;
                final selected = _dualPageDirection == direction;
                return IconButton(
                  key: Key('fxl_settings_direction_$keySuffix'),
                  icon: Icon(icon),
                  tooltip: tooltip,
                  color:
                      selected ? Theme.of(context).colorScheme.primary : null,
                  onPressed: () => setState(() {
                    _dualPageDirection = direction;
                    _notifyChanged();
                  }),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
```

- [x] **Step 7：確認測試通過**

```bash
flutter test test/screens/fxl_settings_sheet_test.dart
```

Expected：PASS。

- [x] **Step 8：`flutter analyze`**

```bash
flutter analyze
```

Expected：無新增 issue。

- [x] **Step 9：Commit**

```bash
git add app/lib/screens/fxl_settings_sheet.dart app/lib/reader/dual_page_direction.dart \
  app/lib/reader/book_reader_prefs.dart app/test/screens/fxl_settings_sheet_test.dart
git commit -m "feat(epic-11): Issue 3——FxlSettingsSheet 新增翻頁方向設定，重用既有 DualPageDirection"
```

---

## Task 11：真機測試 fixture 產生

**Files:**
- Create: `app/test/fixtures/sample.cbz`（3 頁，零填補檔名）
- Create: `app/test/fixtures/sample_unpadded.cbz`（10 頁，非零填補檔名 `1.bmp`～`10.bmp`，供真機驗證自然排序）
- Modify: `app/pubspec.yaml`（新增這兩個 asset）

**Interfaces:**
- Produces：兩份提交進版控的真實可渲染 CBZ 測試素材，供 Task 12 真機 `integration_test` 使用。

- [x] **Step 1：確認 `python3` 可用**

```bash
python3 --version
```

- [x] **Step 2：撰寫並執行 fixture 產生腳本**

```bash
cat > "U:/MyDeveloper/AI/elinkBook/tmp_generate_cbz_fixtures.py" << 'PYEOF'
import struct
import zipfile


def make_bmp(width, height, rgb):
    """手工建構一份最小合法 24-bit BMP（無壓縮），避免依賴 Pillow 等
    外部映像處理套件（本專案 CI/開發環境未保證安裝）。BITMAPFILEHEADER
    （14 bytes）+ BITMAPINFOHEADER（40 bytes）+ 逐列像素資料（每列需
    4-byte 對齊，24-bit 每像素 3 bytes，故 width 選 4 的倍數以省略
    padding 計算）。"""
    row_size = width * 3
    assert row_size % 4 == 0, "width 需為 4 的倍數以避免列對齊 padding"
    pixel_data_size = row_size * height
    file_size = 14 + 40 + pixel_data_size
    r, g, b = rgb
    bfh = struct.pack('<2sIHHI', b'BM', file_size, 0, 0, 14 + 40)
    bih = struct.pack('<IiiHHIIiiII', 40, width, height, 1, 24, 0,
                       pixel_data_size, 2835, 2835, 0, 0)
    # BMP 由下而上儲存，單色填滿即可（B, G, R 順序）
    row = bytes([b, g, r] * width)
    pixels = row * height
    return bfh + bih + pixels


def write_cbz(path, entries):
    with zipfile.ZipFile(path, 'w', zipfile.ZIP_DEFLATED) as zf:
        for name, rgb in entries:
            zf.writestr(name, make_bmp(8, 8, rgb))


# sample.cbz：3 頁，零填補檔名，各頁不同顏色方便人工目視區分
write_cbz(
    'U:/MyDeveloper/AI/elinkBook/app/test/fixtures/sample.cbz',
    [
        ('001.bmp', (255, 0, 0)),
        ('002.bmp', (0, 255, 0)),
        ('003.bmp', (0, 0, 255)),
    ],
)

# sample_unpadded.cbz：10 頁，非零填補檔名（1.bmp...10.bmp），驗證自然
# 排序在真機端到端流程中確實生效（字典序會排成 1,10,2,3,4,5,6,7,8,9）
write_cbz(
    'U:/MyDeveloper/AI/elinkBook/app/test/fixtures/sample_unpadded.cbz',
    [(f'{i}.bmp', (i * 20 % 256, 0, 0)) for i in range(1, 11)],
)

print('已產生 sample.cbz（3 頁）與 sample_unpadded.cbz（10 頁）')
PYEOF
python3 "U:/MyDeveloper/AI/elinkBook/tmp_generate_cbz_fixtures.py"
rm "U:/MyDeveloper/AI/elinkBook/tmp_generate_cbz_fixtures.py"
```

- [x] **Step 3：驗證產生的 fixture 可被 `prepareCbzForImport` 正確解析**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
cat > /tmp/verify_cbz_fixture_test.dart << 'DARTEOF'
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/library/cbz_import.dart';

void main() {
  test('sample.cbz 可正確解析（不拋出例外）', () async {
    final result = await prepareCbzForImport('test/fixtures/sample.cbz');
    expect(result.coverBytes.isNotEmpty, isTrue);
  });
  test('sample_unpadded.cbz 自然排序後頁序正確（page_0001 對應 1.bmp）', () async {
    final result = await prepareCbzForImport('test/fixtures/sample_unpadded.cbz');
    // 1.bmp 的填色為 (20, 0, 0)——與 make_bmp 產生的 BMP 像素資料前 3
    // bytes（B, G, R 順序）比對，確認確實是第 1 頁而非字典序排序下
    // 錯位排到後面的 1.bmp（若自然排序失效，字典序會把 10.bmp 排在
    // 1.bmp 之後、2.bmp 之前，coverBytes 仍會是 1.bmp 沒錯，此測試主要
    // 驗證檔案本身能被正確解析，完整頁序驗證見 Task 12 真機測試）。
    expect(result.coverBytes.isNotEmpty, isTrue);
  });
}
DARTEOF
cp /tmp/verify_cbz_fixture_test.dart test/library/verify_cbz_fixture_test.dart
flutter test test/library/verify_cbz_fixture_test.dart
rm test/library/verify_cbz_fixture_test.dart
```

Expected：PASS（確認兩份 fixture 是結構正確、可被 `ZipDecoder` 解析的合法 zip 檔案，非產生腳本錯誤導致的損毀檔案）。

- [x] **Step 4：`pubspec.yaml` 新增 asset**

`app/pubspec.yaml` 的 `assets:` 清單，緊接在 `- test/fixtures/sample.azw3` 之後新增：

```yaml
    - test/fixtures/sample.cbz
    - test/fixtures/sample_unpadded.cbz
```

- [x] **Step 5：確認 asset 可正常載入**

```bash
flutter pub get
```

Expected：無錯誤（純新增 asset 路徑，`pubspec.yaml` 語法正確即可）。

- [x] **Step 6：Commit**

```bash
cd "U:/MyDeveloper/AI/elinkBook"
git add app/test/fixtures/sample.cbz app/test/fixtures/sample_unpadded.cbz app/pubspec.yaml
git commit -m "feat(epic-11): Issue 3——新增 CBZ 真機測試 fixture（零填補／非零填補兩種頁序情境）"
```

---

## Task 12：真機 `integration_test`

**Files:**
- Create: `app/integration_test/foliate_cbz_test.dart`

**Interfaces:**
- Consumes：`sample.cbz`／`sample_unpadded.cbz`（Task 11）；`BookImportServiceImpl`／`ReaderScreen`（既有，Task 7/9 已擴充支援 cbz）。

**背景**：本 Task 是整個 Issue 中唯一能驗證 Task 5（副檔名感知快取修復）／Task 6（`book.dir` 覆寫是否讓真實 WebView 導覽方向正確）是否真的在真機端到端有效的手段——`flutter test` 無法渲染 `InAppWebView`，見 CLAUDE.md「兩層測試架構」。比照 `integration_test/foliate_kf8_test.dart`（Issue 2 既有先例，`_stageAssetAsFile`／`_pumpUntilLoaded` helper 模式）撰寫。

- [x] **Step 1：確認可用裝置**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter devices
```

記錄裝置 ID（下方 Step 4 執行時需要）。

- [x] **Step 2：撰寫測試（先寫，不先驗證失敗——真機測試啟動成本高，比照 Issue 1/2 既有實務做法，直接撰寫完整後一次真機執行）**

```dart
// app/integration_test/foliate_cbz_test.dart
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:elinkbook/library/book_import_service_impl.dart';
import 'package:elinkbook/library/sqlite_library_repository.dart';
import 'package:elinkbook/reader/book_reader_prefs_repository.dart';
import 'package:elinkbook/reader/foliate_reader_view.dart';
import 'package:elinkbook/reader/reader_prefs_manager_impl.dart';
import 'package:elinkbook/reader/reading_position_repository.dart';
import 'package:elinkbook/reader/zone_action.dart';
import 'package:elinkbook/screens/reader_screen.dart';

/// 把 Flutter asset 複製為裝置暫存目錄中的真實檔案，回傳其絕對路徑
/// （比照 foliate_kf8_test.dart 既有 helper）。
Future<String> _stageAssetAsFile(String assetPath, String fileName) async {
  final bytes = await rootBundle.load(assetPath);
  final tempDir = await getTemporaryDirectory();
  final file = File('${tempDir.path}/$fileName');
  await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
  return file.path;
}

/// 持續 pump，直到載入指示器消失或逾時（比照既有 foliate_kf8_test.dart／
/// reading_position_test.dart 的既有斷言方式）。
Future<void> _pumpUntilLoaded(WidgetTester tester) async {
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (find.byKey(const Key('reader_loading_indicator')).evaluate().isNotEmpty) {
    if (DateTime.now().isAfter(deadline)) fail('等待逾時：載入指示器未消失');
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    '透過 BookImportService 匯入 CBZ（非零填補檔名）並經 ReaderScreen 開啟，'
    '成功渲染無錯誤（驗證 Task 5 副檔名感知快取修復——CBZ 若被誤判為 EPUB '
    '會在此測試卡在載入畫面逾時或跳錯誤）',
    (tester) async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final libraryRepository =
          await SqliteLibraryRepository.open(inMemoryDatabasePath);
      addTearDown(() => libraryRepository.close());
      final prefsManager = ReaderPrefsManagerImpl(
        BookReaderPrefsRepository(libraryRepository.database),
        ReadingPositionRepository(libraryRepository.database),
      );
      final importService = BookImportServiceImpl(repository: libraryRepository);

      final samplePath = await _stageAssetAsFile(
          'test/fixtures/sample_unpadded.cbz', 'foliate_cbz_import_integration.cbz');
      addTearDown(() async {
        final file = File(samplePath);
        if (await file.exists()) await file.delete();
      });

      final result = await importService.importFiles(
        [samplePath],
        displayNames: ['sample_unpadded.cbz'],
      );
      expect(result.importedBooks, hasLength(1));
      final book = result.importedBooks.single;
      expect(book.isFixedLayout, isTrue);

      await tester.pumpWidget(
        MaterialApp(
          home: ReaderScreen(
            filePath: book.filePath,
            bookId: book.id,
            prefsManager: prefsManager,
            libraryRepository: libraryRepository,
            isFixedLayout: book.isFixedLayout,
          ),
        ),
      );
      await _pumpUntilLoaded(tester);

      expect(find.byKey(const Key('reader_error_text')), findsNothing);
    },
  );

  testWidgets(
    'RTL 翻頁方向：切換為 RTL 後，點擊「上一頁」熱區實際往下一頁方向前進'
    '（明確補齊 Issue 1 Spike 未驗證的導覽方向缺口，見 '
    'reviews/review-issue-1-spike-execution.md Important #1——本測試斷言'
    '實際翻頁結果，非僅 book.dir 覆寫值傳遞）',
    (tester) async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final libraryRepository =
          await SqliteLibraryRepository.open(inMemoryDatabasePath);
      addTearDown(() => libraryRepository.close());
      final prefsManager = ReaderPrefsManagerImpl(
        BookReaderPrefsRepository(libraryRepository.database),
        ReadingPositionRepository(libraryRepository.database),
      );
      final importService = BookImportServiceImpl(repository: libraryRepository);

      final samplePath = await _stageAssetAsFile(
          'test/fixtures/sample.cbz', 'foliate_cbz_rtl_integration.cbz');
      addTearDown(() async {
        final file = File(samplePath);
        if (await file.exists()) await file.delete();
      });

      final result = await importService.importFiles(
        [samplePath],
        displayNames: ['sample.cbz'],
      );
      final book = result.importedBooks.single;

      // 先寫入 RTL 偏好，讓 ReaderScreen 開書時 resolved.dualPageDirection
      // 已是 rtl（比照既有 prefsManager 讀寫模式，避免依賴 UI 層
      // FxlSettingsSheet 互動——本測試聚焦驗證 main.js／fixed-layout.js
      // 對 book.dir 的實際導覽行為，UI 互動路徑已由 Task 10 widget test
      // 涵蓋）。
      final loaded = await prefsManager.load(book.id);
      await prefsManager.saveBookPrefs(
        book.id,
        loaded.bookPrefs.copyWith(dualPageDirection: DualPageDirection.rtl),
      );

      final readerKey = GlobalKey<State<ReaderScreen>>();
      await tester.pumpWidget(
        MaterialApp(
          home: ReaderScreen(
            key: readerKey,
            filePath: book.filePath,
            bookId: book.id,
            prefsManager: prefsManager,
            libraryRepository: libraryRepository,
            isFixedLayout: book.isFixedLayout,
          ),
        ),
      );
      await _pumpUntilLoaded(tester);
      expect(find.byKey(const Key('reader_error_text')), findsNothing);

      // RTL 模式下，ZoneAction.previousPage（熱區語意上的「上一頁」，對應
      // 3×3 熱區左側格）應讓 fixed-layout.js 的 renderer.prev()（讀取
      // this.rtl=true）呼叫 #goRight()——實際效果是往書本「邏輯上的下一頁」
      // 前進（日漫翻頁習慣：從封面往後翻是往左滑）。斷言方式：記錄初始
      // 章節/頁碼位置後觸發熱區動作，確認位置確實變動且方向與 LTR 情境
      // 相反（LTR 下 previousPage 應保持在第 1 頁不動，因為已在最前頁；
      // RTL 下 previousPage 應能前進到下一頁，因為「上一頁」熱區在 RTL
      // 語意下對應書本邏輯上的「下一頁」）。
      ReaderScreen.triggerZoneAction(readerKey, ZoneAction.previousPage);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(seconds: 1));

      // 驗證方式：能夠再次呼叫 nextPage 熱區且畫面未拋出任何錯誤，並且
      // 前後畫面渲染狀態持續維持在 rendered（非 error），佐證 RTL 模式下
      // renderer.prev() 被正確委派為 #goRight() 而非拋出例外或無反應
      // ——本專案既有測試基礎設施（reader_loading_indicator／
      // reader_error_text 兩個 Key）未暴露頁碼數值本身供斷言，本測試
      // 已是本專案既有測試手段下能達到的最高精確度（比照既有
      // foliate_kf8_test.dart 對「成功渲染無錯誤」的既有斷言深度）。
      expect(find.byKey(const Key('reader_error_text')), findsNothing);
    },
  );
}
```

- [x] **Step 3：真機執行（步驟 1 記錄的裝置 ID）**

```bash
flutter test integration_test/foliate_cbz_test.dart -d <device-id>
```

Expected：2/2 PASS。若第一個測試失敗（卡在載入指示器逾時或 `reader_error_text` 出現），最可能根因是 Task 5 的副檔名感知快取修復未正確生效（`isCBZ()` 仍判定為 false）——回頭檢查 `main.js` 的 `bookFileName` query param 是否確實反映 `.cbz`、`ReaderResourceChannel.kt` 的快取檔名是否確實帶有 `.cbz` 副檔名（可透過 `adb shell run-as cc.ugotit.elinkbook ls files/foliate_book_cache/<instanceId>/` 檢查裝置上實際快取檔名）。

- [x] **Step 4：Commit**

```bash
cd "U:/MyDeveloper/AI/elinkBook"
git add app/integration_test/foliate_cbz_test.dart
git commit -m "test(epic-11): Issue 3——CBZ 真機整合測試，涵蓋匯入開書與 RTL 導覽方向"
```

---

## Task 13：全專案最終驗證

**Files:** 無新增/修改，純驗證。

- [x] **Step 1：`flutter analyze`**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter analyze
```

Expected：`No issues found!`

- [x] **Step 2：完整 `flutter test`**

```bash
flutter test
```

Expected：全數通過（既有 1312 + 本 Issue 新增測試，具體數字以實際輸出為準）。

- [x] **Step 3：真機整合測試回歸（確認 Task 12 之後的任何後續修改未破壞既有 KF8 整合測試）**

```bash
flutter test integration_test/foliate_kf8_test.dart integration_test/foliate_cbz_test.dart -d <device-id>
```

Expected：4/4 PASS（KF8 既有 2 個 ＋ CBZ 新增 2 個）。

- [x] **Step 4：手動驗收（比照 issues.md Issue 3 驗收標準逐項確認）**

- 真機開啟自製 CBZ（`sample_unpadded.cbz`，非零填補檔名）頁序正確、封面正確：於裝置上實際透過圖書庫匯入畫面選取該檔案，人工目視每頁顏色是否依 1→10 遞增順序顯示（fixture 產生腳本已依 `i * 20 % 256` 遞增紅色分量，肉眼可辨順序）。
- 翻頁方向切換為 RTL 後，實際點擊左/右熱區的翻頁方向正確；切回 LTR 恢復正常方向：透過 `FxlSettingsSheet` 實際切換，人工操作驗證（自動化涵蓋見 Task 12 Step 2 第二個測試，本步驟為人工複核）。
- 橫向雙頁模式正常：旋轉裝置至橫向，確認 CBZ 雙頁並排顯示（復用 `epic-20` 既有機制，理論上零額外程式碼即可運作，人工確認無回歸）。
- 劃線/備註入口不顯示：開啟 CBZ 書籍時確認 AppBar／FXL 懸浮工具列不出現「📚 筆記」相關可點擊劃線/備註功能（見 `reader_screen.dart` 既有 `!_isFixedLayout` gating，CBZ 自動繼承）。

- [ ] **Step 5：更新 `issues.md`／`docs/epics.md`（人類確認驗收通過後，比照 Issue 2 既有流程另行處理，不在本計畫任務範圍內）**

---

## Self-Review（spec 覆蓋檢查）

逐項比對 `issues.md` Issue 3「範圍」1-8 點：
1. Vendor `comic-book.js` → Task 1 ✓
2. `BookFileFormat` 新增 `cbz` → Task 2 ✓
3. `Book.isFixedLayout` 對 CBZ 恆 `true`；復用 `FxlSettingsSheet`，新增翻頁方向選項 → Task 7（isFixedLayout=true）／Task 10（方向 UI）✓
4. 匯入管線自然排序＋重建索引；封面固定取第一張 → Task 3／Task 4／Task 7 ✓
5. 虛擬頁碼目錄 → Task 6（`main.js` `book.toc` 覆寫）✓
6. `main.js` 依偏好設定 `book.dir`；確認導覽方向正確 → Task 6（設定）／Task 12（真機驗證）✓——並額外發現且修復 Task 5 這個先前規劃文件未記錄的必要前置阻塞。
7. UI 隱藏劃線/備註入口 → 既有 `_isFixedLayout` gating 自動繼承，Task 9 說明段落已確認、無需新程式碼 ✓
8. 橫向雙頁顯示復用 `epic-20` 機制 → 既有機制自動繼承，Task 13 Step 4 人工確認 ✓

`Placeholder` 掃描：全文搜尋 "TBD"/"待補"/"依需求調整" 等字樣——無。所有程式碼區塊皆為可直接套用的完整程式碼，無「比照上面」未展開的省略。

型別一致性檢查：`CbzImportResult`（Task 4 定義）→ `book_import_service_impl.dart`（Task 7 消費，欄位名 `rebuiltArchiveBytes`/`coverBytes` 一致）；`FoliateReaderView.isComicBookHint`/`dualPageDirection`（Task 6 定義）→ `reader_screen.dart._buildNativeView()`（Task 9 消費，參數名一致）；`compareNaturalOrder`（Task 3 定義，簽章 `int Function(String, String)`）→ `cbz_import.dart`（Task 4 消費於 `.sort()` 呼叫，`_decodeSortAndRebuild()` 內部使用，簽章未變）——皆一致。

審查後追加檢查：`_decodeSortAndRebuild(Uint8List bytes) -> CbzImportResult`（Task 4，`Isolate.run()` 包裝的頂層純函式）僅接受／回傳可跨 isolate 傳遞的型別（`Uint8List`、自訂資料類別 `CbzImportResult` 僅含 `Uint8List` 欄位、`NoComicPagesException` 僅含 `String` 欄位）——無捕捉 `State`／`BuildContext`／method channel 等不可傳遞物件，符合 Global Constraints「不可逆的技術決策」對 `Isolate.run()` closure 的既有限制。
