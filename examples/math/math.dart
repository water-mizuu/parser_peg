// ignore_for_file: always_declare_return_types, always_put_control_body_on_new_line, always_specify_types, avoid_escaping_inner_quotes, avoid_redundant_argument_values, annotate_overrides, body_might_complete_normally_nullable, constant_pattern_never_matches_value_type, curly_braces_in_flow_control_structures, dead_code, directives_ordering, duplicate_ignore, inference_failure_on_function_return_type, constant_identifier_names, prefer_function_declarations_over_variables, prefer_interpolation_to_compose_strings, prefer_is_empty, no_leading_underscores_for_local_identifiers, non_constant_identifier_names, unnecessary_null_check_pattern, unnecessary_brace_in_string_interps, unnecessary_string_interpolations, unnecessary_this, unused_element, unused_import, prefer_double_quotes, unused_local_variable, unreachable_from_main, use_raw_strings, type_annotate_public_apis

// imports
// ignore_for_file: collection_methods_unrelated_type

import "dart:collection";
import "dart:math" as math;
// PREAMBLE
import"dart:math"as math show pow;
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
    l.head ??= _Head<T>(
      rule: r,
      evalSet: <_Rule<void>>{},
      involvedSet: <_Rule<void>>{},
    );

    for (_Lr<void> lr in _lrStack.takeWhile((_Lr<void> lr) => lr.head != l.head)) {
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
        for (var (int start, int end) in ranges) "${String.fromCharCode(start)}-${String.fromCharCode(end)}",
      ]);
    }
  }

  // ignore: body_might_complete_normally_nullable
  String? matchPattern(Pattern pattern, {bool isReported = true}) {
    if (pattern.matchAsPrefix(buffer, pos) case Match(:int start, :int end)) {
      this.pos = end;
      return buffer.substring(start, end);
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
    this._memo.clear();
    this._lrStack.clear();
  }

  static (int column, int row) _columnRow(String buffer, int pos) {
    List<String> linesToIndex = "$buffer ".substring(0, pos + 1).split("\n");
    return (linesToIndex.length, linesToIndex.last.length);
  }

  String reportFailures() {
    var MapEntry<int, Set<String>>(
      key: int pos,
      value: Set<String> messages,
    ) = failures.entries.last;
    var (int column, int row) = _columnRow(buffer, pos);

    return "($column:$row): Expected the following: $messages";
  }

  static final (RegExp, RegExp) whitespaceRegExp = (RegExp(r"\s"), RegExp(r"(?!\n)\s"));

  final Map<int, Set<String>> failures = <int, Set<String>>{};
  final Map<int, _Head<void>> _heads = <int, _Head<void>>{};
  final Queue<_Lr<void>> _lrStack = DoubleLinkedQueue<_Lr<void>>();
  final Map<(_Rule<void>, int), _Memo> _memo = <(_Rule<void>, int), _Memo>{};

  late String buffer;
  int pos = 0;

  R? parse(String buffer) => (
        this
          ..buffer = buffer
          ..reset(),
        apply(start),
      ).$2;
  _Rule<R> get start;
}

typedef _Rule<T extends Object> = T? Function();

class _Head<T extends Object> {
  const _Head({
    required this.rule,
    required this.involvedSet,
    required this.evalSet,
  });
  final _Rule<T> rule;
  final Set<_Rule<void>> involvedSet;
  final Set<_Rule<void>> evalSet;
}

class _Lr<T extends Object> {
  _Lr({
    required this.seed,
    required this.rule,
    required this.head,
  });

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
final class MathParser extends _PegParser<num> {
  MathParser();

  @override
  get start => r0;


  /// `global::primary`
  num? f0() {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$2) case var $0?) {
        if (this.fg() case var $1?) {
          if (this.apply(this.r1) case var $2?) {
            if (this.fh() case var $3?) {
              if (this.matchPattern(_string.$1) case var $4?) {
                return $2;
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.pos case var from) {
          if (matchPattern(_regexp.$1) case var _2?) {
            if ([_2] case (var $0 && var _loop4)) {
              for (;;) {
                if (this.pos case var mark) {
                  if (matchPattern(_regexp.$1) case var _2?) {
                    _loop4.add(_2);
                    continue;
                  }
                  this.pos = mark;
                  break;
                }
              }
              if (this.matchPattern(_string.$3) case var $1?) {
                if (matchPattern(_regexp.$1) case var _0?) {
                  if ([_0] case (var $2 && var _loop2)) {
                    for (;;) {
                      if (this.pos case var mark) {
                        if (matchPattern(_regexp.$1) case var _0?) {
                          _loop2.add(_0);
                          continue;
                        }
                        this.pos = mark;
                        break;
                      }
                    }
                    if (($0, $1, $2) case var $) {
                      if (this.pos case var to) {
                        return double.parse(buffer.substring(from, to));
                      }
                    }
                  }
                }
              }
            }
          }
        }

        this.pos = mark;
        if (this.pos case var from) {
          if (matchPattern(_regexp.$1) case var _4?) {
            if ([_4] case (var $ && var _loop6)) {
              for (;;) {
                if (this.pos case var mark) {
                  if (matchPattern(_regexp.$1) case var _4?) {
                    _loop6.add(_4);
                    continue;
                  }
                  this.pos = mark;
                  break;
                }
              }
              if (this.pos case var to) {
                return int.parse(buffer.substring(from, to));
              }
            }
          }
        }
      }
    }
  }

  /// `fragment0`
  late final f1 = () {
    if (matchPattern(_regexp.$2) case var $?) {
      return "";
    }
  };

  /// `fragment1`
  late final f2 = () {
    if (matchPattern(_regexp.$2) case var $?) {
      return "";
    }
  };

  /// `fragment2`
  late final f3 = () {
    if (matchPattern(_regexp.$2) case var $?) {
      return "";
    }
  };

  /// `fragment3`
  late final f4 = () {
    if (matchPattern(_regexp.$2) case var $?) {
      return "";
    }
  };

  /// `fragment4`
  late final f5 = () {
    if (matchPattern(_regexp.$2) case var $?) {
      return "";
    }
  };

  /// `fragment5`
  late final f6 = () {
    if (matchPattern(_regexp.$2) case var $?) {
      return "";
    }
  };

  /// `fragment6`
  late final f7 = () {
    if (matchPattern(_regexp.$2) case var $?) {
      return "";
    }
  };

  /// `fragment7`
  late final f8 = () {
    if (matchPattern(_regexp.$2) case var $?) {
      return "";
    }
  };

  /// `fragment8`
  late final f9 = () {
    if (matchPattern(_regexp.$2) case var $?) {
      return "";
    }
  };

  /// `fragment9`
  late final fa = () {
    if (matchPattern(_regexp.$2) case var $?) {
      return "";
    }
  };

  /// `fragment10`
  late final fb = () {
    if (matchPattern(_regexp.$2) case var $?) {
      return "";
    }
  };

  /// `fragment11`
  late final fc = () {
    if (matchPattern(_regexp.$2) case var $?) {
      return "";
    }
  };

  /// `fragment12`
  late final fd = () {
    if (matchPattern(_regexp.$2) case var $?) {
      return "";
    }
  };

  /// `fragment13`
  late final fe = () {
    if (matchPattern(_regexp.$2) case var $?) {
      return "";
    }
  };

  /// `fragment14`
  late final ff = () {
    if (matchPattern(_regexp.$2) case var $?) {
      return "";
    }
  };

  /// `fragment15`
  late final fg = () {
    if (matchPattern(_regexp.$2) case var $?) {
      return "";
    }
  };

  /// `fragment16`
  late final fh = () {
    if (matchPattern(_regexp.$2) case var $?) {
      return "";
    }
  };

  /// `global::rule`
  num? r0() {
    if (this.pos case var $0 when this.pos <= 0) {
      if (this.apply(this.r1) case var $1?) {
        if (this.pos case var $2 when this.pos >= this.buffer.length) {
          return $1;
        }
      }
    }
  }

  /// `global::expr`
  num? r1() {
    if (this.pos case var mark) {
      if (this.apply(this.r1) case (var $0 && var expr)?) {
        if (this.f1() case var $1?) {
          if (this.matchPattern(_string.$4) case var $2?) {
            if (this.f2() case var $3?) {
              if (this.apply(this.r2) case (var $4 && var term)?) {
                if (($0, $1, $2, $3, $4) case var $) {
                  return expr + term;
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.r1) case (var $0 && var expr)?) {
        if (this.f3() case var $1?) {
          if (this.matchPattern(_string.$5) case var $2?) {
            if (this.f4() case var $3?) {
              if (this.apply(this.r2) case (var $4 && var term)?) {
                if (($0, $1, $2, $3, $4) case var $) {
                  return expr - term;
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.r2) case var $?) {
        return $;
      }
    }
  }

  /// `global::term`
  num? r2() {
    if (this.pos case var mark) {
      if (this.apply(this.r2) case (var $0 && var term)?) {
        if (this.f5() case var $1?) {
          if (this.matchPattern(_string.$6) case var $2?) {
            if (this.f6() case var $3?) {
              if (this.apply(this.r3) case (var $4 && var negative)?) {
                if (($0, $1, $2, $3, $4) case var $) {
                  return term * negative;
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.r2) case (var $0 && var term)?) {
        if (this.f7() case var $1?) {
          if (this.matchPattern(_string.$7) case var $2?) {
            if (this.f8() case var $3?) {
              if (this.apply(this.r3) case (var $4 && var negative)?) {
                if (($0, $1, $2, $3, $4) case var $) {
                  return term / negative;
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.r2) case (var $0 && var term)?) {
        if (this.f9() case var $1?) {
          if (this.matchPattern(_string.$8) case var $2?) {
            if (this.fa() case var $3?) {
              if (this.apply(this.r3) case (var $4 && var negative)?) {
                if (($0, $1, $2, $3, $4) case var $) {
                  return term % negative;
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.r2) case (var $0 && var term)?) {
        if (this.fb() case var $1?) {
          if (this.matchPattern(_string.$9) case var $2?) {
            if (this.fc() case var $3?) {
              if (this.apply(this.r3) case (var $4 && var negative)?) {
                if (($0, $1, $2, $3, $4) case var $) {
                  return term ~/ negative;
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.r3) case var $?) {
        return $;
      }
    }
  }

  /// `global::negative`
  num? r3() {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$5) case var $0?) {
        if (this.fd() case var $1?) {
          if (this.apply(this.r3) case (var $2 && var negative)?) {
            if (($0, $1, $2) case var $) {
              return -negative;
            }
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.r4) case var $?) {
        return $;
      }
    }
  }

  /// `global::factor`
  num? r4() {
    if (this.pos case var mark) {
      if (this.f0() case (var $0 && var primary)?) {
        if (this.fe() case var $1?) {
          if (this.matchPattern(_string.$10) case var $2?) {
            if (this.ff() case var $3?) {
              if (this.apply(this.r4) case (var $4 && var factor)?) {
                if (($0, $1, $2, $3, $4) case var $) {
                  return math.pow(primary, factor);
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.f0() case var $?) {
        return $;
      }
    }
  }

  static final _regexp = (
    RegExp("\\d"),
    RegExp("\\s*"),
  );
  static const _string = (
    ")",
    "(",
    ".",
    "+",
    "-",
    "*",
    "/",
    "%",
    "~/",
    "^",
  );
}
