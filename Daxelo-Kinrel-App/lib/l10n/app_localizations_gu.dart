// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Gujarati (`gu`).
class SGu extends S {
  SGu([String locale = 'gu']) : super(locale);

  @override
  String get appName => 'Kinrel';

  @override
  String get appTagline => 'AI સાથે તમારા પરિવારનો નકશો બનાવો';

  @override
  String get homeTitle => 'હોમ';

  @override
  String get kinshipTitle => 'સંબંધો';

  @override
  String get graphTitle => 'ગ્રાફ';

  @override
  String get alertsTitle => 'અલર્ટ';

  @override
  String get profileTitle => 'હું';

  @override
  String get notificationsTitle => 'સૂચનાઓ';

  @override
  String get eventsTitle => 'કાર્યક્રમો અને ઉત્સવો';

  @override
  String get memoriesTitle => 'યાદો અને સમયરેખા';

  @override
  String get chatTitle => 'પારિવારિક ચેટ';

  @override
  String get documentsTitle => 'દસ્તાવેજ વોલ્ટ';

  @override
  String get achievementsTitle => 'સિદ્ધિઓ';

  @override
  String get shareTitle => 'શેર અને આમંત્રણ';

  @override
  String get settingsTitle => 'સેટિંગ્સ';

  @override
  String get signInTitle => 'સાઇન ઇન';

  @override
  String get signUpTitle => 'સાઇન અપ';

  @override
  String get onboardingTitle1 => 'તમારો પરિવાર, તમારી વાર્તા';

  @override
  String get onboardingBody1 =>
      'Kinrel તમારા પરિવારના દરેક સંબંધને મેપ કરે છે — તમારા દાદા-દાદીથી લઈને તમારા પૌત્રો સુધી, જે ભાષામાં તમે મોટા થયા।';

  @override
  String get onboardingTitle2 => 'નામો જે ઘર જેવા લાગે';

  @override
  String get onboardingBody2 =>
      'ફક્ત \'અંકલ\' અને \'આન્ટી\' નહીં — Kinrel તમારા કાકા, મામા, ફૂઆ અને તાઉજી વચ્ચેનો તફાવત જાણે છે।';

  @override
  String get onboardingTitle3 => 'મોટું ચિત્ર જુઓ';

  @override
  String get onboardingBody3 =>
      'તમારો આખો પરિવાર એક સુંદર, ઇન્ટરેક્ટિવ ગ્રાફ તરીકે. ઝૂમ ઇન કરો, જોડાણો શોધો, એવા સંબંધો શોધો જે તમને ખબર નહોતી।';

  @override
  String get onboardingTitle4 => 'કોઈપણ સંબંધ તાત્કાલિક શોધો';

  @override
  String get onboardingBody4 =>
      'પરિવારના કોઈપણ બે સભ્યો પસંદ કરો — Kinrel નું AI તમારી ભાષામાં ચોક્કસ સંબંધનું નામ ગણશે।';

  @override
  String get addMember => 'સભ્ય ઉમેરો';

  @override
  String get shareFamily => 'પરિવાર શેર કરો';

  @override
  String get findPath => 'માર્ગ શોધો';

  @override
  String get viewFullGraph => 'સંપૂર્ણ ગ્રાફ જુઓ';

  @override
  String get recentActivity => 'તાજેતરની પ્રવૃત્તિ';

  @override
  String get familyInsights => 'પરિવાર એક નજરમાં';

  @override
  String get noNotifications => 'બધું બરાબર! કોઈ નવી સૂચના નથી।';

  @override
  String get noEvents =>
      'હજુ કોઈ કાર્યક્રમ નથી. તમારા પરિવારના જન્મદિવસ અને વર્ષગાંઠ અહીં આપમેળે દેખાશે।';

  @override
  String get noMemories =>
      'હજુ કોઈ યાદ નથી. તમારી પ્રથમ પારિવારિક યાદ ઉમેરીને શરૂ કરો।';

  @override
  String get noDocuments =>
      'હજુ કોઈ દસ્તાવેજ નથી. તમારા પરિવારના મહત્વપૂર્ણ દસ્તાવેજ સુરક્ષિત રીતે સંગ્રહિત કરો।';

  @override
  String get createFamily => 'પરિવાર બનાવો';

  @override
  String get joinFamily => 'પરિવારમાં જોડાઓ';

  @override
  String get searchHint => 'સંબંધો શોધો';

  @override
  String birthdayTomorrow(String name) {
    return '$name નો જન્મદિવસ કાલે!';
  }

  @override
  String anniversarySoon(String name, String name2, int days) {
    return '$name અને $name2 ની વર્ષગાંઠ $days દિવસમાં!';
  }

  @override
  String get sendWishes => 'શુભેચ્છા મોકલશો?';

  @override
  String streakDays(int count) {
    return '$count દિવસની સળંગતા';
  }

  @override
  String profileCompletion(int percent) {
    return '$percent% પૂર્ણ';
  }

  @override
  String treeCompleteness(int percent) {
    return 'તમારું વૃક્ષ $percent% પૂર્ણ છે';
  }

  @override
  String get encryptNotice => 'AES-256 થી એન્ક્રિપ્ટેડ';

  @override
  String get generatedByKinrel => 'Kinrel દ્વારા બનાવેલ';

  @override
  String get madeByDaxelo => 'Daxelo દ્વારા પ્રેમથી બનાવેલ';

  @override
  String get welcomeBack => 'ફરીથી સ્વાગત';

  @override
  String get goodMorning => 'સુપ્રભાત';

  @override
  String get goodAfternoon => 'શુભ બપોર';

  @override
  String get goodEvening => 'શુભ સાંજ';

  @override
  String get goodNight => 'શુભ રાત્રિ';

  @override
  String get languageName => 'ગુજરાતી';
}
