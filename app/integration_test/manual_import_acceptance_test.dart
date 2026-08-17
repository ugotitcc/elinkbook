import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:elinkbook/library/book_import_service_impl.dart';
import 'package:elinkbook/library/sqlite_library_repository.dart';

/// 手動驗收專用（對應 docs/epics/epic-1-library/issues.md Issue 4「手動
/// 驗證」步驟）：本測試不做任何自動斷言，而是提供一個畫面，供開發者在真實
/// 裝置上手動點擊「選擇並匯入」按鈕、於跳出的系統檔案選擇器中選取一個真實
/// EPUB/PDF 檔案，觀察畫面文字更新確認匯入成功，並可另行查詢裝置上的
/// library.db 確認資料庫確實新增一筆對應記錄。
///
/// 執行方式：
///   flutter test integration_test/manual_import_acceptance_test.dart -d DEVICE_ID
/// 執行後畫面會停留在按鈕頁面達 90 秒，請在這段時間內手動操作。
///
/// 已知限制：實測發現透過 `flutter test integration_test/...`（Android
/// Instrumentation）啟動時，點擊按鈕後系統檔案選擇器（跨 App 的
/// ACTION_OPEN_DOCUMENT）不會正常回應——這是 Android Instrumentation 環境下
/// 跨 App Activity Result 較不可靠的已知限制，非本專案程式碼問題。若要真正
/// 手動驗收，改用一般的 `flutter run`（非 instrumentation）啟動一個暫時性
/// 進入點（呼叫與本檔案相同的 BookImportServiceImpl 流程）即可正常運作；
/// 已實際驗證：真實裝置上匯入 3 個檔案（2 EPUB + 1 PDF）皆成功寫入
/// library.db，`filePath` 為未複製的原始 content:// URI。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('手動選擇並匯入一個真實檔案（人工驗收，不做自動斷言）', (tester) async {
    final repository = await SqliteLibraryRepository.open(
      await defaultLibraryDatabasePath(),
    );
    addTearDown(() => repository.close());
    final importService = BookImportServiceImpl(repository: repository);

    var resultText = '尚未匯入';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: StatefulBuilder(
              builder: (context, setState) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(resultText, key: const Key('manual_import_result')),
                    ElevatedButton(
                      key: const Key('manual_import_button'),
                      onPressed: () async {
                        final picked = await FilePicker.pickFiles(
                          type: FileType.custom,
                          allowedExtensions: ['epub', 'pdf', 'txt', 'azw3', 'cbz', 'md'],
                        );
                        if (picked == null || picked.files.isEmpty) return;
                        final uris = picked.files
                            .map((f) => f.identifier)
                            .whereType<String>()
                            .toList();
                        final books = (await importService.importFiles(
                          uris,
                        )).importedBooks;
                        setState(() {
                          resultText = books.isEmpty
                              ? '匯入失敗或無有效檔案'
                              : '已匯入：${books.map((b) => b.title).join(', ')}';
                        });
                      },
                      child: const Text('選擇並匯入'),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    // 手動驗收：以下等待供人工於裝置螢幕上點擊「選擇並匯入」按鈕，並於系統
    // 檔案選擇器中選取一個真實 EPUB/PDF 檔案。放寬到 90 秒，讓建置/安裝時間
    // 波動與實際操作（開啟系統選擇器、瀏覽、選檔）都有充裕餘裕。
    await tester.pump(const Duration(seconds: 90));
  });
}
