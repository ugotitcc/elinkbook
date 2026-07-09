# Issue 6：真機驗證與收尾 — 實作計劃

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 完成 Epic 3 的 Issue 6，包含撰寫自動化 `integration_test` 驗證自動旋轉重新分頁，並建立一份人工視覺驗收 Checklist 供使用者實際在真機上執行，最後彙整驗證紀錄產出測試報告。

**Tech Stack:** Flutter `integration_test`、Dart / Flutter

---

### Task 1: 撰寫自動化整合測試（自動旋轉重新分頁）

**Files:**
- Create: `app/integration_test/orientation_repagination_test.dart`

**Description:**
新增一項整合測試。在 `ReaderScreen` 成功載入圖書後，使用 `tester.binding.setSurfaceSize` 將視窗大小從直排（Portrait，如 600x1024）切換為橫排（Landscape，如 1024x600），並反向切換。
此動作模擬真實裝置的自動旋轉，我們需要驗證：
1. 視窗尺寸變更時，Flutter UI 與 `PlatformView` 的寬高會隨之調整。
2. 切換後，不會觸發 `EpubReaderView` 的 `onError`，即不會顯示任何 `reader_error_text`。
3. 圖書內容在旋轉後依然渲染成功。

- [ ] **Step 1: 建立 integration_test/orientation_repagination_test.dart**

```dart
// app/integration_test/orientation_repagination_test.dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:elinkbook/library/sqlite_library_repository.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/reader/book_reader_prefs_repository.dart';
import 'package:elinkbook/screens/reader_screen.dart';

Future<String> _stageAssetAsFile(String assetPath, String fileName) async {
  final bytes = await rootBundle.load(assetPath);
  final tempDir = await getTemporaryDirectory();
  final file = File('${tempDir.path}/$fileName');
  await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
  return file.path;
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  required Duration timeout,
  Duration step = const Duration(milliseconds: 100),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('等待逾時（$timeout）：條件未成立');
    }
    await tester.pump(step);
  }
}

bool _loadingIndicatorGone() =>
    find.byKey(const Key('reader_loading_indicator')).evaluate().isEmpty;

Book _book(String id) => Book(
      id: id,
      title: '旋轉測試書',
      format: BookFileFormat.epub,
      filePath: 'content://example/$id',
      source: BookSource.local,
      createTime: DateTime.fromMillisecondsSinceEpoch(1000),
      lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
    );

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late SqliteLibraryRepository libraryRepository;
  late BookReaderPrefsRepository prefsRepository;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    libraryRepository =
        await SqliteLibraryRepository.open(inMemoryDatabasePath);
    prefsRepository = BookReaderPrefsRepository(libraryRepository.database);
  });

  tearDown(() async {
    await libraryRepository.close();
  });

  testWidgets('模擬自動旋轉：直橫排切換時，畫面能成功重新分頁且無 onError 錯誤', (tester) async {
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample.epub', 'sample_orientation_repage.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });
    await libraryRepository.insertBook(_book('b_repage_1'));

    // 1. 設定初始大小為直排 (Portrait)
    await tester.binding.setSurfaceSize(const Size(600, 1024));

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: samplePath,
          bookId: 'b_repage_1',
          prefsRepository: prefsRepository,
        ),
      ),
    );

    // 等待載入完畢
    await _pumpUntil(
      tester,
      _loadingIndicatorGone,
      timeout: const Duration(seconds: 10),
    );

    expect(find.byKey(const Key('reader_error_text')), findsNothing);

    // 2. 切換為橫排 (Landscape) 模擬物理旋轉
    await tester.binding.setSurfaceSize(const Size(1024, 600));
    await tester.pumpAndSettle();
    // 給予額外的過渡等待，確保 WebView 重新適應新解析度
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byKey(const Key('reader_error_text')), findsNothing,
        reason: '直排切換為橫排時，應能正常重新分頁，不觸發 onError');

    // 3. 再切回直排 (Portrait)
    await tester.binding.setSurfaceSize(const Size(600, 1024));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byKey(const Key('reader_error_text')), findsNothing,
        reason: '橫排切回直排時，應能正常重新分頁，不觸發 onError');
  });
}
```

- [ ] **Step 2: 於本地執行此 integration_test**

您需要在連接真機的環境下執行：
`flutter test integration_test/orientation_repagination_test.dart`

---

### Task 2: 人工視覺驗收與 QA 檢核清單

由於 AI 無法看見實體螢幕，您需要操作真機並完成以下檢核：

- [ ] **Step 1: 自訂字型實際載入驗證 (Check 1)**
  - 開啟書籍，點擊「⚙️版面」開啟設定 Bottom Sheet。
  - 依序切換 5 款內建字型（思源黑體、思源宋體、關夾清楷、臺灣明體、源流明體）。
  - **驗收標準**：肉眼確認文字字體確實隨之切換，而非維持同一字形（確保 `servedAssets` 與字型登記正常運作）。

- [ ] **Step 2: 字重 Variable Font 與模擬粗體確認 (Check 2)**
  - 選取「思源黑體」或「思源宋體」，拖動「字重」滑桿從 300 到 900。
  - **驗收標準**：文字粗細呈多級漸進變化（Variable Font 效果）。
  - 切換至「關夾清楷」，拖動「字重」滑桿到 700 或 900。
  - **驗收標準**：文字呈現模擬粗體（Faux Bold）效果，且沒有發生排版錯亂或崩潰。

- [ ] **Step 3: 端到端偏好設定持久化 (Check 3)**
  - 修改數個設定值（如：字型大 = 20、字型粗細 = 700、排版方向 = 強制直排、E-Ink 模式 = 開啟）。
  - 離開閱讀器返回書架。
  - **驗收標準**：書架介面顯示為 E-Ink 黑白高對比樣式，且主題圓點變暗不可點擊。
  - 重新點選剛才的書籍進入閱讀器。
  - **驗收標準**：字型大小、字重與直排設定均完美維持，無須重新調整。

---

### Task 3: 產出實機驗收報告與 Epic 收尾

- [ ] **Step 1: 建立實機驗收報告檔案**
  - 將您的驗證結果填入 `tmp/epic-3/reviews/qa-issue-6-report.md`。

- [ ] **Step 2: 更新進度狀態並歸檔 Epic 3**
  - 將 `docs/epics/epic-3-fonts-layout/issues.md` 的 Issue 6 標記為已完成。
  - 將 `docs/epics.md` 中的 Epic 3 狀態標記為 `🟢 已歸檔 (Archived)`。
  - 將 `docs/epics/epic-3-fonts-layout/` 目錄搬移至 `docs/archive/`。
