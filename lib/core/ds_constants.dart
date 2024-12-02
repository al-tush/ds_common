import 'dart:async';

import 'package:ds_common/core/fimber/ds_fimber_base.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'ds_logging.dart';

class DSConstants {
  static bool get isInitialized => _instance?._isInitialized ?? false;

  static DSConstants? _instance;

  static DSConstants get I {
    assert(_instance != null, 'Call DSConstants(...) or its subclass before use');
    return _instance!;
  }

  @protected
  @mustCallSuper
  Future<void> internalInit() async {
    packageInfo = await PackageInfo.fromPlatform();
    // 3-number builds are internal (ex 1.4.12)
    if (packageInfo.version.split('.').length == 3) {
      logDebug('INTERNAL VERSION: ${packageInfo.version}');
      _isInternalVersion = true;
    }
  }

  DSConstants({required VoidCallback? then}) {
    assert(_instance == null);
    _instance = this;
    unawaited(() async {
      await internalInit();
      _isInitialized = true;
      then?.call();
    }());
  }

  var _isInitialized = false;
  var _isInternalVersion = false;

  Future<void> waitForInit({final maxWait = const Duration(seconds: 5)}) async {
    final start = DateTime.now();
    while (true) {
      if (isInitialized) break;
      if (DateTime.now().difference(start) >= maxWait) {
        Fimber.e('Failed to wait DSConstants', stacktrace: StackTrace.current);
        break;
      }
      await Future.delayed(const Duration(milliseconds: 10));
    }
  }

  /// is app build internal (3-number builds are internal - ex. 1.4.12; 2-number are production - 1.0, 3.1, etc)
  bool get isInternalVersion {
    if (!_isInitialized) {
      const err = 'Wait for init';
      assert(false, err);
      Fimber.e(err, stacktrace: StackTrace.current);
    }
    return _isInternalVersion;
  }

  bool get isInternalVersionOpt => _isInternalVersion;

  /// is app build production (2-number builds are production - 1.0, 3.1, etc)
  bool get isProductionVersion => !isInternalVersion;

  @Deprecated('Use isProductionVersion instead')
  bool get isProductionAds => isProductionVersion;

  late final PackageInfo packageInfo;
}