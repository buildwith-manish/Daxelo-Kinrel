// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Sindhi (`sd`).
class SSd extends S {
  SSd([String locale = 'sd']) : super(locale);

  @override
  String get appName => 'Kinrel';

  @override
  String get appTagline => 'AI سان پنهنجي خاندان جو نقشو ٺاهيو';

  @override
  String get homeTitle => 'هوم';

  @override
  String get kinshipTitle => 'رشتا';

  @override
  String get graphTitle => 'گراف';

  @override
  String get alertsTitle => 'الرٽس';

  @override
  String get profileTitle => 'مان';

  @override
  String get notificationsTitle => 'اطلاعون';

  @override
  String get eventsTitle => 'تقريبن ۽ تہوار';

  @override
  String get memoriesTitle => 'يادون ۽ وقت لڪير';

  @override
  String get chatTitle => 'خانداني چيٽ';

  @override
  String get documentsTitle => 'دستاويز والٽ';

  @override
  String get achievementsTitle => 'ڪاميابيون';

  @override
  String get shareTitle => 'شيئر ۽ دعوت';

  @override
  String get settingsTitle => 'ترتيبون';

  @override
  String get signInTitle => 'سائن ان';

  @override
  String get signUpTitle => 'سائن اپ';

  @override
  String get onboardingTitle1 => 'توهان جو خاندان، توهان جي ڪهاڻي';

  @override
  String get onboardingBody1 =>
      'Kinrel توهان جي خاندان جي هر رشتي کي نقشي تي آڻي ٿو — توهان جي ڏاڏي ڏاڏي کان توهان جي پوٽن پوٽين تائين، ان ٻولي ۾ جنهن ۾ توهان وڏا ٿيا۔';

  @override
  String get onboardingTitle2 => 'نالا جيڪي گهر جهڙا لڳن';

  @override
  String get onboardingBody2 =>
      'صرف \'انكل\' ۽ \'آنٽي\' ناهي — Kinrel توهان جي چاچي، مامي، پڦي ۽ تائي جي وچ ۾ فرق ڄاڻي ٿو۔';

  @override
  String get onboardingTitle3 => 'وڏي تصوير ڏسو';

  @override
  String get onboardingBody3 =>
      'توهان جو پورو خاندان هڪ خوبصورت، انٽرئڪٽو گراف جي طور تي۔ زوم ان ڪريو، رابطا ڳوليو، اهڙا رشتا دريافت ڪريو جنهن بابت توهان کي خبر ناهي۔';

  @override
  String get onboardingTitle4 => 'ڪو به رشتو فوري ڳوليو';

  @override
  String get onboardingBody4 =>
      'خاندان جي ڪنهن به ٻن ميمبرن جو چونڊ ڪريو — Kinrel جو AI توهان جي ٻولي ۾ صحيح رشتو جو نالو ڳڻي ٿو۔';

  @override
  String get addMember => 'ميمبر شامل ڪريو';

  @override
  String get shareFamily => 'خاندان شيئر ڪريو';

  @override
  String get findPath => 'رستو ڳوليو';

  @override
  String get viewFullGraph => 'مڪمل گراف ڏسو';

  @override
  String get recentActivity => 'تازہ سرگرمي';

  @override
  String get familyInsights => 'خاندان هڪ نظر ۾';

  @override
  String get noNotifications => 'سڀ ٺيڪ! ڪا نئي اطلاع ناهي۔';

  @override
  String get noEvents =>
      'اڃا تائين ڪا تقريب ناهي۔ توهان جي خاندان جا سالگرهون ۽ سالگرهون هتي خودڪار طور تي نظر اينديون۔';

  @override
  String get noMemories =>
      'اڃا تائين ڪا ياد ناهي۔ پنهنجي پهرين خانداني ياد شامل ڪري شروع ڪريو۔';

  @override
  String get noDocuments =>
      'اڃا تائين ڪو دستاويز ناهي۔ پنهنجي خاندان جي اهم دستاويزن کي محفوظ طريقي سان محفوظ ڪريو۔';

  @override
  String get createFamily => 'خاندان ٺاهيو';

  @override
  String get joinFamily => 'خاندان ۾ شامل ٿيو';

  @override
  String get searchHint => 'رشتا ڳوليو';

  @override
  String birthdayTomorrow(String name) {
    return '$name جي سالگرهه سڀاڻي آهي!';
  }

  @override
  String anniversarySoon(String name, String name2, int days) {
    return '$name ۽ $name2 جي سالگرهه $days ڏينهن ۾!';
  }

  @override
  String get sendWishes => 'مبارڪباد موڪليو؟';

  @override
  String streakDays(int count) {
    return '$count ڏينهن جو سلسلو';
  }

  @override
  String profileCompletion(int percent) {
    return '$percent% مڪمل';
  }

  @override
  String treeCompleteness(int percent) {
    return 'توهان جو وڻ $percent% مڪمل آهي';
  }

  @override
  String get encryptNotice => 'AES-256 سان انڪرپٽڊ';

  @override
  String get generatedByKinrel => 'Kinrel پاران تيار ڪيل';

  @override
  String get madeByDaxelo => 'Daxelo جي محبت سان ٺاهيل';

  @override
  String get welcomeBack => 'واهه واپس';

  @override
  String get goodMorning => 'صبح بخير';

  @override
  String get goodAfternoon => 'ڊوپھر بخير';

  @override
  String get goodEvening => 'شام بخير';

  @override
  String get goodNight => 'رات بخير';

  @override
  String get languageName => 'सिन्धी';
}
