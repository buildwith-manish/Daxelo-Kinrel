// lib/core/utils/api_error_mapper.dart
//
// DAXELO KINREL — API Error Mapper Utility
//
// Maps NestJS backend error responses to field-specific error messages.
// Returns Map<String, String>? where:
//   - key   = field name (e.g., 'email', 'username', 'password')
//   - value = user-friendly error message
//   - null  = no mappable errors found
//
// Handles:
//   - HTTP 409 Conflict (email/username already exists)
//   - HTTP 422 Unprocessable Entity (NestJS validation errors)
//   - Network errors (SocketException, timeouts, etc.)
//   - Supabase auth errors (forwarded as-is)

import 'package:dio/dio.dart';

/// Maps a caught error from an API call to field-specific error messages.
///
/// [error] — the caught error (typically a DioException or Exception)
///
/// Returns a map of field names to error messages, or null if the error
/// cannot be mapped to specific fields.
Map<String, String>? mapApiError(dynamic error) {
  if (error is DioException) {
    return _mapDioError(error);
  }

  // Handle non-Dio exceptions (e.g., Supabase AuthException)
  final errorString = error.toString();

  // Supabase auth: user already registered
  if (errorString.contains('User already registered')) {
    return {'email': 'This email is already registered. Try signing in instead.'};
  }

  // Supabase auth: invalid credentials
  if (errorString.contains('Invalid login credentials')) {
    return {'email': 'Incorrect email or password. Please try again.'};
  }

  // Supabase auth: email not confirmed
  if (errorString.contains('Email not confirmed')) {
    return {'email': 'Please verify your email before signing in.'};
  }

  // Supabase auth: password too weak
  if (errorString.contains('Password should be')) {
    return {'password': 'Password is too weak. Use at least 8 characters with numbers and symbols.'};
  }

  // Network errors → generic form error
  if (_isNetworkError(errorString)) {
    return {'form': 'Could not reach server. Please check your internet connection and try again.'};
  }

  return null;
}

/// Maps a DioException to field-specific errors.
Map<String, String>? _mapDioError(DioException error) {
  final response = error.response;

  // No response → network error
  if (response == null) {
    if (_isNetworkError(error.toString())) {
      return {'form': 'Could not reach server. Please check your internet connection and try again.'};
    }
    return {'form': 'Connection failed. Please try again.'};
  }

  final statusCode = response.statusCode;
  final data = response.data;

  switch (statusCode) {
    case 409:
      return _mapConflictError(data);

    case 422:
      return _mapValidationError(data);

    case 401:
      return {'form': 'Session expired. Please sign in again.'};

    case 403:
      return {'form': 'You don\'t have permission to perform this action.'};

    case 404:
      return {'form': 'The requested resource was not found.'};

    case 429:
      return {'form': 'Too many requests. Please wait a moment and try again.'};

    case 500:
    case 502:
    case 503:
    case 504:
      return {'form': 'Server error. Please try again later.'};

    default:
      return {'form': 'Something went wrong. Please try again.'};
  }
}

/// Maps HTTP 409 Conflict responses to field errors.
///
/// NestJS typically returns:
/// ```json
/// { "message": "email already exists" }
/// { "message": "Username already taken" }
/// { "statusCode": 409, "error": "Conflict", "message": "..." }
/// ```
Map<String, String>? _mapConflictError(dynamic data) {
  if (data is! Map<String, dynamic>) {
    return {'form': 'A conflict occurred. Please check your input.'};
  }

  final message = _extractMessage(data).toLowerCase();

  if (message.contains('email') && message.contains('exist')) {
    return {'email': 'This email is already registered. Try signing in instead.'};
  }
  if (message.contains('email') && message.contains('already')) {
    return {'email': 'This email is already registered. Try signing in instead.'};
  }
  if (message.contains('username') && (message.contains('taken') || message.contains('exist'))) {
    return {'username': 'This username is already taken. Please choose another.'};
  }
  if (message.contains('username') && message.contains('already')) {
    return {'username': 'This username is already taken. Please choose another.'};
  }
  if (message.contains('family') && message.contains('name')) {
    return {'name': 'A family with this name already exists.'};
  }

  // Generic conflict
  return {'form': _extractMessage(data)};
}

/// Maps HTTP 422 Unprocessable Entity responses to field errors.
///
/// NestJS class-validator typically returns:
/// ```json
/// {
///   "statusCode": 422,
///   "message": [
///     "email must be an email",
///     "password must be longer than or equal to 8 characters"
///   ],
///   "error": "Unprocessable Entity"
/// }
/// ```
///
/// Or with nested property paths:
/// ```json
/// {
///   "message": [
///     { "property": "email", "constraints": { "isEmail": "email must be an email" } },
///     { "property": "password", "constraints": { "minLength": "..." } }
///   ]
/// }
/// ```
Map<String, String>? _mapValidationError(dynamic data) {
  if (data is! Map<String, dynamic>) {
    return {'form': 'Validation failed. Please check your input.'};
  }

  final messages = data['message'];
  final Map<String, String> fieldErrors = {};

  if (messages is List) {
    for (final msg in messages) {
      if (msg is Map<String, dynamic>) {
        // Object-style validation error with property name
        final property = msg['property'] as String?;
        final constraints = msg['constraints'] as Map<String, dynamic>?;
        if (property != null && constraints != null) {
          // Take the first constraint message
          final errorMsg = constraints.values.firstOrNull?.toString() ??
              'Invalid $property';
          fieldErrors[_normalizeFieldName(property)] = _cleanValidationMessage(errorMsg, property);
        }
      } else if (msg is String) {
        // String-style validation error — parse the field name from message
        final mapped = _parseStringValidationMessage(msg);
        fieldErrors.addAll(mapped);
      }
    }
  } else if (messages is String) {
    final mapped = _parseStringValidationMessage(messages);
    fieldErrors.addAll(mapped);
  }

  if (fieldErrors.isEmpty) {
    return {'form': 'Validation failed. Please check your input.'};
  }

  return fieldErrors;
}

/// Normalizes a backend field name to match the form's field key.
///
/// Backend might send: "email", "password", "familyName", "dateOfBirth"
/// Frontend expects:  "email", "password", "name",        "dateOfBirth"
String _normalizeFieldName(String property) {
  final lower = property.toLowerCase();
  switch (lower) {
    case 'familyname':
    case 'family_name':
      return 'name';
    case 'displayname':
    case 'display_name':
      return 'name';
    case 'fullname':
    case 'full_name':
      return 'name';
    case 'phonenumber':
    case 'phone_number':
      return 'phone';
    case 'dateofbirth':
    case 'date_of_birth':
      return 'dateOfBirth';
    case 'confirmpassword':
    case 'confirm_password':
      return 'confirmPassword';
    case 'currentpassword':
    case 'current_password':
      return 'currentPassword';
    case 'newpassword':
    case 'new_password':
      return 'newPassword';
    default:
      return property;
  }
}

/// Cleans up auto-generated validation messages from class-validator
/// to be more user-friendly.
String _cleanValidationMessage(String message, String property) {
  // class-validator often generates messages like:
  // "email must be an email" → "Please enter a valid email address"
  // "password must be longer than or equal to 8 characters" → keep as-is

  final lower = message.toLowerCase();

  if (lower.contains('must be an email')) {
    return 'Please enter a valid email address';
  }
  if (lower.contains('must be longer than or equal to')) {
    final match = RegExp(r'(\d+)').firstMatch(message);
    final length = match?.group(1) ?? '8';
    return '${_fieldTitle(property)} must be at least $length characters';
  }
  if (lower.contains('must be shorter than or equal to')) {
    final match = RegExp(r'(\d+)').firstMatch(message);
    final length = match?.group(1) ?? '50';
    return '${_fieldTitle(property)} must be $length characters or less';
  }
  if (lower.contains('should not be empty') || lower.contains('must not be empty')) {
    return '${_fieldTitle(property)} is required';
  }
  if (lower.contains('must be a string')) {
    return '${_fieldTitle(property)} must be text';
  }
  if (lower.contains('must be a number')) {
    return '${_fieldTitle(property)} must be a number';
  }
  if (lower.contains('must be a valid date')) {
    return 'Please enter a valid date';
  }

  return message;
}

/// Parses a string-style validation message to extract the field name.
///
/// Examples:
///   "email must be an email" → {"email": "Please enter a valid email address"}
///   "password must be longer than or equal to 8 characters" → {"password": "..."}
Map<String, String> _parseStringValidationMessage(String message) {
  final lower = message.toLowerCase();

  // Try to match common field names at the start of the message
  if (lower.startsWith('email')) {
    return {'email': _cleanValidationMessage(message, 'email')};
  }
  if (lower.startsWith('password')) {
    return {'password': _cleanValidationMessage(message, 'password')};
  }
  if (lower.startsWith('username')) {
    return {'username': _cleanValidationMessage(message, 'username')};
  }
  if (lower.startsWith('name') || lower.startsWith('family name')) {
    return {'name': _cleanValidationMessage(message, 'name')};
  }
  if (lower.startsWith('phone')) {
    return {'phone': _cleanValidationMessage(message, 'phone')};
  }
  if (lower.startsWith('date of birth') || lower.startsWith('dateofbirth')) {
    return {'dateOfBirth': _cleanValidationMessage(message, 'dateOfBirth')};
  }
  if (lower.startsWith('confirm password')) {
    return {'confirmPassword': _cleanValidationMessage(message, 'confirmPassword')};
  }
  if (lower.startsWith('current password')) {
    return {'currentPassword': _cleanValidationMessage(message, 'currentPassword')};
  }

  // If we can't determine the field, return as generic form error
  return {'form': message};
}

/// Extracts the message string from a NestJS error response.
String _extractMessage(Map<String, dynamic> data) {
  final message = data['message'];
  if (message is String) return message;
  if (message is List && message.isNotEmpty) return message.first.toString();
  if (data['error'] is String) return data['error'] as String;
  return 'An error occurred';
}

/// Converts a field property name to a title-case label.
String _fieldTitle(String property) {
  // camelCase → Space separated → Title Case
  final spaced = property.replaceAll(RegExp(r'([A-Z])'), r' $1').trim();
  return spaced.split(' ').map((word) {
    if (word.isEmpty) return word;
    return word[0].toUpperCase() + word.substring(1).toLowerCase();
  }).join(' ');
}

/// Checks if an error string indicates a network connectivity problem.
bool _isNetworkError(String errorString) {
  return errorString.contains('SocketException') ||
      errorString.contains('Failed host lookup') ||
      errorString.contains('Connection refused') ||
      errorString.contains('Network is unreachable') ||
      errorString.contains('No address associated with hostname') ||
      errorString.contains('Connection timed out') ||
      errorString.contains('TimeoutException') ||
      errorString.contains('timed out') ||
      errorString.contains('Unable to connect') ||
      errorString.contains('FetchException') ||
      errorString.contains('Connection reset') ||
      errorString.contains('No internet connection');
}
