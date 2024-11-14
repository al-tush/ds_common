import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:ui';

import 'package:ds_fimber/ds_fimber.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'ds_fimber_trees.dart';
import 'ds_metrica.dart';

abstract class DSFimberService {
  DSFimberService._();

  static const String _portName = 'ds_fimber_service';

  static var _isInitializedInMain = false;
  static var _isInitializedInIsolate = false;

  static Future<void> initFimberInMain(FirebaseOptions? firebaseOptions) async {
    if (_isInitializedInMain) return;
    _isInitializedInMain = true;

    FutureBuilder.debugRethrowError = true;

    WidgetsFlutterBinding.ensureInitialized();

    if (kDebugMode) {
      Fimber.plantTree(DSDebugTree(useColors: true));
    }
    Fimber.plantTree(DSCrashReportingTree());

    FlutterError.onError = (details) {
      Fimber.e('${details.exception}', stacktrace: details.stack);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      Fimber.e('$error', stacktrace: stack);
      return true;
    };

    try {
      await Firebase.initializeApp(options: firebaseOptions);
    } catch (e, trace) {
      Fimber.e('$e', stacktrace: trace);
    }

    if (!kIsWeb) {
      Isolate.current.addErrorListener(RawReceivePort((pair) async {
        final List<dynamic> errorAndStacktrace = pair;
        final error = errorAndStacktrace.first;
        final stackText = errorAndStacktrace.last as String?;
        final StackTrace? stack;
        if (stackText?.isNotEmpty == true) {
          stack = StackTrace.fromString(stackText!);
        } else {
          stack = null;
        }
        Fimber.e('$error', stacktrace: stack);
      }).sendPort);

      if (kDebugMode) {
        await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(false);
      }
      unawaited(FirebaseCrashlytics.instance.setUserIdentifier(DSMetrica.yandexId));

      IsolateNameServer.removePortNameMapping(_portName);
      final port = ReceivePort(_portName);
      final res = IsolateNameServer.registerPortWithName(port.sendPort, _portName);
      if (!res) {
        Fimber.e('Failed to register port $_portName', stacktrace: StackTrace.current);
      }
      port.listen((message) {
        final level = message[0] as String;
        final msg = message[1] as String;
        final tag = message[2] as String?;
        final ex = message[3];
        final stack = message[4] is String ? StackTrace.fromString(message[4]) : null;
        final attrsJson = message[5] as String?;
        final attrs = attrsJson != null ? jsonDecode(attrsJson) : null;
        Fimber.log(level, msg, tag: tag, ex: ex, stacktrace: stack, attributes: attrs);
      });
    }
  }

  static Future<void> initFimberInIsolate() async {
    if (_isInitializedInMain) {
      Fimber.e('Fimber is already initialized', stacktrace: StackTrace.current);
      return;
    }

    if (_isInitializedInIsolate) return;
    _isInitializedInIsolate = true;

    Fimber.plantTree(_ReportingTreeIsolate());

    Isolate.current.addErrorListener(RawReceivePort((pair) async {
      final List<String> errorAndStacktrace = pair;
      Fimber.e(errorAndStacktrace.first, stacktrace: StackTrace.fromString(errorAndStacktrace.last));
    }).sendPort);
  }
}

class _ReportingTreeIsolate extends LogTree {

  SendPort? _sendPort;

  @override
  List<String> getLevels() => ['V', 'D', 'I', 'W', 'E'];

  _ReportingTreeIsolate() {
    _sendPort = IsolateNameServer.lookupPortByName(DSFimberService._portName);
  }

  @override
  void log(
    String level,
    String message, {
    String? tag,
    dynamic ex,
    StackTrace? stacktrace,
    Map<String, String?>? attributes,
  }) {
    final attrsJson = attributes != null ? jsonEncode(attributes) : null;
    _sendPort?.send([level, message, tag, ex, stacktrace?.toString(), attrsJson]);
  }
}
