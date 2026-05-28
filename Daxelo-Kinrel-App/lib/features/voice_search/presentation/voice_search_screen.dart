import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/constants/supported_languages.dart';
import '../providers/voice_search_provider.dart';

class VoiceSearchScreen extends ConsumerStatefulWidget {
  VoiceSearchScreen({super.key});

  @override
  ConsumerState<VoiceSearchScreen> createState() => _VoiceSearchScreenState();
}

class _VoiceSearchScreenState extends ConsumerState<VoiceSearchScreen>
    with TickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final AnimationController _waveformController;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _waveformController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _waveformController.dispose();
    super.dispose();
  }

  void _toggleRecording() {
    final state = ref.read(voiceSearchProvider);
    if (state.isLoading) return;

    if (state.isRecording) {
      // Stop recording and process
      ref.read(voiceSearchProvider.notifier).setRecording(false);
      // Simulate sending audio for transcription
      // In production, this would use actual recorded audio base64
      _simulateVoiceSearch();
    } else {
      // Start recording
      ref.read(voiceSearchProvider.notifier).setRecording(true);
      // Clear previous results
      ref.read(voiceSearchProvider.notifier).clearResults();
    }
  }

  void _simulateVoiceSearch() async {
    // Simulated base64 audio — in production, this comes from the microphone
    // Using a placeholder base64 string to demonstrate the flow
    const simulatedBase64Audio =
        'UklGRiQAAABXQVZFZm10IBAAAAABAAEARKwAAIhYAQACABAAZGF0YQAAAAA=';
    await ref
        .read(voiceSearchProvider.notifier)
        .transcribeAndSearch(simulatedBase64Audio);
  }

  @override
  Widget build(BuildContext context) {
    final voiceState = ref.watch(voiceSearchProvider);

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(color: KinrelColors.darkBackground),
        child: SafeArea(
          child: Column(
            children: [
              // ── Header ────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.all(KinrelSpacing.base),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(
                        Icons.arrow_back,
                        color: KinrelColors.textWhite,
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Voice Search',
                      style: TextStyle(
                        fontFamily: KinrelTypography.displayFont,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: KinrelColors.textWhite,
                      ),
                    ),
                    Spacer(),
                    // Language selector
                    _LanguageSelector(
                      selectedLanguage: voiceState.selectedLanguage,
                      onLanguageChanged: (lang) {
                        ref
                            .read(voiceSearchProvider.notifier)
                            .setLanguage(lang);
                      },
                    ),
                  ],
                ),
              ),

              // ── Main Content ──────────────────────────────────────
              Expanded(
                child: voiceState.isLoading
                    ? _LoadingView()
                    : voiceState.isRecording
                    ? _RecordingView(
                        waveformController: _waveformController,
                        onStop: _toggleRecording,
                      )
                    : voiceState.transcription != null
                    ? _ResultsView(
                        transcription: voiceState.transcription!,
                        results: voiceState.results ?? [],
                        onSearchAgain: () {
                          ref.read(voiceSearchProvider.notifier).clearResults();
                        },
                      )
                    : _IdleView(
                        pulseAnimation: _pulseAnimation,
                        onStart: _toggleRecording,
                      ),
              ),

              // ── Error Banner ──────────────────────────────────────
              if (voiceState.error != null)
                Container(
                  margin: EdgeInsets.all(KinrelSpacing.base),
                  padding: EdgeInsets.all(KinrelSpacing.md),
                  decoration: BoxDecoration(
                    color: KinrelColors.error.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(KinrelSpacing.radiusMd),
                    border: Border.all(
                      color: KinrelColors.error.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.error_outline,
                        color: KinrelColors.error,
                        size: 20,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          voiceState.error!,
                          style: TextStyle(
                            fontFamily: KinrelTypography.bodyFont,
                            fontSize: 13,
                            color: KinrelColors.error,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Idle View (Microphone button) ───────────────────────────────

class _IdleView extends StatelessWidget {
  const _IdleView({required this.pulseAnimation, required this.onStart});

  final Animation<double> pulseAnimation;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Pulsing mic button
          AnimatedBuilder(
            animation: pulseAnimation,
            builder: (context, child) {
              return Transform.scale(
                scale: pulseAnimation.value,
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: KinrelGradients.igniteGradient,
                    boxShadow: [
                      BoxShadow(
                        color: KinrelColors.purpleGlow,
                        blurRadius: 40,
                        spreadRadius: 10,
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(60),
                      onTap: onStart,
                      child: Icon(
                        Icons.mic,
                        size: 48,
                        color: KinrelColors.textWhite,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),

          const SizedBox(height: 32),
          Text(
            'Tap to search by voice',
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: KinrelColors.textWhite,
            ),
          ),

          const SizedBox(height: 12),
          Text(
            'Say any Indian kinship term\nlike "chacha", "bua", "mami"',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 14,
              color: KinrelColors.textDim,
              height: 1.5,
            ),
          ),

          const SizedBox(height: 32),

          // Quick tips
          Container(
            margin: const EdgeInsets.symmetric(horizontal: KinrelSpacing.xxxl),
            padding: EdgeInsets.all(KinrelSpacing.md),
            decoration: BoxDecoration(
              color: KinrelColors.darkCard,
              borderRadius: BorderRadius.circular(KinrelSpacing.radiusMd),
              border: Border.all(
                color: KinrelColors.darkSurface.withValues(alpha: 0.3),
              ),
            ),
            child: Column(
              children: [
                _TipRow(icon: Icons.search, text: 'Search for kinship terms'),
                SizedBox(height: 8),
                _TipRow(
                  icon: Icons.translate,
                  text: 'Get translations in 14 languages',
                ),
                SizedBox(height: 8),
                _TipRow(
                  icon: Icons.record_voice_over,
                  text: 'Works with Hindi, Tamil, Bengali & more',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TipRow extends StatelessWidget {
  const _TipRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: KinrelColors.amber),
        SizedBox(width: 10),
        Text(
          text,
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 13,
            color: KinrelColors.textSilver,
          ),
        ),
      ],
    );
  }
}

// ── Recording View ──────────────────────────────────────────────

class _RecordingView extends StatelessWidget {
  const _RecordingView({
    required this.waveformController,
    required this.onStop,
  });

  final AnimationController waveformController;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Waveform animation
          SizedBox(
            height: 100,
            child: AnimatedBuilder(
              animation: waveformController,
              builder: (context, child) {
                return CustomPaint(
                  painter: _WaveformPainter(
                    animationValue: waveformController.value,
                    color: KinrelColors.purple,
                  ),
                  size: Size(MediaQuery.of(context).size.width - 64, 100),
                );
              },
            ),
          ),

          SizedBox(height: 32),

          // Recording indicator
          Container(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              color: KinrelColors.error.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: KinrelColors.error,
                    shape: BoxShape.circle,
                  ),
                ),
                SizedBox(width: 8),
                Text(
                  'Listening...',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: KinrelColors.error,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 40),

          // Stop button
          GestureDetector(
            onTap: onStop,
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: KinrelColors.error,
                boxShadow: [
                  BoxShadow(
                    color: KinrelColors.error.withValues(alpha: 0.4),
                    blurRadius: 20,
                    spreadRadius: 5,
                  ),
                ],
              ),
              child: Icon(Icons.stop, size: 36, color: KinrelColors.textWhite),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Tap to stop',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 14,
              color: KinrelColors.textDim,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Loading View ────────────────────────────────────────────────

class _LoadingView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: KinrelColors.purple, strokeWidth: 3),
          SizedBox(height: 24),
          Text(
            'Processing your voice...',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 16,
              color: KinrelColors.textSilver,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Transcribing and searching kinship terms',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 13,
              color: KinrelColors.textDim,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Results View ────────────────────────────────────────────────

class _ResultsView extends StatelessWidget {
  const _ResultsView({
    required this.transcription,
    required this.results,
    required this.onSearchAgain,
  });

  final String transcription;
  final List<KinshipVoiceResult> results;
  final VoidCallback onSearchAgain;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Transcription display
        Container(
          margin: const EdgeInsets.symmetric(
            horizontal: KinrelSpacing.base,
            vertical: KinrelSpacing.sm,
          ),
          padding: const EdgeInsets.all(KinrelSpacing.md),
          decoration: BoxDecoration(
            color: KinrelColors.darkCard,
            borderRadius: BorderRadius.circular(KinrelSpacing.radiusMd),
            border: Border.all(
              color: KinrelColors.purple.withValues(alpha: 0.2),
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: KinrelColors.purple.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.record_voice_over,
                  color: KinrelColors.purple,
                  size: 20,
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'You said:',
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 11,
                        color: KinrelColors.textDim,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      '"$transcription"',
                      style: TextStyle(
                        fontFamily: KinrelTypography.displayFont,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: KinrelColors.amber,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Search again button
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: KinrelSpacing.base,
            vertical: KinrelSpacing.sm,
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: onSearchAgain,
              icon: Icon(Icons.mic, size: 16),
              label: Text('Search again'),
              style: TextButton.styleFrom(
                foregroundColor: KinrelColors.purple,
                textStyle: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 13,
                ),
              ),
            ),
          ),
        ),

        // Results list
        Expanded(
          child: results.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.search_off,
                        size: 48,
                        color: KinrelColors.textDim.withValues(alpha: 0.4),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No kinship terms found',
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 16,
                          color: KinrelColors.textDim,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Try saying a different term',
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 13,
                          color: KinrelColors.textDim.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(
                    horizontal: KinrelSpacing.base,
                    vertical: 8,
                  ),
                  itemCount: results.length,
                  separatorBuilder: (_, __) => SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final result = results[index];
                    return _VoiceResultCard(result: result);
                  },
                ),
        ),
      ],
    );
  }
}

class _VoiceResultCard extends StatelessWidget {
  const _VoiceResultCard({required this.result});

  final KinshipVoiceResult result;

  @override
  Widget build(BuildContext context) {
    // Get the first available native translation
    String? nativeTerm;
    String? latinTerm;
    if (result.translations.isNotEmpty) {
      final firstTranslation = result.translations.values.first;
      if (firstTranslation is Map<String, dynamic>) {
        nativeTerm = firstTranslation['native'] as String?;
        latinTerm = firstTranslation['latin'] as String?;
      }
    }

    return Container(
      padding: EdgeInsets.all(KinrelSpacing.base),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(KinrelSpacing.radiusMd),
        border: Border.all(
          color: KinrelColors.darkSurface.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Category badge
          Row(
            children: [
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: KinrelColors.purple.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  result.relationshipCategory
                      .replaceAll('_', ' ')
                      .toUpperCase(),
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: KinrelColors.purple,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              Spacer(),
              Icon(Icons.chevron_right, color: KinrelColors.textDim, size: 20),
            ],
          ),

          SizedBox(height: 10),

          // English term
          Text(
            result.englishTerm,
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: KinrelColors.textWhite,
            ),
          ),

          // Native translation
          if (nativeTerm != null) ...[
            SizedBox(height: 6),
            Row(
              children: [
                Text(
                  nativeTerm,
                  style: TextStyle(
                    fontSize: 16,
                    color: KinrelColors.amber,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (latinTerm != null) ...[
                  SizedBox(width: 8),
                  Text(
                    latinTerm,
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 13,
                      color: KinrelColors.textDim,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ],
            ),
          ],

          // Tags
          const SizedBox(height: 8),
          Row(
            children: [
              _MiniTag(label: result.gender),
              const SizedBox(width: 6),
              _MiniTag(label: result.lineage),
              SizedBox(width: 6),
              _MiniTag(label: 'Gen ${result.generation}'),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniTag extends StatelessWidget {
  const _MiniTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: KinrelColors.darkSurface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: KinrelTypography.bodyFont,
          fontSize: 10,
          color: KinrelColors.textSilver,
        ),
      ),
    );
  }
}

// ── Language Selector ───────────────────────────────────────────

class _LanguageSelector extends StatelessWidget {
  const _LanguageSelector({
    required this.selectedLanguage,
    required this.onLanguageChanged,
  });

  final SupportedLanguage selectedLanguage;
  final ValueChanged<SupportedLanguage> onLanguageChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: KinrelColors.darkElevated,
        borderRadius: BorderRadius.circular(KinrelSpacing.radiusMd),
      ),
      child: PopupMenuButton<SupportedLanguage>(
        icon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              selectedLanguage.code.toUpperCase(),
              style: TextStyle(
                color: KinrelColors.purple,
                fontFamily: KinrelTypography.monoFont,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            Icon(Icons.arrow_drop_down, color: KinrelColors.purple),
          ],
        ),
        onSelected: onLanguageChanged,
        itemBuilder: (context) => SupportedLanguage.values
            .map(
              (lang) => PopupMenuItem(
                value: lang,
                child: Text('${lang.nativeName} (${lang.name})'),
              ),
            )
            .toList(),
      ),
    );
  }
}

// ── Waveform Painter ────────────────────────────────────────────

class _WaveformPainter extends CustomPainter {
  _WaveformPainter({required this.animationValue, required this.color});

  final double animationValue;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final centerY = size.height / 2;
    const barCount = 32;
    const barGap = 4.0;
    final barWidth = (size.width - (barCount - 1) * barGap) / barCount;
    final random = math.Random(42); // Fixed seed for consistency

    for (int i = 0; i < barCount; i++) {
      final x = i * (barWidth + barGap);
      // Create a wave-like pattern that animates
      final phase = (animationValue * 2 * math.pi) + (i * 0.3);
      final amplitude = 15 + random.nextDouble() * 25;
      final waveHeight = amplitude * math.sin(phase) + amplitude * 0.5;

      final height = waveHeight.abs().clamp(6.0, size.height * 0.8);
      final y = centerY - height / 2;

      // Gradient opacity based on distance from center
      final centerDist = (i - barCount / 2).abs() / (barCount / 2);
      final opacity = (1.0 - centerDist * 0.5).clamp(0.3, 1.0);

      paint.color = color.withValues(alpha: opacity);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, barWidth, height),
          const Radius.circular(2),
        ),
        paint..style = PaintingStyle.fill,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) {
    return animationValue != oldDelegate.animationValue;
  }
}
