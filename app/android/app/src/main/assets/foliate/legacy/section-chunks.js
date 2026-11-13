const CHUNK_ATTRIBUTE = "data-foliate-chunk";
const VOID_ELEMENTS = /* @__PURE__ */ new Set([
  "area",
  "base",
  "br",
  "col",
  "embed",
  "hr",
  "img",
  "input",
  "link",
  "meta",
  "source",
  "track",
  "wbr"
]);
const escapeText = (s) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
const escapeAttr = (s) => s.replace(/&/g, "&amp;").replace(/"/g, "&quot;");
const attrs = (el) => Array.from(el.attributes, (a) => ` ${a.name}="${escapeAttr(a.value)}"`).join("");
const placeholder = (el, chunk) => VOID_ELEMENTS.has(el.localName) ? `<${el.localName} ${CHUNK_ATTRIBUTE}="${chunk}">` : `<${el.localName} ${CHUNK_ATTRIBUTE}="${chunk}"></${el.localName}>`;
const parse = (html) => new DOMParser().parseFromString(html, "text/html");
const isPlaceholder = (el) => el.hasAttribute(CHUNK_ATTRIBUTE);
const isCut = (el) => !isPlaceholder(el) && Array.prototype.some.call(el.children, isPlaceholder);
const topLevel = (doc, node) => {
  let el = (node == null ? void 0 : node.nodeType) === 1 ? node : node == null ? void 0 : node.parentElement;
  while (el && el.parentElement !== doc.body) el = el.parentElement;
  return el;
};
const childIndex = (parent, node) => Array.prototype.indexOf.call(parent.children, node);
const ownChildren = (el) => Array.prototype.filter.call(
  el.children,
  (child) => !child.hasAttribute("cfi-inert")
);
const atPath = (doc, path) => (path == null ? void 0 : path.reduce((el, i) => el && ownChildren(el)[i], doc.body)) ?? null;
const splitSection = (html, count) => {
  const doc = parse(html);
  const { body } = doc;
  const kept = (node) => node.nodeType === 1 || node.nodeType === 3;
  const markupOf = (node) => node.nodeType === 1 ? node.outerHTML : escapeText(node.textContent);
  const top = Array.from(body.childNodes).filter(kept);
  const topMarkup = top.map(markupOf);
  const limit = topMarkup.reduce((sum, s) => sum + s.length, 0) / count;
  const units = [];
  const parts = top.map((node, i) => {
    if (node.nodeType === 1 && topMarkup[i].length > limit && node.firstElementChild) {
      const kids = Array.from(node.childNodes).filter(kept).map((child) => ({ node: child, markup: markupOf(child) }));
      units.push(...kids);
      return {
        node,
        kids,
        open: `<${node.localName}${attrs(node)}>`,
        close: `</${node.localName}>`
      };
    }
    const unit = { node, markup: topMarkup[i] };
    units.push(unit);
    return unit;
  });
  const total = units.reduce((sum, unit) => sum + unit.markup.length, 0);
  const starts = [];
  let size = 0, current = 0;
  for (const unit of units) {
    if (unit.node.nodeType === 1) {
      current = Math.min(count - 1, Math.floor(size / total * count));
      starts[current] ?? (starts[current] = size);
    }
    unit.chunk = current;
    size += unit.markup.length;
  }
  const holderOf = (node, chunk2) => node.nodeType === 1 ? placeholder(node, chunk2) : "";
  for (const unit of units) unit.holder = holderOf(unit.node, unit.chunk);
  const chunkOf = [];
  for (const part of parts) {
    if (part.kids) {
      const kids = part.kids.filter((kid) => kid.node.nodeType === 1);
      part.chunks = new Set(kids.map((kid) => kid.chunk));
      part.holder = holderOf(part.node, kids[0].chunk);
      chunkOf.push(kids.map((kid) => kid.chunk));
    } else if (part.node.nodeType === 1) chunkOf.push(part.chunk);
  }
  const ids = /* @__PURE__ */ new Map();
  const indexOf = /* @__PURE__ */ new Map();
  Array.from(body.children, (el, t) => {
    indexOf.set(el, t);
    if (Array.isArray(chunkOf[t])) Array.from(el.children, (child, c) => indexOf.set(child, c));
  });
  for (const el of body.querySelectorAll("[id]")) {
    if (ids.has(el.id)) continue;
    const t = topLevel(doc, el);
    const path = [indexOf.get(t)];
    if (Array.isArray(chunkOf[path[0]]) && el !== t) {
      let child = el;
      while (child.parentElement !== t) child = child.parentElement;
      path.push(indexOf.get(child));
    }
    ids.set(el.id, path);
  }
  const style = doc.createElement("style");
  style.textContent = `[${CHUNK_ATTRIBUTE}] { display: none !important; }`;
  doc.head.append(style);
  const prefix = `<!DOCTYPE html><html${attrs(doc.documentElement)}>${doc.head.outerHTML}<body${attrs(body)}>`;
  const suffix = "</body></html>";
  for (const unit of units) delete unit.node;
  for (const part of parts) delete part.node;
  const piece = (unit, k) => unit.chunk === k ? unit.markup : unit.holder;
  const chunk = (k) => prefix + parts.map((part) => !part.kids ? piece(part, k) : k < 0 || part.chunks.has(k) ? part.open + part.kids.map((kid) => piece(kid, k)).join("") + part.close : part.holder).join("") + suffix;
  const isEmpty = (k) => starts[k] == null;
  const bounds = (k) => {
    let end = k + 1;
    while (end < count && isEmpty(end)) end++;
    return [starts[k], starts[end] ?? total];
  };
  const atFraction = (f) => {
    const pos = f * total;
    let k = Math.min(count - 1, Math.floor(f * count));
    while (k > 0 && (isEmpty(k) || starts[k] > pos)) k--;
    const [start, end] = bounds(k);
    return { chunk: k, anchor: Math.max(0, Math.min(1, (pos - start) / (end - start))) };
  };
  const fraction = (k, f) => {
    if (isEmpty(k)) return k / count;
    const [start, end] = bounds(k);
    return (start + f * (end - start)) / total;
  };
  let skeleton;
  const getSkeleton = () => {
    if (skeleton) return skeleton;
    skeleton = parse(chunk(-1));
    skeleton.getElementById = (id) => atPath(skeleton, ids.get(id));
    return skeleton;
  };
  let full;
  const getFull = () => {
    let doc2 = full == null ? void 0 : full.deref();
    if (!doc2) full = new WeakRef(doc2 = parse(html));
    return doc2;
  };
  const resolve = (doc2, anchor) => {
    let target;
    try {
      target = anchor(doc2);
    } catch {
      return null;
    }
    if (typeof target === "number") return atFraction(target);
    const container = target == null ? void 0 : target.startContainer;
    const node = container ? container.childNodes[target.startOffset] ?? container : target;
    const el = topLevel(doc2, node);
    if (!el) return null;
    const chunks = chunkOf[childIndex(doc2.body, el)];
    if (!Array.isArray(chunks)) return { chunk: chunks ?? 0 };
    let child = node;
    while (child && child.parentNode !== el) child = child.parentNode;
    while (child && child.nodeType !== 1) child = child.previousSibling;
    return { chunk: chunks[child ? childIndex(el, child) : 0] };
  };
  const locate = (anchor) => typeof anchor === "number" ? atFraction(anchor) : resolve(getSkeleton(), anchor) ?? resolve(getFull(), anchor) ?? { chunk: 0 };
  return { count, chunkOf, chunk, isEmpty, locate, fraction };
};
const adjacentChunkAnchor = (doc, direction) => {
  var _a;
  const pieces = [];
  if (doc.body) ownChildren(doc.body).forEach((el, t) => {
    if (isCut(el)) ownChildren(el).forEach((child, c) => pieces.push([child, [t, c]]));
    else pieces.push([el, [t]]);
  });
  const own = ([el]) => !isPlaceholder(el);
  const edge = direction > 0 ? pieces.findLastIndex(own) : pieces.findIndex(own);
  const path = edge < 0 ? null : (_a = pieces[edge + direction]) == null ? void 0 : _a[1];
  if (!path) return null;
  return (doc2) => {
    let el = atPath(doc2, path);
    if (direction < 0 && el && isCut(el)) el = ownChildren(el).at(-1);
    const range = doc2.createRange();
    range.selectNodeContents(el);
    range.collapse(true);
    return range;
  };
};
export {
  CHUNK_ATTRIBUTE,
  adjacentChunkAnchor,
  splitSection
};
