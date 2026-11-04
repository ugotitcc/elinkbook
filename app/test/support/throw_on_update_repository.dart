import 'package:elinkbook/library/models/book.dart';
import 'fake_library_repository.dart';

/// 供測試模擬 `updateBook` 拋出例外，並記錄 `updateBook` 呼叫次數與參數。
class ThrowOnUpdateRepository extends FakeLibraryRepository {
  ThrowOnUpdateRepository({
    super.initialBooks,
    this.throwOnUpdate = false,
  });

  bool throwOnUpdate;
  final List<Book> updateBookCalls = [];

  @override
  Future<void> updateBook(Book book) async {
    updateBookCalls.add(book);
    if (throwOnUpdate) {
      throw Exception('Simulated updateBook failure in ThrowOnUpdateRepository');
    }
    return super.updateBook(book);
  }
}
