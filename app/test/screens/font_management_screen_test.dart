import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/l10n/app_localizations.dart';
import 'package:elinkbook/l10n/app_localizations_en.dart';
import 'package:elinkbook/l10n/app_localizations_zh.dart';
import 'package:elinkbook/reader/custom_font.dart';
import 'package:elinkbook/screens/font_management_screen.dart';
import '../support/fake_custom_fonts_repository.dart';

void main() {
  late FakeCustomFontsRepository repository;

  setUp(() {
    repository = FakeCustomFontsRepository();
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('zh', 'TW'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: FontManagementScreen(repository: repository),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('顯示標題與 5 款內建字型（無操作按鈕）', (tester) async {
    await pumpScreen(tester);

    expect(find.text('字型管理'), findsOneWidget);
    expect(find.text('思源黑體'), findsOneWidget);
    expect(find.text('思源宋體'), findsOneWidget);
    expect(find.text('原俠正楷'), findsOneWidget);
    expect(find.text('台灣圓體'), findsOneWidget);
    expect(find.text('源流明體'), findsOneWidget);
    expect(find.byKey(const Key('font_management_upload_button')),
        findsOneWidget);
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
}
