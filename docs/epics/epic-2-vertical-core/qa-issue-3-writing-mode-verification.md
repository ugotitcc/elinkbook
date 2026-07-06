# Issue 3 驗證紀錄：FR-32 避頭尾符合度與直排分頁文字裁切問題

依 `docs/epics/epic-2-vertical-core/issues.md` Issue 3 與 `docs/epics/epic-2-vertical-core/plans/plan-issue-3.md` 產出。

## 測試環境

| 項目 | 值 |
| --- | --- |
| 裝置型號 | `9491G`（`9491G_ZZ`／`Hera_Vis_WIFI`，實體裝置，非模擬器） |
| Android 版本 | 15（API 35） |
| 螢幕解析度 | 實體 1600x2400；驗證當下裝置呈橫向（landscape），螢幕實際渲染為 2400x1600 |
| 螢幕密度 | 實體密度 320，覆寫密度 366 |
| 系統 WebView 版本 | `com.google.android.webview` versionName `149.0.7827.159`（另偵測到次要 versionName `137.0.7151.115`，為同套件內的次要條目） |
| App 建置方式 | `flutter build apk --debug`（本機組建，未簽章 release），透過 `flutter test integration_test/<暫時性 scratch 測試檔>` 安裝並啟動 |

**方法說明（與 plan-issue-3.md Task 2 brief 的差異）：** 未透過 `LibraryScreen` 的匯入 UI 手動操作，改用暫時性 `integration_test` scratch 測試檔（用畢即刪，未提交版控，比照 Task 1 已刪除的 Python 腳本慣例）直接建構 `ReaderScreen(filePath: ...)`，繞開匯入流程的不確定性；`sample_long_vertical.epub` 開書後預設即為直排模式（切換按鈕 tooltip 顯示「切換為橫排」，代表目前已是直排，未點擊按鈕），畫面保持存活供外部 `adb screencap` 截圖。

## 一、FR-32 標點轉向與避頭尾比對

**方法：** 於裝置上開啟 `sample_long_vertical.epub`（預設直排模式），透過 `adb shell screencap` 截圖並以視覺方式比對下表六個 CNS 11643 常見避頭尾/標點類別的實際渲染結果。截圖涵蓋第 1～31 段內容（`qa-issue-3-fr32-overview.png`）。

| 類別 | 代表字元 | 規則 | 觀察結果（符合／不符合＋說明） |
| --- | --- | --- | --- |
| 收尾類標點不可置於行首 | 」』）］｝、。，；：？！ | 不可出現在下一欄（頁）的最上方 | **無法在本次測試中實際觸發驗證**（見下方說明） |
| 起頭類標點不可置於行尾 | 「『（〔［｛《〈 | 不可出現在欄（頁）的最下方 | **無法在本次測試中實際觸發驗證**（見下方說明） |
| 破折號 | —— | 應連續轉向為縱向、不可斷開 | 符合。`qa-issue-3-fr32-overview.png` 中第 6、16、26 段（「——這是第N段以破折號開頭的句子……」）的「——」皆正確轉向為縱向連續雙短橫，未斷開、未橫向殘留。 |
| 刪節號 | …… | 應連續轉向為縱向、不可斷開 | 符合。第 7、17、27 段（「他在第N段說……然後就沉默了」）的「……」皆正確轉向為縱向連續六點，置中對齊字身。 |
| 書名號 | 《》 | 應正確轉向並置中 | 符合。第 8、18、28 段（「《紅樓夢》是第N段提到的經典小說；《西遊記》也是。」）的《》皆正確轉向為縱向書名號，置中對齊，未見橫向殘留或錯位。 |
| 一般標點置中 | 、。，；：？！ | 直排時應置中對齊字身，而非貼齊某一側 | 符合。全書所有段落中的句號、逗號、頓號、問號、驚嘆號、冒號、分號在螢幕截圖中皆置中對齊各自欄位的字身寬度，未見貼齊左右某一側的情形。 |

**關於前兩類「無法在本次測試中實際觸發驗證」的說明：**

`sample_long_vertical.epub`（Task 1 建立）的 60 段內容，每一段都是一句可在此裝置字級/欄高下完整容納於單一欄位（頁）內的短句（最長約 24～26 字），實機觀察確認：**每一段落的起訖點都精準對齊欄位邊界，段落之間沒有發生「一句話中途被欄高強制換行、其中一部分落到下一欄」的情形**。CNS 11643 避頭尾規則（收尾類標點不可置於行首／起頭類標點不可置於行尾）只在「連續文字因欄高限制被強制換行」時才有意義——若換行點永遠精準落在段落與段落之間（本來就有自然間隔，不需要避頭尾判斷），這條規則就沒有實際運作的機會可供觀察。

因此，這兩類項目**不是「符合」也不是「不符合」，而是本次 fixture 內容設計無法產生可觀察的測試情境**。若要真正驗證這兩條規則，需要一段長度足以在單一欄位內自然換行（而非每段獨立成欄）的連續文字，讓某個換行點恰好落在收尾/起頭類標點附近，藉此觀察 Readium 的 `line-break:strict` 是否確實把該標點推到下一欄，而不是留在錯誤的行首/行尾位置。本次驗證未新增此類 fixture 內容（屬於本次執行的範圍限制，記錄於此供後續複查/追加測試參考）。

## 三、文字裁切問題重現

**回報症狀：** 實機測試中，EPUB3 在手機/平板呈直立（portrait）狀態、採用直排（vertical-RL）閱讀模式時，畫面上下邊緣會出現部份文字被裁切的現象。

**方法補充：** 沿用第一、二章相同的暫時性 `integration_test` scratch 測試檔手法。實測發現兩個與 plan-issue-3.md 原始步驟不同的技術細節，記錄於此供後續任務參考：

1. **`adb shell input swipe` 在 `flutter test integration_test` 執行期間不會真正送達原生 PlatformView**：`LiveTestWidgetsFlutterBinding`（`flutter test` 使用的 binding）會攔截外部注入的觸控事件，僅印出診斷用的「Some possible finders for the widgets at Offset(...)」訊息，不會轉發給底層 WebView 處理翻頁手勢。必須改用 `WidgetTester.dragFrom()`（測試框架自己送出、會正確經由 `GestureBinding` 轉發到原生 `AndroidView` 的手勢）才能讓翻頁動作真正生效。
2. **啟動 `flutter test` 的 host shell 環境變數不會傳遞進裝置端執行的 App 行程**：`Platform.environment` 在裝置端讀到的是裝置自己的環境，與啟動指令的主機 shell 環境無關；要切換測試用的 fixture，須直接修改 scratch 測試檔內寫死的路徑重新執行，無法透過 `FOO=bar flutter test ...` 的環境變數前綴傳遞參數給裝置端程式碼。

**重現條件矩陣：**

| # | 裝置 | 螢幕方向 | 書籍 | 是否出現裁切 | 裁切位置（畫面上緣／下緣／兩者皆有） | 截圖檔名 |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | `9491G`（實體） | 直立 (portrait) | sample_long_vertical.epub | 否（僅見第 1～19 段，第 20～60 段未能翻頁看到） | 無 | `qa-issue-3-clip-row1-portrait-long.png` |
| 2 | `9491G`（實體） | 橫向 (landscape) | sample_long_vertical.epub | 否（僅見第 1～31 段，第 32～60 段未能翻頁看到） | 無 | `qa-issue-3-clip-row2-landscape-long.png` |
| 3 | `9491G`（實體） | 直立 (portrait) | sample.epub（短內容） | 否 | 無 | `qa-issue-3-clip-row3-portrait-short.png` |
| 4 | 無可用裝置，未執行 | — | — | — | 此工作環境（sandbox）無法啟動 Android 模擬器（`Pixel_9`/`Medium_Tablet` 皆已嘗試，`qemu-system-x86_64.exe` 啟動後數秒內固定以 exit code 1 結束，研判為沙盒對巢狀虛擬化的限制，見 `.superpowers/sdd/progress.md` 環境阻塞紀錄），且僅有一支實體裝置可用，無法測試第二支裝置/平板 | — |

**每一列的判別重點：** 裁切若只發生在「特定頁面」而非每一頁都發生，代表症狀符合「欄位高度非行高整數倍，導致該欄最後一行卡在邊界」的假說（見 Task 4）；若每一頁都固定裁切同樣位置，則較可能是容器整體尺寸量測錯誤。

**【審查修正】本節原先誤判「60 段內容在此裝置字級下一次顯示完畢、未產生第二欄」，經重新比對截圖後確認此判斷有誤，已修正如下：** 比對 `qa-issue-3-clip-row1-portrait-long.png`（直立，可見第 1～19 段）與 `qa-issue-3-clip-row2-landscape-long.png`（橫向，可見第 1～31 段）可發現，**橫向視窗看到的段落數量明顯比直立多**（19 → 31 段），且兩者都只看到 60 段中的一部分——這正是「內容確實有跨欄位分頁、但目前畫面只顯示了第一頁」的訊號，而不是「內容一次顯示完畢、沒有分頁」。換言之：**這本書在此裝置上確實有分頁（欄位邊界確實存在於第 19/31 段之後），但本次測試使用的 `tester.dragFrom()` 拖曳手勢未能成功觸發翻頁動作**（畫面內容在嘗試拖曳前後不變），因此沒有機會看到第 20～60 段（直立）或第 32～60 段（橫向）的畫面、也就沒有機會在真正的欄位邊界上觀察是否有裁切。根因可能是拖曳位移量（500px）或缺乏 fling 速度，未達到 Readium 底層 ViewPager2 判定「翻頁」的門檻——這是**測試手法本身的落差**，不是「書籍不需要分頁」的證據，也不應被解讀為 fixture 需要重新設計。

**結論（重現部分）：本次在僅有的一支實體裝置上，三種可測試的條件組合，在「已看到的頁面範圍內」皆未觀察到裁切；但同時未能成功翻頁看到書籍其餘部分，因此無法排除裁切發生在未觀察到的頁面。** 已知本次測試的侷限：(a) 拖曳翻頁手勢的位移量/手勢類型未能成功觸發 Readium 的分頁切換，導致大部分內容（直立第 20～60 段、橫向第 32～60 段）從未被實際看到；(b) 只有一種裝置/字級組合可供測試，使用者原始回報的裝置型號、字級設定、書籍內容皆未知，無法排除是這些因素的特定組合才會觸發裁切。Task 4 的根因分析（見下一節）改以靜態分析 ReadiumCSS 原始碼與比對 upstream 已知 issue 為主要依據，彌補本節「未能實機重現真正分頁邊界」的落差；若後續 issue 需要重新進行實機重現，應優先修正翻頁手勢（例如改用足夠位移量的 fling，或直接呼叫 Readium navigator 的翻頁 API）而非懷疑 fixture 內容長度不足。

## 二、結論

**部分符合 CNS 11643，另有兩類因 fixture 內容限制未能實際驗證：**

- 已驗證的四類（破折號、刪節號、書名號、一般標點置中）皆符合預期，`cjk-vertical` ReadiumCSS 內建規則在這四類上運作正常，不需額外開發或覆寫。
- 避頭尾換行規則（收尾類標點不可置於行首、起頭類標點不可置於行尾）**未能在本次測試中被實際觸發**：`sample_long_vertical.epub` 的每一段落皆短到可完整容納於單一欄位內，欄位邊界永遠精準落在段落之間，從未發生「連續文字因欄高被強制換行」的情形，因此無從觀察 `line-break:strict` 在真正需要避頭尾判斷時的實際表現。
- 是否需要新增後續 issue：**建議新增**——需要一份包含足夠長、會在欄位內自然換行的連續段落（而非本次全為短句独立成段）的 fixture，才能真正驗證避頭尾規則本身；本次驗證範圍未包含此項 fixture 擴充工作。是否新增獨立 issue 或併入 Task 6 的後續處理，留待 Task 6 依 Task 3/4/5（文字裁切問題）調查結果一併決定，避免同一輪產生過多細碎 issue。

## 四、根因分析

**CSS 靜態證據：** 解壓 `readium-navigator:3.3.0` AAR（路徑：`org.readium.kotlin-toolkit/readium-navigator/3.3.0/162dd7fdee9e61a10441e5262792ec0d76b6011e/readium-navigator-3.3.0.aar`，本次執行者親自重新解壓並讀取，非沿用先前結論），`assets/readium/readium-css/cjk-vertical/ReadiumCSS-after.css` 的 `:root` 規則實際內容為：

```css
:root{--RS__colWidth:100vh;--RS__colCount:1;--RS__colGap:0;--RS__maxLineLength:40rem;--RS__pageGutter:20px}
/* ... */
:root{position:relative;column-width:var(--RS__colWidth);column-count:var(--RS__colCount);
column-gap:var(--RS__colGap);column-fill:auto;width:100%;height:100vh;max-width:100%;
max-height:100vh;min-width:100%;min-height:100vh;...writing-mode:vertical-rl}
```

確認 `--RS__colWidth`、`height`、`max-height`、`min-height` 皆為 `100vh`，`column-fill:auto`（單欄逐欄填滿）。即直排分頁的欄位（頁）尺寸完全由 CSS viewport-height 單位驅動，沒有任何機制確保 `100vh` 換算出的實際像素高度是行高（line-height）的整數倍——這是 CSS 規格本身的限制，不是某個特定數值算錯。

**Upstream 已知 issue：**

- `readium/swift-toolkit#804`（狀態：**已關閉**，3 則留言）——標題與本專案症狀完全一致：「column height not aligned to line-height clips partial last line at column boundary」。回報者提供的機制說明：`:root` 套用 `height:100vh` + `column-fill:auto`，當視窗可視高度（`clientHeight`）不是行高的整數倍時，WebKit 會把最後一行（不足一整行）安排進欄位，該行的上緣或下緣會超出欄位邊界而被裁切，肉眼可見的效果是「頁面上下緣出現字元的上半部或下半部」。回報者附上具體幾何範例：`clientHeight=750px`、`lineHeight=24.48px`，比值為 30.6372（非整數），第 31 行會落在 y=734.4→758.88px，其下緣 8.88px 超出欄位邊界。回報者提出的修法是在字型載入完成後，用 JavaScript 把 `:root` 的 height 對齊到行高整數倍（`Math.floor(clientHeight/lineHeight)*lineHeight`），建議實作於 `EPUBReflowableSpreadView`。此問題特別容易在使用者自訂發行商字型（實際渲染行框高度與 CSS 宣告的 line-height 不一致）時出現。
- `readium/readium-css#141`（狀態：**開啟中**，0 則留言）——標題「Park support of pagination for vertical writing」，由 ReadiumCSS 維護者 JayPanoz 發起。內容說明因 CSS Multicolumn／Fragmentation 規格本身的限制，無法完全實現使用者對直排分頁的期待，因此暫緩（park，非放棄）直排分頁支援的進一步開發。文中提到一個對本專案有直接參考價值的細節：**「ReadiumCSS's pagination is disabled in Thorium when rendering vertical writing」**——官方參考 App Thorium 在直排模式下實際上是停用分頁、改用水平方向的視窗捲動（scroll）來呈現內容，理由是直排文字的分頁通常需要用程式化方式處理（利用直排文字字元大致等寬的特性），而非單純依賴 CSS 多欄佈局。

**與本專案程式碼的比對：** 檢視 `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt`（第 127 行）目前呼叫 `navigatorFragment?.submitPreferences(EpubPreferences(verticalText = mode == "vertical"))`，只設定了 `verticalText`，並未額外覆寫 scroll/分頁相關偏好設定去強制直排模式改用水平捲動——也就是說本專案目前依賴的正是 Readium/ReadiumCSS 在直排模式下的**預設分頁行為（CSS 多欄）**，而非官方參考 App Thorium 因 #141 而採用的「直排一律改用捲動」規避方案。這代表本專案目前的直排實作，走的正是 #804 描述的那條會產生裁切的程式碼路徑。

**與 Task 3 重現結果的交叉比對（誠實揭露落差）：** Task 3 的實機重現嘗試**並未真正觀察到欄位邊界**——`WidgetTester.dragFrom()` 翻頁手勢未能成功觸發 Readium 底層的翻頁動作，三種已測試的裝置/方向/書籍組合都只看到第一頁範圍內的內容（直立可見第 1～19 段、橫向可見第 1～31 段，60 段內容中僅一部分），因此無法比對「裁切是否只發生在特定頁面」還是「每頁固定裁切同一位置」這項原訂的診斷特徵。這不是「未發現裁切代表沒有 bug」的證據——分頁確實存在（不同視窗寬度看到的段落數量不同，證明有跨欄位分頁），只是本次測試手法（拖曳位移量/手勢類型）沒能推進到下一頁，因此完全沒有機會在真正的欄位邊界上做觀察。**誠實陳述：本節的根因結論建立在 Step 1／Step 2 的靜態 CSS 與 upstream issue 證據之上，並未取得與 Task 3 的實機交叉驗證。** 若後續要補上這項交叉驗證，需要先修正翻頁手勢（例如改用足夠位移量的 fling，或直接呼叫 Readium navigator 的翻頁 API），而非在目前證據基礎上勉強拼湊一個「已交叉驗證」的結論。

**結論：** 在僅能依據靜態分析的前提下，判定使用者回報的「直排模式畫面上下緣文字裁切」symptom，其根因**確認為 Readium/ReadiumCSS 的 CSS 多欄（multicol）分頁機制在直排書寫模式下的已知上游限制**（`--RS__colWidth`/`height`/`max-height`/`min-height` 皆為 `100vh`、且未對齊行高整數倍，與 `swift-toolkit#804` 描述的機制一致；`readium-css#141` 進一步證實官方對「直排＋CSS 多欄分頁」組合本身的可靠性抱持保留態度，才會提出改採水平捲動的 Thorium 規避方案），**而非本專案 `EpubReaderView.kt`／`epub_reader_view.dart` 自身的程式碼缺陷**——本專案並未修改或覆寫 `cjk-vertical` 的欄位尺寸相關 CSS 變數，裁切現象源自 Readium 官方隨附的 ReadiumCSS 本身。此結論的信心程度受限於「未能與 Task 3 完成實機交叉驗證」這項已知落差（見上），屬於**靜態分析支持、但未經實機最終確認**的結論等級，建議 Task 6 據此決定後續處理方向（例如：比照 Thorium 改用捲動模式規避、或等待上游修正、或嘗試移植 `#804` 建議的行高對齊 JS 修法）。
