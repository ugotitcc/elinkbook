import 'dart:io';

import 'package:flutter/material.dart';

import '../library/book_content_fingerprint.dart';
import '../library/book_import_service.dart';
import '../reader/reader_prefs_manager.dart';
import '../remote/opds_types.dart';
import '../remote/remote_book_downloader.dart';
import '../remote/remote_server_profile.dart';
import '../library/library_preferences.dart';
import '../library/library_repository.dart';
import 'library_screen_dependencies.dart';
import 'book_grid_tile_metrics.dart';
import 'library_book_list_controller.dart';
import 'library_batch_actions.dart';
import '../library/models/book.dart';
import '../library/models/book_group.dart';
import '../library/models/library_enums.dart';
import '../library/widgets/book_cover.dart';
import '../theme/elink_tokens.dart';

import 'book_action_sheet.dart';
import 'library_group_management_dialog.dart';
import 'library_move_to_group_dialog.dart';
import 'library_paging.dart';
import 'reader_screen.dart';
import 'widgets/eb_sheet_shell.dart';
import 'widgets/paging_bar.dart';

/// 圖書庫主畫面：讀取 [LibraryRepository] 的真實資料，取代
/// epic-0-skeleton 遺留的固定範例書籍清單佔位版本（見
/// docs/epics/epic-1-library/spec.md）。
class LibraryScreen extends StatefulWidget {
  final LibraryRepository repository;
  final BookImportService importService;
  final ReaderPrefsManager prefsManager;
  /// 收斂原本 `bookmarksRepository`／`highlightsRepository`／
  /// `notesRepository`／`customFontsRepository`／`layoutPresetRepository`／
  /// `bookReaderPrefsRepository` 六個獨立參數（epic-26-architecture-hardening
  /// Issue 7）。
  final LibraryReaderFeatureRepositories readerFeatureRepositories;
  /// 收斂原本 `syncAccountRepository`／`syncClient`／`syncCheckpointTrigger`
  /// 三個獨立參數（epic-26-architecture-hardening Issue 7）。
  final LibrarySyncDependencies syncDependencies;
  /// 收斂原本 `cloudAccountRepository`／`googleDriveOAuthClient`／
  /// `oneDriveOAuthClient`／`googleDriveStorageClient`／
  /// `oneDriveStorageClient` 五個獨立參數（epic-26-architecture-hardening
  /// Issue 7）。
  final LibraryCloudAccountDependencies cloudAccountDependencies;
  /// 收斂原本 `remoteServerRepository`／`createOpdsClient`／`thumbnailCache`
  /// 三個獨立參數（epic-26-architecture-hardening Issue 7）。
  final LibraryRemoteLibraryDependencies remoteLibraryDependencies;
  final ComputeRemoteFingerprint? computeFingerprint;
  final Future<bool> Function()? isMobileDataConnection;
  /// 收斂原本 `currentTheme`／`isEinkMode`／`onThemeChanged`／`onEinkModeChanged`
  /// 四個獨立參數（epic-26-architecture-hardening Issue 7）。
  final LibraryThemeDependencies themeDependencies;
  final Listenable? refreshSignal;
  final VoidCallback? onNavigateToSource;
  final VoidCallback? onNavigateToSettings;

  const LibraryScreen({
    super.key,
    required this.repository,
    required this.importService,
    required this.prefsManager,
    this.readerFeatureRepositories = const LibraryReaderFeatureRepositories(),
    this.syncDependencies = const LibrarySyncDependencies(),
    this.cloudAccountDependencies = const LibraryCloudAccountDependencies(),
    this.remoteLibraryDependencies = const LibraryRemoteLibraryDependencies(),
    this.computeFingerprint,
    this.isMobileDataConnection,
    this.themeDependencies = const LibraryThemeDependencies(),
    this.refreshSignal,
    this.onNavigateToSource,
    this.onNavigateToSettings,
  });

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> with WidgetsBindingObserver {
  final _preferences = LibraryPreferences();
  late final LibraryBookListController _bookListController;
  late final LibraryBatchActions _batchActions;

  String? _activeGroupFilter;
  LibraryViewMode _viewMode = LibraryViewMode.grid;
  Set<String>? _selectedBookIds;
  final Set<String> _redownloadingBookIds = {};

  /// 目前頁碼（0-based）。分頁筆數固定依螢幕方向決定（見
  /// `library_paging.dart`），排序/分類切換時重置為 0，旋轉螢幕時依
  /// `libraryRecalculatePage()` 換算，其餘情況（管理分類、格狀/清單
  /// 切換）維持不變，見 plans/plan-issue-3.md「計劃範圍澄清」第 4、5 點。
  int _currentPage = 0;

  /// `didChangeMetrics()` 用來跟「新方向換算出的每頁筆數」比較，判斷是否
  /// 真的需要重新換算頁碼；於每次 `_buildBookList()` 呼叫後更新為最新值。
  int? _lastPageSize;

  /// 使用者最後閱讀的書籍（`lastReadTime` 最新且 > epoch 0 者），供頂層
  /// 書架的常駐「繼續閱讀列」使用；`_onBookListChanged()` 每次書籍清單
  /// 變動時重新計算。
  Book? _mostRecentBook;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bookListController = LibraryBookListController(
      repository: widget.repository,
    )..addListener(_onBookListChanged);
    _batchActions = LibraryBatchActions(repository: widget.repository);
    widget.refreshSignal?.addListener(_onExternalRefreshRequested);
    _initialize();
  }

  /// 「來源」畫面匯入新書後切回書架時觸發（見 AdaptiveShellScaffold，
  /// Task 5）——IndexedStack 讓 LibraryScreen 全程保持掛載，切換可見子項不
  /// 會重跑 build()，需要這個外部訊號主動重新整理。
  void _onExternalRefreshRequested() {
    _bookListController.loadBooks();
    _bookListController.loadGroups();
  }

  @override
  void didUpdateWidget(LibraryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.refreshSignal != oldWidget.refreshSignal) {
      oldWidget.refreshSignal?.removeListener(_onExternalRefreshRequested);
      widget.refreshSignal?.addListener(_onExternalRefreshRequested);
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
      if (mostRecent == null || book.lastReadTime.isAfter(mostRecent.lastReadTime)) {
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
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    if (!mounted) return;
    final physicalSize = View.of(context).physicalSize;
    // App 退到背景、螢幕休眠、多視窗模式調整分割大小、可折疊裝置展開
    // 過渡瞬間，physicalSize 可能暫時回報為 0x0——此時 `0 > 0` 為
    // false，會被誤判為 portrait，若裝置原本是 landscape
    // （`_lastPageSize == 4`）就會觸發一次錯誤的頁碼換算。直接略過這種
    // 暫態，等下一次真正有效的 metrics 變化再處理（`review-plan-issue-3.md`
    // I-2）。
    if (physicalSize.isEmpty) return;
    final newOrientation = physicalSize.width > physicalSize.height
        ? Orientation.landscape
        : Orientation.portrait;
    final newPageSize = libraryPageSizeForOrientation(newOrientation);
    final oldPageSize = _lastPageSize;
    if (oldPageSize != null && oldPageSize != newPageSize) {
      setState(() {
        _currentPage = libraryRecalculatePage(
          oldPage: _currentPage,
          oldPageSize: oldPageSize,
          newPageSize: newPageSize,
        );
      });
    }
    _lastPageSize = newPageSize;
  }

  Future<void> _initialize() async {
    final viewMode = await _preferences.loadViewMode();
    if (!mounted) return;
    setState(() => _viewMode = viewMode);
    await _bookListController.initialLoad();
    await _maybeOpenLastBookOnLaunch();
  }

  /// 啟動時開啟最後閱讀的那本書（epic-18-reader-device-qa Issue 29）：只在頂層
  /// 書架啟動當下觸發一次。保留此 guard 是比照 spec.md 明文指示維持語意對稱與
  /// 未來防禦性——原地下鑽後已無獨立實例，點擊拼貼格晚於此方法的執行時機，
  /// 不會重複觸發開書。
  Future<void> _maybeOpenLastBookOnLaunch() async {
    if (_activeGroupFilter != null) return;
    final globalPrefs = await widget.prefsManager.loadGlobalPrefs();
    if (!globalPrefs.openLastBookOnLaunch) return;
    if (!mounted) return;
    final books =
        await widget.repository.listBooks(sortBy: LibrarySortBy.lastRead);
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
      builder: (context) =>           LibraryMoveToGroupDialog(groups: _bookListController.groups),
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
      builder: (dialogContext) => AlertDialog(
        title: const Text('刪除書籍'),
        content: Text(
          '將刪除已選取的 $count 本書籍，並一併刪除其書籤、劃線與備註，此操作無法復原。確定要刪除嗎？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            key: const Key('library_delete_confirm_button'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('刪除'),
          ),
        ],
      ),
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
            builder: (_) => ReaderScreen(
              filePath: book.filePath,
              bookId: book.id,
              prefsManager: widget.prefsManager,
              bookmarksRepository: widget.readerFeatureRepositories.bookmarksRepository,
              highlightsRepository: widget.readerFeatureRepositories.highlightsRepository,
              notesRepository: widget.readerFeatureRepositories.notesRepository,
              bookTitle: book.title,
              bookAuthor: book.author,
              bookProgress: book.progress,
              isFixedLayout: book.isFixedLayout,
              libraryRepository: widget.repository,
              customFontsRepository: widget.readerFeatureRepositories.customFontsRepository,
              layoutPresetRepository: widget.readerFeatureRepositories.layoutPresetRepository,
              bookReaderPrefsRepository: widget.readerFeatureRepositories.bookReaderPrefsRepository,
              syncCheckpointTrigger: widget.syncDependencies.syncCheckpointTrigger,
              ttsProvider: widget.readerFeatureRepositories.ttsProvider,
              ttsAudioHandler: widget.readerFeatureRepositories.ttsAudioHandler,
              ttsAudioFocusSource: widget.readerFeatureRepositories.ttsAudioFocusSource,
              isEinkMode: widget.themeDependencies.isEinkMode,
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
      builder: (dialogContext) => AlertDialog(
        key: const Key('library_redownload_dialog'),
        title: const Text('重新下載'),
        content: Text(
          isMobileData
              ? '即將重新下載「${book.title}」，目前使用行動數據連線，可能產生流量費用，確定要繼續嗎？'
              : '即將重新下載「${book.title}」，確定要繼續嗎？',
        ),
        actions: [
          TextButton(
            key: const Key('library_redownload_cancel_button'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            key: const Key('library_redownload_confirm_button'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('重新下載'),
          ),
        ],
      ),
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
    final remoteServerRepository = widget.remoteLibraryDependencies.remoteServerRepository;
    final createOpdsClient = widget.remoteLibraryDependencies.createOpdsClient;
    final remoteServerId = book.remoteServerId;
    final remoteDownloadUrl = book.remoteDownloadUrl;
    if (remoteServerRepository == null ||
        createOpdsClient == null ||
        remoteServerId == null ||
        remoteDownloadUrl == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('遠端書庫功能未啟用，無法重新下載')));
      return;
    }
    if (_redownloadingBookIds.contains(book.id)) return;

    final isMobileData = await (widget.isMobileDataConnection?.call() ?? Future.value(false));
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
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('找不到對應的遠端書庫站點')));
        return;
      }
      final password = await remoteServerRepository.loadPassword(remoteServerId);
      final client = createOpdsClient();

      tempPath = await downloadToTempFile(
        client: client,
        server: server,
        acquisition: OpdsAcquisition(href: remoteDownloadUrl, format: book.format),
        format: book.format,
        password: password,
      );

      final permanentPath = await promoteToPermanent(tempPath);

      await widget.repository
          .updateBook(book.copyWith(filePath: permanentPath, isDownloaded: true));
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
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('重新下載失敗，請稍後再試')));
    } finally {
      _redownloadingBookIds.remove(book.id);
    }
  }

  Future<void> _openManageGroupsDialog() async {
    await showDialog<void>(
      context: context,
      builder: (context) => LibraryGroupManagementDialog(
        repository: widget.repository,
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
      _currentPage = 0;
    });
  }

  void _exitGroupFilteredView() {
    setState(() {
      _activeGroupFilter = null;
      _currentPage = 0;
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
    final result = await EBSheetShell.show<BookAction>(
      context,
      title: book.title,
      isEinkMode: widget.themeDependencies.isEinkMode,
      builder: (context) => BookActionSheet(
        book: book,
        showRemoveCache:
            book.source == BookSource.calibreOpds && book.isDownloaded,
        showLayoutOverride: false,
      ),
    );
    if (!mounted || result == null) return;
    switch (result) {
      case BookAction.showDetails:
        _showBookDetails(book);
      case BookAction.move:
        // TODO(Task 4): 實作移動邏輯
      case BookAction.layoutOverride:
        // TODO(Task 5): 實作版面覆寫邏輯
      case BookAction.removeCache:
        // TODO(Task 4): 實作移除快取邏輯
      case BookAction.delete:
        // TODO(Task 4): 實作刪除邏輯
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
      builder: (context) => _BookDetailsDialog(book: book),
    );
  }

  void _changeSortBy(LibrarySortBy sortBy) {
    setState(() => _currentPage = 0);
    _bookListController.changeSortBy(sortBy);
  }

  @override
  Widget build(BuildContext context) {
    final books = _bookListController.books;
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
            : (books.isEmpty ? _buildEmptyState() : _buildBookList(books)),
      ),
    );
  }

  AppBar _buildNormalAppBar(List<Book>? books) {
    return AppBar(
      leading: _activeGroupFilter == null
          ? null
          : IconButton(
              key: const Key('library_back_from_group_button'),
              icon: const Icon(Icons.arrow_back),
              tooltip: '返回上層',
              onPressed: _exitGroupFilteredView,
            ),
      title: Text(_activeGroupFilter ?? '書架'),
      actions: [
        PopupMenuButton<void>(
          key: const Key('library_sort_view_button'),
          icon: const Icon(Icons.sort),
          tooltip: '排序與檢視',
          enabled: books != null,
          itemBuilder: (context) {
            final currentSort = _bookListController.sortBy;
            final primaryColor = Theme.of(context).colorScheme.primary;
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
                        _sortLabel(sortBy),
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
                  _viewMode == LibraryViewMode.grid ? '切換為列表' : '切換為書架',
                ),
              ),
              if (_activeGroupFilter == null)
                PopupMenuItem<void>(
                  key: const Key('library_manage_groups_option'),
                  onTap: _openManageGroupsDialog,
                  child: const Text('管理分類...'),
                ),
            ];
          },
        ),
        IconButton(
          key: const Key('library_source_button'),
          icon: const Icon(Icons.cloud_download),
          tooltip: '來源',
          onPressed: widget.onNavigateToSource,
        ),
        IconButton(
          key: const Key('library_settings_button'),
          icon: const Icon(Icons.settings),
          tooltip: '設定',
          onPressed: widget.onNavigateToSettings,
        ),
      ],
    );
  }

  AppBar _buildSelectionAppBar() {
    final count = _selectedBookIds?.length ?? 0;
    return AppBar(
      key: const Key('library_selection_app_bar'),
      leading: IconButton(
        key: const Key('library_selection_cancel_button'),
        icon: const Icon(Icons.close),
        tooltip: '取消選取',
        onPressed: _exitSelectionMode,
      ),
      title: Text('已選取 $count 本'),
      actions: [
        IconButton(
          key: const Key('library_move_to_group_button'),
          icon: const Icon(Icons.drive_file_move),
          tooltip: '移動到分類',
          onPressed: count == 0 ? null : _moveSelectedBooksToGroup,
        ),
        IconButton(
          key: const Key('library_force_fxl_button'),
          icon: const Icon(Icons.menu_book),
          tooltip: '強制 FXL',
          onPressed: count == 0 ? null : _forceFixedLayoutForSelectedBooks,
        ),
        IconButton(
          key: const Key('library_restore_auto_layout_button'),
          icon: const Icon(Icons.restore),
          tooltip: '恢復自動判斷',
          onPressed: count == 0 ? null : _restoreAutoLayoutForSelectedBooks,
        ),
        IconButton(
          key: const Key('library_delete_books_button'),
          icon: const Icon(Icons.delete),
          tooltip: '刪除',
          onPressed: count == 0 ? null : _deleteSelectedBooks,
        ),
        IconButton(
          key: const Key('library_remove_local_cache_button'),
          icon: const Icon(Icons.cloud_off_outlined),
          tooltip: '移除本機快取',
          onPressed: count == 0 ? null : _removeLocalCacheForSelectedBooks,
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('尚未匯入書籍'),
          const SizedBox(height: 12),
          ElevatedButton(
            key: const Key('library_empty_import_button'),
            onPressed: widget.onNavigateToSource,
            child: const Text('匯入書籍'),
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

  Widget _buildBookList(List<Book> books) {
    final selectedIds = _selectedBookIds;
    final groupTiles = _activeGroupFilter == null
        ? _buildGroupTiles(books)
        : const <_GroupTile>[];
    final visibleBooks = _activeGroupFilter == null
        ? books.where((b) => b.groupName == BookGroup.uncategorized).toList()
        : books.where((b) => b.groupName == _activeGroupFilter).toList();
    final itemCount = groupTiles.length + visibleBooks.length;

    final orientation = MediaQuery.orientationOf(context);
    final pageSize = libraryPageSizeForOrientation(orientation);
    _lastPageSize = pageSize;
    final pageCount = libraryPageCount(itemCount, pageSize);
    final safePage = libraryClampPage(_currentPage, pageCount);
    // 同步寫回欄位本身（純賦值，非 setState——目前這次 build 已經在用
    // safePage 渲染，不需要立即再觸發一次重建；純粹是讓 _currentPage
    // 欄位不殘留越界值）。若不同步，批次刪除書籍導致 itemCount 縮減、
    // 使用者又沒有手動點過 PagingBar 時，_currentPage 會一直停留在舊的
    // 越界值，之後旋轉螢幕時 didChangeMetrics() 會拿這個越界值當
    // oldPage 去換算，得出進一步錯誤的頁碼（`review-plan-issue-3.md`
    // M-2）。比照上方 `_lastPageSize = pageSize;` 同樣的既有寫法。
    _currentPage = safePage;
    final pageStart = safePage * pageSize;
    final pageEnd = (pageStart + pageSize).clamp(0, itemCount);

    Widget itemBuilder(
      BuildContext context,
      int globalIndex, {
      required bool isGrid,
    }) {
      if (globalIndex < groupTiles.length) {
        final tile = groupTiles[globalIndex];
        final onTap =
            _inSelectionMode ? null : () => _openGroupFilteredView(tile.name);
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
            )
          : _BookListTile(
              book: book,
              selectionMode: _inSelectionMode,
              selected: selectedIds?.contains(book.id) ?? false,
              onTap: () => _onBookTap(book),
              onLongPress: () => _onBookLongPress(book),
              onMenuTap: () => _openBookActionSheet(book),
            );
    }

    final pageItemCount = pageEnd - pageStart;
    final Widget gridOrList;
    if (_viewMode == LibraryViewMode.grid) {
      final crossAxisCount = orientation == Orientation.landscape ? 4 : 3;
      gridOrList = GridView.builder(
        key: const Key('library_grid_view'),
        padding: const EdgeInsets.all(8),
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          childAspectRatio: 0.62,
          crossAxisSpacing: 8,
          mainAxisSpacing: 12,
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
        if (_activeGroupFilter == null && _mostRecentBook != null)
          _ContinueReadingRow(
            book: _mostRecentBook!,
            // 多選模式進行中時停用點擊（`review-plan-issue-3.md` M-3）：
            // 本列沒有勾選指示器，若不停用，使用者在多選時點到它會在
            // 毫無視覺反饋的情況下切換 _mostRecentBook 的選取狀態，比照
            // `_GroupGridTile`／`_GroupListTile` 在 _inSelectionMode 時
            // 一律把 onTap 傳 null 的既有慣例。
            onTap: _inSelectionMode ? null : () => _onBookTap(_mostRecentBook!),
          ),
        Expanded(child: Align(alignment: Alignment.topCenter, child: gridOrList)),
        PagingBar(
          key: const Key('library_paging_bar'),
          currentPage: safePage,
          pageCount: pageCount,
          onPrevious:
              safePage > 0 ? () => setState(() => _currentPage = safePage - 1) : null,
          onNext: safePage < pageCount - 1
              ? () => setState(() => _currentPage = safePage + 1)
              : null,
          isEinkMode: widget.themeDependencies.isEinkMode,
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
          const SizedBox(height: 4),
          SizedBox(
            height: gridTileFooterHeight(MediaQuery.textScalerOf(context)),
            child: Text(
              '${tile.name} (${tile.totalCount})',
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
      title: Text(tile.name),
      subtitle: Text('${tile.totalCount} 本'),
      onTap: onTap,
    );
  }
}

String _sortLabel(LibrarySortBy sortBy) {
  switch (sortBy) {
    case LibrarySortBy.lastRead:
      return '最後閱讀';
    case LibrarySortBy.createTime:
      return '建立時間';
    case LibrarySortBy.author:
      return '作者';
    case LibrarySortBy.title:
      return '書名';
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

  const _BookGridTile({
    required this.book,
    required this.selectionMode,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
    required this.onMenuTap,
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
                BookCover(book: book),
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
                      child: Container(
                        decoration: BoxDecoration(
                          color: tokens.badgeScrim,
                          shape: BoxShape.circle,
                        ),
                        child: IconButton(
                          key: Key('book_action_menu_${book.id}'),
                          icon: const Icon(
                            Icons.more_vert,
                            color: Colors.white,
                          ),
                          iconSize: 18,
                          padding: EdgeInsets.zero,
                          constraints:
                              const BoxConstraints(minWidth: 32, minHeight: 32),
                          tooltip: '更多',
                          onPressed: onMenuTap,
                        ),
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
                  book.title,
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

  const _BookListTile({
    required this.book,
    required this.selectionMode,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
    required this.onMenuTap,
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
              child: BookCover(book: book),
            ),
          ],
        ),
      ),
      title: Text(book.title),
      subtitle: Text(book.author ?? ''),
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
              tooltip: '更多',
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

  const _ContinueReadingRow({required this.book, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: const Key('library_continue_reading_row'),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            SizedBox(width: 40, height: 56, child: BookCover(book: book)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('繼續閱讀', style: TextStyle(fontSize: 12)),
                  Text(
                    book.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(_progressText(book), style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 單書「詳細資料」對話框（`spec.md` 功能④）：檔案大小查詢為非同步、
/// 具防護——`!book.isDownloaded` 直接顯示「尚未下載」不查詢檔案；
/// `content://` URI 或讀取失敗（`FileSystemException`）一律顯示
/// 「未知大小」，不得讓例外未捕捉往外拋（`review-spec.md` I-4）。
class _BookDetailsDialog extends StatefulWidget {
  final Book book;
  const _BookDetailsDialog({required this.book});

  @override
  State<_BookDetailsDialog> createState() => _BookDetailsDialogState();
}

class _BookDetailsDialogState extends State<_BookDetailsDialog> {
  late final Future<String> _fileSizeFuture;

  @override
  void initState() {
    super.initState();
    _fileSizeFuture = _resolveFileSizeText(widget.book);
  }

  static Future<String> _resolveFileSizeText(Book book) async {
    if (!book.isDownloaded) return '尚未下載';
    try {
      // 【review-plan-issue-4.md I-4】改用同步 I/O 取代 `await length()`：
      // 後者依賴原生 I/O 事件佇列完成，在 Flutter test 的 fake-async 環境下
      // 永遠不會完成（Future 永遠卡在 waiting），導致 `catch (_)` 無法觸發、
      // FutureBuilder 永遠顯示「讀取中...」。
      // 先用 `existsSync()` 確認檔案存在（content:// URI 在桌面端必定回傳
      // false），再以 `statSync().size` 同步取得大小——兩者皆為同步系統呼叫，
      // 立即回傳或拋出 `FileSystemException`，讓 `catch (_)` 正常攔截。
      final file = File(book.filePath);
      if (!file.existsSync()) return '未知大小';
      final length = file.statSync().size;
      return _formatFileSize(length);
    } catch (_) {
      return '未知大小';
    }
  }

  static String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  static String _formatLastReadTime(DateTime time) {
    if (time.millisecondsSinceEpoch <= 0) return '尚未閱讀';
    final y = time.year;
    final m = time.month.toString().padLeft(2, '0');
    final d = time.day.toString().padLeft(2, '0');
    return '$y/$m/$d';
  }

  @override
  Widget build(BuildContext context) {
    final book = widget.book;
    return AlertDialog(
      key: const Key('book_details_dialog'),
      title: Text(book.title),
      content: FutureBuilder<String>(
        future: _fileSizeFuture,
        builder: (context, snapshot) {
          // 【review-plan-issue-4.md M-2】`_resolveFileSizeText()` 內部已用
          // try-catch 保證 Future 本身不會拋錯，但 FutureBuilder 遭遇未預期
          // 的 error 狀態時，`snapshot.data` 為 null 會讓畫面永遠卡在
          // 「讀取中...」，改為明確判斷 hasError。
          final fileSizeText = snapshot.hasError
              ? '未知大小'
              : (snapshot.data ?? '讀取中...');
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('作者：${book.author ?? '未知'}'),
              Text('格式：${book.format.name}'),
              Text('檔案大小：$fileSizeText'),
              Text('進度：${_progressText(book)}'),
              Text('最後閱讀：${_formatLastReadTime(book.lastReadTime)}'),
            ],
          );
        },
      ),
      actions: [
        TextButton(
          key: const Key('book_details_dialog_close_button'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('關閉'),
        ),
      ],
    );
  }
}
