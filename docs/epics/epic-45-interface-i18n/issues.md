# Epic 45 — 多語系介面：工單清單 (Issues)

依 `spec.md`（Architecting 產出，已通過 `reviews/review-spec.md` 審查修訂）拆解為 11 個垂直切片。既有畫面字串抽取（`spec.md` §10 原 Issue 3）依模組拆成 Issue 3-6 四個獨立工單，取代單一巨大 Issue——理由：`design.md`／架構審視報告皆已指出這是「橫跨全部既有畫面的大範圍工作」，單一工單改動面過大不利審查與驗收；且 `/receiving-code-review`（`review-spec.md` I-1）已定案「每個字串抽取 Issue 必須把觸及畫面對應的測試檔遷移一併納入同一 Issue」，模組化拆分讓這個要求可以逐一落實。

**相依順序**：Issue 0 無依賴（`/receiving-code-review` review-issues I-3 修正後，共用元件 `widgets/eb_sheet_shell.dart` 的在地化已收斂在本 Issue 一次處理完畢，不再是 Issue 3/4 平行執行時的共用檔案衝突風險）→ Issue 1／Issue 2 皆依賴 0（互相獨立，可平行）→ Issue 3 依賴 0＋2（分類名稱顯示已在 Issue 2 處理）；Issue 4／5／6 依賴 0（Issue 5 另依賴 1，「語言」項目本身已在 Issue 1 處理）；Issue 3-6 四者彼此互相獨立，可平行 → Issue 7（執行期例外訊息）依賴 0，與 Issue 3-6 無強制順序但建議在其後（部分例外訊息與已抽取畫面共檔）→ Issue 8（Markdown 匯出）依賴 0，獨立→ Issue 9（收斂清理）依賴 3-6 皆完成（範圍取決於 3-6 實際涵蓋面）→ Issue 10（稽核腳本）建議排最後，可歸納 Issue 0-9 實作出的排除清單經驗。

---

## Issue 0：依賴引進＋核心型別骨架＋`MaterialApp` 接線

**Status:** completed

**依賴：** 無，可立即開始。

**背景：** 本身不含任何使用者可見的介面語言切換行為（`spec.md` §1-3、§8 已定案介面），是後續全部切片共用的基礎設施。

**What to build：**
- `pubspec.yaml` 新增 `flutter_localizations`（`sdk: flutter`）＋`intl`（不釘版本號，隨 `flutter pub get` 解析）；`flutter:` 區塊新增 `generate: true`。
- 新增 `app/l10n.yaml`（`spec.md` §1.2 定案內容，含 `output-dir: lib/l10n`）。
- 新增三份 ARB 骨架：`app/lib/l10n/app_zh_TW.arb`（template）／`app_zh_CN.arb`／`app_en.arb`，各自含 `@@locale` metadata＋至少一個示範 key `groupUncategorized`（三語言皆填入真實翻譯：「未分類」／「未分类」／"Uncategorized"，供 Issue 2 直接使用，避免本 Issue 產出的 ARB 完全空白）。
- 新增 `app/lib/l10n/app_locale.dart`：`AppLocale` enum＋`resolveSupportedLocale()` 純函式（`spec.md` §2.1-2.2，含 C-1 修正後的先比對 `languageCode` 邏輯）。
- 新增 `app/lib/l10n/app_locale_preferences.dart`：`AppLocalePreferences`（`spec.md` §2.3，nullable 儲存語意）。
- `app/lib/main.dart`：`main()` 內讀取 `AppLocalePreferences().loadLocaleOverride()` 取得 `initialLocaleOverride`，透過建構子注入 `ElinkBookApp`（比照既有 `initialTheme`/`initialEinkMode` 模式）；`_ElinkBookAppState` 新增 `AppLocale? _localeOverride`；`MaterialApp` 接上 `locale`／`localizationsDelegates`／`supportedLocales`／`localeListResolutionCallback`（`spec.md` §3 定案內容，含 I-3 修正後走訪完整語言喜好清單的邏輯）。
- 新增 `app/test/support/pump_localized_widget.dart`：`pumpLocalizedWidget()`（`spec.md` §8 定案簽章，含 M-3 修正後的 `AppTheme`/`isEinkMode` 參數）。
- **`ElinkBookApp` 建構子參數相容性（`/receiving-code-review` review-issues M-1 修正）**：`initialLocaleOverride`／`localePreferences` 兩個新建構參數皆須為可選（`this.initialLocaleOverride`，預設 `null`＝跟隨系統；`AppLocalePreferences? localePreferences` 建構子內部 `?? AppLocalePreferences()`），比照既有 `initialTheme = AppTheme.light` 既定模式——既有測試套件多處直接 `ElinkBookApp(...)` 建構且不會傳這兩個新參數，若宣告為必填會導致既有測試編譯失敗。
- **`widgets/eb_sheet_shell.dart` 的 `EBSheetShell`（`/receiving-code-review` review-issues I-3 修正）**：查證實際類別名稱為 `EBSheetShell`（非 `EbSheetShell`），目前**沒有**可覆寫的 `closeTooltip` 建構參數——`tooltip: '關閉'` 直接寫死在 `build()` 內（`eb_sheet_shell.dart:91`）。查證此元件被 5 個檔案引用：`library_screen.dart`／`library_search_screen.dart`／`book_action_sheet.dart`（皆屬 Issue 3 書架模組）與 `notes_bottom_sheet.dart`（屬 Issue 4 閱讀器模組），跨模組共用，若分別留給 Issue 3／4 各自處理會有編輯衝突風險。改在本 Issue（基礎設施階段）一次處理：把 `build()` 內的 `tooltip: '關閉'` 改為 `tooltip: AppLocalizations.of(context)!.close`，Issue 3／4 各自的呼叫端不需要、也不應該再碰這個檔案。

**單元測試要求：**
- `resolveSupportedLocale()`：純函式測試，逐條覆蓋 `design.md` Locale 解析矩陣——`zh_TW`／`zh_HK`／`zh_MO`／`zh_Hant`（無 country）／`zh_CN`／`zh_SG`／`zh_Hans`（無 country）／`en`／`en_US`／其他未支援語言（如 `fr_FR`）；**必須包含 `en_SG`／`en_HK`／`en_TW` 迴歸測試**（`/receiving-code-review` C-1 修正要求），驗證回傳 `AppLocale.en` 而非誤判為中文。
- `AppLocalePreferences`：`loadLocaleOverride()`/`saveLocaleOverride()` 三種值（`zhTW`/`zhCN`/`en`）round-trip；未設定鍵回傳 `null`；`saveLocaleOverride(null)` 清除既有覆寫；儲存值污染（非 enum 名稱字串）時安全回退 `null`。
- `ElinkBookApp` widget test：驗證 `localizationsDelegates`/`supportedLocales` 已正確接上（例如透過 `AppLocalizations.of(context)` 不拋例外）；`localeListResolutionCallback` 在多語言喜好清單情境下（例如 `[Locale('fr'), Locale('en')]`）正確解析出 `AppLocale.en`，不因清單第一項不支援就直接 fallback 正體中文。
- `pumpLocalizedWidget()`：至少一個 smoke test，確認以預設參數呼叫能成功 pump 一個簡單 `Text` widget 且不拋例外。
- 既有 `ElinkBookApp` 相關測試（`theme_test.dart`／`app_lifecycle_sync_test.dart` 等）：確認不傳 `initialLocaleOverride`/`localePreferences` 時仍可正常建構、零回歸。
- `eb_sheet_shell_test.dart`：三語言下 `Key('eb_sheet_shell_close_button')` 的 tooltip 正確在地化；既有 `library_screen_test.dart`／`library_search_screen_test.dart`／`book_action_sheet_test.dart`／`notes_bottom_sheet_test.dart` 中涉及此元件的既有斷言改用 `pumpLocalizedWidget()` 後零回歸。

**驗收標準：** `flutter pub get` 成功；`flutter gen-l10n` 成功產生 `AppLocalizations`（`lib/l10n/app_localizations.dart` 或等效路徑，可被一般 `import` 陳述式引用）；`flutter analyze` 乾淨；`flutter test`（本 Issue 新增測試檔）全數通過；App 實際執行時外觀與既有行為零差異（尚無任何既有畫面改用 `AppLocalizations`）。

**Blocked by：** 無。

---

## Issue 1：語言選擇 UI（設定→外觀）

**Status:** completed

**依賴：** Issue 0（`AppLocale`／`AppLocalePreferences`／`MaterialApp` 接線）。

**背景：** `spec.md` §4 已定案 `LibraryLocaleDependencies` 介面與透傳路徑。

**What to build：**
- `app/lib/screens/library_screen_dependencies.dart` 新增 `LibraryLocaleDependencies`（`spec.md` §4）。
- `ElinkBookApp` → `AdaptiveShellScaffold` → `SettingsScaffold` 逐層透傳；`ElinkBookApp` 新增 `_handleLocaleChanged(AppLocale?)`：`setState()` 更新 `_localeOverride`＋呼叫 `AppLocalePreferences().saveLocaleOverride()`。**參數傳遞風格（`/receiving-code-review` review-issues M-2 修正）**：查證 `AdaptiveShellScaffold` 目前把 `themeDependencies` **攤平**成個別具名參數傳給 `SettingsScaffold`（`currentTheme: widget.themeDependencies.currentTheme`／`onThemeChanged: widget.themeDependencies.onThemeChanged` 等，見 `adaptive_shell_scaffold.dart:125-135`），`LibraryLocaleDependencies` 比照同一慣例攤平為 `currentLocaleOverride:`／`onLocaleChanged:` 傳給 `SettingsScaffold`，不要整包物件傳遞。
- `SettingsScaffold`「外觀」分區新增「語言」`ListTile`（緊接「佈景」之後），點擊開啟 4 選項選擇器（跟隨系統／正體中文／簡體中文／English），選取後呼叫 `onLocaleChanged`。**（`/receiving-code-review` review-issues M-3 修正）**：`currentLocaleOverride == null`（跟隨系統）時，項目 subtitle 動態標註目前實際生效的語言（例如「跟隨系統（正體中文）」），呼叫 `resolveSupportedLocale()` 搭配 `View.of(context).platformDispatcher.locale` 算出，讓使用者不需要自行猜測系統語言目前被解析成什麼。
- ARB 新增對應 key（`settingsLanguageTitle`／`settingsLanguageFollowSystem`／`settingsLanguageZhTW`／`settingsLanguageZhCN`／`settingsLanguageEn` 或等效命名），三語言皆填入真實翻譯（含本 Issue 觸及的這幾個字串本身，即本 Epic 第一批「畫面字串抽取」的最小示範）。

**單元測試要求：**
- `SettingsScaffold` widget test：選取器 4 個選項分別點選，驗證 `onLocaleChanged` 收到正確的 `AppLocale?` 值（`null` 對應「跟隨系統」）；當前選中項目正確反映 `currentLocaleOverride`；`currentLocaleOverride == null` 時「跟隨系統」項目正確附帶目前實際生效語言的動態標註。
- `AdaptiveShellScaffold` widget test：`localeDependencies` 正確原樣傳遞給內部 `SettingsScaffold`。
- `ElinkBookApp` widget test：選取語言後，`MaterialApp.locale` 立即反映新語言（不需重啟）；`AppLocalePreferences.saveLocaleOverride()` 被正確呼叫；選「跟隨系統」後 `_localeOverride` 變回 `null`。
- 沿用既有 `settings_scaffold_test.dart` 慣例，改用 `pumpLocalizedWidget()`。

**驗收標準：** 使用者可在「設定→外觀」看到「語言」項目，4 個選項可切換；切換後畫面立即以新語言渲染（至少「語言」設定項本身與已完成的其他字串），不需重啟 App；重新啟動 App 後記住選擇；選「跟隨系統」後裝置系統語言變更時 App 動態跟隨。`flutter analyze` 乾淨、`flutter test` 通過。

**Blocked by：** Issue 0。

**已知限制（追記，`/superpowers:requesting-code-review` review-issue-1.md M-2）**：`_LanguagePickerSheet` 點擊「目前已選中的語言」時，因 Flutter `RadioGroup`/`RadioListTile` 原生行為（`value == groupValue` 時不觸發 `onChanged`），Sheet 不會自動關閉，需使用者手動點右上角關閉鈕或點遮罩——這是符合預期的單選元件原生行為，不是缺陷，不阻塞本 Issue 驗收。若未來要優化這個互動（例如點擊已選中項也能關閉 Sheet），需另外包一層手勢偵測，留待後續視情況另立小工單處理，非本 Epic 當前排程項目。

---

## Issue 2：系統保留分類名稱在地化契約

**Status:** completed

**依賴：** Issue 0。

**背景：** `spec.md` §5 已定案 `localizeGroupName()`／`BookGroupL10n`／撞名防線介面。**（`/receiving-code-review` review-issues C-1 修正，推翻原「6 個檔案」清單）**：查證後範圍收斂為 3 個真正具備分類名稱顯示 UI 的檔案——`library_group_management_dialog.dart`／`library_move_to_group_dialog.dart`／`cloud_browser_screen.dart`。原清單中的 `reader_screen.dart:1759`（`_buildSearchableBook()` 內 `groupName: BookGroup.uncategorized`）查證後**不是 UI 顯示**，是建構一個純暫態、不落地的搜尋用 `Book` 佔位物件（程式碼註解明寫「填入無意義佔位值即可，不影響任何實際行為」），**嚴禁**改為 `localizeGroupName()`/`displayName()`——這裡的 `BookGroup.uncategorized` 必須維持底層 Sentinel 字面值；`reader_screen.dart` 本身無分類名稱顯示 UI，不屬於本 Issue 範圍，其餘字串留待 Issue 4 處理。`library_batch_actions.dart` 查證僅有「移動到分類」按鈕本身（無具體分類名稱文字渲染），該按鈕文案與 `library_screen.dart` 的一般 UI 文案一併留給 Issue 3 處理，不在本 Issue。

**What to build：**
- `app/lib/library/models/book_group.dart` 新增 `localizeGroupName()` 頂層函式＋`BookGroupL10n` extension（`spec.md` §5.1）。
- `library_group_management_dialog.dart`：新增 `_isReservedGroupName()`（`spec.md` §5.2，C-2 修正後的三語言靜態集合版本），`_addGroup()`／`_renameGroup()` 呼叫 repository 方法前先檢查，命中時顯示錯誤、不呼叫 repository；順帶抽取本檔案其餘既有硬編碼字串（「重新命名分類」「新增分類名稱」等對話框文案，本檔案已因本 Issue 被觸及，一併處理避免另立 Issue 重複編輯同一檔案）。
- `library_move_to_group_dialog.dart`／`cloud_browser_screen.dart` 中所有顯示分類名稱給使用者看的位置，改用 `group.displayName(l10n)` 或 `localizeGroupName(rawName, l10n)`，不得直接顯示原始 `name`／字串；兩檔案其餘既有硬編碼字串一併抽取（同一理由：已被本 Issue 觸及，避免留給 Issue 3/6 重複編輯）。
- ARB 新增 `groupUncategorized`（Issue 0 已建立，本 Issue 消費）＋上述 3 個檔案對話框相關 key。

**單元測試要求：**
- `_isReservedGroupName()`（或等效抽出的頂層純函式）：純邏輯單元測試，覆蓋 `{'未分類','未分类','uncategorized','UNCATEGORIZED','Uncategorized'}` 等大小寫變體皆判定為保留字，一般分類名稱（如「小說」）不誤判。
- `localizeGroupName()`/`displayName()`：三語言 `AppLocalizations` 實例下，系統保留分類正確轉譯，一般分類原樣不變。
- `library_group_management_dialog_test.dart`（改用 `pumpLocalizedWidget()`）：新增/重新命名時輸入三語言任一保留字皆被前端攔截、不呼叫 repository 方法、顯示錯誤訊息。
- `library_move_to_group_dialog_test.dart`／`cloud_browser_screen_test.dart` 改用 `pumpLocalizedWidget()` 且全數維持通過（顯示分類名稱處斷言相應調整）。
- **迴歸驗證（C-1 修正要求）**：`reader_screen_test.dart` 中涉及 `_buildSearchableBook()`／搜尋入口的既有測試維持原樣不變、不遷移至 `pumpLocalizedWidget()`（該檔案的字串抽取與測試遷移統一留給 Issue 4），確認本 Issue 未觸碰 `reader_screen.dart`／`reader_screen_test.dart` 任何一行。

**驗收標準：** 書架分類管理相關的 3 個畫面分類名稱顯示依目前介面語言正確轉譯，切換語言不影響底層資料庫欄位值；任一語言下嘗試新增/重新命名為保留名稱皆被攔截；`reader_screen.dart` 的 `BookGroup.uncategorized` 用法維持原樣未受影響；`flutter analyze` 乾淨、`flutter test` 通過。

**Blocked by：** Issue 0。

---

## Issue 3：書架模組字串抽取＋測試遷移

**Status:** completed

**依賴：** Issue 0、Issue 2（分類名稱顯示已在 Issue 2 處理，本 Issue 處理該模組其餘字串）。

**背景：** `design.md`「依模組分批」第一批。與 Issue 4／5／6 同一套機械式模式：把模組內畫面的硬編碼中文字串改為 `AppLocalizations` key，對應測試檔同步改用 `pumpLocalizedWidget()`。

**What to build（代表性範圍，實際檔案清單以認領當下重新 grep 盤點為準）：**
- `library_screen.dart`／`library_batch_actions.dart`（不含分類名稱顯示，已在 Issue 2 處理）／`library_search_screen.dart`／`book_action_sheet.dart`（含其依賴的 `EBSheetShell`，但 `eb_sheet_shell.dart` 本身已在 Issue 0 處理，本 Issue 不重複修改）／`format_selection_dialog.dart`／`layout_preset_book_picker_screen.dart`／`book_search_screen.dart`／`library/widgets/`（`cover_placeholder.dart`／`book_cover.dart` 等）。
- 每個檔案：硬編碼中文字串改為對應 ARB key（新增至三份 ARB，三語言皆填入真實翻譯）。
- **日期格式化（`/receiving-code-review` review-issues I-1 修正）**：`library_screen.dart:1798` 附近的書籍列表日期顯示（`'${date.year}/${date.month}/${date.day}'` 手動拼接），改用 `intl` 的 `DateFormat.yMd(Localizations.localeOf(context).toString())` 依目前介面語言格式化，不維持手動字串拼接。
- **ICU plural（`/receiving-code-review` review-issues I-2 修正）**：`library_screen.dart:412`（刪除確認對話框「將刪除已選取的 $count 本書籍...」）與 `:1006`（「已選取 $count 本」）兩處計數字串，ARB 定義時必須採用 ICU `plural` 語法（例如 `librarySelectedCount: "{count, plural, =1{已選取 1 本} other{已選取 {count} 本}}"`，中文雖無文法複數變化但英文版本 `other` 分支需要正確單複數），不得機械式抽取成固定字串模板。

**實際執行範圍修正記錄（2026-09-21 認領時 grep 盤點）**：移出 `library_batch_actions.dart`（純邏輯類別，零硬編碼字串）、`format_selection_dialog.dart`（實際屬 Issue 6 範圍，唯一呼叫端為 `remote_catalog_screen.dart`）、`layout_preset_book_picker_screen.dart`（實際屬 Issue 4 範圍，唯一呼叫端為 `reader_screen.dart`）、`library/widgets/cover_placeholder.dart`（檔案不存在，`library/widgets/` 僅有 `book_cover.dart` 且零硬編碼字串）；新增 `full_text_search_confirm_dialog.dart`（與 Issue 5 `settings_scaffold.dart` 共用，比照 Issue 0 收斂 `eb_sheet_shell.dart` 先例，本 Issue 一次處理完畢）。

**單元測試要求：**
- 上述每個檔案的既有測試改用 `pumpLocalizedWidget()`，斷言由裸中文字串改為透過 `AppLocalizations`（或維持字面值斷言但測試環境 locale 釘定 `zh_TW`，見 `spec.md` §8），確保零回歸。
- 新增至少一個 `zh_CN`/`en` locale 下的渲染驗證（可併入 `app/test/l10n/locale_switch_test.dart`，見 Issue 8 前置需求；若本 Issue 先執行，可先在此建立該測試檔案的書架部分）。
- 日期格式化：驗證 `zh_TW`/`zh_CN`/`en` 三語言下書籍列表日期渲染格式符合各自地區慣例。
- ICU plural：驗證選取 1 本／2 本以上兩種情境，英文版本分別渲染正確單複數（不出現 "1 books"）。

**驗收標準：** 書架模組（含批次操作、搜尋、分類移動、封面顯示）在三語言下正確渲染；`flutter analyze` 乾淨、`flutter test`（含本模組觸及的測試檔）全數通過。

**Blocked by：** Issue 0、Issue 2。

---

## Issue 4：閱讀器 Chrome Bar 模組字串抽取＋測試遷移

**Status:** completed

**依賴：** Issue 0。

**背景：** 同 Issue 3 模式，範圍為閱讀器 Chrome Bar 與其彈窗/面板。

**What to build（代表性範圍，實際檔案清單以認領當下重新 grep 盤點為準）：**
- `reader_screen.dart`（`_buildSearchableBook()` 的 `BookGroup.uncategorized` 用法除外，見 Issue 2 的不可變性警示，本 Issue 抽取其餘字串時同樣不得觸碰該行）／`reader_chrome_top_bar.dart`／`reader_chrome_bottom_bar.dart`／`reader_footer.dart`／`toc_bottom_sheet.dart`／`toc_bottom_sheet_pdf.dart`／`notes_bottom_sheet.dart`（依賴的 `EBSheetShell` 已在 Issue 0 處理，本 Issue 不重複修改 `eb_sheet_shell.dart`）／`note_edit_dialog.dart`／`annotation_toolbar.dart`／`tts_panel.dart`／`pdf_search_panel.dart`／`pdf_settings_sheet.dart`／`fxl_settings_sheet.dart`／`reader_settings_sheet.dart`／`pdf_thumbnail_panel.dart`／`paging_bar.dart`／`reading_position_conflict_dialog.dart`／`full_text_search_confirm_dialog.dart`／其餘共用小元件（`widgets/eb_option_chip_group.dart`／`widgets/eb_section_header.dart`／`widgets/eb_stepper.dart`／`widgets/eb_field_card.dart`／`reader_option_tile.dart`／`text_conversion_icon.dart`——**不含** `eb_sheet_shell.dart`，見上）。

**實際執行範圍修正記錄（認領時 grep 盤點）**：移出 `toc_bottom_sheet_pdf.dart`（不存在）、`reader_footer.dart`（零硬編碼字串）、`widgets/eb_option_chip_group.dart`／`widgets/eb_section_header.dart`／`widgets/eb_stepper.dart`／`widgets/eb_field_card.dart`／`reader_option_tile.dart`（零硬編碼字串）、`widgets/text_conversion_icon.dart`（4 處命中是簡/繁字元示意圖示本身要呈現的文字，非待翻譯 UI 文案，不修改）。

**2026-09-22 最終複審補記歸屬（`reviews/review-issue-4-final.md` Important #1／#2）**：`layout_preset_book_picker_screen.dart`（Issue 3 範圍修正記錄誤植為「實際屬 Issue 4 範圍」，本 Issue 認領當下的 grep 盤點未涵蓋此檔案，唯一呼叫端為 `reader_screen.dart._handleApplyFromBook()`）與 `layout_preset_name_dialog.dart`（唯一呼叫端為 `reader_screen.dart._handleSaveAsPreset()`，全 Epic 四個 Issue 的「What to build」清單自始皆未列入）在本 Issue 收尾時仍為硬編碼中文（`AppLocalizations` 使用量皆為 0），複審發現後改列入 Issue 6 範圍（見該段落），本 Issue 不處理；兩者的唯一入口皆在本 Issue 已在地化的「版面預設集」流程內，Issue 6 完成前，英文/簡體介面下該流程仍會出現中文夾雜。

**單元測試要求：** 同 Issue 3 模式，逐檔改用 `pumpLocalizedWidget()`，零回歸。

**驗收標準：** 閱讀器 Chrome Bar 全部面板/彈窗在三語言下正確渲染；`flutter analyze` 乾淨、`flutter test`（含本模組觸及的測試檔）全數通過。

**Blocked by：** Issue 0。

---

## Issue 5：系統設定四分區模組字串抽取＋測試遷移

**Status:** completed

**依賴：** Issue 0、Issue 1（「語言」項目本身已在 Issue 1 處理）。

**背景：** 同 Issue 3 模式，範圍為 `SettingsScaffold` 四分區（外觀／閱讀／同步與帳號／關於）其餘子畫面。

**What to build（代表性範圍，實際檔案清單以認領當下重新 grep 盤點為準）：**
- `settings_scaffold.dart`（「語言」項目外的其餘字串）／`nav_zone_settings_screen.dart`／`tts_defaults_screen.dart`／`reading_defaults_screen.dart`／`sync_settings_screen.dart`／`cloud_account_settings_screen.dart`／`font_management_screen.dart`（內建字型名稱本身不翻譯，見 `design.md` 排除範圍，僅週邊 UI 文案抽取）／`reader_console_log_screen.dart`／`about_screen.dart`。
- **日期格式化（`/receiving-code-review` review-issues I-1 修正）**：`sync_settings_screen.dart` 的 `_formatLastSyncedAt()`（`sync_settings_screen.dart:104-111`）目前手動拼接日期時間字串，既有程式碼註解明寫「不引入 `intl` 套件——只有這一處需要格式化」——這個決策前提已被本 Epic 推翻（`intl` 已是全域依賴），改用 `DateFormat.yMd(locale).add_Hm()`（或等效組合）依目前介面語言格式化。
- **ICU plural（review-issues I-2 修正）**：`settings_scaffold.dart:289` 附近的全文檢索索引進度「已索引 $current / $total 本」，ARB 定義時採用 ICU `plural` 語法（比照 `design.md`／`spec.md` 既有「已索引 40/90 本」範例：英文版單複數綁定於 `total` 而非 `current`）。

**實際執行範圍修正記錄（認領時 grep 盤點）**：
- `settings_scaffold.dart` 原本要求的「已索引 $current / $total 本」ICU plural 索引進度字串經查證現行程式碼不存在（`issues.md` 原始描述已過時，本 Issue 未新增對應邏輯）。
- `settings_scaffold_test.dart` 已在 Issue 1 完整遷移至 `pumpLocalizedWidget()`，本 Issue 不重複遷移。
- `cloud_account_settings_screen.dart._buildProviderTile()` 的 `title`（`'Google Drive'`／`'OneDrive'`）為雲端服務商品牌名不翻譯。

**單元測試要求（`/superpowers:requesting-code-review` review-issue-5.md Minor #1 修正——原文字與下方「實際執行範圍修正記錄」不一致，已同步）：** 除 `settings_scaffold_test.dart`（Issue 1 已完整遷移至 `pumpLocalizedWidget()`，本 Issue 不重複遷移，見上）外，其餘 8 個測試檔維持裸 `MaterialApp(...)` 呼叫、逐一補上 `locale`/`localizationsDelegates`/`supportedLocales` 三參數，零回歸；`font_management_screen_test.dart` 特別驗證字型品牌名（思源黑體等）三語言下皆維持原文不翻譯，並驗證 `buildUploadResultMessage()` 上傳結果訊息 ICU plural 單複數正確；`sync_settings_screen_test.dart` 驗證三語言下「最後同步」日期時間格式符合各自地區慣例。

**驗收標準：** 系統設定四分區全部子畫面在三語言下正確渲染，內建字型名稱維持不翻譯；`flutter analyze` 乾淨、`flutter test`（含本模組觸及的測試檔）全數通過。

**Blocked by：** Issue 0、Issue 1。

---

## Issue 6：其餘管理類彈窗與畫面字串抽取＋測試遷移

**Status:** ready-for-agent

**依賴：** Issue 0。

**背景：** 同 Issue 3 模式，範圍為未歸入 Issue 3-5 的其餘畫面（遠端書庫、雲端匯入、WiFi 傳書、來源導覽等）。

**What to build（代表性範圍，實際檔案清單以認領當下重新 grep 盤點為準）：**
- `remote_server_list_screen.dart`／`remote_server_form_screen.dart`／`remote_catalog_screen.dart`／`wifi_transfer_screen.dart`／`sources_home_screen.dart`／`adaptive_shell_scaffold.dart`／`support/book_import_picker_helper.dart`（本檔案同時是 Issue 7 錯誤代碼映射函式的落點，若排程上與 Issue 7 重疊建議協調）。**`cloud_browser_screen.dart` 已在 Issue 2 完整處理（含分類下拉選單與其餘既有字串），本 Issue 不再處理**（`plan-issue-2.md` Global Constraints 記錄之範圍爭議，2026-09-21 使用者裁定 Issue 2 一次抽完）。
- **`layout_preset_book_picker_screen.dart`／`layout_preset_name_dialog.dart`（2026-09-22 由 Issue 4 最終複審補記歸屬，見該 Issue 段落與 `reviews/review-issue-4-final.md` Important #1／#2）**：兩者唯一呼叫端皆為 `reader_screen.dart`（已在 Issue 4 在地化的「版面預設集」流程，分別是 `_handleApplyFromBook()`／`_handleSaveAsPreset()`），目前仍為硬編碼中文、`AppLocalizations` 使用量皆為 0。認領時請一併確認 Issue 4 收尾後這兩個檔案的呼叫端字串是否仍與本次盤點一致。
- **ICU plural（`/receiving-code-review` review-issues I-2 修正）**：`book_import_picker_helper.dart:106-110`（`showImportResultSnackBar()` 的「已匯入 $importedCount 本」／「$skippedCount 本已存在，已跳過」）採用 ICU `plural` 語法，`importedCount`／`skippedCount` 各自獨立處理單複數（兩個計數彼此獨立，不可共用同一個 `plural` 判斷式）。

**單元測試要求：** 同 Issue 3 模式，逐檔改用 `pumpLocalizedWidget()`，零回歸；`showImportResultSnackBar()` 驗證匯入本數／跳過本數各自為 0／1／多本時，英文版單複數皆正確。

**驗收標準：** 其餘畫面在三語言下正確渲染；`flutter analyze` 乾淨、`flutter test`（含本模組觸及的測試檔）全數通過。

**Blocked by：** Issue 0。

---

## Issue 7：執行期例外訊息在地化

**Status:** ready-for-agent

**依賴：** Issue 0；與 Issue 3-6 無強制順序，但部分例外訊息與已抽取畫面共用同一檔案，建議排在其後執行以減少合併衝突。

**背景：** `spec.md` §6 已定案「慣例」原則（非單一 catch-all 函式）。`design.md` I-3 查證的 14 個檔案：`sync_settings_screen.dart`／`opds_http_client.dart`／`sync_engine.dart`／`book_import_service_impl.dart`／`foliate_reader_view.dart`／`wifi_transfer_screen.dart`／`sqlite_library_repository.dart`／`reader_screen.dart`／`search_repository.dart`／`reader_jump_target.dart`／`custom_fonts_repository.dart`／`txt_charset_detection.dart`／`md_frontmatter.dart`／`kf8_metadata.dart`。

**What to build：**
- 原生 `MethodChannel` 錯誤代碼→在地化字串的映射函式，放在表現層/UI Helper（例如 `book_import_picker_helper.dart`），**不放進** `book_import_service_impl.dart`／`sqlite_library_repository.dart` 等純業務服務層（`/receiving-code-review` I-4 修正）。
- 上述 14 個檔案（或其對應的呼叫端表現層檔案）中，使用者可見的錯誤提示改為 `AppLocalizations` 具名 key（`l10n.errorNetworkConnection`／`l10n.errorSyncFailed`／`l10n.errorBookOpenTimeout`／`l10n.errorOperationFailed` 等，實際 key 集合依逐檔盤點結果定案），禁止使用者可見文字出現 `e.toString()`/`e.message`。

**單元測試要求：**
- 各表現層錯誤映射函式的純邏輯單元測試（輸入錯誤代碼/例外型別，驗證輸出正確的 `AppLocalizations` key 對應結果）。
- 相關 widget test：模擬各類例外情境，驗證 UI 顯示的是在地化字串而非原始例外文字。
- 涉及畫面的既有測試改用 `pumpLocalizedWidget()`。

**驗收標準：** 逐一盤點 14 個檔案，使用者可見錯誤訊息皆為三語言在地化字串；技術除錯細節仍寫入 Console Log；`flutter analyze` 乾淨、`flutter test` 通過。

**Blocked by：** Issue 0。

---

## Issue 8：Markdown 匯出契約變更

**Status:** ready-for-agent

**依賴：** Issue 0。

**背景：** `spec.md` §7 已定案介面。獨立、範圍小，可隨時插入執行。

**What to build：**
- `app/lib/reader/markdown_export.dart` 的 `generateMarkdownExport()` 新增 `required AppLocalizations l10n` 參數，內部系統結構文字改讀 `l10n.xxx`（含 `_highlightStyleLabel()` 樣式標籤）。
- 呼叫端 `NotesBottomSheet` 改傳入 `AppLocalizations.of(context)!`。
- ARB 新增對應 key（`markdownExportTitle`／`markdownExportAuthorLabel`／`markdownExportUnknownAuthor`／`markdownExportProgressLabel`／`markdownExportTimeLabel`／`markdownExportBookmarksSection`／`markdownExportNoBookmarks`／`markdownExportAnnotationsSection`／`markdownExportNoAnnotations`／劃線樣式標籤 4 個 key）。
- **日期格式化（`/receiving-code-review` review-issues I-1 修正）**：`markdown_export.dart` 既有 `_formatDate()`（手動拼接 `y-m-d`）改用 `DateFormat.yMd(l10n.localeName)`（或等效寫法，由傳入的 `l10n` 參數取得目前語言），依目前介面語言格式化「導出時間」。

**單元測試要求：**
- `markdown_export_test.dart`（純 Dart `test()`）：改用 `lookupAppLocalizations(Locale)` 同步取得三語言各自的 `AppLocalizations` 實例（`spec.md` §7 I-5 修正指引），驗證匯出內容依語言正確切換，書名/作者/位置標籤等使用者資料不受影響；驗證「導出時間」依三語言正確格式化（不再是固定 `y-m-d` 格式）。
- `NotesBottomSheet` 既有測試改用 `pumpLocalizedWidget()`，驗證匯出呼叫正確傳入 `l10n`。

**驗收標準：** Markdown 匯出的系統結構文字依目前介面語言正確輸出；書名/作者/備註內容等使用者資料不受影響；`flutter analyze` 乾淨、`flutter test` 通過。

**Blocked by：** Issue 0。

---

## Issue 9：收斂清理——其餘邊角測試檔遷移至 `pumpLocalizedWidget()`

**Status:** ready-for-agent

**依賴：** Issue 3、Issue 4、Issue 5、Issue 6（範圍取決於這四個 Issue 實際涵蓋面，本 Issue 只處理殘餘未觸及的測試檔）。

**背景：** `spec.md` §10（I-1 修正後）：既有 68 個測試檔中，Issue 3-6 已依模組逐一遷移對應測試檔；本 Issue 收斂清理剩餘未被任何模組 Issue 觸及、但仍是裸 `MaterialApp(...)` 的邊角測試檔（例如共用小元件測試、尚未歸類的獨立 widget 測試）。

**What to build：**
- 盤點 Issue 3-6 完成後仍殘留裸 `MaterialApp(...)` 且未配置 `localizationsDelegates` 的測試檔，逐一改用 `pumpLocalizedWidget()`。
- 新增（或補完 Issue 3 已起頭的）`app/test/l10n/locale_switch_test.dart`：針對 `SettingsScaffold`／`LibraryScreen` 等代表性畫面在 `zh_CN`/`en` locale 下驗證關鍵字串正確渲染。

**單元測試要求：** 純遷移工作，本身即測試調整；驗收標準是全套 `flutter test` 通過、零回歸。

**驗收標準：** `app/test/` 內不再有裸 `MaterialApp(...)` 缺少 `localizationsDelegates` 的既有測試檔；完整 `flutter test` 通過。

**Blocked by：** Issue 3、Issue 4、Issue 5、Issue 6。

---

## Issue 10：防遺漏稽核腳本

**Status:** ready-for-agent

**依賴：** 建議排最後執行（可歸納 Issue 0-9 實作過程中發現的合法硬編碼中文字面值案例，作為排除清單的實證基礎），技術上僅依賴 Issue 0（有 ARB/AppLocalizations 基礎設施即可開始）。

**背景：** `spec.md` §9 已定案介面。

**What to build：**
- 新增 `app/tool/check_l10n_hardcoded_strings.js`（`spec.md` §9 定案規則，含 M-4 修正後的註解剝離前處理）。
- 排除清單：`book_group.dart`（系統保留 Sentinel 常數定義）、內建字型品牌名所在檔案、`epic-42-text-conversion` 簡繁字典檔案、`app/test/**`；具體清單依 Issue 0-9 實作過程中遇到的合法案例補齊。
- 是否接入 CI／`flutter analyze` 前置檢查，依專案既有 CI 設定方式決定。

**單元測試要求：** 腳本本身可用一組已知的「應該觸發」與「應該被排除」的樣本 `.dart` 片段驗證行為正確（Node 測試或簡單斷言腳本，比照 `check_foliate_es_compat.js` 若有自身測試機制的既有慣例）。

**驗收標準：** 對 `app/lib/` 執行腳本，零假警報（既有排除清單案例皆正確跳過）、且能正確抓出人為植入的一個測試用硬編碼字串；`docs/epics/epic-45-interface-i18n/epic.md` 記錄本 Epic 全部既有畫面字串抽取工作於 Issue 3-9 完成後的最終稽核結果。

**Blocked by：** 無強制阻塞，建議排最後。
