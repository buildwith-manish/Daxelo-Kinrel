// lib/features/pulse/presentation/blessing_chain_screen.dart
//
// A-1 Blessing Chain screen — shows blessings delivered to the user + family blessings.
// P1.1: Real audio playback via just_audio; elder-side recording via blessing_record_sheet.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:just_audio/just_audio.dart';

import '../../../core/constants/brand_colors.dart';
import '../data/pulse_models.dart';
import '../providers/pulse_providers.dart';
import 'blessing_record_sheet.dart';

class BlessingChainScreen extends ConsumerStatefulWidget {
  final bool embedded;
  const BlessingChainScreen({super.key, this.embedded = false});

  @override
  ConsumerState<BlessingChainScreen> createState() => _BlessingChainScreenState();
}

class _BlessingChainScreenState extends ConsumerState<BlessingChainScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KinrelColors.darkBackground,
      appBar: AppBar(
        backgroundColor: KinrelColors.darkBackground,
        elevation: 0,
        title: const Text('Blessing Chain', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => context.pop(),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: KinrelColors.gold,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white.withOpacity(0.4),
          tabs: const [
            Tab(text: 'For Me'),
            Tab(text: 'Family'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          _BlessingsForMeTab(),
          _FamilyBlessingsTab(),
        ],
      ),
      // P1.1: Elder-side recording entry point. Opens the blessing record
      // sheet where an elder (or family member on their behalf) can record
      // a voice blessing, pick a recipient, and schedule delivery.
      floatingActionButton: FloatingActionButton(
        onPressed: () => BlessingRecordSheet.show(context),
        backgroundColor: KinrelColors.gold,
        child: const Icon(Icons.mic, color: Colors.white),
      ),
    );
  }
}

class _BlessingsForMeTab extends ConsumerWidget {
  const _BlessingsForMeTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final blessingsAsync = ref.watch(blessingsForMeProvider);
    return blessingsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator(color: KinrelColors.gold)),
      error: (err, _) => Center(child: Text('Error: $err', style: const TextStyle(color: Colors.white54))),
      data: (blessings) {
        if (blessings.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('🎁', style: TextStyle(fontSize: 48)),
                  const SizedBox(height: 16),
                  const Text('No blessings yet', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Text(
                    'When an elder records a blessing for your birthday\nor a festival, it will appear here.',
                    style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: blessings.length,
          itemBuilder: (context, i) => _BlessingCard(blessing: blessings[i], isForMe: true),
        );
      },
    );
  }
}

class _FamilyBlessingsTab extends ConsumerWidget {
  const _FamilyBlessingsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // We need a familyId — use the current family
    final familyId = ref.watch(currentFamilyIdProvider);
    if (familyId == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'Select a family to view blessings.',
            style: TextStyle(color: Colors.white.withOpacity(0.5)),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final blessingsAsync = ref.watch(familyBlessingsProvider(familyId));
    return blessingsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator(color: KinrelColors.gold)),
      error: (err, _) => Center(child: Text('Error: $err', style: const TextStyle(color: Colors.white54))),
      data: (blessings) {
        if (blessings.isEmpty) {
          return Center(
            child: Text('No family blessings yet', style: TextStyle(color: Colors.white.withOpacity(0.5))),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: blessings.length,
          itemBuilder: (context, i) => _BlessingCard(blessing: blessings[i]),
        );
      },
    );
  }
}

class _BlessingCard extends ConsumerWidget {
  final BlessingChain blessing;
  final bool isForMe;

  const _BlessingCard({required this.blessing, this.isForMe = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isUnviewed = blessing.status == 'delivered';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isUnviewed
              ? KinrelColors.gold.withOpacity(0.4)
              : Colors.white.withOpacity(0.08),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Elder avatar (emoji placeholder if no photo)
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: KinrelColors.gold.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: blessing.elderPerson?.photoThumb != null
                    ? ClipOval(child: Image.network(blessing.elderPerson!.photoThumb!))
                    : const Center(child: Text('👵', style: TextStyle(fontSize: 20))),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      blessing.elderPerson?.name ?? 'A family elder',
                      style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      blessing.isRecurring ? '🔄 Recurring · ${blessing.triggerType}' : blessing.triggerType,
                      style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 11),
                    ),
                  ],
                ),
              ),
              if (isUnviewed)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: KinrelColors.gold,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text('NEW', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
                ),
            ],
          ),
          const SizedBox(height: 12),
          // Blessing content
          if (blessing.isAudio) ...[
            _AudioBlessingPlayer(blessing: blessing),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: KinrelColors.gold.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                blessing.textContent ?? '',
                style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.5, fontStyle: FontStyle.italic),
              ),
            ),
          ],
          const SizedBox(height: 12),
          // Trigger info
          Row(
            children: [
              Icon(Icons.event, color: KinrelColors.gold.withOpacity(0.6), size: 14),
              const SizedBox(width: 4),
              Text(
                'Delivered on ${blessing.triggerDate} (${blessing.triggerType})',
                style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11),
              ),
              const Spacer(),
              if (isForMe && isUnviewed)
                TextButton(
                  onPressed: () async {
                    await ref.read(pulseApiClientProvider).markBlessingViewed(blessing.id);
                    ref.invalidate(blessingsForMeProvider);
                  },
                  child: const Text('Mark viewed', style: TextStyle(color: KinrelColors.gold, fontSize: 12)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AudioBlessingPlayer extends StatefulWidget {
  final BlessingChain blessing;
  const _AudioBlessingPlayer({required this.blessing});

  @override
  State<_AudioBlessingPlayer> createState() => _AudioBlessingPlayerState();
}

class _AudioBlessingPlayerState extends State<_AudioBlessingPlayer> {
  // P1.1: Real audio playback via just_audio (replaces fake _isPlaying toggle).
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _initAudio();
  }

  Future<void> _initAudio() async {
    final url = widget.blessing.mediaUrl;
    if (url == null || url.isEmpty) {
      setState(() => _loadError = 'No audio available for this blessing.');
      return;
    }
    try {
      await _audioPlayer.setUrl(url);
      // Listen to playback state changes.
      _audioPlayer.playerStateStream.listen((state) {
        if (mounted) {
          setState(() {
            _isPlaying = state.playing;
            if (state.processingState == ProcessingState.completed) {
              _isPlaying = false;
              _audioPlayer.seek(Duration.zero);
            }
          });
        }
      });
      // Listen to position updates for the progress bar.
      _audioPlayer.positionStream.listen((pos) {
        if (mounted) setState(() => _position = pos);
      });
      _audioPlayer.durationStream.listen((dur) {
        if (mounted && dur != null) setState(() => _duration = dur);
      });
    } catch (e) {
      if (mounted) {
        setState(() => _loadError =
            'This blessing could not be played. Tap to retry.');
      }
    }
  }

  Future<void> _togglePlayPause() async {
    if (_loadError != null) {
      // Retry loading on tap after an error.
      setState(() => _loadError = null);
      await _initAudio();
      return;
    }
    if (_isPlaying) {
      await _audioPlayer.pause();
    } else {
      await _audioPlayer.play();
    }
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: KinrelColors.gold.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Semantics(
        label:
            'Blessing from ${widget.blessing.elderPerson?.name ?? 'a family elder'}, '
            '${_duration.inSeconds} seconds long. '
            '${_isPlaying ? 'Playing' : 'Paused'}. Double-tap to play or pause.',
        liveRegion: true,
        child: Row(
          children: [
            // Play/pause button — 44x44 min hit target for accessibility.
            GestureDetector(
              onTap: _togglePlayPause,
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: KinrelColors.gold,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _loadError != null
                      ? Icons.refresh
                      : (_isPlaying ? Icons.pause : Icons.play_arrow),
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _loadError ?? 'Voice blessing',
                    style: TextStyle(
                      color: _loadError != null
                          ? Colors.red.shade300
                          : Colors.white.withOpacity(0.7),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (_loadError == null) ...[
                    // Real progress bar reflecting playback position.
                    LinearProgressIndicator(
                      value: _duration.inSeconds > 0
                          ? _position.inSeconds / _duration.inSeconds
                          : 0.0,
                      backgroundColor:
                          KinrelColors.gold.withOpacity(0.2),
                      valueColor:
                          AlwaysStoppedAnimation<Color>(KinrelColors.gold),
                      minHeight: 3,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _formatDuration(_position),
                          style: TextStyle(
                              color: Colors.white.withOpacity(0.5),
                              fontSize: 10),
                        ),
                        Text(
                          _formatDuration(_duration),
                          style: TextStyle(
                              color: Colors.white.withOpacity(0.5),
                              fontSize: 10),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
