// lib/features/profile/presentation/settings/settings_hub_screen.dart
//
// DAXELO KINREL — Settings hub (Screen 2 in the redesign spec).
//
// Shown when the user taps the gear icon on the Me tab. Renders:
//   1. A search field that filters the flat settings registry.
//   2. An Easy Mode (Grandparent Mode) card with a toggle.
//   3. The six category rows with live one-line summaries.
//   4. A centered red "Sign out" text button at the bottom.
//
// Lives inside the ShellRoute so the bottom nav stays visible with
// the Me tab highlighted.

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/brand_colors.dart';
import '../../../../core/constants/brand_spacing.dart';
import '../../../../core/constants/brand_typography.dart';
import '../../../../shared/widgets/dk_components.dart';
import '../../../grandparent_mode/grandparent_mode_profile.dart';
import 'settings_actions.dart';
import 'settings_providers.dart';
import 'settings_registry.dart';
import 'settings_widgets.dart';

class SettingsHubScreen extends ConsumerStatefulWidget {
  const SettingsHubScreen({super.key});

  @override
  ConsumerState<SettingsHubScreen> createState() => _SettingsHubScreenState();
}

class _SettingsHubScreenState extends ConsumerState<SettingsHubScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    // Warm up settings bootstrap so the live summaries show real values
    // as soon as the hub opens. Also load the app version into
    // [appVersionProvider] so the Help & about summary shows
    // "version x.y.z" instead of the placeholder dash.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(settingsBootstrapProvider.future).catchError((_) {});
      _loadVersion();
    });
  }

  Future<void> _loadVersion() async {
    final v = await loadAppVersionInfo();
    if (!mounted) return;
    ref.read(appVersionProvider.notifier).state = v.version;
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bg = DKColors.background(context);
    final cardBg = DKColors.cardColor(context);
    final textPrimary = DKColors.textPrimary(context);
    final textSecondary = DKColors.textSecondary(context);
    final textDim = DKColors.isLight(context)
        ? const Color(0xFF6B7280)
        : const Color(0xFF8A7A72);
    final borderSubtle = DKColors.borderColor(context);

    final isSearching = _query.trim().isNotEmpty;
    final results = isSearching ? searchSettings(_query) : const <SettingsRegistryEntry>[];

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header: back + title ─────────────────────────────────
            _buildHeader(
              context,
              textPrimary: textPrimary,
              textDim: textDim,
              borderSubtle: borderSubtle,
            ),

            // ── Search field ────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: KinrelSpacing.base,
                vertical: 8,
              ),
              child: Container(
                height: 46,
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: borderSubtle),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Icon(Icons.search, color: textDim, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _searchCtrl,
                        onChanged: (v) => setState(() => _query = v),
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 14,
                          color: textPrimary,
                        ),
                        decoration: InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          hintText: 'Search settings',
                          hintStyle: TextStyle(
                            fontFamily: KinrelTypography.bodyFont,
                            fontSize: 14,
                            color: textDim,
                          ),
                        ),
                      ),
                    ),
                    if (_query.isNotEmpty)
                      GestureDetector(
                        onTap: () {
                          _searchCtrl.clear();
                          setState(() => _query = '');
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Icon(Icons.close, color: textDim, size: 18),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // ── Body: search results OR hub categories ───────────────
            Expanded(
              child: isSearching
                  ? _buildSearchResults(results, textPrimary, textSecondary, textDim, cardBg, borderSubtle)
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(
                        KinrelSpacing.base,
                        4,
                        KinrelSpacing.base,
                        32,
                      ),
                      children: [
                        // Easy Mode (Grandparent Mode) card
                        _buildEasyModeCard(context, cardBg, textPrimary, textSecondary),
                        const SizedBox(height: 16),

                        // Category list
                        SettingsCard(
                          children: SettingsCategory.values
                              .map((c) => _buildCategoryRow(
                                    context,
                                    c,
                                    cardBg: cardBg,
                                    textPrimary: textPrimary,
                                    textDim: textDim,
                                  ))
                              .toList(),
                        ),

                        const SizedBox(height: 24),

                        // Sign out (red, centered)
                        Center(
                          child: TextButton(
                            onPressed: () => showSignOutDialog(context, ref),
                            style: TextButton.styleFrom(
                              foregroundColor: KinrelColors.error,
                              minimumSize: const Size(0, 48),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 12,
                              ),
                            ),
                            child: const Text(
                              'Sign out',
                              style: TextStyle(
                                fontFamily: KinrelTypography.bodyFont,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: KinrelColors.error,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Header ──────────────────────────────────────────────────────────

  Widget _buildHeader(
    BuildContext context, {
    required Color textPrimary,
    required Color textDim,
    required Color borderSubtle,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: borderSubtle)),
      ),
      child: Row(
        children: [
          Semantics(
            button: true,
            label: 'Back',
            child: InkWell(
              borderRadius: BorderRadius.circular(24),
              onTap: () {
                if (context.canPop()) {
                  context.pop();
                } else {
                  context.go('/profile');
                }
              },
              child: const SizedBox(
                width: 48,
                height: 48,
                child: Icon(Icons.arrow_back, size: 22),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Settings',
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  // ── Easy Mode (Grandparent Mode) card ───────────────────────────────

  Widget _buildEasyModeCard(
    BuildContext context,
    Color cardBg,
    Color textPrimary,
    Color textSecondary,
  ) {
    const gold = Color(0xFFD4AF37);
    return Consumer(
      builder: (context, ref, _) {
        final gpMode = ref.watch(grandparentModeProvider);
        return Container(
          decoration: BoxDecoration(
            color: gold.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: gold.withValues(alpha: 0.30)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: gold.withValues(alpha: 0.20),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.elderly_outlined,
                    color: gold, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Easy Mode for elders',
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Bigger text, simpler screens. Made for Dadi and Nana.',
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 12,
                        color: textSecondary,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 28,
                child: Switch(
                  value: gpMode.enabled,
                  onChanged: (_) => ref
                      .read(grandparentModeProvider.notifier)
                      .toggle(),
                  activeThumbColor: Colors.white,
                  activeTrackColor:
                      gold.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Category row ────────────────────────────────────────────────────

  Widget _buildCategoryRow(
    BuildContext context,
    SettingsCategory cat, {
    required Color cardBg,
    required Color textPrimary,
    required Color textDim,
  }) {
    final tint = categoryTint(cat);
    final icon = categoryIcon(cat);
    final summary = ref.watch(settingsSummaryProvider(cat));
    final idx = SettingsCategory.values.indexOf(cat);
    return InkWell(
      onTap: () => context.push('/profile/settings/${cat.id}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: tint.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: tint, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    cat.title,
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    summary,
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 12.5,
                      color: textDim,
                      height: 1.3,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: textDim, size: 20),
          ],
        ),
      ),
    ).animate(onPlay: (c) => c.forward()).fadeIn(
          delay: Duration(milliseconds: 30 * idx),
          duration: 200.ms,
        );
  }

  // ── Search results ─────────────────────────────────────────────────

  Widget _buildSearchResults(
    List<SettingsRegistryEntry> results,
    Color textPrimary,
    Color textSecondary,
    Color textDim,
    Color cardBg,
    Color borderSubtle,
  ) {
    if (results.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search_off, color: textDim, size: 36),
              const SizedBox(height: 12),
              Text(
                'No matching settings',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 14,
                  color: textDim,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: results.length,
      itemBuilder: (context, i) {
        final e = results[i];
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderSubtle),
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _onSearchResultTap(e),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Icon(categoryIcon(e.categoryId),
                        color: categoryTint(e.categoryId), size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            e.label,
                            style: TextStyle(
                              fontFamily: KinrelTypography.bodyFont,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            e.categoryId.title,
                            style: TextStyle(
                              fontFamily: KinrelTypography.bodyFont,
                              fontSize: 12,
                              color: textDim,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right, color: textDim, size: 18),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _onSearchResultTap(SettingsRegistryEntry e) {
    // Direct destination routes (no sheet) jump there immediately.
    if (e.destination != null) {
      context.push(e.destination!);
      return;
    }
    // Otherwise, push the category screen and rely on the user to
    // tap the row there. (We could attempt to scroll/highlight the
    // row, but the spec leaves that as a "where it is a toggle or
    // sheet, scrolls to or highlights it" — for v1 we land on the
    // category screen which is close enough.)
    context.push('/profile/settings/${e.categoryId.id}');
  }
}
