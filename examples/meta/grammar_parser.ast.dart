// ignore_for_file: type=lint, body_might_complete_normally_nullable, unused_local_variable, inference_failure_on_function_return_type, unused_import, duplicate_ignore, unused_element, collection_methods_unrelated_type, unused_element, use_setters_to_change_properties

// imports
// ignore_for_file: avoid_positional_boolean_parameters, unnecessary_this, collection_methods_unrelated_type, unused_element, use_setters_to_change_properties

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

  _Mark _mark() {
    return _Mark(false, this.pos);
  }

  void _recover(_Mark mark) {
    this.pos = mark.pos;
    mark.isCut = false;
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
  T? nullable() => this;
}

typedef _Rule<T extends Object> = T? Function();

class _Mark {
  _Mark(this.isCut, this.pos);

  bool isCut;
  final int pos;
}

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
final class GrammarParser extends _PegParser<Object> {
  GrammarParser();

  @override
  get start => r0;


  /// `global::literal::regexp`
  Object? f0() {
    if (this.matchPattern(_string.$1) case _?) {
      if (this.f3n() case var $1?) {
        if (this.matchPattern(_string.$1) case _?) {
          return $1;
        }
      }
    }
  }

  /// `global::literal::string`
  Object? f1() {
    if (this.apply(this.r16)! case _) {
      if (this.f3w() case var $1?) {
        if (this.apply(this.r16)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::literal::range`
  Object? f2() {
    if (this.apply(this.r16)! case _) {
      if (this.f3y() case var $1?) {
        if (this.apply(this.r16)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::literal::range::element`
  Object? f3() {
    var _mark = this._mark();
    if (this.matchPattern(_string.$2) case var $?) {
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
    if (this.fk() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.fl() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.fm() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.fc() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.f4() case (var $0 && var l)?) {
      if (this.matchPattern(_string.$3) case var $1?) {
        if (this.f4() case (var $2 && var r)?) {
          return ($0, $1, $2);
        }
      }
    }
    this._recover(_mark);
    if (this.f4() case var $?) {
      return $;
    }
  }

  /// `global::literal::range::atom`
  Object? f4() {
    var _mark = this._mark();
    if (this.matchPattern(_string.$4) case _?) {
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $1) {
          return $1;
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$5) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  }

  /// `global::literal::raw`
  Object? f5() {
    if (this.matchPattern(_string.$6) case _?) {
      var _mark = this._mark();
        if (this.f3z() case var _0) {
          if ([if (_0 case var _0?) _0] case (var $1 && var _l1)) {
            if (_l1.isNotEmpty) {
              for (;;) {
                var _mark = this._mark();
                if (this.f3z() case var _0?) {
                  _l1.add(_0);
                  continue;
                }
                this._recover(_mark);
                break;
              }
            } else {
              this._recover(_mark);
            }
            if (this.matchPattern(_string.$6) case _?) {
              return $1;
            }
          }
        }
    }
  }

  /// `global::identifier`
  Object? f6() {
    if (this.matchRange(_range.$2) case var $0?) {
      var _mark = this._mark();
      if (this.matchRange(_range.$1) case var _0) {
        if ([if (_0 case var _0?) _0] case (var $1 && var _l1)) {
          if ($1.isNotEmpty) {
            for (;;) {
              var _mark = this._mark();
                if ('' case _) {
                  if (this.matchRange(_range.$1) case var _0?) {
                    _l1.add(_0);
                    continue;
                  }
                }
              this._recover(_mark);
              break;
            }
          } else {
            this._recover(_mark);
          }
          return ($0, $1);
        }
      }
    }
  }

  /// `global::raw`
  Object? f7() {
    if (this.matchPattern(_string.$6) case _?) {
      if (this.f41() case var $1) {
        if (this.matchPattern(_string.$6) case _?) {
          return $1;
        }
      }
    }
  }

  /// `global::number`
  Object? f8() {
    if (this.matchPattern(_regexp.$1) case var _0?) {
      if ([_0] case var _l1) {
        for (;;) {
          var _mark = this._mark();
          if (this.matchPattern(_regexp.$1) case var _0?) {
            _l1.add(_0);
            continue;
          }
          this._recover(_mark);
          break;
        }
        return _l1;
      }
    }
  }

  /// `global::kw::decorator`
  Object? f9() {
    var _mark = this._mark();
    if (this.apply(this.r16)! case var $0) {
      if (this.matchPattern(_string.$7) case var $1?) {
        if (this.apply(this.r16)! case var $2) {
          return ($0, $1, $2);
        }
      }
    }
    this._recover(_mark);
    if (this.apply(this.r16)! case var $0) {
      if (this.matchPattern(_string.$8) case var $1?) {
        if (this.apply(this.r16)! case var $2) {
          return ($0, $1, $2);
        }
      }
    }
    this._recover(_mark);
    if (this.apply(this.r16)! case var $0) {
      if (this.matchPattern(_string.$9) case var $1?) {
        if (this.apply(this.r16)! case var $2) {
          return ($0, $1, $2);
        }
      }
    }
  }

  /// `global::mac`
  Object? fa() {
    var _mark = this._mark();
    if (this.fb() case var $?) {
      return $;
    }
  }

  /// `global::mac::choice`
  Object? fb() {
    if (this.apply(this.r16)! case _) {
      if (this.matchPattern(_string.$10) case var $1?) {
        if (this.apply(this.r16)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::regexEscape::backslash`
  Object? fc() {
    if (this.apply(this.r16)! case _) {
      if (this.f43() case var $1?) {
        return $1;
      }
    }
  }

  /// `global::regexEscape::digit`
  Object? fd() {
    if (this.apply(this.r16)! case _) {
      if (this.f44() case (var $1 && var $)?) {
        if (this.apply(this.r16)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::regexEscape::word`
  Object? fe() {
    if (this.apply(this.r16)! case _) {
      if (this.f45() case (var $1 && var $)?) {
        if (this.apply(this.r16)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::regexEscape::whitespace`
  Object? ff() {
    if (this.apply(this.r16)! case _) {
      if (this.f46() case (var $1 && var $)?) {
        if (this.apply(this.r16)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::regexEscape::wordBoundary`
  Object? fg() {
    if (this.apply(this.r16)! case _) {
      if (this.f47() case (var $1 && var $)?) {
        if (this.apply(this.r16)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::regexEscape::notDigit`
  Object? fh() {
    if (this.apply(this.r16)! case _) {
      if (this.f48() case (var $1 && var $)?) {
        if (this.apply(this.r16)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::regexEscape::notWord`
  Object? fi() {
    if (this.apply(this.r16)! case _) {
      if (this.f49() case (var $1 && var $)?) {
        if (this.apply(this.r16)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::regexEscape::notWhitespace`
  Object? fj() {
    if (this.apply(this.r16)! case _) {
      if (this.f4a() case (var $1 && var $)?) {
        if (this.apply(this.r16)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::regexEscape::newline`
  Object? fk() {
    if (this.apply(this.r16)! case _) {
      if (this.f4b() case (var $1 && var $)?) {
        if (this.apply(this.r16)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::regexEscape::carriageReturn`
  Object? fl() {
    if (this.apply(this.r16)! case _) {
      if (this.f4c() case (var $1 && var $)?) {
        if (this.apply(this.r16)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::regexEscape::tab`
  Object? fm() {
    if (this.apply(this.r16)! case _) {
      if (this.f4d() case (var $1 && var $)?) {
        if (this.apply(this.r16)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::regexEscape::formFeed`
  Object? fn() {
    if (this.apply(this.r16)! case _) {
      if (this.f4e() case (var $1 && var $)?) {
        if (this.apply(this.r16)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::regexEscape::verticalTab`
  Object? fo() {
    if (this.apply(this.r16)! case _) {
      if (this.f4f() case (var $1 && var $)?) {
        if (this.apply(this.r16)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::CHOICE_OP`
  Object? fp() {
    if (this.f1e() case var $0?) {
      if (this.f4g() case var $1) {
        return ($0, $1);
      }
    }
  }

  /// `global::#`
  Object? fq() {
    if (this.apply(this.r16)! case _) {
      if (this.matchPattern(_string.$11) case var $1?) {
        if (this.apply(this.r16)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::..`
  Object? fr() {
    if (this.apply(this.r16)! case _) {
      if (this.matchPattern(_string.$12) case var $1?) {
        if (this.apply(this.r16)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::~>`
  Object? fs() {
    if (this.apply(this.r16)! case _) {
      if (this.matchPattern(_string.$13) case var $1?) {
        if (this.apply(this.r16)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::<~`
  Object? ft() {
    if (this.apply(this.r16)! case _) {
      if (this.matchPattern(_string.$14) case var $1?) {
        if (this.apply(this.r16)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::|>`
  Object? fu() {
    if (this.apply(this.r16)! case _) {
      if (this.matchPattern(_string.$15) case var $1?) {
        if (this.apply(this.r16)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::%`
  Object? fv() {
    if (this.apply(this.r16)! case _) {
      if (this.matchPattern(_string.$16) case var $1?) {
        if (this.apply(this.r16)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::@`
  Object? fw() {
    if (this.apply(this.r16)! case _) {
      if (this.matchPattern(_string.$17) case var $1?) {
        if (this.apply(this.r16)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::<`
  Object? fx() {
    if (this.apply(this.r16)! case _) {
      if (this.matchPattern(_string.$18) case var $1?) {
        if (this.apply(this.r16)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::>`
  Object? fy() {
    if (this.apply(this.r16)! case _) {
      if (this.matchPattern(_string.$19) case var $1?) {
        if (this.apply(this.r16)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::]`
  Object? fz() {
    if (this.apply(this.r16)! case _) {
      if (this.matchPattern(_string.$5) case var $1?) {
        if (this.apply(this.r16)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::[`
  Object? f10() {
    if (this.apply(this.r16)! case _) {
      if (this.matchPattern(_string.$20) case var $1?) {
        if (this.apply(this.r16)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::}`
  Object? f11() {
    if (this.apply(this.r16)! case _) {
      if (this.matchPattern(_string.$21) case var $1?) {
        if (this.apply(this.r16)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::{`
  Object? f12() {
    if (this.apply(this.r16)! case _) {
      if (this.matchPattern(_string.$22) case var $1?) {
        if (this.apply(this.r16)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::)`
  Object? f13() {
    if (this.apply(this.r16)! case _) {
      if (this.matchPattern(_string.$23) case var $1?) {
        if (this.apply(this.r16)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::(`
  Object? f14() {
    if (this.apply(this.r16)! case _) {
      if (this.matchPattern(_string.$24) case var $1?) {
        if (this.apply(this.r16)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::;`
  Object? f15() {
    if (this.apply(this.r16)! case _) {
      if (this.matchPattern(_string.$25) case var $1?) {
        if (this.apply(this.r16)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::=`
  Object? f16() {
    if (this.apply(this.r16)! case _) {
      if (this.matchPattern(_string.$26) case var $1?) {
        if (this.apply(this.r16)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::?`
  Object? f17() {
    if (this.apply(this.r16)! case _) {
      if (this.matchPattern(_string.$27) case var $1?) {
        if (this.apply(this.r16)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::!`
  Object? f18() {
    if (this.apply(this.r16)! case _) {
      if (this.matchPattern(_string.$28) case var $1?) {
        if (this.apply(this.r16)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::~`
  Object? f19() {
    if (this.apply(this.r16)! case _) {
      if (this.matchPattern(_string.$29) case var $1?) {
        if (this.apply(this.r16)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::&`
  Object? f1a() {
    if (this.apply(this.r16)! case _) {
      if (this.matchPattern(_string.$30) case var $1?) {
        if (this.apply(this.r16)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::*`
  Object? f1b() {
    if (this.apply(this.r16)! case _) {
      if (this.matchPattern(_string.$31) case var $1?) {
        if (this.apply(this.r16)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::+`
  Object? f1c() {
    if (this.apply(this.r16)! case _) {
      if (this.matchPattern(_string.$32) case var $1?) {
        if (this.apply(this.r16)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::,`
  Object? f1d() {
    if (this.apply(this.r16)! case _) {
      if (this.matchPattern(_string.$33) case var $1?) {
        if (this.apply(this.r16)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::|`
  Object? f1e() {
    if (this.apply(this.r16)! case _) {
      if (this.matchPattern(_string.$34) case var $1?) {
        if (this.apply(this.r16)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::.`
  Object? f1f() {
    if (this.apply(this.r16)! case _) {
      if (this.matchPattern(_string.$35) case var $1?) {
        if (this.apply(this.r16)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::ε`
  Object? f1g() {
    if (this.apply(this.r16)! case _) {
      if (this.matchPattern(_string.$36) case var $1?) {
        if (this.apply(this.r16)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::^`
  Object? f1h() {
    if (this.apply(this.r16)! case _) {
      if (this.matchPattern(_string.$37) case var $1?) {
        if (this.apply(this.r16)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::$`
  Object? f1i() {
    if (this.apply(this.r16)! case _) {
      if (this.matchPattern(_string.$38) case var $1?) {
        if (this.apply(this.r16)! case _) {
          return $1;
        }
      }
    }
  }

  /// `ROOT`
  Object? f1j() {
    if (this.apply(this.r0) case var $?) {
      return $;
    }
  }

  /// `global::untypedMacroChoice`
  Object? f1k() {
    if (this.f4h() case (var $0 && var outer_decorator)) {
      if (this.f6() case (var $1 && var name)?) {
        if (this.f16() case var $2?) {
          if (this.fb() case var $3?) {
            if (this.f4i() case (var $4 && var inner_decorator)) {
              if (this.f12() case var $5?) {
                if (this.apply(this.r2) case var _0?) {
                  if ([_0] case (var $6 && var statements && var _l1)) {
                    for (;;) {
                      var _mark = this._mark();
                      if (this.apply(this.r16)! case _) {
                        if (this.apply(this.r2) case var _0?) {
                          _l1.add(_0);
                          continue;
                        }
                      }
                      this._recover(_mark);
                      break;
                    }
                    if (this.f11() case var $7?) {
                      if (this.f4j() case var $8) {
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
  }

  /// `global::typedMacroChoice`
  Object? f1l() {
    if (this.f4k() case (var $0 && var outer_decorator)) {
      if (this.apply(this.r11) case (var $1 && var type)?) {
        if (this.f6() case (var $2 && var name)?) {
          if (this.f16() case var $3?) {
            if (this.fb() case var $4?) {
              if (this.f4l() case (var $5 && var inner_decorator)) {
                if (this.f12() case var $6?) {
                  if (this.apply(this.r2) case var _0?) {
                    if ([_0] case (var $7 && var statements && var _l1)) {
                      for (;;) {
                        var _mark = this._mark();
                        if (this.apply(this.r16)! case _) {
                          if (this.apply(this.r2) case var _0?) {
                            _l1.add(_0);
                            continue;
                          }
                        }
                        this._recover(_mark);
                        break;
                      }
                      if (this.f11() case var $8?) {
                        if (this.f4m() case var $9) {
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
  }

  /// `global::dart::literal::string::body`
  Object? f1m() {
    var _mark = this._mark();
    if (this.matchPattern(_string.$40) case var _2?) {
      if ([_2].nullable() case var _l3) {
        if (_l3 != null) {
          while (_l3.length < 1) {
            var _mark = this._mark();
            if (this.matchPattern(_string.$40) case var _2?) {
              _l3.add(_2);
              continue;
            }
            this._recover(_mark);
            break;
          }
          if (_l3.length < 1) {
            _l3 = null;
          }
        }
        if (_l3 case var $0?) {
          if (this.matchPattern(_string.$39) case var $1?) {
            var _mark = this._mark();
              if (this.f4n() case var _0) {
                if ([if (_0 case var _0?) _0] case (var $2 && var _l1)) {
                  if (_l1.isNotEmpty) {
                    for (;;) {
                      var _mark = this._mark();
                      if (this.f4n() case var _0?) {
                        _l1.add(_0);
                        continue;
                      }
                      this._recover(_mark);
                      break;
                    }
                  } else {
                    this._recover(_mark);
                  }
                  if (this.matchPattern(_string.$39) case var $3?) {
                    return ($0, $1, $2, $3);
                  }
                }
              }
          }
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$40) case var _6?) {
      if ([_6].nullable() case var _l7) {
        if (_l7 != null) {
          while (_l7.length < 1) {
            var _mark = this._mark();
            if (this.matchPattern(_string.$40) case var _6?) {
              _l7.add(_6);
              continue;
            }
            this._recover(_mark);
            break;
          }
          if (_l7.length < 1) {
            _l7 = null;
          }
        }
        if (_l7 case var $0?) {
          if (this.matchPattern(_string.$41) case var $1?) {
            var _mark = this._mark();
              if (this.f4o() case var _4) {
                if ([if (_4 case var _4?) _4] case (var $2 && var _l5)) {
                  if (_l5.isNotEmpty) {
                    for (;;) {
                      var _mark = this._mark();
                      if (this.f4o() case var _4?) {
                        _l5.add(_4);
                        continue;
                      }
                      this._recover(_mark);
                      break;
                    }
                  } else {
                    this._recover(_mark);
                  }
                  if (this.matchPattern(_string.$41) case var $3?) {
                    return ($0, $1, $2, $3);
                  }
                }
              }
          }
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$40) case var _10?) {
      if ([_10].nullable() case var _l11) {
        if (_l11 != null) {
          while (_l11.length < 1) {
            var _mark = this._mark();
            if (this.matchPattern(_string.$40) case var _10?) {
              _l11.add(_10);
              continue;
            }
            this._recover(_mark);
            break;
          }
          if (_l11.length < 1) {
            _l11 = null;
          }
        }
        if (_l11 case var $0?) {
          if (this.matchPattern(_string.$42) case var $1?) {
            var _mark = this._mark();
              if (this.f4p() case var _8) {
                if ([if (_8 case var _8?) _8] case (var $2 && var _l9)) {
                  if (_l9.isNotEmpty) {
                    for (;;) {
                      var _mark = this._mark();
                      if (this.f4p() case var _8?) {
                        _l9.add(_8);
                        continue;
                      }
                      this._recover(_mark);
                      break;
                    }
                  } else {
                    this._recover(_mark);
                  }
                  if (this.matchPattern(_string.$42) case var $3?) {
                    return ($0, $1, $2, $3);
                  }
                }
              }
          }
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$40) case var _14?) {
      if ([_14].nullable() case var _l15) {
        if (_l15 != null) {
          while (_l15.length < 1) {
            var _mark = this._mark();
            if (this.matchPattern(_string.$40) case var _14?) {
              _l15.add(_14);
              continue;
            }
            this._recover(_mark);
            break;
          }
          if (_l15.length < 1) {
            _l15 = null;
          }
        }
        if (_l15 case var $0?) {
          if (this.matchPattern(_string.$43) case var $1?) {
            var _mark = this._mark();
              if (this.f4q() case var _12) {
                if ([if (_12 case var _12?) _12] case (var $2 && var _l13)) {
                  if (_l13.isNotEmpty) {
                    for (;;) {
                      var _mark = this._mark();
                      if (this.f4q() case var _12?) {
                        _l13.add(_12);
                        continue;
                      }
                      this._recover(_mark);
                      break;
                    }
                  } else {
                    this._recover(_mark);
                  }
                  if (this.matchPattern(_string.$43) case var $3?) {
                    return ($0, $1, $2, $3);
                  }
                }
              }
          }
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$39) case var $0?) {
      var _mark = this._mark();
        if (this.f4r() case var _16) {
          if ([if (_16 case var _16?) _16] case (var $1 && var _l17)) {
            if (_l17.isNotEmpty) {
              for (;;) {
                var _mark = this._mark();
                if (this.f4r() case var _16?) {
                  _l17.add(_16);
                  continue;
                }
                this._recover(_mark);
                break;
              }
            } else {
              this._recover(_mark);
            }
            if (this.matchPattern(_string.$39) case var $2?) {
              return ($0, $1, $2);
            }
          }
        }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$41) case var $0?) {
      var _mark = this._mark();
        if (this.f4s() case var _18) {
          if ([if (_18 case var _18?) _18] case (var $1 && var _l19)) {
            if (_l19.isNotEmpty) {
              for (;;) {
                var _mark = this._mark();
                if (this.f4s() case var _18?) {
                  _l19.add(_18);
                  continue;
                }
                this._recover(_mark);
                break;
              }
            } else {
              this._recover(_mark);
            }
            if (this.matchPattern(_string.$41) case var $2?) {
              return ($0, $1, $2);
            }
          }
        }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$42) case var $0?) {
      var _mark = this._mark();
        if (this.f4t() case var _20) {
          if ([if (_20 case var _20?) _20] case (var $1 && var _l21)) {
            if (_l21.isNotEmpty) {
              for (;;) {
                var _mark = this._mark();
                if (this.f4t() case var _20?) {
                  _l21.add(_20);
                  continue;
                }
                this._recover(_mark);
                break;
              }
            } else {
              this._recover(_mark);
            }
            if (this.matchPattern(_string.$42) case var $2?) {
              return ($0, $1, $2);
            }
          }
        }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$43) case var $0?) {
      var _mark = this._mark();
        if (this.f4u() case var _22) {
          if ([if (_22 case var _22?) _22] case (var $1 && var _l23)) {
            if (_l23.isNotEmpty) {
              for (;;) {
                var _mark = this._mark();
                if (this.f4u() case var _22?) {
                  _l23.add(_22);
                  continue;
                }
                this._recover(_mark);
                break;
              }
            } else {
              this._recover(_mark);
            }
            if (this.matchPattern(_string.$43) case var $2?) {
              return ($0, $1, $2);
            }
          }
        }
    }
  }

  /// `fragment0`
  Object? f1n() {
    if (this.apply(this.r1) case var $?) {
      return $;
    }
  }

  /// `fragment1`
  Object f1o() {
    if (this.apply(this.r16)! case var $) {
      return $;
    }
  }

  /// `fragment2`
  Object? f1p() {
    if (this.f9() case var $?) {
      return $;
    }
  }

  /// `fragment3`
  Object? f1q() {
    if (this.apply(this.r11) case var $?) {
      return $;
    }
  }

  /// `fragment4`
  Object? f1r() {
    if (this.f9() case var $?) {
      return $;
    }
  }

  /// `fragment5`
  Object? f1s() {
    if (this.f15() case var $?) {
      return $;
    }
  }

  /// `fragment6`
  Object? f1t() {
    if (this.f9() case var $?) {
      return $;
    }
  }

  /// `fragment7`
  Object? f1u() {
    if (this.f6() case var $?) {
      return $;
    }
  }

  /// `fragment8`
  Object? f1v() {
    if (this.f9() case var $?) {
      return $;
    }
  }

  /// `fragment9`
  Object? f1w() {
    if (this.apply(this.r11) case var $?) {
      return $;
    }
  }

  /// `fragment10`
  Object? f1x() {
    if (this.f9() case var $?) {
      return $;
    }
  }

  /// `fragment11`
  Object? f1y() {
    if (this.f16() case _?) {
      if (this.apply(this.r3) case (var $1 && var choice)?) {
        if (this.f15() case _?) {
          return $1;
        }
      }
    }
  }

  /// `fragment12`
  Object? f1z() {
    if (this.f9() case var $?) {
      return $;
    }
  }

  /// `fragment13`
  Object? f20() {
    if (this.f16() case _?) {
      if (this.apply(this.r3) case (var $1 && var choice)?) {
        if (this.f15() case _?) {
          return $1;
        }
      }
    }
  }

  /// `fragment14`
  Object? f21() {
    if (this.fp() case var $?) {
      return $;
    }
  }

  /// `fragment15`
  Object? f22() {
    if (this.apply(this.r16)! case _) {
      if (this.matchPattern(_string.$15) case var $1?) {
        if (this.apply(this.r16)! case _) {
          return $1;
        }
      }
    }
  }

  /// `fragment16`
  Object? f23() {
    if (this.apply(this.r16)! case _) {
      if (this.matchPattern(_string.$17) case var $1?) {
        if (this.apply(this.r16)! case _) {
          return $1;
        }
      }
    }
  }

  /// `fragment17`
  Object? f24() {
    if (this.f23() case _?) {
      if (this.f8() case var $1?) {
        return $1;
      }
    }
  }

  /// `fragment18`
  Object? f25() {
    if (this.apply(this.r16)! case _) {
      if (this.matchPattern(_string.$13) case var $1?) {
        if (this.apply(this.r16)! case _) {
          return $1;
        }
      }
    }
  }

  /// `fragment19`
  Object? f26() {
    if (this.apply(this.r16)! case _) {
      if (this.matchPattern(_string.$29) case var $1?) {
        if (this.apply(this.r16)! case _) {
          return $1;
        }
      }
    }
  }

  /// `fragment20`
  Object? f27() {
    if (this.apply(this.r16)! case _) {
      if (this.matchPattern(_string.$30) case var $1?) {
        if (this.apply(this.r16)! case _) {
          return $1;
        }
      }
    }
  }

  /// `fragment21`
  Object? f28() {
    if (this.apply(this.r16)! case _) {
      if (this.matchPattern(_string.$28) case var $1?) {
        if (this.apply(this.r16)! case _) {
          return $1;
        }
      }
    }
  }

  /// `fragment22`
  Object? f29() {
    if (this.matchPattern(_string.$4) case var $0?) {
      if (this.matchPattern(_string.$44) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `fragment23`
  Object? f2a() {
    if (this.matchPattern(_string.$4) case var $0?) {
      if (this.matchPattern(_string.$45) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `fragment24`
  Object? f2b() {
    if (this.matchPattern(_string.$4) case var $0?) {
      if (this.matchPattern(_string.$46) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `fragment25`
  Object? f2c() {
    if (this.matchPattern(_string.$4) case var $0?) {
      if (this.matchPattern(_string.$47) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `fragment26`
  Object? f2d() {
    if (this.matchPattern(_string.$4) case var $0?) {
      if (this.matchPattern(_string.$48) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `fragment27`
  Object? f2e() {
    if (this.matchPattern(_string.$4) case var $0?) {
      if (this.matchPattern(_string.$49) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `fragment28`
  Object? f2f() {
    var _mark = this._mark();
    if (this.matchPattern(_string.$2) case var $?) {
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
    if (this.fk() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.fl() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.fm() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.fc() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.f4() case (var $0 && var l)?) {
      if (this.matchPattern(_string.$3) case var $1?) {
        if (this.f4() case (var $2 && var r)?) {
          return ($0, $1, $2);
        }
      }
    }
    this._recover(_mark);
    if (this.f4() case var $?) {
      return $;
    }
  }

  /// `fragment29`
  Object? f2g() {
    if (this.matchPattern(_string.$20) case _?) {
      if (this.f2f() case var _0?) {
        if ([_0] case (var $1 && var elements && var _l1)) {
          for (;;) {
            var _mark = this._mark();
            if (this.apply(this.r16)! case _) {
              if (this.f2f() case var _0?) {
                _l1.add(_0);
                continue;
              }
            }
            this._recover(_mark);
            break;
          }
          if (this.matchPattern(_string.$5) case _?) {
            return $1;
          }
        }
      }
    }
  }

  /// `fragment30`
  Object? f2h() {
    var _mark = this._mark();
    if (this.matchPattern(_string.$4) case _?) {
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $1) {
          return $1;
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$1) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  }

  /// `fragment31`
  Object? f2i() {
    if (this.f2h() case var _0?) {
      if ([_0] case var _l1) {
        for (;;) {
          var _mark = this._mark();
          if (this.f2h() case var _0?) {
            _l1.add(_0);
            continue;
          }
          this._recover(_mark);
          break;
        }
        return _l1;
      }
    }
  }

  /// `fragment32`
  Object? f2j() {
    var _mark = this._mark();
    if (this.matchPattern(_string.$39) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  }

  /// `fragment33`
  Object? f2k() {
    var _mark = this._mark();
    if (this.matchPattern(_string.$41) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  }

  /// `fragment34`
  Object? f2l() {
    var _mark = this._mark();
    if (this.matchPattern(_string.$42) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  }

  /// `fragment35`
  Object? f2m() {
    var _mark = this._mark();
    if (this.matchPattern(_string.$43) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  }

  /// `fragment36`
  Object? f2n() {
    var _mark = this._mark();
    if (this.matchPattern(_string.$4) case var $0?) {
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $1) {
          return ($0, $1);
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$39) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  }

  /// `fragment37`
  Object? f2o() {
    var _mark = this._mark();
    if (this.matchPattern(_string.$4) case var $0?) {
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $1) {
          return ($0, $1);
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
  }

  /// `fragment38`
  Object? f2p() {
    var _mark = this._mark();
    if (this.matchPattern(_string.$4) case var $0?) {
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $1) {
          return ($0, $1);
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$42) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  }

  /// `fragment39`
  Object? f2q() {
    var _mark = this._mark();
    if (this.matchPattern(_string.$4) case var $0?) {
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $1) {
          return ($0, $1);
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$43) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  }

  /// `fragment40`
  Object? f2r() {
    var _mark = this._mark();
    if (this.matchPattern(_string.$50) case _?) {
      var _mark = this._mark();
        if (this.f2j() case var _0) {
          if ([if (_0 case var _0?) _0] case (var $1 && var _l1)) {
            if (_l1.isNotEmpty) {
              for (;;) {
                var _mark = this._mark();
                if (this.f2j() case var _0?) {
                  _l1.add(_0);
                  continue;
                }
                this._recover(_mark);
                break;
              }
            } else {
              this._recover(_mark);
            }
            if (this.matchPattern(_string.$39) case _?) {
              return $1;
            }
          }
        }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$51) case _?) {
      var _mark = this._mark();
        if (this.f2k() case var _2) {
          if ([if (_2 case var _2?) _2] case (var $1 && var _l3)) {
            if (_l3.isNotEmpty) {
              for (;;) {
                var _mark = this._mark();
                if (this.f2k() case var _2?) {
                  _l3.add(_2);
                  continue;
                }
                this._recover(_mark);
                break;
              }
            } else {
              this._recover(_mark);
            }
            if (this.matchPattern(_string.$41) case _?) {
              return $1;
            }
          }
        }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$52) case _?) {
      var _mark = this._mark();
        if (this.f2l() case var _4) {
          if ([if (_4 case var _4?) _4] case (var $1 && var _l5)) {
            if (_l5.isNotEmpty) {
              for (;;) {
                var _mark = this._mark();
                if (this.f2l() case var _4?) {
                  _l5.add(_4);
                  continue;
                }
                this._recover(_mark);
                break;
              }
            } else {
              this._recover(_mark);
            }
            if (this.matchPattern(_string.$42) case _?) {
              return $1;
            }
          }
        }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$53) case _?) {
      var _mark = this._mark();
        if (this.f2m() case var _6) {
          if ([if (_6 case var _6?) _6] case (var $1 && var _l7)) {
            if (_l7.isNotEmpty) {
              for (;;) {
                var _mark = this._mark();
                if (this.f2m() case var _6?) {
                  _l7.add(_6);
                  continue;
                }
                this._recover(_mark);
                break;
              }
            } else {
              this._recover(_mark);
            }
            if (this.matchPattern(_string.$43) case _?) {
              return $1;
            }
          }
        }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$39) case _?) {
      var _mark = this._mark();
        if (this.f2n() case var _8) {
          if ([if (_8 case var _8?) _8] case (var $1 && var _l9)) {
            if (_l9.isNotEmpty) {
              for (;;) {
                var _mark = this._mark();
                if (this.f2n() case var _8?) {
                  _l9.add(_8);
                  continue;
                }
                this._recover(_mark);
                break;
              }
            } else {
              this._recover(_mark);
            }
            if (this.matchPattern(_string.$39) case _?) {
              return $1;
            }
          }
        }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$41) case _?) {
      var _mark = this._mark();
        if (this.f2o() case var _10) {
          if ([if (_10 case var _10?) _10] case (var $1 && var _l11)) {
            if (_l11.isNotEmpty) {
              for (;;) {
                var _mark = this._mark();
                if (this.f2o() case var _10?) {
                  _l11.add(_10);
                  continue;
                }
                this._recover(_mark);
                break;
              }
            } else {
              this._recover(_mark);
            }
            if (this.matchPattern(_string.$41) case _?) {
              return $1;
            }
          }
        }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$42) case _?) {
      var _mark = this._mark();
        if (this.f2p() case var _12) {
          if ([if (_12 case var _12?) _12] case (var $1 && var _l13)) {
            if (_l13.isNotEmpty) {
              for (;;) {
                var _mark = this._mark();
                if (this.f2p() case var _12?) {
                  _l13.add(_12);
                  continue;
                }
                this._recover(_mark);
                break;
              }
            } else {
              this._recover(_mark);
            }
            if (this.matchPattern(_string.$42) case _?) {
              return $1;
            }
          }
        }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$43) case _?) {
      var _mark = this._mark();
        if (this.f2q() case var _14) {
          if ([if (_14 case var _14?) _14] case (var $1 && var _l15)) {
            if (_l15.isNotEmpty) {
              for (;;) {
                var _mark = this._mark();
                if (this.f2q() case var _14?) {
                  _l15.add(_14);
                  continue;
                }
                this._recover(_mark);
                break;
              }
            } else {
              this._recover(_mark);
            }
            if (this.matchPattern(_string.$43) case _?) {
              return $1;
            }
          }
        }
    }
  }

  /// `fragment41`
  Object? f2s() {
    var _mark = this._mark();
    if (this.apply(this.rf) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$22) case _?) {
      if (this.apply(this.re)! case var $1) {
        if (this.matchPattern(_string.$21) case _?) {
          return $1;
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$24) case _?) {
      if (this.apply(this.re)! case var $1) {
        if (this.matchPattern(_string.$23) case _?) {
          return $1;
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$20) case _?) {
      if (this.apply(this.re)! case var $1) {
        if (this.matchPattern(_string.$5) case _?) {
          return $1;
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$21) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  }

  /// `fragment42`
  Object? f2t() {
    var _mark = this._mark();
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

  /// `fragment43`
  Object? f2u() {
    var _mark = this._mark();
    if (this.apply(this.rf) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$22) case _?) {
      if (this.apply(this.re)! case var $1) {
        if (this.matchPattern(_string.$21) case _?) {
          return $1;
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$24) case _?) {
      if (this.apply(this.re)! case var $1) {
        if (this.matchPattern(_string.$23) case _?) {
          return $1;
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$20) case _?) {
      if (this.apply(this.re)! case var $1) {
        if (this.matchPattern(_string.$5) case _?) {
          return $1;
        }
      }
    }
    this._recover(_mark);
    if (this.f2t() case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  }

  /// `fragment44`
  Object? f2v() {
    var _mark = this._mark();
    if (this.matchPattern(_string.$21) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$23) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$5) case var $?) {
      return $;
    }
  }

  /// `fragment45`
  Object? f2w() {
    var _mark = this._mark();
    if (this.apply(this.rf) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$22) case _?) {
      if (this.apply(this.re)! case var $1) {
        if (this.matchPattern(_string.$21) case _?) {
          return $1;
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$24) case _?) {
      if (this.apply(this.re)! case var $1) {
        if (this.matchPattern(_string.$23) case _?) {
          return $1;
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$20) case _?) {
      if (this.apply(this.re)! case var $1) {
        if (this.matchPattern(_string.$5) case _?) {
          return $1;
        }
      }
    }
    this._recover(_mark);
    if (this.f2v() case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  }

  /// `fragment46`
  Object? f2x() {
    if (this.f1m() case var $?) {
      return $;
    }
  }

  /// `fragment47`
  Object? f2y() {
    var _mark = this._mark();
    if (this.apply(this.rf) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$22) case _?) {
      if (this.apply(this.ri)! case (var $1 && var $)) {
        if (this.matchPattern(_string.$21) case _?) {
          return $1;
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$21) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  }

  /// `fragment48`
  Object? f2z() {
    if (this.f17() case var $?) {
      return $;
    }
  }

  /// `fragment49`
  Object? f30() {
    if (this.apply(this.r11) case var _0?) {
      if ([_0] case var _l1) {
        for (;;) {
          var _mark = this._mark();
          if (this.f1d() case _?) {
            if (this.apply(this.r11) case var _0?) {
              _l1.add(_0);
              continue;
            }
          }
          this._recover(_mark);
          break;
        }
        return _l1;
      }
    }
  }

  /// `fragment50`
  Object? f31() {
    if (this.f1d() case var $?) {
      return $;
    }
  }

  /// `fragment51`
  Object? f32() {
    if (this.f1d() case var $?) {
      return $;
    }
  }

  /// `fragment52`
  Object? f33() {
    if (this.apply(this.r16)! case _) {
      if (this.matchPattern(_string.$20) case var $1?) {
        if (this.apply(this.r16)! case _) {
          return $1;
        }
      }
    }
  }

  /// `fragment53`
  Object? f34() {
    if (this.f1d() case var $?) {
      return $;
    }
  }

  /// `fragment54`
  Object? f35() {
    if (this.apply(this.r16)! case _) {
      if (this.matchPattern(_string.$5) case var $1?) {
        if (this.apply(this.r16)! case _) {
          return $1;
        }
      }
    }
  }

  /// `fragment55`
  Object? f36() {
    if (this.f1d() case var $?) {
      return $;
    }
  }

  /// `fragment56`
  Object? f37() {
    if (this.f6() case var $?) {
      return $;
    }
  }

  /// `fragment57`
  Object? f38() {
    var _mark = this._mark();
    if (this.matchPattern(_string.$6) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  }

  /// `fragment58`
  Object f39() {
    if (this.f38() case var _0) {
      var _mark = this._mark();
      var _l1 = [if (_0 case var _0?) _0];
      if (_l1.isNotEmpty) {
        for (;;) {
          var _mark = this._mark();
          if (this.f38() case var _0?) {
            _l1.add(_0);
            continue;
          }
          this._recover(_mark);
          break;
        }
      } else {
        this._recover(_mark);
      }
      if (_l1 case var $) {
        return _l1;
      }
    }
  }

  /// `fragment59`
  Object? f3a() {
    if (this.matchPattern(_string.$6) case _?) {
      if (this.f39() case var $1) {
        if (this.matchPattern(_string.$6) case _?) {
          return $1;
        }
      }
    }
  }

  /// `fragment60`
  Object? f3b() {
    if (this.apply(this.rj) case var $0?) {
      if (this.apply(this.r16)! case _) {
        return $0;
      }
    }
  }

  /// `fragment61`
  Object? f3c() {
    var _mark = this._mark();
    if (this.matchPattern(_string.$54) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$12) case (var $0 && null)) {
      this._recover(_mark);
      if (this.matchPattern(_string.$35) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `fragment62`
  Object? f3d() {
    var _mark = this._mark();
    if (this.fb() case var $?) {
      return $;
    }
  }

  /// `fragment63`
  Object? f3e() {
    if (this.f6() case var $0?) {
      if (this.f3c() case _?) {
        var _mark = this._mark();
        if (this.f3d() case null) {
          this._recover(_mark);
          return $0;
        }
      }
    }
  }

  /// `fragment64`
  Object? f3f() {
    var _mark = this._mark();
    if (this.matchPattern(_string.$6) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  }

  /// `fragment65`
  Object? f3g() {
    if (this.matchPattern(_string.$6) case _?) {
      var _mark = this._mark();
        if (this.f3f() case var _0) {
          if ([if (_0 case var _0?) _0] case (var $1 && var _l1)) {
            if (_l1.isNotEmpty) {
              for (;;) {
                var _mark = this._mark();
                if (this.f3f() case var _0?) {
                  _l1.add(_0);
                  continue;
                }
                this._recover(_mark);
                break;
              }
            } else {
              this._recover(_mark);
            }
            if (this.matchPattern(_string.$6) case _?) {
              return $1;
            }
          }
        }
    }
  }

  /// `fragment66`
  Object? f3h() {
    var _mark = this._mark();
    if (this.apply(this.r17) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$1) case var $0?) {
      this._recover(_mark);
      if (this.apply(this.r18) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `fragment67`
  Object? f3i() {
    var _mark = this._mark();
    if (this.apply(this.r1b) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  }

  /// `fragment68`
  Object? f3j() {
    var _mark = this._mark();
    if (this.matchPattern(_string.$55) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  }

  /// `fragment69`
  Object? f3k() {
    if (this.matchPattern(_regexp.$3) case var $?) {
      return $;
    }
  }

  /// `fragment70`
  Object? f3l() {
    if (this.matchPattern(_regexp.$3) case var $?) {
      return $;
    }
  }

  /// `fragment71`
  Object? f3m() {
    var _mark = this._mark();
    if (this.matchPattern(_string.$4) case _?) {
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $1) {
          return $1;
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$1) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  }

  /// `fragment72`
  Object? f3n() {
    if (this.f3m() case var _0?) {
      if ([_0] case var _l1) {
        for (;;) {
          var _mark = this._mark();
          if (this.f3m() case var _0?) {
            _l1.add(_0);
            continue;
          }
          this._recover(_mark);
          break;
        }
        return _l1;
      }
    }
  }

  /// `fragment73`
  Object? f3o() {
    var _mark = this._mark();
    if (this.matchPattern(_string.$39) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  }

  /// `fragment74`
  Object? f3p() {
    var _mark = this._mark();
    if (this.matchPattern(_string.$41) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  }

  /// `fragment75`
  Object? f3q() {
    var _mark = this._mark();
    if (this.matchPattern(_string.$42) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  }

  /// `fragment76`
  Object? f3r() {
    var _mark = this._mark();
    if (this.matchPattern(_string.$43) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  }

  /// `fragment77`
  Object? f3s() {
    var _mark = this._mark();
    if (this.matchPattern(_string.$4) case var $0?) {
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $1) {
          return ($0, $1);
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$39) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  }

  /// `fragment78`
  Object? f3t() {
    var _mark = this._mark();
    if (this.matchPattern(_string.$4) case var $0?) {
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $1) {
          return ($0, $1);
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
  }

  /// `fragment79`
  Object? f3u() {
    var _mark = this._mark();
    if (this.matchPattern(_string.$4) case var $0?) {
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $1) {
          return ($0, $1);
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$42) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  }

  /// `fragment80`
  Object? f3v() {
    var _mark = this._mark();
    if (this.matchPattern(_string.$4) case var $0?) {
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $1) {
          return ($0, $1);
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$43) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  }

  /// `fragment81`
  Object? f3w() {
    var _mark = this._mark();
    if (this.matchPattern(_string.$50) case _?) {
      var _mark = this._mark();
        if (this.f3o() case var _0) {
          if ([if (_0 case var _0?) _0] case (var $1 && var _l1)) {
            if (_l1.isNotEmpty) {
              for (;;) {
                var _mark = this._mark();
                if (this.f3o() case var _0?) {
                  _l1.add(_0);
                  continue;
                }
                this._recover(_mark);
                break;
              }
            } else {
              this._recover(_mark);
            }
            if (this.matchPattern(_string.$39) case _?) {
              return $1;
            }
          }
        }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$51) case _?) {
      var _mark = this._mark();
        if (this.f3p() case var _2) {
          if ([if (_2 case var _2?) _2] case (var $1 && var _l3)) {
            if (_l3.isNotEmpty) {
              for (;;) {
                var _mark = this._mark();
                if (this.f3p() case var _2?) {
                  _l3.add(_2);
                  continue;
                }
                this._recover(_mark);
                break;
              }
            } else {
              this._recover(_mark);
            }
            if (this.matchPattern(_string.$41) case _?) {
              return $1;
            }
          }
        }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$52) case _?) {
      var _mark = this._mark();
        if (this.f3q() case var _4) {
          if ([if (_4 case var _4?) _4] case (var $1 && var _l5)) {
            if (_l5.isNotEmpty) {
              for (;;) {
                var _mark = this._mark();
                if (this.f3q() case var _4?) {
                  _l5.add(_4);
                  continue;
                }
                this._recover(_mark);
                break;
              }
            } else {
              this._recover(_mark);
            }
            if (this.matchPattern(_string.$42) case _?) {
              return $1;
            }
          }
        }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$53) case _?) {
      var _mark = this._mark();
        if (this.f3r() case var _6) {
          if ([if (_6 case var _6?) _6] case (var $1 && var _l7)) {
            if (_l7.isNotEmpty) {
              for (;;) {
                var _mark = this._mark();
                if (this.f3r() case var _6?) {
                  _l7.add(_6);
                  continue;
                }
                this._recover(_mark);
                break;
              }
            } else {
              this._recover(_mark);
            }
            if (this.matchPattern(_string.$43) case _?) {
              return $1;
            }
          }
        }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$39) case _?) {
      var _mark = this._mark();
        if (this.f3s() case var _8) {
          if ([if (_8 case var _8?) _8] case (var $1 && var _l9)) {
            if (_l9.isNotEmpty) {
              for (;;) {
                var _mark = this._mark();
                if (this.f3s() case var _8?) {
                  _l9.add(_8);
                  continue;
                }
                this._recover(_mark);
                break;
              }
            } else {
              this._recover(_mark);
            }
            if (this.matchPattern(_string.$39) case _?) {
              return $1;
            }
          }
        }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$41) case _?) {
      var _mark = this._mark();
        if (this.f3t() case var _10) {
          if ([if (_10 case var _10?) _10] case (var $1 && var _l11)) {
            if (_l11.isNotEmpty) {
              for (;;) {
                var _mark = this._mark();
                if (this.f3t() case var _10?) {
                  _l11.add(_10);
                  continue;
                }
                this._recover(_mark);
                break;
              }
            } else {
              this._recover(_mark);
            }
            if (this.matchPattern(_string.$41) case _?) {
              return $1;
            }
          }
        }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$42) case _?) {
      var _mark = this._mark();
        if (this.f3u() case var _12) {
          if ([if (_12 case var _12?) _12] case (var $1 && var _l13)) {
            if (_l13.isNotEmpty) {
              for (;;) {
                var _mark = this._mark();
                if (this.f3u() case var _12?) {
                  _l13.add(_12);
                  continue;
                }
                this._recover(_mark);
                break;
              }
            } else {
              this._recover(_mark);
            }
            if (this.matchPattern(_string.$42) case _?) {
              return $1;
            }
          }
        }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$43) case _?) {
      var _mark = this._mark();
        if (this.f3v() case var _14) {
          if ([if (_14 case var _14?) _14] case (var $1 && var _l15)) {
            if (_l15.isNotEmpty) {
              for (;;) {
                var _mark = this._mark();
                if (this.f3v() case var _14?) {
                  _l15.add(_14);
                  continue;
                }
                this._recover(_mark);
                break;
              }
            } else {
              this._recover(_mark);
            }
            if (this.matchPattern(_string.$43) case _?) {
              return $1;
            }
          }
        }
    }
  }

  /// `fragment82`
  Object? f3x() {
    var _mark = this._mark();
    if (this.matchPattern(_string.$2) case var $?) {
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
    if (this.fk() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.fl() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.fm() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.fc() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.f4() case (var $0 && var l)?) {
      if (this.matchPattern(_string.$3) case var $1?) {
        if (this.f4() case (var $2 && var r)?) {
          return ($0, $1, $2);
        }
      }
    }
    this._recover(_mark);
    if (this.f4() case var $?) {
      return $;
    }
  }

  /// `fragment83`
  Object? f3y() {
    if (this.matchPattern(_string.$20) case _?) {
      if (this.f3x() case var _0?) {
        if ([_0] case (var $1 && var elements && var _l1)) {
          for (;;) {
            var _mark = this._mark();
            if (this.apply(this.r16)! case _) {
              if (this.f3x() case var _0?) {
                _l1.add(_0);
                continue;
              }
            }
            this._recover(_mark);
            break;
          }
          if (this.matchPattern(_string.$5) case _?) {
            return $1;
          }
        }
      }
    }
  }

  /// `fragment84`
  Object? f3z() {
    var _mark = this._mark();
    if (this.matchPattern(_string.$6) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  }

  /// `fragment85`
  Object? f40() {
    var _mark = this._mark();
    if (this.matchPattern(_string.$6) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  }

  /// `fragment86`
  Object f41() {
    if (this.f40() case var _0) {
      var _mark = this._mark();
      var _l1 = [if (_0 case var _0?) _0];
      if (_l1.isNotEmpty) {
        for (;;) {
          var _mark = this._mark();
          if (this.f40() case var _0?) {
            _l1.add(_0);
            continue;
          }
          this._recover(_mark);
          break;
        }
      } else {
        this._recover(_mark);
      }
      if (_l1 case var $) {
        return _l1;
      }
    }
  }

  /// `fragment87`
  Object? f42() {
    if (this.matchPattern(_string.$4) case var $0?) {
      if (this.matchPattern(_string.$4) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `fragment88`
  Object? f43() {
    if (this.f42() case var $0?) {
      if (this.apply(this.r16)! case _) {
        return $0;
      }
    }
  }

  /// `fragment89`
  Object? f44() {
    if (this.matchPattern(_string.$4) case var $0?) {
      if (this.matchPattern(_string.$56) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `fragment90`
  Object? f45() {
    if (this.matchPattern(_string.$4) case var $0?) {
      if (this.matchPattern(_string.$57) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `fragment91`
  Object? f46() {
    if (this.matchPattern(_string.$4) case var $0?) {
      if (this.matchPattern(_string.$58) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `fragment92`
  Object? f47() {
    if (this.matchPattern(_string.$4) case var $0?) {
      if (this.matchPattern(_string.$49) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `fragment93`
  Object? f48() {
    if (this.matchPattern(_string.$4) case var $0?) {
      if (this.matchPattern(_string.$44) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `fragment94`
  Object? f49() {
    if (this.matchPattern(_string.$4) case var $0?) {
      if (this.matchPattern(_string.$45) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `fragment95`
  Object? f4a() {
    if (this.matchPattern(_string.$4) case var $0?) {
      if (this.matchPattern(_string.$46) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `fragment96`
  Object? f4b() {
    if (this.matchPattern(_string.$4) case var $0?) {
      if (this.matchPattern(_string.$59) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `fragment97`
  Object? f4c() {
    if (this.matchPattern(_string.$4) case var $0?) {
      if (this.matchPattern(_string.$40) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `fragment98`
  Object? f4d() {
    if (this.matchPattern(_string.$4) case var $0?) {
      if (this.matchPattern(_string.$60) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `fragment99`
  Object? f4e() {
    if (this.matchPattern(_string.$4) case var $0?) {
      if (this.matchPattern(_string.$47) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `fragment100`
  Object? f4f() {
    if (this.matchPattern(_string.$4) case var $0?) {
      if (this.matchPattern(_string.$48) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `fragment101`
  Object? f4g() {
    if (this.f1e() case var $?) {
      return $;
    }
  }

  /// `fragment102`
  Object? f4h() {
    if (this.f9() case var $?) {
      return $;
    }
  }

  /// `fragment103`
  Object? f4i() {
    if (this.f9() case var $?) {
      return $;
    }
  }

  /// `fragment104`
  Object? f4j() {
    if (this.f15() case var $?) {
      return $;
    }
  }

  /// `fragment105`
  Object? f4k() {
    if (this.f9() case var $?) {
      return $;
    }
  }

  /// `fragment106`
  Object? f4l() {
    if (this.f9() case var $?) {
      return $;
    }
  }

  /// `fragment107`
  Object? f4m() {
    if (this.f15() case var $?) {
      return $;
    }
  }

  /// `fragment108`
  Object? f4n() {
    var _mark = this._mark();
    if (this.matchPattern(_string.$39) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  }

  /// `fragment109`
  Object? f4o() {
    var _mark = this._mark();
    if (this.matchPattern(_string.$41) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  }

  /// `fragment110`
  Object? f4p() {
    var _mark = this._mark();
    if (this.matchPattern(_string.$42) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  }

  /// `fragment111`
  Object? f4q() {
    var _mark = this._mark();
    if (this.matchPattern(_string.$43) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  }

  /// `fragment112`
  Object? f4r() {
    var _mark = this._mark();
    if (this.matchPattern(_string.$4) case _?) {
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $1) {
          return $1;
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$38) case var $0?) {
      this._recover(_mark);
      if (this.apply(this.rh) case var $1?) {
        return ($0, $1);
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$39) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  }

  /// `fragment113`
  Object? f4s() {
    var _mark = this._mark();
    if (this.matchPattern(_string.$4) case _?) {
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $1) {
          return $1;
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$38) case var $0?) {
      this._recover(_mark);
      if (this.apply(this.rh) case var $1?) {
        return ($0, $1);
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
  }

  /// `fragment114`
  Object? f4t() {
    var _mark = this._mark();
    if (this.matchPattern(_string.$4) case _?) {
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $1) {
          return $1;
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$38) case var $0?) {
      this._recover(_mark);
      if (this.apply(this.rh) case var $1?) {
        return ($0, $1);
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$42) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  }

  /// `fragment115`
  Object? f4u() {
    var _mark = this._mark();
    if (this.matchPattern(_string.$4) case _?) {
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $1) {
          return $1;
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$38) case var $0?) {
      this._recover(_mark);
      if (this.apply(this.rh) case var $1?) {
        return ($0, $1);
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$43) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  }

  /// `global::document`
  Object? r0() {
    if (this.pos case var $0 && <= 0) {
      if (this.f1n() case var $1) {
        if (this.apply(this.r2) case var _0?) {
          if ([_0] case (var $2 && var _l1)) {
            for (;;) {
              var _mark = this._mark();
              if (this.apply(this.r16)! case _) {
                if (this.apply(this.r2) case var _0?) {
                  _l1.add(_0);
                  continue;
                }
              }
              this._recover(_mark);
              break;
            }
            if (this.f1o() case var $3) {
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
    if (this.f12() case _?) {
      if (this.apply(this.r16)! case _) {
        if (this.apply(this.rc)! case (var $2 && var code)) {
          if (this.apply(this.r16)! case _) {
            if (this.f11() case _?) {
              return $2;
            }
          }
        }
      }
    }
  }

  /// `global::statement`
  Object? r2() {
    var _mark = this._mark();
    if (this.f1k() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.f1l() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.f1p() case (var $0 && var outer_decorator)) {
      if (this.f1q() case (var $1 && var type)) {
        if (this.f14() case var $2?) {
          if (this.f13() case var $3?) {
            if (this.f16() case var $4?) {
              if (this.fb() case var $5?) {
                if (this.f1r() case (var $6 && var inner_decorator)) {
                  if (this.f12() case var $7?) {
                    if (this.apply(this.r2) case var _0?) {
                      if ([_0] case (var $8 && var statements && var _l1)) {
                        for (;;) {
                          var _mark = this._mark();
                          if (this.apply(this.r16)! case _) {
                            if (this.apply(this.r2) case var _0?) {
                              _l1.add(_0);
                              continue;
                            }
                          }
                          this._recover(_mark);
                          break;
                        }
                        if (this.f11() case var $9?) {
                          if (this.f1s() case var $10) {
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
    if (this.f1t() case (var $0 && var decorator)) {
      if (this.f1u() case (var $1 && var name)) {
        if (this.f12() case var $2?) {
          if (this.apply(this.r2) case var _2?) {
            if ([_2] case (var $3 && var statements && var _l3)) {
              for (;;) {
                var _mark = this._mark();
                if (this.apply(this.r16)! case _) {
                  if (this.apply(this.r2) case var _2?) {
                    _l3.add(_2);
                    continue;
                  }
                }
                this._recover(_mark);
                break;
              }
              if (this.f11() case var $4?) {
                return ($0, $1, $2, $3, $4);
              }
            }
          }
        }
      }
    }
    this._recover(_mark);
    if (this.f1v() case (var $0 && var decorator)) {
      if (this.f1w() case (var $1 && var type)) {
        if (this.apply(this.r13) case var _4?) {
          if ([_4] case (var $2 && var names && var _l5)) {
            for (;;) {
              var _mark = this._mark();
              if (this.f1d() case _?) {
                if (this.apply(this.r13) case var _4?) {
                  _l5.add(_4);
                  continue;
                }
              }
              this._recover(_mark);
              break;
            }
            if (this.f15() case var $3?) {
              return ($0, $1, $2, $3);
            }
          }
        }
      }
    }
    this._recover(_mark);
    if (this.f1x() case (var $0 && var decorator)) {
      if (this.apply(this.r11) case (var $1 && var type)?) {
        if (this.apply(this.r13) case (var $2 && var name)?) {
          if (this.f1y() case (var $3 && var body)?) {
            return ($0, $1, $2, $3);
          }
        }
      }
    }
    this._recover(_mark);
    if (this.f1z() case (var $0 && var decorator)) {
      if (this.apply(this.r13) case (var $1 && var name)?) {
        if (this.f20() case (var $2 && var body)?) {
          return ($0, $1, $2);
        }
      }
    }
  }

  /// `global::choice`
  Object? r3() {
    if (this.f21() case _) {
      if (this.apply(this.r4) case var _0?) {
        if ([_0] case (var $1 && var options && var _l1)) {
          for (;;) {
            var _mark = this._mark();
            if (this.fp() case _?) {
              if (this.apply(this.r4) case var _0?) {
                _l1.add(_0);
                continue;
              }
            }
            this._recover(_mark);
            break;
          }
          return $1;
        }
      }
    }
  }

  /// `global::acted`
  Object? r4() {
    var _mark = this._mark();
    if (this.apply(this.r5) case (var $0 && var sequence)?) {
      if (this.f22() case var $1?) {
        if (this.apply(this.r16)! case var $2) {
          if (this.apply(this.rd)! case (var $3 && var code)) {
            if (this.apply(this.r16)! case var $4) {
              return ($0, $1, $2, $3, $4);
            }
          }
        }
      }
    }
    this._recover(_mark);
    if (this.apply(this.r5) case (var $0 && var sequence)?) {
      if (this.f12() case var $1?) {
        if (this.apply(this.r16)! case var $2) {
          if (this.apply(this.rc)! case (var $3 && var code)) {
            if (this.apply(this.r16)! case var $4) {
              if (this.f11() case var $5?) {
                return ($0, $1, $2, $3, $4, $5);
              }
            }
          }
        }
      }
    }
    this._recover(_mark);
    if (this.apply(this.r5) case (var $0 && var sequence)?) {
      if (this.f14() case var $1?) {
        if (this.f13() case var $2?) {
          if (this.f12() case var $3?) {
            if (this.apply(this.r16)! case var $4) {
              if (this.apply(this.rc)! case (var $5 && var code)) {
                if (this.apply(this.r16)! case var $6) {
                  if (this.f11() case var $7?) {
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

  /// `global::sequence`
  Object? r5() {
    if (this.apply(this.r6) case var _0?) {
      if ([_0] case (var $0 && var body && var _l1)) {
        for (;;) {
          var _mark = this._mark();
          if (this.apply(this.r16)! case _) {
            if (this.apply(this.r6) case var _0?) {
              _l1.add(_0);
              continue;
            }
          }
          this._recover(_mark);
          break;
        }
        if (this.f24() case (var $1 && var chosen)) {
          return ($0, $1);
        }
      }
    }
  }

  /// `global::dropped`
  Object? r6() {
    var _mark = this._mark();
    if (this.apply(this.r6) case (var $0 && var captured)?) {
      if (this.ft() case var $1?) {
        if (this.apply(this.r8) case (var $2 && var dropped)?) {
          return ($0, $1, $2);
        }
      }
    }
    this._recover(_mark);
    if (this.apply(this.r8) case (var $0 && var dropped)?) {
      if (this.f25() case var $1?) {
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

  /// `global::labeled`
  Object? r7() {
    var _mark = this._mark();
    if (this.f6() case (var $0 && var identifier)?) {
      if (this.matchPattern(_string.$61) case var $1?) {
        if (this.apply(this.r16)! case var $2) {
          if (this.apply(this.r8) case (var $3 && var special)?) {
            return ($0, $1, $2, $3);
          }
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$61) case _?) {
      if (this.apply(this.r15) case (var $1 && var id)?) {
        if (this.f17() case _?) {
          return $1;
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$61) case _?) {
      if (this.apply(this.r15) case (var $1 && var id)?) {
        if (this.f1b() case _?) {
          return $1;
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$61) case _?) {
      if (this.apply(this.r15) case (var $1 && var id)?) {
        if (this.f1c() case _?) {
          return $1;
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$61) case _?) {
      if (this.apply(this.r15) case (var $1 && var id)?) {
        return $1;
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$61) case _?) {
      if (this.apply(this.r8) case (var $1 && var node)?) {
        return $1;
      }
    }
    this._recover(_mark);
    if (this.apply(this.r8) case var $?) {
      return $;
    }
  }

  /// `global::special`
  Object? r8() {
    var _mark = this._mark();
    if (this.apply(this.rb) case (var $0 && var sep)?) {
      if (this.fr() case var $1?) {
        if (this.apply(this.rb) case (var $2 && var expr)?) {
          if (this.f1c() case var $3?) {
            if (this.f17() case var $4?) {
              return ($0, $1, $2, $3, $4);
            }
          }
        }
      }
    }
    this._recover(_mark);
    if (this.apply(this.rb) case (var $0 && var sep)?) {
      if (this.fr() case var $1?) {
        if (this.apply(this.rb) case (var $2 && var expr)?) {
          if (this.f1b() case var $3?) {
            if (this.f17() case var $4?) {
              return ($0, $1, $2, $3, $4);
            }
          }
        }
      }
    }
    this._recover(_mark);
    if (this.apply(this.rb) case (var $0 && var sep)?) {
      if (this.fr() case var $1?) {
        if (this.apply(this.rb) case (var $2 && var expr)?) {
          if (this.f1c() case var $3?) {
            return ($0, $1, $2, $3);
          }
        }
      }
    }
    this._recover(_mark);
    if (this.apply(this.rb) case (var $0 && var sep)?) {
      if (this.fr() case var $1?) {
        if (this.apply(this.rb) case (var $2 && var expr)?) {
          if (this.f1b() case var $3?) {
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

  /// `global::postfix`
  Object? r9() {
    var _mark = this._mark();
    if (this.apply(this.r9) case var $0?) {
      if (this.f17() case _?) {
        return $0;
      }
    }
    this._recover(_mark);
    if (this.apply(this.r9) case var $0?) {
      if (this.f1b() case _?) {
        return $0;
      }
    }
    this._recover(_mark);
    if (this.apply(this.r9) case var $0?) {
      if (this.f1c() case _?) {
        return $0;
      }
    }
    this._recover(_mark);
    if (this.apply(this.ra) case var $?) {
      return $;
    }
  }

  /// `global::prefix`
  Object? ra() {
    var _mark = this._mark();
    if (this.f8() case (var $0 && var min)?) {
      if (this.fr() case var $1?) {
        if (this.f8() case (var $2 && var max)?) {
          if (this.apply(this.rb) case (var $3 && var body)?) {
            return ($0, $1, $2, $3);
          }
        }
      }
    }
    this._recover(_mark);
    if (this.f8() case (var $0 && var min)?) {
      if (this.fr() case var $1?) {
        if (this.apply(this.rb) case (var $2 && var body)?) {
          return ($0, $1, $2);
        }
      }
    }
    this._recover(_mark);
    if (this.f8() case (var $0 && var number)?) {
      if (this.apply(this.rb) case (var $1 && var body)?) {
        return ($0, $1);
      }
    }
    this._recover(_mark);
    if (this.f26() case _?) {
      if (this.apply(this.ra) case var $1?) {
        return $1;
      }
    }
    this._recover(_mark);
    if (this.f27() case _?) {
      if (this.apply(this.ra) case var $1?) {
        return $1;
      }
    }
    this._recover(_mark);
    if (this.f28() case _?) {
      if (this.apply(this.ra) case var $1?) {
        return $1;
      }
    }
    this._recover(_mark);
    if (this.apply(this.rb) case var $?) {
      return $;
    }
  }

  /// `global::atom`
  Object? rb() {
    var _mark = this._mark();
    if (this.f14() case _?) {
      if (null case _) {
        _mark.isCut = true;
        if (this.apply(this.r3) case (var $2 && var $)?) {
          if (this.f13() case _?) {
            return $2;
          }
        }
      }
    }
    if (_mark.isCut) return null; else this._recover(_mark);
    if (this.ft() case null) {
      this._recover(_mark);
      if (this.fx() case _?) {
        if (null case _) {
          _mark.isCut = true;
          if (this.apply(this.r3) case (var $3 && var $)?) {
            if (this.fy() case _?) {
              return $3;
            }
          }
        }
      }
    }
    if (_mark.isCut) return null; else this._recover(_mark);
    if (this.apply(this.r16)! case _) {
      if (this.matchPattern(_string.$37) case var $1?) {
        if (this.apply(this.r16)! case _) {
          return $1;
        }
      }
    }
    this._recover(_mark);
    if (this.apply(this.r16)! case _) {
      if (this.matchPattern(_string.$38) case var $1?) {
        if (this.apply(this.r16)! case _) {
          return $1;
        }
      }
    }
    this._recover(_mark);
    if (this.f1f() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.apply(this.r16)! case _) {
      if (this.matchPattern(_string.$36) case var $1?) {
        if (this.apply(this.r16)! case _) {
          return $1;
        }
      }
    }
    this._recover(_mark);
    if (this.apply(this.r16)! case _) {
      if (this.matchPattern(_string.$11) case var $1?) {
        if (this.apply(this.r16)! case _) {
          return $1;
        }
      }
    }
    this._recover(_mark);
    if (this.apply(this.r16)! case _) {
      if (this.matchPattern(_string.$16) case var $1?) {
        if (this.apply(this.r16)! case _) {
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
    if (this.apply(this.r16)! case _) {
      if (this.f29() case (var $1 && var $)?) {
        if (this.apply(this.r16)! case _) {
          return $1;
        }
      }
    }
    this._recover(_mark);
    if (this.apply(this.r16)! case _) {
      if (this.f2a() case (var $1 && var $)?) {
        if (this.apply(this.r16)! case _) {
          return $1;
        }
      }
    }
    this._recover(_mark);
    if (this.apply(this.r16)! case _) {
      if (this.f2b() case (var $1 && var $)?) {
        if (this.apply(this.r16)! case _) {
          return $1;
        }
      }
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
    if (this.apply(this.r16)! case _) {
      if (this.f2c() case (var $1 && var $)?) {
        if (this.apply(this.r16)! case _) {
          return $1;
        }
      }
    }
    this._recover(_mark);
    if (this.apply(this.r16)! case _) {
      if (this.f2d() case (var $1 && var $)?) {
        if (this.apply(this.r16)! case _) {
          return $1;
        }
      }
    }
    this._recover(_mark);
    if (this.apply(this.r16)! case _) {
      if (this.f2e() case (var $1 && var $)?) {
        if (this.apply(this.r16)! case _) {
          return $1;
        }
      }
    }
    this._recover(_mark);
    if (this.apply(this.r16)! case _) {
      if (this.f2g() case var $1?) {
        if (this.apply(this.r16)! case _) {
          return $1;
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$1) case _?) {
      if (this.f2i() case var $1?) {
        if (this.matchPattern(_string.$1) case _?) {
          return $1;
        }
      }
    }
    this._recover(_mark);
    if (this.apply(this.r16)! case _) {
      if (this.f2r() case var $1?) {
        if (this.apply(this.r16)! case _) {
          return $1;
        }
      }
    }
    this._recover(_mark);
    if (this.apply(this.r13) case var $?) {
      return $;
    }
  }

  /// `global::code::curly`
  Object rc() {
    var _mark = this._mark();
      if (this.f2s() case var _0) {
        if ([if (_0 case var _0?) _0] case var _l1) {
          if (_l1.isNotEmpty) {
            for (;;) {
              var _mark = this._mark();
              if (this.f2s() case var _0?) {
                _l1.add(_0);
                continue;
              }
              this._recover(_mark);
              break;
            }
          } else {
            this._recover(_mark);
          }
          return _l1;
        }
      }
  }

  /// `global::code::nl`
  Object rd() {
    var _mark = this._mark();
      if (this.f2u() case var _0) {
        if ([if (_0 case var _0?) _0] case var _l1) {
          if (_l1.isNotEmpty) {
            for (;;) {
              var _mark = this._mark();
              if (this.f2u() case var _0?) {
                _l1.add(_0);
                continue;
              }
              this._recover(_mark);
              break;
            }
          } else {
            this._recover(_mark);
          }
          return _l1;
        }
      }
  }

  /// `global::code::balanced`
  Object re() {
    var _mark = this._mark();
      if (this.f2w() case var _0) {
        if ([if (_0 case var _0?) _0] case var _l1) {
          if (_l1.isNotEmpty) {
            for (;;) {
              var _mark = this._mark();
              if (this.f2w() case var _0?) {
                _l1.add(_0);
                continue;
              }
              this._recover(_mark);
              break;
            }
          } else {
            this._recover(_mark);
          }
          return _l1;
        }
      }
  }

  /// `global::dart::literal::string`
  Object? rf() {
    if (this.f2x() case var _0?) {
      if ([_0] case var _l1) {
        for (;;) {
          var _mark = this._mark();
          if (this.apply(this.r16)! case _) {
            if (this.f2x() case var _0?) {
              _l1.add(_0);
              continue;
            }
          }
          this._recover(_mark);
          break;
        }
        return _l1;
      }
    }
  }

  /// `global::dart::literal::identifier`
  Object? rg() {
    if (this.f6() case var $?) {
      return $;
    }
  }

  /// `global::dart::literal::string::interpolation`
  Object? rh() {
    var _mark = this._mark();
    if (this.matchPattern(_string.$38) case var $0?) {
      if (this.matchPattern(_string.$22) case var $1?) {
        if (this.apply(this.ri)! case var $2) {
          if (this.matchPattern(_string.$21) case var $3?) {
            return ($0, $1, $2, $3);
          }
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$38) case var $0?) {
      if (this.apply(this.rg) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `global::dart::literal::string::balanced`
  Object ri() {
    var _mark = this._mark();
      if (this.f2y() case var _0) {
        if ([if (_0 case var _0?) _0] case var _l1) {
          if (_l1.isNotEmpty) {
            for (;;) {
              var _mark = this._mark();
              if (this.f2y() case var _0?) {
                _l1.add(_0);
                continue;
              }
              this._recover(_mark);
              break;
            }
          } else {
            this._recover(_mark);
          }
          return _l1;
        }
      }
  }

  /// `global::dart::type::main`
  Object? rj() {
    if (this.apply(this.r16)! case _) {
      if (this.apply(this.rk) case var $1?) {
        if (this.apply(this.r16)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::dart::type::nullable`
  Object? rk() {
    if (this.apply(this.rl) case (var $0 && var nonNullable)?) {
      if (this.f2z() case (var $1 && var question)) {
        return ($0, $1);
      }
    }
  }

  /// `global::dart::type::nonNullable`
  Object? rl() {
    var _mark = this._mark();
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

  /// `global::dart::type::nonNullable::function`
  Object? rm() {
    if (this.apply(this.rk) case (var $0 && var nullable)?) {
      if (this.apply(this.r16)! case var $1) {
        if (this.matchPattern(_string.$62) case var $2?) {
          if (this.apply(this.r16)! case var $3) {
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
      if (this.fx() case var $1?) {
        if (this.f30() case (var $2 && var args)?) {
          if (this.fy() case var $3?) {
            return ($0, $1, $2, $3);
          }
        }
      }
    }
  }

  /// `global::dart::type::nonNullable::record`
  Object? ro() {
    var _mark = this._mark();
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

  /// `global::dart::type::nonNullable::record::all`
  Object? rp() {
    if (this.f14() case var $0?) {
      if (this.apply(this.rx) case (var $1 && var positional)?) {
        if (this.f1d() case var $2?) {
          if (this.apply(this.rw) case (var $3 && var named)?) {
            if (this.f13() case var $4?) {
              return ($0, $1, $2, $3, $4);
            }
          }
        }
      }
    }
  }

  /// `global::dart::type::nonNullable::record::onlyPositional`
  Object? rq() {
    if (this.f14() case _?) {
      if (this.apply(this.rx) case (var $1 && var positional)?) {
        if (this.f31() case _) {
          if (this.f13() case _?) {
            return $1;
          }
        }
      }
    }
  }

  /// `global::dart::type::nonNullable::record::onlyNamed`
  Object? rr() {
    if (this.f14() case _?) {
      if (this.apply(this.rw) case (var $1 && var named)?) {
        if (this.f13() case _?) {
          return $1;
        }
      }
    }
  }

  /// `global::dart::type::nonNullable::record::empty`
  Object? rs() {
    if (this.f14() case var $0?) {
      if (this.f13() case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `global::dart::type::nonNullable::base`
  Object? rt() {
    if (this.f6() case var _0?) {
      if ([_0] case var _l1) {
        for (;;) {
          var _mark = this._mark();
          if (this.f1f() case _?) {
            if (this.f6() case var _0?) {
              _l1.add(_0);
              continue;
            }
          }
          this._recover(_mark);
          break;
        }
        return _l1;
      }
    }
  }

  /// `global::dart::type::fnParameters`
  Object? ru() {
    var _mark = this._mark();
    if (this.f14() case var $0?) {
      if (this.apply(this.rx) case (var $1 && var positional)?) {
        if (this.f1d() case var $2?) {
          if (this.apply(this.rw) case (var $3 && var named)?) {
            if (this.f13() case var $4?) {
              return ($0, $1, $2, $3, $4);
            }
          }
        }
      }
    }
    this._recover(_mark);
    if (this.f14() case var $0?) {
      if (this.apply(this.rx) case (var $1 && var positional)?) {
        if (this.f1d() case var $2?) {
          if (this.apply(this.rv) case (var $3 && var optional)?) {
            if (this.f13() case var $4?) {
              return ($0, $1, $2, $3, $4);
            }
          }
        }
      }
    }
    this._recover(_mark);
    if (this.f14() case _?) {
      if (this.apply(this.rx) case (var $1 && var positional)?) {
        if (this.f32() case _) {
          if (this.f13() case _?) {
            return $1;
          }
        }
      }
    }
    this._recover(_mark);
    if (this.f14() case _?) {
      if (this.apply(this.rw) case (var $1 && var named)?) {
        if (this.f13() case _?) {
          return $1;
        }
      }
    }
    this._recover(_mark);
    if (this.f14() case _?) {
      if (this.apply(this.rv) case (var $1 && var optional)?) {
        if (this.f13() case _?) {
          return $1;
        }
      }
    }
    this._recover(_mark);
    if (this.f14() case var $0?) {
      if (this.f13() case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `global::dart::type::parameters::optional`
  Object? rv() {
    if (this.f33() case _?) {
      if (this.apply(this.rx) case (var $1 && var $)?) {
        if (this.f34() case _) {
          if (this.f35() case _?) {
            return $1;
          }
        }
      }
    }
  }

  /// `global::dart::type::parameters::named`
  Object? rw() {
    if (this.f12() case _?) {
      if (this.apply(this.ry) case (var $1 && var $)?) {
        if (this.f36() case _) {
          if (this.f11() case _?) {
            return $1;
          }
        }
      }
    }
  }

  /// `global::dart::type::fields::positional`
  Object? rx() {
    if (this.apply(this.rz) case (var $0 && var car)?) {
      if (this.f1d() case var $1?) {
        var _mark = this._mark();
        if (this.apply(this.rz) case var _0) {
          if ([if (_0 case var _0?) _0] case (var $2 && var cdr && var _l1)) {
            if ($2.isNotEmpty) {
              for (;;) {
                var _mark = this._mark();
                  if (this.f1d() case _?) {
                    if (this.apply(this.rz) case var _0?) {
                      _l1.add(_0);
                      continue;
                    }
                  }
                this._recover(_mark);
                break;
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

  /// `global::dart::type::fields::named`
  Object? ry() {
    if (this.apply(this.r10) case var _0?) {
      if ([_0] case var _l1) {
        for (;;) {
          var _mark = this._mark();
          if (this.f1d() case _?) {
            if (this.apply(this.r10) case var _0?) {
              _l1.add(_0);
              continue;
            }
          }
          this._recover(_mark);
          break;
        }
        return _l1;
      }
    }
  }

  /// `global::dart::type::field::positional`
  Object? rz() {
    if (this.apply(this.r11) case var $0?) {
      if (this.apply(this.r16)! case var $1) {
        if (this.f37() case var $2) {
          return ($0, $1, $2);
        }
      }
    }
  }

  /// `global::dart::type::field::named`
  Object? r10() {
    if (this.apply(this.r11) case var $0?) {
      if (this.apply(this.r16)! case var $1) {
        if (this.f6() case var $2?) {
          return ($0, $1, $2);
        }
      }
    }
  }

  /// `global::type`
  Object? r11() {
    var _mark = this._mark();
    if (this.apply(this.r16)! case _) {
      if (this.f3a() case var $1?) {
        if (this.apply(this.r16)! case _) {
          return $1;
        }
      }
    }
    this._recover(_mark);
    if (this.apply(this.r16)! case _) {
      if (this.f3b() case var $1?) {
        return $1;
      }
    }
  }

  /// `global::namespaceReference`
  Object r12() {
    var _mark = this._mark();
    if (this.f3e() case var _0?) {
      if ([_0].nullable() case var _l1) {
        if (_l1 != null) {
          for (;;) {
            var _mark = this._mark();
            if (this.f3e() case var _0?) {
              _l1.add(_0);
              continue;
            }
            this._recover(_mark);
            break;
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

  /// `global::name`
  Object? r13() {
    var _mark = this._mark();
    if (this.apply(this.r14) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.apply(this.r15) case var $?) {
      return $;
    }
  }

  /// `global::namespacedRaw`
  Object? r14() {
    if (this.apply(this.r12)! case var $0) {
      if (this.f3g() case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `global::namespacedIdentifier`
  Object? r15() {
    if (this.apply(this.r12)! case var $0) {
      if (this.f6() case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `global::_`
  Object r16() {
    var _mark = this._mark();
      if (this.f3h() case var _0) {
        if ([if (_0 case var _0?) _0] case var _l1) {
          if (_l1.isNotEmpty) {
            for (;;) {
              var _mark = this._mark();
              if (this.f3h() case var _0?) {
                _l1.add(_0);
                continue;
              }
              this._recover(_mark);
              break;
            }
          } else {
            this._recover(_mark);
          }
          return _l1;
        }
      }
  }

  /// `global::whitespace`
  Object? r17() {
    if (this.matchPattern(_regexp.$4) case var _0?) {
      if ([_0] case var _l1) {
        for (;;) {
          var _mark = this._mark();
          if (this.matchPattern(_regexp.$4) case var _0?) {
            _l1.add(_0);
            continue;
          }
          this._recover(_mark);
          break;
        }
        return _l1;
      }
    }
  }

  /// `global::comment`
  Object? r18() {
    var _mark = this._mark();
    if (this.apply(this.r19) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.apply(this.r1a) case var $?) {
      return $;
    }
  }

  /// `global::comment::single`
  Object? r19() {
    if (this.matchPattern(_string.$63) case var $0?) {
      var _mark = this._mark();
        if (this.f3i() case var _0) {
          if ([if (_0 case var _0?) _0] case (var $1 && var _l1)) {
            if (_l1.isNotEmpty) {
              for (;;) {
                var _mark = this._mark();
                if (this.f3i() case var _0?) {
                  _l1.add(_0);
                  continue;
                }
                this._recover(_mark);
                break;
              }
            } else {
              this._recover(_mark);
            }
            return ($0, $1);
          }
        }
    }
  }

  /// `global::comment::multi`
  Object? r1a() {
    if (this.matchPattern(_string.$64) case var $0?) {
      var _mark = this._mark();
        if (this.f3j() case var _0) {
          if ([if (_0 case var _0?) _0] case (var $1 && var _l1)) {
            if (_l1.isNotEmpty) {
              for (;;) {
                var _mark = this._mark();
                if (this.f3j() case var _0?) {
                  _l1.add(_0);
                  continue;
                }
                this._recover(_mark);
                break;
              }
            } else {
              this._recover(_mark);
            }
            if (this.matchPattern(_string.$55) case var $2?) {
              return ($0, $1, $2);
            }
          }
        }
    }
  }

  /// `global::newlineOrEof`
  Object? r1b() {
    var _mark = this._mark();
    if (this.f3k() case var $0) {
      if (this.matchPattern(_regexp.$2) case var $1?) {
        if (this.f3l() case var $2) {
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
  /// `"/"`
  static const $1 = "/";
  /// `" "`
  static const $2 = " ";
  /// `"-"`
  static const $3 = "-";
  /// `"\\"`
  static const $4 = "\\";
  /// `"]"`
  static const $5 = "]";
  /// `"`"`
  static const $6 = "`";
  /// `"@rule"`
  static const $7 = "@rule";
  /// `"@fragment"`
  static const $8 = "@fragment";
  /// `"@inline"`
  static const $9 = "@inline";
  /// `"choice!"`
  static const $10 = "choice!";
  /// `"#"`
  static const $11 = "#";
  /// `".."`
  static const $12 = "..";
  /// `"~>"`
  static const $13 = "~>";
  /// `"<~"`
  static const $14 = "<~";
  /// `"|>"`
  static const $15 = "|>";
  /// `"%"`
  static const $16 = "%";
  /// `"@"`
  static const $17 = "@";
  /// `"<"`
  static const $18 = "<";
  /// `">"`
  static const $19 = ">";
  /// `"["`
  static const $20 = "[";
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
  /// `"!"`
  static const $28 = "!";
  /// `"~"`
  static const $29 = "~";
  /// `"&"`
  static const $30 = "&";
  /// `"*"`
  static const $31 = "*";
  /// `"+"`
  static const $32 = "+";
  /// `","`
  static const $33 = ",";
  /// `"|"`
  static const $34 = "|";
  /// `"."`
  static const $35 = ".";
  /// `"ε"`
  static const $36 = "ε";
  /// `"^"`
  static const $37 = "^";
  /// `"\$"`
  static const $38 = "\$";
  /// `"\"\"\""`
  static const $39 = "\"\"\"";
  /// `"r"`
  static const $40 = "r";
  /// `"'''"`
  static const $41 = "'''";
  /// `"\""`
  static const $42 = "\"";
  /// `"'"`
  static const $43 = "'";
  /// `"D"`
  static const $44 = "D";
  /// `"W"`
  static const $45 = "W";
  /// `"S"`
  static const $46 = "S";
  /// `"f"`
  static const $47 = "f";
  /// `"v"`
  static const $48 = "v";
  /// `"b"`
  static const $49 = "b";
  /// `"r\"\"\""`
  static const $50 = "r\"\"\"";
  /// `"r'''"`
  static const $51 = "r'''";
  /// `"r\""`
  static const $52 = "r\"";
  /// `"r'"`
  static const $53 = "r'";
  /// `"::"`
  static const $54 = "::";
  /// `"*/"`
  static const $55 = "*/";
  /// `"d"`
  static const $56 = "d";
  /// `"w"`
  static const $57 = "w";
  /// `"s"`
  static const $58 = "s";
  /// `"n"`
  static const $59 = "n";
  /// `"t"`
  static const $60 = "t";
  /// `":"`
  static const $61 = ":";
  /// `"Function"`
  static const $62 = "Function";
  /// `"//"`
  static const $63 = "//";
  /// `"/*"`
  static const $64 = "/*";
}
class _range {
  /// `[a-zA-Z0-9_$]`
  static const $1 = { (97, 122), (65, 90), (48, 57), (95, 95), (36, 36) };
  /// `[a-zA-Z_$]`
  static const $2 = { (97, 122), (65, 90), (95, 95), (36, 36) };
}
