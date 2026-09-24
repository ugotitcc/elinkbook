import '../library/models/library_enums.dart';

/// OPDS 目錄一頁的解析結果（epic-30-calibre-remote-library Issue 1，
/// spec.md「OPDS 瀏覽與下載：OpdsClient」）。[nextUrl]/[prevUrl] 若非
/// `null` 保證為絕對 URL（[OpdsFeedParser] 已用 `Uri.resolve()` 正規化）。
class OpdsFeed {
  final String title;
  final String? nextUrl;
  final String? prevUrl;
  final List<OpdsNavigationLink> navigationLinks;
  final List<OpdsEntry> entries;

  const OpdsFeed({
    required this.title,
    this.nextUrl,
    this.prevUrl,
    this.navigationLinks = const [],
    this.entries = const [],
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OpdsFeed &&
          runtimeType == other.runtimeType &&
          title == other.title &&
          nextUrl == other.nextUrl &&
          prevUrl == other.prevUrl &&
          _listEquals(navigationLinks, other.navigationLinks) &&
          _listEquals(entries, other.entries);

  @override
  int get hashCode => Object.hash(
        title,
        nextUrl,
        prevUrl,
        Object.hashAll(navigationLinks),
        Object.hashAll(entries),
      );
}

/// 分類下鑽節點（例如依作者/系列/標籤），對應 OPDS Feed 內
/// `rel="subsection"` 的條目。
class OpdsNavigationLink {
  final String title;
  final String href;

  const OpdsNavigationLink({required this.title, required this.href});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OpdsNavigationLink &&
          runtimeType == other.runtimeType &&
          title == other.title &&
          href == other.href;

  @override
  int get hashCode => Object.hash(title, href);
}

/// 一本書目條目，[remoteBookId] 為 OPDS 條目層級 id（書本身，不分格式，
/// 見 design.md「資料模型」），[acquisitions] 為該書提供的各格式下載
/// 連結。
class OpdsEntry {
  final String remoteBookId;
  final String title;
  final String? author;
  final String? thumbnailUrl;
  final List<OpdsAcquisition> acquisitions;

  const OpdsEntry({
    required this.remoteBookId,
    required this.title,
    this.author,
    this.thumbnailUrl,
    this.acquisitions = const [],
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OpdsEntry &&
          runtimeType == other.runtimeType &&
          remoteBookId == other.remoteBookId &&
          title == other.title &&
          author == other.author &&
          thumbnailUrl == other.thumbnailUrl &&
          _listEquals(acquisitions, other.acquisitions);

  @override
  int get hashCode => Object.hash(
        remoteBookId,
        title,
        author,
        thumbnailUrl,
        Object.hashAll(acquisitions),
      );
}

/// 單一格式的下載連結。[format] 為 `null` 代表 elinkBook 不支援的格式，
/// UI 應置灰不可選（見 spec.md「瀏覽與匯入 UI」）。
class OpdsAcquisition {
  final String href;
  final BookFileFormat? format;
  final int? sizeBytes;

  const OpdsAcquisition({required this.href, this.format, this.sizeBytes});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OpdsAcquisition &&
          runtimeType == other.runtimeType &&
          href == other.href &&
          format == other.format &&
          sizeBytes == other.sizeBytes;

  @override
  int get hashCode => Object.hash(href, format, sizeBytes);
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// 解析 OPDS Feed 時，來源缺少 `<title>` 所使用的後備標題（epic-45-interface-i18n
/// Issue 10）。解析器本身不依賴 `BuildContext`／`AppLocalizations`，由呼叫端
/// （畫面層）依目前介面語言建構後，隨每次 `OpdsClient.fetchFeed()` 傳入。
///
/// 刻意沒有提供預設值：若有預設（例如正體中文），任何忘記傳入的呼叫端都會靜默顯示
/// 寫死的中文；必填參數讓遺漏在編譯期就被抓到。
class OpdsFallbackTitles {
  /// 書目條目缺 `<title>` 時的書名。
  final String unknownBook;

  /// 分類導覽連結缺標題時的名稱。
  final String unnamedCategory;

  const OpdsFallbackTitles({required this.unknownBook, required this.unnamedCategory});
}
