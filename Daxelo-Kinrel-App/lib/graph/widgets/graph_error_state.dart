// lib/graph/widgets/graph_error_state.dart
//
// Extracted from family_graph.dart (v31 refactor).
//
// Reusable error and empty-state widgets for the graph feature.
// Used by FamilyGraphWidget when graph data fails to load or when
// the layout produces no positions.
//
// v62: Categorized error states — distinguishes network failures,
// auth/session expiry, RLS permission errors, family-not-found, and
// generic errors. Each category shows a targeted icon, title, message,
// and action button (Retry / Sign In / Go Back).
//
// Web + mobile compatible: pure Flutter widgets, no platform code.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../../core/constants/brand_colors.dart';
import '../../core/constants/brand_typography.dart';
import '../../features/family/presentation/providers/family_graph_provider.dart';

/// Categories of graph errors, each with a tailored UI.
enum GraphErrorKind {
  /// Network timeout or connection failure.
  network,

  /// Auth token expired or user not signed in.
  auth,

  /// RLS policy denied access (user isn't a member of this family).
  permission,

  /// Family exists but has zero non-deleted persons.
  empty,

  /// Family ID doesn't exist or was deleted.
  notFound,

  /// Anything else — layout failures, parse errors, etc.
  unknown,
}

/// Metadata for a graph error category.
class _ErrorMeta {
  const _ErrorMeta({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final Color color;
}

/// Error state widget for the family graph.
///
/// v62: Categorizes the error and shows a targeted UI:
/// - [GraphErrorKind.network] → "You're offline" + Retry
/// - [GraphErrorKind.auth] → "Session expired" + Sign In
/// - [GraphErrorKind.permission] → "No access" + Go Back
/// - [GraphErrorKind.empty] → "No members yet" + Add Member
/// - [GraphErrorKind.notFound] → "Family not found" + Go Back
/// - [GraphErrorKind.unknown] → "Something went wrong" + Retry
class GraphErrorState extends ConsumerWidget {
  const GraphErrorState({
    super.key,
    required this.familyId,
    required this.error,
  });

  final String familyId;
  final Object error;

  /// Classifies [error] into a [GraphErrorKind] for tailored UI.
  static GraphErrorKind _classify(Object error) {
    if (error is TimeoutException) return GraphErrorKind.network;
    if (error is PostgrestException) {
      final code = error.code;
      // 42501 = RLS denial, 42502 = schema violation
      if (code == '42501' || code == '42502' || code == 'PGRST301') {
        return GraphErrorKind.permission;
      }
      // PGRST116 = "JSON object requested, multiple (or no) rows returned"
      if (code == 'PGRST116') return GraphErrorKind.notFound;
      // Network-related Postgrest errors
      final msg = error.message.toLowerCase();
      if (msg.contains('network') ||
          msg.contains('timeout') ||
          msg.contains('connection') ||
          msg.contains('socket')) {
        return GraphErrorKind.network;
      }
      // Auth-related
      if (msg.contains('jwt') ||
          msg.contains('token') ||
          msg.contains('unauthorized') ||
          msg.contains('session')) {
        return GraphErrorKind.auth;
      }
      return GraphErrorKind.unknown;
    }
    final msg = error.toString().toLowerCase();
    if (msg.contains('supabase client not available') ||
        msg.contains('not signed in') ||
        msg.contains('no current user')) {
      return GraphErrorKind.auth;
    }
    if (msg.contains('socket') ||
        msg.contains('network') ||
        msg.contains('timeout') ||
        msg.contains('connection')) {
      return GraphErrorKind.network;
    }
    if (msg.contains('not found') || msg.contains('no rows')) {
      return GraphErrorKind.notFound;
    }
    return GraphErrorKind.unknown;
  }

  /// Returns the UI metadata for a given error kind.
  static _ErrorMeta _metaFor(GraphErrorKind kind) {
    switch (kind) {
      case GraphErrorKind.network:
        return const _ErrorMeta(
          icon: Icons.wifi_off_rounded,
          title: "You're offline",
          message:
              "Can't reach the server. Check your connection and try again.",
          actionLabel: 'Retry',
          color: Color(0xFF607D8B), // Blue-grey
        );
      case GraphErrorKind.auth:
        return const _ErrorMeta(
          icon: Icons.lock_outline_rounded,
          title: 'Session expired',
          message: 'Your sign-in has expired. Please sign in again.',
          actionLabel: 'Sign In',
          color: Color(0xFFFFA726), // Orange
        );
      case GraphErrorKind.permission:
        return const _ErrorMeta(
          icon: Icons.shield_rounded,
          title: 'No access',
          message:
              "You don't have permission to view this family. Ask a family "
              'admin to invite you, or go back to your families list.',
          actionLabel: 'Go Back',
          color: Color(0xFFEF5350), // Red
        );
      case GraphErrorKind.empty:
        return const _ErrorMeta(
          icon: Icons.family_restroom,
          title: 'No members yet',
          message:
              'This family has no members. Add yourself to start building '
              'the family tree.',
          actionLabel: 'Add Member',
          color: Color(0xFF26A69A), // Teal
        );
      case GraphErrorKind.notFound:
        return const _ErrorMeta(
          icon: Icons.search_off_rounded,
          title: 'Family not found',
          message:
              "This family may have been deleted, or the link is incorrect.",
          actionLabel: 'Go Back',
          color: Color(0xFFAB47BC), // Purple
        );
      case GraphErrorKind.unknown:
        return const _ErrorMeta(
          icon: Icons.error_outline_rounded,
          title: 'Something went wrong',
          message:
              'An unexpected error occurred while loading the graph. '
              'Try again, or contact support if it persists.',
          actionLabel: 'Retry',
          color: KinrelColors.error,
        );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kind = _classify(error);
    final meta = _metaFor(kind);

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: meta.color.withValues(alpha: 0.12),
              ),
              child: Icon(meta.icon, size: 40, color: meta.color),
            ),
            const SizedBox(height: 20),
            Text(
              meta.title,
              style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: KinrelColors.textWhite,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              meta.message,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 14,
                color: KinrelColors.textSilver,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
            // Show the raw error detail in a collapsible section for
            // debugging (only for unknown errors).
            if (kind == GraphErrorKind.unknown) ...[
              const SizedBox(height: 12),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text(
                  'Error details',
                  style: TextStyle(
                    fontSize: 12,
                    color: KinrelColors.textSilver.withValues(alpha: 0.7),
                  ),
                ),
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: KinrelColors.darkCard,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SelectableText(
                      error.toString(),
                      style: TextStyle(
                        fontFamily: KinrelTypography.monoFont,
                        fontSize: 11,
                        color: KinrelColors.textSilver,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 20),
            // Primary action button — behavior depends on error kind.
            ElevatedButton.icon(
              onPressed: () => _handleAction(context, ref, kind),
              icon: Icon(_actionIcon(kind), size: 18),
              label: Text(meta.actionLabel),
              style: ElevatedButton.styleFrom(
                backgroundColor: meta.color,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Handles the primary action button press based on error kind.
  void _handleAction(BuildContext context, WidgetRef ref, GraphErrorKind kind) {
    switch (kind) {
      case GraphErrorKind.network:
      case GraphErrorKind.unknown:
        // Retry: invalidate the provider to trigger a refetch.
        ref.invalidate(familyGraphProvider(familyId));
        break;
      case GraphErrorKind.auth:
        // Navigate to sign-in.
        context.go('/sign-in');
        break;
      case GraphErrorKind.permission:
      case GraphErrorKind.notFound:
        // Go back to the previous screen.
        if (context.canPop()) {
          context.pop();
        } else {
          context.go('/families');
        }
        break;
      case GraphErrorKind.empty:
        // No-op — the empty state is handled by EmptyState widget, not
        // here. This case shouldn't normally be reached via error path.
        break;
    }
  }

  /// Returns the icon for the action button based on error kind.
  IconData _actionIcon(GraphErrorKind kind) {
    switch (kind) {
      case GraphErrorKind.network:
      case GraphErrorKind.unknown:
        return Icons.refresh_rounded;
      case GraphErrorKind.auth:
        return Icons.login_rounded;
      case GraphErrorKind.permission:
      case GraphErrorKind.notFound:
        return Icons.arrow_back_rounded;
      case GraphErrorKind.empty:
        return Icons.person_add_alt_1_rounded;
    }
  }
}

/// Empty-stack wrapper — a minimal Stack that hosts the [EmptyState]
/// widget without any graph canvas. Used when the layout produces no
/// positions (e.g. all persons deleted) but we still want to show
/// the empty-state UI.
class GraphEmptyStack extends StatelessWidget {
  const GraphEmptyStack({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
      ],
    );
  }
}
