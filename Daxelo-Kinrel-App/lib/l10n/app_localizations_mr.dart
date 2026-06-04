// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Marathi (`mr`).
class SMr extends S {
  SMr([String locale = 'mr']) : super(locale);

  @override
  String get appName => 'Kinrel';

  @override
  String get appTagline => 'AI सह तुमच्या कुटुंबाचे नकाशे तयार करा';

  @override
  String get homeTitle => 'होम';

  @override
  String get kinshipTitle => 'नाती';

  @override
  String get graphTitle => 'ग्राफ';

  @override
  String get alertsTitle => 'अलर्ट';

  @override
  String get profileTitle => 'मी';

  @override
  String get notificationsTitle => 'सूचना';

  @override
  String get eventsTitle => 'कार्यक्रम आणि उत्सव';

  @override
  String get memoriesTitle => 'आठवणी आणि वेळरेषा';

  @override
  String get chatTitle => 'कौटुंबिक चॅट';

  @override
  String get documentsTitle => 'दस्तावेज वॉल्ट';

  @override
  String get achievementsTitle => 'यश';

  @override
  String get shareTitle => 'शेअर आणि आमंत्रण';

  @override
  String get settingsTitle => 'सेटिंग्ज';

  @override
  String get signInTitle => 'साइन इन';

  @override
  String get signUpTitle => 'साइन अप';

  @override
  String get onboardingTitle1 => 'तुमचे कुटुंब, तुमची कथा';

  @override
  String get onboardingBody1 =>
      'Kinrel तुमच्या कुटुंबातील प्रत्येक नाते मॅप करते — तुमच्या आजोबांपासून तुमच्या नातवांपर्यंत, ज्या भाषेत तुम्ही वाढलात त्या भाषेत।';

  @override
  String get onboardingTitle2 => 'नावे जी घरासारखी वाटतात';

  @override
  String get onboardingBody2 =>
      'फक्त \'अंकल\' आणि \'आंटी\' नाही — Kinrel तुमच्या काका, मामा, आत्या आणि दादांमधील फरक ओळखते।';

  @override
  String get onboardingTitle3 => 'मोठे चित्र पहा';

  @override
  String get onboardingBody3 =>
      'तुमचे संपूर्ण कुटुंब एका सुंदर, इंटरॅक्टिव्ह ग्राफसारखे। झूम इन करा, संबंध शोधा, अशी नाती शोधा ज्यांची तुम्हाला माहिती नव्हती।';

  @override
  String get onboardingTitle4 => 'कोणतेही नाते त्वरित शोधा';

  @override
  String get onboardingBody4 =>
      'कुटुंबातील कोणत्याही दोन सदस्यांची निवड करा — Kinrel चे AI तुमच्या भाषेत अचूक नात्याचे नाव मोजेल।';

  @override
  String get addMember => 'सदस्य जोडा';

  @override
  String get shareFamily => 'कुटुंब शेअर करा';

  @override
  String get findPath => 'मार्ग शोधा';

  @override
  String get viewFullGraph => 'संपूर्ण ग्राफ पहा';

  @override
  String get recentActivity => 'अलीकडील क्रियाकलाप';

  @override
  String get familyInsights => 'कुटुंब एका दृष्टीक्षेपात';

  @override
  String get noNotifications => 'सर्व ठीक! नवीन सूचना नाहीत।';

  @override
  String get noEvents =>
      'अजून कार्यक्रम नाहीत. तुमच्या कुटुंबातील वाढदिवस आणि वाढदिवस येथे आपोआप दिसतील।';

  @override
  String get noMemories =>
      'अजून आठवणी नाहीत. तुमची पहिली कौटुंबिक आठवण जोडून सुरुवात करा।';

  @override
  String get noDocuments =>
      'अजून दस्तावेज नाहीत. तुमच्या कुटुंबाची महत्त्वाची दस्तावेज सुरक्षितपणे साठवा।';

  @override
  String get createFamily => 'कुटुंब तयार करा';

  @override
  String get joinFamily => 'कुटुंबात सामील व्हा';

  @override
  String get searchHint => 'नाती शोधा';

  @override
  String birthdayTomorrow(String name) {
    return '$name यांचा वाढदिवस उद्या!';
  }

  @override
  String anniversarySoon(String name, String name2, int days) {
    return '$name आणि $name2 यांचा वाढदिवस $days दिवसांत!';
  }

  @override
  String get sendWishes => 'शुभेच्छा पाठवायच्या?';

  @override
  String streakDays(int count) {
    return '$count दिवसांची सातत्यता';
  }

  @override
  String profileCompletion(int percent) {
    return '$percent% पूर्ण';
  }

  @override
  String treeCompleteness(int percent) {
    return 'तुमचे झाड $percent% पूर्ण आहे';
  }

  @override
  String get encryptNotice => 'AES-256 ने एनक्रिप्टेड';

  @override
  String get generatedByKinrel => 'Kinrel द्वारे तयार';

  @override
  String get madeByDaxelo => 'Daxelo यांनी प्रेमाने तयार केले';

  @override
  String get welcomeBack => 'पुन्हा स्वागत';

  @override
  String get goodMorning => 'शुभ सकाळ';

  @override
  String get goodAfternoon => 'शुभ दुपार';

  @override
  String get goodEvening => 'शुभ संध्याकाळ';

  @override
  String get goodNight => 'शुभ रात्री';

  @override
  String get languageName => 'मराठी';
}
