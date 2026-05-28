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
final isOnlineProvider = StreamProvider<bool>((ref) {
  final service = ref.watch(connectivityServiceProvider);
  return service.onConnectivityChanged;
});
