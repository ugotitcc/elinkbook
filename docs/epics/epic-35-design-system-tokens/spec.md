# Epic 35 — 設計系統 Token 落地：Architecting Spec

自本文件起，這是 `epic-35-design-system-tokens` 的唯一事實來源，取代 `design.md` 中「已知風險」「其他待決定小項」的未定案狀態。

## Problem Statement

讀者換主題（晴空藍天／夜讀水墨／宣紙古風）或開啟 E-Ink 高對比模式時，畫面顏色不可靠：主色其實是紫色（非設計文件指定的天空藍），羊皮紙／深色主題下 Material 3 沒填滿的角色會透出預設淡紫色，螢光筆/進度條/封面佔位色等在各畫面各自寫死，同一個語意在不同畫面可能長得不一樣。因為顏色分散寫死在十幾個檔案裡，沒有人能有把握地說「換一次主題，全部畫面都會正確跟著換」。

## Solution

把 `DESIGN.md` §1 定義的色彩系統做成一個真正的 `ElinkTokens`（`ThemeExtension`），讓所有畫面透過 `Theme.of(context)` 統一取色，不再各自寫死。既有的 `resolveThemeData({theme, isEinkMode})` 保留為唯一組裝入口，只補齊角色與掛上 `ElinkTokens`，不重寫既有的「E-Ink 覆寫任何主題」邏輯。Dark 主題兩個跟真機電子紙實測衝突的角色（`outline`／`surfaceContainerHighest`）改採 `DESIGN.md` 色表值以維持配色一致性，可辨識度風險改用元件層級的邊框補強手法解決（見下方 Implementation Decisions）。

## User Stories

1. 作為讀者，我希望切換到「夜讀水墨」主題時，App 裡每一個畫面（書架、閱讀器、設定、來源）的顏色都正確换成深色系，不要有任何角落還殘留預設的淡紫色。
2. 作為讀者，我希望切換到「宣紙古風」主題時，看到的是宣紙暖色調，不是 Material 3 預設的淡紫色透出來。
3. 作為讀者，我希望開啟 E-Ink 高對比模式時，不管我原本選的是哪個主題，畫面都變成純黑白、無中間灰。
4. 作為讀者，我希望在 E-Ink 高對比模式下，設定畫面的主題選擇器清楚顯示「鎖住不可選」，而不是變得半透明看起來像故障。
5. 作為讀者，我希望在夜讀水墨主題下，即使是電子紙裝置，設定畫面裡的開關（Switch）仍然清楚看得見開/關狀態，不會因為主題換了就看不清楚。
6. 作為讀者，我希望我的螢光筆顏色（黃/綠/藍）在三個主題跟 E-Ink 模式下都維持可辨識、風格一致。
7. 作為讀者，我希望書架封面卡片的進度條、空白佔位封面，在每個主題下都用該主題自己的顏色，不是寫死的灰色。
8. 作為讀者，我希望書架長按進多選、單書刪除確認等破壞性操作的提示色，在深色/羊皮紙主題下也維持清楚可讀的警示色（不是寫死的紅），跟主題其他顏色協調。
9. 作為讀者，我希望我在 E-Ink 模式下匯入新的 TXT 書時，自動產生的封面維持純黑白風格，不要出現一塊鮮豔色塊跟畫面其他地方的極簡黑白風格不搭。
10. 作為讀者，我希望我在非 E-Ink 模式下匯入 TXT 書，封面依然有豐富的顏色變化，方便我在書架上用顏色快速辨認不同的書（此行為維持不變）。
11. 作為未來要維護這份設計系統的工程師，我希望顏色只定義在一個地方（`ElinkTokens`／`ColorScheme`），改一個色票就能讓全部畫面同步更新，不用在十幾個檔案裡找哪裡還寫死了顏色。
12. 作為未來要維護這份設計系統的工程師，我希望既有的「Dark 主題可辨識度」真機驗證知識（哪個色值在電子紙上看不見）不會因為這次重構而遺失，而是轉化成另一種仍然有效的補強手法。

## Implementation Decisions

### 核心型別：`ElinkTokens`

`ElinkTokens` 建為 `ThemeExtension<ElinkTokens>` 子類別，欄位（沿用 `DESIGN.md` §1.2 骨架，此處為正式定案版本）：

```dart
class ElinkTokens extends ThemeExtension<ElinkTokens> {
  final Color highlightYellow;
  final Color highlightGreen;   // 取代舊有 highlighterPinkTint，語意色由粉紅改綠（DESIGN.md 既有決策，非本 spec 新增）
  final Color highlightBlue;
  final Color underlineColor;
  final Color progressTrack;
  final Color coverPlaceholder;
  final Color badgeScrim;
  final Color ttsActiveHighlight;
  final bool isEink;
  final bool reducedMotion;
  final bool discretePaging;

  const ElinkTokens({
    required this.highlightYellow,
    required this.highlightGreen,
    required this.highlightBlue,
    required this.underlineColor,
    required this.progressTrack,
    required this.coverPlaceholder,
    required this.badgeScrim,
    required this.ttsActiveHighlight,
    required this.isEink,
    required this.reducedMotion,
    required this.discretePaging,
  });

  @override
  ElinkTokens copyWith({ /* 每個欄位對應的具名選填參數 */ });

  @override
  ElinkTokens lerp(ThemeExtension<ElinkTokens>? other, double t);
  // isEink/reducedMotion/discretePaging 三個 bool 欄位在 lerp 時取 t < 0.5 ? this : other 的離散切換（無漸變意義），
  // 其餘 Color 欄位用 Color.lerp 正常插值。
}
```

（此型別骨架取自 `DESIGN.md` §1.2，這裡是本 Epic 落地時的正式介面定案，非重新設計。）

### `resolveThemeData()` 銜接方式（既有函式簽章不變）

`resolveThemeData({required AppTheme theme, required bool isEinkMode}) -> ThemeData` 維持既有簽章與既有的「`isEinkMode` 為 true 時無條件套用 E-Ink 主題」邏輯不變。改動的是內部：四個 `_build*Theme()` 各自在回傳的 `ThemeData` 上加 `extensions: [ /* 對應該主題+模式的 ElinkTokens 實例 */ ]`。三個一般主題各自對應各自的 `ElinkTokens`（`isEink: false`／`reducedMotion: false`／`discretePaging: false`），`_buildEinkTheme()` 對應唯一一組 `isEink: true`／`reducedMotion: true`／`discretePaging: true` 的 `ElinkTokens`，其餘色彩欄位皆為 `DESIGN.md` §1.2 E-Ink 欄位值（黑/白為主）。

### 四套 `ColorScheme` 對齊 `DESIGN.md` §1.1（含本次 Architecting 決議的例外處理）

三主題＋E-Ink 全部角色（`primary`／`onPrimary`／`primaryContainer`／`onPrimaryContainer`／`surface`／`onSurface`／`onSurfaceVariant`／`outline`／`error`）與 `scaffoldBackgroundColor` 逐一填成 `DESIGN.md` §1.1 表格值，**不留任何角色給 M3 baseline**。

**Dark 主題色值衝突決議**：`outline`（`DESIGN.md` `#2c2c34`）與 `surfaceContainerHighest`（`DESIGN.md` `#19191d`）**採用 `DESIGN.md` 值**，不維持現行真機實測值（`#86868F`／`#3C3C44`）——選擇配色系統一致性優先。既有測試斷言的感知亮度差門檻（`> 0.15`／`> 0.10`）在新色值下會直接失敗，這是預期中的行為改變，不是回歸：**可辨識度風險改由「元件層級邊框補強」機制承接，不再依賴 `outline`／`surfaceContainerHighest` 本身的顏色對比**（見下一段）。

### 電子紙可辨識度補強機制（取代舊有 outline/surfaceContainerHighest 對比手法）

**【審查修正】** 原提案只覆寫 `SwitchThemeData` 的 track，遺漏了 M3 `Switch` OFF 狀態預設也會吃 `outline`（`thumbColor`）與 `surfaceContainerHighest`（`trackColor`）的事實——三個插槽（`thumbColor`／`trackColor`／`trackOutlineColor`）在 M3 預設下全部指向這次被判定有風險的兩個角色，只補一個等於沒補到。訂正為：

新增一份明確的 `SwitchThemeData`，**`thumbColor`／`trackColor`／`trackOutlineColor` 三個插槽全部改參照 `colorScheme.onSurface`**（用 `WidgetStateProperty.resolveWith` 依 OFF/ON 狀態調整透明度以維持三者之間仍可互相區分，例如 thumb 用滿不透明、track 用 onSurface 的低透明度填色、trackOutline 用滿不透明），不是 `outline` 或 `surfaceContainerHighest`。理由：`onSurface`／`surface` 是整個色彩系統裡唯一被「文字可讀性」這個基本需求保證高對比的一組角色（`DESIGN.md` §2.2「CJK 安全行高」等排版原則本身就預設 `onSurface` 對 `surface` 一定夠清楚），比 `outline`／`surfaceContainerHighest` 這種原本設計給分隔線／裝飾用的角色更適合扛「使用者必須看得見」的責任。三主題下 `onSurface` 對 `surface` 的對比皆遠高於原本 `outline` 的門檵（Dark：`#f2efe6` 對 `#1d1d22`）。

**【審查修正】同一個風險色，本 Epic 範圍內至少還有一處直接命中**：`nav_zone_settings_screen.dart`（九宮格導覽熱區設定畫面）有 3 處直接讀取 `Theme.of(context).dividerColor` 畫熱區格線／範本卡片邊框（見下方「寫死顏色遷移」清單，此檔案本來就在範圍內）。這個 Epic 決議移除各 `_build*Theme()` 顯式設定的 `dividerColor`（見「移除項目」一節），移除後 `dividerColor` 會退回 Flutter 預設、解析到 `colorScheme.outline`——跟 Dark 主題衝突色值同一個。修法：這 3 處呼叫點**直接改讀 `colorScheme.onSurface`**（不透過 `dividerColor` 這個間接屬性），不是額外開一份元件層級主題覆寫——因為這是應用程式碼直接呼叫 `Theme.of(context)`，不是吃 Material 元件預設值，直接在呼叫端换掉引用來源即可。

這兩處補強手法**都需要下一輪真機驗證確認**（比照 `epic-18`／`epic-25` 慣例）；若真機上仍不可辨識，回頭討論退回維持實測值的方案，不在本 Epic 自動假設一定成功。**其餘檔案若在 Issue 規劃/實作階段發現有類似直接依賴 `outline`／`surfaceContainerHighest`／`dividerColor` 做關鍵可辨識度用途的情形，比照同一手法（改參照 `onSurface`），不要假設只有這兩處。**

### 【審查新增】`MaterialApp` 零時長主題轉場

`main.dart` 目前建構 `MaterialApp` 時**沒有**設定 `themeAnimationDuration`，Flutter 預設值是 200ms 交叉淡出——切換主題或 E-Ink 開關時，`ElinkTokens.lerp()` 會被呼叫、畫面會有一段插值動畫，跟 `DESIGN.md` §18「零動畫轉場：所有畫面切換...一律套用零時長」的規定不符，且淡出動畫在電子紙上比瞬間切換更容易產生殘影，恰好違反 E-Ink 模式想解決的問題本身。修法：`MaterialApp` 建構時明確加上 `themeAnimationDuration: Duration.zero`。`ElinkTokens.lerp()` 原本設計的「bool 欄位離散跳變、Color 欄位插值」邏輯保留（`ThemeExtension.lerp` 介面要求必須實作），但因為動畫時長歸零，實際上不會有跑到一半的中間態畫面。

### E-Ink 主題既有客製保留

`_buildEinkTheme()` 的 `splashFactory: NoSplash.splashFactory`／`hoverColor: Colors.transparent`／`highlightColor: Colors.transparent` 三行原樣保留，不受本次重構影響。

### 移除項目（YAGNI／M3 遺留清理）

- `secondary`／`onSecondary`：全專案無任何 `colorScheme.secondary` 引用（已 grep 確認），直接移除，回退 M3 預設，不補進 `DESIGN.md`。
- `cardColor`／`dividerColor`：四個 `_build*Theme()` 直接設定的 Material 2 遺留屬性，一併移除，讓 `Card`／`Divider` 走 M3 預設（吃 `ColorScheme.surface`／`outline`）。**需要在 Issue 實作時用 widget test 確認移除後 `Card`／`Divider` 解析出來的顏色仍符合預期**（M3 預設行為需驗證，不能假設一定跟移除前視覺一致）。

### 既有語意色遷移到 `ElinkTokens`

**【審查修正】** 原提案「遷移為 `ElinkTokens.highlightYellow`／`highlightBlue`」過於簡略，忽略了現行架構的結構性限制：`HighlightStyle` 列舉的 `fixedTint` 是**編譯期常數**（`const Color?`），而 `ElinkTokens` 的值只有**執行期**透過 `Theme.of(context)` 才能拿到——列舉欄位不可能直接放一個執行期才知道的顏色，不是把常數名稱換掉這麼簡單。訂正為具體方案：

- `HighlightStyle` 列舉**拿掉 `fixedTint` 欄位**（連同 `highlighterYellowTint`／`highlighterPinkTint`／`highlighterBlueTint` 三個頂層常數一併移除，不再需要編譯期色票）。列舉本身只保留純粹的樣式識別（`highlighterYellow`／`highlighterPink`／`highlighterBlue`／`underline`）。**列舉成員名稱維持 `highlighterPink` 不改名**——即使它視覺上要換成綠色，改名會讓 `Enum.values.byName()` 持久化的既有使用者資料（劃線樣式）反序列化失敗；「這個樣式渲染出來是什麼顏色」跟「這個樣式的識別字串是什麼」是兩件事，不需要同步改。
- `highlightStyleTint()` 改名為 `highlightStyleColor()`，簽章改為 `Color highlightStyleColor(HighlightStyle style, {required ElinkTokens tokens})`——**拿掉 `primaryColor` 參數**（見下一點的 `underlineColor` 修正，四種樣式現在全部能單純從 `tokens` 解出來，不再需要外部傳入 `primaryColor` 這個旁路）。函式內容改為對四個樣式各自回傳 `tokens.highlightYellow`／`tokens.highlightGreen`（`highlighterPink` 對應綠色，語意變更，`DESIGN.md` 既有決策，非本 spec 新增）／`tokens.highlightBlue`／`tokens.underlineColor`。
- **【審查修正】`ElinkTokens.underlineColor` 原本定義了卻沒被用到**（底線色實際上是呼叫端傳入的 `primaryColor`，兩者數值目前巧合相等但屬孤兒欄位、架構上是錯的）。上一點的簽章修正已一併解決：`underline` 樣式現在直接回傳 `tokens.underlineColor`，不再依賴 `primaryColor` 這個旁路參數。
- 呼叫端（`reader_screen.dart:1733,1826`、`notes_bottom_sheet.dart:441`）需要同步改為傳 `tokens`（從 `Theme.of(context).extension<ElinkTokens>()!` 取得）而非 `primaryColor`，函式名稱也要同步改。

### 寫死顏色遷移（13 個檔案，含新納入的 `txt_cover_generator.dart`）

- `notes_bottom_sheet.dart`／`library_group_management_dialog.dart`：`Colors.red` → `colorScheme.error`。
- `pdf_crop_frame_overlay.dart`：`Colors.black`／`Colors.white`／自訂綠色等，遷移至對應 `ColorScheme`／`ElinkTokens` 角色（逐一對應表留給 Issue 規劃時依實際用途決定，此 spec 只定調「不得再寫死字面色值」這個總原則）。
- `book_cover.dart`／`foliate_reader_view.dart`／`pdf_reader_view.dart`／`layout_preset_book_picker_screen.dart`／`library_screen.dart`／`nav_zone_settings_screen.dart`／`reader_screen.dart`／`settings_screen.dart`：同上，個別 `Colors.grey`／`black45`／`white70` 依用途對應 `onSurfaceVariant`／`outline`／`badgeScrim` 等角色，逐一對應表留給 Issue 規劃。
- **`txt_cover_generator.dart`（新納入）**：`generateTxtCover()` 簽章加一個 `isEinkMode`（或直接傳入 `ElinkTokens`）參數。`isEinkMode == true` 時，不使用 6 色色盤，改用單一白底＋黑色邊框樣式（對應 `ElinkTokens.coverPlaceholder`／`outline`），跟 `DESIGN.md` §8.2 封面佔位符在 E-Ink 模式下的規格一致。**【審查修正】書名首字文字色也要跟著改**：現行文字色是寫死白色（`ui.Color(0xFFFFFFFF)`，配合原本的彩色背景），E-Ink 分支若只換背景／外框、不換文字色，會變成白底配白字、書名首字完全看不見——`isEinkMode == true` 時文字色須改為黑色（對應 `ElinkTokens.onSurface`／E-Ink 純黑）。`isEinkMode == false` 時維持既有 6 色依書名雜湊輪替＋白字的行為完全不變。**重要限制**：封面 PNG 是匯入當下產生一次並存成本機檔案（既有架構，本 Epic 不改），之後使用者切換主題／E-Ink 開關**不會**讓已產生的封面重新繪製——只有這次修改合併後、且匯入當下 E-Ink 模式為開的新匯入 TXT 書，才會拿到白底黑框黑字封面；已存在的書封面維持原樣，除非使用者重新匯入。

### `settings_screen.dart` E-Ink 鎖定視覺與主題預覽色

`_buildThemeDot()` 的 `Opacity(0.4)` 改為 `DESIGN.md` §17.2 指定的邊框加粗虛線手法（`3dp` 虛線邊框，比照 §7.2 E-Ink 按壓反饋語彙），`onTap: null` 鎖住邏輯不變。

**【審查新增】** 這三顆主題預覽圓點目前各自寫死一組獨立的示意色（跟 `_build*Theme()` 實際色值是兩份不同的資料），本 Epic 換色後這組獨立示意色會跟正式色表產生落差。遷移時一併改為直接讀取 `resolveThemeData()` 各主題回傳的實際 `scaffoldBackgroundColor`／`primary`（不要維持自己另一份寫死近似值），確保「預覽長什麼樣」跟「選了之後實際長什麼樣」一致。

## Testing Decisions

- **測試縫（seam）沿用既有的、唯一的一個**：`resolveThemeData({theme, isEinkMode}) -> ThemeData`。所有新測試都透過這個公開函式的回傳值斷言（`ThemeData.colorScheme.*`／`ThemeData.extension<ElinkTokens>()`），不直接測試私有的 `_build*Theme()` 函式，比照 `test/theme/app_theme_data_test.dart` 既有慣例。
- 既有 `outline`／`surfaceContainerHighest` 感知亮度差門檻斷言（`> 0.15`／`> 0.10`）**移除**——新色值下必然失敗，且新設計不再靠這兩個角色的顏色對比保證可辨識度。**【審查修正】** 新增斷言範圍擴大為：`ThemeData.switchTheme` 的 `thumbColor`／`trackColor`／`trackOutlineColor` 三個插槽（各狀態下）皆解析自 `colorScheme.onSurface`（不是單一 track 屬性），以及 `nav_zone_settings_screen.dart` 的 3 處熱區／範本卡片邊框顏色確實讀取 `colorScheme.onSurface`（widget test，不是硬編一個期望的 hex 值，是斷言「來源角色」正確，避免色票微調又要改一次測試期望值）。
- 新增 `ElinkTokens` 單元測試：`copyWith` 逐欄位驗證、`lerp` 的 bool 欄位離散切換行為、四種 `theme`×`isEinkMode` 組合透過 `resolveThemeData()` 拿到的 `ElinkTokens` 值正確。
- 【審查新增】新增 `highlightStyleColor()` 單元測試：四個 `HighlightStyle` 各自對應正確的 `ElinkTokens` 欄位（`highlighterPink` → `tokens.highlightGreen`），確認函式簽章不再需要 `primaryColor` 參數；既有測試中依賴舊 `highlightStyleTint()`／`primaryColor` 參數的斷言需同步更新為新簽章。
- 【審查新增】新增 widget test 確認 `MaterialApp` 的 `themeAnimationDuration` 為 `Duration.zero`。
- 13 個檔案的顏色遷移：只要求「既有測試套件維持通過」，不強制新增視覺回歸測試（這個專案目前沒有 golden test 基礎設施，不在本 Epic 引入）。若某檔案目前完全沒有色彩相關測試覆蓋，不強制新增，維持現有測試密度水準即可。
- `cardColor`／`dividerColor` 移除後，需要至少一則 widget test 確認 `Card`／`Divider` 在 M3 預設下解析出的顏色符合預期（不能只靠移除當下沒有編譯錯誤就當作驗證完成）。**【審查新增】** `app_theme_data_test.dart` 現有「`dividerColor` 與 `outline` 同值」的既有測試（第 81-86 行左右）在移除顯式 `dividerColor` 覆寫後**仍會通過**（因為 M3 預設也會讓兩者同值），不是這次要修的失敗測試——實作時不要誤判成需要跟著改動，維持原樣即可。
- `txt_cover_generator.dart` 的 E-Ink 分支：新增單元測試驗證 `isEinkMode: true` 時輸出的 PNG 背景為白、有黑框**、書名首字文字色為黑**（可用像素採樣斷言四角/邊緣/文字區域顏色，比照既有專案內類似的像素級測試手法）；`isEinkMode: false` 時既有的彩色輪替行為需有回歸測試確認未受影響。

## Out of Scope

- Chrome／Page 個別分開的主題選擇器（`DESIGN.md` §17.2 已定案只做單一選擇器，UI 層級的雙選擇器不在任何一個 Epic 範圍內）。
- 閱讀器 Chrome／TTS UI 重構（屬於 `DESIGN.md` §12／§13，多輪 grilling 已決定維持現狀，不在 `epic-35` 或 `epic-36`）。
- 本次盤點的 13 個檔案以外，未來才發現的其他寫死顏色（屬於個案技術債，另開 Issue）。
- 已產生的 TXT 封面 PNG 不會回頭重新產生（見上方 Implementation Decisions 的限制說明）。
- OPDS／WebDAV／雲端來源實作、書籍儲存、閱讀進度持久化等 `UI_DESIGN_RULES.md` 明文禁止本輪碰的核心架構——本 Epic 完全不涉及。

## Further Notes

- Dark 主題 `outline`／`surfaceContainerHighest` 改用 `DESIGN.md` 值＋`onSuface` 邊框補強，是這次 Architecting 階段的決議，但**風險沒有消除、只是換了個地方**——下一輪真機驗證（比照 `epic-18`／`epic-25` 慣例）沒過的話，需要回頭重新討論，不能假設這個提案一定成功。
- `highlight_style.dart` 的粉紅→綠色若日後有人質疑，指向 `DESIGN.md` §1.2 即可，不是本 Epic 或本 spec 的新決策。
- Scrum Master 階段拆 `issues.md` 時，建議切法：Issue 1（`ElinkTokens` 類別＋單元測試＋`MaterialApp` `themeAnimationDuration: Duration.zero`）、Issue 2（四套 `ColorScheme`／`scaffoldBackgroundColor` 對齊＋`secondary`/`cardColor`/`dividerColor` 清理＋`SwitchThemeData`〔thumbColor/trackColor/trackOutlineColor 三插槽〕補強＋既有測試更新）、Issue 3（`settings_screen.dart` 鎖定視覺改邊框虛線＋主題預覽色改讀真實色值）、Issue 4（`highlight_style.dart` 遷移，含 `HighlightStyle` 列舉拿掉 `fixedTint`、`highlightStyleColor()` 新簽章、三處呼叫端更新）、Issue 5（`nav_zone_settings_screen.dart`——因為它同時是「一般寫死顏色遷移」也是「Dark 可辨識度補強」的一部分，建議獨立一張 Issue、跟 Issue 2 的 Switch 補強互相參照）、Issue 6～N（其餘檔案分組遷移，`txt_cover_generator.dart` 因為有明確的新行為與新測試，建議獨立一張 Issue 不跟其他純遷移檔案混在一起）。
