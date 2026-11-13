function createOffsetMapBuilder() {
  const entries = [];
  let accumDelta = 0;
  return {
    /**
     * @param {number} origOffset 原文中此區段的起始 offset（UTF-16）。
     * @param {number} origLen 原文中此區段的長度（UTF-16）。
     * @param {number} dispOffset 顯示文字中此區段的起始 offset（UTF-16）。
     * @param {number} dispLen 顯示文字中此區段的長度（UTF-16）。
     */
    addSegment(origOffset, origLen, dispOffset, dispLen) {
      const delta = dispLen - origLen;
      entries.push({ origOffset, origLen, dispOffset, dispLen, delta, accumDelta });
      accumDelta += delta;
    },
    /** @returns {{ entries: object[] } | null} 沒有任何區段時回傳 null。 */
    build() {
      return entries.length === 0 ? null : { entries };
    }
  };
}
function origToDisplay(offsetMap, origOffset) {
  if (!offsetMap || offsetMap.entries.length === 0) return origOffset;
  const entries = offsetMap.entries;
  let low = 0;
  let high = entries.length - 1;
  let matchedIndex = -1;
  while (low <= high) {
    const mid = low + high >> 1;
    const entry2 = entries[mid];
    if (entry2.origOffset <= origOffset) {
      matchedIndex = mid;
      low = mid + 1;
    } else {
      high = mid - 1;
    }
  }
  if (matchedIndex === -1) return origOffset;
  const entry = entries[matchedIndex];
  if (origOffset < entry.origOffset + entry.origLen) {
    const intraOffset = origOffset - entry.origOffset;
    const clampedIntra = Math.min(intraOffset, entry.dispLen);
    return entry.dispOffset + clampedIntra;
  }
  return origOffset + entry.accumDelta + entry.delta;
}
function displayToOrig(offsetMap, dispOffset, snapPolicy = "floor") {
  if (!offsetMap || offsetMap.entries.length === 0) return dispOffset;
  const entries = offsetMap.entries;
  let low = 0;
  let high = entries.length - 1;
  let matchedIndex = -1;
  while (low <= high) {
    const mid = low + high >> 1;
    const entry2 = entries[mid];
    if (entry2.dispOffset <= dispOffset) {
      matchedIndex = mid;
      low = mid + 1;
    } else {
      high = mid - 1;
    }
  }
  if (matchedIndex === -1) return dispOffset;
  const entry = entries[matchedIndex];
  if (dispOffset < entry.dispOffset + entry.dispLen) {
    return snapPolicy === "ceil" ? entry.origOffset + entry.origLen : entry.origOffset;
  }
  return dispOffset - (entry.accumDelta + entry.delta);
}
export {
  createOffsetMapBuilder,
  displayToOrig,
  origToDisplay
};
