// Custom exception types for the FastAPI Service layer.
// Allows for granular error handling and user feedback.

class ApiResponseException implements Exception {
  final String message;
  final int? statusCode;

  ApiResponseException(this.message, {this.statusCode});

  @override
  String toString() => 'ApiResponseException: $message (Status: $statusCode)';
}

class NetworkException extends ApiResponseException {
  NetworkException(super.message);
}

class AuthException extends ApiResponseException {
  AuthException(super.message, {super.statusCode});
}

class ServerException extends ApiResponseException {
  ServerException(super.message, {super.statusCode});
}

class ValidationException extends ApiResponseException {
  ValidationException(super.message, {super.statusCode});
}

/// A generic class to hold either a success [data] or a failure [exception].
/// Inspired by the Result pattern in Swift/Kotlin.
class ApiResult<T> {
  final T? data;
  final Exception? exception;

  ApiResult.success(this.data) : exception = null;
  ApiResult.failure(this.exception) : data = null;

  bool get isSuccess => exception == null;
  bool get isFailure => exception != null;

  void fold({
    required void Function(T data) onSuccess,
    required void Function(Exception exception) onFailure,
  }) {
    if (isSuccess) {
      onSuccess(data as T);
    } else {
      onFailure(exception!);
    }
  }
}
