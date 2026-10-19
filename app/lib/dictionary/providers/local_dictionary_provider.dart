// app/lib/dictionary/providers/local_dictionary_provider.dart
import '../lookup_candidates.dart';
import '../models/dictionary_source.dart';
import '../models/lookup_request.dart';
import '../models/lookup_result.dart';
import '../storage/dictionary_store.dart';
import 'dictionary_provider.dart';

/// 查一本已匯入的本機字典（一本字典一個實例）。
///
/// 依 [DictionarySource.sourceLang] 產生候選清單，依 `headword_norm` 去重
/// （JSON、CSV、CC-CEDICT 的比對本來就不分大小寫），依序查詢，第一個有結果
/// 的候選就停。
class LocalDictionaryProvider implements DictionaryProvider {
  LocalDictionaryProvider({
    required DictionaryStore store,
    required DictionarySource source,
  })  : _store = store,
        _source = source;

  final DictionaryStore _store;
  final DictionarySource _source;

  @override
  String get id => _source.id;

  @override
  Future<ProviderOutcome> lookup(LookupRequest request) async {
    final candidates = dedupeByHeadwordNorm(
      lookupCandidates(request.word, lang: _source.sourceLang),
    );
    for (final candidate in candidates) {
      final entries = await _store.lookup(_source.id, candidate);
      if (entries.isNotEmpty) {
        return ProviderOutcome(
          providerId: id,
          displayName: _source.name,
          status: OutcomeStatus.found,
          entries: entries,
        );
      }
    }
    return ProviderOutcome(
      providerId: id,
      displayName: _source.name,
      status: OutcomeStatus.notFound,
    );
  }
}
