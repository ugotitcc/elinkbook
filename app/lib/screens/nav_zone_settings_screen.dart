import 'package:flutter/material.dart';

import '../reader/global_reader_prefs.dart';
import '../reader/nav_zone_mode.dart';
import '../reader/reader_prefs_manager.dart';
import '../reader/zone_action.dart';

/// 導航熱區設定畫面（FR-24）：四選一模板（左翻頁／右翻頁／單手／自訂）
/// 選擇即時全域生效；選到「自訂」時顯示 9 格自由編輯器，逐格點擊循環切換
/// 4 種 [ZoneAction]，儲存前呼叫 [isValidCustomZoneConfig] 驗證（design.md
/// 決策 #7，避免使用者設定出沒有任何格子能退出沉浸模式的死鎖組合）。讀寫
/// 對象為 [GlobalReaderPrefs]（透過 [ReaderPrefsManager]），不經過
/// `ResolvedPreferences`——該型別只服務 `ReaderScreen` 的渲染需求，不服務
/// 設定畫面（見 docs/epics/epic-7-interaction/spec.md「模組」節）。熱區
/// 設定為全域生效，不做單書覆寫（design.md 決策 #9），本畫面不接受 bookId
/// 參數。
class NavZoneSettingsScreen extends StatefulWidget {
  final ReaderPrefsManager prefsManager;

  const NavZoneSettingsScreen({super.key, required this.prefsManager});

  @override
  State<NavZoneSettingsScreen> createState() => _NavZoneSettingsScreenState();
}

class _NavZoneSettingsScreenState extends State<NavZoneSettingsScreen> {
  bool _loading = true;
  late GlobalReaderPrefs _prefs;

  /// 自訂模式的編輯中陣列——只在 [_prefs] 的 `navZoneMode` 為
  /// [NavZoneMode.custom] 時於畫面上可見/可互動；點擊格子只更新這裡，
  /// 尚未通過 [_saveCustomActions] 驗證前不會寫入 [_prefs]／持久化，避免
  /// 編輯過程中暫時出現的無效狀態（例如暫時全部非 `menu`）被意外儲存。
  late List<ZoneAction> _customActions;

  String? _validationError;

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
      _customActions = List.of(prefs.navZoneCustomActions);
      _loading = false;
    });
  }

  void _selectMode(NavZoneMode mode) {
    final updated = _prefs.copyWith(navZoneMode: mode);
    widget.prefsManager.saveGlobalPrefs(updated);
    setState(() {
      _prefs = updated;
      // 切換模板時捨棄尚未儲存的自訂編輯，回到上次已儲存的自訂陣列。
      _customActions = List.of(updated.navZoneCustomActions);
      _validationError = null;
    });
  }

  void _toggleDebugOverlay(bool value) {
    final updated = _prefs.copyWith(showNavZoneDebugOverlay: value);
    widget.prefsManager.saveGlobalPrefs(updated);
    setState(() => _prefs = updated);
  }

  void _cycleCell(int index) {
    final current = _customActions[index];
    final next = ZoneAction
        .values[(ZoneAction.values.indexOf(current) + 1) % ZoneAction.values.length];
    setState(() {
      _customActions = List.of(_customActions)..[index] = next;
    });
  }

  void _saveCustomActions() {
    if (!isValidCustomZoneConfig(_customActions)) {
      setState(() {
        _validationError = '至少需要 1 格設為「選單」，否則將無法退出沉浸模式';
      });
      return;
    }
    final updated =
        _prefs.copyWith(navZoneCustomActions: List.of(_customActions));
    widget.prefsManager.saveGlobalPrefs(updated);
    setState(() {
      _prefs = updated;
      _validationError = null;
    });
  }

  String _actionLabel(ZoneAction action) {
    switch (action) {
      case ZoneAction.previousPage:
        return '上一頁';
      case ZoneAction.nextPage:
        return '下一頁';
      case ZoneAction.menu:
        return '選單';
      case ZoneAction.none:
        return '無動作';
    }
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
                RadioGroup<NavZoneMode>(
                  groupValue: _prefs.navZoneMode,
                  onChanged: (mode) => _selectMode(mode!),
                  child: Column(
                    children: [
                      RadioListTile<NavZoneMode>(
                        key: const Key('nav_zone_mode_leftFlip'),
                        title: const Text('左翻頁'),
                        value: NavZoneMode.leftFlip,
                      ),
                      RadioListTile<NavZoneMode>(
                        key: const Key('nav_zone_mode_rightFlip'),
                        title: const Text('右翻頁'),
                        value: NavZoneMode.rightFlip,
                      ),
                      RadioListTile<NavZoneMode>(
                        key: const Key('nav_zone_mode_oneHand'),
                        title: const Text('單手'),
                        value: NavZoneMode.oneHand,
                      ),
                      RadioListTile<NavZoneMode>(
                        key: const Key('nav_zone_mode_custom'),
                        title: const Text('自訂'),
                        value: NavZoneMode.custom,
                      ),
                    ],
                  ),
                ),
                if (_prefs.navZoneMode == NavZoneMode.custom)
                  _buildCustomEditor(),
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

  Widget _buildCustomEditor() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: List.generate(9, (index) {
              return InkWell(
                key: Key('nav_zone_custom_cell_$index'),
                onTap: () => _cycleCell(index),
                child: Container(
                  margin: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    border: Border.all(color: Theme.of(context).dividerColor),
                  ),
                  alignment: Alignment.center,
                  child: Text(_actionLabel(_customActions[index])),
                ),
              );
            }),
          ),
          if (_validationError != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _validationError!,
                key: const Key('nav_zone_custom_validation_error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          const SizedBox(height: 8),
          ElevatedButton(
            key: const Key('nav_zone_save_custom_button'),
            onPressed: _saveCustomActions,
            child: const Text('儲存自訂熱區設定'),
          ),
        ],
      ),
    );
  }
}
