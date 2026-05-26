// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Hindi (`hi`).
class SHi extends S {
  SHi([String locale = 'hi']) : super(locale);

  @override
  String get appName => 'Kinrel';

  @override
  String get appTagline => 'AI के साथ अपने परिवार का मानचित्र बनाएं';

  @override
  String get homeTitle => 'होम';

  @override
  String get kinshipTitle => 'रिश्ते';

  @override
  String get graphTitle => 'ग्राफ';

  @override
  String get alertsTitle => 'अलर्ट';

  @override
  String get profileTitle => 'मैं';

  @override
  String get notificationsTitle => 'सूचनाएं';

  @override
  String get eventsTitle => 'कार्यक्रम और उत्सव';

  @override
  String get memoriesTitle => 'यादें और समयरेखा';

  @override
  String get chatTitle => 'पारिवारिक चैट';

  @override
  String get documentsTitle => 'दस्तावेज़ वॉल्ट';

  @override
  String get achievementsTitle => 'उपलब्धियां';

  @override
  String get shareTitle => 'शेयर और आमंत्रण';

  @override
  String get settingsTitle => 'सेटिंग्स';

  @override
  String get signInTitle => 'साइन इन करें';

  @override
  String get signUpTitle => 'साइन अप करें';

  @override
  String get onboardingTitle1 => 'आपका परिवार, आपकी कहानी';

  @override
  String get onboardingBody1 =>
      'Kinrel आपके परिवार के हर रिश्ते को मैप करता है — आपके दादा-दादी से लेकर आपके पोते-पोतियों तक, उस भाषा में जिसमें आपने पले-बढ़े हैं।';

  @override
  String get onboardingTitle2 => 'वे नाम जो घर जैसा लगें';

  @override
  String get onboardingBody2 =>
      'सिर्फ \'अंकल\' और \'आंटी\' नहीं — Kinrel आपके चाचा, मामा, फूफा और ताऊजी के बीच का अंतर जानता है।';

  @override
  String get onboardingTitle3 => 'पूरी तस्वीर देखें';

  @override
  String get onboardingBody3 =>
      'आपका पूरा परिवार एक सुंदर, इंटरैक्टिव ग्राफ के रूप में। ज़ूम इन करें, कनेक्शन एक्सप्लोर करें, वो रिश्ते खोजें जिनके बारे में आपको पता ही नहीं था।';

  @override
  String get onboardingTitle4 => 'कोई भी रिश्ता तुरंत खोजें';

  @override
  String get onboardingBody4 =>
      'परिवार के किन्हीं दो सदस्यों को चुनें — Kinrel का AI आपकी भाषा में सटीक रिश्ते का नाम बताएगा।';

  @override
  String get addMember => 'सदस्य जोड़ें';

  @override
  String get shareFamily => 'परिवार शेयर करें';

  @override
  String get findPath => 'रास्ता खोजें';

  @override
  String get viewFullGraph => 'पूरा ग्राफ देखें';

  @override
  String get recentActivity => 'हाल की गतिविधि';

  @override
  String get familyInsights => 'परिवार एक नज़र में';

  @override
  String get noNotifications => 'सब पक्का! कोई नई सूचना नहीं।';

  @override
  String get noEvents =>
      'अभी कोई कार्यक्रम नहीं। आपके परिवार के जन्मदिन और सालगिरह यहां स्वचालित रूप से दिखेंगे।';

  @override
  String get noMemories =>
      'अभी कोई याद नहीं। अपनी पहली पारिवारिक याद जोड़कर शुरू करें।';

  @override
  String get noDocuments =>
      'अभी कोई दस्तावेज़ नहीं। अपने परिवार के महत्वपूर्ण दस्तावेज़ सुरक्षित रूप से संग्रहित करें।';

  @override
  String get createFamily => 'परिवार बनाएं';

  @override
  String get joinFamily => 'परिवार में शामिल हों';

  @override
  String get searchHint => 'रिश्ते खोजें';

  @override
  String birthdayTomorrow(String name) {
    return '$name का जन्मदिन कल है!';
  }

  @override
  String anniversarySoon(String name, String name2, int days) {
    return '$name और $name2 की सालगिरह $days दिन में है!';
  }

  @override
  String get sendWishes => 'शुभकामनाएं भेजें?';

  @override
  String streakDays(int count) {
    return '$count दिन का सिलसिला';
  }

  @override
  String profileCompletion(int percent) {
    return '$percent% पूर्ण';
  }

  @override
  String treeCompleteness(int percent) {
    return 'आपका पेड़ $percent% पूरा है';
  }

  @override
  String get encryptNotice => 'AES-256 से एन्क्रिप्टेड';

  @override
  String get generatedByKinrel => 'Kinrel द्वारा बनाया गया';

  @override
  String get madeByDaxelo => 'Daxelo द्वारा प्रेम से बनाया गया';

  @override
  String get welcomeBack => 'वापस स्वागत है';

  @override
  String get goodMorning => 'सुप्रभात';

  @override
  String get goodAfternoon => 'शुभ दोपहर';

  @override
  String get goodEvening => 'शुभ संध्या';

  @override
  String get goodNight => 'शुभ रात्रि';

  @override
  String get languageName => 'हिन्दी';
}
