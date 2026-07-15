/// [EpubReaderView] 目前定位變動時（開書完成、翻頁、跳轉）一次性回報的
/// 位置資訊（epic-5-toc-pagination Issue 2）。[locatorJson] 是原生端
/// `Locator.toJSON().toString()` 的原樣字串，Dart 端不解析其內部結構、
/// 只負責持久化與之後原樣傳回原生端還原（`Locator.fromJSON`）；
/// [progression] 是原生端額外拆出的 `Locator.locations.totalProgression`
/// 平面數值，供 Dart 端直接用於 `Book.progress` 而不需要自行解析
/// [locatorJson] 的巢狀 JSON 結構。
class EpubPositionInfo {
  final String locatorJson;
  final double? progression;

  const EpubPositionInfo({
    required this.locatorJson,
    this.progression,
  });

  @override
  bool operator ==(Object other) =>
      other is EpubPositionInfo &&
      other.locatorJson == locatorJson &&
      other.progression == progression;

  @override
  int get hashCode => Object.hash(locatorJson, progression);

  @override
  String toString() =>
      'EpubPositionInfo(locatorJson: $locatorJson, progression: $progression)';
}
