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
var _entries, _lastMediaOverlayItem, _sectionIndex, _audioIndex, _itemIndex, _audio, _volume, _rate, _state, _MediaOverlay_instances, loadSMIL_fn, activeAudio_get, activeItem_get, error_fn, highlight_fn, unhighlight_fn, play_fn, stop_fn, _uris, _decoders, _algorithms, _cache, _cacheXHTMLContent, _children, _refCount, _loader, _encryption, _EPUB_instances, loadXML_fn, loadOptionalXML_fn;
import * as CFI from "./epubcfi.js";
const NS = {
  CONTAINER: "urn:oasis:names:tc:opendocument:xmlns:container",
  XHTML: "http://www.w3.org/1999/xhtml",
  OPF: "http://www.idpf.org/2007/opf",
  EPUB: "http://www.idpf.org/2007/ops",
  DC: "http://purl.org/dc/elements/1.1/",
  DCTERMS: "http://purl.org/dc/terms/",
  ENC: "http://www.w3.org/2001/04/xmlenc#",
  NCX: "http://www.daisy.org/z3986/2005/ncx/",
  XLINK: "http://www.w3.org/1999/xlink",
  SMIL: "http://www.w3.org/ns/SMIL"
};
const MIME = {
  XML: "application/xml",
  NCX: "application/x-dtbncx+xml",
  XHTML: "application/xhtml+xml",
  HTML: "text/html",
  CSS: "text/css",
  SVG: "image/svg+xml",
  JS: /\/(x-)?(javascript|ecmascript)/
};
const isBrokenXHTML = (doc) => {
  var _a;
  return doc.querySelector("parsererror") || !((_a = doc.documentElement) == null ? void 0 : _a.namespaceURI);
};
const VOID_ELEMENT_RE = /<(meta|link|br|img|hr|input|col|area|base|embed|param|source|track|wbr)(?=[\s/>])((?:[^<>"']|"[^"]*"|'[^']*')*)>/g;
const closeVoidElements = (str) => str.replace(
  VOID_ELEMENT_RE,
  (tag, name, attrs) => attrs.trimEnd().endsWith("/") ? tag : `<${name}${attrs}/>`
);
const parseContentDocument = (parser, str, mediaType) => {
  var _a;
  let doc = parser.parseFromString(str, mediaType);
  if (mediaType !== MIME.XHTML || !isBrokenXHTML(doc)) return { doc, mediaType };
  const repaired = closeVoidElements(str);
  if (repaired !== str) {
    doc = parser.parseFromString(repaired, mediaType);
    if (!isBrokenXHTML(doc)) return { doc, mediaType };
  }
  console.warn(((_a = doc.querySelector("parsererror")) == null ? void 0 : _a.innerText) ?? "Invalid XHTML");
  return { doc: parser.parseFromString(str, MIME.HTML), mediaType: MIME.HTML };
};
const PREFIX = {
  a11y: "http://www.idpf.org/epub/vocab/package/a11y/#",
  dcterms: "http://purl.org/dc/terms/",
  marc: "http://id.loc.gov/vocabulary/",
  media: "http://www.idpf.org/epub/vocab/overlays/#",
  onix: "http://www.editeur.org/ONIX/book/codelists/current.html#",
  rendition: "http://www.idpf.org/vocab/rendition/#",
  schema: "http://schema.org/",
  xsd: "http://www.w3.org/2001/XMLSchema#",
  msv: "http://www.idpf.org/epub/vocab/structure/magazine/#",
  prism: "http://www.prismstandard.org/specifications/3.0/PRISM_CV_Spec_3.0.htm#"
};
const RELATORS = {
  art: "artist",
  aut: "author",
  clr: "colorist",
  edt: "editor",
  ill: "illustrator",
  nrt: "narrator",
  trl: "translator",
  pbl: "publisher"
};
const ONIX5 = {
  "02": "isbn",
  "06": "doi",
  "15": "isbn",
  "26": "doi",
  "34": "issn"
};
const camel = (x) => x.toLowerCase().replace(/[-:](.)/g, (_, g) => g.toUpperCase());
const normalizeWhitespace = (str) => str ? str.replace(/[\t\n\f\r ]+/g, " ").replace(/^[\t\n\f\r ]+/, "").replace(/[\t\n\f\r ]+$/, "") : "";
const filterAttribute = (attr, value, isList) => isList ? (el) => {
  var _a, _b;
  return (_b = (_a = el.getAttribute(attr)) == null ? void 0 : _a.split(/\s/)) == null ? void 0 : _b.includes(value);
} : typeof value === "function" ? (el) => value(el.getAttribute(attr)) : (el) => el.getAttribute(attr) === value;
const getAttributes = (...xs) => (el) => el ? Object.fromEntries(xs.map((x) => [camel(x), el.getAttribute(x)])) : null;
const getElementText = (el) => normalizeWhitespace(el == null ? void 0 : el.textContent);
const childGetter = (doc, ns) => {
  const useNS = doc.lookupNamespaceURI(null) === ns || doc.lookupPrefix(ns);
  const f = useNS ? (el, name) => (el2) => el2.namespaceURI === ns && el2.localName === name : (el, name) => (el2) => el2.localName === name;
  return {
    $: (el, name) => [...el.children].find(f(el, name)),
    $$: (el, name) => [...el.children].filter(f(el, name)),
    $$$: useNS ? (el, name) => [...el.getElementsByTagNameNS(ns, name)] : (el, name) => [...el.getElementsByTagName(name)]
  };
};
const decodeURIPath = (path) => {
  try {
    return decodeURIComponent(path.replace(/%(2f|23)/gi, "%25$1"));
  } catch {
    return path;
  }
};
const resolveURL = (url, relativeTo) => {
  if (isExternal(url)) return url;
  try {
    if (isExternal(relativeTo)) return new URL(url, relativeTo);
    const root = "https://invalid.invalid/";
    const obj = new URL(url, root + relativeTo);
    obj.search = "";
    return decodeURIPath(obj.href.replace(root, ""));
  } catch (e) {
    console.warn(e);
    return url;
  }
};
const isExternal = (uri) => /^(?!blob)\w+:/i.test(uri);
const pathRelative = (from, to) => {
  if (!from) return to;
  const as = from.replace(/\/$/, "").split("/");
  const bs = to.replace(/\/$/, "").split("/");
  const i = (as.length > bs.length ? as : bs).findIndex((_, i2) => as[i2] !== bs[i2]);
  return i < 0 ? "" : Array(as.length - i).fill("..").concat(bs.slice(i)).join("/");
};
const pathDirname = (str) => str.slice(0, str.lastIndexOf("/") + 1);
const mapBounded = async (items, f, limit = 4) => {
  if (!items.length) return [];
  const results = new Array(items.length);
  let next = 0;
  await Promise.all(Array.from(
    { length: Math.min(limit, items.length) },
    async () => {
      while (next < items.length) {
        const i = next++;
        results[i] = await f(items[i], i);
      }
    }
  ));
  return results;
};
const replaceSeries = async (str, regex, f) => {
  const matches = [];
  str.replace(regex, (...args) => (matches.push(args), null));
  const results = await mapBounded(matches, (args) => f(...args));
  return str.replace(regex, () => results.shift());
};
const regexEscape = (str) => str.replace(/[-/\\^$*+?.()|[\]{}]/g, "\\$&");
const tidy = (obj) => {
  for (const [key, val] of Object.entries(obj))
    if (val == null) delete obj[key];
    else if (Array.isArray(val)) {
      obj[key] = val.filter((x) => x).map((x) => typeof x === "object" && !Array.isArray(x) ? tidy(x) : x);
      if (!obj[key].length) delete obj[key];
      else if (obj[key].length === 1) obj[key] = obj[key][0];
    } else if (typeof val === "object") {
      obj[key] = tidy(val);
      if (!Object.keys(val).length) delete obj[key];
    }
  const keys = Object.keys(obj);
  if (keys.length === 1 && keys[0] === "name") return obj[keys[0]];
  return obj;
};
const getPrefixes = (doc) => {
  const map = new Map(Object.entries(PREFIX));
  const value = doc.documentElement.getAttributeNS(NS.EPUB, "prefix") || doc.documentElement.getAttribute("prefix");
  if (value) for (const [, prefix, url] of value.matchAll(/(.+): +(.+)[ \t\r\n]*/g)) map.set(prefix, url);
  return map;
};
const getPropertyURL = (value, prefixes) => {
  if (!value) return null;
  const [a, b] = value.split(":");
  const prefix = b ? a : null;
  const reference = b ? b : a;
  const baseURL = prefixes.get(prefix);
  return baseURL ? baseURL + reference : null;
};
const getCalibreUserMetadata = (metaEls, legacyMeta) => {
  var _a;
  const fromJSON = (x) => (x == null ? void 0 : x.__class__) === "datetime.datetime" ? x.__value__ : x;
  const isEmpty = (value, datatype) => value == null || value === "" || Array.isArray(value) && !value.length || datatype === "datetime" && String(value).startsWith("0101-01-01") || datatype === "rating" && !value;
  const columns = [];
  const add = (key, fm) => {
    if (!(key == null ? void 0 : key.startsWith("#")) || typeof fm !== "object" || !fm) return;
    const datatype = fm.datatype ?? "text";
    const value = fromJSON(fm["#value#"]);
    if (isEmpty(value, datatype)) return;
    const extra = fromJSON(fm["#extra#"]);
    const label = key.slice(1);
    columns.push({
      label,
      name: typeof fm.name === "string" && fm.name ? fm.name : label,
      datatype,
      value,
      ...extra != null ? { extra } : {}
    });
  };
  for (const el of metaEls ?? []) {
    if (((_a = el.getAttribute("property")) == null ? void 0 : _a.toLowerCase()) !== "calibre:user_metadata") continue;
    try {
      for (const [key, fm] of Object.entries(JSON.parse(getElementText(el))))
        add(key, fm);
    } catch {
    }
  }
  if (!columns.length)
    for (const [name, content] of Object.entries(legacyMeta ?? {})) {
      if (!name.startsWith("calibre:user_metadata:")) continue;
      try {
        add(name.slice("calibre:user_metadata:".length), JSON.parse(content));
      } catch {
      }
    }
  return columns.length ? columns : null;
};
const getMetadata = (opf) => {
  var _a, _b, _c, _d, _e, _f, _g, _h, _i, _j, _k, _l, _m, _n, _o, _p, _q, _r, _s, _t, _u, _v, _w;
  const { $ } = childGetter(opf, NS.OPF);
  const $metadata = $(opf.documentElement, "metadata");
  const els = Object.groupBy($metadata.children, (el) => el.namespaceURI === NS.DC ? "dc" : el.namespaceURI === NS.OPF && el.localName === "meta" ? el.hasAttribute("name") ? "legacyMeta" : "meta" : "");
  const baseLang = $metadata.getAttribute("xml:lang") ?? opf.documentElement.getAttribute("xml:lang") ?? "und";
  const prefixes = getPrefixes(opf);
  const parse = (el) => {
    const property = el.getAttribute("property");
    const scheme = el.getAttribute("scheme");
    return {
      property: getPropertyURL(property, prefixes) ?? property,
      scheme: getPropertyURL(scheme, prefixes) ?? scheme,
      lang: el.getAttribute("xml:lang"),
      value: getElementText(el),
      props: getProperties(el),
      // `opf:` attributes from EPUB 2 & EPUB 3.1 (removed in EPUB 3.2)
      attrs: Object.fromEntries(Array.from(el.attributes).filter((attr) => attr.namespaceURI === NS.OPF).map((attr) => [attr.localName, attr.value]))
    };
  };
  const refines = Map.groupBy(els.meta ?? [], (el) => el.getAttribute("refines"));
  const getProperties = (el) => {
    const els2 = refines.get(el ? "#" + el.getAttribute("id") : null);
    if (!els2) return null;
    return Object.groupBy(els2.map(parse), (x) => x.property);
  };
  const dc = Object.fromEntries(Object.entries(Object.groupBy(els.dc || [], (el) => el.localName)).map(([name, els2]) => [name, els2.map(parse)]));
  const properties = getProperties() ?? {};
  const legacyMeta = Object.fromEntries(((_a = els.legacyMeta) == null ? void 0 : _a.map((el) => [el.getAttribute("name"), el.getAttribute("content")])) ?? []);
  const one = (x) => {
    var _a2;
    return (_a2 = x == null ? void 0 : x[0]) == null ? void 0 : _a2.value;
  };
  const prop = (x, p) => {
    var _a2;
    return one((_a2 = x == null ? void 0 : x.props) == null ? void 0 : _a2[p]);
  };
  const makeLanguageMap = (x) => {
    var _a2, _b2;
    if (!x) return null;
    const alts = ((_a2 = x.props) == null ? void 0 : _a2["alternate-script"]) ?? [];
    const altRep = x.attrs["alt-rep"];
    if (!alts.length && (!x.lang || x.lang === baseLang) && !altRep) return x.value;
    const map = { [x.lang ?? baseLang]: x.value };
    if (altRep) map[x.attrs["alt-rep-lang"]] = altRep;
    for (const y of alts) map[_b2 = y.lang] ?? (map[_b2] = y.value);
    return map;
  };
  const makeContributor = (x) => {
    var _a2, _b2, _c2, _d2, _e2;
    return x ? {
      name: makeLanguageMap(x),
      sortAs: makeLanguageMap((_b2 = (_a2 = x.props) == null ? void 0 : _a2["file-as"]) == null ? void 0 : _b2[0]) ?? x.attrs["file-as"],
      role: ((_e2 = (_d2 = (_c2 = x.props) == null ? void 0 : _c2.role) == null ? void 0 : _d2.filter((x2) => x2.scheme === PREFIX.marc + "relators")) == null ? void 0 : _e2.map((x2) => x2.value)) ?? [x.attrs.role],
      code: prop(x, "term") ?? x.attrs.term,
      scheme: prop(x, "authority") ?? x.attrs.authority
    } : null;
  };
  const makeCollection = (x) => {
    var _a2;
    return {
      name: makeLanguageMap(x),
      // NOTE: webpub requires number but EPUB allows values like "2.2.1"
      position: one((_a2 = x.props) == null ? void 0 : _a2["group-position"])
    };
  };
  const makeSeries = (x) => {
    var _a2;
    return {
      name: x.value,
      position: one((_a2 = x.props) == null ? void 0 : _a2["group-position"])
    };
  };
  const makeAltIdentifier = (x) => {
    var _a2;
    const { value } = x;
    if (/^urn:/i.test(value)) return value;
    if (/^doi:/i.test(value)) return `urn:${value}`;
    const type = (_a2 = x.props) == null ? void 0 : _a2["identifier-type"];
    if (!type) {
      const scheme = x.attrs.scheme;
      if (!scheme) return value;
      if (/^(doi|isbn|uuid)$/i.test(scheme)) return `urn:${scheme}:${value}`;
      return { scheme, value };
    }
    if (type.scheme === PREFIX.onix + "codelist5") {
      const nid = ONIX5[type.value];
      if (nid) return `urn:${nid}:${value}`;
    }
    return value;
  };
  const belongsTo = Object.groupBy(
    properties["belongs-to-collection"] ?? [],
    (x) => prop(x, "collection-type") === "series" ? "series" : "collection"
  );
  const mainTitle = ((_b = dc.title) == null ? void 0 : _b.find((x) => prop(x, "title-type") === "main")) ?? ((_c = dc.title) == null ? void 0 : _c[0]);
  const metadata = {
    identifier: getIdentifier(opf),
    title: makeLanguageMap(mainTitle),
    sortAs: makeLanguageMap((_e = (_d = mainTitle == null ? void 0 : mainTitle.props) == null ? void 0 : _d["file-as"]) == null ? void 0 : _e[0]) ?? ((_f = mainTitle == null ? void 0 : mainTitle.attrs) == null ? void 0 : _f["file-as"]) ?? (legacyMeta == null ? void 0 : legacyMeta["calibre:title_sort"]),
    subtitle: (_h = (_g = dc.title) == null ? void 0 : _g.find((x) => prop(x, "title-type") === "subtitle")) == null ? void 0 : _h.value,
    language: (_i = dc.language) == null ? void 0 : _i.map((x) => x.value),
    description: one(dc.description),
    publisher: makeContributor((_j = dc.publisher) == null ? void 0 : _j[0]),
    published: ((_l = (_k = dc.date) == null ? void 0 : _k.find((x) => x.attrs.event === "publication")) == null ? void 0 : _l.value) ?? one(dc.date),
    modified: one(properties[PREFIX.dcterms + "modified"]) ?? ((_n = (_m = dc.date) == null ? void 0 : _m.find((x) => x.attrs.event === "modification")) == null ? void 0 : _n.value),
    subject: (_o = dc.subject) == null ? void 0 : _o.map(makeContributor),
    belongsTo: {
      collection: (_p = belongsTo.collection) == null ? void 0 : _p.map(makeCollection),
      series: ((_q = belongsTo.series) == null ? void 0 : _q.map(makeSeries)) ?? ((legacyMeta == null ? void 0 : legacyMeta["calibre:series"]) ? {
        name: legacyMeta == null ? void 0 : legacyMeta["calibre:series"],
        position: parseFloat(legacyMeta == null ? void 0 : legacyMeta["calibre:series_index"])
      } : null)
    },
    altIdentifier: (_r = dc.identifier) == null ? void 0 : _r.map(makeAltIdentifier),
    source: (_s = dc.source) == null ? void 0 : _s.map(makeAltIdentifier),
    // NOTE: not in webpub schema
    rights: one(dc.rights)
    // NOTE: not in webpub schema
  };
  const remapContributor = (defaultKey) => (x) => {
    var _a2;
    const keys = new Set((_a2 = x.role) == null ? void 0 : _a2.map((role) => RELATORS[role] ?? defaultKey));
    return [keys.size ? keys : [defaultKey], x];
  };
  for (const [keys, val] of [].concat(
    ((_u = (_t = dc.creator) == null ? void 0 : _t.map(makeContributor)) == null ? void 0 : _u.map(remapContributor("author"))) ?? [],
    ((_w = (_v = dc.contributor) == null ? void 0 : _v.map(makeContributor)) == null ? void 0 : _w.map(remapContributor("contributor"))) ?? []
  ))
    for (const key of keys) {
      if (key === "publisher" && metadata.publisher) continue;
      if (metadata[key]) metadata[key].push(val);
      else metadata[key] = [val];
    }
  tidy(metadata);
  if (metadata.altIdentifier === metadata.identifier)
    delete metadata.altIdentifier;
  const calibreColumns = getCalibreUserMetadata(els.meta, legacyMeta);
  if (calibreColumns) metadata.calibreColumns = calibreColumns;
  const rendition = {};
  const media = {};
  for (const [key, val] of Object.entries(properties)) {
    if (key.startsWith(PREFIX.rendition))
      rendition[camel(key.replace(PREFIX.rendition, ""))] = one(val);
    else if (key.startsWith(PREFIX.media))
      media[camel(key.replace(PREFIX.media, ""))] = one(val);
  }
  if (media.duration) media.duration = parseClock(media.duration);
  return { metadata, rendition, media };
};
const parseNav = (doc, resolve = (f) => f) => {
  var _a;
  const { $, $$, $$$ } = childGetter(doc, NS.XHTML);
  const resolveHref = (href) => href ? decodeURI(resolve(href)) : null;
  const parseLI = (getType) => ($li) => {
    var _a2;
    const $a = $($li, "a") ?? $($li, "span");
    const $ol = $($li, "ol");
    const href = resolveHref($a == null ? void 0 : $a.getAttribute("href"));
    const label = getElementText($a) || ($a == null ? void 0 : $a.getAttribute("title"));
    const result = { label, href, subitems: parseOL($ol) };
    if (getType) result.type = (_a2 = $a == null ? void 0 : $a.getAttributeNS(NS.EPUB, "type")) == null ? void 0 : _a2.split(/\s/);
    return result;
  };
  const parseOL = ($ol, getType) => $ol ? $$($ol, "li").map(parseLI(getType)) : null;
  const parseNav2 = ($nav, getType) => parseOL($($nav, "ol"), getType);
  const $$nav = $$$(doc, "nav");
  let toc = null, pageList = null, landmarks = null, others = [];
  for (const $nav of $$nav) {
    const type = ((_a = $nav.getAttributeNS(NS.EPUB, "type")) == null ? void 0 : _a.split(/\s/)) ?? [];
    if (type.includes("toc")) toc ?? (toc = parseNav2($nav));
    else if (type.includes("page-list")) pageList ?? (pageList = parseNav2($nav));
    else if (type.includes("landmarks")) landmarks ?? (landmarks = parseNav2($nav, true));
    else others.push({
      label: getElementText($nav.firstElementChild),
      type,
      list: parseNav2($nav)
    });
  }
  return { toc, pageList, landmarks, others };
};
const parseNCX = (doc, resolve = (f) => f) => {
  const { $, $$ } = childGetter(doc, NS.NCX);
  const resolveHref = (href) => href ? decodeURI(resolve(href)) : null;
  const parseItem = (el) => {
    const $label = $(el, "navLabel");
    const $content = $(el, "content");
    const label = getElementText($label);
    const href = resolveHref($content.getAttribute("src"));
    if (el.localName === "navPoint") {
      const els = $$(el, "navPoint");
      return { label, href, subitems: els.length ? els.map(parseItem) : null };
    }
    return { label, href };
  };
  const parseList = (el, itemName) => $$(el, itemName).map(parseItem);
  const getSingle = (container, itemName) => {
    const $container = $(doc.documentElement, container);
    return $container ? parseList($container, itemName) : null;
  };
  return {
    toc: getSingle("navMap", "navPoint"),
    pageList: getSingle("pageList", "pageTarget"),
    others: $$(doc.documentElement, "navList").map((el) => ({
      label: getElementText($(el, "navLabel")),
      list: parseList(el, "navTarget")
    }))
  };
};
const parseClock = (str) => {
  if (!str) return;
  const parts = str.split(":").map((x2) => parseFloat(x2));
  if (parts.length === 3) {
    const [h, m, s] = parts;
    return h * 60 * 60 + m * 60 + s;
  }
  if (parts.length === 2) {
    const [m, s] = parts;
    return m * 60 + s;
  }
  const [x, unit] = str.split(/(?=[^\d.])/);
  const n = parseFloat(x);
  const f = unit === "h" ? 60 * 60 : unit === "min" ? 60 : unit === "ms" ? 1e-3 : 1;
  return n * f;
};
const IMAGE_EXTENSIONS = ["jpg", "jpeg", "png", "gif", "webp"];
const FONT_EXTENSIONS = ["woff", "woff2", "ttf", "otf"];
const getImageMediaType = (path) => {
  const extension = path.toLowerCase().split(".").pop();
  const mediaTypeMap = {
    "jpg": "image/jpeg",
    "jpeg": "image/jpeg",
    "png": "image/png",
    "gif": "image/gif",
    "webp": "image/webp",
    "svg": "image/svg+xml"
  };
  return mediaTypeMap[extension] || "image/jpeg";
};
const getFontMediaType = (path) => {
  const extension = path.toLowerCase().split(".").pop();
  const mediaTypeMap = {
    "woff": "font/woff",
    "woff2": "font/woff2",
    "ttf": "font/ttf",
    "otf": "font/otf"
  };
  return mediaTypeMap[extension] || "font/ttf";
};
const AUDIO_VIDEO_MEDIA_TYPES = {
  "mp4": "video/mp4",
  "m4v": "video/mp4",
  "webm": "video/webm",
  "ogv": "video/ogg",
  "mov": "video/quicktime",
  "mp3": "audio/mpeg",
  "m4a": "audio/mp4",
  "m4b": "audio/mp4",
  "aac": "audio/aac",
  "oga": "audio/ogg",
  "ogg": "audio/ogg",
  "opus": "audio/ogg",
  "wav": "audio/wav",
  "flac": "audio/flac"
};
const AUDIO_VIDEO_EXTENSIONS = Object.keys(AUDIO_VIDEO_MEDIA_TYPES);
const getAudioVideoMediaType = (path) => AUDIO_VIDEO_MEDIA_TYPES[path.toLowerCase().split(".").pop()];
const UNDECLARED_COVER_RE = /(?:cover|couv)\.(?:jpe?g|png|gif|webp|svg)$/i;
const findUndeclaredCover = (names) => {
  for (const name of names) if (UNDECLARED_COVER_RE.test(name)) return name;
  return null;
};
class MediaOverlay extends EventTarget {
  constructor(book, loadXML) {
    super();
    __privateAdd(this, _MediaOverlay_instances);
    __privateAdd(this, _entries);
    __privateAdd(this, _lastMediaOverlayItem);
    __privateAdd(this, _sectionIndex);
    __privateAdd(this, _audioIndex);
    __privateAdd(this, _itemIndex);
    __privateAdd(this, _audio);
    __privateAdd(this, _volume, 1);
    __privateAdd(this, _rate, 1);
    __privateAdd(this, _state);
    this.book = book;
    this.loadXML = loadXML;
  }
  async start(sectionIndex, filter = () => true) {
    var _a;
    (_a = __privateGet(this, _audio)) == null ? void 0 : _a.pause();
    const section = this.book.sections[sectionIndex];
    const href = section == null ? void 0 : section.id;
    if (!href) return;
    const { mediaOverlay } = section;
    if (!mediaOverlay) return this.start(sectionIndex + 1);
    __privateSet(this, _sectionIndex, sectionIndex);
    await __privateMethod(this, _MediaOverlay_instances, loadSMIL_fn).call(this, mediaOverlay);
    for (let i = 0; i < __privateGet(this, _entries).length; i++) {
      const { items } = __privateGet(this, _entries)[i];
      for (let j = 0; j < items.length; j++) {
        if (items[j].text.split("#")[0] === href && filter(items[j], j, items))
          return __privateMethod(this, _MediaOverlay_instances, play_fn).call(this, i, j).catch((e) => __privateMethod(this, _MediaOverlay_instances, error_fn).call(this, e));
      }
    }
  }
  pause() {
    var _a;
    __privateSet(this, _state, "paused");
    (_a = __privateGet(this, _audio)) == null ? void 0 : _a.pause();
  }
  resume() {
    var _a;
    __privateSet(this, _state, "playing");
    (_a = __privateGet(this, _audio)) == null ? void 0 : _a.play().catch((e) => __privateMethod(this, _MediaOverlay_instances, error_fn).call(this, e));
  }
  stop() {
    __privateSet(this, _state, "stopped");
    __privateMethod(this, _MediaOverlay_instances, stop_fn).call(this);
  }
  prev() {
    if (__privateGet(this, _itemIndex) > 0) __privateMethod(this, _MediaOverlay_instances, play_fn).call(this, __privateGet(this, _audioIndex), __privateGet(this, _itemIndex) - 1);
    else if (__privateGet(this, _audioIndex) > 0) __privateMethod(this, _MediaOverlay_instances, play_fn).call(this, __privateGet(this, _audioIndex) - 1, __privateGet(this, _entries)[__privateGet(this, _audioIndex) - 1].items.length - 1);
    else if (__privateGet(this, _sectionIndex) > 0)
      this.start(__privateGet(this, _sectionIndex) - 1, (_, i, items) => i === items.length - 1);
  }
  next() {
    __privateMethod(this, _MediaOverlay_instances, play_fn).call(this, __privateGet(this, _audioIndex), __privateGet(this, _itemIndex) + 1);
  }
  setVolume(volume) {
    __privateSet(this, _volume, volume);
    if (__privateGet(this, _audio)) __privateGet(this, _audio).volume = volume;
  }
  setRate(rate) {
    __privateSet(this, _rate, rate);
    if (__privateGet(this, _audio)) __privateGet(this, _audio).playbackRate = rate;
  }
}
_entries = new WeakMap();
_lastMediaOverlayItem = new WeakMap();
_sectionIndex = new WeakMap();
_audioIndex = new WeakMap();
_itemIndex = new WeakMap();
_audio = new WeakMap();
_volume = new WeakMap();
_rate = new WeakMap();
_state = new WeakMap();
_MediaOverlay_instances = new WeakSet();
loadSMIL_fn = async function(item) {
  if (__privateGet(this, _lastMediaOverlayItem) === item) return;
  const doc = await this.loadXML(item.href);
  const resolve = (href) => href ? resolveURL(href, item.href) : null;
  const { $, $$$ } = childGetter(doc, NS.SMIL);
  __privateSet(this, _audioIndex, -1);
  __privateSet(this, _itemIndex, -1);
  __privateSet(this, _entries, $$$(doc, "par").reduce((arr, $par) => {
    var _a;
    const text = resolve((_a = $($par, "text")) == null ? void 0 : _a.getAttribute("src"));
    const $audio = $($par, "audio");
    if (!text || !$audio) return arr;
    const src = resolve($audio.getAttribute("src"));
    const begin = parseClock($audio.getAttribute("clipBegin"));
    const end = parseClock($audio.getAttribute("clipEnd"));
    const last = arr.at(-1);
    if ((last == null ? void 0 : last.src) === src) last.items.push({ text, begin, end });
    else arr.push({ src, items: [{ text, begin, end }] });
    return arr;
  }, []));
  __privateSet(this, _lastMediaOverlayItem, item);
};
activeAudio_get = function() {
  return __privateGet(this, _entries)[__privateGet(this, _audioIndex)];
};
activeItem_get = function() {
  var _a, _b;
  return (_b = (_a = __privateGet(this, _MediaOverlay_instances, activeAudio_get)) == null ? void 0 : _a.items) == null ? void 0 : _b[__privateGet(this, _itemIndex)];
};
error_fn = function(e) {
  console.error(e);
  this.dispatchEvent(new CustomEvent("error", { detail: e }));
};
highlight_fn = function() {
  this.dispatchEvent(new CustomEvent("highlight", { detail: __privateGet(this, _MediaOverlay_instances, activeItem_get) }));
};
unhighlight_fn = function() {
  this.dispatchEvent(new CustomEvent("unhighlight", { detail: __privateGet(this, _MediaOverlay_instances, activeItem_get) }));
};
play_fn = async function(audioIndex, itemIndex) {
  var _a;
  __privateMethod(this, _MediaOverlay_instances, stop_fn).call(this);
  __privateSet(this, _audioIndex, audioIndex);
  __privateSet(this, _itemIndex, itemIndex);
  const src = (_a = __privateGet(this, _MediaOverlay_instances, activeAudio_get)) == null ? void 0 : _a.src;
  if (!src || !__privateGet(this, _MediaOverlay_instances, activeItem_get)) return this.start(__privateGet(this, _sectionIndex) + 1);
  const url = URL.createObjectURL(await this.book.loadBlob(src));
  const audio = new Audio(url);
  __privateSet(this, _audio, audio);
  audio.volume = __privateGet(this, _volume);
  audio.playbackRate = __privateGet(this, _rate);
  audio.addEventListener("timeupdate", () => {
    var _a2, _b;
    if (audio.paused) return;
    const t = audio.currentTime;
    const { items } = __privateGet(this, _MediaOverlay_instances, activeAudio_get);
    if (t > ((_a2 = __privateGet(this, _MediaOverlay_instances, activeItem_get)) == null ? void 0 : _a2.end)) {
      __privateMethod(this, _MediaOverlay_instances, unhighlight_fn).call(this);
      if (__privateGet(this, _itemIndex) === items.length - 1) {
        __privateMethod(this, _MediaOverlay_instances, play_fn).call(this, __privateGet(this, _audioIndex) + 1, 0).catch((e) => __privateMethod(this, _MediaOverlay_instances, error_fn).call(this, e));
        return;
      }
    }
    const oldIndex = __privateGet(this, _itemIndex);
    while (((_b = items[__privateGet(this, _itemIndex) + 1]) == null ? void 0 : _b.begin) <= t) __privateWrapper(this, _itemIndex)._++;
    if (__privateGet(this, _itemIndex) !== oldIndex) __privateMethod(this, _MediaOverlay_instances, highlight_fn).call(this);
  });
  audio.addEventListener("error", () => __privateMethod(this, _MediaOverlay_instances, error_fn).call(this, new Error(`Failed to load ${src}`)));
  audio.addEventListener("playing", () => __privateMethod(this, _MediaOverlay_instances, highlight_fn).call(this));
  audio.addEventListener("ended", () => {
    __privateMethod(this, _MediaOverlay_instances, unhighlight_fn).call(this);
    URL.revokeObjectURL(url);
    __privateSet(this, _audio, null);
    __privateMethod(this, _MediaOverlay_instances, play_fn).call(this, audioIndex + 1, 0).catch((e) => __privateMethod(this, _MediaOverlay_instances, error_fn).call(this, e));
  });
  if (__privateGet(this, _state) === "paused") {
    __privateMethod(this, _MediaOverlay_instances, highlight_fn).call(this);
    audio.currentTime = __privateGet(this, _MediaOverlay_instances, activeItem_get).begin ?? 0;
  } else audio.addEventListener("canplaythrough", () => {
    audio.currentTime = __privateGet(this, _MediaOverlay_instances, activeItem_get).begin ?? 0;
    __privateSet(this, _state, "playing");
    audio.play().catch((e) => __privateMethod(this, _MediaOverlay_instances, error_fn).call(this, e));
  }, { once: true });
};
stop_fn = function() {
  if (__privateGet(this, _audio)) {
    __privateGet(this, _audio).pause();
    URL.revokeObjectURL(__privateGet(this, _audio).src);
    __privateSet(this, _audio, null);
    __privateMethod(this, _MediaOverlay_instances, unhighlight_fn).call(this);
  }
};
const isUUID = /([0-9a-f]{8})-([0-9a-f]{4})-([0-9a-f]{4})-([0-9a-f]{4})-([0-9a-f]{12})/i;
const getUUID = (opf) => {
  const extractUUID = (el) => {
    const text = getElementText(el);
    const id = text.split(":").slice(-1)[0];
    const match = isUUID.exec(id);
    return match ? match[0] : null;
  };
  const identifiers = Array.from(opf.getElementsByTagNameNS(NS.DC, "identifier"));
  const uniqueIdAttr = opf.documentElement.getAttribute("unique-identifier");
  if (uniqueIdAttr) {
    const el = identifiers.find((el2) => el2.getAttribute("id") === uniqueIdAttr);
    if (el) {
      const uuid = extractUUID(el);
      if (uuid) return uuid;
    }
  }
  for (const el of identifiers) {
    const text = getElementText(el);
    if (/^urn:uuid:/i.test(text)) {
      const uuid = extractUUID(el);
      if (uuid) return uuid;
    }
  }
  for (const el of identifiers) {
    const uuid = extractUUID(el);
    if (uuid) return uuid;
  }
  return "";
};
const getIdentifier = (opf) => getElementText(
  opf.getElementById(opf.documentElement.getAttribute("unique-identifier")) ?? opf.getElementsByTagNameNS(NS.DC, "identifier")[0]
);
const deobfuscate = async (key, length, blob) => {
  const array = new Uint8Array(await blob.slice(0, length).arrayBuffer());
  length = Math.min(length, array.length);
  for (var i = 0; i < length; i++) array[i] = array[i] ^ key[i % key.length];
  return new Blob([array, blob.slice(length)], { type: blob.type });
};
const WebCryptoSHA1 = async (str) => {
  const data = new TextEncoder().encode(str);
  const buffer = await globalThis.crypto.subtle.digest("SHA-1", data);
  return new Uint8Array(buffer);
};
const deobfuscators = (sha1 = WebCryptoSHA1) => ({
  "http://www.idpf.org/2008/embedding": {
    key: (opf) => sha1(getIdentifier(opf).replaceAll(/[\u0020\u0009\u000d\u000a]/g, "")),
    decode: (key, blob) => deobfuscate(key, 1040, blob)
  },
  "http://ns.adobe.com/pdf/enc#RC": {
    key: (opf) => {
      const uuid = getUUID(opf).replaceAll("-", "");
      return Uint8Array.from({ length: 16 }, (_, i) => parseInt(uuid.slice(i * 2, i * 2 + 2), 16));
    },
    decode: (key, blob) => deobfuscate(key, 1024, blob)
  }
});
class Encryption {
  constructor(algorithms) {
    __privateAdd(this, _uris, /* @__PURE__ */ new Map());
    __privateAdd(this, _decoders, /* @__PURE__ */ new Map());
    __privateAdd(this, _algorithms);
    __privateSet(this, _algorithms, algorithms);
  }
  async init(encryption, opf) {
    if (!encryption) return;
    const data = Array.from(
      encryption.getElementsByTagNameNS(NS.ENC, "EncryptedData"),
      (el) => {
        var _a, _b;
        return {
          algorithm: (_a = el.getElementsByTagNameNS(NS.ENC, "EncryptionMethod")[0]) == null ? void 0 : _a.getAttribute("Algorithm"),
          uri: (_b = el.getElementsByTagNameNS(NS.ENC, "CipherReference")[0]) == null ? void 0 : _b.getAttribute("URI")
        };
      }
    );
    for (const { algorithm, uri } of data) {
      if (!__privateGet(this, _decoders).has(algorithm)) {
        const algo = __privateGet(this, _algorithms)[algorithm];
        if (!algo) {
          console.warn("Unknown encryption algorithm");
          continue;
        }
        const key = await algo.key(opf);
        __privateGet(this, _decoders).set(algorithm, (blob) => algo.decode(key, blob));
      }
      __privateGet(this, _uris).set(uri, algorithm);
    }
  }
  getDecoder(uri) {
    return __privateGet(this, _decoders).get(__privateGet(this, _uris).get(uri)) ?? ((x) => x);
  }
}
_uris = new WeakMap();
_decoders = new WeakMap();
_algorithms = new WeakMap();
class Resources {
  constructor({ opf, resolveHref }) {
    var _a, _b, _c, _d, _e;
    this.opf = opf;
    const { $, $$, $$$ } = childGetter(opf, NS.OPF);
    const $manifest = $(opf.documentElement, "manifest");
    const $spine = $(opf.documentElement, "spine");
    const $$itemref = $$($spine, "itemref");
    this.manifest = $$($manifest, "item").map(getAttributes("href", "id", "media-type", "properties", "media-overlay")).map((item) => {
      var _a2, _b2;
      item.href = resolveHref(item.href);
      item.properties = (_a2 = item.properties) == null ? void 0 : _a2.split(/\s/);
      item.mediaType = (_b2 = item.mediaType) == null ? void 0 : _b2.split(";")[0].trim().toLowerCase();
      return item;
    });
    this.manifestById = new Map(this.manifest.map((item) => [item.id, item]));
    this.spine = $$itemref.map(getAttributes("idref", "id", "linear", "properties")).map((item) => {
      var _a2;
      return item.properties = (_a2 = item.properties) == null ? void 0 : _a2.split(/\s/), item;
    });
    this.pageProgressionDirection = $spine.getAttribute("page-progression-direction");
    this.navPath = (_a = this.getItemByProperty("nav")) == null ? void 0 : _a.href;
    this.ncxPath = (_b = this.getItemByID($spine.getAttribute("toc")) ?? this.manifest.find((item) => item.mediaType === MIME.NCX)) == null ? void 0 : _b.href;
    const $guide = $(opf.documentElement, "guide");
    if ($guide) this.guide = $$($guide, "reference").map(getAttributes("type", "title", "href")).map(({ type, title, href }) => ({
      label: title,
      type: type.split(/\s/),
      href: resolveHref(href)
    }));
    const coverMeta = (_c = $$$(opf, "meta").find(filterAttribute("name", "cover"))) == null ? void 0 : _c.getAttribute("content");
    this.cover = this.getItemByProperty("cover-image") ?? this.getItemByID(coverMeta) ?? (coverMeta ? this.getItemByHref(resolveHref(coverMeta)) : null) ?? this.manifest.find((item) => item.id === "cover" && item.mediaType.startsWith("image")) ?? this.manifest.find((item) => item.href.includes("cover") && item.mediaType.startsWith("image")) ?? this.getItemByHref((_e = (_d = this.guide) == null ? void 0 : _d.find((ref) => ref.type.includes("cover"))) == null ? void 0 : _e.href) ?? this.manifest.find((item) => item.mediaType.startsWith("image"));
    this.cfis = CFI.fromElements($$itemref);
  }
  getItemByID(id) {
    return this.manifestById.get(id);
  }
  getItemByHref(href) {
    return this.manifest.find((item) => item.href === href);
  }
  getItemByProperty(prop) {
    return this.manifest.find((item) => {
      var _a;
      return (_a = item.properties) == null ? void 0 : _a.includes(prop);
    });
  }
  resolveCFI(cfi) {
    const parts = CFI.parse(cfi);
    const top = (parts.parent ?? parts).shift();
    let $itemref = CFI.toElement(this.opf, top);
    if ($itemref && $itemref.nodeName !== "idref") {
      top.at(-1).id = null;
      $itemref = CFI.toElement(this.opf, top);
    }
    const idref = $itemref == null ? void 0 : $itemref.getAttribute("idref");
    const index = this.spine.findIndex((item) => item.idref === idref);
    const anchor = (doc) => CFI.toRange(doc, parts);
    return { index, anchor };
  }
}
class Loader {
  constructor({ loadText, loadBlob, resources, entries }) {
    __privateAdd(this, _cache, /* @__PURE__ */ new Map());
    __privateAdd(this, _cacheXHTMLContent, /* @__PURE__ */ new Map());
    __privateAdd(this, _children, /* @__PURE__ */ new Map());
    __privateAdd(this, _refCount, /* @__PURE__ */ new Map());
    __publicField(this, "eventTarget", new EventTarget());
    this.loadText = loadText;
    this.loadBlob = loadBlob;
    this.manifest = resources.manifest;
    this.assets = resources.manifest;
    this.entries = entries;
  }
  async createURL(href, data, type, parent) {
    if (!data) return "";
    const detail = { data, type };
    Object.defineProperty(detail, "name", { value: href });
    const event = new CustomEvent("data", { detail });
    this.eventTarget.dispatchEvent(event);
    const newData = await event.detail.data;
    const newType = await event.detail.type;
    const url = URL.createObjectURL(new Blob([newData], { type: newType }));
    __privateGet(this, _cache).set(href, url);
    __privateGet(this, _refCount).set(href, 1);
    if (newType === MIME.XHTML || newType === MIME.HTML) {
      __privateGet(this, _cacheXHTMLContent).set(url, { href, type: newType, data: newData });
    }
    if (parent) {
      const childList = __privateGet(this, _children).get(parent);
      if (childList) childList.push(href);
      else __privateGet(this, _children).set(parent, [href]);
    }
    return url;
  }
  ref(href, parent) {
    if (!parent) {
      __privateGet(this, _refCount).set(href, __privateGet(this, _refCount).get(href) + 1);
      return __privateGet(this, _cache).get(href);
    }
    const childList = __privateGet(this, _children).get(parent);
    if (!(childList == null ? void 0 : childList.includes(href))) {
      __privateGet(this, _refCount).set(href, __privateGet(this, _refCount).get(href) + 1);
      if (childList) childList.push(href);
      else __privateGet(this, _children).set(parent, [href]);
    }
    return __privateGet(this, _cache).get(href);
  }
  unref(href) {
    if (!__privateGet(this, _refCount).has(href)) return;
    const count = __privateGet(this, _refCount).get(href) - 1;
    if (count < 1) {
      const url = __privateGet(this, _cache).get(href);
      URL.revokeObjectURL(url);
      __privateGet(this, _cache).delete(href);
      __privateGet(this, _cacheXHTMLContent).delete(url);
      __privateGet(this, _refCount).delete(href);
      const childList = __privateGet(this, _children).get(href);
      if (childList) while (childList.length) this.unref(childList.pop());
      __privateGet(this, _children).delete(href);
    } else __privateGet(this, _refCount).set(href, count);
  }
  // load manifest item, recursively loading all resources as needed
  async loadItem(item, parents = []) {
    if (!item) return null;
    const { href, mediaType } = item;
    const isScript = MIME.JS.test(item.mediaType);
    const detail = { type: mediaType, href, isScript, allow: true };
    const event = new CustomEvent("load", { detail });
    this.eventTarget.dispatchEvent(event);
    const { allow, url } = await event.detail;
    if (!allow) return null;
    if (url !== void 0) return url;
    const parent = parents.at(-1);
    if (__privateGet(this, _cache).has(href)) return this.ref(href, parent);
    const shouldReplace = (isScript || [MIME.XHTML, MIME.HTML, MIME.CSS, MIME.SVG].includes(mediaType)) && parents.every((p) => p !== href);
    if (shouldReplace) return this.loadReplaced(item, parents);
    const tryLoadBlob = Promise.resolve().then(() => this.loadBlob(href));
    return this.createURL(href, tryLoadBlob, mediaType, parent);
  }
  async loadItemXHTMLContent(item, parents = []) {
    var _a;
    const url = __privateGet(this, _cache).get(item == null ? void 0 : item.href) ?? await this.loadItem(item, parents);
    if (url) return (_a = __privateGet(this, _cacheXHTMLContent).get(url)) == null ? void 0 : _a.data;
  }
  tryImageEntryItem(path) {
    if (!IMAGE_EXTENSIONS.some((ext) => path.toLowerCase().endsWith(`.${ext}`))) {
      return null;
    }
    if (!this.entries.get(path)) {
      return null;
    }
    return {
      href: path,
      mediaType: getImageMediaType(path)
    };
  }
  tryFontEntryItem(path) {
    if (!FONT_EXTENSIONS.some((ext) => path.toLowerCase().endsWith(`.${ext}`))) {
      return null;
    }
    if (this.entries.get(path)) {
      return {
        href: path,
        mediaType: getFontMediaType(path)
      };
    }
    return {
      href: `fonts/${path.split("/").pop()}`,
      mediaType: getFontMediaType(path)
    };
  }
  // Builders like epubBuilder (cnepub) ship audio and video in the container
  // but never declare them in the manifest, the same way they leave out the
  // illustrations. A relative href can't resolve against the section's
  // `blob:` URL, so the media element would otherwise end up with no source.
  tryAudioVideoEntryItem(path) {
    if (!AUDIO_VIDEO_EXTENSIONS.some((ext) => path.toLowerCase().endsWith(`.${ext}`))) {
      return null;
    }
    if (!this.entries.get(path)) {
      return null;
    }
    return {
      href: path,
      mediaType: getAudioVideoMediaType(path)
    };
  }
  async loadHref(href, base, parents = []) {
    if (isExternal(href)) return href;
    const path = resolveURL(href, base);
    let item = this.manifest.find((item2) => item2.href === path);
    if (!item) {
      item = this.tryImageEntryItem(path) ?? this.tryFontEntryItem(path) ?? this.tryAudioVideoEntryItem(path);
      if (!item) {
        return href;
      }
    }
    return this.loadItem(item, parents.concat(base));
  }
  async loadReplaced(item, parents = []) {
    const { href, mediaType } = item;
    const parent = parents.at(-1);
    let str = "";
    try {
      str = await this.loadText(href);
    } catch (e) {
      return this.createURL(href, Promise.reject(e), mediaType, parent);
    }
    if (!str) return null;
    if ([MIME.XHTML, MIME.HTML, MIME.SVG].includes(mediaType)) {
      const parsed = parseContentDocument(new DOMParser(), str, mediaType);
      const doc = parsed.doc;
      item.mediaType = parsed.mediaType;
      if ([MIME.XHTML, MIME.SVG].includes(item.mediaType)) {
        let child = doc.firstChild;
        while (child instanceof ProcessingInstruction) {
          if (child.data) {
            const replacedData = await replaceSeries(
              child.data,
              /(?:^|\s*)(href\s*=\s*['"])([^'"]*)(['"])/i,
              (_, p1, p2, p3) => this.loadHref(p2, href, parents).then((p22) => `${p1}${p22}${p3}`)
            );
            child.replaceWith(doc.createProcessingInstruction(
              child.target,
              replacedData
            ));
          }
          child = child.nextSibling;
        }
      }
      await mapBounded([...doc.querySelectorAll("img[src]")], async (el) => {
        const slim = el.getAttribute("src").replace(/(\.\w+)$/, "~slim$1");
        const url = await this.loadHref(slim, href, parents);
        if (url !== slim) el.setAttribute("data-duokan-slim-src", url);
      });
      const replace = async (el, attr) => el.setAttribute(
        attr,
        await this.loadHref(el.getAttribute(attr), href, parents)
      );
      const attrTasks = [
        [...doc.querySelectorAll("link[href]")].map((el) => [el, "href"]),
        [...doc.querySelectorAll("[src]")].map((el) => [el, "src"]),
        [...doc.querySelectorAll("[poster]")].map((el) => [el, "poster"]),
        [...doc.querySelectorAll("object[data]")].map((el) => [el, "data"])
      ].flat();
      await mapBounded(attrTasks, ([el, attr]) => replace(el, attr));
      await mapBounded(
        [...doc.querySelectorAll("[*|href]:not([href])")],
        async (el) => el.setAttributeNS(NS.XLINK, "href", await this.loadHref(
          el.getAttributeNS(NS.XLINK, "href"),
          href,
          parents
        ))
      );
      await mapBounded(
        [...doc.querySelectorAll("[srcset]")],
        async (el) => el.setAttribute("srcset", await replaceSeries(
          el.getAttribute("srcset"),
          /(\s*)(.+?)\s*((?:\s[\d.]+[wx])+\s*(?:,|$)|,\s+|$)/g,
          (_, p1, p2, p3) => this.loadHref(p2, href, parents).then((p22) => `${p1}${p22}${p3}`)
        ))
      );
      await mapBounded([...doc.querySelectorAll("style")], async (el) => {
        if (el.textContent) el.textContent = await this.replaceCSS(el.textContent, href, parents);
      });
      await mapBounded(
        [...doc.querySelectorAll("[style]")],
        async (el) => el.setAttribute(
          "style",
          await this.replaceCSS(el.getAttribute("style"), href, parents)
        )
      );
      const result2 = new XMLSerializer().serializeToString(doc);
      return this.createURL(href, result2, item.mediaType, parent);
    }
    const result = mediaType === MIME.CSS ? await this.replaceCSS(str, href, parents) : await this.replaceString(str, href, parents);
    return this.createURL(href, result, mediaType, parent);
  }
  async replaceCSS(str, href, parents = []) {
    const replacedUrls = await replaceSeries(
      str,
      /url\(\s*["']?([^'"\n]*?)\s*["']?\s*\)/gi,
      (_, url) => this.loadHref(url, href, parents).then((url2) => `url("${url2}")`)
    );
    return replaceSeries(
      replacedUrls,
      /@import\s*["']([^"'\n]*?)["']/gi,
      (_, url) => this.loadHref(url, href, parents).then((url2) => `@import "${url2}"`)
    );
  }
  // find & replace all possible relative paths for all assets without parsing
  replaceString(str, href, parents = []) {
    const assetMap = /* @__PURE__ */ new Map();
    const urls = this.assets.map((asset) => {
      if (asset.href === href) return;
      const relative = pathRelative(pathDirname(href), asset.href);
      const relativeEnc = encodeURI(relative);
      const rootRelative = "/" + asset.href;
      const rootRelativeEnc = encodeURI(rootRelative);
      const set = /* @__PURE__ */ new Set([relative, relativeEnc, rootRelative, rootRelativeEnc]);
      for (const url of set) assetMap.set(url, asset);
      return Array.from(set);
    }).flat().filter((x) => x);
    if (!urls.length) return str;
    const regex = new RegExp(urls.map(regexEscape).join("|"), "g");
    return replaceSeries(str, regex, async (match) => this.loadItem(
      assetMap.get(match.replace(/^\//, "")),
      parents.concat(href)
    ));
  }
  unloadItem(item) {
    this.unref(item == null ? void 0 : item.href);
  }
  destroy() {
    for (const url of __privateGet(this, _cache).values()) URL.revokeObjectURL(url);
  }
}
_cache = new WeakMap();
_cacheXHTMLContent = new WeakMap();
_children = new WeakMap();
_refCount = new WeakMap();
const getHTMLFragment = (doc, id) => doc.getElementById(id) ?? doc.querySelector(`[name="${CSS.escape(id)}"]`);
const getPageSpread = (properties) => {
  for (const p of properties) {
    if (p === "page-spread-left" || p === "rendition:page-spread-left")
      return "left";
    if (p === "page-spread-right" || p === "rendition:page-spread-right")
      return "right";
    if (p === "rendition:page-spread-center") return "center";
  }
};
const getDisplayOptions = (doc) => {
  if (!doc) return null;
  return {
    fixedLayout: getElementText(doc.querySelector('option[name="fixed-layout"]')),
    openToSpread: getElementText(doc.querySelector('option[name="open-to-spread"]'))
  };
};
const xmlNamedEntities = {
  nbsp: "&#160;",
  mdash: "&#8212;",
  ndash: "&#8211;",
  ldquo: "&#8220;",
  rdquo: "&#8221;",
  lsquo: "&#8216;",
  rsquo: "&#8217;",
  hellip: "&#8230;",
  copy: "&#169;",
  reg: "&#174;",
  trade: "&#8482;",
  bull: "&#8226;",
  middot: "&#183;"
};
const sanitizeXMLEntities = (str) => str.replace(/&([a-z]+);/gi, (match, entity) => xmlNamedEntities[entity.toLowerCase()] ?? match).replace(/&(?!#\d+;|#x[0-9a-f]+;|[a-z][a-z0-9]*;)/gi, "&amp;");
class EPUB {
  constructor({ entries, loadText, loadBlob, getSize, sha1 }) {
    __privateAdd(this, _EPUB_instances);
    __publicField(this, "parser", new DOMParser());
    __privateAdd(this, _loader);
    __privateAdd(this, _encryption);
    this.entries = entries.reduce((map, entry) => {
      map.set(entry.filename, entry);
      return map;
    }, /* @__PURE__ */ new Map());
    this.loadText = loadText;
    this.loadBlob = loadBlob;
    this.getSize = getSize;
    __privateSet(this, _encryption, new Encryption(deobfuscators(sha1)));
  }
  async init() {
    var _a, _b;
    const $container = await __privateMethod(this, _EPUB_instances, loadXML_fn).call(this, "META-INF/container.xml");
    if (!$container) throw new Error("Failed to load container file");
    const opfs = Array.from(
      $container.getElementsByTagNameNS(NS.CONTAINER, "rootfile"),
      getAttributes("full-path", "media-type")
    ).filter((file) => file.mediaType === "application/oebps-package+xml");
    if (!opfs.length) throw new Error("No package document defined in container");
    const opfPath = opfs[0].fullPath;
    const opf = await __privateMethod(this, _EPUB_instances, loadXML_fn).call(this, opfPath);
    if (!opf) throw new Error("Failed to load package document");
    const $encryption = await __privateMethod(this, _EPUB_instances, loadXML_fn).call(this, "META-INF/encryption.xml");
    await __privateGet(this, _encryption).init($encryption, opf);
    this.resources = new Resources({
      opf,
      resolveHref: (url) => resolveURL(url, opfPath)
    });
    __privateSet(this, _loader, new Loader({
      loadText: this.loadText,
      loadBlob: (uri) => Promise.resolve(this.loadBlob(uri)).then(__privateGet(this, _encryption).getDecoder(uri)),
      resources: this.resources,
      entries: this.entries
    }));
    this.transformTarget = __privateGet(this, _loader).eventTarget;
    this.sections = this.resources.spine.map((spineItem, index) => {
      const { idref, linear, properties = [] } = spineItem;
      const item = this.resources.getItemByID(idref);
      if (!item) {
        console.warn(`Could not find item with ID "${idref}" in manifest`);
        return null;
      }
      return {
        id: item.href,
        load: () => __privateGet(this, _loader).loadItem(item),
        unload: () => __privateGet(this, _loader).unloadItem(item),
        loadText: () => __privateGet(this, _loader).loadText(item.href),
        loadContent: () => __privateGet(this, _loader).loadItemXHTMLContent(item),
        // Load a resource a script references after the section was
        // rendered (a <video src> built on click); `loadReplaced` only
        // saw what was in the markup. The section is its parent, so it
        // is released together with the section.
        loadHref: (href) => __privateGet(this, _loader).loadHref(href, item.href),
        createDocument: () => this.loadDocument(item),
        size: this.getSize(item.href),
        cfi: this.resources.cfis[index],
        linear,
        spineProperties: properties,
        pageSpread: getPageSpread(properties),
        resolveHref: (href) => resolveURL(href, item.href),
        mediaOverlay: item.mediaOverlay ? this.resources.getItemByID(item.mediaOverlay) : null
      };
    }).filter((s) => s);
    const { navPath, ncxPath } = this.resources;
    if (navPath) try {
      const resolve = (url) => resolveURL(url, navPath);
      const nav = parseNav(await __privateMethod(this, _EPUB_instances, loadXML_fn).call(this, navPath), resolve);
      this.toc = nav.toc;
      this.pageList = nav.pageList;
      this.landmarks = nav.landmarks;
    } catch (e) {
      console.warn(e);
    }
    const hasNavigableHref = (items) => Array.isArray(items) && items.some(
      (it) => it && (it.href || hasNavigableHref(it.subitems))
    );
    if (!hasNavigableHref(this.toc) && ncxPath) try {
      const resolve = (url) => resolveURL(url, ncxPath);
      const ncx = parseNCX(await __privateMethod(this, _EPUB_instances, loadXML_fn).call(this, ncxPath), resolve);
      this.toc = ncx.toc;
      this.pageList = ncx.pageList;
    } catch (e) {
      console.warn(e);
    }
    this.landmarks ?? (this.landmarks = this.resources.guide);
    const { metadata, rendition, media } = getMetadata(opf);
    this.metadata = metadata;
    this.rendition = rendition;
    this.media = media;
    this.dir = this.resources.pageProgressionDirection;
    const displayOptions = getDisplayOptions(
      await __privateMethod(this, _EPUB_instances, loadOptionalXML_fn).call(this, "META-INF/com.apple.ibooks.display-options.xml") ?? await __privateMethod(this, _EPUB_instances, loadOptionalXML_fn).call(this, "META-INF/com.kobobooks.display-options.xml")
    );
    if (displayOptions) {
      if (displayOptions.fixedLayout === "true")
        (_a = this.rendition).layout ?? (_a.layout = "pre-paginated");
      if (displayOptions.openToSpread === "false") (_b = this.sections.find((section) => section.linear !== "no")).pageSpread ?? (_b.pageSpread = this.dir === "rtl" ? "left" : "right");
    }
    return this;
  }
  async loadDocument(item) {
    const str = await this.loadText(item.href) ?? "";
    return parseContentDocument(this.parser, str, item.mediaType).doc;
  }
  getMediaOverlay() {
    return new MediaOverlay(this, __privateMethod(this, _EPUB_instances, loadXML_fn).bind(this));
  }
  resolveCFI(cfi) {
    return this.resources.resolveCFI(cfi);
  }
  resolveHref(href) {
    const [path, hash] = href.split("#");
    const item = this.resources.getItemByHref(decodeURI(path));
    if (!item) return null;
    const index = this.resources.spine.findIndex(({ idref }) => idref === item.id);
    const anchor = hash ? (doc) => getHTMLFragment(doc, hash) : () => 0;
    return { index, anchor };
  }
  splitTOCHref(href) {
    return (href == null ? void 0 : href.split("#")) ?? [];
  }
  getTOCFragment(doc, id) {
    return doc.getElementById(id) ?? doc.querySelector(`[name="${CSS.escape(id)}"]`);
  }
  isExternal(uri) {
    return isExternal(uri);
  }
  async getCover() {
    var _a;
    const cover = (_a = this.resources) == null ? void 0 : _a.cover;
    if (cover == null ? void 0 : cover.href) return new Blob(
      [await this.loadBlob(cover.href)],
      { type: cover.mediaType }
    );
    const href = findUndeclaredCover(this.entries.keys());
    if (!href) return null;
    const blob = await this.loadBlob(href);
    return blob ? new Blob([blob], { type: getImageMediaType(href) }) : null;
  }
  async getCalibreBookmarks() {
    const txt = await this.loadText("META-INF/calibre_bookmarks.txt");
    const magic = "encoding=json+base64:";
    if (txt == null ? void 0 : txt.startsWith(magic)) {
      const json = atob(txt.slice(magic.length));
      return JSON.parse(json);
    }
  }
  destroy() {
    var _a;
    (_a = __privateGet(this, _loader)) == null ? void 0 : _a.destroy();
  }
}
_loader = new WeakMap();
_encryption = new WeakMap();
_EPUB_instances = new WeakSet();
loadXML_fn = async function(uri) {
  const str = await this.loadText(uri);
  if (!str) return null;
  const sanitized = sanitizeXMLEntities(str);
  const doc = this.parser.parseFromString(sanitized, MIME.XML);
  if (doc.querySelector("parsererror"))
    throw new Error(`XML parsing error: ${uri}
${doc.querySelector("parsererror").innerText}`);
  return doc;
};
loadOptionalXML_fn = async function(uri) {
  try {
    return await __privateMethod(this, _EPUB_instances, loadXML_fn).call(this, uri);
  } catch (e) {
    console.warn(e);
    return null;
  }
};
const getEpubMetadata = (opf) => getMetadata(opf);
const parseEpubMetadataFromXML = (xml) => {
  const opf = new DOMParser().parseFromString(sanitizeXMLEntities(xml), "application/xml");
  return getMetadata(opf);
};
export {
  EPUB,
  getEpubMetadata,
  parseEpubMetadataFromXML
};
