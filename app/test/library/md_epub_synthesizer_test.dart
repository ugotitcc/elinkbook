// app/test/library/md_epub_synthesizer_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:xml/xml.dart';
import 'package:elinkbook/library/md_epub_synthesizer.dart';

import '../support/fake_path_provider_platform.dart';

const _channel = MethodChannel('elinkbook/book_metadata');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Archive decodeArchive(MdSynthesisResult result) => ZipDecoder().decodeBytes(result.epubBytes);

  String readEntry(Archive archive, String name) =>
      utf8.decode(archive.findFile(name)!.readBytes()!);

  test('合成結果為結構正確的 EPUB：container.xml 指向 OEBPS/content.opf', () async {
    final mdFile = File('${Directory.systemTemp.path}/synth_md_basic.md');
    await mdFile.writeAsBytes(utf8.encode('# 第一章\n內容一\n\n# 第二章\n內容二'));
    addTearDown(() => mdFile.delete());

    final result = await synthesizeMdBook(mdFile.path, 'book1', '備用標題');
    final archive = decodeArchive(result);

    expect(archive.findFile('mimetype'), isNotNull);
    final containerDoc = XmlDocument.parse(readEntry(archive, 'META-INF/container.xml'));
    expect(containerDoc.findAllElements('rootfile').single.getAttribute('full-path'), 'OEBPS/content.opf');
  });

  test('沒有 Frontmatter 時，OPF 的 dc:title 使用呼叫端傳入的備用標題', () async {
    final mdFile = File('${Directory.systemTemp.path}/synth_md_fallback_title.md');
    await mdFile.writeAsBytes(utf8.encode('# 內容\n沒有 frontmatter'));
    addTearDown(() => mdFile.delete());

    final result = await synthesizeMdBook(mdFile.path, 'book2', '備用標題');
    final archive = decodeArchive(result);
    final opfDoc = XmlDocument.parse(readEntry(archive, 'OEBPS/content.opf'));

    expect(opfDoc.findAllElements('dc:title').single.innerText, '備用標題');
    expect(result.frontmatterTitle, isNull);
  });

  test('有 Frontmatter 時，OPF 的 dc:title 優先使用 Frontmatter 標題', () async {
    final mdFile = File('${Directory.systemTemp.path}/synth_md_fm_title.md');
    await mdFile.writeAsBytes(
      utf8.encode('---\ntitle: Frontmatter 標題\nauthor: 作者甲\n---\n# 內容\n正文'),
    );
    addTearDown(() => mdFile.delete());

    final result = await synthesizeMdBook(mdFile.path, 'book3', '備用標題');
    final archive = decodeArchive(result);
    final opfDoc = XmlDocument.parse(readEntry(archive, 'OEBPS/content.opf'));

    expect(opfDoc.findAllElements('dc:title').single.innerText, 'Frontmatter 標題');
    expect(result.frontmatterTitle, 'Frontmatter 標題');
    expect(result.frontmatterAuthor, '作者甲');
  });

  test('多個 H1 各自產生獨立的 XHTML spine 項目與扁平目錄項', () async {
    final mdFile = File('${Directory.systemTemp.path}/synth_md_sections.md');
    await mdFile.writeAsBytes(utf8.encode('# 第一章\n內容一\n\n# 第二章\n內容二'));
    addTearDown(() => mdFile.delete());

    final result = await synthesizeMdBook(mdFile.path, 'book4', '備用標題');
    final archive = decodeArchive(result);
    final opfDoc = XmlDocument.parse(readEntry(archive, 'OEBPS/content.opf'));
    final navDoc = XmlDocument.parse(readEntry(archive, 'OEBPS/nav.xhtml'));

    expect(
      opfDoc.findAllElements('item').where((e) => e.getAttribute('href')?.startsWith('text/') ?? false),
      hasLength(2),
    );
    final links = navDoc.findAllElements('a').toList();
    expect(links.map((e) => e.innerText), ['第一章', '第二章']);
  });

  test('巢狀標題（H1 下有 H2）產生巢狀 <ol> 目錄結構', () async {
    final mdFile = File('${Directory.systemTemp.path}/synth_md_nested_toc.md');
    await mdFile.writeAsBytes(utf8.encode('# 第一章\n## 子章節 A\n內容\n## 子章節 B\n內容'));
    addTearDown(() => mdFile.delete());

    final result = await synthesizeMdBook(mdFile.path, 'book5', '備用標題');
    final archive = decodeArchive(result);
    final navDoc = XmlDocument.parse(readEntry(archive, 'OEBPS/nav.xhtml'));

    final topLevelOl = navDoc.findAllElements('nav').single.findElements('ol').single;
    final topLevelItems = topLevelOl.findElements('li');
    expect(topLevelItems, hasLength(1)); // 只有「第一章」在頂層
    final nestedOl = topLevelItems.single.findElements('ol').single;
    expect(nestedOl.findElements('li').map((e) => e.findElements('a').single.innerText),
        ['子章節 A', '子章節 B']);
  });

  test('章節內文含標題錨點 id，與目錄連結的 # 片段一致', () async {
    final mdFile = File('${Directory.systemTemp.path}/synth_md_anchor.md');
    await mdFile.writeAsBytes(utf8.encode('# 第一章\n內容'));
    addTearDown(() => mdFile.delete());

    final result = await synthesizeMdBook(mdFile.path, 'book6', '備用標題');
    final archive = decodeArchive(result);
    final navDoc = XmlDocument.parse(readEntry(archive, 'OEBPS/nav.xhtml'));
    final href = navDoc.findAllElements('a').single.getAttribute('href')!;
    final parts = href.split('#');
    expect(parts, hasLength(2));

    final chapterDoc = XmlDocument.parse(readEntry(archive, 'OEBPS/${parts[0]}'));
    final heading = chapterDoc.findAllElements('h1').single;
    expect(heading.getAttribute('id'), parts[1]);
  });

  test('程式碼區塊與表格的 XHTML 內含強制橫排的 <style> 規則', () async {
    final mdFile = File('${Directory.systemTemp.path}/synth_md_code_table.md');
    await mdFile.writeAsBytes(utf8.encode(
      '# 第一章\n```python\nprint(1)\n```\n\n| A | B |\n| --- | --- |\n| 1 | 2 |',
    ));
    addTearDown(() => mdFile.delete());

    final result = await synthesizeMdBook(mdFile.path, 'book7', '備用標題');
    final archive = decodeArchive(result);
    final opfDoc = XmlDocument.parse(readEntry(archive, 'OEBPS/content.opf'));
    final href = opfDoc
        .findAllElements('item')
        .firstWhere((e) => e.getAttribute('href')?.startsWith('text/') ?? false)
        .getAttribute('href')!;
    final chapterXhtmlRaw = readEntry(archive, 'OEBPS/$href');

    expect(chapterXhtmlRaw, contains('writing-mode: horizontal-tb'));
    expect(chapterXhtmlRaw, contains('direction: ltr'));
    final chapterDoc = XmlDocument.parse(chapterXhtmlRaw);
    expect(chapterDoc.findAllElements('pre'), isNotEmpty);
    expect(chapterDoc.findAllElements('table'), isNotEmpty);
  });

  test('XML 特殊字元（&/</>）在標題與內文中正確逸出，可被正常解析', () async {
    final mdFile = File('${Directory.systemTemp.path}/synth_md_escape.md');
    await mdFile.writeAsBytes(utf8.encode('# A&B<C>\n內容含 & < > 符號'));
    addTearDown(() => mdFile.delete());

    final result = await synthesizeMdBook(mdFile.path, 'book8', '備用標題');
    final archive = decodeArchive(result);
    final navDoc = XmlDocument.parse(readEntry(archive, 'OEBPS/nav.xhtml'));
    expect(navDoc.findAllElements('a').single.innerText, 'A&B<C>');
  });

  test('Frontmatter cover 為 data: URI 時正確回傳於 frontmatterCoverBytes', () async {
    final pngBytes = [0x89, 0x50, 0x4E, 0x47];
    final base64Data = base64Encode(pngBytes);
    final mdFile = File('${Directory.systemTemp.path}/synth_md_cover.md');
    await mdFile.writeAsBytes(
      utf8.encode('---\ntitle: 有封面\ncover: data:image/png;base64,$base64Data\n---\n# 內容\n正文'),
    );
    addTearDown(() => mdFile.delete());

    final result = await synthesizeMdBook(mdFile.path, 'book9', '備用標題');

    expect(result.frontmatterCoverBytes, pngBytes);
  });

  test('空白 Markdown 檔案（去除 Frontmatter 後無實際內容）拋出 EmptyMdException', () async {
    final mdFile = File('${Directory.systemTemp.path}/synth_md_empty.md');
    await mdFile.writeAsBytes(utf8.encode('---\ntitle: 空內容\n---\n   \n\n   '));
    addTearDown(() => mdFile.delete());

    expect(
      () => synthesizeMdBook(mdFile.path, 'book10', '備用標題'),
      throwsA(isA<EmptyMdException>()),
    );
  });

  group('content:// URI 支援', () {
    late Directory tempDir;
    late PathProviderPlatform originalPathProvider;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('md_synth_test_tmp');
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
        final args = call.arguments as Map;
        await File(args['destinationPath'] as String).writeAsBytes(utf8.encode('# 內容\n正文'));
        return null;
      });

      final result = await synthesizeMdBook('content://example/note.md', 'book11', '備用標題');
      final archive = decodeArchive(result);

      expect(archive.findFile('OEBPS/content.opf'), isNotNull);
    });
  });
}
