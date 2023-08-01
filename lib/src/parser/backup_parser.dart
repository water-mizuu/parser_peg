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
final class PegParser extends _PegParser<ParserGenerator> {
  PegParser();

  @override
  get start => global__document;

  String? global__name() {
    if (this.pos case var mark) {
      if (this.pos case var from) {
        if (this.fragment6() case var _0) {
          if (this.pos case var mark) {
            if ([if (_0 case var _0?) _0] case (var $0 && var _loop2)) {
              if (_loop2.isNotEmpty) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.fragment6() case var _0?) {
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
              if (this.global__literal__raw() case var $1?) {
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
        if (this.global__identifier() case var $0?) {
          if (this.fragment7() case var _2) {
            if (this.pos case var mark) {
              if ([if (_2 case var _2?) _2] case (var $1 && var _loop4)) {
                if (_loop4.isNotEmpty) {
                  for (;;) {
                    if (this.pos case var mark) {
                      if (this.fragment7() case var _2?) {
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

  Node? global__body() {
    if (this.pos case var from) {
      if (this.global__$61() case var $0?) {
        if (this.apply(this.global__choice) case (var $1 && var choice)?) {
          if (this.global__$59() case var $2?) {
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

  late final global__literal__regexp = () {
    if (matchPattern("/") case var $0?) {
      if (this.fragment9() case var $1?) {
        if (matchPattern("/") case var $2?) {
          return $1;
        }
      }
    }
  };

  late final global__literal__string = () {
    if (this.global___() case var $0) {
      if (this.global__literal__string__main() case var $1?) {
        if (this.global___() case var $2) {
          return $1;
        }
      }
    }
  };

  late final global__literal__string__main = () {
    if (this.pos case var mark) {
      if (this.pos case var from) {
        if (matchPattern("r") case var $0?) {
          if (matchPattern("\"\"\"") case var $1?) {
            if (this.fragment10() case var _0) {
              if (this.pos case var mark) {
                if ([if (_0 case var _0?) _0] case (var $2 && var body && var _loop2)) {
                  if (_loop2.isNotEmpty) {
                    for (;;) {
                      if (this.pos case var mark) {
                        if (this.fragment10() case var _0?) {
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
            if (this.fragment11() case var _2) {
              if (this.pos case var mark) {
                if ([if (_2 case var _2?) _2] case (var $2 && var body && var _loop4)) {
                  if (_loop4.isNotEmpty) {
                    for (;;) {
                      if (this.pos case var mark) {
                        if (this.fragment11() case var _2?) {
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
            if (this.fragment12() case var _4) {
              if (this.pos case var mark) {
                if ([if (_4 case var _4?) _4] case (var $2 && var body && var _loop6)) {
                  if (_loop6.isNotEmpty) {
                    for (;;) {
                      if (this.pos case var mark) {
                        if (this.fragment12() case var _4?) {
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
            if (this.fragment13() case var _6) {
              if (this.pos case var mark) {
                if ([if (_6 case var _6?) _6] case (var $2 && var body && var _loop8)) {
                  if (_loop8.isNotEmpty) {
                    for (;;) {
                      if (this.pos case var mark) {
                        if (this.fragment13() case var _6?) {
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
          if (this.fragment14() case var _8) {
            if (this.pos case var mark) {
              if ([if (_8 case var _8?) _8] case (var $1 && var body && var _loop10)) {
                if (_loop10.isNotEmpty) {
                  for (;;) {
                    if (this.pos case var mark) {
                      if (this.fragment14() case var _8?) {
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
          if (this.fragment15() case var _10) {
            if (this.pos case var mark) {
              if ([if (_10 case var _10?) _10] case (var $1 && var body && var _loop12)) {
                if (_loop12.isNotEmpty) {
                  for (;;) {
                    if (this.pos case var mark) {
                      if (this.fragment15() case var _10?) {
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
          if (this.fragment16() case var _12) {
            if (this.pos case var mark) {
              if ([if (_12 case var _12?) _12] case (var $1 && var body && var _loop14)) {
                if (_loop14.isNotEmpty) {
                  for (;;) {
                    if (this.pos case var mark) {
                      if (this.fragment16() case var _12?) {
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
          if (this.fragment17() case var _14) {
            if (this.pos case var mark) {
              if ([if (_14 case var _14?) _14] case (var $1 && var body && var _loop16)) {
                if (_loop16.isNotEmpty) {
                  for (;;) {
                    if (this.pos case var mark) {
                      if (this.fragment17() case var _14?) {
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

  late final global__literal__range = () {
    if (this.global__literal__range__main() case var $?) {
      return $;
    }
  };

  late final global__literal__range__main = () {
    if (this.pos case var from) {
      if (this.global__$91() case var $0?) {
        if (this.global__literal__range__elements() case (var $1 && var elements)?) {
          if (this.global__$93() case var $2?) {
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

  late final global__literal__range__elements = () {
    if (this.pos case var from) {
      if (this.global__literal__range__element() case var _0?) {
        if ([_0] case (var $ && var _loop2)) {
          for (;;) {
            if (this.pos case var mark) {
              if (this.global___() case var _) {
                if (this.global__literal__range__element() case var _0?) {
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

  late final global__literal__range__element = () {
    if (this.pos case var mark) {
      if (this.pos case var from) {
        if (pos < buffer.length) {
          if (buffer[pos] case (var $0 && var l)) {
            pos++;
            if (matchPattern("-") case var $1?) {
              if (pos < buffer.length) {
                if (buffer[pos] case (var $2 && var r)) {
                  pos++;
                  if (($0, $1, $2) case var $) {
                    if (this.pos case var to) {
                      return (l.codeUnitAt(0), r.codeUnitAt(0));
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
        if (pos < buffer.length) {
          if (buffer[pos] case var $) {
            pos++;
            if (this.pos case var to) {
              return ($.codeUnitAt(0), $.codeUnitAt(0));
            }
          }
        }
      }
    }
  };

  late final global__literal__raw = () {
    if (this.pos case var from) {
      if (matchPattern("`") case var $0?) {
        if (this.fragment18() case var _0) {
          if (this.pos case var mark) {
            if ([if (_0 case var _0?) _0] case (var $1 && var inner && var _loop2)) {
              if (_loop2.isNotEmpty) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.fragment18() case var _0?) {
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

  String? global__type__fields__positional() {
    if (this.pos case var from) {
      if (this.global__type__field__positional() case var _0?) {
        if ([_0] case (var $ && var _loop2)) {
          for (;;) {
            if (this.pos case var mark) {
              if (this.global__$44() case var _?) {
                if (this.global__type__field__positional() case var _0?) {
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

  String? global__type__fields__named() {
    if (this.pos case var from) {
      if (this.global__type__field__named() case var _0?) {
        if ([_0] case (var $ && var _loop2)) {
          for (;;) {
            if (this.pos case var mark) {
              if (this.global__$44() case var _?) {
                if (this.global__type__field__named() case var _0?) {
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

  String? global__type__field__positional() {
    if (this.pos case var from) {
      if (this.apply(this.global__type__nullable) case var $0?) {
        if (this.global___() case var $1) {
          if (this.global__identifier() case var $2) {
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

  String? global__type__field__named() {
    if (this.pos case var from) {
      if (this.apply(this.global__type__nullable) case var $0?) {
        if (this.global___() case var $1) {
          if (this.global__identifier() case var $2?) {
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

  String? global__identifier() {
    if (matchPattern(_regexp.$1) case var $?) {
      return $;
    }
  }

  int? global__number() {
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

  late final global__kw__rule = () {
    if (this.global___() case var $0) {
      if (matchPattern("@rule") case var $1?) {
        if (this.global___() case var $2) {
          return $1;
        }
      }
    }
  };

  late final global__kw__fragment = () {
    if (this.global___() case var $0) {
      if (matchPattern("@fragment") case var $1?) {
        if (this.global___() case var $2) {
          return $1;
        }
      }
    }
  };

  late final global__kw__start = () {
    if (this.global___() case var $0) {
      if (matchPattern("startOfInput") case var $1?) {
        if (this.global___() case var $2) {
          return $1;
        }
      }
    }
  };

  late final global__kw__end = () {
    if (this.global___() case var $0) {
      if (matchPattern("endOfInput") case var $1?) {
        if (this.global___() case var $2) {
          return $1;
        }
      }
    }
  };

  late final global__kw__backslash = () {
    if (this.global___() case var $0) {
      if (matchPattern("backslash") case var $1?) {
        if (this.global___() case var $2) {
          return $1;
        }
      }
    }
  };

  late final global__kw__epsilon = () {
    if (this.global___() case var $0) {
      if (matchPattern("epsilon") case var $1?) {
        if (this.global___() case var $2) {
          return $1;
        }
      }
    }
  };

  late final global__kw__any = () {
    if (this.global___() case var $0) {
      if (matchPattern("any") case var $1?) {
        if (this.global___() case var $2) {
          return $1;
        }
      }
    }
  };

  late final global__kw__var = () {
    if (this.global___() case var $0) {
      if (matchPattern("var") case var $1?) {
        if (this.global___() case var $2) {
          return $1;
        }
      }
    }
  };

  late final global__mac__sep = () {
    if (this.global___() case var $0) {
      if (matchPattern("sep!") case var $1?) {
        if (this.global___() case var $2) {
          return $1;
        }
      }
    }
  };

  late final global__regexEscape__backslash = () {
    if (this.global___() case var $0) {
      if (this.fragment19() case var $1?) {
        if (this.global___() case var $2) {
          return $1;
        }
      }
    }
  };

  late final global__regexEscape__digit = () {
    if (this.global___() case var $0) {
      if (this.fragment20() case var $1?) {
        if (this.global___() case var $2) {
          return $1;
        }
      }
    }
  };

  late final global__regexEscape__word = () {
    if (this.global___() case var $0) {
      if (this.fragment21() case var $1?) {
        if (this.global___() case var $2) {
          return $1;
        }
      }
    }
  };

  late final global__regexEscape__space = () {
    if (this.global___() case var $0) {
      if (this.fragment22() case var $1?) {
        if (this.global___() case var $2) {
          return $1;
        }
      }
    }
  };

  late final global__regexEscape__tab = () {
    if (this.global___() case var $0) {
      if (this.fragment23() case var $1?) {
        if (this.global___() case var $2) {
          return $1;
        }
      }
    }
  };

  late final global__regexEscape__formFeed = () {
    if (this.global___() case var $0) {
      if (this.fragment24() case var $1?) {
        if (this.global___() case var $2) {
          return $1;
        }
      }
    }
  };

  late final global__regexEscape__verticalTab = () {
    if (this.global___() case var $0) {
      if (this.fragment25() case var $1?) {
        if (this.global___() case var $2) {
          return $1;
        }
      }
    }
  };

  late final global__regexEscape__null = () {
    if (this.global___() case var $0) {
      if (this.fragment26() case var $1?) {
        if (this.global___() case var $2) {
          return $1;
        }
      }
    }
  };

  late final global__regexEscape__control = () {
    if (this.global___() case var $0) {
      if (this.fragment27() case var $1?) {
        if (this.global___() case var $2) {
          return $1;
        }
      }
    }
  };

  late final global__regexEscape__hex = () {
    if (this.global___() case var $0) {
      if (this.fragment28() case var $1?) {
        if (this.global___() case var $2) {
          return $1;
        }
      }
    }
  };

  late final global__regexEscape__unicode = () {
    if (this.global___() case var $0) {
      if (this.fragment29() case var $1?) {
        if (this.global___() case var $2) {
          return $1;
        }
      }
    }
  };

  late final global__regexEscape__unicodeExtended = () {
    if (this.global___() case var $0) {
      if (this.fragment30() case var $1?) {
        if (this.global___() case var $2) {
          return $1;
        }
      }
    }
  };

  late final global__regexEscape__literal = () {
    if (this.global___() case var $0) {
      if (this.fragment31() case var $1?) {
        if (this.global___() case var $2) {
          return $1;
        }
      }
    }
  };

  late final global__$46_46 = () {
    if (this.global___() case var $0) {
      if (matchPattern("..") case var $1?) {
        if (this.global___() case var $2) {
          return $1;
        }
      }
    }
  };

  late final global__$58_58 = () {
    if (this.global___() case var $0) {
      if (matchPattern("::") case var $1?) {
        if (this.global___() case var $2) {
          return $1;
        }
      }
    }
  };

  late final global__$37_37 = () {
    if (this.global___() case var $0) {
      if (matchPattern("%%") case var $1?) {
        if (this.global___() case var $2) {
          return $1;
        }
      }
    }
  };

  late final global__$61_62 = () {
    if (this.global___() case var $0) {
      if (matchPattern("=>") case var $1?) {
        if (this.global___() case var $2) {
          return $1;
        }
      }
    }
  };

  late final global__$64 = () {
    if (this.global___() case var $0) {
      if (matchPattern("@") case var $1?) {
        if (this.global___() case var $2) {
          return $1;
        }
      }
    }
  };

  late final global__$60 = () {
    if (this.global___() case var $0) {
      if (matchPattern("<") case var $1?) {
        if (this.global___() case var $2) {
          return $1;
        }
      }
    }
  };

  late final global__$62 = () {
    if (this.global___() case var $0) {
      if (matchPattern(">") case var $1?) {
        if (this.global___() case var $2) {
          return $1;
        }
      }
    }
  };

  late final global__$93 = () {
    if (this.global___() case var $0) {
      if (matchPattern("]") case var $1?) {
        if (this.global___() case var $2) {
          return $1;
        }
      }
    }
  };

  late final global__$91 = () {
    if (this.global___() case var $0) {
      if (matchPattern("[") case var $1?) {
        if (this.global___() case var $2) {
          return $1;
        }
      }
    }
  };

  late final global__$125 = () {
    if (this.global___() case var $0) {
      if (matchPattern("}") case var $1?) {
        if (this.global___() case var $2) {
          return $1;
        }
      }
    }
  };

  late final global__$123 = () {
    if (this.global___() case var $0) {
      if (matchPattern("{") case var $1?) {
        if (this.global___() case var $2) {
          return $1;
        }
      }
    }
  };

  late final global__$41 = () {
    if (this.global___() case var $0) {
      if (matchPattern(")") case var $1?) {
        if (this.global___() case var $2) {
          return $1;
        }
      }
    }
  };

  late final global__$40 = () {
    if (this.global___() case var $0) {
      if (matchPattern("(") case var $1?) {
        if (this.global___() case var $2) {
          return $1;
        }
      }
    }
  };

  late final global__$59 = () {
    if (this.global___() case var $0) {
      if (matchPattern(";") case var $1?) {
        if (this.global___() case var $2) {
          return $1;
        }
      }
    }
  };

  late final global__$61 = () {
    if (this.global___() case var $0) {
      if (matchPattern("=") case var $1?) {
        if (this.global___() case var $2) {
          return $1;
        }
      }
    }
  };

  late final global__$63 = () {
    if (this.global___() case var $0) {
      if (matchPattern("?") case var $1?) {
        if (this.global___() case var $2) {
          return $1;
        }
      }
    }
  };

  late final global__$33 = () {
    if (this.global___() case var $0) {
      if (matchPattern("!") case var $1?) {
        if (this.global___() case var $2) {
          return $1;
        }
      }
    }
  };

  late final global__$38 = () {
    if (this.global___() case var $0) {
      if (matchPattern("&") case var $1?) {
        if (this.global___() case var $2) {
          return $1;
        }
      }
    }
  };

  late final global__$42 = () {
    if (this.global___() case var $0) {
      if (matchPattern("*") case var $1?) {
        if (this.global___() case var $2) {
          return $1;
        }
      }
    }
  };

  late final global__$43 = () {
    if (this.global___() case var $0) {
      if (matchPattern("+") case var $1?) {
        if (this.global___() case var $2) {
          return $1;
        }
      }
    }
  };

  late final global__$44 = () {
    if (this.global___() case var $0) {
      if (matchPattern(",") case var $1?) {
        if (this.global___() case var $2) {
          return $1;
        }
      }
    }
  };

  late final global__$58 = () {
    if (this.global___() case var $0) {
      if (matchPattern(":") case var $1?) {
        if (this.global___() case var $2) {
          return $1;
        }
      }
    }
  };

  late final global__$124 = () {
    if (this.global___() case var $0) {
      if (matchPattern("|") case var $1?) {
        if (this.global___() case var $2) {
          return $1;
        }
      }
    }
  };

  late final global__DOT = () {
    if (this.global___() case var $0) {
      if (matchPattern(".") case var $1?) {
        if (this.global___() case var $2) {
          return $1;
        }
      }
    }
  };

  late final global__EPSILON = () {
    if (this.global___() case var $0) {
      if (matchPattern("ε") case var $1?) {
        if (this.global___() case var $2) {
          return $1;
        }
      }
    }
  };

  late final global__CARET = () {
    if (this.global___() case var $0) {
      if (matchPattern("^") case var $1?) {
        if (this.global___() case var $2) {
          return $1;
        }
      }
    }
  };

  late final global__DOLLAR = () {
    if (this.global___() case var $0) {
      if (matchPattern("\$") case var $1?) {
        if (this.global___() case var $2) {
          return $1;
        }
      }
    }
  };

  late final global___ = () {
    if (this.pos case var from) {
      if (this.fragment32() case var _0) {
        if (this.pos case var mark) {
          if ([if (_0 case var _0?) _0] case (var $ && var _loop2)) {
            if (_loop2.isNotEmpty) {
              for (;;) {
                if (this.pos case var mark) {
                  if (this.fragment32() case var _0?) {
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

  late final fragment0 = () {
    if (this.pos case var mark) {
      if (this.global__$64() case var $?) {
        return $;
      }
      this.pos = mark;
      if (this.global__$61_62() case var $?) {
        return $;
      }
    }
  };

  late final fragment1 = () {
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
          if (this.apply(this.global__rawCode)! case (var $1 && var rawCode)) {
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

  late final fragment2 = () {
    if (this.pos case var mark) {
      if (this.apply(this.global__type__generic) case var $?) {
        return $;
      }
      this.pos = mark;
      if (this.apply(this.global__type__record) case var $?) {
        return $;
      }
      this.pos = mark;
      if (this.apply(this.global__type__base) case var $?) {
        return $;
      }
    }
  };

  late final fragment3 = () {
    if (this.global__$123() case var $0?) {
      if (this.global__type__fields__named() case var $1?) {
        if (this.global__$125() case var $2?) {
          return $1;
        }
      }
    }
  };

  late final fragment4 = () {
    if (this.global__$123() case var $0?) {
      if (this.global__type__fields__named() case var $1?) {
        if (this.global__$125() case var $2?) {
          return $1;
        }
      }
    }
  };

  late final fragment5 = () {
    if (this.global__$44() case var $0?) {
      if (this.global__$123() case var $1?) {
        if (this.global__type__fields__named() case var $2?) {
          if (this.global__$125() case var $3?) {
            return $2;
          }
        }
      }
    }
  };

  late final fragment6 = () {
    if (this.global__identifier() case var $0?) {
      if (matchPattern("::") case var $1?) {
        return $0;
      }
    }
  };

  late final fragment7 = () {
    if (matchPattern("::") case var $0?) {
      if (this.global__identifier() case var $1?) {
        return $1;
      }
    }
  };

  late final fragment8 = () {
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

  late final fragment9 = () {
    if (this.pos case var from) {
      if (this.fragment8() case var _0?) {
        if ([_0] case (var $ && var _loop2)) {
          for (;;) {
            if (this.pos case var mark) {
              if (this.fragment8() case var _0?) {
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

  late final fragment10 = () {
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

  late final fragment11 = () {
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

  late final fragment12 = () {
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

  late final fragment13 = () {
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

  late final fragment14 = () {
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

  late final fragment15 = () {
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

  late final fragment16 = () {
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

  late final fragment17 = () {
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

  late final fragment18 = () {
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

  late final fragment19 = () {
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

  late final fragment20 = () {
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

  late final fragment21 = () {
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

  late final fragment22 = () {
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

  late final fragment23 = () {
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

  late final fragment24 = () {
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

  late final fragment25 = () {
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

  late final fragment26 = () {
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

  late final fragment27 = () {
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

  late final fragment28 = () {
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

  late final fragment29 = () {
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

  late final fragment30 = () {
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

  late final fragment31 = () {
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

  late final fragment32 = () {
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

  ParserGenerator? global__document() {
    if (this.pos case var from) {
      if (this.pos case var $0 when this.pos <= 0) {
        if (this.apply(this.global__preamble) case (var $1 && var preamble)) {
          if (this.apply(this.global__statement) case var _0?) {
            if ([_0] case (var $2 && var statements && var _loop2)) {
              for (;;) {
                if (this.pos case var mark) {
                  if (this.global___() case var _) {
                    if (this.apply(this.global__statement) case var _0?) {
                      _loop2.add(_0);
                      continue;
                    }
                  }
                  this.pos = mark;
                  break;
                }
              }
              if (this.pos case var mark) {
                if (this.global___() case null) {
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

  String? global__preamble() {
    if (this.pos case var from) {
      if (this.global__$123() case var $0?) {
        if (this.global___() case var $1) {
          if (this.apply(this.global__rawCode)! case (var $2 && var rawCode)) {
            if (this.global___() case var $3) {
              if (this.global__$125() case var $4?) {
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

  Statement? global__statement() {
    if (this.pos case var mark) {
      if (this.apply(this.global__namespace) case var $?) {
        return $;
      }
      this.pos = mark;
      if (this.apply(this.global__fragment) case var $?) {
        return $;
      }
      this.pos = mark;
      if (this.apply(this.global__rule) case var $?) {
        return $;
      }
      this.pos = mark;
      if (this.apply(this.global__generic) case var $?) {
        return $;
      }
    }
  }

  Statement? global__namespace() {
    if (this.pos case var mark) {
      if (this.pos case var from) {
        if (this.global__kw__fragment() case var $0?) {
          if (this.global__identifier() case (var $1 && var name)) {
            if (this.global__$123() case var $2?) {
              if (this.apply(this.global__statement) case var _0?) {
                if ([_0] case (var $3 && var statements && var _loop2)) {
                  for (;;) {
                    if (this.pos case var mark) {
                      if (this.global___() case var _) {
                        if (this.apply(this.global__statement) case var _0?) {
                          _loop2.add(_0);
                          continue;
                        }
                      }
                      this.pos = mark;
                      break;
                    }
                  }
                  if (this.global__$125() case var $4?) {
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
        if (this.global__kw__rule() case var $0?) {
          if (this.global__identifier() case (var $1 && var name)) {
            if (this.global__$123() case var $2?) {
              if (this.apply(this.global__statement) case var _2?) {
                if ([_2] case (var $3 && var statements && var _loop4)) {
                  for (;;) {
                    if (this.pos case var mark) {
                      if (this.global___() case var _) {
                        if (this.apply(this.global__statement) case var _2?) {
                          _loop4.add(_2);
                          continue;
                        }
                      }
                      this.pos = mark;
                      break;
                    }
                  }
                  if (this.global__$125() case var $4?) {
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
        if (this.global__identifier() case (var $0 && var name)) {
          if (this.global__$123() case var $1?) {
            if (this.apply(this.global__statement) case var _4?) {
              if ([_4] case (var $2 && var statements && var _loop6)) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.global___() case var _) {
                      if (this.apply(this.global__statement) case var _4?) {
                        _loop6.add(_4);
                        continue;
                      }
                    }
                    this.pos = mark;
                    break;
                  }
                }
                if (this.global__$125() case var $3?) {
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

  Statement? global__rule() {
    if (this.pos case var mark) {
      if (this.pos case var from) {
        if (this.global__kw__rule() case var $0) {
          if (this.global__kw__var() case var $1?) {
            if (this.global__name() case (var $2 && var name)?) {
              if (this.global__body() case (var $3 && var body)?) {
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
        if (this.global__kw__rule() case var $0) {
          if (this.global__name() case (var $1 && var name)?) {
            if (this.global__body() case (var $2 && var body)?) {
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
        if (this.global__kw__rule() case var $0) {
          if (this.apply(this.global__type__nonNullable) case (var $1 && var type)?) {
            if (this.global__name() case (var $2 && var name)?) {
              if (this.global__body() case (var $3 && var body)?) {
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
        if (this.global__kw__rule() case var $0) {
          if (this.global__name() case (var $1 && var name)?) {
            if (this.global__$58() case var $2?) {
              if (this.apply(this.global__type__nonNullable) case (var $3 && var type)?) {
                if (this.global__body() case (var $4 && var body)?) {
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

  Statement? global__fragment() {
    if (this.pos case var mark) {
      if (this.pos case var from) {
        if (this.global__kw__fragment() case var $0?) {
          if (this.global__kw__var() case var $1?) {
            if (this.global__name() case (var $2 && var name)?) {
              if (this.global__body() case (var $3 && var body)?) {
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
        if (this.global__kw__fragment() case var $0?) {
          if (this.global__name() case (var $1 && var name)?) {
            if (this.global__body() case (var $2 && var body)?) {
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
        if (this.global__kw__fragment() case var $0?) {
          if (this.apply(this.global__type__nonNullable) case (var $1 && var type)?) {
            if (this.global__name() case (var $2 && var name)?) {
              if (this.global__body() case (var $3 && var body)?) {
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
        if (this.global__kw__fragment() case var $0?) {
          if (this.global__name() case (var $1 && var name)?) {
            if (this.global__$58() case var $2?) {
              if (this.apply(this.global__type__nonNullable) case (var $3 && var type)?) {
                if (this.global__body() case (var $4 && var body)?) {
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

  Statement? global__generic() {
    if (this.pos case var mark) {
      if (this.pos case var from) {
        if (this.global__kw__var() case var $0?) {
          if (this.global__name() case (var $1 && var name)?) {
            if (this.global__body() case (var $2 && var body)?) {
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
        if (this.global__name() case (var $0 && var name)?) {
          if (this.global__body() case (var $1 && var body)?) {
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
        if (this.apply(this.global__type__nonNullable) case (var $0 && var type)?) {
          if (this.global__name() case (var $1 && var name)?) {
            if (this.global__body() case (var $2 && var body)?) {
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
        if (this.global__name() case (var $0 && var name)?) {
          if (this.global__$58() case var $1?) {
            if (this.apply(this.global__type__nonNullable) case (var $2 && var type)?) {
              if (this.global__body() case (var $3 && var body)?) {
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

  Node? global__choice() {
    if (this.pos case var from) {
      if (this.global__$124() case var $0) {
        if (this.apply(this.global__acted) case var _0?) {
          if ([_0] case (var $1 && var options && var _loop2)) {
            for (;;) {
              if (this.pos case var mark) {
                if (this.global__$124() case var _?) {
                  if (this.apply(this.global__acted) case var _0?) {
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

  Node? global__acted() {
    if (this.pos case var mark) {
      if (this.pos case var from) {
        if (this.apply(this.global__sequence) case (var $0 && var sequence)?) {
          if (this.global__$40() case var $1?) {
            if (this.global__$41() case var $2?) {
              if (this.global__$123() case var $3?) {
                if (this.global___() case var $4) {
                  if (this.apply(this.global__rawCode)! case (var $5 && var rawCode)) {
                    if (this.global___() case var $6) {
                      if (this.global__$125() case var $7?) {
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
        if (this.apply(this.global__sequence) case (var $0 && var sequence)?) {
          if (this.global__$123() case var $1?) {
            if (this.global___() case var $2) {
              if (this.apply(this.global__rawCode)! case (var $3 && var rawCode)) {
                if (this.global___() case var $4) {
                  if (this.global__$125() case var $5?) {
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
      if (this.apply(this.global__sequence) case var $?) {
        return $;
      }
    }
  }

  Node? global__sequence() {
    if (this.pos case var mark) {
      if (this.pos case var from) {
        if (this.apply(this.global__labeled) case var _0?) {
          if ([_0] case (var $0 && var body && var _loop2)) {
            for (;;) {
              if (this.pos case var mark) {
                if (this.global___() case var _) {
                  if (this.apply(this.global__labeled) case var _0?) {
                    _loop2.add(_0);
                    continue;
                  }
                }
                this.pos = mark;
                break;
              }
            }
            if (this.fragment0() case var $1?) {
              if (this.global__number() case (var $2 && var number)?) {
                if (($0, $1, $2) case var $) {
                  if (this.pos case var to) {
                    if (body.length == 1) {
                      return body.single;
                    } else {
                      return SequenceNode(body, choose: number);
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
        if (this.apply(this.global__labeled) case var _2?) {
          if ([_2] case (var $ && var _loop4)) {
            for (;;) {
              if (this.pos case var mark) {
                if (this.global___() case var _) {
                  if (this.apply(this.global__labeled) case var _2?) {
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

  Node? global__labeled() {
    if (this.pos case var mark) {
      if (this.pos case var from) {
        if (this.global__identifier() case (var $0 && var identifier)?) {
          if (matchPattern(":") case var $1?) {
            if (this.global___() case var $2) {
              if (this.apply(this.global__separated) case (var $3 && var separated)?) {
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
          if (this.global__identifier() case var $1?) {
            if (this.global__$63() case var $2?) {
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
          if (this.global__identifier() case var $1?) {
            if (this.global__$42() case var $2?) {
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
          if (this.global__identifier() case var $1?) {
            if (this.global__$43() case var $2?) {
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
          if (this.global__identifier() case var $1?) {
            if (($0, $1) case var $) {
              if (this.pos case var to) {
                return NamedNode($1, ReferenceNode($1));
              }
            }
          }
        }
      }

      this.pos = mark;
      if (this.apply(this.global__separated) case var $?) {
        return $;
      }
    }
  }

  Node? global__separated() {
    if (this.pos case var mark) {
      if (this.pos case var from) {
        if (this.global__number() case (var $0 && var min)?) {
          if (this.global__$46_46() case var $1?) {
            if (this.global__number() case (var $2 && var max)) {
              if (this.apply(this.global__atom) case (var $3 && var atom)?) {
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
        if (this.global__number() case (var $0 && var number)?) {
          if (this.apply(this.global__atom) case (var $1 && var atom)?) {
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
        if (this.apply(this.global__atom) case (var $0 && var sep)?) {
          if (this.global__DOT() case var $1?) {
            if (this.apply(this.global__atom) case (var $2 && var expr)?) {
              if (this.global__$43() case var $3?) {
                if (this.global__$63() case (var $4 && var trailing)) {
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
        if (this.apply(this.global__atom) case (var $0 && var sep)?) {
          if (this.global__DOT() case var $1?) {
            if (this.apply(this.global__atom) case (var $2 && var expr)?) {
              if (this.global__$42() case var $3?) {
                if (this.global__$63() case (var $4 && var trailing)) {
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
      if (this.apply(this.global__postfix) case var $?) {
        return $;
      }
    }
  }

  Node? global__postfix() {
    if (this.pos case var mark) {
      if (this.pos case var from) {
        if (this.apply(this.global__postfix) case var $0?) {
          if (this.global__$63() case var $1?) {
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
        if (this.apply(this.global__postfix) case var $0?) {
          if (this.global__$42() case var $1?) {
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
        if (this.apply(this.global__postfix) case var $0?) {
          if (this.global__$43() case var $1?) {
            if ($0 case var $) {
              if (this.pos case var to) {
                return PlusNode($);
              }
            }
          }
        }
      }

      this.pos = mark;
      if (this.apply(this.global__prefix) case var $?) {
        return $;
      }
    }
  }

  Node? global__prefix() {
    if (this.pos case var mark) {
      if (this.pos case var from) {
        if (this.global__$38() case var $0?) {
          if (this.apply(this.global__prefix) case var $1?) {
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
        if (this.global__$33() case var $0?) {
          if (this.apply(this.global__prefix) case var $1?) {
            if ($1 case var $) {
              if (this.pos case var to) {
                return NotPredicateNode($);
              }
            }
          }
        }
      }

      this.pos = mark;
      if (this.apply(this.global__atom) case var $?) {
        return $;
      }
    }
  }

  Node? global__atom() {
    if (this.pos case var mark) {
      if (this.pos case var from) {
        if (this.global__mac__sep() case var $0?) {
          if (this.global__$40() case var $1?) {
            if (this.global__$43() case var $2?) {
              if (this.global__$63() case var $3?) {
                if (this.global__$41() case var $4?) {
                  if (this.global__$123() case var $5?) {
                    if (this.apply(this.global__atom) case (var $6 && var sep)?) {
                      if (this.global___() case var $7) {
                        if (this.apply(this.global__atom) case (var $8 && var body)?) {
                          if (this.global__$125() case var $9?) {
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
        if (this.global__mac__sep() case var $0?) {
          if (this.global__$40() case var $1?) {
            if (this.global__$42() case var $2?) {
              if (this.global__$63() case var $3?) {
                if (this.global__$41() case var $4?) {
                  if (this.global__$123() case var $5?) {
                    if (this.apply(this.global__atom) case (var $6 && var sep)?) {
                      if (this.global___() case var $7) {
                        if (this.apply(this.global__atom) case (var $8 && var body)?) {
                          if (this.global__$125() case var $9?) {
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
        if (this.global__mac__sep() case var $0?) {
          if (this.global__$40() case var $1?) {
            if (this.global__$43() case var $2?) {
              if (this.global__$41() case var $3?) {
                if (this.global__$123() case var $4?) {
                  if (this.apply(this.global__atom) case (var $5 && var sep)?) {
                    if (this.global___() case var $6) {
                      if (this.apply(this.global__atom) case (var $7 && var body)?) {
                        if (this.global__$125() case var $8?) {
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
        if (this.global__mac__sep() case var $0?) {
          if (this.global__$40() case var $1?) {
            if (this.global__$42() case var $2?) {
              if (this.global__$41() case var $3?) {
                if (this.global__$123() case var $4?) {
                  if (this.apply(this.global__atom) case (var $5 && var sep)?) {
                    if (this.global___() case var $6) {
                      if (this.apply(this.global__atom) case (var $7 && var body)?) {
                        if (this.global__$125() case var $8?) {
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
        if (this.global__mac__sep() case var $0?) {
          if (this.global__$123() case var $1?) {
            if (this.apply(this.global__atom) case (var $2 && var sep)?) {
              if (this.global___() case var $3) {
                if (this.apply(this.global__atom) case (var $4 && var body)?) {
                  if (this.global__$125() case var $5?) {
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
      if (this.global__$40() case var $0?) {
        if (this.apply(this.global__choice) case var $1?) {
          if (this.global__$41() case var $2?) {
            return $1;
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.global__specialSymbol) case var $?) {
        return $;
      }
      this.pos = mark;
      if (this.global__literal__range() case var $?) {
        return $;
      }
      this.pos = mark;
      if (this.pos case var from) {
        if (this.global__literal__regexp() case var $?) {
          if (this.pos case var to) {
            return RegExpNode(RegExp($));
          }
        }
      }

      this.pos = mark;
      if (this.pos case var from) {
        if (this.global__literal__string() case var $?) {
          if (this.pos case var to) {
            return StringLiteralNode($);
          }
        }
      }

      this.pos = mark;
      if (this.pos case var from) {
        if (this.global__name() case var $?) {
          if (this.pos case var to) {
            return ReferenceNode($);
          }
        }
      }
    }
  }

  Node? global__specialSymbol() {
    if (this.pos case var mark) {
      if (this.pos case var from) {
        if (this.pos case var mark) {
          if (this.global__CARET() case var $?) {
            if (this.pos case var to) {
              return const StartOfInputNode();
            }
          }
          this.pos = mark;
          if (this.global__kw__start() case var $?) {
            if (this.pos case var to) {
              return const StartOfInputNode();
            }
          }
        }
      }

      this.pos = mark;
      if (this.pos case var from) {
        if (this.pos case var mark) {
          if (this.global__DOLLAR() case var $?) {
            if (this.pos case var to) {
              return const EndOfInputNode();
            }
          }
          this.pos = mark;
          if (this.global__kw__end() case var $?) {
            if (this.pos case var to) {
              return const EndOfInputNode();
            }
          }
        }
      }

      this.pos = mark;
      if (this.pos case var from) {
        if (this.pos case var mark) {
          if (this.global__DOT() case var $?) {
            if (this.pos case var to) {
              return const AnyCharacterNode();
            }
          }
          this.pos = mark;
          if (this.global__kw__any() case var $?) {
            if (this.pos case var to) {
              return const AnyCharacterNode();
            }
          }
        }
      }

      this.pos = mark;
      if (this.pos case var from) {
        if (this.pos case var mark) {
          if (this.global__EPSILON() case var $?) {
            if (this.pos case var to) {
              return const EpsilonNode();
            }
          }
          this.pos = mark;
          if (this.global__kw__epsilon() case var $?) {
            if (this.pos case var to) {
              return const EpsilonNode();
            }
          }
        }
      }

      this.pos = mark;
      if (this.pos case var from) {
        if (this.global__regexEscape__backslash() case var $?) {
          if (this.pos case var to) {
            return const StringLiteralNode(r"\");
          }
        }
      }

      this.pos = mark;
      if (this.pos case var from) {
        if (this.global__regexEscape__digit() case var $?) {
          if (this.pos case var to) {
            return SimpleRegExpEscapeNode.digit;
          }
        }
      }

      this.pos = mark;
      if (this.pos case var from) {
        if (this.global__regexEscape__space() case var $?) {
          if (this.pos case var to) {
            return SimpleRegExpEscapeNode.whitespace;
          }
        }
      }
    }
  }

  String global__rawCode() {
    if (this.pos case var from) {
      if (this.fragment1() case var _0) {
        if (this.pos case var mark) {
          if ([if (_0 case var _0?) _0] case (var $ && var code && var _loop2)) {
            if (_loop2.isNotEmpty) {
              for (;;) {
                if (this.pos case var mark) {
                  if (this.fragment1() case var _0?) {
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

  String? global__type__nullable() {
    if (this.pos case var from) {
      if (this.global___() case var $0) {
        if (this.apply(this.global__type__nonNullable) case (var $1 && var nonNullable)?) {
          if (this.global___() case var $2) {
            if (this.global__$63() case var $3) {
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

  String? global__type__nonNullable() {
    if (this.global___() case var $0) {
      if (this.fragment2() case var $1?) {
        if (this.global___() case var $2) {
          return $1;
        }
      }
    }
  }

  String? global__type__record() {
    if (this.pos case var mark) {
      if (this.pos case var from) {
        if (this.global__$40() case var $0?) {
          if (this.fragment3() case var $1) {
            if (this.global__$41() case var $2?) {
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
        if (this.global__$40() case var $0?) {
          if (this.global__type__field__positional() case var $1?) {
            if (this.global__$44() case var $2?) {
              if (this.fragment4() case var $3) {
                if (this.global__$41() case var $4?) {
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
        if (this.global__$40() case var $0?) {
          if (this.global__type__fields__positional() case var $1?) {
            if (this.fragment5() case var $2) {
              if (this.global__$41() case var $3?) {
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

  String? global__type__generic() {
    if (this.pos case var from) {
      if (this.apply(this.global__type__base) case (var $0 && var base)?) {
        if (this.global__$60() case var $1?) {
          if (this.apply(this.global__type__arguments) case (var $2 && var arguments)?) {
            if (this.global__$62() case var $3?) {
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

  String? global__type__arguments() {
    if (this.pos case var from) {
      if (this.apply(this.global__type__nullable) case var _0?) {
        if ([_0] case (var $ && var _loop2)) {
          for (;;) {
            if (this.pos case var mark) {
              if (this.global__$44() case var _?) {
                if (this.apply(this.global__type__nullable) case var _0?) {
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

  String? global__type__base() {
    if (this.pos case var from) {
      if (this.global__identifier() case var _0?) {
        if ([_0] case (var $ && var _loop2)) {
          for (;;) {
            if (this.pos case var mark) {
              if (this.global__DOT() case var _?) {
                if (this.global__identifier() case var _0?) {
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
