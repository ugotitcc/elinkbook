import 'package:flutter_test/flutter_test.dart';

import 'fake_app_dependencies.dart';
import 'fake_reader_feature_dependencies.dart';
import 'fake_source_dependencies.dart';
import 'fake_sync_dependencies.dart';

void main() {
  test('fakeAppDependencies 預設的兩組共用同一個 syncCheckpointTrigger（ADR 0037 §1）', () {
    final deps = fakeAppDependencies();
    expect(
      deps.readerFeatures.syncCheckpointTrigger,
      same(deps.sync.syncCheckpointTrigger),
    );
  });

  test('fakeAppDependencies 具名覆寫原樣帶入', () {
    final sources = fakeSourceDependencies();
    expect(fakeAppDependencies(sources: sources).sources, same(sources));
  });

  test('fakeAppDependencies 單邊傳入 readerFeatures 時，未傳入的 sync 自動共用其 syncCheckpointTrigger', () {
    final trigger = fakeSyncDependencies().syncCheckpointTrigger;
    final rf = fakeReaderFeatureDependencies(syncCheckpointTrigger: trigger);
    final deps = fakeAppDependencies(readerFeatures: rf);
    expect(deps.sync.syncCheckpointTrigger, same(trigger));
  });

  test('fakeAppDependencies 單邊傳入 sync 時，未傳入的 readerFeatures 自動共用其 syncCheckpointTrigger', () {
    final trigger = fakeSyncDependencies().syncCheckpointTrigger;
    final s = fakeSyncDependencies(syncCheckpointTrigger: trigger);
    final deps = fakeAppDependencies(sync: s);
    expect(deps.readerFeatures.syncCheckpointTrigger, same(trigger));
  });
}
