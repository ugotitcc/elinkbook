# Epic 35 — Issue 6：書架相關寫死顏色遷移（`book_cover.dart`／`layout_preset_book_picker_screen.dart`／`library_screen.dart`／`library_group_management_dialog.dart`） Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把書架相關四個檔案（`book_cover.dart`／`layout_preset_book_picker_screen.dart`／`library_screen.dart`／`library_group_management_dialog.dart`）內殘留的寫死顏色（`Colors.grey`／`black45`／`black54`／`black38`／`black`／`white`／`red` 等字面值），依用途改讀 `ElinkTokens`（`coverPlaceholder`／`badgeScrim`）或 `ColorScheme`（`onSurfaceVariant`／`scrim`／`onSurface`／`surface`／`error`）對應角色，讓換主題／開啟 E-Ink 模式時這四個畫面的顏色能正確跟著換。

**Architecture:** `BookCover` 是 `LibraryScreen`（格狀＋列表兩種檢視）與 `LayoutPresetBookPickerScreen` 共用的元件，本次是它第一次需要透過 `Theme.of(context).extension<ElinkTokens>()` 取值——這會讓目前用純 `MaterialApp()`（未帶 `theme:`）建構它的既有 widget test 出現 `null` 強制解包例外，因此 Task 1／Task 2 都採「先改原始碼、跑測試看真的紅燈、再補測試腳手架的 `theme:`、確認轉綠燈」的順序，親自驗證這個因果關係，而非憑空假設。`library_screen.dart` 涉及範圍較廣，拆成 Task 3（書籍格線／分類拼貼格／選取徽章，改 `ElinkTokens` 角色）與 Task 4（AppBar 匯入遮罩／E-Ink 切換鈕，改 `ColorScheme` 角色）两個獨立 Task，因為兩者改動的類別完全不同、且 Task 4 的每一處替換都是「解析結果與原字面值相同」的零風險代換（見下方「範圍決定」），適合讓審查者分開檢視這個判斷是否成立。`library_group_management_dialog.dart`（Task 5）是唯一有新增斷言需求的檔案，走標準 TDD 紅燈／綠燈。Task 6 是整份計劃收尾時的全專案驗證（`CLAUDE.md`「測試執行範圍」規則）。

**（`/superpowers:requesting-code-review` 審查發現、已修正的隱性相依）** `app/test/screens/library_screen_test.dart` 有 3 則既有測試直接斷言 `Colors.grey.shade300`／`Colors.grey.shade200` 字面值（L2891／L2947／L2984），Task 1 改動 `book_cover.dart` 會讓 L2891 這一則立即失敗；Task 3 改動 `_groupTilePreviewCell`／`_GroupListTile` 後，L2947／L2984 這兩則會因為「`BookCover` 佔位色與空格佔位色統一成同一個 `tokens.coverPlaceholder`」而讓原本靠色階區分兩者來源的斷言邏輯直接失效（不是字面值置換能解決的結構性問題）。修正後的測試斷言（見 Task 1 新增 Step、Task 3 新增 Step）要求「`BookCover` 佔位色已改為 `tokens.coverPlaceholder`」這個前提成立，所以 **Task 3 現在依賴 Task 1 已先完成**（原先「四個 Task 可任意順序執行」的說法不再成立於 Task 1／Task 3 之間）；Task 2／Task 4／Task 5 彼此、以及與 Task 1／Task 3 之間仍無相依，可任意順序執行。Task 3／Task 4 修改同一份 `library_screen.dart`，兩者之間須序列執行（不可用平行 worktree 同時改同一份檔案），Task 6 仍必須最後執行。

**Tech Stack:** Flutter／Dart，`flutter_test`（`testWidgets`），既有 `ElinkTokens`（`app/lib/theme/elink_tokens.dart`，Issue 1 已完成）與 `resolveThemeData()`（`app/lib/theme/app_theme_data.dart`，Issue 2 已完成），不新增任何 pub 套件依賴、不新增 `ElinkTokens` 欄位。

**Spec:** `docs/epics/epic-35-design-system-tokens/spec.md`（§「寫死顏色遷移」）；工單摘要見 `docs/epics/epic-35-design-system-tokens/issues.md` Issue 6。

## 範圍決定（本計劃自行判斷，執行前請確認）

`issues.md` Issue 6 的 Solution 文字只舉例「`Colors.grey`／`black45`／`white70` 家族」與「`library_screen.dart:747`（已正確，不用改）」，沒有逐行列出 `library_screen.dart` 其餘的 `Colors.black38`／`Colors.black`／`Colors.white`／`Colors.transparent` 用法（匯入中遮罩 L718/725、E-Ink 切換鈕 L742/746/756）該如何處理。驗收標準寫的是「四個檔案內無寫死顏色殘留」，沒有但書。比照 Issue 5 先例（先前自行排除「跟主題無關的裝飾配色」被審查認定未經授權、要求改為一併遷移；本計劃記取這個教訓），逐一檢查後的判斷是：

- **一併遷移（本計劃執行）**：
  - `library_screen.dart:718` `Colors.black38`（匯入中遮罩背景）→ `colorScheme.scrim.withValues(alpha: 0.38)`。四套主題與 E-Ink 主題皆未覆寫 `ColorScheme.scrim`，Flutter 預設值即為不透明黑，所以這個代換在四套主題下解析出來的 8-bit 顯示色值與現行 `Colors.black38` 相同（視覺上不可分辨；`scrim` 目前為浮點內部表示、`Colors.black38` 為 8-bit 整數常數，兩者內部表示法不同，只是量化後的顯示值一致），是零風險的字面值→角色代換，不是「跟主題無關就不用改」的偷懶排除。
  - `library_screen.dart:742` `Colors.black`（E-Ink 切換鈕藥丸底色，`isEinkMode == true` 分支）→ `Theme.of(context).colorScheme.onSurface`。這個分支只有 `isEinkMode == true` 時才會走到，而 `isEinkMode == true` 時 `resolveThemeData()` 一定回傳 `_buildEinkTheme()`，其 `onSurface` 定義即為 `Color(0xFF000000)`，代換後解析結果與原字面值相同。
  - `library_screen.dart:756` `Colors.white`（E-Ink 切換鈕圖示色，`isEinkMode == true` 分支）→ `Theme.of(context).colorScheme.surface`。同一理由，`_buildEinkTheme().colorScheme.surface` 即為 `Color(0xFFFFFFFF)`。
- **維持字面值，不遷移（有具體技術理由，非偷懶）**：
  - `book_cover.dart` 雲朵徽章圖示色、`layout_preset_book_picker_screen.dart`／`library_screen.dart` 選取指示圖示未選取狀態色——三處皆為 `Colors.white`，疊在 `tokens.badgeScrim` 之上。`badgeScrim` 本身四套主題各自有不同色值（晴空 `#94A3B8`／深色 `#7A7872`／宣紙 `#848588`／E-Ink `#000000`，皆為中至深色調），`ElinkTokens` 沒有定義對應的「badgeScrim 前景色」欄位（Issue 1 已定案凍結欄位，新增欄位不在本 Issue 範圍），也沒有任何既有 `ColorScheme` 角色能保證「在這四種深淺不一的背景上都維持白色」——這與 E-Ink 切換鈕的情況不同（那裡背景*固定*是純黑，找得到對應的 `onSurface` 角色）；`badgeScrim` 的色值本身就是設計時特意選在「配白色圖示看得清楚」的深淺區間，維持字面白色是唯一正確選項。
  - `library_screen.dart:725` 匯入中遮罩文字色 `Colors.white`——配對的 `colorScheme.scrim` 在四套主題下皆固定為不透明黑（見上），需要一個「在所有主題下都固定亮」的前景色。M3 `onInverseSurface` 角色會隨主題明暗翻轉（深色主題下 `onInverseSurface` 反而是暗色），配上恆定為黑色的 `scrim` 會在深色主題下讀不到文字，是更糟的選擇；沒有其他既有角色符合「恆定亮色」需求，維持字面白色。
  - `library_screen.dart:746` `Colors.transparent`（E-Ink 切換鈕邊框，`isEinkMode == true` 分支——`isEinkMode` 為 true 時黑底本身已提供足夠視覺邊界，不需要再畫邊框；`isEinkMode` 為 false 時才是 L747 的 `outline` 邊框分支）——這不是一個「顏色」，是「不畫邊框」，不屬於「寫死顏色殘留」，不需要對應任何角色。
  - `book_cover.dart` 的 `bookFormatIcon()` 圖示前景色（目前未設定，走 `IconTheme` 預設）與 `DESIGN.md` §8.2 同一節要求的「書名文字的微型縮略」——`DESIGN.md` §8.2 完整原文是「佔位符內必須包含：`Icons.book` 圖示（前景採用 `onSurfaceVariant`）與書名文字的微型縮略」「E-Ink 模式下的佔位符為純白底＋1.5dp 純黑實線外框」，這整節描述的是封面佔位符更完整的重新設計（換圖示種類＋加書名縮圖＋加 E-Ink 外框），三者是同一個「未來重新設計」的一部分、性質相同，不能只排除圖示/縮圖那半句卻不提外框那半句。`issues.md` Issue 6 的範圍只講「寫死顏色遷移」，圖示、縮圖、外框目前都不是「已存在的寫死顏色需要換成 token」，而是「目前完全不存在、需要新增的視覺元素」，三者一併不在本 Issue 動手範圍，維持現狀，建議留給未來獨立的 UI 補強 Issue（例如封面佔位符完整重新設計）一次處理，不要只做外框而漏掉圖示/縮圖，或反過來。

若人類審查者認為上述任一判斷不成立，請在對應 Task 執行前先提出，比照 Issue 5 的處理方式修正本計劃再繼續。

## Global Constraints

- 依賴 Issue 2 已完成：四套 `ColorScheme` 與 `ElinkTokens` 已掛上 `resolveThemeData()`，本工單直接引用這個既成事實，不重新定義任何色值。
- 本工單只碰 `app/lib/library/widgets/book_cover.dart`、`app/lib/screens/layout_preset_book_picker_screen.dart`、`app/lib/screens/library_screen.dart`、`app/lib/screens/library_group_management_dialog.dart` 及其對應測試檔，不碰其他畫面檔案；不碰 OPDS／WebDAV／雲端來源實作／書籍儲存／閱讀進度持久化。
- 不影響 business logic：書籍匯入／分類 CRUD／選取模式／搜尋篩選／單選複選契約等既有邏輯完全不變，純粹是顏色來源調整。
- `ElinkTokens` 欄位維持 Issue 1 定案的 11 個欄位不變，本工單不新增／不修改任何欄位。
- 所有 Dart 原始碼註解使用正體中文。
- 每個 Task 完成後只跑該 Task 涉及檔案的測試（見各 Task「驗證」欄），不需要整套 `flutter test`；Task 6（最後一個 Task）才跑一次完整 `flutter test`（見 `CLAUDE.md`「測試執行範圍」）。
- 每個 Task 的 Step 完成後，把本檔案對應的 `- [ ]` 改成 `- [x]`。
- 提交前 `flutter analyze` 須維持「No issues found!」（Task 6 統一驗證）。
- 所有指令皆在 `app/` 目錄下執行。

## 動手改程式碼前的四點說明（`UI_DESIGN_RULES.md` 要求）

1. **改哪個 UI 元件**：`BookCover`（`app/lib/library/widgets/book_cover.dart`，書架/書籍選擇器共用的封面卡片元件）、`LayoutPresetBookPickerScreen`（`app/lib/screens/layout_preset_book_picker_screen.dart`，版面預設集/書籍設定複製用的書籍選擇畫面）、`LibraryScreen`（`app/lib/screens/library_screen.dart`，書架主畫面，含分類拼貼格／書籍格線／匯入中遮罩／E-Ink 切換鈕）、`LibraryGroupManagementDialog`（`app/lib/screens/library_group_management_dialog.dart`，分類管理對話框的錯誤訊息文字）。全部是既有畫面既有元件的顏色來源調整，不是新畫面、不新增元件。
2. **為什麼要改**：這四個檔案是 `epic-35-design-system-tokens/spec.md`「寫死顏色遷移」清單成員。改用 `ElinkTokens`／`ColorScheme` 角色後，讀者切換主題（晴空藍天／夜讀水墨／宣紙古風）或開啟 E-Ink 高對比模式時，書架相關畫面的顏色才會正確跟著換，不再殘留寫死色值。
3. **哪些畫面依賴它**：`BookCover` 被 `LibraryScreen`（格狀＋列表兩種檢視）與 `LayoutPresetBookPickerScreen` 共用，是本工單影響面最廣的元件，任何改動都會同時影響這三處呼叫端的既有測試。`LibraryGroupManagementDialog` 只被 `LibraryScreen` 的「管理分類」入口以 `showDialog()` 呼叫。
4. **是否影響 business logic**：不影響。純視覺顏色來源調整；書籍匯入／分類新增-重新命名-刪除／選取模式進出／搜尋篩選／單選複選回傳契約等既有邏輯完全不變。

---

### Task 1：`book_cover.dart` 遷移

**Files:**
- Modify: `app/lib/library/widgets/book_cover.dart`
- Modify: `app/test/screens/library_screen_test.dart`（`/superpowers:requesting-code-review` 審查發現：這個檔案 L2850-2912 的既有測試直接斷言 `Colors.grey.shade300`，Task 1 改動 `book_cover.dart` 後會直接失敗，需要一併修正，見 Step 5）
- Test: `app/test/library/widgets/book_cover_test.dart`

**Interfaces:**
- Consumes：`ElinkTokens`（`app/lib/theme/elink_tokens.dart`，Issue 1）、`resolveThemeData()`（`app/lib/theme/app_theme_data.dart`，Issue 2）既有公開 API。
- Produces：`BookCover` 公開建構參數（`book`）不變；無新公開介面。`book_cover.dart` 的 `ColoredBox` 背景改為 `tokens.coverPlaceholder` 這件事，Task 3 的兩則新測試（L2947／L2984 附近）會依賴它已經完成，見 Task 3 Interfaces。

- [ ] **Step 1：修改 `book_cover.dart`，把兩處字面色改讀 `ElinkTokens`**

把：

```dart
import 'dart:io';

import 'package:flutter/material.dart';

import '../models/book.dart';
import '../models/library_enums.dart';
```

改為：

```dart
import 'dart:io';

import 'package:flutter/material.dart';

import '../models/book.dart';
import '../models/library_enums.dart';
import '../../theme/elink_tokens.dart';
```

把：

```dart
  @override
  Widget build(BuildContext context) {
    final coverPath = book.coverPath;
    final cover = coverPath != null && File(coverPath).existsSync()
        ? Image.file(File(coverPath), fit: BoxFit.cover)
        : ColoredBox(
            color: Colors.grey.shade300,
            child: Center(child: Icon(bookFormatIcon(book.format), size: 32)),
          );
    if (book.isDownloaded) return cover;
    return Stack(
      fit: StackFit.expand,
      children: [
        cover,
        Positioned(
          right: 4,
          top: 4,
          child: Container(
            key: const Key('book_cover_cloud_badge'),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.cloud_outlined, size: 16, color: Colors.white),
          ),
        ),
      ],
    );
  }
```

改為：

```dart
  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<ElinkTokens>()!;
    final coverPath = book.coverPath;
    final cover = coverPath != null && File(coverPath).existsSync()
        ? Image.file(File(coverPath), fit: BoxFit.cover)
        : ColoredBox(
            color: tokens.coverPlaceholder,
            child: Center(child: Icon(bookFormatIcon(book.format), size: 32)),
          );
    if (book.isDownloaded) return cover;
    return Stack(
      fit: StackFit.expand,
      children: [
        cover,
        Positioned(
          right: 4,
          top: 4,
          child: Container(
            key: const Key('book_cover_cloud_badge'),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: tokens.badgeScrim,
              borderRadius: BorderRadius.circular(12),
            ),
            // 雲朵圖示前景維持寫死白色：badgeScrim 四套主題色值深淺不一，
            // 沒有對應的「badgeScrim 前景色」token（ElinkTokens 欄位已於
            // Issue 1 定案凍結），白色是唯一在四種背景上都可辨識的選擇。
            child: const Icon(Icons.cloud_outlined, size: 16, color: Colors.white),
          ),
        ),
      ],
    );
  }
```

- [ ] **Step 2：執行既有測試，確認因 `ElinkTokens` 為 null 而失敗**

Run: `flutter test test/library/widgets/book_cover_test.dart`
Expected: 兩則測試皆 FAIL（`Null check operator used on a null value`），因為 `book_cover_test.dart` 目前用純 `MaterialApp()`（未帶 `theme:`），預設 `ThemeData` 沒有掛 `ElinkTokens`。

- [ ] **Step 3：修正 `book_cover_test.dart`，補上 `theme: resolveThemeData(...)`**

把：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/library/widgets/book_cover.dart';
```

改為：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/library/widgets/book_cover.dart';
import 'package:elinkbook/theme/app_theme.dart';
import 'package:elinkbook/theme/app_theme_data.dart';
```

把：

```dart
  testWidgets('isDownloaded 為 false 時疊加雲朵角標', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: BookCover(book: _book(isDownloaded: false)),
    ));

    expect(find.byKey(const Key('book_cover_cloud_badge')), findsOneWidget);
  });

  testWidgets('isDownloaded 為 true 時不顯示雲朵角標', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: BookCover(book: _book(isDownloaded: true)),
    ));

    expect(find.byKey(const Key('book_cover_cloud_badge')), findsNothing);
  });
```

改為：

```dart
  testWidgets('isDownloaded 為 false 時疊加雲朵角標', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
      home: BookCover(book: _book(isDownloaded: false)),
    ));

    expect(find.byKey(const Key('book_cover_cloud_badge')), findsOneWidget);
  });

  testWidgets('isDownloaded 為 true 時不顯示雲朵角標', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
      home: BookCover(book: _book(isDownloaded: true)),
    ));

    expect(find.byKey(const Key('book_cover_cloud_badge')), findsNothing);
  });
```

- [ ] **Step 4：重新執行測試確認通過**

Run: `flutter test test/library/widgets/book_cover_test.dart`
Expected: 兩則測試皆 PASS。

- [ ] **Step 5：修正 `library_screen_test.dart` 內斷言 `BookCover` 佔位色的既有測試（`/superpowers:requesting-code-review` 審查發現的 Critical 缺口）**

先執行 `flutter test test/screens/library_screen_test.dart`，確認「分類拼貼格（格狀檢視）封面預覽區塊填滿可用高度，下方不留空白」這一則（原始行號約 L2850-2912）FAIL——因為 Step 1 已把 `book_cover.dart` 的 `Colors.grey.shade300` 改為 `tokens.coverPlaceholder`（晴空藍天主題實際值 `Color(0xFFE6F1FA)`），這則測試斷言的 `w.color == Colors.grey.shade300` 會 0 個相符，而不是預期的 4 個。

在 `library_screen_test.dart` 檔案開頭加入 import：

把：

```dart
import 'package:elinkbook/theme/app_theme.dart';
import 'package:elinkbook/theme/app_theme_data.dart';
```

改為：

```dart
import 'package:elinkbook/theme/app_theme.dart';
import 'package:elinkbook/theme/app_theme_data.dart';
import 'package:elinkbook/theme/elink_tokens.dart';
```

把這則測試（原始行號約 L2861-2895）：

```dart
    await tester.pumpWidget(
      MaterialApp(
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: LibraryScreen(
          repository: repository,
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final tileFinder = find.byKey(const Key('group_tile_奇幻'));
    expect(tileFinder, findsOneWidget);

    // 結構性驗證：不再使用 GridView 手排 2×2（改用 Expanded 手排），確保
    // 修法本身確實生效，不是巧合的尺寸吻合。
    expect(
      find.descendant(of: tileFinder, matching: find.byType(GridView)),
      findsNothing,
    );

    // 尺寸驗證：4 本書皆無 coverPath，_BookCover 各自以 ColoredBox 佔位
    // （內含置中的小圖示，圖示本身不會撐滿儲存格，故量測 ColoredBox 本身
    // 的邊界而非圖示）；取最下面那一列（第 3/4 格）佔位色塊的底部，應緊
    // 接分類名稱文字的頂部（僅隔明講的 SizedBox(height: 4) 一點點間距），
    // 而非留下大片空白。
    final coverBoxFinder = find.descendant(
      of: tileFinder,
      matching: find.byWidgetPredicate(
        (w) => w is ColoredBox && w.color == Colors.grey.shade300,
      ),
    );
    final coverBoxCount = tester.widgetList(coverBoxFinder).length;
    expect(coverBoxCount, 4);
```

改為：

```dart
    final theme = resolveThemeData(theme: AppTheme.light, isEinkMode: false);
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: LibraryScreen(
          repository: repository,
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final tileFinder = find.byKey(const Key('group_tile_奇幻'));
    expect(tileFinder, findsOneWidget);

    // 結構性驗證：不再使用 GridView 手排 2×2（改用 Expanded 手排），確保
    // 修法本身確實生效，不是巧合的尺寸吻合。
    expect(
      find.descendant(of: tileFinder, matching: find.byType(GridView)),
      findsNothing,
    );

    // 尺寸驗證：4 本書皆無 coverPath，_BookCover 各自以 ColoredBox 佔位
    // （內含置中的小圖示，圖示本身不會撐滿儲存格，故量測 ColoredBox 本身
    // 的邊界而非圖示）；取最下面那一列（第 3/4 格）佔位色塊的底部，應緊
    // 接分類名稱文字的頂部（僅隔明講的 SizedBox(height: 4) 一點點間距），
    // 而非留下大片空白。
    final coverPlaceholder = theme.extension<ElinkTokens>()!.coverPlaceholder;
    final coverBoxFinder = find.descendant(
      of: tileFinder,
      matching: find.byWidgetPredicate(
        (w) => w is ColoredBox && w.color == coverPlaceholder,
      ),
    );
    final coverBoxCount = tester.widgetList(coverBoxFinder).length;
    expect(coverBoxCount, 4);
```

Run: `flutter test test/screens/library_screen_test.dart`
Expected: 這一則轉為 PASS。其餘既有測試維持 PASS（尚未觸及 L2947／L2984 那兩則，那兩則要等 Task 3 才會被 Task 3 自己的 Step 修正——Task 3 執行前，這兩則測試在 Task 1 完成後仍會維持 PASS，因為它們斷言的 `Colors.grey.shade200` 屬於 `_groupTilePreviewCell` 的空格佔位色，Task 1 沒有動到那段程式碼）。

- [ ] **Step 6：commit**

```bash
git add app/lib/library/widgets/book_cover.dart app/test/library/widgets/book_cover_test.dart app/test/screens/library_screen_test.dart
git commit -m "$(cat <<'EOF'
refactor(epic-35): book_cover.dart 寫死顏色遷移至 ElinkTokens

封面佔位底色／雲朵徽章底色改讀 tokens.coverPlaceholder／tokens.badgeScrim，
換主題或開啟 E-Ink 模式時能正確跟著換色；library_screen_test.dart 既有
斷言 BookCover 佔位色的測試同步改讀 tokens.coverPlaceholder。

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Ue4QKXFUDw4c8F8wzQJzGn
EOF
)"
```

---

### Task 2：`layout_preset_book_picker_screen.dart` 遷移

**Files:**
- Modify: `app/lib/screens/layout_preset_book_picker_screen.dart`
- Test: `app/test/screens/layout_preset_book_picker_screen_test.dart`

**Interfaces:**
- Consumes：`ElinkTokens`（Issue 1）、`resolveThemeData()`（Issue 2）；Task 1 已遷移完成的 `BookCover`（本 Task 的 `_BookGridItem` 會渲染它，兩者互不影響彼此的顏色來源，各自從 `Theme.of(context)` 獨立取值）。
- Produces：`LayoutPresetBookPickerScreen` 公開建構參數（`books`／`multiSelect`）不變；無新公開介面。

- [ ] **Step 1：修改 `layout_preset_book_picker_screen.dart`，把選取指示圈底色改讀 `ElinkTokens`**

把檔案開頭：

```dart
import 'package:flutter/material.dart';

import '../library/models/book.dart';
import '../library/widgets/book_cover.dart';
```

改為：

```dart
import 'package:flutter/material.dart';

import '../library/models/book.dart';
import '../library/widgets/book_cover.dart';
import '../theme/elink_tokens.dart';
```

把 `_BookGridItem.build()`：

```dart
  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: Key('layout_preset_book_picker_item_${book.id}'),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                BookCover(book: book),
                Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(
                        color: Colors.black45,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        selected
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
                        key: Key(
                            'layout_preset_book_picker_item_${book.id}_selected'),
                        color: selected
                            ? Theme.of(context).colorScheme.primary
                            : Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            book.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
```

改為：

```dart
  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<ElinkTokens>()!;
    return InkWell(
      key: Key('layout_preset_book_picker_item_${book.id}'),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                BookCover(book: book),
                Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: tokens.badgeScrim,
                        shape: BoxShape.circle,
                      ),
                      // 未選取狀態圖示前景維持寫死白色，理由同
                      // book_cover.dart 雲朵徽章（見本計劃「範圍決定」）。
                      child: Icon(
                        selected
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
                        key: Key(
                            'layout_preset_book_picker_item_${book.id}_selected'),
                        color: selected
                            ? Theme.of(context).colorScheme.primary
                            : Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            book.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
```

- [ ] **Step 2：執行既有測試，確認因 `ElinkTokens` 為 null 而失敗**

Run: `flutter test test/screens/layout_preset_book_picker_screen_test.dart`
Expected: 涉及非空 `books` 清單的測試 FAIL（`Null check operator used on a null value`），因為 `layout_preset_book_picker_screen_test.dart` 目前 17 處 `MaterialApp()` 都未帶 `theme:`。

- [ ] **Step 3：修正 `layout_preset_book_picker_screen_test.dart`，補上 `theme: resolveThemeData(...)`**

先在檔案開頭加入 import：

把：

```dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/screens/layout_preset_book_picker_screen.dart';
```

改為：

```dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/screens/layout_preset_book_picker_screen.dart';
import 'package:elinkbook/theme/app_theme.dart';
import 'package:elinkbook/theme/app_theme_data.dart';
```

接著在檔案內全部 17 處 `MaterialApp(`（原始行號 14、51、92、121、159、174、206、226、239、252、271、293、310、334、375、395、414）緊接著的下一行，各自插入這一行（縮排比照該處既有其他具名參數，例如 `home:` 的縮排層級）：

```dart
      theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
```

原始第 206 行是 `const MaterialApp(`（唯一使用 `const` 的一處，因為 `resolveThemeData(...)` 是執行期函式呼叫、不能出現在 `const` 建構式內），這一處連同插入 `theme:` 這行，同時要把 `const MaterialApp(` 改為 `MaterialApp(`（拿掉 `const`）：

把：

```dart
  testWidgets('書籍清單為空時顯示提示文字', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: LayoutPresetBookPickerScreen(books: [], multiSelect: false),
    ));

    expect(find.text('沒有可選擇的流式 EPUB 書籍'), findsOneWidget);
  });
```

改為：

```dart
  testWidgets('書籍清單為空時顯示提示文字', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
      home: const LayoutPresetBookPickerScreen(books: [], multiSelect: false),
    ));

    expect(find.text('沒有可選擇的流式 EPUB 書籍'), findsOneWidget);
  });
```

其餘 16 處維持 `MaterialApp(`／`home:` 既有寫法不變，只在 `MaterialApp(` 之後插入上述 `theme:` 那一行。例如原始第 14-30 行：

```dart
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => ElevatedButton(
```

改為：

```dart
    await tester.pumpWidget(MaterialApp(
      theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
      home: Builder(
        builder: (context) => ElevatedButton(
```

其餘 15 處（原始行號 51、92、121、159、174、226、239、252、271、293、310、334、375、395、414）比照同一種插入方式逐一處理，不做人工篩選、每一處都要插入，避免比照 Issue 4 收尾階段發現的同類疏漏（`library_screen_test.dart` 96 處遺漏事件）。

- [ ] **Step 4：重新執行測試確認通過**

Run: `flutter test test/screens/layout_preset_book_picker_screen_test.dart`
Expected: 全部 17 則測試皆 PASS。

- [ ] **Step 5：commit**

```bash
git add app/lib/screens/layout_preset_book_picker_screen.dart app/test/screens/layout_preset_book_picker_screen_test.dart
git commit -m "$(cat <<'EOF'
refactor(epic-35): layout_preset_book_picker_screen.dart 寫死顏色遷移至 ElinkTokens

選取指示圈底色改讀 tokens.badgeScrim；測試檔 17 處 MaterialApp 補齊
ElinkTokens 主題（BookCover 現在需要它才能渲染）。

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Ue4QKXFUDw4c8F8wzQJzGn
EOF
)"
```

---

### Task 3：`library_screen.dart`——書籍格線／分類拼貼格／選取徽章遷移

**Files:**
- Modify: `app/lib/screens/library_screen.dart`（`_GroupGridTile`／`_groupTilePreviewCell`／`_GroupListTile`／`_BookGridTile`，原始行號約 1115-1332）
- Modify: `app/test/screens/library_screen_test.dart`（`/superpowers:requesting-code-review` 審查發現：L2914-2952／L2954-2989 兩則既有測試斷言 `Colors.grey.shade200`，本 Task 改動後這兩則會因為色階區分機制被消滅而失效，需要結構性修正，見 Step 6／Step 7）

**Interfaces:**
- Consumes：`ElinkTokens`（Issue 1）、`resolveThemeData()`（Issue 2）；`library_screen_test.dart` 已在 Issue 4 收尾修正時全面補齊 `theme: resolveThemeData(...)`（見 `issues.md` Issue 4「收尾階段修正」記錄），本 Task 不需要再修改 `MaterialApp` 建構方式本身。**本 Task 依賴 Task 1 已先完成**（`/superpowers:requesting-code-review` 審查發現）：Step 6／Step 7 要修正的兩則測試斷言依賴 `book_cover.dart` 的 `ColoredBox` 已改為 `tokens.coverPlaceholder`（Task 1 的改動）——若 Task 1 尚未完成就執行本 Task 的 Step 6／Step 7，`BookCover` 佔位色仍是 `Colors.grey.shade300`，斷言的「總數 4」會對不上（屆時只有 `_groupTilePreviewCell` 那幾個空格會是新色，`BookCover` 那幾個還是舊色，兩者不會相等），必須先完成 Task 1。
- Produces：`_groupTilePreviewCell` 私有方法簽章由 `Widget _groupTilePreviewCell(int index)` 改為 `Widget _groupTilePreviewCell(BuildContext context, int index)`——純私有實作細節，不影響任何公開介面，Task 4／Task 5 不依賴它。

- [ ] **Step 1：執行既有測試建立基準（綠燈）**

Run: `flutter test test/screens/library_screen_test.dart`
Expected: 全數 PASS（尚未改動原始碼）。

- [ ] **Step 2：修改 `library_screen.dart`，加入 `ElinkTokens` import**

把：

```dart
import '../library/models/book.dart';
import '../library/models/book_group.dart';
import '../library/models/library_enums.dart';
import '../library/widgets/book_cover.dart';
```

改為：

```dart
import '../library/models/book.dart';
import '../library/models/book_group.dart';
import '../library/models/library_enums.dart';
import '../library/widgets/book_cover.dart';
import '../theme/elink_tokens.dart';
```

- [ ] **Step 3：`_GroupGridTile` 改讀 `tokens.coverPlaceholder`**

把 `_GroupGridTile.build()` 內三處呼叫 `_groupTilePreviewCell(0)`／`_groupTilePreviewCell(1)`／`_groupTilePreviewCell(2)`／`_groupTilePreviewCell(3)` 的區塊：

```dart
                Expanded(
                  child: Row(
                    children: [
                      Expanded(child: _groupTilePreviewCell(0)),
                      const SizedBox(width: 2),
                      Expanded(child: _groupTilePreviewCell(1)),
                    ],
                  ),
                ),
                const SizedBox(height: 2),
                Expanded(
                  child: Row(
                    children: [
                      Expanded(child: _groupTilePreviewCell(2)),
                      const SizedBox(width: 2),
                      Expanded(child: _groupTilePreviewCell(3)),
                    ],
                  ),
                ),
```

改為：

```dart
                Expanded(
                  child: Row(
                    children: [
                      Expanded(child: _groupTilePreviewCell(context, 0)),
                      const SizedBox(width: 2),
                      Expanded(child: _groupTilePreviewCell(context, 1)),
                    ],
                  ),
                ),
                const SizedBox(height: 2),
                Expanded(
                  child: Row(
                    children: [
                      Expanded(child: _groupTilePreviewCell(context, 2)),
                      const SizedBox(width: 2),
                      Expanded(child: _groupTilePreviewCell(context, 3)),
                    ],
                  ),
                ),
```

把 `_groupTilePreviewCell` 方法本體：

```dart
  Widget _groupTilePreviewCell(int index) {
    return index < tile.previewBooks.length
        ? BookCover(book: tile.previewBooks[index])
        : ColoredBox(color: Colors.grey.shade200);
  }
```

改為：

```dart
  Widget _groupTilePreviewCell(BuildContext context, int index) {
    return index < tile.previewBooks.length
        ? BookCover(book: tile.previewBooks[index])
        : ColoredBox(
            color: Theme.of(context).extension<ElinkTokens>()!.coverPlaceholder,
          );
  }
```

- [ ] **Step 4：`_GroupListTile` 改讀 `tokens.coverPlaceholder`**

把：

```dart
  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: Key('group_tile_${tile.name}'),
      leading: SizedBox(
        width: 4 * 32,
        height: 48,
        child: Row(
          children: List.generate(
            4,
            (i) => SizedBox(
              width: 32,
              height: 48,
              child: i < tile.previewBooks.length
                  ? BookCover(book: tile.previewBooks[i])
                  : ColoredBox(color: Colors.grey.shade200),
            ),
          ),
        ),
      ),
      title: Text(tile.name),
      subtitle: Text('${tile.totalCount} 本'),
      onTap: onTap,
    );
  }
```

改為：

```dart
  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<ElinkTokens>()!;
    return ListTile(
      key: Key('group_tile_${tile.name}'),
      leading: SizedBox(
        width: 4 * 32,
        height: 48,
        child: Row(
          children: List.generate(
            4,
            (i) => SizedBox(
              width: 32,
              height: 48,
              child: i < tile.previewBooks.length
                  ? BookCover(book: tile.previewBooks[i])
                  : ColoredBox(color: tokens.coverPlaceholder),
            ),
          ),
        ),
      ),
      title: Text(tile.name),
      subtitle: Text('${tile.totalCount} 本'),
      onTap: onTap,
    );
  }
```

- [ ] **Step 5：`_BookGridTile` 選取指示圈改讀 `tokens.badgeScrim`、進度文字色改讀 `colorScheme.onSurfaceVariant`**

把：

```dart
  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: Key('book_item_${book.id}'),
      onTap: onTap,
      onLongPress: onLongPress,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                BookCover(book: book),
                if (selectionMode)
                  Align(
                    alignment: Alignment.topRight,
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Container(
                        // 半透明黑底圓圈確保勾選圖示在任何封面底色下都有
                        // 足夠對比度（審查意見：白色圖示疊在淺色封面上會
                        // 無法辨識）。
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(
                          color: Colors.black45,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          selected
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked,
                          key: Key('book_selection_indicator_${book.id}'),
                          color: selected
                              ? Theme.of(context).colorScheme.primary
                              : Colors.white,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: gridTileFooterHeight(MediaQuery.textScalerOf(context)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  book.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12),
                ),
                Text(
                  _progressText(book),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
```

改為：

```dart
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final tokens = Theme.of(context).extension<ElinkTokens>()!;
    return InkWell(
      key: Key('book_item_${book.id}'),
      onTap: onTap,
      onLongPress: onLongPress,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                BookCover(book: book),
                if (selectionMode)
                  Align(
                    alignment: Alignment.topRight,
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Container(
                        // badgeScrim 確保勾選圖示在任何封面底色下都有足夠
                        // 對比度（審查意見：白色圖示疊在淺色封面上會無法
                        // 辨識），四套主題各自有對應色值。
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: tokens.badgeScrim,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          selected
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked,
                          key: Key('book_selection_indicator_${book.id}'),
                          color: selected ? colorScheme.primary : Colors.white,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: gridTileFooterHeight(MediaQuery.textScalerOf(context)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  book.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12),
                ),
                Text(
                  _progressText(book),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
```

- [ ] **Step 6：修正 L2914-2952「分類拼貼格（格狀檢視）不足 4 本時以中性色塊佔位」測試（`/superpowers:requesting-code-review` 審查發現的 Critical 缺口）**

先執行 `flutter test test/screens/library_screen_test.dart`，確認這一則 FAIL——原本斷言的 `Colors.grey.shade200`（`_groupTilePreviewCell` 空格佔位色）已被 Step 3 改為 `tokens.coverPlaceholder`，找不到任何相符的 `ColoredBox`。

在 `library_screen_test.dart` 開頭加入 import（若 Task 1 Step 5 已加過 `elink_tokens.dart`，這裡只需再加 `book_cover.dart`；比照檔案既有的字母序排列慣例，`library/widgets/book_cover.dart` 排在 `library/models/library_enums.dart` 之後、`theme/app_theme.dart` 之前）：

把：

```dart
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/theme/app_theme.dart';
import 'package:elinkbook/theme/app_theme_data.dart';
import 'package:elinkbook/theme/elink_tokens.dart';
```

改為：

```dart
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/library/widgets/book_cover.dart';
import 'package:elinkbook/theme/app_theme.dart';
import 'package:elinkbook/theme/app_theme_data.dart';
import 'package:elinkbook/theme/elink_tokens.dart';
```

把這則測試：

```dart
  testWidgets('分類拼貼格（格狀檢視）不足 4 本時以中性色塊佔位，名稱與本數正確顯示', (tester) async {
    final bookA = _testBook(id: '1', title: 'A書', groupName: '奇幻');
    final bookB = _testBook(id: '2', title: 'B書', groupName: '奇幻');
    final repository = FakeLibraryRepository(initialBooks: [bookA, bookB]);

    await tester.pumpWidget(
      MaterialApp(
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: LibraryScreen(
          repository: repository,
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final tileFinder = find.byKey(const Key('group_tile_奇幻'));
    expect(tileFinder, findsOneWidget);
    expect(find.text('奇幻 (2)'), findsOneWidget);

    // 2 本書皆無 coverPath，_BookCover 各自退回格式圖示佔位（Icon），故拼
    // 貼格內應有 2 個 Icon（書封佔位）＋ 2 個中性灰色塊（拼貼格本身「不
    // 足 4 本」的空格佔位，色階 grey.shade200，與 _BookCover 內部佔位的
    // shade300 不同，可用色階區分兩者，不需要存取 private widget 型別）。
    expect(
      find.descendant(of: tileFinder, matching: find.byType(Icon)),
      findsNWidgets(2),
    );
    expect(
      find.descendant(
        of: tileFinder,
        matching: find.byWidgetPredicate(
          (w) => w is ColoredBox && w.color == Colors.grey.shade200,
        ),
      ),
      findsNWidgets(2),
    );
  });
```

改為：

```dart
  testWidgets('分類拼貼格（格狀檢視）不足 4 本時以中性色塊佔位，名稱與本數正確顯示', (tester) async {
    final bookA = _testBook(id: '1', title: 'A書', groupName: '奇幻');
    final bookB = _testBook(id: '2', title: 'B書', groupName: '奇幻');
    final repository = FakeLibraryRepository(initialBooks: [bookA, bookB]);
    final theme = resolveThemeData(theme: AppTheme.light, isEinkMode: false);

    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: LibraryScreen(
          repository: repository,
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final tileFinder = find.byKey(const Key('group_tile_奇幻'));
    expect(tileFinder, findsOneWidget);
    expect(find.text('奇幻 (2)'), findsOneWidget);

    // 2 本書皆無 coverPath，_BookCover 各自退回格式圖示佔位（Icon），故拼
    // 貼格內應有 2 個 Icon（書封佔位）。拼貼格本身「不足 4 本」的 2 個空
    // 格佔位（_groupTilePreviewCell 的 fallback 分支）遷移後與 _BookCover
    // 佔位色統一為同一個 tokens.coverPlaceholder（本 Epic「同一語意在不同
    // 畫面應該長一樣」的設計目標本身），不再能單靠色階區分兩者來源，改用
    // 「總數（2 書封佔位＋2 空格佔位＝4）減去 BookCover 數量（2）＝空格
    // 佔位數量（2）」的結構性驗證取代色階區分。
    expect(
      find.descendant(of: tileFinder, matching: find.byType(Icon)),
      findsNWidgets(2),
    );
    final coverPlaceholder = theme.extension<ElinkTokens>()!.coverPlaceholder;
    expect(
      find.descendant(
        of: tileFinder,
        matching: find.byWidgetPredicate(
          (w) => w is ColoredBox && w.color == coverPlaceholder,
        ),
      ),
      findsNWidgets(4),
    );
    expect(
      find.descendant(of: tileFinder, matching: find.byType(BookCover)),
      findsNWidgets(2),
    );
  });
```

Run: `flutter test test/screens/library_screen_test.dart`
Expected: 這一則轉為 PASS。

- [ ] **Step 7：修正 L2954-2989「分類拼貼格（列表檢視）不足 4 本時以中性色塊佔位」測試**

先執行 `flutter test test/screens/library_screen_test.dart`，確認這一則 FAIL（理由同 Step 6）。

把這則測試：

```dart
  testWidgets('分類拼貼格（列表檢視）不足 4 本時以中性色塊佔位', (tester) async {
    final book = _testBook(id: '1', title: 'A書', groupName: '奇幻');
    final repository = FakeLibraryRepository(initialBooks: [book]);

    await tester.pumpWidget(
      MaterialApp(
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: LibraryScreen(
          repository: repository,
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('library_view_mode_toggle')));
    await tester.pumpAndSettle();

    final tileFinder = find.byKey(const Key('group_tile_奇幻'));
    expect(tileFinder, findsOneWidget);
    expect(find.text('奇幻'), findsOneWidget);
    expect(find.text('1 本'), findsOneWidget);
    expect(
      find.descendant(of: tileFinder, matching: find.byType(Icon)),
      findsNWidgets(1),
    );
    expect(
      find.descendant(
        of: tileFinder,
        matching: find.byWidgetPredicate(
          (w) => w is ColoredBox && w.color == Colors.grey.shade200,
        ),
      ),
      findsNWidgets(3),
    );
  });
```

改為：

```dart
  testWidgets('分類拼貼格（列表檢視）不足 4 本時以中性色塊佔位', (tester) async {
    final book = _testBook(id: '1', title: 'A書', groupName: '奇幻');
    final repository = FakeLibraryRepository(initialBooks: [book]);
    final theme = resolveThemeData(theme: AppTheme.light, isEinkMode: false);

    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: LibraryScreen(
          repository: repository,
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('library_view_mode_toggle')));
    await tester.pumpAndSettle();

    final tileFinder = find.byKey(const Key('group_tile_奇幻'));
    expect(tileFinder, findsOneWidget);
    expect(find.text('奇幻'), findsOneWidget);
    expect(find.text('1 本'), findsOneWidget);
    expect(
      find.descendant(of: tileFinder, matching: find.byType(Icon)),
      findsNWidgets(1),
    );
    // 同上（格狀檢視版本）理由：1 本書封佔位 + 3 空格佔位，遷移後統一為
    // 同一個 tokens.coverPlaceholder，改用總數減 BookCover 數量的結構性
    // 驗證取代色階區分。
    final coverPlaceholder = theme.extension<ElinkTokens>()!.coverPlaceholder;
    expect(
      find.descendant(
        of: tileFinder,
        matching: find.byWidgetPredicate(
          (w) => w is ColoredBox && w.color == coverPlaceholder,
        ),
      ),
      findsNWidgets(4),
    );
    expect(
      find.descendant(of: tileFinder, matching: find.byType(BookCover)),
      findsNWidgets(1),
    );
  });
```

Run: `flutter test test/screens/library_screen_test.dart`
Expected: 這一則轉為 PASS。

- [ ] **Step 8：重新執行測試確認全數通過**

Run: `flutter test test/screens/library_screen_test.dart`
Expected: 全數 PASS（無回歸）。

- [ ] **Step 9：commit**

```bash
git add app/lib/screens/library_screen.dart app/test/screens/library_screen_test.dart
git commit -m "$(cat <<'EOF'
refactor(epic-35): library_screen.dart 書籍格線/分類拼貼格/選取徽章遷移至 ElinkTokens

分類拼貼格缺格佔位色改讀 tokens.coverPlaceholder、書籍選取指示圈底色
改讀 tokens.badgeScrim、進度百分比文字色改讀 colorScheme.onSurfaceVariant；
library_screen_test.dart 兩則既有測試改用「總數減 BookCover 數量」的結構
性驗證，取代已被本次遷移消滅的色階區分機制。

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Ue4QKXFUDw4c8F8wzQJzGn
EOF
)"
```

---

### Task 4：`library_screen.dart`——匯入中遮罩／E-Ink 切換鈕遷移

**Files:**
- Modify: `app/lib/screens/library_screen.dart`（`_buildImportingOverlay()`／`_buildNormalAppBar()`，原始行號約 714-765，屬 `_LibraryScreenState`）
- Test: `app/test/screens/library_screen_test.dart`

**Interfaces:**
- Consumes：`ColorScheme.scrim`（Flutter M3 內建角色，四套主題與 E-Ink 主題皆未覆寫，預設不透明黑）；不消費 `ElinkTokens`（這幾處全部改讀 `ColorScheme`，不需要 `ElinkTokens`）。
- Produces：無新公開介面，不變更任何方法簽章（`_buildImportingOverlay()`／`_buildNormalAppBar()` 皆為 `_LibraryScreenState` 的既有私有方法，`context` 透過 `State.context` getter 直接取得，不需要新增參數）。

- [ ] **Step 1：執行既有測試建立基準（綠燈）**

Run: `flutter test test/screens/library_screen_test.dart`
Expected: 全數 PASS（尚未改動這兩個方法）。

- [ ] **Step 2：`_buildImportingOverlay()` 改讀 `colorScheme.scrim`**

把：

```dart
  Widget _buildImportingOverlay() {
    return Positioned.fill(
      child: ColoredBox(
        key: const Key('library_importing_overlay'),
        color: Colors.black38,
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 12),
              Text('匯入中...', style: TextStyle(color: Colors.white)),
            ],
          ),
        ),
      ),
    );
  }
```

改為：

```dart
  Widget _buildImportingOverlay() {
    return Positioned.fill(
      child: ColoredBox(
        key: const Key('library_importing_overlay'),
        // 四套主題與 E-Ink 主題皆未覆寫 ColorScheme.scrim，Flutter 預設值
        // 即為不透明黑，這裡解析後的 8-bit 顯示色值與原本字面值
        // Colors.black38 相同（視覺上不可分辨；scrim 目前為浮點內部表示、
        // Colors.black38 為 8-bit 整數常數，兩者內部表示法不同，只是量化
        // 後的顯示值剛好一致）。
        color: Theme.of(context).colorScheme.scrim.withValues(alpha: 0.38),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 12),
              // 文字色維持寫死白色：scrim 在四套主題下恆為不透明黑，需要
              // 一個「所有主題下都固定亮」的前景色，M3 onInverseSurface
              // 會隨主題明暗翻轉、深色主題下反而是暗色，不適用（見本計劃
              // 「範圍決定」）。
              Text('匯入中...', style: TextStyle(color: Colors.white)),
            ],
          ),
        ),
      ),
    );
  }
```

- [ ] **Step 3：`_buildNormalAppBar()` 的 E-Ink 切換鈕改讀 `colorScheme.onSurface`／`colorScheme.surface`**

把：

```dart
        Container(
          margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          decoration: BoxDecoration(
            // E-Ink 開啟時全域主題一律為 _buildEinkTheme()（brightness 恆為
            // Brightness.light），不需要再判斷 brightness，固定黑底即可。
            color: widget.themeDependencies.isEinkMode ? Colors.black : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: widget.themeDependencies.isEinkMode
                  ? Colors.transparent
                  : Theme.of(context).colorScheme.outline.withValues(alpha: 0.5),
              width: 1.5,
            ),
          ),
          child: IconButton(
            key: const Key('library_eink_toggle'),
            icon: Icon(
              widget.themeDependencies.isEinkMode ? Icons.contrast : Icons.contrast_outlined,
              color: widget.themeDependencies.isEinkMode
                  ? Colors.white
                  : Theme.of(context).colorScheme.onSurface,
              size: 20,
            ),
```

改為：

```dart
        Container(
          margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          decoration: BoxDecoration(
            // E-Ink 開啟時全域主題一律為 _buildEinkTheme()（brightness 恆為
            // Brightness.light），這裡的 onSurface 在該主題下即為純黑，跟
            // 原本字面值 Colors.black 解析結果相同。
            color: widget.themeDependencies.isEinkMode
                ? Theme.of(context).colorScheme.onSurface
                : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: widget.themeDependencies.isEinkMode
                  ? Colors.transparent
                  : Theme.of(context).colorScheme.outline.withValues(alpha: 0.5),
              width: 1.5,
            ),
          ),
          child: IconButton(
            key: const Key('library_eink_toggle'),
            icon: Icon(
              widget.themeDependencies.isEinkMode ? Icons.contrast : Icons.contrast_outlined,
              // 同理，E-Ink 主題下 surface 即為純白，跟原本字面值
              // Colors.white 解析結果相同。
              color: widget.themeDependencies.isEinkMode
                  ? Theme.of(context).colorScheme.surface
                  : Theme.of(context).colorScheme.onSurface,
              size: 20,
            ),
```

- [ ] **Step 4：重新執行測試確認通過**

Run: `flutter test test/screens/library_screen_test.dart`
Expected: 全數 PASS（無回歸）。

- [ ] **Step 5：commit**

```bash
git add app/lib/screens/library_screen.dart
git commit -m "$(cat <<'EOF'
refactor(epic-35): library_screen.dart 匯入中遮罩/E-Ink 切換鈕遷移至 ColorScheme

匯入中遮罩背景改讀 colorScheme.scrim；E-Ink 切換鈕的黑/白底色與圖示色
改讀 colorScheme.onSurface/surface，四套主題下解析結果與原字面值相同。

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Ue4QKXFUDw4c8F8wzQJzGn
EOF
)"
```

---

### Task 5：`library_group_management_dialog.dart`——刪除文字色遷移＋新測試

**Files:**
- Modify: `app/lib/screens/library_group_management_dialog.dart`（原始行號 165-176）
- Test: `app/test/screens/library_group_management_dialog_test.dart`

**Interfaces:**
- Consumes：`resolveThemeData()`（Issue 2）；`FakeLibraryRepository.renameGroup()` 既有行為——重新命名為已存在的分類名稱時拋出 `LibraryRepositoryException('分類「$newName」已存在')`（`app/test/support/fake_library_repository.dart:117-118`，既有實作，本 Task 不修改）。
- Produces：無新公開介面，`LibraryGroupManagementDialog` 公開建構參數（`repository`／`initialGroups`）不變。

- [ ] **Step 1：寫失敗的測試**

在 `app/test/screens/library_group_management_dialog_test.dart` 檔案開頭加入 import：

把：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:elinkbook/screens/library_group_management_dialog.dart';

import '../support/fake_library_repository.dart';
```

改為：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:elinkbook/screens/library_group_management_dialog.dart';
import 'package:elinkbook/theme/app_theme.dart';
import 'package:elinkbook/theme/app_theme_data.dart';

import '../support/fake_library_repository.dart';
```

在既有 `void main() { ... }` 內、既有唯一一則 `testWidgets` 之後，新增這則測試：

```dart
  testWidgets('重新命名為已存在的分類名稱時，錯誤訊息文字色為 colorScheme.error',
      (tester) async {
    final repository = FakeLibraryRepository();
    await repository.upsertGroup('A');
    await repository.upsertGroup('B');
    final groups = await repository.listGroups();
    final theme = resolveThemeData(theme: AppTheme.light, isEinkMode: false);

    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => LibraryGroupManagementDialog(
                    repository: repository,
                    initialGroups: groups,
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('library_group_rename_button_A')));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const Key('library_group_rename_field')), 'B');
    await tester.tap(find.byKey(const Key('library_group_rename_confirm')));
    await tester.pumpAndSettle();

    final errorText = tester.widget<Text>(find.text('分類「B」已存在'));
    expect(errorText.style?.color, theme.colorScheme.error);
  });
```

- [ ] **Step 2：執行測試確認失敗**

Run: `flutter test test/screens/library_group_management_dialog_test.dart`
Expected: 新測試 FAIL——`errorText.style?.color` 目前是 `Colors.red`（`Color(0xFFF44336)`），不等於 `theme.colorScheme.error`（晴空藍天主題 `Color(0xFFEF4444)`）。

- [ ] **Step 3：修改 `library_group_management_dialog.dart`，把 `Colors.red` 改為 `colorScheme.error`**

把：

```dart
              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
```

改為：

```dart
              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    _errorMessage!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
```

- [ ] **Step 4：重新執行測試確認通過**

Run: `flutter test test/screens/library_group_management_dialog_test.dart`
Expected: 兩則測試（既有＋新增）皆 PASS。

- [ ] **Step 5：commit**

```bash
git add app/lib/screens/library_group_management_dialog.dart app/test/screens/library_group_management_dialog_test.dart
git commit -m "$(cat <<'EOF'
refactor(epic-35): library_group_management_dialog.dart 刪除錯誤文字色遷移至 colorScheme.error

分類重新命名/刪除失敗時的錯誤訊息文字色改讀 colorScheme.error，取代
寫死的 Colors.red，新增測試驗證色值來源。

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Ue4QKXFUDw4c8F8wzQJzGn
EOF
)"
```

---

### Task 6：全專案驗證收尾

**Files:**
- 無新增/修改檔案（純驗證）

**Interfaces:**
- 無

- [ ] **Step 1：執行完整 `flutter test`**

Run: `flutter test`
Expected: 全專案測試（含 Task 1-5 新增/修改的測試）全數 PASS，無回歸。若有非本 Issue 範圍內的既存失敗，記錄下來但不在本 Issue 修復（比照 `issues.md` Issue 4 收尾階段的處理原則：若發現本計劃遺漏、屬本 Issue 範圍內的失敗，回頭補 Task 修正，不可略過）。

- [ ] **Step 2：執行 `flutter analyze`**

Run: `flutter analyze`
Expected: 輸出 `No issues found!`。

- [ ] **Step 3：確認四個檔案內無殘留字面顏色**

Run（在 `app/` 目錄下）：

```bash
grep -n "Colors\.\(grey\|black\|white\|red\)" lib/library/widgets/book_cover.dart lib/screens/layout_preset_book_picker_screen.dart lib/screens/library_screen.dart lib/screens/library_group_management_dialog.dart
```

Expected: 只剩下本計劃「範圍決定」段落明確列為「維持字面值」的 3 處 `Colors.white`（`book_cover.dart` 雲朵圖示、`layout_preset_book_picker_screen.dart` 與 `library_screen.dart` 各一處選取指示圖示未選取狀態色）與 `library_screen.dart` 匯入中遮罩的 1 處 `Colors.white`，共 4 處；不應再出現任何其他 `Colors.grey`／`black45`／`black54`／`black38`／`black`／`red` 字面值。

---

## Execution Handoff

計劃完成，已存至 `docs/epics/epic-35-design-system-tokens/plans/plan-issue-6.md`。兩種執行方式：

1. **Subagent-Driven（建議）**——每個 Task 派一個全新 subagent 執行，Task 間逐次審查、快速迭代。
2. **Inline Execution**——在目前對話中依序執行，分批次搭配檢查點。

你想用哪一種？
