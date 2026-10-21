# Issue 6b：MDX 圖片、獨立 CSS、深色與 E-Ink 配色 實作計畫

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** MDX 詞條在 JavaScript 關閉的 WebView 裡顯示 `.mdd` 內的圖片、字典自帶的 CSS，並在深色與 E-Ink 下文字可讀；順手補上 Issue 7 實機發現的兩項面板問題（E-Ink 外框、選取控點蓋住面板）。

**Architecture:** 新增純函式層 `mdx_resource.dart`（網址→MDD 鍵、副檔名→`contentType`、`MdxResource` 型別）與 `mdx_css_inline.dart`（`<link>` 換 `<style>`）。`MdxReader` 開啟時一併開同目錄、同主檔名的 `.mdd`，提供 `readResource(url)`。`MdxDictionaryProvider` 在回傳詞條前內嵌 CSS。`MdxEntryView` 的 `shouldInterceptRequest` 改為非同步，向 `DictionaryService.readMdxResource` 要圖片；配色覆寫樣式由 `prepareEntryHtml` 注入。

**Tech Stack:** Flutter、`flutter_inappwebview`、vendor 修補後的 `dict_reader`（已有，`readOneMdd`）、`gen-l10n`（四份 ARB）。不新增套件，不動 `pubspec.yaml`。

**Spec:** `docs/epics/epic-63-dictionary-lookup/spec.md` §3.6（MDX 詞條處理表：圖片、外部 `.css`、深色與 E-Ink 配色）、§7（整合測試）、§9 驗收 18、19、25；`issues.md` 的 Issue 6b 與檔尾「後續項目」；上游延後項見 `plan-issue-6a.md`「實作期間的偏離」與「未驗證／留待後續」。

## Global Constraints

- 不新增套件；不動 `pubspec.yaml`、主資料庫（`version: 28`）、`app/android/app/src/main/assets/foliate/main.js`、`dictionary.db` 結構。
- MDX 的 WebView 維持：JavaScript 關閉、`allowFileAccess: false`、`allowContentAccess: false`、只載入我們傳入的 HTML 字串。**永不連網**。
- `shouldInterceptRequest` 對所有請求都必須回傳明確的 `WebResourceResponse`（找不到回 404 空內容），只有 `data:` 初始文件例外回 `null`。回 `null` 會讓 WebView 走真實網路。
- 網址→MDD 鍵：去掉 `https://dict.local/` 與開頭 `/` → `Uri.decodeComponent` → `/` 換成 `\` → 前面加 `\`；找不到再試不加開頭 `\` 的形式（spec §3.6）。
- `contentType` 只放 spec 列的五種：`image/jpeg`、`image/png`、`image/gif`、`image/webp`、`image/svg+xml`。其他副檔名回 404。
- 單一資源上限 8 MiB（`kMdxResourceMaxBytes`），超過回 404。理由：驗收 25 的記憶體增量小於 50 MB。
- CSS：只比對 `<link href>` 的**檔名**（不分大小寫）；沒有對應檔案的 `<link>` 移除；移除 `@import`；內嵌時把 `</style` 轉義，避免 CSS 內容提早關閉標籤。
- 字串一律走 `AppLocalizations`，新字串同時加進四份 ARB（`app_zh_TW.arb` 為範本，附 `@key` 說明）。
- 畫面不加 `AnimatedXxx`；E-Ink 用邊框不用陰影。
- 錯誤訊息三段式：發生什麼、為什麼、使用者要做什麼。
- 所有文件與註解用正體中文；commit 訊息不加 `Co-Authored-By`。
- 每個 Task 只跑觸及的測試檔；完整 `flutter test` 只在最後一個 Task 跑一次。

## Review Focus

1. **圖片路徑的邊角**：空白（`%20`）、中文、`%25`、子目錄反斜線、大小寫不同、`?v=1` 查詢字串、找不到。全部不丟例外，找不到回 404（Task 1）。
2. **惡意或壞詞條**：`<link href="http://evil/x.css">`、CSS 內含 `</style>`、`@import url(http://...)`、`url(http://...)` 圖片。結果都是不連網、不破版（Task 2、5）。
3. **`.mdd` 缺失、損壞、比預期大**：沒有 `.mdd` 的字典照常查詢；`.mdd` 壞檔只讓圖片 404，整本字典不失敗；超過 8 MiB 的資源回 404（Task 3）。
4. **深色下詞條寫死顏色**：`<font color>`、`bgcolor`、行內 `style="color:#000"` 都要被蓋掉，文字與背景對比可讀（Task 4）。
5. **選取控點隱藏後的還原**：關閉面板、面板被系統返回鍵關閉、查詢途中發生例外，三種路徑控點與選取範圍都要還原，劃線工具列照常（Task 7）。

## 已決定事項（spec 沒寫清楚，本計畫的選擇）

- **`.mdd` 配對規則：** `MdxReader.open(path)` 在 `.mdx` 同一個目錄找「主檔名相同、副檔名 `.mdd`（不分大小寫）」的檔案。匯入時兩者已在同一個私有目錄（`DictionaryFileStore`）。只支援單一 `.mdd`；`name.1.mdd` 這類分卷列為後續項目。
- **CSS 在哪裡內嵌：** 在 `MdxDictionaryProvider` 回傳詞條前做，讀 `p.dirname(source.storagePath)` 下的 `.css`。這樣首次查詢與交叉參照（`lookupInSource`）都走同一條路，面板與 WebView 不必知道 CSS。
- **配色覆寫在哪裡注入：** 在 `prepareEntryHtml` 以選用參數注入，因為主題是顯示當下才知道。淺色且非 E-Ink 不注入，保留字典原本排版。
- **`.mdd` 內的 `.css` 不處理。** spec 只定義匯入時附加的 `.css`。有些字典把 CSS 放在 `.mdd` 裡，這類 `<link>` 會被移除，詞條改用預設樣式。列為後續項目。
- **E-Ink 外框範圍：** `EBSheetShell` 在 `isEinkMode` 時加上、左、右三邊 2 px 邊框（下緣貼螢幕底，不畫）。其他用 `EBSheetShell` 的畫面（書籍動作 Sheet 等）也會得到外框，符合 E-Ink 用邊框的規則；Task 6 的測試確認它們沒有版面回歸。
- **選取控點：** 控點由系統畫在 WebView 之上，Dart 無法蓋住。本計畫先用 Task 7 的真機探測決定做法；探測失敗就不出貨這一項，改記錄結果並維持後續項目。`main.js` 不能改（Global Constraints）。

## l10n 鍵名與文案（四份 ARB 統一）

| 鍵名 | zh-TW 文案 |
|---|---|
| `dictionaryMdxLimitNote` | 已知限制：字典詞條不會執行 JavaScript，所以依賴點擊腳本的功能（例如牛津 9 的圖片放大）不會運作，只看得到縮圖。 |

## 檔案結構

| 動作 | 路徑 | 責任 |
|---|---|---|
| 建立 | `app/lib/dictionary/mdx_resource.dart` | `MdxResource`、`mddKeysForUrl`、`imageContentTypeForKey`、`kMdxResourceMaxBytes` |
| 建立 | `app/lib/dictionary/mdx_css_inline.dart` | `inlineLinkedCss` |
| 建立 | `app/lib/dictionary/mdx_theme_override.dart` | `MdxColors`、`mdxColorsFor`、`mdxOverrideCss` |
| 修改 | `app/lib/dictionary/storage/mdx_reader.dart` | 開啟同名 `.mdd`、`readResource` |
| 修改 | `app/lib/dictionary/providers/mdx_dictionary_provider.dart` | 回傳前內嵌 CSS |
| 修改 | `app/lib/dictionary/dictionary_service.dart` | `readMdxResource` |
| 修改 | `app/lib/dictionary/mdx_html_prepare.dart` | `prepareEntryHtml` 加選用 `overrideCss` |
| 修改 | `app/lib/screens/widgets/mdx_entry_view.dart` | 非同步攔截、`resolveResource`、`colors` |
| 修改 | `app/lib/screens/widgets/dictionary_lookup_sheet.dart` | 傳入 `readMdxResource` 與配色 |
| 修改 | `app/lib/screens/widgets/eb_sheet_shell.dart` | E-Ink 外框 |
| 修改 | `app/lib/screens/dictionary_settings_screen.dart`、四份 ARB | 已知限制說明 |
| 修改 | `app/lib/reader/foliate_reader_view.dart`、`app/lib/screens/reader_screen.dart` | 選取控點隱藏與還原（Task 7，視探測結果） |
| 修改 | `app/tool/make_test_mdx.py`、`app/tool/README.md` | 產生含圖片的測試 MDX／MDD |
| 建立／修改 | `app/test/dictionary/{mdx_resource,mdx_css_inline,mdx_theme_override,mdx_reader,mdx_dictionary_provider,mdx_html_prepare}_test.dart`、`app/test/screens/widgets/{mdx_entry_view,eb_sheet_shell,dictionary_lookup_sheet}_test.dart`、`app/test/screens/dictionary_settings_screen_test.dart`、`app/integration_test/dictionary_mdx_test.dart` | 測試 |

---

### Task 1：資源鍵轉換與型別（純函式）

**Files:**
- Create: `app/lib/dictionary/mdx_resource.dart`
- Test: `app/test/dictionary/mdx_resource_test.dart`

**Interfaces:**
- Consumes: `kMdxBaseUrl`（`app/lib/dictionary/mdx_link_policy.dart`）。
- Produces:
  - `const int kMdxResourceMaxBytes = 8 * 1024 * 1024;`
  - `class MdxResource { const MdxResource({required Uint8List bytes, required String contentType}); }`
  - `List<String> mddKeysForUrl(String url)`：不在 `kMdxBaseUrl` 底下、解碼失敗、或去掉開頭 `/` 與查詢後路徑為空，一律回空清單；否則回 `[r'\pic\a b.png', r'pic\a b.png']`（第一個含開頭 `\`，第二個不含）。
  - `String? imageContentTypeForKey(String key)`：副檔名不分大小寫，只認 spec 列的五種（`.jpg`／`.jpeg` 皆為 `image/jpeg`），其餘回 `null`。

- [ ] **Step 1: 寫失敗測試** `mdx_resource_test.dart`：
  - `空白與子目錄`：`https://dict.local/pic/a%20b.png` → `[r'\pic\a b.png', r'pic\a b.png']`。
  - `中文與 %25`：`https://dict.local/%E5%9C%96/50%25.png` → 第一個鍵為 `\圖\50%.png`。
  - `查詢字串與錨點被去掉`：`https://dict.local/pic/a.png?v=1#x` → 第一個鍵為 `\pic\a.png`。
  - `不在 baseUrl 底下回空`：`https://evil.example/a.png`、`file:///a.png`、`data:image/png;base64,AA==`。
  - `壞的百分比編碼回空，不丟例外`：`https://dict.local/%E0%A4%A.png`。
  - `根路徑與純查詢字串回空`：`https://dict.local/`、`https://dict.local/?v=1` 回 `[]`，不會出現 `[r'\', '']`。
  - `favicon 不特判`：`https://dict.local/favicon.ico` 回 `[r'\favicon.ico', r'favicon.ico']`（是否 404 由讀取端決定）。
  - `contentType`：`.PNG`、`.jpg`、`.jpeg`、`.gif`、`.webp`、`.svg` 各自對應；`.mp3`、`.css`、無副檔名回 `null`。

- [ ] **Step 2: 執行確認失敗**
  Run: `cd app && flutter test test/dictionary/mdx_resource_test.dart`
  Expected: FAIL（找不到 `mdx_resource.dart`）。

- [ ] **Step 3: 實作**上述簽章。鍵轉換用 `Uri.tryParse` 取 `path`（已排除查詢與錨點），再 `Uri.decodeComponent`（包 try/catch）。

- [ ] **Step 4: 執行確認通過**（同 Step 2 指令）Expected: PASS。

- [ ] **Step 5: Commit**
  ```bash
  git add app/lib/dictionary/mdx_resource.dart app/test/dictionary/mdx_resource_test.dart
  git commit -m "feat(epic-63): Issue 6b MDD 資源鍵轉換與型別"
  ```

---

### Task 2：獨立 CSS 內嵌

**Files:**
- Create: `app/lib/dictionary/mdx_css_inline.dart`
- Modify: `app/lib/dictionary/providers/mdx_dictionary_provider.dart`
- Test: `app/test/dictionary/mdx_css_inline_test.dart`、`app/test/dictionary/mdx_dictionary_provider_test.dart`

**Interfaces:**
- Consumes: `extractReferencedCssNames`（`mdx_companion_files.dart`）。
- Produces: `String inlineLinkedCss(String html, Map<String, String> cssByLowerName)`：`cssByLowerName` 的鍵是小寫檔名。

- [ ] **Step 1: 寫失敗測試** `mdx_css_inline_test.dart`：
  - `依檔名換成 style`：`<link rel="stylesheet" href="css/Ghychyz.CSS">` + `{'ghychyz.css': 'p{color:red}'}` → 輸出含 `<style>p{color:red}</style>`、不含 `<link`。
  - `查詢字串與路徑不影響配對`：`href="../x/a.css?v=2"` 配 `a.css`。
  - `沒有對應檔案的 link 被移除`：輸出不含 `<link`，也不含任何 `<style>`。
  - `@import 被移除`：CSS 內容 `@import url("b.css"); p{color:red}` → 輸出不含 `@import`、保留 `p{color:red}`；詞條自己的 `<style>@import url(http://evil/x.css);</style>` 也被移除。
  - `style 結束標籤被轉義`：CSS 內容含 `</style><script>x</script>` → 輸出恰好一個 `</style>`（內嵌的那個）；CSS 內容裡的 `</style` 變成 `<\/style`；`<script>` 文字仍在，但位置落在唯一的 `<style>` 與 `</style>` 之間，不會成為獨立節點（以字串位置斷言）。
  - `非 UTF-8 的 css 不中斷查詢`（`mdx_dictionary_provider_test.dart`）：`.css` 放入 Big5／GBK 位元組，查詢仍 `found`，該 CSS 以 `utf8.decode(allowMalformed: true)` 的結果內嵌或略過，不丟例外。
  - `其他 link 不動`：`<link rel="icon" href="x.png">` 沒有 `.css` 結尾——保持原樣（它不是樣式表；後續由 6a 的 prepare 與請求攔截處理）。
  - `href="http://evil/x.css"` 且檔名剛好是已匯入的 `x.css`：照檔名配對內嵌（只比對檔名），不產生任何對外請求。
  - `provider` 測試（`mdx_dictionary_provider_test.dart`）：在暫存目錄放 `.mdx`（`html.mdx` 複本）與 `ghychyz.css`，詞條含 `<link href="ghychyz.css">` 時，回傳的 `entry.body` 內嵌了該 CSS；目錄沒有 `.css` 時 `<link>` 被移除、查詢仍 `found`。

- [ ] **Step 2: 執行確認失敗**
  Run: `cd app && flutter test test/dictionary/mdx_css_inline_test.dart test/dictionary/mdx_dictionary_provider_test.dart`
  Expected: FAIL。

- [ ] **Step 3: 實作** `inlineLinkedCss`：用與 `extractReferencedCssNames` 相同的 `<link>`／`href` 比對規則取檔名（可共用該檔的私有 regex 時抽成共用常數，不要複製貼上第二份）；只處理副檔名 `.css` 的 `<link>`。`MdxDictionaryProvider._lookupWith` 在組 `DictionaryEntry` 前，若任一 body 含 `<link`（不分大小寫）才讀 `p.dirname(source.storagePath)` 下的 `.css`（讀取失敗當作沒有），並對每筆 body 呼叫 `inlineLinkedCss`。讀檔用 `File.readAsBytes()` 再 `utf8.decode(bytes, allowMalformed: true)`，整段包 `try/catch`（許多舊字典的 `.css` 是 GBK／Big5，直接 `readAsString()` 會丟 `FormatException`）。

- [ ] **Step 4: 執行確認通過**（同 Step 2 指令）Expected: PASS。

- [ ] **Step 5: Commit**
  ```bash
  git add app/lib/dictionary app/test/dictionary
  git commit -m "feat(epic-63): Issue 6b 詞條外部 CSS 依檔名內嵌"
  ```

---

### Task 3：`.mdd` 讀取與資源服務

**Files:**
- Modify: `app/lib/dictionary/storage/mdx_reader.dart`、`app/lib/dictionary/dictionary_service.dart`
- Modify: `app/tool/make_test_mdx.py`、`app/tool/README.md`（新增 `images` 種類，產生 `images.mdx` 與 `images.mdd`）
- Create: `app/test/fixtures/mdx/images.mdx`、`app/test/fixtures/mdx/images.mdd`
- Test: `app/test/dictionary/mdx_reader_test.dart`、`app/test/dictionary/dictionary_service_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `MdxResource`、`mddKeysForUrl`、`imageContentTypeForKey`、`kMdxResourceMaxBytes`。
- Produces:
  - `MdxReader.readResource(String url, {int maxBytes = kMdxResourceMaxBytes}) → Future<MdxResource?>`：沒有 `.mdd`、鍵不存在、副檔名不支援、超過 `maxBytes`、讀取丟例外，全部回 `null`。`readOneMdd` 回傳 `List<int>`，組 `MdxResource` 時轉成 `Uint8List`（已是 `Uint8List` 就直接用，否則 `Uint8List.fromList`）。
  - `DictionaryService.readMdxResource(String sourceId, String url) → Future<MdxResource?>`：來源不存在、沒有 pool、任何例外回 `null`。

- [ ] **Step 1: 產生 fixture**：`make_test_mdx.py` 新增 `images` 種類。`images.mdx` 有一筆詞條 `pic`，本文含 `<img src="pic/a b.png">`；`images.mdd` 有 `\pic\a b.png`（最小 PNG）、`\pic\sub\c.png`、`\snd\x.mp3`（用來測不支援的副檔名）。依 `tool/README.md` 慣例執行並把指令寫進 README。

- [ ] **Step 2: 寫失敗測試**（`mdx_reader_test.dart`，把 `images.mdx`／`images.mdd` 複製到暫存目錄後開啟）：
  - `讀到圖片`：`readResource('https://dict.local/pic/a%20b.png')` 的 `contentType == 'image/png'`、`bytes` 開頭為 PNG 簽章。
  - `子目錄`：`pic/sub/c.png` 讀得到。
  - `找不到回 null`：`pic/none.png`。
  - `不支援的副檔名回 null`：`snd/x.mp3`。
  - `沒有 mdd 的字典`：只複製 `.mdx` 時 `readResource` 回 `null`，`lookupAll` 照常。
  - `mdd 壞檔不讓字典失敗`：把 `images.mdd` 截斷一半放在旁邊，`MdxReader.open` 仍成功、`readResource` 回 `null`。
  - `主檔名不分大小寫配對`：`Images.MDD` 配 `images.mdx`。
  - `超過上限回 null`：`readResource(url, maxBytes: 1)`，PNG 回 `null`；預設上限下同一張 PNG 讀得到。
  - `close` 之後 `readResource` 回 `null`、不丟例外。
  `dictionary_service_test.dart`：`readMdxResource` 對已匯入的 `images` 來源回圖片；來源不存在回 `null`；`mdxPool == null` 回 `null`。

- [ ] **Step 3: 執行確認失敗**
  Run: `cd app && flutter test test/dictionary/mdx_reader_test.dart test/dictionary/dictionary_service_test.dart`
  Expected: FAIL。

- [ ] **Step 4: 實作** `MdxReader`：`open` 完成 `.mdx` 後，掃同目錄找主檔名相同的 `.mdd`，用 `DictReader(path).initDict()` 開啟，任何失敗當作沒有（並釋放控制代碼）；`close` 一併關閉。`readResource` 依序試 `mddKeysForUrl` 回傳的鍵：`locate` → `readOneMdd`，大小以讀出的位元組數判斷上限。`DictionaryService.readMdxResource` 照 `lookupInSource` 的方式找來源，走 `pool.use`。

- [ ] **Step 5: 執行確認通過**（同 Step 3 指令）Expected: PASS。

- [ ] **Step 6: Commit**
  ```bash
  git add app/lib/dictionary app/tool app/test
  git commit -m "feat(epic-63): Issue 6b 讀取 mdd 圖片資源並經 DictionaryService 提供"
  ```

---

### Task 4：深色與 E-Ink 配色覆寫

**Files:**
- Create: `app/lib/dictionary/mdx_theme_override.dart`
- Modify: `app/lib/dictionary/mdx_html_prepare.dart`
- Test: `app/test/dictionary/mdx_theme_override_test.dart`、`app/test/dictionary/mdx_html_prepare_test.dart`

**Interfaces:**
- Produces:
  - `class MdxColors { const MdxColors({required Color background, required Color foreground, required Color link, required bool underlineLinks}); }`，**實作 `==` 與 `hashCode`**（Task 5 的 `didUpdateWidget` 靠它判斷配色是否變了）。
  - `MdxColors? mdxColorsFor({required bool isEinkMode, required Brightness brightness, required ColorScheme scheme})`：E-Ink 回黑字白底、連結同黑加底線；深色回 `scheme.surface`／`scheme.onSurface`／`scheme.primary`；淺色且非 E-Ink 回 `null`。
  - `String mdxOverrideCss(MdxColors colors)`：回傳 `<style>` 內容，含 `html,body{background:#rrggbb !important;color:#rrggbb !important}`、`*{color:...!important;background-color:transparent !important;border-color:...!important}`、`a{color:... !important}`（`underlineLinks` 為真時加 `text-decoration:underline !important`）、`img{background-color:#ffffff !important;max-width:100% !important;height:auto}`。`img` 必須帶 `!important`：否則會被 `*{background-color:transparent !important}` 蓋掉，透明底黑線圖在深色下就隱形；兩者都有 `!important` 時，元素選擇器 `img` 比 `*` 優先。
  - `prepareEntryHtml(String html, {String? overrideCss})`：有值時在 `</head>` 前（沒有 head 外殼時補在 head 內）插入 `<style>$overrideCss</style>`，保證在字典自己的樣式之後。

- [ ] **Step 1: 寫失敗測試**：
  - `mdxColorsFor`：E-Ink（任何亮度）→ 黑字白底且 `underlineLinks == true`；深色非 E-Ink → 取自 `ColorScheme`；淺色非 E-Ink → `null`。
  - `mdxOverrideCss`：輸出含 `!important`、含傳入的十六進位色碼（小寫、六碼）；`img` 規則含 `background-color:#ffffff !important`（用正規表示式斷言它帶 `!important`）；`MdxColors` 相同欄位的兩個實例 `==` 為真。
  - `對比可讀`：用 `ThemeData.dark()` 與 E-Ink 的色彩，計算前景與背景的 WCAG 對比，皆 ≥ 4.5。
  - `prepareEntryHtml` 注入：完整文件時覆寫樣式位於字典自己的 `<style>` 之後、`</head>` 之前；片段輸入時出現在補出的 `<head>` 內；`overrideCss == null` 時輸出與現行完全相同（回歸）。
  - `詞條寫死顏色`：輸入含 `<font color="#000">`、`bgcolor="#fff"`、`style="color:#000;background:#fff"`，輸出的覆寫樣式仍在其後（行內樣式靠 `!important` 蓋過，單元測試只確認規則存在與順序）。

- [ ] **Step 2: 執行確認失敗**
  Run: `cd app && flutter test test/dictionary/mdx_theme_override_test.dart test/dictionary/mdx_html_prepare_test.dart`
  Expected: FAIL。

- [ ] **Step 3: 實作**上述簽章。色碼轉換用 `Color` 的 RGB 通道取十六進位；`mdx_html_prepare.dart` 檔頭註解「刻意不處理 `<link>`／CSS／配色」改為指向 Task 2 與本 Task 的位置。

- [ ] **Step 4: 執行確認通過**（同 Step 2 指令）Expected: PASS。

- [ ] **Step 5: Commit**
  ```bash
  git add app/lib/dictionary app/test/dictionary
  git commit -m "feat(epic-63): Issue 6b 深色與 E-Ink 配色覆寫樣式"
  ```

---

### Task 5：`MdxEntryView` 與面板接線

**Files:**
- Modify: `app/lib/screens/widgets/mdx_entry_view.dart`、`app/lib/screens/widgets/dictionary_lookup_sheet.dart`
- Test: `app/test/screens/widgets/mdx_entry_view_test.dart`、`app/test/screens/widgets/dictionary_lookup_sheet_test.dart`

**Interfaces:**
- Consumes: Task 1、3、4 的型別與函式。
- Produces:
  - `MdxEntryViewConfig` 新增選用欄位 `Future<MdxResource?> Function(String url)? resolveResource` 與 `MdxColors? colors`。
  - `MdxEntryView.decideRequest` 改為 `static Future<MdxRequestDecision?> decideRequest(String url, {Future<MdxResource?> Function(String url)? resolveResource})`：`data:` 回 `null`；解析到資源回 `statusCode 200`＋位元組＋`contentType`；其餘（含 `resolveResource` 為 `null`、丟例外、`http(s)` 非 `dict.local`）回 404 空內容。`MdxRequestDecision` 新增 `Uint8List? bytes`、`String contentType`（預設 `text/plain`）。
  - `DictionaryLookupSheet` 新增選用參數 `Future<MdxResource?> Function(String sourceId, String url)? readMdxResource`；`show` 傳 `service.readMdxResource`。
  - **`colors` 與 `resolveResource` 在 `_mdxEntryView` 組裝 `MdxEntryViewConfig` 時綁定**：取 `Theme.of(context)` 與 `widget.isEinkMode` 呼叫 `mdxColorsFor`；`resolveResource: (url) => widget.readMdxResource?.call(outcome.providerId, url)`（`readMdxResource` 為 `null` 時整個 `resolveResource` 為 `null`）。這樣測試用的 `mdxEntryViewBuilder` 收到的 `config` 也是完整的。`_buildDefaultMdxEntryView` 維持 `(context, config) => MdxEntryView(config: config)`，不改。
  - `_MdxEntryViewState.didUpdateWidget`：`html` **或 `colors`** 任一不同就呼叫 `_loadHtml()`（面板開著時切換深淺色或 E-Ink，畫面要跟著換）。

- [ ] **Step 1: 寫失敗測試**：
  - `decideRequest`：`data:` 回 `null`；`https://dict.local/pic/a.png` 有資源 → 200、`contentType == 'image/png'`、位元組相同；資源回 `null` → 404；`resolveResource` 丟例外 → 404 不丟；`https://evil.example/a.png`、`file:///x`、`http://dict.local/x` → 404 且**不呼叫** `resolveResource`；`resolveResource == null` → 404。
  - `config 帶 colors 時 prepare 結果含覆寫樣式`；`colors == null` 時不含。
  - `colors 變更會重新載入`：同一個 `MdxEntryView`、`html` 不變、`colors` 從 `null` 換成深色，`_loadHtml` 被觸發（用 `onWebViewCreated` 取得的 controller 替身或載入計數觀察）；`colors` 相等（兩個相同欄位的實例）時不重載。
  - 面板：`mdxEntryViewBuilder` 的測試替身收到的 `config.resolveResource` 非 null，呼叫它會以分段的 `providerId` 與網址呼叫 `readMdxResource`；深色主題的 `config.colors` 非 null，淺色且非 E-Ink 為 null，E-Ink 非 null；`readMdxResource == null` 時 `config.resolveResource` 為 null。
  - `200 的回應不帶 contentEncoding`：`decideRequest` 回傳的決策轉成 `WebResourceResponse` 時，200 的 `contentEncoding` 為 `null`、`headers` 含 `Content-Type`；404 維持 `text/plain` 與 `utf-8`。
  - 回歸：6a 既有的 `decideNavigation`、手勢、返回堆疊測試全數通過。

- [ ] **Step 2: 執行確認失敗**
  Run: `cd app && flutter test test/screens/widgets/mdx_entry_view_test.dart test/screens/widgets/dictionary_lookup_sheet_test.dart`
  Expected: FAIL。

- [ ] **Step 3: 實作**。`shouldInterceptRequest` 回傳的 `WebResourceResponse`：200 時 `contentType` 用資源型別、`statusCode: 200`、`reasonPhrase: 'OK'`、`headers: {'Content-Type': ...}`，**`contentEncoding` 不給（`null`）**——它在 Android 是傳輸壓縮編碼（`Content-Encoding`），不是字元集，二進位圖片帶 `utf-8` 會讓部分 WebView 拒絕渲染（`foliate_reader_view.dart` 的圖片與字型攔截也不帶）；404 維持現有格式（`text/plain`、`utf-8`）。`_loadHtml` 與 `initialData` 都要帶 `overrideCss`。更新檔頭註解中「圖片與外部 CSS 的實際回傳是 Issue 6b」「`blockNetworkLoads` 留待 Issue 6b」兩段。**`blockNetworkLoads` 不在本 Task 啟用**，真機驗證放 Task 8。

- [ ] **Step 4: 執行確認通過**（同 Step 2 指令；另跑 `cd app && node tool/check_l10n_hardcoded_strings.js`）Expected: PASS。

- [ ] **Step 5: Commit**
  ```bash
  git add app/lib/screens/widgets app/test/screens/widgets
  git commit -m "feat(epic-63): Issue 6b MDX 詞條 WebView 回傳 mdd 圖片並套用配色覆寫"
  ```

---

### Task 6：面板 E-Ink 外框與設定畫面說明

**Files:**
- Modify: `app/lib/screens/widgets/eb_sheet_shell.dart`、`app/lib/screens/dictionary_settings_screen.dart`、四份 ARB
- Test: `app/test/screens/widgets/eb_sheet_shell_test.dart`、`app/test/screens/dictionary_settings_screen_test.dart`

**Interfaces:**
- Produces: `EBSheetShell` 在 `isEinkMode: true` 時，最外層有 Key `eb_sheet_shell_eink_border` 的 `DecoratedBox`，邊框為上、左、右各 2 px、顏色 `colorScheme.outline`，無 `boxShadow`；`isEinkMode: false` 時沒有該元件。`EBSheetShell.show` 在 `isEinkMode: true` 時傳 `elevation: 0` 與 `shape: const RoundedRectangleBorder()`（直角、無陰影）：Material 3 的底部面板預設有陰影與頂部圓角，只加內層邊框會留下陰影，且非對稱邊框不能搭圓角；`isEinkMode: false` 時兩者維持 `null`（沿用預設）。設定畫面新增 Key `dictionary_mdx_limit_note` 顯示 `dictionaryMdxLimitNote`（有無字典、載入失敗三種狀態都顯示，比照 Issue 7 線上區塊的做法）。

- [ ] **Step 1: 寫失敗測試**：
  - `E-Ink 時有外框`：找到 `eb_sheet_shell_eink_border`，其 `BoxDecoration.border` 的上、左、右寬度為 2、`boxShadow` 為 `null`。
  - `非 E-Ink 沒有外框元件`。
  - `E-Ink 面板無陰影、直角`：以 `EBSheetShell.show` 開面板，找到的 `BottomSheet` 其 `elevation == 0`、`shape` 為 `RoundedRectangleBorder` 且 `borderRadius` 為 `BorderRadius.zero`；非 E-Ink 時 `elevation` 與 `shape` 沿用主題預設（不是我們指定的值）。
  - `標題、把手、關閉鍵仍在，`ConstrainedBox` 最大高度仍為螢幕 85%（回歸）。
  - 設定畫面：說明文字存在，三種狀態皆顯示；`find.text` 對應 zh-TW 文案。
  - 既有用到 `EBSheetShell` 的測試（`book_action_sheet`、筆記面板、字典面板）：只跑 `grep -rln "EBSheetShell" app/test` 找到的檔案，確認通過。

- [ ] **Step 2: 執行確認失敗**
  Run: `cd app && flutter test test/screens/widgets/eb_sheet_shell_test.dart test/screens/dictionary_settings_screen_test.dart`
  Expected: FAIL。

- [ ] **Step 3: 實作**。ARB 四份加 `dictionaryMdxLimitNote`（zh-TW 見上表；zh-CN、en 各自翻譯，`@key` 附說明）。執行 `cd app && flutter gen-l10n`。

- [ ] **Step 4: 執行確認通過**（同 Step 2 指令加上 `grep` 找到的 `EBSheetShell` 測試檔；另跑 `node tool/check_l10n_hardcoded_strings.js`）Expected: PASS。

- [ ] **Step 5: Commit**
  ```bash
  git add app/lib app/test
  git commit -m "feat(epic-63): Issue 6b E-Ink 面板外框與 MDX 已知限制說明"
  ```

---

### Task 7：選取控點不蓋住面板（含真機探測）

**Files:**
- Modify: `app/lib/reader/foliate_reader_view.dart`、`app/lib/screens/reader_screen.dart`
- Test: `app/test/screens/reader_screen_test.dart`（沿用既有 `clearSelection` 的測試作法）

**Interfaces:**
- Produces: `FoliateReaderView.setSelectionHandlesHidden(GlobalKey<State<FoliateReaderView>> key, bool hidden)`（靜態，仿 `clearSelection` 的寫法）。`ReaderScreen._handleLookupPressed` 開面板前呼叫 `true`，`finally` 呼叫 `false`。選取範圍與 `AnnotationToolbar` 不得被清除。

- [ ] **Step 1: 真機探測（先於實作）**：在 `FoliateReaderView` 用 `InAppWebViewController.clearFocus()`（`app/patches/flutter_inappwebview_android/.../in_app_webview_controller.dart:2245`）做暫時實驗，裝置為 WAVE E-Ink 機。**控制器上沒有 `requestFocus()`**（只有 `requestFocusNodeHref()`，用途不同），還原焦點的路徑要在探測時一併找出，候選依序：Flutter 端 `FocusNode.requestFocus()`、`FocusScope.of(context).requestFocus(...)`、關面板後重新送出原選取（如果前兩者都無法讓控點回來）。判定標準：開字典面板時控點消失；關閉面板後控點與選取範圍都回來；`AnnotationToolbar` 的劃線、備註、複製仍可用。把結果（成功或失敗、做法、現象）寫進 `reviews/`（不進版控）。
  - **失敗時**（含找不到可靠的還原路徑）：不做 Step 2 到 Step 5，在 `issues.md` 檔尾「後續項目」第 2 項補上探測結果與下一步方向，本 Task 結束。
  - `main.js` 不能改；只能用 Dart 端與既有 WebView 控制介面。

- [ ] **Step 2: 寫失敗測試**：點「查字典」開面板時 `setSelectionHandlesHidden(true)` 被呼叫一次；正常關閉、系統返回鍵關閉、`DictionaryLookupSheet.show` 丟例外三種情況，`false` 都被呼叫一次；選取文字與工具列狀態在整個過程不變；`_lookupSheetOpen` 擋重複點擊的既有測試仍通過。

- [ ] **Step 3: 執行確認失敗**
  Run: `cd app && flutter test test/screens/reader_screen_test.dart`
  Expected: FAIL。

- [ ] **Step 4: 實作**探測確認可行的做法；還原放在 `finally`，且先檢查 `mounted`。

- [ ] **Step 5: 執行確認通過**（同 Step 3 指令）Expected: PASS。

- [ ] **Step 6: Commit**
  ```bash
  git add app/lib app/test
  git commit -m "feat(epic-63): Issue 6b 查字典面板開啟時隱藏選取控點"
  ```

---

### Task 8：整合測試、全套驗證與真機確認

**Files:**
- Modify: `app/integration_test/dictionary_mdx_test.dart`
- 需要人類提供：2 至 3 本含圖片的真實 MDX／MDD（只作本機測試，放 `tmp/dictionary/`，不進版控）

- [ ] **Step 1: 寫整合測試**（真機，沿用 6a 的 `_waitFor`／攔截回呼作法，不用 `evaluateJavascript`）：
  - `圖片在 JavaScript 關閉下顯示`：用 `images.mdx`／`images.mdd`，詞條 `pic` 的 `<img src="pic/a b.png">` 被攔截並回 200、`image/png`（以 `onRequestIntercepted` 觀察）。
  - `路徑帶空白與子目錄的圖片`：`pic/a b.png`、`pic/sub/c.png` 各回 200。
  - `找不到的圖片與 favicon 回 404，不連網`。
  - `深色與 E-Ink 下可讀`：以 `colors` 注入後，頁面標題讀取正常，且覆寫樣式存在於載入的文件（用 6a 既有的只讀原生狀態的方式；若無法直接讀，改比對傳給 WebView 的 HTML 字串）。
  - `blockNetworkLoads` 探測：在測試內暫時啟用，確認 `data:` 初始文件與攔截回應仍可載入；可行才在 `MdxEntryView` 啟用並補一個單元測試固定住設定值。**任何渲染異常（含圖片或初始文件載不出來）就維持關閉**，並在 `mdx_entry_view.dart` 註解記下現象。

- [ ] **Step 2: 靜態檢查**
  Run: `cd app && flutter analyze && node tool/check_l10n_hardcoded_strings.js && node tool/check_integration_keys.js`
  Expected: `No issues found!`；兩支腳本無錯誤。

- [ ] **Step 3: 完整測試（本計畫唯一一次）**
  Run: `cd app && flutter test`
  Expected: 全數通過。6a 曾記錄 `test/reader/pdf_reader_view_filters_test.dart` 的兩個 PDF 加粗測試在 `main` 上失敗；若這次又出現，先單獨在 `main` 跑該檔確認是否同樣失敗，一致就在此註明、不在本 Issue 處理；不一致就是本分支的回歸，要修。

- [ ] **Step 4: 驗收對照**（逐項填寫結果）
  - 驗收 18：Task 3「讀到圖片」「子目錄」、Task 5「decideRequest」、Task 8 圖片整合測試。
  - 驗收 19：Task 4「對比可讀」、Task 8 深色與 E-Ink 整合測試。
  - 驗收 25：Step 5 第 6 項實測。
  - 回歸：驗收 27（既有測試）、28（主庫仍是 `version: 28`）、29（`main.js` 無改動）：`git diff main --stat -- app/android/app/src/main/assets/foliate/main.js` 為空。
  - 後續項目兩項：Task 6（外框）、Task 7（控點，或失敗記錄）。

- [ ] **Step 5: 真機確認（請人類執行或在場）**，裝置：WAVE E-Ink 機。
  1. 匯入含圖片的真實 MDX／MDD（例如牛津），查詞：圖片顯示；JavaScript 關閉下不需點擊。
  2. 匯入有獨立 CSS 的字典（教育部、古漢語已有 `ghychyz.css`）：排版接近字典原樣；沒有 CSS 時仍可讀。
  3. 切到深色主題查詞：文字與背景對比可讀，詞條寫死的白底被蓋掉。
  4. E-Ink 模式查詞：黑字白底、連結有底線、無動畫；面板有外框。
  5. 選字後點「查字典」：選取控點不蓋在面板上（Task 7 探測成功時）；關閉面板後選取範圍與劃線工具列仍在。
  6. 開啟 100 MB 等級 MDX（`tmp/dictionary/large_cjk_400k.mdx` 或人類提供的真實檔）：記憶體增量小於 50 MB（沿用 6a 的量測方式與 `PATCH.md` 的基準）。
  7. 設定畫面看得到「已知限制」說明。

- [ ] **Step 6: 回報**：把結果寫進 `reviews/`（不進版控）。通過後等人類決定合併，之後才更新 `issues.md` 狀態與 `docs/epics.md` 備註。

---

## 交給人類

- 提供 2 至 3 本含圖片的真實 MDX／MDD 作驗收（牛津 9 這類，與其 `.css`）。
- 驗收 31（沒有取自 AGPL／GPL 專案的程式碼）由人類在 Issue 8 最終確認。

## 交給後續

- **Issue 8：** 授權頁、隱私頁、l10n 收尾、整合測試補齊。
- **後續優化（不在 Phase 1）：** `.mdd` 分卷（`name.1.mdd`）；放在 `.mdd` 內的 `.css`；`sound://` 音訊；字典名稱過長時自動截短（6a 已記）。

---

## 自我檢查

- **Spec 覆蓋：** §3.6 圖片（Task 1、3、5）、外部 `.css`（Task 2）、深色與 E-Ink 配色（Task 4、5）、已知限制說明（Task 6）；§7 整合測試的圖片與配色項目（Task 8）；驗收 18、19、25（Task 8 Step 4）；後續項目兩項（Task 6、7）。
- **與 spec 的差異：** 新增單一資源 8 MiB 上限與只服務圖片類型（spec 只列了圖片型別，沒寫上限）；Task 7 因技術不確定，採「先探測、失敗就不出貨」。
- **型別一致：** `MdxResource`、`mddKeysForUrl`、`imageContentTypeForKey`、`kMdxResourceMaxBytes` 在 Task 1 定義，Task 3、5 使用同名；`MdxColors`／`mdxColorsFor`／`mdxOverrideCss` 在 Task 4 定義，Task 5 使用；`readResource`／`readMdxResource` 在 Task 3 定義，Task 5 使用。
- **比例：** 計畫只有簽章、測試名稱與斷言、指令，沒有函式本體。
