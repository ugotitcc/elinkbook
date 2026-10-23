import 'dart:convert';


import '../library/models/library_enums.dart';
import 'percent_rect.dart';
import 'reader_surface.dart';

/// 全庫搜尋跳轉目標（epic-10-search Issue 5，spec.md §6）：`ReaderScreen`
/// 開書當下用來決定「建構子傳給底層 View 的初始定位參數」，優先權高於
/// 資料庫既有的 `lastPosition`；作用範圍精確限定於開書當下這一次性用途，
/// 不影響後續任何翻頁/checkpoint 寫入行為（見 `reader_screen.dart`
/// `initialJumpTarget` 欄位文件註解）。
class ReaderJumpTarget {
  /// Foliate 格式（EPUB/KF8/CBZ/TXT/MD）的目標 CFI。
  final String? cfi;

  /// PDF 目標頁碼（0-indexed）。
  final int? pdfPageIndex;

  /// PDF 頁內精確座標，暫態高亮疊加繪製用；[pdfPageIndex] 存在但本欄位
  /// 為 `null` 時，仍會正常跳轉頁面，只是不顯示暫態高亮。
  final PercentRect? pdfRect;

  /// Foliate 格式的目標進度比例（0.0～1.0），進度條拖動用；與 [cfi] 擇一。
  final double? progression;

  const ReaderJumpTarget({
    this.cfi,
    this.pdfPageIndex,
    this.pdfRect,
    this.progression,
  });

  /// 從 `SearchRepository.searchContent()` 回傳的
  /// `ContentMatchSnippet.locator` 建構跳轉目標（spec.md §1／§6）：
  /// Foliate 格式 locator 本身即為 CFI 字串；PDF 格式 locator 為
  /// `{"page":int,"rect":{"left":...,"top":...,"right":...,"bottom":...}}`
  /// 的 JSON 字串（見 `pdf_content_indexer.dart` 寫入格式，Issue 1）。
  /// `page` 欄位缺失/型別錯誤時回傳 `null`——沒有頁碼就沒有任何可跳轉的
  /// 目標，呼叫端應退回一般開書路徑而非崩潰；`rect` 欄位缺失/型別錯誤時
  /// **優雅降級**為只有 `pdfPageIndex`、`pdfRect` 為 `null`（審查修正
  /// M-2，推翻原計畫「rect 有問題就整筆回傳 null」設計）——仍能正確跳轉
  /// 到目標頁面，只是沒有精確座標可畫暫態高亮，比整個放棄跳轉、退回舊
  /// `lastPosition` 更貼近使用者「點了搜尋結果」的意圖。這兩種欄位皆是
  /// 系統自己寫入的衍生資料，理論上不會異常，但不假設一定合法（比照
  /// `SqliteSearchRepository.searchContent()` 對 `DatabaseException` 的
  /// 既有防禦分級）。
  static ReaderJumpTarget? fromContentLocator({
    required BookFileFormat format,
    required String locator,
  }) {
    if (format != BookFileFormat.pdf) {
      return ReaderJumpTarget(cfi: locator);
    }
    try {
      final map = jsonDecode(locator) as Map<String, dynamic>;
      final pageIndex = map['page'] as int;
      return ReaderJumpTarget(
        pdfPageIndex: pageIndex,
        pdfRect: _parsePdfRect(map['rect']),
      );
    } catch (_) {
      return null;
    }
  }

  /// [rawRect] 是否為合法的 `{"left":...,"top":...,"right":...,"bottom":...}`
  /// 結構，任何一步失敗（型別不符、缺欄位）皆回傳 `null`，不拋例外——
  /// 呼叫端（[fromContentLocator]）遇到 `null` 會保留已解析出的
  /// `pdfPageIndex`，只是不顯示暫態高亮（審查修正 M-2）。
  static PercentRect? _parsePdfRect(dynamic rawRect) {
    if (rawRect is! Map<String, dynamic>) return null;
    try {
      return PercentRect(
        left: (rawRect['left'] as num).toDouble(),
        top: (rawRect['top'] as num).toDouble(),
        right: (rawRect['right'] as num).toDouble(),
        bottom: (rawRect['bottom'] as num).toDouble(),
      );
    } catch (_) {
      return null;
    }
  }

  /// 把本跳轉目標套用到「閱讀面」（epic-54 Issue 23：格式分派已搬進
  /// [ReaderSurface] 的各 adapter）：[shouldNavigate] 為 `true` 時先
  /// [ReaderSurface.jumpTo] 導覽過去，再 [ReaderSurface.showTransientHighlight]
  /// 嘗試疊加暫態高亮。**回傳值即「本次是否真的疊加了暫態高亮」**（PDF 端對應
  /// [pdfPageIndex] 與 [pdfRect] 皆存在；Foliate 端對應 [cfi] 存在），呼叫端據此
  /// 決定要不要啟動 3 秒自動清除計時器——本方法本身不管理計時器生命週期，
  /// 那是 [ReaderScreen] 自己的狀態。
  ///
  /// 對應欄位缺失時優雅跳出、不拋例外（沿用 [fromContentLocator] 文件註解的
  /// 既有語意）：PDF 只有 [pdfPageIndex]、[pdfRect] 為 `null` 時，
  /// [shouldNavigate] 為 `true` 仍會先跳頁，只是不顯示暫態高亮、回傳
  /// `false`——跳頁與顯示高亮是兩個獨立判斷，不能因為沒有精確座標就連
  /// 頁面都不跳（`review-plan-issue-8.md` C-1 既有教訓）。閱讀面為
  /// `NoopReaderSurface`（`BookFormat.unknown`）時兩個指令皆為空操作，回傳
  /// `false`。
  bool applyTo({
    required ReaderSurface surface,
    required bool shouldNavigate,
  }) {
    if (shouldNavigate) {
      surface.jumpTo(this);
    }
    return surface.showTransientHighlight(this);
  }
}
