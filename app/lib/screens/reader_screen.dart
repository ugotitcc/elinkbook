import 'package:flutter/material.dart';

import '../reader/book_format.dart';
import '../reader/book_reader_prefs.dart';
import '../reader/book_reader_prefs_repository.dart';
import '../reader/epub_reader_view.dart';
import '../reader/page_turn_mode.dart';
import '../reader/pdf_reader_view.dart';
import '../reader/writing_mode.dart';
import 'reader_settings_sheet.dart';

/// 唯一的閱讀器顯示接縫（seam）：給定書籍檔案路徑，依偵測到的格式分派到
/// 對應的原生渲染 widget，畫面上會渲染出該書第 1 頁。公開建構參數為
/// [filePath]／[bookId]／[prefsRepository]（`bookId`／`prefsRepository` 由
/// epic-3-fonts-layout Issue 3 新增，供讀寫單書版面偏好設定使用，見
/// docs/adr/0007-reader-screen-book-id-contract.md）——載入中／錯誤狀態是
/// 內部實作細節，透過固定的 `Key('reader_loading_indicator')`／
/// `Key('reader_error_text')` 暴露給測試觀察，刻意不新增公開 callback 參數。
/// EPUB 格式下的橫直排切換按鈕（`reader_writing_mode_toggle`）與換頁模式
/// 切換按鈕（`reader_page_turn_mode_toggle`，Issue 4 新增）同理：純屬內部
/// 狀態管理，僅限當次閱讀 session 即時切換，不持久化（見
/// docs/epics/epic-2-vertical-core/design.md「範圍與排除項目」——持久化與
/// 三態覆寫 UI 屬 FR-10／epic-3）。
///
/// AppBar 沿用與 LibraryScreen/SettingsScreen 一致的寫法（純 `AppBar(title:
/// ...)`，不自訂 leading）：Flutter 會依 `Navigator.canPop()` 自動決定是否
/// 顯示返回鍵，且點擊時使用安全的 `Navigator.maybePop()`，不需要手動處理。
class ReaderScreen extends StatefulWidget {
  final String filePath;
  final String bookId;
  final BookReaderPrefsRepository prefsRepository;

  const ReaderScreen({
    super.key,
    required this.filePath,
    required this.bookId,
    required this.prefsRepository,
  });

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

enum _RenderState { loading, rendered, error }

class _ReaderScreenState extends State<ReaderScreen> {
  _RenderState _state = _RenderState.loading;
  String? _errorMessage;
  WritingMode? _writingMode;
  PageTurnMode _pageTurnMode = PageTurnMode.paginated;
  bool _isFixedLayout = false;
  BookReaderPrefs _prefs = BookReaderPrefs.empty;

  @override
  void initState() {
    super.initState();
    widget.prefsRepository.load(widget.bookId).then((prefs) {
      if (!mounted) return;
      setState(() => _prefs = prefs);
    });
  }

  /// 版面設定 Bottom Sheet 任一控制項變動時呼叫：立即更新本地狀態（驅動
  /// EpubReaderView 以新值重建）並非同步持久化。不 await 持久化結果——
  /// 使用者互動的視覺回饋（畫面即時反映新設定）不應等待資料庫寫入完成，
  /// 比照本專案其餘偏好設定寫入呼叫的既有慣例（例如 LibraryPreferences
  /// 系列方法在 UI callback 中皆未 await）。
  void _handlePrefsChanged(BookReaderPrefs prefs) {
    setState(() => _prefs = prefs);
    widget.prefsRepository.save(widget.bookId, prefs);
  }

  void _openLayoutSettings() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      // Bottom Sheet 預設的下滑關閉手勢（enableDrag: true）與 Slider 的
      // 水平拖曳手勢在混合角度滑動時容易被手勢競技場誤判，導致使用者
      // 調整滑桿時選單意外關閉；停用後仍可點擊背景遮罩關閉。
      enableDrag: false,
      builder: (_) => ReaderSettingsSheet(
        prefs: _prefs,
        onChanged: _handlePrefsChanged,
      ),
    );
  }

  void _handlePageRendered() {
    if (!mounted) return;
    setState(() => _state = _RenderState.rendered);
  }

  void _handleError(String message) {
    if (!mounted) return;
    setState(() {
      _state = _RenderState.error;
      _errorMessage = message;
    });
  }

  /// 【已知、可接受的行為】把自動偵測結果寫回 [_writingMode] 後，會驅動
  /// EpubReaderView 以非 null 值重建；EpubReaderView 的 didUpdateWidget 偵測
  /// 到「null → 非 null」的變化時，會多送一次 setWritingMode 給原生端，等於
  /// 把 Readium 剛剛自動判斷好的值重新套用一次。這是多餘但無害的呼叫（目前
  /// 沒有其他偏好設定會被覆蓋，見 EpubReaderView.kt 的 setWritingMode 註解），
  /// 不特地加狀態去抑制它，避免為了避免一次無害的重複呼叫而增加複雜度。
  void _handleLayoutResolved(EpubLayoutInfo info) {
    if (!mounted) return;
    setState(() {
      _isFixedLayout = info.isFixedLayout;
      _writingMode = info.writingMode;
    });
  }

  void _toggleWritingMode() {
    setState(() {
      _writingMode = _writingMode == WritingMode.vertical
          ? WritingMode.horizontal
          : WritingMode.vertical;
    });
  }

  void _togglePageTurnMode() {
    setState(() {
      _pageTurnMode = _pageTurnMode == PageTurnMode.scroll
          ? PageTurnMode.paginated
          : PageTurnMode.scroll;
    });
  }

  @override
  Widget build(BuildContext context) {
    final format = detectBookFormat(widget.filePath);
    return Scaffold(
      appBar: AppBar(
        title: const Text('閱讀器'),
        actions: _buildAppBarActions(format),
      ),
      body: _buildBody(format),
    );
  }

  List<Widget>? _buildAppBarActions(BookFormat format) {
    if (format != BookFormat.epub || _isFixedLayout) return null;
    return [
      IconButton(
        key: const Key('reader_writing_mode_toggle'),
        icon: Icon(
          _writingMode == WritingMode.vertical
              ? Icons.text_rotation_none
              : Icons.text_rotate_vertical,
        ),
        tooltip: _writingMode == WritingMode.vertical ? '切換為橫排' : '切換為直排',
        onPressed: _writingMode == null ? null : _toggleWritingMode,
      ),
      IconButton(
        key: const Key('reader_page_turn_mode_toggle'),
        icon: Icon(
          _pageTurnMode == PageTurnMode.scroll ? Icons.menu_book : Icons.swap_vert,
        ),
        tooltip:
            _pageTurnMode == PageTurnMode.scroll ? '切換為分頁模式' : '切換為捲動模式',
        // 與橫直排切換按鈕共用同一個啟用條件：_writingMode 非 null 代表
        // onLayoutResolved 已觸發，書本已成功開啟、navigatorFragment 已存在，
        // 此時呼叫 setPageTurnMode 才有意義（見 EpubReaderView.kt 的
        // 靜默忽略邏輯說明）。
        onPressed: _writingMode == null ? null : _togglePageTurnMode,
      ),
      IconButton(
        key: const Key('reader_layout_settings_button'),
        icon: const Icon(Icons.settings),
        tooltip: '版面設定',
        onPressed: _writingMode == null ? null : _openLayoutSettings,
      ),
    ];
  }

  Widget _buildBody(BookFormat format) {
    if (format == BookFormat.unknown) {
      return const Center(child: Text('不支援的檔案格式'));
    }
    if (_state == _RenderState.error) {
      // 渲染失敗時直接以錯誤文字取代原生視圖（而非疊加在 Stack 上層），讓
      // 已失敗的 EpubReaderView/PdfReaderView 提早從 widget tree 移除、
      // 觸發其 dispose() 清理原生資源，不讓一個已知失敗的 PlatformView
      // 繼續留在畫面底層。
      return Center(
        child: Text(
          _errorMessage ?? '無法載入書籍',
          key: const Key('reader_error_text'),
        ),
      );
    }
    return Stack(
      children: [
        _buildNativeView(format),
        if (_state == _RenderState.loading)
          const Center(
            key: Key('reader_loading_indicator'),
            child: CircularProgressIndicator(),
          ),
      ],
    );
  }

  Widget _buildNativeView(BookFormat format) {
    switch (format) {
      case BookFormat.epub:
        return EpubReaderView(
          filePath: widget.filePath,
          writingMode: _writingMode,
          pageTurnMode: _pageTurnMode,
          onPageRendered: _handlePageRendered,
          onError: _handleError,
          onLayoutResolved: _handleLayoutResolved,
          fontFamily: _prefs.fontFamily,
          fontSize: _prefs.fontSize,
          fontWeight: _prefs.fontWeight,
          lineHeight: _prefs.lineHeight,
          paragraphSpacing: _prefs.paragraphSpacing,
          pageMargins: _prefs.pageMargins,
          textAlign: _prefs.textAlign,
          publisherStyles: _prefs.publisherStyles,
        );
      case BookFormat.pdf:
        return PdfReaderView(
          filePath: widget.filePath,
          onPageRendered: _handlePageRendered,
          onError: _handleError,
        );
      case BookFormat.unknown:
        return const SizedBox.shrink();
    }
  }
}
