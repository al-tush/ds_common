import 'dart:async';

import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Контракт доступа к префам для сервисов ds_common (сессия, last used, yandex id, сырой доступ).
abstract interface class IDSPrefs {
  SharedPreferences get internal;

  int getSessionId();
  void setSessionId(int value);

  DateTime getAppLastUsed();
  void setAppLastUsed(DateTime value);

  bool isYandexDeviceIdSent();
  void setYandexDeviceIdSent(bool value);
}

/// Контракт констант приложения (internal build, package info).
abstract interface class IDSConstants {
  bool get isInitialized;
  bool get isInternalVersion;
  bool get isInternalVersionOpt;
  int get buildNumber;
  PackageInfo get packageInfo;

  Future<void> waitForInit({Duration maxWait = const Duration(seconds: 5)});
}

/// Контракт remote config для DSMetrica/DSReferrer (uxcam, инициализация).
abstract interface class IDSRemoteConfig {
  bool get isInitialized;
  bool get isFullyInitialized;

  Future<void> waitForInit({Duration maxWait = const Duration(seconds: 5)});
  Future<void> waitForFullInit({Duration maxWait = const Duration(seconds: 5)});

  void setPostfix(String value);

  int getUXCamPercent();
  int getUXCamSessions();
  int getUXCamMinBuild();

  String getString(String key, {String defVal = ''});
}

typedef DSReferrerCallback = void Function(Map<String, String> fields);

/// Контракт реферера для DSMetrica (получение полей, подписка на изменения).
abstract interface class IDSReferrer {
  bool get isInitialized;
  Map<String, String> getReferrerFields();
  void registerChangedCallback(DSReferrerCallback callback);
  void unregisterAttributionCallback(DSReferrerCallback callback);
}
