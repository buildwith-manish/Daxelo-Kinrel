// lib/features/family/presentation/contact_picker_helper_io.dart
//
// Native (Android/iOS) implementation of contact_picker_helper.
// Uses the flutter_contacts package to open the contact picker.
//
// Used via conditional import when dart.library.io IS available
// (i.e. on native builds, NOT web).

import 'package:flutter_contacts/flutter_contacts.dart';

import 'contact_picker_helper.dart';

Future<PickedContact?> _pickContactImpl() async {
  // Open the native contact picker. This shows the system contact
  // list and lets the user select one contact.
  final contact = await FlutterContacts.openContactPicker();
  if (contact == null) {
    return null; // user cancelled
  }

  // Extract name, phone, email from the selected contact.
  final name = contact.displayName.isNotEmpty ? contact.displayName : null;

  String? phone;
  if (contact.phones.isNotEmpty) {
    phone = contact.phones.first.number;
  }

  String? email;
  if (contact.emails.isNotEmpty) {
    email = contact.emails.first.address;
  }

  return PickedContact(name: name, phone: phone, email: email);
}
