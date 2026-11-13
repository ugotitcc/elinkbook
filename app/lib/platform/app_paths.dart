// Windows 版將 App 放在使用者「文件」資料夾的資料收進上層目錄 `elinkbook`（epic-66 Issue 29）。
//
// 為什麼 Windows 要有這層上層目錄：
// Windows 的 `getApplicationDocumentsDirectory()` 直接回傳使用者「文件」資料夾根目錄，
// 導致書庫、字典、封面等項目與使用者個人檔案混在一起，使用者看不出這些檔案屬於哪個 App，
// 也讓解除安裝時無法安全刪除。Android 等平台回傳的是 App 私有空間，無此問題，故維持原狀。
//
// 為什麼不自動遷移舊資料：
// 資料庫內儲存絕對路徑且目前 Windows 僅開發者自用（見 ADR 0044），搬移檔案無法單獨救回書庫；
// 舊位置項目採不讀、不改、不刪策略，由使用者自行處理。
//
// 警告：日後任何要存進使用者「文件」的資料，一律呼叫 [appDocumentsDirectory]，
// 切勿再直接呼叫 `getApplicationDocumentsDirectory()`，否則資料會再次散落在「文件」根目錄。

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'platform_support.dart';

/// Windows 上於使用者「文件」資料夾內建立的專屬上層目錄名稱。
const String kWindowsAppFolderName = 'elinkbook';

/// 取得本 App 存放文件資料的根目錄。
///
/// Windows 平台會回傳 `<文件>\elinkbook`（若不存在則遞迴建立）；
/// 其他平台（如 Android、iOS）原樣回傳 `getApplicationDocumentsDirectory()`，不建立任何子目錄。
Future<Directory> appDocumentsDirectory() async {
  final docsDir = await getApplicationDocumentsDirectory();
  if (!isWindowsPlatform) {
    return docsDir;
  }
  final appDir = Directory(p.join(docsDir.path, kWindowsAppFolderName));
  if (!await appDir.exists()) {
    await appDir.create(recursive: true);
  }
  return appDir;
}
