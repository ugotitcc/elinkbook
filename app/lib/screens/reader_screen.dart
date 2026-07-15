import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../reader/book_format.dart';
import '../reader/book_reader_prefs.dart';
import '../reader/epub_position_info.dart';
import '../reader/epub_reader_view.dart';
import '../reader/pdf_crop_mode.dart';
import '../reader/pdf_crop_rect.dart';
import '../reader/pdf_page_info.dart';
import '../reader/pdf_reader_view.dart';
import '../reader/reading_position.dart';
import '../reader/reader_prefs_manager.dart';
import '../reader/resolved_preferences.dart';
import '../reader/screen_orientation_setting.dart';
import '../reader/writing_mode.dart';
import 'fxl_settings_sheet.dart';
import 'pdf_settings_sheet.dart';
import 'reader_footer.dart';
import 'reader_settings_sheet.dart';

/// 唯一的閱讀器顯示接縫（seam）：給定書籍檔案路徑，依偵測到的格式分派到
/// 對應的原生渲染 widget，畫面上會渲染出該書第 1 頁。公開建構參數為
/// [filePath]／[bookId]／[prefsManager]（`bookId`／`prefsManager` 由
/// epic-3-fonts-layout Issue 3 新增，供讀寫單書版面偏好設定使用，見
/// docs/adr/0007-reader-screen-book-id-contract.md）——載入中／錯誤狀態是
/// 內部實作細節，透過固定的 `Key('reader_loading_indicator')`／
/// `Key('reader_error_text')` 暴露給測試觀察，刻意不新增公開 callback 參數。
/// EPUB 格式下原本各自獨立的橫直排／換頁模式切換按鈕（`reader_writing_mode_toggle`／
/// `reader_page_turn_mode_toggle`，Epic 2 建立的過渡方案）已於
/// epic-3-fonts-layout Issue 4 整併進「⚙️版面」按鈕開啟的
/// `ReaderSettingsSheet`，改為三個持久化的覆寫選擇器（排版方向／翻頁模式／
/// 螢幕方向，見 [_ReaderScreenState._resolved]）。
///
/// AppBar 沿用與 LibraryScreen/SettingsScreen 一致的寫法（純 `AppBar(title:
/// ...)`，不自訂 leading）：Flutter 會依 `Navigator.canPop()` 自動決定是否
/// 顯示返回鍵，且點擊時使用安全的 `Navigator.maybePop()`，不需要手動處理。
class ReaderScreen extends StatefulWidget {
  final String filePath;
  final String bookId;
  final ReaderPrefsManager prefsManager;

  const ReaderScreen({
    super.key,
    required this.filePath,
    required this.bookId,
    required this.prefsManager,
  });

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

enum _RenderState { loading, rendered, error }

class _ReaderScreenState extends State<ReaderScreen> with WidgetsBindingObserver {
  _RenderState _state = _RenderState.loading;
  String? _errorMessage;
  // 自動偵測結果（來自 onLayoutResolved），唯讀、不持久化，每次開書重新
  // 偵測（見 docs/epics/epic-3-fonts-layout/design.md「架構異動：新增
  // book_reader_prefs 資料表」）。
  WritingMode? _autoDetectedWritingMode;
  bool _isFixedLayout = false;
  // 固定版面（FXL）懸浮控制項（返回鍵／設定鍵）是否顯示，由 EpubReaderView
  // 三欄熱區的中間熱區觸發切換（見 epic-16-dual-page Issue 9）。預設顯示。
  bool _fixedLayoutControlsVisible = true;
  BookReaderPrefs _prefs = BookReaderPrefs.empty;
  LoadedPrefs? _loaded;
  ResolvedPreferences? _resolved;
  // 手動裁切互動模式是否進行中（決策 #14），驅動 PdfReaderView 的宣告式
  // cropEditModeActive prop；只有 PDF 分支會用到，EPUB 分支永遠是 false。
  bool _cropEditModeActive = false;
  // PDF 目前頁碼/總頁數狀態，由 PdfReaderView.onPageChanged 回報驅動頁尾
  // 顯示（Epic 5 Issue 1）。EPUB 讀取畫面本 issue 不使用此欄位。
  PdfPageInfo? _pdfPageInfo;
  // EPUB 目前定位狀態，由 EpubReaderView.onLocatorChanged 回報（Epic 5
  // Issue 2）。寫入本機資料庫時讀取此欄位的最新值，比照 _pdfPageInfo
  // 對 PDF 的既有作法。
  EpubPositionInfo? _epubPositionInfo;
  // 開書時讀到的既有位置記錄（若有），只在 initState 賦值一次，之後
  // 不變——僅用於 _buildNativeView() 建構 EpubReaderView/PdfReaderView
  // 時傳入 initialLocatorJson/initialPageIndex 這兩個一次性開書起始值。
  ReadingPosition? _initialPosition;
  // 用於呼叫 PdfReaderView.jumpToPage(key, pageIndex) 這個強型別 static
  // helper（審查修正，見 Task 2 Step 4——不使用 as dynamic 跨 State 私有
  // 邊界呼叫，避免 release 混淆／tree-shaking 風險）。
  final _pdfReaderViewKey = GlobalKey<State<PdfReaderView>>();
  // 記錄上一次實際套用給系統的螢幕方向，避免在偏好設定頻繁變動時（例如
  // 拖曳滑桿）重複呼叫 SystemChrome.setPreferredOrientations。
  ScreenOrientationSetting? _lastAppliedOrientation;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.prefsManager.load(widget.bookId).then((loaded) {
      if (!mounted) return;
      setState(() {
        _prefs = loaded.bookPrefs;
        _loaded = loaded;
        _initialPosition = loaded.readingPosition;
        _resolved = widget.prefsManager.resolve(
          loaded,
          autoDetectedWritingMode: _autoDetectedWritingMode,
        );
      });
      _applyScreenOrientation();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // 離開閱讀畫面時觸發一次位置寫入（spec.md「本機閱讀位置記憶」寫入
    // 時機之一）。不 await——dispose() 是同步方法，且這是離開畫面前的
    // 最後一次呼叫，不需要等待其完成，比照既有 _handlePrefsChanged 不
    // await saveBookPrefs 的既有慣例。
    _writeCurrentPosition();
    // 還原系統預設（允許自由旋轉），不論進入閱讀器時鎖定了哪個角度，比照
    // 音量鍵離開閱讀介面後恢復正常系統音量控制的既有處理原則，避免鎖定
    // 狀態外溢到書架等其他畫面。
    SystemChrome.setPreferredOrientations(const []);
    super.dispose();
  }

  /// App 進入背景時觸發一次位置寫入（spec.md「本機閱讀位置記憶」寫入
  /// 時機之二）。只在 [AppLifecycleState.paused]（真正進入背景）觸發，
  /// 不含 [AppLifecycleState.inactive]（如系統對話框短暫遮蓋等過渡狀態）
  /// ——避免非真正離開情境也觸發資料庫寫入。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _writeCurrentPosition();
    }
  }

  /// 依目前格式讀取對應的持續追蹤狀態（PDF: [_pdfPageInfo]，EPUB:
  /// [_epubPositionInfo]），組成 [ReadingPosition] 後透過 prefsManager
  /// 寫入。尚未收到任何位置回報（例如書籍尚未成功開啟）時靜默不寫入，
  /// 避免用「無資料」覆蓋掉資料庫中既有的正確記錄。
  void _writeCurrentPosition() {
    final format = detectBookFormat(widget.filePath);
    switch (format) {
      case BookFormat.pdf:
        final info = _pdfPageInfo;
        if (info == null) return;
        widget.prefsManager.saveReadingPosition(
          widget.bookId,
          ReadingPosition(
            pdfPageIndex: info.pageIndex,
            progress: info.totalPages > 0
                ? (info.pageIndex + 1) / info.totalPages
                : 0,
          ),
        );
        break;
      case BookFormat.epub:
        final info = _epubPositionInfo;
        if (info == null) return;
        widget.prefsManager.saveReadingPosition(
          widget.bookId,
          ReadingPosition(
            epubLocatorJson: info.locatorJson,
            progress: info.progression ?? 0,
          ),
        );
        break;
      case BookFormat.unknown:
        return;
    }
  }

  /// 依 [_resolved] 的 screenOrientation 呼叫 SystemChrome 套用真實 OS 層級
  /// 鎖定（非僅內容排版層級的假象）。角度與 [DeviceOrientation] 的對應
  /// 是本 issue 撰寫計劃階段決定的慣例（0°→portraitUp、90°→landscapeLeft、
  /// 180°→portraitDown、270°→landscapeRight），實際物理旋轉是否與這組
  /// 對應一致，留待真機測試以驗收標準的人工視覺 QA 確認。
  ///
  /// 為避免使用者在快速拖曳滑桿時產生高頻率的 platform channel 呼叫，
  /// 僅在 screenOrientation 與 [_lastAppliedOrientation] 不同時
  /// 才實際呼叫 SystemChrome。
  void _applyScreenOrientation() {
    final resolved = _resolved;
    if (resolved == null) return;
    if (resolved.screenOrientation == _lastAppliedOrientation) return;
    _lastAppliedOrientation = resolved.screenOrientation;
    SystemChrome.setPreferredOrientations(
      _deviceOrientationsFor(resolved.screenOrientation),
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
    setState(() {
      _prefs = prefs;
      final loaded = _loaded;
      if (loaded != null) {
        final newLoaded = LoadedPrefs(
          bookPrefs: prefs,
          globalPrefs: loaded.globalPrefs,
        );
        _loaded = newLoaded;
        _resolved = widget.prefsManager.resolve(
          newLoaded,
          autoDetectedWritingMode: _autoDetectedWritingMode,
        );
      }
    });
    widget.prefsManager.saveBookPrefs(widget.bookId, prefs);
    _applyScreenOrientation();
  }

  /// 智慧自動裁切首次計算出矩形時觸發（原生端 onCropRectComputed），只
  /// 更新 pdfCropRect 這一個欄位，其餘欄位透過 copyWith 保留原值——這與
  /// _handlePrefsChanged（整列覆寫語意）刻意不同，因為這裡的呼叫端
  /// （PdfReaderView 原生回呼）本來就只知道新計算出的矩形，不該也不會
  /// 附帶其餘欄位的完整狀態。
  void _handleCropRectComputed(PdfCropRect rect) {
    final updated = _prefs.copyWith(pdfCropRect: rect);
    setState(() {
      _prefs = updated;
      final loaded = _loaded;
      if (loaded != null) {
        final newLoaded = LoadedPrefs(
          bookPrefs: updated,
          globalPrefs: loaded.globalPrefs,
        );
        _loaded = newLoaded;
        _resolved = widget.prefsManager.resolve(
          newLoaded,
          autoDetectedWritingMode: _autoDetectedWritingMode,
        );
      }
    });
    widget.prefsManager.saveBookPrefs(widget.bookId, updated);
  }

  /// 手動選區裁切請求（決策 #14）：關閉目前開啟的 PdfSettingsSheet、切換
  /// 至裁切互動模式（宣告式，觸發 PdfReaderView.didUpdateWidget 送出
  /// enterCropEditMode）。context 用的是 State 自身的 context，Navigator
  /// 會沿同一個 Navigator 找到目前最上層的路由（即 showModalBottomSheet
  /// 推入的 PdfSettingsSheet）並將其關閉。
  void _handleRequestManualCrop() {
    Navigator.of(context).pop();
    setState(() => _cropEditModeActive = true);
  }

  /// 使用者在原生裁切互動模式完成框選確認時觸發（PdfReaderView 原生
  /// onCropRectSelected 回呼）：退出裁切互動模式（宣告式，觸發
  /// PdfReaderView.didUpdateWidget 送出 exitCropEditMode）、把結果寫入
  /// BookReaderPrefs（pdfCropMode 固定為 manual、pdfCropRect 為框選
  /// 結果，透過 copyWith 只更新這兩個欄位，其餘欄位保留原值，比照
  /// _handleCropRectComputed 的既有模式），持久化後重新開啟
  /// PdfSettingsSheet 讓使用者看到套用後的結果（見 spec.md「ReaderScreen
  /// 內部行為異動」）。
  void _handleCropRectSelected(PdfCropRect rect) {
    final updated = _prefs.copyWith(
      pdfCropMode: PdfCropMode.manual,
      pdfCropRect: rect,
    );
    setState(() {
      _cropEditModeActive = false;
      _prefs = updated;
      final loaded = _loaded;
      if (loaded != null) {
        final newLoaded = LoadedPrefs(
          bookPrefs: updated,
          globalPrefs: loaded.globalPrefs,
        );
        _loaded = newLoaded;
        _resolved = widget.prefsManager.resolve(
          newLoaded,
          autoDetectedWritingMode: _autoDetectedWritingMode,
        );
      }
    });
    widget.prefsManager.saveBookPrefs(widget.bookId, updated);
    _openPdfSettings();
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

  void _openPdfSettings() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      enableDrag: false,
      builder: (_) => PdfSettingsSheet(
        prefs: _prefs,
        onChanged: _handlePrefsChanged,
        onRequestManualCrop: _handleRequestManualCrop,
      ),
    );
  }

  void _openFxlSettings() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => FxlSettingsSheet(
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
  /// 後，若當下沒有 writingModeOverride，[_resolved] 的 writingMode 會從 null
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
      final loaded = _loaded;
      if (loaded != null) {
        _resolved = widget.prefsManager.resolve(
          loaded,
          autoDetectedWritingMode: info.writingMode,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final format = detectBookFormat(widget.filePath);
    // 方向偵測（spec.md「方向偵測契約」）：在 build() 中統一偵測，格式無關
    // 共用，不寫死在 PDF 專屬程式碼路徑裡——EPUB 分支（Issue 6）之後會消費
    // 同一個 isLandscape 值。
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    return PopScope(
      // 手動裁切互動模式進行中時，返回鍵不應把整個 ReaderScreen 一併 pop
      // 掉——原生端裁切互動模式沒有使用者手勢可以主動觸發離開（見 spec.md
      // 第 123 行「不會主動由使用者手勢觸發」），這裡單純吞掉返回鍵手勢，
      // 讓使用者留在裁切模式，必須透過畫面上的原生確認按鈕才能離開（審查
      // 意見 2.1(b)：避免誤觸返回鍵導致整個閱讀器被意外關閉；刻意不在此
      // 新增「取消並還原」語意，維持 spec.md 已鎖定的簡化狀態機決策）。
      canPop: !_cropEditModeActive,
      child: Scaffold(
        appBar: _isFixedLayout
            ? null // 固定版面（如漫畫）隱藏 Scaffold AppBar，改用 Stack 懸浮半透明按鈕，避免裁切大圖
            : AppBar(
                title: const Text('閱讀器'),
                actions: _buildAppBarActions(format),
              ),
        body: _buildBody(format, isLandscape),
      ),
    );
  }

  List<Widget>? _buildAppBarActions(BookFormat format) {
    if (_isFixedLayout) return null;
    switch (format) {
      case BookFormat.epub:
        return [
          IconButton(
            key: const Key('reader_layout_settings_button'),
            icon: const Icon(Icons.settings),
            tooltip: '版面設定',
            // _autoDetectedWritingMode 非 null 代表 onLayoutResolved 已觸發，
            // 書本已成功開啟、navigatorFragment 已存在，此時開啟版面設定並
            // 呼叫 setPreferences 才有意義（見 EpubReaderView.kt 的靜默忽略
            // 邏輯說明）。
            onPressed:
                _autoDetectedWritingMode == null ? null : _openLayoutSettings,
          ),
        ];
      case BookFormat.pdf:
        return [
          IconButton(
            key: const Key('reader_layout_settings_button'),
            icon: const Icon(Icons.settings),
            tooltip: '版面設定',
            // _state == rendered 代表 onPageRendered 已觸發，PDF 已成功
            // 開啟，此時開啟版面設定並呼叫 setPdfPreferences 才有意義，比照
            // EPUB 分支的既有判斷原則。
            onPressed: _state == _RenderState.rendered ? _openPdfSettings : null,
          ),
        ];
      case BookFormat.unknown:
        return null;
    }
  }

  Widget _buildBody(BookFormat format, bool isLandscape) {
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
    final body = Stack(
      children: [
        if (_resolved != null) _buildNativeView(format, isLandscape),
        if (_isFixedLayout && _fixedLayoutControlsVisible)
          Positioned(
            top: 16, // SafeArea 內層，頂部已扣除狀態列，故直接設為 16 即可
            left: 16,
            child: ClipOval(
              child: Container(
                color: Colors.black54,
                child: IconButton(
                  key: const Key('reader_fixed_layout_back_button'),
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  tooltip: '返回',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ),
          ),
        if (_isFixedLayout && _fixedLayoutControlsVisible)
          Positioned(
            top: 16,
            right: 16,
            child: ClipOval(
              child: Container(
                color: Colors.black54,
                child: IconButton(
                  key: const Key('reader_fixed_layout_settings_button'),
                  icon: const Icon(Icons.settings, color: Colors.white),
                  tooltip: '版面設定',
                  onPressed: _openFxlSettings,
                ),
              ),
            ),
          ),
        if (_state == _RenderState.loading)
          const Center(
            key: Key('reader_loading_indicator'),
            child: CircularProgressIndicator(),
          ),
      ],
    );

    return SafeArea(
      child: Column(
        children: [
          Expanded(child: body),
          // 頁尾佔用固定版面空間、擠壓上方閱讀區域高度（比照
          // prototype/index.html 的 .reader-footer 既有設計，非浮動疊加
          // 層）。本 issue 只接 PDF；EPUB 留給 Issue 3。此階段頁尾一律
          // 顯示，顯示/隱藏開關留給 Issue 5（BookReaderPrefs.showFooter
          // 尚未存在）。
          if (format == BookFormat.pdf && _pdfPageInfo != null)
            ReaderFooter(
              currentPage: _pdfPageInfo!.pageIndex + 1,
              totalPages: _pdfPageInfo!.totalPages,
              onPageChanged: (page1Indexed) {
                // 審查修正：透過強型別 static helper 呼叫，不使用 as dynamic。
                PdfReaderView.jumpToPage(_pdfReaderViewKey, page1Indexed - 1);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildNativeView(BookFormat format, bool isLandscape) {
    final resolved = _resolved!;
    switch (format) {
      case BookFormat.epub:
        return EpubReaderView(
          filePath: widget.filePath,
          writingMode: resolved.writingMode,
          pageTurnMode: resolved.pageTurnMode,
          onPageRendered: _handlePageRendered,
          onError: _handleError,
          onLayoutResolved: _handleLayoutResolved,
          fontFamily: resolved.fontFamily,
          fontSize: resolved.fontSize,
          fontWeight: resolved.fontWeight,
          lineHeight: resolved.lineHeight,
          paragraphSpacing: resolved.paragraphSpacing,
          pageMargins: resolved.pageMargins,
          textAlign: resolved.textAlign,
          publisherStyles: resolved.publisherStyles,
          dualPageMode: resolved.dualPageMode,
          isLandscape: isLandscape,
          onToggleFixedLayoutControls: () => setState(
            () => _fixedLayoutControlsVisible = !_fixedLayoutControlsVisible,
          ),
          // 換頁時一律收起懸浮控制項（更沉浸的閱讀體驗，人類決策，見
          // tmp/epic-16/reviews/review-plan-issue-9.md 之後的討論）——與上面的
          // onToggleFixedLayoutControls 刻意不同：這裡不論收起前是顯示或隱藏，
          // 一律強制設為 false，不是切換（toggle）語意。
          onFixedLayoutPageTurn: () =>
              setState(() => _fixedLayoutControlsVisible = false),
          initialLocatorJson: _initialPosition?.epubLocatorJson,
          onLocatorChanged: (info) {
            if (!mounted) return;
            _epubPositionInfo = info;
          },
        );
      case BookFormat.pdf:
        return PdfReaderView(
          key: _pdfReaderViewKey,
          filePath: widget.filePath,
          initialPageIndex: _initialPosition?.pdfPageIndex,
          onPageRendered: _handlePageRendered,
          onError: _handleError,
          fitMode: resolved.pdfFitMode,
          contrast: resolved.pdfContrast,
          brightness: resolved.pdfBrightness,
          boldStrength: resolved.pdfBoldStrength,
          cropMode: resolved.pdfCropMode,
          cropRect: resolved.pdfCropRect,
          onCropRectComputed: _handleCropRectComputed,
          cropEditModeActive: _cropEditModeActive,
          onCropRectSelected: _handleCropRectSelected,
          dualPageMode: resolved.dualPageMode,
          dualPageCoverAlone: resolved.dualPageCoverAlone,
          dualPageDirection: resolved.dualPageDirection,
          isLandscape: isLandscape,
          onPageChanged: (info) {
            if (!mounted) return;
            setState(() => _pdfPageInfo = info);
          },
        );
      case BookFormat.unknown:
        return const SizedBox.shrink();
    }
  }
}
