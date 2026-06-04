// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Sanskrit (`sa`).
class SSa extends S {
  SSa([String locale = 'sa']) : super(locale);

  @override
  String get appName => 'Kinrel';

  @override
  String get appTagline =>
      'कृत्रिमबुद्ध्या सह तव कुटुम्बस्य मानचित्रं निर्मायताम्';

  @override
  String get homeTitle => 'गृहम्';

  @override
  String get kinshipTitle => 'बन्धाः';

  @override
  String get graphTitle => 'आलेखः';

  @override
  String get alertsTitle => 'सचेतनाः';

  @override
  String get profileTitle => 'अहम्';

  @override
  String get notificationsTitle => 'सूचनाः';

  @override
  String get eventsTitle => 'उत्सवाः च समारोहाः';

  @override
  String get memoriesTitle => 'स्मृतयः च कालरेखा';

  @override
  String get chatTitle => 'कुटुम्बसंवादः';

  @override
  String get documentsTitle => 'लेखागारम्';

  @override
  String get achievementsTitle => 'सिद्धयः';

  @override
  String get shareTitle => 'साझां कुरु च आमन्त्रय';

  @override
  String get settingsTitle => 'विन्यासाः';

  @override
  String get signInTitle => 'प्रवेशः';

  @override
  String get signUpTitle => 'पञ्जीकरणम्';

  @override
  String get onboardingTitle1 => 'तव कुटुम्बम्, तव कथा';

  @override
  String get onboardingBody1 =>
      'Kinrel तव कुटुम्बस्य प्रत्येकं बन्धं मानचित्रयति — तव पितामह-पितामह्याः तव दौहित्र-दौहित्रीपर्यन्तं, यस्यां भाषायां त्वं वर्धितवान्।';

  @override
  String get onboardingTitle2 => 'नामानि यानि गृहमिव अनुभूयन्ते';

  @override
  String get onboardingBody2 =>
      'केवलम् \'अङ्कल्\' \'आण्टि\' च न — Kinrel तव पितृव्य, मातुल, भ्रातृजाया, पितामहस्य ज्येष्ठभ्रातुः च मध्ये भेदं जानाति।';

  @override
  String get onboardingTitle3 => 'बृहच्चित्रं पश्य';

  @override
  String get onboardingBody3 =>
      'तव सम्पूर्णं कुटुम्बम् एकस्मिन् सुन्दरे, परस्परक्रियाशीले आलेखे इव। समीपं गच्छ, सम्बन्धान् अन्विष्य, ये बन्धाः त्वया न ज्ञाताः तान् आविष्कुरु।';

  @override
  String get onboardingTitle4 => 'कोऽपि बन्धः तत्क्षणं अन्विष्यताम्';

  @override
  String get onboardingBody4 =>
      'कुटुम्बस्य कस्यापि द्वौ सदस्यौ चिनो — Kinrel कृत्रिमबुद्धिः तव भाषायां शुद्धं बन्धनाम गणयिष्यति।';

  @override
  String get addMember => 'सदस्यं योजय';

  @override
  String get shareFamily => 'कुटुम्बं साझां कुरु';

  @override
  String get findPath => 'मार्गम् अन्विष्य';

  @override
  String get viewFullGraph => 'सम्पूर्णम् आलेखं पश्य';

  @override
  String get recentActivity => 'अद्यतनक्रियाकलापः';

  @override
  String get familyInsights => 'कुटुम्बम् एकदृष्ट्या';

  @override
  String get noNotifications => 'सर्वं क्षेमम्! नवीनाः सूचनाः न सन्ति।';

  @override
  String get noEvents =>
      'अद्यापि कोऽपि उत्सवः नास्ति। तव कुटुम्बस्य जन्मदिवसाः वार्षिकीच अत्र स्वयमेव दृश्यन्ते।';

  @override
  String get noMemories =>
      'अद्यापि स्मृतयः न सन्ति। तव प्रथमां कुटुम्बस्मृतिं योजयित्वा आरभस्व।';

  @override
  String get noDocuments =>
      'अद्यापि लेखाः न सन्ति। तव कुटुम्बस्य महत्त्वपूर्णान् लेखान् सुरक्षितं स्थापय।';

  @override
  String get createFamily => 'कुटुम्बं सृज';

  @override
  String get joinFamily => 'कुटुम्बे सम्मिल';

  @override
  String get searchHint => 'बन्धान् अन्विष्य';

  @override
  String birthdayTomorrow(String name) {
    return '$name इत्यस्य जन्मदिवसः श्वः!';
  }

  @override
  String anniversarySoon(String name, String name2, int days) {
    return '$name तथा $name2 इत्येतयोः वार्षिकी $days दिनेषु!';
  }

  @override
  String get sendWishes => 'शुभाशंसाः प्रेष्यन्ते?';

  @override
  String streakDays(int count) {
    return '$count दिनानां शृङ्खला';
  }

  @override
  String profileCompletion(int percent) {
    return '$percent% सम्पूर्णम्';
  }

  @override
  String treeCompleteness(int percent) {
    return 'तव वृक्षः $percent% सम्पूर्णः';
  }

  @override
  String get encryptNotice => 'AES-256 इत्यनेन गोपितम्';

  @override
  String get generatedByKinrel => 'Kinrel द्वारा निर्मितम्';

  @override
  String get madeByDaxelo => 'Daxelo प्रेम्णा निर्मितम्';

  @override
  String get welcomeBack => 'पुनः स्वागतम्';

  @override
  String get goodMorning => 'सुप्रभातम्';

  @override
  String get goodAfternoon => 'शुभ मध्याह्नः';

  @override
  String get goodEvening => 'शुभ सन्ध्या';

  @override
  String get goodNight => 'शुभ रात्रिः';

  @override
  String get languageName => 'संस्कृतम्';
}
