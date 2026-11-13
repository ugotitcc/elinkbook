import { makeBook } from "./view.js";
import { Overlayer } from "./overlayer.js";
import { compare as compareCfi } from "./epubcfi.js";
import { resolveTtsSafeWindowDirection } from "./tts-safe-window.js";
import {
  applyTextConversion,
  toOriginalRange,
  resolveDisplayRange
} from "./text-conversion-walker.js";
import { convertTtsSegments } from "./text-conversion.js";
import {
  compensateColumnPitch,
  measureColumnPitch,
  PITCH_TOLERANCE
} from "./column-pitch.js";
const view = document.getElementById("view");
const originalGetCFI = view.getCFI.bind(view);
view.getCFI = (index, range) => originalGetCFI(index, toOriginalRange(range));
const originalResolveCFI = view.resolveCFI.bind(view);
view.resolveCFI = (cfi) => {
  const resolved = originalResolveCFI(cfi);
  if (!resolved) return resolved;
  const { index, anchor } = resolved;
  return { index, anchor: (doc) => resolveDisplayRange(doc, anchor) };
};
function drawVerticalUnderlineLeft(rects, options = {}) {
  const { color = "red", width: strokeWidth = 2, padding = 0 } = options;
  const g = document.createElementNS("http://www.w3.org/2000/svg", "g");
  g.setAttribute("fill", color);
  for (const { left, top, height } of rects) {
    const el = document.createElementNS("http://www.w3.org/2000/svg", "rect");
    el.setAttribute("x", left - strokeWidth / 2 - padding);
    el.setAttribute("y", top);
    el.setAttribute("height", height);
    el.setAttribute("width", strokeWidth);
    g.append(el);
  }
  return g;
}
const params = new URLSearchParams(location.search);
const initialPrefs = JSON.parse(params.get("prefs") || "{}");
const fontFaceCss = params.get("fontFaceCss") || "";
const initialCfi = params.get("initialCfi") || "";
const initialProgressionParam = params.get("initialProgression");
const initialProgression = initialProgressionParam === null ? NaN : parseFloat(initialProgressionParam);
const isIndexMode = params.get("mode") === "index";
const isDesktopKeys = params.get("desktopKeys") === "1";
const forwardDesktopKey = (evt) => {
  const key = evt.key;
  const lower = typeof key === "string" ? key.toLowerCase() : "";
  const isMatch = key === "ArrowLeft" || key === "ArrowRight" || key === "ArrowUp" || key === "ArrowDown" || key === "PageUp" || key === "PageDown" || key === " " || key === "Home" || key === "End" || key === "F11" || key === "Escape" || lower === "f" && (evt.ctrlKey || evt.metaKey);
  if (!isMatch) return;
  evt.preventDefault();
  if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
    window.flutter_inappwebview.callHandler("onDesktopKey", {
      key: evt.key,
      shiftKey: !!evt.shiftKey,
      ctrlKey: !!evt.ctrlKey,
      altKey: !!evt.altKey,
      metaKey: !!evt.metaKey
    });
  }
};
if (isDesktopKeys) {
  window.addEventListener("keydown", forwardDesktopKey, { capture: true });
}
const WRITING_MODE_DECLARATION_RE = /(?:^|[^-])(?:-epub-|-webkit-)?writing-mode\s*:\s*(?:vertical-(?:rl|lr)|tb(?:-rl)?)(?![\w-])/i;
function declaresVerticalWritingMode(cssText) {
  return WRITING_MODE_DECLARATION_RE.test(String(cssText).replace(/\/\*[\s\S]*?\*\//g, " "));
}
let detectedBookWritingMode = null;
let currentWritingMode = "horizontal";
let lastAppliedPrefs = initialPrefs;
let currentTextConversion = initialPrefs.textConversion || "original";
let decorationIdByCfi = /* @__PURE__ */ new Map();
let lastDecorations = [];
function firstColumnRange(view2, range, columnCount) {
  try {
    const renderer = view2.renderer;
    const start = renderer == null ? void 0 : renderer.start;
    const size = renderer == null ? void 0 : renderer.size;
    if (typeof start !== "number" || !(size > 0) || !(columnCount > 1)) return null;
    const doc = range.startContainer.ownerDocument ?? range.startContainer;
    const win = doc.defaultView;
    if (!win) return null;
    const rootStyle = win.getComputedStyle(doc.documentElement);
    const vertical = (rootStyle.writingMode || "").startsWith("vertical");
    if (!vertical && rootStyle.direction === "rtl") return null;
    const pos = (r) => vertical ? r.top : r.left;
    const boundary = start + size / columnCount;
    let reachesSecond = false;
    for (const r of range.getClientRects()) {
      if (pos(r) >= boundary) {
        reachesSecond = true;
        break;
      }
    }
    if (!reachesSecond) return null;
    const charPos = (node2, i) => {
      const r = doc.createRange();
      r.setStart(node2, i);
      r.setEnd(node2, i + 1);
      const rects = r.getClientRects();
      return rects.length ? pos(rects[0]) : NaN;
    };
    const walker = doc.createTreeWalker(range.commonAncestorContainer, NodeFilter.SHOW_TEXT);
    let node = range.startContainer;
    if (node.nodeType !== 3) {
      node = node.childNodes[range.startOffset] ?? node;
      walker.currentNode = node;
      if (node.nodeType !== 3) node = walker.nextNode();
    } else {
      walker.currentNode = node;
    }
    let lastNode = null;
    let lastOffset = 0;
    for (; node; node = walker.nextNode()) {
      if (range.comparePoint(node, 0) > 0) break;
      const len = node.nodeValue.length;
      const from = node === range.startContainer ? range.startOffset : 0;
      const to = node === range.endContainer ? range.endOffset : len;
      if (to <= from) continue;
      const lastPos = charPos(node, to - 1);
      if (lastPos < boundary) {
        lastNode = node;
        lastOffset = to;
        continue;
      }
      if (Number.isNaN(lastPos)) continue;
      let lo = from;
      let hi = to - 1;
      while (lo < hi) {
        const mid = lo + hi >> 1;
        if (charPos(node, mid) >= boundary) hi = mid;
        else lo = mid + 1;
      }
      if (lo > from) {
        lastNode = node;
        lastOffset = lo;
      }
      break;
    }
    if (!lastNode) return null;
    const result = range.cloneRange();
    result.setEnd(lastNode, lastOffset);
    return result;
  } catch (_) {
    return null;
  }
}
function resolveFlowableTocItemId(view2, detail) {
  var _a, _b, _c, _d;
  const fallback = ((_a = detail == null ? void 0 : detail.tocItem) == null ? void 0 : _a.id) ?? null;
  try {
    const sectionIndex = (_b = detail == null ? void 0 : detail.section) == null ? void 0 : _b.current;
    const columnCount = (_c = view2 == null ? void 0 : view2.renderer) == null ? void 0 : _c.columnCount;
    if (typeof sectionIndex !== "number" || !detail.range) return fallback;
    if (!(columnCount > 1)) return fallback;
    const firstColumn = firstColumnRange(view2, detail.range, columnCount);
    if (!firstColumn) return fallback;
    const item = (_d = view2.getProgressOf(sectionIndex, firstColumn)) == null ? void 0 : _d.tocItem;
    return (item == null ? void 0 : item.id) ?? fallback;
  } catch (_) {
    return fallback;
  }
}
function applyBodyFontScale(doc, prefs) {
  const body = doc == null ? void 0 : doc.body;
  const win = doc == null ? void 0 : doc.defaultView;
  if (!body || !win || typeof win.getComputedStyle !== "function") return;
  body.style.removeProperty("font-size");
  const scale = prefs == null ? void 0 : prefs.fontSize;
  if (typeof scale !== "number" || scale === 1 || !(scale > 0)) return;
  const root = doc.documentElement;
  const oldInline = root.style.getPropertyValue("font-size");
  const oldPriority = root.style.getPropertyPriority("font-size");
  let followsRoot = true;
  let basePx = 0;
  try {
    root.style.setProperty("font-size", "16px", "important");
    const atSmall = parseFloat(win.getComputedStyle(body).fontSize);
    root.style.setProperty("font-size", "32px", "important");
    const atLarge = parseFloat(win.getComputedStyle(body).fontSize);
    followsRoot = Math.abs(atSmall - atLarge) > 0.01;
    basePx = atSmall;
  } finally {
    if (oldInline) root.style.setProperty("font-size", oldInline, oldPriority);
    else root.style.removeProperty("font-size");
  }
  if (!followsRoot && basePx > 0) {
    body.style.setProperty("font-size", `${basePx * scale}px`);
  }
}
function markNoIndentParagraphs(doc, prefs) {
  if (!doc) return;
  if (typeof (prefs == null ? void 0 : prefs.firstLineIndent) !== "number") {
    for (const p of doc.querySelectorAll("p[data-elink-no-indent]")) {
      p.removeAttribute("data-elink-no-indent");
    }
    return;
  }
  const skipCentered = !prefs.textAlign;
  const win = doc.defaultView;
  const canCompute = !!win && typeof win.getComputedStyle === "function";
  const toAdd = [];
  const toRemove = [];
  for (const p of doc.querySelectorAll("p")) {
    const empty = (p.textContent || "").trim() === "";
    const centered = !empty && skipCentered && canCompute && (win.getComputedStyle(p).textAlign || "").includes("center");
    const exclude = empty || centered;
    const marked = p.hasAttribute("data-elink-no-indent");
    if (exclude && !marked) toAdd.push(p);
    else if (!exclude && marked) toRemove.push(p);
  }
  for (const p of toAdd) p.setAttribute("data-elink-no-indent", "");
  for (const p of toRemove) p.removeAttribute("data-elink-no-indent");
}
function buildOverrideCss(prefs) {
  const rules = [];
  const selector = prefs.publisherStyles === false ? "*" : "body, p, div, li, span, td, th, blockquote, dd, dt, a, h1, h2, h3, h4, h5, h6";
  if (prefs.publisherStyles === false) {
    rules.push("* { margin: 0 !important; padding: 0 !important; }");
    rules.push("ul, ol { padding-left: 40px !important; }");
  }
  if (prefs.writingMode === "vertical") {
    rules.push("html, body { writing-mode: vertical-rl !important; }");
  } else if (prefs.writingMode === "horizontal") {
    rules.push("html, body { writing-mode: horizontal-tb !important; }");
  }
  if (prefs.fontFamily) {
    rules.push(`${selector} { font-family: '${prefs.fontFamily}' !important; }`);
  }
  if (prefs.headingFontFamily) {
    const headingTags = ["h1", "h2", "h3", "h4", "h5", "h6"];
    const headingSelector = headingTags.map((h) => `${h}, ${h} *`).join(", ");
    rules.push(`${headingSelector} { font-family: '${prefs.headingFontFamily}' !important; }`);
  }
  if (typeof prefs.fontSize === "number") {
    rules.push(`html { font-size: ${prefs.fontSize * 100}% !important; }`);
  }
  if (typeof prefs.fontWeight === "number") {
    const cssWeight = Math.min(1e3, Math.max(1, Math.round(prefs.fontWeight * 400)));
    rules.push(`${selector} { font-weight: ${cssWeight} !important; }`);
  }
  if (typeof prefs.lineHeight === "number") {
    const effectiveLineHeight = Math.max(0.8, prefs.lineHeight);
    rules.push(`${selector} { line-height: ${effectiveLineHeight} !important; }`);
  }
  if (typeof prefs.paragraphSpacing === "number") {
    rules.push(`p { margin-block-end: ${prefs.paragraphSpacing}em !important; }`);
  }
  if (typeof prefs.firstLineIndent === "number") {
    rules.push(`p:not([data-elink-no-indent]) { text-indent: ${prefs.firstLineIndent}em !important; }`);
    rules.push("p[data-elink-no-indent] { text-indent: 0 !important; }");
  }
  if (typeof prefs.letterSpacing === "number") {
    rules.push(`${selector} { letter-spacing: ${prefs.letterSpacing}em !important; }`);
  }
  if (prefs.textAlign) {
    rules.push(`p { text-align: ${prefs.textAlign} !important; }`);
  }
  if (prefs.textColor) {
    rules.push(`${selector} { color: ${prefs.textColor} !important; }`);
  }
  if (prefs.backgroundColor) {
    rules.push(`html, body { background-color: ${prefs.backgroundColor} !important; }`);
  }
  return rules.join("\n");
}
function isDualPageEnabled(dualPageMode, isLandscape) {
  return dualPageMode === "always" || dualPageMode === "auto" && isLandscape === true;
}
window.applyPreferences = function(prefs) {
  var _a, _b;
  lastAppliedPrefs = prefs;
  view.clearLocationDensity();
  const previousTextConversion = currentTextConversion;
  if (prefs.textConversion) {
    currentTextConversion = prefs.textConversion;
  }
  if (!isIndexMode && prefs.textConversion && prefs.textConversion !== previousTextConversion) {
    for (const { doc } of view.renderer.getContents()) {
      applyTextConversion(doc, currentTextConversion);
    }
    if (lastDecorations.length > 0) {
      window.setDecorations(lastDecorations);
    }
  }
  if (view.isFixedLayout) {
    if (prefs.pageTurnMode) {
      view.renderer.setAttribute(
        "flow",
        prefs.pageTurnMode === "scroll" ? "scrolled" : "paginated"
      );
    }
    if (prefs.writingMode) {
      currentWritingMode = prefs.writingMode;
    }
    (_a = view.renderer) == null ? void 0 : _a.setAttribute(
      "spread",
      isDualPageEnabled(prefs.dualPageMode, prefs.isLandscape) ? "both" : "none"
    );
    return;
  }
  if (prefs.pageTurnMode) {
    view.renderer.setAttribute(
      "flow",
      prefs.pageTurnMode === "scroll" ? "scrolled" : "paginated"
    );
  }
  const previousWritingMode = currentWritingMode;
  if (prefs.writingMode) {
    currentWritingMode = prefs.writingMode;
  }
  view.renderer.setAttribute(
    "max-column-count",
    currentWritingMode === "vertical" ? "1" : "2"
  );
  if (prefs.columnMode === "single") {
    view.renderer.setAttribute("max-inline-size", "99999px");
  } else if (prefs.columnMode === "double") {
    const hostRect = view.renderer.getBoundingClientRect();
    const hostSize = currentWritingMode === "vertical" ? hostRect.height : hostRect.width;
    const targetSize = Math.max(360, Math.ceil(hostSize / 2));
    view.renderer.setAttribute("max-inline-size", `${targetSize}px`);
  } else {
    if (typeof prefs.columnSize === "number") {
      view.renderer.setAttribute("max-inline-size", `${prefs.columnSize}px`);
    }
  }
  const marginTopPx = typeof prefs.marginTop === "number" ? prefs.marginTop : 32;
  const marginBottomPx = typeof prefs.marginBottom === "number" ? prefs.marginBottom : 16;
  view.renderer.setAttribute("margin-top", `${marginTopPx}px`);
  view.renderer.setAttribute("margin-bottom", `${marginBottomPx}px`);
  const marginLeftPx = typeof prefs.marginLeft === "number" ? prefs.marginLeft : 24;
  const marginRightPx = typeof prefs.marginRight === "number" ? prefs.marginRight : 24;
  view.renderer.setAttribute("margin-left", `${marginLeftPx}px`);
  view.renderer.setAttribute("margin-right", `${marginRightPx}px`);
  view.renderer.setStyles([fontFaceCss, buildOverrideCss(prefs)]);
  for (const { doc } of view.renderer.getContents()) {
    applyBodyFontScale(doc, prefs);
    markNoIndentParagraphs(doc, prefs);
  }
  if (prefs.writingMode && prefs.writingMode !== previousWritingMode) {
    const cfi = (_b = view.lastLocation) == null ? void 0 : _b.cfi;
    if (cfi) view.goTo(cfi);
  }
};
window.__applyPreferencesReady = true;
if (window.__pendingApplyPreferences) {
  const pendingPrefs = window.__pendingApplyPreferences;
  window.__pendingApplyPreferences = null;
  window.applyPreferences(pendingPrefs);
}
window.nextPage = function() {
  view.next();
};
window.previousPage = function() {
  view.prev();
};
window.jumpToFraction = function(fraction) {
  view.goToFraction(fraction);
};
function resolveValidatedCfi(cfi) {
  var _a, _b;
  let resolved;
  try {
    resolved = view.resolveNavigation(cfi);
  } catch (_) {
    return null;
  }
  if (!resolved || !Number.isInteger(resolved.index)) return null;
  const sectionCount = ((_b = (_a = view.book) == null ? void 0 : _a.sections) == null ? void 0 : _b.length) ?? 0;
  if (resolved.index < 0 || resolved.index >= sectionCount) return null;
  return resolved;
}
async function goToFractionSafely(fraction) {
  if (!Number.isFinite(fraction)) return false;
  try {
    await view.goToFraction(Math.min(1, Math.max(0, fraction)));
    return true;
  } catch (_) {
    return false;
  }
}
function reportNavigationDegraded(reason) {
  window.flutter_inappwebview.callHandler("onNavigationDegraded", reason);
}
async function openAtInitialLocation() {
  if (!initialCfi) {
    await view.init({});
    return;
  }
  const resolved = resolveValidatedCfi(initialCfi);
  if (resolved) {
    try {
      await view.renderer.goTo(resolved);
      view.history.pushState(initialCfi);
      return;
    } catch (_) {
    }
  }
  if (!await goToFractionSafely(initialProgression)) {
    await view.init({});
  }
  reportNavigationDegraded("readingPosition");
}
window.jumpToLocator = async function(cfi, fallbackProgression) {
  const resolved = resolveValidatedCfi(cfi);
  if (resolved) {
    const result = await view.goTo(cfi);
    if (result) return;
  }
  await goToFractionSafely(fallbackProgression);
  reportNavigationDegraded("annotation");
};
window.setDecorations = function(decorations) {
  lastDecorations = decorations;
  for (const cfi of decorationIdByCfi.keys()) {
    view.deleteAnnotation({ value: cfi });
  }
  decorationIdByCfi = /* @__PURE__ */ new Map();
  for (const { id, cfi, color, isUnderline } of decorations) {
    decorationIdByCfi.set(cfi, id);
    view.addAnnotation({ value: cfi, color, isUnderline });
  }
};
const TTS_HIGHLIGHT_COLOR = "rgba(251, 146, 60, 0.45)";
const TTS_HIGHLIGHT_COLOR_EINK = "rgba(0, 0, 0, 0.75)";
let currentTtsAnnotationValue = null;
window.showTtsHighlight = function(cfi, vertical, einkMode) {
  if (currentTtsAnnotationValue) {
    view.deleteAnnotation({ value: currentTtsAnnotationValue });
  }
  currentTtsAnnotationValue = "foliate-note:" + cfi;
  view.addAnnotation({
    value: currentTtsAnnotationValue,
    color: einkMode ? TTS_HIGHLIGHT_COLOR_EINK : TTS_HIGHLIGHT_COLOR,
    isUnderline: false,
    vertical
  });
};
window.clearTtsHighlight = function() {
  if (!currentTtsAnnotationValue) return;
  view.deleteAnnotation({ value: currentTtsAnnotationValue });
  currentTtsAnnotationValue = null;
};
let currentSearchHighlightValue = null;
window.showSearchHighlight = function(cfi) {
  if (currentSearchHighlightValue) {
    view.deleteAnnotation({ value: currentSearchHighlightValue });
  }
  currentSearchHighlightValue = "foliate-search:" + cfi;
  view.addAnnotation({ value: currentSearchHighlightValue });
};
window.clearSearchHighlight = function() {
  if (!currentSearchHighlightValue) return;
  view.deleteAnnotation({ value: currentSearchHighlightValue });
  currentSearchHighlightValue = null;
};
window.lookupTtsSegmentIndex = function(visibleCfi, segmentCfis) {
  try {
    let index = -1;
    if (segmentCfis.length > 0) {
      index = segmentCfis.findIndex((cfi) => compareCfi(cfi, visibleCfi) >= 0);
      if (index === -1) index = segmentCfis.length - 1;
    }
    window.flutter_inappwebview.callHandler("onTtsSegmentIndexReady", index);
  } catch (e) {
    window.flutter_inappwebview.callHandler("onTtsSegmentIndexReady", -1);
  }
};
window.clearSelection = function() {
  var _a;
  for (const { doc } of view.renderer.getContents()) {
    (_a = doc.getSelection()) == null ? void 0 : _a.removeAllRanges();
  }
};
let selectionSuspended = false;
let suspendedSelections = [];
window.suspendSelection = function() {
  if (selectionSuspended) return;
  selectionSuspended = true;
  suspendedSelections = [];
  for (const { doc } of view.renderer.getContents()) {
    const sel = doc.getSelection();
    if (!sel || sel.rangeCount === 0 || sel.isCollapsed) continue;
    suspendedSelections.push({
      doc,
      ranges: Array.from({ length: sel.rangeCount }, (_, i) => sel.getRangeAt(i).cloneRange())
    });
    sel.removeAllRanges();
  }
};
window.restoreSelection = function() {
  if (!selectionSuspended) return;
  selectionSuspended = false;
  const saved = suspendedSelections;
  suspendedSelections = [];
  for (const { doc, ranges } of saved) {
    const sel = doc.getSelection();
    if (!sel) continue;
    sel.removeAllRanges();
    for (const r of ranges) sel.addRange(r);
  }
};
async function buildTocEntry(item) {
  const resolved = item.href ? view.book.resolveHref(item.href) : null;
  let cfi = null;
  let index = null;
  let fraction = null;
  if (resolved && resolved.index >= 0) {
    index = resolved.index;
    try {
      const doc = await view.book.sections[index].createDocument();
      const frag = resolved.anchor(doc);
      let range;
      if (frag instanceof Range) {
        range = frag;
      } else if (frag && frag.nodeType) {
        range = doc.createRange();
        range.selectNodeContents(frag);
      }
      cfi = view.getCFI(index, range);
    } catch (e) {
      cfi = view.getCFI(index, void 0);
    }
    if (cfi) {
      const progress = await view.getCFIProgress(cfi);
      fraction = (progress == null ? void 0 : progress.fraction) ?? null;
    }
  }
  const children = [];
  for (const sub of item.subitems ?? []) {
    children.push(await buildTocEntry(sub));
  }
  return {
    title: item.label ?? "",
    locatorJson: cfi ? JSON.stringify({ cfi, index, fraction }) : "",
    progression: fraction,
    // epic-54 Issue 20：foliate TOCProgress.assignIDs 指派的唯一整數 id
    //（DFS 前序、從 0 起；0 為合法值，故用 ?? 不用 ||），供 Dart 端與
    // relocate 回報的 tocItem.id 直接比對。
    tocId: item.id ?? null,
    children
  };
}
window.getTableOfContents = async function() {
  var _a;
  try {
    const items = ((_a = view.book) == null ? void 0 : _a.toc) ?? [];
    const entries = [];
    for (const item of items) {
      entries.push(await buildTocEntry(item));
    }
    window.flutter_inappwebview.callHandler("onTableOfContentsReady", JSON.stringify(entries));
  } catch (e) {
    window.flutter_inappwebview.callHandler("onTableOfContentsReady", JSON.stringify([]));
  }
};
async function extractSegmentsForSection(sectionIndex) {
  const doc = await view.book.sections[sectionIndex].createDocument();
  const walker = doc.createTreeWalker(doc.body, NodeFilter.SHOW_TEXT, {
    acceptNode: (node2) => {
      const tag = node2.parentElement ? node2.parentElement.tagName.toUpperCase() : "";
      return tag === "RT" || tag === "SCRIPT" ? NodeFilter.FILTER_REJECT : NodeFilter.FILTER_ACCEPT;
    }
  });
  let fullText = "";
  const offsetMap = [];
  let node = walker.nextNode();
  while (node) {
    const text = node.textContent || "";
    for (let i = 0; i < text.length; i++) {
      offsetMap.push({ node, offset: i });
    }
    fullText += text;
    node = walker.nextNode();
  }
  const terminators = /[。！？；.!?;]/;
  const TTS_SECONDARY_BOUNDARY_MIN_LENGTH = 200;
  const secondaryBoundary = /\s/;
  const segments = [];
  let start = 0;
  let segmentIndex = 0;
  for (let i = 0; i < fullText.length; i++) {
    const isLast = i === fullText.length - 1;
    const isPrimaryBoundary = terminators.test(fullText[i]);
    const isSecondaryBoundary = !isPrimaryBoundary && i - start >= TTS_SECONDARY_BOUNDARY_MIN_LENGTH && secondaryBoundary.test(fullText[i]);
    if (isPrimaryBoundary || isSecondaryBoundary || isLast) {
      let rangeStart = start;
      while (rangeStart < i && /\s/.test(fullText[rangeStart])) rangeStart++;
      const trimmed = fullText.slice(start, i + 1).trim();
      if (trimmed.length > 0) {
        const startMap = offsetMap[rangeStart];
        const endMap = offsetMap[i];
        const range = doc.createRange();
        range.setStart(startMap.node, startMap.offset);
        range.setEnd(endMap.node, endMap.offset + 1);
        const cfi = view.getCFI(sectionIndex, range);
        segments.push({ segmentId: String(segmentIndex), cfi, text: trimmed });
        segmentIndex++;
      }
      start = i + 1;
    }
  }
  return segments;
}
window.buildTtsSegments = async function(sectionIndex) {
  try {
    const segments = await extractSegmentsForSection(sectionIndex);
    const converted = convertTtsSegments(segments, currentTextConversion);
    window.flutter_inappwebview.callHandler(
      "onTtsSegmentsReady",
      sectionIndex,
      JSON.stringify(converted)
    );
  } catch (e) {
    window.flutter_inappwebview.callHandler(
      "onTtsSegmentsReady",
      sectionIndex,
      JSON.stringify([])
    );
  }
};
window.buildSegmentsForSection = async function(sectionIndex) {
  try {
    const segments = await extractSegmentsForSection(sectionIndex);
    window.flutter_inappwebview.callHandler(
      "onSegmentsForSectionReady",
      sectionIndex,
      JSON.stringify(segments)
    );
  } catch (e) {
    window.flutter_inappwebview.callHandler(
      "onSegmentsForSectionReady",
      sectionIndex,
      JSON.stringify([])
    );
  }
};
window.getSectionCount = function() {
  try {
    const count = view.book && view.book.sections ? view.book.sections.length : 0;
    window.flutter_inappwebview.callHandler("onSectionCountReady", count);
  } catch (e) {
    window.flutter_inappwebview.callHandler("onSectionCountReady", 0);
  }
};
const LONG_PRESS_GATE_MS = 500;
const SWIPE_DISTANCE_DEADZONE_PX = 15;
const SWIPE_VELOCITY_ESCAPE_PX_PER_MS = 0.3;
const ANNOTATION_CLICK_TAP_MAX_MS = 700;
const SELECTION_RELEASE_GUARD_MS = 150;
console.assert(
  LONG_PRESS_GATE_MS <= ANNOTATION_CLICK_TAP_MAX_MS,
  "\u9577\u6309\u5019\u9078\u9580\u6ABB\u5FC5\u9808 <= \u5FEB\u901F\u9EDE\u64CA\u9580\u6ABB\uFF0C\u5426\u5247\u5169\u500B\u6A5F\u5236\u7684\u512A\u5148\u9806\u5E8F\u5047\u8A2D\u6703\u88AB\u7834\u58DE"
);
class TouchIntentClassifier {
  constructor() {
    this.gesture = { state: "idle", startX: 0, startY: 0, startTime: 0 };
    this.lastTouchStartTime = null;
    this.lastNonCollapsedSelectionAtMs = null;
  }
}
const INLINE_STYLE_SCAN_LIMIT = 20;
function safeLoadText(book, href) {
  return Promise.resolve().then(() => book.loadText(href)).catch(() => null);
}
async function detectBookWritingMode(book) {
  var _a, _b, _c;
  const resources = book.resources;
  if (!(resources == null ? void 0 : resources.manifest)) return null;
  const metaEl = (_a = resources.opf) == null ? void 0 : _a.querySelector(
    'meta[name="primary-writing-mode"], meta[property="primary-writing-mode"]'
  );
  const meta = (metaEl == null ? void 0 : metaEl.getAttribute("content")) || (metaEl == null ? void 0 : metaEl.textContent);
  if (meta && /^\s*vertical/i.test(meta)) return "vertical";
  for (const item of resources.manifest) {
    if (((_b = item.mediaType) == null ? void 0 : _b.toLowerCase()) !== "text/css") continue;
    const css = await safeLoadText(book, item.href);
    if (css && declaresVerticalWritingMode(css)) return "vertical";
  }
  const INLINE_STYLE_RE = /<style[^>]*>([\s\S]*?)<\/style>|<[a-z][^>]*?\sstyle\s*=\s*(?:"([^"]*)"|'([^']*)')/gi;
  let scanned = 0;
  for (const { idref } of resources.spine) {
    if (scanned >= INLINE_STYLE_SCAN_LIMIT) break;
    const item = resources.getItemByID(idref);
    if (!item) continue;
    const type = (_c = item.mediaType) == null ? void 0 : _c.toLowerCase();
    if (type !== "application/xhtml+xml" && type !== "text/html") continue;
    scanned++;
    const xhtml = await safeLoadText(book, item.href);
    if (!xhtml) continue;
    INLINE_STYLE_RE.lastIndex = 0;
    let m;
    while ((m = INLINE_STYLE_RE.exec(xhtml)) !== null) {
      const styleText = m[1] ?? m[2] ?? m[3] ?? "";
      if (declaresVerticalWritingMode(styleText)) return "vertical";
    }
  }
  return "horizontal";
}
async function openBook() {
  var _a, _b;
  try {
    let bookBase = params.get("bookBaseUrl") || "https://appassets.androidplatform.net/book/";
    if (!bookBase.endsWith("/")) bookBase += "/";
    const book = await makeBook(
      bookBase + (params.get("bookFileName") || "current.epub")
    );
    if (!isIndexMode && !initialPrefs.writingMode) {
      detectedBookWritingMode = await detectBookWritingMode(book).catch(() => null);
    }
    (_a = book.transformTarget) == null ? void 0 : _a.addEventListener("data", (e) => {
      if (e.detail.type !== "text/css") return;
      e.detail.data = Promise.resolve(e.detail.data).then((css) => {
        if (detectedBookWritingMode === null) {
          detectedBookWritingMode = declaresVerticalWritingMode(css) ? "vertical" : "horizontal";
        }
        let overriddenCss = `${css}
html, body { --overlayer-highlight-opacity: 1; }
`;
        if (initialPrefs.writingMode) {
          const override = initialPrefs.writingMode === "vertical" ? "writing-mode: vertical-rl !important;" : "writing-mode: horizontal-tb !important;";
          overriddenCss += `html, body { ${override} }
`;
        }
        return overriddenCss;
      });
    });
    view.addEventListener("relocate", () => {
      const resolvedWritingMode = initialPrefs.writingMode ?? detectedBookWritingMode ?? "horizontal";
      window.applyPreferences({ ...initialPrefs, writingMode: resolvedWritingMode });
      window.flutter_inappwebview.callHandler(
        "onPageRendered",
        resolvedWritingMode,
        !!view.isFixedLayout
      );
    }, { once: true });
    view.addEventListener("relocate", (e) => {
      var _a2;
      const { cfi, section, fraction, location: location2 } = e.detail;
      const chapterIndex = (section == null ? void 0 : section.current) ?? 0;
      const position = view.isFixedLayout && view.renderer ? {
        fraction: fraction ?? 0,
        locationIndex: null,
        locationTotal: null,
        visualPageIndex: view.renderer.page ?? 0,
        visualTotalPages: view.renderer.pages ?? 0,
        tocItemId: ((_a2 = e.detail.tocItem) == null ? void 0 : _a2.id) ?? null
      } : {
        fraction: fraction ?? 0,
        locationIndex: (location2 == null ? void 0 : location2.current) ?? chapterIndex,
        locationTotal: (location2 == null ? void 0 : location2.total) ?? 0,
        visualPageIndex: null,
        visualTotalPages: null,
        // epic-66 Issue 24：雙欄時以第一欄範圍內最後一個目錄項判定（單欄與回退
        // 維持 e.detail.tocItem），見 resolveFlowableTocItemId()。
        tocItemId: resolveFlowableTocItemId(view, e.detail)
      };
      window.flutter_inappwebview.callHandler(
        "onLocatorChanged",
        JSON.stringify({ cfi, index: chapterIndex, fraction: fraction ?? 0 }),
        JSON.stringify(position)
      );
    });
    view.addEventListener("draw-annotation", (e) => {
      const { draw, annotation, doc, range } = e.detail;
      const isVertical = annotation.vertical ?? currentWritingMode === "vertical";
      if (annotation.isUnderline) {
        draw(isVertical ? drawVerticalUnderlineLeft : Overlayer.underline, {
          color: annotation.color,
          writingMode: "horizontal-tb"
        });
      } else {
        draw(Overlayer.highlight, {
          color: annotation.color,
          vertical: isVertical
        });
      }
      if (annotation.value === currentTtsAnnotationValue) {
        const rects = range.getClientRects();
        const frameEl = doc.defaultView && doc.defaultView.frameElement;
        const direction = resolveTtsSafeWindowDirection(
          rects[0],
          rects[rects.length - 1],
          frameEl && frameEl.getBoundingClientRect(),
          view.getBoundingClientRect(),
          isVertical
        );
        if (direction) {
          window.flutter_inappwebview.callHandler("onTtsHighlightOutOfSafeWindow", direction);
        }
      }
    });
    view.addEventListener("load", (e) => {
      if (isIndexMode) return;
      const doc = e.detail.doc;
      const index = e.detail.index;
      if (isDesktopKeys && doc) {
        doc.addEventListener("keydown", forwardDesktopKey, { capture: true });
      }
      applyTextConversion(doc, currentTextConversion);
      applyBodyFontScale(doc, lastAppliedPrefs);
      markNoIndentParagraphs(doc, lastAppliedPrefs);
      attachColumnPitchCompensation(doc);
      const classifier = new TouchIntentClassifier();
      const reportSelection = async () => {
        if (selectionSuspended) return;
        const selection = doc.getSelection();
        if (!selection || selection.rangeCount === 0 || selection.isCollapsed) {
          classifier.lastNonCollapsedSelectionAtMs = null;
          window.flutter_inappwebview.callHandler("onSelectionCleared");
          return;
        }
        classifier.lastNonCollapsedSelectionAtMs = doc.defaultView.performance.now();
        const range = selection.getRangeAt(0);
        const rect = range.getClientRects()[0];
        if (!rect) return;
        const cfi = view.getCFI(index, range);
        const progress = await view.getCFIProgress(cfi);
        const iframeRect = doc.defaultView.frameElement.getBoundingClientRect();
        const viewportRect = view.getBoundingClientRect();
        const overlayerEntry = view.renderer.getContents().find((c) => c.index === index);
        const hit = (overlayerEntry == null ? void 0 : overlayerEntry.overlayer) ? overlayerEntry.overlayer.hitTest({ x: (rect.left + rect.right) / 2, y: (rect.top + rect.bottom) / 2 }) : [];
        const hitCfi = hit[0];
        const existingAnnotationId = hitCfi ? decorationIdByCfi.get(hitCfi) ?? null : null;
        window.flutter_inappwebview.callHandler(
          "onSelectionChanged",
          JSON.stringify({ cfi, index, fraction: (progress == null ? void 0 : progress.fraction) ?? 0 }),
          (progress == null ? void 0 : progress.fraction) ?? 0,
          (iframeRect.left + rect.left - viewportRect.left) / viewportRect.width,
          (iframeRect.top + rect.top - viewportRect.top) / viewportRect.height,
          (iframeRect.left + rect.right - viewportRect.left) / viewportRect.width,
          (iframeRect.top + rect.bottom - viewportRect.top) / viewportRect.height,
          selection.toString(),
          existingAnnotationId
        );
      };
      doc.addEventListener("selectionchange", reportSelection);
      doc.addEventListener("contextmenu", (evt) => {
        evt.preventDefault();
        reportSelection();
      });
      doc.addEventListener("pointercancel", () => reportSelection());
      doc.addEventListener("touchstart", (evt) => {
        const touch = evt.touches[0];
        if (!touch || evt.touches.length > 1) {
          classifier.gesture = { state: "idle", startX: 0, startY: 0, startTime: 0 };
          return;
        }
        classifier.gesture = {
          state: "longPressCandidate",
          startX: touch.screenX,
          startY: touch.screenY,
          startTime: evt.timeStamp
        };
      }, { capture: true });
      doc.addEventListener("touchmove", (evt) => {
        if (classifier.gesture.state !== "longPressCandidate") return;
        if (evt.touches.length > 1) {
          classifier.gesture = { state: "idle", startX: 0, startY: 0, startTime: 0 };
          return;
        }
        const selection = doc.getSelection();
        if (selection && selection.rangeCount > 0 && !selection.isCollapsed) {
          classifier.gesture = { state: "idle", startX: 0, startY: 0, startTime: 0 };
          return;
        }
        const touch = evt.touches[0];
        if (!touch) return;
        const elapsed = evt.timeStamp - classifier.gesture.startTime;
        const dx = touch.screenX - classifier.gesture.startX;
        const dy = touch.screenY - classifier.gesture.startY;
        const distance = Math.hypot(dx, dy);
        const avgVelocity = elapsed > 0 ? distance / elapsed : Infinity;
        if (elapsed >= LONG_PRESS_GATE_MS || distance > SWIPE_DISTANCE_DEADZONE_PX || avgVelocity > SWIPE_VELOCITY_ESCAPE_PX_PER_MS) {
          classifier.gesture.state = "swiping";
          return;
        }
        evt.preventDefault();
        evt.stopImmediatePropagation();
      }, { capture: true, passive: false });
      doc.addEventListener("touchend", () => {
        classifier.gesture = { state: "idle", startX: 0, startY: 0, startTime: 0 };
      }, { capture: true });
      doc.addEventListener("touchcancel", () => {
        classifier.gesture = { state: "idle", startX: 0, startY: 0, startTime: 0 };
      }, { capture: true });
      doc.addEventListener("touchstart", (evt) => {
        classifier.lastTouchStartTime = evt.touches.length === 1 ? evt.timeStamp : null;
      }, { capture: true });
      doc.addEventListener("touchcancel", () => {
        classifier.lastTouchStartTime = null;
      }, { capture: true });
      doc.addEventListener("mousedown", (evt) => {
        if (!evt.target.closest("a[href]") && classifier.lastNonCollapsedSelectionAtMs !== null && evt.timeStamp - classifier.lastNonCollapsedSelectionAtMs <= SELECTION_RELEASE_GUARD_MS) {
          evt.preventDefault();
        }
      }, { capture: true });
      doc.addEventListener("click", (evt) => {
        const startTime = classifier.lastTouchStartTime;
        classifier.lastTouchStartTime = null;
        if (startTime === null) return;
        if (evt.target.closest("a[href]")) return;
        if (evt.timeStamp - startTime <= ANNOTATION_CLICK_TAP_MAX_MS) {
          evt.stopImmediatePropagation();
        }
      }, { capture: true });
    });
    if (initialPrefs.isFixedLayoutHint === true && ((_b = book.rendition) == null ? void 0 : _b.layout) !== "pre-paginated") {
      book.rendition = { ...book.rendition, layout: "pre-paginated" };
    }
    if (initialPrefs.isComicBookHint === true) {
      book.dir = initialPrefs.dualPageDirection === "rtl" ? "rtl" : "ltr";
      book.toc = book.sections.map((section, i) => ({
        label: `\u7B2C ${i + 1} \u9801`,
        href: section.id
      }));
    }
    await view.open(book);
    view.renderer.setAttribute("no-swipe", "");
    view.renderer.setAttribute(
      "flow",
      initialPrefs.pageTurnMode === "scroll" ? "scrolled" : "paginated"
    );
    if (!view.isFixedLayout && typeof view.renderer.getContents === "function") {
      let reconcileTimer = null;
      let reconcileRuns = 0;
      const reconcileSectionLayouts = () => {
        reconcileTimer = null;
        const widths = view.renderer.getContents().map((c) => {
          var _a2, _b2, _c;
          return parseFloat((_c = (_b2 = (_a2 = c.doc) == null ? void 0 : _a2.documentElement) == null ? void 0 : _b2.style) == null ? void 0 : _c.columnWidth);
        }).filter((w) => Number.isFinite(w));
        const consistent = widths.length < 2 || widths.every((w) => Math.abs(w - widths[0]) <= 1);
        if (consistent) {
          reconcileRuns = 0;
          return;
        }
        if (reconcileRuns >= 3) return;
        reconcileRuns++;
        view.renderer.render();
      };
      view.renderer.addEventListener("create-overlayer", () => {
        if (reconcileTimer) clearTimeout(reconcileTimer);
        reconcileTimer = setTimeout(reconcileSectionLayouts, 0);
      });
    }
    let resizeDebounceTimer = null;
    const hostResizeObserver = new ResizeObserver(() => {
      if (resizeDebounceTimer) clearTimeout(resizeDebounceTimer);
      resizeDebounceTimer = setTimeout(() => {
        window.applyPreferences(lastAppliedPrefs);
      }, 200);
    });
    hostResizeObserver.observe(view.renderer);
    await openAtInitialLocation();
  } catch (e) {
    window.flutter_inappwebview.callHandler("onError", String(e && e.message || e));
  }
}
let columnPitchGaveUpWarned = false;
function canCompensateColumnPitch(doc) {
  if (!doc || !doc.defaultView || !doc.documentElement || !doc.body) return false;
  if (view.isFixedLayout) return false;
  const renderer = view.renderer;
  if (!renderer || renderer.scrolled !== false) return false;
  if (!(renderer.size > 0)) return false;
  const win = doc.defaultView;
  const rootWm = win.getComputedStyle(doc.documentElement).writingMode || "";
  const bodyWm = win.getComputedStyle(doc.body).writingMode || "";
  return rootWm.indexOf("vertical") === 0 || bodyWm.indexOf("vertical") === 0;
}
function attachColumnPitchCompensation(doc) {
  if (!doc || !doc.defaultView || !doc.documentElement || !doc.body) return;
  if (view.isFixedLayout) return;
  let busy = false;
  let gaveUpTarget = null;
  const observer = new MutationObserver(() => {
    if (!doc.defaultView || !doc.documentElement || !doc.body) return;
    if (busy) return;
    runCompensation();
  });
  function runCompensation() {
    if (busy) return;
    if (!canCompensateColumnPitch(doc)) return;
    const renderer = view.renderer;
    const columnCount = renderer.columnCount || 1;
    const target = renderer.size / columnCount;
    if (!(target > PITCH_TOLERANCE)) return;
    if (gaveUpTarget === target) return;
    busy = true;
    try {
      const result = compensateColumnPitch({
        target,
        measure: () => measureColumnPitch(Array.from(doc.body.getClientRects()), true),
        getBoxHeight: () => doc.documentElement.getBoundingClientRect().height,
        setMaxHeight: (px) => {
          doc.documentElement.style.setProperty(
            "max-height",
            px + "px",
            "important"
          );
        },
        resetMaxHeight: () => {
          doc.documentElement.style.setProperty(
            "max-height",
            "none",
            "important"
          );
        }
      });
      gaveUpTarget = result.status === "gave-up" ? target : null;
      if (result.status === "gave-up" && !columnPitchGaveUpWarned) {
        columnPitchGaveUpWarned = true;
        console.warn("[column-pitch] \u88DC\u511F\u5931\u6557\uFF0C\u7DAD\u6301\u539F\u6392\u7248");
      }
    } finally {
      observer.takeRecords();
      busy = false;
    }
  }
  observer.observe(doc.documentElement, {
    attributes: true,
    attributeFilter: ["style"]
  });
}
openBook();
