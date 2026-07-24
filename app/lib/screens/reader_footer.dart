import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 閱讀畫面頁尾（Epic 5 Issue 1，FR-22/23/40；Epic 18 Issue 2 瘦身為單一
/// 列）：單一 Row 內同時顯示「目前頁碼／總頁數」文字、跳頁輸入框，與可
/// 拖曳的進度滑桿（拖曳時的 label 顯示進度百分比），提供跳頁互動（輸入框
/// + 滑桿雙向同步）。
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
/// 浮動疊加層——本 widget 本身不處理佈局位置，只負責自身內容。內部仍以
/// `Column(mainAxisSize: MainAxisSize.min)` 包住單一 `Row`（而非直接把
/// `Row` 當作 `build()` 回傳值）：實測發現若拿掉這層 `Column`，一旦本
/// widget 被直接放在會給予「有限（bounded）但寬鬆」高度上限的容器下
/// （例如既有測試的 `Scaffold(body: ReaderFooter(...))` pump 慣例），內部
/// `Expanded(child: Slider)` 的 `Slider` 會直接撐滿到那個高度上限（`Slider`
/// 在有界但寬鬆的約束下會填滿，不會退回自然高度，是 Flutter 已知行為），
/// 導致頁尾意外變成佔滿整個畫面。包一層 `Column(mainAxisSize.min)` 能讓
/// `Row` 收到「無界（unbounded）」高度上限（`Flex` 對非 flexible 子項在
/// 主軸方向一律給無界上限的既有行為），此時 `Slider` 才會退回自然高度，
/// 在真實 `ReaderScreen`（外層 `Column` 的非 flex 子項）與既有測試的裸
/// `Scaffold.body` 兩種父層情境下都能穩定保持緊湊。
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
        // 見上方類別文件註解「Slider 高度陷阱」完整原因說明——刻意保留，
        // 不是多餘的殘留寫法。
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              SizedBox(
                width: 72,
                child: Text(
                  key: const Key('reader_footer_progress_text'),
                  '${widget.currentPage}/${widget.totalPages}',
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
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
                  // 原本獨立一列的「進度 YY%」文字併入單行版面後，改以
                  // Slider 拖曳時顯示的 label 呈現（issues.md Issue 2）。
                  label: '$progressPercent%',
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
