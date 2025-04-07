// ignore_for_file: always_declare_return_types, always_put_control_body_on_new_line, always_specify_types, avoid_escaping_inner_quotes, avoid_redundant_argument_values, annotate_overrides, body_might_complete_normally_nullable, constant_pattern_never_matches_value_type, curly_braces_in_flow_control_structures, dead_code, directives_ordering, duplicate_ignore, inference_failure_on_function_return_type, constant_identifier_names, prefer_function_declarations_over_variables, prefer_interpolation_to_compose_strings, prefer_is_empty, no_leading_underscores_for_local_identifiers, non_constant_identifier_names, unnecessary_null_check_pattern, unnecessary_brace_in_string_interps, unnecessary_string_interpolations, unnecessary_this, unused_element, unused_import, prefer_double_quotes, unused_local_variable, unreachable_from_main, use_raw_strings, type_annotate_public_apis

// imports
// ignore_for_file: collection_methods_unrelated_type

import "dart:collection";
import "dart:math" as math;

import "package:parser_peg/src/generator.dart";
// PREAMBLE
import "package:parser_peg/src/node.dart";
import "package:parser_peg/src/statement.dart";

final _regexps = (from: RegExp(r"\bfrom\b"), to: RegExp(r"\bto\b"));

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
final class PegParserAst extends _PegParser<Object> {
  PegParserAst();

  @override
  get start => r0;

  /// `global::type`
  Object? f0() {
    if (this.pos case var mark) {
      if (this.ft() case _) {
        if (this.f2a() case var $1?) {
          if (this.ft() case _) {
            return $1;
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.rk) case var $?) {
        return $;
      }
    }
  }

  /// `global::namespaceReference`
  Object f1() {
    if (this.pos case var mark) {
      if (this.f2d() case var _0) {
        if ([if (_0 case var _0?) _0] case var _l1) {
          if (_l1.isNotEmpty) {
            for (;;) {
              if (this.pos case var mark) {
                if (this.f2d() case var _0?) {
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

  /// `global::namespacedIdentifier`
  Object? f2() {
    if (this.f1() case var $0) {
      if (this.f7() case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `global::name`
  Object? f3() {
    if (this.pos case var mark) {
      if (this.f1() case var $0) {
        if (this.f6() case var $1?) {
          return ($0, $1);
        }
      }
      this.pos = mark;
      if (this.f2() case var $?) {
        return $;
      }
    }
  }

  /// `global::body`
  Object? f4() {
    if (this.f2e() case var $0?) {
      if (this.apply(this.r5) case (var $1 && var choice)?) {
        if (this.f2f() case var $2?) {
          return ($0, $1, $2);
        }
      }
    }
  }

  /// `global::literal::range::atom`
  Object? f5() {
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
  Object? f6() {
    if (this.matchPattern(_string.$3) case _?) {
      if (this.pos case var mark) {
        if (this.f2g() case var _0) {
          if ([if (_0 case var _0?) _0] case (var $1 && var _l1)) {
            if (_l1.isNotEmpty) {
              for (;;) {
                if (this.pos case var mark) {
                  if (this.f2g() case var _0?) {
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
              return $1;
            }
          }
        }
      }
    }
  }

  /// `global::identifier`
  Object? f7() {
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
            return ($0, $1);
          }
        }
      }
    }
  }

  /// `global::number`
  Object? f8() {
    if (matchPattern(_regexp.$1) case var _0?) {
      if ([_0] case var _l1) {
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
        return _l1;
      }
    }
  }

  /// `global::kw::decorator`
  Object? f9() {
    if (this.pos case var mark) {
      if (this.fa() case var $?) {
        return $;
      }
      this.pos = mark;
      if (this.fb() case var $?) {
        return $;
      }
      this.pos = mark;
      if (this.fc() case var $?) {
        return $;
      }
    }
  }

  /// `global::kw::decorator::rule`
  Object? fa() {
    if (this.ft() case var $0) {
      if (this.matchPattern(_string.$4) case var $1?) {
        if (this.ft() case var $2) {
          return ($0, $1, $2);
        }
      }
    }
  }

  /// `global::kw::decorator::fragment`
  Object? fb() {
    if (this.ft() case var $0) {
      if (this.matchPattern(_string.$5) case var $1?) {
        if (this.ft() case var $2) {
          return ($0, $1, $2);
        }
      }
    }
  }

  /// `global::kw::decorator::inline`
  Object? fc() {
    if (this.ft() case var $0) {
      if (this.matchPattern(_string.$6) case var $1?) {
        if (this.ft() case var $2) {
          return ($0, $1, $2);
        }
      }
    }
  }

  /// `global::kw::var`
  Object? fd() {
    if (this.ft() case _) {
      if (this.matchPattern(_string.$7) case var $1?) {
        if (this.ft() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::mac::range`
  Object? fe() {
    if (this.ft() case _) {
      if (this.matchPattern(_string.$8) case var $1?) {
        if (this.ft() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::mac::flat`
  Object? ff() {
    if (this.ft() case _) {
      if (this.matchPattern(_string.$9) case var $1?) {
        if (this.ft() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::mac::sep`
  Object? fg() {
    if (this.ft() case _) {
      if (this.matchPattern(_string.$10) case var $1?) {
        if (this.ft() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::..`
  Object? fh() {
    if (this.ft() case _) {
      if (this.matchPattern(_string.$11) case var $1?) {
        if (this.ft() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::=>`
  Object? fi() {
    if (this.ft() case _) {
      if (this.matchPattern(_string.$12) case var $1?) {
        if (this.ft() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::}`
  Object? fj() {
    if (this.ft() case _) {
      if (this.matchPattern(_string.$13) case var $1?) {
        if (this.ft() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::{`
  Object? fk() {
    if (this.ft() case _) {
      if (this.matchPattern(_string.$14) case var $1?) {
        if (this.ft() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::)`
  Object? fl() {
    if (this.ft() case _) {
      if (this.matchPattern(_string.$15) case var $1?) {
        if (this.ft() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::(`
  Object? fm() {
    if (this.ft() case _) {
      if (this.matchPattern(_string.$16) case var $1?) {
        if (this.ft() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::?`
  Object? fn() {
    if (this.ft() case _) {
      if (this.matchPattern(_string.$17) case var $1?) {
        if (this.ft() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::*`
  Object? fo() {
    if (this.ft() case _) {
      if (this.matchPattern(_string.$18) case var $1?) {
        if (this.ft() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::+`
  Object? fp() {
    if (this.ft() case _) {
      if (this.matchPattern(_string.$19) case var $1?) {
        if (this.ft() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::,`
  Object? fq() {
    if (this.ft() case _) {
      if (this.matchPattern(_string.$20) case var $1?) {
        if (this.ft() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::|`
  Object? fr() {
    if (this.ft() case _) {
      if (this.matchPattern(_string.$21) case var $1?) {
        if (this.ft() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::.`
  Object? fs() {
    if (this.ft() case _) {
      if (this.matchPattern(_string.$22) case var $1?) {
        if (this.ft() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::_`
  Object ft() {
    if (this.pos case var mark) {
      if (this.f2h() case var _0) {
        if ([if (_0 case var _0?) _0] case var _l1) {
          if (_l1.isNotEmpty) {
            for (;;) {
              if (this.pos case var mark) {
                if (this.f2h() case var _0?) {
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

  /// `ROOT`
  Object? fu() {
    if (this.apply(this.r0) case var $?) {
      return $;
    }
  }

  /// `global::dart::literal::string::body`
  Object? fv() {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$24) case var $0?) {
        if (this.matchPattern(_string.$23) case var $1?) {
          if (this.pos case var mark) {
            if (this.f2i() case var _0) {
              if ([if (_0 case var _0?) _0] case (var $2 && var _l1)) {
                if (_l1.isNotEmpty) {
                  for (;;) {
                    if (this.pos case var mark) {
                      if (this.f2i() case var _0?) {
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
                if (this.matchPattern(_string.$23) case var $3?) {
                  return ($0, $1, $2, $3);
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$24) case var $0?) {
        if (this.matchPattern(_string.$25) case var $1?) {
          if (this.pos case var mark) {
            if (this.f2j() case var _2) {
              if ([if (_2 case var _2?) _2] case (var $2 && var _l3)) {
                if (_l3.isNotEmpty) {
                  for (;;) {
                    if (this.pos case var mark) {
                      if (this.f2j() case var _2?) {
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
                if (this.matchPattern(_string.$25) case var $3?) {
                  return ($0, $1, $2, $3);
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$24) case var $0?) {
        if (this.matchPattern(_string.$26) case var $1?) {
          if (this.pos case var mark) {
            if (this.f2k() case var _4) {
              if ([if (_4 case var _4?) _4] case (var $2 && var _l5)) {
                if (_l5.isNotEmpty) {
                  for (;;) {
                    if (this.pos case var mark) {
                      if (this.f2k() case var _4?) {
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
                if (this.matchPattern(_string.$26) case var $3?) {
                  return ($0, $1, $2, $3);
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$24) case var $0?) {
        if (this.matchPattern(_string.$27) case var $1?) {
          if (this.pos case var mark) {
            if (this.f2l() case var _6) {
              if ([if (_6 case var _6?) _6] case (var $2 && var _l7)) {
                if (_l7.isNotEmpty) {
                  for (;;) {
                    if (this.pos case var mark) {
                      if (this.f2l() case var _6?) {
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
                if (this.matchPattern(_string.$27) case var $3?) {
                  return ($0, $1, $2, $3);
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$23) case var $0?) {
        if (this.pos case var mark) {
          if (this.f2m() case var _8) {
            if ([if (_8 case var _8?) _8] case (var $1 && var _l9)) {
              if (_l9.isNotEmpty) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.f2m() case var _8?) {
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
              if (this.matchPattern(_string.$23) case var $2?) {
                return ($0, $1, $2);
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$25) case var $0?) {
        if (this.pos case var mark) {
          if (this.f2n() case var _10) {
            if ([if (_10 case var _10?) _10] case (var $1 && var _l11)) {
              if (_l11.isNotEmpty) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.f2n() case var _10?) {
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
              if (this.matchPattern(_string.$25) case var $2?) {
                return ($0, $1, $2);
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$26) case var $0?) {
        if (this.pos case var mark) {
          if (this.f2o() case var _12) {
            if ([if (_12 case var _12?) _12] case (var $1 && var _l13)) {
              if (_l13.isNotEmpty) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.f2o() case var _12?) {
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
              if (this.matchPattern(_string.$26) case var $2?) {
                return ($0, $1, $2);
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$27) case var $0?) {
        if (this.pos case var mark) {
          if (this.f2p() case var _14) {
            if ([if (_14 case var _14?) _14] case (var $1 && var _l15)) {
              if (_l15.isNotEmpty) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.f2p() case var _14?) {
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
              if (this.matchPattern(_string.$27) case var $2?) {
                return ($0, $1, $2);
              }
            }
          }
        }
      }
    }
  }

  /// `global::dart::literal::string::interpolation`
  Object? fw() {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$28) case var $0?) {
        if (this.matchPattern(_string.$14) case var $1?) {
          if (this.apply(this.rj)! case var $2) {
            if (this.matchPattern(_string.$13) case var $3?) {
              return ($0, $1, $2, $3);
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$28) case var $0?) {
        if (this.apply(this.ri) case var $1?) {
          return ($0, $1);
        }
      }
    }
  }

  /// `fragment0`
  Object? fx() {
    if (this.ft() case _) {
      if (this.matchPattern(_string.$29) case var $1?) {
        if (this.ft() case _) {
          return $1;
        }
      }
    }
  }

  /// `fragment1`
  Object? fy() {
    if (this.ft() case _) {
      if (this.matchPattern(_string.$30) case var $1?) {
        if (this.ft() case _) {
          return $1;
        }
      }
    }
  }

  /// `fragment2`
  Object? fz() {
    if (this.fy() case _?) {
      if (this.f8() case var $1?) {
        return $1;
      }
    }
  }

  /// `fragment3`
  Object? f10() {
    if (this.ft() case _) {
      if (this.matchPattern(_string.$31) case var $1?) {
        if (this.ft() case _) {
          return $1;
        }
      }
    }
  }

  /// `fragment4`
  Object? f11() {
    if (this.ft() case _) {
      if (this.matchPattern(_string.$32) case var $1?) {
        if (this.ft() case _) {
          return $1;
        }
      }
    }
  }

  /// `fragment5`
  Object? f12() {
    if (this.ft() case _) {
      if (this.matchPattern(_string.$33) case var $1?) {
        if (this.ft() case _) {
          return $1;
        }
      }
    }
  }

  /// `fragment6`
  Object? f13() {
    if (this.ft() case _) {
      if (this.matchPattern(_string.$34) case var $1?) {
        if (this.ft() case _) {
          return $1;
        }
      }
    }
  }

  /// `fragment7`
  Object? f14() {
    if (this.ft() case _) {
      if (this.matchPattern(_string.$35) case var $1?) {
        if (this.ft() case _) {
          return $1;
        }
      }
    }
  }

  /// `fragment8`
  Object? f15() {
    if (this.matchPattern(_string.$1) case var $0?) {
      if (this.matchPattern(_string.$1) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `fragment9`
  Object? f16() {
    if (this.matchPattern(_string.$1) case var $0?) {
      if (this.matchPattern(_string.$36) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `fragment10`
  Object? f17() {
    if (this.matchPattern(_string.$1) case var $0?) {
      if (this.matchPattern(_string.$37) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `fragment11`
  Object? f18() {
    if (this.matchPattern(_string.$1) case var $0?) {
      if (this.matchPattern(_string.$38) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `fragment12`
  Object? f19() {
    if (this.matchPattern(_string.$1) case var $0?) {
      if (this.matchPattern(_string.$36) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `fragment13`
  Object? f1a() {
    if (this.matchPattern(_string.$1) case var $0?) {
      if (this.matchPattern(_string.$37) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `fragment14`
  Object? f1b() {
    if (this.matchPattern(_string.$1) case var $0?) {
      if (this.matchPattern(_string.$38) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `fragment15`
  Object? f1c() {
    if (this.matchPattern(_string.$1) case var $0?) {
      if (this.matchPattern(_string.$39) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `fragment16`
  Object? f1d() {
    if (this.matchPattern(_string.$1) case var $0?) {
      if (this.matchPattern(_string.$40) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `fragment17`
  Object? f1e() {
    if (this.matchPattern(_string.$1) case var $0?) {
      if (this.matchPattern(_string.$24) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `fragment18`
  Object? f1f() {
    if (this.matchPattern(_string.$1) case var $0?) {
      if (this.matchPattern(_string.$41) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `fragment19`
  Object? f1g() {
    if (this.matchPattern(_string.$1) case var $0?) {
      if (this.matchPattern(_string.$42) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `fragment20`
  Object? f1h() {
    if (this.matchPattern(_string.$1) case var $0?) {
      if (this.matchPattern(_string.$36) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `fragment21`
  Object? f1i() {
    if (this.matchPattern(_string.$1) case var $0?) {
      if (this.matchPattern(_string.$37) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `fragment22`
  Object? f1j() {
    if (this.matchPattern(_string.$1) case var $0?) {
      if (this.matchPattern(_string.$38) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `fragment23`
  Object? f1k() {
    if (this.matchPattern(_string.$1) case var $0?) {
      if (this.matchPattern(_string.$40) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `fragment24`
  Object? f1l() {
    if (this.matchPattern(_string.$1) case var $0?) {
      if (this.matchPattern(_string.$24) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `fragment25`
  Object? f1m() {
    if (this.matchPattern(_string.$1) case var $0?) {
      if (this.matchPattern(_string.$39) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `fragment26`
  Object? f1n() {
    if (this.matchPattern(_string.$1) case var $0?) {
      if (this.matchPattern(_string.$1) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `fragment27`
  Object? f1o() {
    if (this.pos case var mark) {
      if (this.pos case var mark) {
        if (this.matchPattern(_string.$43) case var $?) {
          return $;
        }
        this.pos = mark;
        if (this.ft() case _) {
          if (this.f1h() case var $1?) {
            if (this.ft() case _) {
              return $1;
            }
          }
        }
        this.pos = mark;
        if (this.ft() case _) {
          if (this.f1i() case var $1?) {
            if (this.ft() case _) {
              return $1;
            }
          }
        }
        this.pos = mark;
        if (this.ft() case _) {
          if (this.f1j() case var $1?) {
            if (this.ft() case _) {
              return $1;
            }
          }
        }
        this.pos = mark;
        if (this.ft() case _) {
          if (this.f1k() case var $1?) {
            if (this.ft() case _) {
              return $1;
            }
          }
        }
        this.pos = mark;
        if (this.ft() case _) {
          if (this.f1l() case var $1?) {
            if (this.ft() case _) {
              return $1;
            }
          }
        }
        this.pos = mark;
        if (this.ft() case _) {
          if (this.f1m() case var $1?) {
            if (this.ft() case _) {
              return $1;
            }
          }
        }
        this.pos = mark;
        if (this.ft() case _) {
          if (this.f1n() case var $1?) {
            if (this.ft() case _) {
              return $1;
            }
          }
        }
      }

      this.pos = mark;
      if (this.f5() case (var $0 && var l)?) {
        if (this.matchPattern(_string.$44) case var $1?) {
          if (this.f5() case (var $2 && var r)?) {
            return ($0, $1, $2);
          }
        }
      }
      this.pos = mark;
      if (this.f5() case var $?) {
        return $;
      }
    }
  }

  /// `fragment28`
  Object? f1p() {
    if (this.ft() case var $0) {
      if (this.matchPattern(_string.$45) case var $1?) {
        if (this.f1o() case var _0?) {
          if ([_0] case (var $2 && var elements && var _l1)) {
            for (;;) {
              if (this.pos case var mark) {
                if (this.ft() case _) {
                  if (this.f1o() case var _0?) {
                    _l1.add(_0);
                    continue;
                  }
                }
                this.pos = mark;
                break;
              }
            }
            if (this.matchPattern(_string.$2) case var $3?) {
              if (this.ft() case var $4) {
                return ($0, $1, $2, $3, $4);
              }
            }
          }
        }
      }
    }
  }

  /// `fragment29`
  Object? f1q() {
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
        if (this.matchPattern(_string.$46) case null) {
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

  /// `fragment30`
  Object? f1r() {
    if (this.f1q() case var _0?) {
      if ([_0] case var _l1) {
        for (;;) {
          if (this.pos case var mark) {
            if (this.f1q() case var _0?) {
              _l1.add(_0);
              continue;
            }
            this.pos = mark;
            break;
          }
        }
        return _l1;
      }
    }
  }

  /// `fragment31`
  Object? f1s() {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$23) case null) {
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

  /// `fragment32`
  Object? f1t() {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$25) case null) {
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

  /// `fragment33`
  Object? f1u() {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$26) case null) {
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

  /// `fragment34`
  Object? f1v() {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$27) case null) {
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

  /// `fragment35`
  Object? f1w() {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$1) case var $0?) {
        if (this.pos < this.buffer.length) {
          if (this.buffer[this.pos] case var $1) {
            this.pos++;
            return ($0, $1);
          }
        }
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.matchPattern(_string.$23) case null) {
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

  /// `fragment36`
  Object? f1x() {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$1) case var $0?) {
        if (this.pos < this.buffer.length) {
          if (this.buffer[this.pos] case var $1) {
            this.pos++;
            return ($0, $1);
          }
        }
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.matchPattern(_string.$25) case null) {
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

  /// `fragment37`
  Object? f1y() {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$1) case var $0?) {
        if (this.pos < this.buffer.length) {
          if (this.buffer[this.pos] case var $1) {
            this.pos++;
            return ($0, $1);
          }
        }
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.matchPattern(_string.$26) case null) {
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

  /// `fragment38`
  Object? f1z() {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$1) case var $0?) {
        if (this.pos < this.buffer.length) {
          if (this.buffer[this.pos] case var $1) {
            this.pos++;
            return ($0, $1);
          }
        }
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.matchPattern(_string.$27) case null) {
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

  /// `fragment39`
  Object? f20() {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$47) case _?) {
        if (this.pos case var mark) {
          if (this.f1s() case var _0) {
            if ([if (_0 case var _0?) _0] case (var $1 && var _l1)) {
              if (_l1.isNotEmpty) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.f1s() case var _0?) {
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
              if (this.matchPattern(_string.$23) case _?) {
                return $1;
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$48) case _?) {
        if (this.pos case var mark) {
          if (this.f1t() case var _2) {
            if ([if (_2 case var _2?) _2] case (var $1 && var _l3)) {
              if (_l3.isNotEmpty) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.f1t() case var _2?) {
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
              if (this.matchPattern(_string.$25) case _?) {
                return $1;
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$49) case _?) {
        if (this.pos case var mark) {
          if (this.f1u() case var _4) {
            if ([if (_4 case var _4?) _4] case (var $1 && var _l5)) {
              if (_l5.isNotEmpty) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.f1u() case var _4?) {
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
              if (this.matchPattern(_string.$26) case _?) {
                return $1;
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$50) case _?) {
        if (this.pos case var mark) {
          if (this.f1v() case var _6) {
            if ([if (_6 case var _6?) _6] case (var $1 && var _l7)) {
              if (_l7.isNotEmpty) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.f1v() case var _6?) {
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
              if (this.matchPattern(_string.$27) case _?) {
                return $1;
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$23) case _?) {
        if (this.pos case var mark) {
          if (this.f1w() case var _8) {
            if ([if (_8 case var _8?) _8] case (var $1 && var _l9)) {
              if (_l9.isNotEmpty) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.f1w() case var _8?) {
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
              if (this.matchPattern(_string.$23) case _?) {
                return $1;
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$25) case _?) {
        if (this.pos case var mark) {
          if (this.f1x() case var _10) {
            if ([if (_10 case var _10?) _10] case (var $1 && var _l11)) {
              if (_l11.isNotEmpty) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.f1x() case var _10?) {
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
              if (this.matchPattern(_string.$25) case _?) {
                return $1;
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$26) case _?) {
        if (this.pos case var mark) {
          if (this.f1y() case var _12) {
            if ([if (_12 case var _12?) _12] case (var $1 && var _l13)) {
              if (_l13.isNotEmpty) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.f1y() case var _12?) {
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
              if (this.matchPattern(_string.$26) case _?) {
                return $1;
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$27) case _?) {
        if (this.pos case var mark) {
          if (this.f1z() case var _14) {
            if ([if (_14 case var _14?) _14] case (var $1 && var _l15)) {
              if (_l15.isNotEmpty) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.f1z() case var _14?) {
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
              if (this.matchPattern(_string.$27) case _?) {
                return $1;
              }
            }
          }
        }
      }
    }
  }

  /// `fragment40`
  Object? f21() {
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
  }

  /// `fragment41`
  Object? f22() {
    if (this.pos case var mark) {
      if (this.apply(this.rh) case var $?) {
        return $;
      }
      this.pos = mark;
      if (this.matchPattern(_string.$14) case _?) {
        if (this.apply(this.rg)! case var $1) {
          if (this.matchPattern(_string.$13) case _?) {
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
  }

  /// `fragment42`
  Object? f23() {
    if (this.fv() case var $?) {
      return $;
    }
  }

  /// `fragment43`
  Object? f24() {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$14) case _?) {
        if (this.apply(this.rj)! case var $1) {
          if (this.matchPattern(_string.$13) case _?) {
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
  }

  /// `fragment44`
  Object? f25() {
    if (this.ft() case _) {
      if (this.matchPattern(_string.$51) case var $1?) {
        if (this.ft() case _) {
          return $1;
        }
      }
    }
  }

  /// `fragment45`
  Object? f26() {
    if (this.ft() case _) {
      if (this.matchPattern(_string.$52) case var $1?) {
        if (this.ft() case _) {
          return $1;
        }
      }
    }
  }

  /// `fragment46`
  Object? f27() {
    if (this.ft() case _) {
      if (this.matchPattern(_string.$45) case var $1?) {
        if (this.ft() case _) {
          return $1;
        }
      }
    }
  }

  /// `fragment47`
  Object? f28() {
    if (this.ft() case _) {
      if (this.matchPattern(_string.$2) case var $1?) {
        if (this.ft() case _) {
          return $1;
        }
      }
    }
  }

  /// `fragment48`
  Object? f29() {
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
  }

  /// `fragment49`
  Object? f2a() {
    if (this.matchPattern(_string.$3) case _?) {
      if (this.pos case var mark) {
        if (this.f29() case var _0) {
          if ([if (_0 case var _0?) _0] case (var $1 && var _l1)) {
            if (_l1.isNotEmpty) {
              for (;;) {
                if (this.pos case var mark) {
                  if (this.f29() case var _0?) {
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
              return $1;
            }
          }
        }
      }
    }
  }

  /// `fragment50`
  Object? f2b() {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$53) case var $?) {
        return $;
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.matchPattern(_string.$11) case (var $0 && null)) {
          this.pos = mark;
          if (this.matchPattern(_string.$22) case var $1?) {
            return ($0, $1);
          }
        }
      }
    }
  }

  /// `fragment51`
  Object? f2c() {
    if (this.pos case var mark) {
      if (this.fe() case var $?) {
        return $;
      }
      this.pos = mark;
      if (this.ff() case var $?) {
        return $;
      }
      this.pos = mark;
      if (this.fg() case var $?) {
        return $;
      }
    }
  }

  /// `fragment52`
  Object? f2d() {
    if (this.f7() case var $0?) {
      if (this.f2b() case _?) {
        if (this.pos case var mark) {
          if (this.f2c() case null) {
            this.pos = mark;
            return $0;
          }
        }
      }
    }
  }

  /// `fragment53`
  Object? f2e() {
    if (this.pos case var mark) {
      if (this.ft() case _) {
        if (this.matchPattern(_string.$54) case var $1?) {
          if (this.ft() case _) {
            return $1;
          }
        }
      }
      this.pos = mark;
      if (this.ft() case _) {
        if (this.matchPattern(_string.$55) case var $1?) {
          if (this.ft() case _) {
            return $1;
          }
        }
      }
      this.pos = mark;
      if (this.ft() case _) {
        if (this.matchPattern(_string.$56) case var $1?) {
          if (this.ft() case _) {
            return $1;
          }
        }
      }
    }
  }

  /// `fragment54`
  Object? f2f() {
    if (this.ft() case _) {
      if (this.matchPattern(_string.$57) case var $1?) {
        if (this.ft() case _) {
          return $1;
        }
      }
    }
  }

  /// `fragment55`
  Object? f2g() {
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
  }

  /// `fragment56`
  Object? f2h() {
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
  }

  /// `fragment57`
  Object? f2i() {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$23) case null) {
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

  /// `fragment58`
  Object? f2j() {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$25) case null) {
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

  /// `fragment59`
  Object? f2k() {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$26) case null) {
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

  /// `fragment60`
  Object? f2l() {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$27) case null) {
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

  /// `fragment61`
  Object? f2m() {
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
        if (this.matchPattern(_string.$28) case var $0?) {
          this.pos = mark;
          if (this.fw() case var $1?) {
            return ($0, $1);
          }
        }
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.matchPattern(_string.$23) case null) {
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

  /// `fragment62`
  Object? f2n() {
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
        if (this.matchPattern(_string.$28) case var $0?) {
          this.pos = mark;
          if (this.fw() case var $1?) {
            return ($0, $1);
          }
        }
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.matchPattern(_string.$25) case null) {
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

  /// `fragment63`
  Object? f2o() {
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
        if (this.matchPattern(_string.$28) case var $0?) {
          this.pos = mark;
          if (this.fw() case var $1?) {
            return ($0, $1);
          }
        }
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.matchPattern(_string.$26) case null) {
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

  /// `fragment64`
  Object? f2p() {
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
        if (this.matchPattern(_string.$28) case var $0?) {
          this.pos = mark;
          if (this.fw() case var $1?) {
            return ($0, $1);
          }
        }
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.matchPattern(_string.$27) case null) {
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

  /// `global::document`
  Object? r0() {
    if (this.pos case var $0 when this.pos <= 0) {
      if (this.apply(this.r1) case (var $1 && var preamble)) {
        if (this.apply(this.r2) case var _0?) {
          if ([_0] case (var $2 && var statements && var _l1)) {
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
            if (this.ft() case var $3) {
              if (this.pos case var $4 when this.pos >= this.buffer.length) {
                return ($0, $1, $2, $3, $4);
              }
            }
          }
        }
      }
    }
  }

  /// `global::preamble`
  Object? r1() {
    if (this.fk() case var $0?) {
      if (this.ft() case var $1) {
        if (this.apply(this.rf)! case (var $2 && var code)) {
          if (this.ft() case var $3) {
            if (this.fj() case var $4?) {
              return ($0, $1, $2, $3, $4);
            }
          }
        }
      }
    }
  }

  /// `global::statement`
  Object? r2() {
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
  Object? r3() {
    if (this.pos case var mark) {
      if (this.fb() case var $0?) {
        if (this.f7() case (var $1 && var name)) {
          if (this.fk() case var $2?) {
            if (this.apply(this.r2) case var _0?) {
              if ([_0] case (var $3 && var statements && var _l1)) {
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
                if (this.fj() case var $4?) {
                  return ($0, $1, $2, $3, $4);
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.fa() case var $0?) {
        if (this.f7() case (var $1 && var name)) {
          if (this.fk() case var $2?) {
            if (this.apply(this.r2) case var _2?) {
              if ([_2] case (var $3 && var statements && var _l3)) {
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
                if (this.fj() case var $4?) {
                  return ($0, $1, $2, $3, $4);
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.fc() case var $0?) {
        if (this.f7() case (var $1 && var name)) {
          if (this.fk() case var $2?) {
            if (this.apply(this.r2) case var _4?) {
              if ([_4] case (var $3 && var statements && var _l5)) {
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
                if (this.fj() case var $4?) {
                  return ($0, $1, $2, $3, $4);
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.f7() case (var $0 && var name)) {
        if (this.fk() case var $1?) {
          if (this.apply(this.r2) case var _6?) {
            if ([_6] case (var $2 && var statements && var _l7)) {
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
              if (this.fj() case var $3?) {
                return ($0, $1, $2, $3);
              }
            }
          }
        }
      }
    }
  }

  /// `global::declaration`
  Object? r4() {
    if (this.pos case var mark) {
      if (this.f9() case (var $0 && var decorator)) {
        if (this.fd() case var $1) {
          if (this.f3() case (var $2 && var name)?) {
            if (this.f4() case (var $3 && var body)?) {
              return ($0, $1, $2, $3);
            }
          }
        }
      }
      this.pos = mark;
      if (this.f9() case (var $0 && var decorator)) {
        if (this.f0() case (var $1 && var type)?) {
          if (this.f3() case (var $2 && var name)?) {
            if (this.f4() case (var $3 && var body)?) {
              return ($0, $1, $2, $3);
            }
          }
        }
      }
      this.pos = mark;
      if (this.f9() case (var $0 && var decorator)) {
        if (this.fd() case var $1) {
          if (this.f3() case (var $2 && var name)?) {
            if (this.fx() case var $3?) {
              if (this.f0() case (var $4 && var type)?) {
                if (this.f4() case (var $5 && var body)?) {
                  return ($0, $1, $2, $3, $4, $5);
                }
              }
            }
          }
        }
      }
    }
  }

  /// `global::choice`
  Object? r5() {
    if (this.fr() case var $0) {
      if (this.apply(this.r6) case var _0?) {
        if ([_0] case (var $1 && var options && var _l1)) {
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
          return ($0, $1);
        }
      }
    }
  }

  /// `global::acted`
  Object? r6() {
    if (this.pos case var mark) {
      if (this.apply(this.r7) case (var $0 && var sequence)?) {
        if (this.fi() case var $1?) {
          if (this.ft() case var $2) {
            if (this.f6() case (var $3 && var raw)?) {
              if (this.ft() case var $4) {
                return ($0, $1, $2, $3, $4);
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.r7) case (var $0 && var sequence)?) {
        if (this.fk() case var $1?) {
          if (this.ft() case var $2) {
            if (this.apply(this.rf)! case (var $3 && var curly)) {
              if (this.ft() case var $4) {
                if (this.fj() case var $5?) {
                  return ($0, $1, $2, $3, $4, $5);
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.r7) case (var $0 && var sequence)?) {
        if (this.fm() case var $1?) {
          if (this.fl() case var $2?) {
            if (this.fk() case var $3?) {
              if (this.ft() case var $4) {
                if (this.apply(this.rf)! case (var $5 && var curly)) {
                  if (this.ft() case var $6) {
                    if (this.fj() case var $7?) {
                      return ($0, $1, $2, $3, $4, $5, $6, $7);
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
  Object? r7() {
    if (this.apply(this.r8) case var _0?) {
      if ([_0] case (var $0 && var body && var _l1)) {
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
        if (this.fz() case (var $1 && var chosen)) {
          return ($0, $1);
        }
      }
    }
  }

  /// `global::dropped`
  Object? r8() {
    if (this.pos case var mark) {
      if (this.apply(this.r8) case (var $0 && var captured)?) {
        if (this.f10() case var $1?) {
          if (this.apply(this.ra) case (var $2 && var dropped)?) {
            return ($0, $1, $2);
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.ra) case (var $0 && var dropped)?) {
        if (this.f11() case var $1?) {
          if (this.apply(this.r8) case (var $2 && var captured)?) {
            return ($0, $1, $2);
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
  Object? r9() {
    if (this.pos case var mark) {
      if (this.f7() case (var $0 && var identifier)?) {
        if (this.matchPattern(_string.$29) case var $1?) {
          if (this.ft() case var $2) {
            if (this.apply(this.ra) case (var $3 && var special)?) {
              return ($0, $1, $2, $3);
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$29) case var $0?) {
        if (this.f2() case (var $1 && var id)?) {
          if (this.fn() case var $2?) {
            return ($0, $1, $2);
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$29) case var $0?) {
        if (this.f2() case (var $1 && var id)?) {
          if (this.fo() case var $2?) {
            return ($0, $1, $2);
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$29) case var $0?) {
        if (this.f2() case (var $1 && var id)?) {
          if (this.fp() case var $2?) {
            return ($0, $1, $2);
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$29) case var $0?) {
        if (this.f2() case (var $1 && var id)?) {
          return ($0, $1);
        }
      }
      this.pos = mark;
      if (this.apply(this.ra) case var $?) {
        return $;
      }
    }
  }

  /// `global::special`
  Object? ra() {
    if (this.pos case var mark) {
      if (this.apply(this.rd) case (var $0 && var sep)?) {
        if (this.fh() case var $1?) {
          if (this.apply(this.rd) case (var $2 && var expr)?) {
            if (this.fp() case var $3?) {
              return ($0, $1, $2, $3);
            }
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.rd) case (var $0 && var sep)?) {
        if (this.fh() case var $1?) {
          if (this.apply(this.rd) case (var $2 && var expr)?) {
            if (this.fo() case var $3?) {
              return ($0, $1, $2, $3);
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
  Object? rb() {
    if (this.pos case var mark) {
      if (this.apply(this.rb) case var $0?) {
        if (this.fn() case _?) {
          return $0;
        }
      }
      this.pos = mark;
      if (this.apply(this.rb) case var $0?) {
        if (this.fo() case _?) {
          return $0;
        }
      }
      this.pos = mark;
      if (this.apply(this.rb) case var $0?) {
        if (this.fp() case _?) {
          return $0;
        }
      }
      this.pos = mark;
      if (this.apply(this.rc) case var $?) {
        return $;
      }
    }
  }

  /// `global::prefix`
  Object? rc() {
    if (this.pos case var mark) {
      if (this.f8() case (var $0 && var min)?) {
        if (this.fh() case var $1?) {
          if (this.f8() case (var $2 && var max)) {
            if (this.apply(this.re) case (var $3 && var body)?) {
              return ($0, $1, $2, $3);
            }
          }
        }
      }
      this.pos = mark;
      if (this.f8() case (var $0 && var number)?) {
        if (this.apply(this.re) case (var $1 && var body)?) {
          return ($0, $1);
        }
      }
      this.pos = mark;
      if (this.f12() case _?) {
        if (this.apply(this.rc) case var $1?) {
          return $1;
        }
      }
      this.pos = mark;
      if (this.f13() case _?) {
        if (this.apply(this.rc) case var $1?) {
          return $1;
        }
      }
      this.pos = mark;
      if (this.f14() case _?) {
        if (this.apply(this.rc) case var $1?) {
          return $1;
        }
      }
      this.pos = mark;
      if (this.apply(this.rd) case var $?) {
        return $;
      }
    }
  }

  /// `global::callLike`
  Object? rd() {
    if (this.pos case var mark) {
      if (this.apply(this.rd) case (var $0 && var target)?) {
        if (this.fs() case var $1?) {
          if (this.ff() case var $2?) {
            if (this.fm() case var $3?) {
              if (this.fl() case var $4?) {
                return ($0, $1, $2, $3, $4);
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.rd) case (var $0 && var target)?) {
        if (this.fs() case var $1?) {
          if (this.fe() case var $2?) {
            if (this.fm() case var $3?) {
              if (this.f8() case (var $4 && var min)?) {
                if (this.fq() case var $5?) {
                  if (this.f8() case (var $6 && var max)?) {
                    if (this.fl() case var $7?) {
                      return ($0, $1, $2, $3, $4, $5, $6, $7);
                    }
                  }
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.rd) case (var $0 && var target)?) {
        if (this.fs() case var $1?) {
          if (this.fe() case var $2?) {
            if (this.fm() case var $3?) {
              if (this.f8() case (var $4 && var number)?) {
                if (this.fl() case var $5?) {
                  return ($0, $1, $2, $3, $4, $5);
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.rd) case (var $0 && var target)?) {
        if (this.fs() case var $1?) {
          if (this.fe() case var $2?) {
            if (this.ft() case var $3) {
              if (this.f8() case (var $4 && var number)?) {
                if (this.ft() case var $5) {
                  return ($0, $1, $2, $3, $4, $5);
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.rd) case (var $0 && var sep)?) {
        if (this.fs() case var $1?) {
          if (this.fg() case var $2?) {
            if (this.fm() case var $3?) {
              if (this.apply(this.r5) case (var $4 && var body)?) {
                if (this.fl() case var $5?) {
                  if (this.fp() case var $6?) {
                    if (this.fn() case var $7?) {
                      return ($0, $1, $2, $3, $4, $5, $6, $7);
                    }
                  }
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.rd) case (var $0 && var sep)?) {
        if (this.fs() case var $1?) {
          if (this.fg() case var $2?) {
            if (this.fm() case var $3?) {
              if (this.apply(this.r5) case (var $4 && var body)?) {
                if (this.fl() case var $5?) {
                  if (this.fo() case var $6?) {
                    if (this.fn() case var $7?) {
                      return ($0, $1, $2, $3, $4, $5, $6, $7);
                    }
                  }
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.rd) case (var $0 && var sep)?) {
        if (this.fs() case var $1?) {
          if (this.fg() case var $2?) {
            if (this.fm() case var $3?) {
              if (this.apply(this.r5) case (var $4 && var body)?) {
                if (this.fl() case var $5?) {
                  if (this.fp() case var $6?) {
                    return ($0, $1, $2, $3, $4, $5, $6);
                  }
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.rd) case (var $0 && var sep)?) {
        if (this.fs() case var $1?) {
          if (this.fg() case var $2?) {
            if (this.fm() case var $3?) {
              if (this.apply(this.r5) case (var $4 && var body)?) {
                if (this.fl() case var $5?) {
                  if (this.fo() case var $6?) {
                    return ($0, $1, $2, $3, $4, $5, $6);
                  }
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.rd) case (var $0 && var sep)?) {
        if (this.fs() case var $1?) {
          if (this.fg() case var $2?) {
            if (this.fm() case var $3?) {
              if (this.apply(this.r5) case (var $4 && var body)?) {
                if (this.fl() case var $5?) {
                  return ($0, $1, $2, $3, $4, $5);
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.rd) case (var $0 && var sep)?) {
        if (this.fs() case var $1?) {
          if (this.fg() case var $2?) {
            if (this.ft() case var $3) {
              if (this.apply(this.re) case (var $4 && var body)?) {
                if (this.ft() case var $5) {
                  return ($0, $1, $2, $3, $4, $5);
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
  Object? re() {
    if (this.pos case var mark) {
      if (this.fm() case _?) {
        if (this.apply(this.r5) case var $1?) {
          if (this.fl() case _?) {
            return $1;
          }
        }
      }
      this.pos = mark;
      if (this.ft() case _) {
        if (this.matchPattern(_string.$58) case var $1?) {
          if (this.ft() case _) {
            return $1;
          }
        }
      }
      this.pos = mark;
      if (this.ft() case _) {
        if (this.matchPattern(_string.$28) case var $1?) {
          if (this.ft() case _) {
            return $1;
          }
        }
      }
      this.pos = mark;
      if (this.fs() case var $?) {
        return $;
      }
      this.pos = mark;
      if (this.ft() case _) {
        if (this.matchPattern(_string.$59) case var $1?) {
          if (this.ft() case _) {
            return $1;
          }
        }
      }
      this.pos = mark;
      if (this.ft() case _) {
        if (this.f15() case var $1?) {
          if (this.ft() case _) {
            return $1;
          }
        }
      }
      this.pos = mark;
      if (this.ft() case _) {
        if (this.f16() case var $1?) {
          if (this.ft() case _) {
            return $1;
          }
        }
      }
      this.pos = mark;
      if (this.ft() case _) {
        if (this.f17() case var $1?) {
          if (this.ft() case _) {
            return $1;
          }
        }
      }
      this.pos = mark;
      if (this.ft() case _) {
        if (this.f18() case var $1?) {
          if (this.ft() case _) {
            return $1;
          }
        }
      }
      this.pos = mark;
      if (this.ft() case _) {
        if (this.f19() case var $1?) {
          if (this.ft() case _) {
            return $1;
          }
        }
      }
      this.pos = mark;
      if (this.ft() case _) {
        if (this.f1a() case var $1?) {
          if (this.ft() case _) {
            return $1;
          }
        }
      }
      this.pos = mark;
      if (this.ft() case _) {
        if (this.f1b() case var $1?) {
          if (this.ft() case _) {
            return $1;
          }
        }
      }
      this.pos = mark;
      if (this.ft() case _) {
        if (this.f1c() case var $1?) {
          if (this.ft() case _) {
            return $1;
          }
        }
      }
      this.pos = mark;
      if (this.ft() case _) {
        if (this.f1d() case var $1?) {
          if (this.ft() case _) {
            return $1;
          }
        }
      }
      this.pos = mark;
      if (this.ft() case _) {
        if (this.f1e() case var $1?) {
          if (this.ft() case _) {
            return $1;
          }
        }
      }
      this.pos = mark;
      if (this.ft() case _) {
        if (this.f1f() case var $1?) {
          if (this.ft() case _) {
            return $1;
          }
        }
      }
      this.pos = mark;
      if (this.ft() case _) {
        if (this.f1g() case var $1?) {
          if (this.ft() case _) {
            return $1;
          }
        }
      }
      this.pos = mark;
      if (this.ft() case _) {
        if (this.f1p() case var $1?) {
          if (this.ft() case _) {
            return $1;
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$46) case _?) {
        if (this.f1r() case var $1?) {
          if (this.matchPattern(_string.$46) case _?) {
            return $1;
          }
        }
      }
      this.pos = mark;
      if (this.ft() case _) {
        if (this.f20() case var $1?) {
          if (this.ft() case _) {
            return $1;
          }
        }
      }
      this.pos = mark;
      if (this.f3() case var $?) {
        return $;
      }
    }
  }

  /// `global::code::curly`
  Object rf() {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$3) case _?) {
        if (this.pos case var mark) {
          if (this.f21() case var _0) {
            if ([if (_0 case var _0?) _0] case (var $1 && var _l1)) {
              if (_l1.isNotEmpty) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.f21() case var _0?) {
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
                return $1;
              }
            }
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
  Object rg() {
    if (this.pos case var mark) {
      if (this.f22() case var _0) {
        if ([if (_0 case var _0?) _0] case (var code && var _l1)) {
          if (_l1.isNotEmpty) {
            for (;;) {
              if (this.pos case var mark) {
                if (this.f22() case var _0?) {
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

  /// `global::dart::literal::string`
  Object? rh() {
    if (this.f23() case var _0?) {
      if ([_0] case var _l1) {
        for (;;) {
          if (this.pos case var mark) {
            if (this.ft() case _) {
              if (this.f23() case var _0?) {
                _l1.add(_0);
                continue;
              }
            }
            this.pos = mark;
            break;
          }
        }
        return _l1;
      }
    }
  }

  /// `global::dart::literal::identifier`
  Object? ri() {
    if (this.f7() case var $?) {
      return $;
    }
  }

  /// `global::dart::literal::string::balanced`
  Object rj() {
    if (this.pos case var mark) {
      if (this.f24() case var _0) {
        if ([if (_0 case var _0?) _0] case (var code && var _l1)) {
          if (_l1.isNotEmpty) {
            for (;;) {
              if (this.pos case var mark) {
                if (this.f24() case var _0?) {
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
  Object? rk() {
    if (this.ft() case _) {
      if (this.apply(this.rl) case var $1?) {
        if (this.ft() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::dart::type::type`
  Object? rl() {
    if (this.pos case var mark) {
      if (this.apply(this.rp) case (var $0 && var parameters)?) {
        if (this.fi() case var $1?) {
          if (this.apply(this.rl) case (var $2 && var type)?) {
            return ($0, $1, $2);
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.rl) case (var $0 && var type)?) {
        if (this.ft() case var $1) {
          if (this.matchPattern(_string.$60) case var $2?) {
            if (this.apply(this.rp) case (var $3 && var parameters)?) {
              if (this.fn() case var $4) {
                return ($0, $1, $2, $3, $4);
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.rm) case var $?) {
        return $;
      }
    }
  }

  /// `global::dart::type::nullable`
  Object? rm() {
    if (this.apply(this.rn) case (var $0 && var nonNullable)?) {
      if (this.fn() case var $1) {
        return ($0, $1);
      }
    }
  }

  /// `global::dart::type::nonNullable`
  Object? rn() {
    if (this.pos case var mark) {
      if (this.apply(this.rq) case var $?) {
        return $;
      }
      this.pos = mark;
      if (this.apply(this.ro) case var $?) {
        return $;
      }
      this.pos = mark;
      if (this.apply(this.rs) case var $?) {
        return $;
      }
    }
  }

  /// `global::dart::type::record`
  Object? ro() {
    if (this.pos case var mark) {
      if (this.fm() case var $0?) {
        if (this.apply(this.rv) case (var $1 && var positional)?) {
          if (this.fq() case var $2?) {
            if (this.apply(this.ru) case (var $3 && var named)?) {
              if (this.fl() case var $4?) {
                return ($0, $1, $2, $3, $4);
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.fm() case var $0?) {
        if (this.apply(this.rv) case (var $1 && var positional)?) {
          if (this.fq() case var $2) {
            if (this.fl() case var $3?) {
              return ($0, $1, $2, $3);
            }
          }
        }
      }
      this.pos = mark;
      if (this.fm() case var $0?) {
        if (this.apply(this.ru) case (var $1 && var named)?) {
          if (this.fl() case var $2?) {
            return ($0, $1, $2);
          }
        }
      }
      this.pos = mark;
      if (this.fm() case var $0?) {
        if (this.fl() case var $1?) {
          return ($0, $1);
        }
      }
    }
  }

  /// `global::dart::type::function_parameters`
  Object? rp() {
    if (this.pos case var mark) {
      if (this.fm() case var $0?) {
        if (this.apply(this.rv) case (var $1 && var positional)?) {
          if (this.fq() case var $2?) {
            if (this.apply(this.ru) case (var $3 && var named)?) {
              if (this.fl() case var $4?) {
                return ($0, $1, $2, $3, $4);
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.fm() case var $0?) {
        if (this.apply(this.rv) case (var $1 && var positional)?) {
          if (this.fq() case var $2?) {
            if (this.apply(this.rt) case (var $3 && var optional)?) {
              if (this.fl() case var $4?) {
                return ($0, $1, $2, $3, $4);
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.fm() case var $0?) {
        if (this.apply(this.rv) case (var $1 && var positional)?) {
          if (this.fq() case var $2) {
            if (this.fl() case var $3?) {
              return ($0, $1, $2, $3);
            }
          }
        }
      }
      this.pos = mark;
      if (this.fm() case var $0?) {
        if (this.apply(this.ru) case (var $1 && var named)?) {
          if (this.fl() case var $2?) {
            return ($0, $1, $2);
          }
        }
      }
      this.pos = mark;
      if (this.fm() case var $0?) {
        if (this.apply(this.rt) case (var $1 && var optional)?) {
          if (this.fl() case var $2?) {
            return ($0, $1, $2);
          }
        }
      }
      this.pos = mark;
      if (this.fm() case var $0?) {
        if (this.fl() case var $1?) {
          return ($0, $1);
        }
      }
    }
  }

  /// `global::dart::type::generic`
  Object? rq() {
    if (this.apply(this.rs) case (var $0 && var base)?) {
      if (this.f25() case var $1?) {
        if (this.apply(this.rr) case (var $2 && var arguments)?) {
          if (this.f26() case var $3?) {
            return ($0, $1, $2, $3);
          }
        }
      }
    }
  }

  /// `global::dart::type::arguments`
  Object? rr() {
    if (this.apply(this.rl) case var _0?) {
      if ([_0] case var _l1) {
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
        return _l1;
      }
    }
  }

  /// `global::dart::type::base`
  Object? rs() {
    if (this.f7() case var _0?) {
      if ([_0] case var _l1) {
        for (;;) {
          if (this.pos case var mark) {
            if (this.fs() case _?) {
              if (this.f7() case var _0?) {
                _l1.add(_0);
                continue;
              }
            }
            this.pos = mark;
            break;
          }
        }
        return _l1;
      }
    }
  }

  /// `global::dart::type::parameters::optional`
  Object? rt() {
    if (this.f27() case var $0?) {
      if (this.apply(this.rv) case var $1?) {
        if (this.fq() case var $2) {
          if (this.f28() case var $3?) {
            return ($0, $1, $2, $3);
          }
        }
      }
    }
  }

  /// `global::dart::type::parameters::named`
  Object? ru() {
    if (this.fk() case var $0?) {
      if (this.apply(this.rw) case var $1?) {
        if (this.fq() case var $2) {
          if (this.fj() case var $3?) {
            return ($0, $1, $2, $3);
          }
        }
      }
    }
  }

  /// `global::dart::type::fields::positional`
  Object? rv() {
    if (this.apply(this.rx) case var _0?) {
      if ([_0] case var _l1) {
        for (;;) {
          if (this.pos case var mark) {
            if (this.fq() case _?) {
              if (this.apply(this.rx) case var _0?) {
                _l1.add(_0);
                continue;
              }
            }
            this.pos = mark;
            break;
          }
        }
        return _l1;
      }
    }
  }

  /// `global::dart::type::fields::named`
  Object? rw() {
    if (this.apply(this.ry) case var _0?) {
      if ([_0] case var _l1) {
        for (;;) {
          if (this.pos case var mark) {
            if (this.fq() case _?) {
              if (this.apply(this.ry) case var _0?) {
                _l1.add(_0);
                continue;
              }
            }
            this.pos = mark;
            break;
          }
        }
        return _l1;
      }
    }
  }

  /// `global::dart::type::field::positional`
  Object? rx() {
    if (this.apply(this.rl) case var $0?) {
      if (this.ft() case var $1) {
        if (this.f7() case var $2) {
          return ($0, $1, $2);
        }
      }
    }
  }

  /// `global::dart::type::field::named`
  Object? ry() {
    if (this.apply(this.rl) case var $0?) {
      if (this.ft() case var $1) {
        if (this.f7() case var $2?) {
          return ($0, $1, $2);
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
  static final _trie = (Trie.from(["{", "}"]),);
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
    "..",
    "=>",
    "}",
    "{",
    ")",
    "(",
    "?",
    "*",
    "+",
    ",",
    "|",
    ".",
    "\"\"\"",
    "r",
    "'''",
    "\"",
    "'",
    "\$",
    ":",
    "@",
    "<~",
    "~>",
    "~",
    "&",
    "!",
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
    "<",
    ">",
    "::",
    "=",
    "<-",
    "->",
    ";",
    "^",
    "ε",
    "Function",
  );
  static const _range = (
    {(97, 122), (65, 90), (48, 57), (95, 95), (36, 36)},
    {(97, 122), (65, 90), (95, 95), (36, 36)},
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

    if (failures[pos] ??= <String>{} case Set<String> failures) {
      trie._keys(trie._innerMap).map((List<String> v) => v.join()).forEach(failures.add);
    }
    return null;
  }
}

class Trie {
  Trie() : _innerMap = HashMap<_Key<String>, Object>();
  factory Trie.from(Iterable<String> strings) =>
      strings.fold(Trie(), (Trie t, String s) => t..add(s));
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
      map =
          map.putIfAbsent((keys[i], null), HashMap<_Key<String>, Object>.new)
              as HashMap<_Key<String>, Object>;
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
