// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Tamil (`ta`).
class STa extends S {
  STa([String locale = 'ta']) : super(locale);

  @override
  String get appName => 'Kinrel';

  @override
  String get appTagline => 'AI மூலம் உங்கள் குடும்பத்தை வரைபடமாக்குங்கள்';

  @override
  String get homeTitle => 'முகப்பு';

  @override
  String get kinshipTitle => 'உறவுகள்';

  @override
  String get graphTitle => 'வரைபடம்';

  @override
  String get alertsTitle => 'எச்சரிக்கைகள்';

  @override
  String get profileTitle => 'நான்';

  @override
  String get notificationsTitle => 'அறிவிப்புகள்';

  @override
  String get eventsTitle => 'நிகழ்வுகள் & விழாக்கள்';

  @override
  String get memoriesTitle => 'நினைவுகள் & காலவரிசை';

  @override
  String get chatTitle => 'குடும்ப அரட்டை';

  @override
  String get documentsTitle => 'ஆவண பெட்டகம்';

  @override
  String get achievementsTitle => 'சாதனைகள்';

  @override
  String get shareTitle => 'பகிர் & அழை';

  @override
  String get settingsTitle => 'அமைப்புகள்';

  @override
  String get signInTitle => 'உள்நுழை';

  @override
  String get signUpTitle => 'பதிவு செய்';

  @override
  String get onboardingTitle1 => 'உங்கள் குடும்பம், உங்கள் கதை';

  @override
  String get onboardingBody1 =>
      'Kinrel உங்கள் குடும்பத்தின் ஒவ்வொரு உறவையும் வரைபடமாக்குகிறது — உங்கள் தாத்தா பாட்டியிலிருந்து உங்கள் பேரப்பிள்ளைகள் வரை, நீங்கள் வளர்ந்த மொழியில்।';

  @override
  String get onboardingTitle2 => 'வீட்டு உணர்வைத் தரும் பெயர்கள்';

  @override
  String get onboardingBody2 =>
      'வெறும் \'அங்கிள்\' மற்றும் \'ஆண்டி\' மட்டுமல்ல — Kinrel உங்கள் சித்தப்பா, மாமா, சித்தி மற்றும் பெரியப்பா இடையேயான வேறுபாட்டை அறியும்।';

  @override
  String get onboardingTitle3 => 'பெரிய படத்தைப் பாருங்கள்';

  @override
  String get onboardingBody3 =>
      'உங்கள் முழு குடும்பமும் ஒரு அழகான, ஊடாடும் வரைபடமாக. பெரிதாக்குங்கள், இணைப்புகளை ஆராயுங்கள், நீங்கள் அறியாத உறவுகளைக் கண்டறியுங்கள்।';

  @override
  String get onboardingTitle4 => 'எந்த உறவையும் உடனடியாகக் கண்டறியுங்கள்';

  @override
  String get onboardingBody4 =>
      'குடும்பத்தின் ஏதேனும் இரு உறுப்பினர்களைத் தேர்ந்தெடுங்கள் — Kinrel AI உங்கள் மொழியில் சரியான உறவுப் பெயரைக் கணக்கிடும்।';

  @override
  String get addMember => 'உறுப்பினர் சேர்';

  @override
  String get shareFamily => 'குடும்பத்தைப் பகிர்';

  @override
  String get findPath => 'பாதையைக் கண்டறி';

  @override
  String get viewFullGraph => 'முழு வரைபடத்தையும் பார்';

  @override
  String get recentActivity => 'சமீபத்திய செயல்பாடு';

  @override
  String get familyInsights => 'குடும்பம் ஒரு பார்வையில்';

  @override
  String get noNotifications => 'எல்லாம் சரி! புதிய அறிவிப்புகள் இல்லை।';

  @override
  String get noEvents =>
      'இன்னும் நிகழ்வுகள் இல்லை. உங்கள் குடும்ப பிறந்தநாட்கள் மற்றும் ஆண்டுவிழாக்கள் இங்கே தானாகத் தோன்றும்।';

  @override
  String get noMemories =>
      'இன்னும் நினைவுகள் இல்லை. உங்கள் முதல் குடும்ப நினைவைச் சேர்த்துத் தொடங்குங்கள்।';

  @override
  String get noDocuments =>
      'இன்னும் ஆவணங்கள் இல்லை. உங்கள் குடும்பத்தின் முக்கிய ஆவணங்களைப் பாதுகாப்பாகச் சேமியுங்கள்।';

  @override
  String get createFamily => 'குடும்பம் உருவாக்கு';

  @override
  String get joinFamily => 'குடும்பத்தில் சேர்';

  @override
  String get searchHint => 'உறவுகளைத் தேடு';

  @override
  String birthdayTomorrow(String name) {
    return '$name-ன் பிறந்தநாள் நாளை!';
  }

  @override
  String anniversarySoon(String name, String name2, int days) {
    return '$name மற்றும் $name2-ன் ஆண்டுவிழா $days நாட்களில்!';
  }

  @override
  String get sendWishes => 'வாழ்த்துக்கள் அனுப்பலாமா?';

  @override
  String streakDays(int count) {
    return '$count நாள் தொடர்';
  }

  @override
  String profileCompletion(int percent) {
    return '$percent% முடிந்தது';
  }

  @override
  String treeCompleteness(int percent) {
    return 'உங்கள் மரம் $percent% முழுமையாகியுள்ளது';
  }

  @override
  String get encryptNotice => 'AES-256 மூலம் மறைகுறியாக்கப்பட்டது';

  @override
  String get generatedByKinrel => 'Kinrel மூலம் உருவாக்கப்பட்டது';

  @override
  String get madeByDaxelo => 'Daxelo அன்போடு உருவாக்கியது';

  @override
  String get welcomeBack => 'மீண்டும் வரவேற்கிறோம்';

  @override
  String get goodMorning => 'காலை வணக்கம்';

  @override
  String get goodAfternoon => 'மதிய வணக்கம்';

  @override
  String get goodEvening => 'மாலை வணக்கம்';

  @override
  String get goodNight => 'இரவு வணக்கம்';

  @override
  String get languageName => 'தமிழ்';
}
