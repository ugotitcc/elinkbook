import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/toc_entry.dart';
import 'package:elinkbook/reader/toc_navigator.dart';

void main() {
  final ch1 = const TocEntry(title: 'Ch1', locatorJson: 'l1', progression: 0.0);
  final ch2s1 =
      const TocEntry(title: 'Ch2-S1', locatorJson: 'l2s1', progression: 0.35);
  final ch2s2 =
      const TocEntry(title: 'Ch2-S2', locatorJson: 'l2s2', progression: 0.45);
  final ch2 = TocEntry(
    title: 'Ch2',
    locatorJson: 'l2',
    progression: 0.3,
    children: [ch2s1, ch2s2],
  );
  final ch3 = const TocEntry(title: 'Ch3', locatorJson: 'l3', progression: 0.7);
  final entries = [ch1, ch2, ch3];

  group('findCurrentPath', () {
    test('currentProgression 為 null 時回傳空清單', () {
      expect(TocNavigator.findCurrentPath(entries, null), isEmpty);
    });

    test('落在第一個頂層章節範圍內時，回傳只含該章節的路徑', () {
      expect(TocNavigator.findCurrentPath(entries, 0.1), [ch1]);
    });

    test('落在有子章節的頂層章節、且已進入其第一個子項範圍時，回傳完整祖先路徑', () {
      expect(TocNavigator.findCurrentPath(entries, 0.4), [ch2, ch2s1]);
    });

    test('落在最後一個頂層章節範圍內時，回傳只含該章節的路徑（不誤留前面章節的子項）', () {
      expect(TocNavigator.findCurrentPath(entries, 0.9), [ch3]);
    });

    test('progression 為 0.0（第一章開頭）時仍正確判定為該章節', () {
      expect(TocNavigator.findCurrentPath(entries, 0.0), [ch1]);
    });

    test('全部節點 progression 皆大於 currentProgression 時回傳空清單', () {
      expect(TocNavigator.findCurrentPath(entries, -0.1), isEmpty);
    });
  });
}