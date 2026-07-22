// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Sanskrit (`sa`).
class SSa extends S {
  SSa([String locale = 'sa']) : super(locale);

  @override
  String get appName => 'Kinrel';

  @override
  String get appTagline =>
      'कृत्रिमबुद्ध्या सह तव कुटुम्बस्य मानचित्रं निर्मायताम्';

  @override
  String get homeTitle => 'गृहम्';

  @override
  String get kinshipTitle => 'बन्धाः';

  @override
  String get graphTitle => 'आलेखः';

  @override
  String get alertsTitle => 'सचेतनाः';

  @override
  String get profileTitle => 'अहम्';

  @override
  String get notificationsTitle => 'सूचनाः';

  @override
  String get eventsTitle => 'उत्सवाः च समारोहाः';

  @override
  String get memoriesTitle => 'स्मृतयः च कालरेखा';

  @override
  String get chatTitle => 'कुटुम्बसंवादः';

  @override
  String get documentsTitle => 'लेखागारम्';

  @override
  String get achievementsTitle => 'सिद्धयः';

  @override
  String get shareTitle => 'साझां कुरु च आमन्त्रय';

  @override
  String get settingsTitle => 'विन्यासाः';

  @override
  String get signInTitle => 'प्रवेशः';

  @override
  String get signUpTitle => 'पञ्जीकरणम्';

  @override
  String get onboardingTitle1 => 'तव कुटुम्बम्, तव कथा';

  @override
  String get onboardingBody1 =>
      'Kinrel तव कुटुम्बस्य प्रत्येकं बन्धं मानचित्रयति — तव पितामह-पितामह्याः तव दौहित्र-दौहित्रीपर्यन्तं, यस्यां भाषायां त्वं वर्धितवान्।';

  @override
  String get onboardingTitle2 => 'नामानि यानि गृहमिव अनुभूयन्ते';

  @override
  String get onboardingBody2 =>
      'केवलम् \'अङ्कल्\' \'आण्टि\' च न — Kinrel तव पितृव्य, मातुल, भ्रातृजाया, पितामहस्य ज्येष्ठभ्रातुः च मध्ये भेदं जानाति।';

  @override
  String get onboardingTitle3 => 'बृहच्चित्रं पश्य';

  @override
  String get onboardingBody3 =>
      'तव सम्पूर्णं कुटुम्बम् एकस्मिन् सुन्दरे, परस्परक्रियाशीले आलेखे इव। समीपं गच्छ, सम्बन्धान् अन्विष्य, ये बन्धाः त्वया न ज्ञाताः तान् आविष्कुरु।';

  @override
  String get onboardingTitle4 => 'कोऽपि बन्धः तत्क्षणं अन्विष्यताम्';

  @override
  String get onboardingBody4 =>
      'कुटुम्बस्य कस्यापि द्वौ सदस्यौ चिनो — Kinrel कृत्रिमबुद्धिः तव भाषायां शुद्धं बन्धनाम गणयिष्यति।';

  @override
  String get addMember => 'सदस्यं योजय';

  @override
  String get shareFamily => 'कुटुम्बं साझां कुरु';

  @override
  String get findPath => 'मार्गम् अन्विष्य';

  @override
  String get viewFullGraph => 'सम्पूर्णम् आलेखं पश्य';

  @override
  String get recentActivity => 'अद्यतनक्रियाकलापः';

  @override
  String get familyInsights => 'कुटुम्बम् एकदृष्ट्या';

  @override
  String get noNotifications => 'सर्वं क्षेमम्! नवीनाः सूचनाः न सन्ति।';

  @override
  String get noEvents =>
      'अद्यापि कोऽपि उत्सवः नास्ति। तव कुटुम्बस्य जन्मदिवसाः वार्षिकीच अत्र स्वयमेव दृश्यन्ते।';

  @override
  String get noMemories =>
      'अद्यापि स्मृतयः न सन्ति। तव प्रथमां कुटुम्बस्मृतिं योजयित्वा आरभस्व।';

  @override
  String get noDocuments =>
      'अद्यापि लेखाः न सन्ति। तव कुटुम्बस्य महत्त्वपूर्णान् लेखान् सुरक्षितं स्थापय।';

  @override
  String get createFamily => 'कुटुम्बं सृज';

  @override
  String get joinFamily => 'कुटुम्बे सम्मिल';

  @override
  String get searchHint => 'बन्धान् अन्विष्य';

  @override
  String birthdayTomorrow(String name) {
    return '$name इत्यस्य जन्मदिवसः श्वः!';
  }

  @override
  String anniversarySoon(String name, String name2, int days) {
    return '$name तथा $name2 इत्येतयोः वार्षिकी $days दिनेषु!';
  }

  @override
  String get sendWishes => 'शुभाशंसाः प्रेष्यन्ते?';

  @override
  String streakDays(int count) {
    return '$count दिनानां शृङ्खला';
  }

  @override
  String profileCompletion(int percent) {
    return '$percent% सम्पूर्णम्';
  }

  @override
  String treeCompleteness(int percent) {
    return 'तव वृक्षः $percent% सम्पूर्णः';
  }

  @override
  String get encryptNotice => 'AES-256 इत्यनेन गोपितम्';

  @override
  String get generatedByKinrel => 'Kinrel द्वारा निर्मितम्';

  @override
  String get madeByDaxelo => 'Daxelo प्रेम्णा निर्मितम्';

  @override
  String get welcomeBack => 'पुनः स्वागतम्';

  @override
  String get goodMorning => 'सुप्रभातम्';

  @override
  String get goodAfternoon => 'शुभ मध्याह्नः';

  @override
  String get goodEvening => 'शुभ सन्ध्या';

  @override
  String get goodNight => 'शुभ रात्रिः';

  @override
  String get languageName => 'संस्कृतम्';

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
  String get familyMapControlLocate => 'मम स्थानं अन्विष्यताम्';

  @override
  String get familyMapControlZoomIn => 'समीपं गच्छतु';

  @override
  String get familyMapControlZoomOut => 'दूरं गच्छतु';

  @override
  String get familyMapControlLayers => 'स्तराः';

  @override
  String get familyMapControlDarkMode => 'गभीरः नक्शः';

  @override
  String get familyMapControlLightMode => 'लघुः नक्शः';

  @override
  String get familyMapLocateServiceOff => 'स्थानसेवाः निष्क्रियाः सन्ति।';

  @override
  String get familyMapLocatePermissionDenied => 'स्थानानुमतिः अस्वीकृता।';

  @override
  String get familyMapLocateFailed => 'भवतः वर्तमानस्थानं न प्राप्तम्।';

  @override
  String get familyMapLayersTitle => 'नक्शस्तराः';

  @override
  String get familyMapLayersDone => 'सम्पन्नम्';

  @override
  String get familyMapLayerHomes => 'कुटुम्बगृहाणि';

  @override
  String get familyMapLayerWeddings => 'विवाहस्थलानि';

  @override
  String get familyMapLayerMemorials => 'स्मारकाणि';

  @override
  String get familyMapLayerSchools => 'विद्यालयाः';

  @override
  String get familyMapLayerPlaces => 'महत्त्वपूर्णस्थलानि';

  @override
  String get familyMapLayerRelationships => 'सम्बन्धमार्गाः';

  @override
  String get familyMapLayerCallouts => 'स्थानलेबल्स्';

  @override
  String get familyMapLayerLivePulses => 'प्रत्यक्षस्पन्दनम्';

  @override
  String get familyMapSearchHint => 'नगरं वा कुटुम्बसदस्यं अन्विष्यताम्';

  @override
  String get familyMapSearchCollapsed => 'नगरं वा कुटुम्बसदस्यं अन्विष्यताम्';

  @override
  String get familyMapSearchClear => 'माञ्जयतु';

  @override
  String get familyMapSearchCityHint => 'नगरम्';

  @override
  String get familyMapLegendPinned => 'स्थितम्';

  @override
  String get familyMapLegendCities => 'नगराणि';

  @override
  String get familyMapLegendStatusTitle => 'स्थितिस्तराः';

  @override
  String get familyMapLegendCategoriesTitle => 'स्थानवर्गाः';

  @override
  String get familyMapLegendUnpinnedTitle => 'नक्शे नास्ति';

  @override
  String get familyMapLegendTierLive => 'प्रत्यक्षम्';

  @override
  String get familyMapLegendTierLiveDesc => '< २ निमेषपूर्वम्';

  @override
  String get familyMapLegendTierRecent => 'आसन्नम्';

  @override
  String get familyMapLegendTierRecentDesc => '< १५ निमेषपूर्वम्';

  @override
  String get familyMapLegendTierStale => 'पुरातनम्';

  @override
  String get familyMapLegendTierStaleDesc => '< १ घटिकापूर्वम्';

  @override
  String get familyMapLegendTierCity => 'नगरम्';

  @override
  String get familyMapLegendTierCityDesc => 'नगरकेन्द्रम्';
}
