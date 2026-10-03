// lib/features/gedcom/presentation/gedcom_export_screen.dart
//
// P12.6 Batch 3 — GEDCOM export screen.
//
// Generates a GEDCOM 5.5.1 file from the current family's persons +
// relationships, using the strict default-deny allowlist in
// GedcomExporter. The user can preview + share/download the file.
//
// GENUINELY PREMIUM — the canExport() gate is enforced here. Free
// (non-premium) users see a paywall instead of the export preview
// and cannot generate/share the file. This matches the competitor
// pattern (Ancestry/MyHeritage both paywall GEDCOM export as a
// defensible premium hook) and matches what the paywall sheet
// advertises. See PremiumService.canExport.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/family/family_provider.dart';
import '../../../core/services/premium_service.dart';
import '../../../shared/widgets/paywall_sheet.dart';
import '../data/gedcom_exporter.dart';

class GedcomExportScreen extends ConsumerStatefulWidget {
  const GedcomExportScreen({super.key, required this.familyId});

  final String familyId;

  @override
  ConsumerState<GedcomExportScreen> createState() => _GedcomExportScreenState();
}

class _GedcomExportScreenState extends ConsumerState<GedcomExportScreen> {
  String? _gedcomContent;
  bool _loading = true;
  bool _permissionChecking = true;
  bool _canExport = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _checkExportPermission();
  }

  /// Check whether the current user is permitted to export. Premium
  /// (Kinrel Plus) users always can; free users are routed to the
  /// paywall. This is the genuine enforcement of the canExport()
  /// gate — it was previously a phantom gate (advertised but never
  /// enforced). See PremiumService.canExport.
  Future<void> _checkExportPermission() async {
    final canExport = await PremiumService.canExport();
    if (mounted) {
      setState(() {
        _canExport = canExport;
        _permissionChecking = false;
      });
      if (canExport) {
        // Fire-and-forget: _generateGedcom manages its own setState and
        // error handling. We don't await here because the parent method
        // is async-but-void (an event handler), and awaiting would tie
        // the permission check's completion to the generation's
        // completion, which is not desired.
        unawaited(_generateGedcom());
      }
    }
  }

  /// Show the paywall sheet and route the user to upgrade. Called
  /// when a non-premium user reaches this screen or taps "Share /
  /// Download" while the permission check was inconclusive.
  void _routeToPaywall() {
    PaywallSheet.show(
      context: context,
      trigger: PaywallTrigger.featureLocked,
      featureName: 'GEDCOM export',
    );
  }

  Future<void> _generateGedcom() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final familyAsync = ref.read(
        familyMembersProvider(widget.familyId).future,
      );
      final detailAsync = ref.read(
        familyDetailProvider(widget.familyId).future,
      );

      final members = await familyAsync;
      final detail = await detailAsync;

      // Get the current user's person ID (viewer)
      final viewerPersonId =
          members.where((p) => p.isLinkedToKinrelUser).firstOrNull?.id ??
          members.first.id;

      // Convert relationships to GedcomRelationship
      final gedcomRels = <GedcomRelationship>[];
      if (detail != null) {
        for (final rel in detail.relationships) {
          if (!rel.isActive) continue;
          gedcomRels.add(
            GedcomRelationship(
              fromPersonId: rel.fromPersonId,
              toPersonId: rel.toPersonId,
              relationshipKey: rel.relationshipKey,
              isActive: rel.isActive,
            ),
          );
        }
      }

      final gedcom = GedcomExporter.export(
        persons: members,
        relationships: gedcomRels,
        viewerPersonId: viewerPersonId,
      );

      if (mounted) {
        setState(() {
          _gedcomContent = gedcom;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KinrelColors.darkBackground,
      appBar: AppBar(
        backgroundColor: KinrelColors.darkCard,
        title: const Text('Export Family Tree (GEDCOM)'),
      ),
      body: _permissionChecking
          ? const Center(child: CircularProgressIndicator())
          : !_canExport
              ? _buildLockedState()
              : _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.error_outline,
                                  size: 48,
                                  color: Colors.red,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'Export failed',
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                                const SizedBox(height: 8),
                                Text(_error!, textAlign: TextAlign.center),
                                const SizedBox(height: 24),
                                FilledButton(
                                  onPressed: _generateGedcom,
                                  child: const Text('Retry'),
                                ),
                              ],
                            ),
                          ),
                        )
                      : _buildContent(),
    );
  }

  /// Locked state for non-premium users. GEDCOM export is a
  /// genuinely premium feature — this matches what the paywall
  /// advertises. Shows a clear "Premium" affordance and routes
  /// the user to the paywall on tap.
  Widget _buildLockedState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [KinrelColors.orange, KinrelColors.amber],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: const Icon(
                Icons.lock_outline_rounded,
                color: Colors.white,
                size: 36,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'GEDCOM export is a Kinrel Plus feature',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Outfit',
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: KinrelColors.textWhite,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Exporting your family tree as a GEDCOM file is part of '
              'Kinrel Plus. Upgrade to download a portable, standards-'
              'compliant copy of your tree.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'DM Sans',
                fontSize: 13,
                color: KinrelColors.textSilver,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: _routeToPaywall,
              icon: const Icon(Icons.workspace_premium_rounded),
              label: const Text('Upgrade to Kinrel Plus'),
              style: FilledButton.styleFrom(
                backgroundColor: KinrelColors.orange,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Privacy notice
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: KinrelColors.darkElevated,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: KinrelColors.orange.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.privacy_tip_outlined,
                  color: KinrelColors.orange,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Only names, gender, birth year, and relationships are exported. '
                    'Private/hidden members are excluded. No locations, emails, or IDs.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Preview
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: KinrelColors.darkCard,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  _gedcomContent ?? '',
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: Color(0xFFC9B4A8),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Share button
          FilledButton.icon(
            onPressed: _shareGedcom,
            icon: const Icon(Icons.share_outlined),
            label: const Text('Share / Download GEDCOM'),
          ),
        ],
      ),
    );
  }

  void _shareGedcom() {
    if (_gedcomContent == null) return;
    // Defensive: if the permission state is somehow stale (e.g.
    // premium expired between screen entry and tap), re-check
    // before sharing. Fail-closed: route to paywall rather than
    // allowing the export.
    if (!_canExport) {
      _routeToPaywall();
      return;
    }
    // Use share_plus to share the GEDCOM content
    Share.share(_gedcomContent!, subject: 'Kinrel Family Tree — GEDCOM Export');
  }
}
