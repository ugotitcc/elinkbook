const findIndices = (arr, f) => arr.map((x, i, a) => f(x, i, a) ? i : null).filter((x) => x != null);
const splitAt = (arr, is) => [-1, ...is, arr.length].reduce(({ xs, a }, b) => ({ xs: (xs == null ? void 0 : xs.concat([arr.slice(a + 1, b)])) ?? [], a: b }), {}).xs;
const concatArrays = (a, b) => a.slice(0, -1).concat([a[a.length - 1].concat(b[0])]).concat(b.slice(1));
const isNumber = /\d/;
const isCFI = /^epubcfi\((.*)\)$/;
const escapeCFI = (str) => str.replace(/[\^[\](),;=]/g, "^$&");
const wrap = (x) => isCFI.test(x) ? x : `epubcfi(${x})`;
const unwrap = (x) => {
  var _a;
  return ((_a = x.match(isCFI)) == null ? void 0 : _a[1]) ?? x;
};
const lift = (f) => (...xs) => `epubcfi(${f(...xs.map((x) => {
  var _a;
  return ((_a = x.match(isCFI)) == null ? void 0 : _a[1]) ?? x;
}))})`;
const joinIndir = lift((...xs) => xs.join("!"));
const tokenizer = (str) => {
  const tokens = [];
  let state, escape, value = "";
  const push = (x) => (tokens.push(x), state = null, value = "");
  const cat = (x) => (value += x, escape = false);
  for (const char of Array.from(str.trim()).concat("")) {
    if (char === "^" && !escape) {
      escape = true;
      continue;
    }
    if (state === "!") push(["!"]);
    else if (state === ",") push([","]);
    else if (state === "/" || state === ":") {
      if (isNumber.test(char)) {
        cat(char);
        continue;
      } else push([state, parseInt(value)]);
    } else if (state === "~") {
      if (isNumber.test(char) || char === ".") {
        cat(char);
        continue;
      } else push(["~", parseFloat(value)]);
    } else if (state === "@") {
      if (char === ":") {
        push(["@", parseFloat(value)]);
        state = "@";
        continue;
      }
      if (isNumber.test(char) || char === ".") {
        cat(char);
        continue;
      } else push(["@", parseFloat(value)]);
    } else if (state === "[") {
      if (char === ";" && !escape) {
        push(["[", value]);
        state = ";";
      } else if (char === "," && !escape) {
        push(["[", value]);
        state = "[";
      } else if (char === "]" && !escape) push(["[", value]);
      else cat(char);
      continue;
    } else if (state == null ? void 0 : state.startsWith(";")) {
      if (char === "=" && !escape) {
        state = `;${value}`;
        value = "";
      } else if (char === ";" && !escape) {
        push([state, value]);
        state = ";";
      } else if (char === "]" && !escape) push([state, value]);
      else cat(char);
      continue;
    }
    if (char === "/" || char === ":" || char === "~" || char === "@" || char === "[" || char === "!" || char === ",") state = char;
  }
  return tokens;
};
const findTokens = (tokens, x) => findIndices(tokens, ([t]) => t === x);
const parser = (tokens) => {
  const parts = [];
  let state;
  for (const [type, val] of tokens) {
    if (type === "/") parts.push({ index: val });
    else {
      const last = parts[parts.length - 1];
      if (type === ":") last.offset = val;
      else if (type === "~") last.temporal = val;
      else if (type === "@") last.spatial = (last.spatial ?? []).concat(val);
      else if (type === ";s") last.side = val;
      else if (type === "[") {
        if (state === "/" && val) last.id = val;
        else {
          last.text = (last.text ?? []).concat(val);
          continue;
        }
      }
    }
    state = type;
  }
  return parts;
};
const parserIndir = (tokens) => splitAt(tokens, findTokens(tokens, "!")).map(parser);
const parse = (cfi) => {
  const tokens = tokenizer(unwrap(cfi));
  const commas = findTokens(tokens, ",");
  if (!commas.length) return parserIndir(tokens);
  const [parent, start, end] = splitAt(tokens, commas).map(parserIndir);
  return { parent, start, end };
};
const partToString = ({ index, id, offset, temporal, spatial, text, side }) => {
  var _a;
  const param = side ? `;s=${side}` : "";
  return `/${index}` + (id ? `[${escapeCFI(id)}${param}]` : "") + (offset != null && index % 2 ? `:${offset}` : "") + (temporal ? `~${temporal}` : "") + (spatial ? `@${spatial.join(":")}` : "") + (text || !id && side ? "[" + (((_a = text == null ? void 0 : text.map(escapeCFI)) == null ? void 0 : _a.join(",")) ?? "") + param + "]" : "");
};
const toInnerString = (parsed) => parsed.parent ? [parsed.parent, parsed.start, parsed.end].map(toInnerString).join(",") : parsed.map((parts) => parts.map(partToString).join("")).join("!");
const toString = (parsed) => wrap(toInnerString(parsed));
const collapse = (x, toEnd) => typeof x === "string" ? toString(collapse(parse(x), toEnd)) : x.parent ? concatArrays(x.parent, x[toEnd ? "end" : "start"]) : x;
const buildRange = (from, to) => {
  if (typeof from === "string") from = parse(from);
  if (typeof to === "string") to = parse(to);
  from = collapse(from);
  to = collapse(to, true);
  const localFrom = from[from.length - 1], localTo = to[to.length - 1];
  const localParent = [], localStart = [], localEnd = [];
  let pushToParent = true;
  const len = Math.max(localFrom.length, localTo.length);
  for (let i = 0; i < len; i++) {
    const a = localFrom[i], b = localTo[i];
    pushToParent && (pushToParent = (a == null ? void 0 : a.index) === (b == null ? void 0 : b.index) && !(a == null ? void 0 : a.offset) && !(b == null ? void 0 : b.offset));
    if (pushToParent) localParent.push(a);
    else {
      if (a) localStart.push(a);
      if (b) localEnd.push(b);
    }
  }
  const parent = from.slice(0, -1).concat([localParent]);
  return toString({ parent, start: [localStart], end: [localEnd] });
};
const compare = (a, b) => {
  if (typeof a === "string") a = parse(a);
  if (typeof b === "string") b = parse(b);
  if (a.start || b.start) return compare(collapse(a), collapse(b)) || compare(collapse(a, true), collapse(b, true));
  for (let i = 0; i < Math.max(a.length, b.length); i++) {
    const p = a[i] ?? [], q = b[i] ?? [];
    const maxIndex = Math.max(p.length, q.length) - 1;
    for (let i2 = 0; i2 <= maxIndex; i2++) {
      const x = p[i2], y = q[i2];
      if (!x) return -1;
      if (!y) return 1;
      if (x.index > y.index) return 1;
      if (x.index < y.index) return -1;
      if (i2 === maxIndex) {
        if (x.offset > y.offset) return 1;
        if (x.offset < y.offset) return -1;
      }
    }
  }
  return 0;
};
const isTextNode = (node) => (node == null ? void 0 : node.nodeType) === 3 || (node == null ? void 0 : node.nodeType) === 4;
const isElementNode = (node) => (node == null ? void 0 : node.nodeType) === 1;
const isInertNode = (node) => {
  var _a;
  return (_a = node.hasAttribute) == null ? void 0 : _a.call(node, "cfi-inert");
};
const isSkipNode = (node) => {
  var _a;
  return (_a = node.hasAttribute) == null ? void 0 : _a.call(node, "cfi-skip");
};
const rawChildNodes = (node, nodes = []) => {
  for (let child = node.firstChild; child; child = child.nextSibling) {
    if (!isTextNode(child) && !isElementNode(child)) continue;
    if (isInertNode(child)) continue;
    if (isSkipNode(child)) rawChildNodes(child, nodes);
    else nodes.push(child);
  }
  return nodes;
};
const getChildNodes = (node, filter) => {
  const nodes = rawChildNodes(node);
  return filter ? nodes.map((node2) => {
    const accept = filter(node2);
    if (accept === NodeFilter.FILTER_REJECT) return null;
    else if (accept === NodeFilter.FILTER_SKIP) return getChildNodes(node2, filter);
    else return node2;
  }).flat().filter((x) => x) : nodes;
};
const indexChildNodes = (node, filter) => {
  const children = getChildNodes(node, filter);
  const nodes = ["before"];
  if (isElementNode(children[0])) nodes.push("first");
  let last;
  for (const child of children) {
    if (last === void 0) nodes.push(child);
    else if (isTextNode(child)) {
      if (Array.isArray(last)) last.push(child);
      else if (isTextNode(last)) nodes[nodes.length - 1] = [last, child];
      else nodes.push(child);
    } else {
      if (isElementNode(last)) nodes.push(null, child);
      else nodes.push(child);
    }
    last = nodes[nodes.length - 1];
  }
  if (isElementNode(children[children.length - 1])) nodes.push("last");
  nodes.push("after");
  return nodes;
};
const partsToNode = (node, parts, filter) => {
  const { id } = parts[parts.length - 1];
  if (id) {
    const el = node.ownerDocument.getElementById(id);
    if (el) return { node: el, offset: 0 };
  }
  for (const { index } of parts) {
    const newNode = node ? indexChildNodes(node, filter)[index] : null;
    if (newNode === "first") return { node: node.firstChild ?? node };
    if (newNode === "last") return { node: node.lastChild ?? node };
    if (newNode === "before") return { node, before: true };
    if (newNode === "after") return { node, after: true };
    node = newNode;
  }
  const { offset } = parts[parts.length - 1];
  if (!Array.isArray(node)) return { node, offset };
  let sum = 0;
  for (const n of node) {
    const { length } = n.nodeValue;
    if (sum + length >= offset) return { node: n, offset: offset - sum };
    sum += length;
  }
};
const nodeToParts = (node, offset, filter) => {
  const { id } = node;
  let parentNode = node.parentNode;
  while (parentNode && isSkipNode(parentNode)) parentNode = parentNode.parentNode;
  const indexed = indexChildNodes(parentNode, filter);
  const index = indexed.findIndex((x) => Array.isArray(x) ? x.some((x2) => x2 === node) : x === node);
  const chunk = indexed[index];
  if (Array.isArray(chunk)) {
    let sum = 0;
    for (const x of chunk) {
      if (x === node) {
        sum += offset;
        break;
      } else sum += x.nodeValue.length;
    }
    offset = sum;
  }
  const part = { id, index, offset };
  return (parentNode !== node.ownerDocument.documentElement ? nodeToParts(parentNode, null, filter).concat(part) : [part]).filter((x) => x.index !== -1);
};
const endInsideChild = (node, offset) => {
  while (isElementNode(node) && offset > 0) {
    const child = node.childNodes[offset - 1];
    if (!(isTextNode(child) || isElementNode(child)) || isInertNode(child)) break;
    node = child;
    offset = isTextNode(child) ? child.nodeValue.length : child.childNodes.length;
  }
  return [node, offset];
};
const fromRange = (range, filter) => {
  const { startContainer, startOffset } = range;
  const start = nodeToParts(startContainer, startOffset, filter);
  if (range.collapsed) return toString([start]);
  const end = nodeToParts(...endInsideChild(range.endContainer, range.endOffset), filter);
  return buildRange([start], [end]);
};
const toRange = (doc, parts, filter) => {
  try {
    const startParts = collapse(parts);
    const endParts = collapse(parts, true);
    const root = doc.documentElement;
    const start = partsToNode(root, startParts[0], filter);
    const end = partsToNode(root, endParts[0], filter);
    if (!(start == null ? void 0 : start.node) || !(end == null ? void 0 : end.node)) return null;
    const range = doc.createRange();
    if (start.before) range.setStartBefore(start.node);
    else if (start.after) range.setStartAfter(start.node);
    else range.setStart(start.node, start.offset);
    if (end.before) range.setEndBefore(end.node);
    else if (end.after) range.setEndAfter(end.node);
    else range.setEnd(end.node, end.offset);
    return range;
  } catch {
    return null;
  }
};
const fromElements = (elements) => {
  const results = [];
  const { parentNode } = elements[0];
  const parts = nodeToParts(parentNode);
  for (const [index, node] of indexChildNodes(parentNode).entries()) {
    const el = elements[results.length];
    if (node === el)
      results.push(toString([parts.concat({ id: el.id, index })]));
  }
  return results;
};
const toElement = (doc, parts) => partsToNode(doc.documentElement, collapse(parts)).node;
const fake = {
  fromIndex: (index) => wrap(`/6/${(index + 1) * 2}`),
  toIndex: (parts) => (parts == null ? void 0 : parts.at(-1).index) / 2 - 1
};
const fromCalibrePos = (pos) => {
  const [parts] = parse(pos);
  const item = parts.shift();
  parts.shift();
  return toString([[{ index: 6 }, item], parts]);
};
const fromCalibreHighlight = ({ spine_index, start_cfi, end_cfi }) => {
  const pre = fake.fromIndex(spine_index) + "!";
  return buildRange(pre + start_cfi.slice(2), pre + end_cfi.slice(2));
};
export {
  buildRange,
  collapse,
  compare,
  fake,
  fromCalibreHighlight,
  fromCalibrePos,
  fromElements,
  fromRange,
  isCFI,
  joinIndir,
  parse,
  toElement,
  toRange,
  toString
};
