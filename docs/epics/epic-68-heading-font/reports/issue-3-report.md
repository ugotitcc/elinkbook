# Issue 3 目視確認報告：標題字型 UI

- 日期：2026-11-14
- 環境：Windows 11；分支 `feat/epic-68-heading-font`；測試基準 commit 58ae5123（Task 3 完成時）；Flutter 3.47.9；Node v26.13.0
- 實作者是否能互動操作桌面 App：**否**。本次由無圖形介面的代理人在終端機執行，無法啟動 `flutter run -d windows` 後操作視窗、點選下拉、觀看字形或截圖。以下以 harness 與 widget／端到端測試作為替代證據，「字形是否真的變化」與「PDF／FXL 面板實機外觀」皆**未驗證**。

## 測試書籍
| 書籍 | 來源 | 含 h1–h6 | 備註 |
|---|---|---|---|
| 未開啟真實書籍 | — | — | 無法互動操作桌面 App |
| 未開啟 PDF | — | — | 同上 |
| 未開啟 FXL EPUB | — | — | 同上（widget 測試以 `FxlSettingsSheet` 單獨驗證） |

## 檢查項目
| # | 項目 | 預期 | 結果 | 證據 |
|---|---|---|---|---|
| 1 | 流式 EPUB 版面設定「文字」分頁顯示「主字型」與「標題字型」兩個下拉 | 兩個下拉，標籤正確，下載提示仍只一個 | 未驗證（目視）；widget 測試通過 | `reader_settings_sheet_test.dart` group「標題字型下拉（epic-68 Issue 3）」13 個測試（標籤、Key、下載提示只一個且位於下拉之後、三語系文案） |
| 2 | 主字型 A、標題字型 B，章名字形為 B | 章名為 B，內文為 A | 未驗證（目視）；渲染規則由 harness 證明 | `node app/tool/foliate_touch_harness/scenario-heading-font.mjs` A2、A3 PASS（只比對 computed `font-family`，不載入真實字型）；端到端測試證明 UI→偏好→`FoliateReaderView.headingFontFamily` |
| 3 | 章名內含 `span`／`a` | 內層同為標題字型 | 未驗證（目視）；harness PASS | harness A2：`h1>span`、`h1>a`、`h2>a>span` 全為標題字型 |
| 4 | 改回「跟隨主字型」 | 章名恢復為主字型，不需重開書 | 未驗證（目視）；測試通過 | harness C、C2 PASS；端到端測試 `onChanged(null)` 後偏好與 `FoliateReaderView.headingFontFamily` 皆為 null |
| 5 | 主字型「使用書本內建字型」＋標題字型 B | 章名 B，內文為書本字型 | 未驗證（目視）；harness PASS | harness D、D2 PASS |
| 6 | 「停用書本 CSS」 | 標題字型仍勝出 | 未驗證（目視）；harness PASS | harness B PASS |
| 7 | 關書再開 | 標題字型保留 | 未驗證 | 偏好持久化屬 Issue 1（資料層測試），本張未做實機確認 |
| 8 | 刪除標題字型使用的自訂字型 | 記錄現況 | 未驗證 | 屬 Issue 4；widget 測試證明不可用字型時下拉顯示「跟隨主字型」且不改寫偏好 |
| 9 | PDF 版面設定沒有字型下拉 | 無下拉 | 未驗證（實機外觀）；widget 測試通過 | `pdf_settings_sheet_test.dart` 負向測試 |
| 10 | FXL 版面設定沒有字型下拉 | 無下拉 | 未驗證（實機外觀）；widget 測試通過 | `fxl_settings_sheet_test.dart` 既有測試補兩個 Key `findsNothing` |
| 11 | 窄視窗／E-Ink 版面 | 無溢位、可操作 | 未驗證（目視）；widget 測試通過 | 412 寬＋過長自訂字型名稱無 overflow；E-Ink 模式可顯示 |

## 發現與限制
- 無法互動操作桌面 App，故 1–11 皆無目視證據；上表「通過」僅指替代證據通過，不等於目視確認。
- 兩個下拉左緣因標籤寬度不同（「主字型」與「標題字型」）可能不齊，未目視評估是否可接受，留待人工確認。
- 面板高度：「版面設定面板高度…」測試實測面板高度新增下拉前後皆為 988.0（門檻 < 1000，餘裕僅 12）；「文字」分頁內容在 738 的 viewport 內無需捲動，非最高分頁，故新增一列不影響面板高度。
- 審查 M8（僅記錄）：宣告 `isFixedLayout=false` 的 CBZ 理論上可開啟流式面板並看到無效果的標題字型下拉；渲染端已保證 CBZ 不套用標題字型（Issue 2，有測試），此為 Issue 2 既有邊角，不在本張處理。

## 結論
**Issue 3 目視確認未完成。** UI 邏輯、偏好寫入、渲染規則由 widget／端到端／harness 測試證明；字形實際變化與 PDF／FXL 面板實機外觀須由使用者或後續真機／桌面操作確認。
