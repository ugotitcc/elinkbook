import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/cloud_import/cloud_storage_client.dart';
import 'package:elinkbook/library/models/library_enums.dart';

void main() {
  test('依標準 MIME type 判斷 EPUB/PDF/TXT', () {
    expect(detectCloudFileFormat('book', 'application/epub+zip'), BookFileFormat.epub);
    expect(detectCloudFileFormat('book', 'application/pdf'), BookFileFormat.pdf);
    expect(detectCloudFileFormat('book', 'text/plain'), BookFileFormat.txt);
  });

  test('無標準 MIME type 時退回副檔名判斷 AZW3/CBZ/MD', () {
    expect(detectCloudFileFormat('book.azw3', 'application/octet-stream'), BookFileFormat.azw3);
    expect(detectCloudFileFormat('book.cbz', 'application/octet-stream'), BookFileFormat.cbz);
    expect(detectCloudFileFormat('notes.md', 'application/octet-stream'), BookFileFormat.md);
  });

  test('MIME type 為 null 時同樣退回副檔名判斷', () {
    expect(detectCloudFileFormat('book.epub', null), BookFileFormat.epub);
  });

  test('副檔名子字串誤判（例如 .mdx）不會被判定為支援格式', () {
    expect(detectCloudFileFormat('notes.mdx', 'application/octet-stream'), isNull);
  });

  test('完全不支援的格式回傳 null', () {
    expect(detectCloudFileFormat('photo.jpg', 'image/jpeg'), isNull);
  });
}
