import 'percent_rect.dart';

/// [EpubReaderView] 使用者原生選字手勢建立/變動選取範圍時回報的資訊
/// （epic-6-annotations Issue 2）。[rect] 為選取矩形相對於 AndroidView
/// 容器寬高的百分比值（見 [PercentRect]），供 Dart 端在
/// `ReaderScreen._buildBody` 既有的 Stack 座標系內定位浮動工具列。
///
/// [text]（epic-27-reader-device-compat Issue 11）為這次選取的文字內容
/// （JS 端 `selection.toString()`），供 `AnnotationToolbar` 的「複製」
/// 按鈕使用；預設空字串。[existingAnnotationId]（同 Issue 11）為 JS 端用
/// `overlayer.hitTest()` 查出這次選取是否命中既有畫線/備註裝飾的結果
/// （`decodeAnnotationId` 相容格式，例如 `"highlight:5"`），沒命中為
/// `null`，供 `resolveEpubExistingAnnotation`
/// （`annotation_resolution.dart`）反查是哪一筆記錄。
class EpubSelectionInfo {
  final String locatorJson;
  final double? progression;
  final PercentRect rect;
  final String text;
  final String? existingAnnotationId;

  const EpubSelectionInfo({
    required this.locatorJson,
    this.progression,
    required this.rect,
    this.text = '',
    this.existingAnnotationId,
  });

  @override
  bool operator ==(Object other) =>
      other is EpubSelectionInfo &&
      other.locatorJson == locatorJson &&
      other.progression == progression &&
      other.rect == rect &&
      other.text == text &&
      other.existingAnnotationId == existingAnnotationId;

  @override
  int get hashCode =>
      Object.hash(locatorJson, progression, rect, text, existingAnnotationId);

  @override
  String toString() =>
      'EpubSelectionInfo(locatorJson: $locatorJson, progression: $progression, '
      'rect: $rect, text: $text, existingAnnotationId: $existingAnnotationId)';
}

