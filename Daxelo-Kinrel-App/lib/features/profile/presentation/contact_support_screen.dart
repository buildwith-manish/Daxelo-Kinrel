// lib/features/profile/presentation/contact_support_screen.dart
//
// DAXELO KINREL — Contact Support Screen
//
// Form with subject dropdown, message, screenshot attachment,
// and send button. Auto-fills user email from profile.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/constants/brand_typography.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/utils/api_error_mapper.dart';
import '../data/profile_provider.dart';

// ── Design Tokens ──────────────────────────────────────────────────
const Color _bg = Color(0xFF131416);
const Color _cardBg = Color(0xFF191B2C);
const Color _orange = Color(0xFFE8612A);
const Color _textPrimary = Color(0xFFF5F0EE);
const Color _textSecondary = Color(0xFFC9B4A8);
const Color _textDim = Color(0xFF8A7A72);
const Color _borderSubtle = Color(0x0FFFFFFF);

// ── Subject Options ────────────────────────────────────────────────
const List<String> _subjectOptions = [
  'Bug Report',
  'Feature Request',
  'Account Issue',
  'Other',
];

class ContactSupportScreen extends ConsumerStatefulWidget {
  const ContactSupportScreen({super.key});

  @override
  ConsumerState<ContactSupportScreen> createState() =>
      _ContactSupportScreenState();
}

class _ContactSupportScreenState extends ConsumerState<ContactSupportScreen> {
  String? _selectedSubject;
  final _messageController = TextEditingController();
  String? _attachedImagePath;
  bool _isSending = false;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    // Load profile to get email
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(profileProvider.notifier).loadProfile();
    });
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  bool get _canSend =>
      _selectedSubject != null &&
      _messageController.text.trim().length >= 20 &&
      !_isSending;

  Future<void> _pickScreenshot() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 80,
      );
      if (picked != null) {
        setState(() => _attachedImagePath = picked.path);
      }
    } catch (e) {
      if (mounted) {
        context.showSnackBar('Failed to pick image', isError: true);
      }
    }
  }

  void _removeScreenshot() {
    setState(() => _attachedImagePath = null);
  }

  Future<void> _sendTicket() async {
    if (!_canSend) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSending = true);

    final profileState = ref.read(profileProvider);
    final email = profileState.profile?.email ?? '';

    final data = <String, dynamic>{
      'subject': _selectedSubject,
      'message': _messageController.text.trim(),
      'email': email,
      'type': 'support',
      if (_attachedImagePath != null) 'hasAttachment': true,
    };

    final success = await ref
        .read(profileProvider.notifier)
        .submitSupportTicket(data);

    if (!mounted) return;

    setState(() => _isSending = false);

    if (success) {
      context.showSnackBar(
        "Support ticket submitted! We'll reply within 24 hours",
      );
      context.pop();
    } else {
      final error = ref.read(profileProvider).error ?? 'Failed to submit ticket';
      final fieldErrors = mapApiError(error);
      if (fieldErrors != null) {
        final formError = fieldErrors['form'] ?? fieldErrors.values.first;
        context.showSnackBar(formError, isError: true);
      } else {
        context.showSnackBar(
          'Failed to submit ticket. Please try again.',
          isError: true,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileState = ref.watch(profileProvider);
    final email = profileState.profile?.email ?? '';

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: _textPrimary),
          onPressed: () => context.pop(),
        ),
        title: const Text(
          'Contact Support',
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: _textPrimary,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Info Banner ──────────────────────────────────────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _orange.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _orange.withValues(alpha: 0.2)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: _orange, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        "We'll get back to you within 24 hours.",
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 13,
                          color: _textSecondary,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // ── Email (auto-filled, read-only) ──────────────────
              if (email.isNotEmpty) ...[
                _buildFieldLabel('Your Email'),
                const SizedBox(height: 8),
                _buildReadOnlyField(email, Icons.email_outlined),
                const SizedBox(height: 20),
              ],

              // ── Subject Dropdown ────────────────────────────────
              _buildFieldLabel('Subject'),
              const SizedBox(height: 8),
              _buildSubjectDropdown(),
              const SizedBox(height: 20),

              // ── Message ─────────────────────────────────────────
              _buildFieldLabel('Message'),
              if (_messageController.text.trim().isNotEmpty &&
                  _messageController.text.trim().length < 20)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Minimum 20 characters (${_messageController.text.trim().length}/20)',
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 11,
                      color: _orange,
                    ),
                  ),
                )
              else
                const SizedBox(height: 4),
              const SizedBox(height: 4),
              _buildMessageField(),
              const SizedBox(height: 20),

              // ── Attach Screenshot ───────────────────────────────
              _buildFieldLabel('Attach Screenshot (optional)'),
              const SizedBox(height: 8),
              _buildScreenshotSection(),
              const SizedBox(height: 32),

              // ── Send Button ─────────────────────────────────────
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _canSend ? _sendTicket : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _orange,
                    disabledBackgroundColor: _orange.withValues(alpha: 0.3),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: _isSending
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
                      : const Text(
                          'Send',
                          style: TextStyle(
                            fontFamily: KinrelTypography.bodyFont,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Helper Builders ──────────────────────────────────────────────

  Widget _buildFieldLabel(String label) {
    return Text(
      label,
      style: const TextStyle(
        fontFamily: KinrelTypography.bodyFont,
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: _textSecondary,
        letterSpacing: 0.3,
      ),
    );
  }

  Widget _buildReadOnlyField(String value, IconData icon) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: _cardBg.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _borderSubtle),
      ),
      child: Row(
        children: [
          Icon(icon, color: _textDim, size: 18),
          const SizedBox(width: 10),
          Text(
            value,
            style: const TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 14,
              color: _textDim,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubjectDropdown() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _selectedSubject != null
              ? _orange.withValues(alpha: 0.3)
              : _borderSubtle,
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedSubject,
          hint: Text(
            'Select a subject',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 15,
              color: _textDim.withValues(alpha: 0.7),
            ),
          ),
          icon: Icon(Icons.arrow_drop_down, color: _textDim),
          isExpanded: true,
          dropdownColor: _cardBg,
          style: const TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 15,
            color: _textPrimary,
          ),
          items: _subjectOptions.map((subject) {
            return DropdownMenuItem<String>(
              value: subject,
              child: Text(subject),
            );
          }).toList(),
          onChanged: (value) {
            setState(() => _selectedSubject = value);
          },
        ),
      ),
    );
  }

  Widget _buildMessageField() {
    return TextFormField(
      controller: _messageController,
      onChanged: (_) => setState(() {}),
      textCapitalization: TextCapitalization.sentences,
      textInputAction: TextInputAction.done,
      minLines: 5,
      maxLines: 10,
      style: const TextStyle(
        fontFamily: KinrelTypography.bodyFont,
        fontSize: 15,
        color: _textPrimary,
        height: 1.5,
      ),
      decoration: InputDecoration(
        hintText: 'Describe your issue or question in detail...',
        hintStyle: TextStyle(
          fontFamily: KinrelTypography.bodyFont,
          fontSize: 15,
          color: _textDim.withValues(alpha: 0.6),
        ),
        filled: true,
        fillColor: _cardBg,
        contentPadding: const EdgeInsets.all(16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _borderSubtle),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _orange, width: 1.5),
        ),
      ),
      validator: (value) {
        if (value == null || value.trim().length < 20) {
          return 'Please enter at least 20 characters';
        }
        return null;
      },
    );
  }

  Widget _buildScreenshotSection() {
    if (_attachedImagePath != null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _cardBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _orange.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            // Thumbnail
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(
                File(_attachedImagePath!),
                width: 56,
                height: 56,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  width: 56,
                  height: 56,
                  color: _bg,
                  child: const Icon(
                    Icons.broken_image,
                    color: _textDim,
                    size: 24,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Screenshot attached',
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: _textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _attachedImagePath!.split('/').last,
                    style: const TextStyle(
                      fontFamily: KinrelTypography.monoFont,
                      fontSize: 11,
                      color: _textDim,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: _removeScreenshot,
              icon: const Icon(Icons.close, color: _textDim, size: 20),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      height: 52,
      child: OutlinedButton.icon(
        onPressed: _pickScreenshot,
        icon: const Icon(Icons.add_photo_alternate_outlined, size: 20),
        label: const Text(
          'Attach Screenshot',
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: _orange,
          ),
        ),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: _orange.withValues(alpha: 0.4), width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}
