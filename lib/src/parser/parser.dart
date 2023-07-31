// ignore_for_file: always_declare_return_types, always_put_control_body_on_new_line, always_specify_types, avoid_escaping_inner_quotes, avoid_redundant_argument_values, annotate_overrides, body_might_complete_normally_nullable, constant_pattern_never_matches_value_type, curly_braces_in_flow_control_structures, dead_code, directives_ordering, duplicate_ignore, inference_failure_on_function_return_type, constant_identifier_names, prefer_function_declarations_over_variables, prefer_interpolation_to_compose_strings, prefer_is_empty, no_leading_underscores_for_local_identifiers, non_constant_identifier_names, unnecessary_null_check_pattern, unnecessary_brace_in_string_interps, unnecessary_string_interpolations, unnecessary_this, unused_element, unused_import, prefer_double_quotes, unused_local_variable, unreachable_from_main, use_raw_strings, type_annotate_public_apis

// imports
// ignore_for_file: collection_methods_unrelated_type

import "dart:collection";
import "dart:math" as math;
// PREAMBLE
import "package:parser_peg/src/node.dart";
import "package:parser_peg/src/generator.dart";
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
  get start => document;


  String? name() {
    if (this.pos case var mark) {
      if (this.pos case var from) {
        if (this.fragment17() case var _0) {
          if (this.pos case var mark) {
            if ([if (_0 case var _0?) _0] case (var $0 && var _loop2)) {
              if (_loop2.isNotEmpty) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.fragment17() case var _0?) {
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
              if (this.apply(this.rawLiteral) case var $1?) {
                if (($0, $1) case var $) {
                  if (this.pos case var to) {
                    return $0.isEmpty ? $1 : "${$0.join("__")}__${$1}" ;
                  }
                }
              }
            }
          }
        }
      }

      this.pos = mark;
      if (this.pos case var from) {
        if (this.apply(this.identifier) case var $0?) {
          if (this.fragment18() case var _2) {
            if (this.pos case var mark) {
              if ([if (_2 case var _2?) _2] case (var $1 && var _loop4)) {
                if (_loop4.isNotEmpty) {
                  for (;;) {
                    if (this.pos case var mark) {
                      if (this.fragment18() case var _2?) {
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
                    return $1.isEmpty ? $0 : "${$0}__${$1.join("__")}" ;
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  Node? body() {
    if (this.pos case var from) {
      if (this.apply(this.$61) case var $0?) {
        if (this.apply(this.choice) case (var $1 && var choice)?) {
          if (this.apply(this.$59) case var $2?) {
            if (($0, $1, $2) case var $) {
              if (this.pos case var to) {
                return choice ;
              }
            }
          }
        }
      }
    }
  }

  String? regexEscape__backslash() {
    if (this.applyNonNull(this._) case var $0) {
      if (this.fragment19() case var $1?) {
        if (this.applyNonNull(this._) case var $2) {
          return $1;
        }
      }
    }
  }

  String? regexEscape__digit() {
    if (this.applyNonNull(this._) case var $0) {
      if (this.fragment20() case var $1?) {
        if (this.applyNonNull(this._) case var $2) {
          return $1;
        }
      }
    }
  }

  String? regexEscape__word() {
    if (this.applyNonNull(this._) case var $0) {
      if (this.fragment21() case var $1?) {
        if (this.applyNonNull(this._) case var $2) {
          return $1;
        }
      }
    }
  }

  String? regexEscape__space() {
    if (this.applyNonNull(this._) case var $0) {
      if (this.fragment22() case var $1?) {
        if (this.applyNonNull(this._) case var $2) {
          return $1;
        }
      }
    }
  }

  String? regexEscape__tab() {
    if (this.applyNonNull(this._) case var $0) {
      if (this.fragment23() case var $1?) {
        if (this.applyNonNull(this._) case var $2) {
          return $1;
        }
      }
    }
  }

  String? regexEscape__formFeed() {
    if (this.applyNonNull(this._) case var $0) {
      if (this.fragment24() case var $1?) {
        if (this.applyNonNull(this._) case var $2) {
          return $1;
        }
      }
    }
  }

  String? regexEscape__verticalTab() {
    if (this.applyNonNull(this._) case var $0) {
      if (this.fragment25() case var $1?) {
        if (this.applyNonNull(this._) case var $2) {
          return $1;
        }
      }
    }
  }

  String? regexEscape__null() {
    if (this.applyNonNull(this._) case var $0) {
      if (this.fragment26() case var $1?) {
        if (this.applyNonNull(this._) case var $2) {
          return $1;
        }
      }
    }
  }

  String? regexEscape__control() {
    if (this.applyNonNull(this._) case var $0) {
      if (this.fragment27() case var $1?) {
        if (this.applyNonNull(this._) case var $2) {
          return $1;
        }
      }
    }
  }

  String? regexEscape__hex() {
    if (this.applyNonNull(this._) case var $0) {
      if (this.fragment28() case var $1?) {
        if (this.applyNonNull(this._) case var $2) {
          return $1;
        }
      }
    }
  }

  String? regexEscape__unicode() {
    if (this.applyNonNull(this._) case var $0) {
      if (this.fragment29() case var $1?) {
        if (this.applyNonNull(this._) case var $2) {
          return $1;
        }
      }
    }
  }

  String? regexEscape__unicodeExtended() {
    if (this.applyNonNull(this._) case var $0) {
      if (this.fragment30() case var $1?) {
        if (this.applyNonNull(this._) case var $2) {
          return $1;
        }
      }
    }
  }

  String? regexEscape__literal() {
    if (this.applyNonNull(this._) case var $0) {
      if (this.fragment31() case var $1?) {
        if (this.applyNonNull(this._) case var $2) {
          return $1;
        }
      }
    }
  }

  late final fragment0 = () {
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
          if (this.applyNonNull(this.rawCode) case (var $1 && var rawCode)) {
            if (matchPattern("}") case var $2?) {
              if ($1 case var $) {
                if (this.pos case var to) {
                  return "{${$}}";
                }
              }
            }
          }
        }
      }
    }
  };

  late final fragment1 = () {
    if (this.pos case var mark) {
      if (this.pos case var from) {
        if (matchPattern("\\") case var $0?) {
          if (pos < buffer.length) {
            if (buffer[pos] case var $1) {
              pos++;
            if ($1 case var $) {
              if (this.pos case var to) {
                return r"\" + $ ;
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

  late final fragment2 = () {
    if (this.pos case var from) {
      if (this.fragment1() case var _0?) {
        if ([_0] case (var $ && var _loop2)) {
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
          if (this.pos case var to) {
            return $.join() ;
          }
        }
      }
    }
  };

  late final fragment3 = () {
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

  late final fragment4 = () {
    if (this.pos case var from) {
      if (this.fragment3() case var _0) {
        if (this.pos case var mark) {
          if ([if (_0 case var _0?) _0] case (var $ && var _loop2)) {
            if (_loop2.isNotEmpty) {
              for (;;) {
                if (this.pos case var mark) {
                  if (this.fragment3() case var _0?) {
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
              return $.join() ;
            }
          }
        }
      }
    }
  };

  late final fragment5 = () {
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

  late final fragment6 = () {
    if (this.pos case var from) {
      if (this.fragment5() case var _0) {
        if (this.pos case var mark) {
          if ([if (_0 case var _0?) _0] case (var $ && var _loop2)) {
            if (_loop2.isNotEmpty) {
              for (;;) {
                if (this.pos case var mark) {
                  if (this.fragment5() case var _0?) {
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
              return $.join() ;
            }
          }
        }
      }
    }
  };

  late final fragment7 = () {
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

  late final fragment8 = () {
    if (this.pos case var from) {
      if (this.fragment7() case var _0) {
        if (this.pos case var mark) {
          if ([if (_0 case var _0?) _0] case (var $ && var _loop2)) {
            if (_loop2.isNotEmpty) {
              for (;;) {
                if (this.pos case var mark) {
                  if (this.fragment7() case var _0?) {
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
              return $.join() ;
            }
          }
        }
      }
    }
  };

  late final fragment9 = () {
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

  late final fragment10 = () {
    if (this.pos case var from) {
      if (this.fragment9() case var _0) {
        if (this.pos case var mark) {
          if ([if (_0 case var _0?) _0] case (var $ && var _loop2)) {
            if (_loop2.isNotEmpty) {
              for (;;) {
                if (this.pos case var mark) {
                  if (this.fragment9() case var _0?) {
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
              return $.join() ;
            }
          }
        }
      }
    }
  };

  late final fragment11 = () {
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

  late final fragment12 = () {
    if (this.pos case var mark) {
      if (this.apply(this.type__generic) case var $?) {
        return $;
      }
      this.pos = mark;
      if (this.apply(this.type__record) case var $?) {
        return $;
      }
      this.pos = mark;
      if (this.apply(this.type__base) case var $?) {
        return $;
      }
    }
  };

  late final fragment13 = () {
    if (this.apply(this.$123) case var $0?) {
      if (this.apply(this.type__fields__named) case var $1?) {
        if (this.apply(this.$125) case var $2?) {
          return $1;
        }
      }
    }
  };

  late final fragment14 = () {
    if (this.apply(this.$123) case var $0?) {
      if (this.apply(this.type__fields__named) case var $1?) {
        if (this.apply(this.$125) case var $2?) {
          return $1;
        }
      }
    }
  };

  late final fragment15 = () {
    if (this.apply(this.$44) case var $0?) {
      if (this.apply(this.$123) case var $1?) {
        if (this.apply(this.type__fields__named) case var $2?) {
          if (this.apply(this.$125) case var $3?) {
            return $2;
          }
        }
      }
    }
  };

  late final fragment16 = () {
    if (this.pos case var mark) {
      if (matchPattern(_regexp.$1) case var $?) {
        return $;
      }
      this.pos = mark;
      if (matchPattern(_regexp.$2) case var $?) {
        return $;
      }
    }
  };

  late final fragment17 = () {
    if (this.apply(this.identifier) case var $0?) {
      if (matchPattern("::") case var $1?) {
        return $0;
      }
    }
  };

  late final fragment18 = () {
    if (matchPattern("::") case var $0?) {
      if (this.apply(this.identifier) case var $1?) {
        return $1;
      }
    }
  };

  late final fragment19 = () {
    if (this.pos case var from) {
      if (matchPattern("\\") case var $0?) {
        if (matchPattern("\\") case var $1?) {
          if (($0, $1) case var $) {
            if (this.pos case var to) {
              return buffer.substring(from, to) ;
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
              return buffer.substring(from, to) ;
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
              return buffer.substring(from, to) ;
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
              return buffer.substring(from, to) ;
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
              return buffer.substring(from, to) ;
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
              return buffer.substring(from, to) ;
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
              return buffer.substring(from, to) ;
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
              return buffer.substring(from, to) ;
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
              return buffer.substring(from, to) ;
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
              return buffer.substring(from, to) ;
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
              return buffer.substring(from, to) ;
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
              return buffer.substring(from, to) ;
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
              return buffer.substring(from, to) ;
            }
          }
        }
      }
    }
  };

  ParserGenerator? document() {
    if (this.pos case var from) {
      if (this.pos case var $0 when this.pos <= 0) {
        if (this.apply(this.preamble) case (var $1 && var preamble)) {
          if (this.apply(this.statement) case var _0?) {
            if ([_0] case (var $2 && var statements && var _loop2)) {
              for (;;) {
                if (this.pos case var mark) {
                  if (this.applyNonNull(this._) case var _) {
                    if (this.apply(this.statement) case var _0?) {
                      _loop2.add(_0);
                      continue;
                    }
                  }
                  this.pos = mark;
                  break;
                }
              }
              if (this.pos case var mark) {
                if (this.applyNonNull(this._) case null) {
                  this.pos = mark;
                }
              }
              if (this.pos case var $3 when this.pos >= this.buffer.length) {
                if (($0, $1, $2, $3) case var $) {
                  if (this.pos case var to) {
                    return ParserGenerator.fromParsed(preamble: preamble, statements: statements)
                  ;
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  String? preamble() {
    if (this.pos case var from) {
      if (this.apply(this.$123) case var $0?) {
        if (this.applyNonNull(this._) case var $1) {
          if (this.applyNonNull(this.rawCode) case (var $2 && var rawCode)) {
            if (this.applyNonNull(this._) case var $3) {
              if (this.apply(this.$125) case var $4?) {
                if (($0, $1, $2, $3, $4) case var $) {
                  if (this.pos case var to) {
                    return rawCode ;
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  Statement? statement() {
    if (this.pos case var mark) {
      if (this.apply(this.namespace) case var $?) {
        return $;
      }
      this.pos = mark;
      if (this.apply(this.fragment) case var $?) {
        return $;
      }
      this.pos = mark;
      if (this.apply(this.rule) case var $?) {
        return $;
      }
    }
  }

  Statement? namespace() {
    if (this.pos case var from) {
      if (this.apply(this.identifier) case (var $0 && var name)?) {
        if (this.apply(this.$123) case var $1?) {
          if (this.apply(this.statement) case var _0?) {
            if ([_0] case (var $2 && var statements && var _loop2)) {
              for (;;) {
                if (this.pos case var mark) {
                  if (this.applyNonNull(this._) case var _) {
                    if (this.apply(this.statement) case var _0?) {
                      _loop2.add(_0);
                      continue;
                    }
                  }
                  this.pos = mark;
                  break;
                }
              }
              if (this.apply(this.$125) case var $3?) {
                if (($0, $1, $2, $3) case var $) {
                  if (this.pos case var to) {
                    return NamespaceStatement(name, statements)
                      ;
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  Statement? rule() {
    if (this.pos case var mark) {
      if (this.pos case var from) {
        if (this.apply(this.kw__var) case var $0?) {
          if (this.name() case (var $1 && var name)?) {
            if (this.body() case (var $2 && var body)?) {
              if (($0, $1, $2) case var $) {
                if (this.pos case var to) {
                  return DeclarationStatement(MapEntry((null, name), body), isFragment: false)
                    ;
                }
              }
            }
          }
        }
      }

      this.pos = mark;
      if (this.pos case var from) {
        if (this.name() case (var $0 && var name)?) {
          if (this.body() case (var $1 && var body)?) {
            if (($0, $1) case var $) {
              if (this.pos case var to) {
                return DeclarationStatement(MapEntry((null, name), body), isFragment: false)
                  ;
              }
            }
          }
        }
      }

      this.pos = mark;
      if (this.pos case var from) {
        if (this.apply(this.type__nonNullable) case (var $0 && var type)?) {
          if (this.name() case (var $1 && var name)?) {
            if (this.body() case (var $2 && var body)?) {
              if (($0, $1, $2) case var $) {
                if (this.pos case var to) {
                  return DeclarationStatement(MapEntry((type, name), body), isFragment: false)
                    ;
                }
              }
            }
          }
        }
      }

      this.pos = mark;
      if (this.pos case var from) {
        if (this.name() case (var $0 && var name)?) {
          if (this.apply(this.$58) case var $1?) {
            if (this.apply(this.type__nonNullable) case (var $2 && var type)?) {
              if (this.body() case (var $3 && var body)?) {
                if (($0, $1, $2, $3) case var $) {
                  if (this.pos case var to) {
                    return DeclarationStatement(MapEntry((type, name), body), isFragment: false)
                      ;
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  Statement? fragment() {
    if (this.pos case var mark) {
      if (this.pos case var from) {
        if (this.apply(this.kw__fragment) case var $0?) {
          if (this.apply(this.kw__var) case var $1?) {
            if (this.name() case (var $2 && var name)?) {
              if (this.body() case (var $3 && var body)?) {
                if (($0, $1, $2, $3) case var $) {
                  if (this.pos case var to) {
                    return DeclarationStatement(MapEntry((null, name), body), isFragment: true)
                      ;
                  }
                }
              }
            }
          }
        }
      }

      this.pos = mark;
      if (this.pos case var from) {
        if (this.apply(this.kw__fragment) case var $0?) {
          if (this.name() case (var $1 && var name)?) {
            if (this.body() case (var $2 && var body)?) {
              if (($0, $1, $2) case var $) {
                if (this.pos case var to) {
                  return DeclarationStatement(MapEntry((null, name), body), isFragment: true)
                    ;
                }
              }
            }
          }
        }
      }

      this.pos = mark;
      if (this.pos case var from) {
        if (this.apply(this.kw__fragment) case var $0?) {
          if (this.apply(this.type__nonNullable) case (var $1 && var type)?) {
            if (this.name() case (var $2 && var name)?) {
              if (this.body() case (var $3 && var body)?) {
                if (($0, $1, $2, $3) case var $) {
                  if (this.pos case var to) {
                    return DeclarationStatement(MapEntry((type, name), body), isFragment: true)
                      ;
                  }
                }
              }
            }
          }
        }
      }

      this.pos = mark;
      if (this.pos case var from) {
        if (this.apply(this.kw__fragment) case var $0?) {
          if (this.name() case (var $1 && var name)?) {
            if (this.apply(this.$58) case var $2?) {
              if (this.apply(this.type__nonNullable) case (var $3 && var type)?) {
                if (this.body() case (var $4 && var body)?) {
                  if (($0, $1, $2, $3, $4) case var $) {
                    if (this.pos case var to) {
                      return DeclarationStatement(MapEntry((type, name), body), isFragment: true)
                        ;
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

  Node? choice() {
    if (this.pos case var from) {
      if (this.apply(this.$124) case var $0) {
        if (this.apply(this.acted) case var _0?) {
          if ([_0] case (var $1 && var options && var _loop2)) {
            for (;;) {
              if (this.pos case var mark) {
                if (this.apply(this.$124) case var _?) {
                  if (this.apply(this.acted) case var _0?) {
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
                return options.length == 1 ? options.single : ChoiceNode(options) ;
              }
            }
          }
        }
      }
    }
  }

  Node? acted() {
    if (this.pos case var mark) {
      if (this.pos case var from) {
        if (this.apply(this.sequence) case (var $0 && var sequence)?) {
          if (this.apply(this.$40) case var $1?) {
            if (this.apply(this.$41) case var $2?) {
              if (this.apply(this.$123) case var $3?) {
                if (this.applyNonNull(this._) case var $4) {
                  if (this.applyNonNull(this.rawCode) case (var $5 && var rawCode)) {
                    if (this.applyNonNull(this._) case var $6) {
                      if (this.apply(this.$125) case var $7?) {
                        if (($0, $1, $2, $3, $4, $5, $6, $7) case var $) {
                          if (this.pos case var to) {
                            return ActionNode(sequence, rawCode, areIndicesProvided: true) ;
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
        if (this.apply(this.sequence) case (var $0 && var sequence)?) {
          if (this.apply(this.$123) case var $1?) {
            if (this.applyNonNull(this._) case var $2) {
              if (this.applyNonNull(this.rawCode) case (var $3 && var rawCode)) {
                if (this.applyNonNull(this._) case var $4) {
                  if (this.apply(this.$125) case var $5?) {
                    if (($0, $1, $2, $3, $4, $5) case var $) {
                      if (this.pos case var to) {
                        return InlineActionNode(sequence, rawCode, areIndicesProvided: true ) ;
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
      if (this.apply(this.sequence) case var $?) {
        return $;
      }
    }
  }

  Node? sequence() {
    if (this.pos case var mark) {
      if (this.pos case var from) {
        if (this.apply(this.labeled) case var _0?) {
          if ([_0] case (var $0 && var body && var _loop2)) {
            for (;;) {
              if (this.pos case var mark) {
                if (this.applyNonNull(this._) case var _) {
                  if (this.apply(this.labeled) case var _0?) {
                    _loop2.add(_0);
                    continue;
                  }
                }
                this.pos = mark;
                break;
              }
            }
            if (this.apply(this.$64) case var $1?) {
              if (this.apply(this.number) case (var $2 && var number)?) {
                if (($0, $1, $2) case var $) {
                  if (this.pos case var to) {
                    return body.length == 1
                          ? body.single
                          : SequenceNode(body, choose: number)
                      ;
                  }
                }
              }
            }
          }
        }
      }

      this.pos = mark;
      if (this.pos case var from) {
        if (this.apply(this.labeled) case var _2?) {
          if ([_2] case (var $ && var _loop4)) {
            for (;;) {
              if (this.pos case var mark) {
                if (this.applyNonNull(this._) case var _) {
                  if (this.apply(this.labeled) case var _2?) {
                    _loop4.add(_2);
                    continue;
                  }
                }
                this.pos = mark;
                break;
              }
            }
            if (this.pos case var to) {
              return $.length == 1 ? $.single : SequenceNode($, choose: null) ;
            }
          }
        }
      }
    }
  }

  Node? labeled() {
    if (this.pos case var mark) {
      if (this.pos case var from) {
        if (this.apply(this.identifier) case (var $0 && var identifier)?) {
          if (matchPattern(":") case var $1?) {
            if (this.applyNonNull(this._) case var $2) {
              if (this.apply(this.separated) case (var $3 && var separated)?) {
                if (($0, $1, $2, $3) case var $) {
                  if (this.pos case var to) {
                    return NamedNode(identifier, separated) ;
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
          if (this.apply(this.identifier) case var $1?) {
            if (this.apply(this.$63) case var $2?) {
              if (($0, $1, $2) case var $) {
                if (this.pos case var to) {
                  return NamedNode($1, OptionalNode(ReferenceNode($1))) ;
                }
              }
            }
          }
        }
      }

      this.pos = mark;
      if (this.pos case var from) {
        if (matchPattern(":") case var $0?) {
          if (this.apply(this.identifier) case var $1?) {
            if (this.apply(this.$42) case var $2?) {
              if (($0, $1, $2) case var $) {
                if (this.pos case var to) {
                  return NamedNode($1, StarNode(ReferenceNode($1))) ;
                }
              }
            }
          }
        }
      }

      this.pos = mark;
      if (this.pos case var from) {
        if (matchPattern(":") case var $0?) {
          if (this.apply(this.identifier) case var $1?) {
            if (this.apply(this.$43) case var $2?) {
              if (($0, $1, $2) case var $) {
                if (this.pos case var to) {
                  return NamedNode($1, PlusNode(ReferenceNode($1))) ;
                }
              }
            }
          }
        }
      }

      this.pos = mark;
      if (this.pos case var from) {
        if (matchPattern(":") case var $0?) {
          if (this.apply(this.identifier) case var $1?) {
            if (($0, $1) case var $) {
              if (this.pos case var to) {
                return NamedNode($1, ReferenceNode($1)) ;
              }
            }
          }
        }
      }

      this.pos = mark;
      if (this.apply(this.separated) case var $?) {
        return $;
      }
    }
  }

  Node? separated() {
    if (this.pos case var mark) {
      if (this.pos case var from) {
        if (this.apply(this.number) case (var $0 && var number)?) {
          if (this.apply(this.$46) case var $1?) {
            if (this.apply(this.atom) case (var $2 && var atom)?) {
              if (($0, $1, $2) case var $) {
                if (this.pos case var to) {
                  return CountedNode(number, number, atom) ;
                }
              }
            }
          }
        }
      }

      this.pos = mark;
      if (this.pos case var from) {
        if (this.apply(this.$91) case var $0?) {
          if (this.apply(this.number) case (var $1 && var number)?) {
            if (this.apply(this.$93) case var $2?) {
              if (this.apply(this.$46) case var $3) {
                if (this.apply(this.atom) case (var $4 && var atom)?) {
                  if (($0, $1, $2, $3, $4) case var $) {
                    if (this.pos case var to) {
                      return CountedNode(number, number, atom) ;
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
        if (this.apply(this.$91) case var $0?) {
          if (this.apply(this.number) case (var $1 && var min)?) {
            if (this.apply(this.$46_46) case var $2?) {
              if (this.apply(this.$93) case var $3?) {
                if (this.apply(this.$46) case var $4) {
                  if (this.apply(this.atom) case (var $5 && var atom)?) {
                    if (($0, $1, $2, $3, $4, $5) case var $) {
                      if (this.pos case var to) {
                        return CountedNode(min, null, atom) ;
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
        if (this.apply(this.$91) case var $0?) {
          if (this.apply(this.number) case (var $1 && var min)?) {
            if (this.apply(this.$46_46) case var $2?) {
              if (this.apply(this.number) case (var $3 && var max)?) {
                if (this.apply(this.$93) case var $4?) {
                  if (this.apply(this.$46) case var $5) {
                    if (this.apply(this.atom) case (var $6 && var atom)?) {
                      if (($0, $1, $2, $3, $4, $5, $6) case var $) {
                        if (this.pos case var to) {
                          return CountedNode(min, max, atom) ;
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
        if (this.apply(this.atom) case (var $0 && var sep)?) {
          if (this.apply(this.$46) case var $1?) {
            if (this.apply(this.atom) case (var $2 && var expr)?) {
              if (this.apply(this.$43) case var $3?) {
                if (this.apply(this.$63) case var $4?) {
                  if (($0, $1, $2, $3, $4) case var $) {
                    if (this.pos case var to) {
                      return PlusSeparatedNode(sep, expr, isTrailingAllowed: true) ;
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
        if (this.apply(this.atom) case (var $0 && var sep)?) {
          if (this.apply(this.$46) case var $1?) {
            if (this.apply(this.atom) case (var $2 && var expr)?) {
              if (this.apply(this.$42) case var $3?) {
                if (this.apply(this.$63) case var $4?) {
                  if (($0, $1, $2, $3, $4) case var $) {
                    if (this.pos case var to) {
                      return StarSeparatedNode(sep, expr, isTrailingAllowed: true) ;
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
        if (this.apply(this.atom) case (var $0 && var sep)?) {
          if (this.apply(this.$46) case var $1?) {
            if (this.apply(this.atom) case (var $2 && var expr)?) {
              if (this.apply(this.$43) case var $3?) {
                if (($0, $1, $2, $3) case var $) {
                  if (this.pos case var to) {
                    return PlusSeparatedNode(sep, expr, isTrailingAllowed: false) ;
                  }
                }
              }
            }
          }
        }
      }

      this.pos = mark;
      if (this.pos case var from) {
        if (this.apply(this.atom) case (var $0 && var sep)?) {
          if (this.apply(this.$46) case var $1?) {
            if (this.apply(this.atom) case (var $2 && var expr)?) {
              if (this.apply(this.$42) case var $3?) {
                if (($0, $1, $2, $3) case var $) {
                  if (this.pos case var to) {
                    return StarSeparatedNode(sep, expr, isTrailingAllowed: false) ;
                  }
                }
              }
            }
          }
        }
      }

      this.pos = mark;
      if (this.apply(this.postfix) case var $?) {
        return $;
      }
    }
  }

  Node? postfix() {
    if (this.pos case var mark) {
      if (this.pos case var from) {
        if (this.apply(this.postfix) case var $0?) {
          if (this.apply(this.$63) case var $1?) {
            if ($0 case var $) {
              if (this.pos case var to) {
                return OptionalNode($) ;
              }
            }
          }
        }
      }

      this.pos = mark;
      if (this.pos case var from) {
        if (this.apply(this.postfix) case var $0?) {
          if (this.apply(this.$42) case var $1?) {
            if ($0 case var $) {
              if (this.pos case var to) {
                return StarNode($) ;
              }
            }
          }
        }
      }

      this.pos = mark;
      if (this.pos case var from) {
        if (this.apply(this.postfix) case var $0?) {
          if (this.apply(this.$43) case var $1?) {
            if ($0 case var $) {
              if (this.pos case var to) {
                return PlusNode($) ;
              }
            }
          }
        }
      }

      this.pos = mark;
      if (this.apply(this.prefix) case var $?) {
        return $;
      }
    }
  }

  Node? prefix() {
    if (this.pos case var mark) {
      if (this.pos case var from) {
        if (this.apply(this.$38) case var $0?) {
          if (this.apply(this.prefix) case var $1?) {
            if ($1 case var $) {
              if (this.pos case var to) {
                return AndPredicateNode($) ;
              }
            }
          }
        }
      }

      this.pos = mark;
      if (this.pos case var from) {
        if (this.apply(this.$33) case var $0?) {
          if (this.apply(this.prefix) case var $1?) {
            if ($1 case var $) {
              if (this.pos case var to) {
                return NotPredicateNode($) ;
              }
            }
          }
        }
      }

      this.pos = mark;
      if (this.apply(this.atom) case var $?) {
        return $;
      }
    }
  }

  Node? atom() {
    if (this.pos case var mark) {
      if (this.pos case var from) {
        if (this.apply(this.mac__sep) case var $0?) {
          if (this.apply(this.$40) case var $1?) {
            if (this.apply(this.$43) case var $2?) {
              if (this.apply(this.$63) case var $3?) {
                if (this.apply(this.$41) case var $4?) {
                  if (this.apply(this.$123) case var $5?) {
                    if (this.apply(this.atom) case (var $6 && var sep)?) {
                      if (this.applyNonNull(this._) case var $7) {
                        if (this.apply(this.atom) case (var $8 && var body)?) {
                          if (this.apply(this.$125) case var $9?) {
                            if (($0, $1, $2, $3, $4, $5, $6, $7, $8, $9) case var $) {
                              if (this.pos case var to) {
                                return PlusSeparatedNode(sep, body, isTrailingAllowed: true) ;
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
        if (this.apply(this.mac__sep) case var $0?) {
          if (this.apply(this.$40) case var $1?) {
            if (this.apply(this.$42) case var $2?) {
              if (this.apply(this.$63) case var $3?) {
                if (this.apply(this.$41) case var $4?) {
                  if (this.apply(this.$123) case var $5?) {
                    if (this.apply(this.atom) case (var $6 && var sep)?) {
                      if (this.applyNonNull(this._) case var $7) {
                        if (this.apply(this.atom) case (var $8 && var body)?) {
                          if (this.apply(this.$125) case var $9?) {
                            if (($0, $1, $2, $3, $4, $5, $6, $7, $8, $9) case var $) {
                              if (this.pos case var to) {
                                return StarSeparatedNode(sep, body, isTrailingAllowed: true) ;
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
        if (this.apply(this.mac__sep) case var $0?) {
          if (this.apply(this.$40) case var $1?) {
            if (this.apply(this.$43) case var $2?) {
              if (this.apply(this.$41) case var $3?) {
                if (this.apply(this.$123) case var $4?) {
                  if (this.apply(this.atom) case (var $5 && var sep)?) {
                    if (this.applyNonNull(this._) case var $6) {
                      if (this.apply(this.atom) case (var $7 && var body)?) {
                        if (this.apply(this.$125) case var $8?) {
                          if (($0, $1, $2, $3, $4, $5, $6, $7, $8) case var $) {
                            if (this.pos case var to) {
                              return PlusSeparatedNode(sep, body, isTrailingAllowed: false) ;
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
        if (this.apply(this.mac__sep) case var $0?) {
          if (this.apply(this.$40) case var $1?) {
            if (this.apply(this.$42) case var $2?) {
              if (this.apply(this.$41) case var $3?) {
                if (this.apply(this.$123) case var $4?) {
                  if (this.apply(this.atom) case (var $5 && var sep)?) {
                    if (this.applyNonNull(this._) case var $6) {
                      if (this.apply(this.atom) case (var $7 && var body)?) {
                        if (this.apply(this.$125) case var $8?) {
                          if (($0, $1, $2, $3, $4, $5, $6, $7, $8) case var $) {
                            if (this.pos case var to) {
                              return StarSeparatedNode(sep, body, isTrailingAllowed: false) ;
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
        if (this.apply(this.mac__sep) case var $0?) {
          if (this.apply(this.$123) case var $1?) {
            if (this.apply(this.atom) case (var $2 && var sep)?) {
              if (this.applyNonNull(this._) case var $3) {
                if (this.apply(this.atom) case (var $4 && var body)?) {
                  if (this.apply(this.$125) case var $5?) {
                    if (($0, $1, $2, $3, $4, $5) case var $) {
                      if (this.pos case var to) {
                        return PlusSeparatedNode(sep, body, isTrailingAllowed: false) ;
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
      if (this.apply(this.$40) case var $0?) {
        if (this.apply(this.choice) case var $1?) {
          if (this.apply(this.$41) case var $2?) {
            return $1;
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.specialSymbol) case var $?) {
        return $;
      }
      this.pos = mark;
      if (this.pos case var from) {
        if (this.apply(this.regExpLiteral) case var $?) {
          if (this.pos case var to) {
            return RegExpNode(RegExp($)) ;
          }
        }
      }

      this.pos = mark;
      if (this.pos case var from) {
        if (this.apply(this.stringLiteral) case var $?) {
          if (this.pos case var to) {
            return StringLiteralNode($) ;
          }
        }
      }

      this.pos = mark;
      if (this.pos case var from) {
        if (this.name() case var $?) {
          if (this.pos case var to) {
            return ReferenceNode($) ;
          }
        }
      }
    }
  }

  Node? specialSymbol() {
    if (this.pos case var mark) {
      if (this.pos case var from) {
        if (this.pos case var mark) {
          if (this.apply(this.$94) case var $?) {
            if (this.pos case var to) {
              return const StartOfInputNode() ;
            }
          }
          this.pos = mark;
          if (this.apply(this.kw__start) case var $?) {
            if (this.pos case var to) {
              return const StartOfInputNode() ;
            }
          }
        }
      }

      this.pos = mark;
      if (this.pos case var from) {
        if (this.pos case var mark) {
          if (this.apply(this.$36) case var $?) {
            if (this.pos case var to) {
              return const EndOfInputNode() ;
            }
          }
          this.pos = mark;
          if (this.apply(this.kw__end) case var $?) {
            if (this.pos case var to) {
              return const EndOfInputNode() ;
            }
          }
        }
      }

      this.pos = mark;
      if (this.pos case var from) {
        if (this.pos case var mark) {
          if (this.apply(this.$46) case var $?) {
            if (this.pos case var to) {
              return const AnyCharacterNode() ;
            }
          }
          this.pos = mark;
          if (this.apply(this.kw__any) case var $?) {
            if (this.pos case var to) {
              return const AnyCharacterNode() ;
            }
          }
        }
      }

      this.pos = mark;
      if (this.pos case var from) {
        if (this.pos case var mark) {
          if (this.apply(this.$949) case var $?) {
            if (this.pos case var to) {
              return const EpsilonNode() ;
            }
          }
          this.pos = mark;
          if (this.apply(this.kw__epsilon) case var $?) {
            if (this.pos case var to) {
              return const EpsilonNode() ;
            }
          }
        }
      }

      this.pos = mark;
      if (this.pos case var from) {
        if (this.regexEscape__backslash() case var $?) {
          if (this.pos case var to) {
            return const StringLiteralNode(r"\") ;
          }
        }
      }

      this.pos = mark;
      if (this.pos case var from) {
        if (this.regexEscape__digit() case var $?) {
          if (this.pos case var to) {
            return SimpleRegExpEscapeNode.digit ;
          }
        }
      }

      this.pos = mark;
      if (this.pos case var from) {
        if (this.regexEscape__space() case var $?) {
          if (this.pos case var to) {
            return SimpleRegExpEscapeNode.whitespace ;
          }
        }
      }
    }
  }

  String rawCode() {
    if (this.pos case var from) {
      if (this.fragment0() case var _0) {
        if (this.pos case var mark) {
          if ([if (_0 case var _0?) _0] case (var $ && var code && var _loop2)) {
            if (_loop2.isNotEmpty) {
              for (;;) {
                if (this.pos case var mark) {
                  if (this.fragment0() case var _0?) {
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
              return code.join() ;
            }
          }
        }
      }
    }
  }

  String? identifier() {
    if (matchPattern(_regexp.$3) case var $?) {
      return $;
    }
  }

  String? regExpLiteral() {
    if (this.pos case var mark) {
      if (matchPattern("/") case var $0?) {
        if (this.fragment2() case var $1?) {
          if (matchPattern("/") case var $2?) {
            return $1;
          }
        }
      }
      this.pos = mark;
      if (this.pos case var from) {
        if (matchPattern(_regexp.$4) case var $?) {
          if (this.pos case var to) {
            return $.substring(4, $.length - 3) ;
          }
        }
      }

      this.pos = mark;
      if (this.pos case var from) {
        if (matchPattern(_regexp.$5) case var $?) {
          if (this.pos case var to) {
            return $.substring(4, $.length - 3) ;
          }
        }
      }

      this.pos = mark;
      if (this.pos case var from) {
        if (matchPattern(_regexp.$6) case var $?) {
          if (this.pos case var to) {
            return $.substring(2, $.length - 1) ;
          }
        }
      }

      this.pos = mark;
      if (this.pos case var from) {
        if (matchPattern(_regexp.$7) case var $?) {
          if (this.pos case var to) {
            return $.substring(2, $.length - 1) ;
          }
        }
      }
    }
  }

  String? stringLiteral() {
    if (this.pos case var mark) {
      if (matchPattern("\"\"\"") case var $0?) {
        if (this.fragment4() case var $1) {
          if (matchPattern("\"\"\"") case var $2?) {
            return $1;
          }
        }
      }
      this.pos = mark;
      if (matchPattern("'''") case var $0?) {
        if (this.fragment6() case var $1) {
          if (matchPattern("'''") case var $2?) {
            return $1;
          }
        }
      }
      this.pos = mark;
      if (matchPattern("\"") case var $0?) {
        if (this.fragment8() case var $1) {
          if (matchPattern("\"") case var $2?) {
            return $1;
          }
        }
      }
      this.pos = mark;
      if (matchPattern("'") case var $0?) {
        if (this.fragment10() case var $1) {
          if (matchPattern("'") case var $2?) {
            return $1;
          }
        }
      }
    }
  }

  String? rawLiteral() {
    if (this.pos case var from) {
      if (matchPattern("`") case var $0?) {
        if (this.fragment11() case var _0) {
          if (this.pos case var mark) {
            if ([if (_0 case var _0?) _0] case (var $1 && var inner && var _loop2)) {
              if (_loop2.isNotEmpty) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.fragment11() case var _0?) {
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
  }

  int? number() {
    if (this.pos case var from) {
      if (matchPattern(_regexp.$8) case var _0?) {
        if ([_0] case (var $ && var _loop2)) {
          for (;;) {
            if (this.pos case var mark) {
              if (matchPattern(_regexp.$8) case var _0?) {
                _loop2.add(_0);
                continue;
              }
              this.pos = mark;
              break;
            }
          }
          if (this.pos case var to) {
            return int.parse(buffer.substring(from, to)) ;
          }
        }
      }
    }
  }

  String? type__nullable() {
    if (this.pos case var mark) {
      if (this.pos case var from) {
        if (this.applyNonNull(this._) case var $0) {
          if (this.apply(this.type__nonNullable) case (var $1 && var nonNullable)?) {
            if (this.applyNonNull(this._) case var $2) {
              if (this.apply(this.$63) case var $3?) {
                if (($0, $1, $2, $3) case var $) {
                  if (this.pos case var to) {
                    return "$nonNullable?" ;
                  }
                }
              }
            }
          }
        }
      }

      this.pos = mark;
      if (this.applyNonNull(this._) case var $0) {
        if (this.apply(this.type__nonNullable) case var $1?) {
          if (this.applyNonNull(this._) case var $2) {
            return $1;
          }
        }
      }
    }
  }

  String? type__nonNullable() {
    if (this.applyNonNull(this._) case var $0) {
      if (this.fragment12() case var $1?) {
        if (this.applyNonNull(this._) case var $2) {
          return $1;
        }
      }
    }
  }

  String? type__record() {
    if (this.pos case var mark) {
      if (this.pos case var from) {
        if (this.apply(this.$40) case var $0?) {
          if (this.fragment13() case var $1) {
            if (this.apply(this.$41) case var $2?) {
              if (($0, $1, $2) case var $) {
                if (this.pos case var to) {
                  return "(" + ($1 == null ? "" : "{" + $1 + "}") + ")"
                      ;
                }
              }
            }
          }
        }
      }

      this.pos = mark;
      if (this.pos case var from) {
        if (this.apply(this.$40) case var $0?) {
          if (this.apply(this.type__field__positional) case var $1?) {
            if (this.apply(this.$44) case var $2?) {
              if (this.fragment14() case var $3) {
                if (this.apply(this.$41) case var $4?) {
                  if (($0, $1, $2, $3, $4) case var $) {
                    if (this.pos case var to) {
                      return "(${$1}, ${$3 == null ? "" : "{${$3}}"})"
                          ;
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
        if (this.apply(this.$40) case var $0?) {
          if (this.apply(this.type__fields__positional) case var $1?) {
            if (this.fragment15() case var $2) {
              if (this.apply(this.$41) case var $3?) {
                if (($0, $1, $2, $3) case var $) {
                  if (this.pos case var to) {
                    return "(" + $1 + ($2 == null ? "" : ", {" + $2 + "}") + ")"
                        ;
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  String? type__generic() {
    if (this.pos case var from) {
      if (this.apply(this.type__base) case (var $0 && var base)?) {
        if (this.apply(this.$60) case var $1?) {
          if (this.apply(this.type__arguments) case (var $2 && var arguments)?) {
            if (this.apply(this.$62) case var $3?) {
              if (($0, $1, $2, $3) case var $) {
                if (this.pos case var to) {
                  return "$base<$arguments>" ;
                }
              }
            }
          }
        }
      }
    }
  }

  String? type__arguments() {
    if (this.pos case var from) {
      if (this.apply(this.type__nullable) case var _0?) {
        if ([_0] case (var $ && var _loop2)) {
          for (;;) {
            if (this.pos case var mark) {
              if (this.apply(this.$44) case var _?) {
                if (this.apply(this.type__nullable) case var _0?) {
                  _loop2.add(_0);
                  continue;
                }
              }
              this.pos = mark;
              break;
            }
          }
          if (this.pos case var to) {
            return $.join(", ") ;
          }
        }
      }
    }
  }

  String? type__base() {
    if (this.pos case var from) {
      if (this.apply(this.identifier) case var _0?) {
        if ([_0] case (var $ && var _loop2)) {
          for (;;) {
            if (this.pos case var mark) {
              if (this.apply(this.$46) case var _?) {
                if (this.apply(this.identifier) case var _0?) {
                  _loop2.add(_0);
                  continue;
                }
              }
              this.pos = mark;
              break;
            }
          }
          if (this.pos case var to) {
            return $.join(".") ;
          }
        }
      }
    }
  }

  String? type__fields__positional() {
    if (this.pos case var from) {
      if (this.apply(this.type__field__positional) case var _0?) {
        if ([_0] case (var $ && var _loop2)) {
          for (;;) {
            if (this.pos case var mark) {
              if (this.apply(this.$44) case var _?) {
                if (this.apply(this.type__field__positional) case var _0?) {
                  _loop2.add(_0);
                  continue;
                }
              }
              this.pos = mark;
              break;
            }
          }
          if (this.pos case var to) {
            return $.join(", ") ;
          }
        }
      }
    }
  }

  String? type__fields__named() {
    if (this.pos case var from) {
      if (this.apply(this.type__field__named) case var _0?) {
        if ([_0] case (var $ && var _loop2)) {
          for (;;) {
            if (this.pos case var mark) {
              if (this.apply(this.$44) case var _?) {
                if (this.apply(this.type__field__named) case var _0?) {
                  _loop2.add(_0);
                  continue;
                }
              }
              this.pos = mark;
              break;
            }
          }
          if (this.pos case var to) {
            return $.join(", ") ;
          }
        }
      }
    }
  }

  String? type__field__positional() {
    if (this.pos case var from) {
      if (this.apply(this.type__nullable) case var $0?) {
        if (this.applyNonNull(this._) case var $1) {
          if (this.apply(this.identifier) case var $2) {
            if (($0, $1, $2) case var $) {
              if (this.pos case var to) {
                return "${$0} ${$2 ?? ""}".trimRight() ;
              }
            }
          }
        }
      }
    }
  }

  String? type__field__named() {
    if (this.pos case var from) {
      if (this.apply(this.type__nullable) case var $0?) {
        if (this.applyNonNull(this._) case var $1) {
          if (this.apply(this.identifier) case var $2?) {
            if (($0, $1, $2) case var $) {
              if (this.pos case var to) {
                return "${$0} ${$2}" ;
              }
            }
          }
        }
      }
    }
  }

  String? kw__rule() {
    if (this.applyNonNull(this._) case var $0) {
      if (matchPattern("@rule") case var $1?) {
        if (this.applyNonNull(this._) case var $2) {
          return $1;
        }
      }
    }
  }

  String? kw__fragment() {
    if (this.applyNonNull(this._) case var $0) {
      if (matchPattern("@fragment") case var $1?) {
        if (this.applyNonNull(this._) case var $2) {
          return $1;
        }
      }
    }
  }

  String? kw__start() {
    if (this.applyNonNull(this._) case var $0) {
      if (matchPattern("startOfInput") case var $1?) {
        if (this.applyNonNull(this._) case var $2) {
          return $1;
        }
      }
    }
  }

  String? kw__end() {
    if (this.applyNonNull(this._) case var $0) {
      if (matchPattern("endOfInput") case var $1?) {
        if (this.applyNonNull(this._) case var $2) {
          return $1;
        }
      }
    }
  }

  String? kw__backslash() {
    if (this.applyNonNull(this._) case var $0) {
      if (matchPattern("backslash") case var $1?) {
        if (this.applyNonNull(this._) case var $2) {
          return $1;
        }
      }
    }
  }

  String? kw__epsilon() {
    if (this.applyNonNull(this._) case var $0) {
      if (matchPattern("epsilon") case var $1?) {
        if (this.applyNonNull(this._) case var $2) {
          return $1;
        }
      }
    }
  }

  String? kw__any() {
    if (this.applyNonNull(this._) case var $0) {
      if (matchPattern("any") case var $1?) {
        if (this.applyNonNull(this._) case var $2) {
          return $1;
        }
      }
    }
  }

  String? kw__var() {
    if (this.applyNonNull(this._) case var $0) {
      if (matchPattern("var") case var $1?) {
        if (this.applyNonNull(this._) case var $2) {
          return $1;
        }
      }
    }
  }

  String? mac__sep() {
    if (this.applyNonNull(this._) case var $0) {
      if (matchPattern("sep!") case var $1?) {
        if (this.applyNonNull(this._) case var $2) {
          return $1;
        }
      }
    }
  }

  String? mac__parse() {
    if (this.applyNonNull(this._) case var $0) {
      if (matchPattern("=>") case var $1?) {
        if (this.applyNonNull(this._) case var $2) {
          return $1;
        }
      }
    }
  }

  late final $46_46 = () {
    if (this.applyNonNull(this._) case var $0) {
      if (matchPattern(".") case var _0?) {
        if ([_0] case (var $1 && var _loop2)) {
          while (_loop2.length < 2) {
            if (this.pos case var mark) {
              if (matchPattern(".") case var _0?) {
                _loop2.add(_0);
                continue;
              }
              this.pos = mark;
              break;
            }
          }
          if (_loop2.length >= 2) {
            if (this.applyNonNull(this._) case var $2) {
              return $1;
            }
          }
        }
      }
    }
  };

  late final $58_58 = () {
    if (this.applyNonNull(this._) case var $0) {
      if (matchPattern(":") case var _0?) {
        if ([_0] case (var $1 && var _loop2)) {
          while (_loop2.length < 2) {
            if (this.pos case var mark) {
              if (matchPattern(":") case var _0?) {
                _loop2.add(_0);
                continue;
              }
              this.pos = mark;
              break;
            }
          }
          if (_loop2.length >= 2) {
            if (this.applyNonNull(this._) case var $2) {
              return $1;
            }
          }
        }
      }
    }
  };

  late final $37_37 = () {
    if (this.applyNonNull(this._) case var $0) {
      if (matchPattern("%") case var _0?) {
        if ([_0] case (var $1 && var _loop2)) {
          while (_loop2.length < 2) {
            if (this.pos case var mark) {
              if (matchPattern("%") case var _0?) {
                _loop2.add(_0);
                continue;
              }
              this.pos = mark;
              break;
            }
          }
          if (_loop2.length >= 2) {
            if (this.applyNonNull(this._) case var $2) {
              return $1;
            }
          }
        }
      }
    }
  };

  late final $949 = () {
    if (this.applyNonNull(this._) case var $0) {
      if (matchPattern("ε") case var $1?) {
        if (this.applyNonNull(this._) case var $2) {
          return $1;
        }
      }
    }
  };

  late final $64 = () {
    if (this.applyNonNull(this._) case var $0) {
      if (matchPattern("@") case var $1?) {
        if (this.applyNonNull(this._) case var $2) {
          return $1;
        }
      }
    }
  };

  late final $60 = () {
    if (this.applyNonNull(this._) case var $0) {
      if (matchPattern("<") case var $1?) {
        if (this.applyNonNull(this._) case var $2) {
          return $1;
        }
      }
    }
  };

  late final $62 = () {
    if (this.applyNonNull(this._) case var $0) {
      if (matchPattern(">") case var $1?) {
        if (this.applyNonNull(this._) case var $2) {
          return $1;
        }
      }
    }
  };

  late final $93 = () {
    if (this.applyNonNull(this._) case var $0) {
      if (matchPattern("]") case var $1?) {
        if (this.applyNonNull(this._) case var $2) {
          return $1;
        }
      }
    }
  };

  late final $91 = () {
    if (this.applyNonNull(this._) case var $0) {
      if (matchPattern("[") case var $1?) {
        if (this.applyNonNull(this._) case var $2) {
          return $1;
        }
      }
    }
  };

  late final $125 = () {
    if (this.applyNonNull(this._) case var $0) {
      if (matchPattern("}") case var $1?) {
        if (this.applyNonNull(this._) case var $2) {
          return $1;
        }
      }
    }
  };

  late final $123 = () {
    if (this.applyNonNull(this._) case var $0) {
      if (matchPattern("{") case var $1?) {
        if (this.applyNonNull(this._) case var $2) {
          return $1;
        }
      }
    }
  };

  late final $41 = () {
    if (this.applyNonNull(this._) case var $0) {
      if (matchPattern(")") case var $1?) {
        if (this.applyNonNull(this._) case var $2) {
          return $1;
        }
      }
    }
  };

  late final $40 = () {
    if (this.applyNonNull(this._) case var $0) {
      if (matchPattern("(") case var $1?) {
        if (this.applyNonNull(this._) case var $2) {
          return $1;
        }
      }
    }
  };

  late final $94 = () {
    if (this.applyNonNull(this._) case var $0) {
      if (matchPattern("^") case var $1?) {
        if (this.applyNonNull(this._) case var $2) {
          return $1;
        }
      }
    }
  };

  late final $36 = () {
    if (this.applyNonNull(this._) case var $0) {
      if (matchPattern("\$") case var $1?) {
        if (this.applyNonNull(this._) case var $2) {
          return $1;
        }
      }
    }
  };

  late final $46 = () {
    if (this.applyNonNull(this._) case var $0) {
      if (matchPattern(".") case var $1?) {
        if (this.applyNonNull(this._) case var $2) {
          return $1;
        }
      }
    }
  };

  late final $44 = () {
    if (this.applyNonNull(this._) case var $0) {
      if (matchPattern(",") case var $1?) {
        if (this.applyNonNull(this._) case var $2) {
          return $1;
        }
      }
    }
  };

  late final $58 = () {
    if (this.applyNonNull(this._) case var $0) {
      if (matchPattern(":") case var $1?) {
        if (this.applyNonNull(this._) case var $2) {
          return $1;
        }
      }
    }
  };

  late final $59 = () {
    if (this.applyNonNull(this._) case var $0) {
      if (matchPattern(";") case var $1?) {
        if (this.applyNonNull(this._) case var $2) {
          return $1;
        }
      }
    }
  };

  late final $124 = () {
    if (this.applyNonNull(this._) case var $0) {
      if (matchPattern("|") case var $1?) {
        if (this.applyNonNull(this._) case var $2) {
          return $1;
        }
      }
    }
  };

  late final $61 = () {
    if (this.applyNonNull(this._) case var $0) {
      if (matchPattern("=") case var $1?) {
        if (this.applyNonNull(this._) case var $2) {
          return $1;
        }
      }
    }
  };

  late final $63 = () {
    if (this.applyNonNull(this._) case var $0) {
      if (matchPattern("?") case var $1?) {
        if (this.applyNonNull(this._) case var $2) {
          return $1;
        }
      }
    }
  };

  late final $33 = () {
    if (this.applyNonNull(this._) case var $0) {
      if (matchPattern("!") case var $1?) {
        if (this.applyNonNull(this._) case var $2) {
          return $1;
        }
      }
    }
  };

  late final $38 = () {
    if (this.applyNonNull(this._) case var $0) {
      if (matchPattern("&") case var $1?) {
        if (this.applyNonNull(this._) case var $2) {
          return $1;
        }
      }
    }
  };

  late final $42 = () {
    if (this.applyNonNull(this._) case var $0) {
      if (matchPattern("*") case var $1?) {
        if (this.applyNonNull(this._) case var $2) {
          return $1;
        }
      }
    }
  };

  late final $43 = () {
    if (this.applyNonNull(this._) case var $0) {
      if (matchPattern("+") case var $1?) {
        if (this.applyNonNull(this._) case var $2) {
          return $1;
        }
      }
    }
  };

  late final _ = () {
    if (this.pos case var from) {
      if (this.fragment16() case var _0) {
        if (this.pos case var mark) {
          if ([if (_0 case var _0?) _0] case (var $ && var _loop2)) {
            if (_loop2.isNotEmpty) {
              for (;;) {
                if (this.pos case var mark) {
                  if (this.fragment16() case var _0?) {
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
              return "" ;
            }
          }
        }
      }
    }
  };

  static final _regexp = (
    RegExp("\\s"),
    RegExp("\\/{2}.*(?:(?:\\r?\\n)|(?:\$))"),
    RegExp("[a-zA-Z_][a-zA-Z\\d_]*"),
    RegExp("r\"{3}((?:(?:\\\\.)|(?!\"{3}).)*)\"{3}"),
    RegExp("r'{3}((?:(?:\\\\.)|(?!'{3}).)*)'{3}"),
    RegExp("r\"((?:(?:\\\\.)|[^\"])*)\""),
    RegExp("r'((?:(?:\\\\.)|[^'])*)'"),
    RegExp("\\d"),
  );
}
