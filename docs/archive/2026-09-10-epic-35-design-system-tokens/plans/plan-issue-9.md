# Epic 35 — Issue 9：封面佔位符完整重新設計（DESIGN.md §8.2：圖示／書名縮略／E-Ink 外框）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 新增一個共用元件 `CoverPlaceholder`，把 `DESIGN.md` §8.2 要求的「依格式圖示＋書名文字微型縮略＋E-Ink 模式 1.5dp 純黑實線外框」補齊到目前完全空白（`BookCover` 無封面圖分支）或只有純色塊（`library_screen.dart` 拼貼格／列表列「不足 4 本」空格）的三個佔位符呼叫點，圖示與文字大小依容器可用尺寸縮放，避免在 32×48 這種極小尺寸下擠爆。

**Architecture:** 分 3 個 Task，依賴順序執行（Task 2、3 都消費 Task 1 產出的元件）。Task 1 建立獨立、自成一體的 `CoverPlaceholder` widget 與其專屬測試檔，不碰任何既有呼叫端。Task 2 把 `BookCover`（`book_cover.dart`）的「沒有封面圖」分支改接這個新元件（Discovery 稱為「A 類」——某本書真的沒封面，有書名可縮略）。Task 3 把 `library_screen.dart` 兩處「不足 4 本」空格分支改接（Discovery 稱為「B 類」——沒有對應的書，`title` 不傳＝渲染空字串佔位列，跟 A 類佈局高度對齊），並在最後一個 Task 跑一次全套 `flutter test` 確認無回歸。

**Tech Stack:** Flutter／Dart，`LayoutBuilder`（依容器可用寬高動態調整圖示/字級，取代現行寫死 `size: 32`）、既有 `ElinkTokens.isEink`／`coverPlaceholder`（Issue 1／Issue 2 已建立，不新增欄位）、`ColorScheme.onSurfaceVariant`／`onSurface`（Issue 2 已對齊 `DESIGN.md` 色表）。不新增任何 pub 套件依賴。

**Spec:** `DESIGN.md` §8.2；`docs/epics/epic-35-design-system-tokens/issues.md` Issue 9（已於 2026-09-04 完成快速 Discovery 並定案 Solution／單元測試要求／驗收標準，本計劃逐條對應該處文字）。

## Global Constraints

- 本工單只碰 `app/lib/library/widgets/book_cover.dart`、`app/lib/screens/library_screen.dart`，及其對應測試檔 `app/test/library/widgets/book_cover_test.dart`（既有）、`app/test/library/widgets/cover_placeholder_test.dart`（新增）、`app/test/screens/library_screen_test.dart`（既有 3 則測試須同步更新斷言以反映新結構，見 Task 3——**審查修正 C1**：初版計劃誤判這個檔案「不預期需要修改」，經對照原始檔案核實是錯的，該檔案有直接斷言 `ColoredBox`／`Icon` 數量的結構測試會被本工單打壞）；不碰 `layout_preset_book_picker_screen.dart`（該檔只是呼叫 `BookCover(book: book)`，透過 Task 2 的改動自動獲得新行為，不需要另外改）；不碰 `ElinkTokens` 欄位定義（Issue 1 已定案凍結，本工單只重用既有 `isEink`／`coverPlaceholder` 兩個欄位）。
- **明確排除：** 真的有封面圖片（`Image.file(...)` 分支）不套用外框／圖示／文字——`DESIGN.md` §8.2 只規範「佔位符」；`BookCover` 右上角的雲朵下載角標（`isDownloaded == false` 時疊加，非 E-Ink 分支既有邏輯，`badgeScrim` 前景寫死白色）不受本工單影響，維持原樣不動。
- **不寫死顏色**：圖示／文字前景一律 `colorScheme.onSurfaceVariant`；E-Ink 外框顏色一律 `colorScheme.onSurface`（E-Ink 主題下該角色本身即為純黑 `0xFF000000`，用角色引用而非 `Colors.black` 字面值，符合本 Epic 全程慣例）。
- 圖示大小 `= clamp(shortSide × 0.4, 16, 40)`；字級 `= clamp(shortSide × 0.14, 9, 12)`；`shortSide = min(可用寬, 可用高)`；標題文字列僅在「可用高 ≥ 56」時渲染——四個數值皆為 Discovery 階段拍板的具體詮釋值，未經真機驗證，比照本 Epic 其餘 Issue（Issue 3／7／8）慣例，留待下一輪真機驗證確認電子紙上的可辨識度，不在本工單驗收範圍內重新調整。
- 所有 Dart 原始碼註解使用正體中文。
- 每個 Task 完成後只跑該 Task 涉及檔案的測試（見各 Task「驗證」欄），不需要整套 `flutter test`；本計劃最後一個 Task（Task 3）完成時才跑一次完整 `flutter test`＋`flutter analyze`（見 `CLAUDE.md`「測試執行範圍」）。
- 每個 Task 的 Step 完成後，把本檔案對應的 `- [ ]` 改成 `- [x]`。
- 提交前 `flutter analyze` 須維持「No issues found!」（Task 3 統一驗證）。
- 計劃書內「改後」程式碼片段的換行/縮排以人工排版呈現，實際落地時以 `dart format` 自動排版結果為準，不需要逐字比對縮排。
- 所有指令皆在 `app/` 目錄下執行。
- 下方各 Task「Commit」步驟的 `Co-Authored-By`／`Claude-Session` 屬名反映本計劃撰寫當下的會話資訊；若實際執行本計劃的是另一個會話（session ID 不同），執行者應改用該會話當下收到的屬名指示，不要照抄這裡的字面值。

## 動手改程式碼前的四點說明（`UI_DESIGN_RULES.md` 要求）

1. **改哪個 UI 元件**：新增共用元件 `CoverPlaceholder`（`app/lib/library/widgets/book_cover.dart`）；改接它的既有元件是 `BookCover`（同檔）與 `library_screen.dart` 的 `_GroupGridTile._groupTilePreviewCell()`／`_GroupListTile`（分類拼貼格「不足 4 本」的空格佔位分支）。
2. **為什麼要改**：`DESIGN.md` §8.2 要求封面佔位符要有依格式圖示＋書名文字微型縮略＋E-Ink 模式下 1.5dp 純黑實線外框，但現行 `BookCover` 只有圖示、`library_screen.dart` 兩處空格分支連圖示都沒有；E-Ink 主題下 `coverPlaceholder` 是純白，跟 E-Ink 的 `scaffoldBackgroundColor` 幾乎無法區分，佔位符會在視覺上「消失」，此為 Issue 6 最終審查發現並開立本 Issue 的直接原因。
3. **哪些畫面依賴它**：`LibraryScreen` 書架格狀／列表檢視（`BookCover` 直接顯示每本書封面或佔位符）、分類資料夾拼貼格與其列表檢視（`_GroupGridTile`／`_GroupListTile` 的「不足 4 本」空格）、`layout_preset_book_picker_screen.dart`（版面預設挑書畫面，透過 `BookCover` 間接獲得新行為）。
4. **是否影響 business logic**：不影響。純視覺佔位符渲染邏輯調整，不改變 `Book` 資料模型、不改變書籍格式判斷（`bookFormatIcon()` 沿用既有邏輯不變）、不改變分類拼貼格挑選前 4 本書的邏輯、不改變任何互動／導覽行為。

---

### Task 1：新增 `CoverPlaceholder` 共用元件

**Files:**
- Modify: `app/lib/library/widgets/book_cover.dart`（新增類別，檔案其餘內容不動）
- Test: `app/test/library/widgets/cover_placeholder_test.dart`（新增檔案）

**Interfaces:**
- Consumes：既有 `ElinkTokens`（`app/lib/theme/elink_tokens.dart`，`isEink`／`coverPlaceholder` 兩個欄位，Issue 1 已定案）；既有 `ColorScheme.onSurfaceVariant`／`onSurface`（Issue 2 已對齊 `DESIGN.md`）。
- Produces：`class CoverPlaceholder extends StatelessWidget`，建構子 `CoverPlaceholder({Key? key, required IconData icon, String? title})`（`title` 選填，`null` 代表 B 類——無對應書籍）。Task 2／Task 3 直接建構這個 widget。

- [x] **Step 1：寫失敗測試**

建立 `app/test/library/widgets/cover_placeholder_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/library/widgets/book_cover.dart';
import 'package:elinkbook/theme/app_theme.dart';
import 'package:elinkbook/theme/app_theme_data.dart';

void main() {
  Widget wrap(Widget child, {required bool isEinkMode}) {
    return MaterialApp(
      theme: resolveThemeData(theme: AppTheme.light, isEinkMode: isEinkMode),
      home: child,
    );
  }

  testWidgets('容器夠大時，圖示大小為縮放上限 40', (tester) async {
    await tester.pumpWidget(wrap(
      const SizedBox(
        width: 200,
        height: 200,
        child: CoverPlaceholder(icon: Icons.book, title: '測試書'),
      ),
      isEinkMode: false,
    ));

    final icon = tester.widget<Icon>(find.byIcon(Icons.book));
    expect(icon.size, 40.0);
  });

  testWidgets('容器很小時，圖示大小為縮放下限 16', (tester) async {
    await tester.pumpWidget(wrap(
      const SizedBox(
        width: 20,
        height: 20,
        child: CoverPlaceholder(icon: Icons.book, title: '測試書'),
      ),
      isEinkMode: false,
    ));

    final icon = tester.widget<Icon>(find.byIcon(Icons.book));
    expect(icon.size, 16.0);
  });

  testWidgets('可用高度低於 56 時，不渲染標題文字列', (tester) async {
    await tester.pumpWidget(wrap(
      const SizedBox(
        width: 100,
        height: 40,
        child: CoverPlaceholder(icon: Icons.book, title: '測試書'),
      ),
      isEinkMode: false,
    ));

    expect(find.text('測試書'), findsNothing);
  });

  testWidgets('可用高度達到 56 時，渲染標題文字列', (tester) async {
    await tester.pumpWidget(wrap(
      const SizedBox(
        width: 100,
        height: 56,
        child: CoverPlaceholder(icon: Icons.book, title: '測試書'),
      ),
      isEinkMode: false,
    ));

    expect(find.text('測試書'), findsOneWidget);
  });

  testWidgets(
      'title 為 null（B 類：無對應書籍）時渲染空字串文字列，字級與非 null 時一致（佈局高度對齊 A 類）',
      (tester) async {
    await tester.pumpWidget(wrap(
      const SizedBox(
        width: 100,
        height: 100,
        child: CoverPlaceholder(icon: Icons.book),
      ),
      isEinkMode: false,
    ));

    final emptyText = tester.widget<Text>(find.text(''));
    // shortSide = 100，字級 clamp(100*0.14=14, 9, 12) = 12。
    expect(emptyText.style?.fontSize, 12.0);
  });

  testWidgets('title 為 null（B 類）時空字串的 RenderBox 高度與非 null（A 類）完全相等'
      '（issues.md Issue 9 單元測試要求明文規定的斷言——只驗證 fontSize 數值相同不夠，'
      '因為那測不出來實作被誤改成 SizedBox.shrink() 或不同 line-height 這種同樣'
      'fontSize 但高度不同的退化寫法，見 reviews/review-plan-issue-9.md C2）',
      (tester) async {
    await tester.pumpWidget(wrap(
      const SizedBox(
        width: 100,
        height: 100,
        child: CoverPlaceholder(icon: Icons.book, title: '測試書'),
      ),
      isEinkMode: false,
    ));
    final titleHeight = tester.getSize(find.text('測試書')).height;

    await tester.pumpWidget(wrap(
      const SizedBox(
        width: 100,
        height: 100,
        child: CoverPlaceholder(icon: Icons.book),
      ),
      isEinkMode: false,
    ));
    final emptyHeight = tester.getSize(find.text('')).height;

    expect(emptyHeight, equals(titleHeight),
        reason: 'B 類空字串文字列高度必須與 A 類標題高度完全一致，才能保證圖示基準線對齊');
  });

  testWidgets('可用寬度低於門檻時（即使高度足夠），不渲染標題文字列', (tester) async {
    await tester.pumpWidget(wrap(
      const SizedBox(
        width: 20,
        height: 100,
        child: CoverPlaceholder(icon: Icons.book, title: '測試書'),
      ),
      isEinkMode: false,
    ));

    expect(find.text('測試書'), findsNothing);
  });

  testWidgets('E-Ink 模式開啟時，外框存在且顏色來自 colorScheme.onSurface（寬度 1.5）',
      (tester) async {
    await tester.pumpWidget(wrap(
      const SizedBox(
        width: 100,
        height: 100,
        child: CoverPlaceholder(icon: Icons.book, title: '測試書'),
      ),
      isEinkMode: true,
    ));

    final container = tester.widget<Container>(find.byType(Container));
    final decoration = container.decoration as BoxDecoration;
    final scheme =
        resolveThemeData(theme: AppTheme.light, isEinkMode: true).colorScheme;
    expect(decoration.border, Border.all(color: scheme.onSurface, width: 1.5));
  });

  testWidgets('非 E-Ink 模式時，無外框', (tester) async {
    await tester.pumpWidget(wrap(
      const SizedBox(
        width: 100,
        height: 100,
        child: CoverPlaceholder(icon: Icons.book, title: '測試書'),
      ),
      isEinkMode: false,
    ));

    final container = tester.widget<Container>(find.byType(Container));
    final decoration = container.decoration as BoxDecoration;
    expect(decoration.border, isNull);
  });
}
```

- [x] **Step 2：執行測試，確認失敗**

Run: `flutter test test/library/widgets/cover_placeholder_test.dart`
Expected: FAIL（編譯錯誤：`CoverPlaceholder` 這個類別尚不存在，`package:elinkbook/library/widgets/book_cover.dart` 沒有匯出這個名字）。

- [x] **Step 3：實作 `CoverPlaceholder`**

在 `app/lib/library/widgets/book_cover.dart` 檔案末尾（`class BookCover` 之後）新增：

```dart

/// 封面佔位符：依格式圖示（或呼叫端傳入的固定圖示）＋書名文字微型縮略
/// （若有）＋E-Ink 模式下的 1.5dp 純黑實線外框（`DESIGN.md` §8.2）。圖示
/// 與文字大小依容器可用尺寸縮放（`LayoutBuilder`）——這顆元件被共用在
/// 差異極大的尺寸上：書架格狀卡片、48×64 列表列、`library_screen.dart`
/// `_GroupListTile` 內小到 32×48 的縮圖皆共用同一顆元件，固定寫死尺寸會
/// 在最小尺寸下擠爆。[title] 為 `null` 代表「這裡沒有對應的書」（拼貼格／
/// 列表列「不足 4 本」的空格佔位），此時仍渲染一行空字串文字列（而非整段
/// 省略），確保跟「某本書真的沒有封面圖」（[title] 非 null）的情況視覺
/// 佈局高度一致。
class CoverPlaceholder extends StatelessWidget {
  final IconData icon;
  final String? title;

  const CoverPlaceholder({super.key, required this.icon, this.title});

  /// 標題文字列的可用高度／寬度門檻——低於任一值不渲染文字，避免在極小
  /// 尺寸下文字被擠壓到無法閱讀（審查修正 I2：初版只檢查高度，極端窄長
  /// 容器──例如寬 24／高 60──高度門檻會通過但寬度連一個省略號都容不下，
  /// 見 reviews/review-plan-issue-9.md）。具體數值未經真機驗證，見計劃書
  /// Global Constraints。
  static const _titleRowMinHeight = 56.0;
  static const _titleRowMinWidth = 36.0;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final tokens = Theme.of(context).extension<ElinkTokens>()!;

    return LayoutBuilder(
      builder: (context, constraints) {
        final shortSide = constraints.maxWidth < constraints.maxHeight
            ? constraints.maxWidth
            : constraints.maxHeight;
        final iconSize = (shortSide * 0.4).clamp(16.0, 40.0).toDouble();
        final fontSize = (shortSide * 0.14).clamp(9.0, 12.0).toDouble();
        final showTitle = constraints.maxHeight >= _titleRowMinHeight &&
            constraints.maxWidth >= _titleRowMinWidth;

        return Container(
          width: double.infinity,
          height: double.infinity,
          decoration: BoxDecoration(
            color: tokens.coverPlaceholder,
            border: tokens.isEink
                ? Border.all(color: colorScheme.onSurface, width: 1.5)
                : null,
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: iconSize, color: colorScheme.onSurfaceVariant),
                if (showTitle) ...[
                  const SizedBox(height: 4),
                  // 審查修正 I1：E-Ink 模式的 1.5dp 外框跟文字之間需要留一點
                  // 呼吸空間，否則長書名的省略號會直接貼在黑框上，在電子紙
                  // 高對比顯示下辨識度變差（見 reviews/review-plan-issue-9.md）。
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4.0),
                    child: Text(
                      title ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: fontSize,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
```

（`(shortSide * 0.4).clamp(16.0, 40.0)` 回傳型別是 `num`，Dart 不會把 `num` 隱式轉成 `double`——`.toDouble()` 是必要的，不是多餘寫法，省略會讓 `Icon(size: iconSize)`／`TextStyle(fontSize: fontSize)` 編譯失敗。）

- [x] **Step 4：執行測試，確認通過**

Run: `flutter test test/library/widgets/cover_placeholder_test.dart`
Expected: PASS（9 個測試全過）。

- [x] **Step 5：Commit**

```bash
git add app/lib/library/widgets/book_cover.dart app/test/library/widgets/cover_placeholder_test.dart
git commit -m "$(cat <<'EOF'
feat(epic-35): Issue 9 — 新增 CoverPlaceholder 共用元件（圖示/書名縮略/E-Ink 外框）

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_019sQtaEfjhZd2MD4vgFzBw3
EOF
)"
```

---

### Task 2：`BookCover` 改接 `CoverPlaceholder`（A 類：某本書無封面圖）

**Files:**
- Modify: `app/lib/library/widgets/book_cover.dart`（`BookCover.build()`，原第 38-46 行）
- Test: `app/test/library/widgets/book_cover_test.dart`

**Interfaces:**
- Consumes：Task 1 產出的 `CoverPlaceholder({required IconData icon, String? title})`；既有 `bookFormatIcon(BookFileFormat format)`（同檔既有函式，不動）。
- Produces：無新介面，`BookCover` 對外建構參數（`Book book`）不變。

- [x] **Step 1：寫失敗測試**

在 `app/test/library/widgets/book_cover_test.dart` 既有兩則測試之後新增：

```dart

  testWidgets('沒有封面圖時顯示依格式圖示與書名', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
      home: BookCover(book: _book(isDownloaded: true)),
    ));

    expect(find.byIcon(Icons.menu_book), findsOneWidget);
    expect(find.text('測試書'), findsOneWidget);
  });

  testWidgets(
      'E-Ink 模式開啟時，沒有封面圖的 BookCover 確實透傳 CoverPlaceholder 的外框'
      '（審查修正 I3：Task 1 只單元測試過 CoverPlaceholder 本身的外框邏輯，'
      'BookCover 作為對外生產元件的整合行為原本完全沒有測試保護，見'
      'reviews/review-plan-issue-9.md）', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: resolveThemeData(theme: AppTheme.light, isEinkMode: true),
      home: BookCover(book: _book(isDownloaded: true)),
    ));

    final container = tester.widget<Container>(find.byType(Container));
    final decoration = container.decoration as BoxDecoration;
    expect(decoration.border, isNotNull);
  });
```

（`_book()` 既有 helper 建構的書本 `format: BookFileFormat.epub`、`title: '測試書'`、無 `coverPath`，`bookFormatIcon(BookFileFormat.epub)` 回傳 `Icons.menu_book`。）

- [x] **Step 2：執行測試，確認失敗**

Run: `flutter test test/library/widgets/book_cover_test.dart`
Expected: FAIL（新增的 2 則測試皆紅燈：`find.text('測試書')` 找不到——`BookCover` 目前的佔位符分支只畫圖示，沒有書名文字；E-Ink 外框測試 `find.byType(Container)` 也找不到——目前是 `ColoredBox`，不是 `Container`）。

- [x] **Step 3：實作串接**

把 `app/lib/library/widgets/book_cover.dart` 的 `BookCover.build()`（原第 38-46 行）：

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
```

改為：

```dart
  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<ElinkTokens>()!;
    final coverPath = book.coverPath;
    final cover = coverPath != null && File(coverPath).existsSync()
        ? Image.file(File(coverPath), fit: BoxFit.cover)
        : CoverPlaceholder(icon: bookFormatIcon(book.format), title: book.title);
```

（`tokens` 變數繼續保留——下方雲朵下載角標的 `color: tokens.badgeScrim` 仍需要它，不是孤兒變數。）

- [x] **Step 4：執行測試，確認通過**

Run: `flutter test test/library/widgets/book_cover_test.dart`
Expected: PASS（4 個測試全過）。

- [x] **Step 5：Commit**

```bash
git add app/lib/library/widgets/book_cover.dart app/test/library/widgets/book_cover_test.dart
git commit -m "$(cat <<'EOF'
feat(epic-35): Issue 9 — BookCover 無封面圖分支改接 CoverPlaceholder（顯示書名縮略）

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_019sQtaEfjhZd2MD4vgFzBw3
EOF
)"
```

---

### Task 3：`library_screen.dart` 兩處「不足 4 本」空格改接 `CoverPlaceholder`（B 類）

**（審查修正 C1，最重要的一項）** 初版計劃誤判 `app/test/screens/library_screen_test.dart` 只是「整合層級的畫面測試，不斷言 private widget 內部渲染細節」，因此原本規定不碰這個測試檔。經審查對照原始檔案逐行核實，這個假設是錯的：該檔案在 Issue 6 就寫入了 3 則直接斷言 `ColoredBox`／`Icon` 數量的精確結構測試（`app/test/screens/library_screen_test.dart:2852-2916`／`2918-2965`／`2967-3011`），會被本 Task（其中一則甚至在 Task 2 完成當下就已經壞掉，只是 Task 2 沒有跑這個測試檔所以沒有立即發現）直接打壞——最嚴重的一則甚至會在空清單上呼叫 `.reduce()` 拋出未攔截的 `StateError`。詳見 `reviews/review-plan-issue-9.md` C1。本 Task 因此新增第 2 個修改目標：把這 3 則測試的斷言方式從「比對 `ColoredBox` 顏色」改為「比對 `CoverPlaceholder` 型別／`Icon` 種類數量」，反映 Issue 9 之後的新結構。

**Files:**
- Modify: `app/lib/screens/library_screen.dart`（`_GroupGridTile._groupTilePreviewCell()`，原第 1194-1200 行及其 4 處呼叫點原第 1159/1161/1169/1171 行；`_GroupListTile.build()`，原第 1210-1235 行）
- Modify: `app/test/screens/library_screen_test.dart`（3 則既有測試，原第 2852-2916／2918-2965／2967-3011 行；移除變成孤兒 import 的 `package:elinkbook/theme/elink_tokens.dart`，原第 27 行）

**Interfaces:**
- Consumes：Task 1 產出的 `CoverPlaceholder({required IconData icon, String? title})`（B 類不傳 `title`）。`library_screen.dart`／`library_screen_test.dart` 皆已 `import '.../book_cover.dart';`，`CoverPlaceholder` 是同檔案的公開類別，不需要新增 import。
- Produces：無新介面，兩個 private widget 對外行為（`_GroupGridTile`／`_GroupListTile` 的建構參數）不變。

- [x] **Step 1：確認基準線**

Run: `flutter test test/screens/library_screen_test.dart`
Expected: 1 個既有失敗、其餘皆 PASS。失敗的是 `分類拼貼格（格狀檢視）封面預覽區塊填滿可用高度，下方不留空白（...）`——這則測試只依賴 Task 2 已完成的改動（4 本書皆無 `coverPath`，全部經過 `BookCover` → `CoverPlaceholder`），在本 Task 開始之前就已經是紅燈，不是本 Task 造成的新回歸（Task 2 沒有跑 `library_screen_test.dart`，沒有立即發現，見上方「審查修正 C1」說明），但一併在本 Task 收尾修正。另外 2 則「不足 4 本」測試此時仍是綠燈（它們依賴的是本 Task 才要動的 `_groupTilePreviewCell`／`_GroupListTile`）——這是本 Task 動手前完整的基準線。

- [x] **Step 2：實作串接**

把 `app/lib/screens/library_screen.dart` 的 `_groupTilePreviewCell()`（原第 1194-1200 行）：

```dart
  Widget _groupTilePreviewCell(BuildContext context, int index) {
    return index < tile.previewBooks.length
        ? BookCover(book: tile.previewBooks[index])
        : ColoredBox(
            color: Theme.of(context).extension<ElinkTokens>()!.coverPlaceholder,
          );
  }
```

改為（`context` 參數在改動後不再被方法內任何一行使用，一併移除，呼叫點同步刪掉這個引數——這是本次改動造成的孤兒參數，依 `CLAUDE.md`「移除 YOUR 改動造成的孤兒」規則一併清掉）：

```dart
  Widget _groupTilePreviewCell(int index) {
    return index < tile.previewBooks.length
        ? BookCover(book: tile.previewBooks[index])
        : const CoverPlaceholder(icon: Icons.book);
  }
```

同一個 `_GroupGridTile.build()` 方法內，4 處呼叫點（原第 1159／1161／1169／1171 行）：

```dart
                      Expanded(child: _groupTilePreviewCell(context, 0)),
                      const SizedBox(width: 2),
                      Expanded(child: _groupTilePreviewCell(context, 1)),
```

```dart
                      Expanded(child: _groupTilePreviewCell(context, 2)),
                      const SizedBox(width: 2),
                      Expanded(child: _groupTilePreviewCell(context, 3)),
```

四處皆把 `_groupTilePreviewCell(context, N)` 改為 `_groupTilePreviewCell(N)`（拿掉 `context,`），改後：

```dart
                      Expanded(child: _groupTilePreviewCell(0)),
                      const SizedBox(width: 2),
                      Expanded(child: _groupTilePreviewCell(1)),
```

```dart
                      Expanded(child: _groupTilePreviewCell(2)),
                      const SizedBox(width: 2),
                      Expanded(child: _groupTilePreviewCell(3)),
```

`_GroupListTile.build()`（原第 1210-1235 行）：

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

改為（`tokens` 變數在改動後不再被使用，一併移除——同樣是本次改動造成的孤兒變數）：

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
                  : const CoverPlaceholder(icon: Icons.book),
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

- [x] **Step 3：執行既有測試，確認 3 則測試如預期紅燈（審查修正 C1）**

Run: `flutter test test/screens/library_screen_test.dart`
Expected: FAIL——3 則測試紅燈，比 Step 1 的基準線多了 2 則新失敗：
- `分類拼貼格（格狀檢視）封面預覽區塊填滿可用高度，下方不留空白（...）`：延續 Step 1 就已存在的失敗（`expect(coverBoxCount, 4)` 因為 `BookCover` 的佔位符分支在 Task 2 已改成 `CoverPlaceholder`、不再是 `ColoredBox`，實際變成 0），不是這一步新造成的。
- `分類拼貼格（格狀檢視）不足 4 本時以中性色塊佔位，名稱與本數正確顯示`：本步驟新增的失敗——`findsNWidgets(2)`（`Icon` 總數）失敗（實際 4，因為 2 個空格現在也各有一個 `Icons.book`）。
- `分類拼貼格（列表檢視）不足 4 本時以中性色塊佔位`：本步驟新增的失敗——`findsNWidgets(1)`（`Icon` 總數）失敗（實際 4，因為 3 個空格現在也各有一個 `Icons.book`）。

- [x] **Step 4：更新這 3 則測試的斷言，反映 Issue 9 之後的新結構**

第一則（`app/test/screens/library_screen_test.dart` 原第 2886-2903 行）：

```dart
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
    final bottomRowBottomY = List.generate(
      coverBoxCount,
      (i) => tester.getBottomLeft(coverBoxFinder.at(i)).dy,
    ).reduce((a, b) => a > b ? a : b);
```

改為：

```dart
    // 尺寸驗證：4 本書皆無 coverPath，BookCover 各自以 CoverPlaceholder 佔位
    // （Issue 9：內含置中的圖示/書名縮略，圖示與文字本身不會撐滿儲存格，
    // 故量測 CoverPlaceholder 本身的邊界而非圖示）；取最下面那一列（第 3/4
    // 格）佔位元件的底部，應緊接分類名稱文字的頂部（僅隔明講的
    // SizedBox(height: 4) 一點點間距），而非留下大片空白。
    final coverBoxFinder = find.descendant(
      of: tileFinder,
      matching: find.byType(CoverPlaceholder),
    );
    final coverBoxCount = tester.widgetList(coverBoxFinder).length;
    expect(coverBoxCount, 4);
    final bottomRowBottomY = List.generate(
      coverBoxCount,
      (i) => tester.getBottomLeft(coverBoxFinder.at(i)).dy,
    ).reduce((a, b) => a > b ? a : b);
```

第二則（原第 2940-2964 行）：

```dart
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

改為：

```dart
    // Issue 9：2 本書皆無 coverPath，BookCover 各自退回 CoverPlaceholder
    // （依格式圖示＋書名），拼貼格本身「不足 4 本」的 2 個空格佔位
    // （_groupTilePreviewCell 的 fallback 分支）也改用 CoverPlaceholder
    // （固定 Icons.book、不傳 title）——A/B 兩類共用同一顆元件、視覺統一，
    // 改用「格式圖示（menu_book，2 個真書）＋固定圖示（Icons.book，2 個
    // 空格）」精確區分來源，取代舊版靠 ColoredBox 色階區分的做法。
    expect(
      find.descendant(of: tileFinder, matching: find.byIcon(Icons.menu_book)),
      findsNWidgets(2),
    );
    expect(
      find.descendant(of: tileFinder, matching: find.byIcon(Icons.book)),
      findsNWidgets(2),
    );
    expect(
      find.descendant(of: tileFinder, matching: find.byType(CoverPlaceholder)),
      findsNWidgets(4),
    );
    expect(
      find.descendant(of: tileFinder, matching: find.byType(BookCover)),
      findsNWidgets(2),
    );
  });
```

第三則（原第 2990-3010 行）：

```dart
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

改為：

```dart
    // Issue 9：同上（格狀檢視版本）理由：1 本書無 coverPath 退回
    // CoverPlaceholder（依格式圖示＋書名），3 個「不足 4 本」空格也改用
    // CoverPlaceholder（固定 Icons.book、不傳 title），改用「格式圖示
    // （menu_book，1 個真書）＋固定圖示（Icons.book，3 個空格）」精確區分
    // 來源，取代舊版靠 ColoredBox 色階區分的做法。
    expect(
      find.descendant(of: tileFinder, matching: find.byIcon(Icons.menu_book)),
      findsNWidgets(1),
    );
    expect(
      find.descendant(of: tileFinder, matching: find.byIcon(Icons.book)),
      findsNWidgets(3),
    );
    expect(
      find.descendant(of: tileFinder, matching: find.byType(CoverPlaceholder)),
      findsNWidgets(4),
    );
    expect(
      find.descendant(of: tileFinder, matching: find.byType(BookCover)),
      findsNWidgets(1),
    );
  });
```

（3 個 `_testBook(...)` 呼叫皆未指定 `format`，預設值 `BookFileFormat.epub`——`bookFormatIcon(BookFileFormat.epub)` 回傳 `Icons.menu_book`，這是上面「真書 Icon 數＝menu_book 數」斷言成立的依據，見 `library_screen_test.dart:4426` 該 helper 的預設參數。）

**移除孤兒 import**：上面 3 處改動移除了這個檔案內全部 3 處（也是僅有的 3 處）`ElinkTokens` 使用，檔案頂部第 27 行 `import 'package:elinkbook/theme/elink_tokens.dart';` 因此變成孤兒 import，一併刪除（依 `CLAUDE.md`「移除 YOUR 改動造成的孤兒」規則）。

- [x] **Step 5：全專案完整驗證（本計劃最後一個 Task，比照 `CLAUDE.md`「測試執行範圍」）**

Run: `flutter test test/screens/library_screen_test.dart`
Expected: PASS（3 則更新後的測試轉綠，其餘既有測試與 Step 1 基準線相同、無回歸——`_groupTilePreviewCell`／`_GroupListTile` 的 `Key`、資料流、互動邏輯完全不變，純視覺疊加）。

Run: `flutter analyze`
Expected: `No issues found!`

Run: `flutter test`
Expected: 全數通過，無回歸。

- [x] **Step 6：Commit**

```bash
git add app/lib/screens/library_screen.dart app/test/screens/library_screen_test.dart
git commit -m "$(cat <<'EOF'
feat(epic-35): Issue 9 — library_screen.dart 拼貼格/列表列空格改接 CoverPlaceholder

_groupTilePreviewCell()/_GroupListTile「不足 4 本」空格分支改用 CoverPlaceholder
（icon: Icons.book，不傳 title），E-Ink 模式下補上 1.5dp 外框，與 BookCover 無封面圖
分支視覺一致。同步更新 library_screen_test.dart 3 則既有結構斷言（ColoredBox
色階比對 → CoverPlaceholder 型別／Icon 種類比對），移除因此變成孤兒的
elink_tokens.dart import（審查修正 C1，見 reviews/review-plan-issue-9.md）。

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_019sQtaEfjhZd2MD4vgFzBw3
EOF
)"
```

---

## 收尾備註

- 全部 3 個 Task 已完成，透過 subagent-driven-development 執行，逐 Task 審查（spec + quality）與最終整分支審查（model=opus）皆通過，**Ready to merge: Yes**。commit 範圍：`ee7f50fd`..`520ce389`（含 Task 1 修復回合 `8e403de6`）。
- **Task 3 執行期間發現並修正的計劃缺口**：計劃書原先只預期 `library_screen_test.dart` 有 3 則既有測試會因本 Issue 打壞，實際執行時發現另外 3 則也因為 Task 2（`BookCover` 顯示書名縮略）跟 `_BookGridTile`/`_BookListTile` 本身既有的書名 caption 產生合法的文字重複而失真。這 3 則已一併在 Task 3 修正（`findsOneWidget` → `findsNWidgets(2)`，其中一則用 `Element.findAncestorWidgetOfExactType<CoverPlaceholder>()` 精確排除封面佔位符的迷你標題），詳見 `.superpowers/sdd/plan-issue-9/progress.md`（SDD 執行帳本，未進版控）。
- 圖示/字級縮放比例（0.4／0.14）、標題文字列高度／寬度門檻（56dp／36dp）、文字左右內距（4dp，審查修正 I1 補上）為 Discovery／審查階段拍板的具體詮釋值，未經真機驗證，建議與本 Epic 其餘 Issue（3／7／8）已記錄的未驗證視覺細節一併排入下一輪真機驗證。最終審查另外指出 `showTitle` 門檻未隨 `MediaQuery.textScalerOf` 縮放（約 3.5 倍字級以上才會在剛好 56dp 高的容器出問題，目前不可達），一併排入同一輪真機驗證。
- **最終審查發現、明確排除於本工單範圍外的殘留事項**（建議記錄供後續參考，是否另開 Issue 由人類決定）：
  1. `DESIGN.md §8.2` 文字寫「`Icons.book` 圖示」，但實際 A 類（真書無封面）用 `bookFormatIcon()` 依格式圖示（Discovery 已定案的更好行為）——文件用詞需要更新以符合實作。
  2. `app/lib/screens/remote_catalog_screen.dart:421-464`（`_buildThumbnail`）與 `app/lib/screens/cloud_browser_screen.dart:397,429` 也是 `DESIGN.md §8.2` 管轄的封面佔位符情境，目前是裸 `Center(child: Icon(Icons.book))`，沒有底色也沒有 E-Ink 外框——正是本 Issue 想解決的「E-Ink 下佔位符會消失」問題，只是發生在另外兩個畫面。`CoverPlaceholder` 現成可以直接套用，建議另開 Issue。
  3. 無封面書籍現在螢幕報讀器會把書名唸兩次（迷你標題 + 書籍格 caption），建議之後補一層 `ExcludeSemantics`。
  4. `layout_preset_book_picker_screen.dart` 經最終審查實際查證（讀過該檔案與其測試檔），確認不受本 Issue 影響，非缺口。
