// lib/core/services/deep_link_service.dart
//
// DAXELO KINREL — Deep Link Service (P3-F2)
//
// Centralizes all deep link handling for the app:
//   • Generates shareable URLs (https://kinrel.app/family/:id,
//     https://kinrel.app/member/:id, https://kinrel.app/share/:id)
//   • Uses share_plus to share via WhatsApp, SMS, etc.
//   • Handles incoming deep links when app is opened from a link
//   • Uses Isar cache to show content instantly while API loads
//   • Navigates to the correct screen using GoRouter
//
// Supported deep link paths:
//   /family/:id   → Family detail screen
//   /member/:id   → Person detail screen
//   /share/:id    → Share screen for a family
//   /invite/:code → Join family by invite code
//
// URL schemes:
//   https://kinrel.app/...  (universal links — Android + iOS)
//   kinrel://...            (custom scheme — Android + iOS)

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app_links/app_links.dart';
// Isar import removed — using Drift via IsarDatabase wrapper
import 'package:share_plus/share_plus.dart' as share_plus;

import '../database/isar_database.dart';
import '../database/collections/cached_family.dart';
import '../database/collections/cached_person.dart';
import '../services/crashlytics_service.dart';

// ═══════════════════════════════════════════════════════════════════════
// Constants
// ═══════════════════════════════════════════════════════════════════════

/// Base URL for universal links
const kDeepLinkBaseUrl = 'https://kinrel.app';

/// Custom URL scheme
const kDeepLinkScheme = 'kinrel';

/// Supported deep link path prefixes
const kPathFamily = '/family';
const kPathMember = '/member';
const kPathShare = '/share';
const kPathInvite = '/invite';

// ═══════════════════════════════════════════════════════════════════════
// URL Generation Helpers
// ═══════════════════════════════════════════════════════════════════════

/// Generate a shareable family profile URL.
/// Example: https://kinrel.app/family/abc123
String generateFamilyUrl(String familyId) {
  return '$kDeepLinkBaseUrl$kPathFamily/$familyId';
}

/// Generate a shareable member profile URL.
/// Example: https://kinrel.app/member/xyz789
String generateMemberUrl(String memberId) {
  return '$kDeepLinkBaseUrl$kPathMember/$memberId';
}

/// Generate a shareable family graph share URL.
/// Example: https://kinrel.app/share/abc123
String generateShareUrl(String familyId) {
  return '$kDeepLinkBaseUrl$kPathShare/$familyId';
}

/// Generate an invite URL from an invite code.
/// Example: https://kinrel.app/invite/sharma25
String generateInviteUrl(String inviteCode) {
  return '$kDeepLinkBaseUrl$kPathInvite/$inviteCode';
}

/// Generate a custom-scheme family URL (fallback).
/// Example: kinrel://family/abc123
String generateFamilySchemeUrl(String familyId) {
  return '$kDeepLinkScheme://$kPathFamily/$familyId';
}

/// Generate a custom-scheme member URL (fallback).
/// Example: kinrel://member/xyz789
String generateMemberSchemeUrl(String memberId) {
  return '$kDeepLinkScheme://$kPathMember/$memberId';
}

// ═══════════════════════════════════════════════════════════════════════
// Share Functions (using share_plus)
// ═══════════════════════════════════════════════════════════════════════

/// Share a family profile link via the system share sheet.
/// Uses share_plus to share via WhatsApp, SMS, email, etc.
Future<void> shareFamilyLink({
  required String familyId,
  required String familyName,
}) async {
  final url = generateFamilyUrl(familyId);
  final text =
      'Hey! Check out the $familyName family on Kinrel 🧡\n\n'
      'Explore our family tree and discover how everyone is connected:\n'
      '🔗 $url\n\n'
      '— Sent via Kinrel by Daxelo';

  logActionBreadcrumb('share_family_link', {'familyId': familyId});

  await share_plus.Share.share(
    text,
    subject: 'Join the $familyName Family on Kinrel',
  );
}

/// Share a member profile link via the system share sheet.
Future<void> shareMemberLink({
  required String memberId,
  required String memberName,
}) async {
  final url = generateMemberUrl(memberId);
  final text =
      'Check out $memberName on Kinrel 🧡\n\n'
      'See how they\'re connected in the family:\n'
      '🔗 $url\n\n'
      '— Sent via Kinrel by Daxelo';

  logActionBreadcrumb('share_member_link', {'memberId': memberId});

  await share_plus.Share.share(
    text,
    subject: '$memberName on Kinrel',
  );
}

/// Share a family graph link (invite-style) via the system share sheet.
Future<void> shareGraphLink({
  required String familyId,
  required String familyName,
}) async {
  final url = generateShareUrl(familyId);
  final text =
      'Explore the $familyName family graph on Kinrel 🧡\n\n'
      'Visualize how everyone is connected in the family tree:\n'
      '🔗 $url\n\n'
      '— Sent via Kinrel by Daxelo';

  logActionBreadcrumb('share_graph_link', {'familyId': familyId});

  await share_plus.Share.share(
    text,
    subject: '$familyName Family Graph on Kinrel',
  );
}

/// Share an invite link via WhatsApp.
/// Opens WhatsApp with a pre-formatted message.
Future<void> shareViaWhatsApp({
  required String familyId,
  required String familyName,
}) async {
  final url = generateFamilyUrl(familyId);
  final message =
      'Hey! Join our family on Kinrel 🧡\n\n'
      'I\'m building our family tree and I\'d love for you to be part of it. '
      'Click the link below to join the *$familyName* family:\n\n'
      '🔗 $url\n\n'
      '— Sent via Kinrel by Daxelo';

  logActionBreadcrumb('share_whatsapp', {'familyId': familyId});

  await share_plus.Share.share(message);
}

/// Share an invite link via SMS.
Future<void> shareViaSMS({
  required String familyId,
  required String familyName,
}) async {
  final url = generateFamilyUrl(familyId);
  final message =
      'Join our family on Kinrel! Click here: $url — Sent via Kinrel';

  logActionBreadcrumb('share_sms', {'familyId': familyId});

  await share_plus.Share.share(message);
}

// ═══════════════════════════════════════════════════════════════════════
// Deep Link Parsing
// ═══════════════════════════════════════════════════════════════════════

/// Parsed result from a deep link URL.
class DeepLinkRoute {
  const DeepLinkRoute({
    required this.path,
    this.id,
    this.queryParams,
  });

  /// The route path (e.g., '/family', '/member', '/share', '/invite')
  final String path;

  /// The ID extracted from the path (e.g., family ID, member ID, invite code)
  final String? id;

  /// Optional query parameters from the URL
  final Map<String, String>? queryParams;

  /// Convert to a GoRouter-compatible location string.
  /// Examples:
  ///   DeepLinkRoute(path: '/family', id: 'abc123') → '/family/abc123'
  ///   DeepLinkRoute(path: '/invite', id: 'sharma25') → '/family/join?code=sharma25'
  String toLocation() {
    if (id == null) return path;
    switch (path) {
      case kPathFamily:
        return '$kPathFamily/$id';
      case kPathMember:
        return '$kPathMember/$id';
      case kPathShare:
        return '$kPathShare/$id';
      case kPathInvite:
        // Invite codes route to the invitations screen with the code
        return '$kPathInvite/$id';
      default:
        return '$path/$id';
    }
  }

  @override
  String toString() => 'DeepLinkRoute(path: $path, id: $id, queryParams: $queryParams)';
}

/// Parse a deep link URI into a DeepLinkRoute.
///
/// Supports both universal links (https://kinrel.app/family/abc123)
/// and custom scheme links (kinrel://family/abc123).
DeepLinkRoute? parseDeepLink(Uri uri) {
  // Normalize: strip host for https links, strip scheme for custom scheme
  final pathSegments = uri.pathSegments;
  if (pathSegments.isEmpty) return null;

  final firstSegment = '/${pathSegments[0]}';

  // Check if this is a supported path
  if (firstSegment != kPathFamily &&
      firstSegment != kPathMember &&
      firstSegment != kPathShare &&
      firstSegment != kPathInvite) {
    return null;
  }

  // Extract the ID from the second path segment
  final id = pathSegments.length > 1 ? pathSegments[1] : null;

  // Extract query parameters
  final queryParams = <String, String>{};
  if (uri.queryParameters.isNotEmpty) {
    queryParams.addAll(uri.queryParameters);
  }

  return DeepLinkRoute(
    path: firstSegment,
    id: id,
    queryParams: queryParams.isEmpty ? null : queryParams,
  );
}

// ═══════════════════════════════════════════════════════════════════════
// Isar Cache Preloading
// ═══════════════════════════════════════════════════════════════════════

/// Preload cached data for a deep link target from Isar.
///
/// This ensures the screen has data to display instantly while
/// the API call loads fresh data in the background.
/// Returns the cached data if available, null otherwise.
Future<DeepLinkCacheResult?> preloadFromCache(DeepLinkRoute route) async {
  if (!IsarDatabase.isInitialized) return null;

  try {
    final isar = IsarDatabase.instance;

    switch (route.path) {
      case kPathFamily:
      case kPathShare:
        if (route.id != null) {
          final cached = await isar.getFamily(route.id!);
          if (cached != null) {
            return DeepLinkCacheResult(
              type: 'family',
              id: route.id!,
              data: cached.toJson(),
            );
          }
        }
        break;

      case kPathMember:
        if (route.id != null) {
          final cached = await isar.getPerson(route.id!);
          if (cached != null) {
            return DeepLinkCacheResult(
              type: 'member',
              id: route.id!,
              data: cached.toJson(),
            );
          }
        }
        break;

      case kPathInvite:
        // Invite codes map to families — look up by familyCode
        if (route.id != null) {
          final cached = await isar.getFamilyByCode(route.id!);
          if (cached != null) {
            return DeepLinkCacheResult(
              type: 'family',
              id: cached.id,
              data: cached.toJson(),
            );
          }
        }
        break;
    }
  } catch (e) {
    debugPrint('⚠️ Deep link cache preload error: $e');
    logError(e, StackTrace.current, reason: 'Deep link cache preload failed');
  }

  return null;
}

/// Result of a cache preload for a deep link.
class DeepLinkCacheResult {
  const DeepLinkCacheResult({
    required this.type,
    required this.id,
    required this.data,
  });

  /// The type of cached entity ('family' or 'member')
  final String type;

  /// The entity ID
  final String id;

  /// The cached data as a JSON map
  final Map<String, dynamic> data;

  /// The family name if this is a family cache result
  String? get familyName => data['name'] as String?;

  /// The member name if this is a member cache result
  String? get memberName => data['name'] as String?;
}

// ═══════════════════════════════════════════════════════════════════════
// Deep Link Service — Initialization & Listener
// ═══════════════════════════════════════════════════════════════════════

/// Service that listens for incoming deep links and navigates accordingly.
///
/// Usage in main.dart or KinrelApp:
/// ```dart
/// final deepLinkService = ref.read(deepLinkServiceProvider);
/// deepLinkService.init(context);
/// ```
class DeepLinkService {
  DeepLinkService(this._ref);

  final Ref _ref;
  StreamSubscription<Uri>? _linkSubscription;
  final _appLinks = AppLinks();
  bool _initialized = false;

  /// Whether the service is currently listening for deep links.
  bool get isInitialized => _initialized;

  /// Initialize the deep link listener.
  /// Call this after the widget tree is built (e.g., in addPostFrameCallback).
  ///
  /// [onDeepLink] is called when a deep link is received while the app
  /// is running. It receives the GoRouter location string to navigate to.
  Future<void> init({
    required void Function(String location) onDeepLink,
  }) async {
    if (_initialized) return;
    _initialized = true;

    logActionBreadcrumb('deep_link_service_init');

    // ── Handle cold start (app opened from a deep link) ────────────
    try {
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) {
        debugPrint('🔗 Deep link (cold start): $initialUri');
        logNavigationBreadcrumb('deep_link_cold:$initialUri');

        final route = parseDeepLink(initialUri);
        if (route != null) {
          // Preload cache for instant display
          await preloadFromCache(route);

          // Navigate after a short delay to let the app fully initialize
          Future.delayed(const Duration(milliseconds: 800), () {
            onDeepLink(route.toLocation());
          });
        }
      }
    } catch (e) {
      debugPrint('⚠️ Deep link initial URI error: $e');
      logError(e, StackTrace.current, reason: 'Deep link initial URI failed');
    }

    // ── Handle warm start (app already running, opened from a link) ─
    try {
      _linkSubscription = _appLinks.uriLinkStream.listen(
        (Uri uri) {
          debugPrint('🔗 Deep link (warm start): $uri');
          logNavigationBreadcrumb('deep_link_warm:$uri');

          final route = parseDeepLink(uri);
          if (route != null) {
            // Preload cache
            preloadFromCache(route).then((_) {
              onDeepLink(route.toLocation());
            });
          }
        },
        onError: (err) {
          debugPrint('⚠️ Deep link stream error: $err');
          logError(err, StackTrace.current, reason: 'Deep link stream error');
        },
      );
    } catch (e) {
      debugPrint('⚠️ Deep link stream setup error: $e');
      logError(e, StackTrace.current, reason: 'Deep link stream setup failed');
    }

    debugPrint('✅ Deep link service initialized');
  }

  /// Stop listening for deep links.
  void dispose() {
    _linkSubscription?.cancel();
    _linkSubscription = null;
    _initialized = false;
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Riverpod Providers
// ═══════════════════════════════════════════════════════════════════════

/// Provider for the DeepLinkService singleton.
final deepLinkServiceProvider = Provider<DeepLinkService>((ref) {
  final service = DeepLinkService(ref);
  ref.onDispose(() => service.dispose());
  return service;
});

/// Provider that resolves a deep link URL to a cached family name.
/// Used to show the family name in the UI while the API loads.
final deepLinkFamilyNameProvider = FutureProvider.family<String?, String>((
  ref,
  familyId,
) async {
  if (!IsarDatabase.isInitialized) return null;

  try {
    final isar = IsarDatabase.instance;
    final cached = await isar.getFamily(familyId);
    return cached?.name;
  } catch (_) {
    return null;
  }
});

/// Provider that resolves a deep link URL to a cached member name.
/// Used to show the member name in the UI while the API loads.
final deepLinkMemberNameProvider = FutureProvider.family<String?, String>((
  ref,
  memberId,
) async {
  if (!IsarDatabase.isInitialized) return null;

  try {
    final isar = IsarDatabase.instance;
    final cached = await isar.getPerson(memberId);
    return cached?.name;
  } catch (_) {
    return null;
  }
});
