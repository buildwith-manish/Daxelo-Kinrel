// lib/features/todays_question/domain/interview_prompts_localized.dart
//
// DAXELO KINREL — Phase B — Today's Question prompt set.
//
// Curated, locale-keyed prompts. NO AI generation. Each prompt is a
// stable identifier (e.g. 'wedding_day.story') mapping to a per-locale
// question string. Falls back to English when the chosen locale is
// missing a translation, so the card NEVER shows an empty or
// "untranslated" string.
//
// The Phase A generational_interviews/providers/interview_prompts.dart
// file remains the source of truth for the Generational Interviews
// screen; this file extends that prompt set with the locale-keyed
// structure Phase B needs and adds the "wedding day" theme the
// product brief asks for.

/// A single curated prompt.
///
/// The [id] is the stable identifier stored in `userTags` on the
/// saved AncestralMemory row (as 'question:<id>') so we can detect
/// "already answered for this elder" without a dedicated column.
class LocalizedPrompt {
  const LocalizedPrompt({
    required this.id,
    required this.theme,
    required this.translations,
  });

  /// Stable identifier, e.g. 'wedding_day.story'.
  final String id;

  /// Theme key, e.g. 'wedding_day', 'childhood', 'wisdom',
  /// 'heritage'. Used by the prompt-picker to walk themes in a
  /// stable order.
  final String theme;

  /// Locale code → question string. Must always contain 'en'.
  final Map<String, String> translations;

  /// Returns the question in [locale], falling back to English.
  String forLocale(String locale) {
    if (translations.containsKey(locale)) {
      return translations[locale]!;
    }
    // Two-letter locale fallback (e.g. 'hi-IN' → 'hi').
    if (locale.contains('-')) {
      final short = locale.split('-').first;
      if (translations.containsKey(short)) {
        return translations[short]!;
      }
    }
    return translations['en']!;
  }
}

/// The full curated prompt set, in stable order. Phase B picks the
/// first prompt the elder hasn't answered yet (see
/// `TodaysQuestionNotifier.pickPromptForElder`).
class LocalizedInterviewPrompts {
  LocalizedInterviewPrompts._();

  /// Theme order — drives the deterministic prompt walk. New themes
  /// append to the end so existing families' next-prompt selection
  /// is stable across app updates.
  static const themeOrder = <String>[
    'wedding_day',
    'childhood',
    'wisdom',
    'heritage',
  ];

  static const prompts = <LocalizedPrompt>[
    // ── Wedding day (the new theme the product brief asks for) ─────
    LocalizedPrompt(
      id: 'wedding_day.story',
      theme: 'wedding_day',
      translations: {
        'en': 'What was your wedding day like?',
        'hi': 'आपकी शादी का दिन कैसा था?',
        'ta': 'உங்கள் திருமண நாள் எப்படி இருந்தது?',
        'ur': 'آپ کی شادی کا دن کیسا تھا؟',
      },
    ),
    LocalizedPrompt(
      id: 'wedding_day.first_meeting',
      theme: 'wedding_day',
      translations: {
        'en': 'How did you and your spouse first meet?',
        'hi': 'आप और आपके जीवनसाथी पहली बार कैसे मिले थे?',
        'ta': 'நீங்களும் உங்கள் வாழ்க்கைத் துணையும் முதலில் எப்படி சந்தித்தீர்கள்?',
        'ur': 'آپ اور آپ کی زندگی ساتھی پہلی بار کیسے ملے تھے؟',
      },
    ),
    LocalizedPrompt(
      id: 'wedding_day.promise',
      theme: 'wedding_day',
      translations: {
        'en': 'What promise from your wedding still matters most today?',
        'hi': 'आपकी शादी का वह कौन सा वादा आज भी सबसे ज्यादा मायने रखता है?',
        'ta': 'உங்கள் திருமணத்தின் எந்த வாக்குறீடு இன்றும் மிக முக்கியமானதாக உள்ளது?',
        'ur': 'آپ کی شادی کا کون سا وعدہ آج بھی سب سے زیادہ اہم ہے؟',
      },
    ),

    // ── Childhood & Origins (extends the existing generational_interviews set) ──
    LocalizedPrompt(
      id: 'childhood.home',
      theme: 'childhood',
      translations: {
        'en': 'What was your childhood home like?',
        'hi': 'आपका बचपन का घर कैसा था?',
        'ta': 'உங்கள் குழந்தைப் பருவ வீடு எப்படி இருந்தது?',
        'ur': 'آپ کا بچپن کا گھر کیسا تھا؟',
      },
    ),
    LocalizedPrompt(
      id: 'childhood.first_job',
      theme: 'childhood',
      translations: {
        'en': 'What was your first job?',
        'hi': 'आपकी पहली नौकरी कौन सी थी?',
        'ta': 'உங்கள் முதல் வேலை எது?',
        'ur': 'آپ کی پہلی نوکری کون سی تھی؟',
      },
    ),
    LocalizedPrompt(
      id: 'childhood.influence',
      theme: 'childhood',
      translations: {
        'en': 'Who was your biggest influence growing up?',
        'hi': 'बड़े होते हुए आप पर सबसे ज्यादा प्रभाव किसने डाला?',
        'ta': 'வளரும் போது உங்கள் மீது மிக பெரிய தாக்கத்தை யார் ஏற்படுத்தினார்?',
        'ur': 'بڑے ہوتے ہوئے آپ پر سب سے زیادہ اثر کس نے ڈالا؟',
      },
    ),

    // ── Life & Wisdom ───────────────────────────────────────────────
    LocalizedPrompt(
      id: 'wisdom.lesson',
      theme: 'wisdom',
      translations: {
        'en': 'What is the most important lesson life has taught you?',
        'hi': 'जीवन ने आपको अब तक की सबसे बड़ी सीख क्या दी है?',
        'ta': 'வாழ்க்கை உங்களுக்கு இதுவரை கறுத்துத் தந்த மிக முக்கியமான பாடம் எது?',
        'ur': 'زندگی نے آپ کو اب تک کی سب سے بڑی سبق کیا سکھایا ہے؟',
      },
    ),
    LocalizedPrompt(
      id: 'wisdom.younger_self',
      theme: 'wisdom',
      translations: {
        'en': 'What advice would you give your younger self?',
        'hi': 'अपने छोटे स्वरूप को आप क्या सलाह देंगे?',
        'ta': 'உங்கள் இளைய தன்னை நோக்கி என்ன அறிவுரை கூறுவீர்கள்?',
        'ur': 'اپنے چھوٹے نفس کو آپ کیا مشورہ دیں گے؟',
      },
    ),
    LocalizedPrompt(
      id: 'wisdom.grateful',
      theme: 'wisdom',
      translations: {
        'en': 'What are you most grateful for?',
        'hi': 'आप सबसे ज्यादा आभारी किस बात के लिए हैं?',
        'ta': 'நீங்கள் எதற்காக மிக அதிகமாக நன்றி கூறுகிறீர்கள்?',
        'ur': 'آپ کس بات کے لیے سب سے زیادہ شکرگزار ہیں؟',
      },
    ),

    // ── Heritage & Traditions ────────────────────────────────────────
    LocalizedPrompt(
      id: 'heritage.traditions',
      theme: 'heritage',
      translations: {
        'en': 'What traditions did your family have when you were growing up?',
        'hi': 'बड़े होते हुए आपके परिवार में कौन सी परंपराएं थीं?',
        'ta': 'நீங்கள் வளரும் போது உங்கள் குடும்பத்தில் என்ன பாரம்பரியங்கள் இருந்தன?',
        'ur': 'بڑے ہوتے ہوئے آپ کے خاندان میں کون سی روایات تھیں؟',
      },
    ),
    LocalizedPrompt(
      id: 'heritage.grandparents_stories',
      theme: 'heritage',
      translations: {
        'en': 'What stories did your grandparents tell you?',
        'hi': 'आपके दादा-दादी आपको कौन सी कहानियां सुनाते थे?',
        'ta': 'உங்கள் தாத்தா-பாட்டி உங்களுக்கு என்ன கதைகளைக் கூறினார்கள்?',
        'ur': 'آپ کے دادا-دادی آپ کو کون سی کہانیاں سناتے تھے؟',
      },
    ),
    LocalizedPrompt(
      id: 'heritage.recipes',
      theme: 'heritage',
      translations: {
        'en': 'What recipes have been passed down in your family?',
        'hi': 'आपके परिवार में कौन सी रेसिपी पीढ़ियों से चली आ रही है?',
        'ta': 'உங்கள் குடும்பத்தில் தலைமுறைளாக எந்தெந்த சமையல் குறிப்புகள் கடத்தப்பட்டு வருகின்றன?',
        'ur': 'آپ کے خاندان میں کون سی ترکیبیں نسلوں سے چلی آ رہی ہیں؟',
      },
    ),
  ];

  /// All prompt ids in stable order — used by the picker to walk
  /// the set and find the first prompt the elder hasn't answered.
  static List<String> get allIds =>
      prompts.map((p) => p.id).toList(growable: false);

  /// Looks up a prompt by id. Returns null for an unknown id (the
  /// picker skips nulls).
  static LocalizedPrompt? byId(String id) {
    for (final p in prompts) {
      if (p.id == id) return p;
    }
    return null;
  }
}
