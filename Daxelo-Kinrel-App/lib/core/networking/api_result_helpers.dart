/// Helper methods for working with [ApiResult]<T>.
///
/// The [ApiResult]<T> sealed class is defined in `api_result.dart` but
/// currently unused throughout the codebase. These extensions make it
/// easy to adopt the pattern by providing ergonomic `when`-style
/// destructuring and utility methods.

import '../errors/api_result.dart';
import '../errors/failures.dart';

/// Extension methods on [ApiResult]<T> for ergonomic result handling.
///
/// Usage:
/// ```dart
/// final result = await someApiCall();
/// result.when(
///   success: (data) => print('Got: $data'),
///   error: (message, code) => print('Error: $message'),
/// );
/// ```
extension ApiResultExtensions<T> on ApiResult<T> {
  /// Destructure the result into success and error cases.
  ///
  /// This is the primary way to handle [ApiResult] values. Both callbacks
  /// are required, ensuring all cases are handled.
  ///
  /// - [success] called with the data when the result is [ApiSuccess].
  /// - [error] called with the error message and optional status code
  ///   when the result is [ApiError].
  R when<R>({
    required R Function(T data) success,
    required R Function(String message, int? code) error,
  }) {
    if (this is ApiSuccess<T>) {
      return success((this as ApiSuccess<T>).data);
    } else if (this is ApiError<T>) {
      final failure = (this as ApiError<T>).failure;
      return error(failure.message, failure.code);
    }
    throw StateError('Unknown ApiResult type: $runtimeType');
  }

  /// Destructure the result with an optional success case.
  ///
  /// Like [when], but [success] is not required. If the result is
  /// successful and no [success] callback is provided, returns null.
  R? maybeWhen<R>({
    R Function(T data)? success,
    R Function(String message, int? code)? error,
  }) {
    if (this is ApiSuccess<T>) {
      return success?.call((this as ApiSuccess<T>).data);
    } else if (this is ApiError<T>) {
      final failure = (this as ApiError<T>).failure;
      return error?.call(failure.message, failure.code);
    }
    return null;
  }

  /// Returns `true` if this is a successful result.
  bool get isSuccess => this is ApiSuccess<T>;

  /// Returns `true` if this is an error result.
  bool get isError => this is ApiError<T>;

  /// Returns the data if successful, or `null` otherwise.
  T? get dataOrNull {
    if (this is ApiSuccess<T>) {
      return (this as ApiSuccess<T>).data;
    }
    return null;
  }

  /// Returns the failure if error, or `null` otherwise.
  Failure? get failureOrNull {
    if (this is ApiError<T>) {
      return (this as ApiError<T>).failure;
    }
    return null;
  }

  /// Returns the error message if error, or `null` otherwise.
  String? get errorMessageOrNull {
    if (this is ApiError<T>) {
      return (this as ApiError<T>).failure.message;
    }
    return null;
  }

  /// Transform the success data using [mapper], preserving error state.
  ///
  /// If this is an error, returns the same error without calling [mapper].
  /// If this is a success, returns a new [ApiSuccess] with the mapped data.
  ApiResult<R> map<R>(R Function(T data) mapper) {
    if (this is ApiSuccess<T>) {
      return ApiSuccess(mapper((this as ApiSuccess<T>).data));
    } else {
      return ApiError((this as ApiError<T>).failure);
    }
  }

  /// Execute [onSuccess] on success or [onError] on error.
  ///
  /// Useful for side effects like logging, showing toasts, etc.
  void fold({
    required void Function(T data) onSuccess,
    required void Function(String message, int? code) onError,
  }) {
    when(
      success: onSuccess,
      error: onError,
    );
  }
}
