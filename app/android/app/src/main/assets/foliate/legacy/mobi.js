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
var _file, _offsets, _start, _resourceStart, _decoder, _encoder, _decompress, _removeTrailingEntries, _MOBI_instances, getHeaders_fn, setup_fn, _resourceCache, _textCache, _cache, _sections, _fileposList, _type, _MOBI6_instances, sanitize_fn, _cache2, _fragmentOffsets, _fragmentSelectors, _tables, _sections2, _fullRawLength, _rawHead, _rawTail, _lastLoadedHead, _lastLoadedTail, _rawQueue, _type2, _inlineMap, _KF8_instances, loadRawLocked_fn, setFragmentSelector_fn;
const unescapeHTML = (str) => {
  if (!str) return "";
  const textarea = document.createElement("textarea");
  textarea.innerHTML = str;
  return textarea.value;
};
const MIME = {
  XML: "application/xml",
  XHTML: "application/xhtml+xml",
  HTML: "text/html",
  CSS: "text/css",
  SVG: "image/svg+xml"
};
const PDB_HEADER = {
  name: [0, 32, "string"],
  type: [60, 4, "string"],
  creator: [64, 4, "string"],
  numRecords: [76, 2, "uint"]
};
const PALMDOC_HEADER = {
  compression: [0, 2, "uint"],
  numTextRecords: [8, 2, "uint"],
  recordSize: [10, 2, "uint"],
  encryption: [12, 2, "uint"]
};
const MOBI_HEADER = {
  magic: [16, 4, "string"],
  length: [20, 4, "uint"],
  type: [24, 4, "uint"],
  encoding: [28, 4, "uint"],
  uid: [32, 4, "uint"],
  version: [36, 4, "uint"],
  titleOffset: [84, 4, "uint"],
  titleLength: [88, 4, "uint"],
  localeRegion: [94, 1, "uint"],
  localeLanguage: [95, 1, "uint"],
  resourceStart: [108, 4, "uint"],
  huffcdic: [112, 4, "uint"],
  numHuffcdic: [116, 4, "uint"],
  exthFlag: [128, 4, "uint"],
  trailingFlags: [240, 4, "uint"],
  indx: [244, 4, "uint"]
};
const KF8_HEADER = {
  resourceStart: [108, 4, "uint"],
  fdst: [192, 4, "uint"],
  numFdst: [196, 4, "uint"],
  frag: [248, 4, "uint"],
  skel: [252, 4, "uint"],
  guide: [260, 4, "uint"]
};
const EXTH_HEADER = {
  magic: [0, 4, "string"],
  length: [4, 4, "uint"],
  count: [8, 4, "uint"]
};
const INDX_HEADER = {
  magic: [0, 4, "string"],
  length: [4, 4, "uint"],
  type: [8, 4, "uint"],
  idxt: [20, 4, "uint"],
  numRecords: [24, 4, "uint"],
  encoding: [28, 4, "uint"],
  language: [32, 4, "uint"],
  total: [36, 4, "uint"],
  ordt: [40, 4, "uint"],
  ligt: [44, 4, "uint"],
  numLigt: [48, 4, "uint"],
  numCncx: [52, 4, "uint"]
};
const TAGX_HEADER = {
  magic: [0, 4, "string"],
  length: [4, 4, "uint"],
  numControlBytes: [8, 4, "uint"]
};
const HUFF_HEADER = {
  magic: [0, 4, "string"],
  offset1: [8, 4, "uint"],
  offset2: [12, 4, "uint"]
};
const CDIC_HEADER = {
  magic: [0, 4, "string"],
  length: [4, 4, "uint"],
  numEntries: [8, 4, "uint"],
  codeLength: [12, 4, "uint"]
};
const FDST_HEADER = {
  magic: [0, 4, "string"],
  numEntries: [8, 4, "uint"]
};
const FONT_HEADER = {
  flags: [8, 4, "uint"],
  dataStart: [12, 4, "uint"],
  keyLength: [16, 4, "uint"],
  keyStart: [20, 4, "uint"]
};
const MOBI_ENCODING = {
  1252: "windows-1252",
  65001: "utf-8"
};
const EXTH_RECORD_TYPE = {
  100: ["creator", "string", true],
  101: ["publisher"],
  103: ["description"],
  104: ["isbn"],
  105: ["subject", "string", true],
  106: ["date"],
  108: ["contributor", "string", true],
  109: ["rights"],
  110: ["subjectCode", "string", true],
  112: ["source", "string", true],
  113: ["asin"],
  121: ["boundary", "uint"],
  122: ["fixedLayout"],
  125: ["numResources", "uint"],
  126: ["originalResolution"],
  127: ["zeroGutter"],
  128: ["zeroMargin"],
  129: ["coverURI"],
  132: ["regionMagnification"],
  201: ["coverOffset", "uint"],
  202: ["thumbnailOffset", "uint"],
  503: ["title"],
  524: ["language", "string", true],
  527: ["pageProgressionDirection"]
};
const MOBI_LANG = {
  1: [
    "ar",
    "ar-SA",
    "ar-IQ",
    "ar-EG",
    "ar-LY",
    "ar-DZ",
    "ar-MA",
    "ar-TN",
    "ar-OM",
    "ar-YE",
    "ar-SY",
    "ar-JO",
    "ar-LB",
    "ar-KW",
    "ar-AE",
    "ar-BH",
    "ar-QA"
  ],
  2: ["bg"],
  3: ["ca"],
  4: ["zh", "zh-TW", "zh-CN", "zh-HK", "zh-SG"],
  5: ["cs"],
  6: ["da"],
  7: ["de", "de-DE", "de-CH", "de-AT", "de-LU", "de-LI"],
  8: ["el"],
  9: [
    "en",
    "en-US",
    "en-GB",
    "en-AU",
    "en-CA",
    "en-NZ",
    "en-IE",
    "en-ZA",
    "en-JM",
    null,
    "en-BZ",
    "en-TT",
    "en-ZW",
    "en-PH"
  ],
  10: [
    "es",
    "es-ES",
    "es-MX",
    null,
    "es-GT",
    "es-CR",
    "es-PA",
    "es-DO",
    "es-VE",
    "es-CO",
    "es-PE",
    "es-AR",
    "es-EC",
    "es-CL",
    "es-UY",
    "es-PY",
    "es-BO",
    "es-SV",
    "es-HN",
    "es-NI",
    "es-PR"
  ],
  11: ["fi"],
  12: ["fr", "fr-FR", "fr-BE", "fr-CA", "fr-CH", "fr-LU", "fr-MC"],
  13: ["he"],
  14: ["hu"],
  15: ["is"],
  16: ["it", "it-IT", "it-CH"],
  17: ["ja"],
  18: ["ko"],
  19: ["nl", "nl-NL", "nl-BE"],
  20: ["no", "nb", "nn"],
  21: ["pl"],
  22: ["pt", "pt-BR", "pt-PT"],
  23: ["rm"],
  24: ["ro"],
  25: ["ru"],
  26: ["hr", null, "sr"],
  27: ["sk"],
  28: ["sq"],
  29: ["sv", "sv-SE", "sv-FI"],
  30: ["th"],
  31: ["tr"],
  32: ["ur"],
  33: ["id"],
  34: ["uk"],
  35: ["be"],
  36: ["sl"],
  37: ["et"],
  38: ["lv"],
  39: ["lt"],
  41: ["fa"],
  42: ["vi"],
  43: ["hy"],
  44: ["az"],
  45: ["eu"],
  46: ["hsb"],
  47: ["mk"],
  48: ["st"],
  49: ["ts"],
  50: ["tn"],
  52: ["xh"],
  53: ["zu"],
  54: ["af"],
  55: ["ka"],
  56: ["fo"],
  57: ["hi"],
  58: ["mt"],
  59: ["se"],
  62: ["ms"],
  63: ["kk"],
  65: ["sw"],
  67: ["uz", null, "uz-UZ"],
  68: ["tt"],
  69: ["bn"],
  70: ["pa"],
  71: ["gu"],
  72: ["or"],
  73: ["ta"],
  74: ["te"],
  75: ["kn"],
  76: ["ml"],
  77: ["as"],
  78: ["mr"],
  79: ["sa"],
  82: ["cy", "cy-GB"],
  83: ["gl", "gl-ES"],
  87: ["kok"],
  97: ["ne"],
  98: ["fy"]
};
const concatTypedArray = (a, b) => {
  const result = new a.constructor(a.length + b.length);
  result.set(a);
  result.set(b, a.length);
  return result;
};
const concatTypedArray3 = (a, b, c) => {
  const result = new a.constructor(a.length + b.length + c.length);
  result.set(a);
  result.set(b, a.length);
  result.set(c, a.length + b.length);
  return result;
};
const decoder = new TextDecoder();
const getString = (buffer) => decoder.decode(buffer);
const getUint = (buffer) => {
  if (!buffer) return;
  const l = buffer.byteLength;
  const func = l === 4 ? "getUint32" : l === 2 ? "getUint16" : "getUint8";
  return new DataView(buffer)[func](0);
};
const getStruct = (def, buffer) => Object.fromEntries(Array.from(Object.entries(def)).map(([key, [start, len, type]]) => [
  key,
  (type === "string" ? getString : getUint)(buffer.slice(start, start + len))
]));
const getDecoder = (x) => new TextDecoder(MOBI_ENCODING[x]);
const getVarLen = (byteArray, i = 0) => {
  let value = 0, length = 0;
  for (const byte of byteArray.subarray(i, i + 4)) {
    value = value << 7 | (byte & 127) >>> 0;
    length++;
    if (byte & 128) break;
  }
  return { value, length };
};
const getVarLenFromEnd = (byteArray) => {
  let value = 0;
  for (const byte of byteArray.subarray(-4)) {
    if (byte & 128) value = 0;
    value = value << 7 | byte & 127;
  }
  return value;
};
const countBitsSet = (x) => {
  let count = 0;
  for (; x > 0; x = x >> 1) if ((x & 1) === 1) count++;
  return count;
};
const countUnsetEnd = (x) => {
  let count = 0;
  while ((x & 1) === 0) x = x >> 1, count++;
  return count;
};
const decompressPalmDOC = (array) => {
  let output = [];
  for (let i = 0; i < array.length; i++) {
    const byte = array[i];
    if (byte === 0) output.push(0);
    else if (byte <= 8)
      for (const x of array.subarray(i + 1, (i += byte) + 1))
        output.push(x);
    else if (byte <= 127) output.push(byte);
    else if (byte <= 191) {
      const bytes = byte << 8 | array[i++ + 1];
      const distance = (bytes & 16383) >>> 3;
      const length = (bytes & 7) + 3;
      for (let j = 0; j < length; j++)
        output.push(output[output.length - distance]);
    } else output.push(32, byte ^ 128);
  }
  return Uint8Array.from(output);
};
const read32Bits = (byteArray, from) => {
  const startByte = from >> 3;
  const end = from + 32;
  const endByte = end >> 3;
  let bits = 0n;
  for (let i = startByte; i <= endByte; i++)
    bits = bits << 8n | BigInt(byteArray[i] ?? 0);
  return bits >> 8n - BigInt(end & 7) & 0xffffffffn;
};
const huffcdic = async (mobi, loadRecord) => {
  const huffRecord = await loadRecord(mobi.huffcdic);
  const { magic, offset1, offset2 } = getStruct(HUFF_HEADER, huffRecord);
  if (magic !== "HUFF") throw new Error("Invalid HUFF record");
  const table1 = Array.from({ length: 256 }, (_, i) => offset1 + i * 4).map((offset) => getUint(huffRecord.slice(offset, offset + 4))).map((x) => [x & 128, x & 31, x >>> 8]);
  const table2 = [null].concat(Array.from({ length: 32 }, (_, i) => offset2 + i * 8).map((offset) => [
    getUint(huffRecord.slice(offset, offset + 4)),
    getUint(huffRecord.slice(offset + 4, offset + 8))
  ]));
  const dictionary = [];
  for (let i = 1; i < mobi.numHuffcdic; i++) {
    const record = await loadRecord(mobi.huffcdic + i);
    const cdic = getStruct(CDIC_HEADER, record);
    if (cdic.magic !== "CDIC") throw new Error("Invalid CDIC record");
    const n = Math.min(1 << cdic.codeLength, cdic.numEntries - dictionary.length);
    const buffer = record.slice(cdic.length);
    for (let i2 = 0; i2 < n; i2++) {
      const offset = getUint(buffer.slice(i2 * 2, i2 * 2 + 2));
      const x = getUint(buffer.slice(offset, offset + 2));
      const length = x & 32767;
      const decompressed = x & 32768;
      const value = new Uint8Array(
        buffer.slice(offset + 2, offset + 2 + length)
      );
      dictionary.push([value, decompressed]);
    }
  }
  const decompress = (byteArray) => {
    let output = new Uint8Array();
    const bitLength = byteArray.byteLength * 8;
    for (let i = 0; i < bitLength; ) {
      const bits = Number(read32Bits(byteArray, i));
      let [found, codeLength, value] = table1[bits >>> 24];
      if (!found) {
        while (bits >>> 32 - codeLength < table2[codeLength][0])
          codeLength += 1;
        value = table2[codeLength][1];
      }
      if ((i += codeLength) > bitLength) break;
      const code = value - (bits >>> 32 - codeLength);
      let [result, decompressed] = dictionary[code];
      if (!decompressed) {
        result = decompress(result);
        dictionary[code] = [result, true];
      }
      output = concatTypedArray(output, result);
    }
    return output;
  };
  return decompress;
};
const getIndexData = async (indxIndex, loadRecord) => {
  const indxRecord = await loadRecord(indxIndex);
  const indx = getStruct(INDX_HEADER, indxRecord);
  if (indx.magic !== "INDX") throw new Error("Invalid INDX record");
  const decoder2 = getDecoder(indx.encoding);
  const tagxBuffer = indxRecord.slice(indx.length);
  const tagx = getStruct(TAGX_HEADER, tagxBuffer);
  if (tagx.magic !== "TAGX") throw new Error("Invalid TAGX section");
  const numTags = (tagx.length - 12) / 4;
  const tagTable = Array.from({ length: numTags }, (_, i) => new Uint8Array(tagxBuffer.slice(12 + i * 4, 12 + i * 4 + 4)));
  const cncx = {};
  let cncxRecordOffset = 0;
  for (let i = 0; i < indx.numCncx; i++) {
    const record = await loadRecord(indxIndex + indx.numRecords + i + 1);
    const array = new Uint8Array(record);
    for (let pos = 0; pos < array.byteLength; ) {
      const index = pos;
      const { value, length } = getVarLen(array, pos);
      pos += length;
      const result = record.slice(pos, pos + value);
      pos += value;
      cncx[cncxRecordOffset + index] = decoder2.decode(result);
    }
    cncxRecordOffset += 65536;
  }
  const table = [];
  for (let i = 0; i < indx.numRecords; i++) {
    const record = await loadRecord(indxIndex + 1 + i);
    const array = new Uint8Array(record);
    const indx2 = getStruct(INDX_HEADER, record);
    if (indx2.magic !== "INDX") throw new Error("Invalid INDX record");
    for (let j = 0; j < indx2.numRecords; j++) {
      const offsetOffset = indx2.idxt + 4 + 2 * j;
      const offset = getUint(record.slice(offsetOffset, offsetOffset + 2));
      const length = getUint(record.slice(offset, offset + 1));
      const name = getString(record.slice(offset + 1, offset + 1 + length));
      const tags = [];
      const startPos = offset + 1 + length;
      let controlByteIndex = 0;
      let pos = startPos + tagx.numControlBytes;
      for (const [tag, numValues, mask, end] of tagTable) {
        if (end & 1) {
          controlByteIndex++;
          continue;
        }
        const offset2 = startPos + controlByteIndex;
        const value = getUint(record.slice(offset2, offset2 + 1)) & mask;
        if (value === mask) {
          if (countBitsSet(mask) > 1) {
            const { value: value2, length: length2 } = getVarLen(array, pos);
            tags.push([tag, null, value2, numValues]);
            pos += length2;
          } else tags.push([tag, 1, null, numValues]);
        } else tags.push([tag, value >> countUnsetEnd(mask), null, numValues]);
      }
      const tagMap = {};
      for (const [tag, valueCount, valueBytes, numValues] of tags) {
        const values = [];
        if (valueCount != null) {
          for (let i2 = 0; i2 < valueCount * numValues; i2++) {
            const { value, length: length2 } = getVarLen(array, pos);
            values.push(value);
            pos += length2;
          }
        } else {
          let count = 0;
          while (count < valueBytes) {
            const { value, length: length2 } = getVarLen(array, pos);
            values.push(value);
            pos += length2;
            count += length2;
          }
        }
        tagMap[tag] = values;
      }
      table.push({ name, tagMap });
    }
  }
  return { table, cncx };
};
const getNCX = async (indxIndex, loadRecord) => {
  const { table, cncx } = await getIndexData(indxIndex, loadRecord);
  const items = table.map(({ tagMap }, index) => {
    var _a, _b, _c, _d, _e, _f;
    return {
      index,
      offset: (_a = tagMap[1]) == null ? void 0 : _a[0],
      size: (_b = tagMap[2]) == null ? void 0 : _b[0],
      label: cncx[tagMap[3]] ?? "",
      headingLevel: (_c = tagMap[4]) == null ? void 0 : _c[0],
      pos: tagMap[6],
      parent: (_d = tagMap[21]) == null ? void 0 : _d[0],
      firstChild: (_e = tagMap[22]) == null ? void 0 : _e[0],
      lastChild: (_f = tagMap[23]) == null ? void 0 : _f[0]
    };
  });
  const getChildren = (item) => {
    if (item.firstChild == null) return item;
    item.children = items.filter((x) => x.parent === item.index).map(getChildren);
    return item;
  };
  return items.filter((item) => item.headingLevel === 0).map(getChildren);
};
const getEXTH = (buf, encoding) => {
  const { magic, count } = getStruct(EXTH_HEADER, buf);
  if (magic !== "EXTH") throw new Error("Invalid EXTH header");
  const decoder2 = getDecoder(encoding);
  const results = {};
  let offset = 12;
  for (let i = 0; i < count; i++) {
    const type = getUint(buf.slice(offset, offset + 4));
    const length = getUint(buf.slice(offset + 4, offset + 8));
    if (type in EXTH_RECORD_TYPE) {
      const [name, typ, many] = EXTH_RECORD_TYPE[type];
      const data = buf.slice(offset + 8, offset + length);
      const value = typ === "uint" ? getUint(data) : decoder2.decode(data);
      if (many) {
        results[name] ?? (results[name] = []);
        results[name].push(value);
      } else results[name] = value;
    }
    offset += length;
  }
  return results;
};
const getFont = async (buf, unzlib) => {
  const { flags, dataStart, keyLength, keyStart } = getStruct(FONT_HEADER, buf);
  const array = new Uint8Array(buf.slice(dataStart));
  if (flags & 2) {
    const bytes = keyLength === 16 ? 1024 : 1040;
    const key = new Uint8Array(buf.slice(keyStart, keyStart + keyLength));
    const length = Math.min(bytes, array.length);
    for (var i = 0; i < length; i++) array[i] = array[i] ^ key[i % key.length];
  }
  if (flags & 1) try {
    return await unzlib(array);
  } catch (e) {
    console.warn(e);
    console.warn("Failed to decompress font");
  }
  return array;
};
const isMOBI = async (file) => {
  const magic = getString(await file.slice(60, 68).arrayBuffer());
  return magic === "BOOKMOBI";
};
class PDB {
  constructor() {
    __privateAdd(this, _file);
    __privateAdd(this, _offsets);
    __publicField(this, "pdb");
  }
  async open(file) {
    __privateSet(this, _file, file);
    const pdb = getStruct(PDB_HEADER, await file.slice(0, 78).arrayBuffer());
    this.pdb = pdb;
    const buffer = await file.slice(78, 78 + pdb.numRecords * 8).arrayBuffer();
    __privateSet(this, _offsets, Array.from(
      { length: pdb.numRecords },
      (_, i) => getUint(buffer.slice(i * 8, i * 8 + 4))
    ).map((x, i, a) => [x, a[i + 1]]));
  }
  loadRecord(index) {
    const offsets = __privateGet(this, _offsets)[index];
    if (!offsets) throw new RangeError("Record index out of bounds");
    return __privateGet(this, _file).slice(...offsets).arrayBuffer();
  }
  async loadMagic(index) {
    const start = __privateGet(this, _offsets)[index][0];
    return getString(await __privateGet(this, _file).slice(start, start + 4).arrayBuffer());
  }
}
_file = new WeakMap();
_offsets = new WeakMap();
class MOBI extends PDB {
  constructor({ unzlib }) {
    super();
    __privateAdd(this, _MOBI_instances);
    __privateAdd(this, _start, 0);
    __privateAdd(this, _resourceStart);
    __privateAdd(this, _decoder);
    __privateAdd(this, _encoder);
    __privateAdd(this, _decompress);
    __privateAdd(this, _removeTrailingEntries);
    this.unzlib = unzlib;
  }
  async open(file, { metadataOnly = false } = {}) {
    var _a;
    await super.open(file);
    this.headers = __privateMethod(this, _MOBI_instances, getHeaders_fn).call(this, await super.loadRecord(0));
    __privateSet(this, _resourceStart, this.headers.mobi.resourceStart);
    let isKF8 = this.headers.mobi.version >= 8;
    if (!isKF8) {
      const boundary = (_a = this.headers.exth) == null ? void 0 : _a.boundary;
      if (boundary < 4294967295) try {
        this.headers = __privateMethod(this, _MOBI_instances, getHeaders_fn).call(this, await super.loadRecord(boundary));
        __privateSet(this, _start, boundary);
        isKF8 = true;
      } catch (e) {
        console.warn(e);
        console.warn("Failed to open KF8; falling back to MOBI");
      }
    }
    await __privateMethod(this, _MOBI_instances, setup_fn).call(this);
    if (metadataOnly) return this;
    return isKF8 ? new KF8(this).init() : new MOBI6(this).init();
  }
  decode(...args) {
    return __privateGet(this, _decoder).decode(...args);
  }
  encode(...args) {
    return __privateGet(this, _encoder).encode(...args);
  }
  loadRecord(index) {
    return super.loadRecord(__privateGet(this, _start) + index);
  }
  loadMagic(index) {
    return super.loadMagic(__privateGet(this, _start) + index);
  }
  loadText(index) {
    return this.loadRecord(index + 1).then((buf) => new Uint8Array(buf)).then(__privateGet(this, _removeTrailingEntries)).then(__privateGet(this, _decompress));
  }
  async loadResource(index) {
    const buf = await super.loadRecord(__privateGet(this, _resourceStart) + index);
    const magic = getString(buf.slice(0, 4));
    if (magic === "FONT") return getFont(buf, this.unzlib);
    if (magic === "VIDE" || magic === "AUDI") return buf.slice(12);
    return buf;
  }
  getNCX() {
    const index = this.headers.mobi.indx;
    if (index < 4294967295) return getNCX(index, this.loadRecord.bind(this));
  }
  getMetadata() {
    var _a, _b;
    const { mobi, exth } = this.headers;
    return {
      identifier: mobi.uid.toString(),
      title: unescapeHTML((exth == null ? void 0 : exth.title) || this.decode(mobi.title)),
      author: (_a = exth == null ? void 0 : exth.creator) == null ? void 0 : _a.map(unescapeHTML),
      publisher: unescapeHTML(exth == null ? void 0 : exth.publisher),
      language: (exth == null ? void 0 : exth.language) ?? mobi.language,
      published: exth == null ? void 0 : exth.date,
      description: unescapeHTML(exth == null ? void 0 : exth.description),
      subject: (_b = exth == null ? void 0 : exth.subject) == null ? void 0 : _b.map(unescapeHTML),
      rights: unescapeHTML(exth == null ? void 0 : exth.rights),
      contributor: exth == null ? void 0 : exth.contributor
    };
  }
  async getCover() {
    const { exth } = this.headers;
    const offset = (exth == null ? void 0 : exth.coverOffset) < 4294967295 ? exth == null ? void 0 : exth.coverOffset : (exth == null ? void 0 : exth.thumbnailOffset) < 4294967295 ? exth == null ? void 0 : exth.thumbnailOffset : null;
    if (offset != null) {
      const buf = await this.loadResource(offset);
      return new Blob([buf]);
    }
  }
}
_start = new WeakMap();
_resourceStart = new WeakMap();
_decoder = new WeakMap();
_encoder = new WeakMap();
_decompress = new WeakMap();
_removeTrailingEntries = new WeakMap();
_MOBI_instances = new WeakSet();
getHeaders_fn = function(buf) {
  const palmdoc = getStruct(PALMDOC_HEADER, buf);
  const mobi = getStruct(MOBI_HEADER, buf);
  if (mobi.magic !== "MOBI") throw new Error("Missing MOBI header");
  const { titleOffset, titleLength, localeLanguage, localeRegion } = mobi;
  mobi.title = buf.slice(titleOffset, titleOffset + titleLength);
  const lang = MOBI_LANG[localeLanguage];
  mobi.language = (lang == null ? void 0 : lang[localeRegion >> 2]) ?? (lang == null ? void 0 : lang[0]);
  const exth = mobi.exthFlag & 64 ? getEXTH(buf.slice(mobi.length + 16), mobi.encoding) : null;
  const kf8 = mobi.version >= 8 ? getStruct(KF8_HEADER, buf) : null;
  return { palmdoc, mobi, exth, kf8 };
};
setup_fn = async function() {
  const { palmdoc, mobi } = this.headers;
  __privateSet(this, _decoder, getDecoder(mobi.encoding));
  __privateSet(this, _encoder, new TextEncoder());
  const { compression } = palmdoc;
  __privateSet(this, _decompress, compression === 1 ? (f) => f : compression === 2 ? decompressPalmDOC : compression === 17480 ? await huffcdic(mobi, this.loadRecord.bind(this)) : null);
  if (!__privateGet(this, _decompress)) throw new Error("Unknown compression type");
  const { trailingFlags } = mobi;
  const multibyte = trailingFlags & 1;
  const numTrailingEntries = countBitsSet(trailingFlags >>> 1);
  __privateSet(this, _removeTrailingEntries, (array) => {
    for (let i = 0; i < numTrailingEntries; i++) {
      const length = getVarLenFromEnd(array);
      array = array.subarray(0, -length);
    }
    if (multibyte) {
      const length = (array[array.length - 1] & 3) + 1;
      array = array.subarray(0, -length);
    }
    return array;
  });
};
const mbpPagebreakRegex = /<\s*(?:mbp:)?pagebreak[^>]*>/gi;
const fileposRegex = /<[^<>]+filepos=['"]{0,1}(\d+)[^<>]*>/gi;
const selfClosingRegex = /<(a|div|span|p)\s*\/>/gi;
const getIndent = (el) => {
  let x = 0;
  while (el) {
    const parent = el.parentElement;
    if (parent) {
      const tag = parent.tagName.toLowerCase();
      if (tag === "p") x += 1.5;
      else if (tag === "blockquote") x += 2;
    }
    el = parent;
  }
  return x;
};
function rawBytesToString(uint8Array) {
  const chunkSize = 32768;
  let result = "";
  for (let i = 0; i < uint8Array.length; i += chunkSize) {
    result += String.fromCharCode.apply(null, uint8Array.subarray(i, i + chunkSize));
  }
  return result;
}
const getImageType = (raw) => {
  const b = ArrayBuffer.isView(raw) ? raw : new Uint8Array(raw);
  if (b[0] === 255 && b[1] === 216) return "image/jpeg";
  if (b[0] === 137 && b[1] === 80 && b[2] === 78 && b[3] === 71) return "image/png";
  if (b[0] === 71 && b[1] === 73 && b[2] === 70) return "image/gif";
  if (b[0] === 66 && b[1] === 77) return "image/bmp";
  return "";
};
class MOBI6 {
  constructor(mobi) {
    __privateAdd(this, _MOBI6_instances);
    __publicField(this, "parser", new DOMParser());
    __publicField(this, "serializer", new XMLSerializer());
    __privateAdd(this, _resourceCache, /* @__PURE__ */ new Map());
    __privateAdd(this, _textCache, /* @__PURE__ */ new Map());
    __privateAdd(this, _cache, /* @__PURE__ */ new Map());
    __privateAdd(this, _sections);
    __privateAdd(this, _fileposList, []);
    __privateAdd(this, _type, MIME.HTML);
    this.mobi = mobi;
  }
  async init() {
    var _a;
    const recordBuffers = [];
    for (let i = 0; i < this.mobi.headers.palmdoc.numTextRecords; i++) {
      const buf = await this.mobi.loadText(i);
      recordBuffers.push(buf);
    }
    const totalLength = recordBuffers.reduce((sum, buf) => sum + buf.byteLength, 0);
    const array = new Uint8Array(totalLength);
    recordBuffers.reduce((offset, buf) => {
      array.set(new Uint8Array(buf), offset);
      return offset + buf.byteLength;
    }, 0);
    const str = rawBytesToString(array);
    __privateSet(this, _sections, [0].concat(Array.from(str.matchAll(mbpPagebreakRegex), (m) => m.index)).map((start, i, a) => {
      const end = a[i + 1] ?? array.length;
      return { book: this, raw: array.subarray(start, end) };
    }).map((section, i, arr) => {
      var _a2;
      section.start = ((_a2 = arr[i - 1]) == null ? void 0 : _a2.end) ?? 0;
      section.end = section.start + section.raw.byteLength;
      return section;
    }));
    this.sections = __privateGet(this, _sections).map((section, index) => ({
      id: index,
      load: () => this.loadSection(section),
      createDocument: () => this.createDocument(section),
      size: section.end - section.start
    }));
    try {
      this.landmarks = await this.getGuide();
      const tocHref = (_a = this.landmarks.find(({ type }) => type == null ? void 0 : type.includes("toc"))) == null ? void 0 : _a.href;
      if (tocHref) {
        const { index } = this.resolveHref(tocHref);
        const doc = await this.sections[index].createDocument();
        let lastItem;
        let lastLevel = 0;
        let lastIndent = 0;
        const lastLevelOfIndent = /* @__PURE__ */ new Map();
        const lastParentOfLevel = /* @__PURE__ */ new Map();
        this.toc = Array.from(doc.querySelectorAll("a[filepos]")).reduce((arr, a) => {
          var _a2;
          const indent = getIndent(a);
          const item = {
            label: ((_a2 = a.innerText) == null ? void 0 : _a2.trim()) ?? "",
            href: `filepos:${a.getAttribute("filepos")}`
          };
          const level = indent > lastIndent ? lastLevel + 1 : indent === lastIndent ? lastLevel : lastLevelOfIndent.get(indent) ?? Math.max(0, lastLevel - 1);
          if (level > lastLevel) {
            if (lastItem) {
              lastItem.subitems ?? (lastItem.subitems = []);
              lastItem.subitems.push(item);
              lastParentOfLevel.set(level, lastItem);
            } else arr.push(item);
          } else {
            const parent = lastParentOfLevel.get(level);
            if (parent) parent.subitems.push(item);
            else arr.push(item);
          }
          lastItem = item;
          lastLevel = level;
          lastIndent = indent;
          lastLevelOfIndent.set(indent, level);
          return arr;
        }, []);
      }
    } catch (e) {
      console.warn(e);
    }
    __privateSet(this, _fileposList, [...new Set(
      Array.from(str.matchAll(fileposRegex), (m) => m[1])
    )].map((filepos) => ({ filepos, number: Number(filepos) })).sort((a, b) => a.number - b.number));
    this.metadata = this.mobi.getMetadata();
    this.getCover = this.mobi.getCover.bind(this.mobi);
    return this;
  }
  async getGuide() {
    const doc = await this.createDocument(__privateGet(this, _sections)[0]);
    return Array.from(doc.getElementsByTagName("reference"), (ref) => {
      var _a;
      return {
        label: ref.getAttribute("title"),
        type: (_a = ref.getAttribute("type")) == null ? void 0 : _a.split(/\s/),
        href: `filepos:${ref.getAttribute("filepos")}`
      };
    });
  }
  async loadResource(index) {
    if (__privateGet(this, _resourceCache).has(index)) return __privateGet(this, _resourceCache).get(index);
    const raw = await this.mobi.loadResource(index);
    const url = URL.createObjectURL(new Blob([raw], { type: getImageType(raw) }));
    __privateGet(this, _resourceCache).set(index, url);
    return url;
  }
  async loadRecindex(recindex) {
    return this.loadResource(Number(recindex) - 1);
  }
  async replaceResources(doc) {
    for (const img of doc.querySelectorAll("img[recindex]")) {
      const recindex = img.getAttribute("recindex");
      try {
        img.src = await this.loadRecindex(recindex);
      } catch {
        console.warn(`Failed to load image ${recindex}`);
      }
    }
    for (const media of doc.querySelectorAll("[mediarecindex]")) {
      const mediarecindex = media.getAttribute("mediarecindex");
      const recindex = media.getAttribute("recindex");
      try {
        media.src = await this.loadRecindex(mediarecindex);
        if (recindex) media.poster = await this.loadRecindex(recindex);
      } catch {
        console.warn(`Failed to load media ${mediarecindex}`);
      }
    }
    for (const a of doc.querySelectorAll("[filepos]")) {
      const filepos = a.getAttribute("filepos");
      a.href = `filepos:${filepos}`;
    }
  }
  async loadText(section) {
    if (__privateGet(this, _textCache).has(section)) return __privateGet(this, _textCache).get(section);
    const { raw } = section;
    const fileposList = __privateGet(this, _fileposList).filter(({ number }) => number >= section.start && number < section.end).map((obj) => ({ ...obj, offset: obj.number - section.start }));
    let arr = raw;
    if (fileposList.length) {
      arr = raw.subarray(0, fileposList[0].offset);
      fileposList.forEach(({ filepos, offset }, i) => {
        const next = fileposList[i + 1];
        const a = this.mobi.encode(`<a id="filepos${filepos}"></a>`);
        arr = concatTypedArray3(arr, a, raw.subarray(offset, next == null ? void 0 : next.offset));
      });
    }
    const str = this.mobi.decode(arr).replaceAll(mbpPagebreakRegex, "");
    __privateGet(this, _textCache).set(section, str);
    return str;
  }
  async createDocument(section) {
    const str = await this.loadText(section);
    return this.parser.parseFromString(__privateMethod(this, _MOBI6_instances, sanitize_fn).call(this, str), __privateGet(this, _type));
  }
  async loadSection(section) {
    if (__privateGet(this, _cache).has(section)) return __privateGet(this, _cache).get(section);
    const doc = await this.createDocument(section);
    const style = doc.createElement("style");
    doc.head.append(style);
    style.append(doc.createTextNode(`blockquote {
            margin-block-start: 0;
            margin-block-end: 0;
            margin-inline-start: 1em;
            margin-inline-end: 0;
        }`));
    await this.replaceResources(doc);
    const result = this.serializer.serializeToString(doc);
    const url = URL.createObjectURL(new Blob([result], { type: __privateGet(this, _type) }));
    __privateGet(this, _cache).set(section, url);
    return url;
  }
  resolveHref(href) {
    const filepos = href.match(/filepos:(.*)/)[1];
    const number = Number(filepos);
    const index = __privateGet(this, _sections).findIndex((section) => section.end > number);
    const anchor = (doc) => doc.getElementById(`filepos${filepos}`);
    return { index, anchor };
  }
  splitTOCHref(href) {
    const filepos = href.match(/filepos:(.*)/)[1];
    const number = Number(filepos);
    const index = __privateGet(this, _sections).findIndex((section) => section.end > number);
    return [index, `filepos${filepos}`];
  }
  getTOCFragment(doc, id) {
    return doc.getElementById(id);
  }
  isExternal(uri) {
    return /^(?!blob|filepos)\w+:/i.test(uri);
  }
  destroy() {
    for (const url of __privateGet(this, _resourceCache).values()) URL.revokeObjectURL(url);
    for (const url of __privateGet(this, _cache).values()) URL.revokeObjectURL(url);
  }
}
_resourceCache = new WeakMap();
_textCache = new WeakMap();
_cache = new WeakMap();
_sections = new WeakMap();
_fileposList = new WeakMap();
_type = new WeakMap();
_MOBI6_instances = new WeakSet();
sanitize_fn = function(str) {
  return str.replace(selfClosingRegex, "<$1></$1>");
};
const kindleResourceRegex = /kindle:(flow|embed):(\w+)(?:\?mime=(\w+\/[-+.\w]+))?/;
const kindlePosRegex = /kindle:pos:fid:(\w+):off:(\w+)/;
const parseResourceURI = (str) => {
  const [resourceType, id, type] = str.match(kindleResourceRegex).slice(1);
  return { resourceType, id: parseInt(id, 32), type };
};
const parsePosURI = (str) => {
  const [fid, off] = str.match(kindlePosRegex).slice(1);
  return { fid: parseInt(fid, 32), off: parseInt(off, 32) };
};
const makePosURI = (fid = 0, off = 0) => `kindle:pos:fid:${fid.toString(32).toUpperCase().padStart(4, "0")}:off:${off.toString(32).toUpperCase().padStart(10, "0")}`;
const getFragmentSelector = (str) => {
  const match = str.match(/\s(id|name|aid)\s*=\s*['"]([^'"]*)['"]/i);
  if (!match) return;
  const [, attr, value] = match;
  return `[${attr}="${CSS.escape(value)}"]`;
};
const replaceSeries = async (str, regex, f) => {
  const matches = [];
  str.replace(regex, (...args) => (matches.push(args), null));
  const results = [];
  for (const args of matches) results.push(await f(...args));
  return str.replace(regex, () => results.shift());
};
const getPageSpread = (properties) => {
  for (const p of properties) {
    if (p === "page-spread-left" || p === "rendition:page-spread-left")
      return "left";
    if (p === "page-spread-right" || p === "rendition:page-spread-right")
      return "right";
    if (p === "rendition:page-spread-center") return "center";
  }
};
class KF8 {
  constructor(mobi) {
    __privateAdd(this, _KF8_instances);
    __publicField(this, "parser", new DOMParser());
    __publicField(this, "serializer", new XMLSerializer());
    __publicField(this, "transformTarget", new EventTarget());
    __privateAdd(this, _cache2, /* @__PURE__ */ new Map());
    __privateAdd(this, _fragmentOffsets, /* @__PURE__ */ new Map());
    __privateAdd(this, _fragmentSelectors, /* @__PURE__ */ new Map());
    __privateAdd(this, _tables, {});
    __privateAdd(this, _sections2);
    __privateAdd(this, _fullRawLength);
    __privateAdd(this, _rawHead, new Uint8Array());
    __privateAdd(this, _rawTail, new Uint8Array());
    __privateAdd(this, _lastLoadedHead, -1);
    __privateAdd(this, _lastLoadedTail, -1);
    __privateAdd(this, _rawQueue, Promise.resolve());
    __privateAdd(this, _type2, MIME.XHTML);
    __privateAdd(this, _inlineMap, /* @__PURE__ */ new Map());
    this.mobi = mobi;
  }
  async init() {
    var _a, _b, _c, _d;
    const loadRecord = this.mobi.loadRecord.bind(this.mobi);
    const { kf8 } = this.mobi.headers;
    try {
      const fdstBuffer = await loadRecord(kf8.fdst);
      const fdst = getStruct(FDST_HEADER, fdstBuffer);
      if (fdst.magic !== "FDST") throw new Error("Missing FDST record");
      const fdstTable = Array.from(
        { length: fdst.numEntries },
        (_, i) => 12 + i * 8
      ).map((offset) => [
        getUint(fdstBuffer.slice(offset, offset + 4)),
        getUint(fdstBuffer.slice(offset + 4, offset + 8))
      ]);
      __privateGet(this, _tables).fdstTable = fdstTable;
      __privateSet(this, _fullRawLength, fdstTable[fdstTable.length - 1][1]);
    } catch {
    }
    const skelTable = (await getIndexData(kf8.skel, loadRecord)).table.map(({ name, tagMap }, index) => ({
      index,
      name,
      numFrag: tagMap[1][0],
      offset: tagMap[6][0],
      length: tagMap[6][1]
    }));
    const fragData = await getIndexData(kf8.frag, loadRecord);
    const fragTable = fragData.table.map(({ name, tagMap }) => ({
      insertOffset: parseInt(name),
      selector: fragData.cncx[tagMap[2][0]],
      index: tagMap[4][0],
      offset: tagMap[6][0],
      length: tagMap[6][1]
    }));
    __privateGet(this, _tables).skelTable = skelTable;
    __privateGet(this, _tables).fragTable = fragTable;
    __privateSet(this, _sections2, skelTable.reduce((arr, skel) => {
      const last = arr[arr.length - 1];
      const fragStart = (last == null ? void 0 : last.fragEnd) ?? 0, fragEnd = fragStart + skel.numFrag;
      const frags = fragTable.slice(fragStart, fragEnd);
      const length = skel.length + frags.map((f) => f.length).reduce((a, b) => a + b, 0);
      const totalLength = ((last == null ? void 0 : last.totalLength) ?? 0) + length;
      return arr.concat({ skel, frags, fragEnd, length, totalLength });
    }, []));
    const resources = await this.getResourcesByMagic(["RESC", "PAGE"]);
    const pageSpreads = /* @__PURE__ */ new Map();
    if (resources.RESC) {
      const buf = await this.mobi.loadRecord(resources.RESC);
      const str = this.mobi.decode(buf.slice(16)).replace(/\0/g, "");
      const index = str.search(/\?>/);
      const xmlStr = `<package>${str.slice(index)}</package>`;
      const opf = this.parser.parseFromString(xmlStr, MIME.XML);
      for (const $itemref of opf.querySelectorAll("spine > itemref")) {
        const i = parseInt($itemref.getAttribute("skelid"));
        pageSpreads.set(i, getPageSpread(
          ((_a = $itemref.getAttribute("properties")) == null ? void 0 : _a.split(" ")) ?? []
        ));
      }
    }
    this.sections = __privateGet(this, _sections2).map((section, index) => section.frags.length ? {
      id: index,
      load: () => this.loadSection(section),
      createDocument: () => this.createDocument(section),
      size: section.length,
      pageSpread: pageSpreads.get(index)
    } : { linear: "no" });
    try {
      const ncx = await this.mobi.getNCX();
      const map = ({ label, pos, children }) => {
        const [fid, off] = pos;
        const href = makePosURI(fid, off);
        const arr = __privateGet(this, _fragmentOffsets).get(fid);
        if (arr) arr.push(off);
        else __privateGet(this, _fragmentOffsets).set(fid, [off]);
        return { label: unescapeHTML(label), href, subitems: children == null ? void 0 : children.map(map) };
      };
      this.toc = ncx == null ? void 0 : ncx.map(map);
      this.landmarks = await this.getGuide();
    } catch (e) {
      console.warn(e);
    }
    const { exth } = this.mobi.headers;
    this.dir = exth.pageProgressionDirection;
    this.rendition = {
      layout: exth.fixedLayout === "true" ? "pre-paginated" : "reflowable",
      viewport: Object.fromEntries(((_d = (_c = (_b = exth.originalResolution) == null ? void 0 : _b.split("x")) == null ? void 0 : _c.slice(0, 2)) == null ? void 0 : _d.map((x, i) => [i ? "height" : "width", x])) ?? [])
    };
    this.metadata = this.mobi.getMetadata();
    this.getCover = this.mobi.getCover.bind(this.mobi);
    return this;
  }
  // is this really the only way of getting to RESC, PAGE, etc.?
  async getResourcesByMagic(keys) {
    const results = {};
    const start = this.mobi.headers.kf8.resourceStart;
    const end = this.mobi.pdb.numRecords;
    for (let i = start; i < end; i++) {
      try {
        const magic = await this.mobi.loadMagic(i);
        const match = keys.find((key) => key === magic);
        if (match) results[match] = i;
      } catch {
      }
    }
    return results;
  }
  async getGuide() {
    const index = this.mobi.headers.kf8.guide;
    if (index < 4294967295) {
      const loadRecord = this.mobi.loadRecord.bind(this.mobi);
      const { table, cncx } = await getIndexData(index, loadRecord);
      return table.map(({ name, tagMap }) => {
        var _a, _b;
        return {
          label: cncx[tagMap[1][0]] ?? "",
          type: name == null ? void 0 : name.split(/\s/),
          href: makePosURI(((_a = tagMap[6]) == null ? void 0 : _a[0]) ?? ((_b = tagMap[3]) == null ? void 0 : _b[0]))
        };
      });
    }
  }
  async loadResourceBlob(str) {
    var _a;
    const { resourceType, id, type } = parseResourceURI(str);
    const raw = resourceType === "flow" ? await this.loadFlow(id) : await this.mobi.loadResource(id - 1);
    const result = [MIME.XHTML, MIME.HTML, MIME.CSS, MIME.SVG].includes(type) ? await this.replaceResources(this.mobi.decode(raw)) : raw;
    const detail = { data: result, type };
    const event = new CustomEvent("data", { detail });
    this.transformTarget.dispatchEvent(event);
    const newData = await event.detail.data;
    const newType = await event.detail.type;
    const doc = newType === MIME.SVG ? this.parser.parseFromString(newData, newType) : null;
    return [
      new Blob([newData], { type: newType }),
      // SVG wrappers need to be inlined
      // as browsers don't allow external resources when loading SVG as an image
      ((_a = doc == null ? void 0 : doc.getElementsByTagNameNS("http://www.w3.org/2000/svg", "image")) == null ? void 0 : _a.length) ? doc.documentElement : null
    ];
  }
  async loadResource(str) {
    if (__privateGet(this, _cache2).has(str)) return __privateGet(this, _cache2).get(str);
    const [blob, inline] = await this.loadResourceBlob(str);
    const url = inline ? str : URL.createObjectURL(blob);
    if (inline) __privateGet(this, _inlineMap).set(url, inline);
    __privateGet(this, _cache2).set(str, url);
    return url;
  }
  replaceResources(str) {
    const regex = new RegExp(kindleResourceRegex, "g");
    return replaceSeries(str, regex, this.loadResource.bind(this));
  }
  // NOTE: there doesn't seem to be a way to access text randomly?
  // how to know the decompressed size of the records without decompressing?
  // 4096 is just the maximum size
  //
  // `#loadRawLocked` appends records to `#rawHead` / `#rawTail` across an
  // `await`, so overlapping calls would interleave and land the records in
  // completion order instead of index order, shifting every byte offset
  // after the first out-of-order append. That never showed up when the book
  // is an in-memory `File` (slices settle in issue order), but a file read
  // through ranged requests finishes out of order, and the renderer does
  // overlap loads — it preloads the adjacent section while another one is
  // still loading. Serialize on a promise chain so the walk stays ordered;
  // whichever call runs second usually finds its window already buffered.
  loadRaw(start, end) {
    const result = __privateGet(this, _rawQueue).then(() => __privateMethod(this, _KF8_instances, loadRawLocked_fn).call(this, start, end));
    __privateSet(this, _rawQueue, result.then(() => {
    }, () => {
    }));
    return result;
  }
  loadFlow(index) {
    if (index < 4294967295)
      return this.loadRaw(...__privateGet(this, _tables).fdstTable[index]);
  }
  async loadText(section) {
    const { skel, frags, length } = section;
    const raw = await this.loadRaw(skel.offset, skel.offset + length);
    let skeleton = raw.slice(0, skel.length);
    for (const frag of frags) {
      const insertOffset = frag.insertOffset - skel.offset;
      const offset = skel.length + frag.offset;
      const fragRaw = raw.slice(offset, offset + frag.length);
      skeleton = concatTypedArray3(
        skeleton.slice(0, insertOffset),
        fragRaw,
        skeleton.slice(insertOffset)
      );
      const offsets = __privateGet(this, _fragmentOffsets).get(frag.index);
      if (offsets) for (const offset2 of offsets) {
        const str = this.mobi.decode(fragRaw.slice(offset2));
        const selector = getFragmentSelector(str);
        __privateMethod(this, _KF8_instances, setFragmentSelector_fn).call(this, frag.index, offset2, selector);
      }
    }
    return this.mobi.decode(skeleton);
  }
  async createDocument(section) {
    const str = await this.loadText(section);
    return this.parser.parseFromString(str, __privateGet(this, _type2));
  }
  async loadSection(section) {
    var _a;
    if (__privateGet(this, _cache2).has(section)) return __privateGet(this, _cache2).get(section);
    const str = await this.loadText(section);
    const replaced = await this.replaceResources(str);
    let doc = this.parser.parseFromString(replaced, __privateGet(this, _type2));
    if (doc.querySelector("parsererror") || !((_a = doc.documentElement) == null ? void 0 : _a.namespaceURI)) {
      __privateSet(this, _type2, MIME.HTML);
      doc = this.parser.parseFromString(replaced, __privateGet(this, _type2));
    }
    for (const [url2, node] of __privateGet(this, _inlineMap)) {
      for (const el of doc.querySelectorAll(`img[src="${url2}"]`))
        el.replaceWith(node);
    }
    const url = URL.createObjectURL(
      new Blob([this.serializer.serializeToString(doc)], { type: __privateGet(this, _type2) })
    );
    __privateGet(this, _cache2).set(section, url);
    return url;
  }
  getIndexByFID(fid) {
    return __privateGet(this, _sections2).findIndex((section) => section.frags.some((frag) => frag.index === fid));
  }
  async resolveHref(href) {
    var _a;
    const { fid, off } = parsePosURI(href);
    const index = this.getIndexByFID(fid);
    if (index < 0) return;
    const saved = (_a = __privateGet(this, _fragmentSelectors).get(fid)) == null ? void 0 : _a.get(off);
    if (saved) return { index, anchor: (doc) => doc.querySelector(saved) };
    const { skel, frags } = __privateGet(this, _sections2)[index];
    const frag = frags.find((frag2) => frag2.index === fid);
    const offset = skel.offset + skel.length + frag.offset;
    const fragRaw = await this.loadRaw(offset, offset + frag.length);
    const str = this.mobi.decode(fragRaw.slice(off));
    const selector = getFragmentSelector(str);
    __privateMethod(this, _KF8_instances, setFragmentSelector_fn).call(this, fid, off, selector);
    const anchor = (doc) => doc.querySelector(selector);
    return { index, anchor };
  }
  splitTOCHref(href) {
    const pos = parsePosURI(href);
    const index = this.getIndexByFID(pos.fid);
    return [index, pos];
  }
  getTOCFragment(doc, { fid, off }) {
    var _a;
    const selector = (_a = __privateGet(this, _fragmentSelectors).get(fid)) == null ? void 0 : _a.get(off);
    return doc.querySelector(selector);
  }
  isExternal(uri) {
    return /^(?!blob|kindle)\w+:/i.test(uri);
  }
  destroy() {
    for (const url of __privateGet(this, _cache2).values()) URL.revokeObjectURL(url);
  }
}
_cache2 = new WeakMap();
_fragmentOffsets = new WeakMap();
_fragmentSelectors = new WeakMap();
_tables = new WeakMap();
_sections2 = new WeakMap();
_fullRawLength = new WeakMap();
_rawHead = new WeakMap();
_rawTail = new WeakMap();
_lastLoadedHead = new WeakMap();
_lastLoadedTail = new WeakMap();
_rawQueue = new WeakMap();
_type2 = new WeakMap();
_inlineMap = new WeakMap();
_KF8_instances = new WeakSet();
loadRawLocked_fn = async function(start, end) {
  const distanceHead = end - __privateGet(this, _rawHead).length;
  const distanceEnd = __privateGet(this, _fullRawLength) == null ? Infinity : __privateGet(this, _fullRawLength) - __privateGet(this, _rawTail).length - start;
  if (distanceHead < 0 || distanceHead < distanceEnd) {
    while (__privateGet(this, _rawHead).length < end) {
      const index = ++__privateWrapper(this, _lastLoadedHead)._;
      const data = await this.mobi.loadText(index);
      __privateSet(this, _rawHead, concatTypedArray(__privateGet(this, _rawHead), data));
    }
    return __privateGet(this, _rawHead).slice(start, end);
  }
  while (__privateGet(this, _fullRawLength) - __privateGet(this, _rawTail).length > start) {
    const index = this.mobi.headers.palmdoc.numTextRecords - 1 - ++__privateWrapper(this, _lastLoadedTail)._;
    const data = await this.mobi.loadText(index);
    __privateSet(this, _rawTail, concatTypedArray(data, __privateGet(this, _rawTail)));
  }
  const rawTailStart = __privateGet(this, _fullRawLength) - __privateGet(this, _rawTail).length;
  return __privateGet(this, _rawTail).slice(start - rawTailStart, end - rawTailStart);
};
setFragmentSelector_fn = function(id, offset, selector) {
  const map = __privateGet(this, _fragmentSelectors).get(id);
  if (map) map.set(offset, selector);
  else {
    const map2 = /* @__PURE__ */ new Map();
    __privateGet(this, _fragmentSelectors).set(id, map2);
    map2.set(offset, selector);
  }
};
const readMobiMetadata = async (file, { unzlib } = {}) => {
  const m = await new MOBI({ unzlib }).open(file, { metadataOnly: true });
  return {
    metadata: m.getMetadata(),
    getCover: m.getCover.bind(m)
  };
};
export {
  MOBI,
  isMOBI,
  readMobiMetadata
};
