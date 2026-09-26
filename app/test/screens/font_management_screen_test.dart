import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/l10n/app_localizations.dart';
import 'package:elinkbook/l10n/app_localizations_en.dart';
import 'package:elinkbook/l10n/app_localizations_zh.dart';
import 'package:elinkbook/reader/app_font.dart';
import 'package:elinkbook/reader/custom_font.dart';
import 'package:elinkbook/reader/downloadable_font_store.dart';
import 'package:elinkbook/screens/font_management_screen.dart';
import '../support/fake_custom_fonts_repository.dart';
import '../support/fake_downloadable_font_store.dart';

void main() {
  late FakeCustomFontsRepository repository;

  setUp(() {
    repository = FakeCustomFontsRepository();
  });

  Future<void> pumpScreen(WidgetTester tester,
      {Locale locale = const Locale('zh', 'TW'),
      DownloadableFontStore? store}) async {
    await tester.pumpWidget(MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: FontManagementScreen(
          repository: repository, downloadableFontStore: store),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('顯示標題與 2 款內建字型（無操作按鈕），已停用的 3 款不顯示（epic-48）',
      (tester) async {
    await pumpScreen(tester);

    expect(find.text('字型管理'), findsOneWidget);
    expect(find.text('思源黑體'), findsOneWidget);
    expect(find.text('思源宋體'), findsOneWidget);
    expect(find.text('原俠正楷'), findsNothing);
    expect(find.text('台灣圓體'), findsNothing);
    expect(find.text('源流明體'), findsNothing);
    expect(find.byKey(const Key('font_management_upload_button')),
        findsOneWidget);
  });

  testWidgets('英文介面下內建字型名稱以英文顯示（epic-48）', (tester) async {
    await pumpScreen(tester, locale: const Locale('en'));

    expect(find.text('Source Han Sans'), findsOneWidget);
    expect(find.text('Source Han Serif'), findsOneWidget);
    expect(find.text('思源黑體'), findsNothing);
    expect(find.text('思源宋體'), findsNothing);
  });

  testWidgets('簡體中文介面下內建字型名稱以簡體顯示（epic-48）', (tester) async {
    await pumpScreen(tester, locale: const Locale('zh', 'CN'));

    expect(find.text('思源黑体'), findsOneWidget);
    expect(find.text('思源宋体'), findsOneWidget);
  });

  testWidgets('顯示已存在的自訂字型，含重新命名與刪除按鈕', (tester) async {
    await repository.insert(const CustomFont(
      displayName: '我的自訂字型',
      familyName: 'MyCustomFamily',
      fontUri: 'content://example/font1',
    ));

    await pumpScreen(tester);

    expect(find.text('我的自訂字型'), findsOneWidget);
    expect(
        find.byKey(const Key('font_management_rename_button_1')),
        findsOneWidget);
    expect(
        find.byKey(const Key('font_management_delete_button_1')),
        findsOneWidget);
  });

  testWidgets('點擊重新命名按鈕，輸入新名稱後清單更新', (tester) async {
    await repository.insert(const CustomFont(
      displayName: '舊名稱',
      familyName: 'RenameFamily',
      fontUri: 'content://example/r',
    ));
    await pumpScreen(tester);

    await tester.tap(find.byKey(const Key('font_management_rename_button_1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('font_management_rename_field')),
        findsOneWidget);
    await tester.enterText(
        find.byKey(const Key('font_management_rename_field')), '新名稱');
    await tester
        .tap(find.byKey(const Key('font_management_rename_confirm')));
    await tester.pumpAndSettle();

    expect(find.text('新名稱'), findsOneWidget);
    expect(find.text('舊名稱'), findsNothing);
  });

  testWidgets('刪除未使用中的字型：確認對話框文案不含使用中提示，確認後清單移除',
      (tester) async {
    await repository.insert(const CustomFont(
      displayName: '未使用字型',
      familyName: 'UnusedFamily',
      fontUri: 'content://example/u',
    ));
    await pumpScreen(tester);

    await tester.tap(find.byKey(const Key('font_management_delete_button_1')));
    await tester.pumpAndSettle();

    expect(find.text('確定要刪除「未使用字型」嗎？'), findsOneWidget);
    await tester.tap(find.byKey(const Key('font_management_delete_confirm')));
    await tester.pumpAndSettle();

    expect(find.text('未使用字型'), findsNothing);
  });

  testWidgets('刪除使用中的字型：確認對話框文案含使用中書籍數量提示', (tester) async {
    await repository.insert(const CustomFont(
      displayName: '使用中字型',
      familyName: 'UsedFamily',
      fontUri: 'content://example/used',
    ));
    repository.usageCounts['UsedFamily'] = 3;
    await pumpScreen(tester);

    await tester.tap(find.byKey(const Key('font_management_delete_button_1')));
    await tester.pumpAndSettle();

    expect(find.text('確定要刪除「使用中字型」嗎？'), findsOneWidget);
    expect(find.text('目前有 3 本書使用此字型，刪除後將自動改用預設字型'),
        findsOneWidget);
  });

  testWidgets('刪除對話框點擊取消，字型不受影響', (tester) async {
    await repository.insert(const CustomFont(
      displayName: '保留字型',
      familyName: 'KeepFamily',
      fontUri: 'content://example/k',
    ));
    await pumpScreen(tester);

    await tester.tap(find.byKey(const Key('font_management_delete_button_1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('font_management_delete_cancel')));
    await tester.pumpAndSettle();

    expect(find.text('保留字型'), findsOneWidget);
  });

  testWidgets('英文介面下標題/區塊標籤/空狀態提示正確以英文渲染', (tester) async {
    final repository = FakeCustomFontsRepository();
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: FontManagementScreen(repository: repository),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Font Management'), findsOneWidget);
    expect(find.text('Built-in Fonts'), findsOneWidget);
    expect(find.text('Custom Fonts'), findsOneWidget);
    expect(find.text('No custom fonts uploaded yet'), findsOneWidget);
  });

  test('resolveUploadOutcome：同一批次內重複 family name 只寫入第一筆，其餘計入已存在',
      () {
    final outcome = resolveUploadOutcome(
      parsedFamilyNames: ['FamilyA', 'FamilyB', 'FamilyA'],
      alreadyExistingFamilyNames: {'FamilyB'},
    );

    expect(outcome.toInsertIndexes, [0]); // 只有索引 0（第一次出現的 FamilyA）要寫入
    expect(outcome.addedCount, 1);
    expect(outcome.skippedCount, 2); // FamilyB（資料庫已存在）+ 第二個 FamilyA（批次內重複）
  });

  test('resolveUploadOutcome：合併訊息文案（有新增有跳過／全部新增／全部跳過）', () {
    final l10n = AppLocalizationsZhTw();
    expect(
      buildUploadResultMessage(l10n: l10n, addedCount: 3, skippedCount: 2),
      '已新增 3 款字型，2 款已存在已跳過',
    );
    expect(buildUploadResultMessage(l10n: l10n, addedCount: 3, skippedCount: 0), '已新增 3 款字型');
    expect(
      buildUploadResultMessage(l10n: l10n, addedCount: 0, skippedCount: 2),
      '2 款字型已存在，已跳過',
    );
  });

  test('buildUploadResultMessage：英文版單複數各自獨立正確變化', () {
    final l10n = AppLocalizationsEn();
    expect(
      buildUploadResultMessage(l10n: l10n, addedCount: 1, skippedCount: 2),
      'Added 1 font, 2 already exist and were skipped',
    );
    expect(
      buildUploadResultMessage(l10n: l10n, addedCount: 3, skippedCount: 1),
      'Added 3 fonts, 1 already exists and was skipped',
    );
    expect(
      buildUploadResultMessage(l10n: l10n, addedCount: 1, skippedCount: 0),
      'Added 1 font',
    );
    expect(
      buildUploadResultMessage(l10n: l10n, addedCount: 0, skippedCount: 1),
      '1 font already exists and was skipped',
    );
  });

  test(
      'resolveUploadOutcome：與內建字型 family name 相同時視為已存在並跳過'
      '（審查發現：custom_fonts 表不含內建字型，見 tmp/epic-14/review-plan-issue-2.md Critical）',
      () {
    final outcome = resolveUploadOutcome(
      parsedFamilyNames: ['SourceHanSansTC', 'MyOwnFamily'],
      // 呼叫端（_pickAndUploadFonts）會把 AppFont.values 的 family name
      // 併入這個集合，此處直接模擬併入後的結果，不重複走訪 AppFont.values。
      alreadyExistingFamilyNames: {'SourceHanSansTC'},
    );

    expect(outcome.toInsertIndexes, [1]); // 只有 MyOwnFamily 要寫入
    expect(outcome.addedCount, 1);
    expect(outcome.skippedCount, 1); // SourceHanSansTC 被判定為已存在（內建字型）而跳過
  });

  group('可下載字型（epic-49）', () {
    late FakeDownloadableFontStore store;

    setUp(() => store = FakeDownloadableFontStore());

    IconButton button(WidgetTester tester, String key) =>
        tester.widget<IconButton>(find.byKey(Key(key)));

    Finder subtitleOf(AppFont font, String text) => find.descendant(
        of: find.byKey(Key('font_management_builtin_${font.name}')),
        matching: find.text(text));

    Future<void> startDownload(WidgetTester tester, AppFont font) async {
      await tester.tap(find.byKey(Key('font_management_download_${font.name}')));
      await tester.pump();
    }

    testWidgets('formatFontFileSize 以 MB 顯示到小數點後一位', (tester) async {
      expect(formatFontFileSize(36034016), '34.4 MB');
      expect(formatFontFileSize(59898316), '57.1 MB');
    });

    testWidgets('沒有注入 store 時，內建字型只顯示名稱，沒有下載按鈕', (tester) async {
      await pumpScreen(tester);

      expect(find.text('思源黑體'), findsOneWidget);
      expect(find.byKey(const Key('font_management_download_sourceHanSans')), findsNothing);
    });

    testWidgets('未下載：標題是字型名稱，副標題是大小與「未下載」，下載按鈕可按', (tester) async {
      await pumpScreen(tester, store: store);

      expect(find.text('思源黑體'), findsOneWidget);
      expect(subtitleOf(AppFont.sourceHanSans, '34.4 MB · 未下載'), findsOneWidget);
      expect(subtitleOf(AppFont.sourceHanSerif, '57.1 MB · 未下載'), findsOneWidget);
      expect(button(tester, 'font_management_download_sourceHanSans').onPressed, isNotNull);
    });

    testWidgets('已下載：副標題是大小與「已下載」，顯示刪除按鈕', (tester) async {
      store.installed.add(AppFont.sourceHanSerif);
      await pumpScreen(tester, store: store);

      expect(subtitleOf(AppFont.sourceHanSerif, '57.1 MB · 已下載'), findsOneWidget);
      expect(find.byKey(const Key('font_management_delete_builtin_sourceHanSerif')), findsOneWidget);
      expect(find.byKey(const Key('font_management_download_sourceHanSerif')), findsNothing);
    });

    testWidgets('下載中：顯示進度與取消；其他列的下載、刪除停用；AppBar 上傳仍可按', (tester) async {
      store.installed.add(AppFont.sourceHanSerif);
      await pumpScreen(tester, store: store);

      await startDownload(tester, AppFont.sourceHanSans);
      store.activeDownload!.progress(42);
      await tester.pump();

      expect(find.text('思源黑體'), findsOneWidget);
      expect(subtitleOf(AppFont.sourceHanSans, '42%'), findsOneWidget);
      expect(
          tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator)).value,
          0.42);
      expect(find.byKey(const Key('font_management_cancel_download_sourceHanSans')), findsOneWidget);
      expect(button(tester, 'font_management_delete_builtin_sourceHanSerif').onPressed, isNull);
      expect(button(tester, 'font_management_upload_button').onPressed, isNotNull);
    });

    testWidgets('下載成功後變成已下載，其他列的按鈕恢復可按', (tester) async {
      await pumpScreen(tester, store: store);

      await startDownload(tester, AppFont.sourceHanSans);
      expect(button(tester, 'font_management_download_sourceHanSerif').onPressed, isNull);
      store.activeDownload!.succeed();
      await tester.pumpAndSettle();

      expect(subtitleOf(AppFont.sourceHanSans, '34.4 MB · 已下載'), findsOneWidget);
      expect(button(tester, 'font_management_download_sourceHanSerif').onPressed, isNotNull);
    });

    testWidgets('按取消會取消下載，store 回報 cancelled 後回到未下載且不顯示錯誤', (tester) async {
      await pumpScreen(tester, store: store);

      await startDownload(tester, AppFont.sourceHanSans);
      await tester.tap(find.byKey(const Key('font_management_cancel_download_sourceHanSans')));
      await tester.pump();
      expect(store.activeDownload!.cancellationToken!.isCancelled, isTrue);

      store.activeDownload!
          .fail(const FontDownloadException(FontDownloadFailure.cancelled));
      await tester.pumpAndSettle();

      expect(subtitleOf(AppFont.sourceHanSans, '34.4 MB · 未下載'), findsOneWidget);
      expect(find.byKey(const Key('font_management_retry_sourceHanSans')), findsNothing);
    });

    testWidgets('下載失敗：標題仍是字型名稱，副標題是大小與錯誤訊息，可以重試', (tester) async {
      await pumpScreen(tester, store: store);

      await startDownload(tester, AppFont.sourceHanSans);
      store.activeDownload!
          .fail(const FontDownloadException(FontDownloadFailure.network));
      await tester.pumpAndSettle();

      expect(find.text('思源黑體'), findsOneWidget);
      expect(subtitleOf(AppFont.sourceHanSans, '34.4 MB · 無法連線，請檢查網路後重試'), findsOneWidget);

      await tester.tap(find.byKey(const Key('font_management_retry_sourceHanSans')));
      await tester.pump();
      expect(store.activeDownload!.font, AppFont.sourceHanSans);
      expect(find.byKey(const Key('font_management_cancel_download_sourceHanSans')), findsOneWidget);
    });

    testWidgets('各種失敗原因顯示對應訊息（HTTP 狀態碼、檔案損毀、無法儲存）', (tester) async {
      await pumpScreen(tester, store: store);
      const cases = {
        FontDownloadException(FontDownloadFailure.httpStatus, statusCode: 503):
            '34.4 MB · 伺服器錯誤（503），請稍後重試',
        FontDownloadException(FontDownloadFailure.integrity): '34.4 MB · 檔案不完整或已損毀，請重試',
        FontDownloadException(FontDownloadFailure.storage): '34.4 MB · 無法儲存檔案，請確認儲存空間是否足夠',
      };
      for (final entry in cases.entries) {
        final retry = find.byKey(const Key('font_management_retry_sourceHanSans'));
        await tester.tap(retry.evaluate().isEmpty
            ? find.byKey(const Key('font_management_download_sourceHanSans'))
            : retry);
        await tester.pump();
        store.activeDownload!.fail(entry.key);
        await tester.pumpAndSettle();
        expect(subtitleOf(AppFont.sourceHanSans, entry.value), findsOneWidget);
      }
    });

    testWidgets('另一款字型下載中時，失敗列的重試停用', (tester) async {
      await pumpScreen(tester, store: store);
      await startDownload(tester, AppFont.sourceHanSans);
      store.activeDownload!
          .fail(const FontDownloadException(FontDownloadFailure.network));
      await tester.pumpAndSettle();

      await startDownload(tester, AppFont.sourceHanSerif);

      expect(button(tester, 'font_management_retry_sourceHanSans').onPressed, isNull);
    });

    testWidgets('刪除確認對話框使用可下載字型專屬內文；取消不刪、確認才刪', (tester) async {
      store.installed.add(AppFont.sourceHanSans);
      await pumpScreen(tester, store: store);

      await tester.tap(find.byKey(const Key('font_management_delete_builtin_sourceHanSans')));
      await tester.pumpAndSettle();
      expect(find.text('確定要刪除「思源黑體」嗎？'), findsOneWidget);
      expect(find.text('刪除後可以隨時重新下載。使用這款字型的書會暫時改用書本或系統字型，重新下載後自動恢復。'),
          findsOneWidget);
      await tester.tap(find.byKey(const Key('font_management_delete_cancel')));
      await tester.pumpAndSettle();
      expect(store.deleted, isEmpty);

      await tester.tap(find.byKey(const Key('font_management_delete_builtin_sourceHanSans')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('font_management_delete_confirm')));
      await tester.pumpAndSettle();

      expect(store.deleted, [AppFont.sourceHanSans]);
      expect(subtitleOf(AppFont.sourceHanSans, '34.4 MB · 未下載'), findsOneWidget);
    });

    testWidgets('離開畫面時取消進行中的下載；之後下載才結束也不拋例外', (tester) async {
      await pumpScreen(tester, store: store);
      await startDownload(tester, AppFont.sourceHanSans);

      await tester.pumpWidget(const SizedBox());
      expect(store.activeDownload!.cancellationToken!.isCancelled, isTrue);

      store.activeDownload!
          .fail(const FontDownloadException(FontDownloadFailure.cancelled));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('已下載清單載入完成前，只顯示大小、沒有操作按鈕，不會誤顯示成「未下載」（程式審查 M-5）',
        (tester) async {
      store.installed.add(AppFont.sourceHanSans);
      store.installedFontsGate = Completer<void>();
      await pumpScreen(tester, store: store);

      expect(subtitleOf(AppFont.sourceHanSans, '34.4 MB'), findsOneWidget);
      expect(find.byKey(const Key('font_management_download_sourceHanSans')), findsNothing);

      store.installedFontsGate!.complete();
      await tester.pumpAndSettle();

      expect(subtitleOf(AppFont.sourceHanSans, '34.4 MB · 已下載'), findsOneWidget);
      expect(button(tester, 'font_management_download_sourceHanSerif').onPressed, isNotNull);
    });

    testWidgets('store 拋出 FontDownloadException 以外的例外時，顯示網路錯誤並可重試（程式審查 I-1）',
        (tester) async {
      await pumpScreen(tester, store: store);

      await startDownload(tester, AppFont.sourceHanSans);
      store.activeDownload!.fail(StateError('unexpected'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(subtitleOf(AppFont.sourceHanSans, '34.4 MB · 無法連線，請檢查網路後重試'), findsOneWidget);
      expect(button(tester, 'font_management_retry_sourceHanSans').onPressed, isNotNull);
    });

    testWidgets('刪除失敗時不拋出未捕捉的例外，畫面依實際檔案狀態顯示（程式審查 M-3）', (tester) async {
      store.installed.add(AppFont.sourceHanSans);
      store.deleteError = const FileSystemException('file in use');
      await pumpScreen(tester, store: store);

      await tester.tap(find.byKey(const Key('font_management_delete_builtin_sourceHanSans')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('font_management_delete_confirm')));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(subtitleOf(AppFont.sourceHanSans, '34.4 MB · 已下載'), findsOneWidget);
    });

    testWidgets('WebView 載得動全部字型時，不顯示隱藏提示（Issue 7）', (tester) async {
      await pumpScreen(tester, store: store);

      expect(find.byKey(const Key('font_management_builtin_unsupported_hint')), findsNothing);
    });

    testWidgets('WebView 太舊、一款都載不動：不列出內建字型，顯示提示（Issue 7）', (tester) async {
      store.supported = [];
      await pumpScreen(tester, store: store);

      expect(find.text('思源黑體'), findsNothing);
      expect(find.text('思源宋體'), findsNothing);
      expect(find.byKey(const Key('font_management_builtin_unsupported_hint')), findsOneWidget);
      expect(
        find.text('這台裝置的系統 WebView 版本太舊，部分內建字型無法使用，已從清單隱藏。更新「Android System WebView」後即可下載。'),
        findsOneWidget,
      );
    });

    testWidgets('只有部分字型載不動：只列出載得動的，並顯示提示（Issue 7）', (tester) async {
      store.supported = [AppFont.sourceHanSerif];
      await pumpScreen(tester, store: store);

      expect(find.text('思源黑體'), findsNothing);
      expect(find.text('思源宋體'), findsOneWidget);
      expect(find.byKey(const Key('font_management_builtin_unsupported_hint')), findsOneWidget);
    });

    testWidgets('英文介面：隱藏提示以英文顯示（Issue 7）', (tester) async {
      store.supported = [];
      await pumpScreen(tester, store: store, locale: const Locale('en'));

      expect(
        find.text("This device's system WebView is too old for some built-in fonts, so they are hidden. Update Android System WebView to download them."),
        findsOneWidget,
      );
    });

    testWidgets('英文介面：字型名稱與狀態以英文顯示', (tester) async {
      await pumpScreen(tester, store: store, locale: const Locale('en'));

      expect(find.text('Source Han Sans'), findsOneWidget);
      expect(subtitleOf(AppFont.sourceHanSans, '34.4 MB · Not downloaded'), findsOneWidget);
    });
  });
}
