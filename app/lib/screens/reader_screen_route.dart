// app/lib/screens/reader_screen_route.dart
import '../library/models/book.dart';
import '../reader/reader_jump_target.dart';
import 'reader_feature_dependencies.dart';
import 'reader_screen.dart';

/// 三處開書路徑（書架、全庫搜尋、單書搜尋）共用的 `ReaderScreen` 組裝點
/// （epic-41 Issue 1）。書本欄位由 [book] 帶入，其餘依賴整組由 [dependencies]
/// 帶入。回傳具體型別 [ReaderScreen]，讓呼叫端與測試不轉型直接存取欄位。
ReaderScreen buildReaderScreen({
  required Book book,
  required ReaderFeatureDependencies dependencies,
  required bool isEinkMode,
  ReaderJumpTarget? initialJumpTarget,
}) {
  return ReaderScreen(
    filePath: book.filePath,
    bookId: book.id,
    dependencies: dependencies,
    bookTitle: book.title,
    bookAuthor: book.author,
    bookProgress: book.progress,
    isFixedLayout: book.isFixedLayout,
    isEinkMode: isEinkMode,
    initialJumpTarget: initialJumpTarget,
  );
}
