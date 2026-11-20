/// Error taxonomy defined in docs/architecture.md and cursorcontext.md
enum ErrorClass {
  network,
  transient,
  auth,
  forbidden,
  validation,
  tooLarge,
  conflict,
  notFound,
  fileMissing,
  storageFull,
  permission,
  local,
  unknown,
}

class AppError implements Exception {
  const AppError({
    required this.klass,
    required this.message,
    this.code,
    this.cause,
  });

  final ErrorClass klass;
  final String message;
  final String? code;
  final Object? cause;

  @override
  String toString() => 'AppError($klass, $message${code != null ? ', code: $code' : ''})';
}
