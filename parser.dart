// ignore_for_file: type=lint, body_might_complete_normally_nullable, unused_local_variable, inference_failure_on_function_return_type, unused_import, duplicate_ignore

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
final class GrammarParser extends _PegParser<ParserGenerator> {
  GrammarParser();

  @override
  get start => r0;

  /// `global::type`
  String? f0() {
    if (this.pos case var mark) {
      if (this.fp() case _) {
        if (this.f2c() case var $1?) {
          if (this.fp() case _) {
            return $1;
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.rl) case var $?) {
        return $;
      }
    }
  }

  /// `global::namespaceReference`
  String f1() {
    if (this.pos case var mark) {
      if (this.f2f() case var _0) {
        if ([if (_0 case var _0?) _0] case (var $ && var _l1)) {
          if (_l1.isNotEmpty) {
            for (;;) {
              if (this.pos case var mark) {
                if (this.f2f() case var _0?) {
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

  /// `global::name`
  List<String>? f2() {
    if (this.pos case var mark) {
      if (this.fi() case _?) {
        if (this.f3() case var _0?) {
          if ([_0] case (var $1 && var _l1)) {
            for (;;) {
              if (this.pos case var mark) {
                if (this.fm() case _?) {
                  if (this.f3() case var _0?) {
                    _l1.add(_0);
                    continue;
                  }
                }
                this.pos = mark;
                break;
              }
            }
            if (this.fh() case _?) {
              return $1;
            }
          }
        }
      }
      this.pos = mark;
      if (this.f3() case var $?) {
        return [$];
      }
    }
  }

  /// `global::singleName`
  String? f3() {
    if (this.pos case var mark) {
      if (this.f1() case var $0) {
        if (this.f2h() case var $1?) {
          if ([$0, $1] case var $) {
            return $0.isEmpty ? $1 : "${$0}::${$1}";
          }
        }
      }
      this.pos = mark;
      if (this.f4() case var $?) {
        return $;
      }
    }
  }

  /// `global::namespacedIdentifier`
  String? f4() {
    if (this.f1() case var $0) {
      if (this.f7() case var $1?) {
        if ([$0, $1] case var $) {
          return $0.isEmpty ? $1 : "${$0}::${$1}";
        }
      }
    }
  }

  /// `global::body`
  Node? f5() {
    if (this.f2i() case _?) {
      if (this.apply(this.r5) case var choice?) {
        if (this.f2j() case _?) {
          return choice;
        }
      }
    }
  }

  /// `global::literal::range::atom`
  String? f6() {
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

  /// `global::identifier`
  String? f7() {
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
  int? f8() {
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
  Tag? f9() {
    if (this.pos case var mark) {
      if (this.fp() case _) {
        if (this.matchPattern(_string.$3) case _?) {
          if (this.fp() case _) {
            return Tag.rule;
          }
        }
      }
      this.pos = mark;
      if (this.fp() case _) {
        if (this.matchPattern(_string.$4) case _?) {
          if (this.fp() case _) {
            return Tag.fragment;
          }
        }
      }
      this.pos = mark;
      if (this.fp() case _) {
        if (this.matchPattern(_string.$5) case _?) {
          if (this.fp() case _) {
            return Tag.inline;
          }
        }
      }
    }
  }

  /// `global::kw::var`
  String? fa() {
    if (this.fp() case _) {
      if (this.matchPattern(_string.$6) case var $1?) {
        if (this.fp() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::mac::range`
  String? fb() {
    if (this.fp() case _) {
      if (this.matchPattern(_string.$7) case var $1?) {
        if (this.fp() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::mac::flat`
  String? fc() {
    if (this.fp() case _) {
      if (this.matchPattern(_string.$8) case var $1?) {
        if (this.fp() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::mac::sep`
  String? fd() {
    if (this.fp() case _) {
      if (this.matchPattern(_string.$9) case var $1?) {
        if (this.fp() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::..`
  String? fe() {
    if (this.fp() case _) {
      if (this.matchPattern(_string.$10) case var $1?) {
        if (this.fp() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::}`
  String? ff() {
    if (this.fp() case _) {
      if (this.matchPattern(_string.$11) case var $1?) {
        if (this.fp() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::{`
  String? fg() {
    if (this.fp() case _) {
      if (this.matchPattern(_string.$12) case var $1?) {
        if (this.fp() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::)`
  String? fh() {
    if (this.fp() case _) {
      if (this.matchPattern(_string.$13) case var $1?) {
        if (this.fp() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::(`
  String? fi() {
    if (this.fp() case _) {
      if (this.matchPattern(_string.$14) case var $1?) {
        if (this.fp() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::?`
  String? fj() {
    if (this.fp() case _) {
      if (this.matchPattern(_string.$15) case var $1?) {
        if (this.fp() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::*`
  String? fk() {
    if (this.fp() case _) {
      if (this.matchPattern(_string.$16) case var $1?) {
        if (this.fp() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::+`
  String? fl() {
    if (this.fp() case _) {
      if (this.matchPattern(_string.$17) case var $1?) {
        if (this.fp() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::,`
  String? fm() {
    if (this.fp() case _) {
      if (this.matchPattern(_string.$18) case var $1?) {
        if (this.fp() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::|`
  String? fn() {
    if (this.fp() case _) {
      if (this.matchPattern(_string.$19) case var $1?) {
        if (this.fp() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::.`
  String? fo() {
    if (this.fp() case _) {
      if (this.matchPattern(_string.$20) case var $1?) {
        if (this.fp() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::_`
  String fp() {
    if (this.pos case var mark) {
      if (this.f2k() case var _0) {
        if ([if (_0 case var _0?) _0] case var _l1) {
          if (_l1.isNotEmpty) {
            for (;;) {
              if (this.pos case var mark) {
                if (this.f2k() case var _0?) {
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
  ParserGenerator? fq() {
    if (this.apply(this.r0) case var $?) {
      return $;
    }
  }

  /// `global::dart::literal::string::body`
  late final fr = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$22) case _?) {
        if (this.matchPattern(_string.$21) case _?) {
          if (this.pos case var mark) {
            if (this.f2l() case var _0) {
              if ([if (_0 case var _0?) _0] case var _l1) {
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
                if (this.matchPattern(_string.$21) case _?) {
                  return ();
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$22) case _?) {
        if (this.matchPattern(_string.$23) case _?) {
          if (this.pos case var mark) {
            if (this.f2m() case var _2) {
              if ([if (_2 case var _2?) _2] case var _l3) {
                if (_l3.isNotEmpty) {
                  for (;;) {
                    if (this.pos case var mark) {
                      if (this.f2m() case var _2?) {
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
                if (this.matchPattern(_string.$23) case _?) {
                  return ();
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$22) case _?) {
        if (this.matchPattern(_string.$24) case _?) {
          if (this.pos case var mark) {
            if (this.f2n() case var _4) {
              if ([if (_4 case var _4?) _4] case var _l5) {
                if (_l5.isNotEmpty) {
                  for (;;) {
                    if (this.pos case var mark) {
                      if (this.f2n() case var _4?) {
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
                if (this.matchPattern(_string.$24) case _?) {
                  return ();
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$22) case _?) {
        if (this.matchPattern(_string.$25) case _?) {
          if (this.pos case var mark) {
            if (this.f2o() case var _6) {
              if ([if (_6 case var _6?) _6] case var _l7) {
                if (_l7.isNotEmpty) {
                  for (;;) {
                    if (this.pos case var mark) {
                      if (this.f2o() case var _6?) {
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
                if (this.matchPattern(_string.$25) case _?) {
                  return ();
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$21) case _?) {
        if (this.pos case var mark) {
          if (this.f2p() case var _8) {
            if ([if (_8 case var _8?) _8] case var _l9) {
              if (_l9.isNotEmpty) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.f2p() case var _8?) {
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
              if (this.matchPattern(_string.$21) case _?) {
                return ();
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$23) case _?) {
        if (this.pos case var mark) {
          if (this.f2q() case var _10) {
            if ([if (_10 case var _10?) _10] case var _l11) {
              if (_l11.isNotEmpty) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.f2q() case var _10?) {
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
              if (this.matchPattern(_string.$23) case _?) {
                return ();
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$24) case _?) {
        if (this.pos case var mark) {
          if (this.f2r() case var _12) {
            if ([if (_12 case var _12?) _12] case var _l13) {
              if (_l13.isNotEmpty) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.f2r() case var _12?) {
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
              if (this.matchPattern(_string.$24) case _?) {
                return ();
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$25) case _?) {
        if (this.pos case var mark) {
          if (this.f2s() case var _14) {
            if ([if (_14 case var _14?) _14] case var _l15) {
              if (_l15.isNotEmpty) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.f2s() case var _14?) {
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
              if (this.matchPattern(_string.$25) case _?) {
                return ();
              }
            }
          }
        }
      }
    }
  };

  /// `global::dart::literal::string::interpolation`
  late final fs = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$26) case var $0?) {
        if (this.matchPattern(_string.$12) case var $1?) {
          if (this.apply(this.rk)! case var $2) {
            if (this.matchPattern(_string.$11) case var $3?) {
              return ($0, $1, $2, $3);
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$26) case var $0?) {
        if (this.apply(this.rj) case var $1?) {
          return ($0, $1);
        }
      }
    }
  };

  /// `fragment0`
  late final ft = () {
    if (this.fp() case _) {
      if (this.matchPattern(_string.$27) case var $1?) {
        if (this.fp() case _) {
          return $1;
        }
      }
    }
  };

  /// `fragment1`
  late final fu = () {
    if (this.fp() case _) {
      if (this.matchPattern(_string.$28) case var $1?) {
        if (this.fp() case _) {
          return $1;
        }
      }
    }
  };

  /// `fragment2`
  late final fv = () {
    if (this.fp() case _) {
      if (this.matchPattern(_string.$29) case var $1?) {
        if (this.fp() case _) {
          return $1;
        }
      }
    }
  };

  /// `fragment3`
  late final fw = () {
    if (this.fv() case _?) {
      if (this.f8() case var $1?) {
        return $1;
      }
    }
  };

  /// `fragment4`
  late final fx = () {
    if (this.fp() case _) {
      if (this.matchPattern(_string.$30) case var $1?) {
        if (this.fp() case _) {
          return $1;
        }
      }
    }
  };

  /// `fragment5`
  late final fy = () {
    if (this.fp() case _) {
      if (this.matchPattern(_string.$31) case var $1?) {
        if (this.fp() case _) {
          return $1;
        }
      }
    }
  };

  /// `fragment6`
  late final fz = () {
    if (this.fp() case _) {
      if (this.matchPattern(_string.$32) case var $1?) {
        if (this.fp() case _) {
          return $1;
        }
      }
    }
  };

  /// `fragment7`
  late final f10 = () {
    if (this.fp() case _) {
      if (this.matchPattern(_string.$33) case var $1?) {
        if (this.fp() case _) {
          return $1;
        }
      }
    }
  };

  /// `fragment8`
  late final f11 = () {
    if (this.fp() case _) {
      if (this.matchPattern(_string.$34) case var $1?) {
        if (this.fp() case _) {
          return $1;
        }
      }
    }
  };

  /// `fragment9`
  late final f12 = () {
    if (this.pos case var from) {
      if (this.matchPattern(_string.$1) case _?) {
        if (this.matchPattern(_string.$1) case _?) {
          if (this.pos case var to) {
            return this.buffer.substring(from, to);
          }
        }
      }
    }
  };

  /// `fragment10`
  late final f13 = () {
    if (this.pos case var from) {
      if (this.matchPattern(_string.$1) case _?) {
        if (this.matchPattern(_string.$35) case _?) {
          if (this.pos case var to) {
            return this.buffer.substring(from, to);
          }
        }
      }
    }
  };

  /// `fragment11`
  late final f14 = () {
    if (this.pos case var from) {
      if (this.matchPattern(_string.$1) case _?) {
        if (this.matchPattern(_string.$36) case _?) {
          if (this.pos case var to) {
            return this.buffer.substring(from, to);
          }
        }
      }
    }
  };

  /// `fragment12`
  late final f15 = () {
    if (this.pos case var from) {
      if (this.matchPattern(_string.$1) case _?) {
        if (this.matchPattern(_string.$37) case _?) {
          if (this.pos case var to) {
            return this.buffer.substring(from, to);
          }
        }
      }
    }
  };

  /// `fragment13`
  late final f16 = () {
    if (this.pos case var from) {
      if (this.matchPattern(_string.$1) case _?) {
        if (this.matchPattern(_string.$35) case _?) {
          if (this.pos case var to) {
            return this.buffer.substring(from, to);
          }
        }
      }
    }
  };

  /// `fragment14`
  late final f17 = () {
    if (this.pos case var from) {
      if (this.matchPattern(_string.$1) case _?) {
        if (this.matchPattern(_string.$36) case _?) {
          if (this.pos case var to) {
            return this.buffer.substring(from, to);
          }
        }
      }
    }
  };

  /// `fragment15`
  late final f18 = () {
    if (this.pos case var from) {
      if (this.matchPattern(_string.$1) case _?) {
        if (this.matchPattern(_string.$37) case _?) {
          if (this.pos case var to) {
            return this.buffer.substring(from, to);
          }
        }
      }
    }
  };

  /// `fragment16`
  late final f19 = () {
    if (this.pos case var from) {
      if (this.matchPattern(_string.$1) case _?) {
        if (this.matchPattern(_string.$38) case _?) {
          if (this.pos case var to) {
            return this.buffer.substring(from, to);
          }
        }
      }
    }
  };

  /// `fragment17`
  late final f1a = () {
    if (this.pos case var from) {
      if (this.matchPattern(_string.$1) case _?) {
        if (this.matchPattern(_string.$39) case _?) {
          if (this.pos case var to) {
            return this.buffer.substring(from, to);
          }
        }
      }
    }
  };

  /// `fragment18`
  late final f1b = () {
    if (this.pos case var from) {
      if (this.matchPattern(_string.$1) case _?) {
        if (this.matchPattern(_string.$22) case _?) {
          if (this.pos case var to) {
            return this.buffer.substring(from, to);
          }
        }
      }
    }
  };

  /// `fragment19`
  late final f1c = () {
    if (this.pos case var from) {
      if (this.matchPattern(_string.$1) case _?) {
        if (this.matchPattern(_string.$40) case _?) {
          if (this.pos case var to) {
            return this.buffer.substring(from, to);
          }
        }
      }
    }
  };

  /// `fragment20`
  late final f1d = () {
    if (this.pos case var from) {
      if (this.matchPattern(_string.$1) case _?) {
        if (this.matchPattern(_string.$41) case _?) {
          if (this.pos case var to) {
            return this.buffer.substring(from, to);
          }
        }
      }
    }
  };

  /// `fragment21`
  late final f1e = () {
    if (this.pos case var from) {
      if (this.matchPattern(_string.$1) case _?) {
        if (this.matchPattern(_string.$35) case _?) {
          if (this.pos case var to) {
            return this.buffer.substring(from, to);
          }
        }
      }
    }
  };

  /// `fragment22`
  late final f1f = () {
    if (this.pos case var from) {
      if (this.matchPattern(_string.$1) case _?) {
        if (this.matchPattern(_string.$36) case _?) {
          if (this.pos case var to) {
            return this.buffer.substring(from, to);
          }
        }
      }
    }
  };

  /// `fragment23`
  late final f1g = () {
    if (this.pos case var from) {
      if (this.matchPattern(_string.$1) case _?) {
        if (this.matchPattern(_string.$37) case _?) {
          if (this.pos case var to) {
            return this.buffer.substring(from, to);
          }
        }
      }
    }
  };

  /// `fragment24`
  late final f1h = () {
    if (this.pos case var from) {
      if (this.matchPattern(_string.$1) case _?) {
        if (this.matchPattern(_string.$39) case _?) {
          if (this.pos case var to) {
            return this.buffer.substring(from, to);
          }
        }
      }
    }
  };

  /// `fragment25`
  late final f1i = () {
    if (this.pos case var from) {
      if (this.matchPattern(_string.$1) case _?) {
        if (this.matchPattern(_string.$22) case _?) {
          if (this.pos case var to) {
            return this.buffer.substring(from, to);
          }
        }
      }
    }
  };

  /// `fragment26`
  late final f1j = () {
    if (this.pos case var from) {
      if (this.matchPattern(_string.$1) case _?) {
        if (this.matchPattern(_string.$38) case _?) {
          if (this.pos case var to) {
            return this.buffer.substring(from, to);
          }
        }
      }
    }
  };

  /// `fragment27`
  late final f1k = () {
    if (this.pos case var from) {
      if (this.matchPattern(_string.$1) case _?) {
        if (this.matchPattern(_string.$1) case _?) {
          if (this.pos case var to) {
            return this.buffer.substring(from, to);
          }
        }
      }
    }
  };

  /// `fragment28`
  late final f1l = () {
    if (this.pos case var mark) {
      if (this.pos case var mark) {
        if (this.matchPattern(_string.$42) case var $?) {
          return {(32, 32)};
        }
        this.pos = mark;
        if (this.fp() case _) {
          if (this.f1e() case _?) {
            if (this.fp() case _) {
              return {(48, 57)};
            }
          }
        }
        this.pos = mark;
        if (this.fp() case _) {
          if (this.f1f() case _?) {
            if (this.fp() case _) {
              return {(64 + 1, 64 + 26), (96 + 1, 96 + 26)};
            }
          }
        }
        this.pos = mark;
        if (this.fp() case _) {
          if (this.f1g() case _?) {
            if (this.fp() case _) {
              return {(9, 13), (32, 32)};
            }
          }
        }
        this.pos = mark;
        if (this.fp() case _) {
          if (this.f1h() case _?) {
            if (this.fp() case _) {
              return {(10, 10)};
            }
          }
        }
        this.pos = mark;
        if (this.fp() case _) {
          if (this.f1i() case _?) {
            if (this.fp() case _) {
              return {(13, 13)};
            }
          }
        }
        this.pos = mark;
        if (this.fp() case _) {
          if (this.f1j() case _?) {
            if (this.fp() case _) {
              return {(9, 9)};
            }
          }
        }
        this.pos = mark;
        if (this.fp() case _) {
          if (this.f1k() case _?) {
            if (this.fp() case _) {
              return {(92, 92)};
            }
          }
        }
      }
      this.pos = mark;
      if (this.f6() case var l?) {
        if (this.matchPattern(_string.$43) case _?) {
          if (this.f6() case var r?) {
            return {(l.codeUnitAt(0), r.codeUnitAt(0))};
          }
        }
      }
      this.pos = mark;
      if (this.f6() case var $?) {
        return {($.codeUnitAt(0), $.codeUnitAt(0))};
      }
    }
  };

  /// `fragment29`
  late final f1m = () {
    if (this.fp() case _) {
      if (this.matchPattern(_string.$44) case _?) {
        if (this.f1l() case var _0?) {
          if ([_0] case (var elements && var _l1)) {
            for (;;) {
              if (this.pos case var mark) {
                if (this.fp() case _) {
                  if (this.f1l() case var _0?) {
                    _l1.add(_0);
                    continue;
                  }
                }
                this.pos = mark;
                break;
              }
            }
            if (this.matchPattern(_string.$2) case _?) {
              if (this.fp() case _) {
                return RangeNode(elements.reduce((a, b) => a.union(b)));
              }
            }
          }
        }
      }
    }
  };

  /// `fragment30`
  late final f1n = () {
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
        if (this.matchPattern(_string.$45) case null) {
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

  /// `fragment31`
  late final f1o = () {
    if (this.f1n() case var _0?) {
      if ([_0] case (var $ && var _l1)) {
        for (;;) {
          if (this.pos case var mark) {
            if (this.f1n() case var _0?) {
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

  /// `fragment32`
  late final f1p = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$21) case null) {
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
  late final f1q = () {
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
  };

  /// `fragment34`
  late final f1r = () {
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

  /// `fragment35`
  late final f1s = () {
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
  };

  /// `fragment36`
  late final f1t = () {
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
        if (this.matchPattern(_string.$21) case null) {
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
  late final f1u = () {
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
  };

  /// `fragment38`
  late final f1v = () {
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

  /// `fragment39`
  late final f1w = () {
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
  };

  /// `fragment40`
  late final f1x = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$46) case var $0?) {
        if (this.pos case var mark) {
          if (this.f1p() case var _0) {
            if ([if (_0 case var _0?) _0] case (var $1 && var _l1)) {
              if (_l1.isNotEmpty) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.f1p() case var _0?) {
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
              if (this.matchPattern(_string.$21) case var $2?) {
                if ($1 case var $) {
                  return $.join();
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$47) case var $0?) {
        if (this.pos case var mark) {
          if (this.f1q() case var _2) {
            if ([if (_2 case var _2?) _2] case (var $1 && var _l3)) {
              if (_l3.isNotEmpty) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.f1q() case var _2?) {
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
              if (this.matchPattern(_string.$23) case var $2?) {
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
          if (this.f1r() case var _4) {
            if ([if (_4 case var _4?) _4] case (var $1 && var _l5)) {
              if (_l5.isNotEmpty) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.f1r() case var _4?) {
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
      if (this.matchPattern(_string.$49) case var $0?) {
        if (this.pos case var mark) {
          if (this.f1s() case var _6) {
            if ([if (_6 case var _6?) _6] case (var $1 && var _l7)) {
              if (_l7.isNotEmpty) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.f1s() case var _6?) {
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
              if (this.matchPattern(_string.$25) case var $2?) {
                if ($1 case var $) {
                  return $.join();
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$21) case var $0?) {
        if (this.pos case var mark) {
          if (this.f1t() case var _8) {
            if ([if (_8 case var _8?) _8] case (var $1 && var _l9)) {
              if (_l9.isNotEmpty) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.f1t() case var _8?) {
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
              if (this.matchPattern(_string.$21) case var $2?) {
                if ($1 case var $) {
                  return $.join();
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$23) case var $0?) {
        if (this.pos case var mark) {
          if (this.f1u() case var _10) {
            if ([if (_10 case var _10?) _10] case (var $1 && var _l11)) {
              if (_l11.isNotEmpty) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.f1u() case var _10?) {
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
              if (this.matchPattern(_string.$23) case var $2?) {
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
          if (this.f1v() case var _12) {
            if ([if (_12 case var _12?) _12] case (var $1 && var _l13)) {
              if (_l13.isNotEmpty) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.f1v() case var _12?) {
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
      if (this.matchPattern(_string.$25) case var $0?) {
        if (this.pos case var mark) {
          if (this.f1w() case var _14) {
            if ([if (_14 case var _14?) _14] case (var $1 && var _l15)) {
              if (_l15.isNotEmpty) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.f1w() case var _14?) {
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
              if (this.matchPattern(_string.$25) case var $2?) {
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

  /// `fragment41`
  late final f1y = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$50) case null) {
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

  /// `fragment42`
  late final f1z = () {
    if (this.pos case var mark) {
      if (this.apply(this.ri) case var $?) {
        return $;
      }
      this.pos = mark;
      if (this.matchPattern(_string.$12) case var $0?) {
        if (this.apply(this.rh)! case var $1) {
          if (this.matchPattern(_string.$11) case var $2?) {
            if ($1 case var $) {
              return "{" + $ + "}";
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$14) case var $0?) {
        if (this.apply(this.rh)! case var $1) {
          if (this.matchPattern(_string.$13) case var $2?) {
            if ($1 case var $) {
              return "(" + $ + ")";
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$44) case var $0?) {
        if (this.apply(this.rh)! case var $1) {
          if (this.matchPattern(_string.$2) case var $2?) {
            if ($1 case var $) {
              return "[" + $ + "]";
            }
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

  /// `fragment43`
  late final f20 = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$50) case null) {
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

  /// `fragment44`
  late final f21 = () {
    if (this.pos case var mark) {
      if (matchPattern(_regexp.$2) case var $?) {
        return $;
      }
      this.pos = mark;
      if (this.matchPattern(_string.$51) case var $?) {
        return $;
      }
    }
  };

  /// `fragment45`
  late final f22 = () {
    if (this.pos case var mark) {
      if (this.apply(this.ri) case var $?) {
        return $;
      }
      this.pos = mark;
      if (this.matchPattern(_string.$12) case var $0?) {
        if (this.apply(this.rh)! case var $1) {
          if (this.matchPattern(_string.$11) case var $2?) {
            if ($1 case var $) {
              return "{" + $ + "}";
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$14) case var $0?) {
        if (this.apply(this.rh)! case var $1) {
          if (this.matchPattern(_string.$13) case var $2?) {
            if ($1 case var $) {
              return "(" + $ + ")";
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$44) case var $0?) {
        if (this.apply(this.rh)! case var $1) {
          if (this.matchPattern(_string.$2) case var $2?) {
            if ($1 case var $) {
              return "[" + $ + "]";
            }
          }
        }
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.f21() case null) {
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

  /// `fragment46`
  late final f23 = () {
    if (this.pos case var mark) {
      if (this.apply(this.ri) case var $?) {
        return $;
      }
      this.pos = mark;
      if (this.matchPattern(_string.$12) case var $0?) {
        if (this.apply(this.rh)! case var $1) {
          if (this.matchPattern(_string.$11) case var $2?) {
            if ($1 case var $) {
              return "{" + $ + "}";
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$14) case var $0?) {
        if (this.apply(this.rh)! case var $1) {
          if (this.matchPattern(_string.$13) case var $2?) {
            if ($1 case var $) {
              return "(" + $ + ")";
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$44) case var $0?) {
        if (this.apply(this.rh)! case var $1) {
          if (this.matchPattern(_string.$2) case var $2?) {
            if ($1 case var $) {
              return "[" + $ + "]";
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

  /// `fragment47`
  late final f24 = () {
    if (this.pos case var from) {
      if (this.fr() case var $?) {
        if (this.pos case var to) {
          return this.buffer.substring(from, to);
        }
      }
    }
  };

  /// `fragment48`
  late final f25 = () {
    if (this.pos case var mark) {
      if (this.apply(this.ri) case var $?) {
        return $;
      }
      this.pos = mark;
      if (this.matchPattern(_string.$12) case var $0?) {
        if (this.apply(this.rk)! case var $1) {
          if (this.matchPattern(_string.$11) case var $2?) {
            if ($1 case var $) {
              return "{" + $ + "}";
            }
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

  /// `fragment49`
  late final f26 = () {
    if (this.fp() case _) {
      if (this.matchPattern(_string.$52) case var $1?) {
        if (this.fp() case _) {
          return $1;
        }
      }
    }
  };

  /// `fragment50`
  late final f27 = () {
    if (this.fp() case _) {
      if (this.matchPattern(_string.$53) case var $1?) {
        if (this.fp() case _) {
          return $1;
        }
      }
    }
  };

  /// `fragment51`
  late final f28 = () {
    if (this.fp() case _) {
      if (this.matchPattern(_string.$54) case var $1?) {
        if (this.fp() case _) {
          return $1;
        }
      }
    }
  };

  /// `fragment52`
  late final f29 = () {
    if (this.fp() case _) {
      if (this.matchPattern(_string.$44) case var $1?) {
        if (this.fp() case _) {
          return $1;
        }
      }
    }
  };

  /// `fragment53`
  late final f2a = () {
    if (this.fp() case _) {
      if (this.matchPattern(_string.$2) case var $1?) {
        if (this.fp() case _) {
          return $1;
        }
      }
    }
  };

  /// `fragment54`
  late final f2b = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$50) case null) {
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

  /// `fragment55`
  late final f2c = () {
    if (this.matchPattern(_string.$50) case var $0?) {
      if (this.pos case var mark) {
        if (this.f2b() case var _0) {
          if ([if (_0 case var _0?) _0] case (var $1 && var _l1)) {
            if (_l1.isNotEmpty) {
              for (;;) {
                if (this.pos case var mark) {
                  if (this.f2b() case var _0?) {
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
            if (this.matchPattern(_string.$50) case var $2?) {
              if ($1 case var $) {
                return $.join();
              }
            }
          }
        }
      }
    }
  };

  /// `fragment56`
  late final f2d = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$55) case var $?) {
        return $;
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.matchPattern(_string.$10) case (var $0 && null)) {
          this.pos = mark;
          if (this.matchPattern(_string.$20) case var $1?) {
            return ($0, $1);
          }
        }
      }
    }
  };

  /// `fragment57`
  late final f2e = () {
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
  };

  /// `fragment58`
  late final f2f = () {
    if (this.f7() case var $0?) {
      if (this.f2d() case _?) {
        if (this.pos case var mark) {
          if (this.f2e() case null) {
            this.pos = mark;
            return $0;
          }
        }
      }
    }
  };

  /// `fragment59`
  late final f2g = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$50) case null) {
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

  /// `fragment60`
  late final f2h = () {
    if (this.matchPattern(_string.$50) case var $0?) {
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
            if (this.matchPattern(_string.$50) case var $2?) {
              if ($1 case var $) {
                return $.join();
              }
            }
          }
        }
      }
    }
  };

  /// `fragment61`
  late final f2i = () {
    if (this.pos case var mark) {
      if (this.fp() case _) {
        if (this.matchPattern(_string.$56) case var $1?) {
          if (this.fp() case _) {
            return $1;
          }
        }
      }
      this.pos = mark;
      if (this.fp() case _) {
        if (this.matchPattern(_string.$57) case var $1?) {
          if (this.fp() case _) {
            return $1;
          }
        }
      }
      this.pos = mark;
      if (this.fp() case _) {
        if (this.matchPattern(_string.$58) case var $1?) {
          if (this.fp() case _) {
            return $1;
          }
        }
      }
    }
  };

  /// `fragment62`
  late final f2j = () {
    if (this.fp() case _) {
      if (this.matchPattern(_string.$51) case var $1?) {
        if (this.fp() case _) {
          return $1;
        }
      }
    }
  };

  /// `fragment63`
  late final f2k = () {
    if (this.pos case var mark) {
      if (matchPattern(_regexp.$3) case var $?) {
        return $;
      }
      this.pos = mark;
      if (matchPattern(_regexp.$4) case var $?) {
        return $;
      }
      this.pos = mark;
      if (matchPattern(_regexp.$5) case var $?) {
        return $;
      }
    }
  };

  /// `fragment64`
  late final f2l = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$21) case null) {
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

  /// `fragment65`
  late final f2m = () {
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
  };

  /// `fragment66`
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

  /// `fragment67`
  late final f2o = () {
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
  };

  /// `fragment68`
  late final f2p = () {
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
        if (this.matchPattern(_string.$26) case var $0?) {
          this.pos = mark;
          if (this.fs() case var $1?) {
            return ($0, $1);
          }
        }
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.matchPattern(_string.$21) case null) {
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

  /// `fragment69`
  late final f2q = () {
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
        if (this.matchPattern(_string.$26) case var $0?) {
          this.pos = mark;
          if (this.fs() case var $1?) {
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
  };

  /// `fragment70`
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
        if (this.matchPattern(_string.$26) case var $0?) {
          this.pos = mark;
          if (this.fs() case var $1?) {
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

  /// `fragment71`
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
        if (this.matchPattern(_string.$26) case var $0?) {
          this.pos = mark;
          if (this.fs() case var $1?) {
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
  };

  /// `global::document`
  ParserGenerator? r0() {
    if (this.pos <= 0) {
      if (this.apply(this.r1) case var preamble) {
        if (this.apply(this.r2) case var _0?) {
          if ([_0] case (var statements && var _l1)) {
            for (;;) {
              if (this.pos case var mark) {
                if (this.fp() case _) {
                  if (this.apply(this.r2) case var _0?) {
                    _l1.add(_0);
                    continue;
                  }
                }
                this.pos = mark;
                break;
              }
            }
            if (this.fp() case _) {
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
    if (this.fg() case _?) {
      if (this.fp() case _) {
        if (this.apply(this.rf)! case var code) {
          if (this.fp() case _) {
            if (this.ff() case _?) {
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
    if (this.f9() case var decorator) {
      if (this.f7() case var name) {
        if (this.fg() case _?) {
          if (this.apply(this.r2) case var _0?) {
            if ([_0] case (var statements && var _l1)) {
              for (;;) {
                if (this.pos case var mark) {
                  if (this.fp() case _) {
                    if (this.apply(this.r2) case var _0?) {
                      _l1.add(_0);
                      continue;
                    }
                  }
                  this.pos = mark;
                  break;
                }
              }
              if (this.ff() case _?) {
                return NamespaceStatement(name, statements, tag: decorator);
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
      if (this.f9() case var decorator) {
        if (this.fa() case _) {
          if (this.f2() case var name?) {
            if (this.f5() case var body?) {
              return DeclarationStatement(null, name, body, tag: decorator);
            }
          }
        }
      }
      this.pos = mark;
      if (this.f9() case var decorator) {
        if (this.f0() case var type?) {
          if (this.f2() case var name?) {
            if (this.f5() case var body?) {
              return DeclarationStatement(type, name, body, tag: decorator);
            }
          }
        }
      }
      this.pos = mark;
      if (this.f9() case var decorator) {
        if (this.fa() case _) {
          if (this.f2() case var name?) {
            if (this.ft() case _?) {
              if (this.f0() case var type?) {
                if (this.f5() case var body?) {
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
    if (this.fn() case _) {
      if (this.apply(this.r6) case var _0?) {
        if ([_0] case (var options && var _l1)) {
          for (;;) {
            if (this.pos case var mark) {
              if (this.fn() case _?) {
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
          if (this.fu() case _?) {
            if (this.fp() case _) {
              if (this.apply(this.rg)! case var code) {
                if (this.fp() case _) {
                  if (this.pos case var to) {
                    return InlineActionNode(
                      sequence,
                      code.trimRight(),
                      areIndicesProvided:
                          code.contains(_regexps.from) && code.contains(_regexps.to),
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
          if (this.fg() case _?) {
            if (this.fp() case _) {
              if (this.apply(this.rf)! case var curly) {
                if (this.fp() case _) {
                  if (this.ff() case _?) {
                    if (this.pos case var to) {
                      return InlineActionNode(
                        sequence,
                        curly.trimRight(),
                        areIndicesProvided:
                            curly.contains(_regexps.from) && curly.contains(_regexps.to),
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
          if (this.fi() case _?) {
            if (this.fh() case _?) {
              if (this.fg() case _?) {
                if (this.fp() case _) {
                  if (this.apply(this.rf)! case var curly) {
                    if (this.fp() case _) {
                      if (this.ff() case _?) {
                        if (this.pos case var to) {
                          return ActionNode(
                            sequence,
                            curly.trimRight(),
                            areIndicesProvided:
                                curly.contains(_regexps.from) && curly.contains(_regexps.to),
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
            if (this.fp() case _) {
              if (this.apply(this.r8) case var _0?) {
                _l1.add(_0);
                continue;
              }
            }
            this.pos = mark;
            break;
          }
        }
        if (this.fw() case var chosen) {
          return body.length == 1 ? body.single : SequenceNode(body, chosenIndex: chosen);
        }
      }
    }
  }

  /// `global::dropped`
  Node? r8() {
    if (this.pos case var mark) {
      if (this.apply(this.r8) case var captured?) {
        if (this.fx() case _?) {
          if (this.apply(this.ra) case var dropped?) {
            return SequenceNode([captured, dropped], chosenIndex: 0);
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.ra) case var dropped?) {
        if (this.fy() case _?) {
          if (this.apply(this.r8) case var captured?) {
            return SequenceNode([dropped, captured], chosenIndex: 1);
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
      if (this.f7() case var identifier?) {
        if (this.matchPattern(_string.$27) case _?) {
          if (this.fp() case _) {
            if (this.apply(this.ra) case var special?) {
              return NamedNode(identifier, special);
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$27) case _?) {
        if (this.f4() case var id?) {
          if (this.fj() case _?) {
            return switch ((id, id.split(ParserGenerator.separator))) {
              (var ref, [..., var name]) => NamedNode(name, OptionalNode(ReferenceNode(ref))),
              _ => null,
            };
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$27) case _?) {
        if (this.f4() case var id?) {
          if (this.fk() case _?) {
            return switch ((id, id.split(ParserGenerator.separator))) {
              (var ref, [..., var name]) => NamedNode(name, StarNode(ReferenceNode(ref))),
              _ => null,
            };
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$27) case _?) {
        if (this.f4() case var id?) {
          if (this.fl() case _?) {
            return switch ((id, id.split(ParserGenerator.separator))) {
              (var ref, [..., var name]) => NamedNode(name, PlusNode(ReferenceNode(ref))),
              _ => null,
            };
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$27) case _?) {
        if (this.f4() case var id?) {
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
        if (this.fe() case _?) {
          if (this.apply(this.rd) case var expr?) {
            if (this.fl() case _?) {
              if (this.fj() case _?) {
                return PlusSeparatedNode(sep, expr, isTrailingAllowed: true);
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.rd) case var sep?) {
        if (this.fe() case _?) {
          if (this.apply(this.rd) case var expr?) {
            if (this.fk() case _?) {
              if (this.fj() case _?) {
                return StarSeparatedNode(sep, expr, isTrailingAllowed: true);
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.rd) case var sep?) {
        if (this.fe() case _?) {
          if (this.apply(this.rd) case var expr?) {
            if (this.fl() case _?) {
              return PlusSeparatedNode(sep, expr, isTrailingAllowed: false);
            }
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.rd) case var sep?) {
        if (this.fe() case _?) {
          if (this.apply(this.rd) case var expr?) {
            if (this.fk() case _?) {
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
        if (this.fj() case var $1?) {
          if ($0 case var $) {
            return OptionalNode($);
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.rb) case var $0?) {
        if (this.fk() case var $1?) {
          if ($0 case var $) {
            return StarNode($);
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.rb) case var $0?) {
        if (this.fl() case var $1?) {
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
      if (this.f8() case var min?) {
        if (this.fe() case _?) {
          if (this.f8() case var max) {
            if (this.apply(this.re) case var body?) {
              return CountedNode(min, max, body);
            }
          }
        }
      }
      this.pos = mark;
      if (this.f8() case var number?) {
        if (this.apply(this.re) case var body?) {
          return CountedNode(number, number, body);
        }
      }
      this.pos = mark;
      if (this.fz() case var $0?) {
        if (this.apply(this.rc) case var $1?) {
          if ($1 case var $) {
            return SequenceNode([NotPredicateNode($), const AnyCharacterNode()], chosenIndex: 1);
          }
        }
      }
      this.pos = mark;
      if (this.f10() case var $0?) {
        if (this.apply(this.rc) case var $1?) {
          if ($1 case var $) {
            return AndPredicateNode($);
          }
        }
      }
      this.pos = mark;
      if (this.f11() case var $0?) {
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
          if (this.fo() case _?) {
            if (this.fc() case _?) {
              if (this.fi() case _?) {
                if (this.fh() case _?) {
                  if (this.pos case var to) {
                    return InlineActionNode(
                      target,
                      "this.buffer.substring(from, to)",
                      areIndicesProvided: true,
                    );
                  }
                }
              }
            }
          }
        }
      }

      this.pos = mark;
      if (this.apply(this.rd) case var target?) {
        if (this.fo() case _?) {
          if (this.fb() case _?) {
            if (this.fi() case _?) {
              if (this.f8() case var min?) {
                if (this.fm() case _?) {
                  if (this.f8() case var max?) {
                    if (this.fh() case _?) {
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
        if (this.fo() case _?) {
          if (this.fb() case _?) {
            if (this.fi() case _?) {
              if (this.f8() case var number?) {
                if (this.fh() case _?) {
                  return CountedNode(number, number, target);
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.rd) case var target?) {
        if (this.fo() case _?) {
          if (this.fb() case _?) {
            if (this.fp() case _) {
              if (this.f8() case var number?) {
                if (this.fp() case _) {
                  return CountedNode(number, number, target);
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.rd) case var sep?) {
        if (this.fo() case _?) {
          if (this.fd() case _?) {
            if (this.fi() case _?) {
              if (this.apply(this.r5) case var body?) {
                if (this.fh() case _?) {
                  if (this.fl() case _?) {
                    if (this.fj() case _?) {
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
        if (this.fo() case _?) {
          if (this.fd() case _?) {
            if (this.fi() case _?) {
              if (this.apply(this.r5) case var body?) {
                if (this.fh() case _?) {
                  if (this.fk() case _?) {
                    if (this.fj() case _?) {
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
        if (this.fo() case _?) {
          if (this.fd() case _?) {
            if (this.fi() case _?) {
              if (this.apply(this.r5) case var body?) {
                if (this.fh() case _?) {
                  if (this.fl() case _?) {
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
        if (this.fo() case _?) {
          if (this.fd() case _?) {
            if (this.fi() case _?) {
              if (this.apply(this.r5) case var body?) {
                if (this.fh() case _?) {
                  if (this.fk() case _?) {
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
        if (this.fo() case _?) {
          if (this.fd() case _?) {
            if (this.fi() case _?) {
              if (this.apply(this.r5) case var body?) {
                if (this.fh() case _?) {
                  return PlusSeparatedNode(sep, body, isTrailingAllowed: false);
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.rd) case var sep?) {
        if (this.fo() case _?) {
          if (this.fd() case _?) {
            if (this.fp() case _) {
              if (this.apply(this.re) case var body?) {
                if (this.fp() case _) {
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
      if (this.fi() case _?) {
        if (this.apply(this.r5) case var $1?) {
          if (this.fh() case _?) {
            return $1;
          }
        }
      }
      this.pos = mark;
      if (this.fp() case _) {
        if (this.matchPattern(_string.$59) case _?) {
          if (this.fp() case _) {
            return const StartOfInputNode();
          }
        }
      }
      this.pos = mark;
      if (this.fp() case _) {
        if (this.matchPattern(_string.$26) case _?) {
          if (this.fp() case _) {
            return const EndOfInputNode();
          }
        }
      }
      this.pos = mark;
      if (this.fo() case var $?) {
        return const AnyCharacterNode();
      }
      this.pos = mark;
      if (this.fp() case _) {
        if (this.matchPattern(_string.$60) case _?) {
          if (this.fp() case _) {
            return const EpsilonNode();
          }
        }
      }
      this.pos = mark;
      if (this.fp() case _) {
        if (this.f12() case _?) {
          if (this.fp() case _) {
            return const StringLiteralNode(r"\");
          }
        }
      }
      this.pos = mark;
      if (this.fp() case _) {
        if (this.f13() case _?) {
          if (this.fp() case _) {
            return SimpleRegExpEscapeNode.digit;
          }
        }
      }
      this.pos = mark;
      if (this.fp() case _) {
        if (this.f14() case _?) {
          if (this.fp() case _) {
            return SimpleRegExpEscapeNode.word;
          }
        }
      }
      this.pos = mark;
      if (this.fp() case _) {
        if (this.f15() case _?) {
          if (this.fp() case _) {
            return SimpleRegExpEscapeNode.whitespace;
          }
        }
      }
      this.pos = mark;
      if (this.fp() case _) {
        if (this.f16() case _?) {
          if (this.fp() case _) {
            return SimpleRegExpEscapeNode.notDigit;
          }
        }
      }
      this.pos = mark;
      if (this.fp() case _) {
        if (this.f17() case _?) {
          if (this.fp() case _) {
            return SimpleRegExpEscapeNode.notWord;
          }
        }
      }
      this.pos = mark;
      if (this.fp() case _) {
        if (this.f18() case _?) {
          if (this.fp() case _) {
            return SimpleRegExpEscapeNode.notWhitespace;
          }
        }
      }
      this.pos = mark;
      if (this.fp() case _) {
        if (this.f19() case _?) {
          if (this.fp() case _) {
            return SimpleRegExpEscapeNode.tab;
          }
        }
      }
      this.pos = mark;
      if (this.fp() case _) {
        if (this.f1a() case _?) {
          if (this.fp() case _) {
            return SimpleRegExpEscapeNode.newline;
          }
        }
      }
      this.pos = mark;
      if (this.fp() case _) {
        if (this.f1b() case _?) {
          if (this.fp() case _) {
            return SimpleRegExpEscapeNode.carriageReturn;
          }
        }
      }
      this.pos = mark;
      if (this.fp() case _) {
        if (this.f1c() case _?) {
          if (this.fp() case _) {
            return SimpleRegExpEscapeNode.formFeed;
          }
        }
      }
      this.pos = mark;
      if (this.fp() case _) {
        if (this.f1d() case _?) {
          if (this.fp() case _) {
            return SimpleRegExpEscapeNode.verticalTab;
          }
        }
      }
      this.pos = mark;
      if (this.fp() case _) {
        if (this.f1m() case var $1?) {
          if (this.fp() case _) {
            return $1;
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$45) case var $0?) {
        if (this.f1o() case var $1?) {
          if (this.matchPattern(_string.$45) case var $2?) {
            if ($1 case var $) {
              return RegExpNode($);
            }
          }
        }
      }
      this.pos = mark;
      if (this.fp() case var $0) {
        if (this.f1x() case var $1?) {
          if (this.fp() case var $2) {
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
      if (this.matchPattern(_string.$50) case var $0?) {
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
              if (this.matchPattern(_string.$50) case var $2?) {
                if ($1 case var $) {
                  return $.join();
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.f1z() case var _2) {
          if ([if (_2 case var _2?) _2] case (var code && var _l3)) {
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
            return code.join();
          }
        }
      }
    }
  }

  /// `global::code::nl`
  String rg() {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$50) case var $0?) {
        if (this.pos case var mark) {
          if (this.f20() case var _0) {
            if ([if (_0 case var _0?) _0] case (var $1 && var _l1)) {
              if (_l1.isNotEmpty) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.f20() case var _0?) {
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
              if (this.matchPattern(_string.$50) case var $2?) {
                if ($1 case var $) {
                  return $.join();
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.f22() case var _2) {
          if ([if (_2 case var _2?) _2] case (var code && var _l3)) {
            if (_l3.isNotEmpty) {
              for (;;) {
                if (this.pos case var mark) {
                  if (this.f22() case var _2?) {
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
            return code.join();
          }
        }
      }
    }
  }

  /// `global::code::balanced`
  String rh() {
    if (this.pos case var mark) {
      if (this.f23() case var _0) {
        if ([if (_0 case var _0?) _0] case (var code && var _l1)) {
          if (_l1.isNotEmpty) {
            for (;;) {
              if (this.pos case var mark) {
                if (this.f23() case var _0?) {
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
  String? ri() {
    if (this.f24() case var _0?) {
      if ([_0] case (var $ && var _l1)) {
        for (;;) {
          if (this.pos case var mark) {
            if (this.fp() case _) {
              if (this.f24() case var _0?) {
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
  String? rj() {
    if (this.pos case var from) {
      if (this.f7() case var $?) {
        if (this.pos case var to) {
          return this.buffer.substring(from, to);
        }
      }
    }
  }

  /// `global::dart::literal::string::balanced`
  String rk() {
    if (this.pos case var mark) {
      if (this.f25() case var _0) {
        if ([if (_0 case var _0?) _0] case (var code && var _l1)) {
          if (_l1.isNotEmpty) {
            for (;;) {
              if (this.pos case var mark) {
                if (this.f25() case var _0?) {
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

  /// `global::dart::type::main`
  String? rl() {
    if (this.fp() case _) {
      if (this.apply(this.rm) case var $1?) {
        if (this.fp() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::dart::type::type`
  String? rm() {
    if (this.pos case var mark) {
      if (this.apply(this.rq) case var parameters?) {
        if (this.f26() case _?) {
          if (this.apply(this.rm) case var type?) {
            return "$type Function$parameters";
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.rm) case var type?) {
        if (this.fp() case var $1) {
          if (this.matchPattern(_string.$61) case var $2?) {
            if (this.apply(this.rq) case var parameters?) {
              if (this.fj() case var $4) {
                if ([type, $1, $2, parameters, $4] case var $) {
                  return "$type Function$parameters${$4 ?? " "}";
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.rn) case var $?) {
        return $;
      }
    }
  }

  /// `global::dart::type::nullable`
  String? rn() {
    if (this.apply(this.ro) case var nonNullable?) {
      if (this.fj() case var $1) {
        return $1 == null ? "$nonNullable" : "$nonNullable?";
      }
    }
  }

  /// `global::dart::type::nonNullable`
  String? ro() {
    if (this.pos case var mark) {
      if (this.apply(this.rr) case var $?) {
        return $;
      }
      this.pos = mark;
      if (this.apply(this.rp) case var $?) {
        return $;
      }
      this.pos = mark;
      if (this.apply(this.rt) case var $?) {
        return $;
      }
    }
  }

  /// `global::dart::type::record`
  String? rp() {
    if (this.pos case var mark) {
      if (this.fi() case _?) {
        if (this.apply(this.rw) case var positional?) {
          if (this.fm() case _?) {
            if (this.apply(this.rv) case var named?) {
              if (this.fh() case _?) {
                return "(" + positional + ", " + named + ")";
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.fi() case _?) {
        if (this.apply(this.rw) case var positional?) {
          if (this.fm() case _) {
            if (this.fh() case _?) {
              return "(" + positional + ")";
            }
          }
        }
      }
      this.pos = mark;
      if (this.fi() case _?) {
        if (this.apply(this.rv) case var named?) {
          if (this.fh() case _?) {
            return "(" + named + ")";
          }
        }
      }
      this.pos = mark;
      if (this.fi() case _?) {
        if (this.fh() case _?) {
          return "()";
        }
      }
    }
  }

  /// `global::dart::type::function_parameters`
  String? rq() {
    if (this.pos case var mark) {
      if (this.fi() case _?) {
        if (this.apply(this.rw) case var positional?) {
          if (this.fm() case _?) {
            if (this.apply(this.rv) case var named?) {
              if (this.fh() case _?) {
                return "($positional, $named)";
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.fi() case _?) {
        if (this.apply(this.rw) case var positional?) {
          if (this.fm() case _?) {
            if (this.apply(this.ru) case var optional?) {
              if (this.fh() case _?) {
                return "($positional, $optional)";
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.fi() case _?) {
        if (this.apply(this.rw) case var positional?) {
          if (this.fm() case _) {
            if (this.fh() case _?) {
              return "($positional)";
            }
          }
        }
      }
      this.pos = mark;
      if (this.fi() case _?) {
        if (this.apply(this.rv) case var named?) {
          if (this.fh() case _?) {
            return "($named)";
          }
        }
      }
      this.pos = mark;
      if (this.fi() case _?) {
        if (this.apply(this.ru) case var optional?) {
          if (this.fh() case _?) {
            return "($optional)";
          }
        }
      }
      this.pos = mark;
      if (this.fi() case _?) {
        if (this.fh() case _?) {
          return "()";
        }
      }
    }
  }

  /// `global::dart::type::generic`
  String? rr() {
    if (this.apply(this.rt) case var base?) {
      if (this.f27() case _?) {
        if (this.apply(this.rs) case var arguments?) {
          if (this.f28() case _?) {
            return "$base<$arguments>";
          }
        }
      }
    }
  }

  /// `global::dart::type::arguments`
  String? rs() {
    if (this.apply(this.rm) case var _0?) {
      if ([_0] case (var $ && var _l1)) {
        for (;;) {
          if (this.pos case var mark) {
            if (this.fm() case _?) {
              if (this.apply(this.rm) case var _0?) {
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

  /// `global::dart::type::base`
  String? rt() {
    if (this.f7() case var _0?) {
      if ([_0] case (var $ && var _l1)) {
        for (;;) {
          if (this.pos case var mark) {
            if (this.fo() case _?) {
              if (this.f7() case var _0?) {
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

  /// `global::dart::type::parameters::optional`
  String? ru() {
    if (this.f29() case _?) {
      if (this.apply(this.rw) case var $1?) {
        if (this.fm() case _) {
          if (this.f2a() case _?) {
            return "[" + $1 + "]";
          }
        }
      }
    }
  }

  /// `global::dart::type::parameters::named`
  String? rv() {
    if (this.fg() case _?) {
      if (this.apply(this.rx) case var $1?) {
        if (this.fm() case _) {
          if (this.ff() case _?) {
            return "{" + $1 + "}";
          }
        }
      }
    }
  }

  /// `global::dart::type::fields::positional`
  String? rw() {
    if (this.apply(this.ry) case var _0?) {
      if ([_0] case (var $ && var _l1)) {
        for (;;) {
          if (this.pos case var mark) {
            if (this.fm() case _?) {
              if (this.apply(this.ry) case var _0?) {
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

  /// `global::dart::type::fields::named`
  String? rx() {
    if (this.apply(this.rz) case var _0?) {
      if ([_0] case (var $ && var _l1)) {
        for (;;) {
          if (this.pos case var mark) {
            if (this.fm() case _?) {
              if (this.apply(this.rz) case var _0?) {
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
  String? ry() {
    if (this.apply(this.rm) case var $0?) {
      if (this.fp() case var $1) {
        if (this.f7() case var $2) {
          if ([$0, $1, $2] case var $) {
            return "${$0} ${$2 ?? ""}".trimRight();
          }
        }
      }
    }
  }

  /// `global::dart::type::field::named`
  String? rz() {
    if (this.apply(this.rm) case var $0?) {
      if (this.fp() case var $1) {
        if (this.f7() case var $2?) {
          if ([$0, $1, $2] case var $) {
            return "${$0} ${$2}";
          }
        }
      }
    }
  }

  static final _regexp = (
    RegExp("\\d"),
    RegExp("\\n"),
    RegExp("\\s+"),
    RegExp("\\/{2}(?:(?!(?:(?:\\r?\\n)|(?:\$))).)*(?=(?:\\r?\\n)|(?:\$))"),
    RegExp("(?:\\/\\*(?:(?!\\*\\/).)*\\*\\/)"),
  );
  static final _trie = (Trie.from(["}", ")", "]"]),);
  static const _string = (
    "\\",
    "]",
    "@rule",
    "@fragment",
    "@inline",
    "var",
    "range!",
    "flat!",
    "sep!",
    "..",
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
    "|>",
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
    "`",
    ";",
    "=>",
    "<",
    ">",
    "::",
    "=",
    "<-",
    "->",
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
