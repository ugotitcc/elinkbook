# Epic 44 Issue 1：網路偵測＋WiFi 傳書畫面骨架＋伺服器基礎設施＋入口 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 打好「打開 WiFi 傳書、PC 瀏覽器連得上首頁」的完整骨架——網路偵測（WiFi 客戶端/熱點/不可用三態分層判定）、`WifiTransferService`／`WifiTransferHttpServer` 骨架（含跨路由共用的併發節流機制與活躍傳輸狀態）、`WifiTransferScreen` 畫面、「來源」畫面入口，讓 Issue 2／3 只需要專注各自的 `/api/*` 路由邏輯。

**Architecture:** `network_availability.dart`（純 Dart，分層判定：`connectivity_plus` 先判斷 WiFi 客戶端，否則列舉 `NetworkInterface.list()` 轉呼叫可測的純函式 `classifyNetworkInterfaces()`）→ `WifiTransferService`（純邏輯層骨架，三個業務方法先 `throw UnimplementedError()`）→ `WifiTransferHttpServer`（`shelf` 薄殼層，`GET /` 真實服務首頁 HTML，其餘路由回 501；內建 `withTransferPermit()` 併發節流機制供 Issue 2/3 共用）→ `WifiTransferScreen`（顯示 IP/QR、手動覆寫、螢幕常亮、離開示警）→ 經 `WifiTransferDependencies` bundle 由 `SourcesHomeScreen`→`AdaptiveShellScaffold`→`main.dart` 三層裝配。

**Tech Stack:** Flutter/Dart、`shelf`（HTTP 路由，無 `shelf_router`，手動比對 `request.url.path`）、`connectivity_plus`、`qr_flutter`（`QrImageView`，4.1.0 版 API）、`wakelock_plus`（1.5.2 版 API，`WakelockPlus.enable()/disable()`）、`dart:io`（`NetworkInterface`／`HttpServer`）。

**Spec:** `docs/epics/epic-44-wifi-book-transfer/spec.md`（「`network_availability.dart`」「`wifi_transfer_service.dart`」「`wifi_transfer_http_server.dart`」「`WifiTransferScreen` 畫面邏輯」「依賴注入收斂」章節）與 `docs/epics/epic-44-wifi-book-transfer/issues.md`（Issue 1）。執行者應同時閱讀這兩份文件；Issue 0 的完成狀態（`findBookById`／channel 改名／四個新依賴）已合併進 `main`，本計畫直接建立在其上。

## Global Constraints

- 所有程式碼註解、commit message、文件皆使用正體中文（zh-TW），專業術語可保留英文（CLAUDE.md 全域規則）。
- 所有指令在 `app/` 目錄下執行（`flutter pub get`／`flutter analyze`／`flutter test`）。
- 每個 Task 只跑「這次異動實際觸及」的測試檔；只有本計畫最後一個 Task（Task 11）才跑一次完整 `flutter test`（CLAUDE.md「測試執行範圍」）。
- `WifiTransferHttpServer.start()` 實際 bind 一律用 `InternetAddress.anyIPv4`（`0.0.0.0`），不直接 bind 傳入的 `ipAddress`（spec.md 已定案：部分客製化 Android 系統對熱點虛擬網卡 IP bind 容易 `EADDRNOTAVAIL`）；`ipAddress` 僅供顯示網址／QR Code 使用。
- Port 選擇策略：呼叫端（`WifiTransferScreen`）先試固定埠 `kWifiTransferDefaultPort`（8080），bind 拋 `SocketException` 才以 `port: 0` 重試——這個重試邏輯屬於呼叫端，不在 `WifiTransferHttpServer.start()` 內部。
- 併發節流上限初始值固定為 2（`WifiTransferHttpServer.maxConcurrentTransfers` 預設值），非本計畫鎖死的最終值（留待真機測試調校，比照 spec.md 既定）。
- 依賴版本不釘死，用 `flutter pub add` 讓工具自行決定當下相容版本（沿用 Issue 0 慣例）。
- 不新增 SQLite schema（spec.md「範圍界定」已定案）。
- 測試裡任何需要繞過真實 socket／真實 `WakelockPlus` 平台呼叫的地方，一律用既有的依賴注入／測試替身慣例（`CheckNetworkAvailability` 函式注入、`activeTransfersNotifierOverride`、`wakelockPlusPlatformInstance` 覆寫），不得讓 `flutter test`（非 `integration_test/`）真的去綁定裝置層級資源。
- 除本計畫列出的檔案外，不修改其他檔案；不「順手」重構、清理或改動未在本 Issue 範圍內的程式碼。

---

### Task 1: `network_availability.dart`——型別與網路偵測邏輯

**Files:**
- Create: `app/lib/wifi_transfer/network_availability.dart`
- Test: `app/test/wifi_transfer/network_availability_test.dart`

**Interfaces:**
- Produces：
  - `enum NetworkAvailabilityKind { wifiClient, hotspot, unavailable }`
  - `class NetworkInterfaceCandidate { final String interfaceName; final String ipAddress; const NetworkInterfaceCandidate({required this.interfaceName, required this.ipAddress}); }`
  - `class NetworkAvailability { final NetworkAvailabilityKind kind; final String? ipAddress; final List<NetworkInterfaceCandidate> allCandidates; const NetworkAvailability({required this.kind, this.ipAddress, this.allCandidates = const []}); }`
  - `typedef CheckNetworkAvailability = Future<NetworkAvailability> Function();`
  - `Future<NetworkAvailability> checkNetworkAvailability()`（生產環境實作，供 Task 9 main.dart 注入）
  - `NetworkAvailability classifyNetworkInterfaces(List<NetworkInterfaceCandidate> raw)`（純函式，供 Task 5/6/7/8 的測試與畫面邏輯間接依賴其型別）

- [ ] **Step 1: 寫失敗測試——`classifyNetworkInterfaces()` 純函式**

Create `app/test/wifi_transfer/network_availability_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/wifi_transfer/network_availability.dart';

void main() {
  group('classifyNetworkInterfaces', () {
    test(
        '含 WiFi 風格介面（私有網段 IP）：kind=hotspot（層一 connectivity_plus '
        '才會再升級為 wifiClient，見 checkNetworkAvailability()），取其 IP', () {
      const raw = [
        NetworkInterfaceCandidate(interfaceName: 'wlan0', ipAddress: '192.168.1.5'),
      ];
      final result = classifyNetworkInterfaces(raw);
      expect(result.kind, NetworkAvailabilityKind.hotspot);
      expect(result.ipAddress, '192.168.1.5');
      expect(result.allCandidates, raw);
    });

    test('純蜂巢式介面：全數被黑名單過濾，kind=unavailable，ipAddress 為 null', () {
      const raw = [
        NetworkInterfaceCandidate(interfaceName: 'rmnet0', ipAddress: '10.20.30.40'),
        NetworkInterfaceCandidate(interfaceName: 'ccmni1', ipAddress: '10.20.30.41'),
      ];
      final result = classifyNetworkInterfaces(raw);
      expect(result.kind, NetworkAvailabilityKind.unavailable);
      expect(result.ipAddress, isNull);
      expect(result.allCandidates, raw);
    });

    test('蜂巢式+熱點混合：蜂巢式被過濾，剩下熱點介面 kind=hotspot', () {
      const raw = [
        NetworkInterfaceCandidate(interfaceName: 'rmnet0', ipAddress: '10.20.30.40'),
        NetworkInterfaceCandidate(interfaceName: 'ap0', ipAddress: '192.168.43.1'),
      ];
      final result = classifyNetworkInterfaces(raw);
      expect(result.kind, NetworkAvailabilityKind.hotspot);
      expect(result.ipAddress, '192.168.43.1');
      expect(result.allCandidates, raw);
    });

    test('VPN 介面同樣被過濾：tun0 不會被誤判為可用網段', () {
      const raw = [
        NetworkInterfaceCandidate(interfaceName: 'tun0', ipAddress: '10.8.0.2'),
      ];
      final result = classifyNetworkInterfaces(raw);
      expect(result.kind, NetworkAvailabilityKind.unavailable);
      expect(result.ipAddress, isNull);
    });

    test('存活介面但 IP 非私有網段（公網 IP）：仍判定 unavailable', () {
      const raw = [
        NetworkInterfaceCandidate(interfaceName: 'eth0', ipAddress: '8.8.8.8'),
      ];
      final result = classifyNetworkInterfaces(raw);
      expect(result.kind, NetworkAvailabilityKind.unavailable);
      expect(result.ipAddress, isNull);
      expect(result.allCandidates, raw);
    });

    test('全空清單：kind=unavailable，allCandidates 為空清單', () {
      final result = classifyNetworkInterfaces(const []);
      expect(result.kind, NetworkAvailabilityKind.unavailable);
      expect(result.ipAddress, isNull);
      expect(result.allCandidates, isEmpty);
    });
  });
}
```

- [ ] **Step 2: 執行測試，確認失敗（檔案尚不存在）**

Run: `flutter test test/wifi_transfer/network_availability_test.dart`
Expected: FAIL，編譯錯誤（`Target of URI doesn't exist: 'package:elinkbook/wifi_transfer/network_availability.dart'`）。

- [ ] **Step 3: 實作 `network_availability.dart`**

Create `app/lib/wifi_transfer/network_availability.dart`：

```dart
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';

/// WiFi 傳書的網路先決條件三態（epic-44-wifi-book-transfer spec.md
/// 「`network_availability.dart`」）。
enum NetworkAvailabilityKind { wifiClient, hotspot, unavailable }

/// 一個偵測到的網路介面候選項，供「手動覆寫」UI 列出所有介面供使用者
/// 自行挑選（見 [NetworkAvailability.allCandidates] 說明）。
class NetworkInterfaceCandidate {
  final String interfaceName;
  final String ipAddress;
  const NetworkInterfaceCandidate({
    required this.interfaceName,
    required this.ipAddress,
  });
}

class NetworkAvailability {
  final NetworkAvailabilityKind kind;

  /// [kind] != unavailable 時，建議直接使用的局域網 IP。
  final String? ipAddress;

  /// 一律回傳目前列舉到的所有網路介面（含被黑名單排除的），即使
  /// [kind] == unavailable 也會有值——供「我確定目前是用手機熱點」手動
  /// 覆寫 UI 列出全部候選項供使用者自行挑選，不需要偵測邏輯本身做到
  /// 100% 準確。
  final List<NetworkInterfaceCandidate> allCandidates;

  const NetworkAvailability({
    required this.kind,
    this.ipAddress,
    this.allCandidates = const [],
  });
}

typedef CheckNetworkAvailability = Future<NetworkAvailability> Function();

/// 蜂巢式資料連線介面名稱黑名單前綴（不分大小寫比對）。
const _cellularInterfacePrefixes = ['rmnet', 'ccmni', 'pdp'];

/// VPN 介面名稱黑名單前綴（不分大小寫比對）。
const _vpnInterfacePrefixes = ['tun', 'ppp'];

/// 純函式，供 [checkNetworkAvailability] 呼叫，也供單元測試直接餵入假
/// 資料驗證（`flutter test` 環境無法可靠呼叫真實 `NetworkInterface.list()`）。
/// 用蜂巢式/VPN 介面名稱黑名單過濾 [raw]；剩餘介面中若有私有網段 IP
/// （非電信、非公網），kind = hotspot、取第一個作為 ipAddress；過濾後
/// 空無一物（或皆非私有網段）→ kind = unavailable，ipAddress 為 null；
/// [raw] 原樣回填為 allCandidates（不論過濾結果為何皆列出全部）。
///
/// 這裡只會回傳 hotspot／unavailable——wifiClient 由
/// [checkNetworkAvailability] 疊加 `connectivity_plus` 的判斷結果後才
/// 升級，純函式本身無法從介面名稱/IP 分辨「是自己開熱點」還是「連到別人
/// 的 WiFi」。
NetworkAvailability classifyNetworkInterfaces(
  List<NetworkInterfaceCandidate> raw,
) {
  final survivors = raw.where((candidate) {
    final name = candidate.interfaceName.toLowerCase();
    final isCellular = _cellularInterfacePrefixes.any(name.startsWith);
    final isVpn = _vpnInterfacePrefixes.any(name.startsWith);
    return !isCellular && !isVpn;
  });
  for (final candidate in survivors) {
    if (_isPrivateIPv4(candidate.ipAddress)) {
      return NetworkAvailability(
        kind: NetworkAvailabilityKind.hotspot,
        ipAddress: candidate.ipAddress,
        allCandidates: raw,
      );
    }
  }
  return NetworkAvailability(
    kind: NetworkAvailabilityKind.unavailable,
    allCandidates: raw,
  );
}

bool _isPrivateIPv4(String ipAddress) {
  final octets = ipAddress.split('.').map(int.tryParse).toList();
  if (octets.length != 4 || octets.any((octet) => octet == null)) {
    return false;
  }
  final first = octets[0]!;
  final second = octets[1]!;
  if (first == 10) return true;
  if (first == 172 && second >= 16 && second <= 31) return true;
  if (first == 192 && second == 168) return true;
  return false;
}

Future<List<NetworkInterfaceCandidate>> _listNetworkInterfaceCandidates() async {
  final interfaces = await NetworkInterface.list(
    includeLinkLocal: false,
    type: InternetAddressType.IPv4,
  );
  return [
    for (final iface in interfaces)
      for (final addr in iface.addresses)
        NetworkInterfaceCandidate(
          interfaceName: iface.name,
          ipAddress: addr.address,
        ),
  ];
}

/// 生產環境實作（Task 9 `main.dart` 組裝）。分層判定（design.md「網路先決
/// 條件」）：
/// 1. `connectivity_plus` 判斷已連到別人的 WiFi → 優先在候選清單中找
///    `wlan`-類介面的私有網段 IP（`_findWlanIp`），kind = wifiClient；
///    找不到 `wlan`-類介面時退回 [classifyNetworkInterfaces] 挑出的 IP
///    （防禦性 fallback，避免少數 OEM 介面命名不含 `wlan` 時整個判定
///    失效）。
/// 2. 否則直接採用 [classifyNetworkInterfaces] 的分類結果（hotspot／
///    unavailable）。
///
/// **（`/receiving-code-review` 審查修正，I-1）** 原設計在 wifiClient
/// 情境下直接沿用 [classifyNetworkInterfaces] 對原始清單「線性挑出的第
/// 一個」私有 IP，多網卡裝置（例如同時開啟 USB 網路共享 `rndis0`／接了
/// `eth0`）時 `NetworkInterface.list()` 的回傳順序不保證 `wlan0` 排在前
/// 面，可能誤挑到與電腦不同網段的介面，導致 QR Code／網址指向錯誤
/// 網段。改為明確優先搜尋 `wlan`-類介面，落實 spec.md 原文「找
/// `wlan0`-類介面的 IP」的要求。
///
/// 本函式本身平台相依（`NetworkInterface.list()`／`Connectivity()`），不
/// 在 `flutter test` 環境下單元測試，只驗證上面的純函式部分（見本檔案
/// 對應測試）。
Future<NetworkAvailability> checkNetworkAvailability() async {
  final raw = await _listNetworkInterfaceCandidates();
  final classified = classifyNetworkInterfaces(raw);
  final connectivityResults = await Connectivity().checkConnectivity();
  if (connectivityResults.contains(ConnectivityResult.wifi)) {
    final wlanIp = _findWlanIp(raw) ?? classified.ipAddress;
    if (wlanIp != null) {
      return NetworkAvailability(
        kind: NetworkAvailabilityKind.wifiClient,
        ipAddress: wlanIp,
        allCandidates: classified.allCandidates,
      );
    }
  }
  return classified;
}

/// 在原始候選清單中尋找第一個介面名稱以 `wlan`（不分大小寫）開頭且 IP
/// 屬私有網段的候選項；找不到回傳 `null`。
String? _findWlanIp(List<NetworkInterfaceCandidate> raw) {
  for (final candidate in raw) {
    if (candidate.interfaceName.toLowerCase().startsWith('wlan') &&
        _isPrivateIPv4(candidate.ipAddress)) {
      return candidate.ipAddress;
    }
  }
  return null;
}
```

- [ ] **Step 4: 執行測試，確認通過**

Run: `flutter test test/wifi_transfer/network_availability_test.dart`
Expected: PASS，6 個測試全數通過。

- [ ] **Step 5: `flutter analyze` 確認乾淨**

Run: `flutter analyze lib/wifi_transfer/network_availability.dart test/wifi_transfer/network_availability_test.dart`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add app/lib/wifi_transfer/network_availability.dart app/test/wifi_transfer/network_availability_test.dart
git commit -m "$(cat <<'EOF'
feat(wifi-transfer): 新增網路先決條件偵測 network_availability.dart

epic-44-wifi-book-transfer Issue 1：NetworkAvailabilityKind 三態
（wifiClient/hotspot/unavailable）、純函式 classifyNetworkInterfaces()
（蜂巢式/VPN 介面名稱黑名單過濾＋私有網段 IP 挑選，完整單元測試覆蓋）、
生產環境 checkNetworkAvailability()（connectivity_plus 判斷 WiFi 客戶端
時優先挑選 wlan-類介面 IP、找不到才退回純函式挑選結果，避免多網卡裝置
誤判網段；本身平台相依不單元測試）。

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: `wifi_transfer_service.dart`——型別與 `WifiTransferService` 骨架

**Files:**
- Create: `app/lib/wifi_transfer/wifi_transfer_service.dart`
- Test: `app/test/wifi_transfer/wifi_transfer_service_test.dart`

**Interfaces:**
- Consumes：`LibraryRepository`（`app/lib/library/library_repository.dart`）、`BookImportService`（`app/lib/library/book_import_service.dart`）、`ComputeRemoteFingerprint`（`app/lib/library/book_content_fingerprint.dart`）、`BookFileFormat`（`app/lib/library/models/library_enums.dart`）。
- Produces：
  - `enum UploadOutcome { imported, duplicateSkipped, unsupportedFormat, failed }`
  - `class UploadResult { final String originalFileName; final UploadOutcome outcome; }`
  - `class DownloadableBook { final String id; final String title; final BookFileFormat format; final int? sizeBytes; }`
  - `class DownloadSource { final String resolvedPath; final String downloadFileName; final bool isTemporaryFile; }`
  - `class WifiTransferService`：建構子 `required libraryRepository/importService/computeFingerprint/materializeContentUri/deleteFile`；三個方法 `handleUploadedFile()`／`listDownloadableBooks()`／`resolveDownloadSource()` 目前皆 `throw UnimplementedError()`，供 Task 4（`WifiTransferHttpServer`）建構子型別依賴、供 Issue 2/3 填入實作。

- [ ] **Step 1: 寫失敗測試**

Create `app/test/wifi_transfer/wifi_transfer_service_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/wifi_transfer/wifi_transfer_service.dart';

import '../support/fake_book_import_service.dart';
import '../support/fake_library_repository.dart';
import '../support/fake_fingerprint_computer.dart';

void main() {
  WifiTransferService buildService() {
    final fingerprintComputer = FakeFingerprintComputer();
    return WifiTransferService(
      libraryRepository: FakeLibraryRepository(),
      importService: FakeBookImportService(),
      computeFingerprint: fingerprintComputer.call,
      materializeContentUri: (uri) async => null,
      deleteFile: (path) async {},
    );
  }

  test('骨架方法尚未實作，呼叫時明確拋出 UnimplementedError（Issue 2/3 填入前的契約）',
      () async {
    final service = buildService();

    await expectLater(
      service.handleUploadedFile(
        landedPath: '/tmp/a.epub',
        originalFileName: 'a.epub',
        format: BookFileFormat.epub,
      ),
      throwsA(isA<UnimplementedError>()),
    );
    await expectLater(
      service.listDownloadableBooks(),
      throwsA(isA<UnimplementedError>()),
    );
    await expectLater(
      service.resolveDownloadSource('book1'),
      throwsA(isA<UnimplementedError>()),
    );
  });
}
```

- [ ] **Step 2: 執行測試，確認失敗**

Run: `flutter test test/wifi_transfer/wifi_transfer_service_test.dart`
Expected: FAIL，編譯錯誤（`wifi_transfer_service.dart` 尚不存在）。

- [ ] **Step 3: 實作 `wifi_transfer_service.dart`**

Create `app/lib/wifi_transfer/wifi_transfer_service.dart`：

```dart
import '../library/book_content_fingerprint.dart';
import '../library/book_import_service.dart';
import '../library/library_repository.dart';
import '../library/models/library_enums.dart';

/// 一次上傳單一檔案的處理結果（epic-44-wifi-book-transfer spec.md
/// 「`wifi_transfer_service.dart`」，Issue 3 填入 [WifiTransferService.handleUploadedFile]
/// 實作時對應的四種結果）。
enum UploadOutcome { imported, duplicateSkipped, unsupportedFormat, failed }

class UploadResult {
  final String originalFileName;
  final UploadOutcome outcome;
  const UploadResult({required this.originalFileName, required this.outcome});
}

/// `GET /api/books` 下載清單的單一項目（Issue 2 填入
/// [WifiTransferService.listDownloadableBooks] 實作時使用）。[sizeBytes]
/// 對 `content://` 來源或本機檔案已不存在時恆為 `null`（清單階段嚴禁觸發
/// 材質化）。
class DownloadableBook {
  final String id;
  final String title;
  final BookFileFormat format;
  final int? sizeBytes;
  const DownloadableBook({
    required this.id,
    required this.title,
    required this.format,
    this.sizeBytes,
  });
}

/// 下載時實際要串流的來源資訊（Issue 2 填入
/// [WifiTransferService.resolveDownloadSource] 實作時使用）。
/// [resolvedPath] 一律是可直接 `File.openRead()` 的本機路徑（`content://`
/// 已由呼叫端材質化為暫存檔）；[downloadFileName] 已套用「TXT/MD 來源
/// 書籍誠實回傳 .epub」規則。[isTemporaryFile] 為 `true` 時，HTTP 回應
/// 完成/斷線後呼叫端須刪除 [resolvedPath]。
class DownloadSource {
  final String resolvedPath;
  final String downloadFileName;
  final bool isTemporaryFile;
  const DownloadSource({
    required this.resolvedPath,
    required this.downloadFileName,
    required this.isTemporaryFile,
  });
}

/// 純邏輯層，建構子全部依賴皆可注入假實作，供 `flutter test` 驗證業務
/// 規則（格式白名單、去重、下載清單過濾）而不需要真實 sqflite/原生呼叫/
/// socket。比照 `RemoteCatalogDependencies`／`ComputeRemoteFingerprint`
/// 既有的依賴注入慣例。
///
/// 本 Issue（Issue 1）只建立骨架——三個業務方法先 `throw
/// UnimplementedError()`，讓 [WifiTransferHttpServer]（Task 4）的建構子
/// 型別依賴可以編譯通過；Issue 2 填入 [listDownloadableBooks]／
/// [resolveDownloadSource]，Issue 3 填入 [handleUploadedFile]。
class WifiTransferService {
  final LibraryRepository libraryRepository;
  final BookImportService importService;
  final ComputeRemoteFingerprint computeFingerprint;

  /// 材質化 `content://` URI 為本機暫存檔（Issue 0 修正後的
  /// `readContentUriAll` 頂層函式變數，走背景佇列 channel）。失敗時回傳
  /// `null`。
  final Future<String?> Function(String contentUri) materializeContentUri;

  /// 刪除一個檔案路徑（生產環境為 `File(path).delete()`）。
  final Future<void> Function(String path) deleteFile;

  const WifiTransferService({
    required this.libraryRepository,
    required this.importService,
    required this.computeFingerprint,
    required this.materializeContentUri,
    required this.deleteFile,
  });

  /// Issue 3 實作：對落地檔案算內容指紋 → 查重複 → 匯入或略過，詳見
  /// spec.md「`wifi_transfer_service.dart`」。
  Future<UploadResult> handleUploadedFile({
    required String landedPath,
    required String originalFileName,
    required BookFileFormat format,
  }) async {
    throw UnimplementedError('Issue 3 實作：上傳落地/去重/匯入邏輯');
  }

  /// Issue 2 實作：呼叫 `libraryRepository.listBooks()` 並過濾
  /// `isDownloaded == true`，詳見 spec.md「`wifi_transfer_service.dart`」。
  Future<List<DownloadableBook>> listDownloadableBooks() async {
    throw UnimplementedError('Issue 2 實作：下載清單查詢');
  }

  /// Issue 2 實作：`findBookById(bookId)` → `content://` 材質化 →
  /// TXT/MD 副檔名改寫，詳見 spec.md「`wifi_transfer_service.dart`」。
  Future<DownloadSource?> resolveDownloadSource(String bookId) async {
    throw UnimplementedError('Issue 2 實作：下載來源解析');
  }
}
```

- [ ] **Step 4: 執行測試，確認通過**

Run: `flutter test test/wifi_transfer/wifi_transfer_service_test.dart`
Expected: PASS。

- [ ] **Step 5: `flutter analyze` 確認乾淨**

Run: `flutter analyze lib/wifi_transfer/wifi_transfer_service.dart test/wifi_transfer/wifi_transfer_service_test.dart`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add app/lib/wifi_transfer/wifi_transfer_service.dart app/test/wifi_transfer/wifi_transfer_service_test.dart
git commit -m "$(cat <<'EOF'
feat(wifi-transfer): 新增 WifiTransferService 骨架與相關型別

epic-44-wifi-book-transfer Issue 1：UploadOutcome/UploadResult/
DownloadableBook/DownloadSource 四個型別＋WifiTransferService 完整
欄位宣告與建構子，三個業務方法（handleUploadedFile/
listDownloadableBooks/resolveDownloadSource）先 throw
UnimplementedError()，讓 WifiTransferHttpServer 的建構子型別依賴可以
編譯通過；Issue 2/3 分別填入實作。

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: PC 端網頁骨架與 asset 註冊

**Files:**
- Create: `app/assets/wifi_transfer/index.html`
- Modify: `app/pubspec.yaml`

**Interfaces:**
- Produces：`assets/wifi_transfer/index.html`（`rootBundle.loadString()` 可讀取的 Flutter asset），供 Task 4 的 `GET /` 路由與其測試使用。

- [ ] **Step 1: 建立 HTML 骨架**

Create `app/assets/wifi_transfer/index.html`：

```html
<!DOCTYPE html>
<html lang="zh-Hant">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>elinkBook WiFi 傳書</title>
<style>
  body {
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
    margin: 0;
    padding: 16px;
    background: #f5f5f5;
    color: #222;
  }
  h1 { font-size: 20px; }
  section {
    background: #fff;
    border-radius: 8px;
    padding: 16px;
    margin-bottom: 16px;
  }
  .placeholder { color: #888; }
</style>
</head>
<body>
  <h1>elinkBook WiFi 傳書</h1>
  <section id="download-section">
    <h2>下載書籍</h2>
    <p class="placeholder">開發中（Issue 2）</p>
  </section>
  <section id="upload-section">
    <h2>上傳書籍</h2>
    <p class="placeholder">開發中（Issue 3）</p>
  </section>
</body>
</html>
```

- [ ] **Step 2: 在 `pubspec.yaml` 註冊 asset**

Edit `app/pubspec.yaml`，在既有 `flutter: assets:` 清單中新增一行（緊接在既有字型/fixture 條目之後即可，位置不影響行為）：

```yaml
    - assets/wifi_transfer/index.html
```

- [ ] **Step 3: `flutter pub get` 確認 asset 宣告有效**

Run: `flutter pub get`
Expected: `Got dependencies!`，無錯誤（本步驟純粹驗證 YAML 語法正確；實際載入驗證留給 Task 4 的 `GET /` 測試）。

- [ ] **Step 4: Commit**

```bash
git add app/assets/wifi_transfer/index.html app/pubspec.yaml
git commit -m "$(cat <<'EOF'
feat(wifi-transfer): 新增 PC 端網頁骨架 assets/wifi_transfer/index.html

epic-44-wifi-book-transfer Issue 1：單一自我完備 HTML 檔案（無外部
資源），下載/上傳區塊先留白顯示「開發中」，Issue 2/3 補上實際 JS
邏輯。已於 pubspec.yaml 宣告為 asset。

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: `wifi_transfer_http_server.dart`——`WifiTransferHttpServer`

**Files:**
- Create: `app/lib/wifi_transfer/wifi_transfer_http_server.dart`
- Test: `app/test/wifi_transfer/wifi_transfer_http_server_test.dart`

**Interfaces:**
- Consumes：`WifiTransferService`（Task 2）、`assets/wifi_transfer/index.html`（Task 3）。
- Produces：
  - `class WifiTransferHttpServer`：建構子 `required WifiTransferService service, int maxConcurrentTransfers = 2`。
  - `ValueListenable<int> get activeTransfersNotifier`——目前活躍傳輸數，供 Task 6（`WifiTransferScreen`）的 `PopScope` 使用。
  - `Future<T> withTransferPermit<T>(Future<T> Function() action)`——併發節流公開方法，供 Issue 2/3 的下載/上傳路由包住各自實際傳輸邏輯呼叫。
  - `Future<HttpServer> start({required String ipAddress, required int port})`——實際 bind `InternetAddress.anyIPv4`；`GET /` 回應 `assets/wifi_transfer/index.html`；`/api/books`／`/api/books/<id>/download`／`/api/upload` 回 501。
  - `Future<void> stop(HttpServer server)`。

- [ ] **Step 1: 寫失敗測試**

Create `app/test/wifi_transfer/wifi_transfer_http_server_test.dart`：

```dart
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:elinkbook/wifi_transfer/wifi_transfer_http_server.dart';
import 'package:elinkbook/wifi_transfer/wifi_transfer_service.dart';

import '../support/fake_book_import_service.dart';
import '../support/fake_library_repository.dart';
import '../support/fake_fingerprint_computer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  WifiTransferService buildService() {
    final fingerprintComputer = FakeFingerprintComputer();
    return WifiTransferService(
      libraryRepository: FakeLibraryRepository(),
      importService: FakeBookImportService(),
      computeFingerprint: fingerprintComputer.call,
      materializeContentUri: (uri) async => null,
      deleteFile: (path) async {},
    );
  }

  group('WifiTransferHttpServer 路由', () {
    late WifiTransferHttpServer wifiServer;
    late HttpServer httpServer;

    setUp(() async {
      wifiServer = WifiTransferHttpServer(service: buildService());
      httpServer = await wifiServer.start(ipAddress: '127.0.0.1', port: 0);
    });

    tearDown(() => wifiServer.stop(httpServer));

    test('start() 綁定成功並回傳實際監聽的埠號', () {
      expect(httpServer.port, greaterThan(0));
    });

    test('GET / 回傳 index.html 內容與正確 Content-Type／Cache-Control', () async {
      final response =
          await http.get(Uri.parse('http://127.0.0.1:${httpServer.port}/'));
      expect(response.statusCode, 200);
      expect(response.headers['content-type'], contains('text/html'));
      expect(response.headers['cache-control'], 'no-cache');
      expect(response.body, contains('elinkBook WiFi 傳書'));
    });

    test('GET /index.html 與 GET / 行為相同（M-3：容錯使用者手動輸入的網址）',
        () async {
      final response = await http
          .get(Uri.parse('http://127.0.0.1:${httpServer.port}/index.html'));
      expect(response.statusCode, 200);
      expect(response.body, contains('elinkBook WiFi 傳書'));
    });

    test('GET /api/books 回傳 501（留給 Issue 2 實作）', () async {
      final response = await http
          .get(Uri.parse('http://127.0.0.1:${httpServer.port}/api/books'));
      expect(response.statusCode, 501);
    });

    test('GET /api/books/<id>/download 回傳 501（留給 Issue 2 實作）', () async {
      final response = await http.get(Uri.parse(
          'http://127.0.0.1:${httpServer.port}/api/books/abc123/download'));
      expect(response.statusCode, 501);
    });

    test('POST /api/upload 回傳 501（留給 Issue 3 實作）', () async {
      final response = await http
          .post(Uri.parse('http://127.0.0.1:${httpServer.port}/api/upload'));
      expect(response.statusCode, 501);
    });

    test('未知路徑回傳 404', () async {
      final response = await http
          .get(Uri.parse('http://127.0.0.1:${httpServer.port}/unknown'));
      expect(response.statusCode, 404);
    });

    test('stop() 後伺服器確實關閉，後續連線失敗', () async {
      await wifiServer.stop(httpServer);
      await expectLater(
        http.get(Uri.parse('http://127.0.0.1:${httpServer.port}/')),
        throwsA(isA<SocketException>()),
      );
    });
  });

  group('WifiTransferHttpServer.withTransferPermit 併發節流', () {
    test('超過 maxConcurrentTransfers 時第三個呼叫會等待，直到有一個釋放', () async {
      final wifiServer = WifiTransferHttpServer(
        service: buildService(),
        maxConcurrentTransfers: 2,
      );
      final release1 = Completer<void>();
      final release2 = Completer<void>();
      var thirdStarted = false;

      final task1 = wifiServer.withTransferPermit(() async {
        await release1.future;
        return 1;
      });
      final task2 = wifiServer.withTransferPermit(() async {
        await release2.future;
        return 2;
      });
      expect(wifiServer.activeTransfersNotifier.value, 2);

      final task3 = wifiServer.withTransferPermit(() async {
        thirdStarted = true;
        return 3;
      });
      expect(thirdStarted, isFalse, reason: '許可已滿，第三個應該還在等待');

      release1.complete();
      final result3 = await task3;
      expect(result3, 3);
      expect(thirdStarted, isTrue);

      release2.complete();
      await Future.wait([task1, task2]);
      expect(wifiServer.activeTransfersNotifier.value, 0);
    });

    test('action 拋出例外時仍會釋放許可（finally），不會卡死後續請求', () async {
      final wifiServer = WifiTransferHttpServer(
        service: buildService(),
        maxConcurrentTransfers: 1,
      );

      await expectLater(
        wifiServer.withTransferPermit(() async => throw StateError('boom')),
        throwsA(isA<StateError>()),
      );
      expect(wifiServer.activeTransfersNotifier.value, 0);

      final result = await wifiServer.withTransferPermit(() async => 'ok');
      expect(result, 'ok');
    });

    test('stop() 時會讓仍在排隊等許可的呼叫以例外結束，不會永久卡住（M-4）',
        () async {
      final wifiServer = WifiTransferHttpServer(
        service: buildService(),
        maxConcurrentTransfers: 1,
      );
      final holdFirst = Completer<void>();

      final task1 = wifiServer.withTransferPermit(() async {
        await holdFirst.future;
        return 1;
      });
      // 許可已滿（1/1），第二個呼叫進入 _waitQueue 排隊。
      final task2 =
          wifiServer.withTransferPermit(() async => 2);
      expect(wifiServer.activeTransfersNotifier.value, 1);

      final httpServer =
          await wifiServer.start(ipAddress: '127.0.0.1', port: 0);
      await wifiServer.stop(httpServer);

      await expectLater(task2, throwsA(isA<StateError>()));

      holdFirst.complete();
      expect(await task1, 1);
    });
  });
}
```

- [ ] **Step 2: 執行測試，確認失敗**

Run: `flutter test test/wifi_transfer/wifi_transfer_http_server_test.dart`
Expected: FAIL，編譯錯誤（`wifi_transfer_http_server.dart` 尚不存在）。

- [ ] **Step 3: 實作 `wifi_transfer_http_server.dart`**

Create `app/lib/wifi_transfer/wifi_transfer_http_server.dart`：

```dart
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;

import 'wifi_transfer_service.dart';

/// 「來源」畫面 WiFi 傳書入口啟動的本機 HTTP Server 薄殼層
/// （epic-44-wifi-book-transfer spec.md「`wifi_transfer_http_server.dart`」）。
/// 未使用 `shelf_router`（非本專案依賴）——路由改用簡單的 `request.url.path`
/// 字串/正則比對，路由數量少（4 條），手動比對已足夠清楚。
class WifiTransferHttpServer {
  final WifiTransferService service;
  final int maxConcurrentTransfers;

  WifiTransferHttpServer({
    required this.service,
    this.maxConcurrentTransfers = 2,
  });

  final ValueNotifier<int> _activeTransfersNotifier = ValueNotifier<int>(0);

  /// 目前活躍中的上傳/下載請求數（進入 [withTransferPermit] 的 action
  /// 時 +1、結束/例外時 -1），供 `WifiTransferScreen` 的 `PopScope`
  /// 判斷「離開畫面時是否有傳輸進行中」。
  ValueListenable<int> get activeTransfersNotifier => _activeTransfersNotifier;

  int _activePermits = 0;
  final List<Completer<void>> _waitQueue = [];

  /// 併發節流：進入實際傳輸邏輯前先取得許可（超過 [maxConcurrentTransfers]
  /// 時在此等待，不回錯誤碼給客戶端，符合「零意外」原則），結束時（含
  /// 拋出例外）一律釋放並同步更新 [activeTransfersNotifier]。Issue 2／3
  /// 的下載/上傳路由須把各自的實際傳輸邏輯包在這個方法內呼叫，例如：
  /// `return withTransferPermit(() => _handleDownload(bookId));`
  Future<T> withTransferPermit<T>(Future<T> Function() action) async {
    if (_activePermits >= maxConcurrentTransfers) {
      final completer = Completer<void>();
      _waitQueue.add(completer);
      await completer.future;
    }
    _activePermits++;
    _activeTransfersNotifier.value = _activePermits;
    try {
      return await action();
    } finally {
      _activePermits--;
      _activeTransfersNotifier.value = _activePermits;
      if (_waitQueue.isNotEmpty) {
        _waitQueue.removeAt(0).complete();
      }
    }
  }

  /// 實際 bind 一律用 `InternetAddress.anyIPv4`（`0.0.0.0`），不使用
  /// [ipAddress] 本身 bind——部分客製化 Android 系統對熱點虛擬網卡 IP
  /// 執行 socket bind 容易遇到 `EADDRNOTAVAIL`；[ipAddress] 目前在本方法
  /// 內未使用，只保留給呼叫端（`WifiTransferScreen`）組顯示網址／QR Code
  /// 使用，與實際監聽位址脫鉤，更具強韌性。[port] 為 0 時系統動態分配，
  /// 回傳的 `HttpServer.port` 是實際監聽的埠號。
  Future<HttpServer> start({required String ipAddress, required int port}) {
    return shelf_io.serve(_handleRequest, InternetAddress.anyIPv4, port);
  }

  /// **（`/receiving-code-review` 審查修正，M-4）** 關閉伺服器前先讓
  /// 仍在 [_waitQueue] 排隊等待許可的呼叫端以例外結束（而非永遠卡在
  /// `await completer.future`）——伺服器都已經要關閉了，繼續等待一個
  /// 不會再被釋放的許可沒有意義，讓呼叫端（Issue 2/3 的路由 handler）
  /// 能明確得知「伺服器已關閉」並結束該次 HTTP 請求，而不是讓連線懸掛。
  Future<void> stop(HttpServer server) async {
    while (_waitQueue.isNotEmpty) {
      _waitQueue.removeAt(0).completeError(
            StateError('WifiTransferHttpServer 已停止，取消排隊中的請求'),
          );
    }
    await server.close(force: true);
  }

  Future<shelf.Response> _handleRequest(shelf.Request request) async {
    final path = request.url.path;
    // 【`/receiving-code-review` 審查修正，M-3】容錯使用者/瀏覽器手動
    // 輸入 `/index.html` 的情境；`cache-control: no-cache` 避免 App 版本
    // 更新後，PC 端瀏覽器快取了舊版 HTML/JS（此頁面每次由 App 當下的
    // asset bundle 即時提供，不該被瀏覽器快取）。
    if (request.method == 'GET' && (path == '' || path == 'index.html')) {
      final html =
          await rootBundle.loadString('assets/wifi_transfer/index.html');
      return shelf.Response.ok(
        html,
        headers: {
          'content-type': 'text/html; charset=utf-8',
          'cache-control': 'no-cache',
        },
      );
    }
    if (request.method == 'GET' && path == 'api/books') {
      // Issue 2 補上：service.listDownloadableBooks()。
      return shelf.Response(501, body: 'Not Implemented');
    }
    if (request.method == 'GET' &&
        RegExp(r'^api/books/[^/]+/download$').hasMatch(path)) {
      // Issue 2 補上：service.resolveDownloadSource()。
      return shelf.Response(501, body: 'Not Implemented');
    }
    if (request.method == 'POST' && path == 'api/upload') {
      // Issue 3 補上：shelf_multipart 解析＋service.handleUploadedFile()。
      return shelf.Response(501, body: 'Not Implemented');
    }
    return shelf.Response.notFound('Not Found');
  }
}
```

- [ ] **Step 4: 執行測試，確認通過**

Run: `flutter test test/wifi_transfer/wifi_transfer_http_server_test.dart`
Expected: PASS，全數測試通過。

- [ ] **Step 5: `flutter analyze` 確認乾淨**

Run: `flutter analyze lib/wifi_transfer/wifi_transfer_http_server.dart test/wifi_transfer/wifi_transfer_http_server_test.dart`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add app/lib/wifi_transfer/wifi_transfer_http_server.dart app/test/wifi_transfer/wifi_transfer_http_server_test.dart
git commit -m "$(cat <<'EOF'
feat(wifi-transfer): 新增 WifiTransferHttpServer（伺服器骨架＋併發節流）

epic-44-wifi-book-transfer Issue 1：start()/stop() 綁定 InternetAddress.
anyIPv4；GET /、GET /index.html 真實服務 assets/wifi_transfer/index.html
（no-cache）；/api/books、/api/books/<id>/download、/api/upload 先回
501 留給 Issue 2/3；withTransferPermit() 公開併發節流方法＋
activeTransfersNotifier 供跨路由共用，含併發/例外釋放的完整測試。
stop() 會讓仍在排隊等許可的呼叫以例外結束，不留下永久懸掛的請求
（/receiving-code-review 審查修正 M-3/M-4）。測試以真實 loopback HTTP
往返驗證，不需裝置。

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: `wifi_transfer_dependencies.dart`——`WifiTransferDependencies` bundle

**Files:**
- Create: `app/lib/wifi_transfer/wifi_transfer_dependencies.dart`

**Interfaces:**
- Consumes：`LibraryRepository`、`BookImportService`、`ComputeRemoteFingerprint`（既有型別）、`CheckNetworkAvailability`（Task 1）。
- Produces：`class WifiTransferDependencies`，四個 nullable 欄位（`libraryRepository`／`importService`／`computeFingerprint`／`checkNetworkAvailability`），全部預設 `null`。供 Task 7（`SourcesHomeScreen`）、Task 8（`AdaptiveShellScaffold`）、Task 9（`main.dart`）使用。

- [ ] **Step 1: 實作 `wifi_transfer_dependencies.dart`**

Create `app/lib/wifi_transfer/wifi_transfer_dependencies.dart`：

```dart
import 'package:flutter/foundation.dart';

import '../library/book_content_fingerprint.dart';
import '../library/book_import_service.dart';
import '../library/library_repository.dart';
import 'network_availability.dart';

/// WiFi 傳書畫面的依賴注入 bundle（epic-44-wifi-book-transfer spec.md
/// 「依賴注入收斂」），比照既有 `LibraryCloudAccountDependencies`／
/// `LibraryRemoteLibraryDependencies` 慣例：全部欄位皆可為 `null`，
/// `SourcesHomeScreen` 依此決定是否顯示「WiFi 傳書」入口（任一欄位為
/// `null` 即不顯示）。
///
/// `materializeContentUri`／`deleteFile` 刻意不進這個 bundle——兩者是純
/// 技術轉接（既有 `readContentUriAll` 頂層函式／`dart:io` 檔案刪除），
/// 沒有「功能未啟用時為 null」的語意，直接在 `WifiTransferScreen`
/// 內部以頂層函式呼叫，不需要呼叫端逐層注入（比照 `RemoteCatalogDependencies`
/// 刻意排除 `computeFingerprint` 的先例：只收斂「呼叫端可能沒有」的
/// 依賴，不收斂「處處皆可用的既有機制」）。純資料容器，無邏輯，不另立
/// 專屬測試檔——由 Task 7/8 的 widget test 間接驗證其欄位正確傳遞。
@immutable
class WifiTransferDependencies {
  final LibraryRepository? libraryRepository;
  final BookImportService? importService;
  final ComputeRemoteFingerprint? computeFingerprint;
  final CheckNetworkAvailability? checkNetworkAvailability;

  const WifiTransferDependencies({
    this.libraryRepository,
    this.importService,
    this.computeFingerprint,
    this.checkNetworkAvailability,
  });
}
```

- [ ] **Step 2: `flutter analyze` 確認乾淨**

Run: `flutter analyze lib/wifi_transfer/wifi_transfer_dependencies.dart`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add app/lib/wifi_transfer/wifi_transfer_dependencies.dart
git commit -m "$(cat <<'EOF'
feat(wifi-transfer): 新增 WifiTransferDependencies 依賴注入 bundle

epic-44-wifi-book-transfer Issue 1：比照既有 LibraryCloudAccountDependencies
慣例，四個欄位皆可為 null，供 SourcesHomeScreen 決定是否顯示「WiFi
傳書」入口。純資料容器，由後續 Task 的 widget test 間接驗證。

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: `WifiTransferScreen` 畫面

**Files:**
- Create: `app/test/support/fake_wakelock_plus_platform.dart`
- Create: `app/lib/screens/wifi_transfer_screen.dart`
- Test: `app/test/screens/wifi_transfer_screen_test.dart`
- Modify: `app/pubspec.yaml`（新增 `wakelock_plus_platform_interface` 至 `dev_dependencies`，供測試覆寫 `WakelockPlus` 平台呼叫）

**Interfaces:**
- Consumes：`NetworkAvailability`／`NetworkAvailabilityKind`／`NetworkInterfaceCandidate`／`CheckNetworkAvailability`（Task 1）、`WifiTransferService`（Task 2）、`WifiTransferHttpServer`（Task 4）、`readContentUriAll`（`app/lib/search/pdf_content_indexer.dart`，Issue 0 已修正 channel）、`LibraryRepository`／`BookImportService`／`ComputeRemoteFingerprint`（既有型別）。
- Produces：`class WifiTransferScreen`——建構子 `required libraryRepository/importService/computeFingerprint/checkNetworkAvailability`，`@visibleForTesting ValueListenable<int>? activeTransfersNotifierOverride`（預設 `null`）。Widget Key：`Key('wifi_transfer_ip_text')`／`Key('wifi_transfer_qr_code')`／`Key('wifi_transfer_manual_override_button')`／`Key('wifi_transfer_candidate_<interfaceName>')`。供 Task 7（`SourcesHomeScreen`）建構使用。`class FakeWakelockPlusPlatform`（`app/test/support/fake_wakelock_plus_platform.dart`）——供本 Task 與 Task 7 的 `sources_home_screen_test.dart` 共用（**`/receiving-code-review` 審查修正 C-1**：`WifiTransferScreen.initState()` 呼叫 `WakelockPlus.enable()`，`flutter test` 環境下未覆寫平台實例會拋出 `PlatformException(channel-error, ...)`——已查證 `wakelock_plus_platform_interface-1.6.0` 的 pigeon 產生碼 `_extractReplyValueOrThrow()`（`messages.g.dart:17-21`）在找不到 mock handler 時確實會這樣拋出，任何會掛載 `WifiTransferScreen` 的測試皆須設定此替身，Task 7 原計畫遺漏此設定會導致該測試 100% 崩潰）。

- [ ] **Step 1: 新增 `wakelock_plus_platform_interface` dev dependency**

Run: `flutter pub add dev:wakelock_plus_platform_interface`
Expected: 指令成功，`app/pubspec.yaml` 的 `dev_dependencies:` 區塊自動新增一行（比照既有 `flutter_secure_storage_platform_interface` 同類測試替身依賴慣例）。

- [ ] **Step 2: 建立共用測試替身 `FakeWakelockPlusPlatform`**

**（`/receiving-code-review` 審查修正，C-1）** 獨立為共用測試支援檔，避免 Task 7 的 `sources_home_screen_test.dart`（該測試會點擊入口卡片導覽至 `WifiTransferScreen`，同樣觸發 `WakelockPlus.enable()`）另外重寫一份或遺漏設定。

Create `app/test/support/fake_wakelock_plus_platform.dart`：

```dart
import 'package:wakelock_plus_platform_interface/wakelock_plus_platform_interface.dart';

/// 供 widget test 覆寫 `wakelockPlusPlatformInstance`（見
/// `package:wakelock_plus/wakelock_plus.dart`），避免測試環境下
/// `WakelockPlus.enable()/disable()` 呼叫真實平台通道拋出
/// `PlatformException(channel-error, ...)`（`flutter test` 環境未提供
/// mock handler 時，`wakelock_plus_platform_interface` 的 pigeon 產生碼
/// `_extractReplyValueOrThrow()` 會直接拋出，見
/// `epic-44-wifi-book-transfer` `reviews/review-plan-issue-1.md` C-1）。
/// 任何會掛載 `WifiTransferScreen` 的測試皆須在 `setUp`／`tearDown` 中
/// 覆寫／還原 `wakelockPlusPlatformInstance`。
class FakeWakelockPlusPlatform extends WakelockPlusPlatformInterface {
  bool isEnabled = false;
  final List<bool> toggleCalls = [];

  @override
  Future<void> toggle({required bool enable}) async {
    isEnabled = enable;
    toggleCalls.add(enable);
  }

  @override
  Future<bool> get enabled async => isEnabled;
}
```

- [ ] **Step 3: 寫失敗測試**

Create `app/test/screens/wifi_transfer_screen_test.dart`：

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wakelock_plus/wakelock_plus.dart' show wakelockPlusPlatformInstance;
import 'package:wakelock_plus_platform_interface/wakelock_plus_platform_interface.dart';
import 'package:elinkbook/screens/wifi_transfer_screen.dart';
import 'package:elinkbook/wifi_transfer/network_availability.dart';

import '../support/fake_book_import_service.dart';
import '../support/fake_library_repository.dart';
import '../support/fake_fingerprint_computer.dart';
import '../support/fake_wakelock_plus_platform.dart';

void main() {
  late FakeWakelockPlusPlatform fakeWakelock;
  late WakelockPlusPlatformInterface originalWakelockPlatform;

  setUp(() {
    fakeWakelock = FakeWakelockPlusPlatform();
    originalWakelockPlatform = wakelockPlusPlatformInstance;
    wakelockPlusPlatformInstance = fakeWakelock;
  });

  tearDown(() {
    wakelockPlusPlatformInstance = originalWakelockPlatform;
  });

  Widget buildScreen({
    required CheckNetworkAvailability checkNetworkAvailability,
    ValueListenable<int>? activeTransfersNotifierOverride,
  }) {
    return MaterialApp(
      home: WifiTransferScreen(
        libraryRepository: FakeLibraryRepository(),
        importService: FakeBookImportService(),
        computeFingerprint: FakeFingerprintComputer().call,
        checkNetworkAvailability: checkNetworkAvailability,
        activeTransfersNotifierOverride:
            activeTransfersNotifierOverride ?? ValueNotifier<int>(0),
      ),
    );
  }

  testWidgets('wifiClient：顯示 IP 文字與 QR Code', (tester) async {
    await tester.pumpWidget(buildScreen(
      checkNetworkAvailability: () async => const NetworkAvailability(
        kind: NetworkAvailabilityKind.wifiClient,
        ipAddress: '192.168.1.5',
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('wifi_transfer_ip_text')), findsOneWidget);
    expect(find.text('http://192.168.1.5:8080'), findsOneWidget);
    expect(find.byKey(const Key('wifi_transfer_qr_code')), findsOneWidget);
  });

  testWidgets('hotspot：顯示 IP 文字與 QR Code', (tester) async {
    await tester.pumpWidget(buildScreen(
      checkNetworkAvailability: () async => const NetworkAvailability(
        kind: NetworkAvailabilityKind.hotspot,
        ipAddress: '192.168.43.1',
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('wifi_transfer_ip_text')), findsOneWidget);
    expect(find.text('http://192.168.43.1:8080'), findsOneWidget);
    expect(find.byKey(const Key('wifi_transfer_qr_code')), findsOneWidget);
  });

  testWidgets('unavailable：停用文案與手動覆寫按鈕，無 IP/QR', (tester) async {
    await tester.pumpWidget(buildScreen(
      checkNetworkAvailability: () async => const NetworkAvailability(
        kind: NetworkAvailabilityKind.unavailable,
        allCandidates: [
          NetworkInterfaceCandidate(
              interfaceName: 'rmnet0', ipAddress: '10.0.0.1'),
        ],
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('wifi_transfer_ip_text')), findsNothing);
    expect(find.byKey(const Key('wifi_transfer_qr_code')), findsNothing);
    expect(find.text('請連線至 WiFi 或開啟手機熱點'), findsOneWidget);
    expect(
      find.byKey(const Key('wifi_transfer_manual_override_button')),
      findsOneWidget,
    );
  });

  testWidgets(
      'unavailable 按下手動覆寫按鈕後列出 allCandidates，點擊候選項後切換為顯示該 IP 網址與 QR Code（M-1）',
      (tester) async {
    await tester.pumpWidget(buildScreen(
      checkNetworkAvailability: () async => const NetworkAvailability(
        kind: NetworkAvailabilityKind.unavailable,
        allCandidates: [
          NetworkInterfaceCandidate(
              interfaceName: 'rmnet0', ipAddress: '10.0.0.1'),
          NetworkInterfaceCandidate(
              interfaceName: 'wlan0', ipAddress: '192.168.1.9'),
        ],
      ),
    ));
    await tester.pumpAndSettle();

    await tester
        .tap(find.byKey(const Key('wifi_transfer_manual_override_button')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('wifi_transfer_candidate_rmnet0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('wifi_transfer_candidate_wlan0')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('wifi_transfer_candidate_wlan0')));
    await tester.pumpAndSettle();

    expect(find.text('http://192.168.1.9:8080'), findsOneWidget);
    expect(find.byKey(const Key('wifi_transfer_qr_code')), findsOneWidget);
  });

  testWidgets('unavailable 且 allCandidates 為空時顯示對應提示', (tester) async {
    await tester.pumpWidget(buildScreen(
      checkNetworkAvailability: () async =>
          const NetworkAvailability(kind: NetworkAvailabilityKind.unavailable),
    ));
    await tester.pumpAndSettle();

    await tester
        .tap(find.byKey(const Key('wifi_transfer_manual_override_button')));
    await tester.pumpAndSettle();

    expect(find.text('找不到任何可用網路介面'), findsOneWidget);
  });

  testWidgets(
      'activeTransfersNotifierOverride > 0 時返回跳出確認對話框，按下確定離開後對話框關閉',
      (tester) async {
    final notifier = ValueNotifier<int>(1);
    await tester.pumpWidget(buildScreen(
      checkNetworkAvailability: () async => const NetworkAvailability(
        kind: NetworkAvailabilityKind.wifiClient,
        ipAddress: '192.168.1.5',
      ),
      activeTransfersNotifierOverride: notifier,
    ));
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('目前尚有檔案正在傳輸'), findsOneWidget);

    await tester.tap(find.text('確定離開'));
    await tester.pumpAndSettle();

    expect(find.text('目前尚有檔案正在傳輸'), findsNothing);
  });

  testWidgets('activeTransfersNotifierOverride == 0 時返回直接放行不跳對話框',
      (tester) async {
    final notifier = ValueNotifier<int>(0);
    await tester.pumpWidget(buildScreen(
      checkNetworkAvailability: () async => const NetworkAvailability(
        kind: NetworkAvailabilityKind.wifiClient,
        ipAddress: '192.168.1.5',
      ),
      activeTransfersNotifierOverride: notifier,
    ));
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('目前尚有檔案正在傳輸'), findsNothing);
  });

  testWidgets('initState 呼叫 WakelockPlus.enable()，dispose 呼叫 disable()',
      (tester) async {
    await tester.pumpWidget(buildScreen(
      checkNetworkAvailability: () async =>
          const NetworkAvailability(kind: NetworkAvailabilityKind.unavailable),
    ));
    await tester.pumpAndSettle();

    expect(fakeWakelock.toggleCalls, [true]);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();

    expect(fakeWakelock.toggleCalls, [true, false]);
  });

  testWidgets(
      'checkNetworkAvailability() 拋出例外時降級為 unavailable，不會因 snapshot.data! 崩潰（I-3）',
      (tester) async {
    await tester.pumpWidget(buildScreen(
      checkNetworkAvailability: () async => throw StateError('模擬平台呼叫失敗'),
    ));
    await tester.pumpAndSettle();

    expect(find.text('請連線至 WiFi 或開啟手機熱點'), findsOneWidget);
  });
}
```

- [ ] **Step 4: 執行測試，確認失敗**

Run: `flutter test test/screens/wifi_transfer_screen_test.dart`
Expected: FAIL，編譯錯誤（`wifi_transfer_screen.dart` 尚不存在）。

- [ ] **Step 5: 實作 `wifi_transfer_screen.dart`**

Create `app/lib/screens/wifi_transfer_screen.dart`：

```dart
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
    _fallbackNotifier.dispose();
    super.dispose();
  }

  Future<void> _confirmLeaveIfTransferring(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('目前尚有檔案正在傳輸'),
        content: const Text('離開將中斷連線，是否確定離開？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('確定離開'),
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
        appBar: AppBar(title: const Text('WiFi 傳書')),
        body: _buildBody(context),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
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
          return const Center(child: Text('請連線至 WiFi 或開啟手機熱點'));
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
                  const Text('在同一個 WiFi 下，用瀏覽器打開以下網址：'),
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
                const Text('請連線至 WiFi 或開啟手機熱點'),
                const SizedBox(height: 16),
                if (!_manualOverrideRequested)
                  ElevatedButton(
                    key: const Key('wifi_transfer_manual_override_button'),
                    onPressed: () =>
                        setState(() => _manualOverrideRequested = true),
                    child: const Text('我確定目前是用手機熱點'),
                  ),
                if (_manualOverrideRequested)
                  if (availability.allCandidates.isEmpty)
                    const Text('找不到任何可用網路介面')
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
```

**關於 I-4 審查建議的部分採納說明**：I-4 建議的第二部分（伺服器啟動期間顯示載入指示器、待綁定完成才切換畫面）本計畫不採納——上面的 `_startingServer` 防重入旗標已解決真正的正確性缺陷（並行啟動導致孤兒 socket 洩漏）；「網址/QR 從預設埠 8080 閃爍為動態埠」是既有「樂觀顯示預設埠、綁定成功後才視實際埠號修正」設計的已知、可接受殘留現象——8080 埠衝突在實務上罕見，為此新增一個載入態旗標、重寫畫面狀態機並連帶調整本 Task 既有 widget test 的斷言時機，成本與 Issue 1 骨架範圍不成比例（YAGNI）；若真機測試發現這個閃爍實際造成使用者困擾，留待後續依真機資料另立工單處理。

- [ ] **Step 6: 執行測試，確認通過**

Run: `flutter test test/screens/wifi_transfer_screen_test.dart`
Expected: PASS，全數測試通過。

- [ ] **Step 7: `flutter analyze` 確認乾淨**

Run: `flutter analyze lib/screens/wifi_transfer_screen.dart test/screens/wifi_transfer_screen_test.dart test/support/fake_wakelock_plus_platform.dart`
Expected: `No issues found!`

- [ ] **Step 8: Commit**

```bash
git add app/pubspec.yaml app/pubspec.lock app/lib/screens/wifi_transfer_screen.dart app/test/screens/wifi_transfer_screen_test.dart app/test/support/fake_wakelock_plus_platform.dart
git commit -m "$(cat <<'EOF'
feat(wifi-transfer): 新增 WifiTransferScreen 畫面

epic-44-wifi-book-transfer Issue 1：顯示 checkNetworkAvailability()
結果（IP/QR Code、unavailable 停用文案與手動覆寫候選清單）、螢幕常亮
（initState/dispose 呼叫 WakelockPlus）、PopScope 離開示警（透過
activeTransfersNotifierOverride 測試接縫繞過真實伺服器啟動，比照
TapZoneDetector 既定慣例）。新增 wakelock_plus_platform_interface
dev dependency 與共用測試替身 FakeWakelockPlusPlatform（供本檔案與
Task 7 sources_home_screen_test.dart 共用）。

/receiving-code-review 審查修正（review-plan-issue-1.md）：I-2 候選
清單與 QR 顯示皆包一層 SingleChildScrollView 避免 RenderFlex
overflow；I-3 _initialize() 例外一律降級為 unavailable 避免
snapshot.data! 裸取崩潰；I-4 新增 _startingServer 防重入旗標避免並行
啟動導致孤兒 socket；M-1 補上點擊候選項切換顯示的測試；M-2
QrImageView 明確指定白色背景避免深色主題黑底黑碼。

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 7: `SourcesHomeScreen`「本機」分區新增入口卡片

**Files:**
- Modify: `app/lib/screens/sources_home_screen.dart`
- Test: `app/test/screens/sources_home_screen_test.dart`

**Interfaces:**
- Consumes：`WifiTransferDependencies`（Task 5）、`WifiTransferScreen`（Task 6）、`FakeWakelockPlusPlatform`（Task 6，`app/test/support/fake_wakelock_plus_platform.dart`）。
- Produces：`SourcesHomeScreen` 新增建構參數 `final WifiTransferDependencies? wifiTransferDependencies`（預設 `null`），供 Task 8（`AdaptiveShellScaffold`）原樣往下傳。

- [ ] **Step 1: 寫失敗測試**

Edit `app/test/screens/sources_home_screen_test.dart`，於檔案頂部新增 import，並在既有測試群組後追加三則測試：

```dart
// 於既有 import 區塊新增：
import 'package:wakelock_plus/wakelock_plus.dart' show wakelockPlusPlatformInstance;
import 'package:wakelock_plus_platform_interface/wakelock_plus_platform_interface.dart';
import 'package:elinkbook/screens/wifi_transfer_screen.dart';
import 'package:elinkbook/wifi_transfer/network_availability.dart';
import 'package:elinkbook/wifi_transfer/wifi_transfer_dependencies.dart';

import '../support/fake_wakelock_plus_platform.dart';
```

**（`/receiving-code-review` 審查修正，C-1）** 在既有 `tearDown`（檔案頂部已有一個處理 `filePickerChannel`／`folderPickerChannel` 的 `tearDown`）之前新增 `setUp`，並在既有 `tearDown` 內補上還原：點擊「WiFi 傳書」入口卡片會導覽至 `WifiTransferScreen`，其 `initState()` 呼叫 `WakelockPlus.enable()`，`flutter test` 環境下未覆寫平台實例會拋出 `PlatformException`，任何一則會觸發這個導覽的測試都需要這個設定：

```dart
// 舊：
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(filePickerChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(folderPickerChannel, null);
  });
```

```dart
// 新：
  late FakeWakelockPlusPlatform fakeWakelock;
  late WakelockPlusPlatformInterface originalWakelockPlatform;

  setUp(() {
    fakeWakelock = FakeWakelockPlusPlatform();
    originalWakelockPlatform = wakelockPlusPlatformInstance;
    wakelockPlusPlatformInstance = fakeWakelock;
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(filePickerChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(folderPickerChannel, null);
    wakelockPlusPlatformInstance = originalWakelockPlatform;
  });
```

```dart
// 於檔案結尾（既有最後一個 testWidgets 之後）新增：

  testWidgets('wifiTransferDependencies 為 null 時不顯示 WiFi 傳書入口', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SourcesHomeScreen(
          repository: FakeLibraryRepository(),
          importService: FakeBookImportService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('sources_wifi_transfer_tile')), findsNothing);
  });

  testWidgets('wifiTransferDependencies 任一欄位為 null 時不顯示入口', (tester) async {
    final fingerprintComputer = FakeFingerprintComputer();
    await tester.pumpWidget(
      MaterialApp(
        home: SourcesHomeScreen(
          repository: FakeLibraryRepository(),
          importService: FakeBookImportService(),
          wifiTransferDependencies: WifiTransferDependencies(
            libraryRepository: FakeLibraryRepository(),
            importService: FakeBookImportService(),
            computeFingerprint: fingerprintComputer.call,
            // checkNetworkAvailability 刻意缺漏
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('sources_wifi_transfer_tile')), findsNothing);
  });

  testWidgets('wifiTransferDependencies 齊全時顯示入口並可點擊導覽至 WifiTransferScreen',
      (tester) async {
    final fingerprintComputer = FakeFingerprintComputer();
    await tester.pumpWidget(
      MaterialApp(
        home: SourcesHomeScreen(
          repository: FakeLibraryRepository(),
          importService: FakeBookImportService(),
          wifiTransferDependencies: WifiTransferDependencies(
            libraryRepository: FakeLibraryRepository(),
            importService: FakeBookImportService(),
            computeFingerprint: fingerprintComputer.call,
            checkNetworkAvailability: () async => const NetworkAvailability(
              kind: NetworkAvailabilityKind.unavailable,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('sources_wifi_transfer_tile')), findsOneWidget);

    await tester.tap(find.byKey(const Key('sources_wifi_transfer_tile')));
    await tester.pumpAndSettle();

    expect(find.byType(WifiTransferScreen), findsOneWidget);
  });
```

- [ ] **Step 2: 執行測試，確認失敗**

Run: `flutter test test/screens/sources_home_screen_test.dart`
Expected: FAIL——`wifiTransferDependencies` 具名參數不存在（`SourcesHomeScreen` 尚未新增此建構參數），編譯錯誤（尚未走到實際執行階段，故此時不會出現 C-1 描述的 `PlatformException`；那個問題要等 Step 3 補上建構參數、程式能編譯之後才會在「未設定 wakelock 替身」的情況下顯現——本計畫已在 Step 1 一併把替身設定寫進測試檔，所以正式走完 TDD 循環時不會遇到）。

- [ ] **Step 3: 修改 `sources_home_screen.dart`**

Edit `app/lib/screens/sources_home_screen.dart`，新增 import：

```dart
// 舊：
import '../remote/remote_catalog_dependencies.dart';
import 'cloud_browser_screen.dart';
import 'library_screen_dependencies.dart';
import 'remote_server_list_screen.dart';
import 'support/book_import_picker_helper.dart';
import 'widgets/download_queue_panel.dart';
import 'widgets/eb_field_card.dart';
import 'widgets/eb_section_header.dart';
```

```dart
// 新：
import '../remote/remote_catalog_dependencies.dart';
import '../wifi_transfer/wifi_transfer_dependencies.dart';
import 'cloud_browser_screen.dart';
import 'library_screen_dependencies.dart';
import 'remote_server_list_screen.dart';
import 'support/book_import_picker_helper.dart';
import 'widgets/download_queue_panel.dart';
import 'widgets/eb_field_card.dart';
import 'widgets/eb_section_header.dart';
import 'wifi_transfer_screen.dart';
```

新增欄位與建構參數：

```dart
// 舊：
  final DownloadQueueController? downloadQueueController;

  const SourcesHomeScreen({
    super.key,
    required this.repository,
    required this.importService,
    this.cloudAccountDependencies = const LibraryCloudAccountDependencies(),
    this.remoteLibraryDependencies = const LibraryRemoteLibraryDependencies(),
    this.computeFingerprint,
    this.isMobileDataConnection,
    this.isEinkMode = false,
    this.onNavigateToLibrary,
    this.onNavigateToSettings,
    this.downloadQueueController,
  });
```

```dart
// 新：
  final DownloadQueueController? downloadQueueController;

  /// WiFi 傳書入口依賴（epic-44-wifi-book-transfer Issue 1，spec.md
  /// 「依賴注入收斂」）：任一必要欄位為 `null` 時「本機」分區不顯示此
  /// 入口。
  final WifiTransferDependencies? wifiTransferDependencies;

  const SourcesHomeScreen({
    super.key,
    required this.repository,
    required this.importService,
    this.cloudAccountDependencies = const LibraryCloudAccountDependencies(),
    this.remoteLibraryDependencies = const LibraryRemoteLibraryDependencies(),
    this.computeFingerprint,
    this.isMobileDataConnection,
    this.isEinkMode = false,
    this.onNavigateToLibrary,
    this.onNavigateToSettings,
    this.downloadQueueController,
    this.wifiTransferDependencies,
  });
```

新增導覽方法（緊接在既有 `_openRemoteLibrary` 之後）：

```dart
// 舊：
  void _openRemoteLibrary(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => RemoteServerListScreen(
          repository: remoteLibraryDependencies.remoteServerRepository!,
          libraryRepository: repository,
          dependencies: RemoteCatalogDependencies(
            computeFingerprint: computeFingerprint!,
            thumbnailCache: remoteLibraryDependencies.thumbnailCache!,
            createOpdsClient: remoteLibraryDependencies.createOpdsClient!,
          ),
          importService: importService,
          isEinkMode: isEinkMode,
          downloadQueueController: downloadQueueController!,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
```

```dart
// 新：
  void _openRemoteLibrary(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => RemoteServerListScreen(
          repository: remoteLibraryDependencies.remoteServerRepository!,
          libraryRepository: repository,
          dependencies: RemoteCatalogDependencies(
            computeFingerprint: computeFingerprint!,
            thumbnailCache: remoteLibraryDependencies.thumbnailCache!,
            createOpdsClient: remoteLibraryDependencies.createOpdsClient!,
          ),
          importService: importService,
          isEinkMode: isEinkMode,
          downloadQueueController: downloadQueueController!,
        ),
      ),
    );
  }

  void _openWifiTransfer(BuildContext context) {
    final deps = wifiTransferDependencies!;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => WifiTransferScreen(
          libraryRepository: deps.libraryRepository!,
          importService: deps.importService!,
          computeFingerprint: deps.computeFingerprint!,
          checkNetworkAvailability: deps.checkNetworkAvailability!,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
```

在 `build()` 內新增可用性判斷，並在「選擇資料夾」卡片之後、「已連結服務」分區標題之前插入第三張卡片：

```dart
// 舊：
    final remoteEnabled =
        remoteLibraryDependencies.remoteServerRepository != null &&
        remoteLibraryDependencies.createOpdsClient != null &&
        remoteLibraryDependencies.thumbnailCache != null &&
        computeFingerprint != null &&
        downloadQueueController != null;
    return Scaffold(
```

```dart
// 新：
    final remoteEnabled =
        remoteLibraryDependencies.remoteServerRepository != null &&
        remoteLibraryDependencies.createOpdsClient != null &&
        remoteLibraryDependencies.thumbnailCache != null &&
        computeFingerprint != null &&
        downloadQueueController != null;
    final wifiTransferEnabled =
        wifiTransferDependencies?.libraryRepository != null &&
        wifiTransferDependencies?.importService != null &&
        wifiTransferDependencies?.computeFingerprint != null &&
        wifiTransferDependencies?.checkNetworkAvailability != null;
    return Scaffold(
```

```dart
// 舊：
          EBFieldCard(
            padding: EdgeInsets.zero,
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: ListTile(
              key: const Key('sources_pick_folder_button'),
              leading: const Icon(Icons.folder),
              title: const Text('選擇資料夾'),
              onTap: () => _handlePickFolder(context),
            ),
          ),
          const EBSectionHeader(title: '已連結服務'),
```

```dart
// 新：
          EBFieldCard(
            padding: EdgeInsets.zero,
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: ListTile(
              key: const Key('sources_pick_folder_button'),
              leading: const Icon(Icons.folder),
              title: const Text('選擇資料夾'),
              onTap: () => _handlePickFolder(context),
            ),
          ),
          if (wifiTransferEnabled)
            EBFieldCard(
              padding: EdgeInsets.zero,
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: ListTile(
                key: const Key('sources_wifi_transfer_tile'),
                leading: const Icon(Icons.wifi),
                title: const Text('WiFi 傳書'),
                onTap: () => _openWifiTransfer(context),
              ),
            ),
          const EBSectionHeader(title: '已連結服務'),
```

- [ ] **Step 4: 執行測試，確認通過**

Run: `flutter test test/screens/sources_home_screen_test.dart`
Expected: PASS，全數測試通過（含既有測試維持綠燈）。

- [ ] **Step 5: `flutter analyze` 確認乾淨**

Run: `flutter analyze lib/screens/sources_home_screen.dart test/screens/sources_home_screen_test.dart`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add app/lib/screens/sources_home_screen.dart app/test/screens/sources_home_screen_test.dart
git commit -m "$(cat <<'EOF'
feat(wifi-transfer): SourcesHomeScreen「本機」分區新增 WiFi 傳書入口

epic-44-wifi-book-transfer Issue 1：新增 wifiTransferDependencies 建構
參數，四個必要欄位皆齊全時才顯示入口卡片（Key sources_wifi_transfer_tile），
點擊導覽至 WifiTransferScreen。測試套用 Task 6 的共用
FakeWakelockPlusPlatform 替身，避免導覽測試因未攔截的 WakelockPlus
平台呼叫而崩潰（/receiving-code-review 審查修正 C-1）。

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 8: `AdaptiveShellScaffold` 裝配串接

**Files:**
- Modify: `app/lib/screens/adaptive_shell_scaffold.dart`
- Test: `app/test/screens/adaptive_shell_scaffold_test.dart`

**Interfaces:**
- Consumes：`WifiTransferDependencies`（Task 5）、`SourcesHomeScreen.wifiTransferDependencies`（Task 7）。
- Produces：`AdaptiveShellScaffold` 新增建構參數 `final WifiTransferDependencies? wifiTransferDependencies`（預設 `null`），建構 `SourcesHomeScreen` 時原樣往下傳。供 Task 9（`main.dart`）組裝生產環境實例。

- [ ] **Step 1: 寫失敗測試**

Edit `app/test/screens/adaptive_shell_scaffold_test.dart`，於檔案頂部新增 import：

```dart
// 於既有 import 區塊新增：
import 'package:elinkbook/screens/sources_home_screen.dart';
import 'package:elinkbook/wifi_transfer/network_availability.dart';
import 'package:elinkbook/wifi_transfer/wifi_transfer_dependencies.dart';

import '../support/fake_fingerprint_computer.dart';
```

於檔案結尾新增測試：

```dart
  testWidgets('wifiTransferDependencies 正確原樣傳遞給 SourcesHomeScreen', (tester) async {
    final fingerprintComputer = FakeFingerprintComputer();
    final wifiDeps = WifiTransferDependencies(
      libraryRepository: FakeLibraryRepository(),
      importService: FakeBookImportService(),
      computeFingerprint: fingerprintComputer.call,
      checkNetworkAvailability: () async =>
          const NetworkAvailability(kind: NetworkAvailabilityKind.unavailable),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: AdaptiveShellScaffold(
          repository: FakeLibraryRepository(),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
          wifiTransferDependencies: wifiDeps,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('library_source_button')));
    await tester.pumpAndSettle();

    final sourcesHomeScreen =
        tester.widget<SourcesHomeScreen>(find.byType(SourcesHomeScreen));
    expect(sourcesHomeScreen.wifiTransferDependencies, wifiDeps);
  });
```

（若 `../support/fake_fingerprint_computer.dart` 已被檔案內其他既有 import 涵蓋則不重複新增；`FakeLibraryRepository`／`FakeBookImportService` 已是既有 import，不需重複。）

- [ ] **Step 2: 執行測試，確認失敗**

Run: `flutter test test/screens/adaptive_shell_scaffold_test.dart`
Expected: FAIL——`wifiTransferDependencies` 具名參數不存在，編譯錯誤。

- [ ] **Step 3: 修改 `adaptive_shell_scaffold.dart`**

Edit `app/lib/screens/adaptive_shell_scaffold.dart`，新增 import：

```dart
// 舊：
import '../downloads/download_queue_controller.dart';
import '../library/book_content_fingerprint.dart';
import '../library/book_import_service.dart';
import '../library/library_repository.dart';
import '../reader/reader_prefs_manager.dart';
import 'library_screen.dart';
import 'library_screen_dependencies.dart';
import 'settings_scaffold.dart';
import 'sources_home_screen.dart';
```

```dart
// 新：
import '../downloads/download_queue_controller.dart';
import '../library/book_content_fingerprint.dart';
import '../library/book_import_service.dart';
import '../library/library_repository.dart';
import '../reader/reader_prefs_manager.dart';
import '../wifi_transfer/wifi_transfer_dependencies.dart';
import 'library_screen.dart';
import 'library_screen_dependencies.dart';
import 'settings_scaffold.dart';
import 'sources_home_screen.dart';
```

新增欄位與建構參數：

```dart
// 舊：
  final LibraryThemeDependencies themeDependencies;

  const AdaptiveShellScaffold({
    super.key,
    required this.repository,
    required this.importService,
    required this.prefsManager,
    this.readerFeatureRepositories = const LibraryReaderFeatureRepositories(),
    this.syncDependencies = const LibrarySyncDependencies(),
    this.cloudAccountDependencies = const LibraryCloudAccountDependencies(),
    this.remoteLibraryDependencies = const LibraryRemoteLibraryDependencies(),
    this.computeFingerprint,
    this.isMobileDataConnection,
    this.downloadQueueController,
    this.themeDependencies = const LibraryThemeDependencies(),
  });
```

```dart
// 新：
  final LibraryThemeDependencies themeDependencies;

  /// WiFi 傳書入口依賴（epic-44-wifi-book-transfer Issue 1），原樣往下
  /// 傳給 `SourcesHomeScreen`。
  final WifiTransferDependencies? wifiTransferDependencies;

  const AdaptiveShellScaffold({
    super.key,
    required this.repository,
    required this.importService,
    required this.prefsManager,
    this.readerFeatureRepositories = const LibraryReaderFeatureRepositories(),
    this.syncDependencies = const LibrarySyncDependencies(),
    this.cloudAccountDependencies = const LibraryCloudAccountDependencies(),
    this.remoteLibraryDependencies = const LibraryRemoteLibraryDependencies(),
    this.computeFingerprint,
    this.isMobileDataConnection,
    this.downloadQueueController,
    this.themeDependencies = const LibraryThemeDependencies(),
    this.wifiTransferDependencies,
  });
```

在 `build()` 內 `SourcesHomeScreen(...)` 呼叫新增欄位：

```dart
// 舊：
            SourcesHomeScreen(
              repository: widget.repository,
              importService: widget.importService,
              cloudAccountDependencies: widget.cloudAccountDependencies,
              remoteLibraryDependencies: widget.remoteLibraryDependencies,
              computeFingerprint: widget.computeFingerprint,
              isMobileDataConnection: widget.isMobileDataConnection,
              downloadQueueController: widget.downloadQueueController,
              isEinkMode: widget.themeDependencies.isEinkMode,
              onNavigateToLibrary: () => _navigateTo(0),
              onNavigateToSettings: () => _navigateTo(2),
            ),
```

```dart
// 新：
            SourcesHomeScreen(
              repository: widget.repository,
              importService: widget.importService,
              cloudAccountDependencies: widget.cloudAccountDependencies,
              remoteLibraryDependencies: widget.remoteLibraryDependencies,
              computeFingerprint: widget.computeFingerprint,
              isMobileDataConnection: widget.isMobileDataConnection,
              downloadQueueController: widget.downloadQueueController,
              isEinkMode: widget.themeDependencies.isEinkMode,
              onNavigateToLibrary: () => _navigateTo(0),
              onNavigateToSettings: () => _navigateTo(2),
              wifiTransferDependencies: widget.wifiTransferDependencies,
            ),
```

- [ ] **Step 4: 執行測試，確認通過**

Run: `flutter test test/screens/adaptive_shell_scaffold_test.dart`
Expected: PASS，全數測試通過（含既有測試維持綠燈）。

- [ ] **Step 5: `flutter analyze` 確認乾淨**

Run: `flutter analyze lib/screens/adaptive_shell_scaffold.dart test/screens/adaptive_shell_scaffold_test.dart`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add app/lib/screens/adaptive_shell_scaffold.dart app/test/screens/adaptive_shell_scaffold_test.dart
git commit -m "$(cat <<'EOF'
feat(wifi-transfer): AdaptiveShellScaffold 新增 wifiTransferDependencies 轉送

epic-44-wifi-book-transfer Issue 1：新增建構參數並原樣往下傳給
SourcesHomeScreen，比照既有 cloudAccountDependencies/
remoteLibraryDependencies 轉送慣例。

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 9: `main.dart` 生產環境裝配

**Files:**
- Modify: `app/lib/main.dart`

**Interfaces:**
- Consumes：`checkNetworkAvailability`（Task 1 真實實作）、`WifiTransferDependencies`（Task 5）、`AdaptiveShellScaffold.wifiTransferDependencies`（Task 8）。
- Produces：`ElinkBookApp` 新增 `checkNetworkAvailability` 欄位；`main()` 組裝並傳入真實實作；`ElinkBookApp.build()` 組裝 `WifiTransferDependencies` 傳給 `AdaptiveShellScaffold`。此為裝配任務，無新測試（既有 `flutter test` 全數維持綠燈即為驗證）。

- [ ] **Step 1: 新增 import**

Edit `app/lib/main.dart`：

```dart
// 舊：
import 'remote/opds_client.dart';
import 'remote/opds_http_client.dart';
import 'remote/remote_server_repository.dart';
```

```dart
// 新：
import 'remote/opds_client.dart';
import 'remote/opds_http_client.dart';
import 'remote/remote_server_repository.dart';
import 'wifi_transfer/network_availability.dart';
import 'wifi_transfer/wifi_transfer_dependencies.dart';
```

- [ ] **Step 2: `ElinkBookApp` 新增欄位與建構參數**

```dart
// 舊：
  final FullTextSearchSettingsRepository? fullTextSearchSettingsRepository;
  final bool isFullTextSearchAvailable;
  final SearchRepository? searchRepository;

  ElinkBookApp({
    super.key,
```

```dart
// 新：
  final FullTextSearchSettingsRepository? fullTextSearchSettingsRepository;
  final bool isFullTextSearchAvailable;
  final SearchRepository? searchRepository;

  /// WiFi 傳書入口的網路先決條件偵測（epic-44-wifi-book-transfer
  /// Issue 1），生產環境傳入 `checkNetworkAvailability`（`network_availability.dart`
  /// 頂層函式）。
  final CheckNetworkAvailability? checkNetworkAvailability;

  ElinkBookApp({
    super.key,
```

```dart
// 舊（建構子具名參數清單結尾，緊接在 searchRepository 之後）：
    this.fullTextSearchSettingsRepository,
    this.isFullTextSearchAvailable = true,
    this.searchRepository,
  });
```

```dart
// 新：
    this.fullTextSearchSettingsRepository,
    this.isFullTextSearchAvailable = true,
    this.searchRepository,
    this.checkNetworkAvailability,
  });
```

- [ ] **Step 3: `build()` 內組裝 `WifiTransferDependencies` 傳給 `AdaptiveShellScaffold`**

```dart
// 舊：
        themeDependencies: LibraryThemeDependencies(
          currentTheme: _theme,
          isEinkMode: _isEinkMode,
          onThemeChanged: _handleThemeChanged,
          onEinkModeChanged: _handleEinkModeChanged,
        ),
      ),
    );
  }
}
```

```dart
// 新：
        themeDependencies: LibraryThemeDependencies(
          currentTheme: _theme,
          isEinkMode: _isEinkMode,
          onThemeChanged: _handleThemeChanged,
          onEinkModeChanged: _handleEinkModeChanged,
        ),
        wifiTransferDependencies: WifiTransferDependencies(
          libraryRepository: widget.repository,
          importService: widget.importService,
          computeFingerprint: widget.computeFingerprint,
          checkNetworkAvailability: widget.checkNetworkAvailability,
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: `main()` 傳入真實實作**

```dart
// 舊：
      computeFingerprint: computeBookContentFingerprint,
      thumbnailCache: thumbnailCache,
      isMobileDataConnection: _isMobileDataConnection,
```

```dart
// 新：
      computeFingerprint: computeBookContentFingerprint,
      thumbnailCache: thumbnailCache,
      isMobileDataConnection: _isMobileDataConnection,
      checkNetworkAvailability: checkNetworkAvailability,
```

- [ ] **Step 5: `flutter analyze` 確認乾淨**

Run: `flutter analyze lib/main.dart`
Expected: `No issues found!`

- [ ] **Step 6: 跑既有相關測試套件確認零回歸**

Run: `flutter test test/screens/adaptive_shell_scaffold_test.dart test/screens/sources_home_screen_test.dart`
Expected: PASS，全數通過（`main.dart` 本身無既有專屬測試檔，這是本次異動實際觸及、需要重新確認的範圍）。

- [ ] **Step 7: Commit**

```bash
git add app/lib/main.dart
git commit -m "$(cat <<'EOF'
feat(wifi-transfer): main.dart 組裝生產環境 WifiTransferDependencies

epic-44-wifi-book-transfer Issue 1：ElinkBookApp 新增
checkNetworkAvailability 欄位，build() 組裝 WifiTransferDependencies
（libraryRepository/importService/computeFingerprint 用既有實例，
checkNetworkAvailability 接上 network_availability.dart 真實實作）傳給
AdaptiveShellScaffold，main() 傳入真實 checkNetworkAvailability。至此
「來源」畫面的 WiFi 傳書入口在正式環境可正常顯示。

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 10: `integration_test/wifi_transfer_screen_test.dart`——真機驗證

**Files:**
- Create: `app/integration_test/wifi_transfer_screen_test.dart`

**Interfaces:**
- Consumes：`WifiTransferScreen`（Task 6）、`checkNetworkAvailability`（Task 1）。
- 本 Task **無法在此次協作/規劃階段的一般開發環境中執行**——比照 CLAUDE.md「兩層測試架構」，`integration_test/` 必須在真實 Android 裝置/模擬器上以 `flutter test integration_test/wifi_transfer_screen_test.dart -d <device-id>` 執行，且裝置須已連上 WiFi 或已開啟手機熱點（否則測試會依下方 Step 3 的防呆邏輯明確失敗並提示原因，而非誤判為程式錯誤）。

- [ ] **Step 1: 寫測試檔**

Create `app/integration_test/wifi_transfer_screen_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:elinkbook/screens/wifi_transfer_screen.dart';
import 'package:elinkbook/wifi_transfer/network_availability.dart';

import '../test/support/fake_book_import_service.dart';
import '../test/support/fake_library_repository.dart';
import '../test/support/fake_fingerprint_computer.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      '真機：伺服器成功綁定 socket，GET / 可取得首頁 HTML（Issue 1 骨架驗證，'
      '裝置須已連上 WiFi 或已開啟手機熱點）', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: WifiTransferScreen(
          libraryRepository: FakeLibraryRepository(),
          importService: FakeBookImportService(),
          computeFingerprint: FakeFingerprintComputer().call,
          checkNetworkAvailability: checkNetworkAvailability,
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 5));

    if (tester.any(find.text('請連線至 WiFi 或開啟手機熱點'))) {
      fail('真機測試裝置目前沒有連上 WiFi／開啟熱點，無法驗證伺服器啟動；'
          '請先連線至 WiFi 或開啟手機熱點後重跑本測試。');
    }

    final ipTextWidget =
        tester.widget<Text>(find.byKey(const Key('wifi_transfer_ip_text')));
    final url = ipTextWidget.data!;

    final response = await http.get(Uri.parse(url));
    expect(response.statusCode, 200);
    expect(response.body, contains('elinkBook WiFi 傳書'));
  });
}
```

- [ ] **Step 2: `flutter analyze` 確認乾淨（純靜態檢查，不需裝置）**

Run: `flutter analyze integration_test/wifi_transfer_screen_test.dart`
Expected: `No issues found!`

- [ ] **Step 3: 人類於真機/模擬器執行本測試**

Run（需要真實裝置且已連上 WiFi 或已開熱點，`<device-id>` 用 `flutter devices` 查詢）：

```bash
flutter test integration_test/wifi_transfer_screen_test.dart -d <device-id>
```

Expected: PASS。若失敗且訊息為「裝置目前沒有連上 WiFi／開啟熱點」，代表測試環境未滿足前提，不是程式缺陷；請先滿足前提再重跑。**此步驟無法在本次規劃/協作階段自動完成，需人類於實際裝置上執行後回報結果。**

- [ ] **Step 4: Commit**

```bash
git add app/integration_test/wifi_transfer_screen_test.dart
git commit -m "$(cat <<'EOF'
test(wifi-transfer): 新增 WifiTransferScreen 真機整合測試

epic-44-wifi-book-transfer Issue 1：驗證伺服器真的能綁定 socket、
GET / 真的能取得首頁 HTML。需在已連上 WiFi／已開熱點的真實裝置上以
flutter test integration_test/wifi_transfer_screen_test.dart -d
<device-id> 執行，無法在一般開發環境自動驗證。

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 11: 最終驗證

**Files:** 無新增/修改檔案，純驗證步驟。

- [ ] **Step 1: 執行完整 `flutter analyze`**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 2: 執行完整 `flutter test`（本計畫唯一一次全套執行，比照 CLAUDE.md「測試執行範圍」慣例）**

Run: `flutter test`
Expected: 全數通過，零回歸（含 Task 1-9 新增/修改的測試，以及專案其餘既有測試案例）。

- [ ] **Step 3: 提醒人類完成 Task 10 的真機驗證（若尚未執行）**

若 Task 10 Step 3 尚未在真實裝置上執行過，於此提醒：本 Issue 的驗收標準要求「使用者可從『來源』畫面點開 WiFi 傳書，看到 IP/QR Code；同一 WiFi 下的瀏覽器連得上首頁」，這需要 `integration_test/wifi_transfer_screen_test.dart` 在真機上跑過一次才能確認（比照 Issue 0 Task 5 的既定模式，此步驟無程式碼異動、無需 commit，僅作為交付給人類的驗收清單）。

---

## `review-plan-issue-1.md` 審查後續（`/receiving-code-review`）

審查判定 Changes Requested（1 Critical／4 Important／4 Minor），逐項查證後：

- **C-1（Task 7 測試遺漏 `wakelockPlusPlatformInstance` 替身導致崩潰）**：查證屬實——已直接讀取 `wakelock_plus_platform_interface-1.6.0` 的 `messages.g.dart:17-21`，確認找不到 mock handler 時確實會拋出 `PlatformException(channel-error, ...)`。採納，已將 Task 6 原本內嵌於測試檔的 `_FakeWakelockPlusPlatform` 抽成共用支援檔 `app/test/support/fake_wakelock_plus_platform.dart`（改名 `FakeWakelockPlusPlatform`），Task 6／Task 7 兩份測試檔皆改為 import 使用，Task 7 補上對應的 `setUp`/`tearDown`。
- **I-1（`checkNetworkAvailability()` 未優先挑選 `wlan`-類介面）**：查證屬實，`spec.md` 原文明確要求「找 `wlan0`-類介面的 IP」，原實作僅沿用 `classifyNetworkInterfaces()` 對原始清單線性挑出的第一個私有 IP，多網卡裝置（USB 網路共享等）確實可能選錯網段。採納，Task 1 Step 3 新增 `_findWlanIp()` 優先搜尋，找不到才 fallback 至原本的分類結果。
- **I-2（候選清單/QR 顯示缺少滾動容器）**：查證屬實，`Column(mainAxisSize: MainAxisSize.min)` 在候選介面數量多或橫向模式下確有 overflow 風險。採納，Task 6 Step 5 兩個分支皆包一層 `SingleChildScrollView`。
- **I-3（`FutureBuilder` 對 `snapshot.data!` 未防禦，例外時崩潰）**：查證屬實。採納，Task 6 Step 5 的 `_initialize()` 加 try-catch 降級為 `unavailable`，`_buildBody()` 額外補上 `!snapshot.hasData` 防禦分支；Task 6 Step 3 新增對應測試。
- **I-4（`_selectManualIp()` 無防重入，可能並行啟動導致孤兒 socket）**：查證屬實，`_wifiServer != null` 這個既有守衛只在非同步啟動「完成」後才生效，啟動期間的空窗確實可能被連續點擊觸發兩次並行 `start()`。**部分採納**——已加上 `_startingServer` 防重入旗標解決真正的正確性缺陷（socket 洩漏）；審查建議的第二部分（啟動期間顯示載入指示器、待綁定完成才切換畫面）**不採納**，理由記錄在 Task 6 實作步驟之後：這只是既有「樂觀顯示預設埠」設計的已知可接受殘留現象（8080 衝突機率低），為此重寫畫面狀態機並牽動既有 widget test 斷言時機的成本與 Issue 1 骨架範圍不成比例（YAGNI），留待真機測試如有實際困擾再另立工單。
- **M-1（缺少「點擊候選項後切換顯示」的測試）／M-2（`QrImageView` 未指定 `backgroundColor` 導致深色主題黑底黑碼）**：查證皆屬實，已分別補進 Task 6 Step 3／Step 5。
- **M-3（首頁路由可同時支援 `GET /index.html`）／M-4（`stop()` 應排解 `_waitQueue` 殘餘 Completer）**：查證皆屬實、成本低，已分別補進 Task 4 Step 1（測試）與 Step 3（實作），含 `cache-control: no-cache` 一併處理（避免 App 版本更新後瀏覽器快取舊版頁面）。

## Self-Review 記錄

- **Spec coverage**：Issue 1「What to build」六項（`network_availability.dart`、`WifiTransferService` 骨架、`WifiTransferHttpServer`、`assets/wifi_transfer/index.html`、`WifiTransferDependencies`、`WifiTransferScreen`）與「裝配串接」兩項（`AdaptiveShellScaffold`／`main.dart`）、`SourcesHomeScreen` 入口卡片，已逐一對應 Task 1-9；「單元測試要求」五項（`classifyNetworkInterfaces()`、`WifiTransferScreen` widget test、`SourcesHomeScreen` widget test、`AdaptiveShellScaffold` widget test、`integration_test/`）已對應 Task 1、6、7、8、10；「驗收標準」四項已對應 Task 11 的驗證清單。
- **Placeholder scan**：所有 Step 皆含可直接套用的實際程式碼區塊，無 TBD／「依上述類推」等佔位敘述；`WifiTransferService` 三個方法體的 `throw UnimplementedError()` 是 spec.md 明確定案的 Issue 1 範圍（非本計畫偷懶留白），Task 2 已附完整測試鎖定這個「尚未實作」契約本身。
- **Type consistency**：`CheckNetworkAvailability`（Task 1）→ `WifiTransferDependencies.checkNetworkAvailability`（Task 5）→ `SourcesHomeScreen._openWifiTransfer()` 解包（Task 7）→ `WifiTransferScreen.checkNetworkAvailability`（Task 6）→ `ElinkBookApp.checkNetworkAvailability`（Task 9）簽章一致；`WifiTransferService`（Task 2）建構參數與 `WifiTransferScreen._startServerIfNeeded()`（Task 6）呼叫端逐一比對相符；`activeTransfersNotifier`（Task 4 `WifiTransferHttpServer`）與 `activeTransfersNotifierOverride`（Task 6 `WifiTransferScreen`）型別皆為 `ValueListenable<int>`。
- **與既有慣例的一致性**：`WifiTransferDependencies` 全 nullable bundle 比照 `LibraryCloudAccountDependencies`；`activeTransfersNotifierOverride` 建構子注入比照 `TapZoneDetector` 的 `nowMs` 注入慣例；`WifiTransferHttpServer` 測試以真實 loopback HTTP 往返驗證（比照專案「真正的行為測試優於空洞 mock」原則），且明確不在 `flutter test` 中觸碰真實 `WakelockPlus`/裝置 socket（`WifiTransferScreen` 測試一律透過 `activeTransfersNotifierOverride` 繞過真實伺服器啟動，`wakelockPlusPlatformInstance` 測試替身繞過真實平台呼叫）。
