import 'package:kinrel/core/widgets/global_error_widget.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/constants/feature_flags.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/family/family_provider.dart';
import '../../../core/family/optimistic_actions.dart';
import '../../../core/family/relationship_edge_builder.dart'; // v5.19
import '../../../core/widgets/person_avatar.dart'; // v5.15
import '../../../core/viewer/viewer_provider.dart' show viewerPersonIdProvider; // v5.13
// v5.41: Graph pending invitations provider (for fromGraph routing).
import 'providers/graph_pending_invitations_provider.dart';
import 'dart:typed_data';

import 'package:image_picker/image_picker.dart' show XFile;

import '../../../core/services/supabase_service.dart';
import 'services/photo_picker_service.dart';
import 'providers/family_graph_provider.dart'
    show FamilyGraphNotifier, familyGraphProvider, unlinkedPersonIdsProvider;
import '../../../graph/interaction/relationship_validation.dart' show graphUndoProvider;
import '../../../core/utils/form_validators.dart';
import '../../../core/utils/api_error_mapper.dart';
import 'add_member_source.dart';
import 'relationship_picker_sheet.dart';
import '../providers/family_invite_provider.dart';

// ─────────────────────────────────────────────────────────────────────
// Add Person Sheet — 4-Step Wizard
//
// Step 0: Basic Info  (name, nickname, gender, DOB, photo)
// Step 1: Relationship to Existing Member
// Step 2: Additional Details (optional, collapsible)
// Step 3: Confirmation + submit
//
// Edit mode: simplified single-page flow.
// ─────────────────────────────────────────────────────────────────────

class AddPersonSheet extends ConsumerStatefulWidget {
  const AddPersonSheet({
    super.key,
    required this.familyId,
    this.existingPerson,
    this.anchorPerson,
    this.source = AddMemberSource.manual,
    this.prefilledName,
    this.prefilledPhone,
    this.prefilledEmail,
    this.preselectedKinrelUser,
    this.fromGraph = false,
  });

  final String familyId;

  /// When non-null, the sheet is in **edit mode** for this person.
  final Person? existingPerson;

  /// When non-null (and not edit mode), the sheet opens the
  /// "Add relative" flow with this person as the anchor in Step 1.
  final Person? anchorPerson;

  /// How the add-member flow was initiated. Controls which step the
  /// flow starts on and how the person is created in _submit().
  ///   - manual: Step 0 → 1 → 2 → 3 (full manual entry)
  ///   - fromContacts: Step 0 (prefilled) → 1 → 2 → 3
  ///   - findOnKinrel: Step 1 → 2 → 3 (skip Step 0, link to existing user)
  final AddMemberSource source;

  /// Pre-filled name (from contacts or Kinrel search).
  final String? prefilledName;

  /// Pre-filled phone (from contacts).
  final String? prefilledPhone;

  /// Pre-filled email (from contacts).
  final String? prefilledEmail;

  /// Pre-selected Kinrel user (from "Find on Kinrel" search).
  /// When non-null, the sheet skips Step 0 and links the new Person
  /// to this Kinrel user's auth account via `linkedUserId`.
  final KinrelUser? preselectedKinrelUser;

  /// v5.41: When true, the sheet was opened from the Family Graph
  /// (e.g. long-press a node → "Invite"). If the user provides a phone
  /// OR email on Step 2 (More Details), the submit logic routes to
  /// `fn_create_graph_pending_invitation` instead of creating a Person
  /// node. This keeps the graph clean — only confirmed members appear.
  ///
  /// When false (the default — Family Space origin), the sheet creates
  /// a Person node as before. The new member appears as an "unlinked"
  /// node in the graph until a relationship is assigned.
  final bool fromGraph;

  /// Show as a full-screen bottom sheet.
  static Future<void> show(
    BuildContext context, {
    required String familyId,
    Person? existingPerson,
    Person? anchorPerson,
    AddMemberSource source = AddMemberSource.manual,
    String? prefilledName,
    String? prefilledPhone,
    String? prefilledEmail,
    KinrelUser? preselectedKinrelUser,
    bool fromGraph = false,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: KinrelColors.darkBackground,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(KinrelRadius.bottomSheet),
        ),
      ),
      builder: (_) => AddPersonSheet(
        familyId: familyId,
        existingPerson: existingPerson,
        anchorPerson: anchorPerson,
        source: source,
        prefilledName: prefilledName,
        prefilledPhone: prefilledPhone,
        prefilledEmail: prefilledEmail,
        preselectedKinrelUser: preselectedKinrelUser,
        fromGraph: fromGraph,
      ),
    );
  }

  @override
  ConsumerState<AddPersonSheet> createState() => _AddPersonSheetState();
}

class _AddPersonSheetState extends ConsumerState<AddPersonSheet>
    with TickerProviderStateMixin {
  // ── Step tracking ──────────────────────────────────────────────
  int _currentStep = 0;
  static const int _kStepCount = 4; // 0-3

  // ── Controllers ────────────────────────────────────────────────
  final _nameController = TextEditingController();
  final _nicknameController = TextEditingController();
  final _dobController = TextEditingController();
  final _anniversaryController = TextEditingController();
  final _cityController = TextEditingController();
  final _gotraController = TextEditingController();
  final _birthPlaceController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _occupationController = TextEditingController();
  final _bioController = TextEditingController();

  // ── State ──────────────────────────────────────────────────────
  String _selectedGender = 'male';
  String? _selectedRelType; // parent | child | spouse | sibling
  String? _selectedSubType; // elder | younger (siblings only)
  String? _selectedRelationshipKey; // full key from RelationshipPickerSheet
  String? _selectedRelationshipLabel;
  // v5.12: Target person picker — the user explicitly chooses WHICH
  // existing member the new person relates to. When null and no
  // anchorPerson was passed, the user hasn't picked a target yet.
  Person? _selectedTargetPerson;
  // v80: Custom kinship state
  String? _customKinshipName;
  int _customNodeColorValue = 0xFF64748B; // default slate
  int _customLineColorValue = 0xFF64748B; // default slate
  String _customLineType = 'solid'; // solid | dashed
  String _customDotType = 'dot'; // dot | heart | none
  bool _isDeceased = false;
  bool _isSubmitting = false;

  /// v5.198: When true, the "More" section (Search all kinship terms +
  /// Add Your Own Kinship) is expanded inline below the 2x3 chip grid.
  /// Tapping the "More" chip toggles this; tapping any other chip
  /// (Parent/Child/Sibling/Spouse/Grandparent) collapses it back
  /// since the user has chosen a primary category.
  bool _showMoreKinship = false;

  /// v5.202: When true, the "locked" tooltip is shown below the
  /// "Related to" field for non-admin/non-creator members. Tapping
  /// the locked field toggles this; tapping elsewhere dismisses it.
  bool _showLockedTooltip = false;

  /// v5.200: ScrollController for the quick-add SingleChildScrollView.
  /// Used to auto-scroll the "More kinship terms" panel into view when
  /// the "More" chip is tapped and the section expands — otherwise the
  /// newly revealed content renders below the visible viewport with no
  /// scroll, and the user sees no visible change (assumes the tap did
  /// nothing).
  final ScrollController _quickAddScrollController = ScrollController();

  /// v5.200: GlobalKey for the "More kinship terms" panel. Used by
  /// the auto-scroll logic to find the panel's position in the
  /// scroll view and scroll it into view.
  final GlobalKey _moreSectionKey = GlobalKey();

  /// v5.200: Caches the family creator's user ID so the admin/creator
  /// role check can work even when familyDetailProvider hasn't loaded
  /// yet (or returned null). Fetched once on initState via a direct
  /// Supabase query to the Family table. This is the root-cause fix
  /// for the "Related to" field not rendering for admin/creator
  /// accounts — the previous code relied solely on
  /// familyDetailProvider, which could return null while loading
  /// (or if the family wasn't in the cached list), leaving isCreator
  /// permanently false.
  String? _cachedFamilyCreatorId;

  /// Stable key for the edit-mode form (NOT recreated on every rebuild).
  /// The previous code created GlobalKey<FormState>() inline in
  /// _buildEditModeContent, which caused the Form to lose its state on
  /// every keystroke (because onChanged → setState → rebuild → new key).
  final _editFormKey = GlobalKey<FormState>();
  DateTime? _selectedDob;
  DateTime? _selectedAnniversary;
  DateTime? _selectedDeathDate;
  bool _locationExpanded = false;
  bool _contactExpanded = false;
  bool _personalExpanded = false;
  bool _showSuccess = false;
  // v5.41: Custom success message for the graph-invitation flow
  // (overrides the default "Welcome to the family!" message).
  String? _successMessage;

  // ── Confetti particles ─────────────────────────────────────────
  final _confettiParticles = <_ConfettiParticle>[];
  late final AnimationController _confettiCtrl;

  bool get _isEditMode => widget.existingPerson != null;

  /// Resolve the effective anchor person for relationship creation.
  /// v5.13: Priority is now:
  ///   1. _selectedTargetPerson (user explicitly picked via UI)
  ///   2. widget.anchorPerson (passed from node context menu)
  ///   3. First existing member (anchor or oldest) — last resort fallback
  Person? get _effectiveAnchorPerson {
    // v5.13: User-selected target takes priority
    if (_selectedTargetPerson != null) return _selectedTargetPerson;
    if (widget.anchorPerson != null) return widget.anchorPerson;
    // Only auto-resolve in add mode (not edit mode)
    if (_isEditMode) return null;
    // Try to find the first existing member in the family
    final membersAsync = ref.read(familyMembersProvider(widget.familyId));
    final existingMembers = membersAsync.valueOrNull;
    if (existingMembers == null || existingMembers.isEmpty) return null;
    // Prefer the anchor person, then fall back to the first member
    final anchor = existingMembers.firstWhere(
      (m) => m.isAnchor,
      orElse: () => existingMembers.first,
    );
    return anchor;
  }

  /// Whether the family members provider is still loading.
  /// Used to prevent the user from skipping Step 1 while we
  /// don't yet know if there are existing members.
  bool get _isFamilyMembersLoading {
    if (_isEditMode) return false;
    final membersAsync = ref.read(familyMembersProvider(widget.familyId));
    return membersAsync.isLoading;
  }

  /// Whether the family has existing members (definitively).
  /// Returns false only when we are certain there are no members.
  /// Returns true if members exist OR if we're still loading OR if the
  /// fetch errored (conservative: assume members exist until proven otherwise).
  ///
  /// v4.7: Added hasError check. When familyMembersProvider throws (e.g. RLS
  /// permission error on an unclaimed/anonymous session), valueOrNull is null,
  /// which previously caused this to return false — meaning "no existing
  /// members" — even though the anchor person clearly exists. This caused
  /// relationships to be skipped (no Relationship row inserted, no edge drawn).
  /// Now we treat error the same as loading: conservative (assume members exist).
  bool get _familyHasExistingMembers {
    if (_isEditMode) return false;
    final membersAsync = ref.read(familyMembersProvider(widget.familyId));
    // Conservative: assume members exist while loading OR if the fetch
    // errored (e.g. RLS/auth issue on an unclaimed/anonymous session).
    // Only return false when we have a definitive, successful empty result.
    if (membersAsync.hasError) return true;
    if (membersAsync.isLoading) return true;
    final existingMembers = membersAsync.valueOrNull;
    return existingMembers != null && existingMembers.isNotEmpty;
  }

  /// v5.197 (ROLE-GATE): Returns true if the current user is the
  /// family CREATOR (Family.createdBy == currentUserId) OR holds an
  /// admin/owner role on the family's FamilyMember row. This gates
  /// the editable "Related to" anchor picker — regular members never
  /// see it (their additions are always anchored to themselves).
  ///
  /// Conservative while loading: returns false during the brief
  /// loading window before memberships/family data arrives. This
  /// means a regular member may see the picker NOT render for one
  /// frame before the data resolves — but they will NEVER see the
  /// picker render then disappear (which would be the flashing bug
  /// the loading-state fix in v5.197 is designed to prevent). Admins/
  /// creators, on the other hand, will see the picker appear after
  /// the data loads, which is the expected behavior.
  ///
  /// Pattern follows the canonical admin/creator check from
  /// family_detail_screen.dart (lines 411-422):
  ///   - isCreator = family.createdBy != null && family.createdBy == currentUserId
  ///   - isAdmin = currentUserMembership?.isAdmin == true (role == 'admin' || 'owner')
  ///   - return isCreator || isAdmin
  bool get _isCurrentUserAdminOrCreator {
    final currentUserId =
        ref.read(supabaseProvider)?.auth.currentUser?.id;
    if (currentUserId == null) return false;

    // Check 1: Family.createdBy == currentUserId (creator).
    final familyAsync = ref.read(familyDetailProvider(widget.familyId));
    final family = familyAsync.valueOrNull?.family;
    if (family != null &&
        family.createdBy != null &&
        family.createdBy == currentUserId) {
      return true;
    }

    // Check 2: FamilyMember role is 'admin' or 'owner'.
    final membershipsAsync =
        ref.read(familyMembershipsProvider(widget.familyId));
    final memberships = membershipsAsync.valueOrNull;
    if (memberships == null) return false; // Still loading or error.
    final currentUserMembership = memberships
        .where((m) => m.userId == currentUserId)
        .firstOrNull;
    return currentUserMembership?.isAdmin ?? false;
  }

  @override
  void initState() {
    super.initState();
    _confettiCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );

    if (_isEditMode) {
      final p = widget.existingPerson!;
      _nameController.text = p.name;
      _selectedGender = p.gender ?? 'male';
      _dobController.text = p.dateOfBirth ?? '';
      _cityController.text = p.city ?? '';
      _gotraController.text = p.gotra ?? '';
      _occupationController.text = p.occupation ?? '';
      _bioController.text = p.notes ?? '';
      _isDeceased = p.isDeceased;

      if (p.dateOfBirth != null && p.dateOfBirth!.isNotEmpty) {
        try {
          _selectedDob = DateTime.parse(p.dateOfBirth!);
        } catch (_) {}
      }
      // Hydrate anniversary date in edit mode
      _anniversaryController.text = p.anniversaryDate ?? '';
      if (p.anniversaryDate != null && p.anniversaryDate!.isNotEmpty) {
        try {
          _selectedAnniversary = DateTime.parse(p.anniversaryDate!);
        } catch (_) {}
      }
    } else {
      // ── Pre-fill data from contacts or Kinrel search ─────────────
      // For fromContacts: pre-fill name, phone, email from the picked
      // contact. The user can edit these in Step 0.
      // For findOnKinrel: pre-fill name from the selected Kinrel user
      // and skip Step 0 entirely (jump to Step 1 = Relationship).
      if (widget.prefilledName != null) {
        _nameController.text = widget.prefilledName!;
      }
      if (widget.prefilledPhone != null) {
        _phoneController.text = widget.prefilledPhone!;
      }
      if (widget.prefilledEmail != null) {
        _emailController.text = widget.prefilledEmail!;
      }

      // For findOnKinrel, also pre-fill gender if available
      if (widget.preselectedKinrelUser != null) {
        final user = widget.preselectedKinrelUser!;
        if (user.name.isNotEmpty) {
          _nameController.text = user.name;
        }
        if (user.gender != null && user.gender!.isNotEmpty) {
          _selectedGender = user.gender!;
        }
        // Skip Step 0 (Basic Info) — jump directly to Step 1 (Relationship)
        // because the person already exists on Kinrel.
        _currentStep = 1;

        // v5.42: Duplicate-member guard. Schedule a post-frame check
        // to see if this Kinrel user is already a member of this family.
        // If so, show an error dialog and pop the sheet — the user
        // cannot re-add an existing member.
        //
        // This is a defense-in-depth check: the Find on Kinrel search
        // screen already shows an "Already Added" badge and disables
        // the Add button, but a race condition or direct navigation
        // could still land the user here.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _checkDuplicateKinrelUser(user);
        });
      }
    }

    // v5.44: Auto-select the logged-in user as the default "Related To"
    // target when the sheet is opened from the Family Graph (fromGraph=true)
    // and no anchorPerson was explicitly passed.
    //
    // This eliminates the friction of requiring the user to manually
    // select themselves as the relationship target. The picker remains
    // editable — the user can still tap it to choose a different family
    // member if needed.
    if (widget.fromGraph && widget.anchorPerson == null && !_isEditMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _autoSelectViewerAsTarget();
      });
    }

    // v5.200: Fetch the family creator's user ID via a direct Supabase
    // query. This is the root-cause fix for the "Related to" field not
    // rendering for admin/creator accounts — the previous code relied
    // solely on familyDetailProvider, which could return null while
    // loading (or if the family wasn't in the cached list), leaving
    // isCreator permanently false. By fetching the createdBy field
    // directly and caching it in _cachedFamilyCreatorId, the admin/
    // creator check works reliably regardless of the
    // familyDetailProvider's loading state.
    if (!_isEditMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _fetchFamilyCreatorId();
      });
    }
  }

  /// v5.200: Fetches the Family.createdBy field via a direct Supabase
  /// query and caches it in [_cachedFamilyCreatorId]. Triggers a
  /// setState so the sheet rebuilds and the "Related to" picker
  /// appears for the creator.
  Future<void> _fetchFamilyCreatorId() async {
    if (_cachedFamilyCreatorId != null) return; // Already fetched.
    try {
      final client = ref.read(supabaseProvider);
      if (client == null) return;
      final response = await client
          .from('Family')
          .select('createdBy')
          .eq('id', widget.familyId)
          .maybeSingle()
          .timeout(const Duration(seconds: 5));
      if (response != null && mounted) {
        setState(() {
          _cachedFamilyCreatorId = response['createdBy'] as String?;
        });
        debugPrint('[ADD-MEMBER] v5.200: Cached family creator ID: $_cachedFamilyCreatorId');
      }
    } catch (e) {
      debugPrint('[ADD-MEMBER] v5.200: Could not fetch family creator: $e');
    }
  }

  /// v5.44: Auto-selects the currently logged-in user's Person as the
  /// default "Related To" target. Called from initState when the sheet
  /// is opened from the Family Graph.
  void _autoSelectViewerAsTarget() {
    // Only auto-select if the user hasn't already picked a target
    if (_selectedTargetPerson != null) return;

    final viewerId = ref.read(viewerPersonIdProvider(widget.familyId)).valueOrNull;
    if (viewerId == null) return;

    final members = ref.read(familyMembersProvider(widget.familyId)).valueOrNull;
    if (members == null || members.isEmpty) return;

    final viewerPerson = members.where((m) => m.id == viewerId).firstOrNull;
    if (viewerPerson != null) {
      setState(() {
        _selectedTargetPerson = viewerPerson;
      });
      debugPrint('[ADD-MEMBER] v5.44: Auto-selected viewer as target: '
          '${viewerPerson.name} (${viewerPerson.id})');
    }
  }

  /// v5.42: Checks if the given Kinrel user is already a member of this
  /// family. If so, shows an error dialog and pops the sheet.
  void _checkDuplicateKinrelUser(KinrelUser user) {
    final existingIds = ref.read(familyLinkedUserIdsProvider(widget.familyId));
    if (existingIds.contains(user.id)) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          backgroundColor: KinrelColors.darkCard,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(KinrelSpacing.radiusLg),
          ),
          title: Text(
            'Already in family',
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: KinrelColors.textWhite,
            ),
          ),
          content: Text(
            '${user.name} is already a member of this family. '
            'You cannot add them again.',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 14,
              color: KinrelColors.textSilver,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                if (mounted) {
                  Navigator.of(context).pop();
                }
              },
              child: Text(
                'OK',
                style: TextStyle(color: KinrelColors.orange),
              ),
            ),
          ],
        ),
      );
    }
  }

  @override
  void dispose() {
    _confettiCtrl.dispose();
    _quickAddScrollController.dispose();
    _nameController.dispose();
    _nicknameController.dispose();
    _dobController.dispose();
    _anniversaryController.dispose();
    _cityController.dispose();
    _gotraController.dispose();
    _birthPlaceController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _occupationController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  // ── Navigation ─────────────────────────────────────────────────

  bool _canProceed() {
    switch (_currentStep) {
      case 0:
        return nameValidator(_nameController.text) == null;
      case 1:
        // v5.42: The relationship requirement depends on the origin:
        //
        //   • Graph origin (fromGraph == true): A relationship IS
        //     required — the new member must be connected to the graph
        //     immediately (linked node). The user cannot proceed to
        //     Step 2 without selecting a relationship type.
        //
        //   • Family Space origin (fromGraph == false): A relationship
        //     is NOT required. The user can skip Step 1's relationship
        //     picker entirely and the Person will be created as an
        //     UNLINKED node. They can assign a relationship later via
        //     the unlinked-members sheet.
        //
        // This matches the new spec:
        //   "Member Added From Family Graph + kinship selected → linked node"
        //   "Member Added From Family Space → unlinked member"
        if (_familyHasExistingMembers && widget.fromGraph) {
          return _effectiveRelationshipKey != null;
        }
        // Family Space origin OR family has no existing members:
        // relationship is optional, user can always proceed.
        return true;
      case 2:
        return true; // Additional details are optional
      case 3:
        return true;
      default:
        return false;
    }
  }

  void _nextStep() {
    if (_currentStep < _kStepCount - 1 && _canProceed()) {
      setState(() => _currentStep++);
    }
  }

  void _prevStep() {
    if (_currentStep > 0) {
      setState(() => _currentStep--);
    }
  }

  // ── Date picking ───────────────────────────────────────────────

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDob ?? DateTime(now.year - 30),
      firstDate: DateTime(1900),
      lastDate: now,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.dark(
              primary: KinrelColors.orange,
              surface: KinrelColors.darkElevated,
              onSurface: KinrelColors.textWhite,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _selectedDob = picked;
        _dobController.text = picked.toIso8601String().split('T').first;
      });
    }
  }

  Future<void> _pickAnniversaryDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedAnniversary ?? DateTime(now.year - 5),
      firstDate: DateTime(1900),
      lastDate: now,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.dark(
              primary: KinrelColors.orange,
              surface: KinrelColors.darkElevated,
              onSurface: KinrelColors.textWhite,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _selectedAnniversary = picked;
        _anniversaryController.text =
            picked.toIso8601String().split('T').first;
      });
    }
  }

  Future<void> _pickDeathDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDeathDate ?? now,
      firstDate: DateTime(1900),
      lastDate: now,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.dark(
              primary: KinrelColors.orange,
              surface: KinrelColors.darkElevated,
              onSurface: KinrelColors.textWhite,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _selectedDeathDate = picked);
    }
  }

  // ── Relationship picking ───────────────────────────────────────

  Future<void> _pickDetailedRelationship() async {
    final anchor = _effectiveAnchorPerson;
    final result = await RelationshipPickerSheet.show(
      context,
      personAName: anchor?.name,
      personBName: _nameController.text.trim().isNotEmpty
          ? _nameController.text.trim()
          : null,
    );
    if (result != null) {
      setState(() {
        _selectedRelationshipKey = result;
        _selectedRelationshipLabel = result.snakeToTitle;
        _selectedRelType = null;   // ← clears simple card so no confusion
        _selectedSubType = null;
        _customKinshipName = null; // clear custom if user picks a standard term
        // v5.199: Collapse the "More" section after a selection is
        // made from within it (per the user's request: "selecting an
        // option from within it should collapse it back").
        _showMoreKinship = false;
      });
    }
  }

  // v80: Show the custom kinship dialog
  Future<void> _showCustomKinshipDialog() async {
    final nameController = TextEditingController(text: _customKinshipName);
    var nodeColor = _customNodeColorValue;
    var lineColor = _customLineColorValue;
    var lineType = _customLineType;
    var dotType = _customDotType;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: KinrelColors.darkCard,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(KinrelSpacing.radiusLg),
          ),
          title: Text(
            'Add Your Own Kinship',
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: KinrelColors.textWhite,
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Kinship Name
                Text('Kinship Name', style: _labelStyle),
                SizedBox(height: 6),
                TextField(
                  controller: nameController,
                  style: TextStyle(color: KinrelColors.textWhite, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'e.g. Guru, Godfather, Chacha...',
                    hintStyle: TextStyle(color: KinrelColors.textDim),
                    filled: true,
                    fillColor: KinrelColors.darkBackground,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: KinrelColors.textDim.withValues(alpha: 0.2)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: KinrelColors.orange),
                    ),
                  ),
                ),
                SizedBox(height: 20),

                // Node Color
                Text('Node Color', style: _labelStyle),
                SizedBox(height: 6),
                _buildColorPicker(setDialogState, () => nodeColor, (c) {
                  nodeColor = c;
                  setDialogState(() {});
                }),
                SizedBox(height: 16),

                // Connection Line Color
                Text('Connection Line Color', style: _labelStyle),
                SizedBox(height: 6),
                _buildColorPicker(setDialogState, () => lineColor, (c) {
                  lineColor = c;
                  setDialogState(() {});
                }),
                SizedBox(height: 16),

                // Connection Line Type
                Text('Connection Line Type', style: _labelStyle),
                SizedBox(height: 6),
                _buildSegmentedChoice(setDialogState, () => lineType, [
                  ('Solid', 'solid'),
                  ('Dashed', 'dashed'),
                ], (v) { lineType = v; setDialogState(() {}); }),
                SizedBox(height: 16),

                // Relationship Dot
                Text('Relationship Dot', style: _labelStyle),
                SizedBox(height: 6),
                _buildSegmentedChoice(setDialogState, () => dotType, [
                  ('Dot', 'dot'),
                  ('Heart', 'heart'),
                  ('None', 'none'),
                ], (v) { dotType = v; setDialogState(() {}); }),
                SizedBox(height: 20),

                // Preview
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: KinrelColors.darkBackground,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                  ),
                  child: Row(
                    children: [
                      // Node preview
                      Container(
                        width: 40, height: 40,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: KinrelColors.darkSurface,
                          border: Border.all(color: Color(nodeColor), width: 3),
                        ),
                      ),
                      // Line preview
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 4),
                          child: CustomPaint(
                            size: Size(double.infinity, 40),
                            painter: _LinePreviewPainter(
                              color: Color(lineColor),
                              isDashed: lineType == 'dashed',
                              dotType: dotType,
                            ),
                          ),
                        ),
                      ),
                      // Anchor preview
                      Container(
                        width: 40, height: 40,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: KinrelColors.darkSurface,
                          border: Border.all(color: KinrelColors.tealAccent, width: 3),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel', style: TextStyle(color: KinrelColors.textDim)),
            ),
            TextButton(
              onPressed: () {
                if (nameController.text.trim().isNotEmpty) {
                  Navigator.pop(context, {
                    'name': nameController.text.trim(),
                    'nodeColor': nodeColor,
                    'lineColor': lineColor,
                    'lineType': lineType,
                    'dotType': dotType,
                  });
                }
              },
              child: Text('Save', style: TextStyle(color: KinrelColors.orange, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );

    if (result != null) {
      setState(() {
        _customKinshipName = result['name'] as String;
        _customNodeColorValue = result['nodeColor'] as int;
        _customLineColorValue = result['lineColor'] as int;
        _customLineType = result['lineType'] as String;
        _customDotType = result['dotType'] as String;
        // Clear standard selections
        _selectedRelationshipKey = null;
        _selectedRelationshipLabel = null;
        _selectedRelType = null;
        _selectedSubType = null;
        // v5.199: Collapse the "More" section after a selection is
        // made from within it (per the user's request: "selecting an
        // option from within it should collapse it back").
        _showMoreKinship = false;
      });
    }
  }

  TextStyle get _labelStyle => TextStyle(
    fontFamily: KinrelTypography.bodyFont,
    fontSize: 13,
    fontWeight: FontWeight.w600,
    color: KinrelColors.textSilver,
  );

  // v80: Color picker row — 10 preset colors
  Widget _buildColorPicker(StateSetter setDialogState, int Function() getter, Function(int) setter) {
    const colors = [
      0xFF0D9488, // teal (self)
      0xFF3B82F6, // blue (parent)
      0xFFEC4899, // pink (child)
      0xFF8B5CF6, // purple (sibling)
      0xFFF97316, // orange (spouse)
      0xFF6366F1, // indigo (grandparent)
      0xFF06B6D4, // cyan (aunt/uncle)
      0xFF10B981, // emerald (cousin)
      0xFFF59E0B, // amber (in-law)
      0xFF64748B, // slate (extended)
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: colors.map((c) {
        final isSelected = getter() == c;
        return GestureDetector(
          onTap: () { setter(c); setDialogState(() {}); },
          child: Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: Color(c),
              shape: BoxShape.circle,
              border: Border.all(
                color: isSelected ? Colors.white : Colors.transparent,
                width: 3,
              ),
            ),
            child: isSelected
                ? Icon(Icons.check, color: Colors.white, size: 18)
                : null,
          ),
        );
      }).toList(),
    );
  }

  // v80: Segmented choice for line type / dot type
  Widget _buildSegmentedChoice(
    StateSetter setDialogState,
    String Function() getter,
    List<(String, String)> options,
    Function(String) onSelect,
  ) {
    return Wrap(
      spacing: 8,
      children: options.map((opt) {
        final label = opt.$1;
        final value = opt.$2;
        final isSelected = getter() == value;
        return GestureDetector(
          onTap: () => onSelect(value),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected
                  ? KinrelColors.orange.withValues(alpha: 0.15)
                  : KinrelColors.darkBackground,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isSelected
                    ? KinrelColors.orange
                    : KinrelColors.textDim.withValues(alpha: 0.15),
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: isSelected ? KinrelColors.orange : KinrelColors.textSilver,
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }



  /// Resolve the effective relationship key from type + gender + sub-type.
  /// The key describes what the ANCHOR person will be to the new person,
  /// so we use the anchor's gender for parent/child/sibling terms.
  /// Resolves the effective relationship key based on the selected
  /// relationship type and the NEW PERSON's gender.
  ///
  /// The question asked is "How is newName related to anchor?" — so
  /// the key represents the NEW PERSON's relationship TO the anchor.
  /// For example, if the user selects "Parent" and the new person is
  /// male, the key is 'father' (newPerson is the father of anchor).
  ///
  /// CRITICAL FIX: Previously this used the ANCHOR's gender, which
  /// produced the wrong key. For example, if the anchor was male and
  /// the user selected "Sibling", it returned 'brother' — but that
  /// means "anchor is the brother of newPerson", which is the OPPOSITE
  /// of what the question asks. Now it uses the new person's gender.
  String? get _effectiveRelationshipKey {
    // v80: Custom kinship — use the custom name as the key
    if (_customKinshipName != null && _customKinshipName!.isNotEmpty) {
      return 'custom_${_customKinshipName!.toLowerCase().replaceAll(' ', '_')}';
    }
    if (_selectedRelationshipKey != null) return _selectedRelationshipKey;

    // Use the NEW PERSON's gender (not the anchor's) because the
    // question is "How is newName related to anchor?".
    final newPersonGender = _selectedGender;
    switch (_selectedRelType) {
      case 'parent':
        return newPersonGender == 'female' ? 'mother' : 'father';
      case 'child':
        return newPersonGender == 'female' ? 'daughter' : 'son';
      case 'spouse':
        return newPersonGender == 'female' ? 'wife' : 'husband';
      case 'sibling':
        if (_selectedSubType == 'elder') {
          return newPersonGender == 'female' ? 'elder_sister' : 'elder_brother';
        } else if (_selectedSubType == 'younger') {
          return newPersonGender == 'female' ? 'younger_sister' : 'younger_brother';
        }
        return newPersonGender == 'female' ? 'sister' : 'brother';
      // v5.198: Added 'grandparent' to support the new 2x3 chip grid.
      // The Grandparent chip maps to 'grandmother' (female) or
      // 'grandfather' (male/other), matching the gender-aware
      // inference pattern used by the Find on Kinrel picker.
      case 'grandparent':
        return newPersonGender == 'female' ? 'grandmother' : 'grandfather';
      default:
        return null;
    }
  }

  /// v5.11: Maps a specific kinship key (e.g. 'father', 'brother', 'wife')
  /// to the FUNDAMENTAL edge type required by the DB constraint
  /// `relationship_fundamental_edge_check` which only allows:
  ///   'parent', 'spouse', 'adoptive_parent', 'step_parent'
  ///
  /// The specific key is still stored in `labelAtoB` (set by the trigger
  /// from `relationshipKey` → `labelAtoB`, then used by the viewer-aware
  /// RPC for perspective-based label resolution).
  ///
  /// Mapping:
  ///   father/mother/parent/son/daughter/child → 'parent'
  ///   husband/wife/spouse → 'spouse'
  ///   brother/sister/sibling → 'parent' (siblings share parents — the
  ///     fundamental edge between siblings IS the parent edge, but since
  ///     we're creating an edge BETWEEN the siblings, not between sibling
  ///     and parent, we use 'parent' as the closest fundamental type.
  ///     The labelAtoB will carry the specific 'brother'/'sister' label.)
  ///   step_father/step_mother/stepfather/stepmother → 'step_parent'
  ///   adoptive_father/adoptive_mother/adoptive_parent → 'adoptive_parent'
  ///   Everything else → 'parent' (safest fallback — covers grandfather,
  ///     uncle, cousin, etc. which are all derived from parent edges)
  static String _mapToFundamentalEdge(String? specificKey) {
    if (specificKey == null || specificKey.isEmpty) return 'parent';
    final k = specificKey.toLowerCase().trim();

    // Spouse
    if (k == 'husband' || k == 'wife' || k == 'spouse') return 'spouse';

    // Step-parent
    if (k == 'step_father' || k == 'step_mother' ||
        k == 'stepfather' || k == 'stepmother' ||
        k == 'step_parent') return 'step_parent';

    // Adoptive parent
    if (k == 'adoptive_father' || k == 'adoptive_mother' ||
        k == 'adoptive_parent') return 'adoptive_parent';

    // Everything else (father, mother, parent, son, daughter, child,
    // brother, sister, sibling, grandfather, grandmother, uncle, aunt,
    // cousin, nephew, niece, etc.) → 'parent' (the fundamental edge)
    return 'parent';
  }

  /// Human-readable preview sentence.
  /// Shows "NewPerson will be the [label] of Anchor" — matching the
  /// question "How is newName related to anchor?".
  String get _relationshipPreview {
    final key = _effectiveRelationshipKey;
    if (key == null) return '';
    final newName = _nameController.text.trim().isNotEmpty
        ? _nameController.text.trim()
        : 'New Member';
    final anchorName = _effectiveAnchorPerson?.name ?? 'existing member';
    // v80: Use custom kinship name if set
    final label = _customKinshipName ?? _selectedRelationshipLabel ?? key.snakeToTitle;
    return '$newName will be the $label of $anchorName';
  }

  // ── Person-Specific Invite Prompt ──────────────────────────────
  // After saving a manually-added Person with phone/email, show a dialog
  // offering to send a personalized invite that references their specific
  // relationship + name (not the generic family-join link).

  Future<void> _showPersonInvitePrompt(Person person) async {
    final name = person.name;
    final relationshipLabel = _selectedRelationshipLabel ?? _selectedRelType ?? 'family member';
    final hasPhone = _phoneController.text.trim().isNotEmpty;
    final hasEmail = _emailController.text.trim().isNotEmpty;

    final shouldInvite = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF191B2C),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text(
          'Invite $name to Kinrel?',
          style: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Color(0xFFF5F0EE),
          ),
        ),
        content: Text(
          'Send $name a personalized invite to confirm their spot as your '
          '$relationshipLabel in the family tree. '
          '${hasPhone ? '📱 ' : ''}${hasEmail ? '✉️ ' : ''}'
          'They\'ll get a link to claim their profile.',
          style: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 13,
            color: Color(0xFFC9B4A8),
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text(
              'Not Now',
              style: TextStyle(
                fontFamily: 'Inter',
                color: Color(0xFF8A7A72),
              ),
            ),
          ),
          Material(
            color: const Color(0xFFE8612A),
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              onTap: () => Navigator.of(ctx).pop(true),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: const Text(
                  'Send Invite',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    if (shouldInvite == true && mounted) {
      // Get the inviter's name + family name for the personalized message
      final client = ref.read(supabaseProvider);
      final myId = client?.auth.currentUser?.id ?? '';
      final myName = (client?.auth.currentUser?.userMetadata?['name'] as String?) ??
          client?.auth.currentUser?.email ??
          'A family member';

      // Get the family name
      String familyName = 'Family';
      if (client != null) {
        try {
          final famResp = await client
              .from('Family')
              .select('name')
              .eq('id', widget.familyId)
              .single()
              .timeout(const Duration(seconds: 5));
          familyName = (famResp['name'] as String?) ?? 'Family';
        } catch (_) {}
      }

      await ref.read(familyInviteProvider.notifier).sharePersonInvite(
            familyId: widget.familyId,
            personId: person.id,
            personName: name,
            relationshipLabel: relationshipLabel,
            inviterName: myName,
            familyName: familyName,
            recipientPhone: hasPhone ? _phoneController.text.trim() : null,
            recipientEmail: hasEmail ? _emailController.text.trim() : null,
          );
    }
  }

  // v5.43: Creates a pending graph invitation via the
  // fn_create_graph_pending_invitation RPC. This stores the invitation
  // WITHOUT creating a Person node — the graph stays clean until the
  // invitee accepts.
  //
  // Called from _submit() when widget.fromGraph is true AND a relationship
  // was selected. Handles both the "Find on Kinrel" flow (recipientUserId
  // is set) and the "Add Manually" flow (phone/email is set).
  Future<void> _createGraphPendingInvitation({
    required String targetPersonId,
    required String relationshipKey,
    required String specificLabel,
  }) async {
    final messenger = ScaffoldMessenger.maybeOf(context);

    // v5.43: Determine the recipient. For Find on Kinrel, use the
    // preselectedKinrelUser's ID. For manual adds, use phone/email.
    final String? recipientUserId = widget.preselectedKinrelUser?.id;
    final String? recipientEmail = _emailController.text.trim().isEmpty
        ? null
        : _emailController.text.trim();
    final String? recipientPhone = _phoneController.text.trim().isEmpty
        ? null
        : _phoneController.text.trim();

    // Validate that we have at least one way to reach the recipient.
    if (recipientUserId == null &&
        (recipientEmail == null || recipientEmail.isEmpty) &&
        (recipientPhone == null || recipientPhone.isEmpty)) {
      if (mounted) setState(() => _isSubmitting = false);
      messenger?.showSnackBar(
        const SnackBar(
          content: Text('Please provide an email, phone number, or use '
              '"Find on Kinrel" to send an invitation.'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 4),
        ),
      );
      return;
    }

    // v5.44: Check for existing pending invitation BEFORE calling the RPC.
    // This prevents the generic "Could not send invitation" error and
    // shows a clear "Invitation already pending" message instead.
    final pendingInvitations =
        ref.read(graphPendingInvitationsProvider(widget.familyId)).valueOrNull ?? [];
    final existingInvitation = findPendingInvitationForRecipient(
      pendingInvitations,
      recipientUserId: recipientUserId,
      recipientEmail: recipientEmail,
      recipientPhone: recipientPhone,
    );
    if (existingInvitation != null) {
      if (mounted) setState(() => _isSubmitting = false);
      messenger?.showSnackBar(
        SnackBar(
          content: Text('Invitation already pending for ${_nameController.text.trim()}. '
              'Tap "Invites" on the graph to cancel or resend.'),
          backgroundColor: KinrelColors.amber,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
      return;
    }

    try {
      final notifier = ref.read(
        graphPendingInvitationsProvider(widget.familyId).notifier,
      );
      final result = await notifier.createInvitation(
        familyId: widget.familyId,
        targetPersonId: targetPersonId,
        relationshipKey: relationshipKey,
        specificLabel: specificLabel,
        recipientName: _nameController.text.trim(),
        recipientEmail: recipientEmail,
        recipientPhone: recipientPhone,
        recipientUserId: recipientUserId,
      );

      if (result.success) {
        // v5.46: Success — show a clear success message, NOT an error.
        if (mounted) {
          setState(() {
            _showSuccess = true;
            _isSubmitting = false; // v5.203: reset loading state
            _successMessage = 'Invitation sent! They\'ll appear in the '
                'graph once they accept.';
          });
          // Refresh the pending invitations list.
          ref.invalidate(graphPendingInvitationsProvider(widget.familyId));
        }
        messenger?.showSnackBar(
          SnackBar(
            content: Text('Invitation sent to ${_nameController.text.trim()}. '
                'Waiting for them to accept.'),
            backgroundColor: KinrelColors.tealAccent,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
          ),
        );
      } else if (result.isDuplicateInvitation) {
        // v5.46: Pending invitation already exists — show amber status,
        // NOT a red error.
        if (mounted) setState(() => _isSubmitting = false);
        messenger?.showSnackBar(
          SnackBar(
            content: Text('Invitation already pending for ${_nameController.text.trim()}. '
                'Tap "Invites" on the graph to cancel or resend.'),
            backgroundColor: KinrelColors.amber,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
          ),
        );
      } else if (result.isDuplicateMember) {
        // v5.46: The recipient is already a family member.
        if (mounted) setState(() => _isSubmitting = false);
        messenger?.showSnackBar(
          SnackBar(
            content: Text('${_nameController.text.trim()} is already a member '
                'of this family.'),
            backgroundColor: KinrelColors.amber,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
          ),
        );
      } else {
        // v5.46: Genuine failure (network error, validation error, etc.)
        if (mounted) setState(() => _isSubmitting = false);
        messenger?.showSnackBar(
          SnackBar(
            content: Text(result.message),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
      messenger?.showSnackBar(
        SnackBar(
          content: Text('Invitation failed: $e'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  // ── Submit ─────────────────────────────────────────────────────

  Future<void> _submit() async {
    // v5.205: Guard against double-submit. If _isSubmitting is already
    // true, the button is disabled, but a fast double-tap could still
    // fire _submit twice before setState propagates. This early return
    // prevents duplicate member creation from rapid retries.
    if (_isSubmitting) return;
    if (_nameController.text.trim().isEmpty) return;

    // v5.205: Set _isSubmitting = true IMMEDIATELY (before any async
    // work) so the button is disabled on the very next frame, not
    // after the first await. This is the critical timing fix that
    // prevents duplicate requests from tap-and-hold/retry sequences.
    if (mounted) {
      setState(() => _isSubmitting = true);
    }

    try {
      // v5.47: Manual Add = Graph-Only Node (no invitation).
      //
      // PER THE LATEST REQUIREMENTS:
      //   • Add Manually (source == manual) → create a Person node + Relationship
      //     edge directly in the graph. NO invitation, NO email/phone required.
      //     Manual members are graph-only placeholders.
      //   • Find on Kinrel (source == findOnKinrel) → send a PENDING INVITATION
      //     to the selected Kinrel user. No Person node is created until they accept.
      //   • From Contacts (source == fromContacts) → send a PENDING INVITATION
      //     using the contact's phone/email. No Person node is created.
      //
      // The `fromGraph` flag indicates the entry point (graph vs family space),
      // but the `source` flag determines whether to invite or create directly.
      if (widget.fromGraph && !_isEditMode &&
          (widget.source == AddMemberSource.findOnKinrel ||
           widget.source == AddMemberSource.fromContacts)) {
        final relKey = _effectiveRelationshipKey;
        final targetPerson = _selectedTargetPerson ?? widget.anchorPerson;

        if (relKey == null) {
          if (mounted) setState(() => _isSubmitting = false);
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            const SnackBar(
              content: Text('Please select a relationship to send an invitation.'),
              backgroundColor: Colors.redAccent,
              behavior: SnackBarBehavior.floating,
            ),
          );
          return;
        }

        if (targetPerson == null) {
          if (mounted) setState(() => _isSubmitting = false);
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            const SnackBar(
              content: Text('Please select who they are related to.'),
              backgroundColor: Colors.redAccent,
              behavior: SnackBarBehavior.floating,
            ),
          );
          return;
        }

        // Route to the pending invitation system (Find on Kinrel / From Contacts only).
        await _createGraphPendingInvitation(
          targetPersonId: targetPerson.id,
          relationshipKey: _mapToFundamentalEdge(relKey),
          specificLabel: relKey,
        );
        return; // Do NOT fall through to Person creation.
      }

      // Family Space origin (fromGraph == false): create a Person node.
      // The relationship creation block below is skipped (v5.42 logic),
      // so the Person appears as an UNLINKED node.
      Person? result;

      // v94 (EDGE BUG FIX): Track whether the relationship creation
      // failed so we can suppress the success flow (confetti,
      // "Welcome to the family") when the compound mutation is
      // incomplete. The Person was created but the edge wasn't —
      // showing success would mislead the user. Declared in the outer
      // try scope so it's visible to the success-gate below.
      var relationshipFailed = false;

      if (_isEditMode) {
        await updatePersonOptimistic(
          ref: ref,
          personId: widget.existingPerson!.id,
          familyId: widget.familyId,
          name: _nameController.text.trim(),
          gender: _selectedGender,
          dateOfBirth: _dobController.text.trim().isEmpty
              ? null
              : _dobController.text.trim(),
          anniversaryDate: _anniversaryController.text.trim().isEmpty
              ? null
              : _anniversaryController.text.trim(),
          city: _cityController.text.trim().isEmpty
              ? null
              : _cityController.text.trim(),
          gotra: _gotraController.text.trim().isEmpty
              ? null
              : _gotraController.text.trim(),
          isDeceased: _isDeceased,
        );
        if (kEnablePhotoPicker && _pickedPhoto != null) {
          await _uploadPickedPhoto(widget.existingPerson!.id);
        }
      } else {
        // v20 FIX: If this is the first member of the family, set isAnchor=true
        // so the graph layout has an anchor to center on. Without an anchor,
        // the graph may render blank because the layout doesn't know where
        // to position nodes.
        //
        // v38 BUG-11 FIX: AWAIT the familyMembersProvider before deciding
        // isFirstMember. Previously, _familyHasExistingMembers returned true
        // while the provider was still loading — causing the first member
        // to be created with isAnchor=false. The graph then had no anchor
        // to center on → blank/displaced graph.
        bool isFirstMember = !_familyHasExistingMembers;
        if (!isFirstMember) {
          // The provider might still be loading — wait for it to settle
          // before making the final decision.
          try {
            final members = await ref
                .read(familyMembersProvider(widget.familyId).future);
            isFirstMember = members.isEmpty;
          } catch (e) {
            debugPrint('[ADD-MEMBER] Could not await familyMembersProvider: $e');
            // Fall back to the synchronous check — if it said "has members",
            // we trust it. If it said "no members", we also trust it.
          }
        }
        // Double-check by querying Person count directly from Supabase
        // (authoritative — the provider may have stale cached data)
        if (!isFirstMember) {
          try {
            final client = ref.read(supabaseProvider);
            if (client != null) {
              final count = await client
                  .from('Person')
                  .select('id')
                  .eq('familyId', widget.familyId)
                  .isFilter('deletedAt', null)
                  .count();
              isFirstMember = count == 0;
              debugPrint('[ADD-MEMBER] Direct Person count: $count → isFirstMember=$isFirstMember');
            }
          } catch (e) {
            debugPrint('[ADD-MEMBER] Direct Person count failed: $e');
          }
        }

        // v94 (EDGE BUG FIX): Compute the relationship key BEFORE creating
        // the Person so we can decide whether to refresh the graph during
        // Person creation. When a relationship WILL be created (non-first
        // member + relKey != null), we pass `refreshGraph: false` to
        // createPersonOptimistic so the graph does NOT refresh into a
        // Person-only intermediate state. The graph refresh happens ONCE
        // after the Relationship INSERT succeeds, via an awaited
        // authoritative refresh + optimistic upsert.
        final preComputedRelKey = _effectiveRelationshipKey;
        final willCreateRelationship =
            !isFirstMember && preComputedRelKey != null;

        result = await createPersonOptimistic(
          ref: ref,
          familyId: widget.familyId,
          name: _nameController.text.trim(),
          gender: _selectedGender,
          dateOfBirth: _dobController.text.trim().isEmpty
              ? null
              : _dobController.text.trim(),
          anniversaryDate: _anniversaryController.text.trim().isEmpty
              ? null
              : _anniversaryController.text.trim(),
          city: _cityController.text.trim().isEmpty
              ? null
              : _cityController.text.trim(),
          gotra: _gotraController.text.trim().isEmpty
              ? null
              : _gotraController.text.trim(),
          isDeceased: _isDeceased,
          isAnchor: isFirstMember, // ← v20/v38: First member is always the anchor
          // v94: Don't refresh the graph between Person and Relationship
          // writes — the compound mutation will refresh once after the
          // edge is created.
          refreshGraph: !willCreateRelationship,
        );

        // ═══════════════════════════════════════════════════════════════
        // LINK TO KINREL USER (findOnKinrel source only)
        // ═══════════════════════════════════════════════════════════════
        // When the user selected an existing Kinrel user via "Find on
        // Kinrel", we link the new Person node to that user's auth
        // account by setting `linkedUserId` on the Person row. This
        // lets the linked user log in and see this family from their
        // own perspective (viewer-perspective graph).
        if (widget.source == AddMemberSource.findOnKinrel &&
            widget.preselectedKinrelUser != null &&
            result != null) {
          try {
            final client = ref.read(supabaseProvider);
            if (client != null) {
              await client
                  .from('Person')
                  .update({
                    'linkedUserId': widget.preselectedKinrelUser!.id,
                    'linkedAt': DateTime.now().toUtc().toIso8601String(),
                  })
                  .eq('id', result.id)
                  .timeout(const Duration(seconds: 10));
              debugPrint(
                  '[ADD-MEMBER] Linked Person ${result.id} to Kinrel user ${widget.preselectedKinrelUser!.id}');
            }
          } catch (e) {
            // Non-fatal — the Person was created, just the link failed.
            // The user can re-link later via the claim flow.
            debugPrint('[ADD-MEMBER] Failed to link Kinrel user: $e');
          }
        }

        // ═══════════════════════════════════════════════════════════════
        // v7 (2026-06-19): RELATIONSHIP CREATION — DIRECT SUPABASE QUERY
        // ═══════════════════════════════════════════════════════════════
        // The previous implementation relied on `_effectiveAnchorPerson`
        // which reads from `familyMembersProvider`. This provider might
        // not have loaded yet, or might have stale data, causing the
        // anchor to be null and the relationship creation to be
        // SILENTLY SKIPPED.
        //
        // New approach: query the anchor person DIRECTLY from Supabase.
        // This is 100% reliable — no provider timing issues.
        // ═══════════════════════════════════════════════════════════════
        if (kEnablePhotoPicker && _pickedPhoto != null && result != null) {
          await _uploadPickedPhoto(result.id);
        }

        final relKey = preComputedRelKey;

        // v5.53: The relationship-creation block runs for ALL adds where
        // a relationship was selected — regardless of fromGraph.
        //
        // PREVIOUSLY, this was gated on `widget.fromGraph` which meant
        // adds from the Family Space (family detail screen) would SKIP
        // relationship creation, leaving the Person as an unlinked node.
        // This was the root cause of "node appears but no connection line".
        //
        // Now: if the user selected a relationship type AND the Person
        // was created successfully, ALWAYS create the relationship edge.
        // The `fromGraph` flag only controls the invitation routing
        // (Find on Kinrel / From Contacts) above — not this block.
        if (relKey != null && !_isEditMode && result != null) {
          // v94: Capture the non-null result in a local variable so
          // dart2js doesn't lose null-promotion across the await
          // boundaries below. Without this, `result.id` triggers
          // "Property 'id' cannot be accessed on 'Person?'" because
          // dart2js can't prove `result` is still non-null after an
          // await inside a nested try block.
          final newPerson = result;
          final resultId = newPerson.id;
          final resultName = newPerson.name;
          final resultGender = newPerson.gender;
          final resultPhotoUrl = newPerson.photoUrl;
          final resultIsDeceased = newPerson.isDeceased;
          try {
            final client = ref.read(supabaseProvider);
            if (client != null && client.auth.currentSession != null) {
              debugPrint('[ADD-MEMBER] v94: Creating relationship with key=$relKey');

              // v5.49: Target person resolution — USER-SELECTED first.
              // Priority:
              //   1. _selectedTargetPerson (user explicitly picked via UI)
              //   2. widget.anchorPerson (passed from node context menu)
              //   3. Viewer's own Person (await viewerPersonIdProvider)
              //   4. DB anchor fallback (last resort)
              String? linkToPersonId;

              if (_selectedTargetPerson != null) {
                // v5.12: User explicitly picked a target person
                linkToPersonId = _selectedTargetPerson!.id;
                debugPrint('[ADD-MEMBER] v5.12: Using user-selected target: ${_selectedTargetPerson!.name} ($linkToPersonId)');
              } else if (widget.anchorPerson != null) {
                // User opened Add from a specific node's context menu
                linkToPersonId = widget.anchorPerson!.id;
                debugPrint('[ADD-MEMBER] v94: Using provided anchorPerson: ${widget.anchorPerson!.name} ($linkToPersonId)');
              } else {
                // v5.49: Try to resolve the VIEWER'S own Person first.
                // This is the most common case — the user is adding a
                // family member relative to themselves. The auto-selection
                // in initState may have failed if viewerPersonIdProvider
                // hadn't resolved yet, so we AWAIT it here.
                try {
                  final viewerId = await ref.read(
                    viewerPersonIdProvider(widget.familyId).future,
                  ).timeout(const Duration(seconds: 5));
                  if (viewerId != null && viewerId.isNotEmpty) {
                    linkToPersonId = viewerId;
                    debugPrint('[ADD-MEMBER] v5.49: Using viewer Person as target: $linkToPersonId');
                  }
                } catch (e) {
                  debugPrint('[ADD-MEMBER] v5.49: Viewer resolution failed: $e');
                }

                // If viewer resolution failed, fall back to DB anchor
                if (linkToPersonId == null || linkToPersonId.isEmpty) {
                  final familyData = await client
                      .from('Family')
                      .select('anchorPersonId')
                      .eq('id', widget.familyId)
                      .maybeSingle()
                      .timeout(const Duration(seconds: 5));

                  linkToPersonId = familyData?['anchorPersonId'] as String?;

                  // If no anchorPersonId, query ALL existing persons
                  if (linkToPersonId == null || linkToPersonId.isEmpty || linkToPersonId == resultId) {
                    debugPrint('[ADD-MEMBER] v94: No valid anchorPersonId, querying existing members...');
                    final existingPersons = await client
                        .from('Person')
                        .select('id, name, gender, "isAnchor"')
                        .eq('familyId', widget.familyId)
                        .neq('id', resultId)
                        .isFilter('deletedAt', null)
                        .order('createdAt', ascending: true)
                        .limit(10)
                        .timeout(const Duration(seconds: 5));

                    if (existingPersons.isNotEmpty) {
                      final anchor = existingPersons.firstWhere(
                        (p) => p['isAnchor'] == true,
                        orElse: () => existingPersons.first,
                      );
                      linkToPersonId = anchor['id'] as String?;
                      debugPrint('[ADD-MEMBER] v94: Found link target: ${anchor['name']} ($linkToPersonId)');
                    }
                  } else {
                    debugPrint('[ADD-MEMBER] v94: Using family anchorPersonId: $linkToPersonId');
                  }
                }
              }

              if (linkToPersonId != null && linkToPersonId.isNotEmpty && linkToPersonId != resultId) {
                // CRITICAL FIX: The relationship question asks "How is
                // newName related to anchor?" — so the user is saying
                // "newPerson IS the [brother/father/etc] OF anchor".
                // The relationship must be stored as:
                //   from: newPerson (resultId), to: anchor (linkToPersonId)
                //   key: relKey (e.g. 'brother' = newPerson is brother of anchor)
                debugPrint('[ADD-MEMBER] v94: Creating relationship: from=$resultId (new) to=$linkToPersonId (anchor) key=$relKey');

                // v5.11 FIX: The relationship_fundamental_edge_check DB
                // constraint ONLY allows 'parent', 'spouse',
                // 'adoptive_parent', 'step_parent' in the relationshipKey
                // column. But relKey is a SPECIFIC key like 'father',
                // 'brother', 'wife' — which would be REJECTED by the
                // constraint, silently failing the INSERT and leaving
                // the new person unlinked.
                //
                // The fix: map the specific key to the FUNDAMENTAL edge
                // type for relationshipKey, while keeping the specific
                // key in labelAtoB (which the viewer-aware RPC uses for
                // perspective-based label resolution).
                final fundamentalKey = _mapToFundamentalEdge(relKey);
                debugPrint('[ADD-MEMBER] v5.11: Mapped $relKey → $fundamentalKey (fundamental edge)');

                // v94 (EDGE BUG FIX): Create the relationship with
                // `refreshGraph: false` — we do NOT want createRelationship
                // to clear the graph cache + invalidate the provider here.
                // The compound mutation will do ONE authoritative refresh
                // after this returns, and the optimistic upsert below
                // ensures the edge appears immediately in the provider
                // state (not just the cache).
                // v5.19: Use shared buildCanonicalRelationshipEdge to ensure
                // this flow and relationship_picker_flow.dart produce
                // IDENTICAL edges for the same semantic input.
                final edgeInput = buildCanonicalRelationshipEdge(
                  referencePersonId: linkToPersonId,
                  describedPersonId: resultId,
                  pickedRelationshipKey: relKey!,
                  referencePersonGender: widget.anchorPerson?.gender ?? _selectedTargetPerson?.gender,
                  describedPersonGender: _selectedGender,
                );

                // v5.55: TEMPORARY debug dialog
                if (kShowRelationshipDebugBanner && mounted) {
                  await showDialog(
                    context: context,
                    barrierDismissible: false,
                    builder: (ctx) => AlertDialog(
                      backgroundColor: KinrelColors.darkCard,
                      title: Text('DEBUG: Relationship Inputs',
                        style: TextStyle(color: KinrelColors.orange, fontSize: 16, fontWeight: FontWeight.w700)),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('relKey: "$relKey"', style: TextStyle(color: KinrelColors.textWhite, fontSize: 13, fontFamily: 'monospace')),
                          SizedBox(height: 6),
                          Text('result.id: "$resultId"', style: TextStyle(color: KinrelColors.textWhite, fontSize: 13, fontFamily: 'monospace')),
                          SizedBox(height: 6),
                          Text('result.name: "$resultName"', style: TextStyle(color: KinrelColors.textWhite, fontSize: 13, fontFamily: 'monospace')),
                          SizedBox(height: 6),
                          Text('linkToPersonId: "$linkToPersonId"', style: TextStyle(color: KinrelColors.textWhite, fontSize: 13, fontFamily: 'monospace')),
                          SizedBox(height: 6),
                          Text('widget.fromGraph: ${widget.fromGraph}', style: TextStyle(color: KinrelColors.textWhite, fontSize: 13, fontFamily: 'monospace')),
                          SizedBox(height: 6),
                          Text('edgeInput.from: "${edgeInput.fromPersonId}"', style: TextStyle(color: KinrelColors.textWhite, fontSize: 13, fontFamily: 'monospace')),
                          SizedBox(height: 6),
                          Text('edgeInput.to: "${edgeInput.toPersonId}"', style: TextStyle(color: KinrelColors.textWhite, fontSize: 13, fontFamily: 'monospace')),
                          SizedBox(height: 6),
                          Text('edgeInput.key: "${edgeInput.relationshipKey}"', style: TextStyle(color: KinrelColors.textWhite, fontSize: 13, fontFamily: 'monospace')),
                          SizedBox(height: 6),
                          Text('edgeInput.label: "${edgeInput.specificLabelAtoB}"', style: TextStyle(color: KinrelColors.textWhite, fontSize: 13, fontFamily: 'monospace')),
                          SizedBox(height: 6),
                          Text('familyId: "${widget.familyId}"', style: TextStyle(color: KinrelColors.textWhite, fontSize: 13, fontFamily: 'monospace')),
                        ],
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          child: Text('Continue', style: TextStyle(color: KinrelColors.orange)),
                        ),
                      ],
                    ),
                  );
                }

                await createRelationship(
                  ref: ref,
                  familyId: widget.familyId,
                  fromPersonId: edgeInput.fromPersonId,
                  toPersonId: edgeInput.toPersonId,
                  relationshipKey: edgeInput.relationshipKey,
                  specificLabelAtoB: edgeInput.specificLabelAtoB,
                  fromPersonGender: edgeInput.fromPersonGender,
                  toPersonGender: edgeInput.toPersonGender,
                  // v83: Pass custom kinship colors + display name
                  customColors: _customKinshipName != null
                      ? {
                          'nodeColor': _customNodeColorValue,
                          'lineColor': _customLineColorValue,
                          'lineType': _customLineType,
                          'dotType': _customDotType,
                        }
                      : null,
                  customDisplayName: _customKinshipName,
                  // v94: Do NOT refresh the graph inside createRelationship
                  // — the compound mutation handles it below.
                  refreshGraph: false,
                  // v5.56: Debug callback — shows checkpoint dialogs
                  debugCallback: kShowRelationshipDebugBanner && mounted
                      ? (String message) async {
                          await showDialog(
                            context: context,
                            barrierDismissible: false,
                            builder: (ctx) => AlertDialog(
                              backgroundColor: KinrelColors.darkCard,
                              title: Text('DEBUG: createRelationship()',
                                style: TextStyle(color: KinrelColors.orange, fontSize: 14, fontWeight: FontWeight.w700)),
                              content: SingleChildScrollView(
                                child: Text(message,
                                  style: TextStyle(color: KinrelColors.textWhite, fontSize: 12, fontFamily: 'monospace')),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.of(ctx).pop(),
                                  child: Text('Continue', style: TextStyle(color: KinrelColors.orange)),
                                ),
                              ],
                            ),
                          );
                        }
                      : null,
                );
                debugPrint('[ADD-MEMBER] v94: ✅ Relationship created successfully');

                // v94 (EDGE BUG FIX): Optimistically upsert the person +
                // edge into the CURRENT provider state via the notifier
                // instance method. Unlike the old injectOptimisticEdge
                // (which silently no-op'd when cache was null), this
                // mutates `state = AsyncData(updated)` directly so
                // Riverpod rebuilds dependents IMMEDIATELY. The edge
                // appears in the graph BEFORE the authoritative refetch
                // lands, and is robust to a null cache.
                //
                // v5.48: Pass the FUNDAMENTAL edge key (not the specific
                // label) so the optimistic state matches what the DB will
                // return after the authoritative refresh. Previously,
                // passing 'father' (specific) instead of 'parent'
                // (fundamental) caused the edge to be deduplicated
                // incorrectly or disappear when the refresh replaced
                // the optimistic state.
                try {
                  ref
                      .read(familyGraphProvider(widget.familyId).notifier)
                      .upsertPersonAndEdge(
                        personId: resultId,
                        personName: resultName,
                        gender: resultGender,
                        relationshipKey: edgeInput.relationshipKey,
                        targetPersonId: linkToPersonId,
                        photoUrl: resultPhotoUrl,
                        isDeceased: resultIsDeceased,
                      );
                  debugPrint('[ADD-MEMBER] v5.48: ✅ Optimistic upsert done — '
                      'key=${edgeInput.relationshipKey}, label=${edgeInput.specificLabelAtoB}');
                } catch (e) {
                  debugPrint('[ADD-MEMBER] v94: Optimistic upsert failed (non-fatal — refetch will recover): $e');
                }

                // v94 (EDGE BUG FIX): Perform ONE awaited authoritative
                // graph refresh. We await `ref.refresh(...).future` so we
                // can verify the new edge is present in the refreshed
                // FlatGraphResult. If it's missing (e.g. eventual-
                // consistency delay), we clear the cache + invalidate
                // again so the next read hits Supabase fresh.
                try {
                  FamilyGraphNotifier.clearCache(widget.familyId);
                  final refreshedGraph = await ref.refresh(
                    familyGraphProvider(widget.familyId).future,
                  );
                  // Verify the edge exists in the refreshed graph.
                  final edgeExists = refreshedGraph.relationships.any((r) {
                    final from = r['fromPersonId']?.toString();
                    final to = r['toPersonId']?.toString();
                    return (from == resultId && to == linkToPersonId) ||
                        (from == linkToPersonId && to == resultId);
                  });
                  if (edgeExists) {
                    debugPrint('[ADD-MEMBER] v94: ✅ Edge verified in refreshed graph');
                  } else {
                    // v5.48: The edge wasn't in the refreshed graph.
                    // The INSERT succeeded (createRelationship would have
                    // thrown otherwise), so this is an eventual-consistency
                    // delay. Schedule a RETRY after 2 seconds so the edge
                    // appears without requiring a manual refresh.
                    debugPrint('[ADD-MEMBER] v5.48: ⚠️ Edge not yet in refreshed graph — scheduling retry in 2s');
                    FamilyGraphNotifier.clearCache(widget.familyId);
                    ref.invalidate(familyGraphProvider(widget.familyId));
                    // v5.48: Schedule a delayed retry to catch up with
                    // Supabase's eventual consistency.
                    Future.delayed(const Duration(seconds: 2), () {
                      if (!mounted) return;
                      debugPrint('[ADD-MEMBER] v5.48: Retrying graph refresh (2s delay)');
                      FamilyGraphNotifier.clearCache(widget.familyId);
                      ref.invalidate(familyGraphProvider(widget.familyId));
                    });
                  }
                } catch (e) {
                  debugPrint('[ADD-MEMBER] v94: Authoritative refresh failed (non-fatal — optimistic state holds): $e');
                  // The optimistic upsert above keeps the edge visible.
                  // Invalidate so the next read retries.
                  FamilyGraphNotifier.clearCache(widget.familyId);
                  ref.invalidate(familyGraphProvider(widget.familyId));
                }
              } else {
                // v5.49: No target person found. The Person was created
                // but has no relationship. Refresh the graph so the Person
                // appears (even if unlinked — the user can link later).
                debugPrint('[ADD-MEMBER] v5.49: ⚠️ No target person found — '
                    'Person created without relationship. Refreshing graph.');
                FamilyGraphNotifier.clearCache(widget.familyId);
                ref.invalidate(familyGraphProvider(widget.familyId));
              }
            } else {
              debugPrint('[ADD-MEMBER] v94: ⚠️ Supabase client or session not available');
              // v5.49: Still refresh the graph so the Person appears.
              FamilyGraphNotifier.clearCache(widget.familyId);
              ref.invalidate(familyGraphProvider(widget.familyId));
            }
          } catch (e, stackTrace) {
            // v5.54: Log the FULL raw error with type info + all fields
            debugPrint('[ADD-MEMBER] v5.54: ❌ Relationship creation failed');
            debugPrint('[ADD-MEMBER] v5.54: Error type: ${e.runtimeType}');
            debugPrint('[ADD-MEMBER] v5.54: Error toString: $e');
            if (e is PostgrestException) {
              debugPrint('[ADD-MEMBER] v5.54: PostgrestException code=${e.code} message=${e.message} details=${e.details} hint=${e.hint}');
            }
            debugPrint('[ADD-MEMBER] v5.54: Stack: $stackTrace');
            relationshipFailed = true;
            if (mounted) {
              // v98 (Phase 0): Compensating rollback — soft-delete the
              // orphan Person so no permanent orphan survives a
              // relationship-creation failure. Uses soft-delete
              // (deletedAt timestamp) matching the existing
              // `.isFilter('deletedAt', null)` pattern, NOT hard delete
              // (Person has onDelete: Cascade from Relationship).
              try {
                final rollbackClient = ref.read(supabaseProvider);
                if (rollbackClient != null && resultId.isNotEmpty) {
                  await rollbackClient
                      .from('Person')
                      .update({
                        'deletedAt': DateTime.now().toUtc().toIso8601String(),
                      })
                      .eq('id', resultId)
                      .timeout(const Duration(seconds: 5));
                  debugPrint('[ADD-MEMBER] v98: Rolled back orphan Person $resultId (soft-deleted)');
                }
              } catch (rollbackError) {
                debugPrint('[ADD-MEMBER] v98: Rollback FAILED — orphan Person $resultId may persist: $rollbackError');
              }
              // Clear graph cache + invalidate so the orphan doesn't render.
              FamilyGraphNotifier.clearCache(widget.familyId);
              ref.invalidate(familyGraphProvider(widget.familyId));
              ref.invalidate(familyMembersProvider(widget.familyId));

              // v5.50: Show the ACTUAL error to the user with full details.
              // The previous code used e.toString() which returned an empty
              // string for PostgrestException — now we extract .message,
              // .code, .details, .hint explicitly.
              String errorDetail;
              if (e is PostgrestException) {
                errorDetail = 'code=${e.code}, message=${e.message}, '
                    'details=${e.details}, hint=${e.hint}';
              } else {
                errorDetail = e.toString();
              }
              final shortError = errorDetail.length > 200
                  ? errorDetail.substring(0, 200) + '...'
                  : errorDetail;
              debugPrint('[ADD-MEMBER] v5.50: Relationship error detail: $errorDetail');
              context.showSnackBar(
                'Could not save the relationship: $shortError. '
                'The member was not added — please try again.',
                isError: true,
              );
            }
          }
        } else if (relKey == null) {
          // v5.53: No relationship selected — create the Person as an
          // unlinked node. This is the only case where a Person should
          // appear without a connection line.
          debugPrint('[ADD-MEMBER] v5.53: No relationship selected — '
              'creating unlinked node.');
          FamilyGraphNotifier.clearCache(widget.familyId);
          ref.invalidate(familyGraphProvider(widget.familyId));
          if (widget.fromGraph) {
            ref.invalidate(unlinkedPersonIdsProvider(widget.familyId));
          }
          // v5.55: Debug dialog — shows WHY the relationship block was skipped
          if (kShowRelationshipDebugBanner && mounted) {
            await showDialog(
              context: context,
              barrierDismissible: false,
              builder: (ctx) => AlertDialog(
                backgroundColor: KinrelColors.darkCard,
                title: Text('DEBUG: Relationship SKIPPED',
                  style: TextStyle(color: Colors.redAccent, fontSize: 16, fontWeight: FontWeight.w700)),
                content: Text(
                  'relKey is NULL — no relationship was selected.\n\n'
                  'result: ${result?.id ?? "NULL"}\n'
                  'fromGraph: ${widget.fromGraph}\n\n'
                  'The Person was created WITHOUT a relationship edge.',
                  style: TextStyle(color: KinrelColors.textWhite, fontSize: 13),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: Text('OK', style: TextStyle(color: KinrelColors.orange)),
                  ),
                ],
              ),
            );
          }
        }
      }

      if (!mounted) return;

      // v94 (EDGE BUG FIX): If the relationship creation failed, do NOT
      // fire confetti or show "Welcome to the family" — the compound
      // mutation is incomplete. The error snackbar was already shown in
      // the catch block above. Keep the sheet open so the user can
      // retry or dismiss manually.
      if (relationshipFailed) {
        if (mounted) {
          setState(() => _isSubmitting = false);
        }
        return;
      }

      // CRITICAL ANR FIX: Consolidated success state updates into single setState
      // Multiple setState calls in sequence caused cascading rebuilds
      unawaited(HapticFeedback.mediumImpact());
      _launchConfetti();

      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _showSuccess = true;
        });
      }

      // v62.5: Reduced from 1800ms to 500ms — the success animation
      // still shows but the sheet closes much faster.
      await Future.delayed(const Duration(milliseconds: 500));

      if (!mounted) return;
      // v99 (Phase 7): Show success snackbar with UNDO action if an
      // undo command was pushed during relationship creation.
      final undoState = ref.read(graphUndoProvider);
      if (undoState.canUndo && !_isEditMode && result != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Welcome to the family, ${result!.name}!'),
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: 'UNDO',
              onPressed: () async {
                final cmd = ref.read(graphUndoProvider.notifier).pop();
                if (cmd == null) return;
                // Perform the inverse: delete the relationship.
                try {
                  final client = ref.read(supabaseProvider);
                  if (client != null && cmd.edgeId != null) {
                    await client
                        .from('Relationship')
                        .delete()
                        .eq('id', cmd.edgeId!)
                        .timeout(const Duration(seconds: 10));
                  }
                  FamilyGraphNotifier.clearCache(widget.familyId);
                  ref.invalidate(familyGraphProvider(widget.familyId));
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Relationship removed.')),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Undo failed: $e')),
                    );
                  }
                }
              },
            ),
          ),
        );
      } else {
        // v5.42: For Family Space origin, use a different success message
        // that tells the user the member was added as unlinked and they
        // can assign a relationship later.
        final successMsg = _isEditMode
            ? 'Person updated successfully'
            : (_successMessage ??
                (widget.fromGraph
                    ? 'Welcome to the family, ${result?.name ?? 'New member'}!'
                    : '${result?.name ?? 'New member'} added. Tap "Link" on '
                      'the graph to connect them to a family member.'));
        context.showSnackBar(successMsg);
      }

      // ═══════════════════════════════════════════════════════════════
      // PERSON-SPECIFIC INVITE PROMPT
      // ═══════════════════════════════════════════════════════════════
      // After saving a manually-added or contact-imported Person (NOT
      // findOnKinrel — that path already links to a real account), if
      // the Person has a phone or email on file, offer to send a
      // personalized invite so they can claim their spot in the tree.
      if (!_isEditMode &&
          widget.source != AddMemberSource.findOnKinrel &&
          result != null &&
          (_phoneController.text.trim().isNotEmpty ||
              _emailController.text.trim().isNotEmpty)) {
        await _showPersonInvitePrompt(result);
      }

      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        // CRITICAL ANR FIX: Single setState for error state
        setState(() => _isSubmitting = false);
        final fieldErrors = mapApiError(e);
        if (fieldErrors != null) {
          final formError = fieldErrors['form'];
          if (formError != null) {
            context.showSnackBar(formError, isError: true);
          } else {
            final firstError = fieldErrors.values.first;
            context.showSnackBar(
              _isEditMode
                  ? 'Failed to update person: $firstError'
                  : 'Failed to add person: $firstError',
              isError: true,
            );
          }
        } else {
          context.showSnackBar(
            _isEditMode
                ? 'Failed to update person: ${e.toString().split('\n').first}'
                : 'Failed to add person: ${e.toString().split('\n').first}',
            isError: true,
          );
        }
      }
    } finally {
      // v5.203: SAFETY NET — always reset the loading state, even if
      // an unexpected code path leaves _isSubmitting = true. This
      // prevents the "Add to Family" button from getting stuck in a
      // permanent spinning/loading state when a save fails (e.g. the
      // "already has a parent" validation error). The success path
      // sets _isSubmitting = false + _showSuccess = true inside the
      // try block (line ~2050), so by the time we reach here, either:
      //   - _showSuccess == true → skip (button is hidden by success view)
      //   - _showSuccess == false → reset _isSubmitting to false so the
      //     button returns to its interactive state and the user can
      //     retry without reloading the page.
      if (mounted && !_showSuccess && _isSubmitting) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  // ── Confetti ───────────────────────────────────────────────────

  void _launchConfetti() {
    final rng = math.Random();
    _confettiParticles.clear();
    for (int i = 0; i < 40; i++) {
      _confettiParticles.add(
        _ConfettiParticle(
          x: rng.nextDouble(),
          y: -0.1 - rng.nextDouble() * 0.3,
          vx: (rng.nextDouble() - 0.5) * 0.004,
          vy: 0.002 + rng.nextDouble() * 0.004,
          size: 4 + rng.nextDouble() * 6,
          color: [
            KinrelColors.orange,
            KinrelColors.amber,
            KinrelColors.brightGold,
            KinrelColors.gold,
            KinrelColors.coral,
            Colors.white,
          ][rng.nextInt(6)],
          rotation: rng.nextDouble() * math.pi * 2,
          rotationSpeed: (rng.nextDouble() - 0.5) * 0.15,
        ),
      );
    }
    _confettiCtrl.forward(from: 0);
  }

  // ── Build ──────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final screenHeight = MediaQuery.of(context).size.height;

    return SizedBox(
      height: screenHeight * 0.94,
      child: Stack(
        children: [
          // Main content
          Padding(
            padding: EdgeInsets.only(
              left: KinrelSpacing.base,
              right: KinrelSpacing.base,
              top: KinrelSpacing.lg,
              bottom: math.max(bottomInset, KinrelSpacing.xl),
            ),
            child: Column(
              children: [
                // Handle bar
                _buildHandleBar(),
                SizedBox(height: 16),

                // Title (no step indicators for quick-add)
                _buildHeader(),
                SizedBox(height: 16),

                // Content
                Expanded(
                  child: _isEditMode
                      ? _buildEditModeContent()
                      : _buildQuickAddContent(),
                ),

                // Bottom action — single "Add to Family" button
                if (!_showSuccess && !_isEditMode) _buildQuickAddButton(),
              ],
            ),
          ),

          // Confetti overlay
          if (_showSuccess)
            Positioned.fill(
              child: IgnorePointer(
                child: KinrelAnimatedBuilder(
                  animation: _confettiCtrl,
                  builder: (context, _) {
                    return CustomPaint(
                      painter: _ConfettiPainter(
                        particles: _confettiParticles,
                        progress: _confettiCtrl.value,
                      ),
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Handle bar ─────────────────────────────────────────────────

  Widget _buildHandleBar() {
    return Center(
      child: Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: KinrelColors.textDim.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────────

  Widget _buildHeader() {
    // v5.52: Simplified header — no step title, no back button
    final title = _isEditMode
        ? 'Edit Person'
        : _showSuccess
        ? 'Welcome! 🎉'
        : 'Add Family Member';

    return Text(
      title,
      style: TextStyle(
        fontFamily: KinrelTypography.displayFont,
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: KinrelColors.textWhite,
      ),
    );
  }

  // ── v5.198: Redesigned Quick Add ──────────────────────────────────
  //
  // v5.198 (REDESIGN): The manual add form was redesigned for speed
  // and minimal friction. Changes:
  //
  //   1. REMOVED "Add Photo" — new members default to an initials
  //      avatar (same style as graph nodes like "A1", "A2"). Photo
  //      upload is available later from the member's profile/edit
  //      screen, not during creation.
  //
  //   2. REORDERED fields to: Full Name → Gender → Relationship Type
  //      → "Add to Family" button. No photo circle above the name.
  //
  //   3. REPLACED the 4-box relationship grid (Parent/Child/Spouse/
  //      Sibling) with the SAME 2x3 chip grid used in the "Find on
  //      Kinrel" relationship picker: Parent, Child, Sibling, Spouse,
  //      Grandparent, More. The interaction pattern is now identical
  //      across both add-member paths.
  //
  //   4. MOVED "Or pick a specific kinship term" (Search all kinship
  //      terms + Add Your Own Kinship) so it is NOT shown by default.
  //      It only appears when the user taps the "More" chip in the
  //      2x3 grid, expanding inline below. Collapses back when a
  //      primary chip is selected.
  //
  //   5. REMOVED the bottom orange error banner ("Please select how
  //      they are related to proceed"). The "Add to Family" button
  //      is now visually disabled (greyed out, non-interactive) until
  //      both Full Name and Relationship Type are filled in. No error
  //      message needed — the disabled button state communicates
  //      this on its own.
  //
  //   6. "Related to" field: per the v5.197 role-gating fix, this
  //      remains hidden for regular members (defaults silently to
  //      their own account via _autoSelectViewerAsTarget) and visible
  //      only for admins/creators.

  Widget _buildQuickAddContent() {
    if (_showSuccess) return _buildSuccessView();
    final anchor = _effectiveAnchorPerson;
    final newName = _nameController.text.trim().isNotEmpty
        ? _nameController.text.trim()
        : 'New Member';

    // v5.199 (BUG FIX): Use ref.watch (not ref.read) for the providers
    // that gate the "Related to" picker so the sheet REBUILDS when the
    // membership/family data arrives. Previously these were read via
    // the _isCurrentUserAdminOrCreator and _familyHasExistingMembers
    // getters, both of which used ref.read — meaning the sheet
    // computed showTargetPicker=false during the initial build (while
    // data was still loading) and never re-evaluated when the data
    // arrived. The "Related to" picker was therefore permanently
    // hidden for admin/creator accounts.
    //
    // Now we watch the providers here (in the build method) so any
    // change in their state triggers a rebuild and the picker appears
    // as soon as the admin/creator status is confirmed.
    final membershipsAsync = ref.watch(familyMembershipsProvider(widget.familyId));
    final familyDetailAsync = ref.watch(familyDetailProvider(widget.familyId));
    final membersAsync = ref.watch(familyMembersProvider(widget.familyId));

    // Compute admin/creator status from the watched providers.
    final currentUserId = ref.read(supabaseProvider)?.auth.currentUser?.id;
    // v5.200 (BUG FIX): Use _cachedFamilyCreatorId as the primary
    // source for the creator check (fetched via a direct Supabase
    // query in initState). The familyDetailProvider-based check
    // is kept as a secondary source — _cachedFamilyCreatorId is
    // populated first (within ~1 second of the sheet opening) and
    // reliably triggers a rebuild via setState, whereas
    // familyDetailProvider can return null while loading or if the
    // family isn't in the cached list, leaving isCreator permanently
    // false. The creator is "current user" if EITHER source confirms
    // the match.
    final familyCreatedBy = familyDetailAsync.valueOrNull?.family.createdBy;
    final bool isCreator = (familyCreatedBy != null && familyCreatedBy == currentUserId) ||
        (_cachedFamilyCreatorId != null && _cachedFamilyCreatorId == currentUserId);
    final bool isAdmin = membershipsAsync.valueOrNull
            ?.where((m) => m.userId == currentUserId)
            .firstOrNull
            ?.isAdmin ??
        false;
    final bool isAdminOrCreator = isCreator || isAdmin;

    // Compute familyHasMembers from the watched provider. Conservative
    // while loading / on error (assume members exist) — same logic
    // as the _familyHasExistingMembers getter but using ref.watch.
    final bool familyHasMembers;
    if (membersAsync.hasError) {
      familyHasMembers = true;
    } else if (membersAsync.isLoading) {
      familyHasMembers = true;
    } else {
      final existingMembers = membersAsync.valueOrNull;
      familyHasMembers = existingMembers != null && existingMembers.isNotEmpty;
    }

    // v5.197: Apply the admin/creator role gate to the "Related to"
    // picker — regular members never see it (their additions are
    // anchored to themselves by default).
    final bool showTargetPicker = widget.anchorPerson == null &&
        !_isEditMode &&
        isAdminOrCreator;

    // v5.201 (DEBUG LOGGING): Log the role-check computation so we
    // can confirm (a) the component IS reached in the render tree,
    // (b) the role check returns the expected admin value for the
    // test account, and (c) it isn't being unintentionally unmounted
    // by the "More" expand/collapse logic. The "Related to" section
    // is NOT nested inside the "More" expansion — it renders as its
    // own separate section between Gender and Relationship Type,
    // completely independent of the "More" chip's expand/collapse state.
    // NOTE: This debugPrint is placed BEFORE the return statement
    // (NOT inside the children list) because debugPrint returns void,
    // not a Widget — placing it inside children would cause a compile
    // error (the previous commit c193ddf8 had this bug, causing the
    // Vercel build to fail).
    debugPrint('[ADD-MEMBER] v5.201: Related-to check -- '
        'isCreator=$isCreator (familyDetail.createdBy=$familyCreatedBy, '
        'cachedCreator=$_cachedFamilyCreatorId, currentUserId=$currentUserId), '
        'isAdmin=$isAdmin, '
        'isAdminOrCreator=$isAdminOrCreator, '
        'showTargetPicker=$showTargetPicker, '
        'familyHasMembers=$familyHasMembers, '
        'anchorPerson=${widget.anchorPerson != null}, '
        'isEditMode=$_isEditMode');

    // v5.200: Use a ScrollController so we can auto-scroll the "More
    // kinship terms" panel into view when the "More" chip is tapped
    // and the section expands (otherwise the newly revealed content
    // renders below the visible viewport with no scroll, and the user
    // sees no visible change — assumes the tap did nothing).
    return SingleChildScrollView(
      controller: _quickAddScrollController,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── #2: Full Name (required, first field, no photo above) ──
          _SectionLabel('Full Name *'),
          SizedBox(height: 6),
          _buildTextField(
            controller: _nameController,
            hint: 'Enter full name',
            isLarge: true,
            keyboardType: TextInputType.name,
            textInputAction: TextInputAction.next,
            validator: (v) => nameValidator(v),
          ),
          // v5.201: Inline validation hint — shows below the name
          // field when the name is invalid (e.g. contains characters
          // not allowed by the validator). This replaces the old
          // bottom-of-form orange error banner that was removed in
          // v5.198. Without this hint, the user sees the "Add to
          // Family" button stay disabled with no explanation.
          if (nameValidator(_nameController.text) != null &&
              _nameController.text.trim().isNotEmpty) ...[
            SizedBox(height: 4),
            Text(
              nameValidator(_nameController.text) ?? '',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 12,
                color: KinrelColors.orange,
              ),
            ),
          ],
          SizedBox(height: 20),

          // ── #2: Gender (unchanged) ──
          _SectionLabel('Gender'),
          SizedBox(height: 10),
          _buildGenderCards(),
          SizedBox(height: 20),

          // ── "Related to" anchor selector ──
          // v5.202: The "Related to" field is now ALWAYS visible when
          // the family has members (not just for admins/creators).
          //   - ADMIN/CREATOR: fully interactive picker (can change the
          //     target account).
          //   - REGULAR MEMBER: locked/disabled visual state (greyed
          //     out, non-editable) showing the current default value
          //     (the auto-selected viewer/"Me"). Tapping shows a brief
          //     inline tooltip: "Only admins or family creators can
          //     change who this connects to."
          //   - ANCHOR PASSED (from node context menu): read-only label
          //     showing the passed anchor person's name.
          // The debug logging for the role check is in the method body
          // above (before the return statement).
          if (familyHasMembers && showTargetPicker) ...[
            _SectionLabel('Related to'),
            SizedBox(height: 8),
            _buildTargetPersonPicker(),
            SizedBox(height: 20),
          ] else if (widget.anchorPerson != null) ...[
            _SectionLabel('Related to'),
            SizedBox(height: 8),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: KinrelColors.darkCard,
                borderRadius: BorderRadius.circular(KinrelSpacing.radiusMd),
                border: Border.all(
                  color: KinrelColors.orange.withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.person, color: KinrelColors.orange, size: 20),
                  SizedBox(width: 10),
                  Text(
                    widget.anchorPerson!.name,
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: KinrelColors.textWhite,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 20),
          ] else if (familyHasMembers && !isAdminOrCreator && !_isEditMode) ...[
            // v5.202: Locked "Related to" for regular members.
            _SectionLabel('Related to'),
            SizedBox(height: 8),
            _buildLockedTargetPersonPicker(),
            if (_showLockedTooltip) ...[
              SizedBox(height: 6),
              _buildLockedTooltip(),
            ],
            SizedBox(height: 20),
          ],

          // ── #2 + #3: Relationship Type (2x3 chip grid) ──
          if (familyHasMembers || widget.anchorPerson != null) ...[
            _SectionLabel('Relationship Type'),
            SizedBox(height: 8),
            if (anchor != null)
              Text(
                'How is $newName related to ${anchor.name}?',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 14,
                  color: KinrelColors.textSilver,
                  height: 1.4,
                ),
              ),
            SizedBox(height: 12),

            // #3: The 2x3 chip grid (same component as Find on Kinrel).
            _buildQuickAddChipGrid(),
            SizedBox(height: 16),

            // Sibling sub-type (Elder / Younger) — shown when the
            // Sibling chip is selected. Kept from the old design since
            // it's a useful refinement for the most common sibling case.
            if (_selectedRelType == 'sibling') ...[
              _SectionLabel('Elder or Younger?'),
              SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _SelectableCard(
                      label: 'Elder',
                      subtitle: 'Older sibling',
                      icon: Icons.arrow_upward,
                      selected: _selectedSubType == 'elder',
                      onTap: () => setState(() => _selectedSubType = 'elder'),
                    ),
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: _SelectableCard(
                      label: 'Younger',
                      subtitle: 'Younger sibling',
                      icon: Icons.arrow_downward,
                      selected: _selectedSubType == 'younger',
                      onTap: () => setState(() => _selectedSubType = 'younger'),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 16),
            ],

            // #4: "More" section — Search all kinship terms + Add Your
            // Own Kinship. NOT shown by default; only expands when the
            // "More" chip is tapped. Collapses when a primary chip is
            // selected instead.
            if (_showMoreKinship) ...[
              _buildMoreKinshipSection(),
              SizedBox(height: 16),
            ],

            // Visual preview (kept — useful feedback when a rel type
            // is selected).
            if (_relationshipPreview.isNotEmpty) ...[
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: KinrelColors.orange.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(KinrelSpacing.radiusMd),
                  border: Border.all(
                    color: KinrelColors.orange.withValues(alpha: 0.2),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.visibility_outlined,
                        color: KinrelColors.orange, size: 18),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _relationshipPreview,
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 14,
                          color: KinrelColors.textWhite,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 16),
            ],

            // #5: REMOVED the orange/teal error banner. The disabled
            // "Add to Family" button now communicates the validation
            // state on its own.
          ] else if (!familyHasMembers) ...[
            Text(
              'This is the first member of the family. No relationship needed yet.',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 16,
                color: KinrelColors.textSilver,
              ),
            ),
          ],

          SizedBox(height: 24),
        ],
      ),
    );
  }

  // ── #3: 2x3 chip grid for Relationship Type ────────────────────────
  //
  // v5.198: Same 2x3 layout as the "Find on Kinrel" relationship
  // picker (relationship_quick_pick_sheet.dart). Order:
  //   Row 1: Parent  | Child
  //   Row 2: Sibling | Spouse
  //   Row 3: Grandparent | More
  //
  // Tapping any primary chip (Parent/Child/Sibling/Spouse/Grandparent)
  // sets _selectedRelType and clears the "More" expansion. Tapping
  // "More" toggles the inline "Search all kinship terms" + "Add Your
  // Own Kinship" section below the grid.
  //
  // Gender-based label inference is handled by the existing
  // _effectiveRelationshipKey getter (parent + female → 'mother',
  // sibling + male → 'brother', etc.) — unchanged from before.

  static const double _kRelChipWidth = 158;
  static const double _kRelChipHeight = 48;

  Widget _buildQuickAddChipGrid() {
    final chips = <Widget>[];

    // Primary chips in the exact 2x3 order: Parent, Child, Sibling,
    // Spouse, Grandparent. The "More" chip is the 6th item.
    final primaryCategories = <_RelChipDef>[
      _RelChipDef(
        type: 'parent',
        label: 'Parent',
        icon: Icons.family_restroom,
      ),
      _RelChipDef(
        type: 'child',
        label: 'Child',
        icon: Icons.child_care,
      ),
      _RelChipDef(
        type: 'sibling',
        label: 'Sibling',
        icon: Icons.people,
      ),
      _RelChipDef(
        type: 'spouse',
        label: 'Spouse',
        icon: Icons.favorite,
      ),
      _RelChipDef(
        type: 'grandparent',
        label: 'Grandparent',
        icon: Icons.elderly,
      ),
    ];

    for (final cat in primaryCategories) {
      final bool isSelected = _selectedRelType == cat.type;
      chips.add(
        _RelChip(
          label: cat.label,
          icon: cat.icon,
          isSelected: isSelected,
          width: _kRelChipWidth,
          height: _kRelChipHeight,
          onTap: () => setState(() {
            _selectedRelType = cat.type;
            _selectedSubType = null;
            _selectedRelationshipKey = null;
            _selectedRelationshipLabel = null;
            // #4: Collapses the "More" section when a primary chip is
            // selected instead.
            _showMoreKinship = false;
            // v5.202: Dismiss the locked "Related to" tooltip when the
            // user interacts with a relationship chip.
            _showLockedTooltip = false;
          }),
        ),
      );
    }

    // The 6th slot is the "More" chip — toggles the inline expansion
    // of the Search-all / Add-Your-Own-Kinship section.
    chips.add(
      _RelChip(
        label: 'More',
        icon: Icons.more_horiz,
        isSelected: _showMoreKinship,
        width: _kRelChipWidth,
        height: _kRelChipHeight,
        isMore: true,
        onTap: () {
          setState(() {
            _showMoreKinship = !_showMoreKinship;
            // Tapping "More" doesn't clear the primary selection — the
            // user might be exploring alternatives. But if they then
            // pick a specific kinship term from the expanded section,
            // _pickDetailedRelationship clears _selectedRelType.
          });
          // v5.200: Auto-scroll the "More kinship terms" panel into
          // view when it expands — otherwise the newly revealed
          // content renders below the visible viewport with no
          // scroll, and the user sees no visible change (assumes the
          // tap did nothing). Only scrolls on expand (not collapse).
          // Uses addPostFrameCallback so the scroll runs AFTER the
          // setState rebuild has mounted the panel (so the
          // _moreSectionKey has a render object to measure).
          if (_showMoreKinship) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _scrollToMoreSection();
            });
          }
        },
      ),
    );

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: chips,
    );
  }

  // ── #4: "More" section (Search all + Add Your Own Kinship) ──────────
  //
  // v5.198: Only rendered when _showMoreKinship is true (toggled by
  // the "More" chip in the 2x3 grid). Contains the same two tappable
  // rows as before — "Search all kinship terms…" and "Add Your Own
  // Kinship" — but now they're collapsed by default.

  Widget _buildMoreKinshipSection() {
    return Container(
      key: _moreSectionKey,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: KinrelColors.orange.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(KinrelSpacing.radiusMd),
        border: Border.all(
          color: KinrelColors.orange.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'More kinship terms',
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: KinrelColors.textWhite,
            ),
          ),
          const SizedBox(height: 12),

          // Search all kinship terms
          GestureDetector(
            onTap: _pickDetailedRelationship,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                color: KinrelColors.darkCard,
                borderRadius: BorderRadius.circular(KinrelSpacing.radiusMd),
                border: Border.all(
                  color: _selectedRelationshipLabel != null
                      ? KinrelColors.orange.withValues(alpha: 0.4)
                      : KinrelColors.textDim.withValues(alpha: 0.15),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.search, color: KinrelColors.orange, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _selectedRelationshipLabel ?? 'Search all kinship terms…',
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 14,
                        color: _selectedRelationshipLabel != null
                            ? KinrelColors.textWhite
                            : KinrelColors.textDim,
                      ),
                    ),
                  ),
                  Icon(Icons.chevron_right,
                      color: KinrelColors.textDim, size: 18),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Add Your Own Kinship
          GestureDetector(
            onTap: _showCustomKinshipDialog,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                color: KinrelColors.darkCard,
                borderRadius: BorderRadius.circular(KinrelSpacing.radiusMd),
                border: Border.all(
                  color: _customKinshipName != null
                      ? KinrelColors.orange.withValues(alpha: 0.4)
                      : KinrelColors.textDim.withValues(alpha: 0.15),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.palette_outlined,
                      color: KinrelColors.purple, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _customKinshipName ?? 'Add Your Own Kinship',
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 14,
                        color: _customKinshipName != null
                            ? KinrelColors.textWhite
                            : KinrelColors.textDim,
                      ),
                    ),
                  ),
                  Icon(Icons.chevron_right,
                      color: KinrelColors.textDim, size: 18),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// v5.200: Auto-scrolls the "More kinship terms" panel into view
  /// using a smooth animation. Called after the "More" chip is tapped
  /// and the section expands (via addPostFrameCallback so the panel
  /// has been mounted and has a render object to measure).
  ///
  /// Uses Flutter's built-in `Scrollable.ensureVisible` which handles
  /// all the coordinate math (finding the nearest Scrollable ancestor,
  /// computing the target scroll offset, and animating to it). The
  /// `alignment: 0.0` aligns the top of the panel with the top of the
  /// viewport; `duration: 300ms` + `Curve.easeOut` gives a smooth
  /// scroll (not an instant jump). If the panel is already visible,
  /// `ensureVisible` is a no-op.
  void _scrollToMoreSection() {
    if (!mounted) {
      debugPrint('[ADD-MEMBER] v5.201: _scrollToMoreSection — not mounted, skipping');
      return;
    }
    final context = _moreSectionKey.currentContext;
    if (context == null) {
      debugPrint('[ADD-MEMBER] v5.201: _scrollToMoreSection — _moreSectionKey.currentContext is null '
          '(panel not yet mounted in the render tree)');
      return;
    }
    debugPrint('[ADD-MEMBER] v5.201: _scrollToMoreSection — calling Scrollable.ensureVisible');
    Scrollable.ensureVisible(
      context,
      alignment: 0.0, // Top of panel aligns with top of viewport.
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  /// Single "Add to Family" button — no steps, no "Next".
  ///
  /// v5.198: Updated `canSubmit` logic — the button is now disabled
  /// (greyed out, non-interactive) until BOTH Full Name and
  /// Relationship Type are filled in. This replaces the previous
  /// bottom-of-form orange error banner ("Please select how they are
  /// related to proceed") — the disabled button state communicates
  /// the validation on its own. No error message needed.
  ///
  /// The previous logic was:
  ///   canSubmit = nameValidator(name) == null &&
  ///     (!_familyHasExistingMembers || !widget.fromGraph || _effectiveRelationshipKey != null)
  ///
  /// The new logic is simpler and consistent across both add paths:
  ///   - First member of the family (no existing members): only Name
  ///     is required (relationship is optional/skipped).
  ///   - Subsequent members: BOTH Name AND a relationship selection
  ///     are required. The relationship can come from any of the
  ///     three sources: a primary chip in the 2x3 grid
  ///     (_effectiveRelationshipKey derives it from _selectedRelType
  ///     + gender + sibling subtype), the "Search all" picker
  ///     (_selectedRelationshipKey), or "Add Your Own Kinship"
  ///     (_customKinshipName).
  Widget _buildQuickAddButton() {
    final bool nameValid = nameValidator(_nameController.text) == null;
    // v5.199: Use ref.watch (not the ref.read-based getter) so the
    // button rebuilds when the family-members data arrives. This
    // ensures canSubmit flips from false→true the moment the data
    // confirms this is the first member (no existing members).
    final membersAsync = ref.watch(familyMembersProvider(widget.familyId));
    final bool isFirstMember;
    if (membersAsync.hasError || membersAsync.isLoading) {
      isFirstMember = false; // Conservative: assume NOT first member
                             // while loading so the button stays
                             // disabled until the data resolves.
    } else {
      final existing = membersAsync.valueOrNull;
      isFirstMember = existing == null || existing.isEmpty;
    }
    final bool hasRelationship = _effectiveRelationshipKey != null;
    final bool canSubmit = nameValid && (isFirstMember || hasRelationship);

    // v5.201 (DEBUG LOGGING): Log the button-state computation so we
    // can verify the canSubmit logic is reading the correct form
    // state. The user reported the button stays disabled even with
    // valid input (name + relationship selected, preview text visible).
    // This log will show whether nameValid is false (the most likely
    // root cause — the nameValidator regex was rejecting underscores
    // in names like "manual_1") or whether hasRelationship is null.
    debugPrint('[ADD-MEMBER] v5.201: Button state — '
        'name="${_nameController.text}", '
        'nameValid=$nameValid, '
        'isFirstMember=$isFirstMember, '
        'hasRelationship=$hasRelationship (key=${_effectiveRelationshipKey}), '
        'selectedRelType=$_selectedRelType, '
        'selectedGender=$_selectedGender, '
        'canSubmit=$canSubmit');

    return Padding(
      padding: EdgeInsets.only(top: 12),
      child: _buildIgniteButton(
        label: _isSubmitting ? '' : 'Add to Family',
        onPressed: _isSubmitting || !canSubmit ? null : _submit,
        isLoading: _isSubmitting,
      ),
    );
  }

  String get _stepTitle {
    switch (_currentStep) {
      case 0:
        return 'Add Family Member';
      case 1:
        return 'Relationship';
      case 2:
        return 'More Details';
      case 3:
        return 'Confirm';
      default:
        return 'Add Family Member';
    }
  }

  // ── Step indicators ────────────────────────────────────────────

  Widget _buildStepIndicators() {
    return Row(
      children: List.generate(_kStepCount, (i) {
        final isActive = i == _currentStep;
        final isCompleted = i < _currentStep;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: i < _kStepCount - 1 ? 6 : 0),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              height: 3,
              decoration: BoxDecoration(
                color: isCompleted
                    ? KinrelColors.orange
                    : isActive
                    ? KinrelColors.orange.withValues(alpha: 0.6)
                    : KinrelColors.textDim.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        );
      }),
    );
  }

  // ── Edit mode content ──────────────────────────────────────────

  Widget _buildEditModeContent() {
    return SingleChildScrollView(
      child: Form(
        key: _editFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Name
            _SectionLabel('Full Name *'),
            SizedBox(height: 6),
            _buildTextField(
              controller: _nameController,
              hint: 'Full name',
              isLarge: true,
              keyboardType: TextInputType.name,
              textInputAction: TextInputAction.next,
              textCapitalization: TextCapitalization.words,
              validator: (v) => nameValidator(v),
            ),
            SizedBox(height: 16),

            // Gender
            _SectionLabel('Gender'),
            SizedBox(height: 8),
            _buildGenderCards(),
            SizedBox(height: 16),

            // DOB
            _SectionLabel('Date of Birth'),
            SizedBox(height: 6),
            _buildDateField(),
            SizedBox(height: 16),

            // Anniversary (optional)
            _SectionLabel('Anniversary Date (optional)'),
            SizedBox(height: 6),
            _buildAnniversaryField(),
            SizedBox(height: 16),

            // City
            _SectionLabel('City / Village'),
            SizedBox(height: 6),
            _buildTextField(
              controller: _cityController,
              hint: 'City or village',
            ),
            SizedBox(height: 16),

            // Gotra
            _SectionLabel('Gotra'),
            SizedBox(height: 6),
            _buildTextField(controller: _gotraController, hint: 'Gotra'),
            SizedBox(height: 16),

            // Occupation
            _SectionLabel('Occupation'),
            SizedBox(height: 6),
            _buildTextField(
              controller: _occupationController,
              hint: 'Occupation',
            ),
            SizedBox(height: 16),

            // Deceased
            _buildDeceasedToggle(),
            SizedBox(height: 28),

            // Save button
            _buildIgniteButton(
              label: 'Save Changes',
              onPressed: _isSubmitting ? null : _submit,
              isLoading: _isSubmitting,
            ),
          ],
        ),
      ),
    );
  }

  // ── Step content ───────────────────────────────────────────────

  Widget _buildStepContent() {
    if (_showSuccess) return _buildSuccessView();

    switch (_currentStep) {
      case 0:
        return _buildStep0BasicInfo();
      case 1:
        return _buildStep1Relationship();
      case 2:
        return _buildStep2AdditionalDetails();
      case 3:
        return _buildStep3Confirmation();
      default:
        return const SizedBox.shrink();
    }
  }

  // ── STEP 0: Basic Info ─────────────────────────────────────────

  Widget _buildStep0BasicInfo() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Photo picker (gated by kEnablePhotoPicker)
          if (kEnablePhotoPicker) ...[
            Center(child: _buildPhotoPicker()),
            SizedBox(height: 24),
          ],

          // Full name (large, prominent)
          _SectionLabel('Full Name *'),
          SizedBox(height: 6),
          _buildTextField(
            controller: _nameController,
            hint: 'Enter full name',
            isLarge: true,
            keyboardType: TextInputType.name,
            textInputAction: TextInputAction.next,
            textCapitalization: TextCapitalization.words,
            validator: (v) => nameValidator(v),
          ),
          SizedBox(height: 16),

          // Nickname
          _SectionLabel('Nickname'),
          SizedBox(height: 6),
          _buildTextField(
            controller: _nicknameController,
            hint: 'Optional nickname',
          ),
          SizedBox(height: 20),

          // Gender
          _SectionLabel('Gender'),
          SizedBox(height: 8),
          _buildGenderCards(),
          SizedBox(height: 20),

          // Date of Birth
          _SectionLabel('Date of Birth'),
          SizedBox(height: 6),
          _buildDateField(),
        ],
      ),
    );
  }

  /// Locally-picked avatar; uploaded on submit when kEnablePhotoPicker is on.
  XFile? _pickedPhoto;

  Widget _buildPhotoPicker() {
    return GestureDetector(
      onTap: () async {
        HapticFeedback.lightImpact();
        if (!kEnablePhotoPicker) {
          context.showSnackBar('Photo picker coming soon');
          return;
        }
        final picked = await PhotoPickerService.pickWithSheet(context);
        if (picked != null && mounted) {
          setState(() => _pickedPhoto = picked);
        }
      },
      child: Container(
        width: 96,
        height: 96,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: KinrelGradients.igniteGradient,
        ),
        child: Container(
          margin: EdgeInsets.all(3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: KinrelColors.darkElevated,
          ),
          child: ClipOval(child: _buildPhotoPickerInner()),
        ),
      ),
    );
  }

  Widget _buildPhotoPickerInner() {
    if (kEnablePhotoPicker && _pickedPhoto != null) {
      return FutureBuilder<Uint8List>(
        future: _pickedPhoto!.readAsBytes(),
        builder: (context, snap) {
          if (snap.hasData) {
            return Image.memory(
              snap.data!,
              width: 96,
              height: 96,
              fit: BoxFit.cover,
            );
          }
          return const Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        },
      );
    }
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.camera_alt_outlined,
            color: KinrelColors.textSilver,
            size: 24,
          ),
          SizedBox(height: 2),
          Text(
            'Add Photo',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 10,
              color: KinrelColors.textDim,
            ),
          ),
        ],
      ),
    );
  }

  /// Uploads the locally-picked avatar (if any) and writes its URL onto the
  /// Person row. Uses a direct Supabase update — same pattern as relationship
  /// creation in [_submit]. Never throws; falls back to initials on failure.
  Future<void> _uploadPickedPhoto(String personId) async {
    final photo = _pickedPhoto;
    if (photo == null) return;
    final url = await PhotoPickerService.uploadAvatar(photo);
    if (url == null) return;
    try {
      final client = ref.read(supabaseProvider);
      await client?.from('Person').update({'photoUrl': url}).eq('id', personId);
    } catch (e) {
      debugPrint('[ADD-MEMBER] photo url update failed: $e');
    }
  }

  Widget _buildGenderCards() {
    return Row(
      children: [
        Expanded(
          child: _GenderCard(
            label: 'Male',
            icon: Icons.male,
            selected: _selectedGender == 'male',
            onTap: () => setState(() => _selectedGender = 'male'),
          ),
        ),
        SizedBox(width: 10),
        Expanded(
          child: _GenderCard(
            label: 'Female',
            icon: Icons.female,
            selected: _selectedGender == 'female',
            onTap: () => setState(() => _selectedGender = 'female'),
          ),
        ),
        SizedBox(width: 10),
        Expanded(
          child: _GenderCard(
            label: 'Other',
            icon: Icons.person,
            selected: _selectedGender == 'other',
            onTap: () => setState(() => _selectedGender = 'other'),
          ),
        ),
      ],
    );
  }

  Widget _buildDateField() {
    return GestureDetector(
      onTap: _pickDate,
      child: AbsorbPointer(
        child: TextFormField(
          controller: _dobController,
          keyboardType: TextInputType.datetime,
          textInputAction: TextInputAction.next,
          textCapitalization: TextCapitalization.none,
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 15,
            color: KinrelColors.textWhite,
          ),
          decoration: _inputDecoration('YYYY-MM-DD').copyWith(
            suffixIcon: Icon(
              Icons.calendar_today_outlined,
              color: KinrelColors.textDim,
              size: 18,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAnniversaryField() {
    return GestureDetector(
      onTap: _pickAnniversaryDate,
      child: AbsorbPointer(
        child: TextFormField(
          controller: _anniversaryController,
          keyboardType: TextInputType.datetime,
          textInputAction: TextInputAction.next,
          textCapitalization: TextCapitalization.none,
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 15,
            color: KinrelColors.textWhite,
          ),
          decoration: _inputDecoration('YYYY-MM-DD (optional)').copyWith(
            suffixIcon: Icon(
              Icons.favorite_outline,
              color: KinrelColors.textDim,
              size: 18,
            ),
          ),
        ),
      ),
    );
  }

  // ── STEP 1: Relationship ───────────────────────────────────────

  /// v5.13: Builds the "Related to" person picker control.
  /// Shows the currently selected target person (or a prompt to pick one).
  /// Tapping opens a bottom sheet listing all existing family members.
  Widget _buildTargetPersonPicker() {
    final target = _selectedTargetPerson;
    final hasSelection = target != null;

    return GestureDetector(
      onTap: _pickTargetPerson,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: KinrelColors.darkCard,
          borderRadius: BorderRadius.circular(KinrelSpacing.radiusMd),
          border: Border.all(
            color: hasSelection
                ? KinrelColors.orange.withValues(alpha: 0.3)
                : KinrelColors.textDim.withValues(alpha: 0.15),
          ),
        ),
        child: Row(
          children: [
            // Avatar or placeholder
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: hasSelection
                    ? KinrelColors.orange.withValues(alpha: 0.15)
                    : KinrelColors.textDim.withValues(alpha: 0.1),
              ),
              child: Icon(
                hasSelection ? Icons.person : Icons.person_add,
                color: hasSelection ? KinrelColors.orange : KinrelColors.textDim,
                size: 18,
              ),
            ),
            SizedBox(width: 12),
            // Name or prompt
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hasSelection ? target!.name : 'Select a family member…',
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: hasSelection
                          ? KinrelColors.textWhite
                          : KinrelColors.textDim,
                    ),
                  ),
                  if (hasSelection && target!.isAnchor)
                    Text(
                      'Family anchor',
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 11,
                        color: KinrelColors.textDim,
                      ),
                    ),
                ],
              ),
            ),
            // Change icon
            Icon(
              hasSelection ? Icons.swap_horiz : Icons.chevron_right,
              color: KinrelColors.textDim,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  /// v5.202: Builds a LOCKED/disabled version of the "Related to"
  /// picker for regular (non-admin/non-creator) members. Same visual
  /// layout as the interactive [_buildTargetPersonPicker] but:
  ///   - Greyed out (dimmed colors, no orange accent)
  ///   - Shows a lock icon instead of the swap/change icon
  ///   - Non-editable (tapping shows the tooltip, doesn't open the
  ///     picker)
  ///   - Shows the current default value (the auto-selected viewer's
  ///     Person name, or "Me" if the auto-select hasn't resolved yet)
  Widget _buildLockedTargetPersonPicker() {
    // Determine the display name for the locked field. The
    // _selectedTargetPerson is auto-selected via
    // _autoSelectViewerAsTarget() (called from initState when
    // fromGraph && anchorPerson == null). If it hasn't resolved
    // yet, fall back to the effective anchor person, or "Me".
    final target = _selectedTargetPerson ?? _effectiveAnchorPerson;
    final displayName = target?.name ?? 'Me';

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        setState(() {
          // Toggle the tooltip on tap. Tapping elsewhere on the
          // form (e.g. tapping a relationship chip, typing in the
          // name field) will trigger a rebuild that collapses the
          // tooltip via the _showLockedTooltip = false reset in
          // those handlers. But we also set it to false on tap
          // here if it's already showing (toggle behavior).
          _showLockedTooltip = !_showLockedTooltip;
        });
        // Auto-dismiss after 4 seconds.
        Future.delayed(const Duration(seconds: 4), () {
          if (mounted) {
            setState(() => _showLockedTooltip = false);
          }
        });
      },
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: KinrelColors.darkCard.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(KinrelSpacing.radiusMd),
          border: Border.all(
            color: KinrelColors.textDim.withValues(alpha: 0.15),
          ),
        ),
        child: Row(
          children: [
            // Avatar placeholder (greyed out)
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: KinrelColors.textDim.withValues(alpha: 0.1),
              ),
              child: Icon(
                Icons.person,
                color: KinrelColors.textDim.withValues(alpha: 0.6),
                size: 18,
              ),
            ),
            SizedBox(width: 12),
            // Name (greyed out)
            Expanded(
              child: Text(
                displayName,
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: KinrelColors.textDim.withValues(alpha: 0.7),
                ),
              ),
            ),
            // Lock icon (instead of swap/chevron)
            Icon(
              Icons.lock_outline,
              color: KinrelColors.textDim.withValues(alpha: 0.5),
              size: 18,
            ),
          ],
        ),
      ),
    );
  }

  /// v5.202: Builds the inline tooltip shown when a non-admin member
  /// taps the locked "Related to" field. A small, professional message
  /// in a soft container, dismissable by tapping elsewhere or
  /// auto-dismissed after 4 seconds.
  Widget _buildLockedTooltip() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: KinrelColors.darkElevated,
        borderRadius: BorderRadius.circular(KinrelSpacing.radiusSm),
        border: Border.all(
          color: KinrelColors.textDim.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline,
            color: KinrelColors.textDim,
            size: 14,
          ),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Only admins or family creators can change who this connects to.',
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

  /// v5.13: Opens a bottom sheet to pick the target person.
  /// Lists all existing family members (excluding the new person being added).
  Future<void> _pickTargetPerson() async {
    final membersAsync = ref.read(familyMembersProvider(widget.familyId));
    final members = membersAsync.valueOrNull ?? [];

    // Filter: exclude the person being edited (if in edit mode)
    final eligible = members
        .where((m) => m.deletedAt == null && m.id != widget.existingPerson?.id)
        .toList();

    if (eligible.isEmpty) {
      return;
    }

    // Default preselection: prefer the viewer's own Person, then the anchor
    Person? preselected;
    // Try viewer's own Person
    try {
      final viewerId = ref.read(viewerPersonIdProvider(widget.familyId)).valueOrNull;
      if (viewerId != null) {
        preselected = eligible.firstWhere(
          (m) => m.id == viewerId,
          orElse: () => eligible.first,
        );
      }
    } catch (_) {}
    preselected ??= eligible.firstWhere(
      (m) => m.isAnchor,
      orElse: () => eligible.first,
    );

    final picked = await showModalBottomSheet<Person>(
      context: context,
      backgroundColor: KinrelColors.darkCard,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20.0)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Padding(
              padding: const EdgeInsets.only(top: 12.0, bottom: 4.0),
              child: Container(
                width: 40.0,
                height: 4.0,
                decoration: BoxDecoration(
                  color: KinrelColors.textDim,
                  borderRadius: BorderRadius.circular(2.0),
                ),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Who is the new member related to?',
                  style: TextStyle(
                    fontFamily: KinrelTypography.displayFont,
                    fontSize: 16.0,
                    fontWeight: FontWeight.w700,
                    color: KinrelColors.textWhite,
                  ),
                ),
              ),
            ),
            const Divider(color: Color(0x1AFFFFFF), height: 1.0),
            // Member list
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: eligible.length,
                itemBuilder: (ctx, i) {
                  final p = eligible[i];
                  final isSelected = _selectedTargetPerson?.id == p.id ||
                      (preselected?.id == p.id && _selectedTargetPerson == null);
                  return ListTile(
                    leading: PersonAvatar(
                      name: p.name,
                      photoUrl: p.photoUrl,
                      size: 40,
                      backgroundColor: KinrelColors.orange.withValues(alpha: 0.15),
                      textColor: KinrelColors.orange,
                    ),
                    title: Text(
                      p.name,
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        color: KinrelColors.textWhite,
                      ),
                    ),
                    subtitle: p.isAnchor
                        ? Text(
                            'Family anchor',
                            style: TextStyle(
                              fontSize: 11,
                              color: KinrelColors.textDim,
                            ),
                          )
                        : null,
                    trailing: isSelected
                        ? Icon(Icons.check_circle, color: KinrelColors.orange, size: 20)
                        : null,
                    onTap: () => Navigator.pop(ctx, p),
                  );
                },
              ),
            ),
            SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (picked != null && mounted) {
      setState(() => _selectedTargetPerson = picked);
      debugPrint('[ADD-MEMBER] v5.13: User selected target person: ${picked.name} (${picked.id})');
    }
  }

  Widget _buildStep1Relationship() {
    final anchor = _effectiveAnchorPerson;
    final newName = _nameController.text.trim().isNotEmpty
        ? _nameController.text.trim()
        : 'New Member';

    // v5.13: Determine if the "Related to" picker should be shown.
    // Show it when NO anchorPerson was explicitly passed (generic Add flow).
    // When anchorPerson IS passed (node context menu), show a read-only label.
    //
    // v5.197 (ROLE-GATE): The editable "Related to *" picker is now
    // restricted to family ADMINS and CREATORS only. Regular members
    // never see the picker — their additions are always anchored to
    // their own account ("Me"), which is auto-selected via the
    // _autoSelectViewerAsTarget() initState hook. This prevents a
    // regular member from creating relationships between two OTHER
    // accounts (which they would not have permission to do anyway
    // per the relationship_permissions.dart check, but the previous
    // flow showed the picker first and then failed at commit time —
    // a confusing UX). Admins/creators see the full picker and can
    // anchor a relationship between any two existing accounts. When
    // an admin uses this to add/link a relationship where the target
    // is a real registered Kinrel account, the existing pending-
    // invite flow still applies (per the v5.194 invite logic).
    final bool isAdminOrCreator = _isCurrentUserAdminOrCreator;
    final bool showTargetPicker =
        widget.anchorPerson == null && !_isEditMode && isAdminOrCreator;
    final bool familyHasMembers = _familyHasExistingMembers;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // v5.13: "Related to" person picker — lets the user choose WHICH
          // existing member the new person relates to.
          if (familyHasMembers && showTargetPicker) ...[
            _SectionLabel('Related to *'),
            SizedBox(height: 8),
            _buildTargetPersonPicker(),
            SizedBox(height: 20),
          ] else if (widget.anchorPerson != null) ...[
            // Non-editable confirmation label when target was passed from context
            _SectionLabel('Related to'),
            SizedBox(height: 8),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: KinrelColors.darkCard,
                borderRadius: BorderRadius.circular(KinrelSpacing.radiusMd),
                border: Border.all(
                  color: KinrelColors.orange.withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.person, color: KinrelColors.orange, size: 20),
                  SizedBox(width: 10),
                  Text(
                    widget.anchorPerson!.name,
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: KinrelColors.textWhite,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 20),
          ],

          // Question
          if (anchor != null) ...[
            Text(
              'How is $newName related to ${anchor.name}?',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 16,
                color: KinrelColors.textSilver,
                height: 1.5,
              ),
            ),
            SizedBox(height: 20),

            // Two portrait cards
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _PortraitCard(
                  name: anchor.name,
                  gender: anchor.gender,
                  label: 'Existing',
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Column(
                    children: [
                      Icon(
                        Icons.swap_horiz,
                        color: KinrelColors.orange,
                        size: 28,
                      ),
                      SizedBox(height: 4),
                      Text(
                        _selectedRelType?.toUpperCase() ?? '?',
                        style: TextStyle(
                          fontFamily: KinrelTypography.monoFont,
                          fontSize: 9,
                          color: KinrelColors.orange,
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ),
                ),
                _PortraitCard(
                  name: newName,
                  gender: _selectedGender,
                  label: 'New',
                  isNew: true,
                ),
              ],
            ),
            SizedBox(height: 28),
          ] else if (!familyHasMembers) ...[
            Text(
              'This is the first member of the family. No relationship needed yet.',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 16,
                color: KinrelColors.textSilver,
              ),
            ),
            SizedBox(height: 20),
          ] else ...[
            // v5.40: familyHasMembers == true && anchor == null.
            // The user opened Add Member from a generic entry point
            // (no anchorPerson passed) and hasn't yet picked a target
            // from the "Related to" picker above. Show a placeholder
            // question + hint so they understand the relationship
            // cards below will relate the new person to whoever they
            // pick as the target (or to the family anchor if they
            // skip the picker).
            Text(
              'How is $newName related to a family member?',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 16,
                color: KinrelColors.textSilver,
                height: 1.5,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Tip: pick "Related to" above to choose a specific person, '
              'or skip to use the family anchor.',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 12,
                color: KinrelColors.textDim,
                height: 1.4,
              ),
            ),
            SizedBox(height: 20),
          ],

          // Relationship type cards
          _SectionLabel('Relationship Type'),
          SizedBox(height: 10),
          _buildRelationshipTypeCards(),
          SizedBox(height: 16),

          // Sub-type for siblings
          if (_selectedRelType == 'sibling') ...[
            SizedBox(height: 8),
            _SectionLabel('Elder or Younger?'),
            SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _SelectableCard(
                    label: 'Elder',
                    subtitle: 'Older sibling',
                    icon: Icons.arrow_upward,
                    selected: _selectedSubType == 'elder',
                    onTap: () => setState(() => _selectedSubType = 'elder'),
                  ),
                ),
                SizedBox(width: 10),
                Expanded(
                  child: _SelectableCard(
                    label: 'Younger',
                    subtitle: 'Younger sibling',
                    icon: Icons.arrow_downward,
                    selected: _selectedSubType == 'younger',
                    onTap: () => setState(() => _selectedSubType = 'younger'),
                  ),
                ),
              ],
            ),
            SizedBox(height: 16),
          ],

          // Detailed relationship picker
          SizedBox(height: 8),
          _SectionLabel('Or pick a specific kinship term'),
          SizedBox(height: 8),
          GestureDetector(
            onTap: _pickDetailedRelationship,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                color: KinrelColors.darkCard,
                borderRadius: BorderRadius.circular(KinrelSpacing.radiusMd),
                border: Border.all(
                  color: KinrelColors.textDim.withValues(alpha: 0.15),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.search, color: KinrelColors.orange, size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _selectedRelationshipLabel ?? 'Search all kinship terms…',
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 14,
                        color: _selectedRelationshipLabel != null
                            ? KinrelColors.textWhite
                            : KinrelColors.textDim,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    color: KinrelColors.textDim,
                    size: 18,
                  ),
                ],
              ),
            ),
          ),

          // v80: Add Your Own Kinship
          SizedBox(height: 8),
          _SectionLabel('Or create your own'),
          SizedBox(height: 8),
          GestureDetector(
            onTap: _showCustomKinshipDialog,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                color: KinrelColors.darkCard,
                borderRadius: BorderRadius.circular(KinrelSpacing.radiusMd),
                border: Border.all(
                  color: _customKinshipName != null
                      ? KinrelColors.orange.withValues(alpha: 0.4)
                      : KinrelColors.textDim.withValues(alpha: 0.15),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.palette_outlined, color: KinrelColors.purple, size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _customKinshipName ?? 'Add Your Own Kinship',
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 14,
                        color: _customKinshipName != null
                            ? KinrelColors.textWhite
                            : KinrelColors.textDim,
                      ),
                    ),
                  ),
                  if (_customKinshipName != null) ...[
                    Container(
                      width: 16, height: 16,
                      decoration: BoxDecoration(
                        color: Color(_customNodeColorValue),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                      ),
                    ),
                    SizedBox(width: 4),
                    Container(
                      width: 16, height: 16,
                      decoration: BoxDecoration(
                        color: Color(_customLineColorValue),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                      ),
                    ),
                    SizedBox(width: 8),
                  ],
                  Icon(Icons.chevron_right, color: KinrelColors.textDim, size: 18),
                ],
              ),
            ),
          ),

          // Visual preview
          if (_relationshipPreview.isNotEmpty) ...[
            SizedBox(height: 24),
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: KinrelColors.orange.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(KinrelSpacing.radiusMd),
                border: Border.all(
                  color: KinrelColors.orange.withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.visibility_outlined,
                    color: KinrelColors.orange,
                    size: 18,
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _relationshipPreview,
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 14,
                        color: KinrelColors.textWhite,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Mandatory hint when no relationship selected but family has existing members
          // v5.42: Only show the "required" hint for graph origin. For Family Space
          // origin, show a softer "optional" hint instead.
          if (_familyHasExistingMembers && _effectiveRelationshipKey == null) ...[
            SizedBox(height: 16),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: (widget.fromGraph ? KinrelColors.orange : KinrelColors.tealAccent)
                    .withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(KinrelSpacing.radiusSm),
                border: Border.all(
                  color: (widget.fromGraph ? KinrelColors.orange : KinrelColors.tealAccent)
                      .withValues(alpha: 0.15),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    widget.fromGraph ? Icons.info_outline : Icons.link_off,
                    size: 16,
                    color: widget.fromGraph
                        ? KinrelColors.orange
                        : KinrelColors.tealAccent,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.fromGraph
                          ? 'Please select how they are related to proceed'
                          : 'Optional: pick a relationship now, or skip and '
                            'link them later from the graph\'s "Link" button.',
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 13,
                        color: widget.fromGraph
                            ? KinrelColors.orange
                            : KinrelColors.tealAccent,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRelationshipTypeCards() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _SelectableCard(
                label: 'Parent',
                subtitle: 'Father / Mother',
                icon: Icons.family_restroom,
                selected: _selectedRelType == 'parent',
                onTap: () => setState(() {
                  _selectedRelType = 'parent';
                  _selectedSubType = null;
                  _selectedRelationshipKey = null;
                  _selectedRelationshipLabel = null;
                }),
              ),
            ),
            SizedBox(width: 10),
            Expanded(
              child: _SelectableCard(
                label: 'Child',
                subtitle: 'Son / Daughter',
                icon: Icons.child_care,
                selected: _selectedRelType == 'child',
                onTap: () => setState(() {
                  _selectedRelType = 'child';
                  _selectedSubType = null;
                  _selectedRelationshipKey = null;
                  _selectedRelationshipLabel = null;
                }),
              ),
            ),
          ],
        ),
        SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _SelectableCard(
                label: 'Spouse',
                subtitle: 'Husband / Wife',
                icon: Icons.favorite,
                selected: _selectedRelType == 'spouse',
                onTap: () => setState(() {
                  _selectedRelType = 'spouse';
                  _selectedSubType = null;
                  _selectedRelationshipKey = null;
                  _selectedRelationshipLabel = null;
                }),
              ),
            ),
            SizedBox(width: 10),
            Expanded(
              child: _SelectableCard(
                label: 'Sibling',
                subtitle: 'Brother / Sister',
                icon: Icons.people,
                selected: _selectedRelType == 'sibling',
                onTap: () => setState(() {
                  _selectedRelType = 'sibling';
                  _selectedSubType = null;
                  _selectedRelationshipKey = null;
                  _selectedRelationshipLabel = null;
                }),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── STEP 2: Additional Details ─────────────────────────────────

  Widget _buildStep2AdditionalDetails() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Collapsible sections
          _buildCollapsibleSection(
            title: 'Location Details',
            icon: Icons.location_on_outlined,
            isExpanded: _locationExpanded,
            onExpansionChanged: (v) => setState(() => _locationExpanded = v),
            children: [
              _SectionLabel('Birth Place'),
              SizedBox(height: 6),
              _buildTextField(
                controller: _birthPlaceController,
                hint: 'Birth place',
              ),
              SizedBox(height: 14),
              _SectionLabel('Current City'),
              SizedBox(height: 6),
              _buildTextField(
                controller: _cityController,
                hint: 'Current city',
              ),
            ],
          ),

          SizedBox(height: 12),

          _buildCollapsibleSection(
            title: 'Contact Information',
            icon: Icons.phone_outlined,
            isExpanded: _contactExpanded,
            onExpansionChanged: (v) => setState(() => _contactExpanded = v),
            children: [
              _SectionLabel('Phone'),
              SizedBox(height: 6),
              _buildTextField(
                controller: _phoneController,
                hint: 'Phone number',
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
                textCapitalization: TextCapitalization.none,
              ),
              SizedBox(height: 14),
              _SectionLabel('Email'),
              SizedBox(height: 6),
              _buildTextField(
                controller: _emailController,
                hint: 'Email address',
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.done,
                textCapitalization: TextCapitalization.none,
              ),
            ],
          ),

          SizedBox(height: 12),

          _buildCollapsibleSection(
            title: 'Professional & Personal',
            icon: Icons.work_outline,
            isExpanded: _personalExpanded,
            onExpansionChanged: (v) => setState(() => _personalExpanded = v),
            children: [
              _SectionLabel('Occupation'),
              SizedBox(height: 6),
              _buildTextField(
                controller: _occupationController,
                hint: 'Occupation',
              ),
              SizedBox(height: 14),
              _SectionLabel('Gotra'),
              SizedBox(height: 6),
              _buildTextField(controller: _gotraController, hint: 'Gotra'),
              SizedBox(height: 14),
              _SectionLabel('Bio / Notes'),
              SizedBox(height: 6),
              _buildTextField(
                controller: _bioController,
                hint: 'Short bio or notes',
                maxLines: 3,
              ),
            ],
          ),

          SizedBox(height: 12),

          // Deceased section (always visible)
          _buildDeceasedSection(),
        ],
      ),
    );
  }

  Widget _buildCollapsibleSection({
    required String title,
    required IconData icon,
    required bool isExpanded,
    required ValueChanged<bool> onExpansionChanged,
    required List<Widget> children,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(KinrelSpacing.radiusMd),
        border: Border.all(color: KinrelColors.textDim.withValues(alpha: 0.08)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          childrenPadding: EdgeInsets.fromLTRB(16, 0, 16, 16),
          initiallyExpanded: isExpanded,
          onExpansionChanged: onExpansionChanged,
          leading: Icon(icon, color: KinrelColors.orange, size: 20),
          title: Text(
            title,
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: KinrelColors.textWhite,
            ),
          ),
          trailing: Icon(
            isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
            color: KinrelColors.textDim,
          ),
          children: children,
        ),
      ),
    );
  }

  Widget _buildDeceasedSection() {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(KinrelSpacing.radiusMd),
        border: Border.all(
          color: _isDeceased
              ? KinrelColors.error.withValues(alpha: 0.3)
              : KinrelColors.textDim.withValues(alpha: 0.08),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _isDeceased ? Icons.cloud : Icons.cloud_outlined,
                color: _isDeceased ? KinrelColors.error : KinrelColors.textDim,
                size: 20,
              ),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Mark as Deceased',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: _isDeceased
                        ? KinrelColors.error
                        : KinrelColors.textWhite,
                  ),
                ),
              ),
              Switch.adaptive(
                value: _isDeceased,
                onChanged: (v) => setState(() => _isDeceased = v),
                activeThumbColor: KinrelColors.error,
                activeTrackColor: KinrelColors.error.withValues(alpha: 0.4),
              ),
            ],
          ),
          if (_isDeceased) ...[
            SizedBox(height: 12),
            GestureDetector(
              onTap: _pickDeathDate,
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: KinrelColors.darkElevated,
                  borderRadius: BorderRadius.circular(KinrelSpacing.radiusSm),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.calendar_today_outlined,
                      color: KinrelColors.textDim,
                      size: 16,
                    ),
                    SizedBox(width: 10),
                    Text(
                      _selectedDeathDate != null
                          ? 'Date of death: ${_selectedDeathDate!.toIso8601String().split('T').first}'
                          : 'Select date of death',
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 13,
                        color: _selectedDeathDate != null
                            ? KinrelColors.textWhite
                            : KinrelColors.textDim,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── STEP 3: Confirmation ───────────────────────────────────────

  Widget _buildStep3Confirmation() {
    final newName = _nameController.text.trim().isNotEmpty
        ? _nameController.text.trim()
        : 'New Member';
    final anchor = widget.anchorPerson;
    final relLabel = _effectiveRelationshipKey?.snakeToTitle ?? 'Not specified';

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Summary card
          Container(
            padding: EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: KinrelColors.darkCard,
              borderRadius: BorderRadius.circular(KinrelSpacing.radiusLg),
              border: Border.all(
                color: KinrelColors.textDim.withValues(alpha: 0.1),
              ),
            ),
            child: Column(
              children: [
                // Avatar
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: _isDeceased
                        ? LinearGradient(
                            colors: [
                              KinrelColors.textDim,
                              KinrelColors.darkSurface,
                            ],
                          )
                        : KinrelGradients.igniteGradient,
                  ),
                  child: Center(
                    child: Text(
                      PersonAvatar.initialsFor(newName),
                      style: TextStyle(
                        fontFamily: KinrelTypography.displayFont,
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                SizedBox(height: 16),

                // Name
                Text(
                  newName,
                  style: TextStyle(
                    fontFamily: KinrelTypography.displayFont,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: KinrelColors.textWhite,
                  ),
                  textAlign: TextAlign.center,
                ),

                // Relationship
                if (anchor != null && _effectiveRelationshipKey != null) ...[
                  SizedBox(height: 8),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: KinrelColors.orange.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: KinrelColors.orange.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Text(
                      '${anchor.name}\'s $relLabel',
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: KinrelColors.orange,
                      ),
                    ),
                  ),
                ],

                SizedBox(height: 16),

                // Detail rows
                _ConfirmationRow(
                  icon: Icons.wc,
                  label: 'Gender',
                  value: _selectedGender.capitalized,
                ),
                if (_selectedDob != null)
                  _ConfirmationRow(
                    icon: Icons.calendar_today_outlined,
                    label: 'Date of Birth',
                    value: _dobController.text,
                  ),
                if (_cityController.text.trim().isNotEmpty)
                  _ConfirmationRow(
                    icon: Icons.location_on_outlined,
                    label: 'City',
                    value: _cityController.text.trim(),
                  ),
                if (_isDeceased)
                  _ConfirmationRow(
                    icon: Icons.cloud,
                    label: 'Status',
                    value: 'Deceased',
                    valueColor: KinrelColors.error,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Success view ───────────────────────────────────────────────

  Widget _buildSuccessView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: KinrelColors.orange.withValues(alpha: 0.15),
            ),
            child: Icon(
              Icons.check_circle,
              color: KinrelColors.orange,
              size: 48,
            ),
          ),
          SizedBox(height: 20),
          Text(
            _successMessage ?? 'Welcome to the family!',
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: KinrelColors.textWhite,
            ),
          ),
          SizedBox(height: 8),
          Text(
            '${_nameController.text.trim()} has been added',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 14,
              color: KinrelColors.textSilver,
            ),
          ),
        ],
      ),
    );
  }

  // ── Deceased toggle (edit mode) ────────────────────────────────

  Widget _buildDeceasedToggle() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(KinrelSpacing.radiusSm),
        border: Border.all(color: KinrelColors.textDim.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Deceased',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 15,
                color: KinrelColors.textSilver,
              ),
            ),
          ),
          Switch.adaptive(
            value: _isDeceased,
            onChanged: (v) => setState(() => _isDeceased = v),
            activeThumbColor: KinrelColors.orange,
            activeTrackColor: KinrelColors.orange.withValues(alpha: 0.4),
          ),
        ],
      ),
    );
  }

  // ── Bottom actions ─────────────────────────────────────────────

  Widget _buildBottomActions() {
    if (_isEditMode) return const SizedBox.shrink();

    return Padding(
      padding: EdgeInsets.only(top: 12),
      child: Row(
        children: [
          // Skip / Back
          if (_currentStep > 0)
            Expanded(
              child: OutlinedButton(
                onPressed: _prevStep,
                style: OutlinedButton.styleFrom(
                  foregroundColor: KinrelColors.textSilver,
                  side: BorderSide(
                    color: KinrelColors.textDim.withValues(alpha: 0.3),
                  ),
                  padding: EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(KinrelSpacing.radiusMd),
                  ),
                ),
                child: Text(
                  'Back',
                  style: TextStyle(
                    fontFamily: KinrelTypography.displayFont,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          if (_currentStep > 0) SizedBox(width: 12),

          // Next / Submit
          Expanded(
            flex: _currentStep > 0 ? 2 : 1,
            child: _currentStep == _kStepCount - 1
                ? _buildIgniteButton(
                    label: 'Add to Family',
                    onPressed: _isSubmitting || !_canProceed() ? null : _submit,
                    isLoading: _isSubmitting,
                  )
                : _buildIgniteButton(
                    label: _currentStep == 1 && !_canProceed()
                        // v5.40: Simpler hint — only the relationship is
                        // required to proceed; the target is optional.
                        ? 'Next (select relationship)'
                        : _currentStep == 0 && !_canProceed()
                            ? 'Next (name required)'
                            : 'Next',
                    onPressed: _canProceed() ? _nextStep : null,
                  ),
          ),
        ],
      ),
    );
  }

  // ── Shared widgets ─────────────────────────────────────────────

  Widget _buildIgniteButton({
    required String label,
    VoidCallback? onPressed,
    bool isLoading = false,
  }) {
    final isDisabled = onPressed == null;
    return Container(
      decoration: BoxDecoration(
        gradient: isDisabled ? null : KinrelGradients.igniteGradient,
        color: isDisabled ? KinrelColors.orange.withValues(alpha: 0.3) : null,
        borderRadius: BorderRadius.circular(KinrelSpacing.radiusMd),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(KinrelSpacing.radiusMd),
          child: Container(
            padding: EdgeInsets.symmetric(vertical: 14),
            alignment: Alignment.center,
            child: isLoading
                ? SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    label,
                    style: TextStyle(
                      fontFamily: KinrelTypography.displayFont,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    bool isLarge = false,
    int maxLines = 1,
    TextInputType? keyboardType,
    TextInputAction textInputAction = TextInputAction.done,
    TextCapitalization textCapitalization = TextCapitalization.none,
    String? Function(String?)? validator,
    void Function(String)? onFieldSubmitted,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      textCapitalization: textCapitalization,
      validator: validator,
      onFieldSubmitted: onFieldSubmitted,
      // v62.5: onChanged triggers setState so the Next/Add button
      // updates immediately as the user types — no 5s delay.
      // v5.202: Also dismiss the locked "Related to" tooltip when
      // the user starts typing (dismiss-on-tap-elsewhere behavior).
      onChanged: (_) => setState(() {
        _showLockedTooltip = false;
      }),
      style: TextStyle(
        fontFamily: isLarge
            ? KinrelTypography.displayFont
            : KinrelTypography.bodyFont,
        fontSize: isLarge ? 20 : 15,
        fontWeight: isLarge ? FontWeight.w600 : FontWeight.w400,
        color: KinrelColors.textWhite,
      ),
      cursorColor: KinrelColors.orange,
      decoration: _inputDecoration(hint),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(
        color: KinrelColors.textDim, // #8A7A72 per spec
        fontFamily: KinrelTypography.bodyFont,
      ),
      filled: true,
      fillColor: KinrelColors.darkElevated, // #202338 per spec
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(KinrelSpacing.radiusSm),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(KinrelSpacing.radiusSm),
        borderSide: BorderSide(
          color: KinrelColors.textDim.withValues(alpha: 0.1),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(KinrelSpacing.radiusSm),
        borderSide: BorderSide(color: KinrelColors.orange), // #E8612A focus
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(KinrelSpacing.radiusSm),
        borderSide: BorderSide(color: KinrelColors.error),
      ),
      contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// SUB-WIDGETS
// ═══════════════════════════════════════════════════════════════════

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontFamily: KinrelTypography.bodyFont,
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: KinrelColors.textSilver, // #C9B4A8
      ),
    );
  }
}

/// Elegant gender card with orange border on selected.
class _GenderCard extends StatelessWidget {
  const _GenderCard({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(vertical: 14, horizontal: 10),
        decoration: BoxDecoration(
          color: selected
              ? KinrelColors.orange.withValues(alpha: 0.1)
              : KinrelColors.darkCard,
          borderRadius: BorderRadius.circular(KinrelSpacing.radiusMd),
          border: Border.all(
            color: selected
                ? KinrelColors.orange
                : KinrelColors.textDim.withValues(alpha: 0.12),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: selected ? KinrelColors.orange : KinrelColors.textDim,
              size: 22,
            ),
            SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: selected ? KinrelColors.orange : KinrelColors.textSilver,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Selectable card for relationship types (Parent, Child, Spouse, Sibling).
class _SelectableCard extends StatelessWidget {
  const _SelectableCard({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        decoration: BoxDecoration(
          color: selected
              ? KinrelColors.orange.withValues(alpha: 0.08)
              : KinrelColors.darkCard,
          borderRadius: BorderRadius.circular(KinrelSpacing.radiusMd),
          border: Border.all(
            color: selected
                ? KinrelColors.orange
                : KinrelColors.textDim.withValues(alpha: 0.1),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  icon,
                  color: selected ? KinrelColors.orange : KinrelColors.textDim,
                  size: 18,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontFamily: KinrelTypography.displayFont,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: selected
                          ? KinrelColors.orange
                          : KinrelColors.textWhite,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 4),
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
    );
  }
}

/// v5.198: Definition for a primary relationship chip in the 2x3
/// quick-add grid. Mirrors the _QuickPickCategory enum used by the
/// "Find on Kinrel" relationship picker so the two flows share the
/// same visual + interaction pattern.
class _RelChipDef {
  const _RelChipDef({
    required this.type,
    required this.label,
    required this.icon,
  });
  final String type; // 'parent' | 'child' | 'sibling' | 'spouse' | 'grandparent'
  final String label;
  final IconData icon;
}

/// v5.198: A single chip in the 2x3 quick-add relationship grid.
/// Visually identical to the _QuickPickChip used by the "Find on
/// Kinrel" relationship picker (same 158pt width, 48pt height,
/// orange fill + white text when selected, orange outline when not).
///
/// `isMore: true` switches the chip to the "More" visual style —
/// dimmer outline + dim text — to signal it's the expansion toggle,
/// not a primary kinship choice. When `isSelected` (the "More"
/// section is currently expanded), it uses the same solid-orange
/// selected style so the user sees the current toggle state.
class _RelChip extends StatelessWidget {
  const _RelChip({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.width,
    required this.height,
    required this.onTap,
    this.isMore = false,
  });

  final String label;
  final IconData icon;
  final bool isSelected;
  final double width;
  final double height;
  final VoidCallback onTap;
  final bool isMore;

  @override
  Widget build(BuildContext context) {
    // Selected chip uses solid orange fill + white text + thicker
    // border. Non-selected primary chips use the subtle orange
    // outline. The "More" chip uses a dimmer outline + dim text in
    // its non-selected state to signal it's an expansion toggle.
    //
    // v5.199 (BUG FIX): The "More" chip previously used
    // `Colors.transparent` as its non-selected background, which made
    // the `InkWell`'s tap ripple invisible (no surface to render on)
    // AND made the chip itself visually merge into the dark sheet
    // background — users reported the chip "does nothing" on tap.
    // Now ALL chips (including "More") use `KinrelColors.darkElevated`
    // as their non-selected background so the InkWell has a solid
    // surface, the ripple is visible, and the chip is visually
    // distinct from the sheet background. The "More" chip is still
    // visually differentiated from primary chips via its dimmer
    // border color + dim text/icon color + a trailing expand icon.
    final Color chipBg = isSelected
        ? KinrelColors.orange
        : KinrelColors.darkElevated;
    final Color chipBorder = isSelected
        ? KinrelColors.orange
        : (isMore
            ? KinrelColors.textDim.withValues(alpha: 0.4)
            : KinrelColors.orange.withValues(alpha: 0.3));
    final double borderWidth = isSelected ? 2 : 1;
    final Color iconColor = isSelected
        ? Colors.white
        : (isMore ? KinrelColors.textDim : KinrelColors.orange);
    final Color textColor = isSelected
        ? Colors.white
        : (isMore ? KinrelColors.textDim : KinrelColors.textWhite);

    return SizedBox(
      width: width,
      height: height,
      child: Container(
        decoration: BoxDecoration(
          color: chipBg,
          borderRadius: BorderRadius.circular(KinrelSpacing.radiusMd),
          border: Border.all(
            color: chipBorder,
            width: borderWidth,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(KinrelSpacing.radiusMd),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: iconColor, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: textColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // v5.199: Show an expand/collapse chevron on the "More"
                  // chip so it's visually clear it's an expansion toggle,
                  // not a dead-end button. When expanded (isSelected),
                  // shows expand_less (up chevron); collapsed shows
                  // expand_more (down chevron).
                  if (isMore) ...[
                    const SizedBox(width: 4),
                    Icon(
                      isSelected ? Icons.expand_less : Icons.expand_more,
                      color: textColor,
                      size: 18,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Portrait card showing a person in the relationship step.
class _PortraitCard extends StatelessWidget {
  const _PortraitCard({
    required this.name,
    this.gender,
    required this.label,
    this.isNew = false,
  });

  final String name;
  final String? gender;
  final String label;
  final bool isNew;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: isNew
                ? KinrelGradients.igniteGradient
                : LinearGradient(
                    colors: [KinrelColors.darkElevated, KinrelColors.darkCard],
                  ),
          ),
          child: Center(
            child: Text(
              PersonAvatar.initialsFor(name),
              style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
        ),
        SizedBox(height: 8),
        Text(
          name.length > 10 ? '${name.substring(0, 9)}…' : name,
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: KinrelColors.textWhite,
          ),
        ),
        SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 11,
            color: KinrelColors.textDim,
          ),
        ),
      ],
    );
  }
}

/// Confirmation detail row.
class _ConfirmationRow extends StatelessWidget {
  const _ConfirmationRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: KinrelColors.textDim),
          SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 12,
              color: KinrelColors.textDim,
            ),
          ),
          Spacer(),
          Text(
            value,
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: valueColor ?? KinrelColors.textWhite,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// CONFETTI
// ═══════════════════════════════════════════════════════════════════

class _ConfettiParticle {
  _ConfettiParticle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.size,
    required this.color,
    required this.rotation,
    required this.rotationSpeed,
  });

  double x;
  double y;
  final double vx;
  final double vy;
  final double size;
  final Color color;
  double rotation;
  final double rotationSpeed;
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter({required this.particles, required this.progress});

  final List<_ConfettiParticle> particles;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in particles) {
      // Simulate movement
      final x = (p.x + p.vx * progress * size.width * 100) * size.width;
      final y = (p.y + p.vy * progress * size.height * 100) * size.height;
      final rotation = p.rotation + p.rotationSpeed * progress * 100;

      // Fade out near end
      final opacity = progress > 0.7 ? (1.0 - progress) / 0.3 : 1.0;

      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(rotation);

      final paint = Paint()
        ..color = p.color.withValues(alpha: opacity.clamp(0.0, 1.0))
        ..style = PaintingStyle.fill;

      canvas.drawRect(
        Rect.fromCenter(
          center: Offset.zero,
          width: p.size,
          height: p.size * 0.6,
        ),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter oldDelegate) =>
      progress != oldDelegate.progress;
}

/// v80: Preview painter for the custom kinship line + dot
class _LinePreviewPainter extends CustomPainter {
  final Color color;
  final bool isDashed;
  final String dotType;

  _LinePreviewPainter({
    required this.color,
    required this.isDashed,
    required this.dotType,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final midY = size.height / 2;
    if (isDashed) {
      double x = 0;
      const dashWidth = 6.0;
      const dashGap = 4.0;
      while (x < size.width) {
        canvas.drawLine(
          Offset(x, midY),
          Offset((x + dashWidth).clamp(0, size.width), midY),
          paint,
        );
        x += dashWidth + dashGap;
      }
    } else {
      canvas.drawLine(Offset(0, midY), Offset(size.width, midY), paint);
    }

    // Draw dot/heart at midpoint
    if (dotType != 'none') {
      final midX = size.width / 2;
      if (dotType == 'heart') {
        // Simple pink heart (circle for preview)
        canvas.drawCircle(
          Offset(midX, midY),
          4,
          Paint()..color = const Color(0xFFEC4899),
        );
      } else {
        canvas.drawCircle(
          Offset(midX, midY),
          4,
          Paint()..color = color,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _LinePreviewPainter old) =>
      color != old.color || isDashed != old.isDashed || dotType != old.dotType;
}
