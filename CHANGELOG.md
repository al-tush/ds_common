## 2.7.2
- add DSMetrica.getYandexDeviceIdHash() method
- set empty userProfileID for failed or unappliable flows

## 2.7.1
- adjust updated

## 2.7.0
- added adjust send methods: global callback and partner parameter

## 2.6.1
- uxcam upadated

## 2.6.0
- ugly hotfix to pervent AppMetrica profiles splitting (set lockMetricaProfile to true to use it)

## 2.5.1
- increase startUXCam RC timeout from 5 sec to 15

## 2.5.0
- update flutter_uxcam and amplitude_flutter to support Flutter 3.29

## 2.4.1
- fix android referrer if forceFBReferrer parameter set to true (universal fb_referrer)

## 2.4.0
- add universal fb_referrer support for DSReferrer

## 2.3.9
- add DSReferrer.I.noReferrer()
- rename session_start_sec -> since_app_start_sec

## 2.3.8
- add session_start_sec attribute to every event (seconds since session start)
- add DSConstants.startTime property

## 2.3.7
- fix false positive assert

## 2.3.6
- add uxcam_min_build parameter

## 2.3.5
- add events sending support for Adjust
- fix DSReferrer for iOS if iosRegion value is empty
- update adjust_sdk to 5.1.0
- update flutter_uxcam to 2.5.8

## 2.3.4
- add ChangeNotifier implementation to DSRemoteConfig

## 2.3.3
- remove UserX support

## 2.3.2
- fix UserX bug: no suitable method found for init(String)

## 2.3.1
- add flag DSCrashReportingTree.sendErrorsToAmpltude (false by default)

## 2.3.0
- temporary restore UserX support (UserX version updated)

## 2.2.1
- DSAppState simplification

## 2.2.0
- add FlutterUxcam.allowShortBreakForAnotherApp support longer sessions recording by UXCam
- fix useless warning

## 2.1.1
- add methods DSMetrica.getAmplitudeDeviceId() and DSMetrica.getAmplitudeUserId()

## 2.1.0
- add Amplitude logging

## 2.0.7
- add AppOpen ad data exchange support between ds_ads and ds_purchase

## 2.0.6
- fix iOS exception on setUserProfile call
- change AppMetrica dispatchPeriodSeconds to default period

## 2.0.5
- add uxcam_percent and uxcam_sessions RemoteConfig params. Old values (userx_percent and userx_sessions) ​​are used only if uxcam_percent and uxcam_sessions are not specified
- synchronize AppMetrica user profile in Android native part

## 2.0.4
- change AppMetrica dispatchPeriodSeconds from 90 (default) seconds to 5
- maybe fix: do not send sessions if kDebugMode is true

## 2.0.3
- add deferredDeeplinkCallback and launchLinkMeEnabled Adjust parameters (#5)

## 2.0.2
- remove all chars since ? and # (path and anchor parts) from screen names

## 2.0.1
- add limited experimental support to trace screens by [DSNavigatorObserver]

## 2.0.0
BREAKING CHANGES:
- replace UserX to UXCam sessions recording library
- remove deprecated and unused code

OTHER CHANGES:
- update shared_preferences library https://github.com/advisories/GHSA-3hpf-ff72-j67p
- fix double quotes hints

## 1.1.0
- integrate Fimber with attributes extensions into ds_common library #4 https://app.asana.com/0/1208203354836323/1208312050177353/f

## 1.0.9
- add unsupported types check by DSMetrica in kDebugMode

## 1.0.8
- improve userx starting (yandexId parsing changed)

## 1.0.7
- fix userx_percent usage https://app.asana.com/0/1208203354836323/1208334659694747/f

## 1.0.6
- sync Android native to Flutter code (package com.yandex.metrica replaced to io.appmetrica.analytics)

## 1.0.5
- Sentry removed (temporary)

## 1.0.4
- extend Android native DSMetrica functionality
- minimum Flutter version is 3.24

## 1.0.3
- fix fetchInstallReferrer call

## 1.0.2
- add Android native DSMetrica and DSTimber classes (unifying native code)

## 1.0.1
- remove device_info dependency (use DSMetrica.getDeviceId() to access to legacy device id)
- fix Flutter 3.24 release build

## 1.0.0
BREAKING CHANGES: 
- update to AppMetrica 3.1 (fix iOS ITMS-91107 https://t.me/appmetrica_chat/50255)
- update dependencies

## 0.1.39
- change DSReferrer.isKnownReferrer() conditions
- add DSMetrica.registerAttrsHandler instead of setPersistentAttrsHandler
- move DSReferrer.getMetricaEventAttrs() to internal DSMetrica implementation

## 0.1.38
- add default values to DSRemoteConfig

## 0.1.37
- add DSReferrer class to install referrer detection
- automatically set '_d' postfix in DSRemoteConfig

## 0.1.36
- changed Adjust.adid initialization
- add Adjust attribution to AppMetrica

## 0.1.35
- update appmetrica_plugin (appmetrica 1.x not works with new projects; need to recheck KSCrash dependency build error: demangle.h:19:10: fatal error: 'absl/base/config.h' file not found)
- update firebase dependencies

## 0.1.34
- adjust_sdk updated to 5.0.1+

## 0.1.33
- add optional property launchDeferredDeeplink to DSAdust.init method
- add catch to Firebase.initializeApp

## 0.1.32
- add user_id_metrica tag to Sentry logging

## 0.1.31
- fix DSLimitedBlock and DSLimitedText bugs

## 0.1.30
- fix DSMetrica UserProfileID initialization

## 0.1.29
- revert "update appmetrica_plugin" to 1.x (fix KSCrash dependency build error: demangle.h:19:10: fatal error: 'absl/base/config.h' file not found)
- add Flutter 3.22 support

## 0.1.28
- try to fix DSMetrica.yandexId for first run

## 0.1.27
- declare web support 

## 0.1.26
- add device_info versions

## 0.1.25
- Add DSMetricaUserIdType calls for ds_purchase support
- Add recall for Adjust.getAdid()
- Add method DSAdjust.addAfterInitCallback

## 0.1.24
- fix breaking change issue

## 0.1.23
- add Sentry support
- add web logging support (by Sentry)
- appmetrica_plugin updated

## 0.1.22
- add EventSendingType oncePerAppLifetime to report method

## 0.1.21
- expand Adjust methods list

## 0.1.20
- add DSAdjust (Adjust library integration)
- minor code quality improvements

## 0.1.19
- fix web platform checks
- add DSConstants.isInternalVersionOpt for uninitialized access

## 0.1.18
- fix DSLimitedText exception

## 0.1.17
- add AppMetrica.setUserProfileID
- add DSLimitedBlock.calcSize method (experimental)
- add exceptions logging for yandexId initialization

## 0.1.16
- allow to exclude duplicated and non-informative exceptions from logging in DSCrashReportingTree

## 0.1.15
- add DSLimitedBlock widget
- add FirebaseAnalytics optional events (fbSend parameter of DSMetrica.reportEvent)
- add AppMetrica putErrorEnvironmentValue wrapper
- UserX updated

## 0.1.14
- add DSLimitedText widget

## 0.1.13
- add method internalInit to DSConstants

## 0.1.12
- add web support
- add "let" extension (like in Kotlin)

## 0.1.11
- fixed first start with no internet connection

## 0.1.10
- add user_time attribute to reportEvent

## 0.1.9
- improve stack logging for unawaitedCatch

## 0.1.8
- update UserX to 1.1.0 (previous versions of ds_common are incompatible with UserX 1.1.0)

## 0.1.7
- add optional debug mode sending to DSMetrica
- add dynamic PersistentAttrs (DSMetrica.setPersistentAttrsHandler)

## 0.1.6
- build fixed

## 0.1.5
- add reportScreenOpened method
- update AppMetrica plugin min version
- add some documentation

## 0.1.4
- DSPrefs now is a ChangeNotifier

## 0.1.3
- disable text highlighting for iOS logging

## 0.1.2
- dependencies updated

## 0.1.1
- DSMetrica initialization fixed

## 0.1.0
- implements Metrica, Firebase Crashlytics, RemoteConfig, Fimber and Shared Preferences support