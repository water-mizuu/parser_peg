// ignore_for_file: always_declare_return_types, always_put_control_body_on_new_line, always_specify_types, avoid_escaping_inner_quotes, avoid_redundant_argument_values, annotate_overrides, body_might_complete_normally_nullable, constant_pattern_never_matches_value_type, curly_braces_in_flow_control_structures, dead_code, directives_ordering, duplicate_ignore, inference_failure_on_function_return_type, constant_identifier_names, prefer_function_declarations_over_variables, prefer_interpolation_to_compose_strings, prefer_is_empty, no_leading_underscores_for_local_identifiers, non_constant_identifier_names, unnecessary_null_check_pattern, unnecessary_brace_in_string_interps, unnecessary_string_interpolations, unnecessary_this, unused_element, unused_import, prefer_double_quotes, unused_local_variable, unreachable_from_main, use_raw_strings, type_annotate_public_apis

// imports
// ignore_for_file: collection_methods_unrelated_type

import "dart:collection";
import "dart:math" as math;
// PREAMBLE
import "package:parser_peg/src/node.dart";
import "package:parser_peg/src/generator.dart";
import "package:parser_peg/src/statement.dart";

final _regexps = (
  from: RegExp(r"\bfrom\b"),
  to: RegExp(r"\bto\b"),
);
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
  final Map<(Pattern, int), (int, String)> _patternMemo = <(Pattern, int), (int, String)>{};

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

extension NullableExtension<T extends Object> on T {
  @pragma("vm:prefer-inline")
  T? asNullable() => this;
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


  /// `global::type`
  String? f0() {
    if (this.pos case var mark) {
      if (this.ft() case _) {
        if (this.f3s() case var $1?) {
          return $1;
        }
      }
      this.pos = mark;
      if (this.apply(this.rk) case var $?) {
        return $;
      }
    }
  }

  /// `global::namespaceReference`
  String f1() {
    if (this.pos case var mark) {
      if (this.f3v() case var _0) {
        if ([if (_0 case var _0?) _0] case (var $ && var _l1)) {
          if (_l1.isNotEmpty) {
            for (;;) {
              if (this.pos case var mark) {
                if (this.f3v() case var _0?) {
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
          return $.join(ParserGenerator.separator);
        }
      }
    }
  }

  /// `global::namespacedIdentifier`
  String? f2() {
    if (this.f1() case var $0) {
      if (this.f8() case var $1?) {
        if (($0, $1) case var $) {
          return $0.isEmpty ? $1 : "${$0}::${$1}";
        }
      }
    }
  }

  /// `global::name`
  String? f3() {
    if (this.pos case var mark) {
      if (this.f1() case var $0) {
        if (this.f6() case var $1?) {
          if (($0, $1) case var $) {
            return $0.isEmpty ? $1 : "${$0}::${$1}";
          }
        }
      }
      this.pos = mark;
      if (this.f2() case var $?) {
        return $;
      }
    }
  }

  /// `global::body`
  Node? f4() {
    if (this.f3z() case _?) {
      if (this.apply(this.r5) case var choice?) {
        if (this.f41() case _?) {
          return choice;
        }
      }
    }
  }

  /// `global::literal::range::atom`
  String? f5() {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$1) case _?) {
        if (this.pos < this.buffer.length) {
          if (this.buffer[this.pos] case var $1) {
            this.pos++;
            return $1;
          }
        }
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.matchPattern(_string.$2) case null) {
          this.pos = mark;
          if (this.pos < this.buffer.length) {
            if (this.buffer[this.pos] case var $1) {
              this.pos++;
              return $1;
            }
          }
        }
      }
    }
  }

  /// `global::literal::raw`
  String? f6() {
    if (this.matchPattern(_string.$3) case var $0?) {
      if (this.f43() case var $1?) {
        if ($1 case var $) {
          return $.join();
        }
      }
    }
  }

  /// `global::dart::type::fields::named`
  String? f7() {
    if (this.f10() case var _0?) {
      if ([_0] case (var $ && var _l1)) {
        for (;;) {
          if (this.pos case var mark) {
            if (this.fq() case _?) {
              if (this.f10() case var _0?) {
                _l1.add(_0);
                continue;
              }
            }
            this.pos = mark;
            break;
          }
        }
        return $.join(", ");
      }
    }
  }

  /// `global::identifier`
  String? f8() {
    if (this.matchRange(_range.$2) case var $0?) {
      if (this.pos case var mark) {
        if (this.matchRange(_range.$1) case var _0) {
          if ([if (_0 case var _0?) _0] case (var $1 && var _l1)) {
            if (_l1.isNotEmpty) {
              for (;;) {
                if (this.pos case var mark) {
                  if (this.matchRange(_range.$1) case var _0?) {
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
            return $0 + $1.join();
          }
        }
      }
    }
  }

  /// `global::number`
  int? f9() {
    if (matchPattern(_regexp.$1) case var _0?) {
      if ([_0] case (var $ && var _l1)) {
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
        return int.parse($.join());
      }
    }
  }

  /// `global::kw::decorator`
  Tag? fa() {
    if (this.pos case var mark) {
      if (this.fb() case var $?) {
        return $;
      }
      this.pos = mark;
      if (this.fc() case var $?) {
        return $;
      }
      this.pos = mark;
      if (this.fd() case var $?) {
        return $;
      }
    }
  }

  /// `global::kw::decorator::rule`
  Tag? fb() {
    if (this.ft() case var $0) {
      if (this.matchPattern(_string.$4) case var $1?) {
        if (this.ft() case var $2) {
          return Tag.rule;
        }
      }
    }
  }

  /// `global::kw::decorator::fragment`
  Tag? fc() {
    if (this.ft() case var $0) {
      if (this.matchPattern(_string.$5) case var $1?) {
        if (this.ft() case var $2) {
          return Tag.fragment;
        }
      }
    }
  }

  /// `global::kw::decorator::inline`
  Tag? fd() {
    if (this.ft() case var $0) {
      if (this.matchPattern(_string.$6) case var $1?) {
        if (this.ft() case var $2) {
          return Tag.inline;
        }
      }
    }
  }

  /// `global::kw::var`
  String? fe() {
    if (this.ft() case _) {
      if (this.matchPattern(_string.$7) case var $1?) {
        if (this.ft() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::mac::range`
  String? ff() {
    if (this.ft() case _) {
      if (this.matchPattern(_string.$8) case var $1?) {
        if (this.ft() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::mac::flat`
  String? fg() {
    if (this.ft() case _) {
      if (this.matchPattern(_string.$9) case var $1?) {
        if (this.ft() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::mac::sep`
  String? fh() {
    if (this.ft() case _) {
      if (this.matchPattern(_string.$10) case var $1?) {
        if (this.ft() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::..`
  String? fi() {
    if (this.ft() case _) {
      if (this.f44() case var $1?) {
        return $1;
      }
    }
  }

  /// `global::}`
  String? fj() {
    if (this.ft() case _) {
      if (this.f45() case var $1?) {
        return $1;
      }
    }
  }

  /// `global::{`
  String? fk() {
    if (this.ft() case _) {
      if (this.f46() case var $1?) {
        return $1;
      }
    }
  }

  /// `global::)`
  String? fl() {
    if (this.ft() case _) {
      if (this.f47() case var $1?) {
        return $1;
      }
    }
  }

  /// `global::(`
  String? fm() {
    if (this.ft() case _) {
      if (this.f48() case var $1?) {
        return $1;
      }
    }
  }

  /// `global::?`
  String? fn() {
    if (this.ft() case _) {
      if (this.f49() case var $1?) {
        return $1;
      }
    }
  }

  /// `global::*`
  String? fo() {
    if (this.ft() case _) {
      if (this.f4a() case var $1?) {
        return $1;
      }
    }
  }

  /// `global::+`
  String? fp() {
    if (this.ft() case _) {
      if (this.f4b() case var $1?) {
        return $1;
      }
    }
  }

  /// `global::,`
  String? fq() {
    if (this.ft() case _) {
      if (this.f4c() case var $1?) {
        return $1;
      }
    }
  }

  /// `global::|`
  String? fr() {
    if (this.ft() case _) {
      if (this.f4d() case var $1?) {
        return $1;
      }
    }
  }

  /// `global::.`
  String? fs() {
    if (this.ft() case _) {
      if (this.f4e() case var $1?) {
        return $1;
      }
    }
  }

  /// `global::_`
  String ft() {
    if (this.pos case var mark) {
      if (this.f4f() case var _0) {
        if ([if (_0 case var _0?) _0] case var _l1) {
          if (_l1.isNotEmpty) {
            for (;;) {
              if (this.pos case var mark) {
                if (this.f4f() case var _0?) {
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
          return "";
        }
      }
    }
  }

  /// `ROOT`
  ParserGenerator? fu() {
    if (this.apply(this.r0) case var $?) {
      return $;
    }
  }

  /// `global::dart::literal::string::body`
  late final fv = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$12) case var $0?) {
        if (this.matchPattern(_string.$11) case var $1?) {
          if (this.pos case var mark) {
            if (this.f4g() case var _0) {
              if ([if (_0 case var _0?) _0] case (var $2 && var _l1)) {
                if (_l1.isNotEmpty) {
                  for (;;) {
                    if (this.pos case var mark) {
                      if (this.f4g() case var _0?) {
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
                if (this.matchPattern(_string.$11) case var $3?) {
                  return ();
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$12) case var $0?) {
        if (this.matchPattern(_string.$13) case var $1?) {
          if (this.pos case var mark) {
            if (this.f4h() case var _2) {
              if ([if (_2 case var _2?) _2] case (var $2 && var _l3)) {
                if (_l3.isNotEmpty) {
                  for (;;) {
                    if (this.pos case var mark) {
                      if (this.f4h() case var _2?) {
                        _l3.add(_2);
                        continue;
                      }
                      this.pos = mark;
                      break;
                    }
                  }
                } else {
                  this.pos = mark;
                }
                if (this.matchPattern(_string.$13) case var $3?) {
                  return ();
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$12) case var $0?) {
        if (this.matchPattern(_string.$14) case var $1?) {
          if (this.pos case var mark) {
            if (this.f4i() case var _4) {
              if ([if (_4 case var _4?) _4] case (var $2 && var _l5)) {
                if (_l5.isNotEmpty) {
                  for (;;) {
                    if (this.pos case var mark) {
                      if (this.f4i() case var _4?) {
                        _l5.add(_4);
                        continue;
                      }
                      this.pos = mark;
                      break;
                    }
                  }
                } else {
                  this.pos = mark;
                }
                if (this.matchPattern(_string.$14) case var $3?) {
                  return ();
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$12) case var $0?) {
        if (this.matchPattern(_string.$15) case var $1?) {
          if (this.pos case var mark) {
            if (this.f4j() case var _6) {
              if ([if (_6 case var _6?) _6] case (var $2 && var _l7)) {
                if (_l7.isNotEmpty) {
                  for (;;) {
                    if (this.pos case var mark) {
                      if (this.f4j() case var _6?) {
                        _l7.add(_6);
                        continue;
                      }
                      this.pos = mark;
                      break;
                    }
                  }
                } else {
                  this.pos = mark;
                }
                if (this.matchPattern(_string.$15) case var $3?) {
                  return ();
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$11) case var $0?) {
        if (this.pos case var mark) {
          if (this.f4k() case var _8) {
            if ([if (_8 case var _8?) _8] case (var $1 && var _l9)) {
              if (_l9.isNotEmpty) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.f4k() case var _8?) {
                      _l9.add(_8);
                      continue;
                    }
                    this.pos = mark;
                    break;
                  }
                }
              } else {
                this.pos = mark;
              }
              if (this.matchPattern(_string.$11) case var $2?) {
                return ();
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$13) case var $0?) {
        if (this.pos case var mark) {
          if (this.f4l() case var _10) {
            if ([if (_10 case var _10?) _10] case (var $1 && var _l11)) {
              if (_l11.isNotEmpty) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.f4l() case var _10?) {
                      _l11.add(_10);
                      continue;
                    }
                    this.pos = mark;
                    break;
                  }
                }
              } else {
                this.pos = mark;
              }
              if (this.matchPattern(_string.$13) case var $2?) {
                return ();
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$14) case var $0?) {
        if (this.pos case var mark) {
          if (this.f4m() case var _12) {
            if ([if (_12 case var _12?) _12] case (var $1 && var _l13)) {
              if (_l13.isNotEmpty) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.f4m() case var _12?) {
                      _l13.add(_12);
                      continue;
                    }
                    this.pos = mark;
                    break;
                  }
                }
              } else {
                this.pos = mark;
              }
              if (this.matchPattern(_string.$14) case var $2?) {
                return ();
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$15) case var $0?) {
        if (this.pos case var mark) {
          if (this.f4n() case var _14) {
            if ([if (_14 case var _14?) _14] case (var $1 && var _l15)) {
              if (_l15.isNotEmpty) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.f4n() case var _14?) {
                      _l15.add(_14);
                      continue;
                    }
                    this.pos = mark;
                    break;
                  }
                }
              } else {
                this.pos = mark;
              }
              if (this.matchPattern(_string.$15) case var $2?) {
                return ();
              }
            }
          }
        }
      }
    }
  };

  /// `global::dart::literal::string::interpolation`
  late final fw = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$18) case var $0?) {
        if (this.matchPattern(_string.$17) case var $1?) {
          if (this.apply(this.rj)! case var $2) {
            if (this.matchPattern(_string.$16) case var $3?) {
              return ($0, $1, $2, $3);
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$18) case var $0?) {
        if (this.apply(this.ri) case var $1?) {
          return ($0, $1);
        }
      }
    }
  };

  /// `global::dart::type::generic`
  String? fx() {
    if (this.f4o() case var base?) {
      if (this.f4q() case _?) {
        if (this.fy() case var arguments?) {
          if (this.f4s() case _?) {
            return "$base<$arguments>";
          }
        }
      }
    }
  }

  /// `global::dart::type::arguments`
  String? fy() {
    if (this.apply(this.rl) case var _0?) {
      if ([_0] case (var $ && var _l1)) {
        for (;;) {
          if (this.pos case var mark) {
            if (this.fq() case _?) {
              if (this.apply(this.rl) case var _0?) {
                _l1.add(_0);
                continue;
              }
            }
            this.pos = mark;
            break;
          }
        }
        return $.join(", ");
      }
    }
  }

  /// `global::dart::type::field::positional`
  String? fz() {
    if (this.apply(this.rl) case var $0?) {
      if (this.ft() case var $1) {
        if (this.f8() case var $2) {
          if (($0, $1, $2) case var $) {
            return "${$0} ${$2 ?? ""}".trimRight();
          }
        }
      }
    }
  }

  /// `global::dart::type::field::named`
  String? f10() {
    if (this.apply(this.rl) case var $0?) {
      if (this.ft() case var $1) {
        if (this.f8() case var $2?) {
          if (($0, $1, $2) case var $) {
            return "${$0} ${$2}";
          }
        }
      }
    }
  }

  /// `global::dart::type::fields::positional`
  String? f11() {
    if (this.fz() case var _0?) {
      if ([_0] case (var $ && var _l1)) {
        for (;;) {
          if (this.pos case var mark) {
            if (this.fq() case _?) {
              if (this.fz() case var _0?) {
                _l1.add(_0);
                continue;
              }
            }
            this.pos = mark;
            break;
          }
        }
        return $.join(", ");
      }
    }
  }

  /// `fragment0`
  late final f12 = () {
    if (this.matchPattern(_string.$19) case var $0?) {
      if (this.ft() case _) {
        return $0;
      }
    }
  };

  /// `fragment1`
  late final f13 = () {
    if (this.ft() case _) {
      if (this.f12() case var $1?) {
        return $1;
      }
    }
  };

  /// `fragment2`
  late final f14 = () {
    if (this.matchPattern(_string.$20) case var $0?) {
      if (this.ft() case _) {
        return $0;
      }
    }
  };

  /// `fragment3`
  late final f15 = () {
    if (this.ft() case _) {
      if (this.f14() case var $1?) {
        return $1;
      }
    }
  };

  /// `fragment4`
  late final f16 = () {
    if (this.matchPattern(_string.$21) case var $0?) {
      if (this.ft() case _) {
        return $0;
      }
    }
  };

  /// `fragment5`
  late final f17 = () {
    if (this.ft() case _) {
      if (this.f16() case var $1?) {
        return $1;
      }
    }
  };

  /// `fragment6`
  late final f18 = () {
    if (this.f17() case _?) {
      if (this.f9() case var $1?) {
        return $1;
      }
    }
  };

  /// `fragment7`
  late final f19 = () {
    if (this.matchPattern(_string.$22) case var $0?) {
      if (this.ft() case _) {
        return $0;
      }
    }
  };

  /// `fragment8`
  late final f1a = () {
    if (this.ft() case _) {
      if (this.f19() case var $1?) {
        return $1;
      }
    }
  };

  /// `fragment9`
  late final f1b = () {
    if (this.matchPattern(_string.$23) case var $0?) {
      if (this.ft() case _) {
        return $0;
      }
    }
  };

  /// `fragment10`
  late final f1c = () {
    if (this.ft() case _) {
      if (this.f1b() case var $1?) {
        return $1;
      }
    }
  };

  /// `fragment11`
  late final f1d = () {
    if (this.matchPattern(_string.$24) case var $0?) {
      if (this.ft() case _) {
        return $0;
      }
    }
  };

  /// `fragment12`
  late final f1e = () {
    if (this.ft() case _) {
      if (this.f1d() case var $1?) {
        return $1;
      }
    }
  };

  /// `fragment13`
  late final f1f = () {
    if (this.matchPattern(_string.$25) case var $0?) {
      if (this.ft() case _) {
        return $0;
      }
    }
  };

  /// `fragment14`
  late final f1g = () {
    if (this.ft() case _) {
      if (this.f1f() case var $1?) {
        return $1;
      }
    }
  };

  /// `fragment15`
  late final f1h = () {
    if (this.matchPattern(_string.$26) case var $0?) {
      if (this.ft() case _) {
        return $0;
      }
    }
  };

  /// `fragment16`
  late final f1i = () {
    if (this.ft() case _) {
      if (this.f1h() case var $1?) {
        return $1;
      }
    }
  };

  /// `fragment17`
  late final f1j = () {
    if (this.apply(this.r5) case var $0?) {
      if (this.fl() case _?) {
        return $0;
      }
    }
  };

  /// `fragment18`
  late final f1k = () {
    if (this.matchPattern(_string.$27) case var $0?) {
      if (this.ft() case _) {
        return $0;
      }
    }
  };

  /// `fragment19`
  late final f1l = () {
    if (this.matchPattern(_string.$18) case var $0?) {
      if (this.ft() case _) {
        return $0;
      }
    }
  };

  /// `fragment20`
  late final f1m = () {
    if (this.matchPattern(_string.$28) case var $0?) {
      if (this.ft() case _) {
        return $0;
      }
    }
  };

  /// `fragment21`
  late final f1n = () {
    if (this.pos case var from) {
      if (this.matchPattern(_string.$1) case var $0?) {
        if (this.matchPattern(_string.$1) case var $1?) {
          if (this.pos case var to) {
            return this.buffer.substring(from, to);
          }
        }
      }
    }
  };

  /// `fragment22`
  late final f1o = () {
    if (this.f1n() case var $0?) {
      if (this.ft() case _) {
        return $0;
      }
    }
  };

  /// `fragment23`
  late final f1p = () {
    if (this.pos case var from) {
      if (this.matchPattern(_string.$1) case var $0?) {
        if (this.matchPattern(_string.$29) case var $1?) {
          if (this.pos case var to) {
            return this.buffer.substring(from, to);
          }
        }
      }
    }
  };

  /// `fragment24`
  late final f1q = () {
    if (this.f1p() case var $0?) {
      if (this.ft() case _) {
        return $0;
      }
    }
  };

  /// `fragment25`
  late final f1r = () {
    if (this.pos case var from) {
      if (this.matchPattern(_string.$1) case var $0?) {
        if (this.matchPattern(_string.$30) case var $1?) {
          if (this.pos case var to) {
            return this.buffer.substring(from, to);
          }
        }
      }
    }
  };

  /// `fragment26`
  late final f1s = () {
    if (this.f1r() case var $0?) {
      if (this.ft() case _) {
        return $0;
      }
    }
  };

  /// `fragment27`
  late final f1t = () {
    if (this.pos case var from) {
      if (this.matchPattern(_string.$1) case var $0?) {
        if (this.matchPattern(_string.$31) case var $1?) {
          if (this.pos case var to) {
            return this.buffer.substring(from, to);
          }
        }
      }
    }
  };

  /// `fragment28`
  late final f1u = () {
    if (this.f1t() case var $0?) {
      if (this.ft() case _) {
        return $0;
      }
    }
  };

  /// `fragment29`
  late final f1v = () {
    if (this.pos case var from) {
      if (this.matchPattern(_string.$1) case var $0?) {
        if (this.matchPattern(_string.$29) case var $1?) {
          if (this.pos case var to) {
            return this.buffer.substring(from, to);
          }
        }
      }
    }
  };

  /// `fragment30`
  late final f1w = () {
    if (this.f1v() case var $0?) {
      if (this.ft() case _) {
        return $0;
      }
    }
  };

  /// `fragment31`
  late final f1x = () {
    if (this.pos case var from) {
      if (this.matchPattern(_string.$1) case var $0?) {
        if (this.matchPattern(_string.$30) case var $1?) {
          if (this.pos case var to) {
            return this.buffer.substring(from, to);
          }
        }
      }
    }
  };

  /// `fragment32`
  late final f1y = () {
    if (this.f1x() case var $0?) {
      if (this.ft() case _) {
        return $0;
      }
    }
  };

  /// `fragment33`
  late final f1z = () {
    if (this.pos case var from) {
      if (this.matchPattern(_string.$1) case var $0?) {
        if (this.matchPattern(_string.$31) case var $1?) {
          if (this.pos case var to) {
            return this.buffer.substring(from, to);
          }
        }
      }
    }
  };

  /// `fragment34`
  late final f20 = () {
    if (this.f1z() case var $0?) {
      if (this.ft() case _) {
        return $0;
      }
    }
  };

  /// `fragment35`
  late final f21 = () {
    if (this.pos case var from) {
      if (this.matchPattern(_string.$1) case var $0?) {
        if (this.matchPattern(_string.$32) case var $1?) {
          if (this.pos case var to) {
            return this.buffer.substring(from, to);
          }
        }
      }
    }
  };

  /// `fragment36`
  late final f22 = () {
    if (this.f21() case var $0?) {
      if (this.ft() case _) {
        return $0;
      }
    }
  };

  /// `fragment37`
  late final f23 = () {
    if (this.pos case var from) {
      if (this.matchPattern(_string.$1) case var $0?) {
        if (this.matchPattern(_string.$33) case var $1?) {
          if (this.pos case var to) {
            return this.buffer.substring(from, to);
          }
        }
      }
    }
  };

  /// `fragment38`
  late final f24 = () {
    if (this.f23() case var $0?) {
      if (this.ft() case _) {
        return $0;
      }
    }
  };

  /// `fragment39`
  late final f25 = () {
    if (this.pos case var from) {
      if (this.matchPattern(_string.$1) case var $0?) {
        if (this.matchPattern(_string.$12) case var $1?) {
          if (this.pos case var to) {
            return this.buffer.substring(from, to);
          }
        }
      }
    }
  };

  /// `fragment40`
  late final f26 = () {
    if (this.f25() case var $0?) {
      if (this.ft() case _) {
        return $0;
      }
    }
  };

  /// `fragment41`
  late final f27 = () {
    if (this.pos case var from) {
      if (this.matchPattern(_string.$1) case var $0?) {
        if (this.matchPattern(_string.$34) case var $1?) {
          if (this.pos case var to) {
            return this.buffer.substring(from, to);
          }
        }
      }
    }
  };

  /// `fragment42`
  late final f28 = () {
    if (this.f27() case var $0?) {
      if (this.ft() case _) {
        return $0;
      }
    }
  };

  /// `fragment43`
  late final f29 = () {
    if (this.pos case var from) {
      if (this.matchPattern(_string.$1) case var $0?) {
        if (this.matchPattern(_string.$35) case var $1?) {
          if (this.pos case var to) {
            return this.buffer.substring(from, to);
          }
        }
      }
    }
  };

  /// `fragment44`
  late final f2a = () {
    if (this.f29() case var $0?) {
      if (this.ft() case _) {
        return $0;
      }
    }
  };

  /// `fragment45`
  late final f2b = () {
    if (this.pos case var from) {
      if (this.matchPattern(_string.$1) case var $0?) {
        if (this.matchPattern(_string.$29) case var $1?) {
          if (this.pos case var to) {
            return this.buffer.substring(from, to);
          }
        }
      }
    }
  };

  /// `fragment46`
  late final f2c = () {
    if (this.f2b() case var $0?) {
      if (this.ft() case _) {
        return $0;
      }
    }
  };

  /// `fragment47`
  late final f2d = () {
    if (this.pos case var from) {
      if (this.matchPattern(_string.$1) case var $0?) {
        if (this.matchPattern(_string.$30) case var $1?) {
          if (this.pos case var to) {
            return this.buffer.substring(from, to);
          }
        }
      }
    }
  };

  /// `fragment48`
  late final f2e = () {
    if (this.f2d() case var $0?) {
      if (this.ft() case _) {
        return $0;
      }
    }
  };

  /// `fragment49`
  late final f2f = () {
    if (this.pos case var from) {
      if (this.matchPattern(_string.$1) case var $0?) {
        if (this.matchPattern(_string.$31) case var $1?) {
          if (this.pos case var to) {
            return this.buffer.substring(from, to);
          }
        }
      }
    }
  };

  /// `fragment50`
  late final f2g = () {
    if (this.f2f() case var $0?) {
      if (this.ft() case _) {
        return $0;
      }
    }
  };

  /// `fragment51`
  late final f2h = () {
    if (this.pos case var from) {
      if (this.matchPattern(_string.$1) case var $0?) {
        if (this.matchPattern(_string.$33) case var $1?) {
          if (this.pos case var to) {
            return this.buffer.substring(from, to);
          }
        }
      }
    }
  };

  /// `fragment52`
  late final f2i = () {
    if (this.f2h() case var $0?) {
      if (this.ft() case _) {
        return $0;
      }
    }
  };

  /// `fragment53`
  late final f2j = () {
    if (this.pos case var from) {
      if (this.matchPattern(_string.$1) case var $0?) {
        if (this.matchPattern(_string.$12) case var $1?) {
          if (this.pos case var to) {
            return this.buffer.substring(from, to);
          }
        }
      }
    }
  };

  /// `fragment54`
  late final f2k = () {
    if (this.f2j() case var $0?) {
      if (this.ft() case _) {
        return $0;
      }
    }
  };

  /// `fragment55`
  late final f2l = () {
    if (this.pos case var from) {
      if (this.matchPattern(_string.$1) case var $0?) {
        if (this.matchPattern(_string.$32) case var $1?) {
          if (this.pos case var to) {
            return this.buffer.substring(from, to);
          }
        }
      }
    }
  };

  /// `fragment56`
  late final f2m = () {
    if (this.f2l() case var $0?) {
      if (this.ft() case _) {
        return $0;
      }
    }
  };

  /// `fragment57`
  late final f2n = () {
    if (this.pos case var from) {
      if (this.matchPattern(_string.$1) case var $0?) {
        if (this.matchPattern(_string.$1) case var $1?) {
          if (this.pos case var to) {
            return this.buffer.substring(from, to);
          }
        }
      }
    }
  };

  /// `fragment58`
  late final f2o = () {
    if (this.f2n() case var $0?) {
      if (this.ft() case _) {
        return $0;
      }
    }
  };

  /// `fragment59`
  late final f2p = () {
    if (this.pos case var mark) {
      if (this.pos case var mark) {
        if (this.matchPattern(_string.$36) case var $?) {
          return {(32, 32)};
        }
        this.pos = mark;
        if (this.ft() case var $0) {
          if (this.f2c() case var $1?) {
            return {(48, 57)};
          }
        }
        this.pos = mark;
        if (this.ft() case var $0) {
          if (this.f2e() case var $1?) {
            return {(64 + 1, 64 + 26), (96 + 1, 96 + 26)};
          }
        }
        this.pos = mark;
        if (this.ft() case var $0) {
          if (this.f2g() case var $1?) {
            return {(9, 13), (32, 32)};
          }
        }
        this.pos = mark;
        if (this.ft() case var $0) {
          if (this.f2i() case var $1?) {
            return {(10, 10)};
          }
        }
        this.pos = mark;
        if (this.ft() case var $0) {
          if (this.f2k() case var $1?) {
            return {(13, 13)};
          }
        }
        this.pos = mark;
        if (this.ft() case var $0) {
          if (this.f2m() case var $1?) {
            return {(9, 9)};
          }
        }
        this.pos = mark;
        if (this.ft() case var $0) {
          if (this.f2o() case var $1?) {
            return {(92, 92)};
          }
        }
      }

      this.pos = mark;
      if (this.f5() case var l?) {
        if (this.matchPattern(_string.$37) case _?) {
          if (this.f5() case var r?) {
            return {(l.codeUnitAt(0), r.codeUnitAt(0))};
          }
        }
      }
      this.pos = mark;
      if (this.f5() case var $?) {
        return {($.codeUnitAt(0), $.codeUnitAt(0))};
      }
    }
  };

  /// `fragment60`
  late final f2q = () {
    if (this.ft() case _) {
      if (this.matchPattern(_string.$38) case _?) {
        if (this.f2p() case var _0?) {
          if ([_0] case (var elements && var _l1)) {
            for (;;) {
              if (this.pos case var mark) {
                if (this.ft() case _) {
                  if (this.f2p() case var _0?) {
                    _l1.add(_0);
                    continue;
                  }
                }
                this.pos = mark;
                break;
              }
            }
            if (this.matchPattern(_string.$2) case _?) {
              if (this.ft() case _) {
                return RangeNode(elements.reduce((a, b) => a.union(b)));
              }
            }
          }
        }
      }
    }
  };

  /// `fragment61`
  late final f2r = () {
    if (this.f2q() case var $0?) {
      if (this.ft() case _) {
        return $0;
      }
    }
  };

  /// `fragment62`
  late final f2s = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$1) case var $0?) {
        if (this.pos < this.buffer.length) {
          if (this.buffer[this.pos] case var $1) {
            this.pos++;
            if ($1 case var $) {
              return r"\" + $;
            }
          }
        }
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.matchPattern(_string.$39) case null) {
          this.pos = mark;
          if (this.pos < this.buffer.length) {
            if (this.buffer[this.pos] case var $1) {
              this.pos++;
              return $1;
            }
          }
        }
      }
    }
  };

  /// `fragment63`
  late final f2t = () {
    if (this.f2s() case var _0?) {
      if ([_0] case (var $ && var _l1)) {
        for (;;) {
          if (this.pos case var mark) {
            if (this.f2s() case var _0?) {
              _l1.add(_0);
              continue;
            }
            this.pos = mark;
            break;
          }
        }
        return $.join();
      }
    }
  };

  /// `fragment64`
  late final f2u = () {
    if (this.f2t() case var $0?) {
      if (this.matchPattern(_string.$39) case _?) {
        return $0;
      }
    }
  };

  /// `fragment65`
  late final f2v = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$11) case null) {
        this.pos = mark;
        if (this.pos < this.buffer.length) {
          if (this.buffer[this.pos] case var $1) {
            this.pos++;
            return $1;
          }
        }
      }
    }
  };

  /// `fragment66`
  late final f2w = () {
    if (this.pos case var mark) {
      if (this.f2v() case var _0) {
        if ([if (_0 case var _0?) _0] case (var $0 && var _l1)) {
          if (_l1.isNotEmpty) {
            for (;;) {
              if (this.pos case var mark) {
                if (this.f2v() case var _0?) {
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
          if (this.matchPattern(_string.$11) case _?) {
            return $0;
          }
        }
      }
    }
  };

  /// `fragment67`
  late final f2x = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$13) case null) {
        this.pos = mark;
        if (this.pos < this.buffer.length) {
          if (this.buffer[this.pos] case var $1) {
            this.pos++;
            return $1;
          }
        }
      }
    }
  };

  /// `fragment68`
  late final f2y = () {
    if (this.pos case var mark) {
      if (this.f2x() case var _0) {
        if ([if (_0 case var _0?) _0] case (var $0 && var _l1)) {
          if (_l1.isNotEmpty) {
            for (;;) {
              if (this.pos case var mark) {
                if (this.f2x() case var _0?) {
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
          if (this.matchPattern(_string.$13) case _?) {
            return $0;
          }
        }
      }
    }
  };

  /// `fragment69`
  late final f2z = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$14) case null) {
        this.pos = mark;
        if (this.pos < this.buffer.length) {
          if (this.buffer[this.pos] case var $1) {
            this.pos++;
            return $1;
          }
        }
      }
    }
  };

  /// `fragment70`
  late final f30 = () {
    if (this.pos case var mark) {
      if (this.f2z() case var _0) {
        if ([if (_0 case var _0?) _0] case (var $0 && var _l1)) {
          if (_l1.isNotEmpty) {
            for (;;) {
              if (this.pos case var mark) {
                if (this.f2z() case var _0?) {
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
          if (this.matchPattern(_string.$14) case _?) {
            return $0;
          }
        }
      }
    }
  };

  /// `fragment71`
  late final f31 = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$15) case null) {
        this.pos = mark;
        if (this.pos < this.buffer.length) {
          if (this.buffer[this.pos] case var $1) {
            this.pos++;
            return $1;
          }
        }
      }
    }
  };

  /// `fragment72`
  late final f32 = () {
    if (this.pos case var mark) {
      if (this.f31() case var _0) {
        if ([if (_0 case var _0?) _0] case (var $0 && var _l1)) {
          if (_l1.isNotEmpty) {
            for (;;) {
              if (this.pos case var mark) {
                if (this.f31() case var _0?) {
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
          if (this.matchPattern(_string.$15) case _?) {
            return $0;
          }
        }
      }
    }
  };

  /// `fragment73`
  late final f33 = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$1) case _?) {
        if (this.pos < this.buffer.length) {
          if (this.buffer[this.pos] case var $1) {
            this.pos++;
            return $1;
          }
        }
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.matchPattern(_string.$11) case null) {
          this.pos = mark;
          if (this.pos < this.buffer.length) {
            if (this.buffer[this.pos] case var $1) {
              this.pos++;
              return $1;
            }
          }
        }
      }
    }
  };

  /// `fragment74`
  late final f34 = () {
    if (this.pos case var mark) {
      if (this.f33() case var _0) {
        if ([if (_0 case var _0?) _0] case (var $0 && var _l1)) {
          if (_l1.isNotEmpty) {
            for (;;) {
              if (this.pos case var mark) {
                if (this.f33() case var _0?) {
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
          if (this.matchPattern(_string.$11) case _?) {
            return $0;
          }
        }
      }
    }
  };

  /// `fragment75`
  late final f35 = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$1) case _?) {
        if (this.pos < this.buffer.length) {
          if (this.buffer[this.pos] case var $1) {
            this.pos++;
            return $1;
          }
        }
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.matchPattern(_string.$13) case null) {
          this.pos = mark;
          if (this.pos < this.buffer.length) {
            if (this.buffer[this.pos] case var $1) {
              this.pos++;
              return $1;
            }
          }
        }
      }
    }
  };

  /// `fragment76`
  late final f36 = () {
    if (this.pos case var mark) {
      if (this.f35() case var _0) {
        if ([if (_0 case var _0?) _0] case (var $0 && var _l1)) {
          if (_l1.isNotEmpty) {
            for (;;) {
              if (this.pos case var mark) {
                if (this.f35() case var _0?) {
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
          if (this.matchPattern(_string.$13) case _?) {
            return $0;
          }
        }
      }
    }
  };

  /// `fragment77`
  late final f37 = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$1) case _?) {
        if (this.pos < this.buffer.length) {
          if (this.buffer[this.pos] case var $1) {
            this.pos++;
            return $1;
          }
        }
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.matchPattern(_string.$14) case null) {
          this.pos = mark;
          if (this.pos < this.buffer.length) {
            if (this.buffer[this.pos] case var $1) {
              this.pos++;
              return $1;
            }
          }
        }
      }
    }
  };

  /// `fragment78`
  late final f38 = () {
    if (this.pos case var mark) {
      if (this.f37() case var _0) {
        if ([if (_0 case var _0?) _0] case (var $0 && var _l1)) {
          if (_l1.isNotEmpty) {
            for (;;) {
              if (this.pos case var mark) {
                if (this.f37() case var _0?) {
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
          if (this.matchPattern(_string.$14) case _?) {
            return $0;
          }
        }
      }
    }
  };

  /// `fragment79`
  late final f39 = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$1) case _?) {
        if (this.pos < this.buffer.length) {
          if (this.buffer[this.pos] case var $1) {
            this.pos++;
            return $1;
          }
        }
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.matchPattern(_string.$15) case null) {
          this.pos = mark;
          if (this.pos < this.buffer.length) {
            if (this.buffer[this.pos] case var $1) {
              this.pos++;
              return $1;
            }
          }
        }
      }
    }
  };

  /// `fragment80`
  late final f3a = () {
    if (this.pos case var mark) {
      if (this.f39() case var _0) {
        if ([if (_0 case var _0?) _0] case (var $0 && var _l1)) {
          if (_l1.isNotEmpty) {
            for (;;) {
              if (this.pos case var mark) {
                if (this.f39() case var _0?) {
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
          if (this.matchPattern(_string.$15) case _?) {
            return $0;
          }
        }
      }
    }
  };

  /// `fragment81`
  late final f3b = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$40) case var $0?) {
        if (this.f2w() case var $1?) {
          if ($1 case var $) {
            return $.join();
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$41) case var $0?) {
        if (this.f2y() case var $1?) {
          if ($1 case var $) {
            return $.join();
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$42) case var $0?) {
        if (this.f30() case var $1?) {
          if ($1 case var $) {
            return $.join();
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$43) case var $0?) {
        if (this.f32() case var $1?) {
          if ($1 case var $) {
            return $.join();
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$11) case var $0?) {
        if (this.f34() case var $1?) {
          if ($1 case var $) {
            return $.join();
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$13) case var $0?) {
        if (this.f36() case var $1?) {
          if ($1 case var $) {
            return $.join();
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$14) case var $0?) {
        if (this.f38() case var $1?) {
          if ($1 case var $) {
            return $.join();
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$15) case var $0?) {
        if (this.f3a() case var $1?) {
          if ($1 case var $) {
            return $.join();
          }
        }
      }
    }
  };

  /// `fragment82`
  late final f3c = () {
    if (this.f3b() case var $0?) {
      if (this.ft() case _) {
        return $0;
      }
    }
  };

  /// `fragment83`
  late final f3d = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$3) case null) {
        this.pos = mark;
        if (this.pos < this.buffer.length) {
          if (this.buffer[this.pos] case var $1) {
            this.pos++;
            return $1;
          }
        }
      }
    }
  };

  /// `fragment84`
  late final f3e = () {
    if (this.pos case var mark) {
      if (this.f3d() case var _0) {
        if ([if (_0 case var _0?) _0] case (var $0 && var _l1)) {
          if (_l1.isNotEmpty) {
            for (;;) {
              if (this.pos case var mark) {
                if (this.f3d() case var _0?) {
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
          if (this.matchPattern(_string.$3) case _?) {
            return $0;
          }
        }
      }
    }
  };

  /// `fragment85`
  late final f3f = () {
    if (this.apply(this.rg)! case var $0) {
      if (this.matchPattern(_string.$16) case _?) {
        return $0;
      }
    }
  };

  /// `fragment86`
  late final f3g = () {
    if (this.pos case var mark) {
      if (this.apply(this.rh) case var $?) {
        return $;
      }
      this.pos = mark;
      if (this.matchPattern(_string.$17) case var $0?) {
        if (this.f3f() case var $1?) {
          if ($1 case var $) {
            return "{" + $ + "}";
          }
        }
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.matchTrie(_trie.$1) case null) {
          this.pos = mark;
          if (this.pos < this.buffer.length) {
            if (this.buffer[this.pos] case var $1) {
              this.pos++;
              return $1;
            }
          }
        }
      }
    }
  };

  /// `fragment87`
  late final f3h = () {
    if (this.pos case var from) {
      if (this.fv() case var $?) {
        if (this.pos case var to) {
          return this.buffer.substring(from, to);
        }
      }
    }
  };

  /// `fragment88`
  late final f3i = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$17) case _?) {
        if (this.apply(this.rj)! case var $1) {
          if (this.matchPattern(_string.$16) case _?) {
            return $1;
          }
        }
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.matchTrie(_trie.$1) case null) {
          this.pos = mark;
          if (this.pos < this.buffer.length) {
            if (this.buffer[this.pos] case var $1) {
              this.pos++;
              return $1;
            }
          }
        }
      }
    }
  };

  /// `fragment89`
  late final f3j = () {
    if (this.apply(this.rl) case var $0?) {
      if (this.ft() case _) {
        return $0;
      }
    }
  };

  /// `fragment90`
  late final f3k = () {
    if (this.f7() case var $0?) {
      if (this.fj() case _?) {
        return $0;
      }
    }
  };

  /// `fragment91`
  late final f3l = () {
    if (this.fk() case _?) {
      if (this.f3k() case var $1?) {
        return $1;
      }
    }
  };

  /// `fragment92`
  late final f3m = () {
    if (this.f7() case var $0?) {
      if (this.fj() case _?) {
        return $0;
      }
    }
  };

  /// `fragment93`
  late final f3n = () {
    if (this.fk() case _?) {
      if (this.f3m() case var $1?) {
        return $1;
      }
    }
  };

  /// `fragment94`
  late final f3o = () {
    if (this.fq() case _?) {
      if (this.fk() case _?) {
        if (this.f7() case var $2?) {
          if (this.fj() case _?) {
            return $2;
          }
        }
      }
    }
  };

  /// `fragment95`
  late final f3p = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$3) case null) {
        this.pos = mark;
        if (this.pos < this.buffer.length) {
          if (this.buffer[this.pos] case var $1) {
            this.pos++;
            return $1;
          }
        }
      }
    }
  };

  /// `fragment96`
  late final f3q = () {
    if (this.pos case var mark) {
      if (this.f3p() case var _0) {
        if ([if (_0 case var _0?) _0] case (var $0 && var _l1)) {
          if (_l1.isNotEmpty) {
            for (;;) {
              if (this.pos case var mark) {
                if (this.f3p() case var _0?) {
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
          if (this.matchPattern(_string.$3) case _?) {
            return $0;
          }
        }
      }
    }
  };

  /// `fragment97`
  late final f3r = () {
    if (this.matchPattern(_string.$3) case var $0?) {
      if (this.f3q() case var $1?) {
        if ($1 case var $) {
          return $.join();
        }
      }
    }
  };

  /// `fragment98`
  late final f3s = () {
    if (this.f3r() case var $0?) {
      if (this.ft() case _) {
        return $0;
      }
    }
  };

  /// `fragment99`
  late final f3t = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$44) case var $?) {
        return $;
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.matchPattern(_string.$46) case (var $0 && null)) {
          this.pos = mark;
          if (this.matchPattern(_string.$45) case var $1?) {
            return ($0, $1);
          }
        }
      }
    }
  };

  /// `fragment100`
  late final f3u = () {
    if (this.pos case var mark) {
      if (this.ff() case var $?) {
        return $;
      }
      this.pos = mark;
      if (this.fg() case var $?) {
        return $;
      }
      this.pos = mark;
      if (this.fh() case var $?) {
        return $;
      }
    }
  };

  /// `fragment101`
  late final f3v = () {
    if (this.f8() case var $0?) {
      if (this.f3t() case _?) {
        if (this.pos case var mark) {
          if (this.f3u() case null) {
            this.pos = mark;
            return $0;
          }
        }
      }
    }
  };

  /// `fragment102`
  late final f3w = () {
    if (this.matchPattern(_string.$47) case var $0?) {
      if (this.ft() case _) {
        return $0;
      }
    }
  };

  /// `fragment103`
  late final f3x = () {
    if (this.matchPattern(_string.$48) case var $0?) {
      if (this.ft() case _) {
        return $0;
      }
    }
  };

  /// `fragment104`
  late final f3y = () {
    if (this.matchPattern(_string.$49) case var $0?) {
      if (this.ft() case _) {
        return $0;
      }
    }
  };

  /// `fragment105`
  late final f3z = () {
    if (this.pos case var mark) {
      if (this.ft() case _) {
        if (this.f3w() case var $1?) {
          return $1;
        }
      }
      this.pos = mark;
      if (this.ft() case _) {
        if (this.f3x() case var $1?) {
          return $1;
        }
      }
      this.pos = mark;
      if (this.ft() case _) {
        if (this.f3y() case var $1?) {
          return $1;
        }
      }
    }
  };

  /// `fragment106`
  late final f40 = () {
    if (this.matchPattern(_string.$50) case var $0?) {
      if (this.ft() case _) {
        return $0;
      }
    }
  };

  /// `fragment107`
  late final f41 = () {
    if (this.ft() case _) {
      if (this.f40() case var $1?) {
        return $1;
      }
    }
  };

  /// `fragment108`
  late final f42 = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$3) case null) {
        this.pos = mark;
        if (this.pos < this.buffer.length) {
          if (this.buffer[this.pos] case var $1) {
            this.pos++;
            return $1;
          }
        }
      }
    }
  };

  /// `fragment109`
  late final f43 = () {
    if (this.pos case var mark) {
      if (this.f42() case var _0) {
        if ([if (_0 case var _0?) _0] case (var $0 && var _l1)) {
          if (_l1.isNotEmpty) {
            for (;;) {
              if (this.pos case var mark) {
                if (this.f42() case var _0?) {
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
          if (this.matchPattern(_string.$3) case _?) {
            return $0;
          }
        }
      }
    }
  };

  /// `fragment110`
  late final f44 = () {
    if (this.matchPattern(_string.$46) case var $0?) {
      if (this.ft() case _) {
        return $0;
      }
    }
  };

  /// `fragment111`
  late final f45 = () {
    if (this.matchPattern(_string.$16) case var $0?) {
      if (this.ft() case _) {
        return $0;
      }
    }
  };

  /// `fragment112`
  late final f46 = () {
    if (this.matchPattern(_string.$17) case var $0?) {
      if (this.ft() case _) {
        return $0;
      }
    }
  };

  /// `fragment113`
  late final f47 = () {
    if (this.matchPattern(_string.$51) case var $0?) {
      if (this.ft() case _) {
        return $0;
      }
    }
  };

  /// `fragment114`
  late final f48 = () {
    if (this.matchPattern(_string.$52) case var $0?) {
      if (this.ft() case _) {
        return $0;
      }
    }
  };

  /// `fragment115`
  late final f49 = () {
    if (this.matchPattern(_string.$53) case var $0?) {
      if (this.ft() case _) {
        return $0;
      }
    }
  };

  /// `fragment116`
  late final f4a = () {
    if (this.matchPattern(_string.$54) case var $0?) {
      if (this.ft() case _) {
        return $0;
      }
    }
  };

  /// `fragment117`
  late final f4b = () {
    if (this.matchPattern(_string.$55) case var $0?) {
      if (this.ft() case _) {
        return $0;
      }
    }
  };

  /// `fragment118`
  late final f4c = () {
    if (this.matchPattern(_string.$56) case var $0?) {
      if (this.ft() case _) {
        return $0;
      }
    }
  };

  /// `fragment119`
  late final f4d = () {
    if (this.matchPattern(_string.$57) case var $0?) {
      if (this.ft() case _) {
        return $0;
      }
    }
  };

  /// `fragment120`
  late final f4e = () {
    if (this.matchPattern(_string.$45) case var $0?) {
      if (this.ft() case _) {
        return $0;
      }
    }
  };

  /// `fragment121`
  late final f4f = () {
    if (this.pos case var mark) {
      if (matchPattern(_regexp.$2) case var $?) {
        return $;
      }
      this.pos = mark;
      if (matchPattern(_regexp.$3) case var $?) {
        return $;
      }
      this.pos = mark;
      if (matchPattern(_regexp.$4) case var $?) {
        return $;
      }
    }
  };

  /// `fragment122`
  late final f4g = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$11) case null) {
        this.pos = mark;
        if (this.pos < this.buffer.length) {
          if (this.buffer[this.pos] case var $1) {
            this.pos++;
            return $1;
          }
        }
      }
    }
  };

  /// `fragment123`
  late final f4h = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$13) case null) {
        this.pos = mark;
        if (this.pos < this.buffer.length) {
          if (this.buffer[this.pos] case var $1) {
            this.pos++;
            return $1;
          }
        }
      }
    }
  };

  /// `fragment124`
  late final f4i = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$14) case null) {
        this.pos = mark;
        if (this.pos < this.buffer.length) {
          if (this.buffer[this.pos] case var $1) {
            this.pos++;
            return $1;
          }
        }
      }
    }
  };

  /// `fragment125`
  late final f4j = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$15) case null) {
        this.pos = mark;
        if (this.pos < this.buffer.length) {
          if (this.buffer[this.pos] case var $1) {
            this.pos++;
            return $1;
          }
        }
      }
    }
  };

  /// `fragment126`
  late final f4k = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$1) case _?) {
        if (this.pos < this.buffer.length) {
          if (this.buffer[this.pos] case var $1) {
            this.pos++;
            return $1;
          }
        }
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.matchPattern(_string.$18) case var $0?) {
          this.pos = mark;
          if (this.fw() case var $1?) {
            return ($0, $1);
          }
        }
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.matchPattern(_string.$11) case null) {
          this.pos = mark;
          if (this.pos < this.buffer.length) {
            if (this.buffer[this.pos] case var $1) {
              this.pos++;
              return $1;
            }
          }
        }
      }
    }
  };

  /// `fragment127`
  late final f4l = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$1) case _?) {
        if (this.pos < this.buffer.length) {
          if (this.buffer[this.pos] case var $1) {
            this.pos++;
            return $1;
          }
        }
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.matchPattern(_string.$18) case var $0?) {
          this.pos = mark;
          if (this.fw() case var $1?) {
            return ($0, $1);
          }
        }
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.matchPattern(_string.$13) case null) {
          this.pos = mark;
          if (this.pos < this.buffer.length) {
            if (this.buffer[this.pos] case var $1) {
              this.pos++;
              return $1;
            }
          }
        }
      }
    }
  };

  /// `fragment128`
  late final f4m = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$1) case _?) {
        if (this.pos < this.buffer.length) {
          if (this.buffer[this.pos] case var $1) {
            this.pos++;
            return $1;
          }
        }
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.matchPattern(_string.$18) case var $0?) {
          this.pos = mark;
          if (this.fw() case var $1?) {
            return ($0, $1);
          }
        }
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.matchPattern(_string.$14) case null) {
          this.pos = mark;
          if (this.pos < this.buffer.length) {
            if (this.buffer[this.pos] case var $1) {
              this.pos++;
              return $1;
            }
          }
        }
      }
    }
  };

  /// `fragment129`
  late final f4n = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$1) case _?) {
        if (this.pos < this.buffer.length) {
          if (this.buffer[this.pos] case var $1) {
            this.pos++;
            return $1;
          }
        }
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.matchPattern(_string.$18) case var $0?) {
          this.pos = mark;
          if (this.fw() case var $1?) {
            return ($0, $1);
          }
        }
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.matchPattern(_string.$15) case null) {
          this.pos = mark;
          if (this.pos < this.buffer.length) {
            if (this.buffer[this.pos] case var $1) {
              this.pos++;
              return $1;
            }
          }
        }
      }
    }
  };

  /// `fragment130`
  late final f4o = () {
    if (this.f8() case var _0?) {
      if ([_0] case (var $ && var _l1)) {
        for (;;) {
          if (this.pos case var mark) {
            if (this.fs() case _?) {
              if (this.f8() case var _0?) {
                _l1.add(_0);
                continue;
              }
            }
            this.pos = mark;
            break;
          }
        }
        return $.join(".");
      }
    }
  };

  /// `fragment131`
  late final f4p = () {
    if (this.matchPattern(_string.$58) case var $0?) {
      if (this.ft() case _) {
        return $0;
      }
    }
  };

  /// `fragment132`
  late final f4q = () {
    if (this.ft() case _) {
      if (this.f4p() case var $1?) {
        return $1;
      }
    }
  };

  /// `fragment133`
  late final f4r = () {
    if (this.matchPattern(_string.$59) case var $0?) {
      if (this.ft() case _) {
        return $0;
      }
    }
  };

  /// `fragment134`
  late final f4s = () {
    if (this.ft() case _) {
      if (this.f4r() case var $1?) {
        return $1;
      }
    }
  };

  /// `global::document`
  ParserGenerator? r0() {
    if (this.pos <= 0) {
      if (this.apply(this.r1) case var preamble) {
        if (this.apply(this.r2) case var _0?) {
          if ([_0] case (var statements && var _l1)) {
            for (;;) {
              if (this.pos case var mark) {
                if (this.ft() case _) {
                  if (this.apply(this.r2) case var _0?) {
                    _l1.add(_0);
                    continue;
                  }
                }
                this.pos = mark;
                break;
              }
            }
            if (this.ft() case _) {
              if (this.pos >= this.buffer.length) {
                return ParserGenerator.fromParsed(preamble: preamble, statements: statements);
              }
            }
          }
        }
      }
    }
  }

  /// `global::preamble`
  String? r1() {
    if (this.fk() case _?) {
      if (this.ft() case _) {
        if (this.apply(this.rf)! case var code) {
          if (this.ft() case _) {
            if (this.fj() case _?) {
              return code;
            }
          }
        }
      }
    }
  }

  /// `global::statement`
  Statement? r2() {
    if (this.pos case var mark) {
      if (this.apply(this.r3) case var $?) {
        return $;
      }
      this.pos = mark;
      if (this.apply(this.r4) case var $?) {
        return $;
      }
    }
  }

  /// `global::namespace`
  Statement? r3() {
    if (this.pos case var mark) {
      if (this.fc() case _?) {
        if (this.f8() case var name) {
          if (this.fk() case _?) {
            if (this.apply(this.r2) case var _0?) {
              if ([_0] case (var statements && var _l1)) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.ft() case _) {
                      if (this.apply(this.r2) case var _0?) {
                        _l1.add(_0);
                        continue;
                      }
                    }
                    this.pos = mark;
                    break;
                  }
                }
                if (this.fj() case _?) {
                  return NamespaceStatement(name, statements, tag: Tag.fragment);
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.fb() case _?) {
        if (this.f8() case var name) {
          if (this.fk() case _?) {
            if (this.apply(this.r2) case var _2?) {
              if ([_2] case (var statements && var _l3)) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.ft() case _) {
                      if (this.apply(this.r2) case var _2?) {
                        _l3.add(_2);
                        continue;
                      }
                    }
                    this.pos = mark;
                    break;
                  }
                }
                if (this.fj() case _?) {
                  return NamespaceStatement(name, statements, tag: Tag.rule);
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.fd() case _?) {
        if (this.f8() case var name) {
          if (this.fk() case _?) {
            if (this.apply(this.r2) case var _4?) {
              if ([_4] case (var statements && var _l5)) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.ft() case _) {
                      if (this.apply(this.r2) case var _4?) {
                        _l5.add(_4);
                        continue;
                      }
                    }
                    this.pos = mark;
                    break;
                  }
                }
                if (this.fj() case _?) {
                  return NamespaceStatement(name, statements, tag: Tag.inline);
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.f8() case var name) {
        if (this.fk() case _?) {
          if (this.apply(this.r2) case var _6?) {
            if ([_6] case (var statements && var _l7)) {
              for (;;) {
                if (this.pos case var mark) {
                  if (this.ft() case _) {
                    if (this.apply(this.r2) case var _6?) {
                      _l7.add(_6);
                      continue;
                    }
                  }
                  this.pos = mark;
                  break;
                }
              }
              if (this.fj() case _?) {
                return NamespaceStatement(name, statements, tag: null);
              }
            }
          }
        }
      }
    }
  }

  /// `global::declaration`
  Statement? r4() {
    if (this.pos case var mark) {
      if (this.fa() case var decorator) {
        if (this.fe() case _) {
          if (this.f3() case var name?) {
            if (this.f4() case var body?) {
              return DeclarationStatement(null, name, body, tag: decorator);
            }
          }
        }
      }
      this.pos = mark;
      if (this.fa() case var decorator) {
        if (this.f0() case var type?) {
          if (this.f3() case var name?) {
            if (this.f4() case var body?) {
              return DeclarationStatement(type, name, body, tag: decorator);
            }
          }
        }
      }
      this.pos = mark;
      if (this.fa() case var decorator) {
        if (this.fe() case _) {
          if (this.f3() case var name?) {
            if (this.f13() case _?) {
              if (this.f0() case var type?) {
                if (this.f4() case var body?) {
                  return DeclarationStatement(type, name, body, tag: decorator);
                }
              }
            }
          }
        }
      }
    }
  }

  /// `global::choice`
  Node? r5() {
    if (this.fr() case _) {
      if (this.apply(this.r6) case var _0?) {
        if ([_0] case (var options && var _l1)) {
          for (;;) {
            if (this.pos case var mark) {
              if (this.fr() case _?) {
                if (this.apply(this.r6) case var _0?) {
                  _l1.add(_0);
                  continue;
                }
              }
              this.pos = mark;
              break;
            }
          }
          return options.length == 1 ? options.single : ChoiceNode(options);
        }
      }
    }
  }

  /// `global::acted`
  Node? r6() {
    if (this.pos case var mark) {
      if (this.pos case var from) {
        if (this.apply(this.r7) case var sequence?) {
          if (this.f15() case _?) {
            if (this.ft() case _) {
              if (this.f6() case var raw?) {
                if (this.ft() case _) {
                  if (this.pos case var to) {
                    return InlineActionNode(
                        sequence,
                        raw.trimRight(),
                        areIndicesProvided: raw.contains(_regexps.from) && raw.contains(_regexps.to),
                      );
                  }
                }
              }
            }
          }
        }
      }

      this.pos = mark;
      if (this.pos case var from) {
        if (this.apply(this.r7) case var sequence?) {
          if (this.fk() case _?) {
            if (this.ft() case _) {
              if (this.apply(this.rf)! case var curly) {
                if (this.ft() case _) {
                  if (this.fj() case _?) {
                    if (this.pos case var to) {
                      return InlineActionNode(
                            sequence,
                            curly.trimRight(),
                            areIndicesProvided: curly.contains(_regexps.from) && curly.contains(_regexps.to),
                          );
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
        if (this.apply(this.r7) case var sequence?) {
          if (this.fm() case _?) {
            if (this.fl() case _?) {
              if (this.fk() case _?) {
                if (this.ft() case _) {
                  if (this.apply(this.rf)! case var curly) {
                    if (this.ft() case _) {
                      if (this.fj() case _?) {
                        if (this.pos case var to) {
                          return ActionNode(
                                sequence,
                                curly.trimRight(),
                                areIndicesProvided: curly.contains(_regexps.from) && curly.contains(_regexps.to),
                              );
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
      if (this.apply(this.r7) case var $?) {
        return $;
      }
    }
  }

  /// `global::sequence`
  Node? r7() {
    if (this.apply(this.r8) case var _0?) {
      if ([_0] case (var body && var _l1)) {
        for (;;) {
          if (this.pos case var mark) {
            if (this.ft() case _) {
              if (this.apply(this.r8) case var _0?) {
                _l1.add(_0);
                continue;
              }
            }
            this.pos = mark;
            break;
          }
        }
        if (this.f18() case var chosen) {
          return body.length == 1 ? body.single : SequenceNode(body, choose: chosen);
        }
      }
    }
  }

  /// `global::dropped`
  Node? r8() {
    if (this.pos case var mark) {
      if (this.apply(this.r8) case var captured?) {
        if (this.f1a() case _?) {
          if (this.apply(this.ra) case var dropped?) {
            return SequenceNode([captured, dropped], choose: 0);
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.ra) case var dropped?) {
        if (this.f1c() case _?) {
          if (this.apply(this.r8) case var captured?) {
            return SequenceNode([dropped, captured], choose: 1);
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.r9) case var $?) {
        return $;
      }
    }
  }

  /// `global::labeled`
  Node? r9() {
    if (this.pos case var mark) {
      if (this.f8() case var identifier?) {
        if (this.matchPattern(_string.$19) case _?) {
          if (this.ft() case _) {
            if (this.apply(this.ra) case var special?) {
              return NamedNode(identifier, special);
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$19) case _?) {
        if (this.f2() case var id?) {
          if (this.fn() case _?) {
            return switch ((id, id.split(ParserGenerator.separator))) {
                  (var ref, [..., var name]) => NamedNode(name, OptionalNode(ReferenceNode(ref))),
                  _ => null,
                };
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$19) case _?) {
        if (this.f2() case var id?) {
          if (this.fo() case _?) {
            return switch ((id, id.split(ParserGenerator.separator))) {
                  (var ref, [..., var name]) => NamedNode(name, StarNode(ReferenceNode(ref))),
                  _ => null,
                };
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$19) case _?) {
        if (this.f2() case var id?) {
          if (this.fp() case _?) {
            return switch ((id, id.split(ParserGenerator.separator))) {
                  (var ref, [..., var name]) => NamedNode(name, PlusNode(ReferenceNode(ref))),
                  _ => null,
                };
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$19) case _?) {
        if (this.f2() case var id?) {
          return switch ((id, id.split(ParserGenerator.separator))) {
                (var ref, [..., var name]) => NamedNode(name, ReferenceNode(ref)),
                _ => null,
              };
        }
      }
      this.pos = mark;
      if (this.apply(this.ra) case var $?) {
        return $;
      }
    }
  }

  /// `global::special`
  Node? ra() {
    if (this.pos case var mark) {
      if (this.apply(this.rd) case var sep?) {
        if (this.fi() case _?) {
          if (this.apply(this.rd) case var expr?) {
            if (this.fp() case _?) {
              return PlusSeparatedNode(sep, expr, isTrailingAllowed: false);
            }
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.rd) case var sep?) {
        if (this.fi() case _?) {
          if (this.apply(this.rd) case var expr?) {
            if (this.fo() case _?) {
              return StarSeparatedNode(sep, expr, isTrailingAllowed: false);
            }
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.rb) case var $?) {
        return $;
      }
    }
  }

  /// `global::postfix`
  Node? rb() {
    if (this.pos case var mark) {
      if (this.apply(this.rb) case var $0?) {
        if (this.fn() case var $1?) {
          if ($0 case var $) {
            return OptionalNode($);
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.rb) case var $0?) {
        if (this.fo() case var $1?) {
          if ($0 case var $) {
            return StarNode($);
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.rb) case var $0?) {
        if (this.fp() case var $1?) {
          if ($0 case var $) {
            return PlusNode($);
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.rc) case var $?) {
        return $;
      }
    }
  }

  /// `global::prefix`
  Node? rc() {
    if (this.pos case var mark) {
      if (this.f9() case var min?) {
        if (this.fi() case _?) {
          if (this.f9() case var max) {
            if (this.apply(this.re) case var body?) {
              return CountedNode(min, max, body);
            }
          }
        }
      }
      this.pos = mark;
      if (this.f9() case var number?) {
        if (this.apply(this.re) case var body?) {
          return CountedNode(number, number, body);
        }
      }
      this.pos = mark;
      if (this.f1e() case var $0?) {
        if (this.apply(this.rc) case var $1?) {
          if ($1 case var $) {
            return SequenceNode([NotPredicateNode($), const AnyCharacterNode()], choose: 1);
          }
        }
      }
      this.pos = mark;
      if (this.f1g() case var $0?) {
        if (this.apply(this.rc) case var $1?) {
          if ($1 case var $) {
            return AndPredicateNode($);
          }
        }
      }
      this.pos = mark;
      if (this.f1i() case var $0?) {
        if (this.apply(this.rc) case var $1?) {
          if ($1 case var $) {
            return NotPredicateNode($);
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.rd) case var $?) {
        return $;
      }
    }
  }

  /// `global::callLike`
  Node? rd() {
    if (this.pos case var mark) {
      if (this.pos case var from) {
        if (this.apply(this.rd) case var target?) {
          if (this.fs() case _?) {
            if (this.fg() case _?) {
              if (this.fm() case _?) {
                if (this.fl() case _?) {
                  if (this.pos case var to) {
                    return InlineActionNode(target, "this.buffer.substring(from, to)", areIndicesProvided: true);
                  }
                }
              }
            }
          }
        }
      }

      this.pos = mark;
      if (this.apply(this.rd) case var target?) {
        if (this.fs() case _?) {
          if (this.ff() case _?) {
            if (this.fm() case _?) {
              if (this.f9() case var min?) {
                if (this.fq() case _?) {
                  if (this.f9() case var max?) {
                    if (this.fl() case _?) {
                      return CountedNode(min, max, target);
                    }
                  }
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.rd) case var target?) {
        if (this.fs() case _?) {
          if (this.ff() case _?) {
            if (this.fm() case _?) {
              if (this.f9() case var number?) {
                if (this.fl() case _?) {
                  return CountedNode(number, number, target);
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.rd) case var target?) {
        if (this.fs() case _?) {
          if (this.ff() case _?) {
            if (this.ft() case _) {
              if (this.f9() case var number?) {
                if (this.ft() case _) {
                  return CountedNode(number, number, target);
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.rd) case var sep?) {
        if (this.fs() case _?) {
          if (this.fh() case _?) {
            if (this.fm() case _?) {
              if (this.apply(this.r5) case var body?) {
                if (this.fl() case _?) {
                  if (this.fp() case _?) {
                    if (this.fn() case _?) {
                      return PlusSeparatedNode(sep, body, isTrailingAllowed: true);
                    }
                  }
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.rd) case var sep?) {
        if (this.fs() case _?) {
          if (this.fh() case _?) {
            if (this.fm() case _?) {
              if (this.apply(this.r5) case var body?) {
                if (this.fl() case _?) {
                  if (this.fo() case _?) {
                    if (this.fn() case _?) {
                      return StarSeparatedNode(sep, body, isTrailingAllowed: true);
                    }
                  }
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.rd) case var sep?) {
        if (this.fs() case _?) {
          if (this.fh() case _?) {
            if (this.fm() case _?) {
              if (this.apply(this.r5) case var body?) {
                if (this.fl() case _?) {
                  if (this.fp() case _?) {
                    return PlusSeparatedNode(sep, body, isTrailingAllowed: false);
                  }
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.rd) case var sep?) {
        if (this.fs() case _?) {
          if (this.fh() case _?) {
            if (this.fm() case _?) {
              if (this.apply(this.r5) case var body?) {
                if (this.fl() case _?) {
                  if (this.fo() case _?) {
                    return StarSeparatedNode(sep, body, isTrailingAllowed: false);
                  }
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.rd) case var sep?) {
        if (this.fs() case _?) {
          if (this.fh() case _?) {
            if (this.fm() case _?) {
              if (this.apply(this.r5) case var body?) {
                if (this.fl() case _?) {
                  return PlusSeparatedNode(sep, body, isTrailingAllowed: false);
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.rd) case var sep?) {
        if (this.fs() case _?) {
          if (this.fh() case _?) {
            if (this.ft() case _) {
              if (this.apply(this.re) case var body?) {
                if (this.ft() case _) {
                  return PlusSeparatedNode(sep, body, isTrailingAllowed: false);
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.re) case var $?) {
        return $;
      }
    }
  }

  /// `global::atom`
  Node? re() {
    if (this.pos case var mark) {
      if (this.fm() case _?) {
        if (this.f1j() case var $1?) {
          return $1;
        }
      }
      this.pos = mark;
      if (this.ft() case var $0) {
        if (this.f1k() case var $1?) {
          return const StartOfInputNode();
        }
      }
      this.pos = mark;
      if (this.ft() case var $0) {
        if (this.f1l() case var $1?) {
          return const EndOfInputNode();
        }
      }
      this.pos = mark;
      if (this.fs() case var $?) {
        return const AnyCharacterNode();
      }
      this.pos = mark;
      if (this.ft() case var $0) {
        if (this.f1m() case var $1?) {
          return const EpsilonNode();
        }
      }
      this.pos = mark;
      if (this.ft() case var $0) {
        if (this.f1o() case var $1?) {
          return const StringLiteralNode(r"\");
        }
      }
      this.pos = mark;
      if (this.ft() case var $0) {
        if (this.f1q() case var $1?) {
          return SimpleRegExpEscapeNode.digit;
        }
      }
      this.pos = mark;
      if (this.ft() case var $0) {
        if (this.f1s() case var $1?) {
          return SimpleRegExpEscapeNode.word;
        }
      }
      this.pos = mark;
      if (this.ft() case var $0) {
        if (this.f1u() case var $1?) {
          return SimpleRegExpEscapeNode.whitespace;
        }
      }
      this.pos = mark;
      if (this.ft() case var $0) {
        if (this.f1w() case var $1?) {
          return SimpleRegExpEscapeNode.notDigit;
        }
      }
      this.pos = mark;
      if (this.ft() case var $0) {
        if (this.f1y() case var $1?) {
          return SimpleRegExpEscapeNode.notWord;
        }
      }
      this.pos = mark;
      if (this.ft() case var $0) {
        if (this.f20() case var $1?) {
          return SimpleRegExpEscapeNode.notWhitespace;
        }
      }
      this.pos = mark;
      if (this.ft() case var $0) {
        if (this.f22() case var $1?) {
          return SimpleRegExpEscapeNode.tab;
        }
      }
      this.pos = mark;
      if (this.ft() case var $0) {
        if (this.f24() case var $1?) {
          return SimpleRegExpEscapeNode.newline;
        }
      }
      this.pos = mark;
      if (this.ft() case var $0) {
        if (this.f26() case var $1?) {
          return SimpleRegExpEscapeNode.carriageReturn;
        }
      }
      this.pos = mark;
      if (this.ft() case var $0) {
        if (this.f28() case var $1?) {
          return SimpleRegExpEscapeNode.formFeed;
        }
      }
      this.pos = mark;
      if (this.ft() case var $0) {
        if (this.f2a() case var $1?) {
          return SimpleRegExpEscapeNode.verticalTab;
        }
      }
      this.pos = mark;
      if (this.ft() case _) {
        if (this.f2r() case var $1?) {
          return $1;
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$39) case var $0?) {
        if (this.f2u() case var $1?) {
          if ($1 case var $) {
            return RegExpNode($);
          }
        }
      }
      this.pos = mark;
      if (this.ft() case var $0) {
        if (this.f3c() case var $1?) {
          if ($1 case var $) {
            return StringLiteralNode($);
          }
        }
      }
      this.pos = mark;
      if (this.f3() case var $?) {
        return ReferenceNode($);
      }
    }
  }

  /// `global::code::curly`
  String rf() {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$3) case var $0?) {
        if (this.f3e() case var $1?) {
          if ($1 case var $) {
            return $.join();
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.rg)! case var $) {
        return $;
      }
    }
  }

  /// `global::code::curly::balanced`
  String rg() {
    if (this.pos case var mark) {
      if (this.f3g() case var _0) {
        if ([if (_0 case var _0?) _0] case (var code && var _l1)) {
          if (_l1.isNotEmpty) {
            for (;;) {
              if (this.pos case var mark) {
                if (this.f3g() case var _0?) {
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
          return code.join();
        }
      }
    }
  }

  /// `global::dart::literal::string`
  String? rh() {
    if (this.f3h() case var _0?) {
      if ([_0] case (var $ && var _l1)) {
        for (;;) {
          if (this.pos case var mark) {
            if (this.ft() case _) {
              if (this.f3h() case var _0?) {
                _l1.add(_0);
                continue;
              }
            }
            this.pos = mark;
            break;
          }
        }
        return $.join(" ");
      }
    }
  }

  /// `global::dart::literal::identifier`
  String? ri() {
    if (this.pos case var from) {
      if (this.f8() case var $?) {
        if (this.pos case var to) {
          return this.buffer.substring(from, to);
        }
      }
    }
  }

  /// `global::dart::literal::string::balanced`
  Object rj() {
    if (this.pos case var mark) {
      if (this.f3i() case var _0) {
        if ([if (_0 case var _0?) _0] case (var code && var _l1)) {
          if (_l1.isNotEmpty) {
            for (;;) {
              if (this.pos case var mark) {
                if (this.f3i() case var _0?) {
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
          return _l1;
        }
      }
    }
  }

  /// `global::dart::type::main`
  String? rk() {
    if (this.ft() case _) {
      if (this.f3j() case var $1?) {
        return $1;
      }
    }
  }

  /// `global::dart::type::nullable`
  String? rl() {
    if (this.apply(this.rm) case var nonNullable?) {
      if (this.fn() case var $1) {
        return $1 == null ? "$nonNullable" : "$nonNullable?";
      }
    }
  }

  /// `global::dart::type::nonNullable`
  String? rm() {
    if (this.pos case var mark) {
      if (this.fx() case var $?) {
        return $;
      }
      this.pos = mark;
      if (this.apply(this.rn) case var $?) {
        return $;
      }
      this.pos = mark;
      if (this.f8() case var _0?) {
        if ([_0] case (var $ && var _l1)) {
          for (;;) {
            if (this.pos case var mark) {
              if (this.fs() case _?) {
                if (this.f8() case var _0?) {
                  _l1.add(_0);
                  continue;
                }
              }
              this.pos = mark;
              break;
            }
          }
          return $.join(".");
        }
      }
    }
  }

  /// `global::dart::type::record`
  String? rn() {
    if (this.pos case var mark) {
      if (this.fm() case var $0?) {
        if (this.f3l() case var $1) {
          if (this.fl() case var $2?) {
            return "(" + ($1 == null ? "" : "{" + $1 + "}") + ")";
          }
        }
      }
      this.pos = mark;
      if (this.fm() case var $0?) {
        if (this.fz() case var $1?) {
          if (this.fq() case var $2?) {
            if (this.f3n() case var $3) {
              if (this.fl() case var $4?) {
                return "(" + $1 + ", " + ($3 == null ? "" : "{" + $3 + "}") + ")";
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.fm() case var $0?) {
        if (this.f11() case var $1?) {
          if (this.f3o() case var $2) {
            if (this.fl() case var $3?) {
              return "(" + $1 + ($2 == null ? "" : ", {" + $2 + "}") + ")";
            }
          }
        }
      }
    }
  }

  static final _regexp = (
    RegExp("\\d"),
    RegExp("\\s+"),
    RegExp("\\/{2}(?:(?!(?:(?:\\r?\\n)|(?:\$))).)*(?=(?:\\r?\\n)|(?:\$))"),
    RegExp("(?:\\/\\*(?:(?!\\*\\/).)*\\*\\/)"),
  );
  static final _trie = (
    Trie.from(["{","}"]),
  );
  static const _string = (
    "\\",
    "]",
    "`",
    "@rule",
    "@fragment",
    "@inline",
    "var",
    "range!",
    "flat!",
    "sep!",
    "\"\"\"",
    "r",
    "'''",
    "\"",
    "'",
    "}",
    "{",
    "\$",
    ":",
    "=>",
    "@",
    "<~",
    "~>",
    "~",
    "&",
    "!",
    "^",
    "ε",
    "d",
    "w",
    "s",
    "t",
    "n",
    "f",
    "v",
    " ",
    "-",
    "[",
    "/",
    "r\"\"\"",
    "r'''",
    "r\"",
    "r'",
    "::",
    ".",
    "..",
    "=",
    "<-",
    "->",
    ";",
    ")",
    "(",
    "?",
    "*",
    "+",
    ",",
    "|",
    "<",
    ">",
  );
  static const _range = (
    { (97, 122), (65, 90), (48, 57), (95, 95), (36, 36) },
    { (97, 122), (65, 90), (95, 95), (36, 36) },
  );
}
typedef _Union<A, B> = (A? a, B? b);
typedef _Key<K> = _Union<K, Symbol>;

extension<R extends Object> on _PegParser<R> {
  // ignore: unused_element
  String? matchTrie(Trie trie) {
    if (trie.matchLongest(buffer, pos) case (int start, int end)) {
      pos = end;

      return buffer.substring(start, end);
    }

    (failures[pos] ??= <String>{}).addAll(trie._keys(trie._innerMap).map((List<String> v) => v.join()));
    return null;
  }
}

class Trie {
  Trie() : _innerMap = HashMap<_Key<String>, Object>();
  factory Trie.from(Iterable<String> strings) => strings.fold(Trie(), (Trie t, String s) => t..add(s));
  const Trie.complete(this._innerMap);

  static final Symbol _safeGuard = Symbol(math.Random.secure().nextInt(32).toString());

  final HashMap<_Key<String>, Object> _innerMap;

  bool add(String value) {
    _set(value.split(""), true);

    return true;
  }

  Trie? derive(String key) => switch (_innerMap[(key, null)]) {
        HashMap<_Key<String>, Object> value => Trie.complete(value),
        _ => null,
      };

  Trie? deriveAll(String value) => value //
      .split("")
      .fold(this, (Trie? trie, String char) => trie?.derive(char));

  (int, int)? matchLongest(String input, [int start = 0]) {
    List<int> ends = <int>[];

    int index = start;
    Trie? derivation = this;
    for (int i = index; i < input.length; ++i) {
      derivation = derivation?.derive(input[i]);
      if (derivation == null) {
        break;
      }

      if (derivation._innerMap.containsKey((null, _safeGuard))) {
        ends.add(i);
      }
    }

    if (ends.isEmpty) {
      return null;
    }

    int max = ends.last + 1;

    return (index, max);
  }

  HashMap<_Key<String>, Object> _derived(List<String> keys) {
    HashMap<_Key<String>, Object> map = _innerMap;
    for (int i = 0; i < keys.length; ++i) {
      map = map.putIfAbsent((keys[i], null), HashMap<_Key<String>, Object>.new) as HashMap<_Key<String>, Object>;
    }

    return map;
  }

  bool _set(List<String> keys, bool value) => _derived(keys)[(null, _safeGuard)] = value;

  Iterable<List<String>> _keys(HashMap<_Key<String>, Object> map) sync* {
    if (map.containsKey((null, _safeGuard))) {
      yield <String>[];
    }

    for (var (String keys, _) in map.keys.whereType<(String, void)>()) {
      /// Since it's not the safeguard,
      ///  Get the derivative of the map.

      switch (map[(keys, null)]) {
        case HashMap<_Key<String>, Object> derivative:
          yield* _keys(derivative).map((List<String> rest) => <String>[keys, ...rest]);
        case null:
          yield <String>[keys];
      }
    }
  }
}
