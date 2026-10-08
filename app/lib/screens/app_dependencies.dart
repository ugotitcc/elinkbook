import 'package:flutter/foundation.dart';

import 'reader_feature_dependencies.dart';
import 'source_dependencies.dart';
import 'sync_dependencies.dart';

/// 應用層依賴容器（ADR 0037 §1）：持有 `main()` 建構一次的三組靜態依賴，**只在 `main.dart`
/// 與 `ElinkBookApp` 使用**，不往畫面傳整包——畫面各自接收所需的那一組。
///
/// 外觀（主題、E-Ink、介面語言）不在這裡：它是含可變狀態的快照，由 `_ElinkBookAppState`
/// 每次 `build()` 現組成 `AppearanceDependencies`。`syncCheckpointTrigger` 同時屬於
/// `readerFeatures` 與 `sync`，由 `main()` 建構一次、同一實例放進兩組。
@immutable
class AppDependencies {
  final ReaderFeatureDependencies readerFeatures;
  final SyncDependencies sync;
  final SourceDependencies sources;

  const AppDependencies({
    required this.readerFeatures,
    required this.sync,
    required this.sources,
  });
}
