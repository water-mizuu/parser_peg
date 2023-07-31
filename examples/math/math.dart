// ignore_for_file: always_declare_return_types, always_put_control_body_on_new_line, always_specify_types, avoid_escaping_inner_quotes, avoid_redundant_argument_values, annotate_overrides, body_might_complete_normally_nullable, constant_pattern_never_matches_value_type, curly_braces_in_flow_control_structures, dead_code, directives_ordering, duplicate_ignore, inference_failure_on_function_return_type, constant_identifier_names, prefer_function_declarations_over_variables, prefer_interpolation_to_compose_strings, no_leading_underscores_for_local_identifiers, non_constant_identifier_names, unnecessary_null_check_pattern, unnecessary_brace_in_string_interps, unnecessary_string_interpolations, unnecessary_this, unused_element, unused_import, prefer_double_quotes, unused_local_variable, unreachable_from_main, use_raw_strings, type_annotate_public_apis

// imports
// ignore_for_file: collection_methods_unrelated_type

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

    // If the head is not being grown, return the memoized result.
    if (h == null) {
      return m;
    }

    // If the current rule is not a part of the head and is not evaluated yet,
    // Add a failure to it.
    if (m == null && h.rule != r && !h.involvedSet.contains(r)) {
      return _Memo(null, p);
    }

    if (m != null && h.evalSet.contains(r)) {
      // Remove the current rule from the head's evaluation set.
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

  @pragma("vm:prefer-inline")
  T applyNonNull<T extends Object>(_NonNullableRule<T> r, [int? p]) => apply<T>(r, p)!;

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
  String? matchRange(Set<(int, int)> ranges) {
    if (pos < buffer.length) {
      int c = buffer.codeUnitAt(pos);
      for (var (int start, int end) in ranges) {
        if (start <= c && c <= end) {
          return buffer[pos++];
        }
      }
    }
  }

  // ignore: body_might_complete_normally_nullable
  String? matchPattern(Pattern pattern) {
    if (pattern.matchAsPrefix(buffer, pos) case Match(:int start, :int end)) {
      this.pos = end;
      return buffer.substring(start, end);
    } else {
      switch (pattern) {
        case RegExp(:String pattern):
          (errors[pos] ??= <String>[]).add(pattern);
        case String pattern:
          (errors[pos] ??= <String>[]).add(pattern);
      }
    }
  }

  void reset() {
    this.pos = 0;
    this._memo.clear();
    this._lrStack.clear();
  }

  static final (RegExp, RegExp) whitespaceRegExp = (RegExp(r"\s"), RegExp(r"(?!\n)\s"));

  final Map<int, List<String>> errors = <int, List<String>>{};
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
typedef _NonNullableRule<T extends Object> = T Function();

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
final class MathGrammar extends _PegParser<num> {
  MathGrammar();

  @override
  get start => rule;


  num? rule() {
    if (this.pos case var $0 when this.pos <= 0) {
      if (this.apply(this.expr) case var $1?) {
        if (this.pos case var $2 when this.pos >= this.buffer.length) {
          return $1;
        }
      }
    }
  }

  num? expr() {
    if (this.pos case var mark) {
      if (this.pos case var from) {
        if (this.apply(this.expr) case (var $0 && var expr)?) {
          if (this.applyNonNull(this._) case var $1) {
            if (matchPattern("+") case var $2?) {
              if (this.applyNonNull(this._) case var $3) {
                if (this.apply(this.term) case (var $4 && var term)?) {
                  if (($0, $1, $2, $3, $4) case var $) {
                    if (this.pos case var to) {
                      return expr + term;
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
        if (this.apply(this.expr) case (var $0 && var expr)?) {
          if (this.applyNonNull(this._) case var $1) {
            if (matchPattern("-") case var $2?) {
              if (this.applyNonNull(this._) case var $3) {
                if (this.apply(this.term) case (var $4 && var term)?) {
                  if (($0, $1, $2, $3, $4) case var $) {
                    if (this.pos case var to) {
                      return expr - term;
                    }
                  }
                }
              }
            }
          }
        }
      }

      this.pos = mark;
      if (this.apply(this.term) case var $?) {
        return $;
      }
    }
  }

  num? term() {
    if (this.pos case var mark) {
      if (this.pos case var from) {
        if (this.apply(this.term) case (var $0 && var term)?) {
          if (this.applyNonNull(this._) case var $1) {
            if (matchPattern("*") case var $2?) {
              if (this.applyNonNull(this._) case var $3) {
                if (this.apply(this.negative) case (var $4 && var negative)?) {
                  if (($0, $1, $2, $3, $4) case var $) {
                    if (this.pos case var to) {
                      return term * negative;
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
        if (this.apply(this.term) case (var $0 && var term)?) {
          if (this.applyNonNull(this._) case var $1) {
            if (matchPattern("/") case var $2?) {
              if (this.applyNonNull(this._) case var $3) {
                if (this.apply(this.negative) case (var $4 && var negative)?) {
                  if (($0, $1, $2, $3, $4) case var $) {
                    if (this.pos case var to) {
                      return term / negative;
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
        if (this.apply(this.term) case (var $0 && var term)?) {
          if (this.applyNonNull(this._) case var $1) {
            if (matchPattern("%") case var $2?) {
              if (this.applyNonNull(this._) case var $3) {
                if (this.apply(this.negative) case (var $4 && var negative)?) {
                  if (($0, $1, $2, $3, $4) case var $) {
                    if (this.pos case var to) {
                      return term % negative;
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
        if (this.apply(this.term) case (var $0 && var term)?) {
          if (this.applyNonNull(this._) case var $1) {
            if (matchPattern("~/") case var $2?) {
              if (this.applyNonNull(this._) case var $3) {
                if (this.apply(this.negative) case (var $4 && var negative)?) {
                  if (($0, $1, $2, $3, $4) case var $) {
                    if (this.pos case var to) {
                      return term ~/ negative;
                    }
                  }
                }
              }
            }
          }
        }
      }

      this.pos = mark;
      if (this.apply(this.negative) case var $?) {
        return $;
      }
    }
  }

  num? negative() {
    if (this.pos case var mark) {
      if (this.pos case var from) {
        if (matchPattern("-") case var $0?) {
          if (this.applyNonNull(this._) case var $1) {
            if (this.apply(this.negative) case (var $2 && var negative)?) {
              if (($0, $1, $2) case var $) {
                if (this.pos case var to) {
                  return -negative;
                }
              }
            }
          }
        }
      }

      this.pos = mark;
      if (this.apply(this.factor) case var $?) {
        return $;
      }
    }
  }

  num? factor() {
    if (this.pos case var mark) {
      if (this.pos case var from) {
        if (this.apply(this.primary) case (var $0 && var primary)?) {
          if (this.applyNonNull(this._) case var $1) {
            if (matchPattern("^") case var $2?) {
              if (this.applyNonNull(this._) case var $3) {
                if (this.apply(this.factor) case (var $4 && var factor)?) {
                  if (($0, $1, $2, $3, $4) case var $) {
                    if (this.pos case var to) {
                      return math.pow(primary, factor);
                    }
                  }
                }
              }
            }
          }
        }
      }

      this.pos = mark;
      if (this.apply(this.primary) case var $?) {
        return $;
      }
    }
  }

  num? primary() {
    if (this.pos case var mark) {
      if (matchPattern("(") case var $0?) {
        if (this.applyNonNull(this._) case var $1) {
          if (this.apply(this.expr) case var $2?) {
            if (this.applyNonNull(this._) case var $3) {
              if (matchPattern(")") case var $4?) {
                return $2;
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.number) case var $?) {
        return $;
      }
    }
  }

  num? number() {
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
            if (matchPattern(".") case var $1?) {
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

  late final _ = () {
    if (this.pos case var from) {
      if (matchPattern(_regexp.$2) case var _6) {
        if (this.pos case var mark) {
          if ([if (_6 case var _6?) _6] case (var $ && var _loop8)) {
            if (_loop8.isNotEmpty) {
              for (;;) {
                if (this.pos case var mark) {
                  if (matchPattern(_regexp.$2) case var _6?) {
                    _loop8.add(_6);
                    continue;
                  }
                  this.pos = mark;
                  break;
                }
              }
            } else {
              this.pos = mark;
            }
            if (this.pos case var to) {
              return "";
            }
          }
        }
      }
    }
  };

  static final _regexp = (
    RegExp("\\d"),
    RegExp("\\s+"),
  );
}
