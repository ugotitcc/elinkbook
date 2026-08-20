import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../reader/annotation_list_item.dart';
import '../reader/book_format.dart';
import '../reader/bookmark.dart';
import '../reader/bookmark_position_context.dart';
import '../reader/bookmark_toggle.dart' as bookmark_toggle;
import '../reader/bookmarks_repository.dart';
import '../reader/book_reader_prefs.dart';
import '../reader/custom_font.dart';
import '../reader/custom_fonts_repository.dart';
import '../reader/epub_decoration.dart';
import '../reader/epub_position_info.dart';
import '../reader/epub_selection_info.dart';
import '../reader/foliate_reader_view.dart';
import '../library/library_repository.dart';
import '../reader/highlight.dart';
import '../reader/highlight_style.dart';
import '../reader/highlights_repository.dart';
import '../reader/note.dart';
import '../reader/notes_repository.dart';
import '../reader/pdf_annotation_decoration.dart';
import '../reader/pdf_search_match.dart';
import '../reader/pdf_search_state.dart';

import '../reader/pdf_page_info.dart';
import '../reader/pdf_crop_frame_overlay.dart';
import '../reader/pdf_crop_mode.dart';
import '../reader/pdf_crop_rect.dart';
import '../reader/pdf_reader_view.dart';
import '../reader/pdf_toc_item.dart';
import '../reader/pdf_toc_navigator.dart';
import '../reader/pdf_selection_info.dart';
import '../reader/reading_position.dart';
import '../reader/reader_prefs_manager.dart';
import '../reader/toc_entry.dart';
import '../reader/toc_navigator.dart';
import '../reader/resolved_preferences.dart';
import '../reader/screen_orientation_setting.dart';
import '../reader/writing_mode.dart';
import '../reader/zone_action.dart';
import '../sync/sync_checkpoint_trigger.dart';
import 'annotation_toolbar.dart';
import 'note_edit_dialog.dart';
import 'notes_bottom_sheet.dart';
import 'fxl_settings_sheet.dart';
import 'layout_preset_book_picker_screen.dart';
import 'layout_preset_name_dialog.dart';
import 'pdf_settings_sheet.dart';
import '../reader/book_reader_prefs_repository.dart';
import '../reader/layout_preset.dart';
import '../reader/layout_preset_repository.dart';
import 'reader_footer.dart';
import 'reader_settings_sheet.dart';
import 'toc_bottom_sheet.dart';
import 'pdf_search_panel.dart';
import 'pdf_thumbnail_panel.dart';

/// 音量鍵事件頻道（epic-7-interaction Issue 7）：原生 `MainActivity.
/// dispatchKeyEvent()` 攔截音量鍵後呼叫 `onVolumeKey`；`_handleVolumeKeyCall`
/// 轉呼叫既有的 `_handleZoneAction`。既有 `PopScope` 的
/// `onPopInvokedWithResult` 於 pop 動作啟動當下呼叫 `notifyLeavingReader`，
/// 讓原生端立即停止攔截（早於退場轉場動畫、更早於 dispose()，見
/// docs/epics/epic-7-interaction/spec.md「新增音量鍵頻道」）。
const _volumeKeyChannel = MethodChannel('elinkbook/volume_key');

/// 全螢幕模式頻道（epic-19-shelf-reading-enhance Issue 1，見 ADR 0015）：
/// 呼叫原生 WindowInsetsControllerCompat 隱藏/顯示系統狀態列與導覽列，
/// 不經過 Flutter SystemChrome（本專案目前 targetSdk 下已知失效）。
const _fullscreenChannel = MethodChannel('elinkbook/fullscreen');

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
  /// `_dispatchedIsFixedLayout` 直接沿用這個 `null` 值。EPUB 一律建構
  /// [FoliateReaderView]（epic-20 Issue 2 起不再依此欄位分派 widget，
  /// 只驅動 FXL 專屬 UI/chrome 語意），非 EPUB 格式完全不受此欄位影響。
  final bool? isFixedLayout;

  /// 供 [isFixedLayout] 為 `null` 時呼叫 [LibraryRepository.detectAndCacheEpubLayout]
  /// 使用。刻意為可選參數——比照 [bookmarksRepository] 既有慣例，避免既有
  /// 大量測試呼叫端需要逐一補上這個參數。
  final LibraryRepository? libraryRepository;

  /// 自訂字型清單的資料存取層（epic-14-system-settings Issue 2）。刻意為
  /// 可選參數——比照 [bookmarksRepository] 既有慣例，未提供時字型選單僅
  /// 顯示內建 5 款，行為等同本 Issue 之前，零回歸。
  final CustomFontsRepository? customFontsRepository;

  /// 版面設定預設集的資料存取層（epic-28-reader-settings-enhancements
  /// Issue 3）。刻意為可選參數——比照 [customFontsRepository] 既有慣例，
  /// 未提供時預設集相關按鈕點擊無效果（callback 內提早 return），行為
  /// 等同本 Issue 之前，零回歸。
  final LayoutPresetRepository? layoutPresetRepository;

  /// 供「書籍設定複製」（讀取來源書籍目前的版面偏好設定）與「套用預設集/
  /// 複製設定到目前書籍以外的其他書籍」（批次寫入）使用，與 [prefsManager]
  /// 底層共用同一個 `BookReaderPrefsRepository` 實例（見 main.dart 建構
  /// 處）。刻意為可選參數，理由同 [layoutPresetRepository]。
  final BookReaderPrefsRepository? bookReaderPrefsRepository;

  /// Checkpoint 觸發器（epic-8-sync Issue 6）。刻意為可選參數——比照
  /// [bookmarksRepository] 既有慣例，未提供時離開閱讀畫面／背景化／閒置
  /// 計時器皆不觸發任何同步動作，行為等同本 Issue 之前，零回歸。
  final SyncCheckpointTrigger? syncCheckpointTrigger;

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
    this.customFontsRepository,
    this.layoutPresetRepository,
    this.bookReaderPrefsRepository,
    this.syncCheckpointTrigger,
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

  /// 供測試（Issue 4 範圍：書籤 toggle 邏輯已完成，對應 FAB 按鈕留給
  /// Issue 8）安全呼叫 [_ReaderScreenState._togglePdfBookmark] 的強型別
  /// static helper，比照 [triggerZoneAction] 既有模式。[key] 對應的 State
  /// 若尚未掛載，靜默忽略。
  static void togglePdfBookmark(GlobalKey<State<ReaderScreen>> key) {
    final state = key.currentState;
    if (state is _ReaderScreenState) {
      unawaited(state._togglePdfBookmark());
    }
  }

  /// 供測試（Issue 5 範圍：目錄載入/跳轉邏輯已完成，對應 FAB 按鈕留給
  /// Issue 8）安全呼叫 [_ReaderScreenState._openPdfToc] 的強型別 static
  /// helper，比照 [togglePdfBookmark] 既有模式。[key] 對應的 State 若尚未
  /// 掛載，靜默忽略。
  static void openPdfToc(GlobalKey<State<ReaderScreen>> key) {
    final state = key.currentState;
    if (state is _ReaderScreenState) {
      state._openPdfToc();
    }
  }

  /// 供真機整合測試讀取目前書籍目錄（epic-11-multi-format-reader
  /// Issue 4），比照既有 [triggerZoneAction] 強型別 static helper 模式。
  /// [key] 對應的 State 若尚未掛載，回傳空清單。
  static Future<List<TocEntry>> loadTableOfContentsForTest(
    GlobalKey<State<ReaderScreen>> key,
  ) async {
    final state = key.currentState;
    if (state is! _ReaderScreenState) return const [];
    return FoliateReaderView.loadTableOfContents(state._foliateEpubReaderViewKey);
  }
}

enum _RenderState { loading, rendered, error }

class _ReaderScreenState extends State<ReaderScreen> with WidgetsBindingObserver {
  // PDF 目錄 Bottom Sheet 不需要字元數快取（頁碼在解析大綱時已知），
  // 但 TocBottomSheet 的建構子要求 ValueListenable<int?> 參數。
  // 共用同一個靜態實例，避免每次開啟都新建 ValueNotifier（Minor #3 修正）。
  static final _pdfDummyCharacterCountNotifier = ValueNotifier<int?>(null);

  // ── PDF 內文搜尋狀態（epic-24 Issue 6）──
  final _pdfSearchStateNotifier = ValueNotifier<PdfSearchState>(const PdfSearchState.initial());
  List<PdfSearchMatch> _pdfSearchMatches = const [];
  int _pdfSearchRequestId = 0;

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
  // 自訂字型清單快取（epic-14-system-settings Issue 2），開書時載入一次，
  // 比照既有 _fxlBookmarks／_highlights 等一次性載入快取模式。
  List<CustomFont> _customFonts = [];
  // 版面設定預設集清單快取（epic-28-reader-settings-enhancements
  // Issue 3），開書時載入一次，比照既有 _customFonts 一次性載入快取模式；
  // 另存/覆蓋/刪除完成後重新載入。
  List<LayoutPreset> _layoutPresets = [];
  // 自訂字型清單是否已完成載入判斷（epic-14-system-settings Issue 3）：
  // 未提供 customFontsRepository 時直接視為已完成（沒有東西要等，零回歸）；
  // 提供時初始為 false，_loadCustomFonts() 完成（不論成功或失敗）後才設為
  // true。_buildBody 的 EPUB gating 條件依此延後 FoliateReaderView 的
  // 建構時機，避免 late final _initialIndexUri（內含 buildFontFaceCss()
  // 產生的自訂字型 @font-face 宣告）在清單查詢完成前就已計算定案、之後
  // 永遠不會重新產生的競態（見本計畫 Global Constraints）。
  late bool _customFontsLoaded = widget.customFontsRepository == null;
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
  // 目錄樹狀結構快取（Epic 5 Issue 4），由 onLayoutResolved 觸發一次性
  // 背景抓取（見 _handleLayoutResolved）。樹狀結構不隨版面設定變動，開書
  // 期間只抓取一次，不需要每次版面參數變動都重新請求。
  List<TocEntry> _tocEntries = const [];
  List<PdfTocItem> _pdfTocEntries = const [];
  bool _pdfTocLoaded = false;
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
  String? _pendingHighlightIdForSelection;
  // PDF 劃線／備註目前選取狀態（epic-6-annotations Issue 3），由原生端
  // onSelectionRectComputed 回報；非 null 時於 body Stack 顯示
  // AnnotationToolbar。與 EPUB 的 _currentSelection 並存但不會同時非
  // null（同一次只會開啟一種格式的書籍）。
  PdfSelectionInfo? _currentPdfSelection;
  String? _pendingPdfHighlightIdForSelection;
  // 供 TocBottomSheet 訂閱、在已開啟的目錄畫面即時反映全書字元數背景計算
  // 完成事件（spec.md「目錄模組」載入中狀態決策）。
  final _totalCharacterCountNotifier = ValueNotifier<int?>(null);
  // 開書時讀到的既有位置記錄（若有），只在 initState 賦值一次，之後
  // 不變——僅用於 _buildNativeView() 建構 EpubReaderView/PdfReaderView
  // 時傳入 initialLocatorJson/initialPageIndex 這兩個一次性開書起始值。
  ReadingPosition? _initialPosition;
  // 用於呼叫 PdfReaderView.jumpToPage(key, pageIndex) 這個強型別 static
  // helper（審查修正，見 Task 2 Step 4——不使用 as dynamic 跨 State 私有
  // 邊界呼叫，避免 release 混淆／tree-shaking 風險）。
  final _pdfReaderViewKey = GlobalKey<State<PdfReaderView>>();
  // 用於呼叫 FoliateReaderView 的強型別 static helper。epic-20 Issue 2
  // 起，所有 EPUB（FXL／流式）皆統一建構 FoliateReaderView（見
  // _resolveEpubEngineDispatch／_buildBody），此 key 已是實際掛載的唯一
  // EPUB widget key；_epubReaderViewKey（Readium）僅保留供 Issue 5 清理前
  // 過渡期間的舊程式碼路徑相容，不再被任何分派邏輯建構。
  final _foliateEpubReaderViewKey = GlobalKey<State<FoliateReaderView>>();
  // 記錄上一次實際套用給系統的螢幕方向，避免在偏好設定頻繁變動時（例如
  // 拖曳滑桿）重複呼叫 SystemChrome.setPreferredOrientations。
  ScreenOrientationSetting? _lastAppliedOrientation;
  // 記錄上一次實際套用給系統的全螢幕模式狀態，避免偏好設定頻繁變動時
  // 重複呼叫 elinkbook/fullscreen 頻道；App 從背景恢復時會被強制清空
  // （見 didChangeAppLifecycleState），確保系統列真的被 OS 重新顯示時
  // 能重新套用。
  bool? _lastAppliedFullscreen;
  // EPUB 版面判斷結果：true=FXL、false=流式、null=尚未解析完成（既有書籍
  // 偵測進行中，畫面維持載入中指示器）。epic-17-epub-render-migration
  // Issue 3 引入當下曾用來分派「建構 EpubReaderView 還是
  // FoliateReaderView」；epic-20 Issue 2 起兩種情況一律建構
  // FoliateReaderView（見 _buildBody），本欄位已不再決定要建構哪個
  // widget，改為單純的 FXL／流式版面旗標，用於 UI 分支（例如 FXL 懸浮
  // 控制項顯示邏輯、跳過流式限定功能）。與既有 _isFixedLayout
  // （foliate-js 開書後才回報的執行期狀態，驅動 FXL 懸浮控制項/AppBar
  // 顯示邏輯）是兩個不同概念，互不影響——見
  // docs/epics/epic-17-epub-render-migration/spec.md「已知限制」。
  bool? _dispatchedIsFixedLayout;

  // epic-8-sync Issue 6：閱讀中每 5 分鐘觸發一次 checkpoint 的週期性
  // 計時器。單純的週期性 Timer（不判斷使用者是否真的有互動），見
  // plan-issue-6.md Global Constraints 的 YAGNI 說明。未提供
  // syncCheckpointTrigger 時完全不建立（見 initState），零額外開銷。
  Timer? _syncCheckpointTimer;

  /// 開書載入逾時哨兵（epic-18-reader-device-qa Issue 33，真機使用回報：
  /// iReader Ocean 4 Plus 開啟書籍時畫面永遠停在載入指示器，5 個推測根因
  /// 皆無真機診斷資料佐證）。單次 Timer，_handlePageRendered()／
  /// _handleError() 觸發時皆會取消（不論成功或失敗都不需要再等）；
  /// 30 秒後若仍是 loading 狀態，代表底層渲染引擎（PdfRenderer／
  /// FoliateReaderView 的 WebView）從未回報任何結果，主動切換為錯誤
  /// 畫面，避免使用者永遠面對轉圈圈、投訴無門（見上方 Issue 33 的
  /// _globalErrorCaptureJs 診斷能力補強說明——這是「連 JS 例外都沒有拋出」
  /// 這種更極端情況的最後一道防線）。原始值為 12 秒（epic-18-reader-device-qa
  /// Issue 33 的原始分析報告建議值，非嚴謹量測結果）；
  /// epic-27-reader-device-compat Issue 2 依 Mobiscribe WAVE 真機回報
  /// 「慢速裝置＋大型 EPUB 組合下 12 秒容易誤判逾時、需反覆重試才能開書
  /// 成功」調整為 30 秒（2026-08-13 使用者於診斷對話中確認此目標值，完整
  /// 診斷見 docs/epics/epic-27-reader-device-compat/reviews/bugfix-repro.md）。
  Timer? _openBookTimeoutTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _volumeKeyChannel.setMethodCallHandler(_handleVolumeKeyCall);
    _resolveEpubEngineDispatch();
    _loadCustomFonts();
    _loadLayoutPresets();
    final syncCheckpointTrigger = widget.syncCheckpointTrigger;
    if (syncCheckpointTrigger != null) {
      _syncCheckpointTimer = Timer.periodic(
        const Duration(minutes: 5),
        (_) => syncCheckpointTrigger.trigger(),
      );
    }
    _openBookTimeoutTimer = Timer(
      const Duration(seconds: 30),
      _handleOpenBookTimeout,
    );
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
      _applySystemUiMode();
    });
  }

  /// 解析 `_dispatchedIsFixedLayout`（EPUB 的 FXL/流式 UI 語意判斷，epic-17
  /// Issue 3 引入；epic-20 Issue 2 起不再決定要建構哪個 widget——EPUB 一律
  /// 建構 [FoliateReaderView]，本方法只決定單頁/雙頁等 UI/chrome 語意）。
  /// `widget.isFixedLayout` 非 null 時直接採用；為 null（既有書籍尚未
  /// 判斷過）時，若提供 [ReaderScreen.libraryRepository]則非同步呼叫
  /// `detectAndCacheEpubLayout()` 判斷並回寫資料庫，期間 `_dispatchedIsFixedLayout`
  /// 維持 null（畫面顯示載入中指示器，見 _buildBody 的 gating 條件）；未
  /// 提供時同步退回既有行為（`_dispatchedIsFixedLayout` 視為 true），確保
  /// 既有測試呼叫端零回歸。非 EPUB 格式完全不受影響（`_dispatchedIsFixedLayout`
  /// 維持 null 但 `_buildBody` 的 gating 條件只在 format == epub 時才要求
  /// 它非 null）。
  void _resolveEpubEngineDispatch() {
    _dispatchedIsFixedLayout = widget.isFixedLayout;
    if (_dispatchedIsFixedLayout != null) {
      // 當使用者透過「強制 FXL」設定 isFixedLayout=true 時，
      // 同步設定 _isFixedLayout 確保所有 FXL chrome（AppBar 隱藏、
      // 懸浮設定按鈕等）正確顯示，不受 native view 異步回報覆蓋。
      if (_dispatchedIsFixedLayout == true) {
        _isFixedLayout = true;
      }
      return;
    }
    final format = detectBookFormat(widget.filePath);
    if (format == BookFormat.azw3) {
      // KF8 目前沒有對應 EPUB detectAndCacheEpubLayout() 的執行期重新偵測
      // 手段（容器格式不同，不能沿用 EPUB 的 OPF/CSS 解析器）。isFixedLayout
      // 為 null 時（多為匯入階段 metadata 擷取失敗的既有書籍），防禦性視為
      // false（reflowable，絕大多數 AZW3 檔案的常態）而非讓其永遠停留
      // null——後者會讓 _buildBody 的 gating 條件永遠等不到非 null 值，
      // FoliateReaderView 永遠無法建構，書籍完全無法開啟（epic-11 Issue 2
      // 程式碼審查 C2）。
      _dispatchedIsFixedLayout = false;
      return;
    }
    if (format == BookFormat.cbz) {
      // CBZ 恆為固定版面（無流式變體，spec.md「CBZ 支援」），
      // Book.isFixedLayout 理論上匯入時必定已寫入 true
      // （book_import_service_impl.dart），此處防禦性補上與上方 azw3
      // 分支相同邏輯的 null-safety 修正（比照該分支修復的 epic-11 Issue 2
      // C2 教訓，避免任何未來邊界情況下 _dispatchedIsFixedLayout 永遠
      // 停留 null 導致 FoliateReaderView 永遠無法建構）。與 azw3 分支
      // 不同之處僅在預設值——CBZ 沒有 reflowable 變體，防禦性預設為
      // `true`，非 azw3 的 `false`（epic-11 Issue 3 程式碼審查 Important
      // #1：此分支原計畫已寫好，實作階段遺漏未落地）。
      _dispatchedIsFixedLayout = true;
      return;
    }
    if (format == BookFormat.txt) {
      // TXT 合成後恆為流式（無 FXL 變體，spec.md「TXT／Markdown 合成書籍
      // 結構」），Book.isFixedLayout 理論上匯入時必定已寫入 false
      // （book_import_service_impl.dart），此處防禦性補上與上方
      // azw3/cbz 分支相同邏輯的 null-safety 修正（比照 Issue 2 C2／
      // Issue 3 Important #1 的既有教訓，避免任何未來邊界情況下
      // _dispatchedIsFixedLayout 永遠停留 null 導致 FoliateReaderView
      // 永遠無法建構）。
      _dispatchedIsFixedLayout = false;
      return;
    }
    if (format == BookFormat.md) {
      // MD 合成後恆為流式（無 FXL 變體，spec.md「TXT／Markdown 合成書籍
      // 結構」），Book.isFixedLayout 理論上匯入時必定已寫入 false
      // （book_import_service_impl.dart），此處防禦性補上與上方
      // azw3/cbz/txt 分支相同邏輯的 null-safety 修正（比照 Issue 2 C2／
      // Issue 3 Important #1／Issue 4 的既有教訓）。
      _dispatchedIsFixedLayout = false;
      return;
    }
    if (format != BookFormat.epub) return;
    final repository = widget.libraryRepository;
    if (repository == null) {
      // 既有測試/呼叫端未提供 libraryRepository 時，退回 Issue 3 之前的
      // 既有行為——_dispatchedIsFixedLayout 一律視為 true，零回歸（EPUB
      // 一律建構 FoliateReaderView，此處只影響 FXL 專屬 UI/chrome
      // 語意，不影響要建構哪個 widget；見
      // docs/epics/epic-17-epub-render-migration/spec.md「已知限制」）。
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
    _syncCheckpointTimer?.cancel();
    _openBookTimeoutTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _volumeKeyChannel.setMethodCallHandler(null);
    _pdfSearchStateNotifier.dispose();
    // 離開閱讀畫面時觸發一次位置寫入（spec.md「本機閱讀位置記憶」寫入
    // 時機之一）。不 await——dispose() 是同步方法，且這是離開畫面前的
    // 最後一次呼叫，不需要等待其完成，比照既有 _handlePrefsChanged 不
    // await saveBookPrefs 的既有慣例。
    _writeCurrentPosition();
    // epic-8-sync Issue 6（spec.md「同步引擎」checkpoint 觸發來源之
    // 「書籍切換」）：離開閱讀畫面視為一次書籍切換，觸發一次 checkpoint。
    // 排在 _writeCurrentPosition() 之後，讓剛寫入的最新閱讀位置有較高
    // 機率被這次 checkpoint 一併判定為待推送——但兩者皆是 fire-and-
    // forget（不 await），呼叫順序並不「保證」上一行的 SQLite 寫入已經
    // 真正落地；即使極端情況下寫入尚未完成，也只是延後到下一次任何
    // checkpoint 才會被推送，不會遺失資料（審查意見 Important #1，
    // 2026-08-04 `/superpowers:requesting-code-review`）。不 await，理由
    // 同上一行 _writeCurrentPosition()，dispose() 是同步方法；未登入或
    // 已有 checkpoint 執行中時 SyncCheckpointTrigger.trigger() 內部會
    // 直接放棄，不會拋出例外。
    widget.syncCheckpointTrigger?.trigger();
    // 還原系統預設（允許自由旋轉），不論進入閱讀器時鎖定了哪個角度，比照
    // 音量鍵離開閱讀介面後恢復正常系統音量控制的既有處理原則，避免鎖定
    // 狀態外溢到書架等其他畫面。
    SystemChrome.setPreferredOrientations(const []);
    // 全螢幕模式離開閱讀畫面時無條件還原，不判斷 _lastAppliedFullscreen
    // （比照上一行既有的螢幕方向無條件還原寫法），避免外溢到書架等其他畫面。
    _fullscreenChannel.invokeMethod('setEnabled', false);
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
    } else if (state == AppLifecycleState.resumed) {
      // App 從背景恢復時，Android 系統列可能已被 OS 自動重新顯示，
      // _lastAppliedFullscreen 等值節流防護會誤判不需重套用，故強制清空
      // 快取後無條件重新呼叫一次（epic-19 Issue 1 review Critical 2）。
      _lastAppliedFullscreen = null;
      _applySystemUiMode();
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
      case BookFormat.azw3:
      case BookFormat.cbz:
      case BookFormat.txt:
      case BookFormat.md:
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

  /// 依 [_resolved] 的 fullscreen 呼叫 elinkbook/fullscreen 頻道，比照
  /// _applyScreenOrientation() 的節流寫法，避免偏好設定頻繁變動時重複
  /// 呼叫 platform channel。
  void _applySystemUiMode() {
    final resolved = _resolved;
    if (resolved == null) return;
    if (resolved.fullscreen == _lastAppliedFullscreen) return;
    _lastAppliedFullscreen = resolved.fullscreen;
    _fullscreenChannel.invokeMethod('setEnabled', resolved.fullscreen);
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
    _applySystemUiMode();
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

  /// 統一包裝 showModalBottomSheet：深色主題下遮罩改為完全透明。
  ///
  /// 顯示流式 EPUB 時，書頁背景已跟隨 `Theme.of(context)` 變深（見
  /// epic-22-reader-theme-integration Issue 1），Flutter `showModalBottomSheet`
  /// 既有預設半透明黑遮罩（`Colors.black54`）疊在這個已經很深的背景上，
  /// 合成結果逼近人眼無法辨識的全黑（`/diagnose` 已用 `Color.alphaBlend`
  /// 實測驗證：`AppTheme.dark` 背景 `#121214` 疊上 54% 黑遮罩，合成
  /// RGB≈(8,8,9)，一般手機螢幕正常環境光下已與純黑無法區分）——這不是
  /// WebView 合成或本次改動引入的 bug，是既有不變的遮罩值疊在變深的背景
  /// 上必然的數學結果，見 Issue 5。純降低遮罩透明度數值救不了（背景起點
  /// 已接近 0，任何黑色遮罩疊上去仍然接近黑），故深色主題下直接取消
  /// 遮罩；淺色/羊皮紙/E-Ink 皆為 `Brightness.light`，維持 Flutter 既有
  /// 預設值不變。本專案所有 Bottom Sheet 呼叫點皆應改用此方法，不直接
  /// 呼叫 `showModalBottomSheet`。
  Future<T?> _showThemedModalBottomSheet<T>({
    required WidgetBuilder builder,
    bool enableDrag = true,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      enableDrag: enableDrag,
      barrierColor: Theme.of(context).brightness == Brightness.dark
          ? Colors.transparent
          : null,
      builder: builder,
    );
  }

  void _openLayoutSettings() {
    StateSetter? setSheetState;
    _showThemedModalBottomSheet<void>(
      // Bottom Sheet 預設的下滑關閉手勢（enableDrag: true）與 Slider 的
      // 水平拖曳手勢在混合角度滑動時容易被手勢競技場誤判，導致使用者
      // 調整滑桿時選單意外關閉；停用後仍可點擊背景遮罩關閉。
      enableDrag: false,
      builder: (_) => StatefulBuilder(
        builder: (context, setState) {
          setSheetState = setState;
          return ReaderSettingsSheet(
            prefs: _prefs,
            onChanged: _handlePrefsChanged,
            customFonts: _customFonts,
            bookId: widget.bookId,
            layoutPresets: _layoutPresets,
            onSaveAsPreset: (draft) async {
              await _handleSaveAsPreset(draft);
              if (mounted) setSheetState?.call(() {});
            },
            onApplyPreset: (preset, {required targetBookIds}) async {
              await _handleApplyPreset(preset, targetBookIds: targetBookIds);
              if (mounted) setSheetState?.call(() {});
            },
            onApplyFromBook: (sourceBookId, {required targetBookIds}) async {
              await _handleApplyFromBook(sourceBookId, targetBookIds: targetBookIds);
              if (mounted) setSheetState?.call(() {});
            },
            onRequestBookPicker: _handleRequestBookPicker,
            onDeletePreset: (id) async {
              await _handleDeletePreset(id);
              if (mounted) setSheetState?.call(() {});
            },
          );
        },
      ),
    );
  }

  void _openPdfSettings() {
    _showThemedModalBottomSheet<void>(
      enableDrag: false,
      builder: (_) => PdfSettingsSheet(
        prefs: _prefs,
        onChanged: _handlePrefsChanged,
        onRequestManualCrop: _handleRequestManualCrop,
      ),
    );
  }

  void _openFxlSettings() {
    _showThemedModalBottomSheet<void>(
      builder: (_) => FxlSettingsSheet(
        prefs: _prefs,
        onChanged: _handlePrefsChanged,
      ),
    );
  }

  /// 版面設定預設集「另存為新預設集」（epic-28-reader-settings-
  /// enhancements Issue 3）：命名輸入 → 未滿 3 組直接 insert，已滿 3 組
  /// 跳出覆蓋選單 → 覆蓋前二次確認 → replace，完成後重新載入清單。
  Future<void> _handleSaveAsPreset(BookReaderPrefs currentDraft) async {
    final repository = widget.layoutPresetRepository;
    if (repository == null) return;
    final name = await showLayoutPresetNameDialog(context);
    if (name == null || !mounted) return;
    final filteredPrefs = currentDraft.reflowableEpubFields();
    final now = DateTime.now();
    if (_layoutPresets.length < 3) {
      await repository.insert(LayoutPreset(
        id: null,
        name: name,
        createdAt: now,
        updatedAt: now,
        prefs: filteredPrefs,
      ));
    } else {
      final target = await _selectPresetToOverwrite();
      if (target == null || !mounted) return;
      final confirmed = await _confirmOverwrite(target.name);
      if (!confirmed) return;
      await repository.replace(
        target.id!,
        LayoutPreset(
          id: target.id,
          name: name,
          createdAt: target.createdAt,
          updatedAt: now,
          prefs: filteredPrefs,
        ),
      );
    }
    await _loadLayoutPresets();
  }

  Future<LayoutPreset?> _selectPresetToOverwrite() {
    return showDialog<LayoutPreset>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('選擇要覆蓋的預設集'),
        children: [
          ..._layoutPresets.map((preset) => SimpleDialogOption(
                key: Key('layout_preset_overwrite_option_${preset.id}'),
                onPressed: () => Navigator.of(dialogContext).pop(preset),
                child: Text(
                    '${preset.name}（最後更新：${preset.updatedAt.year}/${preset.updatedAt.month}/${preset.updatedAt.day}）'),
              )),
          SimpleDialogOption(
            key: const Key('layout_preset_overwrite_cancel'),
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }

  Future<bool> _confirmOverwrite(String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('確認覆蓋'),
        content: Text('即將覆蓋預設集「$name」，此動作無法復原。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            key: const Key('layout_preset_overwrite_confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('確認覆蓋'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<bool> _confirmApplyToOtherBooks(int count) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('確認套用'),
        content: Text('即將覆蓋 $count 本書的版面設定，此動作無法復原。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            key: const Key('layout_preset_apply_confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('確認套用'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  /// 套用預設集（epic-28-reader-settings-enhancements Issue 3）：「套用到
  /// 目前書籍」（`targetBookIds` 恰為 `[widget.bookId]`，[ReaderSettingsSheet]
  /// 的「套用到本書」快速按鈕固定產生這個形狀）直接寫入不需確認；其餘
  /// 情況（「套用到其他書籍」流程，即使使用者只勾選 1 本其他書籍）皆先
  /// 跳出「即將覆蓋 N 本書」確認——**判斷依據刻意不是 `targetBookIds.length
  /// > 1`**：使用者透過「套用到其他書籍」picker 只勾選 1 本書時，
  /// `targetBookIds.length == 1`，但這仍是「其他書籍」語意（design.md
  /// 「套用目標二選一」的第二選項），不是「套用到目前書籍」的快速動作，
  /// 兩者不可用數量混為一談。目標含目前書籍時，寫入後呼叫既有
  /// [_handlePrefsChanged] 即時刷新畫面（比照 spec.md「套用到目前書籍後
  /// 的畫面刷新」，不新增另一條刷新路徑）。
  Future<void> _handleApplyPreset(
    LayoutPreset preset, {
    required List<String> targetBookIds,
  }) async {
    final repository = widget.bookReaderPrefsRepository;
    if (repository == null || targetBookIds.isEmpty) return;
    final isCurrentBookOnly =
        targetBookIds.length == 1 && targetBookIds.single == widget.bookId;
    if (!isCurrentBookOnly) {
      final confirmed = await _confirmApplyToOtherBooks(targetBookIds.length);
      if (!confirmed) return;
    }
    if (targetBookIds.length == 1) {
      await repository.save(targetBookIds.first, preset.prefs);
    } else {
      await repository.saveMultiple(targetBookIds, preset.prefs);
    }
    if (targetBookIds.contains(widget.bookId)) {
      _handlePrefsChanged(preset.prefs);
    }
  }

  /// 書籍設定複製（epic-28-reader-settings-enhancements Issue 3）：先讀取
  /// 來源書籍目前的版面偏好設定，以 [BookReaderPrefs.reflowableEpubFields]
  /// 過濾後寫入。確認對話框觸發條件與批次寫入門檻，語意皆與
  /// [_handleApplyPreset] 一致（見該方法文件「判斷依據刻意不是
  /// targetBookIds.length > 1」的說明）。
  Future<void> _handleApplyFromBook(
    String sourceBookId, {
    required List<String> targetBookIds,
  }) async {
    final repository = widget.bookReaderPrefsRepository;
    if (repository == null || targetBookIds.isEmpty) return;
    final sourcePrefs =
        (await repository.load(sourceBookId)).reflowableEpubFields();
    if (!mounted) return;
    final isCurrentBookOnly =
        targetBookIds.length == 1 && targetBookIds.single == widget.bookId;
    if (!isCurrentBookOnly) {
      final confirmed = await _confirmApplyToOtherBooks(targetBookIds.length);
      if (!confirmed) return;
    }
    if (targetBookIds.length == 1) {
      await repository.save(targetBookIds.first, sourcePrefs);
    } else {
      await repository.saveMultiple(targetBookIds, sourcePrefs);
    }
    if (targetBookIds.contains(widget.bookId)) {
      _handlePrefsChanged(sourcePrefs);
    }
  }

  Future<void> _handleDeletePreset(int id) async {
    final repository = widget.layoutPresetRepository;
    if (repository == null) return;
    String presetName = '';
    for (final preset in _layoutPresets) {
      if (preset.id == id) {
        presetName = preset.name;
        break;
      }
    }
    final confirmed = await _confirmDeletePreset(presetName);
    if (!confirmed) return;
    await repository.delete(id);
    await _loadLayoutPresets();
  }

  Future<bool> _confirmDeletePreset(String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('確認刪除'),
        content: Text('即將刪除預設集「$name」，此動作無法復原。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            key: const Key('layout_preset_delete_confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('確認刪除'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  /// 書籍選擇器（epic-28-reader-settings-enhancements Issue 3
  /// `onRequestBookPicker`）：以 [LibraryRepository.listReflowableEpubBooks]
  /// 過濾為僅流式 EPUB（排除目前書籍本身），推入
  /// [LayoutPresetBookPickerScreen] 供使用者選取。
  Future<List<String>?> _handleRequestBookPicker({
    required bool multiSelect,
  }) async {
    final repository = widget.libraryRepository;
    if (repository == null) return null;
    final books =
        await repository.listReflowableEpubBooks(excludeBookId: widget.bookId);
    if (!mounted) return null;
    return Navigator.of(context).push<List<String>?>(
      MaterialPageRoute(
        builder: (_) => LayoutPresetBookPickerScreen(
          books: books,
          multiSelect: multiSelect,
        ),
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

  Future<void> _loadCustomFonts() async {
    final repository = widget.customFontsRepository;
    if (repository == null) return;
    try {
      final fonts = await repository.listAll();
      if (!mounted) return;
      setState(() {
        _customFonts = fonts;
        _customFontsLoaded = true;
      });
    } catch (e) {
      debugPrint('Failed to load custom fonts: $e');
      if (!mounted) return;
      setState(() => _customFontsLoaded = true);
    }
  }

  Future<void> _loadLayoutPresets() async {
    final repository = widget.layoutPresetRepository;
    if (repository == null) return;
    try {
      final presets = await repository.listAll();
      if (!mounted) return;
      setState(() => _layoutPresets = presets);
    } catch (e) {
      debugPrint('Failed to load layout presets: $e');
    }
  }

  /// 目前頁是否已有書籤——比較 epubLocatorJson 完全相同字串，比照
  /// NotesBottomSheet._matchesCurrentPosition 既有邏輯（FXL／流式 EPUB
  /// 副檔名皆為 .epub，恆用 epubLocatorJson，不使用 pdfPageIndex，見
  /// Global Constraints）。epic-18 Issue 7 泛用化改名（原
  /// _fxlBookmarkAtCurrentPosition），供 FXL 與流式 EPUB 共用。
  Bookmark? get _bookmarkAtCurrentPosition {
    final locatorJson = _epubPositionInfo?.locatorJson;
    if (locatorJson == null) return null;
    for (final bookmark in _fxlBookmarks) {
      if (bookmark.epubLocatorJson == locatorJson) return bookmark;
    }
    return null;
  }

  /// PDF 版本的「目前頁是否已有書籤」（epic-24-pdf-engine-rebuild Issue
  /// 8）：比對 `pdfPageIndex`，比照 [_bookmarkAtCurrentPosition] 的 EPUB
  /// 版本邏輯，共用同一份 [_fxlBookmarks] 快取（[_loadFxlBookmarks] 是
  /// 格式無關的 `repository.listByBook` 查詢，見該方法定義）。
  Bookmark? get _pdfBookmarkAtCurrentPosition {
    final pageIndex = _pdfPageInfo?.pageIndex;
    if (pageIndex == null) return null;
    for (final bookmark in _fxlBookmarks) {
      if (bookmark.pdfPageIndex == pageIndex) return bookmark;
    }
    return null;
  }

  Future<void> _toggleBookmark() async {
    final repository = widget.bookmarksRepository;
    final positionInfo = _epubPositionInfo;
    if (repository == null || positionInfo == null) return;
    await bookmark_toggle.toggleBookmark(
      repository: repository,
      bookId: widget.bookId,
      matches: (bookmark) =>
          bookmark.epubLocatorJson == positionInfo.locatorJson,
      build: () => Bookmark(
        id: const Uuid().v4(),
        bookId: widget.bookId,
        name: Bookmark.defaultName(BookmarkPositionContext(
          epubLocatorJson: positionInfo.locatorJson,
          progression: positionInfo.progression,
        )),
        epubLocatorJson: positionInfo.locatorJson,
        progression: positionInfo.progression,
      ),
    );
    await _loadFxlBookmarks();
  }

  /// PDF 版本的書籤 toggle：本工單只需完成邏輯本身（見 issues.md Issue 4
  /// 範圍界定），對應的 FAB 按鈕留給 Issue 8 統一接線——目前僅能透過
  /// [ReaderScreen.togglePdfBookmark] 這個測試 seam 觸發，UI 尚無法直接
  /// 點擊呼叫。
  Future<void> _togglePdfBookmark() async {
    final repository = widget.bookmarksRepository;
    final pageIndex = _pdfPageInfo?.pageIndex;
    if (repository == null || pageIndex == null) return;
    await bookmark_toggle.toggleBookmark(
      repository: repository,
      bookId: widget.bookId,
      matches: (bookmark) => bookmark.pdfPageIndex == pageIndex,
      build: () => Bookmark(
        id: const Uuid().v4(),
        bookId: widget.bookId,
        name: Bookmark.defaultName(BookmarkPositionContext(pdfPageIndex: pageIndex)),
        pdfPageIndex: pageIndex,
      ),
    );
    await _loadFxlBookmarks();
  }

  /// 依 `_dispatchedIsFixedLayout` 分派到正確的原生 widget 執行目錄／
  /// 書籤／備註跳轉（epic-17-epub-render-migration Issue 6）：FXL
  /// （Readium）用 `EpubReaderView.jumpToLocator`，流式（foliate-js）用
  /// `FoliateReaderView.jumpToLocator`，兩者接受的 `locatorJson`
  /// 格式不同（Readium Locator JSON vs 本 Epic 新 CFI 格式），但呼叫端
  /// （本方法的三個呼叫點：`_openToc`／`_openNotesSheet` 的
  /// `onAnnotationSelected`／`onBookmarkSelected`）不需要關心格式差異，
  /// 只需傳入目前使用中書籍的 `locatorJson`。比照 `_handleZoneAction`
  /// （Issue 5）建立的相同分派模式。
  void _jumpToEpubLocator(String locatorJson) {
    // Epic 20 Issue 2：EPUB 一律使用 FoliateReaderView。
    FoliateReaderView.jumpToLocator(_foliateEpubReaderViewKey, locatorJson);
  }

  void _openToc() {
    final currentPath = TocNavigator.findCurrentPath(
      _tocEntries,
      _epubPositionInfo?.progression,
    );
    _showThemedModalBottomSheet<void>(
      builder: (_) => TocBottomSheet(
        format: BookFormat.epub,
        entries: _tocEntries,
        initiallyExpandedEntries: currentPath.toSet(),
        currentEntry: currentPath.isEmpty ? null : currentPath.last,
        totalCharacterCountListenable: _totalCharacterCountNotifier,
        resolved: _resolved!,
        onEntrySelected: (entry) {
          Navigator.of(context).pop();
          _jumpToEpubLocator((entry as TocEntry).locatorJson);
        },
      ),
    );
  }

  /// PDF 版本的目錄開啟（epic-24-pdf-engine-rebuild Issue 5）：本工單只
  /// 完成資料載入與 Bottom Sheet 顯示邏輯本身，比照 Issue 4 書籤 toggle
  /// 的既有先例（「toggle 對應的 FAB 按鈕留給 Issue 8 統一接線」）——目前
  /// 沒有對應的可見按鈕，只能透過 [ReaderScreen.openPdfToc] 這個測試 seam
  /// 觸發，UI 尚無法直接互動；FAB 接線見 Issue 8。
  ///
  /// 背景載入尚未完成（[_pdfTocLoaded] 仍為 false）時直接忽略，比照 EPUB
  /// 「reader_toc_button」`onPressed: null` 的既有防呆語意（見
  /// _buildAppBarActions case BookFormat.epub 對 _tocLoaded 的既有判斷）。
  void _openPdfToc() {
    if (!_pdfTocLoaded) return;
    final currentPath =
        PdfTocNavigator.findCurrentPath(_pdfTocEntries, _pdfPageInfo?.pageIndex);
    final pdfThumbnailMaxWidth =
        _pdfThumbnailMaxWidth * MediaQuery.of(context).devicePixelRatio.clamp(1.0, 3.0);
    _showThemedModalBottomSheet<void>(
      builder: (_) => TocBottomSheet(
        format: BookFormat.pdf,
        entries: _pdfTocEntries,
        initiallyExpandedEntries: currentPath.toSet(),
        currentEntry: currentPath.isEmpty ? null : currentPath.last,
        totalCharacterCountListenable: _pdfDummyCharacterCountNotifier,
        resolved: _resolved!,
        onEntrySelected: (entry) {
          Navigator.of(context).pop();
          final pageIndex = (entry as PdfTocItem).pageIndex;
          if (pageIndex != null) {
            PdfReaderView.jumpToPage(_pdfReaderViewKey, pageIndex);
          }
        },
        thumbnailTabContent: PdfThumbnailPanel(
          totalPages: _pdfPageInfo?.totalPages ?? 0,
          renderThumbnail: (pageIndex) => PdfReaderView.renderThumbnail(
            _pdfReaderViewKey,
            pageIndex,
            maxWidth: pdfThumbnailMaxWidth,
          ),
          onPageSelected: (pageIndex) {
            Navigator.of(context).pop();
            PdfReaderView.jumpToPage(_pdfReaderViewKey, pageIndex);
          },
        ),
        searchTabContent: PdfSearchPanel(
          searchStateListenable: _pdfSearchStateNotifier,
          initialQuery: _pdfSearchStateNotifier.value.query,
          onQueryChanged: (query) => unawaited(_searchPdf(query)),
          onNext: () => _goToPdfSearchMatch(1),
          onPrevious: () => _goToPdfSearchMatch(-1),
        ),
      ),
    );
  }

  /// 執行 PDF 內文搜尋（epic-24-pdf-engine-rebuild Issue 6）：呼叫
  /// [PdfReaderView.search] 取得符合結果，寫回 [_pdfSearchMatches] 供
  /// [_goToPdfSearchMatch] 使用，並透過 [PdfReaderView.setSearchHighlights]
  /// 疊加高亮＋跳轉至第一筆符合結果所在頁面。[query] 為空字串時清空搜尋
  /// 狀態與畫面高亮，不觸發實際搜尋。
  Future<void> _searchPdf(String query) async {
    final requestId = ++_pdfSearchRequestId;
    if (query.isEmpty) {
      _pdfSearchMatches = const [];
      PdfReaderView.setSearchHighlights(_pdfReaderViewKey, const [], currentIndex: null);
      _pdfSearchStateNotifier.value = const PdfSearchState.initial();
      return;
    }
    _pdfSearchStateNotifier.value = PdfSearchState(
      query: query,
      isSearching: true,
      matchCount: 0,
      currentIndex: null,
    );
    final matches = await PdfReaderView.search(_pdfReaderViewKey, query);
    if (!mounted || requestId != _pdfSearchRequestId) return;
    _pdfSearchMatches = matches;
    final currentIndex = matches.isEmpty ? null : 0;
    PdfReaderView.setSearchHighlights(_pdfReaderViewKey, matches, currentIndex: currentIndex);
    if (currentIndex != null) {
      PdfReaderView.jumpToPage(_pdfReaderViewKey, matches[currentIndex].pageIndex);
    }
    _pdfSearchStateNotifier.value = PdfSearchState(
      query: query,
      isSearching: false,
      matchCount: matches.length,
      currentIndex: currentIndex,
    );
  }

  /// 導覽至下一個（[delta] = 1）或上一個（[delta] = -1）符合結果，循環
  /// 至清單另一端（比照常見 PDF 閱讀器/瀏覽器 Ctrl+F 的既有慣例）。
  void _goToPdfSearchMatch(int delta) {
    if (_pdfSearchMatches.isEmpty) return;
    final current = _pdfSearchStateNotifier.value.currentIndex ?? -1;
    final next = (current + delta) % _pdfSearchMatches.length;
    PdfReaderView.setSearchHighlights(_pdfReaderViewKey, _pdfSearchMatches, currentIndex: next);
    PdfReaderView.jumpToPage(_pdfReaderViewKey, _pdfSearchMatches[next].pageIndex);
    _pdfSearchStateNotifier.value = _pdfSearchStateNotifier.value.copyWith(currentIndex: next);
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
          isFoliateFormat(format) ? _epubPositionInfo?.locatorJson : null,
      progression:
          isFoliateFormat(format) ? _epubPositionInfo?.progression : null,
      pdfPageIndex: format == BookFormat.pdf ? _pdfPageInfo?.pageIndex : null,
      chapterTitle: currentPath.isEmpty ? null : currentPath.last.title,
    );
    final latestProgress = isFoliateFormat(format)
        ? (_epubPositionInfo?.progression ?? widget.bookProgress)
        : (_pdfPageInfo != null && _pdfPageInfo!.totalPages > 0
            ? (_pdfPageInfo!.pageIndex + 1) / _pdfPageInfo!.totalPages
            : widget.bookProgress);
    _showThemedModalBottomSheet<void>(
      builder: (_) => NotesBottomSheet(
        bookId: widget.bookId,
        bookTitle: widget.bookTitle,
        bookAuthor: widget.bookAuthor,
        bookProgress: latestProgress,
        bookmarksRepository: repository,
        currentPosition: positionContext,
        // FXL EPUB 傳入 null（見 _handleSelectionChanged 註解——FXL 頁面
        // 是純點陣圖，無文字節點可選取，劃線/備註排除 FXL 是結構性必然，
        // 非可調整的產品決策，epic-20 Issue 4 審查回應已查證確認）。
        highlightsRepository: (isFoliateFormat(format) && !_isFixedLayout) ||
                format == BookFormat.pdf
            ? widget.highlightsRepository
            : null,
        notesRepository: (isFoliateFormat(format) && !_isFixedLayout) ||
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
      // epic-24-pdf-engine-rebuild Issue 8：PDF 同樣使用 _fxlBookmarks
      // 快取來驅動書籤 FAB 星號圖示（Step 9），Notes Sheet 關閉後的
      // 重新整理必須涵蓋 PDF，否則使用者在筆記面板裡新增/刪除 PDF 書籤
      // 後，FAB 圖示會停留在過期狀態。_openNotesSheet 的 format 參數
      // 已是 BookFormat 型別，此處直接比對即可，無需再呼叫 detectBookFormat。
      if (_isFixedLayout || format == BookFormat.pdf) _loadFxlBookmarks();
    });
  }

  void _handlePageRendered() {
    if (!mounted) return;
    _openBookTimeoutTimer?.cancel();
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
    // epic-24-pdf-engine-rebuild Issue 5：PDF 目錄背景載入，比照上方
    // _annotationsLoaded 的既有旗標模式（先設 true 再發起非同步呼叫，避免
    // 短時間內重複觸發）。與 EPUB 的 _tocLoaded 觸發點
    // （_handleFoliateLayoutResolved）刻意不同——PDF 同樣沒有版面解析
    // 回呼，onPageRendered 是 PDF 開書成功的唯一既有訊號。
    if (detectBookFormat(widget.filePath) == BookFormat.pdf && !_pdfTocLoaded) {
      _pdfTocLoaded = true;
      PdfReaderView.loadTableOfContents(_pdfReaderViewKey).then((items) {
        if (!mounted) return;
        setState(() => _pdfTocEntries = items);
      });
      // epic-24-pdf-engine-rebuild Issue 8（審查意見 Important 1）：PDF
      // 開書成功時一併載入書籤快取，讓 Step 9 新增的書籤 FAB 星號圖示在
      // 使用者尚未手動 toggle／開過筆記面板前就能正確反映既有書籤狀態。
      // 借用既有 _pdfTocLoaded 旗標的去重保護（本區塊本來就只會在單一
      // PDF 開書流程中執行一次），不另外新增專屬旗標。
      // _loadFxlBookmarks() 內部已對 widget.bookmarksRepository == null
      // 做早退防呆，此處不需額外判斷。
      _loadFxlBookmarks();
    }
  }

  /// 【/diagnose：真機回報旋轉螢幕後畫面被錯誤文字取代，無法繼續閱讀】
  /// 只在 `_state == loading` 時才轉為錯誤畫面——書籍已成功渲染
  /// （`_state == rendered`）後才發生的 `onError` 不應覆蓋掉已顯示的
  /// 內容。根因：epic-18-reader-device-qa Issue 33 新增的全域
  /// `window.onerror`／`window.onunhandledrejection` 補捉會轉發「任何」
  /// 未被攔截的 JS 例外，包含瀏覽器層級的良性警告（例如 foliate-js 的
  /// paginator 在螢幕旋轉、ResizeObserver 重新觀察內容尺寸時，Chromium
  /// 觸發的「ResizeObserver loop completed with undelivered
  /// notifications」——這只是瀏覽器告知一輪 resize callback 沒能在同一
  /// frame 內處理完畢，不代表書籍真的開啟失敗）；這個 guard 與既有的
  /// `_handleOpenBookTimeout()` 採用同一種防禦模式。
  void _handleError(String message) {
    if (!mounted) return;
    if (_state != _RenderState.loading) return;
    _openBookTimeoutTimer?.cancel();
    setState(() {
      _state = _RenderState.error;
      _errorMessage = message;
    });
  }

  /// epic-18-reader-device-qa Issue 33：見上方 `_openBookTimeoutTimer` 註解。
  /// 判斷 `_state == loading` 才動作——理論上 `_handlePageRendered()`／
  /// `_handleError()` 都會取消這個 Timer，這裡是雙重防禦，避免任何未預期
  /// 的競態把已經成功渲染或已經顯示其他錯誤訊息的畫面覆蓋掉。
  void _handleOpenBookTimeout() {
    if (!mounted) return;
    if (_state != _RenderState.loading) return;
    setState(() {
      _state = _RenderState.error;
      _errorMessage = '開書逾時，可能是系統 WebView 版本過舊或檔案異常';
    });
  }

  /// `FoliateReaderView` 專屬的 onLayoutResolved 處理。
  /// 【已知、可接受的行為】把自動偵測結果寫回 [_autoDetectedWritingMode]
  /// 後，若當下沒有 writingModeOverride，[_resolved] 的 writingMode 會從 null
  /// 變成非 null，驅動 `FoliateReaderView` 以非 null 值重建。
  /// epic-17-epub-render-migration Issue 4 起，也設定
  /// `_autoDetectedWritingMode` 並重新計算 `_resolved`（比照
  /// `_handleLayoutResolved` 對應段落），讓「版面設定」按鈕能對流式書籍
  /// 生效。Issue 6 起新增目錄背景抓取（比照 `_handleLayoutResolved`
  /// 對應段落，改呼叫 `FoliateReaderView.loadTableOfContents()`
  /// 而非 `EpubReaderView` 的版本）——不需要像 Readium 分支那樣額外檢查
  /// `!info.isFixedLayout`，因為 `FoliateReaderView.loadTableOfContents()`
  /// 對 FXL／流式書籍皆可正常運作。epic-20 Issue 2 起，本方法也會被 FXL
  /// 書籍呼叫（`_dispatchedIsFixedLayout == true` 時同樣建構
  /// `FoliateReaderView`，不再是「恆為流式」）——但目前
  /// `FoliateReaderView` 的 `onPageRendered` handler（見
  /// `foliate_reader_view.dart`）尚未回傳真實的 `isFixedLayout`
  /// 判斷結果，`info.isFixedLayout` 在這裡固定收到 `false`，故本方法內部
  /// 目前不依賴 `info.isFixedLayout` 做任何分支。觸發
  /// `_reloadAnnotationsAndRefreshDecorations` 以載入劃線備註——`_sendDecorationsToNative()`
  /// 現已無條件使用 `FoliateReaderView.setDecorations`，FXL 書籍的
  /// 劃線/備註疊圖已生效（Issue 4 修正）。
  void _handleFoliateLayoutResolved(EpubLayoutInfo info) {
    if (!mounted) return;
    setState(() {
      // 當使用者透過「強制 FXL」手動設定 isFixedLayout=true 時，
      // 覆蓋 native view 的異步回報（見 _resolveEpubEngineDispatch 註解）。
      if (widget.isFixedLayout != true) {
        _isFixedLayout = info.isFixedLayout;
      }
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
      FoliateReaderView.loadTableOfContents(_foliateEpubReaderViewKey)
          .then((entries) {
        if (!mounted) return;
        setState(() {
          _tocEntries = entries;
          _tocLoaded = true;
        });
      });
    }
    if (!_annotationsLoaded &&
        widget.highlightsRepository != null &&
        widget.notesRepository != null) {
      _annotationsLoaded = true;
      _reloadAnnotationsAndRefreshDecorations();
    }
  }

  /// FXL 一律不處理選取事件（design.md 決策 #7：劃線/備註排除 FXL）——
  /// 已查證（epic-20 Issue 4 審查回應）FXL 頁面的 XHTML 內容一律是
  /// `<svg><image .../></svg>`（純點陣圖，OPF 內每個 `p-*.xhtml` 皆同一
  /// 樣式），完全沒有文字節點；`main.js` 的選字回報機制（`:510-550`）
  /// 依賴 `document.getSelection()`/`Range`，`overlayer.js` 疊圖計算也依賴
  /// `Range`／`createRange()`——兩者皆需要文字節點才能產生有意義的
  /// 結果。這代表 FXL 排除劃線/備註**不是可調整的產品決策**，而是目前
  /// 圖片式 FXL 內容結構本身無法支援選字→CFI range 這條既有機制的必然
  /// 結果；此防呆保證不會意外對 FXL 觸發劃線 UI（見 plan-issue-2.md
  /// Global Constraints「FXL 排除」）。
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

  /// Epic 25 Issue 3：使用者主動點擊 AnnotationToolbar 關閉按鈕時呼叫——
  /// 除了清空 Dart 端選取狀態（比照 [_handleSelectionCleared]）外，額外
  /// 呼叫 JS 端 window.clearSelection() 清除 WebView 原生選取（藍色反白
  /// ＋拖曳控點），避免工具列消失後畫面仍殘留原生選取視覺（該視覺層不受
  /// Dart state 控制，見 main.js window.clearSelection 註解）。PDF 端沒有
  /// 這個問題（見 Global Constraints「PDF 端不需要對應的原生選取清除
  /// 機制」的查證結論），故 PDF 呼叫端直接沿用既有
  /// [_handlePdfSelectionCanceled]，不需要對應的 wrapper。
  void _handleCloseAnnotationToolbar() {
    _handleSelectionCleared();
    FoliateReaderView.clearSelection(_foliateEpubReaderViewKey);
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

  Future<void> _handleHighlightStyleSelected(HighlightStyle style) async {
    final selection = _currentSelection;
    final repository = widget.highlightsRepository;
    if (selection == null || repository == null) return;
    final id = const Uuid().v4();
    await repository.insert(Highlight(
      id: id,
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
      id: const Uuid().v4(),
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

  /// 無條件使用 `FoliateReaderView.setDecorations`（Issue 4 修正：
  /// FXL 書籍的劃線/備註疊圖從本工單起才第一次真正生效，先前因
  /// `_dispatchedIsFixedLayout` 分派到已無人建構的 `EpubReaderView` 而
  /// 靜默失敗）。
  void _sendDecorationsToNative() {
    if (!mounted) return;
    final primaryColor = Theme.of(context).colorScheme.primary;
    final decorations = <EpubDecoration>[
      for (final highlight in _highlights)
        if (highlight.epubLocatorJson != null)
          EpubDecoration.forHighlight(
            highlightId: highlight.id,
            locatorJson: highlight.epubLocatorJson!,
            tint: highlightStyleTint(highlight.style, primaryColor: primaryColor),
            isUnderline: highlight.style == HighlightStyle.underline,
          ),
      for (final note in _notes)
        if (note.highlightId == null && note.epubLocatorJson != null)
          EpubDecoration.forNote(
            noteId: note.id,
            locatorJson: note.epubLocatorJson!,
            tint: noteOnlyTint.toARGB32(),
          ),
    ];
    FoliateReaderView.setDecorations(_foliateEpubReaderViewKey, decorations);
  }

  Highlight? _findHighlightById(String id) {
    for (final highlight in _highlights) {
      if (highlight.id == id) return highlight;
    }
    return null;
  }

  Note? _findNoteByHighlightId(String highlightId) {
    for (final note in _notes) {
      if (note.highlightId == highlightId) return note;
    }
    return null;
  }

  Note? _findNoteById(String id) {
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
        await widget.notesRepository!.updateText(note.id, newText);
        await _reloadAnnotationsAndRefreshDecorations();
      }
    } else if (action == 'delete') {
      // 單筆刪除＝整筆一起刪（spec.md 決策 #13），比照
      // NotesBottomSheet._deleteAnnotationItem 的既有原則。
      if (note != null) await widget.notesRepository!.delete(note.id);
      if (highlight != null) await widget.highlightsRepository!.delete(highlight.id);
      await _reloadAnnotationsAndRefreshDecorations();
    }
  }

  Future<void> _handlePdfHighlightStyleSelected(HighlightStyle style) async {
    final selection = _currentPdfSelection;
    final repository = widget.highlightsRepository;
    if (selection == null || repository == null) return;
    final highlightId = const Uuid().v4();
    await repository.insert(Highlight(
      id: highlightId,
      bookId: widget.bookId,
      style: style,
      pdfPageIndex: selection.pageIndex,
      pdfRect: selection.rect,
    ));
    _pendingPdfHighlightIdForSelection = highlightId;
    await _reloadPdfAnnotationsAndSync();
  }

  Future<void> _handlePdfNotePressed() async {
    final selection = _currentPdfSelection;
    final repository = widget.notesRepository;
    if (selection == null || repository == null) return;
    final text = await showNoteTextDialog(context, title: '新增備註');
    if (text == null) return;
    final noteId = const Uuid().v4();
    await repository.insert(Note(
      id: noteId,
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
        // 流式 EPUB（FoliateReaderView）的頁尾已改為浮動疊加層，resize
        // 問題對此路徑已解決。
        extendBodyBehindAppBar: true,
        // epic-18-reader-device-qa Issue 7：流式 EPUB（_dispatchedIsFixedLayout
        // == false）一律不建構 AppBar，改用 _buildBody() 內對稱於 FXL 的
        // Positioned 浮動疊加層 chrome（見下方 _buildBody 的新增區塊）——不論
        // _chromeVisible 為何，讓 EpubReaderView（FXL）／FoliateReaderView
        // （流式）兩條渲染路徑最終殊途同歸都是 appBar: null。
        appBar: (_isFixedLayout ||
                !_chromeVisible ||
                format == BookFormat.pdf ||
                (isFoliateFormat(format) && _dispatchedIsFixedLayout == false))
            ? null // 固定版面（如漫畫）、沉浸模式已收起介面、PDF（epic-24 Issue 8 起改用 FAB）、或流式 Foliate 格式時隱藏 Scaffold AppBar
            : AppBar(
                toolbarHeight: _appBarToolbarHeight,
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
    final showHeader = isFoliateFormat(format) && (_resolved?.showHeader ?? false);
    if (!showHeader) {
      return const Text(
        '閱讀器',
        key: Key('reader_appbar_static_title'),
        style: TextStyle(fontSize: _appBarTitleFontSize),
      );
    }
    final currentPath = TocNavigator.findCurrentPath(
      _tocEntries,
      _epubPositionInfo?.progression,
    );
    final chapterTitle = currentPath.isEmpty ? '閱讀器' : currentPath.last.title;
    return InkWell(
      key: const Key('reader_appbar_chapter_title'),
      onTap: (_autoDetectedWritingMode == null || !_tocLoaded) ? null : _openToc,
      child: Text(
        chapterTitle,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: _appBarTitleFontSize),
      ),
    );
  }

  // AppBar 瘦身（Epic 18 Issue 2，design.md 決策 #2：縮減至約現有高度
  // 1/3）：只設定 toolbarHeight 不夠——IconButton 預設觸控寬度 48dp、
  // 預設圖示 24dp，title 文字預設字級，在 20dp 高的 AppBar 內都會偏擠，
  // 故同步收斂三者。以下數值為起始建議值，真機測試（Task 3）後可再調整
  // （issues.md Issue 2 審查修正）。
  //
  // 【實測發現，記錄供未來維護者知悉】_buildAppBarActions() 的
  // IconButton 一律透過 `style: IconButton.styleFrom(...)` 收斂尺寸，
  // 不使用建構子的 `padding`/`constraints` 參數——Material 3 的
  // IconButton 在本專案 Flutter 版本（3.41.9）下，`padding`/`constraints`
  // 這兩個建構子參數對實際渲染尺寸完全無效（實測仍是 48dp 預設寬度），
  // 必須透過 `style` 才能真正生效。另外，AppBar.actions 內的按鈕實際
  // 渲染高度無論如何設定都會被鎖死在 toolbarHeight（本例為 20），故這裡
  // 只需要一個「最小寬度」常數，不需要（也無法生效）獨立的「最小高度」
  // 常數——`_appBarButtonMinWidth` 只控制寬度，高度直接沿用
  // `_appBarToolbarHeight`。
  static const _appBarToolbarHeight = 20.0;
  static const _appBarButtonMinWidth = 32.0;
  static const _appBarIconSize = 18.0;
  static const _appBarTitleFontSize = 13.0;
  static const double _pdfThumbnailMaxWidth = 120;

  List<Widget>? _buildAppBarActions(BookFormat format) {
    if (_isFixedLayout) return null;
    switch (format) {
      case BookFormat.epub:
      case BookFormat.azw3:
      case BookFormat.cbz:
      case BookFormat.txt:
      case BookFormat.md:
        return [
          IconButton(
            key: const Key('reader_toc_button'),
            icon: const Icon(Icons.menu_book, size: _appBarIconSize),
            tooltip: '目錄',
            style: IconButton.styleFrom(
              minimumSize: const Size(_appBarButtonMinWidth, _appBarToolbarHeight),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              padding: EdgeInsets.zero,
            ),
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
            icon: const Icon(Icons.settings, size: _appBarIconSize),
            tooltip: '版面設定',
            style: IconButton.styleFrom(
              minimumSize: const Size(_appBarButtonMinWidth, _appBarToolbarHeight),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              padding: EdgeInsets.zero,
            ),
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
              icon: const Icon(Icons.bookmarks, size: _appBarIconSize),
              tooltip: '筆記',
              style: IconButton.styleFrom(
                minimumSize: const Size(_appBarButtonMinWidth, _appBarToolbarHeight),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                padding: EdgeInsets.zero,
              ),
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
        return null;
      case BookFormat.unknown:
        return null;
    }
  }

  // 浮動工具列估計高度／與選取範圍的間距（初始選擇，真機測試後可能需
  // 微調，見 Global Constraints「選取矩形座標協定」）。
  static const _annotationToolbarHeight = 56.0;
  static const _annotationToolbarGap = 8.0;
  // AnnotationToolbar 實際渲染寬度（6 顆 IconButton，Material 3 預設每顆
  // 48dp 寬 + Row 外層 Padding 左右各 8dp = 6*48+16 = 304；widget test
  // 量測值，見 plan-issue-2.md Global Constraints，與既有
  // _annotationToolbarHeight 同一量測手法得出）。選取範圍靠近螢幕右緣時，
  // left 的 clamp 上界須扣除這個寬度，否則工具列本體會整個超出螢幕右側
  // （issues.md Issue 2）。【issues.md Issue 3】新增第 6 顆關閉按鈕後，
  // 實際渲染寬度從 256（5 顆）變為 304（6 顆），此常數需同步更新，否則
  // Issue 2 的 clamp 修法會重新出現裁切（見 plan-issue-3.md Task 1）。
  static const _annotationToolbarWidth = 304.0;

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
          key: const Key('reader_body_stack'),
          children: [
            if (_resolved != null &&
                (!isFoliateFormat(format) ||
                    (_dispatchedIsFixedLayout != null && _customFontsLoaded)))
              _buildNativeView(format, isLandscape),
            // epic-27-reader-device-compat Issue 3：原生渲染畫面（InAppWebView／
            // pdfrx 繪圖表面）在真正收到第一次繪製結果前，緩衝區預設顯示黑色
            // （Android 平台已知行為，見 reviews/bugfix-repro.md Issue 3）。這層
            // 不透明遮罩必須疊在 _buildNativeView 之上（Stack 依 children 清單
            // 順序繪製，後面的 child 疊在前面之上）才能真正蓋住原生視圖輸出的
            // 黑色緩衝區，故放在 _buildNativeView 這個 if 區塊之後；僅在
            // _state == loading 時顯示——一旦渲染完成立即移除，避免永久蓋住
            // 已渲染完成的書籍內容或阻擋觸控手勢（見 plans/plan-issue-3.md
            // 「設計決策」1，初版計畫誤放在 _buildNativeView 之下、且恆常顯示，
            // 已於審查發現並修正）。
            // 【review-issue-3.md Critical #1 修正】ColoredBox 預設以
            // HitTestBehavior.opaque 吸收其涵蓋範圍內的所有觸控——會連帶擋掉
            // Issue 1 明確保留、loading 期間仍應可用的 menu 熱區（切換沉浸
            // 模式，不呼叫任何 JS/native API，無崩潰風險，見
            // plan-issue-1.md）。這層遮罩只需要「視覺蓋住黑幀」，不該參與
            // 觸控，故包一層 IgnorePointer 讓觸控直接穿透到底下的原生視圖／
            // 熱區——previousPage/nextPage 在 loading 期間仍受
            // _handleZoneAction 既有的邏輯防呆保護（Issue 1），不依賴這層
            // 遮罩擋觸控才成立。
            if (_state == _RenderState.loading)
              Positioned.fill(
                child: IgnorePointer(
                  child: ColoredBox(
                    key: const Key('reader_render_placeholder_background'),
                    color: Theme.of(context).scaffoldBackgroundColor,
                  ),
                ),
              ),
            // epic-18-reader-device-qa Issue 7：流式 Foliate 格式的 chrome，結構對稱
            // 於上方 FXL 浮動按鈕區塊——appBar 已在 build() 恆為 null（見上方
            // 註解），改用這組 Positioned 疊加層承載「功能操作」（返回／TOC／
            // 設定／書籤／筆記／進度-跳頁），另有 2 個純顯示元件（頁眉章節
            // 名稱／進度文字）承載「資訊顯示」，兩者刻意分離（design.md「第
            // 二輪真機使用回報」項目 2）。
            if (isFoliateFormat(format) && _chromeVisible)
              Positioned(
                top: 16,
                left: 16,
                child: ClipOval(
                  child: Container(
                    color: _themedFabBackgroundColor,
                    child: IconButton(
                      key: const Key('reader_foliate_back_button'),
                      icon: Icon(Icons.arrow_back, color: _themedFabIconColor),
                      tooltip: '返回',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                ),
              ),
            if (isFoliateFormat(format) && _chromeVisible)
              Positioned(
                top: 16,
                right: 16,
                child: ClipOval(
                  child: Container(
                    color: _themedFabBackgroundColor,
                    child: IconButton(
                      key: const Key('reader_foliate_toc_button'),
                      icon: Icon(Icons.menu_book, color: _themedFabIconColor),
                      tooltip: '目錄',
                      onPressed: (_autoDetectedWritingMode == null || !_tocLoaded)
                          ? null
                          : _openToc,
                    ),
                  ),
                ),
              ),
            if (isFoliateFormat(format) && _chromeVisible)
              Positioned(
                top: 72,
                right: 16,
                child: ClipOval(
                  child: Container(
                    color: _themedFabBackgroundColor,
                    child: IconButton(
                      key: const Key('reader_foliate_settings_button'),
                      icon: Icon(Icons.settings, color: _themedFabIconColor),
                      tooltip: '版面設定',
                      onPressed: _isFixedLayout
                          ? _openFxlSettings
                          : (_autoDetectedWritingMode == null ? null : _openLayoutSettings),
                    ),
                  ),
                ),
              ),
            if (isFoliateFormat(format) &&
                _chromeVisible &&
                widget.bookmarksRepository != null)
              Positioned(
                top: 128,
                right: 16,
                child: ClipOval(
                  child: Container(
                    color: _themedFabBackgroundColor,
                    child: IconButton(
                      key: const Key('reader_foliate_bookmark_toggle_button'),
                      icon: Icon(
                        _bookmarkAtCurrentPosition != null
                            ? Icons.star
                            : Icons.star_border,
                        color: _themedFabIconColor,
                      ),
                      tooltip: _bookmarkAtCurrentPosition != null
                          ? '已加入此頁書籤'
                          : '加入此頁書籤',
                      onPressed:
                          _epubPositionInfo == null ? null : _toggleBookmark,
                    ),
                  ),
                ),
              ),
            if (isFoliateFormat(format) &&
                _chromeVisible &&
                widget.bookmarksRepository != null)
              Positioned(
                top: 184,
                right: 16,
                child: ClipOval(
                  child: Container(
                    color: _themedFabBackgroundColor,
                    child: IconButton(
                      key: const Key('reader_foliate_notes_button'),
                      icon: Icon(Icons.bookmarks, color: _themedFabIconColor),
                      tooltip: '筆記',
                      onPressed: (_autoDetectedWritingMode == null ||
                              _epubPositionInfo == null)
                          ? null
                          : () => _openNotesSheet(format),
                    ),
                  ),
                ),
              ),
            if (isFoliateFormat(format) && _chromeVisible)
              Positioned(
                top: 240,
                right: 16,
                child: ClipOval(
                  child: Container(
                    color: _themedFabBackgroundColor,
                    child: IconButton(
                      key: const Key('reader_foliate_progress_button'),
                      icon: Icon(Icons.swap_vert, color: _themedFabIconColor),
                      tooltip: '跳頁',
                      onPressed: _openFoliateProgressSheet,
                    ),
                  ),
                ),
              ),
            // ── PDF FAB 區塊（epic-24-pdf-engine-rebuild Issue 8）─────
            // 與上方 EPUB FAB 完全對稱的 6 顆浮動圓形按鈕：返回／目錄／
            // 版面設定／書籤 toggle／筆記／進度-跳頁。比照 EPUB 既有的
            // ClipOval + Container + IconButton 模式，共用
            // _themedFabBackgroundColor / _themedFabIconColor（已是格式
            // 無關的 getter）。額外加上 !_cropEditModeActive 保護——裁切
            // 編輯模式是封閉狀態（只透過去裁切框自身的確認按鈕離開），
            // FAB 不應在此時可見（見 Global Constraints）。
            if (format == BookFormat.pdf && _chromeVisible && !_cropEditModeActive)
              Positioned(
                top: 16,
                left: 16,
                child: ClipOval(
                  child: Container(
                    color: _themedFabBackgroundColor,
                    child: IconButton(
                      key: const Key('reader_pdf_back_button'),
                      icon: Icon(Icons.arrow_back, color: _themedFabIconColor),
                      tooltip: '返回',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                ),
              ),
            if (format == BookFormat.pdf && _chromeVisible && !_cropEditModeActive)
              Positioned(
                top: 16,
                right: 16,
                child: ClipOval(
                  child: Container(
                    color: _themedFabBackgroundColor,
                    child: IconButton(
                      key: const Key('reader_pdf_toc_button'),
                      icon: Icon(Icons.menu_book, color: _themedFabIconColor),
                      tooltip: '目錄',
                      onPressed: !_pdfTocLoaded ? null : _openPdfToc,
                    ),
                  ),
                ),
              ),
            if (format == BookFormat.pdf && _chromeVisible && !_cropEditModeActive)
              Positioned(
                top: 72,
                right: 16,
                child: ClipOval(
                  child: Container(
                    color: _themedFabBackgroundColor,
                    child: IconButton(
                      key: const Key('reader_pdf_settings_button'),
                      icon: Icon(Icons.settings, color: _themedFabIconColor),
                      tooltip: '版面設定',
                      onPressed:
                          _state == _RenderState.rendered ? _openPdfSettings : null,
                    ),
                  ),
                ),
              ),
            if (format == BookFormat.pdf &&
                _chromeVisible &&
                !_cropEditModeActive &&
                widget.bookmarksRepository != null)
              Positioned(
                top: 128,
                right: 16,
                child: ClipOval(
                  child: Container(
                    color: _themedFabBackgroundColor,
                    child: IconButton(
                      key: const Key('reader_pdf_bookmark_toggle_button'),
                      icon: Icon(
                        _pdfBookmarkAtCurrentPosition != null
                            ? Icons.star
                            : Icons.star_border,
                        color: _themedFabIconColor,
                      ),
                      tooltip: _pdfBookmarkAtCurrentPosition != null
                          ? '已加入此頁書籤'
                          : '加入此頁書籤',
                      onPressed:
                          _pdfPageInfo == null ? null : _togglePdfBookmark,
                    ),
                  ),
                ),
              ),
            if (format == BookFormat.pdf &&
                _chromeVisible &&
                !_cropEditModeActive &&
                widget.bookmarksRepository != null)
              Positioned(
                top: 184,
                right: 16,
                child: ClipOval(
                  child: Container(
                    color: _themedFabBackgroundColor,
                    child: IconButton(
                      key: const Key('reader_pdf_notes_button'),
                      icon: Icon(Icons.bookmarks, color: _themedFabIconColor),
                      tooltip: '筆記',
                      onPressed: _state == _RenderState.rendered
                          ? () => _openNotesSheet(BookFormat.pdf)
                          : null,
                    ),
                  ),
                ),
              ),
            if (format == BookFormat.pdf && _chromeVisible && !_cropEditModeActive)
              Positioned(
                top: 240,
                right: 16,
                child: ClipOval(
                  child: Container(
                    color: _themedFabBackgroundColor,
                    child: IconButton(
                      key: const Key('reader_pdf_progress_button'),
                      icon: Icon(Icons.swap_vert, color: _themedFabIconColor),
                      tooltip: '跳頁',
                      onPressed: _openPdfProgressSheet,
                    ),
                  ),
                ),
              ),
            if (isFoliateFormat(format) &&
                (_resolved?.showHeader ?? false) &&
                !_chromeVisible)
              (_resolved?.writingMode == WritingMode.vertical)
                  ? Positioned(
                      right: 0,
                      top: 16,
                      bottom: 16,
                      child: RotatedBox(
                        quarterTurns: 1,
                        child: _buildFoliateHeaderText(),
                      ),
                    )
                  : Positioned(
                      top: 0,
                      left: 72,
                      right: 72,
                      child: Center(child: _buildFoliateHeaderText()),
                    ),
            if (isFoliateFormat(format) &&
                (_resolved?.showFooter ?? false) &&
                (_epubPositionInfo?.totalPages ?? 0) > 0)
              (_resolved?.writingMode == WritingMode.vertical)
                  ? Positioned(
                      left: 0,
                      bottom: 16,
                      child: RotatedBox(
                        quarterTurns: 1,
                        child: _buildFoliateProgressText(),
                      ),
                    )
                  : Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Center(child: _buildFoliateProgressText()),
                    ),
            if (selection != null)
              Positioned(
                left: (selection.rect.left * size.width)
                    .clamp(0.0, size.width - _annotationToolbarWidth),
                top: _annotationToolbarTop(selection, size),
                child: AnnotationToolbar(
                  onStyleSelected: _handleHighlightStyleSelected,
                  onNotePressed: _handleNotePressed,
                  onClosePressed: _handleCloseAnnotationToolbar,
                ),
              ),
            if (pdfSelection != null)
              Positioned(
                // 同上（見 _pdfAnnotationToolbarTop 註解）：改用相對整個
                // widget 尺寸的 widgetRect，避免 letterbox 留白造成偏移。
                left: (pdfSelection.widgetRect.left * size.width)
                    .clamp(0.0, size.width - _annotationToolbarWidth),
                top: _pdfAnnotationToolbarTop(pdfSelection, size),
                child: AnnotationToolbar(
                  onStyleSelected: _handlePdfHighlightStyleSelected,
                  onNotePressed: _handlePdfNotePressed,
                  onClosePressed: _handlePdfSelectionCanceled,
                ),
              ),
            if (_cropEditModeActive)
              Positioned.fill(
                child: PdfCropFrameOverlay(
                  initialRect: _prefs.pdfCropRect ??
                      const PdfCropRect(left: 0, top: 0, right: 1, bottom: 1),
                  onConfirm: (rect) {
                    setState(() => _cropEditModeActive = false);
                    _handlePrefsChanged(
                      _prefs.copyWith(pdfCropMode: PdfCropMode.manual, pdfCropRect: rect),
                    );
                  },
                  onCancel: () => setState(() => _cropEditModeActive = false),
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
      // 流式 EPUB 頁尾已改為浮動疊加層，不再影響 body 高度。
      padding: EdgeInsets.only(top: MediaQuery.of(context).viewPadding.top),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(child: body),
          ],
        ),
      ),
    );
  }



  /// 流式 EPUB 頁眉（epic-18-reader-device-qa Issue 7）：純顯示章節名稱、
  /// 不可點擊（點擊開 TOC 這個功能已交給獨立的 reader_foliate_toc_button，
  /// 見 design.md「第二輪真機使用回報」項目 2 的「資訊與功能分離」原則）。
  /// 章節名稱推導邏輯與既有 _buildAppBarTitle() 相同，故不重複抽象成共用
  /// 函式——兩者一個要包 InkWell/onTap、一個刻意不包，硬拆共用反而增加
  /// 兩個呼叫端之間不必要的耦合。
  Widget _buildFoliateHeaderText() {
    final currentPath = TocNavigator.findCurrentPath(
      _tocEntries,
      _epubPositionInfo?.progression,
    );
    final chapterTitle =
        currentPath.isEmpty ? widget.bookTitle : currentPath.first.title;
    return Container(
      key: const Key('reader_foliate_header_text'),
      child: Text(
        chapterTitle,
        overflow: TextOverflow.ellipsis,
        maxLines: 1,
        // 【epic-22-reader-theme-integration Issue 2】顯示流式 EPUB 時
        // 跟隨 Theme.of(context)（與書頁內容同一組色值來源，見 Issue 1）；
        // 顯示固定版面時 _themedTextColor 回傳 null，退回既有寫死黑色——
        // 固定版面內容是圖片，背景通常維持白底，文字色跟著深色主題變淺
        // 會看不見（見 spec.md 決策 9）。
        style: TextStyle(color: _themedTextColor ?? Colors.black, fontSize: 12),
      ),
    );
  }

  /// 流式 EPUB 進度純顯示（epic-18-reader-device-qa Issue 7）：內容換算邏輯
  /// 與 _buildFoliateEpubFooter() 相同（pageIndex/totalPages 皆為 0-indexed/
  /// 近似頁碼，+1 換算為人類慣用的 1-indexed），呼叫端已保證
  /// totalPages > 0 才會建構本 widget。跳頁互動已獨立到
  /// reader_foliate_progress_button 開啟的 Bottom Sheet，本 widget 不含任何
  /// 手勢 widget。
  Widget _buildFoliateProgressText() {
    final info = _epubPositionInfo!;
    final totalPages = info.totalPages!;
    final currentPage = ((info.pageIndex ?? 0) + 1).clamp(1, totalPages);
    return Container(
      key: const Key('reader_foliate_progress_text'),
      child: Text(
        '$currentPage/$totalPages',
        // 【epic-22-reader-theme-integration Issue 2】理由同
        // _buildFoliateHeaderText()：跟隨 Theme.of(context)，固定版面時
        // 退回既有寫死黑色。
        style: TextStyle(color: _themedTextColor ?? Colors.black, fontSize: 12),
      ),
    );
  }

  /// 流式 EPUB「進度/跳頁」浮動按鈕開啟的 Bottom Sheet（epic-18-
  /// reader-device-qa Issue 7）：內容直接沿用既有 _buildFoliateEpubFooter()
  /// 回傳的 ReaderFooter widget 實例（含既有 currentPage/totalPages
  /// 換算與 onPageChanged 跳頁邏輯），只是把承載它的容器從 in-flow Column
  /// 子項改為 Bottom Sheet——ReaderFooter 本身不需要任何修改。
  /// _epubPositionInfo 為 null（onLocatorChanged 尚未觸發過）時顯示空白
  /// Sheet，比照 reader_foliate_progress_button 本身只依 showFooter
  /// gating、不額外等待 _epubPositionInfo 的簡化決策（見 issues.md Issue 7
  /// 「進度/跳頁鈕」段落）。
  void _openFoliateProgressSheet() {
    final positionInfo = _epubPositionInfo;
    _showThemedModalBottomSheet<void>(
      builder: (_) => SafeArea(
        child: positionInfo == null
            ? const SizedBox.shrink()
            : _buildFoliateEpubFooter(positionInfo),
      ),
    );
  }

  /// PDF「進度/跳頁」浮動按鈕開啟的 Bottom Sheet（epic-24-pdf-engine-rebuild
  /// Issue 8）：內容直接沿用既有 `ReaderFooter`（原本 in-flow 常駐畫面
  /// 底部，現改為浮動按鈕觸發顯示，不再擠壓可視閱讀區域高度，比照 EPUB
  /// `_openFoliateProgressSheet` 既有機制）。`_pdfPageInfo` 為 null（
  /// `onPageChanged` 尚未觸發過）時顯示空白 Sheet，比照
  /// `reader_pdf_progress_button` 本身不額外 gating 的簡化決策（同
  /// `_openFoliateProgressSheet`）。
  void _openPdfProgressSheet() {
    final pageInfo = _pdfPageInfo;
    _showThemedModalBottomSheet<void>(
      builder: (_) => SafeArea(
        child: pageInfo == null
            ? const SizedBox.shrink()
            : ReaderFooter(
                currentPage: pageInfo.pageIndex + 1,
                totalPages: pageInfo.totalPages,
                onPageChanged: (page1Indexed) {
                  PdfReaderView.jumpToPage(
                      _pdfReaderViewKey, page1Indexed - 1);
                },
              ),
      ),
    );
  }

  /// 流式 EPUB（FoliateReaderView）頁尾（epic-17-epub-render-migration
  /// Issue 6）：直接使用原生端 relocate 事件回報的 pageIndex／totalPages
  /// （foliate-js SectionProgress.getProgress() 的 location.current／
  /// location.total，近似頁碼概念，非精確渲染頁數，見 spec.md「頁碼
  /// 估算」）。pageIndex 為 0-indexed（比照原生端既有慣例），ReaderFooter
  /// 要求 1-indexed，此處 +1 換算。onPageChanged 透過既有
  /// jumpToProgression（Issue 5）換算目標頁對應的全書進度比例（近似值，
  /// 非精確反解頁碼）。
  Widget _buildFoliateEpubFooter(EpubPositionInfo info) {
    final totalPages = info.totalPages ?? 0;
    if (totalPages <= 0) return const SizedBox.shrink();
    final currentPage = ((info.pageIndex ?? 0) + 1).clamp(1, totalPages);
    return ReaderFooter(
      currentPage: currentPage,
      totalPages: totalPages,
      onPageChanged: (page1Indexed) {
        final progression =
            totalPages > 0 ? (page1Indexed - 1) / totalPages : 0.0;
        FoliateReaderView.jumpToProgression(
            _foliateEpubReaderViewKey, progression);
      },
    );
  }

  /// 流式 EPUB 顯示時的內容前景/背景色，來自 `Theme.of(context)`
  /// （已解析後的最終 `AppTheme`/E-Ink 高對比結果，見
  /// `resolveThemeData()`）；EPUB 固定版面顯示時回傳 `null`——固定
  /// 版面內容是圖片，無法預期背景色，強制上色沒有意義。呼叫端依情境
  /// 決定 `null` 時的退回值（epic-22-reader-theme-integration Issue 1：
  /// `FoliateReaderView` 直接傳 `null`；Issue 2 的頁首/頁尾會退回
  /// 既有寫死 `Colors.black`，不在本 Task 範圍）。
  Color? get _themedTextColor =>
      _isFixedLayout ? null : Theme.of(context).colorScheme.onSurface;
  Color? get _themedBackgroundColor =>
      _isFixedLayout ? null : Theme.of(context).scaffoldBackgroundColor;

  /// 浮動控制按鈕（返回/目錄/版面設定/書籤/筆記/進度）的底色/圖示色，
  /// 跟隨 Theme.of(context)（epic-22-reader-theme-integration Issue 3）。
  /// 顯示流式 EPUB 時使用主題色——**底色刻意取 `colorScheme.onSurface`
  /// （而非 `surface`）**：`surface` 在淺色/深色主題下分別接近純白/接近
  /// 頁面背景本身（見 app_theme_data.dart），若拿來當按鈕底色，淺色主題
  /// 下會讓按鈕在近白頁面上幾乎隱形（重蹈 Issue 5 才修過的「控制元件顏色
  /// 跟頁面背景太接近而失去可視性」問題）。`onSurface` 在淺色主題下是
  /// 近黑色、深色主題下是近白色，天生就與同一主題的頁面背景形成對比。
  /// 圖示色相應取 `colorScheme.surface`（與底色反向搭配，維持圖示對底色
  /// 的可視對比）。**底色不透明、不加透明度**（epic-22-reader-theme-
  /// integration Issue 4 電子紙硬體對比追加修正）：原本沿用改動前
  /// `Colors.black54` 的 54% 透明度，在一般 LCD/OLED 顯示器上運算出的
  /// 混合中間灰看起來沒問題，但真機電子紙硬體肉眼實測發現，這個「即時
  /// 運算出來的中間灰」正好落在電子紙灰階抖動渲染最弱的區間，圖示完全
  /// 無法辨識形狀；改用不透明實色色塊後，即使被電子紙抖動處理，仍是
  /// 「一塊清楚色塊 vs. 另一塊清楚色塊」的二元對比。顯示 EPUB 固定版面
  /// （漫畫）時維持既有寫死 Colors.black54/Colors.white——理由同
  /// _themedTextColor：固定版面頁面內容本身不受本 Epic 影響（通常是
  /// 白底圖片），深色主題下若控制按鈕也跟著變色，容易在不可預期的圖片
  /// 背景上失去可視對比（與 Issue 1/2 的 getter 不同，這裡沒有「不適用」
  /// 的情境，故不用 Color? + ?? fallback 模式，兩個分支各自直接回傳明確
  /// 的顏色）。
  Color get _themedFabBackgroundColor =>
      _isFixedLayout ? Colors.black54 : Theme.of(context).colorScheme.onSurface;
  Color get _themedFabIconColor =>
      _isFixedLayout ? Colors.white : Theme.of(context).colorScheme.surface;

  Widget _buildNativeView(BookFormat format, bool isLandscape) {
    final resolved = _resolved!;
    switch (format) {
      case BookFormat.epub:
      case BookFormat.azw3:
      case BookFormat.cbz:
      case BookFormat.txt:
      case BookFormat.md:
        // Epic 11 Issue 4：TXT 與 EPUB/AZW3/CBZ 共用同一個
        // FoliateReaderView，建構參數完全相同——TXT 合成後是一份真正的
        // EPUB，isComicBookHint 恆為 false（非 cbz 格式），dualPageDirection
        // 對流式格式無意義但傳入無害（main.js 僅在 isComicBookHint===true
        // 時讀取它，見 Issue 3 main.js 註解）。
        return FoliateReaderView(
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
          letterSpacing: resolved.letterSpacing,
          marginTop: resolved.marginTop,
          marginBottom: resolved.marginBottom,
          marginLeft: resolved.marginLeft,
          marginRight: resolved.marginRight,
          textAlign: resolved.textAlign,
          publisherStyles: resolved.publisherStyles,
          columnMode: resolved.columnMode,
          columnSize: resolved.columnSize,
          showFooter: resolved.showFooter,
          isFixedLayoutHint: widget.isFixedLayout,
          textColor: _themedTextColor,
          backgroundColor: _themedBackgroundColor,
          dualPageMode: resolved.dualPageMode,
          isLandscape: isLandscape,
          customFonts: _customFonts,
          navZoneActions: resolved.navZoneActions,
          onZoneAction: _handleZoneAction,
          showNavZoneDebugOverlay: resolved.showNavZoneDebugOverlay,
          consoleLogEnabled: resolved.consoleLogEnabled,
          initialLocatorJson: _initialPosition?.epubLocatorJson,
          isComicBookHint: format == BookFormat.cbz,
          dualPageDirection: resolved.dualPageDirection,
          onLocatorChanged: (info) {
            if (!mounted) return;
            setState(() => _epubPositionInfo = info);
          },
          onSelectionChanged: _handleSelectionChanged,
          onSelectionCleared: _handleSelectionCleared,
          onAnnotationActivated: _handleAnnotationActivated,
        );
      case BookFormat.pdf:
        // epic-24-pdf-engine-rebuild：單頁/雙頁（Issue 2）、影像濾鏡/
        // 裁切（Issue 3）、劃線選取回呼（Issue 4）、導航熱區（Issue 8）
        // 皆已補回。
        return PdfReaderView(
          key: _pdfReaderViewKey,
          filePath: widget.filePath,
          initialPageIndex: _initialPosition?.pdfPageIndex,
          onPageRendered: _handlePageRendered,
          onError: _handleError,
          dualPageMode: resolved.dualPageMode,
          dualPageCoverAlone: resolved.dualPageCoverAlone,
          dualPageDirection: resolved.dualPageDirection,
          pdfPageTurnAnimation: resolved.pdfPageTurnAnimation,
          isLandscape: isLandscape,
          pdfContrast: resolved.pdfContrast,
          pdfBrightness: resolved.pdfBrightness,
          pdfBoldStrength: resolved.pdfBoldStrength,
          pdfCropMode: resolved.pdfCropMode,
          pdfCropRect: resolved.pdfCropRect,
          cropEditModeActive: _cropEditModeActive,
          onCropRectComputed: (rect) => _handlePrefsChanged(
            _prefs.copyWith(pdfCropRect: rect),
          ),
          onSelectionRectComputed: _handlePdfSelectionRectComputed,
          onSelectionCanceled: _handlePdfSelectionCanceled,
          navZoneActions: resolved.navZoneActions,
          onZoneAction: _handleZoneAction,
          showNavZoneDebugOverlay: resolved.showNavZoneDebugOverlay,
          onPageChanged: (info) {
            if (!mounted) return;
            setState(() => _pdfPageInfo = info);
          },
        );
      case BookFormat.unknown:
        return const SizedBox.shrink();
    }
  }

  /// 熱區動作統一分派入口（epic-7-interaction Issue 4，Issue 5 擴充 EPUB
  /// FXL 分支）：`previousPage`/`nextPage` 呼叫目前格式對應的既有換頁方法；
  /// `menu` 切換 [_chromeVisible]（沉浸模式）；`none` 不做事。
  /// **`previousPage`/`nextPage` 刻意不影響 [_chromeVisible]**（design.md
  /// 決策 #14）。EPUB 分支的 `previousPage`/`nextPage` 自 epic-20 Issue 2
  /// 起，不論 FXL 或流式一律呼叫 `FoliateReaderView.previousPage`/
  /// `nextPage`——3×3 熱區是 Dart 端 `Stack` 疊加層，`onTap` 直接回呼
  /// [onZoneAction]（見 `_buildNativeView()` 接線），不經過原生端判讀。
  /// epic-20 Issue 5 已刪除的舊 `EpubReaderView.kt`／原生 `InputListener`
  /// 座標換算機制與此無關，本方法從未依賴它。原生端
  /// `MainActivity.dispatchKeyEvent()` 攔截音量鍵後的回呼
  /// （epic-7-interaction Issue 7）：方向固定映射，不查詢
  /// `_resolved!.navZoneActions`（design.md 決策 #19）——`up` 一律上一頁、
  /// `down` 一律下一頁。全域音量鍵開關關閉時（`_resolved?.volumeKeyEnabled
  /// == false`，epic-14-system-settings Issue 4）忽略此次觸發。
  /// **epic-27-reader-device-compat Issue 1**：`previousPage`/`nextPage`
  /// 於 `_state == _RenderState.loading`（書籍仍在載入中）時直接忽略，
  /// 避免 EPUB 端 `window.previousPage`/`nextPage` 賦值早於 `view.renderer`
  /// 真正建立的空窗期被觸控命中而拋出 JS 例外、被 `_handleError()` 誤判
  /// 為崩潰畫面（見 `reviews/bugfix-repro.md` Issue 1）。`menu` 動作不受
  /// 影響——它只切換 Dart 端 `_chromeVisible`，不呼叫任何 JS/native API，
  /// 無此風險。
  Future<void> _handleVolumeKeyCall(MethodCall call) async {
    if (call.method != 'onVolumeKey') return;
    if (_resolved?.volumeKeyEnabled == false) return;
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
        if (_state == _RenderState.loading) return;
        if (format == BookFormat.pdf) {
          PdfReaderView.previousPage(_pdfReaderViewKey);
          // Epic 24 Issue 10：PDF 框選狀態是純 Dart 端矩形選取，沒有
          // EPUB 那種 WebView 切頁自動清空 window.getSelection() 的
          // 瀏覽器原生語意可依賴，換頁時需主動清除既有選取與工具列，
          // 避免選取範圍/AnnotationToolbar 殘留在已經翻過的頁面上。
          if (_currentPdfSelection != null) _handlePdfSelectionCanceled();
          // 審查修正：換頁當下若長按拖曳框選仍進行中（尚未放開手指），
          // 上面的 guard 不會觸發（_currentPdfSelection 此時仍是
          // null），但 PdfReaderView 內部進行中的拖曳狀態不受換頁影響，
          // 放開手指後仍會用換頁前的舊頁面座標重新彈出 Toolbar，一併
          // 中止它，見 PdfReaderView.cancelActiveSelectionDrag 文件。
          PdfReaderView.cancelActiveSelectionDrag(_pdfReaderViewKey);
        } else if (isFoliateFormat(format)) {
          // Epic 11 Issue 2：KF8 (AZW3) 與 EPUB 共用 FoliateReaderView。
          FoliateReaderView.previousPage(_foliateEpubReaderViewKey);
        }
        break;
      case ZoneAction.nextPage:
        if (_state == _RenderState.loading) return;
        if (format == BookFormat.pdf) {
          PdfReaderView.nextPage(_pdfReaderViewKey);
          // Epic 24 Issue 10：理由同上方 previousPage 分支。
          if (_currentPdfSelection != null) _handlePdfSelectionCanceled();
          // 審查修正：理由同上方 previousPage 分支。
          PdfReaderView.cancelActiveSelectionDrag(_pdfReaderViewKey);
        } else if (isFoliateFormat(format)) {
          // Epic 11 Issue 2：KF8 (AZW3) 與 EPUB 共用 FoliateReaderView。
          FoliateReaderView.nextPage(_foliateEpubReaderViewKey);
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
