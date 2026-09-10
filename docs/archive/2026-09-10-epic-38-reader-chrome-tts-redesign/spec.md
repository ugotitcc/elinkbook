# Epic 38 — 閱讀器 Chrome／TTS 重構：Architecting Spec

自本文件起，這是 `epic-38-reader-chrome-tts-redesign` 的唯一事實來源，取代 `design.md` 中尚未定案的細節；`design.md` 保留作為決策背景與規格矛盾裁定的歷史紀錄。撰寫本文件過程中發現兩處 `design.md`／`reviews/review-design.md` 皆未觸及的範圍缺口（⌕ 搜尋按鈕的實際功能範圍、頂部 Chrome Bar 是否隨 ⬓ 一起收合），已個別詢問人類確認，決議已收斂進下方「Implementation Decisions」與「已解決的規格矛盾（新增）」。

## Problem Statement

`ReaderScreen._buildBody()` 目前是**兩套並存的浮動按鈕系統**：流式 EPUB 與 FXL 共用一組 7 顆 `Positioned` 圓鈕（`epic-18-reader-device-qa` Issue 7 起，`appBar` 對所有 Foliate 格式恆為 `null`，`_buildAppBarActions()` 對 epub/azw3/cbz/txt/md 回傳的動作圖示是永遠不會顯示的死碼），PDF 則是獨立一組 6 顆圓鈕，兩者座標各自寫死、互不共用。`_chromeVisible` 目前是「全部按鈕（含返回、目錄等頂部按鈕）一起顯示/隱藏」的單一開關，使用者一旦透過熱區「選單」動作收起介面，畫面上沒有任何常駐按鈕能再次喚出——只能重新點擊熱區。TTS 播放中的常駐控制列 `TtsMiniPlayer` 是個居中飄浮的膠囊，功能明顯簡化（沒有睡眠定時器、沒有語音顯示），且它的「✕ 關閉」鍵只隱藏面板、不停止播放，與 `DESIGN.md` §13.1「點擊關閉必須停止播放並釋放音訊焦點」的既有規格文字矛盾。三種格式的 Chrome 風格不統一、TTS 控制不完整、直排中文內文起讀邊界被 FXL/PDF 側的按鈕塔遮擋，是本 Epic 要解決的三個核心問題。

## Solution

新建 `ReaderChromeTopBar`（56dp，返回／書名章節／⌕ 搜尋／⬓／☰ 目錄，**在閱讀畫面內永遠顯示，不受 `_chromeVisible` 影響**——這是 prototype 實際行為，見下方「已解決的規格矛盾（新增）」第 2 項）與 `ReaderChromeBottomBar`（受 `_chromeVisible` 控制、三格式共用同一份 widget：頁碼列 34dp／跳頁列 56dp（複用既有 `ReaderFooter`）／選單列 64dp），取代兩套各自獨立的浮動按鈕系統與已死亡的 `_buildAppBarActions()`／`AppBar`。既有 `_chromeVisible` 語意收斂為「只控制底部區塊」，頂部列不再受它影響，同時新增 ⬓ 按鈕作為熱區「選單」動作以外的第二個觸發點，兩者切換同一個 `_chromeVisible` 狀態。新建 `TtsPanel` 取代 `TtsMiniPlayer`，改為與 `ReaderChromeBottomBar` 完全互斥的滿版兩排面板（依 `TtsController.status` 直接衍生顯示狀態，不另設手動旗標），內建「收合成細列」子狀態與新增的睡眠定時器；`TtsController` 新增 `stop()` 方法（真正停止＋釋放音訊焦點），修正既有 `onClose` 只隱藏不停止的語意落差。

## User Stories

### ReaderChromeBar 統一（對應 design.md「Chrome 統一」）

1. 作為讀者，我希望不論在看流式 EPUB、固定版面書籍還是 PDF，畫面上的返回／目錄／書籤／版面／筆記按鈕長得一樣、位置一樣，不用因為格式不同重新學習操作。
2. 作為讀者，我希望收起底部工具列後，畫面頂部仍留著一列可以隨時按 ⬓ 叫回工具列的按鈕，不需要精確點中畫面正中央的熱區才能恢復。
3. 作為讀者，我希望頂部列固定顯示書名與目前章節，不需要另外開目錄才知道自己看到哪裡。
4. 作為讀者，我希望點擊「⌕ 搜尋」按鈕目前只會看到「功能開發中」的提示，不會誤以為它已經可以用（本 Epic 不實作內文搜尋，見「Out of Scope」）。
5. 作為維護者，我希望 `_buildAppBarActions()`／`Scaffold.appBar` 這兩塊確認過完全沒有任何格式會實際顯示它們之後，能安心整段刪除，不留死碼。

### 沉浸模式雙觸發（對應 design.md「沉浸模式雙觸發」）

6. 作為讀者，我希望除了熱區「選單」動作，也能直接點擊頂部列的 ⬓ 按鈕收起/展開底部工具列，兩種方式效果相同。
7. 作為讀者，我希望收起底部工具列時，只有底部（頁碼列/跳頁列/選單列，或 TTS 面板）消失，頂部列（含 ⬓ 本身）繼續留著，讓我隨時能點回來。
8. 作為讀者，我希望朗讀進行中收起底部工具列時，朗讀不會被中斷，畫面上會有一個小喇叭圖示提醒我朗讀仍在進行。

### TTS 常駐面板重構（對應 design.md「TTS 常駐面板重構」）

9. 作為使用朗讀功能的讀者，我希望點擊底部「◗ 朗讀」後，畫面切換成朗讀專屬的控制面板，跟一般閱讀時的工具列不會同時出現。
10. 作為使用朗讀功能的讀者，我希望面板裡有「收合成細列」按鈕，按下後只是把上排大按鈕（上一句/播放/下一句/語速/語音）藏起來，下排（睡眠定時器/收合/停止）繼續看得到，朗讀不受影響。
11. 作為使用朗讀功能的讀者，我希望面板裡的「停止朗讀」按鈕會真正停止播放，並讓畫面回到一般閱讀工具列，不是只把面板藏起來、朗讀卻繼續播。
12. 作為使用朗讀功能的讀者，我希望章節朗讀完畢（沒有按停止）時，畫面能自動回到一般閱讀工具列，不會卡在一個「已經沒在朗讀」的面板上。
13. 作為使用 CBZ（純圖像格式）的讀者，我希望「◗ 朗讀」面板打開後看到的是停用狀態的播放控制（因為沒有文字可唸），跟目前 `TtsMiniPlayer` 的既有行為一樣，不會忽然多出一個能點但沒作用的按鈕。

### 睡眠定時器（對應 design.md「睡眠定時器」）

14. 作為睡前使用朗讀功能的讀者，我希望在面板裡設定「30 分鐘後暫停」，不小心睡著也不會讓 App 整晚朗讀耗電。
15. 作為讀者，我希望睡眠定時器選項是 15/30/45/60 分鐘＋「不限時」固定清單，用點的就能選，不需要自己輸入數字。
16. 作為讀者，我希望定時器時間到時朗讀是「暫停」，不是「停止」——隔天可以直接按播放從原本位置接著聽，不用重新找進度。

## Implementation Decisions

### 功能①：`ReaderChromeTopBar`＋死碼清除（對應 Issue「Chrome Bar 統一」，含 review C1／M1 訂正落地）

#### 模組

- **`app/lib/screens/reader_chrome_top_bar.dart`（新）**——`StatelessWidget`，格式無關，56dp 高，五個固定位置：

  ```dart
  class ReaderChromeTopBar extends StatelessWidget {
    final VoidCallback onBack;
    final String chapterTitle; // ReaderScreen 已算好的文字，含「閱讀器」回退值
    final VoidCallback onSearchTap; // 本 Epic 內固定為假按鈕行為，見 Out of Scope
    final bool isBottomChromeVisible; // 給 ⬓ 圖示切換視覺狀態用，非本 widget 自己的狀態
    final VoidCallback onToggleBottomChrome;
    final VoidCallback? onTocTap; // null 時目錄按鈕停用（比照既有 _tocLoaded 防呆慣例）
    final bool showTtsIndicator; // 見功能②「小喇叭圖示」
    final Color backgroundColor;
    final Color iconColor;
    const ReaderChromeTopBar({
      super.key,
      required this.onBack,
      required this.chapterTitle,
      required this.onSearchTap,
      required this.isBottomChromeVisible,
      required this.onToggleBottomChrome,
      required this.onTocTap,
      required this.showTtsIndicator,
      required this.backgroundColor,
      required this.iconColor,
    });
  }
  ```
  Key：`reader_chrome_back_button`／`reader_chrome_title`／`reader_chrome_search_button`／`reader_chrome_immersive_toggle_button`／`reader_chrome_toc_button`／`reader_chrome_tts_indicator_icon`（`showTtsIndicator` 為 `false` 時整個圖示不渲染，不是隱藏，比照 `epic-36` `showRemoveCache` 既有的「能力不存在時不渲染」慣例）。觸控目標依 `DESIGN.md#L184-186` §7.2：一般模式 48dp、`isEinkMode` 時 56dp（新增 `isEinkMode` 建構參數，`IconButton.styleFrom(minimumSize:...)`，比照既有 `_appBarButtonMinWidth` 收斂手法但改用官方觸控目標尺寸而非既有 AppBar 瘦身的 32dp）。
- **`reader_screen.dart` 異動**：
  - `Scaffold.appBar` 固定寫死為 `null`（`reader_screen.dart:1911-1920` 整段條件式與 `AppBar(...)` 建構整段刪除）；`_buildAppBarTitle()`／`_buildAppBarActions()`（`reader_screen.dart:1934-1957`／`:1981-2053`）兩個方法整段刪除——確認過（見上方 Problem Statement）沒有任何格式組合會讓 `appBar` 非 `null`，這兩個方法在目前程式碼裡已經是不可觸及的死碼。
  - `_buildBody()` 內原本三組各自獨立的頂部 `Positioned`（Foliate 返回/目錄按鈕 `reader_screen.dart:2162-2195`、PDF 返回/目錄按鈕 `reader_screen.dart:2360-2391`）整段移除，改為在 `Stack` 最上層（`Positioned.fill` 之外，一律渲染、與 `_chromeVisible` 無關）插入單一 `ReaderChromeTopBar` 實例，依 `format` 分派 `onTocTap`（Foliate → `_openToc`，PDF → `_openPdfToc`，兩者既有的 `_tocLoaded`／`_pdfTocLoaded` 防呆條件原樣保留、改用三元運算式決定傳 `null` 還是實際方法）。`isBottomChromeVisible`／`onToggleBottomChrome` 接下來由功能②定義。
  - `chapterTitle` 計算邏輯**直接複用** `_buildAppBarTitle()` 刪除前的既有邏輯（`TocNavigator.findCurrentPath` + `currentPath.last.title` + 「閱讀器」回退值），搬進一個新的私有方法 `String _currentChapterTitle(BookFormat format)`（PDF 用 `PdfTocNavigator.findCurrentPath(_pdfTocEntries, _pdfPageInfo?.pageIndex)` 對稱實作，Foliate 用既有 `TocNavigator.findCurrentPath(_tocEntries, _epubPositionInfo?.progression)`）——**與舊 `_buildAppBarTitle()` 的關鍵差異**：新版**不再受 `_resolved.showHeader` 偏好門檻限制**，一律顯示章節名稱（未偵測到章節時回退「閱讀器」文字）。`showHeader`／`showFooter` 偏好維持原本語意不變：只控制「`_chromeVisible == false` 時，是否仍在螢幕邊角保留一小段常駐頁首/頁尾文字」（`reader_screen.dart:2473-2509` 這段既有邏輯完全不動，是完全獨立於本 Chrome Bar 重構的既有機制，見「已解決的規格矛盾（新增）」第 3 項）。

### 功能②：`ReaderChromeBottomBar`＋沉浸模式雙觸發語意修正（對應 Issue「Chrome Bar 統一」＋「沉浸模式雙觸發」，含 review M2 訂正落地）

#### 模組

- **`app/lib/screens/reader_chrome_bottom_bar.dart`（新）**——`StatelessWidget`，三列固定結構（`DESIGN.md` §12 需依此訂正）：

  ```dart
  class ReaderChromeBottomBar extends StatelessWidget {
    final String bookTitle;
    final String pageProgressText; // 「184 / 468 · 39%」，ReaderScreen 已算好
    final int currentPage; // 1-indexed，餵給內嵌 ReaderFooter
    final int totalPages;
    final ValueChanged<int> onPageChanged;
    final bool isBookmarked;
    final VoidCallback onBookmarkTap;
    final VoidCallback onAnnotationsTap; // 開 NotesBottomSheet(initialTabIndex: 1)
    final VoidCallback onLayoutTap;
    final VoidCallback? onTtsTap; // null 時「朗讀」整項不渲染，見下方 PDF/CBZ 說明
    final Color backgroundColor;
    final Color iconColor;
    final bool isEinkMode;
    const ReaderChromeBottomBar({ super.key, /* ...同上，皆 required 除 isEinkMode 預設 false */ });
  }
  ```
  三列：
  1. **頁碼列（34dp）**：`Text(bookTitle)` ＋ `Text(pageProgressText, key: Key('reader_chrome_page_info_text'))`，純顯示。
  2. **跳頁列（56dp）**：**直接內嵌既有 `ReaderFooter(currentPage:, totalPages:, onPageChanged:)`**（`app/lib/screens/reader_footer.dart`，`key: Key('reader_footer')` 不變）——`ReaderFooter` 已經是「頁碼＋跳頁輸入框＋可拖曳進度滑桿」的完整實作，prototype 的「跳」按鈕本身在 HTML 原型裡也只是 `showNotification('開啟輸入頁碼跳轉')` 假按鈕（未真正實作），既有 `ReaderFooter` 的內嵌輸入框已提供功能更完整的等價體驗，本 Epic **不**額外複刻 prototype 的獨立「跳」按鈕彈窗，直接沿用 `ReaderFooter`，這是比 prototype 更進一步、不是縮水。
  3. **選單列（64dp，4 顆，`DESIGN.md` §12 對應段落需訂正為此清單）**：⚑ 書籤（`reader_chrome_bookmark_button`）／✎ 劃線筆記（`reader_chrome_annotations_button`）／Aa 版面（`reader_chrome_layout_button`）／◗ 朗讀（`reader_chrome_tts_button`，`onTtsTap == null` 時整項不渲染，非停用——PDF 目前完全沒有 TTS 底層能力，比照既有 PDF FAB 群組本來就不含朗讀按鈕的既有事實，不是本 Epic 新增的限制，也不詢問使用者確認）。
- **`reader_screen.dart` 異動**：
  - **`_chromeVisible` 語意收斂**：現有欄位保留、名稱不變，但**只用來控制 `ReaderChromeBottomBar`／`TtsPanel` 這個底部區塊的顯示，不再影響 `ReaderChromeTopBar`**（功能①已描述，頂部列一律渲染）。`_handleZoneAction`（`reader_screen.dart:3071-3072`）的 `ZoneAction.menu` 分支維持 `setState(() => _chromeVisible = !_chromeVisible)` 不變——它本來就只切換這一個旗標，語意變化完全來自「誰在讀這個旗標」，不是旗標本身的賦值邏輯改變。
  - `ReaderChromeTopBar` 新增 `onToggleBottomChrome: () => setState(() => _chromeVisible = !_chromeVisible)`——與熱區「選單」動作**呼叫同一行程式碼、切換同一個欄位**，滿足「兩種觸發方式並存、切換同一狀態」（design.md 已解決的規格矛盾 #3）。
  - `_buildBody()` 內三格式各自的底部功能按鈕群（Foliate `reader_screen.dart:2196-2276`＋PDF `reader_screen.dart:2392-2472`，共 4 顆：版面設定／書籤/toggle／筆記／進度-跳頁；「返回」「目錄」已移到功能①）整段移除，改為單一 `if (_chromeVisible) ReaderChromeBottomBar(...)`（`_isTtsActive == true` 時改渲染 `TtsPanel`，見功能③），依 `format` 分派 `pageProgressText`／`currentPage`／`totalPages`／`isBookmarked`／各 `onXxxTap` 回呼到既有的 `_toggleBookmark`／`_togglePdfBookmark`／`_openLayoutSettings`／`_openFxlSettings`／`_openPdfSettings`／`_openNotesSheet` 等既有方法，行為與既有邏輯完全相同，只是呼叫路徑從各自的 `Positioned` IconButton 改為統一 widget 的具名參數。

### 功能③：`TtsPanel` 重構（對應 Issue「TTS 常駐面板重構」，含 review I1／M3 訂正落地）

#### 模組

- **`TtsController.stop()`（新方法，`app/lib/reader/tts_controller.dart`）**——修正 `TtsMiniPlayer.onClose` 只隱藏不停止的既有落差（`DESIGN.md` §13.1「點擊『✕ 關閉』必須停止 TTS 播放並釋放音訊焦點」，design.md L59 已裁定的方向）：
  ```dart
  Future<void> stop() async {
    if (_disposed) return;
    _playGeneration++;
    _segmentGeneration++;
    _suppressExpiryTimer?.cancel();
    _suppressNextPositionChange = false;
    _status = TtsPlaybackStatus.idle;
    _currentIndex = -1;
    _segments = const [];
    try {
      await player.stop().catchError((_) {});
    } catch (_) {}
    onHighlightSegment?.call(null);
    notifyListeners();
  }
  ```
  `_playGeneration`／`_segmentGeneration` 無條件遞增，比照既有 `handleExternalPositionChange()` 的既有防重入慣例（讓正在進行中的 `play()`/`_playCurrentSegment()` 呼叫在下一次 await 之後安全放棄，不會在 `stop()` 呼叫後又寫回過期狀態）。
- **`TtsAudioPlayer.stop()`（新抽象方法＋ `JustAudioTtsPlayer` 實作，`app/lib/reader/tts_audio_player.dart`）**：
  ```dart
  Future<void> stop();
  // JustAudioTtsPlayer：
  @override
  Future<void> stop() => _player.stop();
  ```
  `just_audio` 的 `AudioPlayer.stop()`（相對於既有 `pause()`）會釋放底層平台音訊資源／音訊焦點，`pause()` 則保留焦點以便快速恢復——這正是「暫停」與「真正停止」在音訊焦點語意上的既有官方區別，`TtsController.pause()` 維持呼叫 `player.pause()` 不變，只有新的 `stop()` 呼叫 `player.stop()`。`test/support/fake_tts_audio_player.dart` 需同步新增 `stop()` 假實作（記錄呼叫次數供測試斷言）。
- **`app/lib/screens/tts_panel.dart`（新，取代 `app/lib/screens/tts_mini_player.dart`）**——`StatelessWidget`，格式無關，兩排＋收合子狀態：
  ```dart
  class TtsPanel extends StatelessWidget {
    final TtsPlaybackStatus status;
    final double speed;
    final bool isCbz; // 沿用既有 TtsMiniPlayer.isCbz 既有降級語意
    final bool isCollapsed; // 「收合成細列」子狀態，由 ReaderScreen 持有
    final Duration? sleepTimerRemaining; // null＝未設定，見下方睡眠定時器
    final Color backgroundColor;
    final Color iconColor;
    final Color disabledIconColor;
    final VoidCallback onPlayPause;
    final VoidCallback onPrevious;
    final VoidCallback onNext;
    final VoidCallback onSpeedTap;
    final VoidCallback onVoiceTap;
    final VoidCallback onSleepTimerTap;
    final VoidCallback onToggleCollapse;
    final VoidCallback onStop;
    const TtsPanel({ super.key, /* ...皆 required 除 sleepTimerRemaining */ });
  }
  ```
  - **展開控制列**（52/56dp 大按鈕，`isCollapsed == true` 時整排不渲染）：`reader_tts_previous_button`／`reader_tts_play_pause_button`／`reader_tts_next_button`／`reader_tts_speed_button`（皆沿用 `TtsMiniPlayer` 既有 Key 字面值，圖示/文字內容不變，只是版面從飄浮膠囊改為滿版兩排）＋新增 `reader_tts_voice_button`（語音選擇，本 Epic 只需開啟既有 `SystemTtsProvider.getAvailableVoices()`——見 `epic-36` `TtsDefaultsScreen` 已建立的既有呼叫模式——挑選後呼叫 `provider.synthesize` 的 `voice` 參數，UI 為簡單 `RadioListTile` 清單 Bottom Sheet，不需新建元件）。`isCbz == true` 時（比照既有 `TtsMiniPlayer` 降級邏輯）只渲染停用狀態的 `reader_tts_play_pause_button`（`onPressed: null`，tooltip「CBZ 為純圖像格式，不支援語音朗讀」），不渲染上一句/下一句/語速/語音四顆。
  - **底層動作列**（睡眠定時器／收合/展開／停止，恆常渲染，不受 `isCollapsed` 影響）：`reader_tts_sleep_timer_button`（label 依 `sleepTimerRemaining` 顯示「睡眠定時器」或「睡眠 N 分」，見下方睡眠定時器功能）／`reader_tts_panel_collapse_button`（`isCollapsed` 為 `true` 時 label「展開控制列」、`false` 時「收合成細列」，比照 prototype `collapseTts()` 文字切換）／`reader_tts_stop_button`（呼叫 `onStop`，樣式沿用 prototype 的實心黑底強調樣式）。
  - **CBZ 底層動作列不停用**——收合/停止對 CBZ 仍有意義（使用者仍可能想直接跳出朗讀模式，即使 CBZ 從未真的開始播放），沿用既有「isCbz 只影響播放相關按鈕」的既有降級邊界（`TtsMiniPlayer` 既有實作已是如此，非本 Epic 新增行為）。
- **`reader_screen.dart` 異動**：
  - **狀態衍生而非新增手動旗標**（避免手動狀態與 `TtsController.status` 不同步的風險）：
    ```dart
    Widget _buildBottomChrome(BookFormat format) {
      final controller = _ttsController; // 私有欄位，不觸發 lazy 建構
      if (controller == null) return ReaderChromeBottomBar(...);
      return AnimatedBuilder(
        animation: controller,
        builder: (context, _) => controller.status == TtsPlaybackStatus.idle
            ? ReaderChromeBottomBar(...)
            : TtsPanel(
                status: controller.status,
                speed: controller.speed,
                isCbz: format == BookFormat.cbz,
                isCollapsed: _ttsPanelCollapsed,
                sleepTimerRemaining: _ttsSleepTimerDuration,
                onPlayPause: controller.status == TtsPlaybackStatus.playing
                    ? controller.pause : () => controller.play(),
                onPrevious: controller.previousSegment,
                onNext: controller.nextSegment,
                onSpeedTap: () => controller.setSpeed(_nextTtsSpeedPreset(controller.speed)),
                onVoiceTap: () => _openTtsVoicePicker(controller),
                onSleepTimerTap: _openSleepTimerPicker,
                onToggleCollapse: () => setState(() => _ttsPanelCollapsed = !_ttsPanelCollapsed),
                onStop: () async {
                  _cancelTtsSleepTimer();
                  await controller.stop();
                },
                backgroundColor: _themedFabBackgroundColor,
                iconColor: _themedFabIconColor,
                disabledIconColor: _themedTtsDisabledIconColor,
              ),
      );
    }
    ```
    在 `_ttsController == null`（使用者從未按過「朗讀」，見下方）時完全不建構 `AnimatedBuilder`，避免無謂訂閱；比照既有「不提前建構 `TtsController`」的既有效能考量（`_ttsControllerOrNull` doc comment 既有說明）。**章節朗讀自然播完（`_handleSegmentCompleted` 內部把 `status` 重設回 `idle`）時，`AnimatedBuilder` 會自動偵測到 `status == idle` 並切回 `ReaderChromeBottomBar`，不需要額外程式碼**——這正是採用「衍生而非手動旗標」設計的直接效益（解決使用者故事 12）。
  - `_isTtsActive` 衍生 getter（供功能②的「小喇叭圖示」判斷使用）：`bool get _isTtsActive => _ttsController != null && _ttsController!.status != TtsPlaybackStatus.idle;`。
  - `ReaderChromeBottomBar.onTtsTap`（底部「◗ 朗讀」按鈕）：`widget.ttsProvider == null ? null : () => _ttsControllerOrNull!.play()`——第一次點擊觸發 `_ttsControllerOrNull` 的 lazy 建構（既有既定行為不變），`play()` 内部完成 `loadSegments()`/`lookupStartIndex()` 兩次非同步往返後 `status` 才會變成 `playing`，`AnimatedBuilder` 會在那一刻才切換到 `TtsPanel`——這段短暫延遲（通常 <1 秒的 JS bridge 往返＋首段語音合成時間）是既有 `play()` 既有非同步流程的真實反映，prototype 為靜態稿沒有這個延遲，本 Epic 不新增 loading 過場動畫掩蓋它（`DESIGN.md` §18 E-Ink 零動畫轉場精神下，簡單的「按下去、等音訊、面板浮現」即可，避免新增額外的過場元件）。
  - **舊 `TtsMiniPlayer` 相關程式碼整段移除**：`_ttsMiniPlayerVisible`／`_ttsMiniPlayerBottomOffset`／`reader_foliate_tts_toggle_button` 對應的獨立 Positioned FAB（`reader_screen.dart:2277-2351`）整段刪除——「顯示/隱藏朗讀控制列」這個獨立開關被「朗讀中永遠顯示 `TtsPanel`，非朗讀中永遠顯示 `ReaderChromeBottomBar`」的互斥狀態取代，語意上不再需要獨立的可見性旗標。`app/lib/screens/tts_mini_player.dart` 與 `app/test/screens/tts_mini_player_test.dart` 整份刪除。
  - **小喇叭圖示（功能②`ReaderChromeTopBar.showTtsIndicator`）**：`showTtsIndicator: _isTtsActive && !_chromeVisible`——只有「朗讀進行中」且「底部已收合」同時成立時才顯示，對應 design.md L60「⬓ 全收：整個 TTS 面板一起消失⋯新增小喇叭圖示」；`_isTtsActive` 為 `true` 但 `_chromeVisible` 也是 `true` 時（`TtsPanel` 本身可見），面板自己已呈現播放狀態，不需要額外指示。

### 功能④：睡眠定時器（對應 Issue「睡眠定時器」）

#### 模組

- **`reader_screen.dart` 新增狀態與方法**（不新建獨立類別——邏輯僅一個 `Timer` 欄位＋一個回呼，比照 CLAUDE.md「不要為單一用途程式碼建立抽象」原則，維持與既有 `Timer`／`clock` 使用慣例一致的內聯寫法）：
  ```dart
  Timer? _ttsSleepTimer;
  Duration? _ttsSleepTimerDuration; // 目前選定的時長（用於面板 label），到期或取消後歸零

  void _setTtsSleepTimer(Duration? duration) {
    _ttsSleepTimer?.cancel();
    setState(() => _ttsSleepTimerDuration = duration);
    if (duration == null) return; // 「不限時」：取消計時器，不排新的
    _ttsSleepTimer = Timer(duration, () {
      _ttsController?.pause();
      if (mounted) setState(() => _ttsSleepTimerDuration = null);
    });
  }

  void _cancelTtsSleepTimer() => _setTtsSleepTimer(null);

  Future<void> _openSleepTimerPicker() {
    return _showThemedModalBottomSheet<void>(
      builder: (_) => _TtsSleepTimerSheet(
        options: const [
          Duration(minutes: 15), Duration(minutes: 30),
          Duration(minutes: 45), Duration(minutes: 60),
        ],
        selected: _ttsSleepTimerDuration,
        onSelected: (duration) {
          Navigator.of(context).pop();
          _setTtsSleepTimer(duration);
        },
      ),
    );
  }
  ```
  `_TtsSleepTimerSheet` 為 `reader_screen.dart` 內新增的簡單私有 `StatelessWidget`：固定清單（15/30/45/60 分，`key: Key('reader_tts_sleep_timer_option_${minutes}')`）＋一項「不限時」（`key: Key('reader_tts_sleep_timer_option_none')`，點擊呼叫 `onSelected(null)`），`selected` 對應項目打勾（比照既有 `library_sort_option_${sortBy.name}` 勾選樣式慣例）。
  - **`stop()`／自然播完時取消定時器**：`TtsPanel.onStop` 回呼（功能③已列出）與章節自然播完，都需要呼叫 `_cancelTtsSleepTimer()`——避免朗讀已經停止／播完後，定時器仍在背景倒數、時間到時對一個已經是 `idle` 的 controller 呼叫 `pause()`（雖然 `TtsController.pause()` 本身在非 `playing` 狀態下是 no-op、無害，但殘留的計時器與 `_ttsSleepTimerDuration` 顯示值會造成「明明已經停止朗讀，面板卻顯示還在倒數睡眠定時器」的視覺落差）。
  - **不可在 `AnimatedBuilder.builder` 內做這件事（審查修正 C1）**：`builder` 在 Flutter build 階段執行，`_cancelTtsSleepTimer()` 內部的 `setState()` 會立即拋出 `AssertionError: setState() or markNeedsBuild() called during build`——只要使用者正在朗讀且已設定睡眠定時器，章節自然播完的當下就會必然崩潰，不是理論風險。正確作法是在 `_ttsControllerOrNull` getter 建構 `TtsController` 完成當下（`reader_screen.dart:2828` `_ttsController = controller;` 之後）額外掛一個專屬 listener，讓邊緣偵測與 `setState()` 都發生在 build 週期之外（`notifyListeners()` 呼叫時機不等同於某個 widget 正在 `build()`）：
    ```dart
    bool _wasTtsActive = false;

    void _onTtsStatusChanged() {
      final isActive = _isTtsActive;
      if (_wasTtsActive && !isActive) {
        _cancelTtsSleepTimer();
      }
      _wasTtsActive = isActive;
    }
    ```
    `_ttsControllerOrNull` getter 內 `_ttsController = controller;` 之後追加 `controller.addListener(_onTtsStatusChanged);`；`dispose()` 新增 `_ttsController?.removeListener(_onTtsStatusChanged);`（置於既有 `_ttsController?.dispose()` 之前）。`_buildBottomChrome` 的 `AnimatedBuilder` 維持功能③原樣不變，純粹依 `controller.status` 決定渲染哪個 widget，不再承擔任何邊緣偵測或副作用職責——`AnimatedBuilder.builder` 必須是純函式，不得在其中呼叫 `setState`。
  - **`dispose()`**：`_ttsSleepTimer?.cancel()` 加入既有 `dispose()` 方法。

## Testing Decisions

- **一般原則**：延續既有「`Key` 斷言＋純 Dart 單元測試分流」慣例（`tts_controller_test.dart`／`tts_mini_player_test.dart` 既有寫法），計時器相關行為一律用 `package:fake_async` 的 `FakeAsync`（或既有 `flutter_test` `tester.pump(duration)` 慣例，比照本專案 `TapZoneDetector` 既有的 `clock`／`FakeAsync` 測試模式）驗證，不使用真實 `Future.delayed`/`Timer` 等待。
- **`ReaderChromeTopBar`**：獨立 widget test——五個按鈕點擊觸發對應 callback；`onTocTap == null` 時目錄按鈕為停用狀態；`showTtsIndicator` 為 `true`/`false` 時小喇叭圖示存在/不存在（`findsOneWidget`/`findsNothing`，不是停用狀態斷言）；`isEinkMode: true` 時觸控目標尺寸為 56dp——**斷言方式須用 `tester.getSize(find.byKey(...))` 檢查實際渲染尺寸，不能只驗證 `styleFrom(minimumSize:...)` 建構參數有被傳入**（審查修正 M1：`reader_screen.dart:1965-1974` 既有註解已記錄 Material 3 `IconButton` 的 `padding`/`constraints` 建構子參數在本專案 Flutter 版本下對實際渲染尺寸完全無效、必須靠 `style` 才生效這個已知陷阱，測試需要真的量出渲染尺寸才能確認 `styleFrom` 這條路徑本身有效，不能假設「傳了參數就等於生效」）。
- **`ReaderChromeBottomBar`**：獨立 widget test——`onTtsTap == null` 時「朗讀」項目整個不存在於 widget 樹；內嵌 `ReaderFooter` 的既有測試（`reader_footer_test.dart`，若存在）不受影響，`ReaderChromeBottomBar` 只需驗證正確傳遞 `currentPage`/`totalPages`/`onPageChanged` 給它，不重複測試 `ReaderFooter` 本身邏輯。
- **`TtsController.stop()`**：純 Dart 單元測試（`tts_controller_test.dart` 新增案例）——`playing`/`paused` 狀態下呼叫 `stop()` 後 `status == idle`、`segments`/`currentIndex` 清空、`onHighlightSegment` 收到 `null`、`fake_tts_audio_player.dart` 的 `stop()` 呼叫次數為 1（而非 `pause()`）；`stop()` 呼叫期間若有進行中的 `play()`（`_isLoadingSegments` 為 `true`）需驗證世代編號機制正確中止該次呼叫，不會在 `stop()` 之後又把過期資料寫回 `_segments`（比照既有 `_playGeneration` 相關既有測試手法）。
- **`TtsPanel`**：獨立 widget test，不透過 `ReaderScreen` 間接測——`isCollapsed`/`isCbz` 各種組合下對應按鈕存在/不存在（`isCollapsed: true` 時展開列四顆按鈕 `findsNothing`，底層動作列三顆仍 `findsOneWidget`；`isCbz: true` 時只有停用播放鍵，其餘四顆不存在）；`sleepTimerRemaining` 非 `null`/`null` 時按鈕文字正確反映。
- **`ReaderScreen` 整合層**：擴充既有 `reader_screen_test.dart`——
  - 驗證 `_chromeVisible` 切換只影響底部區塊、`ReaderChromeTopBar` 全程可見（斷言 `find.byType(ReaderChromeTopBar)` 恆為 `findsOneWidget`，`_chromeVisible` 為 `false` 時 `find.byType(ReaderChromeBottomBar)`／`find.byType(TtsPanel)` 皆為 `findsNothing`）——這是修正 review 訂正後最核心的回歸測試，明確斷言「頂部與底部各自獨立收合」這個與既有 `_chromeVisible` 舊語意（全部一起收合）不同的新行為。
  - 觸發播放後（fake `TtsProvider`/`TtsAudioPlayer`）驗證畫面從 `ReaderChromeBottomBar` 切換為 `TtsPanel`；模擬章節自然播完（呼叫 fake player 的 `completedStream` 直到最後一段）後驗證自動切回 `ReaderChromeBottomBar`，且睡眠定時器（若先前有設定）已被取消（不再顯示倒數 label）。
  - `_buildAppBarActions()`／`Scaffold.appBar` 刪除後，既有依賴這兩者的測試（若有，例如舊的 `reader_appbar_chapter_title` 相關斷言）需要盤點並改為斷言 `ReaderChromeTopBar` 的 `reader_chrome_title`。
- **`_setTtsSleepTimer`／`_openSleepTimerPicker`**：widget test 用 `FakeAsync`——選擇「30 分」後 `_ttsSleepTimerDuration` 更新、面板 label 反映；`elapse(Duration(minutes: 30))` 後驗證 `controller.pause()` 被呼叫且 `_ttsSleepTimerDuration` 歸零；選擇「不限時」後計時器被取消、`elapse()` 不再觸發 `pause()`。

## Out of Scope

- **⌕ 搜尋按鈕的真實內文搜尋功能**（人類確認決議）：prototype 本身這顆按鈕也只是 `showNotification('搜尋內文')` 假按鈕，未真正實作。本 Epic 對所有格式（含已有底層 `PdfReaderView.search()` 能力的 PDF）一律只接一個 `showNotification`／`SnackBar` 等級的「功能開發中」提示（`onSearchTap` 固定實作為此提示，不接任何真實搜尋邏輯），PDF 既有的內文搜尋能力**維持現狀**（繼續透過 `_openPdfToc` 開啟的 `TocBottomSheet` `searchTabContent: PdfSearchPanel(...)` 分頁存取——審查修正 C2：不是 `_openPdfProgressSheet`，後者開啟的是純 `ReaderFooter`、不含任何搜尋分頁，功能①已規劃 `ReaderChromeTopBar.onTocTap` 對 PDF 分派到 `_openPdfToc`，本 Epic 重構後這條既有搜尋入口依然可達，不搬移、不重複實作），Foliate 格式的內文搜尋能力（目前完全不存在）也不在本 Epic新增。真正把 ⌕ 接上搜尋功能（含是否要新增 Foliate 內文搜尋能力）留待後續 Epic。
- **TTS 面板句數進度／文字摘要**（人類確認決議，`review-design.md` I1）：維持 prototype 原樣，兩者皆不納入，`DESIGN.md` §13.2「文字摘要」需求視為降級。
- **語速控制改為離散選擇清單/Dropdown**（`DESIGN.md` §13.2 原文字）：本 Epic 沿用既有 `_nextTtsSpeedPreset` 的「點擊循環」既有互動模式（`reader_tts_speed_button` 既有行為），prototype 本身呈現的也是單一按鈕顯示目前倍率、無下拉選單視覺，與現有實作一致，不視為需要变更的範圍。
- **PDF／CBZ 的 TTS 全新支援**：PDF 目前完全沒有 TTS 底層能力（無 CFI 等價定位機制可供 `TtsController.loadSegments` 使用），本 Epic 不新增；`ReaderChromeBottomBar.onTtsTap` 對 PDF 恆傳 `null`，「朗讀」選項不渲染，維持既有事實。CBZ 沿用既有降級顯示（見功能③），不是新增支援，也不是移除既有能力。
- **`DESIGN.md` §12.2「直排頁面標題與頁尾自適應」**（`RotatedBox` 轉向問題）：design.md 已列為本輪 Discovery 未觸及，本 spec 同樣不處理，需另立工單或後續 Epic 確認範圍。
- **語音選擇的完整偏好持久化串接**（是否記住上次選擇的語音供下次朗讀直接套用）：`epic-36` 的 `TtsDefaultsScreen`／`GlobalReaderPrefs.ttsVoiceId` 已提供設定畫面層級的全域預設值寫入，但明確排除「播放端何時讀取套用」（見 `epic-36` spec.md「Out of Scope」）。本 Epic 的 `TtsPanel.onVoiceTap` 只提供「單次朗讀 session 內臨時切換語音」，不讀取也不寫入 `GlobalReaderPrefs.ttsVoiceId`——把兩者串接起來（面板預設套用全域偏好、面板內切換是否要回寫全域偏好）留給下一個涉及 TTS 播放端全域偏好串接的 Epic，避免本 Epic 範圍無限擴大。
- **睡眠定時器的倒數即時顯示（例如每秒更新的 `29:58` 倒數文字）**：本 Epic 只顯示「已設定的時長」（如「睡眠 30 分」），不做逐秒刷新的倒數畫面——E-Ink 裝置不利於高頻率畫面刷新，逐秒倒數也不是 prototype 或 `DESIGN.md` 明確要求的行為。

## 已解決的規格矛盾（新增，Architecting 階段查證後裁定）

1. **⌕ 搜尋按鈕本 Epic 全格式一律假按鈕**——不分 PDF（雖已有底層能力）或 Foliate（完全無底層能力），一律只彈提示，不接真實搜尋邏輯（人類確認）。
2. **頂部 `ReaderChromeTopBar` 不受 `_chromeVisible` 影響、永遠顯示**——查證 `prototype/eink_redesign_prototype.html:909-926`（`renderReaderChrome()`／`toggleReaderChrome()` 原始碼與其註解「isChromeVisible 決定目前這組要不要顯示⋯兩畫面共用語彙但各自收合各自的」）確認：`isChromeVisible` 只切換 `#reader-normal-chrome`／`#reader-tts-chrome` 兩個底部區塊的 `hidden` class，prototype 的頂部 56dp Chrome Bar（`h-[56px] border-b-2` 那個 `<div>`）沒有任何 `id`，从未被任何函式收合過。這與 design.md L60「只留頂列＋內文」的既有文字描述一致，本 spec 據此把 `_chromeVisible` 的作用範圍明確收斂為「只控制底部」，屬於把 design.md 已隱含但未明講清楚的行為，落地為明確規格，非新的產品決策。
3. **`showHeader`／`showFooter` 全域偏好與本次 Chrome Bar 重構完全脫鉤**——`reader_screen.dart:2473-2509` 既有「`_chromeVisible == false` 時仍常駐顯示頁首/頁尾文字」邏輯維持原樣不動；`DESIGN.md` §12.1 原文「⬓ 按鈕同時讀寫 §17.1 顯示頁首／頁尾設定，兩者共用同一份狀態」的說法，經比對 `CONTEXT.md`「沉浸模式」既有詞條與 design.md 已裁定文字後判斷為 `DESIGN.md` 撰寫時的過度精簡表述，本 Epic 不採用——⬓ 只切換 `_chromeVisible`（本次新收斂為「底部區塊」語意），不讀寫 `showHeader`/`showFooter` 這組獨立的持久化偏好。`DESIGN.md` §12.1 該句文字待後續文件同步階段一併修正。

## Further Notes

- **`TtsMiniPlayer` 完整淘汰**：`app/lib/screens/tts_mini_player.dart`／`app/test/screens/tts_mini_player_test.dart` 整份刪除，不保留相容包裝——`TtsPanel` 是完全的替代品，沒有任何既有呼叫端會在本 Epic 之後繼續依賴舊元件。
- **`_buildAppBarActions()`／`Scaffold.appBar` 死碼清除的驗證方式**：Issue 規劃階段應先確認目前 `flutter analyze`／既有測試套件中沒有任何測試直接建構帶有非 `null` `appBar` 的情境（例如刻意繞過 `_buildBody` 直接測 `AppBar` 相關 Key），避免刪除時遺漏隱藏的呼叫端；若查無此類測試（依 Problem Statement 的既有原始碼交叉比對，預期查無），刪除後 `flutter analyze` 應為「No issues found!」（`_buildAppBarTitle`／`_buildAppBarActions` 若仍被任何殘留程式碼引用會直接編譯失敗，是最直接的刪除完整性檢查）。
- **`ReaderChromeTopBar`／`ReaderChromeBottomBar` 命名不採用 `DESIGN.md` 提及的 `ReaderScaffold`**：`DESIGN.md` §12 開頭寫「閱讀器畫面重構為統一的 `ReaderScaffold`」，但 `CLAUDE.md` 已有明文架構限制「僅 Chrome 層合併，`PdfReaderView`／`FoliateReaderView` 底層渲染不合併」，`ReaderScreen` 本身（承載兩條渲染路徑分派邏輯的最外層 widget）不需要、也不應該重新命名或重構為另一個「Scaffold」概念——本 Epic 只新增 Chrome 相關子元件，`ReaderScreen` 類別本身維持原名與既有職責，`DESIGN.md` §12 該句文字待後續文件同步階段訂正為「新增 `ReaderChromeTopBar`／`ReaderChromeBottomBar` 取代兩套按鈕塔」，不是整個畫面重構為新類別。
- **Issue 切法建議**（供 Scrum Master 階段參考，非強制）：功能①②因為共用同一個 `_chromeVisible` 狀態欄位與 `ReaderChromeTopBar` 元件，建議合併為同一個 Issue（「Chrome Bar 統一＋沉浸模式雙觸發」）；功能③④因為都圍繞 `TtsPanel`／`TtsController.stop()`，也建議合併為同一個 Issue（「TTS 常駐面板重構＋睡眠定時器」）——與 design.md「下一步」原先設想的 3 個切片相比收斂為 2 個，因為 design.md 原先「睡眠定時器」單獨切分的理由（新功能、無既有程式碼相依）在確定要復用 `TtsPanel` 同一個 widget、同一次 `AnimatedBuilder` 重繪後，拆開反而會造成兩個 Issue 互相修改同一個檔案的既有段落，不利於獨立審查與合併。
