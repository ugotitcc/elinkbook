import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/percent_rect.dart';
import 'package:elinkbook/reader/reader_jump_target.dart';
import 'package:elinkbook/reader/reader_surface.dart';
import 'package:elinkbook/theme/elink_tokens.dart';

import '../support/fake_reader_surface.dart';

const _tokens = ElinkTokens(
  highlightYellow: Color(0xFFFEF08A),
  highlightGreen: Color(0xFFBBF7D0),
  highlightBlue: Color(0xFFBFDBFE),
  underlineColor: Color(0xFF0284C7),
  progressTrack: Color(0xFFCBDFE9),
  coverPlaceholder: Color(0xFFE6F1FA),
  badgeScrim: Color(0xFF94A3B8),
  ttsActiveHighlight: Color(0xFFE0F2FE),
  heatmapLevel0: Color(0xFFEAF1F5),
  heatmapLevel1: Color(0xFFBAE6FD),
  heatmapLevel2: Color(0xFF7DD3FC),
  heatmapLevel3: Color(0xFF38BDF8),
  heatmapLevel4: Color(0xFF0284C7),
  isEink: false,
  reducedMotion: false,
  discretePaging: false,
);

void main() {
  group('ReaderJumpTarget.progression', () {
    test('可只帶進度比例建構（Foliate 進度條拖動用）', () {
      const target = ReaderJumpTarget(progression: 0.5);

      expect(target.progression, 0.5);
      expect(target.cfi, isNull);
      expect(target.pdfPageIndex, isNull);
    });
  });

  group('FakeReaderSurface 契約', () {
    test('Foliate 格式：foliate facet 非 null、pdf facet 為 null', () {
      final surface = FakeReaderSurface.foliate();

      expect(surface.foliate, isNotNull);
      expect(surface.pdf, isNull);
    });

    test('PDF 格式：pdf facet 非 null、foliate facet 為 null', () {
      final surface = FakeReaderSurface.pdf();

      expect(surface.pdf, isNotNull);
      expect(surface.foliate, isNull);
    });

    test('指令依呼叫順序記錄', () {
      final surface = FakeReaderSurface.pdf();

      surface.nextPage();
      surface.pdf!.cancelActiveSelectionDrag();
      surface.previousPage();
      surface.clearSelection();
      surface.suspendSelection();
      surface.restoreSelection();
      surface.clearTransientHighlight();

      expect(surface.calls, [
        'nextPage',
        'pdf.cancelActiveSelectionDrag',
        'previousPage',
        'clearSelection',
        'suspendSelection',
        'restoreSelection',
        'clearTransientHighlight',
      ]);
    });

    test('jumpTo 與 showTransientHighlight 記錄目標；高亮回傳值可由測試指定', () {
      final surface = FakeReaderSurface.pdf(showsTransientHighlight: true);
      const target = ReaderJumpTarget(
        pdfPageIndex: 3,
        pdfRect: PercentRect(left: 0.1, top: 0.1, right: 0.5, bottom: 0.2),
      );

      surface.jumpTo(target);
      final shown = surface.showTransientHighlight(target);

      expect(shown, isTrue);
      expect(surface.calls, ['jumpTo', 'showTransientHighlight']);
      expect(surface.jumpTargets, [target, target]);
    });

    test('提供真實的 GlobalKey，讓注入 fake 時 View 仍能掛載', () {
      expect(FakeReaderSurface.foliate().foliate!.viewKey, isA<GlobalKey>());
      expect(FakeReaderSurface.pdf().pdf!.viewKey, isA<GlobalKey>());
    });
  });

  group('NoopReaderSurface（BookFormat.unknown）', () {
    test('兩個 facet 皆為 null', () {
      const surface = NoopReaderSurface();

      expect(surface.foliate, isNull);
      expect(surface.pdf, isNull);
    });

    test('所有指令為空操作、不拋例外，showTransientHighlight 回 false', () {
      const surface = NoopReaderSurface();
      const target = ReaderJumpTarget(
        cfi: 'epubcfi(/6/4!/4/2)',
        pdfPageIndex: 3,
        pdfRect: PercentRect(left: 0.1, top: 0.1, right: 0.5, bottom: 0.2),
      );

      surface.nextPage();
      surface.previousPage();
      surface.jumpTo(target);
      surface.clearTransientHighlight();
      surface.clearSelection();
      surface.suspendSelection();
      surface.restoreSelection();
      surface.refreshAnnotations(
        highlights: const [],
        notes: const [],
        tokens: _tokens,
      );

      expect(surface.showTransientHighlight(target), isFalse);
    });
  });
}
