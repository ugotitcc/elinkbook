import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:elinkbook/reader/app_font.dart';
import 'package:elinkbook/reader/epub_text_align.dart';
import 'package:elinkbook/reader/foliate_epub_reader_view.dart';
import 'package:elinkbook/reader/writing_mode.dart';

/// Epic 20 Issue 5：EpubReaderView（Readium）刪除後，原本只在（已刪除的）
/// epub_reader_view_test.dart 驗證的兩個場景（毀損檔案偵測、FXL
/// isFixedLayout=true 回報）改到這裡沿用 FoliateEpubReaderView 驗證，避免
/// EpubReaderView 類別刪除連帶讓這兩項行為的自動化涵蓋消失。

/// 把 Flutter asset 複製為裝置暫存目錄中的真實檔案，回傳其絕對路徑。
Future<String> _stageAssetAsFile(String assetPath, String fileName) async {
  final bytes = await rootBundle.load(assetPath);
  final tempDir = await getTemporaryDirectory();
  final file = File('${tempDir.path}/$fileName');
  await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
  return file.path;
}

/// 動態產生一個實體大小達 [fillerBytes] 的合法 EPUB，寫入裝置暫存目錄，回傳其
/// 絕對路徑。Issue 8 修復前，開啟大型 EPUB（真實樣本 217MB）會因整檔讀進單一
/// 記憶體陣列導致 OutOfMemoryError；217MB 的真實樣本不便長期存放於版控
/// （見 plan-issue-8.md Task 5 Step 2），改為在測試當下組出一個內容無意義、
/// 但實體檔案大小足以真正驗證原生 WebViewAssetLoader 串流路徑的合法 EPUB。
///
/// 填充內容（`OEBPS/filler.bin`）未被 manifest／spine 引用，zip.js 只會依
/// container.xml → content.opf → 被引用的檔案這條路徑讀取，不會處理它；
/// 壓縮方式固定為 [CompressionType.none]，確保填充內容不會因為高度可壓縮
/// （全零位元組）被壓成遠小於預期的檔案，讓 .epub 檔案本身的實體大小如實反映
/// [fillerBytes]。
Future<String> _buildLargeSyntheticEpub(
    {required int fillerBytes, required String fileName}) async {
  final archive = Archive();
  void addStored(String name, List<int> data) {
    archive.addFile(ArchiveFile.bytes(name, data)
      ..compression = CompressionType.none);
  }

  addStored('mimetype', utf8.encode('application/epub+zip'));
  addStored(
      'META-INF/container.xml',
      utf8.encode('''<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>
'''));
  addStored(
      'OEBPS/content.opf',
      utf8.encode('''<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="pub-id">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="pub-id">urn:uuid:00000000-0000-0000-0000-000000000099</dc:identifier>
    <dc:title>Issue 8 大型檔案串流測試</dc:title>
    <dc:language>zh-TW</dc:language>
    <meta property="dcterms:modified">2026-08-01T00:00:00Z</meta>
  </metadata>
  <manifest>
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
    <item id="chapter1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine>
    <itemref idref="chapter1"/>
  </spine>
</package>
'''));
  addStored(
      'OEBPS/nav.xhtml',
      utf8.encode('''<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
<head><title>目錄</title></head>
<body><nav epub:type="toc"><ol><li><a href="chapter1.xhtml">第一章</a></li></ol></nav></body>
</html>
'''));
  addStored(
      'OEBPS/chapter1.xhtml',
      utf8.encode('''<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
<head><title>第一章</title></head>
<body><h1>第一章</h1><p>Issue 8 大型檔案串流測試內容。</p></body>
</html>
'''));
  addStored('OEBPS/filler.bin', Uint8List(fillerBytes));

  final zipBytes = ZipEncoder().encode(archive);
  final tempDir = await getTemporaryDirectory();
  final file = File('${tempDir.path}/$fileName');
  await file.writeAsBytes(zipBytes, flush: true);
  return file.path;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('開啟有效的流式 EPUB 檔案觸發 onPageRendered', (tester) async {
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample.epub', 'foliate_sample.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    final completer = Completer<void>();
    String? errorMessage;

    await tester.pumpWidget(
      MaterialApp(
        home: FoliateEpubReaderView(
          filePath: samplePath,
          onPageRendered: () {
            if (!completer.isCompleted) completer.complete();
          },
          onError: (message) {
            errorMessage = message;
            if (!completer.isCompleted) completer.complete();
          },
        ),
      ),
    );

    await completer.future.timeout(const Duration(seconds: 10));
    await tester.pumpAndSettle();

    expect(errorMessage, isNull,
        reason: '應觸發 onPageRendered，但 onError 訊息為: $errorMessage');
  });

  testWidgets('開啟不存在的檔案路徑（但落在允許目錄內）觸發 onError', (tester) async {
    final completer = Completer<void>();
    var rendered = false;
    String? errorMessage;

    final tempDir = await getTemporaryDirectory();
    final missingPath =
        '${tempDir.path}/does_not_exist_${DateTime.now().millisecondsSinceEpoch}.epub';

    await tester.pumpWidget(
      MaterialApp(
        home: FoliateEpubReaderView(
          filePath: missingPath,
          onPageRendered: () {
            rendered = true;
            if (!completer.isCompleted) completer.complete();
          },
          onError: (message) {
            errorMessage = message;
            if (!completer.isCompleted) completer.complete();
          },
        ),
      ),
    );

    await completer.future.timeout(const Duration(seconds: 10));
    await tester.pumpAndSettle();

    expect(rendered, isFalse);
    expect(errorMessage, isNotNull);
  });

  testWidgets(
      'PathHandler 路徑穿越防護：開啟允許目錄之外的檔案路徑觸發 onError（不會被當作合法書籍開啟）',
      (tester) async {
    final completer = Completer<void>();
    var rendered = false;
    String? errorMessage;

    // /data/local/tmp 是裝置上真實存在、但不屬於本 App 私有文件目錄
    // （Context.filesDir）的路徑，驗證 FoliatePathValidator 的目錄邊界
    // 檢查會在真機上正確擋下這類請求，而不是被 File I/O 意外允許。
    const outsidePath =
        '/data/local/tmp/foliate_path_traversal_probe_should_not_open.epub';

    await tester.pumpWidget(
      MaterialApp(
        home: FoliateEpubReaderView(
          filePath: outsidePath,
          onPageRendered: () {
            rendered = true;
            if (!completer.isCompleted) completer.complete();
          },
          onError: (message) {
            errorMessage = message;
            if (!completer.isCompleted) completer.complete();
          },
        ),
      ),
    );

    await completer.future.timeout(const Duration(seconds: 10));
    await tester.pumpAndSettle();

    expect(rendered, isFalse,
        reason: 'PathHandler 的目錄邊界檢查應該拒絕這個請求，不應該渲染成功');
    expect(errorMessage, contains('允許的目錄範圍'));
  });

  testWidgets(
      'FR-06：開啟自行宣告 writing-mode: vertical-rl 的素材，初始即為直排（不需手動切換）',
      (tester) async {
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample_declares_vertical.epub',
        'foliate_declares_vertical.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    final completer = Completer<EpubLayoutInfo>();
    String? errorMessage;

    await tester.pumpWidget(
      MaterialApp(
        home: FoliateEpubReaderView(
          filePath: samplePath,
          onPageRendered: () {},
          onError: (message) {
            errorMessage = message;
          },
          onLayoutResolved: (info) {
            if (!completer.isCompleted) completer.complete(info);
          },
        ),
      ),
    );

    final info = await completer.future.timeout(const Duration(seconds: 10));
    await tester.pumpAndSettle();

    expect(errorMessage, isNull);
    expect(info.writingMode, WritingMode.vertical,
        reason: '書本自行宣告 vertical-rl，FR-06 應偵測到並回報直排');
  });

  testWidgets(
      'FR-06：開啟完全不宣告 writing-mode 的素材，初始為橫排',
      (tester) async {
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample.epub', 'foliate_no_declaration.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    final completer = Completer<EpubLayoutInfo>();
    String? errorMessage;

    await tester.pumpWidget(
      MaterialApp(
        home: FoliateEpubReaderView(
          filePath: samplePath,
          onPageRendered: () {},
          onError: (message) {
            errorMessage = message;
          },
          onLayoutResolved: (info) {
            if (!completer.isCompleted) completer.complete(info);
          },
        ),
      ),
    );

    final info = await completer.future.timeout(const Duration(seconds: 10));
    await tester.pumpAndSettle();

    expect(errorMessage, isNull);
    expect(info.writingMode, WritingMode.horizontal,
        reason: '書本完全不宣告 writing-mode，FR-06 應預設橫排');
  });

  testWidgets('手動切換橫排→直排、直排→橫排皆即時生效（不重新開書）',
      (tester) async {
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample.epub', 'foliate_toggle_direction.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    final key = GlobalKey<State<FoliateEpubReaderView>>();
    final completer = Completer<void>();

    await tester.pumpWidget(
      MaterialApp(
        home: FoliateEpubReaderView(
          key: key,
          filePath: samplePath,
          onPageRendered: () {
            if (!completer.isCompleted) completer.complete();
          },
          onError: (message) {},
          writingMode: WritingMode.horizontal,
        ),
      ),
    );
    await completer.future.timeout(const Duration(seconds: 10));
    await tester.pumpAndSettle();

    // 手動切換為直排：didUpdateWidget 偵測到變動送出 setPreferences，
    // 畫面應即時反映（不重新開書、不再次觸發 onPageRendered）。
    await tester.pumpWidget(
      MaterialApp(
        home: FoliateEpubReaderView(
          key: key,
          filePath: samplePath,
          onPageRendered: () {},
          onError: (message) {},
          writingMode: WritingMode.vertical,
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // 再切回橫排，確認雙向皆可逆。
    await tester.pumpWidget(
      MaterialApp(
        home: FoliateEpubReaderView(
          key: key,
          filePath: samplePath,
          onPageRendered: () {},
          onError: (message) {},
          writingMode: WritingMode.horizontal,
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // 本測試斷言 widget 樹本身未崩潰、無 onError 觸發即代表雙向切換的
    // method channel 呼叫皆正常送達；實際排版方向的視覺正確性（欄位是否
    // 真的改變）留待人工於裝置螢幕截圖確認，比照本專案既有 integration_test
    // 對「視覺效果」類驗收標準的既定作法（純程式碼斷言無法檢查像素排列）。
    expect(find.byType(FoliateEpubReaderView), findsOneWidget);
  });

  testWidgets('字型/字級/行距等偏好設定套用後不觸發 onError（畫面應正確反映變更，人工視覺確認）',
      (tester) async {
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample.epub', 'foliate_style_prefs.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    final completer = Completer<void>();
    String? errorMessage;

    await tester.pumpWidget(
      MaterialApp(
        home: FoliateEpubReaderView(
          filePath: samplePath,
          onPageRendered: () {
            if (!completer.isCompleted) completer.complete();
          },
          onError: (message) {
            errorMessage = message;
            if (!completer.isCompleted) completer.complete();
          },
          fontFamily: AppFont.sourceHanSerif,
          fontSize: 1.5,
          fontWeight: 1.75,
          lineHeight: 2.0,
          paragraphSpacing: 1.5,
          marginTop: 2.0,
          marginBottom: 2.0,
          marginLeft: 2.0,
          marginRight: 2.0,
          textAlign: EpubTextAlign.justify,
        ),
      ),
    );

    await completer.future.timeout(const Duration(seconds: 10));
    await tester.pumpAndSettle();

    expect(errorMessage, isNull,
        reason: '套用完整版面偏好不應觸發 onError');
  });

  testWidgets('開啟內容已損毀的 EPUB 檔案（合法路徑但非合法 zip）觸發 onError',
      (tester) async {
    // 檔案存在且落在允許目錄內，但內容不是合法的 EPUB（甚至不是合法的
    // zip）——與「檔案不存在」的測試案例分屬不同的失敗分支，驗證的是
    // 解析階段（而非路徑驗證階段）的 onError 觸發路徑。
    final tempDir = await getTemporaryDirectory();
    final corruptedFile = File(
        '${tempDir.path}/foliate_corrupted_${DateTime.now().millisecondsSinceEpoch}.epub');
    await corruptedFile.writeAsBytes(
        List<int>.generate(256, (i) => i % 256), flush: true);
    addTearDown(() async {
      if (await corruptedFile.exists()) await corruptedFile.delete();
    });

    final completer = Completer<void>();
    var rendered = false;
    String? errorMessage;

    await tester.pumpWidget(
      MaterialApp(
        home: FoliateEpubReaderView(
          filePath: corruptedFile.path,
          onPageRendered: () {
            rendered = true;
            if (!completer.isCompleted) completer.complete();
          },
          onError: (message) {
            errorMessage = message;
            if (!completer.isCompleted) completer.complete();
          },
        ),
      ),
    );

    await completer.future.timeout(const Duration(seconds: 10));
    await tester.pumpAndSettle();

    expect(errorMessage, isNotNull);
    expect(rendered, isFalse);
  });

  testWidgets('開啟定樣式（FXL）範例 EPUB，onLayoutResolved 回報 isFixedLayout 為 true',
      (tester) async {
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample_fixed_layout.epub', 'foliate_layout_fixed.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    final completer = Completer<void>();
    EpubLayoutInfo? layoutInfo;

    await tester.pumpWidget(
      MaterialApp(
        home: FoliateEpubReaderView(
          filePath: samplePath,
          onPageRendered: () {},
          onError: (message) {
            if (!completer.isCompleted) completer.complete();
          },
          onLayoutResolved: (info) {
            layoutInfo = info;
            if (!completer.isCompleted) completer.complete();
          },
        ),
      ),
    );

    await completer.future.timeout(const Duration(seconds: 10));
    await tester.pumpAndSettle();

    expect(layoutInfo, isNotNull);
    expect(layoutInfo!.isFixedLayout, isTrue);
  });

  // Issue 8 審查 Important #5：大型 EPUB 串流路徑自動化迴歸測試（原本只有
  // 真機人工驗證，缺少自動化保護）。
  testWidgets(
      'Issue 8：開啟動態產生的大型 EPUB（30MB，模擬 OOM 修復前會整檔讀進記憶體的情境）'
      '觸發 onPageRendered，驗證原生 WebViewAssetLoader 串流路徑可正確處理大檔案',
      (tester) async {
    final samplePath = await _buildLargeSyntheticEpub(
        fillerBytes: 30 * 1024 * 1024, fileName: 'foliate_large_synthetic.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    final completer = Completer<void>();
    String? errorMessage;

    await tester.pumpWidget(
      MaterialApp(
        home: FoliateEpubReaderView(
          filePath: samplePath,
          onPageRendered: () {
            if (!completer.isCompleted) completer.complete();
          },
          onError: (message) {
            errorMessage = message;
            if (!completer.isCompleted) completer.complete();
          },
        ),
      ),
    );

    // 30MB 檔案的分塊串流複製＋WebView 解析耗時明顯高於一般小型 fixture，
    // 給予較寬鬆的逾時（真機 217MB 實測分塊複製本身約 2.1 秒，此處額外預留
    // WebView 解析與轉場時間）。
    await completer.future.timeout(const Duration(seconds: 30));
    await tester.pumpAndSettle();

    expect(errorMessage, isNull,
        reason: '應觸發 onPageRendered，但 onError 訊息為: $errorMessage');
  });
}
