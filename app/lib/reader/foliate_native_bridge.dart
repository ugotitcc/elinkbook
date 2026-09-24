import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show MethodChannel, rootBundle;
import 'package:path/path.dart' as p;
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

/// 依 [filePath] 副檔名推導 WebView 快取檔名應使用的副檔名（不含點號，
/// 小寫），供 [cacheBookForServing] 決定原生端快取檔名、[FoliateReaderView]
/// 決定要 fetch 的檔名（epic-11-multi-format-reader Issue 3）。CBZ 依賴
/// `readest/foliate-js` 的 `isCBZ()` 對「檔名副檔名／MIME type」做格式
/// 自動偵測（見 view.js 原始碼）；若快取檔名恆為 `current.epub`（Issue 3
/// 之前的既有寫死行為，KF8/MOBI 靠 magic bytes 偵測不受影響、EPUB 本身
/// 就是 .epub 無影響），CBZ 會被誤判為 EPUB 而開書失敗——本函式讓快取
/// 檔名與副檔名判斷都反映書籍真實格式。無法識別副檔名（例如不含副檔名的
/// `content://` URI）時退回 'epub'，維持 Issue 3 之前對 EPUB／AZW3 的既有
/// 行為不變（AZW3 走 magic bytes 偵測，副檔名判斷結果對它而言其實不影響
/// 正確性，僅影響快取檔名字面值）。
String cacheFileExtension(String filePath) {
  final ext = p.extension(filePath);
  return ext.isEmpty ? 'epub' : ext.substring(1).toLowerCase();
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
  final extension = cacheFileExtension(filePath);
  if (filePath.contains('://')) {
    return _readerResourcesCacheChannel.invokeMethod<String>(
        'cacheBookForServing', {'uri': filePath, 'instanceId': instanceId, 'extension': extension});
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
      'cacheBookForServing', {'filePath': canonicalPath, 'instanceId': instanceId, 'extension': extension});
}

/// 【診斷修正——真機回報：Mobiscribe WAVE（Android 12，
/// `com.android.webview` 版本 91.0.4472.114）開啟流式 EPUB 時畫面永遠停在
/// 轉圈圈載入指示器，且沒有任何可觀察的例外/console 訊息（這台裝置的
/// WebView 建置沒有開啟 `setWebContentsDebuggingEnabled`，無法遠端連接
/// DevTools 檢視實際拋出的例外）】`epub.js`／`epubcfi.js`／`paginator.js`
/// （`readest/foliate-js` 釘定版本）在開書必經路徑（`loadItem()`／
/// `loadReplaced()` 讀取 spine 資源、`paginator.js` 分頁計算）無條件使用
/// 三個較新的 ES 內建方法，較舊的 Android System WebView 統統沒有：
///
/// - `Object.groupBy`／`Map.groupBy`（ES2024，需 Chromium 117+）
/// - `Array.prototype.at()`（ES2022，需 Chromium 92+）
/// - `Array.prototype.findLastIndex()`（ES2023，需 Chromium 97+）
///
/// 這台裝置的 Chromium 91（已用 `dumpsys package com.android.webview` 與
/// `adb logcat` 的 `cr_LibraryLoader` 訊息雙重確認版本號）三個都不支援；
/// `Object.groupBy` 那部分已在前一輪診斷修正過，這次追加 `.at()`／
/// `findLastIndex()` 的 polyfill——已用 `@xmldom/xmldom` + 未經修改的實際
/// epub.js／epubcfi.js 驗證這兩個方法確實會在 Node.js 移除該內建方法後
/// 拋出對應的 `TypeError`。僅在缺席時才定義（不覆蓋原生實作，等原生
/// WebView 支援後行為與新版一致），透過 [UserScript] 在文件載入最早期
/// 注入，不修改 `readest/foliate-js` 釘定版本本身（比照既有 ADR 0011
/// 「不修改釘定版本」的既有限制）。
///
/// 【epic-18-reader-device-qa Issue 38，2026-08-05 追加發現】本腳本自身
/// 曾在 `Object.groupBy` polyfill 內用了 `??=`（邏輯 nullish 賦值，ES2021，
/// 需 Chromium 85+）——JS 引擎會在執行任何程式碼之前完整解析整份腳本，
/// 任何一處語法錯誤都會讓整份腳本（含本檔案其餘 3 個 polyfill）完全不
/// 執行。iReader Ocean 4 Plus 的系統 WebView 為 Chromium 83（早於 85），
/// 代表上面 4 個 polyfill 在這台裝置上其實從未真正生效過。已改寫為
/// ES5 相容語法（`if (!x) x = []` 取代 `x ??= []`）。**本腳本後續新增的
/// 任何 polyfill 本體，禁止使用 ES2020 之後的語法糖**（包括 `??=`／`||=`／
/// `&&=`／選用鏈結 `?.` 需 Chromium 80+、標籤模板等），因為這份腳本存在
/// 的唯一目的就是在不支援新語法的舊版 WebView 上執行。
///
/// 【epic-18-reader-device-qa Issue 41】`epub.js` 的字型反混淆
/// （`deobfuscators`）用了 `String.prototype.replaceAll`（ES2021，需
/// Chromium 85+）；`view.js` 的 Media Overlays 用了 `WeakRef`（ES2021，需
/// Chromium 84+）。iReader Ocean 4 Plus 的 Chromium 83 兩者皆不支援。兩者
/// 皆只在特定書籍功能（含混淆內嵌字型／含 media overlay）才會執行到，非
/// 通用開書路徑，故不像 Issue 38 的 `??=` 語法解析失敗那樣影響「每一本
/// 書」，但仍是真實存在的崩潰風險，一併補上防護。
const esCompatPolyfillJs = '''
if (!Object.groupBy) {
  Object.groupBy = function (items, keyFn) {
    const result = Object.create(null);
    let index = 0;
    for (const item of items) {
      const key = keyFn(item, index++);
      if (!result[key]) result[key] = [];
      result[key].push(item);
    }
    return result;
  };
}
if (!Map.groupBy) {
  Map.groupBy = function (items, keyFn) {
    const result = new Map();
    let index = 0;
    for (const item of items) {
      const key = keyFn(item, index++);
      if (!result.has(key)) result.set(key, []);
      result.get(key).push(item);
    }
    return result;
  };
}
if (!Array.prototype.at) {
  Array.prototype.at = function (index) {
    const len = this.length;
    const relativeIndex = index < 0 ? len + index : index;
    return (relativeIndex >= 0 && relativeIndex < len) ? this[relativeIndex] : undefined;
  };
}
if (!Array.prototype.findLastIndex) {
  Array.prototype.findLastIndex = function (predicate, thisArg) {
    for (let i = this.length - 1; i >= 0; i--) {
      if (predicate.call(thisArg, this[i], i, this)) return i;
    }
    return -1;
  };
}
if (!String.prototype.replaceAll) {
  String.prototype.replaceAll = function (search, replacement) {
    if (search instanceof RegExp) {
      if (!search.global) {
        throw new TypeError('replaceAll must be called with a global RegExp');
      }
      return this.replace(search, replacement);
    }
    if (typeof replacement === 'function') {
      // 目前 vendor 用法（epub.js 的字型反混淆）只會傳入字串
      // replacement，故不實作函式型 replacement——若未來真的用到，寧可
      // 在這裡明確拋出例外，也不要靜默產生錯誤結果（原本的寫法用
      // Array.prototype.join(fn)，join() 對非字串參數只會呼叫
      // fn.toString()，不會逐一呼叫該函式，等於把函式原始碼文字字面
      // 插入結果字串，是難以排查的靜默錯誤）。
      throw new TypeError(
        'replaceAll polyfill 尚未實作函式型 replacement（目前 vendor 用法不需要）'
      );
    }
    // 展開 \$\$（字面 \$ 符號）／\$&（比對到的子字串）兩種替換樣式，比照
    // 原生 String.prototype.replaceAll 規格常見用法；不支援比對前/後文字
    // 這兩種樣式——這兩者需要逐一追蹤每次匹配在原字串中的位置，split/join
    // 這種一次切割做法無法簡單支援，目前 vendor 用法也用不到，暫不實作。
    const expanded = String(replacement).replace(
      /\\\$(\\\$|&)/g,
      function (_, token) { return token === '\$' ? '\$' : String(search); }
    );
    return this.split(search).join(expanded);
  };
}
if (typeof WeakRef === 'undefined') {
  window.WeakRef = function (target) {
    // 注意：僅用強參照模擬 deref()，不具備真正的弱參照／GC 語意，只用於
    // 避免 ReferenceError；已知影響範圍：view.js 的 Media Overlays
    // lastActive 單一插槽變數（見上方文件註解），該變數在下一次
    // 'highlight' 事件觸發時會被覆寫，不會無限累積記憶體。
    this._target = target;
  };
  window.WeakRef.prototype.deref = function () {
    return this._target;
  };
}
''';

/// 全局 JS 錯誤捕捉（epic-18-reader-device-qa Issue 33，真機使用回報：
/// iReader Ocean 4 Plus 開啟書籍時畫面永遠停在載入指示器，5 個推測根因
/// 皆無真機診斷資料佐證）。`main.js` 本身的 `openBook()` 已用 try/catch
/// 涵蓋自身執行期間拋出的例外並回報 `onError`，但無法涵蓋：(1) 釘定的
/// vendor 腳本（`view.js`／`epub.js`／`paginator.js`）在文件載入極早期、
/// `main.js` 的 try/catch 尚未有機會執行前就拋出的例外（例如缺少 ES
/// 內建方法時的 `TypeError`，見上方 `esCompatPolyfillJs` 的既有診斷紀
/// 錄——這正是舊版 WebView 最典型的失敗模式）；(2) 未被 await 的 Promise
/// rejection。透過 `window.onerror`／`window.onunhandledrejection` 補上
/// 這兩類涵蓋範圍，並在 `AT_DOCUMENT_START`（比任何 vendor 腳本都早）
/// 注入，重用既有的 `onError` JS↔Dart bridge channel（見
/// `_onWebViewCreated` 的 'onError' handler），不需要新增任何 Dart 端
/// 接線或新的 channel。
///
/// epic-47：Chromium 的「ResizeObserver loop completed with undelivered
/// notifications」（舊版為「ResizeObserver loop limit exceeded」）只是告知
/// 一輪 resize callback 沒能在同一 frame 內處理完，不是錯誤，但同樣會派送到
/// `window.onerror`。不過濾的話會被轉成 `onError`：閱讀器載入中觸發時會把
/// 正常開啟的書誤判為開啟失敗，全文索引準備完成前觸發時會讓該書索引失敗。
/// 以共同前綴 `ResizeObserver loop` 比對，涵蓋新舊兩種訊息；WebView 仍會把
/// 這個警告鏡射成 console `[ERROR]`，診斷線索不會消失。
const globalErrorCaptureJs = '''
window.onerror = function (message, source, lineno, colno, error) {
  if (String(message).indexOf('ResizeObserver loop') !== -1) return;
  if (window.flutter_inappwebview) {
    window.flutter_inappwebview.callHandler('onError', 'JS Error: ' + message + ' (' + source + ':' + lineno + ')');
  }
};
window.onunhandledrejection = function (event) {
  if (window.flutter_inappwebview) {
    var reason = event && event.reason;
    var message = (reason && reason.message) || String(reason);
    window.flutter_inappwebview.callHandler('onError', 'Unhandled Promise Rejection: ' + message);
  }
};
''';
