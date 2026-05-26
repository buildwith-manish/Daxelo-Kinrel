import '../errors/failures.dart';

/// Sealed result type for API calls
sealed class ApiResult<T> {
  const ApiResult();
}

class ApiSuccess<T> extends ApiResult<T> {
  const ApiSuccess(this.data);

  final T data;
}

class ApiError<T> extends ApiResult<T> {
  const ApiError(this.failure);

  final Failure failure;
}
