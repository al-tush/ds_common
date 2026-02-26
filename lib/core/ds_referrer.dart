import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:ds_common/core/fimber/ds_fimber_base.dart';
import 'package:firebase_app_installations/firebase_app_installations.dart';
import 'package:http/http.dart' as http;

import 'contracts/ds_contracts.dart';
import 'ds_internal.dart';

typedef DSReferrerReportEvent = void Function(String name, {Map<String, Object>? attributes, Map<String, String>? fbAttributes});

/// [DSReferrer] helps to separate organic and partner traffic.
/// Create via constructor; pass [IDSPrefs], [IDSConstants], optional [IDSRemoteConfig] and [reportEvent].
class DSReferrer implements IDSReferrer {
  DSReferrer({
    required IDSPrefs prefs,
    required IDSConstants constants,
    IDSRemoteConfig? remoteConfig,
    DSReferrerReportEvent? reportEvent,
  })  : _prefs = prefs,
        _constants = constants,
        _remoteConfig = remoteConfig,
        _reportEvent = reportEvent ?? _noopReport;

  static void _noopReport(String name, {Map<String, Object>? attributes, Map<String, String>? fbAttributes}) {}

  final IDSPrefs _prefs;
  final IDSConstants _constants;
  final IDSRemoteConfig? _remoteConfig;
  final DSReferrerReportEvent _reportEvent;

  static const _isSentKey = 'installReferrer.isSaved';
  static const _referrerKey = 'installReferrer.referrer';

  var _isInitialized = false;
  @override
  bool get isInitialized => _isInitialized;

  final _changedCallbacks = <DSReferrerCallback>{};

  String? _faultClientIp;
  String? get faultClientIp => _faultClientIp;

  void noReferrer() {
    assert(!_isInitialized, 'Duplicate initialization');
    _isInitialized = true;
  }

  Future<void> trySave({
    @Deprecated('use fbRegion')
    final String iosRegion = '',
    final String fbV1Region = '',
    final String fbV2Url = '',
    final bool forceFBReferrer = false,
    Map<String, Object> Function(Map<String, String> fields)? installParamsExtra,
  }) async {
    assert(!_isInitialized, 'Duplicate trySave call not needed');
    var params = 0;
    if (iosRegion.isNotEmpty) params++;
    if (fbV1Region.isNotEmpty) params++;
    if (fbV2Url.isNotEmpty) params++;
    assert(params <= 1, 'Use fbV1Region or fbV2Url parameter only');
    final region = fbV1Region.isEmpty ? iosRegion : fbV1Region;
    _isInitialized = true;

    try {
      var referrer = _prefs.internal.getString(_referrerKey) ?? '';
      try {
        if (referrer.isEmpty) {
          final res = await Future.wait<String>([
            if (Platform.isIOS || forceFBReferrer)
              () async {
                assert(region.isNotEmpty || fbV2Url.isNotEmpty, 'fbRegion should be assigned');
                try {
                  final startTime = DateTime.timestamp();
                  final int respCode;
                  if (fbV2Url.isEmpty) {
                    final r = await FirebaseFunctions.instanceFor(region: region).httpsCallable('get_referrer').call<String>();
                    respCode = 200;
                    referrer = r.data;
                  } else {
                    final r = await http.get(Uri.parse(fbV2Url));
                    respCode = r.statusCode;
                    if (respCode == 200) referrer = r.body;
                    if (respCode == 404) _faultClientIp = r.body;
                  }
                  final loadTime = DateTime.timestamp().difference(startTime);
                  _reportEvent('fb_referrer', attributes: {
                    'value': referrer,
                    'resp_code': respCode,
                    if (_faultClientIp != null) 'fault_client_ip': _faultClientIp.toString(),
                    'referrer_load_seconds': loadTime.inSeconds,
                    'referrer_load_milliseconds': loadTime.inMilliseconds,
                  });
                  final p = referrer.indexOf('?');
                  if (p >= 0) referrer = referrer.substring(p + 1);
                  return referrer;
                } catch (e, stack) {
                  Fimber.e('fb_referrer $e', stacktrace: stack);
                  return 'err_fb';
                }
              }(),
            if (Platform.isAndroid)
              () async {
                try {
                  final startTime = DateTime.timestamp();
                  final ref = await DSInternal.platform.invokeMethod('fetchInstallReferrer') as String;
                  final loadTime = DateTime.timestamp().difference(startTime);
                  _reportEvent('android_referrer', attributes: {
                    'value': referrer,
                    'referrer_load_seconds': loadTime.inSeconds,
                    'referrer_load_milliseconds': loadTime.inMilliseconds,
                  });
                  return ref;
                } catch (e, stack) {
                  Fimber.e('android_referrer $e', stacktrace: stack);
                  return 'err_android';
                }
              }(),
          ]);
          referrer = res.join('&');
          _prefs.internal.setString(_referrerKey, referrer);
        }

        Fimber.i('ds_referrer=$referrer');

        if (!_constants.isInternalVersion && _remoteConfig != null) {
          if (isKnownReferrer()) {
            _remoteConfig.setPostfix('_r');
          } else {
            _remoteConfig.setPostfix('_e');
          }
        }

        if (_prefs.internal.getBool(_isSentKey) == true || !Platform.isAndroid) return;
        if (referrer == '') return;
        final data = Uri.splitQueryString(referrer);
        final utmSource = data['utm_source'];
        if (utmSource == null) return;

        final fid = await FirebaseInstallations.instance.getId();
        unawaited(FirebaseFirestore.instance
            .collection('installs_full_referrer')
            .add({
          'bundle': _constants.packageInfo.packageName,
          'referrer': referrer,
          'referrer_len': referrer.length,
          'utm_source': utmSource,
          'firebase_id': fid,
          'timestamp': FieldValue.serverTimestamp(),
        }).then((_) {
          _prefs.internal.setBool(_isSentKey, true);
        }).timeout(const Duration(minutes: 1)));

        final isValidFb = utmSource.contains('apps.facebook.com') || utmSource.contains('apps.instagram.com');
        final fbAttrs = <String, String>{
          'gclid': data['gclid'] ?? '',
          'ad_imp': data['adimp'] ?? '',
          'utm_source': utmSource,
          'utm_content': data['utm_content'] ?? '',
          'is_valid_fb_flow': isValidFb.toString(),
          'campaign': data['utm_campaign'] ?? 'unknown',
          'adjust_external_click_id': adjustExternalClickId,
        };
        if (installParamsExtra != null) {
          for (final e in installParamsExtra(data).entries) {
            fbAttrs[e.key] = e.value.toString();
          }
        }
        _reportEvent('install_params', fbAttributes: fbAttrs);
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

  @override
  void registerChangedCallback(DSReferrerCallback callback) {
    _changedCallbacks.add(callback);
    if (_isInitialized) callback(getReferrerFields());
  }

  @override
  void unregisterAttributionCallback(DSReferrerCallback callback) {
    _changedCallbacks.remove(callback);
  }

  var _getFieldsError = false;

  @override
  Map<String, String> getReferrerFields() {
    try {
      final referrer = _prefs.internal.getString(_referrerKey) ?? '';
      return Uri.splitQueryString(referrer);
    } catch (e, stack) {
      if (!_getFieldsError) {
        _getFieldsError = true;
        Fimber.e('$e', stacktrace: stack);
      }
      return {};
    }
  }

  static final _ourReferrerPattern = RegExp(r'^\w+_\d+_\d+');

  bool isKnownReferrer() {
    try {
      final data = getReferrerFields();
      if (Platform.isIOS) return data.containsKey('partner');
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

  bool isValidUtm() {
    final data = getReferrerFields();
    final utmSource = data['utm_source'];
    return utmSource != null && _ourReferrerPattern.hasMatch(utmSource);
  }

  String get adjustExternalClickId => getReferrerFields()['adjust_external_click_id'] ?? '';
}
