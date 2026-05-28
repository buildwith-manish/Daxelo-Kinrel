// lib/features/documents/providers/documents_provider.dart
//
// DAXELO KINREL — Document Vault Provider
//
// Secure family document storage with AES-256 encryption tracking.
// Document types: Birth, Marriage, Death, Property, Academic, Legal, Photos.
//
// Orange K-Graph DNA: Birth = orange, Marriage = amber, Death = silver,
// Property = gold, Academic = blue, Legal = red, Photos = green.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/brand_colors.dart';

// ═══════════════════════════════════════════════════════════════════════
// Document Type Enum
// ═══════════════════════════════════════════════════════════════════════

/// Types of documents stored in the family vault.
enum DocumentType { birth, marriage, death, property, academic, legal, photos }

// ═══════════════════════════════════════════════════════════════════════
// Audit Log Entry
// ═══════════════════════════════════════════════════════════════════════

/// Represents a single access event in the document vault audit log.
class AuditLogEntry {
  const AuditLogEntry({
    required this.id,
    required this.memberName,
    required this.action,
    required this.documentTitle,
    required this.timestamp,
    this.memberInitials,
  });

  final String id;
  final String memberName;
  final String action;
  final String documentTitle;
  final DateTime timestamp;
  final String? memberInitials;

  /// Returns initials derived from the name if not explicitly set.
  String get displayInitials =>
      memberInitials ??
      (memberName.isNotEmpty
          ? memberName
                .split(' ')
                .where((s) => s.isNotEmpty)
                .take(2)
                .map((s) => s[0].toUpperCase())
                .join()
          : '?');

  /// Format the timestamp for display.
  String get formattedTime {
    final now = DateTime.now();
    final diff = now.difference(timestamp);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';

    const months = [
      '',
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${timestamp.day} ${months[timestamp.month]}';
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Vault Document Model
// ═══════════════════════════════════════════════════════════════════════

/// Represents a single document stored in the family vault.
class VaultDocument {
  const VaultDocument({
    required this.id,
    required this.title,
    required this.type,
    required this.memberName,
    required this.uploadDate,
    required this.fileSize,
    this.thumbnailUrl,
    this.isEncrypted = true,
    this.sharedWith = const [],
    this.memberInitials,
    this.fileExtension,
  });

  /// Unique identifier.
  final String id;

  /// Document title / name.
  final String title;

  /// Document type category.
  final DocumentType type;

  /// Name of the family member this document belongs to.
  final String memberName;

  /// Date the document was uploaded.
  final DateTime uploadDate;

  /// File size in bytes.
  final int fileSize;

  /// Optional thumbnail image URL (placeholder for now).
  final String? thumbnailUrl;

  /// Whether the document is encrypted with AES-256.
  final bool isEncrypted;

  /// List of family member IDs who have access to this document.
  final List<String> sharedWith;

  /// Optional member initials for avatar display.
  final String? memberInitials;

  /// Optional file extension (e.g., 'pdf', 'jpg', 'png').
  final String? fileExtension;

  // ── Computed Properties ──────────────────────────────────────────

  /// Returns initials derived from the member name if not explicitly set.
  String get displayInitials =>
      memberInitials ??
      (memberName.isNotEmpty
          ? memberName
                .split(' ')
                .where((s) => s.isNotEmpty)
                .take(2)
                .map((s) => s[0].toUpperCase())
                .join()
          : '?');

  /// Accent color for the document type.
  Color get accentColor {
    switch (type) {
      case DocumentType.birth:
        return KinrelColors.orange; // #E8612A
      case DocumentType.marriage:
        return KinrelColors.amber; // #F59240
      case DocumentType.death:
        return KinrelColors.textSilver; // #C9B4A8
      case DocumentType.property:
        return KinrelColors.gold; // #D4AF37
      case DocumentType.academic:
        return KinrelColors.blue; // #3B82F6
      case DocumentType.legal:
        return KinrelColors.error; // #F04E2A
      case DocumentType.photos:
        return KinrelColors.success; // #4CAF7A
    }
  }

  /// Icon for the document type.
  IconData get typeIcon {
    switch (type) {
      case DocumentType.birth:
        return Icons.child_care_rounded;
      case DocumentType.marriage:
        return Icons.favorite_rounded;
      case DocumentType.death:
        return Icons.church_rounded;
      case DocumentType.property:
        return Icons.home_rounded;
      case DocumentType.academic:
        return Icons.school_rounded;
      case DocumentType.legal:
        return Icons.gavel_rounded;
      case DocumentType.photos:
        return Icons.photo_library_rounded;
    }
  }

  /// Human-readable label for the document type.
  String get typeLabel {
    switch (type) {
      case DocumentType.birth:
        return 'Birth';
      case DocumentType.marriage:
        return 'Marriage';
      case DocumentType.death:
        return 'Death';
      case DocumentType.property:
        return 'Property';
      case DocumentType.academic:
        return 'Academic';
      case DocumentType.legal:
        return 'Legal';
      case DocumentType.photos:
        return 'Photos';
    }
  }

  /// Format the upload date for display.
  String get formattedDate {
    const months = [
      '',
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${uploadDate.day} ${months[uploadDate.month]}, ${uploadDate.year}';
  }

  /// Format file size for display.
  String get formattedFileSize {
    if (fileSize < 1024) return '$fileSize B';
    if (fileSize < 1024 * 1024) {
      return '${(fileSize / 1024).toStringAsFixed(1)} KB';
    }
    return '${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  /// Number of people the document is shared with.
  int get sharedCount => sharedWith.length;

  /// Copy with method for immutable updates.
  VaultDocument copyWith({
    String? id,
    String? title,
    DocumentType? type,
    String? memberName,
    DateTime? uploadDate,
    int? fileSize,
    String? thumbnailUrl,
    bool? isEncrypted,
    List<String>? sharedWith,
    String? memberInitials,
    String? fileExtension,
  }) {
    return VaultDocument(
      id: id ?? this.id,
      title: title ?? this.title,
      type: type ?? this.type,
      memberName: memberName ?? this.memberName,
      uploadDate: uploadDate ?? this.uploadDate,
      fileSize: fileSize ?? this.fileSize,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      isEncrypted: isEncrypted ?? this.isEncrypted,
      sharedWith: sharedWith ?? this.sharedWith,
      memberInitials: memberInitials ?? this.memberInitials,
      fileExtension: fileExtension ?? this.fileExtension,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Documents State
// ═══════════════════════════════════════════════════════════════════════

/// State for the Document Vault feature.
class DocumentsState {
  const DocumentsState({
    this.documents = const [],
    this.auditLog = const [],
    this.searchQuery = '',
    this.selectedType,
    this.isLoading = false,
    this.error,
  });

  final List<VaultDocument> documents;
  final List<AuditLogEntry> auditLog;
  final String searchQuery;
  final DocumentType? selectedType;
  final bool isLoading;
  final String? error;

  /// Filtered documents based on search query and selected type.
  List<VaultDocument> get filteredDocuments {
    var result = documents;

    // Filter by type
    if (selectedType != null) {
      result = result.where((d) => d.type == selectedType).toList();
    }

    // Filter by search query
    if (searchQuery.isNotEmpty) {
      final query = searchQuery.toLowerCase();
      result = result.where((d) {
        return d.title.toLowerCase().contains(query) ||
            d.memberName.toLowerCase().contains(query) ||
            d.typeLabel.toLowerCase().contains(query);
      }).toList();
    }

    // Sort by upload date (newest first)
    result = result.toList()
      ..sort((a, b) => b.uploadDate.compareTo(a.uploadDate));

    return result;
  }

  /// Documents grouped by type for category counts.
  Map<DocumentType, List<VaultDocument>> get documentsByType {
    final map = <DocumentType, List<VaultDocument>>{};
    for (final doc in documents) {
      (map[doc.type] ??= []).add(doc);
    }
    return map;
  }

  /// Total number of encrypted documents.
  int get encryptedCount => documents.where((d) => d.isEncrypted).length;

  /// Total file size of all documents.
  int get totalFileSize => documents.fold(0, (sum, d) => sum + d.fileSize);

  /// Last 3 audit log entries for preview.
  List<AuditLogEntry> get recentAuditLog {
    final sorted = auditLog.toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return sorted.take(3).toList();
  }

  DocumentsState copyWith({
    List<VaultDocument>? documents,
    List<AuditLogEntry>? auditLog,
    String? searchQuery,
    DocumentType? selectedType,
    bool clearSelectedType = false,
    bool isLoading = false,
    String? error,
  }) {
    return DocumentsState(
      documents: documents ?? this.documents,
      auditLog: auditLog ?? this.auditLog,
      searchQuery: searchQuery ?? this.searchQuery,
      selectedType: clearSelectedType
          ? null
          : (selectedType ?? this.selectedType),
      isLoading: isLoading,
      error: error,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Documents Notifier
// ═══════════════════════════════════════════════════════════════════════

/// State notifier managing the documents vault state and operations.
class DocumentsNotifier extends StateNotifier<DocumentsState> {
  DocumentsNotifier()
    : super(DocumentsState(documents: _demoDocuments, auditLog: _demoAuditLog));

  /// Set the search query.
  void setSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
  }

  /// Set the category filter.
  void setSelectedType(DocumentType? type) {
    if (type == null) {
      state = state.copyWith(clearSelectedType: true);
    } else {
      state = state.copyWith(selectedType: type);
    }
  }

  /// Clear all filters.
  void clearFilters() {
    state = state.copyWith(searchQuery: '', clearSelectedType: true);
  }

  /// Add a new document to the vault.
  void addDocument(VaultDocument document) {
    state = state.copyWith(documents: [...state.documents, document]);
    // Add audit log entry for upload
    final logEntry = AuditLogEntry(
      id: 'log-${DateTime.now().millisecondsSinceEpoch}',
      memberName: 'You',
      action: 'uploaded',
      documentTitle: document.title,
      timestamp: DateTime.now(),
      memberInitials: 'YO',
    );
    state = state.copyWith(auditLog: [...state.auditLog, logEntry]);
  }

  /// Share a document with a family member.
  void shareDocument(String documentId, String memberId) {
    final updatedDocs = state.documents.map((d) {
      if (d.id == documentId && !d.sharedWith.contains(memberId)) {
        return d.copyWith(sharedWith: [...d.sharedWith, memberId]);
      }
      return d;
    }).toList();
    state = state.copyWith(documents: updatedDocs);
  }

  /// Remove a document from the vault.
  void removeDocument(String documentId) {
    final doc = state.documents.firstWhere((d) => d.id == documentId);
    final updatedDocs = state.documents
        .where((d) => d.id != documentId)
        .toList();
    // Add audit log entry for deletion
    final logEntry = AuditLogEntry(
      id: 'log-${DateTime.now().millisecondsSinceEpoch}',
      memberName: 'You',
      action: 'deleted',
      documentTitle: doc.title,
      timestamp: DateTime.now(),
      memberInitials: 'YO',
    );
    state = state.copyWith(
      documents: updatedDocs,
      auditLog: [...state.auditLog, logEntry],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Provider
// ═══════════════════════════════════════════════════════════════════════

/// Main documents vault provider.
final documentsProvider =
    StateNotifierProvider<DocumentsNotifier, DocumentsState>((ref) {
      return DocumentsNotifier();
    });

// ═══════════════════════════════════════════════════════════════════════
// Demo Data — Realistic Indian Family Documents
// ═══════════════════════════════════════════════════════════════════════

final _now = DateTime.now();

final _demoDocuments = <VaultDocument>[
  // ── Birth Certificates ───────────────────────────────────────────
  VaultDocument(
    id: 'doc-birth-1',
    title: 'Birth Certificate — Arjun Sharma',
    type: DocumentType.birth,
    memberName: 'Arjun Sharma',
    memberInitials: 'AS',
    uploadDate: DateTime(2023, 6, 15),
    fileSize: 2457600, // 2.3 MB
    fileExtension: 'pdf',
    isEncrypted: true,
    sharedWith: ['m2', 'm7', 'm8'],
  ),
  VaultDocument(
    id: 'doc-birth-2',
    title: 'Birth Certificate — Priya Sharma',
    type: DocumentType.birth,
    memberName: 'Priya Sharma',
    memberInitials: 'PS',
    uploadDate: DateTime(2023, 6, 15),
    fileSize: 1874304, // 1.8 MB
    fileExtension: 'pdf',
    isEncrypted: true,
    sharedWith: ['m1'],
  ),
  VaultDocument(
    id: 'doc-birth-3',
    title: 'Birth Certificate — Aarav Sharma',
    type: DocumentType.birth,
    memberName: 'Aarav Sharma',
    memberInitials: 'AaS',
    uploadDate: DateTime(2023, 8, 22),
    fileSize: 3072000, // 2.9 MB
    fileExtension: 'pdf',
    isEncrypted: true,
    sharedWith: ['m1', 'm2'],
  ),

  // ── Marriage Certificates ────────────────────────────────────────
  VaultDocument(
    id: 'doc-marriage-1',
    title: 'Marriage Certificate — Ravi & Sunita Sharma',
    type: DocumentType.marriage,
    memberName: 'Ravi Sharma',
    memberInitials: 'RS',
    uploadDate: DateTime(2022, 11, 3),
    fileSize: 4096000, // 3.9 MB
    fileExtension: 'pdf',
    isEncrypted: true,
    sharedWith: ['m8', 'm6'],
  ),
  VaultDocument(
    id: 'doc-marriage-2',
    title: 'Marriage Certificate — Arjun & Priya Sharma',
    type: DocumentType.marriage,
    memberName: 'Arjun Sharma',
    memberInitials: 'AS',
    uploadDate: DateTime(2023, 1, 10),
    fileSize: 3584000, // 3.4 MB
    fileExtension: 'pdf',
    isEncrypted: true,
    sharedWith: ['m2', 'm7', 'm8'],
  ),
  VaultDocument(
    id: 'doc-marriage-3',
    title: 'Marriage Certificate — Rajesh & Meera Patel',
    type: DocumentType.marriage,
    memberName: 'Rajesh Patel',
    memberInitials: 'RP',
    uploadDate: DateTime(2023, 2, 18),
    fileSize: 2867200, // 2.7 MB
    fileExtension: 'pdf',
    isEncrypted: true,
    sharedWith: ['m4'],
  ),

  // ── Death Certificates ───────────────────────────────────────────
  VaultDocument(
    id: 'doc-death-1',
    title: 'Death Certificate — Suresh Kumar Sharma (Dada)',
    type: DocumentType.death,
    memberName: 'Suresh Kumar Sharma',
    memberInitials: 'SKS',
    uploadDate: DateTime(2021, 3, 8),
    fileSize: 1536000, // 1.5 MB
    fileExtension: 'pdf',
    isEncrypted: true,
    sharedWith: ['m6', 'm7'],
  ),

  // ── Property Documents ───────────────────────────────────────────
  VaultDocument(
    id: 'doc-property-1',
    title: 'Property Deed — Sharma House, Malviya Nagar',
    type: DocumentType.property,
    memberName: 'Ravi Sharma',
    memberInitials: 'RS',
    uploadDate: DateTime(2022, 7, 20),
    fileSize: 7168000, // 6.8 MB
    fileExtension: 'pdf',
    isEncrypted: true,
    sharedWith: ['m8', 'm6'],
  ),
  VaultDocument(
    id: 'doc-property-2',
    title: 'Property Deed — Farmhouse, Kukas, Jaipur',
    type: DocumentType.property,
    memberName: 'Kamla Sharma',
    memberInitials: 'KS',
    uploadDate: DateTime(2022, 9, 5),
    fileSize: 6144000, // 5.9 MB
    fileExtension: 'pdf',
    isEncrypted: true,
    sharedWith: ['m7', 'm8'],
  ),
  VaultDocument(
    id: 'doc-property-3',
    title: 'Sale Agreement — Patel Flat, Vastrapur',
    type: DocumentType.property,
    memberName: 'Rajesh Patel',
    memberInitials: 'RP',
    uploadDate: DateTime(2024, 1, 12),
    fileSize: 5120000, // 4.9 MB
    fileExtension: 'pdf',
    isEncrypted: true,
    sharedWith: ['m4'],
  ),

  // ── Academic Certificates ────────────────────────────────────────
  VaultDocument(
    id: 'doc-academic-1',
    title: 'B.Tech Degree — Arjun Sharma (IIT Delhi)',
    type: DocumentType.academic,
    memberName: 'Arjun Sharma',
    memberInitials: 'AS',
    uploadDate: DateTime(2023, 4, 15),
    fileSize: 2048000, // 2.0 MB
    fileExtension: 'pdf',
    isEncrypted: true,
    sharedWith: ['m2', 'm7'],
  ),
  VaultDocument(
    id: 'doc-academic-2',
    title: 'MBBS Degree — Neha Sharma (AIIMS Delhi)',
    type: DocumentType.academic,
    memberName: 'Neha Sharma',
    memberInitials: 'NS',
    uploadDate: DateTime(2023, 5, 20),
    fileSize: 1843200, // 1.8 MB
    fileExtension: 'pdf',
    isEncrypted: true,
    sharedWith: ['m7', 'm8'],
  ),
  VaultDocument(
    id: 'doc-academic-3',
    title: 'MBA Certificate — Priya Sharma (IIM Ahmedabad)',
    type: DocumentType.academic,
    memberName: 'Priya Sharma',
    memberInitials: 'PS',
    uploadDate: DateTime(2023, 3, 10),
    fileSize: 1638400, // 1.6 MB
    fileExtension: 'pdf',
    isEncrypted: true,
    sharedWith: ['m1'],
  ),

  // ── Legal Documents ──────────────────────────────────────────────
  VaultDocument(
    id: 'doc-legal-1',
    title: 'Will — Suresh Kumar Sharma (Dada)',
    type: DocumentType.legal,
    memberName: 'Suresh Kumar Sharma',
    memberInitials: 'SKS',
    uploadDate: DateTime(2020, 12, 1),
    fileSize: 3072000, // 2.9 MB
    fileExtension: 'pdf',
    isEncrypted: true,
    sharedWith: ['m6', 'm7'],
  ),
  VaultDocument(
    id: 'doc-legal-2',
    title: 'Power of Attorney — Kamla Sharma',
    type: DocumentType.legal,
    memberName: 'Kamla Sharma',
    memberInitials: 'KS',
    uploadDate: DateTime(2023, 9, 14),
    fileSize: 1280000, // 1.2 MB
    fileExtension: 'pdf',
    isEncrypted: true,
    sharedWith: ['m7'],
  ),
  VaultDocument(
    id: 'doc-legal-3',
    title: 'PAN Card — Arjun Sharma',
    type: DocumentType.legal,
    memberName: 'Arjun Sharma',
    memberInitials: 'AS',
    uploadDate: DateTime(2023, 1, 5),
    fileSize: 512000, // 500 KB
    fileExtension: 'jpg',
    isEncrypted: true,
    sharedWith: [],
  ),

  // ── Family Photographs (Historical) ──────────────────────────────
  VaultDocument(
    id: 'doc-photos-1',
    title: 'Family Photo — Sharma Diwali 1995',
    type: DocumentType.photos,
    memberName: 'Kamla Sharma',
    memberInitials: 'KS',
    uploadDate: DateTime(2024, 2, 10),
    fileSize: 4096000, // 3.9 MB
    fileExtension: 'jpg',
    isEncrypted: true,
    sharedWith: ['m7', 'm8', 'm1'],
  ),
  VaultDocument(
    id: 'doc-photos-2',
    title: 'Wedding Photo — Ravi & Sunita 1987',
    type: DocumentType.photos,
    memberName: 'Ravi Sharma',
    memberInitials: 'RS',
    uploadDate: DateTime(2024, 2, 10),
    fileSize: 5632000, // 5.4 MB
    fileExtension: 'jpg',
    isEncrypted: true,
    sharedWith: ['m8', 'm6'],
  ),
  VaultDocument(
    id: 'doc-photos-3',
    title: 'Dada & Dadi — Golden Jubilee 2010',
    type: DocumentType.photos,
    memberName: 'Suresh Kumar Sharma',
    memberInitials: 'SKS',
    uploadDate: DateTime(2024, 3, 1),
    fileSize: 3584000, // 3.4 MB
    fileExtension: 'jpg',
    isEncrypted: true,
    sharedWith: ['m6'],
  ),
];

// ── Audit Log Demo Data ────────────────────────────────────────────

final _demoAuditLog = <AuditLogEntry>[
  AuditLogEntry(
    id: 'log-1',
    memberName: 'Arjun Sharma',
    memberInitials: 'AS',
    action: 'viewed',
    documentTitle: 'Property Deed — Sharma House, Malviya Nagar',
    timestamp: _now.subtract(const Duration(hours: 2)),
  ),
  AuditLogEntry(
    id: 'log-2',
    memberName: 'Sunita Sharma',
    memberInitials: 'SS',
    action: 'downloaded',
    documentTitle: 'Marriage Certificate — Ravi & Sunita Sharma',
    timestamp: _now.subtract(const Duration(hours: 5)),
  ),
  AuditLogEntry(
    id: 'log-3',
    memberName: 'Ravi Sharma',
    memberInitials: 'RS',
    action: 'shared',
    documentTitle: 'Will — Suresh Kumar Sharma (Dada)',
    timestamp: _now.subtract(const Duration(days: 1)),
  ),
  AuditLogEntry(
    id: 'log-4',
    memberName: 'Priya Sharma',
    memberInitials: 'PS',
    action: 'viewed',
    documentTitle: 'Birth Certificate — Aarav Sharma',
    timestamp: _now.subtract(const Duration(days: 1, hours: 4)),
  ),
  AuditLogEntry(
    id: 'log-5',
    memberName: 'Kamla Sharma',
    memberInitials: 'KS',
    action: 'uploaded',
    documentTitle: 'Dada & Dadi — Golden Jubilee 2010',
    timestamp: _now.subtract(const Duration(days: 2)),
  ),
  AuditLogEntry(
    id: 'log-6',
    memberName: 'Rajesh Patel',
    memberInitials: 'RP',
    action: 'viewed',
    documentTitle: 'Sale Agreement — Patel Flat, Vastrapur',
    timestamp: _now.subtract(const Duration(days: 3)),
  ),
];
