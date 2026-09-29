# Epic 15 Issue 3：字型管理標示讀不到的自訂字型，並可重新連結 — 實作計畫

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 使用者進入字型管理時，讀不到檔案的自訂字型會標示「檔案無法讀取」並提供「重新連結字型檔案」；選到同一款字型（家族名稱相同）後原地更新 URI，所有使用這款字型的書自動恢復。

**Architecture:**
- `CustomFontsRepository` 新增 `updateUri(id, fontUri)`（單一 UPDATE）。
- `FontManagementScreen` 在清單載入後，對「尚未探測過」的自訂字型各自非同步呼叫 `probeStorageAccess`（Issue 1 已完成的可覆寫頂層函式），結果存進「字型 id → 探測結果」對應表；不是 `readable` 的字型在該列顯示文字標籤與外框按鈕。
- 重新連結流程：可注入的單檔選擇器 → 解析家族名稱比對 → 持久化授權（盡力而為）→ `updateUri` → 該字型探測狀態改為 `readable`。閱讀器內的字型行為完全不動。

**Tech Stack:** Flutter／Dart 3（record、pattern matching）、`file_picker`、`sqflite_common_ffi`（repository 測試）、`flutter_test`、`flutter gen-l10n`（ARB）。

**Spec:** [`../spec.md`](../spec.md)（「自訂字型的失效標示與重新連結」「介面文案與在地化」兩段）、[`../issues.md`](../issues.md) Issue 3

## Global Constraints

- 簽章與型別逐字照 spec／issues：

  ```dart
  // CustomFontsRepository 新增
  Future<void> updateUri(int id, String fontUri);

  // font_management_screen.dart 新增
  typedef SingleFontFilePicker =
      Future<({String uri, String name, Uint8List bytes})?> Function();
  ```

- 探測狀態以**字型資料庫主鍵**為 key（`Map<int, StorageAccessProbeResult>`），不使用清單索引。
- 每筆探測結果寫入狀態前，先確認 `mounted`，而且該 id 仍在 `_customFonts` 中；不在就捨棄。
- 探測在清單載入後非同步進行，不阻塞清單顯示；同一個 id 只探測一次（清單因改名、上傳、刪除重新載入時，不重複探測）。
- 標示條件：探測結果不是 `readable`（含 `unknownError`）。標示是**文字標籤**，不能只靠顏色。
- Widget Key：標籤 `Key('font_management_inaccessible_badge_${font.id}')`、動作 `Key('font_management_relink_button_${font.id}')`。處理中的進度指示器 Key：`Key('font_management_relink_progress_${font.id}')`。動作按鈕用 `OutlinedButton`（E-Ink 高對比模式下要有明確外框）。
- 重新連結順序固定：選檔（取消回傳 null → 什麼都不做，不顯示 SnackBar）→ 家族名稱比對（不同就以 SnackBar 拒絕，不持久化授權、不改記錄）→ 持久化授權（`PlatformException` 吞掉，比照 ADR 0021）→ `updateUri` → 探測狀態設為 `readable`。
- 家族名稱解析規則與既有上傳流程一致：`parseFontFamilyName(bytes) ?? _stripExtension(name)`。
- 處理期間停用該列的動作（重新連結、重新命名、刪除），在 `finally` 區段恢復。
- 既有的「上傳字型」批次選取流程不動；閱讀器內的字型行為不動；可下載字型不探測。
- 在地化：新增 `fontManagementFileInaccessibleBadge`、`fontManagementRelinkAction`、`fontManagementFamilyMismatchMessage` 三個 key。四份 ARB 都要補：
  - `app_zh_TW.arb`：範本，含 `@key` 說明。
  - `app_zh.arb`：中文退路，內容同正體中文。
  - `app_zh_CN.arb`、`app_en.arb`。

  改完執行 `flutter gen-l10n`，生成的 `app_localizations*.dart` 已納入版控，要一起提交。
- 視覺沿用既有 `ElinkTokens`，不新增 token。
- 程式碼註解使用正體中文，並標註 `epic-15-storage-permission Issue 3`。
- 每個 Task 只跑觸及的測試檔；最後一個 Task 跑一次完整 `flutter test`。`flutter analyze` 必須是 `No issues found!`。
- 所有指令都在 `app/` 目錄下執行（除非另外註明）。

## Review Focus

spec 沒有明講、但使用者最可能碰到的五種情況，依發生機率排序：

1. **探測進行中，使用者刪除某個字型**：探測結果回來時該 id 已不在清單，不可錯位到別列、不可拋例外。由 Task 2 的「探測未完成時刪除字型」測試釘住。
2. **改名、上傳後清單重新載入**：`_loadFonts` 每次都會被呼叫，若每次都重新探測全部字型，會反覆打原生，也可能用舊結果蓋掉剛重新連結成功的 `readable`。同一個 id 只探測一次。由 Task 2 的「改名後不重複探測」測試釘住。
3. **重新連結處理中快速連點**：選擇器開著、或 `updateUri` 進行中，第二次點擊不可再開選擇器。由 Task 2 的「處理中停用並只開一次選擇器」測試釘住。
4. **取消選檔，或持久化授權失敗**：取消時按鈕要恢復、沒有 SnackBar；授權失敗（部分文件提供者不核發可持久化授權）不可中止更新。由 Task 2 的「取消」與「授權失敗仍更新」測試釘住。
5. **探測回來時已離開畫面**：`mounted` 檢查。由 Task 2 的「離開畫面後探測回來不拋例外」測試釘住。

另外記一個刻意沿用 spec 的取捨：`unknownError`（包含 3 秒逾時）也會顯示標示，因為 spec 明訂「結果不是 `readable`」。逾時的健康字型會被誤標，使用者按下重新連結、選同一個檔案後即可消除；若真機回報誤標太頻繁，再另立工單調整。

## 計畫審查修訂（2026-09-29，`reviews/review-plan-issue-3.md`，0 Critical／0 Important／6 Minor）

- **M-1 不採納**：審查建議選擇器在 `identifier` 為 null 時改用 `file.path`。在 Android 上，`file_picker` 的 `path` 指向它複製到 App 快取目錄的暫存檔，系統清快取後就會消失；寫進 `custom_fonts.font_uri` 的話，這款字型很快又讀不到，正好違背本功能的目的（與 Issue 2 計畫審查 M-3 同一理由）。此外閱讀器讀字型的 `readCustomFontBytes` 只認 `content://` URI，本機路徑根本讀不到。專案既有的批次上傳也只用 `identifier`，維持原寫法：`identifier` 為 null 視為取消。
- **M-2 採納**：`_relinkFont` 在選擇器回傳後加 `!mounted` 檢查，避免使用者選檔期間離開畫面時仍持久化授權、寫資料庫。新增 widget test「選檔期間離開畫面」把這個行為固定住（新增案例 11 → 12 個）。
- **M-3 採納**：新測試 group 內以 `pumpTall` 統一加高視窗（2400×6000），取代直接呼叫 `pumpScreen`，避免長清單後面幾列沒有被建出而偶發失敗。既有測試不動。
- **M-4 採納**：「改名」測試改用 `insertFont` 回傳的 id 組 Key，不再寫死 `_1`。
- **M-5 不採納**：審查建議 `_deleteFont` 成功後清除 `_probeResults`／`_probeRequestedIds` 的對應 id。字型 id 是 `AUTOINCREMENT`，不會被重用，殘留的 id 不會誤套到別的字型；探測結果回來時又已有「id 仍在清單中」的守衛。多改既有的 `_deleteFont` 只換來幾個 int 的記憶體，且違反「只改本 Issue 必須改的地方」。
- **M-6 採納**：「處理中」測試補上重新命名按鈕 `onPressed` 為 null 的斷言。

## File Structure

| 檔案 | 動作 | 責任 |
|---|---|---|
| `app/lib/reader/custom_fonts_repository.dart` | Modify | 新增 `updateUri` |
| `app/test/support/fake_custom_fonts_repository.dart` | Modify | 測試替身同步實作 `updateUri` |
| `app/test/reader/custom_fonts_repository_test.dart` | Modify | `updateUri` 只改 URI 的測試 |
| `app/lib/screens/font_management_screen.dart` | Modify | `SingleFontFilePicker`＋預設實作、探測狀態、失效標示、重新連結流程 |
| `app/test/screens/font_management_screen_test.dart` | Modify | 探測與重新連結的 widget test |
| `app/lib/l10n/app_zh_TW.arb`、`app_zh.arb`、`app_zh_CN.arb`、`app_en.arb` | Modify | 三個新 key |
| `app/lib/l10n/app_localizations*.dart` | Regenerate | `flutter gen-l10n` 產物 |

---

### Task 0：建立工作分支（worktree）

- [ ] **Step 1：建立 worktree**

在儲存庫根目錄執行：

```bash
git worktree add .worktrees/epic-15-issue-3 -b epic-15/issue-3 main
```

之後所有 Task 都在 `.worktrees/epic-15-issue-3` 內進行（指令在其下的 `app/` 目錄執行）。

---

### Task 1：`CustomFontsRepository.updateUri`（資料層＋測試替身）

**Files:**
- Modify: `app/lib/reader/custom_fonts_repository.dart`
- Modify: `app/test/support/fake_custom_fonts_repository.dart`
- Test: `app/test/reader/custom_fonts_repository_test.dart`

**Interfaces:**
- Consumes: 無。
- Produces: `Future<void> updateUri(int id, String fontUri)`（真實與 Fake 兩個實作），Task 2 的畫面呼叫它。

- [ ] **Step 1：寫失敗的測試**

在 `custom_fonts_repository_test.dart` 的 `group('CustomFontsRepository', ...)` 內、既有 `rename` 相關測試之後新增：

```dart
    test('updateUri 只更新指定字型的 URI，顯示名稱與家族名稱不變，其他字型不受影響', () async {
      final targetId = await repository.insert(const CustomFont(
        displayName: '目標字型',
        familyName: 'TargetFamily',
        fontUri: 'content://old/target',
      ));
      await repository.insert(const CustomFont(
        displayName: '其他字型',
        familyName: 'OtherFamily',
        fontUri: 'content://old/other',
      ));

      await repository.updateUri(targetId, 'content://new/target');

      final all = await repository.listAll();
      final target = all.firstWhere((f) => f.id == targetId);
      expect(target.fontUri, 'content://new/target');
      expect(target.displayName, '目標字型');
      expect(target.familyName, 'TargetFamily');
      final other = all.firstWhere((f) => f.id != targetId);
      expect(other.fontUri, 'content://old/other');
    });
```

- [ ] **Step 2：確認測試失敗**

Run: `flutter test test/reader/custom_fonts_repository_test.dart --plain-name "updateUri"`
Expected: 編譯失敗，`The method 'updateUri' isn't defined for the class 'CustomFontsRepository'`。

- [ ] **Step 3：實作 `updateUri` 與 Fake**

`custom_fonts_repository.dart`，在 `rename` 之後新增：

```dart
  /// 只更新該字型的 `font_uri`（epic-15-storage-permission Issue 3：字型檔案
  /// 授權失效後重新連結）。單一 UPDATE 敘述，不需要交易；顯示名稱、家族名稱
  /// 都不動，所以以家族名稱引用這款字型的書籍偏好不需要遷移。
  Future<void> updateUri(int id, String fontUri) {
    return _db.update(
      'custom_fonts',
      {'font_uri': fontUri},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
```

`fake_custom_fonts_repository.dart`，在 `rename` 之後新增：

```dart
  @override
  Future<void> updateUri(int id, String fontUri) async {
    final index = _storage.indexWhere((f) => f.id == id);
    if (index == -1) return;
    final old = _storage[index];
    _storage[index] = CustomFont(
      id: old.id,
      displayName: old.displayName,
      familyName: old.familyName,
      fontUri: fontUri,
    );
  }
```

- [ ] **Step 4：確認測試通過**

Run: `flutter test test/reader/custom_fonts_repository_test.dart`
Expected: All tests passed。

Run: `flutter analyze`
Expected: `No issues found!`（其他實作 `CustomFontsRepository` 的替身若有，會在此報缺 `updateUri`；先用 `grep -rn "implements CustomFontsRepository" test lib` 確認只有 `FakeCustomFontsRepository`）。

- [ ] **Step 5：Commit**

```bash
git add lib/reader/custom_fonts_repository.dart test/support/fake_custom_fonts_repository.dart test/reader/custom_fonts_repository_test.dart
git commit -m "feat(fonts): CustomFontsRepository 新增 updateUri（epic-15 Issue 3）"
```

---

### Task 2：字型管理畫面的失效標示與重新連結（含在地化）

**Files:**
- Modify: `app/lib/l10n/app_zh_TW.arb`、`app_zh.arb`、`app_zh_CN.arb`、`app_en.arb`（並重新產生 `app_localizations*.dart`）
- Modify: `app/lib/screens/font_management_screen.dart`
- Test: `app/test/screens/font_management_screen_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `CustomFontsRepository.updateUri(int id, String fontUri)`；Issue 1 的 `probeStorageAccess` 與 `StorageAccessProbeResult`（`lib/reader/foliate_native_bridge.dart`）；既有 `parseFontFamilyName`、`kBookMetadataChannel`。
- Produces: `SingleFontFilePicker` typedef、`pickSingleFontFileViaFilePicker` 預設實作、`FontManagementScreen` 新選用參數 `pickSingleFontFile`。

- [ ] **Step 1：新增 ARB 字串並產生程式碼**

`app_zh_TW.arb`：在 `fontManagementUploadSkippedOnlyMessage` 區塊（`"@fontManagementUploadSkippedOnlyMessage": {...},`）之後、`"readerConsoleLogTitle"` 之前插入：

```json
  "fontManagementFileInaccessibleBadge": "檔案無法讀取",
  "@fontManagementFileInaccessibleBadge": {
    "description": "epic-15 Issue 3：字型管理中，自訂字型檔案讀不到時，列上顯示的文字標籤"
  },
  "fontManagementRelinkAction": "重新連結字型檔案",
  "@fontManagementRelinkAction": {
    "description": "epic-15 Issue 3：字型管理中，檔案讀不到的自訂字型列上的重新連結按鈕文字"
  },
  "fontManagementFamilyMismatchMessage": "選取的字型與原字型的家族名稱不同",
  "@fontManagementFamilyMismatchMessage": {
    "description": "epic-15 Issue 3：重新連結時，選取的字型家族名稱與原字型不同而被拒絕的 SnackBar"
  },
```

`app_zh.arb`（內容同正體中文）、`app_zh_CN.arb`、`app_en.arb`：在各檔 `"fontManagementUploadSkippedOnlyMessage": ...` 那一行之後插入（這三個檔案沒有 `@key` 區塊）：

```json
  "fontManagementFileInaccessibleBadge": "檔案無法讀取",
  "fontManagementRelinkAction": "重新連結字型檔案",
  "fontManagementFamilyMismatchMessage": "選取的字型與原字型的家族名稱不同",
```

`app_zh_CN.arb` 用：

```json
  "fontManagementFileInaccessibleBadge": "文件无法读取",
  "fontManagementRelinkAction": "重新链接字体文件",
  "fontManagementFamilyMismatchMessage": "所选字体与原字体的家族名称不同",
```

`app_en.arb` 用：

```json
  "fontManagementFileInaccessibleBadge": "File unreadable",
  "fontManagementRelinkAction": "Relink font file",
  "fontManagementFamilyMismatchMessage": "The selected font's family name doesn't match the original font",
```

Run: `flutter gen-l10n`
Expected: 沒有錯誤；`lib/l10n/app_localizations*.dart` 出現三個新 getter。

- [ ] **Step 2：寫失敗的測試**

在 `font_management_screen_test.dart`：

(a) 新增 import（與既有 import 並列）：

```dart
import 'package:flutter/services.dart';
import 'package:elinkbook/library/library_repository.dart' show kBookMetadataChannel;
import 'package:elinkbook/reader/foliate_native_bridge.dart'
    show ProbeStorageAccess, StorageAccessProbeResult, probeStorageAccess;
```

(b) `main()` 開頭，把既有的 `late FakeCustomFontsRepository repository;` 與 `setUp` 換成：

```dart
  late FakeCustomFontsRepository repository;
  // epic-15 Issue 3：假的存取探測與授權持久化（預設一律 readable）
  late ProbeStorageAccess originalProbe;
  late Map<String, StorageAccessProbeResult> probeByUri;
  late List<String> probedUris;
  late List<String> persistedUris;
  // 真實字型檔（家族名稱為 KingHwa_OldSong），供重新連結測試解析家族名稱
  final sampleFontBytes = File('test/fixtures/sample.ttf').readAsBytesSync();

  setUp(() {
    repository = FakeCustomFontsRepository();
    originalProbe = probeStorageAccess;
    probeByUri = {};
    probedUris = [];
    persistedUris = [];
    probeStorageAccess = (uri) async {
      probedUris.add(uri);
      return probeByUri[uri] ?? StorageAccessProbeResult.readable;
    };
  });

  tearDown(() {
    probeStorageAccess = originalProbe;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(kBookMetadataChannel, null);
  });

  /// 攔截 `takePersistableUriPermission`，記錄收到的 URI；[throws] 時模擬
  /// 文件提供者不核發可持久化授權。
  void mockPersistPermission({bool throws = false}) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(kBookMetadataChannel, (call) async {
      if (call.method == 'takePersistableUriPermission') {
        persistedUris.add((call.arguments as Map)['uri'] as String);
        if (throws) throw PlatformException(code: 'denied');
      }
      return null;
    });
  }
```

(c) 既有 `pumpScreen` 新增選用參數並轉交：

```dart
  Future<void> pumpScreen(WidgetTester tester,
      {Locale locale = const Locale('zh', 'TW'),
      DownloadableFontStore? store,
      SingleFontFilePicker? pickSingleFontFile}) async {
    await tester.pumpWidget(MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: FontManagementScreen(
          repository: repository,
          downloadableFontStore: store,
          pickSingleFontFile: pickSingleFontFile),
    ));
    await tester.pumpAndSettle();
  }
```

(d) 在 `main()` 結尾前新增 group：

```dart
  group('儲存權限失效標示與重新連結（epic-15 Issue 3）', () {
    Finder badge(int id) =>
        find.byKey(Key('font_management_inaccessible_badge_$id'));
    Finder relink(int id) =>
        find.byKey(Key('font_management_relink_button_$id'));

    Future<int> insertFont(String name, String family, String uri) =>
        repository.insert(CustomFont(
            displayName: name, familyName: family, fontUri: uri));

    /// 預設 800×600 放不下 5 列內建字型＋帶副標題與按鈕的自訂字型列，
    /// ListView 不會建出後面幾列；本 group 統一加高視窗（比照既有
    /// 「5 款內建字型依序列出」測試的作法）。
    Future<void> pumpTall(WidgetTester tester,
        {Locale locale = const Locale('zh', 'TW'),
        SingleFontFilePicker? pickSingleFontFile}) {
      tester.view.physicalSize = const Size(2400, 6000);
      addTearDown(tester.view.resetPhysicalSize);
      return pumpScreen(tester,
          locale: locale, pickSingleFontFile: pickSingleFontFile);
    }

    testWidgets('只有探測結果不是 readable 的字型顯示標示與重新連結動作', (tester) async {
      final okId = await insertFont('A 正常', 'FamA', 'content://x/a');
      final revokedId = await insertFont('B 失效', 'FamB', 'content://x/b');
      final missingId = await insertFont('C 遺失', 'FamC', 'content://x/c');
      final unknownId = await insertFont('D 未知', 'FamD', 'content://x/d');
      probeByUri['content://x/b'] = StorageAccessProbeResult.permissionRevoked;
      probeByUri['content://x/c'] = StorageAccessProbeResult.fileNotFound;
      probeByUri['content://x/d'] = StorageAccessProbeResult.unknownError;

      await pumpTall(tester);

      expect(badge(okId), findsNothing);
      expect(relink(okId), findsNothing);
      for (final id in [revokedId, missingId, unknownId]) {
        expect(badge(id), findsOneWidget);
        expect(relink(id), findsOneWidget);
      }
      expect(find.text('檔案無法讀取'), findsNWidgets(3));
      expect(find.text('重新連結字型檔案'), findsNWidgets(3));
    });

    testWidgets('探測不阻塞清單顯示：探測完成前先顯示清單，完成後才出現標示', (tester) async {
      final gate = Completer<StorageAccessProbeResult>();
      probeStorageAccess = (uri) => gate.future;
      final id = await insertFont('慢探測字型', 'SlowFam', 'content://x/slow');

      await pumpTall(tester);

      expect(find.text('慢探測字型'), findsOneWidget);
      expect(badge(id), findsNothing);

      gate.complete(StorageAccessProbeResult.permissionRevoked);
      await tester.pumpAndSettle();

      expect(badge(id), findsOneWidget);
    });

    testWidgets('重新連結成功：選到同家族字型後 URI 已更新、標示消失、授權已持久化', (tester) async {
      mockPersistPermission();
      final id = await insertFont('舊字型', 'KingHwa_OldSong', 'content://old/font');
      probeByUri['content://old/font'] =
          StorageAccessProbeResult.permissionRevoked;
      await pumpTall(
        tester,
        pickSingleFontFile: () async =>
            (uri: 'content://new/font', name: 'KingHwa.ttf', bytes: sampleFontBytes),
      );
      expect(badge(id), findsOneWidget);

      await tester.tap(relink(id));
      await tester.pumpAndSettle();

      final font = (await repository.listAll()).single;
      expect(font.fontUri, 'content://new/font');
      expect(font.displayName, '舊字型');
      expect(font.familyName, 'KingHwa_OldSong');
      expect(persistedUris, ['content://new/font']);
      expect(badge(id), findsNothing);
      expect(relink(id), findsNothing);
    });

    testWidgets('持久化授權失敗不中止：仍然更新 URI（比照 ADR 0021）', (tester) async {
      mockPersistPermission(throws: true);
      final id = await insertFont('舊字型', 'KingHwa_OldSong', 'content://old/font');
      probeByUri['content://old/font'] = StorageAccessProbeResult.fileNotFound;
      await pumpTall(
        tester,
        pickSingleFontFile: () async =>
            (uri: 'content://new/font', name: 'KingHwa.ttf', bytes: sampleFontBytes),
      );

      await tester.tap(relink(id));
      await tester.pumpAndSettle();

      expect((await repository.listAll()).single.fontUri, 'content://new/font');
      expect(badge(id), findsNothing);
    });

    testWidgets('選到不同家族的字型：SnackBar 拒絕、記錄不變、不持久化授權、標示仍在', (tester) async {
      mockPersistPermission();
      final id = await insertFont('舊字型', 'KingHwa_OldSong', 'content://old/font');
      probeByUri['content://old/font'] =
          StorageAccessProbeResult.permissionRevoked;
      await pumpTall(
        tester,
        // 只有 3 個位元組，解析不出家族名稱，退回檔名「OtherFamily」，與原字型不同
        pickSingleFontFile: () async => (
          uri: 'content://new/other',
          name: 'OtherFamily.ttf',
          bytes: sampleFontBytes.sublist(0, 3),
        ),
      );

      await tester.tap(relink(id));
      await tester.pumpAndSettle();

      expect(find.text('選取的字型與原字型的家族名稱不同'), findsOneWidget);
      expect((await repository.listAll()).single.fontUri, 'content://old/font');
      expect(persistedUris, isEmpty);
      expect(badge(id), findsOneWidget);
    });

    testWidgets('選擇器取消：沒有任何變化、沒有 SnackBar、按鈕恢復可用', (tester) async {
      mockPersistPermission();
      final id = await insertFont('舊字型', 'KingHwa_OldSong', 'content://old/font');
      probeByUri['content://old/font'] =
          StorageAccessProbeResult.permissionRevoked;
      await pumpTall(tester, pickSingleFontFile: () async => null);

      await tester.tap(relink(id));
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsNothing);
      expect((await repository.listAll()).single.fontUri, 'content://old/font');
      expect(persistedUris, isEmpty);
      expect(badge(id), findsOneWidget);
      expect(tester.widget<OutlinedButton>(relink(id)).onPressed, isNotNull);
    });

    testWidgets('處理中：該列動作停用並顯示進度，連點只開一次選擇器，結束後恢復', (tester) async {
      final gate = Completer<void>();
      var pickCalls = 0;
      final id = await insertFont('舊字型', 'KingHwa_OldSong', 'content://old/font');
      probeByUri['content://old/font'] =
          StorageAccessProbeResult.permissionRevoked;
      await pumpTall(tester, pickSingleFontFile: () async {
        pickCalls++;
        await gate.future;
        return null;
      });

      await tester.tap(relink(id));
      await tester.pump();
      await tester.tap(relink(id), warnIfMissed: false);
      await tester.pump();

      expect(pickCalls, 1);
      expect(tester.widget<OutlinedButton>(relink(id)).onPressed, isNull);
      expect(find.byKey(Key('font_management_relink_progress_$id')),
          findsOneWidget);
      expect(
          tester
              .widget<IconButton>(
                  find.byKey(Key('font_management_delete_button_$id')))
              .onPressed,
          isNull);
      expect(
          tester
              .widget<IconButton>(
                  find.byKey(Key('font_management_rename_button_$id')))
              .onPressed,
          isNull);

      gate.complete();
      await tester.pumpAndSettle();

      expect(tester.widget<OutlinedButton>(relink(id)).onPressed, isNotNull);
      expect(find.byKey(Key('font_management_relink_progress_$id')),
          findsNothing);
    });

    testWidgets('探測未完成時刪除某個字型：結果回來後不錯位、不拋例外', (tester) async {
      final gates = {
        'content://x/a': Completer<StorageAccessProbeResult>(),
        'content://x/b': Completer<StorageAccessProbeResult>(),
      };
      probeStorageAccess = (uri) => gates[uri]!.future;
      final idA = await insertFont('A 字型', 'FamA', 'content://x/a');
      final idB = await insertFont('B 字型', 'FamB', 'content://x/b');
      await pumpTall(tester);

      await tester.tap(find.byKey(Key('font_management_delete_button_$idA')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('font_management_delete_confirm')));
      await tester.pumpAndSettle();
      expect(find.text('A 字型'), findsNothing);

      gates['content://x/a']!.complete(StorageAccessProbeResult.permissionRevoked);
      gates['content://x/b']!.complete(StorageAccessProbeResult.fileNotFound);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(badge(idA), findsNothing);
      expect(badge(idB), findsOneWidget);
      expect(find.text('檔案無法讀取'), findsOneWidget);
    });

    testWidgets('選檔期間離開畫面：選擇器回來後不持久化授權、不改記錄', (tester) async {
      mockPersistPermission();
      final gate = Completer<void>();
      final id = await insertFont('舊字型', 'KingHwa_OldSong', 'content://old/font');
      probeByUri['content://old/font'] =
          StorageAccessProbeResult.permissionRevoked;
      await pumpTall(tester, pickSingleFontFile: () async {
        await gate.future;
        // 即使選到同家族字型，畫面已離開就不該再處理
        return (
          uri: 'content://new/font',
          name: 'KingHwa.ttf',
          bytes: sampleFontBytes,
        );
      });

      await tester.tap(relink(id));
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      gate.complete();
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(persistedUris, isEmpty);
      expect((await repository.listAll()).single.fontUri, 'content://old/font');
    });

    testWidgets('離開畫面後探測才回來：不拋例外', (tester) async {
      final gate = Completer<StorageAccessProbeResult>();
      probeStorageAccess = (uri) => gate.future;
      await insertFont('A 字型', 'FamA', 'content://x/a');
      await pumpTall(tester);

      await tester.pumpWidget(const SizedBox());
      gate.complete(StorageAccessProbeResult.permissionRevoked);
      await tester.pump();

      expect(tester.takeException(), isNull);
    });

    testWidgets('改名讓清單重新載入：已探測過的字型不重複探測', (tester) async {
      final id = await insertFont('舊名稱', 'FamRename', 'content://x/rename');
      await pumpTall(tester);
      expect(probedUris, ['content://x/rename']);

      await tester.tap(find.byKey(Key('font_management_rename_button_$id')));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const Key('font_management_rename_field')), '新名稱');
      await tester.tap(find.byKey(const Key('font_management_rename_confirm')));
      await tester.pumpAndSettle();

      expect(find.text('新名稱'), findsOneWidget);
      expect(probedUris, ['content://x/rename']);
    });

    testWidgets('英文介面：標籤與動作以英文顯示', (tester) async {
      final id = await insertFont('Font', 'FamEn', 'content://x/en');
      probeByUri['content://x/en'] = StorageAccessProbeResult.permissionRevoked;

      await pumpTall(tester, locale: const Locale('en'));

      expect(badge(id), findsOneWidget);
      expect(find.text('File unreadable'), findsOneWidget);
      expect(find.text('Relink font file'), findsOneWidget);
    });
  });
```

- [ ] **Step 3：確認測試失敗**

Run: `flutter test test/screens/font_management_screen_test.dart --plain-name "儲存權限失效標示"`
Expected: 編譯失敗，`No named parameter with the name 'pickSingleFontFile'` 與 `'SingleFontFilePicker' isn't a type`。

- [ ] **Step 4：實作畫面**

`font_management_screen.dart`：

(a) 檔案開頭 import 區補：

```dart
import 'dart:async';
```

並在既有 `import '../reader/font_name_parser.dart';` 之後補：

```dart
import '../reader/foliate_native_bridge.dart'
    show StorageAccessProbeResult, probeStorageAccess;
```

（`Uint8List` 由既有的 `package:flutter/services.dart` 提供，不需另外 import；若 `flutter analyze` 回報 `Undefined class 'Uint8List'` 才補 `import 'dart:typed_data';`。）

(b) 在 `FontManagementScreen` 類別之前新增 typedef 與預設實作：

```dart
/// 單檔字型選擇器（epic-15-storage-permission Issue 3：重新連結用）。
/// 回傳選取的 URI、檔名與位元組（位元組用來解析字型家族名稱）；使用者取消
/// 時回傳 `null`。做成可注入的函式型別，讓 widget test 不必觸碰平台實作。
typedef SingleFontFilePicker =
    Future<({String uri, String name, Uint8List bytes})?> Function();

/// [SingleFontFilePicker] 的預設實作：`FilePicker` 單選 ttf／otf。`uri` 是
/// `PlatformFile.identifier`（Android 上為 `content://` URI）；`identifier` 或
/// 位元組為 null（非 Android 平台）視為取消。選擇器拋出例外時比照
/// [pickSingleBookFileViaFilePicker] 視為取消。
Future<({String uri, String name, Uint8List bytes})?>
    pickSingleFontFileViaFilePicker() async {
  try {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['ttf', 'otf'],
      withData: true,
    );
    final file = picked?.files.firstOrNull;
    final uri = file?.identifier;
    final bytes = file?.bytes;
    if (file == null || uri == null || bytes == null) return null;
    return (uri: uri, name: file.name, bytes: bytes);
  } catch (_) {
    return null;
  }
}
```

(c) `FontManagementScreen` 新增選用參數：

```dart
class FontManagementScreen extends StatefulWidget {
  final CustomFontsRepository repository;
  final DownloadableFontStore? downloadableFontStore;

  /// 重新連結用的單檔選擇器（epic-15-storage-permission Issue 3）。`null` 時
  /// 使用 [pickSingleFontFileViaFilePicker]，供 widget test 注入。
  final SingleFontFilePicker? pickSingleFontFile;

  const FontManagementScreen({
    super.key,
    required this.repository,
    this.downloadableFontStore,
    this.pickSingleFontFile,
  });
```

(d) `_FontManagementScreenState` 新增狀態（放在 `_isUploading` 之後）：

```dart
  // ── 儲存權限失效標示（epic-15-storage-permission Issue 3）──
  /// 字型資料庫主鍵 → 存取探測結果。用 id 而非清單索引：探測期間使用者可能
  /// 刪除或重新命名字型讓清單改變，用 id 對應才不會錯位。
  final Map<int, StorageAccessProbeResult> _probeResults = {};

  /// 已經發出探測的字型 id；清單重新載入時不重複探測。
  final Set<int> _probeRequestedIds = {};

  /// 重新連結處理中的字型 id：該列的動作停用，避免連點重複開選擇器。
  final Set<int> _relinkingIds = {};
```

(e) `_loadFonts` 改為：

```dart
  Future<void> _loadFonts() async {
    try {
      final fonts = await widget.repository.listAll();
      if (!mounted) return;
      setState(() => _customFonts = fonts);
      _probeNewFonts(fonts);
    } catch (e) {
      debugPrint('Failed to load custom fonts: $e');
    }
  }

  /// 對尚未探測過的自訂字型各自發出存取探測（不 await，不阻塞清單顯示）。
  void _probeNewFonts(List<CustomFont> fonts) {
    for (final font in fonts) {
      final id = font.id;
      if (id == null || !_probeRequestedIds.add(id)) continue;
      unawaited(_probeFont(id, font.fontUri));
    }
  }

  Future<void> _probeFont(int id, String uri) async {
    final result = await probeStorageAccess(uri);
    // 探測期間可能已離開畫面，或該字型已被刪除：結果直接捨棄
    if (!mounted || !_customFonts.any((f) => f.id == id)) return;
    setState(() => _probeResults[id] = result);
  }
```

(f) 把 `build` 內自訂字型的 `for (final font in _customFonts) ListTile(...)` 換成：

```dart
          for (final font in _customFonts) _buildCustomFontTile(font, l10n),
```

並新增方法（放在 `_buildBuiltInFontTile` 之前）。既有的標題、重新命名、刪除按鈕內容原樣保留：

```dart
  /// 自訂字型的一列。探測結果不是 `readable` 時，在副標題顯示文字標籤與
  /// 外框的重新連結按鈕（epic-15-storage-permission Issue 3）：標籤是文字而非
  /// 只靠顏色，按鈕用 OutlinedButton，E-Ink 高對比模式下才看得清楚。
  Widget _buildCustomFontTile(CustomFont font, AppLocalizations l10n) {
    final id = font.id;
    final probe = id == null ? null : _probeResults[id];
    final isInaccessible =
        probe != null && probe != StorageAccessProbeResult.readable;
    final isRelinking = id != null && _relinkingIds.contains(id);
    return ListTile(
      title: Text(font.displayName),
      subtitle: isInaccessible
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.fontManagementFileInaccessibleBadge,
                  key: Key('font_management_inaccessible_badge_$id'),
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                OutlinedButton(
                  key: Key('font_management_relink_button_$id'),
                  onPressed: isRelinking ? null : () => _relinkFont(font),
                  child: isRelinking
                      ? SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(
                            key: Key('font_management_relink_progress_$id'),
                            strokeWidth: 2,
                          ),
                        )
                      : Text(l10n.fontManagementRelinkAction),
                ),
              ],
            )
          : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            key: Key('font_management_rename_button_${font.id}'),
            icon: const Icon(Icons.edit),
            tooltip: l10n.fontManagementRenameTooltip,
            onPressed: isRelinking ? null : () => _renameFont(font),
          ),
          IconButton(
            key: Key('font_management_delete_button_${font.id}'),
            icon: const Icon(Icons.delete),
            tooltip: l10n.fontManagementDeleteTooltip,
            onPressed: isRelinking ? null : () => _deleteFont(font),
          ),
        ],
      ),
    );
  }
```

(g) 在 `_renameFont` 之前新增重新連結流程：

```dart
  /// 重新連結字型檔案（epic-15-storage-permission Issue 3）：選檔 → 比對家族
  /// 名稱 → 持久化授權（盡力而為）→ 更新 URI。家族名稱不同就拒絕，不持久化
  /// 授權、不改記錄。單書版面偏好以家族名稱引用字型，所以更新 URI 後所有使用
  /// 這款字型的書自動恢復，不需要遷移。
  Future<void> _relinkFont(CustomFont font) async {
    final id = font.id;
    if (id == null || _relinkingIds.contains(id)) return;
    setState(() => _relinkingIds.add(id));
    try {
      final picker = widget.pickSingleFontFile ?? pickSingleFontFileViaFilePicker;
      final picked = await picker();
      // 選檔期間使用者可能已離開畫面：不再解析、不持久化授權、不寫資料庫
      if (picked == null || !mounted) return;

      // 家族名稱解析規則與批次上傳一致：解析失敗退回檔名（去副檔名）
      final pickedFamily =
          parseFontFamilyName(picked.bytes) ?? _stripExtension(picked.name);
      if (pickedFamily != font.familyName) {
        if (!mounted) return;
        final l10n = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
            content: Text(l10n.fontManagementFamilyMismatchMessage),
          ));
        return;
      }

      try {
        await kBookMetadataChannel.invokeMethod<void>(
            'takePersistableUriPermission', {'uri': picked.uri});
      } on PlatformException {
        // 比照批次上傳與 ADR 0021：字型檔不做落地複本退路，授權盡力而為，
        // 失敗不中止重新連結。
      }
      await widget.repository.updateUri(id, picked.uri);
      if (!mounted) return;
      setState(() => _probeResults[id] = StorageAccessProbeResult.readable);
      await _loadFonts();
    } finally {
      if (mounted) setState(() => _relinkingIds.remove(id));
    }
  }
```

- [ ] **Step 5：確認測試通過**

Run: `flutter test test/screens/font_management_screen_test.dart`
Expected: All tests passed（新增 12 個案例，既有案例不受影響）。

Run: `flutter test test/reader/custom_fonts_repository_test.dart test/screens/settings_scaffold_test.dart test/screens/adaptive_shell_scaffold_test.dart test/elinkbook_app_wiring_test.dart`
Expected: All tests passed（這幾個檔案用到 `CustomFontsRepository`／`FontManagementScreen`，確認建構子新增選用參數沒有影響）。

Run: `flutter analyze`
Expected: `No issues found!`

Run: `node tool/check_l10n_hardcoded_strings.js`
Expected: 通過，沒有新增違規。

- [ ] **Step 6：Commit**

```bash
git add lib/screens/font_management_screen.dart test/screens/font_management_screen_test.dart lib/l10n/
git commit -m "feat(fonts): 字型管理標示讀不到的自訂字型並可重新連結（epic-15 Issue 3）"
```

---

### Task 3：真機驗證（需要真人操作）

**Files:** 無程式改動；結果記錄在 `docs/epics/epic-15-storage-permission/epic.md`。

這個 Task 需要實體 Android 裝置，以及用檔案管理員手動操作。執行者若是 agent，完成 Step 1 後就停下來，把 Step 2～5 交給人類操作，並回報在哪裡等待。

> **驗證方式說明**：Issue 2 已確認，SAF 持久化授權在沒有 root 的裝置上無法主動撤銷，所以不用「撤銷授權」觸發，改用「把字型原始檔搬走」讓探測回報 `fileNotFound`。標示與重新連結流程對 `permissionRevoked`、`fileNotFound`、`unknownError` 完全相同（只看「是否 `readable`」），所以這一條路徑足以驗證整個流程。

- [ ] **Step 1：安裝 debug 版**

Run: `flutter devices`，確認裝置 ID 後執行 `flutter run -d <device-id>`。

- [ ] **Step 2：準備字型與書（人類）**

- 進入「設定 → 字型管理」，用右上角「＋」上傳一款自訂字型（例如放在 `Download/` 的 `.ttf`）。確認這時該字型**沒有**「檔案無法讀取」標示。
- 開任一本書，在閱讀設定把字型改成剛上傳的自訂字型，確認畫面套用了這款字型，返回書架。

- [ ] **Step 3：搬走原始字型檔，確認標示（人類）**

- 用檔案管理員把該 `.ttf` **搬移**到另一個資料夾（不要刪除）。
- 回到 App，進入字型管理。預期：清單先顯示，隨後該字型出現「檔案無法讀取」標示與「重新連結字型檔案」按鈕；其他字型沒有標示。
- 開那本書。預期：靜默改用預設字型，沒有任何提示（閱讀器行為不變）。

- [ ] **Step 4：選錯再選對（人類）**

- 在字型管理按「重新連結字型檔案」，選一款**不同家族**的字型。預期：SnackBar「選取的字型與原字型的家族名稱不同」，標示仍在。
- 再按一次，到新位置選原本那個 `.ttf`。預期：標示消失。
- 再開那本書。預期：恢復顯示這款自訂字型。
- 關掉 App 再重開，進入字型管理。預期：該字型仍沒有標示（新授權已持久化）。

- [ ] **Step 5：記錄結果**

在 `epic.md` 新增「Issue 3 真機驗證」段落，記錄實際執行的情境、裝置型號與結果。任何一項不符預期，如實記錄並回報，不要逕自修改範圍外的程式碼。

---

### Task 4：完整測試與進度文件

- [ ] **Step 1：完整測試**

Run: `flutter test`
Expected: All tests passed。若有失敗，先單獨重跑該檔案，確認是不是本 Issue 造成的；和本 Issue 無關的失敗要如實記錄在 `epic.md`，不要為了讓它通過而修改範圍外的程式碼。

Run: `flutter analyze`
Expected: `No issues found!`

Run: `node tool/check_l10n_hardcoded_strings.js`
Expected: 通過。

- [ ] **Step 2：更新進度文件**

- `docs/epics/epic-15-storage-permission/issues.md`：Issue 3 的 `**Status:** ready-for-agent` 改為 `**Status:** completed`。
- `docs/epics/epic-15-storage-permission/epic.md`：在「目前狀態」之前新增「Issue 3 完成記錄」，內容包含 commit 清單、完整 `flutter test` 結果與執行時的 commit、真機驗證摘要（未執行就如實寫「待補」）。把「目前狀態」改為反映 Issue 3 完成、待 PR 合併；四個 Issue 都完成後備註「全數完成，待歸檔」。
- `docs/epics.md`：epic-15 備註改為 `Issue 3 已完成`（PR 合併、確認全數完成後再改為「全數完成，待歸檔」）。

```bash
git add ../docs/epics/epic-15-storage-permission/issues.md ../docs/epics/epic-15-storage-permission/epic.md ../docs/epics.md
git commit -m "docs(epic-15): 記錄 Issue 3 完成"
```

---

## Self-Review

- **Spec 涵蓋**：`updateUri` 與 Fake（Task 1）；清單載入後非同步探測、以 id 保存、寫入前 mounted＋id 仍在（Task 2 (d)(e)，測試「探測不阻塞」「探測未完成時刪除」「離開畫面」）；文字標籤＋重新連結動作與 Key（(f)）；單檔選擇器 typedef 與預設實作（(b)(c)）；家族名稱比對、拒絕 SnackBar、持久化授權盡力而為、`updateUri`、狀態改 `readable`、處理中停用＋finally（(g)，對應測試各一）；三個 ARB key 四份檔案＋`gen-l10n`（Step 1）；閱讀器與可下載字型不動（沒有改動）；真機驗證（Task 3）；l10n 稽核（Task 2 Step 5、Task 4）。
- **Placeholder 掃描**：無 TBD／「類似 Task N」；每個程式碼步驟都有完整程式碼。
- **型別一致**：`updateUri(int id, String fontUri)`、`SingleFontFilePicker`、`pickSingleFontFileViaFilePicker`、`pickSingleFontFile`、`_probeResults`／`_probeRequestedIds`／`_relinkingIds`、三個 Key 前綴，在各 Task 與測試中拼法一致。
- **Review Focus**：五項各有對應測試（刪除、改名不重複探測、連點、取消＋授權失敗、離開畫面）。
