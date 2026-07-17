import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../reader/annotation_list_item.dart';
import '../reader/book_format.dart';
import '../reader/bookmark_position_context.dart';
import '../reader/bookmarks_repository.dart';
import '../reader/book_reader_prefs.dart';
import '../reader/epub_decoration.dart';
import '../reader/epub_page_estimator.dart';
import '../reader/epub_position_info.dart';
import '../reader/epub_reader_view.dart';
import '../reader/epub_selection_info.dart';
import '../reader/highlight.dart';
import '../reader/highlight_style.dart';
import '../reader/highlights_repository.dart';
import '../reader/note.dart';
import '../reader/notes_repository.dart';
import '../reader/pdf_crop_mode.dart';
import '../reader/pdf_crop_rect.dart';
import '../reader/pdf_page_info.dart';
import '../reader/pdf_reader_view.dart';
import '../reader/reading_position.dart';
import '../reader/reader_prefs_manager.dart';
import '../reader/toc_entry.dart';
import '../reader/toc_navigator.dart';
import '../reader/resolved_preferences.dart';
import '../reader/screen_orientation_setting.dart';
import '../reader/writing_mode.dart';
import 'annotation_toolbar.dart';
import 'note_edit_dialog.dart';
import 'notes_bottom_sheet.dart';
import 'fxl_settings_sheet.dart';
import 'pdf_settings_sheet.dart';
import 'reader_footer.dart';
import 'reader_settings_sheet.dart';
import 'toc_bottom_sheet.dart';

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

  /// 書籤功能的資料存取層（epic-6-annotations Issue 1）。刻意為可選參數
  /// （非 required）——未提供時 AppBar 不顯示「📚 筆記」按鈕，行為等同
  /// 本 Issue 之前，讓既有大量測試呼叫端不需要逐一補上這個參數（見
  /// plan-issue-1.md Global Constraints）。
  final BookmarksRepository? bookmarksRepository;

  /// 劃線／備註功能的資料存取層（epic-6-annotations Issue 2）。與
  /// [bookmarksRepository] 同樣刻意為可選參數——未提供時 EPUB 選取事件
  /// 不會顯示浮動工具列、`NotesBottomSheet`「✏️」分頁維持空狀態佔位符，
  /// 行為等同本 Issue 之前，零回歸。
  final HighlightsRepository? highlightsRepository;
  final NotesRepository? notesRepository;

  const ReaderScreen({
    super.key,
    required this.filePath,
    required this.bookId,
    required this.prefsManager,
    this.bookmarksRepository,
    this.highlightsRepository,
    this.notesRepository,
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
  // EPUB 全書字元數快取，由 LoadedPrefs.totalCharacterCount 載入（若有）
  // 或 EpubReaderView.onCharacterCountReady 回報更新（Epic 5 Issue 3）。
  // null 代表尚未計算完成，此時 EPUB 頁尾不顯示（比照 PDF 頁尾等待
  // _pdfPageInfo 非 null 的既有模式）。
  int? _totalCharacterCount;
  // 目錄樹狀結構快取（Epic 5 Issue 4），由 onLayoutResolved 觸發一次性
  // 背景抓取（見 _handleLayoutResolved）。樹狀結構不隨版面設定變動，開書
  // 期間只抓取一次，不需要每次版面參數變動都重新請求。
  List<TocEntry> _tocEntries = const [];
  // 審查修正：背景抓取是否已完成（不論結果是否為空清單）。目錄按鈕的
  // onPressed 須同時檢查這個旗標，而不是只檢查 _autoDetectedWritingMode
  // 非 null——否則使用者可能在按鈕剛變成可點擊、但 loadTableOfContents()
  // 尚未回應的極短窗口內點擊，開啟一個完全空白、且無法與「本書真的沒有
  // 目錄」區分的 Bottom Sheet。比照既有「⚙️版面設定」按鈕的既定模式
  // （等待相關非同步就緒訊號才啟用），不引入本專案目前沒有的「Bottom
  // Sheet 內顯示載入中」UI 型態。
  bool _tocLoaded = false;
  // EPUB 劃線／備註快取（epic-6-annotations Issue 2），由
  // _reloadAnnotationsAndRefreshDecorations() 統一載入與更新。
  List<Highlight> _highlights = [];
  List<Note> _notes = [];
  bool _annotationsLoaded = false;
  // 目前選取範圍（原生 onSelectionChanged 回報），非 null 時於 body
  // Stack 顯示 AnnotationToolbar；FXL 一律不使用（見
  // _handleSelectionChanged 開頭防呆）。
  EpubSelectionInfo? _currentSelection;
  // 同一次選取中，使用者若已點擊螢光筆/底線建立劃線，暫存其資料庫 id，
  // 供接著點擊「備註」時把新備註連結到這筆劃線（design.md 使用者流程：
  // 「若同時已選色/底線，備註與劃線共存於同一筆記錄」）。新選取範圍
  // 開始時（_handleSelectionChanged）重置為 null。
  int? _pendingHighlightIdForSelection;
  // 供 TocBottomSheet 訂閱、在已開啟的目錄畫面即時反映全書字元數背景計算
  // 完成事件（spec.md「目錄模組」載入中狀態決策）——與 _totalCharacterCount
  // 這個驅動頁尾 rebuild 的既有欄位（Issue 3）刻意分開維護，避免耦合兩條
  // 目的不同的更新路徑（頁尾靠 setState 觸發整個 ReaderScreen rebuild；
  // 目錄靠 ValueNotifier 只更新已開啟的 Bottom Sheet 子樹，不驚動
  // ReaderScreen 本身）。
  final _totalCharacterCountNotifier = ValueNotifier<int?>(null);
  // 開書時讀到的既有位置記錄（若有），只在 initState 賦值一次，之後
  // 不變——僅用於 _buildNativeView() 建構 EpubReaderView/PdfReaderView
  // 時傳入 initialLocatorJson/initialPageIndex 這兩個一次性開書起始值。
  ReadingPosition? _initialPosition;
  // 用於呼叫 PdfReaderView.jumpToPage(key, pageIndex) 這個強型別 static
  // helper（審查修正，見 Task 2 Step 4——不使用 as dynamic 跨 State 私有
  // 邊界呼叫，避免 release 混淆／tree-shaking 風險）。
  final _pdfReaderViewKey = GlobalKey<State<PdfReaderView>>();
  // 用於呼叫 EpubReaderView.jumpToProgression(key, progression) 這個強型別
  // static helper（Epic 5 Issue 3），比照 _pdfReaderViewKey 對 PDF 的既有
  // 作法。
  final _epubReaderViewKey = GlobalKey<State<EpubReaderView>>();
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
        _totalCharacterCount = loaded.totalCharacterCount;
        _totalCharacterCountNotifier.value = loaded.totalCharacterCount;
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
    _totalCharacterCountNotifier.dispose();
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
        // progression 為 null 時（例如 Readium 對某些定位尚未完全解析版面
        // 的早期定位、或 FXL 固定版面的定位），不覆寫進度，改用既有值——
        // 避免把已讀大半的書的進度靜默倒退回 0%（見 C2 審查修正 I2）。
        final progression = info.progression;
        if (progression == null) {
          final existingProgress = _initialPosition?.progress;
          if (existingProgress == null) return;
          widget.prefsManager.saveReadingPosition(
            widget.bookId,
            ReadingPosition(
              epubLocatorJson: info.locatorJson,
              progress: existingProgress,
            ),
          );
        } else {
          widget.prefsManager.saveReadingPosition(
            widget.bookId,
            ReadingPosition(
              epubLocatorJson: info.locatorJson,
              progress: progression,
            ),
          );
        }
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
          readingPosition: loaded.readingPosition,
          totalCharacterCount: loaded.totalCharacterCount,
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
          readingPosition: loaded.readingPosition,
          totalCharacterCount: loaded.totalCharacterCount,
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
          readingPosition: loaded.readingPosition,
          totalCharacterCount: loaded.totalCharacterCount,
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

  void _openToc() {
    final currentPath = TocNavigator.findCurrentPath(
      _tocEntries,
      _epubPositionInfo?.progression,
    );
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => TocBottomSheet(
        entries: _tocEntries,
        initiallyExpandedEntries: currentPath.toSet(),
        currentEntry: currentPath.isEmpty ? null : currentPath.last,
        totalCharacterCountListenable: _totalCharacterCountNotifier,
        resolved: _resolved!,
        onEntrySelected: (entry) {
          Navigator.of(context).pop();
          EpubReaderView.jumpToLocator(_epubReaderViewKey, entry.locatorJson);
        },
      ),
    );
  }

  void _openNotesSheet(BookFormat format) {
    final repository = widget.bookmarksRepository;
    if (repository == null) return;
    final currentPath = TocNavigator.findCurrentPath(
      _tocEntries,
      _epubPositionInfo?.progression,
    );
    final positionContext = BookmarkPositionContext(
      epubLocatorJson:
          format == BookFormat.epub ? _epubPositionInfo?.locatorJson : null,
      progression:
          format == BookFormat.epub ? _epubPositionInfo?.progression : null,
      pdfPageIndex: format == BookFormat.pdf ? _pdfPageInfo?.pageIndex : null,
      chapterTitle: currentPath.isEmpty ? null : currentPath.last.title,
    );
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => NotesBottomSheet(
        bookId: widget.bookId,
        bookmarksRepository: repository,
        currentPosition: positionContext,
        highlightsRepository:
            format == BookFormat.epub && !_isFixedLayout ? widget.highlightsRepository : null,
        notesRepository:
            format == BookFormat.epub && !_isFixedLayout ? widget.notesRepository : null,
        onAnnotationSelected: (item) {
          Navigator.of(context).pop();
          final locatorJson = item.highlight?.epubLocatorJson ?? item.note?.epubLocatorJson;
          if (locatorJson != null) {
            EpubReaderView.jumpToLocator(_epubReaderViewKey, locatorJson);
          }
        },
        onAnnotationsChanged: _reloadAnnotationsAndRefreshDecorations,
        onBookmarkSelected: (bookmark) {
          Navigator.of(context).pop();
          if (bookmark.epubLocatorJson != null) {
            EpubReaderView.jumpToLocator(
              _epubReaderViewKey,
              bookmark.epubLocatorJson!,
            );
          } else if (bookmark.pdfPageIndex != null) {
            PdfReaderView.jumpToPage(_pdfReaderViewKey, bookmark.pdfPageIndex!);
          }
        },
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
    // epic-5-toc-pagination Issue 4：目錄僅支援流式 EPUB（spec.md「範圍
    // 界定」），FXL 不預取。目錄樹狀結構不會隨版面設定變動而改變（與頁碼
    // 估算不同，見 _buildEpubFooter 的重算邏輯），理論上只需要抓取一次。
    //
    // 【審查修正，防禦性保險】原生端 onLayoutResolved 目前的 pageReported
    // 一次性 latch（見 EpubReaderView.kt openBook()/onPageLoaded()）與
    // MainActivity 的 configChanges 宣告，已確保本方法在單次開書期間只會
    // 被呼叫一次——旋轉螢幕、調整字型大小都不會讓它再次觸發，故目前並不
    // 存在「每次版面重排都重複抓取目錄」的實際效能問題。加上
    // `_tocEntries.isEmpty` 這道檢查純粹是把「只抓取一次」這句話從隱含假設
    // 變成程式碼本身強制執行的行為，零成本、無副作用；即使原生端的一次性
    // 觸發機制未來被改動，這裡也不會退化成重複請求。
    if (!info.isFixedLayout && _tocEntries.isEmpty && !_tocLoaded) {
      EpubReaderView.loadTableOfContents(_epubReaderViewKey).then((entries) {
        if (!mounted) return;
        setState(() {
          _tocEntries = entries;
          _tocLoaded = true;
        });
      });
    }
    if (!info.isFixedLayout &&
        !_annotationsLoaded &&
        widget.highlightsRepository != null &&
        widget.notesRepository != null) {
      _annotationsLoaded = true;
      _reloadAnnotationsAndRefreshDecorations();
    }
  }

  /// 原生端背景計算全書字元數完成時觸發（Epic 5 Issue 3）：更新本地狀態
  /// 驅動頁尾重新渲染，並持久化快取值——不 await，比照本類別其餘持久化
  /// 呼叫的既有慣例（見 _handlePrefsChanged）。
  void _handleCharacterCountReady(int totalCharacterCount) {
    if (!mounted) return;
    setState(() => _totalCharacterCount = totalCharacterCount);
    _totalCharacterCountNotifier.value = totalCharacterCount;
    widget.prefsManager.saveTotalCharacterCount(widget.bookId, totalCharacterCount);
  }

  /// FXL 一律不處理選取事件（design.md 決策 #7：劃線/備註排除 FXL）——
  /// 理論上 FXL 頁面多半無可選取文字層，此防呆保證不會意外對 FXL 觸發
  /// 劃線 UI（見 plan-issue-2.md Global Constraints「FXL 排除」）。
  void _handleSelectionChanged(EpubSelectionInfo info) {
    if (!mounted || _isFixedLayout) return;
    setState(() {
      _currentSelection = info;
      _pendingHighlightIdForSelection = null;
    });
  }

  void _handleSelectionCleared() {
    if (!mounted) return;
    setState(() {
      _currentSelection = null;
      _pendingHighlightIdForSelection = null;
    });
  }

  Future<void> _handleHighlightStyleSelected(HighlightStyle style) async {
    final selection = _currentSelection;
    final repository = widget.highlightsRepository;
    if (selection == null || repository == null) return;
    final id = await repository.insert(Highlight(
      bookId: widget.bookId,
      style: style,
      epubLocatorJson: selection.locatorJson,
      progression: selection.progression,
    ));
    _pendingHighlightIdForSelection = id;
    await _reloadAnnotationsAndRefreshDecorations();
  }

  Future<void> _handleNotePressed() async {
    final selection = _currentSelection;
    final repository = widget.notesRepository;
    if (selection == null || repository == null) return;
    final text = await showNoteTextDialog(context, title: '新增備註');
    if (text == null) return;
    await repository.insert(Note(
      bookId: widget.bookId,
      text: text,
      epubLocatorJson: selection.locatorJson,
      progression: selection.progression,
      highlightId: _pendingHighlightIdForSelection,
    ));
    await _reloadAnnotationsAndRefreshDecorations();
    if (!mounted) return;
    setState(() {
      _currentSelection = null;
      _pendingHighlightIdForSelection = null;
    });
  }

  /// 重新查詢本書全部劃線/備註並送給原生端重繪 Decorator（比照 TOC 的
  /// 「只在尚未載入過才抓取」慣例，但本方法每次 CRUD 後皆會主動重新
  /// 呼叫，非只呼叫一次——這裡的 `_annotationsLoaded` 只用於「開書時是否
  /// 已載入過初始清單」，不是「是否曾呼叫過本方法」）。
  Future<void> _reloadAnnotationsAndRefreshDecorations() async {
    final highlightsRepository = widget.highlightsRepository;
    final notesRepository = widget.notesRepository;
    if (highlightsRepository == null || notesRepository == null) return;
    final highlights = await highlightsRepository.listByBook(widget.bookId);
    final notes = await notesRepository.listByBook(widget.bookId);
    if (!mounted) return;
    setState(() {
      _highlights = highlights;
      _notes = notes;
    });
    _sendDecorationsToNative();
  }

  void _sendDecorationsToNative() {
    if (!mounted) return;
    final primaryColor = Theme.of(context).colorScheme.primary;
    final decorations = <EpubDecoration>[
      for (final highlight in _highlights)
        if (highlight.id != null && highlight.epubLocatorJson != null)
          EpubDecoration.forHighlight(
            highlightId: highlight.id!,
            locatorJson: highlight.epubLocatorJson!,
            tint: highlightStyleTint(highlight.style, primaryColor: primaryColor),
            isUnderline: highlight.style == HighlightStyle.underline,
          ),
      for (final note in _notes)
        if (note.highlightId == null && note.id != null && note.epubLocatorJson != null)
          EpubDecoration.forNote(
            noteId: note.id!,
            locatorJson: note.epubLocatorJson!,
            tint: noteOnlyTint.toARGB32(),
          ),
    ];
    EpubReaderView.setDecorations(_epubReaderViewKey, decorations);
  }

  Highlight? _findHighlightById(int id) {
    for (final highlight in _highlights) {
      if (highlight.id == id) return highlight;
    }
    return null;
  }

  Note? _findNoteByHighlightId(int highlightId) {
    for (final note in _notes) {
      if (note.highlightId == highlightId) return note;
    }
    return null;
  }

  Note? _findNoteById(int id) {
    for (final note in _notes) {
      if (note.id == id) return note;
    }
    return null;
  }

  /// 原生端 onAnnotationActivated 回呼（使用者點擊既有標記）：依
  /// [decodeAnnotationId] 反查是哪一筆記錄，開啟編輯/刪除 Dialog
  /// （design.md 使用者流程步驟 3）。id 格式不明或查無對應記錄時靜默
  /// 忽略——理論上不會發生（送給原生端的 id 皆由
  /// [EpubDecoration.forHighlight]/[EpubDecoration.forNote] 產生），但
  /// 點擊當下記錄可能已被其他途徑刪除（極短競速窗口），静默忽略比拋出
  /// 例外更穩妥。
  void _handleAnnotationActivated(String decorationId) {
    final decoded = decodeAnnotationId(decorationId);
    if (decoded == null) return;
    AnnotationListItem item;
    switch (decoded.kind) {
      case AnnotationKind.highlight:
        final highlight = _findHighlightById(decoded.id);
        if (highlight == null) return;
        item = AnnotationListItem(
          highlight: highlight,
          note: _findNoteByHighlightId(decoded.id),
        );
        break;
      case AnnotationKind.note:
        final note = _findNoteById(decoded.id);
        if (note == null) return;
        item = AnnotationListItem(note: note);
        break;
    }
    _showAnnotationActionDialog(item);
  }

  Future<void> _showAnnotationActionDialog(AnnotationListItem item) async {
    final action = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('劃線/備註'),
        children: [
          if (item.note != null)
            SimpleDialogOption(
              onPressed: () => Navigator.of(dialogContext).pop('edit'),
              child: const Text('✍️ 編輯備註文字'),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(dialogContext).pop('delete'),
            child: const Text('🗑️ 刪除此劃線與備註'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    final note = item.note;
    final highlight = item.highlight;
    if (action == 'edit' && note != null) {
      final newText = await showNoteTextDialog(context, initialText: note.text, title: '編輯備註');
      if (newText != null) {
        await widget.notesRepository!.updateText(note.id!, newText);
        await _reloadAnnotationsAndRefreshDecorations();
      }
    } else if (action == 'delete') {
      // 單筆刪除＝整筆一起刪（spec.md 決策 #13），比照
      // NotesBottomSheet._deleteAnnotationItem 的既有原則。
      if (note != null) await widget.notesRepository!.delete(note.id!);
      if (highlight != null) await widget.highlightsRepository!.delete(highlight.id!);
      await _reloadAnnotationsAndRefreshDecorations();
    }
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
                title: _buildAppBarTitle(format),
                actions: _buildAppBarActions(format),
              ),
        body: _buildBody(format, isLandscape),
      ),
    );
  }

  /// 頁首顯示切換（epic-5-toc-pagination Issue 5，spec.md「頁首/頁尾顯示
  /// 切換」）：`showHeader == false` 或非 EPUB 格式時維持既有的靜態標題；
  /// `showHeader == true`（含尚未載入完成前的安全預設值，見
  /// `ResolvedPreferences.showHeader`）時改用目前章節名稱，可點擊開啟目錄
  /// （沿用 Issue 4 的 `TocNavigator.findCurrentPath`／`_openToc`）。章節
  /// 名稱在目錄背景抓取完成（`_tocLoaded`）前一律回退顯示「閱讀器」佔位
  /// 文字，`onTap` 同步以 `_tocLoaded` 防呆，比照 `_buildAppBarActions` 的
  /// 目錄按鈕既有 gating 條件，避免點擊到空白 Bottom Sheet。
  Widget _buildAppBarTitle(BookFormat format) {
    final showHeader = format == BookFormat.epub && (_resolved?.showHeader ?? true);
    if (!showHeader) {
      return const Text('閱讀器', key: Key('reader_appbar_static_title'));
    }
    final currentPath = TocNavigator.findCurrentPath(
      _tocEntries,
      _epubPositionInfo?.progression,
    );
    final chapterTitle = currentPath.isEmpty ? '閱讀器' : currentPath.last.title;
    return InkWell(
      key: const Key('reader_appbar_chapter_title'),
      onTap: (_autoDetectedWritingMode == null || !_tocLoaded) ? null : _openToc,
      child: Text(chapterTitle, overflow: TextOverflow.ellipsis),
    );
  }

  List<Widget>? _buildAppBarActions(BookFormat format) {
    if (_isFixedLayout) return null;
    switch (format) {
      case BookFormat.epub:
        return [
          IconButton(
            key: const Key('reader_toc_button'),
            icon: const Icon(Icons.menu_book),
            tooltip: '目錄',
            // 沿用與「⚙️版面」按鈕一致的啟用條件（_autoDetectedWritingMode
            // 非 null 代表 onLayoutResolved 已觸發，書本已成功開啟），並
            // 額外要求 _tocLoaded（審查修正）——避免使用者在背景抓取
            // 完成前點擊，開啟一個無法與「本書真的沒有目錄」區分的空白
            // Bottom Sheet。
            onPressed: (_autoDetectedWritingMode == null || !_tocLoaded)
                ? null
                : _openToc,
          ),
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
          if (widget.bookmarksRepository != null)
            IconButton(
              key: const Key('reader_notes_button'),
              icon: const Icon(Icons.bookmarks),
              tooltip: '筆記',
              // 除了 _autoDetectedWritingMode（onLayoutResolved 已觸發）之外，
              // 額外要求 _epubPositionInfo 非 null（審查修正）——這兩個回呼
              // 來自原生端兩條各自獨立、無先後順序保證的非同步路徑
              // （onLayoutResolved／onLocatorChanged），若只檢查前者，使用者
              // 可能在 onLocatorChanged 尚未觸發過任何一次的極短窗口內點擊
              // 「新增書籤」，寫入一筆 epubLocatorJson/progression 皆為 null
              // 的壞書籤（之後永遠無法被跳轉、判定為已加書籤或移除）。比照
              // 目錄按鈕 _tocLoaded 的既有防呆模式（見上方 reader_toc_button
              // 註解），同一種競速問題、不同欄位。
              onPressed: (_autoDetectedWritingMode == null || _epubPositionInfo == null)
                  ? null
                  : () => _openNotesSheet(format),
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
          if (widget.bookmarksRepository != null)
            IconButton(
              key: const Key('reader_notes_button'),
              icon: const Icon(Icons.bookmarks),
              tooltip: '筆記',
              onPressed: _state == _RenderState.rendered
                  ? () => _openNotesSheet(format)
                  : null,
            ),
        ];
      case BookFormat.unknown:
        return null;
    }
  }

  // 浮動工具列估計高度／與選取範圍的間距（初始選擇，真機測試後可能需
  // 微調，見 Global Constraints「選取矩形座標協定」）。
  static const _annotationToolbarHeight = 56.0;
  static const _annotationToolbarGap = 8.0;

  /// 【審查修正】原本無條件把工具列定位在選取範圍上方、clamp 到
  /// `>= 0`，若選取範圍太靠近頂端（`topPct * height < 工具列高度`），
  /// clamp 後的 `top` 會落在 0，導致工具列往下遮住選取範圍第一行文字
  /// （clamp 只保證不跑到畫面外，不保證不遮擋選取範圍本身）。改為：
  /// 選取範圍上方若有足夠空間才貼在上方；空間不足時改貼在選取範圍
  /// 下方，兩種情況下工具列都不會覆蓋選取矩形本體。
  double _annotationToolbarTop(EpubSelectionInfo selection, Size size) {
    final topAboveSelection =
        selection.rect.top * size.height - _annotationToolbarHeight - _annotationToolbarGap;
    if (topAboveSelection >= 0) return topAboveSelection;
    final belowSelection = selection.rect.bottom * size.height + _annotationToolbarGap;
    return belowSelection.clamp(0.0, size.height - _annotationToolbarHeight);
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
    final body = LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final selection = _currentSelection;
        return Stack(
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
            if (selection != null)
              Positioned(
                left: (selection.rect.left * size.width).clamp(0.0, size.width),
                top: _annotationToolbarTop(selection, size),
                child: AnnotationToolbar(
                  onStyleSelected: _handleHighlightStyleSelected,
                  onNotePressed: _handleNotePressed,
                ),
              ),
            if (_state == _RenderState.loading)
              const Center(
                key: Key('reader_loading_indicator'),
                child: CircularProgressIndicator(),
              ),
          ],
        );
      },
    );

    return SafeArea(
      child: Column(
        children: [
          Expanded(child: body),
          // 頁尾佔用固定版面空間、擠壓上方閱讀區域高度（比照
          // prototype/index.html 的 .reader-footer 既有設計，非浮動疊加
          // 層）。顯示/隱藏由 showFooter 控制（epic-5-toc-pagination
          // Issue 5），false 時整個 if 條件不成立、完全不佔用版面空間。
          if (format == BookFormat.pdf &&
              _pdfPageInfo != null &&
              (_resolved?.showFooter ?? true))
            ReaderFooter(
              currentPage: _pdfPageInfo!.pageIndex + 1,
              totalPages: _pdfPageInfo!.totalPages,
              onPageChanged: (page1Indexed) {
                // 審查修正：透過強型別 static helper 呼叫，不使用 as dynamic。
                PdfReaderView.jumpToPage(_pdfReaderViewKey, page1Indexed - 1);
              },
            ),
          if (format == BookFormat.epub &&
              !_isFixedLayout &&
              _totalCharacterCount != null &&
              _resolved != null &&
              _resolved!.showFooter)
            _buildEpubFooter(_resolved!, _totalCharacterCount!),
        ],
      ),
    );
  }

  /// EPUB 估算頁碼頁尾（Epic 5 Issue 3）：依目前生效版面參數＋全書字元數
  /// 快取換算總頁數，再依 _epubPositionInfo 的全書進度比例換算目前頁碼；
  /// 任一版面參數變動時，本方法在下一次 build() 會以新的 [resolved] 重新
  /// 計算，不需要額外的快取/失效邏輯（見 spec.md「估計頁數重算時機」）。
  Widget _buildEpubFooter(ResolvedPreferences resolved, int totalCharacterCount) {
    final charsPerScreen = EpubPageEstimator.estimateCharsPerScreen(
      fontSize: resolved.fontSize,
      lineHeight: resolved.lineHeight,
      paragraphSpacing: resolved.paragraphSpacing,
      pageMargins: resolved.pageMargins,
    );
    final totalPages = EpubPageEstimator.estimateTotalPages(
      totalCharacterCount: totalCharacterCount,
      charsPerScreen: charsPerScreen,
    );
    final currentPage = EpubPageEstimator.estimateCurrentPage(
      progression: _epubPositionInfo?.progression,
      totalPages: totalPages,
    );
    return ReaderFooter(
      currentPage: currentPage,
      totalPages: totalPages,
      onPageChanged: (targetPage) {
        final progression = EpubPageEstimator.estimateProgression(
          targetPage: targetPage,
          totalPages: totalPages,
        );
        EpubReaderView.jumpToProgression(_epubReaderViewKey, progression);
      },
    );
  }

  Widget _buildNativeView(BookFormat format, bool isLandscape) {
    final resolved = _resolved!;
    switch (format) {
      case BookFormat.epub:
        return EpubReaderView(
          key: _epubReaderViewKey,
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
            setState(() => _epubPositionInfo = info);
          },
          totalCharacterCount: _totalCharacterCount,
          onCharacterCountReady: _handleCharacterCountReady,
          onSelectionChanged: _handleSelectionChanged,
          onSelectionCleared: _handleSelectionCleared,
          onAnnotationActivated: _handleAnnotationActivated,
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
