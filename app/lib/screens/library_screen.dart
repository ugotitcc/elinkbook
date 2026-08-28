import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../cloud_import/cloud_storage_client.dart';
import '../library/book_content_fingerprint.dart';
import '../library/book_import_service.dart';
import '../reader/reader_prefs_manager.dart';
import '../remote/opds_types.dart';
import '../remote/remote_book_downloader.dart';
import '../remote/remote_server_profile.dart';
import '../remote/remote_catalog_dependencies.dart';
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

import 'cloud_browser_screen.dart';
import 'library_group_management_dialog.dart';
import 'library_move_to_group_dialog.dart';
import 'reader_screen.dart';
import 'remote_server_list_screen.dart';
import 'settings_screen.dart';

const _folderPickerChannel = MethodChannel('elinkbook/folder_picker');

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
  final String? groupFilter;

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
    this.groupFilter,
  });

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final _preferences = LibraryPreferences();
  late final LibraryBookListController _bookListController;
  late final LibraryBatchActions _batchActions;

  LibraryViewMode _viewMode = LibraryViewMode.grid;
  Set<String>? _selectedBookIds;
  bool _isImporting = false;
  // 〔比照 epic-30 Issue 3 review-issue-3.md 既定的重入防護模式〕避免
  // 使用者在重新下載進行中又快速連點同一本「待下載」書籍，重複觸發兩次
  // 下載/確認流程。
  final Set<String> _redownloadingBookIds = {};

  @override
  void initState() {
    super.initState();
    _bookListController = LibraryBookListController(
      repository: widget.repository,
      groupFilter: widget.groupFilter,
    )..addListener(_onBookListChanged);
    _batchActions = LibraryBatchActions(repository: widget.repository);
    _initialize();
  }

  void _onBookListChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _bookListController.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    final viewMode = await _preferences.loadViewMode();
    if (!mounted) return;
    setState(() => _viewMode = viewMode);
    await _bookListController.initialLoad();
    await _maybeOpenLastBookOnLaunch();
  }

  /// 啟動時開啟最後閱讀的那本書（epic-18-reader-device-qa Issue 29）：只在頂層
  /// 書架（`widget.groupFilter == null`）啟動當下觸發一次——`initState()`
  /// 對單一 State 物件只會執行一次，`_openGroupFilteredView()` 推入的分類
  /// 篩選畫面是另一個獨立的 `LibraryScreen` 實例、`groupFilter` 非
  /// null，此處的 guard 確保使用者點進分類篩選畫面時不會被誤判為「App
  /// 剛啟動」而重複觸發。「最後閱讀的書籍」獨立以 `LibrarySortBy.lastRead`
  /// 查詢，不依賴目前畫面選定的 `_sortBy`（使用者的檢視排序偏好與這裡的
  /// 語意是兩件事，即使目前排序條件是「書名」也不該影響這裡判斷的對象）。
  Future<void> _maybeOpenLastBookOnLaunch() async {
    if (widget.groupFilter != null) return;
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


  Future<void> _pickAndImportFiles() async {
    try {
      final picked = await FilePicker.pickFiles(
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: ['epub', 'pdf', 'txt', 'cbz', 'azw3', 'md'],
      );
      if (picked == null || picked.files.isEmpty) return;
      // uris／displayNames 必須用同一次過濾（f.identifier != null）建立，
      // 保持逐一對應——分開各自 map 再各自過濾會在有檔案 identifier 為 null
      // 時位移量不同，導致 displayNames[i] 對應到錯誤的 uris[i]。
      final pickedWithUri =
          picked.files.where((f) => f.identifier != null).toList();
      final uris = pickedWithUri.map((f) => f.identifier!).toList();
      if (uris.isEmpty) return;
      final displayNames = pickedWithUri.map((f) => f.name).toList();
      setState(() => _isImporting = true);
      final result =
          await widget.importService.importFiles(uris, displayNames: displayNames);
      await _bookListController.loadBooks();
      _showImportResultSnackBar(result);
    } catch (_) {
      // 匯入失敗時靜默吞掉，避免異常傳播破壞 widget 樹或留下不一致狀態
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  Future<void> _pickAndImportFolder() async {
    try {
      final folderUri =
          await _folderPickerChannel.invokeMethod<String>('pickFolder');
      if (folderUri == null) return;
      // pickFolder 對應真實系統資料夾選擇器，使用者操作時間可能很長；
      // 確認畫面在這段等待期間沒有被 pop/dispose，才能安全使用 context。
      if (!mounted) return;
      final autoGroup = await _confirmAutoGroupByFolderName();
      if (autoGroup == null) return;
      setState(() => _isImporting = true);
      final result = await widget.importService.importFolder(
        folderUri,
        autoGroupByFolderName: autoGroup,
      );
      await _bookListController.loadGroups();
      await _bookListController.loadBooks();
      _showImportResultSnackBar(result);
    } catch (_) {
      // 匯入失敗時靜默吞掉，避免異常傳播破壞 widget 樹或留下不一致狀態
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  void _openGoogleDriveBrowser(CloudStorageClient client) {
    Navigator.of(context)
        .push(MaterialPageRoute(
          builder: (context) => CloudBrowserScreen(
            client: client,
            libraryRepository: widget.repository,
            importService: widget.importService,
            source: BookSource.googleDrive,
            computeFingerprint: widget.computeFingerprint!,
            isMobileDataConnection: widget.isMobileDataConnection,
          ),
        ))
        .then((_) {
      // 【審查 review-plan-issue-3.md Minor #2 採納】比照
      // `_openGroupFilteredView` 既有慣例，一併重新載入分類——
      // `importFiles(folderName: ...)` 內部會 `upsertGroup()`，回到書架
      // 時分類清單與書籍清單應保持同步一致。
      if (mounted) {
        _bookListController.loadGroups();
        _bookListController.loadBooks();
      }
    });
  }

  void _openOneDriveBrowser(CloudStorageClient client) {
    Navigator.of(context)
        .push(MaterialPageRoute(
          builder: (context) => CloudBrowserScreen(
            client: client,
            libraryRepository: widget.repository,
            importService: widget.importService,
            source: BookSource.oneDrive,
            computeFingerprint: widget.computeFingerprint!,
            isMobileDataConnection: widget.isMobileDataConnection,
            title: 'OneDrive',
          ),
        ))
        .then((_) {
      if (mounted) {
        _bookListController.loadGroups();
        _bookListController.loadBooks();
      }
    });
  }

  /// 匯入完成後顯示單一合併提示：成功匯入本數與（若有）因來源 URI 與既有
  /// 書籍重複而被跳過的本數（見 book_import_service_impl.dart 的重複偵測
  /// 說明），避免使用者連續看到兩則獨立 SnackBar。兩者皆為 0（例如選檔後
  /// 全數格式不支援）時不顯示任何提示，維持既有行為。
  void _showImportResultSnackBar(ImportResult result) {
    final importedCount = result.importedBooks.length;
    final skippedCount = result.skippedDuplicateCount;
    if (importedCount <= 0 && skippedCount <= 0) return;
    if (!mounted) return;
    final message = importedCount > 0
        ? (skippedCount > 0
            ? '已匯入 $importedCount 本，$skippedCount 本已存在，已跳過'
            : '已匯入 $importedCount 本書')
        : '$skippedCount 本已存在，已跳過';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<bool?> _confirmAutoGroupByFolderName() {
    var autoGroup = true;
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('匯入資料夾'),
          content: CheckboxListTile(
            key: const Key('library_import_folder_auto_group_checkbox'),
            value: autoGroup,
            onChanged: (value) =>
                setDialogState(() => autoGroup = value ?? true),
            title: const Text('依資料夾名稱自動建立分類'),
            controlAffinity: ListTileControlAffinity.leading,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('取消'),
            ),
            TextButton(
              key: const Key('library_import_folder_confirm'),
              onPressed: () => Navigator.of(dialogContext).pop(autoGroup),
              child: const Text('匯入'),
            ),
          ],
        ),
      ),
    );
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
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => LibraryScreen(
              repository: widget.repository,
              importService: widget.importService,
              prefsManager: widget.prefsManager,
              readerFeatureRepositories: widget.readerFeatureRepositories,
              // epic-8-sync Issue 10：先前遺漏這三個同步相關欄位，導致從這條
              // 分類篩選路徑開書時 syncCheckpointTrigger 無法貫穿到
              // ReaderScreen，「離開畫面」／「閱讀中 5 分鐘計時器」兩種
              // checkpoint 觸發來源會靜默失效（見 plans/plan-issue-10.md）。
              // 本次改為整包轉送 syncDependencies bundle，結構上不會再重演
              // 「轉 A 忘轉 B」的部分欄位漏轉發（見 review-issue-7.md Minor #1）。
              syncDependencies: widget.syncDependencies,
              // 【審查修正 review-issue-3.md Important #1】先前遺漏
              // googleDriveStorageClient／oneDriveStorageClient 兩個欄位，
              // 導致從分類篩選路徑進入的 LibraryScreen 內「從 Google Drive
              // 匯入」選單項目永遠停用。本次改為整包轉送
              // cloudAccountDependencies bundle，結構上不會再重演「轉 A
              // 忘轉 B」的部分欄位漏轉發（見 review-issue-7.md Minor #1）。
              cloudAccountDependencies: widget.cloudAccountDependencies,
              // 【審查修正 review-issue-5.md Important #1】Issue 5 新增的
              // 「從 Google Drive／OneDrive 匯入」選單門檻改為同時檢查
              // `widget.computeFingerprint != null`，這裡若不轉發，分類
              // 篩選路徑內兩個雲端匯入選項會一起被誤停用（同一種錯誤模式
              // 見上方 googleDriveStorageClient 的審查修正註解）。
              computeFingerprint: widget.computeFingerprint,
              // 【Epic 29 Issue 6】isMobileDataConnection 自 epic-30 Issue 4
              // 加入以來，這個自我遞迴導航點便一直未轉發（當時沒有下游畫面
              // 需要它）；Issue 6 讓 CloudBrowserScreen 開始依賴這個欄位後，
              // 若不轉發，分類篩選路徑內的雲端下載流量警示會靜默失效——比照
              // 上方 computeFingerprint／googleDriveStorageClient 兩次漏轉發
              // 的既有修正慣例，這次主動補上，避免同一種錯誤模式第三次重演
              // （見 review-issue-3.md Important #1、review-issue-5.md
              // Important #1）。
              isMobileDataConnection: widget.isMobileDataConnection,
              themeDependencies: widget.themeDependencies,
              groupFilter: groupName,
            ),
          ),
        )
        .then((_) {
      // 【審查修正】推入的畫面是獨立的 LibraryScreen State 實例，在裡面
      // 移動/刪除書籍只會更新該實例自己的 _books/_groups，不會 touch 這裡
      // （背景頂層畫面）的狀態；返回時若不重新載入，頂層拼貼格與書籍清單
      // 會停留在使用者離開當下的舊快照（比照既有 _openBook() 的 .then()
      // 修正所防範的同類問題）。
      //
      // 【審查修正】原本只呼叫 _loadBooks()，理由是「管理分類」入口在
      // groupFilter != null 的篩選畫面上不顯示，篩選畫面內無法變動分類
      // 名稱集合——但這個假設不成立：篩選畫面的 AppBar 仍保留「匯入書籍」
      // 按鈕（未比照「管理分類」用 groupFilter == null 隱藏），而「選擇
      // 資料夾＋依資料夾名稱自動建立分類」會呼叫
      // BookImportServiceImpl.importFolder() 內部的 repository.upsertGroup()，
      // 確實可以在篩選畫面內建立新分類。若不一併呼叫 _loadGroups()，頂層
      // 的 _groups 快照就不包含新分類，_buildGroupTiles() 的孤兒兜底桶會
      // 把新分類排到「未分類」之後，違反「未分類固定排最後」的不變量，
      // 故改為與 _loadBooks() 一起重新載入。
      if (!mounted) return;
        _bookListController.loadGroups();
      _bookListController.loadBooks();
    });
  }

  @override
  Widget build(BuildContext context) {
    final books = _bookListController.books;
    return PopScope(
      canPop: !_inSelectionMode,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _inSelectionMode) {
          _exitSelectionMode();
        }
      },
      child: Scaffold(
        appBar: _inSelectionMode
            ? _buildSelectionAppBar()
            : _buildNormalAppBar(books),
        body: books == null
            ? const Center(child: CircularProgressIndicator())
            : Stack(
                children: [
                  Column(
                    children: [
                      Expanded(
                        child: books.isEmpty
                            ? _buildEmptyState()
                            : _buildBookList(books),
                      ),
                    ],
                  ),
                  if (_isImporting) _buildImportingOverlay(),
                ],
              ),
      ),
    );
  }

  Widget _buildImportingOverlay() {
    return Positioned.fill(
      child: ColoredBox(
        key: const Key('library_importing_overlay'),
        color: Colors.black38,
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 12),
              Text('匯入中...', style: TextStyle(color: Colors.white)),
            ],
          ),
        ),
      ),
    );
  }

  AppBar _buildNormalAppBar(List<Book>? books) {
    return AppBar(
      title: Text(widget.groupFilter ?? '書架'),
      actions: [
        Container(
          margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          decoration: BoxDecoration(
            // E-Ink 開啟時全域主題一律為 _buildEinkTheme()（brightness 恆為
            // Brightness.light），不需要再判斷 brightness，固定黑底即可。
            color: widget.themeDependencies.isEinkMode ? Colors.black : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: widget.themeDependencies.isEinkMode
                  ? Colors.transparent
                  : Theme.of(context).colorScheme.outline.withValues(alpha: 0.5),
              width: 1.5,
            ),
          ),
          child: IconButton(
            key: const Key('library_eink_toggle'),
            icon: Icon(
              widget.themeDependencies.isEinkMode ? Icons.contrast : Icons.contrast_outlined,
              color: widget.themeDependencies.isEinkMode
                  ? Colors.white
                  : Theme.of(context).colorScheme.onSurface,
              size: 20,
            ),
            tooltip: widget.themeDependencies.isEinkMode
                ? 'E-Ink 模式：已開啟（點擊切換）'
                : 'E-Ink 模式：已關閉（點擊切換）',
            onPressed: () => widget.themeDependencies.onEinkModeChanged?.call(!widget.themeDependencies.isEinkMode),
          ),
        ),
        const VerticalDivider(width: 1, indent: 12, endIndent: 12),
        PopupMenuButton<LibrarySortBy>(
          key: const Key('library_sort_button'),
          icon: const Icon(Icons.sort),
          tooltip: '排序：${_sortLabel(_bookListController.sortBy)}',
          enabled: books != null,
          onSelected: _bookListController.changeSortBy,
          itemBuilder: (context) {
            final currentSort = _bookListController.sortBy;
            final primaryColor = Theme.of(context).colorScheme.primary;

            return LibrarySortBy.values.map(
              (sortBy) {
                final isSelected = currentSort == sortBy;
                return PopupMenuItem<LibrarySortBy>(
                  key: Key('library_sort_option_${sortBy.name}'),
                  value: sortBy,
                  child: Row(
                    children: [
                      SizedBox(
                        width: 24,
                        child: isSelected
                            ? Icon(Icons.check, size: 20, color: primaryColor)
                            : null,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _sortLabel(sortBy),
                        style: TextStyle(
                          fontWeight:
                              isSelected ? FontWeight.bold : FontWeight.normal,
                          color: isSelected ? primaryColor : null,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ).toList();
          },
        ),
        IconButton(
          key: const Key('library_view_mode_toggle'),
          icon: Icon(
            _viewMode == LibraryViewMode.grid
                ? Icons.view_list
                : Icons.grid_view,
          ),
          tooltip: _viewMode == LibraryViewMode.grid ? '切換為列表' : '切換為書架',
          onPressed: books == null ? null : _toggleViewMode,
        ),
        PopupMenuButton<void>(
          key: const Key('library_import_button'),
          icon: const Icon(Icons.add),
          tooltip: '匯入書籍',
          enabled: !_isImporting,
          itemBuilder: (context) => [
            PopupMenuItem<void>(
              key: const Key('library_import_files_option'),
              onTap: _pickAndImportFiles,
              child: const Text('選擇檔案（可多選）'),
            ),
            PopupMenuItem<void>(
              key: const Key('library_import_folder_option'),
              onTap: _pickAndImportFolder,
              child: const Text('選擇資料夾'),
            ),
            PopupMenuItem<void>(
              key: const Key('library_import_google_drive_option'),
              enabled: widget.cloudAccountDependencies.googleDriveStorageClient != null &&
                  widget.computeFingerprint != null,
              onTap: (widget.cloudAccountDependencies.googleDriveStorageClient == null ||
                      widget.computeFingerprint == null)
                  ? null
                  : () => _openGoogleDriveBrowser(
                      widget.cloudAccountDependencies.googleDriveStorageClient!),
              child: const Text('從 Google Drive 匯入'),
            ),
            PopupMenuItem<void>(
              key: const Key('library_import_onedrive_option'),
              enabled: widget.cloudAccountDependencies.oneDriveStorageClient != null &&
                  widget.computeFingerprint != null,
              onTap: (widget.cloudAccountDependencies.oneDriveStorageClient == null ||
                      widget.computeFingerprint == null)
                  ? null
                  : () => _openOneDriveBrowser(
                      widget.cloudAccountDependencies.oneDriveStorageClient!),
              child: const Text('從 OneDrive 匯入'),
            ),
          ],
        ),
        if (widget.groupFilter == null)
          IconButton(
            key: const Key('library_manage_groups_button'),
            icon: const Icon(Icons.category),
            tooltip: '管理分類',
            onPressed: _openManageGroupsDialog,
          ),
        if (widget.remoteLibraryDependencies.remoteServerRepository != null &&
            widget.remoteLibraryDependencies.createOpdsClient != null &&
            widget.computeFingerprint != null &&
            widget.remoteLibraryDependencies.thumbnailCache != null)
          IconButton(
            key: const Key('library_remote_library_button'),
            icon: const Icon(Icons.cloud_outlined),
            tooltip: '遠端書庫',
            onPressed: () {
              Navigator.of(context)
                  .push(
                    MaterialPageRoute(
                      builder: (context) => RemoteServerListScreen(
                        repository: widget.remoteLibraryDependencies.remoteServerRepository!,
                        libraryRepository: widget.repository,
                        dependencies: RemoteCatalogDependencies(
                          computeFingerprint: widget.computeFingerprint!,
                          thumbnailCache: widget.remoteLibraryDependencies.thumbnailCache!,
                          createOpdsClient: widget.remoteLibraryDependencies.createOpdsClient!,
                        ),
                        importService: widget.importService,
                        isEinkMode: widget.themeDependencies.isEinkMode,
                      ),
                    ),
                  )
                  .then((_) {
                // 從遠端書庫返回時重新載入書架，確保新下載的書籍出現。
                if (mounted) _bookListController.loadBooks();
              });
            },
          ),
        IconButton(
          key: const Key('library_settings_button'),
          icon: const Icon(Icons.settings),
          tooltip: '設定',
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => SettingsScreen(
                  prefsManager: widget.prefsManager,
                  currentTheme: widget.themeDependencies.currentTheme,
                  isEinkMode: widget.themeDependencies.isEinkMode,
                  onThemeChanged: widget.themeDependencies.onThemeChanged,
                  // 【審查修正 Critical：見 reviews/review-issue-5-8.md
                  // 補件審查】原本漏傳這個參數，SettingsScreen 的 E-Ink
                  // 開關雖然畫面上存在，但 onChanged 收到 null 會被 Flutter
                  // 判定為停用（灰階、無法點擊），點了完全沒反應。
                  onEinkModeChanged: widget.themeDependencies.onEinkModeChanged,
                  customFontsRepository: widget.readerFeatureRepositories.customFontsRepository,
                  syncAccountRepository: widget.syncDependencies.syncAccountRepository,
                  syncClient: widget.syncDependencies.syncClient,
                  cloudAccountRepository: widget.cloudAccountDependencies.cloudAccountRepository,
                  googleDriveOAuthClient: widget.cloudAccountDependencies.googleDriveOAuthClient,
                  oneDriveOAuthClient: widget.cloudAccountDependencies.oneDriveOAuthClient,
                ),
              ),
            );
          },
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
            onPressed: _isImporting ? null : _pickAndImportFiles,
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
    final groupTiles = widget.groupFilter == null
        ? _buildGroupTiles(books)
        : const <_GroupTile>[];
    // 【診斷修正——真機回報「已分類書籍在頂層重複顯示」】頂層書架
    // （groupFilter == null）已經用拼貼格代表每個非空分類，若已歸類的書籍
    // 同時還出現在下方書籍清單中，等於同一本書在畫面上顯示兩次。故頂層只
    // 保留「未分類」書籍在書籍清單中；已歸類的書籍只透過所屬分類的拼貼格
    // 顯示，要看到該書本身須點擊拼貼格進入該分類的篩選畫面（`groupFilter`
    // 非 null 時不受影響，篩選畫面本來就不顯示拼貼格，books 維持原樣）。
    final visibleBooks = widget.groupFilter == null
        ? books.where((b) => b.groupName == BookGroup.uncategorized).toList()
        : books;
    final itemCount = groupTiles.length + visibleBooks.length;
    Widget itemBuilder(BuildContext context, int index, {required bool isGrid}) {
      if (index < groupTiles.length) {
        final tile = groupTiles[index];
        // 選取模式進行中時，分類格不可觸發導覽（onTap 傳 null），比照舊版
        // _buildGroupTabs() 對 Chip 在 _inSelectionMode 時一律停用互動的
        // 既有慣例——否則使用者長按多選書籍時誤觸分類格，會帶著選取狀態
        // 被推入另一個 LibraryScreen 實例，選取列顯示與計數會與使用者預
        // 期不符。
        final onTap =
            _inSelectionMode ? null : () => _openGroupFilteredView(tile.name);
        return isGrid
            ? _GroupGridTile(tile: tile, onTap: onTap)
            : _GroupListTile(tile: tile, onTap: onTap);
      }
      final book = visibleBooks[index - groupTiles.length];
      return isGrid
          ? _BookGridTile(
              book: book,
              selectionMode: _inSelectionMode,
              selected: selectedIds?.contains(book.id) ?? false,
              onTap: () => _onBookTap(book),
              onLongPress: () => _onBookLongPress(book),
            )
          : _BookListTile(
              book: book,
              selectionMode: _inSelectionMode,
              selected: selectedIds?.contains(book.id) ?? false,
              onTap: () => _onBookTap(book),
              onLongPress: () => _onBookLongPress(book),
            );
    }
    if (_viewMode == LibraryViewMode.grid) {
      final orientation = MediaQuery.orientationOf(context);
      final crossAxisCount = orientation == Orientation.landscape ? 4 : 3;
      return GridView.builder(
        key: const Key('library_grid_view'),
        padding: const EdgeInsets.all(8),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          childAspectRatio: 0.62,
          crossAxisSpacing: 8,
          mainAxisSpacing: 12,
        ),
        itemCount: itemCount,
        itemBuilder: (context, index) =>
            itemBuilder(context, index, isGrid: true),
      );
    }
    return ListView.builder(
      key: const Key('library_list_view'),
      itemCount: itemCount,
      itemBuilder: (context, index) => itemBuilder(context, index, isGrid: false),
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
        : ColoredBox(color: Colors.grey.shade200);
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
                  : ColoredBox(color: Colors.grey.shade200),
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

  const _BookGridTile({
    required this.book,
    required this.selectionMode,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
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
                        // 半透明黑底圓圈確保勾選圖示在任何封面底色下都有
                        // 足夠對比度（審查意見：白色圖示疊在淺色封面上會
                        // 無法辨識）。
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(
                          color: Colors.black45,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          selected
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked,
                          key: Key('book_selection_indicator_${book.id}'),
                          color: selected
                              ? Theme.of(context).colorScheme.primary
                              : Colors.white,
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
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
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

  const _BookListTile({
    required this.book,
    required this.selectionMode,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
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
      trailing: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(_sourceIcon(book.source), size: 16),
          Text(_progressText(book), style: const TextStyle(fontSize: 10)),
        ],
      ),
      onTap: onTap,
      onLongPress: onLongPress,
    );
  }
}
