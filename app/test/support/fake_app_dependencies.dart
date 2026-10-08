import 'package:elinkbook/screens/app_dependencies.dart';
import 'package:elinkbook/screens/reader_feature_dependencies.dart';
import 'package:elinkbook/screens/source_dependencies.dart';
import 'package:elinkbook/screens/sync_dependencies.dart';

import 'fake_reader_feature_dependencies.dart';
import 'fake_source_dependencies.dart';
import 'fake_sync_dependencies.dart';

/// 預設全 fake 的應用層依賴容器（ADR 0037 §1）。
///
/// `syncCheckpointTrigger` 同時屬於 `readerFeatures` 與 `sync` 兩組，必須是
/// 同一實例：優先借用呼叫端傳入那一邊的 trigger——只傳 `readerFeatures` 時，
/// 新建的 `sync` 沿用它的 trigger；只傳 `sync` 時反之；兩邊都沒傳時新建一個
/// 共用的；兩邊都傳時完全尊重呼叫端。
AppDependencies fakeAppDependencies({
  ReaderFeatureDependencies? readerFeatures,
  SyncDependencies? sync,
  SourceDependencies? sources,
}) {
  final trigger = readerFeatures?.syncCheckpointTrigger ??
      sync?.syncCheckpointTrigger ??
      fakeSyncDependencies().syncCheckpointTrigger;
  final rf = readerFeatures ??
      fakeReaderFeatureDependencies(syncCheckpointTrigger: trigger);
  final s = sync ?? fakeSyncDependencies(syncCheckpointTrigger: trigger);
  return AppDependencies(
    readerFeatures: rf,
    sync: s,
    sources: sources ?? fakeSourceDependencies(),
  );
}
