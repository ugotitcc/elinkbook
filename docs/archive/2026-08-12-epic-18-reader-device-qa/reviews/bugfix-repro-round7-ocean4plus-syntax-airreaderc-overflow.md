# Bugfix Repro：第七輪 /diagnose —— iReader Ocean 4 Plus 開書 SyntaxError／Air Reader C 橫屏書架溢位紅字

日期：2026-08-06
回報來源：使用者真機截圖（iReader Ocean 4 Plus ×2、Air Reader C ×1）

## Bug A — iReader Ocean 4 Plus 開書卡住（JS SyntaxError）

### 症狀

開書畫面卡在載入指示器（「尚未匯入書籍」／「讀入中」殘影疊在錯誤文字上），閱讀器內建「Console Log」診斷畫面（Issue 33 產物）截取到：

```
[LOG] [UserAgent] Mozilla/5.0 (Linux; Android 11; Ocean 4 Plus Build/RQ2A.210505.003; wv)
      AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/83.0.4103.120 Safari/537.36
[ERROR] Uncaught SyntaxError: Unexpected token '('
```

另一張截圖（沉浸模式下溢出頁面底部的 JS 錯誤 toast）給出精確定位：

```
JS Error: Uncaught SyntaxError: Unexpected token '('
(https://appassets.androidplatform.net/assets/foliate/view.js:329)
```

### 根因（已用靜態解析驗證，信心高）

`app/android/app/src/main/assets/foliate/view.js:329`：

```js
#emit(name, detail, cancelable) {
    return this.dispatchEvent(new CustomEvent(name, { detail, cancelable }))
}
```

這是 ES2022 class **私有方法**（private instance method）宣告語法。私有「欄位」（`#x = 1`）與私有「方法」（`#foo() {}`）是 TC39 分兩個階段推進、Chromium 也分兩個版本才支援完畢的語法：

- 私有欄位：Chromium 74+ 就支援
- 私有方法／存取器：Chromium **84+** 才支援

該機 UA 回報 `Chrome/83.0.4103.120`——剛好卡在 83、比 84 差一版。這解釋了為什麼錯誤精確指向第 329 行、精確是 `Unexpected token '('`：引擎的解析器認得 `#emit` 是合法的私有 class 元素名稱（因為私有欄位語法它認得），接著預期 `=`/`;` 等欄位宣告收尾符號，卻遇到 `(`，於是丟出這個逐字對應的錯誤。

**驗證方式**：用 `acorn` parser 對整份 `view.js` 分別以 `ecmaVersion: 2019/2020/2021/2022` 解析：

```
ecmaVersion 2019: FAIL - Unexpected token (34:14)
ecmaVersion 2020: FAIL - Unexpected character '#' (128:4)
ecmaVersion 2021: FAIL - Unexpected character '#' (128:4)
ecmaVersion 2022: OK
```

且不是單一巧合——靜態掃描整個 `assets/foliate/` 目錄下私有方法宣告（`^\s*#\w+\(` pattern），6 個檔案共 75 處：`view.js`(7)、`epub.js`(4)、`progress.js`(4)、`overlayer.js`(2)、`fixed-layout.js`(24)、`paginator.js`(34)。這是整份釘定 vendor 程式碼廣泛使用的語法，不是可以單點修補的個案。

### 為什麼這次跟前六輪 /diagnose 修的問題不同類、既有 polyfill 機制救不了

前六輪（Issue 33／38／39／41 等）修的都是**執行期方法缺席**（`Object.groupBy`、`.at()`、`??=`、`Array.prototype.findLastIndex` 等）——這類問題的共通點是：JS 引擎**可以成功解析**整份腳本，只是執行到某一行呼叫了引擎不認得的內建方法才噴錯。因此可以靠 `_esCompatPolyfillJs`（`foliate_epub_reader_view.dart`）透過 `initialUserScripts` 在 `AT_DOCUMENT_START` 搶先注入 polyfill，讓那個方法名稱在 `view.js` 真正執行到之前就已經存在於 `window`/原型鏈上。Issue 38 甚至修過 polyfill 腳本自己誤用 `??=`（需 Chromium 85+）导致 polyfill 本身解析失敗、前幾輪「修好」的 4 個 polyfill 在 Chromium 83 上其實從未生效——但那次修的是 **polyfill 腳本自己**的語法，不是 `view.js` 本身。

這次不一樣：`SyntaxError` 發生在瀏覽器嘗試**解析** `view.js` 這個檔案本身的階段，而不是執行到某一行才出錯。私有方法是**語法層級**的功能，不是「window 上少了某個方法」這種可以用一段跑在它之前的腳本補上的東西——`view.js` 整個檔案在被瀏覽器讀進去的那一刻就解析失敗，後面完全不會有任何程式碼執行的機會，注入再多 polyfill 也無法讓解析器認得這個語法。也就是說，`check_foliate_es_compat.js`／`_esCompatPolyfillJs` 這整套既有防禦機制的作用範圍，天生就只能涵蓋「執行期 API 缺席」這一類問題，對「語法本身引擎看不懂」這一類問題完全無能為力——這是這次診斷發現的一個新的架構層級落差，不是既有機制的漏洞或退化。

### 使用者決定

記錄為已知限制，暫不處理（此輪不修）。

## Bug B — Air Reader C 橫屏書架格狀檢視，個別書本下方出現 RenderFlex 溢位紅字

### 症狀

橫屏（landscape，4 欄）書架格狀檢視，畫面最後一行含有個別書籍卡片（例如「刺蝟法則」），該書卡下方出現 Flutter debug 溢位警示（黃黑警示條 + 紅字），文字讀作 `BOTTOM OVERFLOWED BY 2.0 PIXELS`。

### 已知這個症狀模式先前修過一次，但這次不是同一個成因

`_BookGridTile`／`_GroupGridTile`（`app/lib/screens/library_screen.dart`）今天稍早（23:14–23:28，commit `fae776c`／PR #118，Issue 42）才修過幾乎一模一樣的症狀：文字說明區固定高度 `SizedBox` 沒有隨系統字級（`MediaQuery.textScalerOf(context)`）縮放，字級放大時觸發 RenderFlex 溢位；修法是把常數 `_kGridTileFooterHeightAtScale1 = 34.0` 透過 `.scale(...)` 隨字級同比例縮放，並有對應 widget test（`library_screen_test.dart:3005-3043`，`TextScaler.linear(1.5)` 情境）鎖住回歸。

**已向使用者確認：Air Reader C 上測試用的 APK 是 `fae776c` 合併之後才重新建置安裝的**，也就是說這次重現的並不是「舊 build 沒吃到修復」，而是修復後仍存在的**另一個**觸發路徑，需要重新走一輪 Phase 3-4。

### 修訂後的根因假設（排序，尚未逐一驗證，供下一輪確認）

1. **【最可能】`_kGridTileFooterHeightAtScale1 = 34.0` 這個magic constant，是用 Flutter widget test 「精確量測」校準出來的，但 `app/test/` 底下沒有 `flutter_test_config.dart`（只有 `integration_test/` 才有），代表所有 widget test——包含當初校準這個常數、以及鎖住 Issue 42 回歸的那個 test——文字都是用 Flutter widget test **預設的 fallback 測試字型**繪製，不是真機實際使用的系統字型。測試字型與真機系統字型（尤其 Android 各廠牌可能有自己的預載字型/字重）的行高（line height）度量本來就不保證完全一致；34.0 這個值本質上是「剛好卡到底」的極限值（程式碼註解本身也寫「取書籍格 2 行文字所需的『自然高度』為準」，代表沒有預留安全邊際），只要真機字型行高比測試字型多個 1-2px，就會在系統字級剛好 1.0 倍、完全沒有放大的情況下依然溢位——這正好對得上 Air Reader C 這次「2.0 像素」這種極小幅度的溢位量級，且與是否手動調整過系統字級無關。
   - **可證偽預測**：若這是真正根因，用真實系統字型（而非 widget test fallback 字型）量測 `_BookGridTile` 兩行文字（fontSize 12 + fontSize 10）在系統字級 1.0 倍下的自然高度，會略大於 34.0px；把常數改大幾個像素（或改用非「精確打滿」的量測方式）應能讓溢位消失。
2. **次可能：`childAspectRatio: 0.62` 沒有依方向調整，橫屏 4 欄時單一 cell 寬度變窄，連帶 cell 高度（= 寬度 / 0.62）也變矮**——若某些畫面寬度下 cell 高度扣掉封面 `Expanded` 最小可視需求後，留給固定 footer 的空間本身就比 34px 校準基準更緊繃（例如封面圖片本身有隱性最小高度，或 `Expanded` 在極端窄高比下被其他 sibling 擠壓），也可能是不同於「字型行高差異」的另一條觸發路徑。
   - **可證偽預測**：若這是根因，同一支 app 在較寬的橫屏裝置（例如平板橫放）不會重現，只有較窄的橫屏裝置（如 Air Reader C 實際邏輯寬度）會重現；且與字型無關，即使字級鎖定 1.0 倍不變仍會依裝置寬度不同而重現/消失。
3. **較不可能：Android 非線性字級縮放曲線**——Android 14+ 為避免大字級把 UI 撐爆，`fontScale` 對「原本較大」的數值（例如把 34 當成 fontSize 輸入）與對「原本較小」的數值（實際的 12／10 fontSize）縮放比例不同，導致 `.scale(34.0)` 與「先各自 `.scale(12)`／`.scale(10)` 再加總」在非線性曲線下不再相等，即使兩者在線性 `TextScaler`（既有 widget test 唯一驗證過的情境）下永遠相等。此假設成立的前提是 Flutter 的 Android engine 目前確實會把平台的非線性曲線透傳成非線性 `TextScaler`（而非永遠只透傳線性 `textScaleFactor` 包成 `TextScaler.linear`）——這點沒有把握，需要先查證 Flutter engine 版本行為，故排最後。
   - **可證偽預測**：若這是根因，僅在使用者手動調整過系統字級（尤其較大檔位）時才會重現；系統字級預設 100% 時不會溢位。

### 使用者確認與最終根因（已解決）

使用者確認 Air Reader C 測試當下**手動調大過系統字級**，排除假設 2（與字級無關的窄螢幕觸發），坐實假設 3（非線性字級縮放曲線）為真正根因，且與假設 1（widget test 字型落差）同源、可合併處理。

**用 Flutter 框架原始碼直接確認機制**（不需真機即可證實，信心等級：已驗證）：

- `MediaQuery.textScalerOf(context)` 在真實 App 執行時回傳的是 `SystemTextScaler`（`packages/flutter/lib/src/widgets/media_query.dart:2314`），其 `scale(fontSize)` 直接呼叫 `_platformDispatcher.scaleFontSize(fontSize)`——這條路徑會透傳到原生引擎，在 Android 上可反映系統實際的字級縮放曲線（Flutter 官方 `TextScaler` 文件本身即明白指出：「較大的輸入值通常會得到較大的輸出，但不保證嚴格比例」，是專為非線性縮放預留的抽象）。
- 反觀 `flutter_test` 套件的 `TestPlatformDispatcher.scaleFontSize`（`packages/flutter_test/lib/src/window.dart:334`）寫死是 `textScaleFactor * unscaledFontSize`——**純線性乘法，無法透過任何 textScaleFactor 設定測出非線性行為**。既有 Issue 42 回歸測試用 `TextScaler.linear(1.5)`（透過 `MediaQuery` 直接覆寫，繞過 `TestPlatformDispatcher`）驗證的也仍是線性情境，天生測不出這個落差。
- 舊寫法 `MediaQuery.textScalerOf(context).scale(_kGridTileFooterHeightAtScale1)` 把「書名＋進度」的合計值（34.0）當成單一「字級」整體丟進 `scale()`；但真正的 `Text` 元件是分別對書名（12px）與進度（10px）各自呼叫 `scale()` 再各自渲染。任何嚴格凹的非線性縮放曲線（Android 非線性字級縮放正是為了避免超大字級把 UI 撐爆而刻意「數值越大、縮放越保守」）都會讓 `scale(12) + scale(10) > scale(22)`（進一步 `> scale(34)` 的等比例延伸），也就是固定容器實際拿到的高度，天生就會少於兩行文字真正需要的高度。

**用 TDD 完整驗證**：在 `app/test/screens/library_screen_test.dart` 新增一個自訂 `_NonLinearTextScaler`（`scale(1.0)` 時完全不變、放大時對較大輸入值套用相對保守的縮放，符合任一嚴格凹函式的通用性質），透過 `MediaQuery(data: MediaQueryData(textScaler: ...))` 直接注入（同既有測試手法，繞過 `TestPlatformDispatcher` 的線性限制）：

- **套用修法前**：測試重現 `RenderFlex overflowed by 8.5 pixels on the bottom`，與真機症狀同一種失效模式。
- **套用修法後**：`flutter test test/screens/library_screen_test.dart`（70 項）與全專案 `flutter test`（977 項）全數通過，`flutter analyze` 乾淨。

### 已完成的修法

`app/lib/screens/library_screen.dart`：新增 `_gridTileFooterHeight(BuildContext)`，改成分別對書名字級（12）與進度字級（10）各自呼叫 `MediaQuery.textScalerOf(context).scale(...)` 後再相加，乘上由既有 34.0 校準值反推出的固定行高比例常數（`_kGridTileFooterLineHeightFactor = 34.0 / (12 + 10)`，與縮放曲線本身無關，系統字級 1.0 倍時仍與修法前輸出完全一致，不影響 Issue 42 既有的跨 cell 對齊需求）。`_GroupGridTile`／`_BookGridTile` 兩處使用點皆已改用這個共用函式取代原本的 `.scale(_kGridTileFooterHeightAtScale1)`。

尚未執行：提交（commit）／`docs/epics.md`／`issues.md` 的正式收尾記錄——待人類指示是否比照既有慣例正式立案為一個 Issue 編號。
