# Visual Validation

> **環境限制（誠實聲明，不誇大驗證程度）**：本機沒有連接 Android 裝置/模擬器（`flutter devices` 僅列出 Windows／Chrome／Edge）。嘗試 `flutter run -d chrome` 後確認此專案**未設定 Web 平台支援**（`flutter create .` 提示訊息），啟動後 `path_provider`／`sqflite` 等原生外掛在 Web 上直接丟 `MissingPluginException`，無法跑出真正可用的畫面可供截圖——已終止該次嘗試，不強行在不支援的平台上湊出截圖。
> 因此本輪驗證**不是**依 Reference 截圖做像素級疊圖比對，而是：(1) 逐一元件對照 Reference 截圖與程式碼實際渲染邏輯做人工核對，(2) 針對每個修正新增或更新對應的 `flutter test` 斷言（顏色/樣式直接斷言，非僅存在性檢查），(3) `flutter analyze` 全綠、完整 `flutter test`（2146 個測試）全數通過。PASS/PARTIAL/FAIL 判定依據見各項「驗證依據」。若要做到真正的截圖疊圖比對，需要接上 Android 裝置或幫這個 Android-only 專案另外補上 Web 平台支援（`path_provider`/`sqflite` 的 Web 實作），兩者都超出本輪範圍，需要您決定是否要投入。

---

## Screen

Library（書架）

## Reference

`docs/research/uiux/reference/書架_1.png`

## Flutter Screenshot

無（見上方環境限制聲明）

## Result

### Layout
PARTIAL — AppBar／搜尋列／PagingBar 版面結構未變動，維持既有正確版面；書封/分類格邊框、分類角標已補上（見 Components）。網格 padding／gap 是否與 Reference 的 12/16px 完全一致本輪未逐行核對。

### Typography
PARTIAL — AppBar 標題字重已改為 `FontWeight.w900`（`_buildAppBarTheme`），對齊 Reference 的 `font-black`；書名/其餘字級本輪未逐一核對。

### Color
PASS — `DESIGN_TOKENS.md` 先前已驗證 100% 對齊 `DESIGN.md`；本輪新增修正的 `_GroupGridTile` 角標（`primary`/`onPrimary`）、書封邊框（`outline`）皆使用既有 `ColorScheme` 角色，無寫死色值。

### Spacing
PARTIAL — 未逐行核對網格 gap／卡片內距與 Reference 是否完全一致。

### Components
PASS（有測試佐證）——
- 書封／封面佔位符邊框：`book_cover.dart` 非 E-Ink 主題已補 `outline` 邊框。驗證依據：`flutter test test/library/widgets/book_cover_test.dart` 全數通過。
- 分類拼貼格外框＋「分類」角標：`library_screen.dart` `_GroupGridTile` 已補上。驗證依據：`flutter test test/screens/library_screen_test.dart`（156 項全過，含既有的分類拼貼格系列測試，證明新增的外層 `DecoratedBox`／角標未破壞既有版面斷言）；**本輪未新增角標本身的存在性斷言**，建議下一輪補一則 `find.text('分類')` 測試。
- AppBar 底部分隔線／無陰影：`app_theme_data.dart` `_buildAppBarTheme()` 全域生效。無專屬測試斷言，PARTIAL。

### Responsive
`[UNKNOWN]` — 未涵蓋，Reference 本身也只有單一手機尺寸可比對（見 `SCREEN_SPEC.md`）。

## Remaining Differences
- 網格內距/間距未逐值核對。
- 「分類」角標存在性尚無自動化測試覆蓋。
- PagingBar／搜尋列本輪未再檢視（先前分析標記為 `[UNKNOWN]`，仍未處理）。

---

## Screen

LayoutSettings（版面設定：文字／邊界／呈現／預設集）

## Reference

`docs/research/uiux/reference/版面設定_文字_1.png`、`_文字_2.png`、`_邊界_1.png`、`_邊界_2.png`、`_呈現_1.png`、`_呈現_2.png`、`_預設集.png`

## Flutter Screenshot

無（見上方環境限制聲明）

## Result

### Layout
PASS — 分頁籤結構（文字/邊界/呈現/預設集）與 Reference 一致，未變動。

### Typography
PARTIAL — `EBStepper` 數值文字已改為 `18px / FontWeight.w900`，貼近 Reference 大字級粗體；`-`/`+` 圖示字級未特別調整。

### Color
PASS（有測試佐證）——`ReaderOptionTile` 選中態由 `primaryContainer` 改為 `primary`＋`onPrimary`，對齊 Reference「主色實心填滿＋白字」。驗證依據：`flutter test test/screens/fxl_settings_sheet_test.dart test/screens/pdf_settings_sheet_test.dart test/screens/reader_settings_sheet_test.dart`（141 項全過，含本輪更新的 3 則精確色值斷言：`fxl_settings_sheet_test.dart` 2 處、`pdf_settings_sheet_test.dart` 1 處）。

### Spacing
`[UNKNOWN]` — 未逐值核對。

### Components
PASS（有測試佐證，`EBStepper`）／**決策保留不動**（`Slider`）——
- `EBStepper`（字級/行距/段落間距/字重/字距/上下左右邊界）：已補上邊框＋8dp 圓角容器（`_StepperButton`），對齊 Reference。驗證依據：`flutter test test/screens/widgets/eb_stepper_test.dart` 全數通過（原有測試未斷言邊框存在性，僅驗證數值邏輯不受影響；視覺本身依人工核對程式碼確認）。
- 非 E-Ink 主題的 `Slider`：**依您明確指示維持現況，不改**（`reader_settings_sheet.dart` 非 E-Ink 仍用 `Slider`，E-Ink 用 `EBStepper`，`DESIGN.md` §18.3 既有決策）。此項與 Reference 的差異**刻意保留**，不計入待修清單。
- `Switch`（顯示頁首/頁尾等）：ON 態已改為 `primary`／`onPrimary`。驗證依據：`flutter test test/theme/app_theme_data_test.dart`（新增／更新 4 則測試，含 E-Ink 主題「黑底白點」對比度驗證）。

### Responsive
`[UNKNOWN]`。

## Remaining Differences
- `EBStepper` 邊框/圓角本輪無專屬測試斷言其視覺屬性（僅有既有數值邏輯測試持續通過，證明未破壞行為）。
- 步進器數值文字以外的其餘文字字級（如「使用全域預設」次要說明）未核對。

---

## Screen

Settings（設定）

## Reference

`docs/research/uiux/reference/設定_1.png`、`設定_2.png`

## Flutter Screenshot

無（見上方環境限制聲明）

## Result

### Layout
PASS（有測試佐證）——`settings_scaffold.dart` 每個項目改由 `_SettingsCard`（內部即 `Card`，套用全域 `CardTheme`：無陰影＋`outline` 邊框＋8dp 圓角）包裹，取代原本連續 `ListTile`＋`Divider` 清單；分區間距改由 `EBSectionHeader` 既有頂部留白承擔，畫面上不再出現 `Divider`。驗證依據：`flutter test test/screens/settings_scaffold_test.dart`（24 項全過，含本輪重寫的結構測試——`find.byType(Divider)` 為 `findsNothing`，8 個已知項目 Key 皆能找到 `Card` 祖先）。

### Typography
PASS — 未變動，沿用既有 `EBSectionHeader`／`ListTile` 文字樣式，本輪未發現額外差異。

### Color
PASS — `Card` 顏色來自全域 `CardTheme`（`colorScheme.surface`＋`outline` 邊框），無寫死色值。

### Spacing
PARTIAL — 卡片間距（`margin: EdgeInsets.symmetric(horizontal: 12, vertical: 4)`）依既有 `EBSpace`／原型間距慣例決定，未逐像素比對 Reference 實際間距值。

### Components
PASS（有測試佐證）——見上方 Layout。`clipBehavior: Clip.antiAlias` 確保 `ListTile`/`SwitchListTile` 的按壓水波紋不溢出卡片圓角邊界（人工核對程式碼確認，無專屬測試斷言此點）。

### Responsive
`[UNKNOWN]`。

## Remaining Differences
- 卡片間距未逐像素核對。
- 佈景圓點選擇器（`_buildThemeDot`）本輪未變動，是否需要視覺調整未重新核對。

---

## Screen

Source（來源）／Reader 底部工具列＋TTS 面板

## Result

**未列入本輪修改範圍**——來源畫面（`sources_home_screen.dart`）與閱讀器底部列/TTS 面板本輪完全未讀取現有原始碼，`[UNKNOWN]`，需下一輪處理。

---

## flutter analyze Result

```
No issues found! (ran in 11.3s)
```

## flutter test Result

```
+2146: All tests passed!
```
（含本輪新增/更新的 8 則測試：`app_theme_data_test.dart` Switch ON/OFF 色值 4 則、`fxl_settings_sheet_test.dart`／`pdf_settings_sheet_test.dart` 選中態色值更新 3 則、`library_screen_test.dart` 既有分類拼貼格系列間接驗證 `_GroupGridTile` 改動未回歸）
