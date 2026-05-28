// lib/core/widgets/accessible_icon_button.dart
//
// DAXELO KINREL — Accessible IconButton
//
// A Semantics-wrapped IconButton that guarantees:
//   • Always has a tooltip / semantic label (no unlabeled icon buttons)
//   • Minimum 48×48 dp tap target
//   • Optional custom semantic actions for screen readers
//
// This widget is required for Play Store accessibility rating
// and Indian government app compliance (WCAG 2.1 AA).

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

/// An [IconButton] that is always accessible to screen readers.
///
/// Unlike the raw [IconButton], this widget **requires** a [semanticLabel]
/// so that TalkBack / VoiceOver always have meaningful text to announce.
/// It also enforces a minimum 48×48 dp tap target.
///
/// ```dart
/// AccessibleIconButton(
///   icon: Icon(Icons.share),
///   semanticLabel: 'Share family tree',
///   onPressed: () => _shareTree(),
/// )
/// ```
///
/// If you need custom actions (e.g. "long press to delete"):
/// ```dart
/// AccessibleIconButton(
///   icon: Icon(Icons.more_vert),
///   semanticLabel: 'More options',
///   onPressed: () => _showMenu(),
///   customSemanticsActions: {
///     'Delete': () => _deleteItem(),
///   },
/// )
/// ```
class AccessibleIconButton extends StatelessWidget {
  const AccessibleIconButton({
    super.key,
    required this.icon,
    required this.semanticLabel,
    required this.onPressed,
    this.color,
    this.iconSize,
    this.padding,
    this.alignment,
    this.focusNode,
    this.autofocus = false,
    this.enableFeedback = true,
    this.customSemanticsActions = const {},
    this.disabledHint,
  });

  /// The icon widget to display.
  final Widget icon;

  /// Semantic label announced by screen readers. Required — never leave
  /// an icon button unlabeled.
  final String semanticLabel;

  /// Callback when the button is pressed. If null, the button is disabled.
  final VoidCallback? onPressed;

  /// Color for the icon. Defaults to the theme's icon theme color.
  final Color? color;

  /// Size of the icon inside the button. Defaults to 24.
  final double? iconSize;

  /// Padding around the icon. Defaults to 12 on all sides, which
  /// combined with the default 24 icon gives a 48×48 tap target.
  final EdgeInsetsGeometry? padding;

  /// Alignment of the icon within the button.
  final AlignmentGeometry? alignment;

  /// Optional focus node.
  final FocusNode? focusNode;

  /// Whether the button should auto-focus. Default false.
  final bool autofocus;

  /// Whether to provide haptic / acoustic feedback. Default true.
  final bool enableFeedback;

  /// Custom semantic actions that screen readers can invoke.
  /// Keys are action labels, values are callbacks.
  final Map<String, VoidCallback> customSemanticsActions;

  /// Hint announced when the button is disabled. If omitted, a
  /// default "Currently disabled" hint is used.
  final String? disabledHint;

  @override
  Widget build(BuildContext context) {
    final isDisabled = onPressed == null;
    final defaultPadding = padding ??
        const EdgeInsets.all(12.0); // 24 icon + 12*2 padding = 48

    final button = IconButton(
      icon: icon,
      iconSize: iconSize ?? 24.0,
      color: color,
      padding: defaultPadding,
      alignment: alignment ?? Alignment.center,
      focusNode: focusNode,
      autofocus: autofocus,
      enableFeedback: enableFeedback,
      tooltip: semanticLabel,
      onPressed: onPressed,
    );

    // Build Semantics wrapper
    Widget result = Semantics(
      button: true,
      label: semanticLabel,
      enabled: !isDisabled,
      hint: isDisabled
          ? (disabledHint ?? 'Currently disabled')
          : 'Double tap to activate',
      child: button,
    );

    // Add custom semantic actions if any
    if (customSemanticsActions.isNotEmpty) {
      result = Semantics(
        customSemanticsActions: customSemanticsActions.map(
          (label, callback) => MapEntry(
            CustomSemanticsAction(label: label),
            callback,
          ),
        ),
        child: result,
      );
    }

    // Enforce minimum tap target
    return ConstrainedBox(
      constraints: const BoxConstraints(
        minWidth: 48.0,
        minHeight: 48.0,
      ),
      child: result,
    );
  }
}
