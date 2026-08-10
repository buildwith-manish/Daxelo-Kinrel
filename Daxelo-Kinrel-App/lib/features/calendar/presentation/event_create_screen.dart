// lib/features/calendar/presentation/event_create_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../shared/widgets/dk_components.dart';
import '../models/calendar_models.dart';
import '../providers/calendar_provider.dart';
import 'package:go_router/go_router.dart';

class EventCreateScreen extends ConsumerStatefulWidget {
  const EventCreateScreen({super.key, required this.familyId, this.existingEvent});
  final String familyId;
  final CalendarEvent? existingEvent;

  @override
  ConsumerState<EventCreateScreen> createState() => _EventCreateScreenState();
}

class _EventCreateScreenState extends ConsumerState<EventCreateScreen> {
  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  final _locationController = TextEditingController();
  DateTime _selectedDate = DateTime.now();
  EventCategory _category = EventCategory.custom;
  bool _isAllDay = true;
  bool _isRecurring = false;
  String? _recurrenceRule;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    if (widget.existingEvent != null) {
      final e = widget.existingEvent!;
      _titleController.text = e.title;
      _descController.text = e.description ?? '';
      _locationController.text = e.location ?? '';
      _selectedDate = e.eventDate;
      _category = e.category;
      _isAllDay = e.isAllDay;
      _isRecurring = e.isRecurring;
      _recurrenceRule = e.recurrenceRule;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context, initialDate: _selectedDate, firstDate: DateTime(1900), lastDate: DateTime(2100),
      builder: (context, child) => Theme(data: Theme.of(context).copyWith(colorScheme: ColorScheme.dark(primary: KinrelColors.orange, surface: KinrelColors.darkElevated, onSurface: KinrelColors.textWhite)), child: child!),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  Future<void> _save() async {
    if (_titleController.text.trim().isEmpty) return;
    setState(() => _isSaving = true);
    final event = CalendarEvent(
      id: widget.existingEvent?.id ?? '',
      familyId: widget.familyId,
      createdBy: '',
      title: _titleController.text.trim(),
      description: _descController.text.trim().isEmpty ? null : _descController.text.trim(),
      category: _category,
      eventDate: _selectedDate,
      location: _locationController.text.trim().isEmpty ? null : _locationController.text.trim(),
      isAllDay: _isAllDay,
      isRecurring: _isRecurring,
      recurrenceRule: _isRecurring ? _recurrenceRule : null,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    bool success;
    if (widget.existingEvent != null) {
      success = await ref.read(calendarProvider(widget.familyId).notifier).updateEvent(event);
    } else {
      success = await ref.read(calendarProvider(widget.familyId).notifier).createEvent(event);
    }
    if (mounted) {
      setState(() => _isSaving = false);
      if (success) if (context.canPop()) { context.pop(); } else { context.go('/family/${widget.familyId}'); }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existingEvent != null;
    return DKScaffold(
      backgroundColor: KinrelColors.darkSurface,
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.close), onPressed: () { if (context.canPop()) { context.pop(); } else { context.go('/family/${widget.familyId}'); } }),
        title: Text(isEditing ? 'Edit Event' : 'New Event', style: TextStyle(fontFamily: KinrelTypography.displayFont, fontWeight: FontWeight.w600)),
        backgroundColor: KinrelColors.darkCard, foregroundColor: KinrelColors.textWhite, elevation: 0,
        actions: [TextButton(onPressed: _isSaving ? null : _save, child: Text('Save', style: TextStyle(color: KinrelColors.orange, fontWeight: FontWeight.w700)))],
      ),
      body: SingleChildScrollView(padding: const EdgeInsets.all(KinrelSpacing.base), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Title
        TextField(controller: _titleController, style: TextStyle(color: KinrelColors.textWhite, fontSize: 18, fontFamily: KinrelTypography.displayFont, fontWeight: FontWeight.w600),
          decoration: InputDecoration(hintText: 'Event title', hintStyle: TextStyle(color: KinrelColors.textDim), filled: true, fillColor: KinrelColors.darkCard, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none), contentPadding: const EdgeInsets.all(16))),
        const SizedBox(height: 16),
        // Category picker
        Text('Category', style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 13, fontWeight: FontWeight.w600, color: KinrelColors.textDim)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: EventCategory.values.map((cat) => GestureDetector(
          onTap: () => setState(() => _category = cat),
          child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: _category == cat ? Color(cat.colorValue).withValues(alpha: 0.2) : KinrelColors.darkCard, borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _category == cat ? Color(cat.colorValue) : Colors.transparent, width: 1.5)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [Text(cat.icon, style: TextStyle(fontSize: 14)), const SizedBox(width: 6), Text(cat.label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: _category == cat ? Color(cat.colorValue) : KinrelColors.textDim))]),
          ),
        )).toList()),
        const SizedBox(height: 16),
        // Date
        Text('Date', style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 13, fontWeight: FontWeight.w600, color: KinrelColors.textDim)),
        const SizedBox(height: 8),
        GestureDetector(onTap: _pickDate, child: AbsorbPointer(child: Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: KinrelColors.darkCard, borderRadius: BorderRadius.circular(12)),
          child: Row(children: [Icon(Icons.calendar_today_outlined, color: KinrelColors.orange, size: 20), const SizedBox(width: 12),
            Text('${_selectedDate.month}/${_selectedDate.day}/${_selectedDate.year}', style: TextStyle(fontSize: 15, color: KinrelColors.textWhite, fontFamily: KinrelTypography.bodyFont)),
            const Spacer(), Icon(Icons.chevron_right, color: KinrelColors.textDim, size: 20)])))),
        const SizedBox(height: 16),
        // All day toggle
        _ToggleRow(label: 'All Day', value: _isAllDay, onChanged: (v) => setState(() => _isAllDay = v)),
        const SizedBox(height: 8),
        // Recurring toggle
        _ToggleRow(label: 'Recurring', value: _isRecurring, onChanged: (v) => setState(() => _isRecurring = v)),
        if (_isRecurring) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 6, children: ['daily', 'weekly', 'monthly', 'yearly'].map((r) => ChoiceChip(label: Text(r[0].toUpperCase() + r.substring(1)), selected: _recurrenceRule == r,
            onSelected: (_) => setState(() => _recurrenceRule = r), selectedColor: KinrelColors.orange, labelStyle: TextStyle(color: _recurrenceRule == r ? Colors.white : KinrelColors.textDim))).toList()),
        ],
        const SizedBox(height: 16),
        // Location
        TextField(controller: _locationController, style: TextStyle(color: KinrelColors.textWhite, fontSize: 15),
          decoration: InputDecoration(hintText: 'Location (optional)', hintStyle: TextStyle(color: KinrelColors.textDim), filled: true, fillColor: KinrelColors.darkCard,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none), contentPadding: const EdgeInsets.all(16), prefixIcon: Icon(Icons.location_on_outlined, color: KinrelColors.textDim, size: 20))),
        const SizedBox(height: 16),
        // Description
        TextField(controller: _descController, maxLines: 3, style: TextStyle(color: KinrelColors.textWhite, fontSize: 15),
          decoration: InputDecoration(hintText: 'Notes (optional)', hintStyle: TextStyle(color: KinrelColors.textDim), filled: true, fillColor: KinrelColors.darkCard,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none), contentPadding: const EdgeInsets.all(16))),
        if (_isSaving) ...[const SizedBox(height: 20), Center(child: CircularProgressIndicator(color: KinrelColors.orange))],
      ])),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({required this.label, required this.value, required this.onChanged});
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) => Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), decoration: BoxDecoration(color: KinrelColors.darkCard, borderRadius: BorderRadius.circular(12)),
    child: Row(children: [Text(label, style: TextStyle(fontSize: 15, color: KinrelColors.textWhite, fontFamily: KinrelTypography.bodyFont)), const Spacer(), Switch(value: value, onChanged: onChanged, activeColor: KinrelColors.orange)]));
}
