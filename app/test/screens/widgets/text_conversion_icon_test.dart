import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/text_conversion_mode.dart';
import 'package:elinkbook/screens/widgets/text_conversion_icon.dart';

void main() {
  group('TextConversionIcon', () {
    testWidgets('toTraditional 模式正確渲染「简 → 繁」與箭頭圖示', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: TextConversionIcon(
              mode: TextConversionMode.toTraditional,
            ),
          ),
        ),
      );

      expect(find.text('简'), findsOneWidget);
      expect(find.text('繁'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_forward), findsOneWidget);
    });

    testWidgets('toSimplified 模式正確渲染「繁 → 简」與箭頭圖示', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: TextConversionIcon(
              mode: TextConversionMode.toSimplified,
            ),
          ),
        ),
      );

      expect(find.text('繁'), findsOneWidget);
      expect(find.text('简'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_forward), findsOneWidget);
    });

    testWidgets('original 模式回退為 article_outlined 圖示', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: TextConversionIcon(
              mode: TextConversionMode.original,
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.article_outlined), findsOneWidget);
    });

    testWidgets('繼承 IconTheme 與 DefaultTextStyle 的前景顏色', (tester) async {
      const testColor = Colors.purple;
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: IconTheme(
              data: IconThemeData(color: testColor, size: 22),
              child: TextConversionIcon(
                mode: TextConversionMode.toTraditional,
              ),
            ),
          ),
        ),
      );

      final icon = tester.widget<Icon>(find.byIcon(Icons.arrow_forward));
      expect(icon.color, testColor);

      final textWidget = tester.widget<Text>(find.text('简'));
      expect(textWidget.style?.color, testColor);
    });
  });
}
