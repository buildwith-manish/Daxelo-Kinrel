// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Bengali Bangla (`bn`).
class SBn extends S {
  SBn([String locale = 'bn']) : super(locale);

  @override
  String get appName => 'Kinrel';

  @override
  String get appTagline => 'AI দিয়ে আপনার পরিবারের মানচিত্র তৈরি করুন';

  @override
  String get homeTitle => 'হোম';

  @override
  String get kinshipTitle => 'সম্পর্ক';

  @override
  String get graphTitle => 'গ্রাফ';

  @override
  String get alertsTitle => 'সতর্কতা';

  @override
  String get profileTitle => 'আমি';

  @override
  String get notificationsTitle => 'বিজ্ঞপ্তি';

  @override
  String get eventsTitle => 'অনুষ্ঠান ও উৎসব';

  @override
  String get memoriesTitle => 'স্মৃতি ও সময়রেখা';

  @override
  String get chatTitle => 'পারিবারিক চ্যাট';

  @override
  String get documentsTitle => 'নথি ভল্ট';

  @override
  String get achievementsTitle => 'অর্জন';

  @override
  String get shareTitle => 'শেয়ার ও আমন্ত্রণ';

  @override
  String get settingsTitle => 'সেটিংস';

  @override
  String get signInTitle => 'সাইন ইন';

  @override
  String get signUpTitle => 'সাইন আপ';

  @override
  String get onboardingTitle1 => 'আপনার পরিবার, আপনার গল্প';

  @override
  String get onboardingBody1 =>
      'Kinrel আপনার পরিবারের প্রতিটি সম্পর্ক ম্যাপ করে — আপনার দাদা-দাদি থেকে আপনার নাতি-নাতনি পর্যন্ত, যে ভাষায় আপনি বেড়ে উঠেছেন।';

  @override
  String get onboardingTitle2 => 'নাম যা বাড়ির মতো মনে হয়';

  @override
  String get onboardingBody2 =>
      'শুধু \'আঙ্কেল\' এবং \'আন্টি\' নয় — Kinrel আপনার কাকা, মামা, ফুফা এবং জ্যাঠার মধ্যে পার্থক্য জানে।';

  @override
  String get onboardingTitle3 => 'বড় ছবিটি দেখুন';

  @override
  String get onboardingBody3 =>
      'আপনার পুরো পরিবার একটি সুন্দর, ইন্টারেক্টিভ গ্রাফ হিসেবে। জুম ইন করুন, সংযোগ অন্বেষণ করুন, এমন সম্পর্ক আবিষ্কার করুন যা আপনি জানতেন না।';

  @override
  String get onboardingTitle4 => 'যেকোনো সম্পর্ক তৎক্ষণাৎ খুঁজুন';

  @override
  String get onboardingBody4 =>
      'পরিবারের যেকোনো দুজন সদস্য নির্বাচন করুন — Kinrel-এর AI আপনার ভাষায় সঠিক সম্পর্কের নাম গণনা করবে।';

  @override
  String get addMember => 'সদস্য যোগ করুন';

  @override
  String get shareFamily => 'পরিবার শেয়ার করুন';

  @override
  String get findPath => 'পথ খুঁজুন';

  @override
  String get viewFullGraph => 'সম্পূর্ণ গ্রাফ দেখুন';

  @override
  String get recentActivity => 'সাম্প্রতিক কার্যকলাপ';

  @override
  String get familyInsights => 'পরিবার একনজরে';

  @override
  String get noNotifications => 'সব ঠিক আছে! কোনো নতুন বিজ্ঞপ্তি নেই।';

  @override
  String get noEvents =>
      'এখনো কোনো অনুষ্ঠান নেই। আপনার পরিবারের জন্মদিন ও বার্ষিকী এখানে স্বয়ংক্রিয়ভাবে দেখা যাবে।';

  @override
  String get noMemories =>
      'এখনো কোনো স্মৃতি নেই। আপনার প্রথম পারিবারিক স্মৃতি যোগ করে শুরু করুন।';

  @override
  String get noDocuments =>
      'এখনো কোনো নথি নেই। আপনার পরিবারের গুরুত্বপূর্ণ নথি নিরাপদে সংরক্ষণ করুন।';

  @override
  String get createFamily => 'পরিবার তৈরি করুন';

  @override
  String get joinFamily => 'পরিবারে যোগ দিন';

  @override
  String get searchHint => 'সম্পর্ক খুঁজুন';

  @override
  String birthdayTomorrow(String name) {
    return '$name-এর জন্মদিন আগামীকাল!';
  }

  @override
  String anniversarySoon(String name, String name2, int days) {
    return '$name ও $name2-এর বার্ষিকী $days দিনে!';
  }

  @override
  String get sendWishes => 'শুভেচ্ছা পাঠাবেন?';

  @override
  String streakDays(int count) {
    return '$count দিনের ধারা';
  }

  @override
  String profileCompletion(int percent) {
    return '$percent% সম্পন্ন';
  }

  @override
  String treeCompleteness(int percent) {
    return 'আপনার গাছ $percent% সম্পূর্ণ';
  }

  @override
  String get encryptNotice => 'AES-256 দিয়ে এনক্রিপ্টেড';

  @override
  String get generatedByKinrel => 'Kinrel দ্বারা তৈরি';

  @override
  String get madeByDaxelo => 'Daxelo-এর ভালোবাসায় তৈরি';

  @override
  String get welcomeBack => 'ফিরে স্বাগতম';

  @override
  String get goodMorning => 'সুপ্রভাত';

  @override
  String get goodAfternoon => 'শুভ দুপুর';

  @override
  String get goodEvening => 'শুভ সন্ধ্যা';

  @override
  String get goodNight => 'শুভ রাত্রি';

  @override
  String get languageName => 'বাংলা';

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
  String get familyMapControlLocate => 'আমার অবস্থান খুঁজুন';

  @override
  String get familyMapControlZoomIn => 'জুম ইন';

  @override
  String get familyMapControlZoomOut => 'জুম আউট';

  @override
  String get familyMapControlLayers => 'স্তর';

  @override
  String get familyMapControlDarkMode => 'ডার্ক ম্যাপ';

  @override
  String get familyMapControlLightMode => 'লাইট ম্যাপ';

  @override
  String get familyMapControl3DBuildingsOn => 'Turn on 3D buildings';

  @override
  String get familyMapControl3DBuildingsOff => 'Turn off 3D buildings';

  @override
  String get familyMapLocateServiceOff => 'লোকেশন পরিষেবা বন্ধ আছে।';

  @override
  String get familyMapLocatePermissionDenied => 'লোকেশন অনুমতি অস্বীকৃত।';

  @override
  String get familyMapLocateFailed => 'আপনার বর্তমান অবস্থান পাওয়া যায়নি।';

  @override
  String get familyMapLayersTitle => 'ম্যাপ স্তর';

  @override
  String get familyMapLayersDone => 'সম্পন্ন';

  @override
  String get familyMapLayerHomes => 'পারিবারিক বাড়ি';

  @override
  String get familyMapLayerWeddings => 'বিবাহ স্থল';

  @override
  String get familyMapLayerMemorials => 'স্মৃতিস্তম্ভ';

  @override
  String get familyMapLayerSchools => 'স্কুল';

  @override
  String get familyMapLayerPlaces => 'গুরুত্বপূর্ণ স্থান';

  @override
  String get familyMapLayerRelationships => 'সম্পর্ক পথ';

  @override
  String get familyMapLayerCallouts => 'স্থান লেবেল';

  @override
  String get familyMapLayerLivePulses => 'লাইভ স্পন্দন';

  @override
  String get familyMapSearchHint => 'শহর বা পরিবারের সদস্য খুঁজুন';

  @override
  String get familyMapSearchCollapsed => 'শহর বা পরিবারের সদস্য খুঁজুন';

  @override
  String get familyMapSearchClear => 'মুছুন';

  @override
  String get familyMapSearchCityHint => 'শহর';

  @override
  String get familyMapLegendPinned => 'অবস্থিত';

  @override
  String get familyMapLegendCities => 'শহর';

  @override
  String get familyMapLegendStatusTitle => 'স্থিতি স্তর';

  @override
  String get familyMapLegendCategoriesTitle => 'স্থান বিভাগ';

  @override
  String get familyMapLegendUnpinnedTitle => 'ম্যাপে নেই';

  @override
  String get familyMapLegendTierLive => 'লাইভ';

  @override
  String get familyMapLegendTierLiveDesc => '< ২ মিনিট আগে';

  @override
  String get familyMapLegendTierRecent => 'সাম্প্রতিক';

  @override
  String get familyMapLegendTierRecentDesc => '< ১৫ মিনিট আগে';

  @override
  String get familyMapLegendTierStale => 'পুরোনো';

  @override
  String get familyMapLegendTierStaleDesc => '< ১ ঘন্টা আগে';

  @override
  String get familyMapLegendTierCity => 'শহর';

  @override
  String get familyMapLegendTierCityDesc => 'শহর কেন্দ্র';
}
