// =============================================================================
// Track C v2.0 — Decision Create Screen (multi-step wizard)
// =============================================================================
// Implements the decision-creation flow described in Section 10.2 of the
// FINAL v2.0 spec. Three steps:
//
//   Step 1 — Basics:        title, description, decision type
//   Step 2 — Options:       list of vote options (min 2, max 6)
//   Step 3 — Quorum + deadline: quorumPct, deadlineAt, showVotesLive
//
// Validation rules (each enforced before advancing to the next step):
//   - Step 1 → 2: title is non-empty after trim; type is one of the four
//     allowed kinds (simple_vote, consensus, elder_council, constitution_amend).
//   - Step 2 → 3: at least 2 non-empty option strings after trim; no duplicates.
//   - Step 3 → submit: deadline is in the future; quorumPct is between 1 and 100.
//
// Back/forward behavior: form state is preserved in the State object, so the
// user can navigate back to a previous step, edit, and return without losing
// entered data. The Submit button calls `TrackcApiClient.createDecision()`
// with the assembled payload.
//
// This screen is NOT yet wired into the GoRouter (it's launched modally from
// `TrackcDecisionsListScreen` via `Navigator.push`), because it has no
// meaningful deep-link URL of its own. If deep-linking becomes a requirement
// later, add a `decision-create` route under `/family/:id/governance/decisions`.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/trackc_providers.dart';

class TrackcDecisionCreateScreen extends ConsumerStatefulWidget {
  const TrackcDecisionCreateScreen({super.key});

  @override
  ConsumerState<TrackcDecisionCreateScreen> createState() =>
      _TrackcDecisionCreateScreenState();
}

class _TrackcDecisionCreateScreenState
    extends ConsumerState<TrackcDecisionCreateScreen> {
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _quorumController = TextEditingController(text: '50');
  final List<TextEditingController> _optionControllers = [
    TextEditingController(text: 'Yes'),
    TextEditingController(text: 'No'),
  ];

  String _selectedType = 'simple_vote';
  DateTime? _deadline;
  bool _showVotesLive = false;
  bool _isSubmitting = false;

  int _currentStep = 0;
  static const int _totalSteps = 3;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _quorumController.dispose();
    for (final c in _optionControllers) {
      c.dispose();
    }
    super.dispose();
  }

  // ── Step validation ────────────────────────────────────────────────────

  /// Validation error for the current step, or null if the step is valid.
  /// Used to block the Next button and to surface inline error text.
  String? _stepValidationError() {
    switch (_currentStep) {
      case 0:
        // Step 1 — Basics
        final title = _titleController.text.trim();
        if (title.isEmpty) return 'Title is required';
        if (title.length > 200) return 'Title must be 200 characters or fewer';
        const allowedTypes = {
          'simple_vote',
          'consensus',
          'elder_council',
          'constitution_amend',
        };
        if (!allowedTypes.contains(_selectedType)) {
          return 'Invalid decision type';
        }
        return null;
      case 1:
        // Step 2 — Options
        final options = _optionControllers.map((c) => c.text.trim()).toList();
        final nonEmpty = options.where((s) => s.isNotEmpty).toList();
        if (nonEmpty.length < 2) {
          return 'At least 2 options are required';
        }
        // Check for duplicates (case-insensitive)
        final lower = nonEmpty.map((s) => s.toLowerCase()).toList();
        final unique = lower.toSet();
        if (unique.length != lower.length) {
          return 'Options must be unique (no duplicates)';
        }
        return null;
      case 2:
        // Step 3 — Quorum + deadline
        final quorumPct = int.tryParse(_quorumController.text.trim());
        if (quorumPct == null || quorumPct < 1 || quorumPct > 100) {
          return 'Quorum must be an integer between 1 and 100';
        }
        // Constitution amendments require ≥67% supermajority (Section 10.2)
        if (_selectedType == 'constitution_amend' && quorumPct < 67) {
          return 'Constitution amendments require ≥67% quorum';
        }
        if (_deadline == null) return 'Deadline is required';
        if (_deadline!.isBefore(DateTime.now())) {
          return 'Deadline must be in the future';
        }
        return null;
      default:
        return null;
    }
  }

  bool get _isLastStep => _currentStep == _totalSteps - 1;

  void _next() {
    final err = _stepValidationError();
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err), backgroundColor: Colors.red),
      );
      return;
    }
    if (!_isLastStep) {
      setState(() => _currentStep++);
    } else {
      _submit();
    }
  }

  void _back() {
    if (_currentStep > 0) {
      setState(() => _currentStep--);
    } else {
      Navigator.of(context).maybePop();
    }
  }

  void _addOption() {
    if (_optionControllers.length >= 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Maximum 6 options allowed')),
      );
      return;
    }
    setState(() {
      _optionControllers.add(TextEditingController());
    });
  }

  void _removeOption(int index) {
    if (_optionControllers.length <= 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('At least 2 options are required')),
      );
      return;
    }
    setState(() {
      _optionControllers[index].dispose();
      _optionControllers.removeAt(index);
    });
  }

  Future<void> _pickDeadline() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 7)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked == null) return;
    if (!mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now.add(const Duration(hours: 1))),
    );
    if (time == null) return;
    setState(() {
      _deadline = DateTime(picked.year, picked.month, picked.day, time.hour, time.minute);
    });
  }

  Future<void> _submit() async {
    setState(() => _isSubmitting = true);
    try {
      final familyId = ref.read(selectedFamilyIdProvider);
      if (familyId == null) {
        throw StateError('No family selected');
      }
      final api = ref.read(trackcApiClientProvider);

      final options = _optionControllers
          .map((c) => c.text.trim())
          .where((s) => s.isNotEmpty)
          .toList();

      await api.createDecision(familyId, {
        'title': _titleController.text.trim(),
        'description': _descriptionController.text.trim(),
        'type': _selectedType,
        'options': options,
        'quorumPct': int.parse(_quorumController.text.trim()),
        'showVotesLive': _showVotesLive,
        'deadlineAt': _deadline!.toUtc().toIso8601String(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Decision created')),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create decision: $e'),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  // ── UI ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final validationError = _stepValidationError();

    return Scaffold(
      appBar: AppBar(
        title: const Text('New Decision'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: Column(
        children: [
          // Stepper indicator
          LinearProgressIndicator(
            value: (_currentStep + 1) / _totalSteps,
            minHeight: 4,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Text('Step ${_currentStep + 1} of $_totalSteps',
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.grey[600], fontWeight: FontWeight.w600)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _stepTitle(_currentStep),
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ],
            ),
          ),
          // Step body
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: _stepBody(_currentStep),
            ),
          ),
          // Validation error banner (if any)
          if (validationError != null)
            Container(
              width: double.infinity,
              color: Colors.red.shade50,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.error_outline, color: Colors.red.shade700, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      validationError,
                      style: TextStyle(color: Colors.red.shade900, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          // Bottom action bar
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  TextButton(
                    onPressed: _isSubmitting ? null : _back,
                    child: Text(_currentStep == 0 ? 'Cancel' : 'Back'),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: _isSubmitting ? null : _next,
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : Text(_isLastStep ? 'Create' : 'Next'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _stepTitle(int step) {
    switch (step) {
      case 0:
        return 'Basics';
      case 1:
        return 'Vote Options';
      case 2:
        return 'Quorum & Deadline';
      default:
        return '';
    }
  }

  List<Widget> _stepBody(int step) {
    switch (step) {
      case 0:
        return [
          TextField(
            controller: _titleController,
            decoration: const InputDecoration(
              labelText: 'Title *',
              hintText: 'e.g. Where should we host Diwali 2026?',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _descriptionController,
            decoration: const InputDecoration(
              labelText: 'Description (optional)',
              hintText: 'Provide context for voters',
              border: OutlineInputBorder(),
            ),
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            value: _selectedType,
            decoration: const InputDecoration(
              labelText: 'Decision type *',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(
                  value: 'simple_vote', child: Text('Simple Vote (majority)')),
              DropdownMenuItem(
                  value: 'consensus', child: Text('Consensus (unanimous)')),
              DropdownMenuItem(
                  value: 'elder_council', child: Text('Elder Council')),
              DropdownMenuItem(
                  value: 'constitution_amend',
                  child: Text('Constitution Amendment (≥67%)')),
            ],
            onChanged: (v) => setState(() => _selectedType = v ?? 'simple_vote'),
          ),
          const SizedBox(height: 8),
          Text(
            _typeHint(_selectedType),
            style: TextStyle(color: Colors.grey[600], fontSize: 12),
          ),
        ];
      case 1:
        return [
          const Text('Define the vote options voters can choose between.',
              style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 16),
          ..._optionControllers.asMap().entries.map((entry) {
            final i = entry.key;
            final c = entry.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: c,
                      decoration: InputDecoration(
                        labelText: 'Option ${i + 1}',
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline),
                    color: Colors.red,
                    onPressed: _optionControllers.length <= 2
                        ? null
                        : () => _removeOption(i),
                  ),
                ],
              ),
            );
          }),
          if (_optionControllers.length < 6)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _addOption,
                icon: const Icon(Icons.add),
                label: const Text('Add option'),
              ),
            )
          else
            // When at the max, show a disabled hint so the user understands
            // why they can't add more. (The _addOption() method also defends
            // against this and shows a snackbar if invoked programmatically.)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Maximum 6 options reached',
                style: TextStyle(color: Colors.grey[600], fontSize: 12),
              ),
            ),
        ];
      case 2:
        return [
          TextField(
            controller: _quorumController,
            decoration: const InputDecoration(
              labelText: 'Quorum % *',
              hintText: '1–100',
              border: OutlineInputBorder(),
              suffixText: '%',
            ),
            keyboardType: TextInputType.number,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          if (_selectedType == 'constitution_amend')
            Text(
              'Constitution amendments require ≥67% quorum per Section 10.2.',
              style: TextStyle(color: Colors.orange.shade800, fontSize: 12),
            ),
          const SizedBox(height: 16),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Deadline *'),
            subtitle: Text(_deadline == null
                ? 'No deadline selected'
                : '${_deadline!.toLocal()}'.split('.').first),
            trailing: IconButton(
              icon: const Icon(Icons.calendar_today),
              onPressed: _pickDeadline,
            ),
            onTap: _pickDeadline,
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Show votes live'),
            subtitle: const Text(
                'If on, voters see the running tally as votes are cast. '
                'Off by default to reduce bandwagon effects.'),
            value: _showVotesLive,
            onChanged: (v) => setState(() => _showVotesLive = v),
          ),
          const SizedBox(height: 24),
          Card(
            color: Colors.blue.shade50,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue.shade700, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Review the decision summary before creating. '
                      'You can edit an open decision\'s title and deadline after creation, '
                      'but not its type or options.',
                      style: TextStyle(color: Colors.blue.shade900, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ];
      default:
        return [const Text('Unknown step')];
    }
  }

  String _typeHint(String type) {
    switch (type) {
      case 'simple_vote':
        return 'Majority of cast votes wins. Default quorum: 50%.';
      case 'consensus':
        return 'Requires 100% unanimous approval from all eligible voters.';
      case 'elder_council':
        return 'Only family elders are eligible to vote. Majority of elders wins.';
      case 'constitution_amend':
        return 'Proposes an amendment to the family constitution. Requires ≥67% supermajority.';
      default:
        return '';
    }
  }
}
