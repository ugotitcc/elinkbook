import 'dart:convert';

import 'package:flutter/widgets.dart';

import '../library/models/library_enums.dart';
import 'book_format.dart';
import 'foliate_reader_view.dart';
import 'pdf_reader_view.dart';
import 'percent_rect.dart';

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

  const ReaderJumpTarget({this.cfi, this.pdfPageIndex, this.pdfRect});

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

  /// 把本跳轉目標套用到一個活著的閱讀器 View（epic-41-search-architecture-hardening
  /// Issue 3）：依 [format] 分派到 PDF／Foliate 分支，[shouldNavigate] 為
  /// `true` 時先呼叫 `jumpToPage`/`jumpToLocator` 導覽過去，再嘗試疊加
  /// 暫態高亮。**回傳值即「本次是否真的疊加了暫態高亮」**（PDF 端對應
  /// [pdfPageIndex] 與 [pdfRect] 皆存在；Foliate 端對應 [cfi] 存在），
  /// 呼叫端據此決定要不要啟動 3 秒自動清除計時器——本方法本身不管理
  /// 計時器生命週期，那是 [ReaderScreen] 自己的狀態。
  ///
  /// 對應欄位缺失時優雅跳出、不拋例外（沿用 [fromContentLocator] 文件
  /// 註解的既有語意）：PDF 只有 [pdfPageIndex]、[pdfRect] 為 `null` 時，
  /// [shouldNavigate] 為 `true` 仍會先跳頁，只是不顯示暫態高亮、回傳
  /// `false`——跳頁與顯示高亮是兩個獨立判斷，不能因為沒有精確座標就連
  /// 頁面都不跳（`review-plan-issue-8.md` C-1 既有教訓）。[format] 既非
  /// PDF 也非 Foliate（例如 [BookFormat.unknown]）時直接回傳 `false`，
  /// 不做任何事。
  bool applyTo({
    required BookFormat format,
    required GlobalKey<State<PdfReaderView>> pdfKey,
    required GlobalKey<State<FoliateReaderView>> foliateKey,
    required bool shouldNavigate,
  }) {
    if (format == BookFormat.pdf) {
      final pageIndex = pdfPageIndex;
      if (pageIndex == null) return false;
      if (shouldNavigate) {
        PdfReaderView.jumpToPage(pdfKey, pageIndex);
      }
      final rect = pdfRect;
      if (rect == null) return false;
      PdfReaderView.showTemporaryHighlight(pdfKey, pageIndex, rect);
      return true;
    }
    if (isFoliateFormat(format)) {
      final targetCfi = cfi;
      if (targetCfi == null) return false;
      if (shouldNavigate) {
        FoliateReaderView.jumpToLocator(foliateKey, targetCfi);
      }
      FoliateReaderView.showSearchHighlight(foliateKey, targetCfi);
      return true;
    }
    return false;
  }
}
