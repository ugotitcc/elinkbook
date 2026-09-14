# ADR 0031：簡繁轉換改用 OpenCC 原始字元表雙端各自輕量實作，不 vendor `opencc-js` 套件（`epic-42-text-conversion`）

## 狀態

已採納

## 背景

`epic-42-text-conversion` Discovery 原案規劃 vendor `nk2028/opencc-js`（npm 套件名 `opencc-js`）的建置好 UMD bundle，並規劃「Dart 端（書架、全庫搜尋、目錄面板、書籤清單等純 Flutter 渲染介面）也呼叫 `opencc-js` 的純字串轉換函式」。

2026-09-15 審查（`docs/epics/epic-42-text-conversion/reviews/review-epic-and-design.md` C-1）指出：`app/pubspec.yaml` 只有 `flutter_inappwebview`，專案未引入任何獨立的 headless JS 引擎（如 `flutter_js`／`quickjs`）；Dart 在 Android 上為 AOT 原生編譯執行，Dart VM 無法直接 import 或呼叫 JavaScript 檔案；`LibraryScreen`（書架）、`LibrarySearchScreen`（全庫搜尋）等畫面底層完全沒有 WebView 實例可供橋接。Discovery 原案「Dart 端也呼叫 `opencc-js`」在架構上不成立。

同時，[ADR 0030](./0030-text-conversion-character-level-for-cfi-safety.md) 已將轉換精細度定案為字元對字元 1:1 轉換，不再需要 `opencc-js` 的詞彙/片語/兩岸慣用詞字典與 `HTMLConverter`（該內建元件另有依賴 DOM `lang`/`xml:lang` 屬性匹配、對缺漏或非標準語系標籤的 EPUB 可能導致整本書不被轉換的疑慮，見同一份審查報告 I-3），函式庫需求因此大幅簡化。

## 決策

1. **唯一資料來源改為 OpenCC 專案最底層的字元對照表**（`STCharacters.txt`／`TSCharacters.txt`，純簡繁字元一對一映射，Apache-2.0 授權，寬鬆授權可直接 vendor）。
2. **JS 端（WebView）與 Dart 端各自基於同一份原始字元表資料，產生各自語言慣用格式的輕量查找表**（JS：物件字面量／`Map`；Dart：`Map<String, String>`），確保兩端轉換結果一致——不會出現「內文轉換結果」與「目錄/書架轉換結果」因字典不同而不一致的情況。
3. **兩端皆不使用 `opencc-js` 套件本身（含其 `HTMLConverter`）**，JS 端 DOM 走訪邏輯自行實作（見 ADR 0030 決策 2），不依賴語系標籤匹配。
4. **Vendoring 慣例比照 `readest/foliate-js`**（釘定版本、直接複製進版控、不引入 npm 建置管線），適用於原始字元表資料本身的引入方式。

## 曾考慮的替代方案

- **vendor `opencc-js` 完整套件，Dart 端設法呼叫**：技術上不可行（Dart AOT 無 JS 執行環境，專案未引入任何 headless JS 引擎），予以排除。
- **在書架/全庫搜尋等畫面動態啟動 Headless WebView 執行 JS 轉換以規避上一點**：單一 WebView 實例佔用 50–100MB 記憶體、初始化需數百毫秒，`evaluateJavascript` 恆為非同步 `Future`，書架 `ListView.builder` 渲染數百本書若逐筆 `await` IPC 會造成嚴重掉幀/卡頓/載入閃爍，予以排除。
- **JS 端與 Dart 端各自獨立手刻字典資料（各自從不同來源整理或手動維護）**：有轉換結果不一致的風險（同一本書在內文與目錄/書架顯示不同轉換結果），予以排除，改為共用單一原始資料來源。

## 後果

- `pubspec.yaml` 不需新增任何 headless JS 引擎依賴。
- `epic-42-text-conversion` `design.md` 第 4 點原規劃的 `opencc-js` vendoring 方式作廢，改為本 ADR 記錄的雙端共用原始字元表方案。
- Architecting／實作階段需要一支（或一次性執行的）轉換腳本，把原始字元表轉成 JS 與 Dart 兩種目標格式；兩份查找表須保持同步，資料來源更新時需要重新產生兩份，不得只更新其中一端。
- 相較原規劃的 `opencc-js` 子集 bundle（約 1.8–2MB 級距的詞彙字典），改用純字元表後 JS 端 vendor 檔案體積與 WebView JS Heap 佔用大幅降低，低階 E-Ink 裝置的記憶體壓力隨之緩解。

## 相關佐證

- [ADR 0030](./0030-text-conversion-character-level-for-cfi-safety.md)（1:1 字元轉換決策，是本 ADR 精簡函式庫需求的前提）
- `docs/epics/epic-42-text-conversion/design.md`
- `docs/adr/0011-epub-reflowable-migrate-to-foliate-js.md`（`foliate-js` vendoring 慣例先例）
- `app/pubspec.yaml`（現行依賴清單，確認無 headless JS 引擎）
