import 'dart:async';

import 'package:ds_common/core/fimber/ds_fimber_base.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';

import 'contracts/ds_contracts.dart';

typedef RemoteConfigReportEvent = void Function(String eventName, Map<String, Object> attributes);
typedef RemoteConfigAddPersistentAttrs = void Function(Map<String, String> attrs);

class DSRemoteConfig extends ChangeNotifier implements IDSRemoteConfig {
  DSRemoteConfig({
    required Map<String, dynamic> defaults,
    required IDSConstants constants,
    VoidCallback? onInitialized,
    VoidCallback? onLoaded,
    RemoteConfigReportEvent? onReportEvent,
    RemoteConfigAddPersistentAttrs? onAddPersistentAttrs,
  }) : _constants = constants {
    unawaited(() async {
      final startTime = DateTime.now();
      await _remoteConfig.setConfigSettings(RemoteConfigSettings(
        fetchTimeout: const Duration(minutes: 1),
        minimumFetchInterval: const Duration(hours: 1),
      ));
      await _remoteConfig.setDefaults(defaults);
      await _remoteConfig.ensureInitialized();
      onReportEvent?.call(
        'remote config prestate',
        _remoteConfig.getAll().map((key, value) => MapEntry('prestate_$key', value.asString())),
      );
      _isInitialized = true;
      notifyListeners();
      onInitialized?.call();

      try {
        await _remoteConfig.fetchAndActivate();
        _isFullyInitialized = true;
        final attrs = _remoteConfig.getAll()
            .map((key, value) => MapEntry(key, value.asString()))
          ..removeWhere((k, v) => !k.startsWith('exp_'));
        onAddPersistentAttrs?.call(Map.from(attrs));
      } catch (e, stack) {
        Fimber.e('$e', stacktrace: stack);
      }

      final eventAttrs = Map<String, Object>.from(
        _remoteConfig.getAll().map((key, value) => MapEntry(key, value.asString())),
      );
      eventAttrs['remote_config_load_seconds'] = DateTime.now().difference(startTime).inSeconds;
      eventAttrs['remote_config_loaded'] = _isFullyInitialized;
      onReportEvent?.call('remote_config_loaded', eventAttrs);
      _isInitDone = true;
      notifyListeners();
      onLoaded?.call();
    }());
  }

  final IDSConstants _constants;
  final _remoteConfig = FirebaseRemoteConfig.instance;

  var _isInitialized = false;
  var _isFullyInitialized = false;
  var _isInitDone = false;
  var _prefix = '';
  var _postfix = '';

  @override
  bool get isInitialized => _isInitialized;

  @override
  bool get isFullyInitialized => _isFullyInitialized;

  @override
  Future<void> waitForInit({Duration maxWait = const Duration(seconds: 5)}) async {
    final start = DateTime.now();
    while (true) {
      if (isInitialized) break;
      if (DateTime.now().difference(start) >= maxWait) {
        Fimber.e('Failed to wait RemoteConfig', stacktrace: StackTrace.current);
        break;
      }
      await Future.delayed(const Duration(milliseconds: 10));
    }
  }

  @override
  Future<void> waitForFullInit({Duration maxWait = const Duration(seconds: 5)}) async {
    final start = DateTime.now();
    while (true) {
      if (isFullyInitialized) break;
      if (DateTime.now().difference(start) >= maxWait || _isInitDone) {
        Fimber.e('Failed to wait RemoteConfig full load', stacktrace: StackTrace.current);
        break;
      }
      await Future.delayed(const Duration(milliseconds: 100));
    }
  }

  String get prefix => _prefix;
  String get postfix {
    if (_constants.isInternalVersionOpt) return '_d';
    return _postfix;
  }

  void setPrefix(String value) => _prefix = value;
  @override
  void setPostfix(String value) {
    assert(value == '_d' || !_constants.isInternalVersionOpt, 'Currently only _d postfix supported for internal versions');
    _postfix = value;
  }

  String? _getKey(String key) {
    final all = _remoteConfig.getAll();
    if (prefix.isNotEmpty || postfix.isNotEmpty) {
      final sKey = '$prefix$key$postfix';
      if (all.containsKey(sKey)) return sKey;
    }
    if (all.containsKey(key)) return key;
    return null;
  }

  bool getBool(String key, {bool defVal = false}) {
    final k = _getKey(key);
    if (k == null) return defVal;
    return _remoteConfig.getBool(k);
  }

  int getInt(String key, {int defVal = 0}) {
    final k = _getKey(key);
    if (k == null) return defVal;
    return _remoteConfig.getInt(k);
  }

  @override
  String getString(String key, {String defVal = ''}) {
    final k = _getKey(key);
    if (k == null) return defVal;
    return _remoteConfig.getString(k);
  }

  Duration getDuration(String key, {Duration defVal = const Duration(seconds: 0)}) {
    var res = getInt(key, defVal: defVal.inSeconds);
    if (res < 0) res = 0;
    return Duration(seconds: res);
  }

  @override
  int getUXCamPercent() => getInt('uxcam_percent', defVal: getUserXPercent());
  @override
  int getUXCamSessions() => getInt('uxcam_sessions', defVal: getUserXSessions());
  @override
  int getUXCamMinBuild() => getInt('uxcam_min_build', defVal: 0);

  int getUserXPercent() => getInt('userx_percent');
  int getUserXSessions() => getInt('userx_sessions');
}
