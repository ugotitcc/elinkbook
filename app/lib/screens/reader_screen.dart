import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../reader/annotation_list_item.dart';
import '../reader/book_format.dart';
import '../reader/bookmark.dart';
import '../reader/bookmark_position_context.dart';
import '../reader/bookmarks_repository.dart';
import '../reader/book_reader_prefs.dart';
import '../reader/epub_decoration.dart';
import '../reader/epub_page_estimator.dart';
import '../reader/epub_position_info.dart';
import '../reader/epub_reader_view.dart';
import '../reader/epub_selection_info.dart';
import '../reader/foliate_epub_reader_view.dart';
import '../library/library_repository.dart';
import '../reader/highlight.dart';
import '../reader/highlight_style.dart';
import '../reader/highlights_repository.dart';
import '../reader/note.dart';
import '../reader/notes_repository.dart';
import '../reader/pdf_annotation_decoration.dart';
import '../reader/pdf_crop_mode.dart';
import '../reader/pdf_crop_rect.dart';
import '../reader/pdf_page_info.dart';
import '../reader/pdf_reader_view.dart';
import '../reader/pdf_selection_info.dart';
import '../reader/reading_position.dart';
import '../reader/reader_prefs_manager.dart';
import '../reader/toc_entry.dart';
import '../reader/toc_navigator.dart';
import '../reader/resolved_preferences.dart';
import '../reader/screen_orientation_setting.dart';
import '../reader/writing_mode.dart';
import '../reader/zone_action.dart';
import 'annotation_toolbar.dart';
import 'note_edit_dialog.dart';
import 'notes_bottom_sheet.dart';
import 'fxl_settings_sheet.dart';
import 'pdf_settings_sheet.dart';
import 'reader_footer.dart';
import 'reader_settings_sheet.dart';
import 'toc_bottom_sheet.dart';

/// 音量鍵事件頻道（epic-7-interaction Issue 7）：原生 `MainActivity.
/// dispatchKeyEvent()` 攔截音量鍵後呼叫 `onVolumeKey`；`_handleVolumeKeyCall`
/// 轉呼叫既有的 `_handleZoneAction`。既有 `PopScope` 的
/// `onPopInvokedWithResult` 於 pop 動作啟動當下呼叫 `notifyLeavingReader`，
/// 讓原生端立即停止攔截（早於退場轉場動畫、更早於 dispose()，見
/// docs/epics/epic-7-interaction/spec.md「新增音量鍵頻道」）。
const _volumeKeyChannel = MethodChannel('elinkbook/volume_key');

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

  /// 供「導出為 Markdown」使用的書籍中繼資料（epic-6-annotations
  /// Issue 5）。刻意為可選具名參數並附預設值——比照 [bookmarksRepository]
  /// 既有慣例，避免既有大量測試呼叫端需要逐一補上這三個參數。
  final String bookTitle;
  final String? bookAuthor;
  final double bookProgress;

  /// EPUB 是否為固定版面（FXL），對應 `Book.isFixedLayout`（epic-17
  /// Issue 2）。`null` 代表既有書籍尚未判斷過——此時若提供
  /// [libraryRepository]，會一次性呼叫 [LibraryRepository.detectAndCacheEpubLayout]
  /// 判斷並回寫資料庫；若未提供 [libraryRepository]（例如既有測試呼叫端），
  /// 退回 Issue 3 之前的既有行為，一律視為固定版面、建構 [EpubReaderView]
  /// （Readium），零回歸。非 EPUB 格式完全不受此欄位影響。
  final bool? isFixedLayout;

  /// 供 [isFixedLayout] 為 `null` 時呼叫 [LibraryRepository.detectAndCacheEpubLayout]
  /// 使用。刻意為可選參數——比照 [bookmarksRepository] 既有慣例，避免既有
  /// 大量測試呼叫端需要逐一補上這個參數。
  final LibraryRepository? libraryRepository;

  const ReaderScreen({
    super.key,
    required this.filePath,
    required this.bookId,
    required this.prefsManager,
    this.bookmarksRepository,
    this.highlightsRepository,
    this.notesRepository,
    this.bookTitle = '未知書籍',
    this.bookAuthor,
    this.bookProgress = 0.0,
    this.isFixedLayout,
    this.libraryRepository,
  });

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();

  /// 供測試／`PdfReaderView`／後續 Issue 5-7 的原生回呼安全呼叫
  /// [_ReaderScreenState._handleZoneAction] 的強型別 static helper，比照
  /// `PdfReaderView.jumpToPage` 既有模式：不使用 `as dynamic` 跨越 State
  /// 的 private 邊界。[key] 對應的 State 若尚未掛載，靜默忽略。
  static void triggerZoneAction(
    GlobalKey<State<ReaderScreen>> key,
    ZoneAction action,
  ) {
    final state = key.currentState;
    if (state is _ReaderScreenState) {
      state._handleZoneAction(action);
    }
  }
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
  // 介面顯示狀態（AppBar＋頁尾＋FXL 懸浮控制項）是否可見，格式無關
  // （epic-7-interaction Issue 4，原為 FXL 專屬的 _fixedLayoutControlsVisible
  // 欄位改名／擴大適用範圍）。由熱區「選單」動作切換（見
  // _handleZoneAction），EPUB FXL 既有熱區的中間格（epic-16-dual-page
  // Issue 9；epic-7 Issue 5 擴充為九宮格）與新的 PDF 熱區皆共用同一個
  // 狀態。預設顯示。
  bool _chromeVisible = true;
  // FXL 懸浮「🔖 書籤 toggle」按鈕圖示所需的最小狀態快取
  // （epic-6-annotations Issue 4）：與 NotesBottomSheet 內部「🔖 書籤」
  // 分頁各自獨立載入自己的清單（比照既有分頁按鈕 toggle 與 Bottom Sheet
  // 清單各自管理狀態的既定模式），只負責懸浮按鈕圖示的二態顯示。載入
  // 時機見 _handleLayoutResolved（初次開書）／_openNotesSheet（Bottom
  // Sheet 關閉後重新整理，使用者可能在分頁裡新增/刪除書籤）。
  List<Bookmark> _fxlBookmarks = [];
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
  // PDF 劃線／備註目前選取狀態（epic-6-annotations Issue 3），由原生端
  // onSelectionRectComputed 回報；非 null 時於 body Stack 顯示
  // AnnotationToolbar。與 EPUB 的 _currentSelection 並存但不會同時非
  // null（同一次只會開啟一種格式的書籍）。
  PdfSelectionInfo? _currentPdfSelection;
  int? _pendingPdfHighlightIdForSelection;
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
  // 用於呼叫 FoliateEpubReaderView 未來（Issue 4-8）新增的強型別 static
  // helper，比照 _epubReaderViewKey 對 EpubReaderView 的既有作法。本 Issue
  // 尚未實際使用，先建立以維持與既有 widget 的對稱慣例。
  final _foliateEpubReaderViewKey = GlobalKey<State<FoliateEpubReaderView>>();
  // 記錄上一次實際套用給系統的螢幕方向，避免在偏好設定頻繁變動時（例如
  // 拖曳滑桿）重複呼叫 SystemChrome.setPreferredOrientations。
  ScreenOrientationSetting? _lastAppliedOrientation;
  // EPUB 引擎分派結果（epic-17-epub-render-migration Issue 3）：true=FXL
  // （EpubReaderView／Readium）、false=流式（FoliateEpubReaderView）、
  // null=尚未解析完成（既有書籍偵測進行中，畫面維持載入中指示器）。與既有
  // _isFixedLayout（Readium/foliate-js 開書後才回報的執行期狀態，驅動 FXL
  // 懸浮控制項/AppBar 顯示邏輯）是兩個不同概念，互不影響——見
  // docs/epics/epic-17-epub-render-migration/spec.md「已知限制」。
  bool? _dispatchedIsFixedLayout;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _volumeKeyChannel.setMethodCallHandler(_handleVolumeKeyCall);
    _resolveEpubEngineDispatch();
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

  /// 解析 EPUB 該用哪個渲染引擎（epic-17-epub-render-migration Issue 3）。
  /// `widget.isFixedLayout` 非 null 時直接採用；為 null（既有書籍尚未
  /// 判斷過）時，若提供 [ReaderScreen.libraryRepository]則非同步呼叫
  /// `detectAndCacheEpubLayout()` 判斷並回寫資料庫，期間 `_dispatchedIsFixedLayout`
  /// 維持 null（畫面顯示載入中指示器，見 _buildBody 的 gating 條件）；未
  /// 提供時同步退回既有行為（視為 FXL，建構 EpubReaderView），確保既有
  /// 測試呼叫端零回歸。非 EPUB 格式完全不受影響（`_dispatchedIsFixedLayout`
  /// 維持 null 但 `_buildBody` 的 gating 條件只在 format == epub 時才要求
  /// 它非 null）。
  void _resolveEpubEngineDispatch() {
    _dispatchedIsFixedLayout = widget.isFixedLayout;
    if (_dispatchedIsFixedLayout != null) return;
    if (detectBookFormat(widget.filePath) != BookFormat.epub) return;
    final repository = widget.libraryRepository;
    if (repository == null) {
      // 既有測試/呼叫端未提供 libraryRepository 時，退回 Issue 3 之前的
      // 既有行為——一律視為固定版面（EpubReaderView／Readium），零回歸
      // （見 docs/epics/epic-17-epub-render-migration/spec.md「已知限制」）。
      _dispatchedIsFixedLayout = true;
      return;
    }
    repository
        .detectAndCacheEpubLayout(widget.bookId, widget.filePath)
        .then((result) {
      if (!mounted) return;
      setState(() => _dispatchedIsFixedLayout = result);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _volumeKeyChannel.setMethodCallHandler(null);
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

  Future<void> _loadFxlBookmarks() async {
    final repository = widget.bookmarksRepository;
    if (repository == null) return;
    try {
      final list = await repository.listByBook(widget.bookId);
      if (!mounted) return;
      setState(() => _fxlBookmarks = list);
    } catch (e) {
      debugPrint('Failed to load FXL bookmarks: $e');
    }
  }

  /// 目前頁是否已有書籤——比較 epubLocatorJson 完全相同字串，比照
  /// NotesBottomSheet._matchesCurrentPosition 既有邏輯（FXL 副檔名為
  /// .epub，恆用 epubLocatorJson，不使用 pdfPageIndex，見 Global
  /// Constraints）。
  Bookmark? get _fxlBookmarkAtCurrentPosition {
    final locatorJson = _epubPositionInfo?.locatorJson;
    if (locatorJson == null) return null;
    for (final bookmark in _fxlBookmarks) {
      if (bookmark.epubLocatorJson == locatorJson) return bookmark;
    }
    return null;
  }

  Future<void> _toggleFxlBookmark() async {
    final repository = widget.bookmarksRepository;
    final positionInfo = _epubPositionInfo;
    if (repository == null || positionInfo == null) return;
    final existing = _fxlBookmarkAtCurrentPosition;
    if (existing != null) {
      final id = existing.id;
      if (id != null) {
        await repository.delete(id);
      }
    } else {
      await repository.insert(Bookmark(
        bookId: widget.bookId,
        name: Bookmark.defaultName(BookmarkPositionContext(
          epubLocatorJson: positionInfo.locatorJson,
          progression: positionInfo.progression,
        )),
        epubLocatorJson: positionInfo.locatorJson,
        progression: positionInfo.progression,
      ));
    }
    await _loadFxlBookmarks();
  }

  /// 依 `_dispatchedIsFixedLayout` 分派到正確的原生 widget 執行目錄／
  /// 書籤／備註跳轉（epic-17-epub-render-migration Issue 6）：FXL
  /// （Readium）用 `EpubReaderView.jumpToLocator`，流式（foliate-js）用
  /// `FoliateEpubReaderView.jumpToLocator`，兩者接受的 `locatorJson`
  /// 格式不同（Readium Locator JSON vs 本 Epic 新 CFI 格式），但呼叫端
  /// （本方法的三個呼叫點：`_openToc`／`_openNotesSheet` 的
  /// `onAnnotationSelected`／`onBookmarkSelected`）不需要關心格式差異，
  /// 只需傳入目前使用中書籍的 `locatorJson`。比照 `_handleZoneAction`
  /// （Issue 5）建立的相同分派模式。
  void _jumpToEpubLocator(String locatorJson) {
    if (_dispatchedIsFixedLayout == true) {
      EpubReaderView.jumpToLocator(_epubReaderViewKey, locatorJson);
    } else {
      FoliateEpubReaderView.jumpToLocator(_foliateEpubReaderViewKey, locatorJson);
    }
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
          _jumpToEpubLocator(entry.locatorJson);
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
    final latestProgress = format == BookFormat.epub
        ? (_epubPositionInfo?.progression ?? widget.bookProgress)
        : (_pdfPageInfo != null && _pdfPageInfo!.totalPages > 0
            ? (_pdfPageInfo!.pageIndex + 1) / _pdfPageInfo!.totalPages
            : widget.bookProgress);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => NotesBottomSheet(
        bookId: widget.bookId,
        bookTitle: widget.bookTitle,
        bookAuthor: widget.bookAuthor,
        bookProgress: latestProgress,
        bookmarksRepository: repository,
        currentPosition: positionContext,
        highlightsRepository: (format == BookFormat.epub && !_isFixedLayout) ||
                format == BookFormat.pdf
            ? widget.highlightsRepository
            : null,
        notesRepository: (format == BookFormat.epub && !_isFixedLayout) ||
                format == BookFormat.pdf
            ? widget.notesRepository
            : null,
        onAnnotationSelected: (item) {
          Navigator.of(context).pop();
          final locatorJson = item.highlight?.epubLocatorJson ?? item.note?.epubLocatorJson;
          final pdfPageIndex = item.highlight?.pdfPageIndex ?? item.note?.pdfPageIndex;
          if (locatorJson != null) {
            _jumpToEpubLocator(locatorJson);
          } else if (pdfPageIndex != null) {
            PdfReaderView.jumpToPage(_pdfReaderViewKey, pdfPageIndex);
          }
        },
        onAnnotationsChanged: format == BookFormat.pdf
            ? _reloadPdfAnnotationsAndSync
            : _reloadAnnotationsAndRefreshDecorations,
        onBookmarkSelected: (bookmark) {
          Navigator.of(context).pop();
          if (bookmark.epubLocatorJson != null) {
            _jumpToEpubLocator(bookmark.epubLocatorJson!);
          } else if (bookmark.pdfPageIndex != null) {
            PdfReaderView.jumpToPage(_pdfReaderViewKey, bookmark.pdfPageIndex!);
          }
          // epic-6-annotations Issue 4：FXL 書籤跳轉概念上等同換頁，套用與
          // EpubReaderView.onFixedLayoutPageTurn（見本檔案下方
          // _buildNativeView）相同的既有沉浸式閱讀慣例——一律強制收合，非
          // toggle 語意，不是另立新規則。
          if (_isFixedLayout) {
            setState(() => _chromeVisible = false);
          }
        },
      ),
    ).then((_) {
      // epic-6-annotations Issue 4：FXL 懸浮書籤按鈕的二態圖示快取
      // （_fxlBookmarks）與本 Bottom Sheet 內「🔖 書籤」分頁各自獨立載入
      // 自己的清單（見 _loadFxlBookmarks 說明），Bottom Sheet 關閉後主動
      // 重新整理一次，確保使用者在分頁裡新增/刪除書籤後，懸浮按鈕圖示不會
      // 停留在過期狀態。
      if (_isFixedLayout) _loadFxlBookmarks();
    });
  }

  void _handlePageRendered() {
    if (!mounted) return;
    setState(() => _state = _RenderState.rendered);
    // epic-6-annotations Issue 3：PDF 書籍開啟成功後載入既有劃線/備註並
    // 送給原生端渲染。與 EPUB 的觸發點（_handleLayoutResolved，見 Issue 2
    // Task 10 Step 7）刻意不同——PDF 沒有對應的版面解析回呼，本方法
    // （onPageRendered）是 PDF 開書成功的既有訊號，兩種格式共用同一個
    // _annotationsLoaded 旗標（單一書籍只會是其中一種格式，不會重複觸發）。
    if (detectBookFormat(widget.filePath) == BookFormat.pdf &&
        !_annotationsLoaded &&
        widget.highlightsRepository != null &&
        widget.notesRepository != null) {
      _annotationsLoaded = true;
      _reloadPdfAnnotationsAndSync();
    }
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
    if (info.isFixedLayout && widget.bookmarksRepository != null) {
      _loadFxlBookmarks();
    }
  }

  /// FoliateEpubReaderView（流式）專屬的 onLayoutResolved 處理。
  /// epic-17-epub-render-migration Issue 4 起，也設定
  /// `_autoDetectedWritingMode` 並重新計算 `_resolved`（比照
  /// `_handleLayoutResolved` 對應段落），讓「版面設定」按鈕能對流式書籍
  /// 生效。Issue 6 起新增目錄背景抓取（比照 `_handleLayoutResolved`
  /// 對應段落，改呼叫 `FoliateEpubReaderView.loadTableOfContents()`
  /// 而非 `EpubReaderView` 的版本）——不需要像 Readium 分支那樣額外檢查
  /// `!info.isFixedLayout`，因為本方法只會被 `FoliateEpubReaderView`
  /// （恆為流式）呼叫。**仍然刻意不**觸發
  /// `_reloadAnnotationsAndRefreshDecorations`／`_loadFxlBookmarks`——這兩
  /// 個呼叫對尚未掛載的 `EpubReaderView`/`_epubReaderViewKey` 雖然會靜默
  /// no-op、技術上無害，但會讓 `_annotationsLoaded` 被誤判為「已完成」，
  /// 使「筆記」按鈕看似可用卻永遠開出空清單/無法互動。劃線備註仍是
  /// Issue 8 的範圍。
  void _handleFoliateLayoutResolved(EpubLayoutInfo info) {
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
    if (_tocEntries.isEmpty && !_tocLoaded) {
      FoliateEpubReaderView.loadTableOfContents(_foliateEpubReaderViewKey)
          .then((entries) {
        if (!mounted) return;
        setState(() {
          _tocEntries = entries;
          _tocLoaded = true;
        });
      });
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

  void _handlePdfSelectionRectComputed(PdfSelectionInfo info) {
    if (!mounted) return;
    setState(() {
      _currentPdfSelection = info;
      _pendingPdfHighlightIdForSelection = null;
    });
  }

  void _handlePdfSelectionCanceled() {
    if (!mounted) return;
    setState(() {
      _currentPdfSelection = null;
      _pendingPdfHighlightIdForSelection = null;
    });
  }

  Future<void> _handlePdfHighlightStyleSelected(HighlightStyle style) async {
    final selection = _currentPdfSelection;
    final repository = widget.highlightsRepository;
    if (selection == null || repository == null) return;
    final id = await repository.insert(Highlight(
      bookId: widget.bookId,
      style: style,
      pdfPageIndex: selection.pageIndex,
      pdfRect: selection.rect,
    ));
    _pendingPdfHighlightIdForSelection = id;
    await _reloadPdfAnnotationsAndSync();
  }

  Future<void> _handlePdfNotePressed() async {
    final selection = _currentPdfSelection;
    final repository = widget.notesRepository;
    if (selection == null || repository == null) return;
    final text = await showNoteTextDialog(context, title: '新增備註');
    if (text == null) return;
    await repository.insert(Note(
      bookId: widget.bookId,
      text: text,
      pdfPageIndex: selection.pageIndex,
      pdfRect: selection.rect,
      highlightId: _pendingPdfHighlightIdForSelection,
    ));
    await _reloadPdfAnnotationsAndSync();
    if (!mounted) return;
    setState(() {
      _currentPdfSelection = null;
      _pendingPdfHighlightIdForSelection = null;
    });
  }

  /// 重新查詢本書全部劃線/備註並送給原生端重繪 Bitmap 疊加（PDF 版本，
  /// 比照 EPUB 的 [_reloadAnnotationsAndRefreshDecorations]）。共用同一組
  /// [_highlights]／[_notes] state 欄位——單一 ReaderScreen 會話只會載入
  /// 其中一種格式的書籍，不會同時混用。
  Future<void> _reloadPdfAnnotationsAndSync() async {
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
    _sendPdfAnnotationsToNative();
  }

  void _sendPdfAnnotationsToNative() {
    if (!mounted) return;
    final primaryColor = Theme.of(context).colorScheme.primary;
    final annotations = <PdfAnnotationDecoration>[
      for (final highlight in _highlights)
        if (highlight.pdfPageIndex != null && highlight.pdfRect != null)
          PdfAnnotationDecoration.forHighlight(
            pageIndex: highlight.pdfPageIndex!,
            rect: highlight.pdfRect!,
            tint: highlightStyleTint(highlight.style, primaryColor: primaryColor),
            isUnderline: highlight.style == HighlightStyle.underline,
          ),
      for (final note in _notes)
        if (note.highlightId == null && note.pdfPageIndex != null && note.pdfRect != null)
          PdfAnnotationDecoration.forNote(
            pageIndex: note.pdfPageIndex!,
            rect: note.pdfRect!,
            tint: noteOnlyTint.toARGB32(),
          ),
    ];
    PdfReaderView.refreshAnnotations(_pdfReaderViewKey, annotations);
  }

  // 浮動工具列估計高度／與選取範圍的間距，PDF 版本（比照 EPUB 的
  // _annotationToolbarHeight／_annotationToolbarGap 既有常數值，兩者刻意
  // 保持相同數值，故不重複宣告，直接複用）。

  /// PDF 版本的浮動工具列定位計算，邏輯與 EPUB 的 [_annotationToolbarTop]
  /// 完全相同（皆為「優先貼在選取範圍上方，空間不足時貼下方」），但參數
  /// 型別不同（[PdfSelectionInfo] 而非 [EpubSelectionInfo]），故獨立宣告
  /// 一份而非嘗試合併兩者呼叫端（Surgical Changes 原則：不更動 Issue 2
  /// 已驗證穩定的 [_annotationToolbarTop] 本體）。
  double _pdfAnnotationToolbarTop(PdfSelectionInfo selection, Size size) {
    // 【審查修正 Finding 1】此處 [size] 是整個 widget 尺寸，PAGE_FIT 模式下
    // 頁面常因長寬比與螢幕不同而產生 letterbox 留白，故改用相對整個
    // widget（含留白）換算的 [selection.widgetRect]，而非相對 bitmap
    // 內容範圍的 [selection.rect]（後者仍保留給持久化/重繪使用，見
    // PdfSelectionInfo 的欄位說明），避免工具列位置隨留白量偏移。
    final topAboveSelection =
        selection.widgetRect.top * size.height - _annotationToolbarHeight - _annotationToolbarGap;
    if (topAboveSelection >= 0) return topAboveSelection;
    final belowSelection = selection.widgetRect.bottom * size.height + _annotationToolbarGap;
    return belowSelection.clamp(0.0, size.height - _annotationToolbarHeight);
  }

  @override
  Widget build(BuildContext context) {
    final format = detectBookFormat(widget.filePath);
    // 方向偵測（spec.md「方向偵測契約」）：在 build() 中統一偵測，格式無關
    // 共用，不寫死在 PDF 專屬程式碼路徑裡——EPUB 分支（Issue 6）之後會消費
    // 同一個 isLandscape 值。
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    // 【實作偏離 plan-issue-7.md Task 4 逐字規格，記錄供未來維護者知悉】
    // 顯式標註 <dynamic>：新增 onPopInvokedWithResult 後，若不標註型別參數，
    // Dart 型別推論會依回呼閉包把 T 推成 Object（而非既有測試
    // `find.byType(PopScope)` 預期比對的 PopScope<dynamic>——generic class
    // 名稱單獨作為 Type 值時，未標註型別引數會推論為 <dynamic> 而非
    // <Object?>），導致既有測試（例如「進入手動裁切互動模式後，
    // PopScope.canPop 為 false」）的 find.byType(PopScope) 比對不到任何
    // widget 而失敗。顯式標註 <dynamic> 讓實際型別與既有測試預期的裸型別
    // 字面量一致，回歸零。
    return PopScope<dynamic>(
      // 手動裁切互動模式進行中時，返回鍵不應把整個 ReaderScreen 一併 pop
      // 掉——原生端裁切互動模式沒有使用者手勢可以主動觸發離開（見 spec.md
      // 第 123 行「不會主動由使用者手勢觸發」），這裡單純吞掉返回鍵手勢，
      // 讓使用者留在裁切模式，必須透過畫面上的原生確認按鈕才能離開（審查
      // 意見 2.1(b)：避免誤觸返回鍵導致整個閱讀器被意外關閉；刻意不在此
      // 新增「取消並還原」語意，維持 spec.md 已鎖定的簡化狀態機決策）。
      canPop: !_cropEditModeActive,
      // pop 動作啟動當下（早於退場轉場動畫、更早於 PlatformView.dispose()）
      // 通知原生端立即停止攔截音量鍵（epic-7-interaction Issue 7，收斂
      // 轉場動畫期間的攔截延遲釋放窗口，見 ReaderViewAttachmentTracker
      // 類別註解）。canPop 為 false（裁切模式攔截返回鍵）時 didPop 為
      // false，此時閱讀器仍在使用中，不應釋放攔截，故只在 didPop 為 true
      // 時才呼叫。
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          _volumeKeyChannel.invokeMethod('notifyLeavingReader');
        }
      },
      child: Scaffold(
        // extendBodyBehindAppBar：搭配 _buildBody() 內的 Padding+SafeArea(top:
        // false) 改造（審查修正），讓 body 版面約束不受 AppBar 顯示/隱藏
        // 影響，AppBar 只是視覺疊加、不觸發 body 底下 PlatformView 的
        // resize。【最終審查修正】這只解決了 AppBar 這一半的問題——頁尾
        // （ReaderFooter／_buildEpubFooter，見 _buildBody() 內同樣受
        // _chromeVisible 控制的 in-flow Column 子項）顯示/隱藏仍會改變
        // body 實際配置高度，PlatformView 仍會 resize。PDF 目前僅是微幅
        // 重繪、可接受；但這代表本機制尚未完全解決 resize 問題，Issue 6
        // （EPUB 流式、Readium WebView）若要沿用同一套 _chromeVisible／
        // _buildBody() 基礎設施，必須先把頁尾也改為浮動疊加層（而非
        // in-flow），否則頁尾切換仍會觸發 WebView 整本重新分頁。
        extendBodyBehindAppBar: true,
        appBar: (_isFixedLayout || !_chromeVisible)
            ? null // 固定版面（如漫畫）或沉浸模式已收起介面時隱藏 Scaffold AppBar
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
        final pdfSelection = _currentPdfSelection;
        return Stack(
          children: [
            if (_resolved != null &&
                (format != BookFormat.epub || _dispatchedIsFixedLayout != null))
              _buildNativeView(format, isLandscape),
            if (_isFixedLayout && _chromeVisible)
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
            if (_isFixedLayout && _chromeVisible)
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
            if (_isFixedLayout &&
                _chromeVisible &&
                widget.bookmarksRepository != null)
              Positioned(
                top: 128,
                right: 16,
                child: ClipOval(
                  child: Container(
                    color: Colors.black54,
                    child: IconButton(
                      key: const Key('reader_fixed_layout_bookmark_toggle_button'),
                      icon: Icon(
                        _fxlBookmarkAtCurrentPosition != null
                            ? Icons.star
                            : Icons.star_border,
                        color: Colors.white,
                      ),
                      tooltip: _fxlBookmarkAtCurrentPosition != null
                          ? '已加入此頁書籤'
                          : '加入此頁書籤',
                      onPressed:
                          _epubPositionInfo == null ? null : _toggleFxlBookmark,
                    ),
                  ),
                ),
              ),
            if (_isFixedLayout &&
                _chromeVisible &&
                widget.bookmarksRepository != null)
              Positioned(
                top: 72,
                right: 16,
                child: ClipOval(
                  child: Container(
                    color: Colors.black54,
                    child: IconButton(
                      key: const Key('reader_fixed_layout_notes_button'),
                      icon: const Icon(Icons.bookmarks, color: Colors.white),
                      tooltip: '筆記',
                      onPressed: _epubPositionInfo == null
                          ? null
                          : () => _openNotesSheet(BookFormat.epub),
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
            if (pdfSelection != null)
              Positioned(
                // 同上（見 _pdfAnnotationToolbarTop 註解）：改用相對整個
                // widget 尺寸的 widgetRect，避免 letterbox 留白造成偏移。
                left: (pdfSelection.widgetRect.left * size.width).clamp(0.0, size.width),
                top: _pdfAnnotationToolbarTop(pdfSelection, size),
                child: AnnotationToolbar(
                  onStyleSelected: _handlePdfHighlightStyleSelected,
                  onNotePressed: _handlePdfNotePressed,
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

    return Padding(
      // extendBodyBehindAppBar（見上方 Scaffold 建構）開啟後，Scaffold 會
      // 依 AppBar 是否顯示動態調整 MediaQuery.padding.top；若直接讓
      // SafeArea 消費這個值，body 內容仍會隨沉浸模式切換改變可用高度，
      // 等於沒解決 AppBar 那一半的 PlatformView resize 問題（審查修正）。
      // 改用不受 AppBar 影響、只反映裝置實際安全區域（狀態列/瀏海）的
      // MediaQuery.viewPadding.top，SafeArea 本身關閉頂端判斷（top:
      // false），讓 AppBar 顯示/隱藏不再改變 body 高度。頁尾（下方
      // ReaderFooter／_buildEpubFooter）仍是 in-flow 子項，其顯示/隱藏
      // 仍會改變 body 實際高度——這是另一個尚未解決的 resize 來源，見上方
      // Scaffold 建構處的完整說明。
      padding: EdgeInsets.only(top: MediaQuery.of(context).viewPadding.top),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(child: body),
            // 頁尾佔用固定版面空間、擠壓上方閱讀區域高度（比照
            // prototype/index.html 的 .reader-footer 既有設計，非浮動疊加
            // 層）。顯示/隱藏由 showFooter 控制（epic-5-toc-pagination
            // Issue 5），false 時整個 if 條件不成立、完全不佔用版面空間。
            if (format == BookFormat.pdf &&
                _pdfPageInfo != null &&
                (_resolved?.showFooter ?? true) &&
                _chromeVisible)
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
                _resolved!.showFooter &&
                _chromeVisible)
              _buildEpubFooter(_resolved!, _totalCharacterCount!),
            if (format == BookFormat.epub &&
                _dispatchedIsFixedLayout == false &&
                _epubPositionInfo?.totalPages != null &&
                _resolved != null &&
                _resolved!.showFooter &&
                _chromeVisible)
              _buildFoliateEpubFooter(_epubPositionInfo!),
          ],
        ),
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

  /// 流式 EPUB（FoliateEpubReaderView）頁尾（epic-17-epub-render-migration
  /// Issue 6）：直接使用原生端 relocate 事件回報的 pageIndex／totalPages
  /// （foliate-js SectionProgress.getProgress() 的 location.current／
  /// location.total，近似頁碼概念，非精確渲染頁數，見 spec.md「頁碼
  /// 估算」）——與 _buildEpubFooter（Readium 遺留路徑，依全書字元數估算
  /// 頁數，post-epic-17 對流式書籍已是死路徑，見 plans/plan-issue-5.md
  /// 對 onZoneTapped 的相同結論）刻意不同，不重用其估算邏輯；本 widget
  /// 完全不呼叫任何字數統計（不送出 totalCharacterCount）。pageIndex 為
  /// 0-indexed（比照原生端既有慣例），ReaderFooter 要求 1-indexed，此處
  /// +1 換算。onPageChanged 透過既有 jumpToProgression（Issue 5）換算
  /// 目標頁對應的全書進度比例，與 _buildEpubFooter 的 onPageChanged 作法
  /// 相同（近似值，非精確反解頁碼）。
  Widget _buildFoliateEpubFooter(EpubPositionInfo info) {
    final totalPages = info.totalPages!;
    final currentPage = ((info.pageIndex ?? 0) + 1).clamp(1, totalPages);
    return ReaderFooter(
      currentPage: currentPage,
      totalPages: totalPages,
      onPageChanged: (page1Indexed) {
        final progression =
            totalPages > 0 ? (page1Indexed - 1) / totalPages : 0.0;
        FoliateEpubReaderView.jumpToProgression(
            _foliateEpubReaderViewKey, progression);
      },
    );
  }

  Widget _buildNativeView(BookFormat format, bool isLandscape) {
    final resolved = _resolved!;
    switch (format) {
      case BookFormat.epub:
        if (!_dispatchedIsFixedLayout!) {
          return FoliateEpubReaderView(
            key: _foliateEpubReaderViewKey,
            filePath: widget.filePath,
            onPageRendered: _handlePageRendered,
            onError: _handleError,
            onLayoutResolved: _handleFoliateLayoutResolved,
            writingMode: resolved.writingMode,
            pageTurnMode: resolved.pageTurnMode,
            fontFamily: resolved.fontFamily,
            fontSize: resolved.fontSize,
            fontWeight: resolved.fontWeight,
            lineHeight: resolved.lineHeight,
            paragraphSpacing: resolved.paragraphSpacing,
            pageMargins: resolved.pageMargins,
            textAlign: resolved.textAlign,
            publisherStyles: resolved.publisherStyles,
            navZoneActions: resolved.navZoneActions,
            onZoneAction: _handleZoneAction,
            showNavZoneDebugOverlay: resolved.showNavZoneDebugOverlay,
            initialLocatorJson: _initialPosition?.epubLocatorJson,
            onLocatorChanged: (info) {
              if (!mounted) return;
              setState(() => _epubPositionInfo = info);
            },
          );
        }
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
          navZoneActions: resolved.navZoneActions,
          onZoneAction: _handleZoneAction,
          showNavZoneDebugOverlay: resolved.showNavZoneDebugOverlay,
          onZoneTapped: (index) => _handleZoneAction(resolved.navZoneActions[index]),
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
          onSelectionRectComputed: _handlePdfSelectionRectComputed,
          onSelectionCanceled: _handlePdfSelectionCanceled,
          navZoneActions: resolved.navZoneActions,
          onZoneAction: _handleZoneAction,
          showNavZoneDebugOverlay: resolved.showNavZoneDebugOverlay,
        );
      case BookFormat.unknown:
        return const SizedBox.shrink();
    }
  }

  /// 熱區動作統一分派入口（epic-7-interaction Issue 4，Issue 5 擴充 EPUB
  /// FXL 分支，epic-17-epub-render-migration Issue 5 擴充流式 EPUB 的
  /// `FoliateEpubReaderView` 分支）：`previousPage`/`nextPage` 呼叫目前
  /// 格式對應的既有換頁方法；`menu` 切換 [_chromeVisible]（沉浸模式）；
  /// `none` 不做事。**`previousPage`/`nextPage` 刻意不影響
  /// [_chromeVisible]**（design.md 決策 #14）。EPUB 分支的 `previousPage`/
  /// `nextPage` 依 `_dispatchedIsFixedLayout` 分派：`true`（FXL，
  /// `EpubReaderView`）呼叫 `EpubReaderView.previousPage`/`nextPage`；
  /// `false`（流式，`FoliateEpubReaderView`）呼叫
  /// `FoliateEpubReaderView.previousPage`/`nextPage`——兩者的 3×3 熱區皆是
  /// Dart 端 `Stack` 疊加層，`onTap` 直接回呼 [onZoneAction]（見
  /// `_buildNativeView()` 接線），不經過原生端判讀。`EpubReaderView` 既有的
  /// `onZoneTapped`（cellIndex 回呼）是 epic-17-epub-render-migration 之前
  /// 遺留的流式 EPUB via Readium 機制（原生 `InputListener` 座標換算），
  /// post-epic-17 的分派邏輯下流式書籍一律改建構 `FoliateEpubReaderView`，
  /// 這條舊路徑理論上不再被觸發，保留是避免不必要地改動
  /// `EpubReaderView.kt`（本工單範圍外，見 issues.md Issue 5 描述「原生端
  /// FoliateEpubReaderView.kt 完全不需要移植 NavZoneHitTester.cellIndex()
  /// 或 InputListener 註冊邏輯」）。原生端 `MainActivity.dispatchKeyEvent()`
  /// 攔截音量鍵後的回呼（epic-7-interaction Issue 7）：方向固定映射，不
  /// 查詢 `_resolved!.navZoneActions`（design.md 決策 #19）——`up` 一律
  /// 上一頁、`down` 一律下一頁。
  Future<void> _handleVolumeKeyCall(MethodCall call) async {
    if (call.method != 'onVolumeKey') return;
    final args = call.arguments as Map<Object?, Object?>;
    switch (args['direction'] as String?) {
      case 'up':
        _handleZoneAction(ZoneAction.previousPage);
        break;
      case 'down':
        _handleZoneAction(ZoneAction.nextPage);
        break;
    }
  }

  void _handleZoneAction(ZoneAction action) {
    final format = detectBookFormat(widget.filePath);
    switch (action) {
      case ZoneAction.previousPage:
        if (format == BookFormat.pdf) {
          PdfReaderView.previousPage(_pdfReaderViewKey);
        } else if (format == BookFormat.epub) {
          if (_dispatchedIsFixedLayout == true) {
            EpubReaderView.previousPage(_epubReaderViewKey);
          } else {
            FoliateEpubReaderView.previousPage(_foliateEpubReaderViewKey);
          }
        }
        break;
      case ZoneAction.nextPage:
        if (format == BookFormat.pdf) {
          PdfReaderView.nextPage(_pdfReaderViewKey);
        } else if (format == BookFormat.epub) {
          if (_dispatchedIsFixedLayout == true) {
            EpubReaderView.nextPage(_epubReaderViewKey);
          } else {
            FoliateEpubReaderView.nextPage(_foliateEpubReaderViewKey);
          }
        }
        break;
      case ZoneAction.menu:
        setState(() => _chromeVisible = !_chromeVisible);
        break;
      case ZoneAction.none:
        break;
    }
  }
}
