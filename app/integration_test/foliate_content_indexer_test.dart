// app/integration_test/foliate_content_indexer_test.dart
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/search/foliate_content_indexer.dart';

Future<String> _stageAssetAsFile(String assetPath, String fileName) async {
  final bytes = await rootBundle.load(assetPath);
  final tempDir = await getTemporaryDirectory();
  final file = File('${tempDir.path}/$fileName');
  await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
  return file.path;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'FoliateContentIndexer 對 3 章節 EPUB fixture 正確擷取每章句子與 CFI',
      (tester) async {
    // test/fixtures/sample_multi_chapter.epub：3 個 spine section
    // （chapter1/2/3.xhtml），內容已知（見 plan-issue-1.md 規劃階段查證）：
    // 第 1 章 8 段、第 2 章 16 段（含第一節/第二節）、第 3 章 8 段，各段
    // 皆含「這是第 N 章第 M 段內容」字樣，三章內容彼此明顯不同。
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample_multi_chapter.epub', 'foliate_indexer_integration.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    final book = Book(
      id: 'foliate-indexer-test-book',
      title: '索引器整合測試書',
      format: BookFileFormat.epub,
      filePath: samplePath,
      source: BookSource.local,
      createTime: DateTime(2026, 1, 1),
      lastReadTime: DateTime(2026, 1, 1),
    );

    const indexer = FoliateContentIndexer();
    final segments = await indexer.indexBook(book).toList();

    expect(segments, isNotEmpty);
    expect(segments.map((s) => s.chapterIndex).toSet(), {0, 1, 2},
        reason: '3 個 spine section，chapterIndex 應涵蓋 0-2');

    for (final segment in segments) {
      expect(segment.locator, startsWith('epubcfi('),
          reason: 'Foliate 格式 locator 必須是合法 CFI 字串');
      expect(segment.rawText.trim(), isNotEmpty);
    }

    final textBySection = <int, String>{};
    for (final segment in segments) {
      textBySection[segment.chapterIndex] =
          (textBySection[segment.chapterIndex] ?? '') + segment.rawText;
    }
    expect(textBySection[0], contains('第 1 章'));
    expect(textBySection[1], contains('第 2 章'));
    expect(textBySection[2], contains('第 3 章'));
  });

  testWidgets('FoliateContentIndexer resumeFromChapter 只從指定 section（含）開始擷取',
      (tester) async {
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample_multi_chapter.epub', 'foliate_indexer_resume.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    final book = Book(
      id: 'foliate-indexer-resume-book',
      title: '索引器續跑測試書',
      format: BookFileFormat.epub,
      filePath: samplePath,
      source: BookSource.local,
      createTime: DateTime(2026, 1, 1),
      lastReadTime: DateTime(2026, 1, 1),
    );

    const indexer = FoliateContentIndexer();
    final segments =
        await indexer.indexBook(book, resumeFromChapter: 2).toList();

    expect(segments, isNotEmpty);
    expect(segments.map((s) => s.chapterIndex).toSet(), {2});
    expect(
      segments.map((s) => s.rawText).join(),
      contains('第 3 章'),
    );
  });
}
