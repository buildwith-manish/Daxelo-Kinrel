// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Telugu (`te`).
class STe extends S {
  STe([String locale = 'te']) : super(locale);

  @override
  String get appName => 'Kinrel';

  @override
  String get appTagline => 'AIతో మీ కుటుంబాన్ని మ్యాప్ చేయండి';

  @override
  String get homeTitle => 'హోమ్';

  @override
  String get kinshipTitle => 'సంబంధాలు';

  @override
  String get graphTitle => 'గ్రాఫ్';

  @override
  String get alertsTitle => 'అలర్ట్లు';

  @override
  String get profileTitle => 'నేను';

  @override
  String get notificationsTitle => 'నోటిఫికేషన్లు';

  @override
  String get eventsTitle => 'కార్యక్రమాలు & వేడుకలు';

  @override
  String get memoriesTitle => 'జ్ఞాపకాలు & కాలరేఖ';

  @override
  String get chatTitle => 'కుటుంబ చాట్';

  @override
  String get documentsTitle => 'పత్రాల వాల్ట్';

  @override
  String get achievementsTitle => 'విజయాలు';

  @override
  String get shareTitle => 'షేర్ & ఆహ్వానం';

  @override
  String get settingsTitle => 'సెట్టింగ్లు';

  @override
  String get signInTitle => 'సైన్ ఇన్';

  @override
  String get signUpTitle => 'సైన్ అప్';

  @override
  String get onboardingTitle1 => 'మీ కుటుంబం, మీ కథ';

  @override
  String get onboardingBody1 =>
      'Kinrel మీ కుటుంబంలోని ప్రతి సంబంధాన్ని మ్యాప్ చేస్తుంది — మీ తాతల నుండి మీ మనవరాళ్ళ వరకు, మీరు పెరిగిన భాషలో।';

  @override
  String get onboardingTitle2 => 'ఇంటి వాసన ఉన్న పేర్లు';

  @override
  String get onboardingBody2 =>
      'కేవలం \'అంకుల్\' మరియు \'ఆంటీ\' మాత్రమే కాదు — Kinrel మీ బాబాయి, మామయ్య, పిన్ని మరియు పెద్దన్నల మధ్య తేడాను తెలుసుకోగలదు।';

  @override
  String get onboardingTitle3 => 'పెద్ద చిత్రం చూడండి';

  @override
  String get onboardingBody3 =>
      'మీ మొత్తం కుటుంబం ఒక అందమైన, ఇంటరాక్టివ్ గ్రాఫ్ వలె. జూమ్ ఇన్ చేయండి, సంబంధాలను అన్వేషించండి, మీకు తెలియని సంబంధాలను కనుగొనండి।';

  @override
  String get onboardingTitle4 => 'ఏ సంబంధాన్నైనా వెంటనే కనుగొనండి';

  @override
  String get onboardingBody4 =>
      'కుటుంబంలోని ఏ ఇద్దరు సభ్యులనైనా ఎంచుకోండి — Kinrel AI మీ భాషలో సరైన సంబంధం పేరును గణిస్తుంది।';

  @override
  String get addMember => 'సభ్యుడిని జోడించు';

  @override
  String get shareFamily => 'కుటుంబాన్ని షేర్ చేయండి';

  @override
  String get findPath => 'మార్గం కనుగొనండి';

  @override
  String get viewFullGraph => 'పూర్తి గ్రాఫ్ చూడండి';

  @override
  String get recentActivity => 'ఇటీవలి కార్యకలాపం';

  @override
  String get familyInsights => 'కుటుంబం ఒక్క చూపులో';

  @override
  String get noNotifications => 'అంతా పూర్తి! కొత్త నోటిఫికేషన్లు లేవు।';

  @override
  String get noEvents =>
      'ఇంకా కార్యక్రమాలు లేవు. మీ కుటుంబ పుట్టినరోజులు మరియు వార్షికోత్సవాలు ఇక్కడ స్వయంచాలకంగా కనిపిస్తాయి।';

  @override
  String get noMemories =>
      'ఇంకా జ్ఞాపకాలు లేవు. మీ మొదటి పారివారిక జ్ఞాపకాన్ని జోడించి ప్రారంభించండి।';

  @override
  String get noDocuments =>
      'ఇంకా పత్రాలు లేవు. మీ కుటుంబ ముఖ్యమైన పత్రాలను సురక్షితంగా నిల్వ చేయండి।';

  @override
  String get createFamily => 'కుటుంబాన్ని సృష్టించండి';

  @override
  String get joinFamily => 'కుటుంబంలో చేరండి';

  @override
  String get searchHint => 'సంబంధాలు వెతకండి';

  @override
  String birthdayTomorrow(String name) {
    return '$name పుట్టినరోజు రేపు!';
  }

  @override
  String anniversarySoon(String name, String name2, int days) {
    return '$name మరియు $name2 వార్షికోత్సవం $days రోజుల్లో!';
  }

  @override
  String get sendWishes => 'శుభాకాంక్షలు పంపాలా?';

  @override
  String streakDays(int count) {
    return '$count రోజుల క్రమం';
  }

  @override
  String profileCompletion(int percent) {
    return '$percent% పూర్తి';
  }

  @override
  String treeCompleteness(int percent) {
    return 'మీ వంశవృక్షం $percent% పూర్తయింది';
  }

  @override
  String get encryptNotice => 'AES-256తో ఎన్క్రిప్ట్ చేయబడింది';

  @override
  String get generatedByKinrel => 'Kinrel ద్వారా రూపొందించబడింది';

  @override
  String get madeByDaxelo => 'Daxelo ప్రేమతో తయారుచేసింది';

  @override
  String get welcomeBack => 'తిరిగి స్వాగతం';

  @override
  String get goodMorning => 'శుభోదయం';

  @override
  String get goodAfternoon => 'శుభ మధ్యాహ్నం';

  @override
  String get goodEvening => 'శుభ సాయంత్రం';

  @override
  String get goodNight => 'శుభ రాత్రి';

  @override
  String get languageName => 'తెలుగు';
}
