import 'book_format.dart';
import 'epub_position_info.dart';
import 'pdf_page_info.dart';
import 'reader_prefs_manager.dart';
import 'reading_position.dart';

/// 一次閱讀會話內「此刻要不要儲存閱讀位置、要存什麼」的規則（見
/// `CONTEXT.md`「位置儲存規則」，`epic-54-architecture-optimization`
/// Issue 7）。
///
/// 擁有最新一筆 PDF／Foliate 位置回報，以及各格式「開書後是否已重新定位」
/// 旗標。呼叫端在每次收到位置回報時轉發進來，在進入背景與離開畫面時呼叫
/// [save]。
///
/// [save] 不等待儲存完成；沒趕上的位置由下一次 Checkpoint 同步補送。
class ReadingPositionSaver {
  ReadingPositionSaver({
    required this.bookId,
    required this.prefsManager,
    required this.hasJumpTarget,
    this.initialProgress,
  });

  final String bookId;
  final ReaderPrefsManager prefsManager;

  /// 開書時是否帶有跳轉目標（例如從搜尋結果、書籤開啟）。
  final bool hasJumpTarget;

  /// 開書時資料庫既有位置的進度；Foliate 定位尚未解析出 progression 時沿用，
  /// 避免把已讀大半的書靜默倒退回 0%。
  final double? initialProgress;

  PdfPageInfo? _pdfInfo;
  EpubPositionInfo? _epubInfo;

  /// 只在 [hasJumpTarget] 為 true 時有意義：代表使用者離開了跳轉目標本身（開書後
  /// 第一次回報是套用跳轉目標後的初始定位）。PDF 為第二次（含）以後的頁碼回報；
  /// Foliate 為「位置鍵與上一筆不同」的回報（重複回報不算，見
  /// [EpubPositionInfo.positionKey]）。
  /// 不論觸發來源是翻頁熱區、音量鍵、目錄／書籤跳轉或書內搜尋，都走同一組
  /// 回報，所以這個判斷涵蓋所有導覽方式。單向轉換（false → true）。
  bool _hasRelocatedPdf = false;
  bool _hasRelocatedEpub = false;

  void onPdfPageChanged(PdfPageInfo info) {
    if (_pdfInfo != null) _hasRelocatedPdf = true;
    _pdfInfo = info;
  }

  void onEpubLocated(EpubPositionInfo info) {
    // 只有位置真的改變才算「重新定位」：Foliate 開書後套用樣式重排、圖片／字型
    // 載入後重新對齊錨點，會派發位置相同的重複回報，不是使用者離開了跳轉目標。
    // 旗標只在有跳轉目標、且尚未成立時才有意義，其餘情況略過比較（省下每次
    // 翻頁的 JSON 解析）；_epubInfo 恆常更新，儲存時才有最新的進度。
    if (hasJumpTarget && !_hasRelocatedEpub) {
      final previous = _epubInfo;
      if (previous != null && previous.positionKey != info.positionKey) {
        _hasRelocatedEpub = true;
      }
    }
    _epubInfo = info;
  }

  /// 依 [format] 決定要不要儲存、存什麼；規則見類別文件與 `CONTEXT.md`。
  void save(BookFormat format) {
    switch (format) {
      case BookFormat.pdf:
        // 跳轉後尚未重新定位：保留資料庫既有位置，避免使用者只是看一下搜尋
        // 結果就離開，卻把原本讀到一半的進度覆蓋成跳轉目標本身。
        if (hasJumpTarget && !_hasRelocatedPdf) return;
        final info = _pdfInfo;
        if (info == null) return;
        prefsManager.saveReadingPosition(
          bookId,
          ReadingPosition(
            pdfPageIndex: info.pageIndex,
            progress: info.totalPages > 0
                ? (info.pageIndex + 1) / info.totalPages
                : 0,
          ),
        );
      case BookFormat.epub:
      case BookFormat.azw3:
      case BookFormat.cbz:
      case BookFormat.txt:
      case BookFormat.md:
        if (hasJumpTarget && !_hasRelocatedEpub) return;
        final info = _epubInfo;
        if (info == null) return;
        final progress = info.progression ?? initialProgress;
        if (progress == null) return;
        prefsManager.saveReadingPosition(
          bookId,
          ReadingPosition(epubLocatorJson: info.locatorJson, progress: progress),
        );
      case BookFormat.unknown:
        return;
    }
  }
}
