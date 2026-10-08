import 'dart:async';

import 'dart:io';

import 'package:flutter/material.dart';

import '../reader/book_reader_prefs.dart';
import '../reader/book_reader_prefs_repository.dart';
import '../reader/page_turn_mode.dart';
import '../reader/text_conversion.dart';
import '../reader/text_conversion_mode.dart';
import '../reader/writing_mode.dart';
import '../remote/opds_types.dart';
import '../remote/remote_book_downloader.dart';
import '../remote/remote_server_profile.dart';
import '../library/library_preferences.dart';
import '../library/library_repository.dart';
import 'appearance_dependencies.dart';
import 'reader_feature_dependencies.dart';
import 'source_dependencies.dart';
import 'book_grid_tile_metrics.dart';
import 'library_book_list_controller.dart';
import 'library_batch_actions.dart';
import '../library/models/book.dart';
import '../library/models/book_group.dart';
import '../library/models/library_enums.dart';
import '../library/widgets/book_cover.dart';
import '../theme/elink_tokens.dart';

import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';
import 'book_action_sheet.dart';
import 'library_group_management_dialog.dart';
import 'library_move_to_group_dialog.dart';
import 'library_paging.dart';
import 'library_search_screen.dart';
import 'reader_screen_route.dart';
import 'widgets/eb_sheet_shell.dart';
import 'widgets/paging_bar.dart';
import 'widgets/reader_option_tile.dart';

/// 書架 GridView 每個 cell「整體」的寬高比（cell 寬度 / 高度，封面＋文字
/// 說明區合計，非純封面寬高比——見 `_BookGridTile`：外層 Column 總高度受
/// `childAspectRatio` 約束，封面只是 Expanded 取得的剩餘空間），沿用
/// `SliverGridDelegateWithFixedCrossAxisCount.childAspectRatio` 既有字面
/// 值——抽成具名常數避免 Grid 渲染與 Issue 7 動態列數計算
/// （`_buildBookList()`）各自寫一份 `0.62`，日後改一處漏改另一處
/// （epic-36 Issue 7；`review-plan-issue-7.md` C-2 已確認 `childAspectRatio`
/// 涵蓋整個 cell，不是只有封面部分，命名從 `_kCoverAspectRatio` 正名為
/// `_kCellAspectRatio`）。
// 2026-09-28：0.62 → 0.64，每格略矮，讓 Mobiscribe Wave 書架排得下兩列。
const _kCellAspectRatio = 0.64;

/// 圖書庫主畫面：讀取 [LibraryRepository] 的真實資料，取代
/// epic-0-skeleton 遺留的固定範例書籍清單佔位版本（見
/// docs/epics/epic-1-library/spec.md）。
class LibraryScreen extends StatefulWidget {
  /// 閱讀器功能依賴組（ADR 0037）：書架用到其中的 libraryRepository、prefsManager、
  /// 全文檢索設定、版面覆寫 repository 等；開書與開全庫搜尋時整組轉傳同一個實例。
  final ReaderFeatureDependencies dependencies;

  /// 來源依賴組（ADR 0037）：重新下載遠端書用其中的 remoteServerRepository、
  /// createOpdsClient 與 isMobileDataConnection，全部 non-null。
  final SourceDependencies sources;

  /// 外觀快照（ADR 0037）：主題／E-Ink 等由上層每次 build 現組往下傳。
  final AppearanceDependencies appearance;
  final Listenable? refreshSignal;
  final VoidCallback? onNavigateToSource;
  final VoidCallback? onNavigateToSettings;

  const LibraryScreen({
    super.key,
    required this.dependencies,
    required this.sources,
    required this.appearance,
    this.refreshSignal,
    this.onNavigateToSource,
    this.onNavigateToSettings,
  });

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen>
    with WidgetsBindingObserver {
  final _preferences = LibraryPreferences();
  late final LibraryBookListController _bookListController;
  late LibraryBatchActions _batchActions;

  String? _activeGroupFilter;
  LibraryViewMode _viewMode = LibraryViewMode.grid;
  Set<String>? _selectedBookIds;
  final Set<String> _redownloadingBookIds = {};

  /// 書架搜尋（2026-09-08 `/grill-with-docs` 使用者需求，比照
  /// `prototype/elinkbook_theme_prototype.html` 常駐搜尋列設計）：純記憶體
  /// 內過濾已載入的 `_bookListController.books`，比對書名／作者是否內含
  /// 輸入字串（不分大小寫），不牽動 SQLite／FTS5——與 `epic-10-search`
  /// （書內容全文檢索，`docs/epics.md` Backlog）是完全不同範圍的功能。
  /// 非空時忽略目前分類瀏覽狀態（`_activeGroupFilter`），視為全庫搜尋。
  final _searchController = TextEditingController();
  String _searchQuery = '';
  // 書架搜尋列是否在標題列展開（2026-09-28：搜尋列收進標題列 🔍 按鈕，
  // 不再常駐佔用書架內容區高度）。
  bool _searchExpanded = false;

  /// 書架分頁狀態的唯一負責者（epic-36 Issue 6，架構回顧衍生）：取代原本
  /// 散落在 `build()`／`didChangeMetrics()`／排序/分類切換/換頁按鈕共 7
  /// 處各自寫入的 `_currentPage`／`_lastPageSize` 欄位，見
  /// `plans/plan-issue-6.md`。**與 `issues.md` Issue 6 原文寫的
  /// `late final` 不同，這裡改用 eager 的 `final`**：`LibraryPagingCursor()`
  /// 建構子不依賴 `widget`／`context`，不需要等到 `initState()` 才能
  /// 具現化，用 `late` 只會多一層執行期延遲初始化檢查，沒有實質好處
  /// （`review-plan-issue-6.md` M-3）。
  final LibraryPagingCursor _paging = LibraryPagingCursor();

  /// `didChangeMetrics()` 用來比對「是否真的尺寸改變」的暫存值——鍵盤彈出
  /// /收起改變的是 `viewInsets`，不是 `physicalSize`，比對後可以繼續攔截
  /// 這類無關 metrics 變化，延續 Issue 6（`review-plan-issue-6.md` I-1）
  /// 建立的 E-Ink 防抖保護（`review-plan-issue-7.md` I-4）。
  Size? _lastPhysicalSize;

  /// 使用者最後閱讀的書籍（`lastReadTime` 最新且 > epoch 0 者），供頂層
  /// 書架的常駐「繼續閱讀列」使用；`_onBookListChanged()` 每次書籍清單
  /// 變動時重新計算。
  Book? _mostRecentBook;

  /// 簡繁顯示轉換全域預設值（FR-48，「跨書情境」規則，epic-42-text-
  /// conversion Issue 3：書架畫面一律採全域預設，不做單書覆寫，見
  /// resolve_text_conversion.dart 文件註解）。載入完成前維持
  /// `TextConversionMode.original`（與 `ReadingDefaults` 硬編碼預設值
  /// 一致），避免短暫顯示原文後才套用轉換的畫面跳動。
  TextConversionMode _textConversion = TextConversionMode.original;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bookListController = LibraryBookListController(
      repository: widget.dependencies.libraryRepository,
    )..addListener(_onBookListChanged);
    _batchActions = LibraryBatchActions(
      repository: widget.dependencies.libraryRepository,
      fullTextSearchSettingsRepository:
          widget.dependencies.fullTextSearchSettingsRepository,
    );
    widget.refreshSignal?.addListener(_onExternalRefreshRequested);
    _initialize();
  }

  /// 「來源」畫面匯入新書後切回書架時觸發（見 AdaptiveShellScaffold，
  /// Task 5）——IndexedStack 讓 LibraryScreen 全程保持掛載，切換可見子項不
  /// 會重跑 build()，需要這個外部訊號主動重新整理。
  void _onExternalRefreshRequested() {
    _bookListController.loadBooks();
    _bookListController.loadGroups();
    unawaited(_reloadTextConversion());
  }

  @override
  void didUpdateWidget(LibraryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.refreshSignal != oldWidget.refreshSignal) {
      oldWidget.refreshSignal?.removeListener(_onExternalRefreshRequested);
      widget.refreshSignal?.addListener(_onExternalRefreshRequested);
    }
    // 【review-plan-issue-2.md M-2】_batchActions 在 initState() 建構時
    // 捕捉了當下的 repository/fullTextSearchSettingsRepository 參考；
    // ReaderFeatureDependencies 沒有覆寫 ==（參考相等）；上層（main() 建一次）
    // 傳同一個實例時不會重建 _batchActions，換了實例才重建。
    if (widget.dependencies != oldWidget.dependencies) {
      _batchActions = LibraryBatchActions(
        repository: widget.dependencies.libraryRepository,
        fullTextSearchSettingsRepository:
            widget.dependencies.fullTextSearchSettingsRepository,
      );
    }
  }

  void _onBookListChanged() {
    if (!mounted) return;
    setState(() => _mostRecentBook = _computeMostRecentBook());
  }

  Book? _computeMostRecentBook() {
    final books = _bookListController.books;
    if (books == null) return null;
    Book? mostRecent;
    for (final book in books) {
      if (book.lastReadTime.millisecondsSinceEpoch <= 0) continue;
      if (mostRecent == null ||
          book.lastReadTime.isAfter(mostRecent.lastReadTime)) {
        mostRecent = book;
      }
    }
    return mostRecent;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.refreshSignal?.removeListener(_onExternalRefreshRequested);
    _bookListController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    setState(() {
      _searchQuery = value;
      _paging.resetToFirstPage();
    });
  }

  @override
  void didChangeMetrics() {
    if (!mounted) return;
    final physicalSize = View.of(context).physicalSize;
    // App 退到背景、螢幕休眠、多視窗模式調整分割大小、可折疊裝置展開
    // 過渡瞬間，physicalSize 可能暫時回報為 0x0——此時 `0 > 0` 為
    // false，會被誤判為 portrait，若裝置原本是 landscape 就會觸發一次
    // 不必要的重建。直接略過這種暫態，等下一次真正有效的 metrics 變化
    // 再處理（`review-plan-issue-3.md` I-2）。
    if (physicalSize.isEmpty) return;
    // pageSize 改為由 build() 內的 LayoutBuilder 依實際量測高度計算
    // （epic-36 Issue 7）——didChangeMetrics() 不再自己算 pageSize、也
    // 不再呼叫 LibraryPagingCursor 的任何方法，實際箝制／比例換算全部
    // 延後到下一次 build() 呼叫 _paging.clamp() 時處理。但仍比對
    // physicalSize 是否真的改變才 setState()：軟體鍵盤彈出/收起改變的是
    // viewInsets，不是 physicalSize，這裡比對後可以繼續攔截這類無關變化
    // 觸發整頁重建，延續 Issue 6 建立的 E-Ink 防抖保護
    // （`review-plan-issue-6.md` I-1／`review-plan-issue-7.md` I-4）。
    if (_lastPhysicalSize == physicalSize) return;
    _lastPhysicalSize = physicalSize;
    setState(() {});
  }

  Future<void> _initialize() async {
    final viewMode = await _preferences.loadViewMode();
    if (!mounted) return;
    setState(() => _viewMode = viewMode);
    await _reloadTextConversion();
    await _bookListController.initialLoad();
    await _maybeOpenLastBookOnLaunch();
  }

  /// 重新載入全域簡繁顯示轉換預設值（epic-42-text-conversion Issue 3）：
  /// 初次啟動（`_initialize()`，`await` 等待完成後才載入書籍清單，避免
  /// 啟動畫面文字閃爍，審查修正 I-2）與「設定」分頁切回書架時（見
  /// `_onExternalRefreshRequested()`，`unawaited`——`AdaptiveShellScaffold`
  /// 用 `IndexedStack` 讓 `LibraryScreen` 全程保持掛載，使用者在「設定」
  /// 分頁變更全域預設值後切回書架不會自動重新 build()，需要這個訊號主動
  /// 重新整理；此處書架已完整渲染過，不存在「初次繪製前」的閃爍疑慮，故
  /// 沿用既有「來源」分頁匯入新書後的 `unawaited` 既定模式）各觸發一次。
  Future<void> _reloadTextConversion() async {
    final globalPrefs = await widget.dependencies.prefsManager
        .loadGlobalPrefs();
    if (!mounted) return;
    setState(() => _textConversion = globalPrefs.reading.textConversion);
  }

  /// 啟動時開啟最後閱讀的那本書（epic-18-reader-device-qa Issue 29）：只在頂層
  /// 書架啟動當下觸發一次。保留此 guard 是比照 spec.md 明文指示維持語意對稱與
  /// 未來防禦性——原地下鑽後已無獨立實例，點擊拼貼格晚於此方法的執行時機，
  /// 不會重複觸發開書。
  Future<void> _maybeOpenLastBookOnLaunch() async {
    if (_activeGroupFilter != null) return;
    final globalPrefs = await widget.dependencies.prefsManager
        .loadGlobalPrefs();
    if (!globalPrefs.reading.openLastBookOnLaunch) return;
    if (!mounted) return;
    final books = await widget.dependencies.libraryRepository.listBooks(
      sortBy: LibrarySortBy.lastRead,
    );
    if (!mounted) return;
    if (books.isEmpty) return;
    // 〔epic-30-calibre-remote-library Issue 4 補充發現〕最後閱讀的書籍
    // 若是「待下載」狀態（例如快取已被移除），不應該直接嘗試開啟不存在
    // 的實體檔案——啟動流程不適合順帶跳出重新下載確認對話框打斷使用者，
    // 靜默略過即可，使用者仍可從書架手動點擊觸發重新下載。
    if (!books.first.isDownloaded) return;
    _openBook(books.first);
  }

  void _toggleViewMode() {
    final newMode = _viewMode == LibraryViewMode.grid
        ? LibraryViewMode.list
        : LibraryViewMode.grid;
    setState(() => _viewMode = newMode);
    _preferences.saveViewMode(newMode);
  }

  bool get _inSelectionMode => _selectedBookIds != null;

  void _enterSelectionMode(String bookId) {
    setState(() => _selectedBookIds = {bookId});
  }

  void _exitSelectionMode() {
    setState(() => _selectedBookIds = null);
  }

  void _toggleBookSelection(String bookId) {
    final selected = _selectedBookIds;
    if (selected == null) return;
    setState(() {
      if (selected.contains(bookId)) {
        selected.remove(bookId);
      } else {
        selected.add(bookId);
      }
    });
  }

  void _onBookTap(Book book) {
    if (_inSelectionMode) {
      _toggleBookSelection(book.id);
    } else if (!book.isDownloaded) {
      _handleRedownload(book);
    } else {
      _openBook(book);
    }
  }

  void _onBookLongPress(Book book) {
    if (!_inSelectionMode) {
      _enterSelectionMode(book.id);
    }
  }

  Future<void> _moveSelectedBooksToGroup() async {
    final selectedIds = _selectedBookIds;
    final books = _bookListController.books;
    if (selectedIds == null || selectedIds.isEmpty || books == null) return;
    final destination = await showDialog<String>(
      context: context,
      builder: (context) =>
          LibraryMoveToGroupDialog(groups: _bookListController.groups),
    );
    if (destination == null) return;
    // 立即退出選取模式，而非等到逐筆寫入資料庫的迴圈結束後才退出：這個迴圈
    // 期間「移動到分類」按鈕仍會顯示在選取模式的 App Bar 上，若不提早退出，
    // 使用者理論上可以在寫入尚未完成時再次點擊，重複觸發本方法。
    _exitSelectionMode();
    await _batchActions.moveToGroup(selectedIds, books, destination);
    await _bookListController.loadBooks();
  }

  /// 對選取集合中所有 EPUB 書籍手動覆寫「引擎分派判斷」結果為固定版面
  /// （FXL）——救濟部分漫畫 EPUB 因來源檔案 metadata 不完整/不規範，被
  /// 「引擎分派判斷」誤判為流式的情況（見 CONTEXT.md「人工版面覆蓋」）。
  /// 非 EPUB 書籍（PDF/TXT）自動跳過，不影響、不拋錯。行為比照
  /// _moveSelectedBooksToGroup()：無確認對話框、無完成後 SnackBar，立即
  /// 退出選取模式後才逐筆寫入，避免寫入期間使用者重複點擊觸發本方法。
  /// **`selectedIds` 在 `_exitSelectionMode()` 之前捕捉是安全的**：
  /// `_exitSelectionMode()` 只把 `_selectedBookIds` 欄位重新賦值為
  /// `null`，不會 mutate 這裡捕捉到的 Set 物件本身，比照
  /// `_moveSelectedBooksToGroup()`/`_deleteSelectedBooks()` 既有慣例
  /// （已於 plan-issue-15.md 審查階段確認，見 `reviews/` 對應報告）。
  Future<void> _forceFixedLayoutForSelectedBooks() async {
    final selectedIds = _selectedBookIds;
    final books = _bookListController.books;
    if (selectedIds == null || selectedIds.isEmpty || books == null) return;
    _exitSelectionMode();
    await _batchActions.forceFixedLayout(selectedIds, books);
    await _bookListController.loadBooks();
  }

  /// 對選取集合中所有 EPUB 書籍重新呼叫既有 detectAndCacheEpubLayout()，
  /// 回到系統原始的「引擎分派判斷」結果——用於復原誤按/誤判後想撤銷人工
  /// 覆蓋的情況（見 CONTEXT.md「人工版面覆蓋」）。非 EPUB 書籍自動跳過。
  /// 行為比照 _forceFixedLayoutForSelectedBooks()，含其「捕捉 selectedIds
  /// 參考早於 _exitSelectionMode() 是安全的」註記。
  Future<void> _restoreAutoLayoutForSelectedBooks() async {
    final selectedIds = _selectedBookIds;
    final books = _bookListController.books;
    if (selectedIds == null || selectedIds.isEmpty || books == null) return;
    _exitSelectionMode();
    await _batchActions.restoreAutoLayout(selectedIds, books);
    await _bookListController.loadBooks();
  }

  Future<bool?> _confirmDeleteBooks(int count) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final l10n = AppLocalizations.of(dialogContext)!;
        return AlertDialog(
          title: Text(l10n.libraryDeleteBooksDialogTitle),
          content: Text(l10n.libraryDeleteBooksConfirmMessage(count)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.cancel),
            ),
            TextButton(
              key: const Key('library_delete_confirm_button'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.libraryDeleteBooksConfirmButton),
            ),
          ],
        );
      },
    );
  }

  Future<void> _deleteSelectedBooks() async {
    final selectedIds = _selectedBookIds;
    final books = _bookListController.books;
    if (selectedIds == null || selectedIds.isEmpty || books == null) return;
    final confirmed = await _confirmDeleteBooks(selectedIds.length);
    if (confirmed != true) return;
    // 比照既有 _openManageGroupsDialog() 的既有慣例：await 跳出 dialog 的
    // 操作之後、觸碰 state 之前先確認 widget 是否仍在畫面上（同檔案內
    // 多數 await-dialog 後的路徑皆有此檢查，_moveSelectedBooksToGroup()
    // 缺這道檢查屬既有缺口，不在本工單範圍內一併修正）。
    if (!mounted) return;
    // 比照既有 _moveSelectedBooksToGroup()：先退出選取模式，避免刪除迴圈
    // 執行期間使用者重複點擊觸發本方法。
    _exitSelectionMode();
    await _batchActions.deleteBooks(selectedIds, books);
    await _bookListController.loadBooks();
  }

  /// 移除本機快取：對選取集合中所有 Calibre 來源且已下載的書籍，
  /// 刪除實體檔案並標記 isDownloaded = false。保留 epubLocator / progress
  /// / 書籤 / 劃線 / 備註等使用者資料。
  Future<void> _removeLocalCacheForSelectedBooks() async {
    final selectedIds = _selectedBookIds;
    final books = _bookListController.books;
    if (selectedIds == null || selectedIds.isEmpty || books == null) return;
    _exitSelectionMode();
    await _batchActions.removeLocalCache(selectedIds, books);
    await _bookListController.loadBooks();
  }

  void _openBook(Book book) {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => buildReaderScreen(
              book: book,
              dependencies: widget.dependencies,
              isEinkMode: widget.appearance.isEinkMode,
            ),
          ),
        )
        .then((_) {
          // 【審查修正】ReaderScreen 內離開/背景時會把最新閱讀進度與定位寫入
          // 資料庫（見 Task 6），但 _books 這份記憶體快照不會自動跟著更新。
          // 若不在此重新載入，_books 仍持有進入閱讀器前的舊 Book 物件；之後
          // 任何以 _books 為來源的整列 updateBook()（例如
          // _moveSelectedBooksToGroup()）會用舊值覆蓋掉剛剛寫入的最新進度，
          // 造成資料遺失（`/superpowers:requesting-code-review` Critical 2）。
          // 這裡不檢查 mounted——_loadBooks() 內部已有等效保護（見其既有實作）。
          _bookListController.loadBooks();
        });
  }

  Future<bool?> _confirmRedownload(Book book, bool isMobileData) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final l10n = AppLocalizations.of(dialogContext)!;
        return AlertDialog(
          key: const Key('library_redownload_dialog'),
          title: Text(l10n.libraryRedownloadAction),
          content: Text(
            isMobileData
                ? l10n.libraryRedownloadConfirmMessageMobileData(book.title)
                : l10n.libraryRedownloadConfirmMessage(book.title),
          ),
          actions: [
            TextButton(
              key: const Key('library_redownload_cancel_button'),
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.cancel),
            ),
            TextButton(
              key: const Key('library_redownload_confirm_button'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.libraryRedownloadAction),
            ),
          ],
        );
      },
    );
  }

  /// 「待下載」書籍點擊重新下載（epic-30-calibre-remote-library Issue 4，
  /// spec.md「下載與快取生命週期」「重新下載」）：直接重用該書
  /// [Book.remoteDownloadUrl]（上次下載成功時已存的絕對 URL），不重新
  /// `fetchFeed()` 反查目錄——OPDS 協議不保證支援依 ID 反查單一條目。
  /// 下載暫存/永久落地兩段式流程比照 Issue 2 `RemoteCatalogScreen`
  /// `_DownloadQueueDialogState._downloadOne()` 既有模式（暫存目錄→複製
  /// 到永久 `remote_books/` 目錄→刪除暫存），避免把永久 `filePath` 指向
  /// OS 可回收的暫存路徑。
  Future<void> _handleRedownload(Book book) async {
    final remoteServerRepository = widget.sources.remoteServerRepository;
    final createOpdsClient = widget.sources.createOpdsClient;
    final remoteServerId = book.remoteServerId;
    final remoteDownloadUrl = book.remoteDownloadUrl;
    if (remoteServerId == null || remoteDownloadUrl == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)!.libraryRemoteDisabledMessage,
          ),
        ),
      );
      return;
    }
    if (_redownloadingBookIds.contains(book.id)) return;

    final isMobileData = await widget.sources.isMobileDataConnection();
    if (!mounted) return;
    final confirmed = await _confirmRedownload(book, isMobileData);
    if (confirmed != true) return;

    _redownloadingBookIds.add(book.id);
    // 〔審查 review-plan-issue-4.md Minor 採納〕宣告在 try 外，讓 catch
    // 區塊也能存取，用於下方「copy 到永久目錄中途失敗」時的暫存檔清理
    // ——比照 Issue 2 `_DownloadQueueDialogState._downloadOne()` 既有的
    // 同一防禦手法（`review-plan-issue-2.md` Finding 3）。
    String? tempPath;
    try {
      final servers = await remoteServerRepository.listServers();
      RemoteServerProfile? server;
      for (final s in servers) {
        if (s.id == remoteServerId) {
          server = s;
          break;
        }
      }
      if (server == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context)!.libraryRemoteServerNotFoundMessage,
            ),
          ),
        );
        return;
      }
      final password = await remoteServerRepository.loadPassword(
        remoteServerId,
      );
      final client = createOpdsClient();

      tempPath = await downloadToTempFile(
        client: client,
        server: server,
        acquisition: OpdsAcquisition(
          href: remoteDownloadUrl,
          format: book.format,
        ),
        format: book.format,
        password: password,
      );

      final permanentPath = await promoteToPermanent(tempPath);

      final updatedBook = book.copyWith(
        filePath: permanentPath,
        isDownloaded: true,
      );
      await widget.dependencies.libraryRepository.updateBook(updatedBook);
      // epic-10-search Issue 2（spec.md §7）：重新下載完成＝既有
      // content_index_status 列已因先前的「移除本機快取」被清空（見本
      // 計畫 Task 4），此處補上對應的 unsupported/pending 標記，讓這本
      // 書重新回到正確的索引狀態。search-index 只是衍生資料，寫入失敗
      // 不應讓使用者眼中「檔案已下載成功」被誤判為失敗
      // （review-plan-issue-2.md M-1）。
      try {
        await widget.dependencies.fullTextSearchSettingsRepository
            .handleBookAvailable(updatedBook);
      } catch (_) {
        // 靜默略過——檔案下載與資料庫標記更新才是核心操作，索引狀態可
        // 日後透過「重建索引」補上。
      }
      if (!mounted) return;
      await _bookListController.loadBooks();
    } catch (_) {
      // 〔審查 review-plan-issue-4.md Minor 採納〕downloadBook() 本身
      // 失敗/取消時已經自行清過暫存檔（見 OpdsHttpClient 文件），但
      // copy() 到永久目錄這一步若中途失敗（例如磁碟空間不足），暫存檔
      // 仍會殘留在 remote_download_temp/ 底下——防禦性再清一次，確保
      // 任何例外路徑都不留孤兒檔案。
      if (tempPath != null) {
        final leftover = File(tempPath);
        if (await leftover.exists()) await leftover.delete();
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.libraryRedownloadFailedMessage),
        ),
      );
    } finally {
      _redownloadingBookIds.remove(book.id);
    }
  }

  Future<void> _openManageGroupsDialog() async {
    await showDialog<void>(
      context: context,
      builder: (context) => LibraryGroupManagementDialog(
        repository: widget.dependencies.libraryRepository,
        initialGroups: _bookListController.groups,
      ),
    );
    await _bookListController.loadGroups();
    if (!mounted) return;
    await _bookListController.loadBooks();
  }

  void _openGroupFilteredView(String groupName) {
    setState(() {
      _activeGroupFilter = groupName;
      _paging.resetToFirstPage();
    });
  }

  void _exitGroupFilteredView() {
    setState(() {
      _activeGroupFilter = null;
      _paging.resetToFirstPage();
    });
  }

  /// `onMove`／`onRemoveCache`／`onDelete` 於 Task 4 實作；`onLayoutOverride`
  /// 於 Task 5 實作（`showLayoutOverride` 暫時固定 false，Task 5 才依
  /// `bookReaderPrefsRepository` 是否提供切換）。
  ///
  /// 【修正】改用 `BookAction` enum 回傳模式：`BookActionSheet` 透過
  /// `Navigator.pop(BookAction)` 回傳使用者選擇，Sheet 的 future 完成後
  /// 才在下一幀執行 callback，避免在 Sheet 尚未完全移除時同幀 push
  /// 新 Dialog 導致 Navigator 衝突（`review-plan-issue-4.md M-4`）。
  Future<void> _openBookActionSheet(Book book) async {
    final showRemoveCache =
        book.source == BookSource.calibreOpds && book.isDownloaded;
    final result = await EBSheetShell.show<BookAction>(
      context,
      title: convertText(book.title, _textConversion),
      isEinkMode: widget.appearance.isEinkMode,
      builder: (context) => BookActionSheet(
        book: book,
        showRemoveCache: showRemoveCache,
        showLayoutOverride: true,
      ),
    );
    if (!mounted || result == null) return;
    switch (result) {
      case BookAction.showDetails:
        _showBookDetails(book);
      case BookAction.move:
        _moveBookToGroup(book);
      case BookAction.layoutOverride:
        _showLayoutOverrideDialog(
          book,
          widget.dependencies.bookReaderPrefsRepository,
        );
      case BookAction.removeCache:
        _removeBookCache(book);
      case BookAction.delete:
        _deleteBook(book);
    }
  }

  void _showBookDetails(Book book) {
    // 【review-plan-issue-4.md M-4】Sheet 透過 `Navigator.pop` 回傳結果時，
    // Sheet Route 已被同步標記為待移除；`EBSheetShell.show` 的 Future 在
    // 微任務佇列中完成，此時 Sheet Route 已離開 Navigator 的路由堆疊，
    // 可安全地直接呼叫 `showDialog`，不需要額外的 `addPostFrameCallback`
    // 延遲——前版的延遲反而導致 Dialog Route 被排到 Sheet 關閉動畫的
    // 中途執行，造成 Sheet 尚未完全移除就 push 新 Route 的時序衝突。
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (context) =>
          _BookDetailsDialog(book: book, textConversion: _textConversion),
    );
  }

  void _showLayoutOverrideDialog(
    Book book,
    BookReaderPrefsRepository repository,
  ) {
    showDialog<void>(
      context: context,
      builder: (context) =>
          _LayoutOverrideDialog(bookId: book.id, repository: repository),
    );
  }

  Future<void> _moveBookToGroup(Book book) async {
    final destination = await showDialog<String>(
      context: context,
      builder: (context) =>
          LibraryMoveToGroupDialog(groups: _bookListController.groups),
    );
    if (destination == null) return;
    if (!mounted) return;
    final books = _bookListController.books;
    if (books == null) return;
    await _batchActions.moveToGroup({book.id}, books, destination);
    await _bookListController.loadBooks();
  }

  Future<bool?> _confirmRemoveBookCache(Book book) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final l10n = AppLocalizations.of(dialogContext)!;
        return AlertDialog(
          title: Text(l10n.libraryRemoveLocalCacheTooltip),
          content: Text(l10n.libraryRemoveCacheConfirmMessage(book.title)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.cancel),
            ),
            TextButton(
              key: const Key('book_action_remove_cache_confirm_button'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.libraryRemoveCacheConfirmButton),
            ),
          ],
        );
      },
    );
  }

  Future<void> _removeBookCache(Book book) async {
    final confirmed = await _confirmRemoveBookCache(book);
    if (confirmed != true) return;
    if (!mounted) return;
    final books = _bookListController.books;
    if (books == null) return;
    await _batchActions.removeLocalCache({book.id}, books);
    await _bookListController.loadBooks();
  }

  /// 【計劃範圍澄清第 3 點】不需要額外手動重新計算 `_mostRecentBook`——
  /// `_bookListController.loadBooks()` 成功後一律 `notifyListeners()`，
  /// `initState()` 已註冊的 `_onBookListChanged()` 監聽器會自動重算，比照
  /// 既有 `_deleteSelectedBooks()` 等批次方法的既有寫法。
  Future<void> _deleteBook(Book book) async {
    final confirmed = await _confirmDeleteBooks(1);
    if (confirmed != true) return;
    if (!mounted) return;
    final books = _bookListController.books;
    if (books == null) return;
    await _batchActions.deleteBooks({book.id}, books);
    await _bookListController.loadBooks();
  }

  void _changeSortBy(LibrarySortBy sortBy) {
    setState(() => _paging.resetToFirstPage());
    _bookListController.changeSortBy(sortBy);
  }

  List<Book> _filterBooksBySearchQuery(List<Book> books, String query) {
    final normalized = query.trim().toLowerCase();
    return books
        .where(
          (book) =>
              book.title.toLowerCase().contains(normalized) ||
              (book.author?.toLowerCase().contains(normalized) ?? false),
        )
        .toList();
  }

  /// 展開後放在 AppBar 的 title 位置，取代「書架」標題。
  Widget _buildSearchField() {
    return TextField(
      key: const Key('library_search_field'),
      controller: _searchController,
      onChanged: _onSearchChanged,
      autofocus: true,
      decoration: InputDecoration(
        prefixIcon: const Icon(Icons.search),
        hintText: AppLocalizations.of(context)!.librarySearchHint,
        isDense: true,
        border: const OutlineInputBorder(),
        suffixIcon: _searchQuery.isEmpty
            ? null
            : IconButton(
                key: const Key('library_search_clear_button'),
                icon: const Icon(Icons.clear),
                onPressed: _onSearchCleared,
              ),
      ),
    );
  }

  /// 標題列上的搜尋列開關：收合時是 🔍，展開時是 ✕（清空關鍵字並收合，
  /// 書架恢復完整清單）。
  Widget _buildSearchToggleButton() {
    final l10n = AppLocalizations.of(context)!;
    if (!_searchExpanded) {
      return IconButton(
        key: const Key('library_search_toggle_button'),
        icon: const Icon(Icons.search),
        tooltip: l10n.librarySearchHint,
        onPressed: () => setState(() => _searchExpanded = true),
      );
    }
    return IconButton(
      key: const Key('library_search_close_button'),
      icon: const Icon(Icons.close),
      tooltip: l10n.close,
      onPressed: () {
        _onSearchCleared();
        setState(() => _searchExpanded = false);
      },
    );
  }

  void _onSearchCleared() {
    _searchController.clear();
    _onSearchChanged('');
  }

  /// 「搜尋書本內容」入口（epic-10-search Issue 4，spec.md §5）：帶入目前
  /// 書架快速過濾欄位的關鍵字，導航至 `LibrarySearchScreen`。
  void _openLibrarySearchScreen() {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => LibrarySearchScreen(
              initialQuery: _searchQuery,
              dependencies: widget.dependencies,
              isEinkMode: widget.appearance.isEinkMode,
            ),
          ),
        )
        // 【審查修正 M-1】比照既有 _openBook() 慣例：使用者可能從全庫搜尋
        // 畫面點進 ReaderScreen 閱讀後才返回書架，若不重新整理，
        // _bookListController 持有的書籍清單快照會殘留舊的閱讀進度/排序。
        .then((_) => _bookListController.loadBooks());
  }

  /// 「搜尋書本內容」入口：書架標題列上、排序按鈕左邊的圖示按鈕。
  /// 點了是跳到 `LibrarySearchScreen` 另外輸入，不需要在書架內容區佔一
  /// 整列（2026-09-28 使用者需求：讓出高度，Mobiscribe Wave 可排兩列封面）。
  /// 只放在一般標題列；多選模式換成選取工具列，入口自然不出現，維持
  /// 【審查修正 M-2】「選取中不可跳轉畫面」的原意。
  Widget _buildContentSearchEntryButton() {
    return IconButton(
      key: const Key('library_content_search_entry_button'),
      icon: const Icon(Icons.travel_explore),
      tooltip: AppLocalizations.of(context)!.libraryContentSearchEntryLabel,
      onPressed: _openLibrarySearchScreen,
    );
  }

  @override
  Widget build(BuildContext context) {
    final books = _bookListController.books;
    final trimmedQuery = _searchQuery.trim();
    final searchResults = trimmedQuery.isEmpty || books == null
        ? null
        : _filterBooksBySearchQuery(books, trimmedQuery);
    return PopScope(
      canPop: !_inSelectionMode && _activeGroupFilter == null,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_inSelectionMode) {
          _exitSelectionMode();
        } else if (_activeGroupFilter != null) {
          _exitGroupFilteredView();
        }
      },
      child: Scaffold(
        appBar: _inSelectionMode
            ? _buildSelectionAppBar()
            : _buildNormalAppBar(books),
        body: books == null
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Expanded(
                    child: searchResults != null
                        ? (searchResults.isEmpty
                              ? Center(
                                  child: Text(
                                    AppLocalizations.of(context)!
                                        .libraryNoMatchingBooks,
                                  ),
                                )
                              : _buildBookList(
                                  books,
                                  searchResults: searchResults,
                                ))
                        : (books.isEmpty
                              ? _buildEmptyState()
                              : _buildBookList(books)),
                  ),
                ],
              ),
      ),
    );
  }

  AppBar _buildNormalAppBar(List<Book>? books) {
    final l10n = AppLocalizations.of(context)!;
    return AppBar(
      leading: _activeGroupFilter == null
          ? null
          : IconButton(
              key: const Key('library_back_from_group_button'),
              icon: const Icon(Icons.arrow_back),
              tooltip: l10n.libraryBackButtonTooltip,
              onPressed: _exitGroupFilteredView,
            ),
      title: _searchExpanded
          ? _buildSearchField()
          : Text(_activeGroupFilter ?? l10n.libraryShelfTitle),
      actions: [
        _buildSearchToggleButton(),
        _buildContentSearchEntryButton(),
        PopupMenuButton<void>(
          key: const Key('library_sort_view_button'),
          icon: const Icon(Icons.sort),
          tooltip: l10n.librarySortViewTooltip,
          enabled: books != null,
          itemBuilder: (context) {
            final currentSort = _bookListController.sortBy;
            final primaryColor = Theme.of(context).colorScheme.primary;
            final menuL10n = AppLocalizations.of(context)!;
            return [
              for (final sortBy in LibrarySortBy.values)
                PopupMenuItem<void>(
                  key: Key('library_sort_option_${sortBy.name}'),
                  onTap: () => _changeSortBy(sortBy),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 24,
                        child: currentSort == sortBy
                            ? Icon(Icons.check, size: 20, color: primaryColor)
                            : null,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _sortLabel(sortBy, menuL10n),
                        style: TextStyle(
                          fontWeight: currentSort == sortBy
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: currentSort == sortBy ? primaryColor : null,
                        ),
                      ),
                    ],
                  ),
                ),
              const PopupMenuDivider(),
              PopupMenuItem<void>(
                key: const Key('library_sort_view_toggle_option'),
                onTap: _toggleViewMode,
                child: Text(
                  _viewMode == LibraryViewMode.grid
                      ? menuL10n.libraryToggleViewToList
                      : menuL10n.libraryToggleViewToShelf,
                ),
              ),
              if (_activeGroupFilter == null)
                PopupMenuItem<void>(
                  key: const Key('library_manage_groups_option'),
                  onTap: _openManageGroupsDialog,
                  child: Text(menuL10n.libraryManageGroupsMenuItem),
                ),
            ];
          },
        ),
        IconButton(
          key: const Key('library_source_button'),
          icon: const Icon(Icons.cloud_download),
          tooltip: l10n.librarySourceTooltip,
          onPressed: widget.onNavigateToSource,
        ),
        IconButton(
          key: const Key('library_settings_button'),
          icon: const Icon(Icons.settings),
          tooltip: l10n.librarySettingsTooltip,
          onPressed: widget.onNavigateToSettings,
        ),
      ],
    );
  }

  AppBar _buildSelectionAppBar() {
    final count = _selectedBookIds?.length ?? 0;
    final l10n = AppLocalizations.of(context)!;
    return AppBar(
      key: const Key('library_selection_app_bar'),
      leading: IconButton(
        key: const Key('library_selection_cancel_button'),
        icon: const Icon(Icons.close),
        tooltip: l10n.libraryCancelSelectionTooltip,
        onPressed: _exitSelectionMode,
      ),
      title: Text(l10n.librarySelectedCount(count)),
      actions: [
        IconButton(
          key: const Key('library_move_to_group_button'),
          icon: const Icon(Icons.drive_file_move),
          tooltip: l10n.libraryMoveToGroupTooltip,
          onPressed: count == 0 ? null : _moveSelectedBooksToGroup,
        ),
        IconButton(
          key: const Key('library_force_fxl_button'),
          icon: const Icon(Icons.menu_book),
          tooltip: l10n.libraryForceFxlTooltip,
          onPressed: count == 0 ? null : _forceFixedLayoutForSelectedBooks,
        ),
        IconButton(
          key: const Key('library_restore_auto_layout_button'),
          icon: const Icon(Icons.restore),
          tooltip: l10n.libraryRestoreAutoLayoutTooltip,
          onPressed: count == 0 ? null : _restoreAutoLayoutForSelectedBooks,
        ),
        IconButton(
          key: const Key('library_delete_books_button'),
          icon: const Icon(Icons.delete),
          tooltip: l10n.libraryDeleteTooltip,
          onPressed: count == 0 ? null : _deleteSelectedBooks,
        ),
        IconButton(
          key: const Key('library_remove_local_cache_button'),
          icon: const Icon(Icons.cloud_off_outlined),
          tooltip: l10n.libraryRemoveLocalCacheTooltip,
          onPressed: count == 0 ? null : _removeLocalCacheForSelectedBooks,
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l10n.libraryEmptyStateMessage),
          const SizedBox(height: 12),
          ElevatedButton(
            key: const Key('library_empty_import_button'),
            onPressed: widget.onNavigateToSource,
            child: Text(l10n.libraryEmptyStateImportButton),
          ),
        ],
      ),
    );
  }

  /// 依目前已載入的 [books]（已依 _sortBy 排序）分組，只保留非空的具名
  /// 分類；拼貼格彼此的相對順序＝該分類「排序第一的書籍」在 [books] 中
  /// 出現的順序（`byGroup.keys` 為 `LinkedHashMap` 插入順序，等於書籍
  /// 依目前 `_sortBy` 排序後被迭代到的順序）。
  ///
  /// 【真機使用回報，epic-18-reader-device-qa Issue 31】原本拼貼格順序
  /// 固定依 `_groups`（`_loadGroups()` 讀取的分類清單快照，name ASC）
  /// 排序，完全不受使用者選定的排序模式（例如「最後閱讀」）影響——切換
  /// 排序條件時，書架上未分類書籍與各分類拼貼格內的書籍預覽確實會重新
  /// 排序，但拼貼格「彼此之間」的先後順序始終原地不動。改為直接沿用
  /// `byGroup.keys`（不再參考 `_groups` 的名稱順序），拼貼格順序即與
  /// `_sortBy` 一致，且因為所有分類（含 `_groups` 快照可能落後未涵蓋到
  /// 的孤兒分類）皆統一來自同一份 `byGroup`，不會有分類從書架「消失」
  /// （原本 `_groups` 落後時靠獨立的孤兒兜底桶收留，見本次修正前的舊
  /// 版註解；新寫法下這個安全網已內建在單一資料來源中，不需要再額外
  /// 處理）。
  ///
  /// 【診斷修正】「未分類」不產生拼貼格——`BookGroup.uncategorized` 的書籍
  /// 已經透過 `_buildBookList()` 的 `visibleBooks` 過濾邏輯純粹以個別書籍
  /// 項目顯示在頂層書籍清單中，若還額外顯示一個「未分類」拼貼格，等於同一
  /// 批書籍在畫面上出現兩種呈現方式，造成混淆；只有具名分類才需要拼貼格
  /// 這種「摘要縮圖」的呈現方式。
  List<_GroupTile> _buildGroupTiles(List<Book> books) {
    final byGroup = <String, List<Book>>{};
    for (final book in books) {
      byGroup.putIfAbsent(book.groupName, () => []).add(book);
    }
    return [
      for (final name in byGroup.keys)
        if (name != BookGroup.uncategorized)
          _GroupTile(
            name: name,
            previewBooks: byGroup[name]!.take(4).toList(),
            totalCount: byGroup[name]!.length,
          ),
    ];
  }

  /// [searchResults] 非 null 時代表正在搜尋（[_searchQuery] 非空）：改為
  /// 扁平清單顯示搜尋結果，不分類分組、忽略 [_activeGroupFilter]（Q7
  /// 決策：搜尋範圍為全庫，不受目前分類瀏覽狀態影響）。
  Widget _buildBookList(List<Book> books, {List<Book>? searchResults}) {
    final isSearching = searchResults != null;
    final selectedIds = _selectedBookIds;
    final groupTiles = (!isSearching && _activeGroupFilter == null)
        ? _buildGroupTiles(books)
        : const <_GroupTile>[];
    final visibleBooks = isSearching
        ? searchResults
        : (_activeGroupFilter == null
              ? books
                    .where((b) => b.groupName == BookGroup.uncategorized)
                    .toList()
              : books.where((b) => b.groupName == _activeGroupFilter).toList());
    final itemCount = groupTiles.length + visibleBooks.length;

    final orientation = MediaQuery.orientationOf(context);
    final crossAxisCount = libraryPageSizeForOrientation(orientation);

    Widget itemBuilder(
      BuildContext context,
      int globalIndex, {
      required bool isGrid,
    }) {
      if (globalIndex < groupTiles.length) {
        final tile = groupTiles[globalIndex];
        final onTap = _inSelectionMode
            ? null
            : () => _openGroupFilteredView(tile.name);
        return isGrid
            ? _GroupGridTile(tile: tile, onTap: onTap)
            : _GroupListTile(tile: tile, onTap: onTap);
      }
      final book = visibleBooks[globalIndex - groupTiles.length];
      return isGrid
          ? _BookGridTile(
              book: book,
              selectionMode: _inSelectionMode,
              selected: selectedIds?.contains(book.id) ?? false,
              onTap: () => _onBookTap(book),
              onLongPress: () => _onBookLongPress(book),
              onMenuTap: () => _openBookActionSheet(book),
              textConversion: _textConversion,
            )
          : _BookListTile(
              book: book,
              selectionMode: _inSelectionMode,
              selected: selectedIds?.contains(book.id) ?? false,
              onTap: () => _onBookTap(book),
              onLongPress: () => _onBookLongPress(book),
              onMenuTap: () => _openBookActionSheet(book),
              textConversion: _textConversion,
            );
    }

    return Column(
      children: [
        if (!isSearching &&
            _activeGroupFilter == null &&
            _mostRecentBook != null)
          _ContinueReadingRow(
            book: _mostRecentBook!,
            // 多選模式進行中時停用點擊（`review-plan-issue-3.md` M-3）：
            // 本列沒有勾選指示器，若不停用，使用者在多選時點到它會在
            // 毫無視覺反饋的情況下切換 _mostRecentBook 的選取狀態，比照
            // `_GroupGridTile`／`_GroupListTile` 在 _inSelectionMode 時
            // 一律把 onTap 傳 null 的既有慣例。
            onTap: _inSelectionMode ? null : () => _onBookTap(_mostRecentBook!),
            textConversion: _textConversion,
          ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              // 依實際可用寬高動態計算每頁列數（epic-36 Issue 7），取代
              // Issue 3 寫死「1 行」的舊假設。寬度換算封面格寬/高；高度
              // 扣掉 PagingBar 自身固定高度、以及 GridView 自身上下
              // padding（各 8dp，合計 16dp）後才是 Grid 內容真正可用高度
              // ——這兩者是本區塊唯一需要手動參照的高度常數（PagingBar
              // 因為它被移進了這個 LayoutBuilder 的回傳子樹，GridView
              // padding 因為它是 GridView 自己的既有參數，不是外層
              // Column 佈局能自動消化的東西），AppBar／搜尋列／繼續閱讀
              // 列的高度則由外層 Column／Expanded 佈局自然算出剩餘空
              // 間，不需要在這裡手動加總（`issues.md` Issue 7 Solution
              // 段落；`review-plan-issue-7.md` C-1：原計劃書漏算了
              // GridView 自身 padding，會在邊界高度裁切底列內容）。
              const gridPadding = 8.0;
              const gridSpacing = 8.0;
              // 2026-09-28：12 → 4，縮小書架每列之間的空白。
              const rowSpacing = 4.0;
              final cellWidth =
                  (constraints.maxWidth -
                      2 * gridPadding -
                      (crossAxisCount - 1) * gridSpacing) /
                  crossAxisCount;
              // `_kCellAspectRatio` 是 GridView 每個 cell「整體」的寬高比
              // （封面＋文字說明區合計，見 `_BookGridTile`：外層 Column
              // 的總高度受 `childAspectRatio` 約束，封面只是 Expanded
              // 取得的剩餘空間），不是純封面的寬高比——`cellWidth /
              // _kCellAspectRatio` 本身就已經是含文字說明區的整個 cell
              // 高度，不能再另外疊加 footerHeight（`review-plan-issue-7.md`
              // C-2：疊加會造成單列高度虛增 30~50dp，動態列數因此算得比
              // 實際能放下的還要少，違背 Issue 7「消除留白」的目的）。
              final rowContentHeight = cellWidth / _kCellAspectRatio;
              final pagingBarHeight = PagingBar.resolvedHeight(
                widget.appearance.isEinkMode,
              );
              final availableGridHeight =
                  constraints.maxHeight - pagingBarHeight - 2 * gridPadding;
              // Grid／List 兩種檢視各自獨立算 pageSize（epic-36 Issue 7
              // 追加修正——I-1：原本兩者共用同一組依 Grid cell 幾何算出的
              // pageSize，但 ListTile 實際高度與 Grid cell 完全脫鉤，窄高
              // 裝置下 List 這一頁可能因 NeverScrollableScrollPhysics 而
              // 裁切掉部分項目——看得到頁碼卻看不到/點不到書籍）。List 是
              // 單欄，pageSize 即為列數本身，不需要再乘欄數。
              final gridRows = libraryRowsForHeight(
                availableHeight: availableGridHeight,
                rowContentHeight: rowContentHeight,
                rowSpacing: rowSpacing,
              );
              final listRowHeight = libraryListRowHeight(
                MediaQuery.textScalerOf(context),
              );
              final listRows = libraryRowsForHeight(
                availableHeight: availableGridHeight,
                rowContentHeight: listRowHeight,
                rowSpacing: 0,
              );
              final pageSize = _viewMode == LibraryViewMode.grid
                  ? crossAxisCount * gridRows
                  : listRows;

              final pageCount = _paging.clamp(
                itemCount: itemCount,
                pageSize: pageSize,
              );
              final safePage = _paging.currentPage;
              final pageStart = safePage * pageSize;
              final pageEnd = (pageStart + pageSize).clamp(0, itemCount);
              final pageItemCount = pageEnd - pageStart;

              final Widget gridOrList;
              if (_viewMode == LibraryViewMode.grid) {
                gridOrList = GridView.builder(
                  key: const Key('library_grid_view'),
                  padding: const EdgeInsets.all(gridPadding),
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    childAspectRatio: _kCellAspectRatio,
                    crossAxisSpacing: gridSpacing,
                    mainAxisSpacing: rowSpacing,
                  ),
                  itemCount: pageItemCount,
                  itemBuilder: (context, index) =>
                      itemBuilder(context, pageStart + index, isGrid: true),
                );
              } else {
                gridOrList = ListView.builder(
                  key: const Key('library_list_view'),
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: pageItemCount,
                  itemBuilder: (context, index) =>
                      itemBuilder(context, pageStart + index, isGrid: false),
                );
              }

              return Column(
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: gridOrList,
                    ),
                  ),
                  PagingBar(
                    key: const Key('library_paging_bar'),
                    currentPage: safePage,
                    pageCount: pageCount,
                    onPrevious: safePage > 0
                        ? () => setState(() => _paging.goToPreviousPage())
                        : null,
                    onNext: safePage < pageCount - 1
                        ? () => setState(() => _paging.goToNextPage())
                        : null,
                    isEinkMode: widget.appearance.isEinkMode,
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

/// 單一分類在書架分類拼貼格上的顯示資料，純畫面呈現用途，不持久化、不
/// 跨檔案共用，故不建成 library/models 底下的公開模型。
class _GroupTile {
  final String name;
  final List<Book> previewBooks; // 最多 4 本，依目前排序結果順序截取前 4 筆
  final int totalCount;
  const _GroupTile({
    required this.name,
    required this.previewBooks,
    required this.totalCount,
  });
}

/// 分類拼貼格（格狀檢視）：2×2 拼貼＋分類名稱/數量，重用既有 _BookCover。
/// onTap 為 null 時（選取模式進行中）InkWell 自動停用點擊反饋，比照
/// Flutter 既有「null 停用互動」慣例。
class _GroupGridTile extends StatelessWidget {
  final _GroupTile tile;
  final VoidCallback? onTap;
  const _GroupGridTile({required this.tile, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      key: Key('group_tile_${tile.name}'),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 【診斷修正】改用 Column/Row 巢狀 Expanded 手排 2×2，不用
          // GridView.count——GridView 的儲存格高度由
          // 寬度／childAspectRatio 換算得出（未明講時預設 1.0，即正方形），
          // 與外層 Expanded 實際分配到的高度無關；外層拼貼格採用較窄長的
          // 比例（childAspectRatio: 0.62），正方形的 2×2 網格本身高度只
          // 略等於自身寬度，遠小於 Expanded 分配到的可用高度，
          // NeverScrollableScrollPhysics 又不會讓內容撐滿捲動範圍，導致
          // 封面區塊下方留下大片空白（真機使用回報）。改手排後每個儲存格
          // 皆用 Expanded 包裹，強制精確填滿可用寬高，不受任何比例換算
          // 影響。
          Expanded(
            child: DecoratedBox(
              // 視覺還原（VISUAL_ANALYSIS.md）：Reference 截圖每個分類拼貼
              // 格都有外框＋左上角「分類」角標，原本完全沒有實作。
              decoration: BoxDecoration(
                border: Border.all(color: colorScheme.outline, width: 1.5),
              ),
              child: Column(
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      color: colorScheme.primary,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      child: Text(
                        AppLocalizations.of(context)!.libraryGroupBadgeLabel,
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onPrimary,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        Expanded(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(child: _groupTilePreviewCell(0)),
                              const SizedBox(width: 2),
                              Expanded(child: _groupTilePreviewCell(1)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 2),
                        Expanded(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(child: _groupTilePreviewCell(2)),
                              const SizedBox(width: 2),
                              Expanded(child: _groupTilePreviewCell(3)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: gridTileFooterHeight(MediaQuery.textScalerOf(context)),
            child: Text(
              '${tile.name} (${AppLocalizations.of(context)!.libraryGroupTileCount(tile.totalCount)})',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _groupTilePreviewCell(int index) {
    return index < tile.previewBooks.length
        ? BookCover(book: tile.previewBooks[index])
        : const CoverPlaceholder(icon: Icons.book);
  }
}

/// 分類拼貼格（列表檢視）：橫向 4 張小縮圖＋名稱＋數量，不強行套用 2×2
/// 方形拼貼於列表列。
class _GroupListTile extends StatelessWidget {
  final _GroupTile tile;
  final VoidCallback? onTap; // null＝選取模式進行中，停用點擊（同 _GroupGridTile）
  const _GroupListTile({required this.tile, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: Key('group_tile_${tile.name}'),
      leading: SizedBox(
        width: 4 * 32,
        height: 48,
        child: Row(
          children: List.generate(
            4,
            (i) => SizedBox(
              width: 32,
              height: 48,
              child: i < tile.previewBooks.length
                  ? BookCover(book: tile.previewBooks[i])
                  : const CoverPlaceholder(icon: Icons.book),
            ),
          ),
        ),
      ),
      // maxLines/overflow（epic-36 Issue 7 追加修正——I-1）：分類名稱過長
      // 換行會撐高這一列，讓 libraryListRowHeight() 假設的固定列高失準，
      // 進而讓依此估算出的 pageSize 偏多、造成本頁部分項目被裁切。
      title: Text(tile.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        AppLocalizations.of(context)!.libraryGroupTileCount(tile.totalCount),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: onTap,
    );
  }
}

String _sortLabel(LibrarySortBy sortBy, AppLocalizations l10n) {
  switch (sortBy) {
    case LibrarySortBy.lastRead:
      return l10n.librarySortByLastRead;
    case LibrarySortBy.createTime:
      return l10n.librarySortByCreateTime;
    case LibrarySortBy.author:
      return l10n.librarySortByAuthor;
    case LibrarySortBy.title:
      return l10n.librarySortByTitle;
  }
}

IconData _sourceIcon(BookSource source) {
  switch (source) {
    case BookSource.local:
      return Icons.smartphone;
    case BookSource.googleDrive:
      return Icons.cloud;
    case BookSource.oneDrive:
      return Icons.cloud_outlined;
    case BookSource.calibreOpds:
      return Icons.dns;
  }
}

String _progressText(Book book) => '${(book.progress * 100).round()}%';

class _BookGridTile extends StatelessWidget {
  final Book book;
  final bool selectionMode;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onMenuTap;
  final TextConversionMode textConversion;

  const _BookGridTile({
    required this.book,
    required this.selectionMode,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
    required this.onMenuTap,
    required this.textConversion,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final tokens = Theme.of(context).extension<ElinkTokens>()!;
    return InkWell(
      key: Key('book_item_${book.id}'),
      onTap: onTap,
      onLongPress: onLongPress,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                BookCover(book: book, textConversion: textConversion),
                if (selectionMode)
                  Align(
                    alignment: Alignment.topRight,
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: tokens.badgeScrim,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          selected
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked,
                          key: Key('book_selection_indicator_${book.id}'),
                          color: selected ? colorScheme.primary : Colors.white,
                        ),
                      ),
                    ),
                  )
                else
                  Align(
                    alignment: Alignment.topRight,
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      // 2026-09-28：看得到的圓縮為原本的一半（48 → 24，原本
                      // Material 3 自動補足觸控區，實際渲染是 48）；IconButton
                      // 本身維持 48 觸控區，只把圓畫小，不會變得更難點到。
                      child: IconButton(
                        key: Key('book_action_menu_${book.id}'),
                        icon: Container(
                          key: Key('book_action_menu_circle_${book.id}'),
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: tokens.badgeScrim,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.more_vert,
                            color: Colors.white,
                            size: 14,
                          ),
                        ),
                        padding: EdgeInsets.zero,
                        // 小圓貼齊右上角，維持原本靠封面角落的位置。
                        alignment: Alignment.topRight,
                        constraints: const BoxConstraints(
                          minWidth: 48,
                          minHeight: 48,
                        ),
                        tooltip: AppLocalizations.of(context)!.libraryBookMenuTooltip,
                        onPressed: onMenuTap,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: gridTileFooterHeight(MediaQuery.textScalerOf(context)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  convertText(book.title, textConversion),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12),
                ),
                Text(
                  _progressText(book),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BookListTile extends StatelessWidget {
  final Book book;
  final bool selectionMode;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onMenuTap;
  final TextConversionMode textConversion;

  const _BookListTile({
    required this.book,
    required this.selectionMode,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
    required this.onMenuTap,
    required this.textConversion,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: Key('book_item_${book.id}'),
      selected: selected,
      // 選取模式下把 Checkbox 與封面並列（而非直接取代封面）：使用者在
      // 列表批次選取時仍需要看得到封面才能分辨是哪一本書（例如同系列不同
      // 集數，書名文字可能高度相似），純 Checkbox 會讓列表失去辨識度
      // （審查意見）。
      leading: SizedBox(
        width: selectionMode ? 88 : 48,
        height: 64,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selectionMode)
              Checkbox(
                key: Key('book_selection_indicator_${book.id}'),
                value: selected,
                // 縮小點擊熱區至 40x40（預設 48x48 會讓熱區加上封面寬度
                // 超出上方 SizedBox 的 88px 總寬，造成 RenderFlex overflow）。
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onChanged: (_) => onTap(),
              ),
            SizedBox(
              width: 48,
              height: 64,
              child: BookCover(book: book, textConversion: textConversion),
            ),
          ],
        ),
      ),
      // maxLines/overflow（epic-36 Issue 7 追加修正——I-1）：書名/作者過長
      // 換行會撐高這一列，讓 libraryListRowHeight() 假設的固定列高失準，
      // 進而讓依此估算出的 pageSize 偏多、造成本頁部分項目被裁切。
      title: Text(convertText(book.title, textConversion),
          maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        convertText(book.author ?? '', textConversion),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(_sourceIcon(book.source), size: 16),
              Text(_progressText(book), style: const TextStyle(fontSize: 10)),
            ],
          ),
          if (!selectionMode)
            IconButton(
              key: Key('book_action_menu_${book.id}'),
              icon: const Icon(Icons.more_vert),
              tooltip: AppLocalizations.of(context)!.libraryBookMenuTooltip,
              onPressed: onMenuTap,
            ),
        ],
      ),
      onTap: onTap,
      onLongPress: onLongPress,
    );
  }
}

/// 頂層書架常駐「繼續閱讀列」（`DESIGN.md#L297` §15.1）：顯示使用者最後
/// 閱讀的那本書與進度，點擊直接跳轉繼續閱讀；不受下方分頁影響，
/// `_activeGroupFilter != null`（下鑽檢視分類）時由呼叫端負責不渲染
/// 本元件，本元件本身不做這個判斷。
class _ContinueReadingRow extends StatelessWidget {
  final Book book;
  final VoidCallback? onTap; // null＝多選模式進行中，停用點擊（見呼叫端註解）
  final TextConversionMode textConversion;

  const _ContinueReadingRow({
    required this.book,
    required this.onTap,
    required this.textConversion,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: const Key('library_continue_reading_row'),
      onTap: onTap,
      // 2026-09-28 壓矮本列（讓 Mobiscribe Wave 書架排得下兩列封面）：
      // 進度 % 併到「繼續閱讀」字眼後面，三行字改兩行，縮圖與上下內距
      // 跟著縮小。
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            SizedBox(
              width: 30,
              height: 42,
              child: BookCover(book: book, textConversion: textConversion),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${AppLocalizations.of(context)!.libraryContinueReadingLabel}'
                    ' · ${_progressText(book)}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  Text(
                    convertText(book.title, textConversion),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _FileSizeStatus { notDownloaded, unknown }

/// 單書「詳細資料」對話框（`spec.md` 功能④）：檔案大小查詢為非同步、
/// 具防護——`!book.isDownloaded` 直接顯示「尚未下載」不查詢檔案；
/// `content://` URI 或讀取失敗（`FileSystemException`）一律顯示
/// 「未知大小」，不得讓例外未捕捉往外拋（`review-spec.md` I-4）。
class _BookDetailsDialog extends StatefulWidget {
  final Book book;
  final TextConversionMode textConversion;
  const _BookDetailsDialog({required this.book, required this.textConversion});

  @override
  State<_BookDetailsDialog> createState() => _BookDetailsDialogState();
}

class _BookDetailsDialogState extends State<_BookDetailsDialog> {
  late final Future<Object> _fileSizeFuture;

  @override
  void initState() {
    super.initState();
    _fileSizeFuture = _resolveFileSize(widget.book);
  }

  static Future<Object> _resolveFileSize(Book book) async {
    if (!book.isDownloaded) return _FileSizeStatus.notDownloaded;
    try {
      final file = File(book.filePath);
      if (!file.existsSync()) return _FileSizeStatus.unknown;
      return file.statSync().size;
    } catch (_) {
      return _FileSizeStatus.unknown;
    }
  }

  static String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  static String _formatLastReadTime(
    DateTime time,
    AppLocalizations l10n,
    Locale locale,
  ) {
    if (time.millisecondsSinceEpoch <= 0) return l10n.libraryNeverRead;
    return DateFormat.yMd(locale.toString()).format(time);
  }

  @override
  Widget build(BuildContext context) {
    final book = widget.book;
    final l10n = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context);
    return AlertDialog(
      key: const Key('book_details_dialog'),
      title: Text(convertText(book.title, widget.textConversion)),
      content: FutureBuilder<Object>(
        future: _fileSizeFuture,
        builder: (context, snapshot) {
          final String fileSizeText;
          if (snapshot.hasError) {
            fileSizeText = l10n.libraryUnknownFileSize;
          } else if (!snapshot.hasData) {
            fileSizeText = l10n.libraryLoadingEllipsis;
          } else {
            fileSizeText = switch (snapshot.data!) {
              _FileSizeStatus.notDownloaded => l10n.libraryBookNotDownloaded,
              _FileSizeStatus.unknown => l10n.libraryUnknownFileSize,
              final int bytes => _formatFileSize(bytes),
              _ => l10n.libraryUnknownFileSize,
            };
          }
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.libraryDetailAuthorLabel(
                  book.author == null
                      ? l10n.libraryUnknownAuthor
                      : convertText(book.author!, widget.textConversion),
                ),
              ),
              Text(l10n.libraryDetailFormatLabel(book.format.name)),
              Text(l10n.libraryDetailFileSizeLabel(fileSizeText)),
              Text(l10n.libraryDetailProgressLabel(_progressText(book))),
              Text(
                l10n.libraryDetailLastReadLabel(
                  _formatLastReadTime(book.lastReadTime, l10n, locale),
                ),
              ),
            ],
          );
        },
      ),
      actions: [
        TextButton(
          key: const Key('book_details_dialog_close_button'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.close),
        ),
      ],
    );
  }
}

/// 單書版面覆寫對話框（`spec.md` 功能④「版面覆寫對話框」）。
///
/// **關鍵正確性要求**：`BookReaderPrefsRepository.save()` 是整列覆寫
/// （`INSERT OR REPLACE`），不是只更新有變動的欄位。`_save()` 必須先
/// `load()` 取得該書完整既有 `BookReaderPrefs`，只改
/// `writingModeOverride`/`pageTurnModeOverride` 兩個欄位、其餘欄位原樣
/// 帶回——**不可用 `copyWith()`**：`BookReaderPrefs.copyWith()` 是
/// `newValue ?? this.value` 語意（見 `book_reader_prefs.dart` 文件註解），
/// 選「使用預設」時本地狀態明確為 `null`，若用
/// `copyWith(writingModeOverride: null)` 會被 `??` 吃掉、不會真的清空既有
/// 覆寫值。比照 `reader_settings_sheet.dart` 既有 `_currentDraft` 的整列
/// 重建寫法（`plans/plan-issue-4.md`「計劃範圍澄清」第 2 點）。
class _LayoutOverrideDialog extends StatefulWidget {
  final String bookId;
  final BookReaderPrefsRepository repository;
  const _LayoutOverrideDialog({required this.bookId, required this.repository});

  @override
  State<_LayoutOverrideDialog> createState() => _LayoutOverrideDialogState();
}

class _LayoutOverrideDialogState extends State<_LayoutOverrideDialog> {
  BookReaderPrefs? _existingPrefs;
  WritingMode? _writingMode;
  PageTurnMode? _pageTurnMode;
  bool _isSaving = false; // 【review-plan-issue-4.md M-1】連點防護

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await widget.repository.load(widget.bookId);
    if (!mounted) return;
    setState(() {
      _existingPrefs = prefs;
      _writingMode = prefs.writingModeOverride;
      _pageTurnMode = prefs.pageTurnModeOverride;
    });
  }

  Future<void> _save() async {
    // 【review-plan-issue-4.md M-1】連續快速敲擊「儲存」時，第一次 await
    // 尚未返回前若觸發第二次 _save()，會導致連彈兩層路由（可能誤將呼叫端
    // 的畫面一併 pop 掉）。
    if (_isSaving) return;
    _isSaving = true;
    final existing = _existingPrefs;
    if (existing == null) return;
    // 【review-issue-4.md Important】此建構子逐一列出 BookReaderPrefs 目前
    // 全部欄位，僅 writingModeOverride/pageTurnModeOverride 取本地狀態、其餘
    // 原樣帶回既有值——若 BookReaderPrefs 未來新增欄位，此處必須同步補上，
    // 否則新欄位會在「版面覆寫」儲存時被靜默清空成預設值。
    final updated = BookReaderPrefs(
      fontFamily: existing.fontFamily,
      fontSize: existing.fontSize,
      fontWeight: existing.fontWeight,
      lineHeight: existing.lineHeight,
      paragraphSpacing: existing.paragraphSpacing,
      letterSpacing: existing.letterSpacing,
      pageMargins: existing.pageMargins,
      marginTop: existing.marginTop,
      marginBottom: existing.marginBottom,
      marginLeft: existing.marginLeft,
      marginRight: existing.marginRight,
      textAlign: existing.textAlign,
      publisherStyles: existing.publisherStyles,
      writingModeOverride: _writingMode,
      pageTurnModeOverride: _pageTurnMode,
      screenOrientationOverride: existing.screenOrientationOverride,
      pdfFitMode: existing.pdfFitMode,
      pdfContrast: existing.pdfContrast,
      pdfBrightness: existing.pdfBrightness,
      pdfBoldStrength: existing.pdfBoldStrength,
      pdfCropMode: existing.pdfCropMode,
      pdfCropRect: existing.pdfCropRect,
      dualPageMode: existing.dualPageMode,
      dualPageCoverAlone: existing.dualPageCoverAlone,
      dualPageDirection: existing.dualPageDirection,
      pdfPageTurnAnimation: existing.pdfPageTurnAnimation,
      pdfPageTurnMode: existing.pdfPageTurnMode,
      showHeader: existing.showHeader,
      showFooter: existing.showFooter,
      columnMode: existing.columnMode,
      columnSize: existing.columnSize,
      fullscreen: existing.fullscreen,
      textConversionOverride: existing.textConversionOverride,
    );
    await widget.repository.save(widget.bookId, updated);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (_existingPrefs == null) {
      // 【review-plan-issue-4.md M-3】loading 狀態仍保留 title／取消按鈕，
      // 避免儲存層載入慢時使用者無法從畫面上退出。
      return AlertDialog(
        key: const Key('layout_override_dialog'),
        title: Text(l10n.libraryLayoutOverrideTitle),
        content: const SizedBox(
          height: 80,
          child: Center(child: CircularProgressIndicator()),
        ),
        actions: [
          TextButton(
            key: const Key('layout_override_cancel_button'),
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.cancel),
          ),
        ],
      );
    }
    return AlertDialog(
      key: const Key('layout_override_dialog'),
      title: Text(l10n.libraryLayoutOverrideTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.libraryLayoutOverrideWritingModeLabel),
            Wrap(
              spacing: 4,
              children: [
                ReaderOptionTile<WritingMode?>(
                  itemKey: const Key('layout_override_writing_mode_default'),
                  value: null,
                  groupValue: _writingMode,
                  icon: Icons.auto_awesome,
                  tooltip: l10n.libraryLayoutOverrideWritingModeDefault,
                  onSelected: (v) => setState(() => _writingMode = v),
                ),
                ReaderOptionTile<WritingMode?>(
                  itemKey: const Key('layout_override_writing_mode_horizontal'),
                  value: WritingMode.horizontal,
                  groupValue: _writingMode,
                  icon: Icons.text_rotation_none,
                  tooltip: l10n.libraryLayoutOverrideWritingModeHorizontal,
                  onSelected: (v) => setState(() => _writingMode = v),
                ),
                ReaderOptionTile<WritingMode?>(
                  itemKey: const Key('layout_override_writing_mode_vertical'),
                  value: WritingMode.vertical,
                  groupValue: _writingMode,
                  icon: Icons.text_rotate_vertical,
                  tooltip: l10n.libraryLayoutOverrideWritingModeVertical,
                  onSelected: (v) => setState(() => _writingMode = v),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(l10n.libraryLayoutOverridePageTurnModeLabel),
            Wrap(
              spacing: 4,
              children: [
                ReaderOptionTile<PageTurnMode?>(
                  itemKey: const Key('layout_override_page_turn_mode_default'),
                  value: null,
                  groupValue: _pageTurnMode,
                  icon: Icons.tune,
                  tooltip: l10n.libraryLayoutOverridePageTurnModeDefault,
                  onSelected: (v) => setState(() => _pageTurnMode = v),
                ),
                ReaderOptionTile<PageTurnMode?>(
                  itemKey: const Key(
                    'layout_override_page_turn_mode_paginated',
                  ),
                  value: PageTurnMode.paginated,
                  groupValue: _pageTurnMode,
                  icon: Icons.menu_book,
                  tooltip: l10n.libraryLayoutOverridePageTurnModePaginated,
                  onSelected: (v) => setState(() => _pageTurnMode = v),
                ),
                ReaderOptionTile<PageTurnMode?>(
                  itemKey: const Key('layout_override_page_turn_mode_scroll'),
                  value: PageTurnMode.scroll,
                  groupValue: _pageTurnMode,
                  icon: Icons.swap_vert,
                  tooltip: l10n.libraryLayoutOverridePageTurnModeScroll,
                  onSelected: (v) => setState(() => _pageTurnMode = v),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('layout_override_cancel_button'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        TextButton(
          key: const Key('layout_override_save_button'),
          onPressed: _save,
          child: Text(l10n.libraryLayoutOverrideSaveButton),
        ),
      ],
    );
  }
}
