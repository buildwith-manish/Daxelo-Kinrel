// lib/features/thinking/presentation/family_ring_widget.dart
//
// "Who are you thinking of?" — horizontal ring of family member faces.
// Tap any face to send a silent "Thinking of You" signal.
//
// v109: ONLY shows real, verified Kinrel users — manually-created
// custom profiles (people added just to build the family graph) are
// excluded. The filter is defense-in-depth:
//   1. deletedAt == null (not deleted)
//   2. isLinkedToKinrelUser (linkedUserId is non-null + non-empty)
//   3. linkedUserId is a valid UUID (rejects placeholder / non-UUID
//      values that might have been set incorrectly)
//   4. The current user is excluded (you can't "think of" yourself)
//
// Placed BELOW the Truth Streak card, BEFORE the quick-jump dock,
// as an additional engagement layer. Does NOT replace Truth Streak.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dio/dio.dart';
import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/family/family_provider.dart';
import '../../../core/services/supabase_service.dart';
import '../data/thinking_service.dart';

/// Regex for a valid UUID v4. Used to validate that linkedUserId is a
/// real Kinrel auth user ID, not a placeholder or incorrectly-set value.
/// Manually-created custom profiles have linkedUserId = null, but if a
/// bug or data-migration issue ever set it to a non-UUID value, this
/// check rejects it so the person doesn't appear in the "thinking of"
/// list.
final _uuidRegex = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

/// Returns true if [id] is a valid UUID v4 string.
bool _isValidUuid(String? id) {
  if (id == null || id.isEmpty) return false;
  return _uuidRegex.hasMatch(id);
}

class FamilyRingWidget extends ConsumerStatefulWidget {
  const FamilyRingWidget({
    super.key,
    required this.familyId,
  });

  final String familyId;

  @override
  ConsumerState<FamilyRingWidget> createState() => _FamilyRingWidgetState();
}

class _FamilyRingWidgetState extends ConsumerState<FamilyRingWidget> {
  final Map<String, DateTime> _tappedUntil = {};
  final Set<String> _cooldown = {};

  bool _isTapped(String userId) {
    final expiry = _tappedUntil[userId];
    return expiry != null && DateTime.now().isBefore(expiry);
  }

  Future<void> _onTap(BuildContext context, Person member) async {
    // v109: Guard — only send to real Kinrel users with a valid UUID.
    // This is a belt-and-suspenders check; the build method already
    // filters the list, but this prevents any edge case (e.g., a race
    // where the member list changed between build and tap) from
    // sending a tap to an invalid recipient.
    if (!_isValidUuid(member.linkedUserId)) return;
    final userId = member.linkedUserId!;

    if (_cooldown.contains(userId)) {
      _showSnack(context, 'Already sent — try again later');
      return;
    }

    HapticFeedback.lightImpact();

    // Optimistic UI: show tapped state immediately
    setState(() {
      _tappedUntil[userId] = DateTime.now().add(const Duration(seconds: 3));
    });

    try {
      final service = ref.read(thinkingServiceProvider);
      await service.sendTap(
        receiverId: userId,
        familyId: widget.familyId,
      );

      if (!mounted) return;
      _showSnack(context, '${member.name} knows you\'re thinking of them');
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      setState(() {
        _tappedUntil.remove(userId);
        if (status == 400) _cooldown.add(userId);
      });
      if (status == 400) {
        // Rate limited — show on cooldown for 10s (UI only)
        Future.delayed(const Duration(seconds: 10), () {
          if (mounted) setState(() => _cooldown.remove(userId));
        });
        if (mounted) _showSnack(context, 'Already sent — try again later');
      } else {
        if (mounted) _showSnack(context, 'Something went wrong. Try again.');
      }
    } catch (e) {
      setState(() => _tappedUntil.remove(userId));
      if (mounted) _showSnack(context, 'Something went wrong. Try again.');
    }
  }

  void _showSnack(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        backgroundColor: KinrelColors.darkCard,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(familyDetailProvider(widget.familyId));
    final detail = detailAsync.valueOrNull;

    if (detail == null) return const SizedBox.shrink();

    // v109: Defense-in-depth filter — only real, verified Kinrel users.
    // Manually-created custom profiles (people added just to build the
    // family graph) are excluded by ALL of these checks:
    //   1. deletedAt == null — exclude soft-deleted persons
    //   2. isLinkedToKinrelUser — linkedUserId is non-null + non-empty
    //   3. _isValidUuid(linkedUserId) — the linkedUserId is a valid UUID
    //      v4 (rejects placeholder / non-UUID values that might have been
    //      set incorrectly by a bug or data migration)
    //   4. linkedUserId != currentUserId — exclude the current user (you
    //      can't "think of" yourself)
    final currentUserId = ref.read(currentUserProvider)?.id;

    final members = detail.members
        .where((p) =>
            p.deletedAt == null &&
            p.isLinkedToKinrelUser &&
            _isValidUuid(p.linkedUserId) &&
            p.linkedUserId != currentUserId)
        .take(10)
        .toList();

    if (members.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 16, bottom: 8),
          child: Text(
            'Who are you thinking of?',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: KinrelColors.textDim,
            ),
          ),
        ),
        SizedBox(
          height: 84,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: members.length,
            separatorBuilder: (_, __) => const SizedBox(width: 14),
            itemBuilder: (context, index) {
              final member = members[index];
              final userId = member.linkedUserId ?? '';
              final tapped = _isTapped(userId);
              final onCooldown = _cooldown.contains(userId);

              return GestureDetector(
                onTap: () => _onTap(context, member),
                child: AnimatedScale(
                  scale: tapped ? 1.12 : 1.0,
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutBack,
                  child: Column(
                    children: [
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              boxShadow: tapped
                                  ? [
                                      BoxShadow(
                                        color: KinrelColors.orange
                                            .withValues(alpha: 0.5),
                                        blurRadius: 12,
                                        spreadRadius: 2,
                                      ),
                                    ]
                                  : [],
                              border: Border.all(
                                color: tapped
                                    ? KinrelColors.orange
                                    : onCooldown
                                        ? Colors.white24
                                        : Colors.white12,
                                width: tapped ? 2 : 1.5,
                              ),
                            ),
                            child: ClipOval(
                              child: ColorFiltered(
                                colorFilter: onCooldown
                                    ? const ColorFilter.mode(
                                        Colors.grey, BlendMode.saturation)
                                    : const ColorFilter.mode(
                                        Colors.transparent,
                                        BlendMode.saturation),
                                child: member.photoUrl != null &&
                                        member.photoUrl!.isNotEmpty
                                    ? Image.network(
                                        member.photoUrl!,
                                        width: 52,
                                        height: 52,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) =>
                                            _Placeholder(name: member.name),
                                      )
                                    : _Placeholder(name: member.name),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      SizedBox(
                        width: 56,
                        child: Text(
                          member.name.split(' ').first,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10,
                            color: KinrelColors.textDim,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _Placeholder extends StatelessWidget {
  final String name;
  const _Placeholder({required this.name});

  @override
  Widget build(BuildContext context) {
    final initial =
        name.isNotEmpty ? name[0].toUpperCase() : '?';
    return Container(
      color: KinrelColors.darkElevated,
      alignment: Alignment.center,
      child: Text(
        initial,
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: KinrelColors.orange,
        ),
      ),
    );
  }
}
