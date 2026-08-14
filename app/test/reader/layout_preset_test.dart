import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/book_reader_prefs.dart';
import 'package:elinkbook/reader/layout_preset.dart';

void main() {
  test('LayoutPreset 建構後各欄位正確保存', () {
    final createdAt = DateTime.fromMillisecondsSinceEpoch(1000);
    final updatedAt = DateTime.fromMillisecondsSinceEpoch(2000);
    const prefs = BookReaderPrefs(fontSize: 18);
    final preset = LayoutPreset(
      id: 1,
      name: '臥室夜讀直排',
      createdAt: createdAt,
      updatedAt: updatedAt,
      prefs: prefs,
    );

    expect(preset.id, 1);
    expect(preset.name, '臥室夜讀直排');
    expect(preset.createdAt, createdAt);
    expect(preset.updatedAt, updatedAt);
    expect(preset.prefs, prefs);
  });

  test('LayoutPreset 的 id 可為 null（尚未存入資料庫的暫存物件）', () {
    final preset = LayoutPreset(
      id: null,
      name: '暫存',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      prefs: BookReaderPrefs.empty,
    );
    expect(preset.id, isNull);
  });

  group('validateLayoutPresetName', () {
    test('空字串回傳 null（拒絕）', () {
      expect(validateLayoutPresetName(''), isNull);
    });

    test('純空白字串回傳 null（拒絕）', () {
      expect(validateLayoutPresetName('   '), isNull);
    });

    test('一般名稱回傳已 trim 的字串', () {
      expect(validateLayoutPresetName('  臥室夜讀  '), '臥室夜讀');
    });

    test('超過 20 字元時截斷為 20 字元', () {
      final tooLong = 'a' * 25;
      final result = validateLayoutPresetName(tooLong);
      expect(result, hasLength(20));
      expect(result, 'a' * 20);
    });

    test('恰好 20 字元時原樣保留，不截斷', () {
      final exact = 'a' * 20;
      expect(validateLayoutPresetName(exact), exact);
    });
  });
}
