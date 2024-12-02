import 'dart:async';

import 'package:ds_common/core/fimber/ds_fimber_base.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

import '../ds_logging.dart';
import '../ds_metrica.dart';
import '../ds_metrica_types.dart';

class DSDebugTree extends DebugTree {
  static final Map<String, DSAnsiColor> _colorizeMap = {
    'V': DSAnsiColor.fg(DSAnsiColor.grey(0.5)),
    'D': DSAnsiColor.fg(96),
    'I': DSAnsiColor.fg(12),
    'W': DSAnsiColor.fg(208),
    'E': DSAnsiColor.fg(196),
  };

  final bool useColors;

  DSDebugTree({
    super.logLevels = DebugTree.defaultLevels,
    this.useColors = true,
  });

  @override
  void printLog(String logLine, {String? level}) {
    assert(printTimeType == DebugTree.timeClockType);
    final colorizeTransform = (level != null && useColors) ? _colorizeMap[level] : null;
    var date = DateTime.now().toIso8601String();
    var isFirst = true;
    logLine.split('\n').forEach((line) {
      var printableLine = line;
      if (isFirst) {
        isFirst = false;
        printableLine = '$date\t$line';
      }
      if (colorizeTransform != null) {
        debugPrint(colorizeTransform(printableLine));
      } else {
        debugPrint(printableLine);
      }
    });
  }
}

class DSCrashReportingTree extends LogTree {
  /// Exclude errors with this substrings
  static final excludes = <String>{};

  /// Errors will be skipped if description and stack are same as one of [skipCloneErrors] last errors
  static var skipCloneErrors = 0;

  /// Only Log Warnings and Exceptions
  static const defaultLevels = <String>['W', 'E'];

  /// Same values as android.util.Log
  static const _priorities = <String, int>{
    'V': 2,
    'D': 3,
    'I': 4,
    'W': 5,
    'E': 6,
  };
  final List<String> logLevels;
  final _lastErrors = <String>[];

  @override
  List<String> getLevels() => logLevels;

  DSCrashReportingTree({this.logLevels = defaultLevels});

  @override
  void log(
    String level,
    String message, {
    String? tag,
    dynamic ex,
    StackTrace? stacktrace,
    Map<String, String?>? attributes,
  }) {
    if (excludes.any((e) => message.contains(e))) return;
    if (skipCloneErrors > 0) {
      final text = '$message $stacktrace';
      if (_lastErrors.contains(text)) return;
      if (_lastErrors.length >= skipCloneErrors) {
        _lastErrors.removeRange(skipCloneErrors, _lastErrors.length);
      }
      _lastErrors.insert(0, text);
    }

    if (!kIsWeb) {
      FirebaseCrashlytics.instance.setCustomKey('priority', _priorities[level] ?? 0);
      FirebaseCrashlytics.instance.recordError('[$level] $message', stacktrace);
      FirebaseCrashlytics.instance.setCustomKey('priority', -1);
    }

    if (!message.contains('failed to connect to yandex')) {
      unawaited(DSMetrica.reportError(
        message: '[$level] $message',
        errorDescription:
            stacktrace != null ? AppMetricaErrorDescription(stacktrace, message: message, type: '[$level]') : null,
      ));
      // unawaited(Sentry.captureException(
      //   ex ?? '[$level] $message',
      //   stackTrace: stacktrace,
      //   withScope: (scope) {
      //     scope.setTag('user_id_metrica', DSMetrica.yandexId);
      //   },
      // ));
      final limStack = LimitedStackTrace(
        stackTrace: stacktrace ?? StackTrace.empty,
        deep: 4,
      );
      final Map<String, String> additionalAttributes = attributes?.map((key, v) => MapEntry(key, v.toString())) ?? {};
      DSMetrica.reportEvent('[$level] $message', attributes: {
        'error_priority': _priorities[level] ?? 0,
        'stack': '$limStack',
        ...additionalAttributes,
      });
    }
  }
}
