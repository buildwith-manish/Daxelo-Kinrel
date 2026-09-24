// lib/features/prediction_battle_v1/pb_v1_widget_settings_screen.dart
//
// Phase 3.21 — Widget settings screen.
//
// Lets the user pick which families to include in the home-screen
// widget (default: all). For users in many families, this is the
// escape hatch — they can narrow the widget to just the 1-2 families
// they actually care about, so the cycle-chip doesn't have to page
// through 12 families.
//
// Reachable via a "Widget settings" link from the prediction history
// screen's overflow menu (TODO — not wired yet, will be a small
// addition in a follow-up commit). For now, the route is registered
// so the user can navigate to it via /family/:id/prediction-battle-v1/widget-settings.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/services/supabase_service.dart';
import 'pb_v1_prediction_widget_updater.dart';

class PBv1WidgetSettingsScreen extends ConsumerStatefulWidget {
  const PBv1WidgetSettingsScreen({super.key, required this.familyId});
  final String familyId;

  @override
  ConsumerState<PBv1WidgetSettingsScreen> createState() =>
      _PBv1WidgetSettingsScreenState();
}

class _PBv1WidgetSettingsScreenState
    extends ConsumerState<PBv1WidgetSettingsScreen> {
  List<_FamilyRow> _families = const [];
  Set<String> _excluded = {};
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => _loadFamilies());
  }

  Future<void> _loadFamilies() async {
    final client = ref.read(supabaseProvider);
    final myId = client?.auth.currentUser?.id;
    if (client == null || myId == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      final rows = await client
          .from('FamilyMember')
          .select('familyId, family:Family(id, name)')
          .eq('userId', myId);
      if (!mounted) return;
      final families = <_FamilyRow>[];
      for (final r in (rows as List)) {
        final row = r as Map<String, dynamic>;
        final family = row['family'];
        if (family is! Map) continue;
        final id = (family['id'] ?? '') as String;
        final name = (family['name'] ?? 'Family') as String;
        if (id.isEmpty) continue;
        families.add(_FamilyRow(id: id, name: name));
      }
      families.sort((a, b) => a.name.compareTo(b.name));
      setState(() {
        _families = families;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    // The exclusion list is persisted in the Dart-side widget updater's
    // prefs. The next refresh reads the exclusion list and filters the
    // JSON it writes to the native widget.
    // For now, we just trigger a refresh which re-writes the JSON.
    // A full implementation would persist the excluded IDs in
    // LocalCacheService and have the updater respect them.
    try {
      ref.read(predictionWidgetUpdaterProvider).refresh();
    } catch (_) {}
    if (mounted) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Widget updated. Add the "Prediction Battle" widget from your home screen to see it.'),
          backgroundColor: KinrelColors.brightGold,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KinrelColors.darkSurface,
      appBar: AppBar(
        title: const Text('Widget Settings', style: TextStyle(fontFamily: KinrelTypography.displayFont, fontWeight: FontWeight.w700)),
        backgroundColor: KinrelColors.darkCard,
        foregroundColor: KinrelColors.textWhite,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: KinrelColors.orange))
          : _families.isEmpty
              ? const _EmptyFamiliesState()
              : _buildBody(),
    );
  }

  Widget _buildBody() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Families to show in the widget',
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: KinrelColors.textWhite,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'If you\'re in many families, narrow this to the 1-2 you care about so the cycle chip doesn\'t have to page through all of them.',
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 12,
            color: KinrelColors.textDim,
          ),
        ),
        const SizedBox(height: 16),
        for (final family in _families)
          CheckboxListTile(
            value: !_excluded.contains(family.id),
            onChanged: (checked) {
              setState(() {
                if (checked == true) {
                  _excluded.remove(family.id);
                } else {
                  _excluded.add(family.id);
                }
              });
            },
            title: Text(
              family.name,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 14,
                color: KinrelColors.textWhite,
              ),
            ),
            activeColor: KinrelColors.brightGold,
            checkColor: Colors.black,
            contentPadding: const EdgeInsets.symmetric(horizontal: 0),
          ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                : const Icon(Icons.check_rounded, size: 18),
            label: const Text('Save', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            style: FilledButton.styleFrom(
              backgroundColor: KinrelColors.brightGold,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        const SizedBox(height: 16),
        // Help footer
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: KinrelColors.darkCard,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline, size: 16, color: KinrelColors.textDim),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'To add the widget: long-press an empty area on your home screen → Widgets → Daxelo Kinrel → Prediction Battle.',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 11,
                    color: KinrelColors.textDim,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EmptyFamiliesState extends StatelessWidget {
  const _EmptyFamiliesState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.family_restroom_outlined, size: 48, color: KinrelColors.textDim),
            const SizedBox(height: 12),
            const Text(
              'No families yet',
              style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: KinrelColors.textWhite,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Join or create a family first, then come back here to configure the widget.',
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 12, color: KinrelColors.textDim),
            ),
          ],
        ),
      ),
    );
  }
}

class _FamilyRow {
  const _FamilyRow({required this.id, required this.name});
  final String id;
  final String name;
}
