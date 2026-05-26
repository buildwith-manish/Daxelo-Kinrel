// lib/shared/widgets/dk_components.dart
//
// DAXELO KINREL — DK* Reusable Component Library
//
// A cohesive widget library implementing the stitch.zip design reference.
// All components are theme-aware, supporting both light and dark modes,
// and use the KINREL brand constants (KinrelColors, KinrelTypography,
// KinrelSpacing, KinrelRadius) plus stitch-specific DKColors tokens.
//
// Components:
//   1.  DKScaffold       — Themed scaffold with gradient background
//   2.  DKCard           — Configurable theme-aware card
//   3.  DKButton         — Multi-variant button (primary/secondary/gradient/social/icon)
//   4.  DKAvatar         — Circular avatar with optional border and glow
//   5.  DKSearchField    — Rounded search input
//   6.  DKGlassCard      — Glassmorphism card with backdrop blur
//   7.  DKBottomNav      — 5-tab bottom navigation
//   8.  DKChatBubble     — Chat message bubble (user/AI)
//   9.  DKBadge          — Notification count badge
//   10. DKSuggestionChip — Chat suggestion pill
//   11. DKTabToggle      — Pill-style tab selector
//   12. DKTimelineNode   — Circular date badge
//   13. DKStatChip       — Small stat display
//   14. DKEmptyState     — Beautiful empty state with illustration
//   15. DKLoadingShimmer — Animated shimmer placeholder
//   16. DKErrorState     — Error state with retry

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:shimmer/shimmer.dart';

import '../../core/constants/brand_typography.dart';
import '../../core/constants/brand_spacing.dart';

// ═══════════════════════════════════════════════════════════════════════
// DK DESIGN TOKENS — stitch.zip Color System
// ═══════════════════════════════════════════════════════════════════════

/// Stitch.zip design color tokens used by DK* components.
///
/// These extend the core KINREL brand colors with additional
/// purple/gold/coral tones required by the stitch reference.
class DKColors {
  DKColors._();

  // ── Brand ────────────────────────────────────────────────────────
  static const Color brandPurple = Color(0xFF5D5FEF);
  static const Color brandDeepPurple = Color(0xFF4B3F8A);
  static const Color brandViolet = Color(0xFF8A2BE2);
  static const Color brandGold = Color(0xFFD4AF37);
  static const Color brandBrightGold = Color(0xFFFFD700);
  static const Color brandCoral = Color(0xFFFF6B6B);
  static const Color brandOrange = Color(0xFFF97316);
  static const Color brandBlue = Color(0xFF3B82F6);

  // ── Dark theme surfaces ──────────────────────────────────────────
  static const Color darkBg = Color(0xFF121212);
  static const Color darkCard = Color(0xFF1E1E1E);
  static const Color darkElevated = Color(0xFF2A2A3E);
  static const Color darkSurface = Color(0xFF2A1F4A);

  // ── Light theme surfaces ─────────────────────────────────────────
  static const Color lightBg = Color(0xFFF5F7FA);
  static const Color lightCard = Color(0xFFFFFFFF);
  static const Color lightElevated = Color(0xFFF2F2F7);

  // ── Text ─────────────────────────────────────────────────────────
  static const Color textDark = Color(0xFF2D3748);
  static const Color textLight = Color(0xFFFFFFFF);
  static const Color textSecondaryLight = Color(0xFFB0B0B0);
  static const Color textSecondaryDark = Color(0xFF8E8E93);

  // ── Semantic ─────────────────────────────────────────────────────
  static const Color error = Color(0xFFFF6B6B);
  static const Color success = Color(0xFF4CAF7A);
  static const Color warning = Color(0xFFF5A623);

  // ── Gradients ────────────────────────────────────────────────────
  static const LinearGradient ctaGradient = LinearGradient(
    colors: [brandPurple, brandViolet],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient socialGradient = LinearGradient(
    colors: [brandBlue, brandPurple],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient exploreGradient = LinearGradient(
    colors: [brandBlue, brandViolet],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  static const LinearGradient goldGradient = LinearGradient(
    colors: [brandGold, brandBrightGold],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // ── Helper ───────────────────────────────────────────────────────
  /// Returns `true` if the current theme is light.
  static bool isLight(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light;

  /// Returns the appropriate background color for the current theme.
  static Color background(BuildContext context) =>
      isLight(context) ? lightBg : darkBg;

  /// Returns the appropriate card color for the current theme.
  static Color cardColor(BuildContext context) =>
      isLight(context) ? lightCard : darkCard;

  /// Returns the appropriate elevated color for the current theme.
  static Color elevatedColor(BuildContext context) =>
      isLight(context) ? lightElevated : darkElevated;

  /// Returns the appropriate primary text color for the current theme.
  static Color textPrimary(BuildContext context) =>
      isLight(context) ? textDark : textLight;

  /// Returns the appropriate secondary text color for the current theme.
  static Color textSecondary(BuildContext context) =>
      isLight(context) ? textSecondaryDark : textSecondaryLight;

  /// Returns the appropriate border color for the current theme.
  static Color borderColor(BuildContext context) =>
      isLight(context)
          ? const Color(0xFFE5E7EB)
          : const Color(0xFF3A3A4A);

  /// Returns the primary brand color for the current theme.
  static Color primary(BuildContext context) =>
      isLight(context) ? brandPurple : brandDeepPurple;
}

// ═══════════════════════════════════════════════════════════════════════
// 1. DKScaffold
// ═══════════════════════════════════════════════════════════════════════

/// Themed scaffold with optional gradient background, safe area,
/// and optional floating action button.
///
/// ```dart
/// DKScaffold(
///   gradient: DKColors.ctaGradient,
///   body: Center(child: Text('Hello')),
/// )
/// ```
class DKScaffold extends StatelessWidget {
  const DKScaffold({
    super.key,
    this.gradient,
    this.backgroundColor,
    required this.body,
    this.appBar,
    this.bottomNavigationBar,
    this.floatingActionButton,
    this.useSafeArea = true,
  });

  /// Optional gradient to paint behind the body.
  final LinearGradient? gradient;

  /// Background color used when [gradient] is null.
  /// Defaults to theme-aware background.
  final Color? backgroundColor;

  /// The primary content of the scaffold.
  final Widget body;

  /// Optional app bar displayed at the top.
  final PreferredSizeWidget? appBar;

  /// Optional bottom navigation bar.
  final Widget? bottomNavigationBar;

  /// Optional floating action button.
  final Widget? floatingActionButton;

  /// Whether to wrap the body in a [SafeArea]. Default true.
  final bool useSafeArea;


  @override
  Widget build(BuildContext context) {
    final bgColor = backgroundColor ?? DKColors.background(context);

    Widget bodyContent = body;
    if (useSafeArea) {
      bodyContent = SafeArea(child: body);
    }

    if (gradient != null) {
      bodyContent = DecoratedBox(
        decoration: BoxDecoration(gradient: gradient),
        child: bodyContent,
      );
    }

    return Scaffold(
      backgroundColor: gradient != null ? Colors.transparent : bgColor,
      appBar: appBar,
      body: bodyContent,
      bottomNavigationBar: bottomNavigationBar,
      floatingActionButton: floatingActionButton,
      extendBody: true,
      extendBodyBehindAppBar: appBar != null,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 2. DKCard
// ═══════════════════════════════════════════════════════════════════════

/// Configurable card with theme-aware styling.
///
/// Dark mode: darkCard background with subtle border.
/// Light mode: white background with soft shadow.
///
/// ```dart
/// DKCard(
///   child: Text('Content'),
///   gradient: DKColors.ctaGradient,
///   onTap: () => print('Card tapped'),
/// )
/// ```
class DKCard extends StatelessWidget {
  const DKCard({
    super.key,
    required this.child,
    this.padding = 16,
    this.radius = KinrelRadius.lg,
    this.elevation = 0,
    this.gradient,
    this.borderColor,
    this.backgroundColor,
    this.onTap,
  });

  /// The card's content.
  final Widget child;

  /// Inner padding. Default 16.
  final double padding;

  /// Border radius. Default 16.
  final double radius;

  /// Elevation shadow. Default 0 (no shadow in dark; subtle shadow in light).
  final double elevation;

  /// Optional gradient fill instead of solid color.
  final LinearGradient? gradient;

  /// Optional border color override.
  final Color? borderColor;

  /// Optional background color override.
  final Color? backgroundColor;

  /// Optional tap handler — makes the card interactive.
  final VoidCallback? onTap;


  @override
  Widget build(BuildContext context) {
    final isLight = DKColors.isLight(context);
    final bgColor = backgroundColor ?? DKColors.cardColor(context);
    final border = borderColor ?? (isLight ? null : const Color(0xFF3A3A4A));
    final shadow = elevation > 0
        ? [
            BoxShadow(
              color: Colors.black.withValues(alpha: isLight ? 0.08 : 0.3),
              blurRadius: elevation * 4,
              offset: Offset(0, elevation * 2),
            ),
          ]
        : isLight
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ]
            : null;

    final decoration = BoxDecoration(
      color: gradient != null ? null : bgColor,
      gradient: gradient,
      borderRadius: BorderRadius.circular(radius),
      border: border != null
          ? Border.all(color: border, width: 1)
          : null,
      boxShadow: shadow,
    );

    final cardChild = Padding(
      padding: EdgeInsets.all(padding),
      child: child,
    );

    if (onTap != null) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(radius),
          child: AnimatedContainer(
            duration: KinrelMotion.fast,
            decoration: decoration,
            clipBehavior: Clip.antiAlias,
            child: cardChild,
          ),
        ),
      )
          .animate(onPlay: (c) => c.forward())
          .fadeIn(duration: KinrelMotion.normal);
    }

    return AnimatedContainer(
      duration: KinrelMotion.normal,
      decoration: decoration,
      clipBehavior: Clip.antiAlias,
      child: cardChild,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 3. DKButton
// ═══════════════════════════════════════════════════════════════════════

/// Button size variants.
enum DKButtonSize { sm, md, lg }

/// Button visual variants.
enum DKButtonVariant { primary, secondary, gradient, social, icon }

/// Multi-variant button supporting primary, secondary, gradient,
/// social, and icon styles.
///
/// ```dart
/// DKButton(
///   label: 'Get Started',
///   variant: DKButtonVariant.gradient,
///   onPressed: () {},
/// )
/// ```
class DKButton extends StatefulWidget {
  const DKButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = DKButtonVariant.primary,
    this.icon,
    this.isLoading = false,
    this.gradient,
    this.fullWidth = false,
    this.size = DKButtonSize.md,
  });

  /// Button label text.
  final String label;

  /// Callback when the button is pressed.
  final VoidCallback? onPressed;

  /// Visual variant. Default [DKButtonVariant.primary].
  final DKButtonVariant variant;

  /// Optional icon displayed before the label.
  final IconData? icon;

  /// Whether to show a loading spinner. Default false.
  final bool isLoading;

  /// Custom gradient for the [DKButtonVariant.gradient] variant.
  /// Defaults to [DKColors.ctaGradient].
  final LinearGradient? gradient;

  /// Whether the button should fill available width. Default false.
  final bool fullWidth;

  /// Size variant. Default [DKButtonSize.md].
  final DKButtonSize size;


  @override
  State<DKButton> createState() => _DKButtonState();
}

class _DKButtonState extends State<DKButton> {
  bool _isPressed = false;

  double get _height {
    switch (widget.size) {
      case DKButtonSize.sm:
        return 36;
      case DKButtonSize.md:
        return 48;
      case DKButtonSize.lg:
        return 56;
    }
  }

  double get _fontSize {
    switch (widget.size) {
      case DKButtonSize.sm:
        return 13;
      case DKButtonSize.md:
        return 15;
      case DKButtonSize.lg:
        return 17;
    }
  }

  double get _radius {
    switch (widget.size) {
      case DKButtonSize.sm:
        return KinrelRadius.sm;
      case DKButtonSize.md:
        return KinrelRadius.md;
      case DKButtonSize.lg:
        return KinrelRadius.lg;
    }
  }

  EdgeInsets get _padding {
    switch (widget.size) {
      case DKButtonSize.sm:
        return const EdgeInsets.symmetric(horizontal: 16, vertical: 8);
      case DKButtonSize.md:
        return const EdgeInsets.symmetric(horizontal: 24, vertical: 12);
      case DKButtonSize.lg:
        return const EdgeInsets.symmetric(horizontal: 32, vertical: 16);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLight = DKColors.isLight(context);
    final isDisabled = widget.onPressed == null || widget.isLoading;

    // ── Determine colors based on variant ──────────────────────────
    Color? bg;
    Color fg;
    LinearGradient? bgGradient;
    BorderSide? border;
    List<BoxShadow>? shadows;

    switch (widget.variant) {
      case DKButtonVariant.primary:
        bg = isLight ? DKColors.brandPurple : DKColors.brandDeepPurple;
        fg = Colors.white;

      case DKButtonVariant.secondary:
        bg = Colors.transparent;
        fg = isLight ? DKColors.brandPurple : DKColors.brandPurple;
        border = BorderSide(
          color: isLight
              ? DKColors.brandPurple.withValues(alpha: 0.5)
              : DKColors.brandGold.withValues(alpha: 0.5),
          width: 1.5,
        );

      case DKButtonVariant.gradient:
        bgGradient = widget.gradient ?? DKColors.ctaGradient;
        fg = Colors.white;
        shadows = [
          BoxShadow(
            color: DKColors.brandPurple.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ];

      case DKButtonVariant.social:
        bgGradient = DKColors.socialGradient;
        fg = Colors.white;

      case DKButtonVariant.icon:
        bg = isLight
            ? DKColors.brandPurple.withValues(alpha: 0.1)
            : DKColors.brandPurple.withValues(alpha: 0.15);
        fg = isLight ? DKColors.brandPurple : DKColors.brandPurple;
    }

    // ── Build decoration ───────────────────────────────────────────
    final decoration = BoxDecoration(
      color: isDisabled ? (bg?.withValues(alpha: 0.5) ?? DKColors.darkElevated) : bg,
      gradient: isDisabled ? null : bgGradient,
      borderRadius: BorderRadius.circular(_radius),
      border: border != null && !isDisabled
          ? Border.fromBorderSide(border)
          : null,
      boxShadow: shadows,
    );

    // ── Build child ────────────────────────────────────────────────
    Widget content;
    if (widget.isLoading) {
      content = SizedBox(
        height: _fontSize + 4,
        width: _fontSize + 4,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(fg),
        ),
      );
    } else if (widget.variant == DKButtonVariant.icon && widget.icon != null) {
      content = Icon(widget.icon, size: _fontSize + 6, color: fg);
    } else {
      final List<Widget> rowChildren = [];
      if (widget.icon != null) {
        rowChildren.add(
          Icon(widget.icon, size: _fontSize + 2, color: fg),
        );
        rowChildren.add(const SizedBox(width: 8));
      }
      rowChildren.add(
        Text(
          widget.label,
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: _fontSize,
            fontWeight: FontWeight.w600,
            color: fg,
            letterSpacing: 0.3,
          ),
        ),
      );
      content = Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: rowChildren,
      );
    }

    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: isDisabled ? null : widget.onPressed,
      child: AnimatedScale(
        scale: _isPressed ? 0.96 : 1.0,
        duration: KinrelMotion.instant,
        child: AnimatedContainer(
          duration: KinrelMotion.fast,
          constraints: BoxConstraints(
            minWidth: widget.fullWidth ? double.infinity : 0,
            minHeight: _height,
          ),
          padding: _padding,
          decoration: decoration,
          child: Center(child: content),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 4. DKAvatar
// ═══════════════════════════════════════════════════════════════════════

/// Avatar size presets.
enum DKAvatarSize { sm, md, lg, xl }

/// Circular avatar with optional border and glow effect.
///
/// ```dart
/// DKAvatar(
///   initials: 'AK',
///   size: DKAvatarSize.lg,
///   showGlow: true,
///   borderColor: DKColors.brandGold,
/// )
/// ```
class DKAvatar extends StatelessWidget {
  const DKAvatar({
    super.key,
    this.size = DKAvatarSize.md,
    this.imageUrl,
    this.initials,
    this.borderColor,
    this.showGlow = false,
    this.backgroundColor,
  });

  /// Size preset. Default [DKAvatarSize.md].
  final DKAvatarSize size;

  /// Optional network image URL.
  final String? imageUrl;

  /// Fallback initials displayed when no image is provided.
  final String? initials;

  /// Border color. Default matches theme; gold for premium users.
  final Color? borderColor;

  /// Whether to show a purple glow effect. Default false.
  final bool showGlow;

  /// Background color when no image is provided.
  final Color? backgroundColor;


  double get _diameter {
    switch (size) {
      case DKAvatarSize.sm:
        return 32;
      case DKAvatarSize.md:
        return 40;
      case DKAvatarSize.lg:
        return 56;
      case DKAvatarSize.xl:
        return 80;
    }
  }

  double get _fontSize {
    switch (size) {
      case DKAvatarSize.sm:
        return 12;
      case DKAvatarSize.md:
        return 14;
      case DKAvatarSize.lg:
        return 18;
      case DKAvatarSize.xl:
        return 24;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLight = DKColors.isLight(context);
    final bg = backgroundColor ??
        (isLight
            ? DKColors.brandPurple.withValues(alpha: 0.1)
            : DKColors.brandDeepPurple.withValues(alpha: 0.3));
    final border = borderColor ??
        (isLight ? Colors.transparent : const Color(0xFF3A3A4A));
    final fg = isLight ? DKColors.brandPurple : Colors.white;

    Widget avatar = Container(
      width: _diameter,
      height: _diameter,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: imageUrl != null ? null : bg,
        border: Border.all(
          color: border,
          width: borderColor != null ? 2.5 : 1,
        ),
        image: imageUrl != null
            ? DecorationImage(
                image: NetworkImage(imageUrl!),
                fit: BoxFit.cover,
              )
            : null,
      ),
      child: imageUrl != null
          ? null
          : Center(
              child: Text(
                initials ?? '',
                style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: _fontSize,
                  fontWeight: FontWeight.w700,
                  color: fg,
                  height: 1,
                ),
              ),
            ),
    );

    if (showGlow) {
      avatar = Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: DKColors.brandPurple.withValues(alpha: 0.4),
              blurRadius: _diameter * 0.4,
              spreadRadius: _diameter * 0.1,
            ),
          ],
        ),
        child: avatar,
      );
    }

    return avatar;
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 5. DKSearchField
// ═══════════════════════════════════════════════════════════════════════

/// Rounded search input field with optional gradient background.
///
/// ```dart
/// DKSearchField(
///   hint: 'Search kinship terms...',
///   useGradient: true,
///   onChanged: (value) => print(value),
/// )
/// ```
class DKSearchField extends StatelessWidget {
  const DKSearchField({
    super.key,
    required this.hint,
    this.onChanged,
    this.onSubmitted,
    this.controller,
    this.useGradient = false,
  });

  /// Placeholder hint text.
  final String hint;

  /// Callback when the text changes.
  final ValueChanged<String>? onChanged;

  /// Callback when the user submits the search.
  final ValueChanged<String>? onSubmitted;

  /// Optional text controller.
  final TextEditingController? controller;

  /// Whether to use a blue-to-purple gradient background (dark explore screen).
  /// Default false.
  final bool useGradient;


  @override
  Widget build(BuildContext context) {
    final isLight = DKColors.isLight(context);

    final Color hintColor;
    final Color iconColor;
    final Color textColor;
    final Color inputFillColor;
    BorderSide? border;

    if (useGradient) {
      inputFillColor = Colors.white.withValues(alpha: 0.15);
      hintColor = Colors.white.withValues(alpha: 0.6);
      iconColor = Colors.white.withValues(alpha: 0.7);
      textColor = Colors.white;
      border = null;
    } else {
      inputFillColor = isLight
          ? DKColors.lightElevated
          : DKColors.darkElevated;
      hintColor = DKColors.textSecondary(context);
      iconColor = DKColors.textSecondary(context);
      textColor = DKColors.textPrimary(context);
      border = BorderSide(color: DKColors.borderColor(context));
    }

    Widget textField = TextField(
      controller: controller,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      style: TextStyle(
        fontFamily: KinrelTypography.bodyFont,
        fontSize: 15,
        color: textColor,
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
          fontFamily: KinrelTypography.bodyFont,
          fontSize: 15,
          color: hintColor,
        ),
        prefixIcon: Icon(Icons.search_rounded, color: iconColor, size: 22),
        filled: true,
        fillColor: inputFillColor,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: KinrelSpacing.lg,
          vertical: KinrelSpacing.md,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(KinrelRadius.xl),
          borderSide: border ?? BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(KinrelRadius.xl),
          borderSide: border ?? BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(KinrelRadius.xl),
          borderSide: useGradient
              ? BorderSide(color: Colors.white.withValues(alpha: 0.4), width: 1.5)
              : const BorderSide(color: DKColors.brandPurple, width: 1.5),
        ),
      ),
    );

    if (useGradient) {
      textField = Container(
        decoration: BoxDecoration(
          gradient: DKColors.exploreGradient,
          borderRadius: BorderRadius.circular(KinrelRadius.xl),
        ),
        child: textField,
      );
    }

    return textField;
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 6. DKGlassCard
// ═══════════════════════════════════════════════════════════════════════

/// Glassmorphism card with backdrop blur effect.
///
/// Uses [ClipRRect] + [BackdropFilter] for a frosted-glass
/// appearance with a semi-transparent dark background and
/// subtle border.
///
/// ```dart
/// DKGlassCard(
///   child: Text('Frosted content'),
///   blurSigma: 20,
/// )
/// ```
class DKGlassCard extends StatelessWidget {
  const DKGlassCard({
    super.key,
    required this.child,
    this.padding = 16,
    this.radius = 20,
    this.borderColor,
    this.blurSigma = 16,
  });

  /// The card's content.
  final Widget child;

  /// Inner padding. Default 16.
  final double padding;

  /// Border radius. Default 20.
  final double radius;

  /// Optional border color override.
  final Color? borderColor;

  /// Blur sigma for the backdrop filter. Default 16.
  final double blurSigma;


  @override
  Widget build(BuildContext context) {
    final isLight = DKColors.isLight(context);
    final border = borderColor ??
        (isLight
            ? Colors.white.withValues(alpha: 0.3)
            : Colors.white.withValues(alpha: 0.12));

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: blurSigma,
          sigmaY: blurSigma,
        ),
        child: Container(
          padding: EdgeInsets.all(padding),
          decoration: BoxDecoration(
            color: isLight
                ? Colors.white.withValues(alpha: 0.6)
                : Colors.black.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: border, width: 1),
          ),
          child: child,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 7. DKBottomNav
// ═══════════════════════════════════════════════════════════════════════

/// A navigation item for [DKBottomNav].
class DKNavItem {
  const DKNavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    this.badge,
  });

  /// Icon for the unselected state.
  final IconData icon;

  /// Icon for the selected state.
  final IconData activeIcon;

  /// Label text below the icon.
  final String label;

  /// Optional badge count to display.
  final int? badge;

}

/// 5-tab bottom navigation bar with theme-aware styling.
///
/// Dark mode: semi-transparent background with blur, purple active,
/// gold highlight.
/// Light mode: white background, purple active.
/// Height: 64px, rounded top corners.
///
/// ```dart
/// DKBottomNav(
///   currentIndex: 0,
///   onTap: (i) => setState(() => _index = i),
///   items: [
///     DKNavItem(icon: Icons.home_outlined, activeIcon: Icons.home, label: 'Home'),
///     DKNavItem(icon: Icons.explore_outlined, activeIcon: Icons.explore, label: 'Explore'),
///   ],
/// )
/// ```
class DKBottomNav extends StatelessWidget {
  const DKBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.items,
  });

  /// Currently selected tab index.
  final int currentIndex;

  /// Callback when a tab is tapped.
  final ValueChanged<int> onTap;

  /// List of navigation items.
  final List<DKNavItem> items;


  @override
  Widget build(BuildContext context) {
    final isLight = DKColors.isLight(context);

    return Container(
      height: 64,
      decoration: BoxDecoration(
        color: isLight
            ? DKColors.lightCard
            : DKColors.darkCard.withValues(alpha: 0.9),
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(KinrelRadius.xl),
        ),
        border: isLight
            ? const Border(
                top: BorderSide(color: Color(0xFFE5E7EB), width: 1),
              )
            : Border.all(color: const Color(0xFF3A3A4A), width: 0.5),
        boxShadow: isLight
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -2),
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(KinrelRadius.xl),
        ),
        child: isLight
            ? _buildContent(isLight)
            : BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: _buildContent(isLight),
              ),
      ),
    );
  }

  Widget _buildContent(bool isLight) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: List.generate(items.length, (index) {
        final item = items[index];
        final isSelected = index == currentIndex;
        final activeColor = isLight
            ? DKColors.brandPurple
            : DKColors.brandPurple;
        final inactiveColor = isLight
            ? DKColors.textSecondaryDark
            : DKColors.textSecondaryLight;

        return _DKNavItemWidget(
          item: item,
          isSelected: isSelected,
          activeColor: activeColor,
          inactiveColor: inactiveColor,
          isLight: isLight,
          onTap: () => onTap(index),
        );
      }),
    );
  }
}

class _DKNavItemWidget extends StatelessWidget {
  const _DKNavItemWidget({
    required this.item,
    required this.isSelected,
    required this.activeColor,
    required this.inactiveColor,
    required this.isLight,
    required this.onTap,
  });

  final DKNavItem item;
  final bool isSelected;
  final Color activeColor;
  final Color inactiveColor;
  final bool isLight;
  final VoidCallback onTap;


  @override
  Widget build(BuildContext context) {
    final color = isSelected ? activeColor : inactiveColor;

    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          height: 64,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 40,
                height: 28,
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    Icon(
                      isSelected ? item.activeIcon : item.icon,
                      color: color,
                      size: 24,
                    ),
                    if (item.badge != null && item.badge! > 0)
                      Positioned(
                        top: -2,
                        right: -4,
                        child: DKBadge(count: item.badge!, size: 16),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 2),
              Text(
                item.label,
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 10,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  color: color,
                  height: 1.2,
                ),
              ),
              if (isSelected) ...[
                const SizedBox(height: 2),
                Container(
                  width: 16,
                  height: 2,
                  decoration: BoxDecoration(
                    color: isLight ? DKColors.brandPurple : DKColors.brandGold,
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 8. DKChatBubble
// ═══════════════════════════════════════════════════════════════════════

/// Chat message bubble for user and AI messages.
///
/// User (right): purple background, white text, rounded rect
/// with bottom-right corner cut.
/// AI (left): lavender background in light / dark with purple
/// border in dark, with bottom-left corner cut.
///
/// ```dart
/// DKChatBubble(
///   message: 'Hello there!',
///   isUser: true,
///   time: '2:30 PM',
/// )
/// ```
class DKChatBubble extends StatelessWidget {
  const DKChatBubble({
    super.key,
    required this.message,
    this.isUser = false,
    this.time,
    this.senderName,
  });

  /// The message text.
  final String message;

  /// Whether this is a user message (right-aligned). Default false (AI).
  final bool isUser;

  /// Optional timestamp string.
  final String? time;

  /// Optional sender name (for AI messages).
  final String? senderName;


  @override
  Widget build(BuildContext context) {
    final isLight = DKColors.isLight(context);

    final Color bg;
    final Color fg;
    final Color? border;
    final BorderRadius borderRadius;

    if (isUser) {
      bg = DKColors.brandPurple;
      fg = Colors.white;
      border = null;
      borderRadius = BorderRadius.only(
        topLeft: Radius.circular(KinrelRadius.lg),
        topRight: Radius.circular(KinrelRadius.lg),
        bottomLeft: Radius.circular(KinrelRadius.lg),
        bottomRight: Radius.circular(4),
      );
    } else {
      bg = isLight
          ? const Color(0xFFE6D5F5) // lavender
          : const Color(0xFF2A2A2A);
      fg = isLight ? DKColors.textDark : Colors.white;
      border = isLight ? null : DKColors.brandPurple.withValues(alpha: 0.3);
      borderRadius = BorderRadius.only(
        topLeft: Radius.circular(KinrelRadius.lg),
        topRight: Radius.circular(KinrelRadius.lg),
        bottomLeft: Radius.circular(4),
        bottomRight: Radius.circular(KinrelRadius.lg),
      );
    }

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        margin: EdgeInsets.only(
          left: isUser ? 48 : 0,
          right: isUser ? 0 : 48,
          bottom: 4,
        ),
        padding: EdgeInsets.symmetric(
          horizontal: KinrelSpacing.md,
          vertical: KinrelSpacing.sm + 2,
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: borderRadius,
          border: border != null ? Border.all(color: border, width: 1) : null,
        ),
        child: Column(
          crossAxisAlignment:
              isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (senderName != null && !isUser) ...[
              Text(
                senderName!,
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isLight ? DKColors.brandDeepPurple : DKColors.brandPurple,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 2),
            ],
            Text(
              message,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 14,
                fontWeight: FontWeight.w400,
                color: fg,
                height: 1.5,
              ),
            ),
            if (time != null) ...[
              const SizedBox(height: 4),
              Text(
                time!,
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 10,
                  color: fg.withValues(alpha: 0.6),
                  height: 1.2,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 9. DKBadge
// ═══════════════════════════════════════════════════════════════════════

/// Notification count badge — a small red circle with a white number.
///
/// ```dart
/// DKBadge(count: 3)
/// DKBadge(count: 99, size: 20, color: DKColors.brandCoral)
/// ```
class DKBadge extends StatelessWidget {
  const DKBadge({
    super.key,
    required this.count,
    this.size = 18,
    this.color = DKColors.brandCoral,
  });

  /// The count to display. If 0, the badge is hidden.
  final int count;

  /// Diameter of the badge circle. Default 18.
  final double size;

  /// Background color of the badge. Default red.
  final Color color;


  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();

    final display = count > 99 ? '99+' : '$count';

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        display,
        style: TextStyle(
          fontFamily: KinrelTypography.bodyFont,
          fontSize: size * 0.5,
          fontWeight: FontWeight.w700,
          color: Colors.white,
          height: 1,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 10. DKSuggestionChip
// ═══════════════════════════════════════════════════════════════════════

/// Chat suggestion pill chip.
///
/// Rounded pill with themed background, purple border when selected.
///
/// ```dart
/// DKSuggestionChip(
///   label: 'Family Tree',
///   isSelected: true,
///   onTap: () {},
/// )
/// ```
class DKSuggestionChip extends StatelessWidget {
  const DKSuggestionChip({
    super.key,
    required this.label,
    required this.onTap,
    this.isSelected = false,
  });

  /// The chip label.
  final String label;

  /// Tap callback.
  final VoidCallback onTap;

  /// Whether the chip is in a selected state. Default false.
  final bool isSelected;


  @override
  Widget build(BuildContext context) {
    final isLight = DKColors.isLight(context);
    final bg = isSelected
        ? DKColors.brandPurple.withValues(alpha: isLight ? 0.15 : 0.25)
        : (isLight ? DKColors.lightElevated : DKColors.darkElevated);
    final fg = isSelected
        ? DKColors.brandPurple
        : DKColors.textPrimary(context);
    final border = isSelected
        ? DKColors.brandPurple
        : DKColors.borderColor(context);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: KinrelMotion.fast,
        padding: const EdgeInsets.symmetric(
          horizontal: KinrelSpacing.md,
          vertical: KinrelSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(KinrelRadius.xxl),
          border: Border.all(
            color: border,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
            color: fg,
            height: 1.3,
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 11. DKTabToggle
// ═══════════════════════════════════════════════════════════════════════

/// Pill-style tab selector for AI chat and similar contexts.
///
/// Purple active pill with transparent inactive state.
///
/// ```dart
/// DKTabToggle(
///   tabs: ['Chat', 'History', 'Saved'],
///   selectedIndex: 0,
///   onChanged: (i) => setState(() => _tab = i),
/// )
/// ```
class DKTabToggle extends StatelessWidget {
  const DKTabToggle({
    super.key,
    required this.tabs,
    required this.selectedIndex,
    required this.onChanged,
  });

  /// List of tab labels.
  final List<String> tabs;

  /// Currently selected tab index.
  final int selectedIndex;

  /// Callback when the selected tab changes.
  final ValueChanged<int> onChanged;


  @override
  Widget build(BuildContext context) {
    final isLight = DKColors.isLight(context);

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: isLight
            ? DKColors.lightElevated
            : DKColors.darkElevated,
        borderRadius: BorderRadius.circular(KinrelRadius.lg),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(tabs.length, (index) {
          final isSelected = index == selectedIndex;

          return GestureDetector(
            onTap: () => onChanged(index),
            child: AnimatedContainer(
              duration: KinrelMotion.fast,
              padding: const EdgeInsets.symmetric(
                horizontal: KinrelSpacing.lg,
                vertical: KinrelSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: isSelected
                    ? DKColors.brandPurple
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(KinrelRadius.md),
              ),
              child: Text(
                tabs[index],
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: isSelected
                      ? Colors.white
                      : DKColors.textSecondary(context),
                  height: 1.3,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 12. DKTimelineNode
// ═══════════════════════════════════════════════════════════════════════

/// Circular date badge for timeline views.
///
/// Displays an icon inside a circle with a colored border.
///
/// ```dart
/// DKTimelineNode(
///   icon: Icons.cake,
///   color: DKColors.brandGold,
///   label: 'Birthday',
/// )
/// ```
class DKTimelineNode extends StatelessWidget {
  const DKTimelineNode({
    super.key,
    required this.icon,
    required this.color,
    this.size = 60,
    this.label,
  });

  /// Icon displayed inside the circle.
  final IconData icon;

  /// Color for the border and icon.
  final Color color;

  /// Diameter of the circle. Default 60.
  final double size;

  /// Optional label below the circle.
  final String? label;


  @override
  Widget build(BuildContext context) {
    final isLight = DKColors.isLight(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: isLight ? 0.1 : 0.15),
            border: Border.all(color: color, width: 2),
          ),
          child: Icon(
            icon,
            color: color,
            size: size * 0.4,
          ),
        ),
        if (label != null) ...[
          const SizedBox(height: 4),
          Text(
            label!,
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: DKColors.textSecondary(context),
              height: 1.2,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 13. DKStatChip
// ═══════════════════════════════════════════════════════════════════════

/// Compact stat display chip (e.g., "5 Members").
///
/// ```dart
/// DKStatChip(
///   icon: Icons.people,
///   value: '5',
///   label: 'Members',
///   color: DKColors.brandPurple,
/// )
/// ```
class DKStatChip extends StatelessWidget {
  const DKStatChip({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  /// Icon to display.
  final IconData icon;

  /// The stat value (e.g., "5").
  final String value;

  /// Descriptive label (e.g., "Members").
  final String label;

  /// Accent color for icon and value.
  final Color color;


  @override
  Widget build(BuildContext context) {
    final isLight = DKColors.isLight(context);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: KinrelSpacing.md,
        vertical: KinrelSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isLight ? 0.08 : 0.12),
        borderRadius: BorderRadius.circular(KinrelRadius.md),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            value,
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: color,
              height: 1.2,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 12,
              fontWeight: FontWeight.w400,
              color: DKColors.textSecondary(context),
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 14. DKEmptyState
// ═══════════════════════════════════════════════════════════════════════

/// Beautiful empty state with illustration, title, subtitle,
/// and optional CTA button.
///
/// ```dart
/// DKEmptyState(
///   icon: Icons.family_restroom,
///   title: 'No Families Yet',
///   subtitle: 'Create your first family to get started',
///   actionLabel: 'Create Family',
///   onAction: () => _createFamily(),
/// )
/// ```
class DKEmptyState extends StatelessWidget {
  const DKEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  /// Large centered icon.
  final IconData icon;

  /// Title text.
  final String title;

  /// Subtitle/description text.
  final String subtitle;

  /// Optional CTA button label.
  final String? actionLabel;

  /// Optional CTA button callback.
  final VoidCallback? onAction;


  @override
  Widget build(BuildContext context) {
    final isLight = DKColors.isLight(context);
    final iconColor = isLight ? DKColors.brandPurple : DKColors.brandPurple;

    return Padding(
      padding: const EdgeInsets.all(KinrelSpacing.xxl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: iconColor.withValues(alpha: isLight ? 0.1 : 0.15),
            ),
            child: Icon(
              icon,
              size: 40,
              color: iconColor,
            ),
          )
              .animate(onPlay: (c) => c.forward())
              .fadeIn(duration: 400.ms)
              .scale(
                begin: const Offset(0.8, 0.8),
                end: const Offset(1.0, 1.0),
                duration: 400.ms,
                curve: Curves.easeOutBack,
              ),
          const SizedBox(height: KinrelSpacing.lg),
          Text(
            title,
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: DKColors.textPrimary(context),
              height: 1.3,
            ),
            textAlign: TextAlign.center,
          )
              .animate()
              .fadeIn(duration: 300.ms, delay: 100.ms)
              .slideY(begin: 0.1, end: 0, duration: 300.ms),
          const SizedBox(height: KinrelSpacing.sm),
          Text(
            subtitle,
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 14,
              fontWeight: FontWeight.w400,
              color: DKColors.textSecondary(context),
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          )
              .animate()
              .fadeIn(duration: 300.ms, delay: 200.ms)
              .slideY(begin: 0.1, end: 0, duration: 300.ms),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: KinrelSpacing.xl),
            DKButton(
              label: actionLabel!,
              variant: DKButtonVariant.primary,
              onPressed: onAction,
            )
                .animate()
                .fadeIn(duration: 300.ms, delay: 300.ms)
                .slideY(begin: 0.15, end: 0, duration: 300.ms),
          ],
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 15. DKLoadingShimmer
// ═══════════════════════════════════════════════════════════════════════

/// Animated shimmer placeholder for loading states.
///
/// Uses the `shimmer` package with theme-aware gradient animation.
///
/// ```dart
/// DKLoadingShimmer(width: 200, height: 16)
/// DKLoadingShimmer(width: double.infinity, height: 120, radius: 16)
/// ```
class DKLoadingShimmer extends StatelessWidget {
  const DKLoadingShimmer({
    super.key,
    required this.width,
    required this.height,
    this.radius = KinrelRadius.md,
  });

  /// Width of the shimmer placeholder.
  final double width;

  /// Height of the shimmer placeholder.
  final double height;

  /// Border radius. Default 12.
  final double radius;


  @override
  Widget build(BuildContext context) {
    final isLight = DKColors.isLight(context);

    return Shimmer.fromColors(
      baseColor: isLight
          ? const Color(0xFFE0E0E0)
          : DKColors.darkElevated,
      highlightColor: isLight
          ? const Color(0xFFF5F5F5)
          : DKColors.darkSurface,
      period: const Duration(milliseconds: 1500),
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: isLight ? Colors.white : DKColors.darkCard,
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 16. DKErrorState
// ═══════════════════════════════════════════════════════════════════════

/// Error state with an icon, error message, and retry button.
///
/// ```dart
/// DKErrorState(
///   message: 'Failed to load family data',
///   onRetry: () => _retry(),
/// )
/// ```
class DKErrorState extends StatelessWidget {
  const DKErrorState({
    super.key,
    required this.message,
    required this.onRetry,
    this.icon,
  });

  /// Error message to display.
  final String message;

  /// Retry callback.
  final VoidCallback onRetry;

  /// Optional custom icon. Default [Icons.error_outline_rounded].
  final IconData? icon;


  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(KinrelSpacing.xxl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon ?? Icons.error_outline_rounded,
            size: 48,
            color: DKColors.brandCoral,
          )
              .animate(onPlay: (c) => c.forward())
              .fadeIn(duration: 300.ms)
              .scale(
                begin: const Offset(0.8, 0.8),
                end: const Offset(1.0, 1.0),
                duration: 300.ms,
                curve: Curves.easeOutBack,
              ),
          const SizedBox(height: KinrelSpacing.lg),
          Text(
            message,
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 14,
              fontWeight: FontWeight.w400,
              color: DKColors.textSecondary(context),
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          )
              .animate()
              .fadeIn(duration: 300.ms, delay: 100.ms),
          const SizedBox(height: KinrelSpacing.xl),
          DKButton(
            label: 'Try Again',
            variant: DKButtonVariant.secondary,
            icon: Icons.refresh_rounded,
            onPressed: onRetry,
          )
              .animate()
              .fadeIn(duration: 300.ms, delay: 200.ms)
              .slideY(begin: 0.1, end: 0, duration: 300.ms),
        ],
      ),
    );
  }
}
