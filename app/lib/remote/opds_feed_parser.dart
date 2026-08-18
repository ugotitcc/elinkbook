import 'package:xml/xml.dart';

import '../library/models/library_enums.dart';
import 'opds_types.dart';

/// 純 Dart、無網路依賴的 OPDS Atom XML 解析器（epic-30-calibre-remote-library
/// Issue 1，spec.md「OPDS 瀏覽與下載：OpdsClient」）。所有 `href`
/// （Acquisition／縮圖／導覽／分頁）皆以 [feedUri] 為基準呼叫
/// `Uri.resolve()` 轉為絕對 URL，`review-spec.md` Important #1 已核實
/// 採納——標準 OPDS Feed 的 `href` 常為相對路徑，呼叫端拿到的 [OpdsFeed]
/// 保證不含相對路徑，不需要也不應該自行處理。
///
/// 解析失敗容錯：缺失 `<title>` 時退回「未知書名」／「未命名分類」，
/// 缺失作者時 `author` 為 `null`，格式不規範的欄位跳過不拋例外——維持
/// 既有匯入流程「降級但不中斷」的一貫風格（比照
/// `book_import_service_impl.dart` 對外部詮釋資料缺失的既有處理慣例）。
class OpdsFeedParser {
  const OpdsFeedParser();

  OpdsFeed parse(String xmlString, Uri feedUri) {
    final document = XmlDocument.parse(xmlString);
    final feed = document.rootElement;

    final title = _firstText(feed, 'title') ?? feedUri.toString();

    String? nextUrl;
    String? prevUrl;
    final navigationLinks = <OpdsNavigationLink>[];
    for (final link in feed.findElements('link')) {
      final rel = link.getAttribute('rel');
      final href = link.getAttribute('href');
      if (href == null) continue;
      if (rel == 'next') nextUrl = _resolve(feedUri, href);
      if (rel == 'previous' || rel == 'prev') prevUrl = _resolve(feedUri, href);
      // Calibre 等伺服器的根 OPDS feed 會把分類導覽連結直接放在
      // <feed> 根層級的 <link rel="subsection"> 裡（而非 <entry> 內）。
      if (rel == 'subsection') {
        final title = link.getAttribute('title') ?? '未命名分類';
        navigationLinks.add(OpdsNavigationLink(
          title: title,
          href: _resolve(feedUri, href),
        ));
      }
    }

    final entries = <OpdsEntry>[];

    for (final entry in feed.findElements('entry')) {
      final entryLinks = entry.findElements('link').toList();
      final acquisitionLinks = entryLinks
          .where((l) =>
              (l.getAttribute('rel') ?? '').startsWith('http://opds-spec.org/acquisition'))
          .toList();

      if (acquisitionLinks.isNotEmpty) {
        entries.add(_parseBookEntry(entry, entryLinks, acquisitionLinks, feedUri));
        continue;
      }

      // 導覽分類連結：優先找 rel="subsection"；其次找 type 屬性含
      // kind=navigation（Calibre 分類 entry 實際採用的型別字串，見真機
      // 驗證樣本 `reviews/review-issue-5.md`）；最後才退回「第一個有
      // href、且 rel 不是已知非導覽用途」的 link——`review-issue-5-code.md`
      // Important #1 指出，原本不分 rel 一律取第一個有 href 的 link，
      // 會誤把 rel="self"／"alternate"／"search" 或縮圖連結當成導覽分類。
      const nonNavigationRels = {
        'self',
        'alternate',
        'search',
        'http://opds-spec.org/image',
        'http://opds-spec.org/image/thumbnail',
      };
      final subsectionLink =
          _firstWhereOrNull(entryLinks, (l) => l.getAttribute('rel') == 'subsection');
      final navigationTypeLink = subsectionLink ??
          _firstWhereOrNull(entryLinks,
              (l) => (l.getAttribute('type') ?? '').contains('kind=navigation'));
      final navLink = navigationTypeLink ??
          _firstWhereOrNull(
              entryLinks,
              (l) =>
                  l.getAttribute('href') != null &&
                  !nonNavigationRels.contains(l.getAttribute('rel') ?? ''));
      final navHref = navLink?.getAttribute('href');
      if (navHref != null) {
        navigationLinks.add(OpdsNavigationLink(
          title: _firstText(entry, 'title') ?? '未命名分類',
          href: _resolve(feedUri, navHref),
        ));
      }
    }

    return OpdsFeed(
      title: title,
      nextUrl: nextUrl,
      prevUrl: prevUrl,
      navigationLinks: navigationLinks,
      entries: entries,
    );
  }

  OpdsEntry _parseBookEntry(
    XmlElement entry,
    List<XmlElement> entryLinks,
    List<XmlElement> acquisitionLinks,
    Uri feedUri,
  ) {
    final entryTitle = _firstText(entry, 'title') ?? '未知書名';
    final authorElement = _firstWhereOrNull(entry.findElements('author'), (_) => true);
    final author = authorElement == null ? null : _firstText(authorElement, 'name');
    final remoteBookId = _firstText(entry, 'id') ?? entryTitle;

    final thumbnailLink = _firstWhereOrNull(entryLinks, (l) {
      final rel = l.getAttribute('rel') ?? '';
      return rel == 'http://opds-spec.org/image' ||
          rel == 'http://opds-spec.org/image/thumbnail';
    });
    final thumbnailHref = thumbnailLink?.getAttribute('href');

    final acquisitions = acquisitionLinks
        .map((l) {
          final href = l.getAttribute('href');
          if (href == null) return null;
          final resolvedHref = _resolve(feedUri, href);
          return OpdsAcquisition(
            href: resolvedHref,
            format: _detectFormat(l.getAttribute('type'), resolvedHref),
            sizeBytes: int.tryParse(l.getAttribute('length') ?? ''),
          );
        })
        .whereType<OpdsAcquisition>()
        .toList();

    return OpdsEntry(
      remoteBookId: remoteBookId,
      title: entryTitle,
      author: author,
      thumbnailUrl: thumbnailHref == null ? null : _resolve(feedUri, thumbnailHref),
      acquisitions: acquisitions,
    );
  }

  String? _firstText(XmlElement parent, String name) {
    final elements = parent.findElements(name);
    if (elements.isEmpty) return null;
    final text = elements.first.innerText.trim();
    return text.isEmpty ? null : text;
  }

  XmlElement? _firstWhereOrNull(
    Iterable<XmlElement> elements,
    bool Function(XmlElement) test,
  ) {
    for (final element in elements) {
      if (test(element)) return element;
    }
    return null;
  }

  /// **〔`review-plan-issue-1.md` Finding 4 採納〕** 部分不規範伺服器的
  /// XML `href` 屬性值可能帶有前後空白字元，`trim()` 後再交給
  /// `Uri.resolve()`，避免產生非預期的 URL 編碼或解析例外。
  String _resolve(Uri base, String href) => base.resolve(href.trim()).toString();

  /// **〔`review-plan-issue-1.md` Finding 2 採納〕** 依 `spec.md:138`
  /// 「格式過濾」規範：先比對 MIME type，比對不到已知 MIME type 時退回
  /// 看 `href` 副檔名；皆無法判斷才回傳 `null`（MOBI 等真正不支援的
  /// 格式落在這裡）。[href] 傳入時已經過 [_resolve] 正規化為絕對 URL，
  /// 用 `Uri.tryParse(href)?.path` 只取路徑部分再判斷副檔名——不能直接
  /// 對整個 URL 字串做 `endsWith()`，OPDS 下載連結常帶簽章/權杖查詢
  /// 字串（例如 `download/1.epub?token=abc`），直接比對整串會誤判。
  BookFileFormat? _detectFormat(String? mimeType, String href) {
    final fromMime = _formatFromMimeType(mimeType);
    if (fromMime != null) return fromMime;
    final path = Uri.tryParse(href)?.path ?? href;
    final lowerPath = path.toLowerCase();
    if (lowerPath.endsWith('.epub')) return BookFileFormat.epub;
    if (lowerPath.endsWith('.pdf')) return BookFileFormat.pdf;
    if (lowerPath.endsWith('.txt')) return BookFileFormat.txt;
    if (lowerPath.endsWith('.azw3')) return BookFileFormat.azw3;
    if (lowerPath.endsWith('.cbz')) return BookFileFormat.cbz;
    if (lowerPath.endsWith('.md')) return BookFileFormat.md;
    return null;
  }

  BookFileFormat? _formatFromMimeType(String? mimeType) {
    switch (mimeType) {
      case 'application/epub+zip':
        return BookFileFormat.epub;
      case 'application/pdf':
        return BookFileFormat.pdf;
      case 'text/plain':
        return BookFileFormat.txt;
      case 'application/x-mobipocket-ebook':
      case 'application/vnd.amazon.ebook':
        return BookFileFormat.azw3;
      case 'application/vnd.comicbook+zip':
      case 'application/x-cbz':
        return BookFileFormat.cbz;
      case 'text/markdown':
        return BookFileFormat.md;
      default:
        return null;
    }
  }
}
