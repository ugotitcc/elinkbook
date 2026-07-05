import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../library/book_import_service.dart';
import '../library/library_preferences.dart';
import '../library/library_repository.dart';
import '../library/models/book.dart';
import '../library/models/book_group.dart';
import '../library/models/library_enums.dart';
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

  const LibraryScreen({
    super.key,
    required this.repository,
    required this.importService,
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

  @override
  void initState() {
    super.initState();
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
      final uris =
          picked.files.map((f) => f.identifier).whereType<String>().toList();
      if (uris.isEmpty) return;
      await widget.importService.importFiles(uris);
      await _loadBooks();
    } catch (_) {
      // 匯入失敗時靜默吞掉，避免異常傳播破壞 widget 樹或留下不一致狀態
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
      await widget.importService.importFolder(
        folderUri,
        autoGroupByFolderName: autoGroup,
      );
      await _loadGroups();
      await _loadBooks();
    } catch (_) {
      // 匯入失敗時靜默吞掉，避免異常傳播破壞 widget 樹或留下不一致狀態
    }
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

  Future<void> _changeGroupFilter(String? groupFilter) async {
    setState(() => _groupFilter = groupFilter);
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

  void _openBook(Book book) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ReaderScreen(filePath: book.filePath)),
    );
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
    // 若目前篩選中的分類已在對話框內被刪除，退回「全部」篩選，避免畫面
    // 停留在一個已不存在的分類上（listBooks 對不存在的 groupFilter 只會
    // 回傳空清單，容易誤以為「這個分類沒有書」而非「這個分類已被刪除」）。
    final filterStillExists =
        _groupFilter == null || _groups.any((g) => g.name == _groupFilter);
    if (!filterStillExists) {
      setState(() => _groupFilter = null);
    }
    await _loadBooks();
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
            : Column(
                children: [
                  _buildGroupTabs(),
                  Expanded(
                    child: books.isEmpty
                        ? _buildEmptyState()
                        : _buildBookList(books),
                  ),
                ],
              ),
      ),
    );
  }

  AppBar _buildNormalAppBar(List<Book>? books) {
    return AppBar(
      title: const Text('書架'),
      actions: [
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
        IconButton(
          icon: const Icon(Icons.settings),
          tooltip: '設定',
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => const SettingsScreen(),
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
      ],
    );
  }

  Widget _buildGroupTabs() {
    return SizedBox(
      key: const Key('library_group_tabs'),
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: ChoiceChip(
              key: const Key('library_group_tab_all'),
              label: const Text('全部'),
              selected: _groupFilter == null,
              onSelected:
                  _inSelectionMode ? null : (_) => _changeGroupFilter(null),
            ),
          ),
          for (final group in _groups)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: ChoiceChip(
                key: Key('library_group_tab_${group.name}'),
                label: Text(group.name),
                selected: _groupFilter == group.name,
                onSelected: _inSelectionMode
                    ? null
                    : (_) => _changeGroupFilter(group.name),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: ActionChip(
              key: const Key('library_group_manage_button'),
              avatar: const Icon(Icons.category, size: 16),
              label: const Text('管理分類'),
              onPressed: _inSelectionMode ? null : _openManageGroupsDialog,
            ),
          ),
        ],
      ),
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
            onPressed: _pickAndImportFiles,
            child: const Text('匯入書籍'),
          ),
        ],
      ),
    );
  }

  Widget _buildBookList(List<Book> books) {
    final selectedIds = _selectedBookIds;
    if (_viewMode == LibraryViewMode.grid) {
      return GridView.builder(
        key: const Key('library_grid_view'),
        padding: const EdgeInsets.all(8),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 6,
          childAspectRatio: 0.62,
        ),
        itemCount: books.length,
        itemBuilder: (context, index) {
          final book = books[index];
          return _BookGridTile(
            book: book,
            selectionMode: _inSelectionMode,
            selected: selectedIds?.contains(book.id) ?? false,
            onTap: () => _onBookTap(book),
            onLongPress: () => _onBookLongPress(book),
          );
        },
      );
    }
    return ListView.builder(
      key: const Key('library_list_view'),
      itemCount: books.length,
      itemBuilder: (context, index) {
        final book = books[index];
        return _BookListTile(
          book: book,
          selectionMode: _inSelectionMode,
          selected: selectedIds?.contains(book.id) ?? false,
          onTap: () => _onBookTap(book),
          onLongPress: () => _onBookLongPress(book),
        );
      },
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
