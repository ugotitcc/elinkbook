import 'dart:io';
import 'dart:typed_data';

int _uint16(Uint8List bytes, int offset) =>
    ByteData.sublistView(bytes, offset, offset + 2).getUint16(0, Endian.big);

int _uint32(Uint8List bytes, int offset) =>
    ByteData.sublistView(bytes, offset, offset + 4).getUint32(0, Endian.big);

Future<Uint8List> _readRange(RandomAccessFile raf, int start, int end) async {
  await raf.setPosition(start);
  return raf.read(end - start);
}

/// 對 PDB（Palm Database）容器格式的最小隨機存取讀取器，比照
/// `readest/foliate-js`（釘定 commit dd71f2be356563c16a23272686189fcfb45d0b82）
/// `mobi.js` 的 `class PDB` 邏輯：讀取 78 bytes 標頭取得 record 數量，讀取
/// record info list 取得每筆 record 的起訖 offset，供之後隨機讀取任一 record
/// （metadata 標頭在 record 0，封面圖片在 `resourceStart + coverOffset`）。
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

/// 讀取 KF8 (AZW3) 檔案的 metadata。目前為最小實作，Task 5 會擴充回傳欄位。
Future<Map<String, Object?>> extractKf8Metadata(String filePath) async {
  final reader = await _MobiRecordReader.open(File(filePath));
  try {
    await reader.readRecord(0);
    return const {};
  } finally {
    await reader.close();
  }
}
