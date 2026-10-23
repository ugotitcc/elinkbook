import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/epub_decoration.dart';
import 'package:elinkbook/reader/foliate_reader_surface.dart';
import 'package:elinkbook/reader/foliate_reader_view.dart';
import 'package:elinkbook/reader/highlight.dart';
import 'package:elinkbook/reader/highlight_style.dart';
import 'package:elinkbook/reader/note.dart';
import 'package:elinkbook/reader/percent_rect.dart';
import 'package:elinkbook/reader/reader_jump_target.dart';
import 'package:elinkbook/reader/reader_surface.dart';
import 'package:elinkbook/theme/elink_tokens.dart';

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
  group('FoliateReaderSurface：facet', () {
    test('foliate facet 非 null、pdf facet 為 null', () {
      final ReaderSurface surface = FoliateReaderSurface();

      expect(surface.foliate, isNotNull);
      expect(surface.pdf, isNull);
    });

    test('viewKey 與傳入的 key 相同（過渡期沿用 ReaderScreen 既有的 key）', () {
      final key = GlobalKey<State<FoliateReaderView>>();
      final ReaderSurface surface = FoliateReaderSurface(viewKey: key);

      expect(identical(surface.foliate!.viewKey, key), isTrue);
    });

    test('未傳入 key 時自己建立一把', () {
      final ReaderSurface surface = FoliateReaderSurface();

      expect(surface.foliate!.viewKey, isA<GlobalKey<State<FoliateReaderView>>>());
    });
  });

  group('FoliateReaderSurface：View 尚未掛載', () {
    test('所有指令靜默忽略、不拋例外', () {
      final ReaderSurface surface = FoliateReaderSurface();

      surface.nextPage();
      surface.previousPage();
      surface.jumpTo(const ReaderJumpTarget(cfi: 'epubcfi(/6/4!/4/2)'));
      surface.jumpTo(const ReaderJumpTarget(progression: 0.5));
      surface.jumpTo(const ReaderJumpTarget(pdfPageIndex: 3));
      surface.clearTransientHighlight();
      surface.clearSelection();
      surface.suspendSelection();
      surface.restoreSelection();
      surface.refreshAnnotations(highlights: const [], notes: const [], tokens: _tokens);
      surface.foliate!.clearTtsHighlight();
      surface.foliate!.showTtsHighlight('epubcfi(/6/4)', vertical: false, einkMode: false);
    });

    test('查詢回傳預設值：目錄空清單、TTS 段落空清單、起始段 0', () async {
      final ReaderSurface surface = FoliateReaderSurface();

      expect(await surface.foliate!.loadTableOfContents(), isEmpty);
      expect(await surface.foliate!.loadTtsSegments(0), isEmpty);
      expect(await surface.foliate!.lookupSegmentByCfi('epubcfi(/6/4)', const []), 0);
    });

    test('showTransientHighlight：有 cfi 回 true（沿用 applyTo 語意）、沒有 cfi 回 false', () {
      final ReaderSurface surface = FoliateReaderSurface();

      expect(surface.showTransientHighlight(const ReaderJumpTarget(cfi: 'epubcfi(/6/4!/4/2)')), isTrue);
      expect(surface.showTransientHighlight(const ReaderJumpTarget()), isFalse);
      expect(
        surface.showTransientHighlight(
          const ReaderJumpTarget(
            pdfPageIndex: 3,
            pdfRect: PercentRect(left: 0.1, top: 0.1, right: 0.5, bottom: 0.2),
          ),
        ),
        isFalse,
      );
    });
  });

  group('buildEpubDecorations：劃線／備註 → EpubDecoration', () {
    test('劃線帶樣式色與 isUnderline；有 locator 才轉換', () {
      final decorations = buildEpubDecorations(
        highlights: const [
          Highlight(id: 'h1', bookId: 'b', style: HighlightStyle.highlighterYellow, epubLocatorJson: '{"cfi":"a"}'),
          Highlight(id: 'h2', bookId: 'b', style: HighlightStyle.underline, epubLocatorJson: '{"cfi":"b"}'),
          Highlight(id: 'h3', bookId: 'b', style: HighlightStyle.highlighterBlue),
        ],
        notes: const [],
        tokens: _tokens,
      );

      expect(decorations.map((d) => d.id), ['highlight:h1', 'highlight:h2']);
      expect(decorations[0].tint, _tokens.highlightYellow.toARGB32());
      expect(decorations[0].isUnderline, isFalse);
      expect(decorations[1].isUnderline, isTrue);
    });

    test('只有備註（highlightId 為 null）才產生備註裝飾，使用 noteOnlyTint', () {
      final decorations = buildEpubDecorations(
        highlights: const [],
        notes: const [
          Note(id: 'n1', bookId: 'b', text: 'x', epubLocatorJson: '{"cfi":"a"}'),
          Note(id: 'n2', bookId: 'b', text: 'x', highlightId: 'h1', epubLocatorJson: '{"cfi":"b"}'),
          Note(id: 'n3', bookId: 'b', text: 'x'),
        ],
        tokens: _tokens,
      );

      expect(decorations.map((d) => d.id), ['note:n1']);
      expect(decorations.single.tint, noteOnlyTint.toARGB32());
    });

    test('劃線在前、備註在後（與 reader_screen 既有順序一致）', () {
      final decorations = buildEpubDecorations(
        highlights: const [
          Highlight(id: 'h1', bookId: 'b', style: HighlightStyle.highlighterYellow, epubLocatorJson: '{"cfi":"a"}'),
        ],
        notes: const [
          Note(id: 'n1', bookId: 'b', text: 'x', epubLocatorJson: '{"cfi":"b"}'),
        ],
        tokens: _tokens,
      );

      expect(decorations, isA<List<EpubDecoration>>());
      expect(decorations.map((d) => d.id), ['highlight:h1', 'note:n1']);
    });
  });
}
