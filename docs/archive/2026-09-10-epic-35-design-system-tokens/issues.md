# Epic 35 — 設計系統 Token 落地：工單清單 (Issues)

依 `spec.md`（Architecting 階段唯一事實來源，已經 `/superpowers:requesting-code-review` 審查修訂）拆解為 8 個細粒度垂直切片工單。每個工單都附有單元測試要求；跟 `spec.md` 對應段落的引用一律用 `spec.md §xxx` 標示，實作者動手前應先讀那一段的完整說明，這裡只列摘要與驗收標準。

**依賴順序：** Issue 1 → Issue 2 必須先完成、合併回主線，Issue 3～8 才能開始（三者皆依賴 `ElinkTokens` 類別存在、`resolveThemeData()` 已掛上 `extensions`）。Issue 3～8 彼此互相獨立，可平行進行。

**共同規則（每個工單皆適用，來自 `UI_DESIGN_RULES.md`）：** 動手改程式碼前，先在該工單的 `plans/plan-issue-<N>.md` 說明 (1) 改哪個 UI 元件 (2) 為什麼要改 (3) 哪些畫面依賴它 (4) 是否影響 business logic（不影響則明確寫「不影響」）。本 Epic 全程只碰 Theme／Design tokens／Library UI／Settings UI，不碰 OPDS／WebDAV／雲端來源實作／書籍儲存／閱讀進度持久化。

---

## Issue 1：`ElinkTokens` 類別本體＋`MaterialApp` 零時長主題轉場

**Status:** ✅ 已完成。`ElinkTokens extends ThemeExtension<ElinkTokens>`（11 個欄位、`const` 建構子、`copyWith()`、`lerp()`）與 `main.dart` 的 `MaterialApp themeAnimationDuration: Duration.zero` 皆已實作，透過 `docs/epics/epic-35-design-system-tokens/plans/plan-issue-1.md` 3 個 Task 以 subagent-driven TDD 完成（9 個新測試，`flutter test` 全數通過共 1883 個，`flutter analyze` 乾淨），逐 Task 審查與最終整分支審查（`opus`／`sonnet`）皆核准合併，無 Critical／Important 未決問題。`ElinkTokens` 尚未掛進 `resolveThemeData()`，屬 Issue 2 範圍。

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

**Status:** ✅ 已完成。四套 `ColorScheme`（Light／Dark／Sepia／E-Ink）逐角色對齊 `DESIGN.md` §1.1、`ElinkTokens` 已掛上 `resolveThemeData()`、`secondary`／`onSecondary`／`cardColor`／`dividerColor` 已清除、`SwitchThemeData` 電子紙可辨識度補強已到位，透過 `docs/epics/epic-35-design-system-tokens/plans/plan-issue-2.md` 5 個 Task 以 subagent-driven TDD 完成（新增 20 個測試，最終 `flutter test` 1893/1893 全過、`flutter analyze` 乾淨）。逐 Task 審查（5 次）與最終整分支審查（opus）皆核准，最終審查抓到 1 項必修（`app_theme_data.dart` 檔頭註解仍指向已淘汰的 `prototype/index.html`，已改指向 `DESIGN.md`）與 1 項強烈建議修（`SwitchThemeData` 測試補齊 ON 狀態覆蓋，`spec.md`「Testing Decisions」原文要求「各狀態下」皆需驗證），皆已修正並通過複審。commit 範圍 `56641862..315b6477`（worktree `worktree-epic-35-issue-2`）。

**已知殘留、非本 Issue 阻斷項（最終審查發現，記錄供後續追蹤）：**
- `app/lib/screens/widgets/reader_option_tile.dart:51` 的 `theme.colorScheme.outline.withValues(alpha: 0.35)`（非 E-Ink 分支的選項邊框），Dark 主題 `outline` 改採 `DESIGN.md` 新值（`#2c2c34`，比原真機實測值 `#86868F` 暗很多）後，這條邊框跟背景的對比會大幅降低、電子紙上可能難以辨識。這個檔案不在 `spec.md` 盤點的 13 個寫死顏色遷移清單、也不在任何已排 Issue 的明確範圍內（跟 Issue 7 已排定要目視確認的同名用法是不同一件事——Issue 7 涵蓋的是同一檔案不同分支）。**建議 Issue 7 實作時一併目視確認 Dark 主題下這條外框是否仍可辨識**，若真機驗證證實不可辨識，改參照 `colorScheme.onSurface`（比照 Issue 2 `SwitchThemeData` 與 Issue 5 的同一手法）。
- `SwitchThemeData` 補強無條件套用到全部四套主題（含 Light／Sepia 這兩個 `outline` 本來就對比夠、不需要補強的主題），代價是這兩個主題下 Switch 的 ON 狀態失去 M3 預設的品牌主色語彙，改成純灰階深淺區分。這是忠實反映 `spec.md` 第 88 行「三個插槽全部改參照 `colorScheme.onSurface`」明文決議的結果，不是實作偏離；下一輪真機驗證（比照 `epic-18`／`epic-25` 慣例）確認可辨識度後，若需要找回 ON 狀態品牌色語彙，需回頭跟 `spec.md` 討論（例如 ON 狀態 thumb 改用 `surface` 反轉），不在本 Issue 自行調整範圍內。

**依賴：** Issue 1（需要 `ElinkTokens` 類別已存在，才能掛進 `ThemeData.extensions`）

**來源：** `spec.md` §「resolveThemeData() 銜接方式」、§「四套 ColorScheme 對齊 DESIGN.md §1.1」、§「電子紙可辨識度補強機制」（Switch 部分）、§「移除項目」

**背景／目標：** 這是本 Epic 真正的核心工單——把 `_buildLightTheme()`／`_buildDarkTheme()`／`_buildSepiaTheme()`／`_buildEinkTheme()` 四個函式的 `ColorScheme` 逐角色對齊 `DESIGN.md` 色表，掛上對應的 `ElinkTokens`，並處理 Dark 主題色值衝突後的可辨識度補強。

**Solution：**
- 四個 `_build*Theme()` 的 `ColorScheme` 補齊 `primary`／`onPrimary`／`primaryContainer`／`onPrimaryContainer`／`surface`／`onSurface`／`onSurfaceVariant`／`outline`／`surfaceContainerHighest`／`error` 全部角色＋各自的 `scaffoldBackgroundColor`，逐一對照 `DESIGN.md` §1.1 表格值。**（審查補強）`surfaceContainerHighest` 四個主題皆須明確設定**——現行 Light／Sepia／E-Ink 三個函式完全沒設定這個角色，隱性等於 M3 baseline，正是本 Epic 要修的「淡紫外洩」同一種 bug；Dark 主題的 `outline`（`#2c2c34`）與 `surfaceContainerHighest`（`#19191d`）**改採 DESIGN.md 值，不維持現行真機實測值（`#86868F`／`#3C3C44`）**，其餘三主題對照 `DESIGN.md` §1.1 表格填入對應值。
- 各函式回傳的 `ThemeData` 加上 `extensions: [ElinkTokens(...)]`，三個一般主題 `isEink: false`，`_buildEinkTheme()` `isEink: true`（其餘 bool 欄位同步）。
- 移除 `secondary`／`onSecondary`（`_buildEinkTheme()`）、移除四個函式的顯式 `cardColor`／`dividerColor` 設定。
- 新增 `SwitchThemeData`：`thumbColor`／`trackColor`／`trackOutlineColor` 三個插槽皆改參照 `colorScheme.onSurface`（依 OFF/ON 狀態調整透明度維持三者可區分，見 `spec.md` 該段落的具體理由）。
- `_buildEinkTheme()` 既有的 `splashFactory`／`hoverColor`／`highlightColor` 三行原樣保留。
- **已知連帶影響（非本工單改動範圍，供 Issue 6／7 實作時參照）：** `library_screen.dart`（E-Ink 切換鈕外框，Issue 6 範圍）與 `reader_option_tile.dart`（非 E-Ink 分支的選項邊框，Issue 7 範圍）皆直接引用 `colorScheme.outline`，Dark 主題色值改變後這兩處視覺對比會連帶受影響；用法本身正確（引用角色而非寫死色），Issue 6／7 實作時目視確認 Dark 主題下仍可辨識即可，不需要在本工單處理。

**單元測試要求：**
- 移除既有 `outline`／`surfaceContainerHighest` 感知亮度差門檻斷言（`app_theme_data_test.dart`），新增斷言驗證四套 `ColorScheme` 各角色數值皆與 `DESIGN.md` 表格一致（逐角色逐主題）。
- 新增斷言：`ThemeData.switchTheme` 的 `thumbColor`／`trackColor`／`trackOutlineColor` 在 OFF 狀態下皆解析自 `colorScheme.onSurface`（斷言來源角色，不硬編 hex 值）。
- 新增 widget test 確認移除 `cardColor`／`dividerColor` 後，`Card`／`Divider` 在 M3 預設下解析出的顏色符合預期。
- 既有「`dividerColor` 與 `outline` 同值」測試（原第 81-86 行附近）**維持不動**，M3 預設下依然成立，不需要跟著改動。
- 四種 `theme × isEinkMode` 組合透過 `resolveThemeData()` 拿到的 `ElinkTokens` 值正確（對應 Issue 1 已建好的類別，此處驗證組裝正確）。

**驗收標準：** 四套 `ColorScheme` 逐角色與 `DESIGN.md` §1.1 一致（Dark `outline`／`surfaceContainerHighest` 除外——那兩個本來就是刻意採用 DESIGN.md 值，不是「例外」而是「已對齊」，這裡指的是不再維持舊實測值）；`ElinkTokens` 已掛上 `resolveThemeData()` 輸出；`SwitchThemeData` 補強到位；`flutter analyze` 乾淨、`flutter test` 全數通過（含更新後的斷言）。**已知殘留風險（非本工單驗收範圍，記錄供後續追蹤）：** `SwitchThemeData` 補強手法尚未真機驗證，需要下一輪真機驗證確認在電子紙上確實可辨識（比照 `epic-18`／`epic-25` 慣例）。

---

## Issue 3：`settings_screen.dart` 全面遷移

**Status:** ✅ 已完成。`SettingsScreen` 的「佈景」主題預覽圓點已改讀 `resolveThemeData()` 的實際色值（`scaffoldBackgroundColor` 與 `colorScheme.primary`／`outline`），移除 `Colors.grey` 殘留；E-Ink 鎖定視覺改為 `DESIGN.md` §17.2 指定的虛線邊框（`_LockedDotBorderPainter`，選取 3dp／未選取 1.5dp）＋鎖定提示文字＋`Semantics` 標籤（未鎖定狀態保留 tap 動作）。透過 `docs/epics/epic-35-design-system-tokens/plans/plan-issue-3.md` 2 個 Task 以 subagent-driven TDD 完成（新增 5 個測試，全專案 `flutter test` 1898/1898 全過、`flutter analyze` 乾淨）。逐 Task 審查與最終整分支審查皆核准通過（`reviews/review-issue-3.md`），無 Critical／Important 問題。commit 範圍 `d774b93..6d4c577f`。

**已知殘留風險（非本工單驗收範圍）：** 鎖定狀態下圓點虛線 dash／gap 長度（3dp／3dp）為具體詮釋，需要下一輪真機驗證確認在電子紙螢幕上的可辨識度。

**依賴：** Issue 2

**來源：** `spec.md` §「settings_screen.dart E-Ink 鎖定視覺與主題預覽色」，及「寫死顏色遷移」清單中 `settings_screen.dart` 部分

**背景／目標：** 這個檔案同時牽涉三件事，因為都在同一個檔案，合併成一個工單：E-Ink 鎖定視覺手法訂正、主題預覽色改讀真值、其餘零散寫死顏色遷移。

**Solution：**
- `_buildThemeDot()` 的 `Opacity(0.4)` 鎖定視覺改為 `DESIGN.md` §17.2 指定的邊框加粗虛線手法（`3dp` 虛線邊框，比照 §7.2 E-Ink 按壓反饋語彙），`onTap: null` 鎖住邏輯不變。
- 三顆主題預覽圓點改為直接讀取 `resolveThemeData()` 各主題回傳的實際 `scaffoldBackgroundColor`／`primary`，不再維持自己一份獨立寫死近似值。
- 檔案內其餘寫死顏色殘留（實測僅剩 1 處，`Colors.grey` 家族）依用途對應到 `ColorScheme`／`ElinkTokens` 角色。

**單元測試要求：**
- widget test 驗證 E-Ink 開啟時主題選擇器呈現虛線加粗邊框（不是降低透明度）且不可點擊。
- widget test 驗證主題預覽圓點顏色與 `resolveThemeData()` 對應主題的 `scaffoldBackgroundColor`／`primary` 一致。
- 既有 `settings_screen_test.dart` 全數通過，無回歸。

**驗收標準：** `settings_screen.dart` 內無任何寫死顏色字面值；E-Ink 鎖定視覺符合 `DESIGN.md` §17.2；`flutter analyze` 乾淨、`flutter test` 全數通過。

---

## Issue 4：`highlight_style.dart` 遷移＋呼叫端更新（`reader_screen.dart`／`notes_bottom_sheet.dart`）

**Status:** ✅ 已完成。`HighlightStyle` 列舉移除 `fixedTint` 與三個頂層色票常數（保留 `noteOnlyTint` 不動），移除 `highlightStyleTint()`，改為純函式 `Color highlightStyleColor(HighlightStyle style, {required ElinkTokens tokens})`（`highlighterPink` 語意對應 `tokens.highlightGreen`，成員名稱維持不變以確保持久化反序列化相容性）。四處呼叫端（`reader_screen.dart` 2 處、`notes_bottom_sheet.dart` 1 處、`annotation_toolbar.dart` 1 處）同步遷移改讀 `Theme.of(context).extension<ElinkTokens>()!`；`notes_bottom_sheet.dart` 兩處批次刪除確認對話框前景色遷移至 `Theme.of(context).colorScheme.error`。測試環境補齊 `reader_screen_test.dart`（168 處）、`annotation_toolbar_test.dart`（12 處）、`notes_bottom_sheet_test.dart`（2 處 helper）的 `resolveThemeData`。透過 `docs/epics/epic-35-design-system-tokens/plans/plan-issue-4.md` 2 個 Task 以 subagent-driven TDD 完成（新增 4 個測試，測試全過、`flutter analyze` 乾淨）。逐 Task 規格合規與程式碼審查、以及最終全分支審查皆核准通過（`reviews/review-issue-4.md`），無 Critical／Important 問題。

**收尾階段修正（計劃書範圍缺口）：** 依 `CLAUDE.md`「測試執行範圍」規範，在整份計劃收尾時執行一次完整 `flutter test`（不帶檔案路徑），發現 `library_screen_test.dart` 有 2 則測試崩潰（`Theme.of(context).extension<ElinkTokens>()!` 對 null 強制解包）——原計劃書只覆蓋了 `reader_screen_test.dart`／`notes_bottom_sheet_test.dart`／`annotation_toolbar_test.dart` 三個測試檔，未算到 `library_screen_test.dart` 透過 `LibraryScreen` 導覽也會間接建構 `ReaderScreen`。已比照計劃書 Step 8 同樣的機械式做法，對該檔案全部 96 處 `MaterialApp(home: LibraryScreen(...))` 補齊 `theme: resolveThemeData(...)`，不做人工篩選（commit `67572770`）。修正後完整 `flutter test` 全專案 1899 個測試全數通過，`flutter analyze` 乾淨。commit 範圍 `e7266fc5..67572770`（branch `feature/epic-35-issue-4`）。

**依賴：** Issue 1（需要 `ElinkTokens` 類別存在）、Issue 2（需要 `resolveThemeData()` 已能透過 `Theme.of(context).extension<ElinkTokens>()` 取值）

**來源：** `spec.md` §「既有語意色遷移到 ElinkTokens」

**背景／目標：** `HighlightStyle` 列舉目前用編譯期常數色票，跟 `ElinkTokens` 的執行期取值架構衝突，需要重構函式簽章而非單純換色值；順便處理同一檔案群組裡另外兩個獨立的小修正（`notes_bottom_sheet.dart` 的 `Colors.red`、`reader_screen.dart` 自己其餘的寫死顏色）。

**Solution：**
- `HighlightStyle` 列舉拿掉 `fixedTint` 欄位；`highlighterYellowTint`／`highlighterPinkTint`／`highlighterBlueTint` 三個頂層常數移除。**列舉成員名稱維持 `highlighterPink` 不改名**（避免破壞 `Enum.values.byName()` 持久化的既有使用者資料）。
- `highlightStyleTint()` 改名為 `highlightStyleColor()`，簽章改為 `Color highlightStyleColor(HighlightStyle style, {required ElinkTokens tokens})`，拿掉 `primaryColor` 參數。函式內容：`highlighterYellow`→`tokens.highlightYellow`、`highlighterPink`→`tokens.highlightGreen`（語意變更，`DESIGN.md` 既有決策）、`highlighterBlue`→`tokens.highlightBlue`、`underline`→`tokens.underlineColor`。
- 呼叫端 `reader_screen.dart:1733,1826`、`notes_bottom_sheet.dart:441` 改為傳入 `tokens`（從 `Theme.of(context).extension<ElinkTokens>()!` 取得），不再傳 `primaryColor`。
- `notes_bottom_sheet.dart` 的 `Colors.red`（L349／L531，刪除按鈕前景色）→ `colorScheme.error`。
- `reader_screen.dart` 檔案內其餘寫死顏色（原 8 檔清單項目）依用途遷移到對應角色。
- **明確排除：** `reader_screen.dart:2740-2753`（`_themedFabBackgroundColor`／`_themedFabIconColor` 等 getter）在固定版面（EPUB FXL／CBZ）分支刻意維持寫死 `Colors.black54`／`Colors.white`，理由已寫在既有註解（真機電子紙實測＋避免蓋在不可預期的圖片背景上失去對比，`epic-22` 已修過的 bug）——這是刻意保留，不算「寫死顏色殘留」，不得連這段也換成主題色。

**單元測試要求：**
- `highlightStyleColor()` 單元測試：四個 `HighlightStyle` 各自對應正確的 `ElinkTokens` 欄位值（`highlighterPink` → `tokens.highlightGreen`）。
- 既有依賴舊 `highlightStyleTint()`／`primaryColor` 參數的測試同步更新為新簽章。
- `notes_bottom_sheet_test.dart` 驗證刪除按鈕前景色為 `colorScheme.error`。
- 既有 `reader_screen_test.dart` 全數通過，無回歸。

**驗收標準：** `highlight_style.dart` 不再有任何編譯期色票常數；三處呼叫端皆已更新為新簽章；`notes_bottom_sheet.dart`／`reader_screen.dart` 內無寫死顏色殘留（`_themedFabBackgroundColor` 等固定版面例外分支不計入，見上方明確排除）；`flutter analyze` 乾淨、`flutter test` 全數通過。

---

## Issue 5：`nav_zone_settings_screen.dart`（電子紙可辨識度補強第二處＋其餘遷移）

**Status:** ✅ 已完成。3 處 `Theme.of(context).dividerColor` 均改讀 `Theme.of(context).colorScheme.onSurface`；`navZoneTemplateIconColor(IconData icon, ColorScheme colorScheme)` 函式簽章擴充傳入 `ColorScheme`，未知圖示回退值與 `middleIcon == null` 佔位色皆遷移至 `colorScheme.surfaceContainerHighest`，紅／藍／綠固定裝飾色維持不變，全檔案無寫死灰色殘留。透過 `docs/epics/epic-35-design-system-tokens/plans/plan-issue-5.md` 2 個 Task 以 subagent-driven TDD 完成（21/21 測試全過、`flutter analyze` 乾淨）。Task 1、Task 2 審查與最終整分支審查皆核准，無 Critical／Important 未決問題。commit 範圍 `434fe70a..bc8f2c02`（branch `feat/epic-35-issue-5`；`bc8f2c02` 為第二輪審查後補上的 dartdoc 註解修正）。**已合併：** PR #208，merge commit `1e73bd3e`。

**全套 `flutter test` 最終確認：** 於 `.worktrees/epic-35-issue-5/app` 執行不帶檔案路徑的完整 `flutter test`，1873 個測試中 29 個失敗，全部集中在 `reader_screen_test.dart`（PDF 畫線手勢相關）與 `remote_catalog_screen_test.dart`（遠端下載排隊相關），皆與本 Issue 唯一改動的 `nav_zone_settings_screen.dart` 無程式碼關聯。已用兩項對照排除迴歸可能：(1) 單獨執行這兩個測試檔於 `main`（與本分支合併基準 `434fe70a` app 程式碼完全相同）100% 全過（222/222）；(2) 於 `main` 執行同一份不帶檔案路徑的完整 `flutter test`，1898 個測試中同樣有 1 個失敗（`pdf_reader_view_test.dart`，平台通道呼叫次數斷言），證實全套規模下本來就存在既有計時／資源競爭型不穩定測試。結論：這 29 個失敗屬於既有全套測試不穩定性，非本 Issue 造成的迴歸。

**依賴：** Issue 2

**來源：** `spec.md` §「電子紙可辨識度補強機制」（`nav_zone_settings_screen.dart` 部分）、「寫死顏色遷移」清單

**背景／目標：** 這個檔案有 3 處直接讀取 `Theme.of(context).dividerColor` 畫九宮格熱區格線／範本卡片邊框，Issue 2 移除顯式 `dividerColor` 覆寫後會退回跟 Dark 衝突色值同一個角色（`outline`），需要獨立處理；順便清掉檔案內其餘寫死顏色。

**Solution：**
- 3 處 `Theme.of(context).dividerColor`（原 L232／L318／L349）直接改讀 `Theme.of(context).colorScheme.onSurface`，不透過 `dividerColor` 這個間接屬性。
- 檔案內其餘 `Colors.grey`／`black45`／`white70` 家族依用途遷移。

**單元測試要求：**
- widget test 驗證 3 處熱區／範本卡片邊框顏色確實讀取 `colorScheme.onSurface`（斷言來源角色，不硬編 hex 值）。
- 既有 `nav_zone_settings_screen_test.dart` 全數通過，無回歸。

**驗收標準：** 檔案內無 `dividerColor` 引用、無寫死顏色殘留；`flutter analyze` 乾淨、`flutter test` 全數通過。**已知殘留風險（非本工單驗收範圍）：** 比照 Issue 2，`onSurface` 補強手法尚未真機驗證。

---

## Issue 6：書架相關寫死顏色遷移（`book_cover.dart`／`layout_preset_book_picker_screen.dart`／`library_screen.dart`／`library_group_management_dialog.dart`）

**Status:** ✅ 已完成並合併回 `main`（PR #209，merge commit `34d73c5f`）。`book_cover.dart`／`library_group_management_dialog.dart` 寫死顏色遷移至 `ElinkTokens`／`colorScheme.error`。收尾記錄 3 項待人類確認事項（Dark 主題邊框／Light 主題徽章對比度目視確認、E-Ink 佔位符外框設計決策），其中 E-Ink 外框已由 Issue 9 完成定案，其餘見 `epic.md` 收尾備註。此行先前忘記從 `ready-for-human` 回填，歸檔前補正。

**依賴：** Issue 2

**來源：** `spec.md` §「寫死顏色遷移」

**背景／目標：** 書架功能相關的四個檔案，功能區塊相近，合併一個工單一次處理。

**Solution：**
- `book_cover.dart`／`layout_preset_book_picker_screen.dart`／`library_screen.dart`：`Colors.grey`／`black45`／`white70` 家族依用途對應 `onSurfaceVariant`／`outline`／`badgeScrim`／`coverPlaceholder`／`progressTrack` 等角色。
- `library_group_management_dialog.dart`：`Colors.red`（L174，刪除文字色）→ `colorScheme.error`。
- `library_screen.dart:747`（E-Ink 切換鈕邊框，非 E-Ink 分支 `Theme.of(context).colorScheme.outline.withValues(alpha: 0.5)`）：用法本身正確（引用 `ColorScheme` 角色，非寫死色），**不需要改寫法**，只需要在 Issue 2 的 Dark `outline` 新值落地後目視確認邊框仍可辨識（見 Issue 2 的已知連帶影響備註）。

**單元測試要求：**
- 既有相關測試（`library_screen_test.dart`、`book_cover_test.dart` 等）全數通過，無回歸。
- `library_group_management_dialog_test.dart` 驗證刪除文字色為 `colorScheme.error`。

**驗收標準：** 四個檔案內無「可遷移」的寫死顏色殘留；`flutter analyze` 乾淨、`flutter test` 全數通過。**（2026-09-04 補充）** 實際結果保留 4 處 `Colors.white`（`book_cover.dart` 雲朵徽章圖示、`layout_preset_book_picker_screen.dart` 與 `library_screen.dart` 各一處選取指示圖示未選取狀態色、`library_screen.dart` 匯入中遮罩文字）與 2 處 `Colors.transparent`（`library_screen.dart` E-Ink 切換鈕邊框「不畫邊框」分支，非顏色）——皆經評估為刻意保留，理由詳見 `plans/plan-issue-6.md` §範圍決定，不算驗收標準未達成，也不是遺漏。

**收尾備註（`epic-35` Issue 6 最終分支審查發現，2026-09-03）：** 上方 Solution 第 3 點交辦的「Dark 主題 `outline` 新值落地後，目視確認 `library_screen.dart:747` E-Ink 切換鈕邊框仍可辨識」這件事，六個 Task 執行完畢後從未實際執行——`plan-issue-6.md` 全程沒有任何 Task 涵蓋這個目視確認步驟。最終審查以數值估算指出風險：Dark `outline`（`#2C2C34`）以 50% alpha 疊在 AppBar `surface`（`#1D1D22`）之上，約略等效於 `#25252B`，跟底色對比度約僅 `1.05:1`，接近不可辨識。上方 Solution 第 3 點「用法本身正確、不需要改寫法」的判斷本身可能仍然成立，這裡不片面改寫法，僅記錄這是一項尚未執行、待人類在真實裝置／模擬器上目視確認的開放項目；確認結果（可辨識或需要調整）待補回本備註，屆時 Status 再視情況調回。

**收尾備註二（本分支合併前的獨立程式審查發現，2026-09-04）：** `badgeScrim` 徽章底色（雲朵圖示／選取指示圈）遷移前是半透明黑（`Colors.black45`／`black54`），疊在任意封面上的合成色最亮情況（白底封面）仍有 3.4~4.6:1 對比度；遷移後四套主題改為不透明色值，經 WCAG 相對亮度公式核算，晴空藍天（Light）主題 `badgeScrim = #94A3B8` 疊白色圖示的對比度降為 **2.56:1**，低於 WCAG 1.4.11 圖形物件 3:1 門檻（Dark `#7A7872` 4.5:1／宣紙 `#848588` 3.7:1／E-Ink 純黑 21:1 皆無問題，只有 Light 主題掉到門檻以下）。`DESIGN.md` L50 對 `badgeScrim` 的定義是「半透明罩」，但四套色值實際皆為不透明 hex，此為 token 定義與用法間既有的落差，非本次改動新增，但本次改動讓 Light 主題的可辨識度實際劣化。不在本分支調整 `ElinkTokens` 色值（Issue 1／Issue 2 已定案凍結，逕改需另立工單比照 Issue 5 教訓走完整審查流程），記錄為待人類在真機上目視確認 Light 主題徽章圖示可辨識度的開放項目，與上方 Dark `outline` 目視確認合併處理。

---

## Issue 7：閱讀器相關寫死顏色遷移（`foliate_reader_view.dart`／`pdf_reader_view.dart`／`pdf_crop_frame_overlay.dart`／`reader_option_tile.dart` 及其呼叫端）

**Status:** ✅ 已完成。`foliate_reader_view.dart`（3×3 導覽熱區除錯疊層）與 `pdf_reader_view.dart`（同一組除錯疊層＋框選拖曳預覽框／備註徽章圖釘／搜尋結果高亮）內的寫死顏色殘留（`Colors.white24`／`white70`／`yellow`／`orange`／`black87`／`deepOrange`）均已改讀 `colorScheme.onSurface`／`primary`／`ElinkTokens.highlightYellow`／`highlightGreen`。`pdf_crop_frame_overlay.dart` 全檔與 `reader_option_tile.dart` 及其三個呼叫端依上方 Solution 明確排除，維持寫死不變。透過 `docs/epics/epic-35-design-system-tokens/plans/plan-issue-7.md` 3 個 Task 以 subagent-driven TDD 完成（新增 8 個測試，全專案 `flutter test` 1908/1908 全數通過，`flutter analyze` 乾淨）。逐 Task 審查（3 次）與最終整分支審查皆核准通過（`reviews/review-issue-7.md`），無 Critical 問題；最終審查發現的 Important 項目（文件收尾未落地）與 1 項 Minor（`_buildSearchHighlightWidget()` dartdoc 過時）已在本次收尾一併修正。**已合併：** PR #210，merge commit `87cfe44e`（branch `worktree-epic-35-issue-7`）。

**收尾記錄（範圍決策沿革）：** 本計劃書第一版曾主張 `pdf_reader_view.dart` 的框選拖曳預覽框／備註徽章圖釘／搜尋結果高亮 3 處比照 `pdf_crop_frame_overlay.dart` 同一類理由（疊加在不可預期的 PDF 頁面內容之上）刻意排除、維持寫死不變。經 `/superpowers:requesting-code-review` 獨立審查指出，這個排除是計劃作者自行類比推論、並非本 Issue 上方 Solution 段落逐字授權的排除（與 `pdf_crop_frame_overlay.dart`／`reader_option_tile.dart` 這兩項規格文件本身逐字寫出的排除性質不同），且 `ElinkTokens` 已有 `highlightYellow`／`highlightGreen` 角色正是為此類情境設計，提請人類決策者確認後改為一併遷移（詳見 `plans/plan-issue-7.md` §範圍決定）。這與本 Epic Issue 5 曾被打回的失敗模式相同，記錄於此供後續 Issue 引以為戒：計劃書若要排除規格文件驗收標準涵蓋範圍內的項目，須有規格文件逐字授權，不能自行類比其他排除案例。

**保留待人工確認事項（2026-09-04，`plan-issue-7.md`「全部 Task 完成後」交辦）：**
1. `reader_option_tile.dart:51` 非 E-Ink 分支的 `theme.colorScheme.outline.withValues(alpha: 0.35)` 選項邊框，在 Issue 2 的 Dark `outline` 新值落地後，於真機／模擬器上目視確認 Dark 主題下仍可辨識——此為 Issue 2／Issue 6 已各自記錄過的同一組風險第三次記錄，`issues.md` Issue 7 原文點名的正式落點，不重複展開分析。
2. `_buildDecorationWidget()` 備註徽章圖釘（`colorScheme.onSurface`）在 E-Ink 主題下與純黑劃線 tint 疊加時可能不可辨識——改動前就存在的既有限制，非本工單新增回歸；E-Ink 模式「不畫底色改畫線條」的正確渲染邏輯屬其他 Issue 範圍。
3. （最終整分支審查 M3 補充）搜尋結果高亮（`_buildSearchHighlightWidget()`）在 E-Ink 主題下會呈現純黑 40% 灰罩（僅靠外框區分 current／非 current）；Sepia 主題下 `highlightGreen`（`#EDF5F0`，近白）比 `highlightYellow`（`#FEF08A`）更淡，可能出現「目前符合結果的底色比其他結果還不明顯」的顯著度反轉，全靠 `colorScheme.primary` 紅框撐辨識度。
4. （最終整分支審查 M4 補充）PDF 端除錯疊層（`colorScheme.onSurface`）在 Dark 主題下對比仍偏低（PDF 頁面本身恆為白紙、不隨主題變色）——相對原本「四套主題下全都看不見」是嚴格改善、非回歸，且此除錯疊層預設關閉，需在「九宮格導覽」設定手動開啟，實務影響低。
5. 本工單自行決定的具體透明度數值（`colorScheme.onSurface.withValues(alpha: 0.24/0.7)`、`colorScheme.primary.withValues(alpha: 0.3)`、`tokens.highlightYellow/highlightGreen.withValues(alpha: 0.4)`）尚未經過真機驗證，需要下一輪真機驗證確認在電子紙上確實可辨識。

**依賴：** Issue 2

**來源：** `spec.md` §「寫死顏色遷移」

**背景／目標：** 閱讀器渲染相關的三個檔案，合併一個工單一次處理。

**Solution：**
- `foliate_reader_view.dart`／`pdf_reader_view.dart`：`Colors.grey`／`black45`／`white70` 家族依用途對應角色。
- **明確排除：** `pdf_crop_frame_overlay.dart` 全檔（遮罩、裁切框邊界、確認/取消按鈕，`Colors.black`／`Colors.white` 等）維持寫死不變——這是疊加在任意 PDF 頁面內容之上的覆蓋層 UI，跟 Issue 4 排除的 `reader_screen.dart` 固定版面分支同一類理由：頁面內容本身顏色不可預期，覆蓋層必須維持與主題無關的高對比，才能確保任何頁面背景上都看得見；不算「寫死顏色殘留」，不需要改。
- `reader_option_tile.dart`（`app/lib/screens/widgets/reader_option_tile.dart`）及其三個呼叫端 `reader_settings_sheet.dart`／`pdf_settings_sheet.dart`／`fxl_settings_sheet.dart`：非 E-Ink 分支的 `theme.colorScheme.outline.withValues(alpha: 0.35)` 選項邊框，用法本身正確（引用 `ColorScheme` 角色），隨 Issue 2 的 Dark `outline` 新值連帶受影響，實作時目視確認 Dark 主題下仍可辨識即可，不算寫死顏色、不需要改寫法。

**單元測試要求：**
- 既有相關測試（若存在）全數通過，無回歸。
- `pdf_crop_frame_overlay.dart` 依上方明確排除維持不變，不需要新增測試。
- `reader_option_tile.dart` 相關既有測試（若存在）全數通過；Dark 主題下邊框可辨識為人工目視確認項目，不強制新增自動化測試。

**驗收標準：** `foliate_reader_view.dart`／`pdf_reader_view.dart` 內無寫死顏色殘留；`reader_option_tile.dart` 用法確認無需修改；`pdf_crop_frame_overlay.dart` 依明確排除維持不變；`flutter analyze` 乾淨、`flutter test` 全數通過。

---

## Issue 8：`txt_cover_generator.dart`（E-Ink 分支：白底黑框黑字）

**Status:** ✅ 已完成。`generateTxtCover()` 加上 `isEinkMode` 參數（`{bool isEinkMode = false}` 預設值寫法，非必要參數——這是計劃書審查階段的修正，理由是必要參數會讓第一個 commit 當下專案暫時無法編譯，違反「每個 commit 都應可編譯」的紀律；預設值寫法讓兩個 commit 各自獨立可編譯，且 Task 2 自己的紅燈測試已足以攔截「忘記接線」風險），E-Ink 模式下背景改白底、新增黑色邊框、書名首字文字色改黑；`BookImportServiceImpl` 建構子新增可選參數 `AppThemePreferences? themePreferences`，TXT／MD 兩個匯入分支各自呼叫 `loadEinkMode()` 取得即時狀態後傳入。文字色驗證方式與本文原「單元測試要求」略有調整：計劃審查（`reviews/review-plan-issue-8.md` C2）指出原案「不做像素採樣」會讓「白底白字」回歸完全測不出來，改為新增一個粗粒度黑色像素存在性掃描（沿畫布中心垂直掃描線取樣，只驗證「有沒有黑色像素」，不比對精確字形，不受平台字型渲染差異影響），逐 Task 審查與最終整分支審查（model=opus）皆確認此設計不會脆弱。透過 `docs/epics/epic-35-design-system-tokens/plans/plan-issue-8.md` 2 個 Task 以 subagent-driven TDD 完成：Task 1 commit `7b6ff672`（9/9 測試通過），Task 2 commit `ac74f37c`（全套 1917/1917 測試通過、`flutter analyze` 乾淨）。逐 Task 審查（spec + quality）與最終整分支審查皆核准，無 Critical／Important 未決問題；最終審查列出的 6 項 Minor 皆經三角驗證判定可直接出貨，不需另立修復工單。commit 範圍 `7b6ff672..ac74f37c`（branch `worktree-epic-35-issue-8`）。**已合併：** PR #211，merge commit `896e3b61`。

**已知殘留、非本 Issue 阻斷項（最終審查發現，記錄供後續追蹤）：**
- `_einkBorderWidth`（8px）為未經真機驗證的具體詮釋值，建議與 Issue 3／Issue 7 已記錄的其餘未驗證視覺細節一併排入下一輪真機驗證；數值集中在 `txt_cover_generator.dart` 單一常數，重新校準不需要改動任何測試斷言座標（角落採樣點對 ≥6px 的任何邊框寬度皆有效）。
- 使用者若在匯入之後才開啟 E-Ink 模式，既有封面不會回頭重繪；反之在 E-Ink 模式下匯入、之後切回一般主題，封面也會維持白底樣式——這是既有架構限制（`generateTxtCover()` 僅在匯入當下呼叫一次），非本工單遺漏，`spec.md` 與計劃書 Global Constraints 已明文排除。

**依賴：** Issue 2

**來源：** `spec.md` §「寫死顏色遷移」（`txt_cover_generator.dart` 部分）

**背景／目標：** 這個函式在匯入當下產生一次 PNG 並存成本機檔案（不是即時渲染），本 Epic 不改變這個既有架構，只讓 E-Ink 模式下產生的封面樣式跟隨規範。

**Solution：**
- `generateTxtCover()` 簽章加 `isEinkMode`（bool 參數，**不傳 `ElinkTokens`**——這是離線產生 PNG 的 `dart:ui` 純函式，不在 widget tree 內，沒有 `BuildContext` 可以取 `Theme.of(context)`，直接吃 bool 更單純，白／黑就地寫死 `ui.Color`，跟本函式其餘色盤做法一致）。
- `isEinkMode == true`：不使用 6 色色盤，背景改白底＋黑色邊框＋書名首字文字色改黑（現行寫死白色 `0xFFFFFFFF` 需一併修正，否則白底白字看不見）。
- `isEinkMode == false`：維持既有 6 色依書名雜湊輪替＋白字行為完全不變。
- **呼叫端串接方式（審查 C1 補強，原本留白）：** `BookImportServiceImpl`（`book_import_service_impl.dart`）建構子新增可選參數 `AppThemePreferences? themePreferences`；`main.dart:77` 既有呼叫處改傳 `themePreferences: themePreferences`（`main.dart:71` 已經建構過這個實例，直接傳入，不需要新建）。TXT／MD 匯入分支呼叫 `generateTxtCover()` 前，先 `await (_themePreferences ?? AppThemePreferences()).loadEinkMode()` 取得當下即時狀態（讀取持久化設定，不依賴 App 記憶體內狀態，避免時機問題）。**這個做法刻意只加建構子選填參數，不改 `BookImportService` 抽象介面／`importFiles()`／`importFolder()` 方法簽章**——不影響呼叫這兩個方法的既有呼叫點，也不影響實作該抽象介面的測試替身，不觸碰 `UI_DESIGN_RULES.md`「Book storage」核心架構紅線。**兩個呼叫點都要改**（`book_import_service_impl.dart:288` TXT 分支傳 `fallbackTitle`、`:348` MD 分支傳 `title`——兩處標題語意本來就不同，跟本工單無關，僅提醒兩處都要各自加上 `isEinkMode` 參數，不要漏了其中一個）。

**單元測試要求：**
- 新增單元測試驗證 `isEinkMode: true` 時輸出 PNG：四角／邊緣像素採樣可安全斷言背景為白、邊框為黑（大面積純色區塊，不受字型渲染差異影響）。
- **文字色不做逐像素精確採樣斷言**（比照既有 `txt_cover_generator_test.dart` 開頭註解的既定原則：文字排版實際渲染像素因平台字型渲染差異而不可靠）——改用同一份測試檔已在用的整體 bytes 比對手法：同標題＋`isEinkMode: true` 兩次呼叫輸出 bytes 相等（渲染穩定性）、`isEinkMode: true` 與 `isEinkMode: false` 同標題輸出 bytes 不相等（確認兩分支確實有差異，非死碼）。
- 新增回歸測試驗證 `isEinkMode: false` 時既有 6 色輪替＋白字行為未受影響。
- `BookImportServiceImpl` 新增建構子參數的呼叫端測試：驗證 TXT／MD 匯入時會依 `themePreferences.loadEinkMode()` 的回傳值正確傳遞給 `generateTxtCover()`。

**驗收標準：** E-Ink 模式下新匯入 TXT 書封面為白底黑框黑字，可辨識；非 E-Ink 模式行為完全不變；`BookImportService` 抽象介面與既有呼叫點不受影響；`flutter analyze` 乾淨、`flutter test` 全數通過。**明確排除：** 已產生的舊封面 PNG 不會回頭重新產生，此為既有架構限制，不在本工單修復範圍。

---

## Issue 9：封面佔位符完整重新設計（DESIGN.md §8.2：圖示／書名縮略／E-Ink 外框）

**Status:** ✅ 已完成（2026-09-04 完成快速 Discovery 並定案，透過 subagent-driven-development 執行完成，commit 範圍 `ee7f50fd`..`520ce389`，逐 Task 審查與最終整分支審查皆通過，Ready to merge: Yes）。**已合併：** PR #212，merge commit `ebccc841`（branch `worktree-epic-35-issue-9`）。

**收尾備註：**
- Task 3 執行期間發現計劃書原先只預期 `library_screen_test.dart` 有 3 則既有測試會被本 Issue 打壞，實際上另外還有 3 則也因為 `BookCover` 顯示書名縮略跟 `_BookGridTile`/`_BookListTile` 本身既有的書名 caption 產生合法的文字重複（核准設計的自然結果，非 bug）而失真，已一併修正，詳見 `plans/plan-issue-9.md` 收尾備註。
- 最終審查發現、明確排除於本工單範圍外的殘留事項：(1) `DESIGN.md §8.2` 文字仍寫「`Icons.book` 圖示」，需更新以符合 A 類實際用 `bookFormatIcon()` 依格式圖示的行為；(2) `remote_catalog_screen.dart`／`cloud_browser_screen.dart` 也有 §8.2 管轄的封面佔位符情境，目前無底色/無 E-Ink 外框，建議另開 Issue；(3) 無封面書籍的螢幕報讀器會把書名唸兩次，建議補 `ExcludeSemantics`。詳見 `plans/plan-issue-9.md` 收尾備註。

**依賴：** Issue 6

**來源：** `DESIGN.md` §8.2；`epic-35` Issue 6 最終分支審查發現

**背景／目標：** `DESIGN.md` §8.2 對封面佔位符的完整要求是 `Icons.book` 圖示（前景色 `onSurfaceVariant`）＋書名文字微型縮略＋E-Ink 模式下純白底加 1.5dp 純黑實線外框三件事。Issue 6 只落地了佔位符背景色遷移到 `tokens.coverPlaceholder`（涵蓋 `book_cover.dart`、`library_screen.dart` 的 `_groupTilePreviewCell`／`_GroupListTile`），圖示種類、書名縮略、E-Ink 外框這三個 §8.2 明講的視覺元素目前完全不存在，Issue 6 計劃書把它們歸類為「未來重新設計」而排除在範圍外。

這造成一個實際的視覺退步：E-Ink 主題下 `coverPlaceholder` 為純白（`Color(0xFFFFFFFF)`），跟 E-Ink 的 `scaffoldBackgroundColor`（同樣是純白）幾乎無法區分，封面佔位符與分類拼貼格「不足 4 本」的空格佔位，在 E-Ink 模式下視覺上會消失不見（只剩中央圖示浮著）。本 Issue 由 `epic-35` Issue 6 最終分支審查發現並開立，避免 Issue 6 計劃書裡「留給未來 UI 補強 Issue」這句話沒有實際落點。

**Discovery 發現（動手規劃前先釐清的關鍵事實）：** 現有三處佔位符其實是兩種不同語意混在一起：
- **A 類**（`book_cover.dart` 的 `BookCover`）：某一本書真的沒有封面圖時的佔位符，已經有依格式圖示（`bookFormatIcon()`：EPUB/AZW3=`menu_book`、PDF=`picture_as_pdf`、TXT/MD=`article`、CBZ=`auto_stories`），只是還沒有書名文字、也沒有 E-Ink 外框。
- **B 類**（`library_screen.dart` 的 `_groupTilePreviewCell`／`_GroupListTile`「不足 4 本」空格）：純色塊，代表「這裡沒有第 N 本書」，不是某一本書，沒有書名可縮略。

`BookCover` 這顆元件同時被共用在差異很大的尺寸上（書架格狀卡片較大、列表列 48×64、`_GroupListTile` 內小到 32×48），固定 32px 圖示＋一行文字在最小尺寸下會擠不下，經 Discovery 確認採 `LayoutBuilder` 依容器尺寸縮放圖示/文字，而非新增 `compact` 參數逐一呼叫端指定。

**Solution：**
- 新增共用元件 `CoverPlaceholder({required IconData icon, String? title})`（放在 `app/lib/library/widgets/book_cover.dart`，與現有 `bookFormatIcon()`／`BookCover` 同檔——都是「封面渲染」職責）。`title == null` 代表 B 類（無書名），渲染空字串佔位、不代表「顯示中」。
- 內部用 `LayoutBuilder` 取得可用寬高，`shortSide = min(寬, 高)`：
  - 圖示大小 `= clamp(shortSide × 0.4, 16, 40)`，取代現行寫死 `size: 32`；前景色 `colorScheme.onSurfaceVariant`。
  - 標題文字僅在「可用高 ≥ 56」時渲染：`Text(title ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center)`，字級 `= clamp(shortSide × 0.14, 9, 12)`，顏色同樣 `colorScheme.onSurfaceVariant`；`title == null` 時渲染空字串（`''`），文字列高度/字級與 A 類完全一致，確保 A/B 視覺佈局對齊，不是省略整段。
  - E-Ink 外框：`Theme.of(context).extension<ElinkTokens>()!.isEink == true` 時，外層加 `Border.all(color: colorScheme.onSurface, width: 1.5)`——E-Ink 主題的 `onSurface` 本身即為純黑（`0xFF000000`），用角色引用而非寫死 `Colors.black`，符合本 Epic 全程「不寫死顏色」規則；非 E-Ink 主題不畫外框。背景色沿用既有 `tokens.coverPlaceholder`（E-Ink 主題下已是純白，Issue 6 已到位，不需要在本元件內另外處理）。
- `BookCover`（`book_cover.dart`）目前的「沒有封面圖」分支（`ColoredBox` + 置中 `Icon`）改為 `CoverPlaceholder(icon: bookFormatIcon(book.format), title: book.title)`。
- `library_screen.dart` 的 `_groupTilePreviewCell`／`_GroupListTile` 兩處「不足 4 本」的 `ColoredBox(color: tokens.coverPlaceholder)` 分支改為 `CoverPlaceholder(icon: Icons.book)`（不傳 `title`，即 B 類）。
- **明確排除：** 真的有封面圖片（`Image.file(...)`）的情況不套用外框／圖示／文字——`DESIGN.md` §8.2 只規範「佔位符」，不含已存在的封面圖片；`BookCover` 的雲朵下載角標（`badge`，非 E-Ink 分支既有邏輯）不受本工單影響。

**單元測試要求：**
- 新增 `app/test/library/widgets/cover_placeholder_test.dart`：
  - 用不同 `SizedBox` 尺寸包住 `CoverPlaceholder`，斷言圖示大小隨容器縮放（例如寬高 200 時圖示大小應為 clamp 上限 40；寬高 20 時應為 clamp 下限 16）。
  - 高度 < 56 時標題文字列不渲染（`find.text` 找不到，或渲染的 `Text` widget 不存在於 tree）；高度 ≥ 56 時渲染。
  - `title: null`（B 類）時渲染空字串文字列，佔位高度與 `title` 非 null 時一致（斷言兩者 `Text` widget 的 render box 高度相等）。
  - `ElinkTokens.isEink: true` 時外框（`Border`）存在且顏色來自 `colorScheme.onSurface`；`isEink: false` 時無外框。
- `book_cover_test.dart` 新增一則測試：無封面圖時顯示書名文字（`find.text(book.title)` 命中）。
- `library_screen_test.dart` 既有測試（`_groupTilePreviewCell`／`_GroupListTile` 相關）全數通過，無回歸——本次改動純視覺疊加，不改變既有 `Key`、互動邏輯、資料流。

**驗收標準：** `BookCover` 無封面圖時顯示依格式圖示＋書名縮略＋（E-Ink 模式下）1.5dp 外框；`_groupTilePreviewCell`／`_GroupListTile`「不足 4 本」空格顯示 `Icons.book`＋（E-Ink 模式下）1.5dp 外框；圖示／文字大小隨容器尺寸縮放，小尺寸（高度 < 56）自動隱藏文字列避免擁擠；`flutter analyze` 乾淨、`flutter test` 全數通過，無回歸。

---

## Issue 10：Issue 9 真機驗證後續追蹤（Dark outline 不可辨識／封面色塊高度不一致／雲端畫面缺口）

**Status:** ✅ 已完成（2026-09-04 透過 subagent-driven-development 執行完成，commit 範圍 `b1236ca2`..`2cd76fa8`，3 個 Task 彼此獨立、逐 Task 審查皆通過，最終整分支審查 Ready to merge: With fixes，唯一 Important 為計劃書 checkbox 未勾選，已修復）。**已合併：** PR #213，merge commit `a42838b7`（branch `worktree-epic-35-issue-10`）。

**依賴：** Issue 9

**來源：** `reviews/real-device-verification-checklist.md` 真機測試結果（項目 1）；規劃階段以 widget test 重現確認的分類拼貼格高度不一致；`plans/plan-issue-9.md` 收尾備註殘留事項 (2)。

**背景／目標：** Issue 9 收尾時已知有 3 項需要真機驗證或另開工單的殘留事項，2026-09-04 實機測試逐項確認後，合併為本工單處理：

1. **Dark 主題 `outline` 疊色 — 書架 E-Ink 切換鈕邊框不可辨識**（真機確認，`app/lib/screens/library_screen.dart:760`）。修法比照 Issue 2／Issue 5 已採用手法，改參照 `colorScheme.onSurface`。
2. **無封面書籍佔位符色塊比有封面書籍矮一些**（真機發現）。根因為 `_GroupGridTile` 內 `Row` 預設寬鬆 cross-axis 約束，`Image.file` 依圖片長寬比例自行決定高度、`CoverPlaceholder` 則強制填滿可用高度，兩者因此不等高；規劃階段已用真實 widget test 重現並確認修法（`CrossAxisAlignment.stretch`）有效。
3. **`remote_catalog_screen.dart`／`cloud_browser_screen.dart` 封面佔位符缺口**：這兩個畫面的無封面佔位符原本沒有 `tokens.coverPlaceholder` 底色、沒有 E-Ink 外框，`DESIGN.md` §8.2 規範範圍涵蓋這兩處，但 Issue 9 討論時排除在範圍外。

**Solution：**（詳見 `plans/plan-issue-10.md`）
- Task 1：`library_screen.dart:760` 邊框色值角色由 `colorScheme.outline` 改為 `colorScheme.onSurface`。
- Task 2：`_GroupGridTile.build()` 內兩個 `Row` 加上 `crossAxisAlignment: CrossAxisAlignment.stretch`。
- Task 3：`remote_catalog_screen.dart`／`cloud_browser_screen.dart` 的 `_buildThumbnail()` 三種佔位分支改接 `CoverPlaceholder`，並傳入 `title: entry.title`／`entry.name` 完整落實 `DESIGN.md` §8.2 書名縮略要求（規劃階段審查〔`reviews/review-plan-issue-10.md`〕發現初版計劃誤判「無現成書名可縮略」，修訂後補上）。

**單元測試要求／驗收標準：** 見 `plans/plan-issue-10.md` 各 Task；全數落實，`flutter analyze` 乾淨、全套 `flutter test`（1930/1930）無回歸。

**收尾備註：**
- Task 3 執行期間發現計劃外的設計衝突：`CoverPlaceholder` 傳入書名後，跟 `_buildEntryTile()` 既有下方書名 caption 產生合法的文字重複。裁定比照 `library_screen.dart` `_BookGridTile`／`BookCover` 已上線的相同疊加先例（Issue 6/9 已審查通過）處理——維持 `title:` 傳入不變，5 則既有測試改為 `findsNWidgets(2)`，不修改 `_buildEntryTile()`／`book_cover.dart`。若日後認定疊加顯示是視覺缺陷，需另開工單調整 `_buildEntryTile()` 的 caption 顯示邏輯。
- 最終整分支審查唯一發現：計劃書 16 個 Step checkbox 完成後未勾選（SDD 稽核紀錄缺口）。修復時因機械式全文取代誤傷兩處說明文字，已由 controller 直接還原，未再派工複審（流程明文排除二次 fix wave）。
- 不擋合併的後續建議：(1) Task 1 的 `outline`→`onSurface` 色值替換同時影響 Light／Sepia 主題，推論正確但未經真機覆核，建議列入下一輪真機驗證清單；(2) `remote_catalog_screen.dart`／`cloud_browser_screen.dart` 的 `_buildThumbnail()` 仍有 3 個分支（remote loading／cloud loading／cloud error）未逐一斷言 `.title` 值，屬既有缺口非本次回歸。
