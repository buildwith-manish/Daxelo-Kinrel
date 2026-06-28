// lib/core/app_startup.dart
//
// DAXELO KINREL — App Startup Service
//
// Ensures the app shows real cached data within 100ms of launch.
// Never shows a blank screen or full-screen loader if Drift has
// any cached data.
//
// Responsibilities:
// 1. Pre-warm Drift connection before first frame
// 2. Read auth state from secure storage (no network)
// 3. Schedule background sync after 500ms delay (don't block UI)
// 4. On connectivity restored: trigger full sync of PendingOperations queue
// 5. Coordinate provider invalidation after background fetches

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Family;

import 'database/isar_database.dart';
import 'database/sync/connectivity_service.dart';
import 'database/sync/background_sync_manager.dart';
import 'database/sync/offline_queue.dart';
import 'family/family_provider.dart';
import 'kinship/kinship_provider.dart';
import 'services/supabase_service.dart';
import 'services/local_notification_scheduler.dart';
import 'utils/image_cache_config.dart';
import 'network/realtime_subscription.dart';

// ════════════════════════════════════════════════════════════════════
// APP STARTUP SERVICE
// ════════════════════════════════════════════════════════════════════

/// Coordinates app startup to ensure cached data appears within 100ms.
///
/// Usage:
/// ```dart
/// void main() async {
///   WidgetsFlutterBinding.ensureInitialized();
///   await AppStartupService.preWarmDrift();
///   runApp(const KinrelApp());
/// }
/// ```
///
/// In the app's `initState()`:
/// ```dart
/// AppStartupService.instance.initialize(ref);
/// // or from main.dart with a ProviderContainer:
/// AppStartupService.instance.initializeFromContainer(container);
/// ```
class AppStartupService {
  AppStartupService._();
  static final AppStartupService instance = AppStartupService._();

  ProviderContainer? _container;
  StreamSubscription<bool>? _connectivitySubscription;
  Timer? _backgroundSyncTimer;
  bool _isInitialized = false;
  bool _syncScheduled = false;

  /// Whether the service has been initialized.
  bool get isInitialized => _isInitialized;

  /// Pre-warm the Drift database connection and image cache before the first frame.
  ///
  /// Call this in `main()` BEFORE `runApp()` so that Drift is ready
  /// when the first provider reads from it. This takes typically < 20ms.
  /// Also initializes the image cache with 7-day disk cache and 100MB memory limit.
  static Future<void> preWarmDrift() async {
    try {
      if (!IsarDatabase.isInitialized) {
        await IsarDatabase.initialize();
        debugPrint('🚀 AppStartup: Drift pre-warmed successfully');
      }
    } catch (e) {
      // Don't block app launch if Drift fails — providers will fallback
      debugPrint('⚠️ AppStartup: Drift pre-warm failed: $e');
    }

    // Initialize image cache (7-day disk cache, 100MB memory limit)
    try {
      await ImageCacheConfig.initialize();
    } catch (e) {
      debugPrint('⚠️ AppStartup: Image cache init failed: $e');
    }
  }

  /// Initialize the startup service after the widget tree is built.
  ///
  /// Accepts a [Ref] (from a widget's `ref` or a provider's `ref`).
  void initialize(Ref ref) {
    initializeFromContainer(ref.container);
  }

  /// Initialize from a [ProviderContainer] directly (e.g. from main.dart).
  void initializeFromContainer(ProviderContainer container) {
    if (_isInitialized) return;
    _container = container;
    _isInitialized = true;

    debugPrint('🚀 AppStartup: Service initialized');

    // 1. Listen to connectivity changes
    _listenToConnectivity();

    // 2. Schedule background sync after 500ms (don't block UI)
    _scheduleBackgroundSync(const Duration(milliseconds: 500));

    // 3. Schedule provider refresh after a short delay
    _scheduleProviderRefresh();
  }

  /// Listen to connectivity changes. When connectivity is restored,
  /// trigger a full sync of the PendingOperations queue.
  void _listenToConnectivity() {
    if (_container == null) return;

    try {
      final connectivityService = _container!.read(connectivityServiceProvider);
      _connectivitySubscription = connectivityService.onConnectivityChanged.listen(
        (isOnline) {
          if (isOnline) {
            debugPrint('🚀 AppStartup: Connectivity restored, triggering full sync');
            _onConnectivityRestored();
          }
        },
      );
    } catch (e) {
      debugPrint('⚠️ AppStartup: Could not listen to connectivity: $e');
    }
  }

  /// Called when connectivity is restored.
  /// Triggers full sync of PendingOperations queue + provider refresh.
  void _onConnectivityRestored() {
    if (_container == null) return;

    // 1. Process pending offline operations
    try {
      final queue = _container!.read(offlineQueueProvider);
      queue.processPendingOperations().catchError((e) {
        debugPrint('⚠️ AppStartup: Pending ops sync failed: $e');
        return 0;
      });
    } catch (e) {
      debugPrint('⚠️ AppStartup: Could not process pending ops: $e');
    }

    // 2. Trigger full sync via BackgroundSyncManager
    try {
      final syncManager = _container!.read(backgroundSyncManagerProvider);
      syncManager.onConnectivityRestored();
    } catch (e) {
      debugPrint('⚠️ AppStartup: Could not trigger background sync: $e');
    }

    // 3. Invalidate key providers so they refresh from server
    _invalidateAllProviders();
  }

  /// Schedule background sync with a delay.
  void _scheduleBackgroundSync(Duration delay) {
    _backgroundSyncTimer?.cancel();
    _backgroundSyncTimer = Timer(delay, () {
      if (_container == null) return;

      try {
        final syncManager = _container!.read(backgroundSyncManagerProvider);
        syncManager.start();
        debugPrint('🚀 AppStartup: Background sync started');
      } catch (e) {
        debugPrint('⚠️ AppStartup: Could not start background sync: $e');
      }

      // Also process any pending offline operations
      try {
        final queue = _container!.read(offlineQueueProvider);
        queue.processPendingOperations().catchError((e) {
          debugPrint('⚠️ AppStartup: Pending ops processing failed: $e');
          return 0;
        });
      } catch (e) {
        debugPrint('⚠️ AppStartup: Could not process pending ops: $e');
      }
    });
  }

  /// Schedule a provider refresh to update cached data from server.
  ///
  /// This invalidates the key list providers so they re-fetch from
  /// Supabase. Since the providers already returned Drift cached data
  /// on first build, this invalidation causes a seamless refresh.
  void _scheduleProviderRefresh() {
    if (_syncScheduled) return;
    _syncScheduled = true;

    // Wait for Supabase to be ready before refreshing
    _waitForSupabaseAndRefresh();
  }

  /// Wait for Supabase to become ready, then invalidate providers.
  void _waitForSupabaseAndRefresh() async {
    if (_container == null) return;

    // PERF: Poll every 100ms (was 500ms) up to 50 times = 5 seconds max
    // (was 10 seconds). Checks 5× more frequently so it reacts faster
    // when Supabase is ready, and halves the worst-case wait time.
    for (int i = 0; i < 50; i++) {
      await Future.delayed(const Duration(milliseconds: 100));
      try {
        final isReady = _container!.read(isSupabaseReadyProvider);
        if (isReady) break;
      } catch (_) {}
    }

    // Preload the 5,359-entry Indian kinship dataset so the Add Member
    // flow can use it for inverse-relationship lookup, label display,
    // and the relationship picker sheet. This loads in the background
    // and is cached for the app's lifetime. See kinship_service.dart.
    _preloadKinshipData();

    // Now invalidate providers to trigger server-side refresh
    _invalidateAllProviders();
    _syncScheduled = false;

    // Subscribe to Supabase Realtime for all families
    _subscribeRealtime();

    // Schedule birthday & anniversary reminders after providers are loaded
    _scheduleOccasionReminders();
  }

  /// Preload the kinship dataset (5,359 relationships × 15 languages)
  /// in the background so the Add Member flow has it ready.
  void _preloadKinshipData() {
    if (_container == null) return;
    try {
      // Reading the FutureProvider triggers the load. The result is
      // cached by Riverpod for the app's lifetime.
      _container!.read(kinshipInitializedProvider.future).then((_) {
        final service = _container!.read(kinshipServiceProvider);
        debugPrint(
            '🚀 AppStartup: Kinship dataset loaded — ${service.totalRelationships} relationships across ${service.supportedLanguages.length} languages');
      }).catchError((e) {
        debugPrint('⚠️ AppStartup: Kinship dataset load failed: $e');
      });
    } catch (e) {
      debugPrint('⚠️ AppStartup: Could not preload kinship data: $e');
    }
  }

  /// Subscribe to Supabase Realtime channels for all families.
  /// This provides real-time updates when other users modify family data.
  void _subscribeRealtime() {
    if (_container == null) return;
    try {
      final realtimeService = _container!.read(realtimeSubscriptionProvider);
      realtimeService.subscribeAllFamilies();
      debugPrint('🚀 AppStartup: Supabase Realtime subscriptions activated');
    } catch (e) {
      debugPrint('⚠️ AppStartup: Realtime subscription failed: $e');
    }
  }

  /// Invalidate all key providers to trigger a re-fetch from Supabase.
  ///
  /// This is the core mechanism for "show cache first, refresh silently":
  /// 1. Provider built for the first time → reads from Drift cache (fast)
  /// 2. We call this method after Supabase is ready → providers re-fetch
  /// 3. Providers return fresh server data → UI updates seamlessly
  void _invalidateAllProviders() {
    if (_container == null) return;

    try {
      _container!.invalidate(familyListProvider);
      _container!.invalidate(archivedFamiliesProvider);
      debugPrint('🚀 AppStartup: Providers invalidated for server refresh');
    } catch (e) {
      debugPrint('⚠️ AppStartup: Could not invalidate providers: $e');
    }
  }

  /// Schedule birthday and anniversary reminders for all family members.
  /// Called after Supabase is ready and family data is loaded.
  void _scheduleOccasionReminders() async {
    if (_container == null) return;

    try {
      // Wait a bit for family data to be available
      await Future.delayed(const Duration(seconds: 2));

      final familiesAsync = _container!.read(familyListProvider);
      final families = familiesAsync.valueOrNull ?? [];
      if (families.isEmpty) return;

      final allMembers = <Map<String, dynamic>>[];
      final allAnniversaries = <Map<String, dynamic>>[];

      for (final family in families) {
        try {
          final membersAsync = _container!.read(familyMembersProvider(family.id));
          final members = membersAsync.valueOrNull ?? [];

          for (final person in members) {
            if (person.isDeceased) continue;

            if (person.dateOfBirth != null && person.dateOfBirth!.isNotEmpty) {
              allMembers.add({
                'id': person.id,
                'name': person.name,
                'dateOfBirth': person.dateOfBirth,
              });
            }

            // Check for anniversary date from the person's data
            // Person model may have anniversaryDate in the JSON
            final personJson = person.toJson();
            final annDate = personJson['anniversaryDate'] as String?;
            if (annDate != null && annDate.isNotEmpty) {
              allAnniversaries.add({
                'names': person.name,
                'date': annDate,
                'familyName': family.name,
              });
            }
          }
        } catch (_) {}
      }

      await LocalNotificationScheduler.scheduleAllWithReminders(
        members: allMembers,
        anniversaries: allAnniversaries,
      );
      debugPrint('📬 AppStartup: Occasion reminders scheduled (${allMembers.length} birthdays, ${allAnniversaries.length} anniversaries)');
    } catch (e) {
      debugPrint('⚠️ AppStartup: Occasion reminder scheduling failed: $e');
    }
  }

  /// Dispose all resources.
  void dispose() {
    _connectivitySubscription?.cancel();
    _backgroundSyncTimer?.cancel();
    _container = null;
    _isInitialized = false;
    _syncScheduled = false;
    debugPrint('🚀 AppStartup: Service disposed');
  }
}

// ════════════════════════════════════════════════════════════════════
// RIVERPOD PROVIDERS
// ════════════════════════════════════════════════════════════════════

/// Provider for the AppStartupService singleton.
///
/// Widgets can watch this to ensure the service is initialized.
final appStartupServiceProvider = Provider<AppStartupService>((ref) {
  final service = AppStartupService.instance;

  ref.onDispose(() {
    service.dispose();
  });

  return service;
});

/// Provider that checks if Drift cache has any data.
///
/// Used by UI to determine whether to show a loading skeleton
/// (first install, no cache) or show cached data immediately.
final hasCachedDataProvider = FutureProvider<bool>((ref) async {
  if (!IsarDatabase.isInitialized) return false;

  try {
    final db = ref.read(isarProvider);
    final stats = await db.getStats();
    final familyCount = stats['families'] ?? 0;
    final personCount = stats['persons'] ?? 0;
    return familyCount > 0 || personCount > 0;
  } catch (e) {
    debugPrint('⚠️ hasCachedDataProvider error: $e');
    return false;
  }
});

/// Provider that performs a background refresh of all cached data.
///
/// Call this when you want to silently refresh data without
/// blocking the UI. The pattern is:
/// 1. UI reads from existing providers (which show Drift cache)
/// 2. Call `ref.read(backgroundRefreshProvider.notifier).refresh()`
/// 3. Providers are invalidated → re-fetch from Supabase → UI updates
final backgroundRefreshProvider =
    StateNotifierProvider<BackgroundRefreshNotifier, AsyncValue<void>>((ref) {
  return BackgroundRefreshNotifier(ref);
});

/// Notifier for background refresh operations.
class BackgroundRefreshNotifier extends StateNotifier<AsyncValue<void>> {
  final Ref _ref;

  BackgroundRefreshNotifier(this._ref) : super(const AsyncValue.data(null));

  /// Trigger a background refresh of all key providers.
  ///
  /// This invalidates providers so they re-fetch from Supabase.
  /// The UI will update automatically when new data arrives.
  Future<void> refresh() async {
    state = const AsyncValue.loading();
    try {
      _ref.invalidate(familyListProvider);
      _ref.invalidate(archivedFamiliesProvider);

      // Wait for family list to complete its refresh
      await _ref.read(familyListProvider.future);

      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  /// Refresh providers for a specific family.
  Future<void> refreshFamily(String familyId) async {
    _ref.invalidate(familyDetailProvider(familyId));
    _ref.invalidate(familyMembersProvider(familyId));
    _ref.invalidate(familyRelationshipsProvider(familyId));
    _ref.invalidate(familyMembershipsProvider(familyId));
  }
}
