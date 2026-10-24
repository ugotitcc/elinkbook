import 'book_format.dart';

/// 開書前解析的結果（CONTEXT「引擎分派判斷」的「開書前解析規則」）。
sealed class EngineDispatch {
  const EngineDispatch();
}

/// 已知：宣告值直接採用，或依格式的預設值。
final class EngineDispatchKnown extends EngineDispatch {
  const EngineDispatchKnown(this.isFixedLayout);

  final bool isFixedLayout;

  @override
  bool operator ==(Object other) =>
      other is EngineDispatchKnown && other.isFixedLayout == isFixedLayout;

  @override
  int get hashCode => Object.hash(EngineDispatchKnown, isFixedLayout);

  @override
  String toString() => 'Known($isFixedLayout)';
}

/// 需補判斷：EPUB 且宣告值為 null；補判斷期間畫面維持載入。
final class EngineDispatchNeedsDetection extends EngineDispatch {
  const EngineDispatchNeedsDetection();

  @override
  bool operator ==(Object other) => other is EngineDispatchNeedsDetection;

  @override
  int get hashCode => (EngineDispatchNeedsDetection).hashCode;

  @override
  String toString() => 'NeedsDetection';
}

/// 不適用：PDF 等不套用固定版面旗標的格式，且宣告值為 null。
final class EngineDispatchNotApplicable extends EngineDispatch {
  const EngineDispatchNotApplicable();

  @override
  bool operator ==(Object other) => other is EngineDispatchNotApplicable;

  @override
  int get hashCode => (EngineDispatchNotApplicable).hashCode;

  @override
  String toString() => 'NotApplicable';
}

/// 依「格式＋宣告值」解析開書前的固定版面結果。
EngineDispatch resolveEngineDispatch({
  required BookFormat format,
  required bool? declared,
}) {
  // 宣告值非 null：任何格式都直接採用（含 PDF／unknown）。
  if (declared != null) return EngineDispatchKnown(declared);
  switch (format) {
    case BookFormat.epub:
      return const EngineDispatchNeedsDetection();
    // 以下格式沒有執行期重新偵測手段，宣告值為 null 時（多為匯入階段
    // metadata 擷取失敗的既有書籍）一律防禦性給預設值，而非讓
    // _dispatchedIsFixedLayout 永遠停在 null——後者會讓 _buildBody 的
    // gating 條件永遠等不到非 null 值，FoliateReaderView 永遠無法建構，
    // 書籍完全無法開啟（epic-11 Issue 2 程式碼審查 C2；Issue 3 Important
    // #1、Issue 4 沿用同一教訓）。
    case BookFormat.azw3: // KF8 容器格式不同，不能沿用 EPUB 的 OPF/CSS 偵測；絕大多數為流式
    case BookFormat.txt: // 合成後恆為流式（spec.md「TXT／Markdown 合成書籍結構」）
    case BookFormat.md: // 同 TXT
      return const EngineDispatchKnown(false);
    case BookFormat.cbz: // 恆為固定版面，沒有流式變體（spec.md「CBZ 支援」）
      return const EngineDispatchKnown(true);
    case BookFormat.pdf:
    case BookFormat.unknown:
      return const EngineDispatchNotApplicable();
  }
}

/// 開書後回報如何改寫「FXL 外觀開關」：宣告為 true（含強制 FXL、CBZ）時忽略回報，
/// 保持 [current]；其餘以 [reported] 為準。
bool reconcileFixedLayoutFlag({
  required bool? declared,
  required bool reported,
  required bool current,
}) {
  // 宣告為固定版面（含「強制 FXL」）時，外觀開關已在開書前同步設好，
  // 不受 native view 非同步回報覆蓋。
  return declared == true ? current : reported;
}
