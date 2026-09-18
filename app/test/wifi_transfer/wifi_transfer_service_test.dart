import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/wifi_transfer/wifi_transfer_service.dart';

import '../support/fake_book_import_service.dart';
import '../support/fake_library_repository.dart';
import '../support/fake_fingerprint_computer.dart';

void main() {
  WifiTransferService buildService() {
    final fingerprintComputer = FakeFingerprintComputer();
    return WifiTransferService(
      libraryRepository: FakeLibraryRepository(),
      importService: FakeBookImportService(),
      computeFingerprint: fingerprintComputer.call,
      materializeContentUri: (uri) async => null,
      deleteFile: (path) async {},
    );
  }

  test('骨架方法尚未實作，呼叫時明確拋出 UnimplementedError（Issue 2/3 填入前的契約）',
      () async {
    final service = buildService();

    await expectLater(
      service.handleUploadedFile(
        landedPath: '/tmp/a.epub',
        originalFileName: 'a.epub',
        format: BookFileFormat.epub,
      ),
      throwsA(isA<UnimplementedError>()),
    );
    await expectLater(
      service.listDownloadableBooks(),
      throwsA(isA<UnimplementedError>()),
    );
    await expectLater(
      service.resolveDownloadSource('book1'),
      throwsA(isA<UnimplementedError>()),
    );
  });
}
