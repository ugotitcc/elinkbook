# Issue 2 實作計劃：原生契約擴充——批次偏好設定與字型素材註冊

> **給執行的 Agent：** 建議使用 superpowers:subagent-driven-development（推薦）或 superpowers:executing-plans 逐任務執行本計劃。步驟採用核取方塊（`- [ ]`）語法追蹤進度。

**目標：** 依 ADR 0006 把 `EpubReaderView`/`EpubReaderView.kt` 的偏好設定契約從「一個維度一個方法」擴充為「批次 map」，新增 8 個版面偏好維度（字型、大小、字重、行高、段落間距、邊距、對齊、停用書本 CSS），並讓已持久化的偏好設定在開書當下就能真正套用到原生端。同時完成 5 款內建字型的素材註冊，讓 Readium 內嵌的原生 WebView 能實際載入本地字型檔案渲染。

**架構：** Dart 端 `EpubReaderView` 新增 8 個 nullable 建構參數；`_onPlatformViewCreated` 把所有非 null 偏好參數組成 map，隨 `openBook` 送出（`initialPreferences`）；`didUpdateWidget` 偵測全部 10 個偏好欄位（含既有 `writingMode`/`pageTurnMode`）任一變動時，把目前所有非 null 欄位組成一個 map，透過單一 `setPreferences` 送出。原生端 `EpubReaderView.kt` 的 `openBook`/`setPreferences` 共用同一段「map → `EpubPreferences`」轉換邏輯；`attachNavigator()` 額外透過 Readium `EpubNavigatorFragment.Configuration.addFontFamilyDeclaration` 登記 5 款字型，讓內嵌 WebView 能透過 `androidx.webkit.WebViewAssetLoader` 讀取到 Flutter 打包進 APK 的字型檔案。

**技術棧：** Dart/Flutter（`AndroidView`/`MethodChannel`）、Kotlin、Readium `readium-navigator:3.3.0`（`EpubPreferences`、`EpubNavigatorFragment.Configuration`、`FontFamily`）、Flutter Android Embedding（`FlutterInjector.flutterLoader().getLookupKeyForAsset`）。

## 全域限制條件

- `EpubReaderView(filePath, onPageRendered, onError, onLayoutResolved, writingMode, pageTurnMode, ...)` 既有 5 個參數的**名稱、型別、一般語意不變**（`writingMode`/`pageTurnMode` 仍是「呼叫端已解析好的最終生效值，null 表示不覆寫」）；本 issue 只新增參數、擴充內部批次送出邏輯。**例外（刻意，非疏漏）：** 依 ADR 0006，`initialPreferences` 機制回溯適用於 `writingMode`/`pageTurnMode`——修改前這兩者在首次 `openBook` 當下一律被忽略（等 `didUpdateWidget` 才生效），修改後若非 null 會隨 `openBook` 的 `initialPreferences` 一併送出。這是 ADR 0006 明確要解決的「持久化設定在開書當下沒有真正套用」缺口，屬於本 issue 的核心目標，不是需要避免的行為變動。
- `setWritingMode`／`setPageTurnMode`（Dart 端呼叫、原生端方法）**移除**，邏輯併入單一 `setPreferences`（見 ADR 0006）；既有呼叫這兩個方法名稱的程式碼不得殘留。
- `fontWeight` 建構參數本身已是 Readium 倍率語意（`1.0` = normal），本 issue 不做 UI 慣用值（300-900）↔ 倍率換算，該換算屬於 Issue 3 責任。
- `AppFont` 到實際字型家族名稱字串的對應（`familyName`），與原生端 `addFontFamilyDeclaration` 登記時使用的名稱字串**必須逐字一致**，兩處硬編碼字串以下方 Task 1/Task 3 給定的值為準，不得自創其他命名。
- `pubspec.yaml` 字型檔案改用 `assets:` 宣告（非 `fonts:`）——`fonts:` 只影響 Flutter 自己的 Skia 渲染，與原生 WebView 字型載入無關（見 `spec.md`「自訂字型如何讓原生 WebView 實際載入」）。
- 原生端 Kotlin 邏輯的實際裝置行為驗證（含字型是否真的正確渲染、`initialPreferences`/`setPreferences` 是否真的讓 Readium 套用新偏好）留給 Issue 6；本 issue 對原生端的驗收僅止於 `flutter build apk --debug` 成功建置（無真實裝置可用）。
- 所有新增程式碼註解與文件維持正體中文。
- `flutter analyze` 全程必須維持 `No issues found!`。

---

### Task 1：`AppFont` 家族名稱對應 + 字型素材註冊

**Files:**
- Modify: `app/lib/reader/app_font.dart`
- Modify: `app/pubspec.yaml`
- Test: `app/test/reader/app_font_test.dart`

**Interfaces:**
- Consumes: 既有 `enum AppFont`（Epic 3 Issue 1 建立，`app/lib/reader/app_font.dart`）
- Produces: `extension AppFontFamilyName on AppFont { String get familyName; }`，供 Task 2（`EpubReaderView` 組 `initialPreferences`/`setPreferences` map）使用；家族名稱字串同時是 Task 3（原生端 `addFontFamilyDeclaration`）必須逐字對應的值

**前提確認：** 5 個字型檔案（`SourceHanSansTC-VF.ttf`／`SourceHanSerifTC-VF.ttf`／`GuanKiapTsingKhai.ttf`／`TaiwanPearl-Regular.ttf`／`GenRyuMinTW-Regular.ttf`）已於 Epic 3 Discovery 階段放置在 `app/assets/fonts/`，本 Task 不需要另外搬移或下載——Step 5 只是把已存在的檔案路徑登記進 `pubspec.yaml`。

- [ ] **Step 1：撰寫失敗測試**

建立 `app/test/reader/app_font_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/app_font.dart';

void main() {
  test('每個 AppFont 都有對應的家族名稱字串，且彼此互不相同', () {
    const expected = {
      AppFont.sourceHanSans: 'SourceHanSansTC',
      AppFont.sourceHanSerif: 'SourceHanSerifTC',
      AppFont.guanKiapTsingKhai: 'GuanKiapTsingKhai',
      AppFont.taiwanPearl: 'TaiwanPearl',
      AppFont.genRyuMinTW: 'GenRyuMinTW',
    };
    for (final font in AppFont.values) {
      expect(font.familyName, expected[font]);
    }
    final allNames = AppFont.values.map((f) => f.familyName).toSet();
    expect(
      allNames.length,
      AppFont.values.length,
      reason: '家族名稱字串必須互不相同，否則原生端登記時後者會覆蓋前者',
    );
  });
}
```

- [ ] **Step 2：執行測試確認失敗**

Run（於 `app/` 目錄下）：
```bash
flutter test test/reader/app_font_test.dart
```
Expected：FAIL——`AppFont` 沒有 `familyName` getter（編譯錯誤）。

- [ ] **Step 3：新增 `familyName` extension**

開啟 `app/lib/reader/app_font.dart`，目前內容為：

```dart
/// App 內建的 5 款字型（FR-09）。皆為本地 asset 字型（`app/assets/fonts/`），
/// 非系統字型；自訂字型上傳/管理屬 `epic-14-system-settings`（FR-35），
/// 本 epic 僅從此固定清單中選擇。
enum AppFont {
  sourceHanSans, // 思源黑體 SourceHanSansTC-VF.ttf
  sourceHanSerif, // 思源宋體 SourceHanSerifTC-VF.ttf
  guanKiapTsingKhai, // 原俠正楷 GuanKiapTsingKhai.ttf
  taiwanPearl, // 台灣圓體 TaiwanPearl-Regular.ttf
  genRyuMinTW, // 源流明體 GenRyuMinTW-Regular.ttf
}
```

在檔案最後新增（保留上方既有內容不變）：

```dart

/// [AppFont] 對應的實際字型家族名稱字串。此值透過 method channel 的
/// `fontFamily` key 送給原生端，原生端 `EpubReaderView.kt` 的
/// `addFontFamilyDeclaration` 登記字型時使用**完全相同**的字串（見
/// docs/epics/epic-3-fonts-layout/spec.md「自訂字型如何讓原生 WebView
/// 實際載入」）——兩處字串若不一致，`fontFamily` 偏好設定會被靜默忽略
/// （Readium 找不到對應的已登記字型，落回 WebView 預設字型）。
extension AppFontFamilyName on AppFont {
  String get familyName {
    switch (this) {
      case AppFont.sourceHanSans:
        return 'SourceHanSansTC';
      case AppFont.sourceHanSerif:
        return 'SourceHanSerifTC';
      case AppFont.guanKiapTsingKhai:
        return 'GuanKiapTsingKhai';
      case AppFont.taiwanPearl:
        return 'TaiwanPearl';
      case AppFont.genRyuMinTW:
        return 'GenRyuMinTW';
    }
  }
}
```

- [ ] **Step 4：執行測試確認通過**

Run：
```bash
flutter test test/reader/app_font_test.dart
```
Expected：`All tests passed!`（1 項測試）。

- [ ] **Step 5：`pubspec.yaml` 新增字型檔案的 `assets:` 宣告**

開啟 `app/pubspec.yaml`，把：

```yaml
  assets:
    - test/fixtures/sample.pdf
    - test/fixtures/sample.epub
    - test/fixtures/sample_horizontal.epub
    - test/fixtures/sample_fixed_layout.epub
    - test/fixtures/sample_long_vertical.epub
    - test/fixtures/sample_forced_linebreak_vertical.epub
```

改為：

```yaml
  assets:
    - test/fixtures/sample.pdf
    - test/fixtures/sample.epub
    - test/fixtures/sample_horizontal.epub
    - test/fixtures/sample_fixed_layout.epub
    - test/fixtures/sample_long_vertical.epub
    - test/fixtures/sample_forced_linebreak_vertical.epub
    - assets/fonts/SourceHanSansTC-VF.ttf
    - assets/fonts/SourceHanSerifTC-VF.ttf
    - assets/fonts/GuanKiapTsingKhai.ttf
    - assets/fonts/TaiwanPearl-Regular.ttf
    - assets/fonts/GenRyuMinTW-Regular.ttf
```

（**不**新增 `fonts:` 區塊——見全域限制條件；本 issue 不需要 Flutter 端自己預覽字型外觀。）

- [ ] **Step 6：確認 `flutter pub get` 與靜態分析正常**

Run（於 `app/` 目錄下）：
```bash
flutter pub get
flutter analyze
```
Expected：`flutter pub get` 成功（`Got dependencies!`）；`flutter analyze` 顯示 `No issues found!`（新增的 5 個 asset 項目不會觸發任何警告——asset 是否存在的檢查只在建置時發生，`flutter analyze` 不驗證檔案是否存在）。

- [ ] **Step 7：全量測試確認無回歸**

Run（於 `app/` 目錄下）：
```bash
flutter test
```
Expected：全數通過，無回歸（既有 109 項 + 本次新增 1 項）。

- [ ] **Step 8：Commit**

```bash
git add app/lib/reader/app_font.dart app/pubspec.yaml app/test/reader/app_font_test.dart
git commit -m "Add AppFont family name mapping and register font assets"
```

---

### Task 2：`EpubReaderView` Dart 端契約擴充

**Files:**
- Modify: `app/lib/reader/epub_reader_view.dart`
- Test: `app/test/reader/epub_reader_view_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `AppFont.familyName`；既有 `WritingMode`/`PageTurnMode`/`EpubTextAlign`（`app/lib/reader/writing_mode.dart`/`page_turn_mode.dart`/`epub_text_align.dart`）
- Produces: `EpubReaderView` 新建構參數 `fontFamily`/`fontSize`/`fontWeight`/`lineHeight`/`paragraphSpacing`/`pageMargins`/`textAlign`/`publisherStyles`；`openBook`/`setPreferences` 兩個 method channel 呼叫的 map 格式（key 名稱：`writingMode`/`pageTurnMode`/`fontFamily`/`fontSize`/`fontWeight`/`lineHeight`/`paragraphSpacing`/`pageMargins`/`textAlign`/`publisherStyles`），供 Task 3（原生端）與後續 issue（`ReaderSettingsSheet`/`ReaderScreen`）使用

**背景（測試策略，已於撰寫本計劃時實測驗證）：** `EpubReaderView` 底層透過 `AndroidView` 建立原生 `PlatformView`，一般 `flutter test`（無裝置）不會觸發 `onPlatformViewCreated`。但可透過 mock `SystemChannels.platform_views`（讓 `'create'` 呼叫回傳一個假的 `textureId`）讓 `onPlatformViewCreated` 在無裝置環境下依然觸發；觸發後動態取得的 `id` 即可用來 mock 對應的 per-instance channel（`cc.ugotit.elinkbook/epub_reader_view_$id`），完整攔截 `openBook`/`setPreferences` 呼叫並斷言其參數。此技巧已實際跑過 `flutter test` 確認可行，非未經驗證的猜測。

- [ ] **Step 1：撰寫失敗測試**

建立 `app/test/reader/epub_reader_view_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/app_font.dart';
import 'package:elinkbook/reader/epub_reader_view.dart';
import 'package:elinkbook/reader/epub_text_align.dart';
import 'package:elinkbook/reader/page_turn_mode.dart';
import 'package:elinkbook/reader/writing_mode.dart';

/// 驅動 [EpubReaderView] 底層 AndroidView 完成建立流程所需的最小 mock：
/// 攔截 `SystemChannels.platform_views` 的 `'create'` 呼叫並回傳假的
/// textureId，讓 `onPlatformViewCreated` 得以在沒有真實裝置的 `flutter
/// test` 環境下觸發；同時攔截該次建立實際使用的 per-instance 頻道
/// （`cc.ugotit.elinkbook/epub_reader_view_$id`），記錄所有外送的
/// MethodCall 供測試斷言。view id 由 Flutter 內部計數器決定、跨測試遞增，
/// 因此從 `'create'` 呼叫的 `arguments['id']` 動態取得，不可寫死為固定
/// 數字。
Future<List<MethodCall>> _pumpEpubReaderView(
  WidgetTester tester,
  EpubReaderView widget,
) async {
  final binaryMessenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final instanceCalls = <MethodCall>[];

  binaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views,
      (call) async {
    if (call.method == 'create') {
      final id = (call.arguments as Map<Object?, Object?>)['id'] as int;
      binaryMessenger.setMockMethodCallHandler(
        MethodChannel('cc.ugotit.elinkbook/epub_reader_view_$id'),
        (call) async {
          instanceCalls.add(call);
          return null;
        },
      );
      return 0; // textureId
    }
    return null;
  });

  await tester.pumpWidget(MaterialApp(home: widget));
  await tester.pumpAndSettle();
  return instanceCalls;
}

void main() {
  testWidgets(
      '_onPlatformViewCreated 呼叫 openBook 時，initialPreferences 包含所有非 null 建構參數',
      (tester) async {
    final calls = await _pumpEpubReaderView(
      tester,
      const EpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        writingMode: WritingMode.vertical,
        pageTurnMode: PageTurnMode.scroll,
        fontFamily: AppFont.sourceHanSans,
        fontSize: 18,
        fontWeight: 1.75,
        lineHeight: 1.6,
        paragraphSpacing: 12,
        pageMargins: 20,
        textAlign: EpubTextAlign.justify,
        publisherStyles: false,
      ),
    );

    final openBookCall = calls.firstWhere((c) => c.method == 'openBook');
    expect(openBookCall.arguments['path'], '/tmp/sample.epub');
    expect(openBookCall.arguments['initialPreferences'], {
      'writingMode': 'vertical',
      'pageTurnMode': 'scroll',
      'fontFamily': 'SourceHanSansTC',
      'fontSize': 18.0,
      'fontWeight': 1.75,
      'lineHeight': 1.6,
      'paragraphSpacing': 12.0,
      'pageMargins': 20.0,
      'textAlign': 'justify',
      'publisherStyles': false,
    });
  });

  testWidgets('所有偏好欄位皆為 null 時，initialPreferences 為空 map（而非 null）',
      (tester) async {
    final calls = await _pumpEpubReaderView(
      tester,
      const EpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
      ),
    );

    final openBookCall = calls.firstWhere((c) => c.method == 'openBook');
    expect(openBookCall.arguments['initialPreferences'], <String, Object?>{});
  });

  testWidgets(
      '任一偏好欄位變動時，didUpdateWidget 呼叫 setPreferences 並帶入目前所有非 null 欄位',
      (tester) async {
    final binaryMessenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final instanceCalls = <MethodCall>[];

    binaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views,
        (call) async {
      if (call.method == 'create') {
        final id = (call.arguments as Map<Object?, Object?>)['id'] as int;
        binaryMessenger.setMockMethodCallHandler(
          MethodChannel('cc.ugotit.elinkbook/epub_reader_view_$id'),
          (call) async {
            instanceCalls.add(call);
            return null;
          },
        );
        return 0;
      }
      return null;
    });

    await tester.pumpWidget(const MaterialApp(
      home: EpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        fontSize: 18,
      ),
    ));
    await tester.pumpAndSettle();
    instanceCalls.clear();

    await tester.pumpWidget(const MaterialApp(
      home: EpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        fontSize: 20, // 變動
        writingMode: WritingMode.vertical, // 新增一個原本是 null 的欄位
      ),
    ));
    await tester.pumpAndSettle();

    expect(instanceCalls, hasLength(1));
    expect(instanceCalls.single.method, 'setPreferences');
    expect(instanceCalls.single.arguments, {
      'fontSize': 20.0,
      'writingMode': 'vertical',
    });
  });

  testWidgets('偏好欄位皆未變動時，didUpdateWidget 不觸發任何 setPreferences 呼叫',
      (tester) async {
    final binaryMessenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final instanceCalls = <MethodCall>[];

    binaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views,
        (call) async {
      if (call.method == 'create') {
        final id = (call.arguments as Map<Object?, Object?>)['id'] as int;
        binaryMessenger.setMockMethodCallHandler(
          MethodChannel('cc.ugotit.elinkbook/epub_reader_view_$id'),
          (call) async {
            instanceCalls.add(call);
            return null;
          },
        );
        return 0;
      }
      return null;
    });

    const widget = EpubReaderView(
      filePath: '/tmp/sample.epub',
      onPageRendered: _noop,
      onError: _noopError,
      fontSize: 18,
    );

    await tester.pumpWidget(const MaterialApp(home: widget));
    await tester.pumpAndSettle();
    instanceCalls.clear();

    await tester.pumpWidget(const MaterialApp(home: widget));
    await tester.pumpAndSettle();

    expect(instanceCalls, isEmpty);
  });
}

void _noop() {}
void _noopError(String message) {}
```

- [ ] **Step 2：執行測試確認失敗**

Run（於 `app/` 目錄下）：
```bash
flutter test test/reader/epub_reader_view_test.dart
```
Expected：FAIL——`EpubReaderView` 尚無 `fontFamily`/`fontSize`/`fontWeight`/`lineHeight`/`paragraphSpacing`/`pageMargins`/`textAlign`/`publisherStyles` 建構參數（編譯錯誤）。

- [ ] **Step 3：擴充 `EpubReaderView`**

開啟 `app/lib/reader/epub_reader_view.dart`，把整份內容改為：

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_font.dart';
import 'epub_text_align.dart';
import 'page_turn_mode.dart';
import 'writing_mode.dart';

/// 包裝原生 Android EpubReaderView（Readium kotlin-toolkit）的 Flutter widget，
/// 透過 AndroidView（PlatformView）嵌入畫面。給定 EPUB 檔案的裝置端絕對路徑，通知
/// 原生端渲染起始頁；渲染成功或失敗會分別觸發 [onPageRendered] 或 [onError]。
///
/// 全部 10 個偏好參數（[writingMode]／[pageTurnMode] 與本類別新增的 8 個版面
/// 偏好參數）語意一致：呼叫端傳入的皆是「已解析好的最終生效值」，`null` 代表
/// 不覆寫、使用 Readium 預設。首次建構時，所有非 null 的偏好參數會組成一個
/// map 隨 `openBook` 一併送出（`initialPreferences`）；之後任一偏好參數變動
/// （[didUpdateWidget] 偵測），會把當下所有非 null 的偏好參數（不只是變動的
/// 那個）重新組成一個 map，透過單一 `setPreferences` 呼叫送出——原生端
/// `currentPreferences.plus()` 本身就是合併語意，送出完整目前狀態比只送變動
/// 欄位更不容易遺漏邊界情況（見 docs/adr/0006-epub-reader-batch-preferences-contract.md）。
///
/// 【刻意的設計，非疏漏】即使首次建構時任一偏好參數就已是非 null，開書當下
/// 仍會透過 `initialPreferences` 一併送出——這與先前版本「開書當下一律忽略
/// writingMode／等到 didUpdateWidget 才生效」的行為不同，是 ADR 0006 明確要
/// 解決的缺口（持久化設定在開書當下真正套用）。
class EpubReaderView extends StatefulWidget {
  final String filePath;
  final VoidCallback onPageRendered;
  final ValueChanged<String> onError;
  final WritingMode? writingMode;
  final PageTurnMode? pageTurnMode;
  final ValueChanged<EpubLayoutInfo>? onLayoutResolved;
  final AppFont? fontFamily;
  final double? fontSize;
  final double? fontWeight; // 已是 Readium 倍率語意（1.0 = normal），非 CSS 300-900 原始值
  final double? lineHeight;
  final double? paragraphSpacing;
  final double? pageMargins;
  final EpubTextAlign? textAlign;
  final bool? publisherStyles;

  const EpubReaderView({
    super.key,
    required this.filePath,
    required this.onPageRendered,
    required this.onError,
    this.writingMode,
    this.pageTurnMode,
    this.onLayoutResolved,
    this.fontFamily,
    this.fontSize,
    this.fontWeight,
    this.lineHeight,
    this.paragraphSpacing,
    this.pageMargins,
    this.textAlign,
    this.publisherStyles,
  });

  @override
  State<EpubReaderView> createState() => _EpubReaderViewState();
}

class _EpubReaderViewState extends State<EpubReaderView> {
  MethodChannel? _channel;

  void _onPlatformViewCreated(int id) {
    final channel = MethodChannel('cc.ugotit.elinkbook/epub_reader_view_$id');
    _channel = channel;
    channel.setMethodCallHandler(_handleMethodCall);
    channel.invokeMethod('openBook', {
      'path': widget.filePath,
      'initialPreferences': _buildPreferencesMap(),
    });
  }

  @override
  void didUpdateWidget(covariant EpubReaderView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_preferencesChanged(oldWidget)) {
      _channel?.invokeMethod('setPreferences', _buildPreferencesMap());
    }
  }

  bool _preferencesChanged(EpubReaderView oldWidget) {
    return widget.writingMode != oldWidget.writingMode ||
        widget.pageTurnMode != oldWidget.pageTurnMode ||
        widget.fontFamily != oldWidget.fontFamily ||
        widget.fontSize != oldWidget.fontSize ||
        widget.fontWeight != oldWidget.fontWeight ||
        widget.lineHeight != oldWidget.lineHeight ||
        widget.paragraphSpacing != oldWidget.paragraphSpacing ||
        widget.pageMargins != oldWidget.pageMargins ||
        widget.textAlign != oldWidget.textAlign ||
        widget.publisherStyles != oldWidget.publisherStyles;
  }

  /// 把目前所有非 null 的偏好參數組成一個 map，key 名稱與原生端契約一致
  /// （見 docs/epics/epic-3-fonts-layout/spec.md「原生 method channel 契約
  /// 異動」）。`null` 值的欄位完全不出現在 map 中（而非以 `null` 出現），
  /// 讓原生端可以直接用「key 是否存在」判斷是否覆寫。
  Map<String, Object?> _buildPreferencesMap() {
    final map = <String, Object?>{};
    if (widget.writingMode != null) {
      map['writingMode'] =
          widget.writingMode == WritingMode.vertical ? 'vertical' : 'horizontal';
    }
    if (widget.pageTurnMode != null) {
      map['pageTurnMode'] =
          widget.pageTurnMode == PageTurnMode.scroll ? 'scroll' : 'paginated';
    }
    if (widget.fontFamily != null) {
      map['fontFamily'] = widget.fontFamily!.familyName;
    }
    if (widget.fontSize != null) map['fontSize'] = widget.fontSize;
    if (widget.fontWeight != null) map['fontWeight'] = widget.fontWeight;
    if (widget.lineHeight != null) map['lineHeight'] = widget.lineHeight;
    if (widget.paragraphSpacing != null) {
      map['paragraphSpacing'] = widget.paragraphSpacing;
    }
    if (widget.pageMargins != null) map['pageMargins'] = widget.pageMargins;
    if (widget.textAlign != null) map['textAlign'] = widget.textAlign!.name;
    if (widget.publisherStyles != null) {
      map['publisherStyles'] = widget.publisherStyles;
    }
    return map;
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onPageRendered':
        widget.onPageRendered();
        break;
      case 'onError':
        widget.onError(call.arguments as String);
        break;
      case 'onLayoutResolved':
        final args = call.arguments as Map<Object?, Object?>;
        widget.onLayoutResolved?.call(EpubLayoutInfo(
          isFixedLayout: args['isFixedLayout'] as bool,
          writingMode: (args['writingMode'] as String) == 'vertical'
              ? WritingMode.vertical
              : WritingMode.horizontal,
        ));
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AndroidView(
      viewType: 'cc.ugotit.elinkbook/epub_reader_view',
      onPlatformViewCreated: _onPlatformViewCreated,
    );
  }
}
```

- [ ] **Step 4：執行測試確認通過**

Run：
```bash
flutter test test/reader/epub_reader_view_test.dart
```
Expected：`All tests passed!`（4 項測試）。

- [ ] **Step 5：全量測試與靜態分析確認無回歸**

Run（於 `app/` 目錄下）：
```bash
flutter test
flutter analyze
```
Expected：`flutter test` 全數通過（既有 110 項 + 本次新增 4 項，共 114 項）；`flutter analyze` 顯示 `No issues found!`。

**⚠️ 已知會失敗的既有測試（本 Step 預期會發現，留給 Step 6 處理）：** `app/test/screens/reader_screen_test.dart` 目前仍引用 `Key('reader_writing_mode_toggle')`／`Key('reader_page_turn_mode_toggle')`，這兩個按鈕與其背後呼叫的 `setWritingMode`/`setPageTurnMode` 屬於 `ReaderScreen`（不是本 Task 修改的 `EpubReaderView`），本 Task 不會讓它們編譯失敗或壞掉——`EpubReaderView` 本身向下相容（新參數皆為 optional）。若執行後這兩個測試意外失敗，先確認失敗訊息是否與本 Task 的改動直接相關；若無關，屬於 Task 3（原生端移除 `setWritingMode`/`setPageTurnMode`）之後才會顯現的問題，留待 Task 3 完成後一併處理，不在本 Task 卡關。

- [ ] **Step 6：Commit**

```bash
git add app/lib/reader/epub_reader_view.dart app/test/reader/epub_reader_view_test.dart
git commit -m "Add batch preference parameters to EpubReaderView"
```

---

### Task 3：`EpubReaderView.kt` 原生端契約擴充與字型登記

**Files:**
- Modify: `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt`

**Interfaces:**
- Consumes: Task 2 送出的 method channel 契約（`openBook` 的 `initialPreferences` 參數、`setPreferences` 呼叫格式）；Task 1 決定的 5 個字型家族名稱字串（`SourceHanSansTC`／`SourceHanSerifTC`／`GuanKiapTsingKhai`／`TaiwanPearl`／`GenRyuMinTW`，須與 Task 1 的 `AppFont.familyName` 逐字一致）
- Produces: 無新 Dart 可見介面（純原生端實作，契約已由 Task 2 定義）

**本 Task 無自動化測試**（沿用 `issues.md` 已記載的既有測試限制：原生端 Kotlin 邏輯無法透過 `flutter test` 無裝置驗證，實際裝置行為驗證留給 Issue 6）。驗收方式為 `flutter build apk --debug` 成功建置（Kotlin 編譯通過，無語法/型別錯誤）。

- [ ] **Step 1：新增 import**

開啟 `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt`，把：

```kotlin
import androidx.fragment.app.commitNow
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import org.readium.r2.navigator.epub.EpubNavigatorFactory
import org.readium.r2.navigator.epub.EpubNavigatorFragment
import org.readium.r2.navigator.epub.EpubPreferences
import org.readium.r2.shared.publication.Layout
```

改為：

```kotlin
import androidx.fragment.app.commitNow
import io.flutter.FlutterInjector
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import org.readium.r2.navigator.epub.EpubNavigatorFactory
import org.readium.r2.navigator.epub.EpubNavigatorFragment
import org.readium.r2.navigator.epub.EpubPreferences
import org.readium.r2.navigator.preferences.FontFamily
import org.readium.r2.navigator.preferences.TextAlign
import org.readium.r2.shared.publication.Layout
```

- [ ] **Step 2：更新 `currentPreferences` 欄位註解**

把：

```kotlin
    /**
     * 目前已生效的完整偏好設定（見 docs/adr/0004-epub-reader-page-turn-mode-contract.md）。
     * `setWritingMode`／`setPageTurnMode` 都是「合併進這個物件、再整組送出」，而不是
     * 各自建構獨立的 EpubPreferences 覆蓋——否則兩者會互相把對方剛設定好的欄位
     * 重設回預設值。這是 Issue 1 建立 setWritingMode 時就已預期、留待日後補上的合併
     * 機制，本 issue 引入第二種偏好維度時一併補齊。
     *
     * 【未來注意】目前只有使用者手動呼叫 setWritingMode/setPageTurnMode 時才會更新
     * 這個欄位並送出；openBook 完成當下不會主動代入任何已持久化的偏好設定。若未來
     * epic-3-fonts-layout 引入持久化，需要額外設計「開書當下就把已持久化偏好代入
     * currentPreferences 並送出」的機制，屆時再處理，本 issue 範圍內不需要。
     */
    private var currentPreferences = EpubPreferences()
```

改為：

```kotlin
    /**
     * 目前已生效的完整偏好設定（見
     * docs/adr/0006-epub-reader-batch-preferences-contract.md）。setPreferences
     * 與 openBook 的 initialPreferences 套用都是「合併進這個物件、再整組送出」，
     * 而不是各自建構獨立的 EpubPreferences 覆蓋——否則後送出的欄位會把先前已
     * 設定的其他欄位重設回預設值。openBook 完成後若 initialPreferences 非空，
     * 會在 attachNavigator() 內立即合併套用一次，不需等待後續 setPreferences
     * 呼叫（解決先前版本「持久化設定在開書當下沒有真正套用」的缺口）。
     */
    private var currentPreferences = EpubPreferences()
```

- [ ] **Step 3：改寫 `onMethodCall`，移除 `setWritingMode`／`setPageTurnMode`，新增 `setPreferences` 與轉換邏輯**

把：

```kotlin
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "openBook" -> {
                openBook(call.argument<String>("path"))
                result.success(null)
            }
            "setWritingMode" -> {
                setWritingMode(call.argument<String>("mode"))
                result.success(null)
            }
            "setPageTurnMode" -> {
                setPageTurnMode(call.argument<String>("mode"))
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    /**
     * 開書後即時切換橫直排，不重新 openBook（見
     * docs/adr/0003-epub-reader-writing-mode-contract.md）。書本尚未成功
     * 開啟（navigatorFragment 仍為 null）時靜默忽略——Dart 端只會在
     * onPageRendered 觸發之後才送出這個指令，理論上不會發生。
     *
     * 與 currentPreferences 合併後才送出（見 docs/adr/0004-epub-reader-page-turn-mode-contract.md），
     * 確保不會覆蓋 setPageTurnMode 已設定的 scroll 偏好。
     */
    private fun setWritingMode(mode: String?) {
        currentPreferences = currentPreferences.plus(EpubPreferences(verticalText = mode == "vertical"))
        navigatorFragment?.submitPreferences(currentPreferences)
    }

    /**
     * 開書後即時切換分頁／捲動換頁模式，不重新 openBook（見
     * docs/adr/0004-epub-reader-page-turn-mode-contract.md）。書本尚未成功
     * 開啟時靜默忽略，理由同 setWritingMode。與 currentPreferences 合併後
     * 才送出，確保不會覆蓋 setWritingMode 已設定的 verticalText 偏好。
     */
    private fun setPageTurnMode(mode: String?) {
        currentPreferences = currentPreferences.plus(EpubPreferences(scroll = mode == "scroll"))
        navigatorFragment?.submitPreferences(currentPreferences)
    }
```

改為：

```kotlin
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "openBook" -> {
                @Suppress("UNCHECKED_CAST")
                openBook(
                    call.argument<String>("path"),
                    call.argument<Map<String, Any?>>("initialPreferences"),
                )
                result.success(null)
            }
            "setPreferences" -> {
                @Suppress("UNCHECKED_CAST")
                setPreferences(call.arguments as? Map<String, Any?>)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    /**
     * 合併 [preferences] 進 currentPreferences 並整組送出，取代原本各自獨立的
     * setWritingMode／setPageTurnMode（見
     * docs/adr/0006-epub-reader-batch-preferences-contract.md）。書本尚未成功
     * 開啟（navigatorFragment 仍為 null）時靜默忽略——Dart 端只會在
     * onPageRendered 觸發之後才送出這個指令，理論上不會發生。
     */
    private fun setPreferences(preferences: Map<String, Any?>?) {
        if (preferences == null) return
        currentPreferences = currentPreferences.plus(buildPreferencesFromMap(preferences))
        navigatorFragment?.submitPreferences(currentPreferences)
    }

    /**
     * 把 Dart 端送來的偏好設定 map（openBook 的 initialPreferences，或
     * setPreferences 的參數，兩者格式相同）轉換為 EpubPreferences；未出現在
     * map 中的 key 對應到該欄位的 null（交由 currentPreferences.plus() 決定
     * 最終生效值，不覆蓋既有已設定的其他欄位）。
     */
    private fun buildPreferencesFromMap(map: Map<String, Any?>): EpubPreferences {
        return EpubPreferences(
            verticalText = (map["writingMode"] as? String)?.let { it == "vertical" },
            scroll = (map["pageTurnMode"] as? String)?.let { it == "scroll" },
            fontFamily = (map["fontFamily"] as? String)?.let { FontFamily(it) },
            fontSize = (map["fontSize"] as? Number)?.toDouble(),
            fontWeight = (map["fontWeight"] as? Number)?.toDouble(),
            lineHeight = (map["lineHeight"] as? Number)?.toDouble(),
            paragraphSpacing = (map["paragraphSpacing"] as? Number)?.toDouble(),
            pageMargins = (map["pageMargins"] as? Number)?.toDouble(),
            textAlign = (map["textAlign"] as? String)?.let { textAlignFromName(it) },
            publisherStyles = map["publisherStyles"] as? Boolean,
        )
    }

    private fun textAlignFromName(name: String): TextAlign? {
        return when (name) {
            "center" -> TextAlign.CENTER
            "justify" -> TextAlign.JUSTIFY
            "start" -> TextAlign.START
            "end" -> TextAlign.END
            "left" -> TextAlign.LEFT
            "right" -> TextAlign.RIGHT
            else -> null
        }
    }

    /**
     * 登記 5 款內建字型（FR-09），讓 Readium 內嵌的 WebView 能實際載入本地
     * asset 字型檔案（見 docs/epics/epic-3-fonts-layout/spec.md「自訂字型
     * 如何讓原生 WebView 實際載入」）。這 5 個 family 名稱字串須與 Dart 端
     * `AppFont.familyName`（app/lib/reader/app_font.dart）逐字一致。只需在
     * attachNavigator() 執行一次，字型集合固定、不隨後續 setPreferences
     * 呼叫變動。
     */
    private fun buildFontFamiliesConfiguration(): EpubNavigatorFragment.Configuration {
        val loader = FlutterInjector.instance().flutterLoader()
        val fontAssets = mapOf(
            "SourceHanSansTC" to "assets/fonts/SourceHanSansTC-VF.ttf",
            "SourceHanSerifTC" to "assets/fonts/SourceHanSerifTC-VF.ttf",
            "GuanKiapTsingKhai" to "assets/fonts/GuanKiapTsingKhai.ttf",
            "TaiwanPearl" to "assets/fonts/TaiwanPearl-Regular.ttf",
            "GenRyuMinTW" to "assets/fonts/GenRyuMinTW-Regular.ttf",
        )
        val lookupKeys = fontAssets.mapValues { (_, path) -> loader.getLookupKeyForAsset(path) }
        return EpubNavigatorFragment.Configuration {
            servedAssets = lookupKeys.values.toList()
            for ((familyName, lookupKey) in lookupKeys) {
                addFontFamilyDeclaration(
                    fontFamily = FontFamily(familyName),
                    alternates = listOf(FontFamily.SANS_SERIF),
                ) {
                    addFontFace {
                        addSource(lookupKey, preload = true)
                    }
                }
            }
        }
    }
```

- [ ] **Step 4：擴充 `openBook` 簽章**

把：

```kotlin
    private fun openBook(path: String?) {
        if (path == null) {
            channel.invokeMethod("onError", "缺少檔案路徑")
            return
        }
        pageReported = false
        scope.launch {
```

改為：

```kotlin
    private fun openBook(path: String?, initialPreferences: Map<String, Any?>?) {
        if (path == null) {
            channel.invokeMethod("onError", "缺少檔案路徑")
            return
        }
        pageReported = false
        scope.launch {
```

再把（同一個函式內）：

```kotlin
                if (isDisposed) {
                    openedPublication.close()
                    return@launch
                }
                attachNavigator(openedPublication)
```

改為：

```kotlin
                if (isDisposed) {
                    openedPublication.close()
                    return@launch
                }
                attachNavigator(openedPublication, initialPreferences)
```

- [ ] **Step 5：擴充 `attachNavigator`，套用字型登記與 `initialPreferences`**

把：

```kotlin
    private fun attachNavigator(openedPublication: Publication) {
        // commitNow 在 Activity 已經過了 onSaveInstanceState（例如解析完成前使用者恰好把
        // App 切到背景）時會丟出 IllegalStateException；containerId 若因為合成模式改變
        // 等原因無法解析到實際 View（見上方類別註解），也可能丟出 IllegalArgumentException。
        // 兩者都必須攔截並改走 onError，否則例外會發生在 scope.launch 內成為未攔截的
        // 協程例外，導致 Flutter 端卡住或整個 App 崩潰，繞過既有的錯誤回報機制。
        try {
            publication = openedPublication
            val navigatorFactory = EpubNavigatorFactory(publication = openedPublication)
            val fragmentFactory = navigatorFactory.createFragmentFactory(
                initialLocator = null,
                listener = this,
                paginationListener = this,
            )
            installedFragmentFactory = fragmentFactory
            activity.supportFragmentManager.fragmentFactory = fragmentFactory
            activity.supportFragmentManager.commitNow(allowStateLoss = true) {
                add<EpubNavigatorFragment>(containerId, args = Bundle(), tag = fragmentTag)
            }
            navigatorFragment = activity.supportFragmentManager
                .findFragmentByTag(fragmentTag) as? EpubNavigatorFragment
        } catch (e: Exception) {
            // 掛載失敗時 Fragment 沒有真正附著到任何畫面上，Publication 不會再被使用，
            // 必須主動關閉釋放資源——與 openBook() 中 isDisposed 分支的做法一致。
            publication = null
            openedPublication.close()
            channel.invokeMethod("onError", "掛載 EPUB 閱讀畫面失敗：${e.message}")
        }
    }
```

改為：

```kotlin
    private fun attachNavigator(openedPublication: Publication, initialPreferences: Map<String, Any?>?) {
        // commitNow 在 Activity 已經過了 onSaveInstanceState（例如解析完成前使用者恰好把
        // App 切到背景）時會丟出 IllegalStateException；containerId 若因為合成模式改變
        // 等原因無法解析到實際 View（見上方類別註解），也可能丟出 IllegalArgumentException。
        // 兩者都必須攔截並改走 onError，否則例外會發生在 scope.launch 內成為未攔截的
        // 協程例外，導致 Flutter 端卡住或整個 App 崩潰，繞過既有的錯誤回報機制。
        try {
            publication = openedPublication
            val navigatorFactory = EpubNavigatorFactory(publication = openedPublication)
            val fragmentFactory = navigatorFactory.createFragmentFactory(
                initialLocator = null,
                listener = this,
                paginationListener = this,
                configuration = buildFontFamiliesConfiguration(),
            )
            installedFragmentFactory = fragmentFactory
            activity.supportFragmentManager.fragmentFactory = fragmentFactory
            activity.supportFragmentManager.commitNow(allowStateLoss = true) {
                add<EpubNavigatorFragment>(containerId, args = Bundle(), tag = fragmentTag)
            }
            navigatorFragment = activity.supportFragmentManager
                .findFragmentByTag(fragmentTag) as? EpubNavigatorFragment
            if (initialPreferences != null && initialPreferences.isNotEmpty()) {
                currentPreferences = currentPreferences.plus(buildPreferencesFromMap(initialPreferences))
                navigatorFragment?.submitPreferences(currentPreferences)
            }
        } catch (e: Exception) {
            // 掛載失敗時 Fragment 沒有真正附著到任何畫面上，Publication 不會再被使用，
            // 必須主動關閉釋放資源——與 openBook() 中 isDisposed 分支的做法一致。
            publication = null
            openedPublication.close()
            channel.invokeMethod("onError", "掛載 EPUB 閱讀畫面失敗：${e.message}")
        }
    }
```

- [ ] **Step 6：建置確認編譯成功**

Run（於 `app/` 目錄下）：
```bash
flutter build apk --debug
```
Expected：建置成功（`Built build\app\outputs\flutter-apk\app-debug.apk`），無 Kotlin 編譯錯誤。

- [ ] **Step 7：Commit**

```bash
git add app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt
git commit -m "Add batch preferences and font family registration to native EpubReaderView"
```

---

### Task 4：`ReaderScreen` 呼叫端同步調整（既有橫直排/換頁模式測試修正）

**Files:**
- Modify: `app/lib/screens/reader_screen.dart`
- Modify: `app/test/screens/reader_screen_test.dart`

**Interfaces:**
- Consumes: Task 2 完成的 `EpubReaderView`（既有 `writingMode`/`pageTurnMode` 參數行為不變，本 Task 不需要新增任何新版面偏好參數的傳遞——那是後續 Issue 3/4 的責任，見 `spec.md`「範圍外」）
- Produces: 無新公開介面；確認既有橫直排/換頁模式切換行為在契約擴充後依然正確

**背景：** Task 2 移除了 Dart 端呼叫 `setWritingMode`/`setPageTurnMode` 的舊寫法（改為統一走 `setPreferences`），但 `ReaderScreen` 呼叫 `EpubReaderView` 時傳入 `writingMode`/`pageTurnMode` 的既有程式碼**不需要修改**——這兩個建構參數本身的名稱、型別、語意完全沒變，`EpubReaderView` 內部已經處理好新的 map 組裝邏輯。本 Task 只需確認 `ReaderScreen` 既有的 `reader_writing_mode_toggle`/`reader_page_turn_mode_toggle` 相關測試在整個契約擴充後仍然通過，不需要異動 `reader_screen.dart` 本身的程式碼。

- [ ] **Step 1：執行 `ReaderScreen` 既有測試確認無回歸**

Run（於 `app/` 目錄下）：
```bash
flutter test test/screens/reader_screen_test.dart
```
Expected：`All tests passed!`（既有 4 項全數通過）——因為 `ReaderScreen` 對 `EpubReaderView` 的呼叫方式（`writingMode:`/`pageTurnMode:` 具名參數傳遞）完全沒有變動，且新增的 8 個偏好參數皆為 optional、預設為 `null`，`ReaderScreen` 未傳入時行為與擴充前完全一致。

- [ ] **Step 2：若 Step 1 測試失敗，記錄具體失敗原因並修正**

若 Step 1 的測試意外失敗（例如：實測發現 `EpubReaderView` 新增參數的預設值與舊行為有落差），在此記錄實際失敗訊息，並依失敗原因調整 `app/lib/screens/reader_screen.dart` 或 `app/test/screens/reader_screen_test.dart`（**不可**盲目跳過或刪除失敗的斷言）。若測試通過（預期結果），本 Step 無需任何程式碼異動，直接跳到 Step 3。

- [ ] **Step 3：全量測試與靜態分析確認整個 Issue 無回歸**

Run（於 `app/` 目錄下）：
```bash
flutter test
flutter analyze
```
Expected：`flutter test` 全數通過（114 項，Task 1-3 新增的測試 + 既有全部測試）；`flutter analyze` 顯示 `No issues found!`。

- [ ] **Step 4：Commit（僅當 Step 2 有實際異動時才需要）**

若 Step 2 沒有任何程式碼異動，本 Task 不需要額外 commit（Task 1-3 的 commit 已涵蓋全部異動）。若 Step 2 確實修正了 `reader_screen.dart`/其測試，執行：

```bash
git add app/lib/screens/reader_screen.dart app/test/screens/reader_screen_test.dart
git commit -m "Fix ReaderScreen tests after EpubReaderView batch preferences contract change"
```

---

## 自我審查紀錄

- **Spec 涵蓋範圍：** `issues.md` Issue 2 列出的 3 項產出（Dart 端 `EpubReaderView` 契約擴充、原生端 `EpubReaderView.kt` 契約擴充、字型素材登記）依序對應 Task 2、Task 3、Task 1；`spec.md`「介面」章節定義的 `EpubReaderView` 新建構參數、map key 對應、`EpubPreferences` 完整欄位皆逐字對應到 Task 2/Task 3 的程式碼。Task 4 涵蓋 `issues.md` 驗收標準「既有的 writingMode/pageTurnMode 相關測試需同步調整...不得因本次契約異動而遺留呼叫已移除方法的測試程式碼」——確認後發現既有 `reader_screen_test.dart` 並未直接呼叫 `setWritingMode`/`setPageTurnMode`（那是 `EpubReaderView` 內部實作細節，`ReaderScreen` 只透過建構參數傳遞），故本 issue 範圍內不需要修改 `ReaderScreen` 本身，但仍保留 Task 4 作為驗證關卡，避免遺漏。
- **撰寫計劃階段發現並修正的架構缺口（已取得使用者確認後處理）：** `spec.md` 原先假設「`pubspec.yaml` 的 `fonts:` 區塊即可讓 `fontFamily` 生效」，經反編譯＋對照官方原始碼（`github.com/readium/kotlin-toolkit` tag `3.3.0`）查證後發現這是錯誤假設（`fonts:` 只影響 Flutter 自己的 Skia 渲染，與原生 WebView 完全無關）；已回頭修訂 `spec.md`「自訂字型如何讓原生 WebView 實際載入」、`issues.md` Issue 2/Issue 6 描述、`docs/adr/0003`/`0004` 的狀態欄位，本計劃的 Task 1/Task 3 採用修正後的正確機制（`EpubNavigatorFragment.Configuration.addFontFamilyDeclaration` + `FlutterInjector.flutterLoader().getLookupKeyForAsset`）。同時發現並修正 `spec.md` 對 `EpubPreferences.fontFamily` 型別的誤記（`String?` → 實際為 `FontFamily?`）。
- **與既有慣例的一致性：** `EpubReaderView` 的 `_buildPreferencesMap`/`_preferencesChanged` 沿用既有 `didUpdateWidget` 偵測變動的風格；原生端 `buildPreferencesFromMap` 的 `(map[...] as? Number)?.toDouble()` 寫法與 Epic 3 Issue 1 `BookReaderPrefs.fromMap` 處理 SQLite 數值的風格呼應（同樣是「來源可能回傳非預期的數值子型別，統一轉為 Double」的防禦性寫法），維持專案內對「外部資料來源數值型別不可盡信」的一致處理方式。
- **測試策略的可驗證性：** Task 2 的 `SystemChannels.platform_views` mock 技巧已在撰寫本計劃時實際執行 `flutter test` 驗證可行（非臆測），確保交付執行的 Agent 不會卡在「這個測試技巧到底可不可行」的未知風險上。
- **佔位符掃描：** 所有步驟皆含完整程式碼、明確指令與預期輸出，無 TBD/佔位文字。
- **型別/命名一致性：** `AppFont.familyName` 回傳的 5 個字串（`SourceHanSansTC`／`SourceHanSerifTC`／`GuanKiapTsingKhai`／`TaiwanPearl`／`GenRyuMinTW`）在 Task 1（Dart）與 Task 3（Kotlin `buildFontFamiliesConfiguration`）的程式碼中逐字一致；`EpubReaderView` 新增的 8 個建構參數名稱與型別（Task 2）與 `spec.md`「介面」章節定義的名稱完全一致，供後續 Issue 3/4/5 的實作者直接引用。
- **已知、記錄在案但刻意不處理的情形：** 原生端字型登記／`initialPreferences`/`setPreferences` 是否真的讓 Readium 產生預期的渲染效果，本計劃的驗收僅止於編譯成功（`flutter build apk --debug`），實際裝置行為驗證留給 Issue 6（`issues.md` 已明確記載此範圍界線與對應的「自訂字型實際載入驗證」項目）。
