// ignore_for_file: type=lint, body_might_complete_normally_nullable, unused_local_variable, inference_failure_on_function_return_type, unused_import, duplicate_ignore, unused_element, collection_methods_unrelated_type, unused_element, use_setters_to_change_properties

// imports
// ignore_for_file: collection_methods_unrelated_type, unused_element, use_setters_to_change_properties

import "dart:collection";
import "dart:math" as math;
// PREAMBLE
import "dart:math" as math show pow;
// base.dart
abstract base class _PegParser<R extends Object> {
  _PegParser();

  _Memo? _recall<T extends Object>(_Rule<T> r, int p) {
    _Memo? m = _memo[(r, p)];
    _Head<void>? h = _heads[p];

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

  T? _growLr<T extends Object>(_Rule<T> r, int p, _Memo m, _Head<T> h) {
    _heads[p] = h;
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

    _heads.remove(p);
    this.pos = m.pos;

    return m.ans as T?;
  }

  T? _lrAnswer<T extends Object>(_Rule<T> r, int p, _Memo m) {
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
        return _growLr(r, p, m, h);
      }
    }
  }

  T? apply<T extends Object>(_Rule<T> r, [int? p]) {
    p ??= this.pos;

    _Memo? m = _recall(r, p);
    if (m == null) {
      _Lr<T> lr = _Lr<T>(seed: null, rule: r, head: null);

      _lrStack.addFirst(lr);
      m = _Memo(lr, p);

      _memo[(r, p)] = m;

      T? ans = r.call();
      _lrStack.removeFirst();
      m.pos = this.pos;

      if (lr.head != null) {
        lr.seed = ans;
        return _lrAnswer(r, p, m);
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
    if (_patternMemo[(pattern, this.pos)] case (int pos, String value)) {
      this.pos = pos;
      return value;
    }

    if (pattern.matchAsPrefix(this.buffer, this.pos) case Match(:int start, :int end)) {
      String result = buffer.substring(start, end);
      _patternMemo[(pattern, start)] = (end, result);
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

  int _mark() {
    return this.pos;
  }

  void _recover(int pos) {
    this.pos = pos;
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
  final Map<int, _Head<void>> _heads = <int, _Head<void>>{};
  final Queue<_Lr<void>> _lrStack = DoubleLinkedQueue<_Lr<void>>();
  final Map<(_Rule<void>, int), _Memo> _memo = <(_Rule<void>, int), _Memo>{};
  final Map<(Pattern, int), (int, String)> _patternMemo = <(Pattern, int), (int, String)>{};

  late String buffer;
  int pos = 0;

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
final class Math extends _PegParser<Object> {
  Math();

  @override
  get start => r0;


  /// `ROOT`
  Object? f0() {
    if (this.apply(this.r0) case var $?) {
      return $;
    }
  }

  /// `fragment0`
  Object? f1() {
    var _mark = this._mark();
    if (this.matchPattern(_string.$1) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$2) case var $?) {
      return $;
    }
  }

  /// `global::json::atom::number::slow`
  Object? r0() {
    if (this.apply(this.r1) case var $?) {
      return $;
    }
  }

  /// `global::json::atom::number::number`
  Object? r1() {
    if (this.apply(this.r2) case var $0?) {
      if (this.apply(this.r6)! case var $1) {
        if (this.apply(this.r7)! case var $2) {
          return ($0, $1, $2);
        }
      }
    }
  }

  /// `global::json::atom::number::integer`
  Object? r2() {
    var _mark = this._mark();
    if (this.apply(this.r4) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.apply(this.r5) case var $0?) {
      if (this.apply(this.r3) case var $1?) {
        return ($0, $1);
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$3) case var $0?) {
      if (this.apply(this.r4) case var $1?) {
        return ($0, $1);
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$3) case var $0?) {
      if (this.apply(this.r5) case var $1?) {
        if (this.apply(this.r3) case var $2?) {
          return ($0, $1, $2);
        }
      }
    }
  }

  /// `global::json::atom::number::digits`
  Object? r3() {
    var _mark = this._mark();
    if (this.apply(this.r3) case var $0?) {
      if (this.apply(this.r4) case var $1?) {
        return ($0, $1);
      }
    }
    this._recover(_mark);
    if (this.apply(this.r4) case var $?) {
      return $;
    }
  }

  /// `global::json::atom::number::digit`
  Object? r4() {
    var _mark = this._mark();
    if (this.matchPattern(_string.$4) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.apply(this.r5) case var $?) {
      return $;
    }
  }

  /// `global::json::atom::number::onenine`
  Object? r5() {
    var _mark = this._mark();
    if (this.matchPattern(_string.$5) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$6) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$7) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$8) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$9) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$10) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$11) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$12) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$13) case var $?) {
      return $;
    }
  }

  /// `global::json::atom::number::fraction`
  Object r6() {
    var _mark = this._mark();
    if (this.matchPattern(_string.$14) case var $0?) {
      if (this.apply(this.r3) case var $1?) {
        return ($0, $1);
      }
    }
    this._recover(_mark);
    if ('' case var $) {
      return $;
    }
  }

  /// `global::json::atom::number::exponent`
  Object r7() {
    var _mark = this._mark();
    if (this.f1() case var $0?) {
      if (this.apply(this.r8)! case var $1) {
        if (this.apply(this.r3) case var $2?) {
          return ($0, $1, $2);
        }
      }
    }
    this._recover(_mark);
    if ('' case var $) {
      return $;
    }
  }

  /// `global::json::atom::number::sign`
  Object r8() {
    var _mark = this._mark();
    if (this.matchPattern(_string.$15) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$3) case var $?) {
      return $;
    }
    this._recover(_mark);
    if ('' case var $) {
      return $;
    }
  }

  /// `global::expr`
  Object? r9() {
    var _mark = this._mark();
    if (this.apply(this.r9) case (var $0 && var expr)?) {
      if (this.apply(this.rd)! case var $1) {
        if (this.matchPattern(_string.$15) case var $2?) {
          if (this.apply(this.rd)! case var $3) {
            if (this.apply(this.ra) case (var $4 && var term)?) {
              return ($0, $1, $2, $3, $4);
            }
          }
        }
      }
    }
    this._recover(_mark);
    if (this.apply(this.r9) case (var $0 && var expr)?) {
      if (this.apply(this.rd)! case var $1) {
        if (this.matchPattern(_string.$3) case var $2?) {
          if (this.apply(this.rd)! case var $3) {
            if (this.apply(this.ra) case (var $4 && var term)?) {
              return ($0, $1, $2, $3, $4);
            }
          }
        }
      }
    }
    this._recover(_mark);
    if (this.apply(this.ra) case var $?) {
      return $;
    }
  }

  /// `global::term`
  Object? ra() {
    var _mark = this._mark();
    if (this.matchPattern(_string.$3) case var $0?) {
      if (this.apply(this.rd)! case var $1) {
        if (this.apply(this.ra) case (var $2 && var term)?) {
          return ($0, $1, $2);
        }
      }
    }
    this._recover(_mark);
    if (this.apply(this.ra) case (var $0 && var term)?) {
      if (this.apply(this.rd)! case var $1) {
        if (this.apply(this.rb) case (var $2 && var factor)?) {
          return ($0, $1, $2);
        }
      }
    }
    this._recover(_mark);
    if (this.apply(this.ra) case (var $0 && var term)?) {
      if (this.apply(this.rd)! case var $1) {
        if (this.matchPattern(_string.$16) case var $2?) {
          if (this.apply(this.rd)! case var $3) {
            if (this.apply(this.rb) case (var $4 && var factor)?) {
              return ($0, $1, $2, $3, $4);
            }
          }
        }
      }
    }
    this._recover(_mark);
    if (this.apply(this.ra) case (var $0 && var term)?) {
      if (this.apply(this.rd)! case var $1) {
        if (this.matchPattern(_string.$17) case var $2?) {
          if (this.apply(this.rd)! case var $3) {
            if (this.apply(this.rb) case (var $4 && var factor)?) {
              return ($0, $1, $2, $3, $4);
            }
          }
        }
      }
    }
    this._recover(_mark);
    if (this.apply(this.ra) case (var $0 && var term)?) {
      if (this.apply(this.rd)! case var $1) {
        if (this.matchPattern(_string.$18) case var $2?) {
          if (this.apply(this.rd)! case var $3) {
            if (this.apply(this.rb) case (var $4 && var factor)?) {
              return ($0, $1, $2, $3, $4);
            }
          }
        }
      }
    }
    this._recover(_mark);
    if (this.apply(this.ra) case (var $0 && var term)?) {
      if (this.apply(this.rd)! case var $1) {
        if (this.matchPattern(_string.$19) case var $2?) {
          if (this.apply(this.rd)! case var $3) {
            if (this.apply(this.rb) case (var $4 && var factor)?) {
              return ($0, $1, $2, $3, $4);
            }
          }
        }
      }
    }
    this._recover(_mark);
    if (this.apply(this.rb) case var $?) {
      return $;
    }
  }

  /// `global::factor`
  Object? rb() {
    var _mark = this._mark();
    if (this.apply(this.rc) case (var $0 && var primary)?) {
      if (this.apply(this.rd)! case var $1) {
        if (this.matchPattern(_string.$20) case var $2?) {
          if (this.apply(this.rd)! case var $3) {
            if (this.apply(this.rb) case (var $4 && var factor)?) {
              return ($0, $1, $2, $3, $4);
            }
          }
        }
      }
    }
    this._recover(_mark);
    if (this.apply(this.rc) case var $?) {
      return $;
    }
  }

  /// `global::primary`
  Object? rc() {
    var _mark = this._mark();
    if (this.matchPattern(_string.$22) case var $0?) {
      if (this.apply(this.rd)! case var $1) {
        if (this.apply(this.r9) case (var $2 && var expr)?) {
          if (this.apply(this.rd)! case var $3) {
            if (this.matchPattern(_string.$21) case var $4?) {
              return ($0, $1, $2, $3, $4);
            }
          }
        }
      }
    }
    this._recover(_mark);
    if (this.apply(this.r0) case var $?) {
      return $;
    }
  }

  /// `global::_`
  Object rd() {
    var _mark = this._mark();
    if (matchPattern(_regexp.$1) case var _0) {
      if ([if (_0 case var _0?) _0] case var _l1) {
        if (_l1.isNotEmpty) {
          for (;;) {
            var _mark = this._mark();
            if (matchPattern(_regexp.$1) case var _0?) {
              _l1.add(_0);
              continue;
            }
            this._recover(_mark);
            break;
          }
        } else {
          this._recover(_mark);
        }
        return _l1;
      }
    }
  }

  static final _regexp = (
    RegExp("\\s"),
  );
  static const _string = (
    "E",
    "e",
    "-",
    "0",
    "1",
    "2",
    "3",
    "4",
    "5",
    "6",
    "7",
    "8",
    "9",
    ".",
    "+",
    "*",
    "/",
    "%",
    "~/",
    "^",
    ")",
    "(",
  );
}
