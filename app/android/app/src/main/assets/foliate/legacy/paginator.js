var __defProp = Object.defineProperty;
var __typeError = (msg) => {
  throw TypeError(msg);
};
var __defNormalProp = (obj, key, value) => key in obj ? __defProp(obj, key, { enumerable: true, configurable: true, writable: true, value }) : obj[key] = value;
var __publicField = (obj, key, value) => __defNormalProp(obj, typeof key !== "symbol" ? key + "" : key, value);
var __accessCheck = (obj, member, msg) => member.has(obj) || __typeError("Cannot " + msg);
var __privateGet = (obj, member, getter) => (__accessCheck(obj, member, "read from private field"), getter ? getter.call(obj) : member.get(obj));
var __privateAdd = (obj, member, value) => member.has(obj) ? __typeError("Cannot add the same private member more than once") : member instanceof WeakSet ? member.add(obj) : member.set(obj, value);
var __privateSet = (obj, member, value, setter) => (__accessCheck(obj, member, "write to private field"), setter ? setter.call(obj, value) : member.set(obj, value), value);
var __privateMethod = (obj, member, method) => (__accessCheck(obj, member, "access private method"), method);
var __privateWrapper = (obj, member, setter, getter) => ({
  set _(value) {
    __privateSet(obj, member, value, setter);
  },
  get _() {
    return __privateGet(obj, member, getter);
  }
});
var _observer, _element, _iframe, _contentRange, _overlayer, _vertical, _rtl, _docDirection, _loadedDoc, _directionStyle, _column, _size, _columnCount, _layout, _contentPages, _bgImageSize, _View_instances, setProgressionDirection_fn, demoteUnfragmentableBoxes_fn, zoom_get, _loupeEl, _loupeScaler, _loupeCursor, _root, _observer2, _top, _background, _container, _header, _footer, _views, _primaryIndex, _units, _firstUnit, _bookSections, _chunkCache, _splits, _vertical2, _rtl2, _marginTop, _marginBottom, _anchor, _justAnchored, _locked, _pagePreview, _cancelPagePreview, _styles, _styleMap, _mediaQuery, _mediaQueryListener, _scrollBounds, _touchState, _touchScrolled, _lastVisibleRange, _scrollLocked, _subpixelOffset, _isAnimating, _slideTurnId, _dragTranslateX, _vtDrag, _vtFinishing, _vtProgrammatic, _vtNamedHost, _bgAnimContext, _filling, _fillPromise, _stabilizing, _rendered, _lastLayout, _columnGap, _directionCache, _Paginator_instances, primaryView_get, sortedViews_get, flushScrolledState_fn, _transformTarget, _transformCSS, splitSection_fn, spineOf_fn, toUnitTarget_fn, createView_fn, syncA11y_fn, destroyView_fn, destroyAllViews_fn, clearViewsExcept_fn, isSameDirection_fn, readBackgroundStyle_fn, computePaginatedBgContext_fn, paintPaginatedBackground_fn, replaceBackground_fn, beforeRender_fn, layeredTurn_get, renderedViewSize_get, renderedStart_get, renderedEnd_get, renderedPage_get, renderedPages_get, onTouchStart_fn, onTouchMove_fn, vtSetup_fn, vtCleanup_fn, rejectLayeredGesture_fn, layeredDragStart_fn, vtDragScrub_fn, finishLayeredDrag_fn, dragBy_fn, settleDrag_fn, onTouchEnd_fn, onTouchCancel_fn, getRectMapper_fn, scrollToRect_fn, scrollTo_fn, viewTransitionTurn_fn, scrollToPage_fn, scrollToAnchor_fn, getViewOffset_fn, getPagesBeforeView_fn, getVisibleRange_fn, anchorIsVisible_fn, detectPrimaryView_fn, preloadNext_fn, afterScroll_fn, display_fn, loadAdjacentSection_fn, fillVisibleArea_fn, trimDistantViews_fn, canGoToIndex_fn, goTo_fn, goToUnit_fn, scrollPrev_fn, scrollNext_fn, adjacentIndex_fn, adjacentUnit_fn, turnPage_fn, applyStyles_fn;
import { CHUNK_ATTRIBUTE, splitSection } from "./section-chunks.js";
const wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
const CHUNK_THRESHOLD = 512 * 1024;
const CHUNK_SIZE = 256 * 1024;
const yieldToFrame = () => document.hidden ? wait(0) : new Promise((resolve) => requestAnimationFrame(() => setTimeout(resolve, 0)));
const fontsReady = (doc) => {
  var _a, _b, _c;
  const fonts = doc == null ? void 0 : doc.fonts;
  const win = doc == null ? void 0 : doc.defaultView;
  if (!fonts || !win) return Promise.resolve();
  const buggyWebKit = ((_b = (_a = win.navigator) == null ? void 0 : _a.userAgent) == null ? void 0 : _b.includes("AppleWebKit/605")) && typeof ((_c = win.URL) == null ? void 0 : _c.canParse) !== "function";
  if (!buggyWebKit) return fonts.ready;
  return new Promise((resolve) => {
    const poll = () => fonts.status === "loaded" ? resolve() : win.setTimeout(poll, 100);
    poll();
  });
};
const isTypingOutside = () => {
  const el = document.activeElement;
  return !!el && (el.isContentEditable || el.localName === "textarea" || el.localName === "input");
};
const debounce = (f, wait2, immediate) => {
  let timeout;
  return (...args) => {
    const later = () => {
      timeout = null;
      if (!immediate) f(...args);
    };
    const callNow = immediate && !timeout;
    if (timeout) clearTimeout(timeout);
    timeout = setTimeout(later, wait2);
    if (callNow) f(...args);
  };
};
const SCROLL_RELOCATE_MAX_WAIT = 1e3;
const cssAnimateScroll = (element, scrollProp, startValue, endValue, duration, extraElements = []) => new Promise((resolve) => {
  if (document.hidden) {
    element[scrollProp] = endValue;
    return resolve();
  }
  const children = [...element.children];
  if (!children.length) {
    element[scrollProp] = endValue;
    return resolve();
  }
  const allElements = [...children, ...extraElements];
  const isHorizontal = scrollProp === "scrollLeft";
  const delta = endValue - startValue;
  const transformProp = isHorizontal ? "translateX" : "translateY";
  for (const el of allElements) {
    el.style.willChange = "transform";
    el.style.transform = `${transformProp}(0px)`;
    el.style.transition = "none";
  }
  element.getBoundingClientRect();
  for (const el of allElements) {
    el.style.transition = `transform ${duration}ms cubic-bezier(0.25, 0.46, 0.45, 0.94)`;
    el.style.transform = `${transformProp}(${-delta}px)`;
  }
  let resolved = false;
  const cleanup = () => {
    if (resolved) return;
    resolved = true;
    for (const el of allElements) {
      el.style.willChange = "";
      el.style.transform = "";
      el.style.transition = "";
    }
    element[scrollProp] = endValue;
    if (Math.abs(element[scrollProp] - endValue) > 0.5) {
      requestAnimationFrame(() => {
        element[scrollProp] = endValue;
        resolve();
      });
      return;
    }
    resolve();
  };
  const first = children[0];
  const onTransitionEnd = (e) => {
    if (e.target === first && e.propertyName === "transform") {
      first.removeEventListener("transitionend", onTransitionEnd);
      cleanup();
    }
  };
  first.addEventListener("transitionend", onTransitionEnd);
  setTimeout(cleanup, duration + 50);
});
const slideTurnAnimation = (element, scrollProp, endValue, exitSign, width, duration, isStale, onSwap, startX = 0) => new Promise((resolve) => {
  const children = [...element.children];
  if (document.hidden || !children.length) {
    element[scrollProp] = endValue;
    return resolve();
  }
  const half = duration / 2;
  const exitTarget = exitSign * width;
  const exitDuration = Math.max(16, half * Math.min(1, Math.abs(exitTarget - startX) / width));
  const setAll = (transition, transform) => {
    for (const el of children) {
      el.style.transition = transition;
      el.style.transform = transform;
    }
  };
  for (const el of children) el.style.willChange = "transform";
  setAll("none", `translateX(${startX}px)`);
  element.getBoundingClientRect();
  setAll(`transform ${exitDuration}ms cubic-bezier(0.55, 0, 1, 0.45)`, `translateX(${exitTarget}px)`);
  setTimeout(() => {
    if (isStale()) return resolve();
    element[scrollProp] = endValue;
    onSwap == null ? void 0 : onSwap();
    setAll("none", `translateX(${-exitSign * width}px)`);
    element.getBoundingClientRect();
    setAll(`transform ${half}ms cubic-bezier(0, 0.55, 0.45, 1)`, "translateX(0px)");
    setTimeout(() => {
      if (isStale()) return resolve();
      for (const el of children) {
        el.style.willChange = "";
        el.style.transition = "";
        el.style.transform = "";
      }
      resolve();
    }, half + 20);
  }, exitDuration + 10);
});
const VIEW_TRANSITION_CLASSES = [
  "foliate-vt",
  "foliate-vt-slide",
  "foliate-vt-curl",
  "foliate-vt-scrub",
  "foliate-vt-forward",
  "foliate-vt-backward",
  "foliate-vt-left",
  "foliate-vt-right",
  "foliate-vt-eat-left",
  "foliate-vt-eat-right"
];
const RELEASE_VELOCITY_WINDOW_MS = 90;
const RELEASE_PAUSE_THRESHOLD_MS = 80;
const SLIDE_RELEASE_PROJECTION_MS = 240;
const DRAG_TURN_DISTANCE_RATIO = 0.06;
const LAYERED_EDGE_REGION = 0.18;
const LAYERED_EARLY_CLAIM_PX = 6;
const LAYERED_EARLY_SAMPLE_INTERVAL_MS = 80;
const LAYERED_VERTICAL_REJECT_PX = 8;
const LAYERED_FALLBACK_CLAIM_PX = 24;
const LAYERED_FALLBACK_DOMINANCE = 1.5;
const updateReleaseSample = (state, distance, time) => {
  const previous = state.releaseSamples.at(-1);
  if (!previous || distance !== previous.distance) state.lastMovementTime = time;
  if ((previous == null ? void 0 : previous.time) === time) previous.distance = distance;
  else state.releaseSamples.push({ distance, time });
  const cutoff = time - RELEASE_VELOCITY_WINDOW_MS;
  while (state.releaseSamples.length > 2 && state.releaseSamples[1].time < cutoff) state.releaseSamples.shift();
};
const getReleaseVelocity = (state) => {
  const latest = state.releaseSamples.at(-1);
  if (!latest || latest.time - state.lastMovementTime > RELEASE_PAUSE_THRESHOLD_MS) return 0;
  const cutoff = latest.time - RELEASE_VELOCITY_WINDOW_MS;
  const before = state.releaseSamples[0];
  const after = state.releaseSamples.find((sample) => sample.time >= cutoff);
  if (!before || !after) return 0;
  const startTime = Math.max(cutoff, before.time);
  if (latest.time <= startTime) return 0;
  const interval = after.time - before.time;
  const startDistance = interval > 0 && startTime > before.time ? before.distance + (after.distance - before.distance) * (startTime - before.time) / interval : after.distance;
  return (latest.distance - startDistance) / (latest.time - startTime);
};
const LAYERED_SETTLE_CONFIG = {
  slide: { minSpeed: 0.2, maxSpeed: 1, maxRate: 2 },
  curl: { minSpeed: 0.3, maxSpeed: 1.5, maxRate: 1.5 }
};
const layeredSettlePlaybackRate = (style, speed) => {
  const config = LAYERED_SETTLE_CONFIG[style];
  if (!config || !(speed > config.minSpeed)) return 1;
  const { minSpeed, maxSpeed, maxRate } = config;
  const amount = Math.min(1, (speed - minSpeed) / (maxSpeed - minSpeed));
  return 1 + amount * (maxRate - 1);
};
const updatePlaybackRate = (animation, rate) => {
  if (rate === 1) return;
  try {
    animation.updatePlaybackRate(rate);
    return;
  } catch {
  }
  try {
    animation.playbackRate = rate;
  } catch {
  }
};
const injectViewTransitionStyles = () => {
  const id = "foliate-view-transition-styles";
  if (document.getElementById(id)) return;
  const style = document.createElement("style");
  style.id = id;
  style.textContent = `
    .foliate-vt::view-transition {
        pointer-events: none;
    }
    /* Only the page turn animates; keep the root snapshot inert. */
    .foliate-vt::view-transition-old(root),
    .foliate-vt::view-transition-new(root) {
        animation: none;
    }
    /* The turn layers must OCCLUDE, not blend: the UA pairs old/new with
       mix-blend-mode: plus-lighter for its default cross-fade, which turns
       the still page ghostly under a moving page. Also back both layers
       with the page colour, since snapshots of textured themes or books
       without a background are transparent. */
    .foliate-vt::view-transition-old(foliate-turn),
    .foliate-vt::view-transition-new(foliate-turn) {
        animation: none;
        background: var(--foliate-vt-bg, Canvas);
        mix-blend-mode: normal;
    }
    /* Slide: the moving page travels over the still page with a soft edge
       shadow, like the Apple Books slide. Forward moves the outgoing
       snapshot out on top; backward brings the incoming snapshot in on
       top of the still outgoing page. */
    .foliate-vt-slide.foliate-vt-forward::view-transition-old(foliate-turn) {
        z-index: 1;
        animation: foliate-turn-slide-out-left 300ms cubic-bezier(0.25, 0.46, 0.45, 0.94) both;
        box-shadow: 0 0 24px rgba(0, 0, 0, 0.35);
    }
    .foliate-vt-slide.foliate-vt-forward.foliate-vt-right::view-transition-old(foliate-turn) {
        animation-name: foliate-turn-slide-out-right;
    }
    .foliate-vt-slide.foliate-vt-backward::view-transition-new(foliate-turn) {
        animation: foliate-turn-slide-in-left 300ms cubic-bezier(0.25, 0.46, 0.45, 0.94) both;
        box-shadow: 0 0 24px rgba(0, 0, 0, 0.35);
    }
    .foliate-vt-slide.foliate-vt-backward.foliate-vt-right::view-transition-new(foliate-turn) {
        animation-name: foliate-turn-slide-in-right;
    }
    /* Finger-tracked turns map distance directly to animation time. Declare
       linear timing at the CSS source because some Android WebViews expose
       UA pseudo animations but reject KeyframeEffect.updateTiming(). */
    .foliate-vt-scrub::view-transition-old(foliate-turn),
    .foliate-vt-scrub::view-transition-new(foliate-turn) {
        animation-timing-function: linear !important;
    }
    @keyframes foliate-turn-slide-out-left { to { transform: translateX(-100%); } }
    @keyframes foliate-turn-slide-out-right { to { transform: translateX(100%); } }
    @keyframes foliate-turn-slide-in-left { from { transform: translateX(-100%); } }
    @keyframes foliate-turn-slide-in-right { from { transform: translateX(100%); } }
    /* Curl: a fold line travels across the page, peeling it off the still
       page underneath like the Apple Books / Kindle curl. The fold is an
       oversized gradient mask slid across the OLD snapshot (mask-position is
       animatable; gradients themselves are not), so the page dissolves over
       a soft band at the traveling edge \u2014 the lifted-page falloff. Chrome
       paints masks on the static old snapshot but not on the live new layer,
       so backward turns also choreograph the old page: it recedes from the
       spine side, which reads the same as the incoming page unfolding.
       Filters and shadows are applied before masking and would be cut off
       with the page, hence the soft edge. A flat snapshot cannot mesh-bend
       like a native curl; this is the closest two-layer approximation. */
    /* The curl consumes the old page along a CURVED fold: a transparent
       disc grows out of the page's outer-bottom corner (the corner a reader
       lifts), so the fold edge is an arc sweeping across the page toward
       the spine \u2014 the bent-page line of a corner curl. Backward turns grow
       the arc from the spine-side corner instead, receding the old page so
       the previous page appears to unfold (eat side precomputed on the
       root). The fold edge is an animated gradient STOP (registered custom
       property) re-rasterized each frame against the element box:
       mask-position/mask-size animations paint unreliably on
       view-transition pseudos. The 6% band is the lifted-page falloff. */
    @property --foliate-fold {
        syntax: '<percentage>';
        inherits: false;
        initial-value: 0%;
    }
    .foliate-vt-curl.foliate-vt-eat-right::view-transition-old(foliate-turn) {
        z-index: 1;
        -webkit-mask-image: radial-gradient(circle at 108% 108%, transparent calc(var(--foliate-fold) - 6%), black var(--foliate-fold));
        mask-image: radial-gradient(circle at 108% 108%, transparent calc(var(--foliate-fold) - 6%), black var(--foliate-fold));
        animation: foliate-turn-curl-fold 450ms cubic-bezier(0.3, 0.1, 0.4, 1) both;
    }
    .foliate-vt-curl.foliate-vt-eat-left::view-transition-old(foliate-turn) {
        z-index: 1;
        -webkit-mask-image: radial-gradient(circle at -8% 108%, transparent calc(var(--foliate-fold) - 6%), black var(--foliate-fold));
        mask-image: radial-gradient(circle at -8% 108%, transparent calc(var(--foliate-fold) - 6%), black var(--foliate-fold));
        animation: foliate-turn-curl-fold 450ms cubic-bezier(0.3, 0.1, 0.4, 1) both;
    }
    .foliate-vt-curl::view-transition-new(foliate-turn) {
        animation: none;
    }
    @keyframes foliate-turn-curl-fold {
        from { --foliate-fold: 0%; }
        to { --foliate-fold: 118%; }
    }
    `;
  document.head.append(style);
};
const lerp = (min, max, x) => x * (max - min) + min;
const easeOutQuad = (x) => 1 - (1 - x) * (1 - x);
const rafAnimateScroll = (a, b, duration, ease, render) => new Promise((resolve) => {
  let start;
  const step = (now) => {
    if (document.hidden) {
      render(lerp(a, b, 1));
      return resolve();
    }
    start ?? (start = now);
    const fraction = Math.min(1, (now - start) / duration);
    render(lerp(a, b, ease(fraction)));
    if (fraction < 1) requestAnimationFrame(step);
    else resolve();
  };
  if (document.hidden) {
    render(lerp(a, b, 1));
    return resolve();
  }
  requestAnimationFrame(step);
});
const RAF_ANIMATE_SCROLL_THRESHOLD = 2e4;
const uncollapse = (range) => {
  if (!(range == null ? void 0 : range.collapsed)) return range;
  const { endOffset, endContainer } = range;
  if (endContainer.nodeType === 1) {
    const node = endContainer.childNodes[endOffset];
    if ((node == null ? void 0 : node.nodeType) === 1) return node;
    return endContainer;
  }
  if (endOffset + 1 < endContainer.length) range.setEnd(endContainer, endOffset + 1);
  else if (endOffset > 1) range.setStart(endContainer, endOffset - 1);
  else return endContainer.parentNode;
  return range;
};
const makeRange = (doc, node, start, end = start) => {
  const range = doc.createRange();
  range.setStart(node, start);
  range.setEnd(node, end);
  return range;
};
const bisectNode = (doc, node, cb, start = 0, end = node.nodeValue.length) => {
  if (end - start === 1) {
    const result2 = cb(makeRange(doc, node, start), makeRange(doc, node, end));
    return result2 < 0 ? start : end;
  }
  const mid = Math.floor(start + (end - start) / 2);
  const result = cb(makeRange(doc, node, start, mid), makeRange(doc, node, mid, end));
  return result < 0 ? bisectNode(doc, node, cb, start, mid) : result > 0 ? bisectNode(doc, node, cb, mid, end) : mid;
};
const {
  SHOW_ELEMENT,
  SHOW_TEXT,
  SHOW_CDATA_SECTION,
  FILTER_ACCEPT,
  FILTER_REJECT,
  FILTER_SKIP
} = NodeFilter;
const filter = SHOW_ELEMENT | SHOW_TEXT | SHOW_CDATA_SECTION;
const getBoundingClientRect = (target) => {
  let top = Infinity, right = -Infinity, left = Infinity, bottom = -Infinity;
  for (const rect of target.getClientRects()) {
    left = Math.min(left, rect.left);
    top = Math.min(top, rect.top);
    right = Math.max(right, rect.right);
    bottom = Math.max(bottom, rect.bottom);
  }
  return new DOMRect(left, top, right - left, bottom - top);
};
const getVisibleRange = (doc, start, end, mapRect) => {
  if (!(doc == null ? void 0 : doc.body)) return;
  const acceptNode = (node) => {
    var _a, _b, _c;
    const name = (_a = node.localName) == null ? void 0 : _a.toLowerCase();
    if (name === "script" || name === "style") return FILTER_REJECT;
    if (node.nodeType === 1 && ((_b = node.hasAttribute) == null ? void 0 : _b.call(node, "cfi-inert"))) return FILTER_REJECT;
    if (node.nodeType === 1 && node.hasAttribute(CHUNK_ATTRIBUTE)) return FILTER_REJECT;
    if (node.nodeType === 1) {
      const { left, right } = mapRect(node.getBoundingClientRect());
      if (left === 0 && right === 0) return FILTER_REJECT;
      if (right < start || left > end) return FILTER_REJECT;
      if (left >= start && right <= end) return FILTER_ACCEPT;
    } else {
      if (!((_c = node.nodeValue) == null ? void 0 : _c.trim())) return FILTER_SKIP;
      const range2 = doc.createRange();
      range2.selectNodeContents(node);
      const { left, right } = mapRect(range2.getBoundingClientRect());
      if (left === 0 && right === 0) return FILTER_REJECT;
      if (right >= start && left <= end) return FILTER_ACCEPT;
    }
    return FILTER_SKIP;
  };
  const nodes = [];
  const isPlaceholder = (node) => node.nodeType === 1 && node.hasAttribute(CHUNK_ATTRIBUTE);
  let first = doc.body.firstChild, last = doc.body.lastChild;
  while (first && isPlaceholder(first)) first = first.nextSibling;
  while (last && isPlaceholder(last)) last = last.previousSibling;
  for (let child = first; child; child = child.nextSibling) {
    const type = child.nodeType;
    if (type === 1 || type === 3 || type === 4) {
      const result = acceptNode(child);
      if (result === FILTER_ACCEPT) nodes.push(child);
      if (result !== FILTER_REJECT) {
        const walker = doc.createTreeWalker(child, filter, { acceptNode });
        for (let node = walker.nextNode(); node; node = walker.nextNode())
          nodes.push(node);
      }
    }
    if (child === last) break;
  }
  const from = nodes[0] ?? doc.body;
  const to = nodes[nodes.length - 1] ?? from;
  const startOffset = from.nodeType === 1 ? 0 : bisectNode(doc, from, (a, b) => {
    const p = mapRect(getBoundingClientRect(a));
    const q = mapRect(getBoundingClientRect(b));
    if (p.right < start && q.left > start) return 0;
    return q.left > start ? -1 : 1;
  });
  const endOffset = to.nodeType === 1 ? 0 : bisectNode(doc, to, (a, b) => {
    const p = mapRect(getBoundingClientRect(a));
    const q = mapRect(getBoundingClientRect(b));
    if (p.right < end && q.left > end) return 0;
    return q.left > end ? -1 : 1;
  });
  const range = doc.createRange();
  range.setStart(from, startOffset);
  range.setEnd(to, endOffset);
  return range;
};
const selectionIsBackward = (sel) => {
  const range = document.createRange();
  range.setStart(sel.anchorNode, sel.anchorOffset);
  range.setEnd(sel.focusNode, sel.focusOffset);
  return range.collapsed;
};
const setSelectionTo = (target, collapse) => {
  var _a;
  let range;
  if (target.startContainer) range = target.cloneRange();
  else if (target.nodeType) {
    range = document.createRange();
    range.selectNode(target);
  }
  if (range) {
    const sel = (_a = range.startContainer.ownerDocument) == null ? void 0 : _a.defaultView.getSelection();
    if (sel) {
      sel.removeAllRanges();
      if (collapse === -1) range.collapse(true);
      else if (collapse === 1) range.collapse();
      sel.addRange(range);
    }
  }
};
const isViewVisibleInContainer = (viewRect, containerRect) => viewRect.right > containerRect.left && viewRect.left < containerRect.right && viewRect.bottom > containerRect.top && viewRect.top < containerRect.bottom;
const getDirection = (doc) => {
  const { defaultView } = doc;
  if (!defaultView || !doc.body) return { vertical: false, rtl: false };
  let { writingMode, direction } = defaultView.getComputedStyle(doc.body);
  if (!writingMode || writingMode === "horizontal-tb") {
    const firstChild = doc.body.querySelector(":scope > :not([cfi-inert])");
    if (firstChild) {
      const childStyle = defaultView.getComputedStyle(firstChild);
      if (childStyle.writingMode === "vertical-rl" || childStyle.writingMode === "vertical-lr") {
        writingMode = childStyle.writingMode;
      }
    }
  }
  const vertical = writingMode === "vertical-rl" || writingMode === "vertical-lr";
  const rtl = writingMode === "vertical-rl" || doc.body.dir === "rtl" || direction === "rtl" || doc.documentElement.dir === "rtl";
  return { vertical, rtl };
};
const getPageProgressionRTL = (bookDir, documentRTL) => bookDir === "rtl" ? true : bookDir === "ltr" ? false : documentRTL;
const getBackground = (doc) => {
  if (!doc.defaultView || !doc.body) return "";
  const bodyStyle = doc.defaultView.getComputedStyle(doc.body);
  return bodyStyle.backgroundColor === "rgba(0, 0, 0, 0)" && bodyStyle.backgroundImage === "none" ? doc.defaultView.getComputedStyle(doc.documentElement).background : bodyStyle.background;
};
const computeBackgroundSegments = (views, scrollPos, bgSize, inset, containerSize) => {
  const containerStart = inset;
  const containerEnd = inset + containerSize;
  const segments = [];
  let offset = 0;
  for (const view of views) {
    const segStart = inset + offset - scrollPos;
    const segEnd = segStart + view.size;
    offset += view.size;
    if (segEnd <= 0 || segStart >= bgSize) continue;
    if (!view.bg) continue;
    const start = Math.max(segStart, containerStart);
    const end = Math.min(segEnd, containerEnd);
    if (end <= start) continue;
    segments.push({ start, size: end - start, bg: view.bg });
  }
  return segments;
};
const textureAwareBackground = (resolved, hasTexture) => {
  const hasImage = /\burl\(/i.test(resolved ?? "");
  const isTransparent = !hasImage && (!resolved || /^\s*(transparent|rgba\(0,\s*0,\s*0,\s*0\))/.test(resolved));
  return hasTexture && isTransparent ? "" : resolved;
};
const makeMarginals = (length, part) => Array.from({ length }, () => {
  const div = document.createElement("div");
  const child = document.createElement("div");
  div.append(child);
  child.setAttribute("part", part);
  return div;
});
const setStyles = (el, styles) => {
  if (!el) return;
  const { style } = el;
  for (const [k, v] of Object.entries(styles)) style.setProperty(k, v);
};
const setStylesImportant = (el, styles) => {
  if (!el) return;
  const { style } = el;
  for (const [k, v] of Object.entries(styles)) style.setProperty(k, v, "important");
};
class View {
  constructor({ container, onExpand }) {
    __privateAdd(this, _View_instances);
    __privateAdd(this, _observer, new ResizeObserver(() => this.expand()));
    __privateAdd(this, _element, document.createElement("div"));
    __privateAdd(this, _iframe, document.createElement("iframe"));
    __privateAdd(this, _contentRange, document.createRange());
    __privateAdd(this, _overlayer);
    __privateAdd(this, _vertical, false);
    __privateAdd(this, _rtl, false);
    // The document's own inline direction, read before any of our overrides
    // touch it. `#rtl` is the book's page progression, which can disagree.
    __privateAdd(this, _docDirection, "ltr");
    // The document `load()` has taken `#docDirection` from. A re-render can
    // reach this view earlier, while the iframe holds a section whose load
    // event has not fired yet; see `render()`.
    __privateAdd(this, _loadedDoc, null);
    __privateAdd(this, _directionStyle, null);
    __privateAdd(this, _column, true);
    __privateAdd(this, _size);
    __privateAdd(this, _columnCount, 1);
    __privateAdd(this, _layout, {});
    __privateAdd(this, _contentPages, 0);
    __privateAdd(this, _bgImageSize, null);
    __publicField(this, "fontReady", Promise.resolve());
    __privateAdd(this, _loupeEl, null);
    __privateAdd(this, _loupeScaler, null);
    __privateAdd(this, _loupeCursor, null);
    this.container = container;
    this.onExpand = onExpand;
    __privateGet(this, _iframe).setAttribute("part", "filter");
    __privateGet(this, _element).append(__privateGet(this, _iframe));
    Object.assign(__privateGet(this, _element).style, {
      boxSizing: "content-box",
      position: "relative",
      overflow: "hidden",
      flex: "0 0 auto",
      width: "100%",
      height: "100%",
      display: "flex",
      justifyContent: "flex-start",
      alignItems: "center"
    });
    Object.assign(__privateGet(this, _iframe).style, {
      overflow: "hidden",
      border: "0",
      visibility: "hidden",
      width: "100%",
      height: "100%"
    });
    __privateGet(this, _iframe).setAttribute("sandbox", "allow-same-origin allow-scripts");
    __privateGet(this, _iframe).setAttribute("scrolling", "no");
  }
  get element() {
    return __privateGet(this, _element);
  }
  get document() {
    return __privateGet(this, _iframe).contentDocument;
  }
  get contentPages() {
    return __privateGet(this, _contentPages);
  }
  async load(src, data, afterLoad, beforeRender, waitForIdle) {
    if (typeof src !== "string") throw new Error(`${src} is not string`);
    return new Promise((resolve) => {
      __privateGet(this, _iframe).addEventListener("load", async () => {
        var _a, _b;
        if (waitForIdle) await waitForIdle();
        const doc = this.document;
        if (!(doc == null ? void 0 : doc.documentElement) || !doc.body) return resolve();
        await (afterLoad == null ? void 0 : afterLoad(doc));
        await yieldToFrame();
        if (this.document !== doc) return resolve();
        __privateGet(this, _iframe).setAttribute("aria-label", doc.title);
        __privateGet(this, _iframe).style.visibility = "visible";
        const { vertical, rtl } = getDirection(doc);
        this.docBackground = getBackground(doc);
        doc.body.style.background = "none";
        let bgRendered = false;
        const bgUrl = (_b = (_a = this.docBackground) == null ? void 0 : _a.match(/url\(["']?([^"')]+)["']?\)/)) == null ? void 0 : _b[1];
        if (bgUrl && !this.container.noBackground) {
          const img = new Image();
          let resolveWait;
          const waited = new Promise((res) => {
            resolveWait = res;
          });
          img.onload = () => {
            __privateSet(this, _bgImageSize, {
              width: img.naturalWidth,
              height: img.naturalHeight
            });
            if (bgRendered && !__privateGet(this, _column)) this.expand();
            resolveWait();
          };
          img.onerror = () => resolveWait();
          img.src = bgUrl;
          let timer;
          await Promise.race([
            waited,
            new Promise((res) => {
              timer = setTimeout(res, 3e3);
            })
          ]);
          clearTimeout(timer);
          if (waitForIdle) await waitForIdle();
        }
        if (this.document !== doc) return resolve();
        __privateGet(this, _iframe).style.visibility = "hidden";
        __privateSet(this, _vertical, vertical);
        __privateSet(this, _rtl, rtl);
        __privateSet(this, _docDirection, doc.defaultView.getComputedStyle(doc.documentElement).direction === "rtl" ? "rtl" : "ltr");
        __privateSet(this, _loadedDoc, doc);
        __privateGet(this, _contentRange).selectNodeContents(doc.body);
        const layout = beforeRender == null ? void 0 : beforeRender({ vertical, rtl });
        __privateGet(this, _iframe).style.visibility = "visible";
        this.render(layout);
        bgRendered = true;
        __privateGet(this, _observer).observe(doc.body);
        this.fontReady = fontsReady(doc).then(() => this.expand());
        resolve();
      }, { once: true });
      if (data) {
        __privateGet(this, _iframe).srcdoc = data;
      } else {
        __privateGet(this, _iframe).src = src;
      }
    });
  }
  render(layout) {
    var _a;
    if (!layout || !((_a = this.document) == null ? void 0 : _a.documentElement)) return;
    if (this.document !== __privateGet(this, _loadedDoc)) return;
    if (layout.rtl != null) __privateSet(this, _rtl, layout.rtl);
    __privateSet(this, _column, layout.flow !== "scrolled");
    __privateSet(this, _layout, layout);
    __privateMethod(this, _View_instances, setProgressionDirection_fn).call(this, __privateGet(this, _column) && !__privateGet(this, _vertical) ? __privateGet(this, _rtl) ? "rtl" : "ltr" : null);
    if (__privateGet(this, _column)) this.columnize(layout);
    else this.scrolled(layout);
  }
  scrolled({ width, height, marginTop, marginRight, marginBottom, marginLeft, gap, columnWidth }) {
    const vertical = __privateGet(this, _vertical);
    const doc = this.document;
    setStylesImportant(doc.documentElement, {
      "box-sizing": "border-box",
      "column-width": "auto",
      "height": "auto",
      "width": "auto"
    });
    const availableWidth = Math.trunc(width - marginLeft - marginRight);
    const availableHeight = Math.trunc(height - marginTop - marginBottom);
    const sidePaddingLeft = marginLeft / 2 + gap / 2;
    const sidePaddingRight = marginRight / 2 + gap / 2;
    setStyles(doc.documentElement, {
      "padding": vertical ? `${marginTop * 1.5}px 0px ${marginBottom * 1.5}px 0px` : `0px ${sidePaddingRight}px 0px ${sidePaddingLeft}px`,
      "--page-margin-top": `${vertical ? marginTop * 1.5 : marginTop}px`,
      "--page-margin-right": `${vertical ? marginRight : sidePaddingRight}px`,
      "--page-margin-bottom": `${vertical ? marginBottom * 1.5 : marginBottom}px`,
      "--page-margin-left": `${vertical ? marginLeft : sidePaddingLeft}px`,
      "--full-width": `${Math.trunc(width)}`,
      "--full-height": `${Math.trunc(height)}`,
      "--available-width": `${availableWidth}`,
      "--available-height": `${availableHeight}`
    });
    setStylesImportant(doc.body, {
      [vertical ? "max-height" : "max-width"]: `${columnWidth}px`,
      "margin": "auto",
      // Prevent position:absolute/fixed on body from coupling its
      // size to the iframe, which causes diverging expand() loops
      "position": "static"
    });
    this.setImageSize(availableWidth, availableHeight);
    this.expand();
  }
  columnize({ width, height, marginTop, marginRight, marginBottom, marginLeft, gap, columnWidth, columnCount, columnGap }) {
    const vertical = __privateGet(this, _vertical);
    __privateSet(this, _size, vertical ? height : width);
    __privateSet(this, _columnCount, columnCount || 1);
    const doc = this.document;
    const {
      columnGap: horizontalColumnGap,
      sidePaddingLeft,
      sidePaddingRight,
      columnWidth: columnWidthHint,
      availableWidth: horizontalAvailableWidth
    } = getHorizontalColumnMetrics({
      width,
      marginLeft,
      marginRight,
      gap,
      columnWidth,
      columnCount,
      columnGap: vertical ? null : columnGap
    });
    setStylesImportant(doc.documentElement, {
      "box-sizing": "border-box",
      "column-width": `${columnWidthHint}px`,
      "column-gap": vertical ? `${(marginTop + marginBottom) * 1.5}px` : `${horizontalColumnGap}px`,
      "column-fill": "auto",
      ...vertical ? { "width": `${width}px` } : { "height": `${height}px` },
      "overflow": "hidden",
      // force wrap long words
      "overflow-wrap": "break-word",
      // reset some potentially problematic props
      "position": "static",
      "border": "0",
      "margin": "0",
      "max-height": "none",
      "max-width": "none",
      "min-height": "none",
      "min-width": "none",
      // fix glyph clipping in WebKit
      "-webkit-line-box-contain": "block glyphs replaced"
    });
    const pageWidth = Math.trunc(width / __privateGet(this, _columnCount));
    const pageHeight = Math.trunc(height / __privateGet(this, _columnCount));
    const availableWidth = vertical ? Math.trunc(width - marginLeft / 2 - marginRight / 2 - gap) : horizontalAvailableWidth;
    const availableHeight = vertical ? Math.trunc(height / __privateGet(this, _columnCount) - marginTop * 1.5 - marginBottom * 1.5) : Math.trunc(height - marginTop - marginBottom);
    setStyles(doc.documentElement, {
      "padding": vertical ? `${marginTop * 1.5}px ${marginRight}px ${marginBottom * 1.5}px ${marginLeft}px` : `${marginTop}px ${sidePaddingRight}px ${marginBottom}px ${sidePaddingLeft}px`,
      "--page-margin-top": `${vertical ? marginTop * 1.5 : marginTop}px`,
      "--page-margin-right": `${vertical ? marginRight : sidePaddingRight}px`,
      "--page-margin-bottom": `${vertical ? marginBottom * 1.5 : marginBottom}px`,
      "--page-margin-left": `${vertical ? marginLeft : sidePaddingLeft}px`,
      "--full-width": `${vertical ? availableWidth : pageWidth}`,
      "--full-height": `${vertical ? pageHeight : availableHeight}`,
      "--available-width": `${availableWidth}`,
      "--available-height": `${availableHeight}`
    });
    setStylesImportant(doc.body, {
      "max-height": "none",
      "max-width": "none",
      "margin": "0",
      // Prevent position:absolute/fixed on body from coupling its
      // size to the iframe, which causes diverging expand() loops
      "position": "static"
    });
    this.setImageSize(availableWidth, availableHeight);
    __privateMethod(this, _View_instances, demoteUnfragmentableBoxes_fn).call(this, availableHeight);
    this.expand();
  }
  setImageSize(availableWidth, availableHeight) {
    const { width, height, marginTop, marginRight, marginBottom, marginLeft } = __privateGet(this, _layout);
    const vertical = __privateGet(this, _vertical);
    const doc = this.document;
    const pageFullscreen = doc.documentElement.hasAttribute("data-duokan-page-fullscreen");
    const applyFullscreen = pageFullscreen && __privateGet(this, _column);
    const els = doc.body.querySelectorAll("img, svg, video, canvas");
    for (const el of els) {
      el.style.removeProperty("max-width");
      el.style.removeProperty("max-height");
    }
    const measured = [];
    for (const el of els) {
      const {
        maxHeight,
        maxWidth,
        marginLeft: elMarginLeft,
        marginRight: elMarginRight,
        marginTop: elMarginTop,
        marginBottom: elMarginBottom
      } = doc.defaultView.getComputedStyle(el);
      measured.push({
        el,
        maxHeight,
        maxWidth,
        elMarginLeft,
        elMarginRight,
        elMarginTop,
        elMarginBottom
      });
    }
    const fill = (a, b) => {
      const margins = (parseFloat(a) || 0) + (parseFloat(b) || 0);
      return margins > 0 ? `calc(100% - ${margins}px)` : "100%";
    };
    for (const m of measured) {
      const { el, elMarginLeft, elMarginRight, elMarginTop, elMarginBottom } = m;
      let { maxHeight, maxWidth } = m;
      if (parseInt(maxWidth) > availableWidth) {
        maxWidth = `${availableWidth}px`;
      }
      if (parseInt(maxHeight) > availableHeight) {
        maxHeight = `${availableHeight}px`;
      }
      setStylesImportant(el, {
        "max-height": vertical ? maxHeight !== "none" && maxHeight !== "0px" ? maxHeight : fill(elMarginTop, elMarginBottom) : `${height - (applyFullscreen ? 0 : marginTop + marginBottom)}px`,
        "max-width": vertical ? `${width - (applyFullscreen ? 0 : marginLeft + marginRight)}px` : maxWidth !== "none" && maxWidth !== "0px" ? maxWidth : fill(elMarginLeft, elMarginRight),
        "object-fit": "contain",
        "page-break-inside": "avoid",
        "break-inside": "avoid",
        "box-sizing": "border-box"
      });
      if (applyFullscreen) {
        setStylesImportant(doc.documentElement, {
          position: "relative"
        });
        setStylesImportant(el, {
          position: "absolute",
          inset: "0",
          width: "100%",
          height: "100%",
          margin: "0",
          // fit the whole page while keeping the aspect ratio
          // ('contain' set for all images above); black bars fill
          // the leftover space like Duokan's native full-page render
          "background-color": "#000"
        });
        const slim = el.getAttribute("data-duokan-slim-src");
        if (slim) {
          if (!el.hasAttribute("data-duokan-src"))
            el.setAttribute("data-duokan-src", el.getAttribute("src"));
          const src = height / width > 1.7 ? slim : el.getAttribute("data-duokan-src");
          if (el.getAttribute("src") !== src) el.setAttribute("src", src);
        }
        let ancestor = el.parentElement;
        while (ancestor && ancestor !== doc.body) {
          setStylesImportant(ancestor, {
            width: "100%",
            height: "100%",
            margin: "0",
            padding: "0",
            // a positioned wrapper (e.g. from duokan-bleed handling)
            // would become the containing block for the pinned image,
            // whose height:100% then resolves against the wrapper's
            // zero height and the cover vanishes (#5263)
            position: "static"
          });
          ancestor = ancestor.parentElement;
        }
      } else if (pageFullscreen) {
        doc.documentElement.style.removeProperty("position");
        for (const prop of ["position", "inset", "width", "height", "margin", "background-color"]) {
          el.style.removeProperty(prop);
        }
        const original = el.getAttribute("data-duokan-src");
        if (original) el.setAttribute("src", original);
        let ancestor = el.parentElement;
        while (ancestor && ancestor !== doc.body) {
          for (const prop of ["width", "height", "margin", "padding", "position"]) {
            ancestor.style.removeProperty(prop);
          }
          ancestor = ancestor.parentElement;
        }
      }
    }
  }
  expand() {
    var _a;
    if (!((_a = this.document) == null ? void 0 : _a.documentElement) || this.document !== __privateGet(this, _loadedDoc)) return;
    const { documentElement } = this.document;
    if (__privateGet(this, _column)) {
      const side = __privateGet(this, _vertical) ? "height" : "width";
      const otherSide = __privateGet(this, _vertical) ? "width" : "height";
      const contentRect = __privateGet(this, _contentRange).getBoundingClientRect();
      const rootRect = documentElement.getBoundingClientRect();
      const contentStart = __privateGet(this, _vertical) ? 0 : __privateGet(this, _rtl) ? rootRect.right - contentRect.right : contentRect.left - rootRect.left;
      const contentSize = (contentStart + contentRect[side]) * __privateGet(this, _View_instances, zoom_get);
      const columnSize = __privateGet(this, _size) / __privateGet(this, _columnCount);
      const pageCount = Math.ceil(contentSize / columnSize);
      __privateSet(this, _contentPages, pageCount);
      const expandedSize = pageCount * columnSize;
      __privateGet(this, _element).style.padding = "0";
      __privateGet(this, _iframe).style[side] = `${expandedSize}px`;
      __privateGet(this, _element).style[side] = `${expandedSize}px`;
      __privateGet(this, _iframe).style[otherSide] = "100%";
      __privateGet(this, _element).style[otherSide] = "100%";
      documentElement.style[side] = `${columnSize}px`;
      if (__privateGet(this, _overlayer)) {
        __privateGet(this, _overlayer).element.style.margin = "0";
        __privateGet(this, _overlayer).element.style.left = "0";
        __privateGet(this, _overlayer).element.style.top = "0";
        __privateGet(this, _overlayer).element.style[side] = `${expandedSize}px`;
        __privateGet(this, _overlayer).redraw();
      }
    } else {
      const side = __privateGet(this, _vertical) ? "width" : "height";
      const otherSide = __privateGet(this, _vertical) ? "height" : "width";
      const contentSize = documentElement.getBoundingClientRect()[side];
      let expandedSize = contentSize;
      if (__privateGet(this, _bgImageSize)) {
        const crossSize = __privateGet(this, _element).getBoundingClientRect()[otherSide];
        if (crossSize > 0) {
          const { width: imgW, height: imgH } = __privateGet(this, _bgImageSize);
          const scaledSize = __privateGet(this, _vertical) ? imgW * crossSize / imgH : imgH * crossSize / imgW;
          expandedSize = Math.max(expandedSize, scaledSize);
        }
      }
      __privateGet(this, _element).style.padding = "0";
      __privateGet(this, _iframe).style[side] = `${expandedSize}px`;
      __privateGet(this, _element).style[side] = `${expandedSize}px`;
      __privateGet(this, _iframe).style[otherSide] = "100%";
      __privateGet(this, _element).style[otherSide] = "100%";
      if (__privateGet(this, _overlayer)) {
        __privateGet(this, _overlayer).element.style.margin = "0";
        __privateGet(this, _overlayer).element.style.left = "0";
        __privateGet(this, _overlayer).element.style.top = "0";
        __privateGet(this, _overlayer).element.style[side] = `${expandedSize}px`;
        __privateGet(this, _overlayer).redraw();
      }
    }
    this.onExpand();
  }
  set overlayer(overlayer) {
    __privateSet(this, _overlayer, overlayer);
    __privateGet(this, _element).append(overlayer.element);
  }
  get overlayer() {
    return __privateGet(this, _overlayer);
  }
  // Show a magnifier loupe inside the iframe document.
  // winX/winY are in main-window (screen) coordinates.
  showLoupe(winX, winY, { isVertical, color, gap, margin, radius, magnification }) {
    var _a, _b;
    const doc = this.document;
    if (!doc) return;
    const frameRect = __privateGet(this, _iframe).getBoundingClientRect();
    const vpX = winX - frameRect.left;
    const vpY = winY - frameRect.top;
    const scrollX = ((_a = doc.scrollingElement) == null ? void 0 : _a.scrollLeft) ?? 0;
    const scrollY = ((_b = doc.scrollingElement) == null ? void 0 : _b.scrollTop) ?? 0;
    const docX = vpX + scrollX;
    const docY = vpY + scrollY;
    const MAGNIFICATION = magnification;
    const MARGIN = margin;
    const shortSide = radius * 2;
    const longSide = Math.round(radius * 3.6);
    const loupeW = isVertical ? shortSide : longSide;
    const loupeH = isVertical ? longSide : shortSide;
    const halfW = loupeW / 2;
    const halfH = loupeH / 2;
    const borderRadius = shortSide / 2;
    const GAP = gap;
    let loupeLeft = isVertical ? vpX - loupeW - GAP : vpX - halfW;
    let loupeTop = isVertical ? vpY - halfH : vpY - loupeH - GAP;
    loupeLeft = Math.max(MARGIN, Math.min(loupeLeft, frameRect.width - loupeW - MARGIN));
    loupeTop = Math.max(MARGIN, Math.min(loupeTop, frameRect.height - loupeH - MARGIN));
    const offsetX = halfW - docX * MAGNIFICATION;
    const offsetY = halfH - docY * MAGNIFICATION;
    if (!__privateGet(this, _loupeEl) || !__privateGet(this, _loupeEl).isConnected) {
      __privateSet(this, _loupeEl, doc.createElement("div"));
      const bodyClone = doc.body.cloneNode(true);
      const htmlWrapper = doc.createElement("div");
      htmlWrapper.style.cssText = doc.documentElement.style.cssText;
      if (__privateGet(this, _vertical))
        htmlWrapper.style.height = `${doc.documentElement.scrollHeight}px`;
      else
        htmlWrapper.style.width = `${doc.documentElement.scrollWidth}px`;
      htmlWrapper.appendChild(bodyClone);
      __privateSet(this, _loupeScaler, doc.createElement("div"));
      __privateGet(this, _loupeScaler).appendChild(htmlWrapper);
      const cursorLen = Math.round(shortSide * 0.44);
      __privateSet(this, _loupeCursor, doc.createElement("div"));
      __privateGet(this, _loupeCursor).style.cssText = isVertical ? `position:absolute;left:calc(50% - ${cursorLen / 2}px);top:50%;margin-top:-1px;width:${cursorLen}px;height:2px;background:${color};pointer-events:none;z-index:1;box-sizing:border-box;` : `position:absolute;left:50%;top:calc(50% - ${cursorLen / 2}px);margin-left:-1px;width:2px;height:${cursorLen}px;background:${color};pointer-events:none;z-index:1;box-sizing:border-box;`;
      __privateGet(this, _loupeEl).appendChild(__privateGet(this, _loupeScaler));
      __privateGet(this, _loupeEl).appendChild(__privateGet(this, _loupeCursor));
      doc.documentElement.appendChild(__privateGet(this, _loupeEl));
      __privateGet(this, _loupeEl).style.cssText = `
                position: absolute;
                width: ${loupeW}px;
                height: ${loupeH}px;
                border-radius: ${borderRadius}px;
                overflow: hidden;
                border: 2.5px solid ${color};
                box-shadow: 0 6px 24px rgba(0,0,0,0.28);
                background-color: var(--theme-bg-color);
                z-index: 9999;
                pointer-events: none;
                user-select: none;
                box-sizing: border-box;
                contain: strict;
            `;
      __privateGet(this, _loupeScaler).style.cssText = `
                position: absolute;
                transform: scale(${MAGNIFICATION});
                transform-origin: 0 0;
                pointer-events: none;
            `;
    }
    __privateGet(this, _loupeEl).style.display = "";
    __privateGet(this, _loupeScaler).style.left = `${offsetX}px`;
    __privateGet(this, _loupeScaler).style.top = `${offsetY}px`;
    __privateGet(this, _loupeScaler).style.width = `${doc.documentElement.scrollWidth}px`;
    __privateGet(this, _loupeScaler).style.height = `${doc.documentElement.scrollHeight}px`;
    __privateGet(this, _loupeEl).style.left = `${loupeLeft + scrollX}px`;
    __privateGet(this, _loupeEl).style.top = `${loupeTop + scrollY}px`;
    if (__privateGet(this, _overlayer)) {
      const overlayerRect = __privateGet(this, _overlayer).element.getBoundingClientRect();
      const dx = frameRect.left - overlayerRect.left;
      const dy = frameRect.top - overlayerRect.top;
      const pad = 3;
      const cx = loupeLeft + halfW + dx;
      const cy = loupeTop + halfH + dy;
      __privateGet(this, _overlayer).setHole(cx, cy, loupeW + pad * 2, loupeH + pad * 2, borderRadius + pad);
    }
  }
  hideLoupe() {
    if (__privateGet(this, _loupeEl)) {
      __privateGet(this, _loupeEl).style.display = "none";
    }
    if (__privateGet(this, _overlayer))
      __privateGet(this, _overlayer).clearHole();
  }
  destroyLoupe() {
    if (__privateGet(this, _loupeEl)) {
      __privateGet(this, _loupeEl).remove();
      __privateSet(this, _loupeEl, null);
      __privateSet(this, _loupeScaler, null);
      __privateSet(this, _loupeCursor, null);
    }
    if (__privateGet(this, _overlayer))
      __privateGet(this, _overlayer).clearHole();
  }
  destroy() {
    var _a;
    if ((_a = this.document) == null ? void 0 : _a.body) __privateGet(this, _observer).unobserve(this.document.body);
    this.destroyLoupe();
  }
}
_observer = new WeakMap();
_element = new WeakMap();
_iframe = new WeakMap();
_contentRange = new WeakMap();
_overlayer = new WeakMap();
_vertical = new WeakMap();
_rtl = new WeakMap();
_docDirection = new WeakMap();
_loadedDoc = new WeakMap();
_directionStyle = new WeakMap();
_column = new WeakMap();
_size = new WeakMap();
_columnCount = new WeakMap();
_layout = new WeakMap();
_contentPages = new WeakMap();
_bgImageSize = new WeakMap();
_View_instances = new WeakSet();
// In an HTML document the principal writing mode — the one the root
// element's own box uses, and with it the order of its column boxes — is
// taken from `body`, not from the root (CSS Writing Modes §8.1). So the
// progression has to be written onto `body`, which is also where the text
// direction lives; a rule one level down gives the content back the
// direction the book authored, leaving elements that declare one alone.
setProgressionDirection_fn = function(direction) {
  var _a, _b, _c;
  const doc = this.document;
  if (!(doc == null ? void 0 : doc.head)) return;
  if (!direction || direction === __privateGet(this, _docDirection)) {
    doc.documentElement.style.removeProperty("direction");
    (_a = doc.body) == null ? void 0 : _a.style.removeProperty("direction");
    (_b = __privateGet(this, _directionStyle)) == null ? void 0 : _b.remove();
    __privateSet(this, _directionStyle, null);
    return;
  }
  setStylesImportant(doc.documentElement, { "direction": direction });
  if (doc.body) setStylesImportant(doc.body, { "direction": direction });
  if (((_c = __privateGet(this, _directionStyle)) == null ? void 0 : _c.ownerDocument) !== doc) {
    __privateSet(this, _directionStyle, doc.createElement("style"));
    doc.head.append(__privateGet(this, _directionStyle));
  }
  __privateGet(this, _directionStyle).textContent = `body > *:not([dir]) { direction: ${__privateGet(this, _docDirection)}; }`;
};
// Atomic inline-level boxes (inline-block / inline-flex / inline-grid /
// inline-table) cannot be fragmented across columns. When an EPUB declares
// such a display on a tall block container, the box overflows the page and
// every column past the first is clipped, so whole sections silently vanish
// (e.g. a chapter that jumps straight to its references). Detect the
// vertical overflow this causes in paginated mode and demote the offending
// boxes to their fragmentable block-level equivalents so the content
// paginates normally. The querySelectorAll scan only runs when the document
// actually overflows its column, which is the (rare) bug case.
demoteUnfragmentableBoxes_fn = function(availableHeight) {
  const doc = this.document;
  const root = doc == null ? void 0 : doc.documentElement;
  if (!root || root.scrollHeight <= root.clientHeight + 1) return;
  const view = doc.defaultView;
  const fragmentable = {
    "inline-block": "block",
    "inline-flex": "flex",
    "inline-grid": "grid",
    "inline-table": "table"
  };
  for (const el of doc.body.querySelectorAll("*")) {
    const replacement = fragmentable[view.getComputedStyle(el).display];
    if (replacement && el.getBoundingClientRect().height > availableHeight)
      setStylesImportant(el, { display: replacement });
  }
};
zoom_get = function() {
  if (/^((?!chrome|android).)*AppleWebKit/i.test(navigator.userAgent) && !window.chrome) {
    return window.getComputedStyle(this.document.body).zoom || 1;
  }
  return 1;
};
_loupeEl = new WeakMap();
_loupeScaler = new WeakMap();
_loupeCursor = new WeakMap();
const getHorizontalColumnMetrics = ({ width, marginLeft, marginRight, gap, columnWidth, columnCount, columnGap }) => {
  const multi = columnCount > 1;
  if (!multi || !Number.isFinite(columnGap) || columnGap < 0) {
    const sidePaddingLeft = multi ? marginLeft / 4 + gap / 4 : marginLeft / 2 + gap / 2;
    const sidePaddingRight = multi ? marginRight / 4 + gap / 4 : marginRight / 2 + gap / 2;
    return {
      columnGap: multi ? (marginLeft + marginRight) / 4 + gap / 2 : (marginLeft + marginRight) / 2 + gap,
      sidePaddingLeft,
      sidePaddingRight,
      columnWidth: Math.trunc(columnWidth),
      availableWidth: Math.trunc(width / columnCount - sidePaddingLeft - sidePaddingRight)
    };
  }
  const sidePadding = columnGap / 2;
  const column = Math.trunc(width / columnCount - columnGap);
  return { columnGap, sidePaddingLeft: sidePadding, sidePaddingRight: sidePadding, columnWidth: column, availableWidth: column };
};
const getColumnGapHostTracks = ({ columnGap, marginLeft, marginRight, hostGap }) => {
  const derivedLeft = marginLeft / 4 + hostGap / 4;
  const derivedRight = marginRight / 4 + hostGap / 4;
  return {
    outerMinLeft: Math.max(0, 2 * derivedLeft - columnGap / 2),
    outerMinRight: Math.max(0, 2 * derivedRight - columnGap / 2),
    capExtra: columnGap - derivedLeft - derivedRight
  };
};
class Paginator extends HTMLElement {
  constructor() {
    super();
    __privateAdd(this, _Paginator_instances);
    __privateAdd(this, _root, this.attachShadow({ mode: "open" }));
    __privateAdd(this, _observer2, new ResizeObserver(() => this.render()));
    __privateAdd(this, _top);
    __privateAdd(this, _background);
    __privateAdd(this, _container);
    __privateAdd(this, _header);
    __privateAdd(this, _footer);
    __privateAdd(this, _views, /* @__PURE__ */ new Map());
    // Map<sectionIndex, View>
    __privateAdd(this, _primaryIndex, -1);
    // Internally `index` is a render unit: a whole section, or one chunk of a
    // section too big to render whole. Spine indices only cross the public API.
    __privateAdd(this, _units, []);
    // Array<{ spine, chunk, count }>
    __privateAdd(this, _firstUnit, []);
    // spine index -> its first unit
    __privateAdd(this, _bookSections, []);
    __privateAdd(this, _chunkCache, /* @__PURE__ */ new Map());
    // spine index -> Promise<splitSection result>
    __privateAdd(this, _splits, /* @__PURE__ */ new Map());
    // spine index -> splitSection result, once resolved
    __privateAdd(this, _vertical2, false);
    __privateAdd(this, _rtl2, false);
    __privateAdd(this, _marginTop, 0);
    __privateAdd(this, _marginBottom, 0);
    __privateAdd(this, _anchor, 0);
    // anchor view to a fraction (0-1), Range, or Element
    __privateAdd(this, _justAnchored, false);
    __privateAdd(this, _locked, false);
    // while true, prevent any further navigation
    __privateAdd(this, _pagePreview, null);
    __privateAdd(this, _cancelPagePreview, null);
    __privateAdd(this, _styles);
    __privateAdd(this, _styleMap, /* @__PURE__ */ new WeakMap());
    __privateAdd(this, _mediaQuery, matchMedia("(prefers-color-scheme: dark)"));
    __privateAdd(this, _mediaQueryListener);
    __privateAdd(this, _scrollBounds);
    __privateAdd(this, _touchState);
    __privateAdd(this, _touchScrolled);
    __privateAdd(this, _lastVisibleRange);
    __privateAdd(this, _scrollLocked, false);
    __privateAdd(this, _subpixelOffset, 0);
    __privateAdd(this, _isAnimating, false);
    // Generation counter for slideTurnAnimation: a newer vertical page turn
    // bumps it so an in-flight two-phase slide stops touching the DOM.
    __privateAdd(this, _slideTurnId, 0);
    // Horizontal drag offset (px) applied to the views while a finger tracks
    // a page turn on a vertical book; consumed as the slide's start position
    // when the turn commits, or settled back to 0 when it doesn't.
    __privateAdd(this, _dragTranslateX, 0);
    // Active finger-tracked layered turn (readest#555): a paused view
    // transition whose animations are scrubbed by the drag.
    __privateAdd(this, _vtDrag, null);
    // A released layered turn still owns the global View Transition until its
    // commit/cancel cleanup and terminal lifecycle event complete.
    __privateAdd(this, _vtFinishing, null);
    __privateAdd(this, _vtProgrammatic, null);
    __privateAdd(this, _vtNamedHost, null);
    // Snapshot of the invariant inputs #replaceBackground needs (theme/texture
    // style, background+container geometry, per-view size+colour). Set once when
    // a scroll animation starts so the per-frame repaint reuses it instead of
    // forcing a fresh style+layout read every frame; null when not animating.
    __privateAdd(this, _bgAnimContext, null);
    __privateAdd(this, _filling, false);
    // true while #fillVisibleArea is running
    __privateAdd(this, _fillPromise, null);
    // tracks in-progress #fillVisibleArea for awaiting
    __privateAdd(this, _stabilizing, false);
    // true while #display is stabilizing layout
    __privateAdd(this, _rendered, false);
    // true after first #display completes
    __privateAdd(this, _lastLayout, null);
    // cached layout from the last #beforeRender call
    __privateAdd(this, _columnGap, null);
    // px; set by `column-gap`, overrides the centre gap of a spread
    // Cache of section index → vertical (boolean). Populated as views
    // are loaded so we can check direction *before* loading a section.
    __privateAdd(this, _directionCache, /* @__PURE__ */ new Map());
    __privateAdd(this, _transformTarget);
    __privateAdd(this, _transformCSS, ({ detail }) => {
      if (detail.type !== "text/css") return;
      detail.data = Promise.resolve(detail.data).then((data) => data.replace(/([{\s;])-epub-/gi, "$1").replace(/page-break-(after|before|inside)\s*:/gi, (_, x) => `-webkit-column-break-${x}:`).replace(/break-(after|before|inside)\s*:\s*(avoid-)?page/gi, (_, x, y) => `break-${x}: ${y ?? ""}column`));
    });
    __privateGet(this, _root).innerHTML = `<style>
        :host {
            display: block;
            container-type: size;
        }
        :host, #top {
            box-sizing: border-box;
            position: relative;
            overflow: hidden;
            width: 100%;
            height: 100%;
        }
        #top {
            --_gap: 7%;
            --_margin-top: 48px;
            --_margin-right: 48px;
            --_margin-bottom: 48px;
            --_margin-left: 48px;
            --_max-inline-size: 720px;
            --_max-block-size: 1440px;
            --_max-column-count: 2;
            --_max-column-count-portrait: var(--_max-column-count);
            --_max-column-count-spread: var(--_max-column-count);
            --_half-gap: calc(var(--_gap) / 2);
            --_half-margin-left: calc(var(--_margin-left) / 2);
            --_half-margin-right: calc(var(--_margin-right) / 2);
            --_max-width: calc(var(--_max-inline-size) * var(--_max-column-count-spread));
            --_max-height: var(--_max-block-size);
            --_column-count: 1;
            --_outer-min-left: calc((var(--_column-count) - 1) * (var(--_margin-left) / 4 + var(--_gap) / 4));
            --_outer-min-right: calc((var(--_column-count) - 1) * (var(--_margin-right) / 4 + var(--_gap) / 4));
            /* A column-gap override lowers the outer minimums and widens the
               cap so the text keeps its outer edge; see getColumnGapHostTracks. */
            --_gap-cap-extra: 0px;
            display: grid;
            grid-template-columns:
                minmax(var(--_outer-min-left), 1fr)
                var(--_margin-left)
                minmax(0, calc(var(--_max-width) - var(--_gap) + var(--_gap-cap-extra)))
                var(--_margin-right)
                minmax(var(--_outer-min-right), 1fr);
            grid-template-rows:
                minmax(var(--_margin-top), 1fr)
                minmax(0, var(--_max-height))
                minmax(var(--_margin-bottom), 1fr);
            &.vertical {
                --_max-column-count-spread: var(--_max-column-count-portrait);
                --_max-width: var(--_max-block-size);
                --_max-height: calc(var(--_max-inline-size) * var(--_max-column-count-spread));
            }
            @container (orientation: portrait) {
                & {
                    --_max-column-count-spread: var(--_max-column-count-portrait);
                }
                &.vertical {
                    --_max-column-count-spread: var(--_max-column-count);
                }
            }
        }
        #background {
            grid-column: 1 / -1;
            grid-row: 1 / -1;
            position: relative;
            overflow: hidden;
        }
        #container {
            grid-column: 2 / 5;
            grid-row: 1 / -1;
            overflow: hidden;
            display: flex;
            flex-direction: row;
            transition: opacity 50ms ease-in;
        }
        #container.vertical {
            flex-direction: column;
        }
        /* Apple WebKit (iOS/macOS) composites large, persistent layers without
           the ~1s Blink freeze Android Chromium hits at high DPR (the reason
           these promotion hints were dropped and rafAnimateScroll was added).
           When the host opts in, restore persistent compositor layers for the
           container and each view so the GPU cssAnimateScroll page-turn stays
           smooth on 120Hz ProMotion instead of promoting a layer on-demand
           every turn (readest#4768). Paginated mode only; scrolled mode does
           its own compositing below. */
        :host([gpu-composite]:not([flow="scrolled"])) #container,
        :host([gpu-composite]:not([flow="scrolled"])) #container > * {
            transform: translateZ(0);
        }
        :host([flow="scrolled"]) #container {
            grid-column: 2 / 5;
            grid-row: 1 / -1;
            overflow: auto;
            overflow-anchor: auto;
            flex-direction: column;
            /* Composite the scroll container so its scrollbar repaints on the
               compositor thread; the main-thread scrollbar fails to
               re-invalidate after content-size changes (adjacent-section
               preloading right after open), so on Windows' always-on
               scrollbars it vanishes shortly after the book opens
               (readest#4470). Scoped to scrolled mode to leave the paginated
               page-turn path un-composited. */
            transform: translateZ(0);
        }
        :host([flow="scrolled"]) #container.vertical {
            flex-direction: row;
        }
        #header {
            grid-column: 3 / 4;
            grid-row: 1;
        }
        #footer {
            grid-column: 3 / 4;
            grid-row: 3;
            align-self: end;
        }
        #header {
            display: grid;
            height: var(--_margin-top);
        }
        #footer {
            display: grid;
            height: var(--_margin-bottom);
        }
        #header > *, #footer > * {
            display: flex;
            align-items: center;
            min-width: 0;
        }
        #header > * > *, #footer > * > * {
            width: 100%;
            overflow: hidden;
            white-space: nowrap;
            text-overflow: ellipsis;
            text-align: center;
            font-size: .75em;
            opacity: .6;
        }
        </style>
        <div id="top">
            <div id="background" part="filter"></div>
            <div id="header"></div>
            <div id="container" part="container"></div>
            <div id="footer"></div>
        </div>
        `;
    __privateSet(this, _top, __privateGet(this, _root).getElementById("top"));
    __privateSet(this, _background, __privateGet(this, _root).getElementById("background"));
    __privateSet(this, _container, __privateGet(this, _root).getElementById("container"));
    __privateSet(this, _header, __privateGet(this, _root).getElementById("header"));
    __privateSet(this, _footer, __privateGet(this, _root).getElementById("footer"));
    __privateGet(this, _observer2).observe(__privateGet(this, _container));
    const scrolledScrollRelocate = () => {
      if (__privateGet(this, _stabilizing)) return;
      if (__privateGet(this, _justAnchored)) __privateSet(this, _justAnchored, false);
      else __privateMethod(this, _Paginator_instances, afterScroll_fn).call(this, "scroll");
    };
    let scrollBurstStart = null;
    const debouncedScroll = debounce(() => {
      if (__privateGet(this, _pagePreview)) return;
      scrollBurstStart = null;
      if (this.scrolled && !__privateGet(this, _isAnimating)) {
        scrolledScrollRelocate();
      } else if (!this.scrolled && !__privateGet(this, _stabilizing)) {
        __privateMethod(this, _Paginator_instances, afterScroll_fn).call(this, "container-scroll");
      }
    }, 250);
    __privateGet(this, _container).addEventListener("scroll", () => {
      var _a, _b;
      if (__privateGet(this, _pagePreview)) return;
      if (!__privateGet(this, _isAnimating)) this.dispatchEvent(new Event("scroll"));
      if (!this.scrolled && !__privateGet(this, _isAnimating)) __privateMethod(this, _Paginator_instances, replaceBackground_fn).call(this);
      if (!this.noPreload && !this.noContinuousScroll && !__privateGet(this, _filling) && !__privateGet(this, _stabilizing) && !__privateGet(this, _touchScrolled)) {
        const minPages = 5;
        const pagesAhead = this.size > 0 ? Math.floor((__privateGet(this, _Paginator_instances, renderedViewSize_get) - __privateGet(this, _Paginator_instances, renderedEnd_get)) / this.size) : 0;
        if (pagesAhead < minPages) {
          const sorted = __privateGet(this, _Paginator_instances, sortedViews_get);
          const lastIndex = (_a = sorted[sorted.length - 1]) == null ? void 0 : _a[0];
          if (lastIndex != null) {
            const nextIdx = __privateMethod(this, _Paginator_instances, adjacentIndex_fn).call(this, 1, lastIndex);
            if (nextIdx != null && !__privateGet(this, _views).has(nextIdx) && __privateMethod(this, _Paginator_instances, isSameDirection_fn).call(this, nextIdx)) {
              __privateSet(this, _filling, true);
              __privateMethod(this, _Paginator_instances, loadAdjacentSection_fn).call(this, nextIdx).finally(() => {
                __privateSet(this, _filling, false);
                this.dispatchEvent(new Event("stabilized"));
              });
            }
          }
        }
      }
      if (this.scrolled && !this.noPreload && !this.noContinuousScroll && !__privateGet(this, _filling) && !__privateGet(this, _stabilizing)) {
        const minPages = 5;
        const pagesBehind = this.size > 0 ? Math.floor(__privateGet(this, _Paginator_instances, renderedStart_get) / this.size) : 0;
        if (pagesBehind < minPages) {
          const sorted = __privateGet(this, _Paginator_instances, sortedViews_get);
          const firstIndex = (_b = sorted[0]) == null ? void 0 : _b[0];
          if (firstIndex != null) {
            const prevIdx = __privateMethod(this, _Paginator_instances, adjacentIndex_fn).call(this, -1, firstIndex);
            if (prevIdx != null && !__privateGet(this, _views).has(prevIdx) && __privateMethod(this, _Paginator_instances, isSameDirection_fn).call(this, prevIdx)) {
              __privateSet(this, _filling, true);
              __privateMethod(this, _Paginator_instances, loadAdjacentSection_fn).call(this, prevIdx).finally(() => {
                __privateSet(this, _filling, false);
                this.dispatchEvent(new Event("stabilized"));
              });
            }
          }
        }
      }
      if (this.scrolled && !__privateGet(this, _isAnimating) && !__privateGet(this, _touchScrolled)) {
        const now = Date.now();
        if (scrollBurstStart == null) scrollBurstStart = now;
        else if (now - scrollBurstStart >= SCROLL_RELOCATE_MAX_WAIT) {
          scrollBurstStart = now;
          scrolledScrollRelocate();
        }
      }
      debouncedScroll();
    });
    const opts = { passive: false };
    this.addEventListener("touchstart", __privateMethod(this, _Paginator_instances, onTouchStart_fn).bind(this), opts);
    this.addEventListener("touchmove", __privateMethod(this, _Paginator_instances, onTouchMove_fn).bind(this), opts);
    this.addEventListener("touchend", __privateMethod(this, _Paginator_instances, onTouchEnd_fn).bind(this));
    this.addEventListener("touchcancel", __privateMethod(this, _Paginator_instances, onTouchCancel_fn).bind(this));
    this.addEventListener("load", ({ detail: { doc } }) => {
      doc.addEventListener("touchstart", __privateMethod(this, _Paginator_instances, onTouchStart_fn).bind(this), opts);
      doc.addEventListener("touchmove", __privateMethod(this, _Paginator_instances, onTouchMove_fn).bind(this), opts);
      doc.addEventListener("touchend", __privateMethod(this, _Paginator_instances, onTouchEnd_fn).bind(this));
      doc.addEventListener("touchcancel", __privateMethod(this, _Paginator_instances, onTouchCancel_fn).bind(this));
    });
    this.addEventListener("relocate", ({ detail }) => {
      if (detail.reason === "selection") setSelectionTo(__privateGet(this, _anchor), 0);
      else if (detail.reason === "navigation") {
        if (__privateGet(this, _anchor) === 1) setSelectionTo(detail.range, 1);
        else if (typeof __privateGet(this, _anchor) === "number")
          setSelectionTo(detail.range, -1);
        else setSelectionTo(__privateGet(this, _anchor), -1);
      }
    });
    const checkPointerSelection = debounce((range, sel) => {
      if (!sel.rangeCount) return;
      const selRange = sel.getRangeAt(0);
      const backward = selectionIsBackward(sel);
      if (backward && selRange.compareBoundaryPoints(Range.START_TO_START, range) < 0)
        this.prev();
      else if (!backward && selRange.compareBoundaryPoints(Range.END_TO_END, range) > 0)
        this.next();
    }, 700);
    this.addEventListener("load", ({ detail: { doc } }) => {
      let isPointerSelecting = false;
      doc.addEventListener("pointerdown", () => isPointerSelecting = true);
      doc.addEventListener("pointerup", () => isPointerSelecting = false);
      let isKeyboardSelecting = false;
      doc.addEventListener("keydown", () => isKeyboardSelecting = true);
      doc.addEventListener("keyup", () => isKeyboardSelecting = false);
      doc.addEventListener("selectionchange", () => {
        if (this.scrolled) return;
        const range = __privateGet(this, _lastVisibleRange);
        if (!range) return;
        const sel = doc.getSelection();
        if (!sel.rangeCount) return;
        if (!isPointerSelecting && isPointerSelecting && sel.type === "Range")
          checkPointerSelection(range, sel);
        else if (isKeyboardSelecting) {
          const selRange = sel.getRangeAt(0).cloneRange();
          const backward = selectionIsBackward(sel);
          if (!backward) selRange.collapse();
          __privateMethod(this, _Paginator_instances, scrollToAnchor_fn).call(this, selRange);
        }
      });
      doc.addEventListener("focusin", (e) => {
        if (this.scrolled) return null;
        if (__privateGet(this, _container) && __privateGet(this, _container).contains(e.target)) {
          requestAnimationFrame(() => __privateMethod(this, _Paginator_instances, scrollToAnchor_fn).call(this, e.target));
        }
      });
    });
    __privateSet(this, _mediaQueryListener, () => {
      const view = __privateGet(this, _Paginator_instances, primaryView_get);
      if (!view) return;
      __privateMethod(this, _Paginator_instances, replaceBackground_fn).call(this);
    });
    __privateGet(this, _mediaQuery).addEventListener("change", __privateGet(this, _mediaQueryListener));
  }
  get primaryIndex() {
    return __privateMethod(this, _Paginator_instances, spineOf_fn).call(this, __privateGet(this, _primaryIndex));
  }
  setAttribute(name, value) {
    if (name === "flow" && this.scrolled && String(value) !== "scrolled" && __privateGet(this, _views).size > 0) {
      __privateMethod(this, _Paginator_instances, flushScrolledState_fn).call(this);
    }
    super.setAttribute(name, value);
  }
  attributeChangedCallback(name, _, value) {
    switch (name) {
      case "flow":
        this.render();
        break;
      case "column-gap": {
        const px = parseFloat(value);
        __privateSet(this, _columnGap, Number.isFinite(px) ? px : null);
        this.render();
        break;
      }
      case "gap":
      case "margin-top":
      case "margin-bottom":
      case "margin-left":
      case "margin-right":
      case "max-block-size":
      case "max-column-count":
        __privateGet(this, _top).style.setProperty("--_" + name, value);
        this.render();
        break;
      case "max-inline-size":
        __privateGet(this, _top).style.setProperty("--_" + name, value);
        this.render();
        break;
      case "no-continuous-scroll":
        if (this.noContinuousScroll) {
          for (const [i] of __privateGet(this, _views)) {
            if (i !== __privateGet(this, _primaryIndex)) __privateMethod(this, _Paginator_instances, destroyView_fn).call(this, i);
          }
        }
        break;
    }
  }
  open(book) {
    var _a, _b;
    this.bookDir = book.dir;
    __privateSet(this, _bookSections, book.sections);
    __privateSet(this, _units, []);
    __privateSet(this, _firstUnit, []);
    __privateGet(this, _chunkCache).clear();
    __privateGet(this, _splits).clear();
    const splits = __privateGet(this, _splits);
    this.sections = book.sections.flatMap((section, spine) => {
      __privateGet(this, _firstUnit)[spine] = __privateGet(this, _units).length;
      const count = section.size > CHUNK_THRESHOLD && section.loadContent ? Math.ceil(section.size / CHUNK_SIZE) : 1;
      if (count === 1) {
        __privateGet(this, _units).push({ spine, chunk: 0, count });
        return [section];
      }
      return Array.from({ length: count }, (_, chunk) => {
        __privateGet(this, _units).push({ spine, chunk, count });
        return {
          ...section,
          size: section.size / count,
          loadContent: async () => {
            var _a2;
            return (_a2 = await __privateMethod(this, _Paginator_instances, splitSection_fn).call(this, spine)) == null ? void 0 : _a2.chunk(chunk);
          },
          // chunks share the section's resources; keep them loaded
          unload: () => {
          },
          // a chunk with nothing to show is skipped, once known
          get linear() {
            var _a2;
            return ((_a2 = splits.get(spine)) == null ? void 0 : _a2.isEmpty(chunk)) ? "no" : section.linear;
          }
        };
      });
    });
    (_a = __privateGet(this, _transformTarget)) == null ? void 0 : _a.removeEventListener("data", __privateGet(this, _transformCSS));
    __privateSet(this, _transformTarget, book.transformTarget);
    (_b = __privateGet(this, _transformTarget)) == null ? void 0 : _b.addEventListener("data", __privateGet(this, _transformCSS));
  }
  render() {
    var _a;
    (_a = __privateGet(this, _cancelPagePreview)) == null ? void 0 : _a.call(this);
    if (__privateGet(this, _views).size === 0) return;
    const primaryView = __privateGet(this, _Paginator_instances, primaryView_get);
    if (!primaryView) return;
    const stabilizing = __privateGet(this, _stabilizing);
    __privateSet(this, _stabilizing, true);
    const layout = __privateMethod(this, _Paginator_instances, beforeRender_fn).call(this, {
      vertical: __privateGet(this, _vertical2),
      rtl: __privateGet(this, _rtl2)
    });
    for (const [, view] of __privateGet(this, _views)) {
      if (view.document) view.render(layout);
    }
    __privateMethod(this, _Paginator_instances, scrollToAnchor_fn).call(this, __privateGet(this, _anchor));
    __privateSet(this, _stabilizing, stabilizing);
    this.dispatchEvent(new Event("stabilized"));
  }
  get scrolled() {
    return this.getAttribute("flow") === "scrolled";
  }
  get noPreload() {
    return this.hasAttribute("no-preload");
  }
  get noBackground() {
    return this.hasAttribute("no-background");
  }
  get noContinuousScroll() {
    return this.scrolled && this.hasAttribute("no-continuous-scroll");
  }
  get scrollProp() {
    const { scrolled } = this;
    return __privateGet(this, _vertical2) ? scrolled ? "scrollLeft" : "scrollTop" : scrolled ? "scrollTop" : "scrollLeft";
  }
  get sideProp() {
    const { scrolled } = this;
    return __privateGet(this, _vertical2) ? scrolled ? "width" : "height" : scrolled ? "height" : "width";
  }
  get size() {
    return __privateGet(this, _container).getBoundingClientRect()[this.sideProp];
  }
  get viewSize() {
    const primaryView = __privateGet(this, _Paginator_instances, primaryView_get);
    if (!primaryView) return 0;
    return primaryView.element.getBoundingClientRect()[this.sideProp];
  }
  get start() {
    return __privateGet(this, _Paginator_instances, renderedStart_get) - __privateMethod(this, _Paginator_instances, getViewOffset_fn).call(this, __privateGet(this, _primaryIndex));
  }
  get end() {
    return __privateGet(this, _Paginator_instances, renderedEnd_get) - __privateMethod(this, _Paginator_instances, getViewOffset_fn).call(this, __privateGet(this, _primaryIndex));
  }
  get page() {
    return Math.floor((this.start + this.end) / 2 / this.size);
  }
  get pages() {
    const primaryView = __privateGet(this, _Paginator_instances, primaryView_get);
    if (!primaryView) return 0;
    const viewSize = primaryView.element.getBoundingClientRect()[this.sideProp];
    return Math.round(viewSize / this.size);
  }
  get containerPosition() {
    return __privateGet(this, _container)[this.scrollProp];
  }
  get isOverflowX() {
    return false;
  }
  get isOverflowY() {
    return false;
  }
  set containerPosition(newVal) {
    __privateGet(this, _container)[this.scrollProp] = newVal;
  }
  // Scroll offsets quantize to whole CSS pixels in both Blink and WebKit
  // (`scrollTop = 100.5` reads back 100 or 101), so a slow continuous scroll
  // such as Auto Scroll advances in visible one-pixel steps: at 5px/s that is
  // one jump every 200ms. The whole pixels stay in the scroll position, which
  // everything else reads; this carries only the sub-pixel remainder, as a
  // composited transform on the scrollport itself.
  //
  // The transform goes on #container rather than its children on purpose: a
  // transform on the children shifts their border boxes and shrinks the
  // container's scrollable overflow, which desynchronizes the scroll math
  // (readest#5663). Transforming the scrollport moves it as a whole and
  // leaves its scrollable overflow untouched.
  get subpixelOffset() {
    return __privateGet(this, _subpixelOffset);
  }
  set subpixelOffset(offset) {
    const value = Number.isFinite(offset) ? offset : 0;
    if (value === __privateGet(this, _subpixelOffset)) return;
    __privateSet(this, _subpixelOffset, value);
    const axis = this.scrollProp === "scrollLeft" ? "X" : "Y";
    __privateGet(this, _container).style.transform = value ? `translate${axis}(${-value}px) translateZ(0)` : "";
  }
  get scrollLocked() {
    return __privateGet(this, _scrollLocked);
  }
  set scrollLocked(value) {
    __privateSet(this, _scrollLocked, value);
  }
  scrollBy(dx, dy) {
    if (!__privateGet(this, _scrollBounds)) return;
    const delta = __privateGet(this, _vertical2) ? dy : dx;
    const [offset, a, b] = __privateGet(this, _scrollBounds);
    const rtl = __privateGet(this, _rtl2) && !__privateGet(this, _vertical2);
    const min = rtl ? offset - b : offset - a;
    const max = rtl ? offset + a : offset + b;
    this.containerPosition = Math.max(min, Math.min(
      max,
      this.containerPosition + delta
    ));
  }
  // vx, vy: velocity at the end of the swipe (pixels per ms)
  // dx, dy: total distance swiped
  // dt: total time of the swipe (ms)
  snap(vx, vy, dx, dy, dt) {
    var _a, _b;
    if (!__privateGet(this, _scrollBounds)) return;
    if (__privateGet(this, _vertical2) && Math.abs(dx) <= Math.abs(dy)) {
      __privateMethod(this, _Paginator_instances, settleDrag_fn).call(this);
      return;
    }
    const horizontal = Math.abs(vx) * 2 > Math.abs(vy);
    const pages = __privateGet(this, _Paginator_instances, renderedPages_get);
    let page;
    if (__privateGet(this, _vertical2) && !__privateGet(this, _Paginator_instances, layeredTurn_get) && this.hasAttribute("animated") && !this.hasAttribute("eink")) {
      const width = __privateGet(this, _container).getBoundingClientRect().width;
      const forwardSign = __privateGet(this, _rtl2) ? 1 : -1;
      const dragged = __privateGet(this, _dragTranslateX);
      const flick = Math.abs(vx) > 0.3 ? -Math.sign(vx) : 0;
      let turn;
      if (Math.abs(dragged) > width / 2) {
        turn = flick === -Math.sign(dragged) ? 0 : Math.sign(dragged);
      } else if (flick && (!dragged || flick === Math.sign(dragged))) {
        turn = flick;
      } else {
        turn = 0;
      }
      page = __privateGet(this, _Paginator_instances, renderedPage_get) + turn * forwardSign;
    } else {
      const velocity = vx;
      const avgVelocity = dx / dt;
      const snapping = this.hasAttribute("animated") && !this.hasAttribute("eink") && !__privateGet(this, _vertical2) && !__privateGet(this, _Paginator_instances, layeredTurn_get);
      const aligned = snapping ? horizontal : Math.abs(dx) > Math.abs(dy);
      const sign = __privateGet(this, _rtl2) ? -1 : 1;
      const [offset, a, b] = __privateGet(this, _scrollBounds);
      const size = this.size;
      const start = __privateGet(this, _Paginator_instances, renderedStart_get);
      const end = __privateGet(this, _Paginator_instances, renderedEnd_get);
      const min = Math.abs(offset) - a;
      const max = Math.abs(offset) + b;
      const v = snapping ? velocity : avgVelocity;
      const d = v * sign * size * (aligned ? 1 : 0);
      const velocityBased = isNaN(d) ? 0 : snapping ? d * 2 : d * 10;
      const distanceBased = snapping && Math.abs(dx) > Math.abs(dy) && Math.abs(dx) > size * DRAG_TURN_DISTANCE_RATIO ? Math.sign(dx) * sign * size : 0;
      const snapOffset = Math.abs(velocityBased) > Math.abs(distanceBased) ? velocityBased : distanceBased;
      page = Math.floor(Math.max(min, Math.min(max, (start + end) / 2 + snapOffset)) / size);
    }
    const dir = page < 0 ? -1 : page >= pages ? 1 : null;
    const doGoTo = () => {
      var _a2, _b2;
      if (!dir) return;
      const sorted = __privateGet(this, _Paginator_instances, sortedViews_get);
      const edgeIndex = dir < 0 ? ((_a2 = sorted[0]) == null ? void 0 : _a2[0]) ?? __privateGet(this, _primaryIndex) : ((_b2 = sorted[sorted.length - 1]) == null ? void 0 : _b2[0]) ?? __privateGet(this, _primaryIndex);
      return __privateMethod(this, _Paginator_instances, adjacentUnit_fn).call(this, dir, edgeIndex).then((index) => __privateMethod(this, _Paginator_instances, goTo_fn).call(this, {
        index,
        anchor: dir < 0 ? () => 1 : () => 0
      }));
    };
    if (dir) {
      if (__privateGet(this, _vertical2)) {
        const sorted = __privateGet(this, _Paginator_instances, sortedViews_get);
        const edgeIndex = dir < 0 ? ((_a = sorted[0]) == null ? void 0 : _a[0]) ?? __privateGet(this, _primaryIndex) : ((_b = sorted[sorted.length - 1]) == null ? void 0 : _b[0]) ?? __privateGet(this, _primaryIndex);
        if (__privateMethod(this, _Paginator_instances, adjacentIndex_fn).call(this, dir, edgeIndex) == null) return __privateMethod(this, _Paginator_instances, settleDrag_fn).call(this);
        __privateMethod(this, _Paginator_instances, settleDrag_fn).call(this, true);
      }
      return doGoTo();
    }
    __privateMethod(this, _Paginator_instances, scrollToPage_fn).call(this, page, "snap");
  }
  async scrollToAnchor(anchor, select, smooth) {
    return __privateMethod(this, _Paginator_instances, scrollToAnchor_fn).call(this, anchor, select ? "selection" : "navigation", smooth);
  }
  async goTo(target) {
    if (__privateGet(this, _pagePreview)) await __privateGet(this, _pagePreview);
    if (__privateGet(this, _locked)) return;
    const resolved = await __privateMethod(this, _Paginator_instances, toUnitTarget_fn).call(this, await target);
    if (__privateMethod(this, _Paginator_instances, canGoToIndex_fn).call(this, resolved.index)) return __privateMethod(this, _Paginator_instances, goTo_fn).call(this, resolved);
  }
  get atStart() {
    var _a;
    const sorted = __privateGet(this, _Paginator_instances, sortedViews_get);
    const firstIndex = ((_a = sorted[0]) == null ? void 0 : _a[0]) ?? __privateGet(this, _primaryIndex);
    if (this.scrolled) return __privateMethod(this, _Paginator_instances, adjacentIndex_fn).call(this, -1, firstIndex) == null && __privateGet(this, _Paginator_instances, renderedStart_get) <= 0;
    return __privateMethod(this, _Paginator_instances, adjacentIndex_fn).call(this, -1, firstIndex) == null && __privateGet(this, _Paginator_instances, renderedPage_get) <= 0;
  }
  get atEnd() {
    var _a;
    const sorted = __privateGet(this, _Paginator_instances, sortedViews_get);
    const lastIndex = ((_a = sorted[sorted.length - 1]) == null ? void 0 : _a[0]) ?? __privateGet(this, _primaryIndex);
    if (this.scrolled) return __privateMethod(this, _Paginator_instances, adjacentIndex_fn).call(this, 1, lastIndex) == null && __privateGet(this, _Paginator_instances, renderedViewSize_get) - __privateGet(this, _Paginator_instances, renderedEnd_get) <= 2;
    return __privateMethod(this, _Paginator_instances, adjacentIndex_fn).call(this, 1, lastIndex) == null && __privateGet(this, _Paginator_instances, renderedPage_get) >= __privateGet(this, _Paginator_instances, renderedPages_get) - 1;
  }
  async prev(distance) {
    return await __privateMethod(this, _Paginator_instances, turnPage_fn).call(this, -1, distance);
  }
  // Stable within one layout, including when loaded views are prepended.
  // A preview never calls #afterScroll: reading progress/history stay put.
  getPageTurnKey(delta = 0) {
    if (this.scrolled || __privateGet(this, _vertical2) || !this.size) return null;
    const offset = (__privateGet(this, _Paginator_instances, renderedPage_get) + delta) * this.size;
    if (offset < 0 || offset >= __privateGet(this, _Paginator_instances, renderedViewSize_get) - 1) return null;
    for (const [index, view] of __privateGet(this, _Paginator_instances, sortedViews_get)) {
      const start = __privateMethod(this, _Paginator_instances, getViewOffset_fn).call(this, index);
      const end = start + view.element.getBoundingClientRect()[this.sideProp];
      if (offset >= start - 1 && offset < end - 1)
        return `${index}:${Math.round((offset - start) / this.size)}`;
    }
    return null;
  }
  async previewPage(forward, capture, signal) {
    if ((signal == null ? void 0 : signal.aborted) || __privateGet(this, _pagePreview) || __privateGet(this, _locked) || __privateGet(this, _stabilizing) || __privateGet(this, _touchScrolled)) return null;
    const delta = forward ? 1 : -1;
    const key = this.getPageTurnKey(delta);
    if (!key) return null;
    let release;
    __privateSet(this, _pagePreview, new Promise((resolve) => {
      release = resolve;
    }));
    __privateSet(this, _locked, true);
    const position = this.containerPosition;
    let restored = false;
    let cancelled = false;
    const aborted = Symbol("preview-aborted");
    let stopCapture;
    const interrupted = new Promise((resolve) => {
      stopCapture = resolve;
    });
    const restore = () => {
      if (restored) return;
      restored = true;
      this.containerPosition = position;
      __privateMethod(this, _Paginator_instances, replaceBackground_fn).call(this);
    };
    const cancel = () => {
      cancelled = true;
      restore();
      stopCapture(aborted);
    };
    __privateSet(this, _cancelPagePreview, cancel);
    signal == null ? void 0 : signal.addEventListener("abort", cancel, { once: true });
    const paint = () => new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)));
    try {
      const page = __privateGet(this, _Paginator_instances, renderedPage_get) + delta;
      this.containerPosition = this.size * (__privateGet(this, _rtl2) ? -page : page);
      __privateMethod(this, _Paginator_instances, replaceBackground_fn).call(this);
      await paint();
      if ((signal == null ? void 0 : signal.aborted) || cancelled) return null;
      const value = await Promise.race([capture(), interrupted]);
      return value === aborted ? null : { key, value };
    } finally {
      signal == null ? void 0 : signal.removeEventListener("abort", cancel);
      restore();
      await paint();
      __privateSet(this, _pagePreview, null);
      __privateSet(this, _cancelPagePreview, null);
      __privateSet(this, _locked, false);
      release();
    }
  }
  async next(distance) {
    return await __privateMethod(this, _Paginator_instances, turnPage_fn).call(this, 1, distance);
  }
  async pan(dx, dy) {
    if (__privateGet(this, _locked)) return;
    __privateSet(this, _locked, true);
    this.scrollBy(dx, dy);
    __privateSet(this, _locked, false);
  }
  async prevSection() {
    return __privateMethod(this, _Paginator_instances, goToUnit_fn).call(this, await __privateMethod(this, _Paginator_instances, adjacentUnit_fn).call(this, -1));
  }
  async nextSection() {
    return __privateMethod(this, _Paginator_instances, goToUnit_fn).call(this, await __privateMethod(this, _Paginator_instances, adjacentUnit_fn).call(this, 1));
  }
  firstSection() {
    return __privateMethod(this, _Paginator_instances, goToUnit_fn).call(this, this.sections.findIndex((section) => section.linear !== "no"));
  }
  lastSection() {
    return __privateMethod(this, _Paginator_instances, goToUnit_fn).call(this, this.sections.findLastIndex((section) => section.linear !== "no"));
  }
  getContents() {
    const contents = [];
    for (const [index, view] of __privateGet(this, _Paginator_instances, sortedViews_get)) {
      if (!view.document) continue;
      const content = {
        index: __privateMethod(this, _Paginator_instances, spineOf_fn).call(this, index),
        overlayer: view.overlayer,
        doc: view.document,
        contentPages: view.contentPages
      };
      if (index === __privateGet(this, _primaryIndex)) {
        const first = contents.findIndex((c) => c.index === content.index);
        if (first >= 0) {
          contents.splice(first, 0, content);
          continue;
        }
      }
      contents.push(content);
    }
    return contents;
  }
  setStyles(styles) {
    __privateSet(this, _styles, styles);
    for (const [, view] of __privateGet(this, _views)) {
      if (!__privateGet(this, _styleMap).has(view.document)) continue;
      __privateMethod(this, _Paginator_instances, applyStyles_fn).call(this, view.document);
      fontsReady(view.document).then(() => view.expand());
    }
    const primaryView = __privateGet(this, _Paginator_instances, primaryView_get);
    if (primaryView) {
      requestAnimationFrame(() => __privateMethod(this, _Paginator_instances, replaceBackground_fn).call(this));
    }
  }
  focusView() {
    var _a, _b, _c;
    (_c = (_b = (_a = __privateGet(this, _Paginator_instances, primaryView_get)) == null ? void 0 : _a.document) == null ? void 0 : _b.defaultView) == null ? void 0 : _c.focus();
  }
  showLoupe(winX, winY, { isVertical, color, gap, margin, radius, magnification }) {
    var _a;
    (_a = __privateGet(this, _Paginator_instances, primaryView_get)) == null ? void 0 : _a.showLoupe(winX, winY, { isVertical, color, gap, margin, radius, magnification });
  }
  hideLoupe() {
    var _a;
    (_a = __privateGet(this, _Paginator_instances, primaryView_get)) == null ? void 0 : _a.hideLoupe();
  }
  destroyLoupe() {
    var _a;
    (_a = __privateGet(this, _Paginator_instances, primaryView_get)) == null ? void 0 : _a.destroyLoupe();
  }
  destroy() {
    var _a, _b, _c, _d, _e;
    const transition = ((_a = __privateGet(this, _vtDrag) ?? __privateGet(this, _vtFinishing)) == null ? void 0 : _a.transition) ?? ((_b = __privateGet(this, _vtProgrammatic)) == null ? void 0 : _b.transition);
    __privateSet(this, _vtDrag, null);
    __privateSet(this, _vtFinishing, null);
    __privateSet(this, _vtProgrammatic, null);
    __privateWrapper(this, _slideTurnId)._++;
    if (transition || __privateGet(this, _vtNamedHost)) {
      (_c = transition == null ? void 0 : transition.ready) == null ? void 0 : _c.catch(() => {
      });
      (_d = transition == null ? void 0 : transition.updateCallbackDone) == null ? void 0 : _d.catch(() => {
      });
      try {
        transition == null ? void 0 : transition.skipTransition();
      } catch {
      }
      __privateMethod(this, _Paginator_instances, vtCleanup_fn).call(this);
      __privateSet(this, _isAnimating, false);
    }
    __privateGet(this, _observer2).unobserve(this);
    __privateMethod(this, _Paginator_instances, destroyAllViews_fn).call(this);
    __privateGet(this, _mediaQuery).removeEventListener("change", __privateGet(this, _mediaQueryListener));
    (_e = __privateGet(this, _transformTarget)) == null ? void 0 : _e.removeEventListener("data", __privateGet(this, _transformCSS));
    __privateSet(this, _transformTarget, null);
  }
}
_root = new WeakMap();
_observer2 = new WeakMap();
_top = new WeakMap();
_background = new WeakMap();
_container = new WeakMap();
_header = new WeakMap();
_footer = new WeakMap();
_views = new WeakMap();
_primaryIndex = new WeakMap();
_units = new WeakMap();
_firstUnit = new WeakMap();
_bookSections = new WeakMap();
_chunkCache = new WeakMap();
_splits = new WeakMap();
_vertical2 = new WeakMap();
_rtl2 = new WeakMap();
_marginTop = new WeakMap();
_marginBottom = new WeakMap();
_anchor = new WeakMap();
_justAnchored = new WeakMap();
_locked = new WeakMap();
_pagePreview = new WeakMap();
_cancelPagePreview = new WeakMap();
_styles = new WeakMap();
_styleMap = new WeakMap();
_mediaQuery = new WeakMap();
_mediaQueryListener = new WeakMap();
_scrollBounds = new WeakMap();
_touchState = new WeakMap();
_touchScrolled = new WeakMap();
_lastVisibleRange = new WeakMap();
_scrollLocked = new WeakMap();
_subpixelOffset = new WeakMap();
_isAnimating = new WeakMap();
_slideTurnId = new WeakMap();
_dragTranslateX = new WeakMap();
_vtDrag = new WeakMap();
_vtFinishing = new WeakMap();
_vtProgrammatic = new WeakMap();
_vtNamedHost = new WeakMap();
_bgAnimContext = new WeakMap();
_filling = new WeakMap();
_fillPromise = new WeakMap();
_stabilizing = new WeakMap();
_rendered = new WeakMap();
_lastLayout = new WeakMap();
_columnGap = new WeakMap();
_directionCache = new WeakMap();
_Paginator_instances = new WeakSet();
primaryView_get = function() {
  return __privateGet(this, _views).get(__privateGet(this, _primaryIndex));
};
sortedViews_get = function() {
  return [...__privateGet(this, _views).entries()].sort(([a], [b]) => a - b);
};
flushScrolledState_fn = function() {
  if (__privateGet(this, _views).size > 1) __privateMethod(this, _Paginator_instances, detectPrimaryView_fn).call(this);
  const result = __privateMethod(this, _Paginator_instances, getVisibleRange_fn).call(this);
  if ((result == null ? void 0 : result.range) && !result.range.collapsed) __privateSet(this, _anchor, result.range);
};
_transformTarget = new WeakMap();
_transformCSS = new WeakMap();
splitSection_fn = function(spine) {
  let split = __privateGet(this, _chunkCache).get(spine);
  if (!split) {
    const { count } = __privateGet(this, _units)[__privateGet(this, _firstUnit)[spine]];
    split = Promise.resolve(__privateGet(this, _bookSections)[spine].loadContent()).then((html) => html ? splitSection(html, count) : null).catch((e) => (console.warn(e), null)).then((result) => (__privateGet(this, _splits).set(spine, result), result));
    __privateGet(this, _chunkCache).set(spine, split);
  }
  return split;
};
spineOf_fn = function(index) {
  var _a;
  return ((_a = __privateGet(this, _units)[index]) == null ? void 0 : _a.spine) ?? index;
};
toUnitTarget_fn = async function(target) {
  var _a;
  const { index, anchor } = target;
  const unit = __privateGet(this, _firstUnit)[index];
  if (unit == null) return { ...target, index: -1 };
  const { count } = __privateGet(this, _units)[unit];
  if (count === 1) return { ...target, index: unit };
  if (typeof anchor === "number" || typeof anchor === "function") {
    const split = await __privateMethod(this, _Paginator_instances, splitSection_fn).call(this, index);
    if (!split) return { ...target, index: unit };
    const { chunk, anchor: fraction } = split.locate(anchor);
    return { ...target, index: unit + chunk, anchor: fraction ?? anchor };
  }
  const doc = (_a = (anchor == null ? void 0 : anchor.startContainer) ?? anchor) == null ? void 0 : _a.ownerDocument;
  for (const [i, view] of __privateGet(this, _views))
    if (doc && view.document === doc) return { ...target, index: i };
  return { ...target, index: unit };
};
createView_fn = function(index) {
  const existing = __privateGet(this, _views).get(index);
  if (existing) {
    existing.destroy();
    __privateGet(this, _container).removeChild(existing.element);
    __privateGet(this, _views).delete(index);
  }
  const view = new View({
    container: this,
    onExpand: () => {
      if (__privateGet(this, _filling) || __privateGet(this, _stabilizing) || this.scrolled) return;
      if (__privateGet(this, _primaryIndex) === index)
        __privateMethod(this, _Paginator_instances, scrollToAnchor_fn).call(this, __privateGet(this, _anchor));
    }
  });
  __privateGet(this, _views).set(index, view);
  const sorted = __privateGet(this, _Paginator_instances, sortedViews_get);
  const myPos = sorted.findIndex(([i]) => i === index);
  const nextEntry = sorted[myPos + 1];
  if (nextEntry) __privateGet(this, _container).insertBefore(view.element, nextEntry[1].element);
  else __privateGet(this, _container).append(view.element);
  __privateMethod(this, _Paginator_instances, syncA11y_fn).call(this);
  return view;
};
// Hide off-screen pre-loaded views from the accessibility tree so
// screen-reader swipe-next does not wander into them (which would land
// several pages into the next section instead of its first paragraph).
//
// Only `aria-hidden` is used — `inert` would also block pointer events
// and text selection, which breaks visible non-primary views such as
// the right column of a dual-page spread when each column belongs to
// a different section (readest/readest#4243, readest/readest#4259).
//
// Visible non-primary views stay exposed to assistive tech because a
// sighted user can read them on the same spread.
syncA11y_fn = function() {
  const containerRect = __privateGet(this, _container).getBoundingClientRect();
  for (const [index, view] of __privateGet(this, _views)) {
    const isPrimary = index === __privateGet(this, _primaryIndex);
    const isVisible = isPrimary || isViewVisibleInContainer(
      view.element.getBoundingClientRect(),
      containerRect
    );
    if (isVisible) view.element.removeAttribute("aria-hidden");
    else view.element.setAttribute("aria-hidden", "true");
  }
};
destroyView_fn = function(index) {
  var _a, _b;
  const view = __privateGet(this, _views).get(index);
  if (!view) return;
  view.destroy();
  __privateGet(this, _container).removeChild(view.element);
  __privateGet(this, _views).delete(index);
  (_b = (_a = this.sections[index]) == null ? void 0 : _a.unload) == null ? void 0 : _b.call(_a);
};
destroyAllViews_fn = function() {
  for (const [index] of __privateGet(this, _views)) __privateMethod(this, _Paginator_instances, destroyView_fn).call(this, index);
};
clearViewsExcept_fn = function(keepIndices) {
  for (const [index] of __privateGet(this, _views)) {
    if (!keepIndices.has(index)) __privateMethod(this, _Paginator_instances, destroyView_fn).call(this, index);
  }
};
// Check if a section has the same writing direction as current primary.
// Returns true if same or unknown (not yet cached).
isSameDirection_fn = function(index) {
  if (!__privateGet(this, _directionCache).has(index)) return true;
  return __privateGet(this, _directionCache).get(index) === __privateGet(this, _vertical2);
};
// Read the theme/texture style off the primary section's <html> and return a
// resolver that maps a view's raw background onto the active theme. This is a
// forced style read (getComputedStyle), so callers in the animation hot path
// do it once via #computePaginatedBgContext rather than every frame.
readBackgroundStyle_fn = function(doc) {
  const htmlStyle = doc.defaultView.getComputedStyle(doc.documentElement);
  const themeBgColor = htmlStyle.getPropertyValue("--theme-bg-color");
  const overrideColor = htmlStyle.getPropertyValue("--override-color") === "true";
  const bgTextureId = htmlStyle.getPropertyValue("--bg-texture-id");
  const isDarkMode = htmlStyle.getPropertyValue("color-scheme") === "dark";
  const fallbackBg = themeBgColor || "";
  const hasTexture = !!bgTextureId && bgTextureId !== "none";
  const resolveBackground = (background) => {
    if (!background) return fallbackBg;
    if (themeBgColor) {
      const parsed = background.split(/\s(?=(?:url|rgb|hsl|#[0-9a-fA-F]{3,6}))/);
      if ((isDarkMode || overrideColor) && (bgTextureId === "none" || !bgTextureId)) {
        parsed[0] = themeBgColor;
      }
      return parsed.join(" ");
    }
    return background;
  };
  return { fallbackBg, hasTexture, resolveBackground };
};
// Snapshot every input #paintPaginatedBackground needs that stays constant for
// the duration of a scroll animation: the theme/texture style, the
// background+container geometry, and each rendered view's size and resolved
// background. Returns null when there is nothing to paint (no primary doc,
// backgrounds disabled, or scrolled mode). Built once per animation so the
// per-frame repaint never re-runs getComputedStyle or one
// getBoundingClientRect per view — those forced reads, multiplied by the views
// preloaded at a chapter boundary, are what dropped frames mid-swipe
// (readest#4785).
computePaginatedBgContext_fn = function() {
  var _a;
  const doc = (_a = __privateGet(this, _Paginator_instances, primaryView_get)) == null ? void 0 : _a.document;
  if (!(doc == null ? void 0 : doc.documentElement)) return null;
  if (this.noBackground) return null;
  if (this.scrolled) return null;
  const { fallbackBg, hasTexture, resolveBackground } = __privateMethod(this, _Paginator_instances, readBackgroundStyle_fn).call(this, doc);
  const bgRect = __privateGet(this, _background).getBoundingClientRect();
  const containerRect = __privateGet(this, _container).getBoundingClientRect();
  const startEdge = __privateGet(this, _vertical2) ? "top" : "left";
  const bgSize = bgRect[this.sideProp];
  const inset = containerRect[startEdge] - bgRect[startEdge];
  const containerSize = containerRect[this.sideProp];
  const views = __privateGet(this, _Paginator_instances, sortedViews_get).map(([, view]) => ({
    size: view.element.getBoundingClientRect()[this.sideProp],
    bg: textureAwareBackground(resolveBackground(view.docBackground), hasTexture)
  }));
  return { fallbackBg, hasTexture, bgSize, inset, containerSize, views };
};
// Paint one full-bleed background segment per rendered view from a previously
// computed context, positioned so each tracks its content on screen at the
// given scroll position. Rebuilding on every scroll keeps the backgrounds
// glued to the content during a swipe drag — so when two sections with
// different backgrounds are both visible, each half shows its own colour
// instead of one flat colour flashing across the viewport. Only writes layout
// (no reads), so it is safe to run every animation frame.
paintPaginatedBackground_fn = function(ctx, atPosition) {
  __privateGet(this, _background).style.background = "";
  for (const [, view] of __privateGet(this, _Paginator_instances, sortedViews_get)) {
    view.element.style.background = "";
  }
  const scrollPos = Math.abs(atPosition ?? __privateGet(this, _Paginator_instances, renderedStart_get));
  const segments = computeBackgroundSegments(
    ctx.views,
    scrollPos,
    ctx.bgSize,
    ctx.inset,
    ctx.containerSize
  );
  __privateGet(this, _background).innerHTML = "";
  __privateGet(this, _background).style.display = "";
  __privateGet(this, _background).style.background = ctx.hasTexture ? "" : ctx.fallbackBg;
  const posProp = __privateGet(this, _vertical2) ? "top" : "left";
  const sizeProp = __privateGet(this, _vertical2) ? "height" : "width";
  const crossPosProp = __privateGet(this, _vertical2) ? "left" : "top";
  const crossSizeProp = __privateGet(this, _vertical2) ? "width" : "height";
  for (const { start, size, bg } of segments) {
    const seg = document.createElement("div");
    seg.style.position = "absolute";
    seg.style[posProp] = `${start}px`;
    seg.style[sizeProp] = `${size}px`;
    seg.style[crossPosProp] = "0";
    seg.style[crossSizeProp] = "100%";
    seg.style.background = bg;
    seg.style.backgroundAttachment = "initial";
    __privateGet(this, _background).appendChild(seg);
  }
};
// Update the #background grid so each column shows the correct section's
// background. Pass atPosition to pre-compute for a destination scroll
// position (e.g. before an animation starts). During a scroll animation the
// invariant context is snapshotted in #bgAnimContext and reused here so the
// per-frame repaint stays read-free.
replaceBackground_fn = function(atPosition) {
  var _a;
  const doc = (_a = __privateGet(this, _Paginator_instances, primaryView_get)) == null ? void 0 : _a.document;
  if (!(doc == null ? void 0 : doc.documentElement)) return;
  if (this.noBackground) return;
  if (this.scrolled) {
    const { fallbackBg, hasTexture, resolveBackground } = __privateMethod(this, _Paginator_instances, readBackgroundStyle_fn).call(this, doc);
    __privateGet(this, _background).style.background = "";
    __privateGet(this, _background).innerHTML = "";
    __privateGet(this, _background).style.display = "";
    __privateGet(this, _background).style.background = hasTexture ? "" : fallbackBg;
    for (const [, view] of __privateGet(this, _Paginator_instances, sortedViews_get)) {
      const resolved = resolveBackground(view.docBackground);
      view.element.style.background = textureAwareBackground(resolved, hasTexture);
    }
    return;
  }
  const ctx = __privateGet(this, _bgAnimContext) ?? __privateMethod(this, _Paginator_instances, computePaginatedBgContext_fn).call(this);
  if (!ctx) return;
  __privateMethod(this, _Paginator_instances, paintPaginatedBackground_fn).call(this, ctx, atPosition);
};
beforeRender_fn = function({ vertical, rtl: documentRTL }) {
  if (__privateGet(this, _rendered) && vertical !== __privateGet(this, _vertical2)) {
    for (const [i] of __privateGet(this, _views)) {
      if (i !== __privateGet(this, _primaryIndex)) __privateMethod(this, _Paginator_instances, destroyView_fn).call(this, i);
    }
  }
  __privateSet(this, _vertical2, vertical);
  __privateSet(this, _rtl2, getPageProgressionRTL(this.bookDir, documentRTL));
  __privateGet(this, _top).classList.toggle("vertical", vertical);
  __privateGet(this, _container).classList.toggle("vertical", vertical);
  const style = getComputedStyle(__privateGet(this, _top));
  const maxInlineSize = parseFloat(style.getPropertyValue("--_max-inline-size"));
  const maxColumnCount = parseInt(style.getPropertyValue("--_max-column-count-spread"));
  const marginTop = parseFloat(style.getPropertyValue("--_margin-top"));
  const marginRight = parseFloat(style.getPropertyValue("--_margin-right"));
  const marginBottom = parseFloat(style.getPropertyValue("--_margin-bottom"));
  const marginLeft = parseFloat(style.getPropertyValue("--_margin-left"));
  __privateSet(this, _marginTop, marginTop);
  __privateSet(this, _marginBottom, marginBottom);
  const flow = this.getAttribute("flow");
  const hostRect = this.getBoundingClientRect();
  const hostSize = vertical ? hostRect.height : hostRect.width;
  const divisor = flow === "scrolled" ? 1 : Math.min(
    maxColumnCount + (vertical ? 1 : 0),
    Math.ceil(Math.floor(hostSize) / Math.floor(maxInlineSize))
  );
  __privateGet(this, _top).style.setProperty("--_column-count", divisor);
  const columnGap = flow !== "scrolled" && !vertical && divisor > 1 ? __privateGet(this, _columnGap) : null;
  if (columnGap != null) {
    const hostGap = parseFloat(style.getPropertyValue("--_gap")) / 100 * hostSize;
    const tracks = getColumnGapHostTracks({ columnGap, marginLeft, marginRight, hostGap });
    __privateGet(this, _top).style.setProperty("--_outer-min-left", `${tracks.outerMinLeft}px`);
    __privateGet(this, _top).style.setProperty("--_outer-min-right", `${tracks.outerMinRight}px`);
    __privateGet(this, _top).style.setProperty("--_gap-cap-extra", `${tracks.capExtra}px`);
  } else {
    __privateGet(this, _top).style.removeProperty("--_outer-min-left");
    __privateGet(this, _top).style.removeProperty("--_outer-min-right");
    __privateGet(this, _top).style.setProperty("--_gap-cap-extra", "0px");
  }
  const { width, height } = __privateGet(this, _container).getBoundingClientRect();
  const size = vertical ? height : width;
  const g = parseFloat(style.getPropertyValue("--_gap")) / 100;
  const gap = -g / (g - 1) * size;
  if (flow === "scrolled") {
    this.setAttribute("dir", vertical ? "rtl" : "ltr");
    __privateGet(this, _top).style.padding = "0";
    const columnWidth2 = maxInlineSize;
    this.heads = null;
    this.feet = null;
    __privateGet(this, _header).replaceChildren();
    __privateGet(this, _footer).replaceChildren();
    this.columnCount = 1;
    __privateMethod(this, _Paginator_instances, replaceBackground_fn).call(this);
    const layout2 = { width, height, flow, marginTop, marginRight, marginBottom, marginLeft, gap, columnWidth: columnWidth2, columnCount: 1, rtl: __privateGet(this, _rtl2) };
    __privateSet(this, _lastLayout, layout2);
    return layout2;
  }
  const columnWidth = vertical ? size / divisor - marginTop * 1.5 - marginBottom * 1.5 : size / divisor - gap - marginRight / 2 - marginLeft / 2;
  this.setAttribute("dir", __privateGet(this, _rtl2) && !vertical ? "rtl" : "ltr");
  this.columnCount = divisor;
  __privateMethod(this, _Paginator_instances, replaceBackground_fn).call(this);
  const marginalDivisor = vertical ? Math.min(2, Math.ceil(Math.floor(width) / Math.floor(maxInlineSize))) : divisor;
  const marginalStyle = {
    gridTemplateColumns: `repeat(${marginalDivisor}, 1fr)`,
    gap: `${columnGap ?? gap}px`,
    direction: this.bookDir === "rtl" ? "rtl" : "ltr"
  };
  Object.assign(__privateGet(this, _header).style, marginalStyle);
  Object.assign(__privateGet(this, _footer).style, marginalStyle);
  const heads = makeMarginals(marginalDivisor, "head");
  const feet = makeMarginals(marginalDivisor, "foot");
  this.heads = heads.map((el) => el.children[0]);
  this.feet = feet.map((el) => el.children[0]);
  __privateGet(this, _header).replaceChildren(...heads);
  __privateGet(this, _footer).replaceChildren(...feet);
  const layout = { width, height, marginTop, marginRight, marginBottom, marginLeft, gap, columnWidth, columnCount: divisor, columnGap, rtl: __privateGet(this, _rtl2) };
  __privateSet(this, _lastLayout, layout);
  return layout;
};
layeredTurn_get = function() {
  const style = this.getAttribute("turn-style");
  return (style === "slide" || style === "curl") && typeof document.startViewTransition === "function" ? style : null;
};
renderedViewSize_get = function() {
  if (__privateGet(this, _views).size === 0) return 0;
  let total = 0;
  for (const [, view] of __privateGet(this, _views))
    total += view.element.getBoundingClientRect()[this.sideProp];
  return total;
};
renderedStart_get = function() {
  return Math.abs(__privateGet(this, _container)[this.scrollProp]);
};
renderedEnd_get = function() {
  return __privateGet(this, _Paginator_instances, renderedStart_get) + this.size;
};
renderedPage_get = function() {
  return Math.floor((__privateGet(this, _Paginator_instances, renderedStart_get) + __privateGet(this, _Paginator_instances, renderedEnd_get)) / 2 / this.size);
};
renderedPages_get = function() {
  return Math.round(__privateGet(this, _Paginator_instances, renderedViewSize_get) / this.size);
};
onTouchStart_fn = function(e) {
  var _a;
  const previousState = __privateGet(this, _touchState);
  const replacementTouch = Boolean(previousState == null ? void 0 : previousState.active);
  if (replacementTouch) __privateMethod(this, _Paginator_instances, rejectLayeredGesture_fn).call(this, previousState);
  const multiTouch = e.touches.length > 1;
  const touch = e.changedTouches[0];
  const currentTarget = e.currentTarget;
  const isInnerDocument = (currentTarget == null ? void 0 : currentTarget.nodeType) === 9;
  const bounds = isInnerDocument ? { left: 0, width: ((_a = currentTarget.documentElement) == null ? void 0 : _a.clientWidth) ?? 0 } : this.getBoundingClientRect();
  const localX = ((touch == null ? void 0 : touch.clientX) ?? 0) - bounds.left;
  const reservedLeftRatio = Math.max(0, Math.min(
    0.5,
    Number(this.getAttribute("turn-gesture-left-inset")) || 0
  ));
  const earlyClaimBlocked = bounds.width > 0 && localX <= bounds.width * reservedLeftRatio;
  const edgeDirection = bounds.width > 0 ? !earlyClaimBlocked && localX <= bounds.width * LAYERED_EDGE_REGION ? -1 : localX >= bounds.width * (1 - LAYERED_EDGE_REGION) ? 1 : 0 : 0;
  const blocked = Boolean(multiTouch || __privateGet(this, _vtFinishing) || __privateGet(this, _vtProgrammatic));
  __privateSet(this, _touchState, {
    x: touch == null ? void 0 : touch.screenX,
    y: touch == null ? void 0 : touch.screenY,
    t: e.timeStamp,
    vx: 0,
    xy: 0,
    dx: 0,
    dy: 0,
    dt: 0,
    releaseSamples: [{ distance: 0, time: e.timeStamp }],
    lastMovementTime: e.timeStamp,
    active: true,
    blocked,
    layeredGesture: blocked ? "rejected" : "pending",
    layeredEarlyClaimBlocked: earlyClaimBlocked,
    layeredEdgeDirection: edgeDirection,
    layeredHorizontalDirection: 0,
    layeredHorizontalSamples: 0,
    layeredHorizontalSampleTime: null
  });
  if (replacementTouch || multiTouch) __privateSet(this, _touchScrolled, false);
  const pv = __privateGet(this, _Paginator_instances, primaryView_get);
  if (pv == null ? void 0 : pv.element) {
    pv.element.style.willChange = "transform";
  }
  if (__privateGet(this, _vertical2) && !this.scrolled && !__privateGet(this, _Paginator_instances, layeredTurn_get)) {
    __privateWrapper(this, _slideTurnId)._++;
    __privateSet(this, _isAnimating, false);
    const children = [...__privateGet(this, _container).children];
    const transform = children[0] && getComputedStyle(children[0]).transform;
    const m41 = transform && transform !== "none" ? new DOMMatrix(transform).m41 : 0;
    __privateSet(this, _dragTranslateX, m41);
    for (const el of children) {
      if (!m41 && !el.style.transform && !el.style.transition) continue;
      el.style.transition = "none";
      el.style.transform = m41 ? `translateX(${m41}px)` : "";
    }
  }
  __privateSet(this, _bgAnimContext, this.scrolled ? null : __privateMethod(this, _Paginator_instances, computePaginatedBgContext_fn).call(this));
};
onTouchMove_fn = function(e) {
  var _a;
  const state = __privateGet(this, _touchState);
  if (!(state == null ? void 0 : state.active) || state.blocked) return;
  if (e.touches.length > 1) {
    if (__privateGet(this, _touchScrolled)) e.preventDefault();
    __privateMethod(this, _Paginator_instances, rejectLayeredGesture_fn).call(this, state);
    return;
  }
  if (state.pinched) {
    __privateMethod(this, _Paginator_instances, rejectLayeredGesture_fn).call(this, state);
    return;
  }
  state.pinched = globalThis.visualViewport.scale > 1;
  if (state.pinched) {
    __privateMethod(this, _Paginator_instances, rejectLayeredGesture_fn).call(this, state);
    return;
  }
  if (this.scrolled) return;
  if (this.hasAttribute("no-swipe")) {
    __privateMethod(this, _Paginator_instances, rejectLayeredGesture_fn).call(this, state);
    return;
  }
  const doc = (_a = __privateGet(this, _Paginator_instances, primaryView_get)) == null ? void 0 : _a.document;
  const selection = doc == null ? void 0 : doc.getSelection();
  if (selection && selection.rangeCount > 0 && !selection.isCollapsed) {
    __privateMethod(this, _Paginator_instances, rejectLayeredGesture_fn).call(this, state);
    return;
  }
  const touch = e.changedTouches[0];
  const isStylus = touch.touchType === "stylus";
  if (!isStylus) e.preventDefault();
  if (__privateGet(this, _scrollLocked)) {
    __privateMethod(this, _Paginator_instances, rejectLayeredGesture_fn).call(this, state);
    return;
  }
  const x = touch.screenX, y = touch.screenY;
  const dx = state.x - x, dy = state.y - y;
  const dt = e.timeStamp - state.t;
  state.x = x;
  state.y = y;
  state.t = e.timeStamp;
  state.vx = dx / dt;
  state.vy = dy / dt;
  state.dx += dx;
  state.dy += dy;
  state.dt += dt;
  updateReleaseSample(state, state.dx, e.timeStamp);
  __privateSet(this, _touchScrolled, true);
  if (!this.hasAttribute("animated") || this.hasAttribute("eink")) return;
  if (__privateGet(this, _Paginator_instances, layeredTurn_get)) {
    if (!__privateGet(this, _vtDrag)) __privateMethod(this, _Paginator_instances, layeredDragStart_fn).call(this, state, dx, dy);
    const drag = __privateGet(this, _vtDrag);
    if (drag) {
      const along = __privateGet(this, _rtl2) ? -state.dx : state.dx;
      const totalDistance = drag.forward ? along : -along;
      const visualDistance = drag.style === "slide" ? totalDistance - drag.visualOriginDistance : totalDistance;
      drag.progress = Math.max(0, Math.min(
        1,
        visualDistance / drag.width
      ));
      __privateMethod(this, _Paginator_instances, vtDragScrub_fn).call(this);
    }
    return;
  }
  if (!__privateGet(this, _vertical2) && Math.abs(state.dx) >= Math.abs(state.dy) && !this.hasAttribute("eink") && (!isStylus || Math.abs(dx) > 1)) {
    this.scrollBy(dx, 0);
  } else if (__privateGet(this, _vertical2) && Math.abs(state.dx) >= Math.abs(state.dy) && (!isStylus || Math.abs(dx) > 1)) {
    __privateMethod(this, _Paginator_instances, dragBy_fn).call(this, dx);
  }
};
// Prepare the document for a layered page turn: choreography classes on
// the root and the view-transition-name on the turn boundary. The host
// app can mark a wider boundary with [data-view-transition-root] (e.g.
// a wrapper that also contains its page header and footer, so the
// furniture turns with the page in both layers); otherwise the outermost
// shadow host in the document tree is named, since shadow-internal names
// are tree-scoped away from the document-level pseudo selectors.
vtSetup_fn = function(style, forward, scrubbing = false) {
  var _a;
  injectViewTransitionStyles();
  const html = document.documentElement;
  const side = __privateGet(this, _rtl2) ? "right" : "left";
  const eatSide = forward !== __privateGet(this, _rtl2) ? "right" : "left";
  const classes = [
    "foliate-vt",
    `foliate-vt-${style}`,
    forward ? "foliate-vt-forward" : "foliate-vt-backward",
    `foliate-vt-${side}`,
    `foliate-vt-eat-${eatSide}`
  ];
  if (scrubbing) classes.push("foliate-vt-scrub");
  let namedHost = this;
  while (namedHost.getRootNode() instanceof ShadowRoot) {
    namedHost = namedHost.getRootNode().host;
  }
  namedHost = namedHost.closest("[data-view-transition-root]") ?? namedHost;
  namedHost.style.viewTransitionName = "foliate-turn";
  __privateSet(this, _vtNamedHost, namedHost);
  const doc = (_a = __privateGet(this, _Paginator_instances, primaryView_get)) == null ? void 0 : _a.document;
  const themeBg = (doc == null ? void 0 : doc.documentElement) ? doc.defaultView.getComputedStyle(doc.documentElement).getPropertyValue("--theme-bg-color").trim() : "";
  html.style.setProperty("--foliate-vt-bg", themeBg || "Canvas");
  html.classList.remove(...VIEW_TRANSITION_CLASSES);
  html.classList.add(...classes);
  return namedHost;
};
vtCleanup_fn = function() {
  var _a;
  const html = document.documentElement;
  html.classList.remove(...VIEW_TRANSITION_CLASSES);
  html.style.removeProperty("--foliate-vt-bg");
  (_a = __privateGet(this, _vtNamedHost)) == null ? void 0 : _a.style.removeProperty("view-transition-name");
  __privateSet(this, _vtNamedHost, null);
};
// Permanently yield this touch sequence to another gesture owner. If the
// layered snapshot already exists, cancel it through the normal lifecycle
// instead of letting later samples (or a replacement finger) scrub it.
rejectLayeredGesture_fn = function(state = __privateGet(this, _touchState)) {
  if (state) {
    state.layeredGesture = "rejected";
    state.layeredHorizontalDirection = 0;
    state.layeredHorizontalSamples = 0;
    state.layeredHorizontalSampleTime = null;
  }
  const drag = __privateGet(this, _vtDrag);
  if (!drag) return;
  __privateSet(this, _vtDrag, null);
  __privateMethod(this, _Paginator_instances, finishLayeredDrag_fn).call(this, drag, false);
};
// Begin a finger-tracked layered turn (readest#555). Edge-originated
// gestures can claim on their first clear inward move. In the middle, two
// consecutive horizontal samples can claim after 6px; a vertical gesture
// locks out the turn before a landing wobble can become a page animation.
// Ambiguous trajectories retain the established 24px + 1.5x fallback.
// Once claimed, the existing `before-capture` lifecycle event explicitly
// transfers ownership to the layered turn.
layeredDragStart_fn = function(state, dx, dy) {
  if (__privateGet(this, _vtDrag) || __privateGet(this, _vtFinishing) || __privateGet(this, _vtProgrammatic) || !__privateGet(this, _scrollBounds)) return;
  const style = __privateGet(this, _Paginator_instances, layeredTurn_get);
  if (!style) return;
  if (state.layeredGesture !== "pending") return;
  const absDx = Math.abs(state.dx);
  const absDy = Math.abs(state.dy);
  if (absDy >= LAYERED_VERTICAL_REJECT_PX && absDy > absDx) {
    state.layeredGesture = "rejected";
    return;
  }
  const direction = Math.sign(dx);
  const locallyHorizontal = direction !== 0 && Math.abs(dx) > Math.abs(dy);
  const clearlyHorizontal = locallyHorizontal && Math.abs(dx) >= Math.abs(dy) * LAYERED_FALLBACK_DOMINANCE;
  const cumulativelyHorizontal = absDx >= absDy * LAYERED_FALLBACK_DOMINANCE;
  if (locallyHorizontal && cumulativelyHorizontal) {
    const recentSample = state.layeredHorizontalSampleTime != null && state.t - state.layeredHorizontalSampleTime <= LAYERED_EARLY_SAMPLE_INTERVAL_MS;
    if (state.layeredHorizontalDirection === direction && recentSample) {
      state.layeredHorizontalSamples++;
    } else {
      state.layeredHorizontalDirection = direction;
      state.layeredHorizontalSamples = 1;
    }
    state.layeredHorizontalSampleTime = state.t;
  } else {
    state.layeredHorizontalDirection = 0;
    state.layeredHorizontalSamples = 0;
    state.layeredHorizontalSampleTime = null;
  }
  const edgeClaim = state.layeredEdgeDirection !== 0 && !state.layeredEarlyClaimBlocked && direction === state.layeredEdgeDirection && Math.sign(state.dx) === state.layeredEdgeDirection && clearlyHorizontal && cumulativelyHorizontal;
  const earlyCenterClaim = state.layeredEdgeDirection === 0 && !state.layeredEarlyClaimBlocked && state.layeredHorizontalSamples >= 2 && absDx >= LAYERED_EARLY_CLAIM_PX && Math.sign(state.dx) === state.layeredHorizontalDirection;
  const fallbackClaim = absDx >= LAYERED_FALLBACK_CLAIM_PX && absDx >= absDy * LAYERED_FALLBACK_DOMINANCE;
  if (!edgeClaim && !earlyCenterClaim && !fallbackClaim) return;
  const along = __privateGet(this, _rtl2) ? -state.dx : state.dx;
  const forward = along > 0;
  state.layeredGesture = "claimed";
  this.dispatchEvent(new CustomEvent("layered-turn-gesture-claimed", {
    detail: { style, forward }
  }));
  const pages = __privateGet(this, _Paginator_instances, renderedPages_get);
  const target = __privateGet(this, _Paginator_instances, renderedPage_get) + (forward ? 1 : -1);
  if (target < 0 || target >= pages) return;
  const offset = this.size * (__privateGet(this, _rtl2) && !__privateGet(this, _vertical2) ? -target : target);
  ++__privateWrapper(this, _slideTurnId)._;
  __privateSet(this, _isAnimating, true);
  this.dispatchEvent(new CustomEvent("layered-turn-state", {
    detail: { phase: "before-capture", style, forward }
  }));
  const startPosition = this.containerPosition;
  let turnRoot;
  let transition;
  try {
    turnRoot = __privateMethod(this, _Paginator_instances, vtSetup_fn).call(this, style, forward, true);
    transition = document.startViewTransition(() => {
      this.containerPosition = offset;
      if (!this.scrolled) {
        __privateSet(this, _bgAnimContext, null);
        __privateMethod(this, _Paginator_instances, replaceBackground_fn).call(this);
      }
      this.dispatchEvent(new CustomEvent("layered-turn-state", {
        detail: { phase: "covered", style, forward }
      }));
    });
  } catch {
    state.layeredGesture = "rejected";
    this.containerPosition = startPosition;
    __privateMethod(this, _Paginator_instances, vtCleanup_fn).call(this);
    __privateSet(this, _isAnimating, false);
    this.dispatchEvent(new CustomEvent("layered-turn-state", {
      detail: { phase: "finished", style, forward, committed: false }
    }));
    return;
  }
  const drag = {
    transition,
    offset,
    startPosition,
    forward,
    style,
    progress: 0,
    anims: null,
    visualOriginDistance: style === "slide" ? Math.max(0, forward ? along : -along) : 0,
    // Progress must use the width of the actual named snapshot. The
    // inner content container can be narrower because of page margins;
    // using it makes the sheet gradually outrun the finger.
    width: turnRoot.getBoundingClientRect().width || __privateGet(this, _container).getBoundingClientRect().width
  };
  __privateSet(this, _vtDrag, drag);
  transition.ready.then(() => {
    if (__privateGet(this, _vtDrag) !== drag && __privateGet(this, _vtFinishing) !== drag) return;
    const anims = document.getAnimations().filter((a) => {
      var _a, _b;
      return (_b = (_a = a.effect) == null ? void 0 : _a.pseudoElement) == null ? void 0 : _b.includes("(foliate-turn)");
    });
    for (const a of anims) {
      try {
        a.effect.updateTiming({ easing: "linear" });
      } catch {
      }
      a.pause();
    }
    drag.anims = anims;
    __privateMethod(this, _Paginator_instances, vtDragScrub_fn).call(this, drag);
    this.dispatchEvent(new CustomEvent("layered-turn-state", {
      detail: { phase: "ready", style, forward }
    }));
  }, () => {
    if (__privateGet(this, _vtDrag) === drag || __privateGet(this, _vtFinishing) === drag) drag.failed = true;
  });
};
vtDragScrub_fn = function(drag = __privateGet(this, _vtDrag)) {
  if (!(drag == null ? void 0 : drag.anims)) return;
  for (const a of drag.anims) {
    const duration = a.effect.getTiming().duration;
    a.currentTime = drag.progress * 0.999 * (typeof duration === "number" ? duration : 300);
  }
};
finishLayeredDrag_fn = async function(drag, commit, playbackRate = 1) {
  if (__privateGet(this, _vtFinishing) === drag) return;
  __privateSet(this, _vtFinishing, drag);
  const { transition, offset, startPosition, style, forward } = drag;
  const { size } = this;
  const id = ++__privateWrapper(this, _slideTurnId)._;
  __privateSet(this, _isAnimating, true);
  try {
    try {
      await transition.updateCallbackDone;
    } catch {
    }
    try {
      await transition.ready;
    } catch {
    }
    if (id !== __privateGet(this, _slideTurnId)) return;
    const anims = drag.anims;
    if (anims) for (const a of anims) updatePlaybackRate(a, playbackRate);
    if (commit) {
      if (anims) for (const a of anims) a.play();
      try {
        await transition.finished;
      } catch {
      }
    } else {
      if (anims) {
        for (const a of anims) a.reverse();
        try {
          await Promise.all(anims.map((a) => a.finished));
        } catch {
        }
      }
      if (id !== __privateGet(this, _slideTurnId)) return;
      this.containerPosition = startPosition;
      this.dispatchEvent(new CustomEvent("layered-turn-state", {
        detail: { phase: "cancelled", style, forward, committed: false }
      }));
      await new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)));
      if (id !== __privateGet(this, _slideTurnId)) return;
      try {
        transition.skipTransition();
      } catch {
      }
      try {
        await transition.finished;
      } catch {
      }
    }
    if (id !== __privateGet(this, _slideTurnId)) return;
    __privateMethod(this, _Paginator_instances, vtCleanup_fn).call(this);
    __privateSet(this, _isAnimating, false);
    const finalPosition = commit ? offset : startPosition;
    this.containerPosition = finalPosition;
    __privateSet(this, _scrollBounds, [
      finalPosition,
      this.atStart ? 0 : size,
      this.atEnd ? 0 : size
    ]);
    __privateMethod(this, _Paginator_instances, afterScroll_fn).call(this, "snap");
    this.dispatchEvent(new CustomEvent("layered-turn-state", {
      detail: { phase: "finished", style, forward, committed: commit }
    }));
  } finally {
    if (__privateGet(this, _vtFinishing) === drag) __privateSet(this, _vtFinishing, null);
  }
};
dragBy_fn = function(dx) {
  if (!__privateGet(this, _scrollBounds)) return;
  const [, a, b] = __privateGet(this, _scrollBounds);
  const width = __privateGet(this, _container).getBoundingClientRect().width;
  const forwardSign = __privateGet(this, _rtl2) ? 1 : -1;
  const max = (forwardSign > 0 ? b : a) > 0 ? width : 0;
  const min = (forwardSign > 0 ? a : b) > 0 ? -width : 0;
  __privateSet(this, _dragTranslateX, Math.max(min, Math.min(max, __privateGet(this, _dragTranslateX) - dx)));
  for (const el of __privateGet(this, _container).children) {
    el.style.transition = "none";
    el.style.transform = `translateX(${__privateGet(this, _dragTranslateX)}px)`;
  }
};
// Animate a released drag back to rest when the page did not turn, and
// drop the inline drag styles once the views are back in place. Pass
// instant=true to drop them without the settle animation.
settleDrag_fn = function(instant) {
  const startX = __privateGet(this, _dragTranslateX);
  __privateSet(this, _dragTranslateX, 0);
  const children = [...__privateGet(this, _container).children];
  if (!children.some((el) => el.style.transform)) return;
  const cleanup = () => {
    for (const el of children) {
      el.style.willChange = "";
      el.style.transition = "";
      el.style.transform = "";
    }
  };
  if (!startX || instant) return cleanup();
  const id = ++__privateWrapper(this, _slideTurnId)._;
  for (const el of children) {
    el.style.transition = "transform 150ms ease-out";
    el.style.transform = "translateX(0px)";
  }
  setTimeout(() => {
    if (id !== __privateGet(this, _slideTurnId)) return;
    cleanup();
  }, 170);
};
onTouchEnd_fn = function(e) {
  var _a;
  __privateSet(this, _bgAnimContext, null);
  const state = __privateGet(this, _touchState);
  if (state) state.active = false;
  if (state == null ? void 0 : state.blocked) {
    __privateSet(this, _touchScrolled, false);
    return;
  }
  if (!__privateGet(this, _touchScrolled)) {
    if (__privateGet(this, _vertical2) && !this.scrolled && __privateGet(this, _dragTranslateX)) __privateMethod(this, _Paginator_instances, settleDrag_fn).call(this);
    return;
  }
  __privateSet(this, _touchScrolled, false);
  if (this.scrolled) return;
  if (this.hasAttribute("no-swipe")) return;
  const layeredRejected = __privateGet(this, _Paginator_instances, layeredTurn_get) && (state == null ? void 0 : state.layeredGesture) === "rejected";
  if (layeredRejected && !__privateGet(this, _vertical2)) return;
  if (state && e && e.timeStamp - state.t > RELEASE_PAUSE_THRESHOLD_MS) {
    state.vx = 0;
    state.vy = 0;
  }
  const releaseTouch = (_a = e == null ? void 0 : e.changedTouches) == null ? void 0 : _a[0];
  let releaseDx = (state == null ? void 0 : state.dx) ?? 0;
  let releaseDy = (state == null ? void 0 : state.dy) ?? 0;
  if (state && releaseTouch) {
    releaseDx += state.x - releaseTouch.screenX;
    releaseDy += state.y - releaseTouch.screenY;
  }
  if (state) updateReleaseSample(state, releaseDx, e.timeStamp);
  const drag = __privateGet(this, _vtDrag);
  if (drag) {
    __privateSet(this, _vtDrag, null);
    const gestureDx = drag.style === "slide" ? releaseDx : (state == null ? void 0 : state.dx) ?? 0;
    const gestureDy = drag.style === "slide" ? releaseDy : (state == null ? void 0 : state.dy) ?? 0;
    const gestureAligned = state ? Math.abs(gestureDx) > Math.abs(gestureDy) : true;
    const alongV = __privateGet(this, _rtl2) ? -((state == null ? void 0 : state.vx) ?? 0) : (state == null ? void 0 : state.vx) ?? 0;
    const recentVx = state ? getReleaseVelocity(state) : 0;
    const recentAlongV = __privateGet(this, _rtl2) ? -recentVx : recentVx;
    const progressVelocity = recentAlongV * (drag.forward ? 1 : -1);
    const releaseAlong = __privateGet(this, _rtl2) ? -releaseDx : releaseDx;
    const releaseDistance = drag.forward ? releaseAlong : -releaseAlong;
    const releaseProgress = Math.max(0, Math.min(
      1,
      releaseDistance / drag.width
    ));
    const releaseVisualProgress = Math.max(0, Math.min(
      1,
      (releaseDistance - drag.visualOriginDistance) / drag.width
    ));
    const projectedProgress = releaseProgress + progressVelocity * SLIDE_RELEASE_PROJECTION_MS / drag.width;
    const curlFlick = Math.abs(alongV) > 0.3 ? Math.sign(alongV) * (drag.forward ? 1 : -1) : 0;
    const commit = gestureAligned && (drag.style === "slide" ? projectedProgress > 0.5 : curlFlick > 0 ? true : curlFlick < 0 ? false : drag.progress > 0.5);
    if (gestureAligned && drag.style === "slide") {
      drag.progress = releaseVisualProgress;
      __privateMethod(this, _Paginator_instances, vtDragScrub_fn).call(this, drag);
    }
    const targetDirection = (drag.forward ? 1 : -1) * (commit ? 1 : -1);
    const releaseSpeed = recentAlongV * targetDirection;
    const playbackRate = layeredSettlePlaybackRate(drag.style, releaseSpeed);
    __privateMethod(this, _Paginator_instances, finishLayeredDrag_fn).call(this, drag, commit, playbackRate);
    return;
  }
  const snapState = state;
  requestAnimationFrame(() => {
    if (globalThis.visualViewport.scale === 1 && snapState && __privateGet(this, _touchState) === snapState) {
      const { vx, vy, dx, dy, dt } = snapState;
      this.snap(
        layeredRejected ? 0 : vx,
        vy,
        layeredRejected ? 0 : dx,
        dy,
        dt
      );
    }
  });
};
onTouchCancel_fn = function() {
  __privateSet(this, _bgAnimContext, null);
  const state = __privateGet(this, _touchState);
  if (state) state.active = false;
  if (state == null ? void 0 : state.blocked) {
    __privateSet(this, _touchScrolled, false);
    return;
  }
  const drag = __privateGet(this, _vtDrag);
  if (drag) {
    __privateSet(this, _vtDrag, null);
    __privateSet(this, _touchScrolled, false);
    __privateMethod(this, _Paginator_instances, finishLayeredDrag_fn).call(this, drag, false);
    return;
  }
  const wasScrolled = __privateGet(this, _touchScrolled);
  __privateSet(this, _touchScrolled, false);
  if (this.scrolled || this.hasAttribute("no-swipe")) return;
  if (__privateGet(this, _Paginator_instances, layeredTurn_get) && (state == null ? void 0 : state.layeredGesture) === "rejected" && !__privateGet(this, _vertical2)) return;
  if (__privateGet(this, _vertical2)) {
    __privateMethod(this, _Paginator_instances, settleDrag_fn).call(this);
  } else if (wasScrolled && __privateGet(this, _scrollBounds)) {
    __privateMethod(this, _Paginator_instances, scrollTo_fn).call(this, __privateGet(this, _scrollBounds)[0], "snap");
  }
};
// allows one to process rects as if they were LTR and horizontal
getRectMapper_fn = function(view) {
  if (this.scrolled) {
    const size = view ? view.element.getBoundingClientRect()[this.sideProp] : __privateGet(this, _Paginator_instances, renderedViewSize_get);
    const marginTop = __privateGet(this, _marginTop);
    const marginBottom = __privateGet(this, _marginBottom);
    return __privateGet(this, _vertical2) ? ({ left, right }) => ({ left: size - right - marginTop, right: size - left - marginBottom }) : ({ top, bottom }) => ({ left: top - marginTop, right: bottom - marginBottom });
  }
  const targetView = view ?? __privateGet(this, _Paginator_instances, primaryView_get);
  const viewSize = targetView ? targetView.element.getBoundingClientRect()[this.sideProp] : __privateGet(this, _Paginator_instances, renderedViewSize_get);
  return __privateGet(this, _vertical2) ? ({ top, bottom }) => ({ left: top, right: bottom }) : __privateGet(this, _rtl2) ? ({ left, right }) => ({ left: viewSize - right, right: viewSize - left }) : (f) => f;
};
scrollToRect_fn = async function(rect, reason) {
  if (this.scrolled) {
    const localOffset2 = __privateMethod(this, _Paginator_instances, getRectMapper_fn).call(this)(rect).left - 3;
    const viewOffset2 = __privateMethod(this, _Paginator_instances, getViewOffset_fn).call(this, __privateGet(this, _primaryIndex));
    return __privateMethod(this, _Paginator_instances, scrollTo_fn).call(this, viewOffset2 + localOffset2, reason);
  }
  const localOffset = __privateMethod(this, _Paginator_instances, getRectMapper_fn).call(this)(rect).left;
  const viewOffset = __privateMethod(this, _Paginator_instances, getViewOffset_fn).call(this, __privateGet(this, _primaryIndex));
  const containerOffset = viewOffset + localOffset;
  return __privateMethod(this, _Paginator_instances, scrollToPage_fn).call(this, Math.floor(containerOffset / this.size + 0.01), reason);
};
scrollTo_fn = async function(offset, reason, smooth) {
  const { size } = this;
  if (Math.abs(this.containerPosition - offset) < 1) {
    __privateSet(this, _scrollBounds, [offset, this.atStart ? 0 : size, this.atEnd ? 0 : size]);
    if (__privateGet(this, _vertical2) && !this.scrolled) __privateMethod(this, _Paginator_instances, settleDrag_fn).call(this);
    __privateMethod(this, _Paginator_instances, afterScroll_fn).call(this, reason);
    return;
  }
  if (this.scrolled && __privateGet(this, _vertical2)) offset = -offset;
  if ((reason === "snap" || smooth) && this.hasAttribute("animated") && !this.hasAttribute("eink")) {
    const turning = Math.abs(offset - this.containerPosition) > size / 2;
    const layered = !this.scrolled && turning ? __privateGet(this, _Paginator_instances, layeredTurn_get) : null;
    if (layered) return __privateMethod(this, _Paginator_instances, viewTransitionTurn_fn).call(this, offset, reason, layered);
    const startPosition = this.containerPosition;
    __privateSet(this, _isAnimating, true);
    if (!this.scrolled && __privateGet(this, _vertical2)) {
      __privateSet(this, _bgAnimContext, null);
      if (!this.hasAttribute("gpu-composite") && __privateGet(this, _Paginator_instances, renderedViewSize_get) > RAF_ANIMATE_SCROLL_THRESHOLD) {
        __privateSet(this, _isAnimating, false);
        __privateMethod(this, _Paginator_instances, settleDrag_fn).call(this, true);
        this.containerPosition = offset;
        __privateSet(this, _scrollBounds, [offset, this.atStart ? 0 : size, this.atEnd ? 0 : size]);
        __privateMethod(this, _Paginator_instances, afterScroll_fn).call(this, reason);
        return;
      }
      const id = ++__privateWrapper(this, _slideTurnId)._;
      const forward = offset > startPosition;
      const exitSign = (__privateGet(this, _rtl2) ? 1 : -1) * (forward ? 1 : -1);
      const width = __privateGet(this, _container).getBoundingClientRect().width;
      const dragStartX = __privateGet(this, _dragTranslateX);
      __privateSet(this, _dragTranslateX, 0);
      return slideTurnAnimation(
        __privateGet(this, _container),
        this.scrollProp,
        offset,
        exitSign,
        width,
        300,
        () => id !== __privateGet(this, _slideTurnId),
        // Reposition the background segments for the new scroll
        // offset while both pages are off-screen.
        () => __privateMethod(this, _Paginator_instances, replaceBackground_fn).call(this),
        dragStartX
      ).then(() => {
        if (id !== __privateGet(this, _slideTurnId)) return;
        __privateSet(this, _isAnimating, false);
        __privateSet(this, _scrollBounds, [offset, this.atStart ? 0 : size, this.atEnd ? 0 : size]);
        __privateMethod(this, _Paginator_instances, afterScroll_fn).call(this, reason);
      });
    }
    __privateSet(this, _bgAnimContext, this.scrolled ? null : __privateMethod(this, _Paginator_instances, computePaginatedBgContext_fn).call(this));
    if (!this.hasAttribute("gpu-composite") && __privateGet(this, _Paginator_instances, renderedViewSize_get) > RAF_ANIMATE_SCROLL_THRESHOLD) {
      return rafAnimateScroll(startPosition, offset, 300, easeOutQuad, (x) => {
        __privateGet(this, _container)[this.scrollProp] = x;
        if (!this.scrolled) __privateMethod(this, _Paginator_instances, replaceBackground_fn).call(this);
      }).then(() => {
        __privateSet(this, _isAnimating, false);
        __privateSet(this, _bgAnimContext, null);
        __privateSet(this, _scrollBounds, [offset, this.atStart ? 0 : size, this.atEnd ? 0 : size]);
        __privateMethod(this, _Paginator_instances, afterScroll_fn).call(this, reason);
      });
    }
    if (!this.scrolled) {
      __privateMethod(this, _Paginator_instances, replaceBackground_fn).call(this, startPosition);
      const child = __privateGet(this, _container).children[0];
      const syncBackground = () => {
        if (!__privateGet(this, _isAnimating)) return;
        const transform = child && getComputedStyle(child).transform;
        const tx = transform && transform !== "none" ? new DOMMatrix(transform)[__privateGet(this, _vertical2) ? "m42" : "m41"] : 0;
        __privateMethod(this, _Paginator_instances, replaceBackground_fn).call(this, startPosition - tx);
        requestAnimationFrame(syncBackground);
      };
      requestAnimationFrame(syncBackground);
    }
    return cssAnimateScroll(
      __privateGet(this, _container),
      this.scrollProp,
      startPosition,
      offset,
      300
    ).then(() => {
      __privateSet(this, _isAnimating, false);
      __privateSet(this, _bgAnimContext, null);
      __privateSet(this, _scrollBounds, [offset, this.atStart ? 0 : size, this.atEnd ? 0 : size]);
      __privateMethod(this, _Paginator_instances, afterScroll_fn).call(this, reason);
    });
  } else {
    if (__privateGet(this, _vertical2) && !this.scrolled) __privateMethod(this, _Paginator_instances, settleDrag_fn).call(this, true);
    this.containerPosition = offset;
    __privateSet(this, _scrollBounds, [offset, this.atStart ? 0 : size, this.atEnd ? 0 : size]);
    __privateMethod(this, _Paginator_instances, afterScroll_fn).call(this, reason);
  }
};
viewTransitionTurn_fn = async function(offset, reason, style) {
  var _a;
  if (__privateGet(this, _vtDrag) || __privateGet(this, _vtFinishing) || __privateGet(this, _vtProgrammatic)) return;
  if ((_a = __privateGet(this, _touchState)) == null ? void 0 : _a.active) __privateMethod(this, _Paginator_instances, rejectLayeredGesture_fn).call(this, __privateGet(this, _touchState));
  const { size } = this;
  const startPosition = this.containerPosition;
  const forward = Math.abs(offset) > Math.abs(startPosition);
  const id = ++__privateWrapper(this, _slideTurnId)._;
  __privateSet(this, _isAnimating, true);
  __privateMethod(this, _Paginator_instances, settleDrag_fn).call(this, true);
  __privateMethod(this, _Paginator_instances, vtSetup_fn).call(this, style, forward);
  const transition = document.startViewTransition(() => {
    this.containerPosition = offset;
    if (!this.scrolled) {
      __privateSet(this, _bgAnimContext, null);
      __privateMethod(this, _Paginator_instances, replaceBackground_fn).call(this);
    }
  });
  const active = { transition, id };
  __privateSet(this, _vtProgrammatic, active);
  try {
    try {
      await transition.finished;
    } catch {
    }
    if (id !== __privateGet(this, _slideTurnId)) return;
    __privateMethod(this, _Paginator_instances, vtCleanup_fn).call(this);
    __privateSet(this, _isAnimating, false);
    this.containerPosition = offset;
    __privateSet(this, _scrollBounds, [offset, this.atStart ? 0 : size, this.atEnd ? 0 : size]);
    __privateMethod(this, _Paginator_instances, afterScroll_fn).call(this, reason);
  } finally {
    if (__privateGet(this, _vtProgrammatic) === active) __privateSet(this, _vtProgrammatic, null);
  }
};
scrollToPage_fn = async function(page, reason, smooth) {
  const offset = this.size * (__privateGet(this, _rtl2) && !__privateGet(this, _vertical2) ? -page : page);
  return __privateMethod(this, _Paginator_instances, scrollTo_fn).call(this, offset, reason, smooth);
};
scrollToAnchor_fn = async function(anchor, reason = "anchor", smooth = false) {
  var _a, _b;
  __privateSet(this, _anchor, anchor);
  const rects = (_b = (_a = uncollapse(anchor)) == null ? void 0 : _a.getClientRects) == null ? void 0 : _b.call(_a);
  if (rects) {
    const rect = Array.from(rects).find((r) => r.width > 0 && r.height > 0 && r.x >= 0 && r.y >= 0) || rects[0];
    if (!rect) return this.scrolled ? __privateMethod(this, _Paginator_instances, scrollTo_fn).call(this, __privateMethod(this, _Paginator_instances, getViewOffset_fn).call(this, __privateGet(this, _primaryIndex)), reason) : __privateMethod(this, _Paginator_instances, scrollToPage_fn).call(this, __privateMethod(this, _Paginator_instances, getPagesBeforeView_fn).call(this, __privateGet(this, _primaryIndex)), reason);
    await __privateMethod(this, _Paginator_instances, scrollToRect_fn).call(this, rect, reason);
    if (reason === "navigation" && !isTypingOutside()) {
      let node = anchor.focus ? anchor : void 0;
      if (!node && anchor.startContainer) {
        node = anchor.startContainer;
        if (node.nodeType === Node.TEXT_NODE) {
          node = node.parentElement;
        }
      }
      if (node && node.focus) {
        node.tabIndex = -1;
        node.style.outline = "none";
        node.focus({ preventScroll: true });
      }
    }
    return;
  }
  if (this.scrolled) {
    const primaryOffset = __privateMethod(this, _Paginator_instances, getViewOffset_fn).call(this, __privateGet(this, _primaryIndex));
    const primaryView2 = __privateGet(this, _Paginator_instances, primaryView_get);
    const primarySize = primaryView2 ? primaryView2.element.getBoundingClientRect()[this.sideProp] : __privateGet(this, _Paginator_instances, renderedViewSize_get);
    await __privateMethod(this, _Paginator_instances, scrollTo_fn).call(this, primaryOffset + anchor * primarySize, reason, smooth);
    return;
  }
  const primaryView = __privateGet(this, _Paginator_instances, primaryView_get);
  if (!primaryView) return;
  const pagesBeforePrimary = __privateMethod(this, _Paginator_instances, getPagesBeforeView_fn).call(this, __privateGet(this, _primaryIndex));
  const textPages = primaryView.contentPages;
  if (!textPages) return __privateMethod(this, _Paginator_instances, scrollToPage_fn).call(this, pagesBeforePrimary, reason);
  const newColumn = Math.round(anchor * (textPages - 1));
  const newSpreadPage = Math.floor(newColumn / this.columnCount);
  await __privateMethod(this, _Paginator_instances, scrollToPage_fn).call(this, pagesBeforePrimary + newSpreadPage, reason, smooth);
};
// Get the pixel offset of a view within the container
getViewOffset_fn = function(index) {
  let offset = 0;
  for (const [i, view] of __privateGet(this, _Paginator_instances, sortedViews_get)) {
    if (i === index) return offset;
    offset += view.element.getBoundingClientRect()[this.sideProp];
  }
  return offset;
};
// Get number of full pages (spreads) before a given view.
// Uses floor so the view's first column is always on or after
// the returned page — never rounded past it. The 0.01 tolerance
// absorbs sub-pixel drift on fractional-DPR devices where
// getBoundingClientRect() accumulates ~0.0001px errors.
getPagesBeforeView_fn = function(index) {
  return Math.floor(__privateMethod(this, _Paginator_instances, getViewOffset_fn).call(this, index) / this.size + 0.01);
};
getVisibleRange_fn = function() {
  const targetView = __privateGet(this, _Paginator_instances, primaryView_get);
  if (!(targetView == null ? void 0 : targetView.document)) return;
  const viewOffset = __privateMethod(this, _Paginator_instances, getViewOffset_fn).call(this, __privateGet(this, _primaryIndex));
  if (this.scrolled) {
    const center = __privateGet(this, _Paginator_instances, renderedStart_get) + this.size / 2;
    let fallback;
    let collapsed;
    for (const [index, v] of __privateGet(this, _Paginator_instances, sortedViews_get)) {
      if (!v.document) continue;
      const off = __privateMethod(this, _Paginator_instances, getViewOffset_fn).call(this, index);
      const vSize = v.element.getBoundingClientRect()[this.sideProp];
      if (off + vSize <= __privateGet(this, _Paginator_instances, renderedStart_get) || off >= __privateGet(this, _Paginator_instances, renderedEnd_get)) continue;
      const range2 = getVisibleRange(
        v.document,
        __privateGet(this, _Paginator_instances, renderedStart_get) - off,
        __privateGet(this, _Paginator_instances, renderedEnd_get) - off,
        __privateMethod(this, _Paginator_instances, getRectMapper_fn).call(this, v)
      );
      if (!range2) continue;
      const coversCenter = center >= off && center < off + vSize;
      if (range2.collapsed) {
        if (!collapsed || coversCenter) collapsed = { range: range2, index };
        continue;
      }
      if (coversCenter) return { range: range2, index };
      fallback ?? (fallback = { range: range2, index });
    }
    return fallback ?? collapsed;
  }
  const range = getVisibleRange(
    targetView.document,
    __privateGet(this, _Paginator_instances, renderedStart_get) - viewOffset,
    __privateGet(this, _Paginator_instances, renderedEnd_get) - viewOffset,
    __privateMethod(this, _Paginator_instances, getRectMapper_fn).call(this, targetView)
  );
  return range ? { range, index: __privateGet(this, _primaryIndex) } : void 0;
};
// Whether the current Range anchor starts inside the visible range.
// Fraction and Element anchors are never considered visible, so they
// keep being replaced by the visible range as before.
anchorIsVisible_fn = function(range) {
  const anchor = __privateGet(this, _anchor);
  if (!(anchor == null ? void 0 : anchor.startContainer)) return false;
  const node = anchor.startContainer;
  if (!node.isConnected || node.ownerDocument !== range.startContainer.ownerDocument)
    return false;
  try {
    return range.comparePoint(node, anchor.startOffset) === 0;
  } catch {
    return false;
  }
};
// Determine which view is primary based on scroll position
detectPrimaryView_fn = function() {
  if (__privateGet(this, _views).size <= 1) return;
  const visibleStart = __privateGet(this, _Paginator_instances, renderedStart_get);
  let offset = 0;
  for (const [index, view] of __privateGet(this, _Paginator_instances, sortedViews_get)) {
    const viewSize = view.element.getBoundingClientRect()[this.sideProp];
    if (visibleStart < offset + viewSize - 1) {
      if (index !== __privateGet(this, _primaryIndex)) {
        __privateSet(this, _primaryIndex, index);
        __privateMethod(this, _Paginator_instances, syncA11y_fn).call(this);
        __privateMethod(this, _Paginator_instances, trimDistantViews_fn).call(this);
        __privateMethod(this, _Paginator_instances, replaceBackground_fn).call(this);
        __privateSet(this, _fillPromise, __privateMethod(this, _Paginator_instances, preloadNext_fn).call(this));
      }
      return;
    }
    offset += viewSize;
  }
};
preloadNext_fn = async function() {
  var _a;
  if (this.noPreload || this.noContinuousScroll) return;
  __privateSet(this, _filling, true);
  try {
    const { size } = this;
    const minPages = 5;
    const maxSections = 8;
    let iterations = 0;
    while (__privateGet(this, _views).size < maxSections && iterations < maxSections) {
      iterations++;
      const pagesAhead = size > 0 ? Math.floor((__privateGet(this, _Paginator_instances, renderedViewSize_get) - __privateGet(this, _Paginator_instances, renderedEnd_get)) / size) : 0;
      if (pagesAhead >= minPages) break;
      const sorted = __privateGet(this, _Paginator_instances, sortedViews_get);
      const lastIndex = (_a = sorted[sorted.length - 1]) == null ? void 0 : _a[0];
      if (lastIndex == null) break;
      const nextIdx = __privateMethod(this, _Paginator_instances, adjacentIndex_fn).call(this, 1, lastIndex);
      if (nextIdx == null) break;
      if (!__privateMethod(this, _Paginator_instances, isSameDirection_fn).call(this, nextIdx)) break;
      await __privateMethod(this, _Paginator_instances, loadAdjacentSection_fn).call(this, nextIdx);
      if (!__privateGet(this, _views).has(nextIdx)) break;
    }
    await new Promise((r) => requestAnimationFrame(r));
  } finally {
    __privateSet(this, _filling, false);
    this.dispatchEvent(new Event("stabilized"));
  }
};
afterScroll_fn = function(reason) {
  if (__privateGet(this, _views).size > 1 && reason !== "anchor" && reason !== "navigation") {
    __privateMethod(this, _Paginator_instances, detectPrimaryView_fn).call(this);
    __privateMethod(this, _Paginator_instances, syncA11y_fn).call(this);
  }
  const { range, index: visibleIndex } = __privateMethod(this, _Paginator_instances, getVisibleRange_fn).call(this) || {};
  if (!range) return;
  __privateSet(this, _lastVisibleRange, range);
  if (reason === "selection" || reason === "navigation" || reason === "anchor")
    __privateSet(this, _justAnchored, true);
  else if (reason !== "container-scroll" || !__privateMethod(this, _Paginator_instances, anchorIsVisible_fn).call(this, range))
    __privateSet(this, _anchor, range);
  const index = visibleIndex ?? __privateGet(this, _primaryIndex);
  const primaryView = __privateGet(this, _Paginator_instances, primaryView_get);
  const detail = { reason, range, index };
  if (this.scrolled) {
    const indexView = __privateGet(this, _views).get(index) ?? primaryView;
    const primaryOffset = __privateMethod(this, _Paginator_instances, getViewOffset_fn).call(this, index);
    const primarySize = indexView ? indexView.element.getBoundingClientRect()[this.sideProp] : __privateGet(this, _Paginator_instances, renderedViewSize_get);
    detail.fraction = primarySize > 0 ? Math.max(0, Math.min(1, (__privateGet(this, _Paginator_instances, renderedStart_get) - primaryOffset) / primarySize)) : 0;
  } else if (__privateGet(this, _Paginator_instances, renderedPages_get) > 0 && primaryView) {
    const page = __privateGet(this, _Paginator_instances, renderedPage_get);
    const pagesBeforePrimary = __privateMethod(this, _Paginator_instances, getPagesBeforeView_fn).call(this, index);
    const textPages = primaryView.contentPages;
    __privateGet(this, _header).style.visibility = page > 0 ? "visible" : "hidden";
    const localPage = page - pagesBeforePrimary;
    const localColumn = localPage * this.columnCount;
    detail.fraction = textPages > 0 ? Math.max(0, Math.min(1, localColumn / textPages)) : 0;
    detail.size = textPages > 0 ? this.columnCount / textPages : 1;
    detail.contentPages = textPages;
    if (reason === "container-scroll" && localPage === 0) return;
  }
  if (!this.scrolled) __privateMethod(this, _Paginator_instances, replaceBackground_fn).call(this);
  const { spine, chunk, count } = __privateGet(this, _units)[index] ?? {};
  if (count > 1) {
    const split = __privateGet(this, _splits).get(spine);
    detail.fraction = split ? split.fraction(chunk, detail.fraction ?? 0) : (chunk + (detail.fraction ?? 0)) / count;
    if (detail.size != null) detail.size /= count;
  }
  detail.index = spine ?? index;
  this.dispatchEvent(new CustomEvent("relocate", { detail }));
};
display_fn = async function(promise) {
  var _a, _b, _c, _d, _e;
  __privateSet(this, _stabilizing, true);
  __privateGet(this, _container).style.opacity = "0";
  const { index, src, data, anchor, onLoad, select } = await promise;
  __privateSet(this, _primaryIndex, index);
  __privateMethod(this, _Paginator_instances, syncA11y_fn).call(this);
  const hasFocus = (_b = (_a = __privateGet(this, _Paginator_instances, primaryView_get)) == null ? void 0 : _a.document) == null ? void 0 : _b.hasFocus();
  if (src) {
    const view = __privateMethod(this, _Paginator_instances, createView_fn).call(this, index);
    const afterLoad = (doc) => {
      var _a2;
      if (doc.head) {
        const $styleBefore = doc.createElement("style");
        doc.head.prepend($styleBefore);
        const $style = doc.createElement("style");
        doc.head.append($style);
        (_a2 = this.sections[index].spineProperties) == null ? void 0 : _a2.forEach(
          (prop) => doc.documentElement.setAttribute("data-" + prop, "")
        );
        __privateGet(this, _styleMap).set(doc, [$styleBefore, $style]);
      }
      return onLoad == null ? void 0 : onLoad({ doc, index });
    };
    const beforeRender = __privateMethod(this, _Paginator_instances, beforeRender_fn).bind(this);
    await view.load(src, data, afterLoad, beforeRender);
    if (__privateGet(this, _views).get(index) !== view) return;
    if (!((_c = view.document) == null ? void 0 : _c.documentElement) || !view.document.body) {
      __privateMethod(this, _Paginator_instances, destroyView_fn).call(this, index);
      __privateSet(this, _primaryIndex, ((_d = __privateGet(this, _Paginator_instances, sortedViews_get)[0]) == null ? void 0 : _d[0]) ?? -1);
      __privateGet(this, _container).style.opacity = "1";
      __privateSet(this, _stabilizing, false);
      this.dispatchEvent(new Event("stabilized"));
      return;
    }
    if (view.document) {
      const dir = getDirection(view.document);
      __privateGet(this, _directionCache).set(index, dir.vertical);
    }
    this.dispatchEvent(new CustomEvent("create-overlayer", {
      detail: {
        doc: view.document,
        index: __privateMethod(this, _Paginator_instances, spineOf_fn).call(this, index),
        attach: (overlayer) => view.overlayer = overlayer
      }
    }));
  }
  const primaryView = __privateGet(this, _Paginator_instances, primaryView_get);
  if (!this.noPreload && !this.noContinuousScroll && primaryView) {
    const needsPrev = primaryView.contentPages > 0 && primaryView.contentPages < this.columnCount;
    if (needsPrev || this.scrolled) {
      const sorted = __privateGet(this, _Paginator_instances, sortedViews_get);
      const firstIndex = (_e = sorted[0]) == null ? void 0 : _e[0];
      if (firstIndex != null) {
        const prevIdx = __privateMethod(this, _Paginator_instances, adjacentIndex_fn).call(this, -1, firstIndex);
        if (prevIdx != null && __privateMethod(this, _Paginator_instances, isSameDirection_fn).call(this, prevIdx)) {
          await __privateMethod(this, _Paginator_instances, loadAdjacentSection_fn).call(this, prevIdx);
        }
      }
    }
  }
  const resolvedAnchor = (typeof anchor === "function" ? anchor(primaryView.document) : anchor) ?? 0;
  await this.scrollToAnchor(resolvedAnchor, select);
  if (hasFocus && !isTypingOutside()) this.focusView();
  __privateGet(this, _container).style.opacity = "1";
  __privateSet(this, _rendered, true);
  this.dispatchEvent(new Event("stabilized"));
  __privateSet(this, _fillPromise, __privateMethod(this, _Paginator_instances, fillVisibleArea_fn).call(this, { reanchor: !this.scrolled }));
  __privateGet(this, _fillPromise).then(() => {
    __privateSet(this, _stabilizing, false);
  });
};
loadAdjacentSection_fn = async function(index) {
  var _a, _b, _c;
  if (__privateGet(this, _views).has(index) || !__privateMethod(this, _Paginator_instances, canGoToIndex_fn).call(this, index)) return;
  const unit = __privateGet(this, _units)[index];
  if ((unit == null ? void 0 : unit.count) > 1) await __privateMethod(this, _Paginator_instances, splitSection_fn).call(this, unit.spine);
  const section = this.sections[index];
  if (!section || section.linear === "no") return;
  const firstIndex = (_a = __privateGet(this, _Paginator_instances, sortedViews_get)[0]) == null ? void 0 : _a[0];
  const isPrepend = this.scrolled && firstIndex != null && index < firstIndex;
  const startBefore = isPrepend ? __privateGet(this, _Paginator_instances, renderedStart_get) : 0;
  try {
    const src = await section.load();
    const data = await ((_b = section.loadContent) == null ? void 0 : _b.call(section));
    const view = __privateMethod(this, _Paginator_instances, createView_fn).call(this, index);
    const afterLoad = async (doc) => {
      var _a2;
      if (doc.head) {
        const $styleBefore = doc.createElement("style");
        doc.head.prepend($styleBefore);
        const $style = doc.createElement("style");
        doc.head.append($style);
        (_a2 = section.spineProperties) == null ? void 0 : _a2.forEach(
          (prop) => doc.documentElement.setAttribute("data-" + prop, "")
        );
        __privateGet(this, _styleMap).set(doc, [$styleBefore, $style]);
      }
      __privateMethod(this, _Paginator_instances, applyStyles_fn).call(this, doc);
      await yieldToFrame();
      if (__privateGet(this, _views).get(index) !== view || view.document !== doc) return;
      this.dispatchEvent(new CustomEvent(
        "load",
        { detail: { doc, index: __privateMethod(this, _Paginator_instances, spineOf_fn).call(this, index) } }
      ));
    };
    const cachedLayout = __privateGet(this, _lastLayout);
    const beforeRender = () => cachedLayout;
    await view.load(src, data, afterLoad, beforeRender, async () => {
      var _a2;
      for (let idleFrames = 0; idleFrames < 2 && __privateGet(this, _views).get(index) === view; ) {
        if (__privateMethod(this, _Paginator_instances, getViewOffset_fn).call(this, index) <= __privateGet(this, _Paginator_instances, renderedEnd_get) + this.size) return;
        await new Promise((resolve) => requestAnimationFrame(resolve));
        idleFrames = ((_a2 = __privateGet(this, _touchState)) == null ? void 0 : _a2.active) || __privateGet(this, _isAnimating) ? 0 : idleFrames + 1;
      }
    });
    if (__privateGet(this, _views).get(index) !== view) return;
    if (!((_c = view.document) == null ? void 0 : _c.documentElement) || !view.document.body) {
      __privateMethod(this, _Paginator_instances, destroyView_fn).call(this, index);
      return;
    }
    if (view.document) {
      const dir = getDirection(view.document);
      __privateGet(this, _directionCache).set(index, dir.vertical);
      if (dir.vertical !== __privateGet(this, _vertical2)) {
        __privateMethod(this, _Paginator_instances, destroyView_fn).call(this, index);
        return;
      }
    }
    if (isPrepend) {
      const addedSize = view.element.getBoundingClientRect()[this.sideProp];
      const correction = startBefore + addedSize - __privateGet(this, _Paginator_instances, renderedStart_get);
      if (Math.abs(correction) > 0.5)
        this.containerPosition += (__privateGet(this, _vertical2) ? -1 : 1) * correction;
    }
    this.dispatchEvent(new CustomEvent("create-overlayer", {
      detail: {
        doc: view.document,
        index: __privateMethod(this, _Paginator_instances, spineOf_fn).call(this, index),
        attach: (overlayer) => view.overlayer = overlayer
      }
    }));
  } catch (e) {
    console.warn(e);
    console.warn(new Error(`Failed to load adjacent section ${index}`));
  }
};
fillVisibleArea_fn = async function({ reanchor = true } = {}) {
  var _a, _b;
  if (this.noPreload || this.noContinuousScroll || __privateGet(this, _filling)) return;
  __privateSet(this, _filling, true);
  try {
    const { size } = this;
    if (!size) return;
    const minPages = 5;
    const maxSections = 8;
    const primaryView = __privateGet(this, _Paginator_instances, primaryView_get);
    if (primaryView && primaryView.contentPages > 0 && primaryView.contentPages < this.columnCount) {
      const sorted = __privateGet(this, _Paginator_instances, sortedViews_get);
      const firstIndex = (_a = sorted[0]) == null ? void 0 : _a[0];
      if (firstIndex != null && firstIndex >= __privateGet(this, _primaryIndex)) {
        const prevIdx = __privateMethod(this, _Paginator_instances, adjacentIndex_fn).call(this, -1, firstIndex);
        if (prevIdx != null && __privateMethod(this, _Paginator_instances, isSameDirection_fn).call(this, prevIdx)) {
          await __privateMethod(this, _Paginator_instances, loadAdjacentSection_fn).call(this, prevIdx);
        }
      }
    }
    let iterations = 0;
    while (__privateGet(this, _views).size < maxSections && iterations < maxSections) {
      iterations++;
      const pagesAhead = Math.floor(
        (__privateGet(this, _Paginator_instances, renderedViewSize_get) - __privateGet(this, _Paginator_instances, renderedEnd_get)) / size
      );
      if (pagesAhead >= minPages) break;
      const sorted = __privateGet(this, _Paginator_instances, sortedViews_get);
      const lastIndex = (_b = sorted[sorted.length - 1]) == null ? void 0 : _b[0];
      if (lastIndex == null) break;
      const nextIdx = __privateMethod(this, _Paginator_instances, adjacentIndex_fn).call(this, 1, lastIndex);
      if (nextIdx == null) break;
      if (!__privateMethod(this, _Paginator_instances, isSameDirection_fn).call(this, nextIdx)) break;
      await __privateMethod(this, _Paginator_instances, loadAdjacentSection_fn).call(this, nextIdx);
      if (!__privateGet(this, _views).has(nextIdx)) break;
    }
    if (reanchor) __privateMethod(this, _Paginator_instances, scrollToAnchor_fn).call(this, __privateGet(this, _anchor));
  } finally {
    __privateSet(this, _filling, false);
    this.dispatchEvent(new Event("stabilized"));
  }
};
// Trim views whose content is entirely more than 10 pages away
// from the current viewport. Only removes views AFTER the primary
// — removing views before would shift scroll position.
trimDistantViews_fn = function() {
  const { size } = this;
  if (!size) return;
  const maxDistance = size * 10;
  const viewportEnd = __privateGet(this, _Paginator_instances, renderedEnd_get);
  for (const [index, view] of __privateGet(this, _Paginator_instances, sortedViews_get)) {
    if (index <= __privateGet(this, _primaryIndex)) continue;
    const offset = __privateMethod(this, _Paginator_instances, getViewOffset_fn).call(this, index);
    if (offset - viewportEnd > maxDistance) {
      __privateMethod(this, _Paginator_instances, destroyView_fn).call(this, index);
    }
  }
};
canGoToIndex_fn = function(index) {
  return index >= 0 && index <= this.sections.length - 1;
};
goTo_fn = async function({ index, anchor, select }) {
  var _a, _b;
  if (__privateGet(this, _pagePreview)) await __privateGet(this, _pagePreview);
  const section = this.sections[index];
  if (!section) return;
  let directionChanged = false;
  if (__privateGet(this, _views).has(index)) {
    const view = __privateGet(this, _views).get(index);
    if (view == null ? void 0 : view.document) {
      const { vertical } = getDirection(view.document);
      directionChanged = vertical !== __privateGet(this, _vertical2);
    }
  } else if (__privateGet(this, _directionCache).has(index)) {
    directionChanged = __privateGet(this, _directionCache).get(index) !== __privateGet(this, _vertical2);
  }
  if (__privateGet(this, _views).has(index) && !directionChanged) {
    __privateSet(this, _stabilizing, true);
    const blank = !this.scrolled || this.noContinuousScroll;
    if (blank) __privateGet(this, _container).style.opacity = "0";
    const hasFocus = (_b = (_a = __privateGet(this, _Paginator_instances, primaryView_get)) == null ? void 0 : _a.document) == null ? void 0 : _b.hasFocus();
    __privateSet(this, _primaryIndex, index);
    __privateMethod(this, _Paginator_instances, syncA11y_fn).call(this);
    __privateMethod(this, _Paginator_instances, trimDistantViews_fn).call(this);
    if (this.noContinuousScroll) {
      for (const [i] of __privateGet(this, _views)) {
        if (i !== index) __privateMethod(this, _Paginator_instances, destroyView_fn).call(this, i);
      }
    }
    const primaryView = __privateGet(this, _Paginator_instances, primaryView_get);
    const resolvedAnchor = (typeof anchor === "function" ? anchor(primaryView.document) : anchor) ?? 0;
    const needsPrev = primaryView && primaryView.contentPages > 0 && primaryView.contentPages < this.columnCount;
    const loadPrev = async () => {
      var _a2;
      if (this.noPreload || this.noContinuousScroll) return;
      if (!(needsPrev || this.scrolled)) return;
      const firstIndex = (_a2 = __privateGet(this, _Paginator_instances, sortedViews_get)[0]) == null ? void 0 : _a2[0];
      if (firstIndex == null) return;
      const prevIdx = __privateMethod(this, _Paginator_instances, adjacentIndex_fn).call(this, -1, firstIndex);
      if (prevIdx != null && __privateMethod(this, _Paginator_instances, isSameDirection_fn).call(this, prevIdx))
        await __privateMethod(this, _Paginator_instances, loadAdjacentSection_fn).call(this, prevIdx);
    };
    if (!this.scrolled) await loadPrev();
    await this.scrollToAnchor(resolvedAnchor, select);
    if (this.scrolled) await loadPrev();
    if (blank) __privateGet(this, _container).style.opacity = "1";
    if (hasFocus && !isTypingOutside()) this.focusView();
    __privateSet(this, _fillPromise, __privateMethod(this, _Paginator_instances, fillVisibleArea_fn).call(this));
    __privateGet(this, _fillPromise).then(() => {
      __privateSet(this, _stabilizing, false);
    });
  } else {
    if (directionChanged) {
      __privateMethod(this, _Paginator_instances, destroyAllViews_fn).call(this);
    } else {
      const keep = /* @__PURE__ */ new Set([index]);
      if (!this.noContinuousScroll) {
        for (const [i] of __privateGet(this, _views)) {
          if (Math.abs(i - index) <= 2) keep.add(i);
        }
      }
      __privateMethod(this, _Paginator_instances, clearViewsExcept_fn).call(this, keep);
    }
    const oldIndex = __privateGet(this, _primaryIndex);
    const onLoad = async (detail) => {
      var _a2, _b2, _c;
      if (oldIndex >= 0 && !__privateGet(this, _views).has(oldIndex))
        (_b2 = (_a2 = this.sections[oldIndex]) == null ? void 0 : _a2.unload) == null ? void 0 : _b2.call(_a2);
      __privateMethod(this, _Paginator_instances, applyStyles_fn).call(this, detail.doc);
      await yieldToFrame();
      if (((_c = __privateGet(this, _views).get(index)) == null ? void 0 : _c.document) !== detail.doc) return;
      this.dispatchEvent(new CustomEvent(
        "load",
        { detail: { ...detail, index: __privateMethod(this, _Paginator_instances, spineOf_fn).call(this, detail.index) } }
      ));
    };
    await __privateMethod(this, _Paginator_instances, display_fn).call(this, Promise.resolve(section.load()).then(async (src) => {
      var _a2;
      const data = await ((_a2 = section.loadContent) == null ? void 0 : _a2.call(section));
      return { index, src, data, anchor, onLoad, select };
    }).catch((e) => {
      console.warn(e);
      console.warn(new Error(`Failed to load section ${index}`));
      return {};
    }));
  }
};
goToUnit_fn = async function(index) {
  if (__privateGet(this, _locked)) return;
  if (__privateMethod(this, _Paginator_instances, canGoToIndex_fn).call(this, index)) return __privateMethod(this, _Paginator_instances, goTo_fn).call(this, { index });
};
scrollPrev_fn = function(distance) {
  if (__privateGet(this, _views).size === 0) return true;
  if (this.scrolled) {
    if (__privateGet(this, _Paginator_instances, renderedStart_get) > 0) return __privateMethod(this, _Paginator_instances, scrollTo_fn).call(this, Math.max(0, __privateGet(this, _Paginator_instances, renderedStart_get) - (distance ?? this.size)), null, true);
    return !this.atStart;
  }
  if (this.atStart) return;
  const page = __privateGet(this, _Paginator_instances, renderedPage_get) - 1;
  if (page < 0) return true;
  return __privateMethod(this, _Paginator_instances, scrollToPage_fn).call(this, page, "page", true);
};
scrollNext_fn = function(distance) {
  if (__privateGet(this, _views).size === 0) return true;
  if (this.scrolled) {
    if (__privateGet(this, _Paginator_instances, renderedViewSize_get) - __privateGet(this, _Paginator_instances, renderedEnd_get) > 2) return __privateMethod(this, _Paginator_instances, scrollTo_fn).call(this, Math.min(__privateGet(this, _Paginator_instances, renderedViewSize_get), distance ? __privateGet(this, _Paginator_instances, renderedStart_get) + distance : __privateGet(this, _Paginator_instances, renderedEnd_get)), null, true);
    return !this.atEnd;
  }
  if (this.atEnd) return;
  const page = __privateGet(this, _Paginator_instances, renderedPage_get) + 1;
  const pages = __privateGet(this, _Paginator_instances, renderedPages_get);
  if (page >= pages) return true;
  return __privateMethod(this, _Paginator_instances, scrollToPage_fn).call(this, page, "page", true);
};
adjacentIndex_fn = function(dir, fromIndex) {
  var _a;
  if (fromIndex === void 0) fromIndex = __privateGet(this, _primaryIndex);
  for (let index = fromIndex + dir; __privateMethod(this, _Paginator_instances, canGoToIndex_fn).call(this, index); index += dir)
    if (((_a = this.sections[index]) == null ? void 0 : _a.linear) !== "no") return index;
};
adjacentUnit_fn = async function(dir, fromIndex) {
  const index = __privateMethod(this, _Paginator_instances, adjacentIndex_fn).call(this, dir, fromIndex);
  const unit = __privateGet(this, _units)[index];
  if ((unit == null ? void 0 : unit.count) > 1 && !__privateGet(this, _splits).has(unit.spine)) {
    await __privateMethod(this, _Paginator_instances, splitSection_fn).call(this, unit.spine);
    return __privateMethod(this, _Paginator_instances, adjacentIndex_fn).call(this, dir, fromIndex);
  }
  return index;
};
turnPage_fn = async function(dir, distance) {
  var _a, _b;
  const nativeCommit = this.hasAttribute("data-native-paper-commit");
  if (__privateGet(this, _pagePreview)) await __privateGet(this, _pagePreview);
  if (__privateGet(this, _locked)) return;
  __privateSet(this, _locked, true);
  const prev = dir === -1;
  const shouldGo = await (prev ? __privateMethod(this, _Paginator_instances, scrollPrev_fn).call(this, distance) : __privateMethod(this, _Paginator_instances, scrollNext_fn).call(this, distance));
  if (shouldGo) {
    if (__privateGet(this, _fillPromise)) await __privateGet(this, _fillPromise);
    const sorted = __privateGet(this, _Paginator_instances, sortedViews_get);
    const edgeIndex = prev ? ((_a = sorted[0]) == null ? void 0 : _a[0]) ?? __privateGet(this, _primaryIndex) : ((_b = sorted[sorted.length - 1]) == null ? void 0 : _b[0]) ?? __privateGet(this, _primaryIndex);
    await __privateMethod(this, _Paginator_instances, goTo_fn).call(this, {
      index: await __privateMethod(this, _Paginator_instances, adjacentUnit_fn).call(this, dir, edgeIndex),
      anchor: prev ? () => 1 : () => 0
    });
  }
  if (!nativeCommit && (shouldGo || !this.hasAttribute("animated"))) await wait(100);
  __privateSet(this, _locked, false);
};
applyStyles_fn = function(doc) {
  const $$styles = __privateGet(this, _styleMap).get(doc);
  if (!$$styles) return;
  const [$beforeStyle, $style] = $$styles;
  const styles = __privateGet(this, _styles);
  if (Array.isArray(styles)) {
    const [beforeStyle, style] = styles;
    $beforeStyle.textContent = beforeStyle;
    $style.textContent = style;
  } else $style.textContent = styles;
};
__publicField(Paginator, "observedAttributes", [
  "flow",
  "gap",
  "column-gap",
  "margin-top",
  "margin-bottom",
  "margin-left",
  "margin-right",
  "max-inline-size",
  "max-block-size",
  "max-column-count",
  "no-preload",
  "no-background",
  "no-continuous-scroll"
]);
customElements.define("foliate-paginator", Paginator);
export {
  Paginator,
  computeBackgroundSegments,
  fontsReady,
  getColumnGapHostTracks,
  getDirection,
  getHorizontalColumnMetrics,
  getPageProgressionRTL,
  isViewVisibleInContainer,
  textureAwareBackground
};
