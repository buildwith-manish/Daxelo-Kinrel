/// Maps locale codes to language names and vice versa
const Map<String, String> languageCodeToName = {
  'hi': 'hindi',
  'bn': 'bengali',
  'te': 'telugu',
  'mr': 'marathi',
  'ta': 'tamil',
  'gu': 'gujarati',
  'kn': 'kannada',
  'ml': 'malayalam',
  'pa': 'punjabi',
  'or': 'odia',
  'as': 'assamese',
  'ur': 'urdu',
  'sa': 'sanskrit',
  'sd': 'sindhi',
  'en': 'english',
  // P8.1: Global kinship languages
  'zh': 'chinese',
  'ja': 'japanese',
  'ko': 'korean',
  'ar': 'arabic',
  'es': 'spanish',
  'fr': 'french',
  'de': 'german',
};

final Map<String, String> languageNameToCode = {
  for (final entry in languageCodeToName.entries) entry.value: entry.key,
};

/// Get supported language name from locale code
String? languageNameFromCode(String code) => languageCodeToName[code];

/// Get locale code from language name
String? languageCodeFromName(String name) =>
    languageNameToCode[name.toLowerCase()];
