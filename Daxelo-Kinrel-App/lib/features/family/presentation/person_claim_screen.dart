// lib/features/family/presentation/person_claim_screen.dart
//
// Shown when a recipient taps a person-specific invite link
// (https://kinrel.app/claim/{code}). The screen:
//   1. Fetches the PersonLinkInvitation by code
//   2. Shows a "Confirm your details" view pre-filled with the name +
//      relationship already entered by the family member who invited them
//   3. If the user isn't signed in, prompts them to sign in / sign up first
//   4. On confirm, calls the Supabase RPC to accept the invitation, which
//      links their Kinrel account to the existing Person record (same
//      linkedUserId mechanism as findOnKinrel)
//
// Route: /claim/:code

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/services/supabase_service.dart';
import '../../../shared/widgets/dk_components.dart';

class PersonClaimScreen extends ConsumerStatefulWidget {
  const PersonClaimScreen({super.key, required this.code});
  final String code;

  @override
  ConsumerState<PersonClaimScreen> createState() => _PersonClaimScreenState();
}

class _PersonClaimScreenState extends ConsumerState<PersonClaimScreen> {
  bool _loading = true;
  bool _claiming = false;
  String? _error;
  Map<String, dynamic>? _invitation;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadInvitation());
  }

  Future<void> _loadInvitation() async {
    final client = ref.read(supabaseProvider);
    if (client == null) {
      setState(() {
        _loading = false;
        _error = 'Not signed in';
      });
      return;
    }

    try {
      // Query the PersonLinkInvitation by code
      final resp = await client
          .from('PersonLinkInvitation')
          .select('''
            id, code, status, expiresAt, recipientName, recipientEmail,
            recipientPhone, role, createdAt,
            person:personId(id, name, gender, familyId),
            family:familyId(id, name),
            inviter:inviterUserId(name, email)
          ''')
          .eq('code', widget.code)
          .maybeSingle()
          .timeout(const Duration(seconds: 10));

      if (resp == null) {
        setState(() {
          _loading = false;
          _error = 'Invitation not found. It may have been revoked.';
        });
        return;
      }

      final status = resp['status'] as String?;
      final expiresAtStr = resp['expiresAt'] as String?;
      final expiresAt = expiresAtStr != null
          ? DateTime.tryParse(expiresAtStr)
          : null;

      if (status == 'accepted') {
        setState(() {
          _loading = false;
          _error = 'This invitation has already been accepted.';
        });
        return;
      }

      if (status == 'expired' ||
          (expiresAt != null && DateTime.now().isAfter(expiresAt))) {
        setState(() {
          _loading = false;
          _error = 'This invitation has expired. Ask your family member to send a new one.';
        });
        return;
      }

      setState(() {
        _invitation = resp;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  Future<void> _acceptInvitation() async {
    if (_invitation == null) return;
    setState(() => _claiming = true);

    try {
      final client = ref.read(supabaseProvider);
      if (client == null || client.auth.currentUser == null) {
        // Shouldn't happen — the route guard redirects to sign-in first
        setState(() {
          _claiming = false;
          _error = 'Please sign in to accept this invitation.';
        });
        return;
      }

      final userId = client.auth.currentUser!.id;
      final personId = (_invitation!['person'] as Map<String, dynamic>?)?['id'] as String?;
      final familyId = (_invitation!['family'] as Map<String, dynamic>?)?['id'] as String?;

      if (personId == null || familyId == null) {
        setState(() {
          _claiming = false;
          _error = 'Invalid invitation data.';
        });
        return;
      }

      // Link the Person to the current user's Kinrel account — same mechanism
      // as findOnKinrel (set linkedUserId + linkedAt on the Person row).
      // We also mark the invitation as accepted.
      //
      // We do this via direct Supabase UPDATE (not the NestJS endpoint,
      // which currently rejects Supabase JWTs).
      await client.from('Person').update({
        'linkedUserId': userId,
        'linkedAt': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', personId);

      await client.from('PersonLinkInvitation').update({
        'status': 'accepted',
        'acceptedAt': DateTime.now().toUtc().toIso8601String(),
        'acceptedByUserId': userId,
      }).eq('code', widget.code);

      if (!mounted) return;

      // Show success and navigate to the family
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You\'re now linked to your family tree! 🎉'),
          backgroundColor: KinrelColors.darkElevated,
          duration: Duration(seconds: 3),
        ),
      );

      // Navigate to the family detail screen
      GoRouter.of(context).go('/family/$familyId');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _claiming = false;
        _error = 'Failed to accept invitation: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DKScaffold(
      backgroundColor: KinrelColors.darkBackground,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => GoRouter.of(context).go('/home'),
        ),
        title: Text(
          'Confirm Your Spot',
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
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: KinrelColors.orange),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(KinrelSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline,
                  color: KinrelColors.error, size: 48),
              const SizedBox(height: KinrelSpacing.md),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 14,
                  color: KinrelColors.textDim,
                ),
              ),
              const SizedBox(height: KinrelSpacing.lg),
              DKButton(
                label: 'Go Home',
                variant: DKButtonVariant.primary,
                onPressed: () => GoRouter.of(context).go('/home'),
              ),
            ],
          ),
        ),
      );
    }

    final person = _invitation!['person'] as Map<String, dynamic>?;
    final family = _invitation!['family'] as Map<String, dynamic>?;
    final inviter = _invitation!['inviter'] as Map<String, dynamic>?;
    final recipientName = _invitation!['recipientName'] as String? ?? '';
    final personName = person?['name'] as String? ?? recipientName;
    final familyName = family?['name'] as String? ?? 'Family';
    final inviterName = inviter?['name'] as String? ?? 'A family member';

    return ListView(
      padding: const EdgeInsets.all(KinrelSpacing.xl),
      children: [
        const SizedBox(height: KinrelSpacing.xl),
        // Hero icon
        Container(
          width: 80, height: 80,
          decoration: BoxDecoration(
            color: KinrelColors.orange.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.family_restroom,
              color: KinrelColors.orange, size: 40),
        ),
        const SizedBox(height: KinrelSpacing.lg),

        // Personalized message
        Text(
          '$inviterName added you to the $familyName family tree on Kinrel! 🧡',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: KinrelColors.textWhite,
            height: 1.4,
          ),
        ),
        const SizedBox(height: KinrelSpacing.md),
        Text(
          'You\'ve been added as "$personName". Confirm to link your Kinrel '
          'account to this spot in the family tree.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 13,
            color: KinrelColors.textDim,
            height: 1.5,
          ),
        ),

        const SizedBox(height: KinrelSpacing.xxl),

        // Pre-filled details card
        Container(
          padding: const EdgeInsets.all(KinrelSpacing.lg),
          decoration: BoxDecoration(
            color: KinrelColors.darkCard,
            borderRadius: BorderRadius.circular(KinrelRadius.lg),
            border: Border.all(color: KinrelColors.border, width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _detailRow('Your name', personName),
              if (family != null) _detailRow('Family', familyName),
              if (_invitation!['recipientEmail'] != null)
                _detailRow('Email', _invitation!['recipientEmail'] as String),
              if (_invitation!['recipientPhone'] != null)
                _detailRow('Phone', _invitation!['recipientPhone'] as String),
            ],
          ),
        ),

        const SizedBox(height: KinrelSpacing.xxl),

        // Accept button
        DKButton(
          label: 'Confirm & Join Family',
          variant: DKButtonVariant.gradient,
          fullWidth: true,
          isLoading: _claiming,
          onPressed: _acceptInvitation,
        ),

        const SizedBox(height: KinrelSpacing.md),

        // Decline
        TextButton(
          onPressed: () => GoRouter.of(context).go('/home'),
          child: Text(
            'Not now',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              color: KinrelColors.textDim,
            ),
          ),
        ),

        const SizedBox(height: KinrelSpacing.xl),
        Text(
          'By confirming, you link your Kinrel account to this person in the '
          'family tree. Your family will be able to see your profile and '
          'connect with you.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 10,
            color: KinrelColors.textDim,
            height: 1.5,
          ),
        ),
      ],
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 11,
                color: KinrelColors.textDim,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: KinrelColors.textWhite,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
