// lib/core/utils/io_platform_stub.dart
//
// Web stub for dart:io Platform — provides a Platform class with the
// same static getters as dart:io's Platform, but all return false on
// web (since dart:io is unavailable).
//
// Used via conditional import in main.dart:
//   import 'dart:io'
//       if (dart.library.html) 'core/utils/io_platform_stub.dart'
//       show Platform;
//
// On web, all Platform.is* getters return false, so the desktop window
// setup block in main.dart (which checks Platform.isWindows ||
// Platform.isLinux || Platform.isMacOS) is skipped automatically.

class Platform {
  static bool get isWindows => false;
  static bool get isLinux => false;
  static bool get isMacOS => false;
  static bool get isAndroid => false;
  static bool get isIOS => false;
  static bool get isFuchsia => false;

  static String get operatingSystem => 'web';
  static String get localeName => 'en_US';
  static int get numberOfProcessors => 1;
  static String get pathSeparator => '/';
  static String get operatingSystemVersion => 'web';
}
