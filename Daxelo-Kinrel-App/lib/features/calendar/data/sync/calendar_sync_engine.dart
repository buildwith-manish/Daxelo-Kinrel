// lib/features/calendar/data/sync/calendar_sync_engine.dart
// P5.4 — Calendar Sync Engine. Follows the Trackc pattern.

import 'dart:async';
import '../../../../core/database/sync/abstract_sync_engine.dart';

class CalendarSyncEngine extends AbstractSyncEngine {
  @override
  String get engineName => 'calendar';

  @override
  String get displayName => 'Family Calendar';

  bool _isSyncing = false;
  final _stateController = StreamController<SyncEngineState>.broadcast();

  @override
  bool get isSyncing => _isSyncing;

  @override
  Stream<SyncEngineState> get syncState => _stateController.stream;

  @override
  Future<DateTime?> pullDelta({List<String>? families}) async {
    if (_isSyncing) {
      _stateController.add(SyncEngineState.alreadyRunning);
      return null;
    }
    _isSyncing = true;
    _stateController.add(SyncEngineState.running);
    try {
      // TODO: Implement calendar delta pull
      _stateController.add(SyncEngineState.success);
      return DateTime.now();
    } catch (e) {
      _stateController.add(SyncEngineState.error);
      return null;
    } finally {
      _isSyncing = false;
    }
  }

  @override
  Future<int> pushOutbox() async => 0;

  @override
  void dispose() => _stateController.close();
}
