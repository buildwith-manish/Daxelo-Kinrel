// lib/features/auth/presentation/create_username_screen.dart
//
// Shown immediately after successful sign-up (before /home).
// The user MUST choose a unique username before they can proceed.
// This username is their primary public identity on Kinrel and the
// main identifier used in Search.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/services/supabase_service.dart';
import '../../username/providers/username_provider.dart';

class CreateUsernameScreen extends ConsumerStatefulWidget {
  const CreateUsernameScreen({super.key});

  @override
  ConsumerState<CreateUsernameScreen> createState() =>
      _CreateUsernameScreenState();
}

class _CreateUsernameScreenState extends ConsumerState<CreateUsernameScreen> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _focusNode.requestFocus();
    _controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onChanged() {
    final value = _controller.text.toLowerCase();
    // Reset state when typing
    ref.read(usernameProvider.notifier).reset();

    // The provider already has its own 300ms debounce, so we call
    // checkAvailability directly — no double debounce.
    if (value.isNotEmpty) {
      ref.read(usernameProvider.notifier).checkAvailability(value);
    }
  }

  bool get _isValid =>
      UsernameValidator.validate(_controller.text) == null;

  // Note: availability == UsernameAvailability.available is evaluated in build() via ref.watch, NOT here
  // via ref.read. Using ref.read here would return a stale value because
  // the getter is evaluated on the State object, not during build.
  // The build() method passes the watched availability to _canSubmitAt().

  bool _canSubmitAt(UsernameAvailability availability) =>
      _isValid &&
      availability == UsernameAvailability.available &&
      !_isSaving;

  Future<void> _submit() async {
    // Check availability at call time via ref.read (fresh read)
    final currentAvailability = ref.read(usernameProvider).availability;
    if (!_isValid || currentAvailability != UsernameAvailability.available || _isSaving) {
      return;
    }

    setState(() => _isSaving = true);

    try {
      final client = ref.read(supabaseProvider);
      if (client == null || client.auth.currentUser == null) {
        throw Exception('Not signed in');
      }

      final username = _controller.text.trim().toLowerCase();
      final userId = client.auth.currentUser!.id;

      // Update the User table with the chosen username
      await client.from('User').update({
        'username': username,
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', userId);

      // Also update auth user metadata for redundancy
      await client.auth.updateUser(
        UserAttributes(data: {'username': username}),
      );

      if (!mounted) return;

      // Navigate to home
      context.go('/home');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save username: $e'),
            backgroundColor: KinrelColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final usernameState = ref.watch(usernameProvider);
    final availability = usernameState.availability;

    return Scaffold(
      backgroundColor: KinrelColors.darkBackground,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Text(
          'Choose Your Username',
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: KinrelColors.textWhite,
          ),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Hero icon ──
              const SizedBox(height: 16),
              Container(
                width: 72, height: 72,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: KinrelColors.orange.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.alternate_email,
                    color: KinrelColors.orange, size: 36),
              ),

              // ── Explanation ──
              Text(
                'Your username is your unique identity on Kinrel.',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 14,
                  color: KinrelColors.textDim,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                'Family members can find and connect with you by searching for your @username.',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 12,
                  color: KinrelColors.textDim,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 32),

              // ── Username input ──
              TextFormField(
                controller: _controller,
                focusNode: _focusNode,
                textInputAction: TextInputAction.done,
                textCapitalization: TextCapitalization.none,
                keyboardType: TextInputType.text,
                style: TextStyle(
                  fontFamily: KinrelTypography.monoFont,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: KinrelColors.textWhite,
                ),
                decoration: InputDecoration(
                  prefixText: '@ ',
                  prefixStyle: TextStyle(
                    fontFamily: KinrelTypography.monoFont,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: KinrelColors.orange,
                  ),
                  hintText: 'username',
                  hintStyle: TextStyle(
                    fontFamily: KinrelTypography.monoFont,
                    fontSize: 18,
                    color: KinrelColors.textDim.withValues(alpha: 0.5),
                  ),
                  filled: true,
                  fillColor: KinrelColors.darkCard,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 16),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: availability == UsernameAvailability.available
                          ? const Color(0xFF22C55E)
                          : (availability == UsernameAvailability.taken
                              ? KinrelColors.error
                              : KinrelColors.border),
                      width: availability == UsernameAvailability.available || availability == UsernameAvailability.taken ? 2 : 1,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: availability == UsernameAvailability.available
                          ? const Color(0xFF22C55E)
                          : KinrelColors.orange,
                      width: 2,
                    ),
                  ),
                  suffixIcon: _buildSuffixIcon(availability),
                ),
                onFieldSubmitted: (_) => _canSubmitAt(availability) ? _submit() : null,
              ),

              const SizedBox(height: 10),

              // ── Helper / status text ──
              _buildStatusText(availability),

              const SizedBox(height: 8),

              // ── Rules ──
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: KinrelColors.darkCard,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: KinrelColors.border, width: 1),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'USERNAME RULES',
                      style: TextStyle(
                        fontFamily: KinrelTypography.monoFont,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: KinrelColors.textDim,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    _rule('3–30 characters'),
                    _rule('Lowercase letters, numbers, and underscores only'),
                    _rule('Must be unique — checked in real time'),
                  ],
                ),
              ),

              const Spacer(),

              // ── Submit button ──
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: _canSubmitAt(availability) ? _submit : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: KinrelColors.orange,
                    disabledBackgroundColor: KinrelColors.darkElevated,
                    foregroundColor: Colors.white,
                    disabledForegroundColor: KinrelColors.textDim,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : Text(
                          'Continue',
                          style: TextStyle(
                            fontFamily: KinrelTypography.bodyFont,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ),

              const SizedBox(height: 12),

              // ── Can't skip ──
              Text(
                'You must choose a username to continue.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 11,
                  color: KinrelColors.textDim,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget? _buildSuffixIcon(UsernameAvailability availability) {
    if (availability == UsernameAvailability.checking) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: SizedBox(
          width: 18, height: 18,
          child: CircularProgressIndicator(
              strokeWidth: 2, color: KinrelColors.orange),
        ),
      );
    }
    if (availability == UsernameAvailability.available && _isValid) {
      return const Icon(Icons.check_circle, color: Color(0xFF22C55E), size: 22);
    }
    if (availability == UsernameAvailability.taken) {
      return const Icon(Icons.cancel, color: KinrelColors.error, size: 22);
    }
    return null;
  }

  Widget _buildStatusText(UsernameAvailability availability) {
    if (_controller.text.isEmpty) {
      return const SizedBox.shrink();
    }
    if (availability == UsernameAvailability.checking) {
      return Text(
        'Checking availability…',
        style: TextStyle(
          fontFamily: KinrelTypography.bodyFont,
          fontSize: 12,
          color: KinrelColors.textDim,
        ),
      );
    }
    if (availability == UsernameAvailability.available && _isValid) {
      return Text(
        '✓ @${_controller.text.toLowerCase()} is available!',
        style: const TextStyle(
          fontFamily: KinrelTypography.bodyFont,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Color(0xFF22C55E),
        ),
      );
    }
    if (availability == UsernameAvailability.taken) {
      return Text(
        '✗ @${_controller.text.toLowerCase()} is already taken',
        style: TextStyle(
          fontFamily: KinrelTypography.bodyFont,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: KinrelColors.error,
        ),
      );
    }
    if (!_isValid) {
      final error = UsernameValidator.validate(_controller.text);
      return Text(
        error ?? '',
        style: TextStyle(
          fontFamily: KinrelTypography.bodyFont,
          fontSize: 12,
          color: KinrelColors.error,
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _rule(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Icon(Icons.check, size: 14, color: KinrelColors.textDim),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 12,
                color: KinrelColors.textDim,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
