// lib/features/profile/presentation/quiet_hours_screen.dart
//
// DAXELO KINREL — Quiet Hours Screen
//
// Allows users to configure a daily quiet-hours window during
// which push notifications are silenced. Settings persist to
// Hive key 'quiet_hours' and sync to the backend via
// profileProvider.updateQuietHours().

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
// Hive removed — using shared_preferences for local settings
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/brand_typography.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/networking/dio_client.dart' show dioProvider;
import '../data/profile_provider.dart';

// ── Design Tokens ──────────────────────────────────────────────────
const Color _bg = Color(0xFF131416);
const Color _cardBg = Color(0xFF191B2C);
const Color _orange = Color(0xFFE8612A);
const Color _textPrimary = Color(0xFFF5F0EE);
const Color _textSecondary = Color(0xFFC9B4A8);
const Color _textDim = Color(0xFF8A7A72);
const Color _borderSubtle = Color(0x0FFFFFFF);

class QuietHoursScreen extends ConsumerStatefulWidget {
  const QuietHoursScreen({super.key});

  @override
  ConsumerState<QuietHoursScreen> createState() => _QuietHoursScreenState();
}

class _QuietHoursScreenState extends ConsumerState<QuietHoursScreen> {
  bool _enabled = false;
  TimeOfDay _startTime = const TimeOfDay(hour: 22, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 8, minute: 0);
  bool _isSaving = false;

  // P1.3: Smart notification timing opt-in (default OFF)
  bool _smartTimingOptIn = false;
  bool _smartTimingLoading = true;

  static const String _keyEnabled = 'enabled';
  static const String _keyStartHour = 'startHour';
  static const String _keyStartMinute = 'startMinute';
  static const String _keyEndHour = 'endHour';
  static const String _keyEndMinute = 'endMinute';

  @override
  void initState() {
    super.initState();
    _loadFromPrefs();
    _loadSmartTimingOptIn();
  }

  // P1.3: Fetch the user's smart notification timing opt-in status.
  Future<void> _loadSmartTimingOptIn() async {
    try {
      final dio = ref.read(dioProvider);
      final r = await dio.get('/api/notifications/timing-opt-in');
      if (mounted) {
        setState(() {
          _smartTimingOptIn = (r.data['optIn'] as bool?) ?? false;
          _smartTimingLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _smartTimingLoading = false);
    }
  }

  // P1.3: Toggle smart notification timing with a confirmation dialog.
  Future<void> _toggleSmartTiming(bool value) async {
    if (value) {
      // Show confirmation dialog before opting in.
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: _cardBg,
          title: const Text('Smart notification timing',
              style: TextStyle(color: _textPrimary)),
          content: const Text(
            'Kinrel will learn when you are most likely to engage with '
            'notifications and schedule non-urgent ones accordingly. '
            'Your engagement data is stored securely. You can turn this '
            'off at any time, and your learned data will be deleted.',
            style: TextStyle(color: _textSecondary, height: 1.5),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel', style: TextStyle(color: _textDim)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Enable', style: TextStyle(color: _orange)),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    setState(() => _smartTimingOptIn = value);
    try {
      final dio = ref.read(dioProvider);
      await dio.patch('/api/notifications/timing-opt-in', data: {'optIn': value});
    } catch (_) {
      // Revert on failure
      if (mounted) setState(() => _smartTimingOptIn = !value);
    }
  }

  Future<void> _loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.containsKey(_keyEnabled)) {
        setState(() {
          _enabled = prefs.getBool(_keyEnabled) ?? false;
          _startTime = TimeOfDay(
            hour: prefs.getInt(_keyStartHour) ?? 22,
            minute: prefs.getInt(_keyStartMinute) ?? 0,
          );
          _endTime = TimeOfDay(
            hour: prefs.getInt(_keyEndHour) ?? 8,
            minute: prefs.getInt(_keyEndMinute) ?? 0,
          );
        });
      }
    } catch (_) {
      // Use defaults if read fails
    }
  }

  Future<void> _saveToPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyEnabled, _enabled);
      await prefs.setInt(_keyStartHour, _startTime.hour);
      await prefs.setInt(_keyStartMinute, _startTime.minute);
      await prefs.setInt(_keyEndHour, _endTime.hour);
      await prefs.setInt(_keyEndMinute, _endTime.minute);
    } catch (_) {
      // Silently fail — backend is the source of truth
    }
  }

  String _formatTime(TimeOfDay time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  Future<void> _pickTime(bool isStart) async {
    final initial = isStart ? _startTime : _endTime;
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: _orange,
              onPrimary: Colors.white,
              surface: _cardBg,
              onSurface: _textPrimary,
            ),
            timePickerTheme: TimePickerThemeData(
              backgroundColor: _cardBg,
              hourMinuteColor: WidgetStateColor.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? _orange.withValues(alpha: 0.2)
                    : _bg,
              ),
              hourMinuteTextColor: WidgetStateColor.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? _orange
                    : _textPrimary,
              ),
              dialHandColor: _orange,
              dialBackgroundColor: _bg,
              dialTextColor: WidgetStateColor.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? Colors.white
                    : _textSecondary,
              ),
              entryModeIconColor: _orange,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        if (isStart) {
          _startTime = picked;
        } else {
          _endTime = picked;
        }
      });
    }
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);

    final start = _formatTime(_startTime);
    final end = _formatTime(_endTime);

    final success = await ref
        .read(profileProvider.notifier)
        .updateQuietHours(start, end, _enabled);

    if (!mounted) return;

    if (success) {
      await _saveToPrefs();
      if (mounted) {
        context.showSnackBar('Quiet hours saved successfully');
      }
    } else {
      if (mounted) {
        final error =
            ref.read(profileProvider).error ?? 'Failed to save quiet hours';
        context.showSnackBar(error, isError: true);
      }
    }

    setState(() => _isSaving = false);
  }

  @override
  Widget build(BuildContext context) {
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
          'Quiet Hours',
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: _textPrimary,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Enable Toggle ────────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _cardBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _borderSubtle),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: _orange.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.bedtime_outlined,
                      color: _orange,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Enable Quiet Hours',
                          style: TextStyle(
                            fontFamily: KinrelTypography.bodyFont,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: _textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _enabled ? 'Active' : 'Disabled',
                          style: TextStyle(
                            fontFamily: KinrelTypography.bodyFont,
                            fontSize: 12,
                            color: _enabled ? _orange : _textDim,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: _enabled,
                    onChanged: (v) => setState(() => _enabled = v),
                    activeThumbColor: Colors.white,
                    activeTrackColor: _orange.withValues(alpha: 0.7),
                    inactiveThumbColor: const Color(0xFF9E9E9E),
                    inactiveTrackColor: _cardBg,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // ── Time Range ───────────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _cardBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _borderSubtle),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Time Range',
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: _orange,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // From
                  _TimePickerRow(
                    label: 'From',
                    time: _formatTime(_startTime),
                    onTap: () => _pickTime(true),
                  ),

                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        Container(width: 1.5, height: 24, color: _borderSubtle),
                        const SizedBox(width: 12),
                        Icon(Icons.arrow_downward, color: _textDim, size: 16),
                      ],
                    ),
                  ),

                  // To
                  _TimePickerRow(
                    label: 'To',
                    time: _formatTime(_endTime),
                    onTap: () => _pickTime(false),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // ── Description ──────────────────────────────────────────
            if (_enabled)
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
                    Icon(
                      Icons.notifications_off_outlined,
                      color: _orange,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Notifications will be silenced during these hours',
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

            if (!_enabled)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _cardBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _borderSubtle),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.notifications_active_outlined,
                      color: _textDim,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Enable quiet hours to silence notifications during a specific time range',
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 13,
                          color: _textDim,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 32),

            // ── Save Button ──────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _orange,
                  disabledBackgroundColor: _orange.withValues(alpha: 0.5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                child: _isSaving
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
                        'Save',
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                          letterSpacing: 0.3,
                        ),
                      ),
              ),
            ),

            const SizedBox(height: 32),

            // ── P1.3: Smart Notification Timing ──────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _cardBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _borderSubtle),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: _orange.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.insights_outlined,
                          color: _orange,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Smart notification timing',
                              style: TextStyle(
                                fontFamily: KinrelTypography.bodyFont,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: _textPrimary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'When on, Kinrel learns when you are most likely '
                              'to engage and schedules non-urgent notifications '
                              'accordingly. When off, notifications use the time '
                              'you set above.',
                              style: const TextStyle(
                                color: _textDim,
                                fontSize: 12,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Semantics(
                        label:
                            'Smart notification timing. When on, Kinrel schedules '
                            'non-urgent notifications at your most active hours. '
                            'Currently ${_smartTimingOptIn ? 'on' : 'off'}.',
                        child: Switch(
                          value: _smartTimingOptIn,
                          onChanged: _smartTimingLoading ? null : _toggleSmartTiming,
                          activeColor: _orange,
                        ),
                      ),
                    ],
                  ),
                  if (_smartTimingOptIn) ...[
                    const SizedBox(height: 12),
                    TextButton.icon(
                      onPressed: () => context.push('/profile/notifications/learning-profile'),
                      icon: const Icon(Icons.visibility_outlined,
                          color: _orange, size: 16),
                      label: const Text('What has Kinrel learned?',
                          style: TextStyle(color: _orange, fontSize: 13)),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Time Picker Row
// ═══════════════════════════════════════════════════════════════════════

class _TimePickerRow extends StatelessWidget {
  const _TimePickerRow({
    required this.label,
    required this.time,
    required this.onTap,
  });

  final String label;
  final String time;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
          child: Row(
            children: [
              SizedBox(
                width: 52,
                child: Text(
                  label,
                  style: const TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: _textDim,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: _bg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _borderSubtle),
                ),
                child: Text(
                  time,
                  style: const TextStyle(
                    fontFamily: KinrelTypography.monoFont,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: _textPrimary,
                    letterSpacing: 1,
                  ),
                ),
              ),
              const Spacer(),
              const Icon(Icons.access_time, color: _textDim, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
