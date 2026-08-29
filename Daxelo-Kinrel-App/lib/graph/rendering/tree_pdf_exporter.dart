// lib/graph/rendering/tree_pdf_exporter.dart
//
// DAXELO KINREL — Family Tree PDF Exporter (vector, paginated)
//
// Family Space: Graph ↔ Tree (↔ Map) — v5.126 follow-up.
//
// Re-runs HierarchicalLayout + TreePainter against a PdfCanvas (via the
// `pdf` + `printing` packages already in pubspec.yaml) so the Tree-view
// export is:
//   - VECTOR (pixel-crisp at any zoom, no rasterization)
//   - PAGINATED BY GENERATION ROW (each page = one or more rows)
//   - SHAREABLE via the platform's native share sheet (printing package)
//
// Why a separate exporter (and not a screenshot of the phone screen):
//   The phone screen shows a panned/zoomed subset of the tree. A raster
//   screenshot would be blurry at high zoom and would only contain what
//   was visible at capture time. By re-running the layout against a
//   PdfCanvas, we get the WHOLE tree, paginated, vector — exactly the
//   "print the family tree" experience genealogy apps offer.
//
// Pipeline:
//   1. Run HierarchicalLayout.compute() → positions (Map<personId, Offset>)
//   2. Group positions by BFS generation row.
//   3. For each page-worth of rows (maxRowsPerPage), create a Page in
//      the Document with a CustomPaint that:
//        a) Translates the PdfGraphics so the page's first-row Y lands
//           at the page top.
//        b) Calls TreePainter.paintToAdapter(PdfTreeCanvasAdapter(g))
//           to draw all connectors within the page's Y range.
//        c) Draws each node (avatar circle + name text) within the
//           page's Y range.
//   4. Returns the PDF bytes; the caller (Tree view's "Export" button)
//      hands them to `Printing.sharePdf(bytes: ..., filename: ...)`.
//
// All layout uses the SAME HierarchicalLayout.compute() the in-app
// Tree view uses, so the export matches what the user sees on screen.

import 'dart:typed_data';

import 'package:flutter/material.dart' show Color, Offset, Size;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:vector_math/vector_math_64.dart' show Matrix4;

import '../../core/services/graph_layout_service.dart';
import '../engine/hierarchical_layout.dart';
import 'tree_painter.dart';

/// Generates a vector PDF of the family tree, paginated by generation row.
class TreePdfExporter {
  TreePdfExporter({
    this.pageFormat = PdfPageFormat.a3,
    this.maxRowsPerPage = 4,
    this.nodeTileSize = const Size(96.0, 96.0),
  });

  /// PDF page format. A3 default = bigger canvas per page (fewer pages
  /// for the same family). Override to A4 for consumer printers.
  final PdfPageFormat pageFormat;

  /// Max BFS generation rows per page. With levelSpacing=170dp and
  /// A3 landscape height ≈ 842pt, 4 rows × 170 = 680pt fits with
  /// room for header + footer.
  final int maxRowsPerPage;

  /// Node tile size — must match `kTreeNodeSize` used by the in-app
  /// Tree view so the PDF and screen renderings match exactly.
  final Size nodeTileSize;

  /// Generate the PDF bytes for [persons] + [relationships].
  ///
  /// [familyName] is rendered as a header on each page.
  /// [anchorPersonId] is passed to HierarchicalLayout for the anchor
  /// selection (though v5.126's one-pass root finding means the anchor
  /// no longer affects which nodes are roots — it only affects the
  /// cycle-breaking fallback).
  Future<Uint8List> export({
    required List<GraphPerson> persons,
    required List<GraphRelationship> relationships,
    String? anchorPersonId,
    String? familyName,
  }) async {
    if (persons.isEmpty) {
      return _emptyDocument(familyName: familyName);
    }

    // 1. Run the layout (vector positions, generation-locked Y).
    final layout = HierarchicalLayout(
      config: HierarchicalLayoutConfig(
        siblingSpacing: 110.0,
        levelSpacing: 170.0,
        spouseGap: 28.0,
        padding: 80.0,
        nodeWidth: nodeTileSize.width,
        nodeHeight: nodeTileSize.height,
      ),
    );

    final layoutResult = layout.compute(
      persons: persons,
      relationships: relationships,
      anchorPersonId: anchorPersonId,
    );

    if (layoutResult.positions.isEmpty) {
      return _emptyDocument(familyName: familyName);
    }

    // 2. Group persons by BFS generation row (using their Y coordinate).
    //    We can't read bfsGen directly (it's internal to the layout),
    //    so we derive it from Y — which is generation-locked by the fix.
    final rowYs = <double>{
      for (final pos in layoutResult.positions.values) pos.dy,
    }.toList()
      ..sort();

    // Cluster nearby Y values into discrete rows (BFS gens map 1:1 to Y
    // levels, but rounding tolerance lets us treat anything within 1pt
    // as the same row).
    final rows = <double>[];
    for (final y in rowYs) {
      if (rows.isEmpty || (y - rows.last).abs() > 1.0) {
        rows.add(y);
      }
    }

    // 3. Build the edges list for TreePainter (same dedup logic the
    //    in-app Tree view uses).
    final edges =
        <({String fromId, String toId, String relationshipKey})>[];
    final seenPairs = <String>{};
    for (final r in relationships) {
      final from = r.fromPersonId;
      final to = r.toPersonId;
      if (from.isEmpty || to.isEmpty) continue;
      final key = r.relationshipKey.toLowerCase();
      if (!TreePainter.kSpouseKeys.contains(key) &&
          !TreePainter.kParentKeys.contains(key) &&
          !TreePainter.kChildKeys.contains(key)) {
        continue;
      }
      final pairKey = [from, to]..sort();
      final canonical = '${pairKey[0]}|${pairKey[1]}';
      if (seenPairs.contains(canonical)) continue;
      seenPairs.add(canonical);
      edges.add((fromId: from, toId: to, relationshipKey: key));
    }

    // 4. Build the PDF document.
    final pdf = pw.Document();

    // Resolve fonts once (Type1 fonts are cheap, but resolution
    // requires a PdfDocument which is only available inside the build
    // callback). We declare them as lazy `pw.Font` instances here and
    // resolve them per-page inside the build callback via `getFont(ctx)`.
    final headerFontDecl = pw.Font.helveticaBold();
    final bodyFontDecl = pw.Font.helvetica();

    // 5. Paginate: each page covers [maxRowsPerPage] rows.
    final totalPages = (rows.length / maxRowsPerPage).ceil();
    for (var pageIdx = 0; pageIdx < totalPages; pageIdx++) {
      final pageStartRowIdx = pageIdx * maxRowsPerPage;
      final pageEndRowIdx =
          (pageIdx + 1) * maxRowsPerPage > rows.length
              ? rows.length
              : (pageIdx + 1) * maxRowsPerPage;
      final pageRows = rows.sublist(pageStartRowIdx, pageEndRowIdx);
      final pageYStart = pageRows.first;
      final pageYEnd = pageRows.last;

      // Filter positions + persons to those visible on this page.
      final pagePersons = persons.where((p) {
        final pos = layoutResult.positions[p.id];
        return pos != null &&
            pos.dy >= pageYStart - 1.0 &&
            pos.dy <= pageYEnd + 1.0;
      }).toList();

      pdf.addPage(
        pw.Page(
          pageFormat: pageFormat.landscape,
          margin: const pw.EdgeInsets.all(40),
          build: (pw.Context context) {
            // Resolve the fonts against this document.
            final headerFont = headerFontDecl.getFont(context);
            final bodyFont = bodyFontDecl.getFont(context);

            return pw.CustomPaint(
              size: PdfPoint(
                pageFormat.landscape.availableWidth,
                pageFormat.landscape.availableHeight,
              ),
              painter: (PdfGraphics g, PdfPoint size) {
                _paintPage(
                  g,
                  size,
                  headerFont: headerFont,
                  bodyFont: bodyFont,
                  positions: layoutResult.positions,
                  edges: edges,
                  persons: pagePersons,
                  yStart: pageYStart,
                  yEnd: pageYEnd,
                  canvasWidth: layoutResult.canvasWidth,
                  nodeTileSize: nodeTileSize,
                  familyName: familyName,
                  pageIdx: pageIdx,
                  totalPages: totalPages,
                );
              },
            );
          },
        ),
      );
    }

    return pdf.save();
  }

  /// Empty-document fallback for families with no persons.
  Future<Uint8List> _emptyDocument({String? familyName}) async {
    final pdf = pw.Document();
    pdf.addPage(
      pw.Page(
        pageFormat: pageFormat,
        build: (pw.Context context) => pw.Center(
          child: pw.Text(
            familyName == null
                ? 'No family members yet.'
                : 'The $familyName family has no members yet.',
            style: pw.TextStyle(fontSize: 14),
          ),
        ),
      ),
    );
    return pdf.save();
  }
}

/// Paint a single PDF page (one or more generation rows).
///
/// Static (not an instance method) because each page has different
/// [yStart]/[yEnd]/[persons]/[pageIdx] — passing them explicitly is
/// cleaner than storing per-page state on the exporter instance.
void _paintPage(
  PdfGraphics g,
  PdfPoint pageSize, {
  required PdfFont headerFont,
  required PdfFont bodyFont,
  required Map<String, Offset> positions,
  required List<({String fromId, String toId, String relationshipKey})> edges,
  required List<GraphPerson> persons,
  required double yStart,
  required double yEnd,
  required double canvasWidth,
  required Size nodeTileSize,
  required String? familyName,
  required int pageIdx,
  required int totalPages,
}) {
  // Header text (top-left, in PDF coords — origin bottom-left).
  if (familyName != null) {
    // Note: Type1 fonts (Helvetica) only support Latin1 characters, so
    // we use a plain ASCII hyphen instead of an em-dash. To use Unicode
    // (em-dash, non-Latin names, etc.), bundle a TrueType font via
    // Font.ttf(ByteData) and pass it to drawString instead.
    g
      ..setFillColor(PdfColor.fromInt(0xFFF5F0EE))
      ..drawString(
        headerFont,
        18,
        '$familyName - Family Tree',
        0,
        pageSize.y - 24,
      );
  }

  // Footer (page X of Y, bottom-right).
  g
    ..setFillColor(PdfColor.fromInt(0xFFC9B4A8))
    ..drawString(
      bodyFont,
      10,
      'Page ${pageIdx + 1} of $totalPages',
      pageSize.x - 120,
      12,
    );

  // Compute the scale + translate so this page's Y range fits within
  // the available canvas area (minus header/footer).
  const headerHeight = 40.0;
  const footerHeight = 30.0;
  final availableHeight = pageSize.y - headerHeight - footerHeight;
  final availableWidth = pageSize.x;

  final pageRange = (yEnd - yStart) + nodeTileSize.height;
  final scaleY = availableHeight / pageRange;
  final scaleX = availableWidth / canvasWidth;
  // Use the MINIMUM so the layout doesn't distort.
  final scale = scaleY < scaleX ? scaleY : scaleX;

  g.saveContext();

  // Apply the transform: PDF Y goes UP, our layout Y goes DOWN.
  //   pdfX = layoutX * scale + (leftMargin - scale * layoutPadding)
  //   pdfY = pageSize.y - topMargin - (layoutY - 0) * scale  (with Y flip)
  const leftMargin = 20.0;
  const topMargin = headerHeight;
  const layoutPadding = 80.0; // matches HierarchicalLayoutConfig.padding

  final tx = leftMargin - (scale * layoutPadding);
  final ty = pageSize.y - topMargin - (scale * yStart);

  final mat = Matrix4.identity()
    ..translateByDouble(tx, ty, 0, 1)
    ..scaleByDouble(scale, -scale, 1, 1);

  g.setTransform(mat);

  // ── Draw connectors (via the shared TreePainter.paintToAdapter) ──
  // Filter edges to those whose EITHER endpoint is within this page's
  // Y range. Partial lines (one endpoint off-page) terminate cleanly
  // at the node edge because TreePainter accounts for nodeSize.
  final pageEdges =
      <({String fromId, String toId, String relationshipKey})>[];
  for (final edge in edges) {
    final fromPos = positions[edge.fromId];
    final toPos = positions[edge.toId];
    if (fromPos == null || toPos == null) continue;
    final fromOnPage =
        fromPos.dy >= yStart - 1.0 && fromPos.dy <= yEnd + 1.0;
    final toOnPage =
        toPos.dy >= yStart - 1.0 && toPos.dy <= yEnd + 1.0;
    if (fromOnPage || toOnPage) {
      pageEdges.add(edge);
    }
  }

  final painter = TreePainter(
    positions: positions,
    edges: pageEdges,
    nodeSize: nodeTileSize,
    color: const Color(0x99E2E8F0),
    strokeWidth: 1.5,
  );
  painter.paintToAdapter(_PdfTreeCanvasAdapter(g));

  // ── Draw nodes (avatar circle + name text) ─────────────────────
  final avatarRadius = nodeTileSize.width / 2 * 0.6; // 60% of tile

  for (final person in persons) {
    final pos = positions[person.id];
    if (pos == null) continue;
    if (pos.dy < yStart - 1.0 || pos.dy > yEnd + 1.0) continue;

    // Avatar background (dark fill + light border).
    g
      ..setFillColor(PdfColor.fromInt(0xFF191B2C))
      ..setStrokeColor(PdfColor.fromInt(0xFFE8612A))
      ..setLineWidth(1.5)
      ..drawEllipse(
        pos.dx,
        pos.dy,
        avatarRadius,
        avatarRadius,
      )
      ..fillPath();

    // Initial letter (centered on the avatar).
    final initial =
        person.name.isNotEmpty ? person.name[0].toUpperCase() : '?';
    g
      ..setFillColor(PdfColor.fromInt(0xFFF5F0EE))
      ..drawString(
        bodyFont,
        14,
        initial,
        pos.dx - 5,
        pos.dy - 5,
      );

    // Name (centered, below the avatar).
    // Truncate to 14 chars to fit the tile width. Use ASCII ellipsis
    // "..." because Type1 fonts (Helvetica) don't support Unicode.
    final name = person.name.length > 14
        ? '${person.name.substring(0, 14)}...'
        : person.name;
    g
      ..setFillColor(PdfColor.fromInt(0xFFF5F0EE))
      ..drawString(
        bodyFont,
        8,
        name,
        pos.dx - (name.length * 3.5),
        pos.dy - avatarRadius - 12,
      );
  }

  g.restoreContext();
}

/// Adapter that wraps a `PdfGraphics` so it implements [TreeCanvasAdapter].
///
/// Used by [TreePainter.paintToAdapter] to draw connectors into a PDF
/// instead of a Flutter canvas. Single method — `drawLine` — handles
/// color + stroke width conversion.
class _PdfTreeCanvasAdapter implements TreeCanvasAdapter {
  _PdfTreeCanvasAdapter(this._graphics);

  final PdfGraphics _graphics;

  @override
  void drawLine(Offset from, Offset to, Color color, double strokeWidth) {
    final pdfColor = PdfColor.fromInt(
      // Color.value is ARGB int (0xAARRGGBB); PdfColor.fromInt expects
      // 0xAARRGGBB as well — same format. So direct conversion works.
      color.value,
    );
    _graphics
      ..setStrokeColor(pdfColor)
      ..setLineWidth(strokeWidth)
      // StrokeCap.round would require drawing arcs at each end — for
      // the PDF we accept default (butt) cap to keep the export simple.
      // The visual difference is invisible at typical zoom levels.
      ..drawLine(from.dx, from.dy, to.dx, to.dy)
      ..strokePath();
  }
}
