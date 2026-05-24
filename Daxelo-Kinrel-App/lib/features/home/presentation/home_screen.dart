import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/kinship/kinship_provider.dart';
import '../../../core/services/supabase_service.dart';
import '../../../shared/widgets/kinrel_icon.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _f1, _f2, _f3, _f4, _f5, _f6;
  late Animation<Offset> _s1, _s2, _s3, _s4, _s5, _s6;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900));
    _f1 = _fade(0.00, 0.30); _s1 = _slide(0.00, 0.30);
    _f2 = _fade(0.10, 0.40); _s2 = _slide(0.10, 0.40);
    _f3 = _fade(0.20, 0.50); _s3 = _slide(0.20, 0.50);
    _f4 = _fade(0.30, 0.60); _s4 = _slide(0.30, 0.60);
    _f5 = _fade(0.45, 0.75); _s5 = _slide(0.45, 0.75);
    _f6 = _fade(0.60, 0.90); _s6 = _slide(0.60, 0.90);
    _ctrl.forward();
  }

  Animation<double> _fade(double a, double b) => Tween<double>(begin: 0, end: 1)
      .animate(CurvedAnimation(parent: _ctrl, curve: Interval(a, b, curve: Curves.easeOutCubic)));

  Animation<Offset> _slide(double a, double b) =>
      Tween<Offset>(begin: const Offset(0, 0.15), end: Offset.zero)
          .animate(CurvedAnimation(parent: _ctrl, curve: Interval(a, b, curve: Curves.easeOutCubic)));

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final metaAsync = ref.watch(kinshipMetaProvider);
    final user = ref.watch(currentUserProvider);

    return Scaffold(
      backgroundColor: KinrelColors.darkBackground,
      body: SafeArea(
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            _section(_f1, _s1, _Header(user: user)),
            _gap(16),
            _section(_f2, _s2, const _HeroBanner()),
            _gap(20),
            _section(_f3, _s3, const _SearchBar()),
            _gap(24),
            _section(_f4, _s4, metaAsync.when(
              data: (m) => _StatsRow(meta: m),
              loading: () => const _ShimmerStats(),
              error: (_, __) => const SizedBox.shrink(),
            )),
            _gap(28),
            _section(_f5, _s5, const _QuickActions()),
            _gap(28),
            _section(_f6, _s6, const _CategoriesHeader()),
            _gap(12),
            SliverToBoxAdapter(
              child: _AnimSection(fade: _f6, slide: _s6,
                child: metaAsync.when(
                  data: (m) => _CategoryChips(meta: m),
                  loading: () => const _ShimmerChips(),
                  error: (_, __) => const SizedBox.shrink(),
                ),
              ),
            ),
            _gap(100),
          ],
        ),
      ),
    );
  }

  SliverToBoxAdapter _section(Animation<double> f, Animation<Offset> s, Widget child) =>
      SliverToBoxAdapter(child: _AnimSection(fade: f, slide: s, child: child));

  SliverToBoxAdapter _gap(double h) =>
      SliverToBoxAdapter(child: SizedBox(height: h));
}

// ── Animation wrapper ────────────────────────────────────────────
class _AnimSection extends StatelessWidget {
  final Animation<double> fade;
  final Animation<Offset> slide;
  final Widget child;
  const _AnimSection({required this.fade, required this.slide, required this.child});
  @override
  Widget build(BuildContext context) => FadeTransition(
      opacity: fade, child: SlideTransition(position: slide, child: child));
}

// ── PressDown feedback ───────────────────────────────────────────
class _PressDown extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  const _PressDown({required this.child, required this.onTap});
  @override
  State<_PressDown> createState() => _PressDownState();
}
class _PressDownState extends State<_PressDown> with SingleTickerProviderStateMixin {
  late AnimationController _c;
  late Animation<double> _sc;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 100));
    _sc = Tween<double>(begin: 1.0, end: 0.95).animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut));
  }
  @override
  void dispose() { _c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTapDown: (_) => _c.forward(),
    onTapUp: (_) { _c.reverse(); widget.onTap(); },
    onTapCancel: () => _c.reverse(),
    child: AnimatedBuilder(animation: _sc,
      builder: (_, child) => Transform.scale(scale: _sc.value, child: child),
      child: widget.child),
  );
}

// ── Shimmer ──────────────────────────────────────────────────────
class _Shimmer extends StatefulWidget {
  final double width, height, radius;
  const _Shimmer({this.width = double.infinity, required this.height, this.radius = 12});
  @override
  State<_Shimmer> createState() => _ShimmerState();
}
class _ShimmerState extends State<_Shimmer> with SingleTickerProviderStateMixin {
  late AnimationController _c;
  late Animation<double> _a;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();
    _a = Tween<double>(begin: -2, end: 2).animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut));
  }
  @override
  void dispose() { _c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _a,
    builder: (_, __) => Container(
      width: widget.width, height: widget.height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(widget.radius),
        gradient: LinearGradient(
          colors: [KinrelColors.darkCard, KinrelColors.darkElevated, KinrelColors.darkCard],
          stops: const [0, 0.5, 1],
          begin: Alignment(_a.value - 1, 0),
          end: Alignment(_a.value + 1, 0),
        ),
      ),
    ),
  );
}

class _ShimmerStats extends StatelessWidget {
  const _ShimmerStats();
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
    child: Row(children: [
      Expanded(child: _Shimmer(height: 90, radius: 16)),
      const SizedBox(width: 10),
      Expanded(child: _Shimmer(height: 90, radius: 16)),
      const SizedBox(width: 10),
      Expanded(child: _Shimmer(height: 90, radius: 16)),
    ]),
  );
}

class _ShimmerChips extends StatelessWidget {
  const _ShimmerChips();
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 44,
    child: ListView(scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
      children: [80.0, 100.0, 70.0, 90.0, 80.0, 60.0].map((w) =>
        Padding(padding: const EdgeInsets.only(right: 8),
          child: _Shimmer(width: w, height: 44, radius: 22))).toList(),
    ),
  );
}

// ── Header ───────────────────────────────────────────────────────
class _Header extends StatelessWidget {
  final dynamic user;
  const _Header({required this.user});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base, vertical: KinrelSpacing.md),
    child: Row(children: [
      const KinrelIcon(size: 36),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Good day 👋', style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 12, color: KinrelColors.textDim)),
        Text(user?.email?.split('@').first ?? 'Welcome',
          style: const TextStyle(fontFamily: KinrelTypography.displayFont, fontSize: 20, fontWeight: FontWeight.w700, color: KinrelColors.textWhite)),
      ])),
      _PressDown(
        onTap: () => context.go('/profile'),
        child: Container(width: 40, height: 40,
          decoration: BoxDecoration(shape: BoxShape.circle,
            color: KinrelColors.orange.withValues(alpha: 0.15),
            border: Border.all(color: KinrelColors.orange.withValues(alpha: 0.4))),
          child: const Icon(Icons.person_outline_rounded, color: KinrelColors.orange, size: 20)),
      ),
    ]),
  );
}

// ── Hero Banner ──────────────────────────────────────────────────
class _HeroBanner extends StatelessWidget {
  const _HeroBanner();
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
    child: Container(height: 140,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(colors: [Color(0xFF1E1508), KinrelColors.darkCard]),
        border: Border.all(color: KinrelColors.orange.withValues(alpha: 0.25)),
        boxShadow: [BoxShadow(color: KinrelColors.orange.withValues(alpha: 0.12), blurRadius: 32, offset: const Offset(0, 8))],
      ),
      child: Stack(children: [
        Positioned(right: -20, top: -20,
          child: Container(width: 140, height: 140,
            decoration: BoxDecoration(shape: BoxShape.circle,
              gradient: RadialGradient(colors: [KinrelColors.orange.withValues(alpha: 0.18), Colors.transparent])))),
        Padding(padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(20),
                color: KinrelColors.orange.withValues(alpha: 0.15),
                border: Border.all(color: KinrelColors.orange.withValues(alpha: 0.4))),
              child: Text('🇮🇳  15 Languages',
                style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 11, fontWeight: FontWeight.w600, color: KinrelColors.orange))),
            const SizedBox(height: 10),
            const Text('Discover your\nfamily roots',
              style: TextStyle(fontFamily: KinrelTypography.displayFont, fontSize: 22, fontWeight: FontWeight.w700, color: KinrelColors.textWhite, height: 1.2)),
            const Spacer(),
            _PressDown(
              onTap: () => context.go('/search'),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(20),
                  gradient: const LinearGradient(colors: [KinrelColors.orange, KinrelColors.amber])),
                child: const Text('Explore Now →',
                  style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white)))),
          ])),
      ]),
    ),
  );
}

// ── Search Bar ───────────────────────────────────────────────────
class _SearchBar extends StatelessWidget {
  const _SearchBar();
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
    child: _PressDown(
      onTap: () => context.go('/search'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(color: KinrelColors.darkCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: KinrelColors.darkSurface.withValues(alpha: 0.6)),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 12, offset: const Offset(0, 4))]),
        child: Row(children: [
          Icon(Icons.search_rounded, color: KinrelColors.orange.withValues(alpha: 0.7), size: 20),
          const SizedBox(width: 12),
          Expanded(child: Text('Search 5,359 relationships...',
            style: TextStyle(color: KinrelColors.textDim, fontFamily: KinrelTypography.bodyFont, fontSize: 15))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: KinrelColors.orange.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
            child: Text('⌘K', style: TextStyle(color: KinrelColors.orange, fontSize: 11, fontFamily: KinrelTypography.bodyFont))),
        ]),
      ),
    ),
  );
}

// ── Stats ────────────────────────────────────────────────────────
class _StatsRow extends StatelessWidget {
  final Map<String, dynamic> meta;
  const _StatsRow({required this.meta});
  @override
  Widget build(BuildContext context) {
    final langs = (meta['supportedLanguages'] as List?)?.length ?? 15;
    final cats  = (meta['categories'] as List?)?.length ?? 9;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
      child: Row(children: [
        _StatCard(icon: Icons.people_alt_rounded,  value: '${meta['totalRelationships']}+', label: 'Relations',  color: KinrelColors.orange),
        const SizedBox(width: 10),
        _StatCard(icon: Icons.translate_rounded,    value: '$langs',                          label: 'Languages',  color: KinrelColors.amber),
        const SizedBox(width: 10),
        _StatCard(icon: Icons.category_rounded,     value: '$cats',                           label: 'Categories', color: KinrelColors.ember),
      ]),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon; final String value, label; final Color color;
  const _StatCard({required this.icon, required this.value, required this.label, required this.color});
  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.2)),
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.10), blurRadius: 20, offset: const Offset(0, 4))]),
      child: Column(children: [
        Container(padding: const EdgeInsets.all(7), decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: 0.12)),
          child: Icon(icon, color: color, size: 16)),
        const SizedBox(height: 8),
        Text(value, style: const TextStyle(fontFamily: KinrelTypography.displayFont, fontSize: 18, fontWeight: FontWeight.w700, color: KinrelColors.textWhite)),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 10, color: KinrelColors.textDim)),
      ]),
    ),
  );
}

// ── Quick Actions ────────────────────────────────────────────────
class _QuickActions extends StatelessWidget {
  const _QuickActions();
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
    child: Row(children: [
      _QuickCard(icon: Icons.account_tree_rounded, title: 'Family Tree', subtitle: 'View your tree',       color: KinrelColors.orange, onTap: () => context.go('/families')),
      const SizedBox(width: 10),
      _QuickCard(icon: Icons.auto_awesome_rounded,  title: 'Explore',     subtitle: 'All relationships',   color: KinrelColors.amber,  onTap: () => context.go('/search')),
      const SizedBox(width: 10),
      _QuickCard(icon: Icons.route_rounded,         title: 'Find Path',   subtitle: 'Relationship finder', color: KinrelColors.ember,  onTap: () => context.go('/families')),
    ]),
  );
}

class _QuickCard extends StatelessWidget {
  final IconData icon; final String title, subtitle; final Color color; final VoidCallback onTap;
  const _QuickCard({required this.icon, required this.title, required this.subtitle, required this.color, required this.onTap});
  @override
  Widget build(BuildContext context) => Expanded(
    child: _PressDown(onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(colors: [color.withValues(alpha: 0.18), color.withValues(alpha: 0.06)], begin: Alignment.topLeft, end: Alignment.bottomRight),
          border: Border.all(color: color.withValues(alpha: 0.3)),
          boxShadow: [BoxShadow(color: color.withValues(alpha: 0.08), blurRadius: 16, offset: const Offset(0, 4))]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), color: color.withValues(alpha: 0.15)),
            child: Icon(icon, color: color, size: 20)),
          const SizedBox(height: 10),
          Text(title, style: const TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 12, fontWeight: FontWeight.w600, color: KinrelColors.textWhite)),
          const SizedBox(height: 2),
          Text(subtitle, style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 10, color: KinrelColors.textDim)),
        ]),
      ),
    ),
  );
}

// ── Categories ───────────────────────────────────────────────────
class _CategoriesHeader extends StatelessWidget {
  const _CategoriesHeader();
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      const Text('Categories', style: TextStyle(fontFamily: KinrelTypography.displayFont, fontSize: 18, fontWeight: FontWeight.w600, color: KinrelColors.textWhite)),
      _PressDown(onTap: () => context.go('/search'),
        child: Text('See All', style: TextStyle(color: KinrelColors.orange, fontFamily: KinrelTypography.bodyFont, fontSize: 13, fontWeight: FontWeight.w500))),
    ]),
  );
}

class _CategoryChips extends ConsumerWidget {
  final Map<String, dynamic> meta;
  const _CategoryChips({required this.meta});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = (meta['categories'] as List?)?.cast<String>() ?? [];
    return SizedBox(height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
        itemCount: categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final cat = categories[i];
          return _PressDown(
            onTap: () { ref.read(kinshipCategoryProvider.notifier).state = cat; context.go('/search'); },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(color: KinrelColors.darkCard, borderRadius: BorderRadius.circular(22),
                border: Border.all(color: KinrelColors.orange.withValues(alpha: 0.25))),
              child: Text(cat.replaceAll('_', ' ').toUpperCase(),
                style: const TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 11, fontWeight: FontWeight.w600, color: KinrelColors.textSilver, letterSpacing: 0.5))),
          );
        },
      ),
    );
  }
}
