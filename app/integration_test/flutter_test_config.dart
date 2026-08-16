import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Issue 9 根因修復：`IntegrationTestWidgetsFlutterBinding`
/// （繼承自 `LiveTestWidgetsFlutterBinding`）預設 `framePolicy` 是
/// `fadePointers`——這個模式下，`setState()` 之後不會自動畫下一格，除非
/// 測試明確呼叫 `tester.pump()` 或有指標活動觸發（見 Flutter SDK
/// `flutter_test/lib/src/binding.dart` 的 `handleBeginFrame`）。
///
/// `FoliateReaderView`（Issue 8 起）在 `initState()` 內非同步完成
/// `_cacheBook()` 後才 `setState()` 掛載 `InAppWebView`；既有整合測試多半
/// 是 `pumpWidget()` 後直接 `await` 一個 completer，中間沒有任何
/// `pump()`，導致該次 `setState()` 永遠等不到畫面重繪、`InAppWebView`
/// 從未掛載，最終測試逾時（`docs/epics/epic-20-fxl-foliate-migration/
/// issues.md` Issue 9 記錄的其中一種失敗模式）。改為 `fullyLive`
/// 讓所有非同步等待期間都能正常畫格，符合實機執行 App 時的真實行為。
///
/// 這是 Flutter 標準的全域整合測試設定機制（此檔案名稱與位置為框架
/// 慣例，`flutter test integration_test/` 執行任何測試前都會先跑這裡的
/// `testExecutable`），對 `integration_test/` 目錄下所有測試檔案生效，
/// 不需要在每個測試檔案各自重複設定。
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  await testMain();
}
