import 'package:elinkbook/reader/book_reader_prefs.dart';
import 'package:elinkbook/reader/column_mode.dart';
import 'package:elinkbook/reader/epub_text_align.dart';
import 'package:elinkbook/reader/reader_settings_draft.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/full_book_reader_prefs.dart';

void main() {
  group('ReaderSettingsDraft', () {
    test('空 prefs：fromPrefs(empty).toPrefs() 只輸出具現化的預設欄位', () {
      final draft = ReaderSettingsDraft.fromPrefs(const BookReaderPrefs());

      expect(
        draft.toPrefs(),
        const BookReaderPrefs(
          marginTop: 32,
          marginBottom: 16,
          marginLeft: 24,
          marginRight: 24,
          publisherStyles: true,
          showHeader: false,
          showFooter: false,
          fullscreen: false,
          columnMode: ColumnMode.auto,
          columnSize: 720,
        ),
      );
    });

    test('種子往返：fromPrefs(seed).toPrefs() 等於 seed.reflowableEpubFields()', () {
      final draft = ReaderSettingsDraft.fromPrefs(fullBookReaderPrefsSeed);
      final output = draft.toPrefs();

      expect(output, fullBookReaderPrefsSeed.reflowableEpubFields());
      expect(output.pdfContrast, isNull);
      expect(output.dualPageMode, isNull);
    });

    test('字級與段距：儲存倍率 1.5 對應 UI 值 24、1.2 對應 12；UI 值回輸出 1.5、1.2', () {
      final draft = ReaderSettingsDraft.fromPrefs(
        const BookReaderPrefs(fontSize: 1.5, paragraphSpacing: 1.2),
      );

      expect(draft.fontSize.value, 24);
      expect(draft.paragraphSpacing.value, 12);

      final output = draft.toPrefs();
      expect(output.fontSize, 1.5);
      expect(output.paragraphSpacing, 1.2);
    });

    test('非整數倍率取整到 UI 刻度：fontSize 1.03 的 UI 值為 16，輸出 1.0', () {
      final draft = ReaderSettingsDraft.fromPrefs(
        const BookReaderPrefs(fontSize: 1.03),
      );

      expect(draft.fontSize.value, 16);
      expect(draft.toPrefs().fontSize, 1.0);
    });

    test('未覆寫欄位輸出 null：字級、字重、行距、段距、字距在 empty 輸入下 toPrefs 皆為 null', () {
      final output = ReaderSettingsDraft.fromPrefs(
        const BookReaderPrefs(),
      ).toPrefs();

      expect(output.fontSize, isNull);
      expect(output.fontWeight, isNull);
      expect(output.lineHeight, isNull);
      expect(output.paragraphSpacing, isNull);
      expect(output.letterSpacing, isNull);
    });

    test('OverridableValue.set：value 變為新值且 overridden 為 true', () {
      final field = OverridableValue(defaultValue: 16);

      expect(field.value, 16);
      expect(field.overridden, isFalse);

      field.set(20);

      expect(field.value, 20);
      expect(field.overridden, isTrue);
    });

    test('OverridableValue.reset：value 回 defaultValue 且 overridden 為 false', () {
      final field = OverridableValue(defaultValue: 16, initial: 24);

      expect(field.value, 24);
      expect(field.overridden, isTrue);

      field.reset();

      expect(field.value, 16);
      expect(field.overridden, isFalse);
    });

    test('首行縮排關閉時保留數字', () {
      final draft = ReaderSettingsDraft.fromPrefs(const BookReaderPrefs());

      expect(draft.firstLineIndentOn, isFalse);
      expect(draft.firstLineIndent, 2);

      draft.firstLineIndent = 3;
      expect(draft.toPrefs().firstLineIndent, isNull);

      draft.firstLineIndentOn = true;
      expect(draft.toPrefs().firstLineIndent, 3);
    });

    test('首行縮排為 0 時視為已開啟', () {
      final draft = ReaderSettingsDraft.fromPrefs(
        const BookReaderPrefs(firstLineIndent: 0),
      );

      expect(draft.firstLineIndentOn, isTrue);
      expect(draft.toPrefs().firstLineIndent, 0.0);
    });

    test('resetToBookDefault 只動 6 個欄位', () {
      final draft = ReaderSettingsDraft.fromPrefs(const BookReaderPrefs());
      draft.fontSize.set(24);
      draft.fontWeight.set(1.5);
      draft.lineHeight.set(1.8);
      draft.paragraphSpacing.set(16);
      draft.letterSpacing.set(0.05);
      draft.firstLineIndentOn = true;
      draft.firstLineIndent = 4;

      draft.fontFamily = 'NotoSerifTC';
      draft.marginTop = 48;
      draft.textAlign = EpubTextAlign.justify;
      draft.showFooter = true;

      draft.resetToBookDefault();

      expect(draft.fontSize.overridden, isFalse);
      expect(draft.fontSize.value, ReaderSettingsDraft.defaultFontSize);
      expect(draft.fontWeight.overridden, isFalse);
      expect(draft.fontWeight.value, ReaderSettingsDraft.defaultFontWeight);
      expect(draft.lineHeight.overridden, isFalse);
      expect(draft.lineHeight.value, ReaderSettingsDraft.defaultLineHeight);
      expect(draft.paragraphSpacing.overridden, isFalse);
      expect(
        draft.paragraphSpacing.value,
        ReaderSettingsDraft.defaultParagraphSpacing,
      );
      expect(draft.letterSpacing.overridden, isFalse);
      expect(
        draft.letterSpacing.value,
        ReaderSettingsDraft.defaultLetterSpacing,
      );
      expect(draft.firstLineIndentOn, isFalse);
      expect(draft.firstLineIndent, ReaderSettingsDraft.defaultFirstLineIndent);

      expect(draft.fontFamily, 'NotoSerifTC');
      expect(draft.marginTop, 48);
      expect(draft.textAlign, EpubTextAlign.justify);
      expect(draft.showFooter, isTrue);
    });

    test('isBookDefaultTextStyle：逐一驗證 6 個文字樣式欄位與重置回復', () {
      final draft = ReaderSettingsDraft.fromPrefs(const BookReaderPrefs());
      expect(draft.isBookDefaultTextStyle, isTrue);

      draft.fontSize.set(20);
      expect(draft.isBookDefaultTextStyle, isFalse);
      draft.resetToBookDefault();
      expect(draft.isBookDefaultTextStyle, isTrue);

      draft.fontWeight.set(1.25);
      expect(draft.isBookDefaultTextStyle, isFalse);
      draft.resetToBookDefault();
      expect(draft.isBookDefaultTextStyle, isTrue);

      draft.lineHeight.set(1.5);
      expect(draft.isBookDefaultTextStyle, isFalse);
      draft.resetToBookDefault();
      expect(draft.isBookDefaultTextStyle, isTrue);

      draft.paragraphSpacing.set(14);
      expect(draft.isBookDefaultTextStyle, isFalse);
      draft.resetToBookDefault();
      expect(draft.isBookDefaultTextStyle, isTrue);

      draft.letterSpacing.set(0.05);
      expect(draft.isBookDefaultTextStyle, isFalse);
      draft.resetToBookDefault();
      expect(draft.isBookDefaultTextStyle, isTrue);

      draft.firstLineIndentOn = true;
      expect(draft.isBookDefaultTextStyle, isFalse);
      draft.resetToBookDefault();
      expect(draft.isBookDefaultTextStyle, isTrue);
    });
  });
}
