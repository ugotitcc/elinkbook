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
var _root, _observer, _spreads, _index, _portrait, _left, _right, _center, _side, _zoom, _scaleFactor, _totalScaleFactor, _scrollLocked, _pannedX, _lockedPanX, _pendingPanX, _isOverflowX, _isOverflowY, _preloadCache, _prerenderedSpreads, _spreadAccessTime, _spreadAccessTick, _staleSpreads, _maxConcurrentPreloads, _numPrerenderedSpreads, _maxCachedSpreads, _overlayers, _pageColors, _preloadQueue, _activePreloads, _scrollMode, _scrollHorizontal, _scrollPages, _scrollMounted, _scrollLayout, _scrollContainer, _scrollLoadGen, _scrollMaxLoaded, _scrollMaxConcurrent, _scrollLoadingCount, _scrollIdleTimer, _scrollCurrentIndex, _scrolling, _pinching, _pinchAnchor, _FixedLayout_instances, captureCenterPageRect_fn, restorePinchAnchor_fn, getScrollModePageMetrics_fn, captureScrollModeAnchor_fn, restoreScrollModeAnchor_fn, scrollViewLength_fn, scrollTotalLength_fn, scrollProgression_fn, setScrollProgression_fn, applyPanLock_fn, applyPanLockToFrames_fn, syncScrollPanLock_fn, maxPanX_fn, applyPendingPanX_fn, setLockedPanX_fn, clearLockedPanX_fn, createFrame_fn, render_fn, showSpread_fn, initScrollMode_fn, updateScrollWindow_fn, mountScrollPage_fn, placeScrollPage_fn, scrollPageScale_fn, layoutScrollPages_fn, scheduleScrollPages_fn, _handleScrollEvent, _handleScrollWheel, setScrollIframeInteraction_fn, destroyScrollMode_fn, createScrollFrame_fn, loadScrollPage_fn, teardownScrollPage_fn, renderScrollMode_fn, renderScrollPage_fn, getScrollIndex_fn, scrollToPage_fn, reportScrollLocation_fn, goLeft_fn, goRight_fn, spread_fn, respread_fn, regroup_fn, goToPageOf_fn, reportLocation_fn, preloadNextSpreads_fn, processPreloadQueue_fn, touchSpread_fn, cleanupPreloadCache_fn, removeOverlayerForFrame_fn, refreshOverlayerForFrame_fn, shownFrames_fn;
import "./construct-style-sheets-polyfill.js";
const parseViewport = (str) => {
  var _a, _b;
  return (_b = (_a = str == null ? void 0 : str.split(/[,;\s]/)) == null ? void 0 : _a.filter((x) => x)) == null ? void 0 : _b.map((x) => x.split("=").map((x2) => x2.trim()));
};
const getPageSize = (str) => {
  const props = Object.fromEntries(parseViewport(str) ?? []);
  if (parseFloat(props.width) > 0 && parseFloat(props.height) > 0) return props;
};
const getImageSize = async (src) => {
  const img = new Image();
  img.src = src;
  await img.decode().catch(() => {
  });
  return { width: img.naturalWidth, height: img.naturalHeight };
};
const getViewport = async (doc, viewport) => {
  var _a, _b;
  if (doc.documentElement.localName === "svg") {
    const [, , width, height] = ((_a = doc.documentElement.getAttribute("viewBox")) == null ? void 0 : _a.split(/\s/)) ?? [];
    return { width, height };
  }
  const meta = getPageSize((_b = doc.querySelector('meta[name="viewport"]')) == null ? void 0 : _b.getAttribute("content"));
  if (meta) return meta;
  if (typeof viewport === "string") {
    const size = getPageSize(viewport);
    if (size) return size;
  } else if ((viewport == null ? void 0 : viewport.width) && viewport.height) return viewport;
  const img = doc.querySelector("img");
  if (img) return { width: img.naturalWidth, height: img.naturalHeight };
  const image = doc.querySelector("svg image");
  const src = (image == null ? void 0 : image.getAttribute("href")) ?? (image == null ? void 0 : image.getAttribute("xlink:href"));
  if (src) {
    const { width, height } = await getImageSize(src);
    if (width > 0 && height > 0) return { width, height };
  }
  console.warn(new Error("Missing viewport properties"));
  return { width: 1e3, height: 2e3 };
};
const clamp = (value, min, max) => Math.min(max, Math.max(min, value));
const captureScrollModeAnchor = (pages, scrollPos, fallbackIndex = -1) => {
  const fallbackPage = pages.find((page) => page.index === fallbackIndex);
  const currentPage = pages.find((page) => page.size > 0 && scrollPos >= page.start && scrollPos < page.start + page.size) ?? fallbackPage ?? pages.find((page) => page.size > 0);
  if (!currentPage) return null;
  return {
    index: currentPage.index,
    fraction: currentPage.size > 0 ? clamp((scrollPos - currentPage.start) / currentPage.size, 0, 1) : 0,
    scrollPos
  };
};
const restoreScrollModeAnchor = (pages, anchor, maxScrollPos) => {
  if (!anchor) return 0;
  const page = pages.find((candidate) => candidate.index === anchor.index);
  if (!page || page.size <= 0) return clamp(anchor.scrollPos, 0, maxScrollPos);
  return clamp(page.start + page.size * anchor.fraction, 0, maxScrollPos);
};
const scrollGapToCss = (value) => {
  const n = parseFloat(value);
  return Number.isFinite(n) && n >= 0 ? `${n}px` : null;
};
const layoutScrollPages = ({ sizes, gap, overlap }) => {
  const starts = [];
  let pos = gap;
  for (const size of sizes) {
    starts.push(pos);
    pos += size + 2 * gap - overlap;
  }
  return { starts, sizes, total: sizes.length ? pos - gap + overlap : 0 };
};
const findScrollPageRange = ({ starts, sizes }, lo, hi) => {
  const first = (test) => {
    let a = 0, b = starts.length;
    while (a < b) {
      const mid = a + b >> 1;
      if (test(mid)) b = mid;
      else a = mid + 1;
    }
    return a;
  };
  return [first((i) => starts[i] + sizes[i] > lo), first((i) => starts[i] >= hi)];
};
const planScrollModePages = ({
  pages,
  currentIndex,
  maxLoaded,
  maxConcurrent,
  loadingCount
}) => {
  const dist = (page) => Math.abs(page.index - currentIndex);
  const budget = Math.max(0, maxConcurrent - loadingCount);
  const load = budget === 0 ? [] : pages.filter((page) => page.visible && page.state === "idle").sort((a, b) => dist(a) - dist(b)).slice(0, budget).map((page) => page.index);
  const loaded = pages.filter((page) => page.state === "loaded");
  const evict = loaded.length <= maxLoaded ? [] : loaded.filter((page) => !page.visible).sort((a, b) => dist(b) - dist(a)).slice(0, loaded.length - maxLoaded).map((page) => page.index);
  return { load, evict };
};
const computeScrollPinchTransform = ({
  ratio,
  scrollLeft,
  scrollTop,
  viewportWidth,
  viewportHeight
}) => ({
  transform: `scale(${ratio})`,
  transformOrigin: `${scrollLeft + viewportWidth / 2}px ${scrollTop + viewportHeight / 2}px`
});
const computePaginatedScroll = ({
  elementWidth,
  containerWidth,
  scrollTop,
  scrollLeft,
  pageTurn,
  lockPanX
}) => ({
  scrollLeft: lockPanX ? scrollLeft : (elementWidth - containerWidth) / 2,
  scrollTop: pageTurn ? 0 : scrollTop
});
const computeScrollWheelDelta = ({
  deltaX,
  deltaY,
  ctrlKey,
  horizontal,
  rtl,
  verticalOverflow
}) => {
  if (!horizontal || ctrlKey || verticalOverflow) return null;
  if (Math.abs(deltaY) <= Math.abs(deltaX)) return null;
  return { left: rtl ? -deltaY : deltaY };
};
const computeSpreadSpineOverlap = ({
  center = false,
  portrait = false,
  leftBlank = false,
  rightBlank = false,
  devicePixelRatio = 1
} = {}) => {
  if (center || portrait || leftBlank || rightBlank) return 0;
  return -1 / (devicePixelRatio || 1);
};
const computeScrollPageOverlap = ({ gap = 4, devicePixelRatio = 1 } = {}) => gap === 0 ? 2 / (devicePixelRatio || 1) : 0;
const computeSpreadColumnCount = ({
  center = false,
  portrait = false,
  scrolled = false,
  leftBlank = true,
  rightBlank = true
} = {}) => center || portrait || scrolled || leftBlank || rightBlank ? 1 : 2;
const computeSpreadInlineMargins = (portrait) => portrait ? {
  left: { marginInlineStart: "auto", marginInlineEnd: "auto" },
  right: { marginInlineStart: "auto", marginInlineEnd: "auto" }
} : {
  left: { marginInlineStart: "auto", marginInlineEnd: "" },
  right: { marginInlineStart: "", marginInlineEnd: "auto" }
};
const applyOverlayerViewBox = (frame, overlayer) => {
  if (!(overlayer == null ? void 0 : overlayer.element)) return;
  const el = overlayer.element;
  if (frame == null ? void 0 : frame.onZoom) {
    el.removeAttribute("viewBox");
    el.removeAttribute("preserveAspectRatio");
  } else {
    const w = (frame == null ? void 0 : frame.width) ?? (frame == null ? void 0 : frame.vpWidth);
    const h = (frame == null ? void 0 : frame.height) ?? (frame == null ? void 0 : frame.vpHeight);
    if (w && h) {
      el.setAttribute("viewBox", `0 0 ${w} ${h}`);
      el.setAttribute("preserveAspectRatio", "none");
    }
  }
};
class FixedLayout extends HTMLElement {
  constructor() {
    super();
    __privateAdd(this, _FixedLayout_instances);
    __privateAdd(this, _root, this.attachShadow({ mode: "open" }));
    __privateAdd(this, _observer, new ResizeObserver(() => __privateMethod(this, _FixedLayout_instances, render_fn).call(this)));
    __privateAdd(this, _spreads);
    __privateAdd(this, _index, -1);
    __publicField(this, "defaultViewport");
    __publicField(this, "spread");
    __privateAdd(this, _portrait, false);
    __privateAdd(this, _left);
    __privateAdd(this, _right);
    __privateAdd(this, _center);
    __privateAdd(this, _side);
    __privateAdd(this, _zoom);
    __privateAdd(this, _scaleFactor, 1);
    __privateAdd(this, _totalScaleFactor, 1);
    __privateAdd(this, _scrollLocked, false);
    // Horizontal offset handed over by #showSpread for the next #render().
    __privateAdd(this, _pannedX, null);
    // Horizontal offset of the vertical scroll strip while the pan lock holds
    // it (see #syncScrollPanLock); null while the host scrolls on x itself.
    __privateAdd(this, _lockedPanX, null);
    // Pan handed in through `panX` before there was a page to apply it to.
    __privateAdd(this, _pendingPanX, null);
    __privateAdd(this, _isOverflowX, false);
    __privateAdd(this, _isOverflowY, false);
    __privateAdd(this, _preloadCache, /* @__PURE__ */ new Map());
    __privateAdd(this, _prerenderedSpreads, /* @__PURE__ */ new Map());
    __privateAdd(this, _spreadAccessTime, /* @__PURE__ */ new Map());
    __privateAdd(this, _spreadAccessTick, 0);
    // Counter for the keys stale cached spreads move to on a regroup.
    __privateAdd(this, _staleSpreads, 0);
    __privateAdd(this, _maxConcurrentPreloads, 1);
    __privateAdd(this, _numPrerenderedSpreads, 1);
    __privateAdd(this, _maxCachedSpreads, 2);
    __privateAdd(this, _overlayers, /* @__PURE__ */ new Map());
    __privateAdd(this, _pageColors, {});
    __privateAdd(this, _preloadQueue, []);
    __privateAdd(this, _activePreloads, 0);
    // Scroll mode fields
    __privateAdd(this, _scrollMode, false);
    __privateAdd(this, _scrollHorizontal, false);
    __privateAdd(this, _scrollPages, []);
    // Pages whose placeholder is in the DOM: the ones near the viewport, plus
    // any still loading or loaded (detaching an iframe would unload it).
    __privateAdd(this, _scrollMounted, /* @__PURE__ */ new Set());
    __privateAdd(this, _scrollLayout, layoutScrollPages({ sizes: [], gap: 0, overlap: 0 }));
    __privateAdd(this, _scrollContainer, null);
    __privateAdd(this, _scrollLoadGen, /* @__PURE__ */ new Map());
    // Live rendered-canvas cap. Each PDF page canvas is sized to the on-screen
    // page box × devicePixelRatio (~7 MB at dpr 3), so this is the dominant
    // memory ceiling — keep it just above the visible window plus preload lead.
    __privateAdd(this, _scrollMaxLoaded, 12);
    // Cap on concurrent page loads. A fast fling crosses many pages; without a
    // bound it would start a full-resolution render for every one, thrashing the
    // main thread and spiking memory. Nearest-to-viewport pages load first.
    __privateAdd(this, _scrollMaxConcurrent, 3);
    __privateAdd(this, _scrollLoadingCount, 0);
    __privateAdd(this, _scrollIdleTimer, null);
    __privateAdd(this, _scrollCurrentIndex, -1);
    // True while the host is actively scrolling. Pages load interactive only
    // when idle so a page that finishes loading mid-scroll can't flip its iframe
    // interactive and let its own pointer handlers hijack the native scroll.
    __privateAdd(this, _scrolling, false);
    // True while a pinch gesture is live. Suppresses page load/eviction so the
    // placeholder layout (and thus scrollTop) can't drift mid-pinch, which would
    // make the live preview and the committed zoom land in different places.
    __privateAdd(this, _pinching, false);
    // On-screen rect of the page under the viewport centre, captured from the
    // live (still-transformed) preview at pinch end ({ index, top, left }). The
    // commit re-render scrolls that page back to this exact rect, so the zoom
    // lands where the preview showed it. Using the real getBoundingClientRect
    // (not fraction maths) sidesteps gap/page-boundary and header-offset errors.
    __privateAdd(this, _pinchAnchor, null);
    __privateAdd(this, _handleScrollEvent, () => {
      __privateMethod(this, _FixedLayout_instances, updateScrollWindow_fn).call(this);
      __privateSet(this, _scrolling, true);
      __privateMethod(this, _FixedLayout_instances, setScrollIframeInteraction_fn).call(this, false);
      if (__privateGet(this, _scrollIdleTimer)) clearTimeout(__privateGet(this, _scrollIdleTimer));
      __privateSet(this, _scrollIdleTimer, setTimeout(() => {
        __privateSet(this, _scrolling, false);
        __privateMethod(this, _FixedLayout_instances, setScrollIframeInteraction_fn).call(this, true);
        __privateMethod(this, _FixedLayout_instances, reportScrollLocation_fn).call(this);
      }, 150));
    });
    __privateAdd(this, _handleScrollWheel, (e) => {
      const delta = computeScrollWheelDelta({
        deltaX: e.deltaX,
        deltaY: e.deltaY,
        ctrlKey: e.ctrlKey,
        horizontal: __privateGet(this, _scrollHorizontal),
        rtl: this.rtl,
        verticalOverflow: this.scrollHeight > this.clientHeight + 1
      });
      if (!delta) return;
      e.preventDefault();
      this.scrollBy({ left: delta.left, behavior: "auto" });
    });
    const sheet = new CSSStyleSheet();
    __privateGet(this, _root).adoptedStyleSheets = [sheet];
    sheet.replaceSync(`:host {
            width: 100%;
            height: 100%;
            display: flex;
            justify-content: flex-start;
            align-items: center;
            overflow: auto;
        }
        @supports (justify-content: safe center) {
          :host {
            justify-content: safe center;
          }
        }
        :host([flow="scrolled"]) {
            display: block;
            overflow-y: auto;
            /* auto (not hidden) so a zoomed page wider than the viewport can be
               panned horizontally; collapses to no scrollbar when pages fit. */
            overflow-x: auto;
            /* Keep one-finger pan (native scroll) but reserve two-finger
               gestures for JS so a pinch is delivered instead of triggering the
               browser's own pinch-zoom or being swallowed by the scroller. */
            touch-action: pan-x pan-y;
        }
        :host([flow="scrolled"]) .scroll-page {
            touch-action: pan-x pan-y;
        }
        /* Horizontal pan lock: the finger only moves the page up and down, so a
           zoomed-in page panned to hide its wide side margins can't drift back
           out of alignment with every slightly-diagonal swipe (#5976). Two
           fingers stay unlisted, so pinch is still delivered to JS. Exempt
           horizontal scroll flow, where x is the reading axis and locking it
           would strand the reader. */
        :host([lock-pan-x]:not([flow="scrolled"][scroll-direction="horizontal"])),
        :host([lock-pan-x]:not([flow="scrolled"][scroll-direction="horizontal"])) .scroll-page {
            touch-action: pan-y;
        }
        /* iOS ignores touch-action for a swipe that lands while the strip is
           still coasting from the previous fling, so vertical scroll flow drops
           the horizontal scroll range altogether: the host stops scrolling on
           x and the strip is shifted by the offset the reader panned to
           (#6407). */
        :host([lock-pan-x][flow="scrolled"]:not([scroll-direction="horizontal"])) {
            overflow-x: hidden;
        }
        :host([lock-pan-x][flow="scrolled"]:not([scroll-direction="horizontal"])) .scroll-container {
            translate: var(--locked-pan-x, 0px) 0;
        }
        /* Sized by #layoutScrollPages to the whole strip, but at least the
           viewport so unzoomed pages stay centered. */
        :host([flow="scrolled"]) .scroll-container {
            position: relative;
            min-height: 100%;
            min-width: 100%;
            background-color: var(--scroll-bg-color);
            background-opacity: var(--scroll-bg-opacity);
        }
        /* Placed along the strip by #placeScrollPage and centered across it.
           In Webtoon Mode each page overlaps the previous one to hide the
           anti-aliased seam (readest#6484); later pages come later in the DOM,
           so they paint on top. The pages are not clipped (no overflow:
           hidden) because the clip of a box on a fractional device pixel is
           itself anti-aliased and reopens the seam. */
        :host([flow="scrolled"]) .scroll-page {
            position: absolute;
            left: 0;
            right: 0;
            margin-inline: auto;
        }
        :host([flow="scrolled"]) .scroll-page iframe {
            pointer-events: none;
        }
        :host([flow="scrolled"][scroll-direction="horizontal"]) .scroll-page {
            left: auto;
            right: auto;
            top: 0;
            bottom: 0;
            margin: auto 0;
        }`);
    __privateGet(this, _observer).observe(this);
  }
  attributeChangedCallback(name, _, value) {
    switch (name) {
      case "zoom":
        __privateSet(this, _zoom, value !== "fit-width" && value !== "fit-page" ? parseFloat(value) : value);
        __privateMethod(this, _FixedLayout_instances, render_fn).call(this);
        break;
      case "scale-factor":
        __privateSet(this, _scaleFactor, parseFloat(value) / 100);
        __privateMethod(this, _FixedLayout_instances, render_fn).call(this);
        break;
      case "spread":
        __privateMethod(this, _FixedLayout_instances, respread_fn).call(this, value);
        break;
      case "flow":
        if (value === "scrolled" && !__privateGet(this, _scrollMode)) {
          const savedIndex = this.index;
          __privateSet(this, _scrollMode, true);
          if (this.book) __privateMethod(this, _FixedLayout_instances, initScrollMode_fn).call(this, savedIndex);
        } else if (value !== "scrolled" && __privateGet(this, _scrollMode)) {
          __privateMethod(this, _FixedLayout_instances, destroyScrollMode_fn).call(this);
          __privateSet(this, _scrollMode, false);
          __privateMethod(this, _FixedLayout_instances, render_fn).call(this);
        }
        break;
      case "scroll-gap":
        if (__privateGet(this, _scrollContainer)) __privateMethod(this, _FixedLayout_instances, renderScrollMode_fn).call(this);
        break;
      case "lock-pan-x":
        __privateMethod(this, _FixedLayout_instances, applyPanLockToFrames_fn).call(this);
        __privateMethod(this, _FixedLayout_instances, syncScrollPanLock_fn).call(this);
        break;
      case "scroll-direction": {
        const horizontal = value === "horizontal";
        if (horizontal === __privateGet(this, _scrollHorizontal)) break;
        __privateSet(this, _scrollHorizontal, horizontal);
        if (__privateGet(this, _scrollMode) && this.book) {
          const savedIndex = __privateGet(this, _scrollCurrentIndex) >= 0 ? __privateGet(this, _scrollCurrentIndex) : 0;
          __privateMethod(this, _FixedLayout_instances, destroyScrollMode_fn).call(this, false);
          __privateMethod(this, _FixedLayout_instances, initScrollMode_fn).call(this, savedIndex);
        }
        break;
      }
    }
  }
  // Horizontal pan as a fraction of the page's horizontal overflow (0 = left
  // edge, 1 = right edge), so the reader can store where a zoomed page was
  // panned under the lock and restore it when the book is reopened. null when
  // nothing overflows sideways, or in horizontal scroll flow, where x is the
  // reading axis. Setting it before the first page renders defers it until
  // there is one.
  get panX() {
    if (__privateGet(this, _scrollMode) && __privateGet(this, _scrollHorizontal)) return null;
    const max = __privateMethod(this, _FixedLayout_instances, maxPanX_fn).call(this);
    if (!(max > 0)) return null;
    return (__privateGet(this, _lockedPanX) ?? this.scrollLeft) / max;
  }
  set panX(fraction) {
    __privateSet(this, _pendingPanX, fraction);
    __privateMethod(this, _FixedLayout_instances, applyPendingPanX_fn).call(this);
  }
  open(book) {
    var _a;
    this.book = book;
    this.defaultViewport = (_a = book.rendition) == null ? void 0 : _a.viewport;
    this.rtl = book.dir === "rtl";
    __privateMethod(this, _FixedLayout_instances, spread_fn).call(this);
    if (__privateGet(this, _scrollMode)) __privateMethod(this, _FixedLayout_instances, initScrollMode_fn).call(this);
  }
  get columnCount() {
    return computeSpreadColumnCount({
      center: !!__privateGet(this, _center),
      portrait: __privateGet(this, _portrait),
      scrolled: __privateGet(this, _scrollMode),
      leftBlank: !__privateGet(this, _left) || !!__privateGet(this, _left).blank,
      rightBlank: !__privateGet(this, _right) || !!__privateGet(this, _right).blank
    });
  }
  get index() {
    if (__privateGet(this, _scrollMode)) return __privateGet(this, _scrollCurrentIndex) >= 0 ? __privateGet(this, _scrollCurrentIndex) : __privateMethod(this, _FixedLayout_instances, getScrollIndex_fn).call(this);
    if (__privateGet(this, _index) < 0 || !__privateGet(this, _spreads)) return -1;
    const spread = __privateGet(this, _spreads)[__privateGet(this, _index)];
    if (!spread) return -1;
    const section = spread.center ?? (__privateGet(this, _side) === "left" ? spread.left ?? spread.right : spread.right ?? spread.left);
    return this.book.sections.indexOf(section);
  }
  get pageColors() {
    return __privateGet(this, _pageColors);
  }
  // The reader assigns this on every page load; re-rendering for colors that
  // did not change re-rendered every loaded page and rebuilt its overlayer.
  set pageColors(value) {
    const old = __privateGet(this, _pageColors);
    if ((old == null ? void 0 : old.background) === (value == null ? void 0 : value.background) && (old == null ? void 0 : old.foreground) === (value == null ? void 0 : value.foreground) && (old == null ? void 0 : old.keepImages) === (value == null ? void 0 : value.keepImages)) return;
    __privateSet(this, _pageColors, value);
    __privateMethod(this, _FixedLayout_instances, render_fn).call(this);
  }
  get scrolled() {
    return __privateGet(this, _scrollMode);
  }
  get scrollLocked() {
    return __privateGet(this, _scrollLocked);
  }
  set scrollLocked(value) {
    __privateSet(this, _scrollLocked, value);
  }
  get isOverflowX() {
    return __privateGet(this, _isOverflowX);
  }
  get isOverflowY() {
    return __privateGet(this, _isOverflowY);
  }
  get atStart() {
    if (__privateGet(this, _scrollMode)) return __privateMethod(this, _FixedLayout_instances, scrollProgression_fn).call(this) <= 0;
    return __privateGet(this, _index) <= 0;
  }
  get atEnd() {
    if (__privateGet(this, _scrollMode))
      return __privateMethod(this, _FixedLayout_instances, scrollProgression_fn).call(this) + __privateMethod(this, _FixedLayout_instances, scrollViewLength_fn).call(this) >= __privateMethod(this, _FixedLayout_instances, scrollTotalLength_fn).call(this) - 2;
    return __privateGet(this, _index) >= __privateGet(this, _spreads).length - 1;
  }
  // Names the page next()/prev() would show, as the paginator does. A
  // portrait view shows one side of a spread at a time, so the side is part
  // of the key there.
  getPageTurnKey(delta = 0) {
    const spreads = __privateGet(this, _spreads);
    if (__privateGet(this, _scrollMode) || !(spreads == null ? void 0 : spreads[__privateGet(this, _index)]) || Math.abs(delta) > 1) return null;
    const key = (index2, side2) => __privateGet(this, _portrait) && !spreads[index2].center ? `${index2}:${side2}` : `${index2}`;
    if (!delta) return key(__privateGet(this, _index), __privateGet(this, _side));
    const toward = delta > 0 !== this.rtl ? "right" : "left";
    const frame = toward === "left" ? __privateGet(this, _left) : __privateGet(this, _right);
    if (__privateGet(this, _portrait) && !__privateGet(this, _center) && __privateGet(this, _side) !== toward && frame && !frame.blank)
      return key(__privateGet(this, _index), toward);
    const index = __privateGet(this, _index) + delta;
    const spread = spreads[index];
    if (!spread) return null;
    const side = spread.center ? "center" : !spread.left ? "right" : !spread.right ? "left" : toward === "left" ? "right" : "left";
    return key(index, side);
  }
  // The section on screen, as the paginator names its primary view: callers
  // pick the document they act on from getContents() by it. Without it they
  // fell back to the first frame, the left page of a two-page spread.
  get primaryIndex() {
    return this.index;
  }
  getSpreadOf(section) {
    const spreads = __privateGet(this, _spreads);
    for (let index = 0; index < spreads.length; index++) {
      const { left, right, center } = spreads[index];
      if (left === section) return { index, side: "left" };
      if (right === section) return { index, side: "right" };
      if (center === section) return { index, side: "center" };
    }
  }
  async goToSpread(index, side, reason) {
    var _a, _b, _c, _d, _e, _f;
    if (index < 0 || index > __privateGet(this, _spreads).length - 1) return;
    if (index === __privateGet(this, _index)) {
      const moved = side != null && side !== __privateGet(this, _side);
      if (moved) __privateSet(this, _side, side);
      __privateMethod(this, _FixedLayout_instances, render_fn).call(this, side);
      if (moved) __privateMethod(this, _FixedLayout_instances, reportLocation_fn).call(this, reason);
      return;
    }
    if (__privateGet(this, _index) >= 0) __privateMethod(this, _FixedLayout_instances, touchSpread_fn).call(this, `spread-${__privateGet(this, _index)}`);
    __privateSet(this, _index, index);
    const spread = __privateGet(this, _spreads)[index];
    const cacheKey = `spread-${index}`;
    const cached = __privateGet(this, _preloadCache).get(cacheKey);
    if (cached && cached !== "loading") {
      if (cached.center) {
        const sectionIndex = this.book.sections.indexOf(spread.center);
        await __privateMethod(this, _FixedLayout_instances, showSpread_fn).call(this, { center: { index: sectionIndex, src: cached.center }, spreadIndex: index, side });
      } else {
        const indexL = this.book.sections.indexOf(spread.left);
        const indexR = this.book.sections.indexOf(spread.right);
        const left = { index: indexL, src: cached.left };
        const right = { index: indexR, src: cached.right };
        await __privateMethod(this, _FixedLayout_instances, showSpread_fn).call(this, { left, right, side, spreadIndex: index });
      }
    } else {
      if (spread.center) {
        const sectionIndex = this.book.sections.indexOf(spread.center);
        const src = await ((_b = (_a = spread.center) == null ? void 0 : _a.load) == null ? void 0 : _b.call(_a));
        __privateMethod(this, _FixedLayout_instances, regroup_fn).call(this);
        if (__privateGet(this, _spreads)[index] !== spread) return __privateMethod(this, _FixedLayout_instances, goToPageOf_fn).call(this, spread, side, reason);
        await __privateMethod(this, _FixedLayout_instances, showSpread_fn).call(this, { center: { index: sectionIndex, src }, spreadIndex: index, side });
      } else {
        const indexL = this.book.sections.indexOf(spread.left);
        const indexR = this.book.sections.indexOf(spread.right);
        const srcL = await ((_d = (_c = spread.left) == null ? void 0 : _c.load) == null ? void 0 : _d.call(_c));
        const srcR = await ((_f = (_e = spread.right) == null ? void 0 : _e.load) == null ? void 0 : _f.call(_e));
        __privateMethod(this, _FixedLayout_instances, regroup_fn).call(this);
        if (__privateGet(this, _spreads)[index] !== spread) return __privateMethod(this, _FixedLayout_instances, goToPageOf_fn).call(this, spread, side, reason);
        const left = { index: indexL, src: srcL };
        const right = { index: indexR, src: srcR };
        await __privateMethod(this, _FixedLayout_instances, showSpread_fn).call(this, { left, right, side, spreadIndex: index });
      }
    }
    __privateMethod(this, _FixedLayout_instances, reportLocation_fn).call(this, reason);
    __privateMethod(this, _FixedLayout_instances, preloadNextSpreads_fn).call(this);
  }
  async select(target) {
    await this.goTo(target);
  }
  async goTo(target) {
    const resolved = await target;
    if (__privateGet(this, _scrollMode)) {
      if (__privateGet(this, _scrollPages)[resolved.index]) __privateMethod(this, _FixedLayout_instances, scrollToPage_fn).call(this, resolved.index);
      return;
    }
    const { book } = this;
    const section = book.sections[resolved.index];
    if (!section) return;
    const { index, side } = this.getSpreadOf(section);
    await this.goToSpread(index, side);
  }
  async next(distance) {
    if (__privateGet(this, _scrollMode)) {
      if (__privateGet(this, _scrollHorizontal)) {
        const d = distance || this.clientWidth;
        this.scrollBy({ left: this.rtl ? -d : d, behavior: "smooth" });
      } else {
        this.scrollBy({ top: distance || this.clientHeight, behavior: "smooth" });
      }
      return;
    }
    const s = this.rtl ? __privateMethod(this, _FixedLayout_instances, goLeft_fn).call(this) : __privateMethod(this, _FixedLayout_instances, goRight_fn).call(this);
    if (!s) return this.goToSpread(__privateGet(this, _index) + 1, this.rtl ? "right" : "left", "page");
  }
  async prev(distance) {
    if (__privateGet(this, _scrollMode)) {
      if (__privateGet(this, _scrollHorizontal)) {
        const d = distance || this.clientWidth;
        this.scrollBy({ left: this.rtl ? d : -d, behavior: "smooth" });
      } else {
        this.scrollBy({ top: -(distance || this.clientHeight), behavior: "smooth" });
      }
      return;
    }
    const s = this.rtl ? __privateMethod(this, _FixedLayout_instances, goRight_fn).call(this) : __privateMethod(this, _FixedLayout_instances, goLeft_fn).call(this);
    if (!s) return this.goToSpread(__privateGet(this, _index) - 1, this.rtl ? "left" : "right", "page");
  }
  nextSection() {
    if (!__privateGet(this, _scrollMode)) return;
    const currentIndex = __privateMethod(this, _FixedLayout_instances, getScrollIndex_fn).call(this);
    __privateMethod(this, _FixedLayout_instances, scrollToPage_fn).call(this, Math.min(currentIndex + 1, __privateGet(this, _scrollPages).length - 1), "smooth");
  }
  prevSection() {
    if (!__privateGet(this, _scrollMode)) return;
    const currentIndex = __privateMethod(this, _FixedLayout_instances, getScrollIndex_fn).call(this);
    __privateMethod(this, _FixedLayout_instances, scrollToPage_fn).call(this, Math.max(currentIndex - 1, 0), "smooth");
  }
  async pan(dx, dy) {
    if (__privateGet(this, _scrollMode)) {
      this.scrollBy({ top: dy, left: dx, behavior: "auto" });
      return;
    }
    if (__privateGet(this, _scrollLocked)) return;
    __privateSet(this, _scrollLocked, true);
    const transform = (frame) => {
      let { element, iframe } = frame;
      if (!iframe || !element) return;
      const scrollableContainer = element.parentNode.host;
      scrollableContainer.scrollLeft += dx;
      scrollableContainer.scrollTop += dy;
    };
    transform(__privateGet(this, _center) ?? __privateGet(this, _right) ?? {});
    __privateSet(this, _scrollLocked, false);
  }
  getContents() {
    if (__privateGet(this, _scrollMode)) {
      return __privateGet(this, _scrollPages).filter((p) => {
        var _a;
        return p.state === "loaded" && ((_a = p.frame) == null ? void 0 : _a.iframe);
      }).map((p) => ({
        doc: p.frame.iframe.contentDocument,
        index: p.index,
        overlayer: __privateGet(this, _overlayers).get(p.index)
      }));
    }
    return Array.from(__privateGet(this, _root).querySelectorAll("iframe")).filter((frame) => {
      const parent = frame.parentElement;
      return parent && parent.style.visibility !== "hidden";
    }).map((frame) => {
      const index = frame.dataset.sectionIndex != null ? parseInt(frame.dataset.sectionIndex) : void 0;
      return {
        doc: frame.contentDocument,
        index,
        overlayer: index != null ? __privateGet(this, _overlayers).get(index) : void 0
      };
    });
  }
  pinchZoom(ratio) {
    if (__privateGet(this, _scrollMode)) {
      if (__privateGet(this, _scrollContainer)) {
        __privateSet(this, _pinching, true);
        const { transform, transformOrigin } = computeScrollPinchTransform({
          ratio,
          scrollLeft: __privateGet(this, _scrollHorizontal) && this.rtl ? this.scrollWidth - this.clientWidth + this.scrollLeft : this.scrollLeft + (__privateGet(this, _lockedPanX) ?? 0),
          scrollTop: this.scrollTop,
          viewportWidth: this.clientWidth,
          viewportHeight: this.clientHeight
        });
        __privateGet(this, _scrollContainer).style.transformOrigin = transformOrigin;
        __privateGet(this, _scrollContainer).style.transform = transform;
      }
      return;
    }
    const elements = __privateMethod(this, _FixedLayout_instances, shownFrames_fn).call(this).map((frame) => frame.element).filter((element) => element.style.visibility !== "hidden");
    if (!elements.length) return;
    const left = Math.min(...elements.map((el) => el.offsetLeft));
    const top = Math.min(...elements.map((el) => el.offsetTop));
    const right = Math.max(...elements.map((el) => el.offsetLeft + el.offsetWidth));
    const bottom = Math.max(...elements.map((el) => el.offsetTop + el.offsetHeight));
    for (const element of elements) {
      element.style.transform = `scale(${ratio})`;
      element.style.transformOrigin = `${(left + right) / 2 - element.offsetLeft}px ${(top + bottom) / 2 - element.offsetTop}px`;
    }
  }
  pinchEnd() {
    if (__privateGet(this, _scrollMode)) {
      __privateSet(this, _pinching, false);
      if (__privateGet(this, _scrollContainer)) {
        __privateSet(this, _pinchAnchor, __privateMethod(this, _FixedLayout_instances, captureCenterPageRect_fn).call(this));
        __privateGet(this, _scrollContainer).style.removeProperty("transform");
        __privateGet(this, _scrollContainer).style.removeProperty("transform-origin");
      }
      return;
    }
    const shown = __privateMethod(this, _FixedLayout_instances, shownFrames_fn).call(this)[0];
    if (shown) {
      const b = shown.element.getBoundingClientRect();
      __privateSet(this, _pinchAnchor, { top: b.top, left: b.left });
    }
    for (const frame of [__privateGet(this, _center), __privateGet(this, _left), __privateGet(this, _right)]) {
      if (!(frame == null ? void 0 : frame.element)) continue;
      frame.element.style.removeProperty("transform");
      frame.element.style.removeProperty("transform-origin");
    }
  }
  get size() {
    return __privateGet(this, _scrollMode) && __privateGet(this, _scrollHorizontal) ? this.clientWidth : this.clientHeight;
  }
  get viewSize() {
    return __privateGet(this, _scrollMode) ? __privateMethod(this, _FixedLayout_instances, scrollTotalLength_fn).call(this) : this.clientHeight;
  }
  get start() {
    return __privateGet(this, _scrollMode) ? __privateMethod(this, _FixedLayout_instances, scrollProgression_fn).call(this) : 0;
  }
  get end() {
    return __privateGet(this, _scrollMode) ? __privateMethod(this, _FixedLayout_instances, scrollProgression_fn).call(this) + __privateMethod(this, _FixedLayout_instances, scrollViewLength_fn).call(this) : this.clientHeight;
  }
  get page() {
    if (__privateGet(this, _scrollMode)) return __privateGet(this, _scrollCurrentIndex) >= 0 ? __privateGet(this, _scrollCurrentIndex) : __privateMethod(this, _FixedLayout_instances, getScrollIndex_fn).call(this);
    return __privateGet(this, _index);
  }
  get pages() {
    var _a;
    if (__privateGet(this, _scrollMode)) return __privateGet(this, _scrollPages).length;
    return ((_a = __privateGet(this, _spreads)) == null ? void 0 : _a.length) ?? 0;
  }
  get containerPosition() {
    return __privateGet(this, _scrollMode) ? __privateMethod(this, _FixedLayout_instances, scrollProgression_fn).call(this) : 0;
  }
  set containerPosition(newVal) {
    if (!__privateGet(this, _scrollMode)) return;
    if (__privateGet(this, _scrollHorizontal)) this.scrollLeft = this.rtl ? -newVal : newVal;
    else this.scrollTop = newVal;
  }
  get sideProp() {
    if (__privateGet(this, _scrollMode)) return __privateGet(this, _scrollHorizontal) ? "width" : "height";
    return "width";
  }
  destroy() {
    var _a, _b, _c, _d, _e;
    __privateGet(this, _observer).unobserve(this);
    if (__privateGet(this, _scrollMode)) {
      this.removeEventListener("scroll", __privateGet(this, _handleScrollEvent));
      this.removeEventListener("wheel", __privateGet(this, _handleScrollWheel));
      if (__privateGet(this, _scrollIdleTimer)) {
        clearTimeout(__privateGet(this, _scrollIdleTimer));
        __privateSet(this, _scrollIdleTimer, null);
      }
      for (const page of __privateGet(this, _scrollPages)) {
        __privateMethod(this, _FixedLayout_instances, teardownScrollPage_fn).call(this, page);
      }
      __privateSet(this, _scrollPages, []);
      __privateGet(this, _scrollMounted).clear();
      __privateGet(this, _scrollLoadGen).clear();
      __privateSet(this, _scrollLoadingCount, 0);
      if (__privateGet(this, _scrollContainer)) {
        __privateGet(this, _scrollContainer).remove();
        __privateSet(this, _scrollContainer, null);
      }
    }
    for (const frames of __privateGet(this, _prerenderedSpreads).values()) {
      if (frames.center) {
        (_a = frames.center.element) == null ? void 0 : _a.remove();
      } else {
        (_c = (_b = frames.left) == null ? void 0 : _b.element) == null ? void 0 : _c.remove();
        (_e = (_d = frames.right) == null ? void 0 : _d.element) == null ? void 0 : _e.remove();
      }
    }
    __privateGet(this, _prerenderedSpreads).clear();
    __privateGet(this, _preloadCache).clear();
    __privateGet(this, _spreadAccessTime).clear();
    __privateGet(this, _overlayers).clear();
  }
}
_root = new WeakMap();
_observer = new WeakMap();
_spreads = new WeakMap();
_index = new WeakMap();
_portrait = new WeakMap();
_left = new WeakMap();
_right = new WeakMap();
_center = new WeakMap();
_side = new WeakMap();
_zoom = new WeakMap();
_scaleFactor = new WeakMap();
_totalScaleFactor = new WeakMap();
_scrollLocked = new WeakMap();
_pannedX = new WeakMap();
_lockedPanX = new WeakMap();
_pendingPanX = new WeakMap();
_isOverflowX = new WeakMap();
_isOverflowY = new WeakMap();
_preloadCache = new WeakMap();
_prerenderedSpreads = new WeakMap();
_spreadAccessTime = new WeakMap();
_spreadAccessTick = new WeakMap();
_staleSpreads = new WeakMap();
_maxConcurrentPreloads = new WeakMap();
_numPrerenderedSpreads = new WeakMap();
_maxCachedSpreads = new WeakMap();
_overlayers = new WeakMap();
_pageColors = new WeakMap();
_preloadQueue = new WeakMap();
_activePreloads = new WeakMap();
_scrollMode = new WeakMap();
_scrollHorizontal = new WeakMap();
_scrollPages = new WeakMap();
_scrollMounted = new WeakMap();
_scrollLayout = new WeakMap();
_scrollContainer = new WeakMap();
_scrollLoadGen = new WeakMap();
_scrollMaxLoaded = new WeakMap();
_scrollMaxConcurrent = new WeakMap();
_scrollLoadingCount = new WeakMap();
_scrollIdleTimer = new WeakMap();
_scrollCurrentIndex = new WeakMap();
_scrolling = new WeakMap();
_pinching = new WeakMap();
_pinchAnchor = new WeakMap();
_FixedLayout_instances = new WeakSet();
captureCenterPageRect_fn = function() {
  const hostRect = this.getBoundingClientRect();
  const c = __privateGet(this, _scrollHorizontal) ? hostRect.left + this.clientWidth / 2 : hostRect.top + this.clientHeight / 2;
  for (const page of __privateGet(this, _scrollMounted)) {
    const rect = page.el.getBoundingClientRect();
    const lo = __privateGet(this, _scrollHorizontal) ? rect.left : rect.top;
    const hi = __privateGet(this, _scrollHorizontal) ? rect.right : rect.bottom;
    if (lo <= c && hi > c) {
      return { index: page.index, top: rect.top, left: rect.left };
    }
  }
  return null;
};
// Scroll so the captured page sits back at its pre-commit on-screen rect.
restorePinchAnchor_fn = function(anchor) {
  const page = __privateGet(this, _scrollPages)[anchor.index];
  if (!__privateGet(this, _scrollMounted).has(page)) return;
  const rect = page.el.getBoundingClientRect();
  const maxTop = Math.max(0, this.scrollHeight - this.clientHeight);
  const maxLeft = Math.max(0, this.scrollWidth - this.clientWidth);
  this.scrollTop = clamp(this.scrollTop + (rect.top - anchor.top), 0, maxTop);
  if (__privateGet(this, _lockedPanX) !== null)
    __privateMethod(this, _FixedLayout_instances, setLockedPanX_fn).call(this, __privateGet(this, _lockedPanX) + (rect.left - anchor.left));
  else this.scrollLeft = clamp(this.scrollLeft + (rect.left - anchor.left), 0, maxLeft);
};
getScrollModePageMetrics_fn = function() {
  const { starts, sizes } = __privateGet(this, _scrollLayout);
  return __privateGet(this, _scrollPages).map((page) => ({
    index: page.index,
    start: starts[page.index] ?? 0,
    size: sizes[page.index] ?? 0
  }));
};
captureScrollModeAnchor_fn = function() {
  if (!__privateGet(this, _scrollPages).length) return null;
  const fallbackIndex = __privateGet(this, _scrollCurrentIndex) >= 0 ? __privateGet(this, _scrollCurrentIndex) : __privateMethod(this, _FixedLayout_instances, getScrollIndex_fn).call(this);
  return captureScrollModeAnchor(
    __privateMethod(this, _FixedLayout_instances, getScrollModePageMetrics_fn).call(this),
    __privateMethod(this, _FixedLayout_instances, scrollProgression_fn).call(this),
    fallbackIndex
  );
};
restoreScrollModeAnchor_fn = function(anchor) {
  if (!anchor || !__privateGet(this, _scrollPages).length) return;
  const maxScrollPos = Math.max(0, __privateMethod(this, _FixedLayout_instances, scrollTotalLength_fn).call(this) - __privateMethod(this, _FixedLayout_instances, scrollViewLength_fn).call(this));
  const restoredPos = restoreScrollModeAnchor(
    __privateMethod(this, _FixedLayout_instances, getScrollModePageMetrics_fn).call(this),
    anchor,
    maxScrollPos
  );
  if (Math.abs(restoredPos - __privateMethod(this, _FixedLayout_instances, scrollProgression_fn).call(this)) > 0.5) {
    __privateMethod(this, _FixedLayout_instances, setScrollProgression_fn).call(this, restoredPos);
  }
  __privateSet(this, _scrollCurrentIndex, anchor.index);
};
// Length of the viewport along the scroll axis.
scrollViewLength_fn = function() {
  return __privateGet(this, _scrollHorizontal) ? this.clientWidth : this.clientHeight;
};
// Total scrollable length along the scroll axis.
scrollTotalLength_fn = function() {
  return __privateGet(this, _scrollHorizontal) ? this.scrollWidth : this.scrollHeight;
};
// Distance read from the book start along the reading direction, the
// coordinate space of the page layout. RTL horizontal reading starts at
// the right edge and progresses into negative scrollLeft.
scrollProgression_fn = function() {
  if (!__privateGet(this, _scrollHorizontal)) return this.scrollTop;
  return this.rtl ? -this.scrollLeft : this.scrollLeft;
};
setScrollProgression_fn = function(pos) {
  if (!__privateGet(this, _scrollHorizontal)) this.scrollTop = pos;
  else this.scrollLeft = this.rtl ? -pos : pos;
};
// `touch-action` doesn't cross an iframe boundary: a touch that lands on page
// content is governed by that document's own value, so the host's `pan-y`
// alone still leaves the page pannable sideways (#5976). Mirror the lock
// inside every frame, with the same horizontal-scroll-flow exemption the
// stylesheet makes.
applyPanLock_fn = function(doc) {
  if (!(doc == null ? void 0 : doc.documentElement)) return;
  const locked = this.hasAttribute("lock-pan-x") && !(this.getAttribute("flow") === "scrolled" && this.getAttribute("scroll-direction") === "horizontal");
  doc.documentElement.style.touchAction = locked ? "pan-y" : "";
};
applyPanLockToFrames_fn = function() {
  for (const iframe of __privateGet(this, _root).querySelectorAll("iframe"))
    __privateMethod(this, _FixedLayout_instances, applyPanLock_fn).call(this, iframe.contentDocument);
};
// Hand the horizontal offset between the host's scrollLeft and the strip's
// translate as the lock's overflow-x rule turns on or off, so the page
// stays where the reader panned it.
syncScrollPanLock_fn = function() {
  const locked = !!__privateGet(this, _scrollContainer) && !__privateGet(this, _scrollHorizontal) && this.hasAttribute("lock-pan-x");
  if (locked === (__privateGet(this, _lockedPanX) !== null)) return;
  if (locked) {
    __privateMethod(this, _FixedLayout_instances, setLockedPanX_fn).call(this, this.scrollLeft);
    this.scrollLeft = 0;
    __privateMethod(this, _FixedLayout_instances, applyPendingPanX_fn).call(this);
  } else {
    const x = __privateGet(this, _lockedPanX);
    __privateMethod(this, _FixedLayout_instances, clearLockedPanX_fn).call(this);
    this.scrollLeft = x;
  }
};
maxPanX_fn = function() {
  const width = __privateGet(this, _lockedPanX) !== null ? __privateGet(this, _scrollContainer).offsetWidth : this.scrollWidth;
  return width - this.clientWidth;
};
applyPendingPanX_fn = function() {
  var _a;
  if (__privateGet(this, _pendingPanX) === null) return;
  if (__privateGet(this, _scrollMode) ? !((_a = __privateGet(this, _scrollContainer)) == null ? void 0 : _a.offsetWidth) : !__privateGet(this, _side)) return;
  const fraction = __privateGet(this, _pendingPanX);
  __privateSet(this, _pendingPanX, null);
  if (__privateGet(this, _scrollMode) && __privateGet(this, _scrollHorizontal)) return;
  const max = __privateMethod(this, _FixedLayout_instances, maxPanX_fn).call(this);
  if (!(max > 0)) return;
  if (__privateGet(this, _lockedPanX) !== null) __privateMethod(this, _FixedLayout_instances, setLockedPanX_fn).call(this, fraction * max);
  else this.scrollLeft = fraction * max;
};
setLockedPanX_fn = function(x) {
  const max = Math.max(0, __privateGet(this, _scrollContainer).offsetWidth - this.clientWidth);
  __privateSet(this, _lockedPanX, clamp(x, 0, max));
  this.style.setProperty("--locked-pan-x", `${-__privateGet(this, _lockedPanX)}px`);
};
clearLockedPanX_fn = function() {
  __privateSet(this, _lockedPanX, null);
  this.style.removeProperty("--locked-pan-x");
};
createFrame_fn = async function({ index, src: srcOption, detached = false }) {
  const srcOptionIsString = typeof srcOption === "string";
  const src = srcOptionIsString ? srcOption : srcOption == null ? void 0 : srcOption.src;
  const data = srcOptionIsString ? null : srcOption == null ? void 0 : srcOption.data;
  const onZoom = srcOptionIsString ? null : srcOption == null ? void 0 : srcOption.onZoom;
  const element = document.createElement("div");
  element.setAttribute("dir", "ltr");
  element.style.position = "relative";
  const iframe = document.createElement("iframe");
  element.append(iframe);
  Object.assign(iframe.style, {
    border: "0",
    display: "none",
    overflow: "hidden"
  });
  iframe.setAttribute("sandbox", "allow-same-origin allow-scripts");
  iframe.setAttribute("scrolling", "no");
  iframe.setAttribute("part", "filter");
  __privateGet(this, _root).append(element);
  if (detached) {
    Object.assign(element.style, {
      position: "absolute",
      visibility: "hidden",
      pointerEvents: "none"
    });
  }
  if (!src) return { blank: true, element, iframe };
  return new Promise((resolve) => {
    iframe.addEventListener("load", async () => {
      const doc = iframe.contentDocument;
      __privateMethod(this, _FixedLayout_instances, applyPanLock_fn).call(this, doc);
      iframe.dataset.sectionIndex = index;
      this.dispatchEvent(new CustomEvent("load", { detail: { doc, index } }));
      const { width, height } = await getViewport(doc, this.defaultViewport);
      resolve({
        element,
        iframe,
        width: parseFloat(width),
        height: parseFloat(height),
        onZoom,
        detached
      });
    }, { once: true });
    if (data) {
      iframe.srcdoc = data;
    } else {
      iframe.src = src;
    }
  });
};
render_fn = function(side = __privateGet(this, _side), pageTurn = false) {
  if (__privateGet(this, _scrollMode)) {
    __privateMethod(this, _FixedLayout_instances, renderScrollMode_fn).call(this);
    return [];
  }
  if (!side) return [];
  const pannedX = __privateGet(this, _pannedX) ?? this.scrollLeft;
  __privateSet(this, _pannedX, null);
  const left = __privateGet(this, _left) ?? {};
  const right = __privateGet(this, _center) ?? __privateGet(this, _right) ?? {};
  const target = side === "left" ? left : right;
  const { width, height } = this.getBoundingClientRect();
  const portrait = this.spread !== "both" && this.spread !== "portrait" && height > width * 1.2;
  __privateSet(this, _portrait, portrait);
  const blankWidth = left.width ?? right.width ?? 0;
  const blankHeight = left.height ?? right.height ?? 0;
  const { clientWidth, clientHeight } = this;
  let scale = typeof __privateGet(this, _zoom) === "number" && !isNaN(__privateGet(this, _zoom)) ? __privateGet(this, _zoom) : (__privateGet(this, _zoom) === "fit-width" ? portrait || __privateGet(this, _center) ? clientWidth / (target.width ?? blankWidth) : clientWidth / ((left.width ?? blankWidth) + (right.width ?? blankWidth)) : portrait || __privateGet(this, _center) ? Math.min(
    clientWidth / (target.width ?? blankWidth),
    clientHeight / (target.height ?? blankHeight)
  ) : Math.min(
    clientWidth / ((left.width ?? blankWidth) + (right.width ?? blankWidth)),
    clientHeight / Math.max(
      left.height ?? blankHeight,
      right.height ?? blankHeight
    )
  )) || 1;
  scale *= __privateGet(this, _scaleFactor);
  __privateSet(this, _totalScaleFactor, scale);
  const renderPromises = [];
  const transform = ({ frame, styles }) => {
    var _a;
    let { element, iframe, width: width2, height: height2, blank, onZoom } = frame;
    if (!iframe) return;
    if (onZoom) {
      const p = onZoom({ doc: frame.iframe.contentDocument, scale, pageColors: __privateGet(this, _pageColors) });
      if (p == null ? void 0 : p.then) {
        const refreshed = p.then(() => __privateMethod(this, _FixedLayout_instances, refreshOverlayerForFrame_fn).call(this, frame));
        renderPromises.push(refreshed);
      }
    }
    const iframeScale = onZoom ? scale : 1;
    const zoomedOut = __privateGet(this, _scaleFactor) < 1;
    const centerInBox = zoomedOut && onZoom;
    Object.assign(iframe.style, {
      width: `${width2 * iframeScale}px`,
      height: `${height2 * iframeScale}px`,
      transform: onZoom ? "none" : `scale(${scale})`,
      transformOrigin: "top left",
      display: blank ? "none" : "block"
    });
    Object.assign(element.style, {
      width: `${(width2 ?? blankWidth) * scale}px`,
      height: `${(height2 ?? blankHeight) * scale}px`,
      flexShrink: "0",
      display: centerInBox ? "flex" : "block",
      marginBlock: centerInBox ? void 0 : "auto",
      alignItems: centerInBox ? "center" : void 0,
      justifyContent: centerInBox ? "center" : void 0,
      ...styles
    });
    if (portrait && frame !== target) {
      element.style.display = "none";
    }
    const sectionIndex = iframe.dataset.sectionIndex != null ? parseInt(iframe.dataset.sectionIndex) : void 0;
    if (sectionIndex != null) {
      const overlayer = __privateGet(this, _overlayers).get(sectionIndex);
      if (overlayer) {
        Object.assign(overlayer.element.style, {
          position: "absolute",
          top: "0",
          left: "0",
          width: `${(width2 ?? blankWidth) * scale}px`,
          height: `${(height2 ?? blankHeight) * scale}px`
        });
        applyOverlayerViewBox({
          onZoom,
          width: width2 ?? blankWidth,
          height: height2 ?? blankHeight
        }, overlayer);
        overlayer.redraw();
      }
    }
    const container = (_a = element.parentNode) == null ? void 0 : _a.host;
    if (!container) return;
    const containerWidth = container.clientWidth;
    const containerHeight = container.clientHeight;
    const { scrollLeft, scrollTop } = computePaginatedScroll({
      elementWidth: element.clientWidth,
      containerWidth,
      scrollTop: container.scrollTop,
      scrollLeft: pannedX,
      pageTurn,
      lockPanX: this.hasAttribute("lock-pan-x")
    });
    container.scrollLeft = scrollLeft;
    container.scrollTop = scrollTop;
    return {
      width: element.clientWidth,
      height: element.clientHeight,
      containerWidth,
      containerHeight
    };
  };
  if (__privateGet(this, _center)) {
    const dimensions = transform({ frame: __privateGet(this, _center), styles: { marginInline: "auto" } });
    if (!dimensions) return renderPromises;
    const { width: width2, height: height2, containerWidth, containerHeight } = dimensions;
    __privateSet(this, _isOverflowX, width2 > containerWidth);
    __privateSet(this, _isOverflowY, height2 > containerHeight);
  } else {
    const overlapX = computeSpreadSpineOverlap({
      portrait,
      leftBlank: Boolean(left.blank),
      rightBlank: Boolean(right.blank),
      devicePixelRatio: window.devicePixelRatio || 1
    });
    const margins = computeSpreadInlineMargins(portrait);
    const leftDimensions = transform({ frame: left, styles: margins.left });
    const rightDimensions = transform({ frame: right, styles: {
      ...margins.right,
      transform: overlapX ? `translateX(${overlapX}px)` : "none"
    } });
    if (!leftDimensions || !rightDimensions) return renderPromises;
    const { width: leftWidth, height: leftHeight, containerWidth, containerHeight } = leftDimensions;
    const { width: rightWidth, height: rightHeight } = rightDimensions;
    __privateSet(this, _isOverflowX, leftWidth + rightWidth > containerWidth);
    __privateSet(this, _isOverflowY, Math.max(leftHeight, rightHeight) > containerHeight);
  }
  if (__privateGet(this, _pinchAnchor)) {
    const frame = __privateMethod(this, _FixedLayout_instances, shownFrames_fn).call(this)[0];
    if (frame) {
      const b = frame.element.getBoundingClientRect();
      const maxTop = Math.max(0, this.scrollHeight - this.clientHeight);
      const maxLeft = Math.max(0, this.scrollWidth - this.clientWidth);
      this.scrollTop = clamp(this.scrollTop + (b.top - __privateGet(this, _pinchAnchor).top), 0, maxTop);
      this.scrollLeft = clamp(this.scrollLeft + (b.left - __privateGet(this, _pinchAnchor).left), 0, maxLeft);
    }
    __privateSet(this, _pinchAnchor, null);
  }
  __privateMethod(this, _FixedLayout_instances, applyPendingPanX_fn).call(this);
  return renderPromises;
};
showSpread_fn = async function({ left, right, center, side, spreadIndex }) {
  var _a, _b, _c, _d, _e;
  __privateSet(this, _left, null);
  __privateSet(this, _right, null);
  __privateSet(this, _center, null);
  const cacheKey = spreadIndex !== void 0 ? `spread-${spreadIndex}` : null;
  const prerendered = cacheKey ? __privateGet(this, _prerenderedSpreads).get(cacheKey) : null;
  if (prerendered) {
    __privateMethod(this, _FixedLayout_instances, touchSpread_fn).call(this, cacheKey);
    if (prerendered.center) {
      __privateSet(this, _center, prerendered.center);
    } else {
      __privateSet(this, _left, prerendered.left);
      __privateSet(this, _right, prerendered.right);
    }
  } else {
    if (center) {
      __privateSet(this, _center, await __privateMethod(this, _FixedLayout_instances, createFrame_fn).call(this, center));
      if (cacheKey) {
        __privateGet(this, _prerenderedSpreads).set(cacheKey, { center: __privateGet(this, _center) });
        __privateMethod(this, _FixedLayout_instances, touchSpread_fn).call(this, cacheKey);
      }
    } else {
      __privateSet(this, _left, await __privateMethod(this, _FixedLayout_instances, createFrame_fn).call(this, left));
      __privateSet(this, _right, await __privateMethod(this, _FixedLayout_instances, createFrame_fn).call(this, right));
      if (cacheKey) {
        __privateGet(this, _prerenderedSpreads).set(cacheKey, { left: __privateGet(this, _left), right: __privateGet(this, _right) });
        __privateMethod(this, _FixedLayout_instances, touchSpread_fn).call(this, cacheKey);
      }
    }
  }
  __privateSet(this, _side, center ? "center" : ((_a = __privateGet(this, _left)) == null ? void 0 : _a.blank) ? "right" : ((_b = __privateGet(this, _right)) == null ? void 0 : _b.blank) ? "left" : side);
  const visibleFrames = center ? [(_c = __privateGet(this, _center)) == null ? void 0 : _c.element] : [(_d = __privateGet(this, _left)) == null ? void 0 : _d.element, (_e = __privateGet(this, _right)) == null ? void 0 : _e.element];
  if (this.hasAttribute("lock-pan-x")) __privateSet(this, _pannedX, this.scrollLeft);
  Array.from(__privateGet(this, _root).children).forEach((child) => {
    const isVisible = visibleFrames.includes(child);
    Object.assign(child.style, {
      position: isVisible ? "relative" : "absolute",
      visibility: isVisible ? "visible" : "hidden",
      pointerEvents: isVisible ? "auto" : "none"
    });
  });
  const renderPromises = __privateMethod(this, _FixedLayout_instances, render_fn).call(this, __privateGet(this, _side), true);
  if (renderPromises.length) await Promise.all(renderPromises);
  const showingFrames = center ? [__privateGet(this, _center)] : [__privateGet(this, _left), __privateGet(this, _right)];
  for (const frame of showingFrames) {
    if (!(frame == null ? void 0 : frame.iframe)) continue;
    const index = frame.iframe.dataset.sectionIndex != null ? parseInt(frame.iframe.dataset.sectionIndex) : void 0;
    if (index != null && !__privateGet(this, _overlayers).has(index)) {
      const doc = frame.iframe.contentDocument;
      if (doc) {
        this.dispatchEvent(new CustomEvent("create-overlayer", {
          detail: {
            doc,
            index,
            attach: (overlayer) => {
              __privateGet(this, _overlayers).set(index, overlayer);
              frame.element.append(overlayer.element);
              applyOverlayerViewBox(frame, overlayer);
            }
          }
        }));
      }
    }
  }
};
initScrollMode_fn = function(targetIndex = 0) {
  const currentIndex = targetIndex;
  for (const child of Array.from(__privateGet(this, _root).children)) {
    child.style.display = "none";
  }
  __privateSet(this, _scrollContainer, document.createElement("div"));
  __privateGet(this, _scrollContainer).className = "scroll-container";
  __privateGet(this, _root).append(__privateGet(this, _scrollContainer));
  this.style.direction = __privateGet(this, _scrollHorizontal) && this.rtl ? "rtl" : "";
  const sections = this.book.sections;
  const viewport = this.defaultViewport;
  const vw = (viewport == null ? void 0 : viewport.width) ?? 1e3;
  const vh = (viewport == null ? void 0 : viewport.height) ?? 1400;
  __privateSet(this, _scrollPages, sections.map((section, i) => {
    const el = document.createElement("div");
    el.className = "scroll-page";
    el.dataset.index = i;
    return { el, index: i, section, state: "idle", visible: false, frame: null, vpWidth: vw, vpHeight: vh };
  }));
  if (currentIndex >= 0 && currentIndex < __privateGet(this, _scrollPages).length)
    __privateSet(this, _scrollCurrentIndex, currentIndex);
  __privateMethod(this, _FixedLayout_instances, renderScrollMode_fn).call(this);
  __privateMethod(this, _FixedLayout_instances, syncScrollPanLock_fn).call(this);
  this.addEventListener("scroll", __privateGet(this, _handleScrollEvent));
  if (__privateGet(this, _scrollHorizontal)) {
    this.addEventListener("wheel", __privateGet(this, _handleScrollWheel), { passive: false });
  }
};
// Mount the pages within ~2 viewports of the viewport and flag them
// visible, giving the ~400 ms-per-page render enough lead time to finish
// before a page scrolls into view; unmount the rest unless they hold a
// frame. #scheduleScrollPages decides what to actually load (nearest
// first, bounded concurrency) and evict.
updateScrollWindow_fn = function() {
  const view = __privateMethod(this, _FixedLayout_instances, scrollViewLength_fn).call(this);
  const pos = __privateMethod(this, _FixedLayout_instances, scrollProgression_fn).call(this);
  const [from, to] = findScrollPageRange(__privateGet(this, _scrollLayout), pos - 2 * view, pos + 3 * view);
  let changed = false;
  for (const page of __privateGet(this, _scrollMounted)) {
    if (page.index >= from && page.index < to) continue;
    if (page.visible) changed = true;
    page.visible = false;
    if (page.state !== "loading" && page.state !== "loaded") {
      page.el.remove();
      __privateGet(this, _scrollMounted).delete(page);
    }
  }
  for (let i = from; i < to; i++) {
    const page = __privateGet(this, _scrollPages)[i];
    if (!page.visible) changed = true;
    page.visible = true;
    if (!__privateGet(this, _scrollMounted).has(page)) __privateMethod(this, _FixedLayout_instances, mountScrollPage_fn).call(this, page);
  }
  if (changed) __privateMethod(this, _FixedLayout_instances, scheduleScrollPages_fn).call(this);
};
// Insert in index order: a later page paints over an earlier one where
// they overlap, and readers of `.scroll-page` expect strip order.
mountScrollPage_fn = function(page) {
  let next = null;
  for (const other of __privateGet(this, _scrollMounted))
    if (other.index > page.index && (!next || other.index < next.index)) next = other;
  __privateGet(this, _scrollContainer).insertBefore(page.el, (next == null ? void 0 : next.el) ?? null);
  __privateGet(this, _scrollMounted).add(page);
  __privateMethod(this, _FixedLayout_instances, placeScrollPage_fn).call(this, page);
};
placeScrollPage_fn = function(page) {
  const scale = __privateMethod(this, _FixedLayout_instances, scrollPageScale_fn).call(this, page);
  const start = `${__privateGet(this, _scrollLayout).starts[page.index]}px`;
  Object.assign(page.el.style, {
    width: `${page.vpWidth * scale}px`,
    height: `${page.vpHeight * scale}px`
  });
  if (__privateGet(this, _scrollHorizontal)) page.el.style.insetInlineStart = start;
  else page.el.style.top = start;
};
// Scale fitting a page to the strip's cross axis.
scrollPageScale_fn = function(page) {
  return __privateGet(this, _scrollHorizontal) ? this.clientHeight / page.vpHeight * __privateGet(this, _scaleFactor) : this.clientWidth / page.vpWidth * __privateGet(this, _scaleFactor);
};
// Recompute where every page sits, size the strip, and move the mounted
// pages into place. The gap scales with the zoom so the committed layout
// matches the pinch preview, whose transform scales the whole container,
// gaps included.
layoutScrollPages_fn = function() {
  const horizontal = __privateGet(this, _scrollHorizontal);
  const sizes = __privateGet(this, _scrollPages).map((page) => (horizontal ? page.vpWidth : page.vpHeight) * __privateMethod(this, _FixedLayout_instances, scrollPageScale_fn).call(this, page));
  const gap = parseFloat(scrollGapToCss(this.getAttribute("scroll-gap")) ?? 4);
  __privateSet(this, _scrollLayout, layoutScrollPages({
    sizes,
    gap: gap * __privateGet(this, _scaleFactor),
    overlap: computeScrollPageOverlap({ gap, devicePixelRatio: window.devicePixelRatio || 1 })
  }));
  const total = `${__privateGet(this, _scrollLayout).total}px`;
  const cross = `${(horizontal ? this.clientHeight : this.clientWidth) * __privateGet(this, _scaleFactor)}px`;
  __privateGet(this, _scrollContainer).style.width = horizontal ? total : cross;
  __privateGet(this, _scrollContainer).style.height = horizontal ? cross : total;
  for (const page of __privateGet(this, _scrollMounted)) __privateMethod(this, _FixedLayout_instances, placeScrollPage_fn).call(this, page);
};
// Load the nearest visible idle pages and evict the farthest off-screen ones,
// honouring the concurrency and in-memory caps. Re-run whenever visibility or
// load state changes so a finished load immediately pulls in the next page.
scheduleScrollPages_fn = function() {
  if (__privateGet(this, _pinching)) return;
  const currentIndex = __privateMethod(this, _FixedLayout_instances, getScrollIndex_fn).call(this);
  const { load, evict } = planScrollModePages({
    pages: __privateGet(this, _scrollPages),
    currentIndex,
    maxLoaded: __privateGet(this, _scrollMaxLoaded),
    maxConcurrent: __privateGet(this, _scrollMaxConcurrent),
    loadingCount: __privateGet(this, _scrollLoadingCount)
  });
  for (const index of evict) __privateMethod(this, _FixedLayout_instances, teardownScrollPage_fn).call(this, __privateGet(this, _scrollPages)[index]);
  for (const index of load) __privateMethod(this, _FixedLayout_instances, loadScrollPage_fn).call(this, __privateGet(this, _scrollPages)[index]);
};
_handleScrollEvent = new WeakMap();
_handleScrollWheel = new WeakMap();
setScrollIframeInteraction_fn = function(enabled) {
  var _a;
  const value = enabled ? "auto" : "";
  for (const page of __privateGet(this, _scrollMounted)) {
    if ((_a = page.frame) == null ? void 0 : _a.iframe) {
      page.frame.iframe.style.pointerEvents = value;
    }
  }
};
destroyScrollMode_fn = function(navigate = true) {
  const currentIndex = __privateGet(this, _scrollCurrentIndex) >= 0 ? __privateGet(this, _scrollCurrentIndex) : __privateMethod(this, _FixedLayout_instances, getScrollIndex_fn).call(this);
  this.removeEventListener("scroll", __privateGet(this, _handleScrollEvent));
  this.removeEventListener("wheel", __privateGet(this, _handleScrollWheel));
  if (__privateGet(this, _scrollIdleTimer)) {
    clearTimeout(__privateGet(this, _scrollIdleTimer));
    __privateSet(this, _scrollIdleTimer, null);
  }
  for (const page of __privateGet(this, _scrollPages)) {
    __privateMethod(this, _FixedLayout_instances, teardownScrollPage_fn).call(this, page);
  }
  __privateSet(this, _scrollPages, []);
  __privateGet(this, _scrollMounted).clear();
  __privateGet(this, _scrollLoadGen).clear();
  __privateSet(this, _scrollLoadingCount, 0);
  __privateSet(this, _scrollCurrentIndex, -1);
  if (__privateGet(this, _scrollContainer)) {
    __privateGet(this, _scrollContainer).remove();
    __privateSet(this, _scrollContainer, null);
  }
  __privateMethod(this, _FixedLayout_instances, clearLockedPanX_fn).call(this);
  this.scrollTop = 0;
  this.scrollLeft = 0;
  this.style.removeProperty("direction");
  if (navigate) {
    for (const child of Array.from(__privateGet(this, _root).children)) {
      child.style.display = "";
    }
    if (currentIndex >= 0) {
      const section = this.book.sections[currentIndex];
      if (section) {
        const spread = this.getSpreadOf(section);
        if (spread) {
          __privateSet(this, _index, -1);
          this.goToSpread(spread.index, spread.side, "page");
        }
      }
    }
  }
};
createScrollFrame_fn = async function(pageData, srcOption) {
  const srcOptionIsString = typeof srcOption === "string";
  const src = srcOptionIsString ? srcOption : srcOption == null ? void 0 : srcOption.src;
  const data = srcOptionIsString ? null : srcOption == null ? void 0 : srcOption.data;
  const onZoom = srcOptionIsString ? null : srcOption == null ? void 0 : srcOption.onZoom;
  const element = document.createElement("div");
  element.setAttribute("dir", "ltr");
  element.style.position = "relative";
  const iframe = document.createElement("iframe");
  element.append(iframe);
  Object.assign(iframe.style, {
    border: "0",
    display: "none",
    overflow: "hidden"
  });
  iframe.setAttribute("sandbox", "allow-same-origin allow-scripts");
  iframe.setAttribute("scrolling", "no");
  iframe.setAttribute("part", "filter");
  pageData.el.append(element);
  if (!src) return { blank: true, element, iframe };
  return new Promise((resolve) => {
    iframe.addEventListener("load", async () => {
      const doc = iframe.contentDocument;
      __privateMethod(this, _FixedLayout_instances, applyPanLock_fn).call(this, doc);
      iframe.dataset.sectionIndex = pageData.index;
      this.dispatchEvent(new CustomEvent("load", { detail: { doc, index: pageData.index } }));
      const { width, height } = await getViewport(doc, this.defaultViewport);
      resolve({
        element,
        iframe,
        width: parseFloat(width),
        height: parseFloat(height),
        onZoom
      });
    }, { once: true });
    if (data) {
      iframe.srcdoc = data;
    } else {
      iframe.src = src;
    }
  });
};
loadScrollPage_fn = async function(pageData) {
  var _a, _b, _c;
  if (pageData.state !== "idle") return;
  pageData.state = "loading";
  __privateWrapper(this, _scrollLoadingCount)._++;
  const gen = (__privateGet(this, _scrollLoadGen).get(pageData.index) || 0) + 1;
  __privateGet(this, _scrollLoadGen).set(pageData.index, gen);
  try {
    const src = await ((_b = (_a = pageData.section).load) == null ? void 0 : _b.call(_a));
    if (__privateGet(this, _scrollLoadGen).get(pageData.index) !== gen || !__privateGet(this, _scrollMode)) {
      pageData.state = "idle";
      return;
    }
    if (!src) {
      pageData.state = "error";
      return;
    }
    const frame = await __privateMethod(this, _FixedLayout_instances, createScrollFrame_fn).call(this, pageData, src);
    if (__privateGet(this, _scrollLoadGen).get(pageData.index) !== gen || !__privateGet(this, _scrollMode)) {
      (_c = frame.element) == null ? void 0 : _c.remove();
      pageData.state = "idle";
      return;
    }
    pageData.frame = frame;
    pageData.state = "loaded";
    const scrollAnchor = __privateMethod(this, _FixedLayout_instances, captureScrollModeAnchor_fn).call(this);
    if (frame.width && frame.height && (frame.width !== pageData.vpWidth || frame.height !== pageData.vpHeight)) {
      pageData.vpWidth = frame.width;
      pageData.vpHeight = frame.height;
      __privateMethod(this, _FixedLayout_instances, layoutScrollPages_fn).call(this);
    }
    __privateMethod(this, _FixedLayout_instances, renderScrollPage_fn).call(this, pageData);
    __privateMethod(this, _FixedLayout_instances, restoreScrollModeAnchor_fn).call(this, scrollAnchor);
    __privateMethod(this, _FixedLayout_instances, updateScrollWindow_fn).call(this);
    if (!__privateGet(this, _scrolling) && !__privateGet(this, _pinching) && frame.iframe) {
      frame.iframe.style.pointerEvents = "auto";
    }
    const doc = frame.iframe.contentDocument;
    if (doc) {
      this.dispatchEvent(new CustomEvent("create-overlayer", {
        detail: {
          doc,
          index: pageData.index,
          attach: (overlayer) => {
            __privateGet(this, _overlayers).set(pageData.index, overlayer);
            frame.element.append(overlayer.element);
            applyOverlayerViewBox(frame, overlayer);
          }
        }
      }));
      doc.addEventListener("wheel", (e) => {
        __privateMethod(this, _FixedLayout_instances, setScrollIframeInteraction_fn).call(this, false);
        const delta = computeScrollWheelDelta({
          deltaX: e.deltaX,
          deltaY: e.deltaY,
          ctrlKey: e.ctrlKey,
          horizontal: __privateGet(this, _scrollHorizontal),
          rtl: this.rtl,
          verticalOverflow: this.scrollHeight > this.clientHeight + 1
        });
        if (delta) this.scrollBy({ left: delta.left, behavior: "auto" });
      }, { passive: true });
    }
  } catch (e) {
    console.warn("Failed to load scroll page", pageData.index, e);
    pageData.state = "error";
  } finally {
    __privateSet(this, _scrollLoadingCount, Math.max(0, __privateGet(this, _scrollLoadingCount) - 1));
    if (__privateGet(this, _scrollMode)) __privateMethod(this, _FixedLayout_instances, scheduleScrollPages_fn).call(this);
  }
};
// Remove a loaded scroll page's frame and overlayer
teardownScrollPage_fn = function(pageData) {
  var _a;
  const gen = (__privateGet(this, _scrollLoadGen).get(pageData.index) || 0) + 1;
  __privateGet(this, _scrollLoadGen).set(pageData.index, gen);
  if (pageData.frame) {
    const idx = pageData.index;
    __privateGet(this, _overlayers).delete(idx);
    (_a = pageData.frame.element) == null ? void 0 : _a.remove();
  }
  pageData.frame = null;
  pageData.state = "idle";
  if (!pageData.visible && __privateGet(this, _scrollMounted).delete(pageData)) pageData.el.remove();
};
renderScrollMode_fn = function() {
  const { clientWidth: hostWidth, clientHeight: hostHeight } = this;
  if (!__privateGet(this, _scrollContainer) || !(__privateGet(this, _scrollHorizontal) ? hostHeight : hostWidth)) return;
  const pinchAnchor = __privateGet(this, _pinchAnchor);
  const scrollAnchor = pinchAnchor ? null : __privateMethod(this, _FixedLayout_instances, captureScrollModeAnchor_fn).call(this);
  __privateMethod(this, _FixedLayout_instances, layoutScrollPages_fn).call(this);
  for (const page of __privateGet(this, _scrollMounted)) {
    if (page.state === "loaded" && page.frame) {
      __privateMethod(this, _FixedLayout_instances, renderScrollPage_fn).call(this, page);
    }
  }
  if (__privateGet(this, _lockedPanX) !== null) __privateMethod(this, _FixedLayout_instances, setLockedPanX_fn).call(this, __privateGet(this, _lockedPanX));
  __privateMethod(this, _FixedLayout_instances, applyPendingPanX_fn).call(this);
  if (pinchAnchor) {
    __privateMethod(this, _FixedLayout_instances, restorePinchAnchor_fn).call(this, pinchAnchor);
    __privateSet(this, _pinchAnchor, null);
  } else {
    __privateMethod(this, _FixedLayout_instances, restoreScrollModeAnchor_fn).call(this, scrollAnchor);
  }
  __privateMethod(this, _FixedLayout_instances, updateScrollWindow_fn).call(this);
};
renderScrollPage_fn = function(pageData) {
  const { clientWidth: hostWidth, clientHeight: hostHeight } = this;
  if (!(__privateGet(this, _scrollHorizontal) ? hostHeight : hostWidth) || !pageData.frame) return;
  const { vpWidth: vw, vpHeight: vh, frame } = pageData;
  const scale = __privateMethod(this, _FixedLayout_instances, scrollPageScale_fn).call(this, pageData);
  if (frame.onZoom) {
    const p = frame.onZoom({
      doc: frame.iframe.contentDocument,
      scale,
      pageColors: __privateGet(this, _pageColors)
    });
    if (p == null ? void 0 : p.then) p.then(() => __privateMethod(this, _FixedLayout_instances, refreshOverlayerForFrame_fn).call(this, frame));
    Object.assign(frame.iframe.style, {
      width: `${vw * scale}px`,
      height: `${vh * scale}px`,
      transform: "none",
      display: "block"
    });
  } else {
    Object.assign(frame.iframe.style, {
      width: `${vw}px`,
      height: `${vh}px`,
      transform: `scale(${scale})`,
      transformOrigin: "top left",
      display: "block"
    });
  }
  Object.assign(frame.element.style, {
    width: `${vw * scale}px`,
    height: `${vh * scale}px`
  });
  const overlayer = __privateGet(this, _overlayers).get(pageData.index);
  if (overlayer) {
    Object.assign(overlayer.element.style, {
      position: "absolute",
      top: "0",
      left: "0",
      width: `${vw * scale}px`,
      height: `${vh * scale}px`
    });
    applyOverlayerViewBox(frame, overlayer);
    overlayer.redraw();
  }
};
// The page under the middle of the viewport, or the one after the gap
// the middle falls in.
getScrollIndex_fn = function() {
  if (!__privateGet(this, _scrollPages).length) return -1;
  const mid = __privateMethod(this, _FixedLayout_instances, scrollProgression_fn).call(this) + __privateMethod(this, _FixedLayout_instances, scrollViewLength_fn).call(this) / 2;
  const [index] = findScrollPageRange(__privateGet(this, _scrollLayout), mid, mid);
  return Math.min(index, __privateGet(this, _scrollPages).length - 1);
};
scrollToPage_fn = function(index, behavior) {
  const start = __privateGet(this, _scrollLayout).starts[index] ?? 0;
  if (behavior) this.scrollTo(__privateGet(this, _scrollHorizontal) ? { left: this.rtl ? -start : start, behavior } : { top: start, behavior });
  else {
    __privateMethod(this, _FixedLayout_instances, setScrollProgression_fn).call(this, start);
    __privateMethod(this, _FixedLayout_instances, updateScrollWindow_fn).call(this);
  }
  __privateSet(this, _scrollCurrentIndex, index);
};
reportScrollLocation_fn = function() {
  const index = __privateMethod(this, _FixedLayout_instances, getScrollIndex_fn).call(this);
  if (index < 0) return;
  __privateSet(this, _scrollCurrentIndex, index);
  this.dispatchEvent(new CustomEvent("relocate", { detail: { reason: "scroll", range: null, index, fraction: 0, size: 1 } }));
};
goLeft_fn = function() {
  var _a, _b, _c, _d;
  if (__privateGet(this, _center) || ((_a = __privateGet(this, _left)) == null ? void 0 : _a.blank)) return;
  if (__privateGet(this, _portrait) && ((_d = (_c = (_b = __privateGet(this, _left)) == null ? void 0 : _b.element) == null ? void 0 : _c.style) == null ? void 0 : _d.display) === "none") {
    __privateSet(this, _side, "left");
    __privateMethod(this, _FixedLayout_instances, render_fn).call(this, __privateGet(this, _side), true);
    __privateMethod(this, _FixedLayout_instances, reportLocation_fn).call(this, "page");
    return true;
  }
};
goRight_fn = function() {
  var _a, _b, _c, _d;
  if (__privateGet(this, _center) || ((_a = __privateGet(this, _right)) == null ? void 0 : _a.blank)) return;
  if (__privateGet(this, _portrait) && ((_d = (_c = (_b = __privateGet(this, _right)) == null ? void 0 : _b.element) == null ? void 0 : _c.style) == null ? void 0 : _d.display) === "none") {
    __privateSet(this, _side, "right");
    __privateMethod(this, _FixedLayout_instances, render_fn).call(this, __privateGet(this, _side), true);
    __privateMethod(this, _FixedLayout_instances, reportLocation_fn).call(this, "page");
    return true;
  }
};
spread_fn = function(mode) {
  const book = this.book;
  const { rendition } = book;
  const rtl = this.rtl;
  const ltr = !rtl;
  this.spread = mode || (rendition == null ? void 0 : rendition.spread);
  if (this.spread === "none")
    __privateSet(this, _spreads, book.sections.map((section) => ({ center: section })));
  else __privateSet(this, _spreads, book.sections.reduce((arr, section, i) => {
    const last = arr[arr.length - 1];
    const { pageSpread } = section;
    const newSpread = () => {
      const spread = {};
      arr.push(spread);
      return spread;
    };
    if (pageSpread === "center") {
      const spread = last.left || last.right ? newSpread() : last;
      spread.center = section;
    } else if (pageSpread === "left") {
      const spread = last.center || last.left || ltr && i ? newSpread() : last;
      spread.left = section;
    } else if (pageSpread === "right") {
      const spread = last.center || last.right || rtl && i ? newSpread() : last;
      spread.right = section;
    } else if (ltr) {
      if (last.center || last.right) newSpread().left = section;
      else if (last.left || !i) last.right = section;
      else last.left = section;
    } else {
      if (last.center || last.left) newSpread().right = section;
      else if (last.right || !i) last.left = section;
      else last.right = section;
    }
    return arr;
  }, [{}]));
};
respread_fn = function(spreadMode) {
  var _a, _b, _c, _d, _e;
  if (__privateGet(this, _index) === -1) return;
  const section = this.book.sections[this.index];
  __privateMethod(this, _FixedLayout_instances, spread_fn).call(this, spreadMode);
  const { index } = this.getSpreadOf(section);
  __privateSet(this, _index, -1);
  __privateGet(this, _preloadCache).clear();
  for (const frames of __privateGet(this, _prerenderedSpreads).values()) {
    if (frames.center) {
      (_a = frames.center.element) == null ? void 0 : _a.remove();
    } else {
      (_c = (_b = frames.left) == null ? void 0 : _b.element) == null ? void 0 : _c.remove();
      (_e = (_d = frames.right) == null ? void 0 : _d.element) == null ? void 0 : _e.remove();
    }
  }
  __privateGet(this, _prerenderedSpreads).clear();
  __privateGet(this, _spreadAccessTime).clear();
  __privateGet(this, _overlayers).clear();
  this.goToSpread(index, this.rtl ? "right" : "left", "page");
};
// A section can find out as it loads that it is a spread of its own: a
// streamed comic measures a page when its image arrives, and a wide one
// marks itself `pageSpread: 'center'`. Regroup from the first spread that
// changed; the spreads before it keep their objects and cached frames, so
// a spread object still at its index is still current.
regroup_fn = function() {
  const old = __privateGet(this, _spreads);
  __privateMethod(this, _FixedLayout_instances, spread_fn).call(this, this.spread);
  const same = (a, b) => a && b && a.left === b.left && a.right === b.right && a.center === b.center;
  let from = 0;
  while (from < old.length && same(old[from], __privateGet(this, _spreads)[from])) from++;
  if (from === old.length && from === __privateGet(this, _spreads).length) {
    __privateSet(this, _spreads, old);
    return;
  }
  __privateSet(this, _spreads, [...old.slice(0, from), ...__privateGet(this, _spreads).slice(from)]);
  const isRegrouped = (key) => {
    var _a;
    return Number(((_a = /^spread-(\d+)$/.exec(key)) == null ? void 0 : _a[1]) ?? -1) >= from;
  };
  for (const key of [...__privateGet(this, _preloadCache).keys()])
    if (isRegrouped(key)) __privateGet(this, _preloadCache).delete(key);
  for (const key of [...__privateGet(this, _prerenderedSpreads).keys()]) {
    if (!isRegrouped(key)) continue;
    const staleKey = `stale-${++__privateWrapper(this, _staleSpreads)._}`;
    __privateGet(this, _prerenderedSpreads).set(staleKey, __privateGet(this, _prerenderedSpreads).get(key));
    __privateGet(this, _spreadAccessTime).set(staleKey, __privateGet(this, _spreadAccessTime).get(key) ?? 0);
    __privateGet(this, _prerenderedSpreads).delete(key);
    __privateGet(this, _spreadAccessTime).delete(key);
  }
};
// After a regroup, go where the page a turn aimed at now sits: the page on
// `side` of the spread it was headed for.
goToPageOf_fn = function(spread, side, reason) {
  const section = spread.center ?? spread[side] ?? spread.left ?? spread.right;
  const target = this.getSpreadOf(section);
  __privateSet(this, _index, -1);
  return this.goToSpread(target.index, target.side, reason);
};
reportLocation_fn = function(reason) {
  this.dispatchEvent(new CustomEvent("relocate", { detail: { reason, range: null, index: this.index, fraction: 0, size: 1 } }));
};
preloadNextSpreads_fn = function() {
  __privateMethod(this, _FixedLayout_instances, cleanupPreloadCache_fn).call(this);
  if (__privateGet(this, _numPrerenderedSpreads) <= 0) return;
  const toPreload = [];
  const forwardPreloadCount = Math.max(1, __privateGet(this, _numPrerenderedSpreads) - 1);
  const backwardPreloadCount = Math.max(0, __privateGet(this, _numPrerenderedSpreads) - forwardPreloadCount);
  for (let distance = 1; distance <= forwardPreloadCount; distance++) {
    const forwardIndex = __privateGet(this, _index) + distance;
    if (forwardIndex >= 0 && forwardIndex < __privateGet(this, _spreads).length) {
      toPreload.push({ index: forwardIndex, direction: "forward", distance });
    }
  }
  for (let distance = 1; distance <= backwardPreloadCount; distance++) {
    const backwardIndex = __privateGet(this, _index) - distance;
    if (backwardIndex >= 0 && backwardIndex < __privateGet(this, _spreads).length) {
      toPreload.push({ index: backwardIndex, direction: "backward", distance });
    }
  }
  for (const { index: targetIndex, direction } of toPreload) {
    const cacheKey = `spread-${targetIndex}`;
    if (__privateGet(this, _prerenderedSpreads).has(cacheKey)) continue;
    const spread = __privateGet(this, _spreads)[targetIndex];
    if (!spread) continue;
    __privateGet(this, _preloadQueue).push({ targetIndex, direction, spread, cacheKey });
  }
  __privateMethod(this, _FixedLayout_instances, processPreloadQueue_fn).call(this);
};
processPreloadQueue_fn = async function() {
  while (__privateGet(this, _preloadQueue).length > 0 && __privateGet(this, _activePreloads) < __privateGet(this, _maxConcurrentPreloads)) {
    const task = __privateGet(this, _preloadQueue).shift();
    if (!task) break;
    const { spread, cacheKey, targetIndex } = task;
    const isStale = () => __privateGet(this, _spreads)[targetIndex] !== spread;
    __privateGet(this, _preloadCache).set(cacheKey, "loading");
    __privateWrapper(this, _activePreloads)._++;
    Promise.resolve().then(async () => {
      var _a, _b, _c, _d, _e, _f;
      try {
        if (spread.center) {
          const src = await ((_b = (_a = spread.center) == null ? void 0 : _a.load) == null ? void 0 : _b.call(_a));
          __privateMethod(this, _FixedLayout_instances, regroup_fn).call(this);
          if (isStale()) return __privateMethod(this, _FixedLayout_instances, preloadNextSpreads_fn).call(this);
          __privateGet(this, _preloadCache).set(cacheKey, { center: src });
          const sectionIndex = this.book.sections.indexOf(spread.center);
          const frame = await __privateMethod(this, _FixedLayout_instances, createFrame_fn).call(this, { index: sectionIndex, src, detached: true });
          if (isStale()) return frame.element.remove();
          __privateGet(this, _prerenderedSpreads).set(cacheKey, { center: frame });
          __privateMethod(this, _FixedLayout_instances, touchSpread_fn).call(this, cacheKey);
          if (frame.onZoom) {
            const doc = frame.iframe.contentDocument;
            frame.onZoom({ doc, scale: __privateGet(this, _totalScaleFactor), pageColors: __privateGet(this, _pageColors) });
          }
        } else {
          const srcL = await ((_d = (_c = spread.left) == null ? void 0 : _c.load) == null ? void 0 : _d.call(_c));
          const srcR = await ((_f = (_e = spread.right) == null ? void 0 : _e.load) == null ? void 0 : _f.call(_e));
          __privateMethod(this, _FixedLayout_instances, regroup_fn).call(this);
          if (isStale()) return __privateMethod(this, _FixedLayout_instances, preloadNextSpreads_fn).call(this);
          __privateGet(this, _preloadCache).set(cacheKey, { left: srcL, right: srcR });
          const indexL = this.book.sections.indexOf(spread.left);
          const indexR = this.book.sections.indexOf(spread.right);
          const leftFrame = await __privateMethod(this, _FixedLayout_instances, createFrame_fn).call(this, { index: indexL, src: srcL, detached: true });
          const rightFrame = await __privateMethod(this, _FixedLayout_instances, createFrame_fn).call(this, { index: indexR, src: srcR, detached: true });
          if (isStale()) {
            leftFrame.element.remove();
            rightFrame.element.remove();
            return;
          }
          __privateGet(this, _prerenderedSpreads).set(cacheKey, { left: leftFrame, right: rightFrame });
          __privateMethod(this, _FixedLayout_instances, touchSpread_fn).call(this, cacheKey);
          if (leftFrame.onZoom) {
            const docL = leftFrame.iframe.contentDocument;
            leftFrame.onZoom({ doc: docL, scale: __privateGet(this, _totalScaleFactor), pageColors: __privateGet(this, _pageColors) });
          }
          if (rightFrame.onZoom) {
            const docR = rightFrame.iframe.contentDocument;
            rightFrame.onZoom({ doc: docR, scale: __privateGet(this, _totalScaleFactor), pageColors: __privateGet(this, _pageColors) });
          }
        }
      } catch {
        __privateGet(this, _preloadCache).delete(cacheKey);
        __privateGet(this, _prerenderedSpreads).delete(cacheKey);
      } finally {
        __privateWrapper(this, _activePreloads)._--;
        __privateMethod(this, _FixedLayout_instances, processPreloadQueue_fn).call(this);
      }
    });
  }
};
// Most-recently-used ordering for the spread cache. A counter, not a clock:
// the trim sorts by this value, and two stamps in the same millisecond fell
// back to Map insertion order, which ranked the current spread oldest.
touchSpread_fn = function(cacheKey) {
  __privateGet(this, _spreadAccessTime).set(cacheKey, ++__privateWrapper(this, _spreadAccessTick)._);
};
cleanupPreloadCache_fn = function() {
  const maxSpreads = __privateGet(this, _maxCachedSpreads);
  if (__privateGet(this, _prerenderedSpreads).size <= maxSpreads) {
    return;
  }
  const framesByAge = Array.from(__privateGet(this, _prerenderedSpreads).keys()).map((key) => ({
    key,
    accessTime: __privateGet(this, _spreadAccessTime).get(key) || 0
  })).sort((a, b) => a.accessTime - b.accessTime);
  const numToRemove = __privateGet(this, _prerenderedSpreads).size - maxSpreads;
  const framesToDelete = framesByAge.slice(0, numToRemove).map((item) => item.key);
  if (framesToDelete.length > 0) {
    framesToDelete.forEach((key) => {
      var _a, _b, _c, _d, _e;
      const frames = __privateGet(this, _prerenderedSpreads).get(key);
      if (frames) {
        if (frames.center) {
          __privateMethod(this, _FixedLayout_instances, removeOverlayerForFrame_fn).call(this, frames.center);
          (_a = frames.center.element) == null ? void 0 : _a.remove();
        } else {
          __privateMethod(this, _FixedLayout_instances, removeOverlayerForFrame_fn).call(this, frames.left);
          __privateMethod(this, _FixedLayout_instances, removeOverlayerForFrame_fn).call(this, frames.right);
          (_c = (_b = frames.left) == null ? void 0 : _b.element) == null ? void 0 : _c.remove();
          (_e = (_d = frames.right) == null ? void 0 : _d.element) == null ? void 0 : _e.remove();
        }
      }
      __privateGet(this, _prerenderedSpreads).delete(key);
      __privateGet(this, _spreadAccessTime).delete(key);
      __privateGet(this, _preloadCache).delete(key);
    });
  }
};
removeOverlayerForFrame_fn = function(frame) {
  if (!(frame == null ? void 0 : frame.iframe)) return;
  const idx = frame.iframe.dataset.sectionIndex != null ? parseInt(frame.iframe.dataset.sectionIndex) : void 0;
  if (idx != null) __privateGet(this, _overlayers).delete(idx);
};
// Drop a frame's overlayer and re-emit create-overlayer so listeners can
// re-add annotations. Called after a text layer rebuild (e.g. pdf.js
// onZoom) which invalidates Range objects stored in the overlayer.
refreshOverlayerForFrame_fn = function(frame) {
  var _a, _b;
  if (!(frame == null ? void 0 : frame.iframe)) return;
  const index = frame.iframe.dataset.sectionIndex != null ? parseInt(frame.iframe.dataset.sectionIndex) : void 0;
  if (index == null) return;
  const stale = __privateGet(this, _overlayers).get(index);
  if (!stale) return;
  const isVisible = ((_a = frame.element) == null ? void 0 : _a.parentNode) && frame.element.style.visibility !== "hidden";
  if (!isVisible) return;
  (_b = stale.element) == null ? void 0 : _b.remove();
  __privateGet(this, _overlayers).delete(index);
  const doc = frame.iframe.contentDocument;
  if (!doc) return;
  this.dispatchEvent(new CustomEvent("create-overlayer", {
    detail: {
      doc,
      index,
      attach: (overlayer) => {
        __privateGet(this, _overlayers).set(index, overlayer);
        frame.element.append(overlayer.element);
      }
    }
  }));
};
// The paginated pages on screen. Portrait shows one page of a spread and
// hides the other with display: none, which has no rect to anchor on.
shownFrames_fn = function() {
  const frames = __privateGet(this, _center) ? [__privateGet(this, _center)] : [__privateGet(this, _left), __privateGet(this, _right)];
  return frames.filter((frame) => {
    var _a;
    return (_a = frame == null ? void 0 : frame.element) == null ? void 0 : _a.offsetWidth;
  });
};
__publicField(FixedLayout, "observedAttributes", ["zoom", "scale-factor", "spread", "flow", "scroll-gap", "scroll-direction", "lock-pan-x"]);
customElements.define("foliate-fxl", FixedLayout);
export {
  FixedLayout,
  applyOverlayerViewBox,
  captureScrollModeAnchor,
  computePaginatedScroll,
  computeScrollPageOverlap,
  computeScrollPinchTransform,
  computeScrollWheelDelta,
  computeSpreadColumnCount,
  computeSpreadInlineMargins,
  computeSpreadSpineOverlap,
  findScrollPageRange,
  getViewport,
  layoutScrollPages,
  planScrollModePages,
  restoreScrollModeAnchor,
  scrollGapToCss
};
