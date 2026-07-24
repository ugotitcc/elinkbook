# Epic 17 Issue 9 — 真機端到端驗證與收尾 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 完成 Epic 17 Phase 1（流式 EPUB 渲染引擎遷移至 `readest/foliate-js`）的裝置端整合驗證與收尾——真實圖書庫匯入多本不同結構的流式 EPUB 端到端組合驗證（開書／換頁／熱區／排版切換／目錄跳轉／劃線備註／頁碼顯示）、既有書籍（`is_fixed_layout` 為 `null`）一次性回填流程真機實測、FXL 路徑不受影響的抽測，彙整驗證紀錄並更新 `docs/epics.md` 狀態列，供人類決定是否歸檔本 Epic。

**Architecture:** 本 issue **不新增產品程式碼、不新增任何自動化測試**（`issues.md` Issue 9 原文明訂「單元測試要求：無新增自動化單元測試（本工單以整合/裝置驗證為主）」）。3 個驗證性 Task 皆為真機人工操作（必要時輔以 `adb`／臨時 `debugPrint` 插樁），核心產出是一份 QA 報告（`docs/epics/epic-17-epub-render-migration/reviews/qa-issue-9-report.md`，該目錄已列入根目錄 `.gitignore`，不需要／不應該 `git add`，純供收尾決策參考）與 `issues.md`／`docs/epics.md` 的最終狀態更新（會被 commit），比照 `epic-7-interaction` Issue 8、`epic-16-dual-page` Issue 7 既有模式。

**Tech Stack:** Flutter App 真機操作（`flutter run`／已 build 的 debug APK）＋ `adb`（`shell input tap`／`shell input keyevent`／`logcat`／`exec-out`／`run-as`）＋ Python 內建 `sqlite3` 模組（既有書籍回填情境的資料庫欄位還原，見 Task 2）＋ 既有 App 內建的「匯入」流程與「⚙️版面設定」畫面。

## Global Constraints

- **依賴已解除**：`issues.md` Issue 9 依賴 Issue 2、3、4、5、6、7、8 全部完成——七者皆已完成並合併回 `main`（Issue 8 於 2026-07-24 透過 PR #71 合併），本 issue 現已可開始，是 Epic 17 Phase 1 最後一個工單。
- **裝置**：沿用本 Epic 全程使用的同一台真機（`3CEF42ECD491687`，Android 15／API 35，9491G），執行前以 `adb devices -l` 重新確認裝置仍在；若環境已更換，以當下 `flutter devices` 輸出為準，後續步驟一律以 `<device-id>` 表示。
- **範圍依 `issues.md` Issue 9 原文的 3 個驗證項目 + 收尾**：(1) 端到端組合驗證、(2) 既有書籍回填流程實測、(3) FXL 路徑不受影響抽測、(4) 彙整驗證紀錄並更新狀態。不擴大範圍重新驗證 Issue 1-8 已有明確結論的個別功能細節（例如 Issue 8 QA 報告已詳盡涵蓋的劃線繪製視覺、Issue 6 已涵蓋的目錄跳轉精度）——本 issue 的組合驗證重點是「多個功能疊加在同一本書、同一次操作序列中是否仍正確」，不是重複個別功能的獨立驗證。
- **測試素材（已提交版本控制，直接沿用，不需另外產生）**：
  - `app/test/fixtures/sample_declares_vertical.epub`——EPUB 自身 CSS 宣告 `writing-mode: vertical-rl`（Issue 4 建立，FR-06 驗證用）。
  - `app/test/fixtures/sample_multi_chapter.epub`——不宣告 `writing-mode`（預設橫排起始）、多章節（3 章，含巢狀子目錄項目），適合驗證目錄跳轉/翻頁/劃線備註組合。
  - `app/test/fixtures/sample_fixed_layout.epub`——FXL（固定版面）測試書，供 Task 3 抽測。
  - 三者皆需透過 App 既有「匯入」流程（`file_picker`，`library_screen.dart`）從裝置儲存空間匯入才能開啟——不是透過 `integration_test` 直接注入檔案路徑，因為本 issue 是操作**真實已建置的 App**、走真實使用者路徑，比照 `epic-7-interaction` Issue 8 既有做法。
- **`docs/epics/epic-17-epub-render-migration/reviews/` 已列入根目錄 `.gitignore`**（`f0b96db`/`624e3aa` 事故復原過程中已補上，見 `.gitignore` 第 12 行附近）：QA 報告寫入此目錄即可，**不需要、也不應該** `git add` 這份報告，比照 `epic-7-interaction` Issue 8 既有慣例。真正需要 commit、長期保存的結論一律回填至 `issues.md`（會被 commit）。
- **歸檔決策保留給人類**：依 `CLAUDE.md`「生命週期」第 7 點，Epic 歸檔（搬移至 `docs/archive/`、`docs/epics.md` 狀態改為 🟢 已歸檔）一律由人類指定。Task 4 只負責把 `issues.md`／`docs/epics.md` 更新到「Epic 17 Phase 1 全部 9 個 Issue 皆已完成，可供人類決定是否歸檔」的乾淨狀態，**不自行執行歸檔搬移動作、不自行把 `docs/epics.md` 狀態燈號改為已歸檔**。
- **若驗證中發現落差，另立後續 issue 追蹤、不阻塞本 Phase 1 收尾**（`issues.md` 原文）：任何本 issue 過程中發現的新問題，記錄於 QA 報告與 `issues.md` Task 4 段落即可，不要求當場修復；但若修復成本低、風險小，可直接修正並如實記錄，比照 `issues.md` Issue 6「Bugfix 紀錄」既有先例。
- **暫時性插樁與素材一律不納入版本控制**：Task 2 使用的臨時 `debugPrint` 插樁與資料庫欄位還原用的本機 `.db` 複本，驗證完成後刪除／還原，並以 `git status --short` 確認乾淨後才可進行該 Task 的 commit（本 Task 實際上不需要 commit，見 Task 2 Step 6，但仍需確認乾淨）。
- **本計劃所有 Shell 指令假設在 Git Bash（POSIX）環境下執行**，與本 Epic 既有全部計劃一致。
- **全部 `adb` 指令一律帶 `-s <device-id>`**：避免執行環境同時連線多台裝置/模擬器時觸發 `"more than one device/emulator"` 錯誤而失敗。
- **App 套件名稱**：`cc.ugotit.elinkbook`（`app/android/app/build.gradle.kts` `applicationId`），供 Task 2 的 `adb shell run-as` 指令使用。

---

## File Structure

| 檔案 | 異動類型 | 職責 |
|---|---|---|
| `docs/epics/epic-17-epub-render-migration/reviews/qa-issue-9-report.md` | 新增（**不進版控**，見 Global Constraints） | Task 1-3 各自產出對應段落的完整 QA 驗證紀錄 |
| `docs/epics/epic-17-epub-render-migration/issues.md` | 修改 | Issue 9 完成說明 |
| `docs/epics.md` | 修改 | Epic 17 狀態列彙整 Phase 1 收尾結論（不自行改為已歸檔） |

---

### Task 1：端到端組合驗證（多本不同結構流式 EPUB × 全功能疊加操作序列）

**Files:**
- Create（不進版控）：`docs/epics/epic-17-epub-render-migration/reviews/qa-issue-9-report.md`

**Interfaces:**
- Consumes：既有「匯入」流程（`library_screen.dart`）、`ReaderScreen` 對外行為（Issue 3-8 建立的全部功能）
- Produces：QA 報告「端到端組合驗證」段落

- [ ] **Step 1：匯入兩本不同結構的流式 EPUB 測試書籍**

在真機上啟動已 debug build 的 App（若尚未安裝，先執行 `cd app && flutter build apk --debug && flutter install -d <device-id>`），透過以下方式把測試素材放到裝置可被系統檔案選擇器看到的位置：

```bash
adb -s <device-id> push app/test/fixtures/sample_declares_vertical.epub /sdcard/Download/qa_issue9_vertical.epub
adb -s <device-id> push app/test/fixtures/sample_multi_chapter.epub /sdcard/Download/qa_issue9_multi.epub
```

在 App 書架畫面點擊「匯入」，透過系統檔案選擇器依序匯入 `/sdcard/Download/` 下的兩個檔案。匯入完成後書架應出現 2 本新書。

- [ ] **Step 2：建立 QA 報告檔案骨架**

建立 `docs/epics/epic-17-epub-render-migration/reviews/qa-issue-9-report.md`：

```markdown
# Epic 17 Issue 9 — 真機端到端驗證與收尾 QA 報告

裝置：<執行當下 `flutter devices` 實際輸出的型號／API 版本／device id>
執行日期：<YYYY-MM-DD>

## 1. 端到端組合驗證

### 1.1 `sample_declares_vertical.epub`（含 writing-mode 宣告）——完整操作序列

<記錄開書初始方向、換頁、3×3 熱區、排版切換（橫→直→橫）、目錄跳轉、
新增劃線+備註、頁碼顯示、關閉重開後定位/劃線是否保留 各項結果>

### 1.2 `sample_multi_chapter.epub`（不含宣告，多章節）——完整操作序列

<同上操作序列，額外著重目錄的巢狀子項目跳轉、跨章節翻頁>

### 1.3 結論

<總結：是否全數符合預期，或列出發現的落差>
```

- [ ] **Step 3：`sample_declares_vertical.epub` 完整操作序列**

開啟剛匯入的 `sample_declares_vertical.epub`，依序執行並記錄於 QA 報告 1.1 節：

1. **開書初始方向（FR-06）**：確認開書當下即為直排（`vertical-rl`），不需使用者手動切換（比照 Issue 4 既有驗收標準）。
2. **換頁**：點擊 3×3 熱區的「下一頁」「上一頁」格各 2 次，確認正確翻頁。
3. **目錄跳轉**：開啟目錄，點擊任一非首項目錄項目，確認 200ms 內跳轉且畫面內容與章節標題相符。
4. **排版切換**：進入「⚙️版面設定」，手動切換為橫排，確認即時生效（不重新開書）；再切回直排，確認同樣即時生效。
5. **新增劃線與備註**：長按選取一段文字，套用螢光筆任一色，確認正確繪製；另選取一段文字，新增備註文字「Issue 9 端到端驗證」，確認淡灰底標示正常顯示。
6. **頁碼顯示**：確認頁尾頁碼隨翻頁正確更新。
7. **持久化**：按返回鍵離開閱讀畫面，重新點擊書架該書籍項目重新開啟，確認：(a) 回到離開前的定位（非從頭開始）；(b) 步驟 5 建立的劃線與備註仍正確顯示於畫面上；(c) 排版方向維持步驟 4 離開時的設定（若最後切回直排，重開後應仍為直排）。

- [ ] **Step 4：`sample_multi_chapter.epub` 完整操作序列**

開啟剛匯入的 `sample_multi_chapter.epub`，重複 Step 3 的操作序列（初始方向此處預期為橫排，因該書不宣告 `writing-mode`），額外驗證：

8. **巢狀子目錄項目跳轉**：該書目錄含巢狀子項目（第二章下有兩個子章節），點擊其中一個子項目，確認正確跳轉至對應段落（非只跳到父章節開頭）。
9. **跨章節連續翻頁**：從第一章開頭連續點擊「下一頁」直到進入第二章，確認章節邊界翻頁無縫、無內容跳過/重複。

記錄於 QA 報告 1.2 節。

- [ ] **Step 5：填寫結論並清理裝置端暫存檔案**

在 QA 報告 1.3 節填寫總結。

```bash
adb -s <device-id> shell rm /sdcard/Download/qa_issue9_vertical.epub /sdcard/Download/qa_issue9_multi.epub
```

由於本報告目錄已列入 `.gitignore`，**不執行 `git add`**；本 Task 無其他程式碼異動，無需 commit（Task 1 匯入的 2 本測試書留在書架供 Task 2/3 沿用書架已有匯入流程的既有狀態，不在此提前刪除，改於 Task 4 統一清理，見 Task 4 Step 1）。

---

### Task 2：既有書籍回填流程實測

**Files:**
- Modify（不進版控）：`docs/epics/epic-17-epub-render-migration/reviews/qa-issue-9-report.md`
- 暫時性插樁（驗證後還原，不 commit）：`app/lib/screens/reader_screen.dart`

**Interfaces:**
- Consumes：既有 `_resolveEpubEngineDispatch()`（`reader_screen.dart:280-298`）／`LibraryRepository.detectAndCacheEpubLayout()`（`sqlite_library_repository.dart:341`）／`BookMetadataChannel.kt` 的 `detectEpubLayout` case（Issue 2 建立）
- Produces：QA 報告「既有書籍回填流程實測」段落

`issues.md` Issue 9「既有書籍回填流程實測」原文：「用 Phase 1 上線前已匯入（`is_fixed_layout` 為 `null`）的既有流式 EPUB 書籍實測 `detectAndCacheEpubLayout()` 一次性判斷與回填正確，第二次開書不再重複判斷」。由於本開發裝置在 Epic 17 開發全程已反覆重新安裝/更新 App，資料庫早已是 schema v11、透過正常「匯入」流程新增的書籍一律會在匯入當下就寫入非 `null` 的 `is_fixed_layout`（Issue 2 既有行為），裝置上已不存在真正「Phase 1 上線前」遺留的 `null` 資料列。本 Task 透過直接修改資料庫欄位，人工還原出這個情境，而非等待/假造一個實際上不存在的真實舊資料。

- [ ] **Step 1：在 `_resolveEpubEngineDispatch()` 加入臨時 `debugPrint` 插樁**

`app/lib/screens/reader_screen.dart` 第 292-297 行：

```dart
    repository
        .detectAndCacheEpubLayout(widget.bookId, widget.filePath)
        .then((result) {
      if (!mounted) return;
      setState(() => _dispatchedIsFixedLayout = result);
    });
```

改為（暫時性插樁，驗證後於 Step 6 還原）：

```dart
    debugPrint('[QA-ISSUE9] detectAndCacheEpubLayout() 被呼叫，bookId=${widget.bookId}');
    repository
        .detectAndCacheEpubLayout(widget.bookId, widget.filePath)
        .then((result) {
      if (!mounted) return;
      setState(() => _dispatchedIsFixedLayout = result);
    });
```

重新建置並安裝：

```bash
cd app && flutter build apk --debug && flutter install -d <device-id>
```

- [ ] **Step 2：找出裝置上的資料庫檔案實際路徑**

```bash
adb -s <device-id> shell run-as cc.ugotit.elinkbook find /data/data/cc.ugotit.elinkbook -name "library.db"
```

記錄輸出的完整路徑（下方步驟以 `<db-path>` 表示這個實際路徑；`getApplicationDocumentsDirectory()` 在不同 `path_provider` 版本下對應到的實際子目錄可能不同，故以此指令實測結果為準，不假設固定路徑）。

- [ ] **Step 3：確認 sqlite3 是否可在裝置端直接使用，將 Task 1 匯入的其中一本書的 `is_fixed_layout` 欄位改回 `NULL`**

```bash
adb -s <device-id> shell run-as cc.ugotit.elinkbook sqlite3 --version
```

若輸出版本號（裝置端有 sqlite3 CLI），直接執行：

```bash
adb -s <device-id> shell run-as cc.ugotit.elinkbook sqlite3 "<db-path>" \
  "UPDATE books SET is_fixed_layout = NULL WHERE title LIKE '%multi%' OR file_path LIKE '%qa_issue9_multi%';"
adb -s <device-id> shell run-as cc.ugotit.elinkbook sqlite3 "<db-path>" \
  "SELECT id, title, is_fixed_layout FROM books;"
```

確認 Task 1 匯入的 `sample_multi_chapter.epub` 那筆資料列的 `is_fixed_layout` 已變為 `NULL`（`sqlite3` 輸出該欄位為空字串），其餘書籍不受影響。

若裝置端**沒有** sqlite3 CLI（`command not found`），改用本機 Python 拉取/編輯/推回：

```bash
adb -s <device-id> exec-out run-as cc.ugotit.elinkbook cat "<db-path>" > local_qa9_library.db
python3 -c "
import sqlite3
conn = sqlite3.connect('local_qa9_library.db')
cur = conn.cursor()
cur.execute(\"SELECT id, title, is_fixed_layout FROM books\")
for row in cur.fetchall():
    print(row)
cur.execute(\"UPDATE books SET is_fixed_layout = NULL WHERE file_path LIKE '%qa_issue9_multi%'\")
conn.commit()
conn.close()
print('done')
"
adb -s <device-id> push local_qa9_library.db /sdcard/qa9_library_restore.db
adb -s <device-id> shell run-as cc.ugotit.elinkbook sh -c 'cat /sdcard/qa9_library_restore.db > "<db-path>"'
adb -s <device-id> shell rm /sdcard/qa9_library_restore.db
rm local_qa9_library.db
```

執行 `ls local_qa9_library.db`（Git Bash）確認回報 `No such file or directory`——本機暫存的資料庫複本已確實刪除，不留下含使用者書籍中繼資料的檔案在開發機上。

（App 執行中持有的資料庫連線可能快取檔案內容——若步驟 4 開書後行為與預期不符，先透過 `adb shell am force-stop cc.ugotit.elinkbook` 完全關閉 App 再重新啟動，確保讀到的是磁碟上剛修改過的檔案。）

- [ ] **Step 4：第一次開書——確認一次性判斷與回填正確**

```bash
adb -s <device-id> logcat -c
```

**`logcat -c` 應變說明**：部分裝置/Android 版本下 `logcat -c` 可能無法徹底清空緩衝區（非 root 環境下的已知限制）。若下方 `logcat -d | grep` 的結果混雜了非本次操作產生的舊 `QA-ISSUE9` 行，改用插樁訊息中已內建的 `bookId=${widget.bookId}`（見 Step 1）過濾，或改用 `adb -s <device-id> logcat -d -T '<執行 Step 4 前的時間戳記>'` 只看清空時間點之後的新輸出，不需要依賴 `logcat -c` 真的清空成功。

在 App 書架點擊剛被改回 `NULL` 的那本書（`sample_multi_chapter.epub`），開書過程中執行：

```bash
adb -s <device-id> logcat -d | grep "QA-ISSUE9"
```

確認：(a) 這行插樁 log 確實輸出一次（含正確的 `bookId`）；(b) 書籍正確以流式（`FoliateEpubReaderView`）開啟並成功渲染出內容（非卡在載入中或錯誤畫面）；(c) 用 Step 3 相同的 `sqlite3`/Python 讀取方式重新查詢該書的 `is_fixed_layout`，確認已從 `NULL` 回填為 `0`（流式）。記錄於 QA 報告「既有書籍回填流程實測」段落。

- [ ] **Step 5：第二次開書——確認不再重複判斷**

離開閱讀畫面回到書架，清空 logcat 緩衝後重新開啟同一本書（`logcat -c` 應變說明同 Step 4）：

```bash
adb -s <device-id> logcat -c
```

點擊同一本書再次開啟，執行：

```bash
adb -s <device-id> logcat -d | grep "QA-ISSUE9"
```

確認**兩件事**（缺一不可，避免偽陽性）：(a) **沒有**任何含這本書 `bookId` 的 `QA-ISSUE9` 輸出（`widget.isFixedLayout` 此時已是 Step 4 回填的非 `null` 值，`_resolveEpubEngineDispatch()` 應在 `if (_dispatchedIsFixedLayout != null) return;` 這行就提前返回，不會再呼叫 `detectAndCacheEpubLayout()`）；(b) 書籍仍正確以流式開啟並成功渲染出內容——**若 (a) 成立但 (b) 不成立**（沒有 log、但書也沒開起來/卡在載入畫面），代表 `_resolveEpubEngineDispatch()` 整條路徑根本沒有執行到，不是「正確跳過重複判斷」而是「開書流程本身壞了」，兩者不可混為一談，須在 QA 報告中明確區分。記錄於 QA 報告。

- [ ] **Step 6：還原臨時插樁**

把 `app/lib/screens/reader_screen.dart` 第 292-297 行還原為 Step 1 修改前的原始內容（移除 `debugPrint` 那一行），執行：

```bash
cd app && git diff --stat lib/screens/reader_screen.dart
```

預期：無輸出（完全無差異，插樁已完整還原）。若有殘留差異，重新比對並修正至與 Step 1 修改前逐字元相同。

- [ ] **Step 7：填寫結論**

在 QA 報告新增「## 2. 既有書籍回填流程實測」段落，填入 Step 4/5 的觀察結果與結論。由於本報告目錄已列入 `.gitignore`，不執行 `git add`；本 Task 對 `reader_screen.dart` 的插樁已於 Step 6 完整還原、`git diff` 確認乾淨，無需 commit。

---

### Task 3：FXL 路徑不受影響抽測

**Files:**
- Modify（不進版控）：`docs/epics/epic-17-epub-render-migration/reviews/qa-issue-9-report.md`

**Interfaces:**
- Consumes：既有 `EpubReaderView.kt`（Readium，Epic 17 全程未修改）
- Produces：QA 報告「FXL 路徑不受影響抽測」段落

`spec.md`「範圍界定」明訂本 Epic 全程「FXL（固定版面）EPUB 完全不受影響，繼續使用現有 `EpubReaderView.kt`（Readium），該檔案本次不修改」——已透過程式碼事實保證（`git log --follow -- app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt` 可查證 Epic 17 期間無任何 commit 觸及此檔案）。本 Task 是這個架構保證的最後一次真機行為抽測，非從零建立信心。

- [ ] **Step 1：驗證 `EpubReaderView.kt` 確實全程未被修改**

```bash
cd U:/MyDeveloper/AI/elinkBook
git log --oneline -- app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt | head -5
```

**已知的同日邊界案例（不需要重新查證，直接視為已排除）**：最新一筆命中的 commit 會是 `d1cfd17`（`docs(epic-7): Issue 9 spike——直排/橫排翻頁跳頁問題診斷與收斂`，2026-07-20 18:08），日期與 Epic 17 起源日期（2026-07-20，見 `docs/epics.md`「2026-07-20 起源自 epic-7-interaction Issue 9 spike 診斷」）同一天，單看日期無法直接判斷「早於/晚於」。已查證（`git show d1cfd17 -- app/android/.../EpubReaderView.kt`）此 commit 只修改了 `nextPage` method channel case 上方的 KDoc 註解（補充說明音量鍵翻頁〔`epic-7-interaction` Issue 7，另一個既有 Epic〕也共用同一條既有路徑），不含任何邏輯變更，且是催生 Epic 17 誕生的那次診斷 commit 本身，非 Epic 17 Phase 1 期間（Issue 1 之後）對此檔案的異動。**判準改為**：`git log` 結果中若只有 `d1cfd17` 或更早的 commit，視為驗證通過；若出現 `d1cfd17` 之後的其他 commit，才需要進一步查明原因（理論上不應該有）。

- [ ] **Step 2：匯入並開啟 FXL 測試書，抽測既有行為**

```bash
adb -s <device-id> push app/test/fixtures/sample_fixed_layout.epub /sdcard/Download/qa_issue9_fxl.epub
```

在 App 匯入 `/sdcard/Download/qa_issue9_fxl.epub`，開啟後確認：

1. 開書成功渲染出內容（無錯誤畫面）。
2. 點擊畫面中央的「⚙️」懸浮按鈕，開啟 FXL 版面設定，確認既有設定項目（字型/字級等）仍正常運作。
3. 點擊 3×3 熱區左右兩側，確認正確換頁（FXL 為整頁/跨頁切換，非流式的段落內捲動）。
4. 點擊右上角「筆記」懸浮按鈕，確認既有書籤功能可正常開啟（design.md 決策 #7：劃線/備註排除 FXL，此按鈕僅涉及書籤，非劃線/備註）。

把結果記錄於 QA 報告「FXL 路徑不受影響抽測」段落，並在結論中明確引用 Step 1 的程式碼事實查證結果作為主要證據來源（真機行為抽測是輔助確認，非唯一證據）。

- [ ] **Step 3：清理裝置端暫存檔案並填寫結論**

```bash
adb -s <device-id> shell rm /sdcard/Download/qa_issue9_fxl.epub
```

由於本報告目錄已列入 `.gitignore`，不執行 `git add`；本 Task 無程式碼異動，無需 commit。

---

### Task 4：彙整驗收狀態，更新 `issues.md`／`docs/epics.md`，清理測試素材

**Files:**
- Modify: `docs/epics/epic-17-epub-render-migration/issues.md`
- Modify: `docs/epics.md`

**Interfaces:**
- Consumes：Task 1-3 QA 報告的全部結論
- Produces：無

- [ ] **Step 1：清理書架端的暫存測試書籍**

在 App 書架畫面把 Task 1 匯入的 2 本測試書（`sample_declares_vertical.epub`／`sample_multi_chapter.epub`）與 Task 3 匯入的 `sample_fixed_layout.epub` 逐一刪除（比照既有「刪除書籍」功能），確認書架恢復到本 issue 執行前的狀態，不留下 QA 用測試書籍污染使用者的真實圖書庫。

- [ ] **Step 2：更新 `docs/epics/epic-17-epub-render-migration/issues.md`——Issue 9 完成說明**

把 Issue 9 的 `**Status:**`（現為 `ready-for-agent`）改為完成狀態，比照 Issue 1-8 既有完成說明風格，內容需涵蓋：
- Task 1-3 各自的驗證結論摘要（端到端組合驗證、既有書籍回填流程實測、FXL 路徑不受影響）
- 明確指出 Epic 17 Phase 1（流式 EPUB 遷移至 `readest/foliate-js`）的 Issue 1-9 全部完成
- 若過程中發現任何新問題，需註明已建立哪個後續 issue 追蹤（若無發現，明確寫「無」，不要含糊帶過）
- 引用 QA 報告路徑 `reviews/qa-issue-9-report.md`（並註明該檔案未進版控，僅供本機參考，結論已完整回填至本檔案）

- [ ] **Step 3：更新 `docs/epics.md`——Epic 17 狀態列**

在 `docs/epics.md` 的 `epic-17-epub-render-migration` 那一列備註最後，新增一句總結 Issue 9 收尾的結論（端到端組合驗證/既有書籍回填/FXL 抽測三項驗證結果概述），並註明：**Epic 17 Phase 1 全部 9 個 Issue（Issue 1-9）皆已完成**。狀態燈號本身維持 `🟡 開發中 (Active)`，**不要自行改成 `🟢 已歸檔 (Archived)`**——依 Global Constraints，歸檔動作需要人類明確指定，本步驟只負責把狀態列更新到「所有 Issue 皆已完成，可供人類決定何時歸檔」的乾淨狀態。

- [ ] **Step 4：`flutter analyze` 與完整測試套件最終確認**

```bash
cd app && flutter analyze
```
Expected：`No issues found!`

```bash
cd app && flutter test
```
Expected：全數 PASS（本 issue 未修改任何生產程式碼，此步驟純粹確認環境未因其他因素回歸）。

```bash
cd app/android && ./gradlew.bat :app:testDebugUnitTest
```
Expected：`BUILD SUCCESSFUL`（`issues.md` Issue 9「驗收標準」明訂三項工具皆須全過，非只有 `flutter analyze`／`flutter test` 兩項；本 issue 同樣未修改任何 Kotlin 程式碼，純粹確認既有 JVM 測試套件未因其他因素回歸）。

- [ ] **Step 5：Commit**

```bash
git add docs/epics/epic-17-epub-render-migration/issues.md docs/epics.md
git commit -m "docs(epic-17): Issue 9 彙整驗收狀態，Phase 1 Issue 1-9 全數完成"
```

---

## Self-Review（撰寫計劃時的自我檢查）

**Spec 覆蓋度**：`issues.md` Issue 9「描述」列出的 4 個項目逐一對應：
- 「端到端組合驗證：真實圖書庫匯入多本不同結構的流式 EPUB（含/不含自身 `writing-mode` 宣告、含/不含既有劃線備註），驗證開書、換頁、熱區、排版切換、目錄跳轉、劃線/備註、頁碼顯示全部正確運作」→ Task 1（Step 3/4 的操作序列逐項涵蓋全部 7 項功能點，兩本測試書分別代表「含宣告」與「不含宣告」，兩本皆在操作序列中建立劃線與備註，涵蓋「含既有劃線備註」的持久化後半段——重開書驗證正是「含既有劃線備註」情境的真正意義：不是匯入時就帶有標記的書，而是操作過程中建立、且在重開後仍存在的標記，比對 Issue 8 QA 報告已詳盡涵蓋單一功能的建立流程，本 Task 重點在於「組合＋持久化」而非重複建立流程本身）。
- 「既有書籍回填流程實測：用 Phase 1 上線前已匯入（`is_fixed_layout` 為 `null`）的既有流式 EPUB 書籍實測 `detectAndCacheEpubLayout()` 一次性判斷與回填正確，第二次開書不再重複判斷」→ Task 2（因裝置上已不存在真實舊資料，改用資料庫欄位還原人工重建情境，Step 4/5 分別驗證「一次性判斷與回填」與「不重複判斷」兩個子句）。
- 「FXL 路徑不受影響：抽測既有 FXL EPUB 開書行為與 Phase 1 上線前一致（`EpubReaderView.kt`/Readium 完全未修改）」→ Task 3（Step 1 程式碼事實查證 + Step 2 真機行為抽測雙重確認）。
- 「彙整驗證紀錄，更新 `docs/epics.md` 狀態列，若驗證中發現需要後續處理的落差，比照既有慣例另立後續 issue 追蹤，不阻塞本 Phase 1 收尾」→ Task 4（Step 2/3 彙整並更新兩份文件；Global Constraints 明確要求落差另立 issue 追蹤）。

**驗收標準覆蓋度**（審查修正：先前只核對「描述」段落，遺漏「驗收標準」段落三項，已補查）：`issues.md` Issue 9「驗收標準」列出的 3 個項目逐一對應：
- 「端到端組合驗證產出書面紀錄」→ Task 1 Step 2-5（QA 報告 1.1-1.3 節）。
- 「`flutter analyze` 乾淨、`flutter test` 全數通過、`./gradlew :app:testDebugUnitTest` 全過」→ Task 4 Step 4（三項工具皆已列出，先前草稿僅列前兩項，已補上第三項）。
- 「若有發現需要後續處理的落差，已建立對應的後續 issue 追蹤，不阻塞本 Phase 1 收尾」→ 與「描述」段落同一句要求重複，見上方 Task 4 對應項。

**占位符掃描**：全文無 TBD/待補字樣；QA 報告模板與各 Task Step 中的「<記錄...>」「<總結...>」佔位符是驗收/文件步驟本質使然（真機操作結果需要實際執行才能得知，比照 `epic-7-interaction` Issue 8、`epic-16-dual-page` Issue 7 計劃 Self-Review 對同類段落的既有認定）——所有涉及可預先撰寫的內容（QA 報告骨架結構、adb/sqlite3/Python 指令、操作序列步驟、既有測試素材路徑）皆已提供完整內容，非遺漏。

**型別一致性**：不適用（本計劃不涉及程式碼型別/介面設計，純驗證與文件性質）；Task 2 引用的既有函式簽章（`LibraryRepository.detectAndCacheEpubLayout(bookId, filePath)`、`_resolveEpubEngineDispatch()`）已對照 `app/lib/screens/reader_screen.dart:280-298`、`app/lib/library/sqlite_library_repository.dart:341` 現行原始碼逐一核對存在、行號準確。

## 審查修訂紀錄（`tmp/epic-17/reviews/review-plan-issue-9.md`／`code-review-plan-issue-9.md`，經人類確認後採納）

- **採納**：Task 4 Step 4 補上 `./gradlew :app:testDebugUnitTest`（原稿只列 `flutter analyze`／`flutter test` 兩項，遺漏 `issues.md` Issue 9 驗收標準明訂的第三項工具；Self-Review 新增「驗收標準覆蓋度」段落，補上先前只核對「描述」段落、漏查「驗收標準」段落的缺口）。
- **採納**：Task 3 Step 1 明確標註 `EpubReaderView.kt` 最新一筆 commit（`d1cfd17`，2026-07-20，與 Epic 17 起源同一天）是已查證的同日邊界案例（僅改 KDoc 註解、是催生 Epic 17 誕生的診斷 commit 本身），把原本模糊的「早於/晚於」日期判準改為「以 `d1cfd17` 為基準點」的明確指令，不留給執行者臨場查證。
- **採納**：Task 2 Step 5「不再重複判斷」新增「書籍仍成功渲染」的並列確認條件，避免「log 沒輸出」與「開書流程整條路徑沒執行到」兩種完全不同的失敗模式被誤判為同一種「通過」結果（原稿僅檢查 log 缺席，有偽陽性風險）。
- **採納**：Task 2 Step 3 Python 退路新增 `ls local_qa9_library.db` 確認本機資料庫複本已刪除的驗證指令（原稿有 `rm` 指令但無明確驗證步驟）。
- **採納**：Task 2 Step 4/5 補上 `logcat -c` 在部分裝置/Android 版本下可能無法徹底清空緩衝區的已知限制與應變說明（改用插樁訊息內建的 `bookId` 過濾，或改用 `logcat -T` 依時間戳記過濾），既有插樁天然已支援、不需額外改動插樁本身。
- **不採納**：`adb shell pm clear cc.ugotit.elinkbook` 作為 Task 4 Step 1 裝置清理備案——`pm clear` 是整包資料清空（資料庫/SharedPreferences/cache 全部歸零），效果遠超過「只刪除 3 本 QA 測試書、保留其餘真實資料」的實際需求；本開發裝置是 Epic 17 全程持續使用的同一台真機，可能留有其他非本次 QA 相關的資料，貿然建議整包清空的風險與實際需求不成比例，技術上有效不代表適合作為此處的建議。

## Execution Handoff

Plan complete and saved to `docs/epics/epic-17-epub-render-migration/plans/plan-issue-9.md`. 兩種執行方式：

1. **Subagent-Driven（推薦）**——每個 Task 交給一個全新 subagent 執行，Task 之間逐一審查，快速迭代。
2. **Inline Execution**——在本次會談中依 Task 順序批次執行，設檢查點逐一確認。

要採用哪一種方式？
