/// Base failure class for clean architecture error handling
abstract class Failure {
  final String message;
  final int? code;
  final dynamic originalError;

  const Failure({required this.message, this.code, this.originalError});
}

class ServerFailure extends Failure {
  const ServerFailure({required super.message, super.code, super.originalError});
}

class NetworkFailure extends Failure {
  const NetworkFailure({required super.message, super.originalError});
}

class AuthFailure extends Failure {
  const AuthFailure({required super.message, super.code, super.originalError});
}

class CacheFailure extends Failure {
  const CacheFailure({required super.message, super.originalError});
}

class ValidationFailure extends Failure {
  const ValidationFailure({required super.message, super.originalError});
}

class NotFoundFailure extends Failure {
  const NotFoundFailure({required super.message, super.originalError});
}

class PermissionFailure extends Failure {
  const PermissionFailure({required super.message, super.originalError});
}

class KinshipFailure extends Failure {
  const KinshipFailure({required super.message, super.originalError});
}
