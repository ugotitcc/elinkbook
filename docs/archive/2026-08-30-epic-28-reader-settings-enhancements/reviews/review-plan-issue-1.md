# Epic 28 Issue 1：流式 EPUB 版面設定新增字距選項 實作計畫複審報告

本報告針對 `U:\MyDeveloper\AI\elinkBook\docs\epics\epic-28-reader-settings-enhancements\plans\plan-issue-1.md` 進行全方位的技術複審，確認前次審查中提出的各項疑慮與改進建議已妥善處理或澄清。

---

## 1. 優點與亮點 (Strengths)

* **TDD 流程設計嚴密**：計畫中各個 Task 均採用了「先寫失敗測試、執行確認失敗、編寫實作程式碼、確認測試通過」的 TDD 典型步驟，有助於維持代碼開發的嚴謹性與可追溯性。
* **反序列化 `toDouble()` 防禦設計周延**：在 [`BookReaderPrefs.fromMap`](file:///U:/MyDeveloper/AI/elinkBook/app/lib/reader/book_reader_prefs.dart) 中正確採用了 `(map['letter_spacing'] as num?)?.toDouble()`，且在 [`book_reader_prefs_test.dart`](file:///U:/MyDeveloper/AI/elinkBook/app/test/reader/book_reader_prefs_test.dart) 中特別編寫了餵入 `int`（整數 `0`）的防呆測試案例。這能有效防範 SQLite 因數值無小數點而讀回 `int`，導致 `as double?` 轉型崩潰的潛在 Bug。
* **橫排與直排 CSS 規則普適性佳**：實作計畫正確指出 `letter-spacing` 作用於 CSS 的 inline 軸。在直排（`vertical-rl`）模式下 inline 軸即為垂直方向，因此橫排與直排皆可套用同一個 `letter-spacing` 覆寫規則，不需編寫複雜的排版方向判斷邏輯。
* **UI 滑桿步長與精度設計精準**：滑桿設定 step 為 `0.01em`，並計算 divisions 為 `105`（區間為 `-0.05` 至 `1.0`），且在 onChanged 中採用了 `double.parse(v.toStringAsFixed(2))` 來消除 Dart 浮點數的不精確性，保證滑桿與微調按鈕控制的精確度與流暢度。

---

## 2. 問題與疑慮 (Issues)

### Critical (必須修正)
* 無。

### Important (應該修正)

#### 1. 測試覆蓋率漏洞——未驗證 `resolve()` 的透傳與預設邏輯 `[已修訂 / Resolved]`
* **相關檔案**：[`reader_prefs_manager_test.dart`](file:///U:/MyDeveloper/AI/elinkBook/app/test/reader/reader_prefs_manager_test.dart)
* **修訂確認**：計畫中已於 **Task 1 Step 7-8** 補上對 [`reader_prefs_manager_test.dart`](file:///U:/MyDeveloper/AI/elinkBook/app/test/reader/reader_prefs_manager_test.dart) 的失敗測試步驟，並且在 **Step 9-10** 完成透傳實作後於 **Step 11** 驗證通過，符合 TDD 順序。這確保了 `resolve` 解析層級的正確性已被自動化測試覆蓋。

---

### Minor (建議優化)

#### 2. SQLite Migration 缺乏防禦性欄位存在檢查 `[已澄清 / Resolved]`
* **相關檔案**：[`sqlite_library_repository.dart`](file:///U:/MyDeveloper/AI/elinkBook/app/lib/library/sqlite_library_repository.dart) 中的 `_addLetterSpacingColumn`
* **澄清確認**：經查證，專案內既有之其他 7 個「新增單一欄位」的 helper（例如 `_addFullscreenColumn` 等）均只檢查資料表是否存在，依賴 `onUpgrade` 的 version gate（`oldVersion < 19`）來防範重複執行。為了維持與既有專案結構及開發慣例的一致性，本審查接受不採納在此 helper 中單獨加入 `PRAGMA table_info` 欄位存在檢查的決定。

#### 3. 字距為 `0.00em` 時意外覆寫書本原生字距的副作用 `[已澄清 / Resolved]`
* **相關檔案**：[`main.js`](file:///U:/MyDeveloper/AI/elinkBook/app/android/app/src/main/assets/foliate/main.js)
* **澄清確認**：計畫中指出，`ReaderSettingsSheet` 對其他既有欄位（如 `lineHeight`、`paragraphSpacing` 等）皆採用「設定面板草稿具現化原則」之全局行為（一旦使用者變更設定，欄位即被具現化為非 `null` 值一併寫入資料庫，進而覆寫書本原生對應樣式）。若在此單獨為 `letterSpacing` 加上 `!== 0` 例外，反而會打破與其他欄位的一致性。本審查接受此解釋，將此項目標註為已澄清。

#### 4. CSS 注入副作用防範提示（直排 CJK 標點與破折號斷裂） `[已修訂 / Resolved]`
* **相關檔案**：[`main.js`](file:///U:/MyDeveloper/AI/elinkBook/app/android/app/src/main/assets/foliate/main.js)
* **修訂確認**：計畫已將極端值、直排標點斷裂與 MathML/SVG 書籍的測試案例正式納入計畫末尾的「完成後的驗證」段落中。

---

## 3. 實作建議 (Recommendations)

#### 1. 修正測試步驟順序 `[已修訂 / Resolved]`
* **建議確認**：計畫已在 Task 1 重新編排，在實作 `ResolvedPreferences` 與 `resolve()` 之前，先執行 `reader_prefs_manager_test.dart` 測試確認失敗，維持了正確的 TDD 順序。

#### 2. 多書籍與極端值真機測試 `[已修訂 / Resolved]`
* **建議確認**：已於計畫末尾「完成後的驗證」中併入真機手動驗證指引，包含檢視自帶特殊字距/精排版 EPUB、SVG/MathML 書籍，以及滑桿拉至 `-0.05em` 和 `1.0em` 時的排版效果，特別留意直排引號 `「` `」` 與破折號 `——` 的顯示是否正常。

---

## 4. 評估結論 (Assessment)

* **是否已準備好開始實作 (Ready to implement)？**：準備好開始實作 (Ready to implement)。
* **評估理由**：實作計畫已完整補齊了先前審查所指出的測試覆蓋率漏洞，其餘架構決策與資料模型設計均符合專案的既有一致性設計原則，且已將直排標點斷裂與極端值等邊界測試納入驗收驗證標準，準備就緒。
