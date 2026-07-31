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

**Status:** 實作計劃已撰寫（`plans/plan-issue-4.md`），待計劃審查通過後開始執行。

**依賴：** Issue 2、3。

**背景：** `spec.md`「核心介面異動」第 3 節。`reader_fixed_layout_*`（`epic-18` Issue 15 新增 4 顆）與 `reader_foliate_*`（既有 8 顆，含 Issue 20/21/22 訴求已涵蓋的跳頁/TOC/書籤/筆記功能）目前是兩組平行維護的浮動按鈕，Issue 2/3 完成後 FXL 書籍已統一走 `FoliateEpubReaderView`，兩組應合併為一組。

**範圍：**
1. 移除 `reader_fixed_layout_*` 系列按鈕與其 `_isFixedLayout` gating 條件，`reader_foliate_*` 系列按鈕的 `_dispatchedIsFixedLayout == false` gating 條件改為恆真（或直接移除該判斷式，僅保留 `_chromeVisible`）。
2. `_epubReaderViewKey`／`EpubReaderView.jumpToProgression` 等既有依 `_dispatchedIsFixedLayout` 三元判斷呼叫 `EpubReaderView` 或 `FoliateEpubReaderView` 兩個 key 之一的呼叫點，改為恆定呼叫 `_foliateEpubReaderViewKey` 對應的 static helper。
3. 盤點 `reader_screen_test.dart` 對 `reader_fixed_layout_*` Key 的既有測試斷言，移除或改寫為對 `reader_foliate_*` Key 的斷言。

**單元測試要求：** 既有 `reader_fixed_layout_*`／`reader_foliate_*` 相關 widget test 需全數審視，確認合併後行為（按鈕出現條件、點擊行為）仍有對應測試覆蓋，不遺漏。

**驗收標準：** 真機驗證 FXL 書籍的返回/設定/書籤/筆記/跳頁/目錄功能，皆透過合併後的單一按鈕群組正常運作；`flutter test`／`flutter analyze` 全數通過。

---

## Issue 5：移除 `EpubReaderView.kt`／`readium-navigator` 依賴，`MainActivity` 改回 `FlutterActivity`

**Status:** ready-for-agent

**依賴：** Issue 4（確認 `reader_screen.dart` 不再有任何路徑建構 `EpubReaderView`）。

**背景：** ADR 0017 決策 1／7、`spec.md`「移除項目」。

**範圍：**
1. 刪除 `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt`／`EpubReaderViewFactory.kt`、`app/lib/reader/epub_reader_view.dart`、`app/test/reader/epub_reader_view_test.dart`。
2. `app/android/app/build.gradle.kts` 移除 `org.readium.kotlin-toolkit:readium-navigator:3.3.0`（**保留** `readium-shared`／`readium-streamer`，供 `BookMetadataChannel.kt` 使用，見 ADR 0017 決策 2）。
3. `MainActivity.kt`：`FlutterFragmentActivity` 改回 `FlutterActivity`；移除 `EpubNavigatorFragment` 相關 import 與程序還原邏輯（`:60-75`）；`configureFlutterEngine()` 移除 `EpubReaderView` 的 `PlatformView` 類型字串註冊。
4. `docs/CONTEXT.md`／`CLAUDE.md`「`MainActivity` 為何是 `FlutterFragmentActivity`」段落同步更新或移除（該段落說明的理由已不成立）。

**單元測試要求：** 無新增（純刪除/簡化），確保 `flutter test`／`flutter analyze`／`./gradlew :app:compileDebugKotlin` 全數通過，無殘留的失效 import 或未使用程式碼。

**驗收標準：** 真機完整回歸測試（開書、翻頁、雙頁、書籤、目錄、進度、劃線/備註〔限流式書籍〕、版面設定）皆正常；`app-debug.apk` 建置成功且體積因移除 `readium-navigator` 而縮小（觀察性質，非硬性門檻）。

---

## Issue 6：FXL 書籤驗證（沿用既有 CFI locator 持久化機制）

**Status:** ready-for-agent

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

**Status:** needs-triage

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

**待決事項（需人類決定修復方向，故標記 `needs-triage` 而非 `ready-for-agent`）：**
1. 是否改為串流／分塊讀取（例如 `WebResourceResponse` 直接接 `InputStream` 而非先讀完整個 `ByteArray`，若 `flutter_inappwebview`／Android `WebResourceResponse` API 支援的話）——徹底解法，但需評估對 `content://` SAF 來源與本機檔案兩種情況是否都可行，以及是否波及 `view.js` `makeBook()` 「一次性 fetch」的既有假設（可能需要上游 `readest/foliate-js` 支援 Range，而該專案是「不修改釘定版本」的既有限制，需先查證是否可行）。
2. 或先設一個保守的檔案大小警戒值，超過時提示使用者「檔案過大可能無法開啟」而非讓 App 無聲閃退（治標，成本低，可作為 1 的過渡方案）。
3. 或評估提高 App 的 `largeHeap` manifest 設定（`android:largeHeap="true"`）暫時緩解（治標，非長期解法，且部分裝置可能仍不夠）。

**建議下一步：** 若優先處理，建議先跑 `/diagnose` 或 Discovery 階段確認修復方向（技術可行性），再視結果決定是否需要新 ADR（若牽涉 `readest/foliate-js` Range 支援評估）或直接進入 Scrum Master 拆工單。**建議與 Issue 7（真機端到端驗證）之間建立相依關係**：Issue 7 的真機驗證應涵蓋至少一本大型（150MB+）真實書籍，若本 Issue 未修復，Issue 7 驗收時須明確記錄「大型檔案已知限制」而非略過不提。
