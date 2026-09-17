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

    test(
      '同一個 handler 尚有 pending 請求（未設定 timeout）時又發出新請求，'
      '舊請求的 Future 會立即以帶有 handler 名稱的 StateError 結束，'
      '新請求不受影響、能在 handler 真正回呼時正常完成',
      () {
        fakeAsync((async) {
          void Function(List<dynamic> args)? registeredCallback;
          final gateway = JsBridgeGateway(
            evaluate: (_) {},
            registerHandler: (name, callback) =>
                registeredCallback = callback,
          );
          gateway.register<String>(
            handlerName: 'onFooReady',
            parse: (args) => args[0] as String,
            fallback: '',
          );

          Object? firstError;
          gateway
              .request<String>(
                jsCall: 'window.foo(1)',
                handlerName: 'onFooReady',
              )
              .catchError((Object e) {
                firstError = e;
                return '';
              });

          String? secondResult;
          gateway
              .request<String>(
                jsCall: 'window.foo(2)',
                handlerName: 'onFooReady',
              )
              .then((value) => secondResult = value);

          async.flushMicrotasks();

          // 審查 M-1：不只驗證型別，還核對訊息點出了是哪個 handler——
          // 防止實作寫成 `throw StateError('')` 這種型別對但內容空洞的
          // 版本也能矇混過關。
          expect(
            firstError,
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('onFooReady'),
            ),
          );
          expect(secondResult, isNull); // 尚未收到 handler 回呼。

          registeredCallback!(['second-result']);
          async.flushMicrotasks();

          expect(secondResult, 'second-result');
        });
      },
    );

    test(
      '同一個 handler 尚有 pending 請求（已設定 timeout）時又發出新請求，'
      '舊請求立即以 StateError 結束，不會等到自己的 timeout 才回退 fallback',
      () {
        fakeAsync((async) {
          void Function(List<dynamic> args)? registeredCallback;
          final gateway = JsBridgeGateway(
            evaluate: (_) {},
            registerHandler: (name, callback) =>
                registeredCallback = callback,
          );
          gateway.register<String>(
            handlerName: 'onTtsSegmentsReady',
            parse: (args) => args[0] as String,
            fallback: 'FALLBACK',
          );

          Object? firstError;
          String? firstResult;
          // 審查 I-1 複審：單一 `.then(onValue, onError: ...)` 呼叫的 R
          // 型別由 onValue 推斷（此處為 String?），onError 若回傳型別不
          // 相容的值（`(Object e) => firstError = e` 回傳的是 `e` 本身，
          // 型別為 Object），會在 onError 真正被呼叫時觸發執行期
          // `ArgumentError`。改用 `.then().catchError()` 兩段式，對齊
          // 上一個測試已驗證可行的寫法。
          gateway
              .request<String>(
                jsCall: 'window.foo(1)',
                handlerName: 'onTtsSegmentsReady',
                timeout: const Duration(seconds: 5),
              )
              .then((value) => firstResult = value)
              .catchError((Object e) {
                firstError = e;
                return '';
              });

          gateway.request<String>(
            jsCall: 'window.foo(2)',
            handlerName: 'onTtsSegmentsReady',
            timeout: const Duration(seconds: 5),
          );

          // 確保 handler 已註冊，避免 unused_local_variable 分析警告。
          expect(registeredCallback, isNotNull);

          // 審查 I-1：尚未經過任何時間就應該已經收到錯誤——不是靠 5 秒
          // 逾時機制救回來的，也絕不能回退 fallback 值。
          async.flushMicrotasks();

          expect(
            firstError,
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('onTtsSegmentsReady'),
            ),
          );
          expect(firstResult, isNull);

          // 推進超過 5 秒，確認 Future.timeout() 內部的計時器已隨舊請求
          // 提前結束而被取消，不會在背景殘留、事後又把結果覆寫成 fallback。
          async.elapse(const Duration(seconds: 6));
          async.flushMicrotasks();

          expect(firstError, isA<StateError>());
          expect(firstResult, isNull);
        });
      },
    );
  });
}
