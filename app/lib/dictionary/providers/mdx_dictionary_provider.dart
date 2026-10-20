// MdxDictionaryProvider：把一本 MDX 字典接上 DictionaryProvider 介面
// （epic-63 Issue 6a Task 6）。
import '../lookup_candidates.dart';
import '../models/dictionary_entry.dart';
import '../models/dictionary_source.dart';
import '../models/lookup_request.dart';
import '../models/lookup_result.dart';
import '../storage/mdx_reader.dart';
import '../storage/mdx_reader_pool.dart';
import 'dictionary_provider.dart';

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
      final reader = await _pool.acquire(_source.id, _source.storagePath);

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
        return ProviderOutcome(
          providerId: id,
          displayName: _source.name,
          status: OutcomeStatus.found,
          entries: [
            for (final body in bodies)
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
}
