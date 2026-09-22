import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../library/book_content_fingerprint.dart';
import '../library/book_import_service.dart';
import '../library/library_repository.dart';
import '../search/pdf_content_indexer.dart' show readContentUriAll;
import '../wifi_transfer/network_availability.dart';
import '../wifi_transfer/wifi_transfer_http_server.dart';
import '../l10n/app_localizations.dart';
import '../wifi_transfer/wifi_transfer_service.dart';

/// 呼叫端優先嘗試的固定埠；bind 失敗（`SocketException`，通常是埠號
/// 衝突）才以 `port: 0` 交給系統動態分配（見 [_WifiTransferScreenState._startServerIfNeeded]）。
const kWifiTransferDefaultPort = 8080;

/// WiFi 傳書畫面（epic-44-wifi-book-transfer spec.md「`WifiTransferScreen`
/// 畫面邏輯」）：顯示 [checkNetworkAvailability] 偵測結果、啟動/停止本機
/// HTTP Server、螢幕常亮、離開畫面時有傳輸中須示警。
class WifiTransferScreen extends StatefulWidget {
  final LibraryRepository libraryRepository;
  final BookImportService importService;
  final ComputeRemoteFingerprint computeFingerprint;
  final CheckNetworkAvailability checkNetworkAvailability;

  /// 供 widget test 注入可控的 `ValueNotifier<int>`，繞過真實伺服器啟動
  /// （比照 `TapZoneDetector` 建構子注入時間來源的既定慣例）：非 `null`
  /// 時直接用它驅動 `PopScope` 判斷、且不啟動真實伺服器；生產環境不傳，
  /// 走真實 `WifiTransferHttpServer.activeTransfersNotifier`。
  @visibleForTesting
  final ValueListenable<int>? activeTransfersNotifierOverride;

  const WifiTransferScreen({
    super.key,
    required this.libraryRepository,
    required this.importService,
    required this.computeFingerprint,
    required this.checkNetworkAvailability,
    this.activeTransfersNotifierOverride,
  });

  @override
  State<WifiTransferScreen> createState() => _WifiTransferScreenState();
}

class _WifiTransferScreenState extends State<WifiTransferScreen> {
  late final Future<NetworkAvailability> _availabilityFuture;
  final ValueNotifier<int> _fallbackNotifier = ValueNotifier<int>(0);
  bool _manualOverrideRequested = false;
  String? _manualSelectedIp;
  int? _boundPort;
  bool _startingServer = false;
  WifiTransferHttpServer? _wifiServer;
  HttpServer? _httpServer;

  bool get _isTestMode => widget.activeTransfersNotifierOverride != null;

  ValueListenable<int> get _activeTransfersNotifier =>
      widget.activeTransfersNotifierOverride ??
      _wifiServer?.activeTransfersNotifier ??
      _fallbackNotifier;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    _availabilityFuture = _initialize();
  }

  /// **（`/receiving-code-review` 審查修正，I-3）** `checkNetworkAvailability()`
  /// 或 `_startServerIfNeeded()` 拋出未預期例外時，整體降級回傳
  /// `unavailable`，避免 `_availabilityFuture` 以 error 狀態完成——
  /// `FutureBuilder` 的 `snapshot.data!` 裸取在該情況下會觸發 Null
  /// check crash，讓使用者連「不可用」提示都看不到。
  Future<NetworkAvailability> _initialize() async {
    try {
      final availability = await widget.checkNetworkAvailability();
      if (availability.ipAddress != null &&
          availability.kind != NetworkAvailabilityKind.unavailable) {
        await _startServerIfNeeded(availability.ipAddress!);
      }
      return availability;
    } catch (_) {
      return const NetworkAvailability(
          kind: NetworkAvailabilityKind.unavailable);
    }
  }

  /// [_isTestMode] 時直接略過（widget test 一律注入
  /// [WifiTransferScreen.activeTransfersNotifierOverride]，不啟動真實
  /// socket；真實伺服器行為僅由 `integration_test/` 驗證）。冪等：已
  /// 啟動過（[_wifiServer] 非 null）不重複啟動。
  ///
  /// **（`/receiving-code-review` 審查修正，I-4）** 新增 [_startingServer]
  /// 防重入旗標——原設計只檢查 [_wifiServer] 是否非 null，但該欄位要等
  /// 到非同步啟動「完成」才會被賦值，啟動期間（`await server.start(...)`
  /// 尚未回傳）的這段空窗若使用者連續快速點擊手動覆寫候選項，會觸發兩
  /// 個並行的 `WifiTransferHttpServer.start()` 呼叫，其中一個的
  /// `HttpServer` 引用會被另一個的 `setState()` 覆蓋，變成永不關閉的
  /// 孤兒 socket。
  Future<void> _startServerIfNeeded(String ipAddress) async {
    if (_isTestMode || _wifiServer != null || _startingServer) return;
    _startingServer = true;
    try {
      final service = WifiTransferService(
        libraryRepository: widget.libraryRepository,
        importService: widget.importService,
        computeFingerprint: widget.computeFingerprint,
        materializeContentUri: readContentUriAll,
        deleteFile: (path) => File(path).delete(),
      );
      final server = WifiTransferHttpServer(service: service);
      HttpServer httpServer;
      try {
        httpServer = await server.start(
          ipAddress: ipAddress,
          port: kWifiTransferDefaultPort,
        );
      } on SocketException {
        httpServer = await server.start(ipAddress: ipAddress, port: 0);
      }
      if (!mounted) {
        await server.stop(httpServer);
        return;
      }
      setState(() {
        _wifiServer = server;
        _httpServer = httpServer;
        _boundPort = httpServer.port;
      });
    } finally {
      _startingServer = false;
    }
  }

  void _selectManualIp(String ip) {
    setState(() => _manualSelectedIp = ip);
    _startServerIfNeeded(ip);
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    final httpServer = _httpServer;
    final wifiServer = _wifiServer;
    if (httpServer != null && wifiServer != null) {
      wifiServer.stop(httpServer);
    }
    wifiServer?.dispose();
    _fallbackNotifier.dispose();
    super.dispose();
  }

  Future<void> _confirmLeaveIfTransferring(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.wifiTransferLeaveConfirmTitle),
        content: Text(l10n.wifiTransferLeaveConfirmMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.wifiTransferLeaveConfirmButton),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ValueListenableBuilder<int>(
      valueListenable: _activeTransfersNotifier,
      builder: (context, activeCount, child) {
        return PopScope(
          canPop: activeCount == 0,
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) return;
            _confirmLeaveIfTransferring(context);
          },
          child: child!,
        );
      },
      child: Scaffold(
        appBar: AppBar(title: Text(l10n.wifiTransferTitle)),
        body: _buildBody(context),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return FutureBuilder<NetworkAvailability>(
      future: _availabilityFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        // 【`/receiving-code-review` 審查修正 I-3】_initialize() 已把所有
        // 例外降級為 unavailable，理論上 snapshot.hasError 不會發生；仍
        // 以 !snapshot.hasData 防禦一次，避免任何未預期路徑導致
        // snapshot.data! 崩潰白屏。
        if (!snapshot.hasData) {
          return Center(child: Text(l10n.wifiTransferUnavailableText));
        }
        final availability = snapshot.data!;
        final effectiveIp = _manualSelectedIp ?? availability.ipAddress;
        final effectiveUnavailable = _manualSelectedIp == null &&
            availability.kind == NetworkAvailabilityKind.unavailable;

        if (effectiveIp != null && !effectiveUnavailable) {
          final url =
              'http://$effectiveIp:${_boundPort ?? kWifiTransferDefaultPort}';
          // 【`/receiving-code-review` 審查修正 I-2】包一層
          // SingleChildScrollView——橫向模式下 QR Code＋文字加總高度可能
          // 超出可視範圍，避免 RenderFlex overflow。
          return SingleChildScrollView(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 16),
                  Text(l10n.wifiTransferInstructionText),
                  const SizedBox(height: 8),
                  Text(url, key: const Key('wifi_transfer_ip_text')),
                  const SizedBox(height: 16),
                  // 【`/receiving-code-review` 審查修正 M-2】明確指定白色
                  // 背景——預設 backgroundColor 為 transparent，深色主題／
                  // E-Ink 高對比模式下 Scaffold 背景偏黑，黑色 QR 模組會
                  // 疊在黑底上，相機完全無法辨識。
                  QrImageView(
                    key: const Key('wifi_transfer_qr_code'),
                    data: url,
                    size: 200,
                    backgroundColor: Colors.white,
                  ),
                  ValueListenableBuilder<int>(
                    valueListenable: _activeTransfersNotifier,
                    builder: (context, activeCount, _) {
                      if (activeCount <= 0) {
                        return const SizedBox.shrink();
                      }
                      final theme = Theme.of(context);
                      // 【`/receiving-code-review` 審查修正 I-1】以亮度與 primary/scaffold 顏色
                      // 推斷 E-Ink 高對比主題；未來若全面重構可改為讀取 AppThemePreferences.isEinkMode。
                      final isEink = theme.brightness == Brightness.light &&
                          theme.colorScheme.primary == Colors.black &&
                          theme.scaffoldBackgroundColor == Colors.white;
                      return Container(
                        key: const Key('wifi_transfer_active_transfers_banner'),
                        margin: const EdgeInsets.only(top: 16),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: isEink
                              ? Colors.white
                              : theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isEink
                                ? Colors.black
                                : theme.colorScheme.outline.withValues(alpha: 0.35),
                            width: 1.0,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: isEink ? Colors.black : theme.colorScheme.primary,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              AppLocalizations.of(context)!
                                  .wifiTransferActiveCountText(activeCount),
                              key: const Key('wifi_transfer_active_transfers_text'),
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: isEink
                                    ? Colors.black
                                    : theme.colorScheme.onSurface,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          );
        }

        // 【`/receiving-code-review` 審查修正 I-2】包一層
        // SingleChildScrollView——allCandidates 在真機上可能有 8~12 個
        // 蜂巢式/虛擬介面，直接塞進 Column(mainAxisSize: min) 在直向小
        // 螢幕或橫向模式下會 RenderFlex overflow。
        return SingleChildScrollView(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 16),
                Text(l10n.wifiTransferUnavailableText),
                const SizedBox(height: 16),
                if (!_manualOverrideRequested)
                  ElevatedButton(
                    key: const Key('wifi_transfer_manual_override_button'),
                    onPressed: () =>
                        setState(() => _manualOverrideRequested = true),
                    child: Text(l10n.wifiTransferManualOverrideButton),
                  ),
                if (_manualOverrideRequested)
                  if (availability.allCandidates.isEmpty)
                    Text(l10n.wifiTransferNoInterfacesText)
                  else
                    ...availability.allCandidates.map(
                      (candidate) => ListTile(
                        key: Key(
                            'wifi_transfer_candidate_${candidate.interfaceName}'),
                        title: Text(candidate.interfaceName),
                        subtitle: Text(candidate.ipAddress),
                        onTap: () => _selectManualIp(candidate.ipAddress),
                      ),
                    ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );
  }
}
