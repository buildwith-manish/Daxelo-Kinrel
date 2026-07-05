// lib/features/family/presentation/picked_contact.dart
//
// DAXELO KINREL — PickedContact data class
//
// Extracted into its own file to avoid circular imports between
// contact_picker_helper.dart and its platform-specific implementations
// (contact_picker_helper_stub.dart + contact_picker_helper_io.dart).

/// A simple data class holding the picked contact's details.
class PickedContact {
  final String? name;
  final String? phone;
  final String? email;
  const PickedContact({this.name, this.phone, this.email});
}
