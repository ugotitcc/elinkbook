// Windows 版將 App 放在使用者「文件」資料夾的資料收進上層目錄 `elinkbook-data`（epic-66 Issue 29）。
//
// 為什麼 Windows 要有這層上層目錄：
// Windows 的 `getApplicationDocumentsDirectory()` 直接回傳使用者「文件」資料夾根目錄，
// 導致書庫、字典、封面等項目與使用者個人檔案混在一起，使用者看不出這些檔案屬於哪個 App，
// 也讓解除安裝時無法安全刪除。Android 等平台回傳的是 App 私有空間，無此問題，故維持原狀。
//
// 為什麼叫 `elinkbook-data` 而不是 `elinkbook`：
// 免安裝 zip 解壓出來的程式資料夾叫 `elinkbook`，Windows 路徑又不分大小寫；若使用者把 zip
// 解壓到「文件」，程式與資料會變成同一個資料夾，刪程式就等於刪書庫（見 ADR 0044）。
// 這個名稱發佈後就不能改，否則舊資料會被孤立。
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
///
/// 發佈後不可更改（見檔頭說明與 ADR 0044）；解除安裝程式 `elinkbook.iss` 也寫死同一個名稱。
const String kWindowsAppFolderName = 'elinkbook-data';

/// 取得本 App 存放文件資料的根目錄。
///
/// Windows 平台會回傳 `<文件>\elinkbook-data`（若不存在則遞迴建立）；
/// 其他平台（如 Android、iOS）原樣回傳 `getApplicationDocumentsDirectory()`，不建立任何子目錄。
///
/// 建立失敗（例如該路徑已被同名「檔案」佔用、或受控資料夾存取擋下寫入）時，
/// 原樣丟出 [FileSystemException]：沒有資料夾就無法存放書庫，不做無聲的退路。
Future<Directory> appDocumentsDirectory() async {
  final docsDir = await getApplicationDocumentsDirectory();
  if (!isWindowsPlatform) {
    return docsDir;
  }
  // `create(recursive: true)` 對已存在的資料夾本來就不會報錯，也不怕多處同時呼叫。
  return Directory(p.join(docsDir.path, kWindowsAppFolderName))
      .create(recursive: true);
}
