// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Urdu (`ur`).
class SUr extends S {
  SUr([String locale = 'ur']) : super(locale);

  @override
  String get appName => 'Kinrel';

  @override
  String get appTagline => 'AI کے ساتھ اپنے خاندان کا نقشہ بنائیں';

  @override
  String get homeTitle => 'ہوم';

  @override
  String get kinshipTitle => 'رشتے';

  @override
  String get graphTitle => 'گراف';

  @override
  String get alertsTitle => 'الرٹس';

  @override
  String get profileTitle => 'میں';

  @override
  String get notificationsTitle => 'اطلاعات';

  @override
  String get eventsTitle => 'تقریبات اور تہوار';

  @override
  String get memoriesTitle => 'یادیں اور ٹائم لائن';

  @override
  String get chatTitle => 'خاندانی چیٹ';

  @override
  String get documentsTitle => 'دستاویز والٹ';

  @override
  String get achievementsTitle => 'کامیابیاں';

  @override
  String get shareTitle => 'شیئر اور دعوت';

  @override
  String get settingsTitle => 'ترتیبات';

  @override
  String get signInTitle => 'سائن ان';

  @override
  String get signUpTitle => 'سائن اپ';

  @override
  String get onboardingTitle1 => 'آپ کا خاندان، آپ کی کہانی';

  @override
  String get onboardingBody1 =>
      'Kinrel آپ کے خاندان کے ہر رشتے کو نقشے پر لاتا ہے — آپ کے دادا دادی سے آپ کے پوتے پوتیوں تک، اس زبان میں جس میں آپ پلے بڑھے۔';

  @override
  String get onboardingTitle2 => 'نام جو گھر جیسے لگیں';

  @override
  String get onboardingBody2 =>
      'صرف \'انکل\' اور \'آنٹی\' نہیں — Kinrel آپ کے چچا، ماموں، پھپھا اور تایا کے درمیان فرق جانتا ہے۔';

  @override
  String get onboardingTitle3 => 'بڑی تصویر دیکھیں';

  @override
  String get onboardingBody3 =>
      'آپ کا پورا خاندان ایک خوبصورت، انٹرایکٹو گراف کی طرح۔ زوم ان کریں، رابطوں کی تلاش کریں، ایسے رشتے دریافت کریں جن کے بارے میں آپ نہیں جانتے تھے۔';

  @override
  String get onboardingTitle4 => 'کوئی بھی رشتہ فوراً تلاش کریں';

  @override
  String get onboardingBody4 =>
      'خاندان کے کسی بھی دو اراکین کا انتخاب کریں — Kinrel کا AI آپ کی زبان میں درست رشتے کا نام بتائے گا۔';

  @override
  String get addMember => 'رکن شامل کریں';

  @override
  String get shareFamily => 'خاندان شیئر کریں';

  @override
  String get findPath => 'راستہ تلاش کریں';

  @override
  String get viewFullGraph => 'مکمل گراف دیکھیں';

  @override
  String get recentActivity => 'حالیہ سرگرمی';

  @override
  String get familyInsights => 'خاندان ایک نظر میں';

  @override
  String get noNotifications => 'سب ٹھیک ہے! کوئی نئی اطلاع نہیں۔';

  @override
  String get noEvents =>
      'ابھی تک کوئی تقریب نہیں۔ آپ کے خاندان کی سالگرہیں اور سالگرہیں یہاں خود بخود نظر آئیں گی۔';

  @override
  String get noMemories =>
      'ابھی تک کوئی یاد نہیں۔ اپنی پہلی خاندانی یاد شامل کر کے شروع کریں۔';

  @override
  String get noDocuments =>
      'ابھی تک کوئی دستاویز نہیں۔ اپنے خاندان کی اہم دستاویزات محفوظ طریقے سے محفوظ کریں۔';

  @override
  String get createFamily => 'خاندان بنائیں';

  @override
  String get joinFamily => 'خاندان میں شامل ہوں';

  @override
  String get searchHint => 'رشتے تلاش کریں';

  @override
  String birthdayTomorrow(String name) {
    return '$name کی سالگرہ کل ہے!';
  }

  @override
  String anniversarySoon(String name, String name2, int days) {
    return '$name اور $name2 کی سالگرہ $days دنوں میں!';
  }

  @override
  String get sendWishes => 'مبارکباد بھیجیں؟';

  @override
  String streakDays(int count) {
    return '$count دن کا سلسلہ';
  }

  @override
  String profileCompletion(int percent) {
    return '$percent% مکمل';
  }

  @override
  String treeCompleteness(int percent) {
    return 'آپ کا درخت $percent% مکمل ہے';
  }

  @override
  String get encryptNotice => 'AES-256 سے انکرپٹڈ';

  @override
  String get generatedByKinrel => 'Kinrel کے ذریعے تیار کردہ';

  @override
  String get madeByDaxelo => 'Daxelo کی محبت سے بنایا گیا';

  @override
  String get welcomeBack => 'خوش آمدید';

  @override
  String get goodMorning => 'صبح بخیر';

  @override
  String get goodAfternoon => 'دوپہر بخیر';

  @override
  String get goodEvening => 'شام بخیر';

  @override
  String get goodNight => 'رات بخیر';

  @override
  String get languageName => 'اردو';
}
