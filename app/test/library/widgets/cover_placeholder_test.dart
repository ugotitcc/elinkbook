import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/library/widgets/book_cover.dart';
import 'package:elinkbook/theme/app_theme.dart';
import 'package:elinkbook/theme/app_theme_data.dart';

void main() {
  Widget wrap(Widget child, {required bool isEinkMode}) {
    return MaterialApp(
      theme: resolveThemeData(theme: AppTheme.light, isEinkMode: isEinkMode),
      home: child,
    );
  }

  testWidgets('容器夠大時，圖示大小為縮放上限 40', (tester) async {
    await tester.pumpWidget(wrap(
      const SizedBox(
        width: 200,
        height: 200,
        child: CoverPlaceholder(icon: Icons.book, title: '測試書'),
      ),
      isEinkMode: false,
    ));

    final icon = tester.widget<Icon>(find.byIcon(Icons.book));
    expect(icon.size, 40.0);
  });

  testWidgets('容器很小時，圖示大小為縮放下限 16', (tester) async {
    await tester.pumpWidget(wrap(
      const SizedBox(
        width: 20,
        height: 20,
        child: CoverPlaceholder(icon: Icons.book, title: '測試書'),
      ),
      isEinkMode: false,
    ));

    final icon = tester.widget<Icon>(find.byIcon(Icons.book));
    expect(icon.size, 16.0);
  });

  testWidgets('可用高度低於 56 時，不渲染標題文字列', (tester) async {
    await tester.pumpWidget(wrap(
      const SizedBox(
        width: 100,
        height: 40,
        child: CoverPlaceholder(icon: Icons.book, title: '測試書'),
      ),
      isEinkMode: false,
    ));

    expect(find.text('測試書'), findsNothing);
  });

  testWidgets('可用高度達到 56 時，渲染標題文字列', (tester) async {
    await tester.pumpWidget(wrap(
      const SizedBox(
        width: 100,
        height: 56,
        child: CoverPlaceholder(icon: Icons.book, title: '測試書'),
      ),
      isEinkMode: false,
    ));

    expect(find.text('測試書'), findsOneWidget);
  });

  testWidgets(
      'title 為 null（B 類：無對應書籍）時渲染空字串文字列，字級與非 null 時一致（佈局高度對齊 A 類）',
      (tester) async {
    await tester.pumpWidget(wrap(
      const SizedBox(
        width: 100,
        height: 100,
        child: CoverPlaceholder(icon: Icons.book),
      ),
      isEinkMode: false,
    ));

    final emptyText = tester.widget<Text>(find.text(''));
    // shortSide = 100，字級 clamp(100*0.14=14, 9, 12) = 12。
    expect(emptyText.style?.fontSize, 12.0);
  });

  testWidgets('title 為 null（B 類）時空字串的 RenderBox 高度與非 null（A 類）完全相等'
      '（issues.md Issue 9 單元測試要求明文規定的斷言——只驗證 fontSize 數值相同不夠，'
      '因為那測不出來實作被誤改成 SizedBox.shrink() 或不同 line-height 這種同樣'
      'fontSize 但高度不同的退化寫法，見 reviews/review-plan-issue-9.md C2）',
      (tester) async {
    await tester.pumpWidget(wrap(
      const SizedBox(
        width: 100,
        height: 100,
        child: CoverPlaceholder(icon: Icons.book, title: '測試書'),
      ),
      isEinkMode: false,
    ));
    final titleHeight = tester.getSize(find.text('測試書')).height;

    await tester.pumpWidget(wrap(
      const SizedBox(
        width: 100,
        height: 100,
        child: CoverPlaceholder(icon: Icons.book),
      ),
      isEinkMode: false,
    ));
    final emptyHeight = tester.getSize(find.text('')).height;

    expect(emptyHeight, equals(titleHeight),
        reason: 'B 類空字串文字列高度必須與 A 類標題高度完全一致，才能保證圖示基準線對齊');
  });

  testWidgets('可用寬度低於門檻時（即使高度足夠），不渲染標題文字列', (tester) async {
    await tester.pumpWidget(wrap(
      const SizedBox(
        width: 20,
        height: 100,
        child: CoverPlaceholder(icon: Icons.book, title: '測試書'),
      ),
      isEinkMode: false,
    ));

    expect(find.text('測試書'), findsNothing);
  });

  testWidgets('E-Ink 模式開啟時，外框存在且顏色來自 colorScheme.onSurface（寬度 1.5）',
      (tester) async {
    await tester.pumpWidget(wrap(
      const SizedBox(
        width: 100,
        height: 100,
        child: CoverPlaceholder(icon: Icons.book, title: '測試書'),
      ),
      isEinkMode: true,
    ));

    final container = tester.widget<Container>(find.byType(Container));
    final decoration = container.decoration as BoxDecoration;
    final scheme =
        resolveThemeData(theme: AppTheme.light, isEinkMode: true).colorScheme;
    expect(decoration.border, Border.all(color: scheme.onSurface, width: 1.5));
  });

  testWidgets('非 E-Ink 模式時，無外框', (tester) async {
    await tester.pumpWidget(wrap(
      const SizedBox(
        width: 100,
        height: 100,
        child: CoverPlaceholder(icon: Icons.book, title: '測試書'),
      ),
      isEinkMode: false,
    ));

    final container = tester.widget<Container>(find.byType(Container));
    final decoration = container.decoration as BoxDecoration;
    expect(decoration.border, isNull);
  });
}
