// ignore_for_file: always_declare_return_types, always_put_control_body_on_new_line, always_specify_types, avoid_escaping_inner_quotes, avoid_redundant_argument_values, annotate_overrides, body_might_complete_normally_nullable, constant_pattern_never_matches_value_type, curly_braces_in_flow_control_structures, dead_code, directives_ordering, duplicate_ignore, inference_failure_on_function_return_type, constant_identifier_names, prefer_function_declarations_over_variables, prefer_interpolation_to_compose_strings, prefer_is_empty, no_leading_underscores_for_local_identifiers, non_constant_identifier_names, unnecessary_null_check_pattern, unnecessary_brace_in_string_interps, unnecessary_string_interpolations, unnecessary_this, unused_element, unused_import, prefer_double_quotes, unused_local_variable, unreachable_from_main, use_raw_strings, type_annotate_public_apis

// imports
// ignore_for_file: collection_methods_unrelated_type

import "dart:collection";
import "dart:math" as math;
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
      failures[pos] ??= <String>[
        for (var (int start, int end) in ranges) "${String.fromCharCode(start)}-${String.fromCharCode(end)}",
      ];
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
          (failures[pos] ??= <String>[]).add(pattern);
        case String pattern:
          (failures[pos] ??= <String>[]).add(pattern);
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

    ///
    /// Counts all the newline tokens up until [index], adding 1.
    ///
    return (linesToIndex.length, linesToIndex.last.length);
  }

  String reportFailures() {
    var MapEntry<int, List<String>>(
      key: int pos,
      value: List<String> messages,
    ) = failures.entries.last;
    var (int column, int row) = _columnRow(buffer, pos);

    return "($column:$row): Expected the following: $messages";
  }

  static final (RegExp, RegExp) whitespaceRegExp = (RegExp(r"\s"), RegExp(r"(?!\n)\s"));

  final Map<int, List<String>> failures = <int, List<String>>{};
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
final class PlaygroundParser extends _PegParser<Object> {
  PlaygroundParser();

  @override
  get start => r0;


  /// ```
  /// @fragment fragment0
  /// ```
  late final f0 = () {
    if (this.pos case var mark) {
      if (this.matchPattern("\"\"\"") case (var $0 && null)) {
        this.pos = mark;
        if (pos < buffer.length) {
          if (buffer[pos] case var $1) {
            pos++;
          return $1;
          }
        }
      }
    }
  };

  /// ```
  /// @fragment fragment1
  /// ```
  late final f1 = () {
    if (this.pos case var mark) {
      if (this.matchPattern("'''") case (var $0 && null)) {
        this.pos = mark;
        if (pos < buffer.length) {
          if (buffer[pos] case var $1) {
            pos++;
          return $1;
          }
        }
      }
    }
  };

  /// ```
  /// @fragment fragment2
  /// ```
  late final f2 = () {
    if (this.pos case var mark) {
      if (this.matchPattern("\"") case (var $0 && null)) {
        this.pos = mark;
        if (pos < buffer.length) {
          if (buffer[pos] case var $1) {
            pos++;
          return $1;
          }
        }
      }
    }
  };

  /// ```
  /// @fragment fragment3
  /// ```
  late final f3 = () {
    if (this.pos case var mark) {
      if (this.matchPattern("'") case (var $0 && null)) {
        this.pos = mark;
        if (pos < buffer.length) {
          if (buffer[pos] case var $1) {
            pos++;
          return $1;
          }
        }
      }
    }
  };

  /// ```
  /// @fragment fragment4
  /// ```
  late final f4 = () {
    if (this.pos case var mark) {
      if (this.matchPattern("\\") case var $0?) {
        if (pos < buffer.length) {
          if (buffer[pos] case var $1) {
            pos++;
          return $1;
          }
        }
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.matchPattern("\$") case var $0?) {
          this.pos = mark;
          if (this.apply(this.r2) case var $1?) {
            return ($0, $1);
          }
        }
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.matchPattern("\"\"\"") case (var $0 && null)) {
          this.pos = mark;
          if (pos < buffer.length) {
            if (buffer[pos] case var $1) {
              pos++;
            return $1;
            }
          }
        }
      }
    }
  };

  /// ```
  /// @fragment fragment5
  /// ```
  late final f5 = () {
    if (this.pos case var mark) {
      if (this.matchPattern("\\") case var $0?) {
        if (pos < buffer.length) {
          if (buffer[pos] case var $1) {
            pos++;
          return $1;
          }
        }
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.matchPattern("\$") case var $0?) {
          this.pos = mark;
          if (this.apply(this.r2) case var $1?) {
            return ($0, $1);
          }
        }
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.matchPattern("'''") case (var $0 && null)) {
          this.pos = mark;
          if (pos < buffer.length) {
            if (buffer[pos] case var $1) {
              pos++;
            return $1;
            }
          }
        }
      }
    }
  };

  /// ```
  /// @fragment fragment6
  /// ```
  late final f6 = () {
    if (this.pos case var mark) {
      if (this.matchPattern("\\") case var $0?) {
        if (pos < buffer.length) {
          if (buffer[pos] case var $1) {
            pos++;
          return $1;
          }
        }
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.matchPattern("\$") case var $0?) {
          this.pos = mark;
          if (this.apply(this.r2) case var $1?) {
            return ($0, $1);
          }
        }
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.matchPattern("\"") case (var $0 && null)) {
          this.pos = mark;
          if (pos < buffer.length) {
            if (buffer[pos] case var $1) {
              pos++;
            return $1;
            }
          }
        }
      }
    }
  };

  /// ```
  /// @fragment fragment7
  /// ```
  late final f7 = () {
    if (this.pos case var mark) {
      if (this.matchPattern("\\") case var $0?) {
        if (pos < buffer.length) {
          if (buffer[pos] case var $1) {
            pos++;
          return $1;
          }
        }
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.matchPattern("\$") case var $0?) {
          this.pos = mark;
          if (this.apply(this.r2) case var $1?) {
            return ($0, $1);
          }
        }
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.matchPattern("'") case (var $0 && null)) {
          this.pos = mark;
          if (pos < buffer.length) {
            if (buffer[pos] case var $1) {
              pos++;
            return $1;
            }
          }
        }
      }
    }
  };

  /// ```
  /// @fragment fragment8
  /// ```
  late final f8 = () {
    if (this.pos case var mark) {
      if (this.matchPattern("{") case var $0?) {
        if (this.apply(this.r3)! case var $1) {
          if (this.matchPattern("}") case var $2?) {
            return $1;
          }
        }
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.matchPattern("{") case (var $0 && null)) {
          this.pos = mark;
          if (this.pos case var mark) {
            if (this.matchPattern("}") case (var $1 && null)) {
              this.pos = mark;
              if (pos < buffer.length) {
                if (buffer[pos] case var $2) {
                  pos++;
                return $2;
                }
              }
            }
          }
        }
      }
    }
  };

  /// ```
  /// @rule global::dart::literal::string
  /// ```
  Object? r0() {
    if (this.apply(this.r1) case var $?) {
      return $;
    }
  }

  /// ```
  /// @rule global::dart::literal::string::main
  /// ```
  Object? r1() {
    if (this.pos case var mark) {
      if (this.matchPattern("r") case var $0?) {
        if (this.matchPattern("\"\"\"") case var $1?) {
          if (this.pos case var mark) {
            if (this.f0() case var _0) {
              if ([if (_0 case var _0?) _0] case (var $2 && var body && var _loop2)) {
                if (_loop2.isNotEmpty) {
                  for (;;) {
                    if (this.pos case var mark) {
                      if (this.f0() case var _0?) {
                        _loop2.add(_0);
                        continue;
                      }
                      this.pos = mark;
                      break;
                    }
                  }
                } else {
                  this.pos = mark;
                }
                if (this.matchPattern("\"\"\"") case var $3?) {
                  return ($0, $1, $2, $3);
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern("r") case var $0?) {
        if (this.matchPattern("'''") case var $1?) {
          if (this.pos case var mark) {
            if (this.f1() case var _2) {
              if ([if (_2 case var _2?) _2] case (var $2 && var body && var _loop4)) {
                if (_loop4.isNotEmpty) {
                  for (;;) {
                    if (this.pos case var mark) {
                      if (this.f1() case var _2?) {
                        _loop4.add(_2);
                        continue;
                      }
                      this.pos = mark;
                      break;
                    }
                  }
                } else {
                  this.pos = mark;
                }
                if (this.matchPattern("'''") case var $3?) {
                  return ($0, $1, $2, $3);
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern("r") case var $0?) {
        if (this.matchPattern("\"") case var $1?) {
          if (this.pos case var mark) {
            if (this.f2() case var _4) {
              if ([if (_4 case var _4?) _4] case (var $2 && var body && var _loop6)) {
                if (_loop6.isNotEmpty) {
                  for (;;) {
                    if (this.pos case var mark) {
                      if (this.f2() case var _4?) {
                        _loop6.add(_4);
                        continue;
                      }
                      this.pos = mark;
                      break;
                    }
                  }
                } else {
                  this.pos = mark;
                }
                if (this.matchPattern("\"") case var $3?) {
                  return ($0, $1, $2, $3);
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern("r") case var $0?) {
        if (this.matchPattern("'") case var $1?) {
          if (this.pos case var mark) {
            if (this.f3() case var _6) {
              if ([if (_6 case var _6?) _6] case (var $2 && var body && var _loop8)) {
                if (_loop8.isNotEmpty) {
                  for (;;) {
                    if (this.pos case var mark) {
                      if (this.f3() case var _6?) {
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
                if (this.matchPattern("'") case var $3?) {
                  return ($0, $1, $2, $3);
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern("\"\"\"") case var $0?) {
        if (this.pos case var mark) {
          if (this.f4() case var _8) {
            if ([if (_8 case var _8?) _8] case (var $1 && var body && var _loop10)) {
              if (_loop10.isNotEmpty) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.f4() case var _8?) {
                      _loop10.add(_8);
                      continue;
                    }
                    this.pos = mark;
                    break;
                  }
                }
              } else {
                this.pos = mark;
              }
              if (this.matchPattern("\"\"\"") case var $2?) {
                return ($0, $1, $2);
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern("'''") case var $0?) {
        if (this.pos case var mark) {
          if (this.f5() case var _10) {
            if ([if (_10 case var _10?) _10] case (var $1 && var body && var _loop12)) {
              if (_loop12.isNotEmpty) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.f5() case var _10?) {
                      _loop12.add(_10);
                      continue;
                    }
                    this.pos = mark;
                    break;
                  }
                }
              } else {
                this.pos = mark;
              }
              if (this.matchPattern("'''") case var $2?) {
                return ($0, $1, $2);
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern("\"") case var $0?) {
        if (this.pos case var mark) {
          if (this.f6() case var _12) {
            if ([if (_12 case var _12?) _12] case (var $1 && var body && var _loop14)) {
              if (_loop14.isNotEmpty) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.f6() case var _12?) {
                      _loop14.add(_12);
                      continue;
                    }
                    this.pos = mark;
                    break;
                  }
                }
              } else {
                this.pos = mark;
              }
              if (this.matchPattern("\"") case var $2?) {
                return ($0, $1, $2);
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern("'") case var $0?) {
        if (this.pos case var mark) {
          if (this.f7() case var _14) {
            if ([if (_14 case var _14?) _14] case (var $1 && var body && var _loop16)) {
              if (_loop16.isNotEmpty) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.f7() case var _14?) {
                      _loop16.add(_14);
                      continue;
                    }
                    this.pos = mark;
                    break;
                  }
                }
              } else {
                this.pos = mark;
              }
              if (this.matchPattern("'") case var $2?) {
                return ($0, $1, $2);
              }
            }
          }
        }
      }
    }
  }

  /// ```
  /// @rule global::dart::literal::string::interpolation
  /// ```
  Object? r2() {
    if (this.pos case var mark) {
      if (this.matchPattern("\$") case var $0?) {
        if (this.matchPattern("{") case var $1?) {
          if (this.apply(this.r3)! case var $2) {
            if (this.matchPattern("}") case var $3?) {
              return ($0, $1, $2, $3);
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern("\$") case var $0?) {
        if (this.apply(this.r4) case var $1?) {
          return ($0, $1);
        }
      }
    }
  }

  /// ```
  /// @rule global::dart::literal::string::balanced
  /// ```
  Object r3() {
    if (this.pos case var mark) {
      if (this.f8() case var _0) {
        if ([if (_0 case var _0?) _0] case (var code && var _loop2)) {
          if (_loop2.isNotEmpty) {
            for (;;) {
              if (this.pos case var mark) {
                if (this.f8() case var _0?) {
                  _loop2.add(_0);
                  continue;
                }
                this.pos = mark;
                break;
              }
            }
          } else {
            this.pos = mark;
          }
          return _loop2;
        }
      }
    }
  }

  /// ```
  /// @rule global::dart::literal::identifier
  /// ```
  String? r4() {
    if (this.pos case var from) {
      if (this.matchRange({ (97, 122), (65, 90), (95, 95), (36, 36) }) case var $0?) {
        if (this.pos case var mark) {
          if (this.matchRange({ (97, 122), (65, 90), (48, 57), (95, 95), (36, 36) }) case var _0) {
            if ([if (_0 case var _0?) _0] case (var $1 && var _loop2)) {
              if (_loop2.isNotEmpty) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.matchRange({ (97, 122), (65, 90), (48, 57), (95, 95), (36, 36) }) case var _0?) {
                      _loop2.add(_0);
                      continue;
                    }
                    this.pos = mark;
                    break;
                  }
                }
              } else {
                this.pos = mark;
              }
              if (($0, $1) case var $) {
                if (this.pos case var to) {
                  return $0 + $1.join() ;
                }
              }
            }
          }
        }
      }
    }
  }

}
