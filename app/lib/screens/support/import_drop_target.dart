import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../library/book_import_service.dart';
import '../../platform/platform_support.dart';
import 'book_import_picker_helper.dart';
import 'dropped_import.dart';

/// Windows 拖曳檔案或資料夾匯入包裹元件（epic-66 Issue 5 Task 6）。
///
/// - 非 Windows 平台直接回傳 [child]，不掛載 [DropTarget]。
/// - Windows 永遠掛載一層 [DropTarget] 並以 `enable` 控制開關，避免條件式有無包裹
///   造成內層 `IndexedStack` 子畫面 State 重建。
class ImportDropTarget extends StatefulWidget {
  const ImportDropTarget({
    super.key,
    required this.importService,
    required this.isEinkMode,
    required this.enabled,
    this.onImportCompleted,
    required this.child,
  });

  final BookImportService importService;
  final bool isEinkMode;
  final bool enabled;
  final VoidCallback? onImportCompleted;
  final Widget child;

  @override
  State<ImportDropTarget> createState() => _ImportDropTargetState();
}

class _ImportDropTargetState extends State<ImportDropTarget> {
  bool _dragging = false;
  bool _busy = false;

  void _handleDragEntered(DropEventDetails details) {
    if (_busy) return;
    if (!_dragging) {
      setState(() => _dragging = true);
    }
  }

  void _handleDragExited(DropEventDetails details) {
    if (_dragging) {
      setState(() => _dragging = false);
    }
  }

  Future<void> _handleDragDone(DropDoneDetails details) async {
    if (_dragging) {
      setState(() => _dragging = false);
    }
    if (details.files.isEmpty) return;

    if (_busy) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.importDropBusyMessage)),
      );
      return;
    }

    _busy = true;
    try {
      final paths = details.files.map((f) => f.path).toList();
      final result = await importDroppedPaths(
        widget.importService,
        paths,
        confirmAutoGroup: () => context.mounted
            ? confirmAutoGroupByFolderName(context)
            : Future.value(null),
      );
      if (result == null) return;
      if (!mounted) {
        await discardUpdateCandidates(
          widget.importService,
          result.updateCandidates,
        );
        return;
      }
      showImportResultSnackBar(context, result);
      await handleImportUpdateCandidates(
        context,
        widget.importService,
        result,
        isEinkMode: widget.isEinkMode,
      );
      if (!mounted) return;
      if (result.importedBooks.isNotEmpty ||
          result.updateCandidates.isNotEmpty) {
        widget.onImportCompleted?.call();
      }
    } finally {
      if (mounted) {
        _busy = false;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!isWindowsPlatform) {
      return widget.child;
    }
    final isCurrentRoute = ModalRoute.of(context)?.isCurrent ?? true;
    return DropTarget(
      enable: widget.enabled && isCurrentRoute,
      onDragEntered: _handleDragEntered,
      onDragExited: _handleDragExited,
      onDragDone: _handleDragDone,
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          widget.child,
          if (_dragging)
            Positioned.fill(
              child: IgnorePointer(
                child: ColoredBox(
                  key: const Key('import_drop_overlay'),
                  color: Theme.of(context)
                      .colorScheme
                      .scrim
                      .withValues(alpha: 0.45),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 16,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        AppLocalizations.of(context)!.importDropOverlayText,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
