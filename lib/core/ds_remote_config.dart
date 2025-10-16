import 'dart:async';

import 'package:ds_common/core/fimber/ds_fimber_base.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';

import 'ds_constants.dart';
import 'ds_metrica.dart';

class DSRemoteConfig extends ChangeNotifier {
  final _remoteConfig = FirebaseRemoteConfig.instance;

  var _isInitialized = false;
  var _isFullyInitialized = false;
  var _isInitDone = false;
  var _prefix = '';
  var _postfix = '';

  bool get isInitialized => _isInitialized;
  bool get isFullyInitialized => _isFullyInitialized;

  static DSRemoteConfig? _instance;

  static DSRemoteConfig get I {
    assert(_instance != null, 'Call DSRemoteConfig() or its subclass before use');
    return _instance!;
  }

  DSRemoteConfig({
    required Map<String, dynamic> defaults,
    VoidCallback? onInitialized,
    VoidCallback? onLoaded,
  }) {
    assert(_instance == null);
    _instance = this;

    unawaited(() async {
      final startTime = DateTime.now();
      await _remoteConfig.setConfigSettings(RemoteConfigSettings(
        fetchTimeout: const Duration(minutes: 1),
        minimumFetchInterval: const Duration(hours: 1),
      ));
      await _remoteConfig.setDefaults(defaults);
      await _remoteConfig.ensureInitialized();
      DSMetrica.reportEvent('remote config prestate',
        attributes: _remoteConfig.getAll().map((key, value) => MapEntry('prestate_$key', value.asString())),
      );
      _isInitialized = true;
      notifyListeners();
      onInitialized?.call();

      try {
        await _remoteConfig.fetchAndActivate();
        _isFullyInitialized = true;
        DSMetrica.addPersistentAttrs(_remoteConfig.getAll()
            .map((key, value) => MapEntry(key, value.asString()))
          ..removeWhere((k, v) => !k.startsWith('exp_'))
        );
      } catch (e, stack) {
        Fimber.e('$e', stacktrace: stack);
      }

      final attrs = _remoteConfig.getAll().map<String, Object>((key, value) => MapEntry(key, value.asString()));
      attrs['remote_config_load_seconds'] = DateTime.now().difference(startTime).inSeconds;
      attrs['remote_config_loaded'] = _isFullyInitialized;
      DSMetrica.reportEvent('remote_config_loaded', fbSend: true, attributes: attrs);
      _isInitDone = true;
      notifyListeners();
      onLoaded?.call();
    } ());
  }

  Future<void> waitForInit({final maxWait = const Duration(seconds: 5)}) async {
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

  Future<void> waitForFullInit({final maxWait = const Duration(seconds: 5)}) async {
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
    if (DSConstants.I.isInternalVersionOpt) return '_d';
    return _postfix;
  }

  void setPrefix(String value) => _prefix = value;
  void setPostfix(String value) {
    assert(value == '_d' || !DSConstants.I.isInternalVersionOpt, 'Currently only _d postfix supported for internal versions');
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

  /// Gets the value for a given [key] as a bool.
  /// Returns [defVal] if the [key] does not exist.
  bool getBool(String key, {bool defVal = false}) {
    final k = _getKey(key);
    if (k == null) return defVal;
    return _remoteConfig.getBool(k);
  }

  /// Gets the value for a given [key] as an int.
  /// Returns [defVal] if the [key] does not exist.
  int getInt(String key, {int defVal = 0}) {
    final k = _getKey(key);
    if (k == null) return defVal;
    return _remoteConfig.getInt(k);
  }

  /// Gets the value for a given [key] as a String.
  /// Returns [defVal] if the [key] does not exist.
  String getString(String key, {String defVal = ''}) {
    final k = _getKey(key);
    if (k == null) return defVal;
    return _remoteConfig.getString(k);
  }

  /// Gets the value for a given [key] as a Duration.
  /// Returns [defVal] if the [key] does not exist.
  Duration getDuration(String key, {Duration defVal = const Duration(seconds: 0)}) {
    var res = getInt(key, defVal: defVal.inSeconds);
    if (res < 0) {
      res = 0;
    }
    return Duration(seconds: res);
  }

  int getUXCamPercent() => getInt('uxcam_percent', defVal: getUserXPercent());
  int getUXCamSessions() => getInt('uxcam_sessions', defVal: getUserXSessions());
  int getUXCamMinBuild() => getInt('uxcam_min_build', defVal: 0);

  /// Will be removed in future versions. Use uxcam_percent
  int getUserXPercent() => getInt('userx_percent');
  int getUserXSessions() => getInt('userx_sessions');

}