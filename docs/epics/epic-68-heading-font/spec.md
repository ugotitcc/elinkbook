# `epic-68-heading-font` Spec：標題字型的核心介面與型別

本檔是該 Epic 的唯一事實來源（決策背景見 `design.md`，編號 D# 指 design 決策）。不含實作步驟。

## 1. 資料模型

### 1.1 SQLite（主庫 `version` 29 → 30）

```
book_reader_prefs
  + heading_font_family TEXT   -- 可為空；NULL＝跟隨主字型（D5、D12）
```

- `_createBookReaderPrefsTable`（新裝置／`oldVersion < 2` 一步到位）含此欄位。
- 遷移 `_addHeadingFontFamilyColumn(Database db)`：先查 `sqlite_master` 確認 `book_reader_prefs` 存在才 `ALTER TABLE … ADD COLUMN heading_font_family TEXT`；呼叫處為 `if (oldVersion < 30)`，**放在 `oldVersion >= 2` 的 else 分支內**（理由同 `_addFirstLineIndentColumn`）。
- 不回填；舊列為 `NULL`。`version` 常數與全部測試中的硬編 29 同步改 30。

### 1.2 `BookReaderPrefs`（`app/lib/reader/book_reader_prefs.dart`）

```dart
final String? headingFontFamily; // null＝跟隨主字型；值為字型家族名稱字串，語意同 fontFamily
```

- 位置：緊接 `fontFamily` 之後。
- 必須同步：建構子、`toMap`（key `'heading_font_family'`）、`fromMap`（`map['heading_font_family'] as String?`，缺 key 為 null）、`==`、`hashCode`、`copyWith`、`reflowableEpubFields()`（**納入白名單**，使版面預設集與「從其他書複製」帶上，D7）。
- `copyWith` 是 `newValue ?? this.value`（無 sentinel，不能清回 null），本 Epic **不引入 sentinel**：`headingFontFamily` 比照 `fontFamily` 同法處理；「改回跟隨主字型」靠 `ReaderSettingsSheet._currentDraft` 整列建構（直接傳 null）達成。
- 版面預設集 `prefs_json` 無 schema 版本；舊資料缺 key 讀為 null（D7，不需遷移）。

### 1.3 `ResolvedPreferences`（`resolved_preferences.dart`）與 `reader_prefs_manager_impl.dart`

```dart
final String? headingFontFamily; // 直接取 book.headingFontFamily，無全域預設（D6）
```

## 2. 退回語意（D8）

不新增 `AvailableFonts` 方法。沿用 `String? effectiveFamily(String? preferred)`：

```
heading = fonts.effectiveFamily(resolved.headingFontFamily)
heading == null  → 不輸出標題規則（沿用主字型規則；主字型為書本字型時即書本字型）
heading != null  → 輸出標題規則
```

設定面板下拉目前值同樣取 `effectiveFamily(_headingFontFamily)`，不可用時顯示「跟隨主字型」；**絕不改寫偏好**（ADR 0035）。

## 3. 渲染契約

### 3.1 Dart → JS（`foliate_reader_view.dart`）

- `FoliateReaderView` 新增 `final String? headingFontFamily;` 與建構子參數。
- `buildFoliatePreferencesMap`：`if (view.headingFontFamily != null) map['headingFontFamily'] = view.headingFontFamily!;`
- `foliatePreferencesChanged`：加入 `oldView.headingFontFamily != newView.headingFontFamily`（漏掉會導致變更後須重開書才生效）。
- `reader_screen.dart`（Foliate 分支，約 2925 行）：`headingFontFamily` 僅在「流式 EPUB／KF8／TXT／MD」傳 `fonts.effectiveFamily(resolved.headingFontFamily)`，FXL 與 CBZ 一律傳 null（D4）。判斷條件**不可只用 `_isFixedLayout`**（它只在宣告值為 true 時才為 true，舊資料 CBZ 宣告值為 null 時仍為 false，`reader_screen.dart:604-607`）；須同時排除 `_dispatchedIsFixedLayout == true` 與 `format == BookFormat.cbz`。

### 3.2 JS（`foliate/main.js` `buildOverrideCss`）

```js
if (prefs.headingFontFamily) {
  // 含後代：主字型規則直接指定在 span/a 等元素上，只寫 h1–h6 會被內層元素蓋掉（D3）
  const hs = ['h1','h2','h3','h4','h5','h6']
  rules.push(`${hs.map(h => `${h}, ${h} *`).join(', ')} { font-family: '${prefs.headingFontFamily}' !important; }`)
}
```

- **必須在主字型規則（`main.js` 約 446 行）之後輸出**：`h1 *` 特異度為 (0,0,1)，與主字型規則的 `span`、`a`（(0,0,1)）相同，同為 `!important` 時由後出現者勝，**依賴順序**。`h1`(0,0,1) 高於停用書本 CSS 的 `*`(0)，該情境勝出。
- 不處理字重（D9：沿用 `fontWeight` 規則）。
- `foliate/legacy/main.js` 由 `pnpm build`（`app/tool/foliate_legacy`）重新產生並一併 commit，不手改（D14）。
- 家族名稱含單引號的處理沿用主字型規則既有作法，本 Epic 不擴大。

## 4. UI 契約

- `ReaderSettingsSheet` 的字型卡片（`_buildFontFamilyDropdown` 所在 `EBFieldCard`）內，主字型下拉之下新增標題字型下拉：
  - `Key('reader_settings_heading_font_family')`，`DropdownButton<String?>`，`isExpanded: true`。
  - 第一項 `value: null`，文字 `readerSettingsFollowBodyFontLabel`（「跟隨主字型」）；其餘選項與主字型相同（內建已下載字型＋自訂字型）。
  - 目前值 `fonts.effectiveFamily(_headingFontFamily)`；`onChanged` 寫入 `_headingFontFamily` 並 `_notifyChanged()`；草稿 `_currentDraft`、`initState`、`didUpdateWidget` 三處同步。
  - 只在流式 Foliate 設定面板顯示；`FxlSettingsSheet`／`PdfSettingsSheet` 不顯示，但 `FxlSettingsSheet` 整列重建須保留既有 `headingFontFamily`（不清空）。
- 既有主字型標籤 `readerSettingsFontFamilyLabel` 文案改為「主字型」，新增 `readerSettingsHeadingFontFamilyLabel`（「標題字型」）；`readerSettingsFollowBodyFontLabel` 為新 key；實際 arb 為 `app_zh_TW`／`app_zh`／`app_zh_CN`／`app_en` 四份，並須重新產生 `app_localizations*.dart`；標籤文案改動會打壞 `test/screens/reader_settings_sheet_test.dart` 現有斷言（約 2352、2373、2394 行），須同步更新，並通過 `node tool/check_l10n_hardcoded_strings.js`。

## 5. 刪除自訂字型連動（D11、D16）

`CustomFontsRepository`（`lib/reader/custom_fonts_repository.dart`，簽章不變）：

```dart
Future<int> countBooksUsing(String familyName);        // WHERE font_family = ? OR heading_font_family = ?
Future<void> deleteAndResetUsage(int id, String familyName);
// 同一交易：DELETE custom_fonts；
// UPDATE book_reader_prefs SET font_family = NULL WHERE font_family = ?;
// UPDATE book_reader_prefs SET heading_font_family = NULL WHERE heading_font_family = ?;
// 兩條各自條件式，不可合併成一條同時清兩欄。
```

`FakeCustomFontsRepository`（`test/support/`）同步同語意。

## 6. 整列重建守衛清單（D15）

下列位置建構／複製 `BookReaderPrefs` 時必須帶上 `headingFontFamily`，各自要有「不被清空」測試：

| 位置 | 動作 |
|---|---|
| `book_reader_prefs.dart` `copyWith`／`reflowableEpubFields()` | 帶入 |
| `library_screen.dart`（書架版面覆寫 `_save`，約 1944） | 帶入既有值 |
| `fxl_settings_sheet.dart`（約 67） | 帶入既有值 |
| `reader_settings_sheet.dart`（`_currentDraft`、init、重置） | 帶入／同步 |
| `test/support/full_book_reader_prefs.dart` 種子與欄位計數斷言 | 補欄位、計數＋1 |

## 7. 非目標

標題字重、標題字級、全域預設、PDF／FXL／CBZ 套用、以 class 啟發式辨識章名。
