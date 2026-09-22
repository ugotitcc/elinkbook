import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/l10n/app_localizations.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:elinkbook/downloads/download_queue_controller.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/library/widgets/book_cover.dart';
import 'package:elinkbook/remote/remote_server_profile.dart';
import 'package:elinkbook/remote/opds_types.dart';
import 'package:elinkbook/screens/cloud_duplicate_confirm_dialog.dart';
import 'package:elinkbook/screens/remote_catalog_screen.dart';
import 'package:elinkbook/remote/remote_catalog_dependencies.dart';
import 'package:elinkbook/theme/app_theme.dart';
import 'package:elinkbook/theme/app_theme_data.dart';

import '../support/fake_book_import_service.dart';
import '../support/fake_fingerprint_computer.dart';
import '../support/fake_library_repository.dart';
import '../support/fake_opds_client.dart';
import '../support/fake_remote_server_repository.dart';
import '../support/fake_remote_thumbnail_cache.dart';
import '../support/fake_path_provider_platform.dart';

void main() {
  final server = RemoteServerProfile(
    id: 'srv1',
    name: '家用 NAS',
    baseUrl: 'http://192.168.1.100:8080/opds',
    type: RemoteServerType.opds,
    username: 'admin',
    allowInsecure: false,
    createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
  );

  const entry1 = OpdsEntry(
    remoteBookId: 'book-1',
    title: '紅樓夢',
    author: '曹雪芹',
    thumbnailUrl: 'http://192.168.1.100:8080/opds/cover/1.jpg',
    acquisitions: [
      OpdsAcquisition(href: 'http://192.168.1.100:8080/opds/download/1.epub', format: BookFileFormat.epub),
    ],
  );
  const entry2 = OpdsEntry(
    remoteBookId: 'book-2',
    title: '不支援格式的書',
    acquisitions: [
      OpdsAcquisition(href: 'http://192.168.1.100:8080/opds/download/2.doc', format: null),
    ],
  );

  Book fakeBookMatchingRemote({
    required String id,
    required String remoteServerId,
    required String remoteBookId,
  }) {
    return Book(
      id: id,
      title: '已匯入的書',
      format: BookFileFormat.epub,
      filePath: '/books/$id.epub',
      source: BookSource.calibreOpds,
      remoteServerId: remoteServerId,
      remoteBookId: remoteBookId,
      createTime: DateTime.fromMillisecondsSinceEpoch(1000),
      lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
    );
  }

  Book fakeBookWithFingerprint(String id, String fingerprint) {
    return Book(
      id: id,
      title: '本機已有的書',
      format: BookFileFormat.epub,
      filePath: '/books/$id.epub',
      source: BookSource.local,
      contentFingerprint: fingerprint,
      createTime: DateTime.fromMillisecondsSinceEpoch(1000),
      lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
    );
  }

  Future<void> pumpScreen(
    WidgetTester tester, {
    required FakeOpdsClient opdsClient,
    FakeRemoteServerRepository? repository,
    FakeLibraryRepository? libraryRepository,
    FakeFingerprintComputer? fingerprintComputer,
    FakeRemoteThumbnailCache? thumbnailCache,
    String? feedUrl,
    DownloadQueueController? downloadQueueController,
    Locale locale = const Locale('zh', 'TW'),
  }) async {
    await tester.pumpWidget(MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
      home: RemoteCatalogScreen(
        server: server,
        repository: repository ?? FakeRemoteServerRepository(),
        libraryRepository: libraryRepository ?? FakeLibraryRepository(),
        dependencies: RemoteCatalogDependencies(
          computeFingerprint: (fingerprintComputer ?? FakeFingerprintComputer()).call,
          thumbnailCache: thumbnailCache ?? FakeRemoteThumbnailCache(),
          createOpdsClient: () => opdsClient,
        ),
        importService: FakeBookImportService(),
        feedUrl: feedUrl,
        downloadQueueController:
            downloadQueueController ??
            DownloadQueueController(onDuplicateConfirm: (_) async => false),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('載入根目錄後顯示分類導覽與書目', (tester) async {
    final opdsClient = FakeOpdsClient(feeds: {
      server.baseUrl: const OpdsFeed(
        title: '家用 NAS 書庫',
        navigationLinks: [OpdsNavigationLink(title: '作者分類', href: 'http://192.168.1.100:8080/opds/by-author')],
        entries: [entry1, entry2],
      ),
    });
    await pumpScreen(tester, opdsClient: opdsClient);

    expect(find.text('作者分類'), findsOneWidget);
    expect(find.text('紅樓夢'), findsOneWidget);
    // entry2 沒有縮圖網址，書名會出現兩次：CoverPlaceholder 內部的書名
    // 微縮＋_buildEntryTile() 格子下方既有的書名 caption——與
    // library_screen.dart 的 _BookGridTile／BookCover 既有先例一致
    // （Issue 6/9 已審查通過），非本 Task 造成的回歸。
    expect(find.text('不支援格式的書'), findsNWidgets(2));
  });

  testWidgets('點擊分類導覽項目時 push 新的 RemoteCatalogScreen 並載入該分類 Feed', (tester) async {
    final opdsClient = FakeOpdsClient(feeds: {
      server.baseUrl: const OpdsFeed(
        title: '根目錄',
        navigationLinks: [OpdsNavigationLink(title: '作者分類', href: 'http://192.168.1.100:8080/opds/by-author')],
      ),
      'http://192.168.1.100:8080/opds/by-author': const OpdsFeed(
        title: '作者分類',
        entries: [entry1],
      ),
    });
    await pumpScreen(tester, opdsClient: opdsClient);

    await tester.tap(find.text('作者分類'));
    await tester.pumpAndSettle();

    expect(find.text('紅樓夢'), findsOneWidget);
    expect(opdsClient.fetchFeedCalls, [null, 'http://192.168.1.100:8080/opds/by-author']);
  });

  testWidgets('點擊分類導覽項目下鑽後，新畫面沿用同一個 RemoteCatalogDependencies 實例（epic-26 Issue 6 回歸鎖定）',
      (tester) async {
    final opdsClient = FakeOpdsClient(feeds: {
      server.baseUrl: const OpdsFeed(
        title: '根目錄',
        navigationLinks: [OpdsNavigationLink(title: '作者分類', href: 'http://192.168.1.100:8080/opds/by-author')],
      ),
      'http://192.168.1.100:8080/opds/by-author': const OpdsFeed(
        title: '作者分類',
        entries: [entry1],
      ),
    });
    final dependencies = RemoteCatalogDependencies(
      computeFingerprint: FakeFingerprintComputer().call,
      thumbnailCache: FakeRemoteThumbnailCache(),
      createOpdsClient: () => opdsClient,
    );
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('zh', 'TW'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
      home: RemoteCatalogScreen(
        server: server,
        repository: FakeRemoteServerRepository(),
        libraryRepository: FakeLibraryRepository(),
        dependencies: dependencies,
        importService: FakeBookImportService(),
        downloadQueueController:
            DownloadQueueController(onDuplicateConfirm: (_) async => false),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('作者分類'));
    await tester.pumpAndSettle();

    final pushedScreen = tester.widget<RemoteCatalogScreen>(find.byType(RemoteCatalogScreen).last);
    expect(pushedScreen.dependencies, same(dependencies),
        reason: '下鑽後的新畫面應沿用同一個 bundle 實例，不是重新組裝的另一份');
  });

  testWidgets('有 nextUrl 時顯示載入更多按鈕，點擊後累加下一頁書目', (tester) async {
    final opdsClient = FakeOpdsClient(feeds: {
      server.baseUrl: const OpdsFeed(
        title: '根目錄',
        nextUrl: 'http://192.168.1.100:8080/opds/page2',
        entries: [entry1],
      ),
      'http://192.168.1.100:8080/opds/page2': const OpdsFeed(
        title: '根目錄',
        entries: [entry2],
      ),
    });
    await pumpScreen(tester, opdsClient: opdsClient);

    expect(find.byKey(const Key('remote_catalog_load_more_button')), findsOneWidget);
    await tester.tap(find.byKey(const Key('remote_catalog_load_more_button')));
    await tester.pumpAndSettle();

    expect(find.text('紅樓夢'), findsOneWidget);
    // entry2 沒有縮圖網址，書名重複顯示兩次（CoverPlaceholder 內部書名
    // 微縮＋外層 caption），與 library_screen.dart 既有先例一致。
    expect(find.text('不支援格式的書'), findsNWidgets(2));
    expect(find.byKey(const Key('remote_catalog_load_more_button')), findsNothing);
  });

  testWidgets('沒有 nextUrl 時不顯示載入更多按鈕', (tester) async {
    final opdsClient = FakeOpdsClient(feeds: {
      server.baseUrl: const OpdsFeed(title: '根目錄', entries: [entry1]),
    });
    await pumpScreen(tester, opdsClient: opdsClient);

    expect(find.byKey(const Key('remote_catalog_load_more_button')), findsNothing);
  });

  testWidgets('書目縮圖透過 RemoteThumbnailCache 取得，帶入正確的 URL 與 Basic Auth header', (tester) async {
    final opdsClient = FakeOpdsClient(feeds: {
      server.baseUrl: const OpdsFeed(title: '根目錄', entries: [entry1]),
    });
    final thumbnailCache = FakeRemoteThumbnailCache();
    await pumpScreen(tester, opdsClient: opdsClient, thumbnailCache: thumbnailCache);

    expect(thumbnailCache.fetchCalls, [entry1.thumbnailUrl]);
    final image = tester.widget<Image>(find.byKey(const Key('remote_catalog_thumbnail_book-1')));
    expect(image.image, isA<MemoryImage>());
  });

  testWidgets('縮圖快取擷取失敗時顯示錯誤圖示', (tester) async {
    final opdsClient = FakeOpdsClient(feeds: {
      server.baseUrl: const OpdsFeed(title: '根目錄', entries: [entry1]),
    });
    final thumbnailCache = FakeRemoteThumbnailCache(error: StateError('模擬縮圖下載失敗'));
    await pumpScreen(tester, opdsClient: opdsClient, thumbnailCache: thumbnailCache);

    final errorFinder = find.byKey(const Key('remote_catalog_thumbnail_error_book-1'));
    expect(errorFinder, findsOneWidget);
    final errorPlaceholder = tester.widget(errorFinder);
    expect(errorPlaceholder, isA<CoverPlaceholder>());
    expect((errorPlaceholder as CoverPlaceholder).title, entry1.title);
  });

  testWidgets('沒有縮圖的書目顯示預設圖示佔位符', (tester) async {
    const entryNoCover = OpdsEntry(
      remoteBookId: 'book-3',
      title: '無縮圖的書',
      acquisitions: [OpdsAcquisition(href: 'http://x/3.epub', format: BookFileFormat.epub)],
    );
    final opdsClient = FakeOpdsClient(feeds: {
      server.baseUrl: const OpdsFeed(title: '根目錄', entries: [entryNoCover]),
    });
    await pumpScreen(tester, opdsClient: opdsClient);

    final placeholderFinder =
        find.byKey(const Key('remote_catalog_thumbnail_placeholder_book-3'));
    expect(placeholderFinder, findsOneWidget);
    final placeholder = tester.widget(placeholderFinder);
    expect(placeholder, isA<CoverPlaceholder>());
    expect((placeholder as CoverPlaceholder).title, entryNoCover.title);
  });

  testWidgets('點擊書目可勾選/取消勾選，僅有支援格式的書目可勾選', (tester) async {
    final opdsClient = FakeOpdsClient(feeds: {
      server.baseUrl: const OpdsFeed(title: '根目錄', entries: [entry1, entry2]),
    });
    await pumpScreen(tester, opdsClient: opdsClient);

    await tester.tap(find.byKey(const Key('remote_catalog_entry_book-1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('remote_catalog_checkbox_checked_book-1')), findsOneWidget);

    await tester.tap(find.byKey(const Key('remote_catalog_entry_book-1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('remote_catalog_checkbox_checked_book-1')), findsNothing);

    // entry2 完全沒有支援格式，點擊不應該有任何反應。
    await tester.tap(find.byKey(const Key('remote_catalog_entry_book-2')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('remote_catalog_checkbox_checked_book-2')), findsNothing);
  });

  testWidgets('載入失敗時顯示錯誤文字', (tester) async {
    final opdsClient = FakeOpdsClient(feeds: const {});
    await pumpScreen(tester, opdsClient: opdsClient);

    expect(find.byKey(const Key('remote_catalog_error_text')), findsOneWidget);
  });

  group('選檔前置重複偵測（Layer 1）', () {
    testWidgets('勾選已存在 remoteServerId/remoteBookId 的書目時彈出重複提示，選擇取消則不勾選', (tester) async {
      final opdsClient = FakeOpdsClient(feeds: {
        server.baseUrl: const OpdsFeed(title: '根目錄', entries: [entry1]),
      });
      final libraryRepository = FakeLibraryRepository(initialBooks: [
        fakeBookMatchingRemote(id: 'local-1', remoteServerId: 'srv1', remoteBookId: 'book-1'),
      ]);
      await pumpScreen(tester, opdsClient: opdsClient, libraryRepository: libraryRepository);

      await tester.tap(find.byKey(const Key('remote_catalog_entry_book-1')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('remote_catalog_duplicate_dialog')), findsOneWidget);
      await tester.tap(find.byKey(const Key('remote_catalog_duplicate_dialog_cancel')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('remote_catalog_checkbox_checked_book-1')), findsNothing);
    });

    testWidgets('勾選已存在的書目時彈出重複提示，選擇仍要建立則正常勾選', (tester) async {
      final opdsClient = FakeOpdsClient(feeds: {
        server.baseUrl: const OpdsFeed(title: '根目錄', entries: [entry1]),
      });
      final libraryRepository = FakeLibraryRepository(initialBooks: [
        fakeBookMatchingRemote(id: 'local-1', remoteServerId: 'srv1', remoteBookId: 'book-1'),
      ]);
      await pumpScreen(tester, opdsClient: opdsClient, libraryRepository: libraryRepository);

      await tester.tap(find.byKey(const Key('remote_catalog_entry_book-1')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('remote_catalog_duplicate_dialog_confirm')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('remote_catalog_checkbox_checked_book-1')), findsOneWidget);
    });

    testWidgets('勾選沒有重複紀錄的書目時不彈出提示，直接勾選', (tester) async {
      final opdsClient = FakeOpdsClient(feeds: {
        server.baseUrl: const OpdsFeed(title: '根目錄', entries: [entry1]),
      });
      await pumpScreen(tester, opdsClient: opdsClient);

      await tester.tap(find.byKey(const Key('remote_catalog_entry_book-1')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('remote_catalog_duplicate_dialog')), findsNothing);
      expect(find.byKey(const Key('remote_catalog_checkbox_checked_book-1')), findsOneWidget);
    });
  });

  group('E-Ink 模式離散分頁（Issue 5）', () {
    testWidgets('E-Ink 模式下有 nextUrl 時顯示上一頁/下一頁按鈕，不顯示載入更多按鈕；第一頁上一頁按鈕停用',
        (tester) async {
      final opdsClient = FakeOpdsClient(feeds: {
        server.baseUrl: const OpdsFeed(
          title: '根目錄',
          nextUrl: 'http://x/page2',
          entries: [entry1],
        ),
      });
      await tester.pumpWidget(MaterialApp(
      locale: const Locale('zh', 'TW'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: RemoteCatalogScreen(
          server: server,
          repository: FakeRemoteServerRepository(),
          libraryRepository: FakeLibraryRepository(),
          dependencies: RemoteCatalogDependencies(
            computeFingerprint: FakeFingerprintComputer().call,
            thumbnailCache: FakeRemoteThumbnailCache(),
            createOpdsClient: () => opdsClient,
          ),
          importService: FakeBookImportService(),
          isEinkMode: true,
          downloadQueueController:
              DownloadQueueController(onDuplicateConfirm: (_) async => false),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('remote_catalog_eink_next_page_button')), findsOneWidget);
      expect(find.byKey(const Key('remote_catalog_eink_prev_page_button')), findsOneWidget);
      expect(find.byKey(const Key('remote_catalog_load_more_button')), findsNothing);

      final prevButton =
          tester.widget<OutlinedButton>(find.byKey(const Key('remote_catalog_eink_prev_page_button')));
      expect(prevButton.onPressed, isNull);
    });

    testWidgets('E-Ink 模式點擊下一頁後整批替換書目（非累加），上一頁按鈕變為可點擊', (tester) async {
      final opdsClient = FakeOpdsClient(feeds: {
        server.baseUrl: const OpdsFeed(
          title: '根目錄',
          nextUrl: 'http://x/page2',
          entries: [entry1],
        ),
        'http://x/page2': const OpdsFeed(
          title: '根目錄',
          prevUrl: 'http://x/page1',
          entries: [entry2],
        ),
      });
      await tester.pumpWidget(MaterialApp(
      locale: const Locale('zh', 'TW'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: RemoteCatalogScreen(
          server: server,
          repository: FakeRemoteServerRepository(),
          libraryRepository: FakeLibraryRepository(),
          dependencies: RemoteCatalogDependencies(
            computeFingerprint: FakeFingerprintComputer().call,
            thumbnailCache: FakeRemoteThumbnailCache(),
            createOpdsClient: () => opdsClient,
          ),
          importService: FakeBookImportService(),
          isEinkMode: true,
          downloadQueueController:
              DownloadQueueController(onDuplicateConfirm: (_) async => false),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('remote_catalog_eink_next_page_button')));
      await tester.pumpAndSettle();

      expect(find.text('紅樓夢'), findsNothing);
      // entry2 沒有縮圖網址，書名重複顯示兩次（CoverPlaceholder 內部書名
      // 微縮＋外層 caption），與 library_screen.dart 既有先例一致。
      expect(find.text('不支援格式的書'), findsNWidgets(2));

      final nextButton =
          tester.widget<OutlinedButton>(find.byKey(const Key('remote_catalog_eink_next_page_button')));
      expect(nextButton.onPressed, isNull);
      final prevButton =
          tester.widget<OutlinedButton>(find.byKey(const Key('remote_catalog_eink_prev_page_button')));
      expect(prevButton.onPressed, isNotNull);
    });

    testWidgets('非 E-Ink 模式（預設）維持既有載入更多按鈕，不顯示上一頁/下一頁按鈕', (tester) async {
      final opdsClient = FakeOpdsClient(feeds: {
        server.baseUrl: const OpdsFeed(
          title: '根目錄',
          nextUrl: 'http://x/page2',
          entries: [entry1],
        ),
      });
      await tester.pumpWidget(MaterialApp(
      locale: const Locale('zh', 'TW'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: RemoteCatalogScreen(
          server: server,
          repository: FakeRemoteServerRepository(),
          libraryRepository: FakeLibraryRepository(),
          dependencies: RemoteCatalogDependencies(
            computeFingerprint: FakeFingerprintComputer().call,
            thumbnailCache: FakeRemoteThumbnailCache(),
            createOpdsClient: () => opdsClient,
          ),
          importService: FakeBookImportService(),
          downloadQueueController:
              DownloadQueueController(onDuplicateConfirm: (_) async => false),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('remote_catalog_load_more_button')), findsOneWidget);
      expect(find.byKey(const Key('remote_catalog_eink_next_page_button')), findsNothing);
      expect(find.byKey(const Key('remote_catalog_eink_prev_page_button')), findsNothing);
    });
  });

  group('下載與匯入', () {
    late Directory tempRoot;
    late PathProviderPlatform originalPathProvider;


    setUp(() {
      tempRoot = Directory.systemTemp.createTempSync('remote_catalog_test');
      originalPathProvider = PathProviderPlatform.instance;
      PathProviderPlatform.instance = FakePathProviderPlatform(tempRoot.path);
    });

    tearDown(() {
      PathProviderPlatform.instance = originalPathProvider;
      if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
    });

    testWidgets('勾選單本書下載後呼叫 importFiles，帶入 source/remoteServerId/remoteBookIds/remoteDownloadUrls',
        (tester) async {
      final opdsClient = FakeOpdsClient(feeds: {
        server.baseUrl: const OpdsFeed(title: '根目錄', entries: [entry1]),
      });
      final importService = FakeBookImportService();
      final downloadQueueController =
          DownloadQueueController(onDuplicateConfirm: (_) async => false);
      await tester.pumpWidget(MaterialApp(
      locale: const Locale('zh', 'TW'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: RemoteCatalogScreen(
          server: server,
          repository: FakeRemoteServerRepository(),
          libraryRepository: FakeLibraryRepository(),
          dependencies: RemoteCatalogDependencies(
            computeFingerprint: (path, format) async => 'unused-fingerprint',
            thumbnailCache: FakeRemoteThumbnailCache(),
            createOpdsClient: () => opdsClient,
          ),
          importService: importService,
          downloadQueueController: downloadQueueController,
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('remote_catalog_entry_book-1')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('remote_catalog_download_button')));
      await tester.pump();

      // 視覺還原（Visual Accuracy Mode）：下載改為加入常駐佇列後非模態，
      // 畫面立即顯示提示 Snackbar，不再跳出阻擋畫面的下載對話框——常駐
      // 佇列面板本身掛在 SourcesHomeScreen（見 sources_home_screen_test.dart），
      // 這裡只驗證 RemoteCatalogScreen 端把工作正確交給共用的
      // DownloadQueueController，狀態改用 controller.items 直接查驗。
      expect(
        find.byKey(const Key('remote_catalog_queued_snackbar')),
        findsOneWidget,
      );

      // 交錯 runAsync（提供真實事件迴圈讓 dart:io 完成）與 pump（處理微佇列），
      // 驅動 DownloadQueueController._downloadOne 中的 getTemporaryDirectory
      // → File.create → writeAsBytes → copy → delete → importFiles → notifyListeners 完整鏈。
      for (var i = 0; i < 30; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump();
      }
      await tester.pumpAndSettle();

      expect(downloadQueueController.items.single.status, DownloadItemStatus.done);
      expect(opdsClient.downloadBookCalls, ['http://192.168.1.100:8080/opds/download/1.epub']);
    });

    testWidgets('同一書目有多個支援格式時彈出 FormatSelectionDialog 讓使用者選擇', (tester) async {
      const multiFormatEntry = OpdsEntry(
        remoteBookId: 'book-multi',
        title: '多格式書',
        acquisitions: [
          OpdsAcquisition(href: 'http://x/m.epub', format: BookFileFormat.epub),
          OpdsAcquisition(href: 'http://x/m.pdf', format: BookFileFormat.pdf),
        ],
      );
      final opdsClient = FakeOpdsClient(feeds: {
        server.baseUrl: const OpdsFeed(title: '根目錄', entries: [multiFormatEntry]),
      });
      await tester.pumpWidget(MaterialApp(
      locale: const Locale('zh', 'TW'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: RemoteCatalogScreen(
          server: server,
          repository: FakeRemoteServerRepository(),
          libraryRepository: FakeLibraryRepository(),
          dependencies: RemoteCatalogDependencies(
            computeFingerprint: (path, format) async => 'unused-fingerprint',
            thumbnailCache: FakeRemoteThumbnailCache(),
            createOpdsClient: () => opdsClient,
          ),
          importService: FakeBookImportService(),
          downloadQueueController:
              DownloadQueueController(onDuplicateConfirm: (_) async => false),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('remote_catalog_entry_book-multi')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('remote_catalog_download_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('format_selection_dialog')), findsOneWidget);
      await tester.tap(find.byKey(const Key('format_selection_option_http://x/m.pdf')));
      await tester.pump();

      // 交錯 runAsync 與 pump 驅動 dart:io 完成。
      for (var i = 0; i < 30; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump();
      }
      await tester.pumpAndSettle();

      expect(opdsClient.downloadBookCalls, ['http://x/m.pdf']);
    });

    testWidgets('多選批次下載時逐項序列進行，非平行', (tester) async {
      const entryA = OpdsEntry(
        remoteBookId: 'book-a',
        title: '書 A',
        acquisitions: [OpdsAcquisition(href: 'http://x/a.epub', format: BookFileFormat.epub)],
      );
      const entryB = OpdsEntry(
        remoteBookId: 'book-b',
        title: '書 B',
        acquisitions: [OpdsAcquisition(href: 'http://x/b.epub', format: BookFileFormat.epub)],
      );
      final opdsClient = FakeOpdsClient(feeds: {
        server.baseUrl: const OpdsFeed(title: '根目錄', entries: [entryA, entryB]),
      });
      await tester.pumpWidget(MaterialApp(
      locale: const Locale('zh', 'TW'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: RemoteCatalogScreen(
          server: server,
          repository: FakeRemoteServerRepository(),
          libraryRepository: FakeLibraryRepository(),
          dependencies: RemoteCatalogDependencies(
            computeFingerprint: (path, format) async => 'unused-fingerprint',
            thumbnailCache: FakeRemoteThumbnailCache(),
            createOpdsClient: () => opdsClient,
          ),
          importService: FakeBookImportService(),
          downloadQueueController:
              DownloadQueueController(onDuplicateConfirm: (_) async => false),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('remote_catalog_entry_book-a')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('remote_catalog_entry_book-b')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('remote_catalog_download_button')));
      await tester.pump();

      // 交錯 runAsync 與 pump 驅動 dart:io 完成（兩本書序列下載）。
      for (var i = 0; i < 30; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump();
      }
      await tester.pumpAndSettle();

      expect(opdsClient.downloadBookCalls, ['http://x/a.epub', 'http://x/b.epub']);
    });

    testWidgets('下載失敗時顯示失敗狀態並可手動重試', (tester) async {
      final opdsClient = FakeOpdsClient(
        feeds: {
          server.baseUrl: const OpdsFeed(title: '根目錄', entries: [entry1]),
        },
        downloadError: StateError('模擬下載失敗'),
      );
      final downloadQueueController =
          DownloadQueueController(onDuplicateConfirm: (_) async => false);
      await tester.pumpWidget(MaterialApp(
      locale: const Locale('zh', 'TW'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: RemoteCatalogScreen(
          server: server,
          repository: FakeRemoteServerRepository(),
          libraryRepository: FakeLibraryRepository(),
          dependencies: RemoteCatalogDependencies(
            computeFingerprint: (path, format) async => 'unused-fingerprint',
            thumbnailCache: FakeRemoteThumbnailCache(),
            createOpdsClient: () => opdsClient,
          ),
          importService: FakeBookImportService(),
          downloadQueueController: downloadQueueController,
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('remote_catalog_entry_book-1')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('remote_catalog_download_button')));
      await tester.pump();

      // 交錯 runAsync 與 pump 驅動 dart:io 微佇列（下載失敗仍需 pump 處理微佇列）。
      for (var i = 0; i < 30; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump();
      }
      await tester.pumpAndSettle();

      expect(downloadQueueController.items.single.status, DownloadItemStatus.failed);

      // 常駐佇列面板（重試按鈕）掛在 SourcesHomeScreen，這裡直接呼叫
      // controller.retry() 驗證重試邏輯本身正確，不需要透過 UI 按鈕。
      opdsClient.downloadError = null;
      await tester.runAsync(() => downloadQueueController.retry(entry1.remoteBookId));
      await tester.pumpAndSettle();

      expect(downloadQueueController.items.single.status, DownloadItemStatus.done);
    });

    testWidgets('下載中點擊取消後顯示已取消狀態，暫存檔不殘留', (tester) async {
      final opdsClient = FakeOpdsClient(feeds: {
        server.baseUrl: const OpdsFeed(title: '根目錄', entries: [entry1]),
      });
      opdsClient.downloadPendingCompleter = Completer<void>();
      final downloadQueueController =
          DownloadQueueController(onDuplicateConfirm: (_) async => false);
      await tester.pumpWidget(MaterialApp(
      locale: const Locale('zh', 'TW'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: RemoteCatalogScreen(
          server: server,
          repository: FakeRemoteServerRepository(),
          libraryRepository: FakeLibraryRepository(),
          dependencies: RemoteCatalogDependencies(
            computeFingerprint: (path, format) async => 'unused-fingerprint',
            thumbnailCache: FakeRemoteThumbnailCache(),
            createOpdsClient: () => opdsClient,
          ),
          importService: FakeBookImportService(),
          downloadQueueController: downloadQueueController,
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('remote_catalog_entry_book-1')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('remote_catalog_download_button')));
      await tester.pump();

      // 常駐佇列面板（取消按鈕）掛在 SourcesHomeScreen，這裡直接呼叫
      // controller.cancel() 驗證取消邏輯本身正確，不需要透過 UI 按鈕。
      downloadQueueController.cancel(entry1.remoteBookId);
      opdsClient.downloadPendingCompleter!.complete();

      // 交錯 runAsync 與 pump 驅動 dart:io 微佇列（取消後仍需處理微佇列）。
      for (var i = 0; i < 30; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump();
      }
      await tester.pumpAndSettle();

      expect(downloadQueueController.items.single.status, DownloadItemStatus.cancelled);
    });

    testWidgets(
        '引數驗證：importFiles 被呼叫時正確帶入 source/remoteServerId/remoteBookIds/remoteDownloadUrls（FakeBookImportService）',
        (tester) async {
      final importService = FakeBookImportService();

      final opdsClient = FakeOpdsClient(feeds: {
        server.baseUrl: const OpdsFeed(title: '根目錄', entries: [entry1]),
      });
      await tester.pumpWidget(MaterialApp(
      locale: const Locale('zh', 'TW'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: RemoteCatalogScreen(
          server: server,
          repository: FakeRemoteServerRepository(),
          libraryRepository: FakeLibraryRepository(),
          dependencies: RemoteCatalogDependencies(
            computeFingerprint: (path, format) async => 'unused-fingerprint',
            thumbnailCache: FakeRemoteThumbnailCache(),
            createOpdsClient: () => opdsClient,
          ),
          importService: importService,
          downloadQueueController:
              DownloadQueueController(onDuplicateConfirm: (_) async => false),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('remote_catalog_entry_book-1')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('remote_catalog_download_button')));
      await tester.pump();

      // 交錯 runAsync 與 pump 驅動 dart:io 微佇列。
      for (var i = 0; i < 30; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump();
      }
      await tester.pumpAndSettle();

      // 驗證 importFiles 被正確呼叫，帶入遠端書籍 metadata
      expect(importService.lastImportCall, isNotNull);
      expect(importService.lastImportCall!.source, BookSource.calibreOpds);
      expect(importService.lastImportCall!.remoteServerId, 'srv1');
      expect(importService.lastImportCall!.remoteBookIds, {
        importService.lastImportCall!.uris.single: 'book-1',
      });
      expect(importService.lastImportCall!.remoteDownloadUrls, {
        importService.lastImportCall!.uris.single: 'http://192.168.1.100:8080/opds/download/1.epub',
      });

      // 驗證 OPDS client 被正確呼叫
      expect(opdsClient.downloadBookCalls, ['http://192.168.1.100:8080/opds/download/1.epub']);
    });

    group('下載後指紋比對（Layer 2）', () {
      testWidgets('下載後偵測到與本機書籍內容指紋相同時彈出提示，選擇不建立新副本則刪除暫存檔並標記為略過',
          (tester) async {
        final opdsClient = FakeOpdsClient(feeds: {
          server.baseUrl: const OpdsFeed(title: '根目錄', entries: [entry1]),
        });
        final libraryRepository = FakeLibraryRepository(initialBooks: [
          fakeBookWithFingerprint('local-1', 'dup-fingerprint'),
        ]);
        final fingerprintComputer = FakeFingerprintComputer()..nextFingerprint = 'dup-fingerprint';
        final importService = FakeBookImportService();
        // 視覺還原（Visual Accuracy Mode）：下載後重複（Layer 2）確認彈窗改由
        // 共用的 DownloadQueueController.onDuplicateConfirm 觸發，比照
        // main.dart 的 navigatorKey 橋接模式呼叫 showCloudDuplicateConfirmDialog
        // ——與 RemoteCatalogScreen 自己原本的 Layer 1
        // `_showDuplicateConfirmDialog`（key 為 remote_catalog_duplicate_dialog*）
        // 是不同的兩層檢查、不同的彈窗 key（cloud_duplicate_dialog*）。
        final navigatorKey = GlobalKey<NavigatorState>();
        final downloadQueueController = DownloadQueueController(
          onDuplicateConfirm: (message) async {
            final context = navigatorKey.currentContext;
            if (context == null) return false;
            return showCloudDuplicateConfirmDialog(context, message);
          },
        );
        await tester.pumpWidget(MaterialApp(
      locale: const Locale('zh', 'TW'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
          navigatorKey: navigatorKey,
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: RemoteCatalogScreen(
            server: server,
            repository: FakeRemoteServerRepository(),
            libraryRepository: libraryRepository,
            dependencies: RemoteCatalogDependencies(
              computeFingerprint: fingerprintComputer.call,
              thumbnailCache: FakeRemoteThumbnailCache(),
              createOpdsClient: () => opdsClient,
            ),
            importService: importService,
            downloadQueueController: downloadQueueController,
          ),
        ));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('remote_catalog_entry_book-1')));
        await tester.pump();
        await tester.tap(find.byKey(const Key('remote_catalog_download_button')));
        await tester.pump();

        for (var i = 0; i < 30; i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
          await tester.pump();
          if (find.byKey(const Key('cloud_duplicate_dialog')).evaluate().isNotEmpty) break;
        }

        expect(find.byKey(const Key('cloud_duplicate_dialog')), findsOneWidget);
        await tester.tap(find.byKey(const Key('cloud_duplicate_dialog_cancel')));
        await tester.pump();

        for (var i = 0; i < 30; i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
          await tester.pump();
        }
        await tester.pumpAndSettle();

        expect(
          downloadQueueController.items.single.status,
          DownloadItemStatus.duplicateSkipped,
        );
        expect(importService.lastImportCall, isNull);
        expect(
          Directory(p.join(tempRoot.path, 'remote_download_temp')).listSync(),
          isEmpty,
        );
      });

      testWidgets('下載後偵測到重複時選擇仍要建立新副本，正常完成匯入', (tester) async {
        final opdsClient = FakeOpdsClient(feeds: {
          server.baseUrl: const OpdsFeed(title: '根目錄', entries: [entry1]),
        });
        final libraryRepository = FakeLibraryRepository(initialBooks: [
          fakeBookWithFingerprint('local-1', 'dup-fingerprint'),
        ]);
        final fingerprintComputer = FakeFingerprintComputer()..nextFingerprint = 'dup-fingerprint';
        final importService = FakeBookImportService();
        final navigatorKey = GlobalKey<NavigatorState>();
        final downloadQueueController = DownloadQueueController(
          onDuplicateConfirm: (message) async {
            final context = navigatorKey.currentContext;
            if (context == null) return false;
            return showCloudDuplicateConfirmDialog(context, message);
          },
        );
        await tester.pumpWidget(MaterialApp(
      locale: const Locale('zh', 'TW'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
          navigatorKey: navigatorKey,
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: RemoteCatalogScreen(
            server: server,
            repository: FakeRemoteServerRepository(),
            libraryRepository: libraryRepository,
            dependencies: RemoteCatalogDependencies(
              computeFingerprint: fingerprintComputer.call,
              thumbnailCache: FakeRemoteThumbnailCache(),
              createOpdsClient: () => opdsClient,
            ),
            importService: importService,
            downloadQueueController: downloadQueueController,
          ),
        ));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('remote_catalog_entry_book-1')));
        await tester.pump();
        await tester.tap(find.byKey(const Key('remote_catalog_download_button')));
        await tester.pump();

        for (var i = 0; i < 30; i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
          await tester.pump();
          if (find.byKey(const Key('cloud_duplicate_dialog')).evaluate().isNotEmpty) break;
        }

        await tester.tap(find.byKey(const Key('cloud_duplicate_dialog_confirm')));
        await tester.pump();

        for (var i = 0; i < 30; i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
          await tester.pump();
        }
        await tester.pumpAndSettle();

        expect(downloadQueueController.items.single.status, DownloadItemStatus.done);
        expect(importService.lastImportCall, isNotNull);
      });

      testWidgets('下載後未偵測到重複時不彈出提示，直接完成', (tester) async {
        final opdsClient = FakeOpdsClient(feeds: {
          server.baseUrl: const OpdsFeed(title: '根目錄', entries: [entry1]),
        });
        final importService = FakeBookImportService();
        final fingerprintComputer = FakeFingerprintComputer();
        final navigatorKey = GlobalKey<NavigatorState>();
        final downloadQueueController = DownloadQueueController(
          onDuplicateConfirm: (message) async {
            final context = navigatorKey.currentContext;
            if (context == null) return false;
            return showCloudDuplicateConfirmDialog(context, message);
          },
        );
        await tester.pumpWidget(MaterialApp(
      locale: const Locale('zh', 'TW'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
          navigatorKey: navigatorKey,
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: RemoteCatalogScreen(
            server: server,
            repository: FakeRemoteServerRepository(),
            libraryRepository: FakeLibraryRepository(),
            dependencies: RemoteCatalogDependencies(
              computeFingerprint: fingerprintComputer.call,
              thumbnailCache: FakeRemoteThumbnailCache(),
              createOpdsClient: () => opdsClient,
            ),
            importService: importService,
            downloadQueueController: downloadQueueController,
          ),
        ));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('remote_catalog_entry_book-1')));
        await tester.pump();
        await tester.tap(find.byKey(const Key('remote_catalog_download_button')));
        await tester.pump();

        for (var i = 0; i < 30; i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
          await tester.pump();
        }
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('cloud_duplicate_dialog')), findsNothing);
        expect(downloadQueueController.items.single.status, DownloadItemStatus.done);
        expect(importService.lastImportCall, isNotNull);
        // 〔審查 review-issue-3.md Minor 採納〕驗證指紋計算確實在下載成功
        // 之後才被呼叫恰好一次，且傳入的是下載完成的暫存檔路徑。
        expect(fingerprintComputer.calls, hasLength(1));
        expect(fingerprintComputer.calls.single, isNotEmpty);
      });
    });

    group('選檔前置重複偵測查詢失敗（Layer 1 錯誤處理，review-issue-3.md Important 採納）', () {
      testWidgets('findByRemoteBookId 拋出例外時，視同沒有偵測到重複，直接勾選不中斷', (tester) async {
        final opdsClient = FakeOpdsClient(feeds: {
          server.baseUrl: const OpdsFeed(title: '根目錄', entries: [entry1]),
        });
        final libraryRepository = FakeLibraryRepository()..throwOnFindByRemoteBookId = true;
        await pumpScreen(tester, opdsClient: opdsClient, libraryRepository: libraryRepository);

        await tester.tap(find.byKey(const Key('remote_catalog_entry_book-1')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('remote_catalog_duplicate_dialog')), findsNothing);
        expect(find.byKey(const Key('remote_catalog_checkbox_checked_book-1')), findsOneWidget);
      });
    });

    // 〔審查 review-issue-2.md Important #1 核實後修正做法〕上面的
    // 「引數驗證」測試只證明 importFiles() 被呼叫時傳入了正確的參數，
    // 不證明這些欄位真的正確持久化到資料庫、也不證明下載下來的檔案真的
    // 活過搬移到永久位置這個步驟。原本嘗試在這裡（testWidgets）用真實
    // SqliteLibraryRepository／BookImportServiceImpl 補這項驗證，但
    // 真實 BookImportServiceImpl 對非 content:// 路徑計算指紋時會透過
    // computeBookContentFingerprint() 呼叫 Isolate.run()（見
    // book_content_fingerprint.dart）——這與
    // AutomatedTestWidgetsFlutterBinding 的測試環境有更深層的不相容，
    // 即使把觸發流程整個包進 tester.runAsync()（比照
    // library_screen_test.dart「Markdown 匯出」既有先例）仍會卡在
    // `dart:isolate _RawReceivePort._handleMessage` 直到 10 分鐘逾時
    // ——這個組合（testWidgets + 真實 Isolate.run()）在本專案目前沒有
    // 任何成功先例可循，判斷為環境層級的真實限制，不是可以再調整測試
    // 寫法就解決的問題。改為把這項驗證移到
    // `test/library/book_import_service_test.dart`（plain `test()`，
    // 沒有 testWidgets 的 fake zone 限制，Isolate.run() 可以正常完成）
    // ——見該檔案「遠端書架下載完成後匯入（epic-30 Issue 2）」測試，
    // 直接餵入一個非 content:// 的本機檔案路徑（比照 OPDS 下載佇列實際
    // 產生的檔案型態）驗證欄位持久化與檔案存活。
  });

  testWidgets('英文介面下按鈕與下載佇列訊息正確顯示（含 ICU plural）', (tester) async {
    final opdsClient = FakeOpdsClient(feeds: {
      server.baseUrl: OpdsFeed(
        title: '根目錄',
        entries: [entry1, entry2],
      ),
    });
    final controller = DownloadQueueController(onDuplicateConfirm: (_) async => false);
    await pumpScreen(
      tester,
      opdsClient: opdsClient,
      downloadQueueController: controller,
      locale: const Locale('en'),
    );

    await tester.tap(find.byKey(const Key('remote_catalog_entry_book-1')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('remote_catalog_download_button')));
    await tester.pump();

    expect(
      find.textContaining('Added 1 file to the download queue'),
      findsOneWidget,
    );
  });


}
