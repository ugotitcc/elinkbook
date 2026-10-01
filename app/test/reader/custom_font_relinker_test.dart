import 'dart:io';

import 'package:elinkbook/library/library_repository.dart'
    show kBookMetadataChannel;
import 'package:elinkbook/reader/custom_font.dart';
import 'package:elinkbook/reader/custom_font_relinker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_custom_fonts_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // 真實字型檔（家族名稱為 KingHwa_OldSong）
  final sampleFontBytes = File('test/fixtures/sample.ttf').readAsBytesSync();
  const oldUri = 'content://old/font';
  const newUri = 'content://new/font';

  late FakeCustomFontsRepository repository;
  late List<String> persistedUris;
  late CustomFont font;

  /// 以假授權函式建立 relinker；[persistResult] 為授權回傳值，
  /// [persistError] 非 null 時授權函式拋出它。
  CustomFontRelinker buildRelinker({
    bool persistResult = true,
    Object? persistError,
  }) {
    return CustomFontRelinker(
      repository: repository,
      persistAccess: (uri) async {
        persistedUris.add(uri);
        if (persistError != null) throw persistError;
        return persistResult;
      },
    );
  }

  PickedFontFile sameFamily() =>
      (uri: newUri, name: 'KingHwa.ttf', bytes: sampleFontBytes);

  /// 只有 3 個位元組，解析不出家族名稱，退回檔名「OtherFamily」。
  PickedFontFile otherFamily() => (
        uri: newUri,
        name: 'OtherFamily.ttf',
        bytes: sampleFontBytes.sublist(0, 3),
      );

  Future<String> storedUri() async =>
      (await repository.listAll()).single.fontUri;

  setUp(() async {
    repository = FakeCustomFontsRepository();
    persistedUris = [];
    final id = await repository.insert(const CustomFont(
      displayName: '舊字型',
      familyName: 'KingHwa_OldSong',
      fontUri: oldUri,
    ));
    font = (await repository.listAll()).single;
    expect(font.id, id);
  });

  test('同家族：回傳 success，URI 更新、顯示名稱與家族名稱不動，並持久化新 URI 的授權', () async {
    final result = await buildRelinker().relink(font, sameFamily());

    expect(result, isA<FontRelinkSuccess>());
    final stored = (await repository.listAll()).single;
    expect(stored.fontUri, newUri);
    expect(stored.displayName, '舊字型');
    expect(stored.familyName, 'KingHwa_OldSong');
    expect(persistedUris, [newUri]);
  });

  test('解析失敗退回檔名，檔名剛好等於原家族名稱時視為同家族（與上傳規則一致）', () async {
    final renamed = await repository.insert(const CustomFont(
      displayName: '另一個',
      familyName: 'OtherFamily',
      fontUri: 'content://old/other',
    ));
    final target = (await repository.listAll())
        .firstWhere((f) => f.id == renamed);

    final result = await buildRelinker().relink(target, otherFamily());

    expect(result, isA<FontRelinkSuccess>());
  });

  test('家族不同：回傳 familyMismatch，不持久化授權、不改記錄（Review Focus 1）', () async {
    final result = await buildRelinker().relink(font, otherFamily());

    expect(result, isA<FontRelinkFamilyMismatch>());
    expect(persistedUris, isEmpty);
    expect(await storedUri(), oldUri);
  });

  test('授權回傳 false（提供者不核發）：不中止，仍更新 URI（ADR 0021，Review Focus 4）', () async {
    final result =
        await buildRelinker(persistResult: false).relink(font, sameFamily());

    expect(result, isA<FontRelinkSuccess>());
    expect(await storedUri(), newUri);
  });

  test('授權函式拋出非預期例外：回傳 failed、不改記錄，例外不穿出（Review Focus 4）', () async {
    final result = await buildRelinker(persistError: StateError('爆掉'))
        .relink(font, sameFamily());

    expect(result, isA<FontRelinkFailed>());
    expect(await storedUri(), oldUri);
  });

  test('updateUri 寫入失敗：回傳 failed，記錄不變', () async {
    repository.updateUriError = StateError('disk full');

    final result = await buildRelinker().relink(font, sameFamily());

    expect(result, isA<FontRelinkFailed>());
    repository.updateUriError = null;
    expect(await storedUri(), oldUri);
  });

  test('未注入 persistAccess（正式環境的接線）：預設走 persistReadAccess，向原生端要求新 URI 的授權', () async {
    final calls = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(kBookMetadataChannel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(
        () => messenger.setMockMethodCallHandler(kBookMetadataChannel, null));

    final result = await CustomFontRelinker(repository: repository)
        .relink(font, sameFamily());

    expect(result, isA<FontRelinkSuccess>());
    expect(calls.single.method, 'takePersistableUriPermission');
    expect((calls.single.arguments as Map)['uri'], newUri);
  });

  test('字型沒有 id（尚未寫入資料庫）：回傳 failed，不呼叫授權', () async {
    const unsaved = CustomFont(
      displayName: '未儲存',
      familyName: 'KingHwa_OldSong',
      fontUri: oldUri,
    );

    final result = await buildRelinker().relink(unsaved, sameFamily());

    expect(result, isA<FontRelinkFailed>());
    expect(persistedUris, isEmpty);
  });
}
