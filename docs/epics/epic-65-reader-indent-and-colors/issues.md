# Epic 65 — 版面設定增強：首行縮排與自訂閱讀顏色：工單清單 (Issues)

2 個 Issue，皆為垂直切片。設計依據是 `epic.md`「Discovery 決策」。

| Issue | 標題 | 依賴 | 狀態 | PR |
|---|---|---|---|---|
| 1 | 首行縮排：`BookReaderPrefs.firstLineIndent`、SQLite v29、預設集 JSON、`main.js` 規則、「呈現」分頁開關與滑桿 | 無 | ✅ 已合併 | #372 |
| 2 | 自訂閱讀顏色：各佈景獨立的背景色與文字色（RGB 滑桿加色碼輸入）、E-Ink 不套用、新增「佈景」分頁、對比警告、各自還原預設 | 無（建議 Issue 1 之後做，避免同時改版面設定面板） | ✅ 實作完成，WAVE 真機通過，待合併 | — |
| 3 | 縮排排除置中與無文字段落：`main.js` 新增 `markNoIndentParagraphs`，縮排 CSS 改為 `p:not([data-elink-no-indent])`；使用者選「文字對齊」時不做置中排除（來源：Issue 1 WAVE 實測；先於 Issue 2 執行） | Issue 1 已合併 | ✅ 已合併（PR #373） | — |

## Issue 1 單元測試要求

- 模型：`BookReaderPrefs` 的 `firstLineIndent` 序列化／反序列化往返；`null` 與有值；舊資料（無此欄位）讀成 `null`。
- 資料庫：v28→v29 升級新增欄位，既有資料不遺失；單書偏好寫入與讀回。
- 版面預設集：JSON 含 `firstLineIndent`；舊預設集（無此欄位）讀成 `null`；套用預設集後單書偏好正確。
- JS 規則：開啟時產生 `p { text-indent: Nem !important; }`；`null` 時不產生；與「停用書本 CSS」同時生效。
- 面板：開關打開預設 2 字；滑桿 0～4 字、步進 0.5、+/- 按鈕；關閉後寫入 `null`；E-Ink 模式使用步進器。
- 不套用範圍：PDF、固定版面不顯示此控制項或不生效。

## Issue 2 單元測試要求

- 顏色轉換與色碼解析：`#RRGGBB` 與 RGB 三值互轉；無效輸入不套用。
- 各佈景獨立儲存與讀回；沒設定時退回佈景原本顏色。
- E-Ink 模式不套用自訂色。
- 面板：新增「佈景」分頁（順序 文字｜邊界｜呈現｜佈景｜預設集）；背景與文字兩區塊全展開；滑桿與色碼輸入雙向即時同步；各自的「還原預設」只清除目前佈景的那一個顏色；輸入無效時標紅且不寫入；對比低於 3:1 顯示警告但仍套用。
- E-Ink 模式：「佈景」分頁整頁停用並顯示說明。
- 閱讀器背景色只影響閱讀器頁面，不影響其他畫面的 `scaffoldBackgroundColor`。
- `ReaderScreen`：自訂背景色／文字色傳給 `FoliateReaderView`；頁首／頁尾文字與載入遮罩跟著變；FXL 與 E-Ink 不套用。

## Issue 3 單元測試要求

- 純 `main.js` 變更，本機沒有 Node 時以探針 EPUB 在 WAVE 驗證；有 Node 時新增並實際跑 `app/tool/foliate_touch_harness/scenario-first-line-indent-exclusions.mjs`。
- 情境：一般段落縮排；行內置中、`align="center"`、書本 class 置中的段落不縮排；空段落、只有圖片、只有 `<br>` 的段落不縮排；`prefs.textAlign` 有值時置中段落仍縮排（空段落仍排除）；縮排關閉時沒有標記屬性；`firstLineIndent: 0` 時 computed `text-indent` 為 `0px`；偏好切換後已載入章節重新標記；翻到新章節同樣有標記。
