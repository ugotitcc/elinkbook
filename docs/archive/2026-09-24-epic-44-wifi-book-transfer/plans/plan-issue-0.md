# Epic 44 Issue 0：依賴引進與共用檔案 Prefactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 為 WiFi 傳書 Epic 打好共用基礎設施：引進 4 個正式依賴（`shelf`／`shelf_multipart`／`qr_flutter`／`wakelock_plus`），修正既有 PDF `content://` 材質化呼叫端的主執行緒 ANR 風險（channel 改名），並在 `LibraryRepository` 新增 `findBookById()` 單筆查詢方法。本 Issue 不含任何使用者可見的 WiFi 傳書功能。

**Architecture:** 純粹的依賴/基礎設施異動，不新增業務邏輯模組。兩個既有呼叫端（`PdfReaderView`／`PdfContentIndexer`）改用背景佇列 channel `elinkbook/reader_resources_cache`（原生端 `ReaderResourceChannel.kt` 早已同時服務兩條 channel，Kotlin 端不需修改）；`LibraryRepository` 依既有 `findByContentFingerprint()`／`findByCloudFileId()` 單筆查詢慣例新增 `findBookById()`，`SqliteLibraryRepository`／`FakeLibraryRepository` 兩層皆須實作。

**Tech Stack:** Flutter/Dart、sqflite、flutter_test（純 Dart／widget test，無需裝置）。

**Spec:** `docs/epics/epic-44-wifi-book-transfer/spec.md`（「新增依賴」「共用檔案異動」「`LibraryRepository` 異動」三節）與 `docs/epics/epic-44-wifi-book-transfer/issues.md`（Issue 0）。執行者應同時閱讀這兩份文件。

## Global Constraints

- 所有程式碼註解、commit message、文件皆使用正體中文（zh-TW），專業術語可保留英文（CLAUDE.md 全域規則）。
- 所有指令在 `app/` 目錄下執行（`flutter pub get`／`flutter analyze`／`flutter test`）。
- 每個 Task 只跑「這次異動實際觸及」的測試檔，不需每步驟重跑全套 `flutter test`；只有本計畫最後一個 Task（Task 5）才跑一次完整 `flutter test`（CLAUDE.md「測試執行範圍」）。
- `ReaderResourceChannel.kt`（Kotlin 原生端）**不需要修改**——`readContentUriAll` 等方法已由同一個 `onMethodCall()` 同時服務 `elinkbook/reader_resources`（主執行緒）與 `elinkbook/reader_resources_cache`（背景任務佇列）兩條 channel，差別只在 Dart 端呼叫哪一個 channel 名稱。不要嘗試修改或新增 Kotlin 檔案。
- 新增依賴不釘死版本號（spec.md M-5 明確不採納釘版本建議），用 `flutter pub add` 讓工具自行決定當下相容版本。
- 除本計畫列出的檔案外，不修改其他檔案；不「順手」重構、清理或改動未在本 Issue 範圍內的程式碼。

---

### Task 1: 新增 `pubspec.yaml` 正式依賴

**Files:**
- Modify: `app/pubspec.yaml`

**Interfaces:**
- Produces：`shelf`／`shelf_multipart`／`qr_flutter`／`wakelock_plus` 四個套件成為正式 `dependencies`，供後續 Issue 1-3 匯入使用（本 Task 不使用其 API，僅完成依賴宣告與可解析性驗證）。

- [ ] **Step 1: 用 `flutter pub add` 新增四個依賴**

於 `app/` 目錄下執行：

```bash
flutter pub add shelf shelf_multipart qr_flutter wakelock_plus
```

Expected: 指令成功結束，`app/pubspec.yaml` 的 `dependencies:` 區塊自動新增四行、`app/pubspec.lock` 同步更新，終端機顯示四個套件的已解析版本號（無版本衝突訊息）。

- [ ] **Step 2: 讀取 `app/pubspec.yaml`，為新增的四行補上中文說明註解**

用 Read 工具確認 `flutter pub add` 實際插入的版本號與位置後，用 Edit 工具在這四行前分別加上比照既有依賴（例如 `audio_session`／`flutter_tts` 條目）風格的中文註解，例如：

```yaml
  # 本機 HTTP Server 框架（epic-44-wifi-book-transfer）：官方 Dart 團隊
  # 維護，WiFi 傳書路由/中介層皆用其標準機制，不手刻 socket 處理。
  shelf: ^<實際解析版本>
  # 解析上傳的 multipart/form-data 請求（epic-44-wifi-book-transfer）。
  shelf_multipart: ^<實際解析版本>
  # 畫面上算圖顯示連線用 QR Code（epic-44-wifi-book-transfer）：純本機
  # 算圖，不需要網路連線，適合手機熱點分享情境。
  qr_flutter: ^<實際解析版本>
  # 螢幕常亮（epic-44-wifi-book-transfer）：WiFi 傳書畫面顯示中防止螢幕
  # 休眠中斷傳輸，對應 design.md「前景執行穩健度」承諾。
  wakelock_plus: ^<實際解析版本>
```

（`<實際解析版本>` 替換為 Step 1 實際解析到的版本號，不得手動改動版本號本身。）

**（`/receiving-code-review` 審查修正，M-3）** 編輯時務必維持與既有依賴項目一致的嚴格 2 空格縮排，且只在四個新增依賴前插入註解行，不得改動或重排前後既有依賴項目（例如 `audio_session`）的既有換行結構，避免 YAML 解析異常。

- [ ] **Step 3: 重新執行 `flutter pub get` 確認註解不影響解析**

```bash
flutter pub get
```

Expected: `Got dependencies!`，無錯誤訊息。

- [ ] **Step 4: Commit**

```bash
git add app/pubspec.yaml app/pubspec.lock
git commit -m "$(cat <<'EOF'
chore(deps): 新增 WiFi 傳書共用依賴 shelf/shelf_multipart/qr_flutter/wakelock_plus

epic-44-wifi-book-transfer Issue 0：後續切片（伺服器/上傳/下載/QR
Code/螢幕常亮）共用的基礎依賴，本次僅引進，不含任何業務邏輯。

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: `pdf_reader_view.dart` 的 `content://` 材質化改用背景佇列 channel

**Files:**
- Modify: `app/lib/reader/pdf_reader_view.dart:277`
- Test: `app/test/reader/pdf_reader_view_test.dart:132`

**Interfaces:**
- Consumes：無新介面依賴，僅改動 `_PdfReaderViewState._resourceChannel` 的 `MethodChannel` 名稱常數。
- Produces：`_openContentUriDocument()` 的行為與回傳值完全不變（呼叫方式、`await` 語意皆不變），僅執行緒從原生端主執行緒改為背景任務佇列，消除大檔案複製時的 ANR 風險。

- [ ] **Step 1: 修改既有測試，改用新 channel 名稱（此時尚未改動production程式碼，測試會失敗）**

Edit `app/test/reader/pdf_reader_view_test.dart`：

```dart
// 舊：
    const channel = MethodChannel('elinkbook/reader_resources');
```

```dart
// 新：
    const channel = MethodChannel('elinkbook/reader_resources_cache');
```

- [ ] **Step 2: 執行測試，確認確實失敗**

```bash
flutter test test/reader/pdf_reader_view_test.dart
```

Expected: FAIL——測試 `'content:// URI 開書透過平台通道一次性讀取全部位元組'` 逾時或斷言失敗（`renderedCount` 始終為 0），因為 production 程式碼仍呼叫舊 channel `elinkbook/reader_resources`，測試 mock 掛在新 channel 上接收不到呼叫。

- [ ] **Step 3: 修改 production 程式碼的 channel 名稱**

Edit `app/lib/reader/pdf_reader_view.dart`：

```dart
// 舊：
  static const _resourceChannel = MethodChannel('elinkbook/reader_resources');
```

```dart
// 新：
  static const _resourceChannel = MethodChannel('elinkbook/reader_resources_cache');
```

- [ ] **Step 4: 執行測試，確認通過**

```bash
flutter test test/reader/pdf_reader_view_test.dart
```

Expected: PASS，全數測試通過（含 Step 2 原本失敗的那一項，以及檔案內其餘既有測試皆維持綠燈）。

- [ ] **Step 5: Commit**

```bash
git add app/lib/reader/pdf_reader_view.dart app/test/reader/pdf_reader_view_test.dart
git commit -m "$(cat <<'EOF'
fix(reader): PDF content:// 材質化改走背景佇列 channel，避免主執行緒 ANR

epic-44-wifi-book-transfer Issue 0：ReaderResourceChannel.kt 的
elinkbook/reader_resources 是主執行緒同步複製，大檔案（100MB+）串流
複製會阻塞 UI 觸發 ANR watchdog；原生端已存在背景佇列版本
elinkbook/reader_resources_cache，改呼叫它即可，原生端不需修改。

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: `pdf_content_indexer.dart` 的 `content://` 材質化改用背景佇列 channel

**Files:**
- Modify: `app/lib/search/pdf_content_indexer.dart:94`
- Test: `app/test/search/pdf_content_indexer_test.dart`（僅回歸驗證，無需新增測試——理由見下方 Step 2 說明）

**Interfaces:**
- Consumes：無新介面依賴，僅改動頂層 `_resourceChannel` 常數。
- Produces：`readContentUriAll` 頂層函式變數（`app/lib/search/pdf_content_indexer.dart:101`）對外簽章與行為完全不變，`WifiTransferService`（後續 Issue）materializeContentUri 依賴會直接重用這個已修正版本。

- [ ] **Step 1: 修改 channel 名稱（含同步更新緊鄰的文件註解）**

Edit `app/lib/search/pdf_content_indexer.dart`：

```dart
// 舊：
const _resourceChannel = MethodChannel('elinkbook/reader_resources');
```

```dart
// 新：
const _resourceChannel = MethodChannel('elinkbook/reader_resources_cache');
```

**（`/receiving-code-review` 審查修正，M-1）** 緊接在下方的 `readContentUriAll` 文件註解（第 96-100 行）仍記載舊 channel 名稱，一併同步修正，避免註解與程式碼不一致：

```dart
// 舊：
/// 串流複製 `content://` URI 為本機暫存檔，回傳暫存檔路徑（失敗回傳
/// null）。與 `PdfReaderView._openContentUriDocument()` 呼叫同一條既有原生
/// 通道／方法（`elinkbook/reader_resources` 的 `readContentUriAll`），不
/// 新增原生端程式碼。頂層函式變數寫法（非固定函式宣告）比照
/// `foliate_native_bridge.dart` 的 `cacheBookForServing`，供測試覆寫。
```

```dart
// 新：
/// 串流複製 `content://` URI 為本機暫存檔，回傳暫存檔路徑（失敗回傳
/// null）。與 `PdfReaderView._openContentUriDocument()` 呼叫同一條既有原生
/// 通道／方法（`elinkbook/reader_resources_cache` 的 `readContentUriAll`），
/// 不新增原生端程式碼。頂層函式變數寫法（非固定函式宣告）比照
/// `foliate_native_bridge.dart` 的 `cacheBookForServing`，供測試覆寫。
```

- [ ] **Step 2: 執行既有測試套件，確認零回歸**

```bash
flutter test test/search/pdf_content_indexer_test.dart
```

Expected: PASS，全數測試通過。

**說明（為什麼這裡沒有 TDD 的「先寫失敗測試」步驟）**：查證 `app/test/search/pdf_content_indexer_test.dart` 既有測試（例如 `'content:// URI 書籍透過 readContentUriAll 解析為暫存檔後開啟...'`）是直接覆寫 `readContentUriAll` 這個頂層函式變數繞過真正的 `MethodChannel` 呼叫（測試環境本來就無法呼叫原生端），因此 channel 名稱改動對這些單元測試而言是不可觀察的——這是既有測試 seam 設計本身的限制（見 `spec.md`「測試 seam 設計」），不是本次改動的疏漏。真正驗證「channel 名稱確實正確」需要真機測試，留給 Task 5 的驗收清單提醒人類執行。

- [ ] **Step 3: Commit**

```bash
git add app/lib/search/pdf_content_indexer.dart
git commit -m "$(cat <<'EOF'
fix(search): PDF 背景全文索引的 content:// 材質化改走背景佇列 channel

epic-44-wifi-book-transfer Issue 0：與 pdf_reader_view.dart 同一輪
ANR 修正（見上一次 commit），背景全文索引情境下大檔案複製更容易被
觸發，一併修正。

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: `LibraryRepository.findBookById()`

**Files:**
- Modify: `app/lib/library/library_repository.dart`
- Modify: `app/lib/library/sqlite_library_repository.dart`
- Modify: `app/test/library/sqlite_library_repository_test.dart`
- Modify: `app/test/support/fake_library_repository.dart`
- Modify: `app/test/support/fake_library_repository_test.dart`

**Interfaces:**
- Consumes：`Book`（`app/lib/library/models/book.dart`）、`Book.fromMap()`（`SqliteLibraryRepository` 既有 helper）。
- Produces：`Future<Book?> findBookById(String id)`——命中回傳該本書，未命中回傳 `null`。供後續 Issue 2 的 `WifiTransferService.resolveDownloadSource(bookId)` 使用（單筆查詢，避免整庫 `listBooks()` 過濾）。

- [ ] **Step 1: 在 `sqlite_library_repository_test.dart` 寫失敗測試**

Edit `app/test/library/sqlite_library_repository_test.dart`，在既有 `findByCloudFileId` group 結束後、`listUndownloadedBooksForRemoteServer` group 開始前插入新 group（比照緊鄰的 `findByContentFingerprint`／`findByCloudFileId` 既有測試寫法，各自用獨立的 `SqliteLibraryRepository.open(inMemoryDatabasePath)`）：

```dart
// 錨點：緊接在既有 findByCloudFileId group 的最後一個 test 結尾，
// listUndownloadedBooksForRemoteServer group 開始之前插入：

  group('findBookById', () {
    test('命中：回傳對應書籍', () async {
      final repo = await SqliteLibraryRepository.open(inMemoryDatabasePath);
      addTearDown(() => repo.close());

      await repo.insertBook(Book(
        id: 'book1',
        title: '本機書',
        format: BookFileFormat.epub,
        filePath: '/books/book1.epub',
        source: BookSource.local,
        createTime: DateTime.fromMillisecondsSinceEpoch(1000),
        lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
      ));

      final found = await repo.findBookById('book1');
      expect(found?.id, 'book1');
      expect(found?.title, '本機書');
    });

    test('未命中：回傳 null', () async {
      final repo = await SqliteLibraryRepository.open(inMemoryDatabasePath);
      addTearDown(() => repo.close());

      expect(await repo.findBookById('does-not-exist'), isNull);
    });
  });
```

- [ ] **Step 2: 在 `fake_library_repository_test.dart` 寫失敗測試**

Edit `app/test/support/fake_library_repository_test.dart`，在既有 `FakeLibraryRepository.findByCloudFileId` group 結束後、`FakeLibraryRepository._withGroupName 保留所有新欄位` group 開始前插入：

```dart
  group('FakeLibraryRepository.findBookById', () {
    test('命中：回傳對應書籍', () async {
      final repo = FakeLibraryRepository();
      await repo.insertBook(Book(
        id: 'book1',
        title: '本機書',
        format: BookFileFormat.epub,
        filePath: '/books/book1.epub',
        source: BookSource.local,
        createTime: DateTime.fromMillisecondsSinceEpoch(1000),
        lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
      ));

      final found = await repo.findBookById('book1');
      expect(found?.id, 'book1');
      expect(found?.title, '本機書');
    });

    test('未命中：回傳 null', () async {
      final repo = FakeLibraryRepository();
      expect(await repo.findBookById('does-not-exist'), isNull);
    });
  });
```

- [ ] **Step 3: 執行兩個測試檔，確認皆因編譯錯誤而失敗**

```bash
flutter test test/library/sqlite_library_repository_test.dart test/support/fake_library_repository_test.dart
```

Expected: FAIL——分析/編譯錯誤，訊息類似 `The method 'findBookById' isn't defined for the type 'SqliteLibraryRepository'`／`'FakeLibraryRepository'`（兩個具體類別尚未實作、`LibraryRepository` 抽象類別也尚未宣告這個方法）。

- [ ] **Step 4: 在 `LibraryRepository` 新增抽象方法**

Edit `app/lib/library/library_repository.dart`：

```dart
// 舊（abstract class 結尾）：
  Future<List<Book>> listUndownloadedBooksForRemoteServer(String serverId);
}
```

```dart
// 新：
  Future<List<Book>> listUndownloadedBooksForRemoteServer(String serverId);

  /// 依主鍵 [id] 精確查詢單一書籍，供 WiFi 傳書下載路由解析下載來源使用
  /// （epic-44-wifi-book-transfer Issue 0，spec.md「`LibraryRepository`
  /// 異動」）。命中回傳該本書，未命中回傳 `null`。
  Future<Book?> findBookById(String id);
}
```

- [ ] **Step 5: 在 `SqliteLibraryRepository` 實作**

Edit `app/lib/library/sqlite_library_repository.dart`，緊接在既有 `listUndownloadedBooksForRemoteServer()` 方法之後插入（比照緊鄰的 `findByContentFingerprint()`／`findByCloudFileId()` 既有寫法，單筆查詢用 `limit: 1`）：

```dart
  @override
  Future<Book?> findBookById(String id) async {
    final rows = await _db.query(
      'books',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Book.fromMap(rows.first);
  }
```

- [ ] **Step 6: 在 `FakeLibraryRepository` 實作**

Edit `app/test/support/fake_library_repository.dart`，緊接在既有 `listUndownloadedBooksForRemoteServer()` 方法之後、`_withGroupName()` helper 之前插入（比照緊鄰的 `findByRemoteBookId()`／`findByContentFingerprint()` 既有的線性掃描寫法）：

```dart
  @override
  Future<Book?> findBookById(String id) async {
    for (final book in _books) {
      if (book.id == id) return book;
    }
    return null;
  }
```

- [ ] **Step 7: 執行兩個測試檔，確認通過**

```bash
flutter test test/library/sqlite_library_repository_test.dart test/support/fake_library_repository_test.dart
```

Expected: PASS，全數測試通過（含 Step 1／Step 2 新增的測試，以及檔案內其餘既有測試皆維持綠燈）。

- [ ] **Step 8: `flutter analyze` 確認乾淨**

```bash
flutter analyze
```

Expected: `No issues found!`（確認沒有其他未列於本計畫、意外實作 `LibraryRepository` 的類別因新增抽象方法而編譯失敗——目前已查證僅 `SqliteLibraryRepository`／`FakeLibraryRepository` 兩個實作）。

- [ ] **Step 9: Commit**

```bash
git add app/lib/library/library_repository.dart app/lib/library/sqlite_library_repository.dart app/test/library/sqlite_library_repository_test.dart app/test/support/fake_library_repository.dart app/test/support/fake_library_repository_test.dart
git commit -m "$(cat <<'EOF'
feat(library): LibraryRepository 新增 findBookById 單筆查詢方法

epic-44-wifi-book-transfer Issue 0：供後續 WiFi 傳書下載路由解析
下載來源使用（resolveDownloadSource(bookId)），避免用 listBooks()
在記憶體中過濾整庫。SqliteLibraryRepository／FakeLibraryRepository
兩層皆已補上實作與測試。

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: 最終驗證

**Files:** 無新增/修改檔案，純驗證步驟。

- [ ] **Step 1: 執行完整 `flutter analyze`**

```bash
flutter analyze
```

Expected: `No issues found!`

- [ ] **Step 2: 執行完整 `flutter test`（本計畫唯一一次全套執行，比照 CLAUDE.md「測試執行範圍」慣例）**

```bash
flutter test
```

Expected: 全數通過，零回歸（含 Task 1-4 新增/修改的測試，以及專案其餘既有 1,800+ 個測試案例）。

- [ ] **Step 3: 提醒人類執行真機／手動驗證（無法在本次會話中自動完成）**

本 Issue 的驗收標準要求「真機（或至少一次手動驗證）確認既有 `content://` PDF 開書與背景全文索引仍正常運作」——這是因為 Task 2／Task 3 的 channel 改名在純 Dart 測試環境下不可觀察（見 Task 3 Step 2 說明），必須實機測試：

1. 在 Android 裝置/模擬器上執行 `flutter run`。
2. 匯入一本透過 SAF（Storage Access Framework，`content://` URI）授權的 PDF 檔案（例如透過「選擇資料夾」匯入），確認能正常開啟閱讀。
3. 確認該本書的背景全文索引（搜尋功能）能正常建立索引、可搜尋到書內文字。
4. 若上述任一項失敗，回頭檢查 `ReaderResourceChannel.kt` 的 `elinkbook/reader_resources_cache` channel 是否正確註冊（理論上不需修改，Task 2/3 change log 已註明原生端無異動）。

此步驟無程式碼異動、無需 commit，僅作為交付給人類的驗收清單。

---

## `review-plan-issue-0.md` 審查後續（`/receiving-code-review`）

審查判定 Approved with Minor Suggestions（0 Critical／0 Important／3 Minor），逐項查證後：

- **M-1（`pdf_content_indexer.dart:98` 註解頻道名稱未同步）**：查證屬實，已補進 Task 3 Step 1（改常數的同時一併修正緊鄰的文件註解）。
- **M-3（YAML 縮排提醒）**：已補進 Task 1 Step 2 的明確提醒文字。
- **M-2（`FakeLibraryRepository` 預先加 `throwOnFindBookById` 旗標）**：**不採納**。查證緊鄰的 `throwOnFindByRemoteBookId`／`throwOnFindByCloudFileId` 兩個既有旗標的加入時機——其文件註解明確記載是在 `epic-30-calibre-remote-library Issue 3`／`epic-29-cloud-import Issue 5` 各自「實際需要測試該呼叫端的錯誤處理」時才加入，不是在對應查詢方法誕生的那個 Issue 就預先加好。Issue 0 的驗收標準只要求 `findBookById` 命中/未命中兩種情境；`resolveDownloadSource(bookId)` 的例外容錯分支測試屬於 Issue 2 範圍，屆時若真的需要才加，比照既有慣例（旗標跟著實際需要它的呼叫端走，不預先為假設情境鋪路），符合 CLAUDE.md「Simplicity First：不添加超出要求的功能／不做推測性設計」。

## Self-Review 記錄

- **Spec coverage**：Issue 0「What to build」五項（pubspec 依賴、`pdf_reader_view.dart` 改名、`pdf_content_indexer.dart` 改名、確認 `ReaderResourceChannel.kt` 免修改、`findBookById` 三件套）已逐一對應 Task 1-4；「驗收標準」四項（`flutter analyze` 乾淨、`flutter test` 零回歸、四個新依賴皆可 `flutter pub get`、真機驗證）已對應 Task 5。
- **Placeholder scan**：所有 Step 皆含可直接套用的實際程式碼區塊，無 TBD／「依上述類推」等佔位敘述。
- **Type consistency**：`findBookById(String id)` 回傳型別 `Future<Book?>` 在 `library_repository.dart`（介面）、`sqlite_library_repository.dart`（實作）、`fake_library_repository.dart`（假實作）三處簽章一致。
