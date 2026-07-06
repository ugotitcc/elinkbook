/// 直排／橫排狀態，對應 Readium `EpubPreferences.verticalText`（見
/// docs/adr/0003-epub-reader-writing-mode-contract.md）。
enum WritingMode { horizontal, vertical }

/// [EpubReaderView] 開書完成後一次性回報的版面資訊。
class EpubLayoutInfo {
  final bool isFixedLayout;
  final WritingMode writingMode;

  const EpubLayoutInfo({
    required this.isFixedLayout,
    required this.writingMode,
  });

  @override
  bool operator ==(Object other) =>
      other is EpubLayoutInfo &&
      other.isFixedLayout == isFixedLayout &&
      other.writingMode == writingMode;

  @override
  int get hashCode => Object.hash(isFixedLayout, writingMode);

  @override
  String toString() =>
      'EpubLayoutInfo(isFixedLayout: $isFixedLayout, writingMode: $writingMode)';
}
