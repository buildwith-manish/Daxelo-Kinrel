// lib/core/utils/accessibility_utils.dart
//
// DAXELO KINREL — Accessibility Utility Helpers
//
// A collection of semantic wrapper helpers and tap-target utilities
// that ensure the app meets WCAG 2.1 AA and Indian government app
// compliance requirements for Android TalkBack and iOS VoiceOver.
//
// Key standards enforced:
//   • All interactive elements have semantic labels
//   • Minimum 48×48 dp tap targets (Material Design, WCAG 2.5.5)
//   • Live regions for dynamic content (e.g. network status)
//   • Semantic roles for custom-painted / composed widgets

import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';

// ═══════════════════════════════════════════════════════════════════════
// SEMANTIC WRAPPERS
// ═══════════════════════════════════════════════════════════════════════

/// Wraps a widget with a Semantics node that announces it as a **button**.
///
/// Use for custom tappable widgets (GestureDetector, InkWell, etc.)
/// that are not natively recognized as buttons by screen readers.
///
/// ```dart
/// semanticButton(
///   label: 'Add family member',
///   child: GestureDetector(onTap: () {}, child: Icon(Icons.add)),
/// )
/// ```
Widget semanticButton({
  required String label,
  required Widget child,
  bool enabled = true,
  String? hint,
}) {
  return Semantics(
    button: true,
    label: label,
    enabled: enabled,
    hint: hint,
    child: child,
  );
}

/// Wraps a widget with a Semantics node that announces it as an **image**.
///
/// Use for decorative or informative images (avatars, illustrations)
/// that need a descriptive label for screen readers.
///
/// ```dart
/// semanticImage(
///   label: 'Profile photo of Ravi Sharma',
///   child: CircleAvatar(backgroundImage: ...),
/// )
/// ```
Widget semanticImage({
  required String label,
  required Widget child,
  bool isDecorative = false,
}) {
  return Semantics(
    image: true,
    label: isDecorative ? '' : label,
    child: child,
  );
}

/// Wraps a widget with a Semantics node that announces it as a **header**.
///
/// Use for section titles and headings to allow screen reader users
/// to navigate by heading level.
///
/// ```dart
/// semanticHeader(
///   label: 'Account Settings',
///   child: Text('Account Settings', style: ...),
/// )
/// ```
Widget semanticHeader({
  required String label,
  required Widget child,
}) {
  return Semantics(
    header: true,
    label: label,
    child: child,
  );
}

/// Wraps a widget with a Semantics node that announces it as a **link**.
///
/// Use for navigation targets that behave like hyperlinks
/// (e.g. "Terms of Service" tappable text).
///
/// ```dart
/// semanticLink(
///   label: 'Terms of Service',
///   child: GestureDetector(onTap: () {}, child: Text('Terms')),
/// )
/// ```
Widget semanticLink({
  required String label,
  required Widget child,
}) {
  return Semantics(
    link: true,
    label: label,
    child: child,
  );
}

/// Ensures a minimum tap target size of [minSize]×[minSize] dp.
///
/// Wraps the child in a [ConstrainedBox] so that even small visual
/// targets (e.g. 24×24 icons) have at least a 48×48 dp hit area,
/// meeting WCAG 2.5.5 / Material Design tap target guidelines.
///
/// ```dart
/// minimumTapTarget(
///   child: IconButton(icon: Icon(Icons.close), onPressed: () {}),
/// )
/// ```
Widget minimumTapTarget({
  required Widget child,
  double minSize = 48.0,
}) {
  return ConstrainedBox(
    constraints: BoxConstraints(
      minWidth: minSize,
      minHeight: minSize,
    ),
    child: child,
  );
}

/// Wraps a widget as a **live region** so that screen readers announce
/// changes to its content automatically.
///
/// Use for status banners, toast messages, and dynamic feedback
/// (e.g. "No internet connection" banner).
///
/// [polite] delays announcement until the reader is idle (default).
/// [assertive] interrupts the current announcement immediately.
///
/// ```dart
/// semanticLiveRegion(
///   child: Text(isOnline ? 'Connected' : 'Offline'),
/// )
/// ```
Widget semanticLiveRegion({
  required Widget child,
  bool assertive = false,
}) {
  return Semantics(
    liveRegion: true,
    label: '', // The child's visible text is announced automatically
    child: child,
  );
}

/// Wraps a bottom navigation item with a Semantics node that announces
/// it as a **tab** with its label and selected state.
///
/// Use for each item in a BottomNavigationBar or custom bottom nav
/// to ensure TalkBack/VoiceOver announce the tab's role, label,
/// position, and selected state.
///
/// ```dart
/// semanticTab(
///   label: 'Home',
///   index: 0,
///   child: _NavItemWidget(...),
/// )
/// ```
Widget semanticTab({
  required String label,
  required int index,
  required Widget child,
  bool isSelected = false,
  int? totalTabs,
}) {
  final hintSuffix = totalTabs != null
      ? ', ${index + 1} of $totalTabs'
      : '';

  return Semantics(
    button: true,
    label: label,
    selected: isSelected,
    inMutuallyExclusiveGroup: true,
    hint: isSelected
        ? 'Currently selected$hintSuffix'
        : 'Double tap to select$hintSuffix',
    child: child,
  );
}

// ═══════════════════════════════════════════════════════════════════════
// CUSTOM SEMANTIC ACTIONS
// ═══════════════════════════════════════════════════════════════════════

/// Adds custom accessibility actions to a widget.
///
/// Use for custom gestures that have no standard semantic equivalent
/// (e.g. "long press to delete", "swipe to dismiss").
///
/// ```dart
/// withCustomSemanticActions(
///   actions: {
///     'delete': () => _deleteItem(),
///     'edit': () => _editItem(),
///   },
///   child: ListTile(title: Text('Item')),
/// )
/// ```
Widget withCustomSemanticActions({
  required Map<String, VoidCallback> actions,
  required Widget child,
}) {
  return Semantics(
    customSemanticsActions: actions.map(
      (label, callback) => MapEntry(
        CustomSemanticsAction(label: label),
        callback,
      ),
    ),
    child: child,
  );
}
