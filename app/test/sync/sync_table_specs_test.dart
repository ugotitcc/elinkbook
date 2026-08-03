import 'package:flutter_test/flutter_test.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/sync/sync_table_specs.dart';

void main() {
  group('bookmarksSyncSpec', () {
    test('buildPushFields 從本機列取出對應的推送欄位', () {
      final result = bookmarksSyncSpec.buildPushFields({
        'id': 'bm1',
        'book_id': 'b1',
        'name': '第一章',
        'epub_locator_json': '{"href":"/c1.xhtml"}',
        'progression': 0.1,
        'pdf_page_index': null,
        'updated_at': 1000,
        'deleted_at': null,
      });

      expect(result, {
        'name': '第一章',
        'epub_locator_json': '{"href":"/c1.xhtml"}',
        'progression': 0.1,
        'pdf_page_index': null,
      });
    });

    test('extractRawFields 從 RecordModel 取出原始欄位（未正規化）', () {
      final remote = RecordModel({
        'name': '第一章',
        'epub_locator_json': '',
        'progression': 0,
        'pdf_page_index': 5,
      });

      final result = bookmarksSyncSpec.extractRawFields(remote);

      expect(result['name'], '第一章');
      expect(result['epub_locator_json'], '');
      expect(result['progression'], 0);
      expect(result['pdf_page_index'], 5);
    });

    test('buildLocalFields 對 EPUB 格式：採用 progression，pdf_page_index 一律 null', () {
      final result = bookmarksSyncSpec.buildLocalFields({
        'name': '第一章',
        'epub_locator_json': '',
        'progression': 0,
        'pdf_page_index': 5,
      }, BookFileFormat.epub);

      expect(result['name'], '第一章');
      expect(result['epub_locator_json'], isNull, reason: '空字串正規化為 null');
      expect(result['progression'], 0.0, reason: '真正的 0.0 進度值，不因為是 0 就被丟棄');
      expect(result['pdf_page_index'], isNull, reason: 'PDF 專屬欄位，EPUB 一律 null');
    });

    test('buildLocalFields 對 PDF 格式：採用 pdf_page_index，progression 一律 null', () {
      final result = bookmarksSyncSpec.buildLocalFields({
        'name': '封面',
        'epub_locator_json': null,
        'progression': 0,
        'pdf_page_index': 0,
      }, BookFileFormat.pdf);

      expect(result['pdf_page_index'], 0, reason: '真正的第 0 頁，不因為是 0 就被丟棄');
      expect(result['progression'], isNull, reason: 'EPUB 專屬欄位，PDF 一律 null');
    });
  });

  group('notesSyncSpec', () {
    test('buildPushFields 把本機 highlight_id 對應到 highlight_client_id', () {
      final result = notesSyncSpec.buildPushFields({
        'id': 'n1',
        'book_id': 'b1',
        'text': '備註內容',
        'epub_locator_json': null,
        'progression': 0.2,
        'highlight_id': 'h1',
        'pdf_page_index': null,
        'pdf_rect_json': null,
        'updated_at': 1000,
        'deleted_at': null,
      });

      expect(result['highlight_client_id'], 'h1');
    });

    test('buildLocalFields 把遠端 highlight_client_id 對應回本機 highlight_id', () {
      final result = notesSyncSpec.buildLocalFields({
        'text': '備註內容',
        'epub_locator_json': null,
        'progression': 0.2,
        'highlight_client_id': 'h1',
        'pdf_page_index': null,
        'pdf_rect_json': null,
      }, BookFileFormat.epub);

      expect(result['highlight_id'], 'h1');
    });

    test('buildLocalFields 的 highlight_id 為空字串時正規化為 null（不依賴書籍格式）', () {
      final result = notesSyncSpec.buildLocalFields({
        'text': '備註內容',
        'epub_locator_json': null,
        'progression': 0.2,
        'highlight_client_id': '',
        'pdf_page_index': null,
        'pdf_rect_json': null,
      }, BookFileFormat.epub);

      expect(result['highlight_id'], isNull);
    });
  });

  group('highlightsSyncSpec', () {
    test('buildLocalFields 對 PDF 格式：pdf_rect_json 空字串正規化為 null', () {
      final result = highlightsSyncSpec.buildLocalFields({
        'style': 'underline',
        'epub_locator_json': null,
        'progression': 0,
        'pdf_page_index': 3,
        'pdf_rect_json': '',
      }, BookFileFormat.pdf);

      expect(result['style'], 'underline');
      expect(result['pdf_rect_json'], isNull);
      expect(result['pdf_page_index'], 3);
    });
  });
}
