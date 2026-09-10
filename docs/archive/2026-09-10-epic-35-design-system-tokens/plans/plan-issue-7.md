# Epic 35 — Issue 7：閱讀器相關寫死顏色遷移（`foliate_reader_view.dart`／`pdf_reader_view.dart`／`pdf_crop_frame_overlay.dart`／`reader_option_tile.dart` 及其呼叫端） Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 `foliate_reader_view.dart`／`pdf_reader_view.dart` 內的寫死顏色殘留改讀 `ColorScheme`／`ElinkTokens` 角色，讓換主題／開啟 E-Ink 模式時能正確跟著換：(1) 兩個檔案共有的 3×3 導覽熱區除錯疊層（`showNavZoneDebugOverlay` 分支）的 `Colors.white24`（格線邊框）／`Colors.white70`（動作文字）改讀 `colorScheme.onSurface`；(2) `pdf_reader_view.dart` 額外 3 處先前計劃草案曾主張排除、經獨立審查（`reviews/review-plan-issue-7.md` C1）與人類決策者確認後改為一併遷移的用法——框選拖曳預覽框（`_buildDragIndicator()`）、備註徽章圖釘（`_buildDecorationWidget()`）、搜尋結果高亮（`_buildSearchHighlightWidget()`）。`pdf_crop_frame_overlay.dart`、`reader_option_tile.dart` 及其三個呼叫端依 `issues.md` Issue 7 明文排除，維持現狀不動，這兩項排除已經獨立審查核實有規格文件明文授權，不受上述修正影響。

**Architecture:** 逐檔案掃描（見下方「範圍決定」）確認 `foliate_reader_view.dart`／`pdf_reader_view.dart` 內所有寫死顏色用法，共分 3 個 Task：Task 1／Task 2 處理兩個檔案共有的除錯疊層（結構相同、彼此獨立、互不重疊，各自一個 Task），Task 3 處理 `pdf_reader_view.dart` 額外 3 處（獨立於 Task 1／2，可在其後任意時間執行）。**Task 3 的顏色角色選擇有一個關鍵限制**：逐一核對 `app/lib/theme/app_theme_data.dart` 全檔後確認 `ColorScheme.tertiary`／`secondary` 在四套 `_build*Theme()` 皆未被明確設定（`grep -n "tertiary\|secondary" app_theme_data.dart` 零命中）——這代表這兩個角色會落回 Flutter Material 3 `ColorScheme.fromSeed()` 的預設種子色，正是本 Epic（Issue 2）存在的理由所要清除的「淡紫外洩」同一種 bug，Task 3 因此**不使用** `tertiary`／`secondary`，只從已確認全部四套主題明確賦值的角色中選（`primary`／`onPrimary`／`primaryContainer`／`onPrimaryContainer`／`surface`／`onSurface`／`onSurfaceVariant`／`outline`／`surfaceContainerHighest`／`error`，以及 `ElinkTokens` 8 個 `Color` 欄位），不新增任何 `ElinkTokens` 欄位（Issue 1 已定案凍結）。三個 Task 都採「先寫失敗測試斷言新顏色來源、確認真的紅燈、再改實作、確認轉綠燈」的標準 TDD 順序。`FoliateReaderView`／`PdfReaderView` 兩者的公開建構參數全程不變。

**Tech Stack:** Flutter／Dart，`flutter_test`（`testWidgets`），既有 `ColorScheme.onSurface`（`resolveThemeData()`，Issue 2 已完成）；不新增任何 pub 套件依賴、不新增 `ElinkTokens` 欄位。

**Spec:** `docs/epics/epic-35-design-system-tokens/spec.md`（§「寫死顏色遷移」）；工單摘要見 `docs/epics/epic-35-design-system-tokens/issues.md` Issue 7。

## 範圍決定（已與人類確認，非本計劃自行認定）

本計劃第一版曾主張「`pdf_reader_view.dart` 的框選拖曳預覽框／備註徽章圖釘／搜尋結果高亮 3 處，跟 `pdf_crop_frame_overlay.dart` 同一類理由（疊加在不可預期的 PDF 頁面內容之上），刻意不遷移」，但 `issues.md` Issue 7 的「Solution」段落只逐字點名兩項排除（`pdf_crop_frame_overlay.dart` 全檔、`reader_option_tile.dart` 及其呼叫端），沒有提及這 3 處；「驗收標準」寫的是「`foliate_reader_view.dart`／`pdf_reader_view.dart` 內無寫死顏色殘留」，沒有但書。經 `/superpowers:requesting-code-review` 獨立審查（`reviews/review-plan-issue-7.md` Critical C1）指出這個排除是計劃作者自行類比推論、沒有 `issues.md` 事先授權（不同於 `pdf_crop_frame_overlay.dart`／`reader_option_tile.dart` 這兩項是規格文件本身逐字寫出的排除），與本 Epic Issue 5 曾被打回的失敗模式相同，且審查者指出 `ElinkTokens` 已有 `highlightYellow`／`highlightGreen` 等角色正是為「疊加在不可預期頁面內容之上的標記」情境設計，`_buildDecorationWidget()` 自己也已用執行期取值（非寫死）畫使用者劃線，證明「疊加在頁面內容之上」在這個檔案裡不等於「必須維持寫死色值」。提請人類決策者確認後，**改為一併遷移**，技術設計見下方與 Task 3。逐行核對兩個檔案全文（`grep -n "Colors\.\|Color(0x\|withOpacity"`）確認以下清單是窮盡的（獨立審查已核實過同一份清單無遺漏）：

- **一併遷移（本計劃執行）**：
  - `foliate_reader_view.dart:971,978`／`pdf_reader_view.dart:1010,1017`——3×3 導覽熱區除錯疊層（`showNavZoneDebugOverlay` 開關，`nav_zone_settings_screen.dart` 有對應的「顯示熱區輔助線」開關可切換，見 `app/lib/screens/nav_zone_settings_screen.dart:196-200`）的格線邊框 `Colors.white24` 與動作文字 `Colors.white70`。改讀 `colorScheme.onSurface`（依透明度 0.24／0.7 區分邊框／文字）：這組除錯疊層畫的是 `nav_zone_settings_screen.dart`（Issue 5，已合併）「自訂編輯器 9 格格線」同一個「3×3 熱區」概念的*即時預覽版*，Issue 5 已把該畫面的格線邊框從 `dividerColor` 改為 `colorScheme.onSurface`（理由：Dark 主題 `outline` 改採 `DESIGN.md` 值後跟 `surface` 亮度差縮小，電子紙上可能難以辨識）——本工單延用同一個角色來源，讓「設定畫面預覽格線」與「閱讀器內即時疊層格線」兩處視覺語彙一致。見 Task 1／Task 2。
  - `pdf_reader_view.dart:1053-1054`（`_buildDragIndicator()`，框選拖曳中的即時預覽框）、`:1093`（`_buildDecorationWidget()`，備註徽章圖釘）、`:1128,1130`（`_buildSearchHighlightWidget()`，搜尋符合結果高亮）——技術設計見 Task 3，色彩角色選擇說明如下：
    - `colorScheme.tertiary`／`secondary` **不可用**：逐行核對 `app/lib/theme/app_theme_data.dart` 全檔，四套 `_build*Theme()` 均未明確設定這兩個角色（`grep` 零命中），代表會落回 M3 `ColorScheme.fromSeed()` 的預設種子色——正是本 Epic（Issue 2）存在的理由所要清除的「淡紫外洩」同一種 bug，此處不可重蹈覆轍。
    - `_buildDragIndicator()`（拖曳框選進行中，使用者尚未選定要建立的標記顏色）：填色改 `colorScheme.primary.withValues(alpha: 0.3)`、邊框改 `colorScheme.primary`（實色，寬度不變）——`primary` 是這個 App 既有的「操作中／選取中」狀態語彙（`reader_option_tile.dart` 選中狀態邊框已用 `colorScheme.primary`），拖曳階段尚未決定劃線顏色，用 `primary` 表達「操作進行中」比預先假設某個劃線色更準確，且四套主題皆明確賦值，不會落回 M3 預設。
    - `_buildDecorationWidget()` 備註徽章圖釘（`Icons.push_pin`，疊加在使用者自選劃線 tint 色塊右上角）：改讀 `colorScheme.onSurface`。**已知殘留限制（非本工單新增回歸，記錄供後續追蹤）：** E-Ink 主題下 `onSurface` 與 `highlightYellow`／`highlightGreen`／`highlightBlue`（皆為 `Color(0xFF000000)` 純黑，見 `app_theme_data.dart:266-268` 註解「無背景改用下劃線/外框/點虛線」的色票值決議）疊在一起會同為純黑、圖釘不可辨識——但這個限制在改動前就已存在（原本寫死的 `Colors.black87` 疊在同樣是純黑 tint 的 E-Ink 標記上同樣不可辨識，不是本工單造成的新回歸），E-Ink 模式下「不畫底色改畫線條」的正確渲染邏輯 `app_theme_data.dart:264` 已明文記錄「屬其他 Issue 範圍」，本工單不在此展開修復。
    - `_buildSearchHighlightWidget()`（搜尋符合結果高亮，`isCurrent`／非 `isCurrent` 兩種狀態）：非目前符合結果的填色改 `tokens.highlightYellow.withValues(alpha: 0.4)`；目前符合結果的填色改 `tokens.highlightGreen.withValues(alpha: 0.4)`（沿用既有「劃線」語意色角色，搜尋高亮概念上就是「標示出文字位置」，跟劃線是同一件事的不同觸發來源）；目前符合結果的外框改 `colorScheme.primary`（維持「外框存在與否」而非「色相差異」作為可辨識度依據——這正是原程式碼 L1100-1105 註解記錄的既有設計原則：「純粹用半透明橙色／黃色區分在 E-Ink 灰階顯示或高對比主題下辨識度不足，外框在灰階轉換後仍能維持明顯的邊界對比，不依賴色相差異」，本工單延續同一個原則，只是把色彩角色的具體來源從寫死字面值換成主題角色，不改變這個設計本身）。需要在 `pdf_reader_view.dart` 新增 `import '../theme/elink_tokens.dart';`（其他 `app/lib/reader/` 檔案皆用同一相對路徑，見 `highlight_style.dart:3`）。
- **維持字面值，不遷移（有具體技術理由，非偷懶，`issues.md` Issue 7 已明文授權）**：
  - `pdf_crop_frame_overlay.dart` 全檔（遮罩 `Colors.black.withValues(alpha:0.5)`、裁切框 `Colors.white`／`Colors.black`、確認/取消按鈕 `Colors.white`）——`issues.md` Issue 7 Solution 第 2 點已明文排除，理由是疊加在任意 PDF 頁面內容之上的覆蓋層 UI，頁面內容本身顏色不可預期，覆蓋層必須維持與主題無關的高對比。獨立審查已核實這個排除確有規格文件明文授權，本計劃不重新檢視。
  - `reader_option_tile.dart`（`app/lib/screens/widgets/reader_option_tile.dart`）及其三個呼叫端 `reader_settings_sheet.dart`／`pdf_settings_sheet.dart`／`fxl_settings_sheet.dart`——`issues.md` Issue 7 Solution 第 3 點與「驗收標準」皆明文「用法本身正確（引用 `ColorScheme` 角色）...不算寫死顏色、不需要改寫法」「`reader_option_tile.dart` 用法確認無需修改」。獨立審查已核實這個排除確有規格文件明文授權。本計劃不改動這個檔案，僅在下方「全部 Task 完成後」保留一項人工目視確認待辦（Dark 主題下 `theme.colorScheme.outline.withValues(alpha: 0.35)` 選項邊框是否仍可辨識），呼應 Issue 2／Issue 6 已記錄的同一組殘留風險。

若人類審查者認為上述任一判斷不成立，請在對應 Task 執行前先提出，比照 Issue 5 的處理方式修正本計劃再繼續。

## Global Constraints

- 依賴 Issue 2 已完成：四套 `ColorScheme` 已對齊 `DESIGN.md` §1.1、`resolveThemeData()` 已能正確解析 `colorScheme.onSurface`／`colorScheme.primary` 等角色，本工單直接引用這個既成事實，不重新定義任何色值。
- 本工單只碰 `app/lib/reader/foliate_reader_view.dart`、`app/lib/reader/pdf_reader_view.dart` 及其對應測試檔（`app/test/reader/foliate_reader_view_test.dart`、`app/test/reader/pdf_reader_view_nav_zone_test.dart`、`app/test/reader/pdf_reader_view_selection_test.dart`、`app/test/reader/pdf_reader_view_search_test.dart`），不碰 `pdf_crop_frame_overlay.dart`／`reader_option_tile.dart`／其三個呼叫端／其他任何畫面檔案；不碰 OPDS／WebDAV／雲端來源實作／書籍儲存／閱讀進度持久化。
- 不影響 business logic：`FoliateReaderView`／`PdfReaderView` 的公開建構參數、`TapZoneDetector` 熱區判定邏輯、`onZoneAction` 回呼契約、框選拖曳／備註徽章／搜尋高亮的觸發條件與資料流完全不變，純粹是這些既有視覺元素的顏色來源調整。
- `ElinkTokens` 欄位維持 Issue 1 定案的 11 個欄位不變，本工單不新增／不修改任何欄位。Task 3 重用既有的 `highlightYellow`／`highlightGreen` 欄位，不新增欄位。
- **顏色角色白名單（Task 3 適用，見上方「範圍決定」）**：只能從 `colorScheme.primary`／`onPrimary`／`primaryContainer`／`onPrimaryContainer`／`surface`／`onSurface`／`onSurfaceVariant`／`outline`／`surfaceContainerHighest`／`error`，以及 `ElinkTokens` 的 8 個 `Color` 欄位中選——`colorScheme.tertiary`／`secondary` 兩個角色四套主題皆未明確賦值，會落回 M3 預設種子色，不可使用。
- 所有 Dart 原始碼註解使用正體中文。
- 每個 Task 完成後只跑該 Task 涉及檔案的測試（見各 Task「驗證」欄），不需要整套 `flutter test`；最後一個 Task 完成時才跑一次完整 `flutter test`（見 `CLAUDE.md`「測試執行範圍」）。
- 每個 Task 的 Step 完成後，把本檔案對應的 `- [ ]` 改成 `- [x]`。
- 提交前 `flutter analyze` 須維持「No issues found!」（最後一個 Task 統一驗證）。
- 計劃書內「改後」程式碼片段的換行/縮排以人工排版呈現，實際落地時以 `dart format` 自動排版結果為準，不需要逐字比對縮排。
- 所有指令皆在 `app/` 目錄下執行。

## 動手改程式碼前的四點說明（`UI_DESIGN_RULES.md` 要求）

1. **改哪個 UI 元件**：`FoliateReaderView`（`app/lib/reader/foliate_reader_view.dart`）與 `PdfReaderView`（`app/lib/reader/pdf_reader_view.dart`）共有的 3×3 導覽熱區除錯疊層（`showNavZoneDebugOverlay` 開關，由 `nav_zone_settings_screen.dart` 的「顯示熱區輔助線」開關控制，`false` 時不渲染，Task 1／Task 2）；以及 `PdfReaderView` 額外三個既有視覺元素（Task 3）：框選拖曳預覽框（長按拖曳建立劃線/備註時的即時回饋）、備註徽章圖釘（`isNoteOnly` 標記右上角的圖釘小圖示）、搜尋結果高亮（全文搜尋符合結果的疊加色塊）。全部是既有畫面既有元件的顏色來源調整，不是新畫面、不新增元件。
2. **為什麼要改**：這兩個檔案是 `epic-35-design-system-tokens/spec.md`「寫死顏色遷移」清單成員；除錯疊層、框選拖曳框、備註徽章、搜尋高亮目前皆寫死顏色字面值（`Colors.white24`／`white70`／`yellow`／`orange`／`black87`／`deepOrange`），換主題／開啟 E-Ink 模式時不會跟著換。改用 `colorScheme.onSurface`／`primary` 後與 `nav_zone_settings_screen.dart`（Issue 5，同一組 3×3 熱區概念的設定畫面預覽格線）、`reader_option_tile.dart`（選中狀態邊框既有慣例）採用同一組顏色來源，視覺語彙一致；搜尋高亮改用既有 `ElinkTokens.highlightYellow`／`highlightGreen`，語意上跟「標示文字位置」的既定用途一致。
3. **哪些畫面依賴它**：`FoliateReaderView` 被 `ReaderScreen` 用於 EPUB／KF8／CBZ／TXT／MD 所有 Foliate 格式；`PdfReaderView` 被 `ReaderScreen` 用於 PDF 格式。除錯疊層只在使用者於「九宮格導覽」設定畫面手動開啟「顯示熱區輔助線」後才會渲染，預設關閉；框選拖曳框／備註徽章／搜尋高亮則是 PDF 閱讀時劃線／備註／全文搜尋既有功能的一部分，一般讀者使用這些功能時都會看到。
4. **是否影響 business logic**：不影響。純視覺顏色來源調整；`TapZoneDetector` 熱區點擊判定、`onZoneAction` 回呼、`navZoneActions` 陣列語意、框選拖曳手勢判定、備註/劃線資料模型（`PdfAnnotationDecoration`）、搜尋比對邏輯（`PdfReaderView.search()`／`setSearchHighlights()`）等既有邏輯完全不變。

---

### Task 1：`foliate_reader_view.dart` 除錯疊層改讀 `colorScheme.onSurface`

**Files:**
- Modify: `app/lib/reader/foliate_reader_view.dart`（`build()` 方法開頭，原 L874-880；3×3 熱區除錯疊層 `Container`，原 L968-981）
- Test: `app/test/reader/foliate_reader_view_test.dart`（`group('3×3 導航熱區（InAppWebView）')`）

**Interfaces:**
- Consumes: 既有 Flutter SDK `ThemeData`／`ColorScheme` API（`Theme.of(context).colorScheme.onSurface`），`resolveThemeData()` 產出的四套主題皆已提供這個角色（Issue 2 已完成）。
- Produces: 無新介面——不新增／不變更任何函式簽章或公開建構參數。

- [x] **Step 1: 寫失敗的測試——新增一則斷言除錯疊層格線／文字改讀 `colorScheme.onSurface`**

在 `app/test/reader/foliate_reader_view_test.dart` 的 `group('3×3 導航熱區（InAppWebView）', () { ... })` 內，緊接在既有測試 `'showNavZoneDebugOverlay=true 時，格子顯示對應動作文字標籤'`（原 L763-788）之後，新增：

```dart
    testWidgets(
        'showNavZoneDebugOverlay=true 時，格線與文字改讀 colorScheme.onSurface（'
        'epic-35-design-system-tokens Issue 7：取代原本寫死的 Colors.white24／'
        'white70——這兩個字面值跟主題無關，換主題／開啟 E-Ink 模式時不會跟著換）',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: FoliateReaderView(
            filePath: '/tmp/sample.epub',
            onPageRendered: _noop,
            onError: _noopError,
            navZoneActions: const [
              ZoneAction.previousPage, ZoneAction.menu, ZoneAction.nextPage,
              ZoneAction.none, ZoneAction.none, ZoneAction.none,
              ZoneAction.none, ZoneAction.none, ZoneAction.none,
            ],
            showNavZoneDebugOverlay: true,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      final context =
          tester.element(find.byKey(const Key('nav_zone_1')));
      final onSurfaceColor = Theme.of(context).colorScheme.onSurface;

      final cell = tester.widget<Container>(
        find.descendant(
          of: find.byKey(const Key('nav_zone_1')),
          matching: find.byType(Container),
        ),
      );
      final border = (cell.decoration as BoxDecoration).border as Border;
      expect(border.top.color, onSurfaceColor.withValues(alpha: 0.24));

      final label = tester.widget<Text>(find.text('選單'));
      expect(label.style?.color, onSurfaceColor.withValues(alpha: 0.7));
    });
```

- [x] **Step 2: 執行測試，確認失敗**

Run（於 `app/` 目錄下）: `flutter test test/reader/foliate_reader_view_test.dart`
Expected: 新增的測試 FAIL——`border.top.color` 目前仍是 `Colors.white24`（`Color(0x40ffffff)`），跟 `onSurfaceColor.withValues(alpha: 0.24)` 不相等；`label.style?.color` 目前仍是 `Colors.white70`（`Color(0xb3ffffff)`），跟 `onSurfaceColor.withValues(alpha: 0.7)` 不相等。其餘既有測試維持 PASS。

- [x] **Step 3: 實作——除錯疊層改讀 `colorScheme.onSurface`**

在 `app/lib/reader/foliate_reader_view.dart` 的 `build()` 方法開頭（原 L874-880）：

```dart
  @override
  Widget build(BuildContext context) {
    // 快取未完成前不掛載 InAppWebView（外層 ReaderScreen 已負責視覺載入狀態）
    if (_bookCacheDir == null) {
      return const SizedBox.shrink();
    }
    return Stack(
```

改為：

```dart
  @override
  Widget build(BuildContext context) {
    // 快取未完成前不掛載 InAppWebView（外層 ReaderScreen 已負責視覺載入狀態）
    if (_bookCacheDir == null) {
      return const SizedBox.shrink();
    }
    // epic-35-design-system-tokens Issue 7：3×3 導覽熱區除錯疊層（見下方
    // showNavZoneDebugOverlay 分支）原本寫死 Colors.white24／white70，
    // 換主題／開啟 E-Ink 模式時不會跟著換；改讀 colorScheme.onSurface，
    // 呼應 nav_zone_settings_screen.dart（epic-35 Issue 5）同一組熱區格線
    // 已採用的同一個角色，維持同一功能兩處視覺語彙一致。
    final onSurfaceColor = Theme.of(context).colorScheme.onSurface;
    return Stack(
```

在 3×3 熱區除錯疊層的 `Container`（原 L968-981）：

```dart
                        child: Container(
                          decoration: widget.showNavZoneDebugOverlay
                              ? BoxDecoration(
                                  border: Border.all(color: Colors.white24))
                              : null,
                          alignment: Alignment.center,
                          child: widget.showNavZoneDebugOverlay
                              ? Text(
                                  _zoneActionLabel(action),
                                  style: const TextStyle(
                                      color: Colors.white70, fontSize: 10),
                                )
                              : null,
                        ),
```

改為：

```dart
                        child: Container(
                          decoration: widget.showNavZoneDebugOverlay
                              ? BoxDecoration(
                                  border: Border.all(
                                      color: onSurfaceColor.withValues(
                                          alpha: 0.24)))
                              : null,
                          alignment: Alignment.center,
                          child: widget.showNavZoneDebugOverlay
                              ? Text(
                                  _zoneActionLabel(action),
                                  style: TextStyle(
                                      color: onSurfaceColor.withValues(
                                          alpha: 0.7),
                                      fontSize: 10),
                                )
                              : null,
                        ),
```

（`TextStyle` 前的 `const` 一併移除——`onSurfaceColor` 是執行期才能取得的值，不再是編譯期常數。）

- [x] **Step 4: 執行測試，確認通過**

Run（於 `app/` 目錄下）: `flutter test test/reader/foliate_reader_view_test.dart`
Expected: PASS（本檔案全部測試皆過，含既有的 3×3 熱區點擊／`showNavZoneDebugOverlay` 預設不顯示文字等測試，無回歸）。

- [x] **Step 5: 執行 `flutter analyze`，確認乾淨**

Run（於 `app/` 目錄下）: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 6: Commit**

```bash
git add app/lib/reader/foliate_reader_view.dart app/test/reader/foliate_reader_view_test.dart
git commit -m "$(cat <<'EOF'
feat(epic-35): Issue 7 Task 1 — foliate_reader_view.dart 熱區除錯疊層改讀 colorScheme.onSurface

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01DDZwVcXmYjiFpmqArXeguR
EOF
)"
```

---

### Task 2：`pdf_reader_view.dart` 除錯疊層改讀 `colorScheme.onSurface`

**Files:**
- Modify: `app/lib/reader/pdf_reader_view.dart`（`build()` 方法開頭，原 L914-923；3×3 熱區除錯疊層 `Container`，原 L1007-1020）
- Test: `app/test/reader/pdf_reader_view_nav_zone_test.dart`

**Interfaces:**
- Consumes: 既有 Flutter SDK `ThemeData`／`ColorScheme` API（`Theme.of(context).colorScheme.onSurface`），`resolveThemeData()` 產出的四套主題皆已提供這個角色（Issue 2 已完成）。
- Produces: 無新介面——不新增／不變更任何函式簽章或公開建構參數。

**與 Task 1 的關係：** 完全獨立、修改不同檔案，可任意順序執行，不需要序列化。

- [x] **Step 1: 寫失敗的測試——新增一則斷言除錯疊層格線／文字改讀 `colorScheme.onSurface`**

在 `app/test/reader/pdf_reader_view_nav_zone_test.dart` 中，緊接在既有測試 `'showNavZoneDebugOverlay 為 true 時顯示動作文字標籤'`（原 L97-117）之後，新增：

```dart
  testWidgets(
      'showNavZoneDebugOverlay 為 true 時，格線與文字改讀 colorScheme.onSurface（'
      'epic-35-design-system-tokens Issue 7：取代原本寫死的 Colors.white24／'
      'white70——這兩個字面值跟主題無關，換主題／開啟 E-Ink 模式時不會跟著換）',
      (tester) async {
    var renderedCount = 0;
    final actions = List<ZoneAction>.filled(9, ZoneAction.none);
    actions[1] = ZoneAction.menu;

    await tester.pumpWidget(
      MaterialApp(
        home: PdfReaderView(
          filePath: 'test/fixtures/sample_multi_page.pdf',
          onPageRendered: () => renderedCount++,
          onError: (_) {},
          navZoneActions: actions,
          showNavZoneDebugOverlay: true,
        ),
      ),
    );
    await pumpUntilPdfReady(tester, condition: () => renderedCount != 0);
    await tester.pump();

    final context =
        tester.element(find.byKey(const Key('pdf_reader_nav_zone_1')));
    final onSurfaceColor = Theme.of(context).colorScheme.onSurface;

    final cell = tester.widget<Container>(
      find.descendant(
        of: find.byKey(const Key('pdf_reader_nav_zone_1')),
        matching: find.byType(Container),
      ),
    );
    final border = (cell.decoration as BoxDecoration).border as Border;
    expect(border.top.color, onSurfaceColor.withValues(alpha: 0.24));

    final label = tester.widget<Text>(find.text('選單'));
    expect(label.style?.color, onSurfaceColor.withValues(alpha: 0.7));
    // 等待 PdfViewer 內部 DoubleTapGestureRecognizer 的定時器過期，避免測試
    // 結束時拋出 "A Timer is still pending" 斷言（比照本檔案既有測試慣例）。
    await tester.pump(const Duration(milliseconds: 400));
  });
```

- [x] **Step 2: 執行測試，確認失敗**

Run（於 `app/` 目錄下）: `flutter test test/reader/pdf_reader_view_nav_zone_test.dart`
Expected: 新增的測試 FAIL——`border.top.color` 目前仍是 `Colors.white24`（`Color(0x40ffffff)`），跟 `onSurfaceColor.withValues(alpha: 0.24)` 不相等；`label.style?.color` 目前仍是 `Colors.white70`（`Color(0xb3ffffff)`），跟 `onSurfaceColor.withValues(alpha: 0.7)` 不相等。其餘既有測試維持 PASS。

- [x] **Step 3: 實作——除錯疊層改讀 `colorScheme.onSurface`**

在 `app/lib/reader/pdf_reader_view.dart` 的 `build()` 方法開頭（原 L914-923）：

```dart
  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return const SizedBox.shrink();
    }
    final document = _document;
    if (document == null) {
      return const SizedBox.shrink();
    }
    final viewer = PdfViewer(
```

改為：

```dart
  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return const SizedBox.shrink();
    }
    final document = _document;
    if (document == null) {
      return const SizedBox.shrink();
    }
    // epic-35-design-system-tokens Issue 7：3×3 導覽熱區除錯疊層（見下方
    // showNavZoneDebugOverlay 分支）原本寫死 Colors.white24／white70，
    // 換主題／開啟 E-Ink 模式時不會跟著換；改讀 colorScheme.onSurface，
    // 呼應 nav_zone_settings_screen.dart（epic-35 Issue 5）同一組熱區格線
    // 已採用的同一個角色，維持同一功能兩處視覺語彙一致。
    final onSurfaceColor = Theme.of(context).colorScheme.onSurface;
    final viewer = PdfViewer(
```

在 3×3 熱區除錯疊層的 `Container`（原 L1007-1020）：

```dart
                        child: Container(
                          decoration: widget.showNavZoneDebugOverlay
                              ? BoxDecoration(
                                  border: Border.all(color: Colors.white24))
                              : null,
                          alignment: Alignment.center,
                          child: widget.showNavZoneDebugOverlay
                              ? Text(
                                  _pdfZoneActionLabel(action),
                                  style: const TextStyle(
                                      color: Colors.white70, fontSize: 10),
                                )
                              : null,
                        ),
```

改為：

```dart
                        child: Container(
                          decoration: widget.showNavZoneDebugOverlay
                              ? BoxDecoration(
                                  border: Border.all(
                                      color: onSurfaceColor.withValues(
                                          alpha: 0.24)))
                              : null,
                          alignment: Alignment.center,
                          child: widget.showNavZoneDebugOverlay
                              ? Text(
                                  _pdfZoneActionLabel(action),
                                  style: TextStyle(
                                      color: onSurfaceColor.withValues(
                                          alpha: 0.7),
                                      fontSize: 10),
                                )
                              : null,
                        ),
```

（`TextStyle` 前的 `const` 一併移除——`onSurfaceColor` 是執行期才能取得的值，不再是編譯期常數。）

- [x] **Step 4: 執行測試，確認通過**

Run（於 `app/` 目錄下）: `flutter test test/reader/pdf_reader_view_nav_zone_test.dart`
Expected: PASS（本檔案全部測試皆過，含既有的熱區點擊／`showNavZoneDebugOverlay` 預設不顯示文字／長按逾時不觸發等測試，無回歸）。

- [x] **Step 5: 執行 `flutter analyze`，確認乾淨**

Run（於 `app/` 目錄下）: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 6: Commit**

```bash
git add app/lib/reader/pdf_reader_view.dart app/test/reader/pdf_reader_view_nav_zone_test.dart
git commit -m "$(cat <<'EOF'
feat(epic-35): Issue 7 Task 2 — pdf_reader_view.dart 熱區除錯疊層改讀 colorScheme.onSurface

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01DDZwVcXmYjiFpmqArXeguR
EOF
)"
```

---

### Task 3：`pdf_reader_view.dart` 框選拖曳框／備註徽章／搜尋高亮改讀 `ColorScheme`／`ElinkTokens`

**Files:**
- Modify: `app/lib/reader/pdf_reader_view.dart`（新增 import；`_buildDragIndicator()` 原 L1046-1058；`_buildDecorationWidget()` 原 L1060-1098；`_buildSearchHighlightWidget()` 原 L1106-1135）
- Test: `app/test/reader/pdf_reader_view_selection_test.dart`（框選拖曳框、備註徽章，新增測試）
- Test／Modify: `app/test/reader/pdf_reader_view_search_test.dart`（新增搜尋高亮測試；**另需修改既有 2 則測試**——`'setSearchHighlights 後畫面渲染出對應的高亮 widget...'`〔原 L105-129〕與 `'目前符合結果（isCurrent）額外疊加外框...'`〔原 L131-174〕的 `MaterialApp` 補上 `theme: resolveThemeData(...)` 腳手架，見 Step 9 說明；不補的話 `_buildSearchHighlightWidget()` 呼叫 `Theme.of(context).extension<ElinkTokens>()!` 時這兩則既有測試會因裸 `MaterialApp` 沒有掛 `ElinkTokens` extension 而崩潰，比照本 Epic `69f08017` commit 修過的同一種主題腳手架遺漏問題，`/superpowers:requesting-code-review` 第二輪審查 Critical C1 發現）

**Interfaces:**
- Consumes: 既有 Flutter SDK `ColorScheme` API（`colorScheme.primary`／`onSurface`）、既有 `ElinkTokens.highlightYellow`／`highlightGreen`（Issue 1／Issue 2 已完成，本 Task 不新增欄位）。
- Produces: 無新介面——不新增／不變更任何函式簽章或公開建構參數。

**與 Task 1／Task 2 的關係：** 完全獨立、修改不同私有方法，可在 Task 1／2 之前、之後或同時執行，不需要序列化。

- [x] **Step 1: 寫失敗的測試——框選拖曳預覽框改讀 `colorScheme.primary`**

在 `app/test/reader/pdf_reader_view_selection_test.dart` 中，緊接在既有測試 `'長按拖曳過程中即時顯示選取矩形視覺回饋'`（原 L351-380）之後，新增：

```dart
  testWidgets(
      '長按拖曳過程中，選取矩形視覺回饋改讀 colorScheme.primary（'
      'epic-35-design-system-tokens Issue 7：取代原本寫死的 Colors.yellow／orange）',
      (tester) async {
    var renderedCount = 0;
    final key = GlobalKey<State<PdfReaderView>>();

    await tester.pumpWidget(
      MaterialApp(
        home: PdfReaderView(
          key: key,
          filePath: 'test/fixtures/sample_multi_page.pdf',
          onPageRendered: () => renderedCount++,
          onError: (_) {},
        ),
      ),
    );
    await pumpUntilPdfReady(tester, condition: () => renderedCount != 0);

    final topLeft = tester.getTopLeft(find.byType(PdfReaderView));
    final gesture = await tester.startGesture(topLeft + const Offset(40, 60));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await gesture.moveTo(topLeft + const Offset(160, 220));
    await tester.pump();

    final context = tester
        .element(find.byKey(const Key('pdf_reader_selection_drag_indicator')));
    final primaryColor = Theme.of(context).colorScheme.primary;

    final indicator = tester.widget<Container>(
      find.descendant(
        of: find.byKey(const Key('pdf_reader_selection_drag_indicator')),
        matching: find.byType(Container),
      ),
    );
    final decoration = indicator.decoration as BoxDecoration;
    expect(decoration.color, primaryColor.withValues(alpha: 0.3));
    expect((decoration.border as Border).top.color, primaryColor);

    await gesture.up();
    await tester.pump(const Duration(milliseconds: 350));
  });
```

- [x] **Step 2: 執行測試，確認失敗**

Run（於 `app/` 目錄下）: `flutter test test/reader/pdf_reader_view_selection_test.dart`
Expected: 新增的測試 FAIL——`decoration.color` 目前仍是 `Colors.yellow.withValues(alpha: 0.3)`，跟 `primaryColor.withValues(alpha: 0.3)` 不相等；邊框顏色目前仍是 `Colors.orange`，跟 `primaryColor` 不相等。其餘既有測試維持 PASS。

- [x] **Step 3: 實作——框選拖曳預覽框改讀 `colorScheme.primary`**

把 `_buildDragIndicator()`（原 L1046-1058）：

```dart
  Widget _buildDragIndicator(_PdfSelectionDragState drag) {
    final rect = Rect.fromPoints(drag.start, drag.current);
    return Positioned.fromRect(
      key: const Key('pdf_reader_selection_drag_indicator'),
      rect: rect,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.yellow.withValues(alpha: 0.3),
          border: Border.all(color: Colors.orange, width: 1.5),
        ),
      ),
    );
  }
```

改為：

```dart
  Widget _buildDragIndicator(_PdfSelectionDragState drag) {
    final rect = Rect.fromPoints(drag.start, drag.current);
    // epic-35-design-system-tokens Issue 7：框選進行中尚未決定標記顏色，
    // 改用 primary（App 既有「操作中／選取中」語彙）取代原本寫死的
    // Colors.yellow／orange，換主題／開啟 E-Ink 模式時能正確跟著換。
    final primaryColor = Theme.of(context).colorScheme.primary;
    return Positioned.fromRect(
      key: const Key('pdf_reader_selection_drag_indicator'),
      rect: rect,
      child: Container(
        decoration: BoxDecoration(
          color: primaryColor.withValues(alpha: 0.3),
          border: Border.all(color: primaryColor, width: 1.5),
        ),
      ),
    );
  }
```

- [x] **Step 4: 執行測試，確認框選拖曳框那則測試通過**

Run（於 `app/` 目錄下）: `flutter test test/reader/pdf_reader_view_selection_test.dart`
Expected: PASS（本檔案全部測試皆過，含既有的框選拖曳／取消／裁切互斥／`refreshAnnotations` 等測試，無回歸；Step 5 要新增的備註徽章測試此時還沒寫，不影響這次執行）。

- [x] **Step 5: 寫失敗的測試——備註徽章圖釘改讀 `colorScheme.onSurface`**

在同一份 `app/test/reader/pdf_reader_view_selection_test.dart` 中，緊接在既有測試 `'refreshAnnotations 呼叫後，對應頁面顯示標記疊圖'`（原 L495-524）之後，新增：

```dart
  testWidgets(
      'isNoteOnly=true 時，備註徽章圖釘改讀 colorScheme.onSurface（'
      'epic-35-design-system-tokens Issue 7：取代原本寫死的 Colors.black87）',
      (tester) async {
    var renderedCount = 0;
    final key = GlobalKey<State<PdfReaderView>>();

    await tester.pumpWidget(
      MaterialApp(
        home: PdfReaderView(
          key: key,
          filePath: 'test/fixtures/sample_multi_page.pdf',
          onPageRendered: () => renderedCount++,
          onError: (_) {},
        ),
      ),
    );
    await pumpUntilPdfReady(tester, condition: () => renderedCount != 0);

    PdfReaderView.refreshAnnotations(key, const [
      PdfAnnotationDecoration(
        pageIndex: 0,
        rect: PercentRect(left: 0.1, top: 0.1, right: 0.5, bottom: 0.2),
        tint: 0x73FDE047,
        isNoteOnly: true,
      ),
    ]);
    await tester.pump();

    final context =
        tester.element(find.byKey(const Key('pdf_reader_decoration_0_0')));
    final onSurfaceColor = Theme.of(context).colorScheme.onSurface;

    final pinIcon = tester.widget<Icon>(find.byIcon(Icons.push_pin));
    expect(pinIcon.color, onSurfaceColor);
  });
```

- [x] **Step 6: 執行測試，確認失敗**

Run（於 `app/` 目錄下）: `flutter test test/reader/pdf_reader_view_selection_test.dart`
Expected: 新增的測試 FAIL——`pinIcon.color` 目前仍是 `Colors.black87`，跟 `onSurfaceColor` 不相等（`MaterialApp` 未指定 `theme:` 時使用 Flutter 預設 `ColorScheme`，其 `onSurface` 不等於 `Colors.black87`）。其餘既有測試（含 Step 3 已修好的框選拖曳框測試）維持 PASS。

- [x] **Step 7: 實作——備註徽章圖釘改讀 `colorScheme.onSurface`**

在 `app/lib/reader/pdf_reader_view.dart` 的 `_buildDecorationWidget()`（原 L1089-1094 的備註徽章分支）：

```dart
          if (decoration.isNoteOnly)
            const Positioned(
              right: -6,
              top: -6,
              child: Icon(Icons.push_pin, size: 16, color: Colors.black87),
            ),
```

改為：

```dart
          if (decoration.isNoteOnly)
            Positioned(
              right: -6,
              top: -6,
              child: Icon(Icons.push_pin,
                  size: 16, color: Theme.of(context).colorScheme.onSurface),
            ),
```

（`Positioned` 前的 `const` 一併移除——`Theme.of(context)` 是執行期取值，不再是編譯期常數運算式。E-Ink 主題下這個圖釘與純黑劃線 tint 疊在一起時可能不可辨識，這是改動前就存在的既有限制〔原本寫死的 `Colors.black87` 疊在同樣是純黑的 E-Ink 標記上同樣不可辨識〕，不是本工單造成的新回歸，不在本工單修復範圍，見上方「範圍決定」。）

- [x] **Step 8: 執行測試，確認備註徽章那則測試通過**

Run（於 `app/` 目錄下）: `flutter test test/reader/pdf_reader_view_selection_test.dart`
Expected: PASS（本檔案全部測試皆過，含框選拖曳框／備註徽章兩則新測試與既有測試，無回歸）。

- [x] **Step 9: 補齊主題腳手架＋寫失敗的測試——搜尋高亮改讀 `ElinkTokens`／`colorScheme.primary`**

**（`/superpowers:requesting-code-review` 第二輪審查發現 Critical C1）** Step 11 會讓 `_buildSearchHighlightWidget()` 呼叫 `Theme.of(context).extension<ElinkTokens>()!`；`pdf_reader_view_search_test.dart` 既有 2 則會觸發這個 widget 建構的測試（`'setSearchHighlights 後畫面渲染出對應的高亮 widget...'` 原 L105-129、`'目前符合結果（isCurrent）額外疊加外框...'` 原 L131-174）目前都用裸 `MaterialApp(home: PdfReaderView(...))`，未指定 `theme:`——裸 `MaterialApp` 的預設 `ThemeData` 不掛 `ElinkTokens` extension，`extension<ElinkTokens>()` 回傳 `null`，尾隨的 `!` 會立即拋出 `Null check operator used on a null value`，讓這兩則原本 PASS 的既有測試崩潰（與本 Epic `69f08017` commit「補齊 4 個測試檔案缺漏的 ElinkTokens 主題腳手架」修過的同一種問題）。這個檔案其餘 4 則測試（原 L10-37／L39-59／L61-81／L83-103／L176-184）從未呼叫 `setSearchHighlights`，不會觸發 `_buildSearchHighlightWidget()` 建構，不受影響、不需要補腳手架。

在 `app/test/reader/pdf_reader_view_search_test.dart` 頂部 import 區塊新增（比照 `app/test/screens/annotation_toolbar_test.dart` 既有慣例）：

```dart
import 'package:elinkbook/theme/app_theme.dart';
import 'package:elinkbook/theme/app_theme_data.dart';
import 'package:elinkbook/theme/elink_tokens.dart';
```

把既有測試 `'setSearchHighlights 後畫面渲染出對應的高亮 widget，含目前符合結果的獨立 Key'`（原 L105-129）與 `'目前符合結果（isCurrent）額外疊加外框，其餘符合結果無外框（審查修正 Minor #3）'`（原 L131-174）內的 `MaterialApp(home: PdfReaderView(...))`（原 L110-118、L136-144，兩處內容完全相同）：

```dart
      MaterialApp(
        home: PdfReaderView(
          key: key,
          filePath: 'test/fixtures/sample_multi_page.pdf',
          onPageRendered: () => renderedCount++,
          onError: (_) {},
        ),
      ),
```

各自改為：

```dart
      MaterialApp(
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: PdfReaderView(
          key: key,
          filePath: 'test/fixtures/sample_multi_page.pdf',
          onPageRendered: () => renderedCount++,
          onError: (_) {},
        ),
      ),
```

（這兩則既有測試本身不斷言任何顏色值——L105 只斷言 `findsOneWidget`，L131 只斷言 `border` 是否為 `null`——補上 `theme:` 純粹是為了讓 `Theme.of(context).extension<ElinkTokens>()` 在 Step 11 實作落地後不再回傳 `null`，不影響這兩則測試現有的斷言邏輯或執行結果。）

緊接在既有測試 `'目前符合結果（isCurrent）額外疊加外框，其餘符合結果無外框（審查修正 Minor #3）'`之後，新增：

```dart
  testWidgets(
      '搜尋高亮填色改讀 ElinkTokens.highlightYellow／highlightGreen，'
      'isCurrent 外框改讀 colorScheme.primary（epic-35-design-system-tokens '
      'Issue 7：取代原本寫死的 Colors.yellow／orange／deepOrange）',
      (tester) async {
    var renderedCount = 0;
    final key = GlobalKey<State<PdfReaderView>>();

    await tester.pumpWidget(
      MaterialApp(
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: PdfReaderView(
          key: key,
          filePath: 'test/fixtures/sample_multi_page.pdf',
          onPageRendered: () => renderedCount++,
          onError: (_) {},
        ),
      ),
    );
    await pumpUntilPdfReady(tester, condition: () => renderedCount != 0);

    final matches = await tester.runAsync(() => PdfReaderView.search(key, 'Page'));
    expect(matches, isNotNull);

    PdfReaderView.setSearchHighlights(key, matches!, currentIndex: 0);
    await tester.pump();

    final context = tester
        .element(find.byKey(const Key('pdf_reader_search_highlight_0_0')));
    final tokens = Theme.of(context).extension<ElinkTokens>()!;
    final primaryColor = Theme.of(context).colorScheme.primary;

    final currentContainer = tester.widget<Container>(
      find.descendant(
        of: find.byKey(const Key('pdf_reader_search_highlight_0_0')),
        matching: find.byType(Container),
      ),
    );
    final currentDecoration = currentContainer.decoration as BoxDecoration;
    expect(currentDecoration.color, tokens.highlightGreen.withValues(alpha: 0.4));
    expect((currentDecoration.border as Border).top.color, primaryColor);

    // 頁碼 1（index 1）的符合結果不是目前選取項，應為 highlightYellow、無外框。
    PdfReaderView.jumpToPage(key, 1);
    await tester.pump(const Duration(milliseconds: 300));
    final otherContainer = tester.widget<Container>(
      find.descendant(
        of: find.byKey(const Key('pdf_reader_search_highlight_1_1')),
        matching: find.byType(Container),
      ),
    );
    final otherDecoration = otherContainer.decoration as BoxDecoration;
    expect(otherDecoration.color, tokens.highlightYellow.withValues(alpha: 0.4));
  });
```

- [x] **Step 10: 執行測試，確認失敗**

Run（於 `app/` 目錄下）: `flutter test test/reader/pdf_reader_view_search_test.dart`
Expected: 新增的測試 FAIL——`currentDecoration.color` 目前仍是 `Colors.orange.withValues(alpha: 0.4)`，跟 `tokens.highlightGreen.withValues(alpha: 0.4)` 不相等；`otherDecoration.color` 目前仍是 `Colors.yellow.withValues(alpha: 0.4)`，跟 `tokens.highlightYellow.withValues(alpha: 0.4)` 不相等；邊框顏色目前仍是 `Colors.deepOrange`，跟 `primaryColor` 不相等。**這是一則單純的顏色斷言失敗，不是例外崩潰**——`_buildSearchHighlightWidget()` 尚未實作 Step 11 的改動，此時還沒有任何呼叫 `Theme.of(context).extension<ElinkTokens>()` 的程式碼路徑。原第 105、131 則既有測試（已在本 Step 補上 `theme:` 腳手架）與其餘 4 則既有測試皆維持 PASS。

- [x] **Step 11: 實作——搜尋高亮改讀 `ElinkTokens`／`colorScheme.primary`**

在 `app/lib/reader/pdf_reader_view.dart` 頂部 import 區塊（原 L29 `import 'zone_action.dart';` 之後）新增：

```dart
import '../theme/elink_tokens.dart';
```

把 `_buildSearchHighlightWidget()`（原 L1106-1135）：

```dart
  Widget _buildSearchHighlightWidget(
    int pageIndex,
    int matchIndex,
    PercentRect visibleRect,
    Size areaSize, {
    required bool isCurrent,
  }) {
    final rect = Rect.fromLTRB(
      visibleRect.left * areaSize.width,
      visibleRect.top * areaSize.height,
      visibleRect.right * areaSize.width,
      visibleRect.bottom * areaSize.height,
    );
    return Positioned.fromRect(
      // key 須同時包含 pageIndex 與 matchIndex（matchIndex 是在
      // _searchMatches 整份清單中的全域索引，非同頁內重新歸零的計數）——
      // 理由與 _buildDecorationWidget 的既有註解相同：同一頁可能有多筆
      // 符合結果，只用 pageIndex 當 key 會產生重複 key。
      key: Key('pdf_reader_search_highlight_${pageIndex}_$matchIndex'),
      rect: rect,
      child: Container(
        decoration: BoxDecoration(
          color: (isCurrent ? Colors.orange : Colors.yellow).withValues(alpha: 0.4),
          border: isCurrent
              ? Border.all(color: Colors.deepOrange, width: 1.5)
              : null,
        ),
      ),
    );
  }
```

改為：

```dart
  Widget _buildSearchHighlightWidget(
    int pageIndex,
    int matchIndex,
    PercentRect visibleRect,
    Size areaSize, {
    required bool isCurrent,
  }) {
    final rect = Rect.fromLTRB(
      visibleRect.left * areaSize.width,
      visibleRect.top * areaSize.height,
      visibleRect.right * areaSize.width,
      visibleRect.bottom * areaSize.height,
    );
    // epic-35-design-system-tokens Issue 7：搜尋高亮概念上就是「標示出
    // 文字位置」，沿用既有劃線語意色 ElinkTokens.highlightYellow／
    // highlightGreen 取代原本寫死的 Colors.yellow／orange；isCurrent 外框
    // 改讀 colorScheme.primary 取代 Colors.deepOrange——維持原設計「外框
    // 存在與否（而非色相）才是可辨識度依據」的既有原則不變（見上方
    // _buildSearchHighlightWidget 註解），只換掉色彩角色的來源。
    final tokens = Theme.of(context).extension<ElinkTokens>()!;
    final colorScheme = Theme.of(context).colorScheme;
    return Positioned.fromRect(
      // key 須同時包含 pageIndex 與 matchIndex（matchIndex 是在
      // _searchMatches 整份清單中的全域索引，非同頁內重新歸零的計數）——
      // 理由與 _buildDecorationWidget 的既有註解相同：同一頁可能有多筆
      // 符合結果，只用 pageIndex 當 key 會產生重複 key。
      key: Key('pdf_reader_search_highlight_${pageIndex}_$matchIndex'),
      rect: rect,
      child: Container(
        decoration: BoxDecoration(
          color: (isCurrent ? tokens.highlightGreen : tokens.highlightYellow)
              .withValues(alpha: 0.4),
          border: isCurrent
              ? Border.all(color: colorScheme.primary, width: 1.5)
              : null,
        ),
      ),
    );
  }
```

- [x] **Step 12: 執行測試，確認全部通過**

Run（於 `app/` 目錄下）: `flutter test test/reader/pdf_reader_view_search_test.dart`
Expected: PASS（本檔案全部 7 則測試皆過，特別確認原第 105、131 則已補上 `theme:` 腳手架的既有測試沒有因為 `_buildSearchHighlightWidget()` 新增的 `Theme.of(context).extension<ElinkTokens>()!` 呼叫而崩潰；其餘未觸發這個 widget 建構的既有測試不受影響）。

- [x] **Step 13: 執行 `flutter analyze`，確認乾淨**

Run（於 `app/` 目錄下）: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 14: Commit**

```bash
git add app/lib/reader/pdf_reader_view.dart app/test/reader/pdf_reader_view_selection_test.dart app/test/reader/pdf_reader_view_search_test.dart
git commit -m "$(cat <<'EOF'
feat(epic-35): Issue 7 Task 3 — pdf_reader_view.dart 框選拖曳框／備註徽章／搜尋高亮改讀 ColorScheme／ElinkTokens

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01DDZwVcXmYjiFpmqArXeguR
EOF
)"
```

---

## 全部 Task 完成後

- [x] 執行完整 `flutter test`（於 `app/` 目錄下，不帶檔案路徑），確認全專案無回歸。
- [x] 執行 `flutter analyze`，確認「No issues found!」。
- [x] 把 `docs/epics/epic-35-design-system-tokens/issues.md` Issue 7 的 `Status` 從 `ready-for-agent` 更新為完成狀態（依當時 Epic 慣例用語），並在 `epics.md` 補一筆開發記錄；同時記錄「原計劃草案曾主張排除 3 處顏色未經 `issues.md` 授權，經獨立審查與人類確認後改為一併遷移」這段過程（比照 `plan-issue-5.md` 在 `issues.md` 留下的記錄慣例）。
- [x] 依 `sdd-workflow` 流程，發起 `/superpowers:requesting-code-review` 審查本次程式碼變更（`BASE_SHA`／`HEAD_SHA` 取本工單 3 個 commit 的起訖），審查報告存 `docs/epics/epic-35-design-system-tokens/reviews/review-issue-7.md`。
- [x] 保留 1 項人工待辦（本工單不動手處理，記錄供下一輪真機驗證）：`reader_option_tile.dart:51` 非 E-Ink 分支的 `theme.colorScheme.outline.withValues(alpha: 0.35)` 選項邊框，在 Issue 2 的 Dark `outline` 新值（`#2c2c34`）落地後，於真機／模擬器上目視確認 Dark 主題下仍可辨識——`issues.md` Issue 2／Issue 6 已各自記錄過同一組風險（Issue 2 第 39-41 行、Issue 6 收尾備註），本工單只是第三次、也是 `issues.md` Issue 7 原文點名的正式落點，不重複展開分析。
- [x] 保留第 2 項人工待辦：`_buildDecorationWidget()` 備註徽章圖釘（`colorScheme.onSurface`）在 E-Ink 主題下與純黑劃線 tint 疊加時可能不可辨識——改動前就存在的既有限制，非本工單新增回歸，見 Task 3 Step 7 說明；E-Ink 模式「不畫底色改畫線條」的正確渲染邏輯屬其他 Issue 範圍。
- [x] 提醒：`colorScheme.onSurface.withValues(alpha: 0.24/0.7)`（Task 1／2 除錯疊層）、`colorScheme.primary.withValues(alpha: 0.3)`（Task 3 框選拖曳框填色）、`tokens.highlightYellow/highlightGreen.withValues(alpha: 0.4)`（Task 3 搜尋高亮填色）這些具體透明度數值是本工單自行決定的具體詮釋（比照 Issue 2 `SwitchThemeData`、Issue 5 `onSurface` 邊框的既有慣例），尚未經過真機驗證，需要下一輪真機驗證（比照 `epic-18`／`epic-25` 慣例）確認在電子紙上確實可辨識，不在本工單驗收範圍內完成。
