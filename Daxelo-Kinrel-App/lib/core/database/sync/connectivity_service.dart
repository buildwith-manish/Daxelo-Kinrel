import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

/// Service that monitors network connectivity status.
/// Provides a stream of connectivity changes and current status.
class ConnectivityService {
  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _subscription;

  bool _isOnline = true;
  bool get isOnline => _isOnline;

  final _controller = StreamController<bool>.broadcast();
  Stream<bool> get onConnectivityChanged => _controller.stream;

  /// Start monitoring connectivity changes.
  void startMonitoring() {
    _subscription?.cancel();
    _subscription = _connectivity.onConnectivityChanged.listen((results) {
      final wasOnline = _isOnline;
      _isOnline = results.any((r) => r != ConnectivityResult.none);
      if (wasOnline != _isOnline) {
        debugPrint(
          _isOnline ? '🟢 Connectivity: Online' : '🔴 Connectivity: Offline',
        );
        _controller.add(_isOnline);
      }
    });

    // Check initial state
    checkNow();
  }

  /// Check current connectivity status immediately.
  Future<bool> checkNow() async {
    try {
      final results = await _connectivity.checkConnectivity();
      _isOnline = results.any((r) => r != ConnectivityResult.none);
      return _isOnline;
    } catch (e) {
      debugPrint('⚠️ Connectivity check failed: $e');
      // Assume online if we can't check — better to try and fail
      _isOnline = true;
      return true;
    }
  }

  /// Stop monitoring connectivity changes.
  void stopMonitoring() {
    _subscription?.cancel();
    _subscription = null;
  }

  /// Dispose resources.
  void dispose() {
    stopMonitoring();
    _controller.close();
  }
}

/// Riverpod provider for the ConnectivityService.
final connectivityServiceProvider = Provider<ConnectivityService>((ref) {
  final service = ConnectivityService();
  service.startMonitoring();
  ref.onDispose(() => service.dispose());
  return service;
});

/// Provider that reflects current online/offline status.
/// Automatically updates when connectivity changes.
/// Debounced (1000ms) to prevent rapid sync triggers during connectivity
/// flapping (e.g., mobile network switching between WiFi/cellular).
/// Increased from 500ms to 1000ms because connectivity flapping can trigger
/// multiple fullSync operations that cascade into provider invalidations,
/// causing ANR on slower devices.
final isOnlineProvider = StreamProvider<bool>((ref) {
  final service = ref.watch(connectivityServiceProvider);
  return _debounceStream(service.onConnectivityChanged, const Duration(milliseconds: 1000));
});

/// Debounce a stream — only emits the latest value after [duration] of silence.
Stream<T> _debounceStream<T>(Stream<T> source, Duration duration) {
  final controller = StreamController<T>.broadcast();
  Timer? timer;

  source.listen(
    (event) {
      timer?.cancel();
      timer = Timer(duration, () {
        controller.add(event);
      });
    },
    onError: controller.addError,
    onDone: () {
      timer?.cancel();
      controller.close();
    },
  );

  return controller.stream;
}
