import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import 'package:clock/clock.dart';
import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';

import '../reader/annotation_list_item.dart';
import '../reader/annotation_resolution.dart';
import '../reader/annotation_session.dart';
import '../reader/book_format.dart';
import '../reader/bookmark.dart';
import '../reader/bookmark_position_context.dart';
import '../reader/bookmark_toggle.dart' as bookmark_toggle;
import '../reader/bookmarks_repository.dart';
import '../reader/book_reader_prefs.dart';
import '../reader/app_font.dart';
import '../reader/available_fonts.dart';
import '../reader/custom_font.dart';
import '../reader/custom_fonts_repository.dart';
import '../reader/downloadable_font_store.dart';
import '../reader/epub_decoration.dart';
import '../reader/epub_position_info.dart';
import '../reader/epub_selection_info.dart';
import '../reader/foliate_bridge_codec.dart';
import '../reader/foliate_reader_view.dart';
import '../reader/tts_audio_focus_coordinator.dart';
import '../reader/tts_audio_focus_source.dart';
import '../reader/tts_audio_handler.dart';
import '../reader/tts_audio_player.dart';
import '../reader/tts_controller.dart';
import '../reader/tts_provider.dart';
import '../library/models/book.dart';
import '../library/models/book_group.dart';
import '../library/models/library_enums.dart';
import '../library/book_import_service.dart';
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
import '../reader/reading_position_saver.dart';
import '../storage/storage_access_probe.dart'
    show StorageAccessProbeResult, probeStorageAccess;
import '../reader/open_book_flow.dart';
import '../reader/reader_console_log.dart';
import '../reader/reader_jump_target.dart';
import '../reader/reader_prefs_manager.dart';
import '../reader/toc_entry.dart';
import '../reader/toc_navigator.dart';
import '../reader/resolve_text_conversion.dart';
import '../reader/text_conversion.dart';
import '../reader/text_conversion_mode.dart';
import '../reader/resolved_preferences.dart';
import '../reader/screen_orientation_setting.dart';
import '../reader/writing_mode.dart';
import '../reader/reader_activity_tracker.dart';
import '../reader/zone_action.dart';
import '../search/search_repository.dart';
import '../stats/reading_stats_repository.dart';
import '../stats/reading_stats_tracker.dart';
import '../sync/sync_checkpoint_trigger.dart';
import '../theme/elink_tokens.dart';
import 'annotation_toolbar.dart';
import 'support/book_import_picker_helper.dart'
    show SingleBookFilePicker, pickSingleBookFileViaFilePicker;
import 'note_edit_dialog.dart';
import 'notes_bottom_sheet.dart';
import 'book_search_screen.dart';
import 'fxl_settings_sheet.dart';
import 'library_screen_dependencies.dart';
import 'layout_preset_book_picker_screen.dart';
import 'layout_preset_name_dialog.dart';
import 'pdf_settings_sheet.dart';
import '../reader/book_reader_prefs_repository.dart';
import '../reader/layout_preset.dart';
import '../reader/layout_preset_repository.dart';
import '../reader/layout_preset_actions.dart' as layout_preset_actions;
import 'reader_chrome_bottom_bar.dart';
import 'reader_footer.dart';
import 'reader_settings_sheet.dart';
import 'toc_bottom_sheet.dart';
import 'pdf_search_panel.dart';
import 'pdf_thumbnail_panel.dart';
import 'tts_panel.dart';
import 'reader_chrome_top_bar.dart';

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
  final String? bookTitle;
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
  /// 可選參數——比照 [bookmarksRepository] 既有慣例，未提供時自訂字型
  /// 視為空清單（可用字型只剩已下載的內建字型）。
  final CustomFontsRepository? customFontsRepository;

  /// 可下載字型的存放與查詢（epic-49 Issue 4）。刻意為可選參數，比照
  /// [customFontsRepository] 既有慣例：未提供時已下載字型視為空集合、開書不等待，
  /// 偏好為內建字型時會視為未下載而退回書本字型（epic-54 Issue 1，與設定面板
  /// 顯示一致，偏好本身不改寫），自訂字型不受影響。
  final DownloadableFontStore? downloadableFontStore;

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

  /// 語音朗讀（TTS）的語音來源（epic-34-tts-readalong Issue 2）。刻意為
  /// 可選參數——比照 [bookmarksRepository] 既有慣例，未提供時朗讀播放
  /// 按鈕不顯示，行為等同本 Issue 之前，零回歸。CBZ 格式即使提供本參數
  /// 也會顯示明確停用狀態的按鈕（非隱藏，見 `issues.md` Issue 2 驗收
  /// 標準），因為 CBZ 是純圖像格式、沒有文字可朗讀。
  final TtsProvider? ttsProvider;
  final TtsAudioHandler? ttsAudioHandler;
  final TtsAudioFocusSource? ttsAudioFocusSource;

  /// E-Ink 高對比模式（epic-34-tts-readalong Issue 8）：App 層級主題設定
  /// （見 `main.dart`／`LibraryThemeDependencies.isEinkMode`），由
  /// [LibraryScreen._openBook] 貫穿傳入。目前唯一用途是朗讀高亮的視覺
  /// 呈現方式——[onHighlightSegment] 呼叫
  /// `FoliateReaderView.showTtsHighlight()` 時傳入的 `einkMode` 參數，
  /// E-Ink 模式下改用靜態高對比色，非既有半透明色。非 nullable，預設
  /// `false`：這是既有 App 層級設定值的直接貫穿，不是「未提供時功能不
  /// 啟用」的可選功能旗標（比照 [FoliateReaderView.isLandscape] 既有
  /// 非 nullable＋預設值模式）。
  final bool isEinkMode;

  /// 供背景全文檢索排程器（epic-10-search Issue 1）得知「目前有閱讀畫面
  /// 開啟」而暫停處理，避免與使用者正在閱讀互搶資源。刻意為可選參數——
  /// 比照 [bookmarksRepository] 既有慣例，未提供時零回歸（單純不通知任何
  /// tracker，行為等同本 Issue 之前）。
  final ReaderActivityTracker? readerActivityTracker;

  /// 全庫搜尋跳轉目標（epic-10-search Issue 5，spec.md §6）：非 `null`
  /// 時，開書當下傳給底層 View 的初始定位參數改用本欄位（優先權高於
  /// 資料庫既有 `lastPosition`），除此之外不影響任何後續行為——後續翻頁
  /// /checkpoint 寫入與一般開書完全同構，不新增任何「暫停進度儲存」旗標
  /// （見 `_maybeShowSearchJumpHighlight()` 文件註解的完整理由）。刻意為
  /// 可選參數——比照 `readerActivityTracker` 既有慣例，未提供時零回歸。
  final ReaderJumpTarget? initialJumpTarget;

  /// 全庫搜尋的資料存取層（epic-10-search Issue 8，spec.md §9.4）：供
  /// TopBar「搜尋內文」按鈕開啟 [BookSearchScreen] 使用。刻意為可選
  /// 參數——比照 [readerActivityTracker] 既有慣例，未提供時點擊搜尋按鈕
  /// 顯示「搜尋功能暫時無法使用」提示、不導覽，行為等同本 Issue 之前，
  /// 零回歸。
  final SearchRepository? searchRepository;

  /// 本裝置系統 SQLite 是否有 FTS5 模組可用（epic-10-search Issue 6／
  /// Issue 8，spec.md §9.4）：由呼叫端從
  /// `LibraryReaderFeatureRepositories.isFullTextSearchAvailable` 往下
  /// 傳遞，供 [_openBookSearch] 建構 [BookSearchScreen] 的
  /// `readerFeatureRepositories` 時一併帶入，讓無 FTS5 裝置從閱讀器進入
  /// 單書搜尋時也能正確顯示「本裝置不支援全文檢索」優雅降級提示，而非
  /// 靜默落回預設值 `true` 誤發無效 FTS 查詢。非 nullable，預設 `true`
  /// ——比照 [LibraryReaderFeatureRepositories.isFullTextSearchAvailable]
  /// 既有預設值，維持既有測試呼叫端零回歸。
  final bool isFullTextSearchAvailable;

  /// epic-15-storage-permission Issue 0：書籍匯入服務，由
  /// `LibraryReaderFeatureRepositories.bookImportService` 經
  /// `buildReaderScreen` 轉交。供 Issue 2「檔案存取失效時重新連結書籍」
  /// 使用；`null` 時不提供重新連結功能（比照 [libraryRepository] 等既有
  /// 選用依賴的慣例，既有測試呼叫端零回歸）。
  final BookImportService? bookImportService;

  /// epic-15-storage-permission Issue 2：「重新選取檔案」使用的單檔選擇器；
  /// `null` 時使用 [pickSingleBookFileViaFilePicker]。供 widget test 注入，
  /// 不必觸碰平台實作。
  final SingleBookFilePicker? pickSingleBookFile;

  /// epic-9-stats Issue 4：每日閱讀統計的存取層（由
  /// `LibraryReaderFeatureRepositories.readingStatsRepository` 經
  /// `buildReaderScreen` 轉交）。未提供 [readingStatsTracker] 時，以本書的
  /// id、書名與這個 repository 建立會話級計時器；兩者皆為 `null` 則完全不
  /// 計時，行為與現況相同。
  final ReadingStatsRepository? readingStatsRepository;

  /// epic-9-stats Issue 4：直接注入的計時器（測試用）。優先於
  /// [readingStatsRepository]。**由 [ReaderScreen] 擁有**：離開閱讀器時
  /// 由它呼叫 `flushAndClose()` 結算並關閉，呼叫端不需要（也不應）另外釋放。
  final ReadingStatsTracker? readingStatsTracker;

  const ReaderScreen({
    super.key,
    required this.filePath,
    required this.bookId,
    required this.prefsManager,
    this.bookmarksRepository,
    this.highlightsRepository,
    this.notesRepository,
    this.bookTitle,
    this.bookAuthor,
    this.bookProgress = 0.0,
    this.isFixedLayout,
    this.libraryRepository,
    this.customFontsRepository,
    this.downloadableFontStore,
    this.layoutPresetRepository,
    this.bookReaderPrefsRepository,
    this.syncCheckpointTrigger,
    this.ttsProvider,
    this.ttsAudioHandler,
    this.ttsAudioFocusSource,
    this.isEinkMode = false,
    this.readerActivityTracker,
    this.initialJumpTarget,
    this.searchRepository,
    this.isFullTextSearchAvailable = true,
    this.bookImportService,
    this.pickSingleBookFile,
    this.readingStatsRepository,
    this.readingStatsTracker,
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

  /// 供測試直接呼叫 [_ReaderScreenState._openSleepTimerPicker]（epic-38-
  /// reader-chrome-tts-redesign Issue 2，計劃範圍澄清第 3 點）：真正的
  /// UI 觸發入口 `TtsPanel.onSleepTimerTap` 只有在 `TtsController.status`
  /// 離開 `idle` 後才會出現在畫面上，但 `flutter_test` 環境下
  /// `FoliateReaderView.loadTtsSegments()` 恆回傳空清單（見
  /// `_ttsControllerOrNull` 文件註解既有的「誠實測試邊界」），`play()`
  /// 永遠無法真正離開 `idle`，導致 `TtsPanel` 在 widget test 環境下結構性
  /// 不可能出現。比照既有 [togglePdfBookmark]／[openPdfToc]「對應真實
  /// 觸發入口在測試環境下不可達」的既有模式新增本 helper，讓睡眠定時器
  /// 的 `Timer`／Bottom Sheet 選項邏輯本身仍可被完整測試。[key] 對應的
  /// State 若尚未掛載，靜默忽略。
  static void openSleepTimerPickerForTest(GlobalKey<State<ReaderScreen>> key) {
    final state = key.currentState;
    if (state is _ReaderScreenState) {
      state._openSleepTimerPicker();
    }
  }

  /// 供測試直接回報「TTS 是否正在播放」給閱讀統計計時器
  /// （epic-9-stats Issue 4）：`flutter_test` 環境下 `TtsController` 永遠停在
  /// idle（見 [openSleepTimerPickerForTest] 的同類說明），無法經
  /// `_onTtsStatusChanged` 自然觸發，比照該入口新增。[key] 對應的 State
  /// 若尚未掛載，靜默忽略。
  static void reportTtsPlayingForTest(
    GlobalKey<State<ReaderScreen>> key,
    bool isPlaying,
  ) {
    final state = key.currentState;
    if (state is _ReaderScreenState) {
      state._forwardTtsPlaying(isPlaying);
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

class _ReaderScreenState extends State<ReaderScreen> with WidgetsBindingObserver {
  // ── PDF 內文搜尋狀態（epic-24 Issue 6）──
  final _pdfSearchStateNotifier = ValueNotifier<PdfSearchState>(const PdfSearchState.initial());
  List<PdfSearchMatch> _pdfSearchMatches = const [];
  int _pdfSearchRequestId = 0;

  /// 目前實際開啟的檔案路徑；「重新連結」成功後由 [_openBookFlow] 換成新路徑。
  /// 刻意不在 `didUpdateWidget` 跟隨建構參數 `filePath` 的變動：閱讀器一律由
  /// `MaterialPageRoute` 建立一次，沒有任何呼叫端會以不同 `filePath` 重建
  /// 同一個 `ReaderScreen`。
  String get _activeFilePath => _openBookFlow.filePath;

  /// 開書流程（見 CONTEXT.md「開書流程」）。在 `initState` 最前面建立，
  /// 因為 [_activeFilePath] 在其後的 `_resolveEpubEngineDispatch()` 就會讀取。
  late final OpenBookFlow _openBookFlow;
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
  // CBZ 專屬的 TtsPanel 展開/收合手動旗標（epic-38-reader-chrome-tts-
  // redesign Issue 2）：CBZ 為純圖像格式，_ttsControllerOrNull 刻意不對
  // 它建構（避免白白配置用不到的播放器資源，見該 getter 文件註解），故
  // 沒有真正的 TtsController.status 可供衍生顯示狀態——只有 CBZ 需要這個
  // 手動旗標，一般格式改用 _buildBottomChrome() 依 controller.status
  // 衍生切換，不受本旗標影響。
  bool _cbzTtsPanelVisible = false;
  // TtsPanel「收合」子狀態（epic-38-reader-chrome-tts-redesign
  // Issue 2）：只影響展開列是否顯示，不影響朗讀播放本身，格式無關
  // （CBZ 的裝飾面板與一般格式共用同一個旗標）。
  bool _ttsPanelCollapsed = false;
  // FXL 懸浮「🔖 書籤 toggle」按鈕圖示所需的最小狀態快取
  // （epic-6-annotations Issue 4）：與 NotesBottomSheet 內部「🔖 書籤」
  // 分頁各自獨立載入自己的清單（比照既有分頁按鈕 toggle 與 Bottom Sheet
  // 清單各自管理狀態的既定模式），只負責懸浮按鈕圖示的二態顯示。載入
  // 時機見 _handleLayoutResolved（初次開書）／_openNotesSheet（Bottom
  // Sheet 關閉後重新整理，使用者可能在分頁裡新增/刪除書籤）。
  List<Bookmark> _fxlBookmarks = [];
  // 版面設定預設集清單快取（epic-28-reader-settings-enhancements
  // Issue 3），開書時載入一次，比照既有一次性載入快取模式；
  // 另存/覆蓋/刪除完成後重新載入。
  List<LayoutPreset> _layoutPresets = [];
  // 可用字型（epic-54 Issue 1，見 CONTEXT.md「可用字型」）：已下載的內建字型加自訂
  // 字型，開書時各載入一次，閱讀期間不會改變（字型管理畫面不在閱讀器內，下載或
  // 刪除都要離開閱讀器）。兩邊都讀完（任一邊失敗視為空集合）才組出，在那之前為
  // null。FoliateReaderView 的初始網址（內含 @font-face）是 late final，提早建構
  // 就再也不會套用字型，所以 _buildBody 在 null 時延後建構閱讀器（取代原本的
  // 兩個載入旗標）。兩個來源都沒提供
  // （測試與舊呼叫端）時沒有東西要等，一開始就是 empty。
  late AvailableFonts? _availableFonts =
      widget.customFontsRepository == null && widget.downloadableFontStore == null
          ? AvailableFonts.empty
          : null;
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
  TtsController? _ttsController;
  TtsAudioFocusCoordinator? _ttsAudioFocusCoordinator;
  // 安全視窗跟隨翻頁節流（epic-34-tts-readalong Issue 11 真機驗收發現）：
  // 長段落（尤其直排、欄寬窄）朗讀進度快時，main.js 安全視窗檢查可能在
  // 極短時間內連續多次判定「需要翻頁」，若不加節流會連續多次呼叫
  // FoliateReaderView.nextPage()/previousPage()——真機實測發現直排在
  // 前一次翻頁動畫（paginator.js 內部轉場約 300ms）尚未播完時疊加下一次
  // 觸發，畫面會卡住不再更新（橫排耐受度較高，仍會動但斷頁位置不穩定）。
  // 手動點擊翻頁不受影響（真機已確認正常）——這個節流只作用於 TTS 自動
  // 觸發的路徑。冷卻時間 400ms（略高於動畫時長，留一點餘裕）。
  DateTime? _lastTtsPageTurnAt;
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
  // Epic 43 Issue 1：EPUB／PDF 共用的劃線/備註 CRUD 深模組，僅在兩個
  // repository 皆非 null 時建構，否則為 null（呼叫端統一 guard）。
  late final AnnotationSession? _annotationSession =
      (widget.highlightsRepository != null && widget.notesRepository != null)
          ? AnnotationSession(
              highlightsRepository: widget.highlightsRepository!,
              notesRepository: widget.notesRepository!,
              bookId: widget.bookId,
            )
          : null;
  // 開書時讀到的既有位置記錄（若有），只在 initState 賦值一次，之後
  // 不變——僅用於 _buildNativeView() 建構 EpubReaderView/PdfReaderView
  // 時傳入 initialLocatorJson/initialPageIndex 這兩個一次性開書起始值。
  ReadingPosition? _initialPosition;
  // 與 [_initialPosition] 同時在偏好載入完成時建立；閱讀視圖只在 `_resolved`
  // 非 null 後才建構，所以回呼內正常情況下已存在；回呼與 `dispose`／`paused`
  // 一律以 `?.` 呼叫，與 `_loaded` 尚未載入時的其他早退路徑保持一致，不使用 `!`。
  ReadingPositionSaver? _positionSaver;
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

  /// 搜尋跳轉暫態高亮 3 秒生命週期計時器（epic-10-search Issue 5，
  /// spec.md §6）。非 `null` 代表目前有顯示中的暫態高亮，
  /// [_handleZoneAction] 於任何翻頁/點擊動作發生時會提前呼叫
  /// [_clearSearchJumpHighlight]，取 3 秒與提前清除兩者較早發生者。刻意
  /// 使用裸 `Timer`（不引入 `package:clock`）——理由見本計畫 Global
  /// Constraints。
  Timer? _searchJumpHighlightTimer;

  /// 避免 [_handlePageRendered] 在極端情況下被呼叫超過一次時重複觸發
  /// 暫態高亮、重新啟動 3 秒計時——`initialJumpTarget` 只在開書當下這一
  /// 次性場景生效（spec.md §6）。
  bool _searchJumpHighlightTriggered = false;

  /// 捕捉建立時的 Zone，確保搜尋跳轉 Timer 恆在 fake-async Zone 內建立，
  /// 即使 `_handlePageRendered` 本身是在 `tester.runAsync` 的真實 Zone
  /// 內被觸發（`pumpUntilPdfReady` 為了等待 pdfrx 真實 I/O，會暫時離開
  /// fake Zone），Timer 仍會是 fake Timer，才能被 `tester.pump(duration)`
  /// 正確推進（見 Task 4 測試對 `pumpUntilPdfReady` 與 Timer 互動的註解）。
  late Zone _creationZone;

  /// 本次開書的閱讀統計計時器（epic-9-stats Issue 4）；兩個統計參數皆未提供
  /// 時為 `null`（完全不計時）。本 State 只負責轉送事件，不含任何計時邏輯。
  ReadingStatsTracker? _readingStatsTracker;

  @override
  void initState() {
    super.initState();
    _creationZone = Zone.current;
    final importService = widget.bookImportService;
    _openBookFlow = OpenBookFlow(
      filePath: widget.filePath,
      // 讀取頂層可覆寫變數的當下值，widget test 才能以覆寫注入假探測。
      probe: (uri) => probeStorageAccess(uri),
      relinkBook: importService == null
          ? null
          : (uri, displayName) => importService.relinkBook(
                widget.bookId,
                uri,
                displayName: displayName,
              ),
    )..addListener(_onOpenBookFlowChanged);
    widget.readerActivityTracker?.markReaderOpened();
    _readingStatsTracker = _createReadingStatsTracker();
    WidgetsBinding.instance.addObserver(this);
    _volumeKeyChannel.setMethodCallHandler(_handleVolumeKeyCall);
    _resolveEpubEngineDispatch();
    _loadAvailableFonts();
    _loadLayoutPresets();
    final syncCheckpointTrigger = widget.syncCheckpointTrigger;
    if (syncCheckpointTrigger != null) {
      _syncCheckpointTimer = Timer.periodic(
        const Duration(minutes: 5),
        (_) => syncCheckpointTrigger.trigger(),
      );
    }
    _openBookFlow.start();
    widget.prefsManager.load(widget.bookId).then((loaded) {
      if (!mounted) return;
      setState(() {
        _prefs = loaded.bookPrefs;
        _loaded = loaded;
        _initialPosition = loaded.readingPosition;
        _positionSaver = ReadingPositionSaver(
          bookId: widget.bookId,
          prefsManager: widget.prefsManager,
          hasJumpTarget: widget.initialJumpTarget != null,
          initialProgress: loaded.readingPosition.progress,
        );
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
    final format = detectBookFormat(_activeFilePath);
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
        .detectAndCacheEpubLayout(widget.bookId, _activeFilePath)
        .then((result) {
      if (!mounted) return;
      setState(() => _dispatchedIsFixedLayout = result);
    });
  }

  /// [_openBookFlow] 狀態變動時重繪。
  void _onOpenBookFlowChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.readerActivityTracker?.markReaderClosed();
    // 退出閱讀器：結算閱讀統計尾段並寫入（epic-9-stats Issue 4）。不 await
    // ——dispose() 是同步方法，比照下方 ReadingPositionSaver.save 的既有慣例；
    // 寫入失敗由 tracker 內部吞下並記診斷日誌，不影響離開閱讀器。
    final statsTracker = _readingStatsTracker;
    if (statsTracker != null) unawaited(statsTracker.flushAndClose());
    _syncCheckpointTimer?.cancel();
    _openBookFlow
      ..removeListener(_onOpenBookFlowChanged)
      ..dispose();
    _searchJumpHighlightTimer?.cancel();
    _ttsSleepTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _volumeKeyChannel.setMethodCallHandler(null);
    _pdfSearchStateNotifier.dispose();
    _ttsAudioFocusCoordinator?.dispose();
    widget.ttsAudioHandler?.detachController();
    _ttsController?.removeListener(_onTtsStatusChanged);
    _ttsController?.dispose();
    // 離開閱讀畫面時觸發一次位置寫入（spec.md「本機閱讀位置記憶」寫入
    // 時機之一）。不 await——dispose() 是同步方法，且這是離開畫面前的
    // 最後一次呼叫，不需要等待其完成，比照既有 _handlePrefsChanged 不
    // await saveBookPrefs 的既有慣例。
    _positionSaver?.save(detectBookFormat(_activeFilePath));
    // epic-8-sync Issue 6（spec.md「同步引擎」checkpoint 觸發來源之
    // 「書籍切換」）：離開閱讀畫面視為一次書籍切換，觸發一次 checkpoint。
    // 排在 ReadingPositionSaver.save 之後，讓剛寫入的最新閱讀位置有較高
    // 機率被這次 checkpoint 一併判定為待推送——但兩者皆是 fire-and-
    // forget（不 await），呼叫順序並不「保證」上一行的 SQLite 寫入已經
    // 真正落地；即使極端情況下寫入尚未完成，也只是延後到下一次任何
    // checkpoint 才會被推送，不會遺失資料（審查意見 Important #1，
    // 2026-08-04 `/superpowers:requesting-code-review`）。不 await，理由
    // 同上一行 ReadingPositionSaver.save，dispose() 是同步方法；未登入或
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

  /// 建立本次開書的閱讀統計計時器（epic-9-stats Issue 4）：有注入的
  /// [ReaderScreen.readingStatsTracker] 直接使用；否則有
  /// [ReaderScreen.readingStatsRepository] 就以本書 id、書名（原始書名，
  /// 不經簡繁轉換；未提供時退回 id）與 repository 的寫入方法、`onCleared`
  /// 建立；兩者皆無回傳 `null`（不計時）。
  ReadingStatsTracker? _createReadingStatsTracker() {
    final injected = widget.readingStatsTracker;
    if (injected != null) return injected;
    final repository = widget.readingStatsRepository;
    if (repository == null) return null;
    return ReadingStatsTracker(
      bookId: widget.bookId,
      bookTitle: widget.bookTitle ?? widget.bookId,
      onFlush: (date, bookId, bookTitle, seconds) =>
          repository.addReadingSeconds(
        date: date,
        bookId: bookId,
        bookTitle: bookTitle,
        seconds: seconds,
      ),
      onCleared: repository.onCleared,
    );
  }

  /// 取 locatorJson 中代表「位置」的部分（cfi＋index），忽略會因重排而抖動的
  /// fraction。解析失敗時退回整段字串，行為等同過去的完整比較。
  static String _locatorPositionKey(String locatorJson) {
    try {
      final map = jsonDecode(locatorJson);
      if (map is Map) return '${map['cfi']}|${map['index']}';
    } catch (_) {}
    return locatorJson;
  }

  /// 回報一次閱讀活動（翻頁、捲動、長按劃線）。單純點擊叫出工具列不呼叫。
  void _recordReadingActivity() => _readingStatsTracker?.recordActivity();

  /// 回報 TTS 是否正在播放。tracker 對重複回報相同狀態是冪等的。
  void _forwardTtsPlaying(bool isPlaying) =>
      _readingStatsTracker?.onTtsPlayingChanged(isPlaying);

  /// App 進入背景時觸發一次位置寫入（spec.md「本機閱讀位置記憶」寫入
  /// 時機之二）。只在 [AppLifecycleState.paused]（真正進入背景）觸發，
  /// 不含 [AppLifecycleState.inactive]（如系統對話框短暫遮蓋等過渡狀態）
  /// ——避免非真正離開情境也觸發資料庫寫入。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _readingStatsTracker?.onEnteredBackground();
      _positionSaver?.save(detectBookFormat(_activeFilePath));
    } else if (state == AppLifecycleState.resumed) {
      _readingStatsTracker?.onReturnedToForeground();
      // App 從背景恢復時，Android 系統列可能已被 OS 自動重新顯示，
      // _lastAppliedFullscreen 等值節流防護會誤判不需重套用，故強制清空
      // 快取後無條件重新呼叫一次（epic-19 Issue 1 review Critical 2）。
      _lastAppliedFullscreen = null;
      _applySystemUiMode();
      _ttsController?.resyncHighlight();
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
  ///
  /// [transparentBarrier] 為 `true` 時不論主題一律不加遮罩：版面設定三個
  /// 面板（EPUB／PDF／FXL）用，讓使用者邊調整邊看到上方內文即時變化。
  /// 面板改為不撐滿螢幕後，上方露出的 54% 黑遮罩在 E-Ink 上會抖動成一片
  /// 黑，完全看不到內文（2026-09-28 真機回報）。
  Future<T?> _showThemedModalBottomSheet<T>({
    required WidgetBuilder builder,
    bool enableDrag = true,
    bool transparentBarrier = false,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      enableDrag: enableDrag,
      barrierColor: transparentBarrier ||
              Theme.of(context).brightness == Brightness.dark
          ? Colors.transparent
          : null,
      builder: builder,
    );
  }

  void _openLayoutSettings() {
    StateSetter? setSheetState;
    _showThemedModalBottomSheet<void>(
      transparentBarrier: true,
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
            availableFonts: _availableFonts ?? AvailableFonts.empty,
            bookId: widget.bookId,
            layoutPresets: _layoutPresets,
            isEinkMode: widget.isEinkMode,
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
      transparentBarrier: true,
      enableDrag: false,
      builder: (_) => PdfSettingsSheet(
        prefs: _prefs,
        onChanged: _handlePrefsChanged,
        onRequestManualCrop: _handleRequestManualCrop,
        isEinkMode: widget.isEinkMode,
      ),
    );
  }

  void _openFxlSettings() {
    _showThemedModalBottomSheet<void>(
      transparentBarrier: true,
      builder: (_) => FxlSettingsSheet(
        prefs: _prefs,
        onChanged: _handlePrefsChanged,
        isEinkMode: widget.isEinkMode,
        showTextConversion:
            detectBookFormat(_activeFilePath) != BookFormat.cbz,
      ),
    );
  }

  /// 版面設定預設集「另存為新預設集」（epic-28-reader-settings-
  /// enhancements Issue 3）：命名輸入 → 未滿 3 組直接 insert，已滿 3 組
  /// 跳出覆蓋選單 → 覆蓋前二次確認 → replace，完成後重新載入清單。
  ///
  /// epic-27-reader-device-compat Issue 4：真機回報點擊後畫面完全無反應
  /// （`reviews/bugfix-repro.md` Issue 4），根因無法 100% 確認（可能是
  /// `repository == null`〔階段一〕，也可能是真機環境某處拋出未預期例外
  /// 〔階段二〕），故本次採「提高可觀測性＋防禦性」而非直接臆測修復——
  /// 把兩種原本會靜默失敗的路徑都改成使用者可見的 SnackBar 提示，並保留
  /// debugPrint 供日後若再次收到回報時排查根因。
  Future<void> _handleSaveAsPreset(BookReaderPrefs currentDraft) async {
    final l10n = AppLocalizations.of(context)!;
    final repository = widget.layoutPresetRepository;
    if (repository == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          key: const Key('reader_save_as_preset_repository_unavailable_snackbar'),
          content: Text(l10n.readerSaveAsPresetUnavailableMessage),
        ),
      );
      return;
    }
    try {
      final name = await showLayoutPresetNameDialog(context);
      if (name == null || !mounted) return;
      final filteredPrefs = currentDraft.reflowableEpubFields();
      List<LayoutPreset> updated;
      if (_layoutPresets.length < 3) {
        updated = await layout_preset_actions.insertNewLayoutPreset(
          repository,
          name: name,
          prefs: filteredPrefs,
        );
      } else {
        final target = await _selectPresetToOverwrite();
        if (target == null || !mounted) return;
        final confirmed = await _confirmOverwrite(target.name);
        // I-2（審查修訂）：對話框彈出期間使用者可能退出閱讀器，pop 後
        // State 可能已 unmounted，比照 issues.md I-3／Task 7
        // _applyPrefsToTargets 既有慣例，`!confirmed` 與 `!mounted`
        // 合併檢查。
        if (!confirmed || !mounted) return;
        updated = await layout_preset_actions.overwriteLayoutPreset(
          repository,
          target: target,
          name: name,
          prefs: filteredPrefs,
        );
      }
      if (!mounted) return;
      setState(() => _layoutPresets = updated);
    } catch (e, stackTrace) {
      debugPrint('另存為新預設集失敗：$e\n$stackTrace');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          key: const Key('reader_save_as_preset_error_snackbar'),
          content: Text(l10n.readerSaveAsPresetFailedMessage),
        ),
      );
    }
  }

  Future<LayoutPreset?> _selectPresetToOverwrite() {
    final l10n = AppLocalizations.of(context)!;
    final dateFormat = DateFormat.yMd(Localizations.localeOf(context).toString());
    return showDialog<LayoutPreset>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(l10n.readerOverwritePresetPickerTitle),
        children: [
          ..._layoutPresets.map((preset) => SimpleDialogOption(
                key: Key('layout_preset_overwrite_option_${preset.id}'),
                onPressed: () => Navigator.of(dialogContext).pop(preset),
                child: Text(l10n.readerOverwritePresetOptionLabel(
                  preset.name,
                  dateFormat.format(preset.updatedAt),
                )),
              )),
          SimpleDialogOption(
            key: const Key('layout_preset_overwrite_cancel'),
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.cancel),
          ),
        ],
      ),
    );
  }

  Future<bool> _confirmOverwrite(String name) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.readerConfirmOverwriteTitle),
        content: Text(l10n.readerOverwritePresetConfirmMessage(name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            key: const Key('layout_preset_overwrite_confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.readerConfirmOverwriteTitle),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<bool> _confirmApplyToOtherBooks(int count) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.readerConfirmApplyTitle),
        content: Text(l10n.readerApplyToOthersConfirmMessage(count)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            key: const Key('layout_preset_apply_confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.readerConfirmApplyTitle),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  /// 套用版面設定至一批書籍（epic-28-reader-settings-enhancements Issue 3，
  /// 經 Epic 43 Issue 2 收斂為 [_handleApplyPreset]/[_handleApplyFromBook]
  /// 共用核心）：「套用到目前書籍」（`targetBookIds` 恰為 `[widget.bookId]`，
  /// [ReaderSettingsSheet] 的「套用到本書」快速按鈕固定產生這個形狀）直接
  /// 寫入不需確認；其餘情況（「套用到其他書籍」流程，即使使用者只勾選 1
  /// 本其他書籍）皆先跳出「即將覆蓋 N 本書」確認——**判斷依據刻意不是
  /// `targetBookIds.length > 1`**：使用者透過「套用到其他書籍」picker 只
  /// 勾選 1 本書時，`targetBookIds.length == 1`，但這仍是「其他書籍」語意
  /// （design.md「套用目標二選一」的第二選項），不是「套用到目前書籍」的
  /// 快速動作，兩者不可用數量混為一談，見
  /// [layout_preset_actions.layoutPresetTargetsCurrentBookOnly]。目標含
  /// 目前書籍時，寫入後呼叫既有 [_handlePrefsChanged] 即時刷新畫面（比照
  /// spec.md「套用到目前書籍後的畫面刷新」，不新增另一條刷新路徑）。
  Future<void> _applyPrefsToTargets(
    BookReaderPrefs prefs,
    List<String> targetBookIds,
  ) async {
    final repository = widget.bookReaderPrefsRepository;
    if (repository == null || targetBookIds.isEmpty) return;
    try {
      if (!layout_preset_actions.layoutPresetTargetsCurrentBookOnly(
        targetBookIds,
        widget.bookId,
      )) {
        final confirmed =
            await _confirmApplyToOtherBooks(targetBookIds.length);
        if (!confirmed || !mounted) return;
      }
      await layout_preset_actions.applyLayoutPresetPrefs(
        repository,
        prefs: prefs,
        targetBookIds: targetBookIds,
      );
      if (!mounted) return;
      if (targetBookIds.contains(widget.bookId)) {
        _handlePrefsChanged(prefs);
      }
    } catch (e, stackTrace) {
      // Epic 43 Issue 5：比照 _handleSaveAsPreset 既有的 try/catch +
      // SnackBar 模式，補齊套用預設集失敗時的使用者可見提示。
      debugPrint('套用版面設定失敗：$e\n$stackTrace');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          key: const Key('reader_apply_preset_error_snackbar'),
          content: Text(AppLocalizations.of(context)!.readerApplyPresetFailedMessage),
        ),
      );
    }
  }

  Future<void> _handleApplyPreset(
    LayoutPreset preset, {
    required List<String> targetBookIds,
  }) async {
    await _applyPrefsToTargets(preset.prefs, targetBookIds);
  }

  /// 書籍設定複製（epic-28-reader-settings-enhancements Issue 3）：先讀取
  /// 來源書籍目前的版面偏好設定，以 [BookReaderPrefs.reflowableEpubFields]
  /// 過濾後交給 [_applyPrefsToTargets] 處理後續判斷/確認/寫入/刷新。
  Future<void> _handleApplyFromBook(
    String sourceBookId, {
    required List<String> targetBookIds,
  }) async {
    final repository = widget.bookReaderPrefsRepository;
    if (repository == null || targetBookIds.isEmpty) return;
    try {
      final sourcePrefs =
          (await repository.load(sourceBookId)).reflowableEpubFields();
      if (!mounted) return;
      await _applyPrefsToTargets(sourcePrefs, targetBookIds);
    } catch (e, stackTrace) {
      // Epic 43 Issue 5（I-2 審查修訂）：repository.load() 發生在呼叫
      // _applyPrefsToTargets 之前，不在它內部的 try/catch 保護範圍內，
      // 需要自己獨立這一層——與 _applyPrefsToTargets 內部的 try/catch
      // 是兩層獨立保護，不會為同一次失敗重複顯示兩次 SnackBar（見上方
      // Global Constraints 說明）。
      debugPrint('套用版面設定失敗：$e\n$stackTrace');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          key: const Key('reader_apply_preset_error_snackbar'),
          content: Text(AppLocalizations.of(context)!.readerApplyPresetFailedMessage),
        ),
      );
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
    // I-2（審查修訂）：理由同上（`_handleSaveAsPreset` 覆蓋確認）。
    if (!confirmed || !mounted) return;
    try {
      final updated =
          await layout_preset_actions.deleteLayoutPreset(repository, id);
      if (!mounted) return;
      setState(() => _layoutPresets = updated);
    } catch (e, stackTrace) {
      // Epic 43 Issue 5：比照 _handleSaveAsPreset 既有的 try/catch +
      // SnackBar 模式，補齊刪除預設集失敗時的使用者可見提示。
      debugPrint('刪除預設集失敗：$e\n$stackTrace');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          key: const Key('reader_delete_preset_error_snackbar'),
          content: Text(AppLocalizations.of(context)!.readerDeletePresetFailedMessage),
        ),
      );
    }
  }

  Future<bool> _confirmDeletePreset(String name) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.readerConfirmDeleteTitle),
        content: Text(l10n.readerDeletePresetConfirmMessage(name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            key: const Key('layout_preset_delete_confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.readerConfirmDeleteTitle),
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

  /// 載入可用字型（epic-54 Issue 1）：已下載的內建字型與自訂字型各自讀取、各自
  /// 處理失敗（視為空集合，不阻擋開書），兩邊都完成才一次組出 [AvailableFonts]。
  Future<void> _loadAvailableFonts() async {
    if (_availableFonts != null) return;
    // Dart 3 record 的 .wait：強型別，不依賴陣列下標與強制轉型（審查 M-1）。
    // 兩個方法各自 catch，不會拋出例外，所以不會出現 ParallelWaitError。
    final (installedBuiltIn, customFonts) = await (
      _loadInstalledBuiltInFonts(),
      _loadCustomFonts(),
    ).wait;
    if (!mounted) return;
    setState(() {
      _availableFonts = AvailableFonts(
        installedBuiltIn: installedBuiltIn,
        customFonts: customFonts,
      );
    });
  }

  Future<Set<AppFont>> _loadInstalledBuiltInFonts() async {
    final store = widget.downloadableFontStore;
    if (store == null) return const {};
    try {
      return await store.installedFonts();
    } catch (e) {
      debugPrint('Failed to load downloaded fonts: $e');
      return const {};
    }
  }

  Future<List<CustomFont>> _loadCustomFonts() async {
    final repository = widget.customFontsRepository;
    if (repository == null) return const [];
    try {
      return await repository.listAll();
    } catch (e) {
      debugPrint('Failed to load custom fonts: $e');
      return const [];
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
    // 書籤預設名稱是建立當下語言的快照；在 await 之前取得 l10n
    final l10n = AppLocalizations.of(context)!;
    await bookmark_toggle.toggleBookmark(
      repository: repository,
      bookId: widget.bookId,
      matches: (bookmark) =>
          bookmark.epubLocatorJson == positionInfo.locatorJson,
      build: () => Bookmark(
        id: const Uuid().v4(),
        bookId: widget.bookId,
        name: Bookmark.defaultName(
          BookmarkPositionContext(
            epubLocatorJson: positionInfo.locatorJson,
            progression: positionInfo.progression,
          ),
          l10n,
        ),
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
    final l10n = AppLocalizations.of(context)!;
    await bookmark_toggle.toggleBookmark(
      repository: repository,
      bookId: widget.bookId,
      matches: (bookmark) => bookmark.pdfPageIndex == pageIndex,
      build: () => Bookmark(
        id: const Uuid().v4(),
        bookId: widget.bookId,
        name: Bookmark.defaultName(BookmarkPositionContext(pdfPageIndex: pageIndex), l10n),
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
        onEntrySelected: (entry) {
          Navigator.of(context).pop();
          _jumpToEpubLocator((entry as TocEntry).locatorJson);
        },
        textConversion: _textConversionMode,
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
        textConversion: _textConversionMode,
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

  /// [initialTabIndex] 預設 `0`（🔖書籤，既有呼叫端不受影響）——底部
  /// 選單列「✎ 劃線筆記」按鈕（Step 3a／3b）傳入 `1`，預設停在「✏️劃線與
  /// 備註」分頁（epic-38-reader-chrome-tts-redesign Issue 1，接上 Task 1
  /// 建立的 `NotesBottomSheet.initialTabIndex`）。
  void _openNotesSheet(BookFormat format, {int initialTabIndex = 0}) {
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
        bookTitle: _displayBookTitle,
        bookAuthor: widget.bookAuthor,
        bookProgress: latestProgress,
        bookmarksRepository: repository,
        currentPosition: positionContext,
        initialTabIndex: initialTabIndex,
        textConversion: _textConversionMode,
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
    _openBookFlow.onRendered();
    // epic-6-annotations Issue 3：PDF 書籍開啟成功後載入既有劃線/備註並
    // 送給原生端渲染。與 EPUB 的觸發點（_handleLayoutResolved，見 Issue 2
    // Task 10 Step 7）刻意不同——PDF 沒有對應的版面解析回呼，本方法
    // （onPageRendered）是 PDF 開書成功的既有訊號，兩種格式共用同一個
    // _annotationsLoaded 旗標（單一書籍只會是其中一種格式，不會重複觸發）。
    if (detectBookFormat(_activeFilePath) == BookFormat.pdf &&
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
    if (detectBookFormat(_activeFilePath) == BookFormat.pdf && !_pdfTocLoaded) {
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
    // epic-10-search Issue 5：書籍成功渲染（含 PDF／Foliate，兩者皆走
    // onPageRendered）即代表已抵達 initialJumpTarget 指定的目標位置
    // （initialLocatorJson/initialPageIndex 已在建構時套用，見 Task 1），
    // 此時觸發暫態高亮。
    _maybeShowSearchJumpHighlight();
  }

  /// 抵達 `initialJumpTarget` 目標位置後觸發暫態高亮（epic-10-search
  /// Issue 5，spec.md §6）：[widget.initialJumpTarget] 為 `null`（一般
  /// 開書，非搜尋跳轉而來）時完全不動作，零回歸。PDF 需要
  /// `pdfPageIndex`／`pdfRect` 皆存在才顯示（缺 `pdfRect` 時仍已透過
  /// `initialPageIndex` 正常跳轉頁面，只是沒有精確座標可畫暫態高亮框，見
  /// `ReaderJumpTarget` 文件註解）；Foliate 需要 `cfi` 存在。
  void _maybeShowSearchJumpHighlight() {
    if (_searchJumpHighlightTriggered) return;
    final jumpTarget = widget.initialJumpTarget;
    if (jumpTarget == null) return;
    _searchJumpHighlightTriggered = true;
    final highlightShown = jumpTarget.applyTo(
      format: detectBookFormat(_activeFilePath),
      pdfKey: _pdfReaderViewKey,
      foliateKey: _foliateEpubReaderViewKey,
      shouldNavigate: false,
    );
    if (highlightShown) {
      _startSearchJumpHighlightAutoClearTimer();
    }
  }

  /// 啟動（或重新啟動）搜尋跳轉暫態高亮的 3 秒自動清除計時器（epic-10-search
  /// Issue 5 開書當下高亮／Issue 8 就地跳轉高亮共用同一段邏輯，見
  /// [_maybeShowSearchJumpHighlight]／[_handleReaderSearchJumpTarget]）。
  void _startSearchJumpHighlightAutoClearTimer() {
    _searchJumpHighlightTimer?.cancel();
    // 使用捕捉到的 fake Zone 建立 Timer，避免在 runAsync 真實 Zone 內
    // 建立導致 tester.pump 無法推進。
    _searchJumpHighlightTimer =
        _creationZone.run(() => Timer(
              const Duration(seconds: 3),
              _clearSearchJumpHighlight,
            ));
  }

  /// 清除搜尋跳轉暫態高亮：3 秒計時到期，或 [_handleZoneAction] 偵測到
  /// 使用者提前翻頁/點擊畫面時呼叫，取兩者較早發生者（spec.md §6）。
  /// [_searchJumpHighlightTimer] 為 `null`（尚未顯示過或已清除過）時安全
  /// 提前 return，可重複呼叫（[_handleZoneAction] 對每一次動作都無條件
  /// 呼叫本方法，不會判斷目前是否真的有顯示中的高亮）。
  void _clearSearchJumpHighlight() {
    if (_searchJumpHighlightTimer == null) return;
    _searchJumpHighlightTimer?.cancel();
    _searchJumpHighlightTimer = null;
    final format = detectBookFormat(_activeFilePath);
    if (format == BookFormat.pdf) {
      PdfReaderView.clearTemporaryHighlight(_pdfReaderViewKey);
    } else if (isFoliateFormat(format)) {
      FoliateReaderView.clearSearchHighlight(_foliateEpubReaderViewKey);
    }
  }

  /// 閱讀器搜尋就地跳轉（epic-10-search Issue 8，spec.md §9.4）：使用者在
  /// [BookSearchScreen]（`fromReader: true`）選取片段、pop 回傳
  /// [jumpTarget] 後，於目前已開啟的閱讀器 session 就地跳轉並疊加暫態
  /// 高亮，不銷毀重建閱讀器。與 Issue 5 的 [_maybeShowSearchJumpHighlight]
  /// 差異有二：(1) Issue 5 開書當下已經是目標位置，只需要疊加高亮；本
  /// 方法使用者當下正讀在別處，需要先真的導覽過去（`jumpToPage`／
  /// `jumpToLocator`）。(2) **跳頁與疊加高亮是兩個獨立判斷**
  /// （`review-plan-issue-8.md` C-1）：`ReaderJumpTarget.fromContentLocator()`
  /// 對 PDF 命中片段的 `rect` 解析失敗時會優雅降級成「只有 `pdfPageIndex`、
  /// `pdfRect` 為 `null`」，這是刻意設計的正常狀態；若跳頁與高亮共用同一個
  /// `pageIndex == null || rect == null` 判斷提早 return，會導致使用者點了
  /// 搜尋結果卻完全沒有任何跳轉反應——只要有 `pageIndex` 就必須跳頁，`rect`
  /// 只決定要不要額外疊加高亮／啟動自動清除計時器。
  void _handleReaderSearchJumpTarget(ReaderJumpTarget jumpTarget) {
    final highlightShown = jumpTarget.applyTo(
      format: detectBookFormat(_activeFilePath),
      pdfKey: _pdfReaderViewKey,
      foliateKey: _foliateEpubReaderViewKey,
      shouldNavigate: true,
    );
    if (highlightShown) {
      _startSearchJumpHighlightAutoClearTimer();
    }
  }

  /// [BookFormat]（`reader/book_format.dart`，依副檔名判斷）→
  /// [BookFileFormat]（`library/models/library_enums.dart`，`Book.format`
  /// 型別）的純轉換（epic-10-search Issue 8）——兩者列舉成員名稱刻意
  /// 一一對應，僅 [BookFormat.unknown] 沒有對應值，回傳 `null`，呼叫端
  /// 據此停用搜尋入口。目前 codebase 中沒有其他現成的轉換函式（規劃階段
  /// 查證，見 `plans/plan-issue-8.md`），這裡是唯一一處。
  BookFileFormat? _toBookFileFormat(BookFormat format) {
    switch (format) {
      case BookFormat.epub:
        return BookFileFormat.epub;
      case BookFormat.pdf:
        return BookFileFormat.pdf;
      case BookFormat.azw3:
        return BookFileFormat.azw3;
      case BookFormat.cbz:
        return BookFileFormat.cbz;
      case BookFormat.txt:
        return BookFileFormat.txt;
      case BookFormat.md:
        return BookFileFormat.md;
      case BookFormat.unknown:
        return null;
    }
  }

  /// 供搜尋接線使用的 [Book] 物件（epic-10-search Issue 8）：`ReaderScreen`
  /// 本身不持有完整 [Book] 記錄，只有零散的個別欄位，這裡就地合成一份——
  /// [BookSearchScreen] 實際只讀取 `id`／`title`／`author`／`format`／
  /// `filePath`／`progress`（及透過 `format` 間接使用的
  /// `ReaderJumpTarget.fromContentLocator`），其餘 [Book] 必填欄位
  /// （`source`／`createTime`／`lastReadTime`）填入無意義佔位值即可，不
  /// 影響任何實際行為。`isFixedLayout` 讀取 State 內部已解析的
  /// [_isFixedLayout]（而非可能為 `null`、可能過期的 `widget.isFixedLayout`
  /// ——`review-plan-issue-8.md` M-2），對「使用者當下正在讀哪一種版面」
  /// 是更即時準確的來源。格式無法辨識（[BookFormat.unknown]）時回傳
  /// `null`，呼叫端據此停用搜尋入口，語意對齊既有「不支援的檔案格式」
  /// 畫面分支。
  Book? _buildSearchableBook() {
    final fileFormat = _toBookFileFormat(detectBookFormat(_activeFilePath));
    if (fileFormat == null) return null;
    return Book(
      id: widget.bookId,
      title: _displayBookTitle,
      author: _displayBookAuthor,
      format: fileFormat,
      filePath: _activeFilePath,
      source: BookSource.local,
      progress: widget.bookProgress,
      isFixedLayout: _isFixedLayout,
      groupName: BookGroup.uncategorized,
      createTime: DateTime.fromMillisecondsSinceEpoch(0),
      lastReadTime: DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  /// TopBar「搜尋內文」按鈕（`reader_chrome_search_button`）點擊處理
  /// （epic-10-search Issue 8，spec.md §9.4）：`searchRepository`／
  /// `libraryRepository`（`BookSearchScreen.libraryRepository` 為必填，
  /// 但 [ReaderScreen.libraryRepository] 為可選）任一缺席，或本書格式無法
  /// 辨識時，顯示不可用提示、不導覽；否則以 `fromReader: true` 推入
  /// [BookSearchScreen]，等待其 pop 回傳的 [ReaderJumpTarget]。
  Future<void> _openBookSearch() async {
    final searchRepository = widget.searchRepository;
    final libraryRepository = widget.libraryRepository;
    final book = _buildSearchableBook();
    if (searchRepository == null || libraryRepository == null || book == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          key: const Key('reader_chrome_search_unavailable_snackbar'),
          content: Text(AppLocalizations.of(context)!.readerSearchUnavailableMessage),
        ),
      );
      return;
    }
    final jumpTarget = await Navigator.of(context).push<ReaderJumpTarget>(
      MaterialPageRoute(
        builder: (_) => BookSearchScreen(
          book: book,
          searchRepository: searchRepository,
          prefsManager: widget.prefsManager,
          libraryRepository: libraryRepository,
          readerFeatureRepositories: LibraryReaderFeatureRepositories(
            bookmarksRepository: widget.bookmarksRepository,
            highlightsRepository: widget.highlightsRepository,
            notesRepository: widget.notesRepository,
            customFontsRepository: widget.customFontsRepository,
            downloadableFontStore: widget.downloadableFontStore,
            layoutPresetRepository: widget.layoutPresetRepository,
            bookReaderPrefsRepository: widget.bookReaderPrefsRepository,
            ttsProvider: widget.ttsProvider,
            ttsAudioHandler: widget.ttsAudioHandler,
            ttsAudioFocusSource: widget.ttsAudioFocusSource,
            readerActivityTracker: widget.readerActivityTracker,
            searchRepository: searchRepository,
            isFullTextSearchAvailable: widget.isFullTextSearchAvailable,
            // epic-15-storage-permission Issue 0：這裡是手動逐欄重建
            // bundle，新欄位必須一併轉送，否則「閱讀器→單書搜尋→閱讀器」
            // 開啟的閱讀器會遺失匯入服務、無法重新連結失效書籍。
            bookImportService: widget.bookImportService,
            // epic-9-stats Issue 4：同上，手動逐欄重建 bundle 的新欄位必須
            // 一併轉送，否則「閱讀器→單書搜尋→閱讀器」開啟的閱讀器不計時。
            readingStatsRepository: widget.readingStatsRepository,
          ),
          syncDependencies: LibrarySyncDependencies(
            syncCheckpointTrigger: widget.syncCheckpointTrigger,
          ),
          isEinkMode: widget.isEinkMode,
          fromReader: true,
        ),
      ),
    );
    if (!mounted || jumpTarget == null) return;
    _handleReaderSearchJumpTarget(jumpTarget);
  }

  /// 【/diagnose：真機回報旋轉螢幕後畫面被錯誤文字取代，無法繼續閱讀】
  /// 只在載入中才轉為錯誤畫面——書籍已成功渲染後才發生的 `onError` 不應覆蓋
  /// 掉已顯示的內容（例如旋轉螢幕時 Chromium 的 ResizeObserver 良性警告）。
  /// 這個 guard 與探測、逾時、重新連結的規則都收在 [OpenBookFlow]。
  void _handleError(String message) {
    if (!mounted) return;
    _openBookFlow.onViewError(message);
  }

  /// 「重新選取檔案」按鈕的處理函式。取消選檔時什麼都不做（不顯示
  /// SnackBar）；成功時原地重新開書；失敗時以 SnackBar 說明原因，錯誤視圖
  /// 維持原樣可再試一次。
  Future<void> _handleRelinkPressed() async {
    final outcome = await _openBookFlow.relink(_pickBookFileForRelink);
    if (!mounted) return;
    switch (outcome) {
      case OpenBookRelinkCancelled():
        return;
      case OpenBookRelinkReopened(:final newPath):
        // 先選錯、再選對時，收掉上一次的失敗提示，避免重新開書時畫面還掛著
        // 「內容不同」之類的錯誤訊息。
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        // EPUB 版面偵測若在失敗前尚未完成（仍是 null），以新路徑重新觸發一次，
        // 否則 _buildBody 的 gating 條件會讓閱讀視圖永遠停在等待。偏好設定、
        // 閱讀位置、字型以 bookId 載入，重新連結不改 bookId，不需要重跑。
        if (_dispatchedIsFixedLayout == null &&
            detectBookFormat(newPath) == BookFormat.epub) {
          _resolveEpubEngineDispatch();
        }
      case OpenBookRelinkFailed(:final reason):
        final l10n = AppLocalizations.of(context)!;
        final message = switch (reason) {
          BookRelinkFailureReason.formatMismatch =>
            l10n.readerStorageRelinkFormatMismatch,
          BookRelinkFailureReason.contentMismatch =>
            l10n.readerStorageRelinkContentMismatch,
          BookRelinkFailureReason.alreadyInLibrary =>
            l10n.readerStorageRelinkAlreadyInLibrary,
          BookRelinkFailureReason.failed => l10n.readerStorageRelinkFailed,
        };
        // 先收掉上一則：連續選錯檔案時，新結果不必排在前一則（預設 4 秒）
        // 之後才出現，否則使用者會以為第二次嘗試沒有反應。
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(message)));
    }
  }

  /// 開啟單檔選擇器（副檔名限定為原書格式），交給 [OpenBookFlow.relink]。
  /// 使用者取消時回傳 null。
  Future<OpenBookPickedFile?> _pickBookFileForRelink() {
    final picker = widget.pickSingleBookFile ?? pickSingleBookFileViaFilePicker;
    // 只有 EPUB／PDF／AZW3 會走到這裡，BookFormat 名稱即副檔名。
    return picker([detectBookFormat(_activeFilePath).name]);
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
    if (!mounted) return;
    _recordReadingActivity(); // 長按選取（劃線）算閱讀活動
    if (_isFixedLayout) return;
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

  Future<void> _handleDeleteExistingAnnotation(AnnotationListItem item) async {
    final session = _annotationSession;
    if (session == null) return;
    final snapshot = await session.deleteExisting(item);
    if (!mounted) return;
    setState(() {
      _highlights = snapshot.highlights;
      _notes = snapshot.notes;
    });
    _sendDecorationsToNative();
    _handleCloseAnnotationToolbar();
  }

  Future<void> _handlePdfDeleteExistingAnnotation(AnnotationListItem item) async {
    final session = _annotationSession;
    if (session == null) return;
    final snapshot = await session.deleteExisting(item);
    if (!mounted) return;
    setState(() {
      _highlights = snapshot.highlights;
      _notes = snapshot.notes;
    });
    _sendPdfAnnotationsToNative();
    _handlePdfSelectionCanceled();
  }

  Future<void> _handleCopySelection(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        key: const Key('reader_copy_selection_snackbar'),
        content: Text(AppLocalizations.of(context)!.readerCopiedToClipboardMessage),
      ),
    );
  }

  /// 刪除按鈕的 tooltip 文字，依 [item] 實際含有的內容組合而定
  /// （epic-27-reader-device-compat Issue 11）。
  String _annotationDeleteButtonLabel(AnnotationListItem item) {
    final l10n = AppLocalizations.of(context)!;
    final hasHighlight = item.highlight != null;
    final hasNote = item.note != null;
    if (hasHighlight && hasNote) return l10n.readerAnnotationDeleteHighlightAndNote;
    if (hasHighlight) return l10n.readerAnnotationDeleteHighlight;
    return l10n.readerAnnotationDeleteNote;
  }

  void _handlePdfSelectionRectComputed(PdfSelectionInfo info) {
    if (!mounted) return;
    // epic-25-annotation-interaction-qa Issue 6：PdfReaderView 現在連退化
    // 選取（長按沒有明顯拖曳位移）都會送出一個落點本身的零面積矩形（見
    // pdf_reader_view.dart 的 _finishSelectionDrag()／pointPercentRect()），
    // 不再由它自己判斷「這是不是有意義的操作」——這裡才是真正決定要不要
    // 顯示工具列的地方。退化選取（rect.left == rect.right，見
    // pointPercentRect() doc comment 保證的精確浮點數相等）只有在命中既有
    // 劃線/備註時才顯示編輯工具列；沒命中維持原本「什麼都不做」的行為，
    // 避免任何一次精準點擊（例如翻頁時手指多停留了一下）都意外彈出建立
    // 工具列。非退化選取（有明顯拖曳）的既有行為完全不變。
    final isDegenerate = info.rect.left == info.rect.right;
    if (isDegenerate &&
        resolvePdfExistingAnnotation(
              selection: info,
              highlights: _highlights,
              notes: _notes,
            ) ==
            null) {
      return;
    }
    // 放在退化選取守衛之後：沒命中既有標註的零面積長按（例如翻頁時手指多停留
    // 一下）是無效操作，不算閱讀活動；有效的拖曳框選或點選既有標註才算。
    _recordReadingActivity();
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
    final session = _annotationSession;
    if (selection == null || session == null) return;
    final result = await session.createHighlight(
      locator: AnnotationLocator.epub(
        locatorJson: selection.locatorJson,
        progression: selection.progression,
      ),
      style: style,
    );
    if (!mounted) return;
    setState(() {
      _highlights = result.snapshot.highlights;
      _notes = result.snapshot.notes;
      _pendingHighlightIdForSelection = result.highlightId;
    });
    _sendDecorationsToNative();
  }

  Future<void> _handleNotePressed() async {
    final selection = _currentSelection;
    final session = _annotationSession;
    if (selection == null || session == null) return;
    final existing = resolveEpubExistingAnnotation(
      existingAnnotationId: selection.existingAnnotationId,
      highlights: _highlights,
      notes: _notes,
    )?.note;
    final l10n = AppLocalizations.of(context)!;
    final text = await showNoteTextDialog(
      context,
      initialText: existing?.text ?? '',
      title: existing != null ? l10n.readerAnnotationEditNoteTooltip : l10n.readerAnnotationAddNoteTooltip,
    );
    if (text == null) return;
    final snapshot = await session.createOrUpdateNote(
      locator: AnnotationLocator.epub(
        locatorJson: selection.locatorJson,
        progression: selection.progression,
      ),
      text: text,
      existing: existing,
      pendingHighlightId: _pendingHighlightIdForSelection,
    );
    if (!mounted) return;
    setState(() {
      _highlights = snapshot.highlights;
      _notes = snapshot.notes;
      _currentSelection = null;
      _pendingHighlightIdForSelection = null;
    });
    _sendDecorationsToNative();
  }

  /// 重新查詢本書全部劃線/備註並送給原生端重繪 Decorator（比照 TOC 的
  /// 「只在尚未載入過才抓取」慣例，但本方法每次 CRUD 後皆會主動重新
  /// 呼叫，非只呼叫一次——這裡的 `_annotationsLoaded` 只用於「開書時是否
  /// 已載入過初始清單」，不是「是否曾呼叫過本方法」）。
  Future<void> _reloadAnnotationsAndRefreshDecorations() async {
    final session = _annotationSession;
    if (session == null) return;
    final snapshot = await session.reload();
    if (!mounted) return;
    setState(() {
      _highlights = snapshot.highlights;
      _notes = snapshot.notes;
    });
    _sendDecorationsToNative();
  }

  /// 無條件使用 `FoliateReaderView.setDecorations`（Issue 4 修正：
  /// FXL 書籍的劃線/備註疊圖從本工單起才第一次真正生效，先前因
  /// `_dispatchedIsFixedLayout` 分派到已無人建構的 `EpubReaderView` 而
  /// 靜默失敗）。
  void _sendDecorationsToNative() {
    if (!mounted) return;
    final tokens = Theme.of(context).extension<ElinkTokens>()!;
    final decorations = <EpubDecoration>[
      for (final highlight in _highlights)
        if (highlight.epubLocatorJson != null)
          EpubDecoration.forHighlight(
            highlightId: highlight.id,
            locatorJson: highlight.epubLocatorJson!,
            tint: highlightStyleColor(highlight.style, tokens: tokens).toARGB32(),
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


  Future<void> _handlePdfHighlightStyleSelected(HighlightStyle style) async {
    final selection = _currentPdfSelection;
    final session = _annotationSession;
    if (selection == null || session == null) return;
    final result = await session.createHighlight(
      locator: AnnotationLocator.pdf(pageIndex: selection.pageIndex, rect: selection.rect),
      style: style,
    );
    if (!mounted) return;
    setState(() {
      _highlights = result.snapshot.highlights;
      _notes = result.snapshot.notes;
      _pendingPdfHighlightIdForSelection = result.highlightId;
    });
    _sendPdfAnnotationsToNative();
  }

  Future<void> _handlePdfNotePressed() async {
    final selection = _currentPdfSelection;
    final session = _annotationSession;
    if (selection == null || session == null) return;
    final existing = resolvePdfExistingAnnotation(
      selection: selection,
      highlights: _highlights,
      notes: _notes,
    )?.note;
    final l10n = AppLocalizations.of(context)!;
    final text = await showNoteTextDialog(
      context,
      initialText: existing?.text ?? '',
      title: existing != null ? l10n.readerAnnotationEditNoteTooltip : l10n.readerAnnotationAddNoteTooltip,
    );
    if (text == null) return;
    final snapshot = await session.createOrUpdateNote(
      locator: AnnotationLocator.pdf(pageIndex: selection.pageIndex, rect: selection.rect),
      text: text,
      existing: existing,
      pendingHighlightId: _pendingPdfHighlightIdForSelection,
    );
    if (!mounted) return;
    setState(() {
      _highlights = snapshot.highlights;
      _notes = snapshot.notes;
      _currentPdfSelection = null;
      _pendingPdfHighlightIdForSelection = null;
    });
    _sendPdfAnnotationsToNative();
  }

  /// 重新查詢本書全部劃線/備註並送給原生端重繪 Bitmap 疊加（PDF 版本，
  /// 比照 EPUB 的 [_reloadAnnotationsAndRefreshDecorations]）。共用同一組
  /// [_highlights]／[_notes] state 欄位——單一 ReaderScreen 會話只會載入
  /// 其中一種格式的書籍，不會同時混用。
  Future<void> _reloadPdfAnnotationsAndSync() async {
    final session = _annotationSession;
    if (session == null) return;
    final snapshot = await session.reload();
    if (!mounted) return;
    setState(() {
      _highlights = snapshot.highlights;
      _notes = snapshot.notes;
    });
    _sendPdfAnnotationsToNative();
  }

  void _sendPdfAnnotationsToNative() {
    if (!mounted) return;
    final tokens = Theme.of(context).extension<ElinkTokens>()!;
    final annotations = <PdfAnnotationDecoration>[
      for (final highlight in _highlights)
        if (highlight.pdfPageIndex != null && highlight.pdfRect != null)
          PdfAnnotationDecoration.forHighlight(
            pageIndex: highlight.pdfPageIndex!,
            rect: highlight.pdfRect!,
            tint: highlightStyleColor(highlight.style, tokens: tokens).toARGB32(),
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
    final format = detectBookFormat(_activeFilePath);
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
        // false) 改造，讓 body 版面約束不受頂部 Chrome 疊加影響。
        extendBodyBehindAppBar: true,
        // epic-38-reader-chrome-tts-redesign Issue 1：三格式統一改用
        // ReaderChromeTopBar／ReaderChromeBottomBar 兩個 Positioned 疊加層
        // 承載 Chrome（見 _buildBody），Scaffold.appBar 恆為 null——原本依
        // _isFixedLayout/_chromeVisible/format/_dispatchedIsFixedLayout
        // 四個條件決定要不要建構 AppBar 的邏輯已確認沒有任何組合在正式
        // 產品環境下會實際觸及（見 plans/plan-issue-1.md「計劃範圍澄清」
        // 第 1 點），整段條件式與 AppBar(...) 建構、_buildAppBarTitle()／
        // _buildAppBarActions() 兩個方法一併刪除。
        appBar: null,
        body: _buildBody(format, isLandscape),
      ),
    );
  }

  /// 頂部 Chrome 列標題文字（epic-38-reader-chrome-tts-redesign Issue 1，
  /// spec.md §功能①）：取代已刪除的 `_buildAppBarTitle()`。**與舊方法的
  /// 關鍵差異**：不再受 `_resolved.showHeader` 偏好門檻限制、一律顯示章節
  /// 名稱——`showHeader`／`showFooter` 偏好維持原本語意完全不動，只控制
  /// `_chromeVisible == false` 時螢幕邊角是否仍保留常駐頁首/頁尾文字
  /// （`_buildFoliateHeaderText()`／`_buildFoliateProgressText()` 邏輯，
  /// 完全不受本次改動影響）。標題本身不可點擊（prototype 的頂部列標題是
  /// 純文字，開目錄一律透過獨立的 ☰ 按鈕，見 `ReaderChromeTopBar`）。
  /// 找不到章節時回退為 [widget.bookTitle]（2026-09-08 `/grill-with-docs`
  /// 使用者需求，取代字面 `'閱讀器'`）；截斷交給 `ReaderChromeTopBar` 既有的
  /// `TextOverflow.ellipsis, maxLines: 1`，不需要額外邏輯。
  ///
  /// 2026-09-12 使用者需求：TopBar 目前不再顯示這個值（頁首已有另一處
  /// 顯示，見上方 `_buildChromeTopBar()` 呼叫端），暫時保留這個方法本身
  /// 供後續決定要放什麼內容時使用，故目前無呼叫端。
  // ignore: unused_element
  String _currentChapterTitle(BookFormat format) {
    if (format == BookFormat.pdf) {
      final currentPath =
          PdfTocNavigator.findCurrentPath(_pdfTocEntries, _pdfPageInfo?.pageIndex);
      return currentPath.isEmpty
          ? _displayBookTitle
          : convertText(currentPath.last.title, _textConversionMode);
    }
    final currentPath =
        TocNavigator.findCurrentPath(_tocEntries, _epubPositionInfo?.progression);
    return currentPath.isEmpty
        ? _displayBookTitle
        : convertText(currentPath.last.title, _textConversionMode);
  }

  /// 頁碼列（`ReaderChromeBottomBar` 頂端 34dp 那一列）顯示的「當前頁 /
  /// 總頁數 · 百分比」文字（epic-38-reader-chrome-tts-redesign Issue 1，
  /// spec.md §功能①②）。位置資訊尚未載入完成（`_epubPositionInfo`／
  /// `_pdfPageInfo` 為 `null`，或總頁數 <= 0）時回傳空字串，呼叫端直接
  /// 顯示空白，不額外處理 loading 狀態文字。
  String _pageProgressText(BookFormat format) {
    if (format == BookFormat.pdf) {
      final info = _pdfPageInfo;
      if (info == null || info.totalPages <= 0) return '';
      final current = info.pageIndex + 1;
      final percent = (current / info.totalPages * 100).round();
      return '$current / ${info.totalPages} · $percent%';
    }
    final info = _epubPositionInfo;
    final totalPages = info?.displayTotalPages ?? 0;
    if (totalPages <= 0) return '';
    final current = ((info?.displayPageIndex ?? 0) + 1).clamp(1, totalPages);
    final percent = (current / totalPages * 100).round();
    return '$current / $totalPages · $percent%';
  }

  /// 本書「單書情境」下簡繁顯示轉換的目前生效值（FR-48，epic-42-text-
  /// conversion Issue 3）：`_loaded` 尚未載入完成時（載入中／錯誤等早退
  /// 分支）安全回退 `original`，比照 `_resolved?.showHeader ?? true`
  /// 既有「早退分支維持安全預設值」慣例——部分呼叫點（例如
  /// `_buildSearchableBook()` 供 `ReaderChromeTopBar` 搜尋按鈕使用）在
  /// `_loaded` 尚未賦值前就可能被觸發，不能沿用 `_buildNativeView()`
  /// 既有「`_resolved` 非 null 時 `_loaded` 恆非 null」的前提斷言。
  TextConversionMode get _textConversionMode {
    final loaded = _loaded;
    if (loaded == null) return TextConversionMode.original;
    return resolveTextConversion(_prefs, loaded.globalPrefs.reading);
  }

  /// 依 [_textConversionMode] 轉換後的書名，供頁首／底部工具列／單書
  /// 搜尋標題等「單書情境」渲染點統一取用。[widget.bookTitle] 為 `null`
  /// 時（僅測試直接建構 `ReaderScreen` 未帶 `bookTitle` 才會發生，正式
  /// 生產路徑 `buildReaderScreen()` 恆傳入書名，見 Task 18 計劃範圍
  /// 澄清）回退為 `readerUnknownBookTitle` 在地化文字——此 getter 僅在
  /// `build()` 或使用者互動 callback 內被呼叫（非 `initState()`），
  /// 存取 `AppLocalizations.of(context)!` 安全。
  String get _displayBookTitle {
    final title = widget.bookTitle ??
        AppLocalizations.of(context)!.readerUnknownBookTitle;
    return convertText(title, _textConversionMode);
  }

  /// 同 [_displayBookTitle]，供 `_buildSearchableBook()` 的作者欄位使用；
  /// [widget.bookAuthor] 為 null 時原樣回傳 null。
  String? get _displayBookAuthor {
    final author = widget.bookAuthor;
    return author == null ? null : convertText(author, _textConversionMode);
  }

  // reader_chrome_top_bar.dart/_openPdfToc() 分別接手了 AppBar 瘦身與縮圖
  // 尺寸兩件事——_appBarToolbarHeight/_appBarButtonMinWidth/_appBarIconSize/
  // _appBarTitleFontSize 四個常數隨 Scaffold.appBar／_buildAppBarActions()／
  // _buildAppBarTitle() 一併刪除（epic-38-reader-chrome-tts-redesign
  // Issue 1）；_pdfThumbnailMaxWidth 仍被 _openPdfToc() 使用，保留。
  static const double _pdfThumbnailMaxWidth = 120;

  // 浮動工具列估計高度／與選取範圍的間距（初始選擇，真機測試後可能需
  // 微調，見 Global Constraints「選取矩形座標協定」）。
  //
  // 【epic-27-reader-device-compat Issue 11】改為雙列版面後的估計值：
  // 第一列 5 顆 IconButton（3 色+底線+關閉）＝5*48=240，第二列最多 3 顆
  // （複製/備註/刪除）＝3*48=144，寬度取兩列較大者 240，加上外層 Padding
  // 左右各 8dp＝256；高度為兩列各 48dp 加上外層 Padding 上下各 4dp＝104。
  // 這是估計值，不是嚴謹量測結果——若 widget test（例如既有的「工具列
  // 右緣不應超出畫面寬度」測試）顯示與實際渲染尺寸有落差，以測試回報的
  // 真實數值為準調整這兩個常數，不可保留錯誤估計值。
  static const _annotationToolbarHeight = 104.0;
  static const _annotationToolbarGap = 8.0;
  static const _annotationToolbarWidth = 256.0;

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

  /// 頂部 Chrome 列的 `Positioned` 包裝（epic-38-reader-chrome-tts-redesign
  /// Issue 1 審查修正；2026-09-10 修正：頁首／工具列拆成兩組各自獨立的
  /// 顯示開關，理由與完整狀態表見 `CONTEXT.md`「Chrome Bar」詞條）：抽成
  /// 獨立方法，讓 `_buildBody()` 的「不支援格式」／「渲染錯誤」兩個早退
  /// 分支也能顯示——這兩個分支原本完全跳過主要 `Stack`，`Scaffold.appBar`
  /// 又已改為恆為 `null`，導致使用者在這兩種狀態下沒有返回鍵、無法離開
  /// 閱讀器（此早退分支下 `_chromeVisible` 恆為初始值 `true`，工具列仍會
  /// 顯示，返回鍵可用）。目錄按鈕已移除，改移至 `ReaderChromeBottomBar`。
  Positioned _buildChromeTopBar(BookFormat format) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: ReaderChromeTopBar(
        onBack: () => Navigator.of(context).pop(),
        // 2026-09-12 使用者需求：頁首（_buildFoliateHeaderText()／
        // PDF 頁碼列）已經顯示書籍/章節資訊，TopBar 這裡不需要再重複顯示，
        // 先改為空字串；_currentChapterTitle() 邏輯保留供後續決定要放什麼
        // 內容時使用，故未刪除（見下方 unused_element 抑制）。
        chapterTitle: '',
        onSearchTap: () => unawaited(_openBookSearch()),
        // `_resolved` 為 null 代表偏好設定尚未載入完成（載入中／錯誤／不
        // 支援格式等早退分支），此時預設顯示頁首，比照 `_chromeVisible`
        // 初始值恆為 `true` 的既有慣例——不能解讀成「使用者關閉了顯示
        // 頁首」，兩者語意不同。
        isHeaderVisible: _resolved?.showHeader ?? true,
        isToolbarVisible: _chromeVisible,
        isBottomChromeVisible: _chromeVisible,
        onToggleBottomChrome: () =>
            setState(() => _chromeVisible = !_chromeVisible),
        showTtsIndicator: _isTtsActive && !_chromeVisible,
        backgroundColor: _themedFabBackgroundColor,
        iconColor: _themedFabIconColor,
        isEinkMode: widget.isEinkMode,
      ),
    );
  }

  /// 目錄按鈕的統一分派邏輯（2026-09-10 從 `ReaderChromeTopBar` 移至
  /// `ReaderChromeBottomBar` 時抽出，`_buildChromeTopBar`／
  /// `_buildFoliateChromeBottomBar`／PDF 選單列共用同一份防呆條件，避免
  /// 三處重複）：PDF 用 `_pdfTocLoaded`，Foliate 格式用
  /// `_autoDetectedWritingMode`／`_tocLoaded`，兩者皆未就緒時回傳 `null`
  /// 顯示為停用狀態。
  VoidCallback? _onTocTapFor(BookFormat format) {
    if (format == BookFormat.pdf) {
      return !_pdfTocLoaded ? null : _openPdfToc;
    }
    if (!isFoliateFormat(format)) return null;
    return (_autoDetectedWritingMode == null || !_tocLoaded) ? null : _openToc;
  }

  /// `ReaderChromeBottomBar` 建構參數在 [_buildBottomChrome] 三個分支
  /// （尚未建構 controller／controller 存在但 idle／CBZ 未展開面板）完全
  /// 相同，只有 [onTtsTap] 不同——抽成獨立方法避免三份重複（epic-38-
  /// reader-chrome-tts-redesign Issue 2）。
  ReaderChromeBottomBar _buildFoliateChromeBottomBar(
    BookFormat format, {
    required VoidCallback? onTtsTap,
  }) {
    return ReaderChromeBottomBar(
      bookTitle: _displayBookTitle,
      pageProgressText: _pageProgressText(format),
      footer: _epubPositionInfo == null
          ? const SizedBox.shrink()
          : _buildFoliateEpubFooter(_epubPositionInfo!),
      onTocTap: _onTocTapFor(format),
      isBookmarked: _bookmarkAtCurrentPosition != null,
      onBookmarkTap: widget.bookmarksRepository == null ||
              _epubPositionInfo == null
          ? null
          : _toggleBookmark,
      onAnnotationsTap: widget.bookmarksRepository == null ||
              _autoDetectedWritingMode == null ||
              _epubPositionInfo == null
          ? null
          : () => _openNotesSheet(format, initialTabIndex: 1),
      onLayoutTap: _isFixedLayout
          ? _openFxlSettings
          : (_autoDetectedWritingMode == null ? null : _openLayoutSettings),
      onTtsTap: onTtsTap,
      backgroundColor: _themedFabBackgroundColor,
      iconColor: _themedFabIconColor,
      isEinkMode: widget.isEinkMode,
    );
  }

  /// 底部 Chrome 列的衍生切換（epic-38-reader-chrome-tts-redesign Issue 2，
  /// spec.md §功能③）：`_ttsController` 為 `null`（使用者從未按過「◗
  /// 朗讀」）時回傳 `ReaderChromeBottomBar`；非 `null` 時依
  /// `controller.status` 衍生二擇一渲染，不設手動旗標——章節自然播完時
  /// `AnimatedBuilder` 會自動偵測到 `status == idle` 並切回
  /// `ReaderChromeBottomBar`，不需要額外程式碼。
  ///
  /// **CBZ 結構性例外（計劃範圍澄清第 1 點）**：CBZ 為純圖像格式，無文字
  /// 可朗讀，[_ttsControllerOrNull] 刻意不對 CBZ 存取（避免白白建構用不到
  /// 的 `TtsController`／原生 `AudioPlayer`，見該 getter 文件註解），故
  /// CBZ 沒有真正的 `controller.status` 可供衍生。改用獨立的
  /// [_cbzTtsPanelVisible] 手動旗標控制這個純裝飾、恆為停用狀態的
  /// `TtsPanel` 是否展開——沿用 Issue 1 之前 `TtsMiniPlayer` 對 CBZ 的既有
  /// 處理方式，不受一般格式「衍生而非手動旗標」設計原則影響（CBZ 根本
  /// 沒有可衍生的真實狀態）。
  Widget _buildBottomChrome(BookFormat format) {
    if (format == BookFormat.cbz) {
      if (widget.ttsProvider == null || !_cbzTtsPanelVisible) {
        return _buildFoliateChromeBottomBar(
          format,
          onTtsTap: widget.ttsProvider == null
              ? null
              : () => setState(() => _cbzTtsPanelVisible = true),
        );
      }
      return TtsPanel(
        status: TtsPlaybackStatus.idle,
        speed: 1.0,
        isCbz: true,
        isCollapsed: _ttsPanelCollapsed,
        sleepTimerRemaining: null,
        backgroundColor: _themedFabBackgroundColor,
        iconColor: _themedTtsDisabledIconColor,
        disabledIconColor: _themedTtsDisabledIconColor,
        isEinkMode: widget.isEinkMode,
        onPlayPause: () {},
        onPrevious: () {},
        onNext: () {},
        onSpeedTap: () {},
        onVoiceTap: () {},
        onSleepTimerTap: _openSleepTimerPicker,
        onToggleCollapse: () =>
            setState(() => _ttsPanelCollapsed = !_ttsPanelCollapsed),
        // 審查修正（review-plan-issue-2.md I4）：CBZ 底層動作列雖然沒有
        // 真正的 TtsController、_onTtsStatusChanged 邊緣偵測也不會對 CBZ
        // 觸發，但同一顆睡眠定時器按鈕（onSleepTimerTap 上面那行）與一般
        // 格式共用同一組 _ttsSleepTimer／_ttsSleepTimerDuration 欄位——
        // 若使用者在 CBZ 面板設定了定時器又按「停止」關閉面板，遺漏取消
        // 會讓計時器在背景繼續倒數，到期後對已經關閉的面板毫無意義地
        // 執行 _ttsController?.pause()（CBZ 恆為 null，no-op，但
        // _ttsSleepTimerDuration 狀態本身的殘留仍是明確的邏輯不一致）。
        onStop: () {
          _cancelTtsSleepTimer();
          setState(() => _cbzTtsPanelVisible = false);
        },
      );
    }
    final controller = _ttsController; // 不用 _ttsControllerOrNull，避免觸發 lazy 建構
    if (controller == null) {
      return _buildFoliateChromeBottomBar(
        format,
        onTtsTap: widget.ttsProvider == null
            ? null
            : () => _ttsControllerOrNull!.play(),
      );
    }
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        if (controller.status == TtsPlaybackStatus.idle) {
          return _buildFoliateChromeBottomBar(
            format,
            onTtsTap: () => controller.play(),
          );
        }
        return TtsPanel(
          status: controller.status,
          speed: controller.speed,
          isCbz: false,
          isCollapsed: _ttsPanelCollapsed,
          sleepTimerRemaining: _ttsSleepTimerDuration,
          backgroundColor: _themedFabBackgroundColor,
          iconColor: _themedFabIconColor,
          disabledIconColor: _themedTtsDisabledIconColor,
          isEinkMode: widget.isEinkMode,
          onPlayPause: controller.status == TtsPlaybackStatus.playing
              ? controller.pause
              : () => controller.play(),
          onPrevious: () => controller.previousSegment(),
          onNext: () => controller.nextSegment(),
          onSpeedTap: () =>
              controller.setSpeed(_nextTtsSpeedPreset(controller.speed)),
          onVoiceTap: () => _openTtsVoicePicker(controller),
          onSleepTimerTap: _openSleepTimerPicker,
          onToggleCollapse: () =>
              setState(() => _ttsPanelCollapsed = !_ttsPanelCollapsed),
          onStop: () async {
            _cancelTtsSleepTimer();
            await controller.stop();
          },
        );
      },
    );
  }

  /// 睡眠定時器目前設定的時長（epic-38-reader-chrome-tts-redesign
  /// Issue 2）：`null` 代表「不限時」（未設定，或已到期/取消）。只顯示
  /// 「已設定的時長」（如「定時 30 分」），不做逐秒刷新的倒數畫面——
  /// E-Ink 裝置不利於高頻率畫面刷新，spec.md「Out of Scope」已排除。
  Duration? _ttsSleepTimerDuration;
  Timer? _ttsSleepTimer;

  void _setTtsSleepTimer(Duration? duration) {
    _ttsSleepTimer?.cancel();
    setState(() => _ttsSleepTimerDuration = duration);
    if (duration == null) return; // 「不限時」：取消計時器，不排新的。
    _ttsSleepTimer = Timer(duration, () {
      _ttsController?.pause();
      if (mounted) setState(() => _ttsSleepTimerDuration = null);
    });
  }

  void _cancelTtsSleepTimer() => _setTtsSleepTimer(null);

  /// 供 `TtsPanel.onSleepTimerTap` 呼叫，開啟 15/30/45/60 分＋「不限時」
  /// 固定清單（spec.md「睡眠定時器」User Story 15）。也透過
  /// [ReaderScreen.openSleepTimerPickerForTest] 供測試直接呼叫——見
  /// 計劃範圍澄清第 3 點。
  Future<void> _openSleepTimerPicker() {
    return _showThemedModalBottomSheet<void>(
      builder: (_) => _TtsSleepTimerSheet(
        options: const [
          Duration(minutes: 15),
          Duration(minutes: 30),
          Duration(minutes: 45),
          Duration(minutes: 60),
        ],
        selected: _ttsSleepTimerDuration,
        onSelected: (duration) {
          Navigator.of(context).pop();
          _setTtsSleepTimer(duration);
        },
      ),
    );
  }

  /// 是否正在朗讀（idle 以外的任何狀態），供 [ReaderChromeTopBar]
  /// 小喇叭圖示（Task 7）與下方 [_onTtsStatusChanged] 邊緣偵測共用。讀
  /// 私有欄位 `_ttsController`（非 `_ttsControllerOrNull`），不觸發 lazy
  /// 建構。
  bool get _isTtsActive =>
      _ttsController != null && _ttsController!.status != TtsPlaybackStatus.idle;

  bool _wasTtsActive = false;

  /// 睡眠定時器自動取消機制（審查修正 `review-spec.md` C1 已於 spec.md
  /// 落地）：不可在 `AnimatedBuilder.builder` 內呼叫 `setState`（`builder`
  /// 在 build 階段執行，直接呼叫 `_cancelTtsSleepTimer()` 內部的
  /// `setState()` 會立即拋出 `AssertionError`）。改為 `TtsController`
  /// 的獨立 listener，在 build 週期之外偵測「原本正在朗讀、現在變成
  /// idle」的邊緣，此時才安全呼叫 `_cancelTtsSleepTimer()`——涵蓋「章節
  /// 自然播完」與「使用者按下停止」兩種轉為 idle 的途徑，避免朗讀已經
  /// 停止/播完後，定時器仍在背景倒數的視覺落差。
  void _onTtsStatusChanged() {
    _forwardTtsPlaying(_ttsController?.status == TtsPlaybackStatus.playing);
    final isActive = _isTtsActive;
    if (_wasTtsActive && !isActive) {
      _cancelTtsSleepTimer();
    }
    _wasTtsActive = isActive;
  }

  /// 語音選擇 Bottom Sheet（epic-38-reader-chrome-tts-redesign Issue 2，
  /// spec.md §功能③）：本 Epic 只提供單次朗讀 session 內的臨時切換，不
  /// 讀取也不寫入 `TtsDefaults.ttsVoiceId`（spec.md「Out of
  /// Scope」）。比照既有 `TtsDefaultsScreen` 的 `RadioGroup`／`RadioListTile`
  /// 既有呼叫模式（`tts_defaults_screen.dart`），只是資料來源改為即時
  /// 呼叫 [TtsProvider.getAvailableVoices]、選擇結果直接呼叫
  /// [TtsController.setVoice]。`getAvailableVoices()` 回傳空清單時
  /// （裝置未安裝或不支援語音選擇，比照 `TtsDefaultsScreen` 既有處理）
  /// 靜默不開啟選單，不留一個空白 Bottom Sheet。
  ///
  /// **`SingleChildScrollView` 防溢位（審查修正 review-plan-issue-2.md
  /// I1）**：`_showThemedModalBottomSheet` 帶 `isScrollControlled: true`，
  /// 但這只讓 Bottom Sheet 本身可以撐到接近全螢幕高度，不會讓內容自動
  /// 變成可捲動——`TtsDefaultsScreen` 的既有參考實作是整個畫面包在
  /// `ListView` 裡（見 `tts_defaults_screen.dart`），本 Bottom Sheet 若
  /// 直接用 `Column` 承載，裝置若安裝了 Google/Samsung 等第三方 TTS
  /// 引擎、`getAvailableVoices()` 回傳 10-30+ 個語音選項時，會在真機上
  /// 觸發 `RenderFlex overflowed` 溢位。
  Future<void> _openTtsVoicePicker(TtsController controller) async {
    final provider = widget.ttsProvider;
    if (provider == null) return;
    final voices = await provider.getAvailableVoices();
    if (!mounted || voices.isEmpty) return;
    return _showThemedModalBottomSheet<void>(
      builder: (_) => SafeArea(
        child: SingleChildScrollView(
          child: RadioGroup<String>(
            groupValue: controller.voice.id,
            onChanged: (voiceId) {
              if (voiceId == null) return;
              final selected = voices.firstWhere((v) => v.id == voiceId);
              controller.setVoice(selected);
              Navigator.of(context).pop();
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 審查修正（review-plan-issue-2.md M3）：補上標題列，
                // 讓使用者知道目前是在選語音，不是一份沒有上下文的清單。
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(
                    AppLocalizations.of(context)!.readerTtsVoicePickerTitle,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                for (final voice in voices)
                  RadioListTile<String>(
                    key: Key('reader_tts_voice_option_${voice.id}'),
                    title: Text(localizeTtsVoiceName(voice, AppLocalizations.of(context)!)),
                    value: voice.id,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BookFormat format, bool isLandscape) {
    final l10n = AppLocalizations.of(context)!;
    if (format == BookFormat.unknown) {
      // 審查修正（epic-38-reader-chrome-tts-redesign Issue 1）：早退分支
      // 也要疊上 ReaderChromeTopBar，否則 Scaffold.appBar 已恆為 null 後，
      // 使用者在不支援格式畫面完全沒有返回鍵、無法離開閱讀器。
      return Stack(
        children: [
          Center(child: Text(l10n.readerUnsupportedFormatMessage)),
          if (!_cropEditModeActive) _buildChromeTopBar(format),
        ],
      );
    }
    if (_openBookFlow.isFailed) {
      final failure = _openBookFlow.failure!;
      final isRelinking = _openBookFlow.state is OpenBookRelinking;
      // 渲染失敗時直接以錯誤文字取代原生視圖（而非疊加在 Stack 上層），讓
      // 已失敗的 EpubReaderView/PdfReaderView 提早從 widget tree 移除、
      // 觸發其 dispose() 清理原生資源，不讓一個已知失敗的 PlatformView
      // 繼續留在畫面底層。同樣需要疊上 ReaderChromeTopBar 才有返回鍵
      // （理由同上方「不支援格式」分支）。
      return Stack(
        children: [
          Center(
            // epic-15-storage-permission Issue 1：新的分類說明是多行長文字
            // （英文約 140 字元），加上水平間距並置中，避免貼齊螢幕兩側
            // （審查 M-1）。
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    // 依存取探測結果分流。
                    switch (failure.probeResult) {
                      StorageAccessProbeResult.permissionRevoked =>
                        l10n.readerStoragePermissionRevokedMessage,
                      StorageAccessProbeResult.fileNotFound =>
                        l10n.readerStorageFileNotFoundMessage,
                      _ => switch (failure.source) {
                          OpenBookFailureSource.timeout =>
                            l10n.readerOpenBookTimeoutMessage,
                          OpenBookFailureSource.viewError =>
                            failure.viewMessage ??
                                l10n.readerFailedToLoadBookMessage,
                        },
                    },
                    key: const Key('reader_error_text'),
                    textAlign: TextAlign.center,
                  ),
                  // epic-15-storage-permission Issue 2：權限失效／找不到檔案
                  // 且有匯入服務時才提供重新選取。用 OutlinedButton：E-Ink
                  // 高對比模式只有黑白兩色，純填色或純文字按鈕的輪廓容易和
                  // 背景融在一起。
                  if (widget.bookImportService != null &&
                      (failure.probeResult ==
                              StorageAccessProbeResult.permissionRevoked ||
                          failure.probeResult ==
                              StorageAccessProbeResult.fileNotFound)) ...[
                    const SizedBox(height: 24),
                    OutlinedButton(
                      key: const Key('reader_storage_relink_button'),
                      onPressed: isRelinking ? null : _handleRelinkPressed,
                      child: isRelinking
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(
                                key: Key('reader_storage_relink_progress'),
                                strokeWidth: 2,
                              ),
                            )
                          : Text(l10n.readerStorageRelinkButton),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (!_cropEditModeActive) _buildChromeTopBar(format),
        ],
      );
    }
    final body = LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final selection = _currentSelection;
        final pdfSelection = _currentPdfSelection;
        // epic-27-reader-device-compat Issue 11：每次 build 都重新計算，
        // 不快取在 State 欄位——_highlights/_notes 可能在選取進行中被其他
        // 途徑更動，重新計算才能保證資料是最新的。
        final existingItem = selection == null
            ? null
            : resolveEpubExistingAnnotation(
                existingAnnotationId: selection.existingAnnotationId,
                highlights: _highlights,
                notes: _notes,
              );
        final pdfExistingItem = pdfSelection == null
            ? null
            : resolvePdfExistingAnnotation(
                selection: pdfSelection,
                highlights: _highlights,
                notes: _notes,
              );
        return Stack(
          key: const Key('reader_body_stack'),
          children: [
            if (_resolved != null &&
                (!isFoliateFormat(format) ||
                    (_dispatchedIsFixedLayout != null &&
                        _availableFonts != null)))
              _buildNativeView(format, isLandscape),
            // epic-27-reader-device-compat Issue 3：原生渲染畫面（InAppWebView／
            // pdfrx 繪圖表面）在真正收到第一次繪製結果前，緩衝區預設顯示黑色
            // （Android 平台已知行為，見 reviews/bugfix-repro.md Issue 3）。這層
            // 不透明遮罩必須疊在 _buildNativeView 之上（Stack 依 children 清單
            // 順序繪製，後面的 child 疊在前面之上）才能真正蓋住原生視圖輸出的
            // 黑色緩衝區，故放在 _buildNativeView 這個 if 區塊之後；僅在
            // _openBookFlow.isLoading 時顯示——一旦渲染完成立即移除，避免永久蓋住
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
            if (_openBookFlow.isLoading)
              Positioned.fill(
                child: IgnorePointer(
                  child: ColoredBox(
                    key: const Key('reader_render_placeholder_background'),
                    color: Theme.of(context).scaffoldBackgroundColor,
                  ),
                ),
              ),
            // epic-38-reader-chrome-tts-redesign Issue 1：三格式共用同一份
            // ReaderChromeTopBar，取代原本 Foliate／PDF 各自獨立的返回/目錄
            // Positioned（下方 PDF FAB 區塊對應的返回/目錄兩顆已一併刪除，
            // 見 plans/plan-issue-1.md Task 4 Step 2f）。
            //
            // 【2026-09-10 修正】拿掉這裡原本「全螢幕模式開啟時才讓頂部列
            // 跟 _chromeVisible 一起收合」的特例判斷——全螢幕模式只該管
            // Android 系統列，不該影響 App 自己的頂部列（詳見 CONTEXT.md
            // 「全螢幕模式」詞條）。頂部列一律建構，內部頁首／工具列兩組
            // 各自依 `showHeader`／`_chromeVisible` 獨立決定要不要顯示，
            // 兩者都不需要顯示時 `ReaderChromeTopBar` 自己回傳零高度
            // `SizedBox.shrink()`（見該檔案類別文件註解），不需要在呼叫端
            // 額外判斷。
            if (!_cropEditModeActive) _buildChromeTopBar(format),
            // epic-38-reader-chrome-tts-redesign Issue 2：ReaderChromeBottomBar
            // 與 TtsPanel 依 TtsController.status 衍生切換，取代 Issue 1
            // 過渡期的 !_ttsMiniPlayerVisible 手動旗標與 TtsMiniPlayer（見
            // _buildBottomChrome 文件註解）。
            if (isFoliateFormat(format) && _chromeVisible)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _buildBottomChrome(format),
              ),
            // ── PDF FAB 區塊（epic-24-pdf-engine-rebuild Issue 8）─────
            // 返回已由上方 ReaderChromeTopBar 涵蓋，不再需要獨立的
            // Positioned（epic-38-reader-chrome-tts-redesign Issue 1）。目錄
            // 按鈕 2026-09-10 起改移到本列最左側（見 onTocTap）。版面設定／
            // 書籤／筆記／進度合併為 ReaderChromeBottomBar（epic-38-reader-
            // chrome-tts-redesign Issue 1，Step 3b）。
            if (format == BookFormat.pdf && _chromeVisible && !_cropEditModeActive)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: ReaderChromeBottomBar(
                  bookTitle: _displayBookTitle,
                  pageProgressText: _pageProgressText(format),
                  footer: _pdfPageInfo == null
                      ? const SizedBox.shrink()
                      : ReaderFooter(
                          currentPage: _pdfPageInfo!.pageIndex + 1,
                          totalPages: _pdfPageInfo!.totalPages,
                          onPageChanged: (page1Indexed) => PdfReaderView.jumpToPage(
                              _pdfReaderViewKey, page1Indexed - 1),
                        ),
                  onTocTap: _onTocTapFor(format),
                  isBookmarked: _pdfBookmarkAtCurrentPosition != null,
                  onBookmarkTap: widget.bookmarksRepository == null ||
                          _pdfPageInfo == null
                      ? null
                      : _togglePdfBookmark,
                  onAnnotationsTap: widget.bookmarksRepository == null ||
                          !_openBookFlow.isRendered
                      ? null
                      : () => _openNotesSheet(BookFormat.pdf, initialTabIndex: 1),
                  onLayoutTap:
                      _openBookFlow.isRendered ? _openPdfSettings : null,
                  onTtsTap: null, // PDF 目前結構性沒有 TTS 底層能力
                  backgroundColor: _themedFabBackgroundColor,
                  iconColor: _themedFabIconColor,
                  isEinkMode: widget.isEinkMode,
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
                (_epubPositionInfo?.displayTotalPages ?? 0) > 0)
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
                  onCopyPressed: () => _handleCopySelection(selection.text),
                  onDeletePressed: existingItem == null
                      ? null
                      : () => _handleDeleteExistingAnnotation(existingItem),
                  deleteButtonLabel: existingItem == null
                      ? null
                      : _annotationDeleteButtonLabel(existingItem),
                  hasExistingNote: existingItem?.note != null,
                  isEinkMode: widget.isEinkMode,
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
                  onCopyPressed: () => _handleCopySelection(pdfSelection.text),
                  onDeletePressed: pdfExistingItem == null
                      ? null
                      : () => _handlePdfDeleteExistingAnnotation(pdfExistingItem),
                  deleteButtonLabel: pdfExistingItem == null
                      ? null
                      : _annotationDeleteButtonLabel(pdfExistingItem),
                  hasExistingNote: pdfExistingItem?.note != null,
                  isEinkMode: widget.isEinkMode,
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
            if (_openBookFlow.isLoading)
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
    final chapterTitle = currentPath.isEmpty
        ? _displayBookTitle
        : convertText(currentPath.first.title, _textConversionMode);
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
  /// 與 _buildFoliateEpubFooter() 相同（displayPageIndex/displayTotalPages
  /// 皆為 0-indexed，+1 換算為人類慣用的 1-indexed，見
  /// epic-26-architecture-hardening Issue 10：兩個 getter 依格式互斥挑選
  /// 精確視覺頁碼或估計刻度），呼叫端已保證 displayTotalPages > 0 才會
  /// 建構本 widget。跳頁互動已獨立到 reader_foliate_progress_button 開啟的
  /// Bottom Sheet，本 widget 不含任何手勢 widget。
  Widget _buildFoliateProgressText() {
    final info = _epubPositionInfo!;
    final totalPages = info.displayTotalPages!;
    final currentPage =
        ((info.displayPageIndex ?? 0) + 1).clamp(1, totalPages);
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

  /// 流式 EPUB／FXL／CBZ（FoliateReaderView）頁尾：直接使用原生端 relocate
  /// 事件回報的 displayPageIndex／displayTotalPages（epic-26-architecture-
  /// hardening Issue 10：流式格式是 foliate-js SectionProgress 的位元組
  /// 估計刻度，FXL／CBZ 是 FixedLayout 的全書真實視覺頁數，兩個 getter
  /// 依格式互斥挑選，見 EpubPositionInfo 型別文件）。displayPageIndex 為
  /// 0-indexed（比照原生端既有慣例），ReaderFooter 要求 1-indexed，此處
  /// +1 換算。onPageChanged 透過既有 jumpToProgression（Issue 5）換算目標
  /// 頁對應的全書進度比例（流式格式為近似值，非精確反解頁碼；FXL/CBZ 沿用
  /// 既有行為不變）。
  Widget _buildFoliateEpubFooter(EpubPositionInfo info) {
    final totalPages = info.displayTotalPages ?? 0;
    if (totalPages <= 0) return const SizedBox.shrink();
    final currentPage =
        ((info.displayPageIndex ?? 0) + 1).clamp(1, totalPages);
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
  /// 跟隨 Theme.of(context)（epic-22-reader-theme-integration Issue 3；
  /// 2026-09-08 `/grill-with-docs` 使用者需求修正一般主題分支）。
  /// **E-Ink 高對比模式維持原本「與頁面反差最大化」策略**：底色取
  /// `colorScheme.onSurface`、圖示取 `colorScheme.surface`——E-Ink 主題
  /// 本身 onSurface/surface 即為純黑/純白（見 app_theme_data.dart），這樣
  /// 維持既有黑底白圖示的高對比視覺語言，使用者明確要求本次調整不影響
  /// E-Ink 模式。**一般主題（淺色/深色/羊皮紙）改為底色取 `surface`、
  /// 圖示取 `onSurface`**：原本刻意取 `onSurface` 當底色是為了「與頁面
  /// 反差最大化」，但一般主題下 `onSurface` 是近黑色/近白色，導致淺色與
  /// 羊皮紙主題的工具列視覺上都是同一種近黑色，看起來像沒有跟著主題走
  /// （使用者原話：「已經使用佈景，為何工具列還是黑色」）。改用 `surface`
  /// 當底色後，工具列會呈現該主題自己的色調（淺色呈白、羊皮紙呈米黃、
  /// 深色呈深灰），`onSurface` 當圖示色則保證在同一主題下仍可讀。顯示
  /// EPUB 固定版面（漫畫）時維持既有寫死 Colors.black54/Colors.white——
  /// 理由同 _themedTextColor：固定版面頁面內容本身不受本 Epic 影響（通常
  /// 是白底圖片），控制按鈕跟著主題變色容易在不可預期的圖片背景上失去
  /// 可視對比，本次調整範圍不含這個分支。**底色不透明、不加透明度**
  /// （epic-22-reader-theme-integration Issue 4 電子紙硬體對比追加修正）：
  /// 原本沿用改動前 `Colors.black54` 的 54% 透明度，在一般 LCD/OLED
  /// 顯示器上運算出的混合中間灰看起來沒問題，但真機電子紙硬體肉眼實測
  /// 發現，這個「即時運算出來的中間灰」正好落在電子紙灰階抖動渲染最弱的
  /// 區間，圖示完全無法辨識形狀；改用不透明實色色塊後，即使被電子紙抖動
  /// 處理，仍是「一塊清楚色塊 vs. 另一塊清楚色塊」的二元對比。
  Color get _themedFabBackgroundColor {
    if (_isFixedLayout) return Colors.black54;
    final colorScheme = Theme.of(context).colorScheme;
    return widget.isEinkMode ? colorScheme.onSurface : colorScheme.surface;
  }

  Color get _themedFabIconColor {
    if (_isFixedLayout) return Colors.white;
    final colorScheme = Theme.of(context).colorScheme;
    return widget.isEinkMode ? colorScheme.surface : colorScheme.onSurface;
  }

  /// CBZ 朗讀停用播放鍵專用的圖示色（epic-34-tts-readalong Issue 10）——
  /// 與 [_themedFabIconColor] 明確區隔，讓「按了沒用」不需要依賴
  /// tooltip 就能一眼辨識（Issue 9 真機驗收發現：兩者顏色目前完全
  /// 相同，且 tooltip 在觸控裝置上要長按才會出現，等同視覺上仍是靜默
  /// 無反應）。CBZ 恆為固定版面（`Book.isFixedLayout == true`，見
  /// CLAUDE.md「技術棧」段），本 getter 因此不需要比照
  /// [_themedFabIconColor] 依 `_isFixedLayout` 分支——固定寫死單一值
  /// 即可，避免引入永遠不會被走到的分支。**刻意不使用 alpha 透明度**
  /// （例如 `Colors.white.withValues(alpha: 0.4)`）：
  /// epic-22-reader-theme-integration Issue 4 已在真機電子紙硬體實測
  /// 發現，alpha 混合運算出的「即時中間灰」會落在電子紙灰階抖動渲染
  /// 最弱的區間，圖示無法辨識形狀（詳見 [_themedFabIconColor] 上方
  /// doc comment）；改用不透明實色 [Colors.grey]，避免重蹈相同問題。
  Color get _themedTtsDisabledIconColor => Colors.grey;

  /// 首次存取時才建構 [TtsController]（[widget.ttsProvider] 為 `null` 時
  /// 回傳 `null`，播放按鈕不顯示）。[loadSegments] 內部從
  /// [_epubPositionInfo] 反推目前章節 index（`extractChapterIndex()`，
  /// 缺席時預設第 0 章，比照 `main.js` `section?.current ?? 0` 既有預設
  /// 行為），呼叫 [FoliateReaderView.loadTtsSegments]——完全不需要
  /// [TtsController] 知道 [FoliateReaderView] 或 [GlobalKey] 的存在。
  TtsController? get _ttsControllerOrNull {
    final provider = widget.ttsProvider;
    if (provider == null) return null;
    if (_ttsController != null) return _ttsController;
    final controller = TtsController(
      provider: provider,
      player: JustAudioTtsPlayer(),
      loadSegments: () async {
        final chapterIndex =
            extractChapterIndex(_epubPositionInfo?.locatorJson) ?? 0;
        return FoliateReaderView.loadTtsSegments(
          _foliateEpubReaderViewKey,
          chapterIndex,
        );
      },
      // 朗讀同步高亮（epic-34-tts-readalong Issue 3，ADR 0026）：只呼叫
      // 既有 Overlayer 管線，不引用 highlightsRepository/notesRepository。
      // vertical 旗標讀取 _resolved（目前實際生效的排版方向，含使用者
      // 手動切換的結果，非僅書本 CSS 宣告的 _autoDetectedWritingMode），
      // 比照本檔案既有頁首/頁尾直排判斷寫法（_resolved?.writingMode ==
      // WritingMode.vertical）。
      onHighlightSegment: (segment) {
        if (segment == null) {
          FoliateReaderView.clearTtsHighlight(_foliateEpubReaderViewKey);
        } else {
          FoliateReaderView.showTtsHighlight(
            _foliateEpubReaderViewKey,
            segment.cfi,
            vertical: _resolved?.writingMode == WritingMode.vertical,
            einkMode: widget.isEinkMode,
          );
        }
      },
      // 反向查找起始段落（epic-34-tts-readalong Issue 4，2026-08-27
      // Issue 3 真機驗收追加範圍）：從 _epubPositionInfo 讀取畫面目前可視
      // 位置的 cfi（與 loadSegments 內的 extractChapterIndex 同一份
      // _epubPositionInfo，同一次 play() 呼叫序列內不會中途改變），找不到
      // （例如尚未收到任何 onLocatorChanged 事件）時回傳 0，交由
      // TtsController 既有的「從第 0 段開始」向後相容行為處理。
      lookupStartIndex: (segs) async {
        final visibleCfi = extractCfi(_epubPositionInfo?.locatorJson);
        if (visibleCfi == null) return 0;
        return FoliateReaderView.lookupSegmentByCfi(
          _foliateEpubReaderViewKey,
          visibleCfi,
          segs.map((s) => s.cfi).toList(),
        );
      },
    );
    _ttsController = controller;
    controller.addListener(_onTtsStatusChanged);
    widget.ttsAudioHandler?.attachController(controller, bookTitle: _displayBookTitle);
    final focusSource = widget.ttsAudioFocusSource;
    if (focusSource != null) {
      _ttsAudioFocusCoordinator =
          TtsAudioFocusCoordinator(source: focusSource, controller: controller);
    }
    return controller;
  }

  /// 語速調整（epic-34-tts-readalong Issue 5）的 UI 預設清單，`1.0` 為
  /// 正常速度、其餘為使用者常見的加速/減速倍率選項。點擊「語速」按鈕
  /// 依序循環，找不到目前值（理論上不會發生，僅作防禦）時回退到 `1.0`。
  /// 這批數值直接轉發給 [TtsController.setSpeed]，大於 `1.0` 的選項在
  /// 「下一段」合成時會被 `SystemTtsProvider` 既有的 `clamp(0.0, 1.0)`
  /// 收斂成最快速——僅「目前段落」的執行期變速會如實呈現差異（見
  /// `plan-issue-5.md` Global Constraints「語速刻度不做轉換」說明）。
  static const List<double> _ttsSpeedPresets = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];

  double _nextTtsSpeedPreset(double current) {
    final index =
        _ttsSpeedPresets.indexWhere((p) => (p - current).abs() < 0.001);
    if (index == -1) return 1.0;
    return _ttsSpeedPresets[(index + 1) % _ttsSpeedPresets.length];
  }

  Widget _buildNativeView(BookFormat format, bool isLandscape) {
    final resolved = _resolved!;
    final fonts = _availableFonts ?? AvailableFonts.empty;
    // epic-42-text-conversion Issue 2：_resolved 非 null 時 _loaded 恆非
    // null（兩者在 initState()／_handlePrefsChanged() 內永遠同時賦值，見
    // resolve_text_conversion.dart 呼叫端查證）。
    final textConversionMode =
        resolveTextConversion(_prefs, _loaded!.globalPrefs.reading);
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
          filePath: _activeFilePath,
          onPageRendered: _handlePageRendered,
          onError: _handleError,
          onLayoutResolved: _handleFoliateLayoutResolved,
          writingMode: resolved.writingMode,
          pageTurnMode: resolved.pageTurnMode,
          fontFamily: fonts.effectiveFamily(resolved.fontFamily),
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
          textConversion: textConversionMode,
          isLandscape: isLandscape,
          customFonts: fonts.customFonts,
          installedFonts: fonts.installedBuiltIn,
          downloadedFontsDirectory: widget.downloadableFontStore?.directory,
          navZoneActions: resolved.navZoneActions,
          onZoneAction: _handleZoneAction,
          showNavZoneDebugOverlay: resolved.showNavZoneDebugOverlay,
          consoleLogEnabled: resolved.consoleLogEnabled,
          // epic-10-search Issue 5：initialJumpTarget 存在時優先權高於
          // 資料庫既有 lastPosition（spec.md §6），僅此一處決策點，其餘
          // 行為與一般開書完全同構。
          initialLocatorJson:
              widget.initialJumpTarget?.cfi ?? _initialPosition?.epubLocatorJson,
          isComicBookHint: format == BookFormat.cbz,
          dualPageDirection: resolved.dualPageDirection,
          onLocatorChanged: (info) {
            if (!mounted) return;
            // 位置儲存規則已搬到 ReadingPositionSaver（見其文件註解），含
            // 「第一次／第二次回報」的區分。
            _positionSaver?.onEpubLocated(info);
            final previousPosition = _epubPositionInfo;
            if (previousPosition != null) {
              // 不算閱讀活動的回報（epic-9-stats）：開書後第一次回報是初始定位
              // （上面 previousPosition 為 null 的情況）；位置與上一次相同的
              // 重複回報，是 Foliate 在開書後套用樣式重排、或圖片／字型載入後
              // 重新對齊錨點所派發的，不是使用者操作。位置真正改變（翻頁、
              // 捲動、跳轉）才算。只比 cfi 與 index、忽略 fraction：真機日誌
              // 實證重排時同一 cfi 的 fraction 會來回微幅抖動。
              if (_locatorPositionKey(previousPosition.locatorJson) !=
                  _locatorPositionKey(info.locatorJson)) {
                _recordReadingActivity();
              }
            }
            setState(() => _epubPositionInfo = info);
            // 手動導覽自動暫停並清除舊高亮（epic-34-tts-readalong
            // Issue 4）：直接用既有的 nullable _ttsController 欄位（不用
            // _ttsControllerOrNull getter）——尚未曾建構過 TtsController
            // 時（TTS 從未被使用）保持 null，避免每次翻頁都意外觸發
            // lazy 建構；一旦已建構過，無條件呼叫即可，TtsController 自己
            // 在 idle 狀態下呼叫本方法是 no-op（見 handleExternalPositionChange
            // 文件註解，本檔案不需要自行判斷目前是否正在播放）。
            _ttsController?.handleExternalPositionChange();
          },
          onTtsHighlightOutOfSafeWindow: (direction) {
            // epic-34-tts-readalong Issue 8：main.js 偵測到目前朗讀高亮
            // 超出安全視窗時回報方向，這裡觸發一次性翻頁；呼叫前先讓
            // TtsController 抑制緊接著那一次 handleExternalPositionChange()
            // ——否則這次翻頁觸發的 onLocatorChanged 事件會被既有 Issue 4
            // 邏輯誤判為使用者手動導覽，錯誤暫停朗讀（見 tts_controller.dart
            // suppressNextExternalPositionChange() 文件註解）。
            // 節流（見 _lastTtsPageTurnAt 文件註解）：冷卻時間內的重複
            // 觸發直接跳過，不呼叫翻頁——下一個朗讀段落的安全視窗檢查
            // 仍會重新判斷，若還是沒跟上會再次觸發，不會漏掉。
            final now = DateTime.now();
            if (_lastTtsPageTurnAt != null &&
                now.difference(_lastTtsPageTurnAt!) <
                    const Duration(milliseconds: 400)) {
              return;
            }
            _lastTtsPageTurnAt = now;
            _ttsController?.suppressNextExternalPositionChange();
            if (direction == 'prev') {
              FoliateReaderView.previousPage(_foliateEpubReaderViewKey);
            } else {
              FoliateReaderView.nextPage(_foliateEpubReaderViewKey);
            }
          },
          onSelectionChanged: _handleSelectionChanged,
          onSelectionCleared: _handleSelectionCleared,
        );
      case BookFormat.pdf:
        // epic-24-pdf-engine-rebuild：單頁/雙頁（Issue 2）、影像濾鏡/
        // 裁切（Issue 3）、劃線選取回呼（Issue 4）、導航熱區（Issue 8）
        // 皆已補回。
        return PdfReaderView(
          key: _pdfReaderViewKey,
          filePath: _activeFilePath,
          // epic-10-search Issue 5：理由同上方 FoliateReaderView 分支。
          initialPageIndex: widget.initialJumpTarget?.pdfPageIndex ??
              _initialPosition?.pdfPageIndex,
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
            // 位置儲存規則已搬到 ReadingPositionSaver（見其文件註解），理由同
            // 上方 onLocatorChanged 分支。
            _positionSaver?.onPdfPageChanged(info);
            if (_pdfPageInfo != null) {
              _recordReadingActivity();
            }
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
  /// 於 `_openBookFlow.isLoading`（書籍仍在載入中）時直接忽略，
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
    // epic-10-search Issue 5：使用者翻頁或點擊畫面（本方法涵蓋 3×3 熱區
    // 全部四種動作＋音量鍵翻頁，見 spec.md §6「既有的翻頁/點擊處理路徑
    // 一併呼叫清除」）一律提前清除搜尋跳轉暫態高亮，取 3 秒計時與提前
    // 清除兩者較早發生者。無條件呼叫——_clearSearchJumpHighlight()
    // 內部已對「目前根本沒有顯示中的高亮」做早退保護，重複呼叫安全。
    _clearSearchJumpHighlight();
    final format = detectBookFormat(_activeFilePath);
    switch (action) {
      case ZoneAction.previousPage:
        if (_openBookFlow.isLoading) return;
        _recordReadingActivity();
        if (format == BookFormat.pdf) {
          // Epic 26 Issue 3 暫時性真機診斷插樁：量測熱區判定觸發換頁的
          // 時間點，與 TapZoneDetector／長按框選插樁交叉比對，確認是否
          // 為誤觸換頁。診斷結束後需整段移除。
          ReaderConsoleLog.add(
              '[DEBUG-e26i3-zoneaction] previousPage t=${clock.now().millisecondsSinceEpoch}');
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
        if (_openBookFlow.isLoading) return;
        _recordReadingActivity();
        if (format == BookFormat.pdf) {
          // Epic 26 Issue 3 暫時性真機診斷插樁：見上方 previousPage
          // 分支註解，同理。
          ReaderConsoleLog.add(
              '[DEBUG-e26i3-zoneaction] nextPage t=${clock.now().millisecondsSinceEpoch}');
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

/// 睡眠定時器選單（epic-38-reader-chrome-tts-redesign Issue 2）：固定
/// 15/30/45/60 分＋「不限時」清單，[selected] 對應項目打勾（比照既有
/// `library_sort_option_${sortBy.name}` 勾選樣式慣例）。
class _TtsSleepTimerSheet extends StatelessWidget {
  final List<Duration> options;
  final Duration? selected;
  final ValueChanged<Duration?> onSelected;

  const _TtsSleepTimerSheet({
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final primaryColor = Theme.of(context).colorScheme.primary;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final option in options)
            ListTile(
              key: Key('reader_tts_sleep_timer_option_${option.inMinutes}'),
              title: Text(l10n.readerTtsSleepTimerOptionMinutes(option.inMinutes)),
              trailing:
                  selected == option ? Icon(Icons.check, color: primaryColor) : null,
              onTap: () => onSelected(option),
            ),
          ListTile(
            key: const Key('reader_tts_sleep_timer_option_none'),
            title: Text(l10n.readerTtsSleepTimerNoLimitLabel),
            trailing: selected == null ? Icon(Icons.check, color: primaryColor) : null,
            onTap: () => onSelected(null),
          ),
        ],
      ),
    );
  }
}
