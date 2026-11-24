import 'dart:async';
import 'dart:io';

import 'package:pocketbase/pocketbase.dart';

import '../../core/errors.dart';

/// Maps network and PocketBase exceptions to Tickwalk's typed AppError taxonomy.
AppError mapClientError(Object error, [StackTrace? _]) {
  if (error is ClientException) {
    final status = error.statusCode;
    final serverMsg = error.response['message'] as String?;
    final message = serverMsg != null && serverMsg.isNotEmpty
        ? serverMsg
        : (error.originalError?.toString() ?? 'API error ($status)');

    final klass = switch (status) {
      401 => ErrorClass.auth,
      403 => ErrorClass.forbidden,
      404 => ErrorClass.notFound,
      409 => ErrorClass.conflict,
      413 => ErrorClass.tooLarge,
      400 || 422 => ErrorClass.validation,
      429 => ErrorClass.transient,
      >= 500 && < 600 => ErrorClass.transient,
      _ => ErrorClass.unknown,
    };

    return AppError(
      klass: klass,
      message: message,
      cause: error,
    );
  }

  if (error is SocketException) {
    return AppError(
      klass: ErrorClass.network,
      message: 'No internet connection',
      cause: error,
    );
  }

  if (error is TimeoutException) {
    return AppError(
      klass: ErrorClass.network,
      message: 'Connection timed out',
      cause: error,
    );
  }

  return AppError(
    klass: ErrorClass.unknown,
    message: error.toString(),
    cause: error,
  );
}
