// lib/features/family/presentation/widgets/image_crop_editor.dart
//
// DAXELO KINREL — Lightweight Image Crop Editor (v119)
//
// A self-contained crop editor that lets the user pan/zoom an image
// and crop it to a square (displayed as a circle in the avatar).
// Uses Flutter's built-in InteractiveViewer — no extra packages needed.
//
// Usage:
//   final croppedBytes = await ImageCropEditor.show(
//     context,
//     imageBytes: rawBytes,
//   );
//   if (croppedBytes != null) { /* upload croppedBytes */ }

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../../core/constants/brand_colors.dart';
import '../../../../core/constants/brand_typography.dart';

class ImageCropEditor extends StatefulWidget {
  const ImageCropEditor({
    super.key,
    required this.imageBytes,
    this.title = 'Crop Image',
  });

  final Uint8List imageBytes;
  final String title;

  /// Shows the crop editor as a full-screen modal.
  /// Returns the cropped image bytes, or null if the user cancels.
  static Future<Uint8List?> show(
    BuildContext context, {
    required Uint8List imageBytes,
    String title = 'Crop Profile Picture',
  }) {
    return Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(
        builder: (_) => ImageCropEditor(
          imageBytes: imageBytes,
          title: title,
        ),
        fullscreenDialog: true,
      ),
    );
  }

  @override
  State<ImageCropEditor> createState() => _ImageCropEditorState();
}

class _ImageCropEditorState extends State<ImageCropEditor> {
  final _controller = TransformationController();
  final _cropKey = GlobalKey();
  ui.Image? _decodedImage;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _decodeImage();
  }

  Future<void> _decodeImage() async {
    final codec = await ui.instantiateImageCodec(widget.imageBytes);
    final frame = await codec.getNextFrame();
    if (mounted) setState(() => _decodedImage = frame.image);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _cropAndReturn() async {
    if (_decodedImage == null || _isProcessing) return;
    setState(() => _isProcessing = true);

    try {
      // Capture the crop area via a RepaintBoundary.
      // The cropKey boundary wraps just the image area (square).
      final boundary = _cropKey.currentContext!.findRenderObject()
          as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(
        format: ui.ImageByteFormat.png,
      );

      if (byteData != null && mounted) {
        Navigator.of(context).pop(byteData.buffer.asUint8List());
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not crop image: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancel', style: TextStyle(color: Colors.white)),
        ),
        title: Text(
          widget.title,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        actions: [
          TextButton(
            onPressed: _isProcessing ? null : _cropAndReturn,
            child: _isProcessing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: KinrelColors.orange,
                    ),
                  )
                : const Text(
                    'Save',
                    style: TextStyle(
                      color: KinrelColors.orange,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
          ),
        ],
      ),
      body: _decodedImage == null
          ? const Center(
              child: CircularProgressIndicator(color: KinrelColors.orange),
            )
          : SafeArea(
              child: Column(
                children: [
                  // Hint text
                  Padding(
                    padding: const EdgeInsets.only(top: 16, bottom: 8),
                    child: Text(
                      'Drag to position • Pinch to zoom',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 13,
                      ),
                    ),
                  ),
                  // Crop area
                  Expanded(
                    child: Center(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          // Square crop area — as large as possible.
                          final cropSize = math.min(
                            constraints.maxWidth * 0.85,
                            constraints.maxHeight * 0.85,
                          );
                          return Container(
                            width: cropSize,
                            height: cropSize,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: KinrelColors.orange.withValues(alpha: 0.6),
                                width: 2,
                              ),
                            ),
                            child: ClipOval(
                              child: RepaintBoundary(
                                key: _cropKey,
                                child: InteractiveViewer(
                                  controller: _controller,
                                  minScale: 0.5,
                                  maxScale: 4.0,
                                  boundaryMargin:
                                      const EdgeInsets.all(double.infinity),
                                  clipBehavior: Clip.none,
                                  child: Image.memory(
                                    widget.imageBytes,
                                    fit: BoxFit.contain,
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  // Recommended dimensions hint
                  Padding(
                    padding: const EdgeInsets.only(bottom: 24, top: 8),
                    child: Text(
                      'Recommended: 512×512',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.3),
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
