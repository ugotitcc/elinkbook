import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/book_format.dart';
import 'package:elinkbook/reader/foliate_reader_surface.dart';
import 'package:elinkbook/reader/pdf_reader_surface.dart';
import 'package:elinkbook/reader/reader_surface.dart';
import 'package:elinkbook/reader/reader_surface_factory.dart';

void main() {
  group('defaultReaderSurfaceFactory', () {
    test('PDF → PdfReaderSurface（只有 pdf facet）', () {
      final surface = defaultReaderSurfaceFactory(BookFormat.pdf);

      expect(surface, isA<PdfReaderSurface>());
      expect(surface.pdf, isNotNull);
      expect(surface.foliate, isNull);
    });

    test('EPUB／KF8／CBZ／TXT／MD → FoliateReaderSurface（只有 foliate facet）', () {
      for (final format in [
        BookFormat.epub,
        BookFormat.azw3,
        BookFormat.cbz,
        BookFormat.txt,
        BookFormat.md,
      ]) {
        final surface = defaultReaderSurfaceFactory(format);

        expect(surface, isA<FoliateReaderSurface>(), reason: '$format');
        expect(surface.foliate, isNotNull, reason: '$format');
        expect(surface.pdf, isNull, reason: '$format');
      }
    });

    test('unknown → NoopReaderSurface（兩個 facet 皆為 null）', () {
      final surface = defaultReaderSurfaceFactory(BookFormat.unknown);

      expect(surface, isA<NoopReaderSurface>());
      expect(surface.foliate, isNull);
      expect(surface.pdf, isNull);
    });

    test('每次呼叫都建立新的 surface（一本書一個，不共用 GlobalKey）', () {
      final a = defaultReaderSurfaceFactory(BookFormat.pdf);
      final b = defaultReaderSurfaceFactory(BookFormat.pdf);

      expect(identical(a, b), isFalse);
      expect(identical(a.pdf!.viewKey, b.pdf!.viewKey), isFalse);
    });
  });
}
