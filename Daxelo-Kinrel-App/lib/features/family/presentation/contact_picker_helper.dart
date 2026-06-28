// lib/features/family/presentation/contact_picker_helper.dart
//
// DAXELO KINREL — Contact Picker Helper (conditional import)
//
// flutter_contacts doesn't support web, so we use a conditional import
// to provide a no-op stub on web platforms. On native (Android/iOS),
// the real implementation opens the contact picker.
//
// Usage:
//   final contact = await pickContact();
//   if (contact != null) {
//     // contact.name, contact.phone, contact.email
//   }

import 'picked_contact.dart';
import 'contact_picker_helper_stub.dart'
    if (dart.library.io) 'contact_picker_helper_io.dart';

// Re-export PickedContact so callers only need to import this one file.
export 'picked_contact.dart';

/// Opens the native contact picker and returns the selected contact.
/// Returns null if the user cancelled or the platform doesn't support
/// contact picking (e.g. web).
///
/// Delegates to [pickContactImpl] which is defined in the
/// platform-specific file (stub on web, io on native).
Future<PickedContact?> pickContact() => pickContactImpl();
