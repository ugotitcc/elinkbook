# Epic 7 — 互動控制：工單清單 (Issues)

依 `spec.md`（搭配 `design.md`、ADR 0009／0010、`tmp/epic-7/reviews/review-design.md`／`review-spec.md` 審查修正）拆解出的細粒度垂直切片工單。Issue 1（Spike）與 Issue 2（資料層）可立即平行開始；Issue 3、4 依賴 Issue 2；Issue 5、6、7 依賴 Issue 4（6 另依賴 Issue 1）；Issue 8 為收尾工單，依賴 Issue 3-7 全部完成。

---

## Issue 1：Spike——Readium `InputListener.onTap()` 可行性驗證與收斂關卡

**Status:** ✅ 已完成。依 `plans/plan-issue-1.md` Task 1-3 完成真機驗證，結論寫入 `reviews/spike-epub-inputlistener.md`：Q1 確認 `EpubNavigatorFragment` 對純點擊無內建翻頁反應，不需要停用步驟；Q2 確認 `InputListener.onTap()` 攔截可靠，`onTap` 呼叫次數與點擊次數嚴格 1:1（logcat 實測 6 次點擊對應 6 次呼叫，無重複觸發，反轉方向測試設計成功排除防抖鎖假陽性風險）；Q3 確認 `TapEvent.point` 為 `publicationView`（與 `fragmentView` 尺寸相同、無 letterbox）本地座標，`NavZoneHitTester.cellIndex()` 不需額外轉換公式。三項結論皆與 `spec.md` 原假設一致，已於 `spec.md`「待驗證風險與收斂關卡」段落補上驗證結果摘要，**Issue 6 可依 `spec.md` 既有規劃直接採用 `InputListener` 路線，不需退回自行實作**。驗證過程另發現附帶事實：測試裝置（TCL 9491G 客製化 ROM）系統層會過濾 `Log.d`（Debug 等級）的 `logcat` 輸出，已記錄進報告供未來同裝置除錯參考。Task 2 暫時性 Kotlin 插樁已於驗證後 `git checkout --` 完整還原，`flutter analyze`／`flutter build apk --debug` 皆確認乾淨。已於 branch `worktree-epic7-issue1`（4 個 commit）完成，經 PR #55 合併回 `main`。

**依賴：** 無（起始工單，可與 Issue 2 平行）

**描述：**
`spec.md`「待驗證風險與收斂關卡」明訂本項驗證**必須在進入 Issue 6（EPUB 流式熱區實作）前完成**，不得留待實作階段才發現。`InputListener`/`VisualNavigator`/`SelectableNavigator`/`DecorableNavigator` 全專案目前完全未使用，屬全新技術。本 issue 是一次性研究/驗證工作，非長期功能程式碼：

- 以最小可行方式（可用既有專案的暫時性分支、或 `prototype` skill 建立獨立驗證用 EPUB 開啟流程）在真機上驗證以下 3 個問題：
  1. Readium `EpubNavigatorFragment` 是否已有內建的單擊翻頁手勢，需要先透過 `EpubPreferences` 顯式停用，才能讓 `InputListener.onTap()` 生效
  2. `InputListener.onTap()` 回呼中呼叫 `navigator.goForward()`/`goBackward()` 是否真的能正確換頁、是否會與 Readium 自身可能存在的手勢處理重複觸發（例如同一次點擊換兩頁）
  3. `InputListener.onTap(point: PointF)` 回傳的座標系統——是相對整個 `EpubNavigatorFragment` view，還是相對可視內容區域（可能因 letterbox 或縮放置中偏移而不同）
- 每項驗證需附具體證據（真機截圖、log、或量測數值），不接受「應該可行」的主觀判斷
- 若任一項驗證結果與 `spec.md` 假設不符，需在對應段落（`EpubReaderView.kt` 模組段落／待驗證風險與收斂關卡）記錄退回方案的具體實作路線，供 Issue 6 依循；若座標系統與假設不同，需記錄 `NavZoneHitTester.cellIndex()` 所需的額外座標轉換前處理方式

**單元測試要求：** 無（研究/驗證性質，比照 `epic-16-dual-page` Issue 1 先例；驗證過程中若產生暫時性程式碼或素材，驗證後需清理，不留在版本控制中）

**驗收標準：**
- 上述 3 項問題皆有明確結論與證據，寫入驗證報告（建議路徑：`docs/epics/epic-7-interaction/reviews/spike-epub-inputlistener.md`）
- 若任一項驗證失敗或與假設不符，`spec.md` 對應段落已更新為退回方案／座標轉換說明
- 過程中的暫時性程式碼/素材已清理，`git status` 乾淨

---

## Issue 2：資料層基礎建設——熱區設定資料模型與全域持久化

**Status:** ✅ 已完成。依 `plans/plan-issue-2.md` Task 1-5 完成實作：新增 `ZoneAction`／`NavZoneMode` 列舉與 `resolveZoneActions()`/`hitTestZoneIndex()`/`isValidCustomZoneConfig()` 三個純函式，`GlobalReaderPrefs`／`ResolvedPreferences` 依規劃擴充並接上 `ReaderPrefsManagerImpl` 讀寫。程式碼審查（`reviews/review-issue-2.md`，對照分支 `feat/epic-7-zone-data-model`）結論 Ready to merge: Yes，無 Critical/Important 問題。**分支合併狀況特殊記錄**：實作期間另一個並行 session 已直接在 `main` 上完成同一份 Task 1-5（commit `0787a45`/`d825440`/`619a832`/`cfc1002`/`ceada33`），因此 PR #56（`feat/epic-7-zone-data-model` → `main`）與 `main` 現況逐檔比對後內容完全一致（`git merge-tree` 驗證零衝突、`git diff --stat` 除 Issue 1 相關文件外零差異），PR #56 判定為空合併後由人類直接關閉（未合併），Task 1-5 的實際交付已存在於 `main`。`plan-issue-2.md` Task 6（全域驗證）已在 `main` 上重新執行確認：`flutter analyze` 乾淨、`flutter test`（全專案）511 個測試全數通過。

**依賴：** 無（起始工單，可與 Issue 1 平行）

**描述：**
建立本 epic 全部後續 issue 共用的資料模型、純函式與持久化機制，純 Dart、不涉及原生程式碼、不需要真實裝置：

- 新增列舉型別：`NavZoneMode`（`app/lib/reader/nav_zone_mode.dart`，`leftFlip`/`rightFlip`/`oneHand`/`custom` 四值）、`ZoneAction`（`app/lib/reader/zone_action.dart`，`previousPage`/`nextPage`/`menu`/`none` 四值）
- `resolveZoneActions(NavZoneMode mode, List<ZoneAction> customActions)` 純函式：3 個固定模板依 `spec.md` 常數表查表回傳 9 格陣列，`custom` 直接回傳 `customActions` 原樣
- `hitTestZoneIndex({required double dx, required double dy, required double width, required double height})` 純函式（`app/lib/reader/zone_hit_test.dart`）：座標轉 0-8 格子索引，演算法見 `spec.md`「介面」節
- `isValidCustomZoneConfig(List<ZoneAction> actions)` 純函式：`actions.length == 9 && actions.contains(ZoneAction.menu)`
- `GlobalReaderPrefs`（`app/lib/reader/global_reader_prefs.dart`）新增 3 個 non-nullable 欄位：`navZoneMode`（預設 `rightFlip`）、`navZoneCustomActions`（長度固定 9）、`showNavZoneDebugOverlay`（預設 `false`）；`copyWith`/`==`/`hashCode` 依既有模式平行擴充
- `ReaderPrefsManagerImpl`：`_loadGlobalPrefs()`/`saveGlobalPrefs()` 新增上述 3 欄位的 `SharedPreferences` 讀寫（鍵名見 `spec.md`「資料模型」）；`navZoneCustomActions` 缺席或解析失敗時回退為 `rightFlip` 模板的 9 格陣列（**不可回退全 `none`**，會違反自訂模式「至少 1 格 menu」的驗證規則，審查修正）
- `ResolvedPreferences` 新增 `navZoneActions: List<ZoneAction>`（non-nullable，長度固定 9）與 `showNavZoneDebugOverlay: bool`（non-nullable）；`ReaderPrefsManagerImpl.resolve()` 內呼叫 `resolveZoneActions()` 算出寫入

**單元測試要求：**
- `hitTestZoneIndex()`：邊界值測試（格線正上方座標、畫面四角、正中心），確認回傳 0-8 且 `clamp` 不因浮點誤差在邊界產生 index 9 或負數
- `resolveZoneActions()`：3 個固定模板回傳的 9 格陣列與 `spec.md` 常數表逐格比對；`custom` 回傳傳入陣列原樣
- `isValidCustomZoneConfig()`：全部非 `menu` → `false`；恰好 1 格 `menu` → `true`；多格 `menu` → `true`；長度不為 9 → `false`
- `GlobalReaderPrefs` 新欄位的 `copyWith`/`==`/`hashCode`
- `ReaderPrefsManagerImpl._loadGlobalPrefs()`/`saveGlobalPrefs()`：新 3 欄位讀寫往返（round-trip），比照既有 `pageTurnMode` 測試模式；`navZoneCustomActions` 逗號分隔字串序列化/反序列化含邊界情況（空字串、缺鍵時回退 `rightFlip` 模板）
- `ResolvedPreferences`/`resolve()`：`navZoneActions` 正確依 `navZoneMode` 算出

**驗收標準：**
- 上述測試皆通過
- `flutter analyze` 乾淨
- 本 issue 完全不需要真實裝置即可驗收

---

## Issue 3：導航熱區設定畫面

**Status:** ✅ 已完成。依 `plans/plan-issue-3.md` Task 1-4 完成實作：`ReaderPrefsManager` 新增 `loadGlobalPrefs()`（不依附書籍 ID 的全域偏好讀取入口，`load(bookId)` 內部改呼叫同一份實作）；新增 `NavZoneSettingsScreen`（四選一熱區模板即時全域生效、自訂模式 9 格編輯器逐格循環切換、儲存前 `isValidCustomZoneConfig()` 驗證擋下無效設定、熱區輔助線開關）；`SettingsScreen` 新增「導航熱區」入口、`LibraryScreen` 呼叫點同步更新。程式碼審查（`tmp/epic-7/reviews/review-issue-3.md`，對照分支 `epic-7/issue-3-nav-zone-settings`）結論 Ready to merge: Yes，無 Critical/Important 問題；審查後依 Minor 建議將 `RadioListTile` 的 `groupValue`/`onChanged` 改用 `RadioGroup` 祖先 widget，移除 deprecated API 抑制註解（commit `5fa3f5b`）。已透過 PR #57 合併回 `main`，`main` 上重新驗證：`flutter analyze` 乾淨、`flutter test`（全專案）520 個測試全數通過。

**依賴：** Issue 2

**描述：**
建立使用者可見的熱區設定入口，讀寫對象為 `GlobalReaderPrefs`（不經過 `ResolvedPreferences`——該型別只服務 `ReaderScreen` 渲染需求）：

- `SettingsScreen`（`app/lib/screens/settings_screen.dart`）新增「導航熱區」`ListTile`，導向新畫面 `NavZoneSettingsScreen`
- `NavZoneSettingsScreen`（新增）：四選一模板 `RadioListTile`（左翻頁／右翻頁／單手／自訂）；選到「自訂」時顯示 9 格自由編輯器（3×3 排列，每格點擊循環切換 4 種 `ZoneAction`，或彈出選單挑選）；獨立的「顯示熱區輔助線」`SwitchListTile`
- 儲存自訂設定前呼叫 `isValidCustomZoneConfig()`（Issue 2），未通過（9 格皆非 `menu`）則擋下儲存、顯示錯誤提示（design.md 決策 #7，收斂沉浸模式死鎖風險）

**單元測試要求：**
- `NavZoneSettingsScreen` widget test：四選一模板切換觸發對應 `GlobalReaderPrefs` 更新；選到「自訂」後 9 格編輯器逐格點擊循環切換 4 種動作；儲存時全部非 `menu` 會被擋下（斷言錯誤提示存在、儲存回呼未被觸發）；「顯示熱區輔助線」開關觸發更新
- `SettingsScreen` widget test：「導航熱區」項目存在、點擊可導航至 `NavZoneSettingsScreen`

**驗收標準：**
- 上述測試皆通過
- `flutter analyze` 乾淨
- 本 issue 完全不需要真實裝置即可驗收

---

## Issue 4：PDF 熱區導覽 + 沉浸模式基礎建設

**Status:** ✅ 已完成（Task 4 人工驗證清單待補，見下）。依 `plans/plan-issue-4.md` Task 1-5 完成實作：`ReaderScreen` 既有 `_fixedLayoutControlsVisible` 改名擴大為格式無關的 `_chromeVisible`，新增統一熱區動作分派入口 `_handleZoneAction()` 與強型別 `ReaderScreen.triggerZoneAction()` static helper（供 Issue 5/6/7 複用）；Scaffold 開啟 `extendBodyBehindAppBar: true` 並改造 `_buildBody()` 改用 `MediaQuery.viewPadding.top`，避免沉浸模式切換觸發 `PlatformView` resize；`PdfReaderView` 新增 3×3 導航熱區點擊判讀，移除既有橫向滑動翻頁手勢（ADR 0010）。

**實作階段重大技術發現：** `GestureDetector.onTapUp` 包住 `AndroidView` 時實際上永遠不會觸發——`AndroidView` 內建的被動 `_PlatformViewGestureRecognizer` 依 Flutter 手勢競技場「先加入者勝出」的預設仲裁規則，一定贏過外層 `GestureDetector` 的 `TapGestureRecognizer`（已對照 Flutter SDK 原始碼 `platform_view.dart`/`arena.dart` 驗證屬實，非本專案 bug，也推翻了 `spec.md` 第 34 行「PDF 原生層無觸控監聽、沒有搶手勢競技場對象」的假設——原生層是否有監聽與 `AndroidView` 是否贏得競技場無關）。熱區點擊改由既有 `Listener`（`_handleAnnotationPointerDown`/`_handleAnnotationPointerUp`）手動座標比對判讀，以 `kTouchSlop`／`_longPressActive` 正確區分點擊與既有長按拖曳劃線手勢，不新建第二個 `GestureDetector`、不影響 `AndroidView` 觸控可見度（與 EPUB FXL 熱區疊加層「整個蓋住 AndroidView」的取捨不同）。

**審查與修正：** 5 個 Task 分別經過 spec compliance + code quality 審查（Task 2 因上述發現偏離 brief 逐字碼，經 1 輪修正——補上長按/點擊邊界的回歸測試、修正一處與新機制矛盾的舊註解——後通過）；全分支最終審查（Opus）結論 Ready to merge: With fixes，0 Critical、3 Important（皆源自計畫書本身逐字內容，非實作者自行加料，經人裁示後修正）：(1) 除錯用「熱區輔助線」`GridView.count` 預設方形格子在直式手機上跑版（功能判讀 `hitTestZoneIndex()` 不受影響）→ 改為 `Column`/`Row` of `Expanded` 依實際比例排版；(2) `extendBodyBehindAppBar` 只解決 AppBar 造成的 resize，頁尾（in-flow）顯示/隱藏切換仍會造成 `body` resize，與計畫書聲稱「完全防範 Issue 6 WebView 重新分頁」不完全相符 → 修正程式碼註解用語，明確記錄為 Issue 6 開工前需處理的已知限制，未強行改造頁尾版面結構；(3) 保留的 `onTapUp`/`_handleZoneTap` 死碼有潛在雙重派發風險 → 加上一行防禦性交叉引用註解。已透過 PR #58 合併回 `main`，`main` 上重新驗證：`flutter analyze` 乾淨、`flutter test`（全專案）528 個測試全數通過。

**待辦（未阻擋合併，比照 `epic-6-annotations` 既有先例）：** Task 4 Step 4 人工驗證清單尚未執行，需要人類實機操作：依序點擊 9 宮格各格對應動作是否正確、開啟熱區輔助線視覺確認格線與標籤、熱區點擊與長按拖曳劃線交叉操作不誤觸發、裝置旋轉後熱區位置正確對應。已完整記錄於 `app/integration_test/pdf_nav_zone_test.dart` 檔案開頭註解；驗證結果待補記於本節。

**待辦（人類文件修正，非本 issue 程式碼範圍）：** `docs/epics/epic-7-interaction/spec.md` 第 34 行「PDF 原生層無觸控監聽、沒有搶手勢競技場對象」的敘述已證實不成立，建議修正。

**依賴：** Issue 2

**描述：**
本 issue 建立 `ReaderScreen` 統一的沉浸模式與熱區動作分派機制（供 Issue 5、6、7 後續複用），並以 PDF 作為第一個落地畫面（PDF 無原生變更需求，是本 epic 風險最低、最適合打頭陣建立共用基礎設施的畫面）：

- **`ReaderScreen`**：
  - 既有 FXL 專屬 `_fixedLayoutControlsVisible` 欄位改名／擴大為格式無關的 `_chromeVisible`（`bool`，初始值 `true`）：AppBar 判斷式改為 `(_isFixedLayout || !_chromeVisible) ? null : AppBar(...)`；`ReaderFooter` 顯示條件疊加 `&& _chromeVisible`；FXL 既有 4 個懸浮按鈕的判斷改讀 `_chromeVisible`（本 issue 先完成改名與判斷式遷移，FXL 熱區本身的疊加層擴充留給 Issue 5）
  - 新增單一分派入口 `void _handleZoneAction(ZoneAction action)`：`previousPage`/`nextPage` 呼叫既有換頁方法；`menu` 執行 `setState(() => _chromeVisible = !_chromeVisible)`；`none` 不做事
- **`PdfReaderView.dart`**：
  - 移除既有 `onHorizontalDragEnd` 滑動翻頁 handler 整段（ADR 0010）
  - 新增 `Positioned.fill` 的 3×3 `GestureDetector` 疊加層，每格 `key: Key('nav_zone_$index')`，**只註冊 `onTap`，不註冊任何 drag recognizer**（審查修正——PDF 原生層無任何觸控監聽，不需要搶手勢競技場；與既有長按拖曳框選 `onLongPressStart`/`onLongPressMoveUpdate`/`onLongPressEnd`，`epic-6-annotations` Issue 3，共存於同一個 `GestureDetector`）
  - `onTap` 呼叫 `hitTestZoneIndex()` 換算格子後查 `navZoneActions[index]`（透過 `ReaderScreen` 傳入的 `ResolvedPreferences.navZoneActions`）並呼叫 `_handleZoneAction`
  - `showNavZoneDebugOverlay == true` 時，同一層額外疊加 9 個格子的邊框與動作文字標籤

**單元測試要求：**
- `ReaderScreen` widget test：透過直接呼叫 `_handleZoneAction`（或新增測試可呼叫的入口，比照既有 `PdfReaderView.jumpToPage` 強型別 static helper 模式）驗證 AppBar／`ReaderFooter` 依 `_chromeVisible` 正確顯示/隱藏；驗證呼叫 `_handleZoneAction(ZoneAction.previousPage/nextPage)` 後 `_chromeVisible` 不變（design.md 決策 #14）
- `PdfReaderView` widget test：驗證 9 個 `Key('nav_zone_$index')` widget 存在且可點擊，點擊後觸發對應動作；驗證 `onHorizontalDragEnd` 已移除（既有滑動翻頁測試需同步刪除或改寫）

**驗收標準：**
- 上述測試皆通過
- `flutter analyze` 乾淨
- `integration_test`（真實裝置）：PDF 開書後點擊 9 格熱區正確換頁/切換沉浸模式；與既有長按拖曳劃線手勢（`epic-6-annotations` Issue 3 既有 `integration_test`）交叉操作驗證不誤觸發（ADR 0008 已標記的未收斂風險，本 issue 須收斂）

---

## Issue 5：EPUB FXL 熱區導覽

**Status:** ✅ 已完成。依 `plans/plan-issue-5.md` Task 1-4 完成實作：`EpubReaderView` 既有 FXL 三欄暫代版熱區（`epic-16-dual-page` Issue 9）擴充為 3×3 九宮格，移除 `onToggleFixedLayoutControls`／`onFixedLayoutPageTurn` 舊回呼，改為與 `PdfReaderView`（Issue 4）對稱的 `navZoneActions`／`onZoneAction`／`showNavZoneDebugOverlay` 三個建構參數，新增 `static nextPage`/`previousPage` 強型別 helper；`ReaderScreen._handleZoneAction` 新增 EPUB 分支（`previousPage`/`nextPage` 不再影響沉浸模式，design.md 決策 #14 刻意的行為變更，與 `epic-16-dual-page` Issue 9 舊行為不同）。

**架構重點：** FXL 的九宮格熱區疊加層是 `Stack` 中與 `AndroidView` 同層級的兄弟節點（不像 `PdfReaderView` 把 `GestureDetector` 包在 `AndroidView` 外層），不會遇到 Issue 4 在 PDF 上發現的「`GestureDetector.onTapUp` 包住 `AndroidView` 永遠不會觸發」問題，`tester.tap()` 手勢模擬在真機 `integration_test` 上可靠——沿用 `epic-16-dual-page` Issue 9 既有已驗證多年的模式，不需要比照 PDF Issue 4 改用 `triggerZoneAction` 靜態 helper 繞開手勢模擬。

**審查與修正：** 程式碼審查（`tmp/epic-7/reviews/review-issue-5.md`）結論 Ready to merge: With fixes，0 Critical、2 Important（皆已修正）、3 Minor（文件品質，未修正）：(1) 補上缺少的 `ReaderScreen` 端到端真實點擊測試（比照既有 PDF 對稱測試），驗證 `_buildNativeView()` 的 `navZoneActions`/`onZoneAction` 接線正確——修正過程中發現既有測試慣用的 `view.onLayoutResolved?.call(...)` 只會更新 `ReaderScreen` 自己的狀態副本、不會驅動 `EpubReaderView` 內部真正的熱區疊加層存在與否，改為透過 per-instance platform-view channel 送出真實 `MethodCall` 模擬，並補上 mock handler 的 teardown（否則會洩漏污染後續測試，導致 9 個無關測試因 `'meta != null'` assertion 失敗）；(2) `integration_test` 補上真實換頁驗證（呼叫 `EpubReaderView.previousPage`/`nextPage`、比對 `locatorJson` 前後變動）與 `ZoneAction.none` 格觸控攔截驗證（design.md 決策 #17）。審查過程中另發現 `main` 本機曾有 2 個未經審查、疑似 worktree 混淆導致的直接提交（與本分支內容幾乎逐字重複），經人類確認後已回退並改為透過本分支正常走 PR 流程。

真機（Android 15, API 35）`integration_test` 執行 1/1 PASS：9 格熱區皆存在、換頁真的觸發原生渲染、無動作格正確攔截觸控且不崩潰；`flutter analyze` 乾淨、`flutter test`（全專案）531 個測試全數通過；已透過 PR #59 合併回 `main`。

**依賴：** Issue 2、Issue 4

**描述：**
把 EPUB FXL 現有的暫代版三欄熱區（`epic-16-dual-page` Issue 9）擴充為 9 格，並接上 Issue 4 建立的統一沉浸模式機制：

- **`EpubReaderView.dart`**：既有 FXL 三欄 `Row`+`GestureDetector` 疊加層擴充為 3×3、9 格，每格 `key: Key('nav_zone_$index')`。**沿用既有「`onTap` + no-op `onHorizontalDragStart`/`onVerticalDragStart` 搶手勢競技場」機制**（與 PDF 不同，FXL 底層 Readium WebView 有自己的原生滑動手勢，不搶就會漏接觸控落到 WebView，審查已確認維持此機制）。既有 `onToggleFixedLayoutControls`/`onFixedLayoutPageTurn` 兩個建構參數移除，改為統一透過 `hitTestZoneIndex()` 換算格子、查 `navZoneActions[index]`、呼叫（新增的）`onZoneAction: ValueChanged<ZoneAction>?` 建構參數
- **`ReaderScreen`**：FXL 分支接上 `onZoneAction: _handleZoneAction`（Issue 4 已建立），既有 4 個懸浮按鈕的 `_chromeVisible` 判斷不需再變（Issue 4 已完成遷移）
- `showNavZoneDebugOverlay == true` 時 FXL 疊加層同樣顯示格線與動作標籤

**單元測試要求：**
- `EpubReaderView` widget test：模擬 `onLayoutResolved` 使 `_isFixedLayout` 為 `true` 後，9 個 `Key('nav_zone_$index')` 存在；點擊各格觸發 `onZoneAction` 回呼、傳入正確的 `ZoneAction`
- `ReaderScreen` widget test：FXL 開書後點擊選單格觸發沉浸模式切換；翻頁動作不影響沉浸模式狀態（與 Issue 4 PDF 案例對稱驗證，design.md 決策 #14——確認 FXL 換頁不再強制收起懸浮控制項，此為刻意的行為變更）

**驗收標準：**
- 上述測試皆通過
- `flutter analyze` 乾淨
- `integration_test`（真實裝置，使用真實漫畫 FXL EPUB 素材）：既有 3 欄熱區 `integration_test`（`epic-16-dual-page` Issue 9）擴充/改寫為 9 格版本；「無動作」格維持既有的觸控攔截行為（不穿透到底層 WebView，design.md 決策 #17）；換頁與沉浸模式切換皆正確

---

## Issue 6：EPUB 流式熱區導覽（原生 `InputListener`）

**Status:** ✅ 已完成。依 `plans/plan-issue-6.md` Task 1-6 完成實作：新增純 Kotlin `NavZoneHitTester.cellIndex()`（JVM 測試 10 案，與 Dart 端 `hitTestZoneIndex()` 逐位元一致）；`EpubReaderView.dart` 把既有 `navZoneActions` 欄位首次送到原生端（此前僅供 FXL Dart 端疊加層使用），新增 `onZoneTapped: ValueChanged<int>?` 接收原生端回呼；`EpubReaderView.kt` 新增巢狀 `ZoneAction` 列舉、`buildPreferencesFromMap()` 解析、僅流式（`isFixedLayout == false`）路徑註冊 `InputListener`，依 Issue 1 spike 結論直接採用（不需退回自行實作方案）：`previousPage`/`nextPage` 呼叫 `goBackward()`/`goForward(animated = false)`（捲動模式下依 design.md 決策 #15 略過）、`menu` 觸發 `onZoneTapped({"cellIndex": index})`、`none` 不做事；`ReaderScreen` 接上 `onZoneTapped: (index) => _handleZoneAction(resolved.navZoneActions[index])`，複用既有分派入口。

**真機驗證（Task 5）：** `app/integration_test/epub_stream_nav_zone_test.dart` 在真機（3CEF42ECD491687，Android 15/API 35）執行 2/2 通過，經 3 輪真機除錯收斂：(1) 首輪執行確認生產程式碼（Task 1-4）完全正確——`tester.tapAt()` 對此純原生 `InputListener` 路徑（無 Flutter `GestureDetector` 包裹 `AndroidView`）可靠，未重現 PDF（Issue 4）的手勢競技場問題，不需退回人工 `adb shell input tap` 驗證清單；但發現測試檔本身 2 處斷言錯誤（螢幕正中央點擊實際落在九宮格 index 4 而非誤植的 index 1；locator JSON 嚴格字串相等比對對 Readium 非同步補齊中繼資料過於敏感）；(2) 修正後發現第 3 個問題——捲動模式選單熱區點擊斷言失敗，經控制者複查 `EpubReaderView.kt` dispatch 邏輯確認 `MENU` 分支未受 `scroll` 條件約束（排除生產缺陷），純屬測試等待影格不足，改用 `pumpAndSettle` 後 2/2 通過；(3) 逐工單審查另發現 1 項 Important（測試 1 的換頁斷言用全 JSON 字串不相等判斷、理論上可能被中繼資料雜訊誤判為真的換頁），修正為新增 `_locatorPositionChanged()` 輔助函式改比對 `href`/`progression` 核心欄位，再次真機驗證 2/2 通過。

**全分支最終審查（Opus）：** 結論 Ready to merge: With fixes（實質偏 Yes），0 Critical、1 Important、若干 Minor。Important 已處理：`InputListener.onTap()` 恆回傳 `true`，是否會與既有標記啟用（`epic-6-annotations` 的 `onAnnotationActivated`）或 EPUB 內部連結導覽在流式書籍中雙重觸發，尚未經真機驗證（Issue 1 spike 與本 issue 的 `integration_test` 皆只用無標記/連結的純文字書測試）——已比照 `epub_highlights_notes_test.dart` 既有慣例（該檔案本來就已將「點擊既有標記觸發 `onAnnotationActivated`」列為真機人工驗證項目，非本 issue 新增缺口）記錄為 `epub_stream_nav_zone_test.dart` 檔頭的人工驗證待辦事項，**不阻塞本 issue 合併**，待人類於真機開啟含既有劃線/備註/內部連結的流式 EPUB 驗證後回填結論；若發現雙重觸發，需在 `onTap()` 內先判斷該點是否落在 decoration/連結範圍。Minor 項目：已修正「`positionAfterOpen` 為 null 時斷言恆為真」的假陽性風險（新增 `isNotNull` 前置斷言）；其餘 Minor（`buildPreferencesFromMap()` 副作用範圍略超出函式名、`ReaderScreen` 二次查表冗餘、雙演算法無自動化同步護欄）判定為可接受現狀，未修改。

`flutter analyze` 乾淨、`flutter test`（全專案）534 個測試全數通過（基準 531 + Task 2 新增 2 + Task 4 新增 1）；`./gradlew :app:testDebugUnitTest`（因既有跨磁碟機 Gradle 環境問題改用 `:app:` 範圍限定，主分支同樣存在此問題、與本 issue 無關）`BUILD SUCCESSFUL`，83 個 JVM 測試（8 個測試類別，含新增 `NavZoneHitTesterTest` 10/10）全數通過。

**依賴：** Issue 1、Issue 2、Issue 4

**描述：**
本 epic 技術風險最高的部分——EPUB 流式熱區完全由原生 Kotlin 處理，依 Issue 1 的驗證結論實作：

- **`EpubReaderView.kt`**（僅流式路徑，`isFixedLayout == false`）：
  - `buildPreferencesFromMap()` 新增解析 `navZoneActions`（`List<String>`，9 個 `ZoneAction.name`，一律非 null）
  - 新增純 Kotlin 物件 `NavZoneHitTester`（新檔案 `NavZoneHitTester.kt`，比照 `EpubFxlScaler`/`PdfImageProcessor` 抽離慣例，JVM 可測，無 Android 依賴）：`fun cellIndex(dx: Float, dy: Float, width: Float, height: Float): Int`，演算法與 Dart 端 `hitTestZoneIndex()` 一致（若 Issue 1 發現座標系統需要額外轉換，於此處理）
  - 僅在 `isFixedLayout == false` 時向 `EpubNavigatorFragment` 呼叫 `addInputListener()`；`InputListener.onTap(point)` 回呼內：`NavZoneHitTester.cellIndex()` 換算格子索引 → 查 `navZoneActions[index]` → `previousPage`/`nextPage` 時（若 `pageTurnMode == "scroll"` 則忽略，design.md 決策 #15）呼叫 `navigator.goBackward()`/`goForward(animated = false)`；`menu` 時透過 method channel 觸發 `onZoneTapped(index)` 回呼給 Dart；`none` 不做事、不通知 Dart
  - 若 Issue 1 驗證發現 Readium 原生已有內建點擊翻頁行為，依 Issue 1 記錄的退回方案先行停用
- **`EpubReaderView.dart`**：新增建構參數 `onZoneTapped: ValueChanged<int>?`
- **`ReaderScreen`**：流式分支接上 `onZoneTapped: (index) => _handleZoneAction(_resolved!.navZoneActions[index])`（此路徑收到的 index 恆對應 `menu`，複用同一分派入口）

**單元測試要求：**
- JVM 單元測試：`NavZoneHitTester.cellIndex()` 與 Dart 端 `hitTestZoneIndex()` 相同的邊界值測試案例，確認兩端演算法輸出一致
- `EpubReaderView` widget test：`onZoneTapped` 回呼觸發 `ReaderScreen._handleZoneAction`（可透過 mock method channel 呼叫驗證）
- **已知測試限制**：`InputListener.onTap()` 實際換頁效果無法透過 `flutter test`／JVM 測試驗證，留給 `integration_test`

**驗收標準：**
- 上述測試皆通過
- `flutter analyze` 乾淨
- `integration_test`（真實裝置）：EPUB 流式開書後點擊左/中/右熱區驗證實際換頁與沉浸模式切換；捲動翻頁模式下左右熱區失效、選單格仍可用（design.md 決策 #15）
- 若 Issue 1 驗證結論為「需退回自行實作」，本 issue 的實作與驗收標準需依 Issue 1 記錄的退回方案調整，並在完成後於本工單記錄實際採用的路線

---

## Issue 7：FR-18 音量鍵翻頁

**Status:** ready-for-agent

**依賴：** Issue 4

**描述：**
實作硬體音量鍵翻頁，方向固定、不查詢熱區設定（design.md 決策 #19）：

- **`MainActivity.kt`**：
  - 新增小型執行緒安全計數器 `ReaderViewAttachmentTracker`（新檔案，object 單例）：`fun attach()`/`fun detach()`（內部 `AtomicInteger` 遞增/遞減）、`val isAnyAttached: Boolean get() = count.get() > 0`；`PdfReaderView.kt`/`EpubReaderView.kt` 建構子中呼叫 `attach()`，既有 `override fun dispose()` 內呼叫 `detach()`
  - 新增 `ReaderViewAttachmentTracker.suppressedUntilReattach`（`Boolean`，初始 `false`）：收到 Dart 端 `notifyLeavingReader` 呼叫時設為 `true`；`attach()` 時重設回 `false`
  - 覆寫 `dispatchKeyEvent(event: KeyEvent): Boolean`：`KEYCODE_VOLUME_UP`/`KEYCODE_VOLUME_DOWN`、`ACTION_DOWN`、`isAnyAttached && !suppressedUntilReattach` 時消費事件並透過新建的 `MethodChannel("elinkbook/volume_key")` 呼叫 Dart 端 `onVolumeKey`（`direction: "up" | "down"`）；其餘情況呼叫 `super.dispatchKeyEvent(event)`
- **`ReaderScreen`**：
  - 監聽 `MethodChannel('elinkbook/volume_key')` 的 `onVolumeKey`：`up` → `_handleZoneAction(ZoneAction.previousPage)`、`down` → `_handleZoneAction(ZoneAction.nextPage)`（固定映射，不查詢 `navZoneActions`）。掛載時機：`initState()`／`dispose()`
  - 既有 `PopScope`（目前用於裁切模式攔截返回鍵）新增 `onPopInvokedWithResult` 回呼：pop 動作啟動當下呼叫 `notifyLeavingReader`，主動通知原生端立即停止攔截（審查修正，收斂轉場動畫延遲攔截風險——`dispose()` 只在 300-500ms 退場轉場動畫結束後才觸發，此為額外的即時 override 訊號）

**單元測試要求：**
- JVM 單元測試：`ReaderViewAttachmentTracker` 計數器邏輯（`attach`/`detach` 配對、多次 `attach` 後單次 `detach` 仍為 attached、`suppressedUntilReattach` 於 `attach()` 時重設）
- `ReaderScreen` widget test：模擬 `onVolumeKey('up')`/`onVolumeKey('down')` method call 觸發 `_handleZoneAction` 正確分支；模擬 `PopScope` pop 觸發 `notifyLeavingReader` 呼叫（可透過 mock method channel 驗證呼叫發生）

**驗收標準：**
- 上述測試皆通過
- `flutter analyze` 乾淨
- `integration_test`（真實裝置/模擬器，`adb shell input keyevent` 模擬音量鍵）：`ReaderScreen` 內音量鍵正確翻頁；按下返回鍵觸發 pop 的當下（轉場動畫進行中，PlatformView 尚未 `dispose()`）音量鍵已恢復系統音量調整，而非等轉場動畫結束才恢復

---

## Issue 8：真機驗證與收尾

**Status:** ready-for-agent

**依賴：** Issue 3、4、5、6、7 全部完成

**描述：**
比照 `epic-16-dual-page` Issue 7、`epic-4-pdf-enhance` Issue 7 既有模式，本 issue 為裝置端整合驗證與 Epic 收尾：

- **端到端組合驗證（人工視覺 QA）**：三種模板 + 自訂模式在 EPUB 流式／PDF／EPUB FXL 三種畫面下皆正確生效；切換模板後重開 App，設定正確持久化（全域、不分書籍）
- **手勢競技場交叉驗證**：PDF 熱區點擊與既有長按拖曳劃線（`epic-6-annotations`）、EPUB FXL 熱區點擊與（若有）雙指縮放，交叉操作皆不誤觸發
- **沉浸模式驗證**：三種畫面選單格切換一致；EPUB 流式捲動模式下左右熱區失效、選單格仍可用
- **音量鍵驗證**：三種畫面音量鍵翻頁一致；離開閱讀畫面（含轉場動畫期間）音量鍵正確恢復系統音量
- 彙整驗證紀錄，更新本檔案各 issue 最終驗收狀態，並更新 `docs/epics.md` 狀態列為已歸檔（若人類確認可歸檔）
- 若驗證中發現需要後續處理的落差，比照既有慣例另立後續 issue 追蹤，不阻塞本 epic 合併

**單元測試要求：** 無新增自動化單元測試（本 issue 以整合/裝置驗證為主）

**驗收標準：**
- 端到端組合驗證產出書面紀錄（比照 `qa-issue-N-*.md` 既有慣例）
- `flutter analyze` 乾淨、`flutter test` 全數通過
- 若有發現需要後續處理的落差，已建立對應的後續 issue 追蹤，不阻塞本 epic 合併
