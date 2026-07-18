import 'package:flutter/material.dart';

import '../reader/global_reader_prefs.dart';
import '../reader/nav_zone_mode.dart';
import '../reader/reader_prefs_manager.dart';

/// 導航熱區設定畫面（FR-24）：四選一模板（左翻頁／右翻頁／單手／自訂）
/// 選擇即時全域生效；讀寫對象為 [GlobalReaderPrefs]（透過
/// [ReaderPrefsManager]），不經過 `ResolvedPreferences`——該型別只服務
/// `ReaderScreen` 的渲染需求，不服務設定畫面（見
/// docs/epics/epic-7-interaction/spec.md「模組」節）。熱區設定為全域生效，
/// 不做單書覆寫（design.md 決策 #9），本畫面不接受 bookId 參數。
class NavZoneSettingsScreen extends StatefulWidget {
  final ReaderPrefsManager prefsManager;

  const NavZoneSettingsScreen({super.key, required this.prefsManager});

  @override
  State<NavZoneSettingsScreen> createState() => _NavZoneSettingsScreenState();
}

class _NavZoneSettingsScreenState extends State<NavZoneSettingsScreen> {
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

  void _selectMode(NavZoneMode mode) {
    final updated = _prefs.copyWith(navZoneMode: mode);
    widget.prefsManager.saveGlobalPrefs(updated);
    setState(() => _prefs = updated);
  }

  void _toggleDebugOverlay(bool value) {
    final updated = _prefs.copyWith(showNavZoneDebugOverlay: value);
    widget.prefsManager.saveGlobalPrefs(updated);
    setState(() => _prefs = updated);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('導航熱區')),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(
                key: Key('nav_zone_settings_loading_indicator'),
              ),
            )
          : ListView(
              children: [
                RadioListTile<NavZoneMode>(
                  key: const Key('nav_zone_mode_leftFlip'),
                  title: const Text('左翻頁'),
                  value: NavZoneMode.leftFlip,
                  groupValue: _prefs.navZoneMode,
                  onChanged: (mode) => _selectMode(mode!),
                ),
                RadioListTile<NavZoneMode>(
                  key: const Key('nav_zone_mode_rightFlip'),
                  title: const Text('右翻頁'),
                  value: NavZoneMode.rightFlip,
                  groupValue: _prefs.navZoneMode,
                  onChanged: (mode) => _selectMode(mode!),
                ),
                RadioListTile<NavZoneMode>(
                  key: const Key('nav_zone_mode_oneHand'),
                  title: const Text('單手'),
                  value: NavZoneMode.oneHand,
                  groupValue: _prefs.navZoneMode,
                  onChanged: (mode) => _selectMode(mode!),
                ),
                RadioListTile<NavZoneMode>(
                  key: const Key('nav_zone_mode_custom'),
                  title: const Text('自訂'),
                  value: NavZoneMode.custom,
                  groupValue: _prefs.navZoneMode,
                  onChanged: (mode) => _selectMode(mode!),
                ),
                const Divider(),
                SwitchListTile(
                  key: const Key('nav_zone_debug_overlay_switch'),
                  title: const Text('顯示熱區輔助線'),
                  value: _prefs.showNavZoneDebugOverlay,
                  onChanged: _toggleDebugOverlay,
                ),
              ],
            ),
    );
  }
}
