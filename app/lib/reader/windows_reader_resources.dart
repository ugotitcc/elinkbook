// Windows 的讀者資源實作（epic-66 Issue 1 Task 6）。
//
// 對應 Android 端 `ReaderResourceChannel`／`InternalStoragePathHandler` 的
// 職責，但 Windows 沒有原生 channel，一律直接讀本機檔案：
// - foliate-js 靜態資源：由 `windows/CMakeLists.txt` 複製到執行檔旁的
//   `data/foliate/`（Task 5），經 [loadWindowsFoliateAsset] 讀取。
// - 書檔：先用 [cacheWindowsBook] 複製到「每個 widget 實例獨立」的快取
//   子目錄（比照 Android `cacheBookForServing` 的 instanceId 語意），再由
//   攔截回呼以 [readWindowsBookBytes] 服務 `/book/` 請求。
// - 自訂字型：[loadWindowsFileBytes] 直接讀本機檔案（ADR 0021 不落地快取
//   的語意在 Windows 上即「原本就在本機」）。
//
// 大檔（200 MB 等級的 CBZ/EPUB）複製一律走串流，不整包讀進記憶體；只有
// 攔截回應 `/book/` 時才會把整本位元組交給 WebView（Review Focus 2 的
// 尖峰記憶體在 Task 9 實測）。

import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'foliate_native_bridge.dart' show cacheFileExtension;

/// 讀取 `assetRoot/<relativePath>` 的檔案位元組（Windows 版
/// [loadAndroidAsset]，assetRoot 為執行檔旁的 `data/` 目錄）。
///
/// 檔案不存在回 `null`；[relativePath] 含 `..` 回 `null`（禁止跳出
/// assetRoot）。對應 Android 端找不到檔案回 `null` 的既有語意（例如
/// `view.js` 動態 import 但不存在的 `vendor/fflate.js`）。
Future<Uint8List?> loadWindowsFoliateAsset(
  String relativePath, {
  required String assetRoot,
}) async {
  if (relativePath.contains('..')) return null;
  final file = File(p.join(assetRoot, relativePath));
  try {
    if (!await file.exists()) return null;
    return await file.readAsBytes();
  } on FileSystemException {
    return null;
  }
}

/// 把書檔複製到 `baseDir/<instanceId>/current.<ext>`（副檔名沿用
/// [cacheFileExtension]，與 Android 快取檔名規則一致），回傳該檔絕對路徑。
///
/// 每個 widget 實例有自己的子目錄，同一本書連開兩次、或開書中途離開畫面
/// 都不會互相覆蓋（Review Focus 3）。來源不存在回 `null`。大檔以串流複製，
/// 不整包讀進記憶體。
Future<String?> cacheWindowsBook(
  String filePath,
  String instanceId, {
  required Directory baseDir,
}) async {
  final source = File(filePath);
  try {
    if (!await source.exists()) return null;
    final targetDir = Directory(p.join(baseDir.path, instanceId));
    await targetDir.create(recursive: true);
    final target = File(p.join(targetDir.path, 'current.${cacheFileExtension(filePath)}'));
    await source.openRead().pipe(target.openWrite());
    return target.path;
  } on FileSystemException {
    return null;
  }
}

/// 讀取本機檔案的位元組（Windows 版自訂字型讀取）；檔案不存在回 `null`。
Future<Uint8List?> loadWindowsFileBytes(String path) async {
  final file = File(path);
  try {
    if (!await file.exists()) return null;
    return await file.readAsBytes();
  } on FileSystemException {
    return null;
  }
}

/// 服務攔截到的 `/book/` 請求：[requestPath] 必須以 `/book/` 開頭，
/// 其餘部分視為檔名，讀 `bookDir/<檔名>`。
///
/// 任一情況回 `null`（讓 WebView 走預設行為，不丟例外，Review Focus 4）：
/// - 不以 `/book/` 開頭；
/// - 檔名含 `..` 或路徑分隔符號（`/`、`\`），禁止跳出 bookDir；
/// - 檔案不存在。
/// 閱讀器與索引器共用（Task 7）。
Future<Uint8List?> readWindowsBookBytes(
  String requestPath,
  String bookDir,
) async {
  const prefix = '/book/';
  if (!requestPath.startsWith(prefix)) return null;
  final fileName = requestPath.substring(prefix.length);
  if (fileName.isEmpty ||
      fileName.contains('..') ||
      fileName.contains('/') ||
      fileName.contains(r'\')) {
    return null;
  }
  return loadWindowsFileBytes(p.join(bookDir, fileName));
}

/// `/book/` 回應的 Content-Type：`.epub` 回 `application/epub+zip`、
/// `.cbz` 回 `application/vnd.comicbook+zip`，其餘回
/// `application/octet-stream`（副檔名大小寫不敏感）。
String windowsBookContentType(String fileName) {
  switch (p.extension(fileName).toLowerCase()) {
    case '.epub':
      return 'application/epub+zip';
    case '.cbz':
      return 'application/vnd.comicbook+zip';
    default:
      return 'application/octet-stream';
  }
}
