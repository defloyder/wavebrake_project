/// Compile-time environment. Core URL is never hardcoded in UI widgets.
///
/// dart-define examples:
/// --dart-define=FLAVOR=production
/// --dart-define=CORE_BASE_URL=https://api.wavebreak.app
/// --dart-define=USE_MOCK_API=true
/// --dart-define=USE_SIMULATED_VPN=true
///
/// To point a local build at a real Core instance running via
/// `wavebreak-infrastructure`'s docker compose stack:
/// --dart-define=CORE_BASE_URL=http://127.0.0.1:18080 --dart-define=USE_MOCK_API=false
class AppEnv {
  const AppEnv._();

  static const flavor = String.fromEnvironment(
    'FLAVOR',
    defaultValue: 'development',
  );

  // Defaults point at the real pilot Core over HTTPS, not a mock/localhost
  // instance — a plain `flutter build windows` with no --dart-define flags
  // must still ship a build that can actually reach the backend. Override
  // for local development against a docker-compose Core instance with:
  // --dart-define=CORE_BASE_URL=http://127.0.0.1:18080 --dart-define=USE_MOCK_API=true
  static const coreBaseUrl = String.fromEnvironment(
    'CORE_BASE_URL',
    defaultValue: 'https://api.wavebreak.com.tr',
  );

  static const useMockApi = bool.fromEnvironment(
    'USE_MOCK_API',
    defaultValue: false,
  );

  /// Which protocol to request in `POST /v1/access/grants`. The mock
  /// backend and the original WireGuard contract both expect
  /// `"wireguard"`; the pilot Core only accepts `"vless"` (VLESS REALITY)
  /// and rejects anything else — see docs/mobile-desktop-pilot-testing.md.
  /// Defaults to "vless" to match the real Core; override only for a mock
  /// or non-pilot backend with --dart-define=ACCESS_PROTOCOL=wireguard
  static const accessProtocol = String.fromEnvironment(
    'ACCESS_PROTOCOL',
    defaultValue: 'vless',
  );

  /// Whether to fake the VPN tunnel ([SimulatedVpnAdapter]) instead of
  /// talking to the real native tunnel engine ([PlatformVpnAdapter]).
  /// Independent from [useMockApi] on purpose — e.g. useful to point the
  /// app at the real Core server while the native tunnel engine is still
  /// being wired up per platform. Defaults to following [useMockApi] so a
  /// single `--dart-define=USE_MOCK_API=false` still turns both on unless
  /// this is set explicitly.
  static bool get useSimulatedVpn => const bool.hasEnvironment('USE_SIMULATED_VPN')
      ? const bool.fromEnvironment('USE_SIMULATED_VPN')
      : useMockApi;

  static bool get isProduction => flavor == 'production';
  static bool get isStaging => flavor == 'staging';
  static bool get isDevelopment => flavor == 'development';

  /// WAVEBREAK Core's API is versioned under `/v1` (not `/api/v1` — Core
  /// is a standalone Go service, not behind the Laravel Web/Admin apps).
  static const apiPrefix = '/v1';
}
