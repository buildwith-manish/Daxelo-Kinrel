import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_as.dart';
import 'app_localizations_bn.dart';
import 'app_localizations_en.dart';
import 'app_localizations_gu.dart';
import 'app_localizations_hi.dart';
import 'app_localizations_kn.dart';
import 'app_localizations_ml.dart';
import 'app_localizations_mr.dart';
import 'app_localizations_or.dart';
import 'app_localizations_pa.dart';
import 'app_localizations_sa.dart';
import 'app_localizations_sd.dart';
import 'app_localizations_ta.dart';
import 'app_localizations_te.dart';
import 'app_localizations_ur.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of S
/// returned by `S.of(context)`.
///
/// Applications need to include `S.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: S.localizationsDelegates,
///   supportedLocales: S.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the S.supportedLocales
/// property.
abstract class S {
  S(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static S? of(BuildContext context) {
    return Localizations.of<S>(context, S);
  }

  static const LocalizationsDelegate<S> delegate = _SDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('as'),
    Locale('bn'),
    Locale('gu'),
    Locale('hi'),
    Locale('kn'),
    Locale('ml'),
    Locale('mr'),
    Locale('or'),
    Locale('pa'),
    Locale('sa'),
    Locale('sd'),
    Locale('ta'),
    Locale('te'),
    Locale('ur'),
  ];

  /// The application name
  ///
  /// In en, this message translates to:
  /// **'Kinrel'**
  String get appName;

  /// Short tagline displayed under the app name
  ///
  /// In en, this message translates to:
  /// **'Map your family with AI'**
  String get appTagline;

  /// Bottom navigation tab label for Home
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get homeTitle;

  /// Bottom navigation tab label for Kinship/Explore
  ///
  /// In en, this message translates to:
  /// **'Kinship'**
  String get kinshipTitle;

  /// Bottom navigation tab label for Family Graph
  ///
  /// In en, this message translates to:
  /// **'Graph'**
  String get graphTitle;

  /// Bottom navigation tab label for Alerts/Notifications
  ///
  /// In en, this message translates to:
  /// **'Alerts'**
  String get alertsTitle;

  /// Bottom navigation tab label for Profile
  ///
  /// In en, this message translates to:
  /// **'Me'**
  String get profileTitle;

  /// Screen title for Notifications
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notificationsTitle;

  /// Screen title for Events & Celebrations
  ///
  /// In en, this message translates to:
  /// **'Events & Celebrations'**
  String get eventsTitle;

  /// Screen title for Memories & Timeline
  ///
  /// In en, this message translates to:
  /// **'Memories & Timeline'**
  String get memoriesTitle;

  /// Screen title for Family Chat
  ///
  /// In en, this message translates to:
  /// **'Family Chat'**
  String get chatTitle;

  /// Screen title for Document Vault
  ///
  /// In en, this message translates to:
  /// **'Document Vault'**
  String get documentsTitle;

  /// Screen title for Achievements
  ///
  /// In en, this message translates to:
  /// **'Achievements'**
  String get achievementsTitle;

  /// Screen title for Share & Invite
  ///
  /// In en, this message translates to:
  /// **'Share & Invite'**
  String get shareTitle;

  /// Screen title for Settings
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// Screen title for Sign In
  ///
  /// In en, this message translates to:
  /// **'Sign In'**
  String get signInTitle;

  /// Screen title for Sign Up
  ///
  /// In en, this message translates to:
  /// **'Sign Up'**
  String get signUpTitle;

  /// Onboarding page 1 title
  ///
  /// In en, this message translates to:
  /// **'Your Family, Your Story'**
  String get onboardingTitle1;

  /// Onboarding page 1 body text
  ///
  /// In en, this message translates to:
  /// **'Kinrel maps every relationship in your family — from your grandparents to your grandchildren, in the language you grew up with.'**
  String get onboardingBody1;

  /// Onboarding page 2 title
  ///
  /// In en, this message translates to:
  /// **'Names That Feel Like Home'**
  String get onboardingTitle2;

  /// Onboarding page 2 body text
  ///
  /// In en, this message translates to:
  /// **'Not just \'uncle\' and \'aunt\' — Kinrel knows the difference between your Chacha, Mama, Fufa, and Tauji.'**
  String get onboardingBody2;

  /// Onboarding page 3 title
  ///
  /// In en, this message translates to:
  /// **'See the Big Picture'**
  String get onboardingTitle3;

  /// Onboarding page 3 body text
  ///
  /// In en, this message translates to:
  /// **'Your entire family as a beautiful, interactive graph. Zoom in, explore connections, discover relationships you never knew existed.'**
  String get onboardingBody3;

  /// Onboarding page 4 title
  ///
  /// In en, this message translates to:
  /// **'Find Any Relationship Instantly'**
  String get onboardingTitle4;

  /// Onboarding page 4 body text
  ///
  /// In en, this message translates to:
  /// **'Select any two family members — Kinrel\'s AI calculates the exact relationship name in your language.'**
  String get onboardingBody4;

  /// Button label to add a family member
  ///
  /// In en, this message translates to:
  /// **'Add Member'**
  String get addMember;

  /// Button label to share the family tree
  ///
  /// In en, this message translates to:
  /// **'Share Family'**
  String get shareFamily;

  /// Button label to find relationship path between two people
  ///
  /// In en, this message translates to:
  /// **'Find Path'**
  String get findPath;

  /// Button label to view the complete family graph
  ///
  /// In en, this message translates to:
  /// **'View Full Graph'**
  String get viewFullGraph;

  /// Section header for recent activity feed
  ///
  /// In en, this message translates to:
  /// **'Recent Activity'**
  String get recentActivity;

  /// Section header for family statistics/insights
  ///
  /// In en, this message translates to:
  /// **'Family at a Glance'**
  String get familyInsights;

  /// Empty state message for notifications
  ///
  /// In en, this message translates to:
  /// **'All caught up! No new notifications.'**
  String get noNotifications;

  /// Empty state message for events
  ///
  /// In en, this message translates to:
  /// **'No events yet. Birthdays and anniversaries from your family will appear here automatically.'**
  String get noEvents;

  /// Empty state message for memories
  ///
  /// In en, this message translates to:
  /// **'No memories yet. Add your first family memory to begin.'**
  String get noMemories;

  /// Empty state message for documents
  ///
  /// In en, this message translates to:
  /// **'No documents yet. Securely store your family\'s important documents.'**
  String get noDocuments;

  /// Button label to create a new family
  ///
  /// In en, this message translates to:
  /// **'Create Family'**
  String get createFamily;

  /// Button label to join an existing family
  ///
  /// In en, this message translates to:
  /// **'Join Family'**
  String get joinFamily;

  /// Placeholder text in search bar
  ///
  /// In en, this message translates to:
  /// **'Search relationships'**
  String get searchHint;

  /// Notification text for birthday tomorrow
  ///
  /// In en, this message translates to:
  /// **'{name}\'s birthday is tomorrow!'**
  String birthdayTomorrow(String name);

  /// Notification text for upcoming anniversary
  ///
  /// In en, this message translates to:
  /// **'{name} & {name2}\'s anniversary is in {days} days!'**
  String anniversarySoon(String name, String name2, int days);

  /// Prompt to send birthday/anniversary wishes
  ///
  /// In en, this message translates to:
  /// **'Send wishes?'**
  String get sendWishes;

  /// Label showing consecutive days of activity
  ///
  /// In en, this message translates to:
  /// **'{count} Day Streak'**
  String streakDays(int count);

  /// Label showing profile completion percentage
  ///
  /// In en, this message translates to:
  /// **'{percent}% Complete'**
  String profileCompletion(int percent);

  /// Message showing family tree completion percentage
  ///
  /// In en, this message translates to:
  /// **'Your tree is {percent}% complete'**
  String treeCompleteness(int percent);

  /// Security notice about encryption
  ///
  /// In en, this message translates to:
  /// **'Encrypted with AES-256'**
  String get encryptNotice;

  /// Branding text on shared cards
  ///
  /// In en, this message translates to:
  /// **'Generated by Kinrel'**
  String get generatedByKinrel;

  /// Footer branding text
  ///
  /// In en, this message translates to:
  /// **'Made with love by Daxelo'**
  String get madeByDaxelo;

  /// Greeting for returning user
  ///
  /// In en, this message translates to:
  /// **'Welcome back'**
  String get welcomeBack;

  /// Time-based greeting for morning
  ///
  /// In en, this message translates to:
  /// **'Good morning'**
  String get goodMorning;

  /// Time-based greeting for afternoon
  ///
  /// In en, this message translates to:
  /// **'Good afternoon'**
  String get goodAfternoon;

  /// Time-based greeting for evening
  ///
  /// In en, this message translates to:
  /// **'Good evening'**
  String get goodEvening;

  /// Time-based greeting for night
  ///
  /// In en, this message translates to:
  /// **'Good night'**
  String get goodNight;

  /// Name of this language in its own script
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageName;
}

class _SDelegate extends LocalizationsDelegate<S> {
  const _SDelegate();

  @override
  Future<S> load(Locale locale) {
    return SynchronousFuture<S>(lookupS(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>[
    'as',
    'bn',
    'en',
    'gu',
    'hi',
    'kn',
    'ml',
    'mr',
    'or',
    'pa',
    'sa',
    'sd',
    'ta',
    'te',
    'ur',
  ].contains(locale.languageCode);

  @override
  bool shouldReload(_SDelegate old) => false;
}

S lookupS(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'as':
      return SAs();
    case 'bn':
      return SBn();
    case 'en':
      return SEn();
    case 'gu':
      return SGu();
    case 'hi':
      return SHi();
    case 'kn':
      return SKn();
    case 'ml':
      return SMl();
    case 'mr':
      return SMr();
    case 'or':
      return SOr();
    case 'pa':
      return SPa();
    case 'sa':
      return SSa();
    case 'sd':
      return SSd();
    case 'ta':
      return STa();
    case 'te':
      return STe();
    case 'ur':
      return SUr();
  }

  throw FlutterError(
    'S.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
