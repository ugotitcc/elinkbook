import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show MethodChannel, rootBundle;
import 'package:path_provider/path_provider.dart';

import 'app_font.dart';
import 'custom_font.dart';
import 'foliate_bridge_codec.dart';

const _readerResourcesChannel = MethodChannel('elinkbook/reader_resources');

/// 背景執行緒的 method channel，處理 `cacheBookForServing`。
/// 217MB 檔案複製可能耗時數秒，透過 `BinaryMessenger.makeBackgroundTaskQueue()`
/// 在背景執行緒執行，不阻塞 Android 主執行緒（避免 ANR）。
const _readerResourcesCacheChannel =
    MethodChannel('elinkbook/reader_resources_cache');

/// 供 [attachReaderView]/[detachReaderView] 重用既有的
/// `elinkbook/volume_key` 通道（MainActivity.kt 既有的音量鍵事件通道，見
/// docs/epics/epic-18-reader-device-qa/plans/plan-issue-10.md Task 2）——
/// MethodChannel 物件本身只是依名稱字串指向同一條平台通道的輕量代理，
/// 與 `app/lib/screens/reader_screen.dart` 內私有的同名 `_volumeKeyChannel`
/// 是兩個各自獨立、但指向同一條原生通道的物件實例，皆可正常運作。
const _volumeKeyChannel = MethodChannel('elinkbook/volume_key');

/// 各 [AppFont] 列舉值對應的字型檔名（`app/assets/fonts/` 底下的實際檔
/// 名，`pubspec.yaml` 已宣告）。審查修正（DRY）：家族名稱字串不再於本
/// 檔案重複硬編碼一份，改重用 `app_font.dart` 既有的
/// `AppFontFamilyName.familyName`——本函式只保留「檔名」這一半確實找不到
/// 其他集中定義處的映射，且用 `switch` 而非 `Map<String, String>` 是刻意
/// 選擇：新增 [AppFont] 列舉值時，`switch` 缺少對應分支會直接編譯錯誤
/// （dart 的 exhaustiveness 檢查），比純字串 key 的 map 更難悄悄遺漏。
String _fontFileName(AppFont font) {
  switch (font) {
    case AppFont.sourceHanSans:
      return 'SourceHanSansTC-VF.ttf';
    case AppFont.sourceHanSerif:
      return 'SourceHanSerifTC-VF.ttf';
    case AppFont.guanKiapTsingKhai:
      return 'GuanKiapTsingKhai.ttf';
    case AppFont.taiwanPearl:
      return 'TaiwanPearl-Regular.ttf';
    case AppFont.genRyuMinTW:
      return 'GenRyuMinTW-Regular.ttf';
  }
}

/// 產生固定的 5 款內建字型 @font-face 宣告（FR-09），取代原本 Kotlin
/// `FoliateEpubReaderView.kt buildFontFaceCss()`。字型檔案本身是 Flutter
/// assets（`pubspec.yaml` 已宣告，見 [loadFlutterFontAsset]），故不需要
/// 透過 `FlutterInjector` 查找 Android AssetManager 的 lookup key——直接
/// 用固定虛擬路徑 `https://appassets.androidplatform.net/assets/fonts/...`，
/// 由 `InAppWebView.shouldInterceptRequest`（`foliate_epub_reader_view.dart`）
/// 攔截後呼叫 [loadFlutterFontAsset] 提供位元組。家族名稱字串直接取自
/// `AppFontFamilyName.familyName`（見 [_fontFileName] 註解），與
/// `app/lib/reader/app_font.dart` 保持單一事實來源，不重複維護。
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

/// 讀取 `app/android/app/src/main/assets/foliate/` 底下的 `foliate-js`
/// 靜態檔案位元組（[relativePath] 例如 `'foliate/main.js'`），透過 Task 2
/// 新增的原生 `ReaderResourceChannel` 讀取（Flutter `rootBundle` 讀不到
/// Android 原生 assets 目錄，見本檔案頂部 import 區塊的架構說明）。找不到
/// 該檔案（例如 `view.js` 動態 import 但實際不存在的
/// `vendor/fflate.js`——已知既有情況，非本次遷移引入）時回傳 `null`。
Future<Uint8List?> loadAndroidAsset(String relativePath) {
  return _readerResourcesChannel
      .invokeMethod<Uint8List>('readAndroidAsset', {'path': relativePath});
}

/// 通知原生端「目前有一個流式 EPUB 的 InAppWebView 已建立」，取代原本
/// `FoliateEpubReaderView.kt` `init {}` 呼叫 `ReaderViewAttachmentTracker.attach()`
/// （epic-7-interaction Issue 7 音量鍵攔截依據）。呼叫時機：
/// `foliate_epub_reader_view.dart` 的 `onWebViewCreated` 回呼內。
Future<void> attachReaderView() =>
    _volumeKeyChannel.invokeMethod('attachReaderView');

/// 對稱 [attachReaderView]，取代原本 `FoliateEpubReaderView.kt dispose()`
/// 呼叫 `ReaderViewAttachmentTracker.detach()`。呼叫時機：
/// `_FoliateEpubReaderViewState.dispose()`。
Future<void> detachReaderView() =>
    _volumeKeyChannel.invokeMethod('detachReaderView');

/// 讀取 Flutter 已宣告的字型 asset（`pubspec.yaml` `assets:` 清單），供
/// `InAppWebView.shouldInterceptRequest` 服務 [buildFontFaceCss] 產生的
/// `@font-face src` 請求。
Future<Uint8List?> loadFlutterFontAsset(String assetPath) async {
  try {
    final data = await rootBundle.load(assetPath);
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } catch (_) {
    return null;
  }
}

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

/// 將 EPUB 檔案分塊複製到每個 widget 實例獨立的快取子目錄，
/// 供 `WebViewAssetLoader.InternalStoragePathHandler` 串流服務。
/// [filePath] 依 ADR 0002 可能是真實檔案系統路徑或 `content://` URI；
/// [instanceId] 由呼叫端產生的實例唯一 ID，用於區隔快取子目錄。
/// 回傳快取檔案的絕對路徑，失敗回傳 null。
///
/// 使用頂層函數變數（非直接函數宣告），以便測試環境可以透過
/// 直接覆寫此變數來注入 mock，完全繞過 Dart 端的檔案系統檢查
/// （`File.exists()`、`resolveSymbolicLinksSync()` 等），避免
/// `flutter test` 無法模擬原生檔案操作導致 mock 失效。
Future<String?> Function(String filePath, String instanceId) cacheBookForServing =
    _defaultCacheBookForServing;

Future<String?> _defaultCacheBookForServing(String filePath, String instanceId) async {
  if (filePath.contains('://')) {
    return _readerResourcesCacheChannel.invokeMethod<String>(
        'cacheBookForServing', {'uri': filePath, 'instanceId': instanceId});
  }
  final file = File(filePath);
  final exists = await file.exists();
  if (!exists) return null;
  final canonicalPath = file.resolveSymbolicLinksSync();
  final docsDir = await getApplicationDocumentsDirectory();
  final parentDir = Directory(docsDir.path).parent;
  // Android 上 `/data/user/0` 是指向 `/data/data` 的 symlink，若不解析
  // allowedRoot 的 symlink，`isPathWithinRoot` 會因兩側路徑不一致而誤判
  // 合法檔案為「超出允許範圍」（見 Issue 8 整合測試失敗診斷）。
  String allowedRoot;
  try {
    allowedRoot = parentDir.resolveSymbolicLinksSync();
  } catch (e) {
    allowedRoot = parentDir.path;
  }
  final withinRoot = isPathWithinRoot(canonicalPath, allowedRoot);
  if (!withinRoot) return null;
  return _readerResourcesCacheChannel.invokeMethod<String>(
      'cacheBookForServing', {'filePath': canonicalPath, 'instanceId': instanceId});
}
