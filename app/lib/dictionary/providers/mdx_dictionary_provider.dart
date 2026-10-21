// MdxDictionaryProvider：把一本 MDX 字典接上 DictionaryProvider 介面
// （epic-63 Issue 6a Task 6）。
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../lookup_candidates.dart';
import '../mdx_css_inline.dart';
import '../models/dictionary_entry.dart';
import '../models/dictionary_source.dart';
import '../models/lookup_request.dart';
import '../models/lookup_result.dart';
import '../storage/mdx_reader.dart';
import '../storage/mdx_reader_pool.dart';
import 'dictionary_provider.dart';

final _cssTriggerPattern = RegExp(r'<link|@import', caseSensitive: false);

/// 查一本 MDX 字典。詞條內容是 HTML，交給面板的 WebView 顯示。
class MdxDictionaryProvider implements DictionaryProvider {
  MdxDictionaryProvider({
    required MdxReaderPool pool,
    required DictionarySource source,
  })  : _pool = pool,
        _source = source;

  final MdxReaderPool _pool;
  final DictionarySource _source;

  @override
  String get id => _source.id;

  @override
  Future<ProviderOutcome> lookup(LookupRequest request) async {
    try {
      // 走 `use` 而不是 `acquire`：查詢期間池不會把這個 reader 關掉。
      return await _pool.use(
        _source.id,
        _source.storagePath,
        (reader) => _lookupWith(request, reader),
      );
    } on MdxException catch (error) {
      // 壞檔只讓這一段失敗，不影響其他字典；errorCode 供 UI 轉譯。
      return ProviderOutcome(
        providerId: id,
        displayName: _source.name,
        status: OutcomeStatus.failed,
        errorCode: error.kind.name,
      );
    }
  }

  Future<ProviderOutcome> _lookupWith(
    LookupRequest request,
    MdxReader reader,
  ) async {
    var candidates = lookupCandidates(
      request.word,
      lang: _source.sourceLang,
    );
    // 審查 I-3：區分大小寫的字典不能把 `apple`／`Apple` 合成一個候選，
    // 否則只收其中一種寫法的字典會查不到。不分大小寫的來源才去重。
    if (!reader.meta.keyCaseSensitive) {
      candidates = dedupeByHeadwordNorm(candidates);
    }

    for (final candidate in candidates) {
      final bodies = await reader.lookupAll(candidate);
      if (bodies.isEmpty) continue;

      var processedBodies = bodies;
      if (bodies.any((b) => _cssTriggerPattern.hasMatch(b))) {
        final cssMap = await _loadCssFiles(p.dirname(_source.storagePath));
        processedBodies = [
          for (final body in bodies) inlineLinkedCss(body, cssMap),
        ];
      }

      return ProviderOutcome(
        providerId: id,
        displayName: _source.name,
        status: OutcomeStatus.found,
        entries: [
          for (final body in processedBodies)
            DictionaryEntry(
              sourceId: _source.id,
              headword: candidate,
              body: body,
              bodyKind: EntryBodyKind.html,
            ),
        ],
      );
    }
    return ProviderOutcome(
      providerId: id,
      displayName: _source.name,
      status: OutcomeStatus.notFound,
    );
  }

  Future<Map<String, String>> _loadCssFiles(String dirPath) async {
    final cssMap = <String, String>{};
    try {
      final dir = Directory(dirPath);
      if (!await dir.exists()) return cssMap;
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is! File) continue;
        final name = p.basename(entity.path).toLowerCase();
        if (!name.endsWith('.css')) continue;
        try {
          final bytes = await entity.readAsBytes();
          cssMap[name] = utf8.decode(bytes, allowMalformed: true);
        } catch (_) {
          // 單一檔案讀取失敗略過，不影響其他檔案或查詢。
        }
      }
    } catch (_) {
      // 目錄列舉或權限問題等，回傳已讀到的或空 map。
    }
    return cssMap;
  }
}
