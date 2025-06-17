import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:amplitude_flutter/amplitude.dart';
import 'package:amplitude_flutter/configuration.dart';
import 'package:amplitude_flutter/events/base_event.dart';
import 'package:appmetrica_plugin/appmetrica_plugin.dart' as m;
import 'package:ds_common/core/ds_primitives.dart';
import 'package:ds_common/core/ds_referrer.dart';
import 'package:ds_common/core/fimber/ds_fimber_base.dart';


import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_uxcam/flutter_uxcam.dart';

import 'ds_adjust.dart';
import 'ds_app_state.dart';
import 'ds_constants.dart';
import 'ds_internal.dart';
import 'ds_logging.dart';
import 'ds_metrica_types.dart';
import 'ds_prefs.dart';
import 'ds_remote_config.dart';

typedef DSMetricaAttrsCallback = Map<String, Object> Function();

enum EventSendingType { everyTime, oncePerAppLifetime }

enum DSMetricaUserIdType {
  /// Not initialize Metrica.setUserProfileID(...)
  none,
  /// Use Metrica.setUserProfileID(DEVICE_ID)
  @Deprecated('Legacy only. Prefer to use adjustId in new apps')
  deviceId,
  /// Use Metrica.setUserProfileID(ADJUST_ID)
  adjustId,
}

/// You must call
/// await DSMetrica.init()
/// at the app start
abstract class DSMetrica {
  static const _firstEventParam = 'ds_metrica_first_session_event';

  static var _eventId = 0;
  static var _uxCamKey = '';
  static var _amplitudeKey = '';
  static Amplitude? _amplitude;
  static var _yandexId = '';
  static late final bool _lockMetricaProfile;
  static late final bool _debugModeSend;
  static var _uxCamInitializing = false;
  static var _uxCamRunning = false;
  static var _previousScreenName = '';
  /// Using this approach as we need to keep track of screens
  /// before this one and keep track of screens previous to the
  /// current one.
  static final _screenNames = <String>[];

  static final _persistentAttrs = <String, Object>{};
  static DSMetricaAttrsCallback? _attrsHandlerOld;
  static final  _attrsHandlers = <DSMetricaAttrsCallback>{};
  static var _isInitialized = false;

  static var _userIdType = DSMetricaUserIdType.none;
  static String? _userProfileID;

  static DSMetricaUserIdType get userIdType => _userIdType;

  static String get yandexId {
    assert(_isInitialized);
    return _yandexId;
  }

  static Future<String?> getAmplitudeDeviceId() async {
    if (_amplitudeKey.isEmpty) return null;
    return await _amplitude!.getDeviceId();
  }

  static Future<String?> getAmplitudeUserId() async {
    if (_amplitudeKey.isEmpty) return null;
    return await _amplitude!.getUserId();
  }

  /// Initialize DSMetrica. Must call before the first use
  /// [yandexKey] - API key of Yandex App Metrica
  /// [uxCamKey] - API key of UXCam
  /// [forceSend] - send events in debug mode too
  static Future<void> init({
    required String yandexKey,
    String uxCamKey = '',
    String amplitudeKey = '',
    DSMetricaUserIdType userIdType = DSMetricaUserIdType.none,
    bool lockMetricaProfile = false,
    bool debugModeSend = false,
  }) async {
    if (_isInitialized) {
      Fimber.e('DSMetrica is already initialised', stacktrace: StackTrace.current);
      return;
    }

    DSAppState.internalInit();

    _uxCamKey = uxCamKey;
    _amplitudeKey = amplitudeKey;
    _debugModeSend = debugModeSend;
    _userIdType = userIdType;
    _lockMetricaProfile = lockMetricaProfile;

    final waits = <Future>[];

    WidgetsFlutterBinding.ensureInitialized();

    waits.add(() async {
      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        await m.AppMetrica.activate(m.AppMetricaConfig(yandexKey,
          sessionsAutoTrackingEnabled: !kDebugMode || _debugModeSend,
          dataSendingEnabled: !kDebugMode || _debugModeSend ? null : false,
        ));

        if (kDebugMode && !_debugModeSend) {
          await m.AppMetrica.pauseSession();
        }
      } else {
        assert(yandexKey == '', 'yandexKey supports mobile platform only. Remove yandexKey id');
        assert(uxCamKey == '', 'uxCamKey supports mobile platform only. Remove uxCamKey id');
      }
    } ());
    if (_amplitudeKey.isNotEmpty) {
      waits.add(() async {
        _amplitude = Amplitude(Configuration(
          apiKey: _amplitudeKey,
        ));
      }());
    }

    await Future.wait(waits);

    switch (_userIdType) {
      case DSMetricaUserIdType.none:
        break;
      case DSMetricaUserIdType.adjustId:
        break;
        // ignore: deprecated_member_use_from_same_package
        case DSMetricaUserIdType.deviceId:
        unawaited(() async {
          final id = await getDeviceId();
          await DSMetrica.setUserProfileID(id);
          Fimber.d('deviceId=$id');
        } ());
        break;
    }

    DSAdjust.registerAttributionCallback((data) {
      final adid = DSAdjust.getAdid();
      if (_userIdType == DSMetricaUserIdType.adjustId && adid != null) {
        unawaited(DSMetrica.setUserProfileID(adid));
        Fimber.d('DSMetrica updated by Adjust adid=$adid');
      }
      unawaited(m.AppMetrica.reportExternalAttribution(m.AppMetricaExternalAttribution.adjust(
        adid: adid,
        trackerName: data.trackerName,
        trackerToken: data.trackerToken,
        network: data.network,
        campaign: data.campaign,
        adgroup: data.adgroup,
        creative: data.creative,
        clickLabel: data.clickLabel,
        costType: data.costType,
        costAmount: data.costAmount,
        costCurrency: data.costCurrency,
        fbInstallReferrer: data.fbInstallReferrer,
      )));
    });

    _isInitialized = true;
    // allow to first start without internet connection
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      unawaited(() async {
        // AppMetrica has lazy deviceId initialization after app install. Try to fix
        var exSent = false;
        for (var i = 0; i < 50; i++) {
          try {
            _yandexId = await m.AppMetrica.deviceId ?? '';
          } catch (e, stack) {
            if (!exSent) {
              exSent = true;
              Fimber.e('$e', stacktrace: stack);
            }
          }
          if (_yandexId.isNotEmpty) break;
          await Future.delayed(const Duration(milliseconds: 100));
        }
        Fimber.d('yandexId=$yandexId');
        if (_yandexId.isEmpty) {
          Fimber.e('yandexId was not initialized', stacktrace: StackTrace.current);
        }
      }());
    }
  }

  /// Get user profile ID which was initialized in current session
  static String? userProfileID() => _userProfileID;

  /// Set user profile ID
  static Future<void> setUserProfileID(String userProfileID) async {
    _userProfileID = userProfileID;
    if (_lockMetricaProfile) return;
    await Future.wait([
      m.AppMetrica.setUserProfileID(userProfileID),
      if (Platform.isAndroid)
        DSInternal.platform.invokeMethod('setUserProfile', userProfileID),
    ]);
  }

  /// Get legacy device id. Recommended to use other ID instead
  static Future<String> getDeviceId() async {
    if (kIsWeb) {
      throw Exception('Unsupported platform');
    }
    return await DSInternal.platform.invokeMethod('getDeviceId');
  }

  /// Report event to AppMetrica and uxcam (disabled in debug mode)
  /// [adjustSend] send just a eventName. If you need send extra use [DSAdjust.trackEvent]
  static void reportEvent(
      String eventName, {
        bool fbSend = false,
        bool adjustSend = false,
        bool amplitudeSend = true,
        Map<String, Object>? attributes,
        Map<String, Object>? fbAttributes,
        int stackSkip = 1,
        EventSendingType eventSendingType = EventSendingType.everyTime,
      }) =>
      reportEventWithMap(
        eventName,
        attributes,
        fbSend: fbSend,
        adjustSend: adjustSend,
        amplitudeSend: amplitudeSend,
        fbAttributes: fbAttributes,
        stackSkip: stackSkip + 1,
        eventSendingType: eventSendingType,
      );

  static String _normalizeScreenName(String? name) {
    var res = name ?? 'none';
    final p1 = res.indexOf('?');
    if (p1 >= 0) {
      res = res.substring(0, p1);
    }
    final p2 = res.indexOf('#');
    if (p2 >= 0) {
      res = res.substring(0, p2);
    }
    return res;
  }
  
  /// Report screen change to implement Heatmaps functionality in uxcam
  /// It removes all chars since ? and # (keep just path without queue and anchor)
  static Future<void> reportScreenOpened(String? screenName, {Map<String, Object>? attributes}) async {
    final sn = _normalizeScreenName(screenName);
    if (_previousScreenName == sn) return;
    _previousScreenName = sn;
    _screenNames.add(sn);
    reportEvent('$sn, screen opened', attributes: attributes);
    unawaited(FlutterUxcam.tagScreenName(sn));
  }

  /// Call this method on app start and [AppLifecycleState.resumed]
  static void tryUpdateAppSessionId() {
    final appSuspended = DateTime.now().difference(DSPrefs.I.getAppLastUsed());
    if (appSuspended.inMinutes >= 1) {
      DSPrefs.I.setAppLastUsed(DateTime.now());
      final newSession = DSPrefs.I.getSessionId() + 1;
      DSPrefs.I.setSessionId(newSession);
      if (_uxCamRunning) {
        final sessions = DSRemoteConfig.I.getUXCamSessions();
        if (sessions != 0 && sessions < newSession) {
          stopUXCam();
        }
      }
    }
  }

  static var _reportEventError = false;
  static var _reportEventErrorFB = false;

  /// Report event to AppMetrica and uxcam (disabled in debug mode)
  /// [adjustSend] send just a eventName. If you need send extra use [DSAdjust.trackEvent]
  static Future<void> reportEventWithMap(
      String eventName,
      Map<String, Object>? attributes, {
        bool fbSend = false,
        bool adjustSend = false,
        bool amplitudeSend = true,
        Map<String, Object>? fbAttributes,
        int stackSkip = 1,
        EventSendingType eventSendingType = EventSendingType.everyTime,
      }) async {
    if (kIsWeb || !Platform.isAndroid && !Platform.isIOS) return;

    if (eventSendingType == EventSendingType.oncePerAppLifetime && _isEventAlreadySendPerLifetime(eventName)) {
      logDebug(
          'Analytics event $eventName with type ${EventSendingType.oncePerAppLifetime.name} has already been dispatched, current report is skipped',
          stackSkip: stackSkip,
          stackDeep: 1);
      return;
    }

    _eventId++;
    try {
      final baseAttrs = <String, Object>{};
      baseAttrs.addAll(_persistentAttrs);

      baseAttrs.addAll(_attrsHandlerOld?.call() ?? {});
      for (final handler in _attrsHandlers) {
        baseAttrs.addAll(handler());
      }

      if (DSReferrer.isInitialized) {
        // Add referrer's attributes
        final data = DSReferrer.I.getReferrerFields();
        void addFromData(String key) {
          data[key]?.let((value) {
            baseAttrs[key] = value;
          });
        }
        if (Platform.isIOS) {
          addFromData('partner');
        } else {
          addFromData('utm_source');
          addFromData('utm_campaign');
          addFromData('utm_medium');
          addFromData('gclid');
        }
      }

      DSPrefs.I.setAppLastUsed(DateTime.now());
      final sessionId = DSPrefs.I.getSessionId();

      baseAttrs['session_id'] = sessionId;
      baseAttrs['event_id'] = _eventId;
      baseAttrs['since_app_start_sec'] = DateTime.timestamp().difference(DSConstants.startTime).inSeconds;
      baseAttrs['user_time'] = DateTime.now().toIso8601String();

      final Map<String, Object> attrs;
      if (attributes == null) {
        attrs = baseAttrs;
      } else {
        attrs = Map<String, Object>.from(baseAttrs);
        attrs.addAll(attributes);
      }

      if (kDebugMode) {
        for (final a in attrs.entries) {
          if (a.value is String) continue;
          if (a.value is int) continue;
          if (a.value is bool) continue;
          if (a.value is double) continue;
          throw Exception('DSMetrica: Unsupported attribute type ${a.key} is ${a.value.runtimeType}');
        }
      }

      unawaited(FlutterUxcam.logEventWithProperties(eventName, attrs));

      logDebug('$eventName $attrs', stackSkip: stackSkip, stackDeep: 5);

      if (kDebugMode && !_debugModeSend) {
        if (eventSendingType == EventSendingType.oncePerAppLifetime) {
          _setEventSendPerLifetime(eventName);
        }
        return;
      }

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
      if (amplitudeSend && _amplitudeKey.isNotEmpty) {
        unawaited(_amplitude!.track(BaseEvent(eventName, eventProperties: attrs)));
      }
      if (adjustSend) {
        unawaited(() async {
          final event = DSAdjustEvent(eventName);
          DSAdjust.trackEvent(event);
        } ());
      }
      await m.AppMetrica.reportEventWithMap(eventName, attrs);

      if (eventSendingType == EventSendingType.oncePerAppLifetime) {
        _setEventSendPerLifetime(eventName);
      }
    } catch (e, stack) {
      if (!_reportEventError) {
        _reportEventError = true;
        Fimber.e('$e', stacktrace: stack);
      }
    }
  }

  /// AppMetrica wrapper
  static Future<void> reportAdRevenue(AppMetricaAdRevenue revenue) async {
    if (kIsWeb || !Platform.isAndroid && !Platform.isIOS) return;
    await m.AppMetrica.reportAdRevenue(revenue);
  }

  /// AppMetrica wrapper
  static Future<void> reportUserProfile(UserProfile userProfile) async {
    if (kIsWeb || !Platform.isAndroid && !Platform.isIOS) return;
    await m.AppMetrica.reportUserProfile(userProfile);
  }

  /// AppMetrica wrapper
  static Future<void> reportError({String? message, AppMetricaErrorDescription? errorDescription}) async {
    if (kIsWeb || !Platform.isAndroid && !Platform.isIOS) return;
    await m.AppMetrica.reportError(message: message, errorDescription: errorDescription);
  }

  /// Initialize UXCam if it is allowed by RemoteConfig
  static Future<void> tryStartUXCam() async {
    if (_uxCamRunning || _uxCamInitializing) return;

    assert(DSConstants.isInitialized);

    if (kDebugMode && !_debugModeSend) return;
    if (kIsWeb || !Platform.isAndroid && !Platform.isIOS) return;

    if (DSConstants.I.isInternalVersion) {
      await startUXCam();
      return;
    }

    if (!DSRemoteConfig.I.isInitialized) {
      await DSRemoteConfig.I.waitForInit(maxWait: const Duration(seconds: 15));
    }

    var val = DSRemoteConfig.I.getUXCamPercent();
    if (val == 0) {
      await DSRemoteConfig.I.waitForFullInit(maxWait: const Duration(seconds: 20));
      val = DSRemoteConfig.I.getUXCamPercent();
      if (val == 0) return;
    }
    final sessions = DSRemoteConfig.I.getUXCamSessions();
    if (sessions != 0 && sessions < DSPrefs.I.getSessionId()) {
      return;
    }
    final minBuild = DSRemoteConfig.I.getUXCamMinBuild();
    if (minBuild > 0) {
      await DSConstants.I.waitForInit();
      final build = DSConstants.I.buildNumber;
      if (minBuild > build) return;
    }

    // if yandexId is empty (or non-valid) use simple random
    final yid = int.tryParse(yandexId.let((s) => s.length >= 2 ? s.substring(s.length - 2) : s)) ?? Random().nextInt(100);
    if ((yid % 100).toInt() < val) {
      await DSMetrica.startUXCam();
    }
  }

  /// Initialize UXCam
  static Future<void> startUXCam() async {
    if (kIsWeb || !Platform.isAndroid && !Platform.isIOS) return;

    if (_uxCamInitializing) return;
    _uxCamInitializing = true;
    try {
      assert(DSAppState.isInitialized, 'call DSAppState.preInit() before');
      reportEvent('uxcam starting');
      await FlutterUxcam.optIntoSchematicRecordings(); // Confirm that you have user permission for screen recording
      final config = FlutterUxConfig(
        userAppKey: _uxCamKey,
        enableAutomaticScreenNameTagging: false,
      );
      await FlutterUxcam.startWithConfiguration(config);
      reportEvent('uxcam started');

      DSAppState.registerStateCallback((old, state) async {
        switch (state) {
          case AppLifecycleState.resumed:
            await FlutterUxcam.allowShortBreakForAnotherApp(false);
            break;
          case AppLifecycleState.hidden:
            await FlutterUxcam.allowShortBreakForAnotherApp(true);
            break;
          default:
        }
      });

      unawaited(FlutterUxcam.setUserIdentity(yandexId));
      _uxCamRunning = true;
    } finally {
      _uxCamInitializing = false;
    }
  }

  /// Stop UXCam
  static Future<void> stopUXCam() async {
    if (kIsWeb || !Platform.isAndroid && !Platform.isIOS) return;
    await FlutterUxcam.stopSessionAndUploadData();
    _uxCamRunning = false;
  }

  /// Save attributes to send it in every [reportEvent]
  static void addPersistentAttrs(Map<String, Object> attrs) {
    _persistentAttrs.addAll(attrs);
  }

  @Deprecated('Use addAttrsHandler instead and note than `is_premium` attribute is automatically added by ds_purchase')
  /// Calculate attributes to send it in every [reportEvent]
  static void setPersistentAttrsHandler(DSMetricaAttrsCallback handler) {
    _attrsHandlerOld = handler;
  }

  /// Add [handler] to calculate attributes to send it in every [reportEvent]
  static void registerAttrsHandler(DSMetricaAttrsCallback handler) {
    _attrsHandlers.add(handler);
  }

  /// Remove [handler] which was added by [registerAttrsHandler]
  static void unregisterAttrsHandler(DSMetricaAttrsCallback handler) {
    _attrsHandlers.remove(handler);
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
  static Future<void> putErrorEnvironmentValue(String key, String? value) async {
    if (kIsWeb || !Platform.isAndroid && !Platform.isIOS) return;
    await m.AppMetrica.putErrorEnvironmentValue(key, value);
  }

  static const _oncePerAppLifetimePrefix = 'once_per_lifetime';
  static String _oncePerAppLifetimeEventKey(String eventName) => '${_oncePerAppLifetimePrefix}_$eventName';

  static bool _isEventSentLegacy(String eventName) {
    return DSPrefs.I.internal.getString(_firstEventParam) == eventName;
  }

  static bool _isEventAlreadySendPerLifetime(String eventName) {
    final key = _oncePerAppLifetimeEventKey(eventName);

    return _isEventSentLegacy(eventName) || (DSPrefs.I.internal.getBool(key) ?? false);
  }

  static void _setEventSendPerLifetime(String eventName) {
    final key = _oncePerAppLifetimeEventKey(eventName);

    DSPrefs.I.internal.setBool(key, true);
  }
}

/// Trace navigation in app
/// Based on [FlutterUxcamNavigatorObserver] of [flutter_uxcam]
class DSNavigatorObserver extends NavigatorObserver {

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);

    /// This line of code is required as there are scenarios where we have
    /// routing like in popup menu but it is not handled by routing in
    /// [onGenerateRoute].
    if (route.settings.name != null) {
      DSMetrica.reportScreenOpened(route.settings.name!);
    }
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    DSMetrica._screenNames.remove(oldRoute?.settings.name);
    DSMetrica.reportScreenOpened(newRoute?.settings.name);
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    DSMetrica._screenNames.remove(DSMetrica._normalizeScreenName(route.settings.name));
    final name = DSMetrica._screenNames.isNotEmpty
        ? DSMetrica._screenNames.last
        : '/';
    DSMetrica.reportScreenOpened(name);
    super.didPop(route, previousRoute);
  }

  @override
  void didRemove(Route route, Route? previousRoute) {
    DSMetrica._screenNames.remove(route.settings.name);
    final name = DSMetrica._screenNames.isNotEmpty
        ? DSMetrica._screenNames.last
        : '/';
    DSMetrica.reportScreenOpened(name);
    super.didRemove(route, previousRoute);
  }
}
