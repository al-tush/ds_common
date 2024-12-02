import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:ds_common/core/fimber/ds_fimber_base.dart';
import 'package:firebase_app_installations/firebase_app_installations.dart';

import 'ds_constants.dart';
import 'ds_internal.dart';
import 'ds_metrica.dart';
import 'ds_prefs.dart';
import 'ds_remote_config.dart';

typedef DSReferrerCallback = void Function(Map<String, String> fields);

/// [DSReferrer] helps to separate organic and partner traffic.
/// Also it send referrer data to Firebase collection installs_full_referrer and DSMetrica statistics.
class DSReferrer {
  static var _isInitialized = false;
  static bool get isInitialized => _isInitialized;

  DSReferrer._();

  static final I = DSReferrer._();

  // Names retained for backward compatibility
  final _isSentKey = 'installReferrer.isSaved';
  final _referrerKey = 'installReferrer.referrer';

  final _changedCallbacks = <DSReferrerCallback>{};

  /// Call this method at the start of app
  Future<void> trySave({
    String iosRegion = '',
    Map<String, Object> Function(Map<String, String> fields)? installParamsExtra,
  }) async {
    assert(!_isInitialized, 'Duplicate trySave call not needed');
    _isInitialized = true;

    try {
      final prefs = DSPrefs.I.internal;

      var referrer = prefs.getString(_referrerKey) ?? '';
      try {
        if (referrer.isEmpty && Platform.isAndroid) {
          // Get Android referrer
          try {
            referrer = await DSInternal.platform.invokeMethod('fetchInstallReferrer');
          } catch (e, stack) {
            Fimber.e('$e', stacktrace: stack);
            return;
          }
          if (referrer == 'null') return;
          await prefs.setString(_referrerKey, referrer);
        }

        if (referrer.isEmpty && Platform.isIOS) {
          assert(iosRegion.isNotEmpty, 'iosRegion should be assigned (get_referrer cloud function must be deployed)');
          // Get iOS referrer
          var referrer = 'null';
          try {
            final startTime = DateTime.timestamp();
            final res = await FirebaseFunctions.instanceFor(region: iosRegion).httpsCallable('get_referrer').call<
                String>();
            referrer = res.data;
            final loadTime = DateTime.timestamp().difference(startTime);
            DSMetrica.reportEvent('ios_referrer', attributes: {
              'value': referrer,
              'referrer_load_seconds': loadTime.inSeconds,
              'referrer_load_milliseconds': loadTime.inMilliseconds,
            });
            final p = referrer.indexOf('?');
            if (p >= 0) {
              referrer = referrer.substring(p + 1);
            }
          } catch (e, stack) {
            Fimber.e('ios_referrer $e', stacktrace: stack);
            referrer = 'err';
          }
          await prefs.setString(_referrerKey, referrer);
        }

        Fimber.i('ds_referrer=$referrer');

        if (!DSConstants.I.isInternalVersion) {
          if (isKnownReferrer()) {
            DSRemoteConfig.I.setPostfix('_r');
          } else {
            DSRemoteConfig.I.setPostfix('_e');
          }
        }

        // Send installs_full_referrer once. Only for Android platform
        if (prefs.getBool(_isSentKey) == true || !Platform.isAndroid) return;

        if (referrer == '') return;
        final data = Uri.splitQueryString(referrer);
        final utmSource = data['utm_source'];
        if (utmSource == null) return;

        final fid = await FirebaseInstallations.instance.getId();

        unawaited(FirebaseFirestore.instance.collection('installs_full_referrer').add({
          'bundle': DSConstants.I.packageInfo.packageName,
          'referrer': referrer,
          'referrer_len': referrer.length,
          'utm_source': utmSource,
          'firebase_id': fid,
          'timestamp': FieldValue.serverTimestamp(),
        }).then((value) {
          prefs.setBool(_isSentKey, true);
        }).timeout(const Duration(minutes: 1)));

        {
          final String utmSource = data['utm_source'] ?? '';
          final isValidFb = utmSource.contains('apps.facebook.com') || utmSource.contains('apps.instagram.com');

          DSMetrica.reportEvent('install_params', fbSend: true, fbAttributes: {
            'gclid': data['gclid'] ?? '',
            'ad_imp': data['adimp'] ?? '',
            'utm_source': utmSource,
            'utm_content': data['utm_content'] ?? '',
            'is_valid_fb_flow': isValidFb,
            'campaign': data['utm_campaign'] ?? 'unknown',
            'adjust_external_click_id': adjustExternalClickId,
            if (installParamsExtra != null)
              ...installParamsExtra(data)
          });
        }
      } catch (e, stack) {
        Fimber.e('$e: (referrer: $referrer)', stacktrace: stack);
      }
    } finally {
      final data = getReferrerFields();
      for (final callback in _changedCallbacks) {
        callback(data);
      }
    }
  }

  /// Add handler for any referrer change
  void registerChangedCallback(DSReferrerCallback callback) {
    _changedCallbacks.add(callback);
    if (_isInitialized) {
      callback(I.getReferrerFields());
    }
  }

  /// Remove handler for Adjust -> attributionCallback
  void unregisterAttributionCallback(DSReferrerCallback callback) {
    _changedCallbacks.remove(callback);
  }

  var _getFieldsError = false;

  /// Get stored referrer fields
  Map<String, String> getReferrerFields() {
    var referrer = 'notInitialized';
    try {
      referrer = DSPrefs.I.internal.getString(_referrerKey) ?? '';
      return Uri.splitQueryString(referrer);
    } catch (e, stack) {
      if (!_getFieldsError) {
        _getFieldsError = true;
        Fimber.e('$e: (referrer: $referrer)', stacktrace: stack);
      }
      return {};
    }
  }

  final _ourReferrerPattern = RegExp('^\\w+_\\d+_\\d+');

  /// Is current install from known partner
  bool isKnownReferrer() {
    try {
      final data = getReferrerFields();
      if (Platform.isIOS) {
        if (data.containsKey('partner')) return true;
        return false;
      }

      if ((data['gclid'] ?? '').isNotEmpty) return true;
      final utmSource = data['utm_source'] ?? '';
      if (_ourReferrerPattern.hasMatch(utmSource)) return true;
      if (utmSource.contains('apps.facebook.com') || utmSource.contains('apps.instagram.com')) return true;
      if (adjustExternalClickId.isNotEmpty) return true;

      return false;
    } catch (e, stack) {
      Fimber.e('$e', stacktrace: stack);
      return false;
    }
  }

  /// Is current install  has valid utm (installed from partner)
  bool isValidUtm() {
    final data = getReferrerFields();
    final utmSource = data['utm_source'];
    if (utmSource == null) return false;
    return _ourReferrerPattern.hasMatch(utmSource);
  }

  String get adjustExternalClickId => getReferrerFields()['adjust_external_click_id'] ?? '';
}
