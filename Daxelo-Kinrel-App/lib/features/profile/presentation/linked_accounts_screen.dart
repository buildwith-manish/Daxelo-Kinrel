// lib/features/profile/presentation/linked_accounts_screen.dart
//
// DAXELO KINREL — Linked Accounts Screen
//
// Shows connected auth providers (Google) with
// link/unlink actions and appropriate safeguards.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/services/supabase_service.dart';
import '../../../shared/widgets/dk_components.dart';
import '../data/profile_provider.dart';

// ── Design Tokens ──────────────────────────────────────────────────
const Color _bg = Color(0xFF131416);
const Color _cardBg = Color(0xFF191B2C);
const Color _orange = Color(0xFFE8612A);
const Color _textPrimary = Color(0xFFF5F0EE);
const Color _textSecondary = Color(0xFFC9B4A8);
const Color _textDim = Color(0xFF8A7A72);
const Color _borderSubtle = Color(0x0FFFFFFF);

class LinkedAccountsScreen extends ConsumerStatefulWidget {
  const LinkedAccountsScreen({super.key});

  @override
  ConsumerState<LinkedAccountsScreen> createState() =>
      _LinkedAccountsScreenState();
}

class _LinkedAccountsScreenState extends ConsumerState<LinkedAccountsScreen> {
  bool _isUnlinking = false;
  bool _isGoogleLinked = false;

  @override
  void initState() {
    super.initState();
    // Check auth providers from Supabase
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAuthProviders();
    });
  }

  void _checkAuthProviders() {
    final client = ref.read(supabaseProvider);
    if (client != null) {
      final user = client.auth.currentUser;
      if (user != null) {
        final providers =
            user.appMetadata['providers'] as List? ?? [];
        setState(() {
          _isGoogleLinked = providers.contains('google');
        });
      }
    }
  }

  // ── Provider Definitions ───────────────────────────────────────

  /// Auth providers the user has linked.
  /// Derived from Supabase auth metadata + profile authProvider field.
  Set<String> get _linkedProviders {
    final authProvider =
        ref.read(profileProvider).profile?.authProvider ?? 'email';
    final linked = <String>{'email'}; // Email is always linked
    if (authProvider == 'google' || _isGoogleLinked) {
      linked.add('google');
    }
    return linked;
  }

  // ── Provider Info ──────────────────────────────────────────────

  static const _providerInfo = {
    'google': _ProviderInfo(
      name: 'Google',
      icon: Icons.g_mobiledata_rounded,
      iconColor: Color(0xFF4285F4),
      description: 'Sign in with your Google account',
    ),
  };

  // ── Build ──────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final linkedProviders = _linkedProviders;

    return DKScaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new,
            color: _textPrimary,
            size: 20,
          ),
          onPressed: () => context.pop(),
        ),
        title: const Text(
          'Linked Accounts',
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: _textPrimary,
          ),
        ),
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(
          horizontal: KinrelSpacing.base,
          vertical: KinrelSpacing.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header description ────────────────────────────────
            Text(
              'Manage your connected accounts for quick and secure sign-in.',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 14,
                color: _textSecondary,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 24),

            // ── Provider List ─────────────────────────────────────
            ..._providerInfo.entries.map((entry) {
              final providerKey = entry.key;
              final info = entry.value;
              final isLinked = linkedProviders.contains(providerKey);

              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _ProviderCard(
                  info: info,
                  isLinked: isLinked,
                  canUnlink: isLinked && linkedProviders.length > 1,
                  isUnlinking: _isUnlinking,
                  onLink: () => _handleLink(providerKey),
                  onUnlink: () => _handleUnlink(providerKey, info.name),
                ),
              );
            }),

            const SizedBox(height: 32),

            // ── Info section ──────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _cardBg,
                borderRadius: BorderRadius.circular(KinrelRadius.md),
                border: Border.all(color: _borderSubtle),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, color: _orange, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'You must have at least one linked account to sign in. '
                      'Unlinking an account will sign you out of that provider.',
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 13,
                        color: _textDim,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Link Handler ───────────────────────────────────────────────

  void _handleLink(String providerKey) {
    if (providerKey == 'google') {
      _linkGoogleAccount();
    }
  }

  Future<void> _linkGoogleAccount() async {
    setState(() => _isUnlinking = true);

    try {
      final authService = ref.read(authServiceProvider);
      await authService.linkGoogleAccount();

      if (!mounted) return;

      // Refresh provider check
      _checkAuthProviders();

      context.showSnackBar('Google account linked successfully');
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString();
      if (!msg.contains('cancelled')) {
        context.showSnackBar('Failed to link Google account. Please try again.', isError: true);
      }
    } finally {
      if (mounted) setState(() => _isUnlinking = false);
    }
  }



  // ── Unlink Handler ─────────────────────────────────────────────

  void _handleUnlink(String providerKey, String providerName) {
    final linkedProviders = _linkedProviders;

    // Cannot unlink if it's the only auth method
    if (linkedProviders.length <= 1) {
      context.showSnackBar(
        'Cannot unlink your only authentication method',
        isError: true,
      );
      return;
    }

    // Show confirmation dialog
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _cardBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KinrelRadius.dialog),
          side: const BorderSide(color: _borderSubtle),
        ),
        title: const Text(
          'Unlink Account',
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: _textPrimary,
          ),
        ),
        content: Text(
          'Are you sure you want to unlink $providerName? '
          'You will no longer be able to sign in with this provider.',
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 14,
            color: _textSecondary,
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(
              'Cancel',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                color: _textDim,
              ),
            ),
          ),
          DKButton(
            label: 'Unlink',
            variant: DKButtonVariant.primary,
            size: DKButtonSize.sm,
            onPressed: () async {
              Navigator.of(ctx).pop();
              await _performUnlink(providerKey);
            },
          ),
        ],
      ),
    );
  }

  Future<void> _performUnlink(String providerKey) async {
    setState(() => _isUnlinking = true);

    // Simplified: update auth provider back to 'email'
    final success = await ref.read(profileProvider.notifier).updateProfile({
      'authProvider': 'email',
    });

    if (!mounted) return;
    setState(() => _isUnlinking = false);

    if (success) {
      context.showSnackBar('Account unlinked successfully');
    } else {
      final error = ref.read(profileProvider).error;
      context.showSnackBar(error ?? 'Failed to unlink account', isError: true);
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Provider Info Model
// ═══════════════════════════════════════════════════════════════════════

class _ProviderInfo {
  const _ProviderInfo({
    required this.name,
    required this.icon,
    required this.iconColor,
    required this.description,
  });

  final String name;
  final IconData icon;
  final Color iconColor;
  final String description;
}

// ═══════════════════════════════════════════════════════════════════════
// Provider Card Widget
// ═══════════════════════════════════════════════════════════════════════

class _ProviderCard extends StatelessWidget {
  const _ProviderCard({
    required this.info,
    required this.isLinked,
    required this.canUnlink,
    required this.isUnlinking,
    required this.onLink,
    required this.onUnlink,
  });

  final _ProviderInfo info;
  final bool isLinked;
  final bool canUnlink;
  final bool isUnlinking;
  final VoidCallback onLink;
  final VoidCallback onUnlink;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(KinrelRadius.md),
        border: Border.all(color: _borderSubtle),
      ),
      child: Row(
        children: [
          // ── Provider Icon ──────────────────────────────────────
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: info.iconColor.withValues(alpha: 0.12),
              shape: BoxShape.circle,
              border: Border.all(
                color: info.iconColor.withValues(alpha: 0.2),
                width: 1,
              ),
            ),
            child: Center(
              child: Icon(info.icon, color: info.iconColor, size: 24),
            ),
          ),
          const SizedBox(width: 14),

          // ── Provider Info ──────────────────────────────────────
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      info.name,
                      style: const TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: _textPrimary,
                      ),
                    ),
                    if (isLinked) ...[
                      const SizedBox(width: 8),
                      Icon(
                        Icons.check_circle,
                        color: KinrelColors.success,
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Connected',
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: KinrelColors.success,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  isLinked ? info.description : 'Not linked yet',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 13,
                    color: isLinked ? _textDim : _textSecondary,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 8),

          // ── Action Button ──────────────────────────────────────
          if (isLinked) _buildUnlinkButton() else _buildLinkButton(),
        ],
      ),
    );
  }

  Widget _buildLinkButton() {
    return SizedBox(
      height: 36,
      child: OutlinedButton(
        onPressed: onLink,
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: _orange, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(KinrelRadius.sm),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14),
        ),
        child: const Text(
          'Link',
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: _orange,
          ),
        ),
      ),
    );
  }

  Widget _buildUnlinkButton() {
    if (isUnlinking) {
      return const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(KinrelColors.error),
        ),
      );
    }

    return SizedBox(
      height: 36,
      child: OutlinedButton(
        onPressed: canUnlink ? onUnlink : null,
        style: OutlinedButton.styleFrom(
          side: BorderSide(
            color: canUnlink
                ? KinrelColors.error.withValues(alpha: 0.6)
                : _textDim.withValues(alpha: 0.3),
            width: 1.5,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(KinrelRadius.sm),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14),
        ),
        child: Text(
          'Unlink',
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: canUnlink
                ? KinrelColors.error.withValues(alpha: 0.9)
                : _textDim.withValues(alpha: 0.4),
          ),
        ),
      ),
    );
  }
}
