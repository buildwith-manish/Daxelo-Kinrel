// lib/presentation/screens/debug/feature_switches_screen.dart
//
// DAXELO KINREL — Feature Switches (Phase 1 — Debug Only)
//
// Debug-only screen showing every AppFeature with:
//   • resolved live value (debug override > RC > default > cascade)
//   • compiled default
//   • parent (if any) in the dependency map
//   • active debug override (if any), with a Switch to flip or clear it
//
// Tapping a Switch sets a debug override (persisted to SharedPreferences
// in debug builds; no-op in release). The override survives app restarts
// so QA can flip a feature off, restart the app, and verify the
// experience matches the lean default state.
//
// DO NOT expose in production builds — gate the route with `kDebugMode`.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/features/feature_registry.dart';

class FeatureSwitchesScreen extends ConsumerStatefulWidget {
  const FeatureSwitchesScreen({super.key});

  static const String route = '/debug/features';

  @override
  ConsumerState<FeatureSwitchesScreen> createState() =>
      _FeatureSwitchesScreenState();
}

class _FeatureSwitchesScreenState
    extends ConsumerState<FeatureSwitchesScreen> {
  String _query = '';
  bool _onlyOverridden = false;
  bool _onlyOff = false;

  @override
  Widget build(BuildContext context) {
    // Listen to RC updates so toggles reflect immediately.
    ref.watch(remoteConfigUpdateProvider);

    final allFeatures = AppFeature.values;
    final filtered = allFeatures.where((f) {
      // Search filter on the enum name (case-insensitive contains).
      if (_query.isNotEmpty &&
          !f.name.toLowerCase().contains(_query.toLowerCase())) {
        return false;
      }
      if (_onlyOverridden && !Features.hasDebugOverride(f)) return false;
      if (_onlyOff && Features.isOn(f)) return false;
      return true;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Feature Switches'),
        actions: [
          if (kDebugMode)
            IconButton(
              tooltip: 'Clear all overrides',
              icon: const Icon(Icons.clear_all),
              onPressed: () async {
                final confirmed = await _confirm(context,
                    'Clear all debug overrides?',
                    'All features will revert to RC + compiled defaults.');
                if (confirmed != true) return;
                for (final f in AppFeature.values) {
                  if (Features.hasDebugOverride(f)) {
                    await Features.clearDebugOverride(f);
                  }
                }
                setState(() {});
              },
            ),
        ],
      ),
      body: Column(
        children: [
          // ── Filter row ─────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              decoration: const InputDecoration(
                labelText: 'Filter by feature name',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Wrap(
            spacing: 8,
            children: [
              FilterChip(
                label: const Text('Only overridden'),
                selected: _onlyOverridden,
                onSelected: (v) => setState(() => _onlyOverridden = v),
              ),
              FilterChip(
                label: const Text('Only OFF'),
                selected: _onlyOff,
                onSelected: (v) => setState(() => _onlyOff = v),
              ),
            ],
          ),
          // ── Legend ─────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Resolution: debug override > Remote Config > default. '
                'Parent-OFF forces child-OFF.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
              ),
            ),
          ),
          const Divider(height: 8),
          // ── List ───────────────────────────────────────────────────
          Expanded(
            child: ListView.builder(
              itemCount: filtered.length,
              itemBuilder: (context, i) {
                final f = filtered[i];
                final live = Features.isOn(f);
                final def = Features.defaultOf(f);
                final parent = Features.parentOf(f);
                final overridden = Features.hasDebugOverride(f);
                // A feature is "effectively off" if it would be ON by
                // default but the parent cascade forced it OFF.
                final cascadedOff = def && !live && !overridden;
                return _FeatureTile(
                  feature: f,
                  live: live,
                  def: def,
                  parent: parent,
                  overridden: overridden,
                  cascadedOff: cascadedOff,
                  onToggle: (v) async {
                    await Features.setDebugOverride(f, v);
                    setState(() {});
                  },
                  onClear: () async {
                    await Features.clearDebugOverride(f);
                    setState(() {});
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<bool?> _confirm(
      BuildContext ctx, String title, String body) {
    return showDialog<bool>(
      context: ctx,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(c).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(c).pop(true),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

class _FeatureTile extends StatelessWidget {
  const _FeatureTile({
    required this.feature,
    required this.live,
    required this.def,
    required this.parent,
    required this.overridden,
    required this.cascadedOff,
    required this.onToggle,
    required this.onClear,
  });

  final AppFeature feature;
  final bool live;
  final bool def;
  final AppFeature? parent;
  final bool overridden;
  final bool cascadedOff;
  final ValueChanged<bool> onToggle;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(
        live ? Icons.check_circle : Icons.remove_circle_outline,
        color: live ? scheme.primary : scheme.error,
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              feature.name,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontFamily: 'monospace',
                  ),
            ),
          ),
          if (parent != null)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Tooltip(
                message: 'depends on ${parent!.name}',
                child: Chip(
                  label: Text('parent: ${parent!.name}',
                      style: const TextStyle(fontSize: 10)),
                  padding: EdgeInsets.zero,
                  labelPadding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
        ],
      ),
      subtitle: Text(
        [
          'default: ${def ? "ON" : "OFF"}',
          if (overridden) '• debug override ACTIVE',
          if (cascadedOff) '• forced OFF by parent cascade',
        ].join(' '),
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: overridden
                  ? scheme.tertiary
                  : (cascadedOff ? scheme.error : scheme.outline),
            ),
      ),
      trailing: kDebugMode
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (overridden)
                  IconButton(
                    tooltip: 'Clear override',
                    icon: const Icon(Icons.undo, size: 20),
                    onPressed: onClear,
                    visualDensity: VisualDensity.compact,
                  ),
                Switch(
                  value: live,
                  onChanged: onToggle,
                ),
              ],
            )
          : Text(live ? 'ON' : 'OFF',
              style: Theme.of(context).textTheme.bodySmall),
    );
  }
}
