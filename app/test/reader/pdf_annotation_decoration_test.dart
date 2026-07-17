import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/pdf_annotation_decoration.dart';
import 'package:elinkbook/reader/percent_rect.dart';

void main() {
  test('forHighlight／forNote 產生正確的 wire 格式', () {
    const rect = PercentRect(left: 0.1, top: 0.2, right: 0.3, bottom: 0.4);

    final highlight = PdfAnnotationDecoration.forHighlight(
      pageIndex: 2,
      rect: rect,
      tint: 0x73FDE047,
      isUnderline: false,
    );
    expect(highlight.toWire(), {
      'pageIndex': 2,
      'left': 0.1,
      'top': 0.2,
      'right': 0.3,
      'bottom': 0.4,
      'tint': 0x73FDE047,
      'isUnderline': false,
      'isNoteOnly': false,
    });

    final note = PdfAnnotationDecoration.forNote(pageIndex: 5, rect: rect, tint: 0x73D1D5DB);
    expect(note.toWire()['isNoteOnly'], isTrue);
    expect(note.toWire()['isUnderline'], isFalse);
  });
}
