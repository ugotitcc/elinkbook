// FTS5 可用性探針（epic-66 Issue 1 Task 10，過關條件 6）。
//
// 確認 Windows 桌面的 sqlite（sqflite_common_ffi）建置含 FTS5 模組，
// 且中文 MATCH 查詢可命中——全文檢索子系統（epic-10）的硬性前提。
//
// 執行：flutter test integration_test/windows_spike/fts5_test.dart -d windows

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('sqflite FFI 建置含 FTS5，中文 MATCH 查詢命中一列', (tester) async {
    // 獨立整合測試不經過 lib/main.dart 的 main()（比照
    // integration_test/flutter_test_config.dart 的說明），自行初始化。
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    addTearDown(() => db.close());

    await db.execute('CREATE VIRTUAL TABLE t USING fts5(body)');
    await db.insert('t', {'body': '直排繁體中文排版'});

    final rows = await db.rawQuery(
      'SELECT * FROM t WHERE t MATCH ?',
      ['直排繁體中文排版'],
    );

    expect(rows, hasLength(1), reason: 'FTS5 MATCH 應命中唯一一列');
    expect((rows.first['body'] as String), contains('直排'));
  });
}
