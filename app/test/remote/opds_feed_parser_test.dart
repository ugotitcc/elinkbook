import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/remote/opds_feed_parser.dart';
import 'package:elinkbook/remote/opds_types.dart';

// 解析器缺 <title> 時的後備標題由呼叫端依介面語言傳入（epic-45-interface-i18n Issue 10）
const _zhFallback = OpdsFallbackTitles(unknownBook: '未知書名', unnamedCategory: '未命名分類');
const _enFallback = OpdsFallbackTitles(unknownBook: 'Unknown title', unnamedCategory: 'Untitled category');

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
    final feed = parser.parse(_sampleFeedXml, feedUri, fallbackTitles: _zhFallback);
    expect(feed.title, '家用 NAS 書庫');
    expect(feed.nextUrl, 'http://192.168.1.100:8080/opds/page2');
    expect(feed.prevUrl, isNull);
  });

  test('分類導覽條目（subsection）被歸類到 navigationLinks，href 轉為絕對 URL', () {
    final feed = parser.parse(_sampleFeedXml, feedUri, fallbackTitles: _zhFallback);
    expect(feed.navigationLinks, [
      const OpdsNavigationLink(
        title: '作者分類',
        href: 'http://192.168.1.100:8080/opds/by-author',
      ),
    ]);
  });

  test('書目條目正確解析 id/title/author/縮圖（相對路徑轉絕對）', () {
    final feed = parser.parse(_sampleFeedXml, feedUri, fallbackTitles: _zhFallback);
    final book = feed.entries.firstWhere((e) => e.remoteBookId == 'urn:calibre:book-1');
    expect(book.title, '紅樓夢');
    expect(book.author, '曹雪芹');
    expect(book.thumbnailUrl, 'http://192.168.1.100:8080/opds/cover/1.jpg');
  });

  test('同一書目多個 acquisition 連結皆被解析，相對與絕對路徑皆正確保留/轉換', () {
    final feed = parser.parse(_sampleFeedXml, feedUri, fallbackTitles: _zhFallback);
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
    final feed = parser.parse(_sampleFeedXml, feedUri, fallbackTitles: _zhFallback);
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
    final feed = parser.parse(xml, feedUri, fallbackTitles: _zhFallback);
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
    final feed = parser.parse(xml, feedUri, fallbackTitles: _zhFallback);
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
    final feed = parser.parse(xml, feedUri, fallbackTitles: _zhFallback);
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
    final feed = parser.parse(xml, feedUri, fallbackTitles: _zhFallback);
    final book = feed.entries.single;
    expect(book.title, '未知書名');
    expect(book.author, isNull);
  });

  test('缺少 <title> 時使用呼叫端傳入的後備標題（依介面語言），不寫死在解析器內', () {
    const xml = '''<?xml version="1.0"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <title>缺標題測試</title>
  <link rel="subsection" href="/opds/root-cat"/>
  <entry>
    <id>urn:no-title-cat</id>
    <link rel="subsection" href="/opds/entry-cat"/>
  </entry>
  <entry>
    <id>urn:calibre:book-no-title</id>
    <link rel="http://opds-spec.org/acquisition" type="application/epub+zip"
          href="download/no-title.epub"/>
  </entry>
</feed>''';
    final feed = parser.parse(xml, feedUri, fallbackTitles: _enFallback);
    expect(feed.navigationLinks.map((l) => l.title), everyElement('Untitled category'));
    expect(feed.navigationLinks, hasLength(2));
    expect(feed.entries.single.title, 'Unknown title');
  });

  test('書目缺 <title> 也缺 <id> 時，remoteBookId 為固定識別字，不隨後備標題的語言改變', () {
    // remoteBookId 是持久化的去重鍵（見 RemoteDownloadJob.id），若跟著介面語言變動，
    // 同一本書切換語言後會被當成不同的書。
    const xml = '''<?xml version="1.0"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <title>缺標題與 id</title>
  <entry>
    <link rel="http://opds-spec.org/acquisition" type="application/epub+zip"
          href="download/x.epub"/>
  </entry>
</feed>''';
    final zh = parser.parse(xml, feedUri, fallbackTitles: _zhFallback).entries.single;
    final en = parser.parse(xml, feedUri, fallbackTitles: _enFallback).entries.single;
    expect(en.remoteBookId, zh.remoteBookId);
    expect(zh.title, '未知書名');
    expect(en.title, 'Unknown title');
  });

  test('缺少 length 屬性時 sizeBytes 為 null，不拋出例外', () {
    final feed = parser.parse(_sampleFeedXml, feedUri, fallbackTitles: _zhFallback);
    final book = feed.entries.firstWhere((e) => e.remoteBookId == 'urn:calibre:book-3');
    expect(book.acquisitions.single.sizeBytes, isNull);
  });

  test('根層級 <link rel="subsection"> 被歸類到 navigationLinks（Calibre 模式）', () {
    // Calibre Content Server 的根 OPDS feed 不用 <entry> 包分類，
    // 而是在 <feed> 根層級放 <link rel="subsection"> 連結。
    const xml = '''<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom" xmlns:opds="http://opds-spec.org/2010/catalog">
  <title>calibre 書庫</title>
  <link rel="subsection" href="/opds?library_id=Lib" title="書本在您的書庫"/>
  <link rel="subsection" href="/opds?library_id=Lib&amp;sort=authors" title="依作者"/>
  <link rel="search" title="Search" href="/opds/search/{searchTerms}?library_id=Lib"/>
</feed>''';
    final feed = parser.parse(xml, feedUri, fallbackTitles: _zhFallback);
    expect(feed.navigationLinks, hasLength(2));
    expect(feed.navigationLinks[0].title, '書本在您的書庫');
    expect(feed.navigationLinks[0].href, contains('/opds?library_id=Lib'));
    expect(feed.navigationLinks[1].title, '依作者');
    expect(feed.entries, isEmpty);
  });

  test('Calibre 分類 entry 的 link 不帶 rel 時仍正確解析為導覽連結', () {
    // Calibre Content Server 的分類 <entry> 的 <link> 不帶 rel 屬性，
    // 只有 href + type。Parser 應退回取第一個有 href 的 link。
    const xml = '''<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <title>calibre 書庫</title>
  <entry>
    <title>由 最新</title>
    <id>calibre-navcatalog:abc</id>
    <content type="text">書本排序依 日期</content>
    <link href="/opds/navcatalog/newest?library_id=Library"
          type="application/atom+xml;type=feed;profile=opds-catalog;kind=navigation"/>
  </entry>
  <entry>
    <title>由 書名</title>
    <id>calibre-navcatalog:def</id>
    <content type="text">書本排序依 書名</content>
    <link href="/opds/navcatalog/title?library_id=Library"
          type="application/atom+xml;type=feed;profile=opds-catalog;kind=navigation"/>
  </entry>
</feed>''';
    final feed = parser.parse(xml, feedUri, fallbackTitles: _zhFallback);
    expect(feed.navigationLinks, hasLength(2));
    expect(feed.navigationLinks[0].title, '由 最新');
    expect(feed.navigationLinks[0].href, contains('/opds/navcatalog/newest'));
    expect(feed.navigationLinks[1].title, '由 書名');
    expect(feed.entries, isEmpty);
  });

  test('分類 entry 同時帶有 rel="alternate"/"self" 與無 rel 的導覽連結時，'
      '不會誤把非導覽連結當成分類 href（review-issue-5-code.md Important #1）',
      () {
    // 模擬某些非 Calibre 的 OPDS 伺服器：分類 entry 除了真正的導覽連結
    // 外，還帶有 rel="self"（連回自己）與 rel="alternate"（連到網頁版）
    // 的 <link>，且這些連結排列在真正的導覽連結之前。退回邏輯不能單純
    // 取「第一個有 href 的 link」，否則會誤判為導覽分類。
    const xml = '''<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <title>某書庫</title>
  <entry>
    <title>由 最新</title>
    <id>navcatalog:newest</id>
    <link rel="self" href="/opds/navcatalog/newest?self=1"/>
    <link rel="alternate" type="text/html" href="/browse/newest"/>
    <link href="/opds/navcatalog/newest?library_id=Library"
          type="application/atom+xml;type=feed;profile=opds-catalog;kind=navigation"/>
  </entry>
</feed>''';
    final feed = parser.parse(xml, feedUri, fallbackTitles: _zhFallback);
    expect(feed.navigationLinks, hasLength(1));
    expect(feed.navigationLinks.single.title, '由 最新');
    expect(feed.navigationLinks.single.href, contains('/opds/navcatalog/newest?library_id=Library'),
        reason: '應選中 type 含 kind=navigation 的連結，'
            '而非排列在前面的 rel="self"/"alternate" 連結');
  });

  test('分類 entry 的 link 皆無 rel 也無 kind=navigation type 時，仍退回第一個有 href 的 link',
      () {
    // 確保收斂 rel 白名單後，原本 Calibre「完全無 rel、也無特別 type」
    // 的最小情境（見上方既有測試）以外的邊界案例，退回邏輯依然可用。
    const xml = '''<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <title>某書庫</title>
  <entry>
    <title>由 標籤</title>
    <id>navcatalog:tags</id>
    <link href="/opds/navcatalog/tags?library_id=Library"/>
  </entry>
</feed>''';
    final feed = parser.parse(xml, feedUri, fallbackTitles: _zhFallback);
    expect(feed.navigationLinks, hasLength(1));
    expect(feed.navigationLinks.single.href, contains('/opds/navcatalog/tags'));
  });

  test('沒有 next 連結時 nextUrl 為 null', () {
    const xml = '''<?xml version="1.0"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <title>空書庫</title>
</feed>''';
    final feed = parser.parse(xml, feedUri, fallbackTitles: _zhFallback);
    expect(feed.nextUrl, isNull);
    expect(feed.entries, isEmpty);
    expect(feed.navigationLinks, isEmpty);
  });
}
