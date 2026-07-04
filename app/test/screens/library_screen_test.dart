import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/screens/library_screen.dart';

// 依 spec.md「測試決策」：點擊範例書籍後的檔案複製（path_provider）與
// ReaderScreen 的原生渲染都仰賴真實平台 channel，一般 flutter test（無真實
// 裝置/模擬器）無法可靠驗證，因此「點擊 → 導航 → 渲染」的驗證交給
// integration_test/library_screen_test.dart；此處只驗證書架清單本身有
// 正確渲染出兩個範例書籍項目。
void main() {
  testWidgets('LibraryScreen 顯示書架標題與兩個範例書籍項目', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LibraryScreen()));

    expect(find.text('書架'), findsOneWidget);
    expect(find.text('範例 EPUB 書籍'), findsOneWidget);
    expect(find.text('範例 PDF 文件'), findsOneWidget);
  });
}
