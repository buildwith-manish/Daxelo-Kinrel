import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/family/family_provider.dart';
import 'relationship_picker_sheet.dart';

class AddPersonSheet extends ConsumerStatefulWidget {
  const AddPersonSheet({
    super.key,
    required this.familyId,
    this.existingPerson,
  });

  final String familyId;
  final Person? existingPerson;


  /// Show as bottom sheet
  static Future<void> show(
    BuildContext context, {
    required String familyId,
    Person? existingPerson,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: KinrelColors.darkCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(KinrelRadius.bottomSheet),
        ),
      ),
      builder: (_) => AddPersonSheet(
        familyId: familyId,
        existingPerson: existingPerson,
      ),
    );
  }

  @override
  ConsumerState<AddPersonSheet> createState() => _AddPersonSheetState();
}

class _AddPersonSheetState extends ConsumerState<AddPersonSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _dobController = TextEditingController();
  final _cityController = TextEditingController();
  final _gotraController = TextEditingController();

  String? _selectedRelationshipLabel;
  String _selectedGender = 'male';
  bool _isDeceased = false;
  bool _isSubmitting = false;
  DateTime? _selectedDob;

  bool get _isEditMode => widget.existingPerson != null;

  @override
  void initState() {
    super.initState();
    if (_isEditMode) {
      final p = widget.existingPerson!;
      _nameController.text = p.name;
      _selectedGender = p.gender ?? 'male';
      _dobController.text = p.dateOfBirth ?? '';
      _cityController.text = p.city ?? '';
      _gotraController.text = p.gotra ?? '';
      _isDeceased = p.isDeceased;

      if (p.dateOfBirth != null && p.dateOfBirth!.isNotEmpty) {
        try {
          _selectedDob = DateTime.parse(p.dateOfBirth!);
        } catch (_) {}
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _dobController.dispose();
    _cityController.dispose();
    _gotraController.dispose();
    super.dispose();
  }

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
            colorScheme: const ColorScheme.dark(
              primary: KinrelColors.purple,
              surface: KinrelColors.darkElevated,
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

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    try {
      Person result;

      if (_isEditMode) {
        result = await updatePerson(
          ref: ref,
          personId: widget.existingPerson!.id,
          familyId: widget.familyId,
          name: _nameController.text.trim(),
          gender: _selectedGender,
          dateOfBirth: _dobController.text.trim().isEmpty
              ? null
              : _dobController.text.trim(),
          city: _cityController.text.trim().isEmpty
              ? null
              : _cityController.text.trim(),
          gotra: _gotraController.text.trim().isEmpty
              ? null
              : _gotraController.text.trim(),
          isDeceased: _isDeceased,
        );
      } else {
        result = await createPerson(
          ref: ref,
          familyId: widget.familyId,
          name: _nameController.text.trim(),
          gender: _selectedGender,
          dateOfBirth: _dobController.text.trim().isEmpty
              ? null
              : _dobController.text.trim(),
          city: _cityController.text.trim().isEmpty
              ? null
              : _cityController.text.trim(),
          gotra: _gotraController.text.trim().isEmpty
              ? null
              : _gotraController.text.trim(),
          isDeceased: _isDeceased,
        );
      }

      if (!mounted) return;
      setState(() => _isSubmitting = false);

      context.showSnackBar(
        _isEditMode
            ? 'Person updated successfully'
            : '${result.name} added to family',
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        context.showSnackBar(
          _isEditMode
              ? 'Failed to update person: ${e.toString().split('\n').first}'
              : 'Failed to add person: ${e.toString().split('\n').first}',
          isError: true,
        );
      }
    }
  }

  Future<void> _pickRelationship() async {
    final result = await RelationshipPickerSheet.show(
      context,
      personAName: _nameController.text.trim().isNotEmpty
          ? _nameController.text.trim()
          : null,
    );
    if (result != null) {
      setState(() {
        _selectedRelationshipLabel = result.snakeToTitle;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(
        left: KinrelSpacing.base,
        right: KinrelSpacing.base,
        top: KinrelSpacing.xl,
        bottom: math.max(bottomInset, KinrelSpacing.xl),
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Handle bar
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: KinrelColors.darkSurface,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Title
              Text(
                _isEditconst Mode ? 'Edit Person' : 'Add Family Member',
                style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: KinrelColors.textWhite,
                ),
              ),
              const SizedBox(height: 24),

              const // Name
              _Label('Name *'),
              const SizedBox(height: 6),
              TextFormField(
                controller: _nameController,
                validator: (v) =>
                    v =const = null || v.trim().isEmpty ? 'Name is required' : null,
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 15,
                  color: KinrelColors.textWhite,
                ),
                decoration: _inputDecoration('Full name'),
              ),
              const SizedBox(height: 16),

              const // Relationship Type
              _Label('Relationship Type'),
              const SizedBox(height: 6),
              GestureDetector(
                onTap: _pickRelationship,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: KinrelColors.darkElevated,
                    borderRadius:
                        BorderRadius.circular(KinrelSpacing.radiusSm),
                    border: Border.all(
                      color: KinrelColors.darkSurface.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _selectedRelationshipLabel ?? 'Search relationship...',
                          style: TextStyle(
                            fontFamily: KinrelTypography.bodyFont,
                            fontSize: 15,
                            color: _selectedRelationshipLabel != null
                                ? KinrelColors.textWhite
                                : KinrelColors.textDim,
                          ),
                        ),
                      ,
                      Icon(Icons.search, color: KinrelColors.purple, size: 20),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              const // Gender
              _Label('Gender'),
              const SizedBox(height: 6),
              Row(
                children: [
                  _GenderChip(
                    label: 'Male',
                    selected: _selectedGender == 'male',
                    onTap: () => setState(() => _selectedGender = 'male'),
                  ),
                  const SizedBox(width: 8),
                  _GenderChip(
                    label: 'Female',
                    selected: _selectedGender == 'female',
                    onTap: () => setState(() => _selectedGender = 'female'),
                  ),
                  const SizedBox(width: 8),
                  _GenderChip(
                    label: 'Other',
                    selected: _selectedGender == 'other',
                    onTap: () => setState(() => _selectedGender = 'other'),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              const // Date of Birth
              _Label('Date of Birth'),
              const SizedBox(height: 6),
              GestureDetector(
                onTap: _pickDate,
                child: AbsorbPointer(
                  child: TextFormField(
                    controller: _dobController,
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 15,
                      color: KinrelColors.textWhite,
                    ),
                    decoration: _inputDecoration('YYYY-MM-DD').copyWith(
                      suffixIcon: Icon(
                        Icons.calendar_today,
                        color: KinrelColors.textDim,
                        size: 18,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              const // City/Village
              _Label('City / Village'),
              const SizedBox(height: 6),
              TextFormField(
                controller: _cityController,
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 15,
                  color: KinrelColors.textWhite,
                ),
                decoration: _inputDecoration('City or village name'),
              ),
              const SizedBox(height: 16),

              const // Gotra
              _Label('Gotra'),
              const SizedBox(height: 6),
              TextFormField(
                controller: _gotraController,
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 15,
                  color: KinrelColors.textWhite,
                ),
                decoration: _inputDecoration('Gotra'),
              ),
              const SizedBox(height: 16),

              // Alive / Deceased toggle
              Row(
                children: [
                  Expanded(const child: Text(
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
                    activeColor: KinrelColors.purple,
                  ),
                ],
              ),
              const SizedBox(height: 28),

              // Submit
              FilledButton(
                onPressed: _isSubmitting ? null : _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: KinrelColors.purple,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor:
                      KinrelColors.purple.withValues(alpha: 0.4),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(KinrelSpacing.radiusSm),
                  ),
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        _isEditconst Mode ? 'Save Changes' : 'Add Member',
                        style: TextStyle(
                          fontFamily: KinrelTypography.displayFont,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: KinrelColors.textDim),
      filled: true,
      fillColor: KinrelColors.darkElevated,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(KinrelSpacing.radiusSm),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(KinrelSpacing.radiusSm),
        borderSide: BorderSide(
            color: KinrelColors.darkSurface.withValues(alpha: 0.3)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(KinrelSpacing.radiusSm),
        borderSide: const BorderSide(color: KinrelColors.purple),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(KinrelSpacing.radiusSm),
        borderSide: const BorderSide(color: KinrelColors.error),
      ),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontFamily: KinrelTypography.bodyFont,
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: KinrelColors.textSilver,
      ),
    );
  }
}

class _GenderChip extends StatelessWidget {
  const _GenderChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;


  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? KinrelColors.purple.withValues(alpha: 0.15)
              : KinrelColors.darkElevated,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color:
                selected ? KinrelColors.purple : KinrelColors.darkSurface,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: selected ? KinrelColors.purple : KinrelColors.textSilver,
          ),
        ),
      ),
    );
  }
}
