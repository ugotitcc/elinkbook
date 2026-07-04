# Issue 2 實作計劃：`ReaderScreen` 格式偵測邏輯

> **給執行的 Agent：** 建議使用 superpowers:subagent-driven-development（推薦）或 superpowers:executing-plans 逐任務執行本計劃。步驟採用核取方塊（`- [ ]`）語法追蹤進度。

**目標：** 實作純 Dart 的書籍格式偵測邏輯，以及依偵測結果分派到暫時佔位視圖的 `ReaderScreen` widget，全程可用 `flutter test` 驗證、不需模擬器。

**架構：** 格式偵測邏輯（`detectBookFormat`）獨立成一個不依賴 Flutter widget 的純函式，可用一般 `test()` 單元測試驗證，比 widget test 更快、更聚焦。`ReaderScreen` 是一個薄的 `StatelessWidget`，內部呼叫 `detectBookFormat` 並依結果顯示對應的佔位文字——這是 Issue 5 之後會把「佔位視圖」換成真正原生渲染視圖（`EpubReaderView`/`PdfReaderView`）的擴充點。

**技術棧：** Flutter（Dart）、`flutter_test`。本工單不涉及任何原生程式碼（Kotlin）或 `PlatformView`。

## 全域限制條件

- Flutter 專案位於 `app/`，套件名稱為 `elinkbook`（Issue 1 已建立，此工單延續使用）。
- 本工單**不得**引入任何原生模組整合（Readium、`PdfRenderer`）、`PlatformView`、或任何需要 Android 模擬器/裝置才能執行的測試——這些分別屬於 Issue 3、Issue 4、Issue 5。
- `detectBookFormat` 對任何輸入字串（含空字串、無副檔名、不支援的副檔名）都必須回傳明確結果，**絕不拋出例外**。
- 所有畫面上的使用者可見文字須為正體中文。
- 全部測試須能以 `flutter test`（不含 `integration_test`）跑過，不需啟動模擬器。

---

### Task 1：TDD 實作 `BookFormat` 列舉與 `detectBookFormat` 純函式

**Files:**
- Create: `app/lib/reader/book_format.dart`
- Test: `app/test/reader/book_format_test.dart`

**Interfaces:**
- Consumes: 無（起始工單，不依賴前一個工單的程式碼介面，僅依賴 Issue 1 建立的 `app/` 專案骨架）
- Produces: `enum BookFormat { epub, pdf, unknown }` 與 `BookFormat detectBookFormat(String path)` 函式，供 Task 2 的 `ReaderScreen` 使用。

- [ ] **Step 1：寫失敗測試**

建立 `app/test/reader/book_format_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/book_format.dart';

void main() {
  test('.epub 副檔名判定為 EPUB 格式', () {
    expect(detectBookFormat('book.epub'), BookFormat.epub);
  });

  test('.pdf 副檔名判定為 PDF 格式', () {
    expect(detectBookFormat('book.pdf'), BookFormat.pdf);
  });

  test('不支援的副檔名回傳 unknown', () {
    expect(detectBookFormat('book.txt'), BookFormat.unknown);
  });

  test('無副檔名的路徑回傳 unknown', () {
    expect(detectBookFormat('book'), BookFormat.unknown);
  });

  test('空字串路徑回傳 unknown（不拋出例外）', () {
    expect(detectBookFormat(''), BookFormat.unknown);
  });

  test('大寫副檔名不分大小寫皆能判定成功', () {
    expect(detectBookFormat('book.EPUB'), BookFormat.epub);
    expect(detectBookFormat('book.PDF'), BookFormat.pdf);
  });
}
```

- [ ] **Step 2：執行測試確認失敗**

Run（於 `app/` 目錄下）：
```bash
flutter test test/reader/book_format_test.dart
```
Expected: 失敗，錯誤訊息顯示找不到 `package:elinkbook/reader/book_format.dart`（該檔案尚未建立）。

- [ ] **Step 3：實作最小程式碼使測試通過**

建立 `app/lib/reader/book_format.dart`：

```dart
/// 書籍檔案格式，依副檔名偵測。
enum BookFormat { epub, pdf, unknown }

/// 依檔案路徑的副檔名判斷書籍格式（不分大小寫）。無法識別的副檔名（含無副
/// 檔名、空字串）一律回傳 [BookFormat.unknown]，絕不拋出例外。
BookFormat detectBookFormat(String path) {
  final lowerPath = path.toLowerCase();
  if (lowerPath.endsWith('.epub')) return BookFormat.epub;
  if (lowerPath.endsWith('.pdf')) return BookFormat.pdf;
  return BookFormat.unknown;
}
```

- [ ] **Step 4：執行測試確認通過**

Run：
```bash
flutter test test/reader/book_format_test.dart
```
Expected: `All tests passed!`

- [ ] **Step 5：Commit**

```bash
git add app/lib/reader/book_format.dart app/test/reader/book_format_test.dart
git commit -m "Add BookFormat detection logic with unit tests"
```

---

### Task 2：TDD 實作 `ReaderScreen`（依格式分派至佔位視圖）

**Files:**
- Create: `app/lib/screens/reader_screen.dart`
- Test: `app/test/screens/reader_screen_test.dart`

**Interfaces:**
- Consumes: `BookFormat`、`detectBookFormat(String path)`（Task 1 產出，`package:elinkbook/reader/book_format.dart`）
- Produces: `ReaderScreen({required String filePath})`（`StatelessWidget`），供 Issue 6（書架串接開書流程）與 Issue 5（把佔位視圖換成真正原生視圖）使用。此工單完成後，`ReaderScreen` 的公開介面（建構參數 `filePath`）即固定下來，後續工單只會修改其內部 `build()` 邏輯，不會變更外部呼叫方式。

- [ ] **Step 1：寫失敗測試**

建立 `app/test/screens/reader_screen_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/screens/reader_screen.dart';

void main() {
  testWidgets('EPUB 路徑顯示 EPUB 佔位畫面', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ReaderScreen(filePath: 'test/fixtures/sample.epub'),
      ),
    );

    expect(find.text('閱讀器'), findsOneWidget);
    expect(find.text('EPUB 佔位畫面（尚未接上 Readium 原生渲染）'), findsOneWidget);
  });

  testWidgets('PDF 路徑顯示 PDF 佔位畫面', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ReaderScreen(filePath: 'test/fixtures/sample.pdf'),
      ),
    );

    expect(find.text('PDF 佔位畫面（尚未接上 PdfRenderer 原生渲染）'), findsOneWidget);
  });

  testWidgets('不支援格式顯示明確錯誤訊息', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ReaderScreen(filePath: 'test/fixtures/sample.txt'),
      ),
    );

    expect(find.text('不支援的檔案格式'), findsOneWidget);
  });
}
```

- [ ] **Step 2：執行測試確認失敗**

Run（於 `app/` 目錄下）：
```bash
flutter test test/screens/reader_screen_test.dart
```
Expected: 失敗，錯誤訊息顯示找不到 `package:elinkbook/screens/reader_screen.dart`。

- [ ] **Step 3：實作最小程式碼使測試通過**

建立 `app/lib/screens/reader_screen.dart`：

```dart
import 'package:flutter/material.dart';

import '../reader/book_format.dart';

/// 唯一的閱讀器顯示接縫（seam）：給定書籍檔案路徑，依偵測到的格式顯示對應
/// 內容。本階段（Issue 2）僅分派到佔位視圖；Issue 5 會把佔位視圖換成真正的
/// 原生渲染視圖（EpubReaderView／PdfReaderView），但這個 widget 對外的建構
/// 參數（filePath）不會改變。
///
/// AppBar 沿用與 LibraryScreen/SettingsScreen 一致的寫法（純 `AppBar(title:
/// ...)`，不自訂 leading）：Flutter 會依 `Navigator.canPop()` 自動決定是否
/// 顯示返回鍵，且點擊時使用安全的 `Navigator.maybePop()`，不需要手動處理。
class ReaderScreen extends StatelessWidget {
  final String filePath;

  const ReaderScreen({super.key, required this.filePath});

  @override
  Widget build(BuildContext context) {
    final format = detectBookFormat(filePath);
    return Scaffold(
      appBar: AppBar(
        title: const Text('閱讀器'),
      ),
      body: Center(
        child: Text(_placeholderLabel(format)),
      ),
    );
  }

  String _placeholderLabel(BookFormat format) {
    switch (format) {
      case BookFormat.epub:
        return 'EPUB 佔位畫面（尚未接上 Readium 原生渲染）';
      case BookFormat.pdf:
        return 'PDF 佔位畫面（尚未接上 PdfRenderer 原生渲染）';
      case BookFormat.unknown:
        return '不支援的檔案格式';
    }
  }
}
```

- [ ] **Step 4：執行測試確認通過**

Run：
```bash
flutter test test/screens/reader_screen_test.dart
```
Expected: `All tests passed!`

- [ ] **Step 5：執行全部測試套件確認無回歸**

Run（於 `app/` 目錄下）：
```bash
flutter test
```
Expected: 全部測試檔案（`book_format_test.dart`、`reader_screen_test.dart`，以及 Issue 1 的 `library_screen_test.dart`、`settings_screen_test.dart`、`navigation_test.dart`）皆通過，總結顯示 `All tests passed!`。

- [ ] **Step 6：靜態分析確認無警告**

Run：
```bash
flutter analyze
```
Expected: `No issues found!`

- [ ] **Step 7：Commit**

```bash
git add app/lib/screens/reader_screen.dart app/test/screens/reader_screen_test.dart
git commit -m "Add ReaderScreen with format-based placeholder dispatch"
```

---

## 自我審查紀錄

- **Spec 涵蓋範圍**：對應 `issues.md` Issue 2 的兩項單元測試要求（純 Dart 格式偵測、ReaderScreen 分派邏輯）與兩項驗收標準（`flutter test` 可跑過不需模擬器、依偵測結果分派至佔位視圖）均已對應到 Task 1 與 Task 2。Issue 2 明確排除的原生渲染整合（Issue 3/4/5 範圍）未包含在本計劃中。
- **佔位符掃描**：每個步驟皆含完整程式碼與明確指令/預期輸出，無「之後補上」等字樣；`ReaderScreen` 內部的「佔位視圖」是本工單刻意的設計產物（見 spec.md 分階段渲染的架構），不是未完成的規劃佔位符。
- **型別/命名一致性**：`BookFormat`、`detectBookFormat`、`ReaderScreen`、`filePath` 在 Task 1 與 Task 2 之間、以及與 `spec.md` 定義的 `ReaderScreen(filePath: String)` 介面保持一致。

## 文件審查回應紀錄（`review-plan-issue-2.md`）

- **Important #1（副檔名大小寫）**：查證屬實，已採納。`detectBookFormat` 改為先 `toLowerCase()` 再比對，並在 Task 1 新增大寫副檔名測試案例。
- **Important #2（ReaderScreen 缺返回機制）**：查證屬實（與 `LibraryScreen`/`SettingsScreen` 皆有 `AppBar` 不一致），已採納，但**未採用**審查報告建議的手動 `IconButton` + `Navigator.of(context).pop()` 寫法——改用跟現有兩個畫面一致的純 `AppBar(title: ...)`，讓 Flutter 依 `Navigator.canPop()` 自動決定是否顯示返回鍵並使用安全的 `Navigator.maybePop()`，避免手動處理「無法返回時呼叫 pop() 出錯」的風險。Task 2 測試新增對 AppBar 標題「閱讀器」的斷言。
- **Minor（`trim()` 空白防禦）**：**未採納**。目前沒有具體證據顯示使用者提供的檔案路徑會帶有頭尾空白，屬投機性防禦（YAGNI）；若後續實際遇到此類輸入問題，再另行處理。
