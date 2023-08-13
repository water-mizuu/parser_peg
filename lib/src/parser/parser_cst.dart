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
final class PegParserCst extends _PegParser<Object> {
  PegParserCst();

  @override
  get start => r0;


  /// `global::type`
  Object? f0() {
    if (this.pos case var mark) {
      if (this.ft() case var $0) {
        if (this.f3s() case var $1?) {
          return ("global::type", [$0, $1]);
        }
      }
      this.pos = mark;
      if (this.apply(this.rk) case var $?) {
        return ("global::type", $);
      }
    }
  }

  /// `global::namespaceReference`
  Object f1() {
    if (this.pos case var mark) {
      if (this.f3v() case var _0) {
        if ([if (_0 case var _0?) _0] case var _loop1) {
          if (_loop1.isNotEmpty) {
            for (;;) {
              if (this.pos case var mark) {
                if (this.f3v() case var _0?) {
                  _loop1.add(_0);
                  continue;
                }
                this.pos = mark;
                break;
              }
            }
          } else {
            this.pos = mark;
          }
          return ("global::namespaceReference", _loop1);
        }
      }
    }
  }

  /// `global::namespacedIdentifier`
  Object? f2() {
    if (this.f1() case var $0) {
      if (this.f8() case var $1?) {
        return ("global::namespacedIdentifier", [$0, $1]);
      }
    }
  }

  /// `global::name`
  Object? f3() {
    if (this.pos case var mark) {
      if (this.f1() case var $0) {
        if (this.f6() case var $1?) {
          return ("global::name", [$0, $1]);
        }
      }
      this.pos = mark;
      if (this.f2() case var $?) {
        return ("global::name", $);
      }
    }
  }

  /// `global::body`
  Object? f4() {
    if (this.f3z() case var $0?) {
      if (this.apply(this.r5) case var $1?) {
        if (this.f41() case var $2?) {
          return ("global::body", [$0, $1, $2]);
        }
      }
    }
  }

  /// `global::literal::range::atom`
  Object? f5() {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$1) case var $0?) {
        if (pos < buffer.length) {
          if (buffer[pos] case var $1) {
            pos++;
            return ("global::literal::range::atom", [$0, $1]);
          }
        }
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.matchPattern(_string.$2) case (var $0 && null)) {
          this.pos = mark;
          if (pos < buffer.length) {
            if (buffer[pos] case var $1) {
              pos++;
              return ("global::literal::range::atom", [$0, $1]);
            }
          }
        }
      }
    }
  }

  /// `global::literal::raw`
  Object? f6() {
    if (this.matchPattern(_string.$3) case var $0?) {
      if (this.f43() case var $1?) {
        return ("global::literal::raw", [$0, $1]);
      }
    }
  }

  /// `global::dart::type::fields::named`
  Object? f7() {
    if (this.f10() case var _0?) {
      if (<Object>[_0] case var _loop2) {
        for (;;) {
          if (this.pos case var mark) {
            if (this.fq() case var _1?) {
              if (this.f10() case var _0?) {
                _loop2.addAll([_1, _0]);
                continue;
              }
            }
            this.pos = mark;
            break;
          }
        }
        return ("global::dart::type::fields::named", _loop2);
      }
    }
  }

  /// `global::identifier`
  Object? f8() {
    if (this.matchRange(_range.$2) case var $0?) {
      if (this.pos case var mark) {
        if (this.matchRange(_range.$1) case var _0) {
          if ([if (_0 case var _0?) _0] case (var $1 && var _loop1)) {
            if (_loop1.isNotEmpty) {
              for (;;) {
                if (this.pos case var mark) {
                  if (this.matchRange(_range.$1) case var _0?) {
                    _loop1.add(_0);
                    continue;
                  }
                  this.pos = mark;
                  break;
                }
              }
            } else {
              this.pos = mark;
            }
            return ("global::identifier", [$0, $1]);
          }
        }
      }
    }
  }

  /// `global::number`
  Object? f9() {
    if (matchPattern(_regexp.$1) case var _0?) {
      if ([_0] case var _loop1) {
        for (;;) {
          if (this.pos case var mark) {
            if (matchPattern(_regexp.$1) case var _0?) {
              _loop1.add(_0);
              continue;
            }
            this.pos = mark;
            break;
          }
        }
        return ("global::number", _loop1);
      }
    }
  }

  /// `global::kw::decorator`
  Object? fa() {
    if (this.pos case var mark) {
      if (this.fb() case var $?) {
        return ("global::kw::decorator", $);
      }
      this.pos = mark;
      if (this.fc() case var $?) {
        return ("global::kw::decorator", $);
      }
      this.pos = mark;
      if (this.fd() case var $?) {
        return ("global::kw::decorator", $);
      }
    }
  }

  /// `global::kw::decorator::rule`
  Object? fb() {
    if (this.ft() case var $0) {
      if (this.matchPattern(_string.$4) case var $1?) {
        if (this.ft() case var $2) {
          return ("global::kw::decorator::rule", [$0, $1, $2]);
        }
      }
    }
  }

  /// `global::kw::decorator::fragment`
  Object? fc() {
    if (this.ft() case var $0) {
      if (this.matchPattern(_string.$5) case var $1?) {
        if (this.ft() case var $2) {
          return ("global::kw::decorator::fragment", [$0, $1, $2]);
        }
      }
    }
  }

  /// `global::kw::decorator::inline`
  Object? fd() {
    if (this.ft() case var $0) {
      if (this.matchPattern(_string.$6) case var $1?) {
        if (this.ft() case var $2) {
          return ("global::kw::decorator::inline", [$0, $1, $2]);
        }
      }
    }
  }

  /// `global::kw::var`
  Object? fe() {
    if (this.ft() case var $0) {
      if (this.matchPattern(_string.$7) case var $1?) {
        if (this.ft() case var $2) {
          return ("global::kw::var", [$0, $1, $2]);
        }
      }
    }
  }

  /// `global::mac::range`
  Object? ff() {
    if (this.ft() case var $0) {
      if (this.matchPattern(_string.$8) case var $1?) {
        if (this.ft() case var $2) {
          return ("global::mac::range", [$0, $1, $2]);
        }
      }
    }
  }

  /// `global::mac::flat`
  Object? fg() {
    if (this.ft() case var $0) {
      if (this.matchPattern(_string.$9) case var $1?) {
        if (this.ft() case var $2) {
          return ("global::mac::flat", [$0, $1, $2]);
        }
      }
    }
  }

  /// `global::mac::sep`
  Object? fh() {
    if (this.ft() case var $0) {
      if (this.matchPattern(_string.$10) case var $1?) {
        if (this.ft() case var $2) {
          return ("global::mac::sep", [$0, $1, $2]);
        }
      }
    }
  }

  /// `global::..`
  Object? fi() {
    if (this.ft() case var $0) {
      if (this.f44() case var $1?) {
        return ("global::..", [$0, $1]);
      }
    }
  }

  /// `global::}`
  Object? fj() {
    if (this.ft() case var $0) {
      if (this.f45() case var $1?) {
        return ("global::}", [$0, $1]);
      }
    }
  }

  /// `global::{`
  Object? fk() {
    if (this.ft() case var $0) {
      if (this.f46() case var $1?) {
        return ("global::{", [$0, $1]);
      }
    }
  }

  /// `global::)`
  Object? fl() {
    if (this.ft() case var $0) {
      if (this.f47() case var $1?) {
        return ("global::)", [$0, $1]);
      }
    }
  }

  /// `global::(`
  Object? fm() {
    if (this.ft() case var $0) {
      if (this.f48() case var $1?) {
        return ("global::(", [$0, $1]);
      }
    }
  }

  /// `global::?`
  Object? fn() {
    if (this.ft() case var $0) {
      if (this.f49() case var $1?) {
        return ("global::?", [$0, $1]);
      }
    }
  }

  /// `global::*`
  Object? fo() {
    if (this.ft() case var $0) {
      if (this.f4a() case var $1?) {
        return ("global::*", [$0, $1]);
      }
    }
  }

  /// `global::+`
  Object? fp() {
    if (this.ft() case var $0) {
      if (this.f4b() case var $1?) {
        return ("global::+", [$0, $1]);
      }
    }
  }

  /// `global::,`
  Object? fq() {
    if (this.ft() case var $0) {
      if (this.f4c() case var $1?) {
        return ("global::,", [$0, $1]);
      }
    }
  }

  /// `global::|`
  Object? fr() {
    if (this.ft() case var $0) {
      if (this.f4d() case var $1?) {
        return ("global::|", [$0, $1]);
      }
    }
  }

  /// `global::.`
  Object? fs() {
    if (this.ft() case var $0) {
      if (this.f4e() case var $1?) {
        return ("global::.", [$0, $1]);
      }
    }
  }

  /// `global::_`
  Object ft() {
    if (this.pos case var mark) {
      if (this.f4f() case var _0) {
        if ([if (_0 case var _0?) _0] case var _loop1) {
          if (_loop1.isNotEmpty) {
            for (;;) {
              if (this.pos case var mark) {
                if (this.f4f() case var _0?) {
                  _loop1.add(_0);
                  continue;
                }
                this.pos = mark;
                break;
              }
            }
          } else {
            this.pos = mark;
          }
          return ("global::_", _loop1);
        }
      }
    }
  }

  /// `ROOT`
  Object? fu() {
    if (this.apply(this.r0) case var $?) {
      return ("ROOT", $);
    }
  }

  /// `global::dart::literal::string::body`
  late final fv = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$12) case var $0?) {
        if (this.matchPattern(_string.$11) case var $1?) {
          if (this.pos case var mark) {
            if (this.f4g() case var _0) {
              if ([if (_0 case var _0?) _0] case (var $2 && var _loop1)) {
                if (_loop1.isNotEmpty) {
                  for (;;) {
                    if (this.pos case var mark) {
                      if (this.f4g() case var _0?) {
                        _loop1.add(_0);
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
                  return ("global::dart::literal::string::body", [$0, $1, $2, $3]);
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
              if ([if (_2 case var _2?) _2] case (var $2 && var _loop3)) {
                if (_loop3.isNotEmpty) {
                  for (;;) {
                    if (this.pos case var mark) {
                      if (this.f4h() case var _2?) {
                        _loop3.add(_2);
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
                  return ("global::dart::literal::string::body", [$0, $1, $2, $3]);
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
              if ([if (_4 case var _4?) _4] case (var $2 && var _loop5)) {
                if (_loop5.isNotEmpty) {
                  for (;;) {
                    if (this.pos case var mark) {
                      if (this.f4i() case var _4?) {
                        _loop5.add(_4);
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
                  return ("global::dart::literal::string::body", [$0, $1, $2, $3]);
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
              if ([if (_6 case var _6?) _6] case (var $2 && var _loop7)) {
                if (_loop7.isNotEmpty) {
                  for (;;) {
                    if (this.pos case var mark) {
                      if (this.f4j() case var _6?) {
                        _loop7.add(_6);
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
                  return ("global::dart::literal::string::body", [$0, $1, $2, $3]);
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
            if ([if (_8 case var _8?) _8] case (var $1 && var _loop9)) {
              if (_loop9.isNotEmpty) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.f4k() case var _8?) {
                      _loop9.add(_8);
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
                return ("global::dart::literal::string::body", [$0, $1, $2]);
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$13) case var $0?) {
        if (this.pos case var mark) {
          if (this.f4l() case var _10) {
            if ([if (_10 case var _10?) _10] case (var $1 && var _loop11)) {
              if (_loop11.isNotEmpty) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.f4l() case var _10?) {
                      _loop11.add(_10);
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
                return ("global::dart::literal::string::body", [$0, $1, $2]);
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$14) case var $0?) {
        if (this.pos case var mark) {
          if (this.f4m() case var _12) {
            if ([if (_12 case var _12?) _12] case (var $1 && var _loop13)) {
              if (_loop13.isNotEmpty) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.f4m() case var _12?) {
                      _loop13.add(_12);
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
                return ("global::dart::literal::string::body", [$0, $1, $2]);
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$15) case var $0?) {
        if (this.pos case var mark) {
          if (this.f4n() case var _14) {
            if ([if (_14 case var _14?) _14] case (var $1 && var _loop15)) {
              if (_loop15.isNotEmpty) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.f4n() case var _14?) {
                      _loop15.add(_14);
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
                return ("global::dart::literal::string::body", [$0, $1, $2]);
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
              return ("global::dart::literal::string::interpolation", [$0, $1, $2, $3]);
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$18) case var $0?) {
        if (this.apply(this.ri) case var $1?) {
          return ("global::dart::literal::string::interpolation", [$0, $1]);
        }
      }
    }
  };

  /// `global::dart::type::generic`
  Object? fx() {
    if (this.f4o() case var $0?) {
      if (this.f4q() case var $1?) {
        if (this.fy() case var $2?) {
          if (this.f4s() case var $3?) {
            return ("global::dart::type::generic", [$0, $1, $2, $3]);
          }
        }
      }
    }
  }

  /// `global::dart::type::arguments`
  Object? fy() {
    if (this.apply(this.rl) case var _0?) {
      if (<Object>[_0] case var _loop2) {
        for (;;) {
          if (this.pos case var mark) {
            if (this.fq() case var _1?) {
              if (this.apply(this.rl) case var _0?) {
                _loop2.addAll([_1, _0]);
                continue;
              }
            }
            this.pos = mark;
            break;
          }
        }
        return ("global::dart::type::arguments", _loop2);
      }
    }
  }

  /// `global::dart::type::field::positional`
  Object? fz() {
    if (this.apply(this.rl) case var $0?) {
      if (this.ft() case var $1) {
        if (this.f8() case var $2) {
          return ("global::dart::type::field::positional", [$0, $1, $2]);
        }
      }
    }
  }

  /// `global::dart::type::field::named`
  Object? f10() {
    if (this.apply(this.rl) case var $0?) {
      if (this.ft() case var $1) {
        if (this.f8() case var $2?) {
          return ("global::dart::type::field::named", [$0, $1, $2]);
        }
      }
    }
  }

  /// `global::dart::type::fields::positional`
  Object? f11() {
    if (this.fz() case var _0?) {
      if (<Object>[_0] case var _loop2) {
        for (;;) {
          if (this.pos case var mark) {
            if (this.fq() case var _1?) {
              if (this.fz() case var _0?) {
                _loop2.addAll([_1, _0]);
                continue;
              }
            }
            this.pos = mark;
            break;
          }
        }
        return ("global::dart::type::fields::positional", _loop2);
      }
    }
  }

  /// `fragment0`
  late final f12 = () {
    if (this.matchPattern(_string.$19) case var $0?) {
      if (this.ft() case var $1) {
        return [$0, $1];
      }
    }
  };

  /// `fragment1`
  late final f13 = () {
    if (this.ft() case var $0) {
      if (this.f12() case var $1?) {
        return [$0, $1];
      }
    }
  };

  /// `fragment2`
  late final f14 = () {
    if (this.matchPattern(_string.$20) case var $0?) {
      if (this.ft() case var $1) {
        return [$0, $1];
      }
    }
  };

  /// `fragment3`
  late final f15 = () {
    if (this.ft() case var $0) {
      if (this.f14() case var $1?) {
        return [$0, $1];
      }
    }
  };

  /// `fragment4`
  late final f16 = () {
    if (this.matchPattern(_string.$21) case var $0?) {
      if (this.ft() case var $1) {
        return [$0, $1];
      }
    }
  };

  /// `fragment5`
  late final f17 = () {
    if (this.ft() case var $0) {
      if (this.f16() case var $1?) {
        return [$0, $1];
      }
    }
  };

  /// `fragment6`
  late final f18 = () {
    if (this.f17() case var $0?) {
      if (this.f9() case var $1?) {
        return [$0, $1];
      }
    }
  };

  /// `fragment7`
  late final f19 = () {
    if (this.matchPattern(_string.$22) case var $0?) {
      if (this.ft() case var $1) {
        return [$0, $1];
      }
    }
  };

  /// `fragment8`
  late final f1a = () {
    if (this.ft() case var $0) {
      if (this.f19() case var $1?) {
        return [$0, $1];
      }
    }
  };

  /// `fragment9`
  late final f1b = () {
    if (this.matchPattern(_string.$23) case var $0?) {
      if (this.ft() case var $1) {
        return [$0, $1];
      }
    }
  };

  /// `fragment10`
  late final f1c = () {
    if (this.ft() case var $0) {
      if (this.f1b() case var $1?) {
        return [$0, $1];
      }
    }
  };

  /// `fragment11`
  late final f1d = () {
    if (this.matchPattern(_string.$24) case var $0?) {
      if (this.ft() case var $1) {
        return [$0, $1];
      }
    }
  };

  /// `fragment12`
  late final f1e = () {
    if (this.ft() case var $0) {
      if (this.f1d() case var $1?) {
        return [$0, $1];
      }
    }
  };

  /// `fragment13`
  late final f1f = () {
    if (this.matchPattern(_string.$25) case var $0?) {
      if (this.ft() case var $1) {
        return [$0, $1];
      }
    }
  };

  /// `fragment14`
  late final f1g = () {
    if (this.ft() case var $0) {
      if (this.f1f() case var $1?) {
        return [$0, $1];
      }
    }
  };

  /// `fragment15`
  late final f1h = () {
    if (this.matchPattern(_string.$26) case var $0?) {
      if (this.ft() case var $1) {
        return [$0, $1];
      }
    }
  };

  /// `fragment16`
  late final f1i = () {
    if (this.ft() case var $0) {
      if (this.f1h() case var $1?) {
        return [$0, $1];
      }
    }
  };

  /// `fragment17`
  late final f1j = () {
    if (this.apply(this.r5) case var $0?) {
      if (this.fl() case var $1?) {
        return [$0, $1];
      }
    }
  };

  /// `fragment18`
  late final f1k = () {
    if (this.matchPattern(_string.$27) case var $0?) {
      if (this.ft() case var $1) {
        return [$0, $1];
      }
    }
  };

  /// `fragment19`
  late final f1l = () {
    if (this.matchPattern(_string.$18) case var $0?) {
      if (this.ft() case var $1) {
        return [$0, $1];
      }
    }
  };

  /// `fragment20`
  late final f1m = () {
    if (this.matchPattern(_string.$28) case var $0?) {
      if (this.ft() case var $1) {
        return [$0, $1];
      }
    }
  };

  /// `fragment21`
  late final f1n = () {
    if (this.matchPattern(_string.$1) case var $0?) {
      if (this.matchPattern(_string.$1) case var $1?) {
        return [$0, $1];
      }
    }
  };

  /// `fragment22`
  late final f1o = () {
    if (this.f1n() case var $0?) {
      if (this.ft() case var $1) {
        return [$0, $1];
      }
    }
  };

  /// `fragment23`
  late final f1p = () {
    if (this.matchPattern(_string.$1) case var $0?) {
      if (this.matchPattern(_string.$29) case var $1?) {
        return [$0, $1];
      }
    }
  };

  /// `fragment24`
  late final f1q = () {
    if (this.f1p() case var $0?) {
      if (this.ft() case var $1) {
        return [$0, $1];
      }
    }
  };

  /// `fragment25`
  late final f1r = () {
    if (this.matchPattern(_string.$1) case var $0?) {
      if (this.matchPattern(_string.$30) case var $1?) {
        return [$0, $1];
      }
    }
  };

  /// `fragment26`
  late final f1s = () {
    if (this.f1r() case var $0?) {
      if (this.ft() case var $1) {
        return [$0, $1];
      }
    }
  };

  /// `fragment27`
  late final f1t = () {
    if (this.matchPattern(_string.$1) case var $0?) {
      if (this.matchPattern(_string.$31) case var $1?) {
        return [$0, $1];
      }
    }
  };

  /// `fragment28`
  late final f1u = () {
    if (this.f1t() case var $0?) {
      if (this.ft() case var $1) {
        return [$0, $1];
      }
    }
  };

  /// `fragment29`
  late final f1v = () {
    if (this.matchPattern(_string.$1) case var $0?) {
      if (this.matchPattern(_string.$29) case var $1?) {
        return [$0, $1];
      }
    }
  };

  /// `fragment30`
  late final f1w = () {
    if (this.f1v() case var $0?) {
      if (this.ft() case var $1) {
        return [$0, $1];
      }
    }
  };

  /// `fragment31`
  late final f1x = () {
    if (this.matchPattern(_string.$1) case var $0?) {
      if (this.matchPattern(_string.$30) case var $1?) {
        return [$0, $1];
      }
    }
  };

  /// `fragment32`
  late final f1y = () {
    if (this.f1x() case var $0?) {
      if (this.ft() case var $1) {
        return [$0, $1];
      }
    }
  };

  /// `fragment33`
  late final f1z = () {
    if (this.matchPattern(_string.$1) case var $0?) {
      if (this.matchPattern(_string.$31) case var $1?) {
        return [$0, $1];
      }
    }
  };

  /// `fragment34`
  late final f20 = () {
    if (this.f1z() case var $0?) {
      if (this.ft() case var $1) {
        return [$0, $1];
      }
    }
  };

  /// `fragment35`
  late final f21 = () {
    if (this.matchPattern(_string.$1) case var $0?) {
      if (this.matchPattern(_string.$32) case var $1?) {
        return [$0, $1];
      }
    }
  };

  /// `fragment36`
  late final f22 = () {
    if (this.f21() case var $0?) {
      if (this.ft() case var $1) {
        return [$0, $1];
      }
    }
  };

  /// `fragment37`
  late final f23 = () {
    if (this.matchPattern(_string.$1) case var $0?) {
      if (this.matchPattern(_string.$33) case var $1?) {
        return [$0, $1];
      }
    }
  };

  /// `fragment38`
  late final f24 = () {
    if (this.f23() case var $0?) {
      if (this.ft() case var $1) {
        return [$0, $1];
      }
    }
  };

  /// `fragment39`
  late final f25 = () {
    if (this.matchPattern(_string.$1) case var $0?) {
      if (this.matchPattern(_string.$12) case var $1?) {
        return [$0, $1];
      }
    }
  };

  /// `fragment40`
  late final f26 = () {
    if (this.f25() case var $0?) {
      if (this.ft() case var $1) {
        return [$0, $1];
      }
    }
  };

  /// `fragment41`
  late final f27 = () {
    if (this.matchPattern(_string.$1) case var $0?) {
      if (this.matchPattern(_string.$34) case var $1?) {
        return [$0, $1];
      }
    }
  };

  /// `fragment42`
  late final f28 = () {
    if (this.f27() case var $0?) {
      if (this.ft() case var $1) {
        return [$0, $1];
      }
    }
  };

  /// `fragment43`
  late final f29 = () {
    if (this.matchPattern(_string.$1) case var $0?) {
      if (this.matchPattern(_string.$35) case var $1?) {
        return [$0, $1];
      }
    }
  };

  /// `fragment44`
  late final f2a = () {
    if (this.f29() case var $0?) {
      if (this.ft() case var $1) {
        return [$0, $1];
      }
    }
  };

  /// `fragment45`
  late final f2b = () {
    if (this.matchPattern(_string.$1) case var $0?) {
      if (this.matchPattern(_string.$29) case var $1?) {
        return [$0, $1];
      }
    }
  };

  /// `fragment46`
  late final f2c = () {
    if (this.f2b() case var $0?) {
      if (this.ft() case var $1) {
        return [$0, $1];
      }
    }
  };

  /// `fragment47`
  late final f2d = () {
    if (this.matchPattern(_string.$1) case var $0?) {
      if (this.matchPattern(_string.$30) case var $1?) {
        return [$0, $1];
      }
    }
  };

  /// `fragment48`
  late final f2e = () {
    if (this.f2d() case var $0?) {
      if (this.ft() case var $1) {
        return [$0, $1];
      }
    }
  };

  /// `fragment49`
  late final f2f = () {
    if (this.matchPattern(_string.$1) case var $0?) {
      if (this.matchPattern(_string.$31) case var $1?) {
        return [$0, $1];
      }
    }
  };

  /// `fragment50`
  late final f2g = () {
    if (this.f2f() case var $0?) {
      if (this.ft() case var $1) {
        return [$0, $1];
      }
    }
  };

  /// `fragment51`
  late final f2h = () {
    if (this.matchPattern(_string.$1) case var $0?) {
      if (this.matchPattern(_string.$33) case var $1?) {
        return [$0, $1];
      }
    }
  };

  /// `fragment52`
  late final f2i = () {
    if (this.f2h() case var $0?) {
      if (this.ft() case var $1) {
        return [$0, $1];
      }
    }
  };

  /// `fragment53`
  late final f2j = () {
    if (this.matchPattern(_string.$1) case var $0?) {
      if (this.matchPattern(_string.$12) case var $1?) {
        return [$0, $1];
      }
    }
  };

  /// `fragment54`
  late final f2k = () {
    if (this.f2j() case var $0?) {
      if (this.ft() case var $1) {
        return [$0, $1];
      }
    }
  };

  /// `fragment55`
  late final f2l = () {
    if (this.matchPattern(_string.$1) case var $0?) {
      if (this.matchPattern(_string.$32) case var $1?) {
        return [$0, $1];
      }
    }
  };

  /// `fragment56`
  late final f2m = () {
    if (this.f2l() case var $0?) {
      if (this.ft() case var $1) {
        return [$0, $1];
      }
    }
  };

  /// `fragment57`
  late final f2n = () {
    if (this.matchPattern(_string.$1) case var $0?) {
      if (this.matchPattern(_string.$1) case var $1?) {
        return [$0, $1];
      }
    }
  };

  /// `fragment58`
  late final f2o = () {
    if (this.f2n() case var $0?) {
      if (this.ft() case var $1) {
        return [$0, $1];
      }
    }
  };

  /// `fragment59`
  late final f2p = () {
    if (this.pos case var mark) {
      if (this.pos case var mark) {
        if (this.matchPattern(_string.$36) case var $?) {
          return $;
        }
        this.pos = mark;
        if (this.ft() case var $0) {
          if (this.f2c() case var $1?) {
            return [$0, $1];
          }
        }
        this.pos = mark;
        if (this.ft() case var $0) {
          if (this.f2e() case var $1?) {
            return [$0, $1];
          }
        }
        this.pos = mark;
        if (this.ft() case var $0) {
          if (this.f2g() case var $1?) {
            return [$0, $1];
          }
        }
        this.pos = mark;
        if (this.ft() case var $0) {
          if (this.f2i() case var $1?) {
            return [$0, $1];
          }
        }
        this.pos = mark;
        if (this.ft() case var $0) {
          if (this.f2k() case var $1?) {
            return [$0, $1];
          }
        }
        this.pos = mark;
        if (this.ft() case var $0) {
          if (this.f2m() case var $1?) {
            return [$0, $1];
          }
        }
        this.pos = mark;
        if (this.ft() case var $0) {
          if (this.f2o() case var $1?) {
            return [$0, $1];
          }
        }
      }

      this.pos = mark;
      if (this.f5() case var $0?) {
        if (this.matchPattern(_string.$37) case var $1?) {
          if (this.f5() case var $2?) {
            return [$0, $1, $2];
          }
        }
      }
      this.pos = mark;
      if (this.f5() case var $?) {
        return $;
      }
    }
  };

  /// `fragment60`
  late final f2q = () {
    if (this.ft() case var $0) {
      if (this.matchPattern(_string.$38) case var $1?) {
        if (this.f2p() case var _0?) {
          if (<Object>[_0] case (var $2 && var _loop2)) {
            for (;;) {
              if (this.pos case var mark) {
                if (this.ft() case var _1) {
                  if (this.f2p() case var _0?) {
                    _loop2.addAll([_1, _0]);
                    continue;
                  }
                }
                this.pos = mark;
                break;
              }
            }
            if (this.matchPattern(_string.$2) case var $3?) {
              if (this.ft() case var $4) {
                return [$0, $1, $2, $3, $4];
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
      if (this.ft() case var $1) {
        return [$0, $1];
      }
    }
  };

  /// `fragment62`
  late final f2s = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$1) case var $0?) {
        if (pos < buffer.length) {
          if (buffer[pos] case var $1) {
            pos++;
            return [$0, $1];
          }
        }
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.matchPattern(_string.$39) case (var $0 && null)) {
          this.pos = mark;
          if (pos < buffer.length) {
            if (buffer[pos] case var $1) {
              pos++;
              return [$0, $1];
            }
          }
        }
      }
    }
  };

  /// `fragment63`
  late final f2t = () {
    if (this.f2s() case var _0?) {
      if ([_0] case var _loop1) {
        for (;;) {
          if (this.pos case var mark) {
            if (this.f2s() case var _0?) {
              _loop1.add(_0);
              continue;
            }
            this.pos = mark;
            break;
          }
        }
        return _loop1;
      }
    }
  };

  /// `fragment64`
  late final f2u = () {
    if (this.f2t() case var $0?) {
      if (this.matchPattern(_string.$39) case var $1?) {
        return [$0, $1];
      }
    }
  };

  /// `fragment65`
  late final f2v = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$11) case (var $0 && null)) {
        this.pos = mark;
        if (pos < buffer.length) {
          if (buffer[pos] case var $1) {
            pos++;
            return [$0, $1];
          }
        }
      }
    }
  };

  /// `fragment66`
  late final f2w = () {
    if (this.pos case var mark) {
      if (this.f2v() case var _0) {
        if ([if (_0 case var _0?) _0] case (var $0 && var _loop1)) {
          if (_loop1.isNotEmpty) {
            for (;;) {
              if (this.pos case var mark) {
                if (this.f2v() case var _0?) {
                  _loop1.add(_0);
                  continue;
                }
                this.pos = mark;
                break;
              }
            }
          } else {
            this.pos = mark;
          }
          if (this.matchPattern(_string.$11) case var $1?) {
            return [$0, $1];
          }
        }
      }
    }
  };

  /// `fragment67`
  late final f2x = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$13) case (var $0 && null)) {
        this.pos = mark;
        if (pos < buffer.length) {
          if (buffer[pos] case var $1) {
            pos++;
            return [$0, $1];
          }
        }
      }
    }
  };

  /// `fragment68`
  late final f2y = () {
    if (this.pos case var mark) {
      if (this.f2x() case var _0) {
        if ([if (_0 case var _0?) _0] case (var $0 && var _loop1)) {
          if (_loop1.isNotEmpty) {
            for (;;) {
              if (this.pos case var mark) {
                if (this.f2x() case var _0?) {
                  _loop1.add(_0);
                  continue;
                }
                this.pos = mark;
                break;
              }
            }
          } else {
            this.pos = mark;
          }
          if (this.matchPattern(_string.$13) case var $1?) {
            return [$0, $1];
          }
        }
      }
    }
  };

  /// `fragment69`
  late final f2z = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$14) case (var $0 && null)) {
        this.pos = mark;
        if (pos < buffer.length) {
          if (buffer[pos] case var $1) {
            pos++;
            return [$0, $1];
          }
        }
      }
    }
  };

  /// `fragment70`
  late final f30 = () {
    if (this.pos case var mark) {
      if (this.f2z() case var _0) {
        if ([if (_0 case var _0?) _0] case (var $0 && var _loop1)) {
          if (_loop1.isNotEmpty) {
            for (;;) {
              if (this.pos case var mark) {
                if (this.f2z() case var _0?) {
                  _loop1.add(_0);
                  continue;
                }
                this.pos = mark;
                break;
              }
            }
          } else {
            this.pos = mark;
          }
          if (this.matchPattern(_string.$14) case var $1?) {
            return [$0, $1];
          }
        }
      }
    }
  };

  /// `fragment71`
  late final f31 = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$15) case (var $0 && null)) {
        this.pos = mark;
        if (pos < buffer.length) {
          if (buffer[pos] case var $1) {
            pos++;
            return [$0, $1];
          }
        }
      }
    }
  };

  /// `fragment72`
  late final f32 = () {
    if (this.pos case var mark) {
      if (this.f31() case var _0) {
        if ([if (_0 case var _0?) _0] case (var $0 && var _loop1)) {
          if (_loop1.isNotEmpty) {
            for (;;) {
              if (this.pos case var mark) {
                if (this.f31() case var _0?) {
                  _loop1.add(_0);
                  continue;
                }
                this.pos = mark;
                break;
              }
            }
          } else {
            this.pos = mark;
          }
          if (this.matchPattern(_string.$15) case var $1?) {
            return [$0, $1];
          }
        }
      }
    }
  };

  /// `fragment73`
  late final f33 = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$1) case var $0?) {
        if (pos < buffer.length) {
          if (buffer[pos] case var $1) {
            pos++;
            return [$0, $1];
          }
        }
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.matchPattern(_string.$11) case (var $0 && null)) {
          this.pos = mark;
          if (pos < buffer.length) {
            if (buffer[pos] case var $1) {
              pos++;
              return [$0, $1];
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
        if ([if (_0 case var _0?) _0] case (var $0 && var _loop1)) {
          if (_loop1.isNotEmpty) {
            for (;;) {
              if (this.pos case var mark) {
                if (this.f33() case var _0?) {
                  _loop1.add(_0);
                  continue;
                }
                this.pos = mark;
                break;
              }
            }
          } else {
            this.pos = mark;
          }
          if (this.matchPattern(_string.$11) case var $1?) {
            return [$0, $1];
          }
        }
      }
    }
  };

  /// `fragment75`
  late final f35 = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$1) case var $0?) {
        if (pos < buffer.length) {
          if (buffer[pos] case var $1) {
            pos++;
            return [$0, $1];
          }
        }
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.matchPattern(_string.$13) case (var $0 && null)) {
          this.pos = mark;
          if (pos < buffer.length) {
            if (buffer[pos] case var $1) {
              pos++;
              return [$0, $1];
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
        if ([if (_0 case var _0?) _0] case (var $0 && var _loop1)) {
          if (_loop1.isNotEmpty) {
            for (;;) {
              if (this.pos case var mark) {
                if (this.f35() case var _0?) {
                  _loop1.add(_0);
                  continue;
                }
                this.pos = mark;
                break;
              }
            }
          } else {
            this.pos = mark;
          }
          if (this.matchPattern(_string.$13) case var $1?) {
            return [$0, $1];
          }
        }
      }
    }
  };

  /// `fragment77`
  late final f37 = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$1) case var $0?) {
        if (pos < buffer.length) {
          if (buffer[pos] case var $1) {
            pos++;
            return [$0, $1];
          }
        }
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.matchPattern(_string.$14) case (var $0 && null)) {
          this.pos = mark;
          if (pos < buffer.length) {
            if (buffer[pos] case var $1) {
              pos++;
              return [$0, $1];
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
        if ([if (_0 case var _0?) _0] case (var $0 && var _loop1)) {
          if (_loop1.isNotEmpty) {
            for (;;) {
              if (this.pos case var mark) {
                if (this.f37() case var _0?) {
                  _loop1.add(_0);
                  continue;
                }
                this.pos = mark;
                break;
              }
            }
          } else {
            this.pos = mark;
          }
          if (this.matchPattern(_string.$14) case var $1?) {
            return [$0, $1];
          }
        }
      }
    }
  };

  /// `fragment79`
  late final f39 = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$1) case var $0?) {
        if (pos < buffer.length) {
          if (buffer[pos] case var $1) {
            pos++;
            return [$0, $1];
          }
        }
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.matchPattern(_string.$15) case (var $0 && null)) {
          this.pos = mark;
          if (pos < buffer.length) {
            if (buffer[pos] case var $1) {
              pos++;
              return [$0, $1];
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
        if ([if (_0 case var _0?) _0] case (var $0 && var _loop1)) {
          if (_loop1.isNotEmpty) {
            for (;;) {
              if (this.pos case var mark) {
                if (this.f39() case var _0?) {
                  _loop1.add(_0);
                  continue;
                }
                this.pos = mark;
                break;
              }
            }
          } else {
            this.pos = mark;
          }
          if (this.matchPattern(_string.$15) case var $1?) {
            return [$0, $1];
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
          return [$0, $1];
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$41) case var $0?) {
        if (this.f2y() case var $1?) {
          return [$0, $1];
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$42) case var $0?) {
        if (this.f30() case var $1?) {
          return [$0, $1];
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$43) case var $0?) {
        if (this.f32() case var $1?) {
          return [$0, $1];
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$11) case var $0?) {
        if (this.f34() case var $1?) {
          return [$0, $1];
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$13) case var $0?) {
        if (this.f36() case var $1?) {
          return [$0, $1];
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$14) case var $0?) {
        if (this.f38() case var $1?) {
          return [$0, $1];
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$15) case var $0?) {
        if (this.f3a() case var $1?) {
          return [$0, $1];
        }
      }
    }
  };

  /// `fragment82`
  late final f3c = () {
    if (this.f3b() case var $0?) {
      if (this.ft() case var $1) {
        return [$0, $1];
      }
    }
  };

  /// `fragment83`
  late final f3d = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$3) case (var $0 && null)) {
        this.pos = mark;
        if (pos < buffer.length) {
          if (buffer[pos] case var $1) {
            pos++;
            return [$0, $1];
          }
        }
      }
    }
  };

  /// `fragment84`
  late final f3e = () {
    if (this.pos case var mark) {
      if (this.f3d() case var _0) {
        if ([if (_0 case var _0?) _0] case (var $0 && var _loop1)) {
          if (_loop1.isNotEmpty) {
            for (;;) {
              if (this.pos case var mark) {
                if (this.f3d() case var _0?) {
                  _loop1.add(_0);
                  continue;
                }
                this.pos = mark;
                break;
              }
            }
          } else {
            this.pos = mark;
          }
          if (this.matchPattern(_string.$3) case var $1?) {
            return [$0, $1];
          }
        }
      }
    }
  };

  /// `fragment85`
  late final f3f = () {
    if (this.apply(this.rg)! case var $0) {
      if (this.matchPattern(_string.$16) case var $1?) {
        return [$0, $1];
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
          return [$0, $1];
        }
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.matchTrie(_trie.$1) case (var $0 && null)) {
          this.pos = mark;
          if (pos < buffer.length) {
            if (buffer[pos] case var $1) {
              pos++;
              return [$0, $1];
            }
          }
        }
      }
    }
  };

  /// `fragment87`
  late final f3h = () {
    if (this.fv() case var $?) {
      return $;
    }
  };

  /// `fragment88`
  late final f3i = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$17) case var $0?) {
        if (this.apply(this.rj)! case var $1) {
          if (this.matchPattern(_string.$16) case var $2?) {
            return [$0, $1, $2];
          }
        }
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.matchTrie(_trie.$1) case (var $0 && null)) {
          this.pos = mark;
          if (pos < buffer.length) {
            if (buffer[pos] case var $1) {
              pos++;
              return [$0, $1];
            }
          }
        }
      }
    }
  };

  /// `fragment89`
  late final f3j = () {
    if (this.apply(this.rl) case var $0?) {
      if (this.ft() case var $1) {
        return [$0, $1];
      }
    }
  };

  /// `fragment90`
  late final f3k = () {
    if (this.f7() case var $0?) {
      if (this.fj() case var $1?) {
        return [$0, $1];
      }
    }
  };

  /// `fragment91`
  late final f3l = () {
    if (this.fk() case var $0?) {
      if (this.f3k() case var $1?) {
        return [$0, $1];
      }
    }
  };

  /// `fragment92`
  late final f3m = () {
    if (this.f7() case var $0?) {
      if (this.fj() case var $1?) {
        return [$0, $1];
      }
    }
  };

  /// `fragment93`
  late final f3n = () {
    if (this.fk() case var $0?) {
      if (this.f3m() case var $1?) {
        return [$0, $1];
      }
    }
  };

  /// `fragment94`
  late final f3o = () {
    if (this.fq() case var $0?) {
      if (this.fk() case var $1?) {
        if (this.f7() case var $2?) {
          if (this.fj() case var $3?) {
            return [$0, $1, $2, $3];
          }
        }
      }
    }
  };

  /// `fragment95`
  late final f3p = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$3) case (var $0 && null)) {
        this.pos = mark;
        if (pos < buffer.length) {
          if (buffer[pos] case var $1) {
            pos++;
            return [$0, $1];
          }
        }
      }
    }
  };

  /// `fragment96`
  late final f3q = () {
    if (this.pos case var mark) {
      if (this.f3p() case var _0) {
        if ([if (_0 case var _0?) _0] case (var $0 && var _loop1)) {
          if (_loop1.isNotEmpty) {
            for (;;) {
              if (this.pos case var mark) {
                if (this.f3p() case var _0?) {
                  _loop1.add(_0);
                  continue;
                }
                this.pos = mark;
                break;
              }
            }
          } else {
            this.pos = mark;
          }
          if (this.matchPattern(_string.$3) case var $1?) {
            return [$0, $1];
          }
        }
      }
    }
  };

  /// `fragment97`
  late final f3r = () {
    if (this.matchPattern(_string.$3) case var $0?) {
      if (this.f3q() case var $1?) {
        return [$0, $1];
      }
    }
  };

  /// `fragment98`
  late final f3s = () {
    if (this.f3r() case var $0?) {
      if (this.ft() case var $1) {
        return [$0, $1];
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
            return [$0, $1];
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
      if (this.f3t() case var $1?) {
        if (this.pos case var mark) {
          if (this.f3u() case (var $2 && null)) {
            this.pos = mark;
            return [$0, $1, $2];
          }
        }
      }
    }
  };

  /// `fragment102`
  late final f3w = () {
    if (this.matchPattern(_string.$47) case var $0?) {
      if (this.ft() case var $1) {
        return [$0, $1];
      }
    }
  };

  /// `fragment103`
  late final f3x = () {
    if (this.matchPattern(_string.$48) case var $0?) {
      if (this.ft() case var $1) {
        return [$0, $1];
      }
    }
  };

  /// `fragment104`
  late final f3y = () {
    if (this.matchPattern(_string.$49) case var $0?) {
      if (this.ft() case var $1) {
        return [$0, $1];
      }
    }
  };

  /// `fragment105`
  late final f3z = () {
    if (this.pos case var mark) {
      if (this.ft() case var $0) {
        if (this.f3w() case var $1?) {
          return [$0, $1];
        }
      }
      this.pos = mark;
      if (this.ft() case var $0) {
        if (this.f3x() case var $1?) {
          return [$0, $1];
        }
      }
      this.pos = mark;
      if (this.ft() case var $0) {
        if (this.f3y() case var $1?) {
          return [$0, $1];
        }
      }
    }
  };

  /// `fragment106`
  late final f40 = () {
    if (this.matchPattern(_string.$50) case var $0?) {
      if (this.ft() case var $1) {
        return [$0, $1];
      }
    }
  };

  /// `fragment107`
  late final f41 = () {
    if (this.ft() case var $0) {
      if (this.f40() case var $1?) {
        return [$0, $1];
      }
    }
  };

  /// `fragment108`
  late final f42 = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$3) case (var $0 && null)) {
        this.pos = mark;
        if (pos < buffer.length) {
          if (buffer[pos] case var $1) {
            pos++;
            return [$0, $1];
          }
        }
      }
    }
  };

  /// `fragment109`
  late final f43 = () {
    if (this.pos case var mark) {
      if (this.f42() case var _0) {
        if ([if (_0 case var _0?) _0] case (var $0 && var _loop1)) {
          if (_loop1.isNotEmpty) {
            for (;;) {
              if (this.pos case var mark) {
                if (this.f42() case var _0?) {
                  _loop1.add(_0);
                  continue;
                }
                this.pos = mark;
                break;
              }
            }
          } else {
            this.pos = mark;
          }
          if (this.matchPattern(_string.$3) case var $1?) {
            return [$0, $1];
          }
        }
      }
    }
  };

  /// `fragment110`
  late final f44 = () {
    if (this.matchPattern(_string.$46) case var $0?) {
      if (this.ft() case var $1) {
        return [$0, $1];
      }
    }
  };

  /// `fragment111`
  late final f45 = () {
    if (this.matchPattern(_string.$16) case var $0?) {
      if (this.ft() case var $1) {
        return [$0, $1];
      }
    }
  };

  /// `fragment112`
  late final f46 = () {
    if (this.matchPattern(_string.$17) case var $0?) {
      if (this.ft() case var $1) {
        return [$0, $1];
      }
    }
  };

  /// `fragment113`
  late final f47 = () {
    if (this.matchPattern(_string.$51) case var $0?) {
      if (this.ft() case var $1) {
        return [$0, $1];
      }
    }
  };

  /// `fragment114`
  late final f48 = () {
    if (this.matchPattern(_string.$52) case var $0?) {
      if (this.ft() case var $1) {
        return [$0, $1];
      }
    }
  };

  /// `fragment115`
  late final f49 = () {
    if (this.matchPattern(_string.$53) case var $0?) {
      if (this.ft() case var $1) {
        return [$0, $1];
      }
    }
  };

  /// `fragment116`
  late final f4a = () {
    if (this.matchPattern(_string.$54) case var $0?) {
      if (this.ft() case var $1) {
        return [$0, $1];
      }
    }
  };

  /// `fragment117`
  late final f4b = () {
    if (this.matchPattern(_string.$55) case var $0?) {
      if (this.ft() case var $1) {
        return [$0, $1];
      }
    }
  };

  /// `fragment118`
  late final f4c = () {
    if (this.matchPattern(_string.$56) case var $0?) {
      if (this.ft() case var $1) {
        return [$0, $1];
      }
    }
  };

  /// `fragment119`
  late final f4d = () {
    if (this.matchPattern(_string.$57) case var $0?) {
      if (this.ft() case var $1) {
        return [$0, $1];
      }
    }
  };

  /// `fragment120`
  late final f4e = () {
    if (this.matchPattern(_string.$45) case var $0?) {
      if (this.ft() case var $1) {
        return [$0, $1];
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
      if (this.matchPattern(_string.$11) case (var $0 && null)) {
        this.pos = mark;
        if (pos < buffer.length) {
          if (buffer[pos] case var $1) {
            pos++;
            return [$0, $1];
          }
        }
      }
    }
  };

  /// `fragment123`
  late final f4h = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$13) case (var $0 && null)) {
        this.pos = mark;
        if (pos < buffer.length) {
          if (buffer[pos] case var $1) {
            pos++;
            return [$0, $1];
          }
        }
      }
    }
  };

  /// `fragment124`
  late final f4i = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$14) case (var $0 && null)) {
        this.pos = mark;
        if (pos < buffer.length) {
          if (buffer[pos] case var $1) {
            pos++;
            return [$0, $1];
          }
        }
      }
    }
  };

  /// `fragment125`
  late final f4j = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$15) case (var $0 && null)) {
        this.pos = mark;
        if (pos < buffer.length) {
          if (buffer[pos] case var $1) {
            pos++;
            return [$0, $1];
          }
        }
      }
    }
  };

  /// `fragment126`
  late final f4k = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$1) case var $0?) {
        if (pos < buffer.length) {
          if (buffer[pos] case var $1) {
            pos++;
            return [$0, $1];
          }
        }
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.matchPattern(_string.$18) case var $0?) {
          this.pos = mark;
          if (this.fw() case var $1?) {
            return [$0, $1];
          }
        }
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.matchPattern(_string.$11) case (var $0 && null)) {
          this.pos = mark;
          if (pos < buffer.length) {
            if (buffer[pos] case var $1) {
              pos++;
              return [$0, $1];
            }
          }
        }
      }
    }
  };

  /// `fragment127`
  late final f4l = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$1) case var $0?) {
        if (pos < buffer.length) {
          if (buffer[pos] case var $1) {
            pos++;
            return [$0, $1];
          }
        }
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.matchPattern(_string.$18) case var $0?) {
          this.pos = mark;
          if (this.fw() case var $1?) {
            return [$0, $1];
          }
        }
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.matchPattern(_string.$13) case (var $0 && null)) {
          this.pos = mark;
          if (pos < buffer.length) {
            if (buffer[pos] case var $1) {
              pos++;
              return [$0, $1];
            }
          }
        }
      }
    }
  };

  /// `fragment128`
  late final f4m = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$1) case var $0?) {
        if (pos < buffer.length) {
          if (buffer[pos] case var $1) {
            pos++;
            return [$0, $1];
          }
        }
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.matchPattern(_string.$18) case var $0?) {
          this.pos = mark;
          if (this.fw() case var $1?) {
            return [$0, $1];
          }
        }
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.matchPattern(_string.$14) case (var $0 && null)) {
          this.pos = mark;
          if (pos < buffer.length) {
            if (buffer[pos] case var $1) {
              pos++;
              return [$0, $1];
            }
          }
        }
      }
    }
  };

  /// `fragment129`
  late final f4n = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$1) case var $0?) {
        if (pos < buffer.length) {
          if (buffer[pos] case var $1) {
            pos++;
            return [$0, $1];
          }
        }
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.matchPattern(_string.$18) case var $0?) {
          this.pos = mark;
          if (this.fw() case var $1?) {
            return [$0, $1];
          }
        }
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.matchPattern(_string.$15) case (var $0 && null)) {
          this.pos = mark;
          if (pos < buffer.length) {
            if (buffer[pos] case var $1) {
              pos++;
              return [$0, $1];
            }
          }
        }
      }
    }
  };

  /// `fragment130`
  late final f4o = () {
    if (this.f8() case var _0?) {
      if (<Object>[_0] case var _loop2) {
        for (;;) {
          if (this.pos case var mark) {
            if (this.fs() case var _1?) {
              if (this.f8() case var _0?) {
                _loop2.addAll([_1, _0]);
                continue;
              }
            }
            this.pos = mark;
            break;
          }
        }
        return _loop2;
      }
    }
  };

  /// `fragment131`
  late final f4p = () {
    if (this.matchPattern(_string.$58) case var $0?) {
      if (this.ft() case var $1) {
        return [$0, $1];
      }
    }
  };

  /// `fragment132`
  late final f4q = () {
    if (this.ft() case var $0) {
      if (this.f4p() case var $1?) {
        return [$0, $1];
      }
    }
  };

  /// `fragment133`
  late final f4r = () {
    if (this.matchPattern(_string.$59) case var $0?) {
      if (this.ft() case var $1) {
        return [$0, $1];
      }
    }
  };

  /// `fragment134`
  late final f4s = () {
    if (this.ft() case var $0) {
      if (this.f4r() case var $1?) {
        return [$0, $1];
      }
    }
  };

  /// `global::document`
  Object? r0() {
    if (this.pos case var $0 when this.pos <= 0) {
      if (this.apply(this.r1) case var $1) {
        if (this.apply(this.r2) case var _0?) {
          if (<Object>[_0] case (var $2 && var _loop2)) {
            for (;;) {
              if (this.pos case var mark) {
                if (this.ft() case var _1) {
                  if (this.apply(this.r2) case var _0?) {
                    _loop2.addAll([_1, _0]);
                    continue;
                  }
                }
                this.pos = mark;
                break;
              }
            }
            if (this.ft() case var $3) {
              if (this.pos case var $4 when this.pos >= this.buffer.length) {
                return ("global::document", [$0, $1, $2, $3, $4]);
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
        if (this.apply(this.rf)! case var $2) {
          if (this.ft() case var $3) {
            if (this.fj() case var $4?) {
              return ("global::preamble", [$0, $1, $2, $3, $4]);
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
        return ("global::statement", $);
      }
      this.pos = mark;
      if (this.apply(this.r4) case var $?) {
        return ("global::statement", $);
      }
    }
  }

  /// `global::namespace`
  Object? r3() {
    if (this.pos case var mark) {
      if (this.fc() case var $0?) {
        if (this.f8() case var $1) {
          if (this.fk() case var $2?) {
            if (this.apply(this.r2) case var _0?) {
              if (<Object>[_0] case (var $3 && var _loop2)) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.ft() case var _1) {
                      if (this.apply(this.r2) case var _0?) {
                        _loop2.addAll([_1, _0]);
                        continue;
                      }
                    }
                    this.pos = mark;
                    break;
                  }
                }
                if (this.fj() case var $4?) {
                  return ("global::namespace", [$0, $1, $2, $3, $4]);
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.fb() case var $0?) {
        if (this.f8() case var $1) {
          if (this.fk() case var $2?) {
            if (this.apply(this.r2) case var _3?) {
              if (<Object>[_3] case (var $3 && var _loop5)) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.ft() case var _4) {
                      if (this.apply(this.r2) case var _3?) {
                        _loop5.addAll([_4, _3]);
                        continue;
                      }
                    }
                    this.pos = mark;
                    break;
                  }
                }
                if (this.fj() case var $4?) {
                  return ("global::namespace", [$0, $1, $2, $3, $4]);
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.fd() case var $0?) {
        if (this.f8() case var $1) {
          if (this.fk() case var $2?) {
            if (this.apply(this.r2) case var _6?) {
              if (<Object>[_6] case (var $3 && var _loop8)) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.ft() case var _7) {
                      if (this.apply(this.r2) case var _6?) {
                        _loop8.addAll([_7, _6]);
                        continue;
                      }
                    }
                    this.pos = mark;
                    break;
                  }
                }
                if (this.fj() case var $4?) {
                  return ("global::namespace", [$0, $1, $2, $3, $4]);
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.f8() case var $0) {
        if (this.fk() case var $1?) {
          if (this.apply(this.r2) case var _9?) {
            if (<Object>[_9] case (var $2 && var _loop11)) {
              for (;;) {
                if (this.pos case var mark) {
                  if (this.ft() case var _10) {
                    if (this.apply(this.r2) case var _9?) {
                      _loop11.addAll([_10, _9]);
                      continue;
                    }
                  }
                  this.pos = mark;
                  break;
                }
              }
              if (this.fj() case var $3?) {
                return ("global::namespace", [$0, $1, $2, $3]);
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
      if (this.fa() case var $0) {
        if (this.fe() case var $1) {
          if (this.f3() case var $2?) {
            if (this.f4() case var $3?) {
              return ("global::declaration", [$0, $1, $2, $3]);
            }
          }
        }
      }
      this.pos = mark;
      if (this.fa() case var $0) {
        if (this.f0() case var $1?) {
          if (this.f3() case var $2?) {
            if (this.f4() case var $3?) {
              return ("global::declaration", [$0, $1, $2, $3]);
            }
          }
        }
      }
      this.pos = mark;
      if (this.fa() case var $0) {
        if (this.fe() case var $1) {
          if (this.f3() case var $2?) {
            if (this.f13() case var $3?) {
              if (this.f0() case var $4?) {
                if (this.f4() case var $5?) {
                  return ("global::declaration", [$0, $1, $2, $3, $4, $5]);
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
        if (<Object>[_0] case (var $1 && var _loop2)) {
          for (;;) {
            if (this.pos case var mark) {
              if (this.fr() case var _1?) {
                if (this.apply(this.r6) case var _0?) {
                  _loop2.addAll([_1, _0]);
                  continue;
                }
              }
              this.pos = mark;
              break;
            }
          }
          return ("global::choice", [$0, $1]);
        }
      }
    }
  }

  /// `global::acted`
  Object? r6() {
    if (this.pos case var mark) {
      if (this.apply(this.r7) case var $0?) {
        if (this.f15() case var $1?) {
          if (this.ft() case var $2) {
            if (this.f6() case var $3?) {
              if (this.ft() case var $4) {
                return ("global::acted", [$0, $1, $2, $3, $4]);
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.r7) case var $0?) {
        if (this.fk() case var $1?) {
          if (this.ft() case var $2) {
            if (this.apply(this.rf)! case var $3) {
              if (this.ft() case var $4) {
                if (this.fj() case var $5?) {
                  return ("global::acted", [$0, $1, $2, $3, $4, $5]);
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.r7) case var $0?) {
        if (this.fm() case var $1?) {
          if (this.fl() case var $2?) {
            if (this.fk() case var $3?) {
              if (this.ft() case var $4) {
                if (this.apply(this.rf)! case var $5) {
                  if (this.ft() case var $6) {
                    if (this.fj() case var $7?) {
                      return ("global::acted", [$0, $1, $2, $3, $4, $5, $6, $7]);
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
        return ("global::acted", $);
      }
    }
  }

  /// `global::sequence`
  Object? r7() {
    if (this.apply(this.r8) case var _0?) {
      if (<Object>[_0] case (var $0 && var _loop2)) {
        for (;;) {
          if (this.pos case var mark) {
            if (this.ft() case var _1) {
              if (this.apply(this.r8) case var _0?) {
                _loop2.addAll([_1, _0]);
                continue;
              }
            }
            this.pos = mark;
            break;
          }
        }
        if (this.f18() case var $1) {
          return ("global::sequence", [$0, $1]);
        }
      }
    }
  }

  /// `global::dropped`
  Object? r8() {
    if (this.pos case var mark) {
      if (this.apply(this.r8) case var $0?) {
        if (this.f1a() case var $1?) {
          if (this.apply(this.ra) case var $2?) {
            return ("global::dropped", [$0, $1, $2]);
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.ra) case var $0?) {
        if (this.f1c() case var $1?) {
          if (this.apply(this.r8) case var $2?) {
            return ("global::dropped", [$0, $1, $2]);
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.r9) case var $?) {
        return ("global::dropped", $);
      }
    }
  }

  /// `global::labeled`
  Object? r9() {
    if (this.pos case var mark) {
      if (this.f8() case var $0?) {
        if (this.matchPattern(_string.$19) case var $1?) {
          if (this.ft() case var $2) {
            if (this.apply(this.ra) case var $3?) {
              return ("global::labeled", [$0, $1, $2, $3]);
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$19) case var $0?) {
        if (this.f2() case var $1?) {
          if (this.fn() case var $2?) {
            return ("global::labeled", [$0, $1, $2]);
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$19) case var $0?) {
        if (this.f2() case var $1?) {
          if (this.fo() case var $2?) {
            return ("global::labeled", [$0, $1, $2]);
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$19) case var $0?) {
        if (this.f2() case var $1?) {
          if (this.fp() case var $2?) {
            return ("global::labeled", [$0, $1, $2]);
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$19) case var $0?) {
        if (this.f2() case var $1?) {
          return ("global::labeled", [$0, $1]);
        }
      }
      this.pos = mark;
      if (this.apply(this.ra) case var $?) {
        return ("global::labeled", $);
      }
    }
  }

  /// `global::special`
  Object? ra() {
    if (this.pos case var mark) {
      if (this.apply(this.rd) case var $0?) {
        if (this.fi() case var $1?) {
          if (this.apply(this.rd) case var $2?) {
            if (this.fp() case var $3?) {
              return ("global::special", [$0, $1, $2, $3]);
            }
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.rd) case var $0?) {
        if (this.fi() case var $1?) {
          if (this.apply(this.rd) case var $2?) {
            if (this.fo() case var $3?) {
              return ("global::special", [$0, $1, $2, $3]);
            }
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.rb) case var $?) {
        return ("global::special", $);
      }
    }
  }

  /// `global::postfix`
  Object? rb() {
    if (this.pos case var mark) {
      if (this.apply(this.rb) case var $0?) {
        if (this.fn() case var $1?) {
          return ("global::postfix", [$0, $1]);
        }
      }
      this.pos = mark;
      if (this.apply(this.rb) case var $0?) {
        if (this.fo() case var $1?) {
          return ("global::postfix", [$0, $1]);
        }
      }
      this.pos = mark;
      if (this.apply(this.rb) case var $0?) {
        if (this.fp() case var $1?) {
          return ("global::postfix", [$0, $1]);
        }
      }
      this.pos = mark;
      if (this.apply(this.rc) case var $?) {
        return ("global::postfix", $);
      }
    }
  }

  /// `global::prefix`
  Object? rc() {
    if (this.pos case var mark) {
      if (this.f9() case var $0?) {
        if (this.fi() case var $1?) {
          if (this.f9() case var $2) {
            if (this.apply(this.re) case var $3?) {
              return ("global::prefix", [$0, $1, $2, $3]);
            }
          }
        }
      }
      this.pos = mark;
      if (this.f9() case var $0?) {
        if (this.apply(this.re) case var $1?) {
          return ("global::prefix", [$0, $1]);
        }
      }
      this.pos = mark;
      if (this.f1e() case var $0?) {
        if (this.apply(this.rc) case var $1?) {
          return ("global::prefix", [$0, $1]);
        }
      }
      this.pos = mark;
      if (this.f1g() case var $0?) {
        if (this.apply(this.rc) case var $1?) {
          return ("global::prefix", [$0, $1]);
        }
      }
      this.pos = mark;
      if (this.f1i() case var $0?) {
        if (this.apply(this.rc) case var $1?) {
          return ("global::prefix", [$0, $1]);
        }
      }
      this.pos = mark;
      if (this.apply(this.rd) case var $?) {
        return ("global::prefix", $);
      }
    }
  }

  /// `global::callLike`
  Object? rd() {
    if (this.pos case var mark) {
      if (this.apply(this.rd) case var $0?) {
        if (this.fs() case var $1?) {
          if (this.fg() case var $2?) {
            if (this.fm() case var $3?) {
              if (this.fl() case var $4?) {
                return ("global::callLike", [$0, $1, $2, $3, $4]);
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.rd) case var $0?) {
        if (this.fs() case var $1?) {
          if (this.ff() case var $2?) {
            if (this.fm() case var $3?) {
              if (this.f9() case var $4?) {
                if (this.fq() case var $5?) {
                  if (this.f9() case var $6?) {
                    if (this.fl() case var $7?) {
                      return ("global::callLike", [$0, $1, $2, $3, $4, $5, $6, $7]);
                    }
                  }
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.rd) case var $0?) {
        if (this.fs() case var $1?) {
          if (this.ff() case var $2?) {
            if (this.fm() case var $3?) {
              if (this.f9() case var $4?) {
                if (this.fl() case var $5?) {
                  return ("global::callLike", [$0, $1, $2, $3, $4, $5]);
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.rd) case var $0?) {
        if (this.fs() case var $1?) {
          if (this.ff() case var $2?) {
            if (this.ft() case var $3) {
              if (this.f9() case var $4?) {
                if (this.ft() case var $5) {
                  return ("global::callLike", [$0, $1, $2, $3, $4, $5]);
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.rd) case var $0?) {
        if (this.fs() case var $1?) {
          if (this.fh() case var $2?) {
            if (this.fm() case var $3?) {
              if (this.apply(this.r5) case var $4?) {
                if (this.fl() case var $5?) {
                  if (this.fp() case var $6?) {
                    if (this.fn() case var $7?) {
                      return ("global::callLike", [$0, $1, $2, $3, $4, $5, $6, $7]);
                    }
                  }
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.rd) case var $0?) {
        if (this.fs() case var $1?) {
          if (this.fh() case var $2?) {
            if (this.fm() case var $3?) {
              if (this.apply(this.r5) case var $4?) {
                if (this.fl() case var $5?) {
                  if (this.fo() case var $6?) {
                    if (this.fn() case var $7?) {
                      return ("global::callLike", [$0, $1, $2, $3, $4, $5, $6, $7]);
                    }
                  }
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.rd) case var $0?) {
        if (this.fs() case var $1?) {
          if (this.fh() case var $2?) {
            if (this.fm() case var $3?) {
              if (this.apply(this.r5) case var $4?) {
                if (this.fl() case var $5?) {
                  if (this.fp() case var $6?) {
                    return ("global::callLike", [$0, $1, $2, $3, $4, $5, $6]);
                  }
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.rd) case var $0?) {
        if (this.fs() case var $1?) {
          if (this.fh() case var $2?) {
            if (this.fm() case var $3?) {
              if (this.apply(this.r5) case var $4?) {
                if (this.fl() case var $5?) {
                  if (this.fo() case var $6?) {
                    return ("global::callLike", [$0, $1, $2, $3, $4, $5, $6]);
                  }
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.rd) case var $0?) {
        if (this.fs() case var $1?) {
          if (this.fh() case var $2?) {
            if (this.fm() case var $3?) {
              if (this.apply(this.r5) case var $4?) {
                if (this.fl() case var $5?) {
                  return ("global::callLike", [$0, $1, $2, $3, $4, $5]);
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.rd) case var $0?) {
        if (this.fs() case var $1?) {
          if (this.fh() case var $2?) {
            if (this.ft() case var $3) {
              if (this.apply(this.re) case var $4?) {
                if (this.ft() case var $5) {
                  return ("global::callLike", [$0, $1, $2, $3, $4, $5]);
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.re) case var $?) {
        return ("global::callLike", $);
      }
    }
  }

  /// `global::atom`
  Object? re() {
    if (this.pos case var mark) {
      if (this.fm() case var $0?) {
        if (this.f1j() case var $1?) {
          return ("global::atom", [$0, $1]);
        }
      }
      this.pos = mark;
      if (this.ft() case var $0) {
        if (this.f1k() case var $1?) {
          return ("global::atom", [$0, $1]);
        }
      }
      this.pos = mark;
      if (this.ft() case var $0) {
        if (this.f1l() case var $1?) {
          return ("global::atom", [$0, $1]);
        }
      }
      this.pos = mark;
      if (this.fs() case var $?) {
        return ("global::atom", $);
      }
      this.pos = mark;
      if (this.ft() case var $0) {
        if (this.f1m() case var $1?) {
          return ("global::atom", [$0, $1]);
        }
      }
      this.pos = mark;
      if (this.ft() case var $0) {
        if (this.f1o() case var $1?) {
          return ("global::atom", [$0, $1]);
        }
      }
      this.pos = mark;
      if (this.ft() case var $0) {
        if (this.f1q() case var $1?) {
          return ("global::atom", [$0, $1]);
        }
      }
      this.pos = mark;
      if (this.ft() case var $0) {
        if (this.f1s() case var $1?) {
          return ("global::atom", [$0, $1]);
        }
      }
      this.pos = mark;
      if (this.ft() case var $0) {
        if (this.f1u() case var $1?) {
          return ("global::atom", [$0, $1]);
        }
      }
      this.pos = mark;
      if (this.ft() case var $0) {
        if (this.f1w() case var $1?) {
          return ("global::atom", [$0, $1]);
        }
      }
      this.pos = mark;
      if (this.ft() case var $0) {
        if (this.f1y() case var $1?) {
          return ("global::atom", [$0, $1]);
        }
      }
      this.pos = mark;
      if (this.ft() case var $0) {
        if (this.f20() case var $1?) {
          return ("global::atom", [$0, $1]);
        }
      }
      this.pos = mark;
      if (this.ft() case var $0) {
        if (this.f22() case var $1?) {
          return ("global::atom", [$0, $1]);
        }
      }
      this.pos = mark;
      if (this.ft() case var $0) {
        if (this.f24() case var $1?) {
          return ("global::atom", [$0, $1]);
        }
      }
      this.pos = mark;
      if (this.ft() case var $0) {
        if (this.f26() case var $1?) {
          return ("global::atom", [$0, $1]);
        }
      }
      this.pos = mark;
      if (this.ft() case var $0) {
        if (this.f28() case var $1?) {
          return ("global::atom", [$0, $1]);
        }
      }
      this.pos = mark;
      if (this.ft() case var $0) {
        if (this.f2a() case var $1?) {
          return ("global::atom", [$0, $1]);
        }
      }
      this.pos = mark;
      if (this.ft() case var $0) {
        if (this.f2r() case var $1?) {
          return ("global::atom", [$0, $1]);
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$39) case var $0?) {
        if (this.f2u() case var $1?) {
          return ("global::atom", [$0, $1]);
        }
      }
      this.pos = mark;
      if (this.ft() case var $0) {
        if (this.f3c() case var $1?) {
          return ("global::atom", [$0, $1]);
        }
      }
      this.pos = mark;
      if (this.f3() case var $?) {
        return ("global::atom", $);
      }
    }
  }

  /// `global::code::curly`
  Object rf() {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$3) case var $0?) {
        if (this.f3e() case var $1?) {
          return ("global::code::curly", [$0, $1]);
        }
      }
      this.pos = mark;
      if (this.apply(this.rg)! case var $) {
        return ("global::code::curly", $);
      }
    }
  }

  /// `global::code::curly::balanced`
  Object rg() {
    if (this.pos case var mark) {
      if (this.f3g() case var _0) {
        if ([if (_0 case var _0?) _0] case var _loop1) {
          if (_loop1.isNotEmpty) {
            for (;;) {
              if (this.pos case var mark) {
                if (this.f3g() case var _0?) {
                  _loop1.add(_0);
                  continue;
                }
                this.pos = mark;
                break;
              }
            }
          } else {
            this.pos = mark;
          }
          return ("global::code::curly::balanced", _loop1);
        }
      }
    }
  }

  /// `global::dart::literal::string`
  Object? rh() {
    if (this.f3h() case var _0?) {
      if (<Object>[_0] case var _loop2) {
        for (;;) {
          if (this.pos case var mark) {
            if (this.ft() case var _1) {
              if (this.f3h() case var _0?) {
                _loop2.addAll([_1, _0]);
                continue;
              }
            }
            this.pos = mark;
            break;
          }
        }
        return ("global::dart::literal::string", _loop2);
      }
    }
  }

  /// `global::dart::literal::identifier`
  Object? ri() {
    if (this.f8() case var $?) {
      return ("global::dart::literal::identifier", $);
    }
  }

  /// `global::dart::literal::string::balanced`
  Object rj() {
    if (this.pos case var mark) {
      if (this.f3i() case var _0) {
        if ([if (_0 case var _0?) _0] case var _loop1) {
          if (_loop1.isNotEmpty) {
            for (;;) {
              if (this.pos case var mark) {
                if (this.f3i() case var _0?) {
                  _loop1.add(_0);
                  continue;
                }
                this.pos = mark;
                break;
              }
            }
          } else {
            this.pos = mark;
          }
          return ("global::dart::literal::string::balanced", _loop1);
        }
      }
    }
  }

  /// `global::dart::type::main`
  Object? rk() {
    if (this.ft() case var $0) {
      if (this.f3j() case var $1?) {
        return ("global::dart::type::main", [$0, $1]);
      }
    }
  }

  /// `global::dart::type::nullable`
  Object? rl() {
    if (this.apply(this.rm) case var $0?) {
      if (this.fn() case var $1) {
        return ("global::dart::type::nullable", [$0, $1]);
      }
    }
  }

  /// `global::dart::type::nonNullable`
  Object? rm() {
    if (this.pos case var mark) {
      if (this.fx() case var $?) {
        return ("global::dart::type::nonNullable", $);
      }
      this.pos = mark;
      if (this.apply(this.rn) case var $?) {
        return ("global::dart::type::nonNullable", $);
      }
      this.pos = mark;
      if (this.f8() case var _0?) {
        if (<Object>[_0] case var _loop2) {
          for (;;) {
            if (this.pos case var mark) {
              if (this.fs() case var _1?) {
                if (this.f8() case var _0?) {
                  _loop2.addAll([_1, _0]);
                  continue;
                }
              }
              this.pos = mark;
              break;
            }
          }
          return ("global::dart::type::nonNullable", _loop2);
        }
      }
    }
  }

  /// `global::dart::type::record`
  Object? rn() {
    if (this.pos case var mark) {
      if (this.fm() case var $0?) {
        if (this.f3l() case var $1) {
          if (this.fl() case var $2?) {
            return ("global::dart::type::record", [$0, $1, $2]);
          }
        }
      }
      this.pos = mark;
      if (this.fm() case var $0?) {
        if (this.fz() case var $1?) {
          if (this.fq() case var $2?) {
            if (this.f3n() case var $3) {
              if (this.fl() case var $4?) {
                return ("global::dart::type::record", [$0, $1, $2, $3, $4]);
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
              return ("global::dart::type::record", [$0, $1, $2, $3]);
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
