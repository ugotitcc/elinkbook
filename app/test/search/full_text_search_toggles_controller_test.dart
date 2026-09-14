// app/test/search/full_text_search_toggles_controller_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/search/full_text_search_settings_repository.dart';
import 'package:elinkbook/search/full_text_search_toggles_controller.dart';

import '../support/fake_full_text_search_settings_repository.dart';

void main() {
  group('FullTextSearchTogglesController.load', () {
    test('正確讀回兩個分類目前的啟用狀態', () async {
      final repository = FakeFullTextSearchSettingsRepository(
        initialEnabled: {
          ContentIndexCategory.pdf: true,
          ContentIndexCategory.foliate: false,
        },
      );
      final controller = FullTextSearchTogglesController(repository);

      await controller.load();

      expect(controller.pdfEnabled, isTrue);
      expect(controller.foliateEnabled, isFalse);
    });

    test('repository 為 null 時安全 no-op，兩個布林值維持預設 false，不拋例外', () async {
      final controller = FullTextSearchTogglesController(null);

      await controller.load();

      expect(controller.pdfEnabled, isFalse);
      expect(controller.foliateEnabled, isFalse);
    });
  });

  group('FullTextSearchTogglesController.toggle', () {
    test('切換 PDF 分類：呼叫 repository.setEnabled 並更新 pdfEnabled，foliateEnabled 不受影響',
        () async {
      final repository = FakeFullTextSearchSettingsRepository();
      final controller = FullTextSearchTogglesController(repository);

      await controller.toggle(ContentIndexCategory.pdf, true);

      expect(controller.pdfEnabled, isTrue);
      expect(controller.foliateEnabled, isFalse);
      expect(repository.setEnabledCalls, [(ContentIndexCategory.pdf, true)]);
    });

    test('切換其他格式分類：呼叫 repository.setEnabled 並更新 foliateEnabled，pdfEnabled 不受影響',
        () async {
      final repository = FakeFullTextSearchSettingsRepository();
      final controller = FullTextSearchTogglesController(repository);

      await controller.toggle(ContentIndexCategory.foliate, true);

      expect(controller.foliateEnabled, isTrue);
      expect(controller.pdfEnabled, isFalse);
      expect(
        repository.setEnabledCalls,
        [(ContentIndexCategory.foliate, true)],
      );
    });

    test('repository 為 null 時安全 no-op，兩個布林值維持不變，不拋例外', () async {
      final controller = FullTextSearchTogglesController(null);

      await controller.toggle(ContentIndexCategory.pdf, true);

      expect(controller.pdfEnabled, isFalse);
      expect(controller.foliateEnabled, isFalse);
    });

    test('切換開關由開啟轉為關閉（newValue = false）：正確更新布林值並呼叫 repository.setEnabled',
        () async {
      final repository = FakeFullTextSearchSettingsRepository(
        initialEnabled: {ContentIndexCategory.pdf: true},
      );
      final controller = FullTextSearchTogglesController(repository);
      await controller.load();
      expect(controller.pdfEnabled, isTrue);

      await controller.toggle(ContentIndexCategory.pdf, false);

      expect(controller.pdfEnabled, isFalse);
      expect(repository.setEnabledCalls, [(ContentIndexCategory.pdf, false)]);
    });
  });
}
