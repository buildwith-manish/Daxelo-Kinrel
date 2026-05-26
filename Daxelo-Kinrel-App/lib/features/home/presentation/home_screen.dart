import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Family;
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/constants/supported_languages.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/family/family_provider.dart';
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
    _f1 = _fade(0.00, 0.30);
    _s1 = _slide(0.00, 0.30);
    _f2 = _fade(0.10, 0.40);
    _s2 = _slide(0.10, 0.40);
    _f3 = _fade(0.20, 0.50);
    _s3 = _slide(0.20, 0.50);
    _f4 = _fade(0.30, 0.60);
    _s4 = _slide(0.30, 0.60);
    _f5 = _fade(0.45, 0.75);
    _s5 = _slide(0.45, 0.75);
    _f6 = _fade(0.60, 0.90);
    _s6 = _slide(0.60, 0.90);
    _ctrl.forward();
  }

  Animation<double> _fade(double a, double b) => Tween<double>(begin: 0, end: 1)
      .animate(CurvedAnimation(
          parent: _ctrl, curve: Interval(a, b, curve: Curves.easeOutCubic)));

  Animation<Offset> _slide(double a, double b) =>
      Tween<Offset>(begin: const Offset(0, 0.15), end: Offset.zero).animate(
          CurvedAnimation(
              parent: _ctrl, curve: Interval(a, b, curve: Curves.easeOutCubic)));

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final familiesAsync = ref.watch(familyListProvider);
    final user = ref.watch(currentUserProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SafeArea(
        child: familiesAsync.when(
          loading: () => const Center(
            child: CircularProgressIndicator(color: KinrelColors.orange),
          ),
          error: (error, _) => _ErrorState(
            message: 'Failed to load families',
            onRetry: () => ref.invalidate(familyListProvider),
          ),
          data: (families) {
            if (families.isEmpty) {
              return _buildNoFamiliesView(user);
            }
            return _buildFamiliesView(user, families);
          },
        ),
      ),
    );
  }

  /// No families — show centered CTA
  Widget _buildNoFamiliesView(dynamic user) {
    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        _section(_f1, _s1, _Header(user: user)),
        _gap(40),
        SliverToBoxAdapter(
          child: _AnimSection(
            fade: _f2,
            slide: _s2,
            child: _CreateFirstFamilyCTA(
              onTap: () => context.push('/families/create'),
            ),
          ),
        ),
        _gap(100),
      ],
    );
  }

  /// Has families — show family graph-first home
  Widget _buildFamiliesView(dynamic user, List<Family> families) {
    final primaryFamily = families.first;
    final detailAsync = ref.watch(familyDetailProvider(primaryFamily.id));

    return RefreshIndicator(
      color: KinrelColors.orange,
      onRefresh: () async {
        ref.invalidate(familyListProvider);
        ref.invalidate(familyDetailProvider(primaryFamily.id));
      },
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          _section(_f1, _s1, _Header(user: user)),
          _gap(16),

          // Primary family card
          SliverToBoxAdapter(
            child: _AnimSection(
              fade: _f2,
              slide: _s2,
              child: _PrimaryFamilyCard(
                family: primaryFamily,
                detailAsync: detailAsync,
              ),
            ),
          ),
          _gap(20),

          // Quick actions
          SliverToBoxAdapter(
            child: _AnimSection(
              fade: _f3,
              slide: _s3,
              child: _QuickActions(familyId: primaryFamily.id),
            ),
          ),
          _gap(24),

          // Recent activity
          SliverToBoxAdapter(
            child: _AnimSection(
              fade: _f4,
              slide: _s4,
              child: detailAsync.when(
                data: (detail) => _RecentActivity(
                  members: detail?.members ?? [],
                  relationships: detail?.relationships ?? [],
                ),
                loading: () => const _ShimmerSection(height: 120),
                error: (_, __) => const SizedBox.shrink(),
              ),
            ),
          ),
          _gap(28),

          // Your Families horizontal scroll
          SliverToBoxAdapter(
            child: _AnimSection(
              fade: _f5,
              slide: _s5,
              child: _YourFamiliesSection(families: families),
            ),
          ),
          _gap(100),
        ],
      ),
    );
  }

  SliverToBoxAdapter _section(
          Animation<double> f, Animation<Offset> s, Widget child) =>
      SliverToBoxAdapter(child: _AnimSection(fade: f, slide: s, child: child));

  SliverToBoxAdapter _gap(double h) =>
      SliverToBoxAdapter(child: SizedBox(height: h));
}

// ── Animation wrapper ────────────────────────────────────────────
class _AnimSection extends StatelessWidget {
  final Animation<double> fade;
  final Animation<Offset> slide;
  final Widget child;
  const _AnimSection(
      {required this.fade, required this.slide, required this.child});
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

class _PressDownState extends State<_PressDown>
    with SingleTickerProviderStateMixin {
  late AnimationController _c;
  late Animation<double> _sc;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 100));
    _sc = Tween<double>(begin: 1.0, end: 0.95).animate(
        CurvedAnimation(parent: _c, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTapDown: (_) => _c.forward(),
        onTapUp: (_) {
          _c.reverse();
          widget.onTap();
        },
        onTapCancel: () => _c.reverse(),
        child: AnimatedBuilder(
          animation: _sc,
          builder: (_, child) =>
              Transform.scale(scale: _sc.value, child: child),
          child: widget.child,
        ),
      );
}

// ── Shimmer ──────────────────────────────────────────────────────
class _Shimmer extends StatefulWidget {
  final double width, height, radius;
  const _Shimmer(
      {this.width = double.infinity, required this.height, this.radius = 12});
  @override
  State<_Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<_Shimmer>
    with SingleTickerProviderStateMixin {
  late AnimationController _c;
  late Animation<double> _a;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat();
    _a = Tween<double>(begin: -2, end: 2).animate(
        CurvedAnimation(parent: _c, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _a,
        builder: (_, __) => Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            gradient: LinearGradient(
              colors: [
                KinrelColors.darkCard,
                KinrelColors.darkElevated,
                KinrelColors.darkCard
              ],
              stops: const [0, 0.5, 1],
              begin: Alignment(_a.value - 1, 0),
              end: Alignment(_a.value + 1, 0),
            ),
          ),
        ),
      );
}

class _ShimmerSection extends StatelessWidget {
  final double height;
  const _ShimmerSection({required this.height});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
        child: _Shimmer(height: height, radius: 16),
      );
}

// ── Header ───────────────────────────────────────────────────────
class _Header extends StatelessWidget {
  final dynamic user;
  const _Header({required this.user});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: KinrelSpacing.base, vertical: KinrelSpacing.md),
        child: Row(children: [
          const KinrelIcon(size: 36),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Good day 👋',
                      style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 12,
                          color: KinrelColors.textDim)),
                  Text(
                      user?.email?.split('@').first ?? 'Welcome',
                      style: const TextStyle(
                          fontFamily: KinrelTypography.displayFont,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: KinrelColors.textWhite)),
                ]),
          ),
          _PressDown(
            onTap: () => context.go('/profile'),
            child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: KinrelColors.orange.withValues(alpha: 0.15),
                    border: Border.all(
                        color: KinrelColors.orange.withValues(alpha: 0.4))),
                child: const Icon(Icons.person_outline_rounded,
                    color: KinrelColors.orange, size: 20)),
          ),
        ]),
      );
}

// ── Create First Family CTA ──────────────────────────────────────
class _CreateFirstFamilyCTA extends StatelessWidget {
  final VoidCallback onTap;
  const _CreateFirstFamilyCTA({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Large illustrated button
            _PressDown(
              onTap: onTap,
              child: Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      KinrelColors.orange.withValues(alpha: 0.15),
                      KinrelColors.darkCard,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  border: Border.all(
                    color: KinrelColors.orange.withValues(alpha: 0.4),
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: KinrelColors.orange.withValues(alpha: 0.12),
                      blurRadius: 40,
                      spreadRadius: 10,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: KinrelColors.orange.withValues(alpha: 0.2),
                      ),
                      child: const Icon(
                        Icons.add_rounded,
                        size: 48,
                        color: KinrelColors.orange,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Create Your\nFirst Family',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: KinrelTypography.displayFont,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: KinrelColors.textWhite,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 28),
            Text(
              'Start building your family graph\nand discover your kinship connections',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 15,
                color: KinrelColors.textSilver,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            // Join family link
            TextButton(
              onPressed: () => _showJoinFamilyDialog(context),
              child: Text(
                'Or join an existing family with a code',
                style: TextStyle(
                  color: KinrelColors.orange,
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 14,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showJoinFamilyDialog(BuildContext context) {
    final codeController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: KinrelColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KinrelRadius.dialog),
          side: const BorderSide(color: KinrelColors.border),
        ),
        title: Text(
          'Join Family',
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            color: KinrelColors.textPrimary,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Enter the family code shared with you',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                color: KinrelColors.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: codeController,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                color: KinrelColors.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: 'e.g., sharma-family-2a3b',
                hintStyle: TextStyle(color: KinrelColors.textDim),
                filled: true,
                fillColor: KinrelColors.elevated,
                border: OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(KinrelRadius.input),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel',
                style: TextStyle(color: KinrelColors.textDim)),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              // TODO: Implement join family by code
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Join family coming soon!')),
              );
            },
            style: FilledButton.styleFrom(
              backgroundColor: KinrelColors.orange,
            ),
            child: const Text('Join'),
          ),
        ],
      ),
    );
  }
}

// ── Primary Family Card ──────────────────────────────────────────
class _PrimaryFamilyCard extends StatelessWidget {
  final Family family;
  final AsyncValue<FamilyDetail?> detailAsync;

  const _PrimaryFamilyCard({
    required this.family,
    required this.detailAsync,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
      child: _PressDown(
        onTap: () => context.push('/family/${family.id}'),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: const LinearGradient(
              colors: [Color(0xFF1E1508), KinrelColors.darkCard],
            ),
            border: Border.all(
                color: KinrelColors.orange.withValues(alpha: 0.25)),
            boxShadow: [
              BoxShadow(
                color: KinrelColors.orange.withValues(alpha: 0.12),
                blurRadius: 32,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Family header row
              Row(
                children: [
                  // Family avatar
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: KinrelGradients.igniteGradient,
                    ),
                    child: Center(
                      child: Text(
                        family.name.isNotEmpty
                            ? family.name[0].toUpperCase()
                            : 'F',
                        style: const TextStyle(
                          fontFamily: KinrelTypography.displayFont,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          family.name,
                          style: const TextStyle(
                            fontFamily: KinrelTypography.displayFont,
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: KinrelColors.textWhite,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _familyCode(family),
                          style: TextStyle(
                            fontFamily: KinrelTypography.monoFont,
                            fontSize: 11,
                            color: KinrelColors.textDim,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right,
                      color: KinrelColors.textDim, size: 24),
                ],
              ),
              const SizedBox(height: 20),

              // Quick stats
              detailAsync.when(
                data: (detail) {
                  final members = detail?.members ?? [];
                  final relationships = detail?.relationships ?? [];
                  return Row(
                    children: [
                      _StatChip(
                        icon: Icons.people_outline_rounded,
                        value: '${members.length}',
                        label: 'Members',
                        color: KinrelColors.orange,
                      ),
                      const SizedBox(width: 10),
                      _StatChip(
                        icon: Icons.account_tree_outlined,
                        value: _estimateGenerations(members, relationships),
                        label: 'Generations',
                        color: KinrelColors.amber,
                      ),
                      const SizedBox(width: 10),
                      _StatChip(
                        icon: Icons.link_rounded,
                        value: '${relationships.length}',
                        label: 'Links',
                        color: KinrelColors.ember,
                      ),
                    ],
                  );
                },
                loading: () => Row(
                  children: [
                    Expanded(
                        child: _Shimmer(height: 44, radius: 10)),
                    const SizedBox(width: 10),
                    Expanded(
                        child: _Shimmer(height: 44, radius: 10)),
                    const SizedBox(width: 10),
                    Expanded(
                        child: _Shimmer(height: 44, radius: 10)),
                  ],
                ),
                error: (_, __) => const SizedBox.shrink(),
              ),
              const SizedBox(height: 16),

              // View Full Graph button
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: const LinearGradient(
                      colors: [KinrelColors.orange, KinrelColors.amber]),
                ),
                child: Text(
                  'View Full Graph →',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _familyCode(Family family) {
    // Generate a slug from family name + id suffix
    final slug = family.name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    final idSuffix =
        family.id.length >= 4 ? family.id.substring(0, 4) : family.id;
    return 'kinrel.co/f/$slug-$idSuffix';
  }

  String _estimateGenerations(
      List<Person> members, List<FamilyRelationship> relationships) {
    if (members.isEmpty) return '1';
    // Simple heuristic: count distinct generation levels
    // For now, estimate based on member count
    if (members.length <= 2) return '1';
    if (members.length <= 6) return '2';
    if (members.length <= 15) return '3';
    return '4+';
  }
}

// ── Stat Chip ────────────────────────────────────────────────────
class _StatChip extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;

  const _StatChip({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.2)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 14),
              const SizedBox(width: 6),
              Text(value,
                  style: TextStyle(
                    fontFamily: KinrelTypography.displayFont,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: KinrelColors.textWhite,
                  )),
              const SizedBox(width: 4),
              Flexible(
                child: Text(label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 10,
                      color: KinrelColors.textDim,
                    )),
              ),
            ],
          ),
        ),
      );
}

// ── Quick Actions ────────────────────────────────────────────────
class _QuickActions extends StatelessWidget {
  final String familyId;
  const _QuickActions({required this.familyId});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
        child: Row(children: [
          _QuickCard(
            icon: Icons.person_add_rounded,
            title: 'Add Member',
            subtitle: 'Expand your tree',
            color: KinrelColors.orange,
            onTap: () => context.push('/family/$familyId/add-person'),
          ),
          const SizedBox(width: 10),
          _QuickCard(
            icon: Icons.share_rounded,
            title: 'Share',
            subtitle: 'Invite family',
            color: KinrelColors.amber,
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Share coming soon!')),
              );
            },
          ),
          const SizedBox(width: 10),
          _QuickCard(
            icon: Icons.route_rounded,
            title: 'Find Path',
            subtitle: 'Relationship finder',
            color: KinrelColors.ember,
            onTap: () =>
                context.push('/family/$familyId/path-finder'),
          ),
        ]),
      );
}

class _QuickCard extends StatelessWidget {
  final IconData icon;
  final String title, subtitle;
  final Color color;
  final VoidCallback onTap;
  const _QuickCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Expanded(
        child: _PressDown(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                colors: [
                  color.withValues(alpha: 0.18),
                  color.withValues(alpha: 0.06)
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(color: color.withValues(alpha: 0.3)),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.08),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                )
              ],
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: color.withValues(alpha: 0.15),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(height: 10),
              Text(title,
                  style: const TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: KinrelColors.textWhite,
                  )),
              const SizedBox(height: 2),
              Text(subtitle,
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 10,
                    color: KinrelColors.textDim,
                  )),
            ]),
          ),
        ),
      );
}

// ── Recent Activity ──────────────────────────────────────────────
class _RecentActivity extends StatelessWidget {
  final List<Person> members;
  final List<FamilyRelationship> relationships;

  const _RecentActivity({
    required this.members,
    required this.relationships,
  });

  @override
  Widget build(BuildContext context) {
    // Show last 3 items (mix of members and relationships by creation date)
    final activities = <_ActivityItem>[];

    for (final m in members) {
      activities.add(_ActivityItem(
        icon: Icons.person_outline_rounded,
        title: m.name,
        subtitle: 'Added to family',
        time: m.createdAt,
        color: KinrelColors.orange,
      ));
    }
    for (final r in relationships) {
      activities.add(_ActivityItem(
        icon: Icons.link_rounded,
        title: r.relationshipKey.replaceAll('_', ' ').toUpperCase(),
        subtitle: 'New relationship link',
        time: r.createdAt,
        color: KinrelColors.amber,
      ));
    }

    // Sort by time descending, take last 3
    activities.sort((a, b) =>
        (b.time ?? DateTime(1970)).compareTo(a.time ?? DateTime(1970)));
    final recent = activities.take(3).toList();

    if (recent.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Recent Activity',
                style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: KinrelColors.textWhite,
                )),
            const SizedBox(height: 12),
            Text(
              'No activity yet. Start by adding members!',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                color: KinrelColors.textDim,
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Recent Activity',
              style: const TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: KinrelColors.textWhite,
              )),
          const SizedBox(height: 12),
          ...recent.map((item) => _ActivityTile(item: item)),
        ],
      ),
    );
  }
}

class _ActivityItem {
  final IconData icon;
  final String title;
  final String subtitle;
  final DateTime? time;
  final Color color;

  const _ActivityItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.time,
    required this.color,
  });
}

class _ActivityTile extends StatelessWidget {
  final _ActivityItem item;
  const _ActivityTile({required this.item});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: KinrelColors.darkCard,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: KinrelColors.darkSurface.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: item.color.withValues(alpha: 0.12),
                ),
                child: Icon(item.icon, color: item.color, size: 16),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.title,
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: KinrelColors.textWhite,
                        )),
                    Text(item.subtitle,
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 11,
                          color: KinrelColors.textDim,
                        )),
                  ],
                ),
              ),
              if (item.time != null)
                Text(
                  _timeAgo(item.time!),
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 10,
                    color: KinrelColors.textDim,
                  ),
                ),
            ],
          ),
        ),
      );

  String _timeAgo(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inHours < 1) return '${diff.inMinutes}m';
    if (diff.inDays < 1) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${(diff.inDays / 7).round()}w';
  }
}

// ── Your Families Section ────────────────────────────────────────
class _YourFamiliesSection extends StatelessWidget {
  final List<Family> families;
  const _YourFamiliesSection({required this.families});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Text('Your Families',
                      style: TextStyle(
                        fontFamily: KinrelTypography.displayFont,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: KinrelColors.textWhite,
                      )),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: KinrelColors.orange.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('${families.length}',
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: KinrelColors.orange,
                        )),
                  ),
                ],
              ),
              _PressDown(
                onTap: () => context.go('/families'),
                child: Text('See All',
                    style: TextStyle(
                      color: KinrelColors.orange,
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    )),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 120,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding:
                const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
            itemCount: families.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final family = families[index];
              return _FamilyScrollCard(
                family: family,
                onTap: () => context.push('/family/${family.id}'),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _FamilyScrollCard extends StatelessWidget {
  final Family family;
  final VoidCallback onTap;

  const _FamilyScrollCard({
    required this.family,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return _PressDown(
      onTap: onTap,
      child: Container(
        width: 160,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: KinrelColors.darkCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: KinrelColors.orange.withValues(alpha: 0.15)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Avatar
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    KinrelColors.orange.withValues(alpha: 0.3),
                    KinrelColors.amber.withValues(alpha: 0.15),
                  ],
                ),
              ),
              child: Center(
                child: Text(
                  family.name.isNotEmpty
                      ? family.name[0].toUpperCase()
                      : 'F',
                  style: const TextStyle(
                    fontFamily: KinrelTypography.displayFont,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: KinrelColors.orange,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              family.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: KinrelColors.textWhite,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              family.primaryLanguage != null
                  ? SupportedLanguage.fromCode(family.primaryLanguage!).name
                  : 'English',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 11,
                color: KinrelColors.textDim,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Error State ──────────────────────────────────────────────────
class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline,
                size: 48, color: KinrelColors.error.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            Text(message,
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  color: KinrelColors.textDim,
                )),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onRetry,
              style:
                  FilledButton.styleFrom(backgroundColor: KinrelColors.orange),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
}
