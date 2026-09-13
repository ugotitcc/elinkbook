import 'package:flutter/material.dart';

import '../reader/global_reader_prefs.dart';
import '../reader/nav_zone_mode.dart';
import '../reader/reader_prefs_manager.dart';
import '../reader/zone_action.dart';

/// 「簡單」模板卡片（`leftFlip`／`rightFlip`／`oneHand`）色塊配色表
/// （epic-18-reader-device-qa Issue 44，真機使用回報：`leftFlip`／
/// `rightFlip` 原本用「欄位位置」決定色塊顏色，導致同一個 `chevron_left`
/// 圖示在兩張卡片上顏色不同〔一個紅一個藍〕。改用「圖示本身」決定顏色，
/// 讓三張卡片的配色語意一致：綠＝選單、紅＝上一頁、藍＝下一頁，比照
/// `_buildOneHandTemplateCard()` 既有的配色慣例。抽成頂層純函式方便獨立
/// 測試與未來重用。
///
/// 紅／藍／綠三色是跟主題無關的固定裝飾編碼，維持寫死不變；其餘未知圖示
/// 的回退色改讀 [colorScheme] 的 `surfaceContainerHighest`
/// （epic-35-design-system-tokens Issue 5）。
Color navZoneTemplateIconColor(IconData icon, ColorScheme colorScheme) {
  if (icon == Icons.chevron_left) return Colors.red.shade100;
  if (icon == Icons.chevron_right) return Colors.blue.shade100;
  if (icon == Icons.menu) return Colors.green.shade100;
  return colorScheme.surfaceContainerHighest;
}

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
      _customActions = List.of(prefs.navZone.navZoneCustomActions);
      _loading = false;
    });
  }

  void _selectMode(NavZoneMode mode) {
    final updated =
        _prefs.copyWith(navZone: _prefs.navZone.copyWith(navZoneMode: mode));
    widget.prefsManager.saveGlobalPrefs(updated);
    setState(() {
      _prefs = updated;
      // 切換模板時捨棄尚未儲存的自訂編輯，回到上次已儲存的自訂陣列。
      _customActions = List.of(updated.navZone.navZoneCustomActions);
      _validationError = null;
    });
  }

  void _toggleDebugOverlay(bool value) {
    final updated = _prefs.copyWith(
      navZone: _prefs.navZone.copyWith(showNavZoneDebugOverlay: value),
    );
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
    final updated = _prefs.copyWith(
      navZone: _prefs.navZone
          .copyWith(navZoneCustomActions: List.of(_customActions)),
    );
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
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Text('翻頁方式'),
                      const Spacer(),
                      SegmentedButton<bool>(
                        key: const Key('nav_zone_template_toggle'),
                        segments: const [
                          ButtonSegment(value: false, label: Text('簡單')),
                          ButtonSegment(value: true, label: Text('自訂')),
                        ],
                        selected: {_prefs.navZone.navZoneMode == NavZoneMode.custom},
                        onSelectionChanged: (selection) {
                          final showCustom = selection.first;
                          if (showCustom) {
                            if (_prefs.navZone.navZoneMode != NavZoneMode.custom) {
                              _selectMode(NavZoneMode.custom);
                            }
                          } else {
                            if (_prefs.navZone.navZoneMode == NavZoneMode.custom) {
                              _selectMode(NavZoneMode.rightFlip);
                            }
                          }
                        },
                      ),
                    ],
                  ),
                ),
                if (_prefs.navZone.navZoneMode != NavZoneMode.custom)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildTemplateCard(
                          key: const Key('nav_zone_mode_leftFlip'),
                          mode: NavZoneMode.leftFlip,
                          leftIcon: Icons.chevron_right,
                          middleIcon: Icons.menu,
                          rightIcon: Icons.chevron_left,
                        ),
                        _buildTemplateCard(
                          key: const Key('nav_zone_mode_rightFlip'),
                          mode: NavZoneMode.rightFlip,
                          leftIcon: Icons.chevron_left,
                          middleIcon: Icons.menu,
                          rightIcon: Icons.chevron_right,
                        ),
                        _buildOneHandTemplateCard(),
                      ],
                    ),
                  ),
                if (_prefs.navZone.navZoneMode == NavZoneMode.custom)
                  _buildCustomEditor(),
                const Divider(),
                SwitchListTile(
                  key: const Key('nav_zone_debug_overlay_switch'),
                  title: const Text('顯示熱區輔助線'),
                  value: _prefs.navZone.showNavZoneDebugOverlay,
                  onChanged: _toggleDebugOverlay,
                ),
              ],
            ),
    );
  }

  /// 模板圖示卡片（Issue 5，取代原本的文字 `RadioListTile`）：縮小版三欄
  /// 示意圖（左/中/右三色區塊＋圖示），點選呼叫既有 [_selectMode]；與目前
  /// [NavZonePrefs.navZoneMode] 相同的卡片顯示 primary 色選中外框
  /// （design.md 決策 #7，參考 `tmp/images/導航熱區建議.jpg`）。三欄圖示
  /// 對應該模板實際指派的 [ZoneAction]（`leftFlip`/`rightFlip` 左右欄分別
  /// 對應 `nextPage`/`previousPage`，非固定裝飾符號）——這兩個模板剛好是
  /// 「同一欄、三列動作皆相同」，單列卡片足以正確表達。`oneHand` 模板改用
  /// 下方獨立的 [_buildOneHandTemplateCard]（見該處說明本卡片格式為何不
  /// 適用於它）。
  Widget _buildTemplateCard({
    required Key key,
    required NavZoneMode mode,
    required IconData leftIcon,
    IconData? middleIcon,
    required IconData rightIcon,
  }) {
    final selected = _prefs.navZone.navZoneMode == mode;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => _selectMode(mode),
      child: Container(
        key: key,
        width: 72,
        height: 64,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.onSurface,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Container(
                color: navZoneTemplateIconColor(
                    leftIcon, Theme.of(context).colorScheme),
                alignment: Alignment.center,
                child: Icon(leftIcon, size: 16),
              ),
            ),
            Expanded(
              child: Container(
                color: middleIcon == null
                    ? Theme.of(context).colorScheme.surfaceContainerHighest
                    : navZoneTemplateIconColor(
                        middleIcon, Theme.of(context).colorScheme),
                alignment: Alignment.center,
                child: middleIcon == null ? null : Icon(middleIcon, size: 16),
              ),
            ),
            Expanded(
              child: Container(
                color: navZoneTemplateIconColor(
                    rightIcon, Theme.of(context).colorScheme),
                alignment: Alignment.center,
                child: Icon(rightIcon, size: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// `oneHand` 模板專用的 3 列縮圖（epic-18-reader-device-qa Issue 36，
  /// 真機使用回報，取代 Issue 30 當初選錯的做法）。[oneHandZoneTemplate]
  /// 的語意是「依列變化、左右欄鏡射相同」（上排＝選單、中排＝上一頁、
  /// 下排＝下一頁），跟 `leftFlip`／`rightFlip`「同一欄三列皆相同」完全
  /// 相反——[_buildTemplateCard] 的單列三色塊架構只能表達欄的差異，架構上
  /// 就不可能正確表達列的差異，Issue 30 把左右欄圖示換成
  /// [Icons.chevron_left]／[Icons.chevron_right] 反而暗示「左右欄動作不同」，
  /// 與實際資料不符。改為 3 列各自的左/中/右三色塊（中欄留白，對應
  /// [ZoneAction.none]），列色與圖示對應該列的實際動作（menu／
  /// previousPage／nextPage），比照使用者提供的參考圖。
  Widget _buildOneHandTemplateCard() {
    const mode = NavZoneMode.oneHand;
    final selected = _prefs.navZone.navZoneMode == mode;

    Widget buildRow(IconData icon, Color color) {
      return Expanded(
        child: Row(
          children: [
            Expanded(
              child: Container(
                color: color,
                alignment: Alignment.center,
                child: Icon(icon, size: 12),
              ),
            ),
            const Expanded(child: SizedBox.shrink()),
            Expanded(
              child: Container(
                color: color,
                alignment: Alignment.center,
                child: Icon(icon, size: 12),
              ),
            ),
          ],
        ),
      );
    }

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => _selectMode(mode),
      child: Container(
        key: const Key('nav_zone_mode_oneHand'),
        width: 72,
        height: 64,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.onSurface,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            buildRow(Icons.menu, Colors.green.shade100),
            buildRow(Icons.chevron_left, Colors.red.shade100),
            buildRow(Icons.chevron_right, Colors.blue.shade100),
          ],
        ),
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
                    border: Border.all(
                        color: Theme.of(context).colorScheme.onSurface),
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
