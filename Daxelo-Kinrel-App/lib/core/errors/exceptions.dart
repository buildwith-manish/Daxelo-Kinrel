/// Custom exceptions for the application
class AppException implements Exception {
  final String message;
  final int? statusCode;
  final dynamic originalError;

  const AppException({required this.message, this.statusCode, this.originalError});

  @override
  String toString() => 'AppException: $message';
}

class ServerException extends AppException {
  const ServerException({required super.message, super.statusCode, super.originalError});
}

class NetworkException extends AppException {
  const NetworkException({required super.message, super.originalError});
}

class AuthException extends AppException {
  const AuthException({required super.message, super.statusCode, super.originalError});
}

class CacheException extends AppException {
  const CacheException({required super.message, super.originalError});
}

class ValidationException extends AppException {
  const ValidationException({required super.message, super.originalError});
}

class KinshipParseException extends AppException {
  const KinshipParseException({required super.message, super.originalError});
}
