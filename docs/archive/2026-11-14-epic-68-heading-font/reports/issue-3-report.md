# Issue 3 目視確認報告：標題字型 UI

- 初版日期：2026-11-14（以 harness 與 widget 測試為替代證據，當時無法操作桌面 App）
- 補驗日期：2026-11-14（在 Windows 11 桌面版實機渲染下補做目視確認，見下）

## 環境（補驗）
- Windows 11 Home 10.0.26300；Flutter 3.47.9；WebView2 Runtime 157.0.4341.46
- 基準：main（含 epic-68 全部程式）；專案路徑未映射 W:\（路徑長度未造成建置問題，直接建置成功）
- 自訂字型（以本機檔案路徑註冊，Windows 端 `loadWindowsFileBytes` 載入）：
  - 標楷體：`C:\Windows\Fonts\kaiu.ttf`（家族名 `VisKai`）
  - 黑體：`C:\Windows\Fonts\NotoSansTC-VF.ttf`（家族名 `VisSans`）
- 方法：暫時性整合測試（真實 SQLite 記憶體庫、真實 `ReaderScreen`、真實 `ReaderSettingsSheet` 操作兩個下拉，已刪除、未進版控），命令
  `flutter test integration_test/<暫時測試>.dart -d windows`；另一支 PowerShell 腳本（放 scratchpad）在每個步驟由測試寫標記檔後，以 `PrintWindow`（flag 2）對 elinkbook 視窗截圖（1280x720，Windows 視窗實際大小）。以 Read 工具實際檢視截圖。
- 測試書：自製最小 EPUB3（含 `h1`、`h1>span`、`h1>a`、`h2>a>span` 與三段內文，無書本 CSS）；另用 `sample_multi_page.pdf`、`sample_fixed_layout.epub`。
- 截圖（檔名前綴 `issue3-`）僅保存於執行者本機，**未納入版控**；下表「證據」欄的檔名僅供對照，倉庫內查無對應檔案。

## 檢查項目
| # | 項目 | 結果 | 證據 |
|---|---|---|---|
| 1 | 流式 EPUB「文字」分頁有「主字型」與「標題字型」兩個下拉，下載提示只一個 | **通過（目視）**；另發現左緣未對齊（見發現） | `issue3-01_sheet_two_dropdowns.png`：兩個下拉標籤正確，提示「到『字型管理』下載更多字型」只出現一次、位於下拉之後 |
| 2 | 主字型 A、標題字型 B，章名為 B、內文為 A | **通過（目視）**：章名為楷體、內文為非楷體黑體 | `issue3-03b_heading_kai.png`（主字型選黑體、標題選楷體）；對照 `issue3-02b_main_sans_heading_follow.png`（標題跟隨時與內文同為黑體）。限制：Windows 上「主字型選 NotoSansTC」與未設定時的 WebView 預設中文字型像素完全相同（00 與 02b 截圖位元組一致），故「主字型 A 確實套用」無法由像素獨立證明，僅證明標題與內文字形不同 |
| 3 | 章名內含 `span`／`a` | **通過（目視）**：純標題、`h1>span`、`h1>a`（有底線）、`h2>a>span` 四行皆為楷體 | `issue3-03b_heading_kai.png` |
| 4 | 改回「跟隨主字型」恢復為主字型、不需重開書 | **通過（目視）**：標題立即恢復為與內文相同的黑體，未重開書 | `issue3-04_heading_follow_again.png`（與 `issue3-02b` 同字形；捲動位置不同） |
| 5 | 主字型「使用書本內建字型」＋標題字型 B | **通過（目視）**：章名楷體、內文為預設字型 | `issue3-05_main_book_heading_kai.png` |
| 6 | 「停用書本 CSS」標題字型仍勝出 | **部分**：開啟該開關後章名仍為楷體（目視），但測試書本身無任何書本 CSS 字型規則，無法在實機證明「勝過書本 CSS」；該規則仍由 harness B（`scenario-heading-font.mjs`）證明 | `issue3-06_disable_book_css_heading_kai.png` |
| 7 | 關書再開，標題字型保留 | **通過（目視）**：卸載 `ReaderScreen` 後重建，章名仍為楷體，重開後面板亦顯示偏好（`07_reopened` 與 `05` 位元組一致）。注意是同一進程內重建而非重啟 App，偏好經真實 SQLite 讀回 | `issue3-07_reopened.png` |
| 8 | 刪除標題字型使用的自訂字型 | **通過（現況記錄）**：以 `deleteAndResetUsage` 刪除後重開，偏好 `headingFontFamily=null`、`fontFamily=null`，面板顯示「使用書本內建字型／跟隨主字型」，章名為跟隨狀態，無錯誤 | `issue3-08b_after_delete_sheet.png`；偏好以測試內查詢確認 |
| 9 | PDF 版面設定沒有字型下拉 | **部分**：PDF 面板（顯示／裁切分頁）可見部分無字型下拉，且整棵 Widget 樹查詢兩個下拉 Key 皆 0；但 720 高視窗下面板被截斷，未看到完整面板 | `issue3-p09_pdf_sheet.png` |
| 10 | FXL 版面設定沒有字型下拉 | **部分**：同上（漫畫版面設定，可見部分為雙頁／翻頁方向／簡繁轉換，樹查詢 0） | `issue3-p10_fxl_sheet.png` |
| 11 | 窄視窗／E-Ink 版面無溢位 | **未驗證**：見下 | 無有效截圖 |

## 發現與限制
- **兩個下拉左緣未對齊**（目視確認）：「主字型」下拉左緣約在 x=503，「標題字型」約在 x=521（標籤寬度不同、Row 以固定 12px 間距接 Expanded），差約 18px。是否可接受請人工決定；未修改程式。
- 項目 11 未驗證：嘗試把真實視窗縮成 440x860，Flutter 內容未跟著重排（內容右側被視窗裁掉），再搭配 `tester.view.physicalSize` 覆寫後畫面變成上一本 PDF 的殘影，兩種做法截圖皆無效，不採用。窄版／E-Ink 溢位仍只有初版的 widget 測試證據（412 寬＋過長名稱無 overflow）。過長名稱在 1280 寬視窗的呈現也未單獨截圖。
- 項目 9、10 只看到面板上半部（視窗高 720）。
- 主字型是否確實套用無法由像素獨立證明（見項目 2）。
- 以上為 Windows 11／WebView2 桌面版結果；Android 真機（B78CW2508006423 未授權）與 E-Ink 實機未測。
- 面板高度：「版面設定面板高度…」測試實測面板高度新增下拉前後皆為 988.0（門檻 < 1000，餘裕僅 12）。
- 審查 M8（僅記錄）：宣告 `isFixedLayout=false` 的 CBZ 理論上可開啟流式面板並看到無效果的標題字型下拉；渲染端已保證 CBZ 不套用標題字型（Issue 2，有測試）。

## 初版替代證據（保留）
- `reader_settings_sheet_test.dart` group「標題字型下拉（epic-68 Issue 3）」13 個測試；`pdf_settings_sheet_test.dart`、`fxl_settings_sheet_test.dart` 負向測試。
- `node app/tool/foliate_touch_harness/scenario-heading-font.mjs` A、A2、A3、B、C、C2、D、D2 PASS（只比對 computed `font-family`）。

## 結論
**部分完成。** 在 Windows 桌面實機渲染下，項目 1–5、7、8 已目視通過；6、9、10 部分驗證（見上）；11（窄視窗／E-Ink）仍未驗證；Android 真機與 E-Ink 實機未測。另發現兩下拉左緣約差 18px 未對齊，待人工決定。
