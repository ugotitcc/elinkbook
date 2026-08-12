# Epic 18 — 真機 UI 精修：規格 (Spec)

本文件只涵蓋新增或異動「跨層介面契約」的部分（Issue 4、Issue 5）。Issue 1／2／3 是單一 Dart widget 內的版面調整，不涉及新介面，其精確行為規格直接寫在 `issues.md` 對應段落，不重複列於此處。

## 模組 (Modules)

- **`app/android/app/src/main/assets/foliate/main.js`（異動）**——**審查修正**：`buildOverrideCss(prefs)` 是既有純函式（只組裝、回傳 CSS 規則字串，不觸碰 `view`），本 Epic 維持這個既有職責不變，**不在其內部呼叫 `setAttribute`**。所有 `view.renderer.setAttribute('margin-top', ...)`／`setAttribute('margin-bottom', ...)`／`setAttribute('max-column-count', ...)` 呼叫一律加在 `window.applyPreferences(prefs)`（既有的偏好套用進入點，`pageTurnMode`/`writingMode` 已是同樣模式：讀取 `prefs.xxx` → 呼叫 `setAttribute` → 最後才呼叫 `view.renderer.setStyles([fontFaceCss, buildOverrideCss(prefs)])`），維持既有「純函式算 CSS 字串、`applyPreferences` 統一處理副作用」的既有分工。**不修改** `paginator.js`／`view.js` 等 vendored 檔案本身——`margin-top`／`margin-bottom`／`max-column-count` 三者皆已是 `paginator.js` 既有 `observedAttributes`（`paginator.js:1158-1159`），設定後由既有 `attributeChangedCallback()`（`paginator.js:1545-1559`）自動生效，本 Epic 只需要在 `applyPreferences` 內呼叫 `view.renderer.setAttribute(name, value)`。
- **`app/android/app/src/main/kotlin/cc/ugotit/elinkbook/FoliateEpubReaderView.kt`（異動）**——`setPreferences`／`openBook` 既有的偏好 map 透傳機制不需要新增 method channel case（沿用既有 `applyPreferences(prefs)` JS 呼叫），只需要確認新的 `singleColumn` 欄位會原樣包含在傳給 `window.applyPreferences()` 的 JSON 物件中（現有寫法已是整包 `Map<String, Any?>` 透傳，見 `FoliateEpubReaderView.kt` 既有 `setPreferences`/`openBook` case）。
- **`app/lib/reader/book_reader_prefs.dart`（異動）**——新增 `final bool? singleColumn` 欄位（`null`＝未覆寫，交由 foliate-js 既有的 `--_max-column-count: 2` 自動判斷；`true`＝強制單欄；`false`＝明確允許雙欄，語意上等同 `null` 但保留三態一致性，比照既有 `publisherStyles` 欄位的 nullable-bool 慣例）。`toMap()`／`fromMap()`／`copyWith()`／`==`／`hashCode` 皆需同步新增此欄位。
- **`app/lib/reader/foliate_epub_reader_view.dart`（異動）**——`FoliateEpubReaderView` 新增建構參數 `final bool? singleColumn`；`_buildPreferencesMap()` 新增 `if (widget.singleColumn != null) map['singleColumn'] = widget.singleColumn;`；`_preferencesChanged()` 新增 `|| widget.singleColumn != oldWidget.singleColumn`。
- **`app/lib/screens/reader_settings_sheet.dart`（異動）**——新增一個 `SwitchListTile`（比照既有 `reader_settings_disable_book_css`／`reader_settings_show_header` 寫法），`key: Key('reader_settings_single_column')`，標籤「強制單欄（直排）」，`value: _singleColumn ?? false`，`onChanged` 更新本地狀態並呼叫 `_notifyChanged()`。
- **`app/lib/screens/reader_screen.dart`（異動）**——`_buildNativeView()` 的 `FoliateEpubReaderView(...)` 建構呼叫新增 `singleColumn: resolved.singleColumn`（比照既有 `writingMode`／`pageTurnMode` 等既有偏好參數的傳遞方式）。

## 資料模型 (Data Model)

### `book_reader_prefs` 資料表新增欄位

```sql
ALTER TABLE book_reader_prefs ADD COLUMN single_column INTEGER; -- nullable：NULL=未覆寫、0=false、1=true
```

比照既有 `show_header`/`show_footer` 欄位的既有 migration 慣例（`if (oldVersion < N)` 累加式，`BookReaderPrefsRepository` 或對應的 schema migration 檔案，需在實作階段確認確切的 migration 版本號與所在檔案）。

## 介面 (Interfaces)

### `main.js` 上下邊距組裝（Issue 4）

`buildOverrideCss(prefs)` 目前只組裝：

```js
if (typeof prefs.pageMargins === 'number') {
  rules.push(`body { padding: 0 ${1.5 * prefs.pageMargins}em !important; }`)
}
```

新增：`window.applyPreferences(prefs)` 內（**不是** `buildOverrideCss` 內部，見上方「模組」段落審查修正）對應的上下邊距透過 `view.renderer.setAttribute('margin-top', ...)`／`setAttribute('margin-bottom', ...)` 設定（**不是** CSS `body padding`——`paginator.js` 的 `--_margin-top`/`--_margin-bottom` 是版面配置引擎自己計算分頁時使用的版心邊界，與 `body` CSS padding 是兩個不同的機制，混用會造成邊距被計算兩次，這正是項目 7「本文與頁尾間空白過多」的根因之一，見 `design.md`「調查結論」）。

**審查修正——CSS 單位要求**：`paginator.js` 把 `--_margin-top`/`--_margin-bottom` 直接用在 `height: var(--_margin-top)` 這類長度屬性上（`paginator.js:1332/1336`），`setAttribute()` 傳入的值**必須是帶單位的字串**（例如 `"24px"`），不能是純數字或不帶單位的字串——純數字對 CSS 長度屬性是無效值，會被引擎忽略、邊距形同沒設定，且不會有任何錯誤訊息，是容易被忽略的靜默失敗。實作時務必確認組出的字串包含 `px`（或選定的其他 CSS 長度單位）後才呼叫 `setAttribute`。

下邊距具體數值需在實作階段量測「頁尾實際佔用高度」後決定是否需要動態依 `ReaderFooter`/`showFooter` 狀態調整，或是否維持一個較小的固定值即可解決「多一行空白」的症狀——精確公式由 Task 執行階段的 Plan 決定，本規格只界定「透過 `setAttribute`（帶 CSS 單位字串）而非 CSS padding」這個機制層級決策。

### `singleColumn` 偏好（Issue 5）

| 層級 | 欄位/方法 | 型別 |
|---|---|---|
| SQLite | `book_reader_prefs.single_column` | `INTEGER`（nullable） |
| Dart 資料模型 | `BookReaderPrefs.singleColumn` | `bool?` |
| Dart Widget | `FoliateEpubReaderView.singleColumn` | `bool?`（建構參數） |
| Dart→原生 | `setPreferences`/`openBook` 的 `initialPreferences`/偏好 map | `"singleColumn": bool`（只在非 null 時出現在 map 中，比照既有欄位慣例） |
| 原生→JS | `window.applyPreferences(prefs)` | `prefs.singleColumn: boolean \| undefined` |
| JS→foliate-js | `view.renderer.setAttribute('max-column-count', prefs.singleColumn ? '1' : '2')`（同樣加在 `window.applyPreferences(prefs)` 內，非 `buildOverrideCss`） | 字串（`setAttribute` API 要求；`max-column-count` 用於 CSS `calc()` 乘數，非長度屬性，不需要單位） |

`prefs.singleColumn` 為 `undefined`（Dart 端 `null`，未加入 map）時，`main.js` 不呼叫 `setAttribute('max-column-count', ...)`，保留 `paginator.js` 內建預設值 `2`（`paginator.js:1238`），維持 foliate-js 原有的自動判斷行為——這是「預設關閉」（`design.md` 決策 #3）在機制層級的具體實作方式：不是「呼叫 `setAttribute('max-column-count', '2')`」，而是「完全不呼叫」，兩者對第一次開書而言效果相同，但後者不會意外覆蓋 foliate-js 未來版本可能調整的內建預設值。

## 測試決策 (Testing Decisions)

- **`main.js`／`FoliateEpubReaderView.kt` 的 `setAttribute` 呼叫本身無 JVM/JS 單元測試**（比照 Epic 17 既有慣例——`evaluateJavascript`/`WebView` 呼叫是框架 API 直接串接，無可抽出的純邏輯），驗收依賴真機 `integration_test` 與人工視覺確認。
- **`BookReaderPrefs.singleColumn` 欄位的 `toMap`/`fromMap`/`copyWith`/`==`/`hashCode`** 需要 `flutter test` 單元測試（比照既有 `showHeader`/`showFooter` 欄位新增時的既有測試模式）。
- **`FoliateEpubReaderView._buildPreferencesMap()`／`_preferencesChanged()`** 需要 widget test（比照既有欄位新增時的既有測試模式，見 `app/test/reader/foliate_epub_reader_view_test.dart` 既有結構）。
