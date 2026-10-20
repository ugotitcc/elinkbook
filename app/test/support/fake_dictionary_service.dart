import 'package:elinkbook/dictionary/dictionary_service.dart';
import 'package:elinkbook/dictionary/models/dictionary_entry.dart';
import 'package:elinkbook/dictionary/models/lookup_request.dart';
import 'package:elinkbook/dictionary/models/lookup_result.dart';

/// 不碰資料庫的 [DictionaryService] 測試替身。
///
/// `lookup` 回傳建構子指定的 [response]（預設「沒有匯入任何字典」），並把每次
/// 呼叫的選取文字記錄在 [calls]，供測試斷言「查了幾次、查了什麼」。
class FakeDictionaryService implements DictionaryService {
  FakeDictionaryService({DictionaryLookupResponse? response})
      : response = response ?? _emptyResponse();

  /// 每次 `lookup` 回傳同一個回應；需要逐次不同時改傳 [responses]。
  DictionaryLookupResponse response;

  /// 依序回傳；用完後改回 [response]。最後一項會留在 [response]。
  List<DictionaryLookupResponse>? responses;

  /// 每次呼叫 `lookup` 的參數，依呼叫順序。
  final List<String> calls = [];

  /// 讓 `lookup` 丟出例外，驗證面板的 `snapshot.hasError` 路徑。
  Object? error;

  /// 每次 `lookupInSource` 的參數，依呼叫順序。
  final List<({String sourceId, String word})> lookupInSourceCalls = [];

  /// `lookupInSource` 的回傳；預設查無。
  List<DictionaryEntry> lookupInSourceResult = const [];

  /// 讓 `lookupInSource` 丟出例外。
  Object? lookupInSourceError;

  static DictionaryLookupResponse _emptyResponse() => LookupCompleted(
        result: const LookupResult(request: LookupRequest(''), outcomes: []),
        hasEnabledDictionary: false,
      );

  @override
  Future<DictionaryLookupResponse> lookup(String selectedText) async {
    calls.add(selectedText);
    if (error != null) throw error!;
    final queue = responses;
    if (queue != null && queue.isNotEmpty) {
      response = queue.removeAt(0);
    }
    return response;
  }

  @override
  Future<List<DictionaryEntry>> lookupInSource(
    String sourceId,
    String word,
  ) async {
    lookupInSourceCalls.add((sourceId: sourceId, word: word));
    if (lookupInSourceError != null) throw lookupInSourceError!;
    return lookupInSourceResult;
  }
}
