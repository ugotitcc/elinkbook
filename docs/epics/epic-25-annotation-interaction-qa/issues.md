# Epic 25 — 劃線/備註真機互動精修：工單清單 (Issues)

依 `design.md`「第一輪真機使用回報」（2026-08-12，4 項回報）拆解為 Issue 1-4。全部工單彼此獨立、無依賴關係，可任意順序或平行開始。

---

## Issue 1：畫線選取已確立仍跳頁（裝置相關——Air Reader Pro C 會、TCL 14 吋不會）

**Status:** ✅ 已修復（真機人工驗證，人類確認「改善很多，先這樣」）。兩層防護：`_hasActiveSelection` 抑制（選取已確立時）＋`_NavZoneTapDetector._tapMaxDurationMs` 400ms→700ms（對齊/超過原生長按辨識所需時間）。第六輪真機驗證（`log13.txt` 之後）確認跳頁大幅減少，人類決定以目前狀態結案，不再繼續逐 ms 調校。

**已知殘留限制（誠實記錄，非聲稱 100% 解決）**：結構性上，700ms 仍是「等待原生長按辨識完成」的一個經驗值，不是理論上界——不同裝置/系統負載下，原生長按實際判定所需時間理論上仍可能超過 700ms，屆時同一類跳頁仍有極低機率重現。人類已確認此殘留風險可接受，**若未來需要進一步優化，應另立新 Issue**，不在本 Issue 範圍內繼續調校。

**Cleanup**：全部暫時性除錯插樁（`main.js` 的 `[DEBUG-e25i1]`／`[DEBUG-e25i1-gate]`／`[DEBUG-e25i1-end]`、`foliate_epub_reader_view.dart` 的 `[DEBUG-e25i1-navzone]`）已整段移除，只保留兩個正式修法本體（`evt.preventDefault()` ＋ `{ passive: false }`、`_hasActiveSelection` 抑制 ＋ `_tapMaxDurationMs = 700`）與其永久性說明註解。`tmp/epic-25-issue-1-harness/smoke.mjs`（未進版控）驗證的是已移除的插樁 log，目前重跑會 `FAIL`（`debugLogs captured: 0`），已是預期中的過期產物，不需要修——該 harness 本來就只是診斷階段的輔助工具，不是永久回歸測試。`flutter test`（`foliate_epub_reader_view_test.dart` 64/64）、`flutter analyze`、`node --check main.js` 語法檢查皆通過。

**依賴：** 無

**背景：** 使用者回報：畫線拖曳選取、控點（handle）已顯示於選取範圍左右兩側（即選取已確立）時，Air Reader Pro C 仍會出現頁面跳動，TCL 14 吋不會發生同一症狀。

**與 `epic-18` Issue 47 的關係：** Issue 47 的攔截器一旦偵測到 `selection.rangeCount > 0 && !selection.isCollapsed`（選取已確立）即主動放手（`main.js` 的 `longPressGateState = null; return`），之後交由 `paginator.js` 既有守衛（`paginator.js:2191-2195`）處理。本項回報的正是「已確立」情境本身在特定裝置失效，理論上不屬於 Issue 47 修復範圍。

**根因假說（排序，第 0 項為 2026-08-12 三輪真機資料〔`tmp/epic-25/log.txt`／`log2.txt`／`log3.txt`〕直接佐證，其餘尚未驗證）：**

0.（**目前信心最高，有真機 log 直接佐證，非純理論，第二輪驗證已鎖定確切機制**）**`epic-18` Issue 47 攔截器的監聽器缺少 `passive: false`，導致其 `preventDefault()` 從未真正生效過，誘發瀏覽器原生捲動接管手勢，與選取狀態本身無關**：

   第一輪真機 log（`log.txt`）顯示，插樁只留下 1 筆 `rangeCount=1 isCollapsed=true moved=false` 之後，立刻出現連續瀏覽器原生錯誤：「Ignored attempt to cancel a touchmove event with cancelable=false...scrolling is in progress and cannot be interrupted」。第一輪修法：在 Issue 47 攔截器 `stopImmediatePropagation()` 前補上 `evt.preventDefault()`。

   **第二輪真機測試（`log2.txt`／`log3.txt`，同一支修改過的 debug build）證實第一輪修法未生效**——新出現一行更早的錯誤：「Unable to preventDefault inside passive event listener due to target being treated as passive」，且使用者回報「亂跳依舊發生」「手指在書籍上任意滑動、只要不停留太久不出現畫線工具就會出現 ERROR」「一旦出現畫線工具就不會有 ERROR」。查證確認：Issue 47 攔截器的 `touchmove` 監聽器註冊時只給了 `{ capture: true }`，**沒有明確指定 `passive`**。Chromium 對直接掛在 `Document` 物件（`doc` 正是 iframe 的 `contentDocument`）上、沒有明確指定 `passive` 的 `touchstart`/`touchmove` 監聽器，預設會被當成 passive 處理（效能最佳化），passive 監聽器內呼叫 `preventDefault()` 一律被靜默忽略（只印警告，不拋例外）——第一輪加的 `preventDefault()` 呼叫本身就在這個被隱性判定為 passive 的監聽器裡，從未真正生效過。這代表 Issue 47 從最初合併以來，攔截器本身就從來沒有能力真正取消 touchmove 的預設行為，只是先前沒有真機資料能觀察到這一層。

   完整成因鏈：任何手勢最初幾個 `touchmove`，若 Issue 47 攔截器判定為候選並呼叫 `stopImmediatePropagation()`（讓 `paginator.js:2198` 的 `preventDefault()` 沒機會執行）、而攔截器自己想呼叫的 `preventDefault()` 又因為 passive 而被忽略 → 全程沒有任何一方成功取消這幾個 touchmove → Chromium 判定「沒人要攔」，自行接管為原生捲動，該手勢剩餘所有 touchmove 標記為不可取消，之後不論 `paginator.js` 或攔截器再怎麼呼叫 `preventDefault()` 都被忽略 → 畫面位移由瀏覽器合成器直接控制，完全繞過 `paginator.js` 自己的 `#touchState`/`containerPosition` 追蹤（插樁量到的 `containerPosition` 因此全程不變、`moved=false`，但畫面實際可能正被原生捲動亂拖）。這解釋了使用者的三項觀察：(1) 任意滑動只要沒觸發選字就會出現 ERROR——因為幾乎任何手勢的最初幾格都會落入 Issue 47 的候選窗口；(2) 一旦選字工具出現就不再有 ERROR——**修正**：不是攔截器放手後 `paginator.js` 成功呼叫 `preventDefault()`，而是 `paginator.js:2193-2195`（`if (selection && rangeCount>0 && !isCollapsed) return`）本身在選取已確立時就提早返回，根本不會執行到 2198 行的 `preventDefault()`，自然不會拋出取消失敗的錯誤（見 `tmp/epic-25/issue-1-cause-and-solution-analysis.md` 2.4 節，查證後採納，比原敘述精確）；(3) 不是每次都重現——是否踩到「候選窗口內完全沒有成功取消」取決於手勢時序的細節。**這與選取是否已確立無關，是 `epic-18` Issue 47 修復本身自合併以來就存在、只是先前未被真機資料揭露的缺陷**，不是獨立於 Issue 47 之外的裝置差異 bug。

   **第二輪修法（`main.js`，`epic-25-issue-1-debug-instrumentation` 分支）**：Issue 47 攔截器的 `touchmove` 監聽器註冊選項改為 `{ capture: true, passive: false }`，讓 `evt.preventDefault()` 真正生效。**待真機第三輪驗證**。

   **外部分析報告交叉驗證**（`tmp/epic-25/issue-1-cause-and-solution-analysis.md`，人類提供）：獨立分析同一組 log，收斂到完全相同的根因與修法（其方案 A＝上述第二輪修法，判定「推薦、符合 ADR 0011」），提高本假說信心。逐項技術評估：
   - 採納：2.4 節 `paginator.js` 早退細節（已併入上方成因鏈說明）。
   - 不採納，理由已查證：方案 A 一併建議 `touchstart` 監聽器與診斷插樁的 `touchmove` 監聽器都加 `passive: false`——查證這兩處皆未呼叫 `preventDefault()`，加上不會改變任何行為，維持最小改動、只改真正需要的地方（`epic-18` Issue 47 攔截器的 `touchmove` 監聽器）。
   - 明確駁回：方案 C（修改 `paginator.js` 加 `e.cancelable` 判斷）違反 ADR 0011（不可修改 vendored 檔案），報告本身也承認且僅列為參考，不採用。
   - 記錄為備援選項、暫不實作：方案 B（注入 `touch-action` CSS 限制原生手勢方向）——報告定位為「輔助防護」非必要；`passive: false` 已精準對應已確認機制，**若第三輪真機驗證後發現 `passive: false` 單獨不足以解決亂跳，才評估加上**，避免在還沒有證據顯示必要之前，先做影響範圍更廣（可能牽動縮放等其他手勢）的改動。

0.5（**第三輪真機驗證新發現，機制尚未確認、兩個子假說待下一輪資料區辨**）**`passive: false` 已確認解決 ERROR，但跳頁仍會發生，且僅限畫面右側三行（直排模式，對應九宮格右欄熱區）**：

   `log4.txt`／`log5.txt`／`log6.txt` 三份 log 皆**完全沒有**再出現 `Unable to preventDefault...`／`Ignored attempt to cancel...` 兩則錯誤，確認假說 0 的修法本身有效。但使用者回報跳頁仍會發生，且明確定位在畫面右側三行。

   人類提供第二份外部分析報告（`tmp/epic-25/issue-1-right-three-lines-jump-analysis.md`）提出假說：`longPressGate` 因水平飄移超過 15px 死區提早放行，`paginator.js` 誤判為翻頁手勢暴跳一整頁。**查證後對其具體機制描述持保留態度**：報告引用 `log5.txt` 兩行（`t=25215`/`t=27444`，間隔 2.2 秒）論證「單一手勢內 95px 飄移造成暴跳」，但兩行皆明確標示 `moved=false`——若真是同一手勢內位置真的跳動，第二行理應是 `moved=true`；間隔 2.2 秒也不像是連續同一手勢。更可能是兩次分開的手勢（`debugE25I1LastPosition` 在每次 `touchstart` 重置為 `null`，故各自的「該手勢第一筆」都會被記錄、且必為 `moved=false`），中間的位置落差是被某個插樁完全觀察不到的機制造成的。報告描述的「距離死區 15px 就放行、卻累積到 95px 才暴跳」，也與目前雙門檻設計（距離 >15px **或**速度 >0.3px/ms **或** 耗時 ≥500ms，任一成立即放行，飄移一超過 15px 就會提早放行，不會拖到 95px）不完全吻合，較像是描述修復前的舊版邏輯。

   目前兩個未區辨的子假說：
   - **(a)** 攔截器放行後，`paginator.js` 接手這次移動，`touchend` 時被其自身合法的 `snap()` 判定為一次真實翻頁手勢並提交（不是攔截器的 bug，是放行後的正常後果被使用者感知為非預期跳頁）。
   - **(b)**（上一輪已提出）`foliate_epub_reader_view.dart:827-868` 的 `_NavZoneTapDetector`（九宮格翻頁熱區，`Listener` 不參與手勢競技場，與 WebView 同時收到同一組觸控）用「耗時 ≤400ms 且位移 ≤18px」判定「快速點擊」觸發翻頁——若長按選字的按壓在被 WebView 判定為長按之前就意外提早放開/中斷，落在右欄熱區範圍內就可能被誤判成翻頁點擊，與 JS `touchmove`/`preventDefault` 完全無關，插樁本來就看不到。

   **本輪新增插樁（`main.js`／`foliate_epub_reader_view.dart`，`epic-25-issue-1-debug-instrumentation` 分支）供下一輪真機測試區辨**：
   - `[DEBUG-e25i1-gate]`：記錄 Issue 47 攔截器放行時機與原因（`selection-established`／`elapsed`／`distance`／`velocity`）、放行當下的 dx/dy/距離/速度/`containerPosition`。
   - `[DEBUG-e25i1-end]`：記錄 `touchend` 當下與 +350ms 後（涵蓋一般 `snap()` CSS transition 的 settle 時間）的 `containerPosition`，捕捉子假說 (a)「放開手指後才透過動畫完成的整頁跳動」。
   - `[DEBUG-e25i1-navzone]`：於 `_NavZoneTapDetector` 的 `onTap` 呼叫點記錄觸發的熱區編號與動作，直接證實/排除子假說 (b)。

   **判讀方式**：若跳頁時 log 出現 `[DEBUG-e25i1-navzone]`，代表子假說 (b) 成立；若出現 `[DEBUG-e25i1-gate] released reason=distance/velocity` 後緊接著 `[DEBUG-e25i1-end]` 顯示 +350ms 位置與 touchend 當下差了一整頁，代表子假說 (a) 成立；兩者也可能並存。

0.6（**第四輪真機資料〔`log7.txt`／`log8.txt`／`log9.txt`／`log10_OK.txt`〕已直接證實，子假說 (b) 成立、(a) 已排除**）**「右邊三行」跳頁的確切根因是 `_NavZoneTapDetector` 九宮格熱區誤判，與 Issue 47／`passive: false` 完全無關**：

   決定性證據（`log9.txt` 第 14-18 行）：
   ```
   [DEBUG-e25i1] rangeCount=1 isCollapsed=false ...           選取已成功確立
   [DEBUG-e25i1-gate] released reason=selection-established   Issue 47 攔截器正確放手
   [DEBUG-e25i1-navzone] zone=3 action=ZoneAction.nextPage    但九宮格熱區同時判定成快速點擊
   [DEBUG-e25i1-end] touchend→+350ms delta=714.97              頁面跳了整整一頁
   ```
   `log7`／`log8`／`log9` 三份「有跳頁」的 log，每一次跳頁都精準對應到一筆 `[DEBUG-e25i1-navzone]`，跳動量固定 `±714.97px`（一整頁）；log 中唯一一筆 `[DEBUG-e25i1-gate] released reason=elapsed`（距離僅 10.1px）前後 `containerPosition` 完全沒變——子假說 (a)（攔截器放行後 `paginator.js` 誤判翻頁）在這幾次重現中未曾發生。

   **根因**：`_NavZoneTapDetector`（`foliate_epub_reader_view.dart:827-868`）刻意用 `Listener` 不加入手勢競技場（既有設計，避免攔截 WebView 的原生長按選字），純粹依「耗時 ≤400ms 且位移 ≤18px」判定是否為翻頁點擊，**完全不知道同一次觸控是否同時讓 WebView 建立了文字選取**。人類提供的第三份分析報告（`tmp/epic-25/issue-1-navzone-tap-jump-analysis.md`）獨立收斂到同一根因，但兩處細節查證後有誤，已訂正：(1) zone index 與實體位置對應反了（`index = row*3+col`，zone=3 是中欄靠左非右欄，查證目前使用的是 `leftFlipZoneTemplate` 非報告假設的 `rightFlipZoneTemplate`，不影響核心結論）；(2)「WebView 贏得手勢競技場、Flutter Tap 被取消」的解釋是錯的且被 `log9.txt` 直接證據推翻——`_NavZoneTapDetector` 從未加入競技場，選取確立與否不影響它的獨立判定，兩者是各自判讀同一組觸控事件的平行路徑。

   **修法（`foliate_epub_reader_view.dart`，`epic-25-issue-1-debug-instrumentation` 分支）**：`_FoliateEpubReaderViewState` 新增內部欄位 `_hasActiveSelection`，由既有 `onSelectionChanged`/`onSelectionCleared` JS 橋接 handler 直接維護（不透過 `setState`，只在觸控放開當下被讀取一次）；九宮格熱區 `onTap` 判定要觸發翻頁前，先檢查此欄位，若有選取範圍存在則抑制（不呼叫 `widget.onZoneAction`），並保留 `[DEBUG-e25i1-navzone]` log 標註 `suppressed=true/false` 供下一輪驗證。

   **第四輪真機驗證（`log11.txt`／`log12.txt`）：機制有效但覆蓋不足**——`log11.txt` 第 20-22 行確認 `suppressed=true` 時 100% 擋下跳頁，但兩份 log 裡多數造成跳頁的 `[DEBUG-e25i1-navzone]` 之前完全沒有出現任何 `[DEBUG-e25i1]`/`[DEBUG-e25i1-gate]`，代表那幾次觸控從按下到放開，WebView 端根本還沒來得及建立選取（`_hasActiveSelection` 全程是 `false`，沒有東西可以擋）。查明結構性根因：`_NavZoneTapDetector` 判定「快速點擊」的門檻是 400ms，但原生長按辨識（Android `ViewConfiguration.getLongPressTimeout()`，與 `epic-18` Issue 47 `LONG_PRESS_GATE_MS` 同值）需要 500ms 才會開始——任何按壓在 400ms 內放開，熱區永遠搶在原生選取有機會開始之前就裁定成翻頁點擊，與選取有沒有成立無關。

   人類提供第四份報告（`tmp/epic-25/issue-1-navzone-suppression-architecture-study.md`）評估三個方向，逐一查證：
   - **方案 A**（選字工具跳出後才停用熱區）：時機抓太晚，救不到上述空窗期，報告自己也給了最低評分。
   - **方案 B-1**（`touchstart` 立即鎖定、`touchend` 後 50ms 視情況解鎖）：查證後發現報告畫的狀態機**缺了「解鎖後要補發原本那次點擊動作」這一步**，字面實作會讓熱區整個失效（任何點擊都在 touchend 當下鎖定狀態仍是 true）；即使補上，50ms 這個非同步等待窗口也只能處理「選取其實已成立、只是橋接還沒傳到」的極端邊界情況，處理不了本輪 log 顯示的主要情境（按壓本身就短於原生辨識所需的 500ms，事後等多久都不會生出選取）。
   - **方案 B-2**（按壓時間門檻調整）：完全同步、無競速風險，方向正確，但報告給的 150ms 數字會讓使用者自然稍慢的點擊（尤其 E-Ink 裝置）也失效，屬於用一個新的回歸換掉原本的 bug，需要往另一個方向（提高而非降低）校準。

   **採用修法**：`_NavZoneTapDetector._tapMaxDurationMs` 從 400ms 提高到 **500ms**，對齊原生長按辨識門檻與 Issue 47 `LONG_PRESS_GATE_MS` 同一個值——任何有機會演變成長按選字的按壓，一開始就不會被判定為快速點擊，不需要額外等待或跨 JS/Dart 橋接判斷，與既有 `_hasActiveSelection` 抑制（保護選取已確立後續拖曳控點等情境）互補疊加。**已知限制（誠實記錄，非過度承諾）**：不是 100% 保證——若某次按壓落在 400-500ms 之間、但實際裝置辨識長按所需時間比 500ms 更久，理論上仍有機會漏網；500ms 是有依據的起始值，非憑空選定，若真機重測仍偶發重現，下一輪需視真機數據調整至 550-600ms 區間。PDF 端 `_PdfNavZoneTapDetector`（`pdf_reader_view.dart:1208-1240`）是獨立實作、同樣的結構性落差可能也存在，但 PDF 選字機制（Dart `GestureDetector` 長按拖曳框選）與 EPUB（WebView 原生選取）不同，本輪不動，需要的話應另立 Issue 查證。

   **第五輪真機驗證（`log13.txt`）：有改善但仍會發生，門檻進一步調整至 700ms**——使用者回報「仍會發生，不過有改善」「熱區不會感覺變慢」。`log13.txt` 比對前幾輪，`suppressed=true`（成功擋下）的比例明顯提高，證實 500ms 調整方向正確、有實質效果，但仍有相當比例的 `suppressed=false` 造成跳頁；第 9 行 `[DEBUG-e25i1-gate] released reason=distance t=3389 elapsed=497` 顯示部分候選手勢撐到 elapsed≈497ms 才因距離門檻（非選取確立）放行，代表真機實際判定所需時間比 Android 預設的 500ms 更貼近甚至可能略超過——500ms 仍不夠寬裕。使用者主動確認「提高門檻不會讓一般翻頁點擊感覺變慢」，代表目前的體感延遲仍有餘裕，可以再往上調。採用使用者建議的調整幅度（+100~200ms），選定區間上緣 **700ms**（`_tapMaxDurationMs` 500→700），保留較大安全邊際、減少需要再次真機來回調校的次數。**待真機第六輪驗證**：確認選取存在時不再跳頁，且正常翻頁/選單熱區（無選取時）功能不受影響、體感未明顯變慢。若 700ms 仍不足或使用者開始感覺翻頁有感延遲，才需要在「跳頁機率」與「翻頁即時感」之間做更精細的取捨（例如回到方案 B-1／借用 Issue 47 gate 狀態的非同步方案，用短暫等待換取不必要拉長所有點擊的判定門檻）。

   **已知測試覆蓋缺口**：`flutter test` 的 `FakeInAppWebViewPlatform`（`app/test/support/fake_inappwebview_platform.dart`）不會真正建立 `InAppWebViewController`，`controller.addJavaScriptHandler(...)` 註冊的 handler（含 `onSelectionChanged`/`onSelectionCleared`）在 widget test 環境下無法被觸發，故 `_hasActiveSelection` 這個內部狀態追蹤邏輯目前無法在 `flutter test` 層級寫自動化回歸測試（`reader_screen_test.dart` 既有的 `foliateView.onSelectionChanged?.call(...)` 測試手法是從外部直接呼叫 widget 的 public callback，繞過了 JS handler 內部、不會經過 `_hasActiveSelection` 賦值）——這是既有測試基礎設施的既有限制，不是本次修法引入的缺口；驗證只能依賴真機（比照本專案兩層測試架構文件，JS 橋接觸發的行為本來就歸類到 `integration_test`/真機驗證範疇）。既有 `flutter test`（`foliate_epub_reader_view_test.dart` 64/64，含既有 3×3 導航熱區測試確認未回歸）與 `flutter analyze` 皆通過。
1. 視覺選取控點顯示與 `doc.getSelection()` 的 `rangeCount`/`isCollapsed` JS 狀態同步之間，在該機型 WebView 有時間落差——與 Issue 47 根因同一類「JS 選取 API 落後於原生手勢視覺狀態」問題，只是發生在拖曳控點階段而非長按候選階段。
2. Air Reader Pro C 的 WebView 版本／觸控事件合併（coalesced events）行為與 TCL 14 吋不同（比照 `epic-18` Issue 33／38-41 已知部分機型 WebView 版本偏舊的既有模式）。
3. 兩者疊加。
4.（`plan-issue-1.md` 實作審查新增，`tmp/epic-25/review-issue-1-implementation.md`——架構層級假說，目前無法用 headless CDP 驗證或否證，優先度已因假說 0 的確切機制查明而降低）**原生選取控點的拖曳，很可能根本不會產生 DOM `touchmove` 事件**：Android WebView／Chromium 對「已顯示的文字選取控點」的拖曳，慣例是由瀏覽器 UI／合成器層級（`TouchSelectionController` 一類原生元件）直接處理，不一定會被送進頁面的 DOM 事件派發流程。**若假說 0 的 `passive: false` 修法在下一輪真機驗證後仍未解決跳頁，才需要回頭認真評估這個假說**，需要換一種完全不依賴 DOM touch 事件的偵測方式（例如原生 Android 端用 `WebView` 的捲動變化監聽機制，或改用 `requestAnimationFrame` 輪詢取代事件驅動）。

**下一步：** 已在 `epic-25-issue-1-debug-instrumentation` 分支修正 Issue 47 攔截器的監聽器選項（`{ capture: true, passive: false }`），待使用者重新 build debug APK 裝到 Air Reader Pro C 上第三輪測試（同一台裝置反覆多測幾次，包含「任意滑動不觸發選字」與「長按選字後拖曳控點」兩種情境）。驗證重點：(a) `Unable to preventDefault inside passive event listener` 與 `Ignored attempt to cancel a touchmove event with cancelable=false` 兩則瀏覽器原生錯誤是否不再出現；(b) 任意滑動與拖曳選取控點是否都不再跳頁。若第三輪確認有效，可規劃將 `passive: false` 這項修正正式併入 `epic-18` Issue 47 的既有修復；若仍重現，回頭比對假說 1-4。無法用 headless CDP 模擬選取控點拖曳（不具代表性，與 Issue 47 診斷時發現的局限相同）。

**真機資料蒐集步驟（`plan-issue-1.md` Task 1 完成後可執行）：**

1. 用含 `[DEBUG-e25i1]` 插樁的 debug build（`flutter build apk --debug`）分別安裝到
   Air Reader Pro C 與 TCL 14 吋兩台裝置。
2. 兩台裝置分別開啟同一本流式 EPUB（建議用同一本書、同一個章節位置，降低
   非裝置因素造成的差異）。
3. 長按選取一段文字（例如 5-10 個字），確認選取控點已顯示於左右兩側
   （即選取已確立的狀態）。
4. 用手指拖曳其中一個控點，同時留意畫面是否出現跳頁/位移。**請至少各嘗試
   一次「緩慢」與「明顯較快」兩種拖曳速度**（`plan-issue-1.md` 實作審查
   `tmp/epic-25/review-issue-1-implementation.md` 發現：headless 環境下
   緩慢小幅度的 touchmove 序列，有機率完全不被瀏覽器派發到 JS 層級，只測
   單一慢速手勢可能系統性地採不到任何資料），並在回報時註記每次操作的
   拖曳速度主觀感受。
5. 完成拖曳後，進入「設定」→「閱讀器 Console Log」，點擊右上角「複製全部」
   按鈕，將剪貼簿內容貼到文字檔或直接回報；同步註記該次測試使用的版面
   設定（直排/橫排、單頁/雙頁），以利後續交叉分析是否為版面相關變因。
6. 兩台裝置各重複步驟 3-5 至少 2 次（同一手勢多測幾次，避免單次操作的
   偶然性），並记錄「當下是否有觀察到跳頁」對應到哪一次操作。
7. 將兩台裝置的 log 檔案／文字回報回來，交叉比對 `rangeCount`／
   `isCollapsed`／`containerPosition`／`moved` 欄位在兩台裝置上的差異
   （特別留意 `moved=true` 但 `rangeCount>0 && isCollapsed=false`
   同時成立的行——這代表「選取明明已確立，內容卻仍位移」，是本 Issue
   要鎖定的確切症狀）。

**下一輪（拿到真機資料後）**：依比對結果撰寫 `bugfix-repro-issue-1.md`
確認根因，另立修復計畫；本插樁需在修復計畫的 Cleanup 階段整段移除
（`grep -rn "DEBUG-e25i1"` 確認清除乾淨）。

---

## Issue 2：畫線工具列在螢幕右側被裁切看不全

**Status:** ✅ 已修復並合併回 `main`（PR #135，分支 `epic-25-issue-2`）。實作計畫（`plans/plan-issue-2.md`）與實作結果皆經 `/superpowers:requesting-code-review` 獨立審查，兩輪皆 0 Critical／0 Important（各僅出現風格層級 Minor，不影響合併，詳見 `tmp/epic-25/plan-issue-2-review.md`／`tmp/epic-25/review-issue-2-implementation.md`）。`reader_screen_test.dart` 新增 2 則 widget test（EPUB／PDF 各一）以 `tester.getBottomRight(find.byType(AnnotationToolbar))` 直接量測渲染座標驗證修法前後精確像素值（636.0→400.0），既有選取相關測試零回歸，145/145 全數通過、`flutter analyze` 乾淨。

**依賴：** 無

**背景：** 使用者回報並附截圖（`tmp/images/畫線問題/畫線太右邊無法看到全部工具列.jpg`）：畫線位置偏螢幕右側時，浮動工具列（`AnnotationToolbar`，5 顆按鈕：3 色螢光筆＋底線＋備註）被裁切，只看得到最左邊一小塊圓角＋圖示，其餘超出螢幕右緣。

**根因：** `reader_screen.dart:1970-1989`。垂直位置 `_annotationToolbarTop()`（`reader_screen.dart:1656-1662`）已正確扣除工具列自身高度再 clamp（`belowSelection.clamp(0.0, size.height - _annotationToolbarHeight)`），但水平位置：

```dart
left: (selection.rect.left * size.width).clamp(0.0, size.width),
```

只鎖住起點不小於 0、不大於畫面寬度，**完全沒有扣除工具列自身寬度**——起點一旦接近右邊界，工具列本體就會整個超出螢幕右側。EPUB（`reader_screen.dart:1972`）與 PDF（`reader_screen.dart:1983`）兩條路徑同構，皆有此問題。

**修法：** 比照既有 `_annotationToolbarHeight = 56.0`／`_annotationToolbarGap = 8.0`（`reader_screen.dart:1647-1648`）常數宣告模式，新增 `_annotationToolbarWidth` 常數（`AnnotationToolbar` 為 `Row(mainAxisSize: MainAxisSize.min)` 5 顆 `IconButton`＋左右各 8px padding，實際渲染寬度需在真機/widget test 量測後定案，不可憑空假設數值），`left` 也比照 `top` 的寫法：

```dart
left: (selection.rect.left * size.width).clamp(0.0, size.width - _annotationToolbarWidth),
```

EPUB／PDF 兩處呼叫端皆須修正。

**單元測試要求：**
- widget test：模擬選取範圍 `rect.left` 接近 1.0（螢幕右緣）時，`AnnotationToolbar` 的 `left` 不超過 `size.width - _annotationToolbarWidth`，整個工具列的 `getBottomRight()` 在畫面寬度範圍內（可用 `tester.getBottomRight(find.byType(AnnotationToolbar))` 驗證）。
- 涵蓋 EPUB／PDF 兩條路徑。
- 既有正常位置（工具列不需 clamp）情境不受影響，回歸測試維持通過。

**驗收標準：** 上述測試通過、`flutter analyze` 乾淨；真機或等效螢幕尺寸模擬下，畫線位於螢幕最右側時工具列完整可見可點擊。

---

## Issue 3：選擇畫線樣式後應可主動關閉工具列

**Status:** ✅ 已修復並合併回 `main`（PR #136，分支 `epic-25-issue-3`）。`AnnotationToolbar` 新增第 6 顆「✕ 關閉」按鈕（`onClosePressed` 必要參數）；EPUB 端另新增 `window.clearSelection()` JS 橋接，關閉工具列時一併清除 WebView 原生文字選取（藍色反白＋拖曳控點），PDF 端經查證（`_finishSelectionDrag()` 已在回報選取矩形前清空唯一的視覺疊加層）確認不需要對應處理。實作過程中規劃階段實測發現並同步修正一個連鎖問題：新增第 6 顆按鈕使 `AnnotationToolbar` 實際渲染寬度從 256.0（5 顆）變為 304.0（6 顆），Issue 2 的 `_annotationToolbarWidth` 常數一併更新，避免右緣裁切修法回歸。實作計畫與實作結果皆經 `/superpowers:requesting-code-review` 獨立審查，0 Critical／0 Important（僅 1 項 Minor，純風格不影響合併，詳見 `tmp/epic-25/review-issue-3-implementation.md`）。`reader_screen_test.dart` 147/147、`annotation_toolbar_test.dart` 7/7 全數通過（含 Issue 2 右緣裁切回歸與「選色後保持開啟」回歸），`flutter analyze`／`node --check main.js` 皆乾淨。**已知殘留限制**：`window.clearSelection()` 的 JS 呼叫效果無法在 `flutter_test` 環境下自動化驗證（既有測試基礎設施限制），實際清除效果待真機人工驗證。

**依賴：** 無

**背景：** 使用者回報：選擇完畫線樣式（顏色/底線）後，工具列應自動隱藏，或提供一個明確按鈕可主動關閉——目前只能透過點擊換頁間接關閉。

**既有設計限制：** `_handleHighlightStyleSelected()`（`reader_screen.dart:1176`）刻意在建立劃線後不清空 `_currentSelection`，用意是讓使用者能緊接著點「備註」把新備註連結到剛建立的劃線（既定的「劃線+備註共存」使用者流程，`design.md` 沿用自 `epic-6-annotations`）。若選色後自動關閉整個工具列，會破壞這個既有連續流程。

**人類決定採用方向 (a)：** 保留現有連續流程（選色後工具列預設仍打開、備註仍可接續點擊建立備註），額外新增一顆明確的「✕ 關閉」按鈕於 `AnnotationToolbar` 內，讓使用者可以主動關閉工具列（清空 `_currentSelection`／`_currentPdfSelection`）而不必依賴點擊換頁間接觸發。

**修法方向：**
- `AnnotationToolbar`（`annotation_toolbar.dart`）新增第 6 顆按鈕（`Key('annotation_toolbar_close')`，`Icons.close`），新增 `onClosePressed` 必要參數。
- EPUB／PDF 兩處呼叫端（`reader_screen.dart:1974-1977`／`1985-1988`）的 `onClosePressed` 分別呼叫 `_handleSelectionCleared()`／`_handlePdfSelectionCanceled()`（既有方法，見 `reader_screen.dart:1152`／`1168`）。
- 是否需要同步清除 WebView／PDF 端的原生選取狀態（例如呼叫 JS `window.getSelection().removeAllRanges()`）待 Planning 階段查證是否會造成使用者主動關閉工具列後，原生選取控點仍殘留畫面的不一致體驗。

**單元測試要求：**
- widget test：`AnnotationToolbar` 新增 `Key('annotation_toolbar_close')` 存在且可點擊，點擊後 `onClosePressed` 被呼叫。
- `reader_screen_test.dart`：選取存在時點擊關閉按鈕後，`_currentSelection`／`_currentPdfSelection` 變為 `null`、工具列從畫面消失（`find.byType(AnnotationToolbar)` findsNothing）。
- 既有「選色後工具列保持開啟、可接續點擊備註」流程需有回歸測試保護，確認本次修改沒有連帶破壞。

**驗收標準：** 上述測試通過、`flutter analyze` 乾淨；真機驗證選色後可點擊新按鈕主動關閉工具列，且不影響既有「選色→備註」連續流程。

---

## Issue 4：換頁點擊位置與相鄰頁畫線重疊時，誤跳出刪除確認對話框

**Status:** ✅ 已修復。真機資料（`tmp/epic-25/log-issue4/`，六份 log：`壓到-1/2/3.txt`／`沒壓到.txt`／`明顯不重疊-1/2.txt`）證實根因與原始假說不同——`click` 事件命中畫線的時序有時早於、有時晚於 `window.nextPage()` 實際執行，兩種順序都會誤觸發，純時序競速修法無法涵蓋；本質是「換頁點擊」與「畫線點擊」共用同一組觸控手勢、同一螢幕座標的產品層級語意衝突，不是單純的競速 bug。採用人類確認的產品方向（按壓時長判斷意圖，快速點擊優先視為換頁）修復，`main.js` 新增 capture 階段 `touchstart`/`click` 監聽器，700ms 內攔截 click 傳給畫線點擊監聽器的機會（明確排除超連結點擊，避免連帶回歸）。headless 驗證三種情境（短按攔截／長按放行／超連結不受影響）皆 PASS。**已知殘留限制**：真機上「長按原地放開是否仍合成 click 事件」未經驗證（headless 已確認會，真機 WebView 行為可能不同），需真機驗證「長按查看/編輯既有畫線」這條路徑是否如預期運作。

**依賴：** 無

**背景：** 使用者回報並附兩張連續截圖（`tmp/images/畫線問題/2-1...jpg`、`2-2...jpg`）：點擊換頁的位置，若剛好與上一頁或下一頁「同一螢幕座標」處有畫線重疊，換頁後會立刻誤跳出「是否刪除畫線」的確認對話框（`_showAnnotationActionDialog`，`reader_screen.dart:1309`）。

**根因假說（原始碼層級，信心中高，未經 headless/真機驗證確認確切時序）：**

vendored `view.js:438-445`：

```javascript
doc.addEventListener('click', e => {
    const [value, range, rect] = overlayer.hitTest(e)
    if (value && !value.startsWith(SEARCH_PREFIX)) {
        this.#emit('show-annotation', { value, index, range, rect })
    }
}, false)
```

`Overlayer` 用**原生 `click` 事件**做畫線點擊偵測，而 `paginator.js` 的換頁是自己的 `touchstart`/`touchmove`/`touchend` 手勢邏輯驅動、在 `touchend` 當下就立即完成視覺換頁。瀏覽器的合成 `click` 事件在觸控裝置上是 `touchend` **之後才延遲觸發**的相容性事件——這時頁面視覺上已經換到新頁，`click` 事件座標卻拿去對「新頁面此刻的內容」做 `hitTest()`，如果新頁同一螢幕座標剛好也有畫線，就誤判成「使用者點擊了這筆畫線」而彈出刪除確認。與 `epic-18` Issue 47 是同一類「vendored 觸控換頁邏輯 vs 瀏覽器原生延遲事件」的競速問題，但這次競速的對象是 `click` 而非 `touchmove`。

**真機資料分析與修訂根因（`tmp/epic-25/log-issue4/`，六份 log，`plan-issue-4-fix.md`）：**

真機插樁資料（`plan-issue-4-realdevice-diagnostics.md` 產出）交叉比對後，發現原始假說（`click` 恆常晚於換頁動作、命中新頁內容）**不成立**：

- `壓到-1.txt:15-19`：`show-annotation`（t=636932）發生在 `window.nextPage() called`（t=636933）**之前**——換頁動作根本還沒執行，click 已命中畫面上現有的畫線。
- `壓到-1.txt:56-64`：`window.nextPage() called`（t=653673）在 `click`（t=653678）**之前**，中間差 5ms——這次換頁動作先執行。

兩種相反的時序，皆誤觸發**同一筆畫線**（`highlight:10d0a3b5-5d4a-44ec-b1d5-1b4e9eaf5708`）。這代表問題不是「click 打中換頁後的新內容」這種時序競速，而是：**點擊座標剛好落在畫面上（換頁前或換頁後皆可能）某個位置的畫線，vendored `view.js` 的原生 `click` 監聽器就會 hitTest 命中、跳出對話框**，與換頁動作的執行時機無關。

`沒壓到.txt`（人類原始標記「重疊但沒跳出對話框」）交叉核對後，同樣有 2 次 `show-annotation` 正確觸發（`highlight:f31a9173-...`／`highlight:c34dcde0-...`）——人類確認這份 log 錄製時「點擊很快，可能沒注意到」，故此標記不可靠，予以排除，改採信 log 本身（視為真實誤觸發，與「壓到」系列一致）。`明顯不重疊-1.txt`／`明顯不重疊-2.txt` 則完全零 `show-annotation` 觸發，與「明顯不重疊、不會跳出對話框」的標記完全吻合，佐證插樁資料本身可信。

綜合六次真實誤觸發（`壓到-1`×2、`壓到-2`×2、`壓到-3`×1、`沒壓到`×2，扣除重複計算後共 6 次不同時間點的觸發）與零假陽性（`明顯不重疊`×2）的資料，確認根因是**產品層級的手勢語意衝突**：3×3 換頁熱區點擊與「點擊既有畫線查看/編輯」共用同一種手勢（快速點擊）、可能落在同一螢幕座標，技術上沒有任何訊號能區分使用者意圖。

**人類確認的產品方向**：以按壓時長作為判斷依據——「通常要處理畫線手指都會壓比較久，如果是快速點擊就是要換頁」。快速點擊（≤700ms，比照既有 `_NavZoneTapDetector._tapMaxDurationMs`）優先視為換頁意圖，攔截畫線點擊對話框；按壓夠久則視為使用者確實想操作畫線，正常顯示對話框。修法內容見 `plan-issue-4-fix.md`。

**規劃階段查證（`plan-issue-4.md`，修正原始假說對「點擊換頁」情境的適用範圍）：**

`paginator.js` 原始碼查證（`grep -n "#onTouchStart\|#onClick\|addEventListener('click'\|tap" paginator.js`）確認**沒有任何自己的 tap-to-turn-page click/短按處理**，只有 `touchmove` 驅動的拖曳換頁邏輯。原始假說引用的「`paginator.js` 的換頁是自己的 touchstart/touchmove/touchend 手勢邏輯驅動」精確地說只適用於**滑動換頁**，本專案「點擊換頁」（nav-zone 熱區點擊，即使用者截圖檔名描述的情境）完全是 Flutter 端 `_NavZoneTapDetector` 收到觸控後呼叫 `evaluateJavascript('window.nextPage()')` 實現，與 `paginator.js` 自己的觸控邏輯是兩條獨立路徑（比照 Epic 25 Issue 1 已確立的「Flutter Listener 與 WebView 平行接收同一組觸控、互不阻擋」事實）。

**headless CDP 時序驗證迴圈結果（`tmp/epic-25-issue-4-harness/repro.mjs`，20 次重複量測）：**

模擬「CDP 觸控注入 touchstart/touchend＋緊接著呼叫 `window.nextPage()`」這條路徑（代表 Flutter nav-zone 點擊觸發換頁的最快可能情境——headless `page.evaluate()` 往返延遲，理論上比真機 Flutter→原生橋接→WebView 的實際 IPC 鏈路更短，不會更長），控制組（無換頁介入，單純點擊）正確命中舊頁劃線，證實劃線/座標設置本身無誤；但正式競速測試 **20 次全數命中舊頁內容、0 次重現 Issue 4 症狀**（原生 `click` 合成事件平均只比 `touchend` 晚約 1.5ms 觸發，快於 `page.evaluate()` 往返本身的延遲）。

**解讀（誠實記錄，非下定論）**：此負向結果**不能排除**本假說在真機上成立——有兩種可能同時存在：(a) 若 headless `page.evaluate()` 的往返延遲已經是這條路徑能達到的下限，而真機 Flutter 原生橋接（Dart 事件迴圈→MethodChannel/JS 橋接→Android WebView `evaluateJavascript()`）的實際 IPC 鏈路必然更長，則競速只會更難獲勝，這條假說的可信度應該**下修**；(b) 但也可能是 headless Chromium 的原生 touch-to-click 合成時序特性，與真機 Android System WebView 本身有實質差異（不同瀏覽器引擎組建、不同原生事件合成管線）——這正是 Epic 25 Issue 1 已記錄過的同一類「headless CDP 無法代表真機 WebView 差異」既有限制（Issue 1 是「無法模擬選取控點拖曳」，本次是「觸控轉合成 click 的時序特性未必一致」）。兩者目前無法用 headless 環境本身區辨。

**下一步：**（已完成，見上方「真機資料分析與修訂根因」與 `plan-issue-4-fix.md`）

1. ~~用 Puppeteer + headless Chromium＋CDP `Input.dispatchTouchEvent` 建立可重跑的重現迴圈~~——實際改走真機診斷插樁路線（`plan-issue-4-realdevice-diagnostics.md`）直接取得真實時序資料，取代原規劃的 headless 重現迴圈（該路線 20 次量測 0 次重現，見上方「headless CDP 時序驗證迴圈結果」）。
2. ~~依實測時序再定案修法方向~~——已依真機資料定案：按壓時長判斷意圖（700ms 門檻），見上方「人類確認的產品方向」與 `plan-issue-4-fix.md`。
3. ~~確認修法不影響「正常點擊畫線開啟編輯/刪除選單」這個既有核心功能（回歸測試）~~——已由 headless 驗證情境 B（長按 900ms 直接點在畫線上）確認未回歸。

**單元測試要求：**（已完成）
- `tmp/epic-25-issue-4-harness/fix-verify.mjs`（headless Puppeteer + CDP `Input.dispatchTouchEvent`）涵蓋三種情境：短按（≤700ms）直接點在畫線上應攔截、長按（900ms）直接點在畫線上應正常觸發、短按點在超連結上不受影響，三者皆 PASS，即為「換頁＋相鄰頁畫線重疊→誤觸刪除對話框」symptom 的自動化重現與修復後不再誤觸發的驗證。
- 情境 B 即為「正常點擊畫線（無換頁介入）仍正確觸發編輯/刪除對話框」的回歸測試。

**驗收標準：** 已達成——headless 驗證確認修復後不再誤觸發、正常點擊畫線行為不受影響。**真機驗證換頁+畫線重疊情境不再誤跳出刪除確認尚待補齊**（已知殘留限制，見上方 Status：真機上長按原地放開是否仍合成 click 事件未經驗證）。
