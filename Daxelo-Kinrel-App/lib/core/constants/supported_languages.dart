/// Supported languages for Indian kinship terms
enum SupportedLanguage {
  hindi('hi', 'Hindi', 'हिन्दी', 'Devanagari', false),
  bengali('bn', 'Bengali', 'বাংলা', 'Bengali', false),
  telugu('te', 'Telugu', 'తెలుగు', 'Telugu', false),
  marathi('mr', 'Marathi', 'मराठी', 'Devanagari', false),
  tamil('ta', 'Tamil', 'தமிழ்', 'Tamil', false),
  gujarati('gu', 'Gujarati', 'ગુજરાતી', 'Gujarati', false),
  kannada('kn', 'Kannada', 'ಕನ್ನಡ', 'Kannada', false),
  malayalam('ml', 'Malayalam', 'മലയാളം', 'Malayalam', false),
  punjabi('pa', 'Punjabi', 'ਪੰਜਾਬੀ', 'Gurmukhi', false),
  odia('or', 'Odia', 'ଓଡ଼ିଆ', 'Odia', false),
  assamese('as', 'Assamese', 'অসমীয়া', 'Bengali', false),
  urdu('ur', 'Urdu', 'اردو', 'Arabic', true),
  sanskrit('sa', 'Sanskrit', 'संस्कृतम्', 'Devanagari', false),
  english('en', 'English', 'English', 'Latin', false);

  SupportedLanguage(
    this.code,
    this.name,
    this.nativeName,
    this.script,
    this.isRTL,
  );

  final String code;
  final String name;
  final String nativeName;
  final String script;
  final bool isRTL;

  /// Font family for this language's script
  String get fontFamily {
    switch (script) {
      case 'Devanagari':
        return 'NotoSansDevanagari';
      case 'Bengali':
        return 'NotoSansBengali';
      case 'Tamil':
        return 'NotoSansTamil';
      case 'Telugu':
        return 'NotoSansTelugu';
      case 'Gujarati':
        return 'NotoSansGujarati';
      case 'Kannada':
        return 'NotoSansKannada';
      case 'Malayalam':
        return 'NotoSansMalayalam';
      case 'Gurmukhi':
        return 'NotoSansGurmukhi';
      case 'Odia':
        return 'NotoSansOriya';
      case 'Arabic':
        return 'NotoSansArabic';
      case 'Latin':
      default:
        return 'DMSans';
    }
  }

  static SupportedLanguage fromCode(String code) {
    return SupportedLanguage.values.firstWhere(
      (lang) => lang.code == code,
      orElse: () => SupportedLanguage.english,
    );
  }

  static SupportedLanguage fromName(String name) {
    final lower = name.toLowerCase();
    return SupportedLanguage.values.firstWhere(
      (lang) => lang.name.toLowerCase() == lower,
      orElse: () => SupportedLanguage.english,
    );
  }
}
