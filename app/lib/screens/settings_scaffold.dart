import 'package:flutter/material.dart';

import '../l10n/app_locale.dart';
import '../l10n/app_localizations.dart';
import '../search/full_text_search_settings_repository.dart';
import '../search/full_text_search_toggles_controller.dart';
import '../theme/app_theme.dart';
import '../theme/app_theme_data.dart';
import 'about_screen.dart';
import 'appearance_dependencies.dart';
import 'cloud_account_settings_screen.dart';
import 'font_management_screen.dart';
import 'full_text_search_confirm_dialog.dart';
import 'nav_zone_settings_screen.dart';
import 'reader_feature_dependencies.dart';
import 'reader_console_log_screen.dart';
import 'reading_defaults_screen.dart';
import 'reading_stats_screen.dart';
import 'source_dependencies.dart';
import 'sync_dependencies.dart';
import 'sync_settings_screen.dart';
import 'tts_defaults_screen.dart';
import 'widgets/eb_field_card.dart';
import 'widgets/eb_section_header.dart';
import 'widgets/eb_sheet_shell.dart';

/// 設定畫面：四分區（外觀／閱讀／同步與帳號／關於，`DESIGN.md` §17，
/// epic-36-adaptive-shelf-navigation spec.md §功能⑤）。「佈景」（主題圓點，
/// 原位於 `LibraryScreen` AppBar，見 `epic-18-reader-device-qa` 工具列溢位
/// 修復）、「字型管理」、「閱讀預設值」、「導航熱區」、「同步」、「閱讀器
/// Console Log」（Issue 33 診斷用）、Console Log 攔截開關
/// （`epic-28-reader-settings-enhancements` Issue 2）與「關於」項目皆為既有
/// 功能原樣搬移，本次（由 `SettingsScreen` 更名而來）只是重新分組，行為與
/// 既有 Key 契約不變。
class SettingsScaffold extends StatefulWidget {
  /// 閱讀器功能依賴組（ADR 0037）：設定頁用到其中的 prefsManager、字型、TTS、
  /// 閱讀統計與全文檢索設定。
  final ReaderFeatureDependencies readerFeatures;

  /// 同步依賴組（ADR 0037）：「同步」入口開啟 `SyncSettingsScreen` 時取用。
  final SyncDependencies sync;

  /// 外觀快照（ADR 0037）：主題、E-Ink 與介面語言，加上三個變更 callback，
  /// 全部 non-null，由上層每次 build 現組往下傳。
  final AppearanceDependencies appearance;

  /// 來源依賴組（ADR 0037）：「雲端帳號」入口取其中的帳號 repository 與
  /// Google Drive／OneDrive OAuth client，全部 non-null，入口恆可點。
  final SourceDependencies sources;
  final VoidCallback? onNavigateToLibrary;
  final VoidCallback? onNavigateToSource;

  const SettingsScaffold({
    super.key,
    required this.readerFeatures,
    required this.sync,
    required this.sources,
    required this.appearance,
    this.onNavigateToLibrary,
    this.onNavigateToSource,
  });

  @override
  State<SettingsScaffold> createState() => _SettingsScaffoldState();
}

class _SettingsScaffoldState extends State<SettingsScaffold> {
  /// Console Log 攔截開關目前顯示值（epic-28-reader-settings-enhancements
  /// Issue 2）。刻意不採用「整頁 loading gate」模式——本畫面其餘 `ListTile`
  /// （佈景／字型管理等）與這個開關無關，初始值先顯示預設 `false`，
  /// `initState()` 的非同步載入完成後才 `setState` 更新為實際已儲存值，不
  /// 阻塞其餘項目的同步顯示。
  bool _consoleLogEnabled = false;

  /// 「啟用全文檢索」兩個分類的讀取/切換邏輯已收斂至
  /// [FullTextSearchTogglesController]（epic-41-search-architecture-hardening
  /// Issue 5），本欄位比照上方 `_consoleLogEnabled` 同一套「先顯示預設值、
  /// initState() 非同步載入完成後才 setState 更新」模式。
  late FullTextSearchTogglesController _fullTextSearchTogglesController;

  @override
  void initState() {
    super.initState();
    _fullTextSearchTogglesController = FullTextSearchTogglesController(
      widget.readerFeatures.fullTextSearchSettingsRepository,
    );
    _loadConsoleLogEnabled();
    _loadFullTextSearchSettings();
  }

  /// 【review-plan-issue-3.md M-1】`SettingsScaffold` 被 `AdaptiveShellScaffold`
  /// 的 `IndexedStack` 長駐掛載，只有 `initState()` 會載入一次的話，Issue 4
  /// 全庫搜尋畫面的第二個入口若改變了開關狀態，切回本畫面時會顯示過期的
  /// 值。切分頁會觸發 `AdaptiveShellScaffold.build()` 重新建構
  /// `SettingsScaffold(...)`，本 State 物件被重用、`didUpdateWidget` 因此
  /// 會被呼叫，在這裡重新載入即可低成本解決雙入口同步問題。
  @override
  void didUpdateWidget(covariant SettingsScaffold oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.readerFeatures.fullTextSearchSettingsRepository !=
        widget.readerFeatures.fullTextSearchSettingsRepository) {
      // 上層傳入了不同的 repository 實例（review-plan-issue-5.md I-1）：
      // 重新建構 controller 避免它繼續持有舊實例，與 build() 內
      // 「重建索引」按鈕直接取用 widget.readerFeatures.fullTextSearchSettingsRepository
      // （永遠讀最新實例）的行為分歧。
      _fullTextSearchTogglesController = FullTextSearchTogglesController(
        widget.readerFeatures.fullTextSearchSettingsRepository,
      );
    }
    _loadFullTextSearchSettings();
  }

  Future<void> _loadConsoleLogEnabled() async {
    final prefs = await widget.readerFeatures.prefsManager.loadGlobalPrefs();
    if (!mounted) return;
    setState(() => _consoleLogEnabled = prefs.consoleLogEnabled);
  }

  Future<void> _updateConsoleLogEnabled(bool value) async {
    setState(() => _consoleLogEnabled = value);
    final prefs = await widget.readerFeatures.prefsManager.loadGlobalPrefs();
    await widget.readerFeatures.prefsManager.saveGlobalPrefs(
      prefs.copyWith(consoleLogEnabled: value),
    );
  }

  Future<void> _loadFullTextSearchSettings() async {
    await _fullTextSearchTogglesController.load();
    if (!mounted) return;
    setState(() {});
  }

  /// 關閉開關（[value] 為 `false`）直接呼叫 `setEnabled`，不彈出確認對話框
  /// ——只有「從關閉切成開啟」才需要確認。使用者取消對話框時提前 return，
  /// 開關維持關閉、不呼叫 `setEnabled`。
  Future<void> _handleFullTextSearchToggle(
    ContentIndexCategory category,
    bool value,
  ) async {
    if (value) {
      final confirmed = await showFullTextSearchEnableConfirmDialog(
        context,
        category: category,
        isEinkMode: widget.appearance.isEinkMode,
      );
      if (!confirmed) return;
    }
    await _fullTextSearchTogglesController.toggle(category, value);
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.settingsScaffoldTitle),
        actions: [
          IconButton(
            key: const Key('settings_library_button'),
            icon: const Icon(Icons.grid_view),
            tooltip: l10n.settingsLibraryTooltip,
            onPressed: widget.onNavigateToLibrary,
          ),
          IconButton(
            key: const Key('settings_source_button'),
            icon: const Icon(Icons.cloud_download),
            tooltip: l10n.settingsSourceTooltip,
            onPressed: widget.onNavigateToSource,
          ),
        ],
      ),
      body: ListView(
        children: [
          EBSectionHeader(title: l10n.settingsAppearanceSectionTitle),
          _SettingsCard(
            child: ListTile(
              title: Text(l10n.settingsThemeLabel),
              subtitle: widget.appearance.isEinkMode
                  ? Text(
                      l10n.settingsThemeLockedHint,
                      key: const Key('settings_theme_locked_hint'),
                    )
                  : null,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildThemeDot(
                    context,
                    AppTheme.light,
                    'settings_theme_dot_light',
                  ),
                  _buildThemeDot(
                    context,
                    AppTheme.dark,
                    'settings_theme_dot_dark',
                  ),
                  _buildThemeDot(
                    context,
                    AppTheme.sepia,
                    'settings_theme_dot_sepia',
                  ),
                ],
              ),
            ),
          ),
          _SettingsCard(
            child: ListTile(
              key: const Key('settings_language_button'),
              title: Text(l10n.settingsLanguageTitle),
              subtitle: _buildLanguageSubtitle(context, l10n),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _openLanguagePicker(context, l10n),
            ),
          ),
          _SettingsCard(
            child: SwitchListTile(
              key: const Key('settings_eink_mode_switch'),
              title: Text(l10n.settingsEinkModeLabel),
              subtitle: Text(l10n.settingsEinkModeSubtitle),
              value: widget.appearance.isEinkMode,
              onChanged: widget.appearance.onEinkModeChanged,
            ),
          ),
          _SettingsCard(
            child: ListTile(
              key: const Key('settings_font_management_button'),
              title: Text(l10n.settingsFontManagementLabel),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => FontManagementScreen(
                      repository: widget.readerFeatures.customFontsRepository,
                      downloadableFontStore:
                          widget.readerFeatures.downloadableFontStore,
                    ),
                  ),
                );
              },
            ),
          ),
          EBSectionHeader(title: l10n.settingsReadingSectionTitle),
          _SettingsCard(
            child: ListTile(
              key: const Key('settings_reading_defaults_button'),
              title: Text(l10n.settingsReadingDefaultsLabel),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => ReadingDefaultsScreen(
                      prefsManager: widget.readerFeatures.prefsManager,
                    ),
                  ),
                );
              },
            ),
          ),
          _SettingsCard(
            child: ListTile(
              key: const Key('settings_nav_zone_button'),
              title: Text(l10n.settingsNavZoneLabel),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => NavZoneSettingsScreen(
                      prefsManager: widget.readerFeatures.prefsManager,
                    ),
                  ),
                );
              },
            ),
          ),
          _SettingsCard(
            child: ListTile(
              key: const Key('settings_tts_defaults_button'),
              title: Text(l10n.settingsTtsDefaultsLabel),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => TtsDefaultsScreen(
                      prefsManager: widget.readerFeatures.prefsManager,
                      ttsProvider: widget.readerFeatures.ttsProvider,
                      isEinkMode: widget.appearance.isEinkMode,
                    ),
                  ),
                );
              },
            ),
          ),
          _SettingsCard(
            child: ListTile(
              key: const Key('settings_reading_stats_button'),
              title: Text(l10n.statsScreenTitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => ReadingStatsScreen(
                      repository: widget.readerFeatures.readingStatsRepository,
                    ),
                  ),
                );
              },
            ),
          ),
          if (!widget.readerFeatures.isFullTextSearchAvailable)
            _SettingsCard(
              child: ListTile(
                key: const Key('settings_full_text_search_unavailable_hint'),
                leading: const Icon(Icons.info_outline),
                title: Text(l10n.settingsFullTextSearchUnavailableLabel),
                subtitle: Text(l10n.settingsFullTextSearchUnavailableSubtitle),
              ),
            )
          else ...[
            _SettingsCard(
              child: ListTile(
                title: Text(l10n.settingsFullTextSearchPdfLabel),
                subtitle: Text(l10n.settingsFullTextSearchPdfSubtitle),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      key: const Key(
                        'settings_full_text_search_pdf_rebuild_button',
                      ),
                      icon: const Icon(Icons.refresh),
                      tooltip: l10n.settingsFullTextSearchRebuildIndexTooltip,
                      onPressed: !_fullTextSearchTogglesController.pdfEnabled
                          ? null
                          : () => widget
                                .readerFeatures
                                .fullTextSearchSettingsRepository
                                .rebuildIndex(ContentIndexCategory.pdf),
                    ),
                    Switch(
                      key: const Key('settings_full_text_search_pdf_switch'),
                      value: _fullTextSearchTogglesController.pdfEnabled,
                      onChanged: (value) => _handleFullTextSearchToggle(
                        ContentIndexCategory.pdf,
                        value,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            _SettingsCard(
              child: ListTile(
                title: Text(l10n.settingsFullTextSearchFoliateLabel),
                subtitle: Text(l10n.settingsFullTextSearchFoliateSubtitle),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      key: const Key(
                        'settings_full_text_search_foliate_rebuild_button',
                      ),
                      icon: const Icon(Icons.refresh),
                      tooltip: l10n.settingsFullTextSearchRebuildIndexTooltip,
                      onPressed:
                          !_fullTextSearchTogglesController.foliateEnabled
                          ? null
                          : () => widget
                                .readerFeatures
                                .fullTextSearchSettingsRepository
                                .rebuildIndex(ContentIndexCategory.foliate),
                    ),
                    Switch(
                      key: const Key(
                        'settings_full_text_search_foliate_switch',
                      ),
                      value: _fullTextSearchTogglesController.foliateEnabled,
                      onChanged: (value) => _handleFullTextSearchToggle(
                        ContentIndexCategory.foliate,
                        value,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          EBSectionHeader(title: l10n.settingsSyncAccountSectionTitle),
          _SettingsCard(
            child: ListTile(
              key: const Key('settings_sync_button'),
              title: Text(l10n.settingsSyncLabel),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => SyncSettingsScreen(
                      accountRepository: widget.sync.syncAccountRepository,
                      syncClient: widget.sync.syncClient,
                      onManualSync: widget.sync.onManualSync,
                      loadLastSyncedAt: widget.sync.loadLastSyncedAt,
                    ),
                  ),
                );
              },
            ),
          ),
          _SettingsCard(
            child: ListTile(
              key: const Key('settings_cloud_account_button'),
              title: Text(l10n.settingsCloudAccountLabel),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => CloudAccountSettingsScreen(
                      cloudAccountRepository:
                          widget.sources.cloudAccountRepository,
                      googleDriveOAuthClient:
                          widget.sources.googleDriveOAuthClient,
                      oneDriveOAuthClient: widget.sources.oneDriveOAuthClient,
                    ),
                  ),
                );
              },
            ),
          ),
          EBSectionHeader(title: l10n.settingsAboutSectionTitle),
          _SettingsCard(
            child: ListTile(
              key: const Key('settings_about_button'),
              title: Text(l10n.settingsAboutLabel),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (context) => const AboutScreen()),
                );
              },
            ),
          ),
          _SettingsCard(
            child: ListTile(
              key: const Key('settings_reader_console_log_button'),
              title: Text(l10n.settingsReaderConsoleLogLabel),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const ReaderConsoleLogScreen(),
                  ),
                );
              },
            ),
          ),
          _SettingsCard(
            child: SwitchListTile(
              key: const Key('settings_console_log_switch'),
              title: Text(l10n.settingsConsoleLogInterceptLabel),
              subtitle: Text(l10n.settingsConsoleLogInterceptSubtitle),
              value: _consoleLogEnabled,
              onChanged: (value) => _updateConsoleLogEnabled(value),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThemeDot(BuildContext context, AppTheme theme, String key) {
    final l10n = AppLocalizations.of(context)!;
    final previewTheme = resolveThemeData(theme: theme, isEinkMode: false);
    final locked = widget.appearance.isEinkMode;
    final isCurrentTheme = widget.appearance.currentTheme == theme;
    final isSelected = isCurrentTheme && !locked;
    return Semantics(
      label: locked
          ? l10n.settingsThemeDotLockedSemanticsLabel(
              _themeLabel(theme, l10n),
              _themeLabel(widget.appearance.currentTheme, l10n),
            )
          : l10n.settingsThemeDotSemanticsLabel(_themeLabel(theme, l10n)),
      button: !locked,
      child: GestureDetector(
        key: Key(key),
        onTap: locked ? null : () => widget.appearance.onThemeChanged(theme),
        child: Container(
          width: 24,
          height: 24,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: previewTheme.scaffoldBackgroundColor,
            shape: BoxShape.circle,
            border: locked
                ? null
                : Border.all(
                    color: isSelected
                        ? previewTheme.colorScheme.primary
                        : previewTheme.colorScheme.outline,
                    width: isSelected ? 2 : 1,
                  ),
          ),
          child: locked
              ? CustomPaint(
                  painter: _LockedDotBorderPainter(
                    color: Theme.of(context).colorScheme.onSurface,
                    strokeWidth: isCurrentTheme ? 3 : 1.5,
                  ),
                )
              : null,
        ),
      ),
    );
  }

  String _themeLabel(AppTheme theme, AppLocalizations l10n) => switch (theme) {
    AppTheme.light => l10n.settingsThemeLight,
    AppTheme.dark => l10n.settingsThemeDark,
    AppTheme.sepia => l10n.settingsThemeSepia,
  };

  Widget _buildLanguageSubtitle(BuildContext context, AppLocalizations l10n) {
    final override = widget.appearance.currentLocaleOverride;
    if (override != null) {
      return Text(_languageLabel(override, l10n));
    }
    final resolved = resolveSupportedLocale(
      View.of(context).platformDispatcher.locale,
    );
    final resolvedLabel = _languageLabel(resolved, l10n);
    return Text(l10n.settingsLanguageFollowSystemSubtitle(resolvedLabel));
  }

  String _languageLabel(AppLocale locale, AppLocalizations l10n) =>
      switch (locale) {
        AppLocale.zhTW => l10n.settingsLanguageZhTW,
        AppLocale.zhCN => l10n.settingsLanguageZhCN,
        AppLocale.en => l10n.settingsLanguageEn,
      };

  Future<void> _openLanguagePicker(
    BuildContext context,
    AppLocalizations l10n,
  ) async {
    final choice = await EBSheetShell.show<_LocaleChoice>(
      context,
      title: l10n.settingsLanguageTitle,
      isEinkMode: widget.appearance.isEinkMode,
      builder: (context) => _LanguagePickerSheet(
        currentLocaleOverride: widget.appearance.currentLocaleOverride,
      ),
    );
    if (choice == null) return;
    widget.appearance.onLocaleChanged(choice.value);
  }
}

/// 視覺還原（Visual Accuracy Mode，`docs/research/uiux/VISUAL_ANALYSIS.md`）：
/// Reference 截圖的設定畫面每個項目都是獨立、有邊框、彼此間有間距的卡片，
/// 不是原本連續 `ListTile`＋細分隔線的清單樣式。改用共用的 [EBFieldCard]
/// （套用全域已定案的 `CardTheme`，見 `app_theme_data.dart`）逐一包裹每個
/// 項目，取代原本插在各分區之間的 `Divider`——分區間距改由
/// `EBSectionHeader` 既有的頂部留白（`fromLTRB(16, 24, 16, 8)`）承擔，
/// 不需要額外的分隔線或間距元件。本類別只是針對本畫面情境（`ListTile`／
/// `SwitchListTile` 已自帶內距、外層 `ListView` 無水平 padding）固定住
/// [EBFieldCard] 的 `padding`／`margin` 參數，避免每個呼叫點都要重複填寫
/// 同一組數值，不是重新實作一次卡片包裝邏輯。
class _SettingsCard extends StatelessWidget {
  final Widget child;

  const _SettingsCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return EBFieldCard(
      padding: EdgeInsets.zero,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: child,
    );
  }
}

/// E-Ink 鎖定狀態的圓形虛線邊框（`DESIGN.md` §17.2：邊框改為虛線，取代
/// 原本的降低透明度手法）。
class _LockedDotBorderPainter extends CustomPainter {
  const _LockedDotBorderPainter({
    required this.color,
    required this.strokeWidth,
  });

  final Color color;
  final double strokeWidth;

  static const double _dashLength = 3;
  static const double _gapLength = 3;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = (size.shortestSide - strokeWidth) / 2;
    final center = Offset(size.width / 2, size.height / 2);
    final path = Path()
      ..addOval(Rect.fromCircle(center: center, radius: radius));
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = distance + _dashLength;
        canvas.drawPath(
          metric.extractPath(distance, next.clamp(0, metric.length)),
          paint,
        );
        distance = next + _gapLength;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _LockedDotBorderPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.strokeWidth != strokeWidth;
}

/// [EBSheetShell.show] 的回傳型別包裝：`null`（整個 Future 的結果）代表
/// 使用者未選取任何選項就關閉 Sheet（滑動/點擊外部），[_LocaleChoice.value]
/// 才是使用者實際選取的語言——`value` 本身也可能是 `null`（代表「跟隨
/// 系統」），兩種「null」意義不同，若不用這層包裝、直接讓
/// `EBSheetShell.show<AppLocale?>` 回傳 `AppLocale?`，會無法分辨「使用者選了跟隨系統」
/// 與「使用者什麼都沒選就關閉」。
class _LocaleChoice {
  final AppLocale? value;

  const _LocaleChoice(this.value);
}

class _LanguagePickerSheet extends StatelessWidget {
  final AppLocale? currentLocaleOverride;

  const _LanguagePickerSheet({required this.currentLocaleOverride});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // 【/receiving-code-review I-1 修正】`RadioListTile.groupValue`／
    // `onChanged` 已棄用（見 reading_defaults_screen.dart／commit
    // 5fa3f5bb 既有慣例），改用外層 `RadioGroup<T>` 統一管理選中值與變更
    // 回呼，個別 `RadioListTile` 只宣告自己的 `value`。
    //
    // 【/receiving-code-review M-2 補述】Radio 的原生行為是「點擊與
    // groupValue 相同的選項不會觸發 onChanged」——若使用者打開選擇器後
    // 點擊「目前已選中的語言」，Sheet 不會自動關閉（需手動點右上角關閉或
    // 點遮罩），這是符合預期的單選元件原生行為，不是缺陷；未來若要優化
    // 這個互動（例如點擊已選中項也能關閉），需另外包一層 `GestureDetector`
    // /`InkWell`，不在本 Issue 範圍內。
    return RadioGroup<AppLocale?>(
      groupValue: currentLocaleOverride,
      onChanged: (value) => Navigator.of(context).pop(_LocaleChoice(value)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          RadioListTile<AppLocale?>(
            key: const Key('settings_language_option_follow_system'),
            title: Text(l10n.settingsLanguageFollowSystem),
            value: null,
          ),
          RadioListTile<AppLocale?>(
            key: const Key('settings_language_option_zh_tw'),
            title: Text(l10n.settingsLanguageZhTW),
            value: AppLocale.zhTW,
          ),
          RadioListTile<AppLocale?>(
            key: const Key('settings_language_option_zh_cn'),
            title: Text(l10n.settingsLanguageZhCN),
            value: AppLocale.zhCN,
          ),
          RadioListTile<AppLocale?>(
            key: const Key('settings_language_option_en'),
            title: Text(l10n.settingsLanguageEn),
            value: AppLocale.en,
          ),
        ],
      ),
    );
  }
}
