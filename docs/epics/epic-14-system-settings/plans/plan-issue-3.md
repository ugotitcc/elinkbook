# Epic 14 Issue 3 — 自訂字型 Foliate-JS 原生渲染 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> 本計畫經 `/superpowers:requesting-code-review` 審查（`tmp/epic-14/review-plan-issue-3.md`，結論「核准實作」，0 Critical）與 `/superpowers:receiving-code-review` 核對修訂：採納 1 項 Important（`resolveCustomFontUri` 補 `FormatException` 防護）與 1 項 Minor（原生端補 `Log.w` 診斷紀錄）；**未採納** 1 項 Important（建議把 Task 4 測試改用 `pumpAndSettle()`——查證後判定該畫面含不確定動畫的 `CircularProgressIndicator`〔`Key('reader_loading_indicator')`〕，`pumpAndSettle()` 會因此逾時拋出例外，維持原計畫的 `pump()+runAsync+pump()` 既有模式）。**實作完成後另經一輪程式碼審查**（`tmp/epic-14/review-issue-3.md`）發現並修正 2 項 Important（`sample.ttf` 未宣告為 asset 導致真機 `integration_test` 必定失敗；`reader_screen_test.dart` 新測試缺 `elinkbook/fullscreen` mock 導致 `flutter test` 整體失敗），兩者皆已修正並於真機／全專案回歸測試確認通過。詳見文末兩段「審查修正紀錄」。

**Goal:** 讓使用者在 `reader_settings_sheet.dart` 選擇的自訂字型（Issue 1/2 已完成資料層與選擇器 UI）真正在 Foliate-JS 閱讀畫面渲染出來。擴充 `buildFontFaceCss()` 輸出自訂字型的 `@font-face` 規則，`InAppWebView.shouldInterceptRequest` 新增攔截分支透過原生 `ReaderResourceChannel` 即時讀取 `content://` 字型位元組（不落地快取，見 [ADR 0021](../../adr/0021-custom-font-content-uri-no-copy.md)）。

**Architecture:** 沿用既有 5 款內建字型的服務機制原封不動（`buildFontFaceCss()` → 虛擬路徑 → `InAppWebView.shouldInterceptRequest` 攔截 → Dart 橋接函式取得位元組），自訂字型只是新增一組平行的虛擬路徑前綴與對應橋接函式，**不使用** `WebViewAssetLoader.InternalStoragePathHandler`（那是書籍本體 217MB 級大檔案專用的原生落地快取串流機制，字型檔案沿用既有「Dart 攔截＋原生一次性讀取位元組、不落地」模式即可，見 ADR 0021）。撰寫本計畫過程中發現一個真實的非同步載入競態（`ReaderScreen` 開書時 `_customFonts` 清單非同步查詢，可能晚於 `FoliateEpubReaderView` 的 `late final _initialIndexUri` 計算完成，導致該次開書自訂字型的 `@font-face` 宣告整個缺席、且不會在清單載入完成後補上），已與人類確認需要修正（Task 4），比照既有 `_dispatchedIsFixedLayout`／`_tocLoaded` 的「開書前先等關鍵非同步資料就緒」既定模式處理。

**Tech Stack:** Flutter/Dart（`flutter_inappwebview`）、Kotlin（`ContentResolver`）。Task 1/3/4 純 Dart，不需真機；Task 2（原生 Kotlin）無 JVM 測試（比照 `ReaderResourceChannel.kt` 既有慣例，此類 Android Context/ContentResolver 重度依賴的原生程式碼在本專案是靠 `integration_test` 真機驗證，非 JVM 單元測試，見 Task 5）；Task 5 需要真實裝置。

## Global Constraints

- **虛擬路徑格式**：`/assets/custom-fonts/<Uri.encodeComponent(familyName)>`——family name 可能含空白或非 ASCII 字元（來自使用者上傳字型檔解析結果或檔名回退），必須 URL 編碼；`_shouldInterceptRequest` 端對應用 `Uri.decodeComponent` 還原。
- **`buildFontFaceCss()` 簽章擴充為具名參數＋預設值**（`{List<CustomFont> customFonts = const []}`），**不改動**既有無參數呼叫方式的相容性——`foliate_native_bridge_test.dart` 既有測試 `buildFontFaceCss()`（零參數）需維持通過，不需修改。
- **`loadCustomFontBytes` 比照既有 `loadAndroidAsset` 模式**（非 `cacheBookForServing` 的可覆寫頂層函數變數模式）——字型檔案不需要像書籍本體那樣支援測試環境注入 mock 的彈性，`loadAndroidAsset` 用的固定函式宣告＋`MethodChannel` mock（`TestDefaultBinaryMessengerBinding`）測試模式已經足夠，維持風格一致即可。
- **`ReaderResourceChannel.kt` 新方法比照既有 `readAndroidAsset`**：無快取、`try/catch` 吞掉例外統一回傳 `null`（而非讓例外冒出變成 Dart 端未預期的 `PlatformException`），不使用 `cacheChannel`（背景執行緒佇列）——字型檔案遠小於 217MB 書籍本體，不需要背景執行緒佇列避免 ANR 的機制。
- **`_shouldInterceptRequest` 私有方法在目前的 widget test 環境下無法被真正觸發**（`FakePlatformInAppWebViewWidget` 只回傳固定尺寸的 placeholder，不會呼叫任何真實 WebView 引擎、也不會觸發 `onWebViewCreated`／`shouldInterceptRequest` 回呼，`foliate_epub_reader_view_test.dart` 目前對這兩個回呼完全零測試覆蓋，非本計畫遺漏）。Task 3 因此把「請求路徑 → 該讀哪個自訂字型的 `fontUri`」這段路由/查找邏輯抽成獨立頂層純函式 `resolveCustomFontUri`，可脫離 `InAppWebViewController`／`WebResourceRequest` 直接測試；`_shouldInterceptRequest` 本身呼叫該函式的正確性、以及位元組真的被正確讀取並渲染，留給 Task 5 的真機 `integration_test`／人工視覺驗收確認。
- **自訂字型清單載入競態修正範圍**（Task 4，人類已確認採用）：`ReaderScreen` 新增 `_customFontsLoaded` 欄位，`format == BookFormat.epub` 時 `_buildNativeView` 的既有 gating 條件（`_dispatchedIsFixedLayout != null`）追加 `&& _customFontsLoaded`；未提供 `customFontsRepository` 時 `_customFontsLoaded` 直接初始化為 `true`（沒有東西要等，零回歸）。PDF 格式完全不受影響。

---

### Task 1：`buildFontFaceCss()` 擴充 + `loadCustomFontBytes` 橋接函式

**Files:**
- Modify：`app/lib/reader/foliate_native_bridge.dart`
- Test：`app/test/reader/foliate_native_bridge_test.dart`

**Interfaces:**
- Consumes：Issue 1/2 的 `CustomFont`（`app/lib/reader/custom_font.dart`，`familyName`／`fontUri` 欄位）
- Produces：`String buildFontFaceCss({List<CustomFont> customFonts})`（擴充既有簽章）；新頂層函式 `Future<Uint8List?> loadCustomFontBytes(String uri)`，供 Task 3 的 `_shouldInterceptRequest` 使用

- [x] **Step 1：撰寫失敗測試——`buildFontFaceCss` 輸出自訂字型 `@font-face` 規則**

在 `app/test/reader/foliate_native_bridge_test.dart` 檔案開頭新增 import：

```dart
import 'package:elinkbook/reader/custom_font.dart';
```

在既有 `test('buildFontFaceCss 產生 5 款內建字型的 @font-face 宣告', ...)`（第 8-19 行）之後新增：

```dart
  test('buildFontFaceCss 帶入 customFonts 時，額外輸出自訂字型的 @font-face 宣告',
      () {
    final css = buildFontFaceCss(customFonts: const [
      CustomFont(
        id: 1,
        displayName: '我的字型',
        familyName: 'MyCustomFamily',
        fontUri: 'content://example/font1',
      ),
    ]);

    expect(css, contains(
      "@font-face { font-family: 'MyCustomFamily'; "
      "src: url('https://appassets.androidplatform.net/assets/custom-fonts/MyCustomFamily'); }",
    ));
    // 內建 5 款字型仍照舊輸出，不受影響。
    expect('@font-face'.allMatches(css).length, 6);
  });

  test('buildFontFaceCss 的自訂字型虛擬路徑對 family name 做 URL 編碼', () {
    final css = buildFontFaceCss(customFonts: const [
      CustomFont(
        id: 1,
        displayName: '含空白字型',
        familyName: 'My Custom Family',
        fontUri: 'content://example/font2',
      ),
    ]);

    expect(css, contains(
      "src: url('https://appassets.androidplatform.net/assets/custom-fonts/My%20Custom%20Family'); }",
    ));
  });

  test('buildFontFaceCss 未帶 customFonts 參數時（既有零參數呼叫）行為不變', () {
    final css = buildFontFaceCss();
    expect('@font-face'.allMatches(css).length, 5);
  });
```

- [x] **Step 2：執行測試，確認失敗**

```bash
cd app
flutter test test/reader/foliate_native_bridge_test.dart
```

Expected：FAIL——`buildFontFaceCss` 尚未接受 `customFonts` 具名參數（編譯錯誤）。

- [x] **Step 3：修改 `buildFontFaceCss` 並新增 `loadCustomFontBytes`**

`app/lib/reader/foliate_native_bridge.dart` 第 7 行 import 區塊新增：

```dart
import 'custom_font.dart';
```

第 57-66 行 `buildFontFaceCss()` 改為：

```dart
String buildFontFaceCss({List<CustomFont> customFonts = const []}) {
  final rules = <String>[];
  for (final font in AppFont.values) {
    final familyName = font.familyName;
    final fileName = _fontFileName(font);
    rules.add("@font-face { font-family: '$familyName'; "
        "src: url('https://appassets.androidplatform.net/assets/fonts/$fileName'); }");
  }
  for (final font in customFonts) {
    final encodedFamilyName = Uri.encodeComponent(font.familyName);
    rules.add("@font-face { font-family: '${font.familyName}'; "
        "src: url('https://appassets.androidplatform.net/assets/custom-fonts/$encodedFamilyName'); }");
  }
  return rules.join('\n');
}
```

在 `loadFlutterFontAsset`（第 95-102 行）之後新增：

```dart
/// 讀取自訂字型的位元組（`content://` URI，ADR 0021 決策：不落地快取），
/// 透過原生 `ReaderResourceChannel` 的 `readCustomFontBytes` 一次性讀取，
/// 供 `InAppWebView.shouldInterceptRequest` 服務 [buildFontFaceCss] 產生的
/// 自訂字型 `@font-face src` 請求。比照既有 [loadAndroidAsset] 模式（固定
/// 函式宣告，非 [cacheBookForServing] 的可覆寫頂層函數變數——字型檔案不需要
/// 書籍本體那種測試環境 mock 注入彈性）。
Future<Uint8List?> loadCustomFontBytes(String uri) {
  return _readerResourcesChannel
      .invokeMethod<Uint8List>('readCustomFontBytes', {'uri': uri});
}
```

- [x] **Step 4：執行測試，確認通過**

```bash
flutter test test/reader/foliate_native_bridge_test.dart
```

Expected：全數 PASS（含既有 5 個測試不受影響）。

- [x] **Step 5：撰寫失敗測試——`loadCustomFontBytes` 呼叫正確的 method channel**

在 `test('loadAndroidAsset 呼叫 elinkbook/reader_resources 的 readAndroidAsset', ...)`（第 21-37 行）之後新增：

```dart
  test('loadCustomFontBytes 呼叫 elinkbook/reader_resources 的 readCustomFontBytes',
      () async {
    MethodCall? captured;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('elinkbook/reader_resources'),
      (call) async {
        captured = call;
        return Uint8List.fromList([4, 5, 6]);
      },
    );

    final bytes =
        await loadCustomFontBytes('content://example.provider/font1.ttf');

    expect(captured!.method, 'readCustomFontBytes');
    expect(captured!.arguments, {'uri': 'content://example.provider/font1.ttf'});
    expect(bytes, [4, 5, 6]);
  });
```

- [x] **Step 6：執行測試，確認通過**

```bash
flutter test test/reader/foliate_native_bridge_test.dart
```

Expected：全數 PASS。

- [x] **Step 7：`flutter analyze` + Commit**

```bash
flutter analyze
git add lib/reader/foliate_native_bridge.dart test/reader/foliate_native_bridge_test.dart
git commit -m "feat(epic-14): buildFontFaceCss 擴充自訂字型 + loadCustomFontBytes 橋接函式"
```

Expected：`flutter analyze` "No issues found!"。

---

### Task 2：`ReaderResourceChannel.kt` 新增 `readCustomFontBytes`

**Files:**
- Modify：`app/android/app/src/main/kotlin/cc/ugotit/elinkbook/ReaderResourceChannel.kt`

**Interfaces:**
- Consumes：Task 1 的 `loadCustomFontBytes(uri)` 呼叫 `elinkbook/reader_resources` channel 的 `readCustomFontBytes` method，參數 `{'uri': String}`
- Produces：`ByteArray?`（成功讀取回傳位元組，找不到 `uri` 參數或讀取失敗回傳 `null`），供 Task 5 真機驗證

本 Task 無 JVM 單元測試（比照 Global Constraints 說明的既有慣例），純手動核對程式碼與 Task 5 真機驗證。

- [x] **Step 1：新增 `readCustomFontBytes` case**

`app/android/app/src/main/kotlin/cc/ugotit/elinkbook/ReaderResourceChannel.kt` 第 3-11 行 import 區塊新增：

```kotlin
import android.util.Log
```

`onMethodCall`（第 80-120 行）`when (call.method)` 區塊，在 `"readAndroidAsset" -> { ... }`（第 82-94 行）之後新增：

```kotlin
            "readCustomFontBytes" -> {
                val uriString = call.argument<String>("uri")
                if (uriString == null) {
                    result.success(null)
                    return
                }
                // 比照 readAndroidAsset：一次性讀取，不落地快取（ADR 0021），
                // try/catch 吞掉例外統一回傳 null，避免 SAF 授權失效等情境
                // 讓例外冒出變成 Dart 端未預期的 PlatformException。失敗時
                // 記錄 Log.w（非 Log.d——部分裝置的客製化 ROM 會過濾 Debug
                // 等級的 logcat 輸出，見 epic-7-interaction Issue 1 spike 已
                // 記錄的既有教訓），方便日後用 adb logcat 判斷是 SAF 授權
                // 過期還是原始檔案已被使用者刪除（審查修正，見
                // tmp/epic-14/review-plan-issue-3.md Minor 1）。
                val bytes = try {
                    context.contentResolver.openInputStream(Uri.parse(uriString))
                        ?.use { it.readBytes() }
                } catch (e: Exception) {
                    Log.w("ReaderResourceChannel", "Failed to read custom font bytes for uri: $uriString", e)
                    null
                }
                result.success(bytes)
            }
```

- [x] **Step 2：更新類別頂部 KDoc 說明**

第 13-31 行的類別 KDoc 註解，在「2. `cacheBookForServing`：...」段落之後新增第 3 點：

```kotlin
 * 3. `readCustomFontBytes`：讀取自訂字型的 `content://` URI 位元組
 *    （epic-14-system-settings Issue 3，ADR 0021 決策：不落地快取），
 *    比照 `readAndroidAsset` 一次性讀取模式，非 `cacheBookForServing`
 *    的落地快取模式——字型檔案遠小於 217MB 書籍本體，不需要背景執行緒
 *    佇列避免 ANR。
 *
```

- [x] **Step 3：`flutter build apk --debug` 確認原生端可編譯**

```bash
cd app
flutter build apk --debug
```

Expected：BUILD SUCCESSFUL（純語法/型別層級確認，真正的行為正確性留給 Task 5 真機驗證）。

- [x] **Step 4：Commit**

```bash
git add android/app/src/main/kotlin/cc/ugotit/elinkbook/ReaderResourceChannel.kt
git commit -m "feat(epic-14): ReaderResourceChannel 新增 readCustomFontBytes"
```

---

### Task 3：`FoliateEpubReaderView` 新增 `customFonts` 參數 + `_shouldInterceptRequest` 新分支

**Files:**
- Modify：`app/lib/reader/foliate_epub_reader_view.dart`
- Test：`app/test/reader/foliate_epub_reader_view_test.dart`

**Interfaces:**
- Consumes：Task 1 的 `buildFontFaceCss({customFonts})`／`loadCustomFontBytes(uri)`
- Produces：`FoliateEpubReaderView` 新增 `customFonts: List<CustomFont>`（預設 `const []`）建構參數；新頂層純函式 `String? resolveCustomFontUri(String path, List<CustomFont> customFonts)`，供 Task 4 之後、及未來任何需要驗證此路由邏輯的測試直接呼叫

- [x] **Step 1：撰寫失敗測試——`resolveCustomFontUri` 路由邏輯（純函式，不需 WebView）**

`app/test/reader/foliate_epub_reader_view_test.dart` 開頭新增 import：

```dart
import 'package:elinkbook/reader/custom_font.dart';
```

在檔案內任一 `group` 區塊之後（例如 `group('buildFoliatePreferencesMap', ...)` 結束後）新增新的 `group`：

```dart
  group('resolveCustomFontUri', () {
    const fonts = [
      CustomFont(
        id: 1,
        displayName: 'A',
        familyName: 'FamilyA',
        fontUri: 'content://example/a',
      ),
      CustomFont(
        id: 2,
        displayName: 'B',
        familyName: 'My Custom B',
        fontUri: 'content://example/b',
      ),
    ];

    test('路徑符合自訂字型前綴且 family name 存在於清單中，回傳對應 fontUri',
        () {
      expect(
        resolveCustomFontUri('/assets/custom-fonts/FamilyA', fonts),
        'content://example/a',
      );
    });

    test('family name 含空白，先經 URL 解碼再比對', () {
      expect(
        resolveCustomFontUri(
            '/assets/custom-fonts/My%20Custom%20B', fonts),
        'content://example/b',
      );
    });

    test('family name 不在清單中，回傳 null', () {
      expect(
        resolveCustomFontUri('/assets/custom-fonts/Unknown', fonts),
        isNull,
      );
    });

    test('路徑不是自訂字型前綴，回傳 null（不影響既有 /assets/fonts/ 等其他路徑）',
        () {
      expect(resolveCustomFontUri('/assets/fonts/foo.ttf', fonts), isNull);
      expect(resolveCustomFontUri('/assets/foliate/main.js', fonts), isNull);
    });

    test('customFonts 為空清單時一律回傳 null', () {
      expect(
        resolveCustomFontUri('/assets/custom-fonts/FamilyA', const []),
        isNull,
      );
    });

    test('畸形百分號跳脫序列（Uri.decodeComponent 會拋 FormatException）時回傳 null，不拋出例外',
        () {
      expect(
        () => resolveCustomFontUri('/assets/custom-fonts/Font%2', fonts),
        returnsNormally,
      );
      expect(resolveCustomFontUri('/assets/custom-fonts/Font%2', fonts), isNull);
    });
  });
```

- [x] **Step 2：執行測試，確認失敗**

```bash
cd app
flutter test test/reader/foliate_epub_reader_view_test.dart
```

Expected：FAIL——`resolveCustomFontUri` 未定義。

- [x] **Step 3：新增 `customFonts` 參數與 `resolveCustomFontUri`**

`app/lib/reader/foliate_epub_reader_view.dart` import 區塊新增：

```dart
import 'custom_font.dart';
```

class 欄位（第 161-192 行區塊，`final String? fontFamily;` 附近）新增：

```dart
  final List<CustomFont> customFonts;
```

建構子（第 194-231 行）新增：

```dart
    this.customFonts = const [],
```

在檔案頂層（class 定義之外，例如檔案最下方或 `_shouldInterceptRequest` 方法之前）新增：

```dart
/// 從 `InAppWebView.shouldInterceptRequest` 攔截到的請求路徑，判斷是否為
/// 自訂字型虛擬路徑（`/assets/custom-fonts/<URL 編碼後的 family name>`），
/// 若是則從 [customFonts] 找出對應項目並回傳其 `fontUri`；路徑不符前綴、
/// 或找不到符合的 family name，回傳 `null`。抽成獨立頂層純函式（而非直接
/// 寫在 `_shouldInterceptRequest` 內）的原因：`FakePlatformInAppWebViewWidget`
/// （`test/support/fake_inappwebview_platform.dart`）只回傳固定尺寸
/// placeholder，不會觸發真實 `shouldInterceptRequest` 回呼，
/// `_shouldInterceptRequest` 整個私有方法在目前 widget test 環境下無法被
/// 觸發到——這段路由/查找邏輯抽出後才能脫離 `InAppWebViewController`／
/// `WebResourceRequest` 直接測試。`_shouldInterceptRequest` 攔截的是
/// WebView 的全部請求（非僅我們自己產生的 URL），畸形百分號跳脫序列會讓
/// `Uri.decodeComponent` 拋出 `FormatException`，包 try/catch 統一視為
/// 「不符合自訂字型路徑」回傳 `null`，避免例外冒出到攔截回呼（審查修正，
/// 見 tmp/epic-14/review-plan-issue-3.md Important 1）。
String? resolveCustomFontUri(String path, List<CustomFont> customFonts) {
  const prefix = '/assets/custom-fonts/';
  if (!path.startsWith(prefix)) return null;
  try {
    final familyName = Uri.decodeComponent(path.substring(prefix.length));
    for (final font in customFonts) {
      if (font.familyName == familyName) return font.fontUri;
    }
    return null;
  } on FormatException {
    return null;
  }
}
```

- [x] **Step 4：執行測試，確認通過**

```bash
flutter test test/reader/foliate_epub_reader_view_test.dart
```

Expected：全數 PASS（含既有測試不受影響）。

- [x] **Step 5：接上 `_buildIndexUri()` 與 `_shouldInterceptRequest`**

第 342-346 行 `_buildIndexUri()` 的 `'fontFaceCss': buildFontFaceCss(),` 改為：

```dart
      'fontFaceCss': buildFontFaceCss(customFonts: widget.customFonts),
```

第 452-476 行 `_shouldInterceptRequest`，在 `const fontsPrefix = '/assets/fonts/';` 分支（第 468-474 行）之後、`return null;`（第 475 行）之前新增：

```dart
    final customFontUri = resolveCustomFontUri(path, widget.customFonts);
    if (customFontUri != null) {
      final bytes = await loadCustomFontBytes(customFontUri);
      if (bytes == null) return null;
      return WebResourceResponse(contentType: 'font/ttf', data: bytes);
    }
```

- [x] **Step 6：`flutter analyze` + 執行完整檔案測試 + Commit**

```bash
flutter analyze
flutter test test/reader/foliate_epub_reader_view_test.dart
git add lib/reader/foliate_epub_reader_view.dart test/reader/foliate_epub_reader_view_test.dart
git commit -m "feat(epic-14): FoliateEpubReaderView 新增 customFonts 參數，shouldInterceptRequest 攔截自訂字型請求"
```

Expected：`flutter analyze` "No issues found!"，測試全數 PASS。

---

### Task 4：`ReaderScreen` 貫穿 `customFonts` + 修正非同步載入競態

**Files:**
- Modify：`app/lib/screens/reader_screen.dart`
- Modify：`app/test/support/fake_custom_fonts_repository.dart`
- Test：`app/test/screens/reader_screen_test.dart`

**Interfaces:**
- Consumes：Task 3 的 `FoliateEpubReaderView.customFonts`
- Produces：`ReaderScreen` 開書流程在 `customFontsRepository` 提供時，保證 `FoliateEpubReaderView` 建構當下 `_customFonts` 已載入完成（不再有 Global Constraints 描述的競態）

- [x] **Step 1：`FakeCustomFontsRepository` 新增可控制的載入延遲閘門**

`app/test/support/fake_custom_fonts_repository.dart` 開頭新增 import：

```dart
import 'dart:async';
```

class 欄位新增（`_storage`／`_nextId` 附近）：

```dart
  /// 測試用：若非 null，[listAll] 會先等待這個 Completer 完成才回傳，
  /// 供測試精確控制非同步載入完成的時機（epic-14-system-settings Issue 3，
  /// 驗證 ReaderScreen 在自訂字型清單載入完成前延後建構 FoliateEpubReaderView）。
  Completer<void>? loadGate;
```

`listAll()` 方法改為：

```dart
  @override
  Future<List<CustomFont>> listAll() async {
    if (loadGate != null) await loadGate!.future;
    final list = List<CustomFont>.from(_storage);
    list.sort((a, b) => a.displayName.compareTo(b.displayName));
    return list;
  }
```

- [x] **Step 2：撰寫失敗測試——`FoliateEpubReaderView` 延後至自訂字型清單載入完成才建構**

`app/test/screens/reader_screen_test.dart` 新增 import（若尚未存在）：

```dart
import 'dart:async';

import '../support/fake_custom_fonts_repository.dart';
```

新增測試（找一個既有 EPUB 相關 `group`／頂層位置比照既有寫法插入）：

```dart
  testWidgets(
      '提供 customFontsRepository 時，自訂字型清單載入完成前 FoliateEpubReaderView 不建構，載入完成後才建構',
      (tester) async {
    final customFontsRepository = FakeCustomFontsRepository();
    final gate = Completer<void>();
    customFontsRepository.loadGate = gate;

    await tester.pumpWidget(MaterialApp(
      home: ReaderScreen(
        filePath: 'test/fixtures/sample.epub',
        bookId: 'b1',
        prefsManager: prefsManager,
        customFontsRepository: customFontsRepository,
      ),
    ));
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    // 自訂字型清單尚未載入完成，FoliateEpubReaderView 不應建構，仍顯示載入中指示器。
    expect(find.byType(FoliateEpubReaderView), findsNothing);
    expect(find.byKey(const Key('reader_loading_indicator')), findsOneWidget);

    gate.complete();
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    expect(find.byType(FoliateEpubReaderView), findsOneWidget);
  });
```

- [x] **Step 3：執行測試，確認失敗**

```bash
cd app
flutter test test/screens/reader_screen_test.dart
```

Expected：FAIL——目前 `_buildNativeView` 沒有等待任何自訂字型載入完成旗標，`FoliateEpubReaderView` 在 `gate` 完成前就已經建構。

- [x] **Step 4：新增 `_customFontsLoaded` 欄位與 gating 條件**

`app/lib/screens/reader_screen.dart` 第 179 行 `List<CustomFont> _customFonts = [];` 之後新增：

```dart
  // 自訂字型清單是否已完成載入判斷（epic-14-system-settings Issue 3）：
  // 未提供 customFontsRepository 時直接視為已完成（沒有東西要等，零回歸）；
  // 提供時初始為 false，_loadCustomFonts() 完成（不論成功或失敗）後才設為
  // true。_buildBody 的 EPUB gating 條件依此延後 FoliateEpubReaderView 的
  // 建構時機，避免 late final _initialIndexUri（內含 buildFontFaceCss()
  // 產生的自訂字型 @font-face 宣告）在清單查詢完成前就已計算定案、之後
  // 永遠不會重新產生的競態（見本計畫 Global Constraints）。
  late bool _customFontsLoaded = widget.customFontsRepository == null;
```

第 626-636 行 `_loadCustomFonts()` 改為：

```dart
  Future<void> _loadCustomFonts() async {
    final repository = widget.customFontsRepository;
    if (repository == null) return;
    try {
      final fonts = await repository.listAll();
      if (!mounted) return;
      setState(() {
        _customFonts = fonts;
        _customFontsLoaded = true;
      });
    } catch (e) {
      debugPrint('Failed to load custom fonts: $e');
      if (!mounted) return;
      setState(() => _customFontsLoaded = true);
    }
  }
```

第 1446-1448 行的 `_buildBody` gating 條件：

```dart
            if (_resolved != null &&
                (format != BookFormat.epub ||
                    (_dispatchedIsFixedLayout != null && _customFontsLoaded)))
              _buildNativeView(format, isLandscape),
```

- [x] **Step 5：接上 `FoliateEpubReaderView` 的 `customFonts` 參數**

第 585 行附近（`FoliateEpubReaderView(` 建構呼叫的既有具名參數列表，緊接在 `dualPageMode: resolved.dualPageMode,`／`isLandscape: isLandscape,` 一類欄位之後任一位置）新增：

```dart
          customFonts: _customFonts,
```

- [x] **Step 6：執行測試，確認通過**

```bash
flutter test test/screens/reader_screen_test.dart
```

Expected：全數 PASS（含 Step 2 新增測試，以及既有大量 EPUB 相關測試——它們皆未提供 `customFontsRepository`，`_customFontsLoaded` 同步初始化為 `true`，`FoliateEpubReaderView` 建構時機不受影響，零回歸）。

- [x] **Step 7：全專案回歸測試 + `flutter analyze`**

```bash
flutter test
flutter analyze
```

Expected：全數 PASS，`flutter analyze` "No issues found!"。

- [x] **Step 8：Commit**

```bash
git add lib/screens/reader_screen.dart test/support/fake_custom_fonts_repository.dart test/screens/reader_screen_test.dart
git commit -m "fix(epic-14): ReaderScreen 貫穿 customFonts 並修正非同步載入競態（開書前等待自訂字型清單就緒）"
```

---

### Task 5：真機端到端驗證（`integration_test`）+ 人工視覺驗收

**Files:**
- Create：`app/integration_test/custom_font_rendering_test.dart`

**Interfaces:**
- Consumes：Task 1-4 全部完成的端到端管線
- Produces：真機驗證報告（本 Task 完成時記錄於 `issues.md` Issue 3 驗收說明），無新增供其他 Task 使用的介面

**前置需求**：一台已連接、可執行 `flutter test integration_test/... -d <device-id>` 的 Android 裝置；`app/test/fixtures/sample.ttf`（Issue 1 已使用過的 KingHwa_OldSong 字型，已存在版本控制）與 `app/test/fixtures/sample.epub` 供 staging。**注意（審查修正，見 `tmp/epic-14/review-issue-3.md` Minor 1）**：`sample.epub` 當時已在 `pubspec.yaml` 宣告為 asset，但 `sample.ttf` 當時**未**宣告——這是計畫撰寫當下的事實性錯誤（誤以為兩者狀態相同，未逐一查證），已在 Step 1 實作時因真機測試失敗而發現並補上宣告，本段文字保留錯誤原文供記錄，實際結果見 Step 2。

- [x] **Step 1：撰寫真機整合測試**

新建 `app/integration_test/custom_font_rendering_test.dart`（比照既有 `app/integration_test/pdf_content_uri_metadata_test.dart` 的 `_stageAssetAsFile` 寫法與 `createTestContentUri`／`takePersistableUriPermission` 使用模式）：

```dart
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:elinkbook/library/sqlite_library_repository.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/reader/book_reader_prefs.dart';
import 'package:elinkbook/reader/book_reader_prefs_repository.dart';
import 'package:elinkbook/reader/custom_font.dart';
import 'package:elinkbook/reader/custom_fonts_repository.dart';
import 'package:elinkbook/reader/epub_character_count_repository.dart';
import 'package:elinkbook/reader/reader_prefs_manager_impl.dart';
import 'package:elinkbook/reader/reading_position_repository.dart';
import 'package:elinkbook/screens/reader_screen.dart';
import 'package:flutter/material.dart';

const _metadataChannel = MethodChannel('elinkbook/book_metadata');

Future<String> _stageAssetAsFile(String assetPath, String fileName) async {
  final bytes = await rootBundle.load(assetPath);
  final tempDir = await getTemporaryDirectory();
  final file = File('${tempDir.path}/$fileName');
  await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
  return file.path;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('上傳自訂字型並套用於書籍後，真機開書無錯誤（視覺效果人工確認，見 issues.md）',
      (tester) async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final repository = await SqliteLibraryRepository.open(inMemoryDatabasePath);
    addTearDown(repository.close);

    // 比照 pdf_content_uri_metadata_test.dart：透過 createTestContentUri 取得
    // 真正的 content:// URI（FileProvider 自我授權模擬 SAF 選檔結果），
    // 而非直接用本機檔案路徑，才能驗證 ReaderResourceChannel.readCustomFontBytes
    // 的 ContentResolver.openInputStream 真實路徑。
    final fontPath = await _stageAssetAsFile('test/fixtures/sample.ttf', 'custom_font.ttf');
    final fontUri = await _metadataChannel
        .invokeMethod<String>('createTestContentUri', {'path': fontPath});
    expect(fontUri, isNotNull);
    await _metadataChannel
        .invokeMethod<void>('takePersistableUriPermission', {'uri': fontUri});

    final customFontsRepository = CustomFontsRepository(repository.database);
    await customFontsRepository.insert(CustomFont(
      displayName: '測試字型',
      familyName: 'KingHwa_OldSong',
      fontUri: fontUri!,
    ));

    final epubPath = await _stageAssetAsFile('test/fixtures/sample.epub', 'custom_font_test.epub');
    await repository.insertBook(Book(
      id: 'b_custom_font',
      title: '自訂字型測試書',
      format: BookFileFormat.epub,
      filePath: epubPath,
      source: BookSource.local,
      progress: 0,
      groupName: '未分類',
      createTime: DateTime.now(),
      lastReadTime: DateTime.now(),
    ));
    final prefsRepository = BookReaderPrefsRepository(repository.database);
    await prefsRepository.save(
      'b_custom_font',
      const BookReaderPrefs(fontFamily: 'KingHwa_OldSong'),
    );
    final prefsManager = ReaderPrefsManagerImpl(
      prefsRepository,
      ReadingPositionRepository(repository.database),
      EpubCharacterCountRepository(repository.database),
    );

    await tester.pumpWidget(MaterialApp(
      home: ReaderScreen(
        filePath: epubPath,
        bookId: 'b_custom_font',
        prefsManager: prefsManager,
        customFontsRepository: customFontsRepository,
      ),
    ));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    expect(find.byKey(const Key('reader_error_text')), findsNothing);
    expect(find.byKey(const Key('reader_loading_indicator')), findsNothing);
  });
}
```

- [x] **Step 2：於真機執行**

```bash
flutter devices
flutter test integration_test/custom_font_rendering_test.dart -d <device-id>
```

Expected：測試 PASS（無 `reader_error_text`、無殘留 `reader_loading_indicator`，代表 `readCustomFontBytes` 呼叫鏈路整體未拋出未捕捉例外、書籍成功渲染）。實際於真機 `3CEF42ECD491687`（Android 15）執行，修正 `pubspec.yaml` 缺少 `sample.ttf` asset 宣告（審查修正，見 `tmp/epic-14/review-issue-3.md` Important 1）後確認 PASS。

- [ ] **Step 3：人工真機視覺驗收**

於真機手動操作（非自動化，記錄於 `issues.md` Issue 3 完成時的驗收說明）：

1. 透過 `FontManagementScreen` 上傳一款字型（例如已知字體特徵明顯的字型檔案）。
2. 開啟一本 EPUB，於 `reader_settings_sheet.dart` 選擇該自訂字型。
3. 肉眼確認內文字體確實變成該字型（非退回內建預設字型），比照本專案既有「自動化驗證機制運作、視覺效果人工確認」慣例（例如 `epic-4` PDF 濾鏡效果的驗收方式）。
4. 確認切換回內建字型／其他書籍時行為不受影響。

- [x] **Step 4：`flutter analyze` 全專案確認**

```bash
flutter analyze
```

Expected：`flutter analyze` "No issues found!"。

- [x] **Step 5：Commit**

```bash
git add integration_test/custom_font_rendering_test.dart
git commit -m "test(epic-14): 自訂字型渲染真機端到端整合測試"
```

---

## Self-Review Notes（撰寫計劃時的自我檢查）

- **spec 覆蓋度**：`issues.md` Issue 3「What to build」三段（`buildFontFaceCss` 擴充、`_shouldInterceptRequest` 新分支、`ReaderResourceChannel.readCustomFontBytes`）分別對應 Task 1/3/2；「單元測試要求」的 widget test／integration_test 兩層分別對應 Task 1/3 與 Task 5；驗收標準 6 項逐一對應：`buildFontFaceCss` 輸出正確（Task 1）、`_shouldInterceptRequest` 攔截正確（Task 3 的 `resolveCustomFontUri`，附帶說明為何無法直接測試私有方法本身）、`readCustomFontBytes` 不落地快取（Task 2）、真機端到端無錯誤（Task 5 Step 1-2）、人工視覺驗收（Task 5 Step 3）、自動化測試通過且 `flutter analyze` 乾淨（各 Task 收尾步驟）。
- **撰寫過程中發現並經人類確認納入範圍的額外項目**：`_customFonts` 非同步載入與 `FoliateEpubReaderView._initialIndexUri`（`late final`，只計算一次）之間的競態——若 `FoliateEpubReaderView` 在自訂字型清單查詢完成前就先建構，該次開書的 `@font-face` 宣告會永久缺席自訂字型（不會在清單載入後補上，退出重開也不保證修好，因為每次開書都是全新非同步查詢，同樣的競態會重新發生）。已提出「不修（記錄風險）」與「開書前等待」兩個選項，人類選擇後者，已納入 Task 4，比照既有 `_dispatchedIsFixedLayout`／`_tocLoaded` 的「開書前先等關鍵非同步資料就緒」既定模式實作，PDF 格式完全不受影響。
- **測試可行性排查**：`_shouldInterceptRequest` 私有方法在目前 widget test 環境下無法被觸發到（`FakePlatformInAppWebViewWidget` 純 placeholder，不會呼叫真實 WebView 引擎），已在 Global Constraints 與 Task 3 明確記錄這個既有測試基礎設施限制，並透過抽出 `resolveCustomFontUri` 純函式取得可測試性，非略過測試要求。`ReaderResourceChannel.kt` 的原生 Kotlin 新增同樣無 JVM 測試，比照該類別既有慣例（其餘既有 method 也都沒有 JVM 測試），真機 `integration_test` 是本專案對這類 Android Context/ContentResolver 重度依賴程式碼的既定驗證方式。
- **無佔位符掃描**：所有步驟皆附完整程式碼與確切檔案位置/行號。
- **型別/介面一致性**：`buildFontFaceCss`／`loadCustomFontBytes`／`resolveCustomFontUri`／`readCustomFontBytes` 命名與 `issues.md`「What to build」原文逐字一致；虛擬路徑前綴 `/assets/custom-fonts/` 與 `design.md`／`spec.md` 既有措辭一致；`Task 5` 的真機整合測試沿用 `pdf_content_uri_metadata_test.dart`（Epic 21）已驗證可行的 `createTestContentUri`／`_stageAssetAsFile` 既有模式，不重新發明。

## 審查修正紀錄（`tmp/epic-14/review-plan-issue-3.md`）

- **Important（確認屬實，已修正）**：`resolveCustomFontUri` 呼叫 `Uri.decodeComponent` 未防範畸形百分號跳脫序列拋出的 `FormatException`——`_shouldInterceptRequest` 攔截的是 WebView 全部請求，非僅本專案自己產生的 URL，理論上可能收到非預期路徑。已於 Task 3 補上 `try/catch (on FormatException)`，回傳 `null` 視同不符合自訂字型路徑，並補上對應測試案例。
- **Important（查證後判定建議有誤，不採納，維持原計畫）**：審查建議把 Task 4 Step 2 測試的 `pump()+runAsync(Future.delayed)+pump()` 改用 `pumpAndSettle()`。查證後發現該測試場景畫面上會有 `Key('reader_loading_indicator')` 的 `CircularProgressIndicator`（不確定動畫，`AnimationController.repeat()`），只要它在畫面上，`pumpAndSettle()` 會因為永遠有排定中的下一影格而逾時拋出例外——這正是本專案既有測試（`foliate_epub_reader_view_test.dart` 多處）刻意採用 `pump()+runAsync+pump()` 而非 `pumpAndSettle()` 的既定理由，維持原計畫寫法不變。
- **Minor（確認合理，已採納）**：`ReaderResourceChannel.kt` 的 `readCustomFontBytes` 例外處理補上 `Log.w`（非 `Log.d`——比照 `epic-7-interaction` Issue 1 spike 已記錄的既有教訓：部分裝置客製化 ROM 會過濾 Debug 等級 logcat 輸出），方便日後用 `adb logcat` 判斷 SAF 授權過期或原始檔案已被刪除。

## 實作審查修正紀錄（`tmp/epic-14/review-issue-3.md`）

- **Important（確認屬實，已修正）**：`app/pubspec.yaml` 缺少 `test/fixtures/sample.ttf` 的 `assets:` 宣告，導致 Task 5 真機 `integration_test` 的 `rootBundle.load()` 必定拋出 `Unable to load asset`。已補上宣告，於真機 `3CEF42ECD491687`（Android 15）重新執行確認 PASS。本項連帶暴露「前置需求」段落本身的事實性錯誤（見上方該段補充說明）。
- **Important（確認屬實，已修正）**：`reader_screen_test.dart` 的 Task 4 新測試未 mock `elinkbook/fullscreen` 頻道，導致 `ReaderScreen._applySystemUiMode()` 開書時觸發的 `setEnabled` 呼叫以未捕捉的 `MissingPluginException` 形式讓 `flutter test` 整體失敗（含全專案執行與單檔案獨立執行皆可重現）。已比照同檔既有寫法補上 mock handler，全專案回歸測試 770/770 通過。
- **Minor（確認合理，已採納）**：「前置需求」段落誤寫 `sample.ttf` 當時已宣告為 asset，已修正措辭並保留錯誤原文供記錄（見上方該段）。
