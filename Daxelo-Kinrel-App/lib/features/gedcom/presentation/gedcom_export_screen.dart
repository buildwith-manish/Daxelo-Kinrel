// lib/features/gedcom/presentation/gedcom_export_screen.dart
//
// P12.6 Batch 3 — GEDCOM export screen.
//
// Generates a GEDCOM 5.5.1 file from the current family's persons +
// relationships, using the strict default-deny allowlist in
// GedcomExporter. The user can preview + share/download the file.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/family/family_provider.dart';
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
  String? _error;

  @override
  void initState() {
    super.initState();
    _generateGedcom();
  }

  Future<void> _generateGedcom() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final familyAsync = ref.read(familyMembersProvider(widget.familyId).future);
      final detailAsync = ref.read(familyDetailProvider(widget.familyId).future);

      final members = await familyAsync;
      final detail = await detailAsync;

      // Get the current user's person ID (viewer)
      final viewerPersonId = members
          .where((p) => p.isLinkedToKinrelUser)
          .firstOrNull?.id ?? members.first.id;

      // Convert relationships to GedcomRelationship
      final gedcomRels = <GedcomRelationship>[];
      if (detail != null) {
        for (final rel in detail.relationships) {
          if (!rel.isActive) continue;
          gedcomRels.add(GedcomRelationship(
            fromPersonId: rel.fromPersonId,
            toPersonId: rel.toPersonId,
            relationshipKey: rel.relationshipKey,
            isActive: rel.isActive,
          ));
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
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline, size: 48, color: Colors.red),
                        const SizedBox(height: 16),
                        Text('Export failed', style: Theme.of(context).textTheme.titleLarge),
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
              border: Border.all(color: KinrelColors.orange.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.privacy_tip_outlined, color: KinrelColors.orange, size: 20),
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
    // Use share_plus to share the GEDCOM content
    Share.share(_gedcomContent!, subject: 'Kinrel Family Tree — GEDCOM Export');
  }
}
