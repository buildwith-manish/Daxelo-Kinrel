// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Bengali Bangla (`bn`).
class SBn extends S {
  SBn([String locale = 'bn']) : super(locale);

  @override
  String get appName => 'Kinrel';

  @override
  String get appTagline => 'AI দিয়ে আপনার পরিবারের মানচিত্র তৈরি করুন';

  @override
  String get homeTitle => 'হোম';

  @override
  String get kinshipTitle => 'সম্পর্ক';

  @override
  String get graphTitle => 'গ্রাফ';

  @override
  String get alertsTitle => 'সতর্কতা';

  @override
  String get profileTitle => 'আমি';

  @override
  String get notificationsTitle => 'বিজ্ঞপ্তি';

  @override
  String get eventsTitle => 'অনুষ্ঠান ও উৎসব';

  @override
  String get memoriesTitle => 'স্মৃতি ও সময়রেখা';

  @override
  String get chatTitle => 'পারিবারিক চ্যাট';

  @override
  String get documentsTitle => 'নথি ভল্ট';

  @override
  String get achievementsTitle => 'অর্জন';

  @override
  String get shareTitle => 'শেয়ার ও আমন্ত্রণ';

  @override
  String get settingsTitle => 'সেটিংস';

  @override
  String get signInTitle => 'সাইন ইন';

  @override
  String get signUpTitle => 'সাইন আপ';

  @override
  String get onboardingTitle1 => 'আপনার পরিবার, আপনার গল্প';

  @override
  String get onboardingBody1 =>
      'Kinrel আপনার পরিবারের প্রতিটি সম্পর্ক ম্যাপ করে — আপনার দাদা-দাদি থেকে আপনার নাতি-নাতনি পর্যন্ত, যে ভাষায় আপনি বেড়ে উঠেছেন।';

  @override
  String get onboardingTitle2 => 'নাম যা বাড়ির মতো মনে হয়';

  @override
  String get onboardingBody2 =>
      'শুধু \'আঙ্কেল\' এবং \'আন্টি\' নয় — Kinrel আপনার কাকা, মামা, ফুফা এবং জ্যাঠার মধ্যে পার্থক্য জানে।';

  @override
  String get onboardingTitle3 => 'বড় ছবিটি দেখুন';

  @override
  String get onboardingBody3 =>
      'আপনার পুরো পরিবার একটি সুন্দর, ইন্টারেক্টিভ গ্রাফ হিসেবে। জুম ইন করুন, সংযোগ অন্বেষণ করুন, এমন সম্পর্ক আবিষ্কার করুন যা আপনি জানতেন না।';

  @override
  String get onboardingTitle4 => 'যেকোনো সম্পর্ক তৎক্ষণাৎ খুঁজুন';

  @override
  String get onboardingBody4 =>
      'পরিবারের যেকোনো দুজন সদস্য নির্বাচন করুন — Kinrel-এর AI আপনার ভাষায় সঠিক সম্পর্কের নাম গণনা করবে।';

  @override
  String get addMember => 'সদস্য যোগ করুন';

  @override
  String get shareFamily => 'পরিবার শেয়ার করুন';

  @override
  String get findPath => 'পথ খুঁজুন';

  @override
  String get viewFullGraph => 'সম্পূর্ণ গ্রাফ দেখুন';

  @override
  String get recentActivity => 'সাম্প্রতিক কার্যকলাপ';

  @override
  String get familyInsights => 'পরিবার একনজরে';

  @override
  String get noNotifications => 'সব ঠিক আছে! কোনো নতুন বিজ্ঞপ্তি নেই।';

  @override
  String get noEvents =>
      'এখনো কোনো অনুষ্ঠান নেই। আপনার পরিবারের জন্মদিন ও বার্ষিকী এখানে স্বয়ংক্রিয়ভাবে দেখা যাবে।';

  @override
  String get noMemories =>
      'এখনো কোনো স্মৃতি নেই। আপনার প্রথম পারিবারিক স্মৃতি যোগ করে শুরু করুন।';

  @override
  String get noDocuments =>
      'এখনো কোনো নথি নেই। আপনার পরিবারের গুরুত্বপূর্ণ নথি নিরাপদে সংরক্ষণ করুন।';

  @override
  String get createFamily => 'পরিবার তৈরি করুন';

  @override
  String get joinFamily => 'পরিবারে যোগ দিন';

  @override
  String get searchHint => 'সম্পর্ক খুঁজুন';

  @override
  String birthdayTomorrow(String name) {
    return '$name-এর জন্মদিন আগামীকাল!';
  }

  @override
  String anniversarySoon(String name, String name2, int days) {
    return '$name ও $name2-এর বার্ষিকী $days দিনে!';
  }

  @override
  String get sendWishes => 'শুভেচ্ছা পাঠাবেন?';

  @override
  String streakDays(int count) {
    return '$count দিনের ধারা';
  }

  @override
  String profileCompletion(int percent) {
    return '$percent% সম্পন্ন';
  }

  @override
  String treeCompleteness(int percent) {
    return 'আপনার গাছ $percent% সম্পূর্ণ';
  }

  @override
  String get encryptNotice => 'AES-256 দিয়ে এনক্রিপ্টেড';

  @override
  String get generatedByKinrel => 'Kinrel দ্বারা তৈরি';

  @override
  String get madeByDaxelo => 'Daxelo-এর ভালোবাসায় তৈরি';

  @override
  String get welcomeBack => 'ফিরে স্বাগতম';

  @override
  String get goodMorning => 'সুপ্রভাত';

  @override
  String get goodAfternoon => 'শুভ দুপুর';

  @override
  String get goodEvening => 'শুভ সন্ধ্যা';

  @override
  String get goodNight => 'শুভ রাত্রি';

  @override
  String get languageName => 'বাংলা';
}
