// app/lib/screens/book_search_screen.dart
import 'dart:async';

import 'package:flutter/material.dart';

import '../library/models/book.dart';
import '../library/models/library_enums.dart';
import '../library/library_repository.dart';
import '../reader/reader_jump_target.dart';
import '../reader/reader_prefs_manager.dart';
import '../reader/resolve_text_conversion.dart';
import '../reader/text_conversion.dart';
import '../reader/text_conversion_mode.dart';
import '../search/highlight_segments.dart';
import '../search/search_query_variants.dart';
import '../search/search_repository.dart';
import 'library_paging.dart';
import 'library_screen_dependencies.dart';
import 'reader_screen_route.dart';
import 'widgets/paging_bar.dart';

/// 單書全文檢索畫面（epic-10-search Issue 7，spec.md §9.3）：從全庫搜尋
/// drill-down 或閱讀器 TopBar 搜尋按鈕進入，在指定書籍內即時重搜、切換
/// 排序、顯示位置標籤與關鍵字高亮、E-Ink 離散分頁。
class BookSearchScreen extends StatefulWidget {
  final Book book;
  final String initialQuery;
  final SearchRepository searchRepository;
  final ReaderPrefsManager prefsManager;
  final LibraryRepository libraryRepository;
  final LibraryReaderFeatureRepositories readerFeatureRepositories;
  final LibrarySyncDependencies syncDependencies;
  final bool isEinkMode;

  /// `true` 時代表從閱讀器開啟（Issue 8 接線），點選片段 pop 回傳
  /// `ReaderJumpTarget`；`false`（預設）時從全庫搜尋推入，點選片段
  /// 推入 `ReaderScreen`。
  final bool fromReader;

  const BookSearchScreen({
    super.key,
    required this.book,
    this.initialQuery = '',
    required this.searchRepository,
    required this.prefsManager,
    required this.libraryRepository,
    this.readerFeatureRepositories = const LibraryReaderFeatureRepositories(),
    this.syncDependencies = const LibrarySyncDependencies(),
    this.isEinkMode = false,
    this.fromReader = false,
  });

  @override
  State<BookSearchScreen> createState() => _BookSearchScreenState();
}

class _BookSearchScreenState extends State<BookSearchScreen> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialQuery);
  final FocusNode _searchFocusNode = FocusNode();
  Timer? _debounce;
  int _searchRequestId = 0;

  BookSearchDetailResult? _result;
  bool _sortByBookOrder = true;

  /// E-Ink 離散分頁游標。
  final _pagingCursor = LibraryPagingCursor();

  /// E-Ink 模式每頁筆數（spec.md §9.3）。
  static const _kEinkItemsPerPage = 10;

  /// 內容匹配摘要片段的顯示轉換模式（FR-48，epic-42-text-conversion
  /// Issue 4，spec.md「全文檢索整合」）：一律採全域預設值（「跨書情境」
  /// 規則），不做單書覆寫。
  TextConversionMode _contentTextConversion = TextConversionMode.original;

  /// AppBar 書名／工具列作者的顯示轉換模式（FR-48，單書情境）：依
  /// [widget.book] 所屬的 `resolveTextConversion()` 解析值——與
  /// [_contentTextConversion] 刻意不同層級（見 spec.md「Dart 端字元轉換
  /// 模組」呼叫點分流規則）。本畫面自行解析、不依賴呼叫端是否已預先轉換
  /// 過傳入的 [widget.book]（審查修正 review-plan-issue-4.md I-2）：
  /// `LibrarySearchScreen` 下鑽入口與 `ReaderScreen` 單書搜尋入口皆傳入
  /// 未轉換的原始 `Book`，本畫面統一在此處解析，兩個入口顯示結果一致。
  TextConversionMode _titleTextConversion = TextConversionMode.original;

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    final loaded = await widget.prefsManager.load(widget.book.id);
    if (!mounted) return;
    setState(() {
      _contentTextConversion = loaded.globalPrefs.reading.textConversion;
      _titleTextConversion = resolveTextConversion(
        loaded.bookPrefs,
        loaded.globalPrefs.reading,
      );
    });
    // 裝置不支援全文檢索時跳過初始查詢，由 UI 呈現降級提示（review-plan-issue-7.md I-3）。
    if (!widget.readerFeatureRepositories.isFullTextSearchAvailable) {
      return;
    }
    final initial = widget.initialQuery.trim();
    if (initial.isNotEmpty) {
      _runSearch(initial);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _handleQueryChanged(String value) {
    _debounce?.cancel();
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      // 遞增 requestId 註銷在途中的非同步請求，避免過期結果覆蓋清空狀態（review-plan-issue-7.md I-1）。
      _searchRequestId++;
      setState(() => _result = null);
      return;
    }
    if (!widget.readerFeatureRepositories.isFullTextSearchAvailable) {
      return;
    }
    _debounce = Timer(
      const Duration(milliseconds: 300),
      () => _runSearch(trimmed),
    );
  }

  Future<void> _runSearch(String trimmedQuery) async {
    if (!widget.readerFeatureRepositories.isFullTextSearchAvailable) return;
    final requestId = ++_searchRequestId;
    final result = await widget.searchRepository.searchContentInBook(
      widget.book.id,
      trimmedQuery,
      sortByBookOrder: _sortByBookOrder,
    );
    if (!mounted || requestId != _searchRequestId) return;
    setState(() {
      _result = result;
      _pagingCursor.resetToFirstPage();
    });
  }

  void _toggleSort() {
    setState(() {
      _sortByBookOrder = !_sortByBookOrder;
    });
    final trimmedQuery = _controller.text.trim();
    if (trimmedQuery.isNotEmpty) {
      _runSearch(trimmedQuery);
    }
  }

  void _handleSnippetTap(ContentMatchSnippet snippet) {
    final jumpTarget = ReaderJumpTarget.fromContentLocator(
      format: widget.book.format,
      locator: snippet.locator,
    );

    if (widget.fromReader) {
      // Issue 8 接線：pop 回傳 ReaderJumpTarget 給閱讀器就地跳轉。
      Navigator.of(context).pop(jumpTarget);
      return;
    }

    // 從全庫搜尋推入：開啟 ReaderScreen。
    _searchFocusNode.unfocus();
    FocusScope.of(context).unfocus();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => buildReaderScreen(
          book: widget.book,
          prefsManager: widget.prefsManager,
          features: widget.readerFeatureRepositories,
          sync: widget.syncDependencies,
          libraryRepository: widget.libraryRepository,
          isEinkMode: widget.isEinkMode,
          initialJumpTarget: jumpTarget,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          convertText(widget.book.title, _titleTextConversion),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: Column(
        children: [
          // 搜尋輸入框
          Padding(
            padding: const EdgeInsets.all(12),
            child: ListenableBuilder(
              listenable: _controller,
              builder: (context, _) {
                final hasText = _controller.text.isNotEmpty;
                return TextField(
                  key: const Key('book_search_screen_field'),
                  controller: _controller,
                  focusNode: _searchFocusNode,
                  autofocus: false,
                  onChanged: _handleQueryChanged,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: '在本書中搜尋...',
                    isDense: true,
                    border: const OutlineInputBorder(),
                    suffixIcon: hasText
                        ? IconButton(
                            key: const Key('book_search_screen_clear_button'),
                            icon: const Icon(Icons.close),
                            tooltip: '清除',
                            onPressed: () {
                              _controller.clear();
                              _handleQueryChanged('');
                            },
                          )
                        : null,
                  ),
                );
              },
            ),
          ),
          // 不支援提示或工具列
          if (!widget.readerFeatureRepositories.isFullTextSearchAvailable)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('本裝置不支援全文檢索'),
            )
          else ...[
            _buildToolbar(),
            // 結果清單
            Expanded(child: _buildResults()),
          ],
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    final result = _result;
    if (result == null || result.matches.isEmpty) {
      return const SizedBox.shrink();
    }
    final summaryText = result.isTruncated
        ? '僅顯示前 ${result.matches.length} 筆，共 ${result.totalMatches} 筆'
        : '共 ${result.totalMatches} 筆結果';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          if (widget.book.author != null && widget.book.author!.isNotEmpty)
            Flexible(
              child: Text(
                convertText(widget.book.author!, _titleTextConversion),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          const SizedBox(width: 8),
          Text(
            summaryText,
            key: const Key('book_search_summary'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const Spacer(),
          TextButton.icon(
            key: const Key('book_search_sort_toggle'),
            icon: Icon(
              _sortByBookOrder ? Icons.sort : Icons.trending_up,
              size: 18,
            ),
            label: Text(_sortByBookOrder ? '依書中順序' : '依相關度排序'),
            onPressed: _toggleSort,
          ),
        ],
      ),
    );
  }

  Widget _buildResults() {
    final result = _result;
    if (result == null) return const SizedBox.shrink();
    if (result.matches.isEmpty) {
      return const Center(child: Text('查無符合的書內內容'));
    }

    final trimmedQuery = _controller.text.trim();
    final variants = queryVariants(trimmedQuery);
    final isPdf = widget.book.format == BookFileFormat.pdf;

    if (!widget.isEinkMode) {
      // 非 E-Ink：連續捲動
      return ListView.builder(
        itemCount: result.matches.length,
        itemBuilder: (context, index) => _buildSnippetTile(
          result.matches[index],
          index,
          variants,
          isPdf,
        ),
      );
    }

    // E-Ink 模式：離散分頁
    final pageCount = _pagingCursor.clamp(
      itemCount: result.matches.length,
      pageSize: _kEinkItemsPerPage,
    );
    final safePage = _pagingCursor.currentPage;
    final pageStart = safePage * _kEinkItemsPerPage;
    final pageEnd =
        (pageStart + _kEinkItemsPerPage).clamp(0, result.matches.length);

    return Column(
      children: [
        Expanded(
          child: ListView(
            children: [
              for (var i = pageStart; i < pageEnd; i++)
                _buildSnippetTile(result.matches[i], i, variants, isPdf),
            ],
          ),
        ),
        PagingBar(
          key: const Key('book_search_paging_bar'),
          currentPage: safePage,
          pageCount: pageCount,
          onPrevious: safePage > 0
              ? () => setState(() => _pagingCursor.goToPreviousPage())
              : null,
          onNext: safePage < pageCount - 1
              ? () => setState(() => _pagingCursor.goToNextPage())
              : null,
          isEinkMode: widget.isEinkMode,
          keyPrefix: 'book_search_paging_bar',
        ),
      ],
    );
  }

  Widget _buildSnippetTile(
    ContentMatchSnippet snippet,
    int index,
    List<String> variants,
    bool isPdf,
  ) {
    // 位置標籤：PDF「第 X 頁」，其餘「第 X 章」（chapterIndex 為 0-based）。
    final chapterIndex = snippet.chapterIndex;
    final locationText = chapterIndex != null
        ? (isPdf ? '第 ${chapterIndex + 1} 頁' : '第 ${chapterIndex + 1} 章')
        : null;
    final displaySnippet = convertText(snippet.snippet, _contentTextConversion);

    return ListTile(
      key: Key('book_search_snippet_$index'),
      dense: true,
      title: _buildHighlightedText(displaySnippet, variants),
      subtitle: locationText != null ? Text(locationText) : null,
      onTap: () => _handleSnippetTap(snippet),
    );
  }

  /// 關鍵字高亮：在 [text] 中找到 [query] 出現的所有位置（case-insensitive），
  /// 命中段加粗；非 E-Ink 模式搭配淡色背景，E-Ink 模式搭配底線（高對比、
  /// 避免電子紙殘影）。spec.md §9.3。使用 Text.rich 支援系統文字縮放。
  /// 命中位置切分邏輯已抽至 [splitHighlightSegments]（epic-41 Issue 4），
  /// 本方法只負責把切分結果轉成有樣式的 TextSpan。
  Widget _buildHighlightedText(String text, List<String> variants) {
    // 跨字形高亮：命中內容字形可能與使用者輸入字形不同（例如使用者輸入
    // 簡體「电脑」命中繁體原文「電腦」的章節），改用 findMatchingVariant()
    // 依序嘗試 indexOf，取第一個能在 text 中找到的變體做為高亮比對
    // 基準，而非只用原始查詢字串——找不到任何變體時（理論上不會發生，
    // 見 search_query_variants.dart 說明）保底退回 variants.first（恆為
    // 原始查詢字串 q0，見 queryVariants() 文件註解），交由
    // splitHighlightSegments() 既有「找不到則不高亮」邏輯安全處理。
    final matchQuery = findMatchingVariant(text, variants) ?? variants.first;
    final segments = splitHighlightSegments(text, matchQuery);
    final hasMatch = segments.any((segment) => segment.isMatch);
    if (!hasMatch) {
      // 完全沒有命中（含 query 為空字串）：直接回傳純 Text，不得改用
      // Text.rich(TextSpan(text: text))——【/diagnose：全書搜尋結果符合
      // 文字部分變得特別大】的字級 bug 修復只保護「有命中片段」這條路徑
      // （見下方 spans 分支的說明），這條無高亮路徑本來就沒有手動指定過
      // style，維持現狀即可。用 any(isMatch) 判斷而非假設 segments 長度，
      // 不耦合 splitHighlightSegments 內部「無命中時剛好回傳單一片段」的
      // 實作細節。
      return Text(text);
    }

    final spans = [
      for (final segment in segments)
        TextSpan(
          text: segment.text,
          style: segment.isMatch
              ? TextStyle(
                  fontWeight: FontWeight.bold,
                  backgroundColor: widget.isEinkMode
                      ? null
                      : Theme.of(context).colorScheme.primaryContainer,
                  decoration: widget.isEinkMode ? TextDecoration.underline : null,
                )
              : null,
        ),
    ];

    // 【/diagnose：全書搜尋結果符合文字部分變得特別大】不可在此手動指定
    // style: DefaultTextStyle.of(context).style——這裡的 context 是
    // _BookSearchScreenState 自己的 build context，位於本畫面 Scaffold/
    // Material 之上、尚未進入 ListTile 標題實際掛載位置，解析出來的並非
    // ListTile 的正常字級，而是 MaterialApp 特意設計、用來提醒開發者
    // 「文字未包在 Material 內」的 48px 紅色錯誤警示字級（見
    // flutter/material/app.dart `_errorTextStyle`）。留空讓 Text.rich
    // 用它自己實際掛載時的 context 走正常 DefaultTextStyle 繼承，字級才會
    // 與同一份清單裡的一般 Text（無高亮）一致。
    return Text.rich(TextSpan(children: spans));
  }
}
