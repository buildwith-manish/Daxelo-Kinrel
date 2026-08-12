// lib/features/family/presentation/create_group_screen.dart
//
// DAXELO KINREL — Create Group Flow (v138 Phase 2)
//
// 5-step flow for creating a sub-group within a Family Space:
//   1. Choose group type (cousins, parents, siblings, event, travel, custom)
//   2. Enter group name
//   3. Add description (optional)
//   4. Select members from family
//   5. Review + create
//
// Groups are always created within a Family Space — never standalone.
// This preserves Kinrel's family-first identity.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Family;
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/family/family_provider.dart';
import '../../../shared/widgets/dk_components.dart';
import '../data/group_provider.dart';

class CreateGroupScreen extends ConsumerStatefulWidget {
  const CreateGroupScreen({super.key, required this.familyId});

  final String familyId;

  @override
  ConsumerState<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends ConsumerState<CreateGroupScreen> {
  int _currentStep = 0;
  GroupType _selectedType = GroupType.custom;
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final Set<String> _selectedMemberIds = {};
  bool _isCreating = false;

  static const _steps = ['Type', 'Name', 'Description', 'Members', 'Create'];

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  bool get _canProceed {
    switch (_currentStep) {
      case 0: return true; // type is always selected
      case 1: return _nameController.text.trim().isNotEmpty;
      case 2: return true; // description optional
      case 3: return _selectedMemberIds.isNotEmpty;
      case 4: return true;
      default: return false;
    }
  }

  Future<void> _createGroup() async {
    setState(() => _isCreating = true);

    final membershipsAsync =
        ref.read(familyMembershipsProvider(widget.familyId));
    final memberships = membershipsAsync.valueOrNull ?? [];

    final selectedMembers = memberships
        .where((m) => _selectedMemberIds.contains(m.userId))
        .map((m) => (
              userId: m.userId,
              displayName: m.user?.displayName ?? 'Member',
              isGuest: false,
            ))
        .toList();

    final groupId = await createGroup(
      ref: ref,
      familyId: widget.familyId,
      name: _nameController.text.trim(),
      description: _descriptionController.text.trim().isEmpty
          ? null
          : _descriptionController.text.trim(),
      groupType: _selectedType,
      members: selectedMembers,
    );

    if (!mounted) return;
    setState(() => _isCreating = false);

    if (groupId != null) {
      // Navigate to the new group's hub
      context.go('/family/${widget.familyId}/groups/$groupId/hub');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not create group. Please try again.'),
          backgroundColor: KinrelColors.darkCard,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return DKScaffold(
      backgroundColor: const Color(0xFF0A0B16),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new,
              size: 18, color: KinrelColors.textSilver),
          onPressed: () {
            if (_currentStep > 0) {
              setState(() => _currentStep--);
            } else {
              context.pop();
            }
          },
        ),
        title: Text(
          'Create Group',
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: KinrelColors.textWhite,
            letterSpacing: 0.3,
          ),
        ),
      ),
      body: Column(
        children: [
          // Progress indicator
          _StepProgress(currentStep: _currentStep),
          // Step content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: _buildStepContent(),
            ),
          ),
          // Bottom nav
          _buildBottomNav(),
        ],
      ),
    );
  }

  Widget _buildStepContent() {
    switch (_currentStep) {
      case 0: return _buildTypeStep();
      case 1: return _buildNameStep();
      case 2: return _buildDescriptionStep();
      case 3: return _buildMembersStep();
      case 4: return _buildReviewStep();
      default: return const SizedBox.shrink();
    }
  }

  // ── Step 0: Type ────────────────────────────────────────────────────

  Widget _buildTypeStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'What type of group?',
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: KinrelColors.textWhite,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Choose a category that fits this group',
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 13,
            color: KinrelColors.textSilver.withValues(alpha: 0.70),
          ),
        ),
        const SizedBox(height: 24),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.4,
          ),
          itemCount: GroupType.values.length,
          itemBuilder: (ctx, i) {
            final type = GroupType.values[i];
            final isSelected = type == _selectedType;
            return GestureDetector(
              onTap: () => setState(() => _selectedType = type),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  color: isSelected
                      ? type.color.withValues(alpha: 0.12)
                      : const Color(0xFF11132A).withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isSelected
                        ? type.color.withValues(alpha: 0.50)
                        : Colors.white.withValues(alpha: 0.06),
                    width: isSelected ? 1.5 : 0.75,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      type.icon,
                      size: 28,
                      color: isSelected
                          ? type.color
                          : KinrelColors.textSilver,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      type.label,
                      style: TextStyle(
                        fontFamily: KinrelTypography.displayFont,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: isSelected
                            ? KinrelColors.textWhite
                            : KinrelColors.textSilver,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  // ── Step 1: Name ────────────────────────────────────────────────────

  Widget _buildNameStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Name your group',
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: KinrelColors.textWhite,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'e.g. ${_selectedType.label} Chat, Family Trip 2026, Wedding Planning',
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 13,
            color: KinrelColors.textSilver.withValues(alpha: 0.70),
          ),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _nameController,
          autofocus: true,
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 16,
            color: KinrelColors.textWhite,
          ),
          decoration: InputDecoration(
            hintText: 'Group name',
            hintStyle: TextStyle(
              color: KinrelColors.textDim.withValues(alpha: 0.70),
            ),
            filled: true,
            fillColor: const Color(0xFF1A1D2E),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(
                  color: KinrelColors.ember.withValues(alpha: 0.35)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(
                  color: Colors.white.withValues(alpha: 0.08)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(
                  color: KinrelColors.ember.withValues(alpha: 0.50),
                  width: 1.5),
            ),
          ),
          onChanged: (_) => setState(() {}),
        ),
      ],
    );
  }

  // ── Step 2: Description ─────────────────────────────────────────────

  Widget _buildDescriptionStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Add a description',
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: KinrelColors.textWhite,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Optional — helps members understand the group\'s purpose',
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 13,
            color: KinrelColors.textSilver.withValues(alpha: 0.70),
          ),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _descriptionController,
          maxLines: 4,
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 15,
            color: KinrelColors.textWhite,
            height: 1.5,
          ),
          decoration: InputDecoration(
            hintText: 'What is this group about?',
            hintStyle: TextStyle(
              color: KinrelColors.textDim.withValues(alpha: 0.70),
            ),
            filled: true,
            fillColor: const Color(0xFF1A1D2E),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(
                  color: Colors.white.withValues(alpha: 0.08)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(
                  color: Colors.white.withValues(alpha: 0.08)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(
                  color: KinrelColors.ember.withValues(alpha: 0.50),
                  width: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  // ── Step 3: Members ─────────────────────────────────────────────────

  Widget _buildMembersStep() {
    final membershipsAsync =
        ref.watch(familyMembershipsProvider(widget.familyId));
    final currentUserId =
        ref.read(supabaseProvider)?.auth.currentUser?.id;

    return membershipsAsync.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: KinrelColors.orange),
      ),
      error: (_, __) => Center(
        child: Text('Could not load members',
            style: TextStyle(color: KinrelColors.textDim)),
      ),
      data: (memberships) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Select members',
              style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: KinrelColors.textWhite,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${_selectedMemberIds.length} selected',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 13,
                color: KinrelColors.ember,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 20),
            // Current user is auto-included as admin
            if (currentUserId != null)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: KinrelColors.ember.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: KinrelColors.ember.withValues(alpha: 0.25),
                    width: 0.75,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.admin_panel_settings_rounded,
                        size: 18, color: KinrelColors.ember),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'You (Admin)',
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: KinrelColors.textWhite,
                        ),
                      ),
                    ),
                    Icon(Icons.check_circle_rounded,
                        size: 18, color: KinrelColors.ember),
                  ],
                ),
              ),
            // Member list
            ...memberships.where((m) => m.userId != currentUserId).map((m) {
              final isSelected = _selectedMemberIds.contains(m.userId);
              final name = m.user?.displayName ?? 'Member';
              final initials = m.user?.initials ?? '?';
              final avatarUrl = m.user?.avatarUrl;

              return GestureDetector(
                onTap: () {
                  setState(() {
                    if (isSelected) {
                      _selectedMemberIds.remove(m.userId);
                    } else {
                      _selectedMemberIds.add(m.userId);
                    }
                  });
                },
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? KinrelColors.ember.withValues(alpha: 0.06)
                        : const Color(0xFF11132A).withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isSelected
                          ? KinrelColors.ember.withValues(alpha: 0.30)
                          : Colors.white.withValues(alpha: 0.05),
                      width: 0.75,
                    ),
                  ),
                  child: Row(
                    children: [
                      // Avatar
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: KinrelColors.ember.withValues(alpha: 0.12),
                        ),
                        child: Center(
                          child: Text(
                            initials,
                            style: TextStyle(
                              fontFamily: KinrelTypography.displayFont,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: KinrelColors.ember,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          name,
                          style: TextStyle(
                            fontFamily: KinrelTypography.bodyFont,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: KinrelColors.textWhite,
                          ),
                        ),
                      ),
                      // Checkbox
                      Icon(
                        isSelected
                            ? Icons.check_circle_rounded
                            : Icons.circle_outlined,
                        size: 22,
                        color: isSelected
                            ? KinrelColors.ember
                            : KinrelColors.textDim,
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
        );
      },
    );
  }

  // ── Step 4: Review + Create ─────────────────────────────────────────

  Widget _buildReviewStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Review & create',
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: KinrelColors.textWhite,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 20),
        // Preview card
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFF1A1D2E),
                const Color(0xFF14162A),
              ],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.06),
              width: 0.75,
            ),
          ),
          child: Column(
            children: [
              // Group icon
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _selectedType.color.withValues(alpha: 0.15),
                  border: Border.all(
                    color: _selectedType.color.withValues(alpha: 0.45),
                    width: 1.5,
                  ),
                ),
                child: Icon(
                  _selectedType.icon,
                  size: 28,
                  color: _selectedType.color,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                _nameController.text.trim().isEmpty
                    ? 'Group Name'
                    : _nameController.text.trim(),
                style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: KinrelColors.textWhite,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _selectedType.label,
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _selectedType.color,
                  letterSpacing: 0.3,
                ),
              ),
              if (_descriptionController.text.trim().isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  _descriptionController.text.trim(),
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 12.5,
                    color: KinrelColors.textSilver.withValues(alpha: 0.75),
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.people_outline_rounded,
                      size: 14, color: KinrelColors.textDim),
                  const SizedBox(width: 5),
                  Text(
                    '${_selectedMemberIds.length + 1} members', // +1 for creator
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 12,
                      color: KinrelColors.textDim,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Bottom navigation ───────────────────────────────────────────────

  Widget _buildBottomNav() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0B16),
        border: Border(
          top: BorderSide(
              color: Colors.white.withValues(alpha: 0.06), width: 0.5),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            if (_currentStep > 0)
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _currentStep--),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      'Back',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: KinrelTypography.displayFont,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: KinrelColors.textSilver,
                      ),
                    ),
                  ),
                ),
              ),
            if (_currentStep > 0) const SizedBox(width: 12),
            Expanded(
              child: GestureDetector(
                onTap: _canProceed && !_isCreating
                    ? () {
                        if (_currentStep < 4) {
                          setState(() => _currentStep++);
                        } else {
                          _createGroup();
                        }
                      }
                    : null,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    gradient: _canProceed && !_isCreating
                        ? KinrelGradients.igniteGradient
                        : null,
                    color: !_canProceed || _isCreating
                        ? Colors.white.withValues(alpha: 0.04)
                        : null,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: _canProceed && !_isCreating
                        ? [
                            BoxShadow(
                              color: KinrelColors.ember
                                  .withValues(alpha: 0.30),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ]
                        : null,
                  ),
                  child: _isCreating
                      ? const SizedBox(
                          height: 20,
                          child: Center(
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        )
                      : Text(
                          _currentStep < 4 ? 'Continue' : 'Create Group',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: KinrelTypography.displayFont,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: _canProceed
                                ? Colors.white
                                : KinrelColors.textDim,
                            letterSpacing: 0.3,
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Step Progress Indicator ──────────────────────────────────────────

class _StepProgress extends StatelessWidget {
  const _StepProgress({required this.currentStep});

  final int currentStep;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      child: Row(
        children: List.generate(5, (i) {
          final isActive = i <= currentStep;
          final isCurrent = i == currentStep;
          return Expanded(
            child: Container(
              margin: EdgeInsets.only(right: i < 4 ? 6 : 0),
              child: Column(
                children: [
                  // Progress bar
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    height: 3,
                    decoration: BoxDecoration(
                      color: isActive
                          ? KinrelColors.ember
                          : Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(100),
                      boxShadow: isCurrent
                          ? [
                              BoxShadow(
                                color: KinrelColors.ember
                                    .withValues(alpha: 0.40),
                                blurRadius: 6,
                              ),
                            ]
                          : null,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _steps[i],
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 9.5,
                      fontWeight:
                          isCurrent ? FontWeight.w600 : FontWeight.w500,
                      color: isActive
                          ? KinrelColors.textSilver.withValues(alpha: 0.85)
                          : KinrelColors.textDim,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}
