// app/lib/screens/reading_stats_screen.dart
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';
import '../stats/daily_book_reading_stat.dart';
import '../stats/heatmap_grid.dart';
import '../stats/reading_duration_format.dart';
import '../stats/reading_stats_repository.dart';
import '../theme/elink_tokens.dart';
import 'widgets/eb_field_card.dart';
import 'widgets/reading_heatmap.dart';

/// 閱讀統計畫面（epic-9-stats Issue 5，入口在設定頁）：累計總時數、近 365 天
/// 貢獻圖、貢獻圖下方固定的當日詳情卡片，以及底部的「清除全部統計」。
///
/// 唯讀顯示 [repository] 的資料（清除除外）；詳情一律顯示在固定卡片，不使用
/// Tooltip 或任何浮動層（E-Ink 友善）。資料只在進入畫面與清除後載入。
class ReadingStatsScreen extends StatefulWidget {
  final ReadingStatsRepository repository;

  /// 取得「現在」的時間來源；預設 `clock.now`，測試可注入固定日期。
  final DateTime Function()? nowProvider;

  const ReadingStatsScreen({
    super.key,
    required this.repository,
    this.nowProvider,
  });

  @override
  State<ReadingStatsScreen> createState() => _ReadingStatsScreenState();
}

class _ReadingStatsScreenState extends State<ReadingStatsScreen> {
  final ScrollController _scrollController = ScrollController();
  late final HeatmapGrid _grid;
  late final String _todayKey;

  bool _loading = true;

  /// 讀取資料失敗：顯示錯誤文字取代載入中圖示（成功載入後會清回 false）。
  bool _loadFailed = false;
  bool _didScrollToEnd = false;
  Map<String, int> _dailyTotals = const {};
  int _totalSeconds = 0;

  /// 目前選取的日期，與 [_details] 同步更新（見 [_selectDate]）。
  late String _selectedDate;
  List<DailyBookReadingStat> _details = const [];

  /// 詳情查詢的請求序號：快速連點時，只有最後一次發出的查詢結果會被採用。
  int _detailRequestId = 0;

  /// 整體載入（[_loadAll]）的請求序號，與 [_detailRequestId] 分開：清除後重載
  /// 期間使用者點了方格，只能讓重載的「選取日／詳情」被丟棄，不能連累累計
  /// 時數與貢獻圖各日總計（資料已清空，一定要套用）。
  int _loadRequestId = 0;

  @override
  void initState() {
    super.initState();
    final today = (widget.nowProvider ?? clock.now)();
    _grid = buildHeatmapGrid(today);
    _todayKey = _grid.endDate;
    _selectedDate = _todayKey;
    _loadAll();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// 載入貢獻圖各日總計、累計總時數與詳情。詳情預設載入目前選取日；
  /// 傳入 [selecting] 則改載入該日並一併切換選取（清除後用它回到今天）。
  Future<void> _loadAll({String? selecting}) async {
    final loadId = ++_loadRequestId;
    final detailId = ++_detailRequestId;
    final repository = widget.repository;
    final date = selecting ?? _selectedDate;
    final Map<String, int> totals;
    final int total;
    final List<DailyBookReadingStat> details;
    try {
      totals = await repository.getDailyTotals(
        startDate: _grid.startDate,
        endDate: _grid.endDate,
      );
      total = await repository.getTotalReadingSeconds();
      details = await repository.getBookStatsForDate(date);
    } catch (_) {
      // 讀取失敗不可讓畫面永遠停在載入中；同樣只有最新一次載入才能更新畫面
      if (!mounted || loadId != _loadRequestId) return;
      setState(() {
        _loadFailed = true;
        _loading = false;
      });
      return;
    }
    // 有更新的整體載入發出就整批丟棄；否則總計一律套用，
    // 選取日／詳情則僅在期間沒被使用者點選覆蓋時才套用
    if (!mounted || loadId != _loadRequestId) return;
    setState(() {
      _dailyTotals = totals;
      _totalSeconds = total;
      _loading = false;
      _loadFailed = false;
      if (detailId == _detailRequestId) {
        _selectedDate = date;
        _details = details;
      }
    });
    _scrollToEndOnce();
  }

  /// 首次載入完成後把貢獻圖捲到最右側（今天所在的一週）。
  void _scrollToEndOnce() {
    if (_didScrollToEnd) return;
    _didScrollToEnd = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
  }

  /// 選取某一天：查完該日詳情後才**同時**更新外框與詳情，避免外框與詳情
  /// 短暫對不上；請求序號讓過期（較早發出但較晚回來）的結果被丟棄。
  Future<void> _selectDate(String date) async {
    final requestId = ++_detailRequestId;
    final details = await widget.repository.getBookStatsForDate(date);
    if (!mounted || requestId != _detailRequestId) return;
    setState(() {
      _selectedDate = date;
      _details = details;
    });
  }

  Future<void> _confirmAndClear() async {
    final confirmed = await _showClearConfirmDialog();
    if (confirmed != true || !mounted) return;
    await widget.repository.clearAllStats();
    if (!mounted) return;
    // 「回到空白狀態」＝與全新開啟畫面一致：選取日重置為今天，不停留在歷史日期
    await _loadAll(selecting: _todayKey);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        key: const Key('reading_stats_clear_success_snackbar'),
        content: Text(AppLocalizations.of(context)!.statsClearAllSuccess),
      ),
    );
  }

  /// 破壞性操作確認（`DESIGN.md` §9.1／§9.2）：寬度上限 400dp、主動作靠右、
  /// 確認鈕用 `error` 色並標明具體後果；E-Ink 下不淡入淡出。
  Future<bool?> _showClearConfirmDialog() {
    final isEink =
        Theme.of(context).extension<ElinkTokens>()?.isEink ?? false;
    return showDialog<bool>(
      context: context,
      animationStyle: isEink ? AnimationStyle.noAnimation : null,
      builder: (dialogContext) {
        final l10n = AppLocalizations.of(dialogContext)!;
        return AlertDialog(
          key: const Key('reading_stats_clear_all_dialog'),
          title: Text(l10n.statsClearAllTitle),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Text(l10n.statsClearAllConfirmMessage),
          ),
          actions: [
            TextButton(
              key: const Key('reading_stats_clear_all_cancel_button'),
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.cancel),
            ),
            TextButton(
              key: const Key('reading_stats_clear_all_confirm_button'),
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(dialogContext).colorScheme.error,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.statsClearAllTitle),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.statsScreenTitle)),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(
                key: Key('reading_stats_loading'),
              ),
            )
          : _loadFailed
              ? Center(
                  child: Text(
                    l10n.statsLoadFailed,
                    key: const Key('reading_stats_error_text'),
                  ),
                )
              : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                _buildTotalCard(context, l10n),
                _buildHeatmapCard(),
                _buildDetailCard(context, l10n),
                const SizedBox(height: 8),
                SizedBox(
                  height: 48,
                  child: OutlinedButton(
                    key: const Key('reading_stats_clear_all_button'),
                    onPressed: _confirmAndClear,
                    child: Text(l10n.statsClearAllTitle),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildTotalCard(BuildContext context, AppLocalizations l10n) {
    final textTheme = Theme.of(context).textTheme;
    return EBFieldCard(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: SizedBox(
        width: double.infinity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.statsTotalDuration, style: textTheme.bodySmall),
            const SizedBox(height: 4),
            Text(
              formatReadingDuration(l10n, _totalSeconds),
              key: const Key('reading_stats_total_text'),
              style:
                  textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeatmapCard() {
    return EBFieldCard(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: [
          ReadingHeatmap(
            grid: _grid,
            dailyTotals: _dailyTotals,
            selectedDate: _selectedDate,
            onSelectDate: _selectDate,
            scrollController: _scrollController,
          ),
          const SizedBox(height: 8),
          const ReadingHeatmapLegend(),
        ],
      ),
    );
  }

  Widget _buildDetailCard(BuildContext context, AppLocalizations l10n) {
    final textTheme = Theme.of(context).textTheme;
    final dateLabel = DateFormat.yMd(l10n.localeName)
        .format(DateTime.parse(_selectedDate));
    return EBFieldCard(
      key: const Key('reading_stats_daily_detail_card'),
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: SizedBox(
        width: double.infinity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.statsDailyDetailsTitle(dateLabel),
              key: const Key('reading_stats_detail_title'),
              style: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 4),
            if (_details.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  l10n.statsNoDataOnDate,
                  key: const Key('reading_stats_detail_empty'),
                  style: textTheme.bodySmall,
                ),
              )
            else
              for (final stat in _details)
                Padding(
                  key: Key('reading_stats_detail_row_${stat.bookId}'),
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          // 書名快照若為空白，退回書籍 id，避免出現只有時數的空白列
                          stat.bookTitle.trim().isEmpty
                              ? stat.bookId
                              : stat.bookTitle,
                          style: textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        formatReadingDuration(l10n, stat.readingSeconds),
                        style: textTheme.bodySmall
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
