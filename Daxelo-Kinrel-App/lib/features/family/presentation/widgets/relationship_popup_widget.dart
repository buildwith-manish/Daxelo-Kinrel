// lib/features/family/presentation/widgets/relationship_popup_widget.dart
//
// DAXELO KINREL — Relationship Popup Widget
//
// A popup widget that shows when an edge dot is tapped, displaying the
// relationship between two persons. Shows both forward and inverse
// directions, plus Hindi terms where available.
//
// Features:
//   - Forward: Person A → label → Person B (orange arrow)
//   - Inverse: Person B → inverse label → Person A (gold arrow)
//   - Hindi terms displayed below English labels
//   - Animated entrance: scale 0.8 → 1.0 + fade in over 200ms
//   - Positioned above or below the dot depending on available space
//   - Close button (X) in top-right corner

import 'package:flutter/material.dart';
import '../../../../core/constants/brand_colors.dart';
import '../../../../core/constants/brand_typography.dart';

// ═══════════════════════════════════════════════════════════════════════
// HINDI KINSHIP TERMS LOOKUP
// ═══════════════════════════════════════════════════════════════════════

/// Static lookup map from English relationship keys to Hindi kinship terms.
const Map<String, String> hindiKinshipTerms = {
  'father': 'पिता',
  'mother': 'माँ',
  'son': 'बेटा',
  'daughter': 'बेटी',
  'brother': 'भाई',
  'sister': 'बहन',
  'husband': 'पति',
  'wife': 'पत्नी',
  'grandfather': 'दादा/नाना',
  'grandmother': 'दादी/नानी',
  'uncle': 'चाचा/मामा',
  'aunt': 'बुआ/मौसी',
  'nephew': 'भतीजा/भांजा',
  'niece': 'भतीजी/भांजी',
  'cousin': 'चचेरा भाई/बहन',
  'father_in_law': 'ससुर',
  'mother_in_law': 'सास',
  'son_in_law': 'दामाद',
  'daughter_in_law': 'बहू',
};

// ═══════════════════════════════════════════════════════════════════════
// HELPER FUNCTIONS
// ═══════════════════════════════════════════════════════════════════════

/// Formats a relationship key like 'father_in_law' → 'Father In Law'.
String formatRelationshipKey(String key) {
  return key
      .replaceAll('_', ' ')
      .split(' ')
      .map((w) => w.isEmpty ? '' : w[0].toUpperCase() + w.substring(1))
      .join(' ');
}

// ═══════════════════════════════════════════════════════════════════════
// RELATIONSHIP POPUP WIDGET
// ═══════════════════════════════════════════════════════════════════════

/// A popup widget that shows the relationship between two persons.
///
/// Displays both forward (Person A → Person B) and inverse (Person B → Person A)
/// directions with their respective labels and Hindi terms.
///
/// Usage:
/// ```dart
/// if (showPopup)
///   RelationshipPopupWidget(
///     personAName: 'Rahul',
///     personBName: 'Priya',
///     forwardKey: 'husband',
///     inverseKey: 'wife',
///     forwardHindi: 'पति',
///     inverseHindi: 'पत्नी',
///     dotPosition: Offset(200, 150),
///     canvasSize: Size(800, 600),
///     onClose: () => setState(() => showPopup = false),
///   ),
/// ```
class RelationshipPopupWidget extends StatefulWidget {
  const RelationshipPopupWidget({
    super.key,
    required this.personAName,
    required this.personBName,
    required this.forwardKey,
    required this.inverseKey,
    this.forwardHindi,
    this.inverseHindi,
    required this.dotPosition,
    required this.canvasSize,
    required this.onClose,
  });

  /// Name of Person A (the "from" person in the relationship).
  final String personAName;

  /// Name of Person B (the "to" person in the relationship).
  final String personBName;

  /// Forward relationship key (e.g., 'brother').
  final String forwardKey;

  /// Inverse relationship key (e.g., 'sister').
  final String inverseKey;

  /// Hindi term for forward relationship (optional).
  final String? forwardHindi;

  /// Hindi term for inverse relationship (optional).
  final String? inverseHindi;

  /// Position of the edge dot (for positioning the popup).
  final Offset dotPosition;

  /// Size of the canvas (for boundary checking).
  final Size canvasSize;

  /// Callback to close the popup.
  final VoidCallback onClose;

  @override
  State<RelationshipPopupWidget> createState() =>
      _RelationshipPopupWidgetState();
}

class _RelationshipPopupWidgetState extends State<RelationshipPopupWidget>
    with SingleTickerProviderStateMixin {
  // ── Animation ──────────────────────────────────────────────────────

  late final AnimationController _animationController;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeOut,
      ),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeOut,
      ),
    );

    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  // ── Positioning ────────────────────────────────────────────────────

  /// Whether the popup should be placed above the dot.
  /// If there's not enough space above, place it below.
  bool get _showAbove {
    const popupHeight = 200.0; // approximate popup height
    return widget.dotPosition.dy > popupHeight + 20;
  }

  // ── Build ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    const popupWidth = 280.0;

    // Calculate horizontal position: center on dot, but clamp to canvas
    double left = widget.dotPosition.dx - popupWidth / 2;
    left = left.clamp(8.0, widget.canvasSize.width - popupWidth - 8.0);

    // Calculate vertical position: above or below dot
    final double top;
    if (_showAbove) {
      top = widget.dotPosition.dy - 20 - _estimatedPopupHeight();
    } else {
      top = widget.dotPosition.dy + 24;
    }

    return Positioned(
      left: left,
      top: top.clamp(8.0, widget.canvasSize.height - _estimatedPopupHeight() - 8.0),
      child: AnimatedBuilder(
        animation: _animationController,
        builder: (context, child) {
          return Opacity(
            opacity: _fadeAnimation.value,
            child: Transform.scale(
              scale: _scaleAnimation.value,
              alignment: _showAbove
                  ? Alignment.bottomCenter
                  : Alignment.topCenter,
              child: child,
            ),
          );
        },
        child: _buildPopupContent(popupWidth),
      ),
    );
  }

  /// Estimates the popup height for positioning purposes.
  double _estimatedPopupHeight() {
    // Approximate: header + forward row + inverse row + padding
    double height = 44.0; // header with close button
    height += 64.0; // forward row (name + label + name + optional hindi)
    height += 64.0; // inverse row
    height += 24.0; // bottom padding
    return height;
  }

  /// Builds the actual popup card content.
  Widget _buildPopupContent(double width) {
    final forwardLabel = formatRelationshipKey(widget.forwardKey);
    final inverseLabel = formatRelationshipKey(widget.inverseKey);
    final forwardHindi = widget.forwardHindi ?? hindiKinshipTerms[widget.forwardKey];
    final inverseHindi = widget.inverseHindi ?? hindiKinshipTerms[widget.inverseKey];

    return Container(
      width: width,
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(16.0),
        border: Border.all(
          color: const Color(0x4DE8612A), // rgba(232, 97, 42, 0.3)
          width: 1.0,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000), // rgba(0, 0, 0, 0.4)
            blurRadius: 32.0,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header with close button ────────────────────────────
          _buildHeader(),

          // ── Divider ─────────────────────────────────────────────
          Container(
            height: 1.0,
            margin: const EdgeInsets.symmetric(horizontal: 16.0),
            color: const Color(0x1AFFFFFF), // rgba(255, 255, 255, 0.10)
          ),

          const SizedBox(height: 12.0),

          // ── Forward direction ───────────────────────────────────
          _buildRelationshipRow(
            personFrom: widget.personAName,
            label: forwardLabel,
            personTo: widget.personBName,
            hindiTerm: forwardHindi,
            arrowColor: KinrelColors.orange,
          ),

          const SizedBox(height: 12.0),

          // ── Inverse direction ───────────────────────────────────
          _buildRelationshipRow(
            personFrom: widget.personBName,
            label: inverseLabel,
            personTo: widget.personAName,
            hindiTerm: inverseHindi,
            arrowColor: KinrelColors.gold,
          ),

          const SizedBox(height: 16.0),
        ],
      ),
    );
  }

  /// Builds the popup header with a close button.
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16.0, 12.0, 8.0, 12.0),
      child: Row(
        children: [
          Text(
            'Relationship',
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 13.0,
              fontWeight: FontWeight.w600,
              color: KinrelColors.textWhite,
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: widget.onClose,
            behavior: HitTestBehavior.opaque,
            child: Container(
              width: 28.0,
              height: 28.0,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: KinrelColors.darkElevated,
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.close,
                size: 14.0,
                color: KinrelColors.textDim,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Builds a single relationship row: PersonFrom → Label → PersonTo.
  Widget _buildRelationshipRow({
    required String personFrom,
    required String label,
    required String personTo,
    required String? hindiTerm,
    required Color arrowColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Row: PersonFrom → Label → PersonTo
          Row(
            children: [
              // Person from
              Flexible(
                child: Text(
                  personFrom,
                  style: TextStyle(
                    fontFamily: KinrelTypography.displayFont,
                    fontSize: 12.0,
                    fontWeight: FontWeight.w600,
                    color: KinrelColors.textWhite,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),

              const SizedBox(width: 6.0),

              // Arrow icon
              Icon(
                Icons.arrow_forward,
                size: 14.0,
                color: arrowColor,
              ),

              const SizedBox(width: 6.0),

              // Label
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8.0,
                  vertical: 2.0,
                ),
                decoration: BoxDecoration(
                  color: arrowColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6.0),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 11.0,
                    fontWeight: FontWeight.w500,
                    color: KinrelColors.textSecondaryDark,
                  ),
                ),
              ),

              const SizedBox(width: 6.0),

              // Arrow icon
              Icon(
                Icons.arrow_forward,
                size: 14.0,
                color: arrowColor,
              ),

              const SizedBox(width: 6.0),

              // Person to
              Flexible(
                child: Text(
                  personTo,
                  style: TextStyle(
                    fontFamily: KinrelTypography.displayFont,
                    fontSize: 12.0,
                    fontWeight: FontWeight.w600,
                    color: KinrelColors.textWhite,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            ],
          ),

          // Hindi term (if available)
          if (hindiTerm != null) ...[
            const SizedBox(height: 4.0),
            Padding(
              padding: const EdgeInsets.only(left: 4.0),
              child: Text(
                hindiTerm,
                style: TextStyle(
                  fontFamily: 'NotoSansDevanagari',
                  fontSize: 11.0,
                  fontWeight: FontWeight.w400,
                  color: KinrelColors.textDim,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
