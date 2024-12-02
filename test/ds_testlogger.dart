import 'package:ds_common/core/fimber/ds_fimber_base.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tuple/tuple.dart';

class DSTestLogger extends DebugTree {
  final _log = <Tuple6<String, String, String?, dynamic, StackTrace?, Map<String, dynamic>?>>[];

  @override
  void log(
    String level,
    String message, {
    String? tag,
    dynamic ex,
    StackTrace? stacktrace,
    Map<String, dynamic>? attributes,
  }) {
    _log.add(Tuple6(level, message, tag, ex, stacktrace, attributes));
  }

  expectWarning(String message) {
    final item = _log.removeAt(0);
    expect(item.item1, 'W');
    expect(item.item2, message);
  }

  expectError(String message) {
    final item = _log.removeAt(0);
    expect(item.item1, 'E');
    expect(item.item2, message);
  }

  expectEnd() {
    expect(_log.isEmpty ? 'Log is empty' : 'Log is not empty (${_log.length})', 'Log is empty');
  }
}
