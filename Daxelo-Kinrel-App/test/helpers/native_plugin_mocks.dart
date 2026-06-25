// test/helpers/native_plugin_mocks.dart
//
// DAXELO KINREL — Test helper that mocks native plugin method channels so
// unit tests can run headlessly without MissingPluginException.
//
// Currently mocks:
//   - flutter_secure_storage (plugins.it_nomads.com/flutter_secure_storage)
//   - shared_preferences (plugins.flutter.io/shared_preferences)
//
// Usage in a test file:
//   import '../helpers/native_plugin_mocks.dart';
//
//   void main() {
//     TestWidgetsFlutterBinding.ensureInitialized();
//     setUpAll(setupNativePluginMocks);
//     tearDownAll(tearDownNativePluginMocks);
//     ...
//   }

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// In-memory key-value store backing the mocks.
final Map<String, Object> _sharedPrefsStore = <String, Object>{};
final Map<String, String> _secureStorageStore = <String, String>{};

const MethodChannel _sharedPrefsChannel =
    MethodChannel('plugins.flutter.io/shared_preferences');
const MethodChannel _secureStorageChannel =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

/// Installs mock handlers for all native plugins used by the graph tests.
///
/// Call this in `setUpAll` after `TestWidgetsFlutterBinding.ensureInitialized()`.
void setupNativePluginMocks() {
  // ── shared_preferences mock ──────────────────────────────────────────
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_sharedPrefsChannel, (MethodCall call) async {
    switch (call.method) {
      case 'getAll':
        return Map<String, Object>.from(_sharedPrefsStore);
      case 'setString':
      case 'setBool':
      case 'setInt':
      case 'setDouble':
      case 'setStringList':
        final args = Map<String, dynamic>.from(call.arguments as Map);
        final key = args['key'] as String?;
        final value = args['value'];
        if (key != null) {
          _sharedPrefsStore[key] = value as Object;
        }
        return true;
      case 'remove':
        final args = Map<String, dynamic>.from(call.arguments as Map);
        final key = args['key'] as String?;
        if (key != null) {
          _sharedPrefsStore.remove(key);
        }
        return true;
      case 'clear':
        _sharedPrefsStore.clear();
        return true;
      default:
        return null;
    }
  });

  // ── flutter_secure_storage mock ──────────────────────────────────────
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_secureStorageChannel, (MethodCall call) async {
    switch (call.method) {
      case 'read':
        final args = Map<String, dynamic>.from(call.arguments as Map);
        final key = args['key'] as String?;
        if (key == null) return null;
        return _secureStorageStore[key];
      case 'write':
        final args = Map<String, dynamic>.from(call.arguments as Map);
        final key = args['key'] as String?;
        final value = args['value'] as String?;
        if (key != null && value != null) {
          _secureStorageStore[key] = value;
        }
        return null;
      case 'delete':
        final args = Map<String, dynamic>.from(call.arguments as Map);
        final key = args['key'] as String?;
        if (key != null) {
          _secureStorageStore.remove(key);
        }
        return null;
      case 'readAll':
        return Map<String, String>.from(_secureStorageStore);
      case 'deleteAll':
        _secureStorageStore.clear();
        return null;
      default:
        return null;
    }
  });
}

/// Removes the mock handlers. Call this in `tearDownAll` to avoid
/// cross-test contamination when running in a larger suite.
void tearDownNativePluginMocks() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_sharedPrefsChannel, null);
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_secureStorageChannel, null);
  _sharedPrefsStore.clear();
  _secureStorageStore.clear();
}
