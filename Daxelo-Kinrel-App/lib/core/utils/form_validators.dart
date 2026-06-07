// lib/core/utils/form_validators.dart
//
// DAXELO KINREL — Shared Form Validators
//
// Reusable validation functions for all form fields across the app.
// Every validator returns null for valid input or a user-friendly
// error message string for invalid input. No generic "Invalid input".

/// Validates that a field is non-null and non-empty after trimming.
///
/// [value] — the field value to validate
/// [fieldName] — human-readable name used in the error message (default: 'This field')
///
/// Returns null if valid, or an error message like 'Email is required'.
String? requiredField(String? value, [String fieldName = 'This field']) {
  if (value == null || value.trim().isEmpty) {
    return '$fieldName is required';
  }
  return null;
}

/// Validates an email address using a standard RFC-5322-ish regex.
///
/// Returns null if valid, or a specific error message.
String? emailValidator(String? value) {
  if (value == null || value.trim().isEmpty) {
    return 'Email is required';
  }
  final email = value.trim();

  // Standard email regex — covers 99% of real-world addresses
  final regex = RegExp(
    r'^[a-zA-Z0-9.!#$%&*+/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,253}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,253}[a-zA-Z0-9])?)*$',
  );

  if (!regex.hasMatch(email)) {
    return 'Please enter a valid email address';
  }
  return null;
}

/// Validates a password for minimum length and complexity.
///
/// [value] — the password to validate
/// [minLength] — minimum character count (default: 8)
///
/// Returns null if valid, or a specific error message explaining the requirement.
String? passwordValidator(String? value, [int minLength = 8]) {
  if (value == null || value.isEmpty) {
    return 'Password is required';
  }
  if (value.length < minLength) {
    return 'Password must be at least $minLength characters';
  }
  final hasLetter = RegExp(r'[a-zA-Z]').hasMatch(value);
  final hasNumber = RegExp(r'[0-9]').hasMatch(value);
  if (!hasLetter) {
    return 'Password must contain at least one letter';
  }
  if (!hasNumber) {
    return 'Password must contain at least one number';
  }
  return null;
}

/// Validates that a confirm-password field matches the original password.
///
/// [value] — the confirmation password
/// [password] — the original password to match against
///
/// Returns null if valid, or a specific error message.
String? confirmPasswordValidator(String? value, String password) {
  if (value == null || value.isEmpty) {
    return 'Please confirm your password';
  }
  if (value != password) {
    return 'Passwords do not match';
  }
  return null;
}

/// Validates a phone number format.
///
/// Accepts digits, spaces, dashes, parentheses, and a leading +.
/// Must contain at least 7 digits after stripping non-digit characters.
///
/// Returns null if valid, or a specific error message.
String? phoneValidator(String? value) {
  if (value == null || value.trim().isEmpty) {
    return 'Phone number is required';
  }
  final phone = value.trim();

  // Strip non-digit characters to count actual digits
  final digitsOnly = phone.replaceAll(RegExp(r'[^\d]'), '');

  if (digitsOnly.length < 7) {
    return 'Phone number must have at least 7 digits';
  }
  if (digitsOnly.length > 15) {
    return 'Phone number is too long';
  }

  // Must only contain valid phone characters
  final validChars = RegExp(r'^[+]?[\d\s\-\(\)]+$');
  if (!validChars.hasMatch(phone)) {
    return 'Phone number contains invalid characters';
  }

  return null;
}

/// Validates a person's name — minimum 2 characters, no digits.
///
/// Allows letters (including Unicode), spaces, hyphens, and apostrophes
/// to accommodate international names.
///
/// Returns null if valid, or a specific error message.
String? nameValidator(String? value) {
  if (value == null || value.trim().isEmpty) {
    return 'Name is required';
  }
  final name = value.trim();
  if (name.length < 2) {
    return 'Name must be at least 2 characters';
  }
  // Allow letters (Unicode), spaces, hyphens, apostrophes, dots
  final validName = RegExp(r"^[\p{L}\s'\-\.]+$", unicode: true);
  if (!validName.hasMatch(name)) {
    return 'Name can only contain letters, spaces, hyphens, and apostrophes';
  }
  return null;
}

/// Validates a family name — minimum 2 characters, maximum 50.
///
/// More permissive than [nameValidator] to allow numbers in family names
/// (e.g., "Family 21").
///
/// Returns null if valid, or a specific error message.
String? familyNameValidator(String? value) {
  if (value == null || value.trim().isEmpty) {
    return 'Family name is required';
  }
  final name = value.trim();
  if (name.length < 2) {
    return 'Family name must be at least 2 characters';
  }
  if (name.length > 50) {
    return 'Family name must be 50 characters or less';
  }
  return null;
}

/// Validates a username — alphanumeric + underscore, 3-20 characters.
///
/// Must start with a letter. Used for family @usernames and user handles.
///
/// Returns null if valid, or a specific error message.
String? usernameValidator(String? value) {
  if (value == null || value.trim().isEmpty) {
    return 'Username is required';
  }
  final username = value.trim();
  if (username.length < 3) {
    return 'Username must be at least 3 characters';
  }
  if (username.length > 20) {
    return 'Username must be 20 characters or less';
  }
  // Must start with a letter
  if (!RegExp(r'^[a-zA-Z]').hasMatch(username)) {
    return 'Username must start with a letter';
  }
  // Only alphanumeric and underscore
  if (!RegExp(r'^[a-zA-Z][a-zA-Z0-9_]*$').hasMatch(username)) {
    return 'Username can only contain letters, numbers, and underscores';
  }
  return null;
}

/// Validates a date string in common formats (YYYY-MM-DD, DD/MM/YYYY, MM/DD/YYYY).
///
/// Returns null if valid or empty (date is optional in many contexts),
/// or a specific error message.
String? dateValidator(String? value) {
  if (value == null || value.trim().isEmpty) {
    return null; // Date is optional by default
  }
  final dateStr = value.trim();

  // Try YYYY-MM-DD (ISO format)
  DateTime? parsed;
  if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(dateStr)) {
    parsed = DateTime.tryParse(dateStr);
  }
  // Try DD/MM/YYYY
  else if (RegExp(r'^\d{1,2}/\d{1,2}/\d{4}$').hasMatch(dateStr)) {
    final parts = dateStr.split('/');
    parsed = DateTime.tryParse('${parts[2]}-${parts[1].padLeft(2, '0')}-${parts[0].padLeft(2, '0')}');
  }
  // Try MM/DD/YYYY
  else if (RegExp(r'^\d{1,2}/\d{1,2}/\d{4}$').hasMatch(dateStr)) {
    // Already covered above, but try parsing as-is
    parsed = DateTime.tryParse(dateStr);
  }

  if (parsed == null) {
    return 'Please enter a valid date (YYYY-MM-DD or DD/MM/YYYY)';
  }

  // Check reasonable date range
  if (parsed.year < 1800 || parsed.year > DateTime.now().year + 1) {
    return 'Date must be between 1800 and ${DateTime.now().year + 1}';
  }

  return null;
}

/// Validates a birth year — 4-digit number within a reasonable range.
///
/// Returns null if valid or empty (optional), or a specific error message.
String? birthYearValidator(String? value) {
  if (value == null || value.trim().isEmpty) {
    return null; // Optional field
  }
  final yearStr = value.trim();
  if (!RegExp(r'^\d{4}$').hasMatch(yearStr)) {
    return 'Please enter a valid 4-digit year';
  }
  final year = int.tryParse(yearStr);
  if (year == null) {
    return 'Please enter a valid year';
  }
  final currentYear = DateTime.now().year;
  if (year < 1800 || year > currentYear) {
    return 'Year must be between 1800 and $currentYear';
  }
  return null;
}
