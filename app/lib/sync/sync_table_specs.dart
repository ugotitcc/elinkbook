import 'package:pocketbase/pocketbase.dart';

import '../library/models/library_enums.dart';
import 'sync_models.dart';

typedef PushFieldsBuilder = Map<String, Object?> Function(
    Map<String, Object?> localRow);
typedef RawFieldsExtractor = Map<String, Object?> Function(
    RecordModel remote);
typedef LocalFieldsBuilder = Map<String, Object?> Function(
    Map<String, Object?> rawFields, BookFileFormat format);

/// 單一 collection 的推送/下載欄位轉換設定（epic-8-sync Issue 4）。三張
/// 本機標註表欄位結構高度相似但不完全相同（見 spec.md「PocketBase
/// Collection Schema」），用這個設定物件取代三份幾乎重複的程式碼，避免
/// 過度抽象成通用反射框架。
class SyncTableSpec {
  final SyncCollection collection;
  final PushFieldsBuilder buildPushFields;
  final RawFieldsExtractor extractRawFields;
  final LocalFieldsBuilder buildLocalFields;

  const SyncTableSpec({
    required this.collection,
    required this.buildPushFields,
    required this.extractRawFields,
    required this.buildLocalFields,
  });
}

/// 空字串正規化為 null（PocketBase text 欄位未設值的零值是 `""`，見
/// plan-issue-4.md「與 spec.md／Issue 7 的落差說明」）。
String? _normalizeText(Object? raw) {
  if (raw == null || raw == '') return null;
  return raw as String;
}

final SyncTableSpec bookmarksSyncSpec = SyncTableSpec(
  collection: SyncCollection.bookmarks,
  buildPushFields: (row) => {
        'name': row['name'],
        'epub_locator_json': row['epub_locator_json'],
        'progression': row['progression'],
        'pdf_page_index': row['pdf_page_index'],
      },
  extractRawFields: (remote) => {
        'name': remote.data['name'],
        'epub_locator_json': remote.data['epub_locator_json'],
        'progression': remote.data['progression'],
        'pdf_page_index': remote.data['pdf_page_index'],
      },
  buildLocalFields: (raw, format) => {
        'name': raw['name'] as String,
        'epub_locator_json':
            format == BookFileFormat.pdf ? null : _normalizeText(raw['epub_locator_json']),
        'progression': format == BookFileFormat.pdf
            ? null
            : (raw['progression'] as num?)?.toDouble(),
        'pdf_page_index': format == BookFileFormat.pdf
            ? (raw['pdf_page_index'] as num?)?.toInt()
            : null,
      },
);

final SyncTableSpec highlightsSyncSpec = SyncTableSpec(
  collection: SyncCollection.highlights,
  buildPushFields: (row) => {
        'style': row['style'],
        'epub_locator_json': row['epub_locator_json'],
        'progression': row['progression'],
        'pdf_page_index': row['pdf_page_index'],
        'pdf_rect_json': row['pdf_rect_json'],
      },
  extractRawFields: (remote) => {
        'style': remote.data['style'],
        'epub_locator_json': remote.data['epub_locator_json'],
        'progression': remote.data['progression'],
        'pdf_page_index': remote.data['pdf_page_index'],
        'pdf_rect_json': remote.data['pdf_rect_json'],
      },
  buildLocalFields: (raw, format) => {
        'style': raw['style'] as String,
        'epub_locator_json':
            format == BookFileFormat.pdf ? null : _normalizeText(raw['epub_locator_json']),
        'progression': format == BookFileFormat.pdf
            ? null
            : (raw['progression'] as num?)?.toDouble(),
        'pdf_page_index': format == BookFileFormat.pdf
            ? (raw['pdf_page_index'] as num?)?.toInt()
            : null,
        'pdf_rect_json':
            format == BookFileFormat.pdf ? _normalizeText(raw['pdf_rect_json']) : null,
      },
);

final SyncTableSpec notesSyncSpec = SyncTableSpec(
  collection: SyncCollection.notes,
  buildPushFields: (row) => {
        'text': row['text'],
        'epub_locator_json': row['epub_locator_json'],
        'progression': row['progression'],
        'highlight_client_id': row['highlight_id'],
        'pdf_page_index': row['pdf_page_index'],
        'pdf_rect_json': row['pdf_rect_json'],
      },
  extractRawFields: (remote) => {
        'text': remote.data['text'],
        'epub_locator_json': remote.data['epub_locator_json'],
        'progression': remote.data['progression'],
        'highlight_client_id': remote.data['highlight_client_id'],
        'pdf_page_index': remote.data['pdf_page_index'],
        'pdf_rect_json': remote.data['pdf_rect_json'],
      },
  buildLocalFields: (raw, format) => {
        'text': raw['text'] as String,
        'epub_locator_json':
            format == BookFileFormat.pdf ? null : _normalizeText(raw['epub_locator_json']),
        'progression': format == BookFileFormat.pdf
            ? null
            : (raw['progression'] as num?)?.toDouble(),
        // 劃線的本機 id 現在就是全域唯一的 UUID，同步/本機共用同一個值，不需
        // 要額外轉換查表（見 spec.md「跨裝置參照設計」）；與書籍格式無關，
        // 一律嘗試正規化空字串。
        'highlight_id': _normalizeText(raw['highlight_client_id']),
        'pdf_page_index': format == BookFileFormat.pdf
            ? (raw['pdf_page_index'] as num?)?.toInt()
            : null,
        'pdf_rect_json':
            format == BookFileFormat.pdf ? _normalizeText(raw['pdf_rect_json']) : null,
      },
);

final Map<SyncCollection, SyncTableSpec> syncTableSpecs = {
  SyncCollection.bookmarks: bookmarksSyncSpec,
  SyncCollection.highlights: highlightsSyncSpec,
  SyncCollection.notes: notesSyncSpec,
};
