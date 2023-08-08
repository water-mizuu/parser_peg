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
      if (this.fv() case var $0) {
        if (this.f2e() case var $1?) {
          if (this.fv() case var $2) {
            return ("global::type", [$0, $1, $2]);
          }
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
      if (this.f2h() case var _0) {
        if ([if (_0 case var _0?) _0] case var _loop2) {
          if (_loop2.isNotEmpty) {
            for (;;) {
              if (this.pos case var mark) {
                if (this.f2h() case var _0?) {
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
          return ("global::namespaceReference", _loop2);
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
    if (this.f2i() case var $0?) {
      if (this.apply(this.r5) case (var $1 && var choice)?) {
        if (this.f2j() case var $2?) {
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
      if (this.pos case var mark) {
        if (this.f2k() case var _0) {
          if ([if (_0 case var _0?) _0] case (var $1 && var _loop2)) {
            if (_loop2.isNotEmpty) {
              for (;;) {
                if (this.pos case var mark) {
                  if (this.f2k() case var _0?) {
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
            if (this.matchPattern(_string.$3) case var $2?) {
              return ("global::literal::raw", [$0, $1, $2]);
            }
          }
        }
      }
    }
  }

  /// `global::dart::type::fields::named`
  Object? f7() {
    if (this.f11() case var _0?) {
      if (<Object>[_0] case var _loop3) {
        for (;;) {
          if (this.pos case var mark) {
            if (this.fs() case var _1?) {
              if (this.f11() case var _0?) {
                _loop3.addAll([_1, _0]);
                continue;
              }
            }
            this.pos = mark;
            break;
          }
        }
        return ("global::dart::type::fields::named", _loop3);
      }
    }
  }

  /// `global::identifier`
  Object? f8() {
    if (this.matchRange(_range.$2) case var $0?) {
      if (this.pos case var mark) {
        if (this.matchRange(_range.$1) case var _0) {
          if ([if (_0 case var _0?) _0] case (var $1 && var _loop2)) {
            if (_loop2.isNotEmpty) {
              for (;;) {
                if (this.pos case var mark) {
                  if (this.matchRange(_range.$1) case var _0?) {
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
            return ("global::identifier", [$0, $1]);
          }
        }
      }
    }
  }

  /// `global::number`
  Object? f9() {
    if (matchPattern(_regexp.$1) case var _0?) {
      if ([_0] case var _loop2) {
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
        return ("global::number", _loop2);
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
    if (this.fv() case var $0) {
      if (this.matchPattern(_string.$4) case var $1?) {
        if (this.fv() case var $2) {
          return ("global::kw::decorator::rule", [$0, $1, $2]);
        }
      }
    }
  }

  /// `global::kw::decorator::fragment`
  Object? fc() {
    if (this.fv() case var $0) {
      if (this.matchPattern(_string.$5) case var $1?) {
        if (this.fv() case var $2) {
          return ("global::kw::decorator::fragment", [$0, $1, $2]);
        }
      }
    }
  }

  /// `global::kw::decorator::inline`
  Object? fd() {
    if (this.fv() case var $0) {
      if (this.matchPattern(_string.$6) case var $1?) {
        if (this.fv() case var $2) {
          return ("global::kw::decorator::inline", [$0, $1, $2]);
        }
      }
    }
  }

  /// `global::kw::var`
  Object? fe() {
    if (this.fv() case var $0) {
      if (this.matchPattern(_string.$7) case var $1?) {
        if (this.fv() case var $2) {
          return ("global::kw::var", [$0, $1, $2]);
        }
      }
    }
  }

  /// `global::mac::range`
  Object? ff() {
    if (this.fv() case var $0) {
      if (this.matchPattern(_string.$8) case var $1?) {
        if (this.fv() case var $2) {
          return ("global::mac::range", [$0, $1, $2]);
        }
      }
    }
  }

  /// `global::mac::flat`
  Object? fg() {
    if (this.fv() case var $0) {
      if (this.matchPattern(_string.$9) case var $1?) {
        if (this.fv() case var $2) {
          return ("global::mac::flat", [$0, $1, $2]);
        }
      }
    }
  }

  /// `global::mac::sep`
  Object? fh() {
    if (this.fv() case var $0) {
      if (this.matchPattern(_string.$10) case var $1?) {
        if (this.fv() case var $2) {
          return ("global::mac::sep", [$0, $1, $2]);
        }
      }
    }
  }

  /// `global::..`
  Object? fi() {
    if (this.fv() case var $0) {
      if (this.matchPattern(_string.$11) case var $1?) {
        if (this.fv() case var $2) {
          return ("global::..", [$0, $1, $2]);
        }
      }
    }
  }

  /// `global::~>`
  Object? fj() {
    if (this.fv() case var $0) {
      if (this.matchPattern(_string.$12) case var $1?) {
        if (this.fv() case var $2) {
          return ("global::~>", [$0, $1, $2]);
        }
      }
    }
  }

  /// `global::<~`
  Object? fk() {
    if (this.fv() case var $0) {
      if (this.matchPattern(_string.$13) case var $1?) {
        if (this.fv() case var $2) {
          return ("global::<~", [$0, $1, $2]);
        }
      }
    }
  }

  /// `global::}`
  Object? fl() {
    if (this.fv() case var $0) {
      if (this.matchPattern(_string.$14) case var $1?) {
        if (this.fv() case var $2) {
          return ("global::}", [$0, $1, $2]);
        }
      }
    }
  }

  /// `global::{`
  Object? fm() {
    if (this.fv() case var $0) {
      if (this.matchPattern(_string.$15) case var $1?) {
        if (this.fv() case var $2) {
          return ("global::{", [$0, $1, $2]);
        }
      }
    }
  }

  /// `global::)`
  Object? fn() {
    if (this.fv() case var $0) {
      if (this.matchPattern(_string.$16) case var $1?) {
        if (this.fv() case var $2) {
          return ("global::)", [$0, $1, $2]);
        }
      }
    }
  }

  /// `global::(`
  Object? fo() {
    if (this.fv() case var $0) {
      if (this.matchPattern(_string.$17) case var $1?) {
        if (this.fv() case var $2) {
          return ("global::(", [$0, $1, $2]);
        }
      }
    }
  }

  /// `global::?`
  Object? fp() {
    if (this.fv() case var $0) {
      if (this.matchPattern(_string.$18) case var $1?) {
        if (this.fv() case var $2) {
          return ("global::?", [$0, $1, $2]);
        }
      }
    }
  }

  /// `global::*`
  Object? fq() {
    if (this.fv() case var $0) {
      if (this.matchPattern(_string.$19) case var $1?) {
        if (this.fv() case var $2) {
          return ("global::*", [$0, $1, $2]);
        }
      }
    }
  }

  /// `global::+`
  Object? fr() {
    if (this.fv() case var $0) {
      if (this.matchPattern(_string.$20) case var $1?) {
        if (this.fv() case var $2) {
          return ("global::+", [$0, $1, $2]);
        }
      }
    }
  }

  /// `global::,`
  Object? fs() {
    if (this.fv() case var $0) {
      if (this.matchPattern(_string.$21) case var $1?) {
        if (this.fv() case var $2) {
          return ("global::,", [$0, $1, $2]);
        }
      }
    }
  }

  /// `global::|`
  Object? ft() {
    if (this.fv() case var $0) {
      if (this.matchPattern(_string.$22) case var $1?) {
        if (this.fv() case var $2) {
          return ("global::|", [$0, $1, $2]);
        }
      }
    }
  }

  /// `global::.`
  Object? fu() {
    if (this.fv() case var $0) {
      if (this.matchPattern(_string.$23) case var $1?) {
        if (this.fv() case var $2) {
          return ("global::.", [$0, $1, $2]);
        }
      }
    }
  }

  /// `global::_`
  Object fv() {
    if (this.pos case var mark) {
      if (this.f2l() case var _0) {
        if ([if (_0 case var _0?) _0] case var _loop2) {
          if (_loop2.isNotEmpty) {
            for (;;) {
              if (this.pos case var mark) {
                if (this.f2l() case var _0?) {
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
          return ("global::_", _loop2);
        }
      }
    }
  }

  /// `global::dart::literal::string::body`
  late final fw = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$25) case var $0?) {
        if (this.matchPattern(_string.$24) case var $1?) {
          if (this.pos case var mark) {
            if (this.f2m() case var _0) {
              if ([if (_0 case var _0?) _0] case (var $2 && var _loop2)) {
                if (_loop2.isNotEmpty) {
                  for (;;) {
                    if (this.pos case var mark) {
                      if (this.f2m() case var _0?) {
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
                if (this.matchPattern(_string.$24) case var $3?) {
                  return ("global::dart::literal::string::body", [$0, $1, $2, $3]);
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$25) case var $0?) {
        if (this.matchPattern(_string.$26) case var $1?) {
          if (this.pos case var mark) {
            if (this.f2n() case var _2) {
              if ([if (_2 case var _2?) _2] case (var $2 && var _loop4)) {
                if (_loop4.isNotEmpty) {
                  for (;;) {
                    if (this.pos case var mark) {
                      if (this.f2n() case var _2?) {
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
                if (this.matchPattern(_string.$26) case var $3?) {
                  return ("global::dart::literal::string::body", [$0, $1, $2, $3]);
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$25) case var $0?) {
        if (this.matchPattern(_string.$27) case var $1?) {
          if (this.pos case var mark) {
            if (this.f2o() case var _4) {
              if ([if (_4 case var _4?) _4] case (var $2 && var _loop6)) {
                if (_loop6.isNotEmpty) {
                  for (;;) {
                    if (this.pos case var mark) {
                      if (this.f2o() case var _4?) {
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
                if (this.matchPattern(_string.$27) case var $3?) {
                  return ("global::dart::literal::string::body", [$0, $1, $2, $3]);
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$25) case var $0?) {
        if (this.matchPattern(_string.$28) case var $1?) {
          if (this.pos case var mark) {
            if (this.f2p() case var _6) {
              if ([if (_6 case var _6?) _6] case (var $2 && var _loop8)) {
                if (_loop8.isNotEmpty) {
                  for (;;) {
                    if (this.pos case var mark) {
                      if (this.f2p() case var _6?) {
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
                if (this.matchPattern(_string.$28) case var $3?) {
                  return ("global::dart::literal::string::body", [$0, $1, $2, $3]);
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$24) case var $0?) {
        if (this.pos case var mark) {
          if (this.f2q() case var _8) {
            if ([if (_8 case var _8?) _8] case (var $1 && var _loop10)) {
              if (_loop10.isNotEmpty) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.f2q() case var _8?) {
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
              if (this.matchPattern(_string.$24) case var $2?) {
                return ("global::dart::literal::string::body", [$0, $1, $2]);
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$26) case var $0?) {
        if (this.pos case var mark) {
          if (this.f2r() case var _10) {
            if ([if (_10 case var _10?) _10] case (var $1 && var _loop12)) {
              if (_loop12.isNotEmpty) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.f2r() case var _10?) {
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
              if (this.matchPattern(_string.$26) case var $2?) {
                return ("global::dart::literal::string::body", [$0, $1, $2]);
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$27) case var $0?) {
        if (this.pos case var mark) {
          if (this.f2s() case var _12) {
            if ([if (_12 case var _12?) _12] case (var $1 && var _loop14)) {
              if (_loop14.isNotEmpty) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.f2s() case var _12?) {
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
              if (this.matchPattern(_string.$27) case var $2?) {
                return ("global::dart::literal::string::body", [$0, $1, $2]);
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$28) case var $0?) {
        if (this.pos case var mark) {
          if (this.f2t() case var _14) {
            if ([if (_14 case var _14?) _14] case (var $1 && var _loop16)) {
              if (_loop16.isNotEmpty) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.f2t() case var _14?) {
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
              if (this.matchPattern(_string.$28) case var $2?) {
                return ("global::dart::literal::string::body", [$0, $1, $2]);
              }
            }
          }
        }
      }
    }
  };

  /// `global::dart::literal::string::interpolation`
  late final fx = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$29) case var $0?) {
        if (this.matchPattern(_string.$15) case var $1?) {
          if (this.apply(this.rj)! case var $2) {
            if (this.matchPattern(_string.$14) case var $3?) {
              return ("global::dart::literal::string::interpolation", [$0, $1, $2, $3]);
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$29) case var $0?) {
        if (this.apply(this.ri) case var $1?) {
          return ("global::dart::literal::string::interpolation", [$0, $1]);
        }
      }
    }
  };

  /// `global::dart::type::generic`
  Object? fy() {
    if (this.f2u() case (var $0 && var base)?) {
      if (this.f2v() case var $1?) {
        if (this.fz() case (var $2 && var arguments)?) {
          if (this.f2w() case var $3?) {
            return ("global::dart::type::generic", [$0, $1, $2, $3]);
          }
        }
      }
    }
  }

  /// `global::dart::type::arguments`
  Object? fz() {
    if (this.apply(this.rl) case var _0?) {
      if (<Object>[_0] case var _loop3) {
        for (;;) {
          if (this.pos case var mark) {
            if (this.fs() case var _1?) {
              if (this.apply(this.rl) case var _0?) {
                _loop3.addAll([_1, _0]);
                continue;
              }
            }
            this.pos = mark;
            break;
          }
        }
        return ("global::dart::type::arguments", _loop3);
      }
    }
  }

  /// `global::dart::type::field::positional`
  Object? f10() {
    if (this.apply(this.rl) case var $0?) {
      if (this.fv() case var $1) {
        if (this.f8() case var $2) {
          return ("global::dart::type::field::positional", [$0, $1, $2]);
        }
      }
    }
  }

  /// `global::dart::type::field::named`
  Object? f11() {
    if (this.apply(this.rl) case var $0?) {
      if (this.fv() case var $1) {
        if (this.f8() case var $2?) {
          return ("global::dart::type::field::named", [$0, $1, $2]);
        }
      }
    }
  }

  /// `global::dart::type::fields::positional`
  Object? f12() {
    if (this.f10() case var _0?) {
      if (<Object>[_0] case var _loop3) {
        for (;;) {
          if (this.pos case var mark) {
            if (this.fs() case var _1?) {
              if (this.f10() case var _0?) {
                _loop3.addAll([_1, _0]);
                continue;
              }
            }
            this.pos = mark;
            break;
          }
        }
        return ("global::dart::type::fields::positional", _loop3);
      }
    }
  }

  /// `fragment0`
  late final f13 = () {
    if (this.fv() case var $0) {
      if (this.matchPattern(_string.$30) case var $1?) {
        if (this.fv() case var $2) {
          return ("fragment0", [$0, $1, $2]);
        }
      }
    }
  };

  /// `fragment1`
  late final f14 = () {
    if (this.fv() case var $0) {
      if (this.matchPattern(_string.$31) case var $1?) {
        if (this.fv() case var $2) {
          return ("fragment1", [$0, $1, $2]);
        }
      }
    }
  };

  /// `fragment2`
  late final f15 = () {
    if (this.fv() case var $0) {
      if (this.matchPattern(_string.$32) case var $1?) {
        if (this.fv() case var $2) {
          return ("fragment2", [$0, $1, $2]);
        }
      }
    }
  };

  /// `fragment3`
  late final f16 = () {
    if (this.f15() case var $0?) {
      if (this.f9() case var $1?) {
        return ("fragment3", [$0, $1]);
      }
    }
  };

  /// `fragment4`
  late final f17 = () {
    if (this.fv() case var $0) {
      if (this.matchPattern(_string.$33) case var $1?) {
        if (this.fv() case var $2) {
          return ("fragment4", [$0, $1, $2]);
        }
      }
    }
  };

  /// `fragment5`
  late final f18 = () {
    if (this.fv() case var $0) {
      if (this.matchPattern(_string.$34) case var $1?) {
        if (this.fv() case var $2) {
          return ("fragment5", [$0, $1, $2]);
        }
      }
    }
  };

  /// `fragment6`
  late final f19 = () {
    if (this.fv() case var $0) {
      if (this.matchPattern(_string.$35) case var $1?) {
        if (this.fv() case var $2) {
          return ("fragment6", [$0, $1, $2]);
        }
      }
    }
  };

  /// `fragment7`
  late final f1a = () {
    if (this.matchPattern(_string.$1) case var $0?) {
      if (this.matchPattern(_string.$1) case var $1?) {
        return ("fragment7", [$0, $1]);
      }
    }
  };

  /// `fragment8`
  late final f1b = () {
    if (this.matchPattern(_string.$1) case var $0?) {
      if (this.matchPattern(_string.$36) case var $1?) {
        return ("fragment8", [$0, $1]);
      }
    }
  };

  /// `fragment9`
  late final f1c = () {
    if (this.matchPattern(_string.$1) case var $0?) {
      if (this.matchPattern(_string.$37) case var $1?) {
        return ("fragment9", [$0, $1]);
      }
    }
  };

  /// `fragment10`
  late final f1d = () {
    if (this.matchPattern(_string.$1) case var $0?) {
      if (this.matchPattern(_string.$38) case var $1?) {
        return ("fragment10", [$0, $1]);
      }
    }
  };

  /// `fragment11`
  late final f1e = () {
    if (this.matchPattern(_string.$1) case var $0?) {
      if (this.matchPattern(_string.$36) case var $1?) {
        return ("fragment11", [$0, $1]);
      }
    }
  };

  /// `fragment12`
  late final f1f = () {
    if (this.matchPattern(_string.$1) case var $0?) {
      if (this.matchPattern(_string.$37) case var $1?) {
        return ("fragment12", [$0, $1]);
      }
    }
  };

  /// `fragment13`
  late final f1g = () {
    if (this.matchPattern(_string.$1) case var $0?) {
      if (this.matchPattern(_string.$38) case var $1?) {
        return ("fragment13", [$0, $1]);
      }
    }
  };

  /// `fragment14`
  late final f1h = () {
    if (this.matchPattern(_string.$1) case var $0?) {
      if (this.matchPattern(_string.$39) case var $1?) {
        return ("fragment14", [$0, $1]);
      }
    }
  };

  /// `fragment15`
  late final f1i = () {
    if (this.matchPattern(_string.$1) case var $0?) {
      if (this.matchPattern(_string.$40) case var $1?) {
        return ("fragment15", [$0, $1]);
      }
    }
  };

  /// `fragment16`
  late final f1j = () {
    if (this.matchPattern(_string.$1) case var $0?) {
      if (this.matchPattern(_string.$25) case var $1?) {
        return ("fragment16", [$0, $1]);
      }
    }
  };

  /// `fragment17`
  late final f1k = () {
    if (this.matchPattern(_string.$1) case var $0?) {
      if (this.matchPattern(_string.$41) case var $1?) {
        return ("fragment17", [$0, $1]);
      }
    }
  };

  /// `fragment18`
  late final f1l = () {
    if (this.matchPattern(_string.$1) case var $0?) {
      if (this.matchPattern(_string.$42) case var $1?) {
        return ("fragment18", [$0, $1]);
      }
    }
  };

  /// `fragment19`
  late final f1m = () {
    if (this.matchPattern(_string.$1) case var $0?) {
      if (this.matchPattern(_string.$36) case var $1?) {
        return ("fragment19", [$0, $1]);
      }
    }
  };

  /// `fragment20`
  late final f1n = () {
    if (this.matchPattern(_string.$1) case var $0?) {
      if (this.matchPattern(_string.$37) case var $1?) {
        return ("fragment20", [$0, $1]);
      }
    }
  };

  /// `fragment21`
  late final f1o = () {
    if (this.matchPattern(_string.$1) case var $0?) {
      if (this.matchPattern(_string.$38) case var $1?) {
        return ("fragment21", [$0, $1]);
      }
    }
  };

  /// `fragment22`
  late final f1p = () {
    if (this.matchPattern(_string.$1) case var $0?) {
      if (this.matchPattern(_string.$40) case var $1?) {
        return ("fragment22", [$0, $1]);
      }
    }
  };

  /// `fragment23`
  late final f1q = () {
    if (this.matchPattern(_string.$1) case var $0?) {
      if (this.matchPattern(_string.$25) case var $1?) {
        return ("fragment23", [$0, $1]);
      }
    }
  };

  /// `fragment24`
  late final f1r = () {
    if (this.matchPattern(_string.$1) case var $0?) {
      if (this.matchPattern(_string.$39) case var $1?) {
        return ("fragment24", [$0, $1]);
      }
    }
  };

  /// `fragment25`
  late final f1s = () {
    if (this.matchPattern(_string.$1) case var $0?) {
      if (this.matchPattern(_string.$1) case var $1?) {
        return ("fragment25", [$0, $1]);
      }
    }
  };

  /// `fragment26`
  late final f1t = () {
    if (this.pos case var mark) {
      if (this.pos case var mark) {
        if (this.matchPattern(_string.$43) case var $?) {
          return ("fragment26", $);
        }
        this.pos = mark;
        if (this.fv() case var $0) {
          if (this.f1m() case var $1?) {
            if (this.fv() case var $2) {
              return ("fragment26", [$0, $1, $2]);
            }
          }
        }
        this.pos = mark;
        if (this.fv() case var $0) {
          if (this.f1n() case var $1?) {
            if (this.fv() case var $2) {
              return ("fragment26", [$0, $1, $2]);
            }
          }
        }
        this.pos = mark;
        if (this.fv() case var $0) {
          if (this.f1o() case var $1?) {
            if (this.fv() case var $2) {
              return ("fragment26", [$0, $1, $2]);
            }
          }
        }
        this.pos = mark;
        if (this.fv() case var $0) {
          if (this.f1p() case var $1?) {
            if (this.fv() case var $2) {
              return ("fragment26", [$0, $1, $2]);
            }
          }
        }
        this.pos = mark;
        if (this.fv() case var $0) {
          if (this.f1q() case var $1?) {
            if (this.fv() case var $2) {
              return ("fragment26", [$0, $1, $2]);
            }
          }
        }
        this.pos = mark;
        if (this.fv() case var $0) {
          if (this.f1r() case var $1?) {
            if (this.fv() case var $2) {
              return ("fragment26", [$0, $1, $2]);
            }
          }
        }
        this.pos = mark;
        if (this.fv() case var $0) {
          if (this.f1s() case var $1?) {
            if (this.fv() case var $2) {
              return ("fragment26", [$0, $1, $2]);
            }
          }
        }
      }

      this.pos = mark;
      if (this.f5() case (var $0 && var l)?) {
        if (this.matchPattern(_string.$44) case var $1?) {
          if (this.f5() case (var $2 && var r)?) {
            return ("fragment26", [$0, $1, $2]);
          }
        }
      }
      this.pos = mark;
      if (this.f5() case var $?) {
        return ("fragment26", $);
      }
    }
  };

  /// `fragment27`
  late final f1u = () {
    if (this.fv() case var $0) {
      if (this.matchPattern(_string.$45) case var $1?) {
        if (this.f1t() case var _0?) {
          if (<Object>[_0] case (var $2 && var elements && var _loop3)) {
            for (;;) {
              if (this.pos case var mark) {
                if (this.fv() case var _1) {
                  if (this.f1t() case var _0?) {
                    _loop3.addAll([_1, _0]);
                    continue;
                  }
                }
                this.pos = mark;
                break;
              }
            }
            if (this.matchPattern(_string.$2) case var $3?) {
              if (this.fv() case var $4) {
                return ("fragment27", [$0, $1, $2, $3, $4]);
              }
            }
          }
        }
      }
    }
  };

  /// `fragment28`
  late final f1v = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$1) case var $0?) {
        if (pos < buffer.length) {
          if (buffer[pos] case var $1) {
            pos++;
            return ("fragment28", [$0, $1]);
          }
        }
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.matchPattern(_string.$46) case (var $0 && null)) {
          this.pos = mark;
          if (pos < buffer.length) {
            if (buffer[pos] case var $1) {
              pos++;
              return ("fragment28", [$0, $1]);
            }
          }
        }
      }
    }
  };

  /// `fragment29`
  late final f1w = () {
    if (this.f1v() case var _0?) {
      if ([_0] case var _loop2) {
        for (;;) {
          if (this.pos case var mark) {
            if (this.f1v() case var _0?) {
              _loop2.add(_0);
              continue;
            }
            this.pos = mark;
            break;
          }
        }
        return ("fragment29", _loop2);
      }
    }
  };

  /// `fragment30`
  late final f1x = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$24) case (var $0 && null)) {
        this.pos = mark;
        if (pos < buffer.length) {
          if (buffer[pos] case var $1) {
            pos++;
            return ("fragment30", [$0, $1]);
          }
        }
      }
    }
  };

  /// `fragment31`
  late final f1y = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$26) case (var $0 && null)) {
        this.pos = mark;
        if (pos < buffer.length) {
          if (buffer[pos] case var $1) {
            pos++;
            return ("fragment31", [$0, $1]);
          }
        }
      }
    }
  };

  /// `fragment32`
  late final f1z = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$27) case (var $0 && null)) {
        this.pos = mark;
        if (pos < buffer.length) {
          if (buffer[pos] case var $1) {
            pos++;
            return ("fragment32", [$0, $1]);
          }
        }
      }
    }
  };

  /// `fragment33`
  late final f20 = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$28) case (var $0 && null)) {
        this.pos = mark;
        if (pos < buffer.length) {
          if (buffer[pos] case var $1) {
            pos++;
            return ("fragment33", [$0, $1]);
          }
        }
      }
    }
  };

  /// `fragment34`
  late final f21 = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$1) case var $0?) {
        if (pos < buffer.length) {
          if (buffer[pos] case var $1) {
            pos++;
            return ("fragment34", [$0, $1]);
          }
        }
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.matchPattern(_string.$24) case (var $0 && null)) {
          this.pos = mark;
          if (pos < buffer.length) {
            if (buffer[pos] case var $1) {
              pos++;
              return ("fragment34", [$0, $1]);
            }
          }
        }
      }
    }
  };

  /// `fragment35`
  late final f22 = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$1) case var $0?) {
        if (pos < buffer.length) {
          if (buffer[pos] case var $1) {
            pos++;
            return ("fragment35", [$0, $1]);
          }
        }
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.matchPattern(_string.$26) case (var $0 && null)) {
          this.pos = mark;
          if (pos < buffer.length) {
            if (buffer[pos] case var $1) {
              pos++;
              return ("fragment35", [$0, $1]);
            }
          }
        }
      }
    }
  };

  /// `fragment36`
  late final f23 = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$1) case var $0?) {
        if (pos < buffer.length) {
          if (buffer[pos] case var $1) {
            pos++;
            return ("fragment36", [$0, $1]);
          }
        }
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.matchPattern(_string.$27) case (var $0 && null)) {
          this.pos = mark;
          if (pos < buffer.length) {
            if (buffer[pos] case var $1) {
              pos++;
              return ("fragment36", [$0, $1]);
            }
          }
        }
      }
    }
  };

  /// `fragment37`
  late final f24 = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$1) case var $0?) {
        if (pos < buffer.length) {
          if (buffer[pos] case var $1) {
            pos++;
            return ("fragment37", [$0, $1]);
          }
        }
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.matchPattern(_string.$28) case (var $0 && null)) {
          this.pos = mark;
          if (pos < buffer.length) {
            if (buffer[pos] case var $1) {
              pos++;
              return ("fragment37", [$0, $1]);
            }
          }
        }
      }
    }
  };

  /// `fragment38`
  late final f25 = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$47) case var $0?) {
        if (this.pos case var mark) {
          if (this.f1x() case var _0) {
            if ([if (_0 case var _0?) _0] case (var $1 && var _loop2)) {
              if (_loop2.isNotEmpty) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.f1x() case var _0?) {
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
              if (this.matchPattern(_string.$24) case var $2?) {
                return ("fragment38", [$0, $1, $2]);
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$48) case var $0?) {
        if (this.pos case var mark) {
          if (this.f1y() case var _2) {
            if ([if (_2 case var _2?) _2] case (var $1 && var _loop4)) {
              if (_loop4.isNotEmpty) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.f1y() case var _2?) {
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
              if (this.matchPattern(_string.$26) case var $2?) {
                return ("fragment38", [$0, $1, $2]);
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$49) case var $0?) {
        if (this.pos case var mark) {
          if (this.f1z() case var _4) {
            if ([if (_4 case var _4?) _4] case (var $1 && var _loop6)) {
              if (_loop6.isNotEmpty) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.f1z() case var _4?) {
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
              if (this.matchPattern(_string.$27) case var $2?) {
                return ("fragment38", [$0, $1, $2]);
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$50) case var $0?) {
        if (this.pos case var mark) {
          if (this.f20() case var _6) {
            if ([if (_6 case var _6?) _6] case (var $1 && var _loop8)) {
              if (_loop8.isNotEmpty) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.f20() case var _6?) {
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
              if (this.matchPattern(_string.$28) case var $2?) {
                return ("fragment38", [$0, $1, $2]);
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$24) case var $0?) {
        if (this.pos case var mark) {
          if (this.f21() case var _8) {
            if ([if (_8 case var _8?) _8] case (var $1 && var _loop10)) {
              if (_loop10.isNotEmpty) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.f21() case var _8?) {
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
              if (this.matchPattern(_string.$24) case var $2?) {
                return ("fragment38", [$0, $1, $2]);
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$26) case var $0?) {
        if (this.pos case var mark) {
          if (this.f22() case var _10) {
            if ([if (_10 case var _10?) _10] case (var $1 && var _loop12)) {
              if (_loop12.isNotEmpty) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.f22() case var _10?) {
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
              if (this.matchPattern(_string.$26) case var $2?) {
                return ("fragment38", [$0, $1, $2]);
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$27) case var $0?) {
        if (this.pos case var mark) {
          if (this.f23() case var _12) {
            if ([if (_12 case var _12?) _12] case (var $1 && var _loop14)) {
              if (_loop14.isNotEmpty) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.f23() case var _12?) {
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
              if (this.matchPattern(_string.$27) case var $2?) {
                return ("fragment38", [$0, $1, $2]);
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$28) case var $0?) {
        if (this.pos case var mark) {
          if (this.f24() case var _14) {
            if ([if (_14 case var _14?) _14] case (var $1 && var _loop16)) {
              if (_loop16.isNotEmpty) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.f24() case var _14?) {
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
              if (this.matchPattern(_string.$28) case var $2?) {
                return ("fragment38", [$0, $1, $2]);
              }
            }
          }
        }
      }
    }
  };

  /// `fragment39`
  late final f26 = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$3) case (var $0 && null)) {
        this.pos = mark;
        if (pos < buffer.length) {
          if (buffer[pos] case var $1) {
            pos++;
            return ("fragment39", [$0, $1]);
          }
        }
      }
    }
  };

  /// `fragment40`
  late final f27 = () {
    if (this.pos case var mark) {
      if (this.apply(this.rh) case var $?) {
        return ("fragment40", $);
      }
      this.pos = mark;
      if (this.matchPattern(_string.$15) case var $0?) {
        if (this.apply(this.rg)! case var $1) {
          if (this.matchPattern(_string.$14) case var $2?) {
            return ("fragment40", [$0, $1, $2]);
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
              return ("fragment40", [$0, $1]);
            }
          }
        }
      }
    }
  };

  /// `fragment41`
  late final f28 = () {
    if (this.fw() case var $?) {
      return ("fragment41", $);
    }
  };

  /// `fragment42`
  late final f29 = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$15) case var $0?) {
        if (this.apply(this.rj)! case var $1) {
          if (this.matchPattern(_string.$14) case var $2?) {
            return ("fragment42", [$0, $1, $2]);
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
              return ("fragment42", [$0, $1]);
            }
          }
        }
      }
    }
  };

  /// `fragment43`
  late final f2a = () {
    if (this.fm() case var $0?) {
      if (this.f7() case var $1?) {
        if (this.fl() case var $2?) {
          return ("fragment43", [$0, $1, $2]);
        }
      }
    }
  };

  /// `fragment44`
  late final f2b = () {
    if (this.fm() case var $0?) {
      if (this.f7() case var $1?) {
        if (this.fl() case var $2?) {
          return ("fragment44", [$0, $1, $2]);
        }
      }
    }
  };

  /// `fragment45`
  late final f2c = () {
    if (this.fs() case var $0?) {
      if (this.fm() case var $1?) {
        if (this.f7() case var $2?) {
          if (this.fl() case var $3?) {
            return ("fragment45", [$0, $1, $2, $3]);
          }
        }
      }
    }
  };

  /// `fragment46`
  late final f2d = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$3) case (var $0 && null)) {
        this.pos = mark;
        if (pos < buffer.length) {
          if (buffer[pos] case var $1) {
            pos++;
            return ("fragment46", [$0, $1]);
          }
        }
      }
    }
  };

  /// `fragment47`
  late final f2e = () {
    if (this.matchPattern(_string.$3) case var $0?) {
      if (this.pos case var mark) {
        if (this.f2d() case var _0) {
          if ([if (_0 case var _0?) _0] case (var $1 && var _loop2)) {
            if (_loop2.isNotEmpty) {
              for (;;) {
                if (this.pos case var mark) {
                  if (this.f2d() case var _0?) {
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
            if (this.matchPattern(_string.$3) case var $2?) {
              return ("fragment47", [$0, $1, $2]);
            }
          }
        }
      }
    }
  };

  /// `fragment48`
  late final f2f = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$51) case var $?) {
        return ("fragment48", $);
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.matchPattern(_string.$11) case (var $0 && null)) {
          this.pos = mark;
          if (this.matchPattern(_string.$23) case var $1?) {
            return ("fragment48", [$0, $1]);
          }
        }
      }
    }
  };

  /// `fragment49`
  late final f2g = () {
    if (this.pos case var mark) {
      if (this.ff() case var $?) {
        return ("fragment49", $);
      }
      this.pos = mark;
      if (this.fg() case var $?) {
        return ("fragment49", $);
      }
      this.pos = mark;
      if (this.fh() case var $?) {
        return ("fragment49", $);
      }
    }
  };

  /// `fragment50`
  late final f2h = () {
    if (this.f8() case var $0?) {
      if (this.f2f() case var $1?) {
        if (this.pos case var mark) {
          if (this.f2g() case (var $2 && null)) {
            this.pos = mark;
            return ("fragment50", [$0, $1, $2]);
          }
        }
      }
    }
  };

  /// `fragment51`
  late final f2i = () {
    if (this.pos case var mark) {
      if (this.fv() case var $0) {
        if (this.matchPattern(_string.$52) case var $1?) {
          if (this.fv() case var $2) {
            return ("fragment51", [$0, $1, $2]);
          }
        }
      }
      this.pos = mark;
      if (this.fv() case var $0) {
        if (this.matchPattern(_string.$53) case var $1?) {
          if (this.fv() case var $2) {
            return ("fragment51", [$0, $1, $2]);
          }
        }
      }
      this.pos = mark;
      if (this.fv() case var $0) {
        if (this.matchPattern(_string.$54) case var $1?) {
          if (this.fv() case var $2) {
            return ("fragment51", [$0, $1, $2]);
          }
        }
      }
    }
  };

  /// `fragment52`
  late final f2j = () {
    if (this.fv() case var $0) {
      if (this.matchPattern(_string.$55) case var $1?) {
        if (this.fv() case var $2) {
          return ("fragment52", [$0, $1, $2]);
        }
      }
    }
  };

  /// `fragment53`
  late final f2k = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$3) case (var $0 && null)) {
        this.pos = mark;
        if (pos < buffer.length) {
          if (buffer[pos] case var $1) {
            pos++;
            return ("fragment53", [$0, $1]);
          }
        }
      }
    }
  };

  /// `fragment54`
  late final f2l = () {
    if (this.pos case var mark) {
      if (matchPattern(_regexp.$2) case var $?) {
        return ("fragment54", $);
      }
      this.pos = mark;
      if (matchPattern(_regexp.$3) case var $?) {
        return ("fragment54", $);
      }
      this.pos = mark;
      if (matchPattern(_regexp.$4) case var $?) {
        return ("fragment54", $);
      }
    }
  };

  /// `fragment55`
  late final f2m = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$24) case (var $0 && null)) {
        this.pos = mark;
        if (pos < buffer.length) {
          if (buffer[pos] case var $1) {
            pos++;
            return ("fragment55", [$0, $1]);
          }
        }
      }
    }
  };

  /// `fragment56`
  late final f2n = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$26) case (var $0 && null)) {
        this.pos = mark;
        if (pos < buffer.length) {
          if (buffer[pos] case var $1) {
            pos++;
            return ("fragment56", [$0, $1]);
          }
        }
      }
    }
  };

  /// `fragment57`
  late final f2o = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$27) case (var $0 && null)) {
        this.pos = mark;
        if (pos < buffer.length) {
          if (buffer[pos] case var $1) {
            pos++;
            return ("fragment57", [$0, $1]);
          }
        }
      }
    }
  };

  /// `fragment58`
  late final f2p = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$28) case (var $0 && null)) {
        this.pos = mark;
        if (pos < buffer.length) {
          if (buffer[pos] case var $1) {
            pos++;
            return ("fragment58", [$0, $1]);
          }
        }
      }
    }
  };

  /// `fragment59`
  late final f2q = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$1) case var $0?) {
        if (pos < buffer.length) {
          if (buffer[pos] case var $1) {
            pos++;
            return ("fragment59", [$0, $1]);
          }
        }
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.matchPattern(_string.$29) case var $0?) {
          this.pos = mark;
          if (this.fx() case var $1?) {
            return ("fragment59", [$0, $1]);
          }
        }
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.matchPattern(_string.$24) case (var $0 && null)) {
          this.pos = mark;
          if (pos < buffer.length) {
            if (buffer[pos] case var $1) {
              pos++;
              return ("fragment59", [$0, $1]);
            }
          }
        }
      }
    }
  };

  /// `fragment60`
  late final f2r = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$1) case var $0?) {
        if (pos < buffer.length) {
          if (buffer[pos] case var $1) {
            pos++;
            return ("fragment60", [$0, $1]);
          }
        }
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.matchPattern(_string.$29) case var $0?) {
          this.pos = mark;
          if (this.fx() case var $1?) {
            return ("fragment60", [$0, $1]);
          }
        }
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.matchPattern(_string.$26) case (var $0 && null)) {
          this.pos = mark;
          if (pos < buffer.length) {
            if (buffer[pos] case var $1) {
              pos++;
              return ("fragment60", [$0, $1]);
            }
          }
        }
      }
    }
  };

  /// `fragment61`
  late final f2s = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$1) case var $0?) {
        if (pos < buffer.length) {
          if (buffer[pos] case var $1) {
            pos++;
            return ("fragment61", [$0, $1]);
          }
        }
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.matchPattern(_string.$29) case var $0?) {
          this.pos = mark;
          if (this.fx() case var $1?) {
            return ("fragment61", [$0, $1]);
          }
        }
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.matchPattern(_string.$27) case (var $0 && null)) {
          this.pos = mark;
          if (pos < buffer.length) {
            if (buffer[pos] case var $1) {
              pos++;
              return ("fragment61", [$0, $1]);
            }
          }
        }
      }
    }
  };

  /// `fragment62`
  late final f2t = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$1) case var $0?) {
        if (pos < buffer.length) {
          if (buffer[pos] case var $1) {
            pos++;
            return ("fragment62", [$0, $1]);
          }
        }
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.matchPattern(_string.$29) case var $0?) {
          this.pos = mark;
          if (this.fx() case var $1?) {
            return ("fragment62", [$0, $1]);
          }
        }
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.matchPattern(_string.$28) case (var $0 && null)) {
          this.pos = mark;
          if (pos < buffer.length) {
            if (buffer[pos] case var $1) {
              pos++;
              return ("fragment62", [$0, $1]);
            }
          }
        }
      }
    }
  };

  /// `fragment63`
  late final f2u = () {
    if (this.f8() case var _0?) {
      if (<Object>[_0] case var _loop3) {
        for (;;) {
          if (this.pos case var mark) {
            if (this.fu() case var _1?) {
              if (this.f8() case var _0?) {
                _loop3.addAll([_1, _0]);
                continue;
              }
            }
            this.pos = mark;
            break;
          }
        }
        return ("fragment63", _loop3);
      }
    }
  };

  /// `fragment64`
  late final f2v = () {
    if (this.fv() case var $0) {
      if (this.matchPattern(_string.$56) case var $1?) {
        if (this.fv() case var $2) {
          return ("fragment64", [$0, $1, $2]);
        }
      }
    }
  };

  /// `fragment65`
  late final f2w = () {
    if (this.fv() case var $0) {
      if (this.matchPattern(_string.$57) case var $1?) {
        if (this.fv() case var $2) {
          return ("fragment65", [$0, $1, $2]);
        }
      }
    }
  };

  /// `global::document`
  Object? r0() {
    if (this.pos case var $0 when this.pos <= 0) {
      if (this.apply(this.r1) case (var $1 && var preamble)) {
        if (this.apply(this.r2) case var _0?) {
          if (<Object>[_0] case (var $2 && var statements && var _loop3)) {
            for (;;) {
              if (this.pos case var mark) {
                if (this.fv() case var _1) {
                  if (this.apply(this.r2) case var _0?) {
                    _loop3.addAll([_1, _0]);
                    continue;
                  }
                }
                this.pos = mark;
                break;
              }
            }
            if (this.fv() case var $3) {
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
    if (this.fm() case var $0?) {
      if (this.fv() case var $1) {
        if (this.apply(this.rf)! case (var $2 && var code)) {
          if (this.fv() case var $3) {
            if (this.fl() case var $4?) {
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
        if (this.f8() case (var $1 && var name)) {
          if (this.fm() case var $2?) {
            if (this.apply(this.r2) case var _0?) {
              if (<Object>[_0] case (var $3 && var statements && var _loop3)) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.fv() case var _1) {
                      if (this.apply(this.r2) case var _0?) {
                        _loop3.addAll([_1, _0]);
                        continue;
                      }
                    }
                    this.pos = mark;
                    break;
                  }
                }
                if (this.fl() case var $4?) {
                  return ("global::namespace", [$0, $1, $2, $3, $4]);
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.fb() case var $0?) {
        if (this.f8() case (var $1 && var name)) {
          if (this.fm() case var $2?) {
            if (this.apply(this.r2) case var _3?) {
              if (<Object>[_3] case (var $3 && var statements && var _loop6)) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.fv() case var _4) {
                      if (this.apply(this.r2) case var _3?) {
                        _loop6.addAll([_4, _3]);
                        continue;
                      }
                    }
                    this.pos = mark;
                    break;
                  }
                }
                if (this.fl() case var $4?) {
                  return ("global::namespace", [$0, $1, $2, $3, $4]);
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.fd() case var $0?) {
        if (this.f8() case (var $1 && var name)) {
          if (this.fm() case var $2?) {
            if (this.apply(this.r2) case var _6?) {
              if (<Object>[_6] case (var $3 && var statements && var _loop9)) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.fv() case var _7) {
                      if (this.apply(this.r2) case var _6?) {
                        _loop9.addAll([_7, _6]);
                        continue;
                      }
                    }
                    this.pos = mark;
                    break;
                  }
                }
                if (this.fl() case var $4?) {
                  return ("global::namespace", [$0, $1, $2, $3, $4]);
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.f8() case (var $0 && var name)) {
        if (this.fm() case var $1?) {
          if (this.apply(this.r2) case var _9?) {
            if (<Object>[_9] case (var $2 && var statements && var _loop12)) {
              for (;;) {
                if (this.pos case var mark) {
                  if (this.fv() case var _10) {
                    if (this.apply(this.r2) case var _9?) {
                      _loop12.addAll([_10, _9]);
                      continue;
                    }
                  }
                  this.pos = mark;
                  break;
                }
              }
              if (this.fl() case var $3?) {
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
      if (this.fa() case (var $0 && var decorator)) {
        if (this.fe() case var $1) {
          if (this.f3() case (var $2 && var name)?) {
            if (this.f4() case (var $3 && var body)?) {
              return ("global::declaration", [$0, $1, $2, $3]);
            }
          }
        }
      }
      this.pos = mark;
      if (this.fa() case (var $0 && var decorator)) {
        if (this.f0() case (var $1 && var type)?) {
          if (this.f3() case (var $2 && var name)?) {
            if (this.f4() case (var $3 && var body)?) {
              return ("global::declaration", [$0, $1, $2, $3]);
            }
          }
        }
      }
      this.pos = mark;
      if (this.fa() case (var $0 && var decorator)) {
        if (this.fe() case var $1) {
          if (this.f3() case (var $2 && var name)?) {
            if (this.f13() case var $3?) {
              if (this.f0() case (var $4 && var type)?) {
                if (this.f4() case (var $5 && var body)?) {
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
    if (this.ft() case var $0) {
      if (this.apply(this.r6) case var _0?) {
        if (<Object>[_0] case (var $1 && var options && var _loop3)) {
          for (;;) {
            if (this.pos case var mark) {
              if (this.ft() case var _1?) {
                if (this.apply(this.r6) case var _0?) {
                  _loop3.addAll([_1, _0]);
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
      if (this.apply(this.r7) case (var $0 && var sequence)?) {
        if (this.f14() case var $1?) {
          if (this.fv() case var $2) {
            if (this.f6() case (var $3 && var raw)?) {
              if (this.fv() case var $4) {
                return ("global::acted", [$0, $1, $2, $3, $4]);
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.r7) case (var $0 && var sequence)?) {
        if (this.fm() case var $1?) {
          if (this.fv() case var $2) {
            if (this.apply(this.rf)! case (var $3 && var curly)) {
              if (this.fv() case var $4) {
                if (this.fl() case var $5?) {
                  return ("global::acted", [$0, $1, $2, $3, $4, $5]);
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.r7) case (var $0 && var sequence)?) {
        if (this.fo() case var $1?) {
          if (this.fn() case var $2?) {
            if (this.fm() case var $3?) {
              if (this.fv() case var $4) {
                if (this.apply(this.rf)! case (var $5 && var curly)) {
                  if (this.fv() case var $6) {
                    if (this.fl() case var $7?) {
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
      if (<Object>[_0] case (var $0 && var body && var _loop3)) {
        for (;;) {
          if (this.pos case var mark) {
            if (this.fv() case var _1) {
              if (this.apply(this.r8) case var _0?) {
                _loop3.addAll([_1, _0]);
                continue;
              }
            }
            this.pos = mark;
            break;
          }
        }
        if (this.f16() case (var $1 && var chosen)) {
          return ("global::sequence", [$0, $1]);
        }
      }
    }
  }

  /// `global::dropped`
  Object? r8() {
    if (this.pos case var mark) {
      if (this.apply(this.ra) case (var $0 && var left)?) {
        if (this.fj() case var $1?) {
          if (this.apply(this.r9) case (var $2 && var body)?) {
            if (this.fk() case var $3?) {
              if (this.apply(this.ra) case (var $4 && var right)?) {
                return ("global::dropped", [$0, $1, $2, $3, $4]);
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.r8) case (var $0 && var captured)?) {
        if (this.fk() case var $1?) {
          if (this.apply(this.ra) case (var $2 && var dropped)?) {
            return ("global::dropped", [$0, $1, $2]);
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.ra) case (var $0 && var dropped)?) {
        if (this.fj() case var $1?) {
          if (this.apply(this.r8) case (var $2 && var captured)?) {
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
      if (this.f8() case (var $0 && var identifier)?) {
        if (this.matchPattern(_string.$30) case var $1?) {
          if (this.fv() case var $2) {
            if (this.apply(this.ra) case (var $3 && var special)?) {
              return ("global::labeled", [$0, $1, $2, $3]);
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$30) case var $0?) {
        if (this.f2() case (var $1 && var id)?) {
          if (this.fp() case var $2?) {
            return ("global::labeled", [$0, $1, $2]);
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$30) case var $0?) {
        if (this.f2() case (var $1 && var id)?) {
          if (this.fq() case var $2?) {
            return ("global::labeled", [$0, $1, $2]);
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$30) case var $0?) {
        if (this.f2() case (var $1 && var id)?) {
          if (this.fr() case var $2?) {
            return ("global::labeled", [$0, $1, $2]);
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$30) case var $0?) {
        if (this.f2() case (var $1 && var id)?) {
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
      if (this.f9() case (var $0 && var min)?) {
        if (this.fi() case var $1?) {
          if (this.f9() case (var $2 && var max)) {
            if (this.apply(this.re) case (var $3 && var body)?) {
              return ("global::special", [$0, $1, $2, $3]);
            }
          }
        }
      }
      this.pos = mark;
      if (this.f9() case (var $0 && var number)?) {
        if (this.apply(this.re) case (var $1 && var body)?) {
          return ("global::special", [$0, $1]);
        }
      }
      this.pos = mark;
      if (this.apply(this.rd) case (var $0 && var sep)?) {
        if (this.fi() case var $1?) {
          if (this.apply(this.rd) case (var $2 && var expr)?) {
            if (this.fr() case var $3?) {
              return ("global::special", [$0, $1, $2, $3]);
            }
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.rd) case (var $0 && var sep)?) {
        if (this.fi() case var $1?) {
          if (this.apply(this.rd) case (var $2 && var expr)?) {
            if (this.fq() case var $3?) {
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
        if (this.fp() case var $1?) {
          return ("global::postfix", [$0, $1]);
        }
      }
      this.pos = mark;
      if (this.apply(this.rb) case var $0?) {
        if (this.fq() case var $1?) {
          return ("global::postfix", [$0, $1]);
        }
      }
      this.pos = mark;
      if (this.apply(this.rb) case var $0?) {
        if (this.fr() case var $1?) {
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
      if (this.f17() case var $0?) {
        if (this.apply(this.rc) case var $1?) {
          return ("global::prefix", [$0, $1]);
        }
      }
      this.pos = mark;
      if (this.f18() case var $0?) {
        if (this.apply(this.rc) case var $1?) {
          return ("global::prefix", [$0, $1]);
        }
      }
      this.pos = mark;
      if (this.f19() case var $0?) {
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
      if (this.apply(this.rd) case (var $0 && var target)?) {
        if (this.fu() case var $1?) {
          if (this.fg() case var $2?) {
            if (this.fo() case var $3?) {
              if (this.fn() case var $4?) {
                return ("global::callLike", [$0, $1, $2, $3, $4]);
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.rd) case (var $0 && var target)?) {
        if (this.fu() case var $1?) {
          if (this.ff() case var $2?) {
            if (this.fo() case var $3?) {
              if (this.f9() case (var $4 && var min)?) {
                if (this.fs() case var $5?) {
                  if (this.f9() case (var $6 && var max)?) {
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
      if (this.apply(this.rd) case (var $0 && var target)?) {
        if (this.fu() case var $1?) {
          if (this.ff() case var $2?) {
            if (this.fo() case var $3?) {
              if (this.f9() case (var $4 && var number)?) {
                if (this.fn() case var $5?) {
                  return ("global::callLike", [$0, $1, $2, $3, $4, $5]);
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.rd) case (var $0 && var target)?) {
        if (this.fu() case var $1?) {
          if (this.ff() case var $2?) {
            if (this.fv() case var $3) {
              if (this.f9() case (var $4 && var number)?) {
                if (this.fv() case var $5) {
                  return ("global::callLike", [$0, $1, $2, $3, $4, $5]);
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.rd) case (var $0 && var sep)?) {
        if (this.fu() case var $1?) {
          if (this.fh() case var $2?) {
            if (this.fo() case var $3?) {
              if (this.apply(this.r5) case (var $4 && var body)?) {
                if (this.fn() case var $5?) {
                  if (this.fr() case var $6?) {
                    if (this.fp() case var $7?) {
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
      if (this.apply(this.rd) case (var $0 && var sep)?) {
        if (this.fu() case var $1?) {
          if (this.fh() case var $2?) {
            if (this.fo() case var $3?) {
              if (this.apply(this.r5) case (var $4 && var body)?) {
                if (this.fn() case var $5?) {
                  if (this.fq() case var $6?) {
                    if (this.fp() case var $7?) {
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
      if (this.apply(this.rd) case (var $0 && var sep)?) {
        if (this.fu() case var $1?) {
          if (this.fh() case var $2?) {
            if (this.fo() case var $3?) {
              if (this.apply(this.r5) case (var $4 && var body)?) {
                if (this.fn() case var $5?) {
                  if (this.fr() case var $6?) {
                    return ("global::callLike", [$0, $1, $2, $3, $4, $5, $6]);
                  }
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.rd) case (var $0 && var sep)?) {
        if (this.fu() case var $1?) {
          if (this.fh() case var $2?) {
            if (this.fo() case var $3?) {
              if (this.apply(this.r5) case (var $4 && var body)?) {
                if (this.fn() case var $5?) {
                  if (this.fq() case var $6?) {
                    return ("global::callLike", [$0, $1, $2, $3, $4, $5, $6]);
                  }
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.rd) case (var $0 && var sep)?) {
        if (this.fu() case var $1?) {
          if (this.fh() case var $2?) {
            if (this.fo() case var $3?) {
              if (this.apply(this.r5) case (var $4 && var body)?) {
                if (this.fn() case var $5?) {
                  return ("global::callLike", [$0, $1, $2, $3, $4, $5]);
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.rd) case (var $0 && var sep)?) {
        if (this.fu() case var $1?) {
          if (this.fh() case var $2?) {
            if (this.fv() case var $3) {
              if (this.apply(this.re) case (var $4 && var body)?) {
                if (this.fv() case var $5) {
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
      if (this.fo() case var $0?) {
        if (this.apply(this.r5) case var $1?) {
          if (this.fn() case var $2?) {
            return ("global::atom", [$0, $1, $2]);
          }
        }
      }
      this.pos = mark;
      if (this.fv() case var $0) {
        if (this.matchPattern(_string.$58) case var $1?) {
          if (this.fv() case var $2) {
            return ("global::atom", [$0, $1, $2]);
          }
        }
      }
      this.pos = mark;
      if (this.fv() case var $0) {
        if (this.matchPattern(_string.$29) case var $1?) {
          if (this.fv() case var $2) {
            return ("global::atom", [$0, $1, $2]);
          }
        }
      }
      this.pos = mark;
      if (this.fu() case var $?) {
        return ("global::atom", $);
      }
      this.pos = mark;
      if (this.fv() case var $0) {
        if (this.matchPattern(_string.$59) case var $1?) {
          if (this.fv() case var $2) {
            return ("global::atom", [$0, $1, $2]);
          }
        }
      }
      this.pos = mark;
      if (this.fv() case var $0) {
        if (this.f1a() case var $1?) {
          if (this.fv() case var $2) {
            return ("global::atom", [$0, $1, $2]);
          }
        }
      }
      this.pos = mark;
      if (this.fv() case var $0) {
        if (this.f1b() case var $1?) {
          if (this.fv() case var $2) {
            return ("global::atom", [$0, $1, $2]);
          }
        }
      }
      this.pos = mark;
      if (this.fv() case var $0) {
        if (this.f1c() case var $1?) {
          if (this.fv() case var $2) {
            return ("global::atom", [$0, $1, $2]);
          }
        }
      }
      this.pos = mark;
      if (this.fv() case var $0) {
        if (this.f1d() case var $1?) {
          if (this.fv() case var $2) {
            return ("global::atom", [$0, $1, $2]);
          }
        }
      }
      this.pos = mark;
      if (this.fv() case var $0) {
        if (this.f1e() case var $1?) {
          if (this.fv() case var $2) {
            return ("global::atom", [$0, $1, $2]);
          }
        }
      }
      this.pos = mark;
      if (this.fv() case var $0) {
        if (this.f1f() case var $1?) {
          if (this.fv() case var $2) {
            return ("global::atom", [$0, $1, $2]);
          }
        }
      }
      this.pos = mark;
      if (this.fv() case var $0) {
        if (this.f1g() case var $1?) {
          if (this.fv() case var $2) {
            return ("global::atom", [$0, $1, $2]);
          }
        }
      }
      this.pos = mark;
      if (this.fv() case var $0) {
        if (this.f1h() case var $1?) {
          if (this.fv() case var $2) {
            return ("global::atom", [$0, $1, $2]);
          }
        }
      }
      this.pos = mark;
      if (this.fv() case var $0) {
        if (this.f1i() case var $1?) {
          if (this.fv() case var $2) {
            return ("global::atom", [$0, $1, $2]);
          }
        }
      }
      this.pos = mark;
      if (this.fv() case var $0) {
        if (this.f1j() case var $1?) {
          if (this.fv() case var $2) {
            return ("global::atom", [$0, $1, $2]);
          }
        }
      }
      this.pos = mark;
      if (this.fv() case var $0) {
        if (this.f1k() case var $1?) {
          if (this.fv() case var $2) {
            return ("global::atom", [$0, $1, $2]);
          }
        }
      }
      this.pos = mark;
      if (this.fv() case var $0) {
        if (this.f1l() case var $1?) {
          if (this.fv() case var $2) {
            return ("global::atom", [$0, $1, $2]);
          }
        }
      }
      this.pos = mark;
      if (this.fv() case var $0) {
        if (this.f1u() case var $1?) {
          if (this.fv() case var $2) {
            return ("global::atom", [$0, $1, $2]);
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$46) case var $0?) {
        if (this.f1w() case var $1?) {
          if (this.matchPattern(_string.$46) case var $2?) {
            return ("global::atom", [$0, $1, $2]);
          }
        }
      }
      this.pos = mark;
      if (this.fv() case var $0) {
        if (this.f25() case var $1?) {
          if (this.fv() case var $2) {
            return ("global::atom", [$0, $1, $2]);
          }
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
        if (this.pos case var mark) {
          if (this.f26() case var _0) {
            if ([if (_0 case var _0?) _0] case (var $1 && var _loop2)) {
              if (_loop2.isNotEmpty) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.f26() case var _0?) {
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
              if (this.matchPattern(_string.$3) case var $2?) {
                return ("global::code::curly", [$0, $1, $2]);
              }
            }
          }
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
      if (this.f27() case var _0) {
        if ([if (_0 case var _0?) _0] case (var code && var _loop2)) {
          if (_loop2.isNotEmpty) {
            for (;;) {
              if (this.pos case var mark) {
                if (this.f27() case var _0?) {
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
          return ("global::code::curly::balanced", _loop2);
        }
      }
    }
  }

  /// `global::dart::literal::string`
  Object? rh() {
    if (this.f28() case var _0?) {
      if (<Object>[_0] case var _loop3) {
        for (;;) {
          if (this.pos case var mark) {
            if (this.fv() case var _1) {
              if (this.f28() case var _0?) {
                _loop3.addAll([_1, _0]);
                continue;
              }
            }
            this.pos = mark;
            break;
          }
        }
        return ("global::dart::literal::string", _loop3);
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
      if (this.f29() case var _0) {
        if ([if (_0 case var _0?) _0] case (var code && var _loop2)) {
          if (_loop2.isNotEmpty) {
            for (;;) {
              if (this.pos case var mark) {
                if (this.f29() case var _0?) {
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
          return ("global::dart::literal::string::balanced", _loop2);
        }
      }
    }
  }

  /// `global::dart::type::main`
  Object? rk() {
    if (this.fv() case var $0) {
      if (this.apply(this.rl) case var $1?) {
        if (this.fv() case var $2) {
          return ("global::dart::type::main", [$0, $1, $2]);
        }
      }
    }
  }

  /// `global::dart::type::nullable`
  Object? rl() {
    if (this.apply(this.rm) case (var $0 && var nonNullable)?) {
      if (this.fp() case var $1) {
        return ("global::dart::type::nullable", [$0, $1]);
      }
    }
  }

  /// `global::dart::type::nonNullable`
  Object? rm() {
    if (this.pos case var mark) {
      if (this.fy() case var $?) {
        return ("global::dart::type::nonNullable", $);
      }
      this.pos = mark;
      if (this.apply(this.rn) case var $?) {
        return ("global::dart::type::nonNullable", $);
      }
      this.pos = mark;
      if (this.f8() case var _0?) {
        if (<Object>[_0] case var _loop3) {
          for (;;) {
            if (this.pos case var mark) {
              if (this.fu() case var _1?) {
                if (this.f8() case var _0?) {
                  _loop3.addAll([_1, _0]);
                  continue;
                }
              }
              this.pos = mark;
              break;
            }
          }
          return ("global::dart::type::nonNullable", _loop3);
        }
      }
    }
  }

  /// `global::dart::type::record`
  Object? rn() {
    if (this.pos case var mark) {
      if (this.fo() case var $0?) {
        if (this.f2a() case var $1) {
          if (this.fn() case var $2?) {
            return ("global::dart::type::record", [$0, $1, $2]);
          }
        }
      }
      this.pos = mark;
      if (this.fo() case var $0?) {
        if (this.f10() case var $1?) {
          if (this.fs() case var $2?) {
            if (this.f2b() case var $3) {
              if (this.fn() case var $4?) {
                return ("global::dart::type::record", [$0, $1, $2, $3, $4]);
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.fo() case var $0?) {
        if (this.f12() case var $1?) {
          if (this.f2c() case var $2) {
            if (this.fn() case var $3?) {
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
    "..",
    "~>",
    "<~",
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
    "=>",
    "@",
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
    "::",
    "=",
    "<-",
    "->",
    ";",
    "<",
    ">",
    "^",
    "ε",
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
