// lib/features/calendar/providers/calendar_provider.dart

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';
import '../models/calendar_models.dart';

class CalendarState {
  const CalendarState({
    this.events = const [],
    this.rsvps = const {},
    this.isLoading = false,
    this.error,
  });
  final List<CalendarEvent> events;
  final Map<String, List<EventRSVP>> rsvps; // eventId -> rsvps
  final bool isLoading;
  final String? error;

  CalendarState copyWith({
    List<CalendarEvent>? events,
    Map<String, List<EventRSVP>>? rsvps,
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) => CalendarState(
    events: events ?? this.events,
    rsvps: rsvps ?? this.rsvps,
    isLoading: isLoading ?? this.isLoading,
    error: clearError ? null : (error ?? this.error),
  );
}

class CalendarNotifier extends StateNotifier<CalendarState> {
  CalendarNotifier(this._ref, this.familyId) : super(const CalendarState(isLoading: true));
  final Ref _ref;
  final String familyId;

  SupabaseClient? get _client => _ref.read(supabaseProvider);
  String? get _myId => _client?.auth.currentUser?.id;
  String get _myName => _client?.auth.currentUser?.userMetadata?['name'] as String? ?? 'Member';

  Future<void> load() async {
    final client = _client;
    final myId = _myId;
    if (client == null || myId == null) {
      state = state.copyWith(isLoading: false, error: 'Not signed in');
      return;
    }
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final eventsResp = await client
          .from('calendar_events')
          .select()
          .eq('familyId', familyId)
          .order('eventDate', ascending: true);
      final events = eventsResp.map((e) => CalendarEvent.fromJson(e as Map<String, dynamic>)).toList();
      state = CalendarState(events: events, isLoading: false);
    } catch (e) {
      debugPrint('⚠️ Calendar load error: $e');
      state = state.copyWith(isLoading: false, error: '$e');
    }
  }

  Future<bool> createEvent(CalendarEvent event) async {
    final client = _client;
    final myId = _myId;
    if (client == null || myId == null) return false;
    try {
      final data = event.toJson();
      data['createdBy'] = myId;
      await client.from('calendar_events').insert(data);
      await load();
      return true;
    } catch (e) {
      debugPrint('⚠️ Calendar create error: $e');
      return false;
    }
  }

  Future<bool> updateEvent(CalendarEvent event) async {
    final client = _client;
    if (client == null) return false;
    try {
      await client.from('calendar_events').update(event.toJson()).eq('id', event.id);
      await load();
      return true;
    } catch (e) {
      debugPrint('⚠️ Calendar update error: $e');
      return false;
    }
  }

  Future<bool> deleteEvent(String eventId) async {
    final client = _client;
    if (client == null) return false;
    try {
      await client.from('calendar_events').delete().eq('id', eventId);
      await load();
      return true;
    } catch (e) {
      debugPrint('⚠️ Calendar delete error: $e');
      return false;
    }
  }

  Future<bool> submitRSVP(String eventId, RSVPStatus status) async {
    final client = _client;
    final myId = _myId;
    if (client == null || myId == null) return false;
    try {
      await client.from('calendar_event_rsvps').upsert({
        'eventId': eventId,
        'userId': myId,
        'userName': _myName,
        'status': status.name,
        'respondedAt': DateTime.now().toIso8601String(),
      });
      return true;
    } catch (e) {
      debugPrint('⚠️ RSVP error: $e');
      return false;
    }
  }
}

final calendarProvider =
    StateNotifierProvider.autoDispose.family<CalendarNotifier, CalendarState, String>(
  (ref, familyId) => CalendarNotifier(ref, familyId),
);
