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
