# Issue 1 實作計劃：Flutter 專案初始化 + 最小導航殼

> **給執行的 Agent：** 建議使用 superpowers:subagent-driven-development（推薦）或 superpowers:executing-plans 逐任務執行本計劃。步驟採用核取方塊（`- [ ]`）語法追蹤進度。

**目標：** 建立 elinkBook 的 Flutter 專案骨架（Android 平台），並實作一個最小導航殼：書架佔位畫面 ↔ 設定佔位畫面可互相導航。

**架構：** 在儲存庫根目錄下建立 `app/` 子目錄作為 Flutter 專案根目錄，維持 `docs/` 的 SDD 文件結構乾淨獨立。畫面採 `StatelessWidget` + `Navigator.push` 的標準 Flutter 導航模式，暫不引入任何狀態管理套件（YAGNI——此工單不需要）。

**技術棧：** Flutter（Android 平台）、Dart、`flutter_test`（widget test）。

## 全域限制條件

- Flutter 專案位於儲存庫根目錄下的 `app/` 子目錄，套件名稱為 `elinkbook`，Android 應用程式 ID 為 `cc.ugotit.elinkbook`。
- 本工單僅涵蓋 Android 平台（見 `docs/adr/0001-mobile-architecture.md`：Android 優先，iOS 見 `epic-13-ios`）。
- Android `minSdk` 固定為 `21`（同時滿足兩個要求：一、`docs/prd.md` NFR-6 規定最低須支援 Android 11 / API 30 以上裝置，21 已涵蓋此範圍；二、後續 Issue 3 會用到 `PdfRenderer`，該 API 需要 API 21+）。此處先行設定以避免日後變更 minSdk 造成的相容性問題。
- 所有畫面上的使用者可見文字須為正體中文，符合專案語言慣例。
- 本工單不得引入任何原生模組整合（Readium、`PdfRenderer`）、任何狀態管理套件、任何真實圖書庫資料邏輯——這些分別屬於 Issue 3、Issue 4 與 `epic-1-library`。

---

### Task 1：建立 Flutter 專案骨架並清除預設範例程式碼

**Files:**
- Create: `app/`（整個 Flutter 專案目錄，由 `flutter create` 產生）
- Modify: `app/android/app/build.gradle.kts`
- Delete: `app/test/widget_test.dart`

**Interfaces:**
- Consumes: 無（起始工單）
- Produces: `app/` 專案骨架，供 Task 2 起的所有後續任務使用；`app/lib/`、`app/test/` 為後續程式碼與測試的存放位置。

- [ ] **Step 1：確認 Flutter SDK 可用**

Run: `flutter --version`
Expected: 顯示 Flutter 與 Dart 版本號（例如 `Flutter 3.x.x`），無錯誤訊息。若指令找不到，須先安裝 Flutter SDK 才能繼續。

- [ ] **Step 2：於儲存庫根目錄建立 Flutter 專案**

Run（於儲存庫根目錄 `U:\MyDeveloper\AI\elinkBook` 執行）：
```bash
flutter create --platforms=android --org cc.ugotit --project-name elinkbook app
```
Expected: 終端機顯示 `Creating project app...` 及後續產生檔案清單，最後顯示成功訊息（例如 `All done!`）。執行後應存在 `app/pubspec.yaml`、`app/lib/main.dart`、`app/android/`、`app/test/widget_test.dart`。

- [ ] **Step 3：刪除預設的計數器範例測試檔**

刪除檔案 `app/test/widget_test.dart`（此檔案測試 `flutter create` 產生的預設計數器範例 App，與本專案無關，後續任務會建立全新的測試檔）。

- [ ] **Step 4：將 Android `minSdk` 固定為 21**

開啟 `app/android/app/build.gradle.kts`，找到 `defaultConfig` 區塊中的 `minSdk = flutter.minSdkVersion` 這一行，改為：

```kotlin
minSdk = 21
```

*註：若產生的檔案為 Groovy 語法之 `build.gradle`（而非 Kotlin 語法之 `.kts`），則請找到 `minSdkVersion flutter.minSdkVersion` 並修改為 `minSdkVersion 21`。*

- [ ] **Step 5：驗證專案骨架乾淨無誤**

Run（於 `app/` 目錄下）：
```bash
flutter analyze
```
Expected: 輸出 `No issues found!`（因為已移除引用不存在測試對象的舊測試檔，且尚未加入任何自訂程式碼）。

- [ ] **Step 6：Commit**

```bash
cd U:\MyDeveloper\AI\elinkBook
git add app
git commit -m "Scaffold Flutter project for Android (app/)"
```

---

### Task 2：TDD 實作 `LibraryScreen`（書架佔位畫面）

**Files:**
- Create: `app/lib/screens/library_screen.dart`
- Test: `app/test/screens/library_screen_test.dart`

**Interfaces:**
- Consumes: 無（尚未依賴其他畫面）
- Produces: `LibraryScreen`（`StatelessWidget`，無建構參數），供 Task 4（導航）與 Task 5（`main.dart` 進入點）使用。

- [ ] **Step 1：寫失敗測試**

建立 `app/test/screens/library_screen_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/screens/library_screen.dart';

void main() {
  testWidgets('LibraryScreen 顯示書架標題與佔位內容', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LibraryScreen()));

    expect(find.text('書架'), findsOneWidget);
    expect(find.text('書架（佔位畫面）'), findsOneWidget);
  });
}
```

- [ ] **Step 2：執行測試確認失敗**

Run（於 `app/` 目錄下）：
```bash
flutter test test/screens/library_screen_test.dart
```
Expected: 失敗，錯誤訊息顯示找不到 `package:elinkbook/screens/library_screen.dart`（該檔案尚未建立）。

- [ ] **Step 3：實作最小程式碼使測試通過**

建立 `app/lib/screens/library_screen.dart`：

```dart
import 'package:flutter/material.dart';

/// 書架佔位畫面。真正的圖書庫管理邏輯屬於 epic-1-library，此處僅提供
/// 可導航、可測試的最小畫面。
class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      appBar: AppBar(
        title: Text('書架'),
      ),
      body: Center(
        child: Text('書架（佔位畫面）'),
      ),
    );
  }
}
```

- [ ] **Step 4：執行測試確認通過**

Run：
```bash
flutter test test/screens/library_screen_test.dart
```
Expected: `All tests passed!`

- [ ] **Step 5：Commit**

```bash
cd U:\MyDeveloper\AI\elinkBook
git add app/lib/screens/library_screen.dart app/test/screens/library_screen_test.dart
git commit -m "Add LibraryScreen placeholder with widget test"
```

---

### Task 3：TDD 實作 `SettingsScreen`（設定佔位畫面）

**Files:**
- Create: `app/lib/screens/settings_screen.dart`
- Test: `app/test/screens/settings_screen_test.dart`

**Interfaces:**
- Consumes: 無
- Produces: `SettingsScreen`（`StatelessWidget`，無建構參數），供 Task 4（導航）使用。

- [ ] **Step 1：寫失敗測試**

建立 `app/test/screens/settings_screen_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/screens/settings_screen.dart';

void main() {
  testWidgets('SettingsScreen 顯示設定標題與佔位內容', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));

    expect(find.text('設定'), findsOneWidget);
    expect(find.text('設定（佔位畫面）'), findsOneWidget);
  });
}
```

- [ ] **Step 2：執行測試確認失敗**

Run（於 `app/` 目錄下）：
```bash
flutter test test/screens/settings_screen_test.dart
```
Expected: 失敗，錯誤訊息顯示找不到 `package:elinkbook/screens/settings_screen.dart`。

- [ ] **Step 3：實作最小程式碼使測試通過**

建立 `app/lib/screens/settings_screen.dart`：

```dart
import 'package:flutter/material.dart';

/// 設定佔位畫面。實際設定項目（版面、字型、主題等）屬於後續各功能 Epic，
/// 此處僅提供可導航、可測試的最小畫面。
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      appBar: AppBar(
        title: Text('設定'),
      ),
      body: Center(
        child: Text('設定（佔位畫面）'),
      ),
    );
  }
}
```

- [ ] **Step 4：執行測試確認通過**

Run：
```bash
flutter test test/screens/settings_screen_test.dart
```
Expected: `All tests passed!`

- [ ] **Step 5：Commit**

```bash
cd U:\MyDeveloper\AI\elinkBook
git add app/lib/screens/settings_screen.dart app/test/screens/settings_screen_test.dart
git commit -m "Add SettingsScreen placeholder with widget test"
```

---

### Task 4：TDD 實作 `LibraryScreen` → `SettingsScreen` 導航

**Files:**
- Modify: `app/lib/screens/library_screen.dart`
- Test: `app/test/navigation_test.dart`

**Interfaces:**
- Consumes: `LibraryScreen`（Task 2 產出）、`SettingsScreen`（Task 3 產出）
- Produces: `LibraryScreen` 的 `AppBar` 新增一個設定圖示按鈕（`Icons.settings`），點擊後導航至 `SettingsScreen`；供 Task 5 的整合驗證與未來 Issue 6（書架串接開書流程）沿用同一套導航模式。

- [ ] **Step 1：寫失敗測試**

建立 `app/test/navigation_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/screens/library_screen.dart';

void main() {
  testWidgets('點擊設定圖示導航至 SettingsScreen，返回後回到 LibraryScreen', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LibraryScreen()));

    expect(find.text('書架'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.settings));
    await tester.pumpAndSettle();

    expect(find.text('設定'), findsOneWidget);

    // 點擊 AppBar 的返回按鈕以代替 tester.pageBack()，增加測試強健度
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(find.text('書架'), findsOneWidget);
  });
}
```

- [ ] **Step 2：執行測試確認失敗**

Run（於 `app/` 目錄下）：
```bash
flutter test test/navigation_test.dart
```
Expected: 失敗，因為 `LibraryScreen` 的 `AppBar` 目前沒有 `Icons.settings` 圖示按鈕，`find.byIcon(Icons.settings)` 找不到元件。

- [ ] **Step 3：修改 `LibraryScreen` 加入導航邏輯**

將 `app/lib/screens/library_screen.dart` 整份內容改為：

```dart
import 'package:flutter/material.dart';

import 'settings_screen.dart';

/// 書架佔位畫面。真正的圖書庫管理邏輯屬於 epic-1-library，此處僅提供
/// 可導航、可測試的最小畫面。
class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('書架'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: '設定',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => const SettingsScreen()),
              );
            },
          ),
        ],
      ),
      body: const Center(
        child: Text('書架（佔位畫面）'),
      ),
    );
  }
}
```

- [ ] **Step 4：執行測試確認通過**

Run：
```bash
flutter test test/navigation_test.dart
```
Expected: `All tests passed!`

同時重新執行 Task 2 的測試以確認未被破壞：
```bash
flutter test test/screens/library_screen_test.dart
```
Expected: `All tests passed!`

- [ ] **Step 5：Commit**

```bash
cd U:\MyDeveloper\AI\elinkBook
git add app/lib/screens/library_screen.dart app/test/navigation_test.dart
git commit -m "Wire LibraryScreen to SettingsScreen navigation"
```

---

### Task 5：串接 App 進入點並做最終驗證

**Files:**
- Modify: `app/lib/main.dart`

**Interfaces:**
- Consumes: `LibraryScreen`（Task 2 產出，已於 Task 4 加上導航）
- Produces: 可執行的完整 App 進入點，供 Issue 2（`ReaderScreen` 格式偵測）與後續所有工單作為執行/整合基礎。

- [ ] **Step 1：修改 `main.dart` 使用 `LibraryScreen` 作為首頁**

將 `app/lib/main.dart` 整份內容改為：

```dart
import 'package:flutter/material.dart';

import 'screens/library_screen.dart';

void main() {
  runApp(const ElinkBookApp());
}

/// elinkBook App 根元件。
class ElinkBookApp extends StatelessWidget {
  const ElinkBookApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'elinkBook',
      home: LibraryScreen(),
    );
  }
}
```

- [ ] **Step 2：執行完整測試套件確認全數通過**

Run（於 `app/` 目錄下）：
```bash
flutter test
```
Expected: 三個測試檔（`library_screen_test.dart`、`settings_screen_test.dart`、`navigation_test.dart`）全數通過，總結顯示 `All tests passed!`。

- [ ] **Step 3：靜態分析確認無警告**

Run：
```bash
flutter analyze
```
Expected: `No issues found!`

- [ ] **Step 4：（可選但建議）於 Android 模擬器/裝置實際啟動確認**

Run：
```bash
flutter run
```
Expected: App 成功建置並啟動，畫面顯示「書架」標題與「書架（佔位畫面）」文字，點擊右上角設定圖示可進入「設定」畫面，返回鍵可回到書架畫面。確認無誤後可按 `q` 結束。

- [ ] **Step 5：Commit**

```bash
cd U:\MyDeveloper\AI\elinkBook
git add app/lib/main.dart
git commit -m "Wire main.dart entry point to LibraryScreen"
```

---

## 自我審查紀錄

- **Spec 涵蓋範圍**：本計劃對應 `spec.md` 中「Flutter app 外殼」模組（書架/設定畫面）與 `issues.md` 的 Issue 1。`ReaderScreen`、`EpubReaderView`、`PdfReaderView` 屬於 Issue 2～4，不在本計劃範圍內，符合 Issue 1 的邊界。
- **佔位符掃描**：已確認每個步驟皆含完整程式碼與明確的指令/預期輸出，無「TBD」「之後補上」等字樣。
- **型別/命名一致性**：`LibraryScreen`、`SettingsScreen` 兩個類別名稱與檔案名稱在 Task 2～5 中保持一致；`elinkbook` 套件名稱與 `import 'package:elinkbook/...'` 路徑一致。
