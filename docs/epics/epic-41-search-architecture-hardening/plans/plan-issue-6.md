# Epic 41 Issue 6：JsBridgeGateway 對「同一 handler 重疊請求」補一道呼叫端防呆 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 `JsBridgeGateway.request()` 補一道防呆——偵測到同一 `handlerName` 已有尚未完成的舊請求時，把舊請求以 `StateError` 提前結束，取代目前「靜默覆寫、舊呼叫者的回應被之後抵達的 JS 回呼誤配對，或完全沒設 timeout 時永遠掛住」的行為，讓 `JsBridgeGateway` 既有的隱性契約（同一 handler 不可重疊發出請求）在違反時有明確、可辨識的失敗訊號。

**Architecture:** 純粹在既有 `request()` 方法內插入一段防呆邏輯，不新增任何公開 API、不改變任何既有呼叫端的呼叫方式或回傳型別。全程只動一個生產程式碼檔案（`js_bridge_gateway.dart`）＋一份既有測試檔（`js_bridge_gateway_test.dart` 新增兩個測試案例：無 timeout／有 timeout 各一，見 `reviews/review-plan-issue-6.md` I-1 修訂）。`foliate_reader_view.dart`／`search/foliate_content_indexer.dart` 現有 4 個呼叫點（TOC／TTS segments／TTS segment index／`onSectionCountReady`）皆不需要改動。

**Tech Stack:** Flutter/Dart，`flutter_test`（純 Dart 單元測試；本次新增的測試不涉及計時器，不需要 `fake_async`）。

**Spec:** `docs/epics/epic-41-search-architecture-hardening/issues.md`（Issue 6 段落，2026-09-17 `/grill-with-docs` 重新評估定案版本）。

## Global Constraints

- 所有新增/修改的程式碼註解與本計畫文件一律使用正體中文（zh-TW），不得使用簡體中文（使用者全域 CLAUDE.md 規則）。
- 必須使用真正的例外（`StateError`），**不可用 `assert()`**——`assert()` 在 release build 會被整個移除，等於正式環境完全沒有保護力，違背補安全網的初衷（Issue 6 Q1 已定案）。
- 偵測到重疊時，除了新請求正常繼續之外，**必須**對被取代的舊 completer 呼叫 `completeError()`，讓舊呼叫者的 `await` 立刻收到明確錯誤，而不是繼續傻等到自己的 timeout（或完全沒有 timeout 時永遠掛住）（Issue 6 Q2 已定案）。
- 不需要額外檢查 `existing.isCompleted`——依現有程式碼既有不變量：completer 只要還留在 `_pending` 裡就一定尚未 complete（`register()` 的 callback 與 `request()` 的 timeout `onTimeout` 都是「complete 的同時立即 `_pending.remove()`」成對發生，見 `js_bridge_gateway.dart:41-52`／`78-81`）。
- 現有 4 個呼叫點（`foliate_reader_view.dart` 的 TOC／TTS segments／TTS segment index，`foliate_content_indexer.dart` 的 `onSectionCountReady`）皆不觸發重入路徑，**必須零回歸**，不可修改這些呼叫端程式碼。
- 本 Issue 只有一個 Task，也是整份計畫最後一個 Task——依專案 `CLAUDE.md`「測試執行範圍」既有慣例，本 Task 最後需跑一次完整 `flutter analyze`／`flutter test`，而非只跑本次異動觸及的測試檔。
- Git commit 訊息結尾需附加（本次 session 的固定 attribution，見系統提示）：
  ```
  Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
  ```

---

### Task 1: `JsBridgeGateway.request()` 補「同一 handler 重疊請求」防呆

**Files:**
- Modify: `app/lib/reader/js_bridge_gateway.dart:1-8`（class doc comment）、`app/lib/reader/js_bridge_gateway.dart:62-83`（`request()` 方法）
- Test: `app/test/reader/js_bridge_gateway_test.dart`（既有檔案，於既有 `group('JsBridgeGateway', ...)` 內新增兩個測試案例）

**Interfaces:**
- Consumes：既有 `JsBridgeGateway` 建構子（`evaluate`／`registerHandler`）與 `register<T>()`／`request<T>()` 方法簽章，完全不變，不新增任何參數。
- Produces：`request<T>()` 的新行為——呼叫時若對應 `handlerName` 在 `_pending` 中已有尚未完成的舊 `Completer`，該舊 `Completer` 會以 `StateError` 完成（新請求本身仍正常回傳一個新的、會等待 handler 回呼的 `Future<T>`，不受影響）。本 Issue 只有這一個 Task，無下游任務依賴此處的具體型別。

- [ ] **Step 1: 寫失敗測試**

在 `app/test/reader/js_bridge_gateway_test.dart` 既有 `group('JsBridgeGateway', () { ... })` 內，緊接在最後一個既有測試（`'parse 拋出例外時立即退回 fallback，不需要等逾時'`，目前結尾在第 139 行 `});`）之後、`group` 自己的收尾 `});`（第 140 行）之前，新增兩個測試案例。**兩者皆改用 `fakeAsync`／`flushMicrotasks()`，不直接 `await` 可能永遠不完成的 Future**（審查 `reviews/review-plan-issue-6.md` I-2：在紅燈階段 `await expectLater(firstFuture, ...)` 會卡到 `flutter test` 預設的 30 秒 test timeout 才失敗，改用 `catchError`／`.then(onError: ...)` 把結果捕捉到區域變數、`flushMicrotasks()` 後直接斷言變數，紅燈階段能立即失敗）：

```dart
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
```

修改後，該檔案最上方的 import 區塊（第 1-3 行）不需要變動——`fake_async`／`StateError`／`isA`／`having` 皆已隨既有的 `package:fake_async/fake_async.dart`／`package:flutter_test/flutter_test.dart` 匯入可用（既有 Test 2-4 已在用 `fakeAsync`）。

- [ ] **Step 2: 執行測試，確認會失敗**

於 `app/` 目錄下執行：

```bash
flutter test test/reader/js_bridge_gateway_test.dart --plain-name "同一個 handler 尚有 pending 請求"
```

Expected: FAIL（兩個新測試皆失敗，且是**立即失敗**、不會卡住等待——這正是改用 `fakeAsync`＋`flushMicrotasks()` 而非直接 `await` 的目的）：現行 `request()` 尚未實作防呆，`firstError`／`firstResult` 在 `flushMicrotasks()` 後仍維持初始值 `null`，`expect(firstError, isA<StateError>()...)` 直接判定失敗；`secondResult`/`firstResult` 相關斷言則因現行「靜默覆寫」的既有行為（新請求正常運作、舊請求永遠不完成）而部分通過、部分失敗，整體測試仍為 FAIL。

- [ ] **Step 3: 實作最小程式碼**

修改 `app/lib/reader/js_bridge_gateway.dart`。

先更新 class doc comment（第 1-8 行），在既有段落末尾補一句話說明這個隱性契約：

```dart
import 'dart:async';

/// 收斂「發一個 JS 請求、等 JS 呼叫 handler 回來、完成 Completer」這個
/// 重複樣板的深模組（epic-26-architecture-hardening Issue 13）。不直接
/// 依賴 InAppWebViewController，改收 [evaluate]／[registerHandler] 兩個
/// 注入函式，讓這個類別可以脫離真正的 WebView 環境被單元測試——現有的
/// `fake_inappwebview_platform.dart` 沒有能力模擬 JS handler 回呼，這是
/// 過去三個 `_requestXxx` 完全沒有 Dart 測試涵蓋的根本原因。
///
/// 同一個 [handlerName] 同時只能有一個 pending 請求：呼叫端必須自行保證
/// 不會在前一次對同一 handler 的 [request] 完成前又發出新的請求，否則
/// 回應會被誤配對給錯的呼叫。若違反這個約定，舊請求會被視為過期並以
/// `StateError` 提前結束（見 [request] 實作），不會靜默覆寫或無限期掛住
/// （epic-41-search-architecture-hardening Issue 6）。
class JsBridgeGateway {
```

再修改 `request<T>()` 方法本體（原第 62-83 行）：

```dart
  Future<T> request<T>({
    required String jsCall,
    required String handlerName,
    Duration? timeout,
  }) {
    assert(
      _fallbackByHandler.containsKey(handlerName),
      'Handler "$handlerName" 尚未透過 register() 註冊 fallback 值',
    );
    // 同一 handler 若已有尚未完成的舊請求，代表呼叫端在前一次請求完成前
    // 又發出了新請求——依既有不變量（completer 只要還留在 _pending 裡
    // 就一定尚未 complete，見 register() 的 callback 與下方 timeout 的
    // onTimeout，皆是「complete 的同時立即 remove」成對發生），此時直接
    // 讓舊請求以明確錯誤結束，取代原本「靜默覆寫、舊呼叫者的回應被之後
    // 抵達的 JS 回呼誤配對，或完全沒設 timeout 時永遠掛住」的行為
    // （epic-41-search-architecture-hardening Issue 6，全 build 強制生效，
    // 不可用 assert()——release build 會被整個移除）。
    final existing = _pending[handlerName];
    if (existing != null) {
      existing.completeError(
        StateError(
          'JsBridgeGateway: handler "$handlerName" 的前一個 request() '
          '尚未完成前又收到新的請求，舊請求已被取代並以錯誤結束（呼叫端'
          '需自行保證同一 handler 不會重疊發出請求）。',
        ),
      );
    }
    final completer = Completer<T>();
    _pending[handlerName] = completer;
    evaluate(jsCall);
    final future = completer.future;
    if (timeout == null) return future;
    return future.timeout(
      timeout,
      onTimeout: () {
        _pending.remove(handlerName);
        return _fallbackByHandler[handlerName] as T;
      },
    );
  }
```

- [ ] **Step 4: 執行測試，確認通過**

```bash
flutter test test/reader/js_bridge_gateway_test.dart --plain-name "同一個 handler 尚有 pending 請求"
```

Expected: PASS（兩個新測試皆通過）

- [ ] **Step 5: 執行完整 `js_bridge_gateway_test.dart`，確認既有 4 個測試案例零回歸**

```bash
flutter test test/reader/js_bridge_gateway_test.dart
```

Expected: PASS（6 個測試全過：既有 4 個＋新增 2 個）——尤其確認既有「逾時退回 fallback」／「timeout 為 null 時不受打斷」／「parse 拋出例外」三個測試案例不受本次改動影響，因為它們都只呼叫一次 `request()`，不會觸發新加的重疊防呆分支。

- [ ] **Step 6: 執行完整 `flutter analyze`／`flutter test`**

本 Task 是整份計畫最後一個 Task，依專案 `CLAUDE.md`「測試執行範圍」慣例於此執行一次完整驗證：

```bash
flutter analyze
```

Expected: `No issues found!`

```bash
flutter test
```

Expected: 全數通過，零回歸（尤其 `test/reader/foliate_reader_view_test.dart`／`test/search/foliate_content_indexer_test.dart`——若這兩個測試檔存在，其涵蓋的 4 個既有 `JsBridgeGateway` 呼叫點應完全不受影響）。

- [ ] **Step 7: Commit**

```bash
git add app/lib/reader/js_bridge_gateway.dart app/test/reader/js_bridge_gateway_test.dart
git commit -m "$(cat <<'EOF'
fix(reader): JsBridgeGateway.request() 補同一 handler 重疊請求防呆

同一 handler 若已有尚未完成的舊請求又收到新請求，舊請求現在會以
StateError 提前結束，取代原本靜默覆寫、可能造成回應誤配對或無限期
掛住的行為（epic-41-search-architecture-hardening Issue 6）。

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

## Self-Review

**Spec coverage：** Issue 6 的 Solution 段落三個要求——(1) `request()` 內防呆、全 build 強制生效、不用 `assert()`；(2) 依現有不變量不需檢查 `isCompleted`；(3) class doc comment 補隱性契約說明——皆已對應到 Task 1 Step 3。單元測試要求（新增重疊請求案例＋既有測試零回歸）對應 Step 1／Step 5，並依審查補齊「有 timeout」分支覆蓋。驗收標準（`flutter analyze` 乾淨／`flutter test` 全數通過零回歸）對應 Step 6。無遺漏項目。

**Placeholder 掃描：** 全部步驟皆含完整可執行程式碼與確切指令，無「TBD」/「補上驗證」等佔位字樣。

**型別一致性：** 全程只使用既有型別（`JsBridgeGateway`／`Completer<T>`／`StateError`），未新增任何型別或方法簽章，不存在跨 Task 型別對不上的風險（本計畫僅一個 Task）。

**審查修訂紀錄（`reviews/review-plan-issue-6.md`，2026-09-17 初審＋複審）：** 初審 I-1（補齊 `timeout != null` 分支測試）、I-2（紅燈測試改用 `fakeAsync` 避免卡 30 秒）、M-1（例外訊息斷言加 `contains(handlerName)`）皆已採納並落實於 Task 1 Step 1/2/4/5。M-2（建議 Git commit attribution 改用通用寫法）**不採納**——目前寫法為本次 session 系統層級明確指示的固定 attribution，且與同一 Epic 既有 `plan-issue-5.md` 慣例一致，維持原樣。複審發現的殘留項（第二個測試 `.then(onValue, onError: ...)` 單一呼叫因回傳型別不符會在 `onError` 真正被呼叫時觸發執行期 `ArgumentError`，只會在 Step 4 綠燈階段爆炸、紅燈階段不會出現）已採納，改為 `.then().catchError()` 兩段式寫法，對齊第一個測試已驗證可行的模式。
