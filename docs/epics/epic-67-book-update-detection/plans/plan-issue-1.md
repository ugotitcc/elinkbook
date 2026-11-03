# Issue 1：核心——更新版偵測與取代 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在既有 `BookImportService` 上新增「偵測更新版」「取代」「丟棄候選」「強制作為新書匯入」四個能力，並讓 `importFiles`／`importFolder` 遇到更新版時改為回傳更新候選而不直接寫入。本 Issue 不含任何畫面；Issue 2／3／4 三個入口共用這組能力。

**Architecture:** 新型別與純函式放新檔 `app/lib/library/book_update_models.dart`；服務介面擴充在 `book_import_service.dart`，實作在 `book_import_service_impl.dart`。為了讓「取代」與「第一次匯入」共用同一份逐格式處理邏輯（TXT／MD 合成、CBZ 重建、KF8／EPUB／PDF 取中繼資料、封面），先把 `_importSingleFile` 內的逐格式區塊抽成私有方法 `_prepareBookParts`（行為不變，既有測試護欄），再讓取代以「暫存名稱」呼叫它。取代採「先全部寫到暫存名稱，成功才換名＋更新資料庫」的兩階段，任何階段失敗清掉暫存、舊書不動。

**Tech Stack:** Flutter／Dart、`sqflite_common_ffi`（測試用記憶體資料庫）、`MethodChannel` 假處理器（`elinkbook/book_metadata`）。

**Spec:** `docs/epics/epic-67-book-update-detection/spec.md`；工單見同目錄 `issues.md` Issue 1；架構決策 ADR 0040；詞彙 `CONTEXT.md`「書籍更新版」「書籍內容指紋」。

**分支建議：** `epic-67/issue-1-detect-and-replace`（從最新 `main` 切出）。

## 已查證事實（2026-11-04 讀程式所得，plan 的事實依據）

| # | 事實 | 對設計的影響 |
|---|---|---|
| F1 | `Book.contentFingerprint`：EPUB 為 OPF identifier（trim 後非空時），其餘（含 identifier 缺漏的 EPUB）為整檔 SHA-256；TXT／MD／CBZ 的指紋是**原始檔**的 SHA-256 | 第一層「識別碼命中」＝`新檔 identifier == 既有書.contentFingerprint` 且既有書為 EPUB |
| F2 | TXT／MD／CBZ 的 `Book.filePath` 指向**合成／重建後的落地檔**，原始檔不保留 | 這三種格式讀不到「舊原始檔」可雜湊；重複判定只能退而比對儲存的指紋（見決策 D1） |
| F3 | TXT 沒有作者；CBZ 沒有作者；MD 只有 frontmatter 有作者時才有 | 第二層（書名＋作者）對 TXT／CBZ 永遠不命中，符合 spec 故事 14；這兩種只能走手動入口（Issue 3） |
| F4 | 落地檔名由 `Book.id` 決定：`imported_books/<id>.<epub\|pdf\|azw3\|cbz\|txt\|md>`、`covers/<id>.png`；取代時 `Book.id` 不變 → 新檔會撞到舊檔名 | 一律先寫暫存名稱，成功後以 `File.rename` 覆蓋式換名（同目錄、同檔案系統，rename 為原子） |
| F5 | `Book.copyWith` 用 `x ?? this.x`，**無法把 `coverPath`／`author` 設回 null** | 新增 `clearCoverPath`／`clearAuthor` 兩個旗標（Task 1），不改其他欄位語意 |
| F6 | `books.totalCharacterCount` 欄位仍在 schema，但自 epic-26 Issue 5 起**沒有任何 Dart 程式讀寫**（`sqlite_library_repository.dart:92` 註解） | spec／issues 的「全書字元數重置」在程式層是 **no-op**，本 Issue 不處理、不新增 SQL；在 Task 7 的文件同步中註明 |
| F7 | 閱讀器開書時的 `content://` 暫存複本是每次開啟新建（`foliate_book_cache/<instanceId>/current.<ext>`、`elinkbook_pdf_tmp/doc_<nanoTime>.pdf`） | 取代後不會讀到過期的閱讀器快取 |
| F8 | 封面以 `Image.file(File(coverPath))` 顯示；`Image.file` 以路徑為快取鍵 | 取代後封面路徑不變（`covers/<id>.png`），**Flutter 圖片快取可能仍顯示舊封面**——服務層無法處理，列入 Issue 2／3 的接線要求（取代成功後 evict 該封面的 `FileImage`），本 Issue 在 Review Focus 與 Task 7 記錄 |
| F9 | `FullTextSearchSettingsRepository.clearBookIndex(bookId)`、`handleBookAvailable(book)` 已存在；`handleBookAvailable` 內部已處理「未啟用只略過、CBZ 標 unsupported」 | 取代＝`clearBookIndex` 後呼叫 `handleBookAvailable(updatedBook)`；兩者失敗都吞掉（索引是衍生資料） |
| F10 | `FakeLibraryRepository`（`test/support/`）已實作 `updateBook`、`findBookById`、`listBooks`，可被繼承覆寫以注入失敗 | 寫入失敗注入用 `class _ThrowOnUpdateRepository extends FakeLibraryRepository`，不必手寫 20 個方法的包裝 |

## 已確認決策（2026-11-04 人類確認 D1～D4 全部採用建議）

- **D1（spec 缺口）：重複 vs 更新版對 TXT／MD／CBZ 的舊檔雜湊。** spec 寫「現場讀舊檔計算整檔 SHA-256」，但 F2 說這三種格式沒有舊原始檔。**建議**：EPUB／PDF／AZW3 現場雜湊 `Book.filePath`（舊檔讀不到 → 降級更新版＋標記）；TXT／MD／CBZ 改比對 `Book.contentFingerprint`（原始檔 SHA-256）。已被取代過的 MD 會因指紋已過期而被判為更新版（可由使用者跳過），列為已知限制。
- **D2（spec 與 issues 措辭衝突）：`importFiles`／`importFolder` 遇到「整檔相同」的重複是否跳過並計入 `skippedDuplicateCount`？** issues 寫「新書、重複行為與現況一致」（現況只擋「來源 URI 相同」），spec 故事 6 寫「整檔相同要被告知已存在並跳過」。**建議**：偵測為 `重複` 者計入 `skippedDuplicateCount` 跳過（同時保留既有的 URI 相同跳過）。代價：不同 URI、內容相同的 EPUB／PDF 將不再能重複匯入。
- **D3：取代時新檔解析失敗是否嚴格。** 第一次匯入遇到中繼資料取不到會降級為「檔名當書名、無封面」；取代若也降級，損毀檔會把好好的舊書改成檔名。**建議**：取代採嚴格模式——`PlatformException`、DRM、空 TXT／MD、無頁面 CBZ、KF8 解析例外一律回 `newFileParseFailed`；`MissingPluginException`（Windows 無原生端）維持降級，與匯入一致。
- **D4：`oldFileUnreadable` 的粒度。** spec 寫單一旗標；多候選時各候選可讀性不同。**建議**：以 `Set<String> unreadableCandidateBookIds` 表達（空集合＝全部可讀），語意是 spec 旗標的超集。

## Global Constraints

- 所有註解、文件、測試名稱一律正體中文（zh-TW）；程式碼命名維持英文。
- **不得改變既有 API 的行為**：`importFiles`／`importFolder`／`relinkBook` 對「沒有更新版」的輸入，輸出與副作用必須與現況完全相同（Task 2 以既有 `book_import_service_test.dart` 全數通過為準）。
- 背景雜湊沿用 `computeBookContentFingerprint`（本機檔案走 `Isolate.run` 的頂層函式、`content://` 走原生 `computeSha256`），**不得新增在 UI isolate 讀整檔的路徑**；不得寫會把 `State`／`PdfPage` 捲進 closure 的 `Isolate.run`。
- 畫面字串：本 Issue 無畫面，不新增 ARB 鍵。
- 提交前：`flutter analyze` 必須 "No issues found!"；`node tool/check_l10n_hardcoded_strings.js`（皆在 `app/` 下執行）。本 Issue 不動 `lib/` Key 與 `integration_test/`，不必跑 `check_integration_keys.js`。
- 測試範圍：每個 Task 只跑該 Task 觸及的測試檔；完整 `flutter test` 只在最後一個 Task 執行一次。
- 所有指令工作目錄為 `app/`。測試指令加 `--no-pub`，避免 flutter 工具改動 `pubspec.lock` 與 windows generated 檔。
- 失敗原因與分類一律用 `sealed class`／`enum`，不得用字串旗標；使用者可見文字由呼叫端在地化。

## Review Focus

1. **抽出 `_prepareBookParts` 不得改變匯入行為**（Task 2）：既有 `book_import_service_test.dart`、`book_import_service_metadata_extractor_test.dart`、`book_import_service_missing_channel_test.dart` 是護欄，抽出前後須各跑一次全綠。
2. **原子性窗口**（Task 5）：換名（檔案）與 `updateBook`（資料庫）無法放進同一交易。順序定為「全部暫存成功 → 換名 → `updateBook` → 清舊資產」。**殘餘風險**：換名成功但 `updateBook` 失敗時，磁碟上已是新檔、資料庫仍是舊中繼資料（書仍可開、閱讀位置可能偏移，再執行一次取代即可修復）。`filePath` 改指到新位置的情況（`content://` 保持 URI）則不受影響，因為該情況沒有換名。這個風險須在 `replaceBook` 文件註解明載。
3. **不可刪到仍在使用的檔**（Task 5）：舊私有複本僅在「舊 `filePath` ≠ 新 `filePath` 且位於 `imported_books/` 目錄內」時刪除；使用者重新選取同一個 URI 或本機路徑時，絕不能刪除。
4. **暫存檔零殘留**（Task 5、6）：每個失敗分支（複製、合成、解析、換名、寫庫）與成功分支都要驗證 `imported_books/`、`covers/`、更新暫存目錄下無暫存名稱檔案。
5. **「並存」不得迴圈**（Task 6）：`importCandidateAsNewBook` 必須略過更新版判定直接建新書，且新書 `filePath` 不得指向會被刪除的更新暫存目錄。
6. **候選書排序與去重**（Task 3）：識別碼命中者排最前；同一本書同時符合第一、二層不得重複出現。
7. **效能**（Task 3、7）：大批匯入每個檔案都要多一次中繼資料讀取。已加兩道前置短路：書庫內沒有同格式的書、或沒有任何身份命中，都不計算整檔雜湊。實測（Task 7）若資料夾匯入變慢明顯，回報而非自行優化。
8. **作者為空不進第二層**：空字串、純空白、`null` 皆視為空（Task 1 測試）。

---

### Task 1：型別、正規化函式與 `Book.copyWith` 清除旗標

**Files:**
- Create: `app/lib/library/book_update_models.dart`
- Modify: `app/lib/library/models/book.dart`（`copyWith` 新增 `clearCoverPath`／`clearAuthor`）
- Create: `app/test/library/book_update_models_test.dart`
- Modify: `app/test/library/models/` 下既有 `book_test.dart`（若存在則補案例；不存在則併入上面新檔）

**Interfaces（Produces）：**

```dart
/// 更新版信心等級。
enum UpdateConfidence { high /* 識別碼相同 */, suspected /* 書名＋作者相同 */ }

/// 一筆更新候選（見 spec「更新候選資料契約」）。
class BookUpdateCandidate {
  final String sourceUri;          // 新檔原始位置
  final String? displayName;       // 顯示名稱（選擇器提供的真實檔名）
  final BookFileFormat format;
  final UpdateConfidence confidence;
  final List<Book> candidateBooks; // 識別碼命中者排最前，至少一本
  final Set<String> unreadableCandidateBookIds; // D4：舊檔讀不到的候選書 id
  final String? stagedPath;        // 新檔已預先處理後的暫存位置；偵測階段為 null
  BookUpdateCandidate copyWith({String? stagedPath});
}

/// 偵測結果。
sealed class BookDetectionResult { const BookDetectionResult(); }
final class DetectedNewBook extends BookDetectionResult {}
final class DetectedDuplicate extends BookDetectionResult { final Book existingBook; }
final class DetectedUpdate extends BookDetectionResult { final BookUpdateCandidate candidate; }
final class DetectedUnsupported extends BookDetectionResult {}

/// 取代結果。
sealed class BookReplaceResult { const BookReplaceResult(); }
final class BookReplaceSuccess extends BookReplaceResult { final Book updatedBook; }
final class BookReplaceFailure extends BookReplaceResult { final BookReplaceFailureReason reason; }
enum BookReplaceFailureReason { bookNotFound, formatMismatch, newFileParseFailed, writeFailed }

/// 取代／並存時補寫的來源欄位（Issue 4 使用；只寫入非 null 者）。
class BookSourceRefs {
  final BookSource? source;
  final String? cloudFileId, remoteServerId, remoteBookId, remoteDownloadUrl;
}

/// 書名／作者比對用的正規化：去首尾空白、轉小寫、全形 ASCII（U+FF01～U+FF5E）轉半形、
/// 全形空白（U+3000）轉半形空白；空字串或純空白回傳 null（代表「空」，不參與比對）。
String? normalizeBookKey(String? raw);
```

- [ ] **Step 1：寫失敗測試**（`book_update_models_test.dart`）
  - `normalizeBookKey`：`'  Hello '`→`'hello'`；`'ＡＢＣ１２３'`→`'abc123'`；`'紅　樓夢'`（全形空白）→`'紅 樓夢'`；`''`、`'   '`、`null`→`null`；中文標點不被改動（`'，'` 維持）。
  - `Book.copyWith(clearCoverPath: true)` 得到 `coverPath == null` 且其他欄位不變；`copyWith(clearAuthor: true)` 同理；兩旗標與同名值參數同時給時以清除旗標優先（`copyWith(coverPath: 'x', clearCoverPath: true).coverPath == null`）；不傳旗標時行為與現況相同（既有 `book_test` 全綠）。
  - `BookUpdateCandidate.copyWith(stagedPath: ...)` 只改 `stagedPath`。
- [ ] **Step 2：確認失敗** `flutter test --no-pub test/library/book_update_models_test.dart`
- [ ] **Step 3：實作** 新檔與 `copyWith` 旗標（`copyWith` 只加兩個具名參數與兩行判斷，不動其他欄位）。
- [ ] **Step 4：確認通過**，並跑 `flutter test --no-pub test/library/models`（若目錄存在）確認 `Book` 既有測試不回歸。
- [ ] **Step 5：`flutter analyze`**；提交 `feat(library): 更新版偵測與取代的型別與正規化函式（epic-67 Issue 1 Task 1）`。

---

### Task 2：抽出 `_prepareBookParts`（行為不變的重構）

**Files:**
- Modify: `app/lib/library/book_import_service_impl.dart`

**目標：** 把 `_importSingleFile` 第 382～506 行（逐格式處理）與第 508～523 行（指紋計算）抽成一個私有方法，供 Task 5（取代）以「暫存後綴」重用。**這一步不新增功能，不改任何輸出。**

**Interfaces（Produces，私有）：**

```dart
/// 逐格式處理的結果（尚未寫入資料庫）。
class _BookParts {
  final String title;
  final String? author;
  final String bookFilePath;     // 最終要寫進 Book.filePath 的路徑（含暫存後綴時為暫存路徑）
  final String? coverPath;       // 同上
  final bool? isFixedLayout;
  final String? contentFingerprint;
  final List<String> stagedFiles; // 本次寫出的暫存／落地檔，供失敗時清理
}

/// 例外：嚴格模式下新檔無法解析（D3）。
class _NewFileParseException implements Exception {}

Future<_BookParts?> _prepareBookParts({
  required String originalUri,   // 呼叫端給的來源（指紋依此計算）
  required String resolvedUri,   // 已確定可讀的來源（持久化後的 URI 或本機路徑）
  required BookFileFormat format,
  required String id,
  required String fallbackTitle,
  String landSuffix = '',        // '' ＝ 第一次匯入的正式檔名；'.staging' ＝ 取代用暫存名
  bool strict = false,           // true：解析失敗拋 _NewFileParseException；false：維持現行降級
});
```

`_landCover`／`_landCbzArchive`／`_landTxtEpub`／`_landMdEpub` 各增加選填 `{String suffix = ''}`，檔名為 `'$id.<ext>$suffix'`。

- [ ] **Step 1：先跑護欄並記錄基線** `flutter test --no-pub test/library/book_import_service_test.dart test/library/book_import_service_metadata_extractor_test.dart test/library/book_import_service_missing_channel_test.dart`，全綠後才開始改。
- [ ] **Step 2：重構** 抽出 `_prepareBookParts`，`_importSingleFile` 改呼叫它（`landSuffix: ''`、`strict: false`）。`return null` 的分支（空 TXT、DRM、無頁面 CBZ、空 MD）在非嚴格模式維持回傳 `null`；嚴格模式改拋 `_NewFileParseException`。**不得調整任何既有分支的判斷順序與降級行為。**
- [ ] **Step 3：確認三份既有測試仍全綠**（與 Step 1 相同的指令）。
- [ ] **Step 4：`flutter analyze`**；提交 `refactor(library): 抽出匯入的逐格式處理為 _prepareBookParts，行為不變（epic-67 Issue 1 Task 2）`。

---

### Task 3：偵測能力 `detectBookUpdate`

**Files:**
- Modify: `app/lib/library/book_import_service.dart`（介面新增 `detectBookUpdate`）
- Modify: `app/lib/library/book_import_service_impl.dart`
- Create: `app/test/library/book_import_service_detect_test.dart`

**Interfaces（Produces）：**

```dart
/// 偵測 [uri] 是否為書庫中某本書的更新版（見 spec「判定規則」）。不寫入任何資料。
Future<BookDetectionResult> detectBookUpdate(String uri, {String? displayName});
```

**演算法（實作須依此順序）：**

1. `format = _detectImportFormat(uri, displayName)`；`null` → `DetectedUnsupported`。
2. `sameFormat = listBooks().where(format 相同)`；為空 → `DetectedNewBook`（前置短路，不讀新檔）。
3. 取新檔身份 `_peekIdentity(uri, format, displayName)` → `(title, author, epubIdentifier)`：
   - EPUB／PDF：`extractMetadata`（沿用 `_metadataExtractor` 注入點與 `MissingPluginException` 降級）；EPUB 另取 `identifier`。
   - AZW3：`extractKf8Metadata`，任何例外 → 身份空白。
   - MD：讀檔（`content://` 用 `readContentUriBytes`）→ `parseMdFrontmatter` 取 `title`／`author`；取不到書名退回 `titleFromFileName`。
   - TXT、CBZ：`(titleFromFileName, null, null)`。
   - 解析失敗 → 視為身份空白（回 `DetectedNewBook`），**偵測階段永不拋例外**。
4. 候選：
   - 第一層（僅 EPUB）：`epubIdentifier?.trim()` 非空，且 `book.contentFingerprint == identifier`。
   - 第二層：`normalizeBookKey(title)`、`normalizeBookKey(author)` 皆非 null，且與 `book.title`／`book.author` 正規化後完全相同。
   - 兩層皆命中同一本只出現一次；第一層命中者排最前，其後依 `listBooks()` 順序。無候選 → `DetectedNewBook`。
5. 重複 vs 更新版（D1）：算新檔 `newHash = computeBookContentFingerprint(uri, format)`（不傳 identifier，強制整檔 SHA-256；失敗 → 視為無法比對，回 `DetectedUpdate`）。對每個候選求「舊檔指紋」：
   - EPUB／PDF／AZW3：`computeBookContentFingerprint(book.filePath, format)`；拋例外 → 該書記入 `unreadableCandidateBookIds`，且不參與重複比對。
   - TXT／MD／CBZ：用 `book.contentFingerprint`。
   - 任一候選的舊檔指紋 == `newHash` → `DetectedDuplicate(該書)`；否則 `DetectedUpdate(candidate)`。

- [ ] **Step 1：寫失敗測試**（`book_import_service_detect_test.dart`；以 `SqliteLibraryRepository.open(inMemoryDatabasePath)` 預先 `insertBook` 既有書，`mockChannel` 控制 `extractMetadata`／`computeSha256`，本機檔案用 `Directory.systemTemp` 建 fixture，沿用 `book_import_service_test.dart` 的 setUp 樣式）：
  - `分類`：書庫為空 → `DetectedNewBook`；副檔名未知 → `DetectedUnsupported`；EPUB identifier 相同、內容不同 → `DetectedUpdate(high)`；EPUB identifier 相同、整檔相同 → `DetectedDuplicate`；書名＋作者相同、identifier 不同 → `DetectedUpdate(suspected)`。
  - `格式先決`：PDF 新檔、書庫只有同書名 EPUB → `DetectedNewBook`；TXT 新檔、書庫只有同名 MD → `DetectedNewBook`（TXT 與 MD 不互通）。
  - `作者為空`：新檔作者 `null`／`''`／`'  '` 與書庫同書名 → `DetectedNewBook`；書庫書作者為空亦同。
  - `正規化`：`'ＨＥＬＬＯ 世界'`／`' hello 世界 '` 與書庫 `'Hello 世界'` 視為相同。
  - `多候選排序`：兩本符合（一本識別碼命中、一本僅書名作者）→ 識別碼命中者在 `candidateBooks.first`；同一本兩層都命中只出現一次。
  - `舊檔讀不到`：既有書 `filePath` 指向不存在的檔 → `DetectedUpdate`，且 `unreadableCandidateBookIds` 含該書 id；其他可讀候選不在集合內。
  - `TXT／MD／CBZ 比對指紋`：MD 新檔 SHA == 既有 MD 的 `contentFingerprint` → `DetectedDuplicate`；不同 → `DetectedUpdate`。
  - `前置短路`：書庫無同格式書時 `computeSha256`、`extractMetadata` 一次都沒被呼叫（以 handler 計數驗證）。
  - `無身份命中時不算整檔雜湊`：有同格式書但身份不符 → `computeSha256` 未被呼叫。
  - `永不拋例外`：`extractMetadata` 拋 `PlatformException` → `DetectedNewBook`。
  - `不寫入`：每個案例後 `listBooks()` 內容與預置相同。
- [ ] **Step 2：確認失敗**。
- [ ] **Step 3：實作** `detectBookUpdate` 與 `_peekIdentity`；介面加方法並補文件註解（引用 spec「判定規則」與 D1）。
- [ ] **Step 4：確認通過**，並重跑 Task 2 的三份既有測試。
- [ ] **Step 5：`flutter analyze`**；提交 `feat(library): 書籍更新版偵測（epic-67 Issue 1 Task 3）`。

---

### Task 4：丟棄候選與更新暫存目錄

**Files:**
- Modify: `app/lib/library/book_import_service.dart`、`book_import_service_impl.dart`
- Modify: `app/lib/library/book_import_service_impl.dart` 建構子（新增選填 `Directory? updateStagingDirectory`，預設 `<getApplicationDocumentsDirectory()>/update_staging`，比照 `_resolveImportedBooksDirectory` 的懶建立）
- Create: `app/test/library/book_import_service_update_staging_test.dart`

**Interfaces（Produces）：**

```dart
/// 丟棄候選：刪除其 [BookUpdateCandidate.stagedPath] 指向的暫存檔；已不存在或為 null 時靜默成功。
/// 呼叫端在使用者選跳過、關閉彙整清單、返回、取消時必須呼叫。永不拋例外。
Future<void> discardUpdateCandidate(BookUpdateCandidate candidate);
```

內部輔助（私有）：`_stageNewFile(String uri, BookFileFormat format) → Future<String?>`：把新檔複製到更新暫存目錄（`content://` 呼叫既有 `copyContentUriToFile`；本機路徑用 `File.copy`），檔名 `<微秒時間戳>-<uri.hashCode>.<副檔名>`，失敗回傳 `null`（並清掉半成品）。

- [ ] **Step 1：寫失敗測試**：`discardUpdateCandidate` 刪除暫存檔；`stagedPath == null` 不報錯；檔案已不存在不報錯；刪除失敗（目錄被替換成檔案等）不拋例外。`_stageNewFile` 以 `importFiles`（Task 6）間接驗證，這裡先只測丟棄。
- [ ] **Step 2：確認失敗 → Step 3：實作 → Step 4：確認通過**。
- [ ] **Step 5：`flutter analyze`**；提交 `feat(library): 丟棄更新候選與更新暫存目錄（epic-67 Issue 1 Task 4）`。

---

### Task 5：取代能力 `replaceBook`

**Files:**
- Modify: `app/lib/library/book_import_service.dart`、`book_import_service_impl.dart`
- Create: `app/test/library/book_import_service_replace_test.dart`
- Create: `app/test/support/throw_on_update_repository.dart`（`class ThrowOnUpdateRepository extends FakeLibraryRepository`，`updateBook` 依旗標拋例外，並記錄 `updateBook`／`deleteBook` 呼叫）

**Interfaces（Produces）：**

```dart
/// 以 [newUri]（或 [candidate.stagedPath]）取代書籍 [bookId] 的檔案內容。
/// 見 spec「取代的語意」與 ADR 0040。永不拋例外。
Future<BookReplaceResult> replaceBook(
  String bookId,
  String newUri, {
  String? displayName,
  BookUpdateCandidate? candidate, // 帶入時以 candidate.stagedPath 為處理來源，並於結束後自行丟棄
  BookSourceRefs? sourceRefs,
});
```

**演算法（實作須依此順序，這就是原子性協議）：**

1. `book = findBookById`；`null` → `bookNotFound`。
2. `format = _detectImportFormat(newUri, displayName)`；`!= book.format` → `formatMismatch`。**允許所有格式**（不受 `_relinkableFormats` 限制）。
3. 決定處理來源 `source = candidate?.stagedPath ?? newUri`。
4. **準備階段（只寫暫存名稱 `.staging`，不碰正式檔名與資料庫）**：
   - EPUB／PDF／AZW3：
     - 來源是 `candidate.stagedPath`（本機暫存檔）：最終 `filePath` 一律為私有複本 `imported_books/<id>.<ext>`，先把暫存檔複製到 `imported_books/<id>.<ext>.staging`。
     - 來源是 `content://`：沿用 `_persistPermissionOrLandCopy` 的規則（可持久化且 URI 含副檔名 → 保持 URI、無需換名；否則複製到 `<id>.<ext>.staging`，最終落地為 `<id>.<ext>`）。
     - 來源是本機路徑：保持路徑，無需換名。
   - 呼叫 `_prepareBookParts(landSuffix: '.staging', strict: true)`（D3）；TXT／MD／CBZ 的合成檔、封面皆寫成 `<id>.<ext>.staging`／`<id>.png.staging`。
   - 任何一步失敗：刪除本次所有暫存名稱檔 → 回傳 `newFileParseFailed`（解析類）或 `writeFailed`（複製／寫檔類）；舊書不動。
5. **換名階段**：對每個暫存檔做 `File.rename` 覆蓋為正式檔名（先換書檔、後換封面）。新版沒有封面（`parts.coverPath == null`）→ 刪除舊封面檔。換名失敗 → 清掉剩餘暫存檔、回傳 `writeFailed`（已換成功者無法還原，屬 Review Focus 2 殘餘風險）。
6. **資料庫階段**：以 `book.copyWith(...)` 組新記錄——`title`、`author`（新檔無作者用 `clearAuthor`）、`filePath`、`coverPath`（無封面用 `clearCoverPath`）、`isFixedLayout` 取自新檔；**`id`、`contentFingerprint`、`progress`、`epubLocator`、`pdfPageIndex`、`groupName`、`createTime`、`lastReadTime`、同步相關欄位一律沿用**；`sourceRefs` 非 null 欄位覆寫。`updateBook` 失敗 → `writeFailed`。
7. **收尾（失敗一律吞掉，不影響成功結果）**：舊私有複本——僅當「舊 `filePath` ≠ 新 `filePath`，且舊路徑位於 `imported_books/` 目錄內」才刪除（Review Focus 3）；`clearBookIndex(bookId)` → `handleBookAvailable(updatedBook)`；若有 `candidate` 則 `discardUpdateCandidate`。
8. 回傳 `BookReplaceSuccess(updatedBook)`。

**步驟：**

- [ ] **Step 1：寫失敗測試**（`book_import_service_replace_test.dart`；用 `SqliteLibraryRepository` 記憶體庫＋真實暫存目錄檔案；失敗注入用 `ThrowOnUpdateRepository` 與會拋 `PlatformException` 的 channel handler）：
  - `身份保留`：取代 EPUB 後 `id`、`contentFingerprint`、`progress`、`epubLocator`、`groupName`、`createTime`、`lastReadTime` 與取代前相同；PDF 同理保留 `pdfPageIndex`。
  - `註記保留`：取代前於同一資料庫預先寫入該書的書籤、劃線、備註各一筆，取代後三者仍存在且 `bookId` 不變；整個過程 `deleteBook` 呼叫次數為 0。
  - `單書版面偏好保留`：預先寫入 `book_reader_prefs`，取代後仍存在。
  - `中繼資料更新`：書名、作者、`isFixedLayout` 取自新檔；新檔無作者 → `author == null`。
  - `封面`：新檔有封面 → `covers/<id>.png` 內容為新封面；新檔無封面 → 舊封面檔被刪除且 `coverPath == null`。
  - `TXT／MD／CBZ 重新合成`：以新內容取代後，`filePath` 指向的合成檔內容反映新檔；檔名仍為 `<id>.txt`／`<id>.md`／`<id>.cbz`。
  - `全文索引`：假的 `FullTextSearchSettingsRepository`（記錄呼叫）顯示 `clearBookIndex(bookId)` 在 `handleBookAvailable` 之前被呼叫各一次；未提供該 repository 時不報錯；`clearBookIndex` 拋例外時取代仍成功。
  - `舊資產清理`：舊書為私有複本且新路徑不同（例如新來源是 `content://` 可持久化）→ 舊複本被刪；新路徑等於舊路徑（重新選同一個本機路徑）→ **檔案不被刪**。
  - `格式不符`：PDF 取代 EPUB → `formatMismatch`，舊書、舊檔完全不動。
  - `bookNotFound`：不存在的 id → `bookNotFound`。
  - `原子性（注入失敗）`：分別在 ①`copyContentUriToFile` 拋例外、②TXT 內容為空（合成失敗）、③`extractMetadata` 拋 `PlatformException`、④`ThrowOnUpdateRepository.updateBook` 拋例外 四個階段，驗證：回傳對應失敗原因；`imported_books/`、`covers/` 內**沒有任何 `.staging` 檔**；舊檔位元組與取代前完全相同；舊封面仍在；資料庫記錄與取代前相同（④ 的資料庫本身未被改動）。
  - `合成格式不提前覆蓋`：TXT 取代在「換名前」讀取正式檔名（以 hook 或在準備階段後檢查），內容仍是舊版。
  - `D3 嚴格模式`：`extractMetadata` 拋 `PlatformException` 時回 `newFileParseFailed`（不是降級成檔名）；拋 `MissingPluginException` 時降級成功（Windows 路徑）。
  - `sourceRefs`：帶 `cloudFileId`／`remoteServerId`／`remoteBookId`／`remoteDownloadUrl` 時對應欄位被寫入；不帶時沿用舊值。
  - `candidate`：帶 `candidate.stagedPath` 取代成功後暫存檔消失；失敗時**暫存檔仍保留**（讓呼叫端可重試或自行丟棄）。
  - `殘餘風險記錄`：④ 之外另加一個案例，證明「換名成功但 `updateBook` 失敗」後再次呼叫 `replaceBook` 可成功修復。
- [ ] **Step 2：確認失敗**。
- [ ] **Step 3：實作** `replaceBook` 與必要私有輔助；`replaceBook` 文件註解必須寫明殘餘風險（Review Focus 2）與 D1／D3 的決定。
- [ ] **Step 4：確認通過**，並重跑 Task 2、3 的測試檔。
- [ ] **Step 5：`flutter analyze`**；提交 `feat(library): 書籍取代能力 replaceBook，原子換檔並保留註記與身份（epic-67 Issue 1 Task 5）`。

---

### Task 6：強制作為新書匯入與匯入管線整合

**Files:**
- Modify: `app/lib/library/book_import_service.dart`（`ImportResult` 新增 `updateCandidates`；介面新增 `importCandidateAsNewBook`）
- Modify: `app/lib/library/book_import_service_impl.dart`
- Create: `app/test/library/book_import_service_pipeline_test.dart`

**Interfaces（Produces）：**

```dart
class ImportResult {
  // 既有欄位不變，新增：
  final List<BookUpdateCandidate> updateCandidates; // 預設 const []，stagedPath 皆已填入
}

/// 略過更新版判定，把 [candidate] 當成新書匯入（spec「並存」）。新書 filePath 不得指向更新暫存目錄；
/// 完成後（成功或失敗）都丟棄候選。成功回傳新書，失敗回傳 null。
Future<Book?> importCandidateAsNewBook(
  BookUpdateCandidate candidate, {
  String? folderName,
  BookSourceRefs? sourceRefs,
});
```

**`importFiles`／`importFolder` 的改動：** 在既有「來源 URI 重複 → 跳過」判斷**之後**、`_importSingleFile` **之前**，對每個檔案呼叫 `detectBookUpdate`：
- `DetectedDuplicate` → `skippedDuplicateCount++`，不匯入（D2）。
- `DetectedUpdate` → `_stageNewFile` 複製到更新暫存目錄；成功則 `candidate.copyWith(stagedPath: ...)` 加進 `updateCandidates`、不匯入；複製失敗 → 該檔略過（與單檔匯入失敗的既有處置一致，不影響其他檔）。
- `DetectedNewBook`／`DetectedUnsupported` → 走既有 `_importSingleFile`（`DetectedUnsupported` 仍由其回傳 null 略過，行為不變）。
- `detectBookUpdate` 自身永不拋例外，故不會中斷整批。

`importCandidateAsNewBook` 實作：呼叫 `_importSingleFile`，加選填參數 `bool landLocalCopy`（只此入口為 true）——當處理來源是本機路徑（更新暫存檔）且格式為 EPUB／PDF／AZW3 時，先複製到 `imported_books/<新 id>.<ext>`，讓 `Book.filePath` 指向私有複本而非暫存目錄；TXT／MD／CBZ 本來就落地合成檔，不受影響。無論成敗，最後都 `discardUpdateCandidate`。

- [ ] **Step 1：寫失敗測試**：
  - `更新版不寫入`：預置同 identifier 的 EPUB；`importFiles([新檔])` → `importedBooks` 空、`updateCandidates` 有 1 筆且 `stagedPath` 檔案存在、`listBooks()` 仍只有 1 本。
  - `重複跳過`：整檔相同 → `skippedDuplicateCount == 1`、`updateCandidates` 空（D2）。
  - `新書與既有行為不回歸`：全新書匯入、同批次重複 URI 的跳過計數、`importFolder` 的授權失敗／列舉失敗結果與現況相同。
  - `混合批次`：一批含 1 新書、1 更新版、1 重複 → 結果各歸其類，順序不影響。
  - `暫存複製失敗`：`copyContentUriToFile` 拋例外 → 該檔略過，其他檔照常匯入。
  - `並存`：`importCandidateAsNewBook` → 建出新書（新 `id`、新指紋、`filePath` 不在更新暫存目錄內），原書不變，暫存檔消失；再對同一個新檔呼叫 `detectBookUpdate` 不再被判為「待處理」迴圈——但**不要求**其回 `DetectedNewBook`（它與原書仍同識別碼）；要求的是 `importCandidateAsNewBook` 本身不重新偵測（以「不呼叫 `extractMetadata` 兩次」之外的可觀察行為驗證：結果一定建出新書）。
  - `並存失敗`：`_importSingleFile` 失敗（空 TXT）→ 回傳 null 且暫存檔仍被清除。
  - `sourceRefs`：並存時雲端／遠端欄位被寫入新書。
- [ ] **Step 2：確認失敗 → Step 3：實作 → Step 4：確認通過**，並重跑 Task 2～5 的測試檔。
- [ ] **Step 5：`flutter analyze`**；提交 `feat(library): 強制作為新書匯入，匯入管線改為回傳更新候選（epic-67 Issue 1 Task 6）`。

---

### Task 7：呼叫端相容性、完整測試與文件同步

**Files:**
- Modify（若 analyze 報錯才改）：所有 `implements BookImportService` 的假實作（`grep -rn "implements BookImportService" app/test app/lib`），補上新增的四個方法（假實作回傳固定值即可，不另寫測試）。
- Modify: `docs/epics/epic-67-book-update-detection/epic.md`（開發記錄）、`issues.md`（Issue 1 狀態與 PR 欄）、`docs/epics.md`（備註改為「Issue 1、5 已合併」，**合併後**才改）。
- Modify: `CONTEXT.md` 僅在新增了詞彙時（本 Issue 預計不新增）。

- [ ] **Step 1：`flutter analyze`**：修正因介面新增方法而編譯失敗的假實作。
- [ ] **Step 2：字串檢查** `node tool/check_l10n_hardcoded_strings.js`（本 Issue 無畫面，預期零差異）。
- [ ] **Step 3：完整 `flutter test --no-pub`** 全綠（本計畫唯一一次全套）。
- [ ] **Step 4：大批匯入體感驗證**（Review Focus 7）：以 `importFolder` 對含約 50 個 EPUB 的資料夾（可用測試 fixture 複製）量測匯入前後耗時；若偵測造成顯著退步，在 `epic.md` 記錄數據並回報，**不自行優化**。
- [ ] **Step 5：文件同步**：`epic.md` 新增「Issue 1 計畫與實作」段，記錄 D1～D4 的最終決定、F6（字元數欄位為 no-op）、F8（封面快取須由 Issue 2／3 接線處理）、殘餘風險。`issues.md` Issue 1 補上計畫連結；Issue 2、3 的範圍各補一行「取代成功後須 evict 該書封面的 `FileImage` 快取」。
- [ ] **Step 6：提交** `docs(epic-67): Issue 1 實作記錄與後續 Issue 接線提醒`。

---

## 不在本 Issue 範圍（避免誤做）

- 任何畫面、對話框、ARB 字串（Issue 2、3、4）。
- `relinkBook` 的「強制重新連結」分支（Issue 3）。
- 下載佇列的「待確認更新」狀態與啟動時清掃專屬暫存目錄（Issue 4；本 Issue 只提供 `updateStagingDirectory` 與丟棄能力）。
- WiFi 傳輸服務的去重（維持現狀）。
- `totalCharacterCount` 欄位的任何處理（F6：沒有程式讀寫，不動）。
