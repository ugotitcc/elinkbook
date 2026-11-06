import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/reader_key_command.dart';

void main() {
  group('readerKeyCommandFor', () {
    group('橫排閱讀模式 (verticalWriting: false)', () {
      const bool vertical = false;

      test('上一頁：←、↑、PageUp、Shift+Space', () {
        expect(
          readerKeyCommandFor(
            LogicalKeyboardKey.arrowLeft,
            verticalWriting: vertical,
          ),
          ReaderKeyCommand.previousPage,
        );
        expect(
          readerKeyCommandFor(
            LogicalKeyboardKey.arrowUp,
            verticalWriting: vertical,
          ),
          ReaderKeyCommand.previousPage,
        );
        expect(
          readerKeyCommandFor(
            LogicalKeyboardKey.pageUp,
            verticalWriting: vertical,
          ),
          ReaderKeyCommand.previousPage,
        );
        expect(
          readerKeyCommandFor(
            LogicalKeyboardKey.space,
            shift: true,
            verticalWriting: vertical,
          ),
          ReaderKeyCommand.previousPage,
        );
      });

      test('下一頁：→、↓、PageDown、Space', () {
        expect(
          readerKeyCommandFor(
            LogicalKeyboardKey.arrowRight,
            verticalWriting: vertical,
          ),
          ReaderKeyCommand.nextPage,
        );
        expect(
          readerKeyCommandFor(
            LogicalKeyboardKey.arrowDown,
            verticalWriting: vertical,
          ),
          ReaderKeyCommand.nextPage,
        );
        expect(
          readerKeyCommandFor(
            LogicalKeyboardKey.pageDown,
            verticalWriting: vertical,
          ),
          ReaderKeyCommand.nextPage,
        );
        expect(
          readerKeyCommandFor(
            LogicalKeyboardKey.space,
            shift: false,
            verticalWriting: vertical,
          ),
          ReaderKeyCommand.nextPage,
        );
      });

      test('首頁與末頁：Home 與 End', () {
        expect(
          readerKeyCommandFor(
            LogicalKeyboardKey.home,
            verticalWriting: vertical,
          ),
          ReaderKeyCommand.firstPage,
        );
        expect(
          readerKeyCommandFor(
            LogicalKeyboardKey.end,
            verticalWriting: vertical,
          ),
          ReaderKeyCommand.lastPage,
        );
      });
    });

    group('直排閱讀模式 (verticalWriting: true)', () {
      const bool vertical = true;

      test('←／→ 左右鏡像：← 為下一頁、→ 為上一頁', () {
        expect(
          readerKeyCommandFor(
            LogicalKeyboardKey.arrowLeft,
            verticalWriting: vertical,
          ),
          ReaderKeyCommand.nextPage,
        );
        expect(
          readerKeyCommandFor(
            LogicalKeyboardKey.arrowRight,
            verticalWriting: vertical,
          ),
          ReaderKeyCommand.previousPage,
        );
      });

      test('直排中 ↑／↓／PageUp／PageDown／Space 保持原樣不受影響', () {
        expect(
          readerKeyCommandFor(
            LogicalKeyboardKey.arrowUp,
            verticalWriting: vertical,
          ),
          ReaderKeyCommand.previousPage,
        );
        expect(
          readerKeyCommandFor(
            LogicalKeyboardKey.pageUp,
            verticalWriting: vertical,
          ),
          ReaderKeyCommand.previousPage,
        );
        expect(
          readerKeyCommandFor(
            LogicalKeyboardKey.arrowDown,
            verticalWriting: vertical,
          ),
          ReaderKeyCommand.nextPage,
        );
        expect(
          readerKeyCommandFor(
            LogicalKeyboardKey.pageDown,
            verticalWriting: vertical,
          ),
          ReaderKeyCommand.nextPage,
        );
        expect(
          readerKeyCommandFor(
            LogicalKeyboardKey.space,
            verticalWriting: vertical,
          ),
          ReaderKeyCommand.nextPage,
        );
        expect(
          readerKeyCommandFor(
            LogicalKeyboardKey.space,
            shift: true,
            verticalWriting: vertical,
          ),
          ReaderKeyCommand.previousPage,
        );
      });

      test('直排中 Home 與 End 保持首頁與末頁', () {
        expect(
          readerKeyCommandFor(
            LogicalKeyboardKey.home,
            verticalWriting: vertical,
          ),
          ReaderKeyCommand.firstPage,
        );
        expect(
          readerKeyCommandFor(
            LogicalKeyboardKey.end,
            verticalWriting: vertical,
          ),
          ReaderKeyCommand.lastPage,
        );
      });
    });

    group('書內搜尋 (Ctrl+F)', () {
      test('純 Ctrl+F 為 openSearch', () {
        expect(
          readerKeyCommandFor(
            LogicalKeyboardKey.keyF,
            control: true,
            verticalWriting: false,
          ),
          ReaderKeyCommand.openSearch,
        );
        expect(
          readerKeyCommandFor(
            LogicalKeyboardKey.keyF,
            control: true,
            verticalWriting: true,
          ),
          ReaderKeyCommand.openSearch,
        );
      });

      test('Ctrl+Shift+F、Ctrl+Alt+F、Ctrl+Meta+F、單獨 F 皆為 null', () {
        expect(
          readerKeyCommandFor(
            LogicalKeyboardKey.keyF,
            control: true,
            shift: true,
            verticalWriting: false,
          ),
          isNull,
        );
        expect(
          readerKeyCommandFor(
            LogicalKeyboardKey.keyF,
            control: true,
            alt: true,
            verticalWriting: false,
          ),
          isNull,
        );
        expect(
          readerKeyCommandFor(
            LogicalKeyboardKey.keyF,
            control: true,
            meta: true,
            verticalWriting: false,
          ),
          isNull,
        );
        expect(
          readerKeyCommandFor(
            LogicalKeyboardKey.keyF,
            control: false,
            verticalWriting: false,
          ),
          isNull,
        );
      });
    });

    group('修飾鍵阻斷規則 (Review Focus 2)', () {
      test('翻頁類按鍵帶 control、alt 或 meta 任一皆為 null', () {
        expect(
          readerKeyCommandFor(
            LogicalKeyboardKey.arrowLeft,
            alt: true,
            verticalWriting: false,
          ),
          isNull,
        );
        expect(
          readerKeyCommandFor(
            LogicalKeyboardKey.arrowRight,
            control: true,
            verticalWriting: false,
          ),
          isNull,
        );
        expect(
          readerKeyCommandFor(
            LogicalKeyboardKey.arrowDown,
            meta: true,
            verticalWriting: false,
          ),
          isNull,
        );
        expect(
          readerKeyCommandFor(
            LogicalKeyboardKey.space,
            control: true,
            verticalWriting: false,
          ),
          isNull,
        );
        expect(
          readerKeyCommandFor(
            LogicalKeyboardKey.home,
            control: true,
            verticalWriting: false,
          ),
          isNull,
        );
        expect(
          readerKeyCommandFor(
            LogicalKeyboardKey.end,
            alt: true,
            verticalWriting: false,
          ),
          isNull,
        );
        expect(
          readerKeyCommandFor(
            LogicalKeyboardKey.pageUp,
            control: true,
            verticalWriting: false,
          ),
          isNull,
        );
      });

      test('翻頁類按鍵（除 Space 外）帶 shift 不受影響', () {
        expect(
          readerKeyCommandFor(
            LogicalKeyboardKey.arrowLeft,
            shift: true,
            verticalWriting: false,
          ),
          ReaderKeyCommand.previousPage,
        );
        expect(
          readerKeyCommandFor(
            LogicalKeyboardKey.arrowRight,
            shift: true,
            verticalWriting: false,
          ),
          ReaderKeyCommand.nextPage,
        );
        expect(
          readerKeyCommandFor(
            LogicalKeyboardKey.home,
            shift: true,
            verticalWriting: false,
          ),
          ReaderKeyCommand.firstPage,
        );
      });
    });

    group('無關按鍵', () {
      test('字母、功能鍵與控制鍵回傳 null', () {
        expect(
          readerKeyCommandFor(
            LogicalKeyboardKey.keyA,
            verticalWriting: false,
          ),
          isNull,
        );
        expect(
          readerKeyCommandFor(
            LogicalKeyboardKey.enter,
            verticalWriting: false,
          ),
          isNull,
        );
        expect(
          readerKeyCommandFor(
            LogicalKeyboardKey.tab,
            verticalWriting: false,
          ),
          isNull,
        );
        expect(
          readerKeyCommandFor(
            LogicalKeyboardKey.f5,
            verticalWriting: false,
          ),
          isNull,
        );
        expect(
          readerKeyCommandFor(
            LogicalKeyboardKey.escape,
            verticalWriting: false,
          ),
          isNull,
        );
        expect(
          readerKeyCommandFor(
            LogicalKeyboardKey.f11,
            verticalWriting: false,
          ),
          isNull,
        );
      });
    });
  });
}
