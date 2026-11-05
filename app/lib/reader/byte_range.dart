/// HTTP Range 標頭解析（RFC 9110 第 14 節）。
sealed class ByteRangeResult {
  const ByteRangeResult();

  const factory ByteRangeResult.full() = ByteRangeFull;
  const factory ByteRangeResult.partial(int start, int end) = ByteRangePartial;
  const factory ByteRangeResult.unsatisfiable() = ByteRangeUnsatisfiable;
}

/// 整檔回傳（200 OK）。
class ByteRangeFull extends ByteRangeResult {
  const ByteRangeFull();

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is ByteRangeFull;

  @override
  int get hashCode => 0;

  @override
  String toString() => 'ByteRangeFull()';
}

/// 部分範圍回傳（206 Partial Content），[start] 與 [end] 皆為含頭尾的位元組索引。
class ByteRangePartial extends ByteRangeResult {
  final int start;
  final int end;

  const ByteRangePartial(this.start, this.end);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ByteRangePartial && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'ByteRangePartial($start, $end)';
}

/// 範圍無法滿足（416 Range Not Satisfiable）。
class ByteRangeUnsatisfiable extends ByteRangeResult {
  const ByteRangeUnsatisfiable();

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is ByteRangeUnsatisfiable;

  @override
  int get hashCode => 1;

  @override
  String toString() => 'ByteRangeUnsatisfiable()';
}

/// 解析 HTTP `Range` 標頭並計算位元組範圍。
///
/// 符合 RFC 9110 第 14 節規範：
/// - [header] 為 `null`、空字串或無法辨識的單位時回傳 [ByteRangeFull]（以整檔 200 回應）。
/// - 多段範圍（含逗點）暫不支援，回退為 [ByteRangeFull]。
/// - 範圍無效（如 `start > end`）或格式無法解析時回退為 [ByteRangeFull]。
/// - 起點超過檔尾（`start >= fileLength`）、`bytes=-0`、或檔案大小為 0 時的任何範圍請求，回傳 [ByteRangeUnsatisfiable]（416）。
/// - 終點超出檔尾時自動截斷至 `fileLength - 1`。
ByteRangeResult parseByteRange(String? header, int fileLength) {
  if (header == null) return const ByteRangeResult.full();
  final trimmed = header.trim();
  if (trimmed.isEmpty) return const ByteRangeResult.full();

  if (fileLength <= 0) {
    return const ByteRangeResult.unsatisfiable();
  }

  if (!trimmed.startsWith('bytes=')) {
    return const ByteRangeResult.full();
  }

  final spec = trimmed.substring(6).trim();
  if (spec.contains(',')) {
    // 多段範圍不支援，回退整檔
    return const ByteRangeResult.full();
  }

  if (spec.startsWith('-')) {
    final suffixStr = spec.substring(1).trim();
    if (suffixStr == '0') {
      return const ByteRangeResult.unsatisfiable();
    }
    final suffixLen = int.tryParse(suffixStr);
    if (suffixLen == null || suffixLen <= 0) {
      return const ByteRangeResult.full();
    }
    if (suffixLen >= fileLength) {
      return ByteRangeResult.partial(0, fileLength - 1);
    }
    return ByteRangeResult.partial(fileLength - suffixLen, fileLength - 1);
  }

  final dashIndex = spec.indexOf('-');
  if (dashIndex == -1) {
    return const ByteRangeResult.full();
  }

  final startStr = spec.substring(0, dashIndex).trim();
  final endStr = spec.substring(dashIndex + 1).trim();

  final start = int.tryParse(startStr);
  if (start == null || start < 0) {
    return const ByteRangeResult.full();
  }

  if (start >= fileLength) {
    return const ByteRangeResult.unsatisfiable();
  }

  if (endStr.isEmpty) {
    return ByteRangeResult.partial(start, fileLength - 1);
  }

  final end = int.tryParse(endStr);
  if (end == null || end < 0) {
    return const ByteRangeResult.full();
  }

  if (start > end) {
    return const ByteRangeResult.full();
  }

  final clampedEnd = end >= fileLength ? fileLength - 1 : end;
  return ByteRangeResult.partial(start, clampedEnd);
}
