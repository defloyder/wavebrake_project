import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/app_strings.dart';
import '../../core/i18n/language_controller.dart';
import '../../core/theme/wb_colors.dart';
import '../../core/theme/wb_theme.dart';
import '../../services/split_tunnel/split_tunnel.dart';
import '../../services/vpn/connection_manager.dart';
import '../shared/anchored_page.dart';
import '../shared/data_providers.dart';
import 'settings_ui.dart';

/// Split tunneling (owner, 15.10; like Happ): every app with a switch,
/// "Through VPN" or "Directly". The choice is saved at once and applies
/// when the tunnel is next started — a reconnect button appears while
/// connected. See [SplitTunnelStore] for how each platform does it.
class SplitTunnelScreen extends ConsumerStatefulWidget {
  const SplitTunnelScreen({super.key});

  @override
  ConsumerState<SplitTunnelScreen> createState() => _SplitTunnelScreenState();
}

class _SplitTunnelScreenState extends ConsumerState<SplitTunnelScreen> {
  List<SplitApp>? _apps;
  Set<String> _bypass = {};
  Set<String> _always = {};
  String _query = '';
  bool _showSystem = false;
  bool _changed = false;
  final _program = TextEditingController();

  SplitTunnelStore get _store => ref.read(splitTunnelStoreProvider);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _program.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final store = _store;
    final results = await Future.wait([
      store.load(),
      store.alwaysDirect(),
      store.apps().catchError((Object _) => <SplitApp>[]),
    ]);
    if (!mounted) return;
    setState(() {
      _bypass = results[0] as Set<String>;
      _always = results[1] as Set<String>;
      _apps = results[2] as List<SplitApp>;
    });
  }

  Future<void> _set(String id, {required bool direct}) async {
    setState(() {
      direct ? _bypass.add(id) : _bypass.remove(id);
      _changed = true;
    });
    await _store.save(_bypass);
  }

  Future<void> _addProgram() async {
    final names = normalizeProcessNames([_program.text]);
    if (names.isEmpty) return;
    _program.clear();
    final id = names.single;
    setState(() {
      final apps = _apps ?? [];
      if (!apps.any((a) => a.id == id)) {
        _apps = [...apps, SplitApp(id: id, label: id)];
      }
    });
    await _set(id, direct: true);
  }

  Future<void> _reconnect() async {
    setState(() => _changed = false);
    await ref
        .read(connectionManagerProvider.notifier)
        .restart(subscriptionActive: ref.read(canConnectProvider));
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final connected = ref.watch(connectionManagerProvider
        .select((c) => c.status == ConnectionStatus.connected));
    final apps = _apps;
    final q = _query.trim().toLowerCase();
    bool shown(SplitApp a) =>
        (q.isEmpty ||
            a.label.toLowerCase().contains(q) ||
            a.id.toLowerCase().contains(q)) &&
        (_showSystem || !a.system || _bypass.contains(a.id));
    final direct = [
      for (final a in apps ?? const <SplitApp>[])
        if ((_always.contains(a.id) || _bypass.contains(a.id)) && shown(a)) a,
    ];
    final viaVpn = [
      for (final a in apps ?? const <SplitApp>[])
        if (!_always.contains(a.id) && !_bypass.contains(a.id) && shown(a)) a,
    ];
    final hasSystem = (apps ?? const []).any((a) => a.system);

    return SettingsPage(
      title: s.splitTitle,
      hero: PageEmblem(icon: Icons.call_split_rounded, caption: s.splitRowHint),
      children: [
        SettingsGroup(
          footer: Platform.isWindows ? s.splitWindowsNote : null,
          children: [
            SettingsBlock(
              subtitle: s.splitApplyNote,
              child: TextField(
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  hintText: s.splitSearch,
                  prefixIcon: const Icon(Icons.search_rounded),
                  isDense: true,
                ),
              ),
            ),
            if (_changed && connected)
              SettingsRow(
                icon: Icons.refresh_rounded,
                title: s.splitReconnect,
                onTap: _reconnect,
              ),
            if (Platform.isWindows)
              SettingsBlock(
                child: TextField(
                  controller: _program,
                  onSubmitted: (_) => _addProgram(),
                  decoration: InputDecoration(
                    hintText: s.splitAddProgram,
                    isDense: true,
                    suffixIcon: IconButton(
                      tooltip: s.splitAddProgram,
                      icon: const Icon(Icons.add_rounded),
                      onPressed: _addProgram,
                    ),
                  ),
                ),
              ),
            if (hasSystem)
              SettingsSwitchRow(
                icon: Icons.android_rounded,
                title: s.splitShowSystem,
                value: _showSystem,
                onChanged: (v) => setState(() => _showSystem = v),
              ),
          ],
        ),
        if (apps == null)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (direct.isEmpty && viaVpn.isEmpty)
          SettingsGroup(children: [SettingsRow(title: s.splitEmpty)])
        else ...[
          if (direct.isNotEmpty)
            SettingsGroup(
              title: s.splitChosen.replaceAll('{n}', '${direct.length}'),
              children: [
                for (final a in direct)
                  _AppRow(
                    app: a,
                    direct: true,
                    locked: _always.contains(a.id),
                    s: s,
                    onChanged: (via) => _set(a.id, direct: !via),
                  ),
              ],
            ),
          if (viaVpn.isNotEmpty)
            SettingsGroup(
              title: s.splitViaVpn,
              children: [
                for (final a in viaVpn)
                  _AppRow(
                    app: a,
                    direct: false,
                    locked: false,
                    s: s,
                    onChanged: (via) => _set(a.id, direct: !via),
                  ),
              ],
            ),
        ],
      ],
    );
  }
}

/// An app: icon, name, where it goes, and the switch (on = through the
/// VPN). One the user can't change ([locked]) says why.
class _AppRow extends StatelessWidget {
  const _AppRow({
    required this.app,
    required this.direct,
    required this.locked,
    required this.s,
    required this.onChanged,
  });

  final SplitApp app;
  final bool direct;
  final bool locked;
  final AppStrings s;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final icon = app.icon;
    final v = Theme.of(context).visualDensity.vertical < 0 ? 6.0 : 10.0;
    final status = locked
        ? s.splitAlways
        : direct
            ? s.splitDirect
            : s.splitViaVpn;
    return MergeSemantics(
      child: InkWell(
        onTap: locked ? null : () => onChanged(direct),
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, v, 8, v),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox.square(
                  dimension: 32,
                  child: icon != null
                      ? Image.memory(icon,
                          cacheWidth: 96, gaplessPlayback: true)
                      : const ColoredBox(
                          color: WbColors.ice08,
                          child: Icon(Icons.apps_rounded,
                              size: 20, color: WbColors.ice60),
                        ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(app.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 15.5)),
                    const SizedBox(height: 2),
                    Text(
                      status,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.3,
                        color: direct ? context.accent : WbColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: !direct,
                activeTrackColor: context.accent,
                onChanged: locked ? null : onChanged,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
