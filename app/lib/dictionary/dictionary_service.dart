// app/lib/dictionary/dictionary_service.dart
import 'lookup_text_normalizer.dart';
import 'models/dictionary_entry.dart';
import 'models/dictionary_source.dart';
import 'models/lookup_request.dart';
import 'models/lookup_result.dart';
import 'providers/local_dictionary_provider.dart';
import 'providers/mdx_dictionary_provider.dart';
import 'storage/dictionary_store.dart';
import 'storage/dictionary_store_provider.dart';
import 'storage/mdx_reader_pool.dart';

/// [DictionaryService.lookup] 的回傳。用型別區分「選取無效」與「查詢完成」，
/// 不用例外傳遞預期內的情況。
sealed class DictionaryLookupResponse {
  const DictionaryLookupResponse();
}

/// 選取無效，沒有查任何字典。
final class LookupRejected extends DictionaryLookupResponse {
  const LookupRejected(this.problem);

  final SelectionProblem problem;
}

/// 查詢完成。[hasEnabledDictionary] 區分兩種「outcomes 為空」：沒有任何
/// 啟用中的字典（面板顯示「尚未匯入字典」）／有字典但都不適用這段文字
/// （面板顯示「沒有適用於這段文字的字典」）。
final class LookupCompleted extends DictionaryLookupResponse {
  const LookupCompleted({
    required this.result,
    required this.hasEnabledDictionary,
  });

  final LookupResult result;

  /// `listSources(enabledOnly: true)` 是否非空。
  final bool hasEnabledDictionary;
}

/// 查詢入口：選字處理 → 依文字類型挑字典 → 逐本查詢並組裝結果。
/// 目前只查本機字典（線上字典是後續 Issue）。
class DictionaryService {
  DictionaryService({required DictionaryStore store, MdxReaderPool? mdxPool})
      : _store = DictionaryStoreProvider(() async => store),
        _mdxPool = mdxPool;

  /// 延遲開啟：第一次 [lookup]（且選取有效）才呼叫 [openStore]，之後重用。
  /// 開啟失敗時 [lookup] 丟出例外、不快取失敗，下一次查詢會重試。
  /// 字典是邊緣功能，開檔失敗不應擋住 App 啟動。
  DictionaryService.lazy(
    Future<DictionaryStore> Function() openStore, {
    MdxReaderPool? mdxPool,
  })  : _store = DictionaryStoreProvider(openStore),
        _mdxPool = mdxPool;

  /// 與其他服務（例如字典管理）共用同一個 [provider]，資料庫只開一次。
  DictionaryService.fromProvider(
    DictionaryStoreProvider provider, {
    MdxReaderPool? mdxPool,
  })  : _store = provider,
        _mdxPool = mdxPool;

  final DictionaryStoreProvider _store;

  /// MDX 來源的 reader 池；未提供時 MDX 分段一律回 `failed`。
  final MdxReaderPool? _mdxPool;

  Future<DictionaryLookupResponse> lookup(String selectedText) async {
    final selection = normalizeLookupSelection(selectedText);
    if (selection is RejectedSelection) {
      return LookupRejected(selection.problem);
    }
    selection as NormalizedSelection;

    final request = LookupRequest(selection.text);
    final allowed = _allowedLanguages(selection.charType);
    final store = await _store();
    // 不快取來源清單：設定畫面改動後立即生效。
    final sources = await store.listSources(enabledOnly: true);
    final outcomes = <ProviderOutcome>[];
    for (final source in sources) {
      if (!allowed.contains(_primaryLang(source.sourceLang))) continue;
      outcomes.add(await _lookupOne(store, source, request));
    }
    return LookupCompleted(
      result: LookupResult(request: request, outcomes: outcomes),
      hasEnabledDictionary: sources.isNotEmpty,
    );
  }

  /// 交叉參照用：只查指定來源，不做語言（方向）過濾。
  /// 來源不存在、查無或該段失敗都回空清單。
  Future<List<DictionaryEntry>> lookupInSource(
    String sourceId,
    String word,
  ) async {
    final store = await _store();
    // 與 [lookup] 一樣不快取來源清單。
    final sources = await store.listSources();
    DictionarySource? source;
    for (final candidate in sources) {
      if (candidate.id == sourceId) {
        source = candidate;
        break;
      }
    }
    if (source == null) return const [];
    final outcome = await _lookupOne(store, source, LookupRequest(word));
    return outcome.status == OutcomeStatus.found ? outcome.entries : const [];
  }

  /// 任何例外只影響該分段，不影響其他字典。
  Future<ProviderOutcome> _lookupOne(
    DictionaryStore store,
    DictionarySource source,
    LookupRequest request,
  ) async {
    if (source.format == DictionaryFormat.mdx) {
      final pool = _mdxPool;
      if (pool == null) {
        return ProviderOutcome(
          providerId: source.id,
          displayName: source.name,
          status: OutcomeStatus.failed,
          errorCode: 'mdxUnavailable',
        );
      }
      try {
        return await MdxDictionaryProvider(pool: pool, source: source)
            .lookup(request);
      } catch (_) {
        return ProviderOutcome(
          providerId: source.id,
          displayName: source.name,
          status: OutcomeStatus.failed,
          errorCode: 'localLookupFailed',
        );
      }
    }

    try {
      return await LocalDictionaryProvider(store: store, source: source)
          .lookup(request);
    } catch (_) {
      return ProviderOutcome(
        providerId: source.id,
        displayName: source.name,
        status: OutcomeStatus.failed,
        errorCode: 'localLookupFailed',
      );
    }
  }

  Set<String> _allowedLanguages(SelectionCharType type) => switch (type) {
        SelectionCharType.latin => const {'en'},
        SelectionCharType.cjk => const {'zh'},
        SelectionCharType.mixed => const {'zh', 'en'},
      };

  /// 只看語言碼第一段：`zh-Hant`、`zh` 都算 `zh`；`en-US` 算 `en`。
  String _primaryLang(String lang) =>
      lang.toLowerCase().split(RegExp(r'[-_]')).first;
}
