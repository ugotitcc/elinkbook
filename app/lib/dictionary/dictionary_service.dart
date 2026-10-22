// app/lib/dictionary/dictionary_service.dart
import 'dictionary_settings_repository.dart';
import 'lookup_text_normalizer.dart';
import 'mdx_resource.dart';
import 'models/dictionary_entry.dart';
import 'models/dictionary_source.dart';
import 'models/lookup_request.dart';
import 'models/lookup_result.dart';
import 'providers/local_dictionary_provider.dart';
import 'providers/mdx_dictionary_provider.dart';
import 'providers/online_dictionary_provider.dart';
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
/// 本機字典依優先順序在前，線上來源（若已同意且開啟）最後一段。
class DictionaryService {
  DictionaryService({
    required DictionaryStore store,
    MdxReaderPool? mdxPool,
    OnlineDictionaryProvider? onlineProvider,
    DictionarySettingsRepository? settings,
    Future<bool> Function()? isNetworkAvailable,
  })  : _store = DictionaryStoreProvider(() async => store),
        _mdxPool = mdxPool,
        _onlineProvider = onlineProvider,
        _settings = settings,
        _isNetworkAvailable = isNetworkAvailable;

  /// 延遲開啟：第一次 [lookup]（且選取有效）才呼叫 [openStore]，之後重用。
  /// 開啟失敗時 [lookup] 丟出例外、不快取失敗，下一次查詢會重試。
  /// 字典是邊緣功能，開檔失敗不應擋住 App 啟動。
  DictionaryService.lazy(
    Future<DictionaryStore> Function() openStore, {
    MdxReaderPool? mdxPool,
    OnlineDictionaryProvider? onlineProvider,
    DictionarySettingsRepository? settings,
    Future<bool> Function()? isNetworkAvailable,
  })  : _store = DictionaryStoreProvider(openStore),
        _mdxPool = mdxPool,
        _onlineProvider = onlineProvider,
        _settings = settings,
        _isNetworkAvailable = isNetworkAvailable;

  /// 與其他服務（例如字典管理）共用同一個 [provider]，資料庫只開一次。
  DictionaryService.fromProvider(
    DictionaryStoreProvider provider, {
    MdxReaderPool? mdxPool,
    OnlineDictionaryProvider? onlineProvider,
    DictionarySettingsRepository? settings,
    Future<bool> Function()? isNetworkAvailable,
  })  : _store = provider,
        _mdxPool = mdxPool,
        _onlineProvider = onlineProvider,
        _settings = settings,
        _isNetworkAvailable = isNetworkAvailable;

  final DictionaryStoreProvider _store;

  /// MDX 來源的 reader 池；未提供時 MDX 分段一律回 `failed`。
  final MdxReaderPool? _mdxPool;

  /// 線上查詞來源；與 [_settings] 任一為 `null` 時完全不做線上查詢。
  final OnlineDictionaryProvider? _onlineProvider;

  /// 線上同意狀態；每次查詢都重讀，撤回立即生效。
  final DictionarySettingsRepository? _settings;

  /// `null` 視為有網路；只擋「完全沒有連線」，其餘交給 provider 逾時。
  final Future<bool> Function()? _isNetworkAvailable;

  Future<DictionaryLookupResponse> lookup(String selectedText) async {
    final selection = normalizeLookupSelection(selectedText);
    if (selection is RejectedSelection) {
      return LookupRejected(selection.problem);
    }
    selection as NormalizedSelection;

    final request = LookupRequest(selection.text);
    // 先啟動線上查詢（不 await），與本機查詢同時進行。
    final online = _startOnlineLookup(selection.charType, request);
    final allowed = _allowedLanguages(selection.charType);
    final store = await _store();
    // 不快取來源清單：設定畫面改動後立即生效。
    final sources = await store.listSources(enabledOnly: true);
    final outcomes = <ProviderOutcome>[];
    for (final source in sources) {
      if (!allowed.contains(_primaryLang(source.sourceLang))) continue;
      outcomes.add(await _lookupOne(store, source, request));
    }
    if (online != null) {
      final outcome = await online;
      // 沒有本機字典又未同意時不附 skipped，面板才會顯示「尚未匯入字典」。
      final suppress = outcome.status == OutcomeStatus.skipped && sources.isEmpty;
      if (!suppress) outcomes.add(outcome);
    }
    return LookupCompleted(
      result: LookupResult(request: request, outcomes: outcomes),
      hasEnabledDictionary: sources.isNotEmpty,
    );
  }

  /// 只有含 CJK 的選字才查線上；純拉丁選字沒有線上分段。
  Future<ProviderOutcome>? _startOnlineLookup(
    SelectionCharType charType,
    LookupRequest request,
  ) {
    final provider = _onlineProvider;
    final settings = _settings;
    if (charType == SelectionCharType.latin ||
        provider == null ||
        settings == null) {
      return null;
    }
    return _lookupOnline(provider, settings, request);
  }

  /// 永不丟例外：任何失敗都變成一個分段狀態。
  Future<ProviderOutcome> _lookupOnline(
    OnlineDictionaryProvider provider,
    DictionarySettingsRepository settings,
    LookupRequest request,
  ) async {
    // 每次重新讀：撤回同意後下一次查詢立即生效。
    DateTime? consentAt;
    try {
      consentAt = await settings.loadOnlineConsentAt();
    } catch (_) {
      // 讀不到同意狀態就當作未同意：寧可不連網，也不讓整個查詢丟例外。
      consentAt = null;
    }
    if (consentAt == null) {
      return ProviderOutcome(
        providerId: provider.id,
        displayName: provider.displayName,
        status: OutcomeStatus.skipped,
      );
    }

    final isNetworkAvailable = _isNetworkAvailable;
    if (isNetworkAvailable != null) {
      bool available;
      try {
        available = await isNetworkAvailable();
      } catch (_) {
        // 連線狀態判斷失敗時不擋，交給 provider 的逾時。
        available = true;
      }
      if (!available) {
        return ProviderOutcome(
          providerId: provider.id,
          displayName: provider.displayName,
          status: OutcomeStatus.failed,
          errorCode: 'offline',
        );
      }
    }

    try {
      return await provider.lookup(request);
    } catch (_) {
      return ProviderOutcome(
        providerId: provider.id,
        displayName: provider.displayName,
        status: OutcomeStatus.failed,
        errorCode: 'network',
      );
    }
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

  /// 讀取 MDX 字典成對的 `.mdd` 資源（例如圖片）。
  ///
  /// 來源不存在、來源非 MDX 格式、未提供 `_mdxPool`、或讀取過程拋出任何例外時，
  /// 一律回傳 `null`，不拋出例外。
  Future<MdxResource?> readMdxResource(String sourceId, String url) async {
    final pool = _mdxPool;
    if (pool == null) return null;

    try {
      final store = await _store();
      final sources = await store.listSources();
      DictionarySource? source;
      for (final candidate in sources) {
        if (candidate.id == sourceId) {
          source = candidate;
          break;
        }
      }
      if (source == null || source.format != DictionaryFormat.mdx) {
        return null;
      }
      return await pool.use(source.id, source.storagePath, (reader) {
        return reader.readResource(url);
      });
    } catch (_) {
      return null;
    }
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
