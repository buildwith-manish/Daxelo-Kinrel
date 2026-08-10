// lib/features/profile/presentation/member_profile_sheet.dart
//
// DAXELO KINREL — Member Profile Bottom Sheet
//
// A modal bottom sheet that can be opened from anywhere a member's avatar
// or name is tapped (group chat bubble avatar, chat header members list,
// graph node, etc.). Shows the member's avatar, name, relation label,
// and action buttons: View Full Profile, Message (DM), View Timeline.
//
// The "Message" button is hidden when memberId equals the current user's
// ID (no point DMing yourself).

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/constants/brand_typography.dart';

/// A modal bottom sheet showing a member's profile summary with action
/// buttons to view their full profile, start a DM, or view their timeline.
///
/// Usage:
///   MemberProfileSheet.show(context, memberId, relationLabel: 'Your brother');
///
/// Or inline:
///   MemberProfileSheet(memberId: 'abc123', relationLabel: 'Your sister');
class MemberProfileSheet extends ConsumerWidget {
  const MemberProfileSheet({
    super.key,
    required this.memberId,
    this.relationLabel,
  });

  /// The target user's auth ID (NOT a Person id).
  final String memberId;

  /// Optional viewer-relative relationship label (e.g. "Your brother").
  /// Rendered as a muted subtitle under the name.
  final String? relationLabel;

  /// Opens the sheet as a modal bottom sheet with a DraggableScrollableSheet
  /// inside a transparent container so the rounded corners show.
  static Future<void> show(
    BuildContext context,
    String memberId, {
    String? relationLabel,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.45,
        minChildSize: 0.3,
        maxChildSize: 0.7,
        expand: false,
        builder: (ctx, scrollController) => MemberProfileSheet(
          memberId: memberId,
          relationLabel: relationLabel,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    final isSelf = currentUserId != null && currentUserId == memberId;

    return FutureBuilder<Map<String, dynamic>?>(
      future: _loadProfile(),
      builder: (context, snapshot) {
        final name = snapshot.data?['name'] as String? ?? 'Member';
        final avatarUrl = snapshot.data?['avatarUrl'] as String?;

        return Container(
          decoration: const BoxDecoration(
            color: KinrelColors.darkCard,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(KinrelRadius.bottomSheet),
            ),
          ),
          child: snapshot.connectionState == ConnectionState.waiting
              ? const SizedBox(
                  height: 200,
                  child: Center(
                    child: CircularProgressIndicator(
                      color: KinrelColors.orange,
                    ),
                  ),
                )
              : SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    KinrelSpacing.xl,
                    KinrelSpacing.lg,
                    KinrelSpacing.xl,
                    MediaQuery.of(context).padding.bottom +
                        KinrelSpacing.lg,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Drag handle
                      Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 20),
                        decoration: BoxDecoration(
                          color: KinrelColors.border,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      // Avatar
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: KinrelColors.orange.withValues(alpha: 0.15),
                        ),
                        child: ClipOval(
                          child: avatarUrl != null && avatarUrl.isNotEmpty
                              ? CachedNetworkImage(
                                  imageUrl: avatarUrl,
                                  fit: BoxFit.cover,
                                  placeholder: (_, __) => Center(
                                    child: Text(
                                      _initials(name),
                                      style: TextStyle(
                                        fontFamily:
                                            KinrelTypography.displayFont,
                                        fontSize: 28,
                                        fontWeight: FontWeight.w700,
                                        color: KinrelColors.orange,
                                      ),
                                    ),
                                  ),
                                  errorWidget: (_, __, ___) => Center(
                                    child: Text(
                                      _initials(name),
                                      style: TextStyle(
                                        fontFamily:
                                            KinrelTypography.displayFont,
                                        fontSize: 28,
                                        fontWeight: FontWeight.w700,
                                        color: KinrelColors.orange,
                                      ),
                                    ),
                                  ),
                                )
                              : Center(
                                  child: Text(
                                    _initials(name),
                                    style: TextStyle(
                                      fontFamily: KinrelTypography.displayFont,
                                      fontSize: 28,
                                      fontWeight: FontWeight.w700,
                                      color: KinrelColors.orange,
                                    ),
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Name
                      Text(
                        name,
                        style: TextStyle(
                          fontFamily: KinrelTypography.displayFont,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: KinrelColors.textWhite,
                        ),
                      ),
                      // Relation label
                      if (relationLabel != null &&
                          relationLabel!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          relationLabel!,
                          style: TextStyle(
                            fontFamily: KinrelTypography.bodyFont,
                            fontSize: 13,
                            color: KinrelColors.orange,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      // Message button (hidden for self)
                      if (!isSelf)
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: () {
                              Navigator.of(context).pop();
                              context.push('/dm/$memberId');
                            },
                            icon: const Icon(Icons.chat_bubble_rounded,
                                size: 20),
                            label: const Text('Message'),
                            style: FilledButton.styleFrom(
                              backgroundColor: KinrelColors.orange,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                vertical: 14,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(KinrelRadius.button),
                              ),
                            ),
                          ),
                        ),
                      // View Full Profile button
                      SizedBox(
                        width: double.infinity,
                        child: TextButton.icon(
                          onPressed: () {
                            Navigator.of(context).pop();
                            context.push('/member/$memberId');
                          },
                          icon: const Icon(Icons.person_outline_rounded,
                              size: 20),
                          label: const Text('View Full Profile'),
                          style: TextButton.styleFrom(
                            foregroundColor: KinrelColors.textWhite,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                      // View Timeline button
                      SizedBox(
                        width: double.infinity,
                        child: TextButton.icon(
                          onPressed: () {
                            Navigator.of(context).pop();
                            context.push('/member/$memberId/timeline');
                          },
                          icon: const Icon(Icons.timeline_outlined, size: 20),
                          label: const Text('View Timeline'),
                          style: TextButton.styleFrom(
                            foregroundColor: KinrelColors.textSilver,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
        );
      },
    );
  }

  /// Loads the member's public profile via the same RPC used by
  /// DirectChatScreen.
  Future<Map<String, dynamic>?> _loadProfile() async {
    try {
      final response = await Supabase.instance.client.rpc(
        'fn_get_user_public_profile',
        params: {'p_user_id': memberId},
      ).timeout(const Duration(seconds: 8));
      return response as Map<String, dynamic>?;
    } catch (_) {
      return null;
    }
  }

  String _initials(String name) {
    if (name.isEmpty) return '?';
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name[0].toUpperCase();
  }
}
