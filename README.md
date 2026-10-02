# elinkBook（易閱書）

<img src="assets/appicon_v2.jpg" alt="elinkBook App 圖示" width="120">

跨平台電子書閱讀器，核心差異化在於**繁體中文直排（Vertical Writing）排版的正確與高品質支援**——包含標點符號正確位置（破折號、引號）、避頭尾換行規則——並提供深度排版客製化與無縫跨裝置同步。

## 核心特色

- **排版方向**：依書本 CSS／中繼資料自動偵測直排或橫排，也可手動強制直排／強制橫排；直排時標點轉向置中、遵守避頭尾規則
- **深度版面客製化**：字體大小、字重、字距、行距、段落間距、四邊獨立邊距、文字對齊、翻頁模式（點擊翻頁／滾動翻頁）、螢幕方向鎖定、停用書本 CSS；每個數值型設定都有 +/- 微調按鈕，並支援版面設定預設集
- **可下載字型**：思源黑體、思源宋體、原俠正楷、台灣圓體、源流明體（皆為 SIL OFL 開源字型）；字型檔不打包進安裝檔，由使用者在字型管理下載後離線渲染，也可以上傳自訂字型
- **主題與 E-Ink 高對比模式**：預設（淺色）、深色、羊皮紙三種主題，加上可與任一主題同時開啟的 E-Ink 高對比模式（減少過渡動畫、避免殘影）
- **PDF 專業增強**：影像濾鏡（對比度、亮度、加粗）、智慧／手動裁切、Page-fit／Fit Width／1:1 顯示模式、橫向雙頁並列
- **書籤、劃線與備註**：劃線支援多色與螢光筆，統一側邊欄檢視，支援單筆與批次刪除、Markdown 導出
- **目錄、頁碼與全文檢索**：跨格式通用目錄、書內搜尋；書庫全文檢索可查書名、作者與書內內容
- **語音朗讀（TTS）**：朗讀時同步高亮目前唸到的句子
- **簡繁轉換**：閱讀時轉換書籍內容文字
- **圖書庫管理**：格狀／列表檢視、分類（可依資料夾名稱自動分類）、多種排序、批次操作
- **多元匯入來源**：本機檔案／資料夾、Google Drive、OneDrive（不依賴 Google Play Services）、Calibre 遠端書架、WiFi 傳書（同一個區網雙向傳書，對方不必安裝 App）
- **跨裝置雲端同步**：閱讀位置、劃線、備註、書籤自動同步（後端採用 PocketBase）；雲端位置與本機不一致時，先詢問使用者才跳轉
- **導覽與操作**：可自訂的 3×3 九宮格點擊熱區（直排時左右鏡像）、音量鍵翻頁、全螢幕模式
- **多語系介面**：正體中文、簡體中文、英文

## 支援格式

- ePub3（流式與固定版面 FXL）
- KF8／AZW3
- CBZ（漫畫壓縮檔）
- TXT（自動偵測編碼，含 UTF-8／UTF-16／Big5／GBK，並自動抽取章節）
- Markdown
- PDF

## 開發快速上手

所有指令都在 `app/` 目錄下執行：

```bash
flutter pub get
flutter analyze        # 提交前必須是 "No issues found!"
flutter test
flutter run
```

- 需要測試 Google Drive／OneDrive 的真實 OAuth 登入時，請參考 `app/config/cloud_oauth.example.json` 建立 `cloud_oauth.json`（不進版控），並加上 `--dart-define-from-file=config/cloud_oauth.json` 執行。
- 整合測試（`app/integration_test/`）必須在真實裝置或模擬器上執行；其他檢查工具請見 [`app/tool/README.md`](app/tool/README.md)。
- 架構說明、測試分層與開發流程（SDD）請見 [`CLAUDE.md`](CLAUDE.md)，UI 設計規範請見 [`DESIGN.md`](DESIGN.md)。
- 完整需求請見 [`docs/prd.md`](docs/prd.md)，Epic／Issue 進度請見 [`docs/epics.md`](docs/epics.md)，技術決策請見 [`docs/adr/`](docs/adr/)，領域用語請見 [`CONTEXT.md`](CONTEXT.md)。

## 目錄導覽

| 路徑 | 內容 |
|---|---|
| [`app/`](app/) | Flutter App 主程式 |
| [`docker/`](docker/) | PocketBase 同步後端（部署方式見 [`docker/README.md`](docker/README.md)） |
| [`fonts-cdn/`](fonts-cdn/) | 可下載字型的 Cloudflare R2＋Worker（部署方式見 [`fonts-cdn/README.md`](fonts-cdn/README.md)） |
| [`site/`](site/) | 產品官網、隱私權政策與服務條款 |
| [`store/`](store/) | Google Play 商店上架素材 |
| [`prototype/`](prototype/) | UI/UX 原型（權威版本為 `elinkbook_theme_prototype.html`） |
| [`docs/`](docs/) | PRD、Epic 看板與各 Epic 文件、ADR、研究報告 |

## 範圍外（Non-Goals）

- 不支援解除 DRM（如 Adobe DRM）
- 不提供電子書商店（採購／租閱）
- 不支援 PDF 內容編輯（文字／圖片修改）
- 不含完整社交平台功能，僅支援單向分享
