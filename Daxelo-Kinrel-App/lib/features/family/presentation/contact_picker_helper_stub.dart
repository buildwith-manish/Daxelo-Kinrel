// lib/features/family/presentation/contact_picker_helper_stub.dart
//
// Web stub for contact_picker_helper — returns null (no contact picking
// on web). Used via conditional import when dart.library.io is not
// available (i.e. on web builds).

import 'picked_contact.dart';

/// Web implementation — always returns null because contacts are not
/// available on web platforms. The calling code falls back to manual
/// entry when this returns null.
Future<PickedContact?> pickContactImpl() async {
  return null;
}
