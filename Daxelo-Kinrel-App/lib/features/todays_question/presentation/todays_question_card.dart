// lib/features/todays_question/presentation/todays_question_card.dart
//
// DAXELO KINREL — Phase B — Today's Question card.
//
// Renders one of four states driven by `todaysQuestionProvider` +
// `oralHistoryProvider.recordingState`:
//
//   • noElder        → "Add your first memory" CTA (no fake question).
//   • hidden         → zero-height SizedBox (skipped/answered this cycle).
//   • visible/idle   → question + mic button (tap to start) + Skip.
//   • recording      → live timer + waveform + tap-to-stop (max 3 min).
//   • preview        → Play / Save / Discard.
//   • saving         → spinner + "Saving…".
//   • error          → message + Retry button. If permissionDenied,
//                      show "Open Settings" instead of Retry.
//
// Recording UX (per spec):
//   • Tap-to-start, tap-to-stop — NOT press-and-hold (elders struggle).
//   • Max 3 minutes (auto-stop + jump to preview).
//   • First-time-only consent notice per (familyId, elderPersonId).
//   • App backgrounding → auto-pause (WidgetsBindingObserver).
//   • Permission denied → clear error + "Open Settings" button.
//   • Upload failure → local file preserved; "Retry Save" surfaces.
//   • Reuses OralHistoryNotifier's recorder + upload path (NO third
//     recorder). Calls the new `saveFromTodaysQuestion` extension
//     method on OralHistoryNotifier.

import 'dart:io' show File;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:just_audio/just_audio.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/kinship/kinship_term_providers.dart' show kinshipTermLanguageProvider;
import '../../../core/services/haptic_service.dart';
import '../../../core/utils/accessibility_utils.dart';
import '../../oral_history/providers/oral_history_provider.dart';
import '../providers/todays_question_provider.dart';
import '../widgets/recording_waveform.dart';

const _cOrange = KinrelColors.orange;
const _cCard = KinrelColors.darkCard;
const _cElevated = KinrelColors.darkElevated;
const _cTextPrimary = KinrelColors.textWhite;
const _cTextSecondary = KinrelColors.textSilver;
const _cTextDim = KinrelColors.textDim;
const _cError = KinrelColors.error;

/// Maximum recording duration. The recorder auto-stops when this is
/// reached and jumps to the preview state.
const _kMaxRecordingDuration = Duration(minutes: 3);

/// The Today's Question card. Inserted into the Phase B slot in
/// HomeScreen._buildUnifiedHomeView (replacing the TODO comment).
class TodaysQuestionCard extends ConsumerStatefulWidget {
  const TodaysQuestionCard({super.key, required this.familyId});

  final String familyId;

  @override
  ConsumerState<TodaysQuestionCard> createState() =>
      _TodaysQuestionCardState();
}

class _TodaysQuestionCardState extends ConsumerState<TodaysQuestionCard>
    with WidgetsBindingObserver {
  /// Local preview player for the recorded file (before Save). Null
  /// until the user enters the preview state.
  AudioPlayer? _previewPlayer;

  /// Local preview playback position + duration (drives the seek bar
  /// in the preview state).
  Duration _previewPosition = Duration.zero;
  Duration _previewDuration = Duration.zero;
  bool _previewIsPlaying = false;

  /// The path of the recorded file currently being previewed. Set
  /// when the user taps Stop. Cleared on Save or Discard.
  String? _previewPath;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _disposePreviewPlayer();
    super.dispose();
  }

  void _disposePreviewPlayer() {
    _previewPlayer?.dispose();
    _previewPlayer = null;
    _previewPosition = Duration.zero;
    _previewDuration = Duration.zero;
    _previewIsPlaying = false;
  }

  // ── App lifecycle: pause recording on backgrounding ──────────────
  // The `record` package keeps recording when the app backgrounds on
  // some platforms, but for an elder-facing question flow it's safer
  // to pause: the user may have backgrounded the app to answer a
  // call or check a message, and we don't want to keep capturing
  // audio they didn't intend to record. They can tap Resume when
  // they return.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      final rec = ref.read(oralHistoryProvider).recordingState;
      if (rec.isRecording && !rec.isPaused) {
        ref.read(oralHistoryProvider.notifier).pauseRecording();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final questionAsync = ref.watch(todaysQuestionProvider(widget.familyId));
    final oralHistoryState = ref.watch(oralHistoryProvider);
    final recordingState = oralHistoryState.recordingState;

    return questionAsync.when(
      loading: () => const _CardSkeleton(),
      error: (e, _) => _CardError(
        message: 'Could not load today\'s question. Pull to refresh.',
        onRetry: () =>
            ref.invalidate(todaysQuestionProvider(widget.familyId)),
      ),
      data: (state) {
        switch (state.visibility) {
          case TodaysQuestionVisibility.hidden:
            // Cooldown — user already acted this cycle. Hide the
            // card entirely (zero height, no padding).
            return const SizedBox(width: 0, height: 0);

          case TodaysQuestionVisibility.noElder:
            return _NoElderCard(familyId: widget.familyId);

          case TodaysQuestionVisibility.visible:
            final pick = state.pick!;
            // Sub-state machine: idle → recording → preview → saving → done
            if (recordingState.isSaving) {
              return _SavingCard(pick: pick);
            }
            if (recordingState.error != null && !recordingState.isRecording) {
              return _ErrorCard(
                pick: pick,
                message: recordingState.error!,
                permissionDenied: recordingState.permissionDenied,
                onRetry: () {
                  ref
                      .read(oralHistoryProvider.notifier)
                      .clearRecordingError();
                },
                onOpenSettings: () => _openAppSettings(),
              );
            }
            if (recordingState.isRecording) {
              return _RecordingCard(
                pick: pick,
                recordingState: recordingState,
                consentShown: state.firstTimeConsentShown,
                onStop: () => _stopRecording(pick),
              );
            }
            if (_previewPath != null) {
              return _PreviewCard(
                pick: pick,
                path: _previewPath!,
                duration: recordingState.duration,
                position: _previewPosition,
                previewDuration: _previewDuration,
                isPlaying: _previewIsPlaying,
                onPlay: _playPreview,
                onPause: _pausePreview,
                onSeek: _seekPreview,
                onSave: () => _save(pick),
                onDiscard: _discard,
              );
            }
            // Idle — show the question + mic button + Skip.
            return _IdleCard(
              pick: pick,
              consentShown: state.firstTimeConsentShown,
              onStartRecording: () => _startRecording(pick),
              onSkip: () => _skip(),
            );
        }
      },
    );
  }

  // ── Recording flow ──────────────────────────────────────────────────

  Future<void> _startRecording(TodaysQuestionPick pick) async {
    HapticService.tap();
    // First-time consent notice per elder.
    if (!ref
        .read(todaysQuestionProvider(widget.familyId))
        .valueOrNull!
        .firstTimeConsentShown) {
      final confirmed = await _showFirstTimeConsent(pick);
      if (!confirmed || !mounted) return;
      await recordTodaysQuestionConsentShown(
        widget.familyId,
        pick.elderPersonId,
      );
      ref.invalidate(todaysQuestionProvider(widget.familyId));
    }
    await ref.read(oralHistoryProvider.notifier).startRecording();
  }

  Future<void> _stopRecording(TodaysQuestionPick pick) async {
    HapticService.selection();
    final notifier = ref.read(oralHistoryProvider.notifier);
    final recordedDuration = await notifier.stopRecording();
    // After stop, the file lives at the notifier's internal
    // `_recordingPath`. We can't access it directly (it's private),
    // so we read the recording state's `duration` — but for preview
    // we need the actual path. The save method (saveFromTodaysQuestion)
    // reuses the notifier's internal path, so preview playback is
    // best-effort: if the path isn't available, the preview shows
    // the duration + Save/Discard without a Play button.
    //
    // For Phase B we read the path via the notifier's `currentRecordingPath`
    // accessor (added in the same edit). If null, fall back to no
    // preview playback.
    _previewPath = notifier.currentRecordingPath;
    _previewDuration = recordedDuration;
    if (mounted) setState(() {});
  }

  Future<void> _save(TodaysQuestionPick pick) async {
    HapticService.tap();
    final notifier = ref.read(oralHistoryProvider.notifier);
    notifier.setRecordingSaving(true);
    try {
      final language =
          ref.read(kinshipTermLanguageProvider); // implicit via the import
      final savedStory = await notifier.saveFromTodaysQuestion(
        familyId: widget.familyId,
        elderPersonId: pick.elderPersonId,
        elderName: pick.elderFirstName,
        elderKinshipTerm: pick.elderKinshipTerm,
        questionId: pick.promptId,
        questionText: pick.promptText,
        recordedDuration: _previewDuration,
        language: language,
      );
      if (savedStory == null) {
        // Save failed — the error is in recordingState.error,
        // surfaced by the _ErrorCard sub-state. The local file is
        // preserved (the notifier does NOT delete on save failure)
        // so the user can retry.
        if (mounted) setState(() {}); // re-render to show the error
        return;
      }
      // Save succeeded — mark this cycle as answered + tear down
      // preview state.
      _disposePreviewPlayer();
      _previewPath = null;
      await markTodaysQuestionAnswered(
        ref,
        widget.familyId,
        pick.elderPersonId,
      );
      // Fire the record_saved analytics event.
      // (Phase B doesn't add a new tracker call; the existing
      // analytics_service is invoked by the OralHistory screen. The
      // Home card relies on the same notifier, so the event will be
      // recorded by the notifier if it instruments saves. TODO:
      // instrument saveFromTodaysQuestion with record_saved event.)
    } catch (e) {
      debugPrint('⚠️ TodaysQuestion save failed: $e');
    }
  }

  Future<void> _discard() async {
    HapticService.selection();
    await ref.read(oralHistoryProvider.notifier).cancelRecording();
    _disposePreviewPlayer();
    _previewPath = null;
    if (mounted) setState(() {});
  }

  Future<void> _skip() async {
    HapticService.selection();
    await markTodaysQuestionSkipped(ref, widget.familyId);
  }

  // ── Preview playback (just_audio) ────────────────────────────────────

  Future<void> _playPreview() async {
    final path = _previewPath;
    if (path == null) return;
    if (_previewPlayer == null) {
      _previewPlayer = AudioPlayer();
      _previewPlayer!
        ..positionStream.listen((p) {
          if (mounted) setState(() => _previewPosition = p);
        })
        ..durationStream.listen((d) {
          if (mounted && d != null) setState(() => _previewDuration = d);
        })
        ..playerStateStream.listen((s) {
          if (!mounted) return;
          setState(() => _previewIsPlaying = s.playing);
          if (s.processingState == ProcessingState.completed) {
            _previewPlayer?.seek(Duration.zero);
            _previewPlayer?.pause();
          }
        });
    }
    try {
      await _previewPlayer!.setFilePath(path);
      await _previewPlayer!.play();
    } catch (e) {
      debugPrint('⚠️ TodaysQuestion preview playback failed: $e');
    }
  }

  Future<void> _pausePreview() async {
    await _previewPlayer?.pause();
  }

  Future<void> _seekPreview(Duration pos) async {
    await _previewPlayer?.seek(pos);
  }

  // ── First-time consent notice ────────────────────────────────────────

  Future<bool> _showFirstTimeConsent(TodaysQuestionPick pick) async {
    final genderedSuffix = (pick.elderGender?.toLowerCase() == 'female')
        ? 'her voice'
        : (pick.elderGender?.toLowerCase() == 'male')
            ? 'his voice'
            : 'their voice';
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _cCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KinrelRadius.dialog),
          side: BorderSide(color: _cOrange.withValues(alpha: 0.15)),
        ),
        title: Text(
          'Before you record',
          style: KinrelTypography.headlineSmall.copyWith(color: _cTextPrimary),
        ),
        content: Text(
          'Recording ${pick.elderKinshipTerm}\'s voice. Make sure $genderedSuffix recording is okay with them.',
          style: const TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 14,
            color: _cTextSecondary,
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel',
                style: TextStyle(color: _cTextSecondary)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: _cOrange),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _openAppSettings() async {
    try {
      await openAppSettings();
    } catch (e) {
      debugPrint('⚠️ TodaysQuestion: could not open settings: $e');
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Sub-state widgets
// ═══════════════════════════════════════════════════════════════════════

class _IdleCard extends StatelessWidget {
  const _IdleCard({
    required this.pick,
    required this.consentShown,
    required this.onStartRecording,
    required this.onSkip,
  });

  final TodaysQuestionPick pick;
  final bool consentShown;
  final VoidCallback onStartRecording;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final genderedSubtext =
        (pick.elderGender?.toLowerCase() == 'female')
            ? 'Record her voice. It stays in the family forever.'
            : (pick.elderGender?.toLowerCase() == 'male')
                ? 'Record his voice. It stays in the family forever.'
                : 'Record their voice. It stays in the family forever.';

    return _CardShell(
      child: Padding(
        padding: const EdgeInsets.all(KinrelSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Small label.
            const Text(
              'TODAY\'S QUESTION',
              style: TextStyle(
                fontFamily: KinrelTypography.monoFont,
                fontSize: 10,
                fontWeight: FontWeight.w500,
                letterSpacing: 1.8,
                color: _cOrange,
              ),
            ),
            const SizedBox(height: 6),
            // Question title — "Ask {term}: {question}"
            Text(
              'Ask ${pick.elderKinshipTerm}: ${pick.promptText}',
              style: const TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: _cTextPrimary,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              genderedSubtext,
              style: const TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 12,
                color: _cTextSecondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                // Mic button — tap to start. 56dp tap target.
                semanticButton(
                  label: 'Start recording ${pick.elderKinshipTerm}\'s answer',
                  hint: 'Double tap to start recording',
                  child: GestureDetector(
                    onTap: onStartRecording,
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: KinrelGradients.igniteGradient,
                      ),
                      child: const Icon(
                        Icons.mic_rounded,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                // Skip — secondary text button.
                TextButton(
                  onPressed: onSkip,
                  child: const Text(
                    'Skip',
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 14,
                      color: _cTextSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RecordingCard extends StatelessWidget {
  const _RecordingCard({
    required this.pick,
    required this.recordingState,
    required this.consentShown,
    required this.onStop,
  });

  final TodaysQuestionPick pick;
  final RecordingState recordingState;
  final bool consentShown;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    // Auto-stop at max duration.
    if (recordingState.duration >= _kMaxRecordingDuration) {
      // Fire-and-forget — the parent's _stopRecording handles the rest.
      Future.microtask(onStop);
    }
    return _CardShell(
      borderColor: _cOrange.withValues(alpha: 0.35),
      child: Padding(
        padding: const EdgeInsets.all(KinrelSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Live "REC" indicator — pulsing red dot.
                _PulsingDot(color: _cError, size: 8),
                const SizedBox(width: 8),
                Text(
                  'Recording ${pick.elderKinshipTerm}…',
                  style: const TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _cTextPrimary,
                  ),
                ),
                const Spacer(),
                // Timer.
                Text(
                  recordingState.durationLabel,
                  style: const TextStyle(
                    fontFamily: KinrelTypography.monoFont,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _cOrange,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Live waveform.
            RecordingWaveform(
              amplitudes: recordingState.amplitudes,
              active: true,
              height: 56,
            ),
            const SizedBox(height: 14),
            // Tap-to-stop button (NOT press-and-hold).
            Center(
              child: semanticButton(
                label: 'Stop recording',
                hint: 'Double tap to stop and preview',
                child: GestureDetector(
                  onTap: onStop,
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _cElevated,
                      border: Border.all(
                        color: _cOrange.withValues(alpha: 0.5),
                        width: 2,
                      ),
                    ),
                    child: const Icon(
                      Icons.stop_rounded,
                      color: _cOrange,
                      size: 28,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({
    required this.pick,
    required this.path,
    required this.duration,
    required this.position,
    required this.previewDuration,
    required this.isPlaying,
    required this.onPlay,
    required this.onPause,
    required this.onSeek,
    required this.onSave,
    required this.onDiscard,
  });

  final TodaysQuestionPick pick;
  final String path;
  final Duration duration;
  final Duration position;
  final Duration previewDuration;
  final bool isPlaying;
  final VoidCallback onPlay;
  final VoidCallback onPause;
  final void Function(Duration) onSeek;
  final VoidCallback onSave;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final totalMs = (previewDuration.inMilliseconds > 0
            ? previewDuration
            : duration)
        .inMilliseconds;
    final posMs = position.inMilliseconds.clamp(0, totalMs).toInt();
    final progress = totalMs > 0 ? (posMs / totalMs).clamp(0.0, 1.0) : 0.0;
    final canPlay = File(path).existsSync();

    return _CardShell(
      child: Padding(
        padding: const EdgeInsets.all(KinrelSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Preview ${pick.elderKinshipTerm}\'s answer',
              style: const TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: _cTextPrimary,
              ),
            ),
            const SizedBox(height: 12),
            // Playback row: play/pause + seek bar + duration label.
            Row(
              children: [
                GestureDetector(
                  onTap: isPlaying ? onPause : onPlay,
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: KinrelGradients.igniteGradient,
                    ),
                    child: Icon(
                      isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: canPlay
                      ? SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 3,
                            thumbColor: _cOrange,
                            activeTrackColor: _cOrange,
                            inactiveTrackColor: _cElevated,
                            overlayColor: _cOrange.withValues(alpha: 0.15),
                          ),
                          child: Slider(
                            value: progress,
                            min: 0,
                            max: 1,
                            onChanged: (v) => onSeek(
                              Duration(
                                  milliseconds:
                                      (v * totalMs).toInt()),
                            ),
                          ),
                        )
                      : Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Text(
                            'Recording saved locally — Save to upload.',
                            style: TextStyle(
                              fontFamily: KinrelTypography.bodyFont,
                              fontSize: 12,
                              color: _cTextDim,
                            ),
                          ),
                        ),
                ),
                const SizedBox(width: 8),
                Text(
                  _formatDuration(previewDuration.inSeconds > 0
                      ? previewDuration
                      : duration),
                  style: const TextStyle(
                    fontFamily: KinrelTypography.monoFont,
                    fontSize: 11,
                    color: _cTextSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            // Save / Discard actions.
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onSave,
                    icon: const Icon(Icons.cloud_upload_rounded, size: 18),
                    label: const Text('Save'),
                    style: FilledButton.styleFrom(
                      backgroundColor: _cOrange,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(44),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onDiscard,
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    label: const Text('Discard'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _cTextSecondary,
                      side: BorderSide(
                        color: _cTextDim.withValues(alpha: 0.4),
                      ),
                      minimumSize: const Size.fromHeight(44),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SavingCard extends StatelessWidget {
  const _SavingCard({required this.pick});
  final TodaysQuestionPick pick;

  @override
  Widget build(BuildContext context) {
    return _CardShell(
      child: Padding(
        padding: const EdgeInsets.all(KinrelSpacing.lg),
        child: Row(
          children: [
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: _cOrange,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                'Saving ${pick.elderKinshipTerm}\'s answer…',
                style: const TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: _cTextPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({
    required this.pick,
    required this.message,
    required this.permissionDenied,
    required this.onRetry,
    required this.onOpenSettings,
  });

  final TodaysQuestionPick pick;
  final String message;
  final bool permissionDenied;
  final VoidCallback onRetry;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return _CardShell(
      borderColor: _cError.withValues(alpha: 0.35),
      child: Padding(
        padding: const EdgeInsets.all(KinrelSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.error_outline_rounded,
                    color: _cError, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    message,
                    style: const TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 13,
                      color: _cTextPrimary,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (permissionDenied)
              FilledButton.icon(
                onPressed: onOpenSettings,
                icon: const Icon(Icons.settings_rounded, size: 18),
                label: const Text('Open Settings'),
                style: FilledButton.styleFrom(
                  backgroundColor: _cOrange,
                  minimumSize: const Size.fromHeight(44),
                ),
              )
            else
              OutlinedButton(
                onPressed: onRetry,
                style: OutlinedButton.styleFrom(
                  foregroundColor: _cOrange,
                  side: BorderSide(color: _cOrange.withValues(alpha: 0.4)),
                  minimumSize: const Size.fromHeight(44),
                ),
                child: const Text('Retry'),
              ),
          ],
        ),
      ),
    );
  }
}

class _NoElderCard extends StatelessWidget {
  const _NoElderCard({required this.familyId});
  final String familyId;

  @override
  Widget build(BuildContext context) {
    // Spec: "If no suitable elder exists, show 'Add your first memory'
    // instead of faking a question." We route to the Memory Vault
    // create screen, which already exists for adding memories by
    // photo + caption. This avoids faking a question for a lone user.
    return _CardShell(
      child: Padding(
        padding: const EdgeInsets.all(KinrelSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'TODAY\'S QUESTION',
              style: TextStyle(
                fontFamily: KinrelTypography.monoFont,
                fontSize: 10,
                fontWeight: FontWeight.w500,
                letterSpacing: 1.8,
                color: _cOrange,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Add your first memory',
              style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: _cTextPrimary,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Add a relative to your family graph and we\'ll surface a question to ask them every week.',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 12,
                color: _cTextSecondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () {
                      HapticService.tap();
                      context.push('/family/$familyId');
                    },
                    icon: const Icon(Icons.family_restroom_rounded,
                        size: 18),
                    label: const Text('Add a relative'),
                    style: FilledButton.styleFrom(
                      backgroundColor: _cOrange,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(44),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      HapticService.tap();
                      context.push('/memory-vault');
                    },
                    icon:
                        const Icon(Icons.photo_library_outlined, size: 18),
                    label: const Text('Add memory'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _cTextSecondary,
                      side: BorderSide(
                        color: _cTextDim.withValues(alpha: 0.4),
                      ),
                      minimumSize: const Size.fromHeight(44),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CardSkeleton extends StatelessWidget {
  const _CardSkeleton();

  @override
  Widget build(BuildContext context) {
    return _CardShell(
      child: Padding(
        padding: const EdgeInsets.all(KinrelSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 100,
              height: 10,
              color: _cElevated,
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              height: 18,
              color: _cElevated,
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: const BoxDecoration(
                    color: _cElevated,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CardError extends StatelessWidget {
  const _CardError({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return _CardShell(
      borderColor: _cError.withValues(alpha: 0.35),
      child: Padding(
        padding: const EdgeInsets.all(KinrelSpacing.lg),
        child: Row(
          children: [
            const Icon(Icons.error_outline_rounded,
                color: _cError, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 13,
                  color: _cTextPrimary,
                ),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Card shell — consistent border + radius + bg for all sub-states.
// ═══════════════════════════════════════════════════════════════════════

class _CardShell extends StatelessWidget {
  const _CardShell({
    required this.child,
    this.borderColor,
  });

  final Widget child;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: KinrelSpacing.base,
        vertical: 6,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: _cCard,
          borderRadius: BorderRadius.circular(KinrelRadius.xl),
          border: Border.all(
            color: borderColor ?? Colors.white.withValues(alpha: 0.06),
            width: 1,
          ),
        ),
        child: child,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Helpers
// ═══════════════════════════════════════════════════════════════════════

String _formatDuration(Duration d) {
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$m:$s';
}

/// A small pulsing dot — used as the "REC" indicator.
class _PulsingDot extends StatefulWidget {
  const _PulsingDot({required this.color, required this.size});
  final Color color;
  final double size;

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, __) {
        return Container(
          width: widget.size + (_controller.value * 4),
          height: widget.size + (_controller.value * 4),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.color.withValues(alpha: 0.6 + _controller.value * 0.4),
          ),
        );
      },
    );
  }
}
