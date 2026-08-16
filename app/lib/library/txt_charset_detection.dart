// app/lib/library/txt_charset_detection.dart
import 'dart:convert';
import 'dart:typed_data';

import 'txt_charset_tables.dart';

/// TXT 檔案偵測到的編碼種類，供匯入流程記錄／除錯使用（本 Issue 範圍
/// 不對外暴露此資訊給使用者 UI，`spec.md`「TXT 編碼偵測」未要求）。
/// `fallback` 代表全部優先層皆判定失敗，強制以寬鬆 UTF-8 解碼（見
/// [detectAndDecodeTxt] 文件註解）。`big5` 同時涵蓋 spec.md 優先序中的
/// `big5-hkscs`（見 Global Constraints 已查證事實 #5，兩者共用同一份表，
/// 不需要獨立的列舉值）。
enum TxtEncoding { utf8, big5, gbk, utf16, fallback }

class TxtDecodeResult {
  final String text;
  final TxtEncoding encoding;
  const TxtDecodeResult({required this.text, required this.encoding});
}

class _CharsetTable {
  final Uint16List keys;
  final Uint16List values;
  const _CharsetTable(this.keys, this.values);

  /// 二分搜尋 [keys]（已排序、無重複，見產生腳本的斷言），找不到回傳 -1。
  int indexOf(int key) {
    var lo = 0;
    var hi = keys.length - 1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      final k = keys[mid];
      if (k == key) return mid;
      if (k < key) {
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return -1;
  }
}

Uint16List _unpackUint16(String base64Str) {
  final bytes = base64Decode(base64Str);
  final data = ByteData.sublistView(bytes);
  final result = Uint16List(bytes.length ~/ 2);
  for (var i = 0; i < result.length; i++) {
    result[i] = data.getUint16(i * 2, Endian.little);
  }
  return result;
}

final _big5Table = _CharsetTable(
  _unpackUint16(kBig5TableKeysBase64),
  _unpackUint16(kBig5TableValuesBase64),
);
final _gbkTable = _CharsetTable(
  _unpackUint16(kGbkTableKeysBase64),
  _unpackUint16(kGbkTableValuesBase64),
);

/// 嘗試以 [table] 完整解碼 [bytes]；只要有任一位元組序列無法對映即回傳
/// `null`（代表這組位元組很可能不是這個編碼），呼叫端據此往下一個優先層
/// 退回，不強行猜測。單位元組（<0x80）視為 ASCII 直接透傳。
String? _decodeDbcsStrict(Uint8List bytes, _CharsetTable table) {
  final buffer = StringBuffer();
  var i = 0;
  while (i < bytes.length) {
    final b = bytes[i];
    if (b < 0x80) {
      buffer.writeCharCode(b);
      i += 1;
      continue;
    }
    if (i + 1 >= bytes.length) return null; // 截斷的雙位元組序列
    final key = (b << 8) | bytes[i + 1];
    final idx = table.indexOf(key);
    if (idx == -1) return null;
    buffer.writeCharCode(table.values[idx]);
    i += 2;
  }
  return buffer.toString();
}

/// BOM 開頭時解碼為 UTF-16（大小端依 BOM 判斷）；無 BOM 時回傳 `null`——
/// UTF-16 是優先序最低的最終退路，本函式刻意不猜測無 BOM 情境下的位元組序
/// （見 [detectAndDecodeTxt] 呼叫處說明）。
String? _decodeUtf16WithBom(Uint8List bytes) {
  if (bytes.length < 2) return null;
  final Endian endian;
  const offset = 2;
  if (bytes[0] == 0xFE && bytes[1] == 0xFF) {
    endian = Endian.big;
  } else if (bytes[0] == 0xFF && bytes[1] == 0xFE) {
    endian = Endian.little;
  } else {
    return null;
  }
  final remaining = bytes.length - offset;
  if (remaining.isOdd) return null; // 位元組數不成對，格式不正確
  final data = ByteData.sublistView(bytes, offset);
  final codeUnits = Uint16List(remaining ~/ 2);
  for (var i = 0; i < codeUnits.length; i++) {
    codeUnits[i] = data.getUint16(i * 2, endian);
  }
  return String.fromCharCodes(codeUnits);
}

/// UTF-8 BOM（`EF BB BF`）剝除，其餘位元組原樣保留供後續嘗試 UTF-8 解碼。
Uint8List _stripUtf8Bom(Uint8List bytes) {
  if (bytes.length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF) {
    return bytes.sublist(3);
  }
  return bytes;
}

/// 依 spec.md「TXT 編碼偵測」優先序 `[utf8, big5, big5-hkscs, gbk, utf16]`
/// 嘗試解碼；`big5-hkscs` 與 `big5` 共用同一份對照表（見 Global Constraints
/// 已查證事實 #5），故實際只有 4 個相異分支：utf8 → big5(+hkscs) → gbk →
/// utf16(BOM)。UTF-16 BOM 是比其餘啟發式嘗試解碼更明確的訊號，故優先於
/// utf8/big5/gbk 判斷；其餘依序嘗試，任何一層完整解碼成功（無無法對映的
/// 位元組序列）即採用。全數失敗時強制以 UTF-8 寬鬆解碼（`allowMalformed:
/// true`，絕不拋出例外——比照 spec.md「自動偵測失敗時的退回行為（例如以
/// UTF-8 強制解讀並提示使用者）」，本 Issue 範圍僅實作解碼本身，UI 提示
/// 留待未來視需要評估，不在 issues.md Issue 4 明列範圍內）。
TxtDecodeResult detectAndDecodeTxt(Uint8List bytes) {
  final utf16Result = _decodeUtf16WithBom(bytes);
  if (utf16Result != null) {
    return TxtDecodeResult(text: utf16Result, encoding: TxtEncoding.utf16);
  }

  final withoutBom = _stripUtf8Bom(bytes);
  try {
    final decoded = utf8.decode(withoutBom);
    return TxtDecodeResult(text: decoded, encoding: TxtEncoding.utf8);
  } on FormatException {
    // 非合法 UTF-8，繼續嘗試其餘編碼。
  }

  final big5Result = _decodeDbcsStrict(bytes, _big5Table);
  if (big5Result != null) {
    return TxtDecodeResult(text: big5Result, encoding: TxtEncoding.big5);
  }

  final gbkResult = _decodeDbcsStrict(bytes, _gbkTable);
  if (gbkResult != null) {
    return TxtDecodeResult(text: gbkResult, encoding: TxtEncoding.gbk);
  }

  return TxtDecodeResult(
    text: utf8.decode(bytes, allowMalformed: true),
    encoding: TxtEncoding.fallback,
  );
}
