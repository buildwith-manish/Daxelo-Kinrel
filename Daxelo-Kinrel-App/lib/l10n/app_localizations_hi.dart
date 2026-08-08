// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Hindi (`hi`).
class SHi extends S {
  SHi([String locale = 'hi']) : super(locale);

  @override
  String get appName => 'Kinrel';

  @override
  String get appTagline => 'AI के साथ अपने परिवार का मानचित्र बनाएं';

  @override
  String get homeTitle => 'होम';

  @override
  String get kinshipTitle => 'रिश्ते';

  @override
  String get graphTitle => 'ग्राफ';

  @override
  String get alertsTitle => 'अलर्ट';

  @override
  String get profileTitle => 'मैं';

  @override
  String get notificationsTitle => 'सूचनाएं';

  @override
  String get eventsTitle => 'कार्यक्रम और उत्सव';

  @override
  String get memoriesTitle => 'यादें और समयरेखा';

  @override
  String get chatTitle => 'पारिवारिक चैट';

  @override
  String get documentsTitle => 'दस्तावेज़ वॉल्ट';

  @override
  String get achievementsTitle => 'उपलब्धियां';

  @override
  String get shareTitle => 'शेयर और आमंत्रण';

  @override
  String get settingsTitle => 'सेटिंग्स';

  @override
  String get signInTitle => 'साइन इन करें';

  @override
  String get signUpTitle => 'साइन अप करें';

  @override
  String get onboardingTitle1 => 'आपका परिवार, आपकी कहानी';

  @override
  String get onboardingBody1 =>
      'Kinrel आपके परिवार के हर रिश्ते को मैप करता है — आपके दादा-दादी से लेकर आपके पोते-पोतियों तक, उस भाषा में जिसमें आपने पले-बढ़े हैं।';

  @override
  String get onboardingTitle2 => 'वे नाम जो घर जैसा लगें';

  @override
  String get onboardingBody2 =>
      'सिर्फ \'अंकल\' और \'आंटी\' नहीं — Kinrel आपके चाचा, मामा, फूफा और ताऊजी के बीच का अंतर जानता है।';

  @override
  String get onboardingTitle3 => 'पूरी तस्वीर देखें';

  @override
  String get onboardingBody3 =>
      'आपका पूरा परिवार एक सुंदर, इंटरैक्टिव ग्राफ के रूप में। ज़ूम इन करें, कनेक्शन एक्सप्लोर करें, वो रिश्ते खोजें जिनके बारे में आपको पता ही नहीं था।';

  @override
  String get onboardingTitle4 => 'कोई भी रिश्ता तुरंत खोजें';

  @override
  String get onboardingBody4 =>
      'परिवार के किन्हीं दो सदस्यों को चुनें — Kinrel का AI आपकी भाषा में सटीक रिश्ते का नाम बताएगा।';

  @override
  String get addMember => 'सदस्य जोड़ें';

  @override
  String get shareFamily => 'परिवार शेयर करें';

  @override
  String get findPath => 'रास्ता खोजें';

  @override
  String get viewFullGraph => 'पूरा ग्राफ देखें';

  @override
  String get recentActivity => 'हाल की गतिविधि';

  @override
  String get familyInsights => 'परिवार एक नज़र में';

  @override
  String get noNotifications => 'सब पक्का! कोई नई सूचना नहीं।';

  @override
  String get noEvents =>
      'अभी कोई कार्यक्रम नहीं। आपके परिवार के जन्मदिन और सालगिरह यहां स्वचालित रूप से दिखेंगे।';

  @override
  String get noMemories =>
      'अभी कोई याद नहीं। अपनी पहली पारिवारिक याद जोड़कर शुरू करें।';

  @override
  String get noDocuments =>
      'अभी कोई दस्तावेज़ नहीं। अपने परिवार के महत्वपूर्ण दस्तावेज़ सुरक्षित रूप से संग्रहित करें।';

  @override
  String get createFamily => 'परिवार बनाएं';

  @override
  String get joinFamily => 'परिवार में शामिल हों';

  @override
  String get searchHint => 'रिश्ते खोजें';

  @override
  String birthdayTomorrow(String name) {
    return '$name का जन्मदिन कल है!';
  }

  @override
  String anniversarySoon(String name, String name2, int days) {
    return '$name और $name2 की सालगिरह $days दिन में है!';
  }

  @override
  String get sendWishes => 'शुभकामनाएं भेजें?';

  @override
  String streakDays(int count) {
    return '$count दिन का सिलसिला';
  }

  @override
  String profileCompletion(int percent) {
    return '$percent% पूर्ण';
  }

  @override
  String treeCompleteness(int percent) {
    return 'आपका पेड़ $percent% पूरा है';
  }

  @override
  String get encryptNotice => 'AES-256 से एन्क्रिप्टेड';

  @override
  String get generatedByKinrel => 'Kinrel द्वारा बनाया गया';

  @override
  String get madeByDaxelo => 'Daxelo द्वारा प्रेम से बनाया गया';

  @override
  String get welcomeBack => 'वापस स्वागत है';

  @override
  String get goodMorning => 'सुप्रभात';

  @override
  String get goodAfternoon => 'शुभ दोपहर';

  @override
  String get goodEvening => 'शुभ संध्या';

  @override
  String get goodNight => 'शुभ रात्रि';

  @override
  String get languageName => 'हिन्दी';

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
  String get familyMapControlLocate => 'मेरा स्थान खोजें';

  @override
  String get familyMapControlZoomIn => 'ज़ूम इन';

  @override
  String get familyMapControlZoomOut => 'ज़ूम आउट';

  @override
  String get familyMapControlLayers => 'परतें';

  @override
  String get familyMapControlDarkMode => 'डार्क मैप';

  @override
  String get familyMapControlLightMode => 'लाइट मैप';

  @override
  String get familyMapControl3DBuildingsOn => 'Turn on 3D buildings';

  @override
  String get familyMapControl3DBuildingsOff => 'Turn off 3D buildings';

  @override
  String get familyMapLocateServiceOff => 'लोकेशन सेवाएं बंद हैं।';

  @override
  String get familyMapLocatePermissionDenied => 'लोकेशन अनुमति अस्वीकृत।';

  @override
  String get familyMapLocateFailed => 'आपका वर्तमान स्थान नहीं मिल सका।';

  @override
  String get familyMapLayersTitle => 'मैप परतें';

  @override
  String get familyMapLayersDone => 'पूर्ण';

  @override
  String get familyMapLayerHomes => 'पारिवारिक घर';

  @override
  String get familyMapLayerWeddings => 'विवाह स्थल';

  @override
  String get familyMapLayerMemorials => 'स्मारक';

  @override
  String get familyMapLayerSchools => 'स्कूल';

  @override
  String get familyMapLayerPlaces => 'महत्वपूर्ण स्थान';

  @override
  String get familyMapLayerRelationships => 'रिश्ते पथ';

  @override
  String get familyMapLayerCallouts => 'स्थान लेबल';

  @override
  String get familyMapLayerLivePulses => 'लाइव स्पंदन';

  @override
  String get familyMapSearchHint => 'शहर या परिवार के सदस्य को खोजें';

  @override
  String get familyMapSearchCollapsed => 'शहर या परिवार के सदस्य को खोजें';

  @override
  String get familyMapSearchClear => 'साफ़ करें';

  @override
  String get familyMapSearchCityHint => 'शहर';

  @override
  String get familyMapLegendPinned => 'स्थित';

  @override
  String get familyMapLegendCities => 'शहर';

  @override
  String get familyMapLegendStatusTitle => 'स्थिति स्तर';

  @override
  String get familyMapLegendCategoriesTitle => 'स्थान श्रेणियाँ';

  @override
  String get familyMapLegendUnpinnedTitle => 'मैप पर नहीं';

  @override
  String get familyMapLegendTierLive => 'लाइव';

  @override
  String get familyMapLegendTierLiveDesc => '< 2 मिनट पहले';

  @override
  String get familyMapLegendTierRecent => 'हाल का';

  @override
  String get familyMapLegendTierRecentDesc => '< 15 मिनट पहले';

  @override
  String get familyMapLegendTierStale => 'पुराना';

  @override
  String get familyMapLegendTierStaleDesc => '< 1 घंटे पहले';

  @override
  String get familyMapLegendTierCity => 'शहर';

  @override
  String get familyMapLegendTierCityDesc => 'शहर केंद्र';
}
