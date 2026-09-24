// lib/features/family/presentation/join_or_create_family_screen.dart
//
// First-run decision screen — shown after sign-up + username creation
// if the user has no families yet. Lets the user pick the right path
// in a single tap:
//
//   ┌─────────────────────────────────────┐
//   │     Welcome to Daxelo Kinrel         │
//   │                                      │
//   │  🔗 Join an existing family          │
//   │  Got an invite link? Paste it here.  │
//   │  [___________________________] [Go]  │
//   │                                      │
//   │  ──── or ────                        │
//   │                                      │
//   │  👨‍👩‍👧 Start a new family              │
//   │  You'll be the family admin.        │
//   │  Family name: [_________________]    │
//   │  [Start new family]                 │
//   └─────────────────────────────────────┘
//
// Why this screen (vs auto-creating a default family)
//   Auto-creating "Manish's Family" for every new user explodes the
//   family table — 1000 users → 1000 mostly-abandoned "Manish's
//   Family" rows. The decision screen lets the user pick the right
//   path in 1 tap, and:
//   - Zero orphan families (no row created unless the user taps)
//   - Existing-family joiners get to their family in 1 tap (paste
//     link → done — or just tap the auto-detected clipboard banner)
//   - New-family creators give the family a real name upfront
//     (pre-filled with their surname, but editable)
//
// Three refinements baked in:
//   A. Auto-detect invite link from clipboard — if the user copied
//      a "KIN-XXXXXXXX" family id or a share-plus URL with a family
//      code, show a banner: "We found an invite code in your
//      clipboard — tap to join". Saves the paste step entirely.
//   B. Surname pre-fill for the "Start new family" field — default
//      the family-name field to "<LastName> Family" using the user's
//      name from auth metadata. The user can override but most won't.
//   C. Skip-the-screen-if-not-needed — this screen only renders if
//      the user has zero families. If they already have one (e.g.,
//      via deep-link join during sign-up), they go straight to /home.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';

class JoinOrCreateFamilyScreen extends ConsumerStatefulWidget {
  const JoinOrCreateFamilyScreen({super.key});

  @override
  ConsumerState<JoinOrCreateFamilyScreen> createState() => _JoinOrCreateFamilyScreenState();
}

class _JoinOrCreateFamilyScreenState extends ConsumerState<JoinOrCreateFamilyScreen> {
  final _joinCodeController = TextEditingController();
  final _familyNameController = TextEditingController();
  bool _loading = true;
  bool _checkingClipboard = true;
  String? _clipboardFamilyId;
  String? _clipboardFamilyName;
  String? _joinError;
  bool _joining = false;
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      // 1. Check if user already has a family — if yes, skip this screen.
      final hasFamily = await _userHasFamily();
      if (!mounted) return;
      if (hasFamily) {
        // Already in a family — go straight to home.
        context.go('/home');
        return;
      }
      // 2. No family — show the decision screen. Pre-fill the family
      // name with the user's surname.
      _prefillFamilyName();
      // 3. Check clipboard for an invite code.
      await _checkClipboardForInvite();
      if (mounted) setState(() => _loading = false);
    });
  }

  @override
  void dispose() {
    _joinCodeController.dispose();
    _familyNameController.dispose();
    super.dispose();
  }

  Future<bool> _userHasFamily() async {
    try {
      final client = Supabase.instance.client;
      final userId = client.auth.currentUser?.id;
      if (userId == null) return false;
      final rows = await client
          .from('FamilyMember')
          .select('id')
          .eq('userId', userId)
          .limit(1);
      return (rows as List).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  void _prefillFamilyName() {
    try {
      final client = Supabase.instance.client;
      final user = client.auth.currentUser;
      // The user's display name is stored in auth metadata
      // (provider_profile_data → full_name) OR in the User table.
      // We try auth metadata first since it's local + instant.
      final fullName = (user?.userMetadata?['full_name'] ??
          user?.userMetadata?['name'] ??
          user?.userMetadata?['displayName']) as String? ?? '';
      if (fullName.isEmpty) {
        // Fallback: fetch from User table.
        _fetchNameFromUserTable();
        return;
      }
      final surname = _extractSurname(fullName);
      if (surname.isNotEmpty) {
        _familyNameController.text = '$surname Family';
      }
    } catch (_) {}
  }

  Future<void> _fetchNameFromUserTable() async {
    try {
      final client = Supabase.instance.client;
      final userId = client.auth.currentUser?.id;
      if (userId == null) return;
      final row = await client
          .from('User')
          .select('name')
          .eq('id', userId)
          .maybeSingle();
      if (!mounted) return;
      final name = (row?['name'] as String?) ?? '';
      if (name.isNotEmpty) {
        final surname = _extractSurname(name);
        if (surname.isNotEmpty) {
          // Only set if user hasn't typed something themselves.
          if (_familyNameController.text.isEmpty) {
            setState(() {
              _familyNameController.text = '$surname Family';
            });
          }
        }
      }
    } catch (_) {}
  }

  /// Extracts the surname from a full name. Handles common Indian
  /// name patterns where the surname is the last token. Returns '' if
  /// no surname can be extracted (single-token names, empty names).
  String _extractSurname(String fullName) {
    final trimmed = fullName.trim();
    if (trimmed.isEmpty) return '';
    final parts = trimmed.split(RegExp(r'\s+'));
    if (parts.length < 2) return '';
    // Last token is the surname in most Western + many Indian name
    // patterns. For "Manish Sharma" → "Sharma". For "M. Sharma" →
    // "Sharma". For "Sharma" (single token) → '' (no surname).
    final last = parts.last;
    // Skip patronymic-style single-letter initials at the end
    // (e.g., "Manish S." — the surname is "S" which is too short
    // to be useful as a family name). Fall back to the second-to-
    // last if present.
    if (last.length <= 2 && parts.length >= 3) {
      return parts[parts.length - 2];
    }
    return last;
  }

  Future<void> _checkClipboardForInvite() async {
    try {
      final data = await Clipboard.getData('text/plain');
      final text = data?.text?.trim() ?? '';
      if (text.isEmpty) {
        if (mounted) setState(() => _checkingClipboard = false);
        return;
      }
      // Look for a "KIN-XXXXXXXX" pattern in the clipboard text.
      // The existing JoinFamilyScreen accepts KIN-XXXXXXXX family
      // ids via deep link. We surface the same pattern here so
      // users who copied a code from a WhatsApp group see the
      // banner immediately.
      final kinMatch = RegExp(r'KIN-[A-Za-z0-9]{6,12}').firstMatch(text);
      if (kinMatch != null) {
        final code = kinMatch.group(0)!;
        // Optional: fetch a friendly family name for the preview.
        // We do this best-effort — if it fails, we still show the
        // banner with just the code.
        String? familyName;
        try {
          final client = Supabase.instance.client;
          final row = await client
              .from('Family')
              .select('name')
              .eq('id', code)
              .maybeSingle();
          familyName = row?['name'] as String?;
        } catch (_) {}
        if (!mounted) return;
        setState(() {
          _clipboardFamilyId = code;
          _clipboardFamilyName = familyName;
          _checkingClipboard = false;
        });
        return;
      }
      if (mounted) setState(() => _checkingClipboard = false);
    } catch (_) {
      if (mounted) setState(() => _checkingClipboard = false);
    }
  }

  Future<void> _joinWithClipboardCode() async {
    if (_clipboardFamilyId == null) return;
    setState(() {
      _joining = true;
      _joinError = null;
    });
    try {
      // Use the existing JoinFamilyScreen by pushing it with the
      // kinFamilyId pre-filled. The screen handles the actual join
      // request + navigation. We pop this decision screen so the
      // back stack is clean.
      if (!mounted) return;
      context.go('/join-family?kinFamilyId=$_clipboardFamilyId');
    } catch (e) {
      if (mounted) {
        setState(() {
          _joining = false;
          _joinError = '$e';
        });
      }
    }
  }

  Future<void> _joinWithManualCode() async {
    final code = _joinCodeController.text.trim();
    if (code.isEmpty) {
      setState(() => _joinError = 'Please enter a family code.');
      return;
    }
    // Normalize: if the user typed the code without the "KIN-" prefix,
    // add it. The JoinFamilyScreen expects the KIN-XXXXXXXX format.
    String normalized = code;
    if (!normalized.startsWith('KIN-') && !normalized.startsWith('kin-')) {
      normalized = 'KIN-${code.toUpperCase()}';
    }
    setState(() {
      _joining = true;
      _joinError = null;
    });
    if (!mounted) return;
    context.go('/join-family?kinFamilyId=$normalized');
  }

  Future<void> _createNewFamily() async {
    final name = _familyNameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a family name.')),
      );
      return;
    }
    setState(() => _creating = true);
    if (!mounted) return;
    // Pass the pre-filled name to the create-family screen via
    // query param so the user doesn't retype it. The
    // CreateFamilyScreen reads it from the route in initState.
    context.go('/families/create?prefillName=${Uri.encodeComponent(name)}');
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: const Color(0xFF13141E),
        body: const Center(child: CircularProgressIndicator(color: KinrelColors.orange)),
      );
    }
    return Scaffold(
      backgroundColor: const Color(0xFF13141E),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: KinrelColors.textWhite,
        title: const Text(
          'Welcome to Daxelo Kinrel',
          style: TextStyle(fontFamily: KinrelTypography.displayFont, fontWeight: FontWeight.w700),
        ),
        // Allow the user to skip — they can set up a family later
        // from the home screen's empty state.
        actions: [
          TextButton(
            onPressed: () => context.go('/home'),
            child: const Text('Skip', style: TextStyle(color: KinrelColors.textDim)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 12),
            // Hero illustration / welcome text
            const Text(
              '🧡',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 56),
            ),
            const SizedBox(height: 16),
            Text(
              'Daxelo Kinrel is a private space for your family — share predictions, build your kinship graph, and stay connected with the people who matter.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 14,
                color: KinrelColors.textSilver,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 32),

            // ── Clipboard-detection banner (refinement A) ────────
            if (_clipboardFamilyId != null) ...[
              _ClipboardInviteBanner(
                familyId: _clipboardFamilyId!,
                familyName: _clipboardFamilyName,
                onTap: _joinWithClipboardCode,
                loading: _joining,
              ),
              const SizedBox(height: 20),
              // Divider with "or" — visually separates the banner
              // from the manual options below.
              Row(
                children: [
                  const Expanded(child: Divider(color: KinrelColors.border)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      'or',
                      style: TextStyle(
                        fontFamily: KinrelTypography.monoFont,
                        fontSize: 11,
                        color: KinrelColors.textDim,
                      ),
                    ),
                  ),
                  const Expanded(child: Divider(color: KinrelColors.border)),
                ],
              ),
              const SizedBox(height: 20),
            ],

            // ── Join an existing family ──────────────────────────
            _SectionCard(
              icon: Icons.link_rounded,
              iconColor: KinrelColors.orange,
              title: 'Join an existing family',
              subtitle: 'Got a family code? Enter it below.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _joinCodeController,
                          style: const TextStyle(color: KinrelColors.textWhite, fontFamily: KinrelTypography.bodyFont),
                          decoration: InputDecoration(
                            hintText: 'e.g., KIN-2A3B4C5D',
                            hintStyle: const TextStyle(color: KinrelColors.textDim, fontSize: 13),
                            filled: true,
                            fillColor: KinrelColors.darkCard,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(color: KinrelColors.border),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(color: KinrelColors.orange, width: 1.2),
                            ),
                          ),
                          onSubmitted: (_) => _joinWithManualCode(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        onPressed: _joining ? null : _joinWithManualCode,
                        icon: _joining
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.arrow_forward, size: 18),
                        style: IconButton.styleFrom(
                          backgroundColor: KinrelColors.orange,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  if (_joinError != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _joinError!,
                      style: const TextStyle(color: Colors.red, fontSize: 12, fontFamily: KinrelTypography.bodyFont),
                    ),
                  ],
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () => context.push('/join-family'),
                    child: const Text(
                      'Scan a QR code instead →',
                      style: TextStyle(
                        color: KinrelColors.orange,
                        fontSize: 12,
                        fontFamily: KinrelTypography.bodyFont,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ── Start a new family ────────────────────────────────
            _SectionCard(
              icon: Icons.family_restroom_rounded,
              iconColor: KinrelColors.brightGold,
              title: 'Start a new family',
              subtitle: "You'll be the family admin and can invite members later.",
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _familyNameController,
                    style: const TextStyle(color: KinrelColors.textWhite, fontFamily: KinrelTypography.bodyFont),
                    decoration: InputDecoration(
                      hintText: 'Family name',
                      hintStyle: const TextStyle(color: KinrelColors.textDim, fontSize: 14),
                      filled: true,
                      fillColor: KinrelColors.darkCard,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: KinrelColors.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: KinrelColors.brightGold, width: 1.2),
                      ),
                    ),
                    onSubmitted: (_) => _createNewFamily(),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _creating ? null : _createNewFamily,
                    icon: _creating
                        ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                        : const Icon(Icons.add_rounded, size: 18),
                    label: const Text(
                      'Start new family',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: KinrelColors.brightGold,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),
            // Tiny help footer
            Text(
              'You can always join or create a family later from the home screen.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 11,
                color: KinrelColors.textDim,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Sub-widgets ──────────────────────────────────────────────────────

class _ClipboardInviteBanner extends StatelessWidget {
  const _ClipboardInviteBanner({
    required this.familyId,
    required this.familyName,
    required this.onTap,
    required this.loading,
  });
  final String familyId;
  final String? familyName;
  final VoidCallback onTap;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: KinrelColors.orange.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: KinrelColors.orange.withValues(alpha: 0.35), width: 1),
        ),
        child: Row(
          children: [
            const Icon(Icons.content_paste_rounded, color: KinrelColors.orange, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'We found an invite code in your clipboard',
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: KinrelColors.textWhite,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    familyName != null
                        ? 'Tap to join "$familyName" ($familyId)'
                        : 'Tap to join $familyId',
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 11,
                      color: KinrelColors.textSilver,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (loading)
              const SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: KinrelColors.orange),
              )
            else
              const Icon(Icons.arrow_forward_ios, color: KinrelColors.orange, size: 14),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.child,
  });
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: KinrelColors.border, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontFamily: KinrelTypography.displayFont,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: KinrelColors.textWhite,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 11,
                        color: KinrelColors.textDim,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}
