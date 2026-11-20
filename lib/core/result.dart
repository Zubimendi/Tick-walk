import 'errors.dart';

sealed class Result<T> {
  const Result();

  bool get isOk => this is Ok<T>;
  bool get isErr => this is Err<T>;

  T? get valueOrNull => switch (this) {
        Ok(:final value) => value,
        Err() => null,
      };

  AppError? get errorOrNull => switch (this) {
        Ok() => null,
        Err(:final error) => error,
      };

  R when<R>({
    required R Function(T value) ok,
    required R Function(AppError error) err,
  }) =>
      switch (this) {
        Ok(:final value) => ok(value),
        Err(:final error) => err(error),
      };

  Result<U> map<U>(U Function(T value) transform) => switch (this) {
        Ok(:final value) => Ok(transform(value)),
        Err(:final error) => Err(error),
      };
}

final class Ok<T> extends Result<T> {
  const Ok(this.value);
  final T value;
}

final class Err<T> extends Result<T> {
  const Err(this.error);
  final AppError error;
}
