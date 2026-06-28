// lib/features/family/presentation/contact_picker_helper.dart
//
// DAXELO KINREL — Contact Picker Helper (conditional import)
//
// flutter_contacts doesn't support web, so we use a conditional import
// to provide a no-op stub on web platforms. On native (Android/iOS),
// the real implementation opens the contact picker.
//
// Usage:
//   final contact = await ContactPickerHelper.pickContact();
//   if (contact != null) {
//     // contact.name, contact.phone, contact.email
//   }

import 'contact_picker_helper_stub.dart'
    if (dart.library.io) 'contact_picker_helper_io.dart';

/// A simple data class holding the picked contact's details.
class PickedContact {
  final String? name;
  final String? phone;
  final String? email;
  const PickedContact({this.name, this.phone, this.email});
}

/// Opens the native contact picker and returns the selected contact.
/// Returns null if the user cancelled or the platform doesn't support
/// contact picking (e.g. web).
Future<PickedContact?> pickContact() => _pickContactImpl();
