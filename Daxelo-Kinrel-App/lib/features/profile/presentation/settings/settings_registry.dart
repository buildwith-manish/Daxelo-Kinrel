// lib/features/profile/presentation/settings/settings_registry.dart
//
// DAXELO KINREL — Settings search registry.
//
// A flat list of every setting row in the app (one entry per row from
// section 5 of the spec). Used by the Settings hub's search field to
// filter and jump to a row.
//
// Search matching is case-insensitive substring over label + keywords.
// Label matches are ranked first.

import 'package:flutter/material.dart';

import '../../../../core/config/app_config.dart';
import 'settings_providers.dart';

/// One searchable setting entry.
class SettingsRegistryEntry {
  const SettingsRegistryEntry({
    required this.id,
    required this.label,
    required this.keywords,
    required this.categoryId,
    this.destination,
  });

  /// Stable id; used as a result-row key.
  final String id;

  /// What the user sees (matches the row label exactly).
  final String label;

  /// Lowercase synonyms for search. The label itself is also searched.
  final List<String> keywords;

  /// Which category screen this row lives in.
  final SettingsCategory categoryId;

  /// Where tapping a search result should navigate. May be null for
  /// sheet-triggered rows (the caller runs the sheet directly using
  /// SettingsActions.* — see settings_hub_screen.dart).
  final String? destination;
}

/// The full registry. Add new settings here so they appear in search.
const List<SettingsRegistryEntry> kSettingsRegistry = [
  // ── Account & security ────────────────────────────────────────────
  SettingsRegistryEntry(
    id: 'profile_details',
    label: 'Profile details',
    keywords: ['name', 'username', 'dob', 'bio', 'gender', 'edit profile'],
    categoryId: SettingsCategory.account,
    destination: '/profile/edit',
  ),
  SettingsRegistryEntry(
    id: 'account_information',
    label: 'Account Information',
    keywords: ['email', 'phone', 'security', 'private'],
    categoryId: SettingsCategory.account,
    destination: '/profile/account',
  ),
  SettingsRegistryEntry(
    id: 'change_password',
    label: 'Change password',
    keywords: ['password', 'login', 'credentials', 'reset'],
    categoryId: SettingsCategory.account,
    destination: '/profile/change-password',
  ),
  SettingsRegistryEntry(
    id: 'linked_accounts',
    label: 'Linked accounts',
    keywords: ['google', 'social', 'sign in with'],
    categoryId: SettingsCategory.account,
    destination: '/profile/linked-accounts',
  ),
  SettingsRegistryEntry(
    id: 'two_factor',
    label: 'Two-factor authentication',
    keywords: ['2fa', '2 step', 'totp', 'authenticator', 'verification'],
    categoryId: SettingsCategory.account,
    destination: '/profile/2fa-setup',
  ),
  SettingsRegistryEntry(
    id: 'active_sessions',
    label: 'Active sessions',
    keywords: ['devices', 'logout', 'sign out of devices', 'where am i logged in'],
    categoryId: SettingsCategory.account,
    destination: '/profile/sessions',
  ),
  SettingsRegistryEntry(
    id: 'delete_account',
    label: 'Delete my account',
    keywords: ['remove', 'close account', 'delete me', 'delete kinrel'],
    categoryId: SettingsCategory.account,
    destination: '/profile/delete-account',
  ),

  // ── Privacy ───────────────────────────────────────────────────────
  SettingsRegistryEntry(
    id: 'profile_visibility',
    label: 'Profile visibility',
    keywords: ['public', 'private', 'who can see me', 'visible'],
    categoryId: SettingsCategory.privacy,
  ),
  SettingsRegistryEntry(
    id: 'invite_permission',
    label: 'Who can invite me',
    keywords: ['invitations', 'invite', 'who can add me'],
    categoryId: SettingsCategory.privacy,
  ),
  SettingsRegistryEntry(
    id: 'location_sharing',
    label: 'Share my location with family',
    keywords: ['location', 'gps', 'map', 'where am i', 'live location'],
    categoryId: SettingsCategory.privacy,
  ),
  SettingsRegistryEntry(
    id: 'biometric_lock',
    label: 'Biometric lock',
    keywords: ['fingerprint', 'face', 'unlock', 'lock'],
    categoryId: SettingsCategory.privacy,
  ),
  SettingsRegistryEntry(
    id: 'privacy_active_sessions',
    label: 'Active sessions',
    keywords: ['devices', 'where am i logged in'],
    categoryId: SettingsCategory.privacy,
    destination: '/profile/sessions',
  ),
  SettingsRegistryEntry(
    id: 'your_family_your_data',
    label: 'Your Family, Your Data',
    keywords: ['data', 'store', 'export', 'delete', 'gdpr'],
    categoryId: SettingsCategory.privacy,
    destination: '/your-data',
  ),
  SettingsRegistryEntry(
    id: 'blocked_members',
    label: 'Blocked members',
    keywords: ['block', 'unblock', 'hide'],
    categoryId: SettingsCategory.privacy,
    destination: '/profile/blocked',
  ),

  // ── Notifications ─────────────────────────────────────────────────
  SettingsRegistryEntry(
    id: 'push_notifications',
    label: 'Push notifications',
    keywords: ['push', 'alerts', 'notifications'],
    categoryId: SettingsCategory.notifications,
  ),
  SettingsRegistryEntry(
    id: 'birthday_reminders',
    label: 'Birthday reminders',
    keywords: ['birthday', 'cake', 'reminders'],
    categoryId: SettingsCategory.notifications,
  ),
  SettingsRegistryEntry(
    id: 'anniversary_reminders',
    label: 'Anniversary reminders',
    keywords: ['anniversary', 'wedding'],
    categoryId: SettingsCategory.notifications,
  ),
  SettingsRegistryEntry(
    id: 'family_activity',
    label: 'Family activity',
    keywords: ['activity', 'events', 'updates'],
    categoryId: SettingsCategory.notifications,
  ),
  SettingsRegistryEntry(
    id: 'quiet_hours',
    label: 'Quiet hours',
    keywords: ['dnd', 'do not disturb', 'sleep', 'silent', 'night'],
    categoryId: SettingsCategory.notifications,
    destination: '/profile/quiet-hours',
  ),
  SettingsRegistryEntry(
    id: 'manage_occasions',
    label: 'Manage occasions',
    keywords: ['birthdays', 'anniversaries', 'occasions', 'reminders'],
    categoryId: SettingsCategory.notifications,
    destination: '/occasions',
  ),
  SettingsRegistryEntry(
    id: 'silent_alarms',
    label: 'Silent Alarms',
    keywords: ['alarms', 'nudges', 'quiet', 'inactive'],
    categoryId: SettingsCategory.notifications,
    destination: '/pulse/alarms',
  ),

  // ── Look & language ───────────────────────────────────────────────
  SettingsRegistryEntry(
    id: 'cameo',
    label: 'My Cameo',
    keywords: ['3d', 'character', 'avatar', 'portrait'],
    categoryId: SettingsCategory.look,
    destination: '/b1-verify',
  ),
  SettingsRegistryEntry(
    id: 'theme',
    label: 'Theme',
    keywords: ['dark', 'light', 'system', 'appearance'],
    categoryId: SettingsCategory.look,
  ),
  SettingsRegistryEntry(
    id: 'language',
    label: 'Language',
    keywords: ['hindi', 'tamil', 'bhasha', 'translate', 'indian'],
    categoryId: SettingsCategory.look,
  ),
  SettingsRegistryEntry(
    id: 'text_size',
    label: 'Text size',
    keywords: ['font', 'bigger', 'large', 'accessibility', 'scale'],
    categoryId: SettingsCategory.look,
  ),
  SettingsRegistryEntry(
    id: 'chat_wallpaper',
    label: 'Chat Wallpaper',
    keywords: ['wallpaper', 'chat background', 'background'],
    categoryId: SettingsCategory.look,
    destination: '/settings/wallpaper',
  ),
  SettingsRegistryEntry(
    id: 'easy_mode',
    label: 'Easy Mode for elders',
    keywords: ['grandparent', 'elders', 'simple', 'easy', 'large text'],
    categoryId: SettingsCategory.look,
  ),

  // ── Family & my data ──────────────────────────────────────────────
  SettingsRegistryEntry(
    id: 'join_family_by_id',
    label: 'Join Family by ID',
    keywords: ['kin', 'code', 'join', 'invite code'],
    categoryId: SettingsCategory.familyData,
    destination: '/join-family',
  ),
  SettingsRegistryEntry(
    id: 'my_family_trees',
    label: 'My family trees',
    keywords: ['families', 'trees', 'list'],
    categoryId: SettingsCategory.familyData,
    destination: '/profile/my-families',
  ),
  SettingsRegistryEntry(
    id: 'pending_invitations',
    label: 'Pending invitations',
    keywords: ['invites', 'requests', 'family invites'],
    categoryId: SettingsCategory.familyData,
    destination: '/profile/invitations',
  ),
  SettingsRegistryEntry(
    id: 'blocked_members_family_data',
    label: 'Blocked members',
    keywords: ['block', 'unblock'],
    categoryId: SettingsCategory.familyData,
    destination: '/profile/blocked',
  ),
  SettingsRegistryEntry(
    id: 'export_family_tree',
    label: 'Export family tree',
    keywords: ['export', 'pdf', 'json', 'csv', 'download tree'],
    categoryId: SettingsCategory.familyData,
  ),
  SettingsRegistryEntry(
    id: 'download_my_data',
    label: 'Download my data',
    keywords: ['export', 'backup', 'gdpr', 'data', 'download'],
    categoryId: SettingsCategory.familyData,
  ),
  SettingsRegistryEntry(
    id: 'your_family_your_data_fd',
    label: 'Your Family, Your Data',
    keywords: ['data', 'store', 'export', 'delete'],
    categoryId: SettingsCategory.familyData,
    destination: '/your-data',
  ),
  SettingsRegistryEntry(
    id: 'kinrel_learning_profile',
    label: 'Kinrel Learning Profile',
    keywords: ['learning', 'suggestions', 'transparency', 'reset'],
    categoryId: SettingsCategory.familyData,
  ),
  SettingsRegistryEntry(
    id: 'pulse_learning_profile',
    label: 'Pulse Learning Profile',
    keywords: ['pulse', 'engagement', 'ml', 'transparency'],
    categoryId: SettingsCategory.familyData,
    destination: '/profile/pulse-learning',
  ),
  // Communities row is gated on AppConfig.enableCommunity. While the
  // flag is off, the row disappears from settings search AND from the
  // Settings → Family & my data section (see settings_category_screen).
  // The /community route itself still exists in app_router but
  // redirects away, so a deep link or stale search hit can't reach it.
  if (AppConfig.enableCommunity)
    SettingsRegistryEntry(
      id: 'communities',
      label: 'Communities',
      keywords: ['gotra', 'village', 'surname', 'discover'],
      categoryId: SettingsCategory.familyData,
      destination: '/community',
    ),

  // ── Help & about ──────────────────────────────────────────────────
  SettingsRegistryEntry(
    id: 'help_center',
    label: 'Help center / FAQ',
    keywords: ['help', 'faq', 'questions', 'how to'],
    categoryId: SettingsCategory.help,
    destination: '/profile/help',
  ),
  SettingsRegistryEntry(
    id: 'contact_support',
    label: 'Contact support',
    keywords: ['support', 'contact', 'help', 'email'],
    categoryId: SettingsCategory.help,
    destination: '/profile/contact-support',
  ),
  SettingsRegistryEntry(
    id: 'report_bug',
    label: 'Report a bug',
    keywords: ['bug', 'report', 'issue', 'crash'],
    categoryId: SettingsCategory.help,
    destination: '/profile/report-bug',
  ),
  SettingsRegistryEntry(
    id: 'rate_app',
    label: 'Rate the app',
    keywords: ['rate', 'review', 'stars', 'play store', 'app store'],
    categoryId: SettingsCategory.help,
  ),
  SettingsRegistryEntry(
    id: 'share_app',
    label: 'Share Kinrel with friends',
    keywords: ['share', 'invite friends', 'spread', 'word'],
    categoryId: SettingsCategory.help,
  ),
  SettingsRegistryEntry(
    id: 'app_version',
    label: 'App version',
    keywords: ['version', 'build', 'update', 'changelog'],
    categoryId: SettingsCategory.help,
  ),
  SettingsRegistryEntry(
    id: 'terms_of_service',
    label: 'Terms of service',
    keywords: ['terms', 'legal', 'agreement'],
    categoryId: SettingsCategory.help,
    destination: '/terms',
  ),
  SettingsRegistryEntry(
    id: 'privacy_policy',
    label: 'Privacy policy',
    keywords: ['privacy', 'policy', 'legal'],
    categoryId: SettingsCategory.help,
    destination: '/privacy',
  ),
];

/// Case-insensitive substring search. Returns entries whose label OR
/// any keyword contains the query. Label matches are ranked first.
List<SettingsRegistryEntry> searchSettings(String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return const [];

  final labelHits = <SettingsRegistryEntry>[];
  final keywordHits = <SettingsRegistryEntry>[];
  for (final e in kSettingsRegistry) {
    if (e.label.toLowerCase().contains(q)) {
      labelHits.add(e);
      continue;
    }
    for (final kw in e.keywords) {
      if (kw.contains(q)) {
        keywordHits.add(e);
        break;
      }
    }
  }
  return [...labelHits, ...keywordHits];
}

/// Returns the category's accent color (used by tinted icons).
Color categoryTint(SettingsCategory cat) {
  switch (cat) {
    case SettingsCategory.account:
      return const Color(0xFFE8612A); // orange
    case SettingsCategory.privacy:
      return const Color(0xFF8B5CF6); // purple
    case SettingsCategory.notifications:
      return const Color(0xFF4CAF7A); // success green
    case SettingsCategory.look:
      return const Color(0xFFF59240); // amber
    case SettingsCategory.familyData:
      return const Color(0xFFD4AF37); // gold
    case SettingsCategory.help:
      return const Color(0xFF8A8A9E); // muted gray
  }
}

/// The icon shown on a category's row tile.
IconData categoryIcon(SettingsCategory cat) {
  switch (cat) {
    case SettingsCategory.account:
      return Icons.shield_outlined;
    case SettingsCategory.privacy:
      return Icons.visibility_outlined;
    case SettingsCategory.notifications:
      return Icons.notifications_outlined;
    case SettingsCategory.look:
      return Icons.dark_mode_outlined;
    case SettingsCategory.familyData:
      return Icons.family_restroom_outlined;
    case SettingsCategory.help:
      return Icons.help_outline;
  }
}
