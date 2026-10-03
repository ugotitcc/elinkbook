# Epic 57 程式碼審查報告：書架「版面覆寫」儲存時保留 textConversionOverride

- **審查區間：** `cfc188997f73807f9e0f4fb50047ce4d30f7aa35` .. `0fb98b89cbb2ff6c3c51985a505f55ed2373ded4`
- **審查結論：** **Ready to merge**
- **Issue 統計：** Critical: 0 | Important: 0 | Minor: 1

---

### 1. 審查範圍與驗證

#### 1.1 變更檔案清單
- `app/lib/screens/library_screen.dart`：`_LayoutOverrideDialogState._save()` 補上 `textConversionOverride: existing.textConversionOverride`（+1 行）。
- `app/test/screens/library_screen_test.dart`：新增「版面覆寫：儲存後既有的簡繁轉換覆寫原樣保留（epic-57 回歸）」widget test（+32 行）。
- `docs/epics.md`：更新看板狀態為「已修正，待發 PR」。
- `docs/epics/epic-57-layout-override-save-drops-fields/epic.md`：更新開發記錄與 TDD 驗證狀態。

#### 1.2 驗證執行結果
- **靜態分析：** `flutter analyze` 輸出 `No issues found!`，完全乾淨。
- **針對性測試：** `flutter test test/screens/library_screen_test.dart` 執行 130 項測試全數通過（含本次新增回歸測試）。
- **關聯設定面板測試：**
  - `flutter test test/screens/reader_settings_sheet_test.dart`（95 通過）
  - `flutter test test/screens/fxl_settings_sheet_test.dart test/screens/pdf_settings_sheet_test.dart`（80 通過）
- **多語系硬編碼字串掃描：** `node tool/check_l10n_hardcoded_strings.js`
  - PASS：掃描 247 個檔案，未發現未經 AppLocalizations 包裝的硬編碼中文字串
  - PASS：掃描 275 個測試檔，所有 MaterialApp 皆帶完整 locale 設定

---

### 2. 與規格／需求對照

| 需求項目 | 規格要求 | 實作對照 | 結果 |
| :--- | :--- | :--- | :--- |
| **保留簡繁轉換覆寫** | 書架「版面覆寫」儲存時，原已存在的 `textConversionOverride` 必須原樣保留，不可清為 null | `library_screen.dart` 的 `_save()` 明確帶入 `textConversionOverride: existing.textConversionOverride` | ✅ 符合 |
| **全欄位核對** | 檢視 `BookReaderPrefs` 全部 33 個欄位，確保無其他遺漏欄位 | 逐欄比對 `book_reader_prefs.dart` 與 `_save()`，33 欄位皆已完整對齊 | ✅ 符合 |
| **TDD 回歸測試** | 以 Widget test 模擬真實使用者流程驗證（先紅後綠） | `library_screen_test.dart` 新增真實 Action Sheet/Dialog 點擊與持久化斷言測試 | ✅ 符合 |
| **其他整列重建處核對** | 盤查 `fxl_settings_sheet.dart`、`pdf_settings_sheet.dart` | 全代碼庫 `BookReaderPrefs` 建構處全面掃描，見 2.1 節分析 | ✅ 符合 |
| **文件記錄與規範** | 依專案慣例更新看板與工單開發歷程 | `docs/epics.md` 與 `epic.md` 完整同步 | ✅ 符合 |

#### 2.1 全代碼庫 `BookReaderPrefs` 建構處盤查結果
經 `git grep "BookReaderPrefs(" app/lib/` 盤查所有實例化位置：
1. `book_reader_prefs.dart`：主建構子、`fromMap`、`copyWith`、`reflowableEpubFields` 皆已具備 `textConversionOverride`。
2. `fxl_settings_sheet.dart`：整列建構已涵蓋全部 33 欄位，包含 `textConversionOverride`。
3. `reader_settings_sheet.dart`：流式 EPUB 面板，21 個 EPUB 欄位包含 `textConversionOverride`。
4. `pdf_settings_sheet.dart`：PDF 專屬局部設定面板（PDF 不支援文字轉換與字型設定），不涉本缺陷。
5. `library_screen.dart`：補齊 `textConversionOverride` 後，33 欄位全數具備。

---

### 3. Strengths

1. **精準修復**：1 行改動直擊根因，無多餘程式碼污染或非必要重構。
2. **高品質的整合測試**：新增測試非僅 mock 調用，而是完整經過 `pumpLocalizedWidget`、點擊書籍選單、開啟版面覆寫對話框、切換選項、點擊儲存，並驗證 `FakeBookReaderPrefsRepository` 讀出之狀態，具高度真實性。
3. **註解自帶警示**：`_save()` 前方已保留清楚的架構警示註解（提醒工程師未來擴充欄位時需同步補正）。
4. **開發流程忠實記錄**：`epic.md` 清楚記錄了使用者決策（採直接 TDD、免撰寫 `plan-issue-N.md`、保留 Code Review）、紅綠燈狀態及盤查結論。

---

### 4. Declined to judge

- **`PdfSettingsSheet._notifyChanged` 僅保留 PDF 欄位而未原樣帶回其餘 `BookReaderPrefs` 欄位**：
  - *理由*：PDF 閱讀器在現行架構中並無流式字型或簡繁轉換需求，`PdfSettingsSheet` 的設計自始即為獨立的局部設定面板；且 `epic.md` 已明訂其「為局部更新，不屬本缺陷，未更動」，故不在本次判定範圍。
- **泛用「`_save()` 整列重建不得遺漏任何 `BookReaderPrefs` 欄位」自動化防護機制**：
  - *理由*：`epic.md` 開發記錄已明訂此項屬於未來架構深化與防護改進，範圍較大，不在本 defect 修正範圍內，後續若有需要可另立 Issue。

---

### 5. Issues

- **Critical:** 0
- **Important:** 0
- **Minor:** 1

#### Critical (Must Fix)
無。

#### Important (Should Fix)
無。

#### Minor (Nice to Have)

- **M-1：回歸測試目前為單一欄位抽測，未全面防止未來再次發生類似「漏帶單一欄位」的情況**
  - **位置：** `app/test/screens/library_screen_test.dart:4736-4767`
  - **說明：** 在 `library_screen_test.dart` 中，先前測試抽測了 `fontSize`/`marginTop`，`epic-56` 補測了 `pdfPageTurnMode`，本次 `epic-57` 補測了 `textConversionOverride`。因為 Dart 命名參數建構子在欄位皆為 nullable 時無法提供編譯期防漏檢查（漏寫仍為合法語法），這種「發現漏一個就補一個單欄位測試」的做法，無法預防未來新增第 34 個欄位時再次發生靜默遺漏。

---

### 6. Recommendations

1. **未來建議（另立工單）：撰寫「全欄位保留」整合測試**
   可在 `library_screen_test.dart` 建立一個種子 `BookReaderPrefs`，將全部 33 個欄位均填入非 null 且唯一的數值（例如 dummy enum / 獨特數字），經由 `_save()` 儲存後，斷言除了被覆寫的 `writingModeOverride` 與 `pageTurnModeOverride` 之外，其餘 31 個欄位完全相等於原始種子。未來一旦有人新增欄位卻未更新 `_save()`，測試便會立即報警。
2. **中長期架構建議：支援 Explicit Null 的 CopyWith 模式**
   `_save()` 必須整列重建的主因是 `copyWith` 使用 `newValue ?? this.value` 語意無法將值主動重設為 `null`（「使用預設」需要清空覆寫）。若未來 `BookReaderPrefs` 引進 Sentinel Pattern（如 `const _sentinel = Object(); copyWith({Object? writingModeOverride = _sentinel})`），便可安全使用 `copyWith`，徹底杜絕整列重建漏帶欄位的風險。

---

### 7. Assessment

- **Ready to merge?** **Yes**
- **Reasoning:**
  本次修改範圍精簡、技術方案正確，完全符合 epic-57 要求。所有 33 個欄位已核對一致，靜態分析乾淨，全套相關單元/UI測試與多語系掃描均 100% 通過。Minor 建議屬長期防禦性架構提升，不影響本 PR 的正確性與發佈，建議可直接合併。
