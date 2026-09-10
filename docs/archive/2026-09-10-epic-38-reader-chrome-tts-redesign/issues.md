# Epic 38 — 閱讀器 Chrome／TTS 重構：工單清單 (Issues)

依 `spec.md`（Architecting 階段唯一事實來源，已依 `reviews/review-spec.md` 審查修訂）拆解為 2 個垂直切片工單，對應 `spec.md`「Implementation Decisions」的功能①②（Issue 1）與功能③④（Issue 2）——`spec.md`「Further Notes」已預先裁定此對應關係：①②共用同一個 `_chromeVisible` 狀態欄位與 `ReaderChromeTopBar` 元件，③④共用同一個 `AnimatedBuilder`／`TtsPanel` 切換點，拆開反而會讓兩個 Issue 互改同一段程式碼、不利於獨立審查與合併。每個工單都附有單元測試要求；跟 `spec.md` 對應段落的引用一律用 `spec.md §功能N` 標示，實作者動手前應先讀那一段的完整說明，這裡只列摘要與驗收標準。

**依賴順序：** Issue 1 → Issue 2（Issue 2 沿用 Issue 1 建立的 `ReaderChromeTopBar`／`ReaderChromeBottomBar`，並在 `ReaderChromeTopBar` 新增小喇叭圖示參數）。**Issue 1 刻意不動 TTS 內部**：底部選單列的「◗ 朗讀」按鈕在 Issue 1 完成後仍呼叫既有 `_ttsMiniPlayerVisible` 開關，顯示的仍是舊 `TtsMiniPlayer` 膠囊——只是觸發按鈕本身（原本獨立的 `reader_foliate_tts_toggle_button` `Positioned` FAB）在 Issue 1 就整顆刪除、改由新的統一 `ReaderChromeBottomBar` 選單列承載同一個開關動作，這是刻意的過渡期安排，讓 Issue 1 純粹是「Chrome 層收斂」、不夾帶 TTS 系統置換，Issue 2 才是完整替換 `TtsMiniPlayer` → `TtsPanel`。**過渡期兩者互斥顯示**（`_ttsMiniPlayerVisible == true` 時 `ReaderChromeBottomBar` 不渲染）——舊 `TtsMiniPlayer` 膠囊的定位邏輯（`_ttsMiniPlayerBottomOffset`，僅 12/40dp）是針對「無持久底部列」的畫面設計，若與新的 154dp（34+56+64）`ReaderChromeBottomBar` 同時出現會互相遮擋，Issue 2 完成後這個過渡期互斥條件會被 `TtsPanel` 的正式衍生切換取代。

**共同規則（兩個工單皆適用）：** 動手改程式碼前，先在該工單的 `plans/plan-issue-<N>.md` 說明 (1) 改哪個元件 (2) 為什麼要改 (3) 哪些畫面/格式依賴它 (4) 是否影響既有測試 Key 契約。本 Epic 僅合併 Chrome（按鈕列）這一層，`PdfReaderView`／`FoliateReaderView` 底層渲染路徑不合併，`CLAUDE.md` 已有明文架構限制，不需要在計畫書內重新論證。

---

## Issue 1：ReaderChromeBar 統一＋沉浸模式雙觸發＋死碼清除

**Status:** completed

**依賴：** 無（可立即開始）

**來源：** `spec.md` §功能①②（對應 review-design.md C1／M1／M2 訂正落地，`review-spec.md` C2 訂正落地）

**背景／目標：** `ReaderScreen._buildBody()` 目前是兩套並存的浮動按鈕系統——流式 EPUB 與 FXL 共用一組 7 顆 `Positioned` 圓鈕，PDF 是獨立一組 6 顆，`Scaffold.appBar`／`_buildAppBarActions()` 對所有格式恆為 `null`／死碼。`_chromeVisible` 目前是「全部按鈕一起顯示/隱藏」的單一開關，收起後沒有任何常駐按鈕能再次喚出。本工單新增 `ReaderChromeTopBar`（56dp，永遠顯示）與 `ReaderChromeBottomBar`（受 `_chromeVisible` 控制的三列結構），三格式共用同一份 widget，並把 `_chromeVisible` 的作用範圍收斂為「只控制底部區塊」。

**Solution：**
- 新增 `app/lib/screens/reader_chrome_top_bar.dart`：`ReaderChromeTopBar`（`StatelessWidget`，格式無關）——‹返回／書名＋章節標題／⌕搜尋（固定假按鈕，`onSearchTap` 只彈「功能開發中」提示，PDF／Foliate 皆同，不接任何真實搜尋邏輯）／⬓（`isBottomChromeVisible`＋`onToggleBottomChrome`）／☰目錄（`onTocTap` 為 `null` 時停用）。`showTtsIndicator` 參數本工單先加入介面、固定傳 `false`（小喇叭圖示邏輯屬於 Issue 2）。觸控目標依 `DESIGN.md` §7.2：一般 48dp／`isEinkMode` 56dp。Key：`reader_chrome_back_button`／`reader_chrome_title`／`reader_chrome_search_button`／`reader_chrome_immersive_toggle_button`／`reader_chrome_toc_button`。
- 新增 `app/lib/screens/reader_chrome_bottom_bar.dart`：`ReaderChromeBottomBar`（`StatelessWidget`）——頁碼列（34dp，書名＋頁數/百分比，`key: reader_chrome_page_info_text`）／跳頁列（56dp，直接內嵌既有 `ReaderFooter`，`key: reader_footer` 不變）／選單列（64dp，4 顆：⚑書籤`reader_chrome_bookmark_button`／✎劃線筆記`reader_chrome_annotations_button`／Aa版面`reader_chrome_layout_button`／◗朗讀`reader_chrome_tts_button`，`onTtsTap == null` 時「朗讀」整項不渲染，PDF 目前無 TTS 底層能力比照既有事實不渲染）。
- `reader_screen.dart` 異動：
  - 刪除 `Scaffold.appBar` 整段條件式與 `AppBar(...)` 建構、`_buildAppBarTitle()`、`_buildAppBarActions()`（確認過沒有任何格式組合會讓 `appBar` 非 `null`）。
  - 刪除三格式各自獨立的頂部 `Positioned`（返回/目錄）與底部功能按鈕群——**PDF 4 顆**（版面/書籤/筆記/進度-跳頁）、**Foliate 5 顆**（版面/書籤/筆記/進度-跳頁**＋ `reader_foliate_tts_toggle_button`**，`reader_screen.dart:2277-2296`，這顆連同它下面緊接著的 `TtsMiniPlayer` 膠囊渲染區塊〔`:2298-2351`〕一併考量——**膠囊渲染區塊本身這個 Issue 不動，只刪觸發它的獨立 FAB**），改為插入單一 `ReaderChromeTopBar`（`Stack` 最上層、一律渲染，不受 `_chromeVisible` 影響）＋ `if (_chromeVisible && !_ttsMiniPlayerVisible) ReaderChromeBottomBar(...)`（依格式分派各 `onXxxTap` 到既有方法：`_toggleBookmark`／`_togglePdfBookmark`／`_openLayoutSettings`／`_openFxlSettings`／`_openPdfSettings`／`_openNotesSheet`／`_openToc`／`_openPdfToc`，行為不變，只是呼叫路徑改變；**`onTtsTap: widget.ttsProvider == null ? null : () => setState(() => _ttsMiniPlayerVisible = !_ttsMiniPlayerVisible)`**——過渡期版本，Issue 2 會改成呼叫 `_ttsControllerOrNull!.play()`）。**`!_ttsMiniPlayerVisible` 這個互斥條件是本 Issue 修正「新舊底部列視覺重疊」的關鍵**：舊 `TtsMiniPlayer` 膠囊固定貼在螢幕底部 12/40dp 處，新 `ReaderChromeBottomBar` 三列合計 154dp 高、同樣貼底，兩者同時渲染會互相遮擋、觸控混亂，過渡期間二擇一顯示可避免這個問題。
  - 新增 `String _currentChapterTitle(BookFormat format)`：複用 `_buildAppBarTitle()` 刪除前的既有邏輯（`TocNavigator.findCurrentPath`／`PdfTocNavigator.findCurrentPath` + 回退「閱讀器」文字），**不再受 `_resolved.showHeader` 偏好門檻限制**，一律顯示。`showHeader`／`showFooter` 偏好維持原本語意完全不動（只控制 `_chromeVisible == false` 時螢幕邊角的常駐頁首/頁尾文字，`reader_screen.dart:2473-2509` 不動）。
  - `ReaderChromeTopBar.onToggleBottomChrome` 與熱區 `ZoneAction.menu`（`reader_screen.dart:3071-3072`）呼叫同一行 `setState(() => _chromeVisible = !_chromeVisible)`，兩種觸發方式切換同一狀態。
  - `NotesBottomSheet` 新增 `initialTabIndex`（預設 0）建構參數，`_openNotesSheet` 被 `reader_chrome_annotations_button` 呼叫時傳 `initialTabIndex: 1`（預設停在「劃線與備註」分頁），既有呼叫端（若有）不傳則維持分頁 0。**實作提示**：`notes_bottom_sheet.dart:102` 的 `TabController(length: 2, vsync: this)` 直接改成 `TabController(length: 2, vsync: this, initialIndex: widget.initialTabIndex)` 一行即可，`TabController` 建構子原生支援 `initialIndex`，不需要用 `_tabController.animateTo()` 這類額外的非同步切換寫法。

**單元測試要求：**
- `ReaderChromeTopBar` 獨立 widget test：五個按鈕點擊觸發對應 callback；`onTocTap == null` 時目錄按鈕為停用狀態；`isEinkMode: true` 時用 `tester.getSize(find.byKey(...))` 驗證觸控目標實際渲染尺寸為 56dp（不只驗證建構參數傳遞，比照 `reader_screen.dart:1965-1974` 既有記錄的 Material 3 `padding`/`constraints` 陷阱）。
- `ReaderChromeBottomBar` 獨立 widget test：`onTtsTap == null` 時「朗讀」項目整個不存在於 widget 樹（`findsNothing`）；正確傳遞 `currentPage`/`totalPages`/`onPageChanged` 給內嵌 `ReaderFooter`，不重複測試 `ReaderFooter` 本身邏輯。
- `ReaderScreen` 整合層核心回歸測試：驗證 `_chromeVisible` 切換只影響底部區塊、`ReaderChromeTopBar` 全程可見（`find.byType(ReaderChromeTopBar)` 恆為 `findsOneWidget`，`_chromeVisible == false` 時 `find.byType(ReaderChromeBottomBar)` 為 `findsNothing`）——這是與既有 `_chromeVisible` 舊語意（全部一起收合）不同的新行為，須明確斷言。
- **過渡期互斥回歸測試**：點擊 `reader_chrome_tts_button` 開啟舊 `TtsMiniPlayer`（`_ttsMiniPlayerVisible == true`）後，`find.byType(ReaderChromeBottomBar)` 須為 `findsNothing`（兩者不得同時出現在畫面上）；再次點擊關閉後 `ReaderChromeBottomBar` 恢復顯示。
- `NotesBottomSheet.initialTabIndex`：widget test 驗證傳入 `1` 時初始顯示「劃線與備註」分頁，不傳時維持既有分頁 0 行為。
- 既有 `reader_screen_test.dart` 中依賴舊 `Positioned` Key（各格式的返回/目錄/版面/書籤/筆記/進度按鈕）或 `reader_appbar_chapter_title`／`reader_appbar_static_title` 的斷言，改為斷言新的 `reader_chrome_*` Key；先盤點確認無遺漏呼叫點再刪除舊程式碼。

**驗收標準：** 三格式（流式 EPUB／FXL／PDF）共用同一份 `ReaderChromeTopBar`／`ReaderChromeBottomBar`；`_buildAppBarActions()`／`Scaffold.appBar` 死碼整段清除；⬓ 按鈕與熱區「選單」動作皆能收合/展開底部區塊，頂部列全程可見；舊 `reader_foliate_tts_toggle_button` FAB 已刪除、其開關動作由 `ReaderChromeBottomBar` 的「◗ 朗讀」承接，且與新底部列互斥顯示、不重疊；`flutter analyze` 乾淨、`flutter test test/screens/reader_screen_test.dart` 通過。

---

## Issue 2：`TtsPanel` 重構＋`TtsController.stop()`＋睡眠定時器

**Status:** completed

**依賴：** Issue 1（沿用其 `ReaderChromeBottomBar` 的「朗讀」按鈕位置，並在其 `ReaderChromeTopBar` 補上小喇叭圖示的真實邏輯）

**來源：** `spec.md` §功能③④（對應 `review-design.md` I1／M3 訂正落地，`review-spec.md` C1 訂正落地）

**背景／目標：** 現有 `TtsMiniPlayer` 是飄浮膠囊，功能簡化（無睡眠定時器、無語音顯示），其 `onClose` 只隱藏面板、不停止播放，與 `DESIGN.md` §13.1「點擊關閉必須停止播放並釋放音訊焦點」矛盾。本工單新增 `TtsPanel` 取代它，與 `ReaderChromeBottomBar` 完全互斥（依 `TtsController.status` 衍生切換，不設手動旗標），新增 `TtsController.stop()` 真正停止＋釋放音訊焦點，並新增睡眠定時器。

**Solution：**
- `TtsController.stop()`（`app/lib/reader/tts_controller.dart`，新方法）：`_playGeneration`／`_segmentGeneration` 無條件遞增（比照既有 `handleExternalPositionChange()` 防重入慣例），重設 `status`/`_currentIndex`/`_segments`，呼叫 `player.stop()`，`onHighlightSegment?.call(null)`，`notifyListeners()`。
- `TtsAudioPlayer.stop()`（`app/lib/reader/tts_audio_player.dart`，新抽象方法＋ `JustAudioTtsPlayer` 實作 `_player.stop()`）——`just_audio` 的 `stop()` 相對 `pause()` 會釋放音訊焦點；`test/support/fake_tts_audio_player.dart` 同步新增 `stop()` 假實作。
- 新增 `app/lib/screens/tts_panel.dart`：`TtsPanel`（`StatelessWidget`，取代 `app/lib/screens/tts_mini_player.dart`）——展開控制列（52/56dp，`isCollapsed` 時不渲染：`reader_tts_previous_button`／`reader_tts_play_pause_button`／`reader_tts_next_button`／`reader_tts_speed_button`，沿用既有 Key 字面值；新增 `reader_tts_voice_button`）；底層動作列（恆常渲染：`reader_tts_sleep_timer_button`／`reader_tts_panel_collapse_button`／`reader_tts_stop_button`）。`isCbz: true` 時只渲染停用播放鍵，沿用既有 `TtsMiniPlayer` 降級語意。
- `reader_screen.dart` 異動：
  - `_buildBottomChrome(format)`：`_ttsController == null` 時渲染 `ReaderChromeBottomBar`；非 `null` 時用 `AnimatedBuilder(animation: controller, ...)` 依 `controller.status == idle` 二擇一渲染 `ReaderChromeBottomBar` 或 `TtsPanel`——章節自然播完時自動切回底部列，不需額外程式碼。
  - `bool get _isTtsActive => _ttsController != null && _ttsController!.status != TtsPlaybackStatus.idle;`（讀私有欄位，不觸發 lazy 建構）。
  - **睡眠定時器自動取消機制（審查修正 `review-spec.md` C1，不可在 `AnimatedBuilder.builder` 內呼叫 `setState`）**：`_ttsControllerOrNull` getter 內 `_ttsController = controller;` 之後追加 `controller.addListener(_onTtsStatusChanged);`；新增 `bool _wasTtsActive = false;` 與 `void _onTtsStatusChanged()`（比對 `_isTtsActive` 邊緣、由 `true→false` 時呼叫 `_cancelTtsSleepTimer()`）；`dispose()` 新增 `_ttsController?.removeListener(_onTtsStatusChanged);`（置於既有 `_ttsController?.dispose()` 之前）。
  - 新增 `Timer? _ttsSleepTimer`／`Duration? _ttsSleepTimerDuration`／`_setTtsSleepTimer(Duration?)`／`_cancelTtsSleepTimer()`／`_openSleepTimerPicker()`（`_showThemedModalBottomSheet` 開啟 15/30/45/60 分＋「不限時」固定清單，`key: reader_tts_sleep_timer_option_<N>`／`reader_tts_sleep_timer_option_none`）；`TtsPanel.onStop` 呼叫 `_cancelTtsSleepTimer()` 後才 `await controller.stop()`；`dispose()` 新增 `_ttsSleepTimer?.cancel()`。
  - `ReaderChromeTopBar.showTtsIndicator` 改為 `_isTtsActive && !_chromeVisible`（Issue 1 暫時固定 `false` 的位置，本工單改為真實邏輯）。
  - **移除 Issue 1 的過渡期安排**：`ReaderChromeBottomBar` 的渲染條件從 `_chromeVisible && !_ttsMiniPlayerVisible`（Issue 1 的互斥 hack）改回單純的 `_chromeVisible`，改由功能③既有的 `AnimatedBuilder`／`controller.status` 衍生切換取代（見上方 `_buildBottomChrome`）；刪除 `_ttsMiniPlayerVisible`／`_ttsMiniPlayerBottomOffset` 欄位，以及 `TtsMiniPlayer` 膠囊的 `Positioned` 渲染區塊（`reader_screen.dart:2298-2351`，其觸發 FAB `reader_foliate_tts_toggle_button` 已在 Issue 1 刪除，本工單只需清除膠囊本體與這兩個狀態欄位）；`app/lib/screens/tts_mini_player.dart`／`app/test/screens/tts_mini_player_test.dart` 整份刪除。
  - `ReaderChromeBottomBar.onTtsTap` 從 Issue 1 的過渡期寫法（切換 `_ttsMiniPlayerVisible`）改為：`widget.ttsProvider == null ? null : () => _ttsControllerOrNull!.play()`。

**單元測試要求：**
- `TtsController.stop()`：純 Dart 單元測試（`tts_controller_test.dart`）——`playing`/`paused` 狀態下呼叫後 `status == idle`、`segments`/`currentIndex` 清空、`onHighlightSegment` 收到 `null`、`fake_tts_audio_player.dart` 的 `stop()` 呼叫次數為 1（非 `pause()`）；`stop()` 呼叫期間若有進行中的 `play()` 需驗證世代編號機制正確中止，不會事後又寫回過期資料。
- `TtsPanel` 獨立 widget test（不透過 `ReaderScreen` 間接測）：`isCollapsed`/`isCbz` 各種組合下對應按鈕存在/不存在；`sleepTimerRemaining` 非 `null`/`null` 時按鈕文字正確反映。
- `ReaderScreen` 整合層：觸發播放後（fake `TtsProvider`/`TtsAudioPlayer`）驗證從 `ReaderChromeBottomBar` 切換為 `TtsPanel`；模擬章節自然播完（`completedStream` 觸發到最後一段）後驗證自動切回 `ReaderChromeBottomBar`，且先前設定的睡眠定時器已被取消（用 `_onTtsStatusChanged` listener 機制，不是在 `AnimatedBuilder.builder` 內）。
- `_setTtsSleepTimer`／`_openSleepTimerPicker`：用 `FakeAsync` 驗證——選「30 分」後 label 反映；`elapse(Duration(minutes: 30))` 後 `controller.pause()` 被呼叫且 `_ttsSleepTimerDuration` 歸零；選「不限時」後計時器取消、`elapse()` 不再觸發 `pause()`。
- `showTtsIndicator` 邏輯：widget test 驗證 `_isTtsActive && !_chromeVisible` 同時成立時小喇叭圖示存在，其餘三種組合皆不存在。

**驗收標準：** `TtsPanel` 完全取代 `TtsMiniPlayer`，與 `ReaderChromeBottomBar` 互斥切換且無需手動旗標；「停止朗讀」真正停止播放並釋放音訊焦點；「收合成細列」只隱藏展開列；睡眠定時器到期暫停播放（非停止）且不造成 build 階段崩潰；`flutter analyze` 乾淨、`flutter test test/screens/reader_screen_test.dart test/reader/tts_controller_test.dart` 通過。

---

## 收尾提醒

- 兩個 Issue 皆完成合併後，執行一次完整 `flutter test`（不帶檔案路徑），比照 `CLAUDE.md`「測試執行範圍」規範確認無全域回歸。
- `docs/epics.md` 對應本 Epic 那一列的備註欄位，隨每個 Issue 完成同步更新為「Issue N 已完成」，完整歷程記錄於本 Epic的 `epic.md`。
- `DESIGN.md` §12／§13 對應段落（按鈕配置、底部結構、TTS 面板內容）於 Issue 2 完成後一併訂正，反映 `spec.md`「已解決的規格矛盾（新增）」與「Further Notes」列出的各項文字修正（含 `ReaderScaffold` 命名不採用一事）。
