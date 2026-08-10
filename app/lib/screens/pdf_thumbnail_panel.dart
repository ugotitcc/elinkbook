import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../reader/pdf_thumbnail_cache.dart';

/// PDF 頁碼縮圖面板（epic-24-pdf-engine-rebuild Issue 7），掛載於
/// `TocBottomSheet` 的「縮圖」分頁（`TocBottomSheet.thumbnailTabContent`）。
/// 與 `ReaderScreen`／`PdfReaderView` 完全解耦（比照 `PdfSearchPanel`
/// 既有設計原則）：只透過 [renderThumbnail] 取得縮圖影像、透過
/// [onPageSelected] 回報選取，本身不知道呼叫端如何實際渲染 PDF 頁面、
/// 不直接依賴 `GlobalKey<State<PdfReaderView>>` 或 `PdfDocument`。
///
/// 縮圖僅於可視附近範圍內產生：`GridView.builder` 只會對接近可視範圍的
/// 索引呼叫 `itemBuilder`（Flutter 既有的 sliver 延遲建構機制），本
/// widget 不會在初次建構時就對全書每一頁呼叫 [renderThumbnail]。另外
/// 維護一個獨立於 `GridView` 版面回收機制的 [PdfThumbnailCache]（上限
/// [_maxCachedThumbnails] 張），確保無論捲動模式為何，記憶體中存活的
/// 縮圖影像數量有明確上限，超出上限時最舊使用的影像會被 `dispose()`
/// 釋放——比照既有 `_PdfReaderViewState._boldOverlayImages`（Issue 3）的
/// LRU 快取設計精神。
class PdfThumbnailPanel extends StatefulWidget {
  final int totalPages;
  final Future<ui.Image?> Function(int pageIndex) renderThumbnail;
  final ValueChanged<int> onPageSelected;

  const PdfThumbnailPanel({
    super.key,
    required this.totalPages,
    required this.renderThumbnail,
    required this.onPageSelected,
  });

  @override
  State<PdfThumbnailPanel> createState() => _PdfThumbnailPanelState();
}

class _PdfThumbnailPanelState extends State<PdfThumbnailPanel> {
  static const _maxCachedThumbnails = 24;

  late final _cache = PdfThumbnailCache<ui.Image>(
    maxSize: _maxCachedThumbnails,
    dispose: (image) => image.dispose(),
  );

  /// 防止同一個 [pageIndex] 在前一次 [renderThumbnail] 尚未完成時被重複
  /// 觸發（`GridView.builder` 可能在同一個索引仍在載入中時多次呼叫
  /// `itemBuilder`，例如捲動觸發的重建）。
  final _pending = <int>{};

  @override
  void dispose() {
    _cache.clear();
    super.dispose();
  }

  /// 面板已 unmount 時（`!mounted`）仍要 `image?.dispose()` 才 return——
  /// 非同步渲染完成當下面板可能已被移除（例如使用者已關閉 Bottom
  /// Sheet），此時回傳的 `ui.Image` 不會再被放進 [_cache]、也不會有機會
  /// 透過 [_cache] 的正常淘汰路徑釋放，若在這裡直接捨棄會造成原生記憶體
  /// （C++/GPU 端）洩漏。`_pending.remove` 改放進 `.whenComplete()`，
  /// 確保無論 [renderThumbnail] 成功、失敗或（理論上）被取消，都會執行，
  /// 避免非同步例外導致 `pageIndex` 永久卡在 [_pending]、使用者捲動回該頁
  /// 時 [_load] 恆被擋下、縮圖格永久停留在載入指示器（審查修正）。
  void _load(int pageIndex) {
    if (_pending.contains(pageIndex) || _cache.contains(pageIndex)) return;
    _pending.add(pageIndex);
    unawaited(
      widget.renderThumbnail(pageIndex).then((image) {
        if (!mounted || image == null) {
          image?.dispose();
          return;
        }
        setState(() => _cache.put(pageIndex, image));
      }).whenComplete(() {
        _pending.remove(pageIndex);
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.totalPages <= 0) {
      return const Center(
        key: Key('pdf_thumbnail_panel_empty'),
        child: Text('無可用頁面'),
      );
    }
    return GridView.builder(
      key: const Key('pdf_thumbnail_panel_grid'),
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 0.7,
      ),
      itemCount: widget.totalPages,
      itemBuilder: (context, index) {
        final image = _cache.get(index);
        if (image == null) _load(index);
        return InkWell(
          key: Key('pdf_thumbnail_tile_$index'),
          onTap: () => widget.onPageSelected(index),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Expanded(
                child: image == null
                    ? const Center(child: CircularProgressIndicator())
                    : RawImage(image: image, fit: BoxFit.contain),
              ),
              Text('${index + 1}'),
            ],
          ),
        );
      },
    );
  }
}
