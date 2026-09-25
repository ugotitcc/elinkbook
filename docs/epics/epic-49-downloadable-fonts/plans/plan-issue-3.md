# Issue 3：下載與字型管理畫面（`DownloadableFontStore`＋字型管理 UI）實作計畫

> **給執行者（agentic worker）：** 必須使用子技能 superpowers:subagent-driven-development（建議）或 superpowers:executing-plans，逐一執行本計畫的 Task。步驟使用核取方塊（`- [x]`），完成一個就改成 `- [x]`。

**目標：** 讓使用者在「字型管理」畫面下載、取消、重試、刪除內建字型。下載的檔案經過 SHA-256 驗證後存在 App 支援目錄；本 Issue 還不處理閱讀器套用（Issue 4）。

**架構：** 新增兩個檔案：字型目錄 `font_download_catalog.dart`（每款字型的發布路徑、大小、SHA-256）與核心模組 `downloadable_font_store.dart`（下載、驗證、狀態查詢，全部失敗以 `FontDownloadException` 回報）。`FontManagementScreen` 只依賴 store 的公開介面，測試時注入假的 store。store 的建構參數注入 `http.Client`、存放目錄、基底網址、字型目錄查詢函式，讓 store 本身能用 `MockClient` 與暫存目錄在單元測試中驅動。

**技術：** Flutter／Dart、`package:http`（含 `package:http/testing.dart` 的 `MockClient`）、`package:crypto`（串流 SHA-256）、`package:path`、`package:path_provider`、`flutter_localizations`（ARB）。以上都已是既有依賴，不新增套件。

**規格：** `docs/epics/epic-49-downloadable-fonts/spec.md`（「字型目錄」「可下載字型儲存」「字型管理畫面」「在地化字串」「測試決策」）、`docs/adr/0035-downloadable-fonts-via-r2-worker.md`、`issues.md` Issue 3。

## 全域限制

- 所有指令在 `app/` 目錄執行。
- 啟用中的字型只有 `AppFont.sourceHanSans`、`AppFont.sourceHanSerif`；停用的 3 款沿用 `[字型停用]` 註解標記，數值照填在註解中。
- 字型目錄數值（逐字複製）：
  - `sourceHanSans`：`v1/SourceHanSansTC-VF.ttf`，36034016 bytes，`1a273a56aa47250c7af95e461ee0c8236c60d7141e14a37bd18baccb1e851b19`
  - `sourceHanSerif`：`v1/SourceHanSerifTC-VF.ttf`，59898316 bytes，`71354ed752104c8a3cbcff18943c6110d179d01cc6eaaf1aff7ea14c4a447879`
  - `guanKiapTsingKhai`（停用）：`v1/GuanKiapTsingKhai.ttf`，14675776 bytes，`758632243c499e431fd0c847f5e8c431acf59a9b41a26237a819466139994d38`
  - `taiwanPearl`（停用）：`v1/TaiwanPearl-Regular.ttf`，21704488 bytes，`51b3c9a4ab1b6b45dcdad7c5ae93386aea399fd3dabb85d2ac41110dc57f211d`
  - `genRyuMinTW`（停用）：`v1/GenRyuMinTW-Regular.ttf`，15976964 bytes，`9178c199d633075b8bb91902216c3e1bc977a11fde12471a2c9a250434402927`
- 下載服務基底網址在本 Issue 用 `https://elinkbook-fonts.invalid/`（RFC 2606 保留網域，保證連不上）；Issue 4 換成正式網址。
- 存放目錄：`getApplicationSupportDirectory()` 底下的 `downloaded-fonts/`；本機路徑與發布路徑一致（`downloaded-fonts/v1/<檔名>`）。
- 「已下載」只看正式檔案是否存在；下載先寫 `<正式檔名>.part`，SHA-256 相符才改名。
- 進度以 0～100 的整數百分比回報，**只在數值變大時才呼叫**（一次下載最多 101 次）。
- 已有下載進行中時再呼叫 `download()`，拋出 `StateError`。
- 下載中時，其他所有內建字型列的「下載」「重試」「刪除」停用；AppBar「上傳自訂字型」**不停用**。
- 刪除可下載字型**不修改** `book_reader_prefs`、不查詢使用中的書籍數量；確認對話框標題沿用 `fontManagementDeleteConfirmTitle`，內文用新增的 `fontManagementDownloadableDeleteConfirmMessage`，**不可**用 `fontManagementDeleteConfirmMessage`。
- 所有新增的建構參數都是可選的，既有呼叫端與測試不必修改。
- 新字串三種語系都要提供（`app_zh_TW.arb` 是範本，另有 `app_zh.arb`、`app_zh_CN.arb`、`app_en.arb`）；改完 ARB 必須執行 `flutter gen-l10n`，產生的 `lib/l10n/app_localizations*.dart` 要一起提交。
- 程式註解與文件使用正體中文。
- 單一 Task 只跑異動到的測試檔；完整 `flutter test` 只在 Task 7 執行一次（約 5 分鐘）。

**與 spec 用詞的差異（刻意）：** spec 的錯誤原因代碼 `http`，在程式中命名為 `FontDownloadFailure.httpStatus`，避免和 `import 'package:http/http.dart' as http;` 的前綴撞名。檔案大小顯示格式（例如「34.4 MB」）在三種語系寫法相同，所以做成純函式 `formatFontFileSize()`，不另外做在地化字串。

## 審查重點（Review Focus）

1. **連線在下載中途斷掉**（回應已經 200、串流途中拋出 `http.ClientException`）：應回報 `network`，並且不留下任何檔案。→ Task 3 測試「串流中途斷線」。
2. **伺服器回傳錯誤的 `Content-Length`**（比實際小）：進度不能超過 100、必須嚴格遞增，下載仍以 SHA-256 判定成功。→ Task 3 測試「Content-Length 比實際小」。
3. **已下載的字型再下載一次並成功**（Windows 上 `rename` 無法覆蓋既有檔案）：應正確取代舊檔。→ Task 2 測試「重新下載成功會取代既有檔案」。
4. **離開字型管理畫面後，下載才結束**：不可在已 dispose 的 State 上呼叫 `setState` 拋例外。→ Task 5 測試「離開畫面後下載才結束不拋例外」。
5. **存放目錄無法寫入**：應回報 `storage`，UI 顯示「無法儲存檔案」訊息。→ Task 2 測試「無法建立暫存檔時回報 storage」；Task 5 測試「storage 失敗顯示對應訊息」。

---

## 檔案結構

| 檔案 | 動作 | 責任 |
|---|---|---|
| `lib/reader/font_download_catalog.dart` | 新增 | 字型目錄：`FontDownloadSpec`、`fontDownloadSpecOf()`、`kFontDownloadBaseUrl` |
| `lib/reader/downloadable_font_store.dart` | 新增 | `DownloadableFontStore`、`FontDownloadException`、`FontDownloadFailure`、`FontDownloadCancellationToken` |
| `lib/screens/font_management_screen.dart` | 修改 | 內建字型四種狀態、下載互斥、刪除確認；`formatFontFileSize()` |
| `lib/l10n/app_zh_TW.arb`、`app_zh.arb`、`app_zh_CN.arb`、`app_en.arb` | 修改 | 10 個新字串 |
| `lib/l10n/app_localizations*.dart` | 重新產生 | `flutter gen-l10n` |
| `lib/main.dart` | 修改 | 建構 store、呼叫 `prepare()`、傳給 `ElinkBookApp` |
| `lib/screens/library_screen_dependencies.dart` | 修改 | `LibraryReaderFeatureRepositories` 新增 `downloadableFontStore` |
| `lib/screens/adaptive_shell_scaffold.dart` | 修改 | 傳給 `SettingsScaffold` |
| `lib/screens/settings_scaffold.dart` | 修改 | 新增參數，傳給 `FontManagementScreen` |
| `test/reader/font_download_catalog_test.dart` | 新增 | 目錄數值 |
| `test/reader/downloadable_font_store_test.dart` | 新增 | store 行為 |
| `test/support/fake_downloadable_font_store.dart` | 新增 | 測試用假 store（Issue 4 也會用） |
| `test/screens/font_management_screen_test.dart` | 修改 | 新增畫面測試 |
| `test/screens/settings_scaffold_test.dart` | 修改 | 依賴注入測試 |

---

### Task 1：字型目錄

**Files:**
- Create: `lib/reader/font_download_catalog.dart`
- Test: `test/reader/font_download_catalog_test.dart`

**Interfaces:**
- Produces：
  ```dart
  const String kFontDownloadBaseUrl; // 'https://elinkbook-fonts.invalid/'
  class FontDownloadSpec { final String publishPath; final int sizeBytes; final String sha256; }
  FontDownloadSpec fontDownloadSpecOf(AppFont font);
  ```

- [x] **Step 1：寫失敗的測試**

```dart
import 'package:elinkbook/reader/app_font.dart';
import 'package:elinkbook/reader/font_download_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('啟用中的字型對應 spec.md「字型目錄」表格的數值（epic-49）', () {
    final sans = fontDownloadSpecOf(AppFont.sourceHanSans);
    expect(sans.publishPath, 'v1/SourceHanSansTC-VF.ttf');
    expect(sans.sizeBytes, 36034016);
    expect(sans.sha256,
        '1a273a56aa47250c7af95e461ee0c8236c60d7141e14a37bd18baccb1e851b19');

    final serif = fontDownloadSpecOf(AppFont.sourceHanSerif);
    expect(serif.publishPath, 'v1/SourceHanSerifTC-VF.ttf');
    expect(serif.sizeBytes, 59898316);
    expect(serif.sha256,
        '71354ed752104c8a3cbcff18943c6110d179d01cc6eaaf1aff7ea14c4a447879');
  });

  test('每款字型的發布路徑互不相同，格式為 v<N>/<檔名>.ttf，雜湊為 64 字元小寫十六進位', () {
    final specs = AppFont.values.map(fontDownloadSpecOf).toList();
    expect(specs.map((s) => s.publishPath).toSet().length, specs.length);
    for (final spec in specs) {
      expect(spec.publishPath, matches(RegExp(r'^v[1-9][0-9]*/[A-Za-z0-9._-]+\.ttf$')));
      expect(spec.sha256, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(spec.sizeBytes, greaterThan(0));
    }
  });

  test('基底網址以斜線結尾，讓 Uri.resolve 能正確接上發布路徑', () {
    expect(kFontDownloadBaseUrl, endsWith('/'));
    expect(Uri.parse(kFontDownloadBaseUrl).resolve('v1/A.ttf').path, '/v1/A.ttf');
  });
}
```

- [x] **Step 2：執行測試確認失敗**

Run：`flutter test test/reader/font_download_catalog_test.dart`
Expected：編譯失敗，找不到 `font_download_catalog.dart`。

- [x] **Step 3：實作字型目錄**

`lib/reader/font_download_catalog.dart`：

```dart
import 'app_font.dart';

/// 字型下載服務的基底網址（epic-49，見 docs/adr/0035-downloadable-fonts-via-r2-worker.md）。
///
/// Issue 3 先用 RFC 2606 保留網域 `.invalid`（保證連不上，避免開發中誤連任何真實主機），
/// Issue 4 換成 Issue 2 部署後的 Cloudflare Worker `workers.dev` 網址。
/// 必須以斜線結尾，[Uri.resolve] 才會把發布路徑接在後面而不是取代最後一段。
const String kFontDownloadBaseUrl = 'https://elinkbook-fonts.invalid/';

/// 一款可下載字型的發布資訊。數值必須和 repo 根目錄 `fonts-cdn/fonts.json` 一致
/// （Issue 4 有 Dart 測試比對）；已發布的路徑永遠不覆蓋，改版時改用新的版本路徑。
class FontDownloadSpec {
  /// 相對於基底網址的發布路徑，也是本機存放目錄下的相對路徑，例如 `v1/SourceHanSansTC-VF.ttf`。
  final String publishPath;

  /// 檔案位元組大小；伺服器沒回傳 Content-Length 時用來計算進度，也用於畫面顯示。
  final int sizeBytes;

  /// 檔案內容的 SHA-256（小寫十六進位），下載完成後必須相符才算成功。
  final String sha256;

  const FontDownloadSpec({
    required this.publishPath,
    required this.sizeBytes,
    required this.sha256,
  });
}

/// 回傳 [font] 的發布資訊。用 exhaustive switch：新增或恢復字型時少寫一項就會編譯失敗。
FontDownloadSpec fontDownloadSpecOf(AppFont font) {
  switch (font) {
    case AppFont.sourceHanSans:
      return const FontDownloadSpec(
        publishPath: 'v1/SourceHanSansTC-VF.ttf',
        sizeBytes: 36034016,
        sha256: '1a273a56aa47250c7af95e461ee0c8236c60d7141e14a37bd18baccb1e851b19',
      );
    case AppFont.sourceHanSerif:
      return const FontDownloadSpec(
        publishPath: 'v1/SourceHanSerifTC-VF.ttf',
        sizeBytes: 59898316,
        sha256: '71354ed752104c8a3cbcff18943c6110d179d01cc6eaaf1aff7ea14c4a447879',
      );
    // [字型停用] case AppFont.guanKiapTsingKhai:
    // [字型停用]   return const FontDownloadSpec(
    // [字型停用]     publishPath: 'v1/GuanKiapTsingKhai.ttf',
    // [字型停用]     sizeBytes: 14675776,
    // [字型停用]     sha256: '758632243c499e431fd0c847f5e8c431acf59a9b41a26237a819466139994d38',
    // [字型停用]   );
    // [字型停用] case AppFont.taiwanPearl:
    // [字型停用]   return const FontDownloadSpec(
    // [字型停用]     publishPath: 'v1/TaiwanPearl-Regular.ttf',
    // [字型停用]     sizeBytes: 21704488,
    // [字型停用]     sha256: '51b3c9a4ab1b6b45dcdad7c5ae93386aea399fd3dabb85d2ac41110dc57f211d',
    // [字型停用]   );
    // [字型停用] case AppFont.genRyuMinTW:
    // [字型停用]   return const FontDownloadSpec(
    // [字型停用]     publishPath: 'v1/GenRyuMinTW-Regular.ttf',
    // [字型停用]     sizeBytes: 15976964,
    // [字型停用]     sha256: '9178c199d633075b8bb91902216c3e1bc977a11fde12471a2c9a250434402927',
    // [字型停用]   );
  }
}
```

- [x] **Step 4：執行測試確認通過**

Run：`flutter test test/reader/font_download_catalog_test.dart`
Expected：3 個測試全數通過。

- [x] **Step 5：Commit**

```bash
git add lib/reader/font_download_catalog.dart test/reader/font_download_catalog_test.dart
git commit -m "feat(fonts): 新增可下載字型目錄（epic-49 Issue 3）"
```

---

### Task 2：`DownloadableFontStore` 核心（下載、驗證、錯誤、查詢、刪除、啟動準備）

**Files:**
- Create: `lib/reader/downloadable_font_store.dart`
- Test: `test/reader/downloadable_font_store_test.dart`

**Interfaces:**
- Consumes：Task 1 的 `FontDownloadSpec`、`fontDownloadSpecOf`、`kFontDownloadBaseUrl`。
- Produces：
  ```dart
  enum FontDownloadFailure { network, httpStatus, integrity, storage, cancelled }
  class FontDownloadException implements Exception {
    const FontDownloadException(FontDownloadFailure reason, {int? statusCode});
    final FontDownloadFailure reason; final int? statusCode;
  }
  class FontDownloadCancellationToken { bool get isCancelled; void cancel(); }
  class DownloadableFontStore {
    DownloadableFontStore({required http.Client httpClient, required Directory directory,
        Uri? baseUri, FontDownloadSpec Function(AppFont font) specOf = fontDownloadSpecOf});
    String get directory;
    Future<void> prepare();
    Future<Set<AppFont>> installedFonts();
    Future<void> download(AppFont font,
        {void Function(int percent)? onProgress, FontDownloadCancellationToken? cancellationToken});
    Future<void> delete(AppFont font);
  }
  ```

- [x] **Step 1：寫失敗的測試**

`test/reader/downloadable_font_store_test.dart`（Task 3 會在同一檔案追加測試）：

```dart
import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:elinkbook/reader/app_font.dart';
import 'package:elinkbook/reader/downloadable_font_store.dart';
import 'package:elinkbook/reader/font_download_catalog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;

/// 測試用的假字型內容：100,000 bytes，內容固定，方便計算雜湊。
final List<int> fontBytesA = List<int>.generate(100000, (i) => i % 251);
final List<int> fontBytesB = List<int>.generate(50000, (i) => (i * 7) % 253);

FontDownloadSpec specFor(String path, List<int> bytes) => FontDownloadSpec(
      publishPath: path,
      sizeBytes: bytes.length,
      sha256: sha256.convert(bytes).toString(),
    );

/// 思源黑體對應 v1/A.ttf、思源宋體對應 v1/B.ttf，讓兩款字型的檔案互不干擾。
final specA = specFor('v1/A.ttf', fontBytesA);
final specB = specFor('v1/B.ttf', fontBytesB);
FontDownloadSpec testSpecOf(AppFont font) =>
    font == AppFont.sourceHanSans ? specA : specB;

/// 把 [bytes] 切成每塊 [chunkSize] bytes 的串流。
Stream<List<int>> chunked(List<int> bytes, {int chunkSize = 1000}) async* {
  for (var i = 0; i < bytes.length; i += chunkSize) {
    yield bytes.sublist(i, i + chunkSize > bytes.length ? bytes.length : i + chunkSize);
  }
}

/// 依請求路徑回傳對應內容的 MockClient；[served] 沒有的路徑回 404。
http.Client serving(
  Map<String, List<int>> served, {
  int chunkSize = 1000,
  int? Function(List<int> bytes)? contentLengthOf,
}) {
  return MockClient.streaming((request, _) async {
    final bytes = served[request.url.path];
    if (bytes == null) {
      return http.StreamedResponse(const Stream.empty(), 404);
    }
    return http.StreamedResponse(
      chunked(bytes, chunkSize: chunkSize),
      200,
      contentLength: contentLengthOf == null ? bytes.length : contentLengthOf(bytes),
    );
  });
}

void main() {
  late Directory root;
  late Directory fontsDir;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('downloadable_font_store_test');
    fontsDir = Directory(p.join(root.path, 'downloaded-fonts'));
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  DownloadableFontStore storeWith(http.Client client) => DownloadableFontStore(
        httpClient: client,
        directory: fontsDir,
        baseUri: Uri.parse('https://fonts.test/'),
        specOf: testSpecOf,
      );

  /// 存放目錄底下所有檔案的相對路徑（用 / 分隔），方便斷言「沒有留下任何檔案」。
  Future<List<String>> filesIn(Directory dir) async {
    if (!await dir.exists()) return [];
    return dir
        .list(recursive: true)
        .where((e) => e is File)
        .map((e) => p.relative(e.path, from: dir.path).replaceAll(r'\', '/'))
        .toList();
  }

  File fileFor(String publishPath) =>
      File(p.joinAll([fontsDir.path, ...publishPath.split('/')]));

  group('download 成功', () {
    test('下載後正式檔案內容正確、列為已下載，且請求的網址是基底網址加發布路徑', () async {
      Uri? requested;
      final client = MockClient.streaming((request, _) async {
        requested = request.url;
        return http.StreamedResponse(chunked(fontBytesA), 200,
            contentLength: fontBytesA.length);
      });
      final store = storeWith(client);
      await store.prepare();

      await store.download(AppFont.sourceHanSans);

      expect(requested.toString(), 'https://fonts.test/v1/A.ttf');
      expect(await fileFor('v1/A.ttf').readAsBytes(), fontBytesA);
      expect(await store.installedFonts(), {AppFont.sourceHanSans});
      expect(await filesIn(fontsDir), ['v1/A.ttf']);
    });

    test('存放目錄尚未建立時也能下載（download 會自行建立子目錄）', () async {
      final store = storeWith(serving({'/v1/A.ttf': fontBytesA}));

      await store.download(AppFont.sourceHanSans);

      expect(await store.installedFonts(), {AppFont.sourceHanSans});
    });

    test('重新下載成功會取代既有檔案（Windows 上 rename 不能覆蓋既有檔案）', () async {
      await fileFor('v1/A.ttf').create(recursive: true);
      await fileFor('v1/A.ttf').writeAsBytes([9, 9, 9]);
      final store = storeWith(serving({'/v1/A.ttf': fontBytesA}));

      await store.download(AppFont.sourceHanSans);

      expect(await fileFor('v1/A.ttf').readAsBytes(), fontBytesA);
      expect(await filesIn(fontsDir), ['v1/A.ttf']);
    });
  });

  group('download 失敗', () {
    Matcher failsWith(FontDownloadFailure reason, {int? statusCode}) => throwsA(
          isA<FontDownloadException>()
              .having((e) => e.reason, 'reason', reason)
              .having((e) => e.statusCode, 'statusCode', statusCode),
        );

    test('SHA-256 不符 → integrity，且沒有留下任何檔案', () async {
      final corrupted = List<int>.from(fontBytesA)..[0] ^= 0xff;
      final store = storeWith(serving({'/v1/A.ttf': corrupted}));

      await expectLater(
          store.download(AppFont.sourceHanSans), failsWith(FontDownloadFailure.integrity));
      expect(await filesIn(fontsDir), isEmpty);
    });

    test('HTTP 404 → httpStatus，附狀態碼', () async {
      final store = storeWith(serving({}));

      await expectLater(store.download(AppFont.sourceHanSans),
          failsWith(FontDownloadFailure.httpStatus, statusCode: 404));
      expect(await filesIn(fontsDir), isEmpty);
    });

    test('HTTP 500 → httpStatus，附狀態碼', () async {
      final store = storeWith(MockClient.streaming(
          (request, _) async => http.StreamedResponse(const Stream.empty(), 500)));

      await expectLater(store.download(AppFont.sourceHanSans),
          failsWith(FontDownloadFailure.httpStatus, statusCode: 500));
    });

    test('連線失敗（ClientException）→ network', () async {
      final store = storeWith(MockClient.streaming(
          (request, _) async => throw http.ClientException('offline')));

      await expectLater(
          store.download(AppFont.sourceHanSans), failsWith(FontDownloadFailure.network));
    });

    test('連線失敗（SocketException）→ network', () async {
      final store = storeWith(MockClient.streaming(
          (request, _) async => throw const SocketException('no route')));

      await expectLater(
          store.download(AppFont.sourceHanSans), failsWith(FontDownloadFailure.network));
    });

    test('無法建立暫存檔（存放目錄下的 v1 被一個檔案佔住）→ storage', () async {
      await fontsDir.create(recursive: true);
      await File(p.join(fontsDir.path, 'v1')).writeAsBytes([0]);
      final store = storeWith(serving({'/v1/A.ttf': fontBytesA}));

      await expectLater(
          store.download(AppFont.sourceHanSans), failsWith(FontDownloadFailure.storage));
    });

    test('已下載時重新下載失敗，不影響既有的正式檔案', () async {
      await fileFor('v1/A.ttf').create(recursive: true);
      await fileFor('v1/A.ttf').writeAsBytes(fontBytesA);
      final corrupted = List<int>.from(fontBytesA)..[0] ^= 0xff;
      final store = storeWith(serving({'/v1/A.ttf': corrupted}));

      await expectLater(
          store.download(AppFont.sourceHanSans), failsWith(FontDownloadFailure.integrity));
      expect(await fileFor('v1/A.ttf').readAsBytes(), fontBytesA);
      expect(await filesIn(fontsDir), ['v1/A.ttf']);
    });

    test('失敗後可以再下載（內部的「下載中」狀態有被重設）', () async {
      var attempts = 0;
      final store = storeWith(MockClient.streaming((request, _) async {
        attempts++;
        if (attempts == 1) throw http.ClientException('offline');
        return http.StreamedResponse(chunked(fontBytesA), 200,
            contentLength: fontBytesA.length);
      }));

      await expectLater(
          store.download(AppFont.sourceHanSans), throwsA(isA<FontDownloadException>()));
      await store.download(AppFont.sourceHanSans);

      expect(await store.installedFonts(), {AppFont.sourceHanSans});
    });
  });

  group('installedFonts／delete／prepare', () {
    test('installedFonts 只看正式檔案是否存在，.part 不算', () async {
      await fileFor('v1/A.ttf').create(recursive: true);
      await File('${fileFor('v1/B.ttf').path}.part').create(recursive: true);
      final store = storeWith(serving({}));

      expect(await store.installedFonts(), {AppFont.sourceHanSans});
    });

    test('delete 後不再列為已下載；刪除不存在的檔案不拋錯', () async {
      await fileFor('v1/A.ttf').create(recursive: true);
      final store = storeWith(serving({}));

      await store.delete(AppFont.sourceHanSans);
      await store.delete(AppFont.sourceHanSerif);

      expect(await store.installedFonts(), isEmpty);
    });

    test('prepare 會建立不存在的存放目錄', () async {
      final store = storeWith(serving({}));

      await store.prepare();

      expect(await fontsDir.exists(), isTrue);
      expect(store.directory, fontsDir.path);
    });

    test('prepare 會刪除殘留的 .part 檔，保留正式檔案', () async {
      await fileFor('v1/A.ttf').create(recursive: true);
      await File('${fileFor('v1/A.ttf').path}.part').create(recursive: true);
      await File('${fileFor('v1/B.ttf').path}.part').create(recursive: true);
      final store = storeWith(serving({}));

      await store.prepare();

      expect(await filesIn(fontsDir), ['v1/A.ttf']);
    });
  });
}
```

- [x] **Step 2：執行測試確認失敗**

Run：`flutter test test/reader/downloadable_font_store_test.dart`
Expected：編譯失敗，找不到 `downloadable_font_store.dart`。

- [x] **Step 3：實作 store**

`lib/reader/downloadable_font_store.dart`：

```dart
import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'app_font.dart';
import 'font_download_catalog.dart';

/// 字型下載失敗的原因（epic-49，spec.md「可下載字型儲存」）。UI 依原因顯示在地化訊息，
/// 本模組不產生任何使用者可見的文字（比照 ADR 0034 的精神）。
/// spec 中的 `http` 在這裡命名為 [httpStatus]，避免和 `package:http` 的匯入前綴撞名。
enum FontDownloadFailure { network, httpStatus, integrity, storage, cancelled }

class FontDownloadException implements Exception {
  const FontDownloadException(this.reason, {this.statusCode});

  final FontDownloadFailure reason;

  /// 只在 [FontDownloadFailure.httpStatus] 時有值。
  final int? statusCode;

  @override
  String toString() =>
      'FontDownloadException(${reason.name}${statusCode == null ? '' : ', HTTP $statusCode'})';
}

/// 取消下載用的旗標。store 每收到一個資料區塊就檢查一次（比照雲端下載的既有做法）。
class FontDownloadCancellationToken {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}

/// 可下載字型的下載與保管（epic-49，見 docs/adr/0035-downloadable-fonts-via-r2-worker.md）。
///
/// 「已下載」只看正式檔案是否存在：下載先寫到 `<正式檔名>.part`，SHA-256 相符才改名，
/// 所以正式檔案存在就代表內容完整，不需要另外用資料表記錄狀態。
class DownloadableFontStore {
  DownloadableFontStore({
    required http.Client httpClient,
    required Directory directory,
    Uri? baseUri,
    FontDownloadSpec Function(AppFont font) specOf = fontDownloadSpecOf,
  })  : _httpClient = httpClient,
        _directory = directory,
        _baseUri = baseUri ?? Uri.parse(kFontDownloadBaseUrl),
        _specOf = specOf;

  final http.Client _httpClient;
  final Directory _directory;
  final Uri _baseUri;
  final FontDownloadSpec Function(AppFont font) _specOf;

  /// 同一時間只允許一個下載（spec「字型管理畫面」與規格審查 I-2）。
  bool _downloading = false;

  /// 存放目錄的絕對路徑，供閱讀器設定 WebView 的串流處理器（Issue 4）。
  String get directory => _directory.path;

  File _fileFor(AppFont font) =>
      File(p.joinAll([_directory.path, ..._specOf(font).publishPath.split('/')]));

  File _partFileFor(AppFont font) => File('${_fileFor(font).path}.part');

  /// App 啟動時呼叫一次：建立存放目錄，並刪除 App 被系統終止時殘留的 `.part` 檔
  /// （這種情況下 dispose 與 finally 都不一定會執行）。呼叫時不可有進行中的下載。
  Future<void> prepare() async {
    await _directory.create(recursive: true);
    await for (final entity in _directory.list(recursive: true)) {
      if (entity is File && entity.path.endsWith('.part')) {
        // 盡力清理：單一檔案刪不掉（被占用、權限異常）就略過，繼續清其他的；
        // 留下的 .part 不影響「已下載」判斷，下次下載前也會先刪除同名暫存檔
        try {
          await entity.delete();
        } on FileSystemException {
          // 略過
        }
      }
    }
  }

  Future<Set<AppFont>> installedFonts() async {
    final installed = <AppFont>{};
    for (final font in AppFont.values) {
      if (await _fileFor(font).exists()) installed.add(font);
    }
    return installed;
  }

  /// 刪除已下載的字型檔；檔案不存在時不視為錯誤。不修改任何書籍偏好（ADR 0035）。
  Future<void> delete(AppFont font) async {
    final file = _fileFor(font);
    if (await file.exists()) await file.delete();
  }

  /// 下載 [font]。[onProgress] 收到 0～100 的整數百分比，只在數值變大時才呼叫
  /// （電子紙裝置重繪代價高，設計審查 I-3）。失敗一律拋出 [FontDownloadException]，
  /// 並且不留下暫存檔、不影響既有的正式檔案。已有下載進行中時拋出 [StateError]。
  Future<void> download(
    AppFont font, {
    void Function(int percent)? onProgress,
    FontDownloadCancellationToken? cancellationToken,
  }) async {
    // 必須在任何 await 之前檢查並設定，才能擋住緊接著的第二次呼叫
    if (_downloading) {
      throw StateError('已有字型下載進行中，不可同時下載兩款字型');
    }
    _downloading = true;
    final spec = _specOf(font);
    final target = _fileFor(font);
    final part = _partFileFor(font);
    IOSink? sink;
    try {
      await _preparePartFile(part);
      final response = await _send(spec);
      if (response.statusCode != 200) {
        throw FontDownloadException(FontDownloadFailure.httpStatus,
            statusCode: response.statusCode);
      }

      final total = response.contentLength ?? spec.sizeBytes;
      final digestSink = _DigestSink();
      final hasher = sha256.startChunkedConversion(digestSink);
      var received = 0;
      var lastPercent = -1;
      try {
        sink = part.openWrite();
        await for (final chunk in response.stream) {
          if (cancellationToken?.isCancelled ?? false) {
            throw const FontDownloadException(FontDownloadFailure.cancelled);
          }
          sink.add(chunk);
          hasher.add(chunk);
          received += chunk.length;
          final percent = total > 0 ? (received * 100 ~/ total).clamp(0, 100) : 0;
          if (percent > lastPercent) {
            lastPercent = percent;
            onProgress?.call(percent);
          }
        }
        await sink.close();
        sink = null;
      } on SocketException {
        throw const FontDownloadException(FontDownloadFailure.network);
      } on http.ClientException {
        throw const FontDownloadException(FontDownloadFailure.network);
      } on FileSystemException {
        throw const FontDownloadException(FontDownloadFailure.storage);
      }

      hasher.close();
      if (digestSink.value.toString() != spec.sha256) {
        throw const FontDownloadException(FontDownloadFailure.integrity);
      }
      if (lastPercent < 100) onProgress?.call(100);
      await _promote(part, target);
    } finally {
      try {
        await sink?.close();
      } catch (_) {
        // 寫入已經失敗時 close 會再拋一次同樣的錯誤；原本的例外已經往上拋，這裡忽略
      }
      if (await part.exists()) await part.delete();
      _downloading = false;
    }
  }

  Future<void> _preparePartFile(File part) async {
    try {
      await part.parent.create(recursive: true);
      if (await part.exists()) await part.delete();
    } on FileSystemException {
      throw const FontDownloadException(FontDownloadFailure.storage);
    }
  }

  Future<http.StreamedResponse> _send(FontDownloadSpec spec) async {
    try {
      return await _httpClient.send(http.Request('GET', _baseUri.resolve(spec.publishPath)));
    } on SocketException {
      throw const FontDownloadException(FontDownloadFailure.network);
    } on http.ClientException {
      throw const FontDownloadException(FontDownloadFailure.network);
    }
  }

  /// 把驗證通過的暫存檔改名為正式檔案。Windows 上 rename 不能覆蓋既有檔案，所以先刪除舊檔。
  Future<void> _promote(File part, File target) async {
    try {
      if (await target.exists()) await target.delete();
      await part.rename(target.path);
    } on FileSystemException {
      throw const FontDownloadException(FontDownloadFailure.storage);
    }
  }
}

/// 接收 [sha256.startChunkedConversion] 的最終結果。
class _DigestSink implements Sink<Digest> {
  late Digest value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}
```

- [x] **Step 4：執行測試確認通過**

Run：`flutter test test/reader/downloadable_font_store_test.dart`
Expected：全數通過。

- [x] **Step 5：Commit**

```bash
git add lib/reader/downloadable_font_store.dart test/reader/downloadable_font_store_test.dart
git commit -m "feat(fonts): 新增 DownloadableFontStore 下載、驗證與啟動準備（epic-49 Issue 3）"
```

---

### Task 3：store 的進度節流、取消、重疊下載防護與中途斷線

**Files:**
- Modify: `test/reader/downloadable_font_store_test.dart`（在 `main()` 最後追加一個 group）
- Modify（僅在測試失敗時）: `lib/reader/downloadable_font_store.dart`

**Interfaces:**
- Consumes：Task 2 的全部公開介面。
- Produces：無新介面；本 Task 以測試鎖定 `download()` 的進度、取消、重疊呼叫行為。

- [x] **Step 1：追加測試**

在 `main()` 內、最後一個 `group` 之後加上：

```dart
  group('進度、取消、重疊下載、中途斷線', () {
    test('大量小區塊時，進度回呼不超過 101 次、嚴格遞增、最後是 100', () async {
      final store = storeWith(serving({'/v1/A.ttf': fontBytesA}, chunkSize: 10));
      final reported = <int>[];

      await store.download(AppFont.sourceHanSans, onProgress: reported.add);

      expect(reported.length, lessThanOrEqualTo(101));
      for (var i = 1; i < reported.length; i++) {
        expect(reported[i], greaterThan(reported[i - 1]));
      }
      expect(reported.last, 100);
    });

    test('伺服器沒回傳 Content-Length 時，用字型目錄中的大小計算進度', () async {
      final store = storeWith(
          serving({'/v1/A.ttf': fontBytesA}, contentLengthOf: (_) => null));
      final reported = <int>[];

      await store.download(AppFont.sourceHanSans, onProgress: reported.add);

      expect(reported, contains(50));
      expect(reported.last, 100);
    });

    test('Content-Length 比實際小時，進度不超過 100 且嚴格遞增，下載仍以雜湊判定成功', () async {
      final store = storeWith(serving({'/v1/A.ttf': fontBytesA},
          contentLengthOf: (bytes) => bytes.length ~/ 2));
      final reported = <int>[];

      await store.download(AppFont.sourceHanSans, onProgress: reported.add);

      expect(reported.every((percent) => percent <= 100), isTrue);
      for (var i = 1; i < reported.length; i++) {
        expect(reported[i], greaterThan(reported[i - 1]));
      }
      expect(await store.installedFonts(), {AppFont.sourceHanSans});
    });

    test('取消 → cancelled，且沒有留下任何檔案', () async {
      final store = storeWith(serving({'/v1/A.ttf': fontBytesA}));
      final token = FontDownloadCancellationToken();

      await expectLater(
        store.download(AppFont.sourceHanSans,
            cancellationToken: token,
            onProgress: (percent) {
              if (percent >= 10) token.cancel();
            }),
        throwsA(isA<FontDownloadException>()
            .having((e) => e.reason, 'reason', FontDownloadFailure.cancelled)),
      );
      expect(await filesIn(fontsDir), isEmpty);
    });

    test('串流中途斷線 → network，且沒有留下任何檔案', () async {
      Stream<List<int>> brokenStream() async* {
        yield fontBytesA.sublist(0, 30000);
        throw http.ClientException('connection reset');
      }
      final store = storeWith(MockClient.streaming((request, _) async =>
          http.StreamedResponse(brokenStream(), 200, contentLength: fontBytesA.length)));

      await expectLater(
        store.download(AppFont.sourceHanSans),
        throwsA(isA<FontDownloadException>()
            .having((e) => e.reason, 'reason', FontDownloadFailure.network)),
      );
      expect(await filesIn(fontsDir), isEmpty);
    });

    test('下載進行中再呼叫 download 拋出 StateError，進行中那一筆照常完成', () async {
      final controller = StreamController<List<int>>();
      final store = storeWith(MockClient.streaming((request, _) async =>
          http.StreamedResponse(controller.stream, 200, contentLength: fontBytesA.length)));

      final first = store.download(AppFont.sourceHanSans);
      await expectLater(
          store.download(AppFont.sourceHanSerif), throwsA(isA<StateError>()));

      controller.add(fontBytesA);
      await controller.close();
      await first;

      expect(await store.installedFonts(), {AppFont.sourceHanSans});
    });
  });
```

- [x] **Step 2：執行測試**

Run：`flutter test test/reader/downloadable_font_store_test.dart`
Expected：全數通過。Task 2 的實作已經涵蓋這些行為；**若有任何一個失敗**，代表 Task 2 的實作與規格不符，依失敗訊息修正 `downloadable_font_store.dart`（不要修改測試的期望值），再執行一次直到全數通過。

- [x] **Step 3：驗證測試真的能抓到錯誤（mutation check）**

暫時把 `download()` 中的 `if (percent > lastPercent)` 改成 `if (true)`，執行 Step 2 的指令，確認「進度回呼不超過 101 次」的測試失敗；再暫時把 `if (_downloading)` 那一段整段註解掉，確認「StateError」的測試失敗。兩處都改回原樣，再執行一次確認全數通過。

- [x] **Step 4：Commit**

```bash
git add test/reader/downloadable_font_store_test.dart lib/reader/downloadable_font_store.dart
git commit -m "test(fonts): 鎖定下載進度節流、取消、重疊下載與中途斷線行為（epic-49 Issue 3）"
```

---

### Task 4：在地化字串

**Files:**
- Modify: `lib/l10n/app_zh_TW.arb`、`lib/l10n/app_zh.arb`、`lib/l10n/app_zh_CN.arb`、`lib/l10n/app_en.arb`
- 重新產生：`lib/l10n/app_localizations.dart`、`app_localizations_zh.dart`、`app_localizations_en.dart`

**Interfaces:**
- Produces（`AppLocalizations` 的新 getter／方法）：
  `fontManagementStatusNotDownloaded`、`fontManagementStatusDownloaded`、`fontManagementDownloadTooltip`、`fontManagementCancelDownloadTooltip`、`fontManagementRetryTooltip`、`fontManagementDownloadableDeleteConfirmMessage`、`fontDownloadErrorNetwork`、`fontDownloadErrorHttp(int statusCode)`、`fontDownloadErrorIntegrity`、`fontDownloadErrorStorage`。

- [x] **Step 1：在 `app_zh_TW.arb`（範本）新增字串**

在 `"@fontManagementDeleteConfirmMessage": { … }` 區塊結束的 `},` 後面插入（注意 JSON 逗號）：

```json
  "fontManagementStatusNotDownloaded": "未下載",
  "@fontManagementStatusNotDownloaded": {
    "description": "字型管理：內建字型尚未下載的狀態文字，接在檔案大小後面（epic-49）"
  },
  "fontManagementStatusDownloaded": "已下載",
  "@fontManagementStatusDownloaded": {
    "description": "字型管理：內建字型已下載的狀態文字，接在檔案大小後面（epic-49）"
  },
  "fontManagementDownloadTooltip": "下載",
  "@fontManagementDownloadTooltip": {
    "description": "字型管理：下載內建字型按鈕的提示文字（epic-49）"
  },
  "fontManagementCancelDownloadTooltip": "取消下載",
  "@fontManagementCancelDownloadTooltip": {
    "description": "字型管理：取消進行中下載按鈕的提示文字（epic-49）"
  },
  "fontManagementRetryTooltip": "重試",
  "@fontManagementRetryTooltip": {
    "description": "字型管理：下載失敗後重試按鈕的提示文字（epic-49）"
  },
  "fontManagementDownloadableDeleteConfirmMessage": "刪除後可以隨時重新下載。使用這款字型的書會暫時改用書本或系統字型，重新下載後自動恢復。",
  "@fontManagementDownloadableDeleteConfirmMessage": {
    "description": "刪除已下載內建字型的確認內文。刻意不沿用自訂字型的 fontManagementDeleteConfirmMessage：可下載字型刪除時不清除書籍偏好（ADR 0035）（epic-49）"
  },
  "fontDownloadErrorNetwork": "無法連線，請檢查網路後重試",
  "@fontDownloadErrorNetwork": {
    "description": "字型下載失敗：網路連線失敗或中途斷線（epic-49）"
  },
  "fontDownloadErrorHttp": "伺服器錯誤（{statusCode}），請稍後重試",
  "@fontDownloadErrorHttp": {
    "description": "字型下載失敗：伺服器回傳非 200 狀態碼，{statusCode} 為 HTTP 狀態碼（epic-49）",
    "placeholders": {
      "statusCode": {
        "type": "int"
      }
    }
  },
  "fontDownloadErrorIntegrity": "檔案不完整或已損毀，請重試",
  "@fontDownloadErrorIntegrity": {
    "description": "字型下載失敗：下載內容的 SHA-256 與預期不符（epic-49）"
  },
  "fontDownloadErrorStorage": "無法儲存檔案，請確認儲存空間是否足夠",
  "@fontDownloadErrorStorage": {
    "description": "字型下載失敗：寫入檔案失敗，例如儲存空間不足（epic-49）"
  },
```

- [x] **Step 2：在其他三個 ARB 檔新增字串**

在各檔 `"fontManagementDeleteConfirmMessage": …` 那一行後面插入（這三個檔案沒有 `@` 描述）。

`app_zh.arb`（與 zh_TW 相同）：

```json
  "fontManagementStatusNotDownloaded": "未下載",
  "fontManagementStatusDownloaded": "已下載",
  "fontManagementDownloadTooltip": "下載",
  "fontManagementCancelDownloadTooltip": "取消下載",
  "fontManagementRetryTooltip": "重試",
  "fontManagementDownloadableDeleteConfirmMessage": "刪除後可以隨時重新下載。使用這款字型的書會暫時改用書本或系統字型，重新下載後自動恢復。",
  "fontDownloadErrorNetwork": "無法連線，請檢查網路後重試",
  "fontDownloadErrorHttp": "伺服器錯誤（{statusCode}），請稍後重試",
  "fontDownloadErrorIntegrity": "檔案不完整或已損毀，請重試",
  "fontDownloadErrorStorage": "無法儲存檔案，請確認儲存空間是否足夠",
```

`app_zh_CN.arb`：

```json
  "fontManagementStatusNotDownloaded": "未下载",
  "fontManagementStatusDownloaded": "已下载",
  "fontManagementDownloadTooltip": "下载",
  "fontManagementCancelDownloadTooltip": "取消下载",
  "fontManagementRetryTooltip": "重试",
  "fontManagementDownloadableDeleteConfirmMessage": "删除后可以随时重新下载。使用这款字体的书会暂时改用书本或系统字体，重新下载后自动恢复。",
  "fontDownloadErrorNetwork": "无法连接，请检查网络后重试",
  "fontDownloadErrorHttp": "服务器错误（{statusCode}），请稍后重试",
  "fontDownloadErrorIntegrity": "文件不完整或已损坏，请重试",
  "fontDownloadErrorStorage": "无法保存文件，请确认存储空间是否足够",
```

`app_en.arb`：

```json
  "fontManagementStatusNotDownloaded": "Not downloaded",
  "fontManagementStatusDownloaded": "Downloaded",
  "fontManagementDownloadTooltip": "Download",
  "fontManagementCancelDownloadTooltip": "Cancel download",
  "fontManagementRetryTooltip": "Retry",
  "fontManagementDownloadableDeleteConfirmMessage": "You can download it again at any time. Books that use this font will use the book's font or the system font until it's downloaded again.",
  "fontDownloadErrorNetwork": "Can't connect. Check your network and try again.",
  "fontDownloadErrorHttp": "Server error ({statusCode}). Try again later.",
  "fontDownloadErrorIntegrity": "The file is incomplete or corrupted. Try again.",
  "fontDownloadErrorStorage": "Couldn't save the file. Check that there's enough storage space.",
```

- [x] **Step 3：產生在地化程式碼**

Run：`flutter gen-l10n`
Expected：沒有錯誤（會印出「To use the command line arguments, delete the l10n.yaml file…」提示，屬正常）。
確認：`grep -n "fontDownloadErrorHttp" lib/l10n/app_localizations_en.dart` 有結果。

- [x] **Step 4：靜態分析**

Run：`flutter analyze`
Expected：`No issues found!`

- [x] **Step 5：Commit**

```bash
git add lib/l10n
git commit -m "feat(l10n): 新增可下載字型的狀態、按鈕與錯誤訊息字串（epic-49 Issue 3）"
```

---

### Task 5：字型管理畫面（四種狀態、下載互斥、刪除確認）

**Files:**
- Create: `test/support/fake_downloadable_font_store.dart`
- Modify: `lib/screens/font_management_screen.dart`
- Test: `test/screens/font_management_screen_test.dart`

**Interfaces:**
- Consumes：Task 1 的 `fontDownloadSpecOf`；Task 2 的 `DownloadableFontStore`、`FontDownloadException`、`FontDownloadFailure`、`FontDownloadCancellationToken`；Task 4 的字串。
- Produces：
  - `FontManagementScreen({required CustomFontsRepository repository, DownloadableFontStore? downloadableFontStore})`
  - `String formatFontFileSize(int bytes)`（頂層函式）
  - 固定的 Key（`<name>` 是 `AppFont.name`，例如 `sourceHanSans`）：
    `font_management_builtin_<name>`（每一列）、`font_management_download_<name>`、`font_management_cancel_download_<name>`、`font_management_retry_<name>`、`font_management_delete_builtin_<name>`；確認對話框沿用 `font_management_delete_cancel`、`font_management_delete_confirm`。
  - 測試用 `FakeDownloadableFontStore`（Issue 4 會用到 `installedFontsGate`）：
    ```dart
    class FakeDownloadableFontStore implements DownloadableFontStore {
      final Set<AppFont> installed; final List<AppFont> deleted;
      FakeFontDownload? activeDownload; Completer<void>? installedFontsGate;
    }
    class FakeFontDownload {
      final AppFont font; final FontDownloadCancellationToken? cancellationToken;
      void progress(int percent); void succeed(); void fail(FontDownloadException error);
    }
    ```

- [x] **Step 1：建立假的 store**

`test/support/fake_downloadable_font_store.dart`：

```dart
import 'dart:async';

import 'package:elinkbook/reader/app_font.dart';
import 'package:elinkbook/reader/downloadable_font_store.dart';

/// 測試用 Fake（epic-49）。下載不會自動完成，由測試透過 [activeDownload]
/// 控制進度、成功或失敗，才能精確驗證畫面在每個階段的顯示。
class FakeDownloadableFontStore implements DownloadableFontStore {
  /// 目前視為已下載的字型；測試可以直接預先設定。
  final Set<AppFont> installed = {};

  /// [delete] 被呼叫過的字型，依呼叫順序。
  final List<AppFont> deleted = [];

  /// 最近一次 [download] 呼叫；沒有呼叫過時為 null。
  FakeFontDownload? activeDownload;

  /// 若非 null，[installedFonts] 會先等待它完成才回傳，供測試控制載入完成的時機
  /// （Issue 4 驗證 ReaderScreen 在已下載字型載入完成前延後建構閱讀器）。
  Completer<void>? installedFontsGate;

  @override
  String get directory => '/fake/downloaded-fonts';

  @override
  Future<void> prepare() async {}

  @override
  Future<Set<AppFont>> installedFonts() async {
    if (installedFontsGate != null) await installedFontsGate!.future;
    return {...installed};
  }

  @override
  Future<void> delete(AppFont font) async {
    installed.remove(font);
    deleted.add(font);
  }

  @override
  Future<void> download(
    AppFont font, {
    void Function(int percent)? onProgress,
    FontDownloadCancellationToken? cancellationToken,
  }) {
    final download = FakeFontDownload(font, onProgress, cancellationToken);
    activeDownload = download;
    return download._completer.future.then((_) => installed.add(font));
  }
}

class FakeFontDownload {
  FakeFontDownload(this.font, this._onProgress, this.cancellationToken);

  final AppFont font;
  final void Function(int percent)? _onProgress;
  final FontDownloadCancellationToken? cancellationToken;
  final Completer<void> _completer = Completer<void>();

  void progress(int percent) => _onProgress?.call(percent);
  void succeed() => _completer.complete();
  void fail(FontDownloadException error) => _completer.completeError(error);
}
```

- [x] **Step 2：寫失敗的 widget 測試**

在 `test/screens/font_management_screen_test.dart`：

1. 檔案開頭補上匯入：

```dart
import 'package:elinkbook/reader/app_font.dart';
import 'package:elinkbook/reader/downloadable_font_store.dart';
import '../support/fake_downloadable_font_store.dart';
```

2. 把既有的 `pumpScreen` 改為可選擇注入 store（其餘既有測試不必修改）：

```dart
  Future<void> pumpScreen(WidgetTester tester,
      {Locale locale = const Locale('zh', 'TW'),
      DownloadableFontStore? store}) async {
    await tester.pumpWidget(MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: FontManagementScreen(
          repository: repository, downloadableFontStore: store),
    ));
    await tester.pumpAndSettle();
  }
```

3. 在 `main()` 最後加上：

```dart
  group('可下載字型（epic-49）', () {
    late FakeDownloadableFontStore store;

    setUp(() => store = FakeDownloadableFontStore());

    IconButton button(WidgetTester tester, String key) =>
        tester.widget<IconButton>(find.byKey(Key(key)));

    Finder subtitleOf(AppFont font, String text) => find.descendant(
        of: find.byKey(Key('font_management_builtin_${font.name}')),
        matching: find.text(text));

    Future<void> startDownload(WidgetTester tester, AppFont font) async {
      await tester.tap(find.byKey(Key('font_management_download_${font.name}')));
      await tester.pump();
    }

    testWidgets('formatFontFileSize 以 MB 顯示到小數點後一位', (tester) async {
      expect(formatFontFileSize(36034016), '34.4 MB');
      expect(formatFontFileSize(59898316), '57.1 MB');
    });

    testWidgets('沒有注入 store 時，內建字型只顯示名稱，沒有下載按鈕', (tester) async {
      await pumpScreen(tester);

      expect(find.text('思源黑體'), findsOneWidget);
      expect(find.byKey(const Key('font_management_download_sourceHanSans')), findsNothing);
    });

    testWidgets('未下載：標題是字型名稱，副標題是大小與「未下載」，下載按鈕可按', (tester) async {
      await pumpScreen(tester, store: store);

      expect(find.text('思源黑體'), findsOneWidget);
      expect(subtitleOf(AppFont.sourceHanSans, '34.4 MB · 未下載'), findsOneWidget);
      expect(subtitleOf(AppFont.sourceHanSerif, '57.1 MB · 未下載'), findsOneWidget);
      expect(button(tester, 'font_management_download_sourceHanSans').onPressed, isNotNull);
    });

    testWidgets('已下載：副標題是大小與「已下載」，顯示刪除按鈕', (tester) async {
      store.installed.add(AppFont.sourceHanSerif);
      await pumpScreen(tester, store: store);

      expect(subtitleOf(AppFont.sourceHanSerif, '57.1 MB · 已下載'), findsOneWidget);
      expect(find.byKey(const Key('font_management_delete_builtin_sourceHanSerif')), findsOneWidget);
      expect(find.byKey(const Key('font_management_download_sourceHanSerif')), findsNothing);
    });

    testWidgets('下載中：顯示進度與取消；其他列的下載、刪除停用；AppBar 上傳仍可按', (tester) async {
      store.installed.add(AppFont.sourceHanSerif);
      await pumpScreen(tester, store: store);

      await startDownload(tester, AppFont.sourceHanSans);
      store.activeDownload!.progress(42);
      await tester.pump();

      expect(find.text('思源黑體'), findsOneWidget);
      expect(subtitleOf(AppFont.sourceHanSans, '42%'), findsOneWidget);
      expect(
          tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator)).value,
          0.42);
      expect(find.byKey(const Key('font_management_cancel_download_sourceHanSans')), findsOneWidget);
      expect(button(tester, 'font_management_delete_builtin_sourceHanSerif').onPressed, isNull);
      expect(button(tester, 'font_management_upload_button').onPressed, isNotNull);
    });

    testWidgets('下載成功後變成已下載，其他列的按鈕恢復可按', (tester) async {
      await pumpScreen(tester, store: store);

      await startDownload(tester, AppFont.sourceHanSans);
      expect(button(tester, 'font_management_download_sourceHanSerif').onPressed, isNull);
      store.activeDownload!.succeed();
      await tester.pumpAndSettle();

      expect(subtitleOf(AppFont.sourceHanSans, '34.4 MB · 已下載'), findsOneWidget);
      expect(button(tester, 'font_management_download_sourceHanSerif').onPressed, isNotNull);
    });

    testWidgets('按取消會取消下載，store 回報 cancelled 後回到未下載且不顯示錯誤', (tester) async {
      await pumpScreen(tester, store: store);

      await startDownload(tester, AppFont.sourceHanSans);
      await tester.tap(find.byKey(const Key('font_management_cancel_download_sourceHanSans')));
      await tester.pump();
      expect(store.activeDownload!.cancellationToken!.isCancelled, isTrue);

      store.activeDownload!
          .fail(const FontDownloadException(FontDownloadFailure.cancelled));
      await tester.pumpAndSettle();

      expect(subtitleOf(AppFont.sourceHanSans, '34.4 MB · 未下載'), findsOneWidget);
      expect(find.byKey(const Key('font_management_retry_sourceHanSans')), findsNothing);
    });

    testWidgets('下載失敗：標題仍是字型名稱，副標題是大小與錯誤訊息，可以重試', (tester) async {
      await pumpScreen(tester, store: store);

      await startDownload(tester, AppFont.sourceHanSans);
      store.activeDownload!
          .fail(const FontDownloadException(FontDownloadFailure.network));
      await tester.pumpAndSettle();

      expect(find.text('思源黑體'), findsOneWidget);
      expect(subtitleOf(AppFont.sourceHanSans, '34.4 MB · 無法連線，請檢查網路後重試'), findsOneWidget);

      await tester.tap(find.byKey(const Key('font_management_retry_sourceHanSans')));
      await tester.pump();
      expect(store.activeDownload!.font, AppFont.sourceHanSans);
      expect(find.byKey(const Key('font_management_cancel_download_sourceHanSans')), findsOneWidget);
    });

    testWidgets('各種失敗原因顯示對應訊息（HTTP 狀態碼、檔案損毀、無法儲存）', (tester) async {
      await pumpScreen(tester, store: store);
      const cases = {
        FontDownloadException(FontDownloadFailure.httpStatus, statusCode: 503):
            '34.4 MB · 伺服器錯誤（503），請稍後重試',
        FontDownloadException(FontDownloadFailure.integrity): '34.4 MB · 檔案不完整或已損毀，請重試',
        FontDownloadException(FontDownloadFailure.storage): '34.4 MB · 無法儲存檔案，請確認儲存空間是否足夠',
      };
      for (final entry in cases.entries) {
        final retry = find.byKey(const Key('font_management_retry_sourceHanSans'));
        await tester.tap(retry.evaluate().isEmpty
            ? find.byKey(const Key('font_management_download_sourceHanSans'))
            : retry);
        await tester.pump();
        store.activeDownload!.fail(entry.key);
        await tester.pumpAndSettle();
        expect(subtitleOf(AppFont.sourceHanSans, entry.value), findsOneWidget);
      }
    });

    testWidgets('另一款字型下載中時，失敗列的重試停用', (tester) async {
      await pumpScreen(tester, store: store);
      await startDownload(tester, AppFont.sourceHanSans);
      store.activeDownload!
          .fail(const FontDownloadException(FontDownloadFailure.network));
      await tester.pumpAndSettle();

      await startDownload(tester, AppFont.sourceHanSerif);

      expect(button(tester, 'font_management_retry_sourceHanSans').onPressed, isNull);
    });

    testWidgets('刪除確認對話框使用可下載字型專屬內文；取消不刪、確認才刪', (tester) async {
      store.installed.add(AppFont.sourceHanSans);
      await pumpScreen(tester, store: store);

      await tester.tap(find.byKey(const Key('font_management_delete_builtin_sourceHanSans')));
      await tester.pumpAndSettle();
      expect(find.text('確定要刪除「思源黑體」嗎？'), findsOneWidget);
      expect(find.text('刪除後可以隨時重新下載。使用這款字型的書會暫時改用書本或系統字型，重新下載後自動恢復。'),
          findsOneWidget);
      await tester.tap(find.byKey(const Key('font_management_delete_cancel')));
      await tester.pumpAndSettle();
      expect(store.deleted, isEmpty);

      await tester.tap(find.byKey(const Key('font_management_delete_builtin_sourceHanSans')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('font_management_delete_confirm')));
      await tester.pumpAndSettle();

      expect(store.deleted, [AppFont.sourceHanSans]);
      expect(subtitleOf(AppFont.sourceHanSans, '34.4 MB · 未下載'), findsOneWidget);
    });

    testWidgets('離開畫面時取消進行中的下載；之後下載才結束也不拋例外', (tester) async {
      await pumpScreen(tester, store: store);
      await startDownload(tester, AppFont.sourceHanSans);

      await tester.pumpWidget(const SizedBox());
      expect(store.activeDownload!.cancellationToken!.isCancelled, isTrue);

      store.activeDownload!
          .fail(const FontDownloadException(FontDownloadFailure.cancelled));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('英文介面：字型名稱與狀態以英文顯示', (tester) async {
      await pumpScreen(tester, store: store, locale: const Locale('en'));

      expect(find.text('Source Han Sans'), findsOneWidget);
      expect(subtitleOf(AppFont.sourceHanSans, '34.4 MB · Not downloaded'), findsOneWidget);
    });
  });
```

- [x] **Step 3：執行測試確認失敗**

Run：`flutter test test/screens/font_management_screen_test.dart`
Expected：編譯失敗：`FontManagementScreen` 沒有 `downloadableFontStore` 參數、找不到 `formatFontFileSize`。

- [x] **Step 4：修改 `font_management_screen.dart`**

1. 補上匯入：

```dart
import '../reader/downloadable_font_store.dart';
import '../reader/font_download_catalog.dart';
```

2. 修改 widget 本體（新增可選參數，並更新類別註解）：

```dart
/// 字型管理畫面（epic-14-system-settings FR-35，spec.md「字型管理模組」）：
/// 顯示內建字型＋使用者上傳的自訂字型（可重新命名／刪除），支援批次上傳 `.ttf`/`.otf`。
/// epic-49 起內建字型改為可下載字型：注入 [downloadableFontStore] 時，每款內建字型
/// 可以下載、取消、重試、刪除；沒有注入時只顯示名稱（維持既有行為）。
class FontManagementScreen extends StatefulWidget {
  final CustomFontsRepository repository;
  final DownloadableFontStore? downloadableFontStore;

  const FontManagementScreen({
    super.key,
    required this.repository,
    this.downloadableFontStore,
  });
```

3. 在 `_FontManagementScreenState` 的欄位區（`TextEditingController? _renameController;` 之後）加上：

```dart
  // ── 可下載字型（epic-49）──
  Set<AppFont> _installedFonts = {};

  /// 正在下載的字型；同一時間最多一款（下載中時其他內建字型的按鈕全部停用）。
  AppFont? _downloadingFont;
  int _downloadPercent = 0;
  FontDownloadCancellationToken? _downloadToken;

  /// 最近一次下載失敗的字型與原因；重新下載或下載成功時清除。取消不算失敗。
  final Map<AppFont, FontDownloadException> _downloadFailures = {};
```

4. 修改 `initState` 與 `dispose`：

```dart
  @override
  void initState() {
    super.initState();
    _loadFonts();
    _loadInstalledFonts();
  }

  @override
  void dispose() {
    // 不做背景下載：離開畫面就取消（spec「字型管理畫面」、design.md Q9）
    _downloadToken?.cancel();
    _renameController?.dispose();
    super.dispose();
  }
```

5. 在 `_loadFonts()` 後面新增：

```dart
  Future<void> _loadInstalledFonts() async {
    final store = widget.downloadableFontStore;
    if (store == null) return;
    try {
      final installed = await store.installedFonts();
      if (!mounted) return;
      setState(() => _installedFonts = installed);
    } catch (e) {
      debugPrint('Failed to load downloaded fonts: $e');
    }
  }
```

6. 在 `build()` 中，把：

```dart
          for (final font in AppFont.values)
            ListTile(title: Text(font.displayName(l10n))),
```

改為：

```dart
          for (final font in AppFont.values) _buildBuiltInFontTile(font, l10n),
```

7. 在 `build()` 之後新增：

```dart
  /// 內建字型的一列：標題固定是字型名稱，副標題依狀態顯示大小、進度或錯誤訊息
  /// （規格審查 M-2：任何狀態都看得出是哪一款字型）。
  Widget _buildBuiltInFontTile(AppFont font, AppLocalizations l10n) {
    final title = Text(font.displayName(l10n));
    if (widget.downloadableFontStore == null) return ListTile(title: title);

    final key = Key('font_management_builtin_${font.name}');
    final size = formatFontFileSize(fontDownloadSpecOf(font).sizeBytes);
    // 任何字型下載中時，其他所有內建字型的下載／重試／刪除都停用（規格審查 I-2）
    final isBusy = _downloadingFont != null;

    if (_downloadingFont == font) {
      return ListTile(
        key: key,
        title: title,
        subtitle: Row(
          children: [
            Expanded(child: LinearProgressIndicator(value: _downloadPercent / 100)),
            const SizedBox(width: 8),
            Text('$_downloadPercent%'),
          ],
        ),
        trailing: IconButton(
          key: Key('font_management_cancel_download_${font.name}'),
          icon: const Icon(Icons.close),
          tooltip: l10n.fontManagementCancelDownloadTooltip,
          onPressed: () => _downloadToken?.cancel(),
        ),
      );
    }

    if (_installedFonts.contains(font)) {
      return ListTile(
        key: key,
        title: title,
        subtitle: Text('$size · ${l10n.fontManagementStatusDownloaded}'),
        trailing: IconButton(
          key: Key('font_management_delete_builtin_${font.name}'),
          icon: const Icon(Icons.delete),
          tooltip: l10n.fontManagementDeleteTooltip,
          onPressed: isBusy ? null : () => _deleteDownloadedFont(font),
        ),
      );
    }

    final failure = _downloadFailures[font];
    if (failure != null) {
      return ListTile(
        key: key,
        title: title,
        subtitle: Text('$size · ${_downloadFailureMessage(failure, l10n)}'),
        trailing: IconButton(
          key: Key('font_management_retry_${font.name}'),
          icon: const Icon(Icons.refresh),
          tooltip: l10n.fontManagementRetryTooltip,
          onPressed: isBusy ? null : () => _downloadFont(font),
        ),
      );
    }

    return ListTile(
      key: key,
      title: title,
      subtitle: Text('$size · ${l10n.fontManagementStatusNotDownloaded}'),
      trailing: IconButton(
        key: Key('font_management_download_${font.name}'),
        icon: const Icon(Icons.download),
        tooltip: l10n.fontManagementDownloadTooltip,
        onPressed: isBusy ? null : () => _downloadFont(font),
      ),
    );
  }

  String _downloadFailureMessage(FontDownloadException error, AppLocalizations l10n) {
    switch (error.reason) {
      case FontDownloadFailure.network:
        return l10n.fontDownloadErrorNetwork;
      case FontDownloadFailure.httpStatus:
        return l10n.fontDownloadErrorHttp(error.statusCode ?? 0);
      case FontDownloadFailure.integrity:
        return l10n.fontDownloadErrorIntegrity;
      case FontDownloadFailure.storage:
        return l10n.fontDownloadErrorStorage;
      case FontDownloadFailure.cancelled:
        // 取消不會記錄成失敗（見 _downloadFont），這裡只是讓 switch 完整
        return '';
    }
  }

  Future<void> _downloadFont(AppFont font) async {
    final token = FontDownloadCancellationToken();
    setState(() {
      _downloadingFont = font;
      _downloadPercent = 0;
      _downloadToken = token;
      _downloadFailures.remove(font);
    });
    try {
      await widget.downloadableFontStore!.download(
        font,
        cancellationToken: token,
        // store 已經節流成「整數百分比變大才回報」，這裡每次回報都重繪即可
        onProgress: (percent) {
          if (mounted) setState(() => _downloadPercent = percent);
        },
      );
      if (!mounted) return;
      setState(() => _installedFonts = {..._installedFonts, font});
    } on FontDownloadException catch (error) {
      if (!mounted || error.reason == FontDownloadFailure.cancelled) return;
      setState(() => _downloadFailures[font] = error);
    } finally {
      if (mounted) {
        setState(() {
          _downloadingFont = null;
          _downloadToken = null;
        });
      }
    }
  }

  Future<void> _deleteDownloadedFont(AppFont font) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.fontManagementDeleteConfirmTitle(font.displayName(l10n))),
        // 刻意不用 fontManagementDeleteConfirmMessage：可下載字型刪除時不清除書籍偏好
        // （ADR 0035），也不查詢使用中的書籍數量（規格審查 I-4）
        content: Text(l10n.fontManagementDownloadableDeleteConfirmMessage),
        actions: [
          TextButton(
            key: const Key('font_management_delete_cancel'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            key: const Key('font_management_delete_confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.fontManagementDeleteTooltip),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.downloadableFontStore!.delete(font);
    if (!mounted) return;
    setState(() => _installedFonts = {..._installedFonts}..remove(font));
  }
```

8. 在檔案最後（`_stripExtension` 之後）新增：

```dart
/// 字型檔大小的顯示格式，例如 36034016 → `34.4 MB`。以 1024 × 1024 為 1 MB
/// （實際是 MiB，但沿用一般人熟悉的「MB」標示），數值對齊 spec 字型目錄。
/// MB 在三種語系寫法相同，所以不另外做在地化字串（epic-49）。
String formatFontFileSize(int bytes) =>
    '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
```

9. 上傳自訂字型時的家族名稱衝突檢查（`_pickAndUploadFonts` 內的 `AppFont.values.map(...)` 那段）**不修改**。

- [x] **Step 5：執行測試確認通過**

Run：`flutter test test/screens/font_management_screen_test.dart`
Expected：全數通過（含既有測試）。

- [x] **Step 6：驗證測試真的能抓到錯誤（mutation check）**

暫時把 `_buildBuiltInFontTile` 中「已下載」那一段刪除按鈕的 `onPressed: isBusy ? null : …` 改成永遠可按（`onPressed: () => _deleteDownloadedFont(font)`），執行 Step 5，確認「下載中…其他列的下載、刪除停用」測試失敗；改回原樣後再執行一次確認通過。

- [x] **Step 7：l10n 稽核**

Run：`node tool/check_l10n_hardcoded_strings.js`
Expected：兩行 `PASS`。

- [x] **Step 8：Commit**

```bash
git add lib/screens/font_management_screen.dart test/screens/font_management_screen_test.dart test/support/fake_downloadable_font_store.dart
git commit -m "feat(fonts): 字型管理畫面支援下載、取消、重試與刪除內建字型（epic-49 Issue 3）"
```

---

### Task 6：依賴注入（`main.dart` → 設定頁 → 字型管理畫面）

**Files:**
- Modify: `lib/main.dart`、`lib/screens/library_screen_dependencies.dart`、`lib/screens/adaptive_shell_scaffold.dart`、`lib/screens/settings_scaffold.dart`
- Test: `test/screens/settings_scaffold_test.dart`

**Interfaces:**
- Consumes：Task 2 的 `DownloadableFontStore`、Task 5 的 `FontManagementScreen(downloadableFontStore:)`、`FakeDownloadableFontStore`。
- Produces（Issue 4 會沿用同一條路徑傳給 `ReaderScreen`）：
  - `ElinkBookApp({..., DownloadableFontStore? downloadableFontStore})`
  - `LibraryReaderFeatureRepositories({..., DownloadableFontStore? downloadableFontStore})`，欄位 `final DownloadableFontStore? downloadableFontStore;`
  - `SettingsScaffold({..., DownloadableFontStore? downloadableFontStore})`

- [x] **Step 1：寫失敗的測試**

在 `test/screens/settings_scaffold_test.dart` 補上匯入（已有的就略過）：

```dart
import '../support/fake_custom_fonts_repository.dart';
import '../support/fake_downloadable_font_store.dart';
```

並在 `main()` 最後加上：

```dart
  testWidgets('字型管理入口把 downloadableFontStore 傳給字型管理畫面（epic-49）', (tester) async {
    await pumpLocalizedWidget(
      tester,
      SettingsScaffold(
        prefsManager: FakeReaderPrefsManager(),
        customFontsRepository: FakeCustomFontsRepository(),
        downloadableFontStore: FakeDownloadableFontStore(),
      ),
    );

    final entry = find.byKey(const Key('settings_font_management_button'));
    await tester.ensureVisible(entry);
    await tester.tap(entry);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('font_management_download_sourceHanSans')), findsOneWidget);
  });
```

- [x] **Step 2：執行測試確認失敗**

Run：`flutter test test/screens/settings_scaffold_test.dart`
Expected：編譯失敗，`SettingsScaffold` 沒有 `downloadableFontStore` 參數。

- [x] **Step 3：`settings_scaffold.dart` 新增參數並傳下去**

- 匯入：`import '../reader/downloadable_font_store.dart';`
- 欄位（放在 `final CustomFontsRepository? customFontsRepository;` 之後）：

```dart
  /// epic-49：可下載字型的下載與保管；null 時字型管理畫面的內建字型只顯示名稱。
  final DownloadableFontStore? downloadableFontStore;
```

- 建構子（放在 `this.customFontsRepository,` 之後）：`this.downloadableFontStore,`
- 開啟字型管理畫面處改為：

```dart
                          builder: (context) => FontManagementScreen(
                            repository: widget.customFontsRepository!,
                            downloadableFontStore: widget.downloadableFontStore,
                          ),
```

- [x] **Step 4：`library_screen_dependencies.dart` 新增欄位**

在 `LibraryReaderFeatureRepositories`：
- 匯入：`import '../reader/downloadable_font_store.dart';`
- 欄位（放在 `final CustomFontsRepository? customFontsRepository;` 之後）：

```dart
  /// epic-49：可下載字型的下載與保管。本 Issue 只傳給設定頁的字型管理畫面，
  /// Issue 4 會再傳給 ReaderScreen。
  final DownloadableFontStore? downloadableFontStore;
```

- 建構子（放在 `this.customFontsRepository,` 之後）：`this.downloadableFontStore,`

- [x] **Step 5：`adaptive_shell_scaffold.dart` 傳給 `SettingsScaffold`**

在 `SettingsScaffold(` 的參數中，`customFontsRepository: …` 之後加上：

```dart
              downloadableFontStore:
                  widget.readerFeatureRepositories.downloadableFontStore,
```

- [x] **Step 6：`main.dart` 建構 store、啟動準備、傳給 `ElinkBookApp`**

- 匯入：
  ```dart
  import 'package:http/http.dart' as http;
  import 'reader/downloadable_font_store.dart';
  ```
- 在 `final customFontsRepository = CustomFontsRepository(repository.database);` 之後加上：

```dart
  // epic-49：內建字型改為可下載字型，存在 App 支援目錄（非使用者可見、清除快取不會被刪）。
  // prepare() 建立存放目錄並清掉上次被系統終止時殘留的 .part 暫存檔；
  // 失敗只影響字型下載功能，不能擋住 App 啟動。
  final downloadableFontStore = DownloadableFontStore(
    httpClient: http.Client(),
    directory: Directory(
        p.join((await getApplicationSupportDirectory()).path, 'downloaded-fonts')),
  );
  try {
    await downloadableFontStore.prepare();
  } catch (e) {
    debugPrint('Failed to prepare downloaded fonts directory: $e');
  }
```

- `runApp(ElinkBookApp(…))` 參數中，`customFontsRepository: customFontsRepository,` 之後加上 `downloadableFontStore: downloadableFontStore,`
- `ElinkBookApp` 類別：欄位 `final DownloadableFontStore? downloadableFontStore;`（放在 `customFontsRepository` 欄位之後）、建構子 `this.downloadableFontStore,`（放在 `this.customFontsRepository,` 之後）。
- `LibraryReaderFeatureRepositories(` 的參數中，`customFontsRepository: widget.customFontsRepository,` 之後加上 `downloadableFontStore: widget.downloadableFontStore,`

- [x] **Step 7：執行測試確認通過**

Run：`flutter test test/screens/settings_scaffold_test.dart test/screens/font_management_screen_test.dart`
Expected：全數通過。

- [x] **Step 8：靜態分析**

Run：`flutter analyze`
Expected：`No issues found!`

- [x] **Step 9：Commit**

```bash
git add lib/main.dart lib/screens/library_screen_dependencies.dart lib/screens/adaptive_shell_scaffold.dart lib/screens/settings_scaffold.dart test/screens/settings_scaffold_test.dart
git commit -m "feat(fonts): 由 main.dart 建構 DownloadableFontStore 並傳到字型管理畫面（epic-49 Issue 3）"
```

---

### Task 7：整體驗證與進度記錄

**Files:**
- Modify: `docs/epics/epic-49-downloadable-fonts/issues.md`（Issue 3 的 `Status`）、`docs/epics/epic-49-downloadable-fonts/epic.md`、`docs/epics.md`（第 50 列備註）

- [x] **Step 1：本 Issue 所有異動測試**

```bash
flutter test test/reader/font_download_catalog_test.dart test/reader/downloadable_font_store_test.dart test/screens/font_management_screen_test.dart test/screens/settings_scaffold_test.dart
```

Expected：全數通過。

- [x] **Step 2：靜態分析與 l10n 稽核**

```bash
flutter analyze
node tool/check_l10n_hardcoded_strings.js
```

Expected：`No issues found!`；兩行 `PASS`。

- [x] **Step 3：完整測試套件（本計畫唯一一次）**

Run：`flutter test`
Expected：`All tests passed!`（約 5 分鐘）。有失敗時，先確認是否為本 Issue 造成；是的話修正後只重跑失敗的測試檔，再重跑一次完整套件。

- [x] **Step 4：更新進度**

- `issues.md` Issue 3 的 `**Status:**` 改為 `completed`。
- `epic.md` 追加「Issue 3 完成」記錄：新增的模組、測試數量、完整套件結果與 commit。
- `docs/epics.md` 第 50 列備註改為最後完成的 Issue 編號（例如「Issue 3 已完成」；若 Issue 1 也已完成，寫「Issue 1、3 已完成」）。

- [x] **Step 5：Commit**

```bash
git add docs/epics.md docs/epics/epic-49-downloadable-fonts/issues.md docs/epics/epic-49-downloadable-fonts/epic.md
git commit -m "docs(epic-49): 記錄 Issue 3 完成"
```
