/// A sealed class representing the result of an API call.
///
/// Either [ApiSuccess] with data of type [T], or [ApiError] with a [Failure].
import 'failures.dart';

sealed class ApiResult<T> {}

/// A successful API result containing data of type [T].
class ApiSuccess<T> extends ApiResult<T> {
  ApiSuccess(this.data);

  final T data;
}

/// An error API result containing a [Failure].
class ApiError<T> extends ApiResult<T> {
  ApiError(this.failure);

  final Failure failure;
}
