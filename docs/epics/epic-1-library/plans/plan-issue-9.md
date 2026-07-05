# Issue 9 實作計劃：應用程式「關於」頁面

> **給執行的 Agent：** 建議使用 superpowers:subagent-driven-development（推薦）或 superpowers:executing-plans 逐任務執行本計劃。步驟採用核取方塊（`- [ ]`）語法追蹤進度。

**目標：** 新增獨立的 `AboutScreen`，從 `SettingsScreen` 新增入口，顯示版本號（`package_info_plus`）、開源授權清單入口（Flutter 內建 `showLicensePage()`）、Android 系統 WebView 版本（供除錯 Readium 內部 WebView 用）。

**架構：** 這是 Epic 1 最後一個工單，且刻意獨立於 `books`/`groups` 資料表——不涉及 `LibraryRepository`/`BookImportService`。版本號透過新增的 `package_info_plus` 套件取得；開源授權清單直接呼叫 Flutter Material 內建的 `showLicensePage()`（自動彙整所有 pub 套件的 LICENSE，不需要手刻授權文字）；系統 WebView 版本沒有對應的 Flutter/套件 API，因此新增一個獨立的原生 MethodChannel（`elinkbook/app_info`，與 `elinkbook/book_metadata`／`elinkbook/folder_picker` 語意上不同的關注點，不合併進既有 channel），用 `android.webkit.WebView.getCurrentWebViewPackage()` 取得。`SettingsScreen` 目前是純佔位畫面（`設定（佔位畫面）` 文字），本工單把它換成含「關於」入口的真實清單畫面。

**技術棧：** Flutter（Dart）、`package_info_plus`（新增依賴）、Flutter Material 內建 `showLicensePage()`、Kotlin（`android.webkit.WebView.getCurrentWebViewPackage()`，需注意此 API 從 Android 8.0／API 26 才存在，本專案 `minSdk` 為 24，需要版本判斷）。

## ⚠️ 執行前環境確認事項

原生 WebView 版本查詢與手動驗證步驟需要真實裝置——執行前請先確認 `flutter devices` 能列出至少一個 Android 裝置/模擬器。`package_info_plus` 是本專案首次使用的套件；其官方測試替身 `PackageInfo.setMockInitialValues(...)` 在本計劃撰寫時因套件未快取於本機而無法逐行對照原始碼確認確切簽章（不像先前 `file_picker` 已知有版本 API 落差的前例）——這是一個成熟、多年沒有破壞性變更的套件，但若編譯時發現 `setMockInitialValues` 的參數與本計劃程式碼不符，請依實際安裝版本的原始碼調整，並在報告中記錄差異。

## Global Constraints（全域限制條件）

- `AboutScreen` 為獨立畫面，**不得**引用 `LibraryRepository`/`BookImportService`/任何 `books`/`groups` 相關型別。
- 開源授權清單**不得**手刻授權文字——直接呼叫 Flutter Material 內建的 `showLicensePage()`，讓它自動彙整所有 pub 套件的 LICENSE。
- `android.webkit.WebView.getCurrentWebViewPackage()` 只在 API 26（Android 8.0）以上存在；呼叫前**必須**先判斷 `Build.VERSION.SDK_INT >= Build.VERSION_CODES.O`，低於此版本時回傳 `null`（本專案 `minSdk` 為 24，見 `app/android/app/build.gradle.kts`）。
- 新增的原生 channel 名稱為 `elinkbook/app_info`（**不得**合併進既有的 `elinkbook/book_metadata` 或 `elinkbook/folder_picker`——三者是刻意分開、各自獨立的關注點，此為既有慣例）。
- 新增的 Key：`Key('settings_about_button')`（設定畫面的「關於」入口）、`Key('about_screen_version_text')`（版本號文字）、`Key('about_screen_webview_version_text')`（WebView 版本文字）、`Key('about_screen_view_licenses_button')`（開源授權清單入口）。
- `SettingsScreen` 既有測試中對「設定（佔位畫面）」這段佔位文字的斷言**必須**同步移除／更新——這段佔位文字本身會被本工單移除，不是意外破壞。
- 所有 UI 文字、程式註解維持正體中文。

---

### Task 1：`AboutScreen` + 原生 WebView 版本查詢 + `SettingsScreen` 導航入口

**Files:**
- Modify: `app/pubspec.yaml`（新增 `package_info_plus` 依賴）
- Modify: `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/MainActivity.kt`
- Create: `app/lib/screens/about_screen.dart`
- Modify: `app/lib/screens/settings_screen.dart`
- Create: `app/test/screens/about_screen_test.dart`
- Modify: `app/test/screens/settings_screen_test.dart`

**Interfaces:**
- Consumes：無（本工單不依賴其他工單的程式碼）。
- Produces：`class AboutScreen extends StatelessWidget`（實際為 `StatefulWidget`，因需非同步載入版本號與 WebView 版本）、原生 channel `elinkbook/app_info` 的 `getSystemWebViewVersion() -> String?`。本工單為 Epic 1 最後一個工單，無後續工單依賴這些細節。

- [ ] **Step 1：新增 `package_info_plus` 依賴**

Run: `flutter pub add package_info_plus`（在 `app/` 目錄下執行；讓 `pub` 自動解析目前相容的最新版本，不手動猜測版本號寫入 `pubspec.yaml`）
Expected: 指令成功結束，`app/pubspec.yaml` 的 `dependencies` 區塊新增一行 `package_info_plus: ^X.Y.Z`，`app/pubspec.lock` 同步更新。

- [ ] **Step 2：`MainActivity` 新增 `elinkbook/app_info` channel**

在 `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/MainActivity.kt` 檔案最上方的 `import` 區塊補上：

```kotlin
import android.os.Build
import android.webkit.WebView
```

在 `configureFlutterEngine()` 方法內、既有的 `elinkbook/folder_picker` channel 註冊之後（`}` 之前），新增：

```kotlin
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "elinkbook/app_info")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getSystemWebViewVersion" -> {
                        // WebView.getCurrentWebViewPackage() 從 API 26（Android 8.0）
                        // 才存在；本專案 minSdk 為 24，低於 API 26 的裝置一律回傳
                        // null，交給 Dart 端顯示「無法取得」而非讓 App 崩潰。
                        val versionName = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            WebView.getCurrentWebViewPackage()?.versionName
                        } else {
                            null
                        }
                        result.success(versionName)
                    }
                    else -> result.notImplemented()
                }
            }
```

（既有的 `bookMetadataChannel` 賦值與 `elinkbook/folder_picker` channel 註冊逐行不變，這段程式碼接在它們後面。）

- [ ] **Step 3：寫失敗測試（`AboutScreen` 渲染版本號與 WebView 版本）**

建立 `app/test/screens/about_screen_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:elinkbook/screens/about_screen.dart';

const _appInfoChannel = MethodChannel('elinkbook/app_info');

void main() {
  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'elinkBook',
      packageName: 'cc.ugotit.elinkbook',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_appInfoChannel, (call) async {
      if (call.method == 'getSystemWebViewVersion') return '120.0.6099.43';
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_appInfoChannel, null);
  });

  testWidgets('AboutScreen 正確渲染版本號與 WebView 版本', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AboutScreen()));
    await tester.pumpAndSettle();

    expect(find.text('關於'), findsOneWidget);
    expect(
      find.byKey(const Key('about_screen_version_text')),
      findsOneWidget,
    );
    expect(find.text('1.0.0 (build 1)'), findsOneWidget);
    expect(
      find.byKey(const Key('about_screen_webview_version_text')),
      findsOneWidget,
    );
    expect(find.text('120.0.6099.43'), findsOneWidget);
    expect(
      find.byKey(const Key('about_screen_view_licenses_button')),
      findsOneWidget,
    );
    expect(find.text('開源授權清單'), findsOneWidget);
  });
}
```

- [ ] **Step 4：執行測試，確認失敗**

Run: `flutter test test/screens/about_screen_test.dart -v`
Expected: FAIL（`package:elinkbook/screens/about_screen.dart` 不存在，編譯錯誤）

- [ ] **Step 5：實作 `AboutScreen`**

建立 `app/lib/screens/about_screen.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

const _appInfoChannel = MethodChannel('elinkbook/app_info');

/// 應用程式「關於」頁面（FR-29）：顯示版本號、開源授權清單入口、Android
/// 系統 WebView 版本（因 Readium 內部走 WebView，供除錯用）。獨立畫面，
/// 不涉及 books/groups 資料表（見 docs/epics/epic-1-library/spec.md）。
class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  String _versionText = '讀取中...';
  String? _versionForLicensePage;
  String _webViewVersion = '讀取中...';

  @override
  void initState() {
    super.initState();
    _loadPackageInfo();
    _loadWebViewVersion();
  }

  Future<void> _loadPackageInfo() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() {
        _versionText = '${info.version} (build ${info.buildNumber})';
        _versionForLicensePage = info.version;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _versionText = '無法取得版本號');
    }
  }

  Future<void> _loadWebViewVersion() async {
    try {
      final version = await _appInfoChannel.invokeMethod<String>(
        'getSystemWebViewVersion',
      );
      if (!mounted) return;
      setState(() => _webViewVersion = version ?? '無法取得');
    } catch (_) {
      if (!mounted) return;
      setState(() => _webViewVersion = '無法取得');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('關於')),
      body: ListView(
        children: [
          ListTile(
            title: const Text('版本'),
            subtitle: Text(
              _versionText,
              key: const Key('about_screen_version_text'),
            ),
          ),
          ListTile(
            title: const Text('系統 WebView 版本'),
            subtitle: Text(
              _webViewVersion,
              key: const Key('about_screen_webview_version_text'),
            ),
          ),
          ListTile(
            key: const Key('about_screen_view_licenses_button'),
            title: const Text('開源授權清單'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              showLicensePage(
                context: context,
                applicationName: 'elinkBook',
                applicationVersion: _versionForLicensePage,
              );
            },
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 6：執行測試，確認通過**

Run: `flutter test test/screens/about_screen_test.dart -v`
Expected: 全數 PASS

- [ ] **Step 7：寫失敗測試（`SettingsScreen` 新增「關於」入口 + 導航）**

整檔改寫 `app/test/screens/settings_screen_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:elinkbook/screens/settings_screen.dart';

const _appInfoChannel = MethodChannel('elinkbook/app_info');

void main() {
  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'elinkBook',
      packageName: 'cc.ugotit.elinkbook',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_appInfoChannel, (call) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_appInfoChannel, null);
  });

  testWidgets('SettingsScreen 顯示設定標題與「關於」入口', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));

    expect(find.text('設定'), findsOneWidget);
    expect(find.byKey(const Key('settings_about_button')), findsOneWidget);
  });

  testWidgets('點擊「關於」導航至 AboutScreen，可返回 SettingsScreen', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));

    await tester.tap(find.byKey(const Key('settings_about_button')));
    await tester.pumpAndSettle();

    expect(find.text('關於'), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(find.text('設定'), findsOneWidget);
  });
}
```

- [ ] **Step 8：執行測試，確認失敗**

Run: `flutter test test/screens/settings_screen_test.dart -v`
Expected: FAIL（`settings_about_button` 這個 Key 尚不存在；原本斷言「設定（佔位畫面）」文字的舊測試已被移除，改為新斷言）

- [ ] **Step 9：改寫 `SettingsScreen`**

整檔改寫 `app/lib/screens/settings_screen.dart`：

```dart
import 'package:flutter/material.dart';

import 'about_screen.dart';

/// 設定畫面：目前只有「關於」入口可用；其餘設定項目（版面、字型、主題等）
/// 屬於後續各功能 Epic。
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('設定'),
      ),
      body: ListView(
        children: [
          ListTile(
            key: const Key('settings_about_button'),
            title: const Text('關於'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => const AboutScreen()),
              );
            },
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 10：執行測試，確認通過**

Run: `flutter test test/screens/settings_screen_test.dart -v`
Expected: 全數 PASS

- [ ] **Step 11：執行完整測試與靜態分析**

Run: `flutter test`
Expected: 全數 PASS

Run: `flutter analyze`
Expected: `No issues found!`

Run（真實裝置，確認原生變更未破壞既有建置與啟動）：`flutter test integration_test/smoke_test.dart -d <device-id>`
Expected: `All tests passed!`

- [ ] **Step 12：Commit**

```bash
git add app/pubspec.yaml app/pubspec.lock app/android/app/src/main/kotlin/cc/ugotit/elinkbook/MainActivity.kt app/lib/screens/about_screen.dart app/lib/screens/settings_screen.dart app/test/screens/about_screen_test.dart app/test/screens/settings_screen_test.dart
git commit -m "feat: add AboutScreen with version, licenses, and system WebView version"
```

- [ ] **Step 13：手動驗證（對應驗收標準）**

在真實裝置上執行 `flutter run`，確認：
1. 從書架點擊設定圖示進入 `SettingsScreen`，點擊「關於」進入 `AboutScreen`。
2. 「版本」欄位顯示非空的版本號（例如 `1.0.0 (build 1)`）。
3. 「系統 WebView 版本」欄位顯示非空值（例如 `120.0.6099.43`），不是「無法取得」。
4. 點擊「開源授權清單」，確認能開啟 Flutter 內建的授權清單頁面並列出已使用的第三方套件。
5. 點擊返回鍵能正常回到 `SettingsScreen`。

此步驟為手動驗證，確保原生 `WebView.getCurrentWebViewPackage()` 呼叫在真實裝置上真的回傳非空值（純 Dart widget test 只能用 mock 驗證程式邏輯，無法驗證原生 API 本身在真實 Android 系統上的行為）。
