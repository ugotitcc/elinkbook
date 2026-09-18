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
