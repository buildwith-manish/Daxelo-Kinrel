// lib/features/family/presentation/contact_picker_helper_stub.dart
//
// Web stub for contact_picker_helper — returns null (no contact picking
// on web). Used via conditional import when dart.library.io is not
// available (i.e. on web builds).

import 'contact_picker_helper.dart';

Future<PickedContact?> _pickContactImpl() async {
  // Contacts are not available on web — return null to indicate
  // the user "cancelled" (the calling code falls back to manual entry).
  return null;
}
