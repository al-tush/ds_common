import 'package:ds_common/core/ds_logging.dart';
import 'package:ds_fimber/ds_fimber.dart';

import 'package:flutter_test/flutter_test.dart';

import 'ds_testlogger.dart';

void main() {
  test('test logger 1', () async {
    final log = DSTestLogger();
    Fimber.plantTree(log);
    Fimber.w('warning1');
    Fimber.e('err1');
    Fimber.e('err2');
    log.expectWarning('warning1');
    log.expectError('err1');
    log.expectError('err2');
    log.expectEnd();
  });

  test('test logger 2', () async {
    final log = DSTestLogger();
    Fimber.plantTree(log);
    Fimber.w('warning1');
    Object? err;
    try {
      log.expectEnd();
    } catch (e) {
      err = e;
    }
    expect(err != null, true);
  });

  test('catch as warning', () async {
    final log = DSTestLogger();
    Fimber.plantTree(log);
    catchAsWarning(() {
      throw 1;
    });
    log.expectWarning('1');
    log.expectEnd();
  });

  test('catch as warning 1', () async {
    final log = DSTestLogger();
    Fimber.plantTree(log);
    await catchAsWarningAsync(() async {
      throw 'Err';
    });
    log.expectWarning('Err');
    log.expectEnd();
  });

  test('catch as warning 2', () async {
    final log = DSTestLogger();
    Fimber.plantTree(log);
    await catchAsWarningAsync(() async {
      throw Exception('Err');
    });
    log.expectWarning('Exception: Err');
    log.expectEnd();
  });

}
