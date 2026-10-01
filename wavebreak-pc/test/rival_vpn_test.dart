import 'package:flutter_test/flutter_test.dart';
import 'package:wavebreak/services/vpn/windows_vpn_adapter.dart';

void main() {
  test('VPN-looking adapters are recognised, ours and ordinary ones are not',
      () {
    expect(
      rivalVpnAdapters([
        'Radmin VPN',
        'OpenVPN Data Channel Offload',
        'wavebreak',
        'wavebreak-admin',
        'happ-xray',
        'Беспроводная сеть',
        'vEthernet (Default Switch)',
      ]),
      {'Radmin VPN', 'OpenVPN Data Channel Offload'},
    );
  });

  test('an adapter present at connect is not a rival, a new one is', () {
    final baseline = rivalVpnAdapters(['Radmin VPN', 'Ethernet']);
    final later =
        rivalVpnAdapters(['Radmin VPN', 'Ethernet', 'ProtonVPN']);
    expect(later.difference(baseline), {'ProtonVPN'});
    expect(rivalVpnAdapters(['Radmin VPN', 'Ethernet']).difference(baseline),
        isEmpty);
  });
}
