import 'dart:async';
import 'dart:io';

import 'package:adjust_sdk/adjust.dart';
import 'package:adjust_sdk/adjust_ad_revenue.dart';
import 'package:adjust_sdk/adjust_attribution.dart';
import 'package:adjust_sdk/adjust_config.dart';
import 'package:adjust_sdk/adjust_event.dart';
import 'package:ds_common/core/fimber/ds_fimber_base.dart';
import 'package:flutter/foundation.dart';

import 'ds_constants.dart';
import 'ds_metrica.dart';
import 'ds_primitives.dart';

typedef DSAdjustAttribution = AdjustAttribution;
typedef DSAttributionCallback = void Function(DSAdjustAttribution data);
typedef DSAdjustEvent = AdjustEvent;

abstract class DSAdjust {
  static var _isInitialized = false;
  static bool get isInitialized => _isInitialized;
  static String? _adId;

  static final _attributionCallbacks = <DSAttributionCallback>{};
  static DSAdjustAttribution? _lastAttribution;

  static final _initCallbacks = <void Function()>{};

  /// Initialize DSAdjust
  /// [adjustKey] - API key of Adjust
  static Future<void> init({
    required String adjustKey,
    bool? launchDeferredDeeplink,
    bool? launchLinkMeEnabled,
    DeferredDeeplinkCallback? deferredDeeplinkCallback,
  }) async {
    if (_isInitialized) {
      Fimber.e('DSAdjust is already initialised', stacktrace: StackTrace.current);
      return;
    }

    await DSConstants.I.waitForInit();
    final config = AdjustConfig(
        adjustKey, DSConstants.I.isInternalVersion ? AdjustEnvironment.sandbox : AdjustEnvironment.production);
    config.logLevel = AdjustLogLevel.verbose;
    config.attributionCallback = _setAdjustAttribution;
    config.isDeferredDeeplinkOpeningEnabled = launchDeferredDeeplink;
    config.deferredDeeplinkCallback = deferredDeeplinkCallback;
    config.isLinkMeEnabled = launchLinkMeEnabled;
    Adjust.initSdk(config);

    _isInitialized = true;

    // init adid
    getAdid();

    for (final callback in _initCallbacks) {
      callback();
    }
  }

  static Future<String?> getLastDeeplink() async => await Adjust.getLastDeeplink();

  /// Add callback to be called after initialization
  static addAfterInitCallback(void Function() callback) {
    _initCallbacks.add(callback);
  }

  /// Just Adjust [trackAdRevenueNew] call
  static void trackAdRevenueNew({
    required double value,
    required String currencyCode,
    required String adRevenueNetwork,
    required String adRevenueUnit,
  }) {
    final adRevenue = AdjustAdRevenue('admob_sdk');
    adRevenue.setRevenue(value, currencyCode);
    adRevenue.adRevenueNetwork = adRevenueNetwork;
    adRevenue.adRevenueUnit = adRevenueUnit;
    Adjust.trackAdRevenue(adRevenue);
  }

  /// Result described in https://github.com/adjust/flutter_sdk/blob/master/README.md#af-att-framework
  static Future<num> requestATT() async {
    if (kIsWeb || !Platform.isIOS) return -1;
    final time = Stopwatch()..start();
    final res = await Adjust.requestAppTrackingAuthorization();
    time.stop();
    DSMetrica.reportEvent('AppTrackingTransparency', attributes: {
      'att_result': '$res',
      'att_time_delta_sec': time.elapsed.inSeconds,
      'att_time_delta_ms': time.elapsedMilliseconds,
    });
    return res;
  }

  static Future<void> Function()? _adidUpdater;

  static String? getAdid() {
    if (_adidUpdater == null) {
      // Если никто не запрашивал получение Adid, то дожидаюсь получения от Adjust значения
      var delay = const Duration(milliseconds: 100);
      _adidUpdater = () async {
        while (_adId == null) {
          _adId = await Adjust.getAdid();
          if (_lastAttribution != null) {
            _setAdjustAttribution(_lastAttribution!);
          }
          if (_adId != null) break;
          delay = delay * 2;
          await Future.delayed(delay);
        }
      };
      unawaited(_adidUpdater!());
    }
    // Возвращаю сейчас то, что есть (null или реальное)
    return _adId;
  }

  /// Result described in https://github.com/adjust/flutter_sdk/blob/master/README.md#af-att-framework
  static Future<int> getATTStatus() async {
    return Adjust.getAppTrackingAuthorizationStatus();
  }

  /// Add handler for Adjust -> attributionCallback
  static void registerAttributionCallback(DSAttributionCallback callback) {
    _attributionCallbacks.add(callback);
    _lastAttribution?.let((it) => callback(it));
  }

  /// Remove handler for Adjust -> attributionCallback
  static void unregisterAttributionCallback(DSAttributionCallback callback) {
    _attributionCallbacks.remove(callback);
  }

  static void trackEvent(DSAdjustEvent event) {
    Adjust.trackEvent(event);
  }

  static void _setAdjustAttribution(AdjustAttribution data) {
    _lastAttribution = null;
    for (final callback in _attributionCallbacks) {
      callback(data);
    }
    _lastAttribution = data;
  }

  static void sendGlobalCallbackParameter(String key, String value) {
    Adjust.addGlobalCallbackParameter(key, value);
  }

  static void sendGlobalPartnerParameter(String key, String value) {
    Adjust.addGlobalPartnerParameter(key, value);
  }
}
