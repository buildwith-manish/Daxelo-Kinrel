// lib/features/presence/presence_provider.dart
//
// DAXELO KINREL — Presence Signal
//
// Lightweight "home / at work / do not disturb" status for family members.
// NOT location-tracking — just a manual status toggle.
// High daily-open value: users check who's available before calling/messaging.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/services/supabase_service.dart';

enum PresenceStatus { home, work, dnd, away }

extension PresenceStatusExt on PresenceStatus {
  String get label => switch (this) {
    PresenceStatus.home => 'Home',
    PresenceStatus.work => 'At Work',
    PresenceStatus.dnd => 'Do Not Disturb',
    PresenceStatus.away => 'Away',
  };
  String get emoji => switch (this) {
    PresenceStatus.home => '🏠',
    PresenceStatus.work => '💼',
    PresenceStatus.dnd => '🔕',
    PresenceStatus.away => '🌙',
  };
  int get colorValue => switch (this) {
    PresenceStatus.home => 0xFF4CAF50,
    PresenceStatus.work => 0xFF2196F3,
    PresenceStatus.dnd => 0xFFF44336,
    PresenceStatus.away => 0xFF9E9E9E,
  };
  static PresenceStatus fromString(String? s) => switch (s) {
    'home' => PresenceStatus.home,
    'work' => PresenceStatus.work,
    'dnd' => PresenceStatus.dnd,
    _ => PresenceStatus.away,
  };
}

class FamilyPresence {
  final String userId;
  final String? displayName;
  final String? avatarUrl;
  final PresenceStatus status;
  final DateTime updatedAt;
  FamilyPresence({
    required this.userId,
    this.displayName,
    this.avatarUrl,
    required this.status,
    required this.updatedAt,
  });
  factory FamilyPresence.fromMap(Map<String, dynamic> map) => FamilyPresence(
    userId: map['userId'] as String? ?? '',
    displayName: map['displayName'] as String?,
    avatarUrl: map['avatarUrl'] as String?,
    status: PresenceStatusExt.fromString(map['status'] as String?),
    updatedAt: DateTime.tryParse(map['updatedAt'] as String? ?? '') ?? DateTime.now(),
  );
}

final myPresenceProvider = StateNotifierProvider<MyPresenceNotifier, PresenceStatus>(
  (ref) => MyPresenceNotifier(ref),
);

class MyPresenceNotifier extends StateNotifier<PresenceStatus> {
  final Ref _ref;
  MyPresenceNotifier(this._ref) : super(PresenceStatus.away);

  Future<void> load() async {
    final client = _ref.read(supabaseProvider);
    if (client == null) return;
    try {
      final userId = client.auth.currentUser?.id;
      if (userId == null) return;
      final result = await client
          .from('FamilyMember')
          .select('presenceStatus')
          .eq('userId', userId)
          .maybeSingle();
      if (result != null && mounted) {
        state = PresenceStatusExt.fromString(result['presenceStatus'] as String?);
      }
    } catch (_) {}
  }

  Future<void> update(PresenceStatus newStatus) async {
    state = newStatus;
    final client = _ref.read(supabaseProvider);
    if (client == null) return;
    try {
      final userId = client.auth.currentUser?.id;
      if (userId == null) return;
      await client.from('FamilyMember').update({
        'presenceStatus': newStatus.name,
        'presenceUpdatedAt': DateTime.now().toIso8601String(),
      }).eq('userId', userId);
    } catch (_) {}
  }
}

final familyPresenceProvider =
    FutureProvider.family<List<FamilyPresence>, String>(
  (ref, familyId) async {
    final client = ref.read(supabaseProvider);
    if (client == null) return [];
    try {
      final result = await client
          .from('FamilyMember')
          .select('''
            userId,
            presenceStatus,
            presenceUpdatedAt,
            user:User(displayName, avatarUrl)
          ''')
          .eq('familyId', familyId)
          .neq('role', 'viewer')
          .order('presenceUpdatedAt', ascending: false);
      return result.map((e) => FamilyPresence.fromMap({
        'userId': e['userId'],
        'displayName': (e['user'] as Map?)?['displayName'],
        'avatarUrl': (e['user'] as Map?)?['avatarUrl'],
        'status': e['presenceStatus'],
        'updatedAt': e['presenceUpdatedAt'],
      })).toList();
    } catch (_) {
      return [];
    }
  },
);
