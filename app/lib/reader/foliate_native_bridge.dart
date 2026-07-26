import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show MethodChannel, rootBundle;
import 'package:path_provider/path_provider.dart';

import 'app_font.dart';
import 'foliate_bridge_codec.dart';

const _readerResourcesChannel = MethodChannel('elinkbook/reader_resources');

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
String buildFontFaceCss() {
  final rules = <String>[];
  for (final font in AppFont.values) {
    final familyName = font.familyName;
    final fileName = _fontFileName(font);
    rules.add("@font-face { font-family: '$familyName'; "
        "src: url('https://appassets.androidplatform.net/assets/fonts/$fileName'); }");
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

/// 讀取待開啟的 EPUB 檔案本體位元組，供 `InAppWebView.shouldInterceptRequest`
/// 服務 `main.js` `makeBook()` 對 `/book/current.epub` 的一次性 fetch（已
/// 查證 `view.js` 原始碼確認一次性讀取整份內容、不發 HTTP Range 請求，見
/// 原 Kotlin `FoliateEpubReaderView.kt BookPathHandler` 註解）。[filePath]
/// 依 ADR 0002 可能是真實檔案系統路徑或 `content://` URI（`"://"` 啟發式
/// 判斷，比照既有慣例）：
/// - `content://` URI：透過 Task 2 的原生 `ContentResolver` 橋接讀取，
///   Android SAF 權限模型本身把關存取範圍，不做額外路徑檢查（比照原
///   Kotlin `openBook()` 對 `content://` 分支的既有信任層級）。
/// - 真實檔案路徑：先確認檔案存在，再用 [File.resolveSymbolicLinksSync]
///   取得已解析符號連結的絕對路徑，透過 [isPathWithinRoot] 驗證落在 App
///   私有資料目錄範圍內（`getApplicationDocumentsDirectory()` 的父目錄，
///   同時涵蓋 `files/`／`cache/`／`app_flutter/`，比照原
///   `FoliatePathValidator` 呼叫端的既有範圍定義），不在範圍內則回傳
///   `null`。
Future<Uint8List?> loadBookBytes(String filePath) async {
  if (filePath.contains('://')) {
    return _readerResourcesChannel
        .invokeMethod<Uint8List>('readContentUri', {'uri': filePath});
  }
  final file = File(filePath);
  if (!await file.exists()) return null;
  final canonicalPath = file.resolveSymbolicLinksSync();
  final docsDir = await getApplicationDocumentsDirectory();
  final allowedRoot = Directory(docsDir.path).parent.path;
  if (!isPathWithinRoot(canonicalPath, allowedRoot)) return null;
  return file.readAsBytes();
}
