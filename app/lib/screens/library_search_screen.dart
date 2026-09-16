// app/lib/screens/library_search_screen.dart
import 'dart:async';

import 'package:flutter/material.dart';

import '../library/library_repository.dart';
import '../library/models/book.dart';
import '../library/widgets/book_cover.dart';
import '../reader/reader_jump_target.dart';
import '../reader/reader_prefs_manager.dart';
import '../reader/text_conversion.dart';
import '../reader/text_conversion_mode.dart';
import '../search/full_text_search_settings_repository.dart';
import '../search/full_text_search_toggles_controller.dart';
import '../search/search_repository.dart';
import 'book_search_screen.dart';
import 'full_text_search_confirm_dialog.dart';
import 'library_paging.dart';
import 'library_screen_dependencies.dart';
import 'reader_screen_route.dart';
import 'widgets/eb_field_card.dart';
import 'widgets/eb_section_header.dart';
import 'widgets/eb_sheet_shell.dart';
import 'widgets/paging_bar.dart';

/// 全庫搜尋畫面（epic-10-search Issue 4，spec.md §5）：從 `LibraryScreen`
/// 快速過濾欄位下方的入口進入，帶入前一步關鍵字（可再修改）；結果分「書名/
/// 作者匹配」（永遠可用）與「內容匹配」（依 `SearchRepository.searchContent()`
/// 是否有索引資料而定）兩區。開書一律走一般路徑，無精確定位／暫態高亮
/// （見 Issue 5）。
class LibrarySearchScreen extends StatefulWidget {
  final String initialQuery;
  final SearchRepository searchRepository;
  final ReaderPrefsManager prefsManager;
  final LibraryRepository libraryRepository;
  final LibraryReaderFeatureRepositories readerFeatureRepositories;
  final LibrarySyncDependencies syncDependencies;
  final bool isEinkMode;

  const LibrarySearchScreen({
    super.key,
    this.initialQuery = '',
    required this.searchRepository,
    required this.prefsManager,
    required this.libraryRepository,
    this.readerFeatureRepositories = const LibraryReaderFeatureRepositories(),
    this.syncDependencies = const LibrarySyncDependencies(),
    this.isEinkMode = false,
  });

  @override
  State<LibrarySearchScreen> createState() => _LibrarySearchScreenState();
}

class _LibrarySearchScreenState extends State<LibrarySearchScreen> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialQuery);
  final FocusNode _searchFocusNode = FocusNode();
  Timer? _debounce;
  int _searchRequestId = 0;

  List<Book>? _titleAuthorResults;
  List<BookContentMatches>? _contentResults;
  bool _pdfEnabled = false;
  bool _foliateEnabled = false;

  /// 【審查修正 I-5】E-Ink 模式下「書名/作者匹配」與「內容匹配」兩區各自
  /// 獨立的離散分頁游標（見本計畫 Global Constraints 對這個已知簡化的
  /// 完整說明）。非 E-Ink 模式不使用，維持連續捲動。
  final _titleAuthorPaging = LibraryPagingCursor();
  final _contentPaging = LibraryPagingCursor();

  /// E-Ink 模式下每個分區每頁固定顯示筆數（審查修正 I-5：固定值而非動態
  /// 量測可用高度，見 Global Constraints 對這個已知簡化的說明）。
  static const _kEinkResultsPerPage = 5;

  /// 書名/作者匹配區＋內容匹配區的顯示轉換模式（FR-48，epic-42-text-
  /// conversion Issue 4，spec.md「Dart 端字元轉換模組」跨書情境條列：
  /// 「全庫搜尋結果片段（書名/作者匹配區＋內容匹配區）」）：一律採全域
  /// 預設值，不做任何單書覆寫。
  TextConversionMode _textConversion = TextConversionMode.original;

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    await Future.wait([
      _loadFullTextSearchSettings(),
      _loadTextConversion(),
    ]);
    if (!mounted) return;
    final initial = widget.initialQuery.trim();
    if (initial.isNotEmpty) {
      _runSearch(initial);
    }
  }

  Future<void> _loadTextConversion() async {
    final globalPrefs = await widget.prefsManager.loadGlobalPrefs();
    if (!mounted) return;
    setState(() => _textConversion = globalPrefs.reading.textConversion);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadFullTextSearchSettings() async {
    final repository =
        widget.readerFeatureRepositories.fullTextSearchSettingsRepository;
    if (repository == null) return;
    final pdfEnabled = await repository.isEnabled(ContentIndexCategory.pdf);
    final foliateEnabled =
        await repository.isEnabled(ContentIndexCategory.foliate);
    if (!mounted) return;
    setState(() {
      _pdfEnabled = pdfEnabled;
      _foliateEnabled = foliateEnabled;
    });
  }

  void _handleQueryChanged(String value) {
    _debounce?.cancel();
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _titleAuthorResults = null;
        _contentResults = null;
      });
      return;
    }
    _debounce = Timer(
      const Duration(milliseconds: 300),
      () => _runSearch(trimmed),
    );
  }

  Future<void> _runSearch(String trimmedQuery) async {
    final requestId = ++_searchRequestId;
    final isFullTextSearchAvailable =
        widget.readerFeatureRepositories.isFullTextSearchAvailable;
    final titleAuthorResults =
        await widget.searchRepository.searchTitleAuthor(trimmedQuery);
    final contentResults = isFullTextSearchAvailable
        ? await widget.searchRepository.searchContent(trimmedQuery)
        : const <BookContentMatches>[];
    // 【防止過期回應覆蓋新結果】使用者可能在前一次查詢的 Future 尚未
    // resolve 前就輸入了新關鍵字觸發下一次查詢，若不比對 requestId，先
    // 送出、較晚 resolve 的查詢會用舊結果覆蓋掉使用者已經看到的新結果。
    if (!mounted || requestId != _searchRequestId) return;
    setState(() {
      _titleAuthorResults = titleAuthorResults;
      _contentResults = contentResults;
      // 新一輪查詢結果到達時重置分頁，避免使用者停留在前一次查詢的
      // 第 3 頁，而新結果剛好也有超過 3 頁時，畫面卻仍卡在第 3 頁而非
      // 從第 1 頁開始瀏覽。
      _titleAuthorPaging.resetToFirstPage();
      _contentPaging.resetToFirstPage();
    });
  }

  void _openBook(Book book, {ReaderJumpTarget? jumpTarget}) {
    // 進入閱讀畫面（ReaderScreen）前收起搜尋輸入框焦點與軟鍵盤（IME），
    // 避免部分 Android E-Ink 裝置在未收起鍵盤下 push 新頁面時，因 IME 異步
    // 退場重算 Window Insets 與 setPreferredOrientations([]) 交互誤觸發螢幕旋轉。
    _searchFocusNode.unfocus();
    FocusScope.of(context).unfocus();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => buildReaderScreen(
          book: book,
          prefsManager: widget.prefsManager,
          features: widget.readerFeatureRepositories,
          sync: widget.syncDependencies,
          libraryRepository: widget.libraryRepository,
          isEinkMode: widget.isEinkMode,
          // epic-10-search Issue 5：只有內容匹配片段的點擊會帶入
          // jumpTarget（見下方 _buildContentGroupCard 呼叫端），書名/作者
          // 匹配結果維持一般開書路徑（jumpTarget 預設 null）。
          initialJumpTarget: jumpTarget,
        ),
      ),
    );
  }

  Future<void> _openQuickSettingsSheet() async {
    await EBSheetShell.show<void>(
      context,
      title: '全文檢索設定',
      isEinkMode: widget.isEinkMode,
      builder: (context) => _FullTextSearchQuickSettingsPanel(
        repository:
            widget.readerFeatureRepositories.fullTextSearchSettingsRepository,
        isFullTextSearchAvailable:
            widget.readerFeatureRepositories.isFullTextSearchAvailable,
        isEinkMode: widget.isEinkMode,
      ),
    );
    // 使用者可能在選單裡切換了開關（依 spec.md §4 立即清除/回填該分類
    // 索引資料）或按下「重建索引」，回到搜尋畫面後不能只更新引導卡片
    // 依據的兩個布林值（審查修正 I-3）——若目前輸入框已有查詢字串且正在
    // 顯示結果，必須連帶重新查詢一次，避免畫面殘留切換前查到的過期內容
    // 匹配結果（例如使用者剛關閉 PDF 全文檢索，畫面卻還顯示著幾秒前查到
    // 的 PDF 內容片段）。
    await _loadFullTextSearchSettings();
    final trimmedQuery = _controller.text.trim();
    if (trimmedQuery.isNotEmpty) {
      await _runSearch(trimmedQuery);
    }
  }

  @override
  Widget build(BuildContext context) {
    final trimmedQuery = _controller.text.trim();
    return Scaffold(
      appBar: AppBar(
        title: const Text('搜尋書內內容'),
        actions: [
          IconButton(
            key: const Key('library_search_screen_settings_button'),
            icon: const Icon(Icons.settings),
            tooltip: '全文檢索設定',
            onPressed: _openQuickSettingsSheet,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            // 清除按鈕的顯示與否需要跟著每一次按鍵輸入即時反應，不能依賴
            // _handleQueryChanged 的 300ms 防手震 setState（見該方法：非空
            // 字串時只排程 Timer，不會立即 setState），故另外監聽
            // _controller 本身觸發重建。
            child: ListenableBuilder(
              listenable: _controller,
              builder: (context, _) {
                final hasText = _controller.text.isNotEmpty;
                return TextField(
                  key: const Key('library_search_screen_field'),
                  controller: _controller,
                  focusNode: _searchFocusNode,
                  autofocus: true,
                  onChanged: _handleQueryChanged,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: '搜尋書名、作者或書本內容...',
                    isDense: true,
                    border: const OutlineInputBorder(),
                    suffixIcon: hasText
                        ? IconButton(
                            key: const Key(
                                'library_search_screen_clear_button'),
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
          Expanded(child: _buildResults(trimmedQuery)),
        ],
      ),
    );
  }

  /// 【審查修正 C-1，推翻原計畫第一版設計】原版在「書名/作者匹配」與
  /// 「內容匹配」皆為空時提前 `return` 一段全域「找不到符合的書籍或內容」
  /// 短路訊息，導致 `_buildContentGuidanceCard()` 永遠沒有機會執行——這是
  /// 預設情境（全文檢索未啟用、使用者搜尋內文詞彙）下的必經路徑，直接
  /// 違反 spec.md §5／issues.md Issue 4 的引導卡片要求。修訂為：「內容
  /// 匹配」分區一律渲染（空結果交給 `_buildContentGuidanceCard()`，其內部
  /// 已完整涵蓋三層情境），「書名/作者匹配」分區只在有結果時才顯示標題與
  /// 清單；不再有「兩區皆空」的全域短路分支，原本的 `library_search_
  /// empty_state` Key 隨之移除（新結構下必為死碼）。
  Widget _buildResults(String trimmedQuery) {
    if (trimmedQuery.isEmpty) return const SizedBox.shrink();
    final titleAuthorResults = _titleAuthorResults;
    final contentResults = _contentResults;
    if (titleAuthorResults == null || contentResults == null) {
      return const SizedBox.shrink();
    }
    return ListView(
      children: [
        if (titleAuthorResults.isNotEmpty) ...[
          const EBSectionHeader(title: '書名/作者匹配'),
          ..._buildSection<Book>(
            items: titleAuthorResults,
            paging: _titleAuthorPaging,
            itemBuilder: _buildTitleAuthorTile,
            pagingBarKey: 'library_search_title_author_paging_bar',
          ),
        ],
        const EBSectionHeader(title: '內容匹配'),
        if (contentResults.isEmpty)
          _buildContentGuidanceCard()
        else
          ..._buildSection<BookContentMatches>(
            items: contentResults,
            paging: _contentPaging,
            itemBuilder: _buildContentGroupCard,
            pagingBarKey: 'library_search_content_paging_bar',
          ),
      ],
    );
  }

  Widget _buildTitleAuthorTile(Book book) {
    return ListTile(
      key: Key('library_search_title_author_result_${book.id}'),
      leading: SizedBox(
        width: 40,
        height: 56,
        child: BookCover(book: book, textConversion: _textConversion),
      ),
      title: Text(convertText(book.title, _textConversion),
          maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        convertText(book.author ?? '', _textConversion),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: () => _openBook(book),
    );
  }

  Widget _buildContentGroupCard(BookContentMatches group) {
    return EBFieldCard(
      key: Key('library_search_content_group_${group.book.id}'),
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: SizedBox(
              width: 40,
              height: 56,
              child: BookCover(book: group.book, textConversion: _textConversion),
            ),
            title: Text(
              convertText(group.book.title, _textConversion),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              convertText(group.book.author ?? '', _textConversion),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          for (var i = 0; i < group.matches.length; i++)
            ListTile(
              key: Key(
                'library_search_content_snippet_${group.book.id}_$i',
              ),
              dense: true,
              title: Text(convertText(group.matches[i].snippet, _textConversion)),
              onTap: () => _openBook(
                group.book,
                jumpTarget: ReaderJumpTarget.fromContentLocator(
                  format: group.book.format,
                  locator: group.matches[i].locator,
                ),
              ),
            ),
          if (group.totalMatches > group.matches.length)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 8),
              child: Center(
                child: TextButton(
                  key: Key('library_search_drill_down_${group.book.id}'),
                  onPressed: () => _openBookSearch(group.book),
                  child: Text(
                    '查看全部 ${group.totalMatches} 筆結果'
                    '（還有 ${group.totalMatches - group.matches.length} 筆）',
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _openBookSearch(Book book) {
    _searchFocusNode.unfocus();
    FocusScope.of(context).unfocus();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BookSearchScreen(
          book: book,
          initialQuery: _controller.text.trim(),
          searchRepository: widget.searchRepository,
          prefsManager: widget.prefsManager,
          libraryRepository: widget.libraryRepository,
          readerFeatureRepositories: widget.readerFeatureRepositories,
          syncDependencies: widget.syncDependencies,
          isEinkMode: widget.isEinkMode,
        ),
      ),
    );
  }

  /// 【審查修正 I-5】通用「一組項目＋（E-Ink 模式下）離散分頁列」建構器，
  /// 供「書名/作者匹配」（`items` 為 `List<Book>`）與「內容匹配」（`items`
  /// 為 `List<BookContentMatches>`）兩區共用。非 E-Ink 模式下原樣列出全部
  /// 項目、無分頁列，維持既有連續捲動體驗；E-Ink 模式下依
  /// [_kEinkResultsPerPage] 只顯示當前頁項目＋一個 [PagingBar]（見本計畫
  /// Global Constraints 對這個已知簡化的完整說明）。
  List<Widget> _buildSection<T>({
    required List<T> items,
    required LibraryPagingCursor paging,
    required Widget Function(T) itemBuilder,
    required String pagingBarKey,
  }) {
    if (!widget.isEinkMode) {
      return [for (final item in items) itemBuilder(item)];
    }
    final pageCount = paging.clamp(
      itemCount: items.length,
      pageSize: _kEinkResultsPerPage,
    );
    final safePage = paging.currentPage;
    final pageStart = safePage * _kEinkResultsPerPage;
    final pageEnd = (pageStart + _kEinkResultsPerPage).clamp(0, items.length);
    return [
      for (final item in items.sublist(pageStart, pageEnd)) itemBuilder(item),
      PagingBar(
        key: Key(pagingBarKey),
        currentPage: safePage,
        pageCount: pageCount,
        onPrevious: safePage > 0
            ? () => setState(() => paging.goToPreviousPage())
            : null,
        onNext: safePage < pageCount - 1
            ? () => setState(() => paging.goToNextPage())
            : null,
        isEinkMode: widget.isEinkMode,
        // 【審查修正，見 reviews/review-issue-4.md Minor 2】「書名/作者
        // 匹配」與「內容匹配」兩區各自獨立的 PagingBar 若同時掛載，內部
        // 按鈕若沿用共用的寫死字面 Key 會重複；用各自的 pagingBarKey 當
        // 前綴區分。
        keyPrefix: pagingBarKey,
      ),
    ];
  }

  Widget _buildContentGuidanceCard() {
    if (!widget.readerFeatureRepositories.isFullTextSearchAvailable) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Text('本裝置不支援全文檢索'),
      );
    }
    if (_pdfEnabled && _foliateEnabled) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Text('查無符合的書內內容'),
      );
    }
    return EBFieldCard(
      key: const Key('library_search_content_guidance_card'),
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Text(_guidanceMessage()),
    );
  }

  String _guidanceMessage() {
    if (!_pdfEnabled && !_foliateEnabled) {
      return '尚未啟用全文檢索，開啟後才能搜尋書本內容（點擊右上角設定圖示開啟）';
    }
    if (_pdfEnabled) {
      return '已啟用「PDF」全文檢索，其他格式尚未啟用';
    }
    return '已啟用「其他格式」全文檢索，PDF 內容尚未啟用';
  }
}

/// AppBar「全文檢索設定」入口的面板內容（epic-10-search Issue 4，spec.md
/// §4 雙入口之二）：與 `SettingsScaffold`「閱讀」分區的兩個開關語意完全
/// 相同、共用同一個 [FullTextSearchSettingsRepository] 執行期實例，但獨立
/// 實作一份精簡版 UI、獨立的 `Key` 前綴——`AdaptiveShellScaffold` 用
/// `IndexedStack` 讓 `SettingsScaffold` 全程保持掛載，若共用 `Key`，本畫面
/// 以 `Navigator.push` 疊加在最上層時會與仍掛載中的 `SettingsScaffold`
/// 產生 `Key` 歧義（見本計畫 Global Constraints）。
class _FullTextSearchQuickSettingsPanel extends StatefulWidget {
  final FullTextSearchSettingsRepository? repository;
  final bool isFullTextSearchAvailable;
  final bool isEinkMode;

  const _FullTextSearchQuickSettingsPanel({
    required this.repository,
    required this.isFullTextSearchAvailable,
    required this.isEinkMode,
  });

  @override
  State<_FullTextSearchQuickSettingsPanel> createState() =>
      _FullTextSearchQuickSettingsPanelState();
}

class _FullTextSearchQuickSettingsPanelState
    extends State<_FullTextSearchQuickSettingsPanel> {
  late final FullTextSearchTogglesController _controller;

  @override
  void initState() {
    super.initState();
    _controller = FullTextSearchTogglesController(widget.repository);
    _load();
  }

  Future<void> _load() async {
    await _controller.load();
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _handleToggle(ContentIndexCategory category, bool value) async {
    if (value) {
      final confirmed = await showFullTextSearchEnableConfirmDialog(
        context,
        category: category,
        isEinkMode: widget.isEinkMode,
      );
      if (!confirmed) return;
    }
    await _controller.toggle(category, value);
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isFullTextSearchAvailable) {
      return const Padding(
        key: Key('library_search_full_text_search_unavailable_hint'),
        padding: EdgeInsets.all(16),
        child: Text('本裝置不支援全文檢索'),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: const Text('PDF 全文檢索'),
            subtitle: const Text('部分掃描/圖片型 PDF 可能沒有可搜尋的文字內容'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  key: const Key(
                      'library_search_full_text_search_pdf_rebuild_button'),
                  icon: const Icon(Icons.refresh),
                  tooltip: '重建索引',
                  onPressed:
                      !_controller.pdfEnabled || widget.repository == null
                          ? null
                          : () => widget.repository!
                              .rebuildIndex(ContentIndexCategory.pdf),
                ),
                Switch(
                  key: const Key('library_search_full_text_search_pdf_switch'),
                  value: _controller.pdfEnabled,
                  onChanged: widget.repository == null
                      ? null
                      : (value) =>
                          _handleToggle(ContentIndexCategory.pdf, value),
                ),
              ],
            ),
          ),
          ListTile(
            title: const Text('其他格式全文檢索'),
            subtitle: const Text('EPUB／TXT／KF8 等格式的背景索引建置'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  key: const Key(
                      'library_search_full_text_search_foliate_rebuild_button'),
                  icon: const Icon(Icons.refresh),
                  tooltip: '重建索引',
                  onPressed:
                      !_controller.foliateEnabled || widget.repository == null
                          ? null
                          : () => widget.repository!
                              .rebuildIndex(ContentIndexCategory.foliate),
                ),
                Switch(
                  key: const Key(
                      'library_search_full_text_search_foliate_switch'),
                  value: _controller.foliateEnabled,
                  onChanged: widget.repository == null
                      ? null
                      : (value) =>
                          _handleToggle(ContentIndexCategory.foliate, value),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
