import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/constants/supported_languages.dart';
import '../providers/festival_cards_provider.dart';

class FestivalCardsScreen extends ConsumerStatefulWidget {
  const FestivalCardsScreen({super.key});

  @override
  ConsumerState<FestivalCardsScreen> createState() =>
      _FestivalCardsScreenState();
}

class _FestivalCardsScreenState extends ConsumerState<FestivalCardsScreen> {
  final _kinshipTermController = TextEditingController();
  final _relationshipKeyController = TextEditingController();

  @override
  void dispose() {
    _kinshipTermController.dispose();
    _relationshipKeyController.dispose();
    super.dispose();
  }

  /// Get festival color from KinrelColors based on festival name
  Color _getFestivalColor(String festivalName) {
    switch (festivalName.toLowerCase()) {
      case 'diwali':
        return KinrelColors.diwaliGold;
      case 'holi':
        return KinrelColors.holiPink;
      case 'eid':
        return KinrelColors.eidGreen;
      case 'navratri':
        return KinrelColors.navratriRed;
      case 'onam':
        return KinrelColors.onamYellow;
      case 'baisakhi':
        return KinrelColors.baisakhiOrange;
      case 'pongal':
        return KinrelColors.pongalBrown;
      case 'durga puja':
        return KinrelColors.durgaPurple;
      case 'raksha bandhan':
        return KinrelColors.holiPink;
      case 'bhai dooj':
        return KinrelColors.baisakhiOrange;
      default:
        return KinrelColors.amber;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cardsState = ref.watch(festivalCardsProvider);
    final templatesAsync = ref.watch(festivalTemplatesProvider);

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
        ),
        child: SafeArea(
          child: Column(
            children: [
              // ── Header ────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.all(KinrelSpacing.base),
                child: Row(
                  children: [
                    if (cardsState.selectedFestival != null)
                      IconButton(
                        icon: const Icon(Icons.arrow_back,
                            color: KinrelColors.textWhite),
                        onPressed: () {
                          ref
                              .read(festivalCardsProvider.notifier)
                              .resetToTemplates();
                          _kinshipTermController.clear();
                          _relationshipKeyController.clear();
                        },
                      ),
                    if (cardsState.selectedFestival == null)
                      const SizedBox(width: 48),
                    const SizedBox(width: 8),
                    Text(
                      cardsState.selectedFestival != null
                          ? cardsState.selectedFestival!.name
                          : 'Festival Cards',
                      style: TextStyle(
                        fontFamily: KinrelTypography.displayFont,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: KinrelColors.textWhite,
                      ),
                    ),
                    const Spacer(),
                  ],
                ),
              ),

              // ── Content ───────────────────────────────────────────
              Expanded(
                child: cardsState.isGenerating
                    ? _GeneratingView(festival: cardsState.selectedFestival)
                    : cardsState.imageBase64 != null
                        ? _CardPreviewView(
                            imageBase64: cardsState.imageBase64!,
                            festival: cardsState.festival,
                            kinshipTerm: cardsState.kinshipTerm,
                            onBack: () {
                              ref
                                  .read(festivalCardsProvider.notifier)
                                  .clearCard();
                            },
                          )
                        : cardsState.selectedFestival != null
                            ? _CustomizationForm(
                                kinshipTermController: _kinshipTermController,
                                relationshipKeyController:
                                    _relationshipKeyController,
                                festivalColor: _getFestivalColor(
                                    cardsState.selectedFestival!.name),
                              )
                            : _FestivalGrid(
                                templatesAsync: templatesAsync,
                                festivalColorProvider: _getFestivalColor,
                              ),
              ),

              // ── Error Banner ──────────────────────────────────────
              if (cardsState.error != null)
                Container(
                  margin: const EdgeInsets.all(KinrelSpacing.base),
                  padding: const EdgeInsets.all(KinrelSpacing.md),
                  decoration: BoxDecoration(
                    color: KinrelColors.error.withValues(alpha: 0.15),
                    borderRadius:
                        BorderRadius.circular(KinrelSpacing.radiusMd),
                    border: Border.all(
                        color: KinrelColors.error.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline,
                          color: KinrelColors.error, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          cardsState.error!,
                          style: TextStyle(
                            fontFamily: KinrelTypography.bodyFont,
                            fontSize: 13,
                            color: KinrelColors.error,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Festival Grid ───────────────────────────────────────────────

class _FestivalGrid extends StatelessWidget {
  final AsyncValue<List<FestivalTemplate>> templatesAsync;
  final Color Function(String) festivalColorProvider;

  const _FestivalGrid({
    required this.templatesAsync,
    required this.festivalColorProvider,
  });

  @override
  Widget build(BuildContext context) {
    return templatesAsync.when(
      data: (templates) => GridView.builder(
        padding: const EdgeInsets.all(KinrelSpacing.base),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 0.85,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: templates.length,
        itemBuilder: (context, index) {
          final template = templates[index];
          final festivalColor = festivalColorProvider(template.name);
          return _FestivalCard(
            template: template,
            festivalColor: festivalColor,
          );
        },
      ),
      loading: () => GridView.builder(
        padding: const EdgeInsets.all(KinrelSpacing.base),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 0.85,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: 10,
        itemBuilder: (context, index) => Container(
          decoration: BoxDecoration(
            color: KinrelColors.darkCard,
            borderRadius: BorderRadius.circular(KinrelSpacing.radiusLg),
          ),
        ),
      ),
      error: (_, __) => Center(
        child: Text(
          'Failed to load templates',
          style: TextStyle(
            color: KinrelColors.textDim,
            fontFamily: KinrelTypography.bodyFont,
          ),
        ),
      ),
    );
  }
}

class _FestivalCard extends ConsumerWidget {
  final FestivalTemplate template;
  final Color festivalColor;

  const _FestivalCard({
    required this.template,
    required this.festivalColor,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: () {
        ref.read(festivalCardsProvider.notifier).selectFestival(template);
      },
      child: Container(
        decoration: BoxDecoration(
          color: KinrelColors.darkCard,
          borderRadius: BorderRadius.circular(KinrelSpacing.radiusLg),
          border: Border.all(
              color: festivalColor.withValues(alpha: 0.2)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Festival emoji icon
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: festivalColor.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  template.icon,
                  style: const TextStyle(fontSize: 28),
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Festival name
            Text(
              template.name,
              style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: KinrelColors.textWhite,
              ),
            ),

            const SizedBox(height: 4),

            // Color indicator
            Container(
              width: 40,
              height: 3,
              decoration: BoxDecoration(
                color: festivalColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Customization Form ──────────────────────────────────────────

class _CustomizationForm extends ConsumerStatefulWidget {
  final TextEditingController kinshipTermController;
  final TextEditingController relationshipKeyController;
  final Color festivalColor;

  const _CustomizationForm({
    required this.kinshipTermController,
    required this.relationshipKeyController,
    required this.festivalColor,
  });

  @override
  ConsumerState<_CustomizationForm> createState() =>
      _CustomizationFormState();
}

class _CustomizationFormState extends ConsumerState<_CustomizationForm>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cardsState = ref.watch(festivalCardsProvider);

    return Column(
      children: [
        // Tab bar
        Container(
          margin: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
          decoration: BoxDecoration(
            color: KinrelColors.darkCard,
            borderRadius: BorderRadius.circular(KinrelSpacing.radiusMd),
          ),
          child: TabBar(
            controller: _tabController,
            indicator: BoxDecoration(
              color: widget.festivalColor.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(KinrelSpacing.radiusMd),
            ),
            indicatorSize: TabBarIndicatorSize.tab,
            dividerColor: Colors.transparent,
            labelColor: KinrelColors.textWhite,
            unselectedLabelColor: KinrelColors.textDim,
            labelStyle: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
            unselectedLabelStyle: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 13,
              fontWeight: FontWeight.w400,
            ),
            tabs: const [
              Tab(text: 'Festival Card'),
              Tab(text: 'Kinship Card'),
            ],
          ),
        ),

        const SizedBox(height: KinrelSpacing.md),

        // Tab content
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _FestivalCardForm(
                kinshipTermController: widget.kinshipTermController,
                festivalColor: widget.festivalColor,
              ),
              _KinshipCardForm(
                relationshipKeyController: widget.relationshipKeyController,
                festivalColor: widget.festivalColor,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FestivalCardForm extends ConsumerWidget {
  final TextEditingController kinshipTermController;
  final Color festivalColor;

  const _FestivalCardForm({
    required this.kinshipTermController,
    required this.festivalColor,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cardsState = ref.watch(festivalCardsProvider);
    final notifier = ref.read(festivalCardsProvider.notifier);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(KinrelSpacing.base),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Festival preview
          Center(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(KinrelSpacing.xl),
              decoration: BoxDecoration(
                color: KinrelColors.darkCard,
                borderRadius: BorderRadius.circular(KinrelSpacing.radiusLg),
                border: Border.all(
                    color: festivalColor.withValues(alpha: 0.3)),
              ),
              child: Column(
                children: [
                  Text(
                    cardsState.selectedFestival?.icon ?? '',
                    style: const TextStyle(fontSize: 48),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    cardsState.selectedFestival?.name ?? '',
                    style: TextStyle(
                      fontFamily: KinrelTypography.displayFont,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: festivalColor,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: KinrelSpacing.xl),

          // Kinship term input
          Text(
            'Kinship Term',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: KinrelColors.textSilver,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: kinshipTermController,
            style: const TextStyle(color: KinrelColors.textWhite),
            decoration: InputDecoration(
              hintText: 'e.g., Chacha, Bua, Mami...',
              hintStyle: TextStyle(color: KinrelColors.textDim),
              filled: true,
              fillColor: KinrelColors.darkElevated,
              border: OutlineInputBorder(
                borderRadius:
                    BorderRadius.circular(KinrelSpacing.radiusMd),
                borderSide: BorderSide.none,
              ),
              prefixIcon: Icon(Icons.family_restroom,
                  color: festivalColor, size: 20),
            ),
            onChanged: (value) => notifier.setKinshipTermInput(value),
          ),

          const SizedBox(height: KinrelSpacing.lg),

          // Language picker
          Text(
            'Language',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: KinrelColors.textSilver,
            ),
          ),
          const SizedBox(height: 8),
          _LanguageDropdown(
            selectedLanguage: cardsState.selectedLanguage,
            onLanguageChanged: (lang) => notifier.setLanguage(lang),
          ),

          const SizedBox(height: KinrelSpacing.lg),

          // Style picker
          Text(
            'Card Style',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: KinrelColors.textSilver,
            ),
          ),
          const SizedBox(height: 8),
          _StylePicker(
            selectedStyle: cardsState.selectedStyle,
            onStyleChanged: (style) => notifier.setStyle(style),
            festivalColor: festivalColor,
          ),

          const SizedBox(height: KinrelSpacing.xxl),

          // Generate button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: cardsState.kinshipTermInput.trim().isEmpty
                  ? null
                  : () => notifier.generateFestivalCard(),
              style: ElevatedButton.styleFrom(
                backgroundColor: festivalColor,
                foregroundColor: KinrelColors.darkBackground,
                shape: RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(KinrelSpacing.radiusMd),
                ),
                disabledBackgroundColor:
                    festivalColor.withValues(alpha: 0.3),
              ),
              child: Text(
                'Generate Festival Card',
                style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _KinshipCardForm extends ConsumerWidget {
  final TextEditingController relationshipKeyController;
  final Color festivalColor;

  const _KinshipCardForm({
    required this.relationshipKeyController,
    required this.festivalColor,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cardsState = ref.watch(festivalCardsProvider);
    final notifier = ref.read(festivalCardsProvider.notifier);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(KinrelSpacing.base),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Info card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(KinrelSpacing.md),
            decoration: BoxDecoration(
              color: KinrelColors.darkCard,
              borderRadius: BorderRadius.circular(KinrelSpacing.radiusMd),
              border: Border.all(
                  color: KinrelColors.darkSurface.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: festivalColor, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Enter a relationship key (e.g., fathers_younger_brother) to generate a beautiful kinship card.',
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 12,
                      color: KinrelColors.textSilver,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: KinrelSpacing.xl),

          // Relationship key input
          Text(
            'Relationship Key',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: KinrelColors.textSilver,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: relationshipKeyController,
            style: const TextStyle(color: KinrelColors.textWhite),
            decoration: InputDecoration(
              hintText: 'e.g., fathers_younger_brother, mothers_brother...',
              hintStyle: TextStyle(color: KinrelColors.textDim),
              filled: true,
              fillColor: KinrelColors.darkElevated,
              border: OutlineInputBorder(
                borderRadius:
                    BorderRadius.circular(KinrelSpacing.radiusMd),
                borderSide: BorderSide.none,
              ),
              prefixIcon:
                  Icon(Icons.link, color: festivalColor, size: 20),
            ),
            onChanged: (value) => notifier.setRelationshipKeyInput(value),
          ),

          const SizedBox(height: KinrelSpacing.lg),

          // Language picker
          Text(
            'Language',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: KinrelColors.textSilver,
            ),
          ),
          const SizedBox(height: 8),
          _LanguageDropdown(
            selectedLanguage: cardsState.selectedLanguage,
            onLanguageChanged: (lang) => notifier.setLanguage(lang),
          ),

          const SizedBox(height: KinrelSpacing.lg),

          // Style picker
          Text(
            'Card Style',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: KinrelColors.textSilver,
            ),
          ),
          const SizedBox(height: 8),
          _StylePicker(
            selectedStyle: cardsState.selectedStyle,
            onStyleChanged: (style) => notifier.setStyle(style),
            festivalColor: festivalColor,
          ),

          const SizedBox(height: KinrelSpacing.xxl),

          // Generate button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: cardsState.relationshipKeyInput.trim().isEmpty
                  ? null
                  : () => notifier.generateKinshipCard(),
              style: ElevatedButton.styleFrom(
                backgroundColor: festivalColor,
                foregroundColor: KinrelColors.darkBackground,
                shape: RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(KinrelSpacing.radiusMd),
                ),
                disabledBackgroundColor:
                    festivalColor.withValues(alpha: 0.3),
              ),
              child: Text(
                'Generate Kinship Card',
                style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Language Dropdown ───────────────────────────────────────────

class _LanguageDropdown extends StatelessWidget {
  final SupportedLanguage selectedLanguage;
  final ValueChanged<SupportedLanguage> onLanguageChanged;

  const _LanguageDropdown({
    required this.selectedLanguage,
    required this.onLanguageChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: KinrelColors.darkElevated,
        borderRadius: BorderRadius.circular(KinrelSpacing.radiusMd),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<SupportedLanguage>(
          value: selectedLanguage,
          isExpanded: true,
          icon: const Icon(Icons.arrow_drop_down, color: KinrelColors.orange),
          dropdownColor: KinrelColors.darkElevated,
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 14,
            color: KinrelColors.textWhite,
          ),
          items: SupportedLanguage.values
              .map((lang) => DropdownMenuItem(
                    value: lang,
                    child: Text('${lang.nativeName} (${lang.name})'),
                  ))
              .toList(),
          onChanged: (lang) {
            if (lang != null) onLanguageChanged(lang);
          },
        ),
      ),
    );
  }
}

// ── Style Picker ────────────────────────────────────────────────

class _StylePicker extends StatelessWidget {
  final CardStyle selectedStyle;
  final ValueChanged<CardStyle> onStyleChanged;
  final Color festivalColor;

  const _StylePicker({
    required this.selectedStyle,
    required this.onStyleChanged,
    required this.festivalColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: CardStyle.values.map((style) {
        final isSelected = style == selectedStyle;
        return Expanded(
          child: GestureDetector(
            onTap: () => onStyleChanged(style),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: isSelected
                    ? festivalColor.withValues(alpha: 0.2)
                    : KinrelColors.darkElevated,
                borderRadius:
                    BorderRadius.circular(KinrelSpacing.radiusMd),
                border: Border.all(
                  color: isSelected
                      ? festivalColor
                      : KinrelColors.darkSurface.withValues(alpha: 0.3),
                ),
              ),
              child: Center(
                child: Text(
                  style.name[0].toUpperCase() + style.name.substring(1),
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 12,
                    fontWeight:
                        isSelected ? FontWeight.w600 : FontWeight.w400,
                    color: isSelected
                        ? festivalColor
                        : KinrelColors.textDim,
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ── Generating View ─────────────────────────────────────────────

class _GeneratingView extends StatefulWidget {
  final FestivalTemplate? festival;

  const _GeneratingView({this.festival});

  @override
  State<_GeneratingView> createState() => _GeneratingViewState();
}

class _GeneratingViewState extends State<_GeneratingView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Animated icon
          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return Transform.scale(
                scale: 1.0 + 0.1 * math.sin(_controller.value * 2 * 3.14159),
                child: Text(
                  widget.festival?.icon ?? '🎨',
                  style: const TextStyle(fontSize: 64),
                ),
              );
            },
          ),

          const SizedBox(height: 32),

          // Progress indicator
          const SizedBox(
            width: 200,
            child: LinearProgressIndicator(
              color: KinrelColors.orange,
              backgroundColor: KinrelColors.darkSurface,
              borderRadius: BorderRadius.all(Radius.circular(4)),
            ),
          ),

          const SizedBox(height: 24),

          Text(
            'Creating your card...',
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: KinrelColors.textWhite,
            ),
          ),

          const SizedBox(height: 8),

          Text(
            'AI is crafting a beautiful greeting for you',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 13,
              color: KinrelColors.textDim,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Card Preview View ───────────────────────────────────────────

class _CardPreviewView extends StatelessWidget {
  final String imageBase64;
  final String? festival;
  final String? kinshipTerm;
  final VoidCallback onBack;

  const _CardPreviewView({
    required this.imageBase64,
    this.festival,
    this.kinshipTerm,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(KinrelSpacing.base),
      child: Column(
        children: [
          // Card image
          Container(
            constraints: const BoxConstraints(maxHeight: 500),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(KinrelSpacing.radiusLg),
              boxShadow: [
                BoxShadow(
                  color: KinrelColors.orangeGlow,
                  blurRadius: 30,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(KinrelSpacing.radiusLg),
              child: Image.memory(
                base64Decode(imageBase64),
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    width: double.infinity,
                    height: 400,
                    decoration: BoxDecoration(
                      color: KinrelColors.darkCard,
                      borderRadius:
                          BorderRadius.circular(KinrelSpacing.radiusLg),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.image,
                            size: 64,
                            color: KinrelColors.textDim.withValues(alpha: 0.5)),
                        const SizedBox(height: 16),
                        Text(
                          'Card generated successfully',
                          style: TextStyle(
                            fontFamily: KinrelTypography.bodyFont,
                            fontSize: 16,
                            color: KinrelColors.textSilver,
                          ),
                        ),
                        if (festival != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            '$festival Card for $kinshipTerm',
                            style: TextStyle(
                              fontFamily: KinrelTypography.displayFont,
                              fontSize: 14,
                              color: KinrelColors.amber,
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ),
          ),

          const SizedBox(height: KinrelSpacing.xl),

          // Action buttons
          Row(
            children: [
              // Back / Create Another
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onBack,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Create Another'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: KinrelColors.textSilver,
                    side: BorderSide(
                        color: KinrelColors.darkSurface.withValues(alpha: 0.5)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(KinrelSpacing.radiusMd),
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 12),

              // Share button
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    // In production, this would use share_plus or similar
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Share functionality coming soon!'),
                        backgroundColor: KinrelColors.darkCard,
                      ),
                    );
                  },
                  icon: const Icon(Icons.share, size: 18),
                  label: const Text('Share'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: KinrelColors.orange,
                    foregroundColor: KinrelColors.textWhite,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(KinrelSpacing.radiusMd),
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // WhatsApp share button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('WhatsApp share coming soon!'),
                    backgroundColor: Color(0xFF25D366),
                  ),
                );
              },
              icon: const Icon(Icons.chat, size: 18),
              label: const Text('Share on WhatsApp'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF25D366),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(KinrelSpacing.radiusMd),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}


