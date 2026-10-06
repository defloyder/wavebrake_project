import 'main.dart' as app;

/// The Android TV build's entry point: the same app as on phones (one
/// codebase, same screens and features), built with
/// --dart-define=WAVEBREAK_TV=true — see AppEnv.isTv for what changes on a
/// TV. The Gradle build checks the entry point and the define match.
Future<void> main() => app.main();
