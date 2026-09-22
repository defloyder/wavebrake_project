import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:wavebreak/core/storage/prefs_store.dart';
import 'package:wavebreak/core/storage/secure_store.dart';
import 'package:wavebreak/services/core_api/core_gateway.dart';
import 'package:wavebreak/services/core_api/mock_backend.dart';
import 'package:wavebreak/services/providers.dart';

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

/// Forces [coreGatewayProvider] onto the mock backend regardless of
/// [AppEnv.useMockApi]'s current default — that default is a compile-time
/// `--dart-define` value meant to pick production vs. mock for a real
/// build, not something this test suite should be sensitive to. Without
/// this override, the suite silently depended on that default staying
/// `true`; when it was ever flipped for a production build the tests
/// tried real HTTP against a real host and failed on Flutter test's
/// stubbed HttpClient (always a 400) instead of exercising the mock
/// backend they're actually testing against.
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
  ];
}
