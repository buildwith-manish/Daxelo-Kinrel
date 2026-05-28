// lib/core/utils/share_helper.dart
//
// DAXELO KINREL — Share Helper Utility (P3-F2)
//
// Clean API for sharing deep links via the system share sheet.
// Uses share_plus (already in pubspec.yaml) and generates
// URLs consistent with the DeepLinkService.

import 'package:share_plus/share_plus.dart' as share_plus;
import '../services/crashlytics_service.dart';

/// Base URL for shareable deep links
const _baseUrl = 'https://kinrel.app';

class ShareHelper {
  ShareHelper._();

  /// Share a family profile link
  static Future<void> shareFamily({
    required String familyId,
    required String familyName,
  }) async {
    final url = '$_baseUrl/family/$familyId';
    final text =
        'Hey! Check out the $familyName family on Kinrel 🧡\n\n'
        'Explore our family tree:\n'
        '🔗 $url\n\n'
        '— Sent via Kinrel by Daxelo';

    logActionBreadcrumb('share_family', {'familyId': familyId});

    await share_plus.Share.share(
      text,
      subject: 'Join the $familyName Family on Kinrel',
    );
  }

  /// Share a member profile link
  static Future<void> shareProfile({
    required String memberId,
    required String memberName,
  }) async {
    final url = '$_baseUrl/member/$memberId';
    final text =
        'Check out $memberName on Kinrel 🧡\n\n'
        'See how they\'re connected in the family:\n'
        '🔗 $url\n\n'
        '— Sent via Kinrel by Daxelo';

    logActionBreadcrumb('share_profile', {'memberId': memberId});

    await share_plus.Share.share(
      text,
      subject: '$memberName on Kinrel',
    );
  }

  /// Share an invite link
  static Future<void> shareInvite({
    required String inviteCode,
    required String familyName,
  }) async {
    final url = '$_baseUrl/invite/$inviteCode';
    final text =
        'You\'re invited to join $familyName on Kinrel! 🧡\n\n'
        'Click the link to join the family tree:\n'
        '🔗 $url\n\n'
        '— Sent via Kinrel by Daxelo';

    logActionBreadcrumb('share_invite', {'inviteCode': inviteCode});

    await share_plus.Share.share(
      text,
      subject: 'Family invitation — $familyName on Kinrel',
    );
  }

  /// Share the app (general referral)
  static Future<void> shareApp() async {
    const url = 'https://kinrel.app';
    const text =
        'Discover your family roots on Kinrel! 🧡\n\n'
        'Build your family tree, explore kinship terms, and connect with relatives.\n'
        '🔗 $url\n\n'
        '— Sent via Kinrel by Daxelo';

    logActionBreadcrumb('share_app');

    await share_plus.Share.share(
      text,
      subject: 'Kinrel — Indian Family Relationship Intelligence',
    );
  }
}
