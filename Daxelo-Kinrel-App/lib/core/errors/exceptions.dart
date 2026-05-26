/// Custom exceptions for the application
class AppException implements Exception {
  AppException({required this.message, this.statusCode, this.originalError});

  final String message;
  final int? statusCode;
  final dynamic originalError;


  @override
  String toString() => 'AppException: $message';
}

class ServerException extends AppException {
  ServerException({required super.message, super.statusCode, super.originalError});
}

class NetworkException extends AppException {
  NetworkException({required super.message, super.originalError});
}

class AuthException extends AppException {
  AuthException({required super.message, super.statusCode, super.originalError});
}

class CacheException extends AppException {
  CacheException({required super.message, super.originalError});
}

class ValidationException extends AppException {
  ValidationException({required super.message, super.originalError});
}

class KinshipParseException extends AppException {
  KinshipParseException({required super.message, super.originalError});
}
