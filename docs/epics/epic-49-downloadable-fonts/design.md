# epic-49 可下載字型：設計（Discovery）

2026-09-25 `/grill-with-docs` 定案。題號對應當時的問答順序，方便回溯。

## 目標

內建字型的字型檔不再隨 APK 散布。使用者在「字型管理」畫面點某款字型的「下載」後，App 才下載該字型；下載後完全離線使用。

## 範圍

- 內建字型清單：思源黑體、思源宋體（原俠正楷、台灣圓體、源流明體目前以 `[字型停用]` 標記隱藏，恢復時同樣走下載機制）。
- 5 款全部可下載，**一款都不打包**（Q2、Q11）。
- 只提供 Regular 字重的單一檔案（思源兩款為可變字型 VF）。

## 領域概念

**可下載字型（Downloadable Font）**（Q3，已寫入 `CONTEXT.md`）：屬於內建字型清單，清單由 App 固定定義、不能改名；字型檔由使用者主動下載，下載後由 App 保管在私有目錄。和「自訂字型」不同：自訂字型直接引用使用者自己的檔案、不複製（ADR 0021）。

字型名稱依介面語系顯示該字型官方發行的對應名稱（Q1，`epic-48` 已實作）。

## 下載來源與基礎設施

```
App（寫死網址＋SHA-256）
  │ HTTPS GET /v1/<檔名>
  ▼
Cloudflare Worker  elinkbook-fonts.<帳號>.workers.dev   （約 20 行，讀 R2 物件回傳）
  │ R2 binding
  ▼
Cloudflare R2 bucket（字型原檔）
```

- **R2＋Worker**（Q5、Q11、Q13）：Cloudflare Pages 單一檔案上限 25 MiB，思源兩款超過，所以改用 R2。R2 要綁自訂網域，整個網域的 DNS 必須搬到 Cloudflare 代管；ugotit.cc 目前 DNS 在 GoDaddy，還有 Zoho 郵件的 MX／SPF 記錄，為了不動郵件 DNS，改由 Worker 以 `workers.dev` 網址對外提供。以後 DNS 搬到 Cloudflare 時，可以新增 `fonts.ugotit.cc`，和舊網址並存。
- **費用**：用量都在免費額度內（儲存約 0.14GB／10GB；Worker 每天 10 萬次請求；R2 不收下載流量費），但啟用 R2 必須先綁付款方式。
- **版本化路徑**（Q17）：網址路徑帶版本號（`/v1/…`）。已上傳的檔案**永遠不覆蓋、不刪除**；字型改版時上傳到新的版本路徑，已安裝的舊版 App 才不會雜湊驗證失敗。
- **原檔與部署腳本放在本 repo**（Q14），例如 `fonts-cdn/`：字型清單（檔名、大小、SHA-256）、Worker 程式、上傳腳本（`wrangler r2 object put`）。字型檔已在 git 歷史中（`eddcc85e^`），重新加入不會讓 repo 變大。
- **網址和雜湊寫死在 App**（Q4）：先不做遠端字型清單檔（manifest），需要時再擴充。
- 建立 Cloudflare 帳號、綁付款方式、`wrangler login` 等需要人類本人操作的步驟，用 wizard 腳本引導。

## 使用者流程

- **字型管理畫面**：每款內建字型顯示狀態：未下載（顯示檔案大小與「下載」按鈕）／下載中（進度條、可取消）／已下載（可刪除）。
- **下載**（Q9）：下載前顯示大小；有進度條；可以取消；失敗可重試；完成後做 SHA-256 驗證，不符就刪檔並顯示錯誤。**不區分**行動網路／Wi-Fi，**不做**背景下載（離開畫面就中止）。
- **閱讀設定的字型下拉選單**（Q7、Q16）：只列出已下載的內建字型（加上自訂字型）；沒有任何已下載的內建字型時，顯示一行提示「到『字型管理』下載更多字型」。不在閱讀中跳出下載流程，也不在第一次開書時主動推薦。
- **刪除已下載字型**（Q8）：可以刪除；**不清除**書籍偏好設定。偏好指向已刪除字型時，下拉選單顯示「使用書本字型」（`epic-48` 已有這個防呆），重新下載後自動恢復。閱讀時 WebView 找不到字型檔會退回系統字型。
- **剛安裝、還沒下載任何字型**（Q6）：閱讀器使用書本字型；書本沒指定時使用系統字型。

## 需要調整的既有程式（Architecting 階段細化）

> **Architecting 階段更新**：以下是 Discovery 當時的初步構想，最終做法以 `spec.md` 為準。其中字型檔服務方式已經改變：Architecting 盤點時發現現行做法是由 Dart 把整個字型檔讀進記憶體，再經 platform channel 傳給 WebView，思源宋體（57MB）不適合這樣做，所以改為新增原生 `InternalStoragePathHandler`（`/downloaded-fonts/`）直接串流，**完全移除** Dart 攔截 `/assets/fonts/` 的分支（見 ADR 0035）。

- ~~`foliate_reader_view.dart` 的 `/assets/fonts/` 請求攔截：改為從 App 私有目錄讀取已下載的字型檔。~~ → 改由原生 `InternalStoragePathHandler` 串流，Dart 攔截分支移除（見上方說明）。
- `buildFontFaceCss()`：只為已下載的字型輸出 `@font-face`（或維持全部輸出、找不到檔案時回傳 null，於 spec 決定）。→ spec 定案：只替已下載的字型輸出。
- 字型管理畫面、閱讀設定下拉選單：依下載狀態顯示。
- `app/assets/fonts/GuanKiapTsingKhai.ttf`：移到部署用目錄，或從 repo 移除。→ spec 定案：移到 `fonts-cdn/fonts/`。

## 文件

- ADR（Q18）：Architecting 階段撰寫 `docs/adr/0035-downloadable-fonts-via-r2-worker.md`（原寫 0024，該編號已被使用），說明為何不打包、為何用 R2＋Worker 而不是 Pages 或自訂網域，以及和 ADR 0021 的差異。
- PRD FR-09、`CLAUDE.md`（Q19）：已在 `epic-48` 改為「可下載字型」的描述。

## 流程

完整 SDD（Q20）。預計至少拆成三張 Issue：R2＋Worker 基礎設施與部署腳本、下載與狀態管理、UI 整合。
