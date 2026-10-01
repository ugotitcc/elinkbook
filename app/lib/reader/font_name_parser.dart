import 'dart:convert';
import 'dart:typed_data';

/// 手刻最小化 TTF/OTF `name` table 二進位解析器，取得字型的實際 family
/// name（epic-14-system-settings FR-35，見
/// docs/epics/epic-14-system-settings/design.md 決策 1／spec.md「字型管理
/// 模組」）。不引入第三方套件——只需要解析 `name` table 這一個子集合，
/// 比照本專案「foliate-js 釘定複製、TXT 引擎自訂輕量解析」的既有慣例
/// （不為小範圍、格式明確的問題引入完整字型渲染函式庫依賴）。
///
/// 解碼優先順序：Platform 3（Windows）Unicode BMP（encodingID
/// 1／10）、nameID=1（Font Family）→ Platform 1（Macintosh），nameID=1 →
/// nameID=4（Full Name）→ nameID=6（PostScript Name）。找不到任何可用記錄，
/// 或二進位結構不足以構成合法 sfnt 標頭／name table 時回傳 `null`（呼叫端
/// 負責退回檔名邏輯，不在此函式範圍內）。
String? parseFontFamilyName(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);

  int? nameTableOffset;
  int? nameTableLength;
  try {
    if (bytes.length < 12) return null;
    final numTables = data.getUint16(4);
    const headerLen = 12;
    const recordLen = 16;
    if (bytes.length < headerLen + numTables * recordLen) return null;
    for (var i = 0; i < numTables; i++) {
      final recordOffset = headerLen + i * recordLen;
      final tag = ascii.decode(
          bytes.sublist(recordOffset, recordOffset + 4),
          allowInvalid: true);
      if (tag == 'name') {
        nameTableOffset = data.getUint32(recordOffset + 8);
        nameTableLength = data.getUint32(recordOffset + 12);
        break;
      }
    }
  } catch (_) {
    return null;
  }
  if (nameTableOffset == null) return null;

  try {
    if (nameTableOffset + 6 > bytes.length) return null;
    final count = data.getUint16(nameTableOffset + 2);
    final stringAreaOffset =
        nameTableOffset + data.getUint16(nameTableOffset + 4);
    if (nameTableLength != null &&
        nameTableOffset + nameTableLength > bytes.length) {
      return null;
    }

    String? macCandidate;
    String? fullNameCandidate;
    String? postScriptCandidate;

    for (var i = 0; i < count; i++) {
      final recordOffset = nameTableOffset + 6 + i * 12;
      if (recordOffset + 12 > bytes.length) break;
      final platformId = data.getUint16(recordOffset);
      final languageIdOrUnused = data.getUint16(recordOffset + 4);
      final nameId = data.getUint16(recordOffset + 6);
      final length = data.getUint16(recordOffset + 8);
      final offset = data.getUint16(recordOffset + 10);
      final strStart = stringAreaOffset + offset;
      if (strStart + length > bytes.length) continue;
      final raw = bytes.sublist(strStart, strStart + length);

      String decoded;
      if (platformId == 3) {
        decoded = _decodeUtf16Be(raw);
      } else if (platformId == 1) {
        decoded = ascii.decode(raw, allowInvalid: true);
      } else {
        continue;
      }
      if (decoded.isEmpty) continue;

      if (nameId == 1) {
        // Platform 3（Windows）優先於 Platform 1（Mac），找到 Windows
        // 記錄立刻回傳；Mac 記錄先暫存，全部記錄掃完都沒有 Windows
        // 記錄時才使用。
        if (platformId == 3) return decoded;
        macCandidate ??= decoded;
      } else if (nameId == 4) {
        fullNameCandidate ??= decoded;
      } else if (nameId == 6) {
        postScriptCandidate ??= decoded;
      }
      // ignore: unused_local_variable
      languageIdOrUnused;
    }

    return macCandidate ?? fullNameCandidate ?? postScriptCandidate;
  } catch (_) {
    return null;
  }
}

String _decodeUtf16Be(List<int> bytes) {
  final units = <int>[];
  for (var i = 0; i + 1 < bytes.length; i += 2) {
    units.add((bytes[i] << 8) | bytes[i + 1]);
  }
  return String.fromCharCodes(units);
}

/// 字型檔名去除副檔名。供 [resolveFontFamilyName] 退回依據，也供上傳時產生
/// 預設顯示名稱使用。沒有副檔名、或點在最開頭（例如 `.hidden`）時原樣回傳。
String stripFontFileExtension(String fileName) {
  final dotIndex = fileName.lastIndexOf('.');
  return dotIndex > 0 ? fileName.substring(0, dotIndex) : fileName;
}

/// 決定字型檔案的家族名稱：優先採用 [parseFontFamilyName] 解析出的實際家族
/// 名稱，解析失敗退回檔名去副檔名。批次上傳與重新連結**必須共用這一條規則**
/// ——否則同一個檔案在兩條路徑可能得出不同家族名稱，重新連結就會誤判不符。
String resolveFontFamilyName(Uint8List bytes, String fileName) =>
    parseFontFamilyName(bytes) ?? stripFontFileExtension(fileName);
