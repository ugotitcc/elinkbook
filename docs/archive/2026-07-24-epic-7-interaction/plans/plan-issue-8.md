# Epic 7 Issue 8 — 真機驗證與收尾 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 完成 Epic 7（互動控制）的裝置端整合驗證與收尾——3×3 導航熱區系統（4 選一模板 + 自訂模式）在 EPUB 流式／PDF／EPUB FXL 三種畫面下的端到端組合驗證、手勢競技場交叉驗證、沉浸模式一致性驗證、音量鍵驗證，並回填 Issue 4／6／7 各自遺留的「待人類真機驗證」待辦事項，最後彙整全 Epic 最終驗收狀態供人類決定是否歸檔。

**Architecture:** 本 issue **不新增產品程式碼、不新增任何自動化測試**（`issues.md` Issue 8 原文明訂「單元測試要求：無新增自動化單元測試（本 issue 以整合/裝置驗證為主）」）。全部 4 個驗證性 Task 皆為真機人工操作（必要時輔以 `adb` 指令模擬按鍵/點擊、`adb shell wm size` 取得螢幕尺寸換算熱區座標），核心產出是一份 QA 報告（`docs/epics/epic-7-interaction/reviews/qa-issue-8-report.md`，該目錄已列入根目錄 `.gitignore`，不需要／不應該 `git add`，純供收尾決策參考）與 `issues.md`／`docs/epics.md` 的最終狀態更新（會被 commit）。

**Tech Stack:** Flutter App 真機操作（`flutter run`）＋ `adb`（`shell input tap`／`shell input keyevent`／`shell wm size`／`shell am force-stop`）＋ 既有 App 內建的「導航熱區」設定畫面與「顯示熱區輔助線」除錯視覺。

## Global Constraints

- **依賴已解除**：`issues.md` Issue 8 依賴 Issue 3、4、5、6、7 全部完成——五者皆已於 2026-07-20 完成並合併回 `main`，本 issue 現已可開始。
- **裝置限制**：本開發環境目前僅有一台真機可用（`9491G`，Android 15／API 35，device id `3CEF42ECD491687`，透過 `flutter devices` 確認）。若執行時環境已更換，以當下 `flutter devices` 輸出為準，後續步驟一律以 `<device-id>` 表示。
- **單元測試要求（`issues.md` 原文）**：無新增自動化單元測試，本 issue 純粹是整合/裝置驗證與文件收斂，不修改 `app/` 下任何生產程式碼或既有測試檔。
- **驗收標準（`issues.md` 原文）**：端到端組合驗證產出書面紀錄（QA 報告）；`flutter analyze` 乾淨、`flutter test` 全數通過（本 issue 不改動程式碼，此驗收項實質是「確認沒有因為之前的變更而回歸」）；若有發現需要後續處理的落差，已建立對應的後續 issue 追蹤，不阻塞本 epic 合併。
- **`docs/epics/epic-7-interaction/reviews/` 已列入根目錄 `.gitignore`**（第 11 行）：QA 報告寫入此目錄即可，**不需要、也不應該** `git add` 這份報告——比照 `epic-4-pdf-enhance` Issue 7 既有慣例（`docs/epics/epic-4-pdf-enhance/reviews/` 同樣被排除在版控外）。真正需要 commit、長期保存的結論一律回填至 `issues.md`（會被 commit）。
- **歸檔決策保留給人類**：依 `CLAUDE.md`「生命週期」第 7 點，Epic 歸檔（搬移至 `docs/archive/`、`docs/epics.md` 狀態改為 🟢 已歸檔）一律由人類指定。Task 5 只負責把 `issues.md`／`docs/epics.md` 更新到「Epic 7 全部 8 個 Issue 皆已完成，可供人類決定是否歸檔」的乾淨狀態，**不自行執行歸檔搬移動作、不自行把 `docs/epics.md` 狀態燈號改為已歸檔**。
- **若驗證中發現落差，另立後續 issue 追蹤、不阻塞本 epic 合併**（`issues.md` 原文）：任何本 issue 過程中發現的新問題（非本計劃已預期的已知風險項），記錄於 QA 報告與 `issues.md` Task 5 段落即可，不要求當場修復；但若修復成本低、風險小（例如發現一處文件敘述已過時需要一併修正），可直接修正並如實記錄，比照 `issues.md` Issue 6「Bugfix 紀錄」既有先例。
- **回填 Issue 4／6／7 既有「待辦人工驗證」項目**：本 issue 是這些項目唯一被明確安排執行的地方，Task 1-4 的驗證範圍已涵蓋以下 3 份既有記錄的全部子項（含「裝置旋轉後熱區位置正確對應」——雖然 `issues.md` Issue 8 原文的 4 個驗證範圍未明確列出裝置旋轉，但經計畫審查討論後，人類決定既然本 issue 是 Epic 唯一的收尾 issue、Issue 4 這項待辦沒有其他後續 issue 可以收斂，改為主動擴大 Task 1 範圍一併驗證，徹底收斂技術債，見 Task 1 Step 7），執行完成後 Task 5 需回頭把結論寫回各自 issue 段落：
  - Issue 4：「依序點擊 9 宮格各格對應動作是否正確、開啟熱區輔助線視覺確認格線與標籤、熱區點擊與長按拖曳劃線交叉操作不誤觸發、裝置旋轉後熱區位置正確對應」（`app/integration_test/pdf_nav_zone_test.dart` 檔頭）
  - Issue 6：「`InputListener.onTap()` 恆回傳 `true`，是否會與既有標記啟用（`onAnnotationActivated`）或 EPUB 內部連結導覽在流式書籍中雙重觸發」（`app/integration_test/epub_stream_nav_zone_test.dart` 檔頭）
  - Issue 7：「實體/虛擬音量鍵直接按下驗證三種畫面正確翻頁、離開閱讀畫面轉場期間音量鍵即時恢復系統音量、系統音量條 UI 是否意外跳出」（`app/integration_test/volume_key_test.dart` 檔頭）
- **測試素材（已提交版本控制，直接沿用，不需另外產生）**：PDF 用 `app/test/fixtures/sample_dual_page.pdf`（6 頁，足夠驗證翻頁）；EPUB FXL 用 `app/test/fixtures/sample_fixed_layout.epub`；EPUB 流式（reflowable）用 `app/test/fixtures/sample_multi_chapter.epub`（多章節，足夠頁數供翻頁/捲動驗證）。三者皆需透過 App 既有「匯入」流程（`file_picker`，`library_screen.dart`）從裝置儲存空間匯入才能開啟——不是透過 `integration_test` 直接注入檔案路徑，因為本 issue 是操作**真實已建置的 App**、走真實使用者路徑，不是跑測試框架。
- **3×3 熱區索引慣例**：0-indexed、列優先（`0 1 2 / 3 4 5 / 6 7 8`），與 `spec.md` 全文一致。
- **固定模板常數表**（`spec.md`，人工驗證時逐格核對用）：

  | 模板 | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 |
  |---|---|---|---|---|---|---|---|---|---|
  | 左翻頁（`leftFlip`） | 下一頁 | 選單 | 上一頁 | 下一頁 | 選單 | 上一頁 | 下一頁 | 選單 | 上一頁 |
  | 右翻頁（`rightFlip`，預設值） | 上一頁 | 選單 | 下一頁 | 上一頁 | 選單 | 下一頁 | 上一頁 | 選單 | 下一頁 |
  | 單手（`oneHand`） | 選單 | 無動作 | 選單 | 上一頁 | 無動作 | 上一頁 | 下一頁 | 無動作 | 下一頁 |

- **導航熱區設定入口與元件標籤**：`SettingsScreen` →「導航熱區」→ `NavZoneSettingsScreen`；四選一 `RadioListTile` 標籤為「左翻頁」／「右翻頁」／「單手」／「自訂」；除錯輔助線開關標籤為「顯示熱區輔助線」。熱區設定為**全域生效、不分書籍**（design.md 決策 #9）——切換一次即對全部書籍/格式立即生效，不需要每種格式各自切換。
- **已於程式碼確認全專案未實作任何雙指縮放（pinch-to-zoom）手勢**（`ScaleGestureDetector`／`onScale`／`InteractiveViewer` 全專案 `grep` 皆無結果）：`issues.md` Issue 8 原文「EPUB FXL 熱區點擊與（若有）雙指縮放」的條件不成立，Task 2 對應子項記錄為「N/A（已查證不存在此手勢，非驗證疏漏）」，不得略過不提、也不得虛構一個不存在的手勢去驗證。
- **本計劃所有 Shell 指令假設在 Git Bash（POSIX）環境下執行**（`grep`／管線組合），與本 Epic 既有全部計劃一致。
- **全部 `adb` 指令一律帶 `-s <device-id>`**：避免執行環境同時連線多台裝置/模擬器時觸發 `"more than one device/emulator"` 錯誤而失敗。
- **過時文件描述修正（低成本、經計畫審查確認納入）**：Issue 4 完成說明已明文記錄 `spec.md` 第 34 行「PDF 原生層無觸控監聽、沒有搶手勢競技場對象」的敘述已於 Issue 4 實作時證實不成立（見 `issues.md` Issue 4「實作階段重大技術發現」段落）；`issues.md` 本身 Issue 4「描述」段落內也含有同一句已被推翻的過時文字。修正目標為**兩處**：`spec.md` 第 34 行，以及 `issues.md` Issue 4「描述」段落中的同一句敘述——後者是本計劃唯一一次對「描述」段落本身的修改（而非只在其上方新增「完成說明」），屬於明確的過時事實訂正，不影響本檔案「描述＝原始工單文字、完成說明另外新增於上方」的既有慣例本意（見 Task 5 Step 4）。
- **熱區座標換算公式**（供 `adb shell input tap` 精確點擊第 `index` 格，`index` 為 0-8 列優先索引；`W`／`H` 為螢幕可用內容區寬高，`col = index % 3`、`row = index ÷ 3` 取整數）：`x = W × (col + 0.5) / 3`、`y = H_top + H × (row + 0.5) / 3`（`H_top` 為畫面頂端非內容區域高度，例如 AppBar，沉浸模式收起後可視為 0；螢幕總尺寸透過 `adb shell wm size` 取得）。

---

## File Structure

| 檔案 | 異動類型 | 職責 |
|---|---|---|
| `docs/epics/epic-7-interaction/reviews/qa-issue-8-report.md` | 新增（**不進版控**，見 Global Constraints） | Task 1-4 各自產出對應段落的完整 QA 驗證紀錄 |
| `docs/epics/epic-7-interaction/issues.md` | 修改 | Issue 8 完成說明；回填 Issue 4／6／7 既有「待辦人工驗證」段落結論；修正 Issue 4「描述」段落過時的 PDF 手勢競技場敘述 |
| `docs/epics/epic-7-interaction/spec.md` | 修改 | 修正第 34 行過時的 PDF 手勢競技場敘述 |
| `docs/epics.md` | 修改 | Epic 7 狀態列彙整收尾結論（不自行改為已歸檔） |

---

### Task 1：端到端組合驗證（3 模板 + 自訂模式 × 3 種畫面）

**Files:**
- Create（不進版控）：`docs/epics/epic-7-interaction/reviews/qa-issue-8-report.md`

**Interfaces:**
- Consumes：既有 `NavZoneSettingsScreen`（`app/lib/screens/nav_zone_settings_screen.dart`）、既有「匯入」流程（`library_screen.dart`）、既有 `showNavZoneDebugOverlay` 除錯視覺（PDF／FXL 為 Dart 疊加層文字標籤；EPUB 流式目前**沒有**原生端除錯視覺實作——見 `spec.md`「EPUB 流式熱區」段落與 `EpubReaderView.kt`，`InputListener` 路徑純粹依賴 `navZoneActions` 陣列查表、不疊加任何畫面標籤，本任務對流式格式改用「逐格實際點擊＋觀察換頁/選單行為」取代「讀取除錯標籤」）
- Produces：QA 報告「端到端組合驗證」段落

**效率設計說明**：4 種模式（左翻頁/右翻頁/單手/自訂）× 3 種畫面 = 12 組合，若每組合都逐一實際點擊 9 格會產生 108 次操作，不成比例。PDF／EPUB FXL 兩種畫面有 `showNavZoneDebugOverlay` 視覺標籤，可用「開啟輔助線、肉眼比對 9 格文字標籤是否符合上方常數表」快速覆蓋全部標籤正確性（不需要逐格點擊）；只需對**預設模板（右翻頁）額外做一輪實際點擊**，確認標籤與真實點擊行為一致（標籤不是「畫好看但沒接上邏輯」）。EPUB 流式沒有除錯視覺，4 種模式皆須逐格實際點擊（3 格「上一頁/下一頁/選單」交界＋至少 1 個「無動作」格，單手模式），共 4 模式 × 3-4 個代表格 ≈ 14 次點擊，仍屬合理範圍。裝置旋轉驗證（回填 Issue 4 待辦，見 Step 7）只需在**右翻頁**模板下驗證三種畫面各一次，不需要對 4 種模式重複旋轉驗證——旋轉後的重新排版邏輯（`hitTestZoneIndex()`／`NavZoneHitTester.cellIndex()`）與目前生效的是哪個模板無關，只與螢幕尺寸有關，模板只決定查表結果、不影響座標換算本身。

- [ ] **Step 1：匯入三種格式測試書籍**

在真機上啟動已 debug build 的 App（若尚未安裝，先執行 `cd app && flutter build apk --debug && flutter install -d <device-id>`），透過以下方式把 3 個測試素材放到裝置可被系統檔案選擇器看到的位置：

```bash
adb -s <device-id> push app/test/fixtures/sample_dual_page.pdf /sdcard/Download/qa_issue8_pdf.pdf
adb -s <device-id> push app/test/fixtures/sample_fixed_layout.epub /sdcard/Download/qa_issue8_fxl.epub
adb -s <device-id> push app/test/fixtures/sample_multi_chapter.epub /sdcard/Download/qa_issue8_stream.epub
```

在 App 書架畫面點擊「匯入」，透過系統檔案選擇器依序匯入 `/sdcard/Download/` 下的三個檔案。匯入完成後書架應出現 3 本新書。

- [ ] **Step 2：建立 QA 報告檔案骨架**

建立 `docs/epics/epic-7-interaction/reviews/qa-issue-8-report.md`：

```markdown
# Epic 7 Issue 8 — 真機驗證與收尾 QA 報告

裝置：<執行當下 `flutter devices` 實際輸出的型號／API 版本／device id>
執行日期：<YYYY-MM-DD>

## 1. 端到端組合驗證（3 模板 + 自訂模式 × 3 種畫面）

### 1.1 除錯輔助線標籤比對（PDF／EPUB FXL，4 種模式）

| 畫面 | 模式 | 9 格標籤與常數表逐格比對 | 結論 |
|---|---|---|---|
| PDF | 左翻頁 | | |
| PDF | 右翻頁 | | |
| PDF | 單手 | | |
| PDF | 自訂 | | |
| EPUB FXL | 左翻頁 | | |
| EPUB FXL | 右翻頁 | | |
| EPUB FXL | 單手 | | |
| EPUB FXL | 自訂 | | |

### 1.2 預設模板（右翻頁）實際點擊驗證（PDF／EPUB FXL）

<記錄點擊左/中/右三欄的實際換頁/選單行為是否與標籤一致>

### 1.3 EPUB 流式逐格實際點擊驗證（無除錯視覺，4 種模式）

<記錄各模式下實際點擊代表格的換頁/選單/無動作行為>

### 1.4 自訂模式編輯與驗證邏輯

<記錄「至少 1 格須為選單」的儲存前驗證是否正確擋下無效設定、循環切換 4 種動作是否正常>

### 1.5 模板切換後持久化（重開 App，使用非預設模板）

<記錄切換至非預設模板後強制關閉 App 重開，Settings 畫面與三種畫面實際行為是否仍維持切換後的設定>

### 1.6 裝置旋轉後熱區位置正確對應（回填 Issue 4 待辦）

<記錄 PDF／EPUB FXL／EPUB 流式三種畫面旋轉至橫向後，9 格熱區是否正確依新版面重新排列、標籤/行為是否仍正確，以及轉回直向後是否正確復原>

### 1.7 結論

<總結：是否全數符合預期，或列出發現的落差>
```

- [ ] **Step 3：除錯輔助線標籤比對——PDF**

在「導航熱區」設定畫面開啟「顯示熱區輔助線」開關。依序選擇「左翻頁」／「右翻頁」／「單手」三個固定模板，每次切換後開啟剛匯入的 PDF 測試書，肉眼比對畫面上 9 格的文字標籤與 Global Constraints 常數表是否逐格一致，記錄於 QA 報告 1.1 節對應列。

對「自訂」模式：進入「導航熱區」畫面選擇「自訂」，依序點擊 9 格編輯器把陣列設為「上一頁, 上一頁, 選單, 無動作, 選單, 無動作, 下一頁, 下一頁, 選單」（刻意與 3 個固定模板皆不同的排列，驗證自由編輯不受限於固定模板結構），點擊「儲存」，開啟 PDF 測試書，比對 9 格標籤是否等於剛才編輯的陣列，記錄於 QA 報告。

- [ ] **Step 4：除錯輔助線標籤比對——EPUB FXL**

重複 Step 3 的四種模式流程，改為開啟剛匯入的 EPUB FXL 測試書，記錄於 QA 報告 1.1 節對應列。

- [ ] **Step 5：預設模板實際點擊驗證——PDF／EPUB FXL**

模板切回「右翻頁」（App 首次安裝的預設值）。分別開啟 PDF 與 EPUB FXL 測試書，用手指實際點擊畫面左側（index 0/3/6 任一，預期「上一頁」）、正中央（index 4，預期「選單」，觀察 AppBar/頁尾/懸浮控制項是否切換顯示）、右側（index 2/5/8 任一，預期「下一頁」），確認實際行為與 Step 3/4 讀到的標籤一致。記錄於 QA 報告 1.2 節。

- [ ] **Step 6：EPUB 流式逐格實際點擊驗證**

開啟剛匯入的 EPUB 流式測試書（`isFixedLayout == false` 分支，原生 `InputListener` 路徑，沒有除錯視覺標籤）。依序切換「左翻頁」／「右翻頁」／「單手」／Step 3 建立的「自訂」模式，每個模式下：

- 執行 `adb -s <device-id> shell wm size` 取得目前螢幕尺寸，依 Global Constraints 的座標換算公式算出「上一頁」「下一頁」「選單」三個代表格（依常數表挑選任一對應格）的螢幕座標，用 `adb -s <device-id> shell input tap <x> <y>` 點擊，觀察是否翻頁/切換沉浸模式；「單手」模式額外點擊一個「無動作」格（index 1、4 或 7），確認畫面無任何反應（不翻頁、不切換沉浸模式）。
- 若 `adb -s <device-id> shell input tap` 在此原生 `InputListener` 路徑上有任何不可靠跡象（例如點擊無反應但實際用手指觸碰畫面有反應），改用手指實際觸碰對應螢幕區域驗證，並在 QA 報告中註明改用哪種方式（比照 Issue 6 已確認 `tester.tapAt()` 對此路徑可靠的先例，`adb input tap` 預期同樣可靠，但仍需實測確認，不假設）。

記錄於 QA 報告 1.3 節。

- [ ] **Step 7：裝置旋轉後熱區位置正確對應（回填 Issue 4 待辦，經計畫審查後納入本 issue 範圍）**

模式切回「右翻頁」。依序對 PDF、EPUB FXL、EPUB 流式三本測試書執行以下流程：

1. 開啟測試書，確認目前為直向（portrait）。PDF／EPUB FXL 先開啟「顯示熱區輔助線」。
2. 旋轉裝置至橫向（實體翻轉，或 `adb -s <device-id> shell settings put system accelerometer_rotation 0 && adb -s <device-id> shell settings put system user_rotation 1`），待畫面完成橫向重新排版後：
   - PDF／EPUB FXL：肉眼確認 9 格輔助線格線與文字標籤已依橫向新尺寸重新排列（無殘留直向格線、無格子被裁切到畫面外），標籤內容與常數表仍逐格一致。
   - EPUB 流式：執行 `adb -s <device-id> shell wm size` 重新取得橫向尺寸，依座標換算公式重新算出左（上一頁）／中（選單）／右（下一頁）三個代表格座標，用 `adb -s <device-id> shell input tap <x> <y>` 點擊，確認行為仍正確（換頁/切換沉浸模式）。
3. 旋轉裝置轉回直向（`adb -s <device-id> shell settings put system user_rotation 0`，或實體翻回），重複步驟 2 的確認方式，驗證轉回直向後熱區位置與行為皆正確復原（不會停留在橫向時期算出的舊座標）。

記錄於 QA 報告 1.6 節。

- [ ] **Step 8：自訂模式驗證邏輯確認**

在「導航熱區」畫面選擇「自訂」，把全部 9 格循環切換為「無動作」（不含任何「選單」格），點擊「儲存」，確認畫面顯示錯誤提示「至少需要 1 格設為「選單」，否則將無法退出沉浸模式」且未實際儲存（可切到其他模式再切回「自訂」確認陣列未被錯誤地儲存為全無動作）。記錄於 QA 報告 1.4 節。

- [ ] **Step 9：模板切換後持久化驗證（使用非預設模板）**

把模式切換為「**左翻頁**」（**刻意不用「右翻頁」**——右翻頁是 `navZoneMode` 首次安裝的預設值，若持久化實際故障、載入失敗退回系統預設，重開後看到的「右翻頁」會與正確持久化的結果無法區分，測不出真正的缺陷；改用非預設值才能有效驗證）。執行 `adb -s <device-id> shell am force-stop cc.ugotit.elinkbook` 強制關閉 App，重新從裝置桌面啟動 App，確認：(1)「導航熱區」設定畫面顯示的模式仍是「左翻頁」；(2) 開啟任一測試書，熱區行為仍符合左翻頁模板（與常數表比對，此模板的左右欄動作與右翻頁相反）。記錄於 QA 報告 1.5 節。

- [ ] **Step 10：填寫結論並 Commit**

在 QA 報告 1.7 節填寫總結。由於本報告目錄已列入 `.gitignore`，**不執行 `git add`**；本 Task 無其他程式碼異動，無需 commit。

---

### Task 2：手勢競技場交叉驗證

**Files:**
- Modify（不進版控）：`docs/epics/epic-7-interaction/reviews/qa-issue-8-report.md`

**Interfaces:**
- Consumes：既有 PDF 長按拖曳劃線手勢（`epic-6-annotations` Issue 3）、既有 EPUB 流式標記啟用回呼 `onAnnotationActivated`／內部連結導覽（`epic-6-annotations`）
- Produces：QA 報告「手勢競技場交叉驗證」段落

- [ ] **Step 1：PDF 熱區點擊 vs. 長按拖曳劃線交叉驗證（回填 Issue 4 待辦）**

模式維持「右翻頁」。開啟 PDF 測試書：

1. 短促點擊（< 200ms，不移動手指）畫面正中央，確認觸發「選單」（沉浸模式切換），**不**同時觸發劃線選取。
2. 按住畫面任一文字區域超過長按閾值後拖曳一段距離放開，確認觸發既有的劃線框選（浮動工具列出現），**不**同時觸發熱區換頁/選單動作。
3. 重複步驟 1、2 各 3 次，確認每次結果一致（無偶發性誤觸發）。

在 `docs/epics/epic-7-interaction/reviews/qa-issue-8-report.md` 新增以下段落並填寫結果：

```markdown
## 2. 手勢競技場交叉驗證

### 2.1 PDF：熱區點擊 vs. 長按拖曳劃線（回填 Issue 4 待辦）

<記錄 3 次點擊、3 次長按拖曳的實際結果，是否有任一次誤觸發>

### 2.2 EPUB FXL：熱區點擊 vs. 雙指縮放

N/A——已於程式碼確認全專案未實作任何雙指縮放（pinch-to-zoom）手勢
（`ScaleGestureDetector`／`onScale`／`InteractiveViewer` 全專案 `grep` 皆無
結果），`issues.md` 原文「若有」的條件不成立，本項無需驗證。

### 2.3 EPUB 流式：`InputListener.onTap()` 與既有標記/內部連結雙重觸發
（回填 Issue 6 待辦）

<記錄下方 Step 2 的驗證結果>

### 2.4 結論

<總結>
```

- [ ] **Step 2：EPUB 流式熱區點擊 vs. 既有標記/內部連結雙重觸發（回填 Issue 6 待辦）**

`app/integration_test/epub_stream_nav_zone_test.dart` 檔頭記錄的待辦：`InputListener.onTap()` 恆回傳 `true`，尚未驗證是否會與既有標記啟用（`onAnnotationActivated`）或 EPUB 內部連結導覽在流式書籍中雙重觸發。

1. 在 EPUB 流式測試書中先透過既有劃線功能（長按選取文字→套用螢光筆）建立至少 1 筆劃線標記。
2. 點擊該劃線標記所在的螢幕位置，確認**只**觸發標記互動（例如彈出編輯/刪除選單），**不**同時觸發該格對應的熱區動作（換頁或選單切換）。
3. 若目前測試素材（`sample_multi_chapter.epub`）內文沒有內部連結（例如目錄跳轉連結），可略過內部連結子項，於 QA 報告註明「測試素材無內部連結內容，本次未驗證，建議後續補充含內部連結的測試素材」，不得假裝已驗證。若素材恰好含有內部連結，比照步驟 2 驗證點擊連結時是否同時誤觸發熱區動作。

把結果填入 QA 報告 2.3 節與 2.4 節結論。

- [ ] **Step 3：Commit**

本 Task 無程式碼異動、QA 報告不進版控，無需 commit。

---

### Task 3：沉浸模式一致性驗證

**Files:**
- Modify（不進版控）：`docs/epics/epic-7-interaction/reviews/qa-issue-8-report.md`

**Interfaces:**
- Consumes：既有 `_chromeVisible`／`_handleZoneAction`（`ReaderScreen`，Issue 4 建立）
- Produces：QA 報告「沉浸模式一致性驗證」段落

`app/integration_test/epub_stream_nav_zone_test.dart` 已有自動化測試涵蓋「捲動模式下左右熱區失效、選單格仍可用」（2/2 真機通過，見 Issue 6 完成說明），本 Task 對此子項是**輕量重新確認**而非從零驗證，避免重複勞動。

- [ ] **Step 1：三種畫面選單格切換一致性**

模式維持「右翻頁」。分別開啟 PDF、EPUB FXL、EPUB 流式三本測試書，各自點擊「選單」格，確認：

- PDF／EPUB 流式：AppBar 與頁尾一併顯示/隱藏。
- EPUB FXL：既有 4 個懸浮控制按鈕（返回／設定／書籤切換／筆記）一併顯示/隱藏。
- 三者切回「選單」格皆能正確復原，行為模式一致（皆為「點一下切換一次」，無需長按或其他手勢）。

在 QA 報告新增以下段落並填寫結果：

```markdown
## 3. 沉浸模式一致性驗證

### 3.1 三種畫面選單格切換

<記錄 PDF/EPUB FXL/EPUB 流式各自的顯示/隱藏切換結果>

### 3.2 EPUB 流式捲動模式左右熱區失效確認（輕量重確認，已有 Issue 6 自動化覆蓋）

<記錄輕量重確認結果，並註明已有自動化測試 2/2 通過作為主要證據來源>

### 3.3 結論

<總結>
```

- [ ] **Step 2：EPUB 流式捲動模式左右熱區失效輕量重確認**

在 EPUB 流式測試書的「⚙️版面」設定中，把換頁模式切換為「捲動」。點擊左側/右側熱區（依右翻頁模板為「上一頁」／「下一頁」的格子），確認**不**觸發翻頁（捲動模式下內容改由手指滑動捲動，非離散翻頁）；點擊「選單」格，確認仍能正常切換沉浸模式。切回「無」（分頁）換頁模式，確認左右熱區恢復正常換頁行為。

把結果填入 QA 報告 3.2 節與 3.3 節結論。

- [ ] **Step 3：Commit**

本 Task 無程式碼異動、QA 報告不進版控，無需 commit。

---

### Task 4：音量鍵驗證（回填 Issue 7 待辦）

**Files:**
- Modify（不進版控）：`docs/epics/epic-7-interaction/reviews/qa-issue-8-report.md`

**Interfaces:**
- Consumes：既有 `MainActivity.dispatchKeyEvent()`／`elinkbook/volume_key` `MethodChannel`（Issue 7 建立）
- Produces：QA 報告「音量鍵驗證」段落

`app/integration_test/volume_key_test.dart` 檔頭列出的 3 項人工驗證清單，本 Task 是這些項目首次被實際執行的地方。

- [ ] **Step 1：三種畫面音量鍵翻頁一致性**

模式維持「右翻頁」（音量鍵方向固定映射、不查詢熱區模式，見 design.md 決策 #19，故此步驟不需要對其餘模板重複驗證）。分別開啟 PDF、EPUB FXL、EPUB 流式三本測試書，各自執行：

```bash
adb -s <device-id> shell input keyevent 25   # KEYCODE_VOLUME_DOWN → 下一頁
adb -s <device-id> shell input keyevent 24   # KEYCODE_VOLUME_UP → 上一頁
```

確認三種畫面皆正確翻頁（下一頁/上一頁各驗證至少 2 次），且翻頁不影響沉浸模式（AppBar/頁尾/懸浮控制項顯示狀態不因音量鍵翻頁而改變，design.md 決策 #14）。

在 QA 報告新增以下段落並填寫結果：

```markdown
## 4. 音量鍵驗證（回填 Issue 7 待辦）

### 4.1 三種畫面翻頁一致性

<記錄 PDF/EPUB FXL/EPUB 流式各自的音量鍵翻頁結果>

### 4.2 離開閱讀畫面轉場期間音量鍵即時恢復系統音量

<記錄驗證結果>

### 4.3 音量鍵攔截消費事件後，系統音量條 UI 是否意外跳出

<記錄驗證結果，含 ACTION_UP 是否確實被消費的側面證據>

### 4.4 結論

<總結，若發現落差需註明是否已建立後續 issue>
```

- [ ] **Step 2：離開閱讀畫面轉場期間音量鍵即時恢復系統音量**

在任一測試書的閱讀畫面，按下裝置實體/虛擬返回鍵（或 `adb -s <device-id> shell input keyevent 4`）觸發離開閱讀畫面，**在退場轉場動畫播放期間**（畫面尚未完全轉回書架畫面的短暫窗口內，約 300-500ms）立刻執行一次音量鍵：

```bash
adb -s <device-id> shell input keyevent 24
```

確認此次音量鍵操作是**系統音量調整**（螢幕上或系統音量提示 UI 顯示音量條變化），**不是**閱讀器內的翻頁動作（此時應已看不到閱讀器畫面或畫面正在轉場中，不會有翻頁效果可觀察，只需確認沒有殘留的翻頁副作用，例如重新回到閱讀畫面時發現位置多跳了一頁）。此步驟時機敏感，adb 指令的執行時間點無法精確控制在轉場動畫的特定毫秒內，若第一次未能在轉場窗口內完成操作，重試數次；若持續無法在轉場窗口內完成操作驗證，於 QA 報告誠實記錄「因操作時機精確度限制未能在轉場窗口內完成驗證，改為驗證『轉場動畫結束後音量鍵確實恢復系統音量』作為降級確認」，不得虛報已驗證轉場窗口內的即時性。

把結果填入 QA 報告 4.2 節。

- [ ] **Step 3：系統音量條 UI 是否意外跳出**

在任一測試書的閱讀畫面（確認熱區攔截生效中），連續按壓音量鍵 5 次（`adb -s <device-id> shell input keyevent 24`／`25` 交替各數次，或裝置實體音量鍵），肉眼觀察螢幕上是否出現系統原生的音量提示 UI（音量條/音量 Toast）。這是驗證 Issue 7「`dispatchKeyEvent()` 攔截生效時 `ACTION_DOWN`／`ACTION_UP` 皆消費」修正是否真的在真機上生效的關鍵項目——理論分析已在計畫審查階段完成，本步驟是唯一的真機實測機會。

把結果填入 QA 報告 4.3 節。

- [ ] **Step 4：填寫結論並 Commit**

在 QA 報告 4.4 節填寫總結。本報告目錄已列入 `.gitignore`，不執行 `git add`；本 Task 無其他程式碼異動，無需 commit。

---

### Task 5：彙整驗收狀態，更新 `issues.md`／`docs/epics.md`，清理測試素材

**Files:**
- Modify: `docs/epics/epic-7-interaction/issues.md`
- Modify: `docs/epics/epic-7-interaction/spec.md`
- Modify: `docs/epics.md`

**Interfaces:**
- Consumes：Task 1-4 QA 報告的全部結論
- Produces：無

- [ ] **Step 1：清理裝置端與書架端的暫時性測試素材**

```bash
adb -s <device-id> shell rm /sdcard/Download/qa_issue8_pdf.pdf /sdcard/Download/qa_issue8_fxl.epub /sdcard/Download/qa_issue8_stream.epub
```

在 App 書架畫面把 Task 1 匯入的 3 本測試書逐一刪除（比照既有「刪除書籍」功能），確認書架恢復到 Task 1 執行前的狀態，不留下 QA 用測試書籍污染使用者的真實圖書庫。

- [ ] **Step 2：更新 `docs/epics/epic-7-interaction/issues.md`——Issue 8 完成說明**

把 Issue 8 的 `**Status:**`（現為 `ready-for-agent`）改為完成狀態，比照 Issue 4/6/7 既有完成說明風格，內容需涵蓋：
- Task 1-4 各自的驗證結論摘要（端到端組合驗證、手勢競技場交叉驗證、沉浸模式一致性、音量鍵驗證）
- 明確指出已回填 Issue 4／6／7 各自的待辦人工驗證段落結論（見下方 Step 3）
- 若過程中發現任何新問題，需註明已建立哪個後續 issue 追蹤（若無發現，明確寫「無」，不要含糊帶過）
- 引用 QA 報告路徑 `reviews/qa-issue-8-report.md`（並註明該檔案未進版控，僅供本機參考，結論已完整回填至本檔案）

- [ ] **Step 3：回填 Issue 4／6／7 的既有待辦段落**

在 `docs/epics/epic-7-interaction/issues.md` 中找到以下三處既有的「待辦（未阻擋合併...）」段落，各自追加一句話，引用 Issue 8 的驗證結論並標記為已完成：

- Issue 4 段落：「依序點擊 9 宮格各格對應動作是否正確、開啟熱區輔助線視覺確認格線與標籤、熱區點擊與長按拖曳劃線交叉操作不誤觸發、裝置旋轉後熱區位置正確對應」——4 個子項皆已在 Task 1（前 3 項）與 Task 1 Step 7（裝置旋轉，經計畫審查後納入本 issue 範圍）、Task 2 Step 1（長按拖曳交叉驗證）驗證完畢，引用 QA 報告 1.1-1.4、1.6、2.1 節結論，標記全部 4 子項為已完成。
- Issue 6 段落：「`InputListener.onTap()` 恆回傳 `true`...雙重觸發」——引用 Task 2 Step 2 的驗證結論。
- Issue 7 段落：「實體/虛擬音量鍵直接按下...音量條 Toast」——引用 Task 4 的驗證結論。

- [ ] **Step 4：修正過時文件描述——PDF 原生層手勢競技場敘述**

`docs/epics/epic-7-interaction/spec.md` 第 34 行與 `docs/epics/epic-7-interaction/issues.md` Issue 4「描述」段落皆含有「PDF 原生層無觸控監聽、沒有搶手勢競技場對象」的敘述，已於 Issue 4 實作階段證實不成立（`GestureDetector.onTapUp` 包住 `AndroidView` 時，`AndroidView` 內建的被動 recognizer 依「先加入者勝出」規則必贏，與原生層是否有觸控監聽無關；已對照 Flutter SDK 原始碼驗證，見 `issues.md` Issue 4「實作階段重大技術發現」段落）。

在兩處分別把該句敘述修正為：原生層是否有觸控監聽與 `AndroidView` 是否贏得手勢競技場無關；PDF 熱區改由既有 `Listener`（`_handleAnnotationPointerDown`/`_handleAnnotationPointerUp`）手動座標判讀，正確區分點擊與既有長按拖曳劃線手勢（見 `issues.md` Issue 4 完整技術發現段落）。`issues.md` 的修正僅限這一句過時敘述本身，不改寫該段落其餘文字，不影響「描述＝原始工單文字」的既有慣例本意。

- [ ] **Step 5：更新 `docs/epics.md`——Epic 7 狀態列**

在 `docs/epics.md` 的 `epic-7-interaction` 那一列備註最後，新增一句總結 Issue 8 收尾的結論（端到端組合驗證/手勢競技場/沉浸模式/音量鍵四項驗證結果概述），並註明：**Epic 7 全部 8 個 Issue（Issue 1-8）皆已完成**。狀態燈號本身維持 `🟡 開發中 (Active)`，**不要自行改成 `🟢 已歸檔 (Archived)`**——依 Global Constraints，歸檔動作需要人類明確指定，本步驟只負責把狀態列更新到「所有 Issue 皆已完成，可供人類決定何時歸檔」的乾淨狀態。

- [ ] **Step 6：`flutter analyze` 與完整測試套件最終確認**

```bash
cd app && flutter analyze
```
Expected：`No issues found!`

```bash
cd app && flutter test
```
Expected：全數 PASS（本 issue 未修改任何生產程式碼，此步驟純粹確認環境未因其他因素回歸）。

- [ ] **Step 7：Commit**

```bash
git add docs/epics/epic-7-interaction/issues.md docs/epics/epic-7-interaction/spec.md docs/epics.md
git commit -m "docs(epic-7): Issue 8 彙整驗收狀態，Epic 7 Issue 1-8 全數完成"
```

---

## Self-Review（撰寫計劃時的自我檢查）

**Spec 覆蓋度**：`issues.md` Issue 8「描述」列出的 6 個項目逐一對應：
- 「端到端組合驗證（人工視覺 QA）」→ Task 1
- 「手勢競技場交叉驗證」→ Task 2
- 「沉浸模式驗證」→ Task 3
- 「音量鍵驗證」→ Task 4
- 「彙整驗證紀錄，更新本檔案各 issue 最終驗收狀態，並更新 `docs/epics.md` 狀態列」→ Task 5
- 「若驗證中發現需要後續處理的落差，另立後續 issue 追蹤」→ Global Constraints 明確要求、Task 5 Step 2 要求明確記錄（無論有無發現皆須明確寫出，不得含糊）
另外主動識別並回填了 Issue 4／6／7 三份既有「待辦人工驗證」記錄——這些原本沒有被安排在任何未來 issue 執行，Issue 8 作為 Epic 收尾 issue 是唯一合理的執行位置，已在 Task 1（Issue 4 的 9 宮格/除錯視覺/裝置旋轉子項）、Task 2（Issue 4 的長按拖曳交叉驗證子項、Issue 6 的雙重觸發子項）、Task 4（Issue 7 全部 3 子項）中明確涵蓋並在 Task 5 Step 3 要求回填結論。**範圍決策記錄**：Issue 4 待辦中的「裝置旋轉後熱區位置正確對應」子項原不在 `issues.md` Issue 8 原文列出的 4 個驗證範圍內；初版計畫刻意標記為範圍外、留待人類決定，經計畫審查（`tmp/epic-7/reviews/plan-issue-8-review.md`）提出「Issue 8 是 Epic 唯一收尾 issue，此項無其他 issue 可收斂」的論點後，由人類明確決定納入，已改為 Task 1 Step 7 的正式驗證項目，不再是範圍缺口。

**占位符掃描**：全文無 TBD/待補字樣；QA 報告模板與各 Task Step 中的「<記錄...>」「<總結...>」佔位符是驗收/文件步驟本質使然（真機操作結果需要實際執行才能得知，比照 `epic-16-dual-page`／`epic-4-pdf-enhance` Issue 7 計劃 Self-Review 對同類段落的既有認定）——所有涉及可預先撰寫的內容（QA 報告骨架結構、adb 指令、座標換算公式、常數表、元件標籤、既有待辦事項引用）皆已提供完整內容，非遺漏。

**型別一致性**：不適用（本計劃不涉及程式碼型別/介面設計，純驗證與文件性質）；引用的既有元件標籤（`RadioListTile` 標籤「左翻頁」/「右翻頁」/「單手」/「自訂」、`SwitchListTile` 標籤「顯示熱區輔助線」）與熱區動作中文標籤（「上一頁」/「下一頁」/「選單」/「無動作」，對應 `_actionLabel()`）皆已對照 `app/lib/screens/nav_zone_settings_screen.dart` 現行原始碼逐一核對存在。

## 審查修訂紀錄（`tmp/epic-7/reviews/plan-issue-8-review.md`，經人類確認後採納）

- **採納**：全部 `adb` 指令補上 `-s <device-id>`（原 Task 1 Step 6、Step 8 三處遺漏，現已逐一修正並加入 Global Constraints 統一要求）。
- **採納**：Task 1 模板持久化驗證改用非預設值「左翻頁」而非「右翻頁」（原設計若持久化真的故障、退回系統預設，會與「右翻頁」正確持久化的結果混淆而測不出缺陷；現 Task 1 Step 9）。
- **採納**：裝置旋轉後熱區位置正確對應（Issue 4 遺留待辦）納入 Task 1 驗證範圍——經人類明確決定，理由是 Issue 8 為 Epic 唯一收尾 issue，此項無其他 issue 可收斂，屬主動擴大範圍的決策而非審查者單方面認定（現 Task 1 Step 7）。
- **採納**：過時文件描述（PDF 原生層手勢競技場敘述已被 Issue 4 實作證實不成立）修正目標經人類確認為**兩處**——`spec.md` 第 34 行（Issue 4 完成說明已明確命名的既有待辦）以及 `issues.md` Issue 4「描述」段落中的同一句敘述（審查報告字面指定的位置；本計劃原判斷修正「描述」段落會破壞本檔案既有的審計軌跡慣例，但人類決定兩處都修，現 Task 5 Step 4）。

## Execution Handoff

Plan complete and saved to `docs/epics/epic-7-interaction/plans/plan-issue-8.md`。兩種執行方式：

1. **Subagent-Driven（推薦）**——每個 Task 交給一個全新 subagent 執行，Task 之間逐一審查，快速迭代。
2. **Inline Execution**——在本次會談中依 Task 順序批次執行，設檢查點逐一確認。

要採用哪一種方式？
