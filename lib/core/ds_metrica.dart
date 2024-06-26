import 'dart:async';
import 'dart:io';

import 'package:appmetrica_plugin/appmetrica_plugin.dart' as m;
import 'package:decimal/decimal.dart' as d;
import 'package:ds_common/core/ds_constants.dart';
import 'package:fimber/fimber.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:userx_flutter/userx_flutter.dart';

import 'ds_logging.dart';
import 'ds_prefs.dart';
import 'ds_remote_config.dart';

typedef AdRevenue = m.AdRevenue;
typedef AdType = m.AdType;
typedef Decimal = d.Decimal;
typedef UserProfile = m.UserProfile;
typedef StringAttribute = m.StringAttribute;
typedef AppMetricaErrorDescription = m.AppMetricaErrorDescription;

/// You must call
/// await DSMetrica.init()
/// at the app start
abstract class DSMetrica {
  static const _firstEventParam = 'ds_metrica_first_session_event';

  static var _eventId = 0;
  static var _userXKey = '';
  static var _yandexId = '';
  static late final bool _debugModeSend;
  static var _userXRunning = false;
  static var _previousScreenName = '';

  static final _persistentAttrs = <String, Object>{};
  static Map<String, Object> Function()? _persistentAttrsHandler;
  static var _isInitialized = false;

  static String get yandexId {
    assert(_isInitialized);
    return _yandexId;
  }

  /// Initialize DSMetrica. Must call before the first use
  /// [yandexKey] - API key of Yandex App Metrica
  /// [userXKey] - API key of UserX
  /// [forceSend] - send events in debug mode too
  static Future<void> init({
    required String yandexKey,
    required String userXKey,
    bool debugModeSend = false,
  }) async {
    if (_isInitialized) {
      Fimber.e('DSMetrica is already initialised', stacktrace: StackTrace.current);
      return;
    }

    _userXKey = userXKey;
    _debugModeSend = debugModeSend;

    WidgetsFlutterBinding.ensureInitialized();
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      await m.AppMetrica.activate(m.AppMetricaConfig(yandexKey,
        sessionsAutoTracking: !kDebugMode || _debugModeSend,
      ));
      if (kDebugMode && !_debugModeSend) {
        await m.AppMetrica.pauseSession();
      }
    } else {
      assert(yandexKey == '', 'yandexKey supports mobile platform only. Remove yandexKey id');
      assert(userXKey == '', 'userXKey supports mobile platform only. Remove userXKey id');
    }
    _isInitialized = true;
    // allow to first start without internet connection
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      unawaited(() async {
        try {
          _yandexId = await m.AppMetrica.requestAppMetricaDeviceID();
          Fimber.d('yandexId=$yandexId');
        } on m.DeviceIdRequestException catch (e, stack) {
          Fimber.e('$e reason=${e.reason}', stacktrace: stack);
        }
      }());
    }
  }

  /// Set user profile ID
  static Future<void> setUserProfileID(String userProfileID) => m.AppMetrica.setUserProfileID(userProfileID);

  /// Send only one event per app lifetime
  static void reportFirstEvent(String eventName, {Map<String, Object>? attributes, int stackSkip = 1}) {
    final firstEvent = DSPrefs.I.internal.getString(_firstEventParam);
    if (firstEvent != null) return;
    DSPrefs.I.internal.setString(_firstEventParam, eventName);
    reportEventWithMap('$eventName (first event)', attributes, stackSkip: stackSkip + 1);
  }

  /// Report event to AppMetrica and UserX (disabled in debug mode)
  static void reportEvent(String eventName, {
    bool fbSend = false,
    Map<String, Object>? attributes,
    Map<String, Object>? fbAttributes,
    int stackSkip = 1,
  }) => reportEventWithMap(eventName, attributes, fbSend: fbSend, fbAttributes: fbAttributes, stackSkip: stackSkip + 1);

  /// Report sceen change to implement Heatmaps functionality in UserX
  static Future<void> reportScreenOpened(String screenName, {Map<String, Object>? attributes}) async {
    if (_previousScreenName == screenName) return;
    _previousScreenName = screenName;
    reportEvent('$screenName, screen opened', attributes: attributes);
    UserX.addScreenName(screenName);
  }

  /// Call this method on app start and [AppLifecycleState.resumed]
  static void tryUpdateAppSessionId() {
    final appSuspended = DateTime.now().difference(DSPrefs.I.getAppLastUsed());
    if (appSuspended.inMinutes >= 1) {
      DSPrefs.I.setAppLastUsed(DateTime.now());
      final newSession = DSPrefs.I.getSessionId() + 1;
      DSPrefs.I.setSessionId(newSession);
      if (_userXRunning) {
        final sessions = DSRemoteConfig.I.getUserXSessions();
        if (sessions != 0 && sessions < newSession) {
          stopUserX();
        }
      }
    }
  }

  static var _reportEventError = false;
  static var _reportEventErrorFB = false;

  /// Report event to AppMetrica and UserX (disabled in debug mode)
  static Future<void> reportEventWithMap(String eventName,
      Map<String, Object>? attributes,{
        bool fbSend = false,
        Map<String, Object>? fbAttributes,
        int stackSkip = 1,
      }) async {
    if (kIsWeb || !Platform.isAndroid && !Platform.isIOS) return;

    _eventId++;
    try {
      final baseAttrs = <String, Object>{};
      baseAttrs.addAll(_persistentAttrs);

      baseAttrs.addAll(_persistentAttrsHandler?.call() ?? {});

      DSPrefs.I.setAppLastUsed(DateTime.now());
      final sessionId = DSPrefs.I.getSessionId();

      baseAttrs['session_id'] = sessionId;
      baseAttrs['event_id'] = _eventId;
      baseAttrs['user_time'] = DateTime.now().toIso8601String();

      final Map<String, Object> attrs;
      if (attributes == null) {
        attrs = baseAttrs;
      } else {
        attrs = Map<String, Object>.from(baseAttrs);
        attrs.addAll(attributes);
      }

      UserX.addEvent(eventName, attrs.map<String, String>((key, value) => MapEntry(key, '$value')));

      logDebug('$eventName $attrs', stackSkip: stackSkip, stackDeep: 5);

      if (kDebugMode && !_debugModeSend) return;

      if (fbSend) {
        unawaited(() async {
          try {
            await FirebaseAnalytics.instance.logEvent(name: eventName, parameters: () {
              if (fbAttributes != null) {
                final fbAttrs = Map<String, Object>.from(baseAttrs);
                fbAttrs.addAll(fbAttributes);
                return fbAttrs;
              } else {
                return attrs;
              }
            }());
          } catch (e, stack) {
            if (!_reportEventErrorFB) {
              _reportEventErrorFB = true;
              Fimber.e('$e', stacktrace: stack);
            }
          }
        }());
      }
      await m.AppMetrica.reportEventWithMap(eventName, attrs);
    } catch (e, stack) {
      if (!_reportEventError) {
        _reportEventError = true;
        Fimber.e('$e', stacktrace: stack);
      }
    }
  }

  /// AppMetrica wrapper
  static Future<void> reportAdRevenue(AdRevenue revenue) => m.AppMetrica.reportAdRevenue(revenue);

  /// AppMetrica wrapper
  static Future<void> reportUserProfile(UserProfile userProfile) => m.AppMetrica.reportUserProfile(userProfile);

  /// AppMetrica wrapper
  static Future<void> reportError({String? message, AppMetricaErrorDescription? errorDescription}) =>
      m.AppMetrica.reportError(message: message, errorDescription: errorDescription);

  /// Initialize UserX if it is allowed by RemoteConfig
  static Future<void> tryStartUserX() async {
    assert(DSConstants.isInitialized);
    assert(DSRemoteConfig.I.isInitialized);

    if (kDebugMode && !_debugModeSend) return;
    if (kIsWeb || !Platform.isAndroid && !Platform.isIOS) return;

    if (DSConstants.I.isInternalVersion) {
      await startUserX();
      return;
    }

    var val = DSRemoteConfig.I.getUserXPercent();
    if (val == 0) {
      await DSRemoteConfig.I.waitForFullInit(maxWait: const Duration(seconds: 20));
      val = DSRemoteConfig.I.getUserXPercent();
      if (val == 0) return;
    }
    final sessions = DSRemoteConfig.I.getUserXSessions();
    if (sessions != 0 && sessions < DSPrefs.I.getSessionId()) {
      return;
    }

    final yid = BigInt.tryParse(yandexId) ?? BigInt.from(yandexId.hashCode);
    if ((yid % BigInt.from(100)).toInt() < val) {
      await DSMetrica.startUserX();
    }
  }

  /// Initialize UserX
  static Future<void> startUserX() async {
    if (kIsWeb || !Platform.isAndroid && !Platform.isIOS) return;

    final sessions = DSRemoteConfig.I.getUserXSessions();
    if (sessions != 0 && sessions < DSPrefs.I.getSessionId()) {
      return;
    }

    reportEvent('userx starting');
    UserX.start(_userXKey);
    UserX.setUserId(yandexId);
    _userXRunning = true;
  }

  /// Stop UserX
  static Future<void> stopUserX() async {
    if (kIsWeb || !Platform.isAndroid && !Platform.isIOS) return;
    await UserX.stopScreenRecording();
    _userXRunning = false;
  }

  /// Save attributes to send it in every [reportEvent]
  static void addPersistentAttrs(Map<String, Object> attrs) {
    _persistentAttrs.addAll(attrs);
  }

  /// Calculate attributes to send it in every [reportEvent]
  static void setPersistentAttrsHandler(Map<String, Object> Function() handler) {
    _persistentAttrsHandler = handler;
  }

  /// Send yandex Id to Firebase if it was not send
  static Future<void> sendYandexDeviceId() async {
    if (kIsWeb || !Platform.isAndroid && !Platform.isIOS) return;

    if (DSPrefs.I.isYandexDeviceIdSent()) return;
    assert(yandexId.isNotEmpty);
    await FirebaseAnalytics.instance.setUserProperty(name: 'appmetrica_id', value: yandexId);
    await reportEventWithMap('set appmetrica_id', {'appmetrica_id': yandexId});
    DSPrefs.I.setYandexDeviceIdSent(true);
  }

  /// Adds a [key]-[value] pair to or deletes it from the application error environment. The environment is shown in the crash and error report.
  ///
  /// * The maximum length of the [key] key is 50 characters. If the length is exceeded, the key is truncated to 50 characters.
  /// * The maximum length of the [value] value is 4000 characters. If the length is exceeded, the value is truncated to 4000 characters.
  /// * A maximum of 30 environment pairs of the form {key, value} are allowed. If you try to add the 31st pair, it will be ignored.
  /// * Total size (sum {len(key) + len(value)} for (key, value) in error_environment) - 4500 characters.
  /// * If a new pair exceeds the total size, it will be ignored.
  static Future<void> putErrorEnvironmentValue(String key, String? value) =>
      m.AppMetrica.putErrorEnvironmentValue(key, value);

}
