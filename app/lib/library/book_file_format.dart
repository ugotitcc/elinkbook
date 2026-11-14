import 'models/library_enums.dart';

/// 書籍格式能力（Book Format Capabilities，見 `CONTEXT.md`）。
///
/// 回答「這個檔案是什麼格式」以及「這個格式有什麼靜態事實」，取代過去散在
/// 副檔名表、MIME 表、選檔器清單、`BookFormat`／`BookFileFormat` 兩個平行
/// enum 與 `reader_screen.dart` 內大量 enum 比對的重複知識。呼叫端詢問能力，
/// 不比對 enum 成員；新增格式時，下方各個窮舉 `switch` 會讓編譯器逼你補齊。
///
/// 不含任何執行期判斷（例如「這本 EPUB 是不是固定版面」屬「引擎分派判斷」）。
/// `BookFileFormat` 會經 `values.byName` 寫進資料庫與同步，成員名稱不可改；
/// 「不支援／尚未偵測」不屬於它，以 `null` 表示。

/// 渲染引擎種類。
enum BookEngine { pdf, foliate }

/// 定位座標型別：Foliate 格式用 CFI，PDF 用頁碼（加頁內座標）。
enum LocatorKind { cfi, pdfPage }

extension BookFileFormatCapabilities on BookFileFormat {
  BookEngine get engine {
    switch (this) {
      case BookFileFormat.pdf:
        return BookEngine.pdf;
      case BookFileFormat.epub:
      case BookFileFormat.azw3:
      case BookFileFormat.cbz:
      case BookFileFormat.txt:
      case BookFileFormat.md:
        return BookEngine.foliate;
    }
  }

  LocatorKind get locatorKind {
    switch (this) {
      case BookFileFormat.pdf:
        return LocatorKind.pdfPage;
      case BookFileFormat.epub:
      case BookFileFormat.azw3:
      case BookFileFormat.cbz:
      case BookFileFormat.txt:
      case BookFileFormat.md:
        return LocatorKind.cfi;
    }
  }

  /// 使用者的原始檔本身就是閱讀用檔案：`Book.filePath` 可維持 `content://`
  /// 或原路徑，可重新連結（relink），並存時可落地私有複本。
  ///
  /// TXT／MD 匯入時已合成 EPUB、CBZ 已重建並落地，`filePath` 指向落地檔；
  /// 若換成原始檔，閱讀器會把原始檔當合成結果開啟，整本書壞掉。
  bool get keepsOriginalSource {
    switch (this) {
      case BookFileFormat.epub:
      case BookFileFormat.pdf:
      case BookFileFormat.azw3:
        return true;
      case BookFileFormat.txt:
      case BookFileFormat.md:
      case BookFileFormat.cbz:
        return false;
    }
  }

  /// 匯入時是否合成為最小合法 EPUB3 結構（見 ADR 0023）。
  bool get synthesizesEpub {
    switch (this) {
      case BookFileFormat.txt:
      case BookFileFormat.md:
        return true;
      case BookFileFormat.epub:
      case BookFileFormat.pdf:
      case BookFileFormat.azw3:
      case BookFileFormat.cbz:
        return false;
    }
  }

  /// 副檔名（不含句點，小寫）。
  String get fileExtension {
    switch (this) {
      case BookFileFormat.epub:
        return 'epub';
      case BookFileFormat.pdf:
        return 'pdf';
      case BookFileFormat.txt:
        return 'txt';
      case BookFileFormat.azw3:
        return 'azw3';
      case BookFileFormat.cbz:
        return 'cbz';
      case BookFileFormat.md:
        return 'md';
    }
  }

  /// 此格式在雲端／OPDS 常見的 MIME type。
  List<String> get _mimeTypes {
    switch (this) {
      case BookFileFormat.epub:
        return const ['application/epub+zip'];
      case BookFileFormat.pdf:
        return const ['application/pdf'];
      case BookFileFormat.txt:
        return const ['text/plain'];
      case BookFileFormat.azw3:
        return const [
          'application/x-mobipocket-ebook',
          'application/vnd.amazon.ebook',
        ];
      case BookFileFormat.cbz:
        return const ['application/vnd.comicbook+zip', 'application/x-cbz'];
      case BookFileFormat.md:
        return const ['text/markdown'];
    }
  }
}

/// 「不支援／尚未偵測」以 `null` 表示，兩個查詢對 `null` 一律為 false。
extension BookFileFormatNullable on BookFileFormat? {
  /// 是否經由 `FoliateReaderView`（`foliate-js`）渲染。
  bool get usesFoliate {
    final f = this;
    return f != null && f.engine == BookEngine.foliate;
  }

  bool get isPdf => this == BookFileFormat.pdf;
}

/// 全部支援格式的副檔名（不含句點），供選檔器過濾、暫存檔掃除、Drive 查詢
/// 等共用。順序固定為歷來選檔器清單的順序。
final List<String> kSupportedBookExtensions = List.unmodifiable(const [
  BookFileFormat.epub,
  BookFileFormat.pdf,
  BookFileFormat.txt,
  BookFileFormat.cbz,
  BookFileFormat.azw3,
  BookFileFormat.md,
].map((f) => f.fileExtension));

/// 依 URI／路徑字串最後一段（已對 percent-encoding 解碼）的副檔名判斷格式，
/// 不分大小寫。認不出（含無副檔名、空字串）回傳 `null`，絕不拋例外。
///
/// 只依副檔名判斷：適用本機檔案與有可辨識檔名的 URI；不適用於雲端服務自訂的
/// 不透明文件 ID。
BookFileFormat? detectBookFileFormat(String uriOrPath) {
  final name = lastPathComponentOfUri(uriOrPath).toLowerCase();
  for (final format in BookFileFormat.values) {
    if (name.endsWith('.${format.fileExtension}')) return format;
  }
  return null;
}

/// 依檔案 URI 與顯示名稱判定書籍格式：displayName 優先，無法辨識時退回 URI
/// （content:// 的 URI 常是不透明 ID，真正的檔名只在 displayName）。
BookFileFormat? detectImportFileFormat(String uri, String? displayName) =>
    (displayName != null && displayName.isNotEmpty
        ? detectBookFileFormat(displayName)
        : null) ??
    detectBookFileFormat(uri);

/// 雲端硬碟與 OPDS 用：**副檔名優先**，副檔名認不出才看 [mimeType]。
///
/// 副檔名優先是為了避免 `notes.md`（MIME 為 `text/plain`）被誤判為 txt，
/// 以及 Drive 上 MIME 為 `application/octet-stream` 的 `.txt` 被漏掉。
/// 兩者皆認不出回傳 `null`。
BookFileFormat? detectBookFileFormatByNameAndMime(
  String name,
  String? mimeType,
) {
  final fromName = detectBookFileFormat(name);
  if (fromName != null) return fromName;
  if (mimeType == null) return null;
  for (final format in BookFileFormat.values) {
    if (format._mimeTypes.contains(mimeType)) return format;
  }
  return null;
}

/// 取 URI／路徑字串最後一段檔名（已 percent-decode）。
String lastPathComponentOfUri(String uriOrPath) {
  // displayName 可能是未經 percent-encoding 的原始檔名（例如 file_picker 的
  // PlatformFile.name），Uri.decodeFull 對這類不含合法 percent-encoding 序列
  // 的字串會拋出例外；此時視為不需解碼，直接使用原字串。
  String decoded;
  try {
    decoded = Uri.decodeFull(uriOrPath);
  } on ArgumentError {
    decoded = uriOrPath;
  }
  final normalized = decoded.replaceAll('\\', '/');
  final segments = normalized.split('/');
  return segments.isNotEmpty ? segments.last : normalized;
}
