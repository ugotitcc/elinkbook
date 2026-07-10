# Issue 7：字型粗細（fontWeight）設定無視覺效果 — 實作計劃

**Goal:** 修正 fontWeight 滑桿調整無視覺效果的問題

---

## 修訂紀錄

本計劃原始版本（Task 1/2 的初版內容）判斷根因為「Dart 端倍率換算公式錯誤」，該判斷**並未被採用**：實際落地的 `a2e1cc3` commit 改走另一條路——Dart 端維持送出 Readium 倍率語意（0.75–2.25），不做 `*400`/`/400` 轉換；原生端 `EpubPreferences.fontWeight` 收到倍率後，由 Readium 內部换算成 CSS `font-weight = clamp(1, 1000, 400 × 倍率)`（見 `spec.md` 216 行、經反編譯 `EpubSettingsKt.class` 位元組碼確認）。這條路徑本身是對的。

但緊接著的 `197a013` commit（「啟用 textNormalization for font weight」）引入了一個新的迴歸，導致字重滑桿在該次修正後又再度失效。以下為透過 `/diagnose` 反編譯 `readium-navigator:3.3.0` 實際依賴（`classes.jar` + 內建的 `ReadiumCSS-after.css`）重新確認的根因，取代原始版本的分析。

---

## 根因分析（已透過反編譯確認）

`EpubReaderView.kt` 的 `buildPreferencesFromMap()` 原本寫死 `textNormalization = true`（`197a013` commit 引入，原意是「讓字重生效」，但方向恰好相反）。

反編譯 `readium-navigator-3.3.0.aar` 的 `classes.jar`（`org.readium.r2.navigator.epub.EpubSettingsKt`）確認：

- `fontOverride`（對應 CSS 旗標 `readium-font-on`）的判斷式是 `(fontFamily != null) || textNormalization`。
- `a11yNormalize`（對應 CSS 旗標 `readium-a11y-on`）**直接等於** `textNormalization` 的值。

也就是說，只要 `textNormalization = true`，這兩個旗標永遠同時為真——與使用者是否真的開啟無障礙模式無關。

同時反編譯內建的 `ReadiumCSS-after.css`（實際隨 App 打包、注入 WebView 的樣式表）發現以下規則：

```css
:root[style*=readium-font-on][style*=readium-a11y-on]{
  font-style: normal !important;
  font-weight: 400 !important
}
```

`fontWeight` preference 本身是透過一個通用的 `overrides: Map<String,String>` 欄位，以字面字串 key `"font-weight"`（真正的 CSS 屬性，不是自訂變數）寫進 `<html>` 的 inline style（換算公式正確）。但由於 `textNormalization = true` 讓上述兩個旗標永遠為真，`ReadiumCSS-after.css` 的 `!important` 規則永遠命中同一個 `<html>` 元素，而 CSS 層疊規則下「帶 `!important` 的樣式表規則」永遠贏過「同元素上不帶 `!important` 的 inline style」——導致字重滑桿送出的任何值，在渲染前就被這條規則蓋回 400。

`a11yNormalize`/`textNormalization` 其實是 Readium 的「無障礙文字正規化」功能（刻意抹平字重/字型樣式差異，方便閱讀障礙使用者），語意上與「讓字重滑桿生效」正好相反。

---

### Task 1（原內容已作廢）：Dart 端 fontWeight 值轉換

~~移除 `_fontWeightMultiplier` 的除以 400 轉換，直接使用 CSS 原始值（300-900）。~~

**現況：不需執行。** `a2e1cc3` 已採用另一條正確路徑：`app/lib/screens/reader_settings_sheet.dart` 維持送出 Readium 倍率語意（`_fontWeightMultiplier`，範圍 0.75–2.25），UI 顯示時才 `×400`／使用者拖動時才 `÷400`（見該檔案第 40、47、64、88、113、151、157 行），與 `spec.md` 216 行記載的換算公式一致，無需改動。

---

### Task 2：移除 Kotlin 端 `textNormalization = true`

**Files:**
- Modify: `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt`

**Description:**
刪除 `buildPreferencesFromMap()` 中寫死的 `textNormalization = true`，讓該欄位維持未設定（`null`），不再強制觸發 `readium-font-on` + `readium-a11y-on` 雙旗標，避免 `ReadiumCSS-after.css` 的 a11y 正規化規則蓋掉使用者設定的字重。

- [x] **Step 1：刪除 `textNormalization = true,` 這一行**（第 165 行）——全專案僅此一處使用 `textNormalization`，移除後無其他相依需要調整。

**驗證方式：** 真機測試拖動滑桿 300→900，觀察文字粗細變化；同時確認移除後不影響 `197a013` commit 另一項改動（`reader_screen.dart` 的 SafeArea／manga 底部裁切修正），兩者互不相關。

**結果：** 此步驟為必要但不充分的修正——真機用 WebView 遠端除錯（Chrome DevTools Protocol）實測確認，移除後 `<html>`／`<body>` 的 `font-weight` 確實正確算出使用者設定的值（例如拖到 900 時 `getComputedStyle(document.documentElement).fontWeight === "900"`），但真機仍回報「無法變更字重」，因而繼續往下追查，見 Task 4。

---

### Task 4（`/diagnose` 二次追查）：補強 fontWeight 的強制往下蓋規則

**根因：** ReadiumCSS 對其他數值型 preference（`fontSize`／`lineHeight`／`paraSpacing`）都額外準備了一條規則，把值強制往下蓋到 `p`/`div`/`li`/`pre` 等實際內文元素並帶 `!important`（例如 `:root[style*=readium-advanced-on] dd,div,li,p,pre{font-size:1rem!important}`）。但反編譯確認 `font-weight` **完全沒有對應的往下蓋規則**——它只被設在 `<html>` 本身，之後只靠 CSS 繼承往下傳遞。只要書本自己的 CSS 對段落/標題有任何 `font-weight` 宣告（很常見），該元素會直接吃書本自己的值，完全不會繼承到使用者設定的值——這不是 `!important` 優先權問題，是 CSS 繼承規則本身（子元素有自己的宣告時，繼承根本不會發生）。

**Files:**
- Modify: `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt`

**Description:**
新增 `applyFontWeightCascade()`：透過 View 樹尋找 WebView（`findViewByType<WebView>()`），用 `evaluateJavascript` 注入/更新一個 `<style id="elinkbook-font-weight-cascade">`，把 `currentPreferences.fontWeight` 換算後的 CSS 值以 `!important` 強制套用到 `body, p, div, li, span, td, th, blockquote, dd, dt, a, h1~h6`，仿照 ReadiumCSS 自己對 `fontSize` 的做法；`fontWeight` 為 null 時移除該 `<style>`（避免殘留影響下一本沒有覆寫字重的書）。在 `onPageLoaded()`（每次換頁）與 `setPreferences()`（滑桿即時調整）都呼叫，涵蓋初次開書與即時調整兩種情境。

**驗證方式（已完成，真機 WebView 遠端除錯）：**
```
injectedStyle: "body, p, div, li, span, td, th, blockquote, dd, dt, a, h1, h2, h3, h4, h5, h6 { font-weight: 900 !important; }"
```
確認注入的 `<style>` 內容與滑桿值一致。測試當下開啟的書（六頂思考帽）封面頁本身是純設計圖（標題文字是圖片，DOM 內無真正的文字節點），因此未能在該頁肉眼看到差異，但機制層級已確認正確、且與 Readium 自己對其他屬性的既有作法一致；後續若要肉眼驗收，需切到有實際內文段落的章節頁。

---

### Task 3: 建立單元測試

**Files:**
- Create: `app/test/screens/reader_settings_sheet_test.dart`

**Description:**
驗證 fontWeight 值在 UI 顯示與持久化儲存之間的正確轉換——注意送出的是 Readium **倍率**（0.75–2.25），不是 CSS 原始值（300-900）。

- [ ] **Step 1: 測試 fontWeight 值轉換**

```dart
testWidgets('fontWeight 滑桿調整應送出 Readium 倍率語意（0.75-2.25）', (tester) async {
  final prefs = BookReaderPrefs.empty;
  BookReaderPrefs? capturedPrefs;

  await tester.pumpWidget(MaterialApp(
    home: ReaderSettingsSheet(
      prefs: prefs,
      onChanged: (p) => capturedPrefs = p,
    ),
  ));

  // 拖動字重滑桿到 UI 顯示值 700
  final slider = find.byKey(const Key('reader_settings_font_weight_slider'));
  await tester.drag(slider, Offset(100, 0)); // 向右拖動

  // 送給原生端的是倍率（700 / 400 = 1.75），不是 700 本身
  expect(capturedPrefs?.fontWeight, equals(1.75));
});
```

---

### 驗收標準
- 拖動字重滑桿 300→900，思源黑體/宋體呈現 Variable Font 多級漸進變化
- 其餘 3 款字型呈現模擬粗體效果（Faux Bold）
- `flutter test` 通過、`flutter analyze` 乾淨
- 真機驗證確認移除 `textNormalization` 後，先前 `197a013` 修正的 manga 底部裁切問題未回歸

---

### Task 5（`/diagnose` 三次追查）：原俠正楷／台灣圓體／源流明體 3 款單一靜態字重字型完全無反應

**使用者回報：** 這 3 款字型（`GuanKiapTsingKhai.ttf`／`TaiwanPearl-Regular.ttf`／`GenRyuMinTW-Regular.ttf`）拖動字重滑桿完全沒有視覺效果——與思源黑體/宋體（`-VF` 結尾的真 Variable Font）不同。

**根因：** 這 3 款字型檔案本身只有一種靜態字重，物理上不可能真的變粗；唯一能有效果的方式是靠瀏覽器內建的模擬粗體（synthetic bold）。但 `buildFontFamiliesConfiguration()` 原本對全部 5 款字型都無差別註冊了兩個 `@font-face`——`FontWeight.NORMAL` 與 `FontWeight.BOLD`——對這 3 款靜態字重字型而言，兩個宣告指向**同一份檔案**。瀏覽器看到「family 已經有一個宣告涵蓋 700 字重的 face」就會認定不需要合成，因而**抑制**了原本會自動套用的模擬粗體，導致字重滑桿對這 3 款字型完全沒有視覺效果。

**修正：**
`buildFontFamiliesConfiguration()` 新增 `variableWeightFamilies = setOf("SourceHanSansTC", "SourceHanSerifTC")`，只有落在這個集合裡的字型才額外註冊 `FontWeight.BOLD` 的 `@font-face`；其餘 3 款靜態字重字型只註冊一個對應真實檔案字重的 face，讓瀏覽器預設的 `font-synthesis`（預設開啟）在字重滑桿要求較粗的值時，自動對這 3 款字型套用模擬粗體。

**驗證結果（真機，Chrome DevTools Protocol 直接查詢 `document.fonts`）：**
```json
"GuanKiapTsingKhai": [{ "weight": "400", "style": "normal" }]
"TaiwanPearl":       [{ "weight": "400", "style": "normal" }]
"GenRyuMinTW":       [{ "weight": "400", "style": "normal" }]
"SourceHanSansTC":   [{ "weight": "400" }, { "weight": "700" }]
"SourceHanSerifTC":  [{ "weight": "400" }, { "weight": "700" }]
```
確認 3 款靜態字重字型現在只註冊單一 face、2 款變數字型維持雙 face，符合預期，機制層級已確認正確。
