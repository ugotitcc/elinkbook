import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import '../reader/app_font.dart';
import '../reader/custom_font.dart';
import '../reader/custom_font_relinker.dart';
import '../reader/custom_fonts_repository.dart';
import '../reader/downloadable_font_store.dart';
import '../reader/font_download_catalog.dart';
import '../reader/font_name_parser.dart';
import '../storage/storage_access_probe.dart'
    show StorageAccessProbeResult, probeStorageAccess;
import '../storage/storage_permission.dart';

/// 單檔字型選擇器（epic-15-storage-permission Issue 3：重新連結用）。
/// 回傳選取的 URI、檔名與位元組（位元組用來解析字型家族名稱）；使用者取消
/// 時回傳 `null`。做成可注入的函式型別，讓 widget test 不必觸碰平台實作。
typedef SingleFontFilePicker =
    Future<({String uri, String name, Uint8List bytes})?> Function();

/// [SingleFontFilePicker] 的預設實作：`FilePicker` 單選 ttf／otf。`uri` 是
/// `PlatformFile.identifier`（Android 上為 `content://` URI）；`identifier` 或
/// 位元組為 null（非 Android 平台）視為取消。選擇器拋出例外時比照
/// [pickSingleBookFileViaFilePicker] 視為取消。
Future<({String uri, String name, Uint8List bytes})?>
    pickSingleFontFileViaFilePicker() async {
  try {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['ttf', 'otf'],
      withData: true,
    );
    final file = picked?.files.firstOrNull;
    final uri = file?.identifier;
    final bytes = file?.bytes;
    if (file == null || uri == null || bytes == null) return null;
    return (uri: uri, name: file.name, bytes: bytes);
  } catch (_) {
    return null;
  }
}

/// 字型管理畫面（epic-14-system-settings FR-35，spec.md「字型管理模組」）：
/// 顯示內建字型＋使用者上傳的自訂字型（可重新命名／刪除），支援批次上傳 `.ttf`/`.otf`。
/// epic-49 起內建字型改為可下載字型：注入 [downloadableFontStore] 時，每款內建字型
/// 可以下載、取消、重試、刪除；沒有注入時只顯示名稱（維持既有行為）。
class FontManagementScreen extends StatefulWidget {
  final CustomFontsRepository repository;
  final DownloadableFontStore? downloadableFontStore;

  /// 重新連結用的單檔選擇器（epic-15-storage-permission Issue 3）。`null` 時
  /// 使用 [pickSingleFontFileViaFilePicker]，供 widget test 注入。
  final SingleFontFilePicker? pickSingleFontFile;

  const FontManagementScreen({
    super.key,
    required this.repository,
    this.downloadableFontStore,
    this.pickSingleFontFile,
  });

  @override
  State<FontManagementScreen> createState() => _FontManagementScreenState();
}

class _FontManagementScreenState extends State<FontManagementScreen> {
  List<CustomFont> _customFonts = [];
  bool _isUploading = false;

  // ── 儲存權限失效標示（epic-15-storage-permission Issue 3）──
  /// 字型資料庫主鍵 → 存取探測結果。用 id 而非清單索引：探測期間使用者可能
  /// 刪除或重新命名字型讓清單改變，用 id 對應才不會錯位。
  final Map<int, StorageAccessProbeResult> _probeResults = {};

  /// 已經發出探測的字型 id；清單重新載入時不重複探測。
  final Set<int> _probeRequestedIds = {};

  /// 重新連結處理中的字型 id：該列的動作停用，避免連點重複開選擇器。
  final Set<int> _relinkingIds = {};

  /// 字型重新連結規則（家族名稱比對、授權、更新 URI）；畫面只負責選檔與顯示。
  late final CustomFontRelinker _relinker =
      CustomFontRelinker(repository: widget.repository);
  // 重新命名對話框使用的 TextEditingController，交由本 State 生命週期保管
  // （比照 notes_bottom_sheet.dart 既有先例）：不在 showDialog 呼叫結束後
  // 立即 dispose——showDialog 回傳的 Future 在 Navigator.pop() 當下就完成，
  // 早於 AlertDialog 退場轉場動畫實際跑完，此時其底下的 TextField 仍會在
  // 後續幾個 frame 被重新 build，立即 dispose 會拋出
  // 「TextEditingController used after being disposed」。改為每次重新命名時
  // 若有前一個實例先 dispose，並在 [dispose] 一併清理。
  TextEditingController? _renameController;

  // ── 可下載字型（epic-49）──
  Set<AppFont> _installedFonts = {};

  /// 已下載清單是否已載入。載入前不知道哪些字型已下載，只顯示大小並停用按鈕，
  /// 避免把已下載的字型誤顯示成「未下載」而被重新下載（程式審查 M-5）。
  bool _installedFontsLoaded = false;

  /// 正在下載的字型；同一時間最多一款（下載中時其他內建字型的按鈕全部停用）。
  AppFont? _downloadingFont;
  int _downloadPercent = 0;
  FontDownloadCancellationToken? _downloadToken;

  /// 最近一次下載失敗的字型與原因；重新下載或下載成功時清除。取消不算失敗。
  final Map<AppFont, FontDownloadException> _downloadFailures = {};

  @override
  void initState() {
    super.initState();
    _loadFonts();
    _loadInstalledFonts();
  }

  @override
  void dispose() {
    // 不做背景下載：離開畫面就取消（spec「字型管理畫面」、design.md Q9）
    _downloadToken?.cancel();
    _renameController?.dispose();
    super.dispose();
  }

  Future<void> _loadFonts() async {
    try {
      final fonts = await widget.repository.listAll();
      if (!mounted) return;
      setState(() => _customFonts = fonts);
      _probeNewFonts(fonts);
    } catch (e) {
      debugPrint('Failed to load custom fonts: $e');
    }
  }

  /// 對尚未探測過的自訂字型各自發出存取探測（不 await，不阻塞清單顯示）。
  void _probeNewFonts(List<CustomFont> fonts) {
    for (final font in fonts) {
      final id = font.id;
      if (id == null || !_probeRequestedIds.add(id)) continue;
      unawaited(_probeFont(id, font.fontUri));
    }
  }

  Future<void> _probeFont(int id, String uri) async {
    final result = await probeStorageAccess(uri);
    // 探測期間可能已離開畫面，或該字型已被刪除：結果直接捨棄
    if (!mounted || !_customFonts.any((f) => f.id == id)) return;
    setState(() => _probeResults[id] = result);
  }

  Future<void> _loadInstalledFonts() async {
    final store = widget.downloadableFontStore;
    if (store == null) return;
    try {
      final installed = await store.installedFonts();
      if (!mounted) return;
      setState(() {
        _installedFonts = installed;
        _installedFontsLoaded = true;
      });
    } catch (e) {
      debugPrint('Failed to load downloaded fonts: $e');
      // 讀取失敗時視為沒有已下載的字型，讓使用者仍然可以下載
      if (mounted) setState(() => _installedFontsLoaded = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final builtInFonts = widget.downloadableFontStore?.supportedFonts ?? AppFont.values;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.fontManagementTitle),
        actions: [
          IconButton(
            key: const Key('font_management_upload_button'),
            icon: _isUploading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.add),
            tooltip: l10n.fontManagementUploadTooltip,
            onPressed: _isUploading ? null : _pickAndUploadFonts,
          ),
        ],
      ),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(l10n.fontManagementBuiltInSectionLabel, style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
          // Issue 7：只列出系統 WebView 載得動的內建字型；沒有 store 時照舊列出全部
          if (builtInFonts.length < AppFont.values.length)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text(
                l10n.fontManagementBuiltInUnsupportedHint,
                key: const Key('font_management_builtin_unsupported_hint'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          for (final font in builtInFonts) _buildBuiltInFontTile(font, l10n),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(l10n.fontManagementCustomSectionLabel, style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
          if (_customFonts.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(l10n.fontManagementNoCustomFontsHint),
            ),
          for (final font in _customFonts) _buildCustomFontTile(font, l10n),
        ],
      ),
    );
  }

  /// 自訂字型的一列。探測結果不是 `readable` 時，在副標題顯示文字標籤與
  /// 外框的重新連結按鈕（epic-15-storage-permission Issue 3）：標籤是文字而非
  /// 只靠顏色，按鈕用 OutlinedButton，E-Ink 高對比模式下才看得清楚。
  Widget _buildCustomFontTile(CustomFont font, AppLocalizations l10n) {
    final id = font.id;
    final probe = id == null ? null : _probeResults[id];
    final isInaccessible =
        probe != null && probe != StorageAccessProbeResult.readable;
    final isRelinking = id != null && _relinkingIds.contains(id);
    return ListTile(
      title: Text(font.displayName),
      subtitle: isInaccessible
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.fontManagementFileInaccessibleBadge,
                  key: Key('font_management_inaccessible_badge_$id'),
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                OutlinedButton(
                  key: Key('font_management_relink_button_$id'),
                  onPressed: isRelinking ? null : () => _relinkFont(font),
                  child: isRelinking
                      ? SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(
                            key: Key('font_management_relink_progress_$id'),
                            strokeWidth: 2,
                            // 讀屏軟體才知道這個進度圈在做什麼（程式審查 M-3）
                            semanticsLabel: l10n.fontManagementRelinkAction,
                          ),
                        )
                      : Text(l10n.fontManagementRelinkAction),
                ),
              ],
            )
          : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            key: Key('font_management_rename_button_${font.id}'),
            icon: const Icon(Icons.edit),
            tooltip: l10n.fontManagementRenameTooltip,
            onPressed: isRelinking ? null : () => _renameFont(font),
          ),
          IconButton(
            key: Key('font_management_delete_button_${font.id}'),
            icon: const Icon(Icons.delete),
            tooltip: l10n.fontManagementDeleteTooltip,
            onPressed: isRelinking ? null : () => _deleteFont(font),
          ),
        ],
      ),
    );
  }

  /// 內建字型的一列：標題固定是字型名稱，副標題依狀態顯示大小、進度或錯誤訊息
  /// （規格審查 M-2：任何狀態都看得出是哪一款字型）。
  Widget _buildBuiltInFontTile(AppFont font, AppLocalizations l10n) {
    final title = Text(font.displayName(l10n));
    if (widget.downloadableFontStore == null) return ListTile(title: title);

    final key = Key('font_management_builtin_${font.name}');
    final size = formatFontFileSize(fontDownloadSpecOf(font).sizeBytes);
    if (!_installedFontsLoaded) {
      return ListTile(key: key, title: title, subtitle: Text(size));
    }

    // 任何字型下載中時，其他所有內建字型的下載／重試／刪除都停用（規格審查 I-2）
    final isBusy = _downloadingFont != null;

    if (_downloadingFont == font) {
      return ListTile(
        key: key,
        title: title,
        subtitle: Row(
          children: [
            Expanded(child: LinearProgressIndicator(value: _downloadPercent / 100)),
            const SizedBox(width: 8),
            Text('$_downloadPercent%'),
          ],
        ),
        trailing: IconButton(
          key: Key('font_management_cancel_download_${font.name}'),
          icon: const Icon(Icons.close),
          tooltip: l10n.fontManagementCancelDownloadTooltip,
          onPressed: () => _downloadToken?.cancel(),
        ),
      );
    }

    if (_installedFonts.contains(font)) {
      return ListTile(
        key: key,
        title: title,
        subtitle: Text('$size · ${l10n.fontManagementStatusDownloaded}'),
        trailing: IconButton(
          key: Key('font_management_delete_builtin_${font.name}'),
          icon: const Icon(Icons.delete),
          tooltip: l10n.fontManagementDeleteTooltip,
          onPressed: isBusy ? null : () => _deleteDownloadedFont(font),
        ),
      );
    }

    final failure = _downloadFailures[font];
    if (failure != null) {
      return ListTile(
        key: key,
        title: title,
        subtitle: Text('$size · ${_downloadFailureMessage(failure, l10n)}'),
        trailing: IconButton(
          key: Key('font_management_retry_${font.name}'),
          icon: const Icon(Icons.refresh),
          tooltip: l10n.fontManagementRetryTooltip,
          onPressed: isBusy ? null : () => _downloadFont(font),
        ),
      );
    }

    return ListTile(
      key: key,
      title: title,
      subtitle: Text('$size · ${l10n.fontManagementStatusNotDownloaded}'),
      trailing: IconButton(
        key: Key('font_management_download_${font.name}'),
        icon: const Icon(Icons.download),
        tooltip: l10n.fontManagementDownloadTooltip,
        onPressed: isBusy ? null : () => _downloadFont(font),
      ),
    );
  }

  String _downloadFailureMessage(FontDownloadException error, AppLocalizations l10n) {
    switch (error.reason) {
      case FontDownloadFailure.network:
        return l10n.fontDownloadErrorNetwork;
      case FontDownloadFailure.httpStatus:
        return l10n.fontDownloadErrorHttp(error.statusCode ?? 0);
      case FontDownloadFailure.integrity:
        return l10n.fontDownloadErrorIntegrity;
      case FontDownloadFailure.storage:
        return l10n.fontDownloadErrorStorage;
      case FontDownloadFailure.cancelled:
        // 取消不會記錄成失敗（見 _downloadFont），這裡只是讓 switch 完整
        return '';
    }
  }

  Future<void> _downloadFont(AppFont font) async {
    final token = FontDownloadCancellationToken();
    setState(() {
      _downloadingFont = font;
      _downloadPercent = 0;
      _downloadToken = token;
      _downloadFailures.remove(font);
    });
    try {
      await widget.downloadableFontStore!.download(
        font,
        cancellationToken: token,
        // store 已經節流成「整數百分比變大才回報」，這裡每次回報都重繪即可
        onProgress: (percent) {
          if (mounted) setState(() => _downloadPercent = percent);
        },
      );
      if (!mounted) return;
      setState(() => _installedFonts = {..._installedFonts, font});
    } on FontDownloadException catch (error) {
      if (!mounted || error.reason == FontDownloadFailure.cancelled) return;
      setState(() => _downloadFailures[font] = error);
    } catch (error) {
      // store 應該只拋出 FontDownloadException；萬一出現其他例外，仍顯示錯誤並允許重試，
      // 不讓使用者看到「進度條閃一下就回到原狀」而沒有任何提示（程式審查 I-1）
      debugPrint('Unexpected font download error: $error');
      if (!mounted || token.isCancelled) return;
      setState(() => _downloadFailures[font] =
          const FontDownloadException(FontDownloadFailure.network));
    } finally {
      if (mounted) {
        setState(() {
          _downloadingFont = null;
          _downloadToken = null;
        });
      }
    }
  }

  Future<void> _deleteDownloadedFont(AppFont font) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.fontManagementDeleteConfirmTitle(font.displayName(l10n))),
        // 刻意不用 fontManagementDeleteConfirmMessage：可下載字型刪除時不清除書籍偏好
        // （ADR 0035），也不查詢使用中的書籍數量（規格審查 I-4）
        content: Text(l10n.fontManagementDownloadableDeleteConfirmMessage),
        actions: [
          TextButton(
            key: const Key('font_management_delete_cancel'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            key: const Key('font_management_delete_confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.fontManagementDeleteTooltip),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.downloadableFontStore!.delete(font);
    } catch (error) {
      // 刪除失敗（例如檔案被占用）：重新讀取已下載清單，讓畫面顯示實際的檔案狀態（程式審查 M-3）
      debugPrint('Failed to delete downloaded font: $error');
      await _loadInstalledFonts();
      return;
    }
    if (!mounted) return;
    setState(() => _installedFonts = {..._installedFonts}..remove(font));
  }

  Future<void> _pickAndUploadFonts() async {
    final picked = await FilePicker.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: ['ttf', 'otf'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;
    // identifier 是 Android SAF content:// URI（見 ADR 0021），本專案手機
    // 優先且目前只有 Android 實作，非 Android 平台/桌面測試環境下可能為
    // null，一併過濾避免後續 fontUri 寫入 null。
    final validFiles = picked.files
        .where((f) => f.bytes != null && f.identifier != null)
        .toList();
    if (validFiles.isEmpty) return;

    setState(() => _isUploading = true);
    try {
      final parsedFamilyNames = <String>[];
      for (final file in validFiles) {
        parsedFamilyNames.add(resolveFontFamilyName(file.bytes!, file.name));
      }

      // 內建 5 款字型的 family name 不存在於 custom_fonts 表（該表只存自訂
      // 字型），必須額外併入重複判定集合——否則上傳一款與內建字型 family
      // name 相同的自訂字型會成功寫入，導致 reader_settings_sheet.dart
      // 的 DropdownButton 出現兩個相同 value 的 DropdownMenuItem，觸發
      // Flutter「exactly one item with value」assertion 崩潰（審查發現，
      // 見 tmp/epic-14/review-plan-issue-2.md Critical）。
      final existing = AppFont.values.map((f) => f.familyName).toSet();
      for (final familyName in parsedFamilyNames.toSet()) {
        if (await widget.repository.familyNameExists(familyName)) {
          existing.add(familyName);
        }
      }

      final outcome = resolveUploadOutcome(
        parsedFamilyNames: parsedFamilyNames,
        alreadyExistingFamilyNames: existing,
      );

      for (final index in outcome.toInsertIndexes) {
        final file = validFiles[index];
        final uri = file.identifier!;
        // 部分文件提供者不保證核發持久化授權（見 CONTEXT.md「持久化授權」）；
        // 字型檔案刻意不做落地複本退路（ADR 0021），僅盡力而為，結果忽略，
        // 不因此中止整批上傳。
        await persistReadAccess(uri);
        await widget.repository.insert(CustomFont(
          displayName: stripFontFileExtension(file.name),
          familyName: parsedFamilyNames[index],
          fontUri: uri,
        ));
      }

      await _loadFonts();
      if (!mounted) return;
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(buildUploadResultMessage(
          l10n: l10n,
          addedCount: outcome.addedCount,
          skippedCount: outcome.skippedCount,
        )),
      ));
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  /// 重新連結字型檔案（epic-15-storage-permission Issue 3；規則自
  /// epic-54 Issue 3 起收在 [CustomFontRelinker]）：選檔 → 交給 relinker →
  /// 依結果顯示。成功時更新探測標示並重新載入清單。
  Future<void> _relinkFont(CustomFont font) async {
    final id = font.id;
    if (id == null || _relinkingIds.contains(id)) return;
    setState(() => _relinkingIds.add(id));
    try {
      final picker = widget.pickSingleFontFile ?? pickSingleFontFileViaFilePicker;
      final picked = await picker();
      // 選檔期間使用者可能已離開畫面：不再解析、不持久化授權、不寫資料庫
      if (picked == null || !mounted) return;

      final result = await _relinker.relink(font, picked);
      if (!mounted) return;
      switch (result) {
        case FontRelinkSuccess():
          setState(() => _probeResults[id] = StorageAccessProbeResult.readable);
          await _loadFonts();
        case FontRelinkFamilyMismatch():
          _showRelinkSnackBar(
              AppLocalizations.of(context)!.fontManagementFamilyMismatchMessage);
        case FontRelinkFailed():
          // epic-54 Issue 3：過去只 debugPrint，使用者看不到；改與書籍重新連結
          // 一致，重用既有文字。
          _showRelinkSnackBar(
              AppLocalizations.of(context)!.readerStorageRelinkFailed);
      }
    } finally {
      if (mounted) setState(() => _relinkingIds.remove(id));
    }
  }

  /// 先收掉上一則再顯示，連續失敗時新結果不必排在前一則之後。
  void _showRelinkSnackBar(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _renameFont(CustomFont font) async {
    _renameController?.dispose();
    final controller = TextEditingController(text: font.displayName);
    _renameController = controller;
    final l10n = AppLocalizations.of(context)!;
    final newName = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.fontManagementRenameDialogTitle),
        content: TextField(
          key: const Key('font_management_rename_field'),
          controller: controller,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.cancel),
          ),
          TextButton(
            key: const Key('font_management_rename_confirm'),
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: Text(l10n.confirm),
          ),
        ],
      ),
    );
    if (newName == null || newName.isEmpty || font.id == null) return;
    await widget.repository.rename(font.id!, newName);
    await _loadFonts();
  }

  Future<void> _deleteFont(CustomFont font) async {
    final usageCount = await widget.repository.countBooksUsing(font.familyName);
    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.fontManagementDeleteConfirmTitle(font.displayName)),
        content: usageCount > 0
            ? Text(l10n.fontManagementDeleteConfirmMessage(usageCount))
            : null,
        actions: [
          TextButton(
            key: const Key('font_management_delete_cancel'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            key: const Key('font_management_delete_confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.fontManagementDeleteTooltip),
          ),
        ],
      ),
    );
    if (confirmed != true || font.id == null) return;
    await widget.repository.deleteAndResetUsage(font.id!, font.familyName);
    await _loadFonts();
  }
}

/// 批次上傳結果：哪些索引（對應呼叫端傳入的 [parsedFamilyNames] 順序）
/// 真的要寫入資料庫，以及新增/跳過各自的計數。同一批次內重複的 family
/// name（例如使用者一次選了兩個內容相同的字型檔）只保留第一次出現的索引，
/// 其餘視同重複一併跳過——不能只靠 [alreadyExistingFamilyNames]（那只反映
/// 資料庫既有資料，抓不到「這一批次自己內部重複」的情況）。
class UploadOutcome {
  final List<int> toInsertIndexes;
  final int addedCount;
  final int skippedCount;
  const UploadOutcome({
    required this.toInsertIndexes,
    required this.addedCount,
    required this.skippedCount,
  });
}

UploadOutcome resolveUploadOutcome({
  required List<String> parsedFamilyNames,
  required Set<String> alreadyExistingFamilyNames,
}) {
  final seenInBatch = <String>{};
  final toInsertIndexes = <int>[];
  var skipped = 0;
  for (var i = 0; i < parsedFamilyNames.length; i++) {
    final familyName = parsedFamilyNames[i];
    final isDuplicate = alreadyExistingFamilyNames.contains(familyName) ||
        !seenInBatch.add(familyName);
    if (isDuplicate) {
      skipped++;
    } else {
      toInsertIndexes.add(i);
    }
  }
  return UploadOutcome(
    toInsertIndexes: toInsertIndexes,
    addedCount: toInsertIndexes.length,
    skippedCount: skipped,
  );
}

String buildUploadResultMessage({
  required AppLocalizations l10n,
  required int addedCount,
  required int skippedCount,
}) {
  if (addedCount > 0 && skippedCount > 0) {
    return l10n.fontManagementUploadBothMessage(addedCount, skippedCount);
  }
  if (addedCount > 0) {
    return l10n.fontManagementUploadAddedOnlyMessage(addedCount);
  }
  return l10n.fontManagementUploadSkippedOnlyMessage(skippedCount);
}

/// 字型檔大小的顯示格式，例如 36034016 → `34.4 MB`。以 1024 × 1024 為 1 MB
/// （實際是 MiB，但沿用一般人熟悉的「MB」標示），數值對齊 spec 字型目錄。
/// MB 在三種語系寫法相同，所以不另外做在地化字串（epic-49）。
String formatFontFileSize(int bytes) =>
    '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

