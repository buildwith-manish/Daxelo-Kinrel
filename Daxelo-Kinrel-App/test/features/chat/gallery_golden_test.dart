// Golden capture: renders the Chat UI Gallery's group-chat page with the
// REAL fonts + the REAL widgets so the "Papa · Father" kinship header
// rows, the neutral relationship label, and the left-edge vertical color
// indicators can be visually verified against the chat UI reference
// screenshot.
//
// Regenerate with:
//   flutter test test/features/chat/gallery_golden_test.dart --update-goldens
import 'dart:io';
import 'dart:typed_data' show Uint8List;
import 'dart:ui' show loadFontFromList;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/features/chat/presentation/chat_ui_gallery.dart';

Future<void> _loadRealFonts() async {
  // dart:ui loadFontFromList registers the font family globally for
  // the test VM (the modern replacement for the removed FontLoader).
  for (final font in const [
    ('DMSans', 'assets/fonts/DMSans-Regular.ttf'),
    ('DMSans', 'assets/fonts/DMSans-Medium.ttf'),
    ('DMSans', 'assets/fonts/DMSans-SemiBold.ttf'),
    ('Outfit', 'assets/fonts/Outfit-Regular.ttf'),
    ('Outfit', 'assets/fonts/Outfit-Medium.ttf'),
  ]) {
    final data = File(font.$2).readAsBytesSync();
    await loadFontFromList(Uint8List.view(data.buffer), fontFamily: font.$1);
  }
}

void main() {
  testWidgets('golden: gallery group-chat page — kinship headers + bands',
      (tester) async {
    await _loadRealFonts();
    await tester.binding.setSurfaceSize(const Size(720, 1440));
    tester.view.physicalSize = const Size(720, 1440);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const ChatUiGalleryApp());
    // The gallery is a PageView — page 1 is the group chat.
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(ChatUiGallery),
      matchesGoldenFile('goldens/gallery_group_chat.png'),
    );
  });
}
