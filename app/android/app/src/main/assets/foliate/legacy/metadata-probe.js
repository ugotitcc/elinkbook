import { makeBook } from "./view.js";
function firstText(v) {
  if (v == null) return null;
  if (typeof v === "string") {
    const s = v.trim();
    return s.length > 0 ? s : null;
  }
  if (Array.isArray(v)) {
    return v.length > 0 ? firstText(v[0]) : null;
  }
  if (typeof v === "object") {
    if ("name" in v) {
      return firstText(v.name);
    }
    const values = Object.values(v);
    return values.length > 0 ? firstText(values[0]) : null;
  }
  return null;
}
function blobToBase64(blob) {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onloadend = () => {
      if (typeof reader.result === "string") {
        const commaIdx = reader.result.indexOf(",");
        resolve(commaIdx >= 0 ? reader.result.slice(commaIdx + 1) : reader.result);
      } else {
        resolve(null);
      }
    };
    reader.onerror = reject;
    reader.readAsDataURL(blob);
  });
}
async function readBookMetadata(file) {
  var _a, _b, _c;
  let book = null;
  try {
    book = await makeBook(file);
    const metadata = book.metadata || {};
    const title = firstText(metadata.title);
    const author = firstText(metadata.author);
    let identifier = null;
    if (typeof metadata.identifier === "string") {
      const trimmed = metadata.identifier.trim();
      if (trimmed.length > 0) identifier = trimmed;
    }
    const isFixedLayout = ((_a = book.rendition) == null ? void 0 : _a.layout) === "pre-paginated";
    let coverBase64 = null;
    let coverType = null;
    try {
      const coverBlob = await ((_b = book.getCover) == null ? void 0 : _b.call(book));
      if (coverBlob) {
        coverBase64 = await blobToBase64(coverBlob);
        coverType = coverBlob.type || null;
      }
    } catch (_) {
      coverBase64 = null;
      coverType = null;
    }
    return {
      title,
      author,
      identifier,
      isFixedLayout,
      coverBase64,
      coverType
    };
  } finally {
    try {
      (_c = book == null ? void 0 : book.destroy) == null ? void 0 : _c.call(book);
    } catch (_) {
    }
  }
}
const RANGE_BLOCK_SIZE = 256 * 1024;
class RangeFile {
  constructor(size, fetchRange, name) {
    this.size = size;
    this.name = name;
    this.type = "application/epub+zip";
    this._fetchRange = fetchRange;
    this._blocks = /* @__PURE__ */ new Map();
  }
  _block(index) {
    let pending = this._blocks.get(index);
    if (!pending) {
      const start = index * RANGE_BLOCK_SIZE;
      const end = Math.min(start + RANGE_BLOCK_SIZE, this.size);
      pending = Promise.resolve(this._fetchRange(start, end)).then((buf) => new Uint8Array(buf));
      this._blocks.set(index, pending);
    }
    return pending;
  }
  // 語意比照 Blob.slice：省略或負值的邊界相對於結尾，超出範圍夾回 [0, size]。
  slice(start, end) {
    const size = this.size;
    let from = start === void 0 ? 0 : start;
    let to = end === void 0 ? size : end;
    if (from < 0) from = Math.max(size + from, 0);
    if (to < 0) to = Math.max(size + to, 0);
    from = Math.min(from, size);
    to = Math.min(Math.max(to, from), size);
    const owner = this;
    return {
      size: to - from,
      type: owner.type,
      async arrayBuffer() {
        const length = to - from;
        const out = new Uint8Array(length);
        if (length === 0) return out.buffer;
        const first = Math.floor(from / RANGE_BLOCK_SIZE);
        const last = Math.floor((to - 1) / RANGE_BLOCK_SIZE);
        const blocks = await Promise.all(
          Array.from({ length: last - first + 1 }, (_, i) => owner._block(first + i))
        );
        let written = 0;
        for (let i = 0; i < blocks.length; i++) {
          const blockStart = (first + i) * RANGE_BLOCK_SIZE;
          const lo = Math.max(from, blockStart) - blockStart;
          const hi = Math.min(to, blockStart + blocks[i].length) - blockStart;
          out.set(blocks[i].subarray(lo, hi), written);
          written += hi - lo;
        }
        return out.buffer;
      }
    };
  }
}
async function readBookMetadataByRange(size, fetchRange, name = "book.epub") {
  return readBookMetadata(new RangeFile(size, fetchRange, name));
}
export {
  readBookMetadata,
  readBookMetadataByRange
};
