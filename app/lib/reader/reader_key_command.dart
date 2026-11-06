import 'package:flutter/services.dart';

/// 閱讀器支援的鍵盤快捷鍵語意命令。
///
/// 與平台無關，由 [readerKeyCommandFor] 依書寫方向與修飾鍵解析產出，
/// 供閱讀器畫面（`ReaderScreen`）分派給對應的翻頁或搜尋動作。
enum ReaderKeyCommand {
  /// 翻至上一頁
  previousPage,

  /// 翻至下一頁
  nextPage,

  /// 跳至第一頁（首頁）
  firstPage,

  /// 跳至最後一頁（末頁）
  lastPage,

  /// 開啟書內搜尋
  openSearch,
}

/// 解析鍵盤按鍵為對應的閱讀器命令 [ReaderKeyCommand]。
///
/// 規則：
/// 1. 翻頁與導航鍵（ArrowLeft、ArrowRight、ArrowUp、ArrowDown、PageUp、PageDown、Space、Home、End）：
///    - 若帶有 [control]、[alt] 或 [meta] 修飾鍵，一律視為系統或外部快捷鍵，回傳 `null`。
///    - [space]：單獨按為 [ReaderKeyCommand.nextPage]；若帶有 [shift] 則為 [ReaderKeyCommand.previousPage]。
///    - 其他導航按鍵不受 [shift] 影響。
/// 2. 書寫方向與鏡像（[verticalWriting]）：
///    - 橫排（[verticalWriting] == false）：ArrowLeft 為上一頁、ArrowRight 為下一頁。
///    - 直排（[verticalWriting] == true）：繁體中文直排自右向左翻頁，ArrowLeft 為下一頁、ArrowRight 為上一頁。
///    - ArrowUp／PageUp 永遠為上一頁；ArrowDown／PageDown 永遠為下一頁；Home 永遠為首頁；End 永遠為末頁。
/// 3. 書內搜尋：
///    - 僅在 [control] 為 true 且 [shift]、[alt]、[meta] 皆為 false 時，[LogicalKeyboardKey.keyF] 對應為 [ReaderKeyCommand.openSearch]。
/// 4. 其他按鍵一律回傳 `null`。
ReaderKeyCommand? readerKeyCommandFor(
  LogicalKeyboardKey key, {
  bool shift = false,
  bool control = false,
  bool alt = false,
  bool meta = false,
  required bool verticalWriting,
}) {
  // 書內搜尋：純 Ctrl+F
  if (control && !shift && !alt && !meta && key == LogicalKeyboardKey.keyF) {
    return ReaderKeyCommand.openSearch;
  }

  // 翻頁與導覽鍵不接受 control / alt / meta 修飾鍵
  if (control || alt || meta) {
    return null;
  }

  if (key == LogicalKeyboardKey.arrowLeft) {
    return verticalWriting
        ? ReaderKeyCommand.nextPage
        : ReaderKeyCommand.previousPage;
  }

  if (key == LogicalKeyboardKey.arrowRight) {
    return verticalWriting
        ? ReaderKeyCommand.previousPage
        : ReaderKeyCommand.nextPage;
  }

  if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.pageUp) {
    return ReaderKeyCommand.previousPage;
  }

  if (key == LogicalKeyboardKey.arrowDown ||
      key == LogicalKeyboardKey.pageDown) {
    return ReaderKeyCommand.nextPage;
  }

  if (key == LogicalKeyboardKey.space) {
    return shift ? ReaderKeyCommand.previousPage : ReaderKeyCommand.nextPage;
  }

  if (key == LogicalKeyboardKey.home) {
    return ReaderKeyCommand.firstPage;
  }

  if (key == LogicalKeyboardKey.end) {
    return ReaderKeyCommand.lastPage;
  }

  return null;
}
