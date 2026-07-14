// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Assamese (`as`).
class SAs extends S {
  SAs([String locale = 'as']) : super(locale);

  @override
  String get appName => 'Kinrel';

  @override
  String get appTagline => 'AI ৰ সৈতে আপোনাৰ পৰিয়ালৰ মানচিত্ৰ তৈয়াৰ কৰক';

  @override
  String get homeTitle => 'হোম';

  @override
  String get kinshipTitle => 'সম্পৰ্ক';

  @override
  String get graphTitle => 'গ্ৰাফ';

  @override
  String get alertsTitle => 'সতৰ্কতা';

  @override
  String get profileTitle => 'মই';

  @override
  String get notificationsTitle => 'জাননী';

  @override
  String get eventsTitle => 'অনুষ্ঠান আৰু উৎসৱ';

  @override
  String get memoriesTitle => 'স্মৃতি আৰু সময়ৰেখা';

  @override
  String get chatTitle => 'পাৰিয়ালিক চেট';

  @override
  String get documentsTitle => 'নথি ভল্ট';

  @override
  String get achievementsTitle => 'সাফল্য';

  @override
  String get shareTitle => 'শ্বেয়াৰ আৰু নিমন্ত্ৰণ';

  @override
  String get settingsTitle => 'ছেটিংছ';

  @override
  String get signInTitle => 'ছাইন ইন';

  @override
  String get signUpTitle => 'ছাইন আপ';

  @override
  String get onboardingTitle1 => 'আপোনাৰ পৰিয়াল, আপোনাৰ কাহিনী';

  @override
  String get onboardingBody1 =>
      'Kinrel আপোনাৰ পৰিয়ালৰ প্ৰতিটো সম্পৰ্ক মেপ কৰে — আপোনাৰ ককাইদেউ-আইদেউৰ পৰা আপোনাৰ নাতি-নাতিনীলৈকে, যিটো ভাষাত আপুনি ডাঙৰ-দীঘল হৈছে।';

  @override
  String get onboardingTitle2 => 'নাম যিবোৰে ঘৰৰ দৰে অনুভৱ কৰায়';

  @override
  String get onboardingBody2 =>
      'কেৱল \'আংকল\' আৰু \'আণ্টি\' নহয় — Kinrel আপোনাৰ কাকাই, মামা, পেহী আৰু বৰদেউতাৰ মাজৰ পাৰ্থক্য জানে।';

  @override
  String get onboardingTitle3 => 'ডাঙৰ ছবিখন চাওক';

  @override
  String get onboardingBody3 =>
      'আপোনাৰ সম্পূৰ্ণ পৰিয়াল এটা সুন্দৰ, ইণ্টাৰেক্টিভ গ্ৰাফৰ দৰে। জুম ইন কৰক, সম্পৰ্কসমূহ অন্বেষণ কৰক, এনে সম্পৰ্ক আৱিষ্কাৰ কৰক যিবোৰ আপুনি নজানিছিল।';

  @override
  String get onboardingTitle4 => 'যিকোনো সম্পৰ্ক তৎক্ষণাৎ বিচাৰক';

  @override
  String get onboardingBody4 =>
      'পৰিয়ালৰ যিকোনো দুজন সদস্য বাছক — Kinrel ৰ AI আপোনাৰ ভাষাত সঠিক সম্পৰ্কৰ নাম গণনা কৰিব।';

  @override
  String get addMember => 'সদস্য যোগ কৰক';

  @override
  String get shareFamily => 'পৰিয়াল শ্বেয়াৰ কৰক';

  @override
  String get findPath => 'পথ বিচাৰক';

  @override
  String get viewFullGraph => 'সম্পূৰ্ণ গ্ৰাফ চাওক';

  @override
  String get recentActivity => 'শেহতীয়া কাৰ্যকলাপ';

  @override
  String get familyInsights => 'পৰিয়াল এক দৃষ্টিত';

  @override
  String get noNotifications => 'সকলো ঠিক! কোনো নতুন জাননী নাই।';

  @override
  String get noEvents =>
      'এতিয়ালৈকে কোনো অনুষ্ঠান নাই। আপোনাৰ পৰিয়ালৰ জন্মদিন আৰু বাৰ্ষিকী ইয়াত স্বয়ংক্ৰিয়ভাৱে দেখা যাব।';

  @override
  String get noMemories =>
      'এতিয়ালৈকে কোনো স্মৃতি নাই। আপোনাৰ প্ৰথম পাৰিয়ালিক স্মৃতি যোগ কৰি আৰম্ভ কৰক।';

  @override
  String get noDocuments =>
      'এতিয়ালৈকে কোনো নথি নাই। আপোনাৰ পৰিয়ালৰ গুৰুত্বপূৰ্ণ নথিসমূহ সুৰক্ষিতভাৱে সঞ্চয় কৰক।';

  @override
  String get createFamily => 'পৰিয়াল সৃষ্টি কৰক';

  @override
  String get joinFamily => 'পৰিয়ালত যোগদান কৰক';

  @override
  String get searchHint => 'সম্পৰ্ক বিচাৰক';

  @override
  String birthdayTomorrow(String name) {
    return '$nameৰ জন্মদিন কাইলৈ!';
  }

  @override
  String anniversarySoon(String name, String name2, int days) {
    return '$name আৰু $name2ৰ বাৰ্ষিকী $days দিনত!';
  }

  @override
  String get sendWishes => 'শুভেচ্ছা পঠিয়াবনে?';

  @override
  String streakDays(int count) {
    return '$count দিনৰ ধাৰাবাহিকতা';
  }

  @override
  String profileCompletion(int percent) {
    return '$percent% সম্পূৰ্ণ';
  }

  @override
  String treeCompleteness(int percent) {
    return 'আপোনাৰ গছ $percent% সম্পূৰ্ণ';
  }

  @override
  String get encryptNotice => 'AES-256 ৰে এনক্ৰিপ্টেড';

  @override
  String get generatedByKinrel => 'Kinrel দ্বাৰা সৃষ্টি';

  @override
  String get madeByDaxelo => 'Daxeloৰ প্ৰেমেৰে নিৰ্মিত';

  @override
  String get welcomeBack => 'পুনৰ স্বাগতম';

  @override
  String get goodMorning => 'সুপ্ৰভাত';

  @override
  String get goodAfternoon => 'শুভ দুপৰীয়া';

  @override
  String get goodEvening => 'শুভ সন্ধিয়া';

  @override
  String get goodNight => 'শুভ ৰাতি';

  @override
  String get languageName => 'অসমীয়া';

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
}
