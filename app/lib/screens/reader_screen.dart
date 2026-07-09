import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../reader/book_format.dart';
import '../reader/book_reader_prefs.dart';
import '../reader/book_reader_prefs_repository.dart';
import '../reader/epub_reader_view.dart';
import '../reader/global_reader_defaults.dart';
import '../reader/page_turn_mode.dart';
import '../reader/pdf_reader_view.dart';
import '../reader/screen_orientation_setting.dart';
import '../reader/writing_mode.dart';
import 'reader_settings_sheet.dart';

/// 唯一的閱讀器顯示接縫（seam）：給定書籍檔案路徑，依偵測到的格式分派到
/// 對應的原生渲染 widget，畫面上會渲染出該書第 1 頁。公開建構參數為
/// [filePath]／[bookId]／[prefsRepository]（`bookId`／`prefsRepository` 由
/// epic-3-fonts-layout Issue 3 新增，供讀寫單書版面偏好設定使用，見
/// docs/adr/0007-reader-screen-book-id-contract.md）——載入中／錯誤狀態是
/// 內部實作細節，透過固定的 `Key('reader_loading_indicator')`／
/// `Key('reader_error_text')` 暴露給測試觀察，刻意不新增公開 callback 參數。
/// EPUB 格式下原本各自獨立的橫直排／換頁模式切換按鈕（`reader_writing_mode_toggle`／
/// `reader_page_turn_mode_toggle`，Epic 2 建立的過渡方案）已於
/// epic-3-fonts-layout Issue 4 整併進「⚙️版面」按鈕開啟的
/// `ReaderSettingsSheet`，改為三個持久化的覆寫選擇器（排版方向／翻頁模式／
/// 螢幕方向，見 [_ReaderScreenState._resolvedWritingMode]／
/// [_ReaderScreenState._resolvedPageTurnMode]／
/// [_ReaderScreenState._resolvedScreenOrientation]）。
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
  final _globalDefaults = GlobalReaderDefaults();

  _RenderState _state = _RenderState.loading;
  String? _errorMessage;
  // 自動偵測結果（來自 onLayoutResolved），唯讀、不持久化，每次開書重新
  // 偵測（見 docs/epics/epic-3-fonts-layout/design.md「架構異動：新增
  // book_reader_prefs 資料表」）。
  WritingMode? _autoDetectedWritingMode;
  // 全域預設值（GlobalReaderDefaults，shared_preferences），供未覆寫的
  // 書籍回退使用；初始值與擴充前的硬編碼預設一致（paginated／auto），
  // 避免非同步載入完成前出現行為落差。
  PageTurnMode _globalPageTurnMode = PageTurnMode.paginated;
  ScreenOrientationSetting _globalScreenOrientation =
      ScreenOrientationSetting.auto;
  bool _isFixedLayout = false;
  BookReaderPrefs _prefs = BookReaderPrefs.empty;
  // 記錄上一次實際套用給系統的螢幕方向，避免在偏好設定頻繁變動時（例如
  // 拖曳滑桿）重複呼叫 SystemChrome.setPreferredOrientations。
  ScreenOrientationSetting? _lastAppliedOrientation;

  /// 排版方向最終生效值：單書覆寫優先於自動偵測結果。onLayoutResolved
  /// 尚未觸發、且沒有 writingModeOverride 時，回傳 null（EpubReaderView
  /// 會以 Readium 預設值渲染）。
  WritingMode? get _resolvedWritingMode =>
      _prefs.writingModeOverride ?? _autoDetectedWritingMode;

  /// 翻頁模式最終生效值：單書覆寫優先於全域預設值。
  PageTurnMode get _resolvedPageTurnMode =>
      _prefs.pageTurnModeOverride ?? _globalPageTurnMode;

  /// 螢幕方向最終生效值：單書覆寫優先於全域預設值。
  ScreenOrientationSetting get _resolvedScreenOrientation =>
      _prefs.screenOrientationOverride ?? _globalScreenOrientation;

  @override
  void initState() {
    super.initState();
    // 單書偏好設定與兩項全域預設值彼此獨立、互不依賴，一次併發載入完成
    // 後才更新狀態並套用螢幕方向鎖定——避免分開 await 造成畫面在載入期間
    // 出現多段不同時機的中繼閃爍。
    Future.wait([
      widget.prefsRepository.load(widget.bookId),
      _globalDefaults.loadPageTurnMode(),
      _globalDefaults.loadScreenOrientation(),
    ]).then((results) {
      if (!mounted) return;
      setState(() {
        _prefs = results[0] as BookReaderPrefs;
        _globalPageTurnMode = results[1] as PageTurnMode;
        _globalScreenOrientation = results[2] as ScreenOrientationSetting;
      });
      _applyScreenOrientation();
    });
  }

  @override
  void dispose() {
    // 還原系統預設（允許自由旋轉），不論進入閱讀器時鎖定了哪個角度，比照
    // 音量鍵離開閱讀介面後恢復正常系統音量控制的既有處理原則，避免鎖定
    // 狀態外溢到書架等其他畫面。
    SystemChrome.setPreferredOrientations(const []);
    super.dispose();
  }

  /// 依 [_resolvedScreenOrientation] 呼叫 SystemChrome 套用真實 OS 層級
  /// 鎖定（非僅內容排版層級的假象）。角度與 [DeviceOrientation] 的對應
  /// 是本 issue 撰寫計劃階段決定的慣例（0°→portraitUp、90°→landscapeLeft、
  /// 180°→portraitDown、270°→landscapeRight），實際物理旋轉是否與這組
  /// 對應一致，留待真機測試以驗收標準的人工視覺 QA 確認。
  ///
  /// 為避免使用者在快速拖曳滑桿時產生高頻率的 platform channel 呼叫，
  /// 僅在 [_resolvedScreenOrientation] 與 [_lastAppliedOrientation] 不同時
  /// 才實際呼叫 SystemChrome。
  void _applyScreenOrientation() {
    final current = _resolvedScreenOrientation;
    if (current == _lastAppliedOrientation) return;
    _lastAppliedOrientation = current;
    SystemChrome.setPreferredOrientations(
      _deviceOrientationsFor(current),
    );
  }

  List<DeviceOrientation> _deviceOrientationsFor(
    ScreenOrientationSetting setting,
  ) {
    switch (setting) {
      case ScreenOrientationSetting.auto:
        return const [];
      case ScreenOrientationSetting.lock0:
        return const [DeviceOrientation.portraitUp];
      case ScreenOrientationSetting.lock90:
        return const [DeviceOrientation.landscapeLeft];
      case ScreenOrientationSetting.lock180:
        return const [DeviceOrientation.portraitDown];
      case ScreenOrientationSetting.lock270:
        return const [DeviceOrientation.landscapeRight];
    }
  }

  /// 版面設定 Bottom Sheet 任一控制項變動時呼叫：立即更新本地狀態（驅動
  /// EpubReaderView 以新值重建）並非同步持久化，同時重新套用螢幕方向鎖定
  /// （screenOrientationOverride 可能剛被這次變動改變）。不 await 持久化
  /// 結果——使用者互動的視覺回饋（畫面即時反映新設定）不應等待資料庫寫入
  /// 完成，比照本專案其餘偏好設定寫入呼叫的既有慣例（例如
  /// LibraryPreferences 系列方法在 UI callback 中皆未 await）。
  void _handlePrefsChanged(BookReaderPrefs prefs) {
    setState(() => _prefs = prefs);
    widget.prefsRepository.save(widget.bookId, prefs);
    _applyScreenOrientation();
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

  /// 【已知、可接受的行為】把自動偵測結果寫回 [_autoDetectedWritingMode]
  /// 後，若當下沒有 writingModeOverride，[_resolvedWritingMode] 會從 null
  /// 變成非 null，驅動 EpubReaderView 以非 null 值重建；EpubReaderView 的
  /// didUpdateWidget 偵測到「null → 非 null」的變化時，會多送一次
  /// setPreferences 給原生端，等於把 Readium 剛剛自動判斷好的值重新套用
  /// 一次。這是多餘但無害的呼叫（見 EpubReaderView.kt 的 setPreferences
  /// 註解——currentPreferences.plus() 合併語意，不會覆蓋其他已生效欄位），
  /// 不特地加狀態去抑制它，避免為了避免一次無害的重複呼叫而增加複雜度。
  void _handleLayoutResolved(EpubLayoutInfo info) {
    if (!mounted) return;
    setState(() {
      _isFixedLayout = info.isFixedLayout;
      _autoDetectedWritingMode = info.writingMode;
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
        key: const Key('reader_layout_settings_button'),
        icon: const Icon(Icons.settings),
        tooltip: '版面設定',
        // _autoDetectedWritingMode 非 null 代表 onLayoutResolved 已觸發，
        // 書本已成功開啟、navigatorFragment 已存在，此時開啟版面設定並呼叫
        // setPreferences 才有意義（見 EpubReaderView.kt 的靜默忽略邏輯
        // 說明）。
        onPressed:
            _autoDetectedWritingMode == null ? null : _openLayoutSettings,
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
          writingMode: _resolvedWritingMode,
          pageTurnMode: _resolvedPageTurnMode,
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
