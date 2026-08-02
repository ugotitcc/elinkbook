import 'package:flutter/material.dart';

import '../reader/global_reader_prefs.dart';
import '../reader/page_turn_mode.dart';
import '../reader/reader_prefs_manager.dart';
import '../reader/screen_orientation_setting.dart';

/// 閱讀預設值畫面（FR-36/37/38/42）：音量鍵翻頁開關、翻頁模式、螢幕方向、
/// 全螢幕模式四個獨立控制項，皆讀寫 [GlobalReaderPrefs]。**即時生效、無
/// 「儲存」按鈕**——每項控制項變更當下立即呼叫 `saveGlobalPrefs()`，互動
/// 模式比照既有 `NavZoneSettingsScreen`（design.md 決策 1，spec.md「閱讀
/// 預設值模組」：無預覽跟要不要即時存檔是兩個獨立問題，四項設定彼此獨立
/// 不需要批次提交語意，刻意決定不做「儲存」按鈕，勿因看起來像疏漏而改回
/// 儲存按鈕模式）。全域生效，不做單書覆寫，本畫面不接受 bookId 參數。
class ReadingDefaultsScreen extends StatefulWidget {
  final ReaderPrefsManager prefsManager;

  const ReadingDefaultsScreen({super.key, required this.prefsManager});

  @override
  State<ReadingDefaultsScreen> createState() => _ReadingDefaultsScreenState();
}

class _ReadingDefaultsScreenState extends State<ReadingDefaultsScreen> {
  bool _loading = true;
  late GlobalReaderPrefs _prefs;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await widget.prefsManager.loadGlobalPrefs();
    if (!mounted) return;
    setState(() {
      _prefs = prefs;
      _loading = false;
    });
  }

  void _update(GlobalReaderPrefs updated) {
    widget.prefsManager.saveGlobalPrefs(updated);
    setState(() => _prefs = updated);
  }

  Widget _buildSectionHeader(BuildContext context, String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(label, style: Theme.of(context).textTheme.titleSmall),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('閱讀預設值')),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(
                key: Key('reading_defaults_loading_indicator'),
              ),
            )
          : ListView(
              children: [
                SwitchListTile(
                  key: const Key('reading_defaults_volume_key_switch'),
                  title: const Text('音量鍵翻頁'),
                  value: _prefs.volumeKeyEnabled,
                  onChanged: (value) =>
                      _update(_prefs.copyWith(volumeKeyEnabled: value)),
                ),
                const Divider(height: 1),
                _buildSectionHeader(context, '翻頁模式'),
                RadioGroup<PageTurnMode>(
                  groupValue: _prefs.pageTurnMode,
                  onChanged: (mode) =>
                      _update(_prefs.copyWith(pageTurnMode: mode)),
                  child: Column(
                    children: [
                      RadioListTile<PageTurnMode>(
                        key: const Key(
                            'reading_defaults_page_turn_mode_paginated'),
                        title: const Text('點擊翻頁'),
                        value: PageTurnMode.paginated,
                      ),
                      RadioListTile<PageTurnMode>(
                        key: const Key(
                            'reading_defaults_page_turn_mode_scroll'),
                        title: const Text('滾動翻頁'),
                        value: PageTurnMode.scroll,
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                _buildSectionHeader(context, '螢幕方向'),
                RadioGroup<ScreenOrientationSetting>(
                  groupValue: _prefs.screenOrientation,
                  onChanged: (setting) =>
                      _update(_prefs.copyWith(screenOrientation: setting)),
                  child: Column(
                    children: [
                      RadioListTile<ScreenOrientationSetting>(
                        key: const Key(
                            'reading_defaults_screen_orientation_auto'),
                        title: const Text('自動旋轉'),
                        value: ScreenOrientationSetting.auto,
                      ),
                      RadioListTile<ScreenOrientationSetting>(
                        key: const Key(
                            'reading_defaults_screen_orientation_lock0'),
                        title: const Text('鎖定 0°'),
                        value: ScreenOrientationSetting.lock0,
                      ),
                      RadioListTile<ScreenOrientationSetting>(
                        key: const Key(
                            'reading_defaults_screen_orientation_lock90'),
                        title: const Text('鎖定 90°'),
                        value: ScreenOrientationSetting.lock90,
                      ),
                      RadioListTile<ScreenOrientationSetting>(
                        key: const Key(
                            'reading_defaults_screen_orientation_lock180'),
                        title: const Text('鎖定 180°'),
                        value: ScreenOrientationSetting.lock180,
                      ),
                      RadioListTile<ScreenOrientationSetting>(
                        key: const Key(
                            'reading_defaults_screen_orientation_lock270'),
                        title: const Text('鎖定 270°'),
                        value: ScreenOrientationSetting.lock270,
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  key: const Key('reading_defaults_fullscreen_switch'),
                  title: const Text('全螢幕模式'),
                  value: _prefs.fullscreen,
                  onChanged: (value) =>
                      _update(_prefs.copyWith(fullscreen: value)),
                ),
              ],
            ),
    );
  }
}
