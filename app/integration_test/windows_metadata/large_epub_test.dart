// 224 MB 大檔 EPUB 詮釋資料提取與記憶體量測測試（epic-66 Issue 2 Task 7）。
//
// 驗證 224 MB 大書在 Windows HeadlessInAppWebView 能正常提取 metadata，
// 並輸出執行耗時、標題、作者、識別碼與封面大小。
//
// 執行方式：
// cd app && flutter test integration_test/windows_metadata/large_epub_test.dart -d windows

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

import 'package:elinkbook/library/windows_book_metadata.dart';
import 'package:elinkbook/windows/windows_webview_environment.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Windows HeadlessInAppWebView 解析 224 MB EPUB metadata', (
    tester,
  ) async {
    const largeBookPath = r'U:\05電子書\IT\AI世界的底層邏輯與生存法則.epub';
    if (!File(largeBookPath).existsSync()) {
      // ignore: avoid_print
      print('[large_epub_test] 本機環境無 $largeBookPath，略過實體大書測試');
      return;
    }

    final appSupport = await getApplicationSupportDirectory();
    await initAppWebViewEnvironment(userDataFolder: appSupport.path);

    final stopwatch = Stopwatch()..start();
    // ignore: avoid_print
    print('[large_epub_test] 開始解析 224 MB EPUB metadata: $largeBookPath');

    final metadata = await extractWindowsBookMetadata(
      largeBookPath,
      'epub',
    );

    stopwatch.stop();
    expect(metadata, isNotNull, reason: '解析結果不應為 null');

    final title = metadata!['title'];
    final author = metadata['author'];
    final identifier = metadata['identifier'];
    final isFixedLayout = metadata['isFixedLayout'];
    final coverBytes = metadata['coverBytes'];
    final coverSize = coverBytes is List ? coverBytes.length : 0;

    // ignore: avoid_print
    print('[large_epub_test] 解析完成！耗時: ${stopwatch.elapsedMilliseconds} ms');
    // ignore: avoid_print
    print('[large_epub_test] title: $title');
    // ignore: avoid_print
    print('[large_epub_test] author: $author');
    // ignore: avoid_print
    print('[large_epub_test] identifier: $identifier');
    // ignore: avoid_print
    print('[large_epub_test] isFixedLayout: $isFixedLayout');
    // ignore: avoid_print
    print('[large_epub_test] coverSize: $coverSize bytes');

    expect(title, isNotNull);
  });
}
