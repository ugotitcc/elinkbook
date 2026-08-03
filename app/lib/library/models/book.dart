import 'book_group.dart';
import 'library_enums.dart';

/// 圖書庫中一本書籍的詮釋資料，對應 sqflite `books` 表的一列（見
/// docs/epics/epic-1-library/spec.md「資料模型」章節）。
class Book {
  final String id;
  final String title;
  final String? author;
  final BookFileFormat format;

  /// 檔案系統路徑或 `content://`/`file://` URI 字串（見
  /// docs/adr/0002-content-uri-reader-contract.md）。
  final String filePath;
  final BookSource source;

  /// 產生後封面圖檔的本機路徑（PNG）；`null` 表示尚未產生或產生失敗。
  final String? coverPath;

  /// 閱讀進度百分比（0.0-1.0），由 epic-5-toc-pagination Issue 2 起正式
  /// 活化——EPUB 用 Readium `Locator.locations.totalProgression`，PDF 用
  /// `(pdfPageIndex + 1) / 總頁數`，寫入時機見 [epubLocator]/[pdfPageIndex]。
  final double progress;

  /// EPUB 序列化後的 Readium `Locator`（`Locator.toJSON().toString()`），
  /// `null` 代表尚無記錄（例如書籍從未被開啟過，或本書為 PDF 格式）。與
  /// [pdfPageIndex] 互斥（一本書只會用到其中之一），但兩欄位皆可能同時
  /// 為 null（見 docs/epics/epic-5-toc-pagination/spec.md「本機閱讀位置
  /// 記憶」——位置資料是系統追蹤的狀態，故放在 Book 而非
  /// BookReaderPrefs）。
  final String? epubLocator;

  /// PDF 頁索引（0-indexed），`null` 代表尚無記錄。與 [epubLocator] 互斥。
  final int? pdfPageIndex;

  /// 全書字元數快取（epic-5-toc-pagination Issue 3，spec.md「分頁估算
  /// 模組」決策 #16），僅 EPUB 有值。`null` 代表尚未計算過，開書時原生端
  /// 據此觸發一次背景計算；非 `null` 則直接讀取快取，不重新走訪全書。
  final int? totalCharacterCount;

  /// 本書是否為固定版面（FXL）EPUB，`null` 代表尚未判斷過（涵蓋 Phase 1
  /// 上線前已匯入的既有書籍）或本書非 EPUB 格式（PDF/TXT 恆為 `null`，
  /// 語意上不適用，見 epic-17-epub-render-migration/spec.md「資料模型」）。
  /// 判斷結果由 `BookMetadataChannel.kt` 的 `extractEpubMetadata()`（匯入時）
  /// 或 `detectEpubLayout()`（既有書籍補判斷）提供，寫入後供 `ReaderScreen`
  /// 決定建構 `EpubReaderView`（Readium）或 `FoliateEpubReaderView`
  /// （`foliate-js`），**與 `reader/writing_mode.dart` 的
  /// `EpubLayoutInfo.isFixedLayout`（Readium 開書後才回報的執行期狀態）
  /// 是兩個不同概念，互不影響**。
  final bool? isFixedLayout;

  /// 書籍內容指紋（epic-8-sync Issue 3，spec.md「書籍內容指紋計算」／
  /// 「跨裝置參照設計」）：EPUB 優先為 OPF identifier，缺漏或 PDF/TXT
  /// 為整份檔案內容的 SHA-256，供同步引擎跨裝置比對「這是不是同一本
  /// 書」使用（不攜帶本機 [id]，見 spec.md）。`null` 代表尚未計算過
  /// （既有書籍升級後的暫時狀態，或本次匯入計算失敗），該書在補算前
  /// 不參與跨裝置比對，不影響單機使用。
  final String? contentFingerprint;

  final String groupName;
  final DateTime createTime;
  final DateTime lastReadTime;

  const Book({
    required this.id,
    required this.title,
    this.author,
    required this.format,
    required this.filePath,
    required this.source,
    this.coverPath,
    this.progress = 0,
    this.epubLocator,
    this.pdfPageIndex,
    this.totalCharacterCount,
    this.isFixedLayout,
    this.contentFingerprint,
    this.groupName = BookGroup.uncategorized,
    required this.createTime,
    required this.lastReadTime,
  });

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'title': title,
      'author': author,
      'format': format.name,
      'filePath': filePath,
      'source': source.name,
      'coverPath': coverPath,
      'progress': progress,
      'epubLocator': epubLocator,
      'pdfPageIndex': pdfPageIndex,
      'totalCharacterCount': totalCharacterCount,
      // 欄位名刻意用 snake_case（spec.md「資料模型」決策），與本表其餘
      // 欄位的 camelCase 命名不一致，不是疏漏。
      'is_fixed_layout':
          isFixedLayout == null ? null : (isFixedLayout! ? 1 : 0),
      'content_fingerprint': contentFingerprint,
      'groupName': groupName,
      'createTime': createTime.millisecondsSinceEpoch,
      'lastReadTime': lastReadTime.millisecondsSinceEpoch,
    };
  }

  factory Book.fromMap(Map<String, Object?> map) {
    return Book(
      id: map['id'] as String,
      title: map['title'] as String,
      author: map['author'] as String?,
      format: BookFileFormat.values.byName(map['format'] as String),
      filePath: map['filePath'] as String,
      source: BookSource.values.byName(map['source'] as String),
      coverPath: map['coverPath'] as String?,
      progress: (map['progress'] as num).toDouble(),
      epubLocator: map['epubLocator'] as String?,
      pdfPageIndex: map['pdfPageIndex'] as int?,
      totalCharacterCount: map['totalCharacterCount'] as int?,
      isFixedLayout: map['is_fixed_layout'] == null
          ? null
          : (map['is_fixed_layout'] as int) == 1,
      contentFingerprint: map['content_fingerprint'] as String?,
      groupName: map['groupName'] as String,
      createTime: DateTime.fromMillisecondsSinceEpoch(map['createTime'] as int),
      lastReadTime:
          DateTime.fromMillisecondsSinceEpoch(map['lastReadTime'] as int),
    );
  }

  /// 回傳欄位值與自身相同的新物件，僅覆寫明確傳入的參數。[groupName] 供
  /// Issue 10 的批次分類異動使用；[isFixedLayout] 供本 Issue 的 EPUB 版面
  /// 判斷/回填流程使用。
  Book copyWith({String? groupName, bool? isFixedLayout}) {
    return Book(
      id: id,
      title: title,
      author: author,
      format: format,
      filePath: filePath,
      source: source,
      coverPath: coverPath,
      progress: progress,
      epubLocator: epubLocator,
      pdfPageIndex: pdfPageIndex,
      totalCharacterCount: totalCharacterCount,
      isFixedLayout: isFixedLayout ?? this.isFixedLayout,
      groupName: groupName ?? this.groupName,
      createTime: createTime,
      lastReadTime: lastReadTime,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Book &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          title == other.title &&
          author == other.author &&
          format == other.format &&
          filePath == other.filePath &&
          source == other.source &&
          coverPath == other.coverPath &&
          progress == other.progress &&
          epubLocator == other.epubLocator &&
          pdfPageIndex == other.pdfPageIndex &&
          totalCharacterCount == other.totalCharacterCount &&
          isFixedLayout == other.isFixedLayout &&
          contentFingerprint == other.contentFingerprint &&
          groupName == other.groupName &&
          createTime == other.createTime &&
          lastReadTime == other.lastReadTime;

  @override
  int get hashCode => Object.hash(
        id,
        title,
        author,
        format,
        filePath,
        source,
        coverPath,
        progress,
        epubLocator,
        pdfPageIndex,
        totalCharacterCount,
        isFixedLayout,
        contentFingerprint,
        groupName,
        createTime,
        lastReadTime,
      );
}
