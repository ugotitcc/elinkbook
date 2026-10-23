import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:elinkbook/l10n/app_localizations.dart';
import 'package:elinkbook/reader/highlight.dart';
import 'package:elinkbook/reader/highlight_style.dart';
import 'package:elinkbook/reader/note.dart';
import 'package:elinkbook/reader/pdf_page_info.dart';
import 'package:elinkbook/reader/pdf_page_turn_animation.dart';
import 'package:elinkbook/reader/pdf_reader_surface.dart';
import 'package:elinkbook/reader/pdf_reader_view.dart';
import 'package:elinkbook/reader/percent_rect.dart';
import 'package:elinkbook/reader/reader_jump_target.dart';
import 'package:elinkbook/reader/reader_surface.dart';
import 'package:elinkbook/theme/elink_tokens.dart';

import '../support/pump_until_pdf_ready.dart';

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

const _rect = PercentRect(left: 0.1, top: 0.1, right: 0.5, bottom: 0.2);

void main() {
  setUp(() => pdfrxInitialize());

  group('PdfReaderSurface：facet', () {
    test('pdf facet 非 null、foliate facet 為 null', () {
      final ReaderSurface surface = PdfReaderSurface();

      expect(surface.pdf, isNotNull);
      expect(surface.foliate, isNull);
    });

    test('viewKey 與傳入的 key 相同（過渡期沿用 ReaderScreen 既有的 key）', () {
      final key = GlobalKey<State<PdfReaderView>>();
      final ReaderSurface surface = PdfReaderSurface(viewKey: key);

      expect(identical(surface.pdf!.viewKey, key), isTrue);
    });
  });

  group('PdfReaderSurface：View 尚未掛載', () {
    test('所有指令靜默忽略、不拋例外；選取收起／還原為空操作', () {
      final ReaderSurface surface = PdfReaderSurface();

      surface.nextPage();
      surface.previousPage();
      surface.jumpTo(const ReaderJumpTarget(pdfPageIndex: 3));
      surface.jumpTo(const ReaderJumpTarget(cfi: 'epubcfi(/6/4!/4/2)'));
      surface.clearTransientHighlight();
      surface.clearSelection();
      surface.suspendSelection();
      surface.restoreSelection();
      surface.refreshAnnotations(highlights: const [], notes: const [], tokens: _tokens);
      surface.pdf!.cancelActiveSelectionDrag();
      surface.pdf!.setSearchHighlights(const [], currentIndex: null);
      surface.pdf!.jumpToPageAtRect(2, _rect);
    });

    test('查詢回傳預設值：目錄與搜尋為空清單、縮圖為 null', () async {
      final ReaderSurface surface = PdfReaderSurface();

      expect(await surface.pdf!.loadTableOfContents(), isEmpty);
      expect(await surface.pdf!.search('abc'), isEmpty);
      expect(await surface.pdf!.renderThumbnail(0, maxWidth: 100), isNull);
    });

    test('showTransientHighlight：頁碼與座標皆有才回 true（沿用 applyTo 語意）', () {
      final ReaderSurface surface = PdfReaderSurface();

      expect(
        surface.showTransientHighlight(const ReaderJumpTarget(pdfPageIndex: 3, pdfRect: _rect)),
        isTrue,
      );
      expect(surface.showTransientHighlight(const ReaderJumpTarget(pdfPageIndex: 3)), isFalse);
      expect(surface.showTransientHighlight(const ReaderJumpTarget(pdfRect: _rect)), isFalse);
      expect(surface.showTransientHighlight(const ReaderJumpTarget(cfi: 'epubcfi(/6/4)')), isFalse);
    });
  });

  group('buildPdfAnnotationDecorations：劃線／備註 → PdfAnnotationDecoration', () {
    test('劃線需頁碼與座標皆有；帶樣式色與 isUnderline', () {
      final decorations = buildPdfAnnotationDecorations(
        highlights: const [
          Highlight(id: 'h1', bookId: 'b', style: HighlightStyle.highlighterYellow, pdfPageIndex: 1, pdfRect: _rect),
          Highlight(id: 'h2', bookId: 'b', style: HighlightStyle.underline, pdfPageIndex: 2, pdfRect: _rect),
          Highlight(id: 'h3', bookId: 'b', style: HighlightStyle.highlighterBlue, pdfPageIndex: 3),
          Highlight(id: 'h4', bookId: 'b', style: HighlightStyle.highlighterBlue, pdfRect: _rect),
        ],
        notes: const [],
        tokens: _tokens,
      );

      expect(decorations.map((d) => d.pageIndex), [1, 2]);
      expect(decorations[0].tint, _tokens.highlightYellow.toARGB32());
      expect(decorations[0].isUnderline, isFalse);
      expect(decorations[1].isUnderline, isTrue);
    });

    test('只有備註（highlightId 為 null）才產生備註裝飾，使用 noteOnlyTint；劃線在前、備註在後', () {
      final decorations = buildPdfAnnotationDecorations(
        highlights: const [
          Highlight(id: 'h1', bookId: 'b', style: HighlightStyle.highlighterYellow, pdfPageIndex: 1, pdfRect: _rect),
        ],
        notes: const [
          Note(id: 'n1', bookId: 'b', text: 'x', pdfPageIndex: 4, pdfRect: _rect),
          Note(id: 'n2', bookId: 'b', text: 'x', highlightId: 'h1', pdfPageIndex: 5, pdfRect: _rect),
          Note(id: 'n3', bookId: 'b', text: 'x', pdfPageIndex: 6),
        ],
        tokens: _tokens,
      );

      expect(decorations.map((d) => d.pageIndex), [1, 4]);
      expect(decorations.last.tint, noteOnlyTint.toARGB32());
    });
  });

  testWidgets('PdfReaderSurface：已掛載時，翻頁與跳頁指令送達 View', (tester) async {
    final key = GlobalKey<State<PdfReaderView>>();
    final ReaderSurface surface = PdfReaderSurface(viewKey: key);
    var renderedCount = 0;
    PdfPageInfo? lastPageInfo;

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: PdfReaderView(
          key: key,
          filePath: 'test/fixtures/sample_multi_page.pdf',
          onPageRendered: () => renderedCount++,
          onError: (_) {},
          onPageChanged: (info) => lastPageInfo = info,
          pdfPageTurnAnimation: PdfPageTurnAnimation.none,
        ),
      ),
    );
    await pumpUntilPdfReady(tester, condition: () => renderedCount > 0);
    expect(lastPageInfo?.pageIndex, 0);

    surface.nextPage();
    await tester.pump();
    expect(lastPageInfo?.pageIndex, 1);

    surface.previousPage();
    await tester.pump();
    expect(lastPageInfo?.pageIndex, 0);

    const jumpTarget = ReaderJumpTarget(pdfPageIndex: 2);
    surface.jumpTo(jumpTarget);
    await tester.pump();
    expect(lastPageInfo?.pageIndex, 2);

    // 暫態高亮的畫面呈現由 PdfReaderView 自己的測試保障（pdf_reader_view_paginated_test）；
    // 這裡只確認指令不拋例外、回傳值沿用 applyTo 語意。
    const highlightTarget = ReaderJumpTarget(pdfPageIndex: 0, pdfRect: _rect);
    expect(surface.showTransientHighlight(highlightTarget), isTrue);
    surface.clearTransientHighlight();
  });
}
