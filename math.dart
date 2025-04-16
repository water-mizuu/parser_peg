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
  final Map<int, _Head<void>> _heads = <int, _Head<void>>{};
  final Queue<_Lr<void>> _lrStack = DoubleLinkedQueue<_Lr<void>>();
  final Map<(_Rule<void>, int), _Memo> _memo = <(_Rule<void>, int), _Memo>{};
  final Map<(Pattern, int), (int, String)> _patternMemo = <(Pattern, int), (int, String)>{};

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
final class Math extends _PegParser<num > {
  Math();

  @override
  get start => r0;


  /// `global::json::atom::number::digits`
  Object? f0() {
    if (this._mark() case var _mark) {
      if (this.f0() case var $0?) {
        if (this.f1() case var $1?) {
          return ($0, $1);
        }
      }
      this._recover(_mark);
      if (this.f1() case var $?) {
        return $;
      }
    }
  }

  /// `global::json::atom::number::digit`
  Object? f1() {
    if (this._mark() case var _mark) {
      if (this.matchPattern(_string.$1) case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.f2() case var $?) {
        return $;
      }
    }
  }

  /// `global::json::atom::number::onenine`
  Object? f2() {
    if (this._mark() case var _mark) {
      if (this.matchPattern(_string.$2) case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.matchPattern(_string.$3) case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.matchPattern(_string.$4) case var $?) {
        return $;
      }
      this._recover(_mark);
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
    }
  }

  /// `ROOT`
  num ? f3() {
    if (this.apply(this.r0) case var $?) {
      return $;
    }
  }

  /// `global::json::atom::number::slow`
  Object? f4() {
    if (this.f5() case var $?) {
      return $;
    }
  }

  /// `global::json::atom::number::number`
  Object? f5() {
    if (this.f6() case var $0?) {
      if (this.f7() case var $1) {
        if (this.f8() case var $2) {
          return ($0, $1, $2);
        }
      }
    }
  }

  /// `global::json::atom::number::integer`
  Object? f6() {
    if (this._mark() case var _mark) {
      if (this.f1() case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.f2() case var $0?) {
        if (this.f0() case var $1?) {
          return ($0, $1);
        }
      }
      this._recover(_mark);
      if (this.matchPattern(_string.$11) case var $0?) {
        if (this.f1() case var $1?) {
          return ($0, $1);
        }
      }
      this._recover(_mark);
      if (this.matchPattern(_string.$11) case var $0?) {
        if (this.f2() case var $1?) {
          if (this.f0() case var $2?) {
            return ($0, $1, $2);
          }
        }
      }
    }
  }

  /// `global::json::atom::number::fraction`
  Object f7() {
    if (this._mark() case var _mark) {
      if (this.matchPattern(_string.$12) case var $0?) {
        if (this.f0() case var $1?) {
          return ($0, $1);
        }
      }
      this._recover(_mark);
      if ('' case var $) {
        return $;
      }
    }
  }

  /// `global::json::atom::number::exponent`
  Object f8() {
    if (this._mark() case var _mark) {
      if (this.f9() case var $0?) {
        if (this.fa() case var $1) {
          if (this.f0() case var $2?) {
            return ($0, $1, $2);
          }
        }
      }
      this._recover(_mark);
      if ('' case var $) {
        return $;
      }
    }
  }

  /// `fragment0`
  late final f9 = () {
    if (this._mark() case var _mark) {
      if (this.matchPattern(_string.$13) case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.matchPattern(_string.$14) case var $?) {
        return $;
      }
    }
  };

  /// `fragment1`
  late final fa = () {
    if (this._mark() case var _mark) {
      if (this.matchPattern(_string.$15) case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.matchPattern(_string.$11) case var $?) {
        return $;
      }
      this._recover(_mark);
      if ('' case var $) {
        return $;
      }
    }
  };

  /// `global::rule`
  num ? r0() {
    if (this.pos <= 0) {
      if (this.apply(this.r1) case var $1?) {
        if (this.pos >= this.buffer.length) {
          return $1;
        }
      }
    }
  }

  /// `global::expr`
  num ? r1() {
    if (this._mark() case var _mark) {
      if (this.apply(this.r1) case var expr?) {
        if (this.apply(this.r5)! case _) {
          if (this.matchPattern(_string.$15) case _?) {
            if (this.apply(this.r5)! case _) {
              if (this.apply(this.r2) case var term?) {
                return expr + term;
              }
            }
          }
        }
      }
      this._recover(_mark);
      if (this.apply(this.r1) case var expr?) {
        if (this.apply(this.r5)! case _) {
          if (this.matchPattern(_string.$11) case _?) {
            if (this.apply(this.r5)! case _) {
              if (this.apply(this.r2) case var term?) {
                return expr - term;
              }
            }
          }
        }
      }
      this._recover(_mark);
      if (this.apply(this.r2) case var $?) {
        return $;
      }
    }
  }

  /// `global::term`
  num ? r2() {
    if (this._mark() case var _mark) {
      if (this.matchPattern(_string.$11) case _?) {
        if (this.apply(this.r5)! case _) {
          if (this.apply(this.r2) case var term?) {
            return -term;
          }
        }
      }
      this._recover(_mark);
      if (this.apply(this.r2) case var term?) {
        if (this.apply(this.r5)! case _) {
          if (this.apply(this.r3) case var factor?) {
            return term * factor;
          }
        }
      }
      this._recover(_mark);
      if (this.apply(this.r2) case var term?) {
        if (this.apply(this.r5)! case _) {
          if (this.matchPattern(_string.$16) case _?) {
            if (this.apply(this.r5)! case _) {
              if (this.apply(this.r3) case var factor?) {
                return term * factor;
              }
            }
          }
        }
      }
      this._recover(_mark);
      if (this.apply(this.r2) case var term?) {
        if (this.apply(this.r5)! case _) {
          if (this.matchPattern(_string.$17) case _?) {
            if (this.apply(this.r5)! case _) {
              if (this.apply(this.r3) case var factor?) {
                return term / factor;
              }
            }
          }
        }
      }
      this._recover(_mark);
      if (this.apply(this.r2) case var term?) {
        if (this.apply(this.r5)! case _) {
          if (this.matchPattern(_string.$18) case _?) {
            if (this.apply(this.r5)! case _) {
              if (this.apply(this.r3) case var factor?) {
                return term % factor;
              }
            }
          }
        }
      }
      this._recover(_mark);
      if (this.apply(this.r2) case var term?) {
        if (this.apply(this.r5)! case _) {
          if (this.matchPattern(_string.$19) case _?) {
            if (this.apply(this.r5)! case _) {
              if (this.apply(this.r3) case var factor?) {
                return term ~/ factor;
              }
            }
          }
        }
      }
      this._recover(_mark);
      if (this.apply(this.r3) case var $?) {
        return $;
      }
    }
  }

  /// `global::factor`
  num ? r3() {
    if (this._mark() case var _mark) {
      if (this.apply(this.r4) case var primary?) {
        if (this.apply(this.r5)! case _) {
          if (this.matchPattern(_string.$20) case _?) {
            if (this.apply(this.r5)! case _) {
              if (this.apply(this.r3) case var factor?) {
                return math.pow(primary, factor);
              }
            }
          }
        }
      }
      this._recover(_mark);
      if (this.apply(this.r4) case var $?) {
        return $;
      }
    }
  }

  /// `global::primary`
  num ? r4() {
    if (this._mark() case var _mark) {
      if (this.matchPattern(_string.$22) case _?) {
        if (this.apply(this.r5)! case _) {
          if (this.apply(this.r1) case var expr?) {
            if (this.apply(this.r5)! case _) {
              if (this.matchPattern(_string.$21) case _?) {
                return expr;
              }
            }
          }
        }
      }
      this._recover(_mark);
      if (this.pos case var from) {
        if (this.f4() case var $?) {
          if (this.pos case var to) {
            if (this.buffer.substring(from, to) case var span) {
              return double.parse(span);
            }
          }
        }
      }
    }
  }

  /// `global::_`
  late final r5 = () {
    if (this._mark() case var _mark) {
      if (this.matchPattern(_regexp.$1) case var _0) {
        if ([if (_0 case var _0?) _0] case var _l1) {
          if (_l1.isNotEmpty) {
            for (;;) {
              if (this._mark() case var _mark) {
                if (this.matchPattern(_regexp.$1) case var _0?) {
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
          return ();
        }
      }
    }
  };

}
class _regexp {
  /// `/\s/`
  static final $1 = RegExp("\\s");
}
class _string {
  /// `"0"`
  static const $1 = "0";
  /// `"1"`
  static const $2 = "1";
  /// `"2"`
  static const $3 = "2";
  /// `"3"`
  static const $4 = "3";
  /// `"4"`
  static const $5 = "4";
  /// `"5"`
  static const $6 = "5";
  /// `"6"`
  static const $7 = "6";
  /// `"7"`
  static const $8 = "7";
  /// `"8"`
  static const $9 = "8";
  /// `"9"`
  static const $10 = "9";
  /// `"-"`
  static const $11 = "-";
  /// `"."`
  static const $12 = ".";
  /// `"E"`
  static const $13 = "E";
  /// `"e"`
  static const $14 = "e";
  /// `"+"`
  static const $15 = "+";
  /// `"*"`
  static const $16 = "*";
  /// `"/"`
  static const $17 = "/";
  /// `"%"`
  static const $18 = "%";
  /// `"~/"`
  static const $19 = "~/";
  /// `"^"`
  static const $20 = "^";
  /// `")"`
  static const $21 = ")";
  /// `"("`
  static const $22 = "(";
}
