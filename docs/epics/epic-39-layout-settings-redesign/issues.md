# issues.md — epic-39-layout-settings-redesign

垂直切片工單清單。每個 Issue 皆須以 TDD（紅-綠-重構）完成，實作前先寫 `plans/plan-issue-<N>.md` 並發起審查。

## Issue 1：新增共用元件 `EBStepper`／`EBOptionChipGroup`

**範圍**：`app/lib/screens/widgets/eb_stepper.dart`（新檔）、`app/lib/screens/widgets/eb_option_chip_group.dart`（新檔）、`app/lib/screens/widgets/reader_option_tile.dart`（擴充 `iconSize`/`labelFontSize` 兩個可選參數）。不動任何既有呼叫端（`ReaderSettingsSheet`／`PdfSettingsSheet`／`FxlSettingsSheet` 留給後續 Issue 改接）。

**單元測試要求**：
- `EBStepper`：顯示 `displayValue`；點擊 `+`/`-` 觸發 `onChanged` 並帶入 `value ± step`（clamp 到 `[min, max]`）；超出邊界時對應按鈕 `onPressed` 為 `null`（停用）；無 `Slider` 或任何可拖曳元件存在於 widget tree。
- `EBOptionChipGroup`（審查修正 M1，review-issues.md／依 `spec.md` I2 修正後的寬度演算法撰寫，不再是「56dp/item」）：依 `LayoutBuilder` 的 `constraints.maxWidth`**絕對寬度**（非除以 `items.length`）驗證三種情境——`maxWidth >= 360` 時圖示+文字皆顯示且為上限尺寸（20sp/13sp）；`maxWidth` 介於 240～360 之間時尺寸線性介於上下限之間；`maxWidth <= 240` 時圖示/文字為下限尺寸（16sp/11sp）；`maxWidth < 200` 時只顯示圖示、`label` 對應的 `Text` 不存在。額外驗證：6 個項目的群組在典型手機寬度（`maxWidth` 約 320～360dp）下**不會**因為除以項目數而被誤判為過窄（即label 不應消失）。點擊任一 chip 觸發 `onSelected` 並帶入該 chip 的 `value`；`item.onTap` 非 null 時點擊改觸發該 callback，不呼叫 `onSelected`，且該 chip 恆為未選中樣式（不論 `groupValue` 為何）。
- `ReaderOptionTile`：新增的 `iconSize`/`labelFontSize` 參數正確套用到 `Icon`/`Text` 的對應樣式欄位；未提供時維持既有預設值（既有測試零回歸）。

## Issue 2：`ReaderSettingsSheet` 文字＋邊界分頁 — Slider/EBStepper 切換與覆寫文字徽章

**範圍**：`ReaderSettingsSheet` 新增 `isEinkMode` 建構參數；`_buildSliderRow` 依 `isEinkMode` 切換 `Slider` 或 `EBStepper`（`isEinkMode: true` 時頂列隱藏 `Text(displayValue)`，避免與 `EBStepper` 內顯示的數值重複）；「已覆寫／使用全域預設」改為文字徽章。`ReaderScreen` 呼叫處補上 `isEinkMode: widget.isEinkMode`。**範圍涵蓋「文字」與「邊界」兩個分頁**（審查修正 I2，review-issues.md：`_buildSliderRow` 是兩個分頁共用的私有方法，「邊界」分頁的上/下/左/右邊界 4 個數值列會一併受影響，不能只驗證「文字」分頁）。

**單元測試要求**：
- `isEinkMode: false`（預設）時，「文字」分頁 5 個數值列（字級/字重/行高/段落間距/字距）與「邊界」分頁 4 個數值列（上/下/左/右邊界）皆維持既有 `Slider` 存在，既有測試零回歸。
- `isEinkMode: true` 時，上述 9 個數值列皆改為 `EBStepper`（兩個分頁內 `find.byType(Slider)` 皆 `findsNothing`），`+`/`-` 互動行為與既有 `Slider`／微調按鈕等價（觸發 `onChanged` 帶正確 callback 值）；四邊邊界欄位不支援覆寫語意（`isOverridden == null`），確認其 `EBStepper` 版本同樣不顯示覆寫徽章。
- 已覆寫的欄位顯示文字「此書已覆寫」，點擊仍可重置（既有 reset 行為零回歸）；未覆寫顯示「使用全域預設」，且**維持掛載 `Key('${keyPrefix}_unset_indicator')`**（審查修正 C2，review-issues.md／review-spec.md：既有 6 處測試斷言依賴此 Key，只是底下元件從 `Icon` 換成 `Text`，Key 語意與既有測試寫法皆不變）；`isOverridden == null`（不支援覆寫語意）的欄位不顯示徽章。

## Issue 3：`ReaderSettingsSheet` 分頁重組（文字對齊搬移＋單選群組改用 `EBOptionChipGroup`＋欄位大小步進器）

**範圍**：Tab 顯示文字改名（`文字內容`→`文字`／`邊界首尾`→`邊界`／`版面呈現`→`呈現`／`設定喜好`→`預設集`，Key 不變）；`_buildTextAlignRow()` 從邊界分頁搬到呈現分頁；`_buildColumnModeRow`／`_buildTextAlignRow`／`_buildWritingModeOverrideRow`／`_buildPageTurnModeOverrideRow`／`_buildScreenOrientationOverrideRow` 改用 `EBOptionChipGroup`（套用 spec.md「選項標籤對照表」的 label）；`_buildColumnModeRow()` 內獨立的 `reader_settings_column_size_slider` 依 `isEinkMode` 切換 `EBStepper`（審查修正 I3，review-issues.md／C3，review-spec.md：此控制項不經過 `_buildSliderRow`，Issue 2 不會處理到，須在本 Issue 一併納入）。

**⚠️ 本 Issue 必要配套（審查修正 C1，review-issues.md／review-spec.md）：Tab 改名會直接影響既有測試**——`app/test/screens/reader_settings_sheet_test.dart` 的 `switchToTab(tester, tabLabel)` helper（L1560-1563）是依 `find.widgetWithText(Tab, tabLabel)` 純文字比對，全檔 **43 處**呼叫點使用舊分頁名稱（`'邊界首尾'`／`'版面呈現'`／`'設定喜好'`／`'文字內容'`）。**`reader_settings_sheet_test.dart` 本身正式列入本 Issue 修改範圍**：須同步將 `switchToTab` 的呼叫點字串改為新名稱（`'邊界'`／`'呈現'`／`'預設集'`／`'文字'`），確保全部既有測試在改名後依然能正確定位分頁——這是測試維護，不是「零回歸」（分頁名稱本身就是異動的一部分），但改完後既有測試驗證的行為語意必須維持不變。

**單元測試要求**：
- 四個 `Tab` 的 `text` 分別為「文字」「邊界」「呈現」「預設集」，`Key` 維持既有值；`reader_settings_sheet_test.dart` 全部 43 處 `switchToTab` 呼叫點已改用新名稱且全數通過。
- 「文字對齊」在「邊界」分頁的 `ListView`（`reader_settings_tab_boundary_list`）內 `findsNothing`，在「呈現」分頁的 `ListView`（`reader_settings_tab_presentation_list`）內 `findsOneWidget`。
- 5 組單選群組（欄數/文字對齊/書寫方向/翻頁模式/螢幕方向）改用 `EBOptionChipGroup` 後，既有的選取/點擊切換測試（依 `Key` 定位個別選項）零回歸；文字對齊維持 6 個選項全部存在；螢幕方向維持 6 個選項（含「全域」）全部存在。
- `reader_settings_column_size_slider`：`isEinkMode: false` 維持既有 `Slider`（既有測試零回歸）；`isEinkMode: true` 時（且 `_columnMode == ColumnMode.auto`）改為 `EBStepper`，`+`/`-` 互動觸發 `onChanged` 帶正確值，`min`/`max` 邊界 clamp 行為與既有 `Slider` 等價。

## Issue 4：`ReaderSettingsSheet` 預設集分頁 — 「目前套用中」標示

**範圍**：`_buildLayoutPresetSection()`／`_buildPresetSlot()` 新增「目前套用中」視覺標示：`preset.prefs == _currentDraft` 時整列反白，並**隱藏／替換掉既有的「套用到本書」`IconButton`**（改為獨立的「已套用」指示器，`Key('reader_settings_preset_slot_${index}_active_indicator')`），「套用到其他書籍」與「刪除」兩顆按鈕維持顯示。**審查修正 I1（review-issues.md）**：現有 `_buildPresetSlot()` 每一列非空預設集本來就有一顆 `icon: Icons.check` 的「套用到本書」按鈕（`reader_settings_sheet.dart:955-960`）——不能單純「加一顆 `Icons.check`」，會與既有按鈕並存造成兩個打勾同時出現；測試也不可用裸 `find.byIcon(Icons.check)` 斷言（每一列本來就都有），須改用新的專屬 Key。

**單元測試要求**：
- 目前草稿設定值與某個已存預設集的 `prefs` 完全相等時：該預設集列反白（底色為 `colorScheme.inverseSurface`）；`Key('reader_settings_preset_slot_${index}_active_indicator')` 存在；原本的 `Key('reader_settings_preset_slot_${index}_apply_current')`（套用到本書按鈕）改為 `findsNothing`；「套用到其他書籍」／「刪除」兩顆按鈕仍 `findsOneWidget`。
- 其餘不相等的預設集列維持一般樣式：`_active_indicator` 為 `findsNothing`，`_apply_current` 按鈕維持 `findsOneWidget`（既有行為零回歸）。
- 使用者調整任一數值後（草稿不再與任何預設集相等），先前反白的那一列恢復一般樣式（`_active_indicator` 消失、`_apply_current` 按鈕重新出現）。
- E-Ink 模式下反白改用純黑底白字（`isEinkMode: true` 情境的獨立測試），且反白列內文字/圖示前景色為 `colorScheme.onInverseSurface`（驗證不會出現「深底深字」對比度不足的組合）。

## Issue 5：`PdfSettingsSheet` 視覺風格對齊

**範圍**：新增 `isEinkMode` 建構參數；`_buildSliderRow`（對比度/亮度/加粗強度）依 `isEinkMode` 切換 `EBStepper`；顯示/裁切分頁 5 組單選群組改用 `EBOptionChipGroup`；卡片邊框/文字色改跟隨 `Theme.of(context)`。`ReaderScreen` 呼叫處補上 `isEinkMode`。

**單元測試要求**：
- `isEinkMode: false` 時濾鏡分頁維持 `Slider`；`isEinkMode: true` 時濾鏡分頁 3 個數值列改為 `EBStepper`，互動行為等價。
- 顯示/裁切分頁的 5 組單選群組（Fit 模式/雙頁模式/頁面方向/換頁動畫/裁切模式）改用 `EBOptionChipGroup` 後，既有選取/點擊測試零回歸。
- 「手動選區」項目改用 `EBOptionChipItem.onTap` 承載（審查修正 I4，review-issues.md／I1，review-spec.md：`EBOptionChipGroup` 已在 Issue 1 支援 `onTap` 動作型項目，本 Issue 直接使用，不再需要獨立於群組之外的 `ReaderOptionTile`）：點擊觸發 `widget.onRequestManualCrop()`，不改變 `_cropMode`、不觸發 `_notifyChanged()`；不論裁切模式群組目前選中哪個值，該項目恆為未選中樣式（既有行為零回歸）。

## Issue 6：`FxlSettingsSheet` 視覺風格對齊

**範圍**：新增 `isEinkMode` 建構參數（暫不影響任何渲染分支，純介面一致性，plan 階段可與人類確認是否保留）；兩組單選群組（雙頁模式/翻頁方向）改用 `EBOptionChipGroup`；三顆 `SwitchListTile` 視覺跟隨主題色。

**單元測試要求**：
- 兩組單選群組改用 `EBOptionChipGroup` 後，既有選取/點擊測試零回歸。
- 三顆開關（全螢幕模式/顯示頁首/顯示頁尾）既有 `onChanged` 行為零回歸。

---

**收尾**：Issue 6 完成後，跑一次完整 `flutter test`（無參數）＋ `flutter analyze`，確認零回歸，交由人類決定是否合併與歸檔。

## 審查回應（2026-09-08，`reviews/review-issues.md`）

- **C1（Issue 3 忽視 Tab 改名對既有測試的衝擊）**：已訂正，`reader_settings_sheet_test.dart` 正式列入 Issue 3 修改範圍，43 處 `switchToTab` 呼叫點須同步改名。
- **C2（Issue 2 遺漏 `_unset_indicator` Key 契約）**：已訂正，明確要求文字徽章維持掛載該 Key。
- **I1（Issue 4「無勾勾」與既有 `Icons.check` 按鈕矛盾）**：已訂正，改為隱藏／替換「套用到本書」按鈕為專屬 `_active_indicator` Key，測試不再依賴裸 `Icons.check`。
- **I2（Issue 2 遺漏邊界分頁 4 個 Slider）**：已訂正，Issue 2 標題與範圍擴大為「文字＋邊界分頁」，涵蓋兩分頁共 9 個數值列。
- **I3（Issue 3 遺漏 `reader_settings_column_size_slider`）**：已訂正，納入 Issue 3 範圍與測試要求。
- **I4（Issue 5 未規劃手動選區整合策略）**：已訂正，改用 `EBOptionChipItem.onTap`（`spec.md` I1 已定案的方案）。
- **M1（Issue 1 晶片測試要求需配合寬度公式修正）**：已訂正，測試要求改依 `spec.md` I2 修正後的絕對寬度分級演算法撰寫。
