/// 記憶體洩漏判定結果（epic-66 Issue 3 Task 1）。
class LeakVerdict {
  /// 第 1 到 N 次迭代相對於上一次的私有記憶體增量（MB）。
  final List<double> deltas;

  /// 超過門檻的迭代編號（1-based 索引，對應第 1～N 次）。
  final List<int> exceededIterations;

  /// 是否判定洩漏（任一次增量嚴格大於門檻）。
  final bool leaked;

  /// 是否呈棘輪式持續上升（第 1～N 次增量皆 > 0）。
  final bool ratcheting;

  /// 判定門檻（MB）＝ [bookMb] * [thresholdRatio]。
  final double thresholdMb;

  const LeakVerdict({
    required this.deltas,
    required this.exceededIterations,
    required this.leaked,
    required this.ratcheting,
    required this.thresholdMb,
  });

  @override
  String toString() =>
      'LeakVerdict(leaked: $leaked, deltas: $deltas, exceeded: $exceededIterations, ratcheting: $ratcheting, thresholdMb: $thresholdMb)';
}

/// 依 [privateMb] 歷史序列判定是否發生記憶體洩漏。
///
/// - [privateMb]: 長度至少為 2 的序列。`privateMb[0]` 為暖身基線，`privateMb[i]`（i ≥ 1）為第 i 次等待回落後的私有記憶體（MB）。
/// - [bookMb]: 書籍檔案大小（MB）。
/// - [thresholdRatio]: 判定門檻比例，預設 0.05（即 5%）。
LeakVerdict evaluateLeak({
  required List<double> privateMb,
  required double bookMb,
  double thresholdRatio = 0.05,
}) {
  if (privateMb.length < 2) {
    throw ArgumentError.value(
      privateMb,
      'privateMb',
      '至少需要一筆基線（第 0 次）與至少一次迭代數據',
    );
  }

  final thresholdMb = bookMb * thresholdRatio;
  final deltas = <double>[];
  final exceededIterations = <int>[];

  for (var i = 1; i < privateMb.length; i++) {
    final delta = privateMb[i] - privateMb[i - 1];
    deltas.add(delta);
    if (delta > thresholdMb) {
      exceededIterations.add(i);
    }
  }

  final leaked = exceededIterations.isNotEmpty;
  final ratcheting = deltas.isNotEmpty && deltas.every((d) => d > 0);

  return LeakVerdict(
    deltas: List.unmodifiable(deltas),
    exceededIterations: List.unmodifiable(exceededIterations),
    leaked: leaked,
    ratcheting: ratcheting,
    thresholdMb: thresholdMb,
  );
}
