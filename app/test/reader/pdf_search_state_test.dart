import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/pdf_search_state.dart';

void main() {
  test('initial 為空查詢、非搜尋中、0 筆符合、currentIndex 為 null', () {
    const state = PdfSearchState.initial();
    expect(state.query, '');
    expect(state.isSearching, isFalse);
    expect(state.matchCount, 0);
    expect(state.currentIndex, isNull);
  });

  test('copyWith 只覆寫指定欄位，其餘保留原值', () {
    const state = PdfSearchState(
      query: 'abc',
      isSearching: false,
      matchCount: 3,
      currentIndex: 1,
    );
    final updated = state.copyWith(currentIndex: 2);
    expect(updated.query, 'abc');
    expect(updated.isSearching, isFalse);
    expect(updated.matchCount, 3);
    expect(updated.currentIndex, 2);
  });

  test('copyWith 可將 currentIndex 明確設回 null（clearCurrentIndex）', () {
    const state = PdfSearchState(
      query: 'abc',
      isSearching: false,
      matchCount: 3,
      currentIndex: 1,
    );
    final updated = state.copyWith(clearCurrentIndex: true);
    expect(updated.currentIndex, isNull);
  });
}
