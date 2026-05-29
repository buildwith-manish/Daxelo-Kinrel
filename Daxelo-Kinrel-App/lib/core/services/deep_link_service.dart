// lib/core/services/deep_link_service.dart
//
// DAXELO KINREL — Deep Link Service (P3-F2)
//
// Centralizes all deep link handling for the app:
//   • Generates shareable URLs (https://kinrel.app/family/:id,
//     https://kinrel.app/member/:id, https://kinrel.app/share/:id)
//   • Uses share_plus to share via WhatsApp, SMS, etc.
//   • Handles incoming deep links when app is opened from a link
//   • Uses Drift cache to show content instantly while API loads
//   • Navigates to the correct screen using GoRouter
//
// Supported deep link paths:
//   /family/:id   → Family detail screen
//   /member/:id   → Person detail screen
//   /share/:id    → Share screen for a family
//   /invite/:code → Join family by invite code
//   /join/:kinId  → Join family by KIN-XXXXXXXX ID
//
// Enhancements (Task 4):
//   • KIN-XXXXXXXX format validation for /join/ deep links
//   • Family preview preloading from CachedFamilyIds table
//   • Deep link analytics (tracking when deep links are opened)
//   • Join deep link family preview data (name, member count)
//   • Deferred deep link support (pending deep link for post-login)
//   • Deep link URL validation and sanitization
//
// URL schemes:
//   https://kinrel.app/...  (universal links — Android + iOS)
//   kinrel://...            (custom scheme — Android + iOS)

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app_links/app_links.dart';
import 'package:share_plus/share_plus.dart' as share_plus;

import '../database/isar_database.dart';
import '../services/crashlytics_service.dart';
import '../services/analytics_service.dart';

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
const kPathJoin = '/join';

/// KIN-XXXXXXXX format validation regex
final _kinFamilyIdRegex = RegExp(r'^KIN-[A-Z0-9]{8}$');

/// Validate a KIN-XXXXXXXX Family ID format
bool isValidKinFamilyId(String input) {
  return _kinFamilyIdRegex.hasMatch(input.trim().toUpperCase());
}

/// Sanitize a KIN Family ID by normalizing to uppercase and trimming
String? sanitizeKinFamilyId(String? input) {
  if (input == null || input.isEmpty) return null;
  final sanitized = input.trim().toUpperCase();
  if (isValidKinFamilyId(sanitized)) return sanitized;
  return null;
}

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

/// Generate a join URL from a KIN-XXXXXXXX Family ID.
/// Example: https://kinrel.app/join/KIN-ABCD1234
String generateJoinUrl(String kinFamilyId) {
  return '$kDeepLinkBaseUrl$kPathJoin/$kinFamilyId';
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

  /// The route path (e.g., '/family', '/member', '/share', '/invite', '/join')
  final String path;

  /// The ID extracted from the path (e.g., family ID, member ID, invite code)
  final String? id;

  /// Optional query parameters from the URL
  final Map<String, String>? queryParams;

  /// Convert to a GoRouter-compatible location string.
  /// Examples:
  ///   DeepLinkRoute(path: '/family', id: 'abc123') → '/family/abc123'
  ///   DeepLinkRoute(path: '/invite', id: 'sharma25') → '/invite/sharma25'
  ///   DeepLinkRoute(path: '/join', id: 'KIN-ABCD1234') → '/join-family?kinFamilyId=KIN-ABCD1234'
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
      case kPathJoin:
        // Join by KIN-XXXXXXXX Family ID → join family screen pre-filled
        // Validate the KIN ID format before constructing the route
        final kinId = id!.trim().toUpperCase();
        if (isValidKinFamilyId(kinId)) {
          return '/join-family?kinFamilyId=$kinId';
        }
        // Invalid KIN ID format — still navigate but without pre-fill
        debugPrint('⚠️ Deep link KIN ID invalid format: $id');
        return '/join-family';
      default:
        return '$path/$id';
    }
  }

  /// Whether this deep link is a join-family link
  bool get isJoinLink => path == kPathJoin;

  /// Whether this deep link has a valid KIN-XXXXXXXX ID
  bool get hasValidKinId => id != null && isValidKinFamilyId(id!);

  @override
  String toString() => 'DeepLinkRoute(path: $path, id: $id, queryParams: $queryParams)';
}

/// Parse a deep link URI into a DeepLinkRoute.
///
/// Supports both universal links (https://kinrel.app/family/abc123)
/// and custom scheme links (kinrel://family/abc123).
///
/// For /join/ links, validates the KIN-XXXXXXXX format.
DeepLinkRoute? parseDeepLink(Uri uri) {
  // Normalize: strip host for https links, strip scheme for custom scheme
  final pathSegments = uri.pathSegments;
  if (pathSegments.isEmpty) return null;

  final firstSegment = '/${pathSegments[0]}';

  // Check if this is a supported path
  if (firstSegment != kPathFamily &&
      firstSegment != kPathMember &&
      firstSegment != kPathShare &&
      firstSegment != kPathInvite &&
      firstSegment != kPathJoin) {
    return null;
  }

  // Extract the ID from the second path segment
  final id = pathSegments.length > 1 ? pathSegments[1] : null;

  // For /join/ links, validate and normalize the KIN Family ID
  if (firstSegment == kPathJoin && id != null) {
    final normalizedId = id.trim().toUpperCase();

    // Validate KIN-XXXXXXXX format
    if (!isValidKinFamilyId(normalizedId)) {
      debugPrint('⚠️ Deep link /join/ has invalid KIN ID: $id');
      // Still create the route but with the original (unvalidated) ID
      // The join screen will handle validation
    }
  }

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
// Drift Cache Preloading
// ═══════════════════════════════════════════════════════════════════════

/// Preload cached data for a deep link target from Drift.
///
/// This ensures the screen has data to display instantly while
/// the API call loads fresh data in the background.
/// Returns the cached data if available, null otherwise.
Future<DeepLinkCacheResult?> preloadFromCache(DeepLinkRoute route) async {
  if (!IsarDatabase.isInitialized) return null;

  try {
    final db = IsarDatabase.instance;

    switch (route.path) {
      case kPathFamily:
      case kPathShare:
        if (route.id != null) {
          final cached = await db.getFamily(route.id!);
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
          final cached = await db.getPerson(route.id!);
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
          final cached = await db.getFamilyByCode(route.id!);
          if (cached != null) {
            return DeepLinkCacheResult(
              type: 'family',
              id: cached.id,
              data: cached.toJson(),
            );
          }
        }
        break;

      case kPathJoin:
        // Join by KIN-XXXXXXXX — look up by kinFamilyId in CachedFamilyIds
        if (route.id != null) {
          try {
            final db = IsarDatabase.instance;
            // Try exact match first using the dedicated method
            final cachedById = await db.getFamilyByKinId(route.id!.toUpperCase());
            if (cachedById != null) {
              return DeepLinkCacheResult(
                type: 'family',
                id: cachedById.familyId,
                data: {
                  'id': cachedById.familyId,
                  'name': cachedById.name,
                  'kinFamilyId': cachedById.kinFamilyId,
                  'memberCount': cachedById.memberCount,
                  'avatarUrl': cachedById.avatarUrl,
                },
              );
            }

            // Fallback: scan all cached family IDs
            final cachedIds = await db.getAllCachedFamilyIds();
            for (final cached in cachedIds) {
              if (cached.kinFamilyId.toUpperCase() == route.id!.toUpperCase()) {
                return DeepLinkCacheResult(
                  type: 'family',
                  id: cached.familyId,
                  data: {
                    'id': cached.familyId,
                    'name': cached.name,
                    'kinFamilyId': cached.kinFamilyId,
                    'memberCount': cached.memberCount,
                    'avatarUrl': cached.avatarUrl,
                  },
                );
              }
            }
          } catch (_) {}
        }
        break;
    }
  } catch (e) {
    debugPrint('⚠️ Deep link cache preload error: $e');
    logError(e, StackTrace.current, reason: 'Deep link cache preload failed');
  }

  return null;
}

/// Preload a family preview for a KIN-XXXXXXXX join deep link.
///
/// Returns a [DeepLinkFamilyPreview] with name, member count, and
/// other cached details if available.
Future<DeepLinkFamilyPreview?> preloadFamilyPreview(String kinFamilyId) async {
  if (!IsarDatabase.isInitialized) return null;

  try {
    final db = IsarDatabase.instance;
    final normalizedId = kinFamilyId.trim().toUpperCase();

    // Try exact match in CachedFamilyIds table
    final cached = await db.getFamilyByKinId(normalizedId);
    if (cached != null) {
      return DeepLinkFamilyPreview(
        familyId: cached.familyId,
        kinFamilyId: cached.kinFamilyId,
        name: cached.name,
        memberCount: cached.memberCount,
        avatarUrl: cached.avatarUrl,
      );
    }

    // Fallback: try CachedFamilies table by kinFamilyId
    final allFamilies = await db.getAllFamilies();
    for (final family in allFamilies) {
      if (family.kinFamilyId?.toUpperCase() == normalizedId) {
        return DeepLinkFamilyPreview(
          familyId: family.id,
          kinFamilyId: family.kinFamilyId!,
          name: family.name,
          avatarUrl: null, // not directly on CachedFamily
        );
      }
    }
  } catch (e) {
    debugPrint('⚠️ preloadFamilyPreview error: $e');
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

  /// The member count if this is a family cache result
  int? get memberCount => data['memberCount'] as int?;
}

/// Family preview data for a join deep link.
class DeepLinkFamilyPreview {
  const DeepLinkFamilyPreview({
    required this.familyId,
    required this.kinFamilyId,
    required this.name,
    this.memberCount = 0,
    this.avatarUrl,
  });

  final String familyId;
  final String kinFamilyId;
  final String name;
  final int memberCount;
  final String? avatarUrl;
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

  /// Pending deep link for deferred handling (e.g., after login)
  String? _pendingDeepLinkLocation;

  /// Whether there's a pending deep link waiting to be handled
  bool get hasPendingDeepLink => _pendingDeepLinkLocation != null;

  /// Get and clear the pending deep link location
  String? consumePendingDeepLink() {
    final location = _pendingDeepLinkLocation;
    _pendingDeepLinkLocation = null;
    return location;
  }

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

          // Track deep link open
          _trackDeepLinkOpen(route);

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
              // Track deep link open
              _trackDeepLinkOpen(route);
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

  /// Track deep link open for analytics
  void _trackDeepLinkOpen(DeepLinkRoute route) {
    try {
      AnalyticsService.instance.logScreenView('deep_link_${route.path.substring(1)}');

      if (route.isJoinLink && route.hasValidKinId) {
        // Track invite click from deep link
        debugPrint('📊 Deep link: join family invite clicked (${route.id})');
      }
    } catch (e) {
      debugPrint('⚠️ Deep link analytics error: $e');
    }
  }

  /// Store a pending deep link for deferred handling.
  /// Used when a deep link is received but the user isn't authenticated yet.
  void setPendingDeepLink(String location) {
    _pendingDeepLinkLocation = location;
    debugPrint('🔗 Deep link: stored pending location: $location');
  }

  /// Stop listening for deep links.
  void dispose() {
    _linkSubscription?.cancel();
    _linkSubscription = null;
    _initialized = false;
    _pendingDeepLinkLocation = null;
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
    final db = IsarDatabase.instance;
    final cached = await db.getFamily(familyId);
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
    final db = IsarDatabase.instance;
    final cached = await db.getPerson(memberId);
    return cached?.name;
  } catch (_) {
    return null;
  }
});

/// Provider that preloads a family preview for a KIN Family ID deep link.
/// Used by JoinFamilyScreen to show family info instantly from cache.
final deepLinkFamilyPreviewProvider = FutureProvider.family<DeepLinkFamilyPreview?, String>((
  ref,
  kinFamilyId,
) async {
  return preloadFamilyPreview(kinFamilyId);
});
