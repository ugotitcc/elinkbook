import 'percent_rect.dart';

/// [EpubReaderView] 使用者原生選字手勢建立/變動選取範圍時回報的資訊
/// （epic-6-annotations Issue 2）。[rect] 為選取矩形相對於 AndroidView
/// 容器寬高的百分比值（見 [PercentRect]），供 Dart 端在
/// `ReaderScreen._buildBody` 既有的 Stack 座標系內定位浮動工具列。
class EpubSelectionInfo {
  final String locatorJson;
  final double? progression;
  final PercentRect rect;

  const EpubSelectionInfo({
    required this.locatorJson,
    this.progression,
    required this.rect,
  });

  @override
  bool operator ==(Object other) =>
      other is EpubSelectionInfo &&
      other.locatorJson == locatorJson &&
      other.progression == progression &&
      other.rect == rect;

  @override
  int get hashCode => Object.hash(locatorJson, progression, rect);

  @override
  String toString() =>
      'EpubSelectionInfo(locatorJson: $locatorJson, progression: $progression, rect: $rect)';
}
