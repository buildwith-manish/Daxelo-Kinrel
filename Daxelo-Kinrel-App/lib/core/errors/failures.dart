/// Base failure class for clean architecture error handling
abstract class Failure {
  Failure({required this.message, this.code, this.originalError});

  final String message;
  final int? code;
  final dynamic originalError;
}

class ServerFailure extends Failure {
  ServerFailure({required super.message, super.code, super.originalError});
}

class NetworkFailure extends Failure {
  NetworkFailure({required super.message, super.originalError});
}

class AuthFailure extends Failure {
  AuthFailure({required super.message, super.code, super.originalError});
}

class CacheFailure extends Failure {
  CacheFailure({required super.message, super.originalError});
}

class ValidationFailure extends Failure {
  ValidationFailure({required super.message, super.originalError});
}

class NotFoundFailure extends Failure {
  NotFoundFailure({required super.message, super.originalError});
}

class PermissionFailure extends Failure {
  PermissionFailure({required super.message, super.originalError});
}

class KinshipFailure extends Failure {
  KinshipFailure({required super.message, super.originalError});
}
