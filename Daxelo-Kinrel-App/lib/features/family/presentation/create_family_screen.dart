import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_selector/file_selector.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/constants/feature_flags.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/family/optimistic_actions.dart';
import '../../../core/family/family_provider.dart' show familyGraphProvider;
import '../../../core/services/supabase_service.dart';
import '../../../core/utils/form_validators.dart';
import '../../../core/utils/api_error_mapper.dart';
import '../../../shared/widgets/dk_components.dart';
import 'add_person_sheet.dart';
import 'join_family_screen.dart';
import 'qr_scanner_screen.dart';

class CreateFamilyScreen extends ConsumerStatefulWidget {
  CreateFamilyScreen({super.key});

  @override
  ConsumerState<CreateFamilyScreen> createState() => _CreateFamilyScreenState();
}

class _CreateFamilyScreenState extends ConsumerState<CreateFamilyScreen> {
  final _pageController = PageController();
  int _currentStep = 0;
  static const int _totalSteps = 3;
  bool _isSubmitting = false;

  final _nameController = TextEditingController();
  final _codeController = TextEditingController();
  final _usernameController = TextEditingController();
  File? _avatarImageFile;
  String? _avatarUrl;
  String _selectedRegion = 'North India';
  bool _isCustomCode = false;

  _PrivacyMode _privacyMode = _PrivacyMode.inviteOnly;

  final _personNameController = TextEditingController();
  final _birthYearController = TextEditingController();
  String? _selectedGender;

  @override
  void initState() {
    super.initState();
    _nameController.addListener(_onNameChanged);
    // ✅ FIX (BUG-NEXT): Also listen to person name and gender so
    // _canProceedStep3 re-evaluates on Step 3.
    _personNameController.addListener(_onStep3Changed);

    // ✅ FIX (BUG-02): Generate initial code and username so Next is enabled
    // and the family code shows correctly on first render instead of
    // showing "kinrel.co/f/" with the Next button disabled.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final suffix = _generateCodeSuffix();
        _codeController.text = 'family-$suffix';
        _usernameController.text = 'family$suffix';
        _lastAutoUsername = 'family$suffix';

        // ── Pre-fill the creator's name from their profile ──────────
        // The creator should be added to the family graph by default
        // with their actual name, not "Your Name". We pull the name
        // from (in priority order):
        //   1. Supabase auth userMetadata['name'] (set at sign-up)
        //   2. Supabase auth userMetadata['full_name'] (Google OAuth)
        //   3. Email username (part before @)
        // The user can still edit it before submitting.
        final user = ref.read(supabaseProvider)?.auth.currentUser;
        if (user != null && _personNameController.text.isEmpty) {
          final name = user.userMetadata?['name'] as String? ??
              user.userMetadata?['full_name'] as String? ??
              user.userMetadata?['displayName'] as String?;
          if (name != null && name.trim().isNotEmpty) {
            _personNameController.text = name.trim();
          } else if (user.email != null && user.email!.isNotEmpty) {
            // Fall back to the email username (before @).
            final emailUser = user.email!.split('@').first;
            if (emailUser.isNotEmpty) {
              _personNameController.text = emailUser;
            }
          }
        }

        setState(() {}); // refresh _canProceedStep1 + _canProceedStep3
      }
    });
  }

  @override
  void dispose() {
    _nameController.removeListener(_onNameChanged);
    _personNameController.removeListener(_onStep3Changed);
    _nameController.dispose();
    _codeController.dispose();
    _usernameController.dispose();
    _personNameController.dispose();
    _birthYearController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _onNameChanged() {
    if (!_isCustomCode) {
      final slug = _nameController.text
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
          .replaceAll(RegExp(r'^-|-$'), '');
      // Reuse the same suffix that was generated in initState to avoid
      // generating a new random suffix on every keystroke.
      final currentCodeSuffix = _codeController.text.contains('-')
          ? _codeController.text.split('-').last
          : _generateCodeSuffix();
      _codeController.text = slug.isEmpty ? '' : '$slug-$currentCodeSuffix';
    }
    // Auto-generate username from family name
    if (_usernameController.text.isEmpty ||
        _usernameController.text == _lastAutoUsername) {
      final base = _nameController.text
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9_]'), '')
          .replaceAll(RegExp(r'^[^a-z]+'), '');
      // ✅ FIX: append 4-char suffix to guarantee uniqueness
      // Reuse the same suffix so it doesn't change on every keystroke
      final currentSuffix = _usernameController.text.length >= 4
          ? _usernameController.text.substring(_usernameController.text.length - 4)
          : _generateCodeSuffix();
      final username = base.isEmpty ? 'family$currentSuffix' : '$base$currentSuffix';
      _lastAutoUsername = username;
      _usernameController.text = username;
    }
    // ✅ FIX (BUG-NEXT): Must call setState so the parent rebuilds and
    // _canProceedStep1 / _canProceedStep3 re-evaluate. Without this,
    // the Next / Create Family button state never updates after typing.
    setState(() {});
  }

  String _lastAutoUsername = '';

  // ✅ FIX (BUG-NEXT): Listener for Step 3 fields so the Create Family
  // button state updates as the user types their name.
  void _onStep3Changed() {
    setState(() {});
  }

  Future<void> _pickAvatarImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
    );
    if (picked != null && mounted) {
      setState(() => _avatarImageFile = File(picked.path));
    }
  }

  /// v62.4: Web-compatible photo picker using file_selector.
  /// On web, ImagePicker.pickImage opens a generic file browser.
  /// This method uses file_selector's image-only filter so the user
  /// sees only image files (jpg, png, webp, gif), not all files.
  Future<void> _pickAvatarImageWeb() async {
    try {
      const XTypeGroup typeGroup = XTypeGroup(
        label: 'images',
        extensions: <String>['jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp'],
      );
      final XFile? file =
          await openFile(acceptedTypeGroups: const <XTypeGroup>[typeGroup]);
      if (file != null && mounted) {
        setState(() => _avatarImageFile = File(file.path));
      }
    } catch (e) {
      debugPrint('⚠️ Web image picker failed: $e — falling back to ImagePicker');
      await _pickAvatarImage();
    }
  }

  Future<void> _uploadAvatarIfNeeded() async {
    if (_avatarImageFile == null) return;
    try {
      final supabase = Supabase.instance.client;
      final bytes = await _avatarImageFile!.readAsBytes();
      final ext = _avatarImageFile!.path.split('.').last.toLowerCase();
      final safeExt = ['jpg','jpeg','png','webp'].contains(ext) ? ext : 'jpg';
      final path = 'family-avatars/${DateTime.now().millisecondsSinceEpoch}.$safeExt';

      await supabase.storage.from('avatars').uploadBinary(
        path,
        bytes,
        fileOptions: FileOptions(
          contentType: 'image/$safeExt',
          upsert: true,
        ),
      );
      _avatarUrl = supabase.storage.from('avatars').getPublicUrl(path);
    } on StorageException catch (e) {
      // ✅ FIX (BUG-11): Don't crash — just skip avatar upload and continue with initials
      debugPrint('⚠️ Avatar upload failed: ${e.message}. Continuing without photo.');
      _avatarUrl = null;
    } catch (e) {
      debugPrint('⚠️ Avatar upload unexpected error: $e');
      _avatarUrl = null;
    }
  }

  String _generateCodeSuffix() {
    final random = Random();
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    return String.fromCharCodes(
      Iterable.generate(
        4,
        (_) => chars.codeUnitAt(random.nextInt(chars.length)),
      ),
    );
  }

  String get _fullFamilyCode => _usernameController.text.isNotEmpty
      ? 'kinrel.co/f/@${_usernameController.text}'
      : 'kinrel.co/f/${_codeController.text}';

  bool get _canProceedStep1 {
    final nameError = familyNameValidator(_nameController.text);
    final codeEmpty = _codeController.text.trim().isEmpty;
    final usernameError = usernameValidator(_usernameController.text);
    return nameError == null && !codeEmpty && usernameError == null;
  }

  bool get _canProceedStep3 {
    final nameError = nameValidator(_personNameController.text);
    return nameError == null;
  }

  void _nextStep() {
    if (_currentStep < _totalSteps - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
      );
      setState(() => _currentStep++);
    } else {
      _submit();
    }
  }

  void _prevStep() {
    if (_currentStep > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
      );
      setState(() => _currentStep--);
    } else {
      context.pop();
    }
  }

  Future<void> _submit() async {
    if (_personNameController.text.trim().isEmpty) return;

    setState(() => _isSubmitting = true);

    try {
      await _uploadAvatarIfNeeded().timeout(const Duration(seconds: 10));

      final family = await createFamilyOptimistic(
        ref: ref,
        name: _nameController.text.trim(),
        description: null,
        primaryLanguage: null,
        region: _selectedRegion,
        photoUrl: _avatarUrl,
        privacyMode: _privacyMode == _PrivacyMode.private
            ? 'private'
            : _privacyMode == _PrivacyMode.inviteOnly
            ? 'invite'
            : 'link',
        username: _usernameController.text.trim(),
      ).timeout(const Duration(seconds: 15));

      // v4.2 (2026-08-15): createFamily now AUTO-CREATES the creator Person.
      // Instead of creating a duplicate, UPDATE the auto-created person with
      // the user's custom details (name, gender, birth year).
      final customName = _personNameController.text.trim();
      final birthYear = int.tryParse(_birthYearController.text.trim());
      final customGender = _selectedGender?.toLowerCase();

      // Find the auto-created creator Person (linked to current user)
      final client = ref.read(supabaseProvider);
      final creatorUserId = client?.auth.currentUser?.id;
      if (client != null && creatorUserId != null) {
        try {
          final existingPerson = await client
              .from('Person')
              .select('id')
              .eq('familyId', family.id)
              .eq('linkedUserId', creatorUserId)
              .limit(1)
              .timeout(const Duration(seconds: 5));

          if (existingPerson.isNotEmpty) {
            // UPDATE the auto-created person with custom details
            final personId = existingPerson[0]['id'] as String;
            final updateData = <String, dynamic>{
              'name': customName,
            };
            if (customGender != null) updateData['gender'] = customGender;
            if (birthYear != null) updateData['birthYear'] = birthYear;

            await client
                .from('Person')
                .update(updateData)
                .eq('id', personId)
                .timeout(const Duration(seconds: 10));

            debugPrint('[create_family_screen] Updated auto-created creator Person: $personId');
          } else {
            // Fallback: if no auto-created person exists (e.g. auto-create
            // failed), create one manually via createPersonOptimistic.
            await createPersonOptimistic(
              ref: ref,
              familyId: family.id,
              name: customName,
              gender: customGender,
              birthYear: birthYear,
              isAnchor: true,
              linkedUserId: creatorUserId,
            ).timeout(const Duration(seconds: 15));
          }
        } catch (e) {
          debugPrint('[create_family_screen] Could not update creator Person (non-fatal): $e');
          // Fallback: try creating via createPersonOptimistic
          try {
            await createPersonOptimistic(
              ref: ref,
              familyId: family.id,
              name: customName,
              gender: customGender,
              birthYear: birthYear,
              isAnchor: true,
              linkedUserId: creatorUserId,
            ).timeout(const Duration(seconds: 15));
          } catch (_) {}
        }
      }

      // Invalidate the graph so it reloads with the creator node
      ref.invalidate(familyGraphProvider(family.id));

      if (!mounted) return;

      context.showSnackBar(
        'Family "${family.name}" created! You\'re the anchor!',
      );

      // v62.5: Navigate IMMEDIATELY — don't keep the spinner going.
      setState(() => _isSubmitting = false);

      // Navigate to the family list (avoids white screen from graph
      // not loading freshly-created family data yet).
      context.go('/families');

      // Show the AddPersonSheet after a short delay (let the list load)
      Future.delayed(const Duration(milliseconds: 800), () {
        if (!mounted) return;
        AddPersonSheet.show(context, familyId: family.id);
      });
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);

        final fieldErrors = mapApiError(e);
        if (fieldErrors != null) {
          final formError = fieldErrors['form'];
          if (formError != null) {
            context.showSnackBar(formError, isError: true);
          } else {
            final firstError = fieldErrors.values.first;
            context.showSnackBar('Failed: $firstError', isError: true);
          }
        } else {
          String errorMsg = e.toString();
          if (errorMsg.startsWith('Exception: ')) {
            errorMsg = errorMsg.substring(11);
          }
          if (errorMsg.contains('row-level security')) {
            errorMsg = 'Permission denied. Please contact support.';
          } else if (errorMsg.contains('JWT expired')) {
            errorMsg = 'Session expired. Please sign in again.';
          } else if (errorMsg.contains('SocketException')) {
            errorMsg = 'No internet connection. Please try again.';
          } else if (errorMsg.contains('timed out')) {
            errorMsg = 'Connection timed out. Please try again.';
          }

          context.showSnackBar('Failed: $errorMsg', isError: true);
        }
      }
    }
  }

  /// v4.2 (2026-08-15): "Skip and Create" — creates the family WITH the
  /// auto-created creator Person (no custom details needed).
  /// The createFamily function now auto-creates the creator Person, so
  /// skipping just means the creator gets a default name (from auth
  /// metadata) instead of a custom one. The family graph will never
  /// be empty.
  Future<void> _submitSkip() async {
    setState(() => _isSubmitting = true);

    try {
      await _uploadAvatarIfNeeded().timeout(const Duration(seconds: 10));

      final family = await createFamilyOptimistic(
        ref: ref,
        name: _nameController.text.trim(),
        description: null,
        primaryLanguage: null,
        region: _selectedRegion,
        photoUrl: _avatarUrl,
        privacyMode: _privacyMode == _PrivacyMode.private
            ? 'private'
            : _privacyMode == _PrivacyMode.inviteOnly
            ? 'invite'
            : 'link',
        username: _usernameController.text.trim(),
      ).timeout(const Duration(seconds: 15));

      // v4.2: The creator Person is now auto-created by createFamily.
      // If the user entered a custom name on Step 3, update the
      // auto-created person with it. Otherwise, the default name
      // (derived from auth metadata) is used.
      final personName = _personNameController.text.trim();
      if (personName.isNotEmpty) {
        final client = ref.read(supabaseProvider);
        final creatorUserId = client?.auth.currentUser?.id;
        if (client != null && creatorUserId != null) {
          try {
            final existingPerson = await client
                .from('Person')
                .select('id')
                .eq('familyId', family.id)
                .eq('linkedUserId', creatorUserId)
                .limit(1)
                .timeout(const Duration(seconds: 5));

            if (existingPerson.isNotEmpty) {
              final personId = existingPerson[0]['id'] as String;
              final birthYear = int.tryParse(_birthYearController.text.trim());
              final updateData = <String, dynamic>{'name': personName};
              if (_selectedGender != null) {
                updateData['gender'] = _selectedGender!.toLowerCase();
              }
              if (birthYear != null) updateData['birthYear'] = birthYear;

              await client
                  .from('Person')
                  .update(updateData)
                  .eq('id', personId)
                  .timeout(const Duration(seconds: 10));
            }
          } catch (e) {
            debugPrint('[create_family_screen] _submitSkip: could not update creator Person: $e');
          }
        }
      }

      // Invalidate the graph so it reloads with the creator node
      ref.invalidate(familyGraphProvider(family.id));

      if (!mounted) return;

      context.showSnackBar(
        'Family "${family.name}" created! Add members anytime.',
      );
      setState(() => _isSubmitting = false);
      context.go('/families');
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        String errorMsg = e.toString();
        if (errorMsg.startsWith('Exception: ')) {
          errorMsg = errorMsg.substring(11);
        }
        context.showSnackBar('Failed: $errorMsg', isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_currentStep > 0) {
          _prevStep(); // go to previous step
        } else {
          context.pop(); // go back to previous screen
        }
      },
      child: DKScaffold(
        appBar: AppBar(
          leading: IconButton(icon: Icon(Icons.arrow_back), onPressed: _prevStep),
          title: Text(
            'Create Family',
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontWeight: FontWeight.w600,
            ),
          ),
          // v90 FIX: Add a "Scan QR to Join" action so users who landed on
          // Create Family but actually meant to join an existing family
          // have an escape hatch. Reuses the exact pattern from
          // family_list_screen.dart's _showJoinOptionsBottomSheet.
          actions: [
            if (kEnableQrJoin)
              IconButton(
                icon: const Icon(Icons.qr_code_scanner_rounded),
                tooltip: 'Scan QR to Join',
                onPressed: () {
                  Navigator.of(context).push<String>(
                    MaterialPageRoute(
                      builder: (_) => const QrScannerScreen(),
                    ),
                  ).then((familyId) {
                    if (familyId != null && familyId.isNotEmpty) {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              JoinFamilyScreen(kinFamilyId: familyId),
                        ),
                      );
                    }
                  });
                },
              ),
          ],
        ),
        body: Column(
        children: [
          // Step indicator
          _StepIndicator(currentStep: _currentStep, totalSteps: _totalSteps),

          // Page content
          Expanded(
            child: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _Step1FamilyIdentity(
                  nameController: _nameController,
                  codeController: _codeController,
                  usernameController: _usernameController,
                  fullFamilyCode: _fullFamilyCode,
                  onEditCode: () {
                    setState(() => _isCustomCode = true);
                  },
                  canProceed: _canProceedStep1,
                ),
                _Step2PrivacySetup(
                  privacyMode: _privacyMode,
                  onPrivacyChanged: (mode) =>
                      setState(() => _privacyMode = mode),
                  familyName: _nameController.text.trim(),
                  avatarImageFile: _avatarImageFile,
                  onPickAvatar: kIsWeb ? _pickAvatarImageWeb : _pickAvatarImage,
                ),
                _Step3AddYourself(
                  nameController: _personNameController,
                  birthYearController: _birthYearController,
                  selectedGender: _selectedGender,
                  onGenderChanged: (g) => setState(() => _selectedGender = g),
                  canProceed: _canProceedStep3,
                  familyName: _nameController.text.trim(),
                  avatarImageFile: _avatarImageFile,
                ),
              ],
            ),
          ),

          // Bottom navigation
          _BottomNav(
            currentStep: _currentStep,
            totalSteps: _totalSteps,
            onBack: _prevStep,
            onNext: _nextStep,
            canProceed: _currentStep == 0
                ? _canProceedStep1
                : _currentStep == 2
                ? _canProceedStep3
                : true,
            isSubmitting: _isSubmitting,
            // v62.4: On the last step, pass the Skip callback so the
            // user can create the family without adding more members.
            onSkip: _currentStep == _totalSteps - 1 ? _submitSkip : null,
          ),
        ],
      ),
      ),
    );
  }
}

// ── Step Indicator ────────────────────────────────────────────────

class _StepIndicator extends StatelessWidget {
  const _StepIndicator({required this.currentStep, required this.totalSteps});

  final int currentStep;
  final int totalSteps;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: KinrelSpacing.base,
        vertical: KinrelSpacing.md,
      ),
      child: Row(
        children: List.generate(totalSteps * 2 - 1, (index) {
          if (index.isOdd) {
            final lineIndex = index ~/ 2;
            return Expanded(
              child: Container(
                height: 2,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: lineIndex < currentStep
                      ? DKColors.brandPurple
                      : DKColors.brandPurple.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            );
          }
          final stepIndex = index ~/ 2;
          final isCompleted = stepIndex < currentStep;
          final isCurrent = stepIndex == currentStep;

          return Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isCompleted
                  ? DKColors.brandPurple
                  : isCurrent
                  ? DKColors.brandPurple.withValues(alpha: 0.2)
                  : DKColors.elevatedColor(context),
              border: isCurrent
                  ? Border.all(color: DKColors.brandPurple, width: 2)
                  : null,
            ),
            child: Center(
              child: isCompleted
                  ? Icon(Icons.check_rounded, size: 16, color: Colors.white)
                  : Text(
                      '${stepIndex + 1}',
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isCurrent
                            ? DKColors.brandPurple
                            : DKColors.textSecondary(context),
                      ),
                    ),
            ),
          );
        }),
      ),
    );
  }
}

// ── Step 1: Family Identity ──────────────────────────────────────

class _Step1FamilyIdentity extends StatelessWidget {
  const _Step1FamilyIdentity({
    required this.nameController,
    required this.codeController,
    required this.usernameController,
    required this.fullFamilyCode,
    required this.onEditCode,
    required this.canProceed,
  });

  final TextEditingController nameController;
  final TextEditingController codeController;
  final TextEditingController usernameController;
  final String fullFamilyCode;
  final VoidCallback onEditCode;
  final bool canProceed;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(KinrelSpacing.base),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Decorative family illustration
          Center(
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        DKColors.brandPurple.withValues(alpha: 0.15),
                        DKColors.brandViolet.withValues(alpha: 0.08),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    border: Border.all(
                      color: DKColors.brandPurple.withValues(alpha: 0.2),
                      width: 2,
                    ),
                  ),
                  child: Icon(
                    Icons.family_restroom_rounded,
                    size: 36,
                    color: DKColors.brandPurple,
                  ),
                ),
              )
              .animate(onPlay: (c) => c.forward())
              .fadeIn(duration: 500.ms)
              .scale(
                begin: const Offset(0.8, 0.8),
                end: const Offset(1.0, 1.0),
                duration: 400.ms,
                curve: Curves.easeOutBack,
              ),
          const SizedBox(height: 24),

          // Section header
          Text(
            'Family Identity',
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: DKColors.textPrimary(context),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Give your family a name and choose your settings',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 14,
              color: DKColors.textSecondary(context),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 32),

          // Family Name
          Text(
            'Family Name',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: DKColors.textSecondary(context),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: nameController,
            keyboardType: TextInputType.name,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: DKColors.textPrimary(context),
              height: 1.3,
            ),
            decoration: InputDecoration(
              hintText: 'e.g., Sharma Family',
              hintStyle: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: DKColors.textSecondary(context).withValues(alpha: 0.3),
              ),
              filled: true,
              fillColor: DKColors.elevatedColor(context),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(KinrelRadius.input),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 16,
              ),
            ),
            autofocus: true,
          ),
          const SizedBox(height: 16),

          // Family @username
          Text(
            'Family @username',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: DKColors.textSecondary(context),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: usernameController,
            keyboardType: TextInputType.text,
            textInputAction: TextInputAction.done,
            textCapitalization: TextCapitalization.none,
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: DKColors.textPrimary(context),
            ),
            decoration: InputDecoration(
              prefixText: '@ ',
              prefixStyle: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: DKColors.brandPurple,
              ),
              hintText: 'e.g. sharma_family',
              hintStyle: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: DKColors.textSecondary(context).withValues(alpha: 0.3),
              ),
              filled: true,
              fillColor: DKColors.elevatedColor(context),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(KinrelRadius.input),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Family Code
          Row(
            children: [
              Text(
                'Family Code',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: DKColors.textSecondary(context),
                ),
              ),
              Spacer(),
              GestureDetector(
                onTap: onEditCode,
                child: Text(
                  'Edit',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 12,
                    color: DKColors.brandPurple,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          DKCard(
            padding: 12,
            borderColor: DKColors.brandPurple.withValues(alpha: 0.1),
            child: Row(
              children: [
                Icon(
                  Icons.link_rounded,
                  size: 16,
                  color: DKColors.textSecondary(context),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    fullFamilyCode.isEmpty ? 'kinrel.co/f/' : fullFamilyCode,
                    style: TextStyle(
                      fontFamily: KinrelTypography.monoFont,
                      fontSize: 13,
                      color: fullFamilyCode.isEmpty
                          ? DKColors.textSecondary(context)
                          : DKColors.textPrimary(context),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ── Step 2: Privacy & Setup ──────────────────────────────────────

enum _PrivacyMode { private, inviteOnly, linkSharing }

class _Step2PrivacySetup extends StatelessWidget {
  const _Step2PrivacySetup({
    required this.privacyMode,
    required this.onPrivacyChanged,
    required this.familyName,
    required this.avatarImageFile,
    required this.onPickAvatar,
  });

  final _PrivacyMode privacyMode;
  final ValueChanged<_PrivacyMode> onPrivacyChanged;
  final String familyName;
  final File? avatarImageFile;
  final VoidCallback onPickAvatar;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(KinrelSpacing.base),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Privacy & Setup',
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: DKColors.textPrimary(context),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Control who can see and join your family',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 14,
              color: DKColors.textSecondary(context),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 32),

          Text(
            'Privacy Mode',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: DKColors.textSecondary(context),
            ),
          ),
          const SizedBox(height: 12),

          _PrivacyCard(
            icon: Icons.lock_outline_rounded,
            title: 'Private',
            description: 'Only you can see and manage this family',
            mode: _PrivacyMode.private,
            selectedMode: privacyMode,
            onTap: () => onPrivacyChanged(_PrivacyMode.private),
          ),
          const SizedBox(height: 10),
          _PrivacyCard(
            icon: Icons.mail_outline_rounded,
            title: 'Invite-Only',
            description: 'Family members can join by invitation or family code',
            mode: _PrivacyMode.inviteOnly,
            selectedMode: privacyMode,
            onTap: () => onPrivacyChanged(_PrivacyMode.inviteOnly),
          ),
          const SizedBox(height: 10),
          _PrivacyCard(
            icon: Icons.link_rounded,
            title: 'Link-Sharing',
            description: 'Anyone with the family link can request to join',
            mode: _PrivacyMode.linkSharing,
            selectedMode: privacyMode,
            onTap: () => onPrivacyChanged(_PrivacyMode.linkSharing),
          ),

          const SizedBox(height: 32),

          // Avatar picker
          Text(
            'Family Avatar',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: DKColors.textSecondary(context),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: GestureDetector(
              onTap: onPickAvatar,
              child: Stack(
                children: [
                  avatarImageFile != null
                      ? FutureBuilder<Uint8List>(
                          future: avatarImageFile!.readAsBytes(),
                          builder: (context, snapshot) {
                            if (snapshot.hasData) {
                              return CircleAvatar(
                                radius: 40,
                                backgroundImage: MemoryImage(snapshot.data!),
                              );
                            }
                            return DKAvatar(
                              initials: familyName.isNotEmpty
                                  ? familyName[0].toUpperCase()
                                  : 'S',
                              size: DKAvatarSize.xl,
                              borderColor: DKColors.brandGold.withValues(alpha: 0.4),
                              backgroundColor: DKColors.brandPurple,
                            );
                          },
                        )
                      : DKAvatar(
                          initials: familyName.isNotEmpty
                              ? familyName[0].toUpperCase()
                              : 'S',
                          size: DKAvatarSize.xl,
                          borderColor: DKColors.brandGold.withValues(alpha: 0.4),
                          backgroundColor: DKColors.brandPurple,
                        ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      decoration: BoxDecoration(
                        color: DKColors.brandPurple,
                        shape: BoxShape.circle,
                      ),
                      padding: const EdgeInsets.all(6),
                      child: const Icon(Icons.camera_alt, color: Colors.white, size: 16),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              avatarImageFile != null ? 'Tap to change photo' : 'Tap to add photo',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 12,
                color: DKColors.textSecondary(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Step 3: Add Yourself ─────────────────────────────────────────

class _Step3AddYourself extends StatelessWidget {
  const _Step3AddYourself({
    required this.nameController,
    required this.birthYearController,
    required this.selectedGender,
    required this.onGenderChanged,
    required this.canProceed,
    required this.familyName,
    required this.avatarImageFile,
  });

  final TextEditingController nameController;
  final TextEditingController birthYearController;
  final String? selectedGender;
  final ValueChanged<String?> onGenderChanged;
  final bool canProceed;
  final String familyName;
  final File? avatarImageFile;

  @override
  Widget build(BuildContext context) {
    final genders = ['Male', 'Female', 'Non-Binary', 'Prefer not to say'];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(KinrelSpacing.base),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Add Yourself',
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: DKColors.textPrimary(context),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'You are the anchor of this family tree',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 14,
              color: DKColors.textSecondary(context),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 32),

          // Family avatar preview (persisted from Step 2)
          Center(
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Family avatar as background circle
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        DKColors.brandPurple.withValues(alpha: 0.15),
                        DKColors.brandViolet.withValues(alpha: 0.08),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    border: Border.all(
                      color: DKColors.brandPurple.withValues(alpha: 0.3),
                      width: 2,
                    ),
                  ),
                  child: avatarImageFile != null
                      ? CircleAvatar(
                          radius: 42,
                          backgroundImage: FileImage(avatarImageFile!),
                        )
                      : DKAvatar(
                          initials: familyName.isNotEmpty
                              ? familyName[0].toUpperCase()
                              : 'F',
                          size: DKAvatarSize.xl,
                          backgroundColor: DKColors.brandPurple,
                          borderColor: DKColors.brandGold.withValues(alpha: 0.4),
                        ),
                ),
                // Person initial overlay (bottom-right)
                Positioned(
                  bottom: -2,
                  right: -2,
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: DKColors.brandPurple,
                      border: Border.all(color: DKColors.cardColor(context), width: 2),
                    ),
                    child: Center(
                      child: Text(
                        nameController.text.isNotEmpty
                            ? nameController.text[0].toUpperCase()
                            : '?',
                        style: TextStyle(
                          fontFamily: KinrelTypography.displayFont,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              'Who are you in this family?',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 13,
                color: DKColors.textSecondary(context),
              ),
            ),
          ),
          const SizedBox(height: 28),

          // Name
          Text(
            'Your Name *',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: DKColors.textSecondary(context),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: nameController,
            keyboardType: TextInputType.name,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: DKColors.textPrimary(context),
            ),
            decoration: InputDecoration(
              hintText: 'e.g., Rahul Sharma',
              hintStyle: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: DKColors.textSecondary(context).withValues(alpha: 0.3),
              ),
              filled: true,
              fillColor: DKColors.elevatedColor(context),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(KinrelRadius.input),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
            ),
            autofocus: true,
          ),
          const SizedBox(height: 20),

          // Birth Year
          Text(
            'Birth Year (optional)',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: DKColors.textSecondary(context),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: birthYearController,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            maxLength: 4,
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 16,
              color: DKColors.textPrimary(context),
            ),
            decoration: InputDecoration(
              hintText: 'e.g., 1990',
              hintStyle: TextStyle(
                color: DKColors.textSecondary(context).withValues(alpha: 0.5),
              ),
              filled: true,
              fillColor: DKColors.elevatedColor(context),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(KinrelRadius.input),
                borderSide: BorderSide.none,
              ),
              counterText: '',
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Gender chips
          Text(
            'Gender (optional)',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: DKColors.textSecondary(context),
            ),
          ),
          SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: genders.map((gender) {
              final isSelected = selectedGender == gender;
              return DKSuggestionChip(
                label: gender,
                isSelected: isSelected,
                onTap: () => onGenderChanged(isSelected ? null : gender),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

// ── Bottom Navigation ────────────────────────────────────────────

class _BottomNav extends StatelessWidget {
  const _BottomNav({
    required this.currentStep,
    required this.totalSteps,
    required this.onBack,
    required this.onNext,
    required this.canProceed,
    required this.isSubmitting,
    this.onSkip,
  });

  final int currentStep;
  final int totalSteps;
  final VoidCallback onBack;
  final VoidCallback onNext;
  final bool canProceed;
  final bool isSubmitting;
  /// v62.4: If non-null, a "Skip and Create" button is shown alongside
  /// the primary "Create Family" button on the last step. Tapping it
  /// creates the family without prompting to add more members.
  final VoidCallback? onSkip;

  @override
  Widget build(BuildContext context) {
    final bool isLastStep = currentStep == totalSteps - 1;

    return Container(
      padding: EdgeInsets.all(KinrelSpacing.base),
      decoration: BoxDecoration(
        color: DKColors.cardColor(context),
        border: Border(
          top: BorderSide(color: DKColors.borderColor(context), width: 1),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                if (currentStep > 0)
                  Expanded(
                    child: DKButton(
                      label: 'Back',
                      variant: DKButtonVariant.secondary,
                      onPressed: onBack,
                      size: DKButtonSize.md,
                    ),
                  ),
                if (currentStep > 0) SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: DKButton(
                    label: isLastStep ? 'Create & Add Members' : 'Next',
                    variant: isLastStep
                        ? DKButtonVariant.gradient
                        : DKButtonVariant.primary,
                    onPressed: canProceed && !isSubmitting ? onNext : null,
                    isLoading: isSubmitting,
                    fullWidth: true,
                    size: DKButtonSize.lg,
                  ),
                ),
              ],
            ),
            // v62.4: "Skip and Create" button — only on the last step.
            // v62.5: Skip button only requires Step 1 to be valid (family
            // name + username), NOT Step 3 (person name). The person name
            // is still required by _submitSkip(), but we show a snackbar
            // if it's empty rather than disabling the button.
            if (isLastStep && onSkip != null) ...[
              SizedBox(height: 8),
              DKButton(
                label: 'Skip and Create',
                variant: DKButtonVariant.secondary,
                onPressed: !isSubmitting ? onSkip : null,
                fullWidth: true,
                size: DKButtonSize.md,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Privacy Card ─────────────────────────────────────────────────

class _PrivacyCard extends StatelessWidget {
  const _PrivacyCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.mode,
    required this.selectedMode,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
  final _PrivacyMode mode;
  final _PrivacyMode selectedMode;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isSelected = mode == selectedMode;
    return DKCard(
      borderColor: isSelected
          ? DKColors.brandPurple.withValues(alpha: 0.5)
          : DKColors.borderColor(context),
      backgroundColor: isSelected
          ? DKColors.brandPurple.withValues(alpha: 0.06)
          : null,
      onTap: onTap,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isSelected
                  ? DKColors.brandPurple.withValues(alpha: 0.15)
                  : DKColors.elevatedColor(context),
            ),
            child: Icon(
              icon,
              size: 20,
              color: isSelected
                  ? DKColors.brandPurple
                  : DKColors.textSecondary(context),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontFamily: KinrelTypography.displayFont,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: isSelected
                        ? DKColors.textPrimary(context)
                        : DKColors.textSecondary(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 12,
                    color: DKColors.textSecondary(context),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          if (isSelected)
            Icon(
              Icons.check_circle_rounded,
              color: DKColors.brandPurple,
              size: 22,
            ),
        ],
      ),
    );
  }
}
