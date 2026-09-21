import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

import '../reader/pdf_search_state.dart';

/// PDF 內文搜尋面板（epic-24-pdf-engine-rebuild Issue 6），掛載於
/// `TocBottomSheet` 的「搜尋」分頁（`TocBottomSheet.searchTabContent`）。
/// 與 `ReaderScreen`／`PdfReaderView` 完全解耦：只透過 [onQueryChanged]／
/// [onNext]／[onPrevious] 回呼與 [searchStateListenable] 溝通，本身不知道
/// 呼叫端如何實際執行搜尋。
///
/// 輸入框變動後套用 500ms 防手震延遲才觸發 [onQueryChanged]，避免使用者
/// 每輸入一個字元就觸發一次全文搜尋；清空輸入框時例外，立即觸發（讓畫面
/// 立刻清空搜尋結果與高亮，不需要额外等待）。
class PdfSearchPanel extends StatefulWidget {
  final ValueListenable<PdfSearchState> searchStateListenable;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onNext;
  final VoidCallback onPrevious;

  /// Bottom Sheet 重新開啟時，若使用者先前已有查詢字串，預先填入輸入框
  /// （不會自動觸發 [onQueryChanged]——呼叫端已經持有對應的搜尋結果，
  /// 不需要重新搜尋一次）。
  final String initialQuery;

  const PdfSearchPanel({
    super.key,
    required this.searchStateListenable,
    required this.onQueryChanged,
    required this.onNext,
    required this.onPrevious,
    this.initialQuery = '',
  });

  @override
  State<PdfSearchPanel> createState() => _PdfSearchPanelState();
}

class _PdfSearchPanelState extends State<PdfSearchPanel> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialQuery);
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _handleChanged(String value) {
    _debounce?.cancel();
    if (value.isEmpty) {
      widget.onQueryChanged('');
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 500), () {
      widget.onQueryChanged(value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const Key('pdf_search_field'),
            controller: _controller,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: l10n.readerPdfSearchHint,
              prefixIcon: const Icon(Icons.search),
            ),
            onChanged: _handleChanged,
          ),
          const SizedBox(height: 12),
          ValueListenableBuilder<PdfSearchState>(
            valueListenable: widget.searchStateListenable,
            builder: (context, state, _) {
              if (state.query.isEmpty) return const SizedBox.shrink();
              if (state.isSearching) {
                return const Padding(
                  key: Key('pdf_search_loading'),
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (state.matchCount == 0) {
                return Padding(
                  key: const Key('pdf_search_empty'),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Center(child: Text(l10n.readerPdfSearchNoMatches)),
                );
              }
              return Row(
                key: const Key('pdf_search_counter'),
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('${(state.currentIndex ?? 0) + 1} / ${state.matchCount}'),
                  Row(
                    children: [
                      IconButton(
                        key: const Key('pdf_search_prev_button'),
                        icon: const Icon(Icons.keyboard_arrow_up),
                        tooltip: l10n.readerPdfSearchPreviousTooltip,
                        onPressed: widget.onPrevious,
                      ),
                      IconButton(
                        key: const Key('pdf_search_next_button'),
                        icon: const Icon(Icons.keyboard_arrow_down),
                        tooltip: l10n.readerPdfSearchNextTooltip,
                        onPressed: widget.onNext,
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
