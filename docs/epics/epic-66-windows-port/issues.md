# Epic 66 — Windows 版移植：工單清單 (Issues)

設計依據是 `epic.md`「Discovery 決策」。Issue 1 過關後，才展開後續 Issue。

| Issue | 標題 | 依賴 | 狀態 | PR |
|---|---|---|---|---|
| 1 | 技術驗證：啟用 `windows/`，確認 7 項過關條件，輸出驗證報告 | 無 | ⚪ 未開始 | — |

## Issue 1 過關條件

全部通過才往下做。第 1 項失敗就停下來，重新評估整個計畫；其餘失敗各自討論。

1. EPUB 在 WebView2 能開，直排與橫排都正確。
2. 滑鼠拖曳能選字，並出現劃線工具列。
3. PDF 能開，頁數正確。
4. `HeadlessInAppWebView` 能用 foliate-js 讀出書名、作者、`identifier`、封面。
5. 字典 MDX 的 WebView 能擋住所有外部網路（Android 靠 `shouldInterceptRequest`，Windows 要找對應做法）。
6. SQLite FTS5 搜尋可用。
7. `flutter_secure_storage` 能存取同步憑證。

同時產出：

- WebView2 是否有請求攔截或虛擬網域對應（決定送書方式，見 `epic.md` 決策 6）。
- foliate-js 與 Readium 的 metadata 逐本對比表（決定是否統一，見決策 7）。

## 後續 Issue（待 Issue 1 結果決定）

- 送書給 WebView（伺服器或原生對應）。
- Metadata 背景解析。
- 檔案匯入與資料夾匯入（`folder_picker` 的 Windows 版）。
- 鍵盤快捷鍵與 F11。
- 平台專屬功能的隱藏。
- Windows 版 `integration_test` 冒煙測試。
- 免安裝 zip 打包。
