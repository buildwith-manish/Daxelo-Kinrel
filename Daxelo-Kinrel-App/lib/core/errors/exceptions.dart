/// Typed exception classes for the Kinrel application.
///
/// These provide structured error handling with optional error codes,
/// status codes, and field-level validation errors.

/// Base exception class for all Kinrel application errors.
///
/// Provides a consistent interface with [message], optional [code] for
/// programmatic error identification, and optional [statusCode] for
/// HTTP-related errors.
class KinrelException implements Exception {
  final String message;
  final String? code;
  final int? statusCode;

  const KinrelException(this.message, {this.code, this.statusCode});

  @override
  String toString() => 'KinrelException($code): $message';
}

/// Exception thrown when a network request fails.
///
/// This covers connectivity issues, timeouts, DNS failures,
/// and other transport-layer errors.
class NetworkException extends KinrelException {
  const NetworkException(super.message, {super.code, super.statusCode});
}

/// Exception thrown when authentication or authorization fails.
///
/// Covers invalid credentials, expired tokens, insufficient permissions,
/// and other auth-related failures.
class AuthException extends KinrelException {
  const AuthException(super.message, {super.code});
}

/// Exception thrown when input validation fails.
///
/// Includes [fieldErrors] map for per-field error messages,
/// making it easy to display inline validation feedback.
class ValidationException extends KinrelException {
  final Map<String, String> fieldErrors;

  const ValidationException(super.message, {required this.fieldErrors});

  @override
  String toString() =>
      'ValidationException: $message (${fieldErrors.length} field errors)';
}

/// Exception thrown when a sync operation fails.
///
/// Covers conflicts, sync version mismatches, and offline
/// queue processing failures.
class SyncException extends KinrelException {
  const SyncException(super.message, {super.code});
}

/// Exception thrown when a local cache operation fails.
///
/// Covers cache misses, corruption, and storage errors.
class CacheException extends KinrelException {
  const CacheException(super.message);
}
