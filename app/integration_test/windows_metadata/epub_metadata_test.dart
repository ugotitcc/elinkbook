// Windows EPUB 詮釋資料背景解析整合測試（epic-66 Issue 2 Task 4）。
//
// 驗證 HeadlessInAppWebView 搭配 foliate-js metadata-probe：
// - 正確解析 8 份 metadata fixture 與既有 sample.epub、sample_fxl_svg_cover.epub；
// - 驗證 title, author, identifier, isFixedLayout 與封面大小；
// - 印出 [metadata_comparison] 供 Task 6 Android Readium 逐本對比；
// - 損毀檔案與不存在路徑丟出 PlatformException；
// - 極短逾時丟出 TimeoutException，且逾時後續呼叫能正常重用/重建 WebView。
//
// 執行方式：flutter test integration_test/windows_metadata/epub_metadata_test.dart -d windows

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:elinkbook/library/windows_book_metadata.dart';
import 'package:elinkbook/library/windows_epub_metadata.dart';
import 'package:elinkbook/windows/windows_webview_environment.dart';

Future<String> _stageAssetAsFile(String assetPath, String fileName) async {
  final bytes = await rootBundle.load(assetPath);
  final tempDir = await getTemporaryDirectory();
  final file = File(p.join(tempDir.path, fileName));
  await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
  return file.path;
}

class _EpubTestCase {
  final String assetPath;
  final String fileName;
  final String? expectedTitle;
  final String? expectedAuthor;
  final String? expectedIdentifier;
  final bool expectedIsFixedLayout;
  final bool expectedHasCover;

  const _EpubTestCase({
    required this.assetPath,
    required this.fileName,
    required this.expectedTitle,
    required this.expectedAuthor,
    required this.expectedIdentifier,
    required this.expectedIsFixedLayout,
    required this.expectedHasCover,
  });
}

const _testCases = [
  _EpubTestCase(
    assetPath: 'test/fixtures/metadata/meta_basic.epub',
    fileName: 'meta_basic.epub',
    expectedTitle: '基本書名',
    expectedAuthor: '王小明',
    expectedIdentifier: 'urn:uuid:meta-basic',
    expectedIsFixedLayout: false,
    expectedHasCover: true,
  ),
  _EpubTestCase(
    assetPath: 'test/fixtures/metadata/meta_multi_identifier.epub',
    fileName: 'meta_multi_identifier.epub',
    expectedTitle: '多識別碼',
    expectedAuthor: null,
    expectedIdentifier: 'urn:uuid:meta-multi-second',
    expectedIsFixedLayout: false,
    expectedHasCover: false,
  ),
  _EpubTestCase(
    assetPath: 'test/fixtures/metadata/meta_lang_titles_two_creators.epub',
    fileName: 'meta_lang_titles_two_creators.epub',
    expectedTitle: '繁中書名',
    expectedAuthor: '王小明',
    expectedIdentifier: 'urn:uuid:meta-lang',
    expectedIsFixedLayout: false,
    expectedHasCover: false,
  ),
  _EpubTestCase(
    assetPath: 'test/fixtures/metadata/meta_creator_role.epub',
    fileName: 'meta_creator_role.epub',
    expectedTitle: '角色作者',
    expectedAuthor: '張三',
    expectedIdentifier: 'urn:uuid:meta-role',
    expectedIsFixedLayout: false,
    expectedHasCover: false,
  ),
  _EpubTestCase(
    assetPath: 'test/fixtures/metadata/meta_epub2_cover.epub',
    fileName: 'meta_epub2_cover.epub',
    expectedTitle: 'EPUB2 封面',
    expectedAuthor: null,
    expectedIdentifier: 'urn:uuid:meta-epub2',
    expectedIsFixedLayout: false,
    expectedHasCover: true,
  ),
  _EpubTestCase(
    assetPath: 'test/fixtures/metadata/meta_no_cover.epub',
    fileName: 'meta_no_cover.epub',
    expectedTitle: '無封面',
    expectedAuthor: null,
    expectedIdentifier: 'urn:uuid:meta-nocover',
    expectedIsFixedLayout: false,
    expectedHasCover: false,
  ),
  _EpubTestCase(
    assetPath: 'test/fixtures/metadata/meta_fixed_layout.epub',
    fileName: 'meta_fixed_layout.epub',
    expectedTitle: '固定版面',
    expectedAuthor: null,
    expectedIdentifier: 'urn:uuid:meta-fxl',
    expectedIsFixedLayout: true,
    expectedHasCover: false,
  ),
  _EpubTestCase(
    assetPath: 'test/fixtures/metadata/meta_no_identifier.epub',
    fileName: 'meta_no_identifier.epub',
    expectedTitle: '無識別碼',
    expectedAuthor: null,
    expectedIdentifier: null,
    expectedIsFixedLayout: false,
    expectedHasCover: false,
  ),
  _EpubTestCase(
    assetPath: 'test/fixtures/metadata/meta_unique_id_dangling.epub',
    fileName: 'meta_unique_id_dangling.epub',
    expectedTitle: '識別碼懸空',
    expectedAuthor: null,
    expectedIdentifier: '9789860000009',
    expectedIsFixedLayout: false,
    expectedHasCover: false,
  ),
  _EpubTestCase(
    assetPath: 'test/fixtures/metadata/meta_identifier_whitespace.epub',
    fileName: 'meta_identifier_whitespace.epub',
    expectedTitle: '識別碼含空白',
    expectedAuthor: null,
    expectedIdentifier: 'urn:uuid:meta-ws',
    expectedIsFixedLayout: false,
    expectedHasCover: false,
  ),
  _EpubTestCase(
    assetPath: 'test/fixtures/metadata/meta_identifier_opf_scheme.epub',
    fileName: 'meta_identifier_opf_scheme.epub',
    expectedTitle: '識別碼含 opf:scheme',
    expectedAuthor: null,
    expectedIdentifier: 'urn:uuid:meta-scheme',
    expectedIsFixedLayout: false,
    expectedHasCover: false,
  ),
  _EpubTestCase(
    assetPath: 'test/fixtures/sample.epub',
    fileName: 'sample.epub',
    expectedTitle: null, // sample.epub title 不強制鎖定，以對比表為準
    expectedAuthor: null,
    expectedIdentifier: 'urn:uuid:00000000-0000-0000-0000-000000000001',
    expectedIsFixedLayout: false,
    expectedHasCover: true,
  ),
  _EpubTestCase(
    assetPath: 'test/fixtures/sample_fxl_svg_cover.epub',
    fileName: 'sample_fxl_svg_cover.epub',
    expectedTitle: null,
    expectedAuthor: null,
    expectedIdentifier: null,
    expectedIsFixedLayout: true,
    expectedHasCover: true,
  ),
];

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Windows HeadlessInAppWebView 解析 13 份 EPUB metadata', (
    tester,
  ) async {
    final appSupport = await getApplicationSupportDirectory();
    await initAppWebViewEnvironment(userDataFolder: appSupport.path);

    final stagedPaths = <String>[];
    addTearDown(() async {
      for (final p in stagedPaths) {
        final f = File(p);
        if (await f.exists()) await f.delete();
      }
    });

    for (final tc in _testCases) {
      final staged = await _stageAssetAsFile(tc.assetPath, 'test_${tc.fileName}');
      stagedPaths.add(staged);

      final metadata = await extractWindowsBookMetadata(staged, 'epub');
      expect(metadata, isNotNull, reason: '${tc.fileName} 解析結果不應為 null');

      if (tc.expectedTitle != null) {
        expect(metadata!['title'], equals(tc.expectedTitle), reason: '${tc.fileName} title');
      }
      if (tc.expectedAuthor != null) {
        expect(metadata!['author'], equals(tc.expectedAuthor), reason: '${tc.fileName} author');
      }
      if (tc.expectedIdentifier != null) {
        expect(metadata!['identifier'], equals(tc.expectedIdentifier), reason: '${tc.fileName} identifier');
      }
      expect(
        metadata!['isFixedLayout'],
        equals(tc.expectedIsFixedLayout),
        reason: '${tc.fileName} isFixedLayout',
      );

      final coverBytes = metadata['coverBytes'] as Uint8List?;
      final hasCover = coverBytes != null && coverBytes.isNotEmpty;
      expect(hasCover, equals(tc.expectedHasCover), reason: '${tc.fileName} hasCover');

      // 印出供 Task 6 對比的 JSON 格式
      final comparisonPayload = jsonEncode({
        'title': metadata['title'],
        'author': metadata['author'],
        'identifier': metadata['identifier'],
        'isFixedLayout': metadata['isFixedLayout'],
        'coverSize': coverBytes?.length ?? 0,
      });
      // ignore: avoid_print
      print('[metadata_comparison] ${tc.fileName} $comparisonPayload');
    }

    // 隨機位元組組成的 .epub 檔案：丟 PlatformException
    final tempDir = await getTemporaryDirectory();
    final corruptPath = p.join(tempDir.path, 'corrupt_probe.epub');
    await File(corruptPath).writeAsBytes(List.filled(1024, 0xAA));
    stagedPaths.add(corruptPath);

    expect(
      () => extractWindowsBookMetadata(corruptPath, 'epub'),
      throwsA(
        isA<PlatformException>().having(
          (e) => e.code,
          'code',
          'extraction_failed',
        ),
      ),
    );

    // readEpubMetadataInWebView 逾時測試（timeout: 1ms 必定逾時）：丟 TimeoutException
    final validStaged = stagedPaths.first;
    expect(
      () => readEpubMetadataInWebView(
        validStaged,
        timeout: const Duration(milliseconds: 1),
      ),
      throwsA(isA<TimeoutException>()),
    );

    // 不存在的路徑：extractWindowsBookMetadata 丟 PlatformException
    expect(
      () => extractWindowsBookMetadata(
        p.join(tempDir.path, 'does_not_exist.epub'),
        'epub',
      ),
      throwsA(
        isA<PlatformException>().having(
          (e) => e.code,
          'code',
          'extraction_failed',
        ),
      ),
    );

    // 逾時案例之後，再對 meta_basic.epub 呼叫一次仍成功（前一個 headless WebView 已正確釋放）
    final retryMetadata = await extractWindowsBookMetadata(validStaged, 'epub');
    expect(retryMetadata, isNotNull);
    expect(retryMetadata!['title'], equals('基本書名'));
  });
}
