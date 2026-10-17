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

  @override
  String chatTypingSingle(String name) {
    return '$name टाइप कर रहे हैं';
  }

  @override
  String chatTypingTwo(String name1, String name2) {
    return '$name1 और $name2 टाइप कर रहे हैं';
  }

  @override
  String chatTypingMany(String name) {
    return '$name और अन्य टाइप कर रहे हैं';
  }

  @override
  String get chatActiveNow => 'अभी एक्टिव';

  @override
  String chatNActive(int count) {
    return '$count एक्टिव';
  }

  @override
  String get chatLastSeenJustNow => 'अभी-अभी देखा';

  @override
  String chatLastSeenMinutes(int count) {
    return '$count मिनट पहले देखा';
  }

  @override
  String chatLastSeenHours(int count) {
    return '$count घंटे पहले देखा';
  }

  @override
  String chatLastSeenDays(int count) {
    return '$count दिन पहले देखा';
  }

  @override
  String get chatOffline => 'ऑफलाइन';

  @override
  String get chatEmptyStateTitle => 'बातचीत शुरू करें';

  @override
  String chatEmptyStateSubtitle(String familyName, int count) {
    return '$familyName परिवार में ($count सदस्य)';
  }

  @override
  String chatEmptyStateSubtitleNoCount(String familyName) {
    return '$familyName परिवार में';
  }

  @override
  String get chatSuggestionNamaste => 'सबको नमस्ते 🙏';

  @override
  String get chatSuggestionHowIsEveryone => 'सब कैसे हैं?';

  @override
  String chatSuggestionGoodMorning(String familyName) {
    return 'सुप्रभात, $familyName परिवार! ☀️';
  }

  @override
  String chatBirthdayToday(String name) {
    return 'आज $name का जन्मदिन है! 🎂';
  }

  @override
  String chatBirthdayTomorrow(String name) {
    return 'कल $name का जन्मदिन है 🎂';
  }

  @override
  String chatBirthdayInDays(String name, int count) {
    return '$count दिन में $name का जन्मदिन है 🎂';
  }

  @override
  String get chatSearchPlaceholder => 'संदेश खोजें...';

  @override
  String get chatSearchNoResults => 'कोई संदेश नहीं मिला';

  @override
  String chatSearchResultsCount(int count) {
    return '$count परिणाम';
  }

  @override
  String get chatMessageSending => 'भेजा जा रहा है...';

  @override
  String get chatMessageFailed => 'भेजने में विफल';

  @override
  String get chatMessageFailedRetry => 'पुनः प्रयास करने के लिए टैप करें';

  @override
  String get chatReplyToOriginalNotFound =>
      'संदेश लोड किए गए इतिहास से पुराना है — खोजने के लिए ऊपर स्क्रॉल करें।';

  @override
  String chatSystemMessageUserJoined(String name) {
    return '$name रूम में शामिल हुए';
  }

  @override
  String chatSystemMessageUserLeft(String name) {
    return '$name रूम छोड़ गए';
  }

  @override
  String chatSystemMessageUserDisconnected(String name) {
    return '$name डिस्कनेक्ट हो गए';
  }

  @override
  String chatSystemMessageRoomClosed(String name) {
    return '$name ने रूम बंद कर दिया';
  }

  @override
  String chatSystemMessageUserReacted(String name, String emoji) {
    return '$name ने प्रतिक्रिया दी $emoji';
  }

  @override
  String get chatReportMenuItem => 'रिपोर्ट करें';

  @override
  String get chatReportSheetTitle => 'इस संदेश की रिपोर्ट करें';

  @override
  String chatReportSheetSubtitle(String senderName) {
    return '$senderName का संदेश मॉडरेटर को रिपोर्ट करें';
  }

  @override
  String get chatReportNoPreview => '(कोई पूर्वावलोकन नहीं)';

  @override
  String get chatReportReasonLabel => 'आप यह क्यों रिपोर्ट कर रहे हैं?';

  @override
  String get chatReportReasonSpam => 'स्पैम';

  @override
  String get chatReportReasonHarassment => 'उत्पीड़न';

  @override
  String get chatReportReasonInappropriateContent => 'अनुपयुक्त सामग्री';

  @override
  String get chatReportReasonOther => 'अन्य';

  @override
  String get chatReportDescriptionLabel => 'विवरण जोड़ें (वैकल्पिक)';

  @override
  String get chatReportDescriptionHint => 'बताएं कि क्या गलत है';

  @override
  String get chatReportCancel => 'रद्द करें';

  @override
  String get chatReportSubmit => 'रिपोर्ट सबमिट करें';

  @override
  String get chatReportSubmitted => 'रिपोर्ट सबमिट हुई। धन्यवाद।';

  @override
  String get chatReportAlreadyReported =>
      'आपने पहले ही इस संदेश की रिपोर्ट की है।';

  @override
  String get chatReportFailed =>
      'रिपोर्ट सबमिट करने में विफल। पुनः प्रयास करें।';

  @override
  String get chatBlockedMessagePlaceholder =>
      'ब्लॉक किए गए उपयोगकर्ता का संदेश';

  @override
  String get chatBlockedMessageShow => 'दिखाएं';

  @override
  String get chatBlockedMessageHide => 'छिपाएं';

  @override
  String get chatBlockMenuItem => 'ब्लॉक करें';

  @override
  String get chatBlockFromMessageMenuItem => 'इस उपयोगकर्ता को ब्लॉक करें';

  @override
  String chatBlockDialogTitle(String name) {
    return '$name को ब्लॉक करें?';
  }

  @override
  String get chatBlockDialogBody =>
      'वे आपको डायरेक्ट संदेश नहीं भेज सकेंगे, और आप भी उन्हें नहीं भेज सकेंगे। ग्रुप चैट में उनके संदेश प्लेसहोल्डर के पीछे छिपे रहेंगे। उन्हें नहीं बताया जाएगा कि उन्हें ब्लॉक किया गया है।';

  @override
  String get chatBlockDialogConfirm => 'ब्लॉक करें';

  @override
  String get chatBlockDialogCancel => 'रद्द करें';

  @override
  String get chatBlockSucceeded => 'उपयोगकर्ता ब्लॉक कर दिया गया।';

  @override
  String get chatBlockFailed =>
      'उपयोगकर्ता को ब्लॉक करने में विफल। पुनः प्रयास करें।';

  @override
  String get chatBlockedDirectHeader => 'आपने इस व्यक्ति को ब्लॉक किया है';

  @override
  String get chatBlockedDirectUnblockButton => 'अनब्लॉक करें';

  @override
  String chatDraftPrefix(String text) {
    return 'ड्राफ्ट: $text';
  }

  @override
  String get chatScheduleMenuItem => 'शेड्यूल किए गए संदेश';

  @override
  String get chatScheduleSheetTitle => 'संदेश शेड्यूल करें';

  @override
  String chatScheduleSheetSubtitle(String content) {
    return '\"$content\" बाद में भेजें';
  }

  @override
  String get chatScheduleQuickLaterToday => 'आज शाम';

  @override
  String get chatScheduleQuickTomorrow => 'कल सुबह';

  @override
  String get chatScheduleQuickWeekend => 'इस सप्ताहांत';

  @override
  String get chatScheduleQuickCustom => 'कस्टम...';

  @override
  String get chatScheduleQuickCustomHint => 'तारीख और समय चुनें';

  @override
  String get chatScheduleCancel => 'रद्द करें';

  @override
  String chatScheduleSuccess(String time) {
    return '$time के लिए शेड्यूल किया';
  }

  @override
  String get chatSchedulePastTimeRejected => 'भविष्य में समय चुनें';

  @override
  String get chatScheduleNotSignedIn => 'शेड्यूल करने के लिए साइन इन करें';

  @override
  String get chatScheduleFailed => 'शेड्यूल करने में विफल। पुनः प्रयास करें।';

  @override
  String get chatScheduleDatePickerHelp => 'तारीख चुनें';

  @override
  String get chatScheduleTimePickerHelp => 'समय चुनें';

  @override
  String get chatScheduledListTitle => 'शेड्यूल किए गए संदेश';

  @override
  String get chatScheduledListEmpty =>
      'इस चैट में कोई शेड्यूल किए गए संदेश नहीं हैं।';

  @override
  String get chatScheduledListCancel => 'रद्द करें';

  @override
  String get chatScheduledListRetry => 'पुनः प्रयास';

  @override
  String get chatScheduledListEditTime => 'समय संपादित करें';

  @override
  String get chatScheduledListEditText => 'टेक्स्ट संपादित करें';

  @override
  String get chatScheduledListFailed => 'भेजने में विफल';

  @override
  String chatScheduledListSendingAt(String time) {
    return '$time पर भेजा जा रहा है';
  }

  @override
  String chatScheduledListSentAt(String time) {
    return '$time पर भेजा गया';
  }

  @override
  String get chatScheduleCancelled =>
      'शेड्यूल किया गया संदेश रद्द कर दिया गया।';

  @override
  String get chatScheduleRetried =>
      'शेड्यूल किए गए संदेश को पुनः प्रयास किया गया।';

  @override
  String get chatScheduleEditTimeUpdated => 'समय अपडेट किया गया।';

  @override
  String get chatScheduleEditTextUpdated => 'टेक्स्ट अपडेट किया गया।';

  @override
  String get chatAttachEvent => 'कार्यक्रम';

  @override
  String get chatAttachEventCreateNew => 'नया कार्यक्रम बनाएं';

  @override
  String get chatAttachEventPickExisting => 'मौजूदा कार्यक्रम चुनें';

  @override
  String get chatEventCardNoTitle => 'परिवार कार्यक्रम';

  @override
  String get chatEventCardDeleted => 'कार्यक्रम अब उपलब्ध नहीं है';

  @override
  String chatEventRsvpGoing(int count) {
    return '$count जा रहे हैं';
  }

  @override
  String chatEventRsvpMaybe(int count) {
    return '$count शायद';
  }

  @override
  String chatEventRsvpNotGoing(int count) {
    return '$count नहीं जा सकते';
  }

  @override
  String get chatEventRsvpGoingLabel => 'जा रहे हैं';

  @override
  String get chatEventRsvpMaybeLabel => 'शायद';

  @override
  String get chatEventRsvpNotGoingLabel => 'नहीं जा सकते';

  @override
  String chatEventCardSemantics(
    String title,
    String date,
    String location,
    int going,
    int maybe,
    int notGoing,
  ) {
    return 'परिवार कार्यक्रम कार्ड: $date को $title स्थान पर $location। $going जा रहे हैं, $maybe शायद, $notGoing नहीं जा सकते।';
  }

  @override
  String get chatEventCardSemanticsDeleted =>
      'परिवार कार्यक्रम कार्ड: कार्यक्रम अब उपलब्ध नहीं है।';
}
