const readComicInfoXML = async ({ entries, loadBlob }) => {
  const entry = entries.find((e) => e.filename.toLowerCase() === "comicinfo.xml") ?? entries.find((e) => {
    var _a;
    return ((_a = e.filename.split("/").pop()) == null ? void 0 : _a.toLowerCase()) === "comicinfo.xml";
  });
  if (!entry) return null;
  let text;
  try {
    text = await (await loadBlob(entry.filename)).text();
  } catch {
    return null;
  }
  let doc;
  try {
    doc = new DOMParser().parseFromString(text, "application/xml");
  } catch {
    return null;
  }
  if (!doc || doc.getElementsByTagName("parsererror").length) return null;
  const get = (name) => {
    var _a, _b;
    return ((_b = (_a = doc.getElementsByTagName(name).item(0)) == null ? void 0 : _a.textContent) == null ? void 0 : _b.trim()) || void 0;
  };
  const getPositiveInteger = (name) => {
    const value = Number.parseInt(get(name), 10);
    return Number.isFinite(value) && value > 0 ? value : void 0;
  };
  const getSubjects = () => [...new Set([get("Genre"), get("Tags")].flatMap((value) => (value == null ? void 0 : value.split(/[,;|]/).map((x) => x.trim()).filter(Boolean)) ?? []))];
  const getPublished = () => {
    const year = getPositiveInteger("Year");
    if (!year) return void 0;
    const month = getPositiveInteger("Month");
    const day = getPositiveInteger("Day");
    const yyyy = String(year).padStart(4, "0");
    if (!month || month > 12) return yyyy;
    const yyyyMm = `${yyyy}-${String(month).padStart(2, "0")}`;
    if (!day || day > 31) return yyyyMm;
    return `${yyyyMm}-${String(day).padStart(2, "0")}`;
  };
  const subjects = getSubjects();
  return {
    title: get("Title"),
    publisher: get("Publisher"),
    language: get("LanguageISO"),
    author: get("Writer"),
    published: getPublished(),
    description: get("Summary"),
    subject: subjects.length ? subjects : void 0,
    identifier: get("Web"),
    series: get("Series"),
    seriesPosition: get("Number"),
    seriesTotal: get("Count")
  };
};
const readComicBookInfo = async ({ getComment }) => {
  let info;
  try {
    info = JSON.parse(await getComment() || "")["ComicBookInfo/1.0"];
  } catch {
    return null;
  }
  if (!info) return null;
  const year = info.publicationYear;
  const month = info.publicationMonth;
  const mm = month && month >= 1 && month <= 12 ? String(month).padStart(2, "0") : null;
  return {
    title: info.title,
    publisher: info.publisher,
    language: info.language || info.lang,
    author: info.credits ? info.credits.map((c) => `${c.person} (${c.role})`).join(", ") : "",
    published: year && month ? `${year}-${mm}` : void 0,
    series: info.series,
    seriesPosition: info.issue == null ? void 0 : String(info.issue)
  };
};
const makeComicBook = async ({ entries, loadBlob, getSize, getComment }, file) => {
  const cache = /* @__PURE__ */ new Map();
  const urls = /* @__PURE__ */ new Map();
  const load = async (name) => {
    if (cache.has(name)) return cache.get(name);
    const src = URL.createObjectURL(await loadBlob(name));
    const page = URL.createObjectURL(
      new Blob([`<!DOCTYPE html><html><head><meta charset="utf-8"></head><body style="margin: 0"><img src="${src}"></body></html>`], { type: "text/html" })
    );
    urls.set(name, [src, page]);
    cache.set(name, page);
    return page;
  };
  const unload = (name) => {
    var _a, _b;
    (_b = (_a = urls.get(name)) == null ? void 0 : _a.forEach) == null ? void 0 : _b.call(_a, (url) => URL.revokeObjectURL(url));
    urls.delete(name);
    cache.delete(name);
  };
  const exts = [".jpg", ".jpeg", ".png", ".gif", ".bmp", ".webp", ".svg", ".jxl", ".avif"];
  const collator = new Intl.Collator([], { numeric: true });
  const comparePaths = (a, b) => {
    const as = a.split("/"), bs = b.split("/");
    const len = Math.min(as.length, bs.length);
    for (let i = 0; i < len; i++) {
      const cmp = collator.compare(as[i], bs[i]);
      if (cmp) return cmp;
    }
    return as.length - bs.length;
  };
  const isPage = (name) => {
    if (name.startsWith("__MACOSX/")) return false;
    const base = name.split("/").pop().toLowerCase();
    return !base.startsWith(".") && exts.some((ext) => base.endsWith(ext));
  };
  const files = entries.map((entry) => entry.filename).filter(isPage).sort(comparePaths);
  if (!files.length) throw new Error("No supported image files in archive");
  const book = {};
  const xml = await readComicInfoXML({ entries, loadBlob });
  const cbi = await readComicBookInfo({ getComment });
  const merged = { ...cbi || {}, ...xml || {} };
  book.metadata = {
    title: merged.title || file.name,
    publisher: merged.publisher,
    language: merged.language,
    author: merged.author,
    published: merged.published,
    description: merged.description,
    subject: merged.subject,
    identifier: merged.identifier
  };
  if (merged.series) {
    const series = { name: merged.series };
    if (merged.seriesPosition) series.position = merged.seriesPosition;
    if (merged.seriesTotal) series.total = merged.seriesTotal;
    book.metadata.belongsTo = { series };
  }
  book.getCover = () => loadBlob(files[0]);
  book.sections = files.map((name) => ({
    id: name,
    load: () => load(name),
    unload: () => unload(name),
    size: getSize(name)
  }));
  book.toc = files.map((name) => ({ label: name, href: name }));
  book.rendition = { layout: "pre-paginated" };
  book.resolveHref = (href) => ({ index: book.sections.findIndex((s) => s.id === href) });
  book.splitTOCHref = (href) => [href, null];
  book.getTOCFragment = (doc) => doc.documentElement;
  book.destroy = () => {
    for (const arr of urls.values())
      for (const url of arr) URL.revokeObjectURL(url);
  };
  return book;
};
export {
  makeComicBook
};
