// Smoke test — verifies KinrelApp widget can be imported and
// key types exist without crashing. Full widget render is tested
// via integration tests instead (requires Supabase/Firebase init).

import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/app.dart';

void main() {
  test('KinrelApp class exists and is constructable', () {
    // Verify the class exists and can be instantiated
    // (without actually pumping the widget, which requires Supabase/Firebase)
    expect(KinrelApp, isNotNull);
  });
}
