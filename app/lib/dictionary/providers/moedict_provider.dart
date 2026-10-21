// app/lib/dictionary/providers/moedict_provider.dart
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/dictionary_entry.dart';
import '../models/lookup_request.dart';
import '../models/lookup_result.dart';
import 'online_dictionary_provider.dart';

/// 萌典（`www.moedict.tw`）線上查詞。
///
/// 隱私邊界（spec §3.4、驗收 8、10、15）：
/// - 請求網址只含使用者選取的那個詞，沒有標頭、cookie 或裝置識別。
/// - 只接受 `https`；`AndroidManifest.xml` 開了 `usesCleartextTraffic`，
///   所以必須在 Dart 端擋，重導向也不跟。
/// - 結果原文顯示，不做簡繁轉換、不刪減釋義（CC BY-ND 3.0 TW）。
class MoedictProvider implements OnlineDictionaryProvider {
  MoedictProvider({
    required http.Client client,
    Uri? baseUri,
    this.timeout = const Duration(seconds: 5),
  })  : _client = client,
        _baseUri = baseUri ?? Uri.parse('https://www.moedict.tw/uni');

  /// 教育部《重編國語辭典修訂本》的法定來源標示；各語系一致，不走 l10n。
  static const String attribution =
      '資料來源：教育部《重編國語辭典修訂本》（CC BY-ND 3.0 TW），經由萌典提供';

  static const String _sourceId = 'moedict';

  final http.Client _client;
  final Uri _baseUri;
  final Duration timeout;

  @override
  String get id => _sourceId;

  @override
  String get displayName => '萌典';

  @override
  Future<ProviderOutcome> lookup(LookupRequest request) async {
    if (_baseUri.scheme != 'https') {
      return _failed('insecureUrl');
    }

    // 詞一律當成單一路徑段：`/`、`?`、`#` 會被編成 %2F、%3F、%23，
    // 不會多出查詢字串或 fragment。
    final uri = _baseUri.replace(pathSegments: [
      ..._baseUri.pathSegments.where((segment) => segment.isNotEmpty),
      request.word,
    ]);

    final http.Response response;
    try {
      response = await _fetch(uri).timeout(timeout);
    } on TimeoutException {
      return _failed('timeout');
    } catch (_) {
      // http.ClientException、SocketException 等：一律視為連線失敗。
      return _failed('network');
    }

    if (response.statusCode == 404) {
      return ProviderOutcome(
        providerId: id,
        displayName: displayName,
        status: OutcomeStatus.notFound,
      );
    }
    if (response.statusCode != 200) {
      return _failed('httpError');
    }

    final List<DictionaryEntry>? entries;
    try {
      entries = _parse(response.bodyBytes, request.word);
    } catch (_) {
      return _failed('unparseable');
    }
    if (entries == null) {
      return _failed('unparseable');
    }
    return ProviderOutcome(
      providerId: id,
      displayName: displayName,
      status: OutcomeStatus.found,
      entries: entries,
      attribution: attribution,
    );
  }

  Future<http.Response> _fetch(Uri uri) async {
    final request = http.Request('GET', uri)..followRedirects = false;
    return http.Response.fromStream(await _client.send(request));
  }

  /// 解析萌典的 `/uni/{詞}` 回應。格式不認得時回 `null`（上層轉
  /// `unparseable`）；單一詞條缺欄位則盡量湊出可讀內容，不當掉。
  List<DictionaryEntry>? _parse(List<int> bytes, String fallbackHeadword) {
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map) return null;

    final heteronyms = decoded['heteronyms'];
    if (heteronyms is! List) return null;

    final title = decoded['title'];
    final headword = title is String && title.trim().isNotEmpty
        ? title
        : fallbackHeadword;

    final entries = <DictionaryEntry>[
      for (final heteronym in heteronyms)
        if (heteronym is Map)
          if (_body(heteronym) case final String body)
            DictionaryEntry(
              sourceId: _sourceId,
              headword: headword,
              pronunciation: _pronunciation(heteronym),
              body: body,
              bodyKind: EntryBodyKind.plainText,
            ),
    ];
    return entries.isEmpty ? null : entries;
  }

  /// 每個 `heteronym` 的釋義區塊。多個定義時加 `1. `、`2. ` 編號；
  /// 例句在前、書證在後，各縮排兩個半形空白。
  String? _body(Map<dynamic, dynamic> heteronym) {
    final definitions = heteronym['definitions'];
    if (definitions is! List) return null;

    final usable = [
      for (final definition in definitions)
        if (definition is Map)
          if (definition['def'] case final String def)
            if (def.trim().isNotEmpty) definition,
    ];
    if (usable.isEmpty) return null;

    final lines = <String>[];
    for (var i = 0; i < usable.length; i++) {
      final definition = usable[i];
      final def = definition['def'] as String;
      final type = definition['type'];
      final hasType = type is String && type.trim().isNotEmpty;
      final prefix = usable.length > 1 ? '${i + 1}. ' : '';
      lines.add('$prefix${hasType ? '$type  ' : ''}$def');
      for (final example in _nonEmptyStrings(definition['example'])) {
        lines.add('  $example');
      }
      for (final quote in _nonEmptyStrings(definition['quote'])) {
        lines.add('  $quote');
      }
    }
    return lines.join('\n');
  }

  /// 注音與拼音各自做空白正規化；兩者都有時以 ` ／ ` 相連。
  String? _pronunciation(Map<dynamic, dynamic> heteronym) {
    final parts = <String>[];
    for (final key in const ['bopomofo', 'pinyin']) {
      final raw = heteronym[key];
      if (raw is! String) continue;
      final normalized = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
      if (normalized.isEmpty) continue;
      parts.add(normalized);
    }
    return parts.isEmpty ? null : parts.join(' ／ ');
  }

  /// 寬鬆解析：非字串項目（例如數字）略過，不當掉。
  Iterable<String> _nonEmptyStrings(Object? value) sync* {
    if (value is! List) return;
    for (final item in value) {
      if (item is String && item.trim().isNotEmpty) yield item;
    }
  }

  ProviderOutcome _failed(String errorCode) => ProviderOutcome(
        providerId: id,
        displayName: displayName,
        status: OutcomeStatus.failed,
        errorCode: errorCode,
      );
}
