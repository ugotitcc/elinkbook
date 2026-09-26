# Issue 7：系統 WebView 太舊時不列出可下載字型 實作計畫

> **給執行者：** 必須搭配 superpowers:subagent-driven-development（建議）或 superpowers:executing-plans 逐項執行。步驟使用核取方塊（`- [ ]`），完成一個就改成 `- [x]`。

**目標：** 系統 WebView 載入不了的可下載字型，不出現在字型管理與閱讀設定；已選它的書改用書本字型，不改寫偏好。

**架構：** 新增一個小模組判斷「這個 WebView 載得動多大的字型」。`DownloadableFontStore` 啟動時拿到 WebView 主版本號，對外只公開載得動的字型（`supportedFonts`），`installedFonts()` 也只回傳這些。閱讀器與閱讀設定本來就只看 `installedFonts()`，所以不用改；字型管理畫面改列 `supportedFonts`。

```
main.dart 啟動
  └─ readWebViewMajorVersion()  ── 91 / 154 / 讀不到 = null
        │
        v
DownloadableFontStore(webViewMajorVersion: …)
  ├─ supportedFonts   ── 字型管理畫面只列這些
  ├─ installedFonts() ── 只回傳 supportedFonts 裡已下載的
  │     ├─ ReaderSettingsSheet 選單（不用改）
  │     ├─ buildFontFaceCss()（不用改）
  │     └─ ReaderScreen._renderedFontFamily() → 偏好指向它時改傳 null（Issue 6，不用改）
  └─ prepare()        ── 另外刪掉載不動的已下載檔案
```

**技術：** Flutter、`flutter_inappwebview` 6.1.5 的 `InAppWebViewController.getCurrentWebViewPackage()`、`flutter_test`、`flutter gen-l10n`。

**規格：** `docs/epics/epic-49-downloadable-fonts/issues.md` Issue 7；背景見 `epic.md`「2026-09-26 Issue 5 真機驗證」第 8 項；`docs/adr/0035-downloadable-fonts-via-r2-worker.md`。

**分支：** 從最新的 `main` 建立 `epic-49/issue-7-legacy-webview-fonts`。

## 門檻版本的來源（工單要求寫明）

- 錯誤訊息 `Web font size more than 30MB` 來自 Chromium `third_party/blink/renderer/platform/fonts/web_font_decoder.cc`。
- Chromium commit `3c603c19beafe687d2bf66ca930ac96cb607ecac`「Raise OTS font decompression limit to 128MB」（2022-08-29，`Cr-Commit-Position: refs/heads/main@{#1040311}`）把上限從 30 MB 改成 128 MB。
- chromiumdash 的分支點：M106 = `1036826`、M107 = `1047731`。`1040311` 在兩者之間，所以 **M107 起上限 128 MB，M106 以前 30 MB**。
- 判斷方式是 `buffer->size() > kMaxDecompressedSize` 才拒絕，所以「剛好等於上限」可以載入。
- 真機資料吻合：WebView 91 拒絕思源宋體，WebView 154 正常。

## 計畫做的決定（工單要求寫明）

1. **依字型大小判斷，不寫死兩款字型的名字。** 門檻以下的 WebView，只擋超過 30 MB 的字型。目前兩款都超過，所以結果就是「兩款都不列」；日後恢復 epic-48 停用的 3 款（最大 21.7 MB）時，它們會自動列出。
2. **讀不到版本時，視同支援（行為和現在一樣）。** 讀不到的原因多半是平台呼叫失敗，不代表 WebView 舊。視同不支援會讓新裝置也看不到字型，傷害比較大；視同支援最壞只是回到今天的狀況（字型下載了但套不上）。讀取另外加 3 秒逾時，避免卡住 App 啟動。
3. **舊 WebView 裝置上已下載、但載不動的字型檔，在 App 啟動時由 `prepare()` 自動刪除，不另外提供刪除入口。** 這些檔案在這台裝置上永遠用不到，思源宋體還佔 57 MB。只有「讀得到版本、而且確定太舊」時才刪，讀不到版本時不刪（決定 2）。刪檔不碰書籍偏好；WebView 升級後重新下載，偏好會自動生效。
4. **字型管理畫面有字型被隱藏時，在「內建字型」標題下顯示一行提示**，說明原因與解法。不然舊裝置上會看到一個空的「內建字型」區塊，不知道發生什麼事。
5. **`download()` 不另外檢查字型是否支援，只在說明註解寫明**（計畫審查 M-3）。唯一的呼叫端是字型管理畫面，它只列出 `supportedFonts`；萬一被直接呼叫，下次啟動時 `prepare()` 也會刪掉檔案。

## 計畫審查修訂

依 `reviews/review-plan-issue-7.md`（Ready to implement: With fixes，0 Critical／2 Important／3 Minor）：

- I-1 採納：Fake 的 `installedFonts()` 也依 `supported` 過濾，和真的 store 行為一致（Task 2 Step 7）。
- I-2 採納：`reader_screen_test.dart` 補上工單要求的兩個測試（閱讀設定不列出、閱讀器收到 `null` 且偏好不改寫）。先寫測試、看它在 Fake 還沒過濾時失敗，再加過濾讓它通過（Task 2 Step 5～8）。真正的過濾邏輯由 store 測試驗證；這兩個測試守住「閱讀器只透過 `installedFonts()` 取得字型」這條約定。
- M-1 採納：Task 4 Step 1 改成直接執行，不重導到 `/tmp`。
- M-2 採納：提示文字的 padding 改成 `EdgeInsets.fromLTRB(16, 4, 16, 8)`。
- M-3 採用報告的第二個做法：不加檢查，只在 `download()` 的說明註解寫明（決定 5）。

## 全域限制

- 不改資料庫 schema，不改寫書籍偏好（ADR 0035：刪除字型不修改任何書籍偏好）。
- 不改 `ReaderScreen`、`ReaderSettingsSheet`、`FoliateReaderView`、`buildFontFaceCss()`：它們只透過 `installedFonts()` 取得字型，過濾在 store 裡做。
- 所有指令在 `app/` 目錄執行。
- 每個 Task 只跑異動到的測試檔；完整 `flutter test` 只在 Task 4 跑一次（專案慣例，全套約 5 分鐘）。
- 提交前 `flutter analyze` 必須輸出 `No issues found!`。
- 新增介面字串要同時加進 4 個 arb：`app_zh_TW.arb`（範本，含 `@` 說明）、`app_zh.arb`、`app_zh_CN.arb`、`app_en.arb`，再執行 `flutter gen-l10n`。產生的 `app_localizations*.dart` 有進版控，要一起提交。
- 提交前執行 `node tool/check_l10n_hardcoded_strings.js`。
- commit 訊息結尾加 `Co-Authored-By` 署名行（依當次工作階段的 system reminder）。

## 審查重點（Review Focus）

以下五種情況最可能在真機上出錯，每一條都已在負責的 Task 補上測試：

1. **讀取 WebView 版本拋出例外或一直不回應**：App 必須照常啟動，行為和現在一樣。→ Task 1 `readWebViewMajorVersion` 的例外與逾時測試。
2. **版本字串格式不如預期**（空字串、只有主版本 `91`、非數字開頭、前後空白）：不可拋錯，無法解析就回傳 `null`。→ Task 1 解析測試。
3. **剛好在門檻上**：主版本 106 要擋、107 要放行。→ Task 1 門檻測試。
4. **字型大小剛好在 30 MB 上**：31,457,280 bytes 可以載入、31,457,281 bytes 不行（Chromium 用「大於」判斷）。→ Task 1 邊界測試。
5. **舊裝置上已經有下載好的字型檔**（例如 Issue 5 驗證用的電子紙）：啟動後檔案被刪、不再列為已下載；讀不到版本時檔案保留。→ Task 2 `prepare` 測試。

已知、刻意不處理的行為：舊裝置上一款內建字型都不能用時，閱讀設定仍顯示「到『字型管理』下載更多字型」。使用者點過去會看到決定 4 的提示，說明為什麼沒有字型可下載。

---

## 檔案結構

| 檔案 | 動作 | 責任 |
|---|---|---|
| `app/lib/reader/webview_font_support.dart` | 建立 | 解析 WebView 版本、判斷字型大小是否載得動、讀取系統 WebView 版本 |
| `app/test/reader/webview_font_support_test.dart` | 建立 | 上面三個函式的測試 |
| `app/lib/reader/downloadable_font_store.dart` | 修改 | 新增 `webViewMajorVersion` 參數、`supportedFonts`；`installedFonts()` 過濾；`prepare()` 刪除載不動的檔案 |
| `app/test/reader/downloadable_font_store_test.dart` | 修改 | 新增 `supportedFonts`／過濾／`prepare` 測試 |
| `app/test/support/fake_downloadable_font_store.dart` | 修改 | 實作 `supportedFonts`；`installedFonts()` 依 `supported` 過濾 |
| `app/test/screens/reader_screen_test.dart` | 修改 | 舊 WebView 時閱讀設定不列出、閱讀器收到 `null`（計畫審查 I-2） |
| `app/lib/screens/font_management_screen.dart` | 修改 | 改列 `supportedFonts`；有字型被隱藏時顯示提示 |
| `app/test/screens/font_management_screen_test.dart` | 修改 | 隱藏與提示的測試 |
| `app/lib/l10n/app_zh_TW.arb`、`app_zh.arb`、`app_zh_CN.arb`、`app_en.arb` | 修改 | 新增 `fontManagementBuiltInUnsupportedHint` |
| `app/lib/l10n/app_localizations*.dart` | 重新產生 | `flutter gen-l10n` |
| `app/lib/main.dart` | 修改 | 啟動時讀 WebView 版本並傳給 store |
| `docs/epics/epic-49-downloadable-fonts/epic.md`、`issues.md`、`docs/epics.md` | 修改 | 進度記錄（Task 4） |

---

### Task 1：WebView 字型支援判斷模組

**Files:**
- Create: `app/lib/reader/webview_font_support.dart`
- Test: `app/test/reader/webview_font_support_test.dart`

**Interfaces:**
- Produces：
  - `int? parseWebViewMajorVersion(String? versionName)`
  - `bool webViewCanLoadFont({required int? webViewMajorVersion, required int fontSizeBytes})`
  - `Future<int?> readWebViewMajorVersion({Future<String?> Function()? readVersionName, Duration timeout = const Duration(seconds: 3)})`
  - 常數 `kWebViewLargeFontMinMajorVersion = 107`、`kLegacyWebFontSizeLimitBytes = 30 * 1024 * 1024`、`kWebFontSizeLimitBytes = 128 * 1024 * 1024`

- [ ] **Step 1：建立分支**

在 repo 根目錄：
```bash
git switch main && git pull --ff-only origin main
git switch -c epic-49/issue-7-legacy-webview-fonts
```

- [ ] **Step 2：寫失敗的測試**

建立 `app/test/reader/webview_font_support_test.dart`：

```dart
import 'dart:async';

import 'package:elinkbook/reader/webview_font_support.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseWebViewMajorVersion', () {
    test('取出主版本號', () {
      expect(parseWebViewMajorVersion('91.0.4472.114'), 91);
      expect(parseWebViewMajorVersion('154.0.8037.49'), 154);
    });

    test('只有主版本、前後有空白也能解析', () {
      expect(parseWebViewMajorVersion('107'), 107);
      expect(parseWebViewMajorVersion('  106.0.5249.126 '), 106);
    });

    test('null、空字串、非數字開頭 → null', () {
      expect(parseWebViewMajorVersion(null), isNull);
      expect(parseWebViewMajorVersion(''), isNull);
      expect(parseWebViewMajorVersion('   '), isNull);
      expect(parseWebViewMajorVersion('Chrome/91.0'), isNull);
      expect(parseWebViewMajorVersion('abc'), isNull);
    });
  });

  group('webViewCanLoadFont', () {
    const sans = 36034016; // 思源黑體
    const serif = 59898316; // 思源宋體

    test('WebView 106 以前：超過 30MB 的字型載不動', () {
      expect(webViewCanLoadFont(webViewMajorVersion: 91, fontSizeBytes: sans), isFalse);
      expect(webViewCanLoadFont(webViewMajorVersion: 91, fontSizeBytes: serif), isFalse);
      expect(webViewCanLoadFont(webViewMajorVersion: 106, fontSizeBytes: sans), isFalse);
    });

    test('WebView 107 起：128MB 以內都載得動', () {
      expect(webViewCanLoadFont(webViewMajorVersion: 107, fontSizeBytes: sans), isTrue);
      expect(webViewCanLoadFont(webViewMajorVersion: 154, fontSizeBytes: serif), isTrue);
    });

    test('剛好等於上限可以載入，多 1 byte 就不行（Chromium 用「大於」判斷）', () {
      expect(webViewCanLoadFont(webViewMajorVersion: 91, fontSizeBytes: 31457280), isTrue);
      expect(webViewCanLoadFont(webViewMajorVersion: 91, fontSizeBytes: 31457281), isFalse);
      expect(webViewCanLoadFont(webViewMajorVersion: 154, fontSizeBytes: 134217728), isTrue);
      expect(webViewCanLoadFont(webViewMajorVersion: 154, fontSizeBytes: 134217729), isFalse);
    });

    test('小於 30MB 的字型在舊 WebView 也載得動', () {
      expect(webViewCanLoadFont(webViewMajorVersion: 91, fontSizeBytes: 21704488), isTrue);
    });

    test('讀不到版本（null）→ 視同支援，行為和現在一樣', () {
      expect(webViewCanLoadFont(webViewMajorVersion: null, fontSizeBytes: serif), isTrue);
    });
  });

  group('readWebViewMajorVersion', () {
    test('回傳平台版本字串的主版本號', () async {
      expect(await readWebViewMajorVersion(readVersionName: () async => '91.0.4472.114'), 91);
    });

    test('平台回傳 null → null', () async {
      expect(await readWebViewMajorVersion(readVersionName: () async => null), isNull);
    });

    test('平台呼叫拋例外（例如 MissingPluginException）→ null，不往外拋', () async {
      expect(
        await readWebViewMajorVersion(
            readVersionName: () async => throw MissingPluginException('no impl')),
        isNull,
      );
    });

    test('平台一直不回應 → 逾時後 null，不卡住啟動', () async {
      final never = Completer<String?>();
      expect(
        await readWebViewMajorVersion(
          readVersionName: () => never.future,
          timeout: const Duration(milliseconds: 20),
        ),
        isNull,
      );
    });
  });
}
```

- [ ] **Step 3：執行測試，確認失敗**

```bash
flutter test test/reader/webview_font_support_test.dart
```
預期：FAIL，編譯錯誤 `Error when reading 'lib/reader/webview_font_support.dart'`（檔案還不存在）。

- [ ] **Step 4：寫實作**

建立 `app/lib/reader/webview_font_support.dart`：

```dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// 系統 WebView 能載入的網頁字型大小（epic-49 Issue 7）。
///
/// Chromium 的 `web_font_decoder.cc` 會拒絕超過上限的網頁字型，console 訊息為
/// `OTS parsing error: Web font size more than 30MB`，畫面退回系統字型。上限在
/// Chromium commit 3c603c19be（Cr-Commit-Position #1040311，落在 M107）由 30MB
/// 放寬為 128MB。Issue 5 真機驗證：WebView 91 拒絕思源宋體（57.1MB），WebView 154 正常。

/// 上限放寬為 128MB 的第一個 Chromium 主版本。
const int kWebViewLargeFontMinMajorVersion = 107;

/// WebView 106 以前的網頁字型上限。
const int kLegacyWebFontSizeLimitBytes = 30 * 1024 * 1024;

/// WebView 107 起的網頁字型上限。
const int kWebFontSizeLimitBytes = 128 * 1024 * 1024;

/// 從 WebView 版本字串（例如 `91.0.4472.114`）取出主版本號；無法解析時回傳 null。
int? parseWebViewMajorVersion(String? versionName) {
  if (versionName == null) return null;
  final match = RegExp(r'^\d+').firstMatch(versionName.trim());
  return match == null ? null : int.parse(match.group(0)!);
}

/// 這個 WebView 能不能載入 [fontSizeBytes] 大小的字型。
///
/// [webViewMajorVersion] 為 null（讀不到版本）時視同支援：讀不到多半是平台呼叫失敗，
/// 不代表 WebView 舊；視同支援最壞只是回到 Issue 7 之前的行為（計畫決定 2）。
/// Chromium 以「大於上限」才拒絕，所以剛好等於上限可以載入。
bool webViewCanLoadFont({
  required int? webViewMajorVersion,
  required int fontSizeBytes,
}) {
  if (webViewMajorVersion == null) return true;
  final limit = webViewMajorVersion >= kWebViewLargeFontMinMajorVersion
      ? kWebFontSizeLimitBytes
      : kLegacyWebFontSizeLimitBytes;
  return fontSizeBytes <= limit;
}

/// 讀取系統 WebView 的主版本號。任何失敗（沒有平台實作、例外、逾時）都回傳 null，
/// 不往外拋：這在 App 啟動時呼叫，不能擋住啟動。[readVersionName] 只供測試注入。
Future<int?> readWebViewMajorVersion({
  Future<String?> Function()? readVersionName,
  Duration timeout = const Duration(seconds: 3),
}) async {
  final read = readVersionName ??
      () async => (await InAppWebViewController.getCurrentWebViewPackage())?.versionName;
  try {
    return parseWebViewMajorVersion(await read().timeout(timeout));
  } catch (e) {
    debugPrint('Failed to read WebView version: $e');
    return null;
  }
}
```

- [ ] **Step 5：執行測試，確認通過**

```bash
flutter test test/reader/webview_font_support_test.dart
```
預期：`All tests passed!`（12 個測試）。

- [ ] **Step 6：analyze 並提交**

```bash
flutter analyze
git add lib/reader/webview_font_support.dart test/reader/webview_font_support_test.dart
git commit -m "feat(fonts): 新增 WebView 字型大小支援判斷（epic-49 Issue 7）"
```
預期：`No issues found!`。

---

### Task 2：`DownloadableFontStore` 只公開載得動的字型

**Files:**
- Modify: `app/lib/reader/downloadable_font_store.dart`（建構子 52-62 行、`prepare()` 86-99 行、`installedFonts()` 101-107 行）
- Modify: `app/test/support/fake_downloadable_font_store.dart`
- Test: `app/test/reader/downloadable_font_store_test.dart`
- Test: `app/test/screens/reader_screen_test.dart`（`group('未下載字型改用書本字型（epic-49 Issue 6）'`，約 6673 行）

**Interfaces:**
- Consumes：Task 1 的 `webViewCanLoadFont({required int? webViewMajorVersion, required int fontSizeBytes})`。
- Produces：
  - 建構參數 `int? webViewMajorVersion`（可選，預設 `null` = 視同支援，既有呼叫與測試不必修改）
  - `List<AppFont> get supportedFonts`（依 `AppFont.values` 順序）
  - `installedFonts()` 只回傳 `supportedFonts` 裡已下載的字型
  - `prepare()` 另外刪除不在 `supportedFonts` 裡、但已存在的正式字型檔
  - Fake：`List<AppFont> supported` 欄位（預設全部字型），`installedFonts()` 只回傳 `installed` 與 `supported` 的交集

- [ ] **Step 1：寫失敗的測試**

在 `app/test/reader/downloadable_font_store_test.dart` 最後一個 `group` 之後、`main()` 結尾的 `}` 之前，加入：

```dart
  group('WebView 太舊時只公開載得動的字型（Issue 7）', () {
    /// 思源黑體標成 40MB（舊 WebView 載不動）、思源宋體維持 50,000 bytes（載得動），
    /// 驗證判斷是依每款字型的大小，不是一律全擋。
    FontDownloadSpec mixedSpecOf(AppFont font) => font == AppFont.sourceHanSans
        ? FontDownloadSpec(
            publishPath: specA.publishPath, sizeBytes: 40 * 1024 * 1024, sha256: specA.sha256)
        : specB;

    DownloadableFontStore storeFor(int? webViewMajorVersion) => DownloadableFontStore(
          httpClient: serving({}),
          directory: fontsDir,
          baseUri: Uri.parse('https://fonts.test/'),
          specOf: mixedSpecOf,
          webViewMajorVersion: webViewMajorVersion,
        );

    Future<void> placeInstalledFiles() async {
      await fileFor(specA.publishPath).create(recursive: true);
      await fileFor(specB.publishPath).create(recursive: true);
    }

    test('舊 WebView（91）：supportedFonts 不含超過 30MB 的字型', () {
      expect(storeFor(91).supportedFonts, [AppFont.sourceHanSerif]);
    });

    test('新 WebView（154）與讀不到版本（null）：supportedFonts 是全部字型', () {
      expect(storeFor(154).supportedFonts, AppFont.values);
      expect(storeFor(null).supportedFonts, AppFont.values);
    });

    test('沒有傳 webViewMajorVersion 時行為和以前一樣（全部支援）', () {
      expect(storeWith(serving({})).supportedFonts, AppFont.values);
    });

    test('舊 WebView：檔案存在也不列為已下載', () async {
      await placeInstalledFiles();
      expect(await storeFor(91).installedFonts(), {AppFont.sourceHanSerif});
    });

    test('舊 WebView：prepare 刪除載不動的已下載檔案，保留載得動的', () async {
      await placeInstalledFiles();
      await storeFor(91).prepare();
      expect(await filesIn(fontsDir), [specB.publishPath]);
    });

    test('讀不到版本（null）：prepare 不刪任何正式檔案', () async {
      await placeInstalledFiles();
      await storeFor(null).prepare();
      expect((await filesIn(fontsDir))..sort(), [specA.publishPath, specB.publishPath]);
    });
  });
```

`fileFor`、`filesIn`、`storeWith`、`serving`、`specA`、`specB` 都是這個測試檔既有的 helper（見檔案開頭與 `main()` 內 85-97 行）。

- [ ] **Step 2：執行測試，確認失敗**

```bash
flutter test test/reader/downloadable_font_store_test.dart
```
預期：FAIL，編譯錯誤 `No named parameter with the name 'webViewMajorVersion'` 與 `The getter 'supportedFonts' isn't defined`。

- [ ] **Step 3：寫實作**

在 `app/lib/reader/downloadable_font_store.dart`：

1. 加上 import（放在 `import 'font_download_catalog.dart';` 下一行）：
```dart
import 'webview_font_support.dart';
```

2. 建構子（52-62 行）改成：
```dart
  DownloadableFontStore({
    required http.Client httpClient,
    required Directory directory,
    Uri? baseUri,
    FontDownloadSpec Function(AppFont font) specOf = fontDownloadSpecOf,
    Duration idleTimeout = const Duration(seconds: 30),
    int? webViewMajorVersion,
  })  : _httpClient = httpClient,
        _directory = directory,
        _baseUri = baseUri ?? Uri.parse(kFontDownloadBaseUrl),
        _specOf = specOf,
        _idleTimeout = idleTimeout,
        _webViewMajorVersion = webViewMajorVersion;
```

3. 在 `final Duration _idleTimeout;` 那段之後加上：
```dart
  /// 系統 WebView 主版本號；null 代表讀不到，視同支援全部字型（Issue 7 計畫決定 2）。
  final int? _webViewMajorVersion;

  /// 這台裝置的系統 WebView 載得動的內建字型，依 [AppFont.values] 順序（Issue 7）。
  /// 舊版 WebView 拒絕超過 30MB 的網頁字型，這些字型不列出、不視為已下載。
  List<AppFont> get supportedFonts => [
        for (final font in AppFont.values)
          if (webViewCanLoadFont(
              webViewMajorVersion: _webViewMajorVersion,
              fontSizeBytes: _specOf(font).sizeBytes))
            font,
      ];
```

4. `prepare()`（86-99 行）在 `await for` 迴圈結束後、方法結尾 `}` 之前加上：
```dart
    // Issue 7：WebView 載不動的字型，檔案留著也用不到，刪掉釋放空間（思源宋體約 57MB）。
    // 不修改任何書籍偏好；WebView 升級後重新下載，偏好會自動生效。讀不到 WebView 版本時
    // supportedFonts 是全部字型，這裡不會刪任何檔案。
    final supported = supportedFonts;
    for (final font in AppFont.values) {
      if (supported.contains(font)) continue;
      try {
        await delete(font);
      } on FileSystemException {
        // 盡力清理：刪不掉不影響判斷，installedFonts() 本來就不會列出它
      }
    }
```

5. `installedFonts()`（101-107 行）的迴圈改成走訪 `supportedFonts`：
```dart
  Future<Set<AppFont>> installedFonts() async {
    final installed = <AppFont>{};
    for (final font in supportedFonts) {
      if (await _fileFor(font).exists()) installed.add(font);
    }
    return installed;
  }
```

6. `download()` 的說明註解（115-117 行）最後補一句（計畫審查 M-3）：
```dart
  /// 不檢查 [font] 是否在 [supportedFonts] 裡：唯一的呼叫端（字型管理畫面）只列出
  /// supportedFonts；萬一下載了載不動的字型，下次啟動時 [prepare] 會刪掉（Issue 7）。
```

- [ ] **Step 4：執行 store 測試，確認通過**

```bash
flutter test test/reader/downloadable_font_store_test.dart
```
預期：`All tests passed!`。

- [ ] **Step 5：Fake 加上 `supported`，並寫閱讀器的失敗測試**（計畫審查 I-2）

`app/test/support/fake_downloadable_font_store.dart`，在 `Completer<void>? installedFontsGate;` 那段之後加上（`installedFonts()` 先不改，下一步要看測試失敗）：
```dart
  /// [supportedFonts] 回傳的字型；測試可以改成部分或空清單，模擬舊版系統 WebView（Issue 7）。
  List<AppFont> supported = List.of(AppFont.values);

  @override
  List<AppFont> get supportedFonts => supported;
```

`app/test/screens/reader_screen_test.dart` 的 `group('未下載字型改用書本字型（epic-49 Issue 6）', () {` 群組內、最後一個 `testWidgets` 之後（群組結尾的 `});` 之前）加入。`pumpReader`、`readerView`、`prefsManager` 都是這個群組或檔案既有的 helper：
```dart
    testWidgets('舊 WebView 裝置上已下載的字型：閱讀設定選單不列出（Issue 7）', (tester) async {
      final store = FakeDownloadableFontStore()
        ..installed.add(AppFont.sourceHanSerif)
        ..supported = []; // 模擬舊 WebView 載不動
      await pumpReader(tester, store: store);

      readerView(tester).onLayoutResolved?.call(const EpubLayoutInfo(
            isFixedLayout: false,
            writingMode: WritingMode.horizontal,
          ));
      await tester.pump();
      await tester.tap(find.byKey(const Key('reader_chrome_layout_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      final sheet = tester.widget<ReaderSettingsSheet>(find.byType(ReaderSettingsSheet));
      expect(sheet.installedFonts, isEmpty);
    });

    testWidgets('舊 WebView 裝置上已下載的字型：閱讀器收到 null，偏好不改寫（Issue 7）', (tester) async {
      await prefsManager.saveBookPrefs(
          'b1', const BookReaderPrefs(fontFamily: 'SourceHanSerifTC'));
      final store = FakeDownloadableFontStore()
        ..installed.add(AppFont.sourceHanSerif)
        ..supported = []; // 模擬舊 WebView 載不動

      await pumpReader(tester, store: store);

      expect(readerView(tester).fontFamily, isNull);
      expect(prefsManager.bookPrefsByBookId['b1']!.fontFamily, 'SourceHanSerifTC');
    });
```

- [ ] **Step 6：執行閱讀器測試，確認兩個新測試失敗**

```bash
flutter test test/screens/reader_screen_test.dart --plain-name "Issue 7"
```
預期：2 個測試 FAIL。第一個期望空集合、實際含 `AppFont.sourceHanSerif`；第二個期望 `null`、實際是 `'SourceHanSerifTC'`。原因是 Fake 的 `installedFonts()` 還沒依 `supported` 過濾。

- [ ] **Step 7：Fake 的 `installedFonts()` 依 `supported` 過濾**（計畫審查 I-1）

`app/test/support/fake_downloadable_font_store.dart` 的 `installedFonts()` 改成：
```dart
  @override
  Future<Set<AppFont>> installedFonts() async {
    if (installedFontsGate != null) await installedFontsGate!.future;
    // 比照真的 store：不在 supportedFonts 裡的字型，檔案存在也不算已下載（Issue 7）
    return installed.where(supported.contains).toSet();
  }
```

- [ ] **Step 8：執行測試，確認通過**

```bash
flutter test test/reader/downloadable_font_store_test.dart test/screens/font_management_screen_test.dart test/screens/reader_screen_test.dart
```
預期：`All tests passed!`。後兩個檔案使用 Fake，同時確認 Fake 改動後既有測試零回歸（`supported` 預設是全部字型，過濾對既有測試沒有影響）。

- [ ] **Step 9：analyze 並提交**

```bash
flutter analyze
git add lib/reader/downloadable_font_store.dart test/reader/downloadable_font_store_test.dart test/support/fake_downloadable_font_store.dart test/screens/reader_screen_test.dart
git commit -m "feat(fonts): 字型 store 只公開 WebView 載得動的字型，啟動時刪除載不動的檔案（epic-49 Issue 7）"
```
預期：`No issues found!`。

---

### Task 3：字型管理畫面只列載得動的字型，並在啟動時讀取 WebView 版本

**Files:**
- Modify: `app/lib/screens/font_management_screen.dart`（`build()` 內 128 行）
- Modify: `app/lib/l10n/app_zh_TW.arb`、`app_zh.arb`、`app_zh_CN.arb`、`app_en.arb`
- Regenerate: `app/lib/l10n/app_localizations.dart`、`app_localizations_en.dart`、`app_localizations_zh.dart`
- Modify: `app/lib/main.dart`（import 區、121-125 行）
- Test: `app/test/screens/font_management_screen_test.dart`

**Interfaces:**
- Consumes：Task 2 的 `DownloadableFontStore.supportedFonts`、建構參數 `webViewMajorVersion`；Task 1 的 `readWebViewMajorVersion()`；Fake 的 `supported` 欄位。
- Produces：l10n key `fontManagementBuiltInUnsupportedHint`；Widget key `font_management_builtin_unsupported_hint`。

- [ ] **Step 1：寫失敗的測試**

在 `app/test/screens/font_management_screen_test.dart` 的 `group('可下載字型（epic-49）', () {` 裡，`testWidgets('英文介面：字型名稱與狀態以英文顯示'` 之前加入：

```dart
    testWidgets('WebView 載得動全部字型時，不顯示隱藏提示（Issue 7）', (tester) async {
      await pumpScreen(tester, store: store);

      expect(find.byKey(const Key('font_management_builtin_unsupported_hint')), findsNothing);
    });

    testWidgets('WebView 太舊、一款都載不動：不列出內建字型，顯示提示（Issue 7）', (tester) async {
      store.supported = [];
      await pumpScreen(tester, store: store);

      expect(find.text('思源黑體'), findsNothing);
      expect(find.text('思源宋體'), findsNothing);
      expect(find.byKey(const Key('font_management_builtin_unsupported_hint')), findsOneWidget);
      expect(
        find.text('這台裝置的系統 WebView 版本太舊，部分內建字型無法使用，已從清單隱藏。更新「Android System WebView」後即可下載。'),
        findsOneWidget,
      );
    });

    testWidgets('只有部分字型載不動：只列出載得動的，並顯示提示（Issue 7）', (tester) async {
      store.supported = [AppFont.sourceHanSerif];
      await pumpScreen(tester, store: store);

      expect(find.text('思源黑體'), findsNothing);
      expect(find.text('思源宋體'), findsOneWidget);
      expect(find.byKey(const Key('font_management_builtin_unsupported_hint')), findsOneWidget);
    });

    testWidgets('英文介面：隱藏提示以英文顯示（Issue 7）', (tester) async {
      store.supported = [];
      await pumpScreen(tester, store: store, locale: const Locale('en'));

      expect(
        find.text("This device's system WebView is too old for some built-in fonts, so they are hidden. Update Android System WebView to download them."),
        findsOneWidget,
      );
    });
```

- [ ] **Step 2：執行測試，確認失敗**

```bash
flutter test test/screens/font_management_screen_test.dart
```
預期：後三個新測試 FAIL（找得到「思源黑體」、找不到提示 key）；第一個新測試 PASS（目前本來就沒有這個提示，這是回歸保護，不是新行為）。

- [ ] **Step 3：新增介面字串**

四個 arb 都在 `fontManagementDownloadableDeleteConfirmMessage` 那一項之後加入新項目。

`app/lib/l10n/app_zh_TW.arb`（加在 `"@fontManagementDownloadableDeleteConfirmMessage": { … },` 區塊之後）：
```json
  "fontManagementBuiltInUnsupportedHint": "這台裝置的系統 WebView 版本太舊，部分內建字型無法使用，已從清單隱藏。更新「Android System WebView」後即可下載。",
  "@fontManagementBuiltInUnsupportedHint": {
    "description": "字型管理：系統 WebView 太舊（Chromium 106 以前拒絕超過 30MB 的網頁字型），有內建字型被隱藏時顯示在「內建字型」標題下（epic-49 Issue 7）"
  },
```

`app/lib/l10n/app_zh.arb`：
```json
  "fontManagementBuiltInUnsupportedHint": "這台裝置的系統 WebView 版本太舊，部分內建字型無法使用，已從清單隱藏。更新「Android System WebView」後即可下載。",
```

`app/lib/l10n/app_zh_CN.arb`：
```json
  "fontManagementBuiltInUnsupportedHint": "这台设备的系统 WebView 版本太旧，部分内建字体无法使用，已从列表隐藏。更新「Android System WebView」后即可下载。",
```

`app/lib/l10n/app_en.arb`：
```json
  "fontManagementBuiltInUnsupportedHint": "This device's system WebView is too old for some built-in fonts, so they are hidden. Update Android System WebView to download them.",
```

接著產生程式碼：
```bash
flutter gen-l10n
git status --short lib/l10n
```
預期：4 個 arb 與 `app_localizations.dart`、`app_localizations_en.dart`、`app_localizations_zh.dart` 顯示為已修改。

- [ ] **Step 4：修改字型管理畫面**

`app/lib/screens/font_management_screen.dart` 的 `build()`，把：
```dart
          for (final font in AppFont.values) _buildBuiltInFontTile(font, l10n),
```
改成：
```dart
          // Issue 7：只列出系統 WebView 載得動的內建字型；沒有 store 時照舊列出全部
          if (builtInFonts.length < AppFont.values.length)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text(
                l10n.fontManagementBuiltInUnsupportedHint,
                key: const Key('font_management_builtin_unsupported_hint'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          for (final font in builtInFonts) _buildBuiltInFontTile(font, l10n),
```
並在同一個 `build()` 開頭 `final l10n = AppLocalizations.of(context)!;` 下一行加上：
```dart
    final builtInFonts = widget.downloadableFontStore?.supportedFonts ?? AppFont.values;
```

- [ ] **Step 5：執行測試，確認通過**

```bash
flutter test test/screens/font_management_screen_test.dart
```
預期：`All tests passed!`。

- [ ] **Step 6：啟動時讀取 WebView 版本**

`app/lib/main.dart`：

1. 在 `import 'reader/tts_provider.dart';` 之後加上：
```dart
import 'reader/webview_font_support.dart';
```

2. 把建構 store 的程式（121-125 行）：
```dart
  final downloadableFontStore = DownloadableFontStore(
    httpClient: http.Client(),
    directory: Directory(
        p.join((await getApplicationSupportDirectory()).path, 'downloaded-fonts')),
  );
```
改成：
```dart
  // epic-49 Issue 7：Chromium 106 以前的系統 WebView 拒絕超過 30MB 的網頁字型，
  // store 依版本只公開載得動的字型。讀不到版本時回傳 null（最多等 3 秒），視同支援。
  final webViewMajorVersion = await readWebViewMajorVersion();
  final downloadableFontStore = DownloadableFontStore(
    httpClient: http.Client(),
    directory: Directory(
        p.join((await getApplicationSupportDirectory()).path, 'downloaded-fonts')),
    webViewMajorVersion: webViewMajorVersion,
  );
```

- [ ] **Step 7：analyze、l10n 檢查並提交**

```bash
flutter analyze
node tool/check_l10n_hardcoded_strings.js
git add lib/screens/font_management_screen.dart lib/main.dart lib/l10n test/screens/font_management_screen_test.dart
git commit -m "feat(fonts): 字型管理只列出 WebView 載得動的內建字型並提示原因，啟動時讀取 WebView 版本（epic-49 Issue 7）"
```
預期：`flutter analyze` 輸出 `No issues found!`；l10n 檢查沒有回報問題。

---

### Task 4：整體驗證、真機確認與進度記錄

**Files:**
- Modify: `docs/epics/epic-49-downloadable-fonts/epic.md`
- Modify: `docs/epics/epic-49-downloadable-fonts/issues.md`
- Modify: `docs/epics.md`
- Modify: `docs/epics/epic-49-downloadable-fonts/plans/plan-issue-7.md`（勾選步驟）

- [ ] **Step 1：完整測試與靜態檢查**

在 `app/`：
```bash
flutter test
flutter analyze
node tool/check_l10n_hardcoded_strings.js
```
預期：`All tests passed!`；`No issues found!`；l10n 檢查沒有回報問題。

- [ ] **Step 2：建置 debug APK**

```bash
flutter build apk --debug
```
預期：`√ Built build\app\outputs\flutter-apk\app-debug.apk`。

- [ ] **Step 3：真機確認（人類操作）**

需要 Issue 5 用過的兩台裝置。兩台的 adb 傳輸都很慢（約 20 KB/s），APK 建議用 USB 檔案傳輸複製到裝置「Download」資料夾後在裝置上安裝（同簽章覆蓋更新，資料保留）。

電子紙（Allwinner WAVE，WebView 91；Issue 5 驗證時已下載思源宋體）：
1. 安裝後開 App → 設定 → 字型管理。預期：「內建字型」底下只有一行提示，沒有思源黑體、思源宋體。
2. 確認字型檔已被刪除（Git Bash，repo 根目錄）：
   ```bash
   adb shell run-as cc.ugotit.elinkbook ls -la files/downloaded-fonts/v1
   ```
   預期：沒有 `SourceHanSerifTC-VF.ttf`。
3. 開 `epic-49 字型驗證書` → 閱讀設定。預期：字型選單沒有思源宋體，顯示「使用書本字型」；英文段落是等寬字型。

一般手機（9491G，WebView 154）：
4. 安裝後開字型管理。預期：兩款字型照常列出，沒有提示；已下載的思源宋體、思源黑體仍是「已下載」。
5. 開驗證書。預期：仍是思源宋體（沿用 Issue 5 的偏好）。

回報每一步「通過／失敗＋一句觀察」。

- [ ] **Step 4：記錄進度**

依 Step 1、3 的實際結果：

1. `issues.md` Issue 7 的 `**Status:**` 改成 `completed`。
2. `epic.md` 開發記錄最後新增一段 `**<YYYY-MM-DD> Issue 7 完成**（分支 `epic-49/issue-7-legacy-webview-fonts`，待 PR 合併）`，寫明：門檻版本與來源（commit `3c603c19be`、M107）、計畫決定 1～4、完整測試結果、真機確認結果。
3. 真機確認都通過時，`epic.md` 同一段加一句：Issue 5 第 8 項依 Issue 7 的驗收方式在電子紙重驗通過，由人類決定 Issue 5 是否改為 `completed`。有失敗時照實記錄，不改 Issue 5 狀態。
4. `docs/epics.md` epic-49 那一列備註改成：`Issue 7 已完成，待 PR 合併與 Issue 5 重驗結案`。

- [ ] **Step 5：勾選本計畫並提交**

在 repo 根目錄：
```bash
git add docs/epics.md docs/epics/epic-49-downloadable-fonts/epic.md docs/epics/epic-49-downloadable-fonts/issues.md docs/epics/epic-49-downloadable-fonts/plans/plan-issue-7.md
git commit -m "docs(epic-49): 記錄 Issue 7 完成"
```
之後依人類指示推送並發 PR。
