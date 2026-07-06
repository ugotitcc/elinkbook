# Issue 1 實作計劃：`EpubReaderView` 契約擴充——`setWritingMode` + `onLayoutResolved`

> **給執行的 Agent：** 建議使用 superpowers:subagent-driven-development（推薦）或 superpowers:executing-plans 逐任務執行本計劃。步驟採用核取方塊（`- [ ]`）語法追蹤進度。

**目標：** 依 `docs/adr/0003-epub-reader-writing-mode-contract.md`，把 `EpubReaderView` 從單次靜態開書擴充為支援「開書後即時切換橫直排」（`setWritingMode`）與「開書後一次性回報自動判斷結果」（`onLayoutResolved`）的雙向契約，讓 Issue 2（`ReaderScreen` 切換按鈕 UI）之後可以串接。

**架構：** Dart 端 `EpubReaderView` 新增 `writingMode: WritingMode?` 輸入參數（`didUpdateWidget` 偵測變動後呼叫原生 `setWritingMode`）與 `onLayoutResolved: ValueChanged<EpubLayoutInfo>?` 回呼；原生端 `EpubReaderView.kt` 持有目前 attach 的 `EpubNavigatorFragment` 參照，`setWritingMode` 直接呼叫其 `submitPreferences(EpubPreferences(verticalText = ...))`，`onLayoutResolved` 則在 `onPageLoaded()` 時讀取 `Publication.metadata.layout`（是否為定樣式）與 `EpubNavigatorFragment.settings.value.verticalText`（Readium 已解析完成的直排/橫排結果，不需自行呼叫 `EpubSettingsResolver`）組出結果送回。

**技術棧：** Kotlin、Readium `readium-navigator`/`readium-shared` 3.3.0（`EpubPreferences`、`EpubNavigatorFragment.settings: StateFlow<EpubSettings>`、`Publication.metadata.layout: Layout`）、Dart/Flutter、`integration_test`、Python 3（僅用於一次性產生二進位 EPUB 測試 fixture，不是專案相依套件）。

## ⚠️ 執行前環境確認事項

Task 3、4 的驗證步驟須在真實 Android 模擬器/裝置上執行——執行前請先確認 `flutter devices`（於 `app/` 目錄下）能列出至少一個 Android 裝置/模擬器。

## 全域限制條件

- `openBook(path)` → `onPageRendered()`/`onError(message)` 既有契約簽章與行為**不變**；本 issue 只新增 `setWritingMode`/`onLayoutResolved`。
- 沿用既有 per-instance method channel `cc.ugotit.elinkbook/epub_reader_view_$id`，**不**新增獨立 channel。
- 初次開書**不**主動設定 `verticalText`（維持 `null`），交由 Readium 依書本語言/閱讀方向自動判斷；`setWritingMode` 只在使用者/呼叫端主動要求切換時才送出。
- `ReaderScreen(filePath: String)` 對外簽章不受本 issue 影響——`ReaderScreen` 本身的串接是 Issue 2 的範圍，本 issue 只動 `EpubReaderView` 與其原生對應端。
- 本 issue **不得**修改 `PdfReaderView.kt`（PDF 無 writing-mode 概念）。
- 所有新增的程式碼註解維持正體中文。
- `flutter analyze` 全程必須維持 `No issues found!`。

---

### Task 1：`WritingMode`／`EpubLayoutInfo` 值型別

**Files:**
- Create: `app/lib/reader/writing_mode.dart`
- Create: `app/test/reader/writing_mode_test.dart`

**Interfaces:**
- Consumes: 無
- Produces: `enum WritingMode { horizontal, vertical }`；`class EpubLayoutInfo { final bool isFixedLayout; final WritingMode writingMode; }`（含 `==`/`hashCode`），供 Task 3、4 的 `EpubReaderView` 使用。

- [ ] **Step 1：寫失敗測試**

建立 `app/test/reader/writing_mode_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/writing_mode.dart';

void main() {
  test('EpubLayoutInfo 建構後可讀取欄位', () {
    const info =
        EpubLayoutInfo(isFixedLayout: false, writingMode: WritingMode.vertical);
    expect(info.isFixedLayout, isFalse);
    expect(info.writingMode, WritingMode.vertical);
  });

  test('EpubLayoutInfo 欄位皆相同時相等', () {
    const a =
        EpubLayoutInfo(isFixedLayout: true, writingMode: WritingMode.horizontal);
    const b =
        EpubLayoutInfo(isFixedLayout: true, writingMode: WritingMode.horizontal);
    expect(a, equals(b));
    expect(a.hashCode, equals(b.hashCode));
  });

  test('EpubLayoutInfo 欄位不同時不相等', () {
    const a =
        EpubLayoutInfo(isFixedLayout: false, writingMode: WritingMode.vertical);
    const b =
        EpubLayoutInfo(isFixedLayout: true, writingMode: WritingMode.vertical);
    expect(a, isNot(equals(b)));
  });
}
```

- [ ] **Step 2：執行測試確認失敗（型別尚不存在）**

Run（於 `app/` 目錄下）：
```bash
flutter test test/reader/writing_mode_test.dart
```
Expected: 編譯錯誤，找不到 `package:elinkbook/reader/writing_mode.dart`。

- [ ] **Step 3：建立 `writing_mode.dart`**

建立 `app/lib/reader/writing_mode.dart`：

```dart
/// 直排／橫排狀態，對應 Readium `EpubPreferences.verticalText`（見
/// docs/adr/0003-epub-reader-writing-mode-contract.md）。
enum WritingMode { horizontal, vertical }

/// [EpubReaderView] 開書完成後一次性回報的版面資訊。
class EpubLayoutInfo {
  final bool isFixedLayout;
  final WritingMode writingMode;

  const EpubLayoutInfo({
    required this.isFixedLayout,
    required this.writingMode,
  });

  @override
  bool operator ==(Object other) =>
      other is EpubLayoutInfo &&
      other.isFixedLayout == isFixedLayout &&
      other.writingMode == writingMode;

  @override
  int get hashCode => Object.hash(isFixedLayout, writingMode);

  @override
  String toString() =>
      'EpubLayoutInfo(isFixedLayout: $isFixedLayout, writingMode: $writingMode)';
}
```

- [ ] **Step 4：執行測試確認通過**

Run：
```bash
flutter test test/reader/writing_mode_test.dart
```
Expected: `All tests passed!`（3 項測試）。

- [ ] **Step 5：Commit**

```bash
git add app/lib/reader/writing_mode.dart app/test/reader/writing_mode_test.dart
git commit -m "Add WritingMode/EpubLayoutInfo value types"
```

---

### Task 2：建立測試 fixtures（`sample_horizontal.epub`、`sample_fixed_layout.epub`）

**Files:**
- Create: `app/test/fixtures/sample_horizontal.epub`
- Create: `app/test/fixtures/sample_fixed_layout.epub`
- Modify: `app/pubspec.yaml`

**Interfaces:**
- Consumes: 無
- Produces: 兩個新的 EPUB 測試 fixture，供 Task 3 的 `integration_test` 使用；連同既有 `app/test/fixtures/sample.epub`（`dc:language=zh-TW`，未設定 `page-progression-direction`）共三本書覆蓋三種判斷結果組合。

**背景（為何不需要另外做「直排」fixture）：** 用 `javap` 反編譯 `readium-navigator:3.3.0` 的 `EpubSettingsResolver` 確認其邏輯為：`resolveVerticalText(pref, language, readingProgression) = pref ?: (language.isCjk() && readingProgression == RTL)`；而 `readingProgression` 在 OPF 未指定 `page-progression-direction` 時，會 fallback 成 `language.isRtl()`（`LanguageKt.isRtl()` 明確把 `zh-tw`/`zh-hant` 視为 RTL）。既有 `sample.epub`（`dc:language=zh-TW`、無 `page-progression-direction`）因此會被 Readium 自動解析成**直排**——不需要另外做一本直排 fixture。本 Task 只需要補「語言非 CJK（驗證停留橫排）」與「定樣式（驗證 `isFixedLayout=true`）」兩種既有 fixture 未涵蓋的情境。

- [ ] **Step 1：撰寫並執行 fixture 產生腳本**

在 `app/` 目錄下建立暫時腳本 `app/test/fixtures/_build_fixtures.py`（本步驟結束後會刪除，不會提交進版控）：

```python
import zipfile

CONTAINER_XML = """<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>
"""

HORIZONTAL_OPF = """<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="pub-id">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="pub-id">urn:uuid:00000000-0000-0000-0000-000000000002</dc:identifier>
    <dc:title>elinkBook Sample EPUB (Horizontal)</dc:title>
    <dc:language>en</dc:language>
    <meta property="dcterms:modified">2026-01-01T00:00:00Z</meta>
  </metadata>
  <manifest>
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
    <item id="chapter1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine>
    <itemref idref="chapter1"/>
  </spine>
</package>
"""

HORIZONTAL_NAV = """<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
<head><title>Table of Contents</title></head>
<body>
  <nav epub:type="toc">
    <ol>
      <li><a href="chapter1.xhtml">Chapter 1</a></li>
    </ol>
  </nav>
</body>
</html>
"""

HORIZONTAL_CHAPTER1 = """<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" lang="en" xml:lang="en">
<head><title>Chapter 1</title></head>
<body>
  <h1>Chapter 1</h1>
  <p>This is a sample English EPUB used to verify that non-CJK books resolve to horizontal writing mode.</p>
</body>
</html>
"""

FIXED_LAYOUT_OPF = """<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="pub-id" prefix="rendition: http://www.idpf.org/vocab/rendition/#">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="pub-id">urn:uuid:00000000-0000-0000-0000-000000000003</dc:identifier>
    <dc:title>elinkBook 範例 EPUB（定樣式）</dc:title>
    <dc:language>zh-TW</dc:language>
    <meta property="dcterms:modified">2026-01-01T00:00:00Z</meta>
    <meta property="rendition:layout">pre-paginated</meta>
  </metadata>
  <manifest>
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
    <item id="chapter1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine>
    <itemref idref="chapter1"/>
  </spine>
</package>
"""

FIXED_LAYOUT_NAV = """<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
<head><title>目錄</title></head>
<body>
  <nav epub:type="toc">
    <ol>
      <li><a href="chapter1.xhtml">第一章</a></li>
    </ol>
  </nav>
</body>
</html>
"""

FIXED_LAYOUT_CHAPTER1 = """<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" lang="zh-TW" xml:lang="zh-TW">
<head><title>第一章</title><meta name="viewport" content="width=600, height=800"/></head>
<body>
  <h1>第一章</h1>
  <p>這是 elinkBook 用於驗證定樣式（fixed-layout）EPUB 的範例內容。</p>
</body>
</html>
"""


def build_epub(path, opf, nav, chapter1):
    with zipfile.ZipFile(path, "w") as zf:
        zf.writestr("mimetype", "application/epub+zip", compress_type=zipfile.ZIP_STORED)
        zf.writestr("META-INF/container.xml", CONTAINER_XML, compress_type=zipfile.ZIP_DEFLATED)
        zf.writestr("OEBPS/content.opf", opf, compress_type=zipfile.ZIP_DEFLATED)
        zf.writestr("OEBPS/nav.xhtml", nav, compress_type=zipfile.ZIP_DEFLATED)
        zf.writestr("OEBPS/chapter1.xhtml", chapter1, compress_type=zipfile.ZIP_DEFLATED)


build_epub("sample_horizontal.epub", HORIZONTAL_OPF, HORIZONTAL_NAV, HORIZONTAL_CHAPTER1)
build_epub("sample_fixed_layout.epub", FIXED_LAYOUT_OPF, FIXED_LAYOUT_NAV, FIXED_LAYOUT_CHAPTER1)
print("done")
```

Run（於 `app/test/fixtures/` 目錄下）：
```bash
python _build_fixtures.py
python -c "
import zipfile
for name in ['sample_horizontal.epub', 'sample_fixed_layout.epub']:
    zf = zipfile.ZipFile(name)
    print(name, [(i.filename, i.compress_type) for i in zf.infolist()])
"
rm _build_fixtures.py
```
Expected：印出 `done`；第二個指令印出兩個檔案各自的 5 個項目（`mimetype` 的 `compress_type` 為 `0`／`ZIP_STORED` 且為第一個項目，其餘為 `8`／`ZIP_DEFLATED`）；`_build_fixtures.py` 已刪除，不會被提交進版控。

- [ ] **Step 2：在 `pubspec.yaml` 註冊新 asset**

開啟 `app/pubspec.yaml`，把：

```yaml
  assets:
    - test/fixtures/sample.pdf
    - test/fixtures/sample.epub
```

改為：

```yaml
  assets:
    - test/fixtures/sample.pdf
    - test/fixtures/sample.epub
    - test/fixtures/sample_horizontal.epub
    - test/fixtures/sample_fixed_layout.epub
```

- [ ] **Step 3：確認 asset 註冊無誤**

Run（於 `app/` 目錄下）：
```bash
flutter pub get
```
Expected：成功執行，無錯誤訊息。

- [ ] **Step 4：Commit**

```bash
git add app/test/fixtures/sample_horizontal.epub app/test/fixtures/sample_fixed_layout.epub app/pubspec.yaml
git commit -m "Add sample_horizontal.epub and sample_fixed_layout.epub test fixtures"
```

---

### Task 3：`onLayoutResolved`——開書後自動判斷結果回報

**Files:**
- Modify: `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt`
- Modify: `app/lib/reader/epub_reader_view.dart`
- Modify: `app/integration_test/epub_reader_view_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `WritingMode`/`EpubLayoutInfo`；Task 2 的 `sample_horizontal.epub`/`sample_fixed_layout.epub`
- Produces: `EpubReaderView`（Dart）新增 `onLayoutResolved: ValueChanged<EpubLayoutInfo>?` 建構參數；原生端 `onLayoutResolved` method channel 訊息，供 Task 4 與後續 Issue 2 使用。

> 本專案既有慣例（見 `app/integration_test/epub_reader_view_test.dart` 與 `app/test/screens/reader_screen_test.dart` 開頭註解）：`AndroidView` 的 per-instance method channel 只有在真實原生引擎建立 PlatformView 後才會運作，一般 `flutter test`（無裝置）無法驅動，因此本 Task 的行為驗證全部透過 `integration_test` 在真實裝置上執行，不新增 `app/test/` 底下的 widget test。

- [ ] **Step 1：於 `integration_test/epub_reader_view_test.dart` 新增三項測試**

開啟 `app/integration_test/epub_reader_view_test.dart`，把開頭的 import：

```dart
import 'package:elinkbook/reader/epub_reader_view.dart';
```

改為：

```dart
import 'package:elinkbook/reader/epub_reader_view.dart';
import 'package:elinkbook/reader/writing_mode.dart';
```

在檔案最後一個 `testWidgets`（『開啟指向不存在資源的 content:// URI 觸發 onError』）之後、`main()` 的收尾 `}` 之前，新增三項測試：

```dart
  testWidgets('開啟直排 CJK 範例 EPUB，onLayoutResolved 回報直排且非定樣式',
      (tester) async {
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample.epub', 'sample_layout_vertical.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    final completer = Completer<void>();
    EpubLayoutInfo? layoutInfo;

    await tester.pumpWidget(
      MaterialApp(
        home: EpubReaderView(
          filePath: samplePath,
          onPageRendered: () {},
          onError: (message) {
            if (!completer.isCompleted) completer.complete();
          },
          onLayoutResolved: (info) {
            layoutInfo = info;
            if (!completer.isCompleted) completer.complete();
          },
        ),
      ),
    );

    await completer.future.timeout(const Duration(seconds: 10));
    await tester.pumpAndSettle();

    expect(layoutInfo, isNotNull);
    expect(layoutInfo!.isFixedLayout, isFalse);
    expect(layoutInfo!.writingMode, WritingMode.vertical);
  });

  testWidgets('開啟英文範例 EPUB，onLayoutResolved 回報橫排', (tester) async {
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample_horizontal.epub', 'sample_layout_horizontal.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    final completer = Completer<void>();
    EpubLayoutInfo? layoutInfo;

    await tester.pumpWidget(
      MaterialApp(
        home: EpubReaderView(
          filePath: samplePath,
          onPageRendered: () {},
          onError: (message) {
            if (!completer.isCompleted) completer.complete();
          },
          onLayoutResolved: (info) {
            layoutInfo = info;
            if (!completer.isCompleted) completer.complete();
          },
        ),
      ),
    );

    await completer.future.timeout(const Duration(seconds: 10));
    await tester.pumpAndSettle();

    expect(layoutInfo, isNotNull);
    expect(layoutInfo!.isFixedLayout, isFalse);
    expect(layoutInfo!.writingMode, WritingMode.horizontal);
  });

  testWidgets('開啟定樣式範例 EPUB，onLayoutResolved 回報 isFixedLayout 為 true',
      (tester) async {
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample_fixed_layout.epub', 'sample_layout_fixed.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    final completer = Completer<void>();
    EpubLayoutInfo? layoutInfo;

    await tester.pumpWidget(
      MaterialApp(
        home: EpubReaderView(
          filePath: samplePath,
          onPageRendered: () {},
          onError: (message) {
            if (!completer.isCompleted) completer.complete();
          },
          onLayoutResolved: (info) {
            layoutInfo = info;
            if (!completer.isCompleted) completer.complete();
          },
        ),
      ),
    );

    await completer.future.timeout(const Duration(seconds: 10));
    await tester.pumpAndSettle();

    expect(layoutInfo, isNotNull);
    expect(layoutInfo!.isFixedLayout, isTrue);
  });
```

- [ ] **Step 2：於真實裝置/模擬器上執行測試確認新案例失敗**

Run（於 `app/` 目錄下；`<device-id>` 請替換為 `flutter devices` 列出的實際 Android 裝置/模擬器 ID）：
```bash
flutter test integration_test/epub_reader_view_test.dart -d <device-id>
```
Expected：編譯失敗——`EpubReaderView` 建構子尚無 `onLayoutResolved` 具名參數。

- [ ] **Step 3：擴充 `app/lib/reader/epub_reader_view.dart`**

把整份檔案內容改為：

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'writing_mode.dart';

/// 包裝原生 Android EpubReaderView（Readium kotlin-toolkit）的 Flutter widget，
/// 透過 AndroidView（PlatformView）嵌入畫面。給定 EPUB 檔案的裝置端絕對路徑，通知
/// 原生端渲染起始頁；渲染成功或失敗會分別觸發 [onPageRendered] 或 [onError]。
///
/// [writingMode] 為 null 時，開書當下不覆寫橫直排設定，交由 Readium 依書本
/// 語言／閱讀方向自動判斷（判斷結果透過 [onLayoutResolved] 回報一次）；設定
/// 為非 null 且與前次不同時，會即時呼叫原生端切換，不重新開書（見
/// docs/adr/0003-epub-reader-writing-mode-contract.md）。
///
/// 【刻意的設計，非疏漏】即使首次建構時 [writingMode] 就已是非 null，開書當下
/// 仍一律忽略它、交由自動判斷決定初始模式——[writingMode] 只用於開書後的後續
/// 切換（透過 [didUpdateWidget] 偵測變動）。目前唯一的呼叫端 `ReaderScreen`
/// 也一律等 [onLayoutResolved] 回報後才可能變更 [writingMode]，因此這個限制
/// 現階段不影響任何實際情境。
class EpubReaderView extends StatefulWidget {
  final String filePath;
  final VoidCallback onPageRendered;
  final ValueChanged<String> onError;
  final WritingMode? writingMode;
  final ValueChanged<EpubLayoutInfo>? onLayoutResolved;

  const EpubReaderView({
    super.key,
    required this.filePath,
    required this.onPageRendered,
    required this.onError,
    this.writingMode,
    this.onLayoutResolved,
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
    channel.invokeMethod('openBook', {'path': widget.filePath});
  }

  @override
  void didUpdateWidget(covariant EpubReaderView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newMode = widget.writingMode;
    if (newMode != null && newMode != oldWidget.writingMode) {
      _channel?.invokeMethod('setWritingMode', {
        'mode': newMode == WritingMode.vertical ? 'vertical' : 'horizontal',
      });
    }
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

（`didUpdateWidget` 這次一併加入，是因為 `writingMode` 欄位若不搭配偵測變動的邏輯就毫無用處；`setWritingMode` 的實際即時切換行為驗證屬於 Task 4，這裡先確保欄位與框架接線到位，不影響 Task 3 測試通過與否——Task 3 的三項新測試都沒有傳入 `writingMode`。）

- [ ] **Step 4：擴充 `EpubReaderView.kt`**

開啟 `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt`。

把 import 區塊中的：

```kotlin
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.publication.Publication
```

改為：

```kotlin
import org.readium.r2.shared.publication.Layout
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.publication.Publication
```

把欄位宣告區塊中的：

```kotlin
    private var publication: Publication? = null
    private var pageReported = false
    private var isDisposed = false
```

改為：

```kotlin
    private var publication: Publication? = null
    private var navigatorFragment: EpubNavigatorFragment? = null
    private var pageReported = false
    private var isDisposed = false
```

把 `attachNavigator()` 中的：

```kotlin
            activity.supportFragmentManager.fragmentFactory = fragmentFactory
            activity.supportFragmentManager.commitNow(allowStateLoss = true) {
                add<EpubNavigatorFragment>(containerId, args = Bundle(), tag = fragmentTag)
            }
        } catch (e: Exception) {
```

改為：

```kotlin
            activity.supportFragmentManager.fragmentFactory = fragmentFactory
            activity.supportFragmentManager.commitNow(allowStateLoss = true) {
                add<EpubNavigatorFragment>(containerId, args = Bundle(), tag = fragmentTag)
            }
            navigatorFragment = activity.supportFragmentManager
                .findFragmentByTag(fragmentTag) as? EpubNavigatorFragment
        } catch (e: Exception) {
```

把 `onPageLoaded()`：

```kotlin
    override fun onPageLoaded() {
        if (!pageReported) {
            pageReported = true
            channel.invokeMethod("onPageRendered", null)
        }
    }
```

改為：

```kotlin
    override fun onPageLoaded() {
        if (!pageReported) {
            pageReported = true
            channel.invokeMethod("onPageRendered", null)
            reportLayoutResolved()
        }
    }

    /**
     * 開書完成後一次性回報版面資訊給 Dart 端（見
     * docs/adr/0003-epub-reader-writing-mode-contract.md）：isFixedLayout
     * 讀取 Publication 詮釋資料；writingMode 讀取 Readium 依書本語言／閱讀
     * 方向自動解析出的結果——EpubNavigatorFragment.settings 是已解析完成的
     * StateFlow，直接讀取目前值即可，不需自行呼叫 EpubSettingsResolver。
     */
    private fun reportLayoutResolved() {
        val isFixedLayout = publication?.metadata?.layout == Layout.FIXED
        val isVertical = navigatorFragment?.settings?.value?.verticalText ?: false
        channel.invokeMethod(
            "onLayoutResolved",
            mapOf(
                "isFixedLayout" to isFixedLayout,
                "writingMode" to if (isVertical) "vertical" else "horizontal",
            ),
        )
    }
```

把 `dispose()` 中的：

```kotlin
        publication?.close()
        publication = null
    }
```

改為：

```kotlin
        publication?.close()
        publication = null
        navigatorFragment = null
    }
```

- [ ] **Step 5：於真實裝置/模擬器上重新執行測試確認全部通過**

Run：
```bash
flutter test integration_test/epub_reader_view_test.dart -d <device-id>
```
Expected：`All tests passed!`（既有 5 項 + 新增 3 項，共 8 項測試皆通過）。

- [ ] **Step 6：Commit**

```bash
git add app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt app/lib/reader/epub_reader_view.dart app/integration_test/epub_reader_view_test.dart
git commit -m "Add onLayoutResolved auto-detected writing mode reporting"
```

---

### Task 4：`setWritingMode`——開書後即時切換橫直排

**Files:**
- Modify: `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt`
- Modify: `app/integration_test/epub_reader_view_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `WritingMode`；Task 3 完成後的 `EpubReaderView`（Dart）`writingMode`/`didUpdateWidget` 接線
- Produces: 原生端 `setWritingMode` method channel 訊息處理完畢，`EpubReaderView` 契約（ADR 0003）至此完整實作，供 Issue 2 使用。

- [ ] **Step 1：於 `integration_test/epub_reader_view_test.dart` 新增切換測試**

在 Task 3 新增的三項測試之後、`main()` 的收尾 `}` 之前，新增：

```dart
  testWidgets('開書後呼叫 setWritingMode 切換橫直排，畫面持續渲染成功',
      (tester) async {
    final samplePath =
        await _stageAssetAsFile('test/fixtures/sample.epub', 'sample_switch.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    final renderedCompleter = Completer<void>();
    String? errorMessage;

    await tester.pumpWidget(
      MaterialApp(
        home: EpubReaderView(
          filePath: samplePath,
          writingMode: WritingMode.vertical,
          onPageRendered: () {
            if (!renderedCompleter.isCompleted) renderedCompleter.complete();
          },
          onError: (message) {
            errorMessage = message;
            if (!renderedCompleter.isCompleted) renderedCompleter.complete();
          },
        ),
      ),
    );
    await renderedCompleter.future.timeout(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    expect(errorMessage, isNull,
        reason: '初次開書應成功渲染，但 onError 訊息為: $errorMessage');

    // 重新 pump 同一個位置的 EpubReaderView 但改變 writingMode（filePath 不變，
    // Flutter 會重用既有 State 並呼叫 didUpdateWidget，觸發原生 setWritingMode，
    // 不會重新呼叫 openBook）。
    await tester.pumpWidget(
      MaterialApp(
        home: EpubReaderView(
          filePath: samplePath,
          writingMode: WritingMode.horizontal,
          onPageRendered: () {},
          onError: (message) => errorMessage = message,
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(errorMessage, isNull, reason: '切換為橫排後不應觸發 onError');

    // 再切換回直排，驗證來回切換皆穩定。
    await tester.pumpWidget(
      MaterialApp(
        home: EpubReaderView(
          filePath: samplePath,
          writingMode: WritingMode.vertical,
          onPageRendered: () {},
          onError: (message) => errorMessage = message,
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(errorMessage, isNull, reason: '切換回直排後不應觸發 onError');
  });
```

- [ ] **Step 2：於真實裝置/模擬器上執行測試確認新案例失敗**

Run：
```bash
flutter test integration_test/epub_reader_view_test.dart -d <device-id>
```
Expected：新增的切換測試逾時失敗（原生端尚未處理 `setWritingMode`，`didUpdateWidget` 送出的呼叫會落入既有 `onMethodCall` 的 `else -> result.notImplemented()` 分支，畫面本身仍持續渲染中——`onError` 不會被觸發，但因為 `errorMessage` 期望為 `isNull` 而目前程式邏輯尚未實作切換，最終斷言仍可能通過；因此本步驟改為觀察：在 Step 4 完成前，`setWritingMode` 呼叫不會產生任何原生端可觀察副作用，此為預期的「尚未實作」中間狀態）。若此步驟測試意外通過，直接進行 Step 3、4 補上實作與註解，不影響後續驗收。

- [ ] **Step 3：擴充 `EpubReaderView.kt`**

把 import 區塊中的：

```kotlin
import org.readium.r2.navigator.epub.EpubNavigatorFactory
import org.readium.r2.navigator.epub.EpubNavigatorFragment
```

改為：

```kotlin
import org.readium.r2.navigator.epub.EpubNavigatorFactory
import org.readium.r2.navigator.epub.EpubNavigatorFragment
import org.readium.r2.navigator.epub.EpubPreferences
```

把 `onMethodCall()`：

```kotlin
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "openBook" -> {
                openBook(call.argument<String>("path"))
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }
```

改為：

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
            else -> result.notImplemented()
        }
    }

    /**
     * 開書後即時切換橫直排，不重新 openBook（見
     * docs/adr/0003-epub-reader-writing-mode-contract.md）。書本尚未成功
     * 開啟（navigatorFragment 仍為 null）時靜默忽略——Dart 端只會在
     * onPageRendered 觸發之後才送出這個指令，理論上不會發生。
     *
     * 【未來注意】這裡直接建構全新的 EpubPreferences，只有 verticalText 有值、
     * 其餘欄位皆為預設 null。目前專案唯一會呼叫 submitPreferences() 的地方就是
     * 這裡，所以不會有問題；但一旦 epic-3-fonts-layout 引入字型大小/行距/邊距
     * 等其他偏好設定並也需要呼叫 submitPreferences()，這裡就必須改成與「目前
     * 已生效的偏好設定」合併（EpubPreferences 有提供 plus() 運算子可用於合併），
     * 否則每次切換橫直排都會把其他偏好重設回預設值。
     */
    private fun setWritingMode(mode: String?) {
        navigatorFragment?.submitPreferences(EpubPreferences(verticalText = mode == "vertical"))
    }
```

- [ ] **Step 4：於真實裝置/模擬器上重新執行測試確認全部通過**

Run：
```bash
flutter test integration_test/epub_reader_view_test.dart -d <device-id>
```
Expected：`All tests passed!`（既有 8 項 + 新增 1 項，共 9 項測試皆通過）。

- [ ] **Step 5：重新執行既有 EPUB 相關 `integration_test` 確認無回歸**

Run：
```bash
flutter test integration_test/reader_screen_test.dart -d <device-id>
flutter test integration_test/library_screen_test.dart -d <device-id>
```
Expected：全部 `All tests passed!`。

- [ ] **Step 6：靜態分析、建置與純 Dart 測試確認**

Run（於 `app/` 目錄下）：
```bash
flutter analyze
flutter build apk --debug
flutter test
```
Expected：`flutter analyze` 顯示 `No issues found!`；`flutter build apk --debug` 成功建置；`flutter test`（純 Dart/widget test）全數通過，無回歸。

- [ ] **Step 7：Commit**

```bash
git add app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt app/integration_test/epub_reader_view_test.dart
git commit -m "Add setWritingMode live switching support"
```

---

## 自我審查紀錄

- **Spec 涵蓋範圍**：`spec.md`「介面」章節定義的 `WritingMode`/`EpubLayoutInfo`（Task 1）、`EpubReaderView` 新增參數/回呼與 method channel 契約異動（Task 3、4）、測試 fixture 準備（Task 2，`spec.md`「測試決策」提到的「現有 sample.epub 是否符合待第一個實作 issue 確認」已在 Task 2 的背景說明中確認並解決）皆已對應到任務。`issues.md` Issue 1 的三類 `integration_test` 要求（自動判斷回報、即時切換不崩潰、非 CJK 回歸）分別對應 Task 3 的三項測試與 Task 4 的切換測試。
- **修正 `spec.md`/ADR 0003 原先描述的實作細節**：`spec.md`「原生 method channel 契約異動」與 ADR 0003 原先描述「讀取 `EpubSettingsResolver.resolveVerticalText(...)` 的解析結果」，經 `javap` 反編譯 `readium-navigator:3.3.0` 確認 `EpubNavigatorFragment` 已透過 `Configurable<EpubSettings, EpubPreferences>` 介面提供 `settings: StateFlow<EpubSettings>`，其中 `EpubSettings.verticalText` 就是已經解析完成的結果，不需要在原生端自行建構 `Language`/`ReadingProgression` 重新呼叫解析邏輯。本計劃採用直接讀取 `.settings.value.verticalText` 的簡化做法；建議本 issue 合併後回頭同步修訂 `spec.md`/ADR 0003 的對應描述文字（不影響對外行為與測試斷言，純粹是原生端內部實作細節的簡化）。
- **佔位符掃描**：所有步驟皆含完整程式碼、明確指令與預期輸出；Task 2 的 fixture 產生腳本已於規劃階段實際執行驗證過（zip 結構、`mimetype` 壓縮方式皆已確認正確）。
- **型別/命名一致性**：`WritingMode`/`EpubLayoutInfo`（Task 1）在 Task 3、4 的 Dart/Kotlin 程式碼與測試中命名一致；`setWritingMode`/`onLayoutResolved` 的 method 名稱與參數 key（`mode`/`isFixedLayout`/`writingMode`）在 Dart 端與 Kotlin 端一致。
- **Task 4 Step 2 的「確認失敗」說明**：由於 `setWritingMode` 呼叫失敗時原生端只會落入 `notImplemented()`（不會觸發 `onError`），這項「紅燈」步驟無法像一般案例一樣以斷言失敗的方式呈現，已在步驟說明中明確記錄該中間狀態的預期行為，避免執行者誤以為腳本有誤。

## 文件審查回應紀錄（`review-plan-issue-1.md`）

- **Critical（`Metadata.layout` 是否存在）：不採納，維持原計劃寫法。** 審查意見主張 `Metadata` 類別本身沒有 `layout` 屬性、應改用 `Metadata.presentation.layout`。實際反編譯 `readium-streamer:3.3.0` 的 `org.readium.r2.streamer.parser.epub.LayoutAdapter.adapt()`（`javap -c` 逐行確認位元碼）證實：該方法直接讀取 OPF 的 `rendition:layout` meta 屬性，比對字串是否為 `"pre-paginated"`，回傳 `org.readium.r2.shared.publication.Layout.FIXED` 或 `.REFLOWABLE`——這正是本計劃使用的 `Metadata.layout` 頂層屬性（`javap -public Metadata` 確認 `getLayout(): Layout` 為直接成員），整條解析路徑完全沒有出現 `Presentation`/`EpubLayout`。另確認 `Metadata.presentation` 確實存在，但只是定義於 `org.readium.r2.shared.publication.presentation.MetadataKt` 的獨立 Kotlin extension property，沒有證據顯示 EPUB 解析器會經由這條路徑填值。審查意見所述較符合較舊版本 Readium 的 API 形狀，在本專案實際依賴的 3.3.0 版本下不成立；採納會把已驗證正確的寫法換成未經證實的寫法，故不採納。
- **Important（`setWritingMode` 覆蓋未來偏好設定的風險）：採納，已於 Task 4 Step 3 的 `setWritingMode` 方法補上說明未來需改用 `EpubPreferences.plus()` 合併的註解**（已確認該運算子存在）；不改變本 issue 的實作行為，僅留註記供 `epic-3-fonts-layout` 開發時參考。
- **Minor #1（首次建構時的 `writingMode` 被忽略）：採納，已於 Task 3 Step 3 的 `EpubReaderView` 類別文件註解中補充「刻意的設計，非疏漏」說明**；不改變程式邏輯，因為目前唯一呼叫端 `ReaderScreen`（Issue 2）一律等待 `onLayoutResolved` 回報後才可能變更 `writingMode`，此限制現階段沒有實際影響。
- **Minor #2（`didUpdateWidget` 無法重設回 `null`/自動判斷）：不採納，維持原計劃寫法。** `spec.md`／`issues.md` 皆未定義「重設回自動判斷」的需求，本 epic 的橫直排切換為二態（橫/直）即時切換，屬未來假設性擴充，依專案 YAGNI 原則不預先加入對應處理或註記。
- **審查過程中的衍生發現（非本次計劃異動範圍）**：審查討論過程中確認「橫直排選擇的持久化＋『採用書籍排版／強制直排／強制橫排』三態覆寫 UI」實為 PRD FR-10，明確歸屬 `epic-3-fonts-layout`（而非本 epic），已回頭於 `design.md`／`spec.md` 補上範圍排除說明，避免與 Issue 2 的 session-only 即時切換混淆；本 issue（Issue 1）的 `setWritingMode`/`onLayoutResolved` 契約設計已足夠支撐 `epic-3` 未來讀取持久化設定後直接呼叫套用，未受影響、無需修改。
