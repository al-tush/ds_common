import 'dart:async';
import 'dart:io';


import 'package:ds_fimber/ds_fimber.dart';
import 'package:flutter/foundation.dart';

// static extensions not supported yet https://github.com/dart-lang/language/issues/723

@Deprecated('Remove TEST calls before release')
void logTest(String message, {int stackSkip = 0, int stackDeep = 3}) {
  final date = DateTime.now().toIso8601String();
  debugPrint(DSAnsiColor.fg(11)('$date\tTEST: ')
      + DSAnsiColor.bg(153)(message));

  final stackLines = StackTrace.current.toString().split('\n');
  final stackPart = stackLines.getRange(stackSkip + 1, stackLines.length + stackSkip - 1).take(stackDeep);
  for (final line in stackPart) {
    debugPrint(DSAnsiColor.fg(11)(line));
  }
}

void logDebug(String message, {int stackSkip = 0, int stackDeep = 5}) {
  if (!kDebugMode) return;
  Fimber.d(message, stacktrace: LimitedStackTrace(
    stackTrace: StackTrace.current,
    skipFirst: stackSkip + 1,
    deep: stackDeep,
  ));
}

void catchAsWarning(void Function() func) {
  try {
    func();
  } catch (e, stack) {
    Fimber.w('$e', stacktrace:  stack);
  }
}

Future<void> catchAsWarningAsync(Future<void> Function() func) async {
  try {
    await func();
  } catch (e, stack) {
    Fimber.w('$e', stacktrace:  stack);
  }
}

void unawaitedCatch(Future<void> Function() func) {
  final hostStack = StackTrace.current;
  unawaited(() async {
    try {
      await func();
    } catch (e, stack) {
      final host = LimitedStackTrace(
        stackTrace: hostStack,
        skipFirst: 1,
      );
      Fimber.e('$e', stacktrace: StackTrace.fromString('$stack$host'));
    }
  } ());
}

class LimitedStackTrace implements StackTrace {
  final StackTrace stackTrace;
  final int skipFirst;
  final int deep;

  const LimitedStackTrace({
    required this.stackTrace,
    this.skipFirst = 0,
    this.deep = 3,
  });

  @override
  String toString() {
    final list = stackTrace.toString().split('\n');
    return list.getRange(skipFirst, list.length - 1).take(deep).join('\n');
  }
}

/// Copied from pub.dartlang.org/logger-1.1.0/lib/src/ansi_color.dart
/// This class handles colorizing of terminal output.
class DSAnsiColor {
  /// ANSI Control Sequence Introducer, signals the terminal for new settings.
  static const ansiEsc = '\x1B[';

  /// Reset all colors and options for current SGRs to terminal defaults.
  static const ansiDefault = '${ansiEsc}0m';

  final int? fg;
  final int? bg;
  final bool color;

  DSAnsiColor.none()
      : fg = null,
        bg = null,
        color = false;

  DSAnsiColor.fg(this.fg)
      : bg = null,
        color = true;

  DSAnsiColor.bg(this.bg)
      : fg = null,
        color = true;

  @override
  String toString() {
    if (!kIsWeb && Platform.isIOS) return '';

    if (fg != null) {
      return '${ansiEsc}38;5;${fg}m';
    } else if (bg != null) {
      return '${ansiEsc}48;5;${bg}m';
    } else {
      return '';
    }
  }

  String call(String msg) {
    if (color && !kIsWeb && !Platform.isIOS) {
      return '$this$msg$ansiDefault';
    } else {
      return msg;
    }
  }

  DSAnsiColor toFg() => DSAnsiColor.fg(bg);

  DSAnsiColor toBg() => DSAnsiColor.bg(fg);

  /// Defaults the terminal's foreground color without altering the background.
  String get resetForeground => color && !kIsWeb && !Platform.isIOS ? '${ansiEsc}39m' : '';

  /// Defaults the terminal's background color without altering the foreground.
  String get resetBackground => color && !kIsWeb && !Platform.isIOS ? '${ansiEsc}49m' : '';

  static int grey(double level) => 232 + (level.clamp(0.0, 1.0) * 23).round();
}
