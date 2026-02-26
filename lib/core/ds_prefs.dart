
import 'package:shared_preferences/shared_preferences.dart';

import 'contracts/ds_contracts.dart';

/// Реализация [IDSPrefs]. Приложение создаёт экземпляр, передавая [SharedPreferences].
/// Реактивность (ChangeNotifier) при необходимости реализуется в приложении (например, Riverpod).
class DSPrefs implements IDSPrefs {
  DSPrefs(this._prefs);

  final SharedPreferences _prefs;

  @override
  SharedPreferences get internal => _prefs;

  void notifyAsync() {
    // Hook for app to observe changes if needed (e.g. Riverpod invalidation).
    // No-op by default; app can subclass and override or use a callback.
  }

  @override
  int getSessionId() => _prefs.getInt('app_session_id') ?? 0;
  @override
  void setSessionId(int value) {
    _prefs.setInt('app_session_id', value);
    notifyAsync();
  }

  @override
  DateTime getAppLastUsed() =>
      DateTime.fromMillisecondsSinceEpoch((_prefs.getInt('app_last_used') ?? 0) * 1000);
  @override
  void setAppLastUsed(DateTime value) {
    _prefs.setInt('app_last_used', value.millisecondsSinceEpoch ~/ 1000);
    notifyAsync();
  }

  @override
  bool isYandexDeviceIdSent() => _prefs.getBool('yandexDeviceIdSent') ?? false;
  @override
  void setYandexDeviceIdSent(bool value) {
    _prefs.setBool('yandexDeviceIdSent', value);
    notifyAsync();
  }
}
