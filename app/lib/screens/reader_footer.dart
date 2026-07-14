import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 閱讀畫面頁尾（Epic 5 Issue 1，FR-22/23/40）：顯示閱讀進度百分比與
/// 「目前頁碼／總頁數」，並提供跳頁互動（輸入框 + 滑桿雙向同步）。
///
/// 格式無關——只接收 [currentPage]／[totalPages]／[onPageChanged] 三個
/// 與格式無關的屬性（`/superpowers:requesting-code-review` 審查修正的
/// 介面契約），不含任何 PDF 或 EPUB 專屬邏輯，供 Issue 3 直接複用於
/// EPUB（EPUB 端的估算頁碼與精確度差異由呼叫端負責，本元件不需知道）。
///
/// [currentPage]／[totalPages] 皆為 **1-indexed**（自然的人類頁碼直覺），
/// 呼叫端負責與底層 0-indexed 的原生頁碼互相轉換（見 ReaderScreen）。
///
/// 版面配置比照 `prototype/index.html` 的 `.reader-footer` 既有設計：佔用
/// 固定版面空間的實體列（由呼叫端以 Column 排版擠壓閱讀區域高度），非
/// 浮動疊加層——本 widget 本身不處理佈局位置，只負責自身內容。
class ReaderFooter extends StatefulWidget {
  final int currentPage;
  final int totalPages;
  final ValueChanged<int> onPageChanged;

  const ReaderFooter({
    super.key,
    required this.currentPage,
    required this.totalPages,
    required this.onPageChanged,
  });

  @override
  State<ReaderFooter> createState() => _ReaderFooterState();
}

class _ReaderFooterState extends State<ReaderFooter> {
  late TextEditingController _inputController;
  late double _sliderValue;

  @override
  void initState() {
    super.initState();
    _inputController = TextEditingController(text: '${widget.currentPage}');
    _sliderValue = widget.currentPage.toDouble();
  }

  @override
  void didUpdateWidget(covariant ReaderFooter oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 外部（原生端翻頁回報）造成 currentPage 變動時，同步輸入框與滑桿；
    // 避免使用者正在輸入時被外部狀態打斷，只在數字真的不同時才更新。
    if (widget.currentPage != oldWidget.currentPage) {
      _inputController.text = '${widget.currentPage}';
      _sliderValue = widget.currentPage.toDouble();
    }
  }

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  /// 把使用者輸入/拖曳的值箝制在合法範圍 [1, totalPages] 內。
  int _clamp(int page) => page.clamp(1, widget.totalPages);

  void _handleSliderChangeEnd(double value) {
    final clamped = _clamp(value.round());
    setState(() {
      _sliderValue = clamped.toDouble();
      _inputController.text = '$clamped';
    });
    widget.onPageChanged(clamped);
  }

  void _handleInputSubmitted(String value) {
    final parsed = int.tryParse(value);
    final clamped = _clamp(parsed ?? widget.currentPage);
    setState(() {
      _inputController.text = '$clamped';
      _sliderValue = clamped.toDouble();
    });
    widget.onPageChanged(clamped);
    // 審查修正：跳頁完成後主動收起鍵盤與輸入框焦點，避免鍵盤持續佔用畫面
    // 遮擋閱讀內容。
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final progressPercent =
        widget.totalPages > 0 ? (widget.currentPage / widget.totalPages * 100).round() : 0;
    return Container(
      key: const Key('reader_footer'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            key: const Key('reader_footer_progress_text'),
            '進度 $progressPercent% ｜ 第 ${widget.currentPage}/${widget.totalPages} 頁',
          ),
          Row(
            children: [
              SizedBox(
                width: 56,
                child: TextField(
                  key: const Key('reader_footer_jump_input'),
                  controller: _inputController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  textAlign: TextAlign.center,
                  onSubmitted: _handleInputSubmitted,
                ),
              ),
              Expanded(
                child: Slider(
                  key: const Key('reader_footer_jump_slider'),
                  value: _sliderValue.clamp(1, widget.totalPages.toDouble()),
                  min: 1,
                  max: widget.totalPages > 1 ? widget.totalPages.toDouble() : 2,
                  divisions: widget.totalPages > 1 ? widget.totalPages - 1 : 1,
                  // 審查修正：總頁數只有 1 頁時，拖曳滑桿沒有實際意義（無處
                  // 可跳），停用（onChanged/onChangeEnd 皆傳 null）讓 Slider
                  // 視覺上呈現不可互動狀態，比只靠 max/divisions 防呆更直覺。
                  onChanged: widget.totalPages > 1
                      ? (v) => setState(() {
                            _sliderValue = v;
                            _inputController.text = '${v.round()}';
                          })
                      : null,
                  onChangeEnd: widget.totalPages > 1 ? _handleSliderChangeEnd : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
