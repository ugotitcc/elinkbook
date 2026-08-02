import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/font_name_parser.dart';

/// 手刻最小合成 sfnt 位元組陣列，僅含一張 `name` table（其餘 sfnt table
/// 皆省略——解析器只讀取 table directory 定位 `name` table，不理會其他
/// table 內容，省略對解析結果無影響）。
Uint8List _buildSfntWithNameTable(List<_NameRecord> records) {
  final strings = <List<int>>[];
  final recordBytes = BytesBuilder();
  var stringOffset = 0;
  for (final r in records) {
    final bytes = r.bytes;
    recordBytes.add(_u16(r.platformId));
    recordBytes.add(_u16(r.encodingId));
    recordBytes.add(_u16(r.languageId));
    recordBytes.add(_u16(r.nameId));
    recordBytes.add(_u16(bytes.length));
    recordBytes.add(_u16(stringOffset));
    strings.add(bytes);
    stringOffset += bytes.length;
  }

  final nameTable = BytesBuilder();
  nameTable.add(_u16(0)); // format
  nameTable.add(_u16(records.length)); // count
  nameTable.add(_u16(6 + records.length * 12)); // stringOffset
  nameTable.add(recordBytes.toBytes());
  for (final s in strings) {
    nameTable.add(s);
  }
  final nameTableBytes = nameTable.toBytes();

  const sfntHeaderLen = 12;
  const tableRecordLen = 16;
  final nameTableStart = sfntHeaderLen + tableRecordLen;

  final result = BytesBuilder();
  result.add(_u32(0x00010000)); // sfnt version
  result.add(_u16(1)); // numTables
  result.add(_u16(0)); // searchRange（解析器不使用，任意值）
  result.add(_u16(0)); // entrySelector
  result.add(_u16(0)); // rangeShift
  result.add('name'.codeUnits); // tag
  result.add(_u32(0)); // checksum（解析器不驗證，任意值）
  result.add(_u32(nameTableStart)); // offset
  result.add(_u32(nameTableBytes.length)); // length
  result.add(nameTableBytes);
  return result.toBytes();
}

class _NameRecord {
  final int platformId;
  final int encodingId;
  final int languageId;
  final int nameId;
  final List<int> bytes;
  _NameRecord(this.platformId, this.encodingId, this.languageId, this.nameId,
      this.bytes);
}

List<int> _u16(int value) => [(value >> 8) & 0xff, value & 0xff];
List<int> _u32(int value) => [
      (value >> 24) & 0xff,
      (value >> 16) & 0xff,
      (value >> 8) & 0xff,
      value & 0xff,
    ];

List<int> _utf16be(String s) {
  final bytes = <int>[];
  for (final code in s.codeUnits) {
    bytes.add((code >> 8) & 0xff);
    bytes.add(code & 0xff);
  }
  return bytes;
}

void main() {
  test('真實字型檔案（app/test/fixtures/sample.ttf，KingHwa_OldSong）正確解析出 family name',
      () async {
    final bytes = await File('test/fixtures/sample.ttf').readAsBytes();

    expect(parseFontFamilyName(bytes), 'KingHwa_OldSong');
  });

  test('Platform 3（Windows）Unicode nameID=1 記錄優先於 Platform 1（Mac）記錄',
      () {
    final bytes = _buildSfntWithNameTable([
      _NameRecord(1, 0, 0, 1, 'MacName'.codeUnits),
      _NameRecord(3, 1, 0x0409, 1, _utf16be('WindowsName')),
    ]);

    expect(parseFontFamilyName(bytes), 'WindowsName');
  });

  test('僅有 Platform 1（Mac）nameID=1 記錄時，回退使用該記錄', () {
    final bytes = _buildSfntWithNameTable([
      _NameRecord(1, 0, 0, 1, 'MacOnlyName'.codeUnits),
    ]);

    expect(parseFontFamilyName(bytes), 'MacOnlyName');
  });

  test('無 nameID=1 記錄時，回退使用 nameID=4（Full Name）', () {
    final bytes = _buildSfntWithNameTable([
      _NameRecord(3, 1, 0x0409, 4, _utf16be('FullNameOnly')),
    ]);

    expect(parseFontFamilyName(bytes), 'FullNameOnly');
  });

  test('無 nameID=1/4，回退使用 nameID=6（PostScript Name）', () {
    final bytes = _buildSfntWithNameTable([
      _NameRecord(3, 1, 0x0409, 6, _utf16be('PostScriptNameOnly')),
    ]);

    expect(parseFontFamilyName(bytes), 'PostScriptNameOnly');
  });

  test('name table 完全沒有可用記錄（例如僅有 nameID=2 子家族名稱）時回傳 null',
      () {
    final bytes = _buildSfntWithNameTable([
      _NameRecord(3, 1, 0x0409, 2, _utf16be('Regular')),
    ]);

    expect(parseFontFamilyName(bytes), isNull);
  });

  test('sfnt table directory 找不到 name table 時回傳 null', () {
    final result = BytesBuilder();
    result.add(_u32(0x00010000));
    result.add(_u16(1)); // numTables
    result.add(_u16(0));
    result.add(_u16(0));
    result.add(_u16(0));
    result.add('cmap'.codeUnits); // 只有 cmap，沒有 name
    result.add(_u32(0));
    result.add(_u32(28));
    result.add(_u32(4));
    result.add([0, 0, 0, 0]);

    expect(parseFontFamilyName(result.toBytes()), isNull);
  });

  test('二進位結構損壞（過短、不足以構成合法 sfnt 標頭）時回傳 null，不拋出例外',
      () {
    expect(parseFontFamilyName(Uint8List.fromList([1, 2, 3])), isNull);
    expect(parseFontFamilyName(Uint8List(0)), isNull);
  });
}
