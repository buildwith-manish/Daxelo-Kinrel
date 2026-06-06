// Smoke test — verifies KinrelApp widget renders without crashing.
// This replaces the previous `1+1=2` placeholder.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kinrel/app.dart';

void main() {
  testWidgets('KinrelApp renders without crashing', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: KinrelApp()),
    );
    await tester.pump(const Duration(seconds: 1));

    // The widget tree should contain a KinrelApp instance
    expect(find.byType(KinrelApp), findsOneWidget);
  });
}
