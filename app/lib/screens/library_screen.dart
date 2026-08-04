import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../library/book_import_service.dart';
import '../reader/bookmarks_repository.dart';
import '../reader/custom_fonts_repository.dart';
import '../reader/highlights_repository.dart';
import '../reader/notes_repository.dart';
import '../reader/reader_prefs_manager.dart';
import '../library/library_preferences.dart';
import '../library/library_repository.dart';
import '../library/models/book.dart';
import '../library/models/book_group.dart';
import '../library/models/library_enums.dart';
import '../sync/sync_account_repository.dart';
import '../sync/sync_checkpoint_trigger.dart';
import '../sync/sync_client.dart';
import '../theme/app_theme.dart';
import 'library_group_management_dialog.dart';
import 'library_move_to_group_dialog.dart';
import 'reader_screen.dart';
import 'settings_screen.dart';

const _folderPickerChannel = MethodChannel('elinkbook/folder_picker');

/// 圖書庫主畫面：讀取 [LibraryRepository] 的真實資料，取代
/// epic-0-skeleton 遺留的固定範例書籍清單佔位版本（見
/// docs/epics/epic-1-library/spec.md）。
class LibraryScreen extends StatefulWidget {
  final LibraryRepository repository;
  final BookImportService importService;
  final ReaderPrefsManager prefsManager;
  final BookmarksRepository? bookmarksRepository;
  final HighlightsRepository? highlightsRepository;
  final NotesRepository? notesRepository;
  final CustomFontsRepository? customFontsRepository;
  final SyncAccountRepository? syncAccountRepository;
  final SyncClient? syncClient;
  final SyncCheckpointTrigger? syncCheckpointTrigger;
  final AppTheme currentTheme;
  final bool isEinkMode;
  final ValueChanged<AppTheme>? onThemeChanged;
  final ValueChanged<bool>? onEinkModeChanged;
  final String? groupFilter;

  const LibraryScreen({
    super.key,
    required this.repository,
    required this.importService,
    required this.prefsManager,
    this.bookmarksRepository,
    this.highlightsRepository,
    this.notesRepository,
    this.customFontsRepository,
    this.syncAccountRepository,
    this.syncClient,
    this.syncCheckpointTrigger,
    this.currentTheme = AppTheme.light,
    this.isEinkMode = false,
    this.onThemeChanged,
    this.onEinkModeChanged,
    this.groupFilter,
  });

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final _preferences = LibraryPreferences();

  List<Book>? _books;
  List<BookGroup> _groups = const [];
  LibraryViewMode _viewMode = LibraryViewMode.grid;
  LibrarySortBy _sortBy = LibrarySortBy.lastRead;
  String? _groupFilter;
  Set<String>? _selectedBookIds;
  bool _isImporting = false;

  @override
  void initState() {
    super.initState();
    _groupFilter = widget.groupFilter;
    _initialize();
  }

  Future<void> _initialize() async {
    final viewMode = await _preferences.loadViewMode();
    final sortBy = await _preferences.loadSortBy();
    if (!mounted) return;
    setState(() {
      _viewMode = viewMode;
      _sortBy = sortBy;
    });
    await Future.wait([_loadGroups(), _loadBooks()]);
  }

  Future<void> _loadGroups() async {
    try {
      final groups = await widget.repository.listGroups();
      if (!mounted) return;
      setState(() => _groups = groups);
    } catch (_) {
      // 暫時性錯誤時保留先前已載入的群組清單，避免因為單次讀取失敗就讓
      // 畫面的分類 tab 列與目前的篩選狀態不一致（見 Issue 7 審查）。若是
      // 第一次載入就失敗，_groups 會維持初始的空清單（連「未分類」都不
      // 顯示）——這是「沒有最後已知正確狀態可保留」下的必然結果，安全但
      // 不完美，之後重新整理即可恢復。
    }
  }

  Future<void> _loadBooks() async {
    // 擷取呼叫當下的排序/分類篩選條件；若使用者在這次非同步查詢完成前又
    // 切換了排序或分類 tab，較晚回應但較早發出的查詢結果會對應到舊條件，
    // 此時不應覆蓋畫面（避免顯示內容與目前選定的條件不一致）。
    final requestedSortBy = _sortBy;
    final requestedGroupFilter = _groupFilter;
    try {
      final books = await widget.repository.listBooks(
        sortBy: requestedSortBy,
        groupFilter: requestedGroupFilter,
      );
      if (!mounted) return;
      if (_sortBy != requestedSortBy || _groupFilter != requestedGroupFilter) {
        return;
      }
      setState(() => _books = books);
    } catch (_) {
      // 如果載入失敗，把它當作空列表，顯示既有的空狀態 UI
      if (!mounted) return;
      if (_sortBy != requestedSortBy || _groupFilter != requestedGroupFilter) {
        return;
      }
      setState(() => _books = []);
    }
  }

  Future<void> _pickAndImportFiles() async {
    try {
      final picked = await FilePicker.pickFiles(
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: ['epub', 'pdf', 'txt'],
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
      await _loadBooks();
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
      await _loadGroups();
      await _loadBooks();
      _showImportResultSnackBar(result);
    } catch (_) {
      // 匯入失敗時靜默吞掉，避免異常傳播破壞 widget 樹或留下不一致狀態
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
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

  Future<void> _changeSortBy(LibrarySortBy sortBy) async {
    setState(() => _sortBy = sortBy);
    await _preferences.saveSortBy(sortBy);
    await _loadBooks();
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
    final books = _books;
    if (selectedIds == null || selectedIds.isEmpty || books == null) return;
    final destination = await showDialog<String>(
      context: context,
      builder: (context) => LibraryMoveToGroupDialog(groups: _groups),
    );
    if (destination == null) return;
    // 立即退出選取模式，而非等到逐筆寫入資料庫的迴圈結束後才退出：這個迴圈
    // 期間「移動到分類」按鈕仍會顯示在選取模式的 App Bar 上，若不提早退出，
    // 使用者理論上可以在寫入尚未完成時再次點擊，重複觸發本方法。
    _exitSelectionMode();
    for (final book in books) {
      if (!selectedIds.contains(book.id)) continue;
      await widget.repository.updateBook(book.copyWith(groupName: destination));
    }
    await _loadBooks();
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
    final books = _books;
    if (selectedIds == null || selectedIds.isEmpty || books == null) return;
    _exitSelectionMode();
    for (final book in books) {
      if (!selectedIds.contains(book.id)) continue;
      if (book.format != BookFileFormat.epub) continue;
      await widget.repository.updateBook(book.copyWith(isFixedLayout: true));
    }
    await _loadBooks();
  }

  /// 對選取集合中所有 EPUB 書籍重新呼叫既有 detectAndCacheEpubLayout()，
  /// 回到系統原始的「引擎分派判斷」結果——用於復原誤按/誤判後想撤銷人工
  /// 覆蓋的情況（見 CONTEXT.md「人工版面覆蓋」）。非 EPUB 書籍自動跳過。
  /// 行為比照 _forceFixedLayoutForSelectedBooks()，含其「捕捉 selectedIds
  /// 參考早於 _exitSelectionMode() 是安全的」註記。
  Future<void> _restoreAutoLayoutForSelectedBooks() async {
    final selectedIds = _selectedBookIds;
    final books = _books;
    if (selectedIds == null || selectedIds.isEmpty || books == null) return;
    _exitSelectionMode();
    for (final book in books) {
      if (!selectedIds.contains(book.id)) continue;
      if (book.format != BookFileFormat.epub) continue;
      await widget.repository.detectAndCacheEpubLayout(book.id, book.filePath);
    }
    await _loadBooks();
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
    final books = _books;
    if (selectedIds == null || selectedIds.isEmpty || books == null) return;
    final confirmed = await _confirmDeleteBooks(selectedIds.length);
    if (confirmed != true) return;
    // 比照既有 _openManageGroupsDialog() 的既有慣例：await 跳出 dialog 的
    // 操作之後、觸碰 state 之前先確認 widget 是否仍在畫面上（見
    // library_screen.dart:322，同檔案內多數 await-dialog 後的路徑皆有此
    // 檢查，_moveSelectedBooksToGroup() 缺這道檢查屬既有缺口，不在本工單
    // 範圍內一併修正）。
    if (!mounted) return;
    // 比照既有 _moveSelectedBooksToGroup()：先退出選取模式，避免刪除迴圈
    // 執行期間使用者重複點擊觸發本方法。
    _exitSelectionMode();
    for (final book in books) {
      if (!selectedIds.contains(book.id)) continue;
      await widget.repository.deleteBook(book.id);
      // existsSync() 防護對 content:// 來源的 filePath 安全（design.md
      // 調查結論——content:// 字串永遠不會判定為存在的本機路徑，故此處
      // 不需要分辨 filePath 是本機複本還是原始外部檔案參照）。比照既有
      // _pickAndImportFiles()/_pickAndImportFolder() 的既有慣例，用
      // try-catch 包住檔案系統操作：單一檔案刪除失敗（例如被其他程序鎖
      // 定、權限異常）不應中斷整個批次刪除迴圈——deleteBook()（資料庫紀
      // 錄，使用者最關心的「書從書架消失」）已在上一行完成，迴圈仍要繼
      // 續處理其餘已選取的書籍並跑到最後的 _loadBooks()。
      try {
        // 使用 deleteSync() 而非 await delete()：widget test 的 fake zone
        // 無法完成真實 I/O 的 Future，deleteSync() 是同步系統呼叫，可直接完
        // 成，不受 zone 限制。
        if (File(book.filePath).existsSync()) {
          File(book.filePath).deleteSync();
        }
        final coverPath = book.coverPath;
        if (coverPath != null && File(coverPath).existsSync()) {
          File(coverPath).deleteSync();
        }
      } catch (_) {
        // 檔案刪除失敗時靜默略過，不中斷主流程；資料庫紀錄已刪除，殘留
        // 檔案不影響功能正確性。
      }
    }
    await _loadBooks();
  }

  void _openBook(Book book) {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => ReaderScreen(
              filePath: book.filePath,
              bookId: book.id,
              prefsManager: widget.prefsManager,
              bookmarksRepository: widget.bookmarksRepository,
              highlightsRepository: widget.highlightsRepository,
              notesRepository: widget.notesRepository,
              bookTitle: book.title,
              bookAuthor: book.author,
              bookProgress: book.progress,
              isFixedLayout: book.isFixedLayout,
              libraryRepository: widget.repository,
              customFontsRepository: widget.customFontsRepository,
              syncCheckpointTrigger: widget.syncCheckpointTrigger,
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
      _loadBooks();
    });
  }

  Future<void> _openManageGroupsDialog() async {
    await showDialog<void>(
      context: context,
      builder: (context) => LibraryGroupManagementDialog(
        repository: widget.repository,
        initialGroups: _groups,
      ),
    );
    await _loadGroups();
    if (!mounted) return;
    await _loadBooks();
  }

  void _openGroupFilteredView(String groupName) {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => LibraryScreen(
              repository: widget.repository,
              importService: widget.importService,
              prefsManager: widget.prefsManager,
              bookmarksRepository: widget.bookmarksRepository,
              highlightsRepository: widget.highlightsRepository,
              notesRepository: widget.notesRepository,
              customFontsRepository: widget.customFontsRepository,
              currentTheme: widget.currentTheme,
              isEinkMode: widget.isEinkMode,
              onThemeChanged: widget.onThemeChanged,
              onEinkModeChanged: widget.onEinkModeChanged,
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
      _loadGroups();
      _loadBooks();
    });
  }

  @override
  Widget build(BuildContext context) {
    final books = _books;
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
        IconButton(
          key: const Key('library_eink_toggle'),
          icon: Icon(
            widget.isEinkMode ? Icons.contrast : Icons.contrast_outlined,
            color:
                widget.isEinkMode ? Theme.of(context).colorScheme.primary : null,
          ),
          tooltip: 'E-Ink 高對比模式',
          onPressed: () => widget.onEinkModeChanged?.call(!widget.isEinkMode),
        ),
        const VerticalDivider(width: 1, indent: 12, endIndent: 12),
        PopupMenuButton<LibrarySortBy>(
          key: const Key('library_sort_button'),
          icon: const Icon(Icons.sort),
          tooltip: '排序：${_sortLabel(_sortBy)}',
          enabled: books != null,
          onSelected: _changeSortBy,
          itemBuilder: (context) => LibrarySortBy.values
              .map(
                (sortBy) => PopupMenuItem<LibrarySortBy>(
                  key: Key('library_sort_option_${sortBy.name}'),
                  value: sortBy,
                  child: Text(_sortLabel(sortBy)),
                ),
              )
              .toList(),
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
          ],
        ),
        if (widget.groupFilter == null)
          IconButton(
            key: const Key('library_manage_groups_button'),
            icon: const Icon(Icons.category),
            tooltip: '管理分類',
            onPressed: _openManageGroupsDialog,
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
                  currentTheme: widget.currentTheme,
                  isEinkMode: widget.isEinkMode,
                  onThemeChanged: widget.onThemeChanged,
                  customFontsRepository: widget.customFontsRepository,
                  syncAccountRepository: widget.syncAccountRepository,
                  syncClient: widget.syncClient,
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

  /// 依目前已載入的 [books]（已依 _sortBy 排序）與 [_groups]（name ASC）
  /// 分組，只保留非空的具名分類。
  ///
  /// 【診斷修正】「未分類」不產生拼貼格——`BookGroup.uncategorized` 的書籍
  /// 已經透過 `_buildBookList()` 的 `visibleBooks` 過濾邏輯純粹以個別書籍
  /// 項目顯示在頂層書籍清單中，若還額外顯示一個「未分類」拼貼格，等於同一
  /// 批書籍在畫面上出現兩種呈現方式，造成混淆；只有具名分類才需要拼貼格
  /// 這種「摘要縮圖」的呈現方式。
  ///
  /// `_groups` 是 `_loadGroups()` 讀取的記憶體快照，既有的 `_loadGroups()`
  /// 錯誤處理邏輯本身承認暫時性讀取失敗時會保留舊快照——故 `book.groupName`
  /// 理論上可能不在目前的 `_groups` 清單中、也不是 `BookGroup.uncategorized`
  /// （`_groups` 落後於 `_books` 的情境）。若只依 `_groups` 組出
  /// `orderedNames`，這些書籍會被整批漏掉、從書架上「消失」而非只是分類格
  /// 顯示不完整，後果比拼貼格排序錯誤嚴重得多，故補一個兜底桶收留所有未
  /// 被涵蓋的 `groupName`（`BookGroup.uncategorized` 本身仍被排除在兜底桶
  /// 之外——落後的快照不會讓一本書從「未分類」變成孤兒 `groupName`，
  /// `BookGroup.uncategorized` 這個名字本身不會消失，只是不產生拼貼格）。
  ///
  /// 【審查意見，不要求改動】若同時存在多個孤兒 `groupName`，彼此之間的
  /// 順序取決於 `byGroup.keys`（`LinkedHashMap` 插入順序＝書籍依目前
  /// `_sortBy` 排序後被迭代到的順序），並非依名稱字母排序。`spec.md`／
  /// `design.md` 只要求孤兒不會讓書籍消失，沒有規範多個孤兒彼此的相對
  /// 順序，故此處維持現況，僅記錄此已知特性供日後參考。
  List<_GroupTile> _buildGroupTiles(List<Book> books) {
    final byGroup = <String, List<Book>>{};
    for (final book in books) {
      byGroup.putIfAbsent(book.groupName, () => []).add(book);
    }
    final orderedNames = [
      for (final group in _groups)
        if (group.name != BookGroup.uncategorized) group.name,
      for (final name in byGroup.keys)
        if (name != BookGroup.uncategorized &&
            !_groups.any((g) => g.name == name))
          name,
    ];
    return [
      for (final name in orderedNames)
        if (byGroup[name]?.isNotEmpty ?? false)
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
          Expanded(
            child: GridView.count(
              crossAxisCount: 2,
              // GridView 是 BoxScrollView 的子類，padding 為 null 時會自動
              // 吃進 MediaQuery.of(context).padding（垂直捲動吃 top/bottom
              // safe area）；這個巢狀在拼貼格內的小型 GridView 若不明講
              // padding: EdgeInsets.zero，會意外套上裝置狀態列/導覽列高度
              // 的內距，把 2×2 封面擠壓變形。
              padding: EdgeInsets.zero,
              mainAxisSpacing: 2,
              crossAxisSpacing: 2,
              physics: const NeverScrollableScrollPhysics(),
              children: List.generate(
                4,
                (i) => i < tile.previewBooks.length
                    ? _BookCover(book: tile.previewBooks[i])
                    : ColoredBox(color: Colors.grey.shade200),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${tile.name} (${tile.totalCount})',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
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
                  ? _BookCover(book: tile.previewBooks[i])
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

IconData _formatIcon(BookFileFormat format) {
  switch (format) {
    case BookFileFormat.epub:
      return Icons.menu_book;
    case BookFileFormat.pdf:
      return Icons.picture_as_pdf;
    case BookFileFormat.txt:
      return Icons.article;
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
  }
}

String _progressText(Book book) => '${(book.progress * 100).round()}%';

/// 書籍封面：有 `coverPath` 且檔案存在時顯示圖片，否則以格式圖示佔位。
/// `existsSync()` 只是一次本機 stat 呼叫，成本低，不需要 FutureBuilder。
class _BookCover extends StatelessWidget {
  final Book book;
  const _BookCover({required this.book});

  @override
  Widget build(BuildContext context) {
    final coverPath = book.coverPath;
    if (coverPath != null && File(coverPath).existsSync()) {
      return Image.file(File(coverPath), fit: BoxFit.cover);
    }
    return ColoredBox(
      color: Colors.grey.shade300,
      child: Center(child: Icon(_formatIcon(book.format), size: 32)),
    );
  }
}

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
                _BookCover(book: book),
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
              child: _BookCover(book: book),
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
