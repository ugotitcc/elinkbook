import 'dart:convert';

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

  /// 產生與 main.js buildTocEntry 同格式的 locatorJson：{cfi, index, fraction}。
  String loc(int index, [double? fraction]) =>
      jsonEncode({'cfi': 'epubcfi(/6/${index * 2 + 2})', 'index': index, 'fraction': fraction});

  group('findCurrentPath（spine index 優先，Issue 19）', () {
    // 重現 TCL 14 真機：三個頂層章節各佔一個 spine，頂層 progression 結構性為 null，
    // 第二章有兩個子節（同 spine 1，帶錨點 progression）。
    final c1 = TocEntry(title: '第一章', locatorJson: loc(0), progression: null);
    final c2s1 = TocEntry(title: '第一節', locatorJson: loc(1, 0.30), progression: 0.30);
    final c2s2 = TocEntry(title: '第二節', locatorJson: loc(1, 0.45), progression: 0.45);
    final c2 = TocEntry(
      title: '第二章',
      locatorJson: loc(1),
      progression: null,
      children: [c2s1, c2s2],
    );
    final c3 = TocEntry(title: '第三章', locatorJson: loc(2), progression: null);
    final toc = [c1, c2, c3];

    test('開書在第一章、全書 progression 偏高（0.554）時，仍判定為第一章（不誤展開第二章）', () {
      expect(
        TocNavigator.findCurrentPath(toc, 0.554, currentSpineIndex: 0),
        [c1],
      );
    });

    test('頂層章節 progression 為 null 也能靠 spine index 被選中', () {
      expect(
        TocNavigator.findCurrentPath(toc, null, currentSpineIndex: 2),
        [c3],
      );
    });

    test('位於第二章章首（尚未到任何子節錨點）時，只選第二章本身', () {
      expect(
        TocNavigator.findCurrentPath(toc, 0.10, currentSpineIndex: 1),
        [c2],
      );
    });

    test('位於第二章且已過第一節錨點時，回傳第二章→第一節的完整路徑', () {
      expect(
        TocNavigator.findCurrentPath(toc, 0.35, currentSpineIndex: 1),
        [c2, c2s1],
      );
    });

    test('位於第二章且已過第二節錨點時，回傳第二章→第二節的完整路徑', () {
      expect(
        TocNavigator.findCurrentPath(toc, 0.50, currentSpineIndex: 1),
        [c2, c2s2],
      );
    });

    test('跳轉至第三章且帶有全書 progression 時，精確判定為第三章', () {
      expect(
        TocNavigator.findCurrentPath(toc, 0.90, currentSpineIndex: 2),
        [c3],
      );
    });

    test('節點 locatorJson 為空字串（href 無法解析）時退回 progression 規則，不拋例外', () {
      final broken = TocEntry(title: '壞節點', locatorJson: '', progression: 0.2);
      expect(
        TocNavigator.findCurrentPath([c1, broken], 0.5, currentSpineIndex: 0),
        [broken],
        reason: '缺 index 的節點沿用舊規則：progression 0.2 <= 0.5 視為已通過',
      );
    });

    test('currentSpineIndex 為 null 時行為與舊規則相同（向下相容）', () {
      expect(TocNavigator.findCurrentPath(toc, 0.35), [c2, c2s1],
          reason: '頂層 progression 全為 null，舊規則下只有子節 0.30 <= 0.35 命中');
    });

    test('currentProgression 為 null 但 spine 已知時，同 spine 內所有節點視為已通過（選到最深最後一筆）', () {
      // 釘住現行語意：progression 缺值時無法比較錨點先後，保守取同 spine 最後一筆。
      // 實務上 parseLocatorChanged 以 fraction ?? 0.0 預設，不會走到此分支。
      expect(
        TocNavigator.findCurrentPath(toc, null, currentSpineIndex: 1),
        [c2, c2s2],
      );
    });

    test('currentProgression 與 currentSpineIndex 皆為 null 時回傳空清單', () {
      expect(TocNavigator.findCurrentPath(toc, null), isEmpty);
    });
  });

  group('findCurrentPath（tocItemId 優先，Issue 20）', () {
    // 單一 spine（index 0）內三個錨點：第一章下有第一節／第二節／第三節。
    // progression 刻意設成與「讀者實際位置」不一致，證明結果來自 tocItemId。
    final s1 = TocEntry(
        title: '第一節', locatorJson: loc(0, 0.10), progression: 0.10, tocId: 1);
    final s2 = TocEntry(
        title: '第二節', locatorJson: loc(0, 0.40), progression: 0.40, tocId: 2);
    final s3 = TocEntry(
        title: '第三節', locatorJson: loc(0, 0.70), progression: 0.70, tocId: 3);
    final ch = TocEntry(
      title: '第一章',
      locatorJson: loc(0),
      progression: null,
      tocId: 0,
      children: [s1, s2, s3],
    );
    final next =
        TocEntry(title: '第二章', locatorJson: loc(1), progression: null, tocId: 4);
    final toc = [ch, next];

    test('開書 progression 偏高（0.55）但 foliate 回報目前是第一節：只選第一節', () {
      expect(
        TocNavigator.findCurrentPath(toc, 0.55,
            currentSpineIndex: 0, currentTocItemId: 1),
        [ch, s1],
        reason: '不得因 0.55 >= 0.40 而誤選第二節',
      );
    });

    test('currentTocItemId 為 0（第一個目錄項）要命中第一個節點，不得退回舊規則', () {
      expect(
        TocNavigator.findCurrentPath(toc, 0.55,
            currentSpineIndex: 0, currentTocItemId: 0),
        [ch],
        reason: '0 是合法 id；若被當成缺席會退回 progression 規則而選到第二節',
      );
    });

    test('回報第三節：回傳第一章→第三節的完整祖先路徑', () {
      expect(
        TocNavigator.findCurrentPath(toc, 0.05,
            currentSpineIndex: 0, currentTocItemId: 3),
        [ch, s3],
      );
    });

    test('目前 spine 沒有目錄項、foliate 回報前一章節點：回傳該節點的祖先路徑', () {
      // 讀者在 spine 2（無目錄項的插頁），tocItem 為前一個項目「第三節」。
      expect(
        TocNavigator.findCurrentPath(toc, 0.9,
            currentSpineIndex: 2, currentTocItemId: 3),
        [ch, s3],
      );
    });

    test('currentTocItemId 在樹中查無節點：退回 spine index 規則（Issue 19）', () {
      expect(
        TocNavigator.findCurrentPath(toc, 0.9,
            currentSpineIndex: 1, currentTocItemId: 99),
        [next],
      );
    });

    test('currentTocItemId 為 null：行為與 Issue 19 相同', () {
      expect(
        TocNavigator.findCurrentPath(toc, 0.55, currentSpineIndex: 0),
        TocNavigator.findCurrentPath(toc, 0.55,
            currentSpineIndex: 0, currentTocItemId: null),
      );
    });

    test('節點缺 tocId（舊資料）時 id 不命中，退回舊規則且不拋例外', () {
      final legacy =
          TocEntry(title: '舊節點', locatorJson: loc(0), progression: null);
      expect(
        TocNavigator.findCurrentPath([legacy], null,
            currentSpineIndex: 0, currentTocItemId: 0),
        [legacy],
      );
    });

    test('只有 currentTocItemId、其餘皆 null 也能判定（不被「皆 null 回空」誤擋）', () {
      expect(
        TocNavigator.findCurrentPath(toc, null, currentTocItemId: 2),
        [ch, s2],
      );
    });

    test('三者皆 null 回傳空清單（首個 relocate 之前）', () {
      expect(TocNavigator.findCurrentPath(toc, null), isEmpty);
    });
  });
}