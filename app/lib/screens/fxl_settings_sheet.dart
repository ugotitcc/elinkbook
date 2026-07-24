import 'package:flutter/material.dart';

import '../reader/book_reader_prefs.dart';
import '../reader/dual_page_mode.dart';

/// EPUB 固定版面（FXL 漫畫）專屬的精簡版設定 Bottom Sheet（見
/// docs/epics/epic-16-dual-page/spec.md「模組」段落）：只提供「雙頁模式」
/// 三態切換，不與 PdfSettingsSheet／ReaderSettingsSheet 共用元件（固定版面
/// 沒有字型/裁切/濾鏡等其餘設定）。為未來 FR-42（全螢幕顯示開關）預留擴充
/// 空間，本 issue 不實作該功能本身。
class FxlSettingsSheet extends StatefulWidget {
  final BookReaderPrefs prefs;
  final ValueChanged<BookReaderPrefs> onChanged;

  const FxlSettingsSheet({
    super.key,
    required this.prefs,
    required this.onChanged,
  });

  @override
  State<FxlSettingsSheet> createState() => _FxlSettingsSheetState();
}

class _FxlSettingsSheetState extends State<FxlSettingsSheet> {
  late DualPageMode _dualPageMode;

  @override
  void initState() {
    super.initState();
    _dualPageMode = widget.prefs.dualPageMode ?? DualPageMode.auto;
  }

  void _notifyChanged() {
    widget.onChanged(widget.prefs.copyWith(dualPageMode: _dualPageMode));
  }

  @override
  Widget build(BuildContext context) {
    const dualPageOptions = [
      (DualPageMode.auto, 'auto', Icons.stay_current_landscape, '自動（橫向雙頁）'),
      (DualPageMode.always, 'always', Icons.view_column, '永遠雙頁'),
      (DualPageMode.never, 'never', Icons.crop_portrait, '永遠單頁'),
    ];
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('⚙️ 漫畫版面設定',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                IconButton(
                  key: const Key('fxl_settings_close_button'),
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text('雙頁模式'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 4,
              children: dualPageOptions.map((option) {
                final (mode, keySuffix, icon, tooltip) = option;
                final selected = _dualPageMode == mode;
                return IconButton(
                  key: Key('fxl_settings_dual_page_mode_$keySuffix'),
                  icon: Icon(icon),
                  tooltip: tooltip,
                  color:
                      selected ? Theme.of(context).colorScheme.primary : null,
                  onPressed: () => setState(() {
                    _dualPageMode = mode;
                    _notifyChanged();
                  }),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}
