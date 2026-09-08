# spec.md — epic-39-layout-settings-redesign

本檔案為本 Epic 的唯一事實來源，定義新增/異動的核心介面與型別。決策脈絡見同目錄 `design.md`。

## 新增元件

### 1. `EBStepper`（`app/lib/screens/widgets/eb_stepper.dart`）

E-Ink 模式專用的純步進器，補實作 `DESIGN.md` §18.3：無可拖曳滑桿，只有 `-`／數值／`+` 三段。

```dart
class EBStepper extends StatelessWidget {
  final String keyPrefix; // 產生 '${keyPrefix}_decrement'/'_value'/'_increment' 三個 Key
  final double value;
  final double min;
  final double max;
  final double step;
  final String displayValue; // 呼叫端已格式化好的顯示字串（比照既有 _buildSliderRow displayValue 參數）
  final ValueChanged<double> onChanged;

  const EBStepper({
    super.key,
    required this.keyPrefix,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.displayValue,
    required this.onChanged,
  });
}
```

- 邊界行為（超出 min/max 時按鈕停用）與既有 `_buildSliderRow` 的 `_decrement`/`_increment` 按鈕完全一致（沿用相同的 `1e-9` 浮點容許誤差比較）。
- 純 `StatelessWidget`，顏色一律讀 `Theme.of(context).colorScheme`（E-Ink 主題下 `ColorScheme` 本身已是純黑白，見 `app_theme_data.dart` `_buildEinkTheme()`），元件本身不寫死顏色、不判斷 `isEinkMode`——呼叫端已經知道自己在 E-Ink 模式才會建構這個 widget。

### 2. `EBOptionChipGroup<T>`（`app/lib/screens/widgets/eb_option_chip_group.dart`）

取代目前散落在三個檔案共 13 處「`Wrap` 包一組 `ReaderOptionTile`」的重複寫法，統一負責「依可用寬度縮放圖示/文字大小、低於門檻只顯示圖示」的響應式邏輯（`design.md` Q8）。

```dart
class EBOptionChipItem<T> {
  final Key? itemKey;
  final T value;
  final IconData icon;
  final String label; // 中文 ≤ 2 字
  final String tooltip;
  // 動作型項目（審查修正 I1，review-spec.md）：非 null 時點擊直接執行
  // onTap，不呼叫外層 EBOptionChipGroup.onSelected、也不參與
  // groupValue 選中比對（該 chip 恆為未選中樣式）——供 PdfSettingsSheet
  // 裁切分頁的「手動選區」這種「點擊觸發外部動作、不代表一個可選值」
  // 的項目使用，比照現有 ReaderOptionTile<bool>(value:true,
  // groupValue:false,...) sentinel 寫法但語意明確化。
  final VoidCallback? onTap;

  const EBOptionChipItem({
    this.itemKey,
    required this.value,
    required this.icon,
    required this.label,
    required this.tooltip,
    this.onTap,
  });
}

class EBOptionChipGroup<T> extends StatelessWidget {
  final List<EBOptionChipItem<T>> items;
  final T groupValue;
  final ValueChanged<T> onSelected;
  final VisualDensity visualDensity;

  const EBOptionChipGroup({
    super.key,
    required this.items,
    required this.groupValue,
    required this.onSelected,
    this.visualDensity = VisualDensity.standard,
  });
}
```

- **寬度縮放演算法（審查修正 I2，review-spec.md：原「`maxWidth / items.length`」公式與 `Wrap` 折行特性衝突——6 選項群組在常規手機直向寬度下會被誤判為「永遠過窄」，但 `Wrap` 實際上會自動折成兩行，每行 3 顆的可用寬度綽綽有餘）**。改為直接依容器**絕對寬度**（`LayoutBuilder` 的 `constraints.maxWidth`，不除以 `items.length`）分級，不假設單行排滿：
  - `maxWidth >= 360`：圖示 20sp／文字 13sp（`ReaderOptionTile` 現有預設值，即最寬鬆情境維持原樣不變）。
  - `maxWidth <= 240`：圖示 16sp／文字 11sp（`labelSmall`）。
  - 介於兩者之間：線性內插。
  - `maxWidth < 200`（Bottom Sheet 本身異常窄，例如極端小螢幕或裝置分割視窗）時，不顯示 `label`，只留圖示＋既有 tooltip 機制。
  - 以上門檻值為實作者依 `DESIGN.md` 字級 Token 訂出的預設值，非嚴格規格，Task 內可微調但不需要另外詢問使用者。
- 內部仍然渲染 `Wrap` of `ReaderOptionTile`（不改變既有 chip／可換行排列邏輯），只是額外傳入計算後的 `iconSize`/`labelFontSize`/是否傳 `label`。`item.onTap != null` 的項目改用獨立的 sentinel `value`/`groupValue`（恆不相等）呼叫 `ReaderOptionTile`，`onSelected` 改綁 `item.onTap!`，不觸發外層 `onSelected`。
- `ReaderOptionTile` 需新增兩個可選建構參數 `iconSize`（預設 20，維持既有行為）、`labelFontSize`（預設 13，維持既有行為），供 `EBOptionChipGroup` 覆寫；不影響任何現有直接呼叫 `ReaderOptionTile` 的地方（目前所有呼叫點在本 Epic 完成後皆會改走 `EBOptionChipGroup`，但 `ReaderOptionTile` 本身的公開 API 向下相容）。

## 既有元件異動

### `ReaderSettingsSheet`

- 新增建構參數 `required bool isEinkMode`（呼叫端 `ReaderScreen` 傳入既有的 `widget.isEinkMode`，比照 `TtsPanel`／`ReaderChromeTopBar` 既有慣例）。
- 私有 `_buildSliderRow(...)` 依 `widget.isEinkMode` 分支：`false` 沿用現有 `Slider`＋±按鈕；`true` 改渲染 `EBStepper`。**此方法同時承載「文字」分頁 5 個數值列與「邊界」分頁 4 個邊界數值列**，兩個分頁的數值列會一併受這個分支影響，Issue 2 的測試範圍須涵蓋兩個分頁（見 `issues.md` 審查回應）。
  - **審查修正 M1（review-spec.md）**：`isEinkMode: true` 時，列頂端原本的 `Text(displayValue)` 需隱藏——`EBStepper` 本身中間已經顯示數值，兩者並存會同一數值重複出現兩次。頂端列 E-Ink 模式下只保留 Label 與覆寫徽章。
- **`_buildColumnModeRow()` 內獨立宣告的 `reader_settings_column_size_slider`**（審查修正 C3，review-spec.md：此控制項未經過 `_buildSliderRow`，Discovery／首版 spec 皆遺漏）：`isEinkMode: false` 維持現有 `Slider`（`min: 360.0, max: 1440.0`）；`isEinkMode: true` 改用 `EBStepper`（`keyPrefix: 'reader_settings_column_size'`，`min: 360.0, max: 1440.0, step: 60.0`，比照 prototype `elinkbook_theme_prototype.html:594-601` 的欄位大小步進間距），衍生出的 `reader_settings_column_size_decrement`/`_value`/`_increment` 三個 Key 取代原本單一的 `reader_settings_column_size_slider` Key（僅在 `isEinkMode: true` 分支下）。
- `_buildSliderRow` 的「已覆寫」狀態呈現，從目前的封鎖圖示（`Icons.block` reset 按鈕／灰色停用圖示）改為文字徽章：
  - 已覆寫：`Text('此書已覆寫')`（樣式比照 prototype 的 pill 徽章，用 `Container` + `BorderRadius.circular` 即可，不需要新元件）＋沿用現有 reset 按鈕（`icon: Icons.block`）讓使用者仍能一鍵恢復。
  - 未覆寫：`Text('使用全域預設')`，**外層 `Container`（或直接在 `Text` 上）必須維持掛載既有的 `Key('${keyPrefix}_unset_indicator')`**（審查修正 C2，review-spec.md：`reader_settings_sheet_test.dart` 有 6 處既有斷言直接依賴這個 Key 判斷「未覆寫／跟隨原樣式」，Key 語意不變，只是底下從 `Icon` 換成 `Text`，測試斷言方式不需要跟著改）。
  - `isOverridden == null`（不支援覆寫語意的欄位，如四邊邊界目前就是這種）維持原樣不顯示徽章。
- Tab 重新命名與內容搬移（**審查修正 C1，review-spec.md**：`app/test/screens/reader_settings_sheet_test.dart` 的 `switchToTab(tester, tabLabel)` helper〔L1560-1563〕是依 `find.widgetWithText(Tab, tabLabel)` 純文字比對切換分頁，全檔 43 處呼叫點使用舊分頁名稱——Tab 改名**必然**連動這些既有測試，不存在「Key 不變就能避免波及」這回事，原描述有誤，已訂正如下）：
  - `Tab` 文字：`文字內容`→`文字`、`邊界首尾`→`邊界`、`版面呈現`→`呈現`、`設定喜好`→`預設集`（`Key` 常數名稱不變，只改 `text:` 顯示字串）。
  - `_buildTextAlignRow()` 從 `_buildBoundaryTab()` 搬到 `_buildPresentationTab()`。
  - **配套測試維護（必要，非選項）**：`reader_settings_sheet_test.dart` 的 `switchToTab` helper 與全部 43 處呼叫點的分頁名稱字串，須同步改成新名稱；這是「文字定位邏輯不變、只是文字內容跟著新分頁名稱走」的維護性更新，不是回歸——已在 `issues.md` Issue 3 明訂為該 Issue 的必要範圍。
- 所有 `Wrap` 包 `ReaderOptionTile` 的單選群組（`_buildColumnModeRow`／`_buildTextAlignRow`／`_buildWritingModeOverrideRow`／`_buildPageTurnModeOverrideRow`／`_buildScreenOrientationOverrideRow`）改用 `EBOptionChipGroup`，每個選項補上 ≤2 字 `label`（見下方「選項標籤對照表」）。
- `_buildLayoutPresetSection()`／`_buildPresetSlot()` 新增「目前套用中」視覺標示：比對 `preset.prefs == _currentDraft`（已查證 `BookReaderPrefs` 現有 `operator ==`／`hashCode` 值相等實作，`book_reader_prefs.dart:222/257`，可直接比對，不需新增）。**審查修正 I3（review-spec.md）**：現有 `_buildPresetSlot()` 每一列非空預設集本來就有一顆 `icon: Icons.check` 的「套用到本書」`IconButton`（`reader_settings_sheet.dart:955-960`，`tooltip: '套用到本書'`）——若在文字旁再加一顆 `Icons.check` 會與這顆既有按鈕並存造成兩個打勾同時出現、語意混淆。改為：相等時**隱藏／替換掉「套用到本書」按鈕**，改成一個獨立的「已套用」指示器（`Key('reader_settings_preset_slot_${index}_active_indicator')`，內容可以是 `Icons.check` 圖示＋文字，例如「已套用」），「套用到其他書籍」與「刪除」兩顆按鈕維持顯示。整列底色改用 `colorScheme.inverseSurface`（E-Ink 模式為純黑），**且必須顯式將列內所有文字與圖示前景色統一設為 `colorScheme.onInverseSurface`**（E-Ink 模式為純白）——否則淺色主題下沿用預設暗色圖示，會在深色反白底上形成對比度不足。

### `PdfSettingsSheet`

- 新增建構參數 `required bool isEinkMode`。
- 私有 `_buildSliderRow(...)`（對比度/亮度/加粗強度）依 `isEinkMode` 分支，同 `ReaderSettingsSheet`（此檔案不引用 `EBStepper` 以外的東西，維持 epic-16 design.md 決策 #10「不與 `ReaderSettingsSheet` 共用私有邏輯」，只共用 `EBStepper`／`EBOptionChipGroup` 這兩個新的通用 widget）。
- 覆寫徽章**不適用**（`PdfSettingsSheet` 無全域/單書雙態語意欄位）。
- 所有 `Wrap` 包 `ReaderOptionTile` 的單選群組（Fit 模式／雙頁模式／頁面方向／換頁動畫／裁切模式）改用 `EBOptionChipGroup`。**裁切模式群組的「手動選區」項目**（`pdf_settings_crop_mode_manual`，`pdf_settings_sheet.dart:386-393`：點擊只呼叫 `widget.onRequestManualCrop()`，不改變 `_cropMode`、不觸發 `_notifyChanged()`，外觀恆為未選中）改用 §「新增元件」§2 定義的 `EBOptionChipItem.onTap` 承載（審查修正 I1，review-spec.md），不再需要獨立於群組之外的 `ReaderOptionTile<bool>` sentinel 寫法。
- Tab 名稱（顯示/濾鏡/裁切）與分頁內容維持不變。

### `FxlSettingsSheet`

- 新增建構參數 `required bool isEinkMode`（供未來一致性；FXL 目前無數值型 Slider，`isEinkMode` 暫不影響任何渲染分支，僅為呼叫端統一介面預留——若 Code Review 認為「目前用不到就不要加」，可在該 Issue 的 plan 階段移除本欄位，屆時同步更新本節）。
- 兩組 `Wrap` 包 `ReaderOptionTile`（雙頁模式／翻頁方向）改用 `EBOptionChipGroup`。
- 三顆 `SwitchListTile` 視覺風格調整（跟隨 `Theme.of(context)`，非新邏輯）。

### `ReaderScreen`

- 呼叫 `ReaderSettingsSheet`／`PdfSettingsSheet`／`FxlSettingsSheet` 的三處新增 `isEinkMode: widget.isEinkMode`。

## 選項標籤對照表（≤2 字中文標籤）

| 群組 | 選項 | 既有 tooltip | 新 label |
|---|---|---|---|
| 欄數 | auto/single/double | 自動／單欄／雙欄 | 自動／單欄／雙欄 |
| 文字對齊 | center/justify/start/end/left/right | 置中／左右對齊／起始邊對齊／結尾邊對齊／靠左／靠右 | 置中／齊行／起始／結尾／靠左／靠右 |
| 書寫方向覆寫 | null/vertical/horizontal | 採用書籍排版／強制直排／強制橫排 | 書籍／直排／橫排 |
| 翻頁模式覆寫 | null/paginated/scroll | 使用全域預設／點擊翻頁／滾動翻頁 | 全域／點擊／滾動 |
| 螢幕方向覆寫 | null/auto/lock0/lock90/lock180/lock270 | 使用全域預設／自動旋轉／鎖定0°／鎖定90°／鎖定180°／鎖定270° | 全域／自動／0°／90°／180°／270° |
| PDF Fit 模式 | pageFit/fitWidth/actualSize | Page-fit／Fit Width／真實比例 | 整頁／頁寬／原比 |
| PDF/FXL 雙頁模式 | auto/always/never | 自動／永遠雙頁／永遠單頁 | 自動／雙頁／單頁 |
| PDF/FXL 翻頁方向 | ltr/rtl | 左到右／右到左 | 左翻／右翻（審查修正 M2，review-spec.md：定案取代原「待 Issue 5 另議」） |
| PDF 換頁動畫 | slide/none | 滑動／無 | 滑動／無 |
| PDF 裁切模式 | none/autoDetect/manual | 不裁切／智慧自動／手動選區 | 不裁／智慧／手動 |

## 卡片邊框視覺規範（審查回應 I2，review-design.md）

「卡片邊框風格」（本 spec 多處提及）在一般主題與 E-Ink 模式下的具體 Token 取值：

- **一般主題（淺色/深色/羊皮紙）**：沿用既有 `ReaderOptionTile` 非選中態慣例——邊框色 `colorScheme.outline.withValues(alpha: 0.35)`、寬度 `1.0dp`、圓角 `BorderRadius.circular(8)`。
- **E-Ink 模式**：遵循 `DESIGN.md` §18.5「強制高對比線條」——純黑 `1.5dp` 邊框，不使用透明度混色。

## 審查回應（2026-09-08，`reviews/review-spec.md`）

- **C1（Tab 改名波及既有測試）**：已訂正「ReaderSettingsSheet」一節，移除「Key 不變即可避免波及既有測試」的錯誤前提，明確要求同步更新 `switchToTab` helper 與 43 處呼叫點；已同步反映於 `issues.md` Issue 3。
- **C2（覆寫徽章遺漏 `_unset_indicator` Key）**：已訂正，未覆寫文字徽章必須維持掛載 `Key('${keyPrefix}_unset_indicator')`。
- **C3（`reader_settings_column_size_slider` 遺漏）**：已訂正，納入 `_buildColumnModeRow()` 內獨立滑桿的 E-Ink 步進器規範。
- **I1（`EBOptionChipGroup` 缺乏動作項目支援）**：已在 `EBOptionChipItem` 新增 `onTap` 欄位，`PdfSettingsSheet` 的「手動選區」直接使用此欄位承載，取代原獨立 `ReaderOptionTile` sentinel 寫法。
- **I2（寬度公式與 `Wrap` 折行衝突）**：已訂正為依容器絕對寬度分級（`>=360`/`<=240`/`<200` 三段＋線性內插），不再除以 `items.length`。
- **I3（預設集打勾圖示衝突與反白對比度）**：已訂正，相等時隱藏／替換「套用到本書」按鈕為獨立「已套用」指示器，並要求列內文字/圖示前景色顯式套用 `onInverseSurface`。
- **M1（`EBStepper` 與頂列數值文字重複）**：已訂正，`isEinkMode: true` 時頂列隱藏 `Text(displayValue)`。
- **M2（PDF/FXL 翻頁方向標籤定案）**：已定案為「左翻」／「右翻」。
