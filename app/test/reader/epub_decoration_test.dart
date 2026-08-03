import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/epub_decoration.dart';

void main() {
  test('EpubDecoration.forHighlight／forNote 產生正確的 id 編碼與 wire 格式', () {
    final highlight = EpubDecoration.forHighlight(
      highlightId: 'h12',
      locatorJson: '{"href":"/c1.xhtml"}',
      tint: 0x73FDE047,
      isUnderline: false,
    );
    expect(highlight.id, 'highlight:h12');
    expect(highlight.toWire()['isUnderline'], isFalse);

    final note = EpubDecoration.forNote(
      noteId: 'n7',
      locatorJson: '{"href":"/c2.xhtml"}',
      tint: 0x73D1D5DB,
    );
    expect(note.id, 'note:n7');
  });

  test('decodeAnnotationId 正確解析 "highlight:<id>"／"note:<id>"', () {
    expect(decodeAnnotationId('highlight:h12'), (kind: AnnotationKind.highlight, id: 'h12'));
    expect(decodeAnnotationId('note:n7'), (kind: AnnotationKind.note, id: 'n7'));
  });

  test('decodeAnnotationId 對格式不符的字串回傳 null（不拋出例外）', () {
    expect(decodeAnnotationId('malformed'), isNull);
    expect(decodeAnnotationId('highlight:'), isNull);
    expect(decodeAnnotationId('unknown-kind:1'), isNull);
  });
}
