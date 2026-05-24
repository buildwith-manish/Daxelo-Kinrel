import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/constants/supported_languages.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/family/family_provider.dart';

class CreateFamilyScreen extends ConsumerStatefulWidget {
  const CreateFamilyScreen({super.key});

  @override
  ConsumerState<CreateFamilyScreen> createState() => _CreateFamilyScreenState();
}

class _CreateFamilyScreenState extends ConsumerState<CreateFamilyScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _gotraController = TextEditingController();
  final _originVillageController = TextEditingController();

  SupportedLanguage? _selectedLanguage;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _gotraController.dispose();
    _originVillageController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    final family = await createFamily(
      ref: ref,
      name: _nameController.text.trim(),
      description: _descriptionController.text.trim().isEmpty
          ? null
          : _descriptionController.text.trim(),
      primaryLanguage: _selectedLanguage?.code,
      gotra: _gotraController.text.trim().isEmpty
          ? null
          : _gotraController.text.trim(),
      originVillage: _originVillageController.text.trim().isEmpty
          ? null
          : _originVillageController.text.trim(),
    );

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (family != null) {
      context.showSnackBar('Family "${family.name}" created!');
      context.go('/family/${family.id}');
    } else {
      context.showSnackBar('Failed to create family. Please try again.',
          isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Create Family',
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontWeight: FontWeight.w600,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(KinrelSpacing.base),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Text(
                'Start Your Family Tree',
                style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: KinrelColors.textWhite,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Add your family details to begin building your kinship map.',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 14,
                  color: KinrelColors.textSilver,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 28),

              // Family Name
              _FormFieldLabel(label: 'Family Name *'),
              const SizedBox(height: 6),
              _BrandedTextField(
                controller: _nameController,
                hint: 'e.g., Sharma Family',
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Name is required' : null,
              ),
              const SizedBox(height: 20),

              // Description
              _FormFieldLabel(label: 'Description'),
              const SizedBox(height: 6),
              _BrandedTextField(
                controller: _descriptionController,
                hint: 'A brief description of your family',
                maxLines: 3,
              ),
              const SizedBox(height: 20),

              // Primary Language
              _FormFieldLabel(label: 'Primary Language'),
              const SizedBox(height: 6),
              _LanguageDropdown(
                selectedLanguage: _selectedLanguage,
                onChanged: (lang) =>
                    setState(() => _selectedLanguage = lang),
              ),
              const SizedBox(height: 20),

              // Gotra
              _FormFieldLabel(label: 'Gotra'),
              const SizedBox(height: 6),
              _BrandedTextField(
                controller: _gotraController,
                hint: 'e.g., Kashyap, Bharadwaj',
              ),
              const SizedBox(height: 20),

              // Origin Village / City
              _FormFieldLabel(label: 'Origin Village / City'),
              const SizedBox(height: 6),
              _BrandedTextField(
                controller: _originVillageController,
                hint: 'e.g., Jaipur, Rajasthan',
              ),
              const SizedBox(height: 36),

              // Submit Button
              FilledButton(
                onPressed: _isSubmitting ? null : _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: KinrelColors.orange,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor:
                      KinrelColors.orange.withValues(alpha: 0.4),
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
                        'Create Family',
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
}

class _FormFieldLabel extends StatelessWidget {
  final String label;
  const _FormFieldLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(
        fontFamily: KinrelTypography.bodyFont,
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: KinrelColors.textSilver,
      ),
    );
  }
}

class _BrandedTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final int maxLines;
  final String? Function(String?)? validator;

  const _BrandedTextField({
    required this.controller,
    required this.hint,
    this.maxLines = 1,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      validator: validator,
      maxLines: maxLines,
      style: TextStyle(
        fontFamily: KinrelTypography.bodyFont,
        fontSize: 15,
        color: KinrelColors.textWhite,
      ),
      decoration: InputDecoration(
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
          borderSide:
              BorderSide(color: KinrelColors.darkSurface.withValues(alpha: 0.3)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(KinrelSpacing.radiusSm),
          borderSide: const BorderSide(color: KinrelColors.orange),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(KinrelSpacing.radiusSm),
          borderSide: const BorderSide(color: KinrelColors.error),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }
}

class _LanguageDropdown extends StatelessWidget {
  final SupportedLanguage? selectedLanguage;
  final ValueChanged<SupportedLanguage?> onChanged;

  const _LanguageDropdown({
    required this.selectedLanguage,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: KinrelColors.darkElevated,
        borderRadius: BorderRadius.circular(KinrelSpacing.radiusSm),
        border:
            Border.all(color: KinrelColors.darkSurface.withValues(alpha: 0.3)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<SupportedLanguage>(
          value: selectedLanguage,
          hint: Text(
            'Select language',
            style: TextStyle(color: KinrelColors.textDim),
          ),
          isExpanded: true,
          icon: Icon(Icons.arrow_drop_down, color: KinrelColors.orange),
          dropdownColor: KinrelColors.darkElevated,
          items: SupportedLanguage.values.map((lang) {
            return DropdownMenuItem(
              value: lang,
              child: Row(
                children: [
                  Text(
                    lang.nativeName,
                    style: TextStyle(
                      color: KinrelColors.textWhite,
                      fontFamily: KinrelTypography.bodyFont,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '(${lang.name})',
                    style: TextStyle(
                      color: KinrelColors.textDim,
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}
