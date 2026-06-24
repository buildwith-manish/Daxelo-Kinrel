// lib/features/family/presentation/services/graph_export_service.dart
//
// DAXELO KINREL — Graph Share / Export (Step 5).
//
// Captures a RepaintBoundary (the on-screen graph) to a PNG and shares it via
// the OS share sheet. Sharing uses in-memory bytes (XFile.fromData) so it works
// on web as well as mobile/desktop — no file write required.
//
// PNG is shipped now; PDF is structured for later (see GraphExportFormat and
// the TODO in [shareGraph]). Gated by kEnableGraphShareExport at call sites.

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:share_plus/share_plus.dart' as share_plus;

/// Output formats for graph export. Only [png] is implemented today.
enum GraphExportFormat { png, pdf }

/// Captures and shares a graph rendered under a keyed [RepaintBoundary].
class GraphExportService {
  const GraphExportService._();

  /// Captures the [RepaintBoundary] identified by [boundaryKey] to PNG bytes.
  ///
  /// Returns null if the boundary isn't mounted/painted yet. [pixelRatio]
  /// trades file size for sharpness (3.0 ≈ retina).
  static Future<Uint8List?> capturePngBytes(
    GlobalKey boundaryKey, {
    double pixelRatio = 3.0,
  }) async {
    final renderObject = boundaryKey.currentContext?.findRenderObject();
    if (renderObject is! RenderRepaintBoundary) return null;

    // If the layer is still dirty, give it one frame to settle.
    if (renderObject.debugNeedsPaint) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }

    final ui.Image image = await renderObject.toImage(pixelRatio: pixelRatio);
    try {
      final byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }

  /// Captures the graph and opens the OS share sheet with the image attached.
  ///
  /// Returns true if a shareable image was produced. [format] is accepted for
  /// forward-compatibility; [GraphExportFormat.pdf] is not implemented yet and
  /// falls back to PNG.
  static Future<bool> shareGraph(
    GlobalKey boundaryKey, {
    String subject = 'My family graph',
    String fileName = 'kinrel_family_graph.png',
    double pixelRatio = 3.0,
    GraphExportFormat format = GraphExportFormat.png,
  }) async {
    // TODO(pdf): when a pdf/printing package is added, render the PNG into a
    // single-page PDF here and switch the XFile mimeType to application/pdf.
    final bytes = await capturePngBytes(boundaryKey, pixelRatio: pixelRatio);
    if (bytes == null) return false;

    final xfile = share_plus.XFile.fromData(
      bytes,
      name: fileName,
      mimeType: 'image/png',
    );
    await share_plus.Share.shareXFiles(<share_plus.XFile>[xfile],
        subject: subject);
    return true;
  }
}
