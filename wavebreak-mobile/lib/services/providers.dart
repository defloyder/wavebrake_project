import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api/api_client.dart';
import '../core/storage/secure_store.dart';
import 'core_api/core_api.dart';
import 'core_api/core_gateway.dart';
import 'core_api/mock_backend.dart';

class ApiAuthBindings {
  Future<bool> Function()? refreshSession;
  Future<void> Function()? onAuthLost;
}

final apiAuthBindingsProvider = Provider<ApiAuthBindings>((ref) {
  return ApiAuthBindings();
});

final mockBackendProvider = Provider<MockCoreBackend>((ref) {
  return MockCoreBackend();
});

final apiClientProvider = Provider<ApiClient>((ref) {
  final bindings = ref.watch(apiAuthBindingsProvider);
  return ApiClient(
    readAccessToken: () => SecureStore.read(SecureStore.accessToken),
    refreshSession: () async {
      final fn = bindings.refreshSession;
      if (fn == null) return false;
      return fn();
    },
    onAuthLost: () async {
      await bindings.onAuthLost?.call();
    },
  );
});

final coreApiProvider = Provider<CoreApi>((ref) {
  return CoreApi(ref.watch(apiClientProvider));
});

final coreGatewayProvider = Provider<CoreGateway>((ref) {
  return CoreGateway(
    live: ref.watch(coreApiProvider),
    mock: ref.watch(mockBackendProvider),
  );
});
