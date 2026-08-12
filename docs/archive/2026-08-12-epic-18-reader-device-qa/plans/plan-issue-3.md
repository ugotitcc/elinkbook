# Issue 3：書架封面格數依螢幕方向自適應（直立 3／橫放 4） 實作計劃

> **給執行者（agentic worker）的提示：** 建議使用 `superpowers:subagent-driven-development`（推薦）或 `superpowers:executing-plans` 逐工單執行本計劃。工單內的步驟以核取方塊（`- [ ]`）追蹤完成狀態。

**目標：** 讓 `LibraryScreen` 的書架格狀檢視（grid view）封面格數依螢幕方向動態調整——直立（portrait）3 欄、橫放（landscape）4 欄，取代目前寫死的固定 6 欄，並在裝置旋轉時即時反映新欄數，不需要重新導航或重建整個畫面。

**架構：** `_buildBookList()`（`app/lib/screens/library_screen.dart`）內的 `GridView.builder` 目前使用 `const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 6, ...)`。改為在建構 `gridDelegate` 前，透過 `MediaQuery.orientationOf(context)` 讀取目前螢幕方向，計算出 `crossAxisCount`（`Orientation.landscape` → 4，其餘 → 3），並移除該 `SliverGridDelegateWithFixedCrossAxisCount` 建構式的 `const`（因為 `crossAxisCount` 現在是執行期變數，非編譯期常數）。用 `MediaQuery.orientationOf(context)`（而非 `MediaQuery.of(context).orientation`）是刻意選擇——前者只在 `MediaQueryData.orientation` 這個 aspect 改變時才觸發 rebuild，後者會對整個 `MediaQueryData` 註冊依賴，鍵盤彈出（`viewInsets`）、系統字體縮放（`textScaler`）等無關變化也會連帶觸發 `LibraryScreen` 重建（已對照本機安裝的 Flutter SDK 原始碼 `media_query.dart:1562` 確認此 API 存在且行為如上）。`_buildBookList()` 是 `_LibraryScreenState`（`State<LibraryScreen>`）的既有方法，本身已可透過 `this.context` 存取到 `BuildContext`，不需要新增參數或修改呼叫端（`build()` 內既有的 `_buildBookList(books)` 呼叫，`library_screen.dart:358`，維持不變）。`orientation` 變動（含裝置旋轉）會讓 `_LibraryScreenState` 自動 rebuild，`_buildBookList()` 因此會用新的 `orientation` 重新計算 `crossAxisCount`，不需要額外的監聽或 `setState()`。

**Tech Stack：** Flutter/Dart，`flutter_test` widget test（純 Dart，不需裝置）。

## Global Constraints

- 只調整 `_buildBookList()` 內 grid view 的 `crossAxisCount` 計算方式，`ListView`（列表視圖，`_viewMode == LibraryViewMode.list` 分支）與其餘 `LibraryScreen` 邏輯（排序、篩選、匯入、選取模式等）完全不受影響、不修改。
- `childAspectRatio`（目前 `0.62`）在本計劃**維持不變**——`childAspectRatio` 是套用在「每一格」的寬高比，與欄數（`crossAxisCount`）無關（每格寬度＝可用寬度 / 欄數，高度＝寬度 / `childAspectRatio`），欄數變少不會讓封面比例跑掉，只會讓每格等比例放大。是否仍需要微調留待 Task 3 真機視覺確認，若需要調整必須記錄新數值與理由（見 Task 3 Step 3 的具體決策規則），不得含糊帶過。
- `crossAxisSpacing`／`mainAxisSpacing`（Task 2，計畫審查建議、非必要）起始建議值為 `8`／`12`，僅為起始值，實際數值依真機視覺效果調整（比照 Issue 2/3 既有慣例）。
- 真機驗收裝置固定為 `3CEF42ECD491687`。

---

## 檔案結構

本計劃只修改單一檔案：

- **修改：** `app/lib/screens/library_screen.dart`（`_buildBookList()` 方法，約第 581-618 行，本次異動集中在第 584-590 行的 `GridView.builder`／`gridDelegate` 建構）

---

### Task 1：書架封面格數依螢幕方向動態調整（3/4 欄）

**Files:**
- Modify: `app/lib/screens/library_screen.dart:581-590`
- Test: `app/test/screens/library_screen_test.dart`

**Interfaces:**
- Consumes: 既有 `MediaQuery.orientationOf(BuildContext context)`（Flutter 內建 API，回傳 `Orientation`，無需新增依賴；只在 `orientation` 這個 aspect 改變時才觸發 rebuild，比 `MediaQuery.of(context).orientation` 依賴範圍更窄）。
- Produces: 無新的對外可呼叫函式，純 `_buildBookList()` 內部 `crossAxisCount` 計算方式調整。

- [ ] **Step 1: 確認現況**

執行：
```bash
grep -n "_buildBookList" -A 10 app/lib/screens/library_screen.dart | head -12
```

預期看到（約第 581-590 行）：
```dart
  Widget _buildBookList(List<Book> books) {
    final selectedIds = _selectedBookIds;
    if (_viewMode == LibraryViewMode.grid) {
      return GridView.builder(
        key: const Key('library_grid_view'),
        padding: const EdgeInsets.all(8),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 6,
          childAspectRatio: 0.62,
        ),
```

- [ ] **Step 2: 撰寫會失敗的測試**

在 `app/test/screens/library_screen_test.dart` 找到既有測試「有書籍時，書架 grid 呈現正確渲染書籍項目（標題、進度固定 0%）」（`grep -n "有書籍時，書架 grid 呈現正確渲染書籍項目" app/test/screens/library_screen_test.dart` 確認行號，目前約第 95-113 行），在其後新增 3 個測試：

```dart
  testWidgets('直立（高 > 寬）時，書架封面格數為 3 欄', (tester) async {
    // 800×1200：寬 < 高，MediaQuery.orientation 判定為 portrait。
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final book = _testBook(id: '1', title: '紅樓夢');
    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: [book]),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final delegate = tester
            .widget<GridView>(find.byKey(const Key('library_grid_view')))
            .gridDelegate
        as SliverGridDelegateWithFixedCrossAxisCount;
    expect(delegate.crossAxisCount, 3);
  });

  testWidgets('橫放（寬 > 高）時，書架封面格數為 4 欄', (tester) async {
    // 1200×800：寬 > 高，MediaQuery.orientation 判定為 landscape。
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final book = _testBook(id: '1', title: '紅樓夢');
    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: [book]),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final delegate = tester
            .widget<GridView>(find.byKey(const Key('library_grid_view')))
            .gridDelegate
        as SliverGridDelegateWithFixedCrossAxisCount;
    expect(delegate.crossAxisCount, 4);
  });

  testWidgets(
      '裝置旋轉（MediaQuery 從直立變橫放）後，書架封面欄數即時從 3 變為 4，不需要重新導航或重建整個畫面',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final book = _testBook(id: '1', title: '紅樓夢');
    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: [book]),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pumpAndSettle();

    SliverGridDelegateWithFixedCrossAxisCount currentDelegate() =>
        tester
                .widget<GridView>(find.byKey(const Key('library_grid_view')))
                .gridDelegate
            as SliverGridDelegateWithFixedCrossAxisCount;

    expect(currentDelegate().crossAxisCount, 3);

    // 同一個 pumpWidget 之後直接改變 view 尺寸並重新 pump，模擬裝置旋轉，
    // 不重新導航、不重建 LibraryScreen（比照既有 reader_screen_test.dart
    // 對 tester.view.physicalSize 的既有使用模式）。
    tester.view.physicalSize = const Size(1200, 800);
    await tester.pumpAndSettle();

    expect(currentDelegate().crossAxisCount, 4);
  });
```

- [ ] **Step 3: 執行測試，確認失敗**

執行：
```bash
cd app && flutter test test/screens/library_screen_test.dart --plain-name "書架封面格數"
```
預期：3 項皆 FAIL——目前 `crossAxisCount` 寫死為 `6`，`expect(delegate.crossAxisCount, 3)`／`expect(delegate.crossAxisCount, 4)` 皆不成立。

- [ ] **Step 4: 實作修正**

修改 `app/lib/screens/library_screen.dart` 的 `_buildBookList()`（第 581-590 行）：

```dart
  Widget _buildBookList(List<Book> books) {
    final selectedIds = _selectedBookIds;
    if (_viewMode == LibraryViewMode.grid) {
      final orientation = MediaQuery.orientationOf(context);
      final crossAxisCount = orientation == Orientation.landscape ? 4 : 3;
      return GridView.builder(
        key: const Key('library_grid_view'),
        padding: const EdgeInsets.all(8),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          childAspectRatio: 0.62,
        ),
```

（僅第 584-590 行有異動：新增 2 行方向判斷、`SliverGridDelegateWithFixedCrossAxisCount` 移除 `const`、`crossAxisCount: 6` 改為 `crossAxisCount: crossAxisCount`；`itemCount`／`itemBuilder` 以下維持不動。）

- [ ] **Step 5: 執行測試，確認通過**

執行：
```bash
cd app && flutter test test/screens/library_screen_test.dart --plain-name "書架封面格數|裝置旋轉"
```
預期：4 項（3 個新測試＋既有的「裝置旋轉」若有同名既有測試需一併確認不衝突）皆 PASS。

- [ ] **Step 6: 執行全部既有測試回歸**

執行：
```bash
cd app && flutter analyze
cd app && flutter test
```
預期：`flutter analyze` 顯示 `No issues found!`；`flutter test` 全數通過（含既有「有書籍時，書架 grid 呈現正確渲染書籍項目」等測試，該測試未指定特定 viewport，會沿用 `flutter_test` 預設視窗尺寸 800×600——寬 > 高、屬於 landscape，本次修正後會是 4 欄，但該測試本身未斷言 `crossAxisCount`，不受影響）。

- [x] **Step 7: Commit**

```bash
git add app/lib/screens/library_screen.dart app/test/screens/library_screen_test.dart
git commit -m "feat(epic-18): Issue 3 書架封面格數依螢幕方向自適應（直立 3／橫放 4）"
```

---

### Task 2：補上欄格間距，避免封面互相緊貼（審查建議，非必要）

> 本 Task 為 Issue 描述中「審查建議（Nice to have，非必要）」項目：欄數從 6 降為 3／4 後，每欄變寬，若沿用目前緊貼排列可能顯得擁擠。實作者可與人類確認後決定是否納入本次一併完成，或另行拆出後續工單。

**Files:**
- Modify: `app/lib/screens/library_screen.dart:584-590`（Task 1 完成後的版本）
- Test: `app/test/screens/library_screen_test.dart`

**Interfaces:**
- Consumes: Task 1 完成後的 `crossAxisCount` 計算邏輯。
- Produces: 無新的對外可呼叫函式，純 `gridDelegate` 建構參數新增 `crossAxisSpacing`／`mainAxisSpacing`。

- [ ] **Step 1: 確認現況**

執行：
```bash
grep -n "gridDelegate" -A 4 app/lib/screens/library_screen.dart
```
預期看到 Task 1 完成後的版本（`crossAxisCount: crossAxisCount, childAspectRatio: 0.62,`），尚未含 `crossAxisSpacing`／`mainAxisSpacing`。

- [ ] **Step 2: 撰寫會失敗的測試**

在 `app/test/screens/library_screen_test.dart` 新增（緊接 Task 1 新增的 3 個測試之後）：

```dart
  testWidgets('書架封面格狀檢視含欄格間距，避免封面互相緊貼', (tester) async {
    final book = _testBook(id: '1', title: '紅樓夢');
    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: [book]),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final delegate = tester
            .widget<GridView>(find.byKey(const Key('library_grid_view')))
            .gridDelegate
        as SliverGridDelegateWithFixedCrossAxisCount;
    expect(delegate.crossAxisSpacing, 8);
    expect(delegate.mainAxisSpacing, 12);
  });
```

- [ ] **Step 3: 執行測試，確認失敗**

執行：
```bash
cd app && flutter test test/screens/library_screen_test.dart --plain-name "欄格間距"
```
預期：FAIL——`SliverGridDelegateWithFixedCrossAxisCount` 預設 `crossAxisSpacing`/`mainAxisSpacing` 皆為 `0`，與斷言的 `8`/`12` 不符。

- [ ] **Step 4: 實作修正**

修改 `app/lib/screens/library_screen.dart` 的 `gridDelegate`：

```dart
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          childAspectRatio: 0.62,
          crossAxisSpacing: 8,
          mainAxisSpacing: 12,
        ),
```

- [ ] **Step 5: 執行測試，確認通過**

執行：
```bash
cd app && flutter test test/screens/library_screen_test.dart --plain-name "欄格間距"
```
預期：PASS。

- [ ] **Step 6: 執行全部既有測試回歸**

執行：
```bash
cd app && flutter analyze
cd app && flutter test
```
預期：`flutter analyze` 顯示 `No issues found!`；`flutter test` 全數通過。

- [x] **Step 7: Commit**

```bash
git add app/lib/screens/library_screen.dart app/test/screens/library_screen_test.dart
git commit -m "feat(epic-18): Issue 3 Task 2 書架封面格狀檢視補上欄格間距"
```

---

### Task 3：真機驗收

**Files:** 無程式碼異動（純真機人工驗證）。

**Interfaces:**
- Consumes: Task 1（必要）／Task 2（若一併完成）完成後的 `library_screen.dart`。
- Produces: 驗收結果記錄（供合併前的程式碼審查／`issues.md` Issue 3 狀態更新引用）。

- [x] **Step 1: 安裝最新 debug APK 至真機 `3CEF42ECD491687`**

```bash
cd app && flutter build apk --debug
adb -s 3CEF42ECD491687 install -r build/app/outputs/flutter-apk/app-debug.apk
```

- [x] **Step 2: 驗證直立／橫放格數與旋轉即時切換**

1. 匯入至少 4-6 本書籍，確保書架有足夠封面可觀察排列。
2. 裝置維持直立，確認書架封面為 3 欄一列。
3. 旋轉裝置為橫放，確認**不需要重新進入書架畫面**，封面欄數即時變為 4 欄一列。
4. 旋轉回直立，確認欄數即時變回 3 欄。
5. 記錄：Pass/Fail + 截圖佐證（直立、橫放各一張）。

**驗收結果：Pass。** 直立 3 欄、橫放 4 欄，旋轉裝置時欄數即時切換、未重新進入書架畫面。截圖佐證：`tmp/epic-18/3x4_直排.png`／`tmp/epic-18/3x4_橫排.png`。

- [x] **Step 3: 視覺確認 `childAspectRatio` 與欄格間距，必要時調整**

**若已完成 Task 2**：本步驟必須以「已套用 `crossAxisSpacing: 8`／`mainAxisSpacing: 12` 之後」的最終畫面為準做視覺判斷——間距會改變每格實際可繪製的寬高比例，`childAspectRatio` 與間距必須當作同一次視覺評估的組合結果一併判斷，不可先單獨評估 `childAspectRatio`（假設無間距）、事後才疊加間距檢查，否則兩者互相影響會導致評估基準不一致。

1. 分別在直立（3 欄）與橫放（4 欄）下觀察封面比例是否明顯過寬或過窄（例如封面圖片本身比例被拉伸變形、或每格留白多到不成比例），並同時觀察封面間距是否恰當（不擁擠、也不會因間距過大導致單列可視封面數量減少到需要捲動才能看到下一列的異常情況）。
2. **決策規則（`childAspectRatio`）**：若封面比例目視正常（無明顯拉伸/擠壓、書名文字無異常換行溢出），`childAspectRatio` 維持 `0.62` 不動，Pass。若封面明顯拉伸/擠壓，將 `library_screen.dart` 的 `childAspectRatio` 調整為視覺正確的數值（例如常見書籍封面比例 2:3 對應約 `0.667`），並在 commit message 與 `issues.md` Issue 3 狀態更新中記錄新數值與調整理由（不得只記錄「已調整」而不寫具體數值）。
3. **決策規則（間距，僅當已完成 Task 2）**：若間距目視正常，`crossAxisSpacing`/`mainAxisSpacing` 維持 `8`/`12` 不動，Pass。若需調整，依同樣規則記錄新數值與理由。
4. 記錄：Pass/Fail + 截圖佐證。

**驗收結果：Pass。** 已在套用 `crossAxisSpacing: 8`／`mainAxisSpacing: 12` 之後的最終畫面上一併評估，直立/橫放下封面比例與間距皆目視正常（無明顯拉伸/擠壓、書名文字無異常換行溢出、封面間不擁擠），`childAspectRatio` 維持 `0.62`、`crossAxisSpacing`/`mainAxisSpacing` 維持 `8`/`12` 皆不調整。本步驟未額外留存截圖。

- [x] **Step 4: 既有書架功能回歸確認**

1. 切換至列表檢視（`library_list_view`），確認不受本次改動影響。
2. 確認排序（最後閱讀／建立時間／作者／書名）、分類篩選、批次選取等既有功能正常。
3. 記錄：Pass/Fail。

**驗收結果：Pass。** 列表檢視、排序（最後閱讀／建立時間／作者／書名）、分類篩選、批次選取皆確認正常，未受本次改動影響。本步驟未額外留存截圖。

- [x] **Step 5: 記錄驗收結果**

供後續程式碼審查與 `docs/epics/epic-18-reader-device-qa/issues.md` Issue 3 狀態更新引用；結果已同步記錄於本檔案 Step 2-4 與 `issues.md` Issue 3 條目。

---

## 相關佐證

- `design.md`「使用者回報項目 3」
- `tmp/sample/書櫃首頁範例.png`（原始視覺參考範例）
