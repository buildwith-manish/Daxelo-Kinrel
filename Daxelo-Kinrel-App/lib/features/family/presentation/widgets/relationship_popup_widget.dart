// lib/features/family/presentation/widgets/relationship_popup_widget.dart
//
// DAXELO KINREL — Relationship Popup Widget
//
// A popup widget that shows when an edge dot is tapped, displaying the
// relationship between two persons. Shows both forward and inverse
// directions, plus native-language terms where available.
//
// Features:
//   - Forward: Person A → label → Person B (orange arrow)
//   - Inverse: Person B → inverse label → Person A (gold arrow)
//   - Circular avatar initials for each person
//   - Native-language term shown alongside English
//   - Animated entrance: scale 0.8 → 1.0 + fade in over 200ms
//   - Positioned above or below the dot depending on available space
//   - Close button (X) in top-right corner

import 'package:flutter/material.dart';
import '../../../../core/constants/brand_colors.dart';
import '../../../../core/constants/brand_typography.dart';

// ═══════════════════════════════════════════════════════════════════════
// EXTENDED KINSHIP TERMS LOOKUP
// ═══════════════════════════════════════════════════════════════════════

/// Static lookup map from English relationship keys to Hindi kinship terms.
/// Covers core + extended Indian kinship relationships.
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
  'grandson': 'पोता/नाती',
  'granddaughter': 'पोती/नतनी',
  'uncle': 'चाचा/मामा',
  'aunt': 'बुआ/मौसी',
  'nephew': 'भतीजा/भांजा',
  'niece': 'भतीजी/भांजी',
  'cousin': 'चचेरा भाई/बहन',
  'father_in_law': 'ससुर',
  'mother_in_law': 'सास',
  'son_in_law': 'दामाद',
  'daughter_in_law': 'बहू',
  'brother_in_law': 'साला/जेठ/देवर',
  'sister_in_law': 'साली/भाभी/ननद',
  'paternal_uncle': 'चाचा',
  'paternal_aunt': 'बुआ',
  'maternal_uncle': 'मामा',
  'maternal_aunt': 'मौसी',
  'cousin_brother': 'चचेरा भाई',
  'cousin_sister': 'चचेरी बहन',
  'paternal_grandfather': 'दादा',
  'paternal_grandmother': 'दादी',
  'maternal_grandfather': 'नाना',
  'maternal_grandmother': 'नानी',
  'step_father': 'सौतेले पिता',
  'step_mother': 'सौतेली माँ',
  'half_brother': 'सौतेले भाई',
  'half_sister': 'सौतेली बहन',
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

/// Returns 2-letter initials from a name.
String _getInitials(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return '?';
  final parts = trimmed.split(RegExp(r'\s+'));
  if (parts.length >= 2 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }
  return trimmed.length >= 2
      ? trimmed.substring(0, 2).toUpperCase()
      : trimmed.toUpperCase();
}

// ═══════════════════════════════════════════════════════════════════════
// RELATIONSHIP POPUP WIDGET
// ═══════════════════════════════════════════════════════════════════════

/// A popup widget that shows the relationship between two persons.
///
/// Displays both forward and inverse directions with their respective labels,
/// circular avatar initials, and native-language terms.
class RelationshipPopupWidget extends StatefulWidget {
  const RelationshipPopupWidget({
    super.key,
    required this.personAName,
    required this.personBName,
    this.personAGender,
    this.personBGender,
    required this.forwardKey,
    required this.inverseKey,
    this.forwardNative,
    this.inverseNative,
    required this.dotPosition,
    required this.canvasSize,
    required this.onClose,
  });

  final String personAName;
  final String personBName;
  final String? personAGender;
  final String? personBGender;
  final String forwardKey;
  final String inverseKey;
  final String? forwardNative;
  final String? inverseNative;
  final Offset dotPosition;
  final Size canvasSize;
  final VoidCallback onClose;

  @override
  State<RelationshipPopupWidget> createState() =>
      _RelationshipPopupWidgetState();
}

class _RelationshipPopupWidgetState extends State<RelationshipPopupWidget>
    with SingleTickerProviderStateMixin {
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
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  bool get _showAbove {
    return widget.dotPosition.dy > 220;
  }

  @override
  Widget build(BuildContext context) {
    const popupWidth = 300.0;

    double left = widget.dotPosition.dx - popupWidth / 2;
    left = left.clamp(8.0, widget.canvasSize.width - popupWidth - 8.0);

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
              alignment: _showAbove ? Alignment.bottomCenter : Alignment.topCenter,
              child: child,
            ),
          );
        },
        child: _buildPopupContent(popupWidth),
      ),
    );
  }

  double _estimatedPopupHeight() => 200.0;

  Widget _buildPopupContent(double width) {
    final forwardLabel = formatRelationshipKey(widget.forwardKey);
    final inverseLabel = formatRelationshipKey(widget.inverseKey);
    final forwardNative = widget.forwardNative ?? hindiKinshipTerms[widget.forwardKey];
    final inverseNative = widget.inverseNative ?? hindiKinshipTerms[widget.inverseKey];

    return Container(
      width: width,
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(16.0),
        border: Border.all(color: const Color(0x4DE8612A), width: 1.0),
        boxShadow: const [
          BoxShadow(color: Color(0x66000000), blurRadius: 32.0, offset: Offset(0, 8)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(),
          Container(height: 1.0, margin: const EdgeInsets.symmetric(horizontal: 16.0), color: const Color(0x1AFFFFFF)),
          const SizedBox(height: 12.0),
          _buildRelationshipRow(
            personFrom: widget.personAName,
            personFromGender: widget.personAGender,
            label: forwardLabel,
            personTo: widget.personBName,
            personToGender: widget.personBGender,
            nativeTerm: forwardNative,
            arrowColor: KinrelColors.orange,
          ),
          const SizedBox(height: 12.0),
          _buildRelationshipRow(
            personFrom: widget.personBName,
            personFromGender: widget.personBGender,
            label: inverseLabel,
            personTo: widget.personAName,
            personToGender: widget.personAGender,
            nativeTerm: inverseNative,
            arrowColor: KinrelColors.gold,
          ),
          const SizedBox(height: 16.0),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16.0, 12.0, 8.0, 12.0),
      child: Row(
        children: [
          Text('Relationship', style: TextStyle(fontFamily: KinrelTypography.displayFont, fontSize: 13.0, fontWeight: FontWeight.w600, color: KinrelColors.textWhite)),
          const Spacer(),
          GestureDetector(
            onTap: widget.onClose,
            behavior: HitTestBehavior.opaque,
            child: Container(
              width: 28.0, height: 28.0,
              decoration: BoxDecoration(shape: BoxShape.circle, color: KinrelColors.darkElevated),
              alignment: Alignment.center,
              child: Icon(Icons.close, size: 14.0, color: KinrelColors.textDim),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRelationshipRow({
    required String personFrom,
    String? personFromGender,
    required String label,
    required String personTo,
    String? personToGender,
    required String? nativeTerm,
    required Color arrowColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _buildMiniAvatar(personFrom, personFromGender),
              const SizedBox(width: 6.0),
              Flexible(child: Text(personFrom, style: TextStyle(fontFamily: KinrelTypography.displayFont, fontSize: 12.0, fontWeight: FontWeight.w600, color: KinrelColors.textWhite), overflow: TextOverflow.ellipsis, maxLines: 1)),
              const SizedBox(width: 4.0),
              Icon(Icons.arrow_forward, size: 14.0, color: arrowColor),
              const SizedBox(width: 4.0),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 2.0),
                decoration: BoxDecoration(color: arrowColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6.0)),
                child: Text(label, style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 11.0, fontWeight: FontWeight.w500, color: KinrelColors.textSecondaryDark)),
              ),
              const SizedBox(width: 4.0),
              Icon(Icons.arrow_forward, size: 14.0, color: arrowColor),
              const SizedBox(width: 4.0),
              Flexible(child: Text(personTo, style: TextStyle(fontFamily: KinrelTypography.displayFont, fontSize: 12.0, fontWeight: FontWeight.w600, color: KinrelColors.textWhite), overflow: TextOverflow.ellipsis, maxLines: 1)),
              const SizedBox(width: 6.0),
              _buildMiniAvatar(personTo, personToGender),
            ],
          ),
        ],
      ),
    );
  }

  /// Builds a small circular avatar with 2-letter initials.
  Widget _buildMiniAvatar(String name, String? gender) {
    final initials = _getInitials(name);
    final borderColor = gender == 'male'
        ? KinrelColors.blue
        : gender == 'female'
            ? KinrelColors.coral
            : KinrelColors.textDim;

    return Container(
      width: 24.0,
      height: 24.0,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: KinrelColors.darkElevated,
        border: Border.all(color: borderColor.withValues(alpha: 0.6), width: 1.5),
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: TextStyle(
          fontFamily: KinrelTypography.displayFont,
          fontSize: 9.0,
          fontWeight: FontWeight.w600,
          color: KinrelColors.textWhite,
        ),
      ),
    );
  }
}
