// metadata_comparison 單元測試（epic-66 Issue 12 Task 4）。

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/library/metadata_comparison.dart';

void main() {
  group('diffBookMetadata', () {
    test('完全相同 → 空清單', () {
      final m1 = {
        'title': '三體',
        'author': '劉慈欣',
        'identifier': 'urn:isbn:9787536692930',
        'isFixedLayout': false,
        'coverBytes': Uint8List.fromList([1, 2, 3]),
      };
      final m2 = {
        'title': '三體',
        'author': '劉慈欣',
        'identifier': 'urn:isbn:9787536692930',
        'isFixedLayout': false,
        'coverBytes': Uint8List.fromList([1, 2, 3]),
      };

      expect(diffBookMetadata(m1, m2), isEmpty);
    });

    test('title 不同 → [title]', () {
      final m1 = {'title': '書名 A'};
      final m2 = {'title': '書名 B'};

      expect(diffBookMetadata(m1, m2), ['title']);
    });

    test('title 只差前後空白 → 空清單', () {
      final m1 = {'title': ' 書名 A  '};
      final m2 = {'title': '書名 A'};

      expect(diffBookMetadata(m1, m2), isEmpty);
    });

    test('author 一邊 null 一邊空字串 → 空清單', () {
      final m1 = {'author': null};
      final m2 = {'author': '   '};

      expect(diffBookMetadata(m1, m2), isEmpty);
    });

    test('identifier 不同 → [identifier]', () {
      final m1 = {'identifier': 'id-1'};
      final m2 = {'identifier': 'id-2'};

      expect(diffBookMetadata(m1, m2), ['identifier']);
    });

    test('isFixedLayout 不同 → [isFixedLayout]', () {
      final m1 = {'isFixedLayout': false};
      final m2 = {'isFixedLayout': true};

      expect(diffBookMetadata(m1, m2), ['isFixedLayout']);
    });

    test('一邊有封面一邊沒有 → [cover]', () {
      final m1 = {'coverBytes': Uint8List.fromList([1, 2, 3])};
      final m2 = {'coverBytes': null};

      expect(diffBookMetadata(m1, m2), ['cover']);
    });

    test('兩邊封面位元組不同但都有 → 空清單', () {
      final m1 = {'coverBytes': Uint8List.fromList([1, 2, 3])};
      final m2 = {'coverBytes': Uint8List.fromList([4, 5, 6, 7])};

      expect(diffBookMetadata(m1, m2), isEmpty);
    });

    test('一邊空位元組陣列、一邊 null → 空清單', () {
      final m1 = {'coverBytes': Uint8List(0)};
      final m2 = {'coverBytes': null};

      expect(diffBookMetadata(m1, m2), isEmpty);
    });

    test('一邊空位元組陣列、一邊有封面 → [cover]', () {
      final m1 = {'coverBytes': Uint8List(0)};
      final m2 = {'coverBytes': Uint8List.fromList([1, 2, 3])};

      expect(diffBookMetadata(m1, m2), ['cover']);
    });
  });
}
