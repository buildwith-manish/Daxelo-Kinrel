import '../errors/failures.dart';

/// Sealed result type for API calls
sealed class ApiResult<T> {
  const ApiResult();
}

class ApiSuccess<T> extends ApiResult<T> {
  final T data;
  const ApiSuccess(this.data);
}

class ApiError<T> extends ApiResult<T> {
  final Failure failure;
  const ApiError(this.failure);
}
