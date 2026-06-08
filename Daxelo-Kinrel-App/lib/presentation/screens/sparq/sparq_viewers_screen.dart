// lib/presentation/screens/sparq/sparq_viewers_screen.dart
//
// DAXELO KINREL — Sparq Viewers Screen
//
// Simple list of users who viewed a Sparq:
//   Avatar + name + timeago since viewed

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../data/repositories/follow_repository.dart';
import '../../../data/repositories/sparq_repository.dart';

class SparqViewersScreen extends ConsumerStatefulWidget {
  const SparqViewersScreen({
    super.key,
    required this.sparqId,
  });

  final String sparqId;

  @override
  ConsumerState<SparqViewersScreen> createState() => _SparqViewersScreenState();
}

class _SparqViewersScreenState extends ConsumerState<SparqViewersScreen> {
  List<UserModel> _viewers = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadViewers();
  }

  Future<void> _loadViewers() async {
    try {
      final repo = ref.read(sparqRepositoryProvider);
      final viewers = await repo.getSparqViewers(widget.sparqId);
      if (mounted) {
        setState(() {
          _viewers = viewers;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load viewers';
          _isLoading = false;
        });
      }
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
          icon: const Icon(Icons.arrow_back, color: KinrelColors.textWhite),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Viewers',
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: KinrelColors.textWhite,
          ),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return Center(
        child: CircularProgressIndicator(color: KinrelColors.orange),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: KinrelColors.error),
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 14,
                color: KinrelColors.textSilver,
              ),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () {
                setState(() {
                  _isLoading = true;
                  _error = null;
                });
                _loadViewers();
              },
              child: Text(
                'Retry',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  color: KinrelColors.orange,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (_viewers.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.visibility_off_outlined, size: 48, color: KinrelColors.textDim),
            const SizedBox(height: 12),
            Text(
              'No viewers yet',
              style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: KinrelColors.textWhite,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Viewers will appear here when someone views your Sparq',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 13,
                color: KinrelColors.textDim,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _viewers.length,
      separatorBuilder: (_, __) => Divider(
        height: 1,
        thickness: 0.5,
        color: KinrelColors.border,
        indent: 72,
      ),
      itemBuilder: (context, index) {
        final viewer = _viewers[index];
        return ListTile(
          leading: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: KinrelColors.orange.withValues(alpha: 0.1),
              image: viewer.avatarUrl != null
                  ? DecorationImage(
                      image: NetworkImage(viewer.avatarUrl!),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: viewer.avatarUrl != null
                ? null
                : Center(
                    child: Text(
                      viewer.initials,
                      style: TextStyle(
                        fontFamily: 'Outfit',
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: KinrelColors.orange,
                      ),
                    ),
                  ),
          ),
          title: Text(
            viewer.displayName,
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: KinrelColors.textWhite,
            ),
          ),
        );
      },
    );
  }
}
