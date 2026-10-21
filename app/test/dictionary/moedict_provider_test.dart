// app/test/dictionary/moedict_provider_test.dart
import 'dart:async';
import 'dart:convert';

import 'package:elinkbook/dictionary/models/dictionary_entry.dart';
import 'package:elinkbook/dictionary/models/lookup_request.dart';
import 'package:elinkbook/dictionary/models/lookup_result.dart';
import 'package:elinkbook/dictionary/providers/moedict_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _base = 'https://www.moedict.tw/uni';

/// 以 UTF-8 編碼的 JSON 回應；`http.Response` 預設用 latin1，中文會爆。
http.Response _json(Object body, {int status = 200}) => http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      status,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );

/// 一筆正常的萌典回應，可個別覆寫欄位。
Map<String, Object?> _moedictPayload({
  Object? title = '相濡以沫',
  Object? heteronyms,
}) =>
    {
      if (title != null) 'title': title,
      'heteronyms': heteronyms ??
          [
            {
              'bopomofo': 'ㄒㄧㄤ ㄖㄨˊ ㄧˇ ㄇㄛˋ',
              'pinyin': 'xiāng rú yǐ mò',
              'definitions': [
                {'def': '彼此用微薄的力量互相幫助。'},
              ],
            },
          ],
    };

typedef _Harness = ({
  MoedictProvider provider,
  List<http.Request> requests,
});

_Harness _harness(
  Future<http.Response> Function(http.Request) handler, {
  Uri? baseUri,
  Duration timeout = const Duration(seconds: 5),
}) {
  final requests = <http.Request>[];
  final client = MockClient((request) {
    requests.add(request);
    return handler(request);
  });
  return (
    provider: MoedictProvider(
      client: client,
      baseUri: baseUri,
      timeout: timeout,
    ),
    requests: requests,
  );
}

void main() {
  test('請求網址只含詞', () async {
    final harness = _harness((_) async => _json(_moedictPayload()));

    await harness.provider.lookup(const LookupRequest('相濡以沫'));

    final request = harness.requests.single;
    expect(
      request.url.toString(),
      '$_base/%E7%9B%B8%E6%BF%A1%E4%BB%A5%E6%B2%AB',
    );
    expect(request.method, 'GET');
    final headerNames = request.headers.keys.map((k) => k.toLowerCase());
    expect(headerNames, isNot(contains('cookie')));
    expect(headerNames, isNot(contains('authorization')));
  });

  test('詞含 / ? # 時仍是單一路徑段', () async {
    const word = 'a/b?c#d 手机';
    final harness = _harness((_) async => _json(_moedictPayload()));

    await harness.provider.lookup(const LookupRequest(word));

    final url = harness.requests.single.url;
    expect(url.pathSegments, hasLength(2));
    expect(url.pathSegments.last, word);
    expect(url.query, isEmpty);
    expect(url.fragment, isEmpty);
  });

  test('拒絕非 https', () async {
    final harness = _harness(
      (_) async => _json(_moedictPayload()),
      baseUri: Uri.parse('http://www.moedict.tw/uni'),
    );

    final outcome = await harness.provider.lookup(const LookupRequest('相濡以沫'));

    expect(outcome.status, OutcomeStatus.failed);
    expect(outcome.errorCode, 'insecureUrl');
    expect(harness.requests, isEmpty);
  });

  test('不跟重導向', () async {
    var followRedirects = true;
    final harness = _harness((request) async {
      followRedirects = request.followRedirects;
      return http.Response('', 301, headers: const {
        'location': 'http://evil.example/',
      });
    });

    final outcome = await harness.provider.lookup(const LookupRequest('相濡以沫'));

    expect(outcome.status, OutcomeStatus.failed);
    expect(outcome.errorCode, 'httpError');
    expect(harness.requests, hasLength(1));
    expect(followRedirects, isFalse);
  });

  test('逾時', () async {
    final harness = _harness(
      (_) => Completer<http.Response>().future,
      timeout: const Duration(milliseconds: 20),
    );

    final outcome = await harness.provider.lookup(const LookupRequest('相濡以沫'));

    expect(outcome.status, OutcomeStatus.failed);
    expect(outcome.errorCode, 'timeout');
  });

  test('連線例外', () async {
    final harness = _harness((_) => throw http.ClientException('x'));

    final outcome = await harness.provider.lookup(const LookupRequest('相濡以沫'));

    expect(outcome.status, OutcomeStatus.failed);
    expect(outcome.errorCode, 'network');
  });

  test('404 是查無', () async {
    final harness = _harness((_) async => http.Response('', 404));

    final outcome = await harness.provider.lookup(const LookupRequest('相濡以沫'));

    expect(outcome.status, OutcomeStatus.notFound);
    expect(outcome.entries, isEmpty);
  });

  test('500 與 429', () async {
    for (final status in [500, 429]) {
      final harness = _harness((_) async => http.Response('', status));

      final outcome =
          await harness.provider.lookup(const LookupRequest('相濡以沫'));

      expect(outcome.status, OutcomeStatus.failed, reason: '$status');
      expect(outcome.errorCode, 'httpError', reason: '$status');
    }
  });

  test('正常回應', () async {
    final harness = _harness((_) async => _json(_moedictPayload()));

    final outcome = await harness.provider.lookup(const LookupRequest('相濡以沫'));

    expect(outcome.status, OutcomeStatus.found);
    expect(outcome.entries, hasLength(1));
    final entry = outcome.entries.single;
    expect(entry.sourceId, 'moedict');
    expect(entry.headword, '相濡以沫');
    expect(entry.pronunciation, 'ㄒㄧㄤ ㄖㄨˊ ㄧˇ ㄇㄛˋ ／ xiāng rú yǐ mò');
    expect(entry.body, '彼此用微薄的力量互相幫助。');
    expect(entry.bodyKind, EntryBodyKind.plainText);
    expect(outcome.attribution, MoedictProvider.attribution);
  });

  test('多定義與例句', () async {
    final harness = _harness(
      (_) async => _json(_moedictPayload(heteronyms: [
        {
          'definitions': [
            {'type': '名', 'def': 'def1', 'example': ['例一']},
            {'def': 'def2'},
          ],
        },
      ])),
    );

    final outcome = await harness.provider.lookup(const LookupRequest('相濡以沫'));

    expect(outcome.entries.single.body, '1. 名  def1\n  例一\n2. def2');
  });

  test('例句與書證並存', () async {
    final harness = _harness(
      (_) async => _json(_moedictPayload(heteronyms: [
        {
          'definitions': [
            {
              'type': '名',
              'def': 'def1',
              'example': ['例一'],
              'quote': ['書證一'],
            },
          ],
        },
      ])),
    );

    final outcome = await harness.provider.lookup(const LookupRequest('相濡以沫'));

    expect(outcome.entries.single.body, '名  def1\n  例一\n  書證一');
  });

  test('缺欄位不當掉', () async {
    final harness = _harness(
      (_) async => _json(_moedictPayload(title: null, heteronyms: [
        {
          'definitions': [
            {'def': '只有釋義', 'example': 5},
          ],
        },
      ])),
    );

    final outcome = await harness.provider.lookup(const LookupRequest('相濡以沫'));

    expect(outcome.status, OutcomeStatus.found);
    final entry = outcome.entries.single;
    expect(entry.headword, '相濡以沫');
    expect(entry.pronunciation, isNull);
    expect(entry.body, '只有釋義');
  });

  test('無法解析', () async {
    final badResponses = <String, http.Response>{
      'HTML 字串': http.Response('<html>not json</html>', 200),
      '空物件': _json(const {}),
      'heteronyms 為空': _json(const {'heteronyms': []}),
      '沒有 definitions': _json(const {
        'heteronyms': [
          {'bopomofo': 'ㄒㄧㄤ'},
        ],
      }),
    };

    for (final entry in badResponses.entries) {
      final harness = _harness((_) async => entry.value);

      final outcome =
          await harness.provider.lookup(const LookupRequest('相濡以沫'));

      expect(outcome.status, OutcomeStatus.failed, reason: entry.key);
      expect(outcome.errorCode, 'unparseable', reason: entry.key);
    }
  });
}
