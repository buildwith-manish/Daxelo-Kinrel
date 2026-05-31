// lib/features/profile/presentation/delete_account_screen.dart
//
// DAXELO KINREL — Delete Account Screen
//
// Full-screen deletion flow with two stages:
//   Screen 1: Explains what gets deleted with warnings
//   Screen 2: "DELETE" confirmation + password + 30-second countdown
//
// On success: clears all local storage and navigates to /sign-in.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
// Hive removed — using shared_preferences for local settings
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/brand_typography.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/utils/api_error_mapper.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/storage/secure_storage.dart';
import '../../../core/database/isar_database.dart';
import '../data/profile_provider.dart';

// ── Design Tokens ──────────────────────────────────────────────────
const Color _bg = Color(0xFF131416);
const Color _cardBg = Color(0xFF191B2C);
const Color _orange = Color(0xFFE8612A);
const Color _textPrimary = Color(0xFFF5F0EE);
const Color _textSecondary = Color(0xFFC9B4A8);
const Color _textDim = Color(0xFF8A7A72);
const Color _borderSubtle = Color(0x0FFFFFFF);
const Color _dangerRed = Color(0xFFFF4444);
const Color _dangerRedDark = Color(0xFFCC0000);

class DeleteAccountScreen extends ConsumerStatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  ConsumerState<DeleteAccountScreen> createState() =>
      _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends ConsumerState<DeleteAccountScreen> {
  int _currentScreen = 1;
  final _deleteTextController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isDeleting = false;
  int _countdownSeconds = 30;
  Timer? _countdownTimer;
  bool _countdownComplete = false;
  bool _obscurePassword = true;

  // Families where user is sole admin (loaded from profile state)
  List<FamilyTreeNode> _soleAdminFamilies = [];

  @override
  void initState() {
    super.initState();
    _loadSoleAdminFamilies();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _deleteTextController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loadSoleAdminFamilies() async {
    await ref.read(profileProvider.notifier).loadFamilies();
    if (!mounted) return;
    final families = ref.read(profileProvider).families;
    setState(() {
      _soleAdminFamilies = families
          .where((f) => f.role == 'admin' || f.role == 'owner')
          .toList();
    });
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    setState(() {
      _countdownSeconds = 30;
      _countdownComplete = false;
    });

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _countdownSeconds--;
      });

      if (_countdownSeconds <= 0) {
        timer.cancel();
        setState(() {
          _countdownComplete = true;
        });
      }
    });
  }

  void _goToScreen2() {
    setState(() => _currentScreen = 2);
    _startCountdown();
  }

  void _goBack() {
    if (_currentScreen == 2) {
      _countdownTimer?.cancel();
      setState(() {
        _currentScreen = 1;
        _countdownComplete = false;
        _deleteTextController.clear();
        _passwordController.clear();
      });
    } else {
      context.pop();
    }
  }

  bool get _deleteButtonEnabled {
    return _deleteTextController.text == 'DELETE' &&
        _passwordController.text.isNotEmpty &&
        _countdownComplete &&
        !_isDeleting;
  }

  Future<void> _deleteAccount() async {
    setState(() => _isDeleting = true);

    final success = await ref
        .read(profileProvider.notifier)
        .deleteAccount(_passwordController.text);

    if (!mounted) return;

    if (success) {
      // Clear all local storage
      await _clearAllLocalStorage();

      // Navigate to sign-in, clearing the entire navigation stack
      if (mounted) {
        context.go('/sign-in');
      }
    } else {
      final error = ref.read(profileProvider).error ?? 'Failed to delete account';
      final fieldErrors = mapApiError(error);
      if (fieldErrors != null) {
        final formError = fieldErrors['form'] ?? fieldErrors.values.first;
        context.showSnackBar(formError, isError: true);
      } else {
        context.showSnackBar(error, isError: true);
      }
      setState(() => _isDeleting = false);
    }
  }

  Future<void> _clearAllLocalStorage() async {
    try {
      // Clear SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
    } catch (_) {}

    try {
      // Clear Drift database cache
      await IsarDatabase.clearAll();
    } catch (_) {}

    try {
      // Clear secure storage auth tokens
      await SecureStorageService().clearAuthTokens();
    } catch (_) {}

    try {
      // Clear persisted route
      await clearLastRoute();
    } catch (_) {}

    try {
      // Sign out from Supabase
      final authService = ref.read(authServiceProvider);
      await authService.signOut();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: _textPrimary),
          onPressed: _goBack,
        ),
        title: Text(
          _currentScreen == 1 ? 'Delete Account' : 'Confirm Deletion',
          style: const TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: _textPrimary,
          ),
        ),
      ),
      body: _currentScreen == 1 ? _buildScreen1() : _buildScreen2(),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // SCREEN 1: What gets deleted
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildScreen1() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Warning Banner ────────────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _dangerRed.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _dangerRed.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _dangerRed.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.warning_amber_rounded,
                    color: _dangerRed,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'This cannot be undone',
                    style: TextStyle(
                      fontFamily: KinrelTypography.displayFont,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: _dangerRed,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // ── What Gets Deleted ─────────────────────────────────────
          const Text(
            'What will be deleted',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: _orange,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 12),

          _DeletionItem(
            icon: Icons.person_outline,
            title: 'Your profile info',
            subtitle: 'Name, email, phone, avatar, and bio',
          ),
          _DeletionItem(
            icon: Icons.account_tree_outlined,
            title: 'Family trees where you\'re the sole admin',
            subtitle: 'These trees will be permanently removed',
            isWarning: true,
          ),
          _DeletionItem(
            icon: Icons.link_outlined,
            title: 'All relationships you\'ve created',
            subtitle: 'Connections between family members',
          ),
          _DeletionItem(
            icon: Icons.history_outlined,
            title: 'Activity history',
            subtitle: 'All your past activity and interactions',
          ),

          const SizedBox(height: 20),

          // ── Sole Admin Families ────────────────────────────────────
          if (_soleAdminFamilies.isNotEmpty) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _dangerRed.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _dangerRed.withValues(alpha: 0.15)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        color: _dangerRed,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'You are the sole admin of ${_soleAdminFamilies.length} ${_soleAdminFamilies.length == 1 ? 'family' : 'families'}',
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _dangerRed,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ...(_soleAdminFamilies.map(
                    (family) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Icon(
                            Icons.park_outlined,
                            color: _dangerRed.withValues(alpha: 0.7),
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${family.name} (${family.memberCount} members)',
                              style: const TextStyle(
                                fontFamily: KinrelTypography.bodyFont,
                                fontSize: 13,
                                color: _textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )),
                  const SizedBox(height: 4),
                  Text(
                    'These families will be permanently deleted if you proceed.',
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 12,
                      color: _dangerRed.withValues(alpha: 0.8),
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],

          // ── Continue Button ────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            height: 52,
            child: OutlinedButton(
              onPressed: _goToScreen2,
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: _dangerRed, width: 1.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                backgroundColor: _dangerRed.withValues(alpha: 0.06),
              ),
              child: const Text(
                'Continue',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: _dangerRed,
                ),
              ),
            ),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // SCREEN 2: Confirm deletion
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildScreen2() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Final Warning ─────────────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _dangerRed.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _dangerRed.withValues(alpha: 0.2)),
            ),
            child: Column(
              children: [
                const Icon(
                  Icons.dangerous_outlined,
                  color: _dangerRed,
                  size: 36,
                ),
                const SizedBox(height: 12),
                const Text(
                  'You are about to permanently delete your account',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _dangerRed,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // ── Type DELETE ───────────────────────────────────────────
          const Text(
            'Type DELETE to confirm',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: _orange,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 10),

          TextField(
            controller: _deleteTextController,
            onChanged: (_) => setState(() {}),
            textInputAction: TextInputAction.next,
            textCapitalization: TextCapitalization.characters,
            style: TextStyle(
              fontFamily: KinrelTypography.monoFont,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: _deleteTextController.text == 'DELETE'
                  ? _dangerRed
                  : _textPrimary,
              letterSpacing: 2,
            ),
            decoration: InputDecoration(
              hintText: 'DELETE',
              hintStyle: TextStyle(
                fontFamily: KinrelTypography.monoFont,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: _textDim.withValues(alpha: 0.4),
                letterSpacing: 2,
              ),
              filled: true,
              fillColor: _cardBg,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                  color: _deleteTextController.text == 'DELETE'
                      ? _dangerRed
                      : _orange,
                  width: 1.5,
                ),
              ),
            ),
          ),

          const SizedBox(height: 20),

          // ── Password Field ────────────────────────────────────────
          const Text(
            'Enter your password',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: _orange,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 10),

          TextField(
            controller: _passwordController,
            onChanged: (_) => setState(() {}),
            obscureText: _obscurePassword,
            textInputAction: TextInputAction.done,
            textCapitalization: TextCapitalization.none,
            style: const TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 15,
              color: _textPrimary,
            ),
            decoration: InputDecoration(
              hintText: 'Your current password',
              hintStyle: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 15,
                color: _textDim.withValues(alpha: 0.5),
              ),
              filled: true,
              fillColor: _cardBg,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: _orange, width: 1.5),
              ),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  color: _textDim,
                  size: 20,
                ),
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
              ),
            ),
          ),

          const SizedBox(height: 24),

          // ── Countdown Timer ───────────────────────────────────────
          if (!_countdownComplete)
            Center(
              child: Column(
                children: [
                  SizedBox(
                    width: 56,
                    height: 56,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        CircularProgressIndicator(
                          value: _countdownSeconds / 30,
                          strokeWidth: 3,
                          backgroundColor: _cardBg,
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            _dangerRed,
                          ),
                        ),
                        Text(
                          '${_countdownSeconds}s',
                          style: const TextStyle(
                            fontFamily: KinrelTypography.monoFont,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: _dangerRed,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Please wait before deleting',
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 12,
                      color: _textDim,
                    ),
                  ),
                ],
              ),
            ),

          if (_countdownComplete)
            Center(
              child: Column(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _dangerRed.withValues(alpha: 0.12),
                    ),
                    child: const Icon(
                      Icons.warning_rounded,
                      color: _dangerRed,
                      size: 28,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Deletion is now available',
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 12,
                      color: _textDim,
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 28),

          // ── Delete Button ─────────────────────────────────────────
          Container(
            width: double.infinity,
            height: 52,
            decoration: BoxDecoration(
              gradient: _deleteButtonEnabled
                  ? const LinearGradient(
                      colors: [_dangerRed, _dangerRedDark],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                  : null,
              borderRadius: BorderRadius.circular(12),
              color: _deleteButtonEnabled ? null : _cardBg,
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _deleteButtonEnabled ? _deleteAccount : null,
                borderRadius: BorderRadius.circular(12),
                child: Center(
                  child: _isDeleting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        )
                      : Text(
                          _countdownComplete
                              ? 'Delete My Account'
                              : 'Wait ${_countdownSeconds}s...',
                          style: TextStyle(
                            fontFamily: KinrelTypography.bodyFont,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: _deleteButtonEnabled
                                ? Colors.white
                                : _textDim,
                            letterSpacing: 0.3,
                          ),
                        ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // ── Cancel ────────────────────────────────────────────────
          Center(
            child: TextButton(
              onPressed: _isDeleting ? null : _goBack,
              child: const Text(
                'Cancel and go back',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 14,
                  color: _textDim,
                ),
              ),
            ),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Deletion Item
// ═══════════════════════════════════════════════════════════════════════

class _DeletionItem extends StatelessWidget {
  const _DeletionItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.isWarning = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool isWarning;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _cardBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isWarning
                ? _dangerRed.withValues(alpha: 0.2)
                : _borderSubtle,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: isWarning
                    ? _dangerRed.withValues(alpha: 0.12)
                    : _orange.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                icon,
                color: isWarning ? _dangerRed : _orange,
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isWarning ? _dangerRed : _textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 12,
                      color: _textDim,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.delete_outline,
              color: isWarning ? _dangerRed.withValues(alpha: 0.5) : _textDim,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}
