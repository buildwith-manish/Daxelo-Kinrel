// lib/features/games/carrom/carrom_lobby_screen.dart
//
// Carrom — Lobby screen to pick an opponent from family members.
// Route: /family/$familyId/carrom/lobby

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/services/supabase_service.dart';
import '../../../shared/widgets/dk_components.dart';
import '../game_motion_tokens.dart';
import 'carrom_provider.dart';

class CarromLobbyScreen extends ConsumerStatefulWidget {
  const CarromLobbyScreen({super.key, required this.familyId});
  final String familyId;

  @override
  ConsumerState<CarromLobbyScreen> createState() => _CarromLobbyScreenState();
}

class _CarromLobbyScreenState extends ConsumerState<CarromLobbyScreen> {
  List<Map<String, dynamic>> _familyMembers = [];
  bool _loading = true;
  String? _error;
  String? _selectedOpponentId;
  String _selectedOpponentName = '';
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    _loadFamilyMembers();
  }

  Future<void> _loadFamilyMembers() async {
    final client = ref.read(supabaseProvider);
    final myId = client?.auth.currentUser?.id;
    if (client == null || myId == null) {
      setState(() {
        _loading = false;
        _error = 'Not signed in';
      });
      return;
    }
    try {
      final resp = await client
          .from('FamilyMember')
          .select('userId, user:User(name)')
          .eq('familyId', widget.familyId)
          .neq('userId', myId);
      final members = resp.map((r) {
        final user = r['user'] as Map<String, dynamic>?;
        return {
          'userId': r['userId'] as String,
          'name': (user?['name'] as String?) ?? 'Family Member',
        };
      }).toList();
      setState(() {
        _familyMembers = members;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  Future<void> _createGame() async {
    if (_selectedOpponentId == null) return;
    setState(() => _creating = true);
    final notifier = ref.read(carromProvider(widget.familyId).notifier);
    final gameId = await notifier.createGame(
      opponentId: _selectedOpponentId!,
      opponentName: _selectedOpponentName,
    );
    if (mounted) {
      setState(() => _creating = false);
      if (gameId != null) {
        context.pushReplacement(
          '/family/${widget.familyId}/carrom/board/$gameId',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DKScaffold(
      backgroundColor: KinrelColors.darkSurface,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Carrom',
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontWeight: FontWeight.w600,
            color: KinrelColors.textWhite,
          ),
        ),
        backgroundColor: KinrelColors.darkCard,
        foregroundColor: KinrelColors.textWhite,
        elevation: 0,
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: KinrelColors.orange),
            )
          : _error != null
          ? DKErrorState(message: _error!, onRetry: _loadFamilyMembers)
          : _familyMembers.isEmpty
          ? DKEmptyState(
              icon: Icons.group_outlined,
              title: 'No family members to challenge',
              subtitle:
                  'Invite family members to your family first, then come back to play Carrom.',
            )
          : ListView(
              padding: const EdgeInsets.all(KinrelSpacing.base),
              children: [
                Text(
                  'Challenge a Family Member',
                  style: TextStyle(
                    fontFamily: KinrelTypography.displayFont,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: KinrelColors.textWhite,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'You\'ll play as White (moves first). Your opponent plays as Black.',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 12,
                    color: KinrelColors.textDim,
                  ),
                ),
                const SizedBox(height: KinrelSpacing.lg),
                _rulesCard(),
                const SizedBox(height: KinrelSpacing.lg),
                Text(
                  'SELECT OPPONENT',
                  style: TextStyle(
                    fontFamily: KinrelTypography.monoFont,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: KinrelColors.textDim,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: KinrelSpacing.sm),
                ..._familyMembers.map((m) {
                  final isSelected = _selectedOpponentId == m['userId'];
                  return GestureDetector(
                    onTap: () {
                      GameMotionTokens.tap();
                      setState(() {
                        _selectedOpponentId = m['userId'] as String;
                        _selectedOpponentName = m['name'] as String;
                      });
                    },
                    child: Container(
                      margin: const EdgeInsets.only(bottom: KinrelSpacing.sm),
                      padding: const EdgeInsets.symmetric(
                        horizontal: KinrelSpacing.md,
                        vertical: KinrelSpacing.md,
                      ),
                      decoration: BoxDecoration(
                        color: KinrelColors.darkCard,
                        borderRadius: BorderRadius.circular(KinrelRadius.lg),
                        border: Border.all(
                          color: isSelected
                              ? KinrelColors.orange
                              : KinrelColors.border,
                          width: isSelected ? 2 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          DKAvatar(
                            initials: (m['name'] as String).isNotEmpty
                                ? (m['name'] as String)[0].toUpperCase()
                                : '?',
                            borderColor: isSelected
                                ? KinrelColors.orange
                                : null,
                          ),
                          const SizedBox(width: KinrelSpacing.md),
                          Expanded(
                            child: Text(
                              m['name'] as String,
                              style: TextStyle(
                                fontFamily: KinrelTypography.bodyFont,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: isSelected
                                    ? KinrelColors.textWhite
                                    : KinrelColors.textDim,
                              ),
                            ),
                          ),
                          if (isSelected)
                            Icon(
                              Icons.check_circle,
                              color: KinrelColors.orange,
                              size: 20,
                            ),
                        ],
                      ),
                    ),
                  );
                }),
                const SizedBox(height: KinrelSpacing.xl),
                DKButton(
                  label: _selectedOpponentId == null
                      ? 'Select an opponent'
                      : 'Challenge $_selectedOpponentName',
                  variant: DKButtonVariant.gradient,
                  fullWidth: true,
                  isLoading: _creating,
                  onPressed:
                      _selectedOpponentId == null ? null : _createGame,
                ),
              ],
            ),
    );
  }

  Widget _rulesCard() {
    return Container(
      padding: const EdgeInsets.all(KinrelSpacing.md),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(KinrelRadius.lg),
        border: Border.all(color: KinrelColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, color: KinrelColors.info, size: 18),
              const SizedBox(width: KinrelSpacing.sm),
              Text(
                'How to Play',
                style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: KinrelColors.textWhite,
                ),
              ),
            ],
          ),
          const SizedBox(height: KinrelSpacing.sm),
          _ruleLine('• Drag from the striker to aim, release to flick'),
          const SizedBox(height: 4),
          _ruleLine('• Pot your own color coins to score + get extra turn'),
          const SizedBox(height: 4),
          _ruleLine('• Potting opponent\'s color passes your turn'),
          const SizedBox(height: 4),
          _ruleLine('• Pot the queen + cover with your color in same/next turn'),
          const SizedBox(height: 4),
          _ruleLine('• Don\'t pot the striker — it\'s a foul!'),
          const SizedBox(height: 4),
          _ruleLine('• First to pot all coins (+ covered queen) wins'),
        ],
      ),
    );
  }

  Widget _ruleLine(String text) {
    return Text(
      text,
      style: TextStyle(
        fontFamily: KinrelTypography.bodyFont,
        fontSize: 12,
        color: KinrelColors.textDim,
        height: 1.4,
      ),
    );
  }
}
