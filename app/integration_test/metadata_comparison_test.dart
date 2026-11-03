// Android Readium 詮釋資料提取對比測試（epic-66 Issue 2 Task 6）。
//
// 於實機（如 BooksPad）上執行，呼叫原生 elinkbook/book_metadata 通道
// 提取 10 份 fixture 的 metadata，並印出 [metadata_comparison] 行供比對。
//
// 執行方式：
// cd app && flutter test integration_test/metadata_comparison_test.dart -d <device-id>

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

const _channel = MethodChannel('elinkbook/book_metadata');

Future<String> _stageAssetAsFile(String assetPath, String fileName) async {
  final bytes = await rootBundle.load(assetPath);
  final tempDir = await getTemporaryDirectory();
  final file = File(p.join(tempDir.path, fileName));
  await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
  return file.path;
}

class _EpubComparisonCase {
  final String assetPath;
  final String fileName;

  const _EpubComparisonCase({
    required this.assetPath,
    required this.fileName,
  });
}

const _comparisonCases = [
  _EpubComparisonCase(
    assetPath: 'test/fixtures/metadata/meta_basic.epub',
    fileName: 'meta_basic.epub',
  ),
  _EpubComparisonCase(
    assetPath: 'test/fixtures/metadata/meta_multi_identifier.epub',
    fileName: 'meta_multi_identifier.epub',
  ),
  _EpubComparisonCase(
    assetPath: 'test/fixtures/metadata/meta_lang_titles_two_creators.epub',
    fileName: 'meta_lang_titles_two_creators.epub',
  ),
  _EpubComparisonCase(
    assetPath: 'test/fixtures/metadata/meta_creator_role.epub',
    fileName: 'meta_creator_role.epub',
  ),
  _EpubComparisonCase(
    assetPath: 'test/fixtures/metadata/meta_epub2_cover.epub',
    fileName: 'meta_epub2_cover.epub',
  ),
  _EpubComparisonCase(
    assetPath: 'test/fixtures/metadata/meta_no_cover.epub',
    fileName: 'meta_no_cover.epub',
  ),
  _EpubComparisonCase(
    assetPath: 'test/fixtures/metadata/meta_fixed_layout.epub',
    fileName: 'meta_fixed_layout.epub',
  ),
  _EpubComparisonCase(
    assetPath: 'test/fixtures/metadata/meta_no_identifier.epub',
    fileName: 'meta_no_identifier.epub',
  ),
  _EpubComparisonCase(
    assetPath: 'test/fixtures/sample.epub',
    fileName: 'sample.epub',
  ),
  _EpubComparisonCase(
    assetPath: 'test/fixtures/sample_fxl_svg_cover.epub',
    fileName: 'sample_fxl_svg_cover.epub',
  ),
];

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Android Readium extractMetadata 10 份 fixture 對比傾印', (tester) async {
    final stagedPaths = <String>[];
    addTearDown(() async {
      for (final p in stagedPaths) {
        final f = File(p);
        if (await f.exists()) await f.delete();
      }
    });

    for (final tc in _comparisonCases) {
      final staged = await _stageAssetAsFile(tc.assetPath, 'compare_${tc.fileName}');
      stagedPaths.add(staged);

      final metadata = await _channel.invokeMapMethod<String, Object?>(
        'extractMetadata',
        {'uri': staged, 'format': 'epub'},
      );

      expect(metadata, isNotNull, reason: '${tc.fileName} extractMetadata 回傳不可為 null');

      final coverBytes = metadata!['coverBytes'] as Uint8List?;
      final payload = jsonEncode({
        'title': metadata['title'],
        'author': metadata['author'],
        'identifier': metadata['identifier'],
        'isFixedLayout': metadata['isFixedLayout'],
        'coverSize': coverBytes?.length ?? 0,
      });

      // ignore: avoid_print
      print('[metadata_comparison] ${tc.fileName} $payload');
    }
  });
}
