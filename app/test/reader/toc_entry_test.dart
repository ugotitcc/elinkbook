import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/book_toc_item.dart';
import 'package:elinkbook/reader/toc_entry.dart';

void main() {
  group('TocEntry.fromWire', () {
    test('解析 tocId（含第一個目錄項的 id 為 0，不得被當成缺席）', () {
      final entry = TocEntry.fromWire({
        'title': '第一章',
        'locatorJson': '',
        'progression': null,
        'tocId': 0,
        'children': <Object?>[
          {'title': '第一節', 'locatorJson': '', 'tocId': 1, 'children': <Object?>[]},
        ],
      });
      expect(entry.tocId, 0);
      expect(entry.children.single.tocId, 1);
    });

    test('缺 tocId 欄位時為 null（向下相容舊資料）', () {
      final entry = TocEntry.fromWire({
        'title': '第一章',
        'locatorJson': 'l1',
        'children': <Object?>[],
      });
      expect(entry.tocId, isNull);
    });

    test('解析單層節點（無子項）', () {
      final entry = TocEntry.fromWire({
        'title': '第一章',
        'locatorJson': '{"href":"/chapter1.xhtml"}',
        'progression': 0.1,
        'children': <Object?>[],
      });

      expect(entry.title, '第一章');
      expect(entry.locatorJson, '{"href":"/chapter1.xhtml"}');
      expect(entry.progression, 0.1);
      expect(entry.children, isEmpty);
    });

    test('遞迴解析巢狀子項', () {
      final entry = TocEntry.fromWire({
        'title': '第二章',
        'locatorJson': '{"href":"/chapter2.xhtml"}',
        'progression': 0.3,
        'children': <Object?>[
          {
            'title': '第一節',
            'locatorJson': '{"href":"/chapter2.xhtml#s1"}',
            'progression': 0.35,
            'children': <Object?>[],
          },
        ],
      });

      expect(entry.children, hasLength(1));
      expect(entry.children.single.title, '第一節');
      expect(entry.children.single.progression, 0.35);
    });

    test('progression 為 null（原生端查無對應位置）時保留 null', () {
      final entry = TocEntry.fromWire({
        'title': '未知章節',
        'locatorJson': '{}',
        'progression': null,
        'children': <Object?>[],
      });

      expect(entry.progression, isNull);
    });

    test('title／locatorJson 缺失時採用空字串防呆，不拋出例外', () {
      final entry = TocEntry.fromWire({'children': <Object?>[]});

      expect(entry.title, '');
      expect(entry.locatorJson, '');
    });
  });

  group('BookTocItem 介面（Issue 5）', () {
    test('stableId 回傳 locatorJson 本身', () {
      const entry = TocEntry(title: '第一章', locatorJson: 'l1', progression: 0.0);
      expect(entry.stableId, 'l1');
    });

    test('TocEntry 是 BookTocItem', () {
      const BookTocItem entry =
          TocEntry(title: '第一章', locatorJson: 'l1', progression: 0.0);
      expect(entry, isA<BookTocItem>());
    });
  });
}
