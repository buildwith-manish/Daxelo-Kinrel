// lib/features/family/presentation/family_settings_screen.dart
//
// P1.4: Family settings screen with bridge role opt-in toggle.
//
// Allows family admins to enable/disable the "Silent check-in alerts" feature.
// When ON, designated family admins receive a private alert if a family member
// hasn't opened Kinrel in 7+ days. The inactive member is never notified.
// Default OFF — only enable if the family has explicitly agreed to this.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/networking/dio_client.dart' show dioProvider;

class FamilySettingsScreen extends ConsumerStatefulWidget {
  final String familyId;

  const FamilySettingsScreen({super.key, required this.familyId});

  @override
  ConsumerState<FamilySettingsScreen> createState() =>
      _FamilySettingsScreenState();
}

class _FamilySettingsScreenState extends ConsumerState<FamilySettingsScreen> {
  bool _bridgeOptIn = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadBridgeOptIn();
  }

  Future<void> _loadBridgeOptIn() async {
    try {
      final dio = ref.read(dioProvider);
      final r = await dio.get('/api/families/${widget.familyId}');
      if (mounted) {
        setState(() {
          _bridgeOptIn = (r.data['bridgeRoleOptIn'] as bool?) ?? false;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleBridgeOptIn(bool value) async {
    if (value) {
      // Show confirmation dialog before opting in.
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: KinrelColors.darkCard,
          title: const Text('Silent check-in alerts',
              style: TextStyle(color: KinrelColors.textPrimary)),
          content: const Text(
            'Admins will receive a private alert if a family member '
            'hasn\'t opened Kinrel in 7+ days. The inactive member is '
            'never notified. Only enable if your family has explicitly '
            'agreed to this.',
            style: TextStyle(color: KinrelColors.textSecondary, height: 1.5),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel',
                  style: TextStyle(color: KinrelColors.textDim)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Enable',
                  style: TextStyle(color: KinrelColors.gold)),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    setState(() => _bridgeOptIn = value);
    try {
      final dio = ref.read(dioProvider);
      await dio.patch(
        '/api/families/${widget.familyId}',
        data: {'bridgeRoleOptIn': value},
      );
    } catch (_) {
      // Revert on failure
      if (mounted) setState(() => _bridgeOptIn = !value);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KinrelColors.darkBackground,
      appBar: AppBar(
        backgroundColor: KinrelColors.darkBackground,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => context.pop(),
        ),
        title: const Text(
          'Family Settings',
          style: TextStyle(
              color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: KinrelColors.gold))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Silent Check-in Alerts section ──
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: KinrelColors.darkCard,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white.withOpacity(0.08)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: KinrelColors.gold.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.notifications_active_outlined,
                                color: KinrelColors.gold,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Silent check-in alerts',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'When on, designated family admins receive a '
                                    'private alert if a family member hasn\'t '
                                    'opened Kinrel in 7+ days. The inactive '
                                    'member is never notified. Off by default — '
                                    'only enable if your family has explicitly '
                                    'agreed to this.',
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.5),
                                      fontSize: 12,
                                      height: 1.4,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Semantics(
                              label:
                                  'Silent check-in alerts. When on, admins are '
                                  'notified if a family member is inactive for '
                                  '7+ days. Currently ${_bridgeOptIn ? 'on' : 'off'}.',
                              child: Switch(
                                value: _bridgeOptIn,
                                onChanged: _toggleBridgeOptIn,
                                activeColor: KinrelColors.gold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        // Info row
                        Row(
                          children: [
                            Icon(Icons.shield_outlined,
                                color: Colors.white.withOpacity(0.3), size: 14),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Alarms use absolute inactivity thresholds '
                                    '(7, 14, and 21 days). No behavioral '
                                    'baseline tracking.',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.35),
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Explanation card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: KinrelColors.darkCard.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: Colors.white.withOpacity(0.04)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.info_outline,
                                color: Colors.white.withOpacity(0.4), size: 16),
                            const SizedBox(width: 8),
                            Text(
                              'How this works',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.6),
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '• 7 days inactive → gentle alert to admins\n'
                          '• 14 days inactive → moderate alert to admins\n'
                          '• 21 days inactive → urgent alert to admins\n'
                          '• The inactive member is never notified\n'
                          '• When the member opens the app, the alarm auto-resolves\n'
                          '• No "unusual-for-them" behavioral tracking (removed in P1.4)',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.45),
                            fontSize: 12,
                            height: 1.6,
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
}
