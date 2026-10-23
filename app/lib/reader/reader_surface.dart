import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../theme/elink_tokens.dart';
import 'foliate_reader_view.dart';
import 'highlight.dart';
import 'note.dart';
import 'pdf_reader_view.dart';
import 'pdf_search_match.dart';
import 'pdf_toc_item.dart';
import 'percent_rect.dart';
import 'reader_jump_target.dart';
import 'toc_entry.dart';
import 'tts_segment_cfi.dart';

/// 閱讀面（epic-54-architecture-optimization Issue 23，見 CONTEXT.md「閱讀面」）：
/// `ReaderScreen` 對「目前這本書的渲染畫面」下指令的單一 interface。
///
/// 只放 Foliate 與 PDF 兩邊都有意義的指令；格式專屬功能由 [foliate]／[pdf]
/// 兩個 facet 提供，避免一堆空實作。
///
/// **未掛載規則**（零行為變化，逐字沿用兩個 View 的 static 方法慣例）：底層
/// View 尚未掛載時，指令靜默忽略，查詢回傳預設值（空清單、`0`、`null`、
/// `false`），不拋例外。
abstract class ReaderSurface {
  void nextPage();
  void previousPage();

  /// 只導覽，不疊高亮。依 [target] 的欄位決定：[ReaderJumpTarget.cfi]
  /// （Foliate）、[ReaderJumpTarget.progression]（Foliate 進度條）、
  /// [ReaderJumpTarget.pdfPageIndex]（PDF）。目標欄位與本格式無關時不動作。
  void jumpTo(ReaderJumpTarget target);

  /// 疊加搜尋跳轉暫態高亮；回傳本次是否真的疊加（呼叫端據此決定要不要啟動
  /// 3 秒自動清除計時器）。
  bool showTransientHighlight(ReaderJumpTarget target);

  void clearTransientHighlight();

  void clearSelection();

  /// 查字典面板開啟期間暫時收起選取（見 main.js window.suspendSelection）。
  /// PDF：空操作——框選矩形由 Flutter 自己畫，不會浮在面板上。
  void suspendSelection();
  void restoreSelection();

  /// 整組重畫標註；各格式把 [Highlight]／[Note] 轉成自己的裝飾型別。
  void refreshAnnotations({
    required List<Highlight> highlights,
    required List<Note> notes,
    required ElinkTokens tokens,
  });

  /// Foliate 專屬功能；Foliate 各格式恰有一個非 null（與 [pdf] 互斥）。
  FoliateFacet? get foliate;

  /// PDF 專屬功能；PDF 格式恰有一個非 null（與 [foliate] 互斥）。
  PdfFacet? get pdf;
}

/// Foliate 專屬功能（目錄與 TTS 都只有 Foliate 格式有）。
abstract class FoliateFacet {
  GlobalKey<State<FoliateReaderView>> get viewKey;

  Future<List<TocEntry>> loadTableOfContents();

  Future<List<TtsSegmentCfi>> loadTtsSegments(int sectionIndex);

  Future<int> lookupSegmentByCfi(String visibleCfi, List<String> segmentCfis);

  void showTtsHighlight(
    String cfi, {
    required bool vertical,
    required bool einkMode,
  });

  void clearTtsHighlight();
}

/// PDF 專屬功能（目錄、內文搜尋、頁縮圖與框選拖曳中止）。
abstract class PdfFacet {
  GlobalKey<State<PdfReaderView>> get viewKey;

  Future<List<PdfTocItem>> loadTableOfContents();

  void cancelActiveSelectionDrag();

  Future<List<PdfSearchMatch>> search(String query);

  void setSearchHighlights(
    List<PdfSearchMatch> matches, {
    required int? currentIndex,
  });

  void jumpToPageAtRect(int pageIndex, PercentRect rect);

  Future<ui.Image?> renderThumbnail(int pageIndex, {required double maxWidth});
}

/// `BookFormat.unknown` 專用：畫面只顯示不支援訊息、不建構任何 View，所有
/// 指令本來就是空操作（現況對沒有掛載的 key 呼叫 static 方法的結果相同）。
/// 兩個 facet 皆為 `null`。
class NoopReaderSurface implements ReaderSurface {
  const NoopReaderSurface();

  @override
  void nextPage() {}

  @override
  void previousPage() {}

  @override
  void jumpTo(ReaderJumpTarget target) {}

  @override
  bool showTransientHighlight(ReaderJumpTarget target) => false;

  @override
  void clearTransientHighlight() {}

  @override
  void clearSelection() {}

  @override
  void suspendSelection() {}

  @override
  void restoreSelection() {}

  @override
  void refreshAnnotations({
    required List<Highlight> highlights,
    required List<Note> notes,
    required ElinkTokens tokens,
  }) {}

  @override
  FoliateFacet? get foliate => null;

  @override
  PdfFacet? get pdf => null;
}
