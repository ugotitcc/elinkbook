import '../library/book_file_format.dart';
import '../library/models/library_enums.dart';
import 'foliate_reader_surface.dart';
import 'pdf_reader_surface.dart';
import 'reader_surface.dart';

/// 依書籍格式建立「閱讀面」（見 CONTEXT.md「閱讀面」）的工廠。
///
/// 經 `ReaderFeatureDependencies.readerSurfaceFactory` 注入 `ReaderScreen`：
/// 正式環境用 [defaultReaderSurfaceFactory]，測試可換成 `FakeReaderSurface`。
typedef ReaderSurfaceFactory = ReaderSurface Function(BookFileFormat? format);

/// 正式工廠：PDF → [PdfReaderSurface]；Foliate 各格式（EPUB／KF8／CBZ／TXT／MD）
/// → [FoliateReaderSurface]；`null`（不支援）→ [NoopReaderSurface]。
/// 每次呼叫建立新的 surface（一本書一個，各自擁有自己的 `GlobalKey`）。
ReaderSurface defaultReaderSurfaceFactory(BookFileFormat? format) {
  if (format.isPdf) return PdfReaderSurface();
  if (format.usesFoliate) return FoliateReaderSurface();
  return const NoopReaderSurface();
}
