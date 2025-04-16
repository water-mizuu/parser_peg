// ignore_for_file: type=lint, body_might_complete_normally_nullable, unused_local_variable, inference_failure_on_function_return_type, unused_import, duplicate_ignore, unused_element, collection_methods_unrelated_type, unused_element, use_setters_to_change_properties

// imports
// ignore_for_file: collection_methods_unrelated_type, unused_element, use_setters_to_change_properties

import "dart:collection";
import "dart:math" as math;
// base.dart
abstract base class _PegParser<R extends Object> {
  _PegParser();

  _Memo? _recall<T extends Object>(_Rule<T> r, int p, int i) {
    _Memo? m = _memo[(r, p, i)];
    _Head<void>? h = _heads[(p, i)];

    if (h == null) {
      return m;
    }

    if (m == null && h.rule != r && !h.involvedSet.contains(r)) {
      return _Memo(null, p);
    }

    if (m != null && h.evalSet.contains(r)) {
      h.evalSet.remove(r);

      T? ans = r.call();
      m.ans = ans;
      m.pos = this.pos;
    }

    return m;
  }

  T? _growLr<T extends Object>(_Rule<T> r, int p, int i, _Memo m, _Head<T> h) {
    _heads[(p, i)] = h;
    for (;;) {
      this.pos = p;

      h.evalSet.addAll(h.involvedSet);
      T? ans = r.call();
      if (ans == null || this.pos <= m.pos) {
        break;
      }

      m.ans = ans;
      m.pos = pos;
    }

    _heads.remove((p, i));
    this.pos = m.pos;

    return m.ans as T?;
  }

  T? _lrAnswer<T extends Object>(_Rule<T> r, int p, int i, _Memo m) {
    _Lr<T> lr = m.ans! as _Lr<T>;
    _Head<T> h = lr.head!;
    T? seed = lr.seed;

    if (h.rule != r) {
      return seed;
    } else {
      m.ans = lr.seed;

      if (m.ans == null) {
        return null;
      } else {
        return _growLr(r, p, i, m, h);
      }
    }
  }

  T? apply<T extends Object>(_Rule<T> r, [int? p, int? i]) {
    p ??= this.pos;
    i ??= this.indent.last;

    _Memo? m = _recall(r, p, i);
    if (m == null) {
      _Lr<T> lr = _Lr<T>(seed: null, rule: r, head: null);

      _lrStack.addFirst(lr);
      m = _Memo(lr, p);

      _memo[(r, p, i)] = m;

      T? ans = r.call();
      _lrStack.removeFirst();
      m.pos = this.pos;

      if (lr.head != null) {
        lr.seed = ans;
        return _lrAnswer(r, p, i, m);
      } else {
        m.ans = ans;
        return ans;
      }
    } else {
      this.pos = m.pos;

      if (m.ans case _Lr<void> lr) {
        _setupLr(r, lr);

        return lr.seed as T?;
      } else {
        return m.ans as T?;
      }
    }
  }

  void _setupLr<T extends Object>(_Rule<T> r, _Lr<void> l) {
    l.head ??= _Head<T>(rule: r, evalSet: <_Rule<void>>{}, involvedSet: <_Rule<void>>{});

    for (_Lr<void> lr in _lrStack.takeWhile((lr) => lr.head != l.head)) {
      l.head!.involvedSet.add(lr.rule);
      lr.head = l.head;
    }
  }

  void consumeWhitespace({bool includeNewlines = false}) {
    var regex = includeNewlines ? whitespaceRegExp.$1 : whitespaceRegExp.$2;
    if (regex.matchAsPrefix(buffer, pos) case Match(:int end)) {
      this.pos = end;
    }
  }

  // ignore: body_might_complete_normally_nullable
  String? matchRange(Set<(int, int)> ranges, {bool isReported = true}) {
    if (pos < buffer.length) {
      int c = buffer.codeUnitAt(pos);
      for (var (int start, int end) in ranges) {
        if (start <= c && c <= end) {
          return buffer[pos++];
        }
      }
    }

    if (isReported) {
      (failures[pos] ??= <String>{}).addAll(<String>[
        for (var (int start, int end) in ranges)
          "${String.fromCharCode(start)}-${String.fromCharCode(end)}",
      ]);
    }
  }

  // ignore: body_might_complete_normally_nullable
  String? matchPattern(Pattern pattern, {bool isReported = true}) {
    if (_patternMemo[(pattern, this.pos, this.indent.last)] case (int pos, String value)) {
      this.pos = pos;
      return value;
    }

    if (pattern.matchAsPrefix(this.buffer, this.pos) case Match(:int start, :int end)) {
      String result = buffer.substring(start, end);
      _patternMemo[(pattern, start, this.indent.last)] = (end, result);
      this.pos = end;

      return result;
    }

    if (isReported) {
      switch (pattern) {
        case RegExp(:String pattern):
          (failures[pos] ??= <String>{}).add(pattern);
        case String pattern:
          (failures[pos] ??= <String>{}).add(pattern);
      }
    }
  }

  final Map<int, (int pos, int indent)> _indentationMemo = {};
  (int pos, int indent) _getCurrentIndentation() {
    if (_indentationMemo[pos] case var mark?) {
      return mark;
    }

    var index = pos;
    if (index >= buffer.length) {
      return (pos, 0);
    }

    var affected = {index};
    while (index >= 0 && buffer[index] != "\n") {
      index--;
    }

    /// By here, we are either at the start of a line,
    ///   or we are at the start of the file.
    int indent = 0;
    while (index < buffer.length && buffer[index].trimLeft().isEmpty) {
      indent++;
      index++;
    }

    var result = (index, indent - 1);
    for (var p in affected) {
      _indentationMemo[p] = result;
    }

    return result;
  }

  int? _indent() {
    var (pos, currentIndentation) = _getCurrentIndentation();

    if (currentIndentation > this.indent.last) {
      this.indent.add(currentIndentation);
      this.pos = pos;
      return currentIndentation;
    }
    return null;
  }

  int? _dedent() {
    if (this.pos >= buffer.length) {
      return 0;
    }

    var (pos, currentIndentation) = _getCurrentIndentation();

    if (currentIndentation < this.indent.last) {
      this.indent.removeLast();
      this.pos = pos;
      return currentIndentation;
    }
    return null;
  }

  int? _samedent() {
    var (pos, currentIndentation) = _getCurrentIndentation();

    if (currentIndentation == this.indent.last) {
      this.pos = pos;
      return currentIndentation;
    }
    return null;
  }

  (int, List<int>) _mark() {
    return (this.pos, [...this.indent]);
  }

  void _recover((int, List<int>) mark) {
    if (mark case (var pos, var indent)) {
      this.pos = pos;

      this.indent.clear();
      this.indent.addAll(indent);
    }
  }

  void reset() {
    this.pos = 0;
    this.failures.clear();
    this._heads.clear();
    this._lrStack.clear();
    this._memo.clear();
    this._patternMemo.clear();
  }

  static (int column, int row) _columnRow(String buffer, int pos) {
    List<String> linesToIndex = "$buffer ".substring(0, pos + 1).split("\n");
    return (linesToIndex.length, linesToIndex.last.length);
  }

  String reportFailures() {
    var MapEntry<int, Set<String>>(key: int pos, value: Set<String> messages) =
        failures.entries.last;
    var (int column, int row) = _columnRow(buffer, pos);

    return "($column:$row): Expected the following: $messages";
  }

  static final (RegExp, RegExp) whitespaceRegExp = (RegExp(r"\s"), RegExp(r"(?!\n)\s"));

  final Map<int, Set<String>> failures = <int, Set<String>>{};
  final Map<(int, int), _Head<void>> _heads = <(int, int), _Head<void>>{};
  final Queue<_Lr<void>> _lrStack = DoubleLinkedQueue<_Lr<void>>();
  final Map<(_Rule<void>, int, int), _Memo> _memo = <(_Rule<void>, int, int), _Memo>{};
  final Map<(Pattern, int, int), (int, String)> _patternMemo =
      <(Pattern, int, int), (int, String)>{};

  late String buffer;
  int pos = 0;
  final List<int> indent = [0];

  R? parse(String buffer) =>
      (
        this
          ..buffer = buffer
          ..reset(),
        apply(start),
      ).$2;
  _Rule<R> get start;
}

extension NullableExtension<T extends Object> on T {
  @pragma("vm:prefer-inline")
  T? nullable() => this;
}

typedef _Rule<T extends Object> = T? Function();

class _Head<T extends Object> {
  const _Head({required this.rule, required this.involvedSet, required this.evalSet});
  final _Rule<T> rule;
  final Set<_Rule<void>> involvedSet;
  final Set<_Rule<void>> evalSet;
}

class _Lr<T extends Object> {
  _Lr({required this.seed, required this.rule, required this.head});

  final _Rule<T> rule;
  T? seed;
  _Head<T>? head;
}

class _Memo {
  _Memo(this.ans, this.pos);

  Object? ans;
  int pos;
}

// GENERATED CODE
final class TestParser extends _PegParser<Object > {
  TestParser();

  @override
  get start => r0;


  /// `ROOT`
  Object ? f0() {
    if (this.apply(this.r0) case var $?) {
      return $;
    }
  }

  /// `fragment0`
  late final f1 = () {
    if (this.apply(this.r5) case var $0?) {
      if (this._indent() case var $1?) {
        return ($0, $1);
      }
    }
  };

  /// `fragment1`
  late final f2 = () {
    if (this.apply(this.r5) case var $?) {
      return $;
    }
  };

  /// `fragment2`
  late final f3 = () {
    if (this.f2() case var $0) {
      if (this._dedent() case var $1?) {
        return ($0, $1);
      }
    }
  };

  /// `fragment3`
  late final f4 = () {
    if (this.f1() case _?) {
      if (this.apply(this.r2) case (var $1 && var $)?) {
        if (this.f3() case _?) {
          return $1;
        }
      }
    }
  };

  /// `fragment4`
  late final f5 = () {
    if (this.apply(this.r5) case var $0?) {
      if (this._samedent() case var $1?) {
        return ($0, $1);
      }
    }
  };

  /// `fragment5`
  late final f6 = () {
    if (this._mark() case var _mark) {
      if (this.matchRange(_range.$2) case (var $0 && null)) {
        this._recover(_mark);
        if (this.matchRange(_range.$1) case var $1?) {
          return ($0, $1);
        }
      }
    }
  };

  /// `global::root`
  Object ? r0() {
    if (this.pos <= 0) {
      if (this.apply(this.r1) case var _0?) {
        if ([_0] case (var $1 && var $ && var _l1)) {
          for (;;) {
            if (this._mark() case var _mark) {
              if (this.apply(this.r4)! case _) {
                if (this.apply(this.r1) case var _0?) {
                  _l1.add(_0);
                  continue;
                }
              }
              this._recover(_mark);
              break;
            }
          }
          if (this.apply(this.r4)! case var $) {
            if (this.pos >= this.buffer.length) {
              return $1;
            }
          }
        }
      }
    }
  }

  /// `global::statement`
  Object ? r1() {
    if (this._mark() case var _mark) {
      if (this.apply(this.r3) case var $0?) {
        if (this.f4() case var $1?) {
          return ($0, $1);
        }
      }
      this._recover(_mark);
      if (this.apply(this.r3) case var $?) {
        return $;
      }
    }
  }

  /// `global::block`
  Object ? r2() {
    if (this.apply(this.r1) case var _0?) {
      if ([_0] case var _l1) {
        for (;;) {
          if (this._mark() case var _mark) {
            if (this.f5() case _?) {
              if (this.apply(this.r1) case var _0?) {
                _l1.add(_0);
                continue;
              }
            }
            this._recover(_mark);
            break;
          }
        }
        return _l1;
      }
    }
  }

  /// `global::identifier`
  late final r3 = () {
    if (this.pos case var from) {
      if (this.matchRange(_range.$4) case _?) {
        if (this._mark() case var _mark) {
          if (this.matchRange(_range.$3) case var _0) {
            if ([if (_0 case var _0?) _0] case var _l1) {
              if (_l1.isNotEmpty) {
                for (;;) {
                  if (this._mark() case var _mark) {
                    if (this.matchRange(_range.$3) case var _0?) {
                      _l1.add(_0);
                      continue;
                    }
                    this._recover(_mark);
                    break;
                  }
                }
              } else {
                this._recover(_mark);
              }
              if (this.pos case var to) {
                if (this.buffer.substring(from, to) case var span) {
                  return span;
                }
              }
            }
          }
        }
      }
    }
  };

  /// `global::NEWLINE_WS`
  late final r4 = () {
    if (this._mark() case var _mark) {
      if (this.matchRange(_range.$5) case var _0) {
        if ([if (_0 case var _0?) _0] case var _l1) {
          if (_l1.isNotEmpty) {
            for (;;) {
              if (this._mark() case var _mark) {
                if (this.matchRange(_range.$5) case var _0?) {
                  _l1.add(_0);
                  continue;
                }
                this._recover(_mark);
                break;
              }
            }
          } else {
            this._recover(_mark);
          }
          return _l1;
        }
      }
    }
  };

  /// `global::NEWLINE`
  late final r5 = () {
    if (this.apply(this.r6)! case var $0) {
      if (this.matchRange(_range.$6) case var $1?) {
        return ($0, $1);
      }
    }
  };

  /// `global::WS`
  late final r6 = () {
    if (this._mark() case var _mark) {
      if (this.f6() case var _0) {
        if ([if (_0 case var _0?) _0] case var _l1) {
          if (_l1.isNotEmpty) {
            for (;;) {
              if (this._mark() case var _mark) {
                if (this.f6() case var _0?) {
                  _l1.add(_0);
                  continue;
                }
                this._recover(_mark);
                break;
              }
            }
          } else {
            this._recover(_mark);
          }
          return _l1;
        }
      }
    }
  };

}
class _range {
  /// `[-\r]`
  static const $1 = { (9, 13), (32, 32) };
  /// `[\n\r]`
  static const $2 = { (10, 10), (13, 13) };
  /// `[A-Za-z_0-9]`
  static const $3 = { (65, 90), (97, 122), (95, 95), (48, 57) };
  /// `[A-Za-z_]`
  static const $4 = { (65, 90), (97, 122), (95, 95) };
  /// `[-\r\n\r]`
  static const $5 = { (9, 13), (32, 32), (10, 10), (13, 13) };
  /// `[\n]`
  static const $6 = { (10, 10) };
}
