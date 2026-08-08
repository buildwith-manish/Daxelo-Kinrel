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

  @override
  String get kinrelNavLabel => 'Kinrel';

  @override
  String get kinrelScreenTitle => 'Kinrel';

  @override
  String get kinrelEmptyTitle => 'Kinrel has not been computed yet';

  @override
  String get kinrelEmptyBody =>
      'Kinrel analyses your family graph to generate a unique symbol and archetype. This usually takes a few seconds.';

  @override
  String get kinrelGenerateButton => 'Generate Kinrel';

  @override
  String get kinrelRecomputeButton => 'Recompute';

  @override
  String get kinrelLoadingTitle => 'Computing Kinrel…';

  @override
  String get kinrelCachedBanner => 'Showing cached Kinrel — offline mode';

  @override
  String get kinrelErrorTitle => 'Could not load Kinrel';

  @override
  String get kinrelShareTooltip => 'Share Kinrel';

  @override
  String kinrelShareText(String familyName) {
    return 'Our family\'s Kinrel — $familyName';
  }

  @override
  String get kinrelTimelineTitle => 'Kinrel Timeline';

  @override
  String get kinrelTimelineEmptyTitle => 'No Kinrel history yet';

  @override
  String get kinrelTimelineEmptyBody =>
      'As your family grows, snapshots of how the Kinrel evolved will appear here.';

  @override
  String kinrelMemberCountCaption(int count) {
    return '$count members';
  }

  @override
  String kinrelConfidenceLabel(int percent) {
    return '$percent% match';
  }

  @override
  String get kinrelFeatureDisabled => 'Kinrel is not available.';

  @override
  String get familyMapLoading => 'Loading family map…';

  @override
  String get familyMapEmptyTitle => 'No family locations yet';

  @override
  String get familyMapEmptyBody =>
      'Add a location to a family member to see your family across the map.';

  @override
  String get familyMapFailedTitle => 'Couldn\'t load the family map';

  @override
  String get familyMapFailedBody => 'Check your connection and try again.';

  @override
  String get familyMapRetry => 'Retry';

  @override
  String familyMapLocatedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 's',
      one: '',
    );
    return '$count member$_temp0 located';
  }

  @override
  String get familyMapTitle => 'Family Map';

  @override
  String get familyMapNoJourney =>
      'No journey data for this family member yet.';

  @override
  String familyMapHouseholdMembers(int count) {
    return 'Household — $count members';
  }

  @override
  String get familyMapViewProfile => 'View Profile';

  @override
  String familyMapUnpinnedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 's',
      one: '',
    );
    return '$count member$_temp0 without map pin';
  }

  @override
  String get familyMapAddCityPrompt =>
      'Add a city to these members to see them on the map.';

  @override
  String get familyMapNoCitySet => 'No city set';

  @override
  String familyMapCityNotFound(String city) {
    return '$city (not found)';
  }

  @override
  String familyMapPinned(int count) {
    return '$count pinned';
  }

  @override
  String familyMapNotPinned(int count) {
    return '$count not pinned';
  }

  @override
  String get familyMapCouldNotLoad => 'Could Not Load Map';

  @override
  String get familyMapErrorBody =>
      'Something went wrong while loading the family map. Please try again.';

  @override
  String get familyMapLinkedMember => 'Linked family member';

  @override
  String get familyMapMemories => 'Memories';

  @override
  String get familyMapClose => 'Close';

  @override
  String get familyMapBack => 'Back';

  @override
  String get familyMapTest3dBengaluru => 'Test 3D: Bengaluru';

  @override
  String get familyMapFlyToBengaluruSnackbar =>
      'Flying to Bengaluru — 3D buildings should appear at this zoom level';

  @override
  String get familyMapFamilyMember => 'Family Member';

  @override
  String familyMapViewMember(String name) {
    return 'View $name';
  }

  @override
  String familyMapHouseholdClusterLabel(int count) {
    return 'Household with $count members. Double-tap to expand.';
  }

  @override
  String familyMapTimelineLabel(int year) {
    return 'Family timeline. Currently viewing $year. Drag to change.';
  }

  @override
  String get familyMapTimelinePreviousYear => 'Previous year';

  @override
  String get familyMapTimelineNextYear => 'Next year';

  @override
  String get familyMapTimelinePlay => 'Play timeline';

  @override
  String get familyMapTimelinePause => 'Pause timeline';

  @override
  String familyMapTimelineRange(int min, int max) {
    return '$min–$max';
  }

  @override
  String get familyMapJourneyTitle => 'Family Journey';

  @override
  String get familyMapJourneyBorn => 'Born';

  @override
  String get familyMapJourneyPrevious => 'Previous stop';

  @override
  String get familyMapJourneyNext => 'Next stop';

  @override
  String get familyMapJourneyPlay => 'Play journey';

  @override
  String get familyMapJourneyPause => 'Pause journey';

  @override
  String get familyMapJourneyClose => 'Close journey';

  @override
  String familyMapAvatarPinLabel(String name, String tier) {
    return '$name$tier. Double-tap to focus.';
  }

  @override
  String get familyMapAvatarSelectedSuffix => 'Selected.';

  @override
  String get familyMapAvatarDoubleTapFocus => 'Double-tap to focus.';

  @override
  String get familyMapTierLive => 'Live • now';

  @override
  String get familyMapTierUpdatedRecently => 'Updated recently';

  @override
  String get familyMapTierUpdatedJustNow => 'Updated just now';

  @override
  String familyMapTierUpdatedMinsAgo(int mins) {
    return 'Updated ${mins}m ago';
  }

  @override
  String get familyMapTierLastKnown => 'Last known';

  @override
  String get familyMapProgressOffline => 'Offline — showing cached data';

  @override
  String get familyMapProgressRestoring => 'Restoring your view…';

  @override
  String get familyMapProgressMap => 'Loading map…';

  @override
  String get familyMapProgressLandmarks => 'Loading landmarks…';

  @override
  String get familyMapProgressFamilyPlaces => 'Loading family places…';

  @override
  String get familyMapProgressConnections => 'Loading connections…';

  @override
  String get familyMapProgressMembers => 'Loading family members…';

  @override
  String get familyMapProgressAlmost => 'Almost there…';

  @override
  String get familyMapControlLocate => 'माझे स्थान शोधा';

  @override
  String get familyMapControlZoomIn => 'झूम इन';

  @override
  String get familyMapControlZoomOut => 'झूम आउट';

  @override
  String get familyMapControlLayers => 'स्तर';

  @override
  String get familyMapControlDarkMode => 'डार्क नकाशा';

  @override
  String get familyMapControlLightMode => 'लाइट नकाशा';

  @override
  String get familyMapControl3DBuildingsOn => 'Turn on 3D buildings';

  @override
  String get familyMapControl3DBuildingsOff => 'Turn off 3D buildings';

  @override
  String get familyMapLocateServiceOff => 'स्थान सेवा बंद आहेत.';

  @override
  String get familyMapLocatePermissionDenied => 'स्थान परवानगी नकारली.';

  @override
  String get familyMapLocateFailed => 'तुमचे वर्तमान स्थान मिळाले नाही.';

  @override
  String get familyMapLayersTitle => 'नकाशा स्तर';

  @override
  String get familyMapLayersDone => 'पूर्ण';

  @override
  String get familyMapLayerHomes => 'कौटुंबिक घरे';

  @override
  String get familyMapLayerWeddings => 'विवाह स्थळे';

  @override
  String get familyMapLayerMemorials => 'स्मारके';

  @override
  String get familyMapLayerSchools => 'शाळा';

  @override
  String get familyMapLayerPlaces => 'महत्त्वाची ठिकाणे';

  @override
  String get familyMapLayerRelationships => 'नाती मार्ग';

  @override
  String get familyMapLayerCallouts => 'स्थान लेबल';

  @override
  String get familyMapLayerLivePulses => 'थेट स्पंदन';

  @override
  String get familyMapSearchHint => 'शहर किंवा कुटुंब सदस्य शोधा';

  @override
  String get familyMapSearchCollapsed => 'शहर किंवा कुटुंब सदस्य शोधा';

  @override
  String get familyMapSearchClear => 'साफ करा';

  @override
  String get familyMapSearchCityHint => 'शहर';

  @override
  String get familyMapLegendPinned => 'स्थित';

  @override
  String get familyMapLegendCities => 'शहरे';

  @override
  String get familyMapLegendStatusTitle => 'स्थिती स्तर';

  @override
  String get familyMapLegendCategoriesTitle => 'स्थान श्रेणी';

  @override
  String get familyMapLegendUnpinnedTitle => 'नकाशावर नाही';

  @override
  String get familyMapLegendTierLive => 'थेट';

  @override
  String get familyMapLegendTierLiveDesc => '< 2 मिनिटे आधी';

  @override
  String get familyMapLegendTierRecent => 'अलीकडील';

  @override
  String get familyMapLegendTierRecentDesc => '< 15 मिनिटे आधी';

  @override
  String get familyMapLegendTierStale => 'जुने';

  @override
  String get familyMapLegendTierStaleDesc => '< 1 तास आधी';

  @override
  String get familyMapLegendTierCity => 'शहर';

  @override
  String get familyMapLegendTierCityDesc => 'शहर केंद्र';
}
