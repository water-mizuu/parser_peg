// ignore_for_file: type=lint, body_might_complete_normally_nullable, unused_local_variable, inference_failure_on_function_return_type, unused_import, duplicate_ignore, unused_element, collection_methods_unrelated_type, unused_element, use_setters_to_change_properties

// imports
// ignore_for_file: collection_methods_unrelated_type, unused_element, use_setters_to_change_properties

import "dart:collection";
import "dart:math" as math;
// PREAMBLE
import "package:parser_peg/src/node.dart";
import "package:parser_peg/src/generator.dart";
import "package:parser_peg/src/statement.dart";

final _regexps = (
  from: RegExp(r"\bfrom\b"),
  to: RegExp(r"\bto\b"),
  span: RegExp(r"\bspan\b"),
);

class FlatNode extends InlineActionNode {
  const FlatNode(Node child): super(child, "span", areIndicesProvided: true, isSpanUsed: true);
}
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
final class GrammarParser extends _PegParser<ParserGenerator > {
  GrammarParser();

  @override
  get start => r0;


  /// `global::json::atom::number::digits`
  Object? f0() {
    if (this._mark() case var _mark) {
      if (this.f0() case var $0?) {
        if (this.f1() case var $1?) {
          return ($0, $1);
        }
      }
      this._recover(_mark);
      if (this.f1() case var $?) {
        return $;
      }
    }
  }

  /// `global::json::atom::number::digit`
  Object? f1() {
    if (this._mark() case var _mark) {
      if (this.matchPattern(_string.$1) case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.f2() case var $?) {
        return $;
      }
    }
  }

  /// `global::json::atom::number::onenine`
  Object? f2() {
    if (this._mark() case var _mark) {
      if (this.matchPattern(_string.$2) case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.matchPattern(_string.$3) case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.matchPattern(_string.$4) case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.matchPattern(_string.$5) case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.matchPattern(_string.$6) case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.matchPattern(_string.$7) case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.matchPattern(_string.$8) case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.matchPattern(_string.$9) case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.matchPattern(_string.$10) case var $?) {
        return $;
      }
    }
  }

  /// `global::literal::range::atom`
  String ? f3() {
    if (this._mark() case var _mark) {
      if (this.matchPattern(_string.$11) case _?) {
        if (this.pos < this.buffer.length) {
          if (this.buffer[this.pos++] case var $1) {
            return $1;
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
    }
  }

  /// `global::type`
  String ? f4() {
    if (this._mark() case var _mark) {
      if (this.apply(this.r11)! case _) {
        if (this.f50() case var $1?) {
          if (this.apply(this.r11)! case _) {
            return $1;
          }
        }
      }
      this._recover(_mark);
      if (this.apply(this.rj) case var $?) {
        return $;
      }
    }
  }

  /// `global::namespaceReference`
  String  f5() {
    if (this._mark() case var _mark) {
      if (this.f57() case var _0?) {
        if ([_0].nullable() case var _l1) {
          if (_l1 != null) {
            for (;;) {
              if (this._mark() case var _mark) {
                if (this.f57() case var _0?) {
                  _l1.add(_0);
                  continue;
                }
                this._recover(_mark);
                break;
              }
            }
            if (_l1.length < 1) {
              _l1 = null;
            }
          }
          if (_l1 case var $?) {
            return $.join(ParserGenerator.separator);
          }
        }
      }
      this._recover(_mark);
      if ('' case var $) {
        return $;
      }
    }
  }

  /// `global::name`
  String ? f6() {
    if (this._mark() case var _mark) {
      if (this.f5() case var $0) {
        if (this.f59() case var $1?) {
          return $0.isEmpty ? $1 : "${$0}::${$1}";
        }
      }
      this._recover(_mark);
      if (this.f7() case var $?) {
        return $;
      }
    }
  }

  /// `global::namespacedIdentifier`
  String ? f7() {
    if (this.f5() case var $0) {
      if (this.f9() case var $1?) {
        return $0.isEmpty ? $1 : "${$0}::${$1}";
      }
    }
  }

  /// `global::body`
  Node ? f8() {
    if (this.f10() case _?) {
      if (this.apply(this.r3) case (var $1 && var choice)?) {
        if (this.fz() case _?) {
          return $1;
        }
      }
    }
  }

  /// `global::identifier`
  String ? f9() {
    if (this.pos case var from) {
      if (this.matchRange(_range.$2) case _?) {
        if (this._mark() case var _mark) {
          if (this.matchRange(_range.$1) case var _0) {
            if ([if (_0 case var _0?) _0] case var _l1) {
              if (_l1.isNotEmpty) {
                for (;;) {
                  if (this._mark() case var _mark) {
                    if (this.matchRange(_range.$1) case var _0?) {
                      _l1.add(_0);
                      continue;
                    }
                    this._recover(_mark);
                    break;
                  }
                }
              } else {
                this._recover(_mark);
              }
              if (this.pos case var to) {
                if (this.buffer.substring(from, to) case var span) {
                  return span;
                }
              }
            }
          }
        }
      }
    }
  }

  /// `global::number`
  int ? fa() {
    if (this.matchPattern(_regexp.$1) case var _0?) {
      if ([_0] case (var $ && var _l1)) {
        for (;;) {
          if (this._mark() case var _mark) {
            if (this.matchPattern(_regexp.$1) case var _0?) {
              _l1.add(_0);
              continue;
            }
            this._recover(_mark);
            break;
          }
        }
        return int.parse($.join());
      }
    }
  }

  /// `global::kw::decorator`
  Tag ? fb() {
    if (this._mark() case var _mark) {
      if (this.apply(this.r11)! case _) {
        if (this.matchPattern(_string.$13) case _?) {
          if (this.apply(this.r11)! case _) {
            return Tag.rule;
          }
        }
      }
      this._recover(_mark);
      if (this.apply(this.r11)! case _) {
        if (this.matchPattern(_string.$14) case _?) {
          if (this.apply(this.r11)! case _) {
            return Tag.fragment;
          }
        }
      }
      this._recover(_mark);
      if (this.apply(this.r11)! case _) {
        if (this.matchPattern(_string.$15) case _?) {
          if (this.apply(this.r11)! case _) {
            return Tag.inline;
          }
        }
      }
    }
  }

  /// `global::mac::choice`
  String ? fc() {
    if (this.apply(this.r11)! case _) {
      if (this.matchPattern(_string.$16) case var $1?) {
        if (this.apply(this.r11)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::regexEscape::backslash`
  String ? fd() {
    if (this.apply(this.r11)! case _) {
      if (this.f5b() case var $1?) {
        return $1;
      }
    }
  }

  /// `global::regexEscape::digit`
  String ? fe() {
    if (this.apply(this.r11)! case _) {
      if (this.f5c() case var $1?) {
        if (this.apply(this.r11)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::regexEscape::word`
  String ? ff() {
    if (this.apply(this.r11)! case _) {
      if (this.f5d() case var $1?) {
        if (this.apply(this.r11)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::regexEscape::whitespace`
  String ? fg() {
    if (this.apply(this.r11)! case _) {
      if (this.f5e() case var $1?) {
        if (this.apply(this.r11)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::regexEscape::wordBoundary`
  String ? fh() {
    if (this.apply(this.r11)! case _) {
      if (this.f5f() case var $1?) {
        if (this.apply(this.r11)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::regexEscape::notDigit`
  String ? fi() {
    if (this.apply(this.r11)! case _) {
      if (this.f5g() case var $1?) {
        if (this.apply(this.r11)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::regexEscape::notWord`
  String ? fj() {
    if (this.apply(this.r11)! case _) {
      if (this.f5h() case var $1?) {
        if (this.apply(this.r11)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::regexEscape::notWhitespace`
  String ? fk() {
    if (this.apply(this.r11)! case _) {
      if (this.f5i() case var $1?) {
        if (this.apply(this.r11)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::regexEscape::newline`
  String ? fl() {
    if (this.apply(this.r11)! case _) {
      if (this.f5j() case var $1?) {
        if (this.apply(this.r11)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::regexEscape::carriageReturn`
  String ? fm() {
    if (this.apply(this.r11)! case _) {
      if (this.f5k() case var $1?) {
        if (this.apply(this.r11)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::regexEscape::tab`
  String ? fn() {
    if (this.apply(this.r11)! case _) {
      if (this.f5l() case var $1?) {
        if (this.apply(this.r11)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::regexEscape::formFeed`
  String ? fo() {
    if (this.apply(this.r11)! case _) {
      if (this.f5m() case var $1?) {
        if (this.apply(this.r11)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::regexEscape::verticalTab`
  String ? fp() {
    if (this.apply(this.r11)! case _) {
      if (this.f5n() case var $1?) {
        if (this.apply(this.r11)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::CHOICE_OP`
  String ? fq() {
    if (this.f15() case _?) {
      if (this.f5o() case _) {
        return "";
      }
    }
  }

  /// `global::..`
  String ? fr() {
    if (this.apply(this.r11)! case _) {
      if (this.matchPattern(_string.$17) case var $1?) {
        if (this.apply(this.r11)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::<~`
  String ? fs() {
    if (this.apply(this.r11)! case _) {
      if (this.matchPattern(_string.$18) case var $1?) {
        if (this.apply(this.r11)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::<`
  String ? ft() {
    if (this.apply(this.r11)! case _) {
      if (this.matchPattern(_string.$19) case var $1?) {
        if (this.apply(this.r11)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::>`
  String ? fu() {
    if (this.apply(this.r11)! case _) {
      if (this.matchPattern(_string.$20) case var $1?) {
        if (this.apply(this.r11)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::}`
  String ? fv() {
    if (this.apply(this.r11)! case _) {
      if (this.matchPattern(_string.$21) case var $1?) {
        if (this.apply(this.r11)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::{`
  String ? fw() {
    if (this.apply(this.r11)! case _) {
      if (this.matchPattern(_string.$22) case var $1?) {
        if (this.apply(this.r11)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::)`
  String ? fx() {
    if (this.apply(this.r11)! case _) {
      if (this.matchPattern(_string.$23) case var $1?) {
        if (this.apply(this.r11)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::(`
  String ? fy() {
    if (this.apply(this.r11)! case _) {
      if (this.matchPattern(_string.$24) case var $1?) {
        if (this.apply(this.r11)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::;`
  String ? fz() {
    if (this.apply(this.r11)! case _) {
      if (this.matchPattern(_string.$25) case var $1?) {
        if (this.apply(this.r11)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::=`
  String ? f10() {
    if (this.apply(this.r11)! case _) {
      if (this.matchPattern(_string.$26) case var $1?) {
        if (this.apply(this.r11)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::?`
  String ? f11() {
    if (this.apply(this.r11)! case _) {
      if (this.matchPattern(_string.$27) case var $1?) {
        if (this.apply(this.r11)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::*`
  String ? f12() {
    if (this.apply(this.r11)! case _) {
      if (this.matchPattern(_string.$28) case var $1?) {
        if (this.apply(this.r11)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::+`
  String ? f13() {
    if (this.apply(this.r11)! case _) {
      if (this.matchPattern(_string.$29) case var $1?) {
        if (this.apply(this.r11)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::,`
  String ? f14() {
    if (this.apply(this.r11)! case _) {
      if (this.matchPattern(_string.$30) case var $1?) {
        if (this.apply(this.r11)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::|`
  String ? f15() {
    if (this.apply(this.r11)! case _) {
      if (this.matchPattern(_string.$31) case var $1?) {
        if (this.apply(this.r11)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::.`
  String ? f16() {
    if (this.apply(this.r11)! case _) {
      if (this.matchPattern(_string.$32) case var $1?) {
        if (this.apply(this.r11)! case _) {
          return $1;
        }
      }
    }
  }

  /// `ROOT`
  ParserGenerator ? f17() {
    if (this.apply(this.r0) case var $?) {
      return $;
    }
  }

  /// `global::dart::literal::string::body`
  late final f18 = () {
    if (this._mark() case var _mark) {
      if (this.matchPattern(_string.$34) case var _2?) {
        if ([_2].nullable() case var _l3) {
          if (_l3 != null) {
            while (_l3.length < 1) {
              if (this._mark() case var _mark) {
                if (this.matchPattern(_string.$34) case var _2?) {
                  _l3.add(_2);
                  continue;
                }
                this._recover(_mark);
                break;
              }
            }
            if (_l3.length < 1) {
              _l3 = null;
            }
          }
          if (_l3 case var $0?) {
            if (this.matchPattern(_string.$33) case var $1?) {
              if (this._mark() case var _mark) {
                if (this.f5p() case var _0) {
                  if ([if (_0 case var _0?) _0] case (var $2 && var _l1)) {
                    if (_l1.isNotEmpty) {
                      for (;;) {
                        if (this._mark() case var _mark) {
                          if (this.f5p() case var _0?) {
                            _l1.add(_0);
                            continue;
                          }
                          this._recover(_mark);
                          break;
                        }
                      }
                    } else {
                      this._recover(_mark);
                    }
                    if (this.matchPattern(_string.$33) case var $3?) {
                      return ($0, $1, $2, $3);
                    }
                  }
                }
              }
            }
          }
        }
      }
      this._recover(_mark);
      if (this.matchPattern(_string.$34) case var _6?) {
        if ([_6].nullable() case var _l7) {
          if (_l7 != null) {
            while (_l7.length < 1) {
              if (this._mark() case var _mark) {
                if (this.matchPattern(_string.$34) case var _6?) {
                  _l7.add(_6);
                  continue;
                }
                this._recover(_mark);
                break;
              }
            }
            if (_l7.length < 1) {
              _l7 = null;
            }
          }
          if (_l7 case var $0?) {
            if (this.matchPattern(_string.$35) case var $1?) {
              if (this._mark() case var _mark) {
                if (this.f5q() case var _4) {
                  if ([if (_4 case var _4?) _4] case (var $2 && var _l5)) {
                    if (_l5.isNotEmpty) {
                      for (;;) {
                        if (this._mark() case var _mark) {
                          if (this.f5q() case var _4?) {
                            _l5.add(_4);
                            continue;
                          }
                          this._recover(_mark);
                          break;
                        }
                      }
                    } else {
                      this._recover(_mark);
                    }
                    if (this.matchPattern(_string.$35) case var $3?) {
                      return ($0, $1, $2, $3);
                    }
                  }
                }
              }
            }
          }
        }
      }
      this._recover(_mark);
      if (this.matchPattern(_string.$34) case var _10?) {
        if ([_10].nullable() case var _l11) {
          if (_l11 != null) {
            while (_l11.length < 1) {
              if (this._mark() case var _mark) {
                if (this.matchPattern(_string.$34) case var _10?) {
                  _l11.add(_10);
                  continue;
                }
                this._recover(_mark);
                break;
              }
            }
            if (_l11.length < 1) {
              _l11 = null;
            }
          }
          if (_l11 case var $0?) {
            if (this.matchPattern(_string.$36) case var $1?) {
              if (this._mark() case var _mark) {
                if (this.f5r() case var _8) {
                  if ([if (_8 case var _8?) _8] case (var $2 && var _l9)) {
                    if (_l9.isNotEmpty) {
                      for (;;) {
                        if (this._mark() case var _mark) {
                          if (this.f5r() case var _8?) {
                            _l9.add(_8);
                            continue;
                          }
                          this._recover(_mark);
                          break;
                        }
                      }
                    } else {
                      this._recover(_mark);
                    }
                    if (this.matchPattern(_string.$36) case var $3?) {
                      return ($0, $1, $2, $3);
                    }
                  }
                }
              }
            }
          }
        }
      }
      this._recover(_mark);
      if (this.matchPattern(_string.$34) case var _14?) {
        if ([_14].nullable() case var _l15) {
          if (_l15 != null) {
            while (_l15.length < 1) {
              if (this._mark() case var _mark) {
                if (this.matchPattern(_string.$34) case var _14?) {
                  _l15.add(_14);
                  continue;
                }
                this._recover(_mark);
                break;
              }
            }
            if (_l15.length < 1) {
              _l15 = null;
            }
          }
          if (_l15 case var $0?) {
            if (this.matchPattern(_string.$37) case var $1?) {
              if (this._mark() case var _mark) {
                if (this.f5s() case var _12) {
                  if ([if (_12 case var _12?) _12] case (var $2 && var _l13)) {
                    if (_l13.isNotEmpty) {
                      for (;;) {
                        if (this._mark() case var _mark) {
                          if (this.f5s() case var _12?) {
                            _l13.add(_12);
                            continue;
                          }
                          this._recover(_mark);
                          break;
                        }
                      }
                    } else {
                      this._recover(_mark);
                    }
                    if (this.matchPattern(_string.$37) case var $3?) {
                      return ($0, $1, $2, $3);
                    }
                  }
                }
              }
            }
          }
        }
      }
      this._recover(_mark);
      if (this.matchPattern(_string.$33) case var $0?) {
        if (this._mark() case var _mark) {
          if (this.f5x() case var _16) {
            if ([if (_16 case var _16?) _16] case (var $1 && var _l17)) {
              if (_l17.isNotEmpty) {
                for (;;) {
                  if (this._mark() case var _mark) {
                    if (this.f5x() case var _16?) {
                      _l17.add(_16);
                      continue;
                    }
                    this._recover(_mark);
                    break;
                  }
                }
              } else {
                this._recover(_mark);
              }
              if (this.matchPattern(_string.$33) case var $2?) {
                return ($0, $1, $2);
              }
            }
          }
        }
      }
      this._recover(_mark);
      if (this.matchPattern(_string.$35) case var $0?) {
        if (this._mark() case var _mark) {
          if (this.f62() case var _18) {
            if ([if (_18 case var _18?) _18] case (var $1 && var _l19)) {
              if (_l19.isNotEmpty) {
                for (;;) {
                  if (this._mark() case var _mark) {
                    if (this.f62() case var _18?) {
                      _l19.add(_18);
                      continue;
                    }
                    this._recover(_mark);
                    break;
                  }
                }
              } else {
                this._recover(_mark);
              }
              if (this.matchPattern(_string.$35) case var $2?) {
                return ($0, $1, $2);
              }
            }
          }
        }
      }
      this._recover(_mark);
      if (this.matchPattern(_string.$36) case var $0?) {
        if (this._mark() case var _mark) {
          if (this.f67() case var _20) {
            if ([if (_20 case var _20?) _20] case (var $1 && var _l21)) {
              if (_l21.isNotEmpty) {
                for (;;) {
                  if (this._mark() case var _mark) {
                    if (this.f67() case var _20?) {
                      _l21.add(_20);
                      continue;
                    }
                    this._recover(_mark);
                    break;
                  }
                }
              } else {
                this._recover(_mark);
              }
              if (this.matchPattern(_string.$36) case var $2?) {
                return ($0, $1, $2);
              }
            }
          }
        }
      }
      this._recover(_mark);
      if (this.matchPattern(_string.$37) case var $0?) {
        if (this._mark() case var _mark) {
          if (this.f6c() case var _22) {
            if ([if (_22 case var _22?) _22] case (var $1 && var _l23)) {
              if (_l23.isNotEmpty) {
                for (;;) {
                  if (this._mark() case var _mark) {
                    if (this.f6c() case var _22?) {
                      _l23.add(_22);
                      continue;
                    }
                    this._recover(_mark);
                    break;
                  }
                }
              } else {
                this._recover(_mark);
              }
              if (this.matchPattern(_string.$37) case var $2?) {
                return ($0, $1, $2);
              }
            }
          }
        }
      }
    }
  };

  /// `global::json::atom::number::number`
  Object? f19() {
    if (this.f1a() case var $0?) {
      if (this.f1b() case var $1) {
        if (this.f1c() case var $2) {
          return ($0, $1, $2);
        }
      }
    }
  }

  /// `global::json::atom::number::integer`
  Object? f1a() {
    if (this._mark() case var _mark) {
      if (this.f1() case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.f2() case var $0?) {
        if (this.f0() case var $1?) {
          return ($0, $1);
        }
      }
      this._recover(_mark);
      if (this.matchPattern(_string.$38) case var $0?) {
        if (this.f1() case var $1?) {
          return ($0, $1);
        }
      }
      this._recover(_mark);
      if (this.matchPattern(_string.$38) case var $0?) {
        if (this.f2() case var $1?) {
          if (this.f0() case var $2?) {
            return ($0, $1, $2);
          }
        }
      }
    }
  }

  /// `global::json::atom::number::fraction`
  Object f1b() {
    if (this._mark() case var _mark) {
      if (this.matchPattern(_string.$32) case var $0?) {
        if (this.f0() case var $1?) {
          return ($0, $1);
        }
      }
      this._recover(_mark);
      if ('' case var $) {
        return $;
      }
    }
  }

  /// `global::json::atom::number::exponent`
  Object f1c() {
    if (this._mark() case var _mark) {
      if (this.f6d() case var $0?) {
        if (this.f6e() case var $1) {
          if (this.f0() case var $2?) {
            return ($0, $1, $2);
          }
        }
      }
      this._recover(_mark);
      if ('' case var $) {
        return $;
      }
    }
  }

  /// `fragment0`
  late final f1d = () {
    if (this.apply(this.r1) case var $?) {
      return $;
    }
  };

  /// `fragment1`
  late final f1e = () {
    if (this.apply(this.r11)! case var $) {
      return $;
    }
  };

  /// `fragment2`
  late final f1f = () {
    if (this.fb() case var $?) {
      return $;
    }
  };

  /// `fragment3`
  late final f1g = () {
    if (this.f4() case var $?) {
      return $;
    }
  };

  /// `fragment4`
  late final f1h = () {
    if (this.fb() case var $?) {
      return $;
    }
  };

  /// `fragment5`
  late final f1i = () {
    if (this.fz() case var $?) {
      return $;
    }
  };

  /// `fragment6`
  late final f1j = () {
    if (this.fb() case var $?) {
      return $;
    }
  };

  /// `fragment7`
  late final f1k = () {
    if (this.f4() case var $?) {
      return $;
    }
  };

  /// `fragment8`
  late final f1l = () {
    if (this.fb() case var $?) {
      return $;
    }
  };

  /// `fragment9`
  late final f1m = () {
    if (this.fz() case var $?) {
      return $;
    }
  };

  /// `fragment10`
  late final f1n = () {
    if (this.fb() case var $?) {
      return $;
    }
  };

  /// `fragment11`
  late final f1o = () {
    if (this.f9() case var $?) {
      return $;
    }
  };

  /// `fragment12`
  late final f1p = () {
    if (this.fb() case var $?) {
      return $;
    }
  };

  /// `fragment13`
  late final f1q = () {
    if (this.f4() case var $?) {
      return $;
    }
  };

  /// `fragment14`
  late final f1r = () {
    if (this.fb() case var $?) {
      return $;
    }
  };

  /// `fragment15`
  late final f1s = () {
    if (this.fb() case var $?) {
      return $;
    }
  };

  /// `fragment16`
  late final f1t = () {
    if (this.fq() case var $?) {
      return $;
    }
  };

  /// `fragment17`
  late final f1u = () {
    if (this.apply(this.r11)! case _) {
      if (this.matchPattern(_string.$39) case var $1?) {
        if (this.apply(this.r11)! case _) {
          return $1;
        }
      }
    }
  };

  /// `fragment18`
  late final f1v = () {
    if (this.apply(this.r11)! case _) {
      if (this.matchPattern(_string.$40) case var $1?) {
        if (this.apply(this.r11)! case _) {
          return $1;
        }
      }
    }
  };

  /// `fragment19`
  late final f1w = () {
    if (this.f1v() case _?) {
      if (this.fa() case var $1?) {
        return $1;
      }
    }
  };

  /// `fragment20`
  late final f1x = () {
    if (this.apply(this.r11)! case _) {
      if (this.matchPattern(_string.$41) case var $1?) {
        if (this.apply(this.r11)! case _) {
          return $1;
        }
      }
    }
  };

  /// `fragment21`
  late final f1y = () {
    if (this.apply(this.r11)! case _) {
      if (this.matchPattern(_string.$42) case var $1?) {
        if (this.apply(this.r11)! case _) {
          return $1;
        }
      }
    }
  };

  /// `fragment22`
  late final f1z = () {
    if (this.apply(this.r11)! case _) {
      if (this.matchPattern(_string.$43) case var $1?) {
        if (this.apply(this.r11)! case _) {
          return $1;
        }
      }
    }
  };

  /// `fragment23`
  late final f20 = () {
    if (this.apply(this.r11)! case _) {
      if (this.matchPattern(_string.$44) case var $1?) {
        if (this.apply(this.r11)! case _) {
          return $1;
        }
      }
    }
  };

  /// `fragment24`
  late final f21 = () {
    if (this.apply(this.r3) case var $0?) {
      if (this.fx() case _?) {
        return $0;
      }
    }
  };

  /// `fragment25`
  late final f22 = () {
    if (this.matchPattern(_string.$45) case var $?) {
      return {(32, 32)};
    }
  };

  /// `fragment26`
  late final f23 = () {
    if (this.fe() case var $?) {
      return {(48, 57)};
    }
  };

  /// `fragment27`
  late final f24 = () {
    if (this._mark() case var _mark) {
      if (this.f22() case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.f23() case var $?) {
        return $;
      }
    }
  };

  /// `fragment28`
  late final f25 = () {
    if (this.ff() case var $?) {
      return {(64 + 1, 64 + 26), (96 + 1, 96 + 26)};
    }
  };

  /// `fragment29`
  late final f26 = () {
    if (this._mark() case var _mark) {
      if (this.f24() case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.f25() case var $?) {
        return $;
      }
    }
  };

  /// `fragment30`
  late final f27 = () {
    if (this.fg() case var $?) {
      return {(9, 13), (32, 32)};
    }
  };

  /// `fragment31`
  late final f28 = () {
    if (this._mark() case var _mark) {
      if (this.f26() case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.f27() case var $?) {
        return $;
      }
    }
  };

  /// `fragment32`
  late final f29 = () {
    if (this.fl() case var $?) {
      return {(10, 10)};
    }
  };

  /// `fragment33`
  late final f2a = () {
    if (this._mark() case var _mark) {
      if (this.f28() case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.f29() case var $?) {
        return $;
      }
    }
  };

  /// `fragment34`
  late final f2b = () {
    if (this.fm() case var $?) {
      return {(13, 13)};
    }
  };

  /// `fragment35`
  late final f2c = () {
    if (this._mark() case var _mark) {
      if (this.f2a() case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.f2b() case var $?) {
        return $;
      }
    }
  };

  /// `fragment36`
  late final f2d = () {
    if (this.fn() case var $?) {
      return {(9, 9)};
    }
  };

  /// `fragment37`
  late final f2e = () {
    if (this._mark() case var _mark) {
      if (this.f2c() case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.f2d() case var $?) {
        return $;
      }
    }
  };

  /// `fragment38`
  late final f2f = () {
    if (this.fd() case var $?) {
      return {(92, 92)};
    }
  };

  /// `fragment39`
  late final f2g = () {
    if (this._mark() case var _mark) {
      if (this.f2e() case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.f2f() case var $?) {
        return $;
      }
    }
  };

  /// `fragment40`
  late final f2h = () {
    if (this.f3() case var l?) {
      if (this.matchPattern(_string.$38) case _?) {
        if (this.f3() case var r?) {
          return {(l.codeUnitAt(0), r.codeUnitAt(0))};
        }
      }
    }
  };

  /// `fragment41`
  late final f2i = () {
    if (this._mark() case var _mark) {
      if (this.f2g() case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.f2h() case var $?) {
        return $;
      }
    }
  };

  /// `fragment42`
  late final f2j = () {
    if (this.f3() case var $?) {
      return {($.codeUnitAt(0), $.codeUnitAt(0))};
    }
  };

  /// `fragment43`
  late final f2k = () {
    if (this._mark() case var _mark) {
      if (this.f2i() case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.f2j() case var $?) {
        return $;
      }
    }
  };

  /// `fragment44`
  late final f2l = () {
    if (this.matchPattern(_string.$46) case _?) {
      if (this.f2k() case var _0?) {
        if ([_0] case (var elements && var _l1)) {
          for (;;) {
            if (this._mark() case var _mark) {
              if (this.apply(this.r11)! case _) {
                if (this.f2k() case var _0?) {
                  _l1.add(_0);
                  continue;
                }
              }
              this._recover(_mark);
              break;
            }
          }
          if (this.matchPattern(_string.$12) case _?) {
            return elements.expand((e) => e).toSet();
          }
        }
      }
    }
  };

  /// `fragment45`
  late final f2m = () {
    if (this.matchPattern(_string.$11) case _?) {
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $1) {
          if ($1 case var $) {
            return r"\" + $;
          }
        }
      }
    }
  };

  /// `fragment46`
  late final f2n = () {
    if (this._mark() case var _mark) {
      if (this.matchPattern(_string.$47) case null) {
        this._recover(_mark);
        if (this.pos < this.buffer.length) {
          if (this.buffer[this.pos++] case var $) {
            return $;
          }
        }
      }
    }
  };

  /// `fragment47`
  late final f2o = () {
    if (this._mark() case var _mark) {
      if (this.f2m() case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.f2n() case var $?) {
        return $;
      }
    }
  };

  /// `fragment48`
  late final f2p = () {
    if (this.f2o() case var _0?) {
      if ([_0] case (var $ && var _l1)) {
        for (;;) {
          if (this._mark() case var _mark) {
            if (this.f2o() case var _0?) {
              _l1.add(_0);
              continue;
            }
            this._recover(_mark);
            break;
          }
        }
        return $.join();
      }
    }
  };

  /// `fragment49`
  late final f2q = () {
    if (this._mark() case var _mark) {
      if (this.matchPattern(_string.$33) case null) {
        this._recover(_mark);
        if (this.pos < this.buffer.length) {
          if (this.buffer[this.pos++] case var $) {
            return $;
          }
        }
      }
    }
  };

  /// `fragment50`
  late final f2r = () {
    if (this.matchPattern(_string.$48) case _?) {
      if (this._mark() case var _mark) {
        if (this.f2q() case var _0) {
          if ([if (_0 case var _0?) _0] case (var $1 && var _l1)) {
            if (_l1.isNotEmpty) {
              for (;;) {
                if (this._mark() case var _mark) {
                  if (this.f2q() case var _0?) {
                    _l1.add(_0);
                    continue;
                  }
                  this._recover(_mark);
                  break;
                }
              }
            } else {
              this._recover(_mark);
            }
            if (this.matchPattern(_string.$33) case _?) {
              if ($1 case var $) {
                return $.join();
              }
            }
          }
        }
      }
    }
  };

  /// `fragment51`
  late final f2s = () {
    if (this._mark() case var _mark) {
      if (this.matchPattern(_string.$35) case null) {
        this._recover(_mark);
        if (this.pos < this.buffer.length) {
          if (this.buffer[this.pos++] case var $) {
            return $;
          }
        }
      }
    }
  };

  /// `fragment52`
  late final f2t = () {
    if (this.matchPattern(_string.$49) case _?) {
      if (this._mark() case var _mark) {
        if (this.f2s() case var _0) {
          if ([if (_0 case var _0?) _0] case (var $1 && var _l1)) {
            if (_l1.isNotEmpty) {
              for (;;) {
                if (this._mark() case var _mark) {
                  if (this.f2s() case var _0?) {
                    _l1.add(_0);
                    continue;
                  }
                  this._recover(_mark);
                  break;
                }
              }
            } else {
              this._recover(_mark);
            }
            if (this.matchPattern(_string.$35) case _?) {
              if ($1 case var $) {
                return $.join();
              }
            }
          }
        }
      }
    }
  };

  /// `fragment53`
  late final f2u = () {
    if (this._mark() case var _mark) {
      if (this.f2r() case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.f2t() case var $?) {
        return $;
      }
    }
  };

  /// `fragment54`
  late final f2v = () {
    if (this._mark() case var _mark) {
      if (this.matchPattern(_string.$36) case null) {
        this._recover(_mark);
        if (this.pos < this.buffer.length) {
          if (this.buffer[this.pos++] case var $) {
            return $;
          }
        }
      }
    }
  };

  /// `fragment55`
  late final f2w = () {
    if (this.matchPattern(_string.$50) case _?) {
      if (this._mark() case var _mark) {
        if (this.f2v() case var _0) {
          if ([if (_0 case var _0?) _0] case (var $1 && var _l1)) {
            if (_l1.isNotEmpty) {
              for (;;) {
                if (this._mark() case var _mark) {
                  if (this.f2v() case var _0?) {
                    _l1.add(_0);
                    continue;
                  }
                  this._recover(_mark);
                  break;
                }
              }
            } else {
              this._recover(_mark);
            }
            if (this.matchPattern(_string.$36) case _?) {
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
  late final f2x = () {
    if (this._mark() case var _mark) {
      if (this.f2u() case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.f2w() case var $?) {
        return $;
      }
    }
  };

  /// `fragment57`
  late final f2y = () {
    if (this._mark() case var _mark) {
      if (this.matchPattern(_string.$37) case null) {
        this._recover(_mark);
        if (this.pos < this.buffer.length) {
          if (this.buffer[this.pos++] case var $) {
            return $;
          }
        }
      }
    }
  };

  /// `fragment58`
  late final f2z = () {
    if (this.matchPattern(_string.$51) case _?) {
      if (this._mark() case var _mark) {
        if (this.f2y() case var _0) {
          if ([if (_0 case var _0?) _0] case (var $1 && var _l1)) {
            if (_l1.isNotEmpty) {
              for (;;) {
                if (this._mark() case var _mark) {
                  if (this.f2y() case var _0?) {
                    _l1.add(_0);
                    continue;
                  }
                  this._recover(_mark);
                  break;
                }
              }
            } else {
              this._recover(_mark);
            }
            if (this.matchPattern(_string.$37) case _?) {
              if ($1 case var $) {
                return $.join();
              }
            }
          }
        }
      }
    }
  };

  /// `fragment59`
  late final f30 = () {
    if (this._mark() case var _mark) {
      if (this.f2x() case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.f2z() case var $?) {
        return $;
      }
    }
  };

  /// `fragment60`
  late final f31 = () {
    if (this.matchPattern(_string.$11) case var $0?) {
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $1) {
          return ($0, $1);
        }
      }
    }
  };

  /// `fragment61`
  late final f32 = () {
    if (this._mark() case var _mark) {
      if (this.matchPattern(_string.$33) case null) {
        this._recover(_mark);
        if (this.pos < this.buffer.length) {
          if (this.buffer[this.pos++] case var $) {
            return $;
          }
        }
      }
    }
  };

  /// `fragment62`
  late final f33 = () {
    if (this._mark() case var _mark) {
      if (this.f31() case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.f32() case var $?) {
        return $;
      }
    }
  };

  /// `fragment63`
  late final f34 = () {
    if (this.matchPattern(_string.$33) case _?) {
      if (this._mark() case var _mark) {
        if (this.f33() case var _0) {
          if ([if (_0 case var _0?) _0] case (var $1 && var _l1)) {
            if (_l1.isNotEmpty) {
              for (;;) {
                if (this._mark() case var _mark) {
                  if (this.f33() case var _0?) {
                    _l1.add(_0);
                    continue;
                  }
                  this._recover(_mark);
                  break;
                }
              }
            } else {
              this._recover(_mark);
            }
            if (this.matchPattern(_string.$33) case _?) {
              if ($1 case var $) {
                return $.join();
              }
            }
          }
        }
      }
    }
  };

  /// `fragment64`
  late final f35 = () {
    if (this._mark() case var _mark) {
      if (this.f30() case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.f34() case var $?) {
        return $;
      }
    }
  };

  /// `fragment65`
  late final f36 = () {
    if (this.matchPattern(_string.$11) case var $0?) {
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $1) {
          return ($0, $1);
        }
      }
    }
  };

  /// `fragment66`
  late final f37 = () {
    if (this._mark() case var _mark) {
      if (this.matchPattern(_string.$35) case null) {
        this._recover(_mark);
        if (this.pos < this.buffer.length) {
          if (this.buffer[this.pos++] case var $) {
            return $;
          }
        }
      }
    }
  };

  /// `fragment67`
  late final f38 = () {
    if (this._mark() case var _mark) {
      if (this.f36() case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.f37() case var $?) {
        return $;
      }
    }
  };

  /// `fragment68`
  late final f39 = () {
    if (this.matchPattern(_string.$35) case _?) {
      if (this._mark() case var _mark) {
        if (this.f38() case var _0) {
          if ([if (_0 case var _0?) _0] case (var $1 && var _l1)) {
            if (_l1.isNotEmpty) {
              for (;;) {
                if (this._mark() case var _mark) {
                  if (this.f38() case var _0?) {
                    _l1.add(_0);
                    continue;
                  }
                  this._recover(_mark);
                  break;
                }
              }
            } else {
              this._recover(_mark);
            }
            if (this.matchPattern(_string.$35) case _?) {
              if ($1 case var $) {
                return $.join();
              }
            }
          }
        }
      }
    }
  };

  /// `fragment69`
  late final f3a = () {
    if (this._mark() case var _mark) {
      if (this.f35() case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.f39() case var $?) {
        return $;
      }
    }
  };

  /// `fragment70`
  late final f3b = () {
    if (this.matchPattern(_string.$11) case var $0?) {
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $1) {
          return ($0, $1);
        }
      }
    }
  };

  /// `fragment71`
  late final f3c = () {
    if (this._mark() case var _mark) {
      if (this.matchPattern(_string.$36) case null) {
        this._recover(_mark);
        if (this.pos < this.buffer.length) {
          if (this.buffer[this.pos++] case var $) {
            return $;
          }
        }
      }
    }
  };

  /// `fragment72`
  late final f3d = () {
    if (this._mark() case var _mark) {
      if (this.f3b() case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.f3c() case var $?) {
        return $;
      }
    }
  };

  /// `fragment73`
  late final f3e = () {
    if (this.matchPattern(_string.$36) case _?) {
      if (this._mark() case var _mark) {
        if (this.f3d() case var _0) {
          if ([if (_0 case var _0?) _0] case (var $1 && var _l1)) {
            if (_l1.isNotEmpty) {
              for (;;) {
                if (this._mark() case var _mark) {
                  if (this.f3d() case var _0?) {
                    _l1.add(_0);
                    continue;
                  }
                  this._recover(_mark);
                  break;
                }
              }
            } else {
              this._recover(_mark);
            }
            if (this.matchPattern(_string.$36) case _?) {
              if ($1 case var $) {
                return $.join();
              }
            }
          }
        }
      }
    }
  };

  /// `fragment74`
  late final f3f = () {
    if (this._mark() case var _mark) {
      if (this.f3a() case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.f3e() case var $?) {
        return $;
      }
    }
  };

  /// `fragment75`
  late final f3g = () {
    if (this.matchPattern(_string.$11) case var $0?) {
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $1) {
          return ($0, $1);
        }
      }
    }
  };

  /// `fragment76`
  late final f3h = () {
    if (this._mark() case var _mark) {
      if (this.matchPattern(_string.$37) case null) {
        this._recover(_mark);
        if (this.pos < this.buffer.length) {
          if (this.buffer[this.pos++] case var $) {
            return $;
          }
        }
      }
    }
  };

  /// `fragment77`
  late final f3i = () {
    if (this._mark() case var _mark) {
      if (this.f3g() case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.f3h() case var $?) {
        return $;
      }
    }
  };

  /// `fragment78`
  late final f3j = () {
    if (this.matchPattern(_string.$37) case _?) {
      if (this._mark() case var _mark) {
        if (this.f3i() case var _0) {
          if ([if (_0 case var _0?) _0] case (var $1 && var _l1)) {
            if (_l1.isNotEmpty) {
              for (;;) {
                if (this._mark() case var _mark) {
                  if (this.f3i() case var _0?) {
                    _l1.add(_0);
                    continue;
                  }
                  this._recover(_mark);
                  break;
                }
              }
            } else {
              this._recover(_mark);
            }
            if (this.matchPattern(_string.$37) case _?) {
              if ($1 case var $) {
                return $.join();
              }
            }
          }
        }
      }
    }
  };

  /// `fragment79`
  late final f3k = () {
    if (this._mark() case var _mark) {
      if (this.f3f() case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.f3j() case var $?) {
        return $;
      }
    }
  };

  /// `fragment80`
  late final f3l = () {
    if (this.matchPattern(_string.$22) case _?) {
      if (this.apply(this.re)! case var $1) {
        if (this.matchPattern(_string.$21) case _?) {
          if ($1 case var $) {
            return "{" + $ + "}";
          }
        }
      }
    }
  };

  /// `fragment81`
  late final f3m = () {
    if (this._mark() case var _mark) {
      if (this.apply(this.rf) case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.f3l() case var $?) {
        return $;
      }
    }
  };

  /// `fragment82`
  late final f3n = () {
    if (this.matchPattern(_string.$24) case _?) {
      if (this.apply(this.re)! case var $1) {
        if (this.matchPattern(_string.$23) case _?) {
          if ($1 case var $) {
            return "(" + $ + ")";
          }
        }
      }
    }
  };

  /// `fragment83`
  late final f3o = () {
    if (this._mark() case var _mark) {
      if (this.f3m() case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.f3n() case var $?) {
        return $;
      }
    }
  };

  /// `fragment84`
  late final f3p = () {
    if (this.matchPattern(_string.$46) case _?) {
      if (this.apply(this.re)! case var $1) {
        if (this.matchPattern(_string.$12) case _?) {
          if ($1 case var $) {
            return "[" + $ + "]";
          }
        }
      }
    }
  };

  /// `fragment85`
  late final f3q = () {
    if (this._mark() case var _mark) {
      if (this.f3o() case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.f3p() case var $?) {
        return $;
      }
    }
  };

  /// `fragment86`
  late final f3r = () {
    if (this._mark() case var _mark) {
      if (this.matchPattern(_string.$21) case null) {
        this._recover(_mark);
        if (this.pos < this.buffer.length) {
          if (this.buffer[this.pos++] case var $) {
            return $;
          }
        }
      }
    }
  };

  /// `fragment87`
  late final f3s = () {
    if (this._mark() case var _mark) {
      if (this.f3q() case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.f3r() case var $?) {
        return $;
      }
    }
  };

  /// `fragment88`
  late final f3t = () {
    if (this.matchPattern(_string.$22) case _?) {
      if (this.apply(this.re)! case var $1) {
        if (this.matchPattern(_string.$21) case _?) {
          if ($1 case var $) {
            return "{" + $ + "}";
          }
        }
      }
    }
  };

  /// `fragment89`
  late final f3u = () {
    if (this._mark() case var _mark) {
      if (this.apply(this.rf) case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.f3t() case var $?) {
        return $;
      }
    }
  };

  /// `fragment90`
  late final f3v = () {
    if (this.matchPattern(_string.$24) case _?) {
      if (this.apply(this.re)! case var $1) {
        if (this.matchPattern(_string.$23) case _?) {
          if ($1 case var $) {
            return "(" + $ + ")";
          }
        }
      }
    }
  };

  /// `fragment91`
  late final f3w = () {
    if (this._mark() case var _mark) {
      if (this.f3u() case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.f3v() case var $?) {
        return $;
      }
    }
  };

  /// `fragment92`
  late final f3x = () {
    if (this.matchPattern(_string.$46) case _?) {
      if (this.apply(this.re)! case var $1) {
        if (this.matchPattern(_string.$12) case _?) {
          if ($1 case var $) {
            return "[" + $ + "]";
          }
        }
      }
    }
  };

  /// `fragment93`
  late final f3y = () {
    if (this._mark() case var _mark) {
      if (this.f3w() case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.f3x() case var $?) {
        return $;
      }
    }
  };

  /// `fragment94`
  late final f3z = () {
    if (this._mark() case var _mark) {
      if (this.matchPattern(_regexp.$2) case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.matchPattern(_string.$25) case var $?) {
        return $;
      }
    }
  };

  /// `fragment95`
  late final f40 = () {
    if (this._mark() case var _mark) {
      if (this.f3z() case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.matchPattern(_string.$23) case var $?) {
        return $;
      }
    }
  };

  /// `fragment96`
  late final f41 = () {
    if (this._mark() case var _mark) {
      if (this.f40() case null) {
        this._recover(_mark);
        if (this.pos < this.buffer.length) {
          if (this.buffer[this.pos++] case var $) {
            return $;
          }
        }
      }
    }
  };

  /// `fragment97`
  late final f42 = () {
    if (this._mark() case var _mark) {
      if (this.f3y() case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.f41() case var $?) {
        return $;
      }
    }
  };

  /// `fragment98`
  late final f43 = () {
    if (this.matchPattern(_string.$22) case _?) {
      if (this.apply(this.re)! case var $1) {
        if (this.matchPattern(_string.$21) case _?) {
          if ($1 case var $) {
            return "{" + $ + "}";
          }
        }
      }
    }
  };

  /// `fragment99`
  late final f44 = () {
    if (this._mark() case var _mark) {
      if (this.apply(this.rf) case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.f43() case var $?) {
        return $;
      }
    }
  };

  /// `fragment100`
  late final f45 = () {
    if (this.matchPattern(_string.$24) case _?) {
      if (this.apply(this.re)! case var $1) {
        if (this.matchPattern(_string.$23) case _?) {
          if ($1 case var $) {
            return "(" + $ + ")";
          }
        }
      }
    }
  };

  /// `fragment101`
  late final f46 = () {
    if (this._mark() case var _mark) {
      if (this.f44() case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.f45() case var $?) {
        return $;
      }
    }
  };

  /// `fragment102`
  late final f47 = () {
    if (this.matchPattern(_string.$46) case _?) {
      if (this.apply(this.re)! case var $1) {
        if (this.matchPattern(_string.$12) case _?) {
          if ($1 case var $) {
            return "[" + $ + "]";
          }
        }
      }
    }
  };

  /// `fragment103`
  late final f48 = () {
    if (this._mark() case var _mark) {
      if (this.f46() case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.f47() case var $?) {
        return $;
      }
    }
  };

  /// `fragment104`
  late final f49 = () {
    if (this._mark() case var _mark) {
      if (this.matchPattern(_string.$21) case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.matchPattern(_string.$23) case var $?) {
        return $;
      }
    }
  };

  /// `fragment105`
  late final f4a = () {
    if (this._mark() case var _mark) {
      if (this.f49() case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.matchPattern(_string.$12) case var $?) {
        return $;
      }
    }
  };

  /// `fragment106`
  late final f4b = () {
    if (this._mark() case var _mark) {
      if (this.f4a() case null) {
        this._recover(_mark);
        if (this.pos < this.buffer.length) {
          if (this.buffer[this.pos++] case var $) {
            return $;
          }
        }
      }
    }
  };

  /// `fragment107`
  late final f4c = () {
    if (this._mark() case var _mark) {
      if (this.f48() case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.f4b() case var $?) {
        return $;
      }
    }
  };

  /// `fragment108`
  late final f4d = () {
    if (this.pos case var from) {
      if (this.f18() case var $?) {
        if (this.pos case var to) {
          if (this.buffer.substring(from, to) case var span) {
            return span;
          }
        }
      }
    }
  };

  /// `fragment109`
  late final f4e = () {
    if (this.apply(this.ri)! case var $0) {
      if (this.matchPattern(_string.$21) case _?) {
        return $0;
      }
    }
  };

  /// `fragment110`
  late final f4f = () {
    if (this.matchPattern(_string.$22) case _?) {
      if (this.f4e() case var $1?) {
        if ($1 case var $) {
          return "{" + $ + "}";
        }
      }
    }
  };

  /// `fragment111`
  late final f4g = () {
    if (this._mark() case var _mark) {
      if (this.apply(this.rf) case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.f4f() case var $?) {
        return $;
      }
    }
  };

  /// `fragment112`
  late final f4h = () {
    if (this._mark() case var _mark) {
      if (this.matchPattern(_string.$21) case null) {
        this._recover(_mark);
        if (this.pos < this.buffer.length) {
          if (this.buffer[this.pos++] case var $) {
            return $;
          }
        }
      }
    }
  };

  /// `fragment113`
  late final f4i = () {
    if (this._mark() case var _mark) {
      if (this.f4g() case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.f4h() case var $?) {
        return $;
      }
    }
  };

  /// `fragment114`
  late final f4j = () {
    if (this.f11() case var $?) {
      return $;
    }
  };

  /// `fragment115`
  late final f4k = () {
    if (this.f4() case var _0?) {
      if ([_0] case (var $ && var _l1)) {
        for (;;) {
          if (this._mark() case var _mark) {
            if (this.f14() case _?) {
              if (this.f4() case var _0?) {
                _l1.add(_0);
                continue;
              }
            }
            this._recover(_mark);
            break;
          }
        }
        return $.join(", ");
      }
    }
  };

  /// `fragment116`
  late final f4l = () {
    if (this.f14() case var $?) {
      return $;
    }
  };

  /// `fragment117`
  late final f4m = () {
    if (this.f14() case var $?) {
      return $;
    }
  };

  /// `fragment118`
  late final f4n = () {
    if (this.apply(this.r11)! case _) {
      if (this.matchPattern(_string.$46) case var $1?) {
        if (this.apply(this.r11)! case _) {
          return $1;
        }
      }
    }
  };

  /// `fragment119`
  late final f4o = () {
    if (this.f14() case var $?) {
      return $;
    }
  };

  /// `fragment120`
  late final f4p = () {
    if (this.apply(this.r11)! case _) {
      if (this.matchPattern(_string.$12) case var $1?) {
        if (this.apply(this.r11)! case _) {
          return $1;
        }
      }
    }
  };

  /// `fragment121`
  late final f4q = () {
    if (this.f14() case var $?) {
      return $;
    }
  };

  /// `fragment122`
  late final f4r = () {
    if (this.f9() case var $?) {
      return $;
    }
  };

  /// `fragment123`
  late final f4s = () {
    if (this._mark() case var _mark) {
      if (this.matchPattern(_string.$47) case var $0?) {
        this._recover(_mark);
        if (this.apply(this.r13) case var $1?) {
          return ($0, $1);
        }
      }
    }
  };

  /// `fragment124`
  late final f4t = () {
    if (this._mark() case var _mark) {
      if (this.apply(this.r12) case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.f4s() case var $?) {
        return $;
      }
    }
  };

  /// `fragment125`
  late final f4u = () {
    if (this._mark() case var _mark) {
      if (this.apply(this.r16) case null) {
        this._recover(_mark);
        if (this.pos < this.buffer.length) {
          if (this.buffer[this.pos++] case var $) {
            return $;
          }
        }
      }
    }
  };

  /// `fragment126`
  late final f4v = () {
    if (this._mark() case var _mark) {
      if (this.matchPattern(_string.$52) case null) {
        this._recover(_mark);
        if (this.pos < this.buffer.length) {
          if (this.buffer[this.pos++] case var $) {
            return $;
          }
        }
      }
    }
  };

  /// `fragment127`
  late final f4w = () {
    if (this.matchPattern(_regexp.$3) case var $?) {
      return $;
    }
  };

  /// `fragment128`
  late final f4x = () {
    if (this.matchPattern(_regexp.$3) case var $?) {
      return $;
    }
  };

  /// `fragment129`
  late final f4y = () {
    if (this._mark() case var _mark) {
      if (this.matchPattern(_string.$53) case null) {
        this._recover(_mark);
        if (this.pos < this.buffer.length) {
          if (this.buffer[this.pos++] case var $) {
            return $;
          }
        }
      }
    }
  };

  /// `fragment130`
  late final f4z = () {
    if (this.pos case var from) {
      if (this.f4y() case var _0) {
        if (this._mark() case var _mark) {
          var _l1 = [if (_0 case var _0?) _0];
          if (_l1.isNotEmpty) {
            for (;;) {
              if (this._mark() case var _mark) {
                if (this.f4y() case var _0?) {
                  _l1.add(_0);
                  continue;
                }
                this._recover(_mark);
                break;
              }
            }
          } else {
            this._recover(_mark);
          }
          if (_l1 case var $) {
            if (this.pos case var to) {
              if (this.buffer.substring(from, to) case var span) {
                return span;
              }
            }
          }
        }
      }
    }
  };

  /// `fragment131`
  late final f50 = () {
    if (this.matchPattern(_string.$53) case _?) {
      if (this.f4z() case var $1) {
        if (this.matchPattern(_string.$53) case _?) {
          return $1;
        }
      }
    }
  };

  /// `fragment132`
  late final f51 = () {
    if (this._mark() case var _mark) {
      if (this.matchPattern(_string.$17) case (var $0 && null)) {
        this._recover(_mark);
        if (this.matchPattern(_string.$32) case var $1?) {
          return ($0, $1);
        }
      }
    }
  };

  /// `fragment133`
  late final f52 = () {
    if (this._mark() case var _mark) {
      if (this.matchPattern(_string.$54) case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.f51() case var $?) {
        return $;
      }
    }
  };

  /// `fragment134`
  late final f53 = () {
    if (this.apply(this.r11)! case _) {
      if (this.matchPattern(_string.$55) case var $1?) {
        if (this.apply(this.r11)! case _) {
          return $1;
        }
      }
    }
  };

  /// `fragment135`
  late final f54 = () {
    if (this.apply(this.r11)! case _) {
      if (this.matchPattern(_string.$56) case var $1?) {
        if (this.apply(this.r11)! case _) {
          return $1;
        }
      }
    }
  };

  /// `fragment136`
  late final f55 = () {
    if (this.apply(this.r11)! case _) {
      if (this.matchPattern(_string.$57) case var $1?) {
        if (this.apply(this.r11)! case _) {
          return $1;
        }
      }
    }
  };

  /// `fragment137`
  late final f56 = () {
    if (this._mark() case var _mark) {
      if (this.f53() case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.f54() case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.f55() case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.fc() case var $?) {
        return $;
      }
    }
  };

  /// `fragment138`
  late final f57 = () {
    if (this.f9() case var $0?) {
      if (this.f52() case _?) {
        if (this._mark() case var _mark) {
          if (this.f56() case null) {
            this._recover(_mark);
            return $0;
          }
        }
      }
    }
  };

  /// `fragment139`
  late final f58 = () {
    if (this._mark() case var _mark) {
      if (this.matchPattern(_string.$53) case null) {
        this._recover(_mark);
        if (this.pos < this.buffer.length) {
          if (this.buffer[this.pos++] case var $) {
            return $;
          }
        }
      }
    }
  };

  /// `fragment140`
  late final f59 = () {
    if (this.matchPattern(_string.$53) case _?) {
      if (this._mark() case var _mark) {
        if (this.f58() case var _0) {
          if ([if (_0 case var _0?) _0] case (var $1 && var _l1)) {
            if (_l1.isNotEmpty) {
              for (;;) {
                if (this._mark() case var _mark) {
                  if (this.f58() case var _0?) {
                    _l1.add(_0);
                    continue;
                  }
                  this._recover(_mark);
                  break;
                }
              }
            } else {
              this._recover(_mark);
            }
            if (this.matchPattern(_string.$53) case _?) {
              if ($1 case var $) {
                return $.join();
              }
            }
          }
        }
      }
    }
  };

  /// `fragment141`
  late final f5a = () {
    if (this.pos case var from) {
      if (this.matchPattern(_string.$11) case _?) {
        if (this.matchPattern(_string.$11) case _?) {
          if (this.pos case var to) {
            if (this.buffer.substring(from, to) case var span) {
              return span;
            }
          }
        }
      }
    }
  };

  /// `fragment142`
  late final f5b = () {
    if (this.f5a() case var $0?) {
      if (this.apply(this.r11)! case _) {
        return $0;
      }
    }
  };

  /// `fragment143`
  late final f5c = () {
    if (this.pos case var from) {
      if (this.matchPattern(_string.$11) case _?) {
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

  /// `fragment144`
  late final f5d = () {
    if (this.pos case var from) {
      if (this.matchPattern(_string.$11) case _?) {
        if (this.matchPattern(_string.$59) case _?) {
          if (this.pos case var to) {
            if (this.buffer.substring(from, to) case var span) {
              return span;
            }
          }
        }
      }
    }
  };

  /// `fragment145`
  late final f5e = () {
    if (this.pos case var from) {
      if (this.matchPattern(_string.$11) case _?) {
        if (this.matchPattern(_string.$60) case _?) {
          if (this.pos case var to) {
            if (this.buffer.substring(from, to) case var span) {
              return span;
            }
          }
        }
      }
    }
  };

  /// `fragment146`
  late final f5f = () {
    if (this.pos case var from) {
      if (this.matchPattern(_string.$11) case _?) {
        if (this.matchPattern(_string.$61) case _?) {
          if (this.pos case var to) {
            if (this.buffer.substring(from, to) case var span) {
              return span;
            }
          }
        }
      }
    }
  };

  /// `fragment147`
  late final f5g = () {
    if (this.pos case var from) {
      if (this.matchPattern(_string.$11) case _?) {
        if (this.matchPattern(_string.$62) case _?) {
          if (this.pos case var to) {
            if (this.buffer.substring(from, to) case var span) {
              return span;
            }
          }
        }
      }
    }
  };

  /// `fragment148`
  late final f5h = () {
    if (this.pos case var from) {
      if (this.matchPattern(_string.$11) case _?) {
        if (this.matchPattern(_string.$63) case _?) {
          if (this.pos case var to) {
            if (this.buffer.substring(from, to) case var span) {
              return span;
            }
          }
        }
      }
    }
  };

  /// `fragment149`
  late final f5i = () {
    if (this.pos case var from) {
      if (this.matchPattern(_string.$11) case _?) {
        if (this.matchPattern(_string.$64) case _?) {
          if (this.pos case var to) {
            if (this.buffer.substring(from, to) case var span) {
              return span;
            }
          }
        }
      }
    }
  };

  /// `fragment150`
  late final f5j = () {
    if (this.pos case var from) {
      if (this.matchPattern(_string.$11) case _?) {
        if (this.matchPattern(_string.$65) case _?) {
          if (this.pos case var to) {
            if (this.buffer.substring(from, to) case var span) {
              return span;
            }
          }
        }
      }
    }
  };

  /// `fragment151`
  late final f5k = () {
    if (this.pos case var from) {
      if (this.matchPattern(_string.$11) case _?) {
        if (this.matchPattern(_string.$34) case _?) {
          if (this.pos case var to) {
            if (this.buffer.substring(from, to) case var span) {
              return span;
            }
          }
        }
      }
    }
  };

  /// `fragment152`
  late final f5l = () {
    if (this.pos case var from) {
      if (this.matchPattern(_string.$11) case _?) {
        if (this.matchPattern(_string.$66) case _?) {
          if (this.pos case var to) {
            if (this.buffer.substring(from, to) case var span) {
              return span;
            }
          }
        }
      }
    }
  };

  /// `fragment153`
  late final f5m = () {
    if (this.pos case var from) {
      if (this.matchPattern(_string.$11) case _?) {
        if (this.matchPattern(_string.$67) case _?) {
          if (this.pos case var to) {
            if (this.buffer.substring(from, to) case var span) {
              return span;
            }
          }
        }
      }
    }
  };

  /// `fragment154`
  late final f5n = () {
    if (this.pos case var from) {
      if (this.matchPattern(_string.$11) case _?) {
        if (this.matchPattern(_string.$68) case _?) {
          if (this.pos case var to) {
            if (this.buffer.substring(from, to) case var span) {
              return span;
            }
          }
        }
      }
    }
  };

  /// `fragment155`
  late final f5o = () {
    if (this.f15() case var $?) {
      return $;
    }
  };

  /// `fragment156`
  late final f5p = () {
    if (this._mark() case var _mark) {
      if (this.matchPattern(_string.$33) case null) {
        this._recover(_mark);
        if (this.pos < this.buffer.length) {
          if (this.buffer[this.pos++] case var $) {
            return $;
          }
        }
      }
    }
  };

  /// `fragment157`
  late final f5q = () {
    if (this._mark() case var _mark) {
      if (this.matchPattern(_string.$35) case null) {
        this._recover(_mark);
        if (this.pos < this.buffer.length) {
          if (this.buffer[this.pos++] case var $) {
            return $;
          }
        }
      }
    }
  };

  /// `fragment158`
  late final f5r = () {
    if (this._mark() case var _mark) {
      if (this.matchPattern(_string.$36) case null) {
        this._recover(_mark);
        if (this.pos < this.buffer.length) {
          if (this.buffer[this.pos++] case var $) {
            return $;
          }
        }
      }
    }
  };

  /// `fragment159`
  late final f5s = () {
    if (this._mark() case var _mark) {
      if (this.matchPattern(_string.$37) case null) {
        this._recover(_mark);
        if (this.pos < this.buffer.length) {
          if (this.buffer[this.pos++] case var $) {
            return $;
          }
        }
      }
    }
  };

  /// `fragment160`
  late final f5t = () {
    if (this.matchPattern(_string.$11) case _?) {
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $1) {
          return $1;
        }
      }
    }
  };

  /// `fragment161`
  late final f5u = () {
    if (this._mark() case var _mark) {
      if (this.matchPattern(_string.$69) case var $0?) {
        this._recover(_mark);
        if (this.apply(this.rh) case var $1?) {
          return ($0, $1);
        }
      }
    }
  };

  /// `fragment162`
  late final f5v = () {
    if (this._mark() case var _mark) {
      if (this.f5t() case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.f5u() case var $?) {
        return $;
      }
    }
  };

  /// `fragment163`
  late final f5w = () {
    if (this._mark() case var _mark) {
      if (this.matchPattern(_string.$33) case null) {
        this._recover(_mark);
        if (this.pos < this.buffer.length) {
          if (this.buffer[this.pos++] case var $) {
            return $;
          }
        }
      }
    }
  };

  /// `fragment164`
  late final f5x = () {
    if (this._mark() case var _mark) {
      if (this.f5v() case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.f5w() case var $?) {
        return $;
      }
    }
  };

  /// `fragment165`
  late final f5y = () {
    if (this.matchPattern(_string.$11) case _?) {
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $1) {
          return $1;
        }
      }
    }
  };

  /// `fragment166`
  late final f5z = () {
    if (this._mark() case var _mark) {
      if (this.matchPattern(_string.$69) case var $0?) {
        this._recover(_mark);
        if (this.apply(this.rh) case var $1?) {
          return ($0, $1);
        }
      }
    }
  };

  /// `fragment167`
  late final f60 = () {
    if (this._mark() case var _mark) {
      if (this.f5y() case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.f5z() case var $?) {
        return $;
      }
    }
  };

  /// `fragment168`
  late final f61 = () {
    if (this._mark() case var _mark) {
      if (this.matchPattern(_string.$35) case null) {
        this._recover(_mark);
        if (this.pos < this.buffer.length) {
          if (this.buffer[this.pos++] case var $) {
            return $;
          }
        }
      }
    }
  };

  /// `fragment169`
  late final f62 = () {
    if (this._mark() case var _mark) {
      if (this.f60() case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.f61() case var $?) {
        return $;
      }
    }
  };

  /// `fragment170`
  late final f63 = () {
    if (this.matchPattern(_string.$11) case _?) {
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $1) {
          return $1;
        }
      }
    }
  };

  /// `fragment171`
  late final f64 = () {
    if (this._mark() case var _mark) {
      if (this.matchPattern(_string.$69) case var $0?) {
        this._recover(_mark);
        if (this.apply(this.rh) case var $1?) {
          return ($0, $1);
        }
      }
    }
  };

  /// `fragment172`
  late final f65 = () {
    if (this._mark() case var _mark) {
      if (this.f63() case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.f64() case var $?) {
        return $;
      }
    }
  };

  /// `fragment173`
  late final f66 = () {
    if (this._mark() case var _mark) {
      if (this.matchPattern(_string.$36) case null) {
        this._recover(_mark);
        if (this.pos < this.buffer.length) {
          if (this.buffer[this.pos++] case var $) {
            return $;
          }
        }
      }
    }
  };

  /// `fragment174`
  late final f67 = () {
    if (this._mark() case var _mark) {
      if (this.f65() case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.f66() case var $?) {
        return $;
      }
    }
  };

  /// `fragment175`
  late final f68 = () {
    if (this.matchPattern(_string.$11) case _?) {
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $1) {
          return $1;
        }
      }
    }
  };

  /// `fragment176`
  late final f69 = () {
    if (this._mark() case var _mark) {
      if (this.matchPattern(_string.$69) case var $0?) {
        this._recover(_mark);
        if (this.apply(this.rh) case var $1?) {
          return ($0, $1);
        }
      }
    }
  };

  /// `fragment177`
  late final f6a = () {
    if (this._mark() case var _mark) {
      if (this.f68() case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.f69() case var $?) {
        return $;
      }
    }
  };

  /// `fragment178`
  late final f6b = () {
    if (this._mark() case var _mark) {
      if (this.matchPattern(_string.$37) case null) {
        this._recover(_mark);
        if (this.pos < this.buffer.length) {
          if (this.buffer[this.pos++] case var $) {
            return $;
          }
        }
      }
    }
  };

  /// `fragment179`
  late final f6c = () {
    if (this._mark() case var _mark) {
      if (this.f6a() case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.f6b() case var $?) {
        return $;
      }
    }
  };

  /// `fragment180`
  late final f6d = () {
    if (this._mark() case var _mark) {
      if (this.matchPattern(_string.$70) case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.matchPattern(_string.$71) case var $?) {
        return $;
      }
    }
  };

  /// `fragment181`
  late final f6e = () {
    if (this._mark() case var _mark) {
      if (this.matchPattern(_string.$29) case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.matchPattern(_string.$38) case var $?) {
        return $;
      }
      this._recover(_mark);
      if ('' case var $) {
        return $;
      }
    }
  };

  /// `global::document`
  ParserGenerator ? r0() {
    if (this.pos <= 0) {
      if (this.f1d() case var $1) {
        if (this.apply(this.r2) case var _0?) {
          if ([_0] case (var $2 && var _l1)) {
            for (;;) {
              if (this._mark() case var _mark) {
                if (this.apply(this.r11)! case _) {
                  if (this.apply(this.r2) case var _0?) {
                    _l1.add(_0);
                    continue;
                  }
                }
                this._recover(_mark);
                break;
              }
            }
            if (this.f1e() case _) {
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
  String ? r1() {
    if (this.fw() case _?) {
      if (this.apply(this.r11)! case _) {
        if (this.apply(this.rc)! case (var $2 && var code)) {
          if (this.apply(this.r11)! case _) {
            if (this.fv() case _?) {
              return $2;
            }
          }
        }
      }
    }
  }

  /// `global::statement`
  Statement ? r2() {
    if (this._mark() case var _mark) {
      if (this.f1f() case var outer_decorator) {
        if (this.f1g() case var type) {
          if (this.f9() case var name?) {
            if (this.f10() case _?) {
              if (this.fc() case _?) {
                if (this.f1h() case var inner_decorator) {
                  if (this.fw() case _?) {
                    if (this.apply(this.r2) case var _0?) {
                      if ([_0] case (var statements && var _l1)) {
                        for (;;) {
                          if (this._mark() case var _mark) {
                            if (this.apply(this.r11)! case _) {
                              if (this.apply(this.r2) case var _0?) {
                                _l1.add(_0);
                                continue;
                              }
                            }
                            this._recover(_mark);
                            break;
                          }
                        }
                        if (this.fv() case _?) {
                          if (this.f1i() case _) {
                            return HybridNamespaceStatement(
                                  type, name, statements,
                                  outerTag: outer_decorator, innerTag: inner_decorator
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
      if (this.f1j() case var outer_decorator) {
        if (this.f1k() case var type) {
          if (this.fy() case _?) {
            if (this.fx() case _?) {
              if (this.f10() case _?) {
                if (this.fc() case _?) {
                  if (this.f1l() case var inner_decorator) {
                    if (this.fw() case _?) {
                      if (this.apply(this.r2) case var _2?) {
                        if ([_2] case (var statements && var _l3)) {
                          for (;;) {
                            if (this._mark() case var _mark) {
                              if (this.apply(this.r11)! case _) {
                                if (this.apply(this.r2) case var _2?) {
                                  _l3.add(_2);
                                  continue;
                                }
                              }
                              this._recover(_mark);
                              break;
                            }
                          }
                          if (this.fv() case _?) {
                            if (this.f1m() case _) {
                              return HybridNamespaceStatement(
                                    type, null, statements,
                                    outerTag: outer_decorator, innerTag: inner_decorator
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
      if (this.f1n() case var decorator) {
        if (this.f1o() case var name) {
          if (this.fw() case _?) {
            if (this.apply(this.r2) case var _4?) {
              if ([_4] case (var statements && var _l5)) {
                for (;;) {
                  if (this._mark() case var _mark) {
                    if (this.apply(this.r11)! case _) {
                      if (this.apply(this.r2) case var _4?) {
                        _l5.add(_4);
                        continue;
                      }
                    }
                    this._recover(_mark);
                    break;
                  }
                }
                if (this.fv() case _?) {
                  return NamespaceStatement(name, statements, tag: decorator);
                }
              }
            }
          }
        }
      }
      this._recover(_mark);
      if (this.f1p() case var decorator) {
        if (this.f1q() case var type) {
          if (this.f6() case var _6?) {
            if ([_6] case (var names && var _l7)) {
              for (;;) {
                if (this._mark() case var _mark) {
                  if (this.f14() case _?) {
                    if (this.f6() case var _6?) {
                      _l7.add(_6);
                      continue;
                    }
                  }
                  this._recover(_mark);
                  break;
                }
              }
              if (this.fz() case _?) {
                return DeclarationTypeStatement(type, names, tag: decorator);
              }
            }
          }
        }
      }
      this._recover(_mark);
      if (this.f1r() case var decorator) {
        if (this.f4() case var type?) {
          if (this.f6() case var name?) {
            if (this.f8() case var body?) {
              return DeclarationStatement(type, name, body, tag: decorator);
            }
          }
        }
      }
      this._recover(_mark);
      if (this.f1s() case var decorator) {
        if (this.f6() case var name?) {
          if (this.f8() case var body?) {
            return DeclarationStatement(null, name, body, tag: decorator);
          }
        }
      }
    }
  }

  /// `global::choice`
  Node ? r3() {
    if (this._mark() case var _mark) {
      if (this.apply(this.r3) case var choice?) {
        if (this.fq() case _?) {
          if (this.apply(this.r4) case var acted?) {
            return ChoiceNode([choice, acted]);
          }
        }
      }
      this._recover(_mark);
      if (this.f1t() case _) {
        if (this.apply(this.r4) case var acted?) {
          return acted;
        }
      }
    }
  }

  /// `global::acted`
  Node ? r4() {
    if (this._mark() case var _mark) {
      if (this.pos case var from) {
        if (this.apply(this.r5) case var sequence?) {
          if (this.f1u() case _?) {
            if (this.apply(this.r11)! case _) {
              if (this.apply(this.rd)! case var code) {
                if (this.apply(this.r11)! case _) {
                  if (this.pos case var to) {
                    if (this.buffer.substring(from, to) case var span) {
                      return InlineActionNode(
                              sequence,
                              code.trimRight(),
                              areIndicesProvided: code.contains(_regexps.from) && code.contains(_regexps.to),
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
          if (this.fw() case _?) {
            if (this.apply(this.r11)! case _) {
              if (this.apply(this.rc)! case var code) {
                if (this.apply(this.r11)! case _) {
                  if (this.fv() case _?) {
                    if (this.pos case var to) {
                      if (this.buffer.substring(from, to) case var span) {
                        return InlineActionNode(
                                sequence,
                                code.trimRight(),
                                areIndicesProvided: code.contains(_regexps.from) && code.contains(_regexps.to),
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
          if (this.fy() case _?) {
            if (this.fx() case _?) {
              if (this.fw() case _?) {
                if (this.apply(this.r11)! case _) {
                  if (this.apply(this.rc)! case var code) {
                    if (this.apply(this.r11)! case _) {
                      if (this.fv() case _?) {
                        if (this.pos case var to) {
                          if (this.buffer.substring(from, to) case var span) {
                            return ActionNode(
                                    sequence,
                                    code.trimRight(),
                                    areIndicesProvided: code.contains(_regexps.from) && code.contains(_regexps.to),
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
  }

  /// `global::sequence`
  Node ? r5() {
    if (this.apply(this.r6) case var _0?) {
      if ([_0] case (var body && var _l1)) {
        for (;;) {
          if (this._mark() case var _mark) {
            if (this.apply(this.r11)! case _) {
              if (this.apply(this.r6) case var _0?) {
                _l1.add(_0);
                continue;
              }
            }
            this._recover(_mark);
            break;
          }
        }
        if (this.f1w() case var chosen) {
          return body.length == 1 ? body.single : SequenceNode(body, chosenIndex: chosen);
        }
      }
    }
  }

  /// `global::dropped`
  Node ? r6() {
    if (this._mark() case var _mark) {
      if (this.apply(this.r6) case var captured?) {
        if (this.fs() case _?) {
          if (this.apply(this.r8) case var dropped?) {
            return SequenceNode([captured, dropped], chosenIndex: 0);
          }
        }
      }
      this._recover(_mark);
      if (this.apply(this.r8) case var dropped?) {
        if (this.f1x() case _?) {
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
  }

  /// `global::labeled`
  Node ? r7() {
    if (this._mark() case var _mark) {
      if (this.f9() case var identifier?) {
        if (this.matchPattern(_string.$72) case _?) {
          if (this.apply(this.r11)! case _) {
            if (this.apply(this.r8) case var special?) {
              return NamedNode(identifier, special);
            }
          }
        }
      }
      this._recover(_mark);
      if (this.matchPattern(_string.$72) case _?) {
        if (this.f7() case var id?) {
          if (this.f11() case _?) {
            var name = id.split(ParserGenerator.separator).last;

                  return NamedNode(name, OptionalNode(ReferenceNode(id)));
          }
        }
      }
      this._recover(_mark);
      if (this.matchPattern(_string.$72) case _?) {
        if (this.f7() case var id?) {
          if (this.f12() case _?) {
            var name = id.split(ParserGenerator.separator).last;

                  return NamedNode(name, StarNode(ReferenceNode(id)));
          }
        }
      }
      this._recover(_mark);
      if (this.matchPattern(_string.$72) case _?) {
        if (this.f7() case var id?) {
          if (this.f13() case _?) {
            var name = id.split(ParserGenerator.separator).last;

                  return NamedNode(name, PlusNode(ReferenceNode(id)));
          }
        }
      }
      this._recover(_mark);
      if (this.matchPattern(_string.$72) case _?) {
        if (this.f7() case var id?) {
          var name = id.split(ParserGenerator.separator).last;

                return NamedNode(name, ReferenceNode(id));
        }
      }
      this._recover(_mark);
      if (this.apply(this.r8) case var $?) {
        return $;
      }
    }
  }

  /// `global::special`
  Node ? r8() {
    if (this._mark() case var _mark) {
      if (this.apply(this.rb) case var sep?) {
        if (this.fr() case _?) {
          if (this.apply(this.rb) case var expr?) {
            if (this.f13() case _?) {
              if (this.f11() case _?) {
                return PlusSeparatedNode(sep, expr, isTrailingAllowed: true);
              }
            }
          }
        }
      }
      this._recover(_mark);
      if (this.apply(this.rb) case var sep?) {
        if (this.fr() case _?) {
          if (this.apply(this.rb) case var expr?) {
            if (this.f12() case _?) {
              if (this.f11() case _?) {
                return StarSeparatedNode(sep, expr, isTrailingAllowed: true);
              }
            }
          }
        }
      }
      this._recover(_mark);
      if (this.apply(this.rb) case var sep?) {
        if (this.fr() case _?) {
          if (this.apply(this.rb) case var expr?) {
            if (this.f13() case _?) {
              return PlusSeparatedNode(sep, expr, isTrailingAllowed: false);
            }
          }
        }
      }
      this._recover(_mark);
      if (this.apply(this.rb) case var sep?) {
        if (this.fr() case _?) {
          if (this.apply(this.rb) case var expr?) {
            if (this.f12() case _?) {
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
  }

  /// `global::postfix`
  Node ? r9() {
    if (this._mark() case var _mark) {
      if (this.apply(this.r9) case var $0?) {
        if (this.f11() case _?) {
          if ($0 case var $) {
            return OptionalNode($);
          }
        }
      }
      this._recover(_mark);
      if (this.apply(this.r9) case var $0?) {
        if (this.f12() case _?) {
          if ($0 case var $) {
            return StarNode($);
          }
        }
      }
      this._recover(_mark);
      if (this.apply(this.r9) case var $0?) {
        if (this.f13() case _?) {
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
  }

  /// `global::prefix`
  Node ? ra() {
    if (this._mark() case var _mark) {
      if (this.fa() case var min?) {
        if (this.fr() case _?) {
          if (this.fa() case var max?) {
            if (this.apply(this.rb) case var body?) {
              return CountedNode(min, max, body);
            }
          }
        }
      }
      this._recover(_mark);
      if (this.fa() case var min?) {
        if (this.fr() case _?) {
          if (this.apply(this.rb) case var body?) {
            return CountedNode(min, null, body);
          }
        }
      }
      this._recover(_mark);
      if (this.fa() case var number?) {
        if (this.apply(this.rb) case var body?) {
          return CountedNode(number, number, body);
        }
      }
      this._recover(_mark);
      if (this.f1y() case _?) {
        if (this.apply(this.ra) case var $1?) {
          if ($1 case var $) {
            return ExceptNode($);
          }
        }
      }
      this._recover(_mark);
      if (this.f1z() case _?) {
        if (this.apply(this.ra) case var $1?) {
          if ($1 case var $) {
            return AndPredicateNode($);
          }
        }
      }
      this._recover(_mark);
      if (this.f20() case _?) {
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
  }

  /// `global::atom`
  Node ? rb() {
    if (this._mark() case var _mark) {
      if (this.fy() case _?) {
        if (this.f21() case var $1?) {
          return $1;
        }
      }
      this._recover(_mark);
      if (this.fs() case null) {
        this._recover(_mark);
        if (this.ft() case _?) {
          if (this.apply(this.r3) case var choice?) {
            if (this.fu() case _?) {
              return FlatNode(choice);
            }
          }
        }
      }

      this._recover(_mark);
      if (this.apply(this.r11)! case _) {
        if (this.matchPattern(_string.$73) case var $1?) {
          if (this.apply(this.r11)! case _) {
            return const StartOfInputNode();
          }
        }
      }
      this._recover(_mark);
      if (this.apply(this.r11)! case _) {
        if (this.matchPattern(_string.$69) case var $1?) {
          if (this.apply(this.r11)! case _) {
            return const EndOfInputNode();
          }
        }
      }
      this._recover(_mark);
      if (this.f16() case var $?) {
        return const AnyCharacterNode();
      }
      this._recover(_mark);
      if (this.apply(this.r11)! case _) {
        if (this.matchPattern(_string.$74) case var $1?) {
          if (this.apply(this.r11)! case _) {
            return const EpsilonNode();
          }
        }
      }
      this._recover(_mark);
      if (this.fd() case var $?) {
        return const StringLiteralNode(r"\");
      }
      this._recover(_mark);
      if (this.fe() case var $?) {
        return SimpleRegExpEscapeNode.digit;
      }
      this._recover(_mark);
      if (this.ff() case var $?) {
        return SimpleRegExpEscapeNode.word;
      }
      this._recover(_mark);
      if (this.fg() case var $?) {
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
      if (this.fh() case var $?) {
        return SimpleRegExpEscapeNode.wordBoundary;
      }
      this._recover(_mark);
      if (this.apply(this.r11)! case _) {
        if (this.f2l() case var $1?) {
          if (this.apply(this.r11)! case _) {
            if ($1 case var $) {
              return RangeNode($);
            }
          }
        }
      }
      this._recover(_mark);
      if (this.matchPattern(_string.$47) case _?) {
        if (this.f2p() case var $1?) {
          if (this.matchPattern(_string.$47) case _?) {
            if ($1 case var $) {
              return RegExpNode($);
            }
          }
        }
      }
      this._recover(_mark);
      if (this.apply(this.r11)! case _) {
        if (this.f3k() case var $1?) {
          if (this.apply(this.r11)! case _) {
            if ($1 case var $) {
              return StringLiteralNode($);
            }
          }
        }
      }
      this._recover(_mark);
      if (this.f6() case var $?) {
        return ReferenceNode($);
      }
    }
  }

  /// `global::code::curly`
  String  rc() {
    if (this._mark() case var _mark) {
      if (this.f3s() case var _0) {
        if ([if (_0 case var _0?) _0] case (var $ && var _l1)) {
          if (_l1.isNotEmpty) {
            for (;;) {
              if (this._mark() case var _mark) {
                if (this.f3s() case var _0?) {
                  _l1.add(_0);
                  continue;
                }
                this._recover(_mark);
                break;
              }
            }
          } else {
            this._recover(_mark);
          }
          return $.join();
        }
      }
    }
  }

  /// `global::code::nl`
  String  rd() {
    if (this._mark() case var _mark) {
      if (this.f42() case var _0) {
        if ([if (_0 case var _0?) _0] case (var $ && var _l1)) {
          if (_l1.isNotEmpty) {
            for (;;) {
              if (this._mark() case var _mark) {
                if (this.f42() case var _0?) {
                  _l1.add(_0);
                  continue;
                }
                this._recover(_mark);
                break;
              }
            }
          } else {
            this._recover(_mark);
          }
          return $.join();
        }
      }
    }
  }

  /// `global::code::balanced`
  String  re() {
    if (this._mark() case var _mark) {
      if (this.f4c() case var _0) {
        if ([if (_0 case var _0?) _0] case (var $ && var _l1)) {
          if (_l1.isNotEmpty) {
            for (;;) {
              if (this._mark() case var _mark) {
                if (this.f4c() case var _0?) {
                  _l1.add(_0);
                  continue;
                }
                this._recover(_mark);
                break;
              }
            }
          } else {
            this._recover(_mark);
          }
          return $.join();
        }
      }
    }
  }

  /// `global::dart::literal::string`
  String ? rf() {
    if (this.f4d() case var _0?) {
      if ([_0] case (var $ && var _l1)) {
        for (;;) {
          if (this._mark() case var _mark) {
            if (this.apply(this.r11)! case _) {
              if (this.f4d() case var _0?) {
                _l1.add(_0);
                continue;
              }
            }
            this._recover(_mark);
            break;
          }
        }
        return $.join(" ");
      }
    }
  }

  /// `global::dart::literal::identifier`
  String ? rg() {
    if (this.f9() case var $?) {
      return $;
    }
  }

  /// `global::dart::literal::string::interpolation`
  late final rh = () {
    if (this._mark() case var _mark) {
      if (this.matchPattern(_string.$69) case var $0?) {
        if (this.matchPattern(_string.$22) case var $1?) {
          if (this.apply(this.ri)! case var $2) {
            if (this.matchPattern(_string.$21) case var $3?) {
              return ($0, $1, $2, $3);
            }
          }
        }
      }
      this._recover(_mark);
      if (this.matchPattern(_string.$69) case var $0?) {
        if (this.apply(this.rg) case var $1?) {
          return ($0, $1);
        }
      }
    }
  };

  /// `global::dart::literal::string::balanced`
  String  ri() {
    if (this._mark() case var _mark) {
      if (this.f4i() case var _0) {
        if ([if (_0 case var _0?) _0] case (var $ && var _l1)) {
          if (_l1.isNotEmpty) {
            for (;;) {
              if (this._mark() case var _mark) {
                if (this.f4i() case var _0?) {
                  _l1.add(_0);
                  continue;
                }
                this._recover(_mark);
                break;
              }
            }
          } else {
            this._recover(_mark);
          }
          return $.join();
        }
      }
    }
  }

  /// `global::dart::type::main`
  String ? rj() {
    if (this.apply(this.r11)! case _) {
      if (this.apply(this.rk) case var $1?) {
        if (this.apply(this.r11)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::dart::type::nullable`
  String ? rk() {
    if (this.apply(this.rl) case var nonNullable?) {
      if (this.f4j() case var $1) {
        return "$nonNullable${$1 ?? " "}";
      }
    }
  }

  /// `global::dart::type::nonNullable`
  String ? rl() {
    if (this._mark() case var _mark) {
      if (this.apply(this.rm) case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.apply(this.rn) case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.apply(this.ro) case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.apply(this.rt) case var $?) {
        return $;
      }
    }
  }

  /// `global::dart::type::nonNullable::function`
  String ? rm() {
    if (this.apply(this.rk) case (var nullable && var $0)?) {
      if (this.apply(this.r11)! case _) {
        if (this.matchPattern(_string.$75) case _?) {
          if (this.apply(this.r11)! case _) {
            if (this.apply(this.ru) case (var fnParameters && var $4)?) {
              return "${$0} Function${$4}";
            }
          }
        }
      }
    }
  }

  /// `global::dart::type::nonNullable::generic`
  String ? rn() {
    if (this.apply(this.rt) case var base?) {
      if (this.ft() case _?) {
        if (this.f4k() case var args?) {
          if (this.fu() case _?) {
            return "$base<$args>";
          }
        }
      }
    }
  }

  /// `global::dart::type::nonNullable::record`
  String ? ro() {
    if (this._mark() case var _mark) {
      if (this.apply(this.rp) case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.apply(this.rq) case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.apply(this.rr) case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.apply(this.rs) case var $?) {
        return $;
      }
    }
  }

  /// `global::dart::type::nonNullable::record::all`
  String ? rp() {
    if (this.fy() case _?) {
      if (this.apply(this.rx) case var positional?) {
        if (this.f14() case _?) {
          if (this.apply(this.rw) case var named?) {
            if (this.fx() case _?) {
              return "(" + positional + ", " + named + ")";
            }
          }
        }
      }
    }
  }

  /// `global::dart::type::nonNullable::record::onlyPositional`
  String ? rq() {
    if (this.fy() case _?) {
      if (this.apply(this.rx) case var positional?) {
        if (this.f4l() case _) {
          if (this.fx() case _?) {
            return "(" + positional + ")";
          }
        }
      }
    }
  }

  /// `global::dart::type::nonNullable::record::onlyNamed`
  String ? rr() {
    if (this.fy() case _?) {
      if (this.apply(this.rw) case var named?) {
        if (this.fx() case _?) {
          return "(" + named + ")";
        }
      }
    }
  }

  /// `global::dart::type::nonNullable::record::empty`
  String ? rs() {
    if (this.fy() case _?) {
      if (this.fx() case _?) {
        return "()";
      }
    }
  }

  /// `global::dart::type::nonNullable::base`
  String ? rt() {
    if (this.f9() case var _0?) {
      if ([_0] case (var $ && var _l1)) {
        for (;;) {
          if (this._mark() case var _mark) {
            if (this.f16() case _?) {
              if (this.f9() case var _0?) {
                _l1.add(_0);
                continue;
              }
            }
            this._recover(_mark);
            break;
          }
        }
        return $.join(".");
      }
    }
  }

  /// `global::dart::type::fnParameters`
  String ? ru() {
    if (this._mark() case var _mark) {
      if (this.fy() case _?) {
        if (this.apply(this.rx) case var positional?) {
          if (this.f14() case _?) {
            if (this.apply(this.rw) case var named?) {
              if (this.fx() case _?) {
                return "($positional, $named)";
              }
            }
          }
        }
      }
      this._recover(_mark);
      if (this.fy() case _?) {
        if (this.apply(this.rx) case var positional?) {
          if (this.f14() case _?) {
            if (this.apply(this.rv) case var optional?) {
              if (this.fx() case _?) {
                return "($positional, $optional)";
              }
            }
          }
        }
      }
      this._recover(_mark);
      if (this.fy() case _?) {
        if (this.apply(this.rx) case var positional?) {
          if (this.f4m() case _) {
            if (this.fx() case _?) {
              return "($positional)";
            }
          }
        }
      }
      this._recover(_mark);
      if (this.fy() case _?) {
        if (this.apply(this.rw) case var named?) {
          if (this.fx() case _?) {
            return "($named)";
          }
        }
      }
      this._recover(_mark);
      if (this.fy() case _?) {
        if (this.apply(this.rv) case var optional?) {
          if (this.fx() case _?) {
            return "($optional)";
          }
        }
      }
      this._recover(_mark);
      if (this.fy() case _?) {
        if (this.fx() case _?) {
          return "()";
        }
      }
    }
  }

  /// `global::dart::type::parameters::optional`
  String ? rv() {
    if (this.f4n() case _?) {
      if (this.apply(this.rx) case var $1?) {
        if (this.f4o() case _) {
          if (this.f4p() case _?) {
            return "[" + $1 + "]";
          }
        }
      }
    }
  }

  /// `global::dart::type::parameters::named`
  String ? rw() {
    if (this.fw() case _?) {
      if (this.apply(this.ry) case var $1?) {
        if (this.f4q() case _) {
          if (this.fv() case _?) {
            return "{" + $1 + "}";
          }
        }
      }
    }
  }

  /// `global::dart::type::fields::positional`
  String ? rx() {
    if (this.apply(this.rz) case var car?) {
      if (this.f14() case _?) {
        if (this._mark() case var _mark) {
          if (this.apply(this.rz) case var _0) {
            if ([if (_0 case var _0?) _0] case (var cdr && var _l1)) {
              if (cdr.isNotEmpty) {
                for (;;) {
                  if (this._mark() case var _mark) {
                      if (this.f14() case _?) {
                        if (this.apply(this.rz) case var _0?) {
                          _l1.add(_0);
                          continue;
                        }
                      }
                    this._recover(_mark);
                    break;
                  }
                }
              } else {
                this._recover(_mark);
              }
              return [car, ...cdr].join(", ");
            }
          }
        }
      }
    }
  }

  /// `global::dart::type::fields::named`
  String ? ry() {
    if (this.apply(this.r10) case var _0?) {
      if ([_0] case (var $ && var _l1)) {
        for (;;) {
          if (this._mark() case var _mark) {
            if (this.f14() case _?) {
              if (this.apply(this.r10) case var _0?) {
                _l1.add(_0);
                continue;
              }
            }
            this._recover(_mark);
            break;
          }
        }
        return $.join(", ");
      }
    }
  }

  /// `global::dart::type::field::positional`
  String ? rz() {
    if (this.f4() case var $0?) {
      if (this.apply(this.r11)! case _) {
        if (this.f4r() case var $2) {
          return "${$0} ${$2 ?? ""}".trimRight();
        }
      }
    }
  }

  /// `global::dart::type::field::named`
  String ? r10() {
    if (this.f4() case var $0?) {
      if (this.apply(this.r11)! case _) {
        if (this.f9() case var $2?) {
          return "${$0} ${$2}";
        }
      }
    }
  }

  /// `global::_`
  String  r11() {
    if (this._mark() case var _mark) {
      if (this.f4t() case var _0) {
        if ([if (_0 case var _0?) _0] case var _l1) {
          if (_l1.isNotEmpty) {
            for (;;) {
              if (this._mark() case var _mark) {
                if (this.f4t() case var _0?) {
                  _l1.add(_0);
                  continue;
                }
                this._recover(_mark);
                break;
              }
            }
          } else {
            this._recover(_mark);
          }
          return "";
        }
      }
    }
  }

  /// `global::whitespace`
  late final r12 = () {
    if (this.matchPattern(_regexp.$4) case var _0?) {
      if ([_0] case var _l1) {
        for (;;) {
          if (this._mark() case var _mark) {
            if (this.matchPattern(_regexp.$4) case var _0?) {
              _l1.add(_0);
              continue;
            }
            this._recover(_mark);
            break;
          }
        }
        return "";
      }
    }
  };

  /// `global::comment`
  String ? r13() {
    if (this._mark() case var _mark) {
      if (this.apply(this.r14) case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.apply(this.r15) case var $?) {
        return $;
      }
    }
  }

  /// `global::comment::single`
  String ? r14() {
    if (this.matchPattern(_string.$76) case _?) {
      if (this._mark() case var _mark) {
        if (this.f4u() case var _0) {
          if ([if (_0 case var _0?) _0] case var _l1) {
            if (_l1.isNotEmpty) {
              for (;;) {
                if (this._mark() case var _mark) {
                  if (this.f4u() case var _0?) {
                    _l1.add(_0);
                    continue;
                  }
                  this._recover(_mark);
                  break;
                }
              }
            } else {
              this._recover(_mark);
            }
            return "";
          }
        }
      }
    }
  }

  /// `global::comment::multi`
  String ? r15() {
    if (this.matchPattern(_string.$77) case _?) {
      if (this._mark() case var _mark) {
        if (this.f4v() case var _0) {
          if ([if (_0 case var _0?) _0] case var _l1) {
            if (_l1.isNotEmpty) {
              for (;;) {
                if (this._mark() case var _mark) {
                  if (this.f4v() case var _0?) {
                    _l1.add(_0);
                    continue;
                  }
                  this._recover(_mark);
                  break;
                }
              }
            } else {
              this._recover(_mark);
            }
            if (this.matchPattern(_string.$52) case _?) {
              return "";
            }
          }
        }
      }
    }
  }

  /// `global::newlineOrEof`
  late final r16 = () {
    if (this._mark() case var _mark) {
      if (this.f4w() case var $0) {
        if (this.matchPattern(_regexp.$2) case var $1?) {
          if (this.f4x() case var $2) {
            return ($0, $1, $2);
          }
        }
      }
      this._recover(_mark);
      if (this.pos case var $ when this.pos >= this.buffer.length) {
        return $;
      }
    }
  };

  static final _regexp = (
    RegExp("\\d"),
    RegExp("\\n"),
    RegExp("\\r"),
    RegExp("\\s"),
  );
  static const _string = (
    "0",
    "1",
    "2",
    "3",
    "4",
    "5",
    "6",
    "7",
    "8",
    "9",
    "\\",
    "]",
    "@rule",
    "@fragment",
    "@inline",
    "choice!",
    "..",
    "<~",
    "<",
    ">",
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
    "|",
    ".",
    "\"\"\"",
    "r",
    "'''",
    "\"",
    "'",
    "-",
    "|>",
    "@",
    "~>",
    "~",
    "&",
    "!",
    " ",
    "[",
    "/",
    "r\"\"\"",
    "r'''",
    "r\"",
    "r'",
    "*/",
    "`",
    "::",
    "range!",
    "flat!",
    "sep!",
    "d",
    "w",
    "s",
    "b",
    "D",
    "W",
    "S",
    "n",
    "t",
    "f",
    "v",
    "\$",
    "E",
    "e",
    ":",
    "^",
    "ε",
    "Function",
    "//",
    "/*",
  );
  static const _range = (
    { (97, 122), (65, 90), (48, 57), (95, 95), (36, 36) },
    { (97, 122), (65, 90), (95, 95), (36, 36) },
  );
}
