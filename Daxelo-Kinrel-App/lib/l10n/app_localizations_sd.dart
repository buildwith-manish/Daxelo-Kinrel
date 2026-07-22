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
  String get familyMapControlLocate => 'Locate me';

  @override
  String get familyMapControlZoomIn => 'Zoom in';

  @override
  String get familyMapControlZoomOut => 'Zoom out';

  @override
  String get familyMapControlLayers => 'Layers';

  @override
  String get familyMapControlDarkMode => 'Dark map';

  @override
  String get familyMapControlLightMode => 'Light map';

  @override
  String get familyMapLocateServiceOff => 'Location services are off.';

  @override
  String get familyMapLocatePermissionDenied => 'Location permission denied.';

  @override
  String get familyMapLocateFailed => 'Could not get your current location.';

  @override
  String get familyMapLayersTitle => 'Map layers';

  @override
  String get familyMapLayersDone => 'Done';

  @override
  String get familyMapLayerHomes => 'Family homes';

  @override
  String get familyMapLayerWeddings => 'Wedding venues';

  @override
  String get familyMapLayerMemorials => 'Memorials';

  @override
  String get familyMapLayerSchools => 'Schools';

  @override
  String get familyMapLayerPlaces => 'Important places';

  @override
  String get familyMapLayerRelationships => 'Relationship paths';

  @override
  String get familyMapLayerCallouts => 'Place labels';

  @override
  String get familyMapLayerLivePulses => 'Live pulses';

  @override
  String get familyMapSearchHint => 'Search city or family member';

  @override
  String get familyMapSearchCollapsed => 'Search city or family member';

  @override
  String get familyMapSearchClear => 'Clear';

  @override
  String get familyMapSearchCityHint => 'City';

  @override
  String get familyMapLegendPinned => 'located';

  @override
  String get familyMapLegendCities => 'cities';

  @override
  String get familyMapLegendStatusTitle => 'Status tiers';

  @override
  String get familyMapLegendCategoriesTitle => 'Place categories';

  @override
  String get familyMapLegendUnpinnedTitle => 'Not on map';

  @override
  String get familyMapLegendTierLive => 'Live';

  @override
  String get familyMapLegendTierLiveDesc => '< 2 min ago';

  @override
  String get familyMapLegendTierRecent => 'Recent';

  @override
  String get familyMapLegendTierRecentDesc => '< 15 min ago';

  @override
  String get familyMapLegendTierStale => 'Stale';

  @override
  String get familyMapLegendTierStaleDesc => '< 1 hour ago';

  @override
  String get familyMapLegendTierCity => 'City';

  @override
  String get familyMapLegendTierCityDesc => 'city centroid';
}
