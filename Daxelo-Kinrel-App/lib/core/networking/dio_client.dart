import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/app_config.dart';
import '../config/env_config.dart';
import '../services/crashlytics_service.dart';
import '../services/supabase_service.dart';
import '../widgets/offline_banner.dart';

/// Configured Dio HTTP client with network resilience:
///   1. ConnectivityInterceptor  — instant offline detection
///   2. RetryInterceptor         — exponential backoff on transient failures
///   3. _AuthInterceptor         — Supabase JWT injection
///   4. _LoggingInterceptor      — debug request/response logging
///   5. _ErrorInterceptor        — error transformation
///   6. _ErrorLoggingInterceptor — Crashlytics error reporting (P3-F1)
final dioProvider = Provider<Dio>((ref) {
  final dio = Dio(
    BaseOptions(
      baseUrl: EnvConfig.apiBaseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 30),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'apikey': AppConfig.supabaseAnonKey,
      },
    ),
  );

  dio.interceptors.addAll([
    ConnectivityInterceptor(ref: ref),
    RetryInterceptor(dio),
    _AuthInterceptor(ref),
    _LoggingInterceptor(),
    _ErrorInterceptor(),
    _ErrorLoggingInterceptor(), // P3-F1: Crashlytics error logging (last in chain)
  ]);

  return dio;
});

// ---------------------------------------------------------------------------
// ConnectivityInterceptor — fails fast when the device is offline
// ---------------------------------------------------------------------------

/// Checks [Connectivity] before every request. If no connection is available,
/// throws a [DioException] with [DioExceptionType.connectionError] immediately
/// instead of waiting for the connect timeout (8 s).
class ConnectivityInterceptor extends Interceptor {
  ConnectivityInterceptor({Connectivity? connectivity, Ref? ref})
      : _connectivity = connectivity ?? Connectivity(),
        _ref = ref;

  final Connectivity _connectivity;
  final Ref? _ref;

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    try {
      final result = await _connectivity.checkConnectivity();
      final hasConnection = result.any(
        (c) => c != ConnectivityResult.none,
      );

      if (!hasConnection) {
        // Record the failure timestamp so the OfflineBanner can show
        _ref?.read(recentRequestFailureProvider.notifier).state =
            DateTime.now();

        handler.reject(
          DioException(
            requestOptions: options,
            error: const SocketException('No internet connection'),
            type: DioExceptionType.connectionError,
            message: 'No internet connection — please check your network',
          ),
        );
        return;
      }
    } catch (_) {
      // If connectivity check itself fails, let the request proceed.
      // The retry interceptor will handle any subsequent failure.
    }
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    // Record connection-type errors so the OfflineBanner can react
    // to failures that occur after the request was sent (e.g. DNS
    // failure, server unreachable, timeout).
    if (err.type == DioExceptionType.connectionError ||
        err.error is SocketException) {
      _ref?.read(recentRequestFailureProvider.notifier).state =
          DateTime.now();
    }
    handler.next(err);
  }
}

// ---------------------------------------------------------------------------
// RetryInterceptor — exponential backoff on transient errors
// ---------------------------------------------------------------------------

/// Retries failed requests up to 3 times with delays of 1 s, 2 s, 4 s.
///
/// Retries on:
///   - [SocketException]
///   - [TimeoutException]
///   - [HttpException]
///   - HTTP 500, 502, 503, 504
///
/// Never retries:
///   - HTTP 400, 401, 403, 404, 422
///   - Any other non-retryable DioException
class RetryInterceptor extends Interceptor {
  RetryInterceptor(this._dio, {int maxRetries = 3})
      : _maxRetries = maxRetries,
        _delays = const [
          Duration(seconds: 1),
          Duration(seconds: 2),
          Duration(seconds: 4),
        ];

  final Dio _dio;
  final int _maxRetries;
  final List<Duration> _delays;

  /// HTTP status codes that are considered retryable (server errors).
  static const _retryableStatusCodes = {500, 502, 503, 504};

  /// HTTP status codes that must never be retried (client errors).
  static const _nonRetryableStatusCodes = {400, 401, 403, 404, 422};

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final retryCount = (err.requestOptions.extra['retryCount'] as int?) ?? 0;

    if (!_isRetryable(err) || retryCount >= _maxRetries) {
      handler.next(err);
      return;
    }

    // Calculate backoff delay
    final delay = _delays[retryCount.clamp(0, _delays.length - 1)];

    // Wait before retrying
    await Future<void>.delayed(delay);

    // Increment retry count on the request options
    final newOptions = err.requestOptions.copyWith(
      extra: {
        ...err.requestOptions.extra,
        'retryCount': retryCount + 1,
      },
    );

    try {
      final response = await _dio.fetch(newOptions);
      handler.resolve(response);
    } on DioException catch (e) {
      // Propagate the new error through the interceptor chain
      handler.next(e);
    }
  }

  /// Determines whether a [DioException] is retryable based on its cause
  /// or HTTP status code.
  bool _isRetryable(DioException err) {
    // Never retry explicitly non-retryable status codes
    final statusCode = err.response?.statusCode;
    if (statusCode != null && _nonRetryableStatusCodes.contains(statusCode)) {
      return false;
    }

    // Retry on specific status codes (500, 502, 503, 504)
    if (statusCode != null && _retryableStatusCodes.contains(statusCode)) {
      return true;
    }

    // Retry on specific exception types from the underlying error
    final error = err.error;
    if (error is SocketException) return true;
    if (error is TimeoutException) return true;
    if (error is HttpException) return true;

    // Retry on Dio timeout types
    if (err.type == DioExceptionType.connectionTimeout) return true;
    if (err.type == DioExceptionType.sendTimeout) return true;
    if (err.type == DioExceptionType.receiveTimeout) return true;

    // Retry on connection error (e.g. from ConnectivityInterceptor)
    if (err.type == DioExceptionType.connectionError) return true;

    return false;
  }
}

// ---------------------------------------------------------------------------
// _AuthInterceptor — injects Supabase JWT into requests
// ---------------------------------------------------------------------------

class _AuthInterceptor extends Interceptor {
  _AuthInterceptor(this._ref);

  final Ref _ref;

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    // Add auth token from Supabase session if available
    try {
      final client = _ref.read(supabaseProvider);
      if (client != null) {
        final session = client.auth.currentSession;
        if (session != null && !session.isExpired) {
          options.headers['Authorization'] = 'Bearer ${session.accessToken}';
        }
      }
    } catch (_) {
      // Ignore — request will proceed without auth token
    }
    handler.next(options);
  }
}

// ---------------------------------------------------------------------------
// _LoggingInterceptor — debug-only request/response logging
// ---------------------------------------------------------------------------

class _LoggingInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    // Only log in debug mode
    assert(() {
      // ignore: avoid_print
      print('→ ${options.method} ${options.uri}');
      return true;
    }());
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    assert(() {
      // ignore: avoid_print
      print('← ${response.statusCode} ${response.requestOptions.uri}');
      return true;
    }());
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    assert(() {
      // ignore: avoid_print
      print(
        '✗ ${err.response?.statusCode} ${err.requestOptions.uri}: ${err.message}',
      );
      return true;
    }());
    handler.next(err);
  }
}

// ---------------------------------------------------------------------------
// _ErrorInterceptor — transforms Dio errors to app exceptions
// ---------------------------------------------------------------------------

class _ErrorInterceptor extends Interceptor {
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    // Transform Dio errors to app exceptions
    handler.next(err);
  }
}

// ---------------------------------------------------------------------------
// _ErrorLoggingInterceptor — logs network errors to Crashlytics (P3-F1)
// ---------------------------------------------------------------------------

/// Reports network errors to Firebase Crashlytics as non-fatal errors.
///
/// Placed LAST in the interceptor chain so it sees the final error state
/// after retries and transformations. Only logs metadata (method, path,
/// statusCode, errorType) — NEVER logs request/response bodies (may contain PII).
///
/// Skips logging for expected/normal status codes:
///   - All 4xx client errors: expected responses that the app handles gracefully
///     (401 = expired token, 404 = missing endpoint, 403 = no permissions, etc.)
class _ErrorLoggingInterceptor extends Interceptor {
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final statusCode = err.response?.statusCode;

    // Skip logging for ALL 4xx client errors — these are expected responses
    // that the app handles gracefully (fallback to Supabase data, etc.)
    // Only 5xx server errors and network-level failures are logged.
    if (statusCode != null && statusCode >= 400 && statusCode < 500) {
      handler.next(err);
      return;
    }

    final method = err.requestOptions.method;
    final path = err.requestOptions.path;
    final errorType = err.type.name;

    logError(
      'NetworkError: $method $path',
      err.stackTrace,
      reason: 'method=$method, path=$path, '
          'statusCode=$statusCode, errorType=$errorType',
    );

    handler.next(err);
  }
}
