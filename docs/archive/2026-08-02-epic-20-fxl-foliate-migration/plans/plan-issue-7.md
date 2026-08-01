# Epic 20 Issue 7 — 真機端到端驗證與收尾 實作計劃

> **給執行者（agentic worker）的提示：** 建議使用 `superpowers:subagent-driven-development`（推薦）或 `superpowers:executing-plans` 逐工單執行本計劃。工單內的步驟以核取方塊（`- [ ]`）追蹤完成狀態。

**目標：** 完成 Epic 20（FXL 渲染引擎遷移至 `foliate-js`）的裝置端收尾驗證——(1) FXL＋流式兩類書籍在同一操作序列中疊加多項功能的端到端組合驗證（開書/換頁/熱區/雙頁模式切換/目錄跳轉/書籤/頁碼與重開書持久化）；(2) 實測 ADR 0017 決策 5「既有 FXL 書籍使用者資料視為失效」在真機上確實不會導致 crash；(3) 全套建置/測試工具鏈最終確認無 Regression；(4) 彙整 QA 報告、更新 `issues.md`／`docs/epics.md`，供人類決定 Epic 是否可以歸檔。比照 `epic-17` Issue 9（同名工單）既有先例，並依 `issues.md` Issue 7 原文的 4 項範圍逐一對應。

**依賴：** Issue 2-6 已全部完成並合併回 `main`（Issue 6 於 PR #96、Issue 5 於 PR #94）；Issue 8（大型 EPUB OOM 修復）／Issue 9（`framePolicy` 根因修復）亦已完成並合併（PR #95），雖非 Issue 7 正式依賴項，但完成順序上已在本工單之前，Task 1 的組合驗證會自然覆蓋到這兩者的真機行為。

**架構：** 本 issue **原則上不新增產品程式碼、不新增自動化測試**（`issues.md` Issue 7「單元測試要求：無新增」）。3 個驗證性 Task 皆為真機操作（`adb shell input tap`／`screencap`／`logcat`，比照 Issue 6 剛建立的操作方式）＋ 1 個工具鏈確認 Task。核心產出是一份 QA 報告（`docs/epics/epic-20-fxl-foliate-migration/reviews/qa-issue-7-report.md`，該目錄已列入根目錄 `.gitignore`，不進版控）與 `issues.md`／`docs/epics.md` 的最終狀態更新（會被 commit）。若驗證過程中發現真實缺陷，比照 Issue 6「不預先假設有問題，發現後如實記錄並評估」的既有做法——修正成本低則可直接修（需回頭走一次規劃/審查），成本高則另立子工單，不阻塞本工單收尾。

**已查證的關鍵技術事實（避免計劃內容基於臆測）：**

- **Task 2 的核心程式碼路徑已查證，行為符合 ADR 0017 決策 5 的預期**：`FoliateEpubReaderView.jumpToLocator()`（`app/lib/reader/foliate_epub_reader_view.dart:258-269`）與開書時的 `_buildIndexUri()`（同檔案）皆透過共用的 `extractCfi()`（`app/lib/reader/foliate_bridge_codec.dart:12-21`）解析傳入的 locator JSON——`extractCfi()` 用 `try/catch` 包住 `jsonDecode`，且只在 `obj['cfi'] is String` 成立時才回傳非 null 值，否則一律回傳 `null`；呼叫端（`jumpToLocator`／`_buildIndexUri`）在 `cfi == null` 時**直接跳過該次呼叫（無 `else` 分支、無例外拋出）**。這代表任何「不含 `cfi` 欄位的合法 JSON」（例如舊版 Readium 的 `Locator.toJSON()` 格式，結構是 `href`/`locations`/`title` 而非 `cfi`）或「完全不是合法 JSON 的字串」，理論上都會被靜默忽略、不會導致 crash——Task 2 的目的是在真機上**實際驗證這個程式碼層級的保證在完整的 Native↔Dart↔JS 呼叫鏈中確實成立**，而非重新猜測行為。
- **`books` 表 schema**（`app/lib/library/sqlite_library_repository.dart:44-58`）：`id TEXT PRIMARY KEY`、`epubLocator TEXT`（閱讀進度定位，camelCase 無底線）、`progress REAL`、`is_fixed_layout INTEGER`。`bookmarks` 表另有獨立的 `epub_locator_json TEXT`（snake_case，見 `app/lib/reader/bookmark.dart:33`）。兩者欄位命名風格不同，Task 2 撰寫 SQL 時需注意不要混用。
- **Readium 相關程式碼已在 Issue 5 完整刪除**（`EpubReaderView.kt`／`epub_reader_view.dart`），儲存庫內已無法直接查證舊版 `Locator.toJSON()` 的精確歷史輸出格式。Task 2 改用一個「結構上明顯不含 `cfi` 欄位、但本身是合法 JSON」的替代品（模擬 Readium Locator 的 `href`/`locations` 巢狀結構）進行測試——重點不是逐位元組重現歷史格式，而是驗證「任何欠缺 `cfi` 欄位的既有資料」這個**已被程式碼保證涵蓋的等價情境**，範圍比精確重現歷史格式更廣、也更貼近 ADR 0017 決策 5 實際要保護的情境（任何 Phase 1 遷移前遺留、格式不明的舊資料）。
- **測試素材**：FXL 沿用本 Epic 全程使用的 `tmp/一弦定音.epub`（202 頁 RTL 漫畫，Issue 1/2/3/4/6 一路使用同一本，Issue 6 已驗證雙頁書籤正確）；流式沿用 `app/test/fixtures/sample_multi_chapter.epub`（`epic-17` Issue 9 既有使用，多章節含巢狀子目錄）。真機固定使用 `3CEF42ECD491687`（已確認連線中）。

## Global Constraints

- **依賴已解除**：Issue 2-6 皆已完成並合併回 `main`；Issue 8/9 亦已完成，不阻塞但其真機行為會被 Task 1 自然覆蓋到。
- **裝置**：`3CEF42ECD491687`。全部 `adb` 指令一律帶 `-s 3CEF42ECD491687`，避免多裝置連線時的 `"more than one device/emulator"` 錯誤。
- **App 套件名稱**：`cc.ugotit.elinkbook`（`app/android/app/build.gradle.kts` `applicationId`），供 Task 2 的 `adb shell run-as` 指令使用。
- **不擴大範圍重新驗證 Issue 1-6 已有明確結論的個別功能細節**（例如 Issue 6 已詳盡驗證的雙頁書籤 CFI 配對正確性、Issue 4 已驗證的浮動按鈕群組）——Task 1 的組合驗證重點是「多個功能疊加在同一次操作序列中是否仍正確」，不是重複個別功能的獨立深度驗證。
- **`docs/epics/epic-20-fxl-foliate-migration/reviews/` 已列入根目錄 `.gitignore`**：QA 報告寫入此目錄即可，**不需要、也不應該** `git add` 這份報告。真正需要 commit、長期保存的結論一律回填至 `issues.md`（會被 commit）。
- **歸檔決策保留給人類**：依 `CLAUDE.md`「生命週期」第 7 點，Epic 歸檔（搬移至 `docs/archive/`、`docs/epics.md` 狀態改為 🟢 已歸檔）一律由人類指定。Task 4 只負責把 `issues.md`／`docs/epics.md` 更新到「Epic 20 全部 9 個 Issue 皆已完成，可供人類決定是否歸檔」的乾淨狀態，**不自行執行歸檔搬移動作**。
- **若驗證中發現落差，如實記錄；成本低可直接修正（需回頭走一次規劃/審查），成本高則另立子工單追蹤、不阻塞本工單收尾**，比照 Issue 6/8/9 既有先例。
- **暫時性資料庫竄改（Task 2）驗證完成後必須清理**：Task 2 用來模擬舊資料的資料庫欄位竄改與 Task 4 的裝置端測試書籍，皆屬暫時性測試資料，不應殘留在裝置上污染真實圖書庫（比照 `epic-17` Issue 9 Task 2/4 既有做法）。
- **本計劃所有 Shell 指令假設在 Git Bash（POSIX）環境下執行**，路徑含 `/sdcard/` 等 Android 端路徑時，若使用 Git Bash 需留意 MSYS 路徑自動轉換問題（見下方指令的 `MSYS_NO_PATHCONV=1` 前綴，本 Epic Issue 6 執行時已確認此問題存在並建立此解法）。

---

## 檔案結構

- 新增（**不進版控**，見 Global Constraints）：`docs/epics/epic-20-fxl-foliate-migration/reviews/qa-issue-7-report.md`
- Modify：`docs/epics/epic-20-fxl-foliate-migration/issues.md`
- Modify：`docs/epics.md`
- Modify：本計畫檔（`plans/plan-issue-7.md`，逐步勾選）
- **不預期修改任何 `app/` 底下的程式碼／測試檔**（除非 Task 2/3 發現需要修正的真實缺陷，屆時視成本決定是否當場修正並回頭走規劃/審查）

---

### Task 1：端到端組合驗證（FXL＋流式各一本，全功能疊加操作序列）

**Files:**
- Create（不進版控）：`docs/epics/epic-20-fxl-foliate-migration/reviews/qa-issue-7-report.md`

**Interfaces:**
- Consumes：既有「匯入」流程（`library_screen.dart`）、`ReaderScreen`／`FoliateEpubReaderView` 對外行為（Issue 2-6 建立的全部功能）
- Produces：QA 報告「端到端組合驗證」段落

- [ ] **Step 1：建置並安裝最新 `main` APK 至真機**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter build apk --debug
adb -s 3CEF42ECD491687 install -r build/app/outputs/flutter-apk/app-debug.apk
```

- [ ] **Step 2：推送並匯入兩本測試書籍**

```bash
MSYS_NO_PATHCONV=1 adb -s 3CEF42ECD491687 push "U:/MyDeveloper/AI/elinkBook/tmp/一弦定音.epub" /sdcard/Download/qa_issue7_fxl.epub
MSYS_NO_PATHCONV=1 adb -s 3CEF42ECD491687 push "U:/MyDeveloper/AI/elinkBook/app/test/fixtures/sample_multi_chapter.epub" /sdcard/Download/qa_issue7_flow.epub
```

在 App 書架點擊「+」→「選擇檔案（可多選）」，於系統檔案選擇器的 Download 目錄依序匯入 `qa_issue7_fxl.epub`（FXL）與 `qa_issue7_flow.epub`（流式）。匯入完成後書架應出現這 2 本新書（截圖存 `tmp/epic-20/issue7_step2_imported.png`）。

- [ ] **Step 3：建立 QA 報告檔案骨架**

```markdown
# Epic 20 Issue 7 — 真機端到端驗證與收尾 QA 報告

裝置：<執行當下 `adb devices -l` 實際輸出>
執行日期：<YYYY-MM-DD>

## 1. 端到端組合驗證

### 1.1 FXL（`qa_issue7_fxl.epub`，一弦定音！(11)）——完整操作序列

<記錄開書、單頁/雙頁模式切換、換頁、目錄跳轉、新增書籤、
關閉重開後定位/書籤/版面模式是否保留 各項結果，附截圖檔名>

### 1.2 流式（`qa_issue7_flow.epub`，多章節）——完整操作序列

<同上操作序列（無雙頁模式，改為驗證橫排初始方向），
額外著重目錄的巢狀子項目跳轉、跨章節連續翻頁>

### 1.3 結論

<總結：是否全數符合預期，或列出發現的落差與後續處理方式>
```

- [ ] **Step 4：FXL（`qa_issue7_fxl.epub`）完整操作序列**

依序執行並記錄於 QA 報告 1.1 節，每個判斷點截圖存 `tmp/epic-20/issue7_t1_fxl_<step>.png`：

1. **開書**：裝置轉直向（`MSYS_NO_PATHCONV=1 adb -s 3CEF42ECD491687 shell settings put system accelerometer_rotation 0` + `settings put system user_rotation 0`），開啟該書，確認單頁模式正常渲染出真實內容（非空白/錯誤畫面）。
2. **雙頁模式切換**：轉橫向（`user_rotation 1`），確認自動進入雙頁模式（兩頁並排，比照 Issue 6 已驗證的判準：真正雙頁並排的插畫/文字內容橫跨左右兩半，非兩張獨立單頁置中）。
3. **換頁**：雙頁模式下點擊 3×3 熱區左右兩側各 2 次，確認正確翻頁（頁碼遞增/遞減、畫面內容隨之改變）。
4. **目錄跳轉**：開啟目錄（頂部「閱讀器」工具列的書本圖示），點擊任一非首項目錄項目，確認正確跳轉且畫面內容與章節標題相符。
5. **新增書籤**：在跳轉後的畫面新增一筆書籤（星形圖示），確認圖示切換為 filled、書籤清單出現對應項目（比照 Issue 6 既有做法，此處僅需 1 次操作確認整合無誤，不需要 Issue 6 等級的雙頁配對深度驗證）。
6. **持久化**：按返回鍵離開閱讀畫面，重新點擊書架該書籍項目重新開啟，確認：(a) 回到離開前的定位（非從頭開始）；(b) 步驟 5 建立的書籤仍存在於清單；(c) 版面模式（雙頁/單頁）符合當下裝置實際方向（不是記憶步驟 1 離開時的模式，而是即時依方向判定，比照 Issue 3 既有行為）。

- [ ] **Step 5：流式（`qa_issue7_flow.epub`）完整操作序列**

重複 Step 4 的精神（開書/換頁/目錄跳轉/書籤/持久化），額外注意流式書籍的差異點，記錄於 QA 報告 1.2 節，截圖存 `tmp/epic-20/issue7_t1_flow_<step>.png`：

1. **開書初始方向**：確認開書當下為橫排（該書不宣告 `writing-mode`，預設橫排，非直排）。
2. **換頁**：3×3 熱區換頁，確認正確捲動/翻頁。
3. **巢狀子目錄項目跳轉**：該書目錄含巢狀子項目（第二章下有子章節），點擊子項目，確認正確跳轉至對應段落（非只跳到父章節開頭）。
4. **跨章節連續翻頁**：從第一章開頭連續翻頁直到進入第二章，確認章節邊界翻頁無縫、無內容跳過/重複。
5. **新增書籤**：新增一筆書籤，確認圖示與清單同步。
6. **持久化**：離開重開，確認定位與書籤皆保留。

- [ ] **Step 6：填寫結論**

在 QA 報告 1.3 節填寫總結（是否全數正常；若有落差，具體描述現象並註明後續處理方式）。本 Task 匯入的 2 本測試書留在書架供 Task 2 沿用（Task 2 直接使用 `qa_issue7_fxl.epub`），統一於 Task 4 清理，不在此提前刪除。

---

### Task 2：既有 FXL 資料視為失效驗證（ADR 0017 決策 5）

**Files:**
- Modify（不進版控）：`docs/epics/epic-20-fxl-foliate-migration/reviews/qa-issue-7-report.md`

**Interfaces:**
- Consumes：Task 1 已匯入的 `qa_issue7_fxl.epub`；`books.epubLocator`／`bookmarks.epub_locator_json` 欄位（見上方「已查證的關鍵技術事實」的 schema 說明）
- Produces：QA 報告「既有 FXL 資料視為失效驗證」段落

- [ ] **Step 1：找出裝置上的資料庫檔案實際路徑**

```bash
MSYS_NO_PATHCONV=1 adb -s 3CEF42ECD491687 shell run-as cc.ugotit.elinkbook find /data/data/cc.ugotit.elinkbook -name "*.db"
```

記錄輸出的完整路徑（下方以 `<db-path>` 表示；比照 `epic-17` Issue 9 Task 2 既有做法，以實測結果為準，不假設固定路徑）。

- [ ] **Step 2：確認裝置端 sqlite3 CLI 可用性，查出 `qa_issue7_fxl.epub` 對應的 `books.id`**

```bash
MSYS_NO_PATHCONV=1 adb -s 3CEF42ECD491687 shell run-as cc.ugotit.elinkbook sqlite3 --version
```

若有版本輸出（裝置端可直接用 sqlite3 CLI），執行：

```bash
MSYS_NO_PATHCONV=1 adb -s 3CEF42ECD491687 shell run-as cc.ugotit.elinkbook sqlite3 "<db-path>" \
  "SELECT id, title, filePath, epubLocator FROM books WHERE filePath LIKE '%qa_issue7_fxl%';"
```

記錄回傳的 `id`（下方以 `<book-id>` 表示）與目前的 `epubLocator` 值（Task 1 操作後應已是 foliate-js 的 CFI JSON 格式，含 `"cfi":...`）。

若裝置端**沒有** sqlite3 CLI，改用本機 Python 拉取/編輯/推回（比照 `epic-17` Issue 9 Task 2 既有退路）：

```bash
adb -s 3CEF42ECD491687 exec-out run-as cc.ugotit.elinkbook cat "<db-path>" > local_qa7_library.db
python3 -c "
import sqlite3
conn = sqlite3.connect('local_qa7_library.db')
cur = conn.cursor()
cur.execute(\"SELECT id, title, filePath, epubLocator FROM books WHERE filePath LIKE '%qa_issue7_fxl%'\")
for row in cur.fetchall():
    print(row)
conn.close()
"
```

記錄查到的 `<book-id>`，此步驟純查詢，暫不寫回（寫回動作於 Step 3 一併執行，避免中途裝置端資料庫檔案被本機複本覆蓋兩次造成不一致）。

- [ ] **Step 3：竄改 `epubLocator` 為模擬舊版 Readium 格式的替代 JSON，並插入一筆同類型的舊格式書籤**

用 sqlite3 CLI（若裝置端可用）：

```bash
MSYS_NO_PATHCONV=1 adb -s 3CEF42ECD491687 shell run-as cc.ugotit.elinkbook sqlite3 "<db-path>" \
  "UPDATE books SET epubLocator = '{\"href\":\"/OEBPS/chapter1.xhtml\",\"type\":\"application/xhtml+xml\",\"locations\":{\"position\":5,\"totalProgression\":0.05},\"title\":\"legacy readium locator (simulated)\"}' WHERE id = '<book-id>';"
MSYS_NO_PATHCONV=1 adb -s 3CEF42ECD491687 shell run-as cc.ugotit.elinkbook sqlite3 "<db-path>" \
  "INSERT INTO bookmarks (book_id, name, epub_locator_json) VALUES ('<book-id>', 'legacy bookmark (simulated)', '{\"href\":\"/OEBPS/chapter2.xhtml\",\"locations\":{\"position\":9,\"totalProgression\":0.12}}');"
```

若走 Python 退路，改用 Python 的 `sqlite3` 模組執行等效的 `UPDATE`/`INSERT`（同上 SQL 語句），完成後 `push` 回裝置（指令樣式比照 `epic-17` Issue 9 Task 2 Step 3 的 Python 退路段落）並用 `ls local_qa7_library.db` 確認本機暫存複本已刪除。

App 執行中持有的資料庫連線可能快取檔案內容——完成竄改後先 `adb shell am force-stop cc.ugotit.elinkbook` 完全關閉 App 再重新啟動，確保讀到磁碟上剛修改過的檔案。

- [ ] **Step 4：重新開啟該書，確認不會 crash、以新書狀態正常開啟**

```bash
MSYS_NO_PATHCONV=1 adb -s 3CEF42ECD491687 logcat -c
```

在書架點擊該書開啟，過程中執行：

```bash
MSYS_NO_PATHCONV=1 adb -s 3CEF42ECD491687 logcat -d | grep -iE "FATAL EXCEPTION|AndroidRuntime.*elinkbook"
```

確認：(a) **無任何 `FATAL EXCEPTION`／App 層級的未捕捉例外輸出**（App 沒有閃退）；(b) 書籍正常渲染出內容（截圖存 `tmp/epic-20/issue7_t2_reopened.png`）；(c) 畫面顯示的位置是書籍開頭（或至少不是 Step 3 竄改前 Task 1 建立的那個特定位置）——因為 `epubLocator` 已被替換成不含 `cfi` 欄位的資料，`extractCfi()` 應回傳 `null`，`_buildIndexUri()` 不會帶入 `initialCfi` 參數，書籍以預設起始位置開啟，等同 ADR 0017「以新書狀態開始」的預期行為。若 (a)/(b)/(c) 任一項不符，如實記錄具體現象（畫面截圖＋文字描述），評估是否需要修正。

- [ ] **Step 5：開啟書籤清單，確認含舊格式資料的書籤不會導致清單本身崩潰或點擊後 crash**

開啟筆記 Bottom Sheet「書籤」分頁，觀察 Step 3 插入的「legacy bookmark (simulated)」是否正常顯示在清單中（`Bookmark.defaultName`／清單渲染只依賴 `name`／`progression`／`pdfPageIndex` 欄位，不解析 `epub_locator_json` 內部結構，預期會正常顯示）。點擊該筆書籤，清空 logcat 後執行：

```bash
MSYS_NO_PATHCONV=1 adb -s 3CEF42ECD491687 logcat -c
```

點擊後執行：

```bash
MSYS_NO_PATHCONV=1 adb -s 3CEF42ECD491687 logcat -d | grep -iE "FATAL EXCEPTION|AndroidRuntime.*elinkbook"
```

確認無 crash；記錄畫面實際反應（預期：`jumpToLocator()` 因 `extractCfi()` 回傳 `null` 而靜默不做任何事，畫面停留原地，無錯誤提示——這是已知、可接受的行為，非缺陷，但需要在真機上實際確認，不能只憑程式碼閱讀假設）。截圖存 `tmp/epic-20/issue7_t2_legacy_bookmark.png`。

- [ ] **Step 6：清理本 Task 建立的測試資料，填寫結論**

刪除書架上的 `qa_issue7_fxl.epub`（連帶清除其所有書籤/閱讀進度資料，比照既有「刪除書籍」功能，不需要再手動下 SQL 清理）。在 QA 報告新增「## 2. 既有 FXL 資料視為失效驗證」段落，填入 Step 4/5 的觀察結果與結論，明確標註「ADR 0017 決策 5 的行為已用真機實測確認/未確認」。

---

### Task 3：完整建置/測試工具鏈最終確認

**Files:** 無（純指令執行，若有失敗才會涉及程式碼修正）

**Interfaces:**
- Consumes：`main` 分支目前完整狀態
- Produces：QA 報告「工具鏈確認」段落

- [ ] **Step 1：`flutter analyze`**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter analyze
```

Expected：`No issues found!`

- [ ] **Step 2：`flutter test`**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter test
```

Expected：全數 PASS。

- [ ] **Step 3：`./gradlew :app:compileDebugKotlin`**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app/android"
./gradlew.bat :app:compileDebugKotlin
```

Expected：`BUILD SUCCESSFUL`。

- [ ] **Step 4：`./gradlew :app:testDebugUnitTest`**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app/android"
./gradlew.bat :app:testDebugUnitTest
```

Expected：`BUILD SUCCESSFUL`。

- [ ] **Step 5：記錄結果**

在 QA 報告新增「## 3. 工具鏈確認」段落，逐項記錄 4 個工具的實際輸出結果（版本號/通過數量/耗時等），若任一項失敗需在此明確標註並評估是否阻塞本工單收尾。

---

### Task 4：彙整 QA 報告、更新 `issues.md`／`docs/epics.md`、清理裝置

**Files:**
- Modify：`docs/epics/epic-20-fxl-foliate-migration/issues.md`
- Modify：`docs/epics.md`

**Interfaces:**
- Consumes：Task 1-3 全部結論
- Produces：無

- [ ] **Step 1：清理裝置端暫存測試素材**

```bash
MSYS_NO_PATHCONV=1 adb -s 3CEF42ECD491687 shell rm /sdcard/Download/qa_issue7_fxl.epub /sdcard/Download/qa_issue7_flow.epub
```

在書架刪除 Task 1 匯入、Task 2 已刪除 FXL 那本以外的剩餘測試書（`qa_issue7_flow.epub`，若尚未刪除），確認書架恢復到本工單執行前的狀態，不留下 QA 用測試書籍污染真實圖書庫。

- [ ] **Step 2：更新 `docs/epics/epic-20-fxl-foliate-migration/issues.md`——Issue 7 完成說明**

把 Issue 7 的 `**Status:**`（現為 `ready-for-agent`）改為完成狀態，內容需涵蓋：
- Task 1-3 各自的驗證結論摘要（端到端組合驗證、ADR 0017 決策 5 真機實測、工具鏈確認）
- 明確指出 Epic 20 Issue 1-9 全部完成
- 若過程中發現任何新問題，需註明已建立哪個後續 issue 追蹤（若無發現，明確寫「無」）
- 引用 QA 報告路徑 `reviews/qa-issue-7-report.md`（並註明該檔案未進版控，僅供本機參考，結論已完整回填至本檔案）

- [ ] **Step 3：更新 `docs/epics.md`——Epic 20 狀態列**

在 `docs/epics.md` 的 `epic-20-fxl-foliate-migration` 那一列備註最後，新增一句總結 Issue 7 收尾結論，並註明：**Epic 20 全部 9 個 Issue（Issue 1-9）皆已完成**。狀態燈號本身維持 `🟡 開發中 (Active)`，**不自行改成 `🟢 已歸檔 (Archived)`**。

- [ ] **Step 4：本計畫檔 Task 1-4 所有 Step 依實際完成進度勾選**

- [ ] **Step 5：Commit**

```bash
cd "U:/MyDeveloper/AI/elinkBook"
git add docs/epics/epic-20-fxl-foliate-migration/issues.md docs/epics.md docs/epics/epic-20-fxl-foliate-migration/plans/plan-issue-7.md
git commit -m "docs(epic-20): Issue 7 真機端到端驗證與收尾——Epic 20 Issue 1-9 全數完成"
```

- [ ] **Step 6：送出 code review（`superpowers:requesting-code-review`），依審查結果修正後開 PR**

比照 Issue 6/8 的做法，審查者除核對文件敘述外，應實際核對本工單引用的截圖內容是否與文字宣告相符（`tmp/epic-20/issue7_*.png`）。

---

## 相關佐證

- `docs/epics/epic-20-fxl-foliate-migration/issues.md` Issue 7 原始描述
- `docs/adr/0017-fxl-migrate-to-foliate-js.md` 決策 5（既有 FXL 使用者資料視為失效）
- `docs/archive/2026-07-24-epic-17-epub-render-migration/plans/plan-issue-9.md`（同名工單既有先例，本計劃 Task 1/2/4 的結構與方法論參考來源）
- `app/lib/reader/foliate_epub_reader_view.dart:258-269`（`jumpToLocator`）、`app/lib/reader/foliate_bridge_codec.dart:12-21`（`extractCfi`）——Task 2 核心行為的程式碼查證來源
- `app/lib/library/sqlite_library_repository.dart:44-58`（`books` 表 schema）
- `docs/epics/epic-20-fxl-foliate-migration/plans/plan-issue-6.md`（本 Epic 剛建立的真機截圖驗證方法論，Task 1/2 沿用相同精神）
- `tmp/一弦定音.epub`／`app/test/fixtures/sample_multi_chapter.epub`（測試素材）
