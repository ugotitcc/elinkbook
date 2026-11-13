var __typeError = (msg) => {
  throw TypeError(msg);
};
var __accessCheck = (obj, member, msg) => member.has(obj) || __typeError("Cannot " + msg);
var __privateGet = (obj, member, getter) => (__accessCheck(obj, member, "read from private field"), getter ? getter.call(obj) : member.get(obj));
var __privateAdd = (obj, member, value) => member.has(obj) ? __typeError("Cannot add the same private member more than once") : member instanceof WeakSet ? member.add(obj) : member.set(obj, value);
var __privateSet = (obj, member, value, setter) => (__accessCheck(obj, member, "write to private field"), setter ? setter.call(obj, value) : member.set(obj, value), value);
var __privateMethod = (obj, member, method) => (__accessCheck(obj, member, "access private method"), method);
var _svg, _map, _doc, _clipPath, _clipPathPath, _clipPathId, _Overlayer_instances, zoom_get, splitRange_fn, getRects_fn;
const createSVGElement = (tag) => document.createElementNS("http://www.w3.org/2000/svg", tag);
let overlayerCounter = 0;
const pageOf = (root, { left, top, right, bottom }) => {
  if (!(root.width > 0 && root.height > 0)) return null;
  const x = root.left + Math.floor(((left + right) / 2 - root.left) / root.width) * root.width;
  const y = root.top + Math.floor(((top + bottom) / 2 - root.top) / root.height) * root.height;
  return { left: x, top: y, right: x + root.width, bottom: y + root.height };
};
const mergeLineRects = (rects, vertical) => {
  var _a, _b, _c, _d;
  const [start, end, crossStart, crossEnd] = vertical ? ["top", "bottom", "left", "right"] : ["left", "right", "top", "bottom"];
  const size = (r) => Math.max(r[crossEnd] - r[crossStart], 1);
  const merged = [];
  for (const rect of rects) {
    const line = merged[merged.length - 1];
    let sameLine = false;
    if (line && ((_a = line.page) == null ? void 0 : _a.left) === ((_b = rect.page) == null ? void 0 : _b.left) && ((_c = line.page) == null ? void 0 : _c.top) === ((_d = rect.page) == null ? void 0 : _d.top)) {
      const big = Math.max(size(line), size(rect));
      const gap = Math.max(line[start], rect[start]) - Math.min(line[end], rect[end]);
      sameLine = size(rect) < 2 * size(line) && gap > -big && gap < 2 * big && Math.min(line[crossEnd], rect[crossEnd]) > Math.max(line[crossStart], rect[crossStart]);
    }
    if (!sameLine) {
      merged.push({ ...rect });
      continue;
    }
    line.left = Math.min(line.left, rect.left);
    line.top = Math.min(line.top, rect.top);
    line.right = Math.max(line.right, rect.right);
    line.bottom = Math.max(line.bottom, rect.bottom);
    line.width = line.right - line.left;
    line.height = line.bottom - line.top;
  }
  return merged;
};
class Overlayer {
  constructor(doc) {
    __privateAdd(this, _Overlayer_instances);
    __privateAdd(this, _svg, createSVGElement("svg"));
    __privateAdd(this, _map, /* @__PURE__ */ new Map());
    __privateAdd(this, _doc, null);
    __privateAdd(this, _clipPath, null);
    __privateAdd(this, _clipPathPath, null);
    __privateAdd(this, _clipPathId);
    __privateSet(this, _doc, doc);
    __privateSet(this, _clipPathId, `foliate-loupe-clip-${overlayerCounter++}`);
    Object.assign(__privateGet(this, _svg).style, {
      position: "absolute",
      top: "0",
      left: "0",
      width: "100%",
      height: "100%",
      pointerEvents: "none"
    });
    const defs = createSVGElement("defs");
    __privateSet(this, _clipPath, createSVGElement("clipPath"));
    __privateGet(this, _clipPath).setAttribute("id", __privateGet(this, _clipPathId));
    __privateGet(this, _clipPath).setAttribute("clipPathUnits", "userSpaceOnUse");
    __privateSet(this, _clipPathPath, createSVGElement("path"));
    __privateGet(this, _clipPathPath).setAttribute("clip-rule", "evenodd");
    __privateGet(this, _clipPathPath).setAttribute("fill-rule", "evenodd");
    __privateGet(this, _clipPath).append(__privateGet(this, _clipPathPath));
    defs.append(__privateGet(this, _clipPath));
    __privateGet(this, _svg).append(defs);
  }
  setHole(cx, cy, w, h, r) {
    const outer = "M -2000000 -2000000 H 4000000 V 4000000 H -2000000 Z";
    const hw = w / 2, hh = h / 2;
    const cr = Math.min(r, hw, hh);
    const inner = `M ${cx - hw + cr} ${cy - hh} H ${cx + hw - cr} A ${cr} ${cr} 0 0 1 ${cx + hw} ${cy - hh + cr} V ${cy + hh - cr} A ${cr} ${cr} 0 0 1 ${cx + hw - cr} ${cy + hh} H ${cx - hw + cr} A ${cr} ${cr} 0 0 1 ${cx - hw} ${cy + hh - cr} V ${cy - hh + cr} A ${cr} ${cr} 0 0 1 ${cx - hw + cr} ${cy - hh} Z`;
    __privateGet(this, _clipPathPath).setAttribute("d", `${outer} ${inner}`);
    __privateGet(this, _svg).setAttribute("clip-path", `url(#${__privateGet(this, _clipPathId)})`);
    __privateGet(this, _svg).style.webkitClipPath = `url(#${__privateGet(this, _clipPathId)})`;
  }
  clearHole() {
    __privateGet(this, _svg).removeAttribute("clip-path");
    __privateGet(this, _svg).style.webkitClipPath = "";
    __privateGet(this, _clipPathPath).removeAttribute("d");
  }
  get element() {
    return __privateGet(this, _svg);
  }
  add(key, range, draw, options) {
    if (__privateGet(this, _map).has(key)) this.remove(key);
    if (typeof range === "function") range = range(__privateGet(this, _svg).getRootNode());
    const rects = __privateMethod(this, _Overlayer_instances, getRects_fn).call(this, range);
    const element = draw(rects, options);
    __privateGet(this, _svg).append(element);
    __privateGet(this, _map).set(key, { range, draw, options, element, rects });
  }
  remove(key) {
    if (!__privateGet(this, _map).has(key)) return;
    __privateGet(this, _svg).removeChild(__privateGet(this, _map).get(key).element);
    __privateGet(this, _map).delete(key);
  }
  redraw() {
    for (const obj of __privateGet(this, _map).values()) {
      const { range, draw, options, element } = obj;
      __privateGet(this, _svg).removeChild(element);
      const rects = __privateMethod(this, _Overlayer_instances, getRects_fn).call(this, range);
      const el = draw(rects, options);
      __privateGet(this, _svg).append(el);
      obj.element = el;
      obj.rects = rects;
    }
  }
  hitTest({ x, y }) {
    const arr = Array.from(__privateGet(this, _map).entries());
    for (let i = arr.length - 1; i >= 0; i--) {
      const tolerance = 5;
      const [key, obj] = arr[i];
      for (const { left, top, right, bottom } of obj.rects) {
        if (top <= y + tolerance && left <= x + tolerance && bottom > y - tolerance && right > x - tolerance) {
          return [key, obj.range, { left, top, right, bottom }];
        }
      }
    }
    return [];
  }
  static underline(rects, options = {}) {
    const { color = "red", width: strokeWidth = 2, padding = 0, writingMode } = options;
    const g = createSVGElement("g");
    g.setAttribute("fill", color);
    if (writingMode === "vertical-rl" || writingMode === "vertical-lr")
      for (const { right, top, height } of rects) {
        const el = createSVGElement("rect");
        el.setAttribute("x", right - strokeWidth / 2 + padding);
        el.setAttribute("y", top);
        el.setAttribute("height", height);
        el.setAttribute("width", strokeWidth);
        g.append(el);
      }
    else for (const { left, bottom, width } of rects) {
      const el = createSVGElement("rect");
      el.setAttribute("x", left);
      el.setAttribute("y", bottom - strokeWidth / 2 + padding);
      el.setAttribute("height", strokeWidth);
      el.setAttribute("width", width);
      g.append(el);
    }
    return g;
  }
  static strikethrough(rects, options = {}) {
    const { color = "red", width: strokeWidth = 2, writingMode } = options;
    const g = createSVGElement("g");
    g.setAttribute("fill", color);
    if (writingMode === "vertical-rl" || writingMode === "vertical-lr")
      for (const { right, left, top, height } of rects) {
        const el = createSVGElement("rect");
        el.setAttribute("x", (right + left) / 2);
        el.setAttribute("y", top);
        el.setAttribute("height", height);
        el.setAttribute("width", strokeWidth);
        g.append(el);
      }
    else for (const { left, top, bottom, width } of rects) {
      const el = createSVGElement("rect");
      el.setAttribute("x", left);
      el.setAttribute("y", (top + bottom) / 2);
      el.setAttribute("height", strokeWidth);
      el.setAttribute("width", width);
      g.append(el);
    }
    return g;
  }
  static squiggly(rects, options = {}) {
    const { color = "red", width: strokeWidth = 2, padding = 0, writingMode } = options;
    const g = createSVGElement("g");
    g.setAttribute("fill", "none");
    g.setAttribute("stroke", color);
    g.setAttribute("stroke-width", strokeWidth);
    const block = strokeWidth * 1.5;
    if (writingMode === "vertical-rl" || writingMode === "vertical-lr")
      for (const { right, top, height } of rects) {
        const el = createSVGElement("path");
        const n = Math.round(height / block / 1.5);
        const inline = height / n;
        const ls = Array.from(
          { length: n },
          (_, i) => `l${i % 2 ? -block : block} ${inline}`
        ).join("");
        el.setAttribute("d", `M${right - strokeWidth / 2 + padding} ${top}${ls}`);
        g.append(el);
      }
    else for (const { left, bottom, width } of rects) {
      const el = createSVGElement("path");
      const n = Math.round(width / block / 1.5);
      const inline = width / n;
      const ls = Array.from(
        { length: n },
        (_, i) => `l${inline} ${i % 2 ? block : -block}`
      ).join("");
      el.setAttribute("d", `M${left} ${bottom + strokeWidth / 2 + padding}${ls}`);
      g.append(el);
    }
    return g;
  }
  static highlight(rects, options = {}) {
    const {
      color = "red",
      padding = 0,
      radius = 4,
      radiusPadding = 2,
      vertical = false
    } = options;
    const g = createSVGElement("g");
    g.setAttribute("fill", color);
    g.style.opacity = "var(--overlayer-highlight-opacity, .3)";
    g.style.mixBlendMode = "var(--overlayer-highlight-blend-mode, normal)";
    const lines = mergeLineRects(rects, vertical);
    for (const [index, { left, top, height, width, page }] of lines.entries()) {
      const isFirst = index === 0;
      const isLast = index === lines.length - 1;
      let x, y, w, h;
      let radiusTopLeft, radiusTopRight, radiusBottomRight, radiusBottomLeft;
      if (vertical) {
        x = left - padding;
        y = top - padding - (isFirst ? radiusPadding : 0);
        w = width + padding * 2;
        h = height + padding * 2 + (isFirst ? radiusPadding : 0) + (isLast ? radiusPadding : 0);
        radiusTopLeft = isFirst ? radius : 0;
        radiusTopRight = isFirst ? radius : 0;
        radiusBottomRight = isLast ? radius : 0;
        radiusBottomLeft = isLast ? radius : 0;
      } else {
        x = left - padding - (isFirst ? radiusPadding : 0);
        y = top - padding;
        w = width + padding * 2 + (isFirst ? radiusPadding : 0) + (isLast ? radiusPadding : 0);
        h = height + padding * 2;
        radiusTopLeft = isFirst ? radius : 0;
        radiusTopRight = isLast ? radius : 0;
        radiusBottomRight = isLast ? radius : 0;
        radiusBottomLeft = isFirst ? radius : 0;
      }
      if (page) {
        const right = Math.min(x + w, page.right);
        const bottom = Math.min(y + h, page.bottom);
        x = Math.max(x, page.left);
        y = Math.max(y, page.top);
        w = right - x;
        h = bottom - y;
        if (w <= 0 || h <= 0) continue;
      }
      const rtl = Math.min(radiusTopLeft, w / 2, h / 2);
      const rtr = Math.min(radiusTopRight, w / 2, h / 2);
      const rbr = Math.min(radiusBottomRight, w / 2, h / 2);
      const rbl = Math.min(radiusBottomLeft, w / 2, h / 2);
      if (rtl === 0 && rtr === 0 && rbr === 0 && rbl === 0) {
        const el = createSVGElement("rect");
        el.setAttribute("x", x);
        el.setAttribute("y", y);
        el.setAttribute("height", h);
        el.setAttribute("width", w);
        g.append(el);
      } else {
        const el = createSVGElement("path");
        const d = `
                M ${x + rtl} ${y}
                L ${x + w - rtr} ${y}
                ${rtr > 0 ? `Q ${x + w} ${y} ${x + w} ${y + rtr}` : `L ${x + w} ${y}`}
                L ${x + w} ${y + h - rbr}
                ${rbr > 0 ? `Q ${x + w} ${y + h} ${x + w - rbr} ${y + h}` : `L ${x + w} ${y + h}`}
                L ${x + rbl} ${y + h}
                ${rbl > 0 ? `Q ${x} ${y + h} ${x} ${y + h - rbl}` : `L ${x} ${y + h}`}
                L ${x} ${y + rtl}
                ${rtl > 0 ? `Q ${x} ${y} ${x + rtl} ${y}` : `L ${x} ${y}`}
                Z
            `.trim().replace(/\s+/g, " ");
        el.setAttribute("d", d);
        g.append(el);
      }
    }
    return g;
  }
  static outline(rects, options = {}) {
    const { color = "red", width: strokeWidth = 3, padding = 0, radius = 3 } = options;
    const g = createSVGElement("g");
    g.setAttribute("fill", "none");
    g.setAttribute("stroke", color);
    g.setAttribute("stroke-width", strokeWidth);
    for (const { left, top, height, width } of rects) {
      const el = createSVGElement("rect");
      el.setAttribute("x", left - padding);
      el.setAttribute("y", top - padding);
      el.setAttribute("height", height + padding * 2);
      el.setAttribute("width", width + padding * 2);
      el.setAttribute("rx", radius);
      g.append(el);
    }
    return g;
  }
  static bubble(rects, options = {}) {
    const { color = "#fbbf24", writingMode, opacity = 0.85, size = 20, padding = 10 } = options;
    const isVertical = writingMode === "vertical-rl" || writingMode === "vertical-lr";
    const g = createSVGElement("g");
    g.style.opacity = opacity;
    if (rects.length === 0) return g;
    rects.splice(1);
    const firstRect = rects[0];
    const x = isVertical ? firstRect.right - size + padding : firstRect.right - size + padding;
    const y = isVertical ? firstRect.bottom - size + padding : firstRect.top - size + padding;
    firstRect.top = y - padding;
    firstRect.right = x + size + padding;
    firstRect.bottom = y + size + padding;
    firstRect.left = x - padding;
    const bubble = createSVGElement("path");
    const s = size;
    const r = s * 0.15;
    const d = `
            M ${x + r} ${y}
            h ${s - 2 * r}
            a ${r} ${r} 0 0 1 ${r} ${r}
            v ${s * 0.65 - 2 * r}
            a ${r} ${r} 0 0 1 ${-r} ${r}
            h ${-s * 0.3}
            l ${-s * 0.15} ${s * 0.2}
            l ${s * 0.05} ${-s * 0.2}
            h ${-s * 0.6 + 2 * r}
            a ${r} ${r} 0 0 1 ${-r} ${-r}
            v ${-s * 0.65 + 2 * r}
            a ${r} ${r} 0 0 1 ${r} ${-r}
            z
        `.replace(/\s+/g, " ").trim();
    bubble.setAttribute("d", d);
    bubble.setAttribute("fill", color);
    bubble.setAttribute("stroke", "rgba(0, 0, 0, 0.2)");
    bubble.setAttribute("stroke-width", "1");
    const lineGroup = createSVGElement("g");
    lineGroup.setAttribute("stroke", "rgba(0, 0, 0, 0.3)");
    lineGroup.setAttribute("stroke-width", "1.5");
    lineGroup.setAttribute("stroke-linecap", "round");
    const lineY1 = y + s * 0.18;
    const lineY2 = y + s * 0.33;
    const lineY3 = y + s * 0.48;
    const lineX1 = x + s * 0.2;
    const lineX2 = x + s * 0.8;
    const line1 = createSVGElement("line");
    line1.setAttribute("x1", lineX1);
    line1.setAttribute("y1", lineY1);
    line1.setAttribute("x2", lineX2);
    line1.setAttribute("y2", lineY1);
    const line2 = createSVGElement("line");
    line2.setAttribute("x1", lineX1);
    line2.setAttribute("y1", lineY2);
    line2.setAttribute("x2", lineX2);
    line2.setAttribute("y2", lineY2);
    const line3 = createSVGElement("line");
    line3.setAttribute("x1", lineX1);
    line3.setAttribute("y1", lineY3);
    line3.setAttribute("x2", x + s * 0.6);
    line3.setAttribute("y2", lineY3);
    lineGroup.append(line1, line2, line3);
    if (isVertical) {
      const centerX = x + s / 2;
      const centerY = y + s / 2;
      bubble.setAttribute("transform", `rotate(90 ${centerX} ${centerY})`);
      lineGroup.setAttribute("transform", `rotate(90 ${centerX} ${centerY})`);
    }
    g.append(bubble);
    g.append(lineGroup);
    return g;
  }
  // make an exact copy of an image in the overlay
  // one can then apply filters to the entire element, without affecting them;
  // it's a bit silly and probably better to just invert images twice
  // (though the color will be off in that case if you do heu-rotate)
  static copyImage([rect], options = {}) {
    const { src } = options;
    const image = createSVGElement("image");
    const { left, top, height, width } = rect;
    image.setAttribute("href", src);
    image.setAttribute("x", left);
    image.setAttribute("y", top);
    image.setAttribute("height", height);
    image.setAttribute("width", width);
    return image;
  }
}
_svg = new WeakMap();
_map = new WeakMap();
_doc = new WeakMap();
_clipPath = new WeakMap();
_clipPathPath = new WeakMap();
_clipPathId = new WeakMap();
_Overlayer_instances = new WeakSet();
zoom_get = function() {
  if (/^((?!chrome|android).)*AppleWebKit/i.test(navigator.userAgent) && !window.chrome) {
    return window.getComputedStyle(__privateGet(this, _doc).body).zoom || 1;
  }
  return 1;
};
// Split a range into per-text-node sub-ranges (plus replaced elements
// like images), so `getClientRects()` only ever returns line-level boxes.
// Collecting rects on the whole range would also include the border boxes
// of fully contained block elements, over-highlighting blank space.
splitRange_fn = function(range) {
  const ancestor = range.commonAncestorContainer;
  if (ancestor.nodeType !== Node.ELEMENT_NODE && ancestor.nodeType !== Node.DOCUMENT_NODE) return [range];
  const doc = ancestor.ownerDocument ?? ancestor;
  let past = false;
  const walker = doc.createTreeWalker(
    ancestor,
    NodeFilter.SHOW_TEXT | NodeFilter.SHOW_ELEMENT,
    {
      acceptNode: (node) => {
        var _a, _b;
        if (range.comparePoint(node, 0) > 0) {
          past = true;
          return NodeFilter.FILTER_ACCEPT;
        }
        if (!range.intersectsNode(node)) return NodeFilter.FILTER_REJECT;
        const el = node.nodeType === Node.TEXT_NODE ? node.parentElement : node;
        if ((_a = el == null ? void 0 : el.closest) == null ? void 0 : _a.call(el, "rt, rp, rtc, [cfi-inert]"))
          return NodeFilter.FILTER_REJECT;
        if (node.nodeType === Node.TEXT_NODE) return NodeFilter.FILTER_ACCEPT;
        return ((_b = node.matches) == null ? void 0 : _b.call(node, "img, svg")) ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_SKIP;
      }
    }
  );
  const { startContainer, startOffset } = range;
  const start = startContainer.nodeType === Node.TEXT_NODE || startContainer.nodeType === Node.CDATA_SECTION_NODE ? startContainer : startContainer.childNodes[startOffset];
  if (start && start !== ancestor && ancestor.contains(start)) {
    let before = start.previousSibling;
    if (before) while (before.lastChild) before = before.lastChild;
    walker.currentNode = before ?? start.parentNode;
  }
  const splitRanges = [];
  for (let node = walker.nextNode(); node && !past; node = walker.nextNode()) {
    const subRange = doc.createRange();
    if (node.nodeType === Node.TEXT_NODE) {
      subRange.selectNodeContents(node);
      if (subRange.compareBoundaryPoints(Range.START_TO_START, range) < 0) {
        subRange.setStart(range.startContainer, range.startOffset);
      }
      if (subRange.compareBoundaryPoints(Range.END_TO_END, range) > 0) {
        subRange.setEnd(range.endContainer, range.endOffset);
      }
    } else subRange.selectNode(node);
    splitRanges.push(subRange);
  }
  return splitRanges.length === 0 ? [range] : splitRanges;
};
getRects_fn = function(range) {
  const zoom = __privateGet(this, _Overlayer_instances, zoom_get);
  const root = __privateGet(this, _doc).documentElement.getBoundingClientRect();
  const rects = [];
  for (const subRange of __privateMethod(this, _Overlayer_instances, splitRange_fn).call(this, range)) {
    for (const rect of subRange.getClientRects()) {
      const scaled = {
        left: rect.left * zoom,
        top: rect.top * zoom,
        right: rect.right * zoom,
        bottom: rect.bottom * zoom,
        width: rect.width * zoom,
        height: rect.height * zoom
      };
      scaled.page = pageOf(root, scaled);
      rects.push(scaled);
    }
  }
  return rects;
};
export {
  Overlayer
};
