# Epic 27 Issue 4 實作計畫審查報告

**審查對象：** `docs/epics/epic-27-reader-device-compat/plans/plan-issue-4.md`  
**審查目標：** 審查版面設定「另存為新預設集」點擊後彈窗無反應之實作計畫架構合理性、防禦性與可觀測性設計、TDD 測試流程自洽性、既有成功路徑零回歸保證。  
**審查標準：** 需求與根因對齊、防禦性與可觀測性策略有效性、TDD Red-Green 流程嚴謹度、程式碼與行號精確度、零回歸邊界。  
**審查狀態：** ✅ 技術審查通過（附 TDD 執行順序優化建議，Ready to implement）

---

## 1. 優點與亮點 (Strengths)

1. **防禦性與可觀測性策略精準對齊真機問題**：
   - 鑑於真機 Release build 下 Gesture handler 拋出例外會被靜默吞掉且 `repository == null` 是唯一可能造成靜默 return 的路徑，計畫採取「雙層防守」：
     1. `repository == null` 分支補上明確的 `SnackBar` 使用者提示（`Key('reader_save_as_preset_repository_unavailable_snackbar')`，文字「暫時無法儲存預設集」）。
     2. 方法本體以 `try / catch` 完整包覆，遇到任何未預期例外時輸出 `debugPrint` 堆疊並顯示 `SnackBar`（`Key('reader_save_as_preset_error_snackbar')`）。
   - 此設計不盲目臆測單一根因，而是徹底消除所有「靜默失敗」路徑，大幅提升真機可觀測性。

2. **測試設計精巧，無侵入式模擬真機異常**：
   - 計畫善用 `LayoutPresetRepository` 為一般 class（非 `final`/`sealed`）的特性，在測試中定義 `_ThrowingLayoutPresetRepository` 僅覆寫 `insert()` 拋出例外，其餘 `listAll()` 仍使用真實記憶體內 SQLite 連線，完全不干擾 `ReaderScreen` `initState()` 時期的 `_loadLayoutPresets()` 正常初始化。
   - 擴充 `pumpReaderScreen()` helper 增加 `includeLayoutPresetRepository` 與 `layoutPresetRepositoryOverride` 具名參數，預設值保持與既有行為完全一致，實現既有測試零改動、零回歸。

3. **嚴謹遵守 Flutter 非同步 UI 與專案既有慣例**：
   - `catch` 分支在執行 `ScaffoldMessenger.of(context).showSnackBar` 之前精確加上 `if (!mounted) return;` 檢查，防範 async gap 導致的 context 失效問題。
   - 錯誤提示與 `SnackBar` 命名風格完全對齊專案既有規範（`Key` 命名規範明確、不引入多餘的 helper 元件）。

4. **上下文與行號定位 100% 精準**：
   - 經與程式碼庫比對，`reader_screen.dart:774-806`（`_handleSaveAsPreset`）與 `reader_screen_test.dart:6677-6709`（`pumpReaderScreen` 定義）、第 6783 行（插入點）之行號與周遭代碼完全精準吻合。

---

## 2. 審查發現與改進建議 (Issues & Recommendations)

### Important #1：Step 3 實作範例提前包覆 `try/catch`，將導致 Step 6 測試無法呈現預期的紅燈（FAIL）

- **問題描述**：
  在計畫的 Task 1 中：
  - Step 3 的程式碼修改範例直接將 `if (repository == null)` 提示 **以及** `try { ... } catch (e, stackTrace) { ... }` 一併實作。
  - 接著 Step 5 撰寫第二則失敗測試（模擬 insert 拋出例外），Step 6 預期測試失敗（紅燈），Step 7 註記「已於 Step 3 一併完成」。
  - 若執行者在 Step 3 即寫入完整的 `try/catch`，則在 Step 5 新增測試後，Step 6 執行測試時會**直接通過（綠燈）**，無法驗證「測試在未實作 `try/catch` 前能有效捕獲未攔截例外」的紅燈階段。
- **改進建議（執行者於實作時遵循）**：
  建議執行者在 TDD 過程中落實兩階段實作：
  1. **階段一（處理 `repository == null`）**：
     - Step 1 新增測試 1。
     - Step 2 執行測試 1 確認紅燈（FAIL）。
     - Step 3 **僅在 `if (repository == null)` 分支加入 `SnackBar` 提示與 `return;`**（暫不包覆外層 `try/catch`）。
     - Step 4 執行測試 1 確認綠燈（PASS）。
  2. **階段二（處理未捕捉例外 `try/catch`）**：
     - Step 5 新增 `_ThrowingLayoutPresetRepository` 與測試 2。
     - Step 6 執行測試 2 確認紅燈（FAIL，此時因未包覆 `try/catch` 會拋出未捕捉例外）。
     - Step 7 **為方法本體加上 `try/catch`、`debugPrint` 與錯誤提示 `SnackBar`**。
     - Step 8 執行測試 2 確認綠燈（PASS）。

---

## 3. 實作建議與執行指引 (Implementation Guidelines)

1. **依 TDD 節奏循序實作**：
   - 按照上述階段一與階段二的順序執行，確保每則測試均經過真實的 Red-Green 循環驗證。
2. **驗證全專案測試與分析**：
   - 實作完成後，務必執行：
     ```bash
     cd app
     flutter analyze
     flutter test
     ```
   - 確認全專案無任何 warning/error，且測試總數正確增加 2 則。

---

## 4. 評估結論 (Assessment)

- **是否已準備好開始實作 (Ready to implement)？**  
  **【是 / 準備好開始實作 (Ready to implement)】**

- **評估理由：**  
  本計畫架構清晰、零回歸邊界明確、防禦策略精準有效、測試設計考量深思熟慮。只需在實作執行時留意將 Step 3 與 Step 7 的程式碼按 TDD 節奏分步落地，即可確保實作品質與驗證嚴謹性。
