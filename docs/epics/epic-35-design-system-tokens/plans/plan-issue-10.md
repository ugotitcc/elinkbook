# Epic 35 — Issue 10：真機驗證後續追蹤（Dark outline 不可辨識／封面色塊高度不一致／雲端畫面缺口）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修正 2026-09-04 真機驗證發現的 2 項真實缺陷（書架 E-Ink 切換鈕邊框在 Dark 主題下不可辨識；分類拼貼格內封面圖片格與佔位符格渲染高度不保證一致），並補齊 `remote_catalog_screen.dart`／`cloud_browser_screen.dart` 兩處雲端瀏覽畫面的封面佔位符缺口（改用 Issue 9 新增的 `CoverPlaceholder` 共用元件，取代目前純 `Icon` 佔位、無底色／無 E-Ink 外框／無書名縮略的做法，完整落實 `DESIGN.md` §8.2）。

**Architecture:** 3 個 Task，彼此互相獨立（不同檔案、無共享狀態），可任意順序執行。Task 1 是單行色值角色替換（`colorScheme.outline` → `colorScheme.onSurface`）。Task 2 修正 `_GroupGridTile` 內部 `Row` 的 cross-axis 約束問題（新增 `crossAxisAlignment: CrossAxisAlignment.stretch`）。Task 3 把 `remote_catalog_screen.dart`／`cloud_browser_screen.dart` 的 `_buildThumbnail()` 佔位分支改接 `CoverPlaceholder`。最後一個 Task 完成時跑一次全套 `flutter test`＋`flutter analyze` 確認無回歸。

**Tech Stack:** Flutter／Dart，既有 `ColorScheme.onSurface`（Issue 2 已對齊 `DESIGN.md`）、既有 `CoverPlaceholder`（Issue 9 新增）、`CrossAxisAlignment.stretch`（Flutter 標準 API，本工單首次在這個檔案使用）。不新增任何 pub 套件依賴。

**Spec:** `docs/epics/epic-35-design-system-tokens/issues.md` Issue 10；`docs/epics/epic-35-design-system-tokens/reviews/real-device-verification-checklist.md`（2026-09-04 真機測試結果，項目 1，Task 1 的來源）；`issues.md` Issue 10 背景項目 2（分類拼貼格封面/佔位符格高度不一致，Task 2 的來源，根因已於規劃階段以 widget test 重現確認，見 Task 2「Discovery 發現」段落——checklist 本身未逐項記錄此觀察，不宜引用特定項目編號佐證）；`DESIGN.md` §8.2（封面佔位符規範，Task 3 的來源，含書名文字微型縮略要求）。

## Global Constraints

- 本工單只碰 `app/lib/screens/library_screen.dart`、`app/lib/screens/remote_catalog_screen.dart`、`app/lib/screens/cloud_browser_screen.dart` 三個檔案，及其對應測試檔（`app/test/screens/library_screen_test.dart`、`app/test/screens/remote_catalog_screen_test.dart`、`app/test/screens/cloud_browser_screen_test.dart`，皆為既有檔案新增/修改測試，不新增測試檔）。
- **不寫死顏色**：Task 1 的邊框顏色一律 `colorScheme.onSurface`（角色引用），不得使用 `Colors.xxx` 字面值，符合本 Epic 全程慣例。
- **不重新設計** `CoverPlaceholder` 本身（Issue 9 已定案凍結其內部邏輯與視覺參數）——Task 3 只是把既有呼叫端（`remote_catalog_screen.dart`／`cloud_browser_screen.dart`）改接這顆既有元件，不修改 `app/lib/library/widgets/book_cover.dart`。
- **明確排除**：`cloud_browser_screen.dart` 的資料夾圖示分支（`Icons.folder, size: 48`，`_buildEntryTile()` 內，非 `_buildThumbnail()`）不屬於「封面佔位符」語意（資料夾本身不是書籍），不套用 `CoverPlaceholder`，維持原樣不動。
- Task 2 的根因與修法已在規劃階段以真實 widget test 驗證（見 Task 2「Discovery 發現」段落），不是臆測；`CrossAxisAlignment.stretch` 修法已實測確認可讓封面圖片格與佔位符格渲染高度完全一致（修法前 `Size(94.0, 0.0)` vs `Size(94.0, 133.2)`，修法後兩者皆為 `Size(94.0, 133.2)`）。
- 每個 Task 完成後只跑該 Task 涉及檔案的測試，不需要整套 `flutter test`；本計劃最後一個 Task（Task 3）完成時才跑一次完整 `flutter test`＋`flutter analyze`（見 `CLAUDE.md`「測試執行範圍」）。
- 每個 Task 的 Step 完成後，把本檔案對應的 `- [ ]` 改成 `- [x]`。
- 提交前 `flutter analyze` 須維持「No issues found!」。
- 計劃書內「改後」程式碼片段的換行/縮排以人工排版呈現，實際落地時以 `dart format` 自動排版結果為準，不需要逐字比對縮排。
- 所有指令皆在 `app/` 目錄下執行。
- 下方各 Task「Commit」步驟的 `Co-Authored-By`／`Claude-Session` 屬名反映本計劃撰寫當下的會話資訊；若實際執行本計劃的是另一個會話（session ID 不同），執行者應改用該會話當下收到的屬名指示，不要照抄這裡的字面值。

## 動手改程式碼前的四點說明（`UI_DESIGN_RULES.md` 要求）

1. **改哪個 UI 元件**：(1) `library_screen.dart` 的 `_buildNormalAppBar()` E-Ink 切換鈕外框；(2) `library_screen.dart` 的 `_GroupGridTile`（分類拼貼格 2×2 預覽格）；(3) `remote_catalog_screen.dart`／`cloud_browser_screen.dart` 的 `_buildThumbnail()` 無縮圖／載入中／錯誤三種佔位分支。
2. **為什麼要改**：(1) 真機驗證確認 Dark 主題下 `outline` 疊在 AppBar `surface` 上對比不足，肉眼不可辨識；(2) 真機驗證發現分類拼貼格內封面圖片格與無封面佔位符格渲染高度不一致，經 Discovery 確認根因是 `Row` 預設 `crossAxisAlignment.center` 給子項目寬鬆（非強制）高度約束，導致內容各自決定高度；(3) `DESIGN.md` §8.2 封面佔位符規範（底色＋E-Ink 外框＋書名文字微型縮略）目前只覆蓋書架／分類拼貼格，雲端瀏覽畫面的同款佔位符完全沒有這三個視覺元素，是 Issue 9 收尾時發現、明確排除於該工單範圍外的殘留缺口（審查修正 I1：初版計劃原打算只補底色與外框、略過書名縮略，經審查發現 `OpdsEntry`/`CloudFileEntry` 皆有現成標題欄位可用，改為三者一併補齊）。
3. **哪些畫面依賴它**：書架主畫面（AppBar E-Ink 切換鈕、分類拼貼格）；Calibre OPDS 遠端書庫瀏覽畫面（`RemoteCatalogScreen`）；Google Drive／OneDrive 雲端瀏覽畫面（`CloudBrowserScreen`）。
4. **是否影響 business logic**：不影響。三處改動皆為純視覺渲染調整——色值角色替換、Row 佈局約束修正、佔位符元件替換——不改變任何資料模型、下載/選取邏輯、縮圖快取行為。

---

### Task 1：Dark 主題 `outline` 疊色修正 — 書架 E-Ink 切換鈕邊框改參照 `onSurface`

**Files:**
- Modify: `app/lib/screens/library_screen.dart:757-762`
- Test: `app/test/screens/library_screen_test.dart`（新增 1 則測試，加在現有「LibraryScreen 在 E-Ink 模式開啟與關閉時，切換按鈕具備明確狀態容器與 tooltip」測試之後，約第 4328 行後）

**Interfaces:**
- Consumes：既有 `ColorScheme.onSurface`（Issue 2 已對齊 `DESIGN.md`，各主題皆有明確值）。
- Produces：無新介面，本 Task 不影響其他 Task。

**現況程式碼**（`library_screen.dart:743-780` 內，`_buildNormalAppBar()`）：

```dart
        Container(
          margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          decoration: BoxDecoration(
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
            ...
```

- [ ] **Step 1：寫失敗測試**

在 `app/test/screens/library_screen_test.dart` 現有「LibraryScreen 在 E-Ink 模式開啟與關閉時，切換按鈕具備明確狀態容器與 tooltip」測試（約第 4299-4328 行）之後，新增：

```dart
  testWidgets(
    'LibraryScreen 在 Dark 主題、E-Ink 關閉時，切換鈕外框改參照 onSurface'
    '（避免 outline 疊色在 Dark surface 上對比不足，2026-09-04 真機驗證確認'
    '不可辨識，見 reviews/real-device-verification-checklist.md 項目 1）',
    (tester) async {
      final colorScheme =
          resolveThemeData(theme: AppTheme.dark, isEinkMode: false).colorScheme;
      await tester.pumpWidget(
        MaterialApp(
          theme: resolveThemeData(theme: AppTheme.dark, isEinkMode: false),
          home: LibraryScreen(
            repository: FakeLibraryRepository(),
            importService: FakeBookImportService(),
            prefsManager: prefsManager,
          ),
        ),
      );

      final container = tester.widget<Container>(
        find
            .ancestor(
              of: find.byKey(const Key('library_eink_toggle')),
              matching: find.byType(Container),
            )
            .first,
      );
      final decoration = container.decoration as BoxDecoration;
      final border = decoration.border as Border;
      expect(border.top.color, colorScheme.onSurface.withValues(alpha: 0.5));
    },
  );
```

- [ ] **Step 2：執行測試確認失敗**

Run: `flutter test test/screens/library_screen_test.dart --plain-name "Dark 主題、E-Ink 關閉時"`
Expected: FAIL — 斷言 `border.top.color` 等於 `colorScheme.onSurface.withValues(alpha: 0.5)`，但目前程式碼實際解析出的是 `colorScheme.outline.withValues(alpha: 0.5)`，Dark 主題下兩個角色數值不同，斷言不成立。

- [ ] **Step 3：修正程式碼**

`library_screen.dart:760` 由：

```dart
                  : Theme.of(context).colorScheme.outline.withValues(alpha: 0.5),
```

改為：

```dart
                  : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
```

- [ ] **Step 4：執行測試確認通過**

Run: `flutter test test/screens/library_screen_test.dart`
Expected: 全數通過（含新增測試與既有「切換按鈕具備明確狀態容器與 tooltip」測試，後者不斷言邊框顏色，不受影響）。

- [ ] **Step 5：Commit**

```bash
git add app/lib/screens/library_screen.dart app/test/screens/library_screen_test.dart
git commit -m "$(cat <<'EOF'
fix(epic-35): 書架 E-Ink 切換鈕邊框改參照 onSurface

Dark 主題下 outline 疊在 AppBar surface 上對比不足，2026-09-04
真機驗證確認肉眼不可辨識；比照 Issue 2/5 既有手法改參照 onSurface。

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_019sQtaEfjhZd2MD4vgFzBw3
EOF
)"
```

---

### Task 2：分類拼貼格內，封面圖片格與佔位符格渲染高度不一致

**Files:**
- Modify: `app/lib/screens/library_screen.dart:1156-1174`（`_GroupGridTile.build()`）
- Test: `app/test/screens/library_screen_test.dart`（新增 1 則測試，可加在既有「點擊分類拼貼格後只顯示該分類書籍...」測試之後，約第 550 行區塊附近）

**Interfaces:**
- Consumes：既有 `BookCover`（`app/lib/library/widgets/book_cover.dart`，Issue 9 已定案，內部依 `coverPath` 是否存在分派 `Image.file` 或 `CoverPlaceholder`）；既有私有方法 `_groupTilePreviewCell(int)`（本 Task 不修改其內容，只調整外層 `Row` 的佈局約束）。
- Produces：無新介面，本 Task 不影響其他 Task。

**Discovery 發現（規劃階段已用真實 widget test 驗證，非臆測）：** `_GroupGridTile.build()` 內兩個 `Row`（`library_screen.dart:1157`、`1167`）皆使用預設 `crossAxisAlignment: CrossAxisAlignment.center`，只給 `Expanded(child: _groupTilePreviewCell(...))` **寬鬆**（非強制）的高度約束（`0..Row 可用高度`）。`CoverPlaceholder` 內部用 `Container(width: double.infinity, height: double.infinity)` 明確強制填滿可用最大高度；但 `BookCover` 在書籍有封面時渲染的 `Image.file(fit: BoxFit.cover)` **沒有**明確 `width`/`height`，其實際渲染高度依解碼後圖片本身的長寬比例與寬度約束換算而來，不保證等於 Row 可用高度——兩者在同一個 2×2 拼貼格內因此可能渲染出不同高度。

規劃階段以 `library_screen_test.dart` 相同的 `FakeLibraryRepository`／`_testBook()` 手法，建立一個分類含 2 本書（1 本有封面圖檔、1 本無封面）並實際測量兩個預覽格的 `tester.getSize()`：

- 修正前：有封面格 `Size(94.0, 0.0)`、無封面格（`CoverPlaceholder`）`Size(94.0, 133.2)`——高度明顯不一致。
- 修正後（`Row` 加上 `crossAxisAlignment: CrossAxisAlignment.stretch`）：兩者皆為 `Size(94.0, 133.2)`——完全一致。

（真機實際觀察到的方向可能因個別封面圖片的長寬比例不同而異——某些封面的計算高度可能大於或小於可用高度；`CrossAxisAlignment.stretch` 從根本消除「子項目依自身內容決定高度」的不確定性，讓兩種格子在任何封面長寬比例下皆強制等高，不需要知道使用者真機上那本書封面的確切長寬比例即可修正。）

**現況程式碼**（`library_screen.dart:1153-1177`）：

```dart
          Expanded(
            child: Column(
              children: [
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
              ],
            ),
          ),
```

- [ ] **Step 1：寫失敗測試**

在 `app/test/screens/library_screen_test.dart` 頂部既有 `_testBook()` helper 定義之後可使用的位置（例如緊接在第 550 行附近既有分類拼貼格測試之後），新增：

```dart
  testWidgets(
    '分類拼貼格內，有封面圖片的書籍格與無封面佔位符格渲染高度一致'
    '（根因見本計劃 Task 2「Discovery 發現」：_GroupGridTile 內部 Row'
    ' 預設寬鬆 cross-axis 約束，已於規劃階段以 widget test 重現）',
    (tester) async {
      final tempDir = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('group_tile_height_test'),
      ))!;
      addTearDown(() => tester.runAsync(() => tempDir.delete(recursive: true)));
      final coverFile = File('${tempDir.path}/cover.png');
      await tester.runAsync(() => coverFile.writeAsBytes(
            base64Decode(
              'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY'
              '42YAAAAASUVORK5CYII=',
            ),
          ));

      final bookWithCover = _testBook(
        id: '1',
        title: '有封面的書',
        groupName: '測試分類',
        coverPath: coverFile.path,
      );
      final bookWithoutCover = _testBook(
        id: '2',
        title: '沒有封面的書',
        groupName: '測試分類',
      );
      final repository = FakeLibraryRepository(
        initialBooks: [bookWithCover, bookWithoutCover],
      );

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

      final groupTileFinder = find.byKey(const Key('group_tile_測試分類'));
      expect(groupTileFinder, findsOneWidget);

      final cellsFinder =
          find.descendant(of: groupTileFinder, matching: find.byType(BookCover));
      expect(cellsFinder, findsNWidgets(2));
      final firstSize = tester.getSize(cellsFinder.at(0));
      final secondSize = tester.getSize(cellsFinder.at(1));
      expect(firstSize.height, secondSize.height);
    },
  );
```

需在檔案頂部 import 區塊加入（若尚未有）：`import 'dart:convert';`（`base64Decode`，檔案已於第 2 行 import `dart:convert`，本步驟免加）。

- [ ] **Step 2：執行測試確認失敗**

Run: `flutter test test/screens/library_screen_test.dart --plain-name "有封面圖片的書籍格與無封面佔位符格渲染高度一致"`
Expected: FAIL —— `firstSize.height` 與 `secondSize.height` 不相等（規劃階段實測為 `0.0` vs `133.2` 這個量級的差異，實際數字依測試環境字型/裝置像素比例可能略有出入，但兩者不相等）。

- [ ] **Step 3：修正程式碼**

`library_screen.dart:1156-1174` 兩個 `Row(` 皆加上 `crossAxisAlignment: CrossAxisAlignment.stretch`：

```dart
          Expanded(
            child: Column(
              children: [
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
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
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: _groupTilePreviewCell(2)),
                      const SizedBox(width: 2),
                      Expanded(child: _groupTilePreviewCell(3)),
                    ],
                  ),
                ),
              ],
            ),
          ),
```

- [ ] **Step 4：執行測試確認通過**

Run: `flutter test test/screens/library_screen_test.dart`
Expected: 全數通過（含新增測試；既有分類拼貼格相關測試不斷言格子高度，不受影響——本修正純粹讓 cross-axis 從「寬鬆置中」改為「強制填滿」，不改變格子本身的寬度、間距、或既有測試斷言的 `Key`／文字／圖示存在性）。

- [ ] **Step 5：Commit**

```bash
git add app/lib/screens/library_screen.dart app/test/screens/library_screen_test.dart
git commit -m "$(cat <<'EOF'
fix(epic-35): 分類拼貼格封面圖片格與佔位符格改為強制等高

_GroupGridTile 內部 Row 預設寬鬆 cross-axis 約束，讓 Image
與 CoverPlaceholder 各自決定高度，2026-09-04 真機驗證發現
兩者渲染高度不一致；改用 CrossAxisAlignment.stretch 強制
兩格在任何封面長寬比例下皆等高。

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_019sQtaEfjhZd2MD4vgFzBw3
EOF
)"
```

---

### Task 3：`remote_catalog_screen.dart`／`cloud_browser_screen.dart` 封面佔位符改接 `CoverPlaceholder`

**Files:**
- Modify: `app/lib/screens/remote_catalog_screen.dart:421-467`（`_buildThumbnail()`）
- Modify: `app/lib/screens/cloud_browser_screen.dart:392-438`（`_buildThumbnail()`）
- Test: `app/test/screens/remote_catalog_screen_test.dart`（修改既有 2 則測試的斷言）
- Test: `app/test/screens/cloud_browser_screen_test.dart`（修改既有 1 則測試的斷言）

**Interfaces:**
- Consumes：既有 `CoverPlaceholder({Key? key, required IconData icon, String? title})`（`app/lib/library/widgets/book_cover.dart`，Issue 9 已定案）。三處呼叫（無縮圖／載入中／載入失敗）皆傳入 `title`——`remote_catalog_screen.dart` 傳 `entry.title`（`OpdsEntry` 必填欄位）、`cloud_browser_screen.dart` 傳 `entry.name`（`CloudFileEntry` 必填欄位），完整落實 `DESIGN.md` §8.2「書名文字的微型縮略」要求（審查修正 I1：初版計劃誤判「沒有現成書名可縮略」而不傳，與原始碼不符，`OpdsEntry`/`CloudFileEntry` 皆有現成標題欄位，見 `reviews/review-plan-issue-10.md`）。`CoverPlaceholder` 內部門檻（`_titleRowMinHeight`/`_titleRowMinWidth`）在縮圖格過小時仍會自動隱藏文字，不需呼叫端另行判斷。
- Produces：無新介面，本 Task 不影響其他 Task。

**現況程式碼**（`remote_catalog_screen.dart:421-467`）：

```dart
  Widget _buildThumbnail(OpdsEntry entry) {
    final thumbnailUrl = entry.thumbnailUrl;
    if (thumbnailUrl == null) {
      return Center(
        child: Icon(
          Icons.book,
          key: Key('remote_catalog_thumbnail_placeholder_${entry.remoteBookId}'),
        ),
      );
    }
    return FutureBuilder<Uint8List>(
      future: widget.dependencies.thumbnailCache.fetch(
        widget.server,
        thumbnailUrl,
        buildOpdsAuthHeaders(widget.server, _password),
      ),
      // 〔審查 review-plan-issue-5.md Important 採納〕Flutter 的
      // FutureBuilder.didUpdateWidget() 只要傳入的 future 是新的物件實例
      // 就會把 connectionState 重置（不是 done），但 snapshot.data 仍保留
      // 上一輪成功的結果——這個 build() 方法每次重建都會呼叫一次
      // fetch()、產生新的 Future 實例（即使底層記憶體 LRU 幾乎立即命中），
      // 若先判斷 connectionState != done 就先回傳載入中佔位符，會讓已經
      // 載入完成的縮圖在任何無關的 setState()（例如勾選另一本書）後閃爍
      // 回佔位符一幀，在 E-Ink 螢幕上更明顯、恰好牴觸本 Issue 想解決的
      // 殘影問題——優先檢查 hasData，已有資料就直接顯示，不受
      // connectionState 短暫重置影響。
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data != null) {
          return Image.memory(
            snapshot.data!,
            key: Key('remote_catalog_thumbnail_${entry.remoteBookId}'),
            fit: BoxFit.cover,
          );
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return Center(
            key: Key('remote_catalog_thumbnail_loading_${entry.remoteBookId}'),
            child: const Icon(Icons.book),
          );
        }
        return Center(
          key: Key('remote_catalog_thumbnail_error_${entry.remoteBookId}'),
          child: const Icon(Icons.broken_image),
        );
      },
    );
  }
```

> **審查修正 I2：** 上方 `future:`／`builder:` 之間的註解區塊是既有程式碼、Step 3 動手時必須原樣保留，不可在替換佔位分支時連帶刪除——這段註解記錄了「為何優先檢查 `hasData` 而非 `connectionState`」的非顯而易見設計決策（防止 E-Ink 螢幕縮圖閃爍），刪除會讓未來維護者失去這個脈絡，見 `reviews/review-plan-issue-10.md`。

`cloud_browser_screen.dart:392-438` 的 `_buildThumbnail()` 結構完全對應（`Icons.book`/`Icons.broken_image` 用法相同，key 前綴改為 `google_drive_browser_thumbnail_...`，且沒有上述註解區塊）。

- [ ] **Step 1：修改既有測試斷言（先確認測試存在、理解現況）**

`app/test/screens/remote_catalog_screen_test.dart` 第 233-245 行「沒有縮圖的書目顯示預設圖示佔位符」測試，原本：

```dart
    expect(find.byKey(const Key('remote_catalog_thumbnail_placeholder_book-3')), findsOneWidget);
```

改為：

```dart
    final placeholderFinder =
        find.byKey(const Key('remote_catalog_thumbnail_placeholder_book-3'));
    expect(placeholderFinder, findsOneWidget);
    final placeholder = tester.widget(placeholderFinder);
    expect(placeholder, isA<CoverPlaceholder>());
    expect((placeholder as CoverPlaceholder).title, entryNoCover.title);
```

（`entryNoCover.title` 即該測試前段已建構的 `'無縮圖的書'`，審查修正 I1：斷言改讀 `entryNoCover.title` 而非重複寫死字面值，避免測試資料與斷言各自維護、日後改了 fixture 卻忘記同步改斷言。）

第 223-231 行「縮圖快取擷取失敗時顯示錯誤圖示」測試，原本：

```dart
    expect(find.byKey(const Key('remote_catalog_thumbnail_error_book-1')), findsOneWidget);
```

改為：

```dart
    final errorFinder = find.byKey(const Key('remote_catalog_thumbnail_error_book-1'));
    expect(errorFinder, findsOneWidget);
    final errorPlaceholder = tester.widget(errorFinder);
    expect(errorPlaceholder, isA<CoverPlaceholder>());
    expect((errorPlaceholder as CoverPlaceholder).title, entry1.title);
```

（`entry1.title` 即檔案頂部既有 fixture 的 `'紅樓夢'`。）

檔案頂部 import 區塊加入：

```dart
import 'package:elinkbook/library/widgets/book_cover.dart';
```

`app/test/screens/cloud_browser_screen_test.dart` 第 125-135 行「無縮圖網址的檔案顯示縮圖佔位符」測試，原本：

```dart
    expect(
      find.byKey(const Key('google_drive_browser_thumbnail_placeholder_file-1')),
      findsOneWidget,
    );
```

改為：

```dart
    final placeholderFinder = find.byKey(
      const Key('google_drive_browser_thumbnail_placeholder_file-1'),
    );
    expect(placeholderFinder, findsOneWidget);
    final placeholder = tester.widget(placeholderFinder);
    expect(placeholder, isA<CoverPlaceholder>());
    expect((placeholder as CoverPlaceholder).title, fileEntryNoThumbnail.name);
```

（`fileEntryNoThumbnail.name` 即檔案頂部既有 fixture 的 `'紅樓夢.epub'`。）

檔案頂部 import 區塊加入：

```dart
import 'package:elinkbook/library/widgets/book_cover.dart';
```

- [ ] **Step 2：執行測試確認失敗**

Run: `flutter test test/screens/remote_catalog_screen_test.dart test/screens/cloud_browser_screen_test.dart`
Expected: 3 則修改過的測試 FAIL（`isA<CoverPlaceholder>()` 不成立，目前實際 widget 是 `Icon`）；其餘既有測試維持通過。

- [ ] **Step 3：修正程式碼**

`remote_catalog_screen.dart` 頂部 import 區塊加入：

```dart
import '../library/widgets/book_cover.dart';
```

`remote_catalog_screen.dart:421-467` 的 `_buildThumbnail()` 改為：

```dart
  Widget _buildThumbnail(OpdsEntry entry) {
    final thumbnailUrl = entry.thumbnailUrl;
    if (thumbnailUrl == null) {
      return CoverPlaceholder(
        key: Key('remote_catalog_thumbnail_placeholder_${entry.remoteBookId}'),
        icon: Icons.book,
        title: entry.title,
      );
    }
    return FutureBuilder<Uint8List>(
      future: widget.dependencies.thumbnailCache.fetch(
        widget.server,
        thumbnailUrl,
        buildOpdsAuthHeaders(widget.server, _password),
      ),
      // 〔審查 review-plan-issue-5.md Important 採納〕Flutter 的
      // FutureBuilder.didUpdateWidget() 只要傳入的 future 是新的物件實例
      // 就會把 connectionState 重置（不是 done），但 snapshot.data 仍保留
      // 上一輪成功的結果——這個 build() 方法每次重建都會呼叫一次
      // fetch()、產生新的 Future 實例（即使底層記憶體 LRU 幾乎立即命中），
      // 若先判斷 connectionState != done 就先回傳載入中佔位符，會讓已經
      // 載入完成的縮圖在任何無關的 setState()（例如勾選另一本書）後閃爍
      // 回佔位符一幀，在 E-Ink 螢幕上更明顯、恰好牴觸本 Issue 想解決的
      // 殘影問題——優先檢查 hasData，已有資料就直接顯示，不受
      // connectionState 短暫重置影響。
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data != null) {
          return Image.memory(
            snapshot.data!,
            key: Key('remote_catalog_thumbnail_${entry.remoteBookId}'),
            fit: BoxFit.cover,
          );
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return CoverPlaceholder(
            key: Key('remote_catalog_thumbnail_loading_${entry.remoteBookId}'),
            icon: Icons.book,
            title: entry.title,
          );
        }
        return CoverPlaceholder(
          key: Key('remote_catalog_thumbnail_error_${entry.remoteBookId}'),
          icon: Icons.broken_image,
          title: entry.title,
        );
      },
    );
  }
```

（審查修正 I2：`future:`／`builder:` 之間的既有註解區塊原樣保留，未隨佔位分支替換而刪除。）

`cloud_browser_screen.dart` 頂部 import 區塊加入：

```dart
import '../library/widgets/book_cover.dart';
```

`cloud_browser_screen.dart:392-438` 的 `_buildThumbnail()` 依相同手法改為：

```dart
  Widget _buildThumbnail(CloudFileEntry entry) {
    final thumbnailUrl = entry.thumbnailUrl;
    if (thumbnailUrl == null) {
      return CoverPlaceholder(
        key: Key('google_drive_browser_thumbnail_placeholder_${entry.id}'),
        icon: Icons.book,
        title: entry.name,
      );
    }
    final cached = _thumbnailCache[thumbnailUrl];
    if (cached != null) {
      return Image.memory(
        cached,
        key: Key('google_drive_browser_thumbnail_${entry.id}'),
        fit: BoxFit.cover,
      );
    }
    final pending = _pendingThumbnailFetches[thumbnailUrl] ??=
        widget.client.fetchThumbnail(thumbnailUrl).then((bytes) {
      _thumbnailCache[thumbnailUrl] = bytes;
      _pendingThumbnailFetches.remove(thumbnailUrl);
      return bytes;
    });
    return FutureBuilder<Uint8List>(
      future: pending,
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data != null) {
          return Image.memory(
            snapshot.data!,
            key: Key('google_drive_browser_thumbnail_${entry.id}'),
            fit: BoxFit.cover,
          );
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return CoverPlaceholder(
            key: Key('google_drive_browser_thumbnail_loading_${entry.id}'),
            icon: Icons.book,
            title: entry.name,
          );
        }
        return CoverPlaceholder(
          key: Key('google_drive_browser_thumbnail_error_${entry.id}'),
          icon: Icons.broken_image,
          title: entry.name,
        );
      },
    );
  }
```

- [ ] **Step 4：執行測試確認通過**

Run: `flutter test test/screens/remote_catalog_screen_test.dart test/screens/cloud_browser_screen_test.dart`
Expected: 全數通過。

- [ ] **Step 5：全套驗證（本計劃最後一個 Task）**

Run: `flutter analyze`
Expected: `No issues found!`

Run: `flutter test`
Expected: 全數通過，無回歸（跟 Task 1／Task 2 合併後的完整套件一起驗證）。

- [ ] **Step 6：Commit**

```bash
git add app/lib/screens/remote_catalog_screen.dart app/lib/screens/cloud_browser_screen.dart app/test/screens/remote_catalog_screen_test.dart app/test/screens/cloud_browser_screen_test.dart
git commit -m "$(cat <<'EOF'
fix(epic-35): 雲端瀏覽畫面封面佔位符改接 CoverPlaceholder

RemoteCatalogScreen／CloudBrowserScreen 的縮圖佔位符（無縮圖／
載入中／載入失敗）先前只有裸 Icon，沒有 DESIGN.md §8.2 規範的
底色、E-Ink 外框與書名縮略；Issue 9 收尾時發現、留待本工單補齊，
改接 Issue 9 新增的 CoverPlaceholder 共用元件，並傳入 entry.title／
entry.name 完整落實書名縮略要求。

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_019sQtaEfjhZd2MD4vgFzBw3
EOF
)"
```
