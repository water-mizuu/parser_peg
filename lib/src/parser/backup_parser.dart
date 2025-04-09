// ignore_for_file: type=lint, body_might_complete_normally_nullable, unused_local_variable, inference_failure_on_function_return_type, unused_import, duplicate_ignore, unused_element, collection_methods_unrelated_type, unused_element, use_setters_to_change_properties

// imports
// ignore_for_file: collection_methods_unrelated_type, unused_element, use_setters_to_change_properties

import "dart:collection";
import "dart:math" as math;
// PREAMBLE
import "package:parser_peg/src/node.dart";
import "package:parser_peg/src/generator.dart";
import "package:parser_peg/src/statement.dart";

final _regexps = (from: RegExp(r"\bfrom\b"), to: RegExp(r"\bto\b"), span: RegExp(r"\bspan\b"));

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
    var regex = includeNewlines ? whitespaceRegExp.$1 : whitespaceRegExp.$2;
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

  int _mark() {
    return this.pos;
  }

  void _recover(int pos) {
    this.pos = pos;
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
  T? nullable() => this;
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

  /// `global::literal::range::atom`
  String? f0() {
    var _mark = this._mark();
    if (this.matchPattern(_string.$1) case _?) {
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $1) {
          return $1;
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$2) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  }

  /// `global::type`
  String? f1() {
    var _mark = this._mark();
    if (this.f14() case _?) {
      if (this.f2a() case var $1?) {
        if (this.f14() case _?) {
          return $1;
        }
      }
    }
    this._recover(_mark);
    if (this.apply(this.rj) case var $?) {
      return $;
    }
  }

  /// `global::namespaceReference`
  String f2() {
    var _mark = this._mark();
    if (this.f2d() case var _0) {
      if ([if (_0 case var _0?) _0] case (var $ && var _l1)) {
        if (_l1.isNotEmpty) {
          for (;;) {
            var _mark = this._mark();
            if (this.f2d() case var _0?) {
              _l1.add(_0);
              continue;
            }
            this._recover(_mark);
            break;
          }
        } else {
          this._recover(_mark);
        }
        return $.join(ParserGenerator.separator);
      }
    }
  }

  /// `global::name`
  String? f3() {
    var _mark = this._mark();
    if (this.f2() case var $0) {
      if (this.f2f() case var $1?) {
        if (($0, $1) case var $) {
          return $0.isEmpty ? $1 : "${$0}::${$1}";
        }
      }
    }
    this._recover(_mark);
    if (this.f4() case var $?) {
      return $;
    }
  }

  /// `global::namespacedIdentifier`
  String? f4() {
    if (this.f2() case var $0) {
      if (this.f6() case var $1?) {
        if (($0, $1) case var $) {
          return $0.isEmpty ? $1 : "${$0}::${$1}";
        }
      }
    }
  }

  /// `global::body`
  Node? f5() {
    if (this.f2g() case _?) {
      if (this.apply(this.r3) case var choice?) {
        if (this.fv() case _?) {
          return choice;
        }
      }
    }
  }

  /// `global::identifier`
  String? f6() {
    if (this.pos case var from) {
      if (matchPattern(_regexp.$1) case var $?) {
        if (this.pos case var to) {
          if (this.buffer.substring(from, to) case var span) {
            return span;
          }
        }
      }
    }
  }

  /// `global::number`
  int? f7() {
    if (matchPattern(_regexp.$2) case var _0?) {
      if ([_0] case (var $ && var _l1)) {
        for (;;) {
          var _mark = this._mark();
          if (matchPattern(_regexp.$2) case var _0?) {
            _l1.add(_0);
            continue;
          }
          this._recover(_mark);
          break;
        }
        return int.parse($.join());
      }
    }
  }

  /// `global::kw::decorator`
  Tag? f8() {
    var _mark = this._mark();
    if (this.f14() case _?) {
      if (this.matchPattern(_string.$3) case _?) {
        if (this.f14() case _?) {
          return Tag.rule;
        }
      }
    }
    this._recover(_mark);
    if (this.f14() case _?) {
      if (this.matchPattern(_string.$4) case _?) {
        if (this.f14() case _?) {
          return Tag.fragment;
        }
      }
    }
    this._recover(_mark);
    if (this.f14() case _?) {
      if (this.matchPattern(_string.$5) case _?) {
        if (this.f14() case _?) {
          return Tag.inline;
        }
      }
    }
  }

  /// `global::kw::var`
  String? f9() {
    if (this.f14() case _?) {
      if (this.matchPattern(_string.$6) case var $1?) {
        if (this.f14() case _?) {
          return $1;
        }
      }
    }
  }

  /// `global::mac::range`
  String? fa() {
    if (this.f14() case _?) {
      if (this.matchPattern(_string.$7) case var $1?) {
        if (this.f14() case _?) {
          return $1;
        }
      }
    }
  }

  /// `global::mac::flat`
  String? fb() {
    if (this.f14() case _?) {
      if (this.matchPattern(_string.$8) case var $1?) {
        if (this.f14() case _?) {
          return $1;
        }
      }
    }
  }

  /// `global::mac::sep`
  String? fc() {
    if (this.f14() case _?) {
      if (this.matchPattern(_string.$9) case var $1?) {
        if (this.f14() case _?) {
          return $1;
        }
      }
    }
  }

  /// `global::mac::choice`
  String? fd() {
    if (this.f14() case _?) {
      if (this.matchPattern(_string.$10) case var $1?) {
        if (this.f14() case _?) {
          return $1;
        }
      }
    }
  }

  /// `global::regexEscape::backslash`
  String? fe() {
    if (this.f14() case _?) {
      if (this.f2h() case var $1?) {
        if (this.f14() case _?) {
          return $1;
        }
      }
    }
  }

  /// `global::regexEscape::digit`
  String? ff() {
    if (this.f14() case _?) {
      if (this.f2i() case var $1?) {
        if (this.f14() case _?) {
          return $1;
        }
      }
    }
  }

  /// `global::regexEscape::word`
  String? fg() {
    if (this.f14() case _?) {
      if (this.f2j() case var $1?) {
        if (this.f14() case _?) {
          return $1;
        }
      }
    }
  }

  /// `global::regexEscape::whitespace`
  String? fh() {
    if (this.f14() case _?) {
      if (this.f2k() case var $1?) {
        if (this.f14() case _?) {
          return $1;
        }
      }
    }
  }

  /// `global::regexEscape::notDigit`
  String? fi() {
    if (this.f14() case _?) {
      if (this.f2l() case var $1?) {
        if (this.f14() case _?) {
          return $1;
        }
      }
    }
  }

  /// `global::regexEscape::notWord`
  String? fj() {
    if (this.f14() case _?) {
      if (this.f2m() case var $1?) {
        if (this.f14() case _?) {
          return $1;
        }
      }
    }
  }

  /// `global::regexEscape::notWhitespace`
  String? fk() {
    if (this.f14() case _?) {
      if (this.f2n() case var $1?) {
        if (this.f14() case _?) {
          return $1;
        }
      }
    }
  }

  /// `global::regexEscape::newline`
  String? fl() {
    if (this.f14() case _?) {
      if (this.f2o() case var $1?) {
        if (this.f14() case _?) {
          return $1;
        }
      }
    }
  }

  /// `global::regexEscape::carriageReturn`
  String? fm() {
    if (this.f14() case _?) {
      if (this.f2p() case var $1?) {
        if (this.f14() case _?) {
          return $1;
        }
      }
    }
  }

  /// `global::regexEscape::tab`
  String? fn() {
    if (this.f14() case _?) {
      if (this.f2q() case var $1?) {
        if (this.f14() case _?) {
          return $1;
        }
      }
    }
  }

  /// `global::regexEscape::formFeed`
  String? fo() {
    if (this.f14() case _?) {
      if (this.f2r() case var $1?) {
        if (this.f14() case _?) {
          return $1;
        }
      }
    }
  }

  /// `global::regexEscape::verticalTab`
  String? fp() {
    if (this.f14() case _?) {
      if (this.f2s() case var $1?) {
        if (this.f14() case _?) {
          return $1;
        }
      }
    }
  }

  /// `global::..`
  String? fq() {
    if (this.f14() case _?) {
      if (this.matchPattern(_string.$11) case var $1?) {
        if (this.f14() case _?) {
          return $1;
        }
      }
    }
  }

  /// `global::}`
  String? fr() {
    if (this.f14() case _?) {
      if (this.matchPattern(_string.$12) case var $1?) {
        if (this.f14() case _?) {
          return $1;
        }
      }
    }
  }

  /// `global::{`
  String? fs() {
    if (this.f14() case _?) {
      if (this.matchPattern(_string.$13) case var $1?) {
        if (this.f14() case _?) {
          return $1;
        }
      }
    }
  }

  /// `global::)`
  String? ft() {
    if (this.f14() case _?) {
      if (this.matchPattern(_string.$14) case var $1?) {
        if (this.f14() case _?) {
          return $1;
        }
      }
    }
  }

  /// `global::(`
  String? fu() {
    if (this.f14() case _?) {
      if (this.matchPattern(_string.$15) case var $1?) {
        if (this.f14() case _?) {
          return $1;
        }
      }
    }
  }

  /// `global::;`
  String? fv() {
    if (this.f14() case _?) {
      if (this.matchPattern(_string.$16) case var $1?) {
        if (this.f14() case _?) {
          return $1;
        }
      }
    }
  }

  /// `global::=`
  String? fw() {
    if (this.f14() case _?) {
      if (this.matchPattern(_string.$17) case var $1?) {
        if (this.f14() case _?) {
          return $1;
        }
      }
    }
  }

  /// `global::?`
  String? fx() {
    if (this.f14() case _?) {
      if (this.matchPattern(_string.$18) case var $1?) {
        if (this.f14() case _?) {
          return $1;
        }
      }
    }
  }

  /// `global::*`
  String? fy() {
    if (this.f14() case _?) {
      if (this.matchPattern(_string.$19) case var $1?) {
        if (this.f14() case _?) {
          return $1;
        }
      }
    }
  }

  /// `global::+`
  String? fz() {
    if (this.f14() case _?) {
      if (this.matchPattern(_string.$20) case var $1?) {
        if (this.f14() case _?) {
          return $1;
        }
      }
    }
  }

  /// `global::,`
  String? f10() {
    if (this.f14() case _?) {
      if (this.matchPattern(_string.$21) case var $1?) {
        if (this.f14() case _?) {
          return $1;
        }
      }
    }
  }

  /// `global:::`
  String? f11() {
    if (this.f14() case _?) {
      if (this.matchPattern(_string.$22) case var $1?) {
        if (this.f14() case _?) {
          return $1;
        }
      }
    }
  }

  /// `global::|`
  String? f12() {
    if (this.f14() case _?) {
      if (this.matchPattern(_string.$23) case var $1?) {
        if (this.f14() case _?) {
          return $1;
        }
      }
    }
  }

  /// `global::.`
  String? f13() {
    if (this.f14() case _?) {
      if (this.matchPattern(_string.$24) case var $1?) {
        if (this.f14() case _?) {
          return $1;
        }
      }
    }
  }

  /// `global::_`
  String? f14() {
    if (matchPattern(_regexp.$3) case var $?) {
      return "";
    }
  }

  /// `ROOT`
  ParserGenerator? f15() {
    if (this.apply(this.r0) case var $?) {
      return $;
    }
  }

  /// `global::dart::literal::string::body`
  late final f16 = () {
    var _mark = this._mark();
    if (this.matchPattern(_string.$26) case var _2?) {
      if ([_2].nullable() case var _l3) {
        if (_l3 != null) {
          while (_l3.length < 1) {
            var _mark = this._mark();
            if (this.matchPattern(_string.$26) case var _2?) {
              _l3.add(_2);
              continue;
            }
            this._recover(_mark);
            break;
          }
        }
        if (_l3 case _) {
          if (this.matchPattern(_string.$25) case _?) {
            var _mark = this._mark();
            if (this.f2t() case var _0) {
              if ([if (_0 case var _0?) _0] case var _l1) {
                if (_l1.isNotEmpty) {
                  for (;;) {
                    var _mark = this._mark();
                    if (this.f2t() case var _0?) {
                      _l1.add(_0);
                      continue;
                    }
                    this._recover(_mark);
                    break;
                  }
                } else {
                  this._recover(_mark);
                }
                if (this.matchPattern(_string.$25) case _?) {
                  return ();
                }
              }
            }
          }
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$26) case var _6?) {
      if ([_6].nullable() case var _l7) {
        if (_l7 != null) {
          while (_l7.length < 1) {
            var _mark = this._mark();
            if (this.matchPattern(_string.$26) case var _6?) {
              _l7.add(_6);
              continue;
            }
            this._recover(_mark);
            break;
          }
        }
        if (_l7 case _) {
          if (this.matchPattern(_string.$27) case _?) {
            var _mark = this._mark();
            if (this.f2u() case var _4) {
              if ([if (_4 case var _4?) _4] case var _l5) {
                if (_l5.isNotEmpty) {
                  for (;;) {
                    var _mark = this._mark();
                    if (this.f2u() case var _4?) {
                      _l5.add(_4);
                      continue;
                    }
                    this._recover(_mark);
                    break;
                  }
                } else {
                  this._recover(_mark);
                }
                if (this.matchPattern(_string.$27) case _?) {
                  return ();
                }
              }
            }
          }
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$26) case var _10?) {
      if ([_10].nullable() case var _l11) {
        if (_l11 != null) {
          while (_l11.length < 1) {
            var _mark = this._mark();
            if (this.matchPattern(_string.$26) case var _10?) {
              _l11.add(_10);
              continue;
            }
            this._recover(_mark);
            break;
          }
        }
        if (_l11 case _) {
          if (this.matchPattern(_string.$28) case _?) {
            var _mark = this._mark();
            if (this.f2v() case var _8) {
              if ([if (_8 case var _8?) _8] case var _l9) {
                if (_l9.isNotEmpty) {
                  for (;;) {
                    var _mark = this._mark();
                    if (this.f2v() case var _8?) {
                      _l9.add(_8);
                      continue;
                    }
                    this._recover(_mark);
                    break;
                  }
                } else {
                  this._recover(_mark);
                }
                if (this.matchPattern(_string.$28) case _?) {
                  return ();
                }
              }
            }
          }
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$26) case var _14?) {
      if ([_14].nullable() case var _l15) {
        if (_l15 != null) {
          while (_l15.length < 1) {
            var _mark = this._mark();
            if (this.matchPattern(_string.$26) case var _14?) {
              _l15.add(_14);
              continue;
            }
            this._recover(_mark);
            break;
          }
        }
        if (_l15 case _) {
          if (this.matchPattern(_string.$29) case _?) {
            var _mark = this._mark();
            if (this.f2w() case var _12) {
              if ([if (_12 case var _12?) _12] case var _l13) {
                if (_l13.isNotEmpty) {
                  for (;;) {
                    var _mark = this._mark();
                    if (this.f2w() case var _12?) {
                      _l13.add(_12);
                      continue;
                    }
                    this._recover(_mark);
                    break;
                  }
                } else {
                  this._recover(_mark);
                }
                if (this.matchPattern(_string.$29) case _?) {
                  return ();
                }
              }
            }
          }
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$25) case _?) {
      var _mark = this._mark();
      if (this.f2x() case var _16) {
        if ([if (_16 case var _16?) _16] case var _l17) {
          if (_l17.isNotEmpty) {
            for (;;) {
              var _mark = this._mark();
              if (this.f2x() case var _16?) {
                _l17.add(_16);
                continue;
              }
              this._recover(_mark);
              break;
            }
          } else {
            this._recover(_mark);
          }
          if (this.matchPattern(_string.$25) case _?) {
            return ();
          }
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$27) case _?) {
      var _mark = this._mark();
      if (this.f2y() case var _18) {
        if ([if (_18 case var _18?) _18] case var _l19) {
          if (_l19.isNotEmpty) {
            for (;;) {
              var _mark = this._mark();
              if (this.f2y() case var _18?) {
                _l19.add(_18);
                continue;
              }
              this._recover(_mark);
              break;
            }
          } else {
            this._recover(_mark);
          }
          if (this.matchPattern(_string.$27) case _?) {
            return ();
          }
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$28) case _?) {
      var _mark = this._mark();
      if (this.f2z() case var _20) {
        if ([if (_20 case var _20?) _20] case var _l21) {
          if (_l21.isNotEmpty) {
            for (;;) {
              var _mark = this._mark();
              if (this.f2z() case var _20?) {
                _l21.add(_20);
                continue;
              }
              this._recover(_mark);
              break;
            }
          } else {
            this._recover(_mark);
          }
          if (this.matchPattern(_string.$28) case _?) {
            return ();
          }
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$29) case _?) {
      var _mark = this._mark();
      if (this.f30() case var _22) {
        if ([if (_22 case var _22?) _22] case var _l23) {
          if (_l23.isNotEmpty) {
            for (;;) {
              var _mark = this._mark();
              if (this.f30() case var _22?) {
                _l23.add(_22);
                continue;
              }
              this._recover(_mark);
              break;
            }
          } else {
            this._recover(_mark);
          }
          if (this.matchPattern(_string.$29) case _?) {
            return ();
          }
        }
      }
    }
  };

  /// `global::dart::literal::string::interpolation`
  late final f17 = () {
    var _mark = this._mark();
    if (this.matchPattern(_string.$30) case var $0?) {
      if (this.matchPattern(_string.$13) case var $1?) {
        if (this.apply(this.ri)! case var $2) {
          if (this.matchPattern(_string.$12) case var $3?) {
            return ($0, $1, $2, $3);
          }
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$30) case var $0?) {
      if (this.apply(this.rh) case var $1?) {
        return ($0, $1);
      }
    }
  };

  /// `fragment0`
  late final f18 = () {
    if (this.f12() case var $0?) {
      if (this.f12() case var $1) {
        return ($0, $1);
      }
    }
  };

  /// `fragment1`
  late final f19 = () {
    if (this.f12() case var $0?) {
      if (this.f12() case var $1) {
        return ($0, $1);
      }
    }
  };

  /// `fragment2`
  late final f1a = () {
    if (this.f14() case _?) {
      if (this.matchPattern(_string.$31) case var $1?) {
        if (this.f14() case _?) {
          return $1;
        }
      }
    }
  };

  /// `fragment3`
  late final f1b = () {
    if (this.f14() case _?) {
      if (this.matchPattern(_string.$32) case var $1?) {
        if (this.f14() case _?) {
          return $1;
        }
      }
    }
  };

  /// `fragment4`
  late final f1c = () {
    if (this.f1b() case _?) {
      if (this.f7() case var $1?) {
        return $1;
      }
    }
  };

  /// `fragment5`
  late final f1d = () {
    if (this.f14() case _?) {
      if (this.matchPattern(_string.$33) case var $1?) {
        if (this.f14() case _?) {
          return $1;
        }
      }
    }
  };

  /// `fragment6`
  late final f1e = () {
    if (this.f14() case _?) {
      if (this.matchPattern(_string.$34) case var $1?) {
        if (this.f14() case _?) {
          return $1;
        }
      }
    }
  };

  /// `fragment7`
  late final f1f = () {
    if (this.f14() case _?) {
      if (this.matchPattern(_string.$35) case var $1?) {
        if (this.f14() case _?) {
          return $1;
        }
      }
    }
  };

  /// `fragment8`
  late final f1g = () {
    if (this.f14() case _?) {
      if (this.matchPattern(_string.$36) case var $1?) {
        if (this.f14() case _?) {
          return $1;
        }
      }
    }
  };

  /// `fragment9`
  late final f1h = () {
    if (this.f14() case _?) {
      if (this.matchPattern(_string.$37) case var $1?) {
        if (this.f14() case _?) {
          return $1;
        }
      }
    }
  };

  /// `fragment10`
  late final f1i = () {
    if (this.apply(this.r3) case var $0?) {
      if (this.ft() case _?) {
        return $0;
      }
    }
  };

  /// `fragment11`
  late final f1j = () {
    var _mark = this._mark();
    if (this.matchPattern(_string.$38) case var $?) {
      return {(32, 32)};
    }
    this._recover(_mark);
    if (this.ff() case var $?) {
      return {(48, 57)};
    }
    this._recover(_mark);
    if (this.fg() case var $?) {
      return {(64 + 1, 64 + 26), (96 + 1, 96 + 26)};
    }
    this._recover(_mark);
    if (this.fh() case var $?) {
      return {(9, 13), (32, 32)};
    }
    this._recover(_mark);
    if (this.fl() case var $?) {
      return {(10, 10)};
    }
    this._recover(_mark);
    if (this.fm() case var $?) {
      return {(13, 13)};
    }
    this._recover(_mark);
    if (this.fn() case var $?) {
      return {(9, 9)};
    }
    this._recover(_mark);
    if (this.fe() case var $?) {
      return {(92, 92)};
    }
    this._recover(_mark);
    if (this.f0() case var l?) {
      if (this.matchPattern(_string.$39) case _?) {
        if (this.f0() case var r?) {
          return {(l.codeUnitAt(0), r.codeUnitAt(0))};
        }
      }
    }
    this._recover(_mark);
    if (this.f0() case var $?) {
      return {($.codeUnitAt(0), $.codeUnitAt(0))};
    }
  };

  /// `fragment12`
  late final f1k = () {
    if (this.f14() case _?) {
      if (this.matchPattern(_string.$40) case _?) {
        if (this.f1j() case var _0?) {
          if ([_0] case (var elements && var _l1)) {
            for (;;) {
              var _mark = this._mark();
              if (this.f14() case _?) {
                if (this.f1j() case var _0?) {
                  _l1.add(_0);
                  continue;
                }
              }
              this._recover(_mark);
              break;
            }
            if (this.matchPattern(_string.$2) case _?) {
              if (this.f14() case _?) {
                return RangeNode(elements.expand((e) => e).toSet());
              }
            }
          }
        }
      }
    }
  };

  /// `fragment13`
  late final f1l = () {
    var _mark = this._mark();
    if (this.matchPattern(_string.$1) case var $0?) {
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $1) {
          if ($1 case var $) {
            return r"\" + $;
          }
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$41) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  };

  /// `fragment14`
  late final f1m = () {
    if (this.f1l() case var _0?) {
      if ([_0] case (var $ && var _l1)) {
        for (;;) {
          var _mark = this._mark();
          if (this.f1l() case var _0?) {
            _l1.add(_0);
            continue;
          }
          this._recover(_mark);
          break;
        }
        return $.join();
      }
    }
  };

  /// `fragment15`
  late final f1n = () {
    var _mark = this._mark();
    if (this.matchPattern(_string.$25) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  };

  /// `fragment16`
  late final f1o = () {
    var _mark = this._mark();
    if (this.matchPattern(_string.$27) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  };

  /// `fragment17`
  late final f1p = () {
    var _mark = this._mark();
    if (this.matchPattern(_string.$28) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  };

  /// `fragment18`
  late final f1q = () {
    var _mark = this._mark();
    if (this.matchPattern(_string.$29) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  };

  /// `fragment19`
  late final f1r = () {
    var _mark = this._mark();
    if (this.matchPattern(_string.$1) case var $0?) {
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $1) {
          return ($0, $1);
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$25) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  };

  /// `fragment20`
  late final f1s = () {
    var _mark = this._mark();
    if (this.matchPattern(_string.$1) case var $0?) {
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $1) {
          return ($0, $1);
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$27) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  };

  /// `fragment21`
  late final f1t = () {
    var _mark = this._mark();
    if (this.matchPattern(_string.$1) case var $0?) {
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $1) {
          return ($0, $1);
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$28) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  };

  /// `fragment22`
  late final f1u = () {
    var _mark = this._mark();
    if (this.matchPattern(_string.$1) case var $0?) {
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $1) {
          return ($0, $1);
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$29) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  };

  /// `fragment23`
  late final f1v = () {
    var _mark = this._mark();
    if (this.matchPattern(_string.$42) case var $0?) {
      var _mark = this._mark();
      if (this.f1n() case var _0) {
        if ([if (_0 case var _0?) _0] case (var $1 && var _l1)) {
          if (_l1.isNotEmpty) {
            for (;;) {
              var _mark = this._mark();
              if (this.f1n() case var _0?) {
                _l1.add(_0);
                continue;
              }
              this._recover(_mark);
              break;
            }
          } else {
            this._recover(_mark);
          }
          if (this.matchPattern(_string.$25) case var $2?) {
            if ($1 case var $) {
              return $.join();
            }
          }
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$43) case var $0?) {
      var _mark = this._mark();
      if (this.f1o() case var _2) {
        if ([if (_2 case var _2?) _2] case (var $1 && var _l3)) {
          if (_l3.isNotEmpty) {
            for (;;) {
              var _mark = this._mark();
              if (this.f1o() case var _2?) {
                _l3.add(_2);
                continue;
              }
              this._recover(_mark);
              break;
            }
          } else {
            this._recover(_mark);
          }
          if (this.matchPattern(_string.$27) case var $2?) {
            if ($1 case var $) {
              return $.join();
            }
          }
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$44) case var $0?) {
      var _mark = this._mark();
      if (this.f1p() case var _4) {
        if ([if (_4 case var _4?) _4] case (var $1 && var _l5)) {
          if (_l5.isNotEmpty) {
            for (;;) {
              var _mark = this._mark();
              if (this.f1p() case var _4?) {
                _l5.add(_4);
                continue;
              }
              this._recover(_mark);
              break;
            }
          } else {
            this._recover(_mark);
          }
          if (this.matchPattern(_string.$28) case var $2?) {
            if ($1 case var $) {
              return $.join();
            }
          }
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$45) case var $0?) {
      var _mark = this._mark();
      if (this.f1q() case var _6) {
        if ([if (_6 case var _6?) _6] case (var $1 && var _l7)) {
          if (_l7.isNotEmpty) {
            for (;;) {
              var _mark = this._mark();
              if (this.f1q() case var _6?) {
                _l7.add(_6);
                continue;
              }
              this._recover(_mark);
              break;
            }
          } else {
            this._recover(_mark);
          }
          if (this.matchPattern(_string.$29) case var $2?) {
            if ($1 case var $) {
              return $.join();
            }
          }
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$25) case var $0?) {
      var _mark = this._mark();
      if (this.f1r() case var _8) {
        if ([if (_8 case var _8?) _8] case (var $1 && var _l9)) {
          if (_l9.isNotEmpty) {
            for (;;) {
              var _mark = this._mark();
              if (this.f1r() case var _8?) {
                _l9.add(_8);
                continue;
              }
              this._recover(_mark);
              break;
            }
          } else {
            this._recover(_mark);
          }
          if (this.matchPattern(_string.$25) case var $2?) {
            if ($1 case var $) {
              return $.join();
            }
          }
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$27) case var $0?) {
      var _mark = this._mark();
      if (this.f1s() case var _10) {
        if ([if (_10 case var _10?) _10] case (var $1 && var _l11)) {
          if (_l11.isNotEmpty) {
            for (;;) {
              var _mark = this._mark();
              if (this.f1s() case var _10?) {
                _l11.add(_10);
                continue;
              }
              this._recover(_mark);
              break;
            }
          } else {
            this._recover(_mark);
          }
          if (this.matchPattern(_string.$27) case var $2?) {
            if ($1 case var $) {
              return $.join();
            }
          }
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$28) case var $0?) {
      var _mark = this._mark();
      if (this.f1t() case var _12) {
        if ([if (_12 case var _12?) _12] case (var $1 && var _l13)) {
          if (_l13.isNotEmpty) {
            for (;;) {
              var _mark = this._mark();
              if (this.f1t() case var _12?) {
                _l13.add(_12);
                continue;
              }
              this._recover(_mark);
              break;
            }
          } else {
            this._recover(_mark);
          }
          if (this.matchPattern(_string.$28) case var $2?) {
            if ($1 case var $) {
              return $.join();
            }
          }
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$29) case var $0?) {
      var _mark = this._mark();
      if (this.f1u() case var _14) {
        if ([if (_14 case var _14?) _14] case (var $1 && var _l15)) {
          if (_l15.isNotEmpty) {
            for (;;) {
              var _mark = this._mark();
              if (this.f1u() case var _14?) {
                _l15.add(_14);
                continue;
              }
              this._recover(_mark);
              break;
            }
          } else {
            this._recover(_mark);
          }
          if (this.matchPattern(_string.$29) case var $2?) {
            if ($1 case var $) {
              return $.join();
            }
          }
        }
      }
    }
  };

  /// `fragment24`
  late final f1w = () {
    var _mark = this._mark();
    if (this.matchPattern(_string.$46) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  };

  /// `fragment25`
  late final f1x = () {
    var _mark = this._mark();
    if (this.apply(this.rg) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$13) case var $0?) {
      if (this.apply(this.rf)! case var $1) {
        if (this.matchPattern(_string.$12) case var $2?) {
          if ($1 case var $) {
            return "{" + $ + "}";
          }
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$15) case var $0?) {
      if (this.apply(this.rf)! case var $1) {
        if (this.matchPattern(_string.$14) case var $2?) {
          if ($1 case var $) {
            return "(" + $ + ")";
          }
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$40) case var $0?) {
      if (this.apply(this.rf)! case var $1) {
        if (this.matchPattern(_string.$2) case var $2?) {
          if ($1 case var $) {
            return "[" + $ + "]";
          }
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$12) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  };

  /// `fragment26`
  late final f1y = () {
    var _mark = this._mark();
    if (this.matchPattern(_string.$46) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  };

  /// `fragment27`
  late final f1z = () {
    var _mark = this._mark();
    if (matchPattern(_regexp.$4) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$16) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$14) case var $?) {
      return $;
    }
  };

  /// `fragment28`
  late final f20 = () {
    var _mark = this._mark();
    if (this.apply(this.rg) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$13) case var $0?) {
      if (this.apply(this.rf)! case var $1) {
        if (this.matchPattern(_string.$12) case var $2?) {
          if ($1 case var $) {
            return "{" + $ + "}";
          }
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$15) case var $0?) {
      if (this.apply(this.rf)! case var $1) {
        if (this.matchPattern(_string.$14) case var $2?) {
          if ($1 case var $) {
            return "(" + $ + ")";
          }
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$40) case var $0?) {
      if (this.apply(this.rf)! case var $1) {
        if (this.matchPattern(_string.$2) case var $2?) {
          if ($1 case var $) {
            return "[" + $ + "]";
          }
        }
      }
    }
    this._recover(_mark);
    if (this.f1z() case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  };

  /// `fragment29`
  late final f21 = () {
    var _mark = this._mark();
    if (this.matchPattern(_string.$12) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$14) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$2) case var $?) {
      return $;
    }
  };

  /// `fragment30`
  late final f22 = () {
    var _mark = this._mark();
    if (this.apply(this.rg) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$13) case var $0?) {
      if (this.apply(this.rf)! case var $1) {
        if (this.matchPattern(_string.$12) case var $2?) {
          if ($1 case var $) {
            return "{" + $ + "}";
          }
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$15) case var $0?) {
      if (this.apply(this.rf)! case var $1) {
        if (this.matchPattern(_string.$14) case var $2?) {
          if ($1 case var $) {
            return "(" + $ + ")";
          }
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$40) case var $0?) {
      if (this.apply(this.rf)! case var $1) {
        if (this.matchPattern(_string.$2) case var $2?) {
          if ($1 case var $) {
            return "[" + $ + "]";
          }
        }
      }
    }
    this._recover(_mark);
    if (this.f21() case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  };

  /// `fragment31`
  late final f23 = () {
    if (this.pos case var from) {
      if (this.f16() case var $?) {
        if (this.pos case var to) {
          if (this.buffer.substring(from, to) case var span) {
            return span;
          }
        }
      }
    }
  };

  /// `fragment32`
  late final f24 = () {
    var _mark = this._mark();
    if (this.apply(this.rg) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$13) case var $0?) {
      if (this.apply(this.ri)! case var $1) {
        if (this.matchPattern(_string.$12) case var $2?) {
          if ($1 case var $) {
            return "{" + $ + "}";
          }
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$12) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  };

  /// `fragment33`
  late final f25 = () {
    if (this.f14() case _?) {
      if (this.matchPattern(_string.$47) case var $1?) {
        if (this.f14() case _?) {
          return $1;
        }
      }
    }
  };

  /// `fragment34`
  late final f26 = () {
    if (this.f14() case _?) {
      if (this.matchPattern(_string.$48) case var $1?) {
        if (this.f14() case _?) {
          return $1;
        }
      }
    }
  };

  /// `fragment35`
  late final f27 = () {
    if (this.f14() case _?) {
      if (this.matchPattern(_string.$40) case var $1?) {
        if (this.f14() case _?) {
          return $1;
        }
      }
    }
  };

  /// `fragment36`
  late final f28 = () {
    if (this.f14() case _?) {
      if (this.matchPattern(_string.$2) case var $1?) {
        if (this.f14() case _?) {
          return $1;
        }
      }
    }
  };

  /// `fragment37`
  late final f29 = () {
    var _mark = this._mark();
    if (this.matchPattern(_string.$46) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  };

  /// `fragment38`
  late final f2a = () {
    if (this.matchPattern(_string.$46) case var $0?) {
      if (this.f29() case var _0) {
        var _mark = this._mark();
        var _l1 = [if (_0 case var _0?) _0];
        if (_l1.isNotEmpty) {
          for (;;) {
            var _mark = this._mark();
            if (this.f29() case var _0?) {
              _l1.add(_0);
              continue;
            }
            this._recover(_mark);
            break;
          }
        } else {
          this._recover(_mark);
        }
        if (_l1 case var $1) {
          if (this.matchPattern(_string.$46) case var $2?) {
            if ($1 case var $) {
              return $.join();
            }
          }
        }
      }
    }
  };

  /// `fragment39`
  late final f2b = () {
    var _mark = this._mark();
    if (this.matchPattern(_string.$49) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$11) case (var $0 && null)) {
      this._recover(_mark);
      if (this.matchPattern(_string.$24) case var $1?) {
        return ($0, $1);
      }
    }
  };

  /// `fragment40`
  late final f2c = () {
    var _mark = this._mark();
    if (this.fa() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.fb() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.fc() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.fd() case var $?) {
      return $;
    }
  };

  /// `fragment41`
  late final f2d = () {
    if (this.f6() case var $0?) {
      if (this.f2b() case _?) {
        var _mark = this._mark();
        if (this.f2c() case null) {
          this._recover(_mark);
          return $0;
        }
      }
    }
  };

  /// `fragment42`
  late final f2e = () {
    var _mark = this._mark();
    if (this.matchPattern(_string.$46) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  };

  /// `fragment43`
  late final f2f = () {
    if (this.matchPattern(_string.$46) case var $0?) {
      var _mark = this._mark();
      if (this.f2e() case var _0) {
        if ([if (_0 case var _0?) _0] case (var $1 && var _l1)) {
          if (_l1.isNotEmpty) {
            for (;;) {
              var _mark = this._mark();
              if (this.f2e() case var _0?) {
                _l1.add(_0);
                continue;
              }
              this._recover(_mark);
              break;
            }
          } else {
            this._recover(_mark);
          }
          if (this.matchPattern(_string.$46) case var $2?) {
            if ($1 case var $) {
              return $.join();
            }
          }
        }
      }
    }
  };

  /// `fragment44`
  late final f2g = () {
    var _mark = this._mark();
    if (this.f11() case var $0) {
      if (this.fw() case var $1?) {
        return ($0, $1);
      }
    }
    this._recover(_mark);
    if (this.f14() case _?) {
      if (this.matchPattern(_string.$50) case var $1?) {
        if (this.f14() case _?) {
          return $1;
        }
      }
    }
    this._recover(_mark);
    if (this.f14() case _?) {
      if (this.matchPattern(_string.$51) case var $1?) {
        if (this.f14() case _?) {
          return $1;
        }
      }
    }
  };

  /// `fragment45`
  late final f2h = () {
    if (this.pos case var from) {
      if (this.matchPattern(_string.$1) case _?) {
        if (this.matchPattern(_string.$1) case _?) {
          if (this.pos case var to) {
            if (this.buffer.substring(from, to) case var span) {
              return span;
            }
          }
        }
      }
    }
  };

  /// `fragment46`
  late final f2i = () {
    if (this.pos case var from) {
      if (this.matchPattern(_string.$1) case _?) {
        if (this.matchPattern(_string.$52) case _?) {
          if (this.pos case var to) {
            if (this.buffer.substring(from, to) case var span) {
              return span;
            }
          }
        }
      }
    }
  };

  /// `fragment47`
  late final f2j = () {
    if (this.pos case var from) {
      if (this.matchPattern(_string.$1) case _?) {
        if (this.matchPattern(_string.$53) case _?) {
          if (this.pos case var to) {
            if (this.buffer.substring(from, to) case var span) {
              return span;
            }
          }
        }
      }
    }
  };

  /// `fragment48`
  late final f2k = () {
    if (this.pos case var from) {
      if (this.matchPattern(_string.$1) case _?) {
        if (this.matchPattern(_string.$54) case _?) {
          if (this.pos case var to) {
            if (this.buffer.substring(from, to) case var span) {
              return span;
            }
          }
        }
      }
    }
  };

  /// `fragment49`
  late final f2l = () {
    if (this.pos case var from) {
      if (this.matchPattern(_string.$1) case _?) {
        if (this.matchPattern(_string.$52) case _?) {
          if (this.pos case var to) {
            if (this.buffer.substring(from, to) case var span) {
              return span;
            }
          }
        }
      }
    }
  };

  /// `fragment50`
  late final f2m = () {
    if (this.pos case var from) {
      if (this.matchPattern(_string.$1) case _?) {
        if (this.matchPattern(_string.$53) case _?) {
          if (this.pos case var to) {
            if (this.buffer.substring(from, to) case var span) {
              return span;
            }
          }
        }
      }
    }
  };

  /// `fragment51`
  late final f2n = () {
    if (this.pos case var from) {
      if (this.matchPattern(_string.$1) case _?) {
        if (this.matchPattern(_string.$54) case _?) {
          if (this.pos case var to) {
            if (this.buffer.substring(from, to) case var span) {
              return span;
            }
          }
        }
      }
    }
  };

  /// `fragment52`
  late final f2o = () {
    if (this.pos case var from) {
      if (this.matchPattern(_string.$1) case _?) {
        if (this.matchPattern(_string.$55) case _?) {
          if (this.pos case var to) {
            if (this.buffer.substring(from, to) case var span) {
              return span;
            }
          }
        }
      }
    }
  };

  /// `fragment53`
  late final f2p = () {
    if (this.pos case var from) {
      if (this.matchPattern(_string.$1) case _?) {
        if (this.matchPattern(_string.$26) case _?) {
          if (this.pos case var to) {
            if (this.buffer.substring(from, to) case var span) {
              return span;
            }
          }
        }
      }
    }
  };

  /// `fragment54`
  late final f2q = () {
    if (this.pos case var from) {
      if (this.matchPattern(_string.$1) case _?) {
        if (this.matchPattern(_string.$56) case _?) {
          if (this.pos case var to) {
            if (this.buffer.substring(from, to) case var span) {
              return span;
            }
          }
        }
      }
    }
  };

  /// `fragment55`
  late final f2r = () {
    if (this.pos case var from) {
      if (this.matchPattern(_string.$1) case _?) {
        if (this.matchPattern(_string.$57) case _?) {
          if (this.pos case var to) {
            if (this.buffer.substring(from, to) case var span) {
              return span;
            }
          }
        }
      }
    }
  };

  /// `fragment56`
  late final f2s = () {
    if (this.pos case var from) {
      if (this.matchPattern(_string.$1) case _?) {
        if (this.matchPattern(_string.$58) case _?) {
          if (this.pos case var to) {
            if (this.buffer.substring(from, to) case var span) {
              return span;
            }
          }
        }
      }
    }
  };

  /// `fragment57`
  late final f2t = () {
    var _mark = this._mark();
    if (this.matchPattern(_string.$25) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  };

  /// `fragment58`
  late final f2u = () {
    var _mark = this._mark();
    if (this.matchPattern(_string.$27) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  };

  /// `fragment59`
  late final f2v = () {
    var _mark = this._mark();
    if (this.matchPattern(_string.$28) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  };

  /// `fragment60`
  late final f2w = () {
    var _mark = this._mark();
    if (this.matchPattern(_string.$29) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  };

  /// `fragment61`
  late final f2x = () {
    var _mark = this._mark();
    if (this.matchPattern(_string.$1) case _?) {
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $1) {
          return $1;
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$30) case var $0?) {
      this._recover(_mark);
      if (this.f17() case var $1?) {
        return ($0, $1);
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$25) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  };

  /// `fragment62`
  late final f2y = () {
    var _mark = this._mark();
    if (this.matchPattern(_string.$1) case _?) {
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $1) {
          return $1;
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$30) case var $0?) {
      this._recover(_mark);
      if (this.f17() case var $1?) {
        return ($0, $1);
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$27) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  };

  /// `fragment63`
  late final f2z = () {
    var _mark = this._mark();
    if (this.matchPattern(_string.$1) case _?) {
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $1) {
          return $1;
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$30) case var $0?) {
      this._recover(_mark);
      if (this.f17() case var $1?) {
        return ($0, $1);
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$28) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  };

  /// `fragment64`
  late final f30 = () {
    var _mark = this._mark();
    if (this.matchPattern(_string.$1) case _?) {
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $1) {
          return $1;
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$30) case var $0?) {
      this._recover(_mark);
      if (this.f17() case var $1?) {
        return ($0, $1);
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$29) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  };

  /// `global::document`
  ParserGenerator? r0() {
    if (this.pos <= 0) {
      if (this.apply(this.r1) case var $1) {
        if (this.apply(this.r2) case var _0?) {
          if ([_0] case (var $2 && var _l1)) {
            for (;;) {
              var _mark = this._mark();
              if (this.f14() case _?) {
                if (this.apply(this.r2) case var _0?) {
                  _l1.add(_0);
                  continue;
                }
              }
              this._recover(_mark);
              break;
            }
            if (this.f14() case _) {
              if (this.pos >= this.buffer.length) {
                return ParserGenerator.fromParsed(preamble: $1, statements: $2);
              }
            }
          }
        }
      }
    }
  }

  /// `global::preamble`
  String? r1() {
    if (this.fs() case _?) {
      if (this.f14() case _?) {
        if (this.apply(this.rd) case (var $2 && var code)?) {
          if (this.f14() case _?) {
            if (this.fr() case _?) {
              return $2;
            }
          }
        }
      }
    }
  }

  /// `global::statement`
  Statement? r2() {
    var _mark = this._mark();
    if (this.f8() case var outer_decorator) {
      if (this.f1() case var type) {
        if (this.f6() case var name?) {
          if (this.fw() case _?) {
            if (this.fd() case _?) {
              if (this.f8() case var inner_decorator) {
                if (this.fs() case _?) {
                  if (this.apply(this.r2) case var _0?) {
                    if ([_0] case (var statements && var _l1)) {
                      for (;;) {
                        var _mark = this._mark();
                        if (this.f14() case _?) {
                          if (this.apply(this.r2) case var _0?) {
                            _l1.add(_0);
                            continue;
                          }
                        }
                        this._recover(_mark);
                        break;
                      }
                      if (this.fr() case _?) {
                        if (this.fv() case _) {
                          return HybridNamespaceStatement(
                            type,
                            name,
                            statements,
                            outerTag: outer_decorator,
                            innerTag: inner_decorator,
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
    }
    this._recover(_mark);
    if (this.f8() case var outer_decorator) {
      if (this.f1() case var type) {
        if (this.fu() case _?) {
          if (this.ft() case _?) {
            if (this.fw() case _?) {
              if (this.fd() case _?) {
                if (this.f8() case var inner_decorator) {
                  if (this.fs() case _?) {
                    if (this.apply(this.r2) case var _2?) {
                      if ([_2] case (var statements && var _l3)) {
                        for (;;) {
                          var _mark = this._mark();
                          if (this.f14() case _?) {
                            if (this.apply(this.r2) case var _2?) {
                              _l3.add(_2);
                              continue;
                            }
                          }
                          this._recover(_mark);
                          break;
                        }
                        if (this.fr() case _?) {
                          if (this.fv() case _) {
                            return HybridNamespaceStatement(
                              type,
                              null,
                              statements,
                              outerTag: outer_decorator,
                              innerTag: inner_decorator,
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
      }
    }
    this._recover(_mark);
    if (this.f8() case var decorator) {
      if (this.f6() case var name) {
        if (this.fs() case _?) {
          if (this.apply(this.r2) case var _4?) {
            if ([_4] case (var statements && var _l5)) {
              for (;;) {
                var _mark = this._mark();
                if (this.f14() case _?) {
                  if (this.apply(this.r2) case var _4?) {
                    _l5.add(_4);
                    continue;
                  }
                }
                this._recover(_mark);
                break;
              }
              if (this.fr() case _?) {
                return NamespaceStatement(name, statements, tag: decorator);
              }
            }
          }
        }
      }
    }
    this._recover(_mark);
    if (this.f8() case var decorator) {
      if (this.f1() case var type) {
        if (this.f3() case var name?) {
          if (this.fv() case _?) {
            return DeclarationTypeStatement(type, name, tag: decorator);
          }
        }
      }
    }
    this._recover(_mark);
    if (this.f8() case var decorator) {
      if (this.f9() case _) {
        if (this.f1() case var type) {
          if (this.f3() case var name?) {
            if (this.fv() case _?) {
              return DeclarationTypeStatement(type, name, tag: decorator);
            }
          }
        }
      }
    }
    this._recover(_mark);
    if (this.f8() case var decorator) {
      if (this.f9() case _) {
        if (this.f3() case var name?) {
          if (this.f5() case var body?) {
            return DeclarationStatement(null, name, body, tag: decorator);
          }
        }
      }
    }
    this._recover(_mark);
    if (this.f8() case var decorator) {
      if (this.f1() case var type?) {
        if (this.f3() case var name?) {
          if (this.f5() case var body?) {
            return DeclarationStatement(type, name, body, tag: decorator);
          }
        }
      }
    }
    this._recover(_mark);
    if (this.f8() case var decorator) {
      if (this.f9() case _) {
        if (this.f3() case var name?) {
          if (this.f11() case _?) {
            if (this.f1() case var type?) {
              if (this.f5() case var body?) {
                return DeclarationStatement(type, name, body, tag: decorator);
              }
            }
          }
        }
      }
    }
  }

  /// `global::choice`
  Node? r3() {
    if (this.f18() case _) {
      if (this.apply(this.r4) case var _0?) {
        if ([_0] case (var options && var _l1)) {
          for (;;) {
            var _mark = this._mark();
            if (this.f19() case _?) {
              if (this.apply(this.r4) case var _0?) {
                _l1.add(_0);
                continue;
              }
            }
            this._recover(_mark);
            break;
          }
          return options.length == 1 ? options.single : ChoiceNode(options);
        }
      }
    }
  }

  /// `global::acted`
  Node? r4() {
    var _mark = this._mark();
    if (this.pos case var from) {
      if (this.apply(this.r5) case var sequence?) {
        if (this.f1a() case _?) {
          if (this.f14() case _?) {
            if (this.apply(this.re) case var code?) {
              if (this.f14() case _?) {
                if (this.pos case var to) {
                  if (this.buffer.substring(from, to) case var span) {
                    return InlineActionNode(
                      sequence,
                      code.trimRight(),
                      areIndicesProvided:
                          code.contains(_regexps.from) && code.contains(_regexps.to),
                      isSpanUsed: code.contains(_regexps.span),
                    );
                  }
                }
              }
            }
          }
        }
      }
    }

    this._recover(_mark);
    if (this.pos case var from) {
      if (this.apply(this.r5) case var sequence?) {
        if (this.fs() case _?) {
          if (this.f14() case _?) {
            if (this.apply(this.rd) case var code?) {
              if (this.f14() case _?) {
                if (this.fr() case _?) {
                  if (this.pos case var to) {
                    if (this.buffer.substring(from, to) case var span) {
                      return InlineActionNode(
                        sequence,
                        code.trimRight(),
                        areIndicesProvided:
                            code.contains(_regexps.from) && code.contains(_regexps.to),
                        isSpanUsed: code.contains(_regexps.span),
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

    this._recover(_mark);
    if (this.pos case var from) {
      if (this.apply(this.r5) case var sequence?) {
        if (this.fu() case _?) {
          if (this.ft() case _?) {
            if (this.fs() case _?) {
              if (this.f14() case _?) {
                if (this.apply(this.rd) case var code?) {
                  if (this.f14() case _?) {
                    if (this.fr() case _?) {
                      if (this.pos case var to) {
                        if (this.buffer.substring(from, to) case var span) {
                          return ActionNode(
                            sequence,
                            code.trimRight(),
                            areIndicesProvided:
                                code.contains(_regexps.from) && code.contains(_regexps.to),
                            isSpanUsed: code.contains(_regexps.span),
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
    }

    this._recover(_mark);
    if (this.apply(this.r5) case var $?) {
      return $;
    }
  }

  /// `global::sequence`
  Node? r5() {
    if (this.apply(this.r6) case var _0?) {
      if ([_0] case (var body && var _l1)) {
        for (;;) {
          var _mark = this._mark();
          if (this.f14() case _?) {
            if (this.apply(this.r6) case var _0?) {
              _l1.add(_0);
              continue;
            }
          }
          this._recover(_mark);
          break;
        }
        if (this.f1c() case var chosen) {
          return body.length == 1 ? body.single : SequenceNode(body, chosenIndex: chosen);
        }
      }
    }
  }

  /// `global::dropped`
  Node? r6() {
    var _mark = this._mark();
    if (this.apply(this.r6) case var captured?) {
      if (this.f1d() case _?) {
        if (this.apply(this.r8) case var dropped?) {
          return SequenceNode([captured, dropped], chosenIndex: 0);
        }
      }
    }
    this._recover(_mark);
    if (this.apply(this.r8) case var dropped?) {
      if (this.f1e() case _?) {
        if (this.apply(this.r6) case var captured?) {
          return SequenceNode([dropped, captured], chosenIndex: 1);
        }
      }
    }
    this._recover(_mark);
    if (this.apply(this.r7) case var $?) {
      return $;
    }
  }

  /// `global::labeled`
  Node? r7() {
    var _mark = this._mark();
    if (this.f6() case var identifier?) {
      if (this.matchPattern(_string.$22) case _?) {
        if (this.f14() case _?) {
          if (this.apply(this.r8) case var special?) {
            return NamedNode(identifier, special);
          }
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$22) case _?) {
      if (this.f4() case var id?) {
        if (this.fx() case _?) {
          var name = id.split(ParserGenerator.separator).last;

          return NamedNode(name, OptionalNode(ReferenceNode(id)));
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$22) case _?) {
      if (this.f4() case var id?) {
        if (this.fy() case _?) {
          var name = id.split(ParserGenerator.separator).last;

          return NamedNode(name, StarNode(ReferenceNode(id)));
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$22) case _?) {
      if (this.f4() case var id?) {
        if (this.fz() case _?) {
          var name = id.split(ParserGenerator.separator).last;

          return NamedNode(name, PlusNode(ReferenceNode(id)));
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$22) case _?) {
      if (this.f4() case var id?) {
        var name = id.split(ParserGenerator.separator).last;

        return NamedNode(name, ReferenceNode(id));
      }
    }
    this._recover(_mark);
    if (this.apply(this.r8) case var $?) {
      return $;
    }
  }

  /// `global::special`
  Node? r8() {
    var _mark = this._mark();
    if (this.apply(this.rb) case var sep?) {
      if (this.fq() case _?) {
        if (this.apply(this.rb) case var expr?) {
          if (this.fz() case _?) {
            if (this.fx() case _?) {
              return PlusSeparatedNode(sep, expr, isTrailingAllowed: true);
            }
          }
        }
      }
    }
    this._recover(_mark);
    if (this.apply(this.rb) case var sep?) {
      if (this.fq() case _?) {
        if (this.apply(this.rb) case var expr?) {
          if (this.fy() case _?) {
            if (this.fx() case _?) {
              return StarSeparatedNode(sep, expr, isTrailingAllowed: true);
            }
          }
        }
      }
    }
    this._recover(_mark);
    if (this.apply(this.rb) case var sep?) {
      if (this.fq() case _?) {
        if (this.apply(this.rb) case var expr?) {
          if (this.fz() case _?) {
            return PlusSeparatedNode(sep, expr, isTrailingAllowed: false);
          }
        }
      }
    }
    this._recover(_mark);
    if (this.apply(this.rb) case var sep?) {
      if (this.fq() case _?) {
        if (this.apply(this.rb) case var expr?) {
          if (this.fy() case _?) {
            return StarSeparatedNode(sep, expr, isTrailingAllowed: false);
          }
        }
      }
    }
    this._recover(_mark);
    if (this.apply(this.r9) case var $?) {
      return $;
    }
  }

  /// `global::postfix`
  Node? r9() {
    var _mark = this._mark();
    if (this.apply(this.r9) case var $0?) {
      if (this.fx() case var $1?) {
        if ($0 case var $) {
          return OptionalNode($);
        }
      }
    }
    this._recover(_mark);
    if (this.apply(this.r9) case var $0?) {
      if (this.fy() case var $1?) {
        if ($0 case var $) {
          return StarNode($);
        }
      }
    }
    this._recover(_mark);
    if (this.apply(this.r9) case var $0?) {
      if (this.fz() case var $1?) {
        if ($0 case var $) {
          return PlusNode($);
        }
      }
    }
    this._recover(_mark);
    if (this.apply(this.ra) case var $?) {
      return $;
    }
  }

  /// `global::prefix`
  Node? ra() {
    var _mark = this._mark();
    if (this.f7() case var min?) {
      if (this.fq() case _?) {
        if (this.f7() case var max) {
          if (this.apply(this.rc) case var body?) {
            return CountedNode(min, max, body);
          }
        }
      }
    }
    this._recover(_mark);
    if (this.f7() case var number?) {
      if (this.apply(this.rc) case var body?) {
        return CountedNode(number, number, body);
      }
    }
    this._recover(_mark);
    if (this.f1f() case var $0?) {
      if (this.apply(this.ra) case var $1?) {
        if ($1 case var $) {
          return ExceptNode($);
        }
      }
    }
    this._recover(_mark);
    if (this.f1g() case var $0?) {
      if (this.apply(this.ra) case var $1?) {
        if ($1 case var $) {
          return AndPredicateNode($);
        }
      }
    }
    this._recover(_mark);
    if (this.f1h() case var $0?) {
      if (this.apply(this.ra) case var $1?) {
        if ($1 case var $) {
          return NotPredicateNode($);
        }
      }
    }
    this._recover(_mark);
    if (this.apply(this.rb) case var $?) {
      return $;
    }
  }

  /// `global::call`
  Node? rb() {
    var _mark = this._mark();
    if (this.pos case var from) {
      if (this.apply(this.rb) case var target?) {
        if (this.f13() case _?) {
          if (this.fb() case _?) {
            if (this.fu() case _?) {
              if (this.ft() case _?) {
                if (this.pos case var to) {
                  if (this.buffer.substring(from, to) case var span) {
                    return InlineActionNode(
                      target,
                      "span",
                      areIndicesProvided: true,
                      isSpanUsed: true,
                    );
                  }
                }
              }
            }
          }
        }
      }
    }

    this._recover(_mark);
    if (this.apply(this.rb) case var target?) {
      if (this.f13() case _?) {
        if (this.fa() case _?) {
          if (this.fu() case _?) {
            if (this.f7() case var min?) {
              if (this.f10() case _?) {
                if (this.f7() case var max?) {
                  if (this.ft() case _?) {
                    return CountedNode(min, max, target);
                  }
                }
              }
            }
          }
        }
      }
    }
    this._recover(_mark);
    if (this.apply(this.rb) case var target?) {
      if (this.f13() case _?) {
        if (this.fa() case _?) {
          if (this.fu() case _?) {
            if (this.f7() case var number?) {
              if (this.ft() case _?) {
                return CountedNode(number, number, target);
              }
            }
          }
        }
      }
    }
    this._recover(_mark);
    if (this.apply(this.rb) case var target?) {
      if (this.f13() case _?) {
        if (this.fa() case _?) {
          if (this.f14() case _?) {
            if (this.f7() case var number?) {
              if (this.f14() case _?) {
                return CountedNode(number, number, target);
              }
            }
          }
        }
      }
    }
    this._recover(_mark);
    if (this.apply(this.rb) case var sep?) {
      if (this.f13() case _?) {
        if (this.fc() case _?) {
          if (this.fu() case _?) {
            if (this.apply(this.r3) case var body?) {
              if (this.ft() case _?) {
                if (this.fz() case _?) {
                  if (this.fx() case _?) {
                    return PlusSeparatedNode(sep, body, isTrailingAllowed: true);
                  }
                }
              }
            }
          }
        }
      }
    }
    this._recover(_mark);
    if (this.apply(this.rb) case var sep?) {
      if (this.f13() case _?) {
        if (this.fc() case _?) {
          if (this.fu() case _?) {
            if (this.apply(this.r3) case var body?) {
              if (this.ft() case _?) {
                if (this.fy() case _?) {
                  if (this.fx() case _?) {
                    return StarSeparatedNode(sep, body, isTrailingAllowed: true);
                  }
                }
              }
            }
          }
        }
      }
    }
    this._recover(_mark);
    if (this.apply(this.rb) case var sep?) {
      if (this.f13() case _?) {
        if (this.fc() case _?) {
          if (this.fu() case _?) {
            if (this.apply(this.r3) case var body?) {
              if (this.ft() case _?) {
                if (this.fz() case _?) {
                  return PlusSeparatedNode(sep, body, isTrailingAllowed: false);
                }
              }
            }
          }
        }
      }
    }
    this._recover(_mark);
    if (this.apply(this.rb) case var sep?) {
      if (this.f13() case _?) {
        if (this.fc() case _?) {
          if (this.fu() case _?) {
            if (this.apply(this.r3) case var body?) {
              if (this.ft() case _?) {
                if (this.fy() case _?) {
                  return StarSeparatedNode(sep, body, isTrailingAllowed: false);
                }
              }
            }
          }
        }
      }
    }
    this._recover(_mark);
    if (this.apply(this.rb) case var sep?) {
      if (this.f13() case _?) {
        if (this.fc() case _?) {
          if (this.fu() case _?) {
            if (this.apply(this.r3) case var body?) {
              if (this.ft() case _?) {
                return PlusSeparatedNode(sep, body, isTrailingAllowed: false);
              }
            }
          }
        }
      }
    }
    this._recover(_mark);
    if (this.apply(this.rb) case var sep?) {
      if (this.f13() case _?) {
        if (this.fc() case _?) {
          if (this.f14() case _?) {
            if (this.apply(this.rc) case var body?) {
              if (this.f14() case _?) {
                return PlusSeparatedNode(sep, body, isTrailingAllowed: false);
              }
            }
          }
        }
      }
    }
    this._recover(_mark);
    if (this.apply(this.rc) case var $?) {
      return $;
    }
  }

  /// `global::atom`
  Node? rc() {
    var _mark = this._mark();
    if (this.fu() case _?) {
      if (this.f1i() case var $1?) {
        return $1;
      }
    }
    this._recover(_mark);
    if (this.f14() case _?) {
      if (this.matchPattern(_string.$59) case _?) {
        if (this.f14() case _?) {
          return const StartOfInputNode();
        }
      }
    }
    this._recover(_mark);
    if (this.f14() case _?) {
      if (this.matchPattern(_string.$30) case _?) {
        if (this.f14() case _?) {
          return const EndOfInputNode();
        }
      }
    }
    this._recover(_mark);
    if (this.f13() case var $?) {
      return const AnyCharacterNode();
    }
    this._recover(_mark);
    if (this.f14() case _?) {
      if (this.matchPattern(_string.$60) case _?) {
        if (this.f14() case _?) {
          return const EpsilonNode();
        }
      }
    }
    this._recover(_mark);
    if (this.fe() case var $?) {
      return const StringLiteralNode(r"\");
    }
    this._recover(_mark);
    if (this.ff() case var $?) {
      return SimpleRegExpEscapeNode.digit;
    }
    this._recover(_mark);
    if (this.fg() case var $?) {
      return SimpleRegExpEscapeNode.word;
    }
    this._recover(_mark);
    if (this.fh() case var $?) {
      return SimpleRegExpEscapeNode.whitespace;
    }
    this._recover(_mark);
    if (this.fi() case var $?) {
      return SimpleRegExpEscapeNode.notDigit;
    }
    this._recover(_mark);
    if (this.fj() case var $?) {
      return SimpleRegExpEscapeNode.notWord;
    }
    this._recover(_mark);
    if (this.fk() case var $?) {
      return SimpleRegExpEscapeNode.notWhitespace;
    }
    this._recover(_mark);
    if (this.fn() case var $?) {
      return SimpleRegExpEscapeNode.tab;
    }
    this._recover(_mark);
    if (this.fl() case var $?) {
      return SimpleRegExpEscapeNode.newline;
    }
    this._recover(_mark);
    if (this.fm() case var $?) {
      return SimpleRegExpEscapeNode.carriageReturn;
    }
    this._recover(_mark);
    if (this.fo() case var $?) {
      return SimpleRegExpEscapeNode.formFeed;
    }
    this._recover(_mark);
    if (this.fp() case var $?) {
      return SimpleRegExpEscapeNode.verticalTab;
    }
    this._recover(_mark);
    if (this.f14() case _?) {
      if (this.f1k() case var $1?) {
        if (this.f14() case _?) {
          return $1;
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$41) case var $0?) {
      if (this.f1m() case var $1?) {
        if (this.matchPattern(_string.$41) case var $2?) {
          if ($1 case var $) {
            return RegExpNode($);
          }
        }
      }
    }
    this._recover(_mark);
    if (this.f14() case var $0?) {
      if (this.f1v() case var $1?) {
        if (this.f14() case var $2?) {
          if ($1 case var $) {
            return StringLiteralNode($);
          }
        }
      }
    }
    this._recover(_mark);
    if (this.f3() case var $?) {
      return ReferenceNode($);
    }
  }

  /// `global::code::curly`
  String? rd() {
    var _mark = this._mark();
    if (this.matchPattern(_string.$46) case var $0?) {
      var _mark = this._mark();
      if (this.f1w() case var _0) {
        if ([if (_0 case var _0?) _0] case (var $1 && var _l1)) {
          if (_l1.isNotEmpty) {
            for (;;) {
              var _mark = this._mark();
              if (this.f1w() case var _0?) {
                _l1.add(_0);
                continue;
              }
              this._recover(_mark);
              break;
            }
          } else {
            this._recover(_mark);
          }
          if (this.matchPattern(_string.$46) case var $2?) {
            if ($1 case var $) {
              return $.join();
            }
          }
        }
      }
    }
    this._recover(_mark);
    if (this.f1x() case var _2) {
      if ([if (_2 case var _2?) _2] case (var code && var _l3)) {
        if (_l3.isNotEmpty) {
          for (;;) {
            var _mark = this._mark();
            if (this.f1x() case var _2?) {
              _l3.add(_2);
              continue;
            }
            this._recover(_mark);
            break;
          }
        } else {
          this._recover(_mark);
        }
        return code.join();
      }
    }
  }

  /// `global::code::nl`
  String? re() {
    var _mark = this._mark();
    if (this.matchPattern(_string.$46) case var $0?) {
      var _mark = this._mark();
      if (this.f1y() case var _0) {
        if ([if (_0 case var _0?) _0] case (var $1 && var _l1)) {
          if (_l1.isNotEmpty) {
            for (;;) {
              var _mark = this._mark();
              if (this.f1y() case var _0?) {
                _l1.add(_0);
                continue;
              }
              this._recover(_mark);
              break;
            }
          } else {
            this._recover(_mark);
          }
          if (this.matchPattern(_string.$46) case var $2?) {
            if ($1 case var $) {
              return $.join();
            }
          }
        }
      }
    }
    this._recover(_mark);
    if (this.f20() case var _2) {
      if ([if (_2 case var _2?) _2] case (var $ && var _l3)) {
        if (_l3.isNotEmpty) {
          for (;;) {
            var _mark = this._mark();
            if (this.f20() case var _2?) {
              _l3.add(_2);
              continue;
            }
            this._recover(_mark);
            break;
          }
        } else {
          this._recover(_mark);
        }
        return $.join();
      }
    }
  }

  /// `global::code::balanced`
  String rf() {
    var _mark = this._mark();
    if (this.f22() case var _0) {
      if ([if (_0 case var _0?) _0] case (var $ && var _l1)) {
        if (_l1.isNotEmpty) {
          for (;;) {
            var _mark = this._mark();
            if (this.f22() case var _0?) {
              _l1.add(_0);
              continue;
            }
            this._recover(_mark);
            break;
          }
        } else {
          this._recover(_mark);
        }
        return $.join();
      }
    }
  }

  /// `global::dart::literal::string`
  String? rg() {
    if (this.f23() case var _0?) {
      if ([_0] case (var $ && var _l1)) {
        for (;;) {
          var _mark = this._mark();
          if (this.f14() case _?) {
            if (this.f23() case var _0?) {
              _l1.add(_0);
              continue;
            }
          }
          this._recover(_mark);
          break;
        }
        return $.join(" ");
      }
    }
  }

  /// `global::dart::literal::identifier`
  String? rh() {
    if (this.pos case var from) {
      if (this.f6() case var $?) {
        if (this.pos case var to) {
          if (this.buffer.substring(from, to) case var span) {
            return span;
          }
        }
      }
    }
  }

  /// `global::dart::literal::string::balanced`
  String ri() {
    var _mark = this._mark();
    if (this.f24() case var _0) {
      if ([if (_0 case var _0?) _0] case (var $ && var _l1)) {
        if (_l1.isNotEmpty) {
          for (;;) {
            var _mark = this._mark();
            if (this.f24() case var _0?) {
              _l1.add(_0);
              continue;
            }
            this._recover(_mark);
            break;
          }
        } else {
          this._recover(_mark);
        }
        return $.join();
      }
    }
  }

  /// `global::dart::type::main`
  String? rj() {
    if (this.f14() case _?) {
      if (this.apply(this.rk) case var $1?) {
        if (this.f14() case _?) {
          return $1;
        }
      }
    }
  }

  /// `global::dart::type::type`
  String? rk() {
    var _mark = this._mark();
    if (this.apply(this.ro) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.apply(this.rl) case var $?) {
      return $;
    }
  }

  /// `global::dart::type::nullable`
  String? rl() {
    if (this.apply(this.rm) case var nonNullable?) {
      if (this.fx() case var $1) {
        return $1 == null ? "$nonNullable" : "$nonNullable?";
      }
    }
  }

  /// `global::dart::type::nonNullable`
  String? rm() {
    var _mark = this._mark();
    if (this.apply(this.rq) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.apply(this.rn) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.apply(this.rs) case var $?) {
      return $;
    }
  }

  /// `global::dart::type::record`
  String? rn() {
    var _mark = this._mark();
    if (this.fu() case _?) {
      if (this.apply(this.rv) case var positional?) {
        if (this.f10() case _?) {
          if (this.apply(this.ru) case var named?) {
            if (this.ft() case _?) {
              return "(" + positional + ", " + named + ")";
            }
          }
        }
      }
    }
    this._recover(_mark);
    if (this.fu() case _?) {
      if (this.apply(this.rv) case var positional?) {
        if (this.f10() case _) {
          if (this.ft() case _?) {
            return "(" + positional + ")";
          }
        }
      }
    }
    this._recover(_mark);
    if (this.fu() case _?) {
      if (this.apply(this.ru) case var named?) {
        if (this.ft() case _?) {
          return "(" + named + ")";
        }
      }
    }
    this._recover(_mark);
    if (this.fu() case _?) {
      if (this.ft() case _?) {
        return "()";
      }
    }
  }

  /// `global::dart::type::function::type`
  String? ro() {
    if (this.apply(this.rj) case var type?) {
      if (this.f14() case var $1?) {
        if (this.matchPattern(_string.$61) case var $2?) {
          if (this.f14() case var $3?) {
            if (this.apply(this.rp) case var fnParameters?) {
              if (this.fx() case var $5) {
                if ((type, $1, $2, $3, fnParameters, $5) case var $) {
                  return "$type Function$fnParameters${$5 ?? " "}";
                }
              }
            }
          }
        }
      }
    }
  }

  /// `global::dart::type::function::fnParameters`
  String? rp() {
    var _mark = this._mark();
    if (this.fu() case _?) {
      if (this.apply(this.rv) case var positional?) {
        if (this.f10() case _?) {
          if (this.apply(this.ru) case var named?) {
            if (this.ft() case _?) {
              return "($positional, $named)";
            }
          }
        }
      }
    }
    this._recover(_mark);
    if (this.fu() case _?) {
      if (this.apply(this.rv) case var positional?) {
        if (this.f10() case _?) {
          if (this.apply(this.rt) case var optional?) {
            if (this.ft() case _?) {
              return "($positional, $optional)";
            }
          }
        }
      }
    }
    this._recover(_mark);
    if (this.fu() case _?) {
      if (this.apply(this.rv) case var positional?) {
        if (this.f10() case _) {
          if (this.ft() case _?) {
            return "($positional)";
          }
        }
      }
    }
    this._recover(_mark);
    if (this.fu() case _?) {
      if (this.apply(this.ru) case var named?) {
        if (this.ft() case _?) {
          return "($named)";
        }
      }
    }
    this._recover(_mark);
    if (this.fu() case _?) {
      if (this.apply(this.rt) case var optional?) {
        if (this.ft() case _?) {
          return "($optional)";
        }
      }
    }
    this._recover(_mark);
    if (this.fu() case _?) {
      if (this.ft() case _?) {
        return "()";
      }
    }
  }

  /// `global::dart::type::generic`
  String? rq() {
    if (this.apply(this.rs) case var base?) {
      if (this.f25() case _?) {
        if (this.apply(this.rr) case var arguments?) {
          if (this.f26() case _?) {
            return "$base<$arguments>";
          }
        }
      }
    }
  }

  /// `global::dart::type::arguments`
  String? rr() {
    if (this.apply(this.rk) case var _0?) {
      if ([_0] case (var $ && var _l1)) {
        for (;;) {
          var _mark = this._mark();
          if (this.f10() case _?) {
            if (this.apply(this.rk) case var _0?) {
              _l1.add(_0);
              continue;
            }
          }
          this._recover(_mark);
          break;
        }
        return $.join(", ");
      }
    }
  }

  /// `global::dart::type::base`
  String? rs() {
    if (this.f6() case var _0?) {
      if ([_0] case (var $ && var _l1)) {
        for (;;) {
          var _mark = this._mark();
          if (this.f13() case _?) {
            if (this.f6() case var _0?) {
              _l1.add(_0);
              continue;
            }
          }
          this._recover(_mark);
          break;
        }
        return $.join(".");
      }
    }
  }

  /// `global::dart::type::parameters::optional`
  String? rt() {
    if (this.f27() case _?) {
      if (this.apply(this.rv) case var $1?) {
        if (this.f10() case _) {
          if (this.f28() case _?) {
            return "[" + $1 + "]";
          }
        }
      }
    }
  }

  /// `global::dart::type::parameters::named`
  String? ru() {
    if (this.fs() case _?) {
      if (this.apply(this.rw) case var $1?) {
        if (this.f10() case _) {
          if (this.fr() case _?) {
            return "{" + $1 + "}";
          }
        }
      }
    }
  }

  /// `global::dart::type::fields::positional`
  String? rv() {
    if (this.apply(this.rx) case var _0?) {
      if ([_0] case (var $ && var _l1)) {
        for (;;) {
          var _mark = this._mark();
          if (this.f10() case _?) {
            if (this.apply(this.rx) case var _0?) {
              _l1.add(_0);
              continue;
            }
          }
          this._recover(_mark);
          break;
        }
        return $.join(", ");
      }
    }
  }

  /// `global::dart::type::fields::named`
  String? rw() {
    if (this.apply(this.ry) case var _0?) {
      if ([_0] case (var $ && var _l1)) {
        for (;;) {
          var _mark = this._mark();
          if (this.f10() case _?) {
            if (this.apply(this.ry) case var _0?) {
              _l1.add(_0);
              continue;
            }
          }
          this._recover(_mark);
          break;
        }
        return $.join(", ");
      }
    }
  }

  /// `global::dart::type::field::positional`
  String? rx() {
    if (this.apply(this.rk) case var $0?) {
      if (this.f14() case var $1?) {
        if (this.f6() case var $2) {
          if (($0, $1, $2) case var $) {
            return "${$0} ${$2 ?? ""}".trimRight();
          }
        }
      }
    }
  }

  /// `global::dart::type::field::named`
  String? ry() {
    if (this.apply(this.rk) case var $0?) {
      if (this.f14() case var $1?) {
        if (this.f6() case var $2?) {
          if (($0, $1, $2) case var $) {
            return "${$0} ${$2}";
          }
        }
      }
    }
  }

  static final _regexp = (
    RegExp("[a-zA-Z_\$][a-zA-Z0-9_\$]*"),
    RegExp("\\d"),
    RegExp(
      "((\\s+)|(\\/{2}((?!((\\r?\\n)|(\$))).)*(?=(\\r?\\n)|(\$)))|((\\/\\*((?!\\*\\/).)*\\*\\/)))*",
    ),
    RegExp("\\n"),
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
    "choice!",
    "..",
    "}",
    "{",
    ")",
    "(",
    ";",
    "=",
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
    " ",
    "-",
    "[",
    "/",
    "r\"\"\"",
    "r'''",
    "r\"",
    "r'",
    "`",
    "<",
    ">",
    "::",
    "<-",
    "->",
    "d",
    "w",
    "s",
    "n",
    "t",
    "f",
    "v",
    "^",
    "ε",
    "Function",
  );
}
