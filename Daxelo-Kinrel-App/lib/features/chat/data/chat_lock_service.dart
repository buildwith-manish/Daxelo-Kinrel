// lib/features/chat/data/chat_lock_service.dart
//
// DAXELO KINREL — Chat Lock Service (Tier 2 chat feature)
//
// Per-chat biometric lock using local_auth (already in pubspec).
// When a chat is locked, opening the chat screen shows a biometric
// prompt (Face ID / Touch ID / fingerprint). The chat only renders
// after a successful biometric check.
//
// Storage: a per-chat "locked" flag in shared_preferences (key
// 'chat_lock_<familyId>'). No DB round-trip — the lock is per-device
// (locking a chat on your phone doesn't lock it on your tablet).
//
// This matches WhatsApp's chat-lock behavior: the lock is local to
// the device, not synced. A future v2 could sync the locked-chats
// list via a new ChatSettings.isLocked column.

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ChatLockService {
  ChatLockService(this._ref);
  final Ref _ref;

  static const _prefix = 'chat_lock_';

  final LocalAuthentication _auth = LocalAuthentication();

  /// Whether the device supports biometric authentication (Face ID /
  /// Touch ID / fingerprint). Returns false on web (no biometrics).
  Future<bool> get isBiometricsAvailable async {
    try {
      final canCheck = await _auth.canCheckBiometrics;
      final isDeviceSupported = await _auth.isDeviceSupported();
      return canCheck || isDeviceSupported;
    } on PlatformException catch (e) {
      debugPrint('⚠️ ChatLockService.isBiometricsAvailable: $e');
      return false;
    }
  }

  /// Whether a specific chat is locked. Returns false if the
  /// lock flag isn't set (default = unlocked).
  Future<bool> isLocked(String chatId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool('$_prefix$chatId') ?? false;
    } catch (e) {
      debugPrint('⚠️ ChatLockService.isLocked: $e');
      return false;
    }
  }

  /// Lock or unlock a chat. Persists to shared_preferences.
  Future<void> setLocked(String chatId, bool locked) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('$_prefix$chatId', locked);
      debugPrint('🔒 ChatLockService: chat $chatId ${locked ? "locked" : "unlocked"}');
    } catch (e) {
      debugPrint('⚠️ ChatLockService.setLocked: $e');
    }
  }

  /// Prompt the user for biometric authentication. Returns true on
  /// success, false on failure / cancellation. The [reason] string is
  /// shown in the OS biometric prompt.
  Future<bool> authenticate(String reason) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false, // allow device PIN as fallback
        ),
      );
    } on PlatformException catch (e) {
      debugPrint('⚠️ ChatLockService.authenticate: $e');
      return false;
    }
  }
}

final chatLockServiceProvider = Provider<ChatLockService>((ref) {
  return ChatLockService(ref);
});
