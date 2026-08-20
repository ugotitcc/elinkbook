/// PDF 內文搜尋的目前狀態（epic-24-pdf-engine-rebuild Issue 6），由
/// `ReaderScreen` 擁有並透過 `ValueNotifier<PdfSearchState>` 廣播給
/// `PdfSearchPanel`（`ValueListenableBuilder`），讓已開啟的目錄 Bottom
/// Sheet 能在背景搜尋完成當下即時更新。
///
/// [currentIndex] 是 0-indexed，指向目前使用者正在檢視的符合結果在
/// `ReaderScreen` 所持有的符合結果清單中的位置；`null` 代表尚無符合結果
/// 或尚未開始搜尋。
class PdfSearchState {
  final String query;
  final bool isSearching;
  final int matchCount;
  final int? currentIndex;

  const PdfSearchState({
    required this.query,
    required this.isSearching,
    required this.matchCount,
    required this.currentIndex,
  });

  const PdfSearchState.initial()
      : query = '',
        isSearching = false,
        matchCount = 0,
        currentIndex = null;

  /// [clearCurrentIndex] 為 true 時，無論是否有傳入 [currentIndex] 參數，
  /// 結果一律是 `null`——一般的 `currentIndex: null` 語意在 `copyWith`
  /// 慣例下代表「不覆寫」，需要這個獨立旗標才能明確表達「覆寫為 null」。
  PdfSearchState copyWith({
    String? query,
    bool? isSearching,
    int? matchCount,
    int? currentIndex,
    bool clearCurrentIndex = false,
  }) {
    return PdfSearchState(
      query: query ?? this.query,
      isSearching: isSearching ?? this.isSearching,
      matchCount: matchCount ?? this.matchCount,
      currentIndex: clearCurrentIndex ? null : (currentIndex ?? this.currentIndex),
    );
  }
}
