// ignore_for_file: always_declare_return_types, always_put_control_body_on_new_line, always_specify_types, avoid_escaping_inner_quotes, avoid_redundant_argument_values, annotate_overrides, body_might_complete_normally_nullable, constant_pattern_never_matches_value_type, curly_braces_in_flow_control_structures, dead_code, directives_ordering, duplicate_ignore, inference_failure_on_function_return_type, constant_identifier_names, prefer_function_declarations_over_variables, prefer_interpolation_to_compose_strings, prefer_is_empty, no_leading_underscores_for_local_identifiers, non_constant_identifier_names, unnecessary_null_check_pattern, unnecessary_brace_in_string_interps, unnecessary_string_interpolations, unnecessary_this, unused_element, unused_import, prefer_double_quotes, unused_local_variable, unreachable_from_main, use_raw_strings, type_annotate_public_apis

// imports
// ignore_for_file: collection_methods_unrelated_type

import "dart:collection";
import "dart:math" as math;

import "package:parser_peg/src/generator.dart";
// PREAMBLE
import "package:parser_peg/src/node.dart";
import "package:parser_peg/src/statement.dart";

typedef ParserArgument = MapEntry<(String?, String), Node>;
typedef ParserArguments = ({Map<(String?, String), Node> rules, Map<(String?, String), Node> fragments});

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
final class PegParser extends _PegParser<ParserGenerator> {
  PegParser();

  @override
  get start => r0;

  String? f0() {
    if (this.pos case var mark) {
      if (this.pos case var from) {
        if (this.f73() case var _0) {
          if (this.pos case var mark) {
            if ([if (_0 case var _0?) _0] case (var $0 && var _loop2)) {
              if (_loop2.isNotEmpty) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.f73() case var _0?) {
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
              if (this.f10() case var $1?) {
                if (($0, $1) case var $) {
                  if (this.pos case var to) {
                    return $0.isEmpty ? $1 : "${$0.join("__")}__${$1}";
                  }
                }
              }
            }
          }
        }
      }

      this.pos = mark;
      if (this.pos case var from) {
        if (this.f15() case var $0?) {
          if (this.f74() case var _2) {
            if (this.pos case var mark) {
              if ([if (_2 case var _2?) _2] case (var $1 && var _loop4)) {
                if (_loop4.isNotEmpty) {
                  for (;;) {
                    if (this.pos case var mark) {
                      if (this.f74() case var _2?) {
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
                if (($0, $1) case var $) {
                  if (this.pos case var to) {
                    return $1.isEmpty ? $0 : "${$0}__${$1.join("__")}";
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  Node? f1() {
    if (this.pos case var from) {
      if (this.f53() case var $0?) {
        if (this.apply(this.r7) case (var $1 && var choice)?) {
          if (this.f52() case var $2?) {
            if (($0, $1, $2) case var $) {
              if (this.pos case var to) {
                return choice;
              }
            }
          }
        }
      }
    }
  }

  late final f2 = () {
    if (matchPattern("/") case var $0?) {
      if (this.f76() case var $1?) {
        if (matchPattern("/") case var $2?) {
          return $1;
        }
      }
    }
  };

  late final f3 = () {
    if (this.f66() case var $0) {
      if (this.f4() case var $1?) {
        if (this.f66() case var $2) {
          return $1;
        }
      }
    }
  };

  late final f4 = () {
    if (this.pos case var mark) {
      if (this.pos case var from) {
        if (matchPattern("r") case var $0?) {
          if (matchPattern("\"\"\"") case var $1?) {
            if (this.f77() case var _0) {
              if (this.pos case var mark) {
                if ([if (_0 case var _0?) _0] case (var $2 && var body && var _loop2)) {
                  if (_loop2.isNotEmpty) {
                    for (;;) {
                      if (this.pos case var mark) {
                        if (this.f77() case var _0?) {
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
                  if (matchPattern("\"\"\"") case var $3?) {
                    if (($0, $1, $2, $3) case var $) {
                      if (this.pos case var to) {
                        return body.join();
                      }
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
        if (matchPattern("r") case var $0?) {
          if (matchPattern("'''") case var $1?) {
            if (this.f78() case var _2) {
              if (this.pos case var mark) {
                if ([if (_2 case var _2?) _2] case (var $2 && var body && var _loop4)) {
                  if (_loop4.isNotEmpty) {
                    for (;;) {
                      if (this.pos case var mark) {
                        if (this.f78() case var _2?) {
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
                  if (matchPattern("'''") case var $3?) {
                    if (($0, $1, $2, $3) case var $) {
                      if (this.pos case var to) {
                        return body.join();
                      }
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
        if (matchPattern("r") case var $0?) {
          if (matchPattern("\"") case var $1?) {
            if (this.f79() case var _4) {
              if (this.pos case var mark) {
                if ([if (_4 case var _4?) _4] case (var $2 && var body && var _loop6)) {
                  if (_loop6.isNotEmpty) {
                    for (;;) {
                      if (this.pos case var mark) {
                        if (this.f79() case var _4?) {
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
                  if (matchPattern("\"") case var $3?) {
                    if (($0, $1, $2, $3) case var $) {
                      if (this.pos case var to) {
                        return body.join();
                      }
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
        if (matchPattern("r") case var $0?) {
          if (matchPattern("'") case var $1?) {
            if (this.f80() case var _6) {
              if (this.pos case var mark) {
                if ([if (_6 case var _6?) _6] case (var $2 && var body && var _loop8)) {
                  if (_loop8.isNotEmpty) {
                    for (;;) {
                      if (this.pos case var mark) {
                        if (this.f80() case var _6?) {
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
                  if (matchPattern("'") case var $3?) {
                    if (($0, $1, $2, $3) case var $) {
                      if (this.pos case var to) {
                        return body.join();
                      }
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
        if (matchPattern("\"\"\"") case var $0?) {
          if (this.f81() case var _8) {
            if (this.pos case var mark) {
              if ([if (_8 case var _8?) _8] case (var $1 && var body && var _loop10)) {
                if (_loop10.isNotEmpty) {
                  for (;;) {
                    if (this.pos case var mark) {
                      if (this.f81() case var _8?) {
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
                if (matchPattern("\"\"\"") case var $2?) {
                  if (($0, $1, $2) case var $) {
                    if (this.pos case var to) {
                      return body.join();
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
        if (matchPattern("'''") case var $0?) {
          if (this.f82() case var _10) {
            if (this.pos case var mark) {
              if ([if (_10 case var _10?) _10] case (var $1 && var body && var _loop12)) {
                if (_loop12.isNotEmpty) {
                  for (;;) {
                    if (this.pos case var mark) {
                      if (this.f82() case var _10?) {
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
                if (matchPattern("'''") case var $2?) {
                  if (($0, $1, $2) case var $) {
                    if (this.pos case var to) {
                      return body.join();
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
        if (matchPattern("\"") case var $0?) {
          if (this.f83() case var _12) {
            if (this.pos case var mark) {
              if ([if (_12 case var _12?) _12] case (var $1 && var body && var _loop14)) {
                if (_loop14.isNotEmpty) {
                  for (;;) {
                    if (this.pos case var mark) {
                      if (this.f83() case var _12?) {
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
                if (matchPattern("\"") case var $2?) {
                  if (($0, $1, $2) case var $) {
                    if (this.pos case var to) {
                      return body.join();
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
        if (matchPattern("'") case var $0?) {
          if (this.f84() case var _14) {
            if (this.pos case var mark) {
              if ([if (_14 case var _14?) _14] case (var $1 && var body && var _loop16)) {
                if (_loop16.isNotEmpty) {
                  for (;;) {
                    if (this.pos case var mark) {
                      if (this.f84() case var _14?) {
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
                if (matchPattern("'") case var $2?) {
                  if (($0, $1, $2) case var $) {
                    if (this.pos case var to) {
                      return body.join();
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  };

  late final f5 = () {
    if (this.f6() case var $?) {
      return $;
    }
  };

  late final f6 = () {
    if (this.pos case var from) {
      if (this.f47() case var $0?) {
        if (this.f7() case (var $1 && var elements)?) {
          if (this.f46() case var $2?) {
            if (($0, $1, $2) case var $) {
              if (this.pos case var to) {
                return RangeNode(elements);
              }
            }
          }
        }
      }
    }
  };

  late final f7 = () {
    if (this.pos case var from) {
      if (this.f8() case var _0?) {
        if ([_0] case (var $ && var _loop2)) {
          for (;;) {
            if (this.pos case var mark) {
              if (this.f66() case var _) {
                if (this.f8() case var _0?) {
                  _loop2.add(_0);
                  continue;
                }
              }
              this.pos = mark;
              break;
            }
          }
          if (this.pos case var to) {
            return $.toSet();
          }
        }
      }
    }
  };

  late final f8 = () {
    if (this.pos case var mark) {
      if (this.pos case var from) {
        if (this.f9() case (var $0 && var l)?) {
          if (matchPattern("-") case var $1?) {
            if (this.f9() case (var $2 && var r)?) {
              if (($0, $1, $2) case var $) {
                if (this.pos case var to) {
                  return (l.codeUnitAt(0), r.codeUnitAt(0));
                }
              }
            }
          }
        }
      }

      this.pos = mark;
      if (this.pos case var from) {
        if (this.f9() case var $?) {
          if (this.pos case var to) {
            return ($.codeUnitAt(0), $.codeUnitAt(0));
          }
        }
      }
    }
  };

  late final f9 = () {
    if (this.pos case var mark) {
      if (matchPattern("]") case (var $0 && null)) {
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

  late final f10 = () {
    if (this.pos case var from) {
      if (matchPattern("`") case var $0?) {
        if (this.f85() case var _0) {
          if (this.pos case var mark) {
            if ([if (_0 case var _0?) _0] case (var $1 && var inner && var _loop2)) {
              if (_loop2.isNotEmpty) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.f85() case var _0?) {
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
              if (matchPattern("`") case var $2?) {
                if (($0, $1, $2) case var $) {
                  if (this.pos case var to) {
                    StringBuffer buffer = StringBuffer(r"$");

                    for (var (int i, String character) in inner.indexed) {
                      int unit = character.codeUnits.single;

                      if (64 + 1 <= unit && unit <= 64 + 26 || 96 + 1 <= unit && unit <= 96 + 26) {
                        buffer.write(character);
                      } else {
                        buffer.write(unit);
                        if (i < inner.length - 1) {
                          buffer.write("_");
                        }
                      }
                    }

                    return buffer.toString();
                  }
                }
              }
            }
          }
        }
      }
    }
  };

  String? f11() {
    if (this.pos case var from) {
      if (this.f13() case var _0?) {
        if ([_0] case (var $ && var _loop2)) {
          for (;;) {
            if (this.pos case var mark) {
              if (this.f59() case var _?) {
                if (this.f13() case var _0?) {
                  _loop2.add(_0);
                  continue;
                }
              }
              this.pos = mark;
              break;
            }
          }
          if (this.pos case var to) {
            return $.join(", ");
          }
        }
      }
    }
  }

  String? f12() {
    if (this.pos case var from) {
      if (this.f14() case var _0?) {
        if ([_0] case (var $ && var _loop2)) {
          for (;;) {
            if (this.pos case var mark) {
              if (this.f59() case var _?) {
                if (this.f14() case var _0?) {
                  _loop2.add(_0);
                  continue;
                }
              }
              this.pos = mark;
              break;
            }
          }
          if (this.pos case var to) {
            return $.join(", ");
          }
        }
      }
    }
  }

  String? f13() {
    if (this.pos case var from) {
      if (this.apply(this.r17) case var $0?) {
        if (this.f66() case var $1) {
          if (this.f15() case var $2) {
            if (($0, $1, $2) case var $) {
              if (this.pos case var to) {
                return "${$0} ${$2 ?? ""}".trimRight();
              }
            }
          }
        }
      }
    }
  }

  String? f14() {
    if (this.pos case var from) {
      if (this.apply(this.r17) case var $0?) {
        if (this.f66() case var $1) {
          if (this.f15() case var $2?) {
            if (($0, $1, $2) case var $) {
              if (this.pos case var to) {
                return "${$0} ${$2}";
              }
            }
          }
        }
      }
    }
  }

  String? f15() {
    if (matchPattern(_regexp.$1) case var $?) {
      return $;
    }
  }

  int? f16() {
    if (this.pos case var from) {
      if (matchPattern(_regexp.$2) case var _0?) {
        if ([_0] case (var $ && var _loop2)) {
          for (;;) {
            if (this.pos case var mark) {
              if (matchPattern(_regexp.$2) case var _0?) {
                _loop2.add(_0);
                continue;
              }
              this.pos = mark;
              break;
            }
          }
          if (this.pos case var to) {
            return int.parse($.join());
          }
        }
      }
    }
  }

  late final f17 = () {
    if (this.f66() case var $0) {
      if (matchPattern("@rule") case var $1?) {
        if (this.f66() case var $2) {
          return $1;
        }
      }
    }
  };

  late final f18 = () {
    if (this.f66() case var $0) {
      if (matchPattern("@fragment") case var $1?) {
        if (this.f66() case var $2) {
          return $1;
        }
      }
    }
  };

  late final f19 = () {
    if (this.f66() case var $0) {
      if (matchPattern("startOfInput") case var $1?) {
        if (this.f66() case var $2) {
          return $1;
        }
      }
    }
  };

  late final f20 = () {
    if (this.f66() case var $0) {
      if (matchPattern("endOfInput") case var $1?) {
        if (this.f66() case var $2) {
          return $1;
        }
      }
    }
  };

  late final f21 = () {
    if (this.f66() case var $0) {
      if (matchPattern("backslash") case var $1?) {
        if (this.f66() case var $2) {
          return $1;
        }
      }
    }
  };

  late final f22 = () {
    if (this.f66() case var $0) {
      if (matchPattern("epsilon") case var $1?) {
        if (this.f66() case var $2) {
          return $1;
        }
      }
    }
  };

  late final f23 = () {
    if (this.f66() case var $0) {
      if (matchPattern("any") case var $1?) {
        if (this.f66() case var $2) {
          return $1;
        }
      }
    }
  };

  late final f24 = () {
    if (this.f66() case var $0) {
      if (matchPattern("var") case var $1?) {
        if (this.f66() case var $2) {
          return $1;
        }
      }
    }
  };

  late final f25 = () {
    if (this.f66() case var $0) {
      if (matchPattern("sep!") case var $1?) {
        if (this.f66() case var $2) {
          return $1;
        }
      }
    }
  };

  late final f26 = () {
    if (this.f66() case var $0) {
      if (this.f86() case var $1?) {
        if (this.f66() case var $2) {
          return $1;
        }
      }
    }
  };

  late final f27 = () {
    if (this.f66() case var $0) {
      if (this.f87() case var $1?) {
        if (this.f66() case var $2) {
          return $1;
        }
      }
    }
  };

  late final f28 = () {
    if (this.f66() case var $0) {
      if (this.f88() case var $1?) {
        if (this.f66() case var $2) {
          return $1;
        }
      }
    }
  };

  late final f29 = () {
    if (this.f66() case var $0) {
      if (this.f89() case var $1?) {
        if (this.f66() case var $2) {
          return $1;
        }
      }
    }
  };

  late final f30 = () {
    if (this.f66() case var $0) {
      if (this.f90() case var $1?) {
        if (this.f66() case var $2) {
          return $1;
        }
      }
    }
  };

  late final f31 = () {
    if (this.f66() case var $0) {
      if (this.f91() case var $1?) {
        if (this.f66() case var $2) {
          return $1;
        }
      }
    }
  };

  late final f32 = () {
    if (this.f66() case var $0) {
      if (this.f92() case var $1?) {
        if (this.f66() case var $2) {
          return $1;
        }
      }
    }
  };

  late final f33 = () {
    if (this.f66() case var $0) {
      if (this.f93() case var $1?) {
        if (this.f66() case var $2) {
          return $1;
        }
      }
    }
  };

  late final f34 = () {
    if (this.f66() case var $0) {
      if (this.f94() case var $1?) {
        if (this.f66() case var $2) {
          return $1;
        }
      }
    }
  };

  late final f35 = () {
    if (this.f66() case var $0) {
      if (this.f95() case var $1?) {
        if (this.f66() case var $2) {
          return $1;
        }
      }
    }
  };

  late final f36 = () {
    if (this.f66() case var $0) {
      if (this.f96() case var $1?) {
        if (this.f66() case var $2) {
          return $1;
        }
      }
    }
  };

  late final f37 = () {
    if (this.f66() case var $0) {
      if (this.f97() case var $1?) {
        if (this.f66() case var $2) {
          return $1;
        }
      }
    }
  };

  late final f38 = () {
    if (this.f66() case var $0) {
      if (this.f98() case var $1?) {
        if (this.f66() case var $2) {
          return $1;
        }
      }
    }
  };

  late final f39 = () {
    if (this.f66() case var $0) {
      if (matchPattern("..") case var $1?) {
        if (this.f66() case var $2) {
          return $1;
        }
      }
    }
  };

  late final f40 = () {
    if (this.f66() case var $0) {
      if (matchPattern("::") case var $1?) {
        if (this.f66() case var $2) {
          return $1;
        }
      }
    }
  };

  late final f41 = () {
    if (this.f66() case var $0) {
      if (matchPattern("%%") case var $1?) {
        if (this.f66() case var $2) {
          return $1;
        }
      }
    }
  };

  late final f42 = () {
    if (this.f66() case var $0) {
      if (matchPattern("=>") case var $1?) {
        if (this.f66() case var $2) {
          return $1;
        }
      }
    }
  };

  late final f43 = () {
    if (this.f66() case var $0) {
      if (matchPattern("@") case var $1?) {
        if (this.f66() case var $2) {
          return $1;
        }
      }
    }
  };

  late final f44 = () {
    if (this.f66() case var $0) {
      if (matchPattern("<") case var $1?) {
        if (this.f66() case var $2) {
          return $1;
        }
      }
    }
  };

  late final f45 = () {
    if (this.f66() case var $0) {
      if (matchPattern(">") case var $1?) {
        if (this.f66() case var $2) {
          return $1;
        }
      }
    }
  };

  late final f46 = () {
    if (this.f66() case var $0) {
      if (matchPattern("]") case var $1?) {
        if (this.f66() case var $2) {
          return $1;
        }
      }
    }
  };

  late final f47 = () {
    if (this.f66() case var $0) {
      if (matchPattern("[") case var $1?) {
        if (this.f66() case var $2) {
          return $1;
        }
      }
    }
  };

  late final f48 = () {
    if (this.f66() case var $0) {
      if (matchPattern("}") case var $1?) {
        if (this.f66() case var $2) {
          return $1;
        }
      }
    }
  };

  late final f49 = () {
    if (this.f66() case var $0) {
      if (matchPattern("{") case var $1?) {
        if (this.f66() case var $2) {
          return $1;
        }
      }
    }
  };

  late final f50 = () {
    if (this.f66() case var $0) {
      if (matchPattern(")") case var $1?) {
        if (this.f66() case var $2) {
          return $1;
        }
      }
    }
  };

  late final f51 = () {
    if (this.f66() case var $0) {
      if (matchPattern("(") case var $1?) {
        if (this.f66() case var $2) {
          return $1;
        }
      }
    }
  };

  late final f52 = () {
    if (this.f66() case var $0) {
      if (matchPattern(";") case var $1?) {
        if (this.f66() case var $2) {
          return $1;
        }
      }
    }
  };

  late final f53 = () {
    if (this.f66() case var $0) {
      if (matchPattern("=") case var $1?) {
        if (this.f66() case var $2) {
          return $1;
        }
      }
    }
  };

  late final f54 = () {
    if (this.f66() case var $0) {
      if (matchPattern("?") case var $1?) {
        if (this.f66() case var $2) {
          return $1;
        }
      }
    }
  };

  late final f55 = () {
    if (this.f66() case var $0) {
      if (matchPattern("!") case var $1?) {
        if (this.f66() case var $2) {
          return $1;
        }
      }
    }
  };

  late final f56 = () {
    if (this.f66() case var $0) {
      if (matchPattern("&") case var $1?) {
        if (this.f66() case var $2) {
          return $1;
        }
      }
    }
  };

  late final f57 = () {
    if (this.f66() case var $0) {
      if (matchPattern("*") case var $1?) {
        if (this.f66() case var $2) {
          return $1;
        }
      }
    }
  };

  late final f58 = () {
    if (this.f66() case var $0) {
      if (matchPattern("+") case var $1?) {
        if (this.f66() case var $2) {
          return $1;
        }
      }
    }
  };

  late final f59 = () {
    if (this.f66() case var $0) {
      if (matchPattern(",") case var $1?) {
        if (this.f66() case var $2) {
          return $1;
        }
      }
    }
  };

  late final f60 = () {
    if (this.f66() case var $0) {
      if (matchPattern(":") case var $1?) {
        if (this.f66() case var $2) {
          return $1;
        }
      }
    }
  };

  late final f61 = () {
    if (this.f66() case var $0) {
      if (matchPattern("|") case var $1?) {
        if (this.f66() case var $2) {
          return $1;
        }
      }
    }
  };

  late final f62 = () {
    if (this.f66() case var $0) {
      if (matchPattern(".") case var $1?) {
        if (this.f66() case var $2) {
          return $1;
        }
      }
    }
  };

  late final f63 = () {
    if (this.f66() case var $0) {
      if (matchPattern("ε") case var $1?) {
        if (this.f66() case var $2) {
          return $1;
        }
      }
    }
  };

  late final f64 = () {
    if (this.f66() case var $0) {
      if (matchPattern("^") case var $1?) {
        if (this.f66() case var $2) {
          return $1;
        }
      }
    }
  };

  late final f65 = () {
    if (this.f66() case var $0) {
      if (matchPattern("\$") case var $1?) {
        if (this.f66() case var $2) {
          return $1;
        }
      }
    }
  };

  late final f66 = () {
    if (this.pos case var from) {
      if (this.f99() case var _0) {
        if (this.pos case var mark) {
          if ([if (_0 case var _0?) _0] case (var $ && var _loop2)) {
            if (_loop2.isNotEmpty) {
              for (;;) {
                if (this.pos case var mark) {
                  if (this.f99() case var _0?) {
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
            if (this.pos case var to) {
              return "";
            }
          }
        }
      }
    }
  };

  late final f67 = () {
    if (this.pos case var mark) {
      if (this.f43() case var $?) {
        return $;
      }
      this.pos = mark;
      if (this.f42() case var $?) {
        return $;
      }
    }
  };

  late final f68 = () {
    if (this.pos case var mark) {
      if (this.pos case var mark) {
        if (matchPattern("{") case (var $0 && null)) {
          this.pos = mark;
          if (this.pos case var mark) {
            if (matchPattern("}") case (var $1 && null)) {
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

      this.pos = mark;
      if (this.pos case var from) {
        if (matchPattern("{") case var $0?) {
          if (this.apply(this.r16)! case (var $1 && var rawCode)) {
            if (matchPattern("}") case var $2?) {
              if ($1 case var $) {
                if (this.pos case var to) {
                  return "{" + $ + "}";
                }
              }
            }
          }
        }
      }
    }
  };

  late final f69 = () {
    if (this.pos case var mark) {
      if (this.apply(this.r20) case var $?) {
        return $;
      }
      this.pos = mark;
      if (this.apply(this.r19) case var $?) {
        return $;
      }
      this.pos = mark;
      if (this.apply(this.r22) case var $?) {
        return $;
      }
    }
  };

  late final f70 = () {
    if (this.f49() case var $0?) {
      if (this.f12() case var $1?) {
        if (this.f48() case var $2?) {
          return $1;
        }
      }
    }
  };

  late final f71 = () {
    if (this.f49() case var $0?) {
      if (this.f12() case var $1?) {
        if (this.f48() case var $2?) {
          return $1;
        }
      }
    }
  };

  late final f72 = () {
    if (this.f59() case var $0?) {
      if (this.f49() case var $1?) {
        if (this.f12() case var $2?) {
          if (this.f48() case var $3?) {
            return $2;
          }
        }
      }
    }
  };

  late final f73 = () {
    if (this.f15() case var $0?) {
      if (matchPattern("::") case var $1?) {
        return $0;
      }
    }
  };

  late final f74 = () {
    if (matchPattern("::") case var $0?) {
      if (this.f15() case var $1?) {
        return $1;
      }
    }
  };

  late final f75 = () {
    if (this.pos case var mark) {
      if (this.pos case var from) {
        if (matchPattern("\\") case var $0?) {
          if (pos < buffer.length) {
            if (buffer[pos] case var $1) {
              pos++;
              if ($1 case var $) {
                if (this.pos case var to) {
                  return r"\" + $;
                }
              }
            }
          }
        }
      }

      this.pos = mark;
      if (this.pos case var mark) {
        if (matchPattern("/") case (var $0 && null)) {
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

  late final f76 = () {
    if (this.pos case var from) {
      if (this.f75() case var _0?) {
        if ([_0] case (var $ && var _loop2)) {
          for (;;) {
            if (this.pos case var mark) {
              if (this.f75() case var _0?) {
                _loop2.add(_0);
                continue;
              }
              this.pos = mark;
              break;
            }
          }
          if (this.pos case var to) {
            return $.join();
          }
        }
      }
    }
  };

  late final f77 = () {
    if (this.pos case var mark) {
      if (matchPattern("\"\"\"") case (var $0 && null)) {
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

  late final f78 = () {
    if (this.pos case var mark) {
      if (matchPattern("'''") case (var $0 && null)) {
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

  late final f79 = () {
    if (this.pos case var mark) {
      if (matchPattern("\"") case (var $0 && null)) {
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

  late final f80 = () {
    if (this.pos case var mark) {
      if (matchPattern("'") case (var $0 && null)) {
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

  late final f81 = () {
    if (this.pos case var mark) {
      if (matchPattern("\\") case var $0?) {
        if (pos < buffer.length) {
          if (buffer[pos] case var $1) {
            pos++;
            return $1;
          }
        }
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (matchPattern("\"\"\"") case (var $0 && null)) {
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

  late final f82 = () {
    if (this.pos case var mark) {
      if (matchPattern("\\") case var $0?) {
        if (pos < buffer.length) {
          if (buffer[pos] case var $1) {
            pos++;
            return $1;
          }
        }
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (matchPattern("'''") case (var $0 && null)) {
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

  late final f83 = () {
    if (this.pos case var mark) {
      if (matchPattern("\\") case var $0?) {
        if (pos < buffer.length) {
          if (buffer[pos] case var $1) {
            pos++;
            return $1;
          }
        }
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (matchPattern("\"") case (var $0 && null)) {
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

  late final f84 = () {
    if (this.pos case var mark) {
      if (matchPattern("\\") case var $0?) {
        if (pos < buffer.length) {
          if (buffer[pos] case var $1) {
            pos++;
            return $1;
          }
        }
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (matchPattern("'") case (var $0 && null)) {
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

  late final f85 = () {
    if (this.pos case var mark) {
      if (matchPattern("`") case (var $0 && null)) {
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

  late final f86 = () {
    if (this.pos case var from) {
      if (matchPattern("\\") case var $0?) {
        if (matchPattern("\\") case var $1?) {
          if (($0, $1) case var $) {
            if (this.pos case var to) {
              return buffer.substring(from, to);
            }
          }
        }
      }
    }
  };

  late final f87 = () {
    if (this.pos case var from) {
      if (matchPattern("\\") case var $0?) {
        if (matchPattern("d") case var $1?) {
          if (($0, $1) case var $) {
            if (this.pos case var to) {
              return buffer.substring(from, to);
            }
          }
        }
      }
    }
  };

  late final f88 = () {
    if (this.pos case var from) {
      if (matchPattern("\\") case var $0?) {
        if (matchPattern("w") case var $1?) {
          if (($0, $1) case var $) {
            if (this.pos case var to) {
              return buffer.substring(from, to);
            }
          }
        }
      }
    }
  };

  late final f89 = () {
    if (this.pos case var from) {
      if (matchPattern("\\") case var $0?) {
        if (matchPattern("s") case var $1?) {
          if (($0, $1) case var $) {
            if (this.pos case var to) {
              return buffer.substring(from, to);
            }
          }
        }
      }
    }
  };

  late final f90 = () {
    if (this.pos case var from) {
      if (matchPattern("\\") case var $0?) {
        if (matchPattern("t") case var $1?) {
          if (($0, $1) case var $) {
            if (this.pos case var to) {
              return buffer.substring(from, to);
            }
          }
        }
      }
    }
  };

  late final f91 = () {
    if (this.pos case var from) {
      if (matchPattern("\\") case var $0?) {
        if (matchPattern("f") case var $1?) {
          if (($0, $1) case var $) {
            if (this.pos case var to) {
              return buffer.substring(from, to);
            }
          }
        }
      }
    }
  };

  late final f92 = () {
    if (this.pos case var from) {
      if (matchPattern("\\") case var $0?) {
        if (matchPattern("v") case var $1?) {
          if (($0, $1) case var $) {
            if (this.pos case var to) {
              return buffer.substring(from, to);
            }
          }
        }
      }
    }
  };

  late final f93 = () {
    if (this.pos case var from) {
      if (matchPattern("\\") case var $0?) {
        if (matchPattern("0") case var $1?) {
          if (($0, $1) case var $) {
            if (this.pos case var to) {
              return buffer.substring(from, to);
            }
          }
        }
      }
    }
  };

  late final f94 = () {
    if (this.pos case var from) {
      if (matchPattern("\\") case var $0?) {
        if (matchPattern("c") case var $1?) {
          if (($0, $1) case var $) {
            if (this.pos case var to) {
              return buffer.substring(from, to);
            }
          }
        }
      }
    }
  };

  late final f95 = () {
    if (this.pos case var from) {
      if (matchPattern("\\") case var $0?) {
        if (matchPattern("x") case var $1?) {
          if (($0, $1) case var $) {
            if (this.pos case var to) {
              return buffer.substring(from, to);
            }
          }
        }
      }
    }
  };

  late final f96 = () {
    if (this.pos case var from) {
      if (matchPattern("\\") case var $0?) {
        if (matchPattern("u") case var $1?) {
          if (($0, $1) case var $) {
            if (this.pos case var to) {
              return buffer.substring(from, to);
            }
          }
        }
      }
    }
  };

  late final f97 = () {
    if (this.pos case var from) {
      if (matchPattern("\\") case var $0?) {
        if (matchPattern("U") case var $1?) {
          if (($0, $1) case var $) {
            if (this.pos case var to) {
              return buffer.substring(from, to);
            }
          }
        }
      }
    }
  };

  late final f98 = () {
    if (this.pos case var from) {
      if (matchPattern("\\") case var $0?) {
        if (matchPattern(".") case var $1?) {
          if (($0, $1) case var $) {
            if (this.pos case var to) {
              return buffer.substring(from, to);
            }
          }
        }
      }
    }
  };

  late final f99 = () {
    if (this.pos case var mark) {
      if (matchPattern(_regexp.$3) case var $?) {
        return $;
      }
      this.pos = mark;
      if (matchPattern(_regexp.$4) case var $?) {
        return $;
      }
    }
  };

  ParserGenerator? r0() {
    if (this.pos case var from) {
      if (this.pos case var $0 when this.pos <= 0) {
        if (this.apply(this.r1) case (var $1 && var preamble)) {
          if (this.apply(this.r2) case var _0?) {
            if ([_0] case (var $2 && var statements && var _loop2)) {
              for (;;) {
                if (this.pos case var mark) {
                  if (this.f66() case var _) {
                    if (this.apply(this.r2) case var _0?) {
                      _loop2.add(_0);
                      continue;
                    }
                  }
                  this.pos = mark;
                  break;
                }
              }
              if (this.pos case var mark) {
                if (this.f66() case null) {
                  this.pos = mark;
                }
              }
              if (this.pos case var $3 when this.pos >= this.buffer.length) {
                if (($0, $1, $2, $3) case var $) {
                  if (this.pos case var to) {
                    return ParserGenerator.fromParsed(preamble: preamble, statements: statements);
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  String? r1() {
    if (this.pos case var from) {
      if (this.f49() case var $0?) {
        if (this.f66() case var $1) {
          if (this.apply(this.r16)! case (var $2 && var rawCode)) {
            if (this.f66() case var $3) {
              if (this.f48() case var $4?) {
                if (($0, $1, $2, $3, $4) case var $) {
                  if (this.pos case var to) {
                    return rawCode;
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  Statement? r2() {
    if (this.pos case var mark) {
      if (this.apply(this.r3) case var $?) {
        return $;
      }
      this.pos = mark;
      if (this.apply(this.r5) case var $?) {
        return $;
      }
      this.pos = mark;
      if (this.apply(this.r4) case var $?) {
        return $;
      }
      this.pos = mark;
      if (this.apply(this.r6) case var $?) {
        return $;
      }
    }
  }

  Statement? r3() {
    if (this.pos case var mark) {
      if (this.pos case var from) {
        if (this.f18() case var $0?) {
          if (this.f15() case (var $1 && var name)) {
            if (this.f49() case var $2?) {
              if (this.apply(this.r2) case var _0?) {
                if ([_0] case (var $3 && var statements && var _loop2)) {
                  for (;;) {
                    if (this.pos case var mark) {
                      if (this.f66() case var _) {
                        if (this.apply(this.r2) case var _0?) {
                          _loop2.add(_0);
                          continue;
                        }
                      }
                      this.pos = mark;
                      break;
                    }
                  }
                  if (this.f48() case var $4?) {
                    if (($0, $1, $2, $3, $4) case var $) {
                      if (this.pos case var to) {
                        return NamespaceStatement(name, statements, tag: Tag.fragment);
                      }
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
        if (this.f17() case var $0?) {
          if (this.f15() case (var $1 && var name)) {
            if (this.f49() case var $2?) {
              if (this.apply(this.r2) case var _2?) {
                if ([_2] case (var $3 && var statements && var _loop4)) {
                  for (;;) {
                    if (this.pos case var mark) {
                      if (this.f66() case var _) {
                        if (this.apply(this.r2) case var _2?) {
                          _loop4.add(_2);
                          continue;
                        }
                      }
                      this.pos = mark;
                      break;
                    }
                  }
                  if (this.f48() case var $4?) {
                    if (($0, $1, $2, $3, $4) case var $) {
                      if (this.pos case var to) {
                        return NamespaceStatement(name, statements, tag: Tag.rule);
                      }
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
        if (this.f15() case (var $0 && var name)) {
          if (this.f49() case var $1?) {
            if (this.apply(this.r2) case var _4?) {
              if ([_4] case (var $2 && var statements && var _loop6)) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.f66() case var _) {
                      if (this.apply(this.r2) case var _4?) {
                        _loop6.add(_4);
                        continue;
                      }
                    }
                    this.pos = mark;
                    break;
                  }
                }
                if (this.f48() case var $3?) {
                  if (($0, $1, $2, $3) case var $) {
                    if (this.pos case var to) {
                      return NamespaceStatement(name, statements, tag: Tag.none);
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  Statement? r4() {
    if (this.pos case var mark) {
      if (this.pos case var from) {
        if (this.f17() case var $0) {
          if (this.f24() case var $1?) {
            if (this.f0() case (var $2 && var name)?) {
              if (this.f1() case (var $3 && var body)?) {
                if (($0, $1, $2, $3) case var $) {
                  if (this.pos case var to) {
                    return DeclarationStatement(MapEntry((null, name), body), tag: $0 == null ? Tag.none : Tag.rule);
                  }
                }
              }
            }
          }
        }
      }

      this.pos = mark;
      if (this.pos case var from) {
        if (this.f17() case var $0) {
          if (this.f0() case (var $1 && var name)?) {
            if (this.f1() case (var $2 && var body)?) {
              if (($0, $1, $2) case var $) {
                if (this.pos case var to) {
                  return DeclarationStatement(MapEntry((null, name), body), tag: $0 == null ? Tag.none : Tag.rule);
                }
              }
            }
          }
        }
      }

      this.pos = mark;
      if (this.pos case var from) {
        if (this.f17() case var $0) {
          if (this.apply(this.r18) case (var $1 && var type)?) {
            if (this.f0() case (var $2 && var name)?) {
              if (this.f1() case (var $3 && var body)?) {
                if (($0, $1, $2, $3) case var $) {
                  if (this.pos case var to) {
                    return DeclarationStatement(MapEntry((type, name), body), tag: $0 == null ? Tag.none : Tag.rule);
                  }
                }
              }
            }
          }
        }
      }

      this.pos = mark;
      if (this.pos case var from) {
        if (this.f17() case var $0) {
          if (this.f0() case (var $1 && var name)?) {
            if (this.f60() case var $2?) {
              if (this.apply(this.r18) case (var $3 && var type)?) {
                if (this.f1() case (var $4 && var body)?) {
                  if (($0, $1, $2, $3, $4) case var $) {
                    if (this.pos case var to) {
                      return DeclarationStatement(MapEntry((type, name), body), tag: $0 == null ? Tag.none : Tag.rule);
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  Statement? r5() {
    if (this.pos case var mark) {
      if (this.pos case var from) {
        if (this.f18() case var $0?) {
          if (this.f24() case var $1?) {
            if (this.f0() case (var $2 && var name)?) {
              if (this.f1() case (var $3 && var body)?) {
                if (($0, $1, $2, $3) case var $) {
                  if (this.pos case var to) {
                    return DeclarationStatement(MapEntry((null, name), body), tag: Tag.fragment);
                  }
                }
              }
            }
          }
        }
      }

      this.pos = mark;
      if (this.pos case var from) {
        if (this.f18() case var $0?) {
          if (this.f0() case (var $1 && var name)?) {
            if (this.f1() case (var $2 && var body)?) {
              if (($0, $1, $2) case var $) {
                if (this.pos case var to) {
                  return DeclarationStatement(MapEntry((null, name), body), tag: Tag.fragment);
                }
              }
            }
          }
        }
      }

      this.pos = mark;
      if (this.pos case var from) {
        if (this.f18() case var $0?) {
          if (this.apply(this.r18) case (var $1 && var type)?) {
            if (this.f0() case (var $2 && var name)?) {
              if (this.f1() case (var $3 && var body)?) {
                if (($0, $1, $2, $3) case var $) {
                  if (this.pos case var to) {
                    return DeclarationStatement(MapEntry((type, name), body), tag: Tag.fragment);
                  }
                }
              }
            }
          }
        }
      }

      this.pos = mark;
      if (this.pos case var from) {
        if (this.f18() case var $0?) {
          if (this.f0() case (var $1 && var name)?) {
            if (this.f60() case var $2?) {
              if (this.apply(this.r18) case (var $3 && var type)?) {
                if (this.f1() case (var $4 && var body)?) {
                  if (($0, $1, $2, $3, $4) case var $) {
                    if (this.pos case var to) {
                      return DeclarationStatement(MapEntry((type, name), body), tag: Tag.fragment);
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  Statement? r6() {
    if (this.pos case var mark) {
      if (this.pos case var from) {
        if (this.f24() case var $0?) {
          if (this.f0() case (var $1 && var name)?) {
            if (this.f1() case (var $2 && var body)?) {
              if (($0, $1, $2) case var $) {
                if (this.pos case var to) {
                  return DeclarationStatement(MapEntry((null, name), body), tag: Tag.none);
                }
              }
            }
          }
        }
      }

      this.pos = mark;
      if (this.pos case var from) {
        if (this.f0() case (var $0 && var name)?) {
          if (this.f1() case (var $1 && var body)?) {
            if (($0, $1) case var $) {
              if (this.pos case var to) {
                return DeclarationStatement(MapEntry((null, name), body), tag: Tag.none);
              }
            }
          }
        }
      }

      this.pos = mark;
      if (this.pos case var from) {
        if (this.apply(this.r18) case (var $0 && var type)?) {
          if (this.f0() case (var $1 && var name)?) {
            if (this.f1() case (var $2 && var body)?) {
              if (($0, $1, $2) case var $) {
                if (this.pos case var to) {
                  return DeclarationStatement(MapEntry((type, name), body), tag: Tag.none);
                }
              }
            }
          }
        }
      }

      this.pos = mark;
      if (this.pos case var from) {
        if (this.f0() case (var $0 && var name)?) {
          if (this.f60() case var $1?) {
            if (this.apply(this.r18) case (var $2 && var type)?) {
              if (this.f1() case (var $3 && var body)?) {
                if (($0, $1, $2, $3) case var $) {
                  if (this.pos case var to) {
                    return DeclarationStatement(MapEntry((type, name), body), tag: Tag.none);
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  Node? r7() {
    if (this.pos case var from) {
      if (this.f61() case var $0) {
        if (this.apply(this.r8) case var _0?) {
          if ([_0] case (var $1 && var options && var _loop2)) {
            for (;;) {
              if (this.pos case var mark) {
                if (this.f61() case var _?) {
                  if (this.apply(this.r8) case var _0?) {
                    _loop2.add(_0);
                    continue;
                  }
                }
                this.pos = mark;
                break;
              }
            }
            if (($0, $1) case var $) {
              if (this.pos case var to) {
                return options.length == 1 ? options.single : ChoiceNode(options);
              }
            }
          }
        }
      }
    }
  }

  Node? r8() {
    if (this.pos case var mark) {
      if (this.pos case var from) {
        if (this.apply(this.r9) case (var $0 && var sequence)?) {
          if (this.f51() case var $1?) {
            if (this.f50() case var $2?) {
              if (this.f49() case var $3?) {
                if (this.f66() case var $4) {
                  if (this.apply(this.r16)! case (var $5 && var rawCode)) {
                    if (this.f66() case var $6) {
                      if (this.f48() case var $7?) {
                        if (($0, $1, $2, $3, $4, $5, $6, $7) case var $) {
                          if (this.pos case var to) {
                            return ActionNode(sequence, rawCode, areIndicesProvided: true);
                          }
                        }
                      }
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
        if (this.apply(this.r9) case (var $0 && var sequence)?) {
          if (this.f49() case var $1?) {
            if (this.f66() case var $2) {
              if (this.apply(this.r16)! case (var $3 && var rawCode)) {
                if (this.f66() case var $4) {
                  if (this.f48() case var $5?) {
                    if (($0, $1, $2, $3, $4, $5) case var $) {
                      if (this.pos case var to) {
                        return InlineActionNode(sequence, rawCode, areIndicesProvided: true);
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }

      this.pos = mark;
      if (this.apply(this.r9) case var $?) {
        return $;
      }
    }
  }

  Node? r9() {
    if (this.pos case var mark) {
      if (this.pos case var from) {
        if (this.apply(this.r10) case var _0?) {
          if ([_0] case (var $0 && var body && var _loop2)) {
            for (;;) {
              if (this.pos case var mark) {
                if (this.f66() case var _) {
                  if (this.apply(this.r10) case var _0?) {
                    _loop2.add(_0);
                    continue;
                  }
                }
                this.pos = mark;
                break;
              }
            }
            if (this.f67() case var $1?) {
              if (this.f16() case (var $2 && var number)?) {
                if (($0, $1, $2) case var $) {
                  if (this.pos case var to) {
                    return body.length == 1 ? body.single : SequenceNode(body, choose: number);
                  }
                }
              }
            }
          }
        }
      }

      this.pos = mark;
      if (this.pos case var from) {
        if (this.apply(this.r10) case var _2?) {
          if ([_2] case (var $ && var _loop4)) {
            for (;;) {
              if (this.pos case var mark) {
                if (this.f66() case var _) {
                  if (this.apply(this.r10) case var _2?) {
                    _loop4.add(_2);
                    continue;
                  }
                }
                this.pos = mark;
                break;
              }
            }
            if (this.pos case var to) {
              return $.length == 1 ? $.single : SequenceNode($, choose: null);
            }
          }
        }
      }
    }
  }

  Node? r10() {
    if (this.pos case var mark) {
      if (this.pos case var from) {
        if (this.f15() case (var $0 && var identifier)?) {
          if (matchPattern(":") case var $1?) {
            if (this.f66() case var $2) {
              if (this.apply(this.r11) case (var $3 && var separated)?) {
                if (($0, $1, $2, $3) case var $) {
                  if (this.pos case var to) {
                    return NamedNode(identifier, separated);
                  }
                }
              }
            }
          }
        }
      }

      this.pos = mark;
      if (this.pos case var from) {
        if (matchPattern(":") case var $0?) {
          if (this.f15() case var $1?) {
            if (this.f54() case var $2?) {
              if (($0, $1, $2) case var $) {
                if (this.pos case var to) {
                  return NamedNode($1, OptionalNode(ReferenceNode($1)));
                }
              }
            }
          }
        }
      }

      this.pos = mark;
      if (this.pos case var from) {
        if (matchPattern(":") case var $0?) {
          if (this.f15() case var $1?) {
            if (this.f57() case var $2?) {
              if (($0, $1, $2) case var $) {
                if (this.pos case var to) {
                  return NamedNode($1, StarNode(ReferenceNode($1)));
                }
              }
            }
          }
        }
      }

      this.pos = mark;
      if (this.pos case var from) {
        if (matchPattern(":") case var $0?) {
          if (this.f15() case var $1?) {
            if (this.f58() case var $2?) {
              if (($0, $1, $2) case var $) {
                if (this.pos case var to) {
                  return NamedNode($1, PlusNode(ReferenceNode($1)));
                }
              }
            }
          }
        }
      }

      this.pos = mark;
      if (this.pos case var from) {
        if (matchPattern(":") case var $0?) {
          if (this.f15() case var $1?) {
            if (($0, $1) case var $) {
              if (this.pos case var to) {
                return NamedNode($1, ReferenceNode($1));
              }
            }
          }
        }
      }

      this.pos = mark;
      if (this.apply(this.r11) case var $?) {
        return $;
      }
    }
  }

  Node? r11() {
    if (this.pos case var mark) {
      if (this.pos case var from) {
        if (this.f16() case (var $0 && var min)?) {
          if (this.f39() case var $1?) {
            if (this.f16() case (var $2 && var max)) {
              if (this.apply(this.r14) case (var $3 && var atom)?) {
                if (($0, $1, $2, $3) case var $) {
                  if (this.pos case var to) {
                    return CountedNode(min, max, atom);
                  }
                }
              }
            }
          }
        }
      }

      this.pos = mark;
      if (this.pos case var from) {
        if (this.f16() case (var $0 && var number)?) {
          if (this.apply(this.r14) case (var $1 && var atom)?) {
            if (($0, $1) case var $) {
              if (this.pos case var to) {
                return CountedNode(number, number, atom);
              }
            }
          }
        }
      }

      this.pos = mark;
      if (this.pos case var from) {
        if (this.apply(this.r14) case (var $0 && var sep)?) {
          if (this.f62() case var $1?) {
            if (this.apply(this.r14) case (var $2 && var expr)?) {
              if (this.f58() case var $3?) {
                if (this.f54() case (var $4 && var trailing)) {
                  if (($0, $1, $2, $3, $4) case var $) {
                    if (this.pos case var to) {
                      return PlusSeparatedNode(sep, expr, isTrailingAllowed: trailing != null);
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
        if (this.apply(this.r14) case (var $0 && var sep)?) {
          if (this.f62() case var $1?) {
            if (this.apply(this.r14) case (var $2 && var expr)?) {
              if (this.f57() case var $3?) {
                if (this.f54() case (var $4 && var trailing)) {
                  if (($0, $1, $2, $3, $4) case var $) {
                    if (this.pos case var to) {
                      return StarSeparatedNode(sep, expr, isTrailingAllowed: trailing != null);
                    }
                  }
                }
              }
            }
          }
        }
      }

      this.pos = mark;
      if (this.apply(this.r12) case var $?) {
        return $;
      }
    }
  }

  Node? r12() {
    if (this.pos case var mark) {
      if (this.pos case var from) {
        if (this.apply(this.r12) case var $0?) {
          if (this.f54() case var $1?) {
            if ($0 case var $) {
              if (this.pos case var to) {
                return OptionalNode($);
              }
            }
          }
        }
      }

      this.pos = mark;
      if (this.pos case var from) {
        if (this.apply(this.r12) case var $0?) {
          if (this.f57() case var $1?) {
            if ($0 case var $) {
              if (this.pos case var to) {
                return StarNode($);
              }
            }
          }
        }
      }

      this.pos = mark;
      if (this.pos case var from) {
        if (this.apply(this.r12) case var $0?) {
          if (this.f58() case var $1?) {
            if ($0 case var $) {
              if (this.pos case var to) {
                return PlusNode($);
              }
            }
          }
        }
      }

      this.pos = mark;
      if (this.apply(this.r13) case var $?) {
        return $;
      }
    }
  }

  Node? r13() {
    if (this.pos case var mark) {
      if (this.pos case var from) {
        if (this.f56() case var $0?) {
          if (this.apply(this.r13) case var $1?) {
            if ($1 case var $) {
              if (this.pos case var to) {
                return AndPredicateNode($);
              }
            }
          }
        }
      }

      this.pos = mark;
      if (this.pos case var from) {
        if (this.f55() case var $0?) {
          if (this.apply(this.r13) case var $1?) {
            if ($1 case var $) {
              if (this.pos case var to) {
                return NotPredicateNode($);
              }
            }
          }
        }
      }

      this.pos = mark;
      if (this.apply(this.r14) case var $?) {
        return $;
      }
    }
  }

  Node? r14() {
    if (this.pos case var mark) {
      if (this.pos case var from) {
        if (this.f25() case var $0?) {
          if (this.f51() case var $1?) {
            if (this.f58() case var $2?) {
              if (this.f54() case var $3?) {
                if (this.f50() case var $4?) {
                  if (this.f49() case var $5?) {
                    if (this.apply(this.r14) case (var $6 && var sep)?) {
                      if (this.f66() case var $7) {
                        if (this.apply(this.r14) case (var $8 && var body)?) {
                          if (this.f48() case var $9?) {
                            if (($0, $1, $2, $3, $4, $5, $6, $7, $8, $9) case var $) {
                              if (this.pos case var to) {
                                return PlusSeparatedNode(sep, body, isTrailingAllowed: true);
                              }
                            }
                          }
                        }
                      }
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
        if (this.f25() case var $0?) {
          if (this.f51() case var $1?) {
            if (this.f57() case var $2?) {
              if (this.f54() case var $3?) {
                if (this.f50() case var $4?) {
                  if (this.f49() case var $5?) {
                    if (this.apply(this.r14) case (var $6 && var sep)?) {
                      if (this.f66() case var $7) {
                        if (this.apply(this.r14) case (var $8 && var body)?) {
                          if (this.f48() case var $9?) {
                            if (($0, $1, $2, $3, $4, $5, $6, $7, $8, $9) case var $) {
                              if (this.pos case var to) {
                                return StarSeparatedNode(sep, body, isTrailingAllowed: true);
                              }
                            }
                          }
                        }
                      }
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
        if (this.f25() case var $0?) {
          if (this.f51() case var $1?) {
            if (this.f58() case var $2?) {
              if (this.f50() case var $3?) {
                if (this.f49() case var $4?) {
                  if (this.apply(this.r14) case (var $5 && var sep)?) {
                    if (this.f66() case var $6) {
                      if (this.apply(this.r14) case (var $7 && var body)?) {
                        if (this.f48() case var $8?) {
                          if (($0, $1, $2, $3, $4, $5, $6, $7, $8) case var $) {
                            if (this.pos case var to) {
                              return PlusSeparatedNode(sep, body, isTrailingAllowed: false);
                            }
                          }
                        }
                      }
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
        if (this.f25() case var $0?) {
          if (this.f51() case var $1?) {
            if (this.f57() case var $2?) {
              if (this.f50() case var $3?) {
                if (this.f49() case var $4?) {
                  if (this.apply(this.r14) case (var $5 && var sep)?) {
                    if (this.f66() case var $6) {
                      if (this.apply(this.r14) case (var $7 && var body)?) {
                        if (this.f48() case var $8?) {
                          if (($0, $1, $2, $3, $4, $5, $6, $7, $8) case var $) {
                            if (this.pos case var to) {
                              return StarSeparatedNode(sep, body, isTrailingAllowed: false);
                            }
                          }
                        }
                      }
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
        if (this.f25() case var $0?) {
          if (this.f49() case var $1?) {
            if (this.apply(this.r14) case (var $2 && var sep)?) {
              if (this.f66() case var $3) {
                if (this.apply(this.r14) case (var $4 && var body)?) {
                  if (this.f48() case var $5?) {
                    if (($0, $1, $2, $3, $4, $5) case var $) {
                      if (this.pos case var to) {
                        return PlusSeparatedNode(sep, body, isTrailingAllowed: false);
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }

      this.pos = mark;
      if (this.f51() case var $0?) {
        if (this.apply(this.r7) case var $1?) {
          if (this.f50() case var $2?) {
            return $1;
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.r15) case var $?) {
        return $;
      }
      this.pos = mark;
      if (this.f5() case var $?) {
        return $;
      }
      this.pos = mark;
      if (this.pos case var from) {
        if (this.f2() case var $?) {
          if (this.pos case var to) {
            return RegExpNode(RegExp($));
          }
        }
      }

      this.pos = mark;
      if (this.pos case var from) {
        if (this.f3() case var $?) {
          if (this.pos case var to) {
            return StringLiteralNode($);
          }
        }
      }

      this.pos = mark;
      if (this.pos case var from) {
        if (this.f0() case var $?) {
          if (this.pos case var to) {
            return ReferenceNode($);
          }
        }
      }
    }
  }

  Node? r15() {
    if (this.pos case var mark) {
      if (this.pos case var from) {
        if (this.pos case var mark) {
          if (this.f64() case var $?) {
            if (this.pos case var to) {
              return const StartOfInputNode();
            }
          }
          this.pos = mark;
          if (this.f19() case var $?) {
            if (this.pos case var to) {
              return const StartOfInputNode();
            }
          }
        }
      }

      this.pos = mark;
      if (this.pos case var from) {
        if (this.pos case var mark) {
          if (this.f65() case var $?) {
            if (this.pos case var to) {
              return const EndOfInputNode();
            }
          }
          this.pos = mark;
          if (this.f20() case var $?) {
            if (this.pos case var to) {
              return const EndOfInputNode();
            }
          }
        }
      }

      this.pos = mark;
      if (this.pos case var from) {
        if (this.pos case var mark) {
          if (this.f62() case var $?) {
            if (this.pos case var to) {
              return const AnyCharacterNode();
            }
          }
          this.pos = mark;
          if (this.f23() case var $?) {
            if (this.pos case var to) {
              return const AnyCharacterNode();
            }
          }
        }
      }

      this.pos = mark;
      if (this.pos case var from) {
        if (this.pos case var mark) {
          if (this.f63() case var $?) {
            if (this.pos case var to) {
              return const EpsilonNode();
            }
          }
          this.pos = mark;
          if (this.f22() case var $?) {
            if (this.pos case var to) {
              return const EpsilonNode();
            }
          }
        }
      }

      this.pos = mark;
      if (this.pos case var from) {
        if (this.f26() case var $?) {
          if (this.pos case var to) {
            return const StringLiteralNode(r"\");
          }
        }
      }

      this.pos = mark;
      if (this.pos case var from) {
        if (this.f27() case var $?) {
          if (this.pos case var to) {
            return SimpleRegExpEscapeNode.digit;
          }
        }
      }

      this.pos = mark;
      if (this.pos case var from) {
        if (this.f29() case var $?) {
          if (this.pos case var to) {
            return SimpleRegExpEscapeNode.whitespace;
          }
        }
      }
    }
  }

  String r16() {
    if (this.pos case var from) {
      if (this.f68() case var _0) {
        if (this.pos case var mark) {
          if ([if (_0 case var _0?) _0] case (var $ && var code && var _loop2)) {
            if (_loop2.isNotEmpty) {
              for (;;) {
                if (this.pos case var mark) {
                  if (this.f68() case var _0?) {
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
            if (this.pos case var to) {
              return code.join();
            }
          }
        }
      }
    }
  }

  String? r17() {
    if (this.pos case var from) {
      if (this.f66() case var $0) {
        if (this.apply(this.r18) case (var $1 && var nonNullable)?) {
          if (this.f66() case var $2) {
            if (this.f54() case var $3) {
              if (($0, $1, $2, $3) case var $) {
                if (this.pos case var to) {
                  return $3 == null ? "$nonNullable" : "$nonNullable?";
                }
              }
            }
          }
        }
      }
    }
  }

  String? r18() {
    if (this.f66() case var $0) {
      if (this.f69() case var $1?) {
        if (this.f66() case var $2) {
          return $1;
        }
      }
    }
  }

  String? r19() {
    if (this.pos case var mark) {
      if (this.pos case var from) {
        if (this.f51() case var $0?) {
          if (this.f70() case var $1) {
            if (this.f50() case var $2?) {
              if (($0, $1, $2) case var $) {
                if (this.pos case var to) {
                  return "(" + ($1 == null ? "" : "{" + $1 + "}") + ")";
                }
              }
            }
          }
        }
      }

      this.pos = mark;
      if (this.pos case var from) {
        if (this.f51() case var $0?) {
          if (this.f13() case var $1?) {
            if (this.f59() case var $2?) {
              if (this.f71() case var $3) {
                if (this.f50() case var $4?) {
                  if (($0, $1, $2, $3, $4) case var $) {
                    if (this.pos case var to) {
                      return "(" + $1 + ", " + ($3 == null ? "" : "{" + $3 + "}") + ")";
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
        if (this.f51() case var $0?) {
          if (this.f11() case var $1?) {
            if (this.f72() case var $2) {
              if (this.f50() case var $3?) {
                if (($0, $1, $2, $3) case var $) {
                  if (this.pos case var to) {
                    return "(" + $1 + ($2 == null ? "" : ", {" + $2 + "}") + ")";
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  String? r20() {
    if (this.pos case var from) {
      if (this.apply(this.r22) case (var $0 && var base)?) {
        if (this.f44() case var $1?) {
          if (this.apply(this.r21) case (var $2 && var arguments)?) {
            if (this.f45() case var $3?) {
              if (($0, $1, $2, $3) case var $) {
                if (this.pos case var to) {
                  return "$base<$arguments>";
                }
              }
            }
          }
        }
      }
    }
  }

  String? r21() {
    if (this.pos case var from) {
      if (this.apply(this.r17) case var _0?) {
        if ([_0] case (var $ && var _loop2)) {
          for (;;) {
            if (this.pos case var mark) {
              if (this.f59() case var _?) {
                if (this.apply(this.r17) case var _0?) {
                  _loop2.add(_0);
                  continue;
                }
              }
              this.pos = mark;
              break;
            }
          }
          if (this.pos case var to) {
            return $.join(", ");
          }
        }
      }
    }
  }

  String? r22() {
    if (this.pos case var from) {
      if (this.f15() case var _0?) {
        if ([_0] case (var $ && var _loop2)) {
          for (;;) {
            if (this.pos case var mark) {
              if (this.f62() case var _?) {
                if (this.f15() case var _0?) {
                  _loop2.add(_0);
                  continue;
                }
              }
              this.pos = mark;
              break;
            }
          }
          if (this.pos case var to) {
            return $.join(".");
          }
        }
      }
    }
  }

  static final _regexp = (
    RegExp("[a-zA-Z_][a-zA-z0-9_]*"),
    RegExp("\\d"),
    RegExp("\\s"),
    RegExp("\\/{2}.*(?:(?:\\r?\\n)|(?:\$))"),
  );
}
