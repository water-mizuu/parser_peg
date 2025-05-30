// ignore_for_file: always_declare_return_types, always_put_control_body_on_new_line, always_specify_types, avoid_escaping_inner_quotes, avoid_redundant_argument_values, annotate_overrides, body_might_complete_normally_nullable, constant_pattern_never_matches_value_type, curly_braces_in_flow_control_structures, dead_code, directives_ordering, duplicate_ignore, inference_failure_on_function_return_type, constant_identifier_names, prefer_function_declarations_over_variables, prefer_interpolation_to_compose_strings, prefer_is_empty, no_leading_underscores_for_local_identifiers, non_constant_identifier_names, unnecessary_null_check_pattern, unnecessary_brace_in_string_interps, unnecessary_string_interpolations, unnecessary_this, unused_element, unused_import, prefer_double_quotes, unused_local_variable, unreachable_from_main, use_raw_strings, type_annotate_public_apis

// imports
// ignore_for_file: collection_methods_unrelated_type

import "dart:collection";
// PREAMBLE
import "dart:math" as math show pow;
import "dart:math" as math;

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
    RegExp regex = includeNewlines ? whitespaceRegExp.$1 : whitespaceRegExp.$2;
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
  T? asNullable() => this;
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
final class MathParserCst extends _PegParser<Object> {
  MathParserCst();

  @override
  get start => r0;

  /// `ROOT`
  Object? f0() {
    if (this.apply(this.r0) case var $?) {
      return ("<ROOT>", $);
    }
  }

  /// `global::rule`
  Object? r0() {
    if (this.pos case var $0 when this.pos <= 0) {
      if (this.apply(this.r1) case var expr?) {
        if (this.pos case var $2 when this.pos >= this.buffer.length) {
          if ([$0, expr, $2] case var $) {
            return ("<rule>", $);
          }
        }
      }
    }
  }

  /// `global::expr`
  Object? r1() {
    if (this.pos case var mark) {
      if (this.apply(this.r1) case var expr?) {
        if (this.apply(this.r5)! case var $1) {
          if (this.matchPattern(_string.$1) case var $2?) {
            if (this.apply(this.r5)! case var $3) {
              if (this.apply(this.r2) case var term?) {
                if ([expr, $1, $2, $3, term] case var $) {
                  return ("<expr>", $);
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.r1) case var expr?) {
        if (this.apply(this.r5)! case var $1) {
          if (this.matchPattern(_string.$2) case var $2?) {
            if (this.apply(this.r5)! case var $3) {
              if (this.apply(this.r2) case var term?) {
                if ([expr, $1, $2, $3, term] case var $) {
                  return ("<expr>", $);
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.r2) case var $?) {
        return ("<expr>", $);
      }
    }
  }

  /// `global::term`
  Object? r2() {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$2) case var $0?) {
        if (this.apply(this.r5)! case var $1) {
          if (this.apply(this.r2) case var term?) {
            if ([$0, $1, term] case var $) {
              return ("<term>", $);
            }
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.r2) case var term?) {
        if (this.apply(this.r5)! case var $1) {
          if (this.apply(this.r3) case var factor?) {
            if ([term, $1, factor] case var $) {
              return ("<term>", $);
            }
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.r2) case var term?) {
        if (this.apply(this.r5)! case var $1) {
          if (this.matchPattern(_string.$3) case var $2?) {
            if (this.apply(this.r5)! case var $3) {
              if (this.apply(this.r3) case var factor?) {
                if ([term, $1, $2, $3, factor] case var $) {
                  return ("<term>", $);
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.r2) case var term?) {
        if (this.apply(this.r5)! case var $1) {
          if (this.matchPattern(_string.$4) case var $2?) {
            if (this.apply(this.r5)! case var $3) {
              if (this.apply(this.r3) case var factor?) {
                if ([term, $1, $2, $3, factor] case var $) {
                  return ("<term>", $);
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.r2) case var term?) {
        if (this.apply(this.r5)! case var $1) {
          if (this.matchPattern(_string.$5) case var $2?) {
            if (this.apply(this.r5)! case var $3) {
              if (this.apply(this.r3) case var factor?) {
                if ([term, $1, $2, $3, factor] case var $) {
                  return ("<term>", $);
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.r2) case var term?) {
        if (this.apply(this.r5)! case var $1) {
          if (this.matchPattern(_string.$6) case var $2?) {
            if (this.apply(this.r5)! case var $3) {
              if (this.apply(this.r3) case var factor?) {
                if ([term, $1, $2, $3, factor] case var $) {
                  return ("<term>", $);
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.r3) case var $?) {
        return ("<term>", $);
      }
    }
  }

  /// `global::factor`
  Object? r3() {
    if (this.pos case var mark) {
      if (this.apply(this.r4) case var primary?) {
        if (this.apply(this.r5)! case var $1) {
          if (this.matchPattern(_string.$7) case var $2?) {
            if (this.apply(this.r5)! case var $3) {
              if (this.apply(this.r3) case var factor?) {
                if ([primary, $1, $2, $3, factor] case var $) {
                  return ("<factor>", $);
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.r4) case var $?) {
        return ("<factor>", $);
      }
    }
  }

  /// `global::primary`
  Object? r4() {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$9) case var $0?) {
        if (this.apply(this.r5)! case var $1) {
          if (this.apply(this.r1) case var expr?) {
            if (this.apply(this.r5)! case var $3) {
              if (this.matchPattern(_string.$8) case var $4?) {
                if ([$0, $1, expr, $3, $4] case var $) {
                  return ("<primary>", $);
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (matchPattern(_regexp.$1) case var _2?) {
          if ([_2] case (var $0 && var _l3)) {
            for (;;) {
              if (this.pos case var mark) {
                if (matchPattern(_regexp.$1) case var _2?) {
                  _l3.add(_2);
                  continue;
                }
                this.pos = mark;
                break;
              }
            }
            if (this.matchPattern(_string.$10) case var $1?) {
              if (matchPattern(_regexp.$1) case var _0?) {
                if ([_0] case (var $2 && var _l1)) {
                  for (;;) {
                    if (this.pos case var mark) {
                      if (matchPattern(_regexp.$1) case var _0?) {
                        _l1.add(_0);
                        continue;
                      }
                      this.pos = mark;
                      break;
                    }
                  }
                  if ([$0, $1, $2] case var $) {
                    return ("<primary>", $);
                  }
                }
              }
            }
          }
        }
        this.pos = mark;
        if (matchPattern(_regexp.$1) case var _4?) {
          if ([_4] case (var $ && var _l5)) {
            for (;;) {
              if (this.pos case var mark) {
                if (matchPattern(_regexp.$1) case var _4?) {
                  _l5.add(_4);
                  continue;
                }
                this.pos = mark;
                break;
              }
            }
            return ("<primary>", $);
          }
        }
      }
    }
  }

  /// `global::_`
  Object r5() {
    if (this.pos case var mark) {
      if (matchPattern(_regexp.$2) case var _0) {
        if ([if (_0 case var _0?) _0] case (var $ && var _l1)) {
          if (_l1.isNotEmpty) {
            for (;;) {
              if (this.pos case var mark) {
                if (matchPattern(_regexp.$2) case var _0?) {
                  _l1.add(_0);
                  continue;
                }
                this.pos = mark;
                break;
              }
            }
          } else {
            this.pos = mark;
          }
          return ("<_>", $);
        }
      }
    }
  }

  static final _regexp = (RegExp("\\d"), RegExp("\\s"));
  static const _string = ("+", "-", "*", "/", "%", "~/", "^", ")", "(", ".");
}
