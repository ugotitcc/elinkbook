import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/library/sqlite_library_repository.dart';
import 'package:elinkbook/reader/book_reader_prefs.dart';
import 'package:elinkbook/reader/book_reader_prefs_repository.dart';
import 'package:elinkbook/reader/layout_preset.dart';
import 'package:elinkbook/reader/layout_preset_flow.dart';
import 'package:elinkbook/reader/layout_preset_repository.dart';

import '../support/fake_book_reader_prefs_repository.dart';
import '../support/fake_layout_preset_repository.dart';

/// 記錄呼叫順序的假對話框；每個回應都可在測試中替換。
class _FakePrompts implements LayoutPresetPrompts {
  final List<String> log = [];

  Future<String?> Function() onAskName = () async => '新名稱';
  Future<LayoutPreset?> Function(List<LayoutPreset> presets) onPick =
      (presets) async => presets.first;
  Future<bool> Function(String name) onConfirmOverwrite = (_) async => true;
  Future<bool> Function(int count) onConfirmApply = (_) async => true;
  Future<bool> Function(String name) onConfirmDelete = (_) async => true;

  /// 最近一次 confirmDelete 收到的名稱。
  String? lastDeleteName;

  @override
  Future<String?> askName() {
    log.add('askName');
    return onAskName();
  }

  @override
  Future<LayoutPreset?> pickOverwriteTarget(List<LayoutPreset> presets) {
    log.add('pickOverwriteTarget');
    return onPick(presets);
  }

  @override
  Future<bool> confirmOverwrite(String presetName) {
    log.add('confirmOverwrite');
    return onConfirmOverwrite(presetName);
  }

  @override
  Future<bool> confirmApplyToOthers(int bookCount) {
    log.add('confirmApplyToOthers');
    return onConfirmApply(bookCount);
  }

  @override
  Future<bool> confirmDelete(String presetName) {
    log.add('confirmDelete');
    lastDeleteName = presetName;
    return onConfirmDelete(presetName);
  }
}

LayoutPreset _preset(String name, BookReaderPrefs prefs) => LayoutPreset(
      id: null,
      name: name,
      createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(1000),
      prefs: prefs,
    );

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  // ---- 以假 repository 測流程與錯誤注入 ----
  group('LayoutPresetFlow（假 repository）', () {
    late FakeLayoutPresetRepository presetRepo;
    late FakeBookReaderPrefsRepository prefsRepo;
    late _FakePrompts prompts;
    late List<String> events; // 'applied' 與 'notify' 的先後順序
    late List<BookReaderPrefs> applied;
    late LayoutPresetFlow flow;

    setUp(() {
      presetRepo = FakeLayoutPresetRepository();
      prefsRepo = FakeBookReaderPrefsRepository();
      prompts = _FakePrompts();
      events = [];
      applied = [];
      flow = LayoutPresetFlow(
        presetRepository: presetRepo,
        prefsRepository: prefsRepo,
        currentBookId: 'b1',
        prompts: prompts,
        onCurrentBookPrefsApplied: (prefs) {
          applied.add(prefs);
          events.add('applied');
        },
      )..addListener(() => events.add('notify'));
      addTearDown(flow.dispose);
    });

    Future<void> seed(int count) async {
      for (var i = 0; i < count; i++) {
        await presetRepo.insert(_preset('既有$i', BookReaderPrefs(fontSize: 10.0 + i)));
      }
      await flow.load();
      events.clear();
    }

    group('load', () {
      test('載入後 presets 為 repository 內容並通知一次', () async {
        await presetRepo.insert(_preset('A', BookReaderPrefs.empty));

        await flow.load();

        expect(flow.presets.map((p) => p.name), ['A']);
        expect(events, ['notify']);
      });

      test('repository 丟例外時清單不變、不通知、不丟出', () async {
        await seed(1);
        presetRepo.failOn.add('listAll');

        await flow.load();

        expect(flow.presets.map((p) => p.name), ['既有0']);
        expect(events, isEmpty);
      });
    });

    group('saveAsPreset', () {
      test('未滿 3 組：取名後新增，清單含新預設集且已有 id、依插入順序', () async {
        await seed(1);
        prompts.onAskName = () async => '第二組';

        final outcome = await flow.saveAsPreset(const BookReaderPrefs(fontSize: 18));

        expect(outcome, LayoutPresetOutcome.done);
        expect(prompts.log, ['askName']);
        expect(flow.presets.map((p) => p.name), ['既有0', '第二組']);
        expect(flow.presets.last.id, isNotNull);
        expect(flow.presets.last.prefs.fontSize, 18);
        expect(events, ['notify']);
      });

      test('寫入前以 reflowableEpubFields() 過濾（非流式欄位不進預設集）', () async {
        await flow.saveAsPreset(
          const BookReaderPrefs(fontSize: 18, pdfContrast: 30),
        );

        final saved = flow.presets.single.prefs;
        expect(saved.fontSize, 18);
        expect(saved.pdfContrast, isNull);
      });

      test('取名取消 → cancelled，不寫入，仍通知一次', () async {
        prompts.onAskName = () async => null;

        final outcome = await flow.saveAsPreset(BookReaderPrefs.empty);

        expect(outcome, LayoutPresetOutcome.cancelled);
        expect(flow.presets, isEmpty);
        expect(events, ['notify']);
      });

      test('已滿 3 組：順序 = 取名 → 選目標 → 覆蓋確認 → 寫入，覆蓋後清單更新', () async {
        await seed(3);
        prompts.onAskName = () async => '覆蓋後';
        prompts.onPick = (presets) async => presets[1];

        final outcome = await flow.saveAsPreset(const BookReaderPrefs(fontSize: 22));

        expect(outcome, LayoutPresetOutcome.done);
        expect(prompts.log, ['askName', 'pickOverwriteTarget', 'confirmOverwrite']);
        expect(flow.presets, hasLength(3));
        expect(flow.presets[1].name, '覆蓋後');
        expect(flow.presets[1].prefs.fontSize, 22);
      });

      test('釘點 1：是否滿 3 組在 askName 回傳之後才判斷', () async {
        await seed(2);
        prompts.onAskName = () async {
          // 取名對話框開著的期間，資料庫多了一組 → 長度由 2 變 3
          await presetRepo.insert(_preset('中途新增', BookReaderPrefs.empty));
          await flow.load();
          events.clear();
          return '新名稱';
        };

        await flow.saveAsPreset(BookReaderPrefs.empty);

        expect(prompts.log, ['askName', 'pickOverwriteTarget', 'confirmOverwrite']);
        expect(flow.presets, hasLength(3));
      });

      test('已滿 3 組：選目標取消 → cancelled，不寫入', () async {
        await seed(3);
        prompts.onPick = (_) async => null;

        final outcome = await flow.saveAsPreset(BookReaderPrefs.empty);

        expect(outcome, LayoutPresetOutcome.cancelled);
        expect(prompts.log, ['askName', 'pickOverwriteTarget']);
        expect(flow.presets.map((p) => p.name), ['既有0', '既有1', '既有2']);
      });

      test('已滿 3 組：覆蓋確認取消 → cancelled，不寫入', () async {
        await seed(3);
        prompts.onConfirmOverwrite = (_) async => false;

        final outcome = await flow.saveAsPreset(BookReaderPrefs.empty);

        expect(outcome, LayoutPresetOutcome.cancelled);
        expect(flow.presets.map((p) => p.name), ['既有0', '既有1', '既有2']);
      });

      test('寫入丟例外 → failed，清單不變，仍通知一次', () async {
        await seed(1);
        presetRepo.failOn.add('insert');

        final outcome = await flow.saveAsPreset(BookReaderPrefs.empty);

        expect(outcome, LayoutPresetOutcome.failed);
        expect(flow.presets, hasLength(1));
        expect(events, ['notify']);
      });

      test('釘點 2：askName／pickOverwriteTarget／confirmOverwrite 丟例外 → failed', () async {
        prompts.onAskName = () async => throw StateError('askName boom');
        expect(await flow.saveAsPreset(BookReaderPrefs.empty), LayoutPresetOutcome.failed);

        await seed(3);
        prompts.onAskName = () async => 'x';
        prompts.onPick = (_) async => throw StateError('pick boom');
        expect(await flow.saveAsPreset(BookReaderPrefs.empty), LayoutPresetOutcome.failed);

        prompts.onPick = (presets) async => presets.first;
        prompts.onConfirmOverwrite = (_) async => throw StateError('confirm boom');
        expect(await flow.saveAsPreset(BookReaderPrefs.empty), LayoutPresetOutcome.failed);
      });

      test('覆蓋目標 id 為 null（未持久化的暫存物件）→ failed，repository 沒有任何寫入', () async {
        await seed(3);
        prompts.onPick = (_) async => _preset('暫存', BookReaderPrefs.empty); // id: null

        final outcome = await flow.saveAsPreset(const BookReaderPrefs(fontSize: 99));

        expect(outcome, LayoutPresetOutcome.failed);
        expect((await presetRepo.listAll()).map((p) => p.prefs.fontSize), [10.0, 11.0, 12.0]);
      });
    });

    group('applyPreset', () {
      final preset = _preset('P', const BookReaderPrefs(fontSize: 20));

      test('目標恰為 [目前書籍]：不跳確認，單筆 save，呼叫回呼且先於通知', () async {
        final outcome = await flow.applyPreset(preset, targetBookIds: ['b1']);

        expect(outcome, LayoutPresetOutcome.done);
        expect(prompts.log, isEmpty);
        expect(prefsRepo.calls, ['save']);
        expect((await prefsRepo.load('b1')).fontSize, 20);
        expect(events, ['applied', 'notify']); // 先回呼、後通知（C-1）
        expect(applied.single.fontSize, 20);
      });

      test('目標只有 1 本但不是目前書籍：要確認，寫入後不呼叫回呼', () async {
        final outcome = await flow.applyPreset(preset, targetBookIds: ['b2']);

        expect(outcome, LayoutPresetOutcome.done);
        expect(prompts.log, ['confirmApplyToOthers']);
        expect(prefsRepo.calls, ['save']);
        expect(applied, isEmpty);
        expect(events, ['notify']);
      });

      test('目標有多本且含目前書籍：要確認、批次 saveMultiple、呼叫回呼', () async {
        int? askedCount;
        prompts.onConfirmApply = (count) async {
          askedCount = count;
          return true;
        };

        await flow.applyPreset(preset, targetBookIds: ['b1', 'b2', 'b3']);

        expect(askedCount, 3);
        expect(prefsRepo.calls, ['saveMultiple']);
        expect((await prefsRepo.load('b3')).fontSize, 20);
        expect(applied, hasLength(1));
      });

      test('確認取消 → cancelled，不寫入，仍通知一次', () async {
        prompts.onConfirmApply = (_) async => false;

        final outcome = await flow.applyPreset(preset, targetBookIds: ['b2', 'b3']);

        expect(outcome, LayoutPresetOutcome.cancelled);
        expect(prefsRepo.calls, isEmpty);
        expect(events, ['notify']);
      });

      test('targetBookIds 為空 → cancelled，不寫入、不確認', () async {
        final outcome = await flow.applyPreset(preset, targetBookIds: []);

        expect(outcome, LayoutPresetOutcome.cancelled);
        expect(prompts.log, isEmpty);
        expect(prefsRepo.calls, isEmpty);
      });

      test('寫入丟例外 → failed，不呼叫回呼，仍通知一次', () async {
        prefsRepo.failOn.add('save');

        final outcome = await flow.applyPreset(preset, targetBookIds: ['b1']);

        expect(outcome, LayoutPresetOutcome.failed);
        expect(applied, isEmpty);
        expect(events, ['notify']);
      });

      test('釘點 3：onCurrentBookPrefsApplied 丟例外 → failed', () async {
        final throwingFlow = LayoutPresetFlow(
          presetRepository: presetRepo,
          prefsRepository: prefsRepo,
          currentBookId: 'b1',
          prompts: prompts,
          onCurrentBookPrefsApplied: (_) => throw StateError('callback boom'),
        );
        addTearDown(throwingFlow.dispose);

        final outcome = await throwingFlow.applyPreset(preset, targetBookIds: ['b1']);

        expect(outcome, LayoutPresetOutcome.failed);
      });

      test('釘點 2：confirmApplyToOthers 丟例外 → failed', () async {
        prompts.onConfirmApply = (_) async => throw StateError('boom');

        final outcome = await flow.applyPreset(preset, targetBookIds: ['b2']);

        expect(outcome, LayoutPresetOutcome.failed);
      });
    });

    group('applyFromBook', () {
      test('成功：以 reflowableEpubFields() 過濾來源設定後套用到目前書籍', () async {
        await prefsRepo.save(
          'src',
          const BookReaderPrefs(fontSize: 19, pdfContrast: 40),
        );
        prefsRepo.calls.clear();

        final outcome = await flow.applyFromBook('src', targetBookIds: ['b1']);

        expect(outcome, LayoutPresetOutcome.done);
        final target = await prefsRepo.load('b1');
        expect(target.fontSize, 19);
        expect(target.pdfContrast, isNull);
        expect(applied.single.pdfContrast, isNull);
        expect(events, ['applied', 'notify']);
      });

      test('讀取來源書籍丟例外 → failed 且只回報一次，不往下寫', () async {
        prefsRepo.failOn.add('load');

        final outcome = await flow.applyFromBook('src', targetBookIds: ['b1']);

        expect(outcome, LayoutPresetOutcome.failed);
        expect(prefsRepo.calls, ['load']);
        expect(events, ['notify']); // 只通知一次，不因兩層保護而重複
      });

      test('釘點 4：targetBookIds 為空 → cancelled，來源書籍的 load 沒有被呼叫', () async {
        final outcome = await flow.applyFromBook('src', targetBookIds: []);

        expect(outcome, LayoutPresetOutcome.cancelled);
        expect(prefsRepo.calls, isEmpty);
      });

      test('I-3：load 完成後 flow 已被 dispose → cancelled，不寫入', () async {
        // 讀取來源書籍設定的期間，畫面被關閉（flow 被 dispose）
        late final LayoutPresetFlow disposable;
        final fakePrefs = _DisposeOnLoadPrefsRepository(
          onLoad: () => disposable.dispose(),
        );
        disposable = LayoutPresetFlow(
          presetRepository: presetRepo,
          prefsRepository: fakePrefs,
          currentBookId: 'b1',
          prompts: prompts,
          onCurrentBookPrefsApplied: applied.add,
        );

        final outcome = await disposable.applyFromBook('src', targetBookIds: ['b1']);

        expect(outcome, LayoutPresetOutcome.cancelled);
        expect(applied, isEmpty);
        expect(fakePrefs.calls, ['load']); // 讀取之後沒有任何寫入
      });
    });

    group('deletePreset', () {
      test('確認後刪除：清單不含該筆、其餘保留，並通知', () async {
        await seed(2);
        final id = flow.presets.first.id!;

        final outcome = await flow.deletePreset(id);

        expect(outcome, LayoutPresetOutcome.done);
        expect(prompts.lastDeleteName, '既有0');
        expect(flow.presets.map((p) => p.name), ['既有1']);
        expect(events, ['notify']);
      });

      test('確認取消 → cancelled，不刪除（取代 reader_screen_test 的同名案例）', () async {
        await seed(1);
        prompts.onConfirmDelete = (_) async => false;

        final outcome = await flow.deletePreset(flow.presets.single.id!);

        expect(outcome, LayoutPresetOutcome.cancelled);
        expect(flow.presets, hasLength(1));
        expect(await presetRepo.listAll(), hasLength(1));
      });

      test('刪除丟例外 → failed，清單不變', () async {
        await seed(1);
        presetRepo.failOn.add('delete');

        final outcome = await flow.deletePreset(flow.presets.single.id!);

        expect(outcome, LayoutPresetOutcome.failed);
        expect(flow.presets, hasLength(1));
      });

      test('釘點 5：id 不存在 → 仍以空字串名稱呼叫 confirmDelete', () async {
        final outcome = await flow.deletePreset(999);

        expect(outcome, LayoutPresetOutcome.done);
        expect(prompts.log, ['confirmDelete']);
        expect(prompts.lastDeleteName, '');
      });

      test('釘點 2：confirmDelete 丟例外 → 例外往上拋（不在 try 內）', () async {
        prompts.onConfirmDelete = (_) async => throw StateError('boom');

        await expectLater(flow.deletePreset(1), throwsA(isA<StateError>()));
      });
    });

    group('dispose', () {
      test('dispose 後才完成的寫入：不通知、不呼叫 onCurrentBookPrefsApplied', () async {
        final preset = _preset('P', const BookReaderPrefs(fontSize: 20));
        prompts.onConfirmApply = (_) async {
          flow.dispose(); // 確認對話框開著的期間畫面被關閉
          return true;
        };

        final outcome = await flow.applyPreset(preset, targetBookIds: ['b2']);

        expect(outcome, LayoutPresetOutcome.done);
        expect(applied, isEmpty);
        expect(events, isEmpty);
      });

      test('連續呼叫兩次 dispose 不拋錯', () {
        flow.dispose();
        expect(flow.dispose, returnsNormally);
      });
    });
  });

  // ---- 以真實 sqlite 測持久化語意（取代舊的預設集操作函式測試）----
  group('LayoutPresetFlow（真實 sqlite）', () {
    late SqliteLibraryRepository libraryRepository;
    late LayoutPresetRepository presetRepo;
    late BookReaderPrefsRepository prefsRepo;
    late _FakePrompts prompts;
    late LayoutPresetFlow flow;

    setUp(() async {
      libraryRepository =
          await SqliteLibraryRepository.open(inMemoryDatabasePath);
      presetRepo = LayoutPresetRepository(libraryRepository.database);
      prefsRepo = BookReaderPrefsRepository(libraryRepository.database);
      for (final id in ['b1', 'b2', 'b3']) {
        await libraryRepository.insertBook(Book(
          id: id,
          title: '書名$id',
          format: BookFileFormat.epub,
          filePath: 'content://example/$id',
          source: BookSource.local,
          createTime: DateTime.fromMillisecondsSinceEpoch(1000),
          lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
        ));
      }
      prompts = _FakePrompts();
      flow = LayoutPresetFlow(
        presetRepository: presetRepo,
        prefsRepository: prefsRepo,
        currentBookId: 'b1',
        prompts: prompts,
        onCurrentBookPrefsApplied: (_) {},
      );
    });

    tearDown(() async {
      flow.dispose();
      await libraryRepository.close();
    });

    test('新增：清單包含新預設集，且已由資料庫指派 id', () async {
      prompts.onAskName = () async => '臥室夜讀直排';

      await flow.saveAsPreset(const BookReaderPrefs(fontSize: 18));

      expect(flow.presets, hasLength(1));
      expect(flow.presets.single.id, isNotNull);
      expect(flow.presets.single.name, '臥室夜讀直排');
      expect(flow.presets.single.prefs.fontSize, 18);
    });

    test('覆蓋後 id／createdAt 不變，name／prefs 更新為新值', () async {
      for (var i = 0; i < 3; i++) {
        await presetRepo.insert(_preset('舊$i', BookReaderPrefs(fontSize: 16.0 + i)));
      }
      await flow.load();
      final target = flow.presets[1];
      prompts.onAskName = () async => '新名稱';
      prompts.onPick = (presets) async => presets[1];

      await flow.saveAsPreset(const BookReaderPrefs(fontSize: 20));

      final updated = flow.presets[1];
      expect(flow.presets, hasLength(3));
      expect(updated.id, target.id);
      expect(updated.name, '新名稱');
      expect(updated.prefs.fontSize, 20);
      expect(updated.createdAt, target.createdAt);
    });

    test('刪除後清單不含該筆，其餘保留', () async {
      await presetRepo.insert(_preset('保留組', BookReaderPrefs.empty));
      await presetRepo.insert(_preset('刪除組', BookReaderPrefs.empty));
      await flow.load();
      final toDelete = flow.presets.firstWhere((p) => p.name == '刪除組');

      await flow.deletePreset(toDelete.id!);

      expect(flow.presets.map((p) => p.name), ['保留組']);
    });

    test('套用到單一書籍走 save；多本走 saveMultiple，皆正確寫入', () async {
      final preset = _preset('P', const BookReaderPrefs(fontSize: 22));

      await flow.applyPreset(preset, targetBookIds: ['b1']);
      expect((await prefsRepo.load('b1')).fontSize, 22);
      expect((await prefsRepo.load('b2')).fontSize, isNull);

      await flow.applyPreset(preset, targetBookIds: ['b1', 'b2', 'b3']);
      expect((await prefsRepo.load('b2')).fontSize, 22);
      expect((await prefsRepo.load('b3')).fontSize, 22);
    });

    test('空清單不執行寫入且安全返回', () async {
      final outcome = await flow.applyPreset(
        _preset('P', const BookReaderPrefs(fontSize: 20)),
        targetBookIds: [],
      );

      expect(outcome, LayoutPresetOutcome.cancelled);
      expect((await prefsRepo.load('b1')).fontSize, isNull);
    });
  });
}

/// load() 被呼叫時觸發 [onLoad]（用來模擬「讀取期間畫面被關閉」）。
class _DisposeOnLoadPrefsRepository extends FakeBookReaderPrefsRepository {
  _DisposeOnLoadPrefsRepository({required this.onLoad});
  final void Function() onLoad;

  @override
  Future<BookReaderPrefs> load(String bookId) async {
    await super.load(bookId); // 記錄呼叫
    onLoad();
    return const BookReaderPrefs(fontSize: 19);
  }
}
