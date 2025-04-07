// ignore_for_file: type=lint, body_might_complete_normally_nullable, unused_local_variable, inference_failure_on_function_return_type, unused_import, duplicate_ignore

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
    l.head ??= _Head<T>(rule: r, evalSet: <_Rule<void>>{}, involvedSet: <_Rule<void>>{});

    for (_Lr<void> lr in _lrStack.takeWhile((lr) => lr.head != l.head)) {
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
final class CstGrammarParser extends _PegParser<Object> {
  CstGrammarParser();

  @override
  get start => r0;


  /// `global::literal::range::atom`
  Object? f0() {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$1) case var $0?) {
        if (this.pos < this.buffer.length) {
          if (this.buffer[this.pos] case var $1) {
            this.pos++;
            if ([$0, $1] case var $) {
              return ("<literal::range::atom>", $);
            }
          }
        }
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.matchPattern(_string.$2) case (var $0 && null)) {
          this.pos = mark;
          if (this.pos < this.buffer.length) {
            if (this.buffer[this.pos] case var $1) {
              this.pos++;
              if ([$0, $1] case var $) {
                return ("<literal::range::atom>", $);
              }
            }
          }
        }
      }
    }
  }

  /// `global::type`
  Object? f1() {
    if (this.pos case var mark) {
      if (this.fq() case var $0) {
        if (this.f2e() case var $1?) {
          if (this.fq() case var $2) {
            if ([$0, $1, $2] case var $) {
              return ("<type>", $);
            }
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.rl) case var $?) {
        return ("<type>", $);
      }
    }
  }

  /// `global::namespaceReference`
  Object f2() {
    if (this.pos case var mark) {
      if (this.f2h() case var _0) {
        if ([if (_0 case var _0?) _0] case (var $ && var _l1)) {
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
          return ("<namespaceReference>", $);
        }
      }
    }
  }

  /// `global::name`
  Object? f3() {
    if (this.pos case var mark) {
      if (this.fi() case var $0?) {
        if (this.f4() case var _0?) {
          if ([_0] case (var $1 && var _l1)) {
            for (;;) {
              if (this.pos case var mark) {
                if (this.fm() case _?) {
                  if (this.f4() case var _0?) {
                    _l1.add(_0);
                    continue;
                  }
                }
                this.pos = mark;
                break;
              }
            }
            if (this.fh() case var $2?) {
              if ([$0, $1, $2] case var $) {
                return ("<name>", $);
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.f4() case var $?) {
        return ("<name>", $);
      }
    }
  }

  /// `global::singleName`
  Object? f4() {
    if (this.pos case var mark) {
      if (this.f2() case var $0) {
        if (this.f2j() case var $1?) {
          if ([$0, $1] case var $) {
            return ("<singleName>", $);
          }
        }
      }
      this.pos = mark;
      if (this.f5() case var $?) {
        return ("<singleName>", $);
      }
    }
  }

  /// `global::namespacedIdentifier`
  Object? f5() {
    if (this.f2() case var $0) {
      if (this.f7() case var $1?) {
        if ([$0, $1] case var $) {
          return ("<namespacedIdentifier>", $);
        }
      }
    }
  }

  /// `global::body`
  Object? f6() {
    if (this.f2l() case var $0?) {
      if (this.apply(this.r5) case var choice?) {
        if (this.f2m() case var $2?) {
          if ([$0, choice, $2] case var $) {
            return ("<body>", $);
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
            if ([$0, $1] case var $) {
              return ("<identifier>", $);
            }
          }
        }
      }
    }
  }

  /// `global::number`
  Object? f8() {
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
        return ("<number>", $);
      }
    }
  }

  /// `global::kw::decorator`
  Object? f9() {
    if (this.pos case var mark) {
      if (this.fq() case var $0) {
        if (this.matchPattern(_string.$3) case var $1?) {
          if (this.fq() case var $2) {
            if ([$0, $1, $2] case var $) {
              return ("<kw::decorator>", $);
            }
          }
        }
      }
      this.pos = mark;
      if (this.fq() case var $0) {
        if (this.matchPattern(_string.$4) case var $1?) {
          if (this.fq() case var $2) {
            if ([$0, $1, $2] case var $) {
              return ("<kw::decorator>", $);
            }
          }
        }
      }
      this.pos = mark;
      if (this.fq() case var $0) {
        if (this.matchPattern(_string.$5) case var $1?) {
          if (this.fq() case var $2) {
            if ([$0, $1, $2] case var $) {
              return ("<kw::decorator>", $);
            }
          }
        }
      }
    }
  }

  /// `global::kw::var`
  Object? fa() {
    if (this.fq() case var $0) {
      if (this.matchPattern(_string.$6) case var $1?) {
        if (this.fq() case var $2) {
          if ([$0, $1, $2] case var $) {
            return ("<kw::var>", $);
          }
        }
      }
    }
  }

  /// `global::mac::range`
  Object? fb() {
    if (this.fq() case var $0) {
      if (this.matchPattern(_string.$7) case var $1?) {
        if (this.fq() case var $2) {
          if ([$0, $1, $2] case var $) {
            return ("<mac::range>", $);
          }
        }
      }
    }
  }

  /// `global::mac::flat`
  Object? fc() {
    if (this.fq() case var $0) {
      if (this.matchPattern(_string.$8) case var $1?) {
        if (this.fq() case var $2) {
          if ([$0, $1, $2] case var $) {
            return ("<mac::flat>", $);
          }
        }
      }
    }
  }

  /// `global::mac::sep`
  Object? fd() {
    if (this.fq() case var $0) {
      if (this.matchPattern(_string.$9) case var $1?) {
        if (this.fq() case var $2) {
          if ([$0, $1, $2] case var $) {
            return ("<mac::sep>", $);
          }
        }
      }
    }
  }

  /// `global::..`
  Object? fe() {
    if (this.fq() case var $0) {
      if (this.matchPattern(_string.$10) case var $1?) {
        if (this.fq() case var $2) {
          if ([$0, $1, $2] case var $) {
            return ("<..>", $);
          }
        }
      }
    }
  }

  /// `global::}`
  Object? ff() {
    if (this.fq() case var $0) {
      if (this.matchPattern(_string.$11) case var $1?) {
        if (this.fq() case var $2) {
          if ([$0, $1, $2] case var $) {
            return ("<}>", $);
          }
        }
      }
    }
  }

  /// `global::{`
  Object? fg() {
    if (this.fq() case var $0) {
      if (this.matchPattern(_string.$12) case var $1?) {
        if (this.fq() case var $2) {
          if ([$0, $1, $2] case var $) {
            return ("<{>", $);
          }
        }
      }
    }
  }

  /// `global::)`
  Object? fh() {
    if (this.fq() case var $0) {
      if (this.matchPattern(_string.$13) case var $1?) {
        if (this.fq() case var $2) {
          if ([$0, $1, $2] case var $) {
            return ("<)>", $);
          }
        }
      }
    }
  }

  /// `global::(`
  Object? fi() {
    if (this.fq() case var $0) {
      if (this.matchPattern(_string.$14) case var $1?) {
        if (this.fq() case var $2) {
          if ([$0, $1, $2] case var $) {
            return ("<(>", $);
          }
        }
      }
    }
  }

  /// `global::?`
  Object? fj() {
    if (this.fq() case var $0) {
      if (this.matchPattern(_string.$15) case var $1?) {
        if (this.fq() case var $2) {
          if ([$0, $1, $2] case var $) {
            return ("<?>", $);
          }
        }
      }
    }
  }

  /// `global::*`
  Object? fk() {
    if (this.fq() case var $0) {
      if (this.matchPattern(_string.$16) case var $1?) {
        if (this.fq() case var $2) {
          if ([$0, $1, $2] case var $) {
            return ("<*>", $);
          }
        }
      }
    }
  }

  /// `global::+`
  Object? fl() {
    if (this.fq() case var $0) {
      if (this.matchPattern(_string.$17) case var $1?) {
        if (this.fq() case var $2) {
          if ([$0, $1, $2] case var $) {
            return ("<+>", $);
          }
        }
      }
    }
  }

  /// `global::,`
  Object? fm() {
    if (this.fq() case var $0) {
      if (this.matchPattern(_string.$18) case var $1?) {
        if (this.fq() case var $2) {
          if ([$0, $1, $2] case var $) {
            return ("<,>", $);
          }
        }
      }
    }
  }

  /// `global:::`
  Object? fn() {
    if (this.fq() case var $0) {
      if (this.matchPattern(_string.$19) case var $1?) {
        if (this.fq() case var $2) {
          if ([$0, $1, $2] case var $) {
            return ("<:>", $);
          }
        }
      }
    }
  }

  /// `global::|`
  Object? fo() {
    if (this.fq() case var $0) {
      if (this.matchPattern(_string.$20) case var $1?) {
        if (this.fq() case var $2) {
          if ([$0, $1, $2] case var $) {
            return ("<|>", $);
          }
        }
      }
    }
  }

  /// `global::.`
  Object? fp() {
    if (this.fq() case var $0) {
      if (this.matchPattern(_string.$21) case var $1?) {
        if (this.fq() case var $2) {
          if ([$0, $1, $2] case var $) {
            return ("<.>", $);
          }
        }
      }
    }
  }

  /// `global::_`
  Object fq() {
    if (this.pos case var mark) {
      if (this.f2n() case var _0) {
        if ([if (_0 case var _0?) _0] case (var $ && var _l1)) {
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
          return ("<_>", $);
        }
      }
    }
  }

  /// `ROOT`
  Object? fr() {
    if (this.apply(this.r0) case var $?) {
      return ("<ROOT>", $);
    }
  }

  /// `global::dart::literal::string::body`
  Object? fs() {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$23) case var $0?) {
        if (this.matchPattern(_string.$22) case var $1?) {
          if (this.pos case var mark) {
            if (this.f2o() case var _0) {
              if ([if (_0 case var _0?) _0] case (var $2 && var _l1)) {
                if (_l1.isNotEmpty) {
                  for (;;) {
                    if (this.pos case var mark) {
                      if (this.f2o() case var _0?) {
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
                if (this.matchPattern(_string.$22) case var $3?) {
                  if ([$0, $1, $2, $3] case var $) {
                    return ("<dart::literal::string::body>", $);
                  }
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$23) case var $0?) {
        if (this.matchPattern(_string.$24) case var $1?) {
          if (this.pos case var mark) {
            if (this.f2p() case var _2) {
              if ([if (_2 case var _2?) _2] case (var $2 && var _l3)) {
                if (_l3.isNotEmpty) {
                  for (;;) {
                    if (this.pos case var mark) {
                      if (this.f2p() case var _2?) {
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
                if (this.matchPattern(_string.$24) case var $3?) {
                  if ([$0, $1, $2, $3] case var $) {
                    return ("<dart::literal::string::body>", $);
                  }
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$23) case var $0?) {
        if (this.matchPattern(_string.$25) case var $1?) {
          if (this.pos case var mark) {
            if (this.f2q() case var _4) {
              if ([if (_4 case var _4?) _4] case (var $2 && var _l5)) {
                if (_l5.isNotEmpty) {
                  for (;;) {
                    if (this.pos case var mark) {
                      if (this.f2q() case var _4?) {
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
                if (this.matchPattern(_string.$25) case var $3?) {
                  if ([$0, $1, $2, $3] case var $) {
                    return ("<dart::literal::string::body>", $);
                  }
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$23) case var $0?) {
        if (this.matchPattern(_string.$26) case var $1?) {
          if (this.pos case var mark) {
            if (this.f2r() case var _6) {
              if ([if (_6 case var _6?) _6] case (var $2 && var _l7)) {
                if (_l7.isNotEmpty) {
                  for (;;) {
                    if (this.pos case var mark) {
                      if (this.f2r() case var _6?) {
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
                if (this.matchPattern(_string.$26) case var $3?) {
                  if ([$0, $1, $2, $3] case var $) {
                    return ("<dart::literal::string::body>", $);
                  }
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$22) case var $0?) {
        if (this.pos case var mark) {
          if (this.f2s() case var _8) {
            if ([if (_8 case var _8?) _8] case (var $1 && var _l9)) {
              if (_l9.isNotEmpty) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.f2s() case var _8?) {
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
              if (this.matchPattern(_string.$22) case var $2?) {
                if ([$0, $1, $2] case var $) {
                  return ("<dart::literal::string::body>", $);
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$24) case var $0?) {
        if (this.pos case var mark) {
          if (this.f2t() case var _10) {
            if ([if (_10 case var _10?) _10] case (var $1 && var _l11)) {
              if (_l11.isNotEmpty) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.f2t() case var _10?) {
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
              if (this.matchPattern(_string.$24) case var $2?) {
                if ([$0, $1, $2] case var $) {
                  return ("<dart::literal::string::body>", $);
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$25) case var $0?) {
        if (this.pos case var mark) {
          if (this.f2u() case var _12) {
            if ([if (_12 case var _12?) _12] case (var $1 && var _l13)) {
              if (_l13.isNotEmpty) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.f2u() case var _12?) {
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
              if (this.matchPattern(_string.$25) case var $2?) {
                if ([$0, $1, $2] case var $) {
                  return ("<dart::literal::string::body>", $);
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$26) case var $0?) {
        if (this.pos case var mark) {
          if (this.f2v() case var _14) {
            if ([if (_14 case var _14?) _14] case (var $1 && var _l15)) {
              if (_l15.isNotEmpty) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.f2v() case var _14?) {
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
              if (this.matchPattern(_string.$26) case var $2?) {
                if ([$0, $1, $2] case var $) {
                  return ("<dart::literal::string::body>", $);
                }
              }
            }
          }
        }
      }
    }
  }

  /// `global::dart::literal::string::interpolation`
  Object? ft() {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$27) case var $0?) {
        if (this.matchPattern(_string.$12) case var $1?) {
          if (this.apply(this.rk)! case var $2) {
            if (this.matchPattern(_string.$11) case var $3?) {
              if ([$0, $1, $2, $3] case var $) {
                return ("<dart::literal::string::interpolation>", $);
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$27) case var $0?) {
        if (this.apply(this.rj) case var $1?) {
          if ([$0, $1] case var $) {
            return ("<dart::literal::string::interpolation>", $);
          }
        }
      }
    }
  }

  /// `fragment0`
  Object? fu() {
    if (this.fo() case var $0?) {
      if (this.fo() case var $1) {
        if ([$0, $1] case var $) {
          return $;
        }
      }
    }
  }

  /// `fragment1`
  Object? fv() {
    if (this.fo() case var $0?) {
      if (this.fo() case var $1) {
        if ([$0, $1] case var $) {
          return $;
        }
      }
    }
  }

  /// `fragment2`
  Object? fw() {
    if (this.fq() case var $0) {
      if (this.matchPattern(_string.$28) case var $1?) {
        if (this.fq() case var $2) {
          if ([$0, $1, $2] case var $) {
            return $;
          }
        }
      }
    }
  }

  /// `fragment3`
  Object? fx() {
    if (this.fq() case var $0) {
      if (this.matchPattern(_string.$29) case var $1?) {
        if (this.fq() case var $2) {
          if ([$0, $1, $2] case var $) {
            return $;
          }
        }
      }
    }
  }

  /// `fragment4`
  Object? fy() {
    if (this.fx() case var $0?) {
      if (this.f8() case var $1?) {
        if ([$0, $1] case var $) {
          return $;
        }
      }
    }
  }

  /// `fragment5`
  Object? fz() {
    if (this.fq() case var $0) {
      if (this.matchPattern(_string.$30) case var $1?) {
        if (this.fq() case var $2) {
          if ([$0, $1, $2] case var $) {
            return $;
          }
        }
      }
    }
  }

  /// `fragment6`
  Object? f10() {
    if (this.fq() case var $0) {
      if (this.matchPattern(_string.$31) case var $1?) {
        if (this.fq() case var $2) {
          if ([$0, $1, $2] case var $) {
            return $;
          }
        }
      }
    }
  }

  /// `fragment7`
  Object? f11() {
    if (this.fq() case var $0) {
      if (this.matchPattern(_string.$32) case var $1?) {
        if (this.fq() case var $2) {
          if ([$0, $1, $2] case var $) {
            return $;
          }
        }
      }
    }
  }

  /// `fragment8`
  Object? f12() {
    if (this.fq() case var $0) {
      if (this.matchPattern(_string.$33) case var $1?) {
        if (this.fq() case var $2) {
          if ([$0, $1, $2] case var $) {
            return $;
          }
        }
      }
    }
  }

  /// `fragment9`
  Object? f13() {
    if (this.fq() case var $0) {
      if (this.matchPattern(_string.$34) case var $1?) {
        if (this.fq() case var $2) {
          if ([$0, $1, $2] case var $) {
            return $;
          }
        }
      }
    }
  }

  /// `fragment10`
  Object? f14() {
    if (this.matchPattern(_string.$1) case var $0?) {
      if (this.matchPattern(_string.$1) case var $1?) {
        if ([$0, $1] case var $) {
          return $;
        }
      }
    }
  }

  /// `fragment11`
  Object? f15() {
    if (this.matchPattern(_string.$1) case var $0?) {
      if (this.matchPattern(_string.$35) case var $1?) {
        if ([$0, $1] case var $) {
          return $;
        }
      }
    }
  }

  /// `fragment12`
  Object? f16() {
    if (this.matchPattern(_string.$1) case var $0?) {
      if (this.matchPattern(_string.$36) case var $1?) {
        if ([$0, $1] case var $) {
          return $;
        }
      }
    }
  }

  /// `fragment13`
  Object? f17() {
    if (this.matchPattern(_string.$1) case var $0?) {
      if (this.matchPattern(_string.$37) case var $1?) {
        if ([$0, $1] case var $) {
          return $;
        }
      }
    }
  }

  /// `fragment14`
  Object? f18() {
    if (this.matchPattern(_string.$1) case var $0?) {
      if (this.matchPattern(_string.$35) case var $1?) {
        if ([$0, $1] case var $) {
          return $;
        }
      }
    }
  }

  /// `fragment15`
  Object? f19() {
    if (this.matchPattern(_string.$1) case var $0?) {
      if (this.matchPattern(_string.$36) case var $1?) {
        if ([$0, $1] case var $) {
          return $;
        }
      }
    }
  }

  /// `fragment16`
  Object? f1a() {
    if (this.matchPattern(_string.$1) case var $0?) {
      if (this.matchPattern(_string.$37) case var $1?) {
        if ([$0, $1] case var $) {
          return $;
        }
      }
    }
  }

  /// `fragment17`
  Object? f1b() {
    if (this.matchPattern(_string.$1) case var $0?) {
      if (this.matchPattern(_string.$38) case var $1?) {
        if ([$0, $1] case var $) {
          return $;
        }
      }
    }
  }

  /// `fragment18`
  Object? f1c() {
    if (this.matchPattern(_string.$1) case var $0?) {
      if (this.matchPattern(_string.$39) case var $1?) {
        if ([$0, $1] case var $) {
          return $;
        }
      }
    }
  }

  /// `fragment19`
  Object? f1d() {
    if (this.matchPattern(_string.$1) case var $0?) {
      if (this.matchPattern(_string.$23) case var $1?) {
        if ([$0, $1] case var $) {
          return $;
        }
      }
    }
  }

  /// `fragment20`
  Object? f1e() {
    if (this.matchPattern(_string.$1) case var $0?) {
      if (this.matchPattern(_string.$40) case var $1?) {
        if ([$0, $1] case var $) {
          return $;
        }
      }
    }
  }

  /// `fragment21`
  Object? f1f() {
    if (this.matchPattern(_string.$1) case var $0?) {
      if (this.matchPattern(_string.$41) case var $1?) {
        if ([$0, $1] case var $) {
          return $;
        }
      }
    }
  }

  /// `fragment22`
  Object? f1g() {
    if (this.matchPattern(_string.$1) case var $0?) {
      if (this.matchPattern(_string.$35) case var $1?) {
        if ([$0, $1] case var $) {
          return $;
        }
      }
    }
  }

  /// `fragment23`
  Object? f1h() {
    if (this.matchPattern(_string.$1) case var $0?) {
      if (this.matchPattern(_string.$36) case var $1?) {
        if ([$0, $1] case var $) {
          return $;
        }
      }
    }
  }

  /// `fragment24`
  Object? f1i() {
    if (this.matchPattern(_string.$1) case var $0?) {
      if (this.matchPattern(_string.$37) case var $1?) {
        if ([$0, $1] case var $) {
          return $;
        }
      }
    }
  }

  /// `fragment25`
  Object? f1j() {
    if (this.matchPattern(_string.$1) case var $0?) {
      if (this.matchPattern(_string.$39) case var $1?) {
        if ([$0, $1] case var $) {
          return $;
        }
      }
    }
  }

  /// `fragment26`
  Object? f1k() {
    if (this.matchPattern(_string.$1) case var $0?) {
      if (this.matchPattern(_string.$23) case var $1?) {
        if ([$0, $1] case var $) {
          return $;
        }
      }
    }
  }

  /// `fragment27`
  Object? f1l() {
    if (this.matchPattern(_string.$1) case var $0?) {
      if (this.matchPattern(_string.$38) case var $1?) {
        if ([$0, $1] case var $) {
          return $;
        }
      }
    }
  }

  /// `fragment28`
  Object? f1m() {
    if (this.matchPattern(_string.$1) case var $0?) {
      if (this.matchPattern(_string.$1) case var $1?) {
        if ([$0, $1] case var $) {
          return $;
        }
      }
    }
  }

  /// `fragment29`
  Object? f1n() {
    if (this.pos case var mark) {
      if (this.pos case var mark) {
        if (this.matchPattern(_string.$42) case var $?) {
          return $;
        }
        this.pos = mark;
        if (this.fq() case var $0) {
          if (this.f1g() case var $1?) {
            if (this.fq() case var $2) {
              if ([$0, $1, $2] case var $) {
                return $;
              }
            }
          }
        }
        this.pos = mark;
        if (this.fq() case var $0) {
          if (this.f1h() case var $1?) {
            if (this.fq() case var $2) {
              if ([$0, $1, $2] case var $) {
                return $;
              }
            }
          }
        }
        this.pos = mark;
        if (this.fq() case var $0) {
          if (this.f1i() case var $1?) {
            if (this.fq() case var $2) {
              if ([$0, $1, $2] case var $) {
                return $;
              }
            }
          }
        }
        this.pos = mark;
        if (this.fq() case var $0) {
          if (this.f1j() case var $1?) {
            if (this.fq() case var $2) {
              if ([$0, $1, $2] case var $) {
                return $;
              }
            }
          }
        }
        this.pos = mark;
        if (this.fq() case var $0) {
          if (this.f1k() case var $1?) {
            if (this.fq() case var $2) {
              if ([$0, $1, $2] case var $) {
                return $;
              }
            }
          }
        }
        this.pos = mark;
        if (this.fq() case var $0) {
          if (this.f1l() case var $1?) {
            if (this.fq() case var $2) {
              if ([$0, $1, $2] case var $) {
                return $;
              }
            }
          }
        }
        this.pos = mark;
        if (this.fq() case var $0) {
          if (this.f1m() case var $1?) {
            if (this.fq() case var $2) {
              if ([$0, $1, $2] case var $) {
                return $;
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.f0() case var l?) {
        if (this.matchPattern(_string.$43) case var $1?) {
          if (this.f0() case var r?) {
            if ([l, $1, r] case var $) {
              return $;
            }
          }
        }
      }
      this.pos = mark;
      if (this.f0() case var $?) {
        return $;
      }
    }
  }

  /// `fragment30`
  Object? f1o() {
    if (this.fq() case var $0) {
      if (this.matchPattern(_string.$44) case var $1?) {
        if (this.f1n() case var _0?) {
          if ([_0] case (var elements && var _l1)) {
            for (;;) {
              if (this.pos case var mark) {
                if (this.fq() case _) {
                  if (this.f1n() case var _0?) {
                    _l1.add(_0);
                    continue;
                  }
                }
                this.pos = mark;
                break;
              }
            }
            if (this.matchPattern(_string.$2) case var $3?) {
              if (this.fq() case var $4) {
                if ([$0, $1, elements, $3, $4] case var $) {
                  return $;
                }
              }
            }
          }
        }
      }
    }
  }

  /// `fragment31`
  Object? f1p() {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$1) case var $0?) {
        if (this.pos < this.buffer.length) {
          if (this.buffer[this.pos] case var $1) {
            this.pos++;
            if ([$0, $1] case var $) {
              return $;
            }
          }
        }
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.matchPattern(_string.$45) case (var $0 && null)) {
          this.pos = mark;
          if (this.pos < this.buffer.length) {
            if (this.buffer[this.pos] case var $1) {
              this.pos++;
              if ([$0, $1] case var $) {
                return $;
              }
            }
          }
        }
      }
    }
  }

  /// `fragment32`
  Object? f1q() {
    if (this.f1p() case var _0?) {
      if ([_0] case (var $ && var _l1)) {
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
        return $;
      }
    }
  }

  /// `fragment33`
  Object? f1r() {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$22) case (var $0 && null)) {
        this.pos = mark;
        if (this.pos < this.buffer.length) {
          if (this.buffer[this.pos] case var $1) {
            this.pos++;
            if ([$0, $1] case var $) {
              return $;
            }
          }
        }
      }
    }
  }

  /// `fragment34`
  Object? f1s() {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$24) case (var $0 && null)) {
        this.pos = mark;
        if (this.pos < this.buffer.length) {
          if (this.buffer[this.pos] case var $1) {
            this.pos++;
            if ([$0, $1] case var $) {
              return $;
            }
          }
        }
      }
    }
  }

  /// `fragment35`
  Object? f1t() {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$25) case (var $0 && null)) {
        this.pos = mark;
        if (this.pos < this.buffer.length) {
          if (this.buffer[this.pos] case var $1) {
            this.pos++;
            if ([$0, $1] case var $) {
              return $;
            }
          }
        }
      }
    }
  }

  /// `fragment36`
  Object? f1u() {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$26) case (var $0 && null)) {
        this.pos = mark;
        if (this.pos < this.buffer.length) {
          if (this.buffer[this.pos] case var $1) {
            this.pos++;
            if ([$0, $1] case var $) {
              return $;
            }
          }
        }
      }
    }
  }

  /// `fragment37`
  Object? f1v() {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$1) case var $0?) {
        if (this.pos < this.buffer.length) {
          if (this.buffer[this.pos] case var $1) {
            this.pos++;
            if ([$0, $1] case var $) {
              return $;
            }
          }
        }
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.matchPattern(_string.$22) case (var $0 && null)) {
          this.pos = mark;
          if (this.pos < this.buffer.length) {
            if (this.buffer[this.pos] case var $1) {
              this.pos++;
              if ([$0, $1] case var $) {
                return $;
              }
            }
          }
        }
      }
    }
  }

  /// `fragment38`
  Object? f1w() {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$1) case var $0?) {
        if (this.pos < this.buffer.length) {
          if (this.buffer[this.pos] case var $1) {
            this.pos++;
            if ([$0, $1] case var $) {
              return $;
            }
          }
        }
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.matchPattern(_string.$24) case (var $0 && null)) {
          this.pos = mark;
          if (this.pos < this.buffer.length) {
            if (this.buffer[this.pos] case var $1) {
              this.pos++;
              if ([$0, $1] case var $) {
                return $;
              }
            }
          }
        }
      }
    }
  }

  /// `fragment39`
  Object? f1x() {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$1) case var $0?) {
        if (this.pos < this.buffer.length) {
          if (this.buffer[this.pos] case var $1) {
            this.pos++;
            if ([$0, $1] case var $) {
              return $;
            }
          }
        }
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.matchPattern(_string.$25) case (var $0 && null)) {
          this.pos = mark;
          if (this.pos < this.buffer.length) {
            if (this.buffer[this.pos] case var $1) {
              this.pos++;
              if ([$0, $1] case var $) {
                return $;
              }
            }
          }
        }
      }
    }
  }

  /// `fragment40`
  Object? f1y() {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$1) case var $0?) {
        if (this.pos < this.buffer.length) {
          if (this.buffer[this.pos] case var $1) {
            this.pos++;
            if ([$0, $1] case var $) {
              return $;
            }
          }
        }
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.matchPattern(_string.$26) case (var $0 && null)) {
          this.pos = mark;
          if (this.pos < this.buffer.length) {
            if (this.buffer[this.pos] case var $1) {
              this.pos++;
              if ([$0, $1] case var $) {
                return $;
              }
            }
          }
        }
      }
    }
  }

  /// `fragment41`
  Object? f1z() {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$46) case var $0?) {
        if (this.pos case var mark) {
          if (this.f1r() case var _0) {
            if ([if (_0 case var _0?) _0] case (var $1 && var _l1)) {
              if (_l1.isNotEmpty) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.f1r() case var _0?) {
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
              if (this.matchPattern(_string.$22) case var $2?) {
                if ([$0, $1, $2] case var $) {
                  return $;
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$47) case var $0?) {
        if (this.pos case var mark) {
          if (this.f1s() case var _2) {
            if ([if (_2 case var _2?) _2] case (var $1 && var _l3)) {
              if (_l3.isNotEmpty) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.f1s() case var _2?) {
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
              if (this.matchPattern(_string.$24) case var $2?) {
                if ([$0, $1, $2] case var $) {
                  return $;
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$48) case var $0?) {
        if (this.pos case var mark) {
          if (this.f1t() case var _4) {
            if ([if (_4 case var _4?) _4] case (var $1 && var _l5)) {
              if (_l5.isNotEmpty) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.f1t() case var _4?) {
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
              if (this.matchPattern(_string.$25) case var $2?) {
                if ([$0, $1, $2] case var $) {
                  return $;
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$49) case var $0?) {
        if (this.pos case var mark) {
          if (this.f1u() case var _6) {
            if ([if (_6 case var _6?) _6] case (var $1 && var _l7)) {
              if (_l7.isNotEmpty) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.f1u() case var _6?) {
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
              if (this.matchPattern(_string.$26) case var $2?) {
                if ([$0, $1, $2] case var $) {
                  return $;
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$22) case var $0?) {
        if (this.pos case var mark) {
          if (this.f1v() case var _8) {
            if ([if (_8 case var _8?) _8] case (var $1 && var _l9)) {
              if (_l9.isNotEmpty) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.f1v() case var _8?) {
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
              if (this.matchPattern(_string.$22) case var $2?) {
                if ([$0, $1, $2] case var $) {
                  return $;
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$24) case var $0?) {
        if (this.pos case var mark) {
          if (this.f1w() case var _10) {
            if ([if (_10 case var _10?) _10] case (var $1 && var _l11)) {
              if (_l11.isNotEmpty) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.f1w() case var _10?) {
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
              if (this.matchPattern(_string.$24) case var $2?) {
                if ([$0, $1, $2] case var $) {
                  return $;
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$25) case var $0?) {
        if (this.pos case var mark) {
          if (this.f1x() case var _12) {
            if ([if (_12 case var _12?) _12] case (var $1 && var _l13)) {
              if (_l13.isNotEmpty) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.f1x() case var _12?) {
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
              if (this.matchPattern(_string.$25) case var $2?) {
                if ([$0, $1, $2] case var $) {
                  return $;
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$26) case var $0?) {
        if (this.pos case var mark) {
          if (this.f1y() case var _14) {
            if ([if (_14 case var _14?) _14] case (var $1 && var _l15)) {
              if (_l15.isNotEmpty) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.f1y() case var _14?) {
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
              if (this.matchPattern(_string.$26) case var $2?) {
                if ([$0, $1, $2] case var $) {
                  return $;
                }
              }
            }
          }
        }
      }
    }
  }

  /// `fragment42`
  Object? f20() {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$50) case (var $0 && null)) {
        this.pos = mark;
        if (this.pos < this.buffer.length) {
          if (this.buffer[this.pos] case var $1) {
            this.pos++;
            if ([$0, $1] case var $) {
              return $;
            }
          }
        }
      }
    }
  }

  /// `fragment43`
  Object? f21() {
    if (this.pos case var mark) {
      if (this.apply(this.ri) case var $?) {
        return $;
      }
      this.pos = mark;
      if (this.matchPattern(_string.$12) case var $0?) {
        if (this.apply(this.rh)! case var $1) {
          if (this.matchPattern(_string.$11) case var $2?) {
            if ([$0, $1, $2] case var $) {
              return $;
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$14) case var $0?) {
        if (this.apply(this.rh)! case var $1) {
          if (this.matchPattern(_string.$13) case var $2?) {
            if ([$0, $1, $2] case var $) {
              return $;
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$44) case var $0?) {
        if (this.apply(this.rh)! case var $1) {
          if (this.matchPattern(_string.$2) case var $2?) {
            if ([$0, $1, $2] case var $) {
              return $;
            }
          }
        }
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.matchPattern(_string.$11) case (var $0 && null)) {
          this.pos = mark;
          if (this.pos < this.buffer.length) {
            if (this.buffer[this.pos] case var $1) {
              this.pos++;
              if ([$0, $1] case var $) {
                return $;
              }
            }
          }
        }
      }
    }
  }

  /// `fragment44`
  Object? f22() {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$50) case (var $0 && null)) {
        this.pos = mark;
        if (this.pos < this.buffer.length) {
          if (this.buffer[this.pos] case var $1) {
            this.pos++;
            if ([$0, $1] case var $) {
              return $;
            }
          }
        }
      }
    }
  }

  /// `fragment45`
  Object? f23() {
    if (this.pos case var mark) {
      if (matchPattern(_regexp.$2) case var $?) {
        return $;
      }
      this.pos = mark;
      if (this.matchPattern(_string.$51) case var $?) {
        return $;
      }
    }
  }

  /// `fragment46`
  Object? f24() {
    if (this.pos case var mark) {
      if (this.apply(this.ri) case var $?) {
        return $;
      }
      this.pos = mark;
      if (this.matchPattern(_string.$12) case var $0?) {
        if (this.apply(this.rh)! case var $1) {
          if (this.matchPattern(_string.$11) case var $2?) {
            if ([$0, $1, $2] case var $) {
              return $;
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$14) case var $0?) {
        if (this.apply(this.rh)! case var $1) {
          if (this.matchPattern(_string.$13) case var $2?) {
            if ([$0, $1, $2] case var $) {
              return $;
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$44) case var $0?) {
        if (this.apply(this.rh)! case var $1) {
          if (this.matchPattern(_string.$2) case var $2?) {
            if ([$0, $1, $2] case var $) {
              return $;
            }
          }
        }
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.f23() case (var $0 && null)) {
          this.pos = mark;
          if (this.pos < this.buffer.length) {
            if (this.buffer[this.pos] case var $1) {
              this.pos++;
              if ([$0, $1] case var $) {
                return $;
              }
            }
          }
        }
      }
    }
  }

  /// `fragment47`
  Object? f25() {
    if (this.pos case var mark) {
      if (this.apply(this.ri) case var $?) {
        return $;
      }
      this.pos = mark;
      if (this.matchPattern(_string.$12) case var $0?) {
        if (this.apply(this.rh)! case var $1) {
          if (this.matchPattern(_string.$11) case var $2?) {
            if ([$0, $1, $2] case var $) {
              return $;
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$14) case var $0?) {
        if (this.apply(this.rh)! case var $1) {
          if (this.matchPattern(_string.$13) case var $2?) {
            if ([$0, $1, $2] case var $) {
              return $;
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$44) case var $0?) {
        if (this.apply(this.rh)! case var $1) {
          if (this.matchPattern(_string.$2) case var $2?) {
            if ([$0, $1, $2] case var $) {
              return $;
            }
          }
        }
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.matchTrie(_trie.$1) case (var $0 && null)) {
          this.pos = mark;
          if (this.pos < this.buffer.length) {
            if (this.buffer[this.pos] case var $1) {
              this.pos++;
              if ([$0, $1] case var $) {
                return $;
              }
            }
          }
        }
      }
    }
  }

  /// `fragment48`
  Object? f26() {
    if (this.fs() case var $?) {
      return $;
    }
  }

  /// `fragment49`
  Object? f27() {
    if (this.pos case var mark) {
      if (this.apply(this.ri) case var $?) {
        return $;
      }
      this.pos = mark;
      if (this.matchPattern(_string.$12) case var $0?) {
        if (this.apply(this.rk)! case var $1) {
          if (this.matchPattern(_string.$11) case var $2?) {
            if ([$0, $1, $2] case var $) {
              return $;
            }
          }
        }
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.matchPattern(_string.$11) case (var $0 && null)) {
          this.pos = mark;
          if (this.pos < this.buffer.length) {
            if (this.buffer[this.pos] case var $1) {
              this.pos++;
              if ([$0, $1] case var $) {
                return $;
              }
            }
          }
        }
      }
    }
  }

  /// `fragment50`
  Object? f28() {
    if (this.fq() case var $0) {
      if (this.matchPattern(_string.$52) case var $1?) {
        if (this.fq() case var $2) {
          if ([$0, $1, $2] case var $) {
            return $;
          }
        }
      }
    }
  }

  /// `fragment51`
  Object? f29() {
    if (this.fq() case var $0) {
      if (this.matchPattern(_string.$53) case var $1?) {
        if (this.fq() case var $2) {
          if ([$0, $1, $2] case var $) {
            return $;
          }
        }
      }
    }
  }

  /// `fragment52`
  Object? f2a() {
    if (this.fq() case var $0) {
      if (this.matchPattern(_string.$54) case var $1?) {
        if (this.fq() case var $2) {
          if ([$0, $1, $2] case var $) {
            return $;
          }
        }
      }
    }
  }

  /// `fragment53`
  Object? f2b() {
    if (this.fq() case var $0) {
      if (this.matchPattern(_string.$44) case var $1?) {
        if (this.fq() case var $2) {
          if ([$0, $1, $2] case var $) {
            return $;
          }
        }
      }
    }
  }

  /// `fragment54`
  Object? f2c() {
    if (this.fq() case var $0) {
      if (this.matchPattern(_string.$2) case var $1?) {
        if (this.fq() case var $2) {
          if ([$0, $1, $2] case var $) {
            return $;
          }
        }
      }
    }
  }

  /// `fragment55`
  Object? f2d() {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$50) case (var $0 && null)) {
        this.pos = mark;
        if (this.pos < this.buffer.length) {
          if (this.buffer[this.pos] case var $1) {
            this.pos++;
            if ([$0, $1] case var $) {
              return $;
            }
          }
        }
      }
    }
  }

  /// `fragment56`
  Object? f2e() {
    if (this.matchPattern(_string.$50) case var $0?) {
      if (this.pos case var mark) {
        if (this.f2d() case var _0) {
          if ([if (_0 case var _0?) _0] case (var $1 && var _l1)) {
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
            if (this.matchPattern(_string.$50) case var $2?) {
              if ([$0, $1, $2] case var $) {
                return $;
              }
            }
          }
        }
      }
    }
  }

  /// `fragment57`
  Object? f2f() {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$55) case var $?) {
        return $;
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.matchPattern(_string.$10) case (var $0 && null)) {
          this.pos = mark;
          if (this.matchPattern(_string.$21) case var $1?) {
            if ([$0, $1] case var $) {
              return $;
            }
          }
        }
      }
    }
  }

  /// `fragment58`
  Object? f2g() {
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

  /// `fragment59`
  Object? f2h() {
    if (this.f7() case var $0?) {
      if (this.f2f() case var $1?) {
        if (this.pos case var mark) {
          if (this.f2g() case (var $2 && null)) {
            this.pos = mark;
            if ([$0, $1, $2] case var $) {
              return $;
            }
          }
        }
      }
    }
  }

  /// `fragment60`
  Object? f2i() {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$50) case (var $0 && null)) {
        this.pos = mark;
        if (this.pos < this.buffer.length) {
          if (this.buffer[this.pos] case var $1) {
            this.pos++;
            if ([$0, $1] case var $) {
              return $;
            }
          }
        }
      }
    }
  }

  /// `fragment61`
  Object? f2j() {
    if (this.matchPattern(_string.$50) case var $0?) {
      if (this.pos case var mark) {
        if (this.f2i() case var _0) {
          if ([if (_0 case var _0?) _0] case (var $1 && var _l1)) {
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
            if (this.matchPattern(_string.$50) case var $2?) {
              if ([$0, $1, $2] case var $) {
                return $;
              }
            }
          }
        }
      }
    }
  }

  /// `fragment62`
  Object? f2k() {
    if (this.fq() case var $0) {
      if (this.matchPattern(_string.$56) case var $1?) {
        if (this.fq() case var $2) {
          if ([$0, $1, $2] case var $) {
            return $;
          }
        }
      }
    }
  }

  /// `fragment63`
  Object? f2l() {
    if (this.pos case var mark) {
      if (this.fn() case var $0) {
        if (this.f2k() case var $1?) {
          if ([$0, $1] case var $) {
            return $;
          }
        }
      }
      this.pos = mark;
      if (this.fq() case var $0) {
        if (this.matchPattern(_string.$57) case var $1?) {
          if (this.fq() case var $2) {
            if ([$0, $1, $2] case var $) {
              return $;
            }
          }
        }
      }
      this.pos = mark;
      if (this.fq() case var $0) {
        if (this.matchPattern(_string.$58) case var $1?) {
          if (this.fq() case var $2) {
            if ([$0, $1, $2] case var $) {
              return $;
            }
          }
        }
      }
    }
  }

  /// `fragment64`
  Object? f2m() {
    if (this.fq() case var $0) {
      if (this.matchPattern(_string.$51) case var $1?) {
        if (this.fq() case var $2) {
          if ([$0, $1, $2] case var $) {
            return $;
          }
        }
      }
    }
  }

  /// `fragment65`
  Object? f2n() {
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
  }

  /// `fragment66`
  Object? f2o() {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$22) case (var $0 && null)) {
        this.pos = mark;
        if (this.pos < this.buffer.length) {
          if (this.buffer[this.pos] case var $1) {
            this.pos++;
            if ([$0, $1] case var $) {
              return $;
            }
          }
        }
      }
    }
  }

  /// `fragment67`
  Object? f2p() {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$24) case (var $0 && null)) {
        this.pos = mark;
        if (this.pos < this.buffer.length) {
          if (this.buffer[this.pos] case var $1) {
            this.pos++;
            if ([$0, $1] case var $) {
              return $;
            }
          }
        }
      }
    }
  }

  /// `fragment68`
  Object? f2q() {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$25) case (var $0 && null)) {
        this.pos = mark;
        if (this.pos < this.buffer.length) {
          if (this.buffer[this.pos] case var $1) {
            this.pos++;
            if ([$0, $1] case var $) {
              return $;
            }
          }
        }
      }
    }
  }

  /// `fragment69`
  Object? f2r() {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$26) case (var $0 && null)) {
        this.pos = mark;
        if (this.pos < this.buffer.length) {
          if (this.buffer[this.pos] case var $1) {
            this.pos++;
            if ([$0, $1] case var $) {
              return $;
            }
          }
        }
      }
    }
  }

  /// `fragment70`
  Object? f2s() {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$1) case var $0?) {
        if (this.pos < this.buffer.length) {
          if (this.buffer[this.pos] case var $1) {
            this.pos++;
            if ([$0, $1] case var $) {
              return $;
            }
          }
        }
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.matchPattern(_string.$27) case var $0?) {
          this.pos = mark;
          if (this.ft() case var $1?) {
            if ([$0, $1] case var $) {
              return $;
            }
          }
        }
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.matchPattern(_string.$22) case (var $0 && null)) {
          this.pos = mark;
          if (this.pos < this.buffer.length) {
            if (this.buffer[this.pos] case var $1) {
              this.pos++;
              if ([$0, $1] case var $) {
                return $;
              }
            }
          }
        }
      }
    }
  }

  /// `fragment71`
  Object? f2t() {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$1) case var $0?) {
        if (this.pos < this.buffer.length) {
          if (this.buffer[this.pos] case var $1) {
            this.pos++;
            if ([$0, $1] case var $) {
              return $;
            }
          }
        }
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.matchPattern(_string.$27) case var $0?) {
          this.pos = mark;
          if (this.ft() case var $1?) {
            if ([$0, $1] case var $) {
              return $;
            }
          }
        }
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.matchPattern(_string.$24) case (var $0 && null)) {
          this.pos = mark;
          if (this.pos < this.buffer.length) {
            if (this.buffer[this.pos] case var $1) {
              this.pos++;
              if ([$0, $1] case var $) {
                return $;
              }
            }
          }
        }
      }
    }
  }

  /// `fragment72`
  Object? f2u() {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$1) case var $0?) {
        if (this.pos < this.buffer.length) {
          if (this.buffer[this.pos] case var $1) {
            this.pos++;
            if ([$0, $1] case var $) {
              return $;
            }
          }
        }
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.matchPattern(_string.$27) case var $0?) {
          this.pos = mark;
          if (this.ft() case var $1?) {
            if ([$0, $1] case var $) {
              return $;
            }
          }
        }
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.matchPattern(_string.$25) case (var $0 && null)) {
          this.pos = mark;
          if (this.pos < this.buffer.length) {
            if (this.buffer[this.pos] case var $1) {
              this.pos++;
              if ([$0, $1] case var $) {
                return $;
              }
            }
          }
        }
      }
    }
  }

  /// `fragment73`
  Object? f2v() {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$1) case var $0?) {
        if (this.pos < this.buffer.length) {
          if (this.buffer[this.pos] case var $1) {
            this.pos++;
            if ([$0, $1] case var $) {
              return $;
            }
          }
        }
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.matchPattern(_string.$27) case var $0?) {
          this.pos = mark;
          if (this.ft() case var $1?) {
            if ([$0, $1] case var $) {
              return $;
            }
          }
        }
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.matchPattern(_string.$26) case (var $0 && null)) {
          this.pos = mark;
          if (this.pos < this.buffer.length) {
            if (this.buffer[this.pos] case var $1) {
              this.pos++;
              if ([$0, $1] case var $) {
                return $;
              }
            }
          }
        }
      }
    }
  }

  /// `global::document`
  Object? r0() {
    if (this.pos case var $0 when this.pos <= 0) {
      if (this.apply(this.r1) case var preamble) {
        if (this.apply(this.r2) case var _0?) {
          if ([_0] case (var statements && var _l1)) {
            for (;;) {
              if (this.pos case var mark) {
                if (this.fq() case _) {
                  if (this.apply(this.r2) case var _0?) {
                    _l1.add(_0);
                    continue;
                  }
                }
                this.pos = mark;
                break;
              }
            }
            if (this.fq() case var $3) {
              if (this.pos case var $4 when this.pos >= this.buffer.length) {
                if ([$0, preamble, statements, $3, $4] case var $) {
                  return ("<document>", $);
                }
              }
            }
          }
        }
      }
    }
  }

  /// `global::preamble`
  Object? r1() {
    if (this.fg() case var $0?) {
      if (this.fq() case var $1) {
        if (this.apply(this.rf)! case var code) {
          if (this.fq() case var $3) {
            if (this.ff() case var $4?) {
              if ([$0, $1, code, $3, $4] case var $) {
                return ("<preamble>", $);
              }
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
        return ("<statement>", $);
      }
      this.pos = mark;
      if (this.apply(this.r4) case var $?) {
        return ("<statement>", $);
      }
    }
  }

  /// `global::namespace`
  Object? r3() {
    if (this.f9() case var decorator) {
      if (this.f7() case var name) {
        if (this.fg() case var $2?) {
          if (this.apply(this.r2) case var _0?) {
            if ([_0] case (var statements && var _l1)) {
              for (;;) {
                if (this.pos case var mark) {
                  if (this.fq() case _) {
                    if (this.apply(this.r2) case var _0?) {
                      _l1.add(_0);
                      continue;
                    }
                  }
                  this.pos = mark;
                  break;
                }
              }
              if (this.ff() case var $4?) {
                if ([decorator, name, $2, statements, $4] case var $) {
                  return ("<namespace>", $);
                }
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
      if (this.f9() case var decorator) {
        if (this.fa() case var $1) {
          if (this.f3() case var name?) {
            if (this.f6() case var body?) {
              if ([decorator, $1, name, body] case var $) {
                return ("<declaration>", $);
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.f9() case var decorator) {
        if (this.f1() case var type?) {
          if (this.f3() case var name?) {
            if (this.f6() case var body?) {
              if ([decorator, type, name, body] case var $) {
                return ("<declaration>", $);
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.f9() case var decorator) {
        if (this.fa() case var $1) {
          if (this.f3() case var name?) {
            if (this.fn() case var $3?) {
              if (this.f1() case var type?) {
                if (this.f6() case var body?) {
                  if ([decorator, $1, name, $3, type, body] case var $) {
                    return ("<declaration>", $);
                  }
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
    if (this.fu() case var $0) {
      if (this.apply(this.r6) case var _0?) {
        if ([_0] case (var options && var _l1)) {
          for (;;) {
            if (this.pos case var mark) {
              if (this.fv() case _?) {
                if (this.apply(this.r6) case var _0?) {
                  _l1.add(_0);
                  continue;
                }
              }
              this.pos = mark;
              break;
            }
          }
          if ([$0, options] case var $) {
            return ("<choice>", $);
          }
        }
      }
    }
  }

  /// `global::acted`
  Object? r6() {
    if (this.pos case var mark) {
      if (this.apply(this.r7) case var sequence?) {
        if (this.fw() case var $1?) {
          if (this.fq() case var $2) {
            if (this.apply(this.rg)! case var code) {
              if (this.fq() case var $4) {
                if ([sequence, $1, $2, code, $4] case var $) {
                  return ("<acted>", $);
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.r7) case var sequence?) {
        if (this.fg() case var $1?) {
          if (this.fq() case var $2) {
            if (this.apply(this.rf)! case var curly) {
              if (this.fq() case var $4) {
                if (this.ff() case var $5?) {
                  if ([sequence, $1, $2, curly, $4, $5] case var $) {
                    return ("<acted>", $);
                  }
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.r7) case var sequence?) {
        if (this.fi() case var $1?) {
          if (this.fh() case var $2?) {
            if (this.fg() case var $3?) {
              if (this.fq() case var $4) {
                if (this.apply(this.rf)! case var curly) {
                  if (this.fq() case var $6) {
                    if (this.ff() case var $7?) {
                      if ([sequence, $1, $2, $3, $4, curly, $6, $7] case var $) {
                        return ("<acted>", $);
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
        return ("<acted>", $);
      }
    }
  }

  /// `global::sequence`
  Object? r7() {
    if (this.apply(this.r8) case var _0?) {
      if ([_0] case (var body && var _l1)) {
        for (;;) {
          if (this.pos case var mark) {
            if (this.fq() case _) {
              if (this.apply(this.r8) case var _0?) {
                _l1.add(_0);
                continue;
              }
            }
            this.pos = mark;
            break;
          }
        }
        if (this.fy() case var chosen) {
          if ([body, chosen] case var $) {
            return ("<sequence>", $);
          }
        }
      }
    }
  }

  /// `global::dropped`
  Object? r8() {
    if (this.pos case var mark) {
      if (this.apply(this.r8) case var captured?) {
        if (this.fz() case var $1?) {
          if (this.apply(this.ra) case var dropped?) {
            if ([captured, $1, dropped] case var $) {
              return ("<dropped>", $);
            }
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.ra) case var dropped?) {
        if (this.f10() case var $1?) {
          if (this.apply(this.r8) case var captured?) {
            if ([dropped, $1, captured] case var $) {
              return ("<dropped>", $);
            }
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.r9) case var $?) {
        return ("<dropped>", $);
      }
    }
  }

  /// `global::labeled`
  Object? r9() {
    if (this.pos case var mark) {
      if (this.f7() case var identifier?) {
        if (this.matchPattern(_string.$19) case var $1?) {
          if (this.fq() case var $2) {
            if (this.apply(this.ra) case var special?) {
              if ([identifier, $1, $2, special] case var $) {
                return ("<labeled>", $);
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$19) case var $0?) {
        if (this.f5() case var id?) {
          if (this.fj() case var $2?) {
            if ([$0, id, $2] case var $) {
              return ("<labeled>", $);
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$19) case var $0?) {
        if (this.f5() case var id?) {
          if (this.fk() case var $2?) {
            if ([$0, id, $2] case var $) {
              return ("<labeled>", $);
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$19) case var $0?) {
        if (this.f5() case var id?) {
          if (this.fl() case var $2?) {
            if ([$0, id, $2] case var $) {
              return ("<labeled>", $);
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$19) case var $0?) {
        if (this.f5() case var id?) {
          if ([$0, id] case var $) {
            return ("<labeled>", $);
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.ra) case var $?) {
        return ("<labeled>", $);
      }
    }
  }

  /// `global::special`
  Object? ra() {
    if (this.pos case var mark) {
      if (this.apply(this.rd) case var sep?) {
        if (this.fe() case var $1?) {
          if (this.apply(this.rd) case var expr?) {
            if (this.fl() case var $3?) {
              if (this.fj() case var $4?) {
                if ([sep, $1, expr, $3, $4] case var $) {
                  return ("<special>", $);
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.rd) case var sep?) {
        if (this.fe() case var $1?) {
          if (this.apply(this.rd) case var expr?) {
            if (this.fk() case var $3?) {
              if (this.fj() case var $4?) {
                if ([sep, $1, expr, $3, $4] case var $) {
                  return ("<special>", $);
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.rd) case var sep?) {
        if (this.fe() case var $1?) {
          if (this.apply(this.rd) case var expr?) {
            if (this.fl() case var $3?) {
              if ([sep, $1, expr, $3] case var $) {
                return ("<special>", $);
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.rd) case var sep?) {
        if (this.fe() case var $1?) {
          if (this.apply(this.rd) case var expr?) {
            if (this.fk() case var $3?) {
              if ([sep, $1, expr, $3] case var $) {
                return ("<special>", $);
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.rb) case var $?) {
        return ("<special>", $);
      }
    }
  }

  /// `global::postfix`
  Object? rb() {
    if (this.pos case var mark) {
      if (this.apply(this.rb) case var $0?) {
        if (this.fj() case var $1?) {
          if ([$0, $1] case var $) {
            return ("<postfix>", $);
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.rb) case var $0?) {
        if (this.fk() case var $1?) {
          if ([$0, $1] case var $) {
            return ("<postfix>", $);
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.rb) case var $0?) {
        if (this.fl() case var $1?) {
          if ([$0, $1] case var $) {
            return ("<postfix>", $);
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.rc) case var $?) {
        return ("<postfix>", $);
      }
    }
  }

  /// `global::prefix`
  Object? rc() {
    if (this.pos case var mark) {
      if (this.f8() case var min?) {
        if (this.fe() case var $1?) {
          if (this.f8() case var max) {
            if (this.apply(this.re) case var body?) {
              if ([min, $1, max, body] case var $) {
                return ("<prefix>", $);
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.f8() case var number?) {
        if (this.apply(this.re) case var body?) {
          if ([number, body] case var $) {
            return ("<prefix>", $);
          }
        }
      }
      this.pos = mark;
      if (this.f11() case var $0?) {
        if (this.apply(this.rc) case var $1?) {
          if ([$0, $1] case var $) {
            return ("<prefix>", $);
          }
        }
      }
      this.pos = mark;
      if (this.f12() case var $0?) {
        if (this.apply(this.rc) case var $1?) {
          if ([$0, $1] case var $) {
            return ("<prefix>", $);
          }
        }
      }
      this.pos = mark;
      if (this.f13() case var $0?) {
        if (this.apply(this.rc) case var $1?) {
          if ([$0, $1] case var $) {
            return ("<prefix>", $);
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.rd) case var $?) {
        return ("<prefix>", $);
      }
    }
  }

  /// `global::callLike`
  Object? rd() {
    if (this.pos case var mark) {
      if (this.apply(this.rd) case var target?) {
        if (this.fp() case var $1?) {
          if (this.fc() case var $2?) {
            if (this.fi() case var $3?) {
              if (this.fh() case var $4?) {
                if ([target, $1, $2, $3, $4] case var $) {
                  return ("<callLike>", $);
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.rd) case var target?) {
        if (this.fp() case var $1?) {
          if (this.fb() case var $2?) {
            if (this.fi() case var $3?) {
              if (this.f8() case var min?) {
                if (this.fm() case var $5?) {
                  if (this.f8() case var max?) {
                    if (this.fh() case var $7?) {
                      if ([target, $1, $2, $3, min, $5, max, $7] case var $) {
                        return ("<callLike>", $);
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
      if (this.apply(this.rd) case var target?) {
        if (this.fp() case var $1?) {
          if (this.fb() case var $2?) {
            if (this.fi() case var $3?) {
              if (this.f8() case var number?) {
                if (this.fh() case var $5?) {
                  if ([target, $1, $2, $3, number, $5] case var $) {
                    return ("<callLike>", $);
                  }
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.rd) case var target?) {
        if (this.fp() case var $1?) {
          if (this.fb() case var $2?) {
            if (this.fq() case var $3) {
              if (this.f8() case var number?) {
                if (this.fq() case var $5) {
                  if ([target, $1, $2, $3, number, $5] case var $) {
                    return ("<callLike>", $);
                  }
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.rd) case var sep?) {
        if (this.fp() case var $1?) {
          if (this.fd() case var $2?) {
            if (this.fi() case var $3?) {
              if (this.apply(this.r5) case var body?) {
                if (this.fh() case var $5?) {
                  if (this.fl() case var $6?) {
                    if (this.fj() case var $7?) {
                      if ([sep, $1, $2, $3, body, $5, $6, $7] case var $) {
                        return ("<callLike>", $);
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
      if (this.apply(this.rd) case var sep?) {
        if (this.fp() case var $1?) {
          if (this.fd() case var $2?) {
            if (this.fi() case var $3?) {
              if (this.apply(this.r5) case var body?) {
                if (this.fh() case var $5?) {
                  if (this.fk() case var $6?) {
                    if (this.fj() case var $7?) {
                      if ([sep, $1, $2, $3, body, $5, $6, $7] case var $) {
                        return ("<callLike>", $);
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
      if (this.apply(this.rd) case var sep?) {
        if (this.fp() case var $1?) {
          if (this.fd() case var $2?) {
            if (this.fi() case var $3?) {
              if (this.apply(this.r5) case var body?) {
                if (this.fh() case var $5?) {
                  if (this.fl() case var $6?) {
                    if ([sep, $1, $2, $3, body, $5, $6] case var $) {
                      return ("<callLike>", $);
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
        if (this.fp() case var $1?) {
          if (this.fd() case var $2?) {
            if (this.fi() case var $3?) {
              if (this.apply(this.r5) case var body?) {
                if (this.fh() case var $5?) {
                  if (this.fk() case var $6?) {
                    if ([sep, $1, $2, $3, body, $5, $6] case var $) {
                      return ("<callLike>", $);
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
        if (this.fp() case var $1?) {
          if (this.fd() case var $2?) {
            if (this.fi() case var $3?) {
              if (this.apply(this.r5) case var body?) {
                if (this.fh() case var $5?) {
                  if ([sep, $1, $2, $3, body, $5] case var $) {
                    return ("<callLike>", $);
                  }
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.rd) case var sep?) {
        if (this.fp() case var $1?) {
          if (this.fd() case var $2?) {
            if (this.fq() case var $3) {
              if (this.apply(this.re) case var body?) {
                if (this.fq() case var $5) {
                  if ([sep, $1, $2, $3, body, $5] case var $) {
                    return ("<callLike>", $);
                  }
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.re) case var $?) {
        return ("<callLike>", $);
      }
    }
  }

  /// `global::atom`
  Object? re() {
    if (this.pos case var mark) {
      if (this.fi() case var $0?) {
        if (this.apply(this.r5) case var $1?) {
          if (this.fh() case var $2?) {
            if ([$0, $1, $2] case var $) {
              return ("<atom>", $);
            }
          }
        }
      }
      this.pos = mark;
      if (this.fq() case var $0) {
        if (this.matchPattern(_string.$59) case var $1?) {
          if (this.fq() case var $2) {
            if ([$0, $1, $2] case var $) {
              return ("<atom>", $);
            }
          }
        }
      }
      this.pos = mark;
      if (this.fq() case var $0) {
        if (this.matchPattern(_string.$27) case var $1?) {
          if (this.fq() case var $2) {
            if ([$0, $1, $2] case var $) {
              return ("<atom>", $);
            }
          }
        }
      }
      this.pos = mark;
      if (this.fp() case var $?) {
        return ("<atom>", $);
      }
      this.pos = mark;
      if (this.fq() case var $0) {
        if (this.matchPattern(_string.$60) case var $1?) {
          if (this.fq() case var $2) {
            if ([$0, $1, $2] case var $) {
              return ("<atom>", $);
            }
          }
        }
      }
      this.pos = mark;
      if (this.fq() case var $0) {
        if (this.f14() case var $1?) {
          if (this.fq() case var $2) {
            if ([$0, $1, $2] case var $) {
              return ("<atom>", $);
            }
          }
        }
      }
      this.pos = mark;
      if (this.fq() case var $0) {
        if (this.f15() case var $1?) {
          if (this.fq() case var $2) {
            if ([$0, $1, $2] case var $) {
              return ("<atom>", $);
            }
          }
        }
      }
      this.pos = mark;
      if (this.fq() case var $0) {
        if (this.f16() case var $1?) {
          if (this.fq() case var $2) {
            if ([$0, $1, $2] case var $) {
              return ("<atom>", $);
            }
          }
        }
      }
      this.pos = mark;
      if (this.fq() case var $0) {
        if (this.f17() case var $1?) {
          if (this.fq() case var $2) {
            if ([$0, $1, $2] case var $) {
              return ("<atom>", $);
            }
          }
        }
      }
      this.pos = mark;
      if (this.fq() case var $0) {
        if (this.f18() case var $1?) {
          if (this.fq() case var $2) {
            if ([$0, $1, $2] case var $) {
              return ("<atom>", $);
            }
          }
        }
      }
      this.pos = mark;
      if (this.fq() case var $0) {
        if (this.f19() case var $1?) {
          if (this.fq() case var $2) {
            if ([$0, $1, $2] case var $) {
              return ("<atom>", $);
            }
          }
        }
      }
      this.pos = mark;
      if (this.fq() case var $0) {
        if (this.f1a() case var $1?) {
          if (this.fq() case var $2) {
            if ([$0, $1, $2] case var $) {
              return ("<atom>", $);
            }
          }
        }
      }
      this.pos = mark;
      if (this.fq() case var $0) {
        if (this.f1b() case var $1?) {
          if (this.fq() case var $2) {
            if ([$0, $1, $2] case var $) {
              return ("<atom>", $);
            }
          }
        }
      }
      this.pos = mark;
      if (this.fq() case var $0) {
        if (this.f1c() case var $1?) {
          if (this.fq() case var $2) {
            if ([$0, $1, $2] case var $) {
              return ("<atom>", $);
            }
          }
        }
      }
      this.pos = mark;
      if (this.fq() case var $0) {
        if (this.f1d() case var $1?) {
          if (this.fq() case var $2) {
            if ([$0, $1, $2] case var $) {
              return ("<atom>", $);
            }
          }
        }
      }
      this.pos = mark;
      if (this.fq() case var $0) {
        if (this.f1e() case var $1?) {
          if (this.fq() case var $2) {
            if ([$0, $1, $2] case var $) {
              return ("<atom>", $);
            }
          }
        }
      }
      this.pos = mark;
      if (this.fq() case var $0) {
        if (this.f1f() case var $1?) {
          if (this.fq() case var $2) {
            if ([$0, $1, $2] case var $) {
              return ("<atom>", $);
            }
          }
        }
      }
      this.pos = mark;
      if (this.fq() case var $0) {
        if (this.f1o() case var $1?) {
          if (this.fq() case var $2) {
            if ([$0, $1, $2] case var $) {
              return ("<atom>", $);
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$45) case var $0?) {
        if (this.f1q() case var $1?) {
          if (this.matchPattern(_string.$45) case var $2?) {
            if ([$0, $1, $2] case var $) {
              return ("<atom>", $);
            }
          }
        }
      }
      this.pos = mark;
      if (this.fq() case var $0) {
        if (this.f1z() case var $1?) {
          if (this.fq() case var $2) {
            if ([$0, $1, $2] case var $) {
              return ("<atom>", $);
            }
          }
        }
      }
      this.pos = mark;
      if (this.f4() case var $?) {
        return ("<atom>", $);
      }
    }
  }

  /// `global::code::curly`
  Object rf() {
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
                if ([$0, $1, $2] case var $) {
                  return ("<code::curly>", $);
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.f21() case var _2) {
          if ([if (_2 case var _2?) _2] case (var $ && var code && var _l3)) {
            if (_l3.isNotEmpty) {
              for (;;) {
                if (this.pos case var mark) {
                  if (this.f21() case var _2?) {
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
            return ("<code::curly>", $);
          }
        }
      }
    }
  }

  /// `global::code::nl`
  Object rg() {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$50) case var $0?) {
        if (this.pos case var mark) {
          if (this.f22() case var _0) {
            if ([if (_0 case var _0?) _0] case (var $1 && var _l1)) {
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
              if (this.matchPattern(_string.$50) case var $2?) {
                if ([$0, $1, $2] case var $) {
                  return ("<code::nl>", $);
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.f24() case var _2) {
          if ([if (_2 case var _2?) _2] case (var $ && var code && var _l3)) {
            if (_l3.isNotEmpty) {
              for (;;) {
                if (this.pos case var mark) {
                  if (this.f24() case var _2?) {
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
            return ("<code::nl>", $);
          }
        }
      }
    }
  }

  /// `global::code::balanced`
  Object rh() {
    if (this.pos case var mark) {
      if (this.f25() case var _0) {
        if ([if (_0 case var _0?) _0] case (var $ && var code && var _l1)) {
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
          return ("<code::balanced>", $);
        }
      }
    }
  }

  /// `global::dart::literal::string`
  Object? ri() {
    if (this.f26() case var _0?) {
      if ([_0] case (var $ && var _l1)) {
        for (;;) {
          if (this.pos case var mark) {
            if (this.fq() case _) {
              if (this.f26() case var _0?) {
                _l1.add(_0);
                continue;
              }
            }
            this.pos = mark;
            break;
          }
        }
        return ("<dart::literal::string>", $);
      }
    }
  }

  /// `global::dart::literal::identifier`
  Object? rj() {
    if (this.f7() case var $?) {
      return ("<dart::literal::identifier>", $);
    }
  }

  /// `global::dart::literal::string::balanced`
  Object rk() {
    if (this.pos case var mark) {
      if (this.f27() case var _0) {
        if ([if (_0 case var _0?) _0] case (var $ && var code && var _l1)) {
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
          return ("<dart::literal::string::balanced>", $);
        }
      }
    }
  }

  /// `global::dart::type::main`
  Object? rl() {
    if (this.fq() case var $0) {
      if (this.apply(this.rm) case var $1?) {
        if (this.fq() case var $2) {
          if ([$0, $1, $2] case var $) {
            return ("<dart::type::main>", $);
          }
        }
      }
    }
  }

  /// `global::dart::type::type`
  Object? rm() {
    if (this.pos case var mark) {
      if (this.apply(this.rq) case var parameters?) {
        if (this.f28() case var $1?) {
          if (this.apply(this.rm) case var type?) {
            if ([parameters, $1, type] case var $) {
              return ("<dart::type::type>", $);
            }
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.rm) case var type?) {
        if (this.fq() case var $1) {
          if (this.matchPattern(_string.$61) case var $2?) {
            if (this.apply(this.rq) case var parameters?) {
              if (this.fj() case var $4) {
                if ([type, $1, $2, parameters, $4] case var $) {
                  return ("<dart::type::type>", $);
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.rn) case var $?) {
        return ("<dart::type::type>", $);
      }
    }
  }

  /// `global::dart::type::nullable`
  Object? rn() {
    if (this.apply(this.ro) case var nonNullable?) {
      if (this.fj() case var $1) {
        if ([nonNullable, $1] case var $) {
          return ("<dart::type::nullable>", $);
        }
      }
    }
  }

  /// `global::dart::type::nonNullable`
  Object? ro() {
    if (this.pos case var mark) {
      if (this.apply(this.rr) case var $?) {
        return ("<dart::type::nonNullable>", $);
      }
      this.pos = mark;
      if (this.apply(this.rp) case var $?) {
        return ("<dart::type::nonNullable>", $);
      }
      this.pos = mark;
      if (this.apply(this.rt) case var $?) {
        return ("<dart::type::nonNullable>", $);
      }
    }
  }

  /// `global::dart::type::record`
  Object? rp() {
    if (this.pos case var mark) {
      if (this.fi() case var $0?) {
        if (this.apply(this.rw) case var positional?) {
          if (this.fm() case var $2?) {
            if (this.apply(this.rv) case var named?) {
              if (this.fh() case var $4?) {
                if ([$0, positional, $2, named, $4] case var $) {
                  return ("<dart::type::record>", $);
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.fi() case var $0?) {
        if (this.apply(this.rw) case var positional?) {
          if (this.fm() case var $2) {
            if (this.fh() case var $3?) {
              if ([$0, positional, $2, $3] case var $) {
                return ("<dart::type::record>", $);
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.fi() case var $0?) {
        if (this.apply(this.rv) case var named?) {
          if (this.fh() case var $2?) {
            if ([$0, named, $2] case var $) {
              return ("<dart::type::record>", $);
            }
          }
        }
      }
      this.pos = mark;
      if (this.fi() case var $0?) {
        if (this.fh() case var $1?) {
          if ([$0, $1] case var $) {
            return ("<dart::type::record>", $);
          }
        }
      }
    }
  }

  /// `global::dart::type::function_parameters`
  Object? rq() {
    if (this.pos case var mark) {
      if (this.fi() case var $0?) {
        if (this.apply(this.rw) case var positional?) {
          if (this.fm() case var $2?) {
            if (this.apply(this.rv) case var named?) {
              if (this.fh() case var $4?) {
                if ([$0, positional, $2, named, $4] case var $) {
                  return ("<dart::type::function_parameters>", $);
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.fi() case var $0?) {
        if (this.apply(this.rw) case var positional?) {
          if (this.fm() case var $2?) {
            if (this.apply(this.ru) case var optional?) {
              if (this.fh() case var $4?) {
                if ([$0, positional, $2, optional, $4] case var $) {
                  return ("<dart::type::function_parameters>", $);
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.fi() case var $0?) {
        if (this.apply(this.rw) case var positional?) {
          if (this.fm() case var $2) {
            if (this.fh() case var $3?) {
              if ([$0, positional, $2, $3] case var $) {
                return ("<dart::type::function_parameters>", $);
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.fi() case var $0?) {
        if (this.apply(this.rv) case var named?) {
          if (this.fh() case var $2?) {
            if ([$0, named, $2] case var $) {
              return ("<dart::type::function_parameters>", $);
            }
          }
        }
      }
      this.pos = mark;
      if (this.fi() case var $0?) {
        if (this.apply(this.ru) case var optional?) {
          if (this.fh() case var $2?) {
            if ([$0, optional, $2] case var $) {
              return ("<dart::type::function_parameters>", $);
            }
          }
        }
      }
      this.pos = mark;
      if (this.fi() case var $0?) {
        if (this.fh() case var $1?) {
          if ([$0, $1] case var $) {
            return ("<dart::type::function_parameters>", $);
          }
        }
      }
    }
  }

  /// `global::dart::type::generic`
  Object? rr() {
    if (this.apply(this.rt) case var base?) {
      if (this.f29() case var $1?) {
        if (this.apply(this.rs) case var arguments?) {
          if (this.f2a() case var $3?) {
            if ([base, $1, arguments, $3] case var $) {
              return ("<dart::type::generic>", $);
            }
          }
        }
      }
    }
  }

  /// `global::dart::type::arguments`
  Object? rs() {
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
        return ("<dart::type::arguments>", $);
      }
    }
  }

  /// `global::dart::type::base`
  Object? rt() {
    if (this.f7() case var _0?) {
      if ([_0] case (var $ && var _l1)) {
        for (;;) {
          if (this.pos case var mark) {
            if (this.fp() case _?) {
              if (this.f7() case var _0?) {
                _l1.add(_0);
                continue;
              }
            }
            this.pos = mark;
            break;
          }
        }
        return ("<dart::type::base>", $);
      }
    }
  }

  /// `global::dart::type::parameters::optional`
  Object? ru() {
    if (this.f2b() case var $0?) {
      if (this.apply(this.rw) case var $1?) {
        if (this.fm() case var $2) {
          if (this.f2c() case var $3?) {
            if ([$0, $1, $2, $3] case var $) {
              return ("<dart::type::parameters::optional>", $);
            }
          }
        }
      }
    }
  }

  /// `global::dart::type::parameters::named`
  Object? rv() {
    if (this.fg() case var $0?) {
      if (this.apply(this.rx) case var $1?) {
        if (this.fm() case var $2) {
          if (this.ff() case var $3?) {
            if ([$0, $1, $2, $3] case var $) {
              return ("<dart::type::parameters::named>", $);
            }
          }
        }
      }
    }
  }

  /// `global::dart::type::fields::positional`
  Object? rw() {
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
        return ("<dart::type::fields::positional>", $);
      }
    }
  }

  /// `global::dart::type::fields::named`
  Object? rx() {
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
        return ("<dart::type::fields::named>", $);
      }
    }
  }

  /// `global::dart::type::field::positional`
  Object? ry() {
    if (this.apply(this.rm) case var $0?) {
      if (this.fq() case var $1) {
        if (this.f7() case var $2) {
          if ([$0, $1, $2] case var $) {
            return ("<dart::type::field::positional>", $);
          }
        }
      }
    }
  }

  /// `global::dart::type::field::named`
  Object? rz() {
    if (this.apply(this.rm) case var $0?) {
      if (this.fq() case var $1) {
        if (this.f7() case var $2?) {
          if ([$0, $1, $2] case var $) {
            return ("<dart::type::field::named>", $);
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
  static final _trie = (
    Trie.from(["}",")","]"]),
  );
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
    ":",
    "|",
    ".",
    "\"\"\"",
    "r",
    "'''",
    "\"",
    "'",
    "\$",
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

    if (failures[pos] ??= <String>{} case Set<String> failures) {
      trie._keys(trie._innerMap).map((v) => v.join()).forEach(failures.add);
    }
    return null;
  }
}

class Trie {
  Trie() : _innerMap = HashMap<_Key<String>, Object>();
  factory Trie.from(Iterable<String> strings) => strings.fold(Trie(), (t, s) => t..add(s));
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
      .fold(this, (trie, char) => trie?.derive(char));

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
          yield* _keys(derivative).map((rest) => <String>[keys, ...rest]);
        case null:
          yield <String>[keys];
      }
    }
  }
}
