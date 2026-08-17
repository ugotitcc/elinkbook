import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/remote/opds_feed_parser.dart';
import 'package:elinkbook/remote/opds_types.dart';

const _sampleFeedXml = '''<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <title>家用 NAS 書庫</title>
  <link rel="next" href="/opds/page2"/>
  <entry>
    <title>作者分類</title>
    <link rel="subsection" href="/opds/by-author"
          type="application/atom+xml;profile=opds-catalog;kind=navigation"/>
  </entry>
  <entry>
    <id>urn:calibre:book-1</id>
    <title>紅樓夢</title>
    <author><name>曹雪芹</name></author>
    <link rel="http://opds-spec.org/image/thumbnail" href="/opds/cover/1.jpg"/>
    <link rel="http://opds-spec.org/acquisition" type="application/epub+zip"
          href="download/1.epub" length="123456"/>
    <link rel="http://opds-spec.org/acquisition" type="application/pdf"
          href="http://192.168.1.100:8080/opds/download/1.pdf" length="654321"/>
  </entry>
  <entry>
    <id>urn:calibre:book-2</id>
    <title>不支援格式的書</title>
    <link rel="http://opds-spec.org/acquisition" type="application/vnd.ms-word"
          href="download/2.doc"/>
  </entry>
  <entry>
    <id>urn:calibre:book-3</id>
    <title>不支援格式的書</title>
    <link rel="http://opds-spec.org/acquisition" type="application/epub+zip"
          href="download/3.epub"/>
  </entry>
</feed>''';

void main() {
  late OpdsFeedParser parser;
  final feedUri = Uri.parse('http://192.168.1.100:8080/opds/root');

  setUp(() {
    parser = const OpdsFeedParser();
  });

  test('解析 feed 標題與分頁 next 連結，相對路徑轉為絕對 URL', () {
    final feed = parser.parse(_sampleFeedXml, feedUri);
    expect(feed.title, '家用 NAS 書庫');
    expect(feed.nextUrl, 'http://192.168.1.100:8080/opds/page2');
    expect(feed.prevUrl, isNull);
  });

  test('分類導覽條目（subsection）被歸類到 navigationLinks，href 轉為絕對 URL', () {
    final feed = parser.parse(_sampleFeedXml, feedUri);
    expect(feed.navigationLinks, [
      const OpdsNavigationLink(
        title: '作者分類',
        href: 'http://192.168.1.100:8080/opds/by-author',
      ),
    ]);
  });

  test('書目條目正確解析 id/title/author/縮圖（相對路徑轉絕對）', () {
    final feed = parser.parse(_sampleFeedXml, feedUri);
    final book = feed.entries.firstWhere((e) => e.remoteBookId == 'urn:calibre:book-1');
    expect(book.title, '紅樓夢');
    expect(book.author, '曹雪芹');
    expect(book.thumbnailUrl, 'http://192.168.1.100:8080/opds/cover/1.jpg');
  });

  test('同一書目多個 acquisition 連結皆被解析，相對與絕對路徑皆正確保留/轉換', () {
    final feed = parser.parse(_sampleFeedXml, feedUri);
    final book = feed.entries.firstWhere((e) => e.remoteBookId == 'urn:calibre:book-1');
    expect(book.acquisitions, [
      const OpdsAcquisition(
        href: 'http://192.168.1.100:8080/opds/download/1.epub',
        format: BookFileFormat.epub,
        sizeBytes: 123456,
      ),
      const OpdsAcquisition(
        href: 'http://192.168.1.100:8080/opds/download/1.pdf',
        format: BookFileFormat.pdf,
        sizeBytes: 654321,
      ),
    ]);
  });

  test('不支援的 MIME type 時 format 為 null', () {
    final feed = parser.parse(_sampleFeedXml, feedUri);
    final book = feed.entries.firstWhere((e) => e.remoteBookId == 'urn:calibre:book-2');
    expect(book.acquisitions.single.format, isNull);
  });

  test('〔審查 Finding 2〕MIME type 無法辨識時退回看 href 副檔名（含查詢字串，不誤判）', () {
    const xml = '''<?xml version="1.0"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <title>格式退回測試</title>
  <entry>
    <id>urn:calibre:book-4</id>
    <title>MIME 遺失但副檔名可辨識</title>
    <link rel="http://opds-spec.org/acquisition" type="application/octet-stream"
          href="download/4.epub?token=abc123"/>
  </entry>
</feed>''';
    final feed = parser.parse(xml, feedUri);
    final book = feed.entries.single;
    expect(book.acquisitions.single.format, BookFileFormat.epub);
    expect(book.acquisitions.single.href,
        'http://192.168.1.100:8080/opds/download/4.epub?token=abc123');
  });

  test('〔審查 Finding 2〕MIME type 與副檔名皆無法辨識時 format 仍為 null', () {
    const xml = '''<?xml version="1.0"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <title>格式退回測試</title>
  <entry>
    <id>urn:calibre:book-5</id>
    <title>兩者皆無法辨識</title>
    <link rel="http://opds-spec.org/acquisition" type="application/octet-stream"
          href="download/5.mobi"/>
  </entry>
</feed>''';
    final feed = parser.parse(xml, feedUri);
    expect(feed.entries.single.acquisitions.single.format, isNull);
  });

  test('〔審查 Finding 4〕href 前後帶空白字元時 trim() 後仍正確解析為絕對 URL', () {
    const xml = '''<?xml version="1.0"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <title>空白字元測試</title>
  <entry>
    <id>urn:calibre:book-6</id>
    <title>href 帶空白</title>
    <link rel="http://opds-spec.org/image/thumbnail" href=" /opds/cover/6.jpg "/>
    <link rel="http://opds-spec.org/acquisition" type="application/epub+zip"
          href=" download/6.epub "/>
  </entry>
</feed>''';
    final feed = parser.parse(xml, feedUri);
    final book = feed.entries.single;
    expect(book.thumbnailUrl, 'http://192.168.1.100:8080/opds/cover/6.jpg');
    expect(book.acquisitions.single.href, 'http://192.168.1.100:8080/opds/download/6.epub');
  });

  test('缺少 <title> 的書目條目容錯，退回顯示「未知書名」，不拋出例外', () {
    const xml = '''<?xml version="1.0"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <title>缺標題測試</title>
  <entry>
    <id>urn:calibre:book-no-title</id>
    <link rel="http://opds-spec.org/acquisition" type="application/epub+zip"
          href="download/no-title.epub"/>
  </entry>
</feed>''';
    final feed = parser.parse(xml, feedUri);
    final book = feed.entries.single;
    expect(book.title, '未知書名');
    expect(book.author, isNull);
  });

  test('缺少 length 屬性時 sizeBytes 為 null，不拋出例外', () {
    final feed = parser.parse(_sampleFeedXml, feedUri);
    final book = feed.entries.firstWhere((e) => e.remoteBookId == 'urn:calibre:book-3');
    expect(book.acquisitions.single.sizeBytes, isNull);
  });

  test('沒有 next 連結時 nextUrl 為 null', () {
    const xml = '''<?xml version="1.0"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <title>空書庫</title>
</feed>''';
    final feed = parser.parse(xml, feedUri);
    expect(feed.nextUrl, isNull);
    expect(feed.entries, isEmpty);
    expect(feed.navigationLinks, isEmpty);
  });
}
