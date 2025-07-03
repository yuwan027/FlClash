import 'dart:async';

import 'package:fl_clash/enum/enum.dart';

class Debouncer {
  final Map<FunctionTag, Timer?> _operations = {};

  call(
    FunctionTag tag,
    Function func, {
    List<dynamic>? args,
    Duration duration = const Duration(milliseconds: 600),
  }) {
    final timer = _operations[tag];
    if (timer != null) {
      timer.cancel();
    }
    _operations[tag] = Timer(
      duration,
      () {
        _operations[tag]?.cancel();
        _operations.remove(tag);
        Function.apply(
          func,
          args,
        );
      },
    );
  }

  cancel(dynamic tag) {
    _operations[tag]?.cancel();
    _operations[tag] = null;
  }
}

class Throttler {
  final Map<FunctionTag, Timer?> _operations = {};

  call(
    FunctionTag tag,
    Function func, {
    List<dynamic>? args,
    Duration duration = const Duration(milliseconds: 600),
  }) {
    final timer = _operations[tag];
    if (timer != null) {
      return true;
    }
    _operations[tag] = Timer(
      duration,
      () {
        _operations[tag]?.cancel();
        _operations.remove(tag);
        Function.apply(
          func,
          args,
        );
      },
    );
    return false;
  }

  cancel(dynamic tag) {
    _operations[tag]?.cancel();
    _operations[tag] = null;
  }
}

Future<T> retry<T>({
  required Future<T> Function() task,
  int maxAttempts = 3,
  required bool Function(T res) retryIf,
  Duration delay = Duration.zero,
}) async {
  int attempts = 0;
  while (attempts < maxAttempts) {
    final res = await task();
    if (!retryIf(res) || attempts >= maxAttempts) {
      return res;
    }
    attempts++;
  }
  throw "unknown error";
}

final debouncer = Debouncer();

final throttler = Throttler();
