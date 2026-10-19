// app/lib/dictionary/models/lookup_result.dart
import 'dictionary_entry.dart';
import 'lookup_request.dart';

/// 單一 provider 的查詢狀態。
enum OutcomeStatus { found, notFound, skipped, failed }

/// 單一 provider 的查詢結果（面板上的一個分段）。
class ProviderOutcome {
  const ProviderOutcome({
    required this.providerId,
    required this.displayName,
    required this.status,
    this.entries = const [],
    this.attribution,
    this.errorCode,
  });

  final String providerId;
  final String displayName;
  final OutcomeStatus status;
  final List<DictionaryEntry> entries;

  /// 例：萌典的來源標示。
  final String? attribution;

  /// 供 l10n 轉譯，不放 stack trace。
  final String? errorCode;
}

/// 一次查詢的完整結果。
class LookupResult {
  const LookupResult({required this.request, required this.outcomes});

  final LookupRequest request;

  /// 每個 provider 一筆，保持順序。
  final List<ProviderOutcome> outcomes;
}
