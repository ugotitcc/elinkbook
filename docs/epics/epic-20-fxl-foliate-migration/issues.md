# Epic 20 — FXL 渲染引擎遷移評估：Issue 追蹤

## Issue 1：Spike——`readest/foliate-js` 的 `fixed-layout.js` 能否正確處理 FXL 漫畫橫向雙頁/RTL/封面獨立顯示

**Status:** ✅ 已完成，**結論 GO**（2026-07-31，真機以真實問題書籍《一弦定音！(11)》驗證，4 項核心判準全數通過，完整證據見 `reviews/spike-issue1-fxl-foliate.md`）。過程中曾有兩輪驗證嘗試因證據與結論矛盾／測試素材誤用而被獨立覆核判定不成立（見報告內「本報告狀態說明」），第三輪由執行者本人直接操作真機、使用真實問題書籍取得最終結論。`epic-18` Issue 20/21 已由本 Issue 取代，不再執行。

**依賴：** 無（起始工單）。

**背景：** 見 `design.md`「問題陳述」。已查證我們現有 vendored `readest/foliate-js`（釘定 commit `dd71f2be356563c16a23272686189fcfb45d0b82`）的 `view.js` 已有偵測 FXL 並動態 `import('./fixed-layout.js')` 的潛伏邏輯，`epub.js` 已在解析 `page-spread-*` metadata，但 `fixed-layout.js` 本身當初（ADR 0011 Phase 1）未被 vendored 進來。人類提供的兩份外部分析報告（Anx Reader／Readest 皆用 foliate-js 處理 FXL 漫畫且效果良好）觸發本次評估。

**驗證範圍：**

1. **主要驗證**：獨立 throwaway Android 測試專案（比照 `epic-17` Issue 1 既有 harness 設計），打包釘定 commit 的 `readest/foliate-js`（額外補上 `fixed-layout.js`），真機開啟已知會被誤判為流式的漫畫 EPUB（RTL、多頁，沿用 `epic-18` Issue 15/17/18/19 一路使用的同一本），裝置橫向、雙頁模式下驗證：
   - 橫向雙頁排版是否正確顯示兩頁並排。
   - 封面是否獨立成頁，第二頁起是否正確兩兩配對（`1,3-2,5-4`）。
   - RTL 頁序是否正確（`[3｜2]`／`[5｜4]`）。
   - 連續翻頁 3 次以上內容是否連續無跳過/重複。
2. **觀察性質（不影響 GO/NO-GO）**：大尺寸漫畫圖片頁的載入效能/記憶體表現；1px 白縫等視覺細節。

**明確不在本 Issue 範圍**：完整遷移架構設計（`EpubReaderView.kt`/Readium FXL 路徑是否退場、既有資料轉換、劃線/備註/書籤對接）——這些留待 GO 之後的 Architecting 階段（`spec.md`）。

**GO/NO-GO 決策路徑：**
- **GO**（判準表 4 項核心項目皆通過，見 `design.md`「Spike 驗證方法與判準」）：記錄結果，進入 Architecting 階段，`epic-18` Issue 20/21 正式標記為「被本 Epic 取代，不再執行」。
- **NO-GO**（任一核心項目失敗，或效能/記憶體有無法接受的明顯問題）：記錄具體失敗證據，本 Epic 結束，`epic-18` Issue 20/21 恢復依原計畫執行。

**單元測試要求：** 無（研究/驗證性質，比照 `epic-17` Issue 1、`epic-18` Issue 8/17/18 先例）。過程中產生的 harness 專案與素材（截圖/log）驗證後需清理，不進版控（放 `tmp/`，已 gitignore）。

**驗收標準：**
- 真機以已知問題漫畫書驗證，明確記錄 GO/NO-GO 判定與依據（截圖或 log 佐證）。
- 依結果更新 `design.md`／`issues.md` 對應狀態，以及 `epic-18` Issue 20/21 的狀態。

**相關佐證：**
- `docs/epics/epic-20-fxl-foliate-migration/design.md`「問題陳述」「Spike 驗證方法與判準」
- `docs/archive/2026-07-24-epic-17-epub-render-migration/plans/plan-issue-1.md`（Spike harness 既有先例，方法論參考）
- `docs/epics/epic-18-reader-device-qa/issues.md` Issue 16-21
- `docs/epics/epic-18-reader-device-qa/reviews/readest_foliate_fxl_spread_analysis.md`／`anx_reader_foliate_fxl_spread_analysis.md`
- `app/android/app/src/main/assets/foliate/view.js:255-257`、`epub.js:1091-1095`

---

## Issue 2：打包 `fixed-layout.js` 至 production assets，`FoliateEpubReaderView` 基本開書渲染 FXL 書籍

**Status:** ✅ 程式碼實作完成（7 個 commits：`9b71c89`、`df6bd60`、`23ed574`、`101ac7e`、`41dc599`、`b826c79`、`13bbe55`）。`flutter test`（全專案）708/708 通過（含程式碼審查 Important #2 補上的 `isFixedLayoutHint` 測試），`flutter analyze` 乾淨。真機驗證已於裝置解鎖後完成，人類（huthief）親自在場全程觀察 FXL 開書/雙頁/翻頁，確認正常運作（詳見 `plans/plan-issue-2.md` Task 5 Step 2——過程存檔的部分截圖經審查發現無法單獨佐證翻頁行為，已如實記錄該落差，最終以人類親自確認結案）。

**已知限制（程式碼審查發現，2026-07-31）：** `FoliateEpubReaderView` 目前沒有任何字元數統計/頁碼進度回報機制（`onCharacterCountReady` 只存在於舊 `EpubReaderView`／Readium widget），導致頁尾 `X/Y` 頁碼顯示對所有透過 `FoliateEpubReaderView` 渲染的 EPUB（不論 FXL 或流式）皆不可用——這不是 Issue 2 新造成的問題（`FoliateEpubReaderView` 自 epic-17 遷移完成以來即是如此），但 Issue 2 的統一分派讓流式書籍第一次也繼承這個既存缺口的可見影響（`reader_screen_test.dart` 已有多處測試斷言「頁尾不顯示」反映此現況）。修復（補上字元數統計機制）待另立工單評估，非本 Epic 既定範圍。

**依賴：** Issue 1（Spike GO）。

**背景：** `spec.md`「核心介面異動」第 2 節。Production `app/android/app/src/main/assets/foliate/` 目前只有 8 個檔案，沒有 `fixed-layout.js`，`main.js` 從未處理過 FXL。本工單只求「能開書、能看到內容」，尚不含雙頁模式（Issue 3）。

**範圍：**
1. 打包釘定 commit `dd71f2be356563c16a23272686189fcfb45d0b82` 的 `fixed-layout.js` 進 `app/android/app/src/main/assets/foliate/`（含 `construct-style-sheets-polyfill` no-op stub 處理，比照 Spike Task 2 Step 1 已驗證作法）。
2. `main.js` 的 `openBook()` 新增 `isFixedLayoutHint` 偏好讀取與覆寫邏輯（`spec.md` 第 2 節：`book.rendition?.layout !== 'pre-paginated'` 時才覆寫，避免影響已正確判斷的書籍）。
3. `foliate_epub_reader_view.dart` 新增 `isFixedLayoutHint` 建構參數，`buildFoliatePreferencesMap()`／`foliatePreferencesChanged()` 同步擴充。
4. `reader_screen.dart`：EPUB 一律建構 `FoliateEpubReaderView`（移除 `if (!_dispatchedIsFixedLayout!) {...} else { return EpubReaderView(...) }` 雙分支），傳入 `isFixedLayoutHint: widget.isFixedLayout`。**本工單暫不移除 `EpubReaderView.kt`／Dart widget 本身**（留給 Issue 5 一次清理，避免本工單範圍混雜「新增」與「刪除」兩種性質）。

**單元測試要求：** `foliate_epub_reader_view_test.dart` 新增 `isFixedLayoutHint` 參數的 `buildFoliatePreferencesMap`／`foliatePreferencesChanged` 測試；`reader_screen_test.dart` 更新既有依 `_dispatchedIsFixedLayout` 分支建構 widget 的測試，改為一律斷言 `FoliateEpubReaderView`。原生渲染需真機驗證（比照既有兩層測試架構）。

**驗收標準：** 真機開啟已知 FXL 漫畫書（強制 FXL／原生判定皆須驗證），確認由 `FoliateEpubReaderView` 正確渲染（單頁，尚無雙頁），`isFixedLayoutHint` 覆蓋機制對「原生判定不出 FXL」的邊界情況生效。

---

## Issue 3：雙頁模式（`dualPageMode`／`isLandscape` 參數 + `main.js` spread 邏輯）

**Status:** ✅ 程式碼實作完成（commit `f0fe2aa`），程式碼審查通過（`tmp/epic-20/issue3-implementation-review.md`，With fixes，2 項 Important 皆為文件數字誤植已修正，程式碼本身無缺陷）。`flutter test`（全專案）730/730 通過，`flutter analyze` 乾淨。真機驗證已於 2026-07-31 由 Claude Code 親自在真機（`3CEF42ECD491687`）以 `tmp/一弦定音.epub` 完成，5 項判準（橫向雙頁／封面獨立顯示／RTL 頁序／直向單頁／開書雙重渲染觀察）皆為 GO，詳見 `plans/plan-issue-3.md` Task 4 Step 3。

**依賴：** Issue 2。

**背景：** `spec.md`「核心介面異動」第 1/2 節。`isDualPageEnabled(dualPageMode, isLandscape)` 邏輯目前是 `EpubReaderView.kt` 的 Kotlin 純函式，需移植成 JS（`main.js`），因為 `FoliateEpubReaderView` 沒有對應的原生 Kotlin 類別（純 WebView + JS）。

**範圍（已完成）：**
1. `main.js`：新增 `isDualPageEnabled(dualPageMode, isLandscape)` 純函式（移植自 `EpubReaderView.kt:149-151`），`applyPreferences()` FXL 分支新增 `setAttribute('spread', ...)` 設定 `'both'`/`'none'`。
2. `foliate_epub_reader_view.dart`：新增 `dualPageMode`（`DualPageMode?`，nullable）與 `isLandscape`（`bool`，非 nullable，預設 `false`）建構參數，`buildFoliatePreferencesMap()` 與 `foliatePreferencesChanged()` 同步擴充。
3. `reader_screen.dart`：`_buildNativeView()` 將 `resolved.dualPageMode` 與 `isLandscape` 下傳至 `FoliateEpubReaderView`。

**單元測試：** 18 項 `foliate_epub_reader_view_test.dart`（含 `isDualPageEnabled` truth table 可執行文件）+ 4 項 `reader_screen_test.dart` 新增測試。

**真機驗證：** APK 已安裝，待人類驗證：橫向雙頁、封面獨立顯示、RTL 頁序、直向/單頁模式四項判準。

---

## Issue 4：`ReaderScreen` 浮動按鈕群組合併，移除 FXL/流式雙軌 UI 分支

**Status:** ✅ 程式碼實作完成，程式碼審查通過（`tmp/epic-20/issue4-implementation-review.md`，With fixes，已依審查回應修正文件矛盾、補齊測試、訂正過度樂觀的劃線/備註驗證宣稱）。`flutter test`（全專案）733/733 通過（含審查回應補上的 3 項新測試），`flutter analyze` 乾淨（0 issues）。真機驗證已於 2026-07-31 完成（`tmp/一弦定音.epub` FXL 書籍，裝置 `3CEF42ECD491687`），截圖佐證：返回/設定（`FxlSettingsSheet`）/書籤/筆記/目錄/跳頁（20/93頁）按鈕均正常運作。**劃線/備註疊圖判準改列不適用**——FXL 圖片式頁面無文字節點可選取，正常操作下無法新增劃線/備註（`epic-6-annotations` 既有決策 #7，非本工單新增限制），詳見 `design.md`「Issue 4 實作完成紀錄」。

**依賴：** Issue 2、3。

**背景：** `spec.md`「核心介面異動」第 3 節。`reader_fixed_layout_*`（`epic-18` Issue 15 新增 4 顆）與 `reader_foliate_*`（既有 8 顆，含 Issue 20/21/22 訴求已涵蓋的跳頁/TOC/書籤/筆記功能）目前是兩組平行維護的浮動按鈕，Issue 2/3 完成後 FXL 書籍已統一走 `FoliateEpubReaderView`，兩組應合併為一組。

**範圍：**
1. 移除 `reader_fixed_layout_*` 系列按鈕與其 `_isFixedLayout` gating 條件，`reader_foliate_*` 系列按鈕的 `_dispatchedIsFixedLayout == false` gating 條件改為恆真（或直接移除該判斷式，僅保留 `_chromeVisible`）。
2. `_epubReaderViewKey`／`EpubReaderView.jumpToProgression` 等既有依 `_dispatchedIsFixedLayout` 三元判斷呼叫 `EpubReaderView` 或 `FoliateEpubReaderView` 兩個 key 之一的呼叫點，改為恆定呼叫 `_foliateEpubReaderViewKey` 對應的 static helper。
3. 盤點 `reader_screen_test.dart` 對 `reader_fixed_layout_*` Key 的既有測試斷言，移除或改寫為對 `reader_foliate_*` Key 的斷言。

**單元測試要求：** 既有 `reader_fixed_layout_*`／`reader_foliate_*` 相關 widget test 需全數審視，確認合併後行為（按鈕出現條件、點擊行為）仍有對應測試覆蓋，不遺漏。

**驗收標準：** 真機驗證 FXL 書籍的返回/設定/書籤/筆記/跳頁/目錄功能，皆透過合併後的單一按鈕群組正常運作；`flutter test`／`flutter analyze` 全數通過。

---

## Issue 5：移除 `EpubReaderView.kt`／`readium-navigator` 依賴，`MainActivity` 移除 Readium Fragment 依賴

**Status:** ✅ 程式碼實作完成，程式碼審查通過（`tmp/epic-20/issue5_code_review_report.md`，With fixes，已依審查回應修正 `app/integration_test/` 7 個檔案的失效引用、補齊 Task 1 Step 3 過時說明文字訂正、修正 `CLAUDE.md` MainActivity 文件缺口、訂正本欄位測試數字）。`flutter analyze` 乾淨（0 issues）、`flutter test`（`app/test/`）713/713 通過（較 Issue 4 基準 733 減少 20，對應刪除的 `app/test/reader/epub_reader_view_test.dart`）、`./gradlew :app:compileDebugKotlin` 成功、`flutter build apk --debug` 成功。真機 APK 已安裝至 `3CEF42ECD491687`，待人類執行完整回歸測試後結案。`MainActivity` 因 `registerForActivityResult`（FolderPicker 需要）保留 `FlutterFragmentActivity`（與原計劃不同，但功能上必要）。審查回應真機測試發現 `FoliateEpubReaderView` 的 `Failed to fetch` 間歇性 WebView 資源載入失敗，已核實在 `main`（`a7366a6`，本工單改動前）同樣可重現，非本工單迴歸，不阻塞結案，建議另立 Issue／Bug 追蹤。

**依賴：** Issue 4（確認 `reader_screen.dart` 不再有任何路徑建構 `EpubReaderView`）。

**背景：** ADR 0017 決策 1／7、`spec.md`「移除項目」。

**範圍：**
1. 刪除 `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt`／`EpubReaderViewFactory.kt`、`app/lib/reader/epub_reader_view.dart`、`app/test/reader/epub_reader_view_test.dart`。
2. `app/android/app/build.gradle.kts` 移除 `org.readium.kotlin-toolkit:readium-navigator:3.3.0`（**保留** `readium-shared`／`readium-streamer`，供 `BookMetadataChannel.kt` 使用，見 ADR 0017 決策 2）。
3. `MainActivity.kt`：移除 `EpubNavigatorFragment` 相關 import 與處理邏輯、`configureFlutterEngine()` 移除 `EpubReaderView` 的 `PlatformView` 類型字串註冊。`MainActivity` 因 `registerForActivityResult`（FolderPicker 需要）保留 `FlutterFragmentActivity`。
4. `CLAUDE.md`／`CONTEXT.md`／`AGENTS.md` 同步更新（移除對已刪除程式碼的引用、更正不成立的技術事實陳述）。

**單元測試要求：** 無新增（純刪除/簡化），`flutter test`／`flutter analyze`／`./gradlew :app:compileDebugKotlin` 全數通過。

**驗收標準：** 真機完整回歸測試（開書、翻頁、雙頁、書籤、目錄、進度、劃線/備註〔限流式書籍〕、版面設定）皆正常；`app-debug.apk` 建置成功且體積因移除 `readium-navigator` 而縮小（觀察性質，非硬性門檻）。

---

## Issue 6：FXL 書籤驗證（沿用既有 CFI locator 持久化機制）

**Status:** 實作計劃已撰寫（`plans/plan-issue-6.md`），待計劃審查通過後開始真機驗證。純驗證性質工單，不預先假設需要程式碼修正——計劃聚焦於單頁模式回歸基準（Task 1）與雙頁模式核心驗證（Task 2，含跨模式一致性、書籤跳轉後雙頁配對正確性兩項具體疑點）。

**依賴：** Issue 3。

**背景：** ADR 0017 決策 5：書籤風險低（無視覺 overlay），沿用 `FoliateEpubReaderView` 既有的 CFI locator 持久化機制（`epic-17` Issue 6 為 reflowable 已建立），本工單只需驗證雙頁模式下書籤功能是否正常運作，非新增功能。

**範圍：**
1. 真機驗證 FXL 書籍在雙頁模式下新增/刪除/跳轉書籤是否正常。
2. 若發現雙頁模式下 CFI 定位或跳轉有異常（例如書籤跳轉後畫面未正確對齊到雙頁邊界），記錄具體問題，評估是否需要額外修正（視實際發現情況另開子工單，不預先假設有問題）。

**單元測試要求：** 若發現需要程式碼修正，比照既有書籤相關測試模式補測試；若驗證結果全數正常，無需新增測試（純驗證性質）。

**驗收標準：** FXL 書籍書籤新增/刪除/跳轉/清單顯示皆正常運作，與既有流式書籍書籤功能行為一致。

---

## Issue 7：真機端到端驗證與收尾

**Status:** ready-for-agent

**依賴：** Issue 2-6 全部完成。

**背景：** 比照 `epic-17` Issue 9（真機端到端驗證與收尾）既有先例。

**範圍：**
1. 端到端組合操作序列（開書、換頁、熱區、雙頁模式切換、目錄跳轉、書籤、頁碼與重開書持久化）於真機通過驗證，涵蓋 FXL 與流式兩類書籍。
2. 既有 FXL 書籍（有舊書籤/劃線/備註/進度資料）重開後的「資料視為失效」行為（ADR 0017 決策 4）實際驗證一次，確認不會 crash、以新書狀態正常開啟。
3. 全套 `flutter test`／`flutter analyze`／`./gradlew :app:compileDebugKotlin`／`:app:testDebugUnitTest` 確認無 Regression。
4. QA 報告存放於 `reviews/qa-issue-7-report.md`。

**單元測試要求：** 無新增（驗證性質）。

**驗收標準：** 比照 `epic-17` Issue 9 驗收標準，全數通過且無 Regression。

---

## Issue 8：大型 EPUB（約 200MB+）開書時因整檔載入記憶體導致 `OutOfMemoryError` 閃退

**Status:** ✅ 實作完成。原生 `WebViewAssetLoader.InternalStoragePathHandler` 串流服務已實作（Kotlin `cacheBookForServing` + Dart `cacheBookForServing()` + `FoliateEpubReaderView` 改用 `webViewAssetLoader`），`loadBookBytes()` 已移除。額外修復 `flutter_inappwebview_android-1.1.3` `AndroidInternalStoragePathHandler.toMap()` 無限遞迴 bug（本地 patch：`app/patches/flutter_inappwebview_android/`）。711/711 單元測試通過，`flutter analyze` 乾淨。整合測試 24/26 通過（2 項失敗為既有的 FXL 超時與 DB 隔離問題，與 Issue 8 無關）。真機 217MB EPUB 開書不再 OOM。待送出 code review。

**發現時機／方式：** 2026-07-31，Issue 3 真機測試階段人類回報「開啟 `tmp/膽大黨10.epub`（正常 FXL 漫畫）會閃退，但 `tmp/一弦定音.epub`（Issue 1/2 一路使用的測試書）沒事」。由 Claude Code 直接 `adb -s 3CEF42ECD491687 shell dumpsys dropbox --print` 從真機拉出 6 筆真實當機記錄查證，非二手轉述，逐一交叉比對程式碼確認根因，詳見 `tmp/epic-20/issue3-implementation-review.md`。**已確認與 Issue 3 本身的 `spread` attribute 邏輯完全無關**（Issue 3 分支未觸碰任何 `.kt` 檔案／`foliate_native_bridge.dart`）。

**根因（已用真機 logcat + 原始碼交叉查證，非推測）：**

```
java.lang.OutOfMemoryError: Failed to allocate a 219210408 byte allocation with 25165824 free bytes and 41MB until OOM, target footprint 249790736, growth limit 268435456
	at java.util.Arrays.copyOf(Arrays.java:4276)
	at java.io.ByteArrayOutputStream.toByteArray(ByteArrayOutputStream.java:211)
	at kotlin.io.ByteStreamsKt.readBytes(IOStreams.kt:152)
	at cc.ugotit.elinkbook.ReaderResourceChannel.onMethodCall(ReaderResourceChannel.kt:58)
```

`FoliateEpubReaderView` 開書時，`loadBookBytes()`（`app/lib/reader/foliate_native_bridge.dart:113-124`）依 `filePath` 是否為 `content://` URI 分派：`content://` 走 `ReaderResourceChannel.kt:58` 的 `readContentUri`（`context.contentResolver.openInputStream(...).use { it.readBytes() }`）；本機檔案路徑走 Dart `File.readAsBytes()`（`foliate_native_bridge.dart:124`）。兩者皆是**整份檔案一次性讀進單一 byte array**，供 `InAppWebView.shouldInterceptRequest` 攔截 `/book/current.epub` 後整包回傳——這是既有、經查證的設計（程式碼註解已明文記載：`main.js` 的 `view.js` `makeBook()` 對這個 URL 只做一次性 `fetch()`、不發 HTTP Range 請求，見該函式 doc comment），不是本次新發現的程式錯誤，而是**檔案大小超出既有假設**首次被真實踩到。

**與檔案大小直接對應**：
- `tmp/膽大黨10.epub` = 217,237,457 bytes → 崩潰時嘗試配置 219,210,408 bytes，超過 App heap 上限（`growth limit 268435456` ≈ 256MB，扣掉既有佔用後不足）
- `tmp/一弦定音.epub` = 76,791,360 bytes → 遠低於上限，故 Issue 1/2 全程未觸發

**影響範圍**：`loadBookBytes()`／`_shouldInterceptRequest` 是 `FoliateEpubReaderView` 通用機制，**不分 FXL／流式**，任何經此 widget 開啟（epic-20 Issue 2 起已是全部 EPUB 的唯一路徑）、檔案大小逼近或超過 App heap 上限的書籍皆會受影響，非 FXL 專屬問題。

**`/diagnose` 修復方向研究結論（2026-07-31，完整過程見 `reviews/bugfix-repro.md`）：**

方向 (1)「串流/分塊讀取」**技術上完全可行**，且是唯一能徹底解法（非治標）的選項，已查證確認：

- 現行 Dart 端 `InAppWebView.shouldInterceptRequest` callback（含 `flutter_inappwebview` 的 `CustomPathHandler`）一律要求回傳 `Uint8List`，天生無法串流——問題不在 Kotlin 端怎麼讀，瓶頸在跨 platform channel 前 Dart 端必須先持有完整位元組陣列。
- `flutter_inappwebview` 原生端已內建 `WebViewAssetLoader` 整合（優先於 Dart callback 被檢查），其 `InternalStoragePathHandler` 完全在原生端運作、以 `FileInputStream` 串流讀取，**不經過 Dart callback，不受 `Uint8List` 限制**，且不需要 fork/patch 套件本身。
- 本機檔案路徑（既有 `isPathWithinRoot` 已強制要求落在 App 私有資料目錄）已 100% 符合 `InternalStoragePathHandler` 前提，不需額外複製；`content://` SAF 來源可比照既有 `BookImportService`（ADR 0002）落地機制，開書前以 Kotlin `InputStream.copyTo(OutputStream, bufferSize)` 有界記憶體分塊複製到私有快取後，同樣走 `InternalStoragePathHandler`。
- **不會**波及 `readest/foliate-js` 釘定版本「一次性 `fetch()`」的既有假設——`InternalStoragePathHandler` 只改變原生端「怎麼組出 `WebResourceResponse`」，WebView 收到的仍是單一完整 HTTP 回應，不涉及 HTTP Range，不需要修改釘定版本任何程式碼。
- 本專案 epic-17 時期（commit `4bc492a`）其實用過原生 `WebViewAssetLoader`，後來因 ADR 0013（觸控/選字手勢限制，與記憶體無關）換成目前的 `flutter_inappwebview` `InAppWebView`——改回原生資產載入不是走回頭路撞到 ADR 0013 要解決的問題，手勢處理仍由 `InAppWebView` 負責，只是資源載入這一小塊換回原生路徑。

**下一步：** 已具備足夠可行性證據直接進入 Planning（視規模決定是否需要新 ADR 記錄「resource loading 從 Dart-side callback 改回原生 WebViewAssetLoader」的決策），標記 `ready-for-agent`。**與 Issue 7（真機端到端驗證）之間建立相依關係**：Issue 7 的真機驗證應涵蓋至少一本大型（150MB+）真實書籍，驗收判準包含 `tmp/膽大黨10.epub`（217MB，本 Issue 原始崩潰樣本）真機開啟不再 OOM。

**追加查證（2026-07-31，人類提供兩份外部分析報告後）：** 逐項核對 `tmp/epic-20/anx_reader_large_file_analysis_report.md`／`foliate_large_file_analysis_report.md` 的具體技術宣稱與本專案 vendored 原始碼是否相符（完整過程見 `reviews/bugfix-repro.md` 追加段落）——`zip.js` 具備 `HttpRangeReader` 隨需讀取的核心論點**經查證不成立**（本專案 vendored 的 `vendor/zip.js` 全檔搜尋無 `HttpRangeReader`、無任何 `Range` 字樣，只有 `BlobReader`／`FileReader`／`ZipReader`），與 `epic-18` Issue 21 先前發現的「外部報告編造不存在 API」是同一種失準模式；`epub.js` `Loader` 引用計數卸載機制、`fixed-layout.js` `maxLoaded`/`maxConcurrent` 頁面調度機制則查證屬實，但兩者管的是「書已開啟後逐頁閱讀期間」的記憶體，不影響「開書當下」的問題本身。獨立重新查證 `view.js` `fetchFile()`：`fetch(url)` + `await res.blob()` 為單次完整緩衝，與既有查證結論一致。**新增一項尚待真機驗證的殘餘風險**：原生端串流修正後，WebView 仍會對整份回應呼叫 `res.blob()`，在渲染器行程（獨立於 App 主行程）緩衝整份內容，這一步驟對 217MB 檔案是否會觸發渲染器行程自身的 OOM 目前無既有證據（原始崩潰發生在更早的 App 主行程階段，從未真正走到這一步）——Planning／實作階段完成原生串流修正後，務必以 `tmp/膽大黨10.epub` 在真機測試到底整個開書流程（含 WebView 端），不能只確認 `ReaderResourceChannel.kt` 這一個點不再拋錯。

---

## Issue 9：`FoliateEpubReaderView` 開書偶發 `onError('Failed to fetch')`／`onLayoutResolved` 逾時，與分支無關的既有問題

**Status:** needs-triage

**發現時機／方式：** 2026-07-31，Issue 5 程式碼審查回應階段，於真機（`3CEF42ECD491687`）執行 `flutter test integration_test/foliate_epub_reader_view_test.dart -d 3CEF42ECD491687` 驗證審查回應的測試修正時發現。

**現象：** 同一輪測試執行內，多項測試（含完全未被本次改動觸碰的既有測試）出現兩類失敗：
1. `onError` 收到字面訊息 `'Failed to fetch'`（而非預期的 `null`／特定驗證訊息），包含最基本的「開啟有效的流式 EPUB 檔案觸發 onPageRendered」（第一項測試，最簡單情境即失敗）、「PathHandler 路徑穿越防護」（預期收到含『允許的目錄範圍』的訊息，實際收到 `'Failed to fetch'`）、「字型/字級/行距等偏好設定套用」。
2. `onLayoutResolved`／`onPageRendered` 完全未觸發，10 秒後 `TimeoutException`：「FR-06：開啟自行宣告 writing-mode」「FR-06：開啟完全不宣告 writing-mode」「手動切換橫排→直排」。

**已排除為本次分支迴歸的查證過程：**
- 完整 `adb uninstall`／重新安裝後重跑，現象不變。
- `adb shell pm clear com.google.android.webview`（清除 WebView 元件資料）後重跑，現象不變。
- **切換到 `main`（commit `a7366a6`，epic-20 Issue 5 任何改動之前）重跑同一份測試，現象完全相同**（同樣是第一項最基本測試就以 `'Failed to fetch'` 失敗）——確認與 Issue 5 的 Dart／Kotlin 改動無關，是既有、branch-independent 的問題。
- 用 `integration_test/smoke_test.dart`（純 Flutter widget，不涉及 `FoliateEpubReaderView`／WebView）驗證裝置本身可正常執行 integration test、非裝置全面故障——僅 `FoliateEpubReaderView` 的 WebView 資源載入路徑受影響。
- `adb logcat` 未在失敗當下找到明確對應的原生端錯誤堆疊（WebView/chromium 啟動日誌看起來正常，`Failed to fetch` 是 JS `fetch()` 層級的錯誤訊息，尚未定位是 `main.js`／`view.js` 內部哪一次 `fetch()` 呼叫失敗、或 `InAppWebView.shouldInterceptRequest`／`ReaderResourceChannel` 原生端攔截哪個環節出狀況）。

**已知但未確認的線索：** 本次失敗具間歇性——同一份 `FoliateEpubReaderView` 架構在本次 epic-20（Issue 1-5）多次先前的真機人工驗證（Issue 3/4 的手動驗收、Issue 1/2 的 spike）皆成功開書，並非「這條路徑從未在此裝置上正常運作過」；本次是在同一個裝置上短時間內反覆執行大量 `flutter test -d` 建置/安裝/解除安裝循環（本次審查回應流程內即重新建置安裝 3 次以上）之後才穩定重現，不排除與裝置端資源狀態（記憶體/儲存空間/WebView sandboxed process 累積）或近期裝置系統 WebView 更新（`com.google.android.webview` 150.0.7871.181）有關，但未實際驗證。

**待決事項（需人類決定調查方向，故標記 `needs-triage`）：**
1. 是否值得投入 `/diagnose` 立案調查根因（例如逐步加 log 定位是哪一次 `fetch()` 呼叫失敗、或改用 `chrome://inspect` 遠端除錯 WebView 內容），還是先觀察是否為裝置特定的暫時性狀態（例如重啟裝置、換一台裝置測試是否重現）。
2. 若確認間歇性與「短時間內大量重複安裝/解除安裝」相關，可能純屬本機開發/測試循環的副作用，不代表終端使用者實際會遇到的問題——待確認後再決定是否需要修正產品程式碼，或只是測試流程本身需要調整（例如兩次真機測試之間加入裝置重啟）。

**建議下一步：** 不阻塞 Issue 5／Issue 6／Issue 7 的既定工作——三者皆已個別確認過這類 WebView 資源載入路徑在人工真機驗證時可正常運作。建議累積更多重現樣本（不同裝置、不同時間點）後再評估是否立案 `/diagnose`。
