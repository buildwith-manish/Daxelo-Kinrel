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
  String get familyMapControlLocate => 'میری جگہ تلاش کریں';

  @override
  String get familyMapControlZoomIn => 'زوم ان';

  @override
  String get familyMapControlZoomOut => 'زوم آؤٹ';

  @override
  String get familyMapControlLayers => 'تہیں';

  @override
  String get familyMapControlDarkMode => 'ڈارک نقشہ';

  @override
  String get familyMapControlLightMode => 'لائٹ نقشہ';

  @override
  String get familyMapLocateServiceOff => 'مقام کی خدمات بند ہیں۔';

  @override
  String get familyMapLocatePermissionDenied => 'مقام کی اجازت مسترد کر دی گئی۔';

  @override
  String get familyMapLocateFailed => 'آپ کا موجودہ مقام حاصل نہیں ہو سکا۔';

  @override
  String get familyMapLayersTitle => 'نقشہ تہیں';

  @override
  String get familyMapLayersDone => 'مکمل';

  @override
  String get familyMapLayerHomes => 'خاندانی گھر';

  @override
  String get familyMapLayerWeddings => 'شادی کے مقامات';

  @override
  String get familyMapLayerMemorials => 'یادگاریں';

  @override
  String get familyMapLayerSchools => 'اسکول';

  @override
  String get familyMapLayerPlaces => 'اہم مقامات';

  @override
  String get familyMapLayerRelationships => 'رشتہ راستے';

  @override
  String get familyMapLayerCallouts => 'مقام لیبل';

  @override
  String get familyMapLayerLivePulses => 'بروقت دھڑکن';

  @override
  String get familyMapSearchHint => 'شہر یا خاندان کے رکن کو تلاش کریں';

  @override
  String get familyMapSearchCollapsed => 'شہر یا خاندان کے رکن کو تلاش کریں';

  @override
  String get familyMapSearchClear => 'صاف کریں';

  @override
  String get familyMapSearchCityHint => 'شہر';

  @override
  String get familyMapLegendPinned => 'موجود';

  @override
  String get familyMapLegendCities => 'شہر';

  @override
  String get familyMapLegendStatusTitle => 'حالت کی سطحیں';

  @override
  String get familyMapLegendCategoriesTitle => 'مقام کی اقسام';

  @override
  String get familyMapLegendUnpinnedTitle => 'نقشے پر نہیں';

  @override
  String get familyMapLegendTierLive => 'بروقت';

  @override
  String get familyMapLegendTierLiveDesc => '< 2 منٹ پہلے';

  @override
  String get familyMapLegendTierRecent => 'حالیہ';

  @override
  String get familyMapLegendTierRecentDesc => '< 15 منٹ پہلے';

  @override
  String get familyMapLegendTierStale => 'پرانا';

  @override
  String get familyMapLegendTierStaleDesc => '< 1 گھنٹہ پہلے';

  @override
  String get familyMapLegendTierCity => 'شہر';

  @override
  String get familyMapLegendTierCityDesc => 'شہر کا مرکز';
}
