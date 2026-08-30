# Epic 34 Issue 10 實作計畫審查報告 (Plan Review Report)

**審查對象：** [`docs/epics/epic-34-tts-readalong/plans/plan-issue-10.md`](file:///U:/MyDeveloper/AI/elinkBook/docs/epics/epic-34-tts-readalong/plans/plan-issue-10.md)  
**對應工單：** [`docs/epics/epic-34-tts-readalong/issues.md`](file:///U:/MyDeveloper/AI/elinkBook/docs/epics/epic-34-tts-readalong/issues.md) Issue 10（CBZ 朗讀停用按鈕缺乏視覺區隔——與啟用狀態顏色相同）  
**診斷依據：**
- [`docs/epics/epic-34-tts-readalong/issues.md`](file:///U:/MyDeveloper/AI/elinkBook/docs/epics/epic-34-tts-readalong/issues.md)（Issue 10 需求與驗收標準）
- [`docs/epics/epic-34-tts-readalong/spec.md`](file:///U:/MyDeveloper/AI/elinkBook/docs/epics/epic-34-tts-readalong/spec.md)（朗讀控制列與格式支援範圍規範）
- [`app/lib/screens/reader_screen.dart`](file:///U:/MyDeveloper/AI/elinkBook/app/lib/screens/reader_screen.dart)（`_themedFabIconColor`、`_themedFabBackgroundColor` 與 CBZ `TtsMiniPlayer` 掛載點）
- [`app/lib/screens/tts_mini_player.dart`](file:///U:/MyDeveloper/AI/elinkBook/app/lib/screens/tts_mini_player.dart)（`TtsMiniPlayer` 元件與 `isCbz` 分支渲染邏輯）
- [`app/test/screens/reader_screen_test.dart`](file:///U:/MyDeveloper/AI/elinkBook/app/test/screens/reader_screen_test.dart)（既有 CBZ 停用狀態測試與 TTS 測試群組）  
**審查日期：** 2026-08-28  
**審查結果：** **Approved（正式核准，可直接執行）**

---

## 1. 審查總結（Executive Summary）

經逐行核對現行 Codebase 與 Issue 10 驗收標準，[`plan-issue-10.md`](file:///U:/MyDeveloper/AI/elinkBook/docs/epics/epic-34-tts-readalong/plans/plan-issue-10.md) 是一份精確、嚴謹且高度符合 E-Ink 硬體特性的實作計畫。

核心優勢與技術評估：
1. **精準指出架構演進現況**：計畫開頭明確指出 `issues.md` 的行號為 Issue 6 合併前的舊行號，並準確依據目前 `reader_screen.dart` 將播放按鈕委派給 `TtsMiniPlayer` 的最新架構進行規劃，不盲從舊文件。
2. **深刻的 E-Ink 電子紙設計防禦**：
   - 計畫深知 `issues.md` 字面提及的「降低透明度（`withValues(alpha: ...)`）」在電子紙硬體上會引發灰階抖動（dithering）渲染失真（重蹈 epic-22 Issue 4 的硬體教訓）；
   - 刻意採用**不透明實色 `Colors.grey`**（`_themedTtsDisabledIconColor`），既確保在 LCD/OLED 上呈現低對比的停用灰色，又能在 E-Ink 螢幕上以乾淨穩定的灰階色塊與啟用狀態的純白（`Colors.white`）形成清晰對比。
3. **行號與程式碼位置零誤差**：
   - 實體檔案 `app/lib/screens/reader_screen.dart` 的 `_themedFabIconColor`（第 2693-2694 行）與 `format == BookFormat.cbz` Mini Player 呼叫點（第 2255-2266 行）與計畫完全吻合。
   - 測試檔案 `app/test/screens/reader_screen_test.dart` 第 7461 行插入點與既有測試環境（`prefsManager`、`sample.cbz`、`FoliateReaderView` mock layout）完全相容。
4. **TDD 流程與測試驗證完整**：
   - Step 1 先行撰寫反向與正向斷言（`expect(icon.color, isNot(Colors.white))` 與 `expect(icon.color, Colors.grey)`）；
   - 包含單元測試、檔案級測試、`flutter analyze` 與全專案 `flutter test` 的完整防歸歸驗證。

---

## 2. 審查檢核清單（Review Checklist）

| 檢核維度 | 評估項目 | 狀態 | 備註與技術確認 |
|---|---|:---:|---|
| **規格符合度** | Issue 10 驗收標準涵蓋 | **✅ 完整** | CBZ 朗讀停用按鈕圖示視覺區隔明確，驗收標準 4 點全數覆蓋。 |
| **E-Ink 相容性** | 避免 Alpha 抖動失真 | **✅ 優秀** | 遵循 ADR/epic-22 硬體教訓，使用不透明實色 `Colors.grey` 替代 alpha 混合。 |
| **架構約束性** | 零狀態侵入與邏輯隔離 | **✅ 優秀** | 純私有 getter 與單一呼叫點參數傳遞，完全不更動 `TtsController` 或 `SystemTtsProvider`。 |
| **範圍邊界控制** | 不影響其他 FAB／按鈕 | **✅ 良好** | 僅替換 CBZ 分支之 `iconColor`，其餘流式格式與 PDF FAB 保持既有色彩體系。 |
| **檔案與行號精準度** | 實體檔案與插入點查證 | **✅ 精確** | `reader_screen.dart` 與 `reader_screen_test.dart` 行號、上下文與型別完全吻合。 |
| **測試設計品質** | TDD 失敗→實作→通過 | **✅ 健全** | 斷言清楚比對 `Icon.color`，包含明確的失敗預期與零回歸驗證。 |
| **可執行性 (Actionability)** | 無 placeholder 或模糊描述 | **✅ 完整** | 程式碼片段可直接替換，Git commit message 規範完整。 |

---

## 3. 核心設計亮點（Strengths to Preserve）

1. **避免重蹈電子紙 Alpha 混合陷阱**：
   在 `_themedTtsDisabledIconColor` 的 doc comment 與 Global Constraints 中，詳細記錄了為何不採用 `Color.withValues(alpha: 0.4)` 而採用 `Colors.grey` 的原因，為 Codebase 留下了寶貴的跨硬體設計脈絡。
2. **最小侵入式變更**：
   由於 `TtsMiniPlayer`（`app/lib/screens/tts_mini_player.dart`）已設計有 `iconColor` 參數，因此完全不需要修改 `TtsMiniPlayer` 組件本身，只需在 `ReaderScreen` 端將 CBZ 分支傳入的參數由 `_themedFabIconColor` 換為 `_themedTtsDisabledIconColor`，程式碼變更行數極小、風險極低。

---

## 4. 審查發現（Issues）

- **Critical (Must Fix)**: 無
- **Important (Should Fix)**: 無
- **Minor (Nice to Have)**: 無

---

## 5. 實作建議（Recommendations）

1. **實作階段**：本計畫可直接交付 Subagent 執行實作（推薦使用 `superpowers:subagent-driven-development`）。
2. **真機驗收**：實作完成後，可配合實體 E-Ink 裝置（如 Air Reader C / AiPaper Reader C）開啟 CBZ 漫畫，肉眼確認按鈕灰色與 EPUB 啟用狀態的純白色塊有明確的灰階反差。

---

## 6. 審查結論（Final Verdict）

- [x] **實作計畫審查正式通過（Approved）**
- **判定理由**：計畫設計簡潔、邏輯嚴密、測試步驟精確，並具備充分的 E-Ink 電子紙硬體考量，符合所有驗收標準與專案規範，已具備立即執行的成熟度。
