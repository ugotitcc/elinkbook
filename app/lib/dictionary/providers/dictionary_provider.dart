// app/lib/dictionary/providers/dictionary_provider.dart
import '../models/lookup_request.dart';
import '../models/lookup_result.dart';

/// 查詢來源的共同介面。`DictionaryService` 只認這個介面。
abstract class DictionaryProvider {
  String get id;

  Future<ProviderOutcome> lookup(LookupRequest request);
}
