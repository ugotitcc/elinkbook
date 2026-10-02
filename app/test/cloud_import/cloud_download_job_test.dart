import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/cloud_import/cloud_download_job.dart';
import 'package:elinkbook/cloud_import/cloud_storage_client.dart';
import 'package:elinkbook/library/models/library_enums.dart';

import '../support/fake_book_import_service.dart';
import '../support/fake_cloud_storage_client.dart';
import '../support/fake_fingerprint_computer.dart';
import '../support/fake_library_repository.dart';

void main() {
  CloudDownloadJob makeJob() => CloudDownloadJob(
        entry: const CloudFileEntry(
          id: 'file-1',
          name: 'a.epub',
          isFolder: false,
          format: BookFileFormat.epub,
        ),
        client: FakeCloudStorageClient(),
        importService: FakeBookImportService(),
        libraryRepository: FakeLibraryRepository(),
        computeFingerprintFn: FakeFingerprintComputer().call,
        source: BookSource.googleDrive,
      );

  test('isAuthFailure 只對 CloudAuthRequiredException 為真', () {
    final job = makeJob();

    expect(job.isAuthFailure(CloudAuthRequiredException()), isTrue);
    expect(job.isAuthFailure(Exception('HTTP 500')), isFalse);
    expect(job.isAuthFailure(StateError('x')), isFalse);
  });
}
