# Epic 35 — 設計系統 Token 落地：工單清單 (Issues)

依 `spec.md`（Architecting 階段唯一事實來源，已經 `/superpowers:requesting-code-review` 審查修訂）拆解為 8 個細粒度垂直切片工單。每個工單都附有單元測試要求；跟 `spec.md` 對應段落的引用一律用 `spec.md §xxx` 標示，實作者動手前應先讀那一段的完整說明，這裡只列摘要與驗收標準。

**依賴順序：** Issue 1 → Issue 2 必須先完成、合併回主線，Issue 3～8 才能開始（三者皆依賴 `ElinkTokens` 類別存在、`resolveThemeData()` 已掛上 `extensions`）。Issue 3～8 彼此互相獨立，可平行進行。

**共同規則（每個工單皆適用，來自 `UI_DESIGN_RULES.md`）：** 動手改程式碼前，先在該工單的 `plans/plan-issue-<N>.md` 說明 (1) 改哪個 UI 元件 (2) 為什麼要改 (3) 哪些畫面依賴它 (4) 是否影響 business logic（不影響則明確寫「不影響」）。本 Epic 全程只碰 Theme／Design tokens／Library UI／Settings UI，不碰 OPDS／WebDAV／雲端來源實作／書籍儲存／閱讀進度持久化。

---

## Issue 1：`ElinkTokens` 類別本體＋`MaterialApp` 零時長主題轉場

**Status:** ready-for-agent

**依賴：** 無

**來源：** `spec.md` §「核心型別：ElinkTokens」、§「【審查新增】MaterialApp 零時長主題轉場」

**背景／目標：** 建立 `ElinkTokens extends ThemeExtension<ElinkTokens>`（`DESIGN.md` §1.2 骨架的正式定案版），並讓 `main.dart` 的 `MaterialApp` 明確設定 `themeAnimationDuration: Duration.zero`——這是後續所有 Issue 的地基，本身不涉及任何畫面顏色實際替換。

**Solution：**
- 新增 `ElinkTokens` 類別（欄位：`highlightYellow`／`highlightGreen`／`highlightBlue`／`underlineColor`／`progressTrack`／`coverPlaceholder`／`badgeScrim`／`ttsActiveHighlight`／`isEink`／`reducedMotion`／`discretePaging`），實作 `copyWith()`（逐欄位選填參數）與 `lerp()`（bool 欄位離散跳變、Color 欄位 `Color.lerp` 插值）。
- `main.dart` 的 `MaterialApp(...)` 加上 `themeAnimationDuration: Duration.zero`。
- 此工單**不**修改 `resolveThemeData()` 或任何 `_build*Theme()`——`ElinkTokens` 此時只是一個獨立存在、還沒被任何主題使用的類別，掛上 `ThemeData.extensions` 是 Issue 2 的範圍。

**單元測試要求：**
- `ElinkTokens.copyWith()`：逐欄位驗證只改指定欄位、其餘欄位維持原值。
- `ElinkTokens.lerp()`：三個 bool 欄位在 `t < 0.5` 與 `t >= 0.5` 兩種情況下正確離散跳變；Color 欄位確認有走 `Color.lerp`（不是直接回傳其中一邊）。
- widget test 確認 `MaterialApp` 的 `themeAnimationDuration` 為 `Duration.zero`。

**驗收標準：** `ElinkTokens` 類別存在、可獨立編譯、單元測試全數通過；`MaterialApp` 零時長轉場設定到位；`flutter analyze` 乾淨；本工單不改變任何現有畫面的實際顯示顏色（`ElinkTokens` 尚未被 `resolveThemeData()` 使用）。

---

## Issue 2：四套 `ColorScheme` 對齊 `DESIGN.md` §1.1＋YAGNI 清理＋電子紙可辨識度補強（Switch）

**Status:** ready-for-agent

**依賴：** Issue 1（需要 `ElinkTokens` 類別已存在，才能掛進 `ThemeData.extensions`）

**來源：** `spec.md` §「resolveThemeData() 銜接方式」、§「四套 ColorScheme 對齊 DESIGN.md §1.1」、§「電子紙可辨識度補強機制」（Switch 部分）、§「移除項目」

**背景／目標：** 這是本 Epic 真正的核心工單——把 `_buildLightTheme()`／`_buildDarkTheme()`／`_buildSepiaTheme()`／`_buildEinkTheme()` 四個函式的 `ColorScheme` 逐角色對齊 `DESIGN.md` 色表，掛上對應的 `ElinkTokens`，並處理 Dark 主題色值衝突後的可辨識度補強。

**Solution：**
- 四個 `_build*Theme()` 的 `ColorScheme` 補齊 `primary`／`onPrimary`／`primaryContainer`／`onPrimaryContainer`／`surface`／`onSurface`／`onSurfaceVariant`／`outline`／`error` 全部角色＋各自的 `scaffoldBackgroundColor`，逐一對照 `DESIGN.md` §1.1 表格值（含 Dark 的 `outline #2c2c34`／`surfaceContainerHighest #19191d`，**採用 DESIGN.md 值，不維持現行實測值**）。
- 各函式回傳的 `ThemeData` 加上 `extensions: [ElinkTokens(...)]`，三個一般主題 `isEink: false`，`_buildEinkTheme()` `isEink: true`（其餘 bool 欄位同步）。
- 移除 `secondary`／`onSecondary`（`_buildEinkTheme()`）、移除四個函式的顯式 `cardColor`／`dividerColor` 設定。
- 新增 `SwitchThemeData`：`thumbColor`／`trackColor`／`trackOutlineColor` 三個插槽皆改參照 `colorScheme.onSurface`（依 OFF/ON 狀態調整透明度維持三者可區分，見 `spec.md` 該段落的具體理由）。
- `_buildEinkTheme()` 既有的 `splashFactory`／`hoverColor`／`highlightColor` 三行原樣保留。

**單元測試要求：**
- 移除既有 `outline`／`surfaceContainerHighest` 感知亮度差門檻斷言（`app_theme_data_test.dart`），新增斷言驗證四套 `ColorScheme` 各角色數值皆與 `DESIGN.md` 表格一致（逐角色逐主題）。
- 新增斷言：`ThemeData.switchTheme` 的 `thumbColor`／`trackColor`／`trackOutlineColor` 在 OFF 狀態下皆解析自 `colorScheme.onSurface`（斷言來源角色，不硬編 hex 值）。
- 新增 widget test 確認移除 `cardColor`／`dividerColor` 後，`Card`／`Divider` 在 M3 預設下解析出的顏色符合預期。
- 既有「`dividerColor` 與 `outline` 同值」測試（原第 81-86 行附近）**維持不動**，M3 預設下依然成立，不需要跟著改動。
- 四種 `theme × isEinkMode` 組合透過 `resolveThemeData()` 拿到的 `ElinkTokens` 值正確（對應 Issue 1 已建好的類別，此處驗證組裝正確）。

**驗收標準：** 四套 `ColorScheme` 逐角色與 `DESIGN.md` §1.1 一致（Dark `outline`／`surfaceContainerHighest` 除外——那兩個本來就是刻意採用 DESIGN.md 值，不是「例外」而是「已對齊」，這裡指的是不再維持舊實測值）；`ElinkTokens` 已掛上 `resolveThemeData()` 輸出；`SwitchThemeData` 補強到位；`flutter analyze` 乾淨、`flutter test` 全數通過（含更新後的斷言）。**已知殘留風險（非本工單驗收範圍，記錄供後續追蹤）：** `SwitchThemeData` 補強手法尚未真機驗證，需要下一輪真機驗證確認在電子紙上確實可辨識（比照 `epic-18`／`epic-25` 慣例）。

---

## Issue 3：`settings_screen.dart` 全面遷移

**Status:** ready-for-agent

**依賴：** Issue 2

**來源：** `spec.md` §「settings_screen.dart E-Ink 鎖定視覺與主題預覽色」，及「寫死顏色遷移」清單中 `settings_screen.dart` 部分

**背景／目標：** 這個檔案同時牽涉三件事，因為都在同一個檔案，合併成一個工單：E-Ink 鎖定視覺手法訂正、主題預覽色改讀真值、其餘零散寫死顏色遷移。

**Solution：**
- `_buildThemeDot()` 的 `Opacity(0.4)` 鎖定視覺改為 `DESIGN.md` §17.2 指定的邊框加粗虛線手法（`3dp` 虛線邊框，比照 §7.2 E-Ink 按壓反饋語彙），`onTap: null` 鎖住邏輯不變。
- 三顆主題預覽圓點改為直接讀取 `resolveThemeData()` 各主題回傳的實際 `scaffoldBackgroundColor`／`primary`，不再維持自己一份獨立寫死近似值。
- 檔案內其餘 `Colors.grey`／`black45`／`white70` 家族依用途對應到 `ColorScheme`／`ElinkTokens` 角色。

**單元測試要求：**
- widget test 驗證 E-Ink 開啟時主題選擇器呈現虛線加粗邊框（不是降低透明度）且不可點擊。
- widget test 驗證主題預覽圓點顏色與 `resolveThemeData()` 對應主題的 `scaffoldBackgroundColor`／`primary` 一致。
- 既有 `settings_screen_test.dart`（若存在）全數通過，無回歸。

**驗收標準：** `settings_screen.dart` 內無任何寫死顏色字面值；E-Ink 鎖定視覺符合 `DESIGN.md` §17.2；`flutter analyze` 乾淨、`flutter test` 全數通過。

---

## Issue 4：`highlight_style.dart` 遷移＋呼叫端更新（`reader_screen.dart`／`notes_bottom_sheet.dart`）

**Status:** ready-for-agent

**依賴：** Issue 1（需要 `ElinkTokens` 類別存在）、Issue 2（需要 `resolveThemeData()` 已能透過 `Theme.of(context).extension<ElinkTokens>()` 取值）

**來源：** `spec.md` §「既有語意色遷移到 ElinkTokens」

**背景／目標：** `HighlightStyle` 列舉目前用編譯期常數色票，跟 `ElinkTokens` 的執行期取值架構衝突，需要重構函式簽章而非單純換色值；順便處理同一檔案群組裡另外兩個獨立的小修正（`notes_bottom_sheet.dart` 的 `Colors.red`、`reader_screen.dart` 自己其餘的寫死顏色）。

**Solution：**
- `HighlightStyle` 列舉拿掉 `fixedTint` 欄位；`highlighterYellowTint`／`highlighterPinkTint`／`highlighterBlueTint` 三個頂層常數移除。**列舉成員名稱維持 `highlighterPink` 不改名**（避免破壞 `Enum.values.byName()` 持久化的既有使用者資料）。
- `highlightStyleTint()` 改名為 `highlightStyleColor()`，簽章改為 `Color highlightStyleColor(HighlightStyle style, {required ElinkTokens tokens})`，拿掉 `primaryColor` 參數。函式內容：`highlighterYellow`→`tokens.highlightYellow`、`highlighterPink`→`tokens.highlightGreen`（語意變更，`DESIGN.md` 既有決策）、`highlighterBlue`→`tokens.highlightBlue`、`underline`→`tokens.underlineColor`。
- 呼叫端 `reader_screen.dart:1733,1826`、`notes_bottom_sheet.dart:441` 改為傳入 `tokens`（從 `Theme.of(context).extension<ElinkTokens>()!` 取得），不再傳 `primaryColor`。
- `notes_bottom_sheet.dart` 的 `Colors.red`（L349／L531，刪除按鈕前景色）→ `colorScheme.error`。
- `reader_screen.dart` 檔案內其餘寫死顏色（原 8 檔清單項目）依用途遷移到對應角色。

**單元測試要求：**
- `highlightStyleColor()` 單元測試：四個 `HighlightStyle` 各自對應正確的 `ElinkTokens` 欄位值（`highlighterPink` → `tokens.highlightGreen`）。
- 既有依賴舊 `highlightStyleTint()`／`primaryColor` 參數的測試同步更新為新簽章。
- `notes_bottom_sheet_test.dart`（若存在）驗證刪除按鈕前景色為 `colorScheme.error`。
- 既有 `reader_screen_test.dart` 全數通過，無回歸。

**驗收標準：** `highlight_style.dart` 不再有任何編譯期色票常數；三處呼叫端皆已更新為新簽章；`notes_bottom_sheet.dart`／`reader_screen.dart` 內無寫死顏色殘留；`flutter analyze` 乾淨、`flutter test` 全數通過。

---

## Issue 5：`nav_zone_settings_screen.dart`（電子紙可辨識度補強第二處＋其餘遷移）

**Status:** ready-for-agent

**依賴：** Issue 2

**來源：** `spec.md` §「電子紙可辨識度補強機制」（`nav_zone_settings_screen.dart` 部分）、「寫死顏色遷移」清單

**背景／目標：** 這個檔案有 3 處直接讀取 `Theme.of(context).dividerColor` 畫九宮格熱區格線／範本卡片邊框，Issue 2 移除顯式 `dividerColor` 覆寫後會退回跟 Dark 衝突色值同一個角色（`outline`），需要獨立處理；順便清掉檔案內其餘寫死顏色。

**Solution：**
- 3 處 `Theme.of(context).dividerColor`（原 L232／L318／L349）直接改讀 `Theme.of(context).colorScheme.onSurface`，不透過 `dividerColor` 這個間接屬性。
- 檔案內其餘 `Colors.grey`／`black45`／`white70` 家族依用途遷移。

**單元測試要求：**
- widget test 驗證 3 處熱區／範本卡片邊框顏色確實讀取 `colorScheme.onSurface`（斷言來源角色，不硬編 hex 值）。
- 既有 `nav_zone_settings_screen_test.dart`（若存在）全數通過，無回歸。

**驗收標準：** 檔案內無 `dividerColor` 引用、無寫死顏色殘留；`flutter analyze` 乾淨、`flutter test` 全數通過。**已知殘留風險（非本工單驗收範圍）：** 比照 Issue 2，`onSurface` 補強手法尚未真機驗證。

---

## Issue 6：書架相關寫死顏色遷移（`book_cover.dart`／`layout_preset_book_picker_screen.dart`／`library_screen.dart`／`library_group_management_dialog.dart`）

**Status:** ready-for-agent

**依賴：** Issue 2

**來源：** `spec.md` §「寫死顏色遷移」

**背景／目標：** 書架功能相關的四個檔案，功能區塊相近，合併一個工單一次處理。

**Solution：**
- `book_cover.dart`／`layout_preset_book_picker_screen.dart`／`library_screen.dart`：`Colors.grey`／`black45`／`white70` 家族依用途對應 `onSurfaceVariant`／`outline`／`badgeScrim`／`coverPlaceholder`／`progressTrack` 等角色。
- `library_group_management_dialog.dart`：`Colors.red`（L174，刪除文字色）→ `colorScheme.error`。

**單元測試要求：**
- 既有相關測試（`library_screen_test.dart`、`book_cover_test.dart` 等，若存在）全數通過，無回歸。
- `library_group_management_dialog.dart` 若有既有測試，驗證刪除文字色為 `colorScheme.error`。

**驗收標準：** 四個檔案內無寫死顏色殘留；`flutter analyze` 乾淨、`flutter test` 全數通過。

---

## Issue 7：閱讀器相關寫死顏色遷移（`foliate_reader_view.dart`／`pdf_reader_view.dart`／`pdf_crop_frame_overlay.dart`）

**Status:** ready-for-agent

**依賴：** Issue 2

**來源：** `spec.md` §「寫死顏色遷移」

**背景／目標：** 閱讀器渲染相關的三個檔案，合併一個工單一次處理。

**Solution：**
- `foliate_reader_view.dart`／`pdf_reader_view.dart`：`Colors.grey`／`black45`／`white70` 家族依用途對應角色。
- `pdf_crop_frame_overlay.dart`：`Colors.black`／`Colors.white`／自訂綠色等，依實際用途對應 `ColorScheme`／`ElinkTokens` 角色（例如裁切框邊界對應 `outline`，指示色對應語意色，實作時依畫面實際呈現逐一確認，不得直接臆測）。

**單元測試要求：**
- 既有相關測試（若存在）全數通過，無回歸。
- 若 `pdf_crop_frame_overlay.dart` 目前完全沒有色彩相關測試覆蓋，不強制新增，維持現有測試密度水準即可。

**驗收標準：** 三個檔案內無寫死顏色殘留；`flutter analyze` 乾淨、`flutter test` 全數通過。

---

## Issue 8：`txt_cover_generator.dart`（E-Ink 分支：白底黑框黑字）

**Status:** ready-for-agent

**依賴：** Issue 2

**來源：** `spec.md` §「寫死顏色遷移」（`txt_cover_generator.dart` 部分）

**背景／目標：** 這個函式在匯入當下產生一次 PNG 並存成本機檔案（不是即時渲染），本 Epic 不改變這個既有架構，只讓 E-Ink 模式下產生的封面樣式跟隨規範。

**Solution：**
- `generateTxtCover()` 簽章加 `isEinkMode`（或直接傳入 `ElinkTokens`）參數。
- `isEinkMode == true`：不使用 6 色色盤，背景改白底（`ElinkTokens.coverPlaceholder`）＋黑色邊框（`outline`）＋書名首字文字色改黑（現行寫死白色 `0xFFFFFFFF` 需一併修正，否則白底白字看不見）。
- `isEinkMode == false`：維持既有 6 色依書名雜湊輪替＋白字行為完全不變。
- 呼叫端（書籍匯入流程）傳入當下的 `isEinkMode` 狀態。

**單元測試要求：**
- 新增單元測試驗證 `isEinkMode: true` 時輸出 PNG 背景為白、有黑框、書名首字文字色為黑（像素採樣斷言四角/邊緣/文字區域顏色）。
- 新增回歸測試驗證 `isEinkMode: false` 時既有 6 色輪替＋白字行為未受影響。

**驗收標準：** E-Ink 模式下新匯入 TXT 書封面為白底黑框黑字，可辨識；非 E-Ink 模式行為完全不變；`flutter analyze` 乾淨、`flutter test` 全數通過。**明確排除：** 已產生的舊封面 PNG 不會回頭重新產生，此為既有架構限制，不在本工單修復範圍。
