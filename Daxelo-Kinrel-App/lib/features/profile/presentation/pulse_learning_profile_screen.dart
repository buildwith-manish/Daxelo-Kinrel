// lib/features/profile/presentation/pulse_learning_profile_screen.dart
//
// P1.3: Transparency screen for smart notification timing.
//
// Shows the user exactly what the ML has learned about their engagement
// patterns: hour-of-day histogram, weekday histogram, confidence, when it
// was last updated, and a "Reset" button that deletes the data.
//
// Mirrors the Trackc Learning Profile transparency pattern per spec step 5.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_typography.dart';
import '../../../core/networking/dio_client.dart' show dioProvider;

// ── Design Tokens (match quiet_hours_screen) ──────────────────────
const Color _bg = Color(0xFF131416);
const Color _cardBg = Color(0xFF191B2C);
const Color _orange = Color(0xFFE8612A);
const Color _textPrimary = Color(0xFFF5F0EE);
const Color _textSecondary = Color(0xFFC9B4A8);
const Color _textDim = Color(0xFF8A7A72);
const Color _borderSubtle = Color(0x0FFFFFFF);

class PulseLearningProfileScreen extends ConsumerStatefulWidget {
  const PulseLearningProfileScreen({super.key});

  @override
  ConsumerState<PulseLearningProfileScreen> createState() =>
      _PulseLearningProfileScreenState();
}

class _PulseLearningProfileScreenState
    extends ConsumerState<PulseLearningProfileScreen> {
  bool _optedIn = false;
  Map<String, dynamic>? _profile;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final dio = ref.read(dioProvider);
      final r = await dio.get('/api/notifications/engagement-profile');
      if (mounted) {
        setState(() {
          _optedIn = (r.data['optedIn'] as bool?) ?? false;
          _profile = r.data['profile'] as Map<String, dynamic>?;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not load your engagement profile.';
          _loading = false;
        });
      }
    }
  }

  Future<void> _resetProfile() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _cardBg,
        title: const Text('Reset engagement profile',
            style: TextStyle(color: _textPrimary)),
        content: const Text(
          'This will delete all of Kinrel\'s learned data about your '
          'notification engagement patterns. The data will be rebuilt '
          'from scratch as you continue using the app.',
          style: TextStyle(color: _textSecondary, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: _textDim)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reset', style: TextStyle(color: _orange)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final dio = ref.read(dioProvider);
      await dio.delete('/api/notifications/engagement-profile');
      await _loadProfile();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not reset. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: _textPrimary),
          onPressed: () => context.pop(),
        ),
        title: const Text(
          'What Kinrel Learned',
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: _textPrimary,
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _orange))
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(_error!,
                        style: const TextStyle(color: _textDim),
                        textAlign: TextAlign.center),
                  ),
                )
              : _buildContent(),
    );
  }

  Widget _buildContent() {
    if (!_optedIn) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline, color: _textDim, size: 48),
              const SizedBox(height: 16),
              const Text(
                'Smart notification timing is off',
                style: TextStyle(
                    color: _textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                'When you enable smart notification timing, Kinrel will '
                'learn your active hours and show the learned data here. '
                'You can turn it on in Quiet Hours settings.',
                style: const TextStyle(color: _textDim, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    if (_profile == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.hourglass_empty, color: _textDim, size: 48),
              const SizedBox(height: 16),
              const Text(
                'No data yet',
                style: TextStyle(
                    color: _textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              const Text(
                'Kinrel needs at least 10 engagement samples before it '
                'can learn your active hours. Keep using the app — your '
                'profile will appear here.',
                style: TextStyle(color: _textDim, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    final hourHistogram = (_profile!['hourHistogram'] as List)
        .map((e) => (e as num).toInt())
        .toList();
    final totalSamples = (_profile!['totalSamples'] as num).toInt();
    final updatedAt = _profile!['updatedAt'] as String?;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Summary card ──
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _cardBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _borderSubtle),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Summary',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: _orange,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 12),
                _summaryRow('Total samples', '$totalSamples'),
                if (updatedAt != null)
                  _summaryRow(
                      'Last updated',
                      DateTime.parse(updatedAt)
                          .toLocal()
                          .toString()
                          .split('.')
                          .first),
                _summaryRow('Minimum for predictions', '10 samples'),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // ── Hour histogram ──
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _cardBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _borderSubtle),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Activity by hour',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: _orange,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'When you are most likely to engage with notifications.',
                  style: TextStyle(color: _textDim, fontSize: 12),
                ),
                const SizedBox(height: 16),
                _buildHourHistogram(hourHistogram),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // ── Reset button ──
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _resetProfile,
              style: OutlinedButton.styleFrom(
                foregroundColor: _orange,
                side: BorderSide(color: _orange.withValues(alpha: 0.4)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const Text('Reset engagement profile',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: _textDim, fontSize: 13)),
          Text(value,
              style: const TextStyle(
                  color: _textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildHourHistogram(List<int> hours) {
    final maxCount = hours.reduce((a, b) => a > b ? a : b);
    if (maxCount == 0) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text('No engagement recorded yet.',
              style: TextStyle(color: _textDim, fontSize: 13)),
        ),
      );
    }
    return SizedBox(
      height: 120,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(24, (h) {
          final count = hours[h];
          final heightPct = count / maxCount;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Container(
                    height: 80 * heightPct,
                    decoration: BoxDecoration(
                      color: _orange.withValues(alpha: 0.3 + 0.7 * heightPct),
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(2)),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$h',
                    style: TextStyle(
                        color: _textDim,
                        fontSize: 8,
                        fontWeight: h % 6 == 0
                            ? FontWeight.w700
                            : FontWeight.w400),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}
