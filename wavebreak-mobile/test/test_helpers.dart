import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:wavebreak/core/storage/prefs_store.dart';
import 'package:wavebreak/core/storage/secure_store.dart';
import 'package:wavebreak/features/shared/data_providers.dart';
import 'package:wavebreak/services/core_api/core_gateway.dart';
import 'package:wavebreak/services/core_api/mock_backend.dart';
import 'package:wavebreak/services/providers.dart';
import 'package:wavebreak/services/vpn/connection_manager.dart';
import 'package:wavebreak/services/vpn/vpn_adapter.dart';

const _secureStorageChannel = MethodChannel(
  'plugins.it_nomads.com/flutter_secure_storage',
);

/// Initializes PrefsStore/SecureStore against in-memory fakes so unit and
/// widget tests never touch real platform channels.
Future<void> setUpTestEnvironment() async {
  TestWidgetsFlutterBinding.ensureInitialized();

  final memory = <String, String>{};
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_secureStorageChannel, (call) async {
    switch (call.method) {
      case 'write':
        memory[call.arguments['key'] as String] =
            call.arguments['value'] as String;
        return null;
      case 'read':
        return memory[call.arguments['key'] as String];
      case 'delete':
        memory.remove(call.arguments['key'] as String);
        return null;
      case 'deleteAll':
        memory.clear();
        return null;
      case 'containsKey':
        return memory.containsKey(call.arguments['key'] as String);
      case 'readAll':
        return memory;
      default:
        return null;
    }
  });

  SharedPreferences.setMockInitialValues({});
  PrefsStore.init(await SharedPreferences.getInstance());
  SecureStore.init(const FlutterSecureStorage());
}

List<Override> mockCoreOverrides([MockCoreBackend? mock]) {
  final backend = mock ?? MockCoreBackend();
  return [
    mockBackendProvider.overrideWithValue(backend),
    coreGatewayProvider.overrideWith(
      (ref) => CoreGateway(
        live: ref.watch(coreApiProvider),
        mock: backend,
        useMock: true,
      ),
    ),
    locationsProvider.overrideWith((ref) async => backend.locations),
    vpnAdapterProvider.overrideWithValue(
      SimulatedVpnAdapter(delay: Duration.zero),
    ),
  ];
}
