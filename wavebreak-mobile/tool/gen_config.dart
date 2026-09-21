import 'dart:io';
import 'package:wavebreak/services/vpn/share_link_config.dart';

void main() {
  const link =
      'vless://a8128415-e459-4813-9c68-52e9a7ceff70@direct.wavebreak.com.tr:9443?encryption=none&host=direct.wavebreak.com.tr&path=%2Fwvb-dt&security=tls&sni=direct.wavebreak.com.tr&type=ws#%F0%9F%87%B3%F0%9F%87%B1%20Netherlands%2C%20Amsterdam%20%28Direct-TLS%29';
  final parsed = parseShareLink(link);
  final config = parsed.getFullConfiguration();
  File('config_test.json').writeAsStringSync(config);
  print(config);
}
