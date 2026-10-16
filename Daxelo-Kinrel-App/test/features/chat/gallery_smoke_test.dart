// Smoke test: the UI gallery boots and renders the group-chat page with
// the kinship-aware "Name · Relationship" sender rows.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/features/chat/presentation/chat_ui_gallery.dart';

void main() {
  testWidgets('ChatUiGallery boots and renders the group chat page',
      (tester) async {
    await tester.pumpWidget(const ChatUiGalleryApp());
    await tester.pumpAndSettle();

    // The group-chat page shows the sample conversation.
    expect(find.text('Dinner at 8, everyone coming?'), findsOneWidget);
    expect(find.text('I will bring the sweets.'), findsOneWidget);
    expect(find.text('Yes, on my way.'), findsOneWidget);

    // Kinship header rows exist as multi-span RichTexts.
    final headers = tester
        .widgetList<RichText>(find.byType(RichText))
        .where((rt) =>
            rt.text is TextSpan &&
            ((rt.text as TextSpan).children?.length ?? 0) >= 5)
        .toList();
    expect(headers.length, 3, reason: 'Papa + Nani + Meera sender header rows');
    final papaHeader =
        headers.where((h) => h.text.toPlainText().contains('Papa')).first;
    expect(papaHeader.text.toPlainText(), contains('Father'));
    final naniHeader =
        headers.where((h) => h.text.toPlainText().contains('Nani')).first;
    expect(naniHeader.text.toPlainText(), contains('Maternal grandmother'));
  });
}
