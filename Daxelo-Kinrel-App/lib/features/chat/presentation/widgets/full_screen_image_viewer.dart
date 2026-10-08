// lib/features/chat/presentation/widgets/full_screen_image_viewer.dart
//
// DAXELO KINREL — Full-Screen Image Viewer (v125)
//
// A WhatsApp-style full-screen image viewer with:
// - Pinch-to-zoom (InteractiveViewer)
// - Double-tap to zoom in/out
// - Swipe down to close
// - Dark background
// - Sender name + timestamp overlay
//
// Usage:
//   FullScreenImageViewer.show(
//     context,
//     imageUrl: url,
//     senderName: 'Manish',
//     timestamp: DateTime.now(),
//   );

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../../core/services/image_cache_manager.dart';
import '../../../../core/theme/kinrel_fx.dart';


class FullScreenImageViewer extends StatefulWidget {
  const FullScreenImageViewer({
    super.key,
    required this.imageUrl,
    this.senderName,
    this.timestamp,
    this.heroTag,
    this.closeOnTap = false,
  });

  final String imageUrl;
  final String? senderName;
  final DateTime? timestamp;

  /// Optional Hero tag for shared-element transitions from a source
  /// widget (e.g. a Timeline card's inline photo). When provided, the
  /// image is wrapped in a [Hero] widget with this tag.
  final String? heroTag;

  /// When true, tapping anywhere (outside zoom gestures) closes the
  /// viewer AND a subtle "Tap anywhere to close" hint is shown at the
  /// bottom. When false (default, for backward compat with chat), tap
  /// toggles the overlay instead.
  final bool closeOnTap;

  /// Opens the viewer as a full-screen route.
  static void show(
    BuildContext context, {
    required String imageUrl,
    String? senderName,
    DateTime? timestamp,
    String? heroTag,
    bool closeOnTap = false,
  }) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        pageBuilder: (_, __, ___) => FullScreenImageViewer(
          imageUrl: imageUrl,
          senderName: senderName,
          timestamp: timestamp,
          heroTag: heroTag,
          closeOnTap: closeOnTap,
        ),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  @override
  State<FullScreenImageViewer> createState() => _FullScreenImageViewerState();
}

class _FullScreenImageViewerState extends State<FullScreenImageViewer>
    with SingleTickerProviderStateMixin {
  final _transformationController = TransformationController();
  late AnimationController _fadeController;
  double _dragY = 0;
  bool _showOverlay = true;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _fadeController.forward();
  }

  @override
  void dispose() {
    _transformationController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  void _toggleOverlay() {
    setState(() => _showOverlay = !_showOverlay);
  }

  /// When [closeOnTap] is true, a single tap closes the viewer.
  /// When false, a single tap toggles the overlay (chat-mode behavior).
  void _onSingleTap() {
    if (widget.closeOnTap) {
      Navigator.of(context).pop();
    } else {
      _toggleOverlay();
    }
  }

  void _onDoubleTap() {
    if (_transformationController.value != Matrix4.identity()) {
      _transformationController.value = Matrix4.identity();
    } else {
      _transformationController.value = Matrix4.identity()..scale(2.0);
    }
  }

  /// Builds the CachedNetworkImage for the full-screen viewer.
  /// Extracted to a method so it can be wrapped in a [Hero] widget
  /// when [widget.heroTag] is provided (for shared-element transitions
  /// from a Timeline card's inline photo).
  ///
  /// Reuses the SAME cached URL + KinrelImageCacheManager instance as
  /// the card thumbnail — the image is already in the disk cache, so
  /// the full-screen viewer loads instantly. The memCacheWidth is
  /// capped to the physical screen width so we don't hold a 4K image
  /// in memory.
  Widget _buildImage() {
    return CachedNetworkImage(
      imageUrl: widget.imageUrl,
      cacheManager: KinrelImageCacheManager.instance,
      fit: BoxFit.contain,
      // Full-screen viewer: cap decode width to the physical screen
      // width so we don't hold a 4K image in memory when the device
      // is ~1080p. The card thumbnail uses memCacheWidth: 400 which
      // is already cached — the viewer loads a higher-res version
      // only if the screen is wider than 400 logical pixels.
      memCacheWidth: (MediaQuery.of(context).size.width *
              MediaQuery.of(context).devicePixelRatio)
          .toInt(),
      placeholder: (context, url) => const Center(
        child: CircularProgressIndicator(
          color: Colors.white,
        ),
      ),
      errorWidget: (_, __, ___) => const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.broken_image_outlined,
                size: 64, color: Colors.white54),
            SizedBox(height: 16),
            Text('Could not load image',
                style: TextStyle(color: Colors.white54)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        // Swipe down to close (only when not zoomed in).
        onVerticalDragUpdate: (details) {
          if (_transformationController.value == Matrix4.identity()) {
            setState(() => _dragY += details.delta.dy);
          }
        },
        onVerticalDragEnd: (details) {
          if (_dragY > 100) {
            Navigator.of(context).pop();
          } else {
            setState(() => _dragY = 0);
          }
        },
        onTap: _onSingleTap,
        onDoubleTap: _onDoubleTap,
        child: Stack(
          children: [
            // Image with zoom + pan.
            Transform.translate(
              offset: Offset(0, _dragY),
              child: InteractiveViewer(
                transformationController: _transformationController,
                minScale: 0.5,
                maxScale: 4.0,
                boundaryMargin: const EdgeInsets.all(double.infinity),
                child: Center(
                  child: widget.heroTag != null
                      ? Hero(
                          tag: widget.heroTag!,
                          child: _buildImage(),
                        )
                      : _buildImage(),
                ),
              ),
            ),

            // Top overlay: back button + sender info.
            if (_showOverlay)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    // PERF (Flat): solid black 70% in flat mode; gradient
                    // in rich mode. The scrim is a fixed-height header
                    // overlay, so a flat 70% black is visually equivalent
                    // for legibility.
                    decoration: BoxDecoration(
                      color: KinrelFx.rich
                          ? null
                          : Colors.black.withValues(alpha: 0.7),
                      gradient: KinrelFx.gradient(
                        LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.7),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (widget.senderName != null)
                                Text(
                                  widget.senderName!,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              if (widget.timestamp != null)
                                Text(
                                  _formatTimestamp(widget.timestamp!),
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.6),
                                    fontSize: 12,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // Subtle "Tap anywhere to close" hint (only when closeOnTap
            // is true — used by the Memories/Timeline feature).
            // Per the spec: small text, low visual prominence,
            // semi-transparent, positioned near the bottom safe area,
            // should not obstruct image content.
            if (widget.closeOnTap)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          'Tap anywhere to close',
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            // Drag-to-close hint at bottom (only when closeOnTap is
            // false — chat-mode behavior, shows only while dragging).
            if (!widget.closeOnTap && _showOverlay && _dragY > 10)
              Positioned(
                bottom: 50,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.keyboard_arrow_down,
                            color: Colors.white70, size: 20),
                        SizedBox(width: 4),
                        Text('Swipe down to close',
                            style:
                                TextStyle(color: Colors.white70, fontSize: 13)),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _formatTimestamp(DateTime dt) {
    final hour = dt.hour;
    final minute = dt.minute.toString().padLeft(2, '0');
    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
    final month = dt.month.toString().padLeft(2, '0');
    final day = dt.day.toString().padLeft(2, '0');
    return '$displayHour:$minute $period · $month/$day/${dt.year}';
  }
}
