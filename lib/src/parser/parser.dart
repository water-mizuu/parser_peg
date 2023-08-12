// ignore_for_file: always_declare_return_types, always_put_control_body_on_new_line, always_specify_types, avoid_escaping_inner_quotes, avoid_redundant_argument_values, annotate_overrides, body_might_complete_normally_nullable, constant_pattern_never_matches_value_type, curly_braces_in_flow_control_structures, dead_code, directives_ordering, duplicate_ignore, inference_failure_on_function_return_type, constant_identifier_names, prefer_function_declarations_over_variables, prefer_interpolation_to_compose_strings, prefer_is_empty, no_leading_underscores_for_local_identifiers, non_constant_identifier_names, unnecessary_null_check_pattern, unnecessary_brace_in_string_interps, unnecessary_string_interpolations, unnecessary_this, unused_element, unused_import, prefer_double_quotes, unused_local_variable, unreachable_from_main, use_raw_strings, type_annotate_public_apis

// imports
// ignore_for_file: collection_methods_unrelated_type

import "dart:collection";
import "dart:math" as math;

import "package:parser_peg/src/generator.dart";
// PREAMBLE
import "package:parser_peg/src/node.dart";
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
      if (this.fv() case _) {
        if (this.f2f() case var $1?) {
          if (this.fv() case _) {
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
  String f1() {
    if (this.pos case var mark) {
      if (this.f2i() case var _0) {
        if ([if (_0 case var _0?) _0] case (var $ && var _l1)) {
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
    if (this.f2j() case _?) {
      if (this.apply(this.r5) case var choice?) {
        if (this.f2k() case _?) {
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
      if (this.pos case var mark) {
        if (this.f2l() case var _0) {
          if ([if (_0 case var _0?) _0] case (var $1 && var _l1)) {
            if (_l1.isNotEmpty) {
              for (;;) {
                if (this.pos case var mark) {
                  if (this.f2l() case var _0?) {
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
            if (this.matchPattern(_string.$3) case var $2?) {
              if ($1 case var $) {
                return $.join();
              }
            }
          }
        }
      }
    }
  }

  /// `global::dart::type::fields::named`
  String? f7() {
    if (this.f12() case var _0?) {
      if ([_0] case (var $ && var _l1)) {
        for (;;) {
          if (this.pos case var mark) {
            if (this.fs() case _?) {
              if (this.f12() case var _0?) {
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
    if (this.fv() case var $0) {
      if (this.matchPattern(_string.$4) case var $1?) {
        if (this.fv() case var $2) {
          return Tag.rule;
        }
      }
    }
  }

  /// `global::kw::decorator::fragment`
  Tag? fc() {
    if (this.fv() case var $0) {
      if (this.matchPattern(_string.$5) case var $1?) {
        if (this.fv() case var $2) {
          return Tag.fragment;
        }
      }
    }
  }

  /// `global::kw::decorator::inline`
  Tag? fd() {
    if (this.fv() case var $0) {
      if (this.matchPattern(_string.$6) case var $1?) {
        if (this.fv() case var $2) {
          return Tag.inline;
        }
      }
    }
  }

  /// `global::kw::var`
  String? fe() {
    if (this.fv() case _) {
      if (this.matchPattern(_string.$7) case var $1?) {
        if (this.fv() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::mac::range`
  String? ff() {
    if (this.fv() case _) {
      if (this.matchPattern(_string.$8) case var $1?) {
        if (this.fv() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::mac::flat`
  String? fg() {
    if (this.fv() case _) {
      if (this.matchPattern(_string.$9) case var $1?) {
        if (this.fv() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::mac::sep`
  String? fh() {
    if (this.fv() case _) {
      if (this.matchPattern(_string.$10) case var $1?) {
        if (this.fv() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::..`
  String? fi() {
    if (this.fv() case _) {
      if (this.matchPattern(_string.$11) case var $1?) {
        if (this.fv() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::~>`
  String? fj() {
    if (this.fv() case _) {
      if (this.matchPattern(_string.$12) case var $1?) {
        if (this.fv() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::<~`
  String? fk() {
    if (this.fv() case _) {
      if (this.matchPattern(_string.$13) case var $1?) {
        if (this.fv() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::}`
  String? fl() {
    if (this.fv() case _) {
      if (this.matchPattern(_string.$14) case var $1?) {
        if (this.fv() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::{`
  String? fm() {
    if (this.fv() case _) {
      if (this.matchPattern(_string.$15) case var $1?) {
        if (this.fv() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::)`
  String? fn() {
    if (this.fv() case _) {
      if (this.matchPattern(_string.$16) case var $1?) {
        if (this.fv() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::(`
  String? fo() {
    if (this.fv() case _) {
      if (this.matchPattern(_string.$17) case var $1?) {
        if (this.fv() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::?`
  String? fp() {
    if (this.fv() case _) {
      if (this.matchPattern(_string.$18) case var $1?) {
        if (this.fv() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::*`
  String? fq() {
    if (this.fv() case _) {
      if (this.matchPattern(_string.$19) case var $1?) {
        if (this.fv() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::+`
  String? fr() {
    if (this.fv() case _) {
      if (this.matchPattern(_string.$20) case var $1?) {
        if (this.fv() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::,`
  String? fs() {
    if (this.fv() case _) {
      if (this.matchPattern(_string.$21) case var $1?) {
        if (this.fv() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::|`
  String? ft() {
    if (this.fv() case _) {
      if (this.matchPattern(_string.$22) case var $1?) {
        if (this.fv() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::.`
  String? fu() {
    if (this.fv() case _) {
      if (this.matchPattern(_string.$23) case var $1?) {
        if (this.fv() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::_`
  String fv() {
    if (this.pos case var mark) {
      if (this.f2m() case var _0) {
        if ([if (_0 case var _0?) _0] case var _l1) {
          if (_l1.isNotEmpty) {
            for (;;) {
              if (this.pos case var mark) {
                if (this.f2m() case var _0?) {
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
  ParserGenerator? fw() {
    if (this.apply(this.r0) case var $?) {
      return $;
    }
  }

  /// `global::dart::literal::string::body`
  late final fx = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$25) case var $0?) {
        if (this.matchPattern(_string.$24) case var $1?) {
          if (this.pos case var mark) {
            if (this.f2n() case var _0) {
              if ([if (_0 case var _0?) _0] case (var $2 && var _l1)) {
                if (_l1.isNotEmpty) {
                  for (;;) {
                    if (this.pos case var mark) {
                      if (this.f2n() case var _0?) {
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
                if (this.matchPattern(_string.$24) case var $3?) {
                  return ();
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
            if (this.f2o() case var _2) {
              if ([if (_2 case var _2?) _2] case (var $2 && var _l3)) {
                if (_l3.isNotEmpty) {
                  for (;;) {
                    if (this.pos case var mark) {
                      if (this.f2o() case var _2?) {
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
                if (this.matchPattern(_string.$26) case var $3?) {
                  return ();
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
            if (this.f2p() case var _4) {
              if ([if (_4 case var _4?) _4] case (var $2 && var _l5)) {
                if (_l5.isNotEmpty) {
                  for (;;) {
                    if (this.pos case var mark) {
                      if (this.f2p() case var _4?) {
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
                if (this.matchPattern(_string.$27) case var $3?) {
                  return ();
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
            if (this.f2q() case var _6) {
              if ([if (_6 case var _6?) _6] case (var $2 && var _l7)) {
                if (_l7.isNotEmpty) {
                  for (;;) {
                    if (this.pos case var mark) {
                      if (this.f2q() case var _6?) {
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
                if (this.matchPattern(_string.$28) case var $3?) {
                  return ();
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$24) case var $0?) {
        if (this.pos case var mark) {
          if (this.f2r() case var _8) {
            if ([if (_8 case var _8?) _8] case (var $1 && var _l9)) {
              if (_l9.isNotEmpty) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.f2r() case var _8?) {
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
              if (this.matchPattern(_string.$24) case var $2?) {
                return ();
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$26) case var $0?) {
        if (this.pos case var mark) {
          if (this.f2s() case var _10) {
            if ([if (_10 case var _10?) _10] case (var $1 && var _l11)) {
              if (_l11.isNotEmpty) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.f2s() case var _10?) {
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
              if (this.matchPattern(_string.$26) case var $2?) {
                return ();
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$27) case var $0?) {
        if (this.pos case var mark) {
          if (this.f2t() case var _12) {
            if ([if (_12 case var _12?) _12] case (var $1 && var _l13)) {
              if (_l13.isNotEmpty) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.f2t() case var _12?) {
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
              if (this.matchPattern(_string.$27) case var $2?) {
                return ();
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$28) case var $0?) {
        if (this.pos case var mark) {
          if (this.f2u() case var _14) {
            if ([if (_14 case var _14?) _14] case (var $1 && var _l15)) {
              if (_l15.isNotEmpty) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.f2u() case var _14?) {
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
              if (this.matchPattern(_string.$28) case var $2?) {
                return ();
              }
            }
          }
        }
      }
    }
  };

  /// `global::dart::literal::string::interpolation`
  late final fy = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$29) case var $0?) {
        if (this.matchPattern(_string.$15) case var $1?) {
          if (this.apply(this.rj)! case var $2) {
            if (this.matchPattern(_string.$14) case var $3?) {
              return ($0, $1, $2, $3);
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$29) case var $0?) {
        if (this.apply(this.ri) case var $1?) {
          return ($0, $1);
        }
      }
    }
  };

  /// `global::dart::type::generic`
  String? fz() {
    if (this.f2v() case var base?) {
      if (this.f2w() case _?) {
        if (this.f10() case var arguments?) {
          if (this.f2x() case _?) {
            return "$base<$arguments>";
          }
        }
      }
    }
  }

  /// `global::dart::type::arguments`
  String? f10() {
    if (this.apply(this.rl) case var _0?) {
      if ([_0] case (var $ && var _l1)) {
        for (;;) {
          if (this.pos case var mark) {
            if (this.fs() case _?) {
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
  String? f11() {
    if (this.apply(this.rl) case var $0?) {
      if (this.fv() case var $1) {
        if (this.f8() case var $2) {
          if (($0, $1, $2) case var $) {
            return "${$0} ${$2 ?? ""}".trimRight();
          }
        }
      }
    }
  }

  /// `global::dart::type::field::named`
  String? f12() {
    if (this.apply(this.rl) case var $0?) {
      if (this.fv() case var $1) {
        if (this.f8() case var $2?) {
          if (($0, $1, $2) case var $) {
            return "${$0} ${$2}";
          }
        }
      }
    }
  }

  /// `global::dart::type::fields::positional`
  String? f13() {
    if (this.f11() case var _0?) {
      if ([_0] case (var $ && var _l1)) {
        for (;;) {
          if (this.pos case var mark) {
            if (this.fs() case _?) {
              if (this.f11() case var _0?) {
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
  late final f14 = () {
    if (this.fv() case _) {
      if (this.matchPattern(_string.$30) case var $1?) {
        if (this.fv() case _) {
          return $1;
        }
      }
    }
  };

  /// `fragment1`
  late final f15 = () {
    if (this.fv() case _) {
      if (this.matchPattern(_string.$31) case var $1?) {
        if (this.fv() case _) {
          return $1;
        }
      }
    }
  };

  /// `fragment2`
  late final f16 = () {
    if (this.fv() case _) {
      if (this.matchPattern(_string.$32) case var $1?) {
        if (this.fv() case _) {
          return $1;
        }
      }
    }
  };

  /// `fragment3`
  late final f17 = () {
    if (this.f16() case _?) {
      if (this.f9() case var $1?) {
        return $1;
      }
    }
  };

  /// `fragment4`
  late final f18 = () {
    if (this.fv() case _) {
      if (this.matchPattern(_string.$33) case var $1?) {
        if (this.fv() case _) {
          return $1;
        }
      }
    }
  };

  /// `fragment5`
  late final f19 = () {
    if (this.fv() case _) {
      if (this.matchPattern(_string.$34) case var $1?) {
        if (this.fv() case _) {
          return $1;
        }
      }
    }
  };

  /// `fragment6`
  late final f1a = () {
    if (this.fv() case _) {
      if (this.matchPattern(_string.$35) case var $1?) {
        if (this.fv() case _) {
          return $1;
        }
      }
    }
  };

  /// `fragment7`
  late final f1b = () {
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

  /// `fragment8`
  late final f1c = () {
    if (this.pos case var from) {
      if (this.matchPattern(_string.$1) case var $0?) {
        if (this.matchPattern(_string.$36) case var $1?) {
          if (this.pos case var to) {
            return this.buffer.substring(from, to);
          }
        }
      }
    }
  };

  /// `fragment9`
  late final f1d = () {
    if (this.pos case var from) {
      if (this.matchPattern(_string.$1) case var $0?) {
        if (this.matchPattern(_string.$37) case var $1?) {
          if (this.pos case var to) {
            return this.buffer.substring(from, to);
          }
        }
      }
    }
  };

  /// `fragment10`
  late final f1e = () {
    if (this.pos case var from) {
      if (this.matchPattern(_string.$1) case var $0?) {
        if (this.matchPattern(_string.$38) case var $1?) {
          if (this.pos case var to) {
            return this.buffer.substring(from, to);
          }
        }
      }
    }
  };

  /// `fragment11`
  late final f1f = () {
    if (this.pos case var from) {
      if (this.matchPattern(_string.$1) case var $0?) {
        if (this.matchPattern(_string.$36) case var $1?) {
          if (this.pos case var to) {
            return this.buffer.substring(from, to);
          }
        }
      }
    }
  };

  /// `fragment12`
  late final f1g = () {
    if (this.pos case var from) {
      if (this.matchPattern(_string.$1) case var $0?) {
        if (this.matchPattern(_string.$37) case var $1?) {
          if (this.pos case var to) {
            return this.buffer.substring(from, to);
          }
        }
      }
    }
  };

  /// `fragment13`
  late final f1h = () {
    if (this.pos case var from) {
      if (this.matchPattern(_string.$1) case var $0?) {
        if (this.matchPattern(_string.$38) case var $1?) {
          if (this.pos case var to) {
            return this.buffer.substring(from, to);
          }
        }
      }
    }
  };

  /// `fragment14`
  late final f1i = () {
    if (this.pos case var from) {
      if (this.matchPattern(_string.$1) case var $0?) {
        if (this.matchPattern(_string.$39) case var $1?) {
          if (this.pos case var to) {
            return this.buffer.substring(from, to);
          }
        }
      }
    }
  };

  /// `fragment15`
  late final f1j = () {
    if (this.pos case var from) {
      if (this.matchPattern(_string.$1) case var $0?) {
        if (this.matchPattern(_string.$40) case var $1?) {
          if (this.pos case var to) {
            return this.buffer.substring(from, to);
          }
        }
      }
    }
  };

  /// `fragment16`
  late final f1k = () {
    if (this.pos case var from) {
      if (this.matchPattern(_string.$1) case var $0?) {
        if (this.matchPattern(_string.$25) case var $1?) {
          if (this.pos case var to) {
            return this.buffer.substring(from, to);
          }
        }
      }
    }
  };

  /// `fragment17`
  late final f1l = () {
    if (this.pos case var from) {
      if (this.matchPattern(_string.$1) case var $0?) {
        if (this.matchPattern(_string.$41) case var $1?) {
          if (this.pos case var to) {
            return this.buffer.substring(from, to);
          }
        }
      }
    }
  };

  /// `fragment18`
  late final f1m = () {
    if (this.pos case var from) {
      if (this.matchPattern(_string.$1) case var $0?) {
        if (this.matchPattern(_string.$42) case var $1?) {
          if (this.pos case var to) {
            return this.buffer.substring(from, to);
          }
        }
      }
    }
  };

  /// `fragment19`
  late final f1n = () {
    if (this.pos case var from) {
      if (this.matchPattern(_string.$1) case var $0?) {
        if (this.matchPattern(_string.$36) case var $1?) {
          if (this.pos case var to) {
            return this.buffer.substring(from, to);
          }
        }
      }
    }
  };

  /// `fragment20`
  late final f1o = () {
    if (this.pos case var from) {
      if (this.matchPattern(_string.$1) case var $0?) {
        if (this.matchPattern(_string.$37) case var $1?) {
          if (this.pos case var to) {
            return this.buffer.substring(from, to);
          }
        }
      }
    }
  };

  /// `fragment21`
  late final f1p = () {
    if (this.pos case var from) {
      if (this.matchPattern(_string.$1) case var $0?) {
        if (this.matchPattern(_string.$38) case var $1?) {
          if (this.pos case var to) {
            return this.buffer.substring(from, to);
          }
        }
      }
    }
  };

  /// `fragment22`
  late final f1q = () {
    if (this.pos case var from) {
      if (this.matchPattern(_string.$1) case var $0?) {
        if (this.matchPattern(_string.$40) case var $1?) {
          if (this.pos case var to) {
            return this.buffer.substring(from, to);
          }
        }
      }
    }
  };

  /// `fragment23`
  late final f1r = () {
    if (this.pos case var from) {
      if (this.matchPattern(_string.$1) case var $0?) {
        if (this.matchPattern(_string.$25) case var $1?) {
          if (this.pos case var to) {
            return this.buffer.substring(from, to);
          }
        }
      }
    }
  };

  /// `fragment24`
  late final f1s = () {
    if (this.pos case var from) {
      if (this.matchPattern(_string.$1) case var $0?) {
        if (this.matchPattern(_string.$39) case var $1?) {
          if (this.pos case var to) {
            return this.buffer.substring(from, to);
          }
        }
      }
    }
  };

  /// `fragment25`
  late final f1t = () {
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

  /// `fragment26`
  late final f1u = () {
    if (this.pos case var mark) {
      if (this.pos case var mark) {
        if (this.matchPattern(_string.$43) case var $?) {
          return {(32, 32)};
        }
        this.pos = mark;
        if (this.fv() case var $0) {
          if (this.f1n() case var $1?) {
            if (this.fv() case var $2) {
              return {(48, 57)};
            }
          }
        }
        this.pos = mark;
        if (this.fv() case var $0) {
          if (this.f1o() case var $1?) {
            if (this.fv() case var $2) {
              return {(64 + 1, 64 + 26), (96 + 1, 96 + 26)};
            }
          }
        }
        this.pos = mark;
        if (this.fv() case var $0) {
          if (this.f1p() case var $1?) {
            if (this.fv() case var $2) {
              return {(9, 13), (32, 32)};
            }
          }
        }
        this.pos = mark;
        if (this.fv() case var $0) {
          if (this.f1q() case var $1?) {
            if (this.fv() case var $2) {
              return {(10, 10)};
            }
          }
        }
        this.pos = mark;
        if (this.fv() case var $0) {
          if (this.f1r() case var $1?) {
            if (this.fv() case var $2) {
              return {(13, 13)};
            }
          }
        }
        this.pos = mark;
        if (this.fv() case var $0) {
          if (this.f1s() case var $1?) {
            if (this.fv() case var $2) {
              return {(9, 9)};
            }
          }
        }
        this.pos = mark;
        if (this.fv() case var $0) {
          if (this.f1t() case var $1?) {
            if (this.fv() case var $2) {
              return {(92, 92)};
            }
          }
        }
      }

      this.pos = mark;
      if (this.f5() case var l?) {
        if (this.matchPattern(_string.$44) case _?) {
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

  /// `fragment27`
  late final f1v = () {
    if (this.fv() case _) {
      if (this.matchPattern(_string.$45) case _?) {
        if (this.f1u() case var _0?) {
          if ([_0] case (var elements && var _l1)) {
            for (;;) {
              if (this.pos case var mark) {
                if (this.fv() case _) {
                  if (this.f1u() case var _0?) {
                    _l1.add(_0);
                    continue;
                  }
                }
                this.pos = mark;
                break;
              }
            }
            if (this.matchPattern(_string.$2) case _?) {
              if (this.fv() case _) {
                return RangeNode(elements.reduce((a, b) => a.union(b)));
              }
            }
          }
        }
      }
    }
  };

  /// `fragment28`
  late final f1w = () {
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
  };

  /// `fragment29`
  late final f1x = () {
    if (this.f1w() case var _0?) {
      if ([_0] case (var $ && var _l1)) {
        for (;;) {
          if (this.pos case var mark) {
            if (this.f1w() case var _0?) {
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

  /// `fragment30`
  late final f1y = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$24) case null) {
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

  /// `fragment31`
  late final f1z = () {
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
  };

  /// `fragment32`
  late final f20 = () {
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
  };

  /// `fragment33`
  late final f21 = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$28) case null) {
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

  /// `fragment34`
  late final f22 = () {
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
        if (this.matchPattern(_string.$24) case null) {
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

  /// `fragment35`
  late final f23 = () {
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
  };

  /// `fragment36`
  late final f24 = () {
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
  };

  /// `fragment37`
  late final f25 = () {
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
        if (this.matchPattern(_string.$28) case null) {
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

  /// `fragment38`
  late final f26 = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$47) case var $0?) {
        if (this.pos case var mark) {
          if (this.f1y() case var _0) {
            if ([if (_0 case var _0?) _0] case (var $1 && var _l1)) {
              if (_l1.isNotEmpty) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.f1y() case var _0?) {
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
              if (this.matchPattern(_string.$24) case var $2?) {
                if ($1 case var $) {
                  return $.join();
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$48) case var $0?) {
        if (this.pos case var mark) {
          if (this.f1z() case var _2) {
            if ([if (_2 case var _2?) _2] case (var $1 && var _l3)) {
              if (_l3.isNotEmpty) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.f1z() case var _2?) {
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
              if (this.matchPattern(_string.$26) case var $2?) {
                if ($1 case var $) {
                  return $.join();
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$49) case var $0?) {
        if (this.pos case var mark) {
          if (this.f20() case var _4) {
            if ([if (_4 case var _4?) _4] case (var $1 && var _l5)) {
              if (_l5.isNotEmpty) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.f20() case var _4?) {
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
              if (this.matchPattern(_string.$27) case var $2?) {
                if ($1 case var $) {
                  return $.join();
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$50) case var $0?) {
        if (this.pos case var mark) {
          if (this.f21() case var _6) {
            if ([if (_6 case var _6?) _6] case (var $1 && var _l7)) {
              if (_l7.isNotEmpty) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.f21() case var _6?) {
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
              if (this.matchPattern(_string.$28) case var $2?) {
                if ($1 case var $) {
                  return $.join();
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$24) case var $0?) {
        if (this.pos case var mark) {
          if (this.f22() case var _8) {
            if ([if (_8 case var _8?) _8] case (var $1 && var _l9)) {
              if (_l9.isNotEmpty) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.f22() case var _8?) {
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
              if (this.matchPattern(_string.$24) case var $2?) {
                if ($1 case var $) {
                  return $.join();
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$26) case var $0?) {
        if (this.pos case var mark) {
          if (this.f23() case var _10) {
            if ([if (_10 case var _10?) _10] case (var $1 && var _l11)) {
              if (_l11.isNotEmpty) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.f23() case var _10?) {
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
              if (this.matchPattern(_string.$26) case var $2?) {
                if ($1 case var $) {
                  return $.join();
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$27) case var $0?) {
        if (this.pos case var mark) {
          if (this.f24() case var _12) {
            if ([if (_12 case var _12?) _12] case (var $1 && var _l13)) {
              if (_l13.isNotEmpty) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.f24() case var _12?) {
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
              if (this.matchPattern(_string.$27) case var $2?) {
                if ($1 case var $) {
                  return $.join();
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$28) case var $0?) {
        if (this.pos case var mark) {
          if (this.f25() case var _14) {
            if ([if (_14 case var _14?) _14] case (var $1 && var _l15)) {
              if (_l15.isNotEmpty) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.f25() case var _14?) {
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
              if (this.matchPattern(_string.$28) case var $2?) {
                if ($1 case var $) {
                  return $.join();
                }
              }
            }
          }
        }
      }
    }
  };

  /// `fragment39`
  late final f27 = () {
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

  /// `fragment40`
  late final f28 = () {
    if (this.pos case var mark) {
      if (this.apply(this.rh) case var $?) {
        return $;
      }
      this.pos = mark;
      if (this.matchPattern(_string.$15) case var $0?) {
        if (this.apply(this.rg)! case var $1) {
          if (this.matchPattern(_string.$14) case var $2?) {
            if ($1 case var $) {
              return "{" + $ + "}";
            }
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

  /// `fragment41`
  late final f29 = () {
    if (this.pos case var from) {
      if (this.fx() case var $?) {
        if (this.pos case var to) {
          return this.buffer.substring(from, to);
        }
      }
    }
  };

  /// `fragment42`
  late final f2a = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$15) case _?) {
        if (this.apply(this.rj)! case var $1) {
          if (this.matchPattern(_string.$14) case _?) {
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

  /// `fragment43`
  late final f2b = () {
    if (this.fm() case _?) {
      if (this.f7() case var $1?) {
        if (this.fl() case _?) {
          return $1;
        }
      }
    }
  };

  /// `fragment44`
  late final f2c = () {
    if (this.fm() case _?) {
      if (this.f7() case var $1?) {
        if (this.fl() case _?) {
          return $1;
        }
      }
    }
  };

  /// `fragment45`
  late final f2d = () {
    if (this.fs() case _?) {
      if (this.fm() case _?) {
        if (this.f7() case var $2?) {
          if (this.fl() case _?) {
            return $2;
          }
        }
      }
    }
  };

  /// `fragment46`
  late final f2e = () {
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

  /// `fragment47`
  late final f2f = () {
    if (this.matchPattern(_string.$3) case var $0?) {
      if (this.pos case var mark) {
        if (this.f2e() case var _0) {
          if ([if (_0 case var _0?) _0] case (var $1 && var _l1)) {
            if (_l1.isNotEmpty) {
              for (;;) {
                if (this.pos case var mark) {
                  if (this.f2e() case var _0?) {
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
            if (this.matchPattern(_string.$3) case var $2?) {
              if ($1 case var $) {
                return $.join();
              }
            }
          }
        }
      }
    }
  };

  /// `fragment48`
  late final f2g = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$51) case var $?) {
        return $;
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.matchPattern(_string.$11) case (var $0 && null)) {
          this.pos = mark;
          if (this.matchPattern(_string.$23) case var $1?) {
            return ($0, $1);
          }
        }
      }
    }
  };

  /// `fragment49`
  late final f2h = () {
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

  /// `fragment50`
  late final f2i = () {
    if (this.f8() case var $0?) {
      if (this.f2g() case _?) {
        if (this.pos case var mark) {
          if (this.f2h() case null) {
            this.pos = mark;
            return $0;
          }
        }
      }
    }
  };

  /// `fragment51`
  late final f2j = () {
    if (this.pos case var mark) {
      if (this.fv() case _) {
        if (this.matchPattern(_string.$52) case var $1?) {
          if (this.fv() case _) {
            return $1;
          }
        }
      }
      this.pos = mark;
      if (this.fv() case _) {
        if (this.matchPattern(_string.$53) case var $1?) {
          if (this.fv() case _) {
            return $1;
          }
        }
      }
      this.pos = mark;
      if (this.fv() case _) {
        if (this.matchPattern(_string.$54) case var $1?) {
          if (this.fv() case _) {
            return $1;
          }
        }
      }
    }
  };

  /// `fragment52`
  late final f2k = () {
    if (this.fv() case _) {
      if (this.matchPattern(_string.$55) case var $1?) {
        if (this.fv() case _) {
          return $1;
        }
      }
    }
  };

  /// `fragment53`
  late final f2l = () {
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

  /// `fragment54`
  late final f2m = () {
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

  /// `fragment55`
  late final f2n = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$24) case null) {
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

  /// `fragment56`
  late final f2o = () {
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
  };

  /// `fragment57`
  late final f2p = () {
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
  };

  /// `fragment58`
  late final f2q = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$28) case null) {
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

  /// `fragment59`
  late final f2r = () {
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
        if (this.matchPattern(_string.$29) case var $0?) {
          this.pos = mark;
          if (this.fy() case var $1?) {
            return ($0, $1);
          }
        }
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.matchPattern(_string.$24) case null) {
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

  /// `fragment60`
  late final f2s = () {
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
        if (this.matchPattern(_string.$29) case var $0?) {
          this.pos = mark;
          if (this.fy() case var $1?) {
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
  };

  /// `fragment61`
  late final f2t = () {
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
        if (this.matchPattern(_string.$29) case var $0?) {
          this.pos = mark;
          if (this.fy() case var $1?) {
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
  };

  /// `fragment62`
  late final f2u = () {
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
        if (this.matchPattern(_string.$29) case var $0?) {
          this.pos = mark;
          if (this.fy() case var $1?) {
            return ($0, $1);
          }
        }
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.matchPattern(_string.$28) case null) {
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
  late final f2v = () {
    if (this.f8() case var _0?) {
      if ([_0] case (var $ && var _l1)) {
        for (;;) {
          if (this.pos case var mark) {
            if (this.fu() case _?) {
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

  /// `fragment64`
  late final f2w = () {
    if (this.fv() case _) {
      if (this.matchPattern(_string.$56) case var $1?) {
        if (this.fv() case _) {
          return $1;
        }
      }
    }
  };

  /// `fragment65`
  late final f2x = () {
    if (this.fv() case _) {
      if (this.matchPattern(_string.$57) case var $1?) {
        if (this.fv() case _) {
          return $1;
        }
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
                if (this.fv() case _) {
                  if (this.apply(this.r2) case var _0?) {
                    _l1.add(_0);
                    continue;
                  }
                }
                this.pos = mark;
                break;
              }
            }
            if (this.fv() case _) {
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
    if (this.fm() case _?) {
      if (this.fv() case _) {
        if (this.apply(this.rf)! case var code) {
          if (this.fv() case _) {
            if (this.fl() case _?) {
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
          if (this.fm() case _?) {
            if (this.apply(this.r2) case var _0?) {
              if ([_0] case (var statements && var _l1)) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.fv() case _) {
                      if (this.apply(this.r2) case var _0?) {
                        _l1.add(_0);
                        continue;
                      }
                    }
                    this.pos = mark;
                    break;
                  }
                }
                if (this.fl() case _?) {
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
          if (this.fm() case _?) {
            if (this.apply(this.r2) case var _2?) {
              if ([_2] case (var statements && var _l3)) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.fv() case _) {
                      if (this.apply(this.r2) case var _2?) {
                        _l3.add(_2);
                        continue;
                      }
                    }
                    this.pos = mark;
                    break;
                  }
                }
                if (this.fl() case _?) {
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
          if (this.fm() case _?) {
            if (this.apply(this.r2) case var _4?) {
              if ([_4] case (var statements && var _l5)) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.fv() case _) {
                      if (this.apply(this.r2) case var _4?) {
                        _l5.add(_4);
                        continue;
                      }
                    }
                    this.pos = mark;
                    break;
                  }
                }
                if (this.fl() case _?) {
                  return NamespaceStatement(name, statements, tag: Tag.inline);
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.f8() case var name) {
        if (this.fm() case _?) {
          if (this.apply(this.r2) case var _6?) {
            if ([_6] case (var statements && var _l7)) {
              for (;;) {
                if (this.pos case var mark) {
                  if (this.fv() case _) {
                    if (this.apply(this.r2) case var _6?) {
                      _l7.add(_6);
                      continue;
                    }
                  }
                  this.pos = mark;
                  break;
                }
              }
              if (this.fl() case _?) {
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
            if (this.f14() case _?) {
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
    if (this.ft() case _) {
      if (this.apply(this.r6) case var _0?) {
        if ([_0] case (var options && var _l1)) {
          for (;;) {
            if (this.pos case var mark) {
              if (this.ft() case _?) {
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
            if (this.fv() case _) {
              if (this.f6() case var raw?) {
                if (this.fv() case _) {
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
          if (this.fm() case _?) {
            if (this.fv() case _) {
              if (this.apply(this.rf)! case var curly) {
                if (this.fv() case _) {
                  if (this.fl() case _?) {
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
          if (this.fo() case _?) {
            if (this.fn() case _?) {
              if (this.fm() case _?) {
                if (this.fv() case _) {
                  if (this.apply(this.rf)! case var curly) {
                    if (this.fv() case _) {
                      if (this.fl() case _?) {
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
            if (this.fv() case _) {
              if (this.apply(this.r8) case var _0?) {
                _l1.add(_0);
                continue;
              }
            }
            this.pos = mark;
            break;
          }
        }
        if (this.f17() case var chosen) {
          return body.length == 1 ? body.single : SequenceNode(body, choose: chosen);
        }
      }
    }
  }

  /// `global::dropped`
  Node? r8() {
    if (this.pos case var mark) {
      if (this.apply(this.ra) case var left?) {
        if (this.fj() case _?) {
          if (this.apply(this.r9) case var body?) {
            if (this.fk() case _?) {
              if (this.apply(this.ra) case var right?) {
                return SequenceNode([left, body, right], choose: 1);
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.r8) case var captured?) {
        if (this.fk() case _?) {
          if (this.apply(this.ra) case var dropped?) {
            return SequenceNode([captured, dropped], choose: 1);
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.ra) case var dropped?) {
        if (this.fj() case _?) {
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
        if (this.matchPattern(_string.$30) case _?) {
          if (this.fv() case _) {
            if (this.apply(this.ra) case var special?) {
              return NamedNode(identifier, special);
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$30) case _?) {
        if (this.f2() case var id?) {
          if (this.fp() case _?) {
            return switch ((id, id.split(ParserGenerator.separator))) {
              (var ref, [..., var name]) => NamedNode(name, OptionalNode(ReferenceNode(ref))),
              _ => null,
            };
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$30) case _?) {
        if (this.f2() case var id?) {
          if (this.fq() case _?) {
            return switch ((id, id.split(ParserGenerator.separator))) {
              (var ref, [..., var name]) => NamedNode(name, StarNode(ReferenceNode(ref))),
              _ => null,
            };
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$30) case _?) {
        if (this.f2() case var id?) {
          if (this.fr() case _?) {
            return switch ((id, id.split(ParserGenerator.separator))) {
              (var ref, [..., var name]) => NamedNode(name, PlusNode(ReferenceNode(ref))),
              _ => null,
            };
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$30) case _?) {
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
            if (this.fr() case _?) {
              return PlusSeparatedNode(sep, expr, isTrailingAllowed: false);
            }
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.rd) case var sep?) {
        if (this.fi() case _?) {
          if (this.apply(this.rd) case var expr?) {
            if (this.fq() case _?) {
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
        if (this.fp() case var $1?) {
          if ($0 case var $) {
            return OptionalNode($);
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.rb) case var $0?) {
        if (this.fq() case var $1?) {
          if ($0 case var $) {
            return StarNode($);
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.rb) case var $0?) {
        if (this.fr() case var $1?) {
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
      if (this.f18() case var $0?) {
        if (this.apply(this.rc) case var $1?) {
          if ($1 case var $) {
            return SequenceNode([NotPredicateNode($), const AnyCharacterNode()], choose: 1);
          }
        }
      }
      this.pos = mark;
      if (this.f19() case var $0?) {
        if (this.apply(this.rc) case var $1?) {
          if ($1 case var $) {
            return AndPredicateNode($);
          }
        }
      }
      this.pos = mark;
      if (this.f1a() case var $0?) {
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
          if (this.fu() case _?) {
            if (this.fg() case _?) {
              if (this.fo() case _?) {
                if (this.fn() case _?) {
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
        if (this.fu() case _?) {
          if (this.ff() case _?) {
            if (this.fo() case _?) {
              if (this.f9() case var min?) {
                if (this.fs() case _?) {
                  if (this.f9() case var max?) {
                    if (this.fn() case _?) {
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
        if (this.fu() case _?) {
          if (this.ff() case _?) {
            if (this.fo() case _?) {
              if (this.f9() case var number?) {
                if (this.fn() case _?) {
                  return CountedNode(number, number, target);
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.rd) case var target?) {
        if (this.fu() case _?) {
          if (this.ff() case _?) {
            if (this.fv() case _) {
              if (this.f9() case var number?) {
                if (this.fv() case _) {
                  return CountedNode(number, number, target);
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.rd) case var sep?) {
        if (this.fu() case _?) {
          if (this.fh() case _?) {
            if (this.fo() case _?) {
              if (this.apply(this.r5) case var body?) {
                if (this.fn() case _?) {
                  if (this.fr() case _?) {
                    if (this.fp() case _?) {
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
        if (this.fu() case _?) {
          if (this.fh() case _?) {
            if (this.fo() case _?) {
              if (this.apply(this.r5) case var body?) {
                if (this.fn() case _?) {
                  if (this.fq() case _?) {
                    if (this.fp() case _?) {
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
        if (this.fu() case _?) {
          if (this.fh() case _?) {
            if (this.fo() case _?) {
              if (this.apply(this.r5) case var body?) {
                if (this.fn() case _?) {
                  if (this.fr() case _?) {
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
        if (this.fu() case _?) {
          if (this.fh() case _?) {
            if (this.fo() case _?) {
              if (this.apply(this.r5) case var body?) {
                if (this.fn() case _?) {
                  if (this.fq() case _?) {
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
        if (this.fu() case _?) {
          if (this.fh() case _?) {
            if (this.fo() case _?) {
              if (this.apply(this.r5) case var body?) {
                if (this.fn() case _?) {
                  return PlusSeparatedNode(sep, body, isTrailingAllowed: false);
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.rd) case var sep?) {
        if (this.fu() case _?) {
          if (this.fh() case _?) {
            if (this.fv() case _) {
              if (this.apply(this.re) case var body?) {
                if (this.fv() case _) {
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
      if (this.fo() case _?) {
        if (this.apply(this.r5) case var $1?) {
          if (this.fn() case _?) {
            return $1;
          }
        }
      }
      this.pos = mark;
      if (this.fv() case var $0) {
        if (this.matchPattern(_string.$58) case var $1?) {
          if (this.fv() case var $2) {
            return const StartOfInputNode();
          }
        }
      }
      this.pos = mark;
      if (this.fv() case var $0) {
        if (this.matchPattern(_string.$29) case var $1?) {
          if (this.fv() case var $2) {
            return const EndOfInputNode();
          }
        }
      }
      this.pos = mark;
      if (this.fu() case var $?) {
        return const AnyCharacterNode();
      }
      this.pos = mark;
      if (this.fv() case var $0) {
        if (this.matchPattern(_string.$59) case var $1?) {
          if (this.fv() case var $2) {
            return const EpsilonNode();
          }
        }
      }
      this.pos = mark;
      if (this.fv() case var $0) {
        if (this.f1b() case var $1?) {
          if (this.fv() case var $2) {
            return const StringLiteralNode(r"\");
          }
        }
      }
      this.pos = mark;
      if (this.fv() case var $0) {
        if (this.f1c() case var $1?) {
          if (this.fv() case var $2) {
            return SimpleRegExpEscapeNode.digit;
          }
        }
      }
      this.pos = mark;
      if (this.fv() case var $0) {
        if (this.f1d() case var $1?) {
          if (this.fv() case var $2) {
            return SimpleRegExpEscapeNode.word;
          }
        }
      }
      this.pos = mark;
      if (this.fv() case var $0) {
        if (this.f1e() case var $1?) {
          if (this.fv() case var $2) {
            return SimpleRegExpEscapeNode.whitespace;
          }
        }
      }
      this.pos = mark;
      if (this.fv() case var $0) {
        if (this.f1f() case var $1?) {
          if (this.fv() case var $2) {
            return SimpleRegExpEscapeNode.notDigit;
          }
        }
      }
      this.pos = mark;
      if (this.fv() case var $0) {
        if (this.f1g() case var $1?) {
          if (this.fv() case var $2) {
            return SimpleRegExpEscapeNode.notWord;
          }
        }
      }
      this.pos = mark;
      if (this.fv() case var $0) {
        if (this.f1h() case var $1?) {
          if (this.fv() case var $2) {
            return SimpleRegExpEscapeNode.notWhitespace;
          }
        }
      }
      this.pos = mark;
      if (this.fv() case var $0) {
        if (this.f1i() case var $1?) {
          if (this.fv() case var $2) {
            return SimpleRegExpEscapeNode.tab;
          }
        }
      }
      this.pos = mark;
      if (this.fv() case var $0) {
        if (this.f1j() case var $1?) {
          if (this.fv() case var $2) {
            return SimpleRegExpEscapeNode.newline;
          }
        }
      }
      this.pos = mark;
      if (this.fv() case var $0) {
        if (this.f1k() case var $1?) {
          if (this.fv() case var $2) {
            return SimpleRegExpEscapeNode.carriageReturn;
          }
        }
      }
      this.pos = mark;
      if (this.fv() case var $0) {
        if (this.f1l() case var $1?) {
          if (this.fv() case var $2) {
            return SimpleRegExpEscapeNode.formFeed;
          }
        }
      }
      this.pos = mark;
      if (this.fv() case var $0) {
        if (this.f1m() case var $1?) {
          if (this.fv() case var $2) {
            return SimpleRegExpEscapeNode.verticalTab;
          }
        }
      }
      this.pos = mark;
      if (this.fv() case _) {
        if (this.f1v() case var $1?) {
          if (this.fv() case _) {
            return $1;
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$46) case var $0?) {
        if (this.f1x() case var $1?) {
          if (this.matchPattern(_string.$46) case var $2?) {
            if ($1 case var $) {
              return RegExpNode($);
            }
          }
        }
      }
      this.pos = mark;
      if (this.fv() case var $0) {
        if (this.f26() case var $1?) {
          if (this.fv() case var $2) {
            if ($1 case var $) {
              return StringLiteralNode($);
            }
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
        if (this.pos case var mark) {
          if (this.f27() case var _0) {
            if ([if (_0 case var _0?) _0] case (var $1 && var _l1)) {
              if (_l1.isNotEmpty) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.f27() case var _0?) {
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
              if (this.matchPattern(_string.$3) case var $2?) {
                if ($1 case var $) {
                  return $.join();
                }
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
  String rg() {
    if (this.pos case var mark) {
      if (this.f28() case var _0) {
        if ([if (_0 case var _0?) _0] case (var code && var _l1)) {
          if (_l1.isNotEmpty) {
            for (;;) {
              if (this.pos case var mark) {
                if (this.f28() case var _0?) {
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
    if (this.f29() case var _0?) {
      if ([_0] case (var $ && var _l1)) {
        for (;;) {
          if (this.pos case var mark) {
            if (this.fv() case _) {
              if (this.f29() case var _0?) {
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
      if (this.f2a() case var _0) {
        if ([if (_0 case var _0?) _0] case (var code && var _l1)) {
          if (_l1.isNotEmpty) {
            for (;;) {
              if (this.pos case var mark) {
                if (this.f2a() case var _0?) {
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
    if (this.fv() case _) {
      if (this.apply(this.rl) case var $1?) {
        if (this.fv() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::dart::type::nullable`
  String? rl() {
    if (this.apply(this.rm) case var nonNullable?) {
      if (this.fp() case var $1) {
        return $1 == null ? "$nonNullable" : "$nonNullable?";
      }
    }
  }

  /// `global::dart::type::nonNullable`
  String? rm() {
    if (this.pos case var mark) {
      if (this.fz() case var $?) {
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
              if (this.fu() case _?) {
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
      if (this.fo() case var $0?) {
        if (this.f2b() case var $1) {
          if (this.fn() case var $2?) {
            return "(" + ($1 == null ? "" : "{" + $1 + "}") + ")";
          }
        }
      }
      this.pos = mark;
      if (this.fo() case var $0?) {
        if (this.f11() case var $1?) {
          if (this.fs() case var $2?) {
            if (this.f2c() case var $3) {
              if (this.fn() case var $4?) {
                return "(" + $1 + ", " + ($3 == null ? "" : "{" + $3 + "}") + ")";
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.fo() case var $0?) {
        if (this.f13() case var $1?) {
          if (this.f2d() case var $2) {
            if (this.fn() case var $3?) {
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
    ParserGenerator.separator,
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
