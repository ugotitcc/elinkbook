# Epic 26 Issue 9：`Book.copyWith()` 全欄位開放為具名參數 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development（推薦）或 superpowers:executing-plans 以逐 Task 執行本計畫。步驟採用 checkbox（`- [ ]`）語法追蹤進度。

**Goal:** 把 `Book.copyWith()`（目前只開放 `groupName`／`isFixedLayout`／`filePath`／`isDownloaded` 4 個欄位為具名參數，其餘 17 個欄位在函式本體逐一手動 `fieldName: fieldName` 原樣帶入）改為 21 個欄位（除 `id` 外全部）皆為具名參數、`field: field ?? this.field` 逐一覆寫，讓「漏帶欄位、執行期靜默清空」這個已發生過真實事故（2026-08-04 漏帶 `positionSyncedServerUpdatedAt`／`positionUpdatedAt`）的 bug class 直接變成編譯期錯誤（未在新建構子參數列宣告的欄位無法遺漏，因為所有欄位都出現在同一份參數列）。

**Architecture:** 純函式簽章擴寬，不改變 `Book` 類別的欄位、`toMap()`／`fromMap()`／`operator==`／`hashCode`，也不改變任何呼叫端程式碼——單一檔案 `app/lib/library/models/book.dart` 內 `copyWith()` 方法的內部改寫。

**Tech Stack:** Flutter／Dart，無新增套件依賴。

**Spec:** `docs/epics/epic-26-architecture-hardening/issues.md` Issue 9；`docs/research/architecture-review-library-remote-screens.md` 候選 4（強度 Worth exploring，已有真實事故佐證）。

## 規劃階段查證：欄位數對帳、`id` 為何刻意排除、需要一併修正的過時文件（務必先讀）

1. **欄位數對帳（22 個欄位、21 個開放為具名參數，`id` 排除在外）。** 逐一核對現行 `app/lib/library/models/book.dart:104-127` 建構子，`Book` 目前共 22 個欄位：`id`／`title`／`author`／`format`／`filePath`／`source`／`coverPath`／`progress`／`epubLocator`／`pdfPageIndex`／`isFixedLayout`／`contentFingerprint`／`positionUpdatedAt`／`positionSyncedServerUpdatedAt`／`remoteServerId`／`remoteBookId`／`remoteDownloadUrl`／`isDownloaded`／`cloudFileId`／`groupName`／`createTime`／`lastReadTime`。Issue 原文「21 個欄位」與候選 4 原文「4/21」的計算基準一致——都是扣掉 `id` 之後的欄位總數（22 − 1 = 21），現行 4 個既有具名參數（`groupName`／`isFixedLayout`／`filePath`／`isDownloaded`）＋本計畫新開放的 17 個欄位＝21，與 Issue 原文「其餘欄位（現為 18 個，含 `id` 本身）在函式本體逐一手動原樣帶入」的說法一致（18 = 17 個待開放欄位 ＋ `id` 這 1 個永遠不開放的欄位）。
2. **`id` 刻意排除在具名參數之外，不是遺漏。** `copyWith()` 語意上是「複製同一本書、覆寫部分欄位」，不是「建立一本新書」——識別碼本來就不該被 `copyWith()` 覆寫；真的需要一本新 `id` 的書應直接呼叫 `Book(...)` 建構子。本計畫在新版 `copyWith()` 的 doc comment 中明確記載這個設計決策，避免未來被誤判為「還有一個欄位忘記開放」。
3. **`positionSyncedServerUpdatedAt` 欄位上方現行有一段（`book.dart:70-75`）明講「不開放為 `copyWith()` 的具名參數（...YAGNI）」的過時文件，必須連同 `copyWith()` 本身一併修正，否則文件會與程式碼矛盾。** 這段註解是 2026-08-04 那次真實事故修正時寫下的，描述的是「事故修正當下」的權宜決策（先確保不被靜默清空，但先不开放成主動可寫），本 Issue 正是回頭把這個當時的權宜決策正式升級為全面一致的介面設計，故該段落需要更新，不能留著自相矛盾的舊說法（見 Task 1 Step 3）。
4. **`copyWith()` 方法本身上方的 doc comment（`book.dart:190-200`）描述的是舊的「4 個具名參數＋4 個欄位刻意排除」不對稱設計，全文需要重寫。** 舊文件提到「`remoteServerId`／`remoteBookId`／`remoteDownloadUrl`／`cloudFileId` 仍不開放為具名參數」，本 Issue 之後這句話不再成立，必須同步改寫（見 Task 1 Step 3）。
5. **既有呼叫點現況已與 Issue 原文「`app/lib/screens/library_screen.dart` 等」的描述不完全一致，重新核對如下（epic-26 Issue 8 已把其中 3 個呼叫點搬到新檔案）：** `app/lib/screens/library_screen.dart:576`（`book.copyWith(filePath: permanentPath, isDownloaded: true)`）、`app/lib/screens/library_batch_actions.dart:45`（`book.copyWith(groupName: destination)`）、`app/lib/screens/library_batch_actions.dart:58`（`book.copyWith(isFixedLayout: true)`）、`app/lib/screens/library_batch_actions.dart:118`（`book.copyWith(isDownloaded: false)`）——共 4 個呼叫點，與 Issue 原文「現有 4 個呼叫點」數字一致，皆只使用既有 4 個具名參數的子集，介面擴寬後這 4 處呼叫端程式碼不需要任何修改（純粹新增可選具名參數，不影響既有呼叫語法）。
6. **新開放的 17 個欄位中，凡是可為 `null` 型別的（`author`／`coverPath`／`epubLocator`／`pdfPageIndex`／`contentFingerprint`／`positionUpdatedAt`／`positionSyncedServerUpdatedAt`／`remoteServerId`／`remoteBookId`／`remoteDownloadUrl`／`cloudFileId`），比照現行 `isFixedLayout ?? this.isFixedLayout` 既有慣例，一律用 `field ?? this.field`——這代表呼叫端目前無法透過 `copyWith()` 把一個已經有值的可為 `null` 欄位「明確改回 `null`」（傳 `null` 或不傳，效果相同，皆維持原值）。這是本專案既有的 `copyWith()` 慣例（`isFixedLayout` 現行已是如此），不是本計畫新引入的限制，也不在本 Issue 驗收範圍內另外設計「明確清空」語意（YAGNI，目前沒有任何呼叫端需要把已有值的欄位清回 `null`）。

**結論：** `copyWith()` 改為 21 個具名參數（`id` 排除），兩段過時文件（方法本身 doc comment、`positionSyncedServerUpdatedAt` 欄位上方 doc comment）一併改寫以消除與程式碼矛盾，4 個既有呼叫點與其餘所有方法（`toMap`／`fromMap`／`operator==`／`hashCode`）維持零改變。

## Global Constraints

- 程式碼註解／變數說明使用中文，遵循既有檔案風格。
- 零行為改變：既有 4 個呼叫點的呼叫語法與執行結果不變；新開放的 17 個具名參數皆為可選（nullable 型別或有預設 fallback 至 `this.field`），不傳入時行為與修改前完全一致。
- `flutter analyze` 涵蓋 `app/integration_test/`——本計畫不涉及原生渲染，預期不受影響，仍需確保能編譯通過。
- Commit message 慣例：`refactor(epic-26): Issue 9 Task N——<描述>`。

---

### Task 1：`Book.copyWith()` 21 個欄位全數開放為具名參數

**Files:**
- Modify: `app/lib/library/models/book.dart`
- Test: `app/test/library/models/book_test.dart`

**Interfaces:**
- Produces：`Book copyWith({String? title, String? author, BookFileFormat? format, String? filePath, BookSource? source, String? coverPath, double? progress, String? epubLocator, int? pdfPageIndex, bool? isFixedLayout, String? contentFingerprint, int? positionUpdatedAt, String? positionSyncedServerUpdatedAt, String? remoteServerId, String? remoteBookId, String? remoteDownloadUrl, bool? isDownloaded, String? cloudFileId, String? groupName, DateTime? createTime, DateTime? lastReadTime})`——`id` 不在參數列中，回傳的新物件 `id` 恆等於原物件 `id`。

- [x] **Step 1：寫失敗測試，驗證新開放的 17 個具名參數皆可正確覆寫，既有 4 個具名參數未傳入時維持原值**

```dart
// app/test/library/models/book_test.dart（新增於既有 main() 內任一位置，
// 建議接在既有 copyWith 相關測試群組之後）
  test(
      'copyWith() 覆寫全部新開放的具名參數（epic-26-architecture-hardening '
      'Issue 9），值正確套用，未覆寫的既有具名參數維持原值', () {
    final original = Book(
      id: 'b23',
      title: '原書名',
      author: '原作者',
      format: BookFileFormat.pdf,
      filePath: '/storage/original.pdf',
      source: BookSource.local,
      coverPath: '/storage/original_cover.png',
      progress: 0.1,
      epubLocator: 'original-locator',
      pdfPageIndex: 3,
      isFixedLayout: false,
      contentFingerprint: 'fp-original',
      positionUpdatedAt: 1000,
      positionSyncedServerUpdatedAt: '2026-01-01 00:00:00.000Z',
      remoteServerId: 'srv-original',
      remoteBookId: 'remote-original',
      remoteDownloadUrl: 'http://example.com/original.pdf',
      isDownloaded: true,
      cloudFileId: 'cloud-original',
      groupName: '原分類',
      createTime: DateTime.fromMillisecondsSinceEpoch(1000),
      lastReadTime: DateTime.fromMillisecondsSinceEpoch(2000),
    );

    final updated = original.copyWith(
      title: '新書名',
      author: '新作者',
      format: BookFileFormat.epub,
      source: BookSource.googleDrive,
      coverPath: '/storage/new_cover.png',
      progress: 0.9,
      epubLocator: 'new-locator',
      pdfPageIndex: 7,
      contentFingerprint: 'fp-new',
      positionUpdatedAt: 5000,
      positionSyncedServerUpdatedAt: '2026-08-21 00:00:00.000Z',
      remoteServerId: 'srv-new',
      remoteBookId: 'remote-new',
      remoteDownloadUrl: 'http://example.com/new.pdf',
      cloudFileId: 'cloud-new',
      createTime: DateTime.fromMillisecondsSinceEpoch(9000),
      lastReadTime: DateTime.fromMillisecondsSinceEpoch(9999),
    );

    expect(updated.id, 'b23', reason: 'id 不開放為具名參數，不可能改變');
    expect(updated.title, '新書名');
    expect(updated.author, '新作者');
    expect(updated.format, BookFileFormat.epub);
    expect(updated.source, BookSource.googleDrive);
    expect(updated.coverPath, '/storage/new_cover.png');
    expect(updated.progress, 0.9);
    expect(updated.epubLocator, 'new-locator');
    expect(updated.pdfPageIndex, 7);
    expect(updated.contentFingerprint, 'fp-new');
    expect(updated.positionUpdatedAt, 5000);
    expect(updated.positionSyncedServerUpdatedAt, '2026-08-21 00:00:00.000Z');
    expect(updated.remoteServerId, 'srv-new');
    expect(updated.remoteBookId, 'remote-new');
    expect(updated.remoteDownloadUrl, 'http://example.com/new.pdf');
    expect(updated.cloudFileId, 'cloud-new');
    expect(updated.createTime, DateTime.fromMillisecondsSinceEpoch(9000));
    expect(updated.lastReadTime, DateTime.fromMillisecondsSinceEpoch(9999));

    // 既有 4 個具名參數本次未傳入，維持原值——證明新開放的 17 個參數不影響
    // 既有行為。
    expect(updated.filePath, '/storage/original.pdf');
    expect(updated.isFixedLayout, isFalse);
    expect(updated.isDownloaded, isTrue);
    expect(updated.groupName, '原分類');
  });
```

- [x] **Step 2：執行測試確認失敗（新參數尚未存在，編譯失敗）**

執行：`cd app && flutter test test/library/models/book_test.dart`
預期：`FAIL`，錯誤訊息為 `copyWith` 找不到 `title`（或其他新參數）這個具名參數（`no_matching_named_parameter` 之類的編譯期錯誤，而非執行期測試失敗——這正是本 Issue 要達成的「遺漏欄位變成編譯期錯誤」效果的直接證明）。

- [x] **Step 3：實作新版 `copyWith()`，並改寫上方兩段過時 doc comment**

修改 `app/lib/library/models/book.dart`，`positionSyncedServerUpdatedAt` 欄位上方原本（`book.dart:65-76`）：

```dart
  /// 快取上次成功同步時，PocketBase `sync_reading_positions` 該筆紀錄的
  /// 伺服器時間戳記字串（epic-8-sync Issue 5，spec.md「本機 Schema
  /// 變更」）：供同步引擎偵測「其他裝置是否在此之後又推送過」用——與
  /// 本機快取值不同即代表衝突。`null` 代表這本書的閱讀位置從未成功同步
  /// 過。
  /// **不開放為 `copyWith()` 的具名參數**（本 Issue 對這兩個欄位的所有
  /// 寫入皆透過 partial update 完成，沒有呼叫端需要透過 `copyWith()`
  /// 修改，YAGNI）——但仍會原樣帶入 `copyWith()` 回傳的新物件，不能
  /// 讓 `copyWith()` 把這兩個欄位清空（2026-08-04 最終全分支審查修正：
  /// 原本沒有帶入，會被任何呼叫 `copyWith()` 的地方靜默清成 null，見
  /// `sqlite_library_repository.dart` 的 `updateBook()` 呼叫端）。
  final String? positionSyncedServerUpdatedAt;
```

改為：

```dart
  /// 快取上次成功同步時，PocketBase `sync_reading_positions` 該筆紀錄的
  /// 伺服器時間戳記字串（epic-8-sync Issue 5，spec.md「本機 Schema
  /// 變更」）：供同步引擎偵測「其他裝置是否在此之後又推送過」用——與
  /// 本機快取值不同即代表衝突。`null` 代表這本書的閱讀位置從未成功同步
  /// 過。與 [positionUpdatedAt] 目前的主要寫入路徑仍是
  /// `ReadingPositionRepository.save()` 的 partial update，但
  /// `copyWith()` 自 epic-26-architecture-hardening Issue 9 起已開放為
  /// 具名參數（原本刻意不開放，2026-08-04 曾因未帶入原樣值而被任何呼叫
  /// `copyWith()` 的地方靜默清成 `null`，見 `sqlite_library_repository.
  /// dart` 的 `updateBook()` 呼叫端），不傳入時仍維持原值不被清空。
  final String? positionSyncedServerUpdatedAt;
```

`copyWith()` 方法本身，原本（`book.dart:190-231`）：

```dart
  /// 回傳欄位值與自身相同的新物件，僅覆寫明確傳入的參數。[groupName] 供
  /// Issue 10 的批次分類異動使用；[isFixedLayout] 供本 Issue 的 EPUB 版面
  /// 判斷/回填流程使用；[filePath]／[isDownloaded] 供
  /// epic-30-calibre-remote-library Issue 4 的「移除本機快取」（僅傳
  /// `isDownloaded: false`）／「重新下載」（`filePath` 與
  /// `isDownloaded: true` 一併傳入）使用——Issue 0 當時刻意不開放這兩個
  /// 欄位為具名參數（YAGNI，當時沒有呼叫端需要真的異動它們），本 Issue
  /// 是第一個需要的呼叫端。
  /// **⚠️ `remoteServerId`／`remoteBookId`／`remoteDownloadUrl`／
  /// `cloudFileId` 仍不開放為具名參數（目前沒有呼叫端需要異動這幾個
  /// 欄位），但必須原樣帶入新物件以避免靜默清空**。
  Book copyWith({
    String? groupName,
    bool? isFixedLayout,
    String? filePath,
    bool? isDownloaded,
  }) {
    return Book(
      id: id,
      title: title,
      author: author,
      format: format,
      filePath: filePath ?? this.filePath,
      source: source,
      coverPath: coverPath,
      progress: progress,
      epubLocator: epubLocator,
      pdfPageIndex: pdfPageIndex,
      contentFingerprint: contentFingerprint,
      positionUpdatedAt: positionUpdatedAt,
      positionSyncedServerUpdatedAt: positionSyncedServerUpdatedAt,
      remoteServerId: remoteServerId,
      remoteBookId: remoteBookId,
      remoteDownloadUrl: remoteDownloadUrl,
      isDownloaded: isDownloaded ?? this.isDownloaded,
      cloudFileId: cloudFileId,
      isFixedLayout: isFixedLayout ?? this.isFixedLayout,
      groupName: groupName ?? this.groupName,
      createTime: createTime,
      lastReadTime: lastReadTime,
    );
  }
```

改為：

```dart
  /// 回傳欄位值與自身相同的新物件，可覆寫除 [id] 外的全部 21 個欄位
  /// （epic-26-architecture-hardening Issue 9）。[id] 刻意不開放為具名
  /// 參數——`copyWith()` 語意上是「複製同一本書、覆寫部分欄位」，不是
  /// 「建立一本新書」，識別碼不應該被覆寫；真的需要一本新 [id] 的書，
  /// 應直接呼叫 [Book] 建構子。可為 `null` 型別的欄位（例如
  /// [contentFingerprint]／[cloudFileId]）比照既有 [isFixedLayout] 慣例，
  /// 不傳入時維持原值、無法透過本方法明確清空為 `null`（YAGNI，目前沒有
  /// 呼叫端需要這個語意）。
  ///
  /// 【epic-26-architecture-hardening Issue 9 前情提要，避免未來重演】
  /// 本方法原本只開放 4 個欄位（[groupName]／[isFixedLayout]／[filePath]／
  /// [isDownloaded]）為具名參數，其餘欄位在函式本體逐一手動
  /// `fieldName: fieldName` 原樣帶入——寫漏一個不會編譯錯誤，只會在執行期
  /// 靜默清空該欄位；2026-08-04 曾因此漏帶 [positionSyncedServerUpdatedAt]／
  /// [positionUpdatedAt]，任何呼叫 `copyWith()` 的批次操作（例如
  /// `LibraryBatchActions`）都會靜默清空同步進度資料，直到審查才發現修正
  /// （詳見 `docs/research/architecture-review-library-remote-screens.md`
  /// 候選 4）。全欄位開放為具名參數後，遺漏欄位會直接編譯失敗，這個
  /// bug class 不會再發生。
  Book copyWith({
    String? title,
    String? author,
    BookFileFormat? format,
    String? filePath,
    BookSource? source,
    String? coverPath,
    double? progress,
    String? epubLocator,
    int? pdfPageIndex,
    bool? isFixedLayout,
    String? contentFingerprint,
    int? positionUpdatedAt,
    String? positionSyncedServerUpdatedAt,
    String? remoteServerId,
    String? remoteBookId,
    String? remoteDownloadUrl,
    bool? isDownloaded,
    String? cloudFileId,
    String? groupName,
    DateTime? createTime,
    DateTime? lastReadTime,
  }) {
    return Book(
      id: id,
      title: title ?? this.title,
      author: author ?? this.author,
      format: format ?? this.format,
      filePath: filePath ?? this.filePath,
      source: source ?? this.source,
      coverPath: coverPath ?? this.coverPath,
      progress: progress ?? this.progress,
      epubLocator: epubLocator ?? this.epubLocator,
      pdfPageIndex: pdfPageIndex ?? this.pdfPageIndex,
      isFixedLayout: isFixedLayout ?? this.isFixedLayout,
      contentFingerprint: contentFingerprint ?? this.contentFingerprint,
      positionUpdatedAt: positionUpdatedAt ?? this.positionUpdatedAt,
      positionSyncedServerUpdatedAt:
          positionSyncedServerUpdatedAt ?? this.positionSyncedServerUpdatedAt,
      remoteServerId: remoteServerId ?? this.remoteServerId,
      remoteBookId: remoteBookId ?? this.remoteBookId,
      remoteDownloadUrl: remoteDownloadUrl ?? this.remoteDownloadUrl,
      isDownloaded: isDownloaded ?? this.isDownloaded,
      cloudFileId: cloudFileId ?? this.cloudFileId,
      groupName: groupName ?? this.groupName,
      createTime: createTime ?? this.createTime,
      lastReadTime: lastReadTime ?? this.lastReadTime,
    );
  }
```

- [x] **Step 4：執行測試確認 Step 1 新增的測試通過**

執行：`cd app && flutter test test/library/models/book_test.dart`
預期：`PASS`（含 Step 1 新增的測試）。

- [x] **Step 5：修正一處因本次改動而變得過時的既有測試標題（`cloudFileId` 已開放為具名參數，測試斷言本身不變，只有標題描述的前提不再成立）**

修改 `app/test/library/models/book_test.dart`，原本：

```dart
  test('copyWith 保留 cloudFileId（欄位未開放為具名參數，但不可被 copyWith 清空）', () {
```

改為：

```dart
  test(
      'copyWith() 不傳入 cloudFileId 時維持原值（epic-26-architecture-hardening '
      'Issue 9 已開放為具名參數，沿用既有「不傳入即維持原值」慣例，不可被'
      '靜默清空）', () {
```

（測試本體其餘程式碼不動——`book.copyWith(groupName: '新分類')` 呼叫本身沒有傳入 `cloudFileId`，斷言 `copied.cloudFileId` 等於原值的邏輯在新版 `copyWith()` 下依然成立，只是標題原本聲稱「未開放為具名參數」這個前提在本 Task 完成後不再是事實，故只改標題文字，不改測試邏輯。）

- [x] **Step 6：執行整個 `book_test.dart` 確認全數通過**

執行：`cd app && flutter test test/library/models/book_test.dart`
預期：`PASS`（全部既有案例＋ Step 1 新增案例，零回歸）。

- [x] **Step 7：Commit**

```bash
git add app/lib/library/models/book.dart app/test/library/models/book_test.dart
git commit -m "refactor(epic-26): Issue 9 Task 1——Book.copyWith() 21 個欄位全數開放為具名參數"
```

---

### Task 2：全專案最終驗證

**Files:**
- 無新增/修改檔案，純驗證。

- [x] **Step 1：全域殘留掃描，確認 4 個既有呼叫點未被意外修改**

執行：

```bash
cd app
grep -n "book.copyWith(" lib/screens/library_screen.dart lib/screens/library_batch_actions.dart
```

預期：輸出恰好 4 行，分別對應
`library_screen.dart:576`（`filePath: permanentPath, isDownloaded: true`）、
`library_batch_actions.dart:45`（`groupName: destination`）、
`library_batch_actions.dart:58`（`isFixedLayout: true`）、
`library_batch_actions.dart:118`（`isDownloaded: false`）——
與 base commit（本 Task 開始前）逐行比對完全一致，證明介面擴寬未波及任何既有呼叫端程式碼（比照 `review-issue-7.md`／`review-issue-8.md` 的既有教訓，任何「內部/介面調整」類型的計畫都必須明確驗證所有既有呼叫點未被意外波及）。

- [x] **Step 2：執行 `flutter analyze`**

執行：`cd app && flutter analyze`
預期：`No issues found!`

- [x] **Step 3：執行全專案測試**

執行：`cd app && flutter test`
預期：全數通過，零回歸（相較 Issue 8 合併後的基準數字 1628，本 Issue Task 1 新增 1 項 `copyWith()` 全欄位覆寫測試，其餘為既有 `book_test.dart` 案例的逐字保留或僅標題文字調整，總數應為「1628 + 1」）。

- [x] **Step 4：逐項核對驗收標準**

- [x] `Book.copyWith()` 21 個欄位（除 `id` 外全部）全數開放為具名參數。
- [x] 既有 4 個呼叫點（`library_screen.dart`／`library_batch_actions.dart` 三處）行為零改變，程式碼零修改。
- [x] `positionSyncedServerUpdatedAt` 欄位上方與 `copyWith()` 方法本身的過時 doc comment 皆已同步更新，不再與程式碼矛盾。
- [x] `flutter analyze` 乾淨、`flutter test` 全數通過。

- [x] **Step 5：Commit（若 Step 1-4 有任何微調）**

```bash
git add -A
git commit -m "refactor(epic-26): Issue 9 Task 2——最終驗證：殘留掃描、flutter analyze 乾淨、全數測試通過"
```

（若 Step 1-4 皆一次到位無需任何修改，本 Task 可以不產生新 commit，直接在審查報告中記錄驗證結果。）
