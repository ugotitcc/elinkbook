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
var _timeout, _el, _check, _state, _CursorAutohider_instances, hasSelection_fn, _arr, _index, _root, _sectionProgress, _tocProgress, _pageProgress, _cfiProgress, _searchResults, _cursorAutohider, _View_instances, emit_fn, onRelocate_fn, onLoad_fn, handleLinks_fn, getOverlayer_fn, createOverlayer_fn, toSearchMatch_fn, searchSection_fn, searchBook_fn;
import * as CFI from "./epubcfi.js";
import { TOCProgress, SectionProgress, PageProgress } from "./progress.js";
import { Overlayer } from "./overlayer.js";
import { textWalker } from "./text-walker.js";
import { CHUNK_ATTRIBUTE } from "./section-chunks.js";
const SEARCH_PREFIX = "foliate-search:";
const NOTE_PREFIX = "foliate-note:";
const isZip = async (file) => {
  const arr = new Uint8Array(await file.slice(0, 4).arrayBuffer());
  return arr[0] === 80 && arr[1] === 75 && arr[2] === 3 && arr[3] === 4;
};
const isPDF = async (file) => {
  const arr = new Uint8Array(await file.slice(0, 5).arrayBuffer());
  return arr[0] === 37 && arr[1] === 80 && arr[2] === 68 && arr[3] === 70 && arr[4] === 45;
};
const isCBZ = ({ name, type }) => type === "application/vnd.comicbook+zip" || name.endsWith(".cbz");
const isFB2 = ({ name, type }) => type === "application/x-fictionbook+xml" || name.endsWith(".fb2");
const isFBZ = ({ name, type }) => type === "application/x-zip-compressed-fb2" || name.endsWith(".fb2.zip") || name.endsWith(".fbz");
const makeZipLoader = async (file) => {
  const { configure, ZipReader, BlobReader, TextWriter, BlobWriter } = await import("./vendor/zip.js");
  configure({ useWebWorkers: false });
  const reader = new ZipReader(new BlobReader(file));
  const entries = await reader.getEntries();
  const map = new Map(entries.map((entry) => [entry.filename, entry]));
  const load = (f) => (name, ...args) => map.has(name) ? f(map.get(name), ...args) : null;
  const loadText = load((entry) => entry.getData(new TextWriter()));
  const loadBlob = load((entry, type) => entry.getData(new BlobWriter(type)));
  const getSize = (name) => {
    var _a;
    return ((_a = map.get(name)) == null ? void 0 : _a.uncompressedSize) ?? 0;
  };
  return { entries, loadText, loadBlob, getSize };
};
const getFileEntries = async (entry) => entry.isFile ? entry : (await Promise.all(Array.from(
  await new Promise((resolve, reject) => entry.createReader().readEntries((entries) => resolve(entries), (error) => reject(error))),
  getFileEntries
))).flat();
const makeDirectoryLoader = async (entry) => {
  const entries = await getFileEntries(entry);
  const files = await Promise.all(
    entries.map((entry2) => new Promise((resolve, reject) => entry2.file(
      (file) => resolve([file, entry2.fullPath]),
      (error) => reject(error)
    )))
  );
  const map = new Map(files.map(([file, path]) => [path.replace(entry.fullPath + "/", ""), file]));
  const decoder = new TextDecoder();
  const decode = (x) => x ? decoder.decode(x) : null;
  const getBuffer = (name) => {
    var _a;
    return ((_a = map.get(name)) == null ? void 0 : _a.arrayBuffer()) ?? null;
  };
  const loadText = async (name) => decode(await getBuffer(name));
  const loadBlob = (name) => map.get(name);
  const getSize = (name) => {
    var _a;
    return ((_a = map.get(name)) == null ? void 0 : _a.size) ?? 0;
  };
  return { loadText, loadBlob, getSize };
};
class ResponseError extends Error {
}
class NotFoundError extends Error {
}
class UnsupportedTypeError extends Error {
}
const fetchFile = async (url) => {
  const res = await fetch(url);
  if (!res.ok) throw new ResponseError(
    `${res.status} ${res.statusText}`,
    { cause: res }
  );
  return new File([await res.blob()], new URL(res.url).pathname);
};
const makeBook = async (file) => {
  if (typeof file === "string") file = await fetchFile(file);
  let book;
  if (file.isDirectory) {
    const loader = await makeDirectoryLoader(file);
    const { EPUB } = await import("./epub.js");
    book = await new EPUB(loader).init();
  } else if (!file.size) throw new NotFoundError("File not found");
  else if (await isZip(file)) {
    const loader = await makeZipLoader(file);
    if (isCBZ(file)) {
      const { makeComicBook } = await import("./comic-book.js");
      book = makeComicBook(loader, file);
    } else if (isFBZ(file)) {
      const { makeFB2 } = await import("./fb2.js");
      const { entries } = loader;
      const entry = entries.find((entry2) => entry2.filename.endsWith(".fb2"));
      const blob = await loader.loadBlob((entry ?? entries[0]).filename);
      book = await makeFB2(blob);
    } else {
      const { EPUB } = await import("./epub.js");
      book = await new EPUB(loader).init();
    }
  } else if (await isPDF(file)) {
    const { makePDF } = await import("./pdf.js");
    book = await makePDF(file);
  } else {
    const { isMOBI, MOBI } = await import("./mobi.js");
    if (await isMOBI(file)) {
      const fflate = await import("./vendor/fflate.js");
      book = await new MOBI({ unzlib: fflate.unzlibSync }).open(file);
    } else if (isFB2(file)) {
      const { makeFB2 } = await import("./fb2.js");
      book = await makeFB2(file);
    }
  }
  if (!book) throw new UnsupportedTypeError("File type not supported");
  return book;
};
const _CursorAutohider = class _CursorAutohider {
  constructor(el, check, state = {}) {
    __privateAdd(this, _CursorAutohider_instances);
    __privateAdd(this, _timeout);
    __privateAdd(this, _el);
    __privateAdd(this, _check);
    __privateAdd(this, _state);
    __privateSet(this, _el, el);
    __privateSet(this, _check, check);
    __privateSet(this, _state, state);
    if (__privateGet(this, _state).hidden) this.hide();
    __privateGet(this, _el).addEventListener("mousemove", ({ screenX, screenY }) => {
      if (screenX === __privateGet(this, _state).x && screenY === __privateGet(this, _state).y) return;
      __privateGet(this, _state).x = screenX, __privateGet(this, _state).y = screenY;
      this.show();
      if (__privateGet(this, _timeout)) clearTimeout(__privateGet(this, _timeout));
      if (check()) __privateSet(this, _timeout, setTimeout(this.hide.bind(this), 1e3));
    }, false);
  }
  cloneFor(el) {
    return new _CursorAutohider(el, __privateGet(this, _check), __privateGet(this, _state));
  }
  hide() {
    if (__privateMethod(this, _CursorAutohider_instances, hasSelection_fn).call(this)) return;
    __privateGet(this, _el).style.cursor = "none";
    __privateGet(this, _state).hidden = true;
  }
  show() {
    __privateGet(this, _el).style.removeProperty("cursor");
    __privateGet(this, _state).hidden = false;
  }
};
_timeout = new WeakMap();
_el = new WeakMap();
_check = new WeakMap();
_state = new WeakMap();
_CursorAutohider_instances = new WeakSet();
hasSelection_fn = function() {
  var _a;
  const selection = (_a = __privateGet(this, _el).ownerDocument) == null ? void 0 : _a.getSelection();
  return selection ? !selection.isCollapsed : false;
};
let CursorAutohider = _CursorAutohider;
class History extends EventTarget {
  constructor() {
    super(...arguments);
    __privateAdd(this, _arr, []);
    __privateAdd(this, _index, -1);
  }
  pushState(x) {
    const last = __privateGet(this, _arr)[__privateGet(this, _index)];
    if (last === x || (last == null ? void 0 : last.fraction) && last.fraction === x.fraction) return;
    __privateGet(this, _arr)[++__privateWrapper(this, _index)._] = x;
    __privateGet(this, _arr).length = __privateGet(this, _index) + 1;
    this.dispatchEvent(new Event("index-change"));
  }
  replaceState(x) {
    const index = __privateGet(this, _index);
    __privateGet(this, _arr)[index] = x;
  }
  back() {
    const index = __privateGet(this, _index);
    if (index <= 0) return;
    const detail = { state: __privateGet(this, _arr)[index - 1] };
    __privateSet(this, _index, index - 1);
    this.dispatchEvent(new CustomEvent("popstate", { detail }));
    this.dispatchEvent(new Event("index-change"));
  }
  forward() {
    const index = __privateGet(this, _index);
    if (index >= __privateGet(this, _arr).length - 1) return;
    const detail = { state: __privateGet(this, _arr)[index + 1] };
    __privateSet(this, _index, index + 1);
    this.dispatchEvent(new CustomEvent("popstate", { detail }));
    this.dispatchEvent(new Event("index-change"));
  }
  get canGoBack() {
    return __privateGet(this, _index) > 0;
  }
  get canGoForward() {
    return __privateGet(this, _index) < __privateGet(this, _arr).length - 1;
  }
  clear() {
    __privateSet(this, _arr, []);
    __privateSet(this, _index, -1);
  }
}
_arr = new WeakMap();
_index = new WeakMap();
const languageInfo = (lang) => {
  var _a, _b;
  if (!lang) return {};
  try {
    const canonical = Intl.getCanonicalLocales(lang)[0];
    const locale = new Intl.Locale(canonical);
    const isCJK = ["zh", "ja", "kr"].includes(locale.language);
    const direction = (_b = ((_a = locale.getTextInfo) == null ? void 0 : _a.call(locale)) ?? locale.textInfo) == null ? void 0 : _b.direction;
    return { canonical, locale, isCJK, direction };
  } catch (e) {
    console.warn(e);
    return {};
  }
};
class View extends HTMLElement {
  constructor() {
    super();
    __privateAdd(this, _View_instances);
    __privateAdd(this, _root, this.attachShadow({ mode: "open" }));
    __privateAdd(this, _sectionProgress);
    __privateAdd(this, _tocProgress);
    __privateAdd(this, _pageProgress);
    __privateAdd(this, _cfiProgress);
    __privateAdd(this, _searchResults, /* @__PURE__ */ new Map());
    __privateAdd(this, _cursorAutohider, new CursorAutohider(this, () => this.hasAttribute("autohide-cursor")));
    __publicField(this, "isFixedLayout", false);
    __publicField(this, "lastLocation");
    __publicField(this, "history", new History());
    this.history.addEventListener("popstate", ({ detail }) => {
      const resolved = this.resolveNavigation(detail.state);
      this.renderer.goTo(resolved);
    });
  }
  async open(book) {
    var _a, _b;
    if (typeof book === "string" || typeof book.arrayBuffer === "function" || book.isDirectory) book = await makeBook(book);
    this.book = book;
    this.language = languageInfo((_a = book.metadata) == null ? void 0 : _a.language);
    if (book.splitTOCHref && book.getTOCFragment) {
      const ids = book.sections.map((s) => s.id);
      __privateSet(this, _sectionProgress, new SectionProgress(book.sections, 1500, 1600));
      const splitHref = book.splitTOCHref.bind(book);
      const getFragment = book.getTOCFragment.bind(book);
      __privateSet(this, _tocProgress, new TOCProgress());
      await __privateGet(this, _tocProgress).init({
        toc: book.toc ?? [],
        ids,
        splitHref,
        getFragment
      });
      __privateSet(this, _pageProgress, new TOCProgress());
      await __privateGet(this, _pageProgress).init({
        toc: book.pageList ?? [],
        ids,
        splitHref,
        getFragment
      });
    }
    __privateSet(this, _cfiProgress, new PageProgress(book, this.resolveNavigation.bind(this)));
    this.isFixedLayout = ((_b = this.book.rendition) == null ? void 0 : _b.layout) === "pre-paginated";
    if (this.isFixedLayout) {
      await import("./fixed-layout.js");
      this.renderer = document.createElement("foliate-fxl");
    } else {
      await import("./paginator.js");
      this.renderer = document.createElement("foliate-paginator");
    }
    this.renderer.setAttribute("exportparts", "head,foot,filter,container");
    this.renderer.addEventListener("load", (e) => __privateMethod(this, _View_instances, onLoad_fn).call(this, e.detail));
    this.renderer.addEventListener("relocate", (e) => __privateMethod(this, _View_instances, onRelocate_fn).call(this, e.detail));
    this.renderer.addEventListener("create-overlayer", (e) => e.detail.attach(__privateMethod(this, _View_instances, createOverlayer_fn).call(this, e.detail)));
    this.renderer.open(book);
    __privateGet(this, _root).append(this.renderer);
    if (book.sections.some((section) => section.mediaOverlay)) {
      const activeClass = book.media.activeClass;
      const playbackActiveClass = book.media.playbackActiveClass;
      this.mediaOverlay = book.getMediaOverlay();
      let lastActive;
      this.mediaOverlay.addEventListener("highlight", (e) => {
        const resolved = this.resolveNavigation(e.detail.text);
        this.renderer.goTo(resolved).then(() => {
          const { doc } = this.renderer.getContents().find((x) => x.index = resolved.index);
          const el = resolved.anchor(doc);
          el.classList.add(activeClass);
          if (playbackActiveClass) el.ownerDocument.documentElement.classList.add(playbackActiveClass);
          lastActive = new WeakRef(el);
        });
      });
      this.mediaOverlay.addEventListener("unhighlight", () => {
        const el = lastActive == null ? void 0 : lastActive.deref();
        if (el) {
          el.classList.remove(activeClass);
          if (playbackActiveClass) el.ownerDocument.documentElement.classList.remove(playbackActiveClass);
        }
      });
    }
  }
  close() {
    var _a, _b;
    (_a = this.renderer) == null ? void 0 : _a.destroy();
    (_b = this.renderer) == null ? void 0 : _b.remove();
    __privateSet(this, _sectionProgress, null);
    __privateSet(this, _tocProgress, null);
    __privateSet(this, _pageProgress, null);
    __privateSet(this, _cfiProgress, null);
    __privateSet(this, _searchResults, /* @__PURE__ */ new Map());
    this.lastLocation = null;
    this.history.clear();
    this.tts = null;
    this.mediaOverlay = null;
  }
  goToTextStart() {
    var _a, _b;
    return this.goTo(((_b = (_a = this.book.landmarks) == null ? void 0 : _a.find((m) => m.type.includes("bodymatter") || m.type.includes("text"))) == null ? void 0 : _b.href) ?? this.book.sections.findIndex((s) => s.linear !== "no"));
  }
  async init({ lastLocation, showTextStart }) {
    const resolved = lastLocation ? this.resolveNavigation(lastLocation) : null;
    if (resolved) {
      await this.renderer.goTo(resolved);
      this.history.pushState(lastLocation);
    } else if (showTextStart) await this.goToTextStart();
    else {
      this.history.pushState(0);
      await this.next();
    }
  }
  async addAnnotation(annotation, remove) {
    var _a, _b;
    const { value } = annotation;
    if (value.startsWith(SEARCH_PREFIX)) {
      const cfi = value.replace(SEARCH_PREFIX, "");
      const { index: index2, anchor: anchor2 } = await this.resolveNavigation(cfi);
      const obj2 = __privateMethod(this, _View_instances, getOverlayer_fn).call(this, index2, anchor2);
      if (obj2) {
        const { overlayer, doc } = obj2;
        if (remove) {
          overlayer.remove(value);
          return;
        }
        const range = doc ? anchor2(doc) : anchor2;
        if (range) overlayer.add(value, range, Overlayer.outline);
      }
      return;
    } else if (value.startsWith(NOTE_PREFIX)) {
      const cfi = value.replace(NOTE_PREFIX, "");
      const { index: index2, anchor: anchor2 } = await this.resolveNavigation(cfi);
      const obj2 = __privateMethod(this, _View_instances, getOverlayer_fn).call(this, index2, anchor2);
      if (obj2) {
        const { overlayer, doc } = obj2;
        if (remove) {
          overlayer.remove(value);
          return;
        }
        const range = doc ? anchor2(doc) : anchor2;
        if (range) {
          const draw = (func, opts) => overlayer.add(value, range, func, opts);
          __privateMethod(this, _View_instances, emit_fn).call(this, "draw-annotation", { draw, annotation, doc, range });
        }
      }
      return;
    }
    const { index, anchor } = await this.resolveNavigation(value);
    const obj = __privateMethod(this, _View_instances, getOverlayer_fn).call(this, index, anchor);
    if (obj) {
      const { overlayer, doc } = obj;
      overlayer.remove(value);
      if (!remove) {
        const range = doc ? anchor(doc) : anchor;
        if (range) {
          const draw = (func, opts) => overlayer.add(value, range, func, opts);
          __privateMethod(this, _View_instances, emit_fn).call(this, "draw-annotation", { draw, annotation, doc, range });
        }
      }
    }
    const label = ((_b = (_a = __privateGet(this, _tocProgress)) == null ? void 0 : _a.getProgress(index)) == null ? void 0 : _b.label) ?? "";
    return { index, label };
  }
  deleteAnnotation(annotation) {
    return this.addAnnotation(annotation, true);
  }
  async showAnnotation(annotation) {
    const { value } = annotation;
    const resolved = await this.goTo(value);
    if (resolved) {
      const { index, anchor } = resolved;
      const { doc } = __privateMethod(this, _View_instances, getOverlayer_fn).call(this, index, anchor);
      const range = anchor(doc);
      __privateMethod(this, _View_instances, emit_fn).call(this, "show-annotation", { value, index, range });
    }
  }
  getCFI(index, range) {
    const baseCFI = this.book.sections[index].cfi ?? CFI.fake.fromIndex(index);
    if (!range) return baseCFI;
    return CFI.joinIndir(baseCFI, CFI.fromRange(range));
  }
  resolveCFI(cfi) {
    if (this.book.resolveCFI)
      return this.book.resolveCFI(cfi);
    else {
      const parts = CFI.parse(cfi);
      const index = CFI.fake.toIndex((parts.parent ?? parts).shift());
      const anchor = (doc) => CFI.toRange(doc, parts);
      return { index, anchor };
    }
  }
  resolveNavigation(target) {
    try {
      if (typeof target === "number") return { index: target };
      if (typeof target.fraction === "number") {
        const [index, anchor] = __privateGet(this, _sectionProgress).getSection(target.fraction);
        return { index, anchor };
      }
      if (CFI.isCFI.test(target)) return this.resolveCFI(target);
      return this.book.resolveHref(target);
    } catch (e) {
      console.error(e);
      console.error(`Could not resolve target ${target}`);
    }
  }
  async goTo(target) {
    const resolved = this.resolveNavigation(target);
    try {
      await this.renderer.goTo(resolved);
      this.history.pushState(target);
      return resolved;
    } catch (e) {
      console.error(e);
      console.error(`Could not go to ${target}`);
    }
  }
  async goToFraction(frac) {
    const [index, anchor] = __privateGet(this, _sectionProgress).getSection(frac);
    await this.renderer.goTo({ index, anchor });
    this.history.pushState({ fraction: frac });
  }
  async select(target) {
    try {
      const obj = await this.resolveNavigation(target);
      await this.renderer.goTo({ ...obj, select: true });
      this.history.pushState(target);
    } catch (e) {
      console.error(e);
      console.error(`Could not go to ${target}`);
    }
  }
  deselect() {
    for (const { doc } of this.renderer.getContents())
      doc.defaultView.getSelection().removeAllRanges();
  }
  getSectionFractions() {
    var _a;
    return (((_a = __privateGet(this, _sectionProgress)) == null ? void 0 : _a.sectionFractions) ?? []).map((x) => x + Number.EPSILON);
  }
  // epic-26-architecture-hardening Issue 11：排版設定變更時，main.js 的
  // window.applyPreferences() 呼叫這個方法清空已記錄的密度校正資料——
  // 字級/行距/邊距/欄數/螢幕方向/直橫排改變後，舊密度全部失真。
  clearLocationDensity() {
    var _a;
    (_a = __privateGet(this, _sectionProgress)) == null ? void 0 : _a.clearDensity();
  }
  getProgressOf(index, range) {
    var _a, _b;
    const tocItem = (_a = __privateGet(this, _tocProgress)) == null ? void 0 : _a.getProgress(index, range);
    const pageItem = (_b = __privateGet(this, _pageProgress)) == null ? void 0 : _b.getProgress(index, range);
    return { tocItem, pageItem };
  }
  async getCFIProgress(cfi) {
    var _a, _b;
    const progress = await ((_a = __privateGet(this, _cfiProgress)) == null ? void 0 : _a.getProgress(cfi));
    if (!progress || progress.index === -1) return null;
    return (_b = __privateGet(this, _sectionProgress)) == null ? void 0 : _b.getProgress(progress.index, progress.fraction);
  }
  async getTOCItemOf(target) {
    var _a;
    try {
      const { index, anchor } = await this.resolveNavigation(target);
      const doc = await this.book.sections[index].createDocument();
      const frag = anchor(doc);
      const isRange = frag instanceof Range;
      const range = isRange ? frag : doc.createRange();
      if (!isRange) range.selectNodeContents(frag);
      return (_a = __privateGet(this, _tocProgress)) == null ? void 0 : _a.getProgress(index, range);
    } catch (e) {
      console.error(e);
      console.error(`Could not get ${target}`);
    }
  }
  async prev(distance) {
    await this.renderer.prev(distance);
  }
  async next(distance) {
    await this.renderer.next(distance);
  }
  async pan(dx, dy) {
    await this.renderer.pan(dx, dy);
  }
  isOverflowX() {
    return this.renderer.isOverflowX;
  }
  isOverflowY() {
    return this.renderer.isOverflowY;
  }
  goLeft() {
    return this.book.dir === "rtl" ? this.next() : this.prev();
  }
  goRight() {
    return this.book.dir === "rtl" ? this.prev() : this.next();
  }
  async *search(opts) {
    var _a, _b;
    this.clearSearch();
    const { searchMatcher } = await import("./search.js");
    const { sections } = this.book;
    const { query, index, results } = opts;
    const matcher = searchMatcher(
      textWalker,
      { defaultLocale: this.language, ...opts }
    );
    const iter = (results == null ? void 0 : results.length) ? (async function* () {
      for (const result of results) {
        if (result.subitems) {
          const progress = (result.index + 1) / sections.length;
          yield { progress };
          yield { index: result.index, subitems: result.subitems };
        } else {
          yield { cfi: result.cfi, cfis: result.cfis, excerpt: result.excerpt };
        }
      }
    })() : index != null ? __privateMethod(this, _View_instances, searchSection_fn).call(this, matcher, query, index) : __privateMethod(this, _View_instances, searchBook_fn).call(this, matcher, query);
    const list = [];
    const seen = /* @__PURE__ */ new Set();
    __privateGet(this, _searchResults).set(index, list);
    const addHighlights = (cfis, sink, sinkSeen) => {
      for (const cfi of cfis) {
        if (sinkSeen.has(cfi)) continue;
        sinkSeen.add(cfi);
        const item = { value: SEARCH_PREFIX + cfi };
        sink.push(item);
        this.addAnnotation(item);
      }
    };
    for await (const result of iter) {
      if (result.subitems) {
        const sectionList = [];
        const sectionSeen = /* @__PURE__ */ new Set();
        for (const item of result.subitems)
          addHighlights(item.cfis ?? [item.cfi], sectionList, sectionSeen);
        __privateGet(this, _searchResults).set(result.index, sectionList);
        yield {
          index: result.index,
          label: ((_b = (_a = __privateGet(this, _tocProgress)) == null ? void 0 : _a.getProgress(result.index)) == null ? void 0 : _b.label) ?? "",
          subitems: result.subitems
        };
      } else {
        if (result.cfi) addHighlights(result.cfis ?? [result.cfi], list, seen);
        yield result;
      }
    }
    yield "done";
  }
  clearSearch() {
    for (const list of __privateGet(this, _searchResults).values())
      for (const item of list) this.deleteAnnotation(item);
    __privateGet(this, _searchResults).clear();
  }
  async initTTS(granularity = "word", nodeFilter, highlighter) {
    const contents = this.renderer.getContents();
    const primaryIndex = this.renderer.primaryIndex;
    const primary = contents.find((x) => x.index === primaryIndex) ?? contents[0];
    const doc = primary == null ? void 0 : primary.doc;
    if (!doc) return;
    if (this.tts && this.tts.doc === doc) return;
    const { TTS } = await import("./tts.js");
    this.tts = new TTS(doc, textWalker, nodeFilter, highlighter || ((range) => this.renderer.scrollToAnchor(range, true)), granularity);
  }
  startMediaOverlay() {
    const contents = this.renderer.getContents();
    const primaryIndex = this.renderer.primaryIndex;
    const primary = contents.find((x) => x.index === primaryIndex) ?? contents[0];
    const { index } = primary ?? {};
    return this.mediaOverlay.start(index);
  }
}
_root = new WeakMap();
_sectionProgress = new WeakMap();
_tocProgress = new WeakMap();
_pageProgress = new WeakMap();
_cfiProgress = new WeakMap();
_searchResults = new WeakMap();
_cursorAutohider = new WeakMap();
_View_instances = new WeakSet();
emit_fn = function(name, detail, cancelable) {
  return this.dispatchEvent(new CustomEvent(name, { detail, cancelable }));
};
onRelocate_fn = function({ reason, range, index, fraction, size, contentPages }) {
  var _a, _b, _c, _d;
  if (contentPages) (_a = __privateGet(this, _sectionProgress)) == null ? void 0 : _a.recordDensity(index, contentPages);
  const progress = ((_b = __privateGet(this, _sectionProgress)) == null ? void 0 : _b.getProgress(index, fraction, size)) ?? {};
  const tocItem = (_c = __privateGet(this, _tocProgress)) == null ? void 0 : _c.getProgress(index, range);
  const pageItem = (_d = __privateGet(this, _pageProgress)) == null ? void 0 : _d.getProgress(index, range);
  const cfi = this.getCFI(index, range);
  this.lastLocation = { ...progress, tocItem, pageItem, cfi, range };
  if (reason === "snap" || reason === "page" || reason === "scroll")
    this.history.replaceState(cfi);
  __privateMethod(this, _View_instances, emit_fn).call(this, "relocate", this.lastLocation);
};
onLoad_fn = function({ doc, index }) {
  var _a, _b;
  (_a = doc.documentElement).lang || (_a.lang = this.language.canonical ?? "");
  if (!this.language.isCJK)
    (_b = doc.documentElement).dir || (_b.dir = this.language.direction ?? "");
  __privateMethod(this, _View_instances, handleLinks_fn).call(this, doc, index);
  __privateGet(this, _cursorAutohider).cloneFor(doc.documentElement);
  __privateMethod(this, _View_instances, emit_fn).call(this, "load", { doc, index });
};
handleLinks_fn = function(doc, index) {
  const { book } = this;
  const section = book.sections[index];
  doc.addEventListener("click", (e) => {
    var _a, _b, _c;
    const a = e.target.closest("a[href]");
    if (!a) return;
    e.preventDefault();
    const href_ = a.getAttribute("href");
    const href = ((_a = section == null ? void 0 : section.resolveHref) == null ? void 0 : _a.call(section, href_)) ?? href_;
    if ((_b = book == null ? void 0 : book.isExternal) == null ? void 0 : _b.call(book, href))
      Promise.resolve(__privateMethod(this, _View_instances, emit_fn).call(this, "external-link", { a, href }, true)).then((x) => x ? globalThis.open(href, "_blank") : null).catch((e2) => console.error(e2));
    else {
      let internalHref = href;
      if (!book.resolveHref(href)) {
        const hashIndex = href_.indexOf("#");
        if (hashIndex >= 0) {
          const hash = href_.slice(hashIndex);
          internalHref = ((_c = section == null ? void 0 : section.resolveHref) == null ? void 0 : _c.call(section, hash)) ?? href;
        }
      }
      Promise.resolve(__privateMethod(this, _View_instances, emit_fn).call(this, "link", { a, href: internalHref }, true)).then((x) => x ? this.goTo(internalHref) : null).catch((e2) => console.error(e2));
    }
  });
};
getOverlayer_fn = function(index, anchor) {
  const candidates = this.renderer.getContents().filter((x) => x.index === index && x.overlayer);
  if (candidates.length > 1 && typeof anchor === "function")
    return candidates.find(({ doc }) => {
      try {
        const target = anchor(doc);
        const node = (target == null ? void 0 : target.startContainer) ?? target;
        const el = (node == null ? void 0 : node.nodeType) === 1 ? node : node == null ? void 0 : node.parentElement;
        return el && !el.closest(`[${CHUNK_ATTRIBUTE}]`);
      } catch {
        return false;
      }
    }) ?? candidates[0];
  return candidates[0];
};
createOverlayer_fn = function({ doc, index }) {
  const overlayer = new Overlayer(doc);
  doc.addEventListener("click", (e) => {
    const [value, range, rect] = overlayer.hitTest(e);
    if (value && !value.startsWith(SEARCH_PREFIX)) {
      __privateMethod(this, _View_instances, emit_fn).call(this, "show-annotation", { value, index, range, rect });
    }
  }, false);
  let lastHitTestTime = 0;
  const THROTTLE_MS = 200;
  const isAndroid = /Android/i.test(navigator.userAgent);
  doc.addEventListener("mousemove", (e) => {
    if (isAndroid) return;
    const now = performance.now();
    if (now - lastHitTestTime < THROTTLE_MS) return;
    lastHitTestTime = now;
    const [value] = overlayer.hitTest(e);
    if (value && !value.startsWith(SEARCH_PREFIX)) {
      doc.body.style.cursor = "pointer";
    } else {
      doc.body.style.cursor = "";
    }
  });
  const list = __privateGet(this, _searchResults).get(index);
  if (list) for (const item of list) this.addAnnotation(item);
  __privateMethod(this, _View_instances, emit_fn).call(this, "create-overlay", { index });
  return overlayer;
};
// A matcher result carries a primary `range` (nav/excerpt anchor) and, for
// nearby-words, per-word `subRanges` to highlight each matched word.
toSearchMatch_fn = function(index, { range, excerpt, subRanges }) {
  const cfi = this.getCFI(index, range);
  if (subRanges == null ? void 0 : subRanges.length)
    return { cfi, cfis: subRanges.map((r) => this.getCFI(index, r)), excerpt };
  return { cfi, excerpt };
};
searchSection_fn = async function* (matcher, query, index) {
  const doc = await this.book.sections[index].createDocument();
  for (const match of matcher(doc, query))
    yield __privateMethod(this, _View_instances, toSearchMatch_fn).call(this, index, match);
};
searchBook_fn = async function* (matcher, query) {
  const { sections } = this.book;
  for (const [index, { createDocument }] of sections.entries()) {
    if (!createDocument) continue;
    const doc = await createDocument();
    const subitems = Array.from(matcher(doc, query), (match) => __privateMethod(this, _View_instances, toSearchMatch_fn).call(this, index, match));
    const progress = (index + 1) / sections.length;
    yield { progress };
    if (subitems.length) yield { index, subitems };
  }
};
customElements.define("foliate-view", View);
export {
  NotFoundError,
  ResponseError,
  UnsupportedTypeError,
  View,
  makeBook
};
