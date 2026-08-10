// lib/features/pulse/presentation/blessing_record_sheet.dart
//
// P1.1: Elder-side blessing recording UI.
//
// An elder (or family member on their behalf) can:
//   1. Record a voice blessing using the `record` package
//   2. Preview the recording before scheduling
//   3. Pick a recipient (any family member)
//   4. Pick a delivery date (birthday, festival, anniversary, custom)
//   5. Upload to Supabase Storage and create the blessing record
//
// Design rationale (Guardrail 2 — Warmth, not addiction):
//   The elder initiates. There is no system-pushed prompt, no streak,
//   no karma. The recording is the elder's voice — that is the entire
//   value. No manufactured urgency in the UI copy.

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:record/record.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/family/family_provider.dart';
import '../../../core/services/supabase_service.dart';
import '../data/pulse_api_client.dart';
import '../providers/pulse_providers.dart';
import 'package:go_router/go_router.dart';

/// Recording state for the blessing record sheet.
enum _RecordState {
  idle,
  recording,
  stopped,
  previewing,
  uploading,
  scheduled,
  error,
}

/// A bottom sheet for recording and scheduling a voice blessing.
///
/// Shown via [BlessingRecordSheet.show] from the Blessing Chain screen's FAB.
class BlessingRecordSheet extends ConsumerStatefulWidget {
  const BlessingRecordSheet({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: KinrelColors.darkBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const BlessingRecordSheet(),
    );
  }

  @override
  ConsumerState<BlessingRecordSheet> createState() =>
      _BlessingRecordSheetState();
}

class _BlessingRecordSheetState extends ConsumerState<BlessingRecordSheet> {
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _previewPlayer = AudioPlayer();

  _RecordState _state = _RecordState.idle;
  String? _recordingPath;
  Duration _recordingDuration = Duration.zero;
  String? _errorMessage;

  // Recipient + scheduling.
  String? _selectedRecipientId;
  String _triggerType = 'custom'; // birthday | festival | anniversary | custom
  DateTime _triggerDate = DateTime.now().add(const Duration(days: 1));
  bool _isRecurring = false;

  @override
  void dispose() {
    _recorder.dispose();
    _previewPlayer.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    try {
      setState(() {
        _state = _RecordState.recording;
        _errorMessage = null;
        _recordingPath = null;
        _recordingDuration = Duration.zero;
      });

      final recordPath = '${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 64000,
          sampleRate: 44100,
        ),
        path: recordPath,
      );
      setState(() => _recordingPath = recordPath);
    } catch (e) {
      setState(() {
        _state = _RecordState.error;
        _errorMessage = 'Could not start recording. Check microphone permissions.';
      });
    }
  }

  Future<void> _stopRecording() async {
    try {
      final path = await _recorder.stop();
      setState(() {
        _state = _RecordState.stopped;
        if (path != null) _recordingPath = path;
      });
    } catch (e) {
      setState(() {
        _state = _RecordState.error;
        _errorMessage = 'Recording could not be saved.';
      });
    }
  }

  Future<void> _previewRecording() async {
    if (_recordingPath == null) return;
    try {
      setState(() => _state = _RecordState.previewing);
      await _previewPlayer.setFilePath(_recordingPath!);
      _previewPlayer.playerStateStream.listen((state) {
        if (state.processingState == ProcessingState.completed && mounted) {
          setState(() => _state = _RecordState.stopped);
        }
      });
      await _previewPlayer.play();
    } catch (e) {
      setState(() {
        _state = _RecordState.error;
        _errorMessage = 'Could not play the preview.';
      });
    }
  }

  Future<void> _scheduleBlessing() async {
    if (_recordingPath == null || _selectedRecipientId == null) {
      setState(() => _errorMessage = 'Record a blessing and pick a recipient.');
      return;
    }

    final familyId = ref.read(currentFamilyIdProvider);
    if (familyId == null) {
      setState(() => _errorMessage = 'Select a family first.');
      return;
    }

    setState(() {
      _state = _RecordState.uploading;
      _errorMessage = null;
    });

    try {
      final supabase = ref.read(supabaseProvider);
      if (supabase == null) {
        setState(() {
          _state = _RecordState.error;
          _errorMessage = 'Connection not ready. Please try again.';
        });
        return;
      }

      // Upload to Supabase Storage: blessings bucket.
      // Path: family/{familyId}/blessings/{timestamp}.m4a
      final fileName =
          'family/$familyId/blessings/${DateTime.now().millisecondsSinceEpoch}.m4a';
      final fileBytes = await File(_recordingPath!).readAsBytes();
      await supabase.storage.from('blessings').uploadBinary(
            fileName,
            fileBytes,
          );
      final mediaUrl = supabase.storage.from('blessings').getPublicUrl(fileName);

      // Get the current user's linked Person ID (the elder).
      // For simplicity, we pass the recipientPersonId and let the server
      // resolve the elder from the auth context.
      final client = ref.read(pulseApiClientProvider);
      await client.createBlessing({
        'familyId': familyId,
        'recipientPersonId': _selectedRecipientId,
        'mediaType': 'audio',
        'mediaUrl': mediaUrl,
        'durationSec': _recordingDuration.inSeconds,
        'triggerType': _triggerType,
        'triggerDate': _triggerDate.toIso8601String().split('T').first,
        'isRecurring': _isRecurring,
      });

      setState(() => _state = _RecordState.scheduled);
    } catch (e) {
      setState(() {
        _state = _RecordState.error;
        _errorMessage = 'Could not schedule the blessing. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final familyId = ref.watch(currentFamilyIdProvider);
    final screenHeight = MediaQuery.of(context).size.height;

    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SizedBox(
        height: screenHeight * 0.85,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ──
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Record a Blessing',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white54),
                  onPressed: () { if (context.canPop()) { context.pop(); } else { context.go('/home'); } },
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Record a voice blessing for a family member. '
              'They will receive it on the date you choose.',
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 24),

            // ── Record button ──
            _buildRecordButton(),

            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                style: TextStyle(color: Colors.red.shade300, fontSize: 13),
              ),
            ],

            if (_state == _RecordState.scheduled) ...[
              const SizedBox(height: 24),
              _buildSuccessMessage(),
            ] else ...[
              const SizedBox(height: 24),

              // ── Recipient picker ──
              if (familyId != null) _buildRecipientPicker(familyId),

              const SizedBox(height: 16),

              // ── Date picker ──
              _buildDateRow(),

              const SizedBox(height: 16),

              // ── Recurring toggle ──
              _buildRecurringToggle(),

              const Spacer(),

              // ── Schedule button ──
              _buildScheduleButton(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRecordButton() {
    final isRecording = _state == _RecordState.recording;
    return Center(
      child: Semantics(
        label: isRecording
            ? 'Recording. Double-tap to stop.'
            : 'Record a voice blessing. Double-tap to start.',
        button: true,
        child: GestureDetector(
          onTap: isRecording ? _stopRecording : _startRecording,
          child: Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: isRecording
                  ? Colors.red.shade400
                  : KinrelColors.gold,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: (isRecording
                          ? Colors.red.shade400
                          : KinrelColors.gold)
                      .withOpacity(0.3),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Icon(
              isRecording ? Icons.stop : Icons.mic,
              color: Colors.white,
              size: 36,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRecipientPicker(String familyId) {
    final membersAsync = ref.watch(familyMembersProvider(familyId));
    return membersAsync.when(
      loading: () => const SizedBox(
        height: 56,
        child: Center(
          child: CircularProgressIndicator(color: KinrelColors.gold),
        ),
      ),
      error: (e, _) => Text(
        'Could not load family members.',
        style: TextStyle(color: Colors.red.shade300, fontSize: 13),
      ),
      data: (members) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Recipient',
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: KinrelColors.darkCard,
                borderRadius: BorderRadius.circular(12),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedRecipientId,
                  hint: Text(
                    'Choose a family member',
                    style: TextStyle(color: Colors.white.withOpacity(0.4)),
                  ),
                  dropdownColor: KinrelColors.darkCard,
                  isExpanded: true,
                  items: members
                      .where((m) => !m.isDeceased)
                      .map((m) => DropdownMenuItem(
                            value: m.id,
                            child: Text(
                              m.name,
                              style: const TextStyle(color: Colors.white),
                            ),
                          ))
                      .toList(),
                  onChanged: (id) =>
                      setState(() => _selectedRecipientId = id),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDateRow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Deliver on',
          style: TextStyle(
            color: Colors.white.withOpacity(0.7),
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: KinrelColors.darkCard,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _triggerType,
                    dropdownColor: KinrelColors.darkCard,
                    isExpanded: true,
                    items: const [
                      DropdownMenuItem(
                          value: 'custom', child: Text('Custom date')),
                      DropdownMenuItem(
                          value: 'birthday', child: Text('Birthday')),
                      DropdownMenuItem(
                          value: 'anniversary', child: Text('Anniversary')),
                      DropdownMenuItem(
                          value: 'festival', child: Text('Festival')),
                    ],
                    onChanged: (v) =>
                        setState(() => _triggerType = v ?? 'custom'),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Container(
              decoration: BoxDecoration(
                color: KinrelColors.darkCard,
                borderRadius: BorderRadius.circular(12),
              ),
              child: TextButton.icon(
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _triggerDate,
                    firstDate: DateTime.now(),
                    lastDate:
                        DateTime.now().add(const Duration(days: 365 * 5)),
                  );
                  if (picked != null) {
                    setState(() => _triggerDate = picked);
                  }
                },
                icon: const Icon(Icons.calendar_today,
                    color: KinrelColors.gold, size: 18),
                label: Text(
                  '${_triggerDate.day}/${_triggerDate.month}/${_triggerDate.year}',
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildRecurringToggle() {
    return Row(
      children: [
        Switch(
          value: _isRecurring,
          onChanged: (v) => setState(() => _isRecurring = v),
          activeColor: KinrelColors.gold,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Deliver every year on this date',
            style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 13),
          ),
        ),
      ],
    );
  }

  Widget _buildScheduleButton() {
    final isUploading = _state == _RecordState.uploading;
    final canSchedule =
        _recordingPath != null && _selectedRecipientId != null && !isUploading;

    return SizedBox(
      width: double.infinity,
      height: 52,
      child: FilledButton(
        onPressed: canSchedule ? _scheduleBlessing : null,
        style: FilledButton.styleFrom(
          backgroundColor:
              canSchedule ? KinrelColors.gold : KinrelColors.darkCard,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: isUploading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            : Text(
                'Schedule blessing',
                style: TextStyle(
                  color: canSchedule ? Colors.white : Colors.white38,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
      ),
    );
  }

  Widget _buildSuccessMessage() {
    return Center(
      child: Column(
        children: [
          const Icon(Icons.check_circle,
              color: KinrelColors.gold, size: 56),
          const SizedBox(height: 16),
          const Text(
            'Blessing scheduled',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Your blessing will be delivered on '
            '${_triggerDate.day}/${_triggerDate.month}/${_triggerDate.year}.',
            style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          TextButton(
            onPressed: () { if (context.canPop()) { context.pop(); } else { context.go('/home'); } },
            child: const Text('Done',
                style: TextStyle(color: KinrelColors.gold, fontSize: 15)),
          ),
        ],
      ),
    );
  }
}
