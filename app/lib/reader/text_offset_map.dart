import 'dart:math' as math;

/// 雙向分段偏移映射（Piecewise Offset Mapping，見
/// `docs/epics/epic-42-text-conversion/offset-mapping-spec.md` 第 2 節）：
/// 記錄一個文字節點中，長度會改變的置換區段（原文 offset/長度、顯示文字
/// offset/長度），供 [origToDisplay]／[displayToOrig] 在原文與顯示文字
/// 之間互相換算 UTF-16 offset，讓 EPUB CFI（恆依原文）與 live DOM（顯示
/// 轉換後文字）在座標系不同時仍能正確對應。
class OffsetEntry {
  /// 原文中，此置換區段的起始 offset（UTF-16 code unit）。
  final int origOffset;

  /// 原文中，此置換區段的長度（UTF-16 code unit）。
  final int origLen;

  /// 顯示文字中，此置換區段的起始 offset（UTF-16 code unit）。
  final int dispOffset;

  /// 顯示文字中，此置換區段的長度（UTF-16 code unit）。
  final int dispLen;

  /// dispLen - origLen（長度增減量）。
  final int delta;

  /// 此區段之前所有區段的累計 delta。
  final int accumDelta;

  const OffsetEntry({
    required this.origOffset,
    required this.origLen,
    required this.dispOffset,
    required this.dispLen,
    required this.delta,
    required this.accumDelta,
  });
}

/// 一個文字節點的完整偏移映射，`entries` 依 [OffsetEntry.origOffset]
/// 遞增排序。`null`（而非空的 [TextOffsetMap]）代表這個節點轉換後長度
/// 完全不變——[origToDisplay]／[displayToOrig] 對 `null` 一律原樣回傳輸入
/// offset，零額外開銷（見 offset-mapping-spec.md 2.1 節「記憶體最佳化」）。
class TextOffsetMap {
  final List<OffsetEntry> entries;
  const TextOffsetMap(this.entries);
}

/// 累加建構 [TextOffsetMap] 的可變 builder：呼叫端在掃描/替換文字的過程
/// 中，每遇到一個長度改變的置換區段就呼叫一次 [addSegment]，全部處理完
/// 後呼叫 [build]——沒有任何區段時回傳 `null`，代表這個節點可以走零開銷
/// 路徑（見 [TextOffsetMap] 文件）。
class OffsetMapBuilder {
  final List<OffsetEntry> _entries = [];
  int _accumDelta = 0;

  void addSegment({
    required int origOffset,
    required int origLen,
    required int dispOffset,
    required int dispLen,
  }) {
    final delta = dispLen - origLen;
    _entries.add(OffsetEntry(
      origOffset: origOffset,
      origLen: origLen,
      dispOffset: dispOffset,
      dispLen: dispLen,
      delta: delta,
      accumDelta: _accumDelta,
    ));
    _accumDelta += delta;
  }

  TextOffsetMap? build() => _entries.isEmpty ? null : TextOffsetMap(_entries);
}

/// 原文 offset → 顯示文字 offset（見 offset-mapping-spec.md 2.2 節第 1
/// 式）。用於 CFI 還原劃線（`toRange`）、搜尋結果高亮、TTS 朗讀進度定位。
/// [offsetMap] 為 `null`（或沒有任何區段）時直接原樣回傳（零開銷路徑）。
int origToDisplay(TextOffsetMap? offsetMap, int origOffset) {
  if (offsetMap == null || offsetMap.entries.isEmpty) return origOffset;

  final entries = offsetMap.entries;
  var low = 0;
  var high = entries.length - 1;
  var matchedIndex = -1;
  while (low <= high) {
    final mid = (low + high) >> 1;
    final entry = entries[mid];
    if (entry.origOffset <= origOffset) {
      matchedIndex = mid;
      low = mid + 1;
    } else {
      high = mid - 1;
    }
  }

  if (matchedIndex == -1) return origOffset;

  final entry = entries[matchedIndex];
  if (origOffset < entry.origOffset + entry.origLen) {
    final intraOffset = origOffset - entry.origOffset;
    // 審查修正 C-2：片語「縮短」時（dispLen < origLen，例如「公共汽車」
    // (4) -> 「公車」(2)，TWPhrases.txt 實際存在 237 條此類詞彙），
    // intraOffset 可能超出顯示詞的實際長度（例如原文第 4 個字元的
    // intraOffset=3，但顯示詞只有 2 個字元）。必須夾在 [0, dispLen] 內，
    // 否則回傳值會指向顯示文字節點長度以外的位置，live DOM 呼叫
    // range.setEnd() 時直接拋出 IndexSizeError；夾住同時修復了單調性
    // 破壞（未夾住時，區段內最後一個 offset 的回傳值會大於區段之後緊接
    // 的 offset 回傳值）。
    final clampedIntra = math.min(intraOffset, entry.dispLen);
    return entry.dispOffset + clampedIntra;
  }

  return origOffset + entry.accumDelta + entry.delta;
}

/// 顯示文字 offset → 原文 offset（見 offset-mapping-spec.md 2.2 節第 2
/// 式）。用於使用者在畫面選取文字建立劃線（`fromRange`）時，換算出應
/// 存入 CFI 的原文 offset。[snapPolicy]（`'floor'`／`'ceil'`）決定 offset
/// 落在置換詞中間時要貼齊詞首還是詞尾——選取起點用 `'floor'`、選取終點
/// 用 `'ceil'`，確保框選結果涵蓋整個置換詞，不會切在詞彙中間。
int displayToOrig(
  TextOffsetMap? offsetMap,
  int dispOffset, {
  String snapPolicy = 'floor',
}) {
  assert(
    snapPolicy == 'floor' || snapPolicy == 'ceil',
    'snapPolicy 必須為 \'floor\' 或 \'ceil\'，收到："$snapPolicy"',
  );
  if (offsetMap == null || offsetMap.entries.isEmpty) return dispOffset;

  final entries = offsetMap.entries;
  var low = 0;
  var high = entries.length - 1;
  var matchedIndex = -1;
  while (low <= high) {
    final mid = (low + high) >> 1;
    final entry = entries[mid];
    if (entry.dispOffset <= dispOffset) {
      matchedIndex = mid;
      low = mid + 1;
    } else {
      high = mid - 1;
    }
  }

  if (matchedIndex == -1) return dispOffset;

  final entry = entries[matchedIndex];
  if (dispOffset < entry.dispOffset + entry.dispLen) {
    return snapPolicy == 'ceil'
        ? entry.origOffset + entry.origLen
        : entry.origOffset;
  }

  return dispOffset - (entry.accumDelta + entry.delta);
}
