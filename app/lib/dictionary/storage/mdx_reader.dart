// MdxReader：dict_reader 的薄封裝（epic-63 Issue 6a）。
//
// 這一層的責任：
// 1. 把 dict_reader 的各種失敗（含它直接丟出的字串）統一成 [MdxException]。
// 2. 套用 MDict 的鍵正規化規則（KeyCaseSensitive、StripKey）。
// 3. 提供顯示名稱規則（Title 佔位字串 → Description 第一行 → 檔名）。
// 4. 在主 isolate 做整檔區塊檢查（不解壓記錄區塊）。
//
// 記憶體：字串正規化只在使用者查詢時對單一查詢字串做，不建額外索引；
// 鍵的常駐記憶體由 vendor 修補後的 dict_reader 以區塊為單位控管
// （見 app/third_party/dict_reader/PATCH.md）。
import 'dart:io';

import 'package:dict_reader/dict_reader.dart';
import 'package:path/path.dart' as p;

/// MDX 開啟或讀取失敗的種類。錯誤訊息由 UI 依此轉成三段式文案。
enum MdxErrorKind {
  /// 區塊壓縮型態不是 none／zlib（例如 LZO）。
  unsupportedCompression,

  /// 記錄區塊加密（`Encrypted` 含 bit 0），需要註冊碼，Phase 1 不支援。
  encryptedRecords,

  /// 檔案損壞、截斷或格式不符。
  corrupt,

  /// 檔案不存在或無法開啟。
  notFound,

  /// 其他未分類錯誤。
  other,
}

/// dict_reader 失敗的統一例外。
class MdxException implements Exception {
  const MdxException(this.kind, [this.detail]);

  final MdxErrorKind kind;

  /// 供除錯用的細節，不直接顯示給使用者。
  final String? detail;

  @override
  String toString() =>
      'MdxException(${kind.name})${detail == null ? '' : ': $detail'}';
}

/// 開啟後即可取得的標頭資訊。
class MdxMeta {
  const MdxMeta({
    required this.title,
    required this.description,
    required this.keyCaseSensitive,
    required this.stripKey,
    required this.encrypted,
    required this.entryCount,
  });

  /// 標頭 `Title` 原值（尚未套用佔位字串規則）。
  final String title;

  /// 標頭 `Description` 原值；空白視為 null。
  final String? description;

  /// `KeyCaseSensitive=No` 時為 false（預設 true）。
  final bool keyCaseSensitive;

  /// `StripKey=Yes` 時為 true。
  final bool stripKey;

  /// 標頭 `Encrypted` 數值：0 無加密、1 記錄區塊加密、2 關鍵字索引加密。
  final int encrypted;

  final int entryCount;
}

/// `dict_reader` 的薄封裝。
///
/// 同一時間只會持有一個檔案控制代碼；[close] 可重複呼叫。開啟失敗時
/// 不會保留半初始化的 reader，也不會佔住檔案。
class MdxReader {
  MdxReader._(this._reader, this._path, this.meta);

  final DictReader _reader;
  final String _path;

  final MdxMeta meta;

  bool _closed = false;

  /// 開啟 [path] 並讀取標頭與區塊索引（不含全部鍵）。
  ///
  /// 失敗一律轉成 [MdxException]。記錄區塊加密的檔案在開啟後立刻以
  /// [MdxErrorKind.encryptedRecords] 失敗，避免之後才在查詢時出錯。
  static Future<MdxReader> open(String path) async {
    if (!await File(path).exists()) {
      throw MdxException(MdxErrorKind.notFound, path);
    }

    final reader = DictReader(path);
    try {
      await reader.initDict();
      final meta = _metaFrom(reader);
      if (meta.encrypted & 1 != 0) {
        throw MdxException(
          MdxErrorKind.encryptedRecords,
          'Encrypted=${meta.encrypted}',
        );
      }
      return MdxReader._(reader, path, meta);
    } catch (error) {
      // 失敗路徑一定要釋放控制代碼，否則呼叫端重試好檔時會受影響。
      try {
        await reader.close();
      } catch (_) {
        // 清理失敗不覆蓋原始錯誤。
      }
      throw _mapError(error, path);
    }
  }

  static MdxMeta _metaFrom(DictReader reader) {
    final header = reader.header;
    final description = header['Description'];
    return MdxMeta(
      title: header['Title'] ?? '',
      description: description == null || description.trim().isEmpty
          ? null
          : description,
      // dict_reader 的預設是大小寫敏感；只有明確寫 No 才折疊。
      keyCaseSensitive:
          (header['KeyCaseSensitive'] ?? 'Yes').toLowerCase() != 'no',
      stripKey: (header['StripKey'] ?? 'No').toLowerCase() == 'yes',
      encrypted: _parseEncrypted(header['Encrypted']),
      entryCount: reader.numEntries,
    );
  }

  /// 解析標頭 `Encrypted`，規則與 dict_reader 一致：缺欄位或 `No` 為 0、
  /// `Yes` 為 1（舊格式的記錄區塊加密），其餘當整數解析，解析不出來視為 0。
  static int _parseEncrypted(String? raw) {
    if (raw == null || raw == 'No') return 0;
    if (raw == 'Yes') return 1;
    return int.tryParse(raw) ?? 0;
  }

  /// 把 dict_reader 的失敗統一成 [MdxException]。
  ///
  /// dict_reader 對不支援的壓縮型態是 `throw "Compression method not supported"`，
  /// 不是 Exception，所以必須攔 `String`。
  static MdxException _mapError(Object error, String path) {
    if (error is MdxException) return error;
    if (error is String) {
      if (error.toLowerCase().contains('compression')) {
        return MdxException(MdxErrorKind.unsupportedCompression, error);
      }
      return MdxException(MdxErrorKind.corrupt, error);
    }
    if (error is FileSystemException) {
      return MdxException(
        File(path).existsSync() ? MdxErrorKind.corrupt : MdxErrorKind.notFound,
        error.toString(),
      );
    }
    if (error is FormatException ||
        error is StateError ||
        error is RangeError ||
        error is UnsupportedError) {
      return MdxException(MdxErrorKind.corrupt, error.toString());
    }
    return MdxException(MdxErrorKind.other, '${error.runtimeType}: $error');
  }

  /// 依標頭規則決定字典顯示名稱。
  ///
  /// 1. `Title` 非空白且不是預設佔位字串 → 原樣回傳。
  /// 2. 否則用 `Description` 第一行（去 HTML 標籤）。
  /// 3. 再不行用 [fileName] 的檔名（不含副檔名）。
  String displayName(String fileName) {
    final title = meta.title.trim();
    if (title.isNotEmpty && !_isPlaceholderTitle(title)) return title;

    final descriptionLine = _firstLine(meta.description);
    if (descriptionLine != null) return descriptionLine;

    final base = p.basename(fileName);
    final extension = p.extension(base);
    return extension.isEmpty
        ? base
        : base.substring(0, base.length - extension.length);
  }

  static bool _isPlaceholderTitle(String title) =>
      title.trim().toLowerCase() == 'title (no html code allowed)';

  /// 取第一行非空白文字：先解 HTML 實體、把換行標籤視為換行，再移除標籤。
  static String? _firstLine(String? raw) {
    if (raw == null) return null;
    var text = _unescapeHtml(raw);
    text = text.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
    text = text.replaceAll(
      RegExp(r'</(?:p|div|h[1-6]|li|tr)>', caseSensitive: false),
      '\n',
    );
    text = text.replaceAll(RegExp(r'<[^>]*>'), '');
    for (final line in text.split('\n')) {
      final trimmed = line.replaceAll('\u00a0', ' ').trim();
      if (trimmed.isNotEmpty) return trimmed;
    }
    return null;
  }

  /// 只解常見的 HTML 實體；`&amp;` 最後解，避免二次解碼。
  static String _unescapeHtml(String text) {
    var out = text.replaceAllMapped(
      RegExp(r'&#x([0-9a-fA-F]+);'),
      (m) => String.fromCharCode(int.parse(m.group(1)!, radix: 16)),
    );
    out = out.replaceAllMapped(
      RegExp(r'&#(\d+);'),
      (m) => String.fromCharCode(int.parse(m.group(1)!)),
    );
    return out
        .replaceAll('&nbsp;', '\u00a0')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&#39;', "'")
        .replaceAll('&amp;', '&');
  }

  /// 查詢 [key]，回傳所有命中詞條的 HTML（已展開 StyleSheet 標記）。
  ///
  /// - 空字串與純空白回傳空清單，不丟例外。
  /// - `StripKey=Yes` 時查詢字串先去空白與標點（Unicode `P` 類別與全形空白）。
  /// - `KeyCaseSensitive=No` 時折疊大小寫。
  /// - 同一把鍵的多筆記錄全部回傳，不去重。
  Future<List<String>> lookupAll(String key) async {
    final normalized = _normalizeQuery(key);
    if (normalized.isEmpty) return const [];

    try {
      final matches = await _reader.locateAll(normalized);
      final bodies = <String>[];
      for (final match in matches) {
        bodies.add(await _reader.readOneMdx(match));
      }
      return bodies;
    } catch (error) {
      throw _mapError(error, _path);
    }
  }

  /// 抽樣前 [limit] 筆詞條的內容，供匯入時找 `<link href="...css">`。
  ///
  /// 只讀前幾筆，不掃整本字典；解壓失敗一樣轉成 [MdxException]。
  Future<List<String>> sampleEntryBodies({int limit = 200}) async {
    if (limit <= 0) return const [];
    try {
      final bodies = <String>[];
      await for (final record in _reader.readWithOffset()) {
        bodies.add(await _reader.readOneMdx(record));
        if (bodies.length >= limit) break;
      }
      return bodies;
    } catch (error) {
      throw _mapError(error, _path);
    }
  }

  /// 依標頭套用查詢字串的正規化；結果為空表示不需要查。
  String _normalizeQuery(String key) {
    var query = key.trim();
    if (meta.stripKey) {
      query = query.replaceAll(RegExp(r'[\s\p{P}\u3000]', unicode: true), '');
    }
    if (!meta.keyCaseSensitive) query = query.toLowerCase();
    return query;
  }

  /// 快速檢查整份檔案的記錄區塊（主 isolate，不解壓）。
  ///
  /// 逐塊讀取 4 位元組的壓縮型態並檢查區塊是否落在檔案內：
  /// - 0（none）與 2（zlib）視為可用。
  /// - 其他型態（含 1／LZO）→ [MdxErrorKind.unsupportedCompression]。
  /// - 區塊超出檔尾或長度不足 → [MdxErrorKind.corrupt]。
  ///
  /// [onProgress] 每檢查完一塊呼叫一次；最後一次 `done == total`。
  Future<void> validateBlocks({
    void Function(int done, int total)? onProgress,
  }) async {
    RandomAccessFile? file;
    try {
      file = await File(_path).open();
      final length = await file.length();
      final version =
          double.tryParse(_reader.header['GeneratedByEngineVersion'] ?? '') ??
          2.0;
      final numberWidth = version >= 2.0 ? 8 : 4;

      await file.setPosition(0);
      final headerSizeBytes = await file.read(4);
      if (headerSizeBytes.length < 4) {
        throw const MdxException(MdxErrorKind.corrupt, '缺少檔頭長度');
      }
      final headerSize = _readUintBE(headerSizeBytes, 4, 0);

      // 關鍵字區標頭依版本不同（比照 dict_reader 的 _readKeySectionHeader）：
      // - v2：5 個數字（區塊數、筆數、資訊解壓大小、資訊大小、鍵區塊大小）
      //   ＋ 4 位元組 checksum。
      // - v1：4 個數字（區塊數、筆數、資訊大小、鍵區塊大小），沒有 checksum。
      final isV2 = version >= 2.0;
      final keyOffset = headerSize + 8;
      final keyHeadLength = numberWidth * (isV2 ? 5 : 4) + (isV2 ? 4 : 0);
      await file.setPosition(keyOffset);
      final keyHead = await file.read(keyHeadLength);
      if (keyHead.length < keyHeadLength) {
        throw const MdxException(MdxErrorKind.corrupt, '關鍵字區標頭不完整');
      }
      final keyInfoSize = _readUintBE(
        keyHead,
        numberWidth,
        numberWidth * (isV2 ? 3 : 2),
      );
      final keyBlocksSize = _readUintBE(
        keyHead,
        numberWidth,
        numberWidth * (isV2 ? 4 : 3),
      );
      final recordOffset = keyOffset + keyHeadLength + keyInfoSize + keyBlocksSize;
      if (recordOffset < 0 || recordOffset + numberWidth * 4 > length) {
        throw const MdxException(MdxErrorKind.corrupt, '記錄區標頭超出檔尾');
      }

      await file.setPosition(recordOffset);
      final recordHead = await file.read(numberWidth * 4);
      if (recordHead.length < numberWidth * 4) {
        throw const MdxException(MdxErrorKind.corrupt, '記錄區標頭不完整');
      }
      final blockCount = _readUintBE(recordHead, numberWidth, 0);
      // 先和剩餘檔案長度比對再讀，避免亂數的 blockCount 觸發超大讀取。
      final infoBytes = blockCount * numberWidth * 2;
      if (blockCount < 0 ||
          infoBytes < 0 ||
          recordOffset + numberWidth * 4 + infoBytes > length) {
        throw const MdxException(MdxErrorKind.corrupt, '記錄區塊資訊超出檔尾');
      }
      final infoLength = await file.read(infoBytes);
      if (infoLength.length < infoBytes) {
        throw const MdxException(MdxErrorKind.corrupt, '記錄區塊資訊不完整');
      }

      var blockOffset =
          recordOffset + numberWidth * 4 + blockCount * numberWidth * 2;
      for (var i = 0; i < blockCount; i++) {
        final compressedSize = _readUintBE(
          infoLength,
          numberWidth,
          i * numberWidth * 2,
        );
        // 至少要有 4 位元組壓縮型態 + 4 位元組 Adler-32。
        if (compressedSize < 8 || blockOffset + compressedSize > length) {
          throw const MdxException(MdxErrorKind.corrupt, '記錄區塊超出檔尾');
        }
        await file.setPosition(blockOffset);
        final blockHeader = await file.read(4);
        if (blockHeader.length < 4) {
          throw const MdxException(MdxErrorKind.corrupt, '記錄區塊不完整');
        }
        final compression = blockHeader[0] & 0x0f;
        if (compression != 0 && compression != 2) {
          throw MdxException(
            MdxErrorKind.unsupportedCompression,
            '壓縮型態 $compression',
          );
        }
        blockOffset += compressedSize;
        onProgress?.call(i + 1, blockCount);
      }
    } on MdxException {
      rethrow;
    } catch (error) {
      throw _mapError(error, _path);
    } finally {
      await file?.close();
    }
  }

  static int _readUintBE(List<int> bytes, int width, int start) {
    var value = 0;
    for (var i = 0; i < width; i++) {
      value = (value << 8) | bytes[start + i];
    }
    return value;
  }

  /// 關閉檔案；可重複呼叫。
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _reader.close();
  }
}
