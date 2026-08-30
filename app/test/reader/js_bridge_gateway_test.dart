import 'package:elinkbook/reader/js_bridge_gateway.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('JsBridgeGateway', () {
    test('request() 在對應 handler 回呼後正確完成，且真的呼叫了 evaluate', () async {
      final evaluatedCalls = <String>[];
      void Function(List<dynamic> args)? registeredCallback;
      final gateway = JsBridgeGateway(
        evaluate: (js) => evaluatedCalls.add(js),
        registerHandler: (name, callback) {
          expect(name, 'onFooReady');
          registeredCallback = callback;
        },
      );
      gateway.register<String>(
        handlerName: 'onFooReady',
        parse: (args) => args[0] as String,
        fallback: '',
      );

      final future = gateway.request<String>(
        jsCall: 'window.foo()',
        handlerName: 'onFooReady',
      );

      // evaluate 必須在 request() 呼叫的當下同步執行，不等 handler 回呼。
      expect(evaluatedCalls, ['window.foo()']);

      registeredCallback!(['bar']);

      expect(await future, 'bar');
    });

    test('設有逾時的請求，時限內未收到 handler 回呼時退回 register() 登記的 fallback；'
        '逾時後遲到的回呼不會拋出例外、也不會覆蓋已確定的結果', () {
      fakeAsync((async) {
        void Function(List<dynamic> args)? registeredCallback;
        final gateway = JsBridgeGateway(
          evaluate: (_) {},
          registerHandler: (name, callback) => registeredCallback = callback,
        );
        gateway.register<int>(
          handlerName: 'onBarReady',
          parse: (args) => args[0] as int,
          fallback: -1,
        );

        int? result;
        gateway
            .request<int>(
              jsCall: 'window.bar()',
              handlerName: 'onBarReady',
              timeout: const Duration(seconds: 5),
            )
            .then((value) => result = value);

        async.elapse(const Duration(seconds: 5));
        async.flushMicrotasks();

        expect(result, -1);

        // 逾時當下 _pending 裡的 Completer 已被移除；這裡模擬 JS 端遲到
        // 才送達的回呼，驗證不會拋出未處理例外，也不會把已經確定的
        // fallback 結果覆蓋掉（register() 內的
        // `if (completer == null) return null;` 防呆生效）。
        registeredCallback!([999]);
        async.flushMicrotasks();

        expect(result, -1);
      });
    });

    test('timeout 為 null 時不會被逾時機制打斷，只在 handler 真的回呼後才完成', () {
      fakeAsync((async) {
        void Function(List<dynamic> args)? registeredCallback;
        final gateway = JsBridgeGateway(
          evaluate: (_) {},
          registerHandler: (name, callback) => registeredCallback = callback,
        );
        gateway.register<List<String>>(
          handlerName: 'onBazReady',
          parse: (args) => (args[0] as List).cast<String>(),
          fallback: const [],
        );

        List<String>? result;
        gateway
            .request<List<String>>(
              jsCall: 'window.baz()',
              handlerName: 'onBazReady',
            )
            .then((value) => result = value);

        // 沒有設逾時：等再久也不該被打斷、也不該提前完成。
        async.elapse(const Duration(hours: 1));
        async.flushMicrotasks();
        expect(result, isNull);

        registeredCallback!([
          ['a', 'b']
        ]);
        async.flushMicrotasks();

        expect(result, ['a', 'b']);
      });
    });

    test('parse 拋出例外時立即退回 fallback，不需要等逾時', () {
      fakeAsync((async) {
        void Function(List<dynamic> args)? registeredCallback;
        final gateway = JsBridgeGateway(
          evaluate: (_) {},
          registerHandler: (name, callback) => registeredCallback = callback,
        );
        gateway.register<int>(
          handlerName: 'onBrokenReady',
          parse: (args) => throw const FormatException('模擬 JS 端回傳的 JSON 格式損壞'),
          fallback: -1,
        );

        int? result;
        gateway
            .request<int>(
              jsCall: 'window.broken()',
              handlerName: 'onBrokenReady',
              timeout: const Duration(seconds: 5),
            )
            .then((value) => result = value);

        registeredCallback!(['this triggers parse() to throw']);
        async.flushMicrotasks();

        // 還沒經過 5 秒逾時，就已經拿到 fallback——證明是 parse() 例外
        // 防護生效，不是靠逾時機制救回來的。
        expect(result, -1);
      });
    });
  });
}
