import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/brand_colors.dart';
import '../../data/models/sparq_model.dart';
import '../../data/providers/sparq_provider.dart';

class SparqViewerScreen extends ConsumerStatefulWidget {
  const SparqViewerScreen({super.key, required this.userId});
  final String userId;

  @override
  ConsumerState<SparqViewerScreen> createState() => _SparqViewerScreenState();
}

class _SparqViewerScreenState extends ConsumerState<SparqViewerScreen>
    with TickerProviderStateMixin {
  int _currentIndex = 0;
  double _progress = 0.0;
  late AnimationController _progressController;
  bool _isPaused = false;
  List<SparqModel> _sparqs = [];

  @override
  void initState() {
    super.initState();
    _progressController = AnimationController(vsync: this);
    _progressController.addListener(() {
      setState(() => _progress = _progressController.value);
    });
    _progressController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _goToNext();
      }
    });
    _loadSparqs();
  }

  Future<void> _loadSparqs() async {
    try {
      final sparqs = await ref.read(userSparqsProvider(widget.userId).future);
      if (mounted && sparqs.isNotEmpty) {
        setState(() => _sparqs = sparqs);
        _startProgress();
      }
    } catch (e) {
      if (mounted) context.pop();
    }
  }

  void _startProgress() {
    if (_currentIndex >= _sparqs.length) {
      context.pop();
      return;
    }
    final sparq = _sparqs[_currentIndex];
    final durationMs = sparq.autoAdvanceDuration * 1000;
    _progressController.duration = Duration(milliseconds: durationMs);
    _progressController.forward(from: 0);
    // Mark as viewed
    ref.read(sparqProvider.notifier).markSparqViewed(sparq.id, sparq.userId);
    ref.read(sparqProvider.notifier).markLocalViewed(sparq.id);
  }

  void _goToNext() {
    if (_currentIndex < _sparqs.length - 1) {
      setState(() => _currentIndex++);
      _startProgress();
    } else {
      context.pop();
    }
  }

  void _goToPrevious() {
    if (_currentIndex > 0) {
      setState(() => _currentIndex--);
      _startProgress();
    }
  }

  void _togglePause() {
    if (_isPaused) {
      _progressController.forward();
    } else {
      _progressController.stop();
    }
    setState(() => _isPaused = !_isPaused);
  }

  Future<void> _deleteSparq() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: KinrelColors.elevation3,
        title: Text('Delete Sparq', style: TextStyle(color: Colors.white)),
        content: Text('Are you sure you want to delete this Sparq?',
            style: TextStyle(color: KinrelColors.textSilver)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: KinrelColors.textSilver)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete', style: TextStyle(color: KinrelColors.error)),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await ref.read(sparqProvider.notifier).deleteSparq(_sparqs[_currentIndex].id);
      if (_sparqs.length <= 1) {
        context.pop();
      } else {
        setState(() {
          _sparqs.removeAt(_currentIndex);
          if (_currentIndex >= _sparqs.length) _currentIndex = _sparqs.length - 1;
        });
        _startProgress();
      }
    }
  }

  @override
  void dispose() {
    _progressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_sparqs.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: KinrelColors.orange)),
      );
    }

    final sparq = _sparqs[_currentIndex];

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onVerticalDragEnd: (details) {
          if (details.primaryVelocity != null && details.primaryVelocity! > 300) {
            context.pop();
          }
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Content
            _buildSparqContent(sparq),

            // Progress bars at top
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              left: 8,
              right: 8,
              child: Row(
                children: List.generate(_sparqs.length, (i) {
                  return Expanded(
                    child: Container(
                      height: 2,
                      margin: const EdgeInsets.symmetric(horizontal: 1),
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(1),
                      ),
                      child: FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: i < _currentIndex
                            ? 1.0
                            : i == _currentIndex
                                ? _progress
                                : 0.0,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(1),
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),

            // Top bar: close + viewer count
            Positioned(
              top: MediaQuery.of(context).padding.top + 16,
              left: 8,
              right: 8,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: Icon(Icons.close, color: Colors.white, size: 24),
                    onPressed: () => context.pop(),
                  ),
                  Row(
                    children: [
                      Icon(Icons.visibility, color: Colors.white54, size: 16),
                      SizedBox(width: 4),
                      Text(
                        '${sparq.viewCount}',
                        style: TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Tap areas
            Positioned.fill(
              child: Row(
                children: [
                  Expanded(
                    flex: 1,
                    child: GestureDetector(onTap: _goToPrevious),
                  ),
                  Expanded(
                    flex: 2,
                    child: GestureDetector(
                      onTap: _togglePause,
                      onLongPress: _togglePause,
                    ),
                  ),
                ],
              ),
            ),

            // Family badge
            if (sparq.audience == 'FAMILY_ONLY')
              Positioned(
                bottom: MediaQuery.of(context).padding.bottom + 80,
                left: 16,
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: KinrelColors.orange.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: KinrelColors.orange, width: 1),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.family_restroom, size: 14, color: KinrelColors.orange),
                      SizedBox(width: 4),
                      Text('Family',
                        style: TextStyle(color: KinrelColors.orange, fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),

            // Delete button (creator only)
            Positioned(
              bottom: MediaQuery.of(context).padding.bottom + 80,
              right: 16,
              child: IconButton(
                icon: Icon(Icons.delete_outline, color: Colors.white54),
                onPressed: _deleteSparq,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSparqContent(SparqModel sparq) {
    switch (sparq.type) {
      case 'IMAGE':
        if (sparq.mediaUrl != null && sparq.mediaUrl!.isNotEmpty) {
          return Center(
            child: Image.network(sparq.mediaUrl!, fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => _buildErrorContent(),
            ),
          );
        }
        return _buildErrorContent();
      case 'VIDEO':
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.play_circle_outline, size: 64, color: Colors.white54),
              SizedBox(height: 12),
              Text('Video Sparq', style: TextStyle(color: Colors.white54, fontSize: 14)),
            ],
          ),
        );
      case 'TEXT':
        return Container(
          color: _parseBackgroundColor(sparq.backgroundColor),
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Text(
                sparq.text ?? '',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Outfit',
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        );
      case 'VOICE':
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.graphic_eq, size: 64, color: KinrelColors.orange),
              SizedBox(height: 12),
              Text('Voice Note', style: TextStyle(color: Colors.white54, fontSize: 14)),
              SizedBox(height: 4),
              Text('${sparq.duration ?? 0}s',
                style: TextStyle(color: Colors.white38, fontSize: 12)),
            ],
          ),
        );
      default:
        return _buildErrorContent();
    }
  }

  Color _parseBackgroundColor(String? hex) {
    if (hex == null || hex.isEmpty) return KinrelColors.elevation1;
    try {
      return Color(int.parse(hex.replaceFirst('#', 'FF'), radix: 16));
    } catch (_) {
      return KinrelColors.elevation1;
    }
  }

  Widget _buildErrorContent() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.broken_image, size: 48, color: Colors.white38),
          SizedBox(height: 8),
          Text('Content unavailable', style: TextStyle(color: Colors.white38)),
        ],
      ),
    );
  }
}
