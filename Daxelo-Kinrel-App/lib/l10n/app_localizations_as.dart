// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Assamese (`as`).
class SAs extends S {
  SAs([String locale = 'as']) : super(locale);

  @override
  String get appName => 'Kinrel';

  @override
  String get appTagline => 'AI ৰ সৈতে আপোনাৰ পৰিয়ালৰ মানচিত্ৰ তৈয়াৰ কৰক';

  @override
  String get homeTitle => 'হোম';

  @override
  String get kinshipTitle => 'সম্পৰ্ক';

  @override
  String get graphTitle => 'গ্ৰাফ';

  @override
  String get alertsTitle => 'সতৰ্কতা';

  @override
  String get profileTitle => 'মই';

  @override
  String get notificationsTitle => 'জাননী';

  @override
  String get eventsTitle => 'অনুষ্ঠান আৰু উৎসৱ';

  @override
  String get memoriesTitle => 'স্মৃতি আৰু সময়ৰেখা';

  @override
  String get chatTitle => 'পাৰিয়ালিক চেট';

  @override
  String get documentsTitle => 'নথি ভল্ট';

  @override
  String get achievementsTitle => 'সাফল্য';

  @override
  String get shareTitle => 'শ্বেয়াৰ আৰু নিমন্ত্ৰণ';

  @override
  String get settingsTitle => 'ছেটিংছ';

  @override
  String get signInTitle => 'ছাইন ইন';

  @override
  String get signUpTitle => 'ছাইন আপ';

  @override
  String get onboardingTitle1 => 'আপোনাৰ পৰিয়াল, আপোনাৰ কাহিনী';

  @override
  String get onboardingBody1 =>
      'Kinrel আপোনাৰ পৰিয়ালৰ প্ৰতিটো সম্পৰ্ক মেপ কৰে — আপোনাৰ ককাইদেউ-আইদেউৰ পৰা আপোনাৰ নাতি-নাতিনীলৈকে, যিটো ভাষাত আপুনি ডাঙৰ-দীঘল হৈছে।';

  @override
  String get onboardingTitle2 => 'নাম যিবোৰে ঘৰৰ দৰে অনুভৱ কৰায়';

  @override
  String get onboardingBody2 =>
      'কেৱল \'আংকল\' আৰু \'আণ্টি\' নহয় — Kinrel আপোনাৰ কাকাই, মামা, পেহী আৰু বৰদেউতাৰ মাজৰ পাৰ্থক্য জানে।';

  @override
  String get onboardingTitle3 => 'ডাঙৰ ছবিখন চাওক';

  @override
  String get onboardingBody3 =>
      'আপোনাৰ সম্পূৰ্ণ পৰিয়াল এটা সুন্দৰ, ইণ্টাৰেক্টিভ গ্ৰাফৰ দৰে। জুম ইন কৰক, সম্পৰ্কসমূহ অন্বেষণ কৰক, এনে সম্পৰ্ক আৱিষ্কাৰ কৰক যিবোৰ আপুনি নজানিছিল।';

  @override
  String get onboardingTitle4 => 'যিকোনো সম্পৰ্ক তৎক্ষণাৎ বিচাৰক';

  @override
  String get onboardingBody4 =>
      'পৰিয়ালৰ যিকোনো দুজন সদস্য বাছক — Kinrel ৰ AI আপোনাৰ ভাষাত সঠিক সম্পৰ্কৰ নাম গণনা কৰিব।';

  @override
  String get addMember => 'সদস্য যোগ কৰক';

  @override
  String get shareFamily => 'পৰিয়াল শ্বেয়াৰ কৰক';

  @override
  String get findPath => 'পথ বিচাৰক';

  @override
  String get viewFullGraph => 'সম্পূৰ্ণ গ্ৰাফ চাওক';

  @override
  String get recentActivity => 'শেহতীয়া কাৰ্যকলাপ';

  @override
  String get familyInsights => 'পৰিয়াল এক দৃষ্টিত';

  @override
  String get noNotifications => 'সকলো ঠিক! কোনো নতুন জাননী নাই।';

  @override
  String get noEvents =>
      'এতিয়ালৈকে কোনো অনুষ্ঠান নাই। আপোনাৰ পৰিয়ালৰ জন্মদিন আৰু বাৰ্ষিকী ইয়াত স্বয়ংক্ৰিয়ভাৱে দেখা যাব।';

  @override
  String get noMemories =>
      'এতিয়ালৈকে কোনো স্মৃতি নাই। আপোনাৰ প্ৰথম পাৰিয়ালিক স্মৃতি যোগ কৰি আৰম্ভ কৰক।';

  @override
  String get noDocuments =>
      'এতিয়ালৈকে কোনো নথি নাই। আপোনাৰ পৰিয়ালৰ গুৰুত্বপূৰ্ণ নথিসমূহ সুৰক্ষিতভাৱে সঞ্চয় কৰক।';

  @override
  String get createFamily => 'পৰিয়াল সৃষ্টি কৰক';

  @override
  String get joinFamily => 'পৰিয়ালত যোগদান কৰক';

  @override
  String get searchHint => 'সম্পৰ্ক বিচাৰক';

  @override
  String birthdayTomorrow(String name) {
    return '$nameৰ জন্মদিন কাইলৈ!';
  }

  @override
  String anniversarySoon(String name, String name2, int days) {
    return '$name আৰু $name2ৰ বাৰ্ষিকী $days দিনত!';
  }

  @override
  String get sendWishes => 'শুভেচ্ছা পঠিয়াবনে?';

  @override
  String streakDays(int count) {
    return '$count দিনৰ ধাৰাবাহিকতা';
  }

  @override
  String profileCompletion(int percent) {
    return '$percent% সম্পূৰ্ণ';
  }

  @override
  String treeCompleteness(int percent) {
    return 'আপোনাৰ গছ $percent% সম্পূৰ্ণ';
  }

  @override
  String get encryptNotice => 'AES-256 ৰে এনক্ৰিপ্টেড';

  @override
  String get generatedByKinrel => 'Kinrel দ্বাৰা সৃষ্টি';

  @override
  String get madeByDaxelo => 'Daxeloৰ প্ৰেমেৰে নিৰ্মিত';

  @override
  String get welcomeBack => 'পুনৰ স্বাগতম';

  @override
  String get goodMorning => 'সুপ্ৰভাত';

  @override
  String get goodAfternoon => 'শুভ দুপৰীয়া';

  @override
  String get goodEvening => 'শুভ সন্ধিয়া';

  @override
  String get goodNight => 'শুভ ৰাতি';

  @override
  String get languageName => 'অসমীয়া';
}
