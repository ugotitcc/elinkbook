import { applyTextConversionToString } from "./text-conversion.js";
import { origToDisplay, displayToOrig } from "./text-offset-map.js";
const EXCLUDED_TAGS = /* @__PURE__ */ new Set(["RT", "SCRIPT", "STYLE"]);
function applyTextConversion(doc, mode) {
  const root = doc.body ?? doc.documentElement ?? doc;
  const walker = doc.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
    acceptNode: (node2) => {
      const tag = node2.parentElement ? node2.parentElement.tagName.toUpperCase() : "";
      return EXCLUDED_TAGS.has(tag) ? NodeFilter.FILTER_REJECT : NodeFilter.FILTER_ACCEPT;
    }
  });
  let node = walker.nextNode();
  while (node) {
    if (node._elinkOrigText === void 0) node._elinkOrigText = node.nodeValue;
    const { text, offsetMap } = applyTextConversionToString(node._elinkOrigText, mode);
    node._elinkOffsetMap = offsetMap;
    if (node.nodeValue !== text) node.nodeValue = text;
    node = walker.nextNode();
  }
}
function adjustOffsetForCfi(node, offset, direction) {
  const map = node ? node._elinkOffsetMap : null;
  if (direction === "origToDisplay") {
    const dispOffset = origToDisplay(map, offset);
    return node && typeof node.nodeValue === "string" ? Math.min(dispOffset, node.nodeValue.length) : dispOffset;
  }
  return displayToOrig(map, offset, direction === "displayToOrig-ceil" ? "ceil" : "floor");
}
const isTextNode = (node) => node && node.nodeType === 3;
function toOriginalRange(liveRange) {
  if (!liveRange) return liveRange;
  const startOffset = isTextNode(liveRange.startContainer) ? adjustOffsetForCfi(liveRange.startContainer, liveRange.startOffset, "displayToOrig-floor") : liveRange.startOffset;
  const endOffset = isTextNode(liveRange.endContainer) ? adjustOffsetForCfi(liveRange.endContainer, liveRange.endOffset, "displayToOrig-ceil") : liveRange.endOffset;
  return {
    startContainer: liveRange.startContainer,
    startOffset,
    endContainer: liveRange.endContainer,
    endOffset,
    collapsed: liveRange.startContainer === liveRange.endContainer && startOffset === endOffset
  };
}
function resolveDisplayRange(doc, anchor) {
  const root = doc.body ?? doc.documentElement ?? doc;
  const walker = doc.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
    acceptNode: (node2) => node2._elinkOffsetMap ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_REJECT
  });
  const swapped = [];
  let node = walker.nextNode();
  while (node) {
    swapped.push({ node, displayValue: node.nodeValue });
    node.nodeValue = node._elinkOrigText;
    node = walker.nextNode();
  }
  let captured = null;
  try {
    const origRange = anchor(doc);
    if (origRange) {
      captured = {
        startContainer: origRange.startContainer,
        startOffset: origRange.startOffset,
        endContainer: origRange.endContainer,
        endOffset: origRange.endOffset
      };
    }
  } finally {
    for (const { node: n, displayValue } of swapped) n.nodeValue = displayValue;
  }
  if (!captured) return null;
  const range = doc.createRange();
  range.setStart(
    captured.startContainer,
    isTextNode(captured.startContainer) ? adjustOffsetForCfi(captured.startContainer, captured.startOffset, "origToDisplay") : captured.startOffset
  );
  range.setEnd(
    captured.endContainer,
    isTextNode(captured.endContainer) ? adjustOffsetForCfi(captured.endContainer, captured.endOffset, "origToDisplay") : captured.endOffset
  );
  return range;
}
export {
  adjustOffsetForCfi,
  applyTextConversion,
  resolveDisplayRange,
  toOriginalRange
};
