import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../providers/quiz_provider.dart';

class QuizScreen extends ConsumerStatefulWidget {
  QuizScreen({super.key});

  @override
  ConsumerState<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends ConsumerState<QuizScreen>
    with TickerProviderStateMixin {
  late AnimationController _staggerCtrl;
  late Animation<double> _f1, _f2, _f3, _f4, _f5;
  late Animation<Offset> _s1, _s2, _s3, _s4, _s5;

  // Quiz selection state
  String _selectedCategory = 'mixed';
  String _selectedDifficulty = 'medium';
  String _selectedLanguage = 'hi';
  int _questionCount = 5;

  final List<Map<String, String>> _categories = [
    {'value': 'mixed', 'label': 'Mixed'},
    {'value': 'paternal', 'label': 'Paternal'},
    {'value': 'maternal', 'label': 'Maternal'},
    {'value': 'sibling', 'label': 'Siblings'},
    {'value': 'spouse', 'label': 'Spouse'},
    {'value': 'in_law', 'label': 'In-Laws'},
    {'value': 'grandparent', 'label': 'Grandparents'},
    {'value': 'cousin', 'label': 'Cousins'},
    {'value': 'offspring', 'label': 'Offspring'},
    {'value': 'extended', 'label': 'Extended'},
  ];

  final List<Map<String, String>> _difficulties = [
    {'value': 'easy', 'label': 'Easy'},
    {'value': 'medium', 'label': 'Medium'},
    {'value': 'hard', 'label': 'Hard'},
  ];

  final List<Map<String, String>> _languages = [
    {'value': 'hi', 'label': 'Hindi'},
    {'value': 'bn', 'label': 'Bengali'},
    {'value': 'te', 'label': 'Telugu'},
    {'value': 'ta', 'label': 'Tamil'},
    {'value': 'mr', 'label': 'Marathi'},
    {'value': 'gu', 'label': 'Gujarati'},
    {'value': 'kn', 'label': 'Kannada'},
    {'value': 'ml', 'label': 'Malayalam'},
    {'value': 'pa', 'label': 'Punjabi'},
    {'value': 'ur', 'label': 'Urdu'},
  ];

  @override
  void initState() {
    super.initState();
    _staggerCtrl = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 900),
    );
    _f1 = _fade(0.00, 0.25);
    _s1 = _slide(0.00, 0.25);
    _f2 = _fade(0.10, 0.35);
    _s2 = _slide(0.10, 0.35);
    _f3 = _fade(0.20, 0.45);
    _s3 = _slide(0.20, 0.45);
    _f4 = _fade(0.30, 0.55);
    _s4 = _slide(0.30, 0.55);
    _f5 = _fade(0.40, 0.65);
    _s5 = _slide(0.40, 0.65);
    _staggerCtrl.forward();
  }

  Animation<double> _fade(double a, double b) =>
      Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(
          parent: _staggerCtrl,
          curve: Interval(a, b, curve: Curves.easeOutCubic),
        ),
      );

  Animation<Offset> _slide(double a, double b) =>
      Tween<Offset>(begin: Offset(0, 0.15), end: Offset.zero).animate(
        CurvedAnimation(
          parent: _staggerCtrl,
          curve: Interval(a, b, curve: Curves.easeOutCubic),
        ),
      );

  @override
  void dispose() {
    _staggerCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final quizState = ref.watch(quizStateProvider);

    return Scaffold(
      backgroundColor: KinrelColors.darkBackground,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: KinrelColors.textWhite),
          onPressed: () {
            if (quizState.state == QuizState.playing) {
              ref.read(quizStateProvider.notifier).resetQuiz();
            } else {
              context.pop();
            }
          },
        ),
        title: Text(
          _getAppBarTitle(quizState.state),
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: KinrelColors.textWhite,
          ),
        ),
      ),
      body: switch (quizState.state) {
        QuizState.idle => _buildSelectionScreen(),
        QuizState.playing => _buildQuizPlayScreen(quizState),
        QuizState.results => _buildResultsScreen(quizState),
      },
    );
  }

  String _getAppBarTitle(QuizState state) {
    switch (state) {
      case QuizState.idle:
        return 'Kinship Quiz';
      case QuizState.playing:
        return 'Question ${ref.read(quizStateProvider).currentQuestionIndex + 1}';
      case QuizState.results:
        return 'Results';
    }
  }

  // ── Selection Screen ──────────────────────────────────────────────

  Widget _buildSelectionScreen() {
    final quizState = ref.watch(quizStateProvider);

    return SafeArea(
      child: SingleChildScrollView(
        physics: BouncingScrollPhysics(),
        padding: EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: 8),
            _AnimSection(fade: _f1, slide: _s1, child: _buildHeaderBanner()),
            SizedBox(height: 24),
            _AnimSection(
              fade: _f2,
              slide: _s2,
              child: _buildSectionTitle('Category'),
            ),
            SizedBox(height: 8),
            _AnimSection(
              fade: _f2,
              slide: _s2,
              child: _buildChipRow(
                items: _categories,
                selected: _selectedCategory,
                onSelect: (v) => setState(() => _selectedCategory = v),
              ),
            ),
            SizedBox(height: 20),
            _AnimSection(
              fade: _f3,
              slide: _s3,
              child: _buildSectionTitle('Difficulty'),
            ),
            SizedBox(height: 8),
            _AnimSection(
              fade: _f3,
              slide: _s3,
              child: _buildChipRow(
                items: _difficulties,
                selected: _selectedDifficulty,
                onSelect: (v) => setState(() => _selectedDifficulty = v),
                colorMap: {
                  'easy': KinrelColors.success,
                  'medium': KinrelColors.amber,
                  'hard': KinrelColors.error,
                },
              ),
            ),
            SizedBox(height: 20),
            _AnimSection(
              fade: _f4,
              slide: _s4,
              child: _buildSectionTitle('Language'),
            ),
            SizedBox(height: 8),
            _AnimSection(
              fade: _f4,
              slide: _s4,
              child: _buildChipRow(
                items: _languages,
                selected: _selectedLanguage,
                onSelect: (v) => setState(() => _selectedLanguage = v),
              ),
            ),
            SizedBox(height: 20),
            _AnimSection(
              fade: _f4,
              slide: _s4,
              child: _buildSectionTitle('Questions: $_questionCount'),
            ),
            SizedBox(height: 8),
            _AnimSection(
              fade: _f4,
              slide: _s4,
              child: Slider(
                value: _questionCount.toDouble(),
                min: 3,
                max: 15,
                divisions: 12,
                activeColor: KinrelColors.purple,
                inactiveColor: KinrelColors.darkSurface,
                onChanged: (v) => setState(() => _questionCount = v.round()),
              ),
            ),
            SizedBox(height: 32),
            _AnimSection(
              fade: _f5,
              slide: _s5,
              child: _buildStartButton(quizState.isGenerating),
            ),
            SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderBanner() {
    return Container(
      height: 120,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [Color(0xFF1E1508), KinrelColors.darkCard],
        ),
        border: Border.all(color: KinrelColors.purple.withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(
            color: KinrelColors.purple.withValues(alpha: 0.12),
            blurRadius: 32,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -20,
            top: -20,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    KinrelColors.purple.withValues(alpha: 0.18),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        color: KinrelColors.purple.withValues(alpha: 0.15),
                        border: Border.all(
                          color: KinrelColors.purple.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.quiz_rounded,
                            color: KinrelColors.purple,
                            size: 14,
                          ),
                          SizedBox(width: 4),
                          Text(
                            'Kinship Quiz',
                            style: TextStyle(
                              fontFamily: KinrelTypography.bodyFont,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: KinrelColors.purple,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 10),
                Text(
                  'Test your knowledge\nof Indian kinship terms',
                  style: TextStyle(
                    fontFamily: KinrelTypography.displayFont,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: KinrelColors.textWhite,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: TextStyle(
        fontFamily: KinrelTypography.displayFont,
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: KinrelColors.textWhite,
      ),
    );
  }

  Widget _buildChipRow({
    required List<Map<String, String>> items,
    required String selected,
    required Function(String) onSelect,
    Map<String, Color>? colorMap,
  }) {
    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, __) => SizedBox(width: 8),
        itemBuilder: (context, index) {
          final item = items[index];
          final value = item['value']!;
          final label = item['label']!;
          final isSelected = value == selected;
          final accentColor = colorMap?[value] ?? KinrelColors.purple;

          return _PressDown(
            onTap: () => onSelect(value),
            child: AnimatedContainer(
              duration: Duration(milliseconds: 200),
              padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isSelected
                    ? accentColor.withValues(alpha: 0.18)
                    : KinrelColors.darkCard,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: isSelected
                      ? accentColor.withValues(alpha: 0.6)
                      : KinrelColors.darkSurface.withValues(alpha: 0.6),
                ),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? accentColor : KinrelColors.textDim,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildStartButton(bool isGenerating) {
    return _PressDown(
      onTap: isGenerating
          ? () {}
          : () {
              ref
                  .read(quizStateProvider.notifier)
                  .generateQuiz(
                    category: _selectedCategory == 'mixed'
                        ? null
                        : _selectedCategory,
                    language: _selectedLanguage,
                    count: _questionCount,
                    difficulty: _selectedDifficulty,
                  );
            },
      child: Container(
        width: double.infinity,
        height: 56,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: const LinearGradient(
            colors: [KinrelColors.purple, KinrelColors.amber],
          ),
          boxShadow: [
            BoxShadow(
              color: KinrelColors.purple.withValues(alpha: 0.3),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Center(
          child: isGenerating
              ? SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2.5,
                  ),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Start Quiz',
                      style: TextStyle(
                        fontFamily: KinrelTypography.displayFont,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  // ── Quiz Play Screen ──────────────────────────────────────────────

  Widget _buildQuizPlayScreen(QuizStateData quizState) {
    if (quizState.session == null) return const SizedBox.shrink();
    final questions = quizState.session!.questions;
    final currentIndex = quizState.currentQuestionIndex;
    final question = questions[currentIndex];
    final progress = (currentIndex + 1) / questions.length;

    return SafeArea(
      child: Column(
        children: [
          // Progress bar
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: KinrelSpacing.base,
              vertical: 8,
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${currentIndex + 1} of ${questions.length}',
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 13,
                        color: KinrelColors.textDim,
                      ),
                    ),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: _difficultyColor(
                          quizState.session!.difficulty,
                        ).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        quizState.session!.difficulty.toUpperCase(),
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: _difficultyColor(
                            quizState.session!.difficulty,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    backgroundColor: KinrelColors.darkSurface,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      KinrelColors.purple,
                    ),
                    minHeight: 6,
                  ),
                ),
              ],
            ),
          ),

          // Question
          Expanded(
            child: SingleChildScrollView(
              physics: BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(
                horizontal: KinrelSpacing.base,
                vertical: 16,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Question type badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: KinrelColors.amber.withValues(alpha: 0.12),
                      border: Border.all(
                        color: KinrelColors.amber.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Text(
                      _questionTypeLabel(question.type),
                      style: const TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: KinrelColors.amber,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Question text
                  Text(
                    question.question,
                    style: TextStyle(
                      fontFamily: KinrelTypography.displayFont,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: KinrelColors.textWhite,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 28),

                  // Option cards
                  ...List.generate(question.options.length, (i) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _buildOptionCard(
                        optionIndex: i,
                        text: question.options[i],
                        question: question,
                        quizState: quizState,
                      ),
                    );
                  }),

                  // Explanation (shown after answering)
                  if (quizState.selectedAnswer != null) ...[
                    const SizedBox(height: 16),
                    _buildExplanationCard(question, quizState),
                    const SizedBox(height: 16),
                    _buildNextButton(quizState),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOptionCard({
    required int optionIndex,
    required String text,
    required QuizQuestion question,
    required QuizStateData quizState,
  }) {
    final isSelected = quizState.selectedAnswer == optionIndex;
    final isCorrectOption = optionIndex == question.correctIndex;
    final hasAnswered = quizState.selectedAnswer != null;

    Color borderColor = KinrelColors.darkSurface.withValues(alpha: 0.6);
    Color bgColor = KinrelColors.darkCard;
    Color textColor = KinrelColors.textWhite;
    IconData? trailingIcon;

    if (hasAnswered) {
      if (isCorrectOption) {
        borderColor = KinrelColors.success;
        bgColor = KinrelColors.success.withValues(alpha: 0.12);
        textColor = KinrelColors.success;
        trailingIcon = Icons.check_circle_rounded;
      } else if (isSelected && !isCorrectOption) {
        borderColor = KinrelColors.error;
        bgColor = KinrelColors.error.withValues(alpha: 0.12);
        textColor = KinrelColors.error;
        trailingIcon = Icons.cancel_rounded;
      } else {
        textColor = KinrelColors.textDim;
      }
    } else if (isSelected) {
      borderColor = KinrelColors.purple;
      bgColor = KinrelColors.purple.withValues(alpha: 0.12);
    }

    return _PressDown(
      onTap: hasAnswered
          ? () {}
          : () {
              ref.read(quizStateProvider.notifier).selectAnswer(optionIndex);
            },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor),
          boxShadow: hasAnswered && isCorrectOption
              ? [
                  BoxShadow(
                    color: KinrelColors.success.withValues(alpha: 0.2),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : hasAnswered && isSelected && !isCorrectOption
              ? [
                  BoxShadow(
                    color: KinrelColors.error.withValues(alpha: 0.2),
                    blurRadius: 12,
                    offset: Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: borderColor.withValues(alpha: 0.15),
                border: Border.all(color: borderColor),
              ),
              child: Center(
                child: trailingIcon != null
                    ? Icon(trailingIcon, color: textColor, size: 16)
                    : Text(
                        String.fromCharCode(65 + optionIndex), // A, B, C, D
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: textColor,
                        ),
                      ),
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: textColor,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExplanationCard(QuizQuestion question, QuizStateData quizState) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: KinrelColors.darkElevated,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color:
              (quizState.isCorrect == true
                      ? KinrelColors.success
                      : KinrelColors.error)
                  .withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                quizState.isCorrect == true
                    ? Icons.lightbulb_rounded
                    : Icons.info_rounded,
                color: quizState.isCorrect == true
                    ? KinrelColors.success
                    : KinrelColors.error,
                size: 18,
              ),
              SizedBox(width: 8),
              Text(
                quizState.isCorrect == true ? 'Correct!' : 'Not quite',
                style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: quizState.isCorrect == true
                      ? KinrelColors.success
                      : KinrelColors.error,
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          Text(
            question.explanation,
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 13,
              color: KinrelColors.textSilver,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNextButton(QuizStateData quizState) {
    final isLast =
        quizState.session != null &&
        quizState.currentQuestionIndex ==
            quizState.session!.questions.length - 1;

    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: () {
          ref.read(quizStateProvider.notifier).nextQuestion();
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: KinrelColors.purple,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 0,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              isLast ? 'See Results' : 'Next Question',
              style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            SizedBox(width: 8),
            Icon(
              isLast ? Icons.emoji_events_rounded : Icons.arrow_forward_rounded,
              color: Colors.white,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  // ── Results Screen ────────────────────────────────────────────────

  Widget _buildResultsScreen(QuizStateData quizState) {
    final result = quizState.result;
    if (result == null) return SizedBox.shrink();

    final isGreat = result.percentage >= 80;
    final isGood = result.percentage >= 60;

    return SafeArea(
      child: SingleChildScrollView(
        physics: BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
        child: Column(
          children: [
            const SizedBox(height: 24),

            // Score circle
            Container(
              width: 160,
              height: 160,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    (isGreat
                            ? KinrelColors.success
                            : isGood
                            ? KinrelColors.amber
                            : KinrelColors.error)
                        .withValues(alpha: 0.2),
                    Colors.transparent,
                  ],
                ),
                border: Border.all(
                  color: isGreat
                      ? KinrelColors.success
                      : isGood
                      ? KinrelColors.amber
                      : KinrelColors.error,
                  width: 3,
                ),
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${result.percentage}%',
                      style: TextStyle(
                        fontFamily: KinrelTypography.displayFont,
                        fontSize: 40,
                        fontWeight: FontWeight.w800,
                        color: isGreat
                            ? KinrelColors.success
                            : isGood
                            ? KinrelColors.amber
                            : KinrelColors.error,
                      ),
                    ),
                    Text(
                      '${result.correctAnswers}/${result.totalQuestions}',
                      style: const TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 14,
                        color: KinrelColors.textDim,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Score label
            Text(
              isGreat
                  ? 'Excellent! 🎉'
                  : isGood
                  ? 'Good job! 👍'
                  : 'Keep practicing! 💪',
              style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: KinrelColors.textWhite,
              ),
            ),
            const SizedBox(height: 8),

            // Streak
            if (result.streak > 0)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  color: KinrelColors.amber.withValues(alpha: 0.12),
                  border: Border.all(
                    color: KinrelColors.amber.withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.local_fire_department_rounded,
                      color: KinrelColors.amber,
                      size: 16,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${result.streak} streak',
                      style: const TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: KinrelColors.amber,
                      ),
                    ),
                  ],
                ),
              ),
            SizedBox(height: 32),

            // Question-by-question results
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: KinrelColors.darkCard,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: KinrelColors.darkSurface.withValues(alpha: 0.6),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Question Breakdown',
                    style: TextStyle(
                      fontFamily: KinrelTypography.displayFont,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: KinrelColors.textWhite,
                    ),
                  ),
                  SizedBox(height: 12),
                  ...List.generate(result.results.length, (i) {
                    final r = result.results[i];
                    final q = quizState.session?.questions[i];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Icon(
                            r.correct
                                ? Icons.check_circle_rounded
                                : Icons.cancel_rounded,
                            color: r.correct
                                ? KinrelColors.success
                                : KinrelColors.error,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              q?.question ?? 'Question ${i + 1}',
                              style: const TextStyle(
                                fontFamily: KinrelTypography.bodyFont,
                                fontSize: 13,
                                color: KinrelColors.textSilver,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Action buttons
            Row(
              children: [
                Expanded(
                  child: _PressDown(
                    onTap: () {
                      ref.read(quizStateProvider.notifier).resetQuiz();
                    },
                    child: Container(
                      height: 52,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        color: KinrelColors.darkCard,
                        border: Border.all(
                          color: KinrelColors.purple.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.refresh_rounded,
                            color: KinrelColors.purple,
                            size: 20,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Play Again',
                            style: TextStyle(
                              fontFamily: KinrelTypography.displayFont,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: KinrelColors.purple,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _PressDown(
                    onTap: () {
                      // Share result
                    },
                    child: Container(
                      height: 52,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        gradient: LinearGradient(
                          colors: [KinrelColors.purple, KinrelColors.amber],
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.share_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Share',
                            style: TextStyle(
                              fontFamily: KinrelTypography.displayFont,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────

  Color _difficultyColor(String difficulty) {
    switch (difficulty) {
      case 'easy':
        return KinrelColors.success;
      case 'hard':
        return KinrelColors.error;
      default:
        return KinrelColors.amber;
    }
  }

  String _questionTypeLabel(String type) {
    switch (type) {
      case 'term_to_language':
        return 'TRANSLATE';
      case 'native_to_relationship':
        return 'IDENTIFY';
      case 'native_to_english':
        return 'ENGLISH TERM';
      default:
        return 'QUIZ';
    }
  }
}

// ── Animation wrapper ────────────────────────────────────────────────

class _AnimSection extends StatelessWidget {
  const _AnimSection({
    required this.fade,
    required this.slide,
    required this.child,
  });

  final Animation<double> fade;
  final Animation<Offset> slide;
  final Widget child;

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: fade,
    child: SlideTransition(position: slide, child: child),
  );
}

// ── PressDown feedback ───────────────────────────────────────────────

class _PressDown extends StatefulWidget {
  const _PressDown({required this.child, required this.onTap});

  final Widget child;
  final VoidCallback onTap;

  @override
  State<_PressDown> createState() => _PressDownState();
}

class _PressDownState extends State<_PressDown>
    with SingleTickerProviderStateMixin {
  late AnimationController _c;
  late Animation<double> _sc;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _sc = Tween<double>(
      begin: 1.0,
      end: 0.95,
    ).animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTapDown: (_) => _c.forward(),
    onTapUp: (_) {
      _c.reverse();
      widget.onTap();
    },
    onTapCancel: () => _c.reverse(),
    child: AnimatedBuilder(
      animation: _sc,
      builder: (_, child) => Transform.scale(scale: _sc.value, child: child),
      child: widget.child,
    ),
  );
}
