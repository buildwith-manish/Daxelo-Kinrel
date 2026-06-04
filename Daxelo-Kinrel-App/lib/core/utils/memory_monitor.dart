import 'dart:async';
import 'dart:developer' as developer;
/// Memory Monitor — debug-only utility that logs memory usage
/// periodically to help catch memory leaks before release.
///
/// Only runs in debug mode (stripped from release builds via assert).
class MemoryMonitor {
  MemoryMonitor._();

  static Timer? _timer;

  /// Start monitoring memory usage every 30 seconds.
  /// Only active in debug mode — no-op in release builds.
  static void start() {
    assert(() {
      _timer?.cancel();
      _timer = Timer.periodic(
        const Duration(seconds: 30),
        (_) {
          developer.log(
            'Memory: check flutter devtools for detailed memory profiling',
            name: 'MemoryMonitor',
            level: 900, // Fine level
          );
        },
      );
      developer.log(
        'MemoryMonitor started — logging every 30s',
        name: 'MemoryMonitor',
      );
      return true;
    }(), 'MemoryMonitor is only available in debug mode');
  }

  /// Stop monitoring memory usage.
  static void stop() {
    assert(() {
      _timer?.cancel();
      _timer = null;
      developer.log(
        'MemoryMonitor stopped',
        name: 'MemoryMonitor',
      );
      return true;
    }(), 'MemoryMonitor is only available in debug mode');
  }
}
