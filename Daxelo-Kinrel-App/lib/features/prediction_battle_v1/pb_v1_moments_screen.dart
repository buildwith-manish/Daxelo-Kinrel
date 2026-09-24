// lib/features/prediction_battle_v1/pb_v1_moments_screen.dart
//
// Family Moments feed screen — lists all moments in the family
// (prediction wins + future types) with the featured moment pinned
// to the top. Each moment card shows the title, body, date, and a
// "Feature for 24h · 🪙 50" button that spends 50 coins to pin the
// moment for 24 hours (Tier 2 item 7).
//
// Reachable via a "Family Moments" link in the prediction history
// screen + via a future hub card. Not wired into the family hub
// directly to avoid clutter — the moments feed is a destination,
// not a hub surface.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/utils/app_time.dart';
import 'pb_v1_coin_provider.dart';

class PBv1MomentsScreen extends ConsumerStatefulWidget {
  const PBv1MomentsScreen({super.key, required this.familyId});
  final String familyId;

  @override
  ConsumerState<PBv1MomentsScreen> createState() => _PBv1MomentsScreenState();
}

class _PBv1MomentsScreenState extends ConsumerState<PBv1MomentsScreen> {
  List<Map<String, dynamic>> _moments = const [];
  Map<String, String> _userNames = const {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      _loadMoments();
      _loadUserNames();
      ref.read(pbV1CoinProvider(widget.familyId).notifier).load();
    });
  }

  Future<void> _loadMoments() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final client = ref.read(supabaseProvider);
    if (client == null) {
      setState(() {
        _loading = false;
        _error = 'Not signed in';
      });
      return;
    }
    try {
      // Order: featured moments first (by featuredUntil DESC), then
      // all moments by createdAt DESC. Featured moments have a
      // non-null featuredUntil that is in the future.
      final rows = await client
          .from('family_moments')
          .select('id, "familyId", "userId", type, title, body, metadata, "createdAt", "featuredUntil"')
          .eq('familyId', widget.familyId)
          .order('featuredUntil', ascending: false, nullsFirst: false)
          .order('createdAt', ascending: false)
          .limit(50);
      if (!mounted) return;
      setState(() {
        _moments = (rows as List).map((r) => Map<String, dynamic>.from(r as Map)).toList();
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '$e';
        });
      }
    }
  }

  Future<void> _loadUserNames() async {
    final client = ref.read(supabaseProvider);
    if (client == null) return;
    try {
      final rows = await client
          .from('FamilyMember')
          .select('userId, user:User(name)')
          .eq('familyId', widget.familyId);
      if (!mounted) return;
      final map = <String, String>{};
      for (final r in (rows as List)) {
        final row = r as Map<String, dynamic>;
        final uid = (row['userId'] ?? '') as String;
        if (uid.isEmpty) continue;
        final user = row['user'];
        if (user is Map && user['name'] is String && (user['name'] as String).isNotEmpty) {
          map[uid] = user['name'] as String;
        } else {
          map[uid] = uid.substring(0, 8);
        }
      }
      setState(() => _userNames = map);
    } catch (_) {}
  }

  Future<void> _featureMoment(String momentId) async {
    final client = ref.read(supabaseProvider);
    final myId = client?.auth.currentUser?.id;
    if (client == null || myId == null) return;

    // Confirm dialog — 50 coins is non-trivial.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: KinrelColors.darkCard,
        title: const Text('Feature this moment?', style: TextStyle(color: KinrelColors.textWhite)),
        content: const Text(
          'Pins this moment to the top of the family hub for 24 hours.\n\nCost: 🪙 50 coins.',
          style: TextStyle(color: KinrelColors.textSilver),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: KinrelColors.orange, foregroundColor: Colors.white),
            child: const Text('Feature for 🪙 50'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final resp = await client.rpc('fn_pb_v1_feature_moment', params: {
        'p_user_id': myId,
        'p_family_id': widget.familyId,
        'p_moment_id': momentId,
      });
      if (mounted) {
        if (resp is Map && resp['ok'] == true) {
          // Refresh moments + coin balance (the latter is what
          // updates the chip on the family hub hero).
          await _loadMoments();
          await ref.read(pbV1CoinProvider(widget.familyId).notifier).refresh();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Moment featured for 24h! 🪙 50 coins spent.'),
              backgroundColor: KinrelColors.orange,
            ),
          );
        } else {
          final reason = (resp is Map ? resp['reason'] : null) ?? 'unknown_error';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Could not feature: $reason'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not feature: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KinrelColors.darkSurface,
      appBar: AppBar(
        title: const Text('Family Moments', style: TextStyle(fontFamily: KinrelTypography.displayFont, fontWeight: FontWeight.w700)),
        backgroundColor: KinrelColors.darkCard,
        foregroundColor: KinrelColors.textWhite,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _loadMoments,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: KinrelColors.orange))
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Could not load: $_error', style: const TextStyle(color: KinrelColors.textDim))))
              : _moments.isEmpty
                  ? const _EmptyMomentsState()
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _moments.length,
                      itemBuilder: (ctx, i) => _MomentCard(
                        moment: _moments[i],
                        userNames: _userNames,
                        onFeature: () => _featureMoment(_moments[i]['id'] as String),
                      ),
                    ),
    );
  }
}

class _EmptyMomentsState extends StatelessWidget {
  const _EmptyMomentsState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.photo_library_outlined, size: 48, color: KinrelColors.textDim),
            const SizedBox(height: 12),
            const Text(
              'No Family Moments yet',
              style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: KinrelColors.textWhite,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'When someone in your family wins a Prediction Battle, the moment will show up here automatically.',
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 12, color: KinrelColors.textDim),
            ),
          ],
        ),
      ),
    );
  }
}

class _MomentCard extends StatelessWidget {
  const _MomentCard({required this.moment, required this.userNames, required this.onFeature});
  final Map<String, dynamic> moment;
  final Map<String, String> userNames;
  final VoidCallback onFeature;

  @override
  Widget build(BuildContext context) {
    final title = (moment['title'] ?? '') as String;
    final body = (moment['body'] ?? '') as String;
    final createdAt = DateTime.tryParse((moment['createdAt'] ?? '').toString()) ?? DateTime.now();
    final featuredUntilRaw = moment['featuredUntil'];
    final featuredUntil = featuredUntilRaw != null
        ? DateTime.tryParse(featuredUntilRaw.toString())
        : null;
    final isFeatured = featuredUntil != null && featuredUntil.isAfter(DateTime.now().toUtc());
    final userId = (moment['userId'] ?? '') as String;
    final userName = userNames[userId] ?? userId.substring(0, 8);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isFeatured ? KinrelColors.brightGold.withValues(alpha: 0.08) : KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isFeatured ? KinrelColors.brightGold.withValues(alpha: 0.4) : KinrelColors.border,
          width: 0.8,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isFeatured)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  const Icon(Icons.push_pin, size: 12, color: KinrelColors.brightGold),
                  const SizedBox(width: 4),
                  Text(
                    'FEATURED · ${_timeUntil(featuredUntil!)} left',
                    style: TextStyle(
                      fontFamily: KinrelTypography.monoFont,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                      color: KinrelColors.brightGold,
                    ),
                  ),
                ],
              ),
            ),
          Text(
            title,
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: KinrelColors.textWhite,
            ),
          ),
          if (body.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              body,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 12,
                color: KinrelColors.textSilver,
                height: 1.4,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                '$userName · ${_formatDate(createdAt)}',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 10,
                  color: KinrelColors.textDim,
                ),
              ),
              const Spacer(),
              if (!isFeatured)
                GestureDetector(
                  onTap: onFeature,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: KinrelColors.brightGold.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: KinrelColors.brightGold.withValues(alpha: 0.30), width: 0.8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.push_pin, size: 10, color: KinrelColors.brightGold),
                        const SizedBox(width: 4),
                        Text(
                          'Feature · 🪙 50',
                          style: TextStyle(
                            fontFamily: KinrelTypography.monoFont,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: KinrelColors.brightGold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final ist = AppTime.toLocalDisplay(dt);
    final now = DateTime.now();
    final diff = now.difference(ist);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'yesterday';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[ist.month - 1]} ${ist.day}';
  }

  String _timeUntil(DateTime futureUtc) {
    final diff = futureUtc.difference(DateTime.now().toUtc());
    if (diff.isNegative) return 'expired';
    final h = diff.inHours;
    final m = diff.inMinutes % 60;
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }
}
