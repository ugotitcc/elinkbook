import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/wifi_transfer/network_availability.dart';

import 'fake_fingerprint_computer.dart';
import 'fake_source_dependencies.dart';

void main() {
  test('fakeSourceDependencies 預設全部有值（non-null），且每次呼叫是新實例', () async {
    final a = fakeSourceDependencies();
    final b = fakeSourceDependencies();
    expect(identical(a.downloadQueueController, b.downloadQueueController), isFalse);
    expect(identical(a.remoteServerRepository, b.remoteServerRepository), isFalse);
    expect(identical(a.cloudAccountRepository, b.cloudAccountRepository), isFalse);
    expect(await a.isMobileDataConnection(), isFalse);
    expect(
      (await a.checkNetworkAvailability()).kind,
      NetworkAvailabilityKind.unavailable,
    );
    expect(a.createOpdsClient(), isNotNull);
  });

  test('fakeSourceDependencies 具名覆寫原樣帶入（同一實例）', () {
    final fingerprint = FakeFingerprintComputer().call;
    final deps = fakeSourceDependencies(computeFingerprint: fingerprint);
    expect(deps.computeFingerprint, same(fingerprint));
  });

  test('fakeSourceDependencies 具名 cloudAccountRepository 正確原樣帶入', () {
    final account = fakeSourceDependencies().cloudAccountRepository;
    final deps = fakeSourceDependencies(cloudAccountRepository: account);
    expect(deps.cloudAccountRepository, same(account));
  });
}
