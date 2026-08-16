import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// KF8 (AZW3) 檔案偵測到 DRM 加密內容時拋出，呼叫端須中止該書匯入、不寫入
/// `Book` 記錄（spec.md「KF8 (AZW3) 支援」）。
class DrmProtectedException implements Exception {
  final String message;
  const DrmProtectedException(this.message);

  @override
  String toString() => 'DrmProtectedException: $message';
}

int _uint16(Uint8List bytes, int offset) =>
    ByteData.sublistView(bytes, offset, offset + 2).getUint16(0, Endian.big);

int _uint32(Uint8List bytes, int offset) =>
    ByteData.sublistView(bytes, offset, offset + 4).getUint32(0, Endian.big);

Future<Uint8List> _readRange(RandomAccessFile raf, int start, int end) async {
  await raf.setPosition(start);
  return raf.read(end - start);
}

class _MobiRecordReader {
  _MobiRecordReader._(this._raf, this._offsets);

  final RandomAccessFile _raf;
  final List<List<int>> _offsets;

  static Future<_MobiRecordReader> open(File file) async {
    final raf = await file.open();
    final header = await _readRange(raf, 0, 78);
    final type = String.fromCharCodes(header.sublist(60, 64));
    final creator = String.fromCharCodes(header.sublist(64, 68));
    if (type != 'BOOK' || creator != 'MOBI') {
      await raf.close();
      throw const FormatException('不是有效的 MOBI/KF8 檔案：PDB type/creator 不符');
    }
    final numRecords = _uint16(header, 76);
    final infoList = await _readRange(raf, 78, 78 + numRecords * 8);
    final starts = [for (var i = 0; i < numRecords; i++) _uint32(infoList, i * 8)];
    final fileLength = await raf.length();
    final offsets = [
      for (var i = 0; i < starts.length; i++)
        [starts[i], i + 1 < starts.length ? starts[i + 1] : fileLength],
    ];
    return _MobiRecordReader._(raf, offsets);
  }

  Future<Uint8List> readRecord(int index) async {
    if (index < 0 || index >= _offsets.length) {
      throw RangeError('record index $index 超出範圍（共 ${_offsets.length} 筆）');
    }
    final range = _offsets[index];
    return _readRange(_raf, range[0], range[1]);
  }

  Future<void> close() => _raf.close();
}

/// CP1252（Windows-1252）0x80-0x9F 這 32 個位元組對應的 Unicode 碼點，與
/// ISO-8859-1（`dart:convert` 的 `latin1`）在此區段的定義不同（其餘
/// 0x00-0x7F／0xA0-0xFF 兩者相同）。舊版 MOBI（`encoding == 1252`）用此
/// 表解碼；未定義的位元組（Windows-1252 保留未使用）直接保留原碼位。
const _cp1252HighBytes = <int, int>{
  0x80: 0x20AC, 0x82: 0x201A, 0x83: 0x0192, 0x84: 0x201E, 0x85: 0x2026,
  0x86: 0x2020, 0x87: 0x2021, 0x88: 0x02C6, 0x89: 0x2030, 0x8A: 0x0160,
  0x8B: 0x2039, 0x8C: 0x0152, 0x8E: 0x017D, 0x91: 0x2018, 0x92: 0x2019,
  0x93: 0x201C, 0x94: 0x201D, 0x95: 0x2022, 0x96: 0x2013, 0x97: 0x2014,
  0x98: 0x02DC, 0x99: 0x2122, 0x9A: 0x0161, 0x9B: 0x203A, 0x9C: 0x0153,
  0x9E: 0x017E, 0x9F: 0x0178,
};

String _decodeText(Uint8List bytes, int encoding) {
  if (encoding == 65001) return utf8.decode(bytes, allowMalformed: true);
  return String.fromCharCodes(bytes.map((b) => _cp1252HighBytes[b] ?? b));
}

class _MobiHeaders {
  const _MobiHeaders({
    required this.mobiLength,
    required this.exthFlag,
    required this.titleOffset,
    required this.titleLength,
    required this.encoding,
    required this.resourceStart,
  });

  final int mobiLength;
  final int exthFlag;
  final int titleOffset;
  final int titleLength;
  final int encoding;
  final int resourceStart;
}

_MobiHeaders _parseMobiHeaders(Uint8List record0) {
  final magic = String.fromCharCodes(record0.sublist(16, 20));
  if (magic != 'MOBI') {
    throw const FormatException('不是有效的 MOBI/KF8 檔案：缺少 MOBI 標頭');
  }
  return _MobiHeaders(
    mobiLength: _uint32(record0, 20),
    exthFlag: _uint32(record0, 128),
    titleOffset: _uint32(record0, 84),
    titleLength: _uint32(record0, 88),
    encoding: _uint32(record0, 28),
    resourceStart: _uint32(record0, 108),
  );
}

/// 只解析本模組需要的 5 個 EXTH tag：100=creator（作者）、122=fixedLayout、
/// 201=coverOffset、202=thumbnailOffset、503=title——其餘 tag 略過。
Map<int, List<Object>> _parseExth(Uint8List record0, int exthOffset, int encoding) {
  if (exthOffset + 12 > record0.length) return {};
  final magic = String.fromCharCodes(record0.sublist(exthOffset, exthOffset + 4));
  if (magic != 'EXTH') return {};
  final count = _uint32(record0, exthOffset + 8);
  final results = <int, List<Object>>{};
  var offset = exthOffset + 12;
  for (var i = 0; i < count; i++) {
    final type = _uint32(record0, offset);
    final length = _uint32(record0, offset + 4);
    final data = record0.sublist(offset + 8, offset + length);
    if (type == 100 || type == 122 || type == 503) {
      results.putIfAbsent(type, () => []).add(_decodeText(data, encoding));
    } else if (type == 201 || type == 202) {
      results.putIfAbsent(type, () => []).add(_uint32(data, 0));
    }
    offset += length;
  }
  return results;
}

String? _firstString(List<Object>? values) =>
    (values == null || values.isEmpty) ? null : values.first as String;

int? _firstInt(List<Object>? values) =>
    (values == null || values.isEmpty) ? null : values.first as int;

/// 讀取 KF8 (AZW3) 檔案的 metadata（`title`／`author`／`isFixedLayout`／
/// `coverBytes`，鍵名與既有 native `extractMetadata` channel 回傳格式一致，
/// 供 `book_import_service_impl.dart` 以相同方式消費）。[filePath] 可為本機
/// 路徑或 `content://` URI——後者先透過既有、格式無關的 `copyContentUriToFile`
/// 原生方法複製到暫存檔（`dart:io` 無法對 `content://` URI 做隨機存取讀取，
/// 讀封面資源需要 range read，比照 ADR 0002 既有限制），完成後清除暫存檔。
///
/// `PALMDOC_HEADER.encryption`（record 0 內 offset 12，2 bytes 大端序）非 0
/// 時拋出 [DrmProtectedException]，不繼續解析（`mobi.js` 本身不會因此欄位
/// 拒絕開啟，偵測必須獨立於 `mobi.js` 之外，見 Issue 1 Spike 查證）。
Future<Map<String, Object?>> extractKf8Metadata(String filePath) async {
  if (filePath.contains('://')) {
    // Note: kBookMetadataChannel is not available in this context.
    // For content:// URIs, the caller should handle copying to local storage.
    // This is a simplified implementation that only supports local files.
    throw UnimplementedError('content:// URI 尚未在此模組實作，請先複製到本機路徑');
  }
  return _extractFromLocalFile(filePath);
}

Future<Map<String, Object?>> _extractFromLocalFile(String filePath) async {
  final reader = await _MobiRecordReader.open(File(filePath));
  try {
    final record0 = await reader.readRecord(0);
    final encryption = _uint16(record0, 12);
    if (encryption != 0) {
      throw const DrmProtectedException('此檔案受 DRM 保護，暫不支援');
    }

    final headers = _parseMobiHeaders(record0);
    final exthOffset = headers.mobiLength + 16;
    final exth = (headers.exthFlag & 0x40) != 0
        ? _parseExth(record0, exthOffset, headers.encoding)
        : <int, List<Object>>{};

    final title = _firstString(exth[503]) ??
        _decodeText(
          record0.sublist(
            headers.titleOffset,
            headers.titleOffset + headers.titleLength,
          ),
          headers.encoding,
        );

    Uint8List? coverBytes;
    final coverOffset = _firstInt(exth[201]) ?? _firstInt(exth[202]);
    if (coverOffset != null) {
      coverBytes = await reader.readRecord(headers.resourceStart + coverOffset);
    }

    return {
      'title': title,
      'author': _firstString(exth[100]),
      'isFixedLayout': _firstString(exth[122]) == 'true',
      'coverBytes': coverBytes,
    };
  } finally {
    await reader.close();
  }
}
