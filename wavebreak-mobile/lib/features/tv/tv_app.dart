import 'dart:async';

import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/session_controller.dart';
import '../../core/errors/app_exception.dart';
import '../../core/i18n/app_strings.dart';
import '../../core/i18n/language_controller.dart';
import '../../services/providers.dart';
import '../../services/vpn/connection_manager.dart';
import '../shared/data_providers.dart';

/// Large controls with an explicit focus outline, including remote OK/Select.
class TvButton extends StatelessWidget {
  const TvButton(
      {super.key,
      required this.label,
      required this.onPressed,
      this.autofocus = false,
      this.selected = false});
  final String label;
  final VoidCallback? onPressed;
  final bool autofocus;
  final bool selected;

  @override
  Widget build(BuildContext context) => FilledButton(
        autofocus: autofocus,
        onPressed: onPressed,
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(0, 58)),
          padding: const WidgetStatePropertyAll(
              EdgeInsets.symmetric(horizontal: 22, vertical: 14)),
          textStyle: const WidgetStatePropertyAll(TextStyle(fontSize: 20)),
          backgroundColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.disabled)
                  ? const Color(0xff242a35)
                  : states.contains(WidgetState.focused)
                      ? const Color(0xff147d89)
                      : selected
                          ? const Color(0xff18505a)
                          : const Color(0xff202a3a)),
          foregroundColor: const WidgetStatePropertyAll(Colors.white),
          side: WidgetStateProperty.resolveWith((states) => BorderSide(
              color: states.contains(WidgetState.focused)
                  ? Colors.white
                  : Colors.transparent,
              width: 3)),
        ),
        child: Text(label, textAlign: TextAlign.center),
      );
}

class WavebreakTvApp extends ConsumerWidget {
  const WavebreakTvApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final phase = ref.watch(sessionControllerProvider).phase;
    final s = ref.watch(stringsProvider);
    return MaterialApp(
      title: 'WAVEBREAK TV',
      debugShowCheckedModeBanner: false,
      locale: Locale(ref.watch(languageProvider).name),
      supportedLocales: AppLanguage.values.map((l) => Locale(l.name)).toList(),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate
      ],
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: const Color(0xff0b1020),
        inputDecorationTheme: const InputDecorationTheme(
            border: OutlineInputBorder(), contentPadding: EdgeInsets.all(18)),
      ),
      shortcuts: <ShortcutActivator, Intent>{
        ...WidgetsApp.defaultShortcuts,
        const SingleActivator(LogicalKeyboardKey.select):
            const ActivateIntent(),
      },
      home: switch (phase) {
        SessionPhase.booting =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
        SessionPhase.authenticated => const TvDashboard(),
        SessionPhase.unauthenticated || SessionPhase.guest => const TvLogin(),
        SessionPhase.maintenance => _Gate(message: s.errUnavailable),
        SessionPhase.updateRequired => _Gate(message: s.errUpdateRequired),
      },
    );
  }
}

class _Gate extends ConsumerWidget {
  const _Gate({required this.message});
  final String message;
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
          body: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(message, style: const TextStyle(fontSize: 24)),
        const SizedBox(height: 24),
        TvButton(
            label: ref.watch(stringsProvider).refreshServers,
            autofocus: true,
            onPressed: () => ref
                .read(sessionControllerProvider.notifier)
                .bootstrapSession()),
      ])));
}

class TvLogin extends ConsumerStatefulWidget {
  const TvLogin({super.key});
  @override
  ConsumerState<TvLogin> createState() => _TvLoginState();
}

class _TvLoginState extends ConsumerState<TvLogin> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _code = TextEditingController();
  CancelToken? _cancel;
  bool _busy = false;
  bool _verify = false;
  bool _loginCode = false;
  String? _error;
  int _authGeneration = 0;

  @override
  void dispose() {
    _authGeneration++;
    _cancel?.cancel();
    _email.dispose();
    _password.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) {
      return;
    }
    _authGeneration++;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action().timeout(const Duration(seconds: 30), onTimeout: () {
        _authGeneration++;
        _cancel?.cancel('TV auth timeout');
        throw AppException(AppErrorKind.unavailable);
      });
    } on AppException catch (e) {
      if (!mounted) {
        return;
      }
      if (e.kind == AppErrorKind.emailNotVerified) {
        _verify = true;
      }
      setState(() => _error = e.localized(ref.read(stringsProvider)));
    } catch (_) {
      if (mounted) {
        setState(() => _error = ref.read(stringsProvider).errUnavailable);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _signIn() => _run(() async {
        final generation = _authGeneration;
        _cancel = CancelToken();
        final api = ref.read(coreGatewayProvider);
        final tokens = _verify
            ? (_loginCode
                ? await api.confirmLoginCode(
                    email: _email.text.trim(), code: _code.text.trim())
                : await api.verifyEmail(
                    email: _email.text.trim(), code: _code.text.trim()))
            : await api.login(
                email: _email.text.trim(),
                password: _password.text,
                cancelToken: _cancel);
        if (!mounted || generation != _authGeneration) {
          return;
        }
        await ref
            .read(sessionControllerProvider.notifier)
            .onAuthenticated(tokens);
      });

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    return Scaffold(
        body: SafeArea(
            child: Center(
                child: SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: SizedBox(
          width: 560,
          child: FocusTraversalGroup(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                const Text('WAVEBREAK TV',
                    textAlign: TextAlign.center,
                    style:
                        TextStyle(fontSize: 36, fontWeight: FontWeight.bold)),
                const SizedBox(height: 24),
                TextField(
                    controller: _email,
                    autofocus: true,
                    enabled: !_busy && !_verify,
                    style: const TextStyle(fontSize: 22),
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(labelText: s.email)),
                const SizedBox(height: 16),
                if (!_verify)
                  TextField(
                      controller: _password,
                      enabled: !_busy,
                      obscureText: true,
                      style: const TextStyle(fontSize: 22),
                      decoration: InputDecoration(labelText: s.password),
                      onSubmitted: (_) => _signIn()),
                if (_verify)
                  TextField(
                      controller: _code,
                      autofocus: true,
                      enabled: !_busy,
                      style: const TextStyle(fontSize: 22),
                      keyboardType: TextInputType.number,
                      decoration:
                          InputDecoration(labelText: s.verifyEmailCodeHint),
                      onSubmitted: (_) => _signIn()),
                const SizedBox(height: 16),
                if (_error != null)
                  Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(_error!,
                          style: const TextStyle(
                              fontSize: 20, color: Colors.orange))),
                TvButton(
                    label: _verify ? s.verifyEmailConfirm : s.signIn,
                    onPressed: _busy ? null : _signIn),
                const SizedBox(height: 12),
                TvButton(
                    label: _verify ? s.verifyEmailResend : s.emailCodeSignIn,
                    onPressed: _busy
                        ? null
                        : () => _run(() async {
                              final api = ref.read(coreGatewayProvider);
                              final generation = _authGeneration;
                              if (_verify && !_loginCode) {
                                await api.resendEmailCode(
                                    email: _email.text.trim(),
                                    language: ref.read(languageProvider).name);
                              } else {
                                await api.requestLoginCode(
                                    email: _email.text.trim(),
                                    language: ref.read(languageProvider).name);
                                if (mounted && generation == _authGeneration) {
                                  setState(() {
                                    _verify = true;
                                    _loginCode = true;
                                  });
                                }
                              }
                            })),
                if (_verify)
                  TvButton(
                      label: s.cancel,
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                                _verify = false;
                                _loginCode = false;
                                _error = null;
                                _code.clear();
                              })),
                if (_busy)
                  const Padding(
                      padding: EdgeInsets.all(12),
                      child: Center(child: CircularProgressIndicator())),
              ]))),
    ))));
  }
}

class TvDashboard extends ConsumerStatefulWidget {
  const TvDashboard({super.key});
  @override
  ConsumerState<TvDashboard> createState() => _TvDashboardState();
}

class _TvDashboardState extends ConsumerState<TvDashboard>
    with WidgetsBindingObserver {
  int _page = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final manager = ref.read(connectionManagerProvider.notifier);
      final items = ref.read(locationsProvider).valueOrNull;
      if (items != null) {
        manager.hydrateLocations(items);
      }
      unawaited(manager.reconcileWithSystem());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(
          ref.read(connectionManagerProvider.notifier).reconcileWithSystem());
    }
  }

  void _refresh() {
    ref.invalidate(subscriptionProvider);
    ref.invalidate(locationsProvider);
    ref.invalidate(userProfileProvider);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final connection = ref.watch(connectionManagerProvider);
    final locations = ref.watch(locationsProvider);
    final active = ref.watch(canConnectProvider);
    final manager = ref.read(connectionManagerProvider.notifier);
    ref.listen(locationsProvider, (_, next) {
      final items = next.valueOrNull;
      if (items != null) {
        manager.hydrateLocations(items);
      }
    });
    final status = switch (connection.status) {
      ConnectionStatus.connected => s.connected,
      ConnectionStatus.configPending => s.configPending,
      ConnectionStatus.connecting ||
      ConnectionStatus.requestingProfile =>
        s.connecting,
      ConnectionStatus.disconnecting => s.disconnecting,
      ConnectionStatus.idle || ConnectionStatus.error => s.notConnected,
    };
    return PopScope(
        canPop: _page == 0,
        onPopInvokedWithResult: (popped, _) {
          if (!popped) {
            setState(() => _page = 0);
          }
        },
        child: Scaffold(
            body: SafeArea(
                child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child: FocusTraversalGroup(
              child:
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
                width: 220,
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('WAVEBREAK',
                          style: TextStyle(
                              fontSize: 28, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 28),
                      for (final (i, label)
                          in [s.navHome, s.navLocations, s.navSettings].indexed)
                        Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: TvButton(
                                label: label,
                                selected: _page == i,
                                onPressed: () => setState(() => _page = i))),
                    ])),
            const SizedBox(width: 32),
            Expanded(
                child: SingleChildScrollView(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                  Text([s.navHome, s.navLocations, s.navSettings][_page],
                      style: const TextStyle(fontSize: 32)),
                  const SizedBox(height: 24),
                  if (_page == 0) ...[
                    Text(status, style: const TextStyle(fontSize: 28)),
                    const SizedBox(height: 12),
                    Text(
                        '${connection.location.country} ${connection.location.city}',
                        style: const TextStyle(fontSize: 22)),
                    const SizedBox(height: 24),
                    if (connection.error != null)
                      Text(connection.error!.localized(s),
                          style: const TextStyle(
                              color: Colors.orange, fontSize: 20)),
                    if (connection.noTraffic)
                      Text(s.errConnectionFailed,
                          style: const TextStyle(
                              color: Colors.orange, fontSize: 20)),
                    if (!active && !locations.isLoading)
                      Text(s.subscriptionRequiredTitle,
                          style: const TextStyle(fontSize: 22)),
                    const SizedBox(height: 16),
                    TvButton(
                        autofocus: true,
                        label: connection.isBusy ||
                                connection.status ==
                                    ConnectionStatus.configPending
                            ? s.cancel
                            : status == s.connected
                                ? s.coreDisconnect
                                : s.coreConnect,
                        onPressed: connection.status ==
                                ConnectionStatus.disconnecting
                            ? null
                            : () => manager.toggle(subscriptionActive: active)),
                    const SizedBox(height: 16),
                    TvButton(label: s.refreshServers, onPressed: _refresh),
                  ],
                  if (_page == 1) ...[
                    TvButton(label: s.refreshServers, onPressed: _refresh),
                    const SizedBox(height: 16),
                    locations.when(
                        loading: () =>
                            const Center(child: CircularProgressIndicator()),
                        error: (_, __) => Text(s.errUnavailable,
                            style: const TextStyle(fontSize: 22)),
                        data: (items) => Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (items.where((l) => !l.isAuto).isEmpty)
                                    Text(s.subscriptionRequiredTitle,
                                        style: const TextStyle(fontSize: 22)),
                                  for (final l in items.where((l) => !l.isAuto))
                                    Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 12),
                                        child: TvButton(
                                            label: '${l.country} · ${l.city}',
                                            selected:
                                                connection.location.id == l.id,
                                            onPressed: !l.available ||
                                                    connection.isBusy
                                                ? null
                                                : () => manager.selectLocation(
                                                    l,
                                                    subscriptionActive:
                                                        active))),
                                ])),
                  ],
                  if (_page == 2) ...[
                    Text(ref.watch(sessionControllerProvider).user?.email ?? '',
                        style: const TextStyle(fontSize: 22)),
                    const SizedBox(height: 16),
                    Text(
                        ref.watch(subscriptionProvider).valueOrNull?.planName ??
                            s.subscription,
                        style: const TextStyle(fontSize: 22)),
                    const SizedBox(height: 24),
                    Text(s.language, style: const TextStyle(fontSize: 24)),
                    const SizedBox(height: 12),
                    Wrap(spacing: 12, runSpacing: 12, children: [
                      for (final language in AppLanguage.values)
                        TvButton(
                            label: stringsFor(language).languageName,
                            selected: ref.watch(languageProvider) == language,
                            onPressed: () => ref
                                .read(languageProvider.notifier)
                                .setLanguage(language)),
                    ]),
                    const SizedBox(height: 24),
                    TvButton(label: s.refreshServers, onPressed: _refresh),
                    const SizedBox(height: 12),
                    TvButton(
                        label: s.logOut,
                        onPressed: () async {
                          final confirm = await showDialog<bool>(
                              context: context,
                              builder: (ctx) =>
                                  AlertDialog(title: Text(s.logOut), actions: [
                                    TvButton(
                                        label: s.cancel,
                                        autofocus: true,
                                        onPressed: () =>
                                            Navigator.pop(ctx, false)),
                                    TvButton(
                                        label: s.logOut,
                                        onPressed: () =>
                                            Navigator.pop(ctx, true)),
                                  ]));
                          if (confirm == true && mounted) {
                            await ref
                                .read(sessionControllerProvider.notifier)
                                .logout();
                          }
                        }),
                  ],
                ]))),
          ])),
        ))));
  }
}
