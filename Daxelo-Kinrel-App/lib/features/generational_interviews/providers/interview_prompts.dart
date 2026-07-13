// lib/features/generational_interviews/providers/interview_prompts.dart
//
// P7.4c — Generational interviews (curated prompts).
// Curated, neutral, open-ended prompts. NOT AI-generated.
// NO guilt language, NO urgency, NO comparison.

/// Curated interview prompts organized by theme.
/// These are static, human-curated prompts — not AI-generated.
class InterviewPrompts {
  InterviewPrompts._();

  /// Prompts about childhood and family origins.
  static const List<String> childhood = [
    'What was your first job?',
    'How did you meet your spouse?',
    'What was your childhood home like?',
    'Who was your biggest influence growing up?',
    'What did you want to be when you grew up?',
  ];

  /// Prompts about life lessons and wisdom.
  static const List<String> wisdom = [
    'What is the most important lesson life has taught you?',
    'What advice would you give your younger self?',
    'What are you most grateful for?',
    'What accomplishment are you most proud of?',
    'How has the world changed since you were young?',
  ];

  /// Prompts about family heritage and traditions.
  static const List<String> heritage = [
    'What traditions did your family have when you were growing up?',
    'What stories did your grandparents tell you?',
    'Where does your family come from originally?',
    'What language(s) did your grandparents speak?',
    'What recipes have been passed down in your family?',
  ];

  /// All prompts grouped by theme.
  static const Map<String, List<String>> byTheme = {
    'Childhood & Origins': childhood,
    'Life & Wisdom': wisdom,
    'Heritage & Traditions': heritage,
  };

  /// All prompts flat list.
  static List<String> get all => [...childhood, ...wisdom, ...heritage];
}
