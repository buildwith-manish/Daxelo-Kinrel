// lib/features/family/presentation/contact_picker_helper_io.dart
//
// Native (Android/iOS) implementation of contact_picker_helper.
// Uses the flutter_contacts package to open the contact picker.
//
// Used via conditional import when dart.library.io IS available
// (i.e. on native builds, NOT web).

import 'package:flutter_contacts/flutter_contacts.dart';

import 'picked_contact.dart';

/// Native implementation — opens the system contact picker via
/// flutter_contacts and returns the selected contact's name, phone,
/// and email.
Future<PickedContact?> pickContactImpl() async {
  // Open the system contact picker. This shows the native contact
  // list and lets the user select one contact.
  final contact = await FlutterContacts.openExternalPick();
  if (contact == null) {
    return null; // user cancelled
  }

  // Extract name, phone, email from the selected contact.
  // The contact returned by openExternalPick may not have full
  // properties — fetch them if needed.
  Contact fullContact = contact;
  if (contact.phones.isEmpty && contact.emails.isEmpty) {
    try {
      fullContact = await FlutterContacts.getContact(contact.id,
          withProperties: true, withPhoto: false);
    } catch (_) {
      // Fall back to the partial contact
    }
  }

  final name = fullContact.displayName.isNotEmpty
      ? fullContact.displayName
      : null;

  String? phone;
  if (fullContact.phones.isNotEmpty) {
    phone = fullContact.phones.first.number;
  }

  String? email;
  if (fullContact.emails.isNotEmpty) {
    email = fullContact.emails.first.address;
  }

  return PickedContact(name: name, phone: phone, email: email);
}
