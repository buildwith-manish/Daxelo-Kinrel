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
  String get familyMapControlLocate => 'મારું સ્થાન શોધો';

  @override
  String get familyMapControlZoomIn => 'ઝૂમ ઇન';

  @override
  String get familyMapControlZoomOut => 'ઝૂમ આઉટ';

  @override
  String get familyMapControlLayers => 'સ્તરો';

  @override
  String get familyMapControlDarkMode => 'ડાર્ક મેપ';

  @override
  String get familyMapControlLightMode => 'લાઇટ મેપ';

  @override
  String get familyMapControl3DBuildingsOn => 'Turn on 3D buildings';

  @override
  String get familyMapControl3DBuildingsOff => 'Turn off 3D buildings';

  @override
  String get familyMapLocateServiceOff => 'લોકેશન સેવાઓ બંધ છે.';

  @override
  String get familyMapLocatePermissionDenied => 'લોકેશન પરવાનગી નકારાઈ.';

  @override
  String get familyMapLocateFailed => 'તમારું વર્તમાન સ્થાન મળ્યું નહીં.';

  @override
  String get familyMapLayersTitle => 'મેપ સ્તરો';

  @override
  String get familyMapLayersDone => 'પૂર્ણ';

  @override
  String get familyMapLayerHomes => 'પારિવારિક ઘરો';

  @override
  String get familyMapLayerWeddings => 'લગ્ન સ્થળો';

  @override
  String get familyMapLayerMemorials => 'સ્મારકો';

  @override
  String get familyMapLayerSchools => 'શાળાઓ';

  @override
  String get familyMapLayerPlaces => 'મહત્વપૂર્ણ સ્થળો';

  @override
  String get familyMapLayerRelationships => 'સંબંધ પથ';

  @override
  String get familyMapLayerCallouts => 'સ્થળ લેબલ્સ';

  @override
  String get familyMapLayerLivePulses => 'લાઇવ સ્પંદન';

  @override
  String get familyMapSearchHint => 'શહેર અથવા પરિવારના સભ્યને શોધો';

  @override
  String get familyMapSearchCollapsed => 'શહેર અથવા પરિવારના સભ્યને શોધો';

  @override
  String get familyMapSearchClear => 'સાફ કરો';

  @override
  String get familyMapSearchCityHint => 'શહેર';

  @override
  String get familyMapLegendPinned => 'સ્થિત';

  @override
  String get familyMapLegendCities => 'શહેરો';

  @override
  String get familyMapLegendStatusTitle => 'સ્થિતિ સ્તરો';

  @override
  String get familyMapLegendCategoriesTitle => 'સ્થળ શ્રેણીઓ';

  @override
  String get familyMapLegendUnpinnedTitle => 'મેપ પર નથી';

  @override
  String get familyMapLegendTierLive => 'લાઇવ';

  @override
  String get familyMapLegendTierLiveDesc => '< ૨ મિનિટ પહેલા';

  @override
  String get familyMapLegendTierRecent => 'તાજેતરનું';

  @override
  String get familyMapLegendTierRecentDesc => '< ૧૫ મિનિટ પહેલા';

  @override
  String get familyMapLegendTierStale => 'જૂનું';

  @override
  String get familyMapLegendTierStaleDesc => '< ૧ કલાક પહેલા';

  @override
  String get familyMapLegendTierCity => 'શહેર';

  @override
  String get familyMapLegendTierCityDesc => 'શહેર કેન્દ્ર';
}
