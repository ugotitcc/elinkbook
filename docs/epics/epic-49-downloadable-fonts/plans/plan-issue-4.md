# Issue 4：閱讀器套用已下載字型 實作計畫

> **給執行者（agentic worker）：** 必須使用子技能 superpowers:subagent-driven-development（建議）或 superpowers:executing-plans，逐一執行本計畫的 Task。步驟使用核取方塊（`- [ ]`），完成一個就改成 `- [x]`。

**目標：** 使用者在字型管理下載的思源黑體／思源宋體，開書後真的套用在書本上：WebView 由原生端直接串流已下載的字型檔；閱讀設定的字型選單只列出已下載的內建字型，一款都沒有時提示去字型管理下載。

**架構：**
- `buildFontFaceCss()` 改成只替「已下載」的內建字型輸出 `@font-face`，網址是 `https://appassets.androidplatform.net/downloaded-fonts/<發布路徑>`。發布路徑直接取自字型目錄（`fontDownloadSpecOf(font).publishPath`），和 store 在磁碟上的相對路徑是同一個值。
- `FoliateReaderView` 收到存放目錄時，在 `WebViewAssetLoader` 註冊 `/downloaded-fonts/` 的 `InternalStoragePathHandler`，同時移除 Dart 攔截 `/assets/fonts/` 的舊分支。
- `ReaderScreen` 開書時向 `DownloadableFontStore` 讀取已下載字型，**讀完才建構** `FoliateReaderView`（它的初始網址是 `late final`，內含 `@font-face`）。

**技術：** Flutter／Dart、`flutter_inappwebview`（`WebViewAssetLoader`、`InternalStoragePathHandler`）、`flutter_localizations`（ARB）。不新增任何套件。

**規格：** `docs/epics/epic-49-downloadable-fonts/spec.md`（「閱讀器」「在地化字串」「測試決策」）、`docs/adr/0035-downloadable-fonts-via-r2-worker.md`、`issues.md` Issue 4。

**分支：** 從最新的 `main` 建立 `epic-49/issue-4-reader-downloaded-fonts`。

## 全域限制

- 所有指令在 `app/` 目錄執行（Task 1 的一致性測試會讀取 repo 根目錄的 `../fonts-cdn/fonts.json`）。
- 下載服務正式網址（Issue 2 部署結果）：`https://elinkbook-fonts.huthief.workers.dev/`（必須以斜線結尾）。
- WebView 虛擬網域固定為 `https://appassets.androidplatform.net`；已下載字型的路徑前綴固定為 `/downloaded-fonts/`，由新常數 `kDownloadedFontsPathPrefix` 統一提供，CSS 與路徑處理器都使用它。
- 啟用中的字型只有 `AppFont.sourceHanSans`、`AppFont.sourceHanSerif`；停用的 3 款仍是 `[字型停用]` 註解，本 Issue 不恢復。
- **所有新增的建構參數都是可選的**：
  - `FoliateReaderView`：`installedFonts`（預設 `const {}`）、`downloadedFontsDirectory`（預設 `null`）。
  - `ReaderScreen`：`downloadableFontStore`（預設 `null`）。
  - `ReaderSettingsSheet`：`installedFonts`（預設 `const {}`）。

  既有呼叫端不必修改。
- `ReaderScreen` 建構 Foliate 閱讀器的條件必須**同時**要求 `_customFontsLoaded` 與 `_downloadedFontsLoaded`。沒有 store 時，`_downloadedFontsLoaded` 一開始就是 `true`；讀取失敗時視為空集合，不阻擋開書。
- 刪除可下載字型不改書籍偏好：偏好指向未下載的字型時，下拉選單顯示「使用書本字型」（`epic-48` 已實作，沿用）。
- 新字串 4 個 ARB 都要提供（`app_zh_TW.arb` 是範本，另有 `app_zh.arb`、`app_zh_CN.arb`、`app_en.arb`）。改完 ARB 必須執行 `flutter gen-l10n`，產生的 `lib/l10n/app_localizations*.dart` 要一起提交。
- 程式註解與文件使用正體中文。
- 單一 Task 只跑異動到的測試檔；完整 `flutter test`（約 7 分鐘）只在 Task 6 執行一次。

**與 issues.md 的差異（刻意）：**
- 內建字型的檔名不再另外維護。舊的 `_fontFileName()` 刪除，CSS 網址改用字型目錄的 `publishPath`，這樣 CSS 網址和 store 存檔的路徑不可能不一致。
- `CLAUDE.md` 目前沒有描述 `/assets/fonts/` 攔截或 `loadFlutterFontAsset` 的段落（已用 grep 確認），所以不需要修改；Task 6 會再確認一次。

## 審查重點（Review Focus）

1. **自訂字型已經載入完成，但已下載字型還沒讀完**：這是最容易漏掉的組合。閱讀器不可以先建構，否則下載的字型永遠不會套用。→ Task 5 測試「已下載字型讀完前不建構 FoliateReaderView」，測試中同時注入已載入完成的自訂字型 repository。
2. **讀取已下載字型失敗**（例如存放目錄權限異常）：書仍然要能正常打開，只是不套用下載字型。→ Task 5 測試「installedFonts() 失敗時仍建構閱讀器，已下載字型為空集合」。
3. **CSS 網址和 store 存檔路徑不一致**：WebView 會請求一個不存在的檔案，而且沒有任何錯誤訊息。→ Task 2 測試「網址等於前綴加上字型目錄的 publishPath」；Task 5 測試「傳給閱讀器的存放目錄等於 `store.directory`」。
4. **沒有傳入存放目錄**（既有測試、以及還沒接上 store 的呼叫端）：只註冊 `/book/` 處理器，初始網址也不含任何下載字型規則，行為和現在完全相同。→ Task 3 測試「沒有傳入時只有 /book/ 處理器」。
5. **偏好設定指向已被刪除（未下載）的內建字型**：面板正常開啟，下拉選單顯示「使用書本字型」，不會 assert 失敗。→ Task 4 測試「偏好值指向未下載字型時顯示使用書本字型」。

---

## 檔案結構

| 檔案 | 動作 | 責任 |
|---|---|---|
| `lib/reader/font_download_catalog.dart` | 修改 | 基底網址改為正式 Worker 網址 |
| `test/reader/font_download_catalog_test.dart` | 修改 | 新增：與 `fonts-cdn/fonts.json` 的一致性測試；網址不是保留網域 |
| `lib/reader/foliate_native_bridge.dart` | 修改 | `kDownloadedFontsPathPrefix`；`buildFontFaceCss(installedFonts:)`；刪除 `_fontFileName()`、`loadFlutterFontAsset()` |
| `test/reader/foliate_native_bridge_test.dart` | 修改 | 改寫內建字型規則的測試；刪除 `loadFlutterFontAsset` 測試 |
| `lib/reader/foliate_reader_view.dart` | 修改 | `installedFonts`／`downloadedFontsDirectory` 參數、註冊處理器、移除 `/assets/fonts/` 攔截 |
| `test/reader/foliate_reader_view_test.dart` | 修改 | 路徑處理器與初始網址的測試 |
| `lib/l10n/app_*.arb`（4 個） | 修改 | 新字串 `readerSettingsDownloadMoreFontsHint` |
| `lib/l10n/app_localizations*.dart` | 重新產生 | `flutter gen-l10n` |
| `lib/screens/reader_settings_sheet.dart` | 修改 | `installedFonts` 參數、只列出已下載字型、提示文字 |
| `test/screens/reader_settings_sheet_test.dart` | 修改 | `_pumpSheet` 新增 `installedFonts` 參數；新增 5 個測試 |
| `lib/screens/reader_screen.dart` | 修改 | `downloadableFontStore` 參數、`_loadDownloadedFonts()`、延後建構、傳給閱讀器與設定面板 |
| `lib/screens/reader_screen_route.dart` | 修改 | 把 `features.downloadableFontStore` 傳給 `ReaderScreen` |
| `test/screens/reader_screen_test.dart` | 修改 | 新增 4 個測試 |
| `test/screens/reader_screen_route_test.dart` | 修改 | 欄位對帳加上 store |
| `docs/epics/epic-49-downloadable-fonts/issues.md`、`epic.md`、`docs/epics.md` | 修改 | 進度記錄（Task 6） |

---

### Task 1：正式下載網址與字型目錄一致性測試

**Files:**
- Modify: `lib/reader/font_download_catalog.dart`（`kFontDownloadBaseUrl` 與它的文件註解）
- Test: `test/reader/font_download_catalog_test.dart`

**Interfaces:**
- Consumes：`fontDownloadSpecOf(AppFont) → FontDownloadSpec`（`publishPath`、`sizeBytes`、`sha256`）；`../fonts-cdn/fonts.json` 的格式為 `{ "fonts": [ { "id", "file", "path", "bytes", "sha256" } ] }`，其中 `id` 等於 `AppFont` 的列舉名。
- Produces：`kFontDownloadBaseUrl == 'https://elinkbook-fonts.huthief.workers.dev/'`。

- [ ] **Step 1：寫失敗的測試**

在 `test/reader/font_download_catalog_test.dart` 開頭加上 import：

```dart
import 'dart:convert';
import 'dart:io';
```

在 `main()` 最後加上兩個測試：

```dart
  test('基底網址是正式的下載服務（https，不是開發用的 .invalid 保留網域）（epic-49 Issue 4）', () {
    final uri = Uri.parse(kFontDownloadBaseUrl);
    expect(uri.scheme, 'https');
    expect(uri.host, isNot(endsWith('.invalid')));
    expect(uri.host, 'elinkbook-fonts.huthief.workers.dev');
  });

  test('字型目錄與 fonts-cdn/fonts.json 的路徑、大小、SHA-256 完全一致（工單審查 I-1）', () {
    // flutter test 的工作目錄是 app/，字型清單在 repo 根目錄的 fonts-cdn/
    final manifest = jsonDecode(File('../fonts-cdn/fonts.json').readAsStringSync())
        as Map<String, dynamic>;
    final entries = {
      for (final entry in (manifest['fonts'] as List).cast<Map<String, dynamic>>())
        entry['id'] as String: entry,
    };
    for (final font in AppFont.values) {
      final entry = entries[font.name];
      expect(entry, isNotNull, reason: '${font.name} 不在 fonts-cdn/fonts.json 中');
      final spec = fontDownloadSpecOf(font);
      expect(spec.publishPath, entry!['path'], reason: font.name);
      expect(spec.sizeBytes, entry['bytes'], reason: font.name);
      expect(spec.sha256, entry['sha256'], reason: font.name);
    }
  });
```

- [ ] **Step 2：執行測試確認失敗**

Run：`flutter test test/reader/font_download_catalog_test.dart`
Expected：「基底網址是正式的下載服務」失敗（host 是 `elinkbook-fonts.invalid`）；一致性測試通過（數值本來就一致，這個測試是防止日後只改其中一邊）。

- [ ] **Step 3：改基底網址**

`lib/reader/font_download_catalog.dart` 把常數與註解換成：

```dart
/// 字型下載服務的基底網址（epic-49，見 docs/adr/0035-downloadable-fonts-via-r2-worker.md）。
///
/// Issue 2 部署的 Cloudflare Worker（`workers.dev` 網址）。日後改用自訂網域時，
/// 舊網址仍會保留，已安裝的舊版 App 不受影響。
/// 必須以斜線結尾，[Uri.resolve] 才會把發布路徑接在後面而不是取代最後一段。
const String kFontDownloadBaseUrl = 'https://elinkbook-fonts.huthief.workers.dev/';
```

- [ ] **Step 4：執行測試確認通過**

Run：`flutter test test/reader/font_download_catalog_test.dart test/reader/downloadable_font_store_test.dart`
Expected：全數通過（store 測試都注入自己的 `baseUri`，不受影響）。

- [ ] **Step 5：Commit**

```bash
git add lib/reader/font_download_catalog.dart test/reader/font_download_catalog_test.dart
git commit -m "feat(fonts): 下載網址改為正式 Worker，新增字型目錄與 fonts-cdn 清單一致性測試（epic-49 Issue 4）"
```

---

### Task 2：`buildFontFaceCss()` 只替已下載字型輸出規則

**Files:**
- Modify: `lib/reader/foliate_native_bridge.dart`（第 1～70 行的 import、`_fontFileName`、`buildFontFaceCss`；第 99～110 行的 `loadFlutterFontAsset`）
- Test: `test/reader/foliate_native_bridge_test.dart`

**Interfaces:**
- Consumes：`fontDownloadSpecOf(AppFont).publishPath`（Task 1 檔案，例如 `v1/SourceHanSansTC-VF.ttf`）。
- Produces：
  - `const String kDownloadedFontsPathPrefix = '/downloaded-fonts/';`
  - `String buildFontFaceCss({Set<AppFont> installedFonts = const {}, List<CustomFont> customFonts = const []})`
  - `loadFlutterFontAsset()` **刪除**。

- [ ] **Step 1：改寫測試（先讓它失敗）**

`test/reader/foliate_native_bridge_test.dart`：

1. 加上 import：
   ```dart
   import 'package:elinkbook/reader/app_font.dart';
   import 'package:elinkbook/reader/font_download_catalog.dart';
   ```
2. 把第一個測試「buildFontFaceCss 只產生思源黑體／思源宋體 2 款內建字型的 @font-face 宣告（epic-48）」**整個換成**下面 3 個測試：
   ```dart
   test('沒有已下載的內建字型時，不輸出任何內建字型規則（epic-49 Issue 4）', () {
     final css = buildFontFaceCss();
     expect('@font-face'.allMatches(css).length, 0);
     expect(css, isNot(contains('/assets/fonts/')));
   });

   test('只下載思源黑體時，只輸出一條規則，網址指向 /downloaded-fonts/v1/…', () {
     final css = buildFontFaceCss(installedFonts: {AppFont.sourceHanSans});
     expect(css,
         "@font-face { font-family: 'SourceHanSansTC'; "
         "src: url('https://appassets.androidplatform.net/downloaded-fonts/v1/SourceHanSansTC-VF.ttf'); }");
     expect(css, isNot(contains('SourceHanSerifTC')));
   });

   test('網址等於前綴加上字型目錄的 publishPath，和 store 存檔路徑一致（審查重點 3）', () {
     final css = buildFontFaceCss(installedFonts: AppFont.values.toSet());
     expect('@font-face'.allMatches(css).length, AppFont.values.length);
     for (final font in AppFont.values) {
       expect(css, contains(
           "src: url('https://appassets.androidplatform.net$kDownloadedFontsPathPrefix"
           "${fontDownloadSpecOf(font).publishPath}')"));
     }
   });
   ```
3. 「buildFontFaceCss 帶入 customFonts 時，額外輸出自訂字型的 @font-face 宣告」這個測試最後兩行改成：
   ```dart
       // 沒有傳入已下載字型，所以只有自訂字型這一條規則。
       expect('@font-face'.allMatches(css).length, 1);
   ```
4. 在它後面新增：
   ```dart
   test('已下載字型與自訂字型同時存在時，兩者的規則都輸出，自訂字型規則不受影響', () {
     final css = buildFontFaceCss(
       installedFonts: {AppFont.sourceHanSerif},
       customFonts: const [
         CustomFont(
           id: 1,
           displayName: '我的字型',
           familyName: 'MyCustomFamily',
           fontUri: 'content://example/font1',
         ),
       ],
     );
     expect('@font-face'.allMatches(css).length, 2);
     expect(css, contains('/downloaded-fonts/v1/SourceHanSerifTC-VF.ttf'));
     expect(css, contains(
       "@font-face { font-family: 'MyCustomFamily'; "
       "src: url('https://appassets.androidplatform.net/assets/custom-fonts/MyCustomFamily'); }",
     ));
   });
   ```
5. 刪除「buildFontFaceCss 未帶 customFonts 參數時（既有零參數呼叫）行為不變」（已被第 2 點的第一個測試取代）。
6. 刪除「loadFlutterFontAsset 透過 rootBundle 讀取 Flutter 字型 asset」。
7. 「內建字型一律不打包進 App」這個測試改為直接呼叫 `rootBundle`：這條保證仍然有價值，只是 `loadFlutterFontAsset` 已經不存在。
   ```dart
   test('內建字型一律不打包進 App（pubspec 未宣告，改由 epic-49 下載提供）', () async {
     for (final path in const [
       'assets/fonts/SourceHanSansTC-VF.ttf',
       'assets/fonts/SourceHanSerifTC-VF.ttf',
       'assets/fonts/GuanKiapTsingKhai.ttf',
       'assets/fonts/TaiwanPearl-Regular.ttf',
       'assets/fonts/GenRyuMinTW-Regular.ttf',
     ]) {
       await expectLater(rootBundle.load(path), throwsA(anything), reason: path);
     }
   });
   ```
   （`rootBundle` 來自已經 import 的 `package:flutter/services.dart`。）

- [ ] **Step 2：執行測試確認失敗**

Run：`flutter test test/reader/foliate_native_bridge_test.dart`
Expected：編譯失敗：`buildFontFaceCss` 沒有 `installedFonts` 參數、找不到 `kDownloadedFontsPathPrefix`。

- [ ] **Step 3：實作**

`lib/reader/foliate_native_bridge.dart`：

1. 第 4 行改成 `import 'package:flutter/services.dart' show MethodChannel;`（`rootBundle` 只有 `loadFlutterFontAsset` 在用）。
2. 在 `import 'custom_font.dart';` 之後加上 `import 'font_download_catalog.dart';`。
3. 刪除 `_fontFileName()` 與它上方的文件註解（第 28～49 行）。
4. `buildFontFaceCss` 與它的文件註解換成：
   ```dart
   /// WebView 內已下載字型的虛擬路徑前綴（epic-49）。[FoliateReaderView] 用它註冊
   /// `InternalStoragePathHandler`，[buildFontFaceCss] 用它組出 `@font-face` 網址，
   /// 兩邊共用同一個常數，避免路徑不一致。
   const String kDownloadedFontsPathPrefix = '/downloaded-fonts/';

   /// 產生 `@font-face` 宣告（FR-09）。
   ///
   /// 內建字型只替 [installedFonts]（已下載）輸出規則：未下載的字型不輸出，
   /// 避免 WebView 發出注定失敗的請求。網址是 `/downloaded-fonts/` 加上字型目錄的
   /// 發布路徑（例如 `v1/SourceHanSansTC-VF.ttf`），和 `DownloadableFontStore`
   /// 在存放目錄底下的相對路徑相同，由原生 `InternalStoragePathHandler` 直接串流
   /// （epic-49，ADR 0035）。家族名稱取自 `AppFontFamilyName.familyName`。
   ///
   /// 自訂字型（[customFonts]）的規則不變：由 `shouldInterceptRequest` 讀取
   /// `content://` 位元組提供（ADR 0021）。
   String buildFontFaceCss({
     Set<AppFont> installedFonts = const {},
     List<CustomFont> customFonts = const [],
   }) {
     final rules = <String>[];
     // 依 AppFont.values 的順序輸出，結果不受集合的迭代順序影響
     for (final font in AppFont.values) {
       if (!installedFonts.contains(font)) continue;
       final publishPath = fontDownloadSpecOf(font).publishPath;
       rules.add("@font-face { font-family: '${font.familyName}'; "
           "src: url('https://appassets.androidplatform.net$kDownloadedFontsPathPrefix$publishPath'); }");
     }
     for (final font in customFonts) {
       final encodedFamilyName = Uri.encodeComponent(font.familyName);
       rules.add("@font-face { font-family: '${font.familyName}'; "
           "src: url('https://appassets.androidplatform.net/assets/custom-fonts/$encodedFamilyName'); }");
     }
     return rules.join('\n');
   }
   ```
5. 刪除 `loadFlutterFontAsset()` 與它的文件註解。
6. 刪除後若 `dart:typed_data` 仍有其他函式使用（`loadAndroidAsset`、`loadCustomFontBytes` 回傳 `Uint8List`），就保留這個 import。

`foliate_reader_view.dart` 的 `_shouldInterceptRequest` 還在呼叫 `loadFlutterFontAsset`，刪掉函式後會編譯失敗。為了讓每個 Task 結束時都能編譯，本 Task 一併刪除 `foliate_reader_view.dart` 第 749～755 行的 `/assets/fonts/` 攔截分支：

```dart
    const fontsPrefix = '/assets/fonts/';
    if (path.startsWith(fontsPrefix)) {
      final relative = 'assets/fonts/${path.substring(fontsPrefix.length)}';
      final bytes = await loadFlutterFontAsset(relative);
      if (bytes == null) return null;
      return WebResourceResponse(contentType: 'font/ttf', data: bytes);
    }
```

這一段整個刪除，前後其他程式不變。

- [ ] **Step 4：執行測試確認通過**

Run：`flutter test test/reader/foliate_native_bridge_test.dart test/reader/foliate_reader_view_test.dart`
Expected：全數通過。

Run：`flutter analyze`
Expected：`No issues found!`（特別確認沒有未使用的 import）。

- [ ] **Step 5：Commit**

```bash
git add lib/reader/foliate_native_bridge.dart lib/reader/foliate_reader_view.dart test/reader/foliate_native_bridge_test.dart
git commit -m "feat(fonts): @font-face 只替已下載字型輸出並指向 /downloaded-fonts/，移除 /assets/fonts/ 攔截（epic-49 Issue 4）"
```

---

### Task 3：`FoliateReaderView` 註冊已下載字型的串流處理器

**Files:**
- Modify: `lib/reader/foliate_reader_view.dart`（import；欄位約第 296 行；建構子約第 347 行；`_buildIndexUri` 約第 579 行；`pathHandlers` 約第 807 行）
- Test: `test/reader/foliate_reader_view_test.dart`

**Interfaces:**
- Consumes：Task 2 的 `buildFontFaceCss({installedFonts, customFonts})`、`kDownloadedFontsPathPrefix`。
- Produces：`FoliateReaderView` 新增兩個可選參數 `Set<AppFont> installedFonts = const {}`、`String? downloadedFontsDirectory`（Task 5 使用）。

- [ ] **Step 1：寫失敗的測試**

在 `test/reader/foliate_reader_view_test.dart` 加上 import `package:elinkbook/reader/app_font.dart`，並在 `main()` 內新增一個 group（放在檔案最後一個 group 之後、`tearDownAll` 之前）：

```dart
  group('已下載字型（epic-49 Issue 4）', () {
    Future<InAppWebView> pumpView(
      WidgetTester tester, {
      Set<AppFont> installedFonts = const {},
      String? downloadedFontsDirectory,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: FoliateReaderView(
            filePath: '/tmp/sample.epub',
            onPageRendered: _noop,
            onError: _noopError,
            installedFonts: installedFonts,
            downloadedFontsDirectory: downloadedFontsDirectory,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();
      return tester.widget<InAppWebView>(find.byType(InAppWebView));
    }

    Map<String, String> handlerDirectories(InAppWebView webView) => {
          for (final handler in webView.platform.params.initialSettings!
              .webViewAssetLoader!.pathHandlers!
              .whereType<InternalStoragePathHandler>())
            handler.path: handler.directory,
        };

    String fontFaceCssOf(InAppWebView webView) =>
        webView.platform.params.initialUrlRequest!.url!.queryParameters['fontFaceCss']!;

    testWidgets('沒有傳入存放目錄時，只註冊 /book/ 處理器，初始網址不含下載字型規則（審查重點 4）',
        (tester) async {
      final webView = await pumpView(tester);

      expect(handlerDirectories(webView).keys, ['/book/']);
      expect(fontFaceCssOf(webView), isNot(contains('/downloaded-fonts/')));
    });

    testWidgets('傳入存放目錄時，註冊 /downloaded-fonts/ 處理器指向該目錄', (tester) async {
      final webView = await pumpView(tester,
          installedFonts: {AppFont.sourceHanSerif},
          downloadedFontsDirectory: '/data/app/downloaded-fonts');

      expect(handlerDirectories(webView), {
        '/book/': '/fake/cache/dir',
        '/downloaded-fonts/': '/data/app/downloaded-fonts',
      });
    });

    testWidgets('初始網址的 @font-face 只包含傳入的已下載字型', (tester) async {
      final webView = await pumpView(tester,
          installedFonts: {AppFont.sourceHanSerif},
          downloadedFontsDirectory: '/data/app/downloaded-fonts');

      final css = fontFaceCssOf(webView);
      expect(css, contains('/downloaded-fonts/v1/SourceHanSerifTC-VF.ttf'));
      expect(css, isNot(contains('SourceHanSansTC')));
    });
  });
```

（`_noop`、`_noopError` 是這個測試檔既有的頂層函式；`/fake/cache/dir` 來自檔案開頭 `setUpAll` 覆寫的 `cacheBookForServing`。）

- [ ] **Step 2：執行測試確認失敗**

Run：`flutter test test/reader/foliate_reader_view_test.dart --plain-name "已下載字型"`
Expected：編譯失敗：`FoliateReaderView` 沒有 `installedFonts`／`downloadedFontsDirectory` 參數。

- [ ] **Step 3：實作**

`lib/reader/foliate_reader_view.dart`：

1. import 區加上 `import 'app_font.dart';`（依字母順序放在 `'../l10n/app_localizations.dart'` 之後、`'column_mode.dart'` 之前）。
2. 在 `final List<CustomFont> customFonts;` 之後加上：
   ```dart
   /// 已下載的內建字型（epic-49）。只替這些字型輸出 `@font-face`；開書時決定，
   /// 之後不會重算（見 `_FoliateReaderViewState._initialIndexUri`），所以
   /// `ReaderScreen` 必須等清單讀完才建構本 widget。
   final Set<AppFont> installedFonts;

   /// 已下載字型的存放目錄（`DownloadableFontStore.directory`）。不為 null 時才註冊
   /// `/downloaded-fonts/` 的 `InternalStoragePathHandler`，由原生端直接串流字型檔，
   /// 不經過 Dart（ADR 0035）。
   final String? downloadedFontsDirectory;
   ```
3. 建構子 `this.customFonts = const [],` 之後加上：
   ```dart
       this.installedFonts = const {},
       this.downloadedFontsDirectory,
   ```
4. `_buildIndexUri()` 的 `'fontFaceCss'` 改成：
   ```dart
         'fontFaceCss': buildFontFaceCss(
           installedFonts: widget.installedFonts,
           customFonts: widget.customFonts,
         ),
   ```
5. `WebViewAssetLoader` 的 `pathHandlers` 改成：
   ```dart
               pathHandlers: [
                 InternalStoragePathHandler(
                     path: '/book/', directory: _bookCacheDir!),
                 if (widget.downloadedFontsDirectory != null)
                   InternalStoragePathHandler(
                       path: kDownloadedFontsPathPrefix,
                       directory: widget.downloadedFontsDirectory!),
               ],
   ```

- [ ] **Step 4：執行測試確認通過**

Run：`flutter test test/reader/foliate_reader_view_test.dart`
Expected：全數通過（含既有測試，零回歸）。

- [ ] **Step 5：Commit**

```bash
git add lib/reader/foliate_reader_view.dart test/reader/foliate_reader_view_test.dart
git commit -m "feat(reader): FoliateReaderView 以原生處理器串流已下載字型（epic-49 Issue 4）"
```

---

### Task 4：閱讀設定只列出已下載的內建字型

**Files:**
- Modify: `lib/l10n/app_zh_TW.arb`、`app_zh.arb`、`app_zh_CN.arb`、`app_en.arb`（在 `readerSettingsFontFamilyLabel` 之後）
- Regenerate: `lib/l10n/app_localizations*.dart`
- Modify: `lib/screens/reader_settings_sheet.dart`（欄位約第 34 行、建構子約第 57 行、`_buildFontFamilyDropdown` 約第 659～718 行）
- Test: `test/screens/reader_settings_sheet_test.dart`

**Interfaces:**
- Produces：
  - `ReaderSettingsSheet` 新增可選參數 `Set<AppFont> installedFonts = const {}`（Task 5 使用）。
  - 在地化字串 `readerSettingsDownloadMoreFontsHint`。
  - 提示文字的 Key 為 `reader_settings_download_fonts_hint`。

- [ ] **Step 1：新增在地化字串**

`app_zh_TW.arb`，在 `"@readerSettingsFontFamilyLabel": {…},` 這個區塊之後加上：
```json
  "readerSettingsDownloadMoreFontsHint": "到「字型管理」下載更多字型",
  "@readerSettingsDownloadMoreFontsHint": {
    "description": "閱讀設定字型下拉選單下方的提示：一款內建字型都還沒下載時顯示（epic-49）"
  },
```
`app_zh.arb`，在 `"readerSettingsFontFamilyLabel": "字型",` 之後加上：
```json
  "readerSettingsDownloadMoreFontsHint": "到「字型管理」下載更多字型",
```
`app_zh_CN.arb`，在 `"readerSettingsFontFamilyLabel": "字体",` 之後加上：
```json
  "readerSettingsDownloadMoreFontsHint": "到「字体管理」下载更多字体",
```
`app_en.arb`，在 `"readerSettingsFontFamilyLabel": "Font",` 之後加上：
```json
  "readerSettingsDownloadMoreFontsHint": "Download more fonts in Font Management",
```

Run：`flutter gen-l10n`
Expected：沒有錯誤；`grep -n "readerSettingsDownloadMoreFontsHint" lib/l10n/app_localizations_en.dart` 有結果。

- [ ] **Step 2：寫失敗的測試**

`test/screens/reader_settings_sheet_test.dart`：

1. 加上 import `package:elinkbook/reader/app_font.dart`。
2. `_pumpSheet` 新增具名參數 `Set<AppFont>? installedFonts,`（放在 `customFonts` 之後），並在建構 `ReaderSettingsSheet` 時傳入：
   ```dart
        // 既有測試的前提都是「內建字型已經可用」，沿用這個前提：沒指定時視為全部已下載。
        // 驗證「只列出已下載字型」的新測試會明確傳入集合。
        installedFonts: installedFonts ?? AppFont.values.toSet(),
   ```
3. 在「字型選單合併顯示內建 2 款與傳入的自訂字型清單」這個測試之前，新增：
   ```dart
   group('只列出已下載的內建字型（epic-49 Issue 4）', () {
     testWidgets('只下載思源黑體時，選單只有思源黑體，沒有思源宋體', (tester) async {
       await _pumpSheet(tester, const BookReaderPrefs(), (_) {},
           installedFonts: {AppFont.sourceHanSans});

       await tester.tap(find.byKey(const Key('reader_settings_font_family')));
       await tester.pumpAndSettle();

       expect(find.text('思源黑體'), findsWidgets);
       expect(find.text('思源宋體'), findsNothing);
     });

     testWidgets('一款內建字型都沒下載時，選單下方顯示提示（即使有自訂字型）', (tester) async {
       await _pumpSheet(
         tester,
         const BookReaderPrefs(),
         (_) {},
         installedFonts: const {},
         customFonts: const [
           CustomFont(
             id: 1,
             displayName: '我的自訂字型',
             familyName: 'MyCustomFamily',
             fontUri: 'content://example/font1',
           ),
         ],
       );

       final hint = find.byKey(const Key('reader_settings_download_fonts_hint'));
       expect(hint, findsOneWidget);
       expect(tester.widget<Text>(hint).data, '到「字型管理」下載更多字型');
     });

     testWidgets('有已下載的內建字型時，不顯示提示', (tester) async {
       await _pumpSheet(tester, const BookReaderPrefs(), (_) {},
           installedFonts: {AppFont.sourceHanSerif});

       expect(find.byKey(const Key('reader_settings_download_fonts_hint')), findsNothing);
     });

     testWidgets('偏好值指向未下載的內建字型時，面板正常開啟並顯示「使用書本字型」（審查重點 5）',
         (tester) async {
       await _pumpSheet(tester, const BookReaderPrefs(fontFamily: 'SourceHanSerifTC'), (_) {},
           installedFonts: {AppFont.sourceHanSans});

       expect(tester.takeException(), isNull);
       final dropdown = tester.widget<DropdownButton<String?>>(
           find.byKey(const Key('reader_settings_font_family')));
       expect(dropdown.value, isNull);
     });

     testWidgets('英文介面的提示文字', (tester) async {
       await _pumpSheet(tester, const BookReaderPrefs(), (_) {},
           installedFonts: const {}, locale: const Locale('en'));

       expect(
           tester.widget<Text>(find.byKey(const Key('reader_settings_download_fonts_hint'))).data,
           'Download more fonts in Font Management');
     });
   });
   ```

- [ ] **Step 3：執行測試確認失敗**

Run：`flutter test test/screens/reader_settings_sheet_test.dart`
Expected：編譯失敗：`ReaderSettingsSheet` 沒有 `installedFonts` 參數。

- [ ] **Step 4：實作**

`lib/screens/reader_settings_sheet.dart`：

1. 在 `final List<CustomFont> customFonts;` 之後加上：
   ```dart
   /// 已下載的內建字型（epic-49）。字型選單只列出這些內建字型，
   /// 選了一定有效果；一款都沒有時在選單下方提示去字型管理下載。
   final Set<AppFont> installedFonts;
   ```
2. 建構子 `this.customFonts = const [],` 之後加上 `this.installedFonts = const {},`。
3. `_buildFontFamilyDropdown()` 整個換成：
   ```dart
   Widget _buildFontFamilyDropdown() {
     final l10n = AppLocalizations.of(context)!;
     // 依 AppFont.values 的順序列出，不受集合迭代順序影響
     final builtInFonts =
         AppFont.values.where(widget.installedFonts.contains).toList();
     return EBFieldCard(
       child: Column(
         crossAxisAlignment: CrossAxisAlignment.start,
         children: [
           Row(
             children: [
               Text(l10n.readerSettingsFontFamilyLabel, style: const TextStyle(fontWeight: FontWeight.bold)),
               const SizedBox(width: 12),
               // DropdownButton 內部以 IndexedStack 疊放「所有」選項來決定自身寬度
               // （不只是目前選中的值），字型名稱過長（尤其使用者自訂字型）時會把
               // 整顆 Row 撐爆版。isExpanded:true 讓寬度改吃 Expanded 給的可用空間，
               // 搭配 Text 的 overflow: ellipsis 讓過長名稱改為截斷顯示，而非溢位。
               Expanded(
                 child: DropdownButton<String?>(
                   key: const Key('reader_settings_font_family'),
                   isExpanded: true,
                   // 偏好設定可能指向已停用（epic-48）或尚未下載／已刪除（epic-49）的
                   // 內建字型，該值不在選項中時 DropdownButton 會 assert 失敗，改顯示為
                   // 「使用書本字型」。只影響顯示，不改寫偏好設定，字型下載後舊設定
                   // 自然生效。
                   value: {
                     ...builtInFonts.map((f) => f.familyName),
                     ...widget.customFonts.map((f) => f.familyName),
                   }.contains(_fontFamily)
                       ? _fontFamily
                       : null,
                   items: [
                     DropdownMenuItem<String?>(
                       value: null,
                       child: Text(l10n.readerSettingsUseBookFontLabel, overflow: TextOverflow.ellipsis),
                     ),
                     ...builtInFonts.map(
                       (font) => DropdownMenuItem<String?>(
                         value: font.familyName,
                         child: Text(font.displayName(l10n),
                             overflow: TextOverflow.ellipsis),
                       ),
                     ),
                     ...widget.customFonts.map(
                       (font) => DropdownMenuItem<String?>(
                         value: font.familyName,
                         child: Text(font.displayName,
                             overflow: TextOverflow.ellipsis),
                       ),
                     ),
                   ],
                   onChanged: (value) => setState(() {
                     _fontFamily = value;
                     _notifyChanged();
                   }),
                 ),
               ),
             ],
           ),
           if (builtInFonts.isEmpty)
             Padding(
               padding: const EdgeInsets.only(top: 4),
               child: Text(
                 l10n.readerSettingsDownloadMoreFontsHint,
                 key: const Key('reader_settings_download_fonts_hint'),
                 style: Theme.of(context).textTheme.bodySmall,
               ),
             ),
         ],
       ),
     );
   }
   ```

- [ ] **Step 5：執行測試確認通過**

Run：`flutter test test/screens/reader_settings_sheet_test.dart`
Expected：全數通過（既有測試透過 `_pumpSheet` 的預設值維持「內建字型已下載」的前提；檔案中直接建構 `ReaderSettingsSheet` 的其他測試不驗證內建字型選項，不受影響）。

Run：`flutter analyze`，Expected：`No issues found!`
Run：`node tool/check_l10n_hardcoded_strings.js`，Expected：兩行 PASS。

- [ ] **Step 6：Commit**

```bash
git add lib/l10n lib/screens/reader_settings_sheet.dart test/screens/reader_settings_sheet_test.dart
git commit -m "feat(reader): 閱讀設定字型選單只列出已下載的內建字型，未下載時提示去字型管理（epic-49 Issue 4）"
```

---

### Task 5：`ReaderScreen` 等已下載字型讀完才建構閱讀器

**Files:**
- Modify: `lib/screens/reader_screen.dart`：
  - import
  - 欄位：`customFontsRepository` 附近，約第 164 行
  - 建構子：約第 248 行
  - 狀態：`_customFontsLoaded` 附近，約第 385 行
  - `initState`：約第 550 行
  - `_loadCustomFonts` 之後：約第 1294 行
  - `_openBookSearch` 的 `LibraryReaderFeatureRepositories(`：約第 1812 行
  - `ReaderSettingsSheet(`：約第 911 行
  - `_buildBody` 的建構條件：約第 2805 行
  - `FoliateReaderView(`：約第 3296 行
- Modify: `lib/screens/reader_screen_route.dart`
- Test: `test/screens/reader_screen_test.dart`、`test/screens/reader_screen_route_test.dart`

**Interfaces:**
- Consumes：
  - Task 3 的 `FoliateReaderView(installedFonts:, downloadedFontsDirectory:)`；
  - Task 4 的 `ReaderSettingsSheet(installedFonts:)`；
  - Issue 3 的 `DownloadableFontStore.installedFonts() → Future<Set<AppFont>>`、`DownloadableFontStore.directory → String`；
  - 測試用 `FakeDownloadableFontStore`（`test/support/fake_downloadable_font_store.dart`，有 `installed`、`installedFontsGate`，`directory` 固定回傳 `'/fake/downloaded-fonts'`）；
  - `LibraryReaderFeatureRepositories.downloadableFontStore`（Issue 3 已新增）。
- Produces：`ReaderScreen` 新增可選參數 `DownloadableFontStore? downloadableFontStore`。

- [ ] **Step 1：寫失敗的測試**

1. `test/screens/reader_screen_test.dart` 加上 import：
   ```dart
   import 'package:elinkbook/reader/app_font.dart';
   import 'package:elinkbook/reader/downloadable_font_store.dart';
   import '../support/fake_downloadable_font_store.dart';
   ```

2. 在測試「提供 customFontsRepository 時，自訂字型清單載入完成前 FoliateReaderView 不建構，載入完成後才建構」之後，新增 4 個測試：
   ```dart
   group('已下載字型（epic-49 Issue 4）', () {
     Future<void> pumpReader(WidgetTester tester,
         {DownloadableFontStore? store,
         FakeCustomFontsRepository? customFontsRepository}) async {
       await tester.pumpWidget(
         MaterialApp(
           locale: const Locale('zh', 'TW'),
           localizationsDelegates: AppLocalizations.localizationsDelegates,
           supportedLocales: AppLocalizations.supportedLocales,
           theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
           home: ReaderScreen(
             filePath: 'test/fixtures/sample.epub',
             bookId: 'b1',
             prefsManager: prefsManager,
             customFontsRepository: customFontsRepository,
             downloadableFontStore: store,
           ),
         ),
       );
       await tester.pump();
       await tester.runAsync(() => Future.delayed(Duration.zero));
       await tester.pump();
     }

     testWidgets(
         '已下載字型讀完前不建構 FoliateReaderView（自訂字型已載入完成也一樣）；'
         '讀完後才建構，並收到正確的已下載字型與存放目錄（規格審查 C-1、審查重點 1、3）',
         (tester) async {
       final store = FakeDownloadableFontStore()
         ..installed.add(AppFont.sourceHanSerif)
         ..installedFontsGate = Completer<void>();

       await pumpReader(tester,
           store: store, customFontsRepository: FakeCustomFontsRepository());

       expect(find.byType(FoliateReaderView), findsNothing);
       expect(find.byKey(const Key('reader_loading_indicator')), findsOneWidget);

       store.installedFontsGate!.complete();
       await tester.pump();
       await tester.runAsync(() => Future.delayed(Duration.zero));
       await tester.pump();

       final view = tester.widget<FoliateReaderView>(find.byType(FoliateReaderView));
       expect(view.installedFonts, {AppFont.sourceHanSerif});
       expect(view.downloadedFontsDirectory, store.directory);
     });

     testWidgets('沒有傳入 store 時開書不等待，已下載字型為空、不註冊存放目錄（工單審查 M-1）',
         (tester) async {
       await pumpReader(tester);

       final view = tester.widget<FoliateReaderView>(find.byType(FoliateReaderView));
       expect(view.installedFonts, isEmpty);
       expect(view.downloadedFontsDirectory, isNull);
     });

     testWidgets('installedFonts() 失敗時仍建構閱讀器，已下載字型為空集合（審查重點 2）',
         (tester) async {
       final store = FakeDownloadableFontStore()
         ..installedFontsGate = Completer<void>();

       await pumpReader(tester, store: store);
       store.installedFontsGate!.completeError(StateError('denied'));
       await tester.pump();
       await tester.runAsync(() => Future.delayed(Duration.zero));
       await tester.pump();

       expect(tester.takeException(), isNull);
       final view = tester.widget<FoliateReaderView>(find.byType(FoliateReaderView));
       expect(view.installedFonts, isEmpty);
     });

     testWidgets('開啟版面設定時，已下載字型集合傳給 ReaderSettingsSheet', (tester) async {
       final store = FakeDownloadableFontStore()..installed.add(AppFont.sourceHanSans);
       await pumpReader(tester, store: store);

       tester.widget<FoliateReaderView>(find.byType(FoliateReaderView))
           .onLayoutResolved
           ?.call(const EpubLayoutInfo(
             isFixedLayout: false,
             writingMode: WritingMode.horizontal,
           ));
       await tester.pump();

       await tester.tap(find.byKey(const Key('reader_chrome_layout_button')));
       await tester.pump();
       await tester.pump(const Duration(milliseconds: 500));

       final sheet = tester.widget<ReaderSettingsSheet>(find.byType(ReaderSettingsSheet));
       expect(sheet.installedFonts, {AppFont.sourceHanSans});
     });
   });
   ```
   - `EpubLayoutInfo`、`WritingMode` 在這個測試檔已經有人使用，import 已存在。

3. `test/screens/reader_screen_route_test.dart` 的「欄位對帳」測試：
   - 測試名稱中的「features 12 個欄位」改為「features 13 個欄位」。
   - 在 `final customFontsRepository = FakeCustomFontsRepository();` 之後加上 `final downloadableFontStore = FakeDownloadableFontStore();`，並加上 import `'../support/fake_downloadable_font_store.dart'`。
   - `LibraryReaderFeatureRepositories(` 內，在 `customFontsRepository: customFontsRepository,` 之後加上 `downloadableFontStore: downloadableFontStore,`。
   - 在 `expect(screen.customFontsRepository, same(customFontsRepository));` 之後加上：
     ```dart
     expect(screen.downloadableFontStore, same(downloadableFontStore));
     ```

- [ ] **Step 2：執行測試確認失敗**

Run：`flutter test test/screens/reader_screen_test.dart --plain-name "已下載字型" test/screens/reader_screen_route_test.dart`
Expected：編譯失敗：`ReaderScreen` 沒有 `downloadableFontStore` 參數。

- [ ] **Step 3：實作 `ReaderScreen`**

`lib/screens/reader_screen.dart`：

1. import 區，在 `import '../reader/custom_fonts_repository.dart';` 之後加上：
   ```dart
   import '../reader/downloadable_font_store.dart';
   ```
   並在 `import '../reader/custom_font.dart';` 之前加上 `import '../reader/app_font.dart';`（`_installedFonts` 的型別是 `Set<AppFont>`，目前這個檔案沒有 import 它）。
2. 在 `final CustomFontsRepository? customFontsRepository;` 之後加上：
   ```dart
   /// 可下載字型的存放與查詢（epic-49 Issue 4）。刻意為可選參數，比照
   /// [customFontsRepository] 既有慣例：未提供時已下載字型視為空集合、開書不等待，
   /// 行為和本 Issue 之前相同（既有測試不必修改）。
   final DownloadableFontStore? downloadableFontStore;
   ```
3. 建構子 `this.customFontsRepository,` 之後加上 `this.downloadableFontStore,`。
4. 在 `late bool _customFontsLoaded = widget.customFontsRepository == null;` 之後加上：
   ```dart
   // 已下載的內建字型（epic-49 Issue 4），開書時載入一次。閱讀期間不會改變：
   // 字型管理畫面不在閱讀器內，下載或刪除都要離開閱讀器。
   Set<AppFont> _installedFonts = const {};
   // 已下載字型清單是否已讀完，用法比照 _customFontsLoaded：FoliateReaderView 的
   // 初始網址（內含 @font-face）是 late final，提早建構就再也不會套用下載的字型
   // （規格審查 C-1）。未提供 store 時一開始就是 true；讀取失敗也設為 true，不阻擋開書。
   late bool _downloadedFontsLoaded = widget.downloadableFontStore == null;
   ```
5. `initState` 的 `_loadCustomFonts();` 之後加上 `_loadDownloadedFonts();`。
6. 在 `_loadCustomFonts()` 方法之後加上：
   ```dart
   Future<void> _loadDownloadedFonts() async {
     final store = widget.downloadableFontStore;
     if (store == null) return;
     try {
       final fonts = await store.installedFonts();
       if (!mounted) return;
       setState(() {
         _installedFonts = fonts;
         _downloadedFontsLoaded = true;
       });
     } catch (e) {
       debugPrint('Failed to load downloaded fonts: $e');
       if (!mounted) return;
       setState(() => _downloadedFontsLoaded = true);
     }
   }
   ```
7. `_openLayoutSettings()` 的 `ReaderSettingsSheet(` 內，在 `customFonts: _customFonts,` 之後加上 `installedFonts: _installedFonts,`。
8. `_buildBody` 的建構條件改成：
   ```dart
               if (_resolved != null &&
                   (!isFoliateFormat(format) ||
                       (_dispatchedIsFixedLayout != null &&
                           _customFontsLoaded &&
                           _downloadedFontsLoaded)))
   ```
9. `FoliateReaderView(` 內，在 `customFonts: _customFonts,` 之後加上：
   ```dart
             installedFonts: _installedFonts,
             downloadedFontsDirectory: widget.downloadableFontStore?.directory,
   ```
10. `_openBookSearch()` 建構 `LibraryReaderFeatureRepositories(` 時，在 `customFontsRepository: widget.customFontsRepository,` 之後加上：
    ```dart
                downloadableFontStore: widget.downloadableFontStore,
    ```
    從閱讀器進入搜尋時（`fromReader: true`），搜尋畫面目前只會 `pop` 回跳轉目標，用不到 store。但同一處已經傳遞其他所有依賴，補上這一行可以維持一致，日後搜尋畫面改變導覽行為時也不會漏掉（計畫審查 I-2）。

- [ ] **Step 4：實作 `reader_screen_route.dart`**

在 `customFontsRepository: features.customFontsRepository,` 之後加上：
```dart
    downloadableFontStore: features.downloadableFontStore,
```

- [ ] **Step 5：執行測試確認通過**

Run：`flutter test test/screens/reader_screen_test.dart test/screens/reader_screen_route_test.dart`
Expected：全數通過（含既有測試，零回歸）。

變異檢查：暫時把第 3 步第 8 點的 `&& _downloadedFontsLoaded` 拿掉，再執行 `flutter test test/screens/reader_screen_test.dart --plain-name "已下載字型"`。Expected：第一個測試失敗（閘門完成前就找到 `FoliateReaderView`）。確認後**改回來**，重新執行一次，確認全部通過。

- [ ] **Step 6：Commit**

```bash
git add lib/screens/reader_screen.dart lib/screens/reader_screen_route.dart test/screens/reader_screen_test.dart test/screens/reader_screen_route_test.dart
git commit -m "feat(reader): ReaderScreen 讀完已下載字型才建構閱讀器，並傳給閱讀器與版面設定（epic-49 Issue 4）"
```

---

### Task 6：整體驗證與進度記錄

**Files:**
- Modify: `docs/epics/epic-49-downloadable-fonts/issues.md`（Issue 4 的 `**Status:**`）、`docs/epics/epic-49-downloadable-fonts/epic.md`、`docs/epics.md`（第 50 列備註）

- [ ] **Step 1：確認沒有殘留的舊字型服務程式與文件描述**

在 repo 根目錄執行。這裡用 `git grep`：Git Bash 和 PowerShell 都能直接執行（計畫審查 M-1）。它只搜尋已追蹤的檔案，不過 Task 1～5 都已經 commit，不影響結果。

```bash
git grep -n -E "loadFlutterFontAsset|/assets/fonts/|_fontFileName" -- app/lib app/test CLAUDE.md
```

Expected：`app/lib` 沒有任何結果。`app/test` 只剩兩處：
- `foliate_native_bridge_test.dart`：「內建字型一律不打包」測試中的 `assets/fonts/...` 字串（沒有開頭的斜線）。
- `foliate_reader_view_test.dart`：`resolveCustomFontUri('/assets/fonts/foo.ttf', …)` 測試。這個測試驗證「非自訂字型前綴的路徑回傳 null」，和本 Issue 無關，保留。

`CLAUDE.md` 沒有結果，所以不需要修改。如果有結果，把描述改成「已下載字型由 `FoliateReaderView` 的 `InternalStoragePathHandler`（`/downloaded-fonts/`）串流」。

- [ ] **Step 2：完整測試與檢查**

在 `app/` 執行：

```bash
flutter test
flutter analyze
node tool/check_l10n_hardcoded_strings.js
```

Expected：
- `flutter test`：`All tests passed!`
- `flutter analyze`：`No issues found!`
- l10n 檢查：兩行都是 `PASS`

- [ ] **Step 3：更新進度**

- `issues.md`：Issue 4 的 `**Status:**` 改為 `completed`。
- `epic.md`：追加一段「Issue 4 完成」記錄，內容包括：
  - 各 Task 的重點
  - 新增的測試數量
  - 完整 `flutter test` 的結果
  - 變異檢查的結果
  - 和 issues.md 刻意不同的兩點（見本計畫開頭）
- `docs/epics.md` 第 50 列備註改為「Issue 1～4 已完成，待 Issue 5 真機驗證」。

- [ ] **Step 4：Commit**

```bash
git add docs/epics.md docs/epics/epic-49-downloadable-fonts/issues.md docs/epics/epic-49-downloadable-fonts/epic.md docs/epics/epic-49-downloadable-fonts/plans/plan-issue-4.md
git commit -m "docs(epic-49): 記錄 Issue 4 完成"
```
