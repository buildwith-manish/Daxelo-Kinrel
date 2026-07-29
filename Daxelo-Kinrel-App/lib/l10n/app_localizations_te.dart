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

  // ── P13 — Control stack + search + legend (en baseline — translate later)
  @override
  String get familyMapControlLocate => 'నా స్థానాన్ని కనుగొను';

  @override
  String get familyMapControlZoomIn => 'జూమ్ ఇన్';

  @override
  String get familyMapControlZoomOut => 'జూమ్ అవుట్';

  @override
  String get familyMapControlLayers => 'పొరలు';

  @override
  String get familyMapControlDarkMode => 'డార్క్ మ్యాప్';

  @override
  String get familyMapControlLightMode => 'లైట్ మ్యాప్';

  @override
  String get familyMapControl3DBuildingsOn => 'Turn on 3D buildings';

  @override
  String get familyMapControl3DBuildingsOff => 'Turn off 3D buildings';

  @override
  String get familyMapLocateServiceOff => 'స్థాన సేవలు ఆఫ్‌లో ఉన్నాయి.';

  @override
  String get familyMapLocatePermissionDenied => 'స్థాన అనుమతి తిరస్కరించబడింది.';

  @override
  String get familyMapLocateFailed => 'మీ ప్రస్తుత స్థానం పొందడం సాధ్యం కాలేదు.';

  @override
  String get familyMapLayersTitle => 'మ్యాప్ పొరలు';

  @override
  String get familyMapLayersDone => 'పూర్తయింది';

  @override
  String get familyMapLayerHomes => 'కుటుంబ ఇళ్లు';

  @override
  String get familyMapLayerWeddings => 'వివాహ స్థలాలు';

  @override
  String get familyMapLayerMemorials => 'స్మారక చిహ్నాలు';

  @override
  String get familyMapLayerSchools => 'పాఠశాలలు';

  @override
  String get familyMapLayerPlaces => 'ముఖ్యమైన స్థలాలు';

  @override
  String get familyMapLayerRelationships => 'సంబంధ మార్గాలు';

  @override
  String get familyMapLayerCallouts => 'స్థల లేబుల్‌లు';

  @override
  String get familyMapLayerLivePulses => 'ప్రత్యక్ష స్పందన';

  @override
  String get familyMapSearchHint => 'నగరం లేదా కుటుంబ సభ్యుడిని వెతకండి';

  @override
  String get familyMapSearchCollapsed => 'నగరం లేదా కుటుంబ సభ్యుడిని వెతకండి';

  @override
  String get familyMapSearchClear => 'క్లియర్';

  @override
  String get familyMapSearchCityHint => 'నగరం';

  @override
  String get familyMapLegendPinned => 'ఉన్నాయి';

  @override
  String get familyMapLegendCities => 'నగరాలు';

  @override
  String get familyMapLegendStatusTitle => 'స్థితి స్థాయిలు';

  @override
  String get familyMapLegendCategoriesTitle => 'స్థల వర్గాలు';

  @override
  String get familyMapLegendUnpinnedTitle => 'మ్యాప్‌లో లేవు';

  @override
  String get familyMapLegendTierLive => 'ప్రత్యక్ష';

  @override
  String get familyMapLegendTierLiveDesc => '< 2 నిమిషాల క్రితం';

  @override
  String get familyMapLegendTierRecent => 'ఇటీవలి';

  @override
  String get familyMapLegendTierRecentDesc => '< 15 నిమిషాల క్రితం';

  @override
  String get familyMapLegendTierStale => 'పాత';

  @override
  String get familyMapLegendTierStaleDesc => '< 1 గంట క్రితం';

  @override
  String get familyMapLegendTierCity => 'నగరం';

  @override
  String get familyMapLegendTierCityDesc => 'నగర కేంద్రం';
}
