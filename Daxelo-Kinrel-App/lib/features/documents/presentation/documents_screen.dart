// lib/features/documents/presentation/documents_screen.dart
//
// DAXELO KINREL — Document Vault Screen
//
// Secure family document storage with AES-256 encryption.
// KINREL Global Top 1 Prompt §24 — Document Vault:
//   • Header: "Document Vault" with lock/shield icon in orange
//   • Search bar (#202338 bg, orange search icon)
//   • Category filter chips: All, Birth, Marriage, Death, Property, Academic, Legal, Photos
//   • Grid view (2 columns) of document cards
//   • FAB: Upload Document (orange gradient)
//   • Upload bottom sheet: Document type selector, title input,
//     associate member picker, file picker placeholder, upload button
//   • Security section: AES-256 badge, authorized access text, audit log preview
//   • Empty state: Vault illustration with "No documents yet"
//
// Design colors:
//   Background:  #13141E (darkSurface)
//   Cards:       #191B2C (darkCard)
//   Primary:     #F5F0EE (textWhite)
//   Secondary:   #C9B4A8 (textSilver)
//   Accent:      #E8612A (orange)
//   Birth:       orange (#E8612A)
//   Marriage:    amber (#F59240)
//   Death:       silver (#C9B4A8)
//   Property:    gold (#D4AF37)
//   Academic:    blue (#3B82F6)
//   Legal:       red (#F04E2A)
//   Photos:      green (#4CAF7A)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../shared/widgets/dk_components.dart';
import '../providers/documents_provider.dart';

// ── Color shortcuts ──────────────────────────────────────────────────
const _cOrange = KinrelColors.orange;           // #E8612A
const _cAmber = KinrelColors.amber;             // #F59240
const _cGold = KinrelColors.gold;               // #D4AF37
const _cBg = KinrelColors.darkSurface;          // #13141E
const _cCard = KinrelColors.darkCard;           // #191B2C
const _cElevated = KinrelColors.darkElevated;   // #202338
const _cTextPrimary = KinrelColors.textWhite;   // #F5F0EE
const _cTextSecondary = KinrelColors.textSilver; // #C9B4A8
const _cTextDim = KinrelColors.textDim;         // #8A7A72
const _cBorder = Color(0xFF3A3A4A);

// ═══════════════════════════════════════════════════════════════════════
// Documents Screen
// ═══════════════════════════════════════════════════════════════════════

class DocumentsScreen extends ConsumerStatefulWidget {
  const DocumentsScreen({super.key});

  @override
  ConsumerState<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends ConsumerState<DocumentsScreen> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final docsState = ref.watch(documentsProvider);
    final filteredDocs = docsState.filteredDocuments;

    return DKScaffold(
      backgroundColor: _cBg,
      body: Column(
        children: [
          // ── Header ────────────────────────────────────────────────
          const _VaultHeader()
              .animate()
              .fadeIn(duration: 300.ms)
              .slideY(begin: -0.05, end: 0),

          // ── Search Bar ────────────────────────────────────────────
          _SearchBar(
            controller: _searchController,
            onChanged: (query) =>
                ref.read(documentsProvider.notifier).setSearchQuery(query),
          )
              .animate()
              .fadeIn(duration: 300.ms, delay: 50.ms),

          const SizedBox(height: 12),

          // ── Category Filter Chips ─────────────────────────────────
          _CategoryChips(
            selectedType: docsState.selectedType,
            onTypeSelected: (type) =>
                ref.read(documentsProvider.notifier).setSelectedType(type),
            onAllSelected: () =>
                ref.read(documentsProvider.notifier).setSelectedType(null),
            documentsByType: docsState.documentsByType,
            totalDocuments: docsState.documents.length,
          )
              .animate()
              .fadeIn(duration: 300.ms, delay: 100.ms),

          const SizedBox(height: 12),

          // ── Security Section ──────────────────────────────────────
          _SecuritySection(
            encryptedCount: docsState.encryptedCount,
            totalDocuments: docsState.documents.length,
            auditLog: docsState.recentAuditLog,
          )
              .animate()
              .fadeIn(duration: 300.ms, delay: 120.ms),

          const SizedBox(height: 12),

          // ── Document Grid / Empty State ───────────────────────────
          Expanded(
            child: filteredDocs.isEmpty
                ? _EmptyState()
                    .animate()
                    .fadeIn(duration: 400.ms)
                    .slideY(begin: 0.1, end: 0)
                : _DocumentGrid(documents: filteredDocs),
          ),
        ],
      ),
      // ── FAB: Upload Document (Orange gradient) ──────────────────
      floatingActionButton: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          gradient: KinrelGradients.igniteGradient,
          boxShadow: [
            BoxShadow(
              color: _cOrange.withValues(alpha: 0.35),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: FloatingActionButton.extended(
          onPressed: () => _showUploadSheet(context),
          backgroundColor: Colors.transparent,
          elevation: 0,
          icon: const Icon(Icons.cloud_upload_rounded, color: Colors.white, size: 22),
          label: Text(
            'Upload Document',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.white,
              letterSpacing: 0.3,
            ),
          ),
        ),
      ),
    );
  }

  void _showUploadSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _cCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(KinrelRadius.bottomSheet),
        ),
      ),
      builder: (ctx) => const _UploadDocumentSheet(),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Header: "Document Vault" with lock/shield icon in orange
// ═══════════════════════════════════════════════════════════════════════

class _VaultHeader extends StatelessWidget {
  const _VaultHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        KinrelSpacing.base,
        16,
        KinrelSpacing.base,
        8,
      ),
      decoration: BoxDecoration(
        color: _cBg,
        border: Border(
          bottom: BorderSide(
            color: Colors.white.withValues(alpha: 0.06),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          // Lock/Shield icon in orange
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _cOrange.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(KinrelRadius.md),
            ),
            child: const Icon(
              Icons.shield_rounded,
              color: _cOrange,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Document Vault',
                  style: TextStyle(
                    fontFamily: KinrelTypography.displayFont,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: _cTextPrimary,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Secure family document storage',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 12,
                    color: _cTextDim,
                  ),
                ),
              ],
            ),
          ),
          // Info icon
          GestureDetector(
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('All documents are encrypted with AES-256'),
                  backgroundColor: _cCard,
                ),
              );
            },
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _cElevated,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.info_outline_rounded,
                color: _cTextSecondary,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Search Bar (#202338 bg, orange search icon)
// ═══════════════════════════════════════════════════════════════════════

class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.controller,
    required this.onChanged,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: TextStyle(
          fontFamily: KinrelTypography.bodyFont,
          fontSize: 14,
          color: _cTextPrimary,
        ),
        decoration: InputDecoration(
          hintText: 'Search documents, members...',
          hintStyle: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 14,
            color: _cTextDim,
          ),
          prefixIcon: Icon(Icons.search_rounded, color: _cOrange, size: 22),
          filled: true,
          fillColor: _cElevated, // #202338
          contentPadding: const EdgeInsets.symmetric(
            horizontal: KinrelSpacing.lg,
            vertical: KinrelSpacing.md,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(KinrelRadius.xl),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(KinrelRadius.xl),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(KinrelRadius.xl),
            borderSide: BorderSide(color: _cOrange, width: 1.5),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Category Filter Chips
// ═══════════════════════════════════════════════════════════════════════

class _CategoryChips extends StatelessWidget {
  const _CategoryChips({
    required this.selectedType,
    required this.onTypeSelected,
    required this.onAllSelected,
    required this.documentsByType,
    required this.totalDocuments,
  });

  final DocumentType? selectedType;
  final ValueChanged<DocumentType> onTypeSelected;
  final VoidCallback onAllSelected;
  final Map<DocumentType, List<VaultDocument>> documentsByType;
  final int totalDocuments;

  static const _chipData = [
    (type: null, label: 'All', icon: Icons.folder_rounded),
    (type: DocumentType.birth, label: 'Birth', icon: Icons.child_care_rounded),
    (type: DocumentType.marriage, label: 'Marriage', icon: Icons.favorite_rounded),
    (type: DocumentType.death, label: 'Death', icon: Icons.church_rounded),
    (type: DocumentType.property, label: 'Property', icon: Icons.home_rounded),
    (type: DocumentType.academic, label: 'Academic', icon: Icons.school_rounded),
    (type: DocumentType.legal, label: 'Legal', icon: Icons.gavel_rounded),
    (type: DocumentType.photos, label: 'Photos', icon: Icons.photo_library_rounded),
  ];

  Color _chipColor(DocumentType? type) {
    if (type == null) return _cOrange;
    return VaultDocument(id: '', title: '', type: type, memberName: '', uploadDate: DateTime.now(), fileSize: 0).accentColor;
  }

  int _chipCount(DocumentType? type) {
    if (type == null) return totalDocuments;
    return documentsByType[type]?.length ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
        itemCount: _chipData.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final chip = _chipData[index];
          final isSelected = selectedType == chip.type;
          final color = _chipColor(chip.type);
          final count = _chipCount(chip.type);

          return GestureDetector(
            onTap: () {
              if (chip.type == null) {
                onAllSelected();
              } else {
                onTypeSelected(chip.type!);
              }
            },
            child: AnimatedContainer(
              duration: KinrelMotion.fast,
              curve: KinrelMotion.easeOut,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                gradient: isSelected
                    ? KinrelGradients.igniteGradient
                    : null,
                color: isSelected ? null : _cCard,
                borderRadius: BorderRadius.circular(KinrelRadius.full),
                border: isSelected
                    ? null
                    : Border.all(color: _cBorder, width: 1),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    chip.icon,
                    size: 14,
                    color: isSelected ? Colors.white : color,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    chip.label,
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                      color: isSelected ? Colors.white : _cTextSecondary,
                    ),
                  ),
                  if (count > 0) ...[
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? Colors.white.withValues(alpha: 0.2)
                            : _cElevated,
                        borderRadius: BorderRadius.circular(KinrelRadius.full),
                      ),
                      child: Text(
                        '$count',
                        style: TextStyle(
                          fontFamily: KinrelTypography.monoFont,
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: isSelected ? Colors.white : _cTextDim,
                          height: 1.2,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Security Section: AES-256 badge, authorized access, audit log
// ═══════════════════════════════════════════════════════════════════════

class _SecuritySection extends StatelessWidget {
  const _SecuritySection({
    required this.encryptedCount,
    required this.totalDocuments,
    required this.auditLog,
  });

  final int encryptedCount;
  final int totalDocuments;
  final List<AuditLogEntry> auditLog;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
      child: Container(
        padding: const EdgeInsets.all(KinrelSpacing.base),
        decoration: BoxDecoration(
          color: _cCard,
          borderRadius: BorderRadius.circular(KinrelRadius.lg),
          border: Border.all(
            color: _cOrange.withValues(alpha: 0.12),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Top Row: AES-256 Badge + Encrypted Count ────────────
            Row(
              children: [
                // AES-256 Badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    gradient: KinrelGradients.igniteGradient,
                    borderRadius: BorderRadius.circular(KinrelRadius.full),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.shield_rounded,
                        size: 13,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        'Encrypted with AES-256',
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                // Encrypted count
                Text(
                  '$encryptedCount/$totalDocuments encrypted',
                  style: TextStyle(
                    fontFamily: KinrelTypography.monoFont,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: _cTextDim,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),

            // ── Authorized access text ──────────────────────────────
            Row(
              children: [
                Icon(Icons.lock_outline_rounded, size: 13, color: _cOrange.withValues(alpha: 0.7)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Only authorized family members can access these documents',
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 12,
                      color: _cTextDim,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),

            // ── Audit Log Preview (last 3 events) ───────────────────
            if (auditLog.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _cElevated,
                  borderRadius: BorderRadius.circular(KinrelRadius.md),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.history_rounded, size: 13, color: _cOrange),
                        const SizedBox(width: 5),
                        Text(
                          'Recent Access',
                          style: TextStyle(
                            fontFamily: KinrelTypography.bodyFont,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: _cTextSecondary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ...auditLog.map((entry) => _AuditLogItem(entry: entry)),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Single audit log item ────────────────────────────────────────────

class _AuditLogItem extends StatelessWidget {
  const _AuditLogItem({required this.entry});

  final AuditLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final actionColor = switch (entry.action) {
      'viewed' => _cTextDim,
      'downloaded' => KinrelColors.success,
      'uploaded' => _cOrange,
      'shared' => _cAmber,
      'deleted' => KinrelColors.error,
      _ => _cTextDim,
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          // Mini avatar
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _cCard,
              border: Border.all(color: _cBorder, width: 0.5),
            ),
            alignment: Alignment.center,
            child: Text(
              entry.displayInitials,
              style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 8,
                fontWeight: FontWeight.w700,
                color: _cTextSecondary,
                height: 1,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: entry.memberName,
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: _cTextSecondary,
                    ),
                  ),
                  TextSpan(
                    text: ' ${entry.action} ',
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 11,
                      color: actionColor,
                    ),
                  ),
                  TextSpan(
                    text: entry.documentTitle.length > 25
                        ? '${entry.documentTitle.substring(0, 25)}...'
                        : entry.documentTitle,
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 11,
                      color: _cTextDim,
                    ),
                  ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            entry.formattedTime,
            style: TextStyle(
              fontFamily: KinrelTypography.monoFont,
              fontSize: 9,
              color: _cTextDim,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Document Grid (2 columns)
// ═══════════════════════════════════════════════════════════════════════

class _DocumentGrid extends StatelessWidget {
  const _DocumentGrid({required this.documents});

  final List<VaultDocument> documents;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(
        KinrelSpacing.base,
        0,
        KinrelSpacing.base,
        100,
      ),
      physics: const BouncingScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.62,
      ),
      itemCount: documents.length,
      itemBuilder: (context, index) {
        return _DocumentCard(document: documents[index])
            .animate()
            .fadeIn(duration: 350.ms, delay: Duration(milliseconds: index * 40))
            .slideY(begin: 0.06, end: 0);
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Document Card
// ═══════════════════════════════════════════════════════════════════════

class _DocumentCard extends ConsumerWidget {
  const _DocumentCard({required this.document});

  final VaultDocument document;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accentColor = document.accentColor;

    return GestureDetector(
      onTap: () => _showDocumentDetail(context),
      child: Container(
        decoration: BoxDecoration(
          color: _cCard,
          borderRadius: BorderRadius.circular(KinrelRadius.lg),
          border: Border.all(
            color: accentColor.withValues(alpha: 0.12),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: accentColor.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Thumbnail Preview Placeholder ───────────────────────
            _ThumbnailPreview(document: document, accentColor: accentColor),

            // ── Card Content ────────────────────────────────────────
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Type badge ───────────────────────────────────
                    Row(
                      children: [
                        _TypeBadge(type: document.type, accentColor: accentColor),
                        const Spacer(),
                        // Security badge (lock icon)
                        if (document.isEncrypted)
                          Icon(
                            Icons.lock_rounded,
                            size: 12,
                            color: accentColor.withValues(alpha: 0.6),
                          ),
                      ],
                    ),

                    const SizedBox(height: 6),

                    // ── Title ────────────────────────────────────────
                    Text(
                      document.title,
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _cTextPrimary,
                        height: 1.3,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),

                    const SizedBox(height: 4),

                    // ── Member name ──────────────────────────────────
                    Row(
                      children: [
                        Container(
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: accentColor.withValues(alpha: 0.15),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            document.displayInitials,
                            style: TextStyle(
                              fontFamily: KinrelTypography.displayFont,
                              fontSize: 7,
                              fontWeight: FontWeight.w700,
                              color: accentColor,
                              height: 1,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            document.memberName,
                            style: TextStyle(
                              fontFamily: KinrelTypography.bodyFont,
                              fontSize: 11,
                              color: _cTextSecondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),

                    const Spacer(),

                    // ── Bottom row: Upload date + File size ──────────
                    Row(
                      children: [
                        Icon(Icons.schedule_rounded, size: 10, color: _cTextDim),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(
                            document.formattedDate,
                            style: TextStyle(
                              fontFamily: KinrelTypography.monoFont,
                              fontSize: 9,
                              color: _cTextDim,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 2),

                    Row(
                      children: [
                        Icon(Icons.insert_drive_file_rounded, size: 10, color: _cTextDim),
                        const SizedBox(width: 3),
                        Text(
                          document.formattedFileSize,
                          style: TextStyle(
                            fontFamily: KinrelTypography.monoFont,
                            fontSize: 9,
                            color: _cTextDim,
                          ),
                        ),
                        const Spacer(),
                        // Download button
                        GestureDetector(
                          onTap: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Downloading ${document.title}...'),
                                backgroundColor: _cCard,
                              ),
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: _cElevated,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Icon(
                              Icons.download_rounded,
                              size: 12,
                              color: _cTextSecondary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        // Share button
                        GestureDetector(
                          onTap: () => _showShareDialog(context, ref),
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: _cElevated,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Icon(
                              Icons.share_rounded,
                              size: 12,
                              color: _cTextSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showDocumentDetail(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _cCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(KinrelRadius.bottomSheet),
        ),
      ),
      builder: (ctx) => _DocumentDetailSheet(document: document),
    );
  }

  void _showShareDialog(BuildContext context, WidgetRef ref) {
    final accentColor = document.accentColor;

    showModalBottomSheet(
      context: context,
      backgroundColor: _cCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(KinrelRadius.bottomSheet),
        ),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(KinrelSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: _cBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Title
            Row(
              children: [
                Icon(Icons.share_rounded, color: accentColor, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Share Document',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: _cTextPrimary,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Permission check info
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _cOrange.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(KinrelRadius.md),
                border: Border.all(
                  color: _cOrange.withValues(alpha: 0.2),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.shield_rounded, size: 16, color: _cOrange),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Sharing requires family admin permission. Only authorized members can access shared documents.',
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 12,
                        color: _cTextSecondary,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Family member list
            Text(
              'Select family members to share with:',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _cTextSecondary,
              ),
            ),
            const SizedBox(height: 10),

            // Member options
            _ShareMemberOption(name: 'Arjun Sharma', initials: 'AS', accentColor: accentColor),
            _ShareMemberOption(name: 'Priya Sharma', initials: 'PS', accentColor: accentColor),
            _ShareMemberOption(name: 'Ravi Sharma', initials: 'RS', accentColor: accentColor),
            _ShareMemberOption(name: 'Sunita Sharma', initials: 'SS', accentColor: accentColor),

            const SizedBox(height: 20),

            // Share button
            Container(
              width: double.infinity,
              height: 48,
              decoration: BoxDecoration(
                gradient: KinrelGradients.igniteGradient,
                borderRadius: BorderRadius.circular(KinrelRadius.md),
                boxShadow: [
                  BoxShadow(
                    color: _cOrange.withValues(alpha: 0.25),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    Navigator.of(ctx).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Document shared successfully'),
                        backgroundColor: _cCard,
                      ),
                    );
                  },
                  borderRadius: BorderRadius.circular(KinrelRadius.md),
                  child: Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.share_rounded, color: Colors.white, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          'Share with Permission',
                          style: TextStyle(
                            fontFamily: KinrelTypography.bodyFont,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Share member option row ──────────────────────────────────────────

class _ShareMemberOption extends StatefulWidget {
  const _ShareMemberOption({
    required this.name,
    required this.initials,
    required this.accentColor,
  });

  final String name;
  final String initials;
  final Color accentColor;

  @override
  State<_ShareMemberOption> createState() => _ShareMemberOptionState();
}

class _ShareMemberOptionState extends State<_ShareMemberOption> {
  bool _isSelected = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => setState(() => _isSelected = !_isSelected),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            // Avatar
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.accentColor.withValues(alpha: 0.12),
                border: Border.all(
                  color: _isSelected ? widget.accentColor : _cBorder,
                  width: _isSelected ? 2 : 1,
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                widget.initials,
                style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: widget.accentColor,
                  height: 1,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                widget.name,
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 14,
                  color: _cTextPrimary,
                ),
              ),
            ),
            // Check indicator
            AnimatedContainer(
              duration: KinrelMotion.fast,
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _isSelected ? widget.accentColor : Colors.transparent,
                border: Border.all(
                  color: _isSelected ? widget.accentColor : _cBorder,
                  width: 1.5,
                ),
              ),
              child: _isSelected
                  ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Thumbnail Preview Placeholder
// ═══════════════════════════════════════════════════════════════════════

class _ThumbnailPreview extends StatelessWidget {
  const _ThumbnailPreview({
    required this.document,
    required this.accentColor,
  });

  final VaultDocument document;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 80,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            accentColor.withValues(alpha: 0.08),
            accentColor.withValues(alpha: 0.03),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(KinrelRadius.lg),
        ),
      ),
      child: Stack(
        children: [
          // Centered type icon
          Center(
            child: Icon(
              document.typeIcon,
              size: 32,
              color: accentColor.withValues(alpha: 0.3),
            ),
          ),

          // File extension badge (top-right)
          if (document.fileExtension != null)
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _cCard.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(KinrelRadius.xs),
                ),
                child: Text(
                  document.fileExtension!.toUpperCase(),
                  style: TextStyle(
                    fontFamily: KinrelTypography.monoFont,
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: accentColor,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),

          // Shared indicator (top-left)
          if (document.sharedWith.isNotEmpty)
            Positioned(
              top: 8,
              left: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: _cCard.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(KinrelRadius.full),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.group_rounded, size: 9, color: _cTextDim),
                    const SizedBox(width: 2),
                    Text(
                      '${document.sharedCount}',
                      style: TextStyle(
                        fontFamily: KinrelTypography.monoFont,
                        fontSize: 8,
                        fontWeight: FontWeight.w600,
                        color: _cTextDim,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Document Type Badge
// ═══════════════════════════════════════════════════════════════════════

class _TypeBadge extends StatelessWidget {
  const _TypeBadge({
    required this.type,
    required this.accentColor,
  });

  final DocumentType type;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final doc = VaultDocument(id: '', title: '', type: type, memberName: '', uploadDate: DateTime.now(), fileSize: 0);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(KinrelRadius.full),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(doc.typeIcon, size: 10, color: accentColor),
          const SizedBox(width: 3),
          Text(
            doc.typeLabel,
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: accentColor,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Empty State
// ═══════════════════════════════════════════════════════════════════════

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.xxl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Vault illustration
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: _cOrange.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Vault/shield base
                  Icon(
                    Icons.shield_rounded,
                    size: 64,
                    color: _cOrange.withValues(alpha: 0.3),
                  ),
                  // Lock icon in center
                  Positioned(
                    bottom: 32,
                    child: Icon(
                      Icons.lock_outline_rounded,
                      size: 24,
                      color: _cOrange.withValues(alpha: 0.5),
                    ),
                  ),
                  // Small sparkle
                  Positioned(
                    top: 20,
                    right: 22,
                    Icon(
                      Icons.auto_awesome_rounded,
                      size: 20,
                      color: _cGold.withValues(alpha: 0.6),
                    ),
                  ),
                  // Document icon
                  Positioned(
                    bottom: 18,
                    left: 22,
                    Icon(
                      Icons.description_rounded,
                      size: 18,
                      color: _cAmber.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            )
                .animate(onPlay: (c) => c.repeat())
                .shimmer(duration: 3000.ms, color: _cOrange.withValues(alpha: 0.06)),

            const SizedBox(height: 24),

            Text(
              'No documents yet',
              style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: _cTextPrimary,
              ),
            ),

            const SizedBox(height: 10),

            Text(
              'Securely store your family\'s important documents.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 14,
                color: _cTextSecondary,
                height: 1.6,
              ),
            ),

            const SizedBox(height: 6),

            Text(
              'Birth certificates, property deeds, legal documents — all encrypted with AES-256.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 13,
                color: _cTextDim,
                height: 1.5,
              ),
            ),

            const SizedBox(height: 24),

            // Upload CTA
            GestureDetector(
              onTap: () {
                // Trigger FAB-like action
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                decoration: BoxDecoration(
                  gradient: KinrelGradients.igniteGradient,
                  borderRadius: BorderRadius.circular(KinrelRadius.full),
                  boxShadow: [
                    BoxShadow(
                      color: _cOrange.withValues(alpha: 0.3),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cloud_upload_rounded, color: Colors.white, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      'Upload First Document',
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Document Detail Sheet
// ═══════════════════════════════════════════════════════════════════════

class _DocumentDetailSheet extends StatelessWidget {
  const _DocumentDetailSheet({required this.document});

  final VaultDocument document;

  @override
  Widget build(BuildContext context) {
    final accentColor = document.accentColor;

    return Padding(
      padding: const EdgeInsets.all(KinrelSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle bar
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: _cBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Document icon + type
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(KinrelRadius.md),
                ),
                child: Icon(document.typeIcon, size: 28, color: accentColor),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      document.title,
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: _cTextPrimary,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    _TypeBadge(type: document.type, accentColor: accentColor),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Document details
          _DetailRow(icon: Icons.person_outline_rounded, label: 'Member', value: document.memberName),
          _DetailRow(icon: Icons.calendar_today_rounded, label: 'Uploaded', value: document.formattedDate),
          _DetailRow(icon: Icons.insert_drive_file_rounded, label: 'Size', value: document.formattedFileSize),
          _DetailRow(
            icon: document.isEncrypted ? Icons.lock_rounded : Icons.lock_open_rounded,
            label: 'Encryption',
            value: document.isEncrypted ? 'AES-256 Encrypted' : 'Not Encrypted',
            valueColor: document.isEncrypted ? KinrelColors.success : KinrelColors.error,
          ),
          if (document.sharedWith.isNotEmpty)
            _DetailRow(
              icon: Icons.group_rounded,
              label: 'Shared with',
              value: '${document.sharedCount} member${document.sharedCount > 1 ? 's' : ''}',
            ),

          const SizedBox(height: 20),

          // Action buttons
          Row(
            children: [
              Expanded(
                child: _ActionButton(
                  icon: Icons.download_rounded,
                  label: 'Download',
                  accentColor: accentColor,
                  onTap: () {
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Downloading ${document.title}...'),
                        backgroundColor: _cCard,
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ActionButton(
                  icon: Icons.share_rounded,
                  label: 'Share',
                  accentColor: accentColor,
                  onTap: () {
                    Navigator.of(context).pop();
                  },
                  isGradient: true,
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Delete button
          SizedBox(
            width: double.infinity,
            child: TextButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
              },
              icon: Icon(Icons.delete_outline_rounded, size: 16, color: KinrelColors.error),
              label: Text(
                'Delete Document',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 13,
                  color: KinrelColors.error,
                ),
              ),
            ),
          ),

          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ── Detail row ───────────────────────────────────────────────────────

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: _cTextDim),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 13,
              color: _cTextDim,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: valueColor ?? _cTextPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Action button ────────────────────────────────────────────────────

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.accentColor,
    required this.onTap,
    this.isGradient = false,
  });

  final IconData icon;
  final String label;
  final Color accentColor;
  final VoidCallback onTap;
  final bool isGradient;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          gradient: isGradient ? KinrelGradients.igniteGradient : null,
          color: isGradient ? null : _cElevated,
          borderRadius: BorderRadius.circular(KinrelRadius.md),
          border: isGradient
              ? null
              : Border.all(color: accentColor.withValues(alpha: 0.3), width: 1),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16,
              color: isGradient ? Colors.white : accentColor,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isGradient ? Colors.white : accentColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Upload Document Bottom Sheet
// ═══════════════════════════════════════════════════════════════════════

class _UploadDocumentSheet extends ConsumerStatefulWidget {
  const _UploadDocumentSheet();

  @override
  ConsumerState<_UploadDocumentSheet> createState() => _UploadDocumentSheetState();
}

class _UploadDocumentSheetState extends ConsumerState<_UploadDocumentSheet> {
  DocumentType? _selectedType;
  final _titleController = TextEditingController();
  final _memberController = TextEditingController();
  bool _isUploading = false;

  static const _typeOptions = [
    (type: DocumentType.birth, label: 'Birth', icon: Icons.child_care_rounded),
    (type: DocumentType.marriage, label: 'Marriage', icon: Icons.favorite_rounded),
    (type: DocumentType.death, label: 'Death', icon: Icons.church_rounded),
    (type: DocumentType.property, label: 'Property', icon: Icons.home_rounded),
    (type: DocumentType.academic, label: 'Academic', icon: Icons.school_rounded),
    (type: DocumentType.legal, label: 'Legal', icon: Icons.gavel_rounded),
    (type: DocumentType.photos, label: 'Photos', icon: Icons.photo_library_rounded),
  ];

  @override
  void dispose() {
    _titleController.dispose();
    _memberController.dispose();
    super.dispose();
  }

  Color _typeColor(DocumentType type) {
    return VaultDocument(id: '', title: '', type: type, memberName: '', uploadDate: DateTime.now(), fileSize: 0).accentColor;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: KinrelSpacing.xl,
        right: KinrelSpacing.xl,
        top: KinrelSpacing.xl,
        bottom: MediaQuery.of(context).viewInsets.bottom + KinrelSpacing.xl,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: _cBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Title
            Text(
              'Upload Document',
              style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: _cTextPrimary,
                letterSpacing: 0.3,
              ),
            ),

            const SizedBox(height: 4),

            Text(
              'Securely add documents to the family vault',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 13,
                color: _cTextDim,
              ),
            ),

            const SizedBox(height: 20),

            // ── Document Type Selector ───────────────────────────────
            Text(
              'Document Type',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _cTextSecondary,
              ),
            ),
            const SizedBox(height: 10),

            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _typeOptions.map((option) {
                final isSelected = _selectedType == option.type;
                final color = _typeColor(option.type);

                return GestureDetector(
                  onTap: () => setState(() => _selectedType = option.type),
                  child: AnimatedContainer(
                    duration: KinrelMotion.fast,
                    curve: KinrelMotion.easeOut,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      gradient: isSelected
                          ? LinearGradient(
                              colors: [color, color.withValues(alpha: 0.8)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            )
                          : null,
                      color: isSelected ? null : _cElevated,
                      borderRadius: BorderRadius.circular(KinrelRadius.full),
                      border: isSelected
                          ? null
                          : Border.all(color: _cBorder, width: 1),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          option.icon,
                          size: 13,
                          color: isSelected ? Colors.white : color,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          option.label,
                          style: TextStyle(
                            fontFamily: KinrelTypography.bodyFont,
                            fontSize: 12,
                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                            color: isSelected ? Colors.white : _cTextSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: 20),

            // ── Title Input ──────────────────────────────────────────
            Text(
              'Document Title',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _cTextSecondary,
              ),
            ),
            const SizedBox(height: 8),

            TextField(
              controller: _titleController,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 14,
                color: _cTextPrimary,
              ),
              decoration: InputDecoration(
                hintText: 'e.g., Birth Certificate — Arjun Sharma',
                hintStyle: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 14,
                  color: _cTextDim,
                ),
                filled: true,
                fillColor: _cElevated,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(KinrelRadius.md),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(KinrelRadius.md),
                  borderSide: BorderSide(color: _cOrange, width: 1.5),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // ── Associate Member Picker ─────────────────────────────
            Text(
              'Associate Family Member',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _cTextSecondary,
              ),
            ),
            const SizedBox(height: 8),

            TextField(
              controller: _memberController,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 14,
                color: _cTextPrimary,
              ),
              decoration: InputDecoration(
                hintText: 'e.g., Arjun Sharma',
                hintStyle: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 14,
                  color: _cTextDim,
                ),
                filled: true,
                fillColor: _cElevated,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                suffixIcon: Icon(Icons.person_search_rounded, color: _cOrange, size: 20),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(KinrelRadius.md),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(KinrelRadius.md),
                  borderSide: BorderSide(color: _cOrange, width: 1.5),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // ── File Picker Placeholder ──────────────────────────────
            Text(
              'Select File',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _cTextSecondary,
              ),
            ),
            const SizedBox(height: 8),

            GestureDetector(
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('File picker will open here'),
                    backgroundColor: _cCard,
                  ),
                );
              },
              child: Container(
                height: 80,
                decoration: BoxDecoration(
                  color: _cElevated,
                  borderRadius: BorderRadius.circular(KinrelRadius.md),
                  border: Border.all(
                    color: _cBorder,
                    width: 1,
                    strokeAlign: BorderSide.strokeAlignInside,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.cloud_upload_outlined,
                      size: 28,
                      color: _cOrange.withValues(alpha: 0.6),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Tap to select PDF, Image, or Document',
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 11,
                        color: _cTextDim,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // ── Upload Button ───────────────────────────────────────
            Container(
              width: double.infinity,
              height: 50,
              decoration: BoxDecoration(
                gradient: KinrelGradients.igniteGradient,
                borderRadius: BorderRadius.circular(KinrelRadius.md),
                boxShadow: [
                  BoxShadow(
                    color: _cOrange.withValues(alpha: 0.25),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _isUploading ? null : _handleUpload,
                  borderRadius: BorderRadius.circular(KinrelRadius.md),
                  child: Center(
                    child: _isUploading
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.cloud_upload_rounded, color: Colors.white, size: 20),
                              const SizedBox(width: 8),
                              Text(
                                'Upload & Encrypt',
                                style: TextStyle(
                                  fontFamily: KinrelTypography.bodyFont,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            ),

            // Encryption notice
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.shield_rounded, size: 12, color: _cOrange.withValues(alpha: 0.6)),
                const SizedBox(width: 4),
                Text(
                  'Document will be encrypted with AES-256 before storage',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 10,
                    color: _cTextDim,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _handleUpload() {
    if (_selectedType == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please select a document type'),
          backgroundColor: _cCard,
        ),
      );
      return;
    }

    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please enter a document title'),
          backgroundColor: _cCard,
        ),
      );
      return;
    }

    setState(() => _isUploading = true);

    // Simulate upload with encryption
    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;

      final newDoc = VaultDocument(
        id: 'doc-${DateTime.now().millisecondsSinceEpoch}',
        title: _titleController.text.trim(),
        type: _selectedType!,
        memberName: _memberController.text.trim().isEmpty
            ? 'Unassigned'
            : _memberController.text.trim(),
        uploadDate: DateTime.now(),
        fileSize: 1024000, // Placeholder 1 MB
        fileExtension: 'pdf',
        isEncrypted: true,
        sharedWith: [],
      );

      ref.read(documentsProvider.notifier).addDocument(newDoc);

      setState(() => _isUploading = false);
      Navigator.of(context).pop();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Document uploaded and encrypted successfully'),
          backgroundColor: _cCard,
        ),
      );
    });
  }
}
