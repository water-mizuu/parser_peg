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

extension on Node {
  Node operator |(Node other) => switch ((this, other)) {
    (ChoiceNode(children :var l), ChoiceNode(children: var r)) => ChoiceNode([...l, ...r]),
    (ChoiceNode(children :var l), Node r) => ChoiceNode([...l, r]),
    (Node l, ChoiceNode(children: var r)) => ChoiceNode([l, ...r]),
    (Node l, Node r) => ChoiceNode([l, r]),
  };
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
final class AstGrammarParser extends _PegParser<Object> {
  AstGrammarParser();

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
  Object? f3() {
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
  Object? f4() {
    if (this._mark() case var _mark) {
      if (this.apply(this.r11)! case _) {
        if (this.f4d() case var $1?) {
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
  Object f5() {
    if (this._mark() case var _mark) {
      if (this.f4h() case var _0?) {
        if ([_0].nullable() case var _l1) {
          if (_l1 != null) {
            for (;;) {
              if (this._mark() case var _mark) {
                if (this.f4h() case var _0?) {
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
            return _l1;
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
  Object? f6() {
    if (this._mark() case var _mark) {
      if (this.f5() case var $0) {
        if (this.f4j() case var $1?) {
          return ($0, $1);
        }
      }
      this._recover(_mark);
      if (this.f7() case var $?) {
        return $;
      }
    }
  }

  /// `global::namespacedIdentifier`
  Object? f7() {
    if (this.f5() case var $0) {
      if (this.f8() case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `global::identifier`
  Object? f8() {
    if (this.matchRange(_range.$2) case var $0?) {
      if (this._mark() case var _mark) {
        if (this.matchRange(_range.$1) case var _0) {
          if ([if (_0 case var _0?) _0] case (var $1 && var _l1)) {
            if ($1.isNotEmpty) {
              for (;;) {
                if (this._mark() case var _mark) {
                    if ('' case _) {
                      if (this.matchRange(_range.$1) case var _0?) {
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
            return ($0, $1);
          }
        }
      }
    }
  }

  /// `global::number`
  Object? f9() {
    if (this.matchPattern(_regexp.$1) case var _0?) {
      if ([_0] case var _l1) {
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
        return _l1;
      }
    }
  }

  /// `global::kw::decorator`
  Object? fa() {
    if (this._mark() case var _mark) {
      if (this.apply(this.r11)! case var $0) {
        if (this.matchPattern(_string.$13) case var $1?) {
          if (this.apply(this.r11)! case var $2) {
            return ($0, $1, $2);
          }
        }
      }
      this._recover(_mark);
      if (this.apply(this.r11)! case var $0) {
        if (this.matchPattern(_string.$14) case var $1?) {
          if (this.apply(this.r11)! case var $2) {
            return ($0, $1, $2);
          }
        }
      }
      this._recover(_mark);
      if (this.apply(this.r11)! case var $0) {
        if (this.matchPattern(_string.$15) case var $1?) {
          if (this.apply(this.r11)! case var $2) {
            return ($0, $1, $2);
          }
        }
      }
    }
  }

  /// `global::mac::choice`
  Object? fb() {
    if (this.apply(this.r11)! case _) {
      if (this.matchPattern(_string.$16) case var $1?) {
        if (this.apply(this.r11)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::regexEscape::backslash`
  Object? fc() {
    if (this.apply(this.r11)! case _) {
      if (this.f4l() case var $1?) {
        return $1;
      }
    }
  }

  /// `global::regexEscape::digit`
  Object? fd() {
    if (this.apply(this.r11)! case _) {
      if (this.f4m() case var $1?) {
        if (this.apply(this.r11)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::regexEscape::word`
  Object? fe() {
    if (this.apply(this.r11)! case _) {
      if (this.f4n() case var $1?) {
        if (this.apply(this.r11)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::regexEscape::whitespace`
  Object? ff() {
    if (this.apply(this.r11)! case _) {
      if (this.f4o() case var $1?) {
        if (this.apply(this.r11)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::regexEscape::wordBoundary`
  Object? fg() {
    if (this.apply(this.r11)! case _) {
      if (this.f4p() case var $1?) {
        if (this.apply(this.r11)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::regexEscape::notDigit`
  Object? fh() {
    if (this.apply(this.r11)! case _) {
      if (this.f4q() case var $1?) {
        if (this.apply(this.r11)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::regexEscape::notWord`
  Object? fi() {
    if (this.apply(this.r11)! case _) {
      if (this.f4r() case var $1?) {
        if (this.apply(this.r11)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::regexEscape::notWhitespace`
  Object? fj() {
    if (this.apply(this.r11)! case _) {
      if (this.f4s() case var $1?) {
        if (this.apply(this.r11)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::regexEscape::newline`
  Object? fk() {
    if (this.apply(this.r11)! case _) {
      if (this.f4t() case var $1?) {
        if (this.apply(this.r11)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::regexEscape::carriageReturn`
  Object? fl() {
    if (this.apply(this.r11)! case _) {
      if (this.f4u() case var $1?) {
        if (this.apply(this.r11)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::regexEscape::tab`
  Object? fm() {
    if (this.apply(this.r11)! case _) {
      if (this.f4v() case var $1?) {
        if (this.apply(this.r11)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::regexEscape::formFeed`
  Object? fn() {
    if (this.apply(this.r11)! case _) {
      if (this.f4w() case var $1?) {
        if (this.apply(this.r11)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::regexEscape::verticalTab`
  Object? fo() {
    if (this.apply(this.r11)! case _) {
      if (this.f4x() case var $1?) {
        if (this.apply(this.r11)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::CHOICE_OP`
  Object? fp() {
    if (this.f14() case var $0?) {
      if (this.f4y() case var $1) {
        return ($0, $1);
      }
    }
  }

  /// `global::..`
  Object? fq() {
    if (this.apply(this.r11)! case _) {
      if (this.matchPattern(_string.$17) case var $1?) {
        if (this.apply(this.r11)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::<~`
  Object? fr() {
    if (this.apply(this.r11)! case _) {
      if (this.matchPattern(_string.$18) case var $1?) {
        if (this.apply(this.r11)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::<`
  Object? fs() {
    if (this.apply(this.r11)! case _) {
      if (this.matchPattern(_string.$19) case var $1?) {
        if (this.apply(this.r11)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::>`
  Object? ft() {
    if (this.apply(this.r11)! case _) {
      if (this.matchPattern(_string.$20) case var $1?) {
        if (this.apply(this.r11)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::}`
  Object? fu() {
    if (this.apply(this.r11)! case _) {
      if (this.matchPattern(_string.$21) case var $1?) {
        if (this.apply(this.r11)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::{`
  Object? fv() {
    if (this.apply(this.r11)! case _) {
      if (this.matchPattern(_string.$22) case var $1?) {
        if (this.apply(this.r11)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::)`
  Object? fw() {
    if (this.apply(this.r11)! case _) {
      if (this.matchPattern(_string.$23) case var $1?) {
        if (this.apply(this.r11)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::(`
  Object? fx() {
    if (this.apply(this.r11)! case _) {
      if (this.matchPattern(_string.$24) case var $1?) {
        if (this.apply(this.r11)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::;`
  Object? fy() {
    if (this.apply(this.r11)! case _) {
      if (this.matchPattern(_string.$25) case var $1?) {
        if (this.apply(this.r11)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::=`
  Object? fz() {
    if (this.apply(this.r11)! case _) {
      if (this.matchPattern(_string.$26) case var $1?) {
        if (this.apply(this.r11)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::?`
  Object? f10() {
    if (this.apply(this.r11)! case _) {
      if (this.matchPattern(_string.$27) case var $1?) {
        if (this.apply(this.r11)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::*`
  Object? f11() {
    if (this.apply(this.r11)! case _) {
      if (this.matchPattern(_string.$28) case var $1?) {
        if (this.apply(this.r11)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::+`
  Object? f12() {
    if (this.apply(this.r11)! case _) {
      if (this.matchPattern(_string.$29) case var $1?) {
        if (this.apply(this.r11)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::,`
  Object? f13() {
    if (this.apply(this.r11)! case _) {
      if (this.matchPattern(_string.$30) case var $1?) {
        if (this.apply(this.r11)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::|`
  Object? f14() {
    if (this.apply(this.r11)! case _) {
      if (this.matchPattern(_string.$31) case var $1?) {
        if (this.apply(this.r11)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::.`
  Object? f15() {
    if (this.apply(this.r11)! case _) {
      if (this.matchPattern(_string.$32) case var $1?) {
        if (this.apply(this.r11)! case _) {
          return $1;
        }
      }
    }
  }

  /// `ROOT`
  Object? f16() {
    if (this.apply(this.r0) case var $?) {
      return $;
    }
  }

  /// `global::dart::literal::string::body`
  Object? f17() {
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
                if (this.f4z() case var _0) {
                  if ([if (_0 case var _0?) _0] case (var $2 && var _l1)) {
                    if (_l1.isNotEmpty) {
                      for (;;) {
                        if (this._mark() case var _mark) {
                          if (this.f4z() case var _0?) {
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
                if (this.f50() case var _4) {
                  if ([if (_4 case var _4?) _4] case (var $2 && var _l5)) {
                    if (_l5.isNotEmpty) {
                      for (;;) {
                        if (this._mark() case var _mark) {
                          if (this.f50() case var _4?) {
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
                if (this.f51() case var _8) {
                  if ([if (_8 case var _8?) _8] case (var $2 && var _l9)) {
                    if (_l9.isNotEmpty) {
                      for (;;) {
                        if (this._mark() case var _mark) {
                          if (this.f51() case var _8?) {
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
                if (this.f52() case var _12) {
                  if ([if (_12 case var _12?) _12] case (var $2 && var _l13)) {
                    if (_l13.isNotEmpty) {
                      for (;;) {
                        if (this._mark() case var _mark) {
                          if (this.f52() case var _12?) {
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
          if (this.f56() case var _16) {
            if ([if (_16 case var _16?) _16] case (var $1 && var _l17)) {
              if (_l17.isNotEmpty) {
                for (;;) {
                  if (this._mark() case var _mark) {
                    if (this.f56() case var _16?) {
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
          if (this.f5a() case var _18) {
            if ([if (_18 case var _18?) _18] case (var $1 && var _l19)) {
              if (_l19.isNotEmpty) {
                for (;;) {
                  if (this._mark() case var _mark) {
                    if (this.f5a() case var _18?) {
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
          if (this.f5e() case var _20) {
            if ([if (_20 case var _20?) _20] case (var $1 && var _l21)) {
              if (_l21.isNotEmpty) {
                for (;;) {
                  if (this._mark() case var _mark) {
                    if (this.f5e() case var _20?) {
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
          if (this.f5i() case var _22) {
            if ([if (_22 case var _22?) _22] case (var $1 && var _l23)) {
              if (_l23.isNotEmpty) {
                for (;;) {
                  if (this._mark() case var _mark) {
                    if (this.f5i() case var _22?) {
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
  }

  /// `global::json::atom::number::number`
  Object? f18() {
    if (this.f19() case var $0?) {
      if (this.f1a() case var $1) {
        if (this.f1b() case var $2) {
          return ($0, $1, $2);
        }
      }
    }
  }

  /// `global::json::atom::number::integer`
  Object? f19() {
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
  Object f1a() {
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
  Object f1b() {
    if (this._mark() case var _mark) {
      if (this.f5j() case var $0?) {
        if (this.f5k() case var $1) {
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
  Object? f1c() {
    if (this.apply(this.r1) case var $?) {
      return $;
    }
  }

  /// `fragment1`
  Object f1d() {
    if (this.apply(this.r11)! case var $) {
      return $;
    }
  }

  /// `fragment2`
  Object? f1e() {
    if (this.fa() case var $?) {
      return $;
    }
  }

  /// `fragment3`
  Object? f1f() {
    if (this.fa() case var $?) {
      return $;
    }
  }

  /// `fragment4`
  Object? f1g() {
    if (this.fy() case var $?) {
      return $;
    }
  }

  /// `fragment5`
  Object? f1h() {
    if (this.fa() case var $?) {
      return $;
    }
  }

  /// `fragment6`
  Object? f1i() {
    if (this.fa() case var $?) {
      return $;
    }
  }

  /// `fragment7`
  Object? f1j() {
    if (this.fy() case var $?) {
      return $;
    }
  }

  /// `fragment8`
  Object? f1k() {
    if (this.fa() case var $?) {
      return $;
    }
  }

  /// `fragment9`
  Object? f1l() {
    if (this.f4() case var $?) {
      return $;
    }
  }

  /// `fragment10`
  Object? f1m() {
    if (this.fa() case var $?) {
      return $;
    }
  }

  /// `fragment11`
  Object? f1n() {
    if (this.fy() case var $?) {
      return $;
    }
  }

  /// `fragment12`
  Object? f1o() {
    if (this.fa() case var $?) {
      return $;
    }
  }

  /// `fragment13`
  Object? f1p() {
    if (this.f8() case var $?) {
      return $;
    }
  }

  /// `fragment14`
  Object? f1q() {
    if (this.fa() case var $?) {
      return $;
    }
  }

  /// `fragment15`
  Object? f1r() {
    if (this.f4() case var $?) {
      return $;
    }
  }

  /// `fragment16`
  Object? f1s() {
    if (this.fa() case var $?) {
      return $;
    }
  }

  /// `fragment17`
  Object? f1t() {
    if (this.fz() case _?) {
      if (this.apply(this.r3) case (var $1 && var choice)?) {
        if (this.fy() case _?) {
          return $1;
        }
      }
    }
  }

  /// `fragment18`
  Object? f1u() {
    if (this.fa() case var $?) {
      return $;
    }
  }

  /// `fragment19`
  Object? f1v() {
    if (this.fz() case _?) {
      if (this.apply(this.r3) case (var $1 && var choice)?) {
        if (this.fy() case _?) {
          return $1;
        }
      }
    }
  }

  /// `fragment20`
  Object? f1w() {
    if (this.fp() case var $?) {
      return $;
    }
  }

  /// `fragment21`
  Object? f1x() {
    if (this.apply(this.r11)! case _) {
      if (this.matchPattern(_string.$39) case var $1?) {
        if (this.apply(this.r11)! case _) {
          return $1;
        }
      }
    }
  }

  /// `fragment22`
  Object? f1y() {
    if (this.apply(this.r11)! case _) {
      if (this.matchPattern(_string.$40) case var $1?) {
        if (this.apply(this.r11)! case _) {
          return $1;
        }
      }
    }
  }

  /// `fragment23`
  Object? f1z() {
    if (this.f1y() case _?) {
      if (this.f9() case var $1?) {
        return $1;
      }
    }
  }

  /// `fragment24`
  Object? f20() {
    if (this.apply(this.r11)! case _) {
      if (this.matchPattern(_string.$41) case var $1?) {
        if (this.apply(this.r11)! case _) {
          return $1;
        }
      }
    }
  }

  /// `fragment25`
  Object? f21() {
    if (this.apply(this.r11)! case _) {
      if (this.matchPattern(_string.$42) case var $1?) {
        if (this.apply(this.r11)! case _) {
          return $1;
        }
      }
    }
  }

  /// `fragment26`
  Object? f22() {
    if (this.apply(this.r11)! case _) {
      if (this.matchPattern(_string.$43) case var $1?) {
        if (this.apply(this.r11)! case _) {
          return $1;
        }
      }
    }
  }

  /// `fragment27`
  Object? f23() {
    if (this.apply(this.r11)! case _) {
      if (this.matchPattern(_string.$44) case var $1?) {
        if (this.apply(this.r11)! case _) {
          return $1;
        }
      }
    }
  }

  /// `fragment28`
  Object? f24() {
    if (this.apply(this.r3) case var $0?) {
      if (this.fw() case _?) {
        return $0;
      }
    }
  }

  /// `fragment29`
  Object? f25() {
    if (this.matchPattern(_string.$45) case var $?) {
      return $;
    }
  }

  /// `fragment30`
  Object? f26() {
    if (this.fd() case var $?) {
      return $;
    }
  }

  /// `fragment31`
  Object? f27() {
    if (this.fe() case var $?) {
      return $;
    }
  }

  /// `fragment32`
  Object? f28() {
    if (this.ff() case var $?) {
      return $;
    }
  }

  /// `fragment33`
  Object? f29() {
    if (this.fk() case var $?) {
      return $;
    }
  }

  /// `fragment34`
  Object? f2a() {
    if (this.fl() case var $?) {
      return $;
    }
  }

  /// `fragment35`
  Object? f2b() {
    if (this.fm() case var $?) {
      return $;
    }
  }

  /// `fragment36`
  Object? f2c() {
    if (this.fc() case var $?) {
      return $;
    }
  }

  /// `fragment37`
  Object? f2d() {
    if (this._mark() case var _mark) {
      if (this.f25() case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.f26() case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.f27() case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.f28() case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.f29() case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.f2a() case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.f2b() case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.f2c() case var $?) {
        return $;
      }
    }
  }

  /// `fragment38`
  Object? f2e() {
    if (this.f3() case (var $0 && var l)?) {
      if (this.matchPattern(_string.$38) case var $1?) {
        if (this.f3() case (var $2 && var r)?) {
          return ($0, $1, $2);
        }
      }
    }
  }

  /// `fragment39`
  Object? f2f() {
    if (this.f3() case var $?) {
      return $;
    }
  }

  /// `fragment40`
  Object? f2g() {
    if (this._mark() case var _mark) {
      if (this.f2d() case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.f2e() case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.f2f() case var $?) {
        return $;
      }
    }
  }

  /// `fragment41`
  Object? f2h() {
    if (this.matchPattern(_string.$46) case var $0?) {
      if (this.f2g() case var _0?) {
        if ([_0] case (var $1 && var elements && var _l1)) {
          for (;;) {
            if (this._mark() case var _mark) {
              if (this.apply(this.r11)! case _) {
                if (this.f2g() case var _0?) {
                  _l1.add(_0);
                  continue;
                }
              }
              this._recover(_mark);
              break;
            }
          }
          if (this.matchPattern(_string.$12) case var $2?) {
            return ($0, $1, $2);
          }
        }
      }
    }
  }

  /// `fragment42`
  Object? f2i() {
    if (this.matchPattern(_string.$11) case _?) {
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $1) {
          return $1;
        }
      }
    }
  }

  /// `fragment43`
  Object? f2j() {
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
  }

  /// `fragment44`
  Object? f2k() {
    if (this._mark() case var _mark) {
      if (this.f2i() case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.f2j() case var $?) {
        return $;
      }
    }
  }

  /// `fragment45`
  Object? f2l() {
    if (this.f2k() case var _0?) {
      if ([_0] case var _l1) {
        for (;;) {
          if (this._mark() case var _mark) {
            if (this.f2k() case var _0?) {
              _l1.add(_0);
              continue;
            }
            this._recover(_mark);
            break;
          }
        }
        return _l1;
      }
    }
  }

  /// `fragment46`
  Object? f2m() {
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
  }

  /// `fragment47`
  Object? f2n() {
    if (this.matchPattern(_string.$48) case _?) {
      if (this._mark() case var _mark) {
        if (this.f2m() case var _0) {
          if ([if (_0 case var _0?) _0] case (var $1 && var _l1)) {
            if (_l1.isNotEmpty) {
              for (;;) {
                if (this._mark() case var _mark) {
                  if (this.f2m() case var _0?) {
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
              return $1;
            }
          }
        }
      }
    }
  }

  /// `fragment48`
  Object? f2o() {
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
  }

  /// `fragment49`
  Object? f2p() {
    if (this.matchPattern(_string.$49) case _?) {
      if (this._mark() case var _mark) {
        if (this.f2o() case var _0) {
          if ([if (_0 case var _0?) _0] case (var $1 && var _l1)) {
            if (_l1.isNotEmpty) {
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
            } else {
              this._recover(_mark);
            }
            if (this.matchPattern(_string.$35) case _?) {
              return $1;
            }
          }
        }
      }
    }
  }

  /// `fragment50`
  Object? f2q() {
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
  }

  /// `fragment51`
  Object? f2r() {
    if (this.matchPattern(_string.$50) case _?) {
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
            if (this.matchPattern(_string.$36) case _?) {
              return $1;
            }
          }
        }
      }
    }
  }

  /// `fragment52`
  Object? f2s() {
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
  }

  /// `fragment53`
  Object? f2t() {
    if (this.matchPattern(_string.$51) case _?) {
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
            if (this.matchPattern(_string.$37) case _?) {
              return $1;
            }
          }
        }
      }
    }
  }

  /// `fragment54`
  Object? f2u() {
    if (this.matchPattern(_string.$11) case var $0?) {
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $1) {
          return ($0, $1);
        }
      }
    }
  }

  /// `fragment55`
  Object? f2v() {
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
  }

  /// `fragment56`
  Object? f2w() {
    if (this._mark() case var _mark) {
      if (this.f2u() case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.f2v() case var $?) {
        return $;
      }
    }
  }

  /// `fragment57`
  Object? f2x() {
    if (this.matchPattern(_string.$33) case _?) {
      if (this._mark() case var _mark) {
        if (this.f2w() case var _0) {
          if ([if (_0 case var _0?) _0] case (var $1 && var _l1)) {
            if (_l1.isNotEmpty) {
              for (;;) {
                if (this._mark() case var _mark) {
                  if (this.f2w() case var _0?) {
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
              return $1;
            }
          }
        }
      }
    }
  }

  /// `fragment58`
  Object? f2y() {
    if (this.matchPattern(_string.$11) case var $0?) {
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $1) {
          return ($0, $1);
        }
      }
    }
  }

  /// `fragment59`
  Object? f2z() {
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
  }

  /// `fragment60`
  Object? f30() {
    if (this._mark() case var _mark) {
      if (this.f2y() case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.f2z() case var $?) {
        return $;
      }
    }
  }

  /// `fragment61`
  Object? f31() {
    if (this.matchPattern(_string.$35) case _?) {
      if (this._mark() case var _mark) {
        if (this.f30() case var _0) {
          if ([if (_0 case var _0?) _0] case (var $1 && var _l1)) {
            if (_l1.isNotEmpty) {
              for (;;) {
                if (this._mark() case var _mark) {
                  if (this.f30() case var _0?) {
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
              return $1;
            }
          }
        }
      }
    }
  }

  /// `fragment62`
  Object? f32() {
    if (this.matchPattern(_string.$11) case var $0?) {
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $1) {
          return ($0, $1);
        }
      }
    }
  }

  /// `fragment63`
  Object? f33() {
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
  }

  /// `fragment64`
  Object? f34() {
    if (this._mark() case var _mark) {
      if (this.f32() case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.f33() case var $?) {
        return $;
      }
    }
  }

  /// `fragment65`
  Object? f35() {
    if (this.matchPattern(_string.$36) case _?) {
      if (this._mark() case var _mark) {
        if (this.f34() case var _0) {
          if ([if (_0 case var _0?) _0] case (var $1 && var _l1)) {
            if (_l1.isNotEmpty) {
              for (;;) {
                if (this._mark() case var _mark) {
                  if (this.f34() case var _0?) {
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
              return $1;
            }
          }
        }
      }
    }
  }

  /// `fragment66`
  Object? f36() {
    if (this.matchPattern(_string.$11) case var $0?) {
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $1) {
          return ($0, $1);
        }
      }
    }
  }

  /// `fragment67`
  Object? f37() {
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
  }

  /// `fragment68`
  Object? f38() {
    if (this._mark() case var _mark) {
      if (this.f36() case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.f37() case var $?) {
        return $;
      }
    }
  }

  /// `fragment69`
  Object? f39() {
    if (this.matchPattern(_string.$37) case _?) {
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
            if (this.matchPattern(_string.$37) case _?) {
              return $1;
            }
          }
        }
      }
    }
  }

  /// `fragment70`
  Object? f3a() {
    if (this._mark() case var _mark) {
      if (this.f2n() case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.f2p() case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.f2r() case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.f2t() case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.f2x() case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.f31() case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.f35() case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.f39() case var $?) {
        return $;
      }
    }
  }

  /// `fragment71`
  Object? f3b() {
    if (this.matchPattern(_string.$22) case _?) {
      if (this.apply(this.re)! case var $1) {
        if (this.matchPattern(_string.$21) case _?) {
          return $1;
        }
      }
    }
  }

  /// `fragment72`
  Object? f3c() {
    if (this.matchPattern(_string.$24) case _?) {
      if (this.apply(this.re)! case var $1) {
        if (this.matchPattern(_string.$23) case _?) {
          return $1;
        }
      }
    }
  }

  /// `fragment73`
  Object? f3d() {
    if (this.matchPattern(_string.$46) case _?) {
      if (this.apply(this.re)! case var $1) {
        if (this.matchPattern(_string.$12) case _?) {
          return $1;
        }
      }
    }
  }

  /// `fragment74`
  Object? f3e() {
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
  }

  /// `fragment75`
  Object? f3f() {
    if (this._mark() case var _mark) {
      if (this.apply(this.rf) case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.f3b() case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.f3c() case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.f3d() case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.f3e() case var $?) {
        return $;
      }
    }
  }

  /// `fragment76`
  Object? f3g() {
    if (this.matchPattern(_string.$22) case _?) {
      if (this.apply(this.re)! case var $1) {
        if (this.matchPattern(_string.$21) case _?) {
          return $1;
        }
      }
    }
  }

  /// `fragment77`
  Object? f3h() {
    if (this.matchPattern(_string.$24) case _?) {
      if (this.apply(this.re)! case var $1) {
        if (this.matchPattern(_string.$23) case _?) {
          return $1;
        }
      }
    }
  }

  /// `fragment78`
  Object? f3i() {
    if (this.matchPattern(_string.$46) case _?) {
      if (this.apply(this.re)! case var $1) {
        if (this.matchPattern(_string.$12) case _?) {
          return $1;
        }
      }
    }
  }

  /// `fragment79`
  Object? f3j() {
    if (this._mark() case var _mark) {
      if (this.matchPattern(_regexp.$2) case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.matchPattern(_string.$25) case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.matchPattern(_string.$23) case var $?) {
        return $;
      }
    }
  }

  /// `fragment80`
  Object? f3k() {
    if (this._mark() case var _mark) {
      if (this.f3j() case null) {
        this._recover(_mark);
        if (this.pos < this.buffer.length) {
          if (this.buffer[this.pos++] case var $) {
            return $;
          }
        }
      }
    }
  }

  /// `fragment81`
  Object? f3l() {
    if (this._mark() case var _mark) {
      if (this.apply(this.rf) case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.f3g() case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.f3h() case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.f3i() case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.f3k() case var $?) {
        return $;
      }
    }
  }

  /// `fragment82`
  Object? f3m() {
    if (this.matchPattern(_string.$22) case _?) {
      if (this.apply(this.re)! case var $1) {
        if (this.matchPattern(_string.$21) case _?) {
          return $1;
        }
      }
    }
  }

  /// `fragment83`
  Object? f3n() {
    if (this.matchPattern(_string.$24) case _?) {
      if (this.apply(this.re)! case var $1) {
        if (this.matchPattern(_string.$23) case _?) {
          return $1;
        }
      }
    }
  }

  /// `fragment84`
  Object? f3o() {
    if (this.matchPattern(_string.$46) case _?) {
      if (this.apply(this.re)! case var $1) {
        if (this.matchPattern(_string.$12) case _?) {
          return $1;
        }
      }
    }
  }

  /// `fragment85`
  Object? f3p() {
    if (this._mark() case var _mark) {
      if (this.matchPattern(_string.$21) case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.matchPattern(_string.$23) case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.matchPattern(_string.$12) case var $?) {
        return $;
      }
    }
  }

  /// `fragment86`
  Object? f3q() {
    if (this._mark() case var _mark) {
      if (this.f3p() case null) {
        this._recover(_mark);
        if (this.pos < this.buffer.length) {
          if (this.buffer[this.pos++] case var $) {
            return $;
          }
        }
      }
    }
  }

  /// `fragment87`
  Object? f3r() {
    if (this._mark() case var _mark) {
      if (this.apply(this.rf) case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.f3m() case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.f3n() case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.f3o() case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.f3q() case var $?) {
        return $;
      }
    }
  }

  /// `fragment88`
  Object? f3s() {
    if (this.f17() case var $?) {
      return $;
    }
  }

  /// `fragment89`
  Object? f3t() {
    if (this.matchPattern(_string.$22) case _?) {
      if (this.apply(this.ri)! case (var $1 && var $)) {
        if (this.matchPattern(_string.$21) case _?) {
          return $1;
        }
      }
    }
  }

  /// `fragment90`
  Object? f3u() {
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
  }

  /// `fragment91`
  Object? f3v() {
    if (this._mark() case var _mark) {
      if (this.apply(this.rf) case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.f3t() case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.f3u() case var $?) {
        return $;
      }
    }
  }

  /// `fragment92`
  Object? f3w() {
    if (this.f10() case var $?) {
      return $;
    }
  }

  /// `fragment93`
  Object? f3x() {
    if (this.f4() case var _0?) {
      if ([_0] case var _l1) {
        for (;;) {
          if (this._mark() case var _mark) {
            if (this.f13() case _?) {
              if (this.f4() case var _0?) {
                _l1.add(_0);
                continue;
              }
            }
            this._recover(_mark);
            break;
          }
        }
        return _l1;
      }
    }
  }

  /// `fragment94`
  Object? f3y() {
    if (this.f13() case var $?) {
      return $;
    }
  }

  /// `fragment95`
  Object? f3z() {
    if (this.f13() case var $?) {
      return $;
    }
  }

  /// `fragment96`
  Object? f40() {
    if (this.apply(this.r11)! case _) {
      if (this.matchPattern(_string.$46) case var $1?) {
        if (this.apply(this.r11)! case _) {
          return $1;
        }
      }
    }
  }

  /// `fragment97`
  Object? f41() {
    if (this.f13() case var $?) {
      return $;
    }
  }

  /// `fragment98`
  Object? f42() {
    if (this.apply(this.r11)! case _) {
      if (this.matchPattern(_string.$12) case var $1?) {
        if (this.apply(this.r11)! case _) {
          return $1;
        }
      }
    }
  }

  /// `fragment99`
  Object? f43() {
    if (this.f13() case var $?) {
      return $;
    }
  }

  /// `fragment100`
  Object? f44() {
    if (this.f8() case var $?) {
      return $;
    }
  }

  /// `fragment101`
  Object? f45() {
    if (this._mark() case var _mark) {
      if (this.matchPattern(_string.$47) case var $0?) {
        this._recover(_mark);
        if (this.apply(this.r13) case var $1?) {
          return ($0, $1);
        }
      }
    }
  }

  /// `fragment102`
  Object? f46() {
    if (this._mark() case var _mark) {
      if (this.apply(this.r12) case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.f45() case var $?) {
        return $;
      }
    }
  }

  /// `fragment103`
  Object? f47() {
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
  }

  /// `fragment104`
  Object? f48() {
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
  }

  /// `fragment105`
  Object? f49() {
    if (this.matchPattern(_regexp.$3) case var $?) {
      return $;
    }
  }

  /// `fragment106`
  Object? f4a() {
    if (this.matchPattern(_regexp.$3) case var $?) {
      return $;
    }
  }

  /// `fragment107`
  Object? f4b() {
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
  }

  /// `fragment108`
  Object f4c() {
    if (this.f4b() case var _0) {
      if (this._mark() case var _mark) {
        var _l1 = [if (_0 case var _0?) _0];
        if (_l1.isNotEmpty) {
          for (;;) {
            if (this._mark() case var _mark) {
              if (this.f4b() case var _0?) {
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
          return _l1
        }
      }
    }
  }

  /// `fragment109`
  Object? f4d() {
    if (this.matchPattern(_string.$53) case _?) {
      if (this.f4c() case var $1) {
        if (this.matchPattern(_string.$53) case _?) {
          return $1;
        }
      }
    }
  }

  /// `fragment110`
  Object? f4e() {
    if (this._mark() case var _mark) {
      if (this.matchPattern(_string.$17) case (var $0 && null)) {
        this._recover(_mark);
        if (this.matchPattern(_string.$32) case var $1?) {
          return ($0, $1);
        }
      }
    }
  }

  /// `fragment111`
  Object? f4f() {
    if (this._mark() case var _mark) {
      if (this.matchPattern(_string.$54) case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.f4e() case var $?) {
        return $;
      }
    }
  }

  /// `fragment112`
  Object? f4g() {
    if (this._mark() case var _mark) {
      if (this.fb() case var $?) {
        return $;
      }
    }
  }

  /// `fragment113`
  Object? f4h() {
    if (this.f8() case var $0?) {
      if (this.f4f() case _?) {
        if (this._mark() case var _mark) {
          if (this.f4g() case null) {
            this._recover(_mark);
            return $0;
          }
        }
      }
    }
  }

  /// `fragment114`
  Object? f4i() {
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
  }

  /// `fragment115`
  Object? f4j() {
    if (this.matchPattern(_string.$53) case _?) {
      if (this._mark() case var _mark) {
        if (this.f4i() case var _0) {
          if ([if (_0 case var _0?) _0] case (var $1 && var _l1)) {
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
            if (this.matchPattern(_string.$53) case _?) {
              return $1;
            }
          }
        }
      }
    }
  }

  /// `fragment116`
  Object? f4k() {
    if (this.matchPattern(_string.$11) case var $0?) {
      if (this.matchPattern(_string.$11) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `fragment117`
  Object? f4l() {
    if (this.f4k() case var $0?) {
      if (this.apply(this.r11)! case _) {
        return $0;
      }
    }
  }

  /// `fragment118`
  Object? f4m() {
    if (this.matchPattern(_string.$11) case var $0?) {
      if (this.matchPattern(_string.$55) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `fragment119`
  Object? f4n() {
    if (this.matchPattern(_string.$11) case var $0?) {
      if (this.matchPattern(_string.$56) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `fragment120`
  Object? f4o() {
    if (this.matchPattern(_string.$11) case var $0?) {
      if (this.matchPattern(_string.$57) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `fragment121`
  Object? f4p() {
    if (this.matchPattern(_string.$11) case var $0?) {
      if (this.matchPattern(_string.$58) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `fragment122`
  Object? f4q() {
    if (this.matchPattern(_string.$11) case var $0?) {
      if (this.matchPattern(_string.$59) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `fragment123`
  Object? f4r() {
    if (this.matchPattern(_string.$11) case var $0?) {
      if (this.matchPattern(_string.$60) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `fragment124`
  Object? f4s() {
    if (this.matchPattern(_string.$11) case var $0?) {
      if (this.matchPattern(_string.$61) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `fragment125`
  Object? f4t() {
    if (this.matchPattern(_string.$11) case var $0?) {
      if (this.matchPattern(_string.$62) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `fragment126`
  Object? f4u() {
    if (this.matchPattern(_string.$11) case var $0?) {
      if (this.matchPattern(_string.$34) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `fragment127`
  Object? f4v() {
    if (this.matchPattern(_string.$11) case var $0?) {
      if (this.matchPattern(_string.$63) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `fragment128`
  Object? f4w() {
    if (this.matchPattern(_string.$11) case var $0?) {
      if (this.matchPattern(_string.$64) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `fragment129`
  Object? f4x() {
    if (this.matchPattern(_string.$11) case var $0?) {
      if (this.matchPattern(_string.$65) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `fragment130`
  Object? f4y() {
    if (this.f14() case var $?) {
      return $;
    }
  }

  /// `fragment131`
  Object? f4z() {
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
  }

  /// `fragment132`
  Object? f50() {
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
  }

  /// `fragment133`
  Object? f51() {
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
  }

  /// `fragment134`
  Object? f52() {
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
  }

  /// `fragment135`
  Object? f53() {
    if (this.matchPattern(_string.$11) case _?) {
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $1) {
          return $1;
        }
      }
    }
  }

  /// `fragment136`
  Object? f54() {
    if (this._mark() case var _mark) {
      if (this.matchPattern(_string.$66) case var $0?) {
        this._recover(_mark);
        if (this.apply(this.rh) case var $1?) {
          return ($0, $1);
        }
      }
    }
  }

  /// `fragment137`
  Object? f55() {
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
  }

  /// `fragment138`
  Object? f56() {
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
    }
  }

  /// `fragment139`
  Object? f57() {
    if (this.matchPattern(_string.$11) case _?) {
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $1) {
          return $1;
        }
      }
    }
  }

  /// `fragment140`
  Object? f58() {
    if (this._mark() case var _mark) {
      if (this.matchPattern(_string.$66) case var $0?) {
        this._recover(_mark);
        if (this.apply(this.rh) case var $1?) {
          return ($0, $1);
        }
      }
    }
  }

  /// `fragment141`
  Object? f59() {
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
  }

  /// `fragment142`
  Object? f5a() {
    if (this._mark() case var _mark) {
      if (this.f57() case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.f58() case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.f59() case var $?) {
        return $;
      }
    }
  }

  /// `fragment143`
  Object? f5b() {
    if (this.matchPattern(_string.$11) case _?) {
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $1) {
          return $1;
        }
      }
    }
  }

  /// `fragment144`
  Object? f5c() {
    if (this._mark() case var _mark) {
      if (this.matchPattern(_string.$66) case var $0?) {
        this._recover(_mark);
        if (this.apply(this.rh) case var $1?) {
          return ($0, $1);
        }
      }
    }
  }

  /// `fragment145`
  Object? f5d() {
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
  }

  /// `fragment146`
  Object? f5e() {
    if (this._mark() case var _mark) {
      if (this.f5b() case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.f5c() case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.f5d() case var $?) {
        return $;
      }
    }
  }

  /// `fragment147`
  Object? f5f() {
    if (this.matchPattern(_string.$11) case _?) {
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $1) {
          return $1;
        }
      }
    }
  }

  /// `fragment148`
  Object? f5g() {
    if (this._mark() case var _mark) {
      if (this.matchPattern(_string.$66) case var $0?) {
        this._recover(_mark);
        if (this.apply(this.rh) case var $1?) {
          return ($0, $1);
        }
      }
    }
  }

  /// `fragment149`
  Object? f5h() {
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
  }

  /// `fragment150`
  Object? f5i() {
    if (this._mark() case var _mark) {
      if (this.f5f() case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.f5g() case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.f5h() case var $?) {
        return $;
      }
    }
  }

  /// `fragment151`
  Object? f5j() {
    if (this._mark() case var _mark) {
      if (this.matchPattern(_string.$67) case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.matchPattern(_string.$68) case var $?) {
        return $;
      }
    }
  }

  /// `fragment152`
  Object f5k() {
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
  }

  /// `global::document`
  Object? r0() {
    if (this.pos case var $0 && <= 0) {
      if (this.f1c() case var $1) {
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
            if (this.f1d() case var $3) {
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
    if (this.fv() case _?) {
      if (this.apply(this.r11)! case _) {
        if (this.apply(this.rc)! case (var $2 && var code)) {
          if (this.apply(this.r11)! case _) {
            if (this.fu() case _?) {
              return $2;
            }
          }
        }
      }
    }
  }

  /// `global::statement`
  Object? r2() {
    if (this._mark() case var _mark) {
      if (this.f1e() case (var $0 && var outer_decorator)) {
        if (this.f8() case (var $1 && var name)?) {
          if (this.fz() case var $2?) {
            if (this.fb() case var $3?) {
              if (this.f1f() case (var $4 && var inner_decorator)) {
                if (this.fv() case var $5?) {
                  if (this.apply(this.r2) case var _0?) {
                    if ([_0] case (var $6 && var statements && var _l1)) {
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
                      if (this.fu() case var $7?) {
                        if (this.f1g() case var $8) {
                          return ($0, $1, $2, $3, $4, $5, $6, $7, $8);
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
      if (this.f1h() case (var $0 && var outer_decorator)) {
        if (this.f4() case (var $1 && var type)?) {
          if (this.f8() case (var $2 && var name)?) {
            if (this.fz() case var $3?) {
              if (this.fb() case var $4?) {
                if (this.f1i() case (var $5 && var inner_decorator)) {
                  if (this.fv() case var $6?) {
                    if (this.apply(this.r2) case var _2?) {
                      if ([_2] case (var $7 && var statements && var _l3)) {
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
                        if (this.fu() case var $8?) {
                          if (this.f1j() case var $9) {
                            return ($0, $1, $2, $3, $4, $5, $6, $7, $8, $9);
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
      if (this.f1k() case (var $0 && var outer_decorator)) {
        if (this.f1l() case (var $1 && var type)) {
          if (this.fx() case var $2?) {
            if (this.fw() case var $3?) {
              if (this.fz() case var $4?) {
                if (this.fb() case var $5?) {
                  if (this.f1m() case (var $6 && var inner_decorator)) {
                    if (this.fv() case var $7?) {
                      if (this.apply(this.r2) case var _4?) {
                        if ([_4] case (var $8 && var statements && var _l5)) {
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
                          if (this.fu() case var $9?) {
                            if (this.f1n() case var $10) {
                              return ($0, $1, $2, $3, $4, $5, $6, $7, $8, $9, $10);
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
      if (this.f1o() case (var $0 && var decorator)) {
        if (this.f1p() case (var $1 && var name)) {
          if (this.fv() case var $2?) {
            if (this.apply(this.r2) case var _6?) {
              if ([_6] case (var $3 && var statements && var _l7)) {
                for (;;) {
                  if (this._mark() case var _mark) {
                    if (this.apply(this.r11)! case _) {
                      if (this.apply(this.r2) case var _6?) {
                        _l7.add(_6);
                        continue;
                      }
                    }
                    this._recover(_mark);
                    break;
                  }
                }
                if (this.fu() case var $4?) {
                  return ($0, $1, $2, $3, $4);
                }
              }
            }
          }
        }
      }
      this._recover(_mark);
      if (this.f1q() case (var $0 && var decorator)) {
        if (this.f1r() case (var $1 && var type)) {
          if (this.f6() case var _8?) {
            if ([_8] case (var $2 && var names && var _l9)) {
              for (;;) {
                if (this._mark() case var _mark) {
                  if (this.f13() case _?) {
                    if (this.f6() case var _8?) {
                      _l9.add(_8);
                      continue;
                    }
                  }
                  this._recover(_mark);
                  break;
                }
              }
              if (this.fy() case var $3?) {
                return ($0, $1, $2, $3);
              }
            }
          }
        }
      }
      this._recover(_mark);
      if (this.f1s() case (var $0 && var decorator)) {
        if (this.f4() case (var $1 && var type)?) {
          if (this.f6() case (var $2 && var name)?) {
            if (this.f1t() case (var $3 && var body)?) {
              return ($0, $1, $2, $3);
            }
          }
        }
      }
      this._recover(_mark);
      if (this.f1u() case (var $0 && var decorator)) {
        if (this.f6() case (var $1 && var name)?) {
          if (this.f1v() case (var $2 && var body)?) {
            return ($0, $1, $2);
          }
        }
      }
    }
  }

  /// `global::choice`
  Object? r3() {
    if (this.f1w() case var $0) {
      if (this.apply(this.r4) case var _0?) {
        if ([_0] case (var $1 && var options && var _l1)) {
          for (;;) {
            if (this._mark() case var _mark) {
              if (this.fp() case _?) {
                if (this.apply(this.r4) case var _0?) {
                  _l1.add(_0);
                  continue;
                }
              }
              this._recover(_mark);
              break;
            }
          }
          return ($0, $1);
        }
      }
    }
  }

  /// `global::acted`
  Object? r4() {
    if (this._mark() case var _mark) {
      if (this.apply(this.r5) case (var $0 && var sequence)?) {
        if (this.f1x() case var $1?) {
          if (this.apply(this.r11)! case var $2) {
            if (this.apply(this.rd)! case (var $3 && var code)) {
              if (this.apply(this.r11)! case var $4) {
                return ($0, $1, $2, $3, $4);
              }
            }
          }
        }
      }
      this._recover(_mark);
      if (this.apply(this.r5) case (var $0 && var sequence)?) {
        if (this.fv() case var $1?) {
          if (this.apply(this.r11)! case var $2) {
            if (this.apply(this.rc)! case (var $3 && var code)) {
              if (this.apply(this.r11)! case var $4) {
                if (this.fu() case var $5?) {
                  return ($0, $1, $2, $3, $4, $5);
                }
              }
            }
          }
        }
      }
      this._recover(_mark);
      if (this.apply(this.r5) case (var $0 && var sequence)?) {
        if (this.fx() case var $1?) {
          if (this.fw() case var $2?) {
            if (this.fv() case var $3?) {
              if (this.apply(this.r11)! case var $4) {
                if (this.apply(this.rc)! case (var $5 && var code)) {
                  if (this.apply(this.r11)! case var $6) {
                    if (this.fu() case var $7?) {
                      return ($0, $1, $2, $3, $4, $5, $6, $7);
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
  Object? r5() {
    if (this.apply(this.r6) case var _0?) {
      if ([_0] case (var $0 && var body && var _l1)) {
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
        if (this.f1z() case (var $1 && var chosen)) {
          return ($0, $1);
        }
      }
    }
  }

  /// `global::dropped`
  Object? r6() {
    if (this._mark() case var _mark) {
      if (this.apply(this.r6) case (var $0 && var captured)?) {
        if (this.fr() case var $1?) {
          if (this.apply(this.r8) case (var $2 && var dropped)?) {
            return ($0, $1, $2);
          }
        }
      }
      this._recover(_mark);
      if (this.apply(this.r8) case (var $0 && var dropped)?) {
        if (this.f20() case var $1?) {
          if (this.apply(this.r6) case (var $2 && var captured)?) {
            return ($0, $1, $2);
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
  Object? r7() {
    if (this._mark() case var _mark) {
      if (this.f8() case (var $0 && var identifier)?) {
        if (this.matchPattern(_string.$69) case var $1?) {
          if (this.apply(this.r11)! case var $2) {
            if (this.apply(this.r8) case (var $3 && var special)?) {
              return ($0, $1, $2, $3);
            }
          }
        }
      }
      this._recover(_mark);
      if (this.matchPattern(_string.$69) case var $0?) {
        if (this.f7() case (var $1 && var id)?) {
          if (this.f10() case var $2?) {
            return ($0, $1, $2);
          }
        }
      }
      this._recover(_mark);
      if (this.matchPattern(_string.$69) case var $0?) {
        if (this.f7() case (var $1 && var id)?) {
          if (this.f11() case var $2?) {
            return ($0, $1, $2);
          }
        }
      }
      this._recover(_mark);
      if (this.matchPattern(_string.$69) case var $0?) {
        if (this.f7() case (var $1 && var id)?) {
          if (this.f12() case var $2?) {
            return ($0, $1, $2);
          }
        }
      }
      this._recover(_mark);
      if (this.matchPattern(_string.$69) case var $0?) {
        if (this.f7() case (var $1 && var id)?) {
          return ($0, $1);
        }
      }
      this._recover(_mark);
      if (this.apply(this.r8) case var $?) {
        return $;
      }
    }
  }

  /// `global::special`
  Object? r8() {
    if (this._mark() case var _mark) {
      if (this.apply(this.rb) case (var $0 && var sep)?) {
        if (this.fq() case var $1?) {
          if (this.apply(this.rb) case (var $2 && var expr)?) {
            if (this.f12() case var $3?) {
              if (this.f10() case var $4?) {
                return ($0, $1, $2, $3, $4);
              }
            }
          }
        }
      }
      this._recover(_mark);
      if (this.apply(this.rb) case (var $0 && var sep)?) {
        if (this.fq() case var $1?) {
          if (this.apply(this.rb) case (var $2 && var expr)?) {
            if (this.f11() case var $3?) {
              if (this.f10() case var $4?) {
                return ($0, $1, $2, $3, $4);
              }
            }
          }
        }
      }
      this._recover(_mark);
      if (this.apply(this.rb) case (var $0 && var sep)?) {
        if (this.fq() case var $1?) {
          if (this.apply(this.rb) case (var $2 && var expr)?) {
            if (this.f12() case var $3?) {
              return ($0, $1, $2, $3);
            }
          }
        }
      }
      this._recover(_mark);
      if (this.apply(this.rb) case (var $0 && var sep)?) {
        if (this.fq() case var $1?) {
          if (this.apply(this.rb) case (var $2 && var expr)?) {
            if (this.f11() case var $3?) {
              return ($0, $1, $2, $3);
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
  Object? r9() {
    if (this._mark() case var _mark) {
      if (this.apply(this.r9) case var $0?) {
        if (this.f10() case _?) {
          return $0;
        }
      }
      this._recover(_mark);
      if (this.apply(this.r9) case var $0?) {
        if (this.f11() case _?) {
          return $0;
        }
      }
      this._recover(_mark);
      if (this.apply(this.r9) case var $0?) {
        if (this.f12() case _?) {
          return $0;
        }
      }
      this._recover(_mark);
      if (this.apply(this.ra) case var $?) {
        return $;
      }
    }
  }

  /// `global::prefix`
  Object? ra() {
    if (this._mark() case var _mark) {
      if (this.f9() case (var $0 && var min)?) {
        if (this.fq() case var $1?) {
          if (this.f9() case (var $2 && var max)?) {
            if (this.apply(this.rb) case (var $3 && var body)?) {
              return ($0, $1, $2, $3);
            }
          }
        }
      }
      this._recover(_mark);
      if (this.f9() case (var $0 && var min)?) {
        if (this.fq() case var $1?) {
          if (this.apply(this.rb) case (var $2 && var body)?) {
            return ($0, $1, $2);
          }
        }
      }
      this._recover(_mark);
      if (this.f9() case (var $0 && var number)?) {
        if (this.apply(this.rb) case (var $1 && var body)?) {
          return ($0, $1);
        }
      }
      this._recover(_mark);
      if (this.f21() case _?) {
        if (this.apply(this.ra) case var $1?) {
          return $1;
        }
      }
      this._recover(_mark);
      if (this.f22() case _?) {
        if (this.apply(this.ra) case var $1?) {
          return $1;
        }
      }
      this._recover(_mark);
      if (this.f23() case _?) {
        if (this.apply(this.ra) case var $1?) {
          return $1;
        }
      }
      this._recover(_mark);
      if (this.apply(this.rb) case var $?) {
        return $;
      }
    }
  }

  /// `global::atom`
  Object? rb() {
    if (this._mark() case var _mark) {
      if (this.fx() case _?) {
        if (this.f24() case var $1?) {
          return $1;
        }
      }
      this._recover(_mark);
      if (this.fr() case null) {
        this._recover(_mark);
        if (this.fs() case _?) {
          if (this.apply(this.r3) case (var $2 && var $)?) {
            if (this.ft() case _?) {
              return $2;
            }
          }
        }
      }

      this._recover(_mark);
      if (this.apply(this.r11)! case _) {
        if (this.matchPattern(_string.$70) case var $1?) {
          if (this.apply(this.r11)! case _) {
            return $1;
          }
        }
      }
      this._recover(_mark);
      if (this.apply(this.r11)! case _) {
        if (this.matchPattern(_string.$66) case var $1?) {
          if (this.apply(this.r11)! case _) {
            return $1;
          }
        }
      }
      this._recover(_mark);
      if (this.f15() case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.apply(this.r11)! case _) {
        if (this.matchPattern(_string.$71) case var $1?) {
          if (this.apply(this.r11)! case _) {
            return $1;
          }
        }
      }
      this._recover(_mark);
      if (this.fc() case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.fd() case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.fe() case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.ff() case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.fh() case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.fi() case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.fj() case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.fm() case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.fk() case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.fl() case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.fn() case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.fo() case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.fg() case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.apply(this.r11)! case _) {
        if (this.f2h() case var $1?) {
          if (this.apply(this.r11)! case _) {
            return $1;
          }
        }
      }
      this._recover(_mark);
      if (this.matchPattern(_string.$47) case _?) {
        if (this.f2l() case var $1?) {
          if (this.matchPattern(_string.$47) case _?) {
            return $1;
          }
        }
      }
      this._recover(_mark);
      if (this.apply(this.r11)! case _) {
        if (this.f3a() case var $1?) {
          if (this.apply(this.r11)! case _) {
            return $1;
          }
        }
      }
      this._recover(_mark);
      if (this.f6() case var $?) {
        return $;
      }
    }
  }

  /// `global::code::curly`
  Object rc() {
    if (this._mark() case var _mark) {
      if (this.f3f() case var _0) {
        if ([if (_0 case var _0?) _0] case var _l1) {
          if (_l1.isNotEmpty) {
            for (;;) {
              if (this._mark() case var _mark) {
                if (this.f3f() case var _0?) {
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
          return _l1;
        }
      }
    }
  }

  /// `global::code::nl`
  Object rd() {
    if (this._mark() case var _mark) {
      if (this.f3l() case var _0) {
        if ([if (_0 case var _0?) _0] case var _l1) {
          if (_l1.isNotEmpty) {
            for (;;) {
              if (this._mark() case var _mark) {
                if (this.f3l() case var _0?) {
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
          return _l1;
        }
      }
    }
  }

  /// `global::code::balanced`
  Object re() {
    if (this._mark() case var _mark) {
      if (this.f3r() case var _0) {
        if ([if (_0 case var _0?) _0] case var _l1) {
          if (_l1.isNotEmpty) {
            for (;;) {
              if (this._mark() case var _mark) {
                if (this.f3r() case var _0?) {
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
          return _l1;
        }
      }
    }
  }

  /// `global::dart::literal::string`
  Object? rf() {
    if (this.f3s() case var _0?) {
      if ([_0] case var _l1) {
        for (;;) {
          if (this._mark() case var _mark) {
            if (this.apply(this.r11)! case _) {
              if (this.f3s() case var _0?) {
                _l1.add(_0);
                continue;
              }
            }
            this._recover(_mark);
            break;
          }
        }
        return _l1;
      }
    }
  }

  /// `global::dart::literal::identifier`
  Object? rg() {
    if (this.f8() case var $?) {
      return $;
    }
  }

  /// `global::dart::literal::string::interpolation`
  Object? rh() {
    if (this._mark() case var _mark) {
      if (this.matchPattern(_string.$66) case var $0?) {
        if (this.matchPattern(_string.$22) case var $1?) {
          if (this.apply(this.ri)! case var $2) {
            if (this.matchPattern(_string.$21) case var $3?) {
              return ($0, $1, $2, $3);
            }
          }
        }
      }
      this._recover(_mark);
      if (this.matchPattern(_string.$66) case var $0?) {
        if (this.apply(this.rg) case var $1?) {
          return ($0, $1);
        }
      }
    }
  }

  /// `global::dart::literal::string::balanced`
  Object ri() {
    if (this._mark() case var _mark) {
      if (this.f3v() case var _0) {
        if ([if (_0 case var _0?) _0] case var _l1) {
          if (_l1.isNotEmpty) {
            for (;;) {
              if (this._mark() case var _mark) {
                if (this.f3v() case var _0?) {
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
          return _l1;
        }
      }
    }
  }

  /// `global::dart::type::main`
  Object? rj() {
    if (this.apply(this.r11)! case _) {
      if (this.apply(this.rk) case var $1?) {
        if (this.apply(this.r11)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::dart::type::nullable`
  Object? rk() {
    if (this.apply(this.rl) case (var $0 && var nonNullable)?) {
      if (this.f3w() case var $1) {
        return ($0, $1);
      }
    }
  }

  /// `global::dart::type::nonNullable`
  Object? rl() {
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
  Object? rm() {
    if (this.apply(this.rk) case (var $0 && var nullable)?) {
      if (this.apply(this.r11)! case var $1) {
        if (this.matchPattern(_string.$72) case var $2?) {
          if (this.apply(this.r11)! case var $3) {
            if (this.apply(this.ru) case (var $4 && var fnParameters)?) {
              return ($0, $1, $2, $3, $4);
            }
          }
        }
      }
    }
  }

  /// `global::dart::type::nonNullable::generic`
  Object? rn() {
    if (this.apply(this.rt) case (var $0 && var base)?) {
      if (this.fs() case var $1?) {
        if (this.f3x() case (var $2 && var args)?) {
          if (this.ft() case var $3?) {
            return ($0, $1, $2, $3);
          }
        }
      }
    }
  }

  /// `global::dart::type::nonNullable::record`
  Object? ro() {
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
  Object? rp() {
    if (this.fx() case var $0?) {
      if (this.apply(this.rx) case (var $1 && var positional)?) {
        if (this.f13() case var $2?) {
          if (this.apply(this.rw) case (var $3 && var named)?) {
            if (this.fw() case var $4?) {
              return ($0, $1, $2, $3, $4);
            }
          }
        }
      }
    }
  }

  /// `global::dart::type::nonNullable::record::onlyPositional`
  Object? rq() {
    if (this.fx() case var $0?) {
      if (this.apply(this.rx) case (var $1 && var positional)?) {
        if (this.f3y() case var $2) {
          if (this.fw() case var $3?) {
            return ($0, $1, $2, $3);
          }
        }
      }
    }
  }

  /// `global::dart::type::nonNullable::record::onlyNamed`
  Object? rr() {
    if (this.fx() case var $0?) {
      if (this.apply(this.rw) case (var $1 && var named)?) {
        if (this.fw() case var $2?) {
          return ($0, $1, $2);
        }
      }
    }
  }

  /// `global::dart::type::nonNullable::record::empty`
  Object? rs() {
    if (this.fx() case var $0?) {
      if (this.fw() case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `global::dart::type::nonNullable::base`
  Object? rt() {
    if (this.f8() case var _0?) {
      if ([_0] case var _l1) {
        for (;;) {
          if (this._mark() case var _mark) {
            if (this.f15() case _?) {
              if (this.f8() case var _0?) {
                _l1.add(_0);
                continue;
              }
            }
            this._recover(_mark);
            break;
          }
        }
        return _l1;
      }
    }
  }

  /// `global::dart::type::fnParameters`
  Object? ru() {
    if (this._mark() case var _mark) {
      if (this.fx() case var $0?) {
        if (this.apply(this.rx) case (var $1 && var positional)?) {
          if (this.f13() case var $2?) {
            if (this.apply(this.rw) case (var $3 && var named)?) {
              if (this.fw() case var $4?) {
                return ($0, $1, $2, $3, $4);
              }
            }
          }
        }
      }
      this._recover(_mark);
      if (this.fx() case var $0?) {
        if (this.apply(this.rx) case (var $1 && var positional)?) {
          if (this.f13() case var $2?) {
            if (this.apply(this.rv) case (var $3 && var optional)?) {
              if (this.fw() case var $4?) {
                return ($0, $1, $2, $3, $4);
              }
            }
          }
        }
      }
      this._recover(_mark);
      if (this.fx() case var $0?) {
        if (this.apply(this.rx) case (var $1 && var positional)?) {
          if (this.f3z() case var $2) {
            if (this.fw() case var $3?) {
              return ($0, $1, $2, $3);
            }
          }
        }
      }
      this._recover(_mark);
      if (this.fx() case var $0?) {
        if (this.apply(this.rw) case (var $1 && var named)?) {
          if (this.fw() case var $2?) {
            return ($0, $1, $2);
          }
        }
      }
      this._recover(_mark);
      if (this.fx() case var $0?) {
        if (this.apply(this.rv) case (var $1 && var optional)?) {
          if (this.fw() case var $2?) {
            return ($0, $1, $2);
          }
        }
      }
      this._recover(_mark);
      if (this.fx() case var $0?) {
        if (this.fw() case var $1?) {
          return ($0, $1);
        }
      }
    }
  }

  /// `global::dart::type::parameters::optional`
  Object? rv() {
    if (this.f40() case _?) {
      if (this.apply(this.rx) case (var $1 && var $)?) {
        if (this.f41() case _) {
          if (this.f42() case _?) {
            return $1;
          }
        }
      }
    }
  }

  /// `global::dart::type::parameters::named`
  Object? rw() {
    if (this.fv() case _?) {
      if (this.apply(this.ry) case (var $1 && var $)?) {
        if (this.f43() case _) {
          if (this.fu() case _?) {
            return $1;
          }
        }
      }
    }
  }

  /// `global::dart::type::fields::positional`
  Object? rx() {
    if (this.apply(this.rz) case (var $0 && var car)?) {
      if (this.f13() case var $1?) {
        if (this._mark() case var _mark) {
          if (this.apply(this.rz) case var _0) {
            if ([if (_0 case var _0?) _0] case (var $2 && var cdr && var _l1)) {
              if ($2.isNotEmpty) {
                for (;;) {
                  if (this._mark() case var _mark) {
                      if (this.f13() case _?) {
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
              return ($0, $1, $2);
            }
          }
        }
      }
    }
  }

  /// `global::dart::type::fields::named`
  Object? ry() {
    if (this.apply(this.r10) case var _0?) {
      if ([_0] case var _l1) {
        for (;;) {
          if (this._mark() case var _mark) {
            if (this.f13() case _?) {
              if (this.apply(this.r10) case var _0?) {
                _l1.add(_0);
                continue;
              }
            }
            this._recover(_mark);
            break;
          }
        }
        return _l1;
      }
    }
  }

  /// `global::dart::type::field::positional`
  Object? rz() {
    if (this.f4() case var $0?) {
      if (this.apply(this.r11)! case var $1) {
        if (this.f44() case var $2) {
          return ($0, $1, $2);
        }
      }
    }
  }

  /// `global::dart::type::field::named`
  Object? r10() {
    if (this.f4() case var $0?) {
      if (this.apply(this.r11)! case var $1) {
        if (this.f8() case var $2?) {
          return ($0, $1, $2);
        }
      }
    }
  }

  /// `global::_`
  Object r11() {
    if (this._mark() case var _mark) {
      if (this.f46() case var _0) {
        if ([if (_0 case var _0?) _0] case var _l1) {
          if (_l1.isNotEmpty) {
            for (;;) {
              if (this._mark() case var _mark) {
                if (this.f46() case var _0?) {
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
          return _l1;
        }
      }
    }
  }

  /// `global::whitespace`
  Object? r12() {
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
        return _l1;
      }
    }
  }

  /// `global::comment`
  Object? r13() {
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
  Object? r14() {
    if (this.matchPattern(_string.$73) case var $0?) {
      if (this._mark() case var _mark) {
        if (this.f47() case var _0) {
          if ([if (_0 case var _0?) _0] case (var $1 && var _l1)) {
            if (_l1.isNotEmpty) {
              for (;;) {
                if (this._mark() case var _mark) {
                  if (this.f47() case var _0?) {
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
            return ($0, $1);
          }
        }
      }
    }
  }

  /// `global::comment::multi`
  Object? r15() {
    if (this.matchPattern(_string.$74) case var $0?) {
      if (this._mark() case var _mark) {
        if (this.f48() case var _0) {
          if ([if (_0 case var _0?) _0] case (var $1 && var _l1)) {
            if (_l1.isNotEmpty) {
              for (;;) {
                if (this._mark() case var _mark) {
                  if (this.f48() case var _0?) {
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
            if (this.matchPattern(_string.$52) case var $2?) {
              return ($0, $1, $2);
            }
          }
        }
      }
    }
  }

  /// `global::newlineOrEof`
  Object? r16() {
    if (this._mark() case var _mark) {
      if (this.f49() case var $0) {
        if (this.matchPattern(_regexp.$2) case var $1?) {
          if (this.f4a() case var $2) {
            return ($0, $1, $2);
          }
        }
      }
      this._recover(_mark);
      if (this.pos case var $ when this.pos >= this.buffer.length) {
        return $;
      }
    }
  }

}
class _regexp {
  /// `/\d/`
  static final $1 = RegExp("\\d");
  /// `/\n/`
  static final $2 = RegExp("\\n");
  /// `/\r/`
  static final $3 = RegExp("\\r");
  /// `/\s/`
  static final $4 = RegExp("\\s");
}
class _string {
  /// `"0"`
  static const $1 = "0";
  /// `"1"`
  static const $2 = "1";
  /// `"2"`
  static const $3 = "2";
  /// `"3"`
  static const $4 = "3";
  /// `"4"`
  static const $5 = "4";
  /// `"5"`
  static const $6 = "5";
  /// `"6"`
  static const $7 = "6";
  /// `"7"`
  static const $8 = "7";
  /// `"8"`
  static const $9 = "8";
  /// `"9"`
  static const $10 = "9";
  /// `"\\"`
  static const $11 = "\\";
  /// `"]"`
  static const $12 = "]";
  /// `"@rule"`
  static const $13 = "@rule";
  /// `"@fragment"`
  static const $14 = "@fragment";
  /// `"@inline"`
  static const $15 = "@inline";
  /// `"choice!"`
  static const $16 = "choice!";
  /// `".."`
  static const $17 = "..";
  /// `"<~"`
  static const $18 = "<~";
  /// `"<"`
  static const $19 = "<";
  /// `">"`
  static const $20 = ">";
  /// `"}"`
  static const $21 = "}";
  /// `"{"`
  static const $22 = "{";
  /// `")"`
  static const $23 = ")";
  /// `"("`
  static const $24 = "(";
  /// `";"`
  static const $25 = ";";
  /// `"="`
  static const $26 = "=";
  /// `"?"`
  static const $27 = "?";
  /// `"*"`
  static const $28 = "*";
  /// `"+"`
  static const $29 = "+";
  /// `","`
  static const $30 = ",";
  /// `"|"`
  static const $31 = "|";
  /// `"."`
  static const $32 = ".";
  /// `"\"\"\""`
  static const $33 = "\"\"\"";
  /// `"r"`
  static const $34 = "r";
  /// `"'''"`
  static const $35 = "'''";
  /// `"\""`
  static const $36 = "\"";
  /// `"'"`
  static const $37 = "'";
  /// `"-"`
  static const $38 = "-";
  /// `"|>"`
  static const $39 = "|>";
  /// `"@"`
  static const $40 = "@";
  /// `"~>"`
  static const $41 = "~>";
  /// `"~"`
  static const $42 = "~";
  /// `"&"`
  static const $43 = "&";
  /// `"!"`
  static const $44 = "!";
  /// `" "`
  static const $45 = " ";
  /// `"["`
  static const $46 = "[";
  /// `"/"`
  static const $47 = "/";
  /// `"r\"\"\""`
  static const $48 = "r\"\"\"";
  /// `"r'''"`
  static const $49 = "r'''";
  /// `"r\""`
  static const $50 = "r\"";
  /// `"r'"`
  static const $51 = "r'";
  /// `"*/"`
  static const $52 = "*/";
  /// `"`"`
  static const $53 = "`";
  /// `"::"`
  static const $54 = "::";
  /// `"d"`
  static const $55 = "d";
  /// `"w"`
  static const $56 = "w";
  /// `"s"`
  static const $57 = "s";
  /// `"b"`
  static const $58 = "b";
  /// `"D"`
  static const $59 = "D";
  /// `"W"`
  static const $60 = "W";
  /// `"S"`
  static const $61 = "S";
  /// `"n"`
  static const $62 = "n";
  /// `"t"`
  static const $63 = "t";
  /// `"f"`
  static const $64 = "f";
  /// `"v"`
  static const $65 = "v";
  /// `"\$"`
  static const $66 = "\$";
  /// `"E"`
  static const $67 = "E";
  /// `"e"`
  static const $68 = "e";
  /// `":"`
  static const $69 = ":";
  /// `"^"`
  static const $70 = "^";
  /// `"ε"`
  static const $71 = "ε";
  /// `"Function"`
  static const $72 = "Function";
  /// `"//"`
  static const $73 = "//";
  /// `"/*"`
  static const $74 = "/*";
}
class _range {
  /// `[a-zA-Z0-9_$]`
  static const $1 = { (97, 122), (65, 90), (48, 57), (95, 95), (36, 36) };
  /// `[a-zA-Z_$]`
  static const $2 = { (97, 122), (65, 90), (95, 95), (36, 36) };
}
