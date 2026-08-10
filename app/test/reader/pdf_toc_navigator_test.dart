import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/pdf_toc_item.dart';
import 'package:elinkbook/reader/pdf_toc_navigator.dart';

void main() {
  final ch1 = const PdfTocItem(title: 'Ch1', pageIndex: 0, stableId: 'id1');
  final ch2s1 =
      const PdfTocItem(title: 'Ch2-S1', pageIndex: 3, stableId: 'id2s1');
  final ch2s2 =
      const PdfTocItem(title: 'Ch2-S2', pageIndex: 5, stableId: 'id2s2');
  final ch2 = PdfTocItem(
    title: 'Ch2',
    pageIndex: 2,
    stableId: 'id2',
    children: [ch2s1, ch2s2],
  );
  final ch3 = const PdfTocItem(title: 'Ch3', pageIndex: 8, stableId: 'id3');
  final noDest =
      const PdfTocItem(title: '無目的地章節', pageIndex: null, stableId: 'idNull');
  final entries = [ch1, ch2, ch3, noDest];

  group('findCurrentPath', () {
    test('currentPageIndex 為 null 時回傳空清單', () {
      expect(PdfTocNavigator.findCurrentPath(entries, null), isEmpty);
    });

    test('落在第一個頂層章節範圍內時，回傳只含該章節的路徑', () {
      expect(PdfTocNavigator.findCurrentPath(entries, 1), [ch1]);
    });

    test('落在有子章節的頂層章節、且已進入其第一個子項範圍時，回傳完整祖先路徑', () {
      expect(PdfTocNavigator.findCurrentPath(entries, 4), [ch2, ch2s1]);
    });

    test('落在最後一個頂層章節範圍內時，回傳只含該章節的路徑（不誤留前面章節的子項）', () {
      expect(PdfTocNavigator.findCurrentPath(entries, 9), [ch3]);
    });

    test('pageIndex 為 0（第一章開頭）時仍正確判定為該章節', () {
      expect(PdfTocNavigator.findCurrentPath(entries, 0), [ch1]);
    });

    test('全部節點 pageIndex 皆大於 currentPageIndex 時回傳空清單', () {
      expect(PdfTocNavigator.findCurrentPath(entries, -1), isEmpty);
    });

    test('pageIndex 為 null 的節點永遠不會被判定為目前章節', () {
      final onlyNullEntries = [noDest];
      expect(PdfTocNavigator.findCurrentPath(onlyNullEntries, 100), isEmpty);
    });

    test('父子節點指向同一頁碼時，回傳最深層（子節點）而非停在父節點（審查修正，'
        'review-plan-issue-5.md Minor #1：PDF 大綱常見「章節標題與該章第一節同頁」的寫法）', () {
      final child =
          const PdfTocItem(title: 'Chapter 1', pageIndex: 0, stableId: 'c1');
      final parent = PdfTocItem(
        title: 'Part One',
        pageIndex: 0,
        stableId: 'p1',
        children: [child],
      );
      expect(
        PdfTocNavigator.findCurrentPath([parent], 0),
        [parent, child],
      );
    });
  });
}
