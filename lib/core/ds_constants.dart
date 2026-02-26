import 'dart:async';

import 'package:ds_common/core/fimber/ds_fimber_base.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'contracts/ds_contracts.dart';
import 'ds_logging.dart';

class DSConstants implements IDSConstants {
  DSConstants({required VoidCallback? then}) {
    unawaited(() async {
      await internalInit();
      _isInitialized = true;
      then?.call();
    }());
  }

  static final startTime = DateTime.timestamp();

  @protected
  @mustCallSuper
  Future<void> internalInit() async {
    packageInfo = await PackageInfo.fromPlatform();
    if (packageInfo.version.split('.').length == 3) {
      logDebug('INTERNAL VERSION: ${packageInfo.version}');
      _isInternalVersion = true;
    }
  }

  var _isInitialized = false;
  var _isInternalVersion = false;

  @override
  bool get isInitialized => _isInitialized;

  @override
  Future<void> waitForInit({Duration maxWait = const Duration(seconds: 5)}) async {
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

  @override
  bool get isInternalVersion {
    if (!_isInitialized) {
      const err = 'Wait for init';
      assert(false, err);
      Fimber.e(err, stacktrace: StackTrace.current);
    }
    return _isInternalVersion;
  }

  @override
  bool get isInternalVersionOpt => _isInternalVersion;

  bool get isProductionVersion => !isInternalVersion;

  @override
  late final PackageInfo packageInfo;

  int? _buildNumber;

  @override
  int get buildNumber {
    if (!isInitialized) {
      const err = 'Wait for initialization DSConstants firstly';
      assert(false, err);
      Fimber.e(err, stacktrace: StackTrace.current);
      return 0;
    }
    if (_buildNumber != null) return _buildNumber!;
    final build = int.tryParse(packageInfo.buildNumber);
    if (build == null || packageInfo.buildNumber != build.toString()) {
      const err = 'Failed to parse build';
      assert(false, err);
      Fimber.e(err, stacktrace: StackTrace.current, attributes: {
        'build_num': packageInfo.buildNumber,
      });
      _buildNumber = 0;
    } else {
      _buildNumber = build;
    }
    return _buildNumber!;
  }
}
