import 'package:elinkbook/reader/app_font.dart';
import 'package:elinkbook/reader/available_fonts.dart';
import 'package:elinkbook/reader/custom_font.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const kingHwa = CustomFont(
    displayName: '京華老宋體',
    familyName: 'KingHwa_OldSong',
    fontUri: 'content://example/kinghwa',
  );

  group('effectiveFamily：偏好字型現在能不能用（epic-54 Issue 1）', () {
    test('偏好為 null（使用書本字型）：回傳 null', () {
      const fonts = AvailableFonts(installedBuiltIn: {AppFont.sourceHanSerif});

      expect(fonts.effectiveFamily(null), isNull);
    });

    test('偏好為已下載的內建字型：照原值回傳', () {
      const fonts = AvailableFonts(installedBuiltIn: {AppFont.sourceHanSerif});

      expect(fonts.effectiveFamily('SourceHanSerifTC'), 'SourceHanSerifTC');
    });

    test('偏好為未下載的內建字型：回傳 null（偏好本身不會被改寫）', () {
      const fonts = AvailableFonts(installedBuiltIn: {AppFont.sourceHanSans});

      expect(fonts.effectiveFamily('SourceHanSerifTC'), isNull);
    });

    test('偏好為已恢復的內建字型（原俠正楷）：沒下載回傳 null，下載後照原值回傳', () {
      expect(const AvailableFonts().effectiveFamily('GuanKiapTsingKhai'), isNull);
      expect(
        const AvailableFonts(installedBuiltIn: {AppFont.guanKiapTsingKhai})
            .effectiveFamily('GuanKiapTsingKhai'),
        'GuanKiapTsingKhai',
      );
    });

    test('偏好為清單中的自訂字型：照原值回傳，即使沒有任何已下載的內建字型', () {
      const fonts = AvailableFonts(customFonts: [kingHwa]);

      expect(fonts.effectiveFamily('KingHwa_OldSong'), 'KingHwa_OldSong');
    });

    test('偏好為不認得的名稱：回傳 null（行為調整：與設定面板顯示一致）', () {
      const fonts = AvailableFonts(
        installedBuiltIn: {AppFont.sourceHanSerif},
        customFonts: [kingHwa],
      );

      expect(fonts.effectiveFamily('NoSuchFont'), isNull);
    });

    test('沒有任何來源（AvailableFonts.empty，例如測試與舊呼叫端）：內建字型偏好回傳 null', () {
      expect(AvailableFonts.empty.effectiveFamily('SourceHanSerifTC'), isNull);
    });

    test('偏好為空字串：回傳 null，不當成有效家族名稱（Review Focus 2）', () {
      const fonts = AvailableFonts(
        installedBuiltIn: {AppFont.sourceHanSerif},
        customFonts: [kingHwa],
      );

      expect(fonts.effectiveFamily(''), isNull);
    });

    test('自訂字型的家族名稱與未下載的內建字型相同：自訂字型有自己的 @font-face，視為可用（Review Focus 3）', () {
      const sameNameCustom = CustomFont(
        displayName: '我的思源黑體',
        familyName: 'SourceHanSansTC',
        fontUri: 'content://example/mine',
      );
      const fonts = AvailableFonts(customFonts: [sameNameCustom]);

      expect(fonts.effectiveFamily('SourceHanSansTC'), 'SourceHanSansTC');
    });
  });

  group('builtInFonts：下拉選單可列出的內建字型', () {
    test('依 AppFont.values 的順序，不受集合建構順序影響', () {
      const fonts = AvailableFonts(
        installedBuiltIn: {AppFont.taiwanPearl, AppFont.sourceHanSans},
      );

      expect(fonts.builtInFonts, [AppFont.sourceHanSans, AppFont.taiwanPearl]);
    });

    test('沒有任何已下載的內建字型：空清單', () {
      expect(AvailableFonts.empty.builtInFonts, isEmpty);
    });
  });
}
