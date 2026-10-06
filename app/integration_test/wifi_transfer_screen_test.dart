import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:elinkbook/library/book_content_fingerprint.dart';
import 'package:elinkbook/library/book_import_service_impl.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/library/sqlite_library_repository.dart';
import 'package:elinkbook/screens/wifi_transfer_screen.dart';
import 'package:elinkbook/wifi_transfer/network_availability.dart';

import '../test/support/fake_book_import_service.dart';
import '../test/support/fake_library_repository.dart';
import '../test/support/fake_fingerprint_computer.dart';
import '../test/support/pump_localized_widget.dart';

const _metadataChannel = MethodChannel('elinkbook/book_metadata');

/// 把 Flutter asset 複製為裝置暫存目錄中的真實檔案，回傳其絕對路徑（比照
/// `content_uri_acceptance_test.dart` 既有慣例）。
Future<String> _stageAssetAsFile(String assetPath, String fileName) async {
  final bytes = await rootBundle.load(assetPath);
  final tempDir = await getTemporaryDirectory();
  final file = File('${tempDir.path}/$fileName');
  await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
  return file.path;
}

/// 在 [path] 檔案結尾附加 [megabytes] MB 的零位元組填充，讓「中途取消
/// 下載」測試有足夠大的檔案，提高真的能在串流傳輸「中途」（而非傳輸剛
/// 完成後）觸發取消的機率。
Future<void> _padFileWithZeros(String path, int megabytes) async {
  final padding = Uint8List(megabytes * 1024 * 1024);
  await File(path).writeAsBytes(padding, mode: FileMode.append);
}

Future<String> _createAndAuthorizeContentUri(String localPath) async {
  final contentUri = await _metadataChannel
      .invokeMethod<String>('createTestContentUri', {'path': localPath});
  if (contentUri == null) {
    fail('createTestContentUri 未回傳有效的 content:// URI');
  }
  await _metadataChannel
      .invokeMethod<void>('takePersistableUriPermission', {'uri': contentUri});
  return contentUri;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      '真機：伺服器成功綁定 socket，GET / 可取得首頁 HTML（Issue 1 骨架驗證，'
      '裝置須已連上 WiFi 或已開啟手機熱點）', (tester) async {
    await pumpLocalizedWidget(
      tester,
      WifiTransferScreen(
        libraryRepository: FakeLibraryRepository(),
        importService: FakeBookImportService(),
        computeFingerprint: FakeFingerprintComputer().call,
        checkNetworkAvailability: checkNetworkAvailability,
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 5));

    if (tester.any(find.text('請連線至 WiFi 或開啟手機熱點'))) {
      fail('真機測試裝置目前沒有連上 WiFi／開啟熱點，無法驗證伺服器啟動；'
          '請先連線至 WiFi 或開啟手機熱點後重跑本測試。');
    }

    final ipTextWidget =
        tester.widget<Text>(find.byKey(const Key('wifi_transfer_ip_text')));
    final url = ipTextWidget.data!;

    final response = await http.get(Uri.parse(url));
    expect(response.statusCode, 200);
    expect(response.body, contains('elinkBook WiFi 傳書'));
  });

  testWidgets(
      '真機：下載本機路徑來源的書籍，位元組與檔名皆正確（含中文書名，Issue 2 驗收）',
      (tester) async {
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample.pdf', 'wifi_download_local.pdf');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });
    final now = DateTime.fromMillisecondsSinceEpoch(0);
    final book = Book(
      id: 'local-book-1',
      title: '真機測試書名',
      format: BookFileFormat.pdf,
      filePath: samplePath,
      source: BookSource.local,
      createTime: now,
      lastReadTime: now,
    );

    await pumpLocalizedWidget(
      tester,
      WifiTransferScreen(
        libraryRepository: FakeLibraryRepository(initialBooks: [book]),
        importService: FakeBookImportService(),
        computeFingerprint: FakeFingerprintComputer().call,
        checkNetworkAvailability: checkNetworkAvailability,
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 5));

    if (tester.any(find.text('請連線至 WiFi 或開啟手機熱點'))) {
      fail('真機測試裝置目前沒有連上 WiFi／開啟熱點，無法驗證下載；'
          '請先連線至 WiFi 或開啟手機熱點後重跑本測試。');
    }

    final ipTextWidget =
        tester.widget<Text>(find.byKey(const Key('wifi_transfer_ip_text')));
    final baseUrl = ipTextWidget.data!;

    final listResponse = await http.get(Uri.parse('$baseUrl/api/books'));
    expect(listResponse.statusCode, 200);
    final books = jsonDecode(listResponse.body) as List<dynamic>;
    final entry =
        books.singleWhere((b) => b['id'] == 'local-book-1') as Map<String, dynamic>;
    expect(entry['title'], '真機測試書名');

    final downloadResponse =
        await http.get(Uri.parse('$baseUrl/api/books/local-book-1/download'));
    expect(downloadResponse.statusCode, 200);
    expect(downloadResponse.bodyBytes, await File(samplePath).readAsBytes());
    expect(downloadResponse.headers['content-disposition'],
        contains("filename*=UTF-8''"));
  });

  testWidgets(
      '真機：下載 content:// 來源的書籍，位元組正確且暫存檔下載完成後確實清理'
      '（Issue 2 驗收）', (tester) async {
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample.epub', 'wifi_download_content.epub');
    final contentUri = await _createAndAuthorizeContentUri(samplePath);
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    final now = DateTime.fromMillisecondsSinceEpoch(0);
    final book = Book(
      id: 'content-book-1',
      title: 'content 來源書',
      format: BookFileFormat.epub,
      filePath: contentUri,
      source: BookSource.local,
      createTime: now,
      lastReadTime: now,
    );

    await pumpLocalizedWidget(
      tester,
      WifiTransferScreen(
        libraryRepository: FakeLibraryRepository(initialBooks: [book]),
        importService: FakeBookImportService(),
        computeFingerprint: FakeFingerprintComputer().call,
        checkNetworkAvailability: checkNetworkAvailability,
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 5));
    if (tester.any(find.text('請連線至 WiFi 或開啟手機熱點'))) {
      fail('真機測試裝置目前沒有連上 WiFi／開啟熱點，無法驗證下載；'
          '請先連線至 WiFi 或開啟手機熱點後重跑本測試。');
    }
    final ipTextWidget =
        tester.widget<Text>(find.byKey(const Key('wifi_transfer_ip_text')));
    final baseUrl = ipTextWidget.data!;

    final tempDir = await getTemporaryDirectory();
    final pdfTmpDir = Directory('${tempDir.path}/elinkbook_pdf_tmp');
    final before = await pdfTmpDir.exists()
        ? pdfTmpDir.listSync().map((f) => f.path).toSet()
        : <String>{};

    final downloadResponse =
        await http.get(Uri.parse('$baseUrl/api/books/content-book-1/download'));
    expect(downloadResponse.statusCode, 200);
    expect(downloadResponse.bodyBytes, await File(samplePath).readAsBytes());

    // 清理發生在回應串流完全送出「之後」，非同步執行；輪詢等待，最多 5 秒。
    var leftover = <String>{};
    for (var i = 0; i < 25; i++) {
      final after = await pdfTmpDir.exists()
          ? pdfTmpDir.listSync().map((f) => f.path).toSet()
          : <String>{};
      leftover = after.difference(before);
      if (leftover.isEmpty) break;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    expect(leftover, isEmpty,
        reason: '下載完成後，content:// 材質化產生的暫存檔應已被刪除，殘留：$leftover');
  });

  testWidgets('真機：TXT 來源書籍下載時誠實回傳 .epub 副檔名（Issue 2 驗收）',
      (tester) async {
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample.epub', 'wifi_download_txt_source.txt');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });
    final now = DateTime.fromMillisecondsSinceEpoch(0);
    final book = Book(
      id: 'txt-book-1',
      title: 'TXT 合成書',
      format: BookFileFormat.txt,
      filePath: samplePath,
      source: BookSource.local,
      createTime: now,
      lastReadTime: now,
    );

    await pumpLocalizedWidget(
      tester,
      WifiTransferScreen(
        libraryRepository: FakeLibraryRepository(initialBooks: [book]),
        importService: FakeBookImportService(),
        computeFingerprint: FakeFingerprintComputer().call,
        checkNetworkAvailability: checkNetworkAvailability,
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 5));
    if (tester.any(find.text('請連線至 WiFi 或開啟手機熱點'))) {
      fail('真機測試裝置目前沒有連上 WiFi／開啟熱點，無法驗證下載；'
          '請先連線至 WiFi 或開啟手機熱點後重跑本測試。');
    }
    final ipTextWidget =
        tester.widget<Text>(find.byKey(const Key('wifi_transfer_ip_text')));
    final baseUrl = ipTextWidget.data!;

    final downloadResponse =
        await http.get(Uri.parse('$baseUrl/api/books/txt-book-1/download'));
    expect(downloadResponse.statusCode, 200);
    expect(downloadResponse.headers['content-disposition'], contains('.epub'));
    expect(downloadResponse.headers['content-disposition'], isNot(contains('.txt')));
  });

  testWidgets(
      '真機：下載 content:// 來源書籍時中途取消連線，暫存檔仍會被清理'
      '（Issue 2 驗收）', (tester) async {
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample.epub', 'wifi_download_cancel.epub');
    // 補大檔案，提高真的能在串流傳輸「中途」（而非傳輸剛完成後）觸發
    // 取消的機率——見上方 _padFileWithZeros() 文件註解。
    await _padFileWithZeros(samplePath, 8);
    final contentUri = await _createAndAuthorizeContentUri(samplePath);
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    final now = DateTime.fromMillisecondsSinceEpoch(0);
    final book = Book(
      id: 'cancel-book-1',
      title: '中途取消測試書',
      format: BookFileFormat.epub,
      filePath: contentUri,
      source: BookSource.local,
      createTime: now,
      lastReadTime: now,
    );

    await pumpLocalizedWidget(
      tester,
      WifiTransferScreen(
        libraryRepository: FakeLibraryRepository(initialBooks: [book]),
        importService: FakeBookImportService(),
        computeFingerprint: FakeFingerprintComputer().call,
        checkNetworkAvailability: checkNetworkAvailability,
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 5));
    if (tester.any(find.text('請連線至 WiFi 或開啟手機熱點'))) {
      fail('真機測試裝置目前沒有連上 WiFi／開啟熱點，無法驗證下載；'
          '請先連線至 WiFi 或開啟手機熱點後重跑本測試。');
    }
    final ipTextWidget =
        tester.widget<Text>(find.byKey(const Key('wifi_transfer_ip_text')));
    final baseUrl = ipTextWidget.data!;

    final tempDir = await getTemporaryDirectory();
    final pdfTmpDir = Directory('${tempDir.path}/elinkbook_pdf_tmp');
    final before = await pdfTmpDir.exists()
        ? pdfTmpDir.listSync().map((f) => f.path).toSet()
        : <String>{};

    final client = HttpClient();
    final request = await client
        .getUrl(Uri.parse('$baseUrl/api/books/cancel-book-1/download'));
    final response = await request.close();
    // 只讀取第一個資料區塊就中途放棄，模擬使用者關閉瀏覽器分頁/中斷連線。
    await response.first;
    client.close(force: true);

    var leftover = <String>{};
    for (var i = 0; i < 25; i++) {
      final after = await pdfTmpDir.exists()
          ? pdfTmpDir.listSync().map((f) => f.path).toSet()
          : <String>{};
      leftover = after.difference(before);
      if (leftover.isEmpty) break;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    expect(leftover, isEmpty,
        reason: '中途取消下載後，暫存檔仍應被清理，殘留：$leftover');
  });

  testWidgets(
      '真機：上傳一個支援格式檔案，成功出現在圖書庫（Issue 3 驗收）',
      (tester) async {
    sqfliteFfiInit();
    final repository =
        await SqliteLibraryRepository.open(inMemoryDatabasePath);
    addTearDown(() => repository.close());
    final importService = BookImportServiceImpl(repository: repository);

    await pumpLocalizedWidget(
      tester,
      WifiTransferScreen(
        libraryRepository: repository,
        importService: importService,
        computeFingerprint: computeBookContentFingerprint,
        checkNetworkAvailability: checkNetworkAvailability,
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 5));
    if (tester.any(find.text('請連線至 WiFi 或開啟手機熱點'))) {
      fail('真機測試裝置目前沒有連上 WiFi／開啟熱點，無法驗證上傳；'
          '請先連線至 WiFi 或開啟手機熱點後重跑本測試。');
    }
    final ipTextWidget =
        tester.widget<Text>(find.byKey(const Key('wifi_transfer_ip_text')));
    final baseUrl = ipTextWidget.data!;

    final bytes =
        (await rootBundle.load('test/fixtures/sample.pdf')).buffer.asUint8List();
    final request =
        http.MultipartRequest('POST', Uri.parse('$baseUrl/api/upload'))
          ..files.add(http.MultipartFile.fromBytes('files', bytes,
              filename: '真機上傳測試書.pdf'));
    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    expect(response.statusCode, 200);
    final results = jsonDecode(response.body) as List<dynamic>;
    expect(results.single['outcome'], 'imported');

    final books = await repository.listBooks();
    expect(books, hasLength(1));
    expect(books.single.format, BookFileFormat.pdf);
  });

  testWidgets(
      '真機：上傳不支援格式檔案被拒絕，且不影響同一請求內其他檔案的解析'
      '（Issue 3 M-2 驗收）', (tester) async {
    sqfliteFfiInit();
    final repository =
        await SqliteLibraryRepository.open(inMemoryDatabasePath);
    addTearDown(() => repository.close());
    final importService = BookImportServiceImpl(repository: repository);

    await pumpLocalizedWidget(
      tester,
      WifiTransferScreen(
        libraryRepository: repository,
        importService: importService,
        computeFingerprint: computeBookContentFingerprint,
        checkNetworkAvailability: checkNetworkAvailability,
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 5));
    if (tester.any(find.text('請連線至 WiFi 或開啟手機熱點'))) {
      fail('真機測試裝置目前沒有連上 WiFi／開啟熱點，無法驗證上傳；'
          '請先連線至 WiFi 或開啟手機熱點後重跑本測試。');
    }
    final ipTextWidget =
        tester.widget<Text>(find.byKey(const Key('wifi_transfer_ip_text')));
    final baseUrl = ipTextWidget.data!;

    final pdfBytes =
        (await rootBundle.load('test/fixtures/sample.pdf')).buffer.asUint8List();
    final request =
        http.MultipartRequest('POST', Uri.parse('$baseUrl/api/upload'))
          ..files.add(http.MultipartFile.fromBytes(
              'files', Uint8List.fromList([1, 2, 3]),
              filename: '不支援的檔案.docx'))
          ..files.add(http.MultipartFile.fromBytes('files', pdfBytes,
              filename: '正常上傳.pdf'));
    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    expect(response.statusCode, 200);
    final results = jsonDecode(response.body) as List<dynamic>;
    expect(results, hasLength(2));
    expect(results[0]['outcome'], 'unsupportedFormat');
    expect(results[1]['outcome'], 'imported');
    final books = await repository.listBooks();
    expect(books, hasLength(1));
  });

  testWidgets(
      '真機：重複上傳同一檔案兩次，第二次靜默略過、書架上只有一筆記錄'
      '（Issue 3 驗收；改用 PDF，理由見 plan-issue-3.md「已知限制」）',
      (tester) async {
    sqfliteFfiInit();
    final repository =
        await SqliteLibraryRepository.open(inMemoryDatabasePath);
    addTearDown(() => repository.close());
    final importService = BookImportServiceImpl(repository: repository);

    await pumpLocalizedWidget(
      tester,
      WifiTransferScreen(
        libraryRepository: repository,
        importService: importService,
        computeFingerprint: computeBookContentFingerprint,
        checkNetworkAvailability: checkNetworkAvailability,
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 5));
    if (tester.any(find.text('請連線至 WiFi 或開啟手機熱點'))) {
      fail('真機測試裝置目前沒有連上 WiFi／開啟熱點，無法驗證上傳；'
          '請先連線至 WiFi 或開啟手機熱點後重跑本測試。');
    }
    final ipTextWidget =
        tester.widget<Text>(find.byKey(const Key('wifi_transfer_ip_text')));
    final baseUrl = ipTextWidget.data!;

    final bytes =
        (await rootBundle.load('test/fixtures/sample.pdf')).buffer.asUint8List();

    Future<String> uploadOnce() async {
      final request =
          http.MultipartRequest('POST', Uri.parse('$baseUrl/api/upload'))
            ..files.add(http.MultipartFile.fromBytes('files', bytes,
                filename: '重複測試.pdf'));
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      expect(response.statusCode, 200);
      final results = jsonDecode(response.body) as List<dynamic>;
      return results.single['outcome'] as String;
    }

    final firstOutcome = await uploadOnce();
    final secondOutcome = await uploadOnce();

    expect(firstOutcome, 'imported');
    expect(secondOutcome, 'duplicateSkipped');
    final books = await repository.listBooks();
    expect(books, hasLength(1));
  });
}
