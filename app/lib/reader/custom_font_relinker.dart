import 'package:flutter/foundation.dart';

import '../storage/storage_permission.dart';
import 'custom_font.dart';
import 'custom_fonts_repository.dart';
import 'font_name_parser.dart';

/// 使用者重新選取的字型檔案（與 `SingleFontFilePicker` 的回傳型別相同）。
typedef PickedFontFile = ({String uri, String name, Uint8List bytes});

/// 持久化授權函式；預設是 [persistReadAccess]，測試注入假的以免碰原生。
typedef PersistReadAccess = Future<bool> Function(String uri);

/// [CustomFontRelinker.relink] 的結果，與書籍的 `BookRelinkResult` 並列：
/// 畫面只負責把結果對應成文字，規則都在 relinker 內。
sealed class FontRelinkResult {
  const FontRelinkResult();
}

/// 重新連結成功：記錄的 URI 已更新為新選取的檔案。
final class FontRelinkSuccess extends FontRelinkResult {
  const FontRelinkSuccess();

  // 只覆寫 toString：測試斷言失敗時看得到是哪個結果，不會只印 Instance of。
  // 刻意不實作 ==／hashCode：呼叫端與測試都以 isA<>／switch 比對型別，沒有人
  // 需要值等價（比照 OpenBookState）。
  @override
  String toString() => 'FontRelinkSuccess';
}

/// 選取的字型與原字型的家族名稱不同：記錄完全不動、也沒有持久化授權。
final class FontRelinkFamilyMismatch extends FontRelinkResult {
  const FontRelinkFamilyMismatch();

  @override
  String toString() => 'FontRelinkFamilyMismatch';
}

/// 其他失敗（資料庫寫入失敗等）：記錄維持原樣。
final class FontRelinkFailed extends FontRelinkResult {
  const FontRelinkFailed();

  @override
  String toString() => 'FontRelinkFailed';
}

/// 字型重新連結（CONTEXT.md「重新連結」；epic-15-storage-permission Issue 3
/// 原本寫在 `FontManagementScreen`，epic-54 Issue 3 搬出）。
///
/// 流程：比對家族名稱 → 持久化授權（盡力而為）→ 更新 URI。單書版面偏好以
/// 家族名稱引用字型，所以更新 URI 後所有使用這款字型的書自動恢復，不需要
/// 遷移。選檔器、SnackBar、按鈕停用狀態留在畫面。
class CustomFontRelinker {
  CustomFontRelinker({
    required this.repository,
    this.persistAccess = persistReadAccess,
  });

  final CustomFontsRepository repository;
  final PersistReadAccess persistAccess;

  /// 保證不拋出例外：任何非預期的例外都視為 [FontRelinkFailed]，畫面只需
  /// 依結果顯示對應 SnackBar。
  Future<FontRelinkResult> relink(CustomFont font, PickedFontFile picked) async {
    final id = font.id;
    if (id == null) return const FontRelinkFailed();

    // 家族名稱解析規則與批次上傳共用（resolveFontFamilyName）。
    final pickedFamily = resolveFontFamilyName(picked.bytes, picked.name);
    if (pickedFamily != font.familyName) {
      // 不符一律拒絕：選錯檔案不該白白消耗系統的持久化授權配額，更不能改記錄。
      return const FontRelinkFamilyMismatch();
    }

    try {
      // 字型檔不做落地複本退路（ADR 0021），授權盡力而為：被拒絕（false）
      // 不中止重新連結。
      await persistAccess(picked.uri);
      await repository.updateUri(id, picked.uri);
      return const FontRelinkSuccess();
    } catch (e) {
      // 資料庫寫入失敗（機率很低）等：記錄後回傳 failed，記錄與標示維持原樣，
      // 使用者可以再試一次。
      debugPrint('Failed to relink custom font: $e');
      return const FontRelinkFailed();
    }
  }
}
