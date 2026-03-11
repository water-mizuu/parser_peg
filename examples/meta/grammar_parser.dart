// ignore_for_file: type=lint, body_might_complete_normally_nullable, unused_local_variable, inference_failure_on_function_return_type, unused_import, duplicate_ignore, unused_element, collection_methods_unrelated_type, unused_element, use_setters_to_change_properties

// imports
// ignore_for_file: avoid_positional_boolean_parameters, unnecessary_this, unused_element, use_setters_to_change_properties

// ignore: unused_shown_name
import "dart:collection" show DoubleLinkedQueue, HashMap, Queue;
import "dart:math" as math show Random;
// PREAMBLE
import "package:parser_peg/src/node.dart";
import "package:parser_peg/src/generator.dart";
import "package:parser_peg/src/statement.dart";

final _regexps = (from: RegExp(r"\bfrom\b"), to: RegExp(r"\bto\b"), span: RegExp(r"\bspan\b"));

class FlatNode extends InlineActionNode {
  const FlatNode(Node child) : super(child, "span", areIndicesProvided: true, isSpanUsed: true);
}

extension on Node {
  Node operator |(Node other) => switch ((this, other)) {
    (ChoiceNode(children: var l), ChoiceNode(children: var r)) => ChoiceNode([...l, ...r]),
    (ChoiceNode(children: var l), Node r) => ChoiceNode([...l, r]),
    (Node l, ChoiceNode(children: var r)) => ChoiceNode([l, ...r]),
    (Node l, Node r) => ChoiceNode([l, r]),
  };
}

ActionNode inlineBlockAction(Node node, List<String> code) {
  var trimmed = code.reversed.skipWhile((c) => c.trim().isEmpty).toList().reversed.toList();

  /// We removed a semicolon for the last one.
  ///   We should at it back later.
  if (trimmed.length != code.length) {
    trimmed.last += ";";
  }
  if (trimmed.last.trim() case String last when !last.startsWith("return") && !last.endsWith(";")) {
    trimmed.last = "return ${trimmed.last};";
  }

  var joined = trimmed.join(";").trimRight();

  return ActionNode(
    node,
    joined,
    areIndicesProvided: joined.contains(_regexps.from) && joined.contains(_regexps.to),
    isSpanUsed: joined.contains(_regexps.span),
  );
}

InlineActionNode inlineAction(Node node, String code) => InlineActionNode(
  node,
  code.trimRight(),
  areIndicesProvided: code.contains(_regexps.from) && code.contains(_regexps.to),
  isSpanUsed: code.contains(_regexps.span),
);

ActionNode action(Node node, String code) => ActionNode(
  node,
  code.trimRight(),
  areIndicesProvided: code.contains(_regexps.from) && code.contains(_regexps.to),
  isSpanUsed: code.contains(_regexps.span),
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
final class GrammarParser extends _PegParser<ParserGenerator> {
  GrammarParser();

  @override
  get start => r0;

  /// `global::literal::regexp`
  String? f0() {
    if (this.matchPattern(_string.$1) case _?) {
      if (this.f3c() case var $1?) {
        if (this.matchPattern(_string.$1) case _?) {
          return $1;
        }
      }
    }
  }

  /// `global::literal::string`
  String? f1() {
    if (this.apply(this.r1i)! case _) {
      if (this.f3l() case var $1?) {
        if (this.apply(this.r1i)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::literal::range`
  Set<(int, int)>? f2() {
    if (this.apply(this.r1i)! case _) {
      if (this.f3n() case var $1?) {
        if (this.apply(this.r1i)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::literal::range::element`
  Set<(int, int)>? f3() {
    var _mark = this._mark();
    if (this.matchPattern(_string.$2) case var $?) {
      return {(32, 32)};
    }
    this._recover(_mark);
    if (this.f7() case var $?) {
      return {(48, 57)};
    }
    this._recover(_mark);
    if (this.f9() case var $?) {
      return {(64 + 1, 64 + 26), (96 + 1, 96 + 26)};
    }
    this._recover(_mark);
    if (this.fb() case var $?) {
      return {(9, 13), (32, 32)};
    }
    this._recover(_mark);
    if (this.fe() case var $?) {
      return {(10, 10)};
    }
    this._recover(_mark);
    if (this.ff() case var $?) {
      return {(13, 13)};
    }
    this._recover(_mark);
    if (this.fg() case var $?) {
      return {(9, 9)};
    }
    this._recover(_mark);
    if (this.f6() case var $?) {
      return {(92, 92)};
    }
    this._recover(_mark);
    if (this.f4() case var l?) {
      if (this.matchPattern(_string.$3) case _?) {
        if (this.f4() case var r?) {
          return {(l.codeUnitAt(0), r.codeUnitAt(0))};
        }
      }
    }
    this._recover(_mark);
    if (this.f4() case var $?) {
      return {($.codeUnitAt(0), $.codeUnitAt(0))};
    }
  }

  /// `global::literal::range::atom`
  String? f4() {
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
  String? f5() {
    if (this.matchPattern(_string.$6) case _?) {
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
          if (this.matchPattern(_string.$6) case _?) {
            if ($1 case var $) {
              return $.join();
            }
          }
        }
      }
    }
  }

  /// `global::regexEscape::backslash`
  String? f6() {
    if (this.apply(this.r1i)! case _) {
      if (this.f3q() case var $1?) {
        return $1;
      }
    }
  }

  /// `global::regexEscape::digit`
  String? f7() {
    if (this.apply(this.r1i)! case _) {
      if (this.f3r() case (var $1 && var $)?) {
        if (this.apply(this.r1i)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::regexEscape::notDigit`
  String? f8() {
    if (this.apply(this.r1i)! case _) {
      if (this.f3s() case (var $1 && var $)?) {
        if (this.apply(this.r1i)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::regexEscape::word`
  String? f9() {
    if (this.apply(this.r1i)! case _) {
      if (this.f3t() case (var $1 && var $)?) {
        if (this.apply(this.r1i)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::regexEscape::notWord`
  String? fa() {
    if (this.apply(this.r1i)! case _) {
      if (this.f3u() case (var $1 && var $)?) {
        if (this.apply(this.r1i)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::regexEscape::whitespace`
  String? fb() {
    if (this.apply(this.r1i)! case _) {
      if (this.f3v() case (var $1 && var $)?) {
        if (this.apply(this.r1i)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::regexEscape::notWhitespace`
  String? fc() {
    if (this.apply(this.r1i)! case _) {
      if (this.f3w() case (var $1 && var $)?) {
        if (this.apply(this.r1i)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::regexEscape::wordBoundary`
  String? fd() {
    if (this.apply(this.r1i)! case _) {
      if (this.f3x() case (var $1 && var $)?) {
        if (this.apply(this.r1i)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::regexEscape::newline`
  String? fe() {
    if (this.apply(this.r1i)! case _) {
      if (this.f3y() case (var $1 && var $)?) {
        if (this.apply(this.r1i)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::regexEscape::carriageReturn`
  String? ff() {
    if (this.apply(this.r1i)! case _) {
      if (this.f3z() case (var $1 && var $)?) {
        if (this.apply(this.r1i)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::regexEscape::tab`
  String? fg() {
    if (this.apply(this.r1i)! case _) {
      if (this.f40() case (var $1 && var $)?) {
        if (this.apply(this.r1i)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::regexEscape::formFeed`
  String? fh() {
    if (this.apply(this.r1i)! case _) {
      if (this.f41() case (var $1 && var $)?) {
        if (this.apply(this.r1i)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::regexEscape::verticalTab`
  String? fi() {
    if (this.apply(this.r1i)! case _) {
      if (this.f42() case (var $1 && var $)?) {
        if (this.apply(this.r1i)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::CHOICE_OP`
  String? fj() {
    if (this.pos case var from) {
      if (this.f19() case _?) {
        if (this.f43() case _) {
          if (this.pos case var to) {
            if (this.buffer.substring(from, to) case var span) {
              return span;
            }
          }
        }
      }
    }
  }

  /// `global::#`
  String? fk() {
    if (this.apply(this.r1i)! case _) {
      if (this.matchPattern(_string.$7) case var $1?) {
        if (this.apply(this.r1i)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::..`
  String? fl() {
    if (this.apply(this.r1i)! case _) {
      if (this.matchPattern(_string.$8) case var $1?) {
        if (this.apply(this.r1i)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::=>`
  String? fm() {
    if (this.apply(this.r1i)! case _) {
      if (this.matchPattern(_string.$9) case var $1?) {
        if (this.apply(this.r1i)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::~>`
  String? fn() {
    if (this.apply(this.r1i)! case _) {
      if (this.matchPattern(_string.$10) case var $1?) {
        if (this.apply(this.r1i)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::<~`
  String? fo() {
    if (this.apply(this.r1i)! case _) {
      if (this.matchPattern(_string.$11) case var $1?) {
        if (this.apply(this.r1i)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::|>`
  String? fp() {
    if (this.apply(this.r1i)! case _) {
      if (this.matchPattern(_string.$12) case var $1?) {
        if (this.apply(this.r1i)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::%`
  String? fq() {
    if (this.apply(this.r1i)! case _) {
      if (this.matchPattern(_string.$13) case var $1?) {
        if (this.apply(this.r1i)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::@`
  String? fr() {
    if (this.apply(this.r1i)! case _) {
      if (this.matchPattern(_string.$14) case var $1?) {
        if (this.apply(this.r1i)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::<`
  String? fs() {
    if (this.apply(this.r1i)! case _) {
      if (this.matchPattern(_string.$15) case var $1?) {
        if (this.apply(this.r1i)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::>`
  String? ft() {
    if (this.apply(this.r1i)! case _) {
      if (this.matchPattern(_string.$16) case var $1?) {
        if (this.apply(this.r1i)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::[`
  String? fu() {
    if (this.apply(this.r1i)! case _) {
      if (this.matchPattern(_string.$17) case var $1?) {
        if (this.apply(this.r1i)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::]`
  String? fv() {
    if (this.apply(this.r1i)! case _) {
      if (this.matchPattern(_string.$5) case var $1?) {
        if (this.apply(this.r1i)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::{`
  String? fw() {
    if (this.apply(this.r1i)! case _) {
      if (this.matchPattern(_string.$18) case var $1?) {
        if (this.apply(this.r1i)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::(`
  String? fx() {
    if (this.apply(this.r1i)! case _) {
      if (this.matchPattern(_string.$19) case var $1?) {
        if (this.apply(this.r1i)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::)`
  String? fy() {
    if (this.apply(this.r1i)! case _) {
      if (this.matchPattern(_string.$20) case var $1?) {
        if (this.apply(this.r1i)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::}`
  String? fz() {
    if (this.apply(this.r1i)! case _) {
      if (this.matchPattern(_string.$21) case var $1?) {
        if (this.apply(this.r1i)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::;`
  String? f10() {
    if (this.apply(this.r1i)! case _) {
      if (this.matchPattern(_string.$22) case var $1?) {
        if (this.apply(this.r1i)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::=`
  String? f11() {
    if (this.apply(this.r1i)! case _) {
      if (this.matchPattern(_string.$23) case var $1?) {
        if (this.apply(this.r1i)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::?`
  String? f12() {
    if (this.apply(this.r1i)! case _) {
      if (this.matchPattern(_string.$24) case var $1?) {
        if (this.apply(this.r1i)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::!`
  String? f13() {
    if (this.apply(this.r1i)! case _) {
      if (this.matchPattern(_string.$25) case var $1?) {
        if (this.apply(this.r1i)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::~`
  String? f14() {
    if (this.apply(this.r1i)! case _) {
      if (this.matchPattern(_string.$26) case var $1?) {
        if (this.apply(this.r1i)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::&`
  String? f15() {
    if (this.apply(this.r1i)! case _) {
      if (this.matchPattern(_string.$27) case var $1?) {
        if (this.apply(this.r1i)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::*`
  String? f16() {
    if (this.apply(this.r1i)! case _) {
      if (this.matchPattern(_string.$28) case var $1?) {
        if (this.apply(this.r1i)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::+`
  String? f17() {
    if (this.apply(this.r1i)! case _) {
      if (this.matchPattern(_string.$29) case var $1?) {
        if (this.apply(this.r1i)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::,`
  String? f18() {
    if (this.apply(this.r1i)! case _) {
      if (this.matchPattern(_string.$30) case var $1?) {
        if (this.apply(this.r1i)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::|`
  String? f19() {
    if (this.apply(this.r1i)! case _) {
      if (this.matchPattern(_string.$31) case var $1?) {
        if (this.apply(this.r1i)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::.`
  String? f1a() {
    if (this.apply(this.r1i)! case _) {
      if (this.matchPattern(_string.$32) case var $1?) {
        if (this.apply(this.r1i)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::ε`
  String? f1b() {
    if (this.apply(this.r1i)! case _) {
      if (this.matchPattern(_string.$33) case var $1?) {
        if (this.apply(this.r1i)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::^`
  String? f1c() {
    if (this.apply(this.r1i)! case _) {
      if (this.matchPattern(_string.$34) case var $1?) {
        if (this.apply(this.r1i)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::$`
  String? f1d() {
    if (this.apply(this.r1i)! case _) {
      if (this.matchPattern(_string.$35) case var $1?) {
        if (this.apply(this.r1i)! case _) {
          return $1;
        }
      }
    }
  }

  /// `ROOT`
  ParserGenerator? f1e() {
    if (this.apply(this.r0) case var $?) {
      return $;
    }
  }

  /// `global::untypedMacroChoice`
  late final f1f = () {
    if (this.f44() case var outer_decorator) {
      if (this.apply(this.r18) case var name?) {
        if (this.f11() case _?) {
          if (this.apply(this.r1h) case _?) {
            if (this.f45() case var inner_decorator) {
              if (this.fw() case _?) {
                if (this.apply(this.r2) case var _0?) {
                  if ([_0] case (var statements && var _l1)) {
                    for (;;) {
                      var _mark = this._mark();
                      if (this.apply(this.r1i)! case _) {
                        if (this.apply(this.r2) case var _0?) {
                          _l1.add(_0);
                          continue;
                        }
                      }
                      this._recover(_mark);
                      break;
                    }
                    if (this.fz() case _?) {
                      if (this.f46() case _) {
                        return HybridNamespaceStatement(
                          null,
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
  };

  /// `global::typedMacroChoice`
  late final f1g = () {
    if (this.f47() case var outer_decorator) {
      if (this.apply(this.r13) case var type?) {
        if (this.apply(this.r18) case var name?) {
          if (this.f11() case _?) {
            if (this.apply(this.r1h) case _?) {
              if (this.f48() case var inner_decorator) {
                if (this.fw() case _?) {
                  if (this.apply(this.r2) case var _0?) {
                    if ([_0] case (var statements && var _l1)) {
                      for (;;) {
                        var _mark = this._mark();
                        if (this.apply(this.r1i)! case _) {
                          if (this.apply(this.r2) case var _0?) {
                            _l1.add(_0);
                            continue;
                          }
                        }
                        this._recover(_mark);
                        break;
                      }
                      if (this.fz() case _?) {
                        if (this.f49() case _) {
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
  };

  /// `global::unnamedTypedMacroChoice`
  late final f1h = () {
    if (this.f4a() case var outer_decorator) {
      if (this.f4b() case var type) {
        if (this.fx() case _?) {
          if (this.fy() case _?) {
            if (this.f11() case _?) {
              if (this.apply(this.r1h) case _?) {
                if (this.f4c() case var inner_decorator) {
                  if (this.fw() case _?) {
                    if (this.apply(this.r2) case var _0?) {
                      if ([_0] case (var statements && var _l1)) {
                        for (;;) {
                          var _mark = this._mark();
                          if (this.apply(this.r1i)! case _) {
                            if (this.apply(this.r2) case var _0?) {
                              _l1.add(_0);
                              continue;
                            }
                          }
                          this._recover(_mark);
                          break;
                        }
                        if (this.fz() case _?) {
                          if (this.f4d() case _) {
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
  };

  /// `global::namespace`
  late final f1i = () {
    if (this.f4e() case var decorator) {
      if (this.f4f() case var name) {
        if (this.fw() case _?) {
          if (this.apply(this.r2) case var _0?) {
            if ([_0] case (var statements && var _l1)) {
              for (;;) {
                var _mark = this._mark();
                if (this.apply(this.r1i)! case _) {
                  if (this.apply(this.r2) case var _0?) {
                    _l1.add(_0);
                    continue;
                  }
                }
                this._recover(_mark);
                break;
              }
              if (this.fz() case _?) {
                return NamespaceStatement(name, statements, tag: decorator);
              }
            }
          }
        }
      }
    }
  };

  /// `global::typeDeclaration`
  late final f1j = () {
    if (this.f4g() case var decorator) {
      if (this.f4h() case var type) {
        if (this.apply(this.r15) case var _0?) {
          if ([_0] case (var names && var _l1)) {
            for (;;) {
              var _mark = this._mark();
              if (this.f18() case _?) {
                if (this.apply(this.r15) case var _0?) {
                  _l1.add(_0);
                  continue;
                }
              }
              this._recover(_mark);
              break;
            }
            if (this.f10() case _?) {
              return DeclarationTypeStatement(type, names, tag: decorator);
            }
          }
        }
      }
    }
  };

  /// `global::typedRule`
  late final f1k = () {
    if (this.f4i() case var decorator) {
      if (this.apply(this.r13) case var type?) {
        if (this.apply(this.r15) case var name?) {
          if (this.f11() case _?) {
            if (this.apply(this.r3) case var body?) {
              if (this.f10() case _?) {
                return DeclarationStatement(type, name, body, tag: decorator);
              }
            }
          }
        }
      }
    }
  };

  /// `global::untypedRule`
  late final f1l = () {
    if (this.f4j() case var decorator) {
      if (this.apply(this.r15) case var name?) {
        if (this.f11() case _?) {
          if (this.apply(this.r3) case var body?) {
            if (this.f10() case _?) {
              return DeclarationStatement(null, name, body, tag: decorator);
            }
          }
        }
      }
    }
  };

  /// `global::code::_curly`
  late final f1m = () {
    var _mark = this._mark();
    if (this.f4l() case var _0) {
      if ([if (_0 case var _0?) _0] case (var $ && var _l1)) {
        if (_l1.isNotEmpty) {
          for (;;) {
            var _mark = this._mark();
            if (this.f4l() case var _0?) {
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
  };

  /// `global::dart::literal::string::body`
  late final f1n = () {
    var _mark = this._mark();
    if (this.matchPattern(_string.$37) case var _2?) {
      if ([_2].nullable() case var _l3) {
        if (_l3 != null) {
          while (_l3.length < 1) {
            var _mark = this._mark();
            if (this.matchPattern(_string.$37) case var _2?) {
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
          if (this.matchPattern(_string.$36) case var $1?) {
            var _mark = this._mark();
            if (this.f4m() case var _0) {
              if ([if (_0 case var _0?) _0] case (var $2 && var _l1)) {
                if (_l1.isNotEmpty) {
                  for (;;) {
                    var _mark = this._mark();
                    if (this.f4m() case var _0?) {
                      _l1.add(_0);
                      continue;
                    }
                    this._recover(_mark);
                    break;
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
    this._recover(_mark);
    if (this.matchPattern(_string.$37) case var _6?) {
      if ([_6].nullable() case var _l7) {
        if (_l7 != null) {
          while (_l7.length < 1) {
            var _mark = this._mark();
            if (this.matchPattern(_string.$37) case var _6?) {
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
          if (this.matchPattern(_string.$38) case var $1?) {
            var _mark = this._mark();
            if (this.f4n() case var _4) {
              if ([if (_4 case var _4?) _4] case (var $2 && var _l5)) {
                if (_l5.isNotEmpty) {
                  for (;;) {
                    var _mark = this._mark();
                    if (this.f4n() case var _4?) {
                      _l5.add(_4);
                      continue;
                    }
                    this._recover(_mark);
                    break;
                  }
                } else {
                  this._recover(_mark);
                }
                if (this.matchPattern(_string.$38) case var $3?) {
                  return ($0, $1, $2, $3);
                }
              }
            }
          }
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$37) case var _10?) {
      if ([_10].nullable() case var _l11) {
        if (_l11 != null) {
          while (_l11.length < 1) {
            var _mark = this._mark();
            if (this.matchPattern(_string.$37) case var _10?) {
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
          if (this.matchPattern(_string.$39) case var $1?) {
            var _mark = this._mark();
            if (this.f4o() case var _8) {
              if ([if (_8 case var _8?) _8] case (var $2 && var _l9)) {
                if (_l9.isNotEmpty) {
                  for (;;) {
                    var _mark = this._mark();
                    if (this.f4o() case var _8?) {
                      _l9.add(_8);
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
    if (this.matchPattern(_string.$37) case var _14?) {
      if ([_14].nullable() case var _l15) {
        if (_l15 != null) {
          while (_l15.length < 1) {
            var _mark = this._mark();
            if (this.matchPattern(_string.$37) case var _14?) {
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
          if (this.matchPattern(_string.$40) case var $1?) {
            var _mark = this._mark();
            if (this.f4p() case var _12) {
              if ([if (_12 case var _12?) _12] case (var $2 && var _l13)) {
                if (_l13.isNotEmpty) {
                  for (;;) {
                    var _mark = this._mark();
                    if (this.f4p() case var _12?) {
                      _l13.add(_12);
                      continue;
                    }
                    this._recover(_mark);
                    break;
                  }
                } else {
                  this._recover(_mark);
                }
                if (this.matchPattern(_string.$40) case var $3?) {
                  return ($0, $1, $2, $3);
                }
              }
            }
          }
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$36) case var $0?) {
      var _mark = this._mark();
      if (this.f4q() case var _16) {
        if ([if (_16 case var _16?) _16] case (var $1 && var _l17)) {
          if (_l17.isNotEmpty) {
            for (;;) {
              var _mark = this._mark();
              if (this.f4q() case var _16?) {
                _l17.add(_16);
                continue;
              }
              this._recover(_mark);
              break;
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
    this._recover(_mark);
    if (this.matchPattern(_string.$38) case var $0?) {
      var _mark = this._mark();
      if (this.f4r() case var _18) {
        if ([if (_18 case var _18?) _18] case (var $1 && var _l19)) {
          if (_l19.isNotEmpty) {
            for (;;) {
              var _mark = this._mark();
              if (this.f4r() case var _18?) {
                _l19.add(_18);
                continue;
              }
              this._recover(_mark);
              break;
            }
          } else {
            this._recover(_mark);
          }
          if (this.matchPattern(_string.$38) case var $2?) {
            return ($0, $1, $2);
          }
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$39) case var $0?) {
      var _mark = this._mark();
      if (this.f4s() case var _20) {
        if ([if (_20 case var _20?) _20] case (var $1 && var _l21)) {
          if (_l21.isNotEmpty) {
            for (;;) {
              var _mark = this._mark();
              if (this.f4s() case var _20?) {
                _l21.add(_20);
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
    if (this.matchPattern(_string.$40) case var $0?) {
      var _mark = this._mark();
      if (this.f4t() case var _22) {
        if ([if (_22 case var _22?) _22] case (var $1 && var _l23)) {
          if (_l23.isNotEmpty) {
            for (;;) {
              var _mark = this._mark();
              if (this.f4t() case var _22?) {
                _l23.add(_22);
                continue;
              }
              this._recover(_mark);
              break;
            }
          } else {
            this._recover(_mark);
          }
          if (this.matchPattern(_string.$40) case var $2?) {
            return ($0, $1, $2);
          }
        }
      }
    }
  };

  /// `fragment0`
  late final f1o = () {
    if (this.apply(this.r1) case var $?) {
      return $;
    }
  };

  /// `fragment1`
  late final f1p = () {
    if (this.apply(this.r1i)! case var $) {
      return $;
    }
  };

  /// `fragment2`
  late final f1q = () {
    if (this.fj() case var $?) {
      return $;
    }
  };

  /// `fragment3`
  late final f1r = () {
    if (this.apply(this.r1i)! case _) {
      if (this.matchPattern(_string.$12) case var $1?) {
        if (this.apply(this.r1i)! case _) {
          return $1;
        }
      }
    }
  };

  /// `fragment4`
  late final f1s = () {
    if (this.apply(this.r1i)! case _) {
      if (this.matchPattern(_string.$9) case var $1?) {
        if (this.apply(this.r1i)! case _) {
          return $1;
        }
      }
    }
  };

  /// `fragment5`
  late final f1t = () {
    if (this.apply(this.r1i)! case _) {
      if (this.matchPattern(_string.$14) case var $1?) {
        if (this.apply(this.r1i)! case _) {
          return $1;
        }
      }
    }
  };

  /// `fragment6`
  late final f1u = () {
    if (this.f1t() case _?) {
      if (this.apply(this.r1a) case var $1?) {
        return $1;
      }
    }
  };

  /// `fragment7`
  late final f1v = () {
    if (this.apply(this.r1i)! case _) {
      if (this.matchPattern(_string.$10) case var $1?) {
        if (this.apply(this.r1i)! case _) {
          return $1;
        }
      }
    }
  };

  /// `fragment8`
  late final f1w = () {
    if (this.apply(this.r1i)! case _) {
      if (this.matchPattern(_string.$26) case var $1?) {
        if (this.apply(this.r1i)! case _) {
          return $1;
        }
      }
    }
  };

  /// `fragment9`
  late final f1x = () {
    if (this.apply(this.r1i)! case _) {
      if (this.matchPattern(_string.$27) case var $1?) {
        if (this.apply(this.r1i)! case _) {
          return $1;
        }
      }
    }
  };

  /// `fragment10`
  late final f1y = () {
    if (this.apply(this.r1i)! case _) {
      if (this.matchPattern(_string.$25) case var $1?) {
        if (this.apply(this.r1i)! case _) {
          return $1;
        }
      }
    }
  };

  /// `fragment11`
  late final f1z = () {
    if (this.pos case var from) {
      if (this.matchPattern(_string.$4) case _?) {
        if (this.matchPattern(_string.$41) case _?) {
          if (this.pos case var to) {
            if (this.buffer.substring(from, to) case var span) {
              return span;
            }
          }
        }
      }
    }
  };

  /// `fragment12`
  late final f20 = () {
    if (this.pos case var from) {
      if (this.matchPattern(_string.$4) case _?) {
        if (this.matchPattern(_string.$42) case _?) {
          if (this.pos case var to) {
            if (this.buffer.substring(from, to) case var span) {
              return span;
            }
          }
        }
      }
    }
  };

  /// `fragment13`
  late final f21 = () {
    if (this.pos case var from) {
      if (this.matchPattern(_string.$4) case _?) {
        if (this.matchPattern(_string.$43) case _?) {
          if (this.pos case var to) {
            if (this.buffer.substring(from, to) case var span) {
              return span;
            }
          }
        }
      }
    }
  };

  /// `fragment14`
  late final f22 = () {
    if (this.pos case var from) {
      if (this.matchPattern(_string.$4) case _?) {
        if (this.matchPattern(_string.$44) case _?) {
          if (this.pos case var to) {
            if (this.buffer.substring(from, to) case var span) {
              return span;
            }
          }
        }
      }
    }
  };

  /// `fragment15`
  late final f23 = () {
    if (this.pos case var from) {
      if (this.matchPattern(_string.$4) case _?) {
        if (this.matchPattern(_string.$45) case _?) {
          if (this.pos case var to) {
            if (this.buffer.substring(from, to) case var span) {
              return span;
            }
          }
        }
      }
    }
  };

  /// `fragment16`
  late final f24 = () {
    if (this.pos case var from) {
      if (this.matchPattern(_string.$4) case _?) {
        if (this.matchPattern(_string.$46) case _?) {
          if (this.pos case var to) {
            if (this.buffer.substring(from, to) case var span) {
              return span;
            }
          }
        }
      }
    }
  };

  /// `fragment17`
  late final f25 = () {
    var _mark = this._mark();
    if (this.matchPattern(_string.$2) case var $?) {
      return {(32, 32)};
    }
    this._recover(_mark);
    if (this.f7() case var $?) {
      return {(48, 57)};
    }
    this._recover(_mark);
    if (this.f9() case var $?) {
      return {(64 + 1, 64 + 26), (96 + 1, 96 + 26)};
    }
    this._recover(_mark);
    if (this.fb() case var $?) {
      return {(9, 13), (32, 32)};
    }
    this._recover(_mark);
    if (this.fe() case var $?) {
      return {(10, 10)};
    }
    this._recover(_mark);
    if (this.ff() case var $?) {
      return {(13, 13)};
    }
    this._recover(_mark);
    if (this.fg() case var $?) {
      return {(9, 9)};
    }
    this._recover(_mark);
    if (this.f6() case var $?) {
      return {(92, 92)};
    }
    this._recover(_mark);
    if (this.f4() case var l?) {
      if (this.matchPattern(_string.$3) case _?) {
        if (this.f4() case var r?) {
          return {(l.codeUnitAt(0), r.codeUnitAt(0))};
        }
      }
    }
    this._recover(_mark);
    if (this.f4() case var $?) {
      return {($.codeUnitAt(0), $.codeUnitAt(0))};
    }
  };

  /// `fragment18`
  late final f26 = () {
    if (this.matchPattern(_string.$17) case _?) {
      if (this.f25() case var _0?) {
        if ([_0] case (var $1 && var elements && var _l1)) {
          for (;;) {
            var _mark = this._mark();
            if (this.f25() case var _0?) {
              _l1.add(_0);
              continue;
            }
            this._recover(_mark);
            break;
          }
          if (this.matchPattern(_string.$5) case _?) {
            return elements.expand((e) => e).toSet();
          }
        }
      }
    }
  };

  /// `fragment19`
  late final f27 = () {
    var _mark = this._mark();
    if (this.matchPattern(_string.$4) case _?) {
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $1) {
          if ($1 case var $) {
            return r"\" + $;
          }
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
  };

  /// `fragment20`
  late final f28 = () {
    if (this.f27() case var _0?) {
      if ([_0] case (var $ && var _l1)) {
        for (;;) {
          var _mark = this._mark();
          if (this.f27() case var _0?) {
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

  /// `fragment21`
  late final f29 = () {
    var _mark = this._mark();
    if (this.matchPattern(_string.$36) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  };

  /// `fragment22`
  late final f2a = () {
    var _mark = this._mark();
    if (this.matchPattern(_string.$38) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  };

  /// `fragment23`
  late final f2b = () {
    var _mark = this._mark();
    if (this.matchPattern(_string.$39) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  };

  /// `fragment24`
  late final f2c = () {
    var _mark = this._mark();
    if (this.matchPattern(_string.$40) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  };

  /// `fragment25`
  late final f2d = () {
    var _mark = this._mark();
    if (this.matchPattern(_string.$4) case _?) {
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $1) {
          return $1;
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$36) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  };

  /// `fragment26`
  late final f2e = () {
    var _mark = this._mark();
    if (this.matchPattern(_string.$4) case _?) {
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $1) {
          return $1;
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$38) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  };

  /// `fragment27`
  late final f2f = () {
    var _mark = this._mark();
    if (this.matchPattern(_string.$4) case _?) {
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $1) {
          return $1;
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
  };

  /// `fragment28`
  late final f2g = () {
    var _mark = this._mark();
    if (this.matchPattern(_string.$4) case _?) {
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $1) {
          return $1;
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$40) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  };

  /// `fragment29`
  late final f2h = () {
    var _mark = this._mark();
    if (this.matchPattern(_string.$47) case _?) {
      var _mark = this._mark();
      if (this.f29() case var _0) {
        if ([if (_0 case var _0?) _0] case (var $1 && var _l1)) {
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
          if (this.matchPattern(_string.$36) case _?) {
            if ($1 case var $) {
              return $.join();
            }
          }
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$48) case _?) {
      var _mark = this._mark();
      if (this.f2a() case var _2) {
        if ([if (_2 case var _2?) _2] case (var $1 && var _l3)) {
          if (_l3.isNotEmpty) {
            for (;;) {
              var _mark = this._mark();
              if (this.f2a() case var _2?) {
                _l3.add(_2);
                continue;
              }
              this._recover(_mark);
              break;
            }
          } else {
            this._recover(_mark);
          }
          if (this.matchPattern(_string.$38) case _?) {
            if ($1 case var $) {
              return $.join();
            }
          }
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$49) case _?) {
      var _mark = this._mark();
      if (this.f2b() case var _4) {
        if ([if (_4 case var _4?) _4] case (var $1 && var _l5)) {
          if (_l5.isNotEmpty) {
            for (;;) {
              var _mark = this._mark();
              if (this.f2b() case var _4?) {
                _l5.add(_4);
                continue;
              }
              this._recover(_mark);
              break;
            }
          } else {
            this._recover(_mark);
          }
          if (this.matchPattern(_string.$39) case _?) {
            if ($1 case var $) {
              return $.join();
            }
          }
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$50) case _?) {
      var _mark = this._mark();
      if (this.f2c() case var _6) {
        if ([if (_6 case var _6?) _6] case (var $1 && var _l7)) {
          if (_l7.isNotEmpty) {
            for (;;) {
              var _mark = this._mark();
              if (this.f2c() case var _6?) {
                _l7.add(_6);
                continue;
              }
              this._recover(_mark);
              break;
            }
          } else {
            this._recover(_mark);
          }
          if (this.matchPattern(_string.$40) case _?) {
            if ($1 case var $) {
              return $.join();
            }
          }
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$36) case _?) {
      var _mark = this._mark();
      if (this.f2d() case var _8) {
        if ([if (_8 case var _8?) _8] case (var $1 && var _l9)) {
          if (_l9.isNotEmpty) {
            for (;;) {
              var _mark = this._mark();
              if (this.f2d() case var _8?) {
                _l9.add(_8);
                continue;
              }
              this._recover(_mark);
              break;
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
    this._recover(_mark);
    if (this.matchPattern(_string.$38) case _?) {
      var _mark = this._mark();
      if (this.f2e() case var _10) {
        if ([if (_10 case var _10?) _10] case (var $1 && var _l11)) {
          if (_l11.isNotEmpty) {
            for (;;) {
              var _mark = this._mark();
              if (this.f2e() case var _10?) {
                _l11.add(_10);
                continue;
              }
              this._recover(_mark);
              break;
            }
          } else {
            this._recover(_mark);
          }
          if (this.matchPattern(_string.$38) case _?) {
            if ($1 case var $) {
              return $.join();
            }
          }
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$39) case _?) {
      var _mark = this._mark();
      if (this.f2f() case var _12) {
        if ([if (_12 case var _12?) _12] case (var $1 && var _l13)) {
          if (_l13.isNotEmpty) {
            for (;;) {
              var _mark = this._mark();
              if (this.f2f() case var _12?) {
                _l13.add(_12);
                continue;
              }
              this._recover(_mark);
              break;
            }
          } else {
            this._recover(_mark);
          }
          if (this.matchPattern(_string.$39) case _?) {
            if ($1 case var $) {
              return $.join();
            }
          }
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$40) case _?) {
      var _mark = this._mark();
      if (this.f2g() case var _14) {
        if ([if (_14 case var _14?) _14] case (var $1 && var _l15)) {
          if (_l15.isNotEmpty) {
            for (;;) {
              var _mark = this._mark();
              if (this.f2g() case var _14?) {
                _l15.add(_14);
                continue;
              }
              this._recover(_mark);
              break;
            }
          } else {
            this._recover(_mark);
          }
          if (this.matchPattern(_string.$40) case _?) {
            if ($1 case var $) {
              return $.join();
            }
          }
        }
      }
    }
  };

  /// `fragment30`
  late final f2i = () {
    var _mark = this._mark();
    if (this.matchPattern(_regexp.$1) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.matchPattern(_regexp.$2) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$22) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$20) case var $?) {
      return $;
    }
  };

  /// `fragment31`
  late final f2j = () {
    var _mark = this._mark();
    if (this.apply(this.rg) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$18) case _?) {
      if (this.apply(this.rf)! case var $1) {
        if (this.matchPattern(_string.$21) case _?) {
          if ($1 case var $) {
            return "{" + $ + "}";
          }
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$19) case _?) {
      if (this.apply(this.rf)! case var $1) {
        if (this.matchPattern(_string.$20) case _?) {
          if ($1 case var $) {
            return "(" + $ + ")";
          }
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$17) case _?) {
      if (this.apply(this.rf)! case var $1) {
        if (this.matchPattern(_string.$5) case _?) {
          if ($1 case var $) {
            return "[" + $ + "]";
          }
        }
      }
    }
    this._recover(_mark);
    if (this.f2i() case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  };

  /// `fragment32`
  late final f2k = () {
    var _mark = this._mark();
    if (this.matchPattern(_string.$21) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$20) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$5) case var $?) {
      return $;
    }
  };

  /// `fragment33`
  late final f2l = () {
    var _mark = this._mark();
    if (this.apply(this.rg) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$18) case _?) {
      if (this.apply(this.rf)! case var $1) {
        if (this.matchPattern(_string.$21) case _?) {
          if ($1 case var $) {
            return "{" + $ + "}";
          }
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$19) case _?) {
      if (this.apply(this.rf)! case var $1) {
        if (this.matchPattern(_string.$20) case _?) {
          if ($1 case var $) {
            return "(" + $ + ")";
          }
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$17) case _?) {
      if (this.apply(this.rf)! case var $1) {
        if (this.matchPattern(_string.$5) case _?) {
          if ($1 case var $) {
            return "[" + $ + "]";
          }
        }
      }
    }
    this._recover(_mark);
    if (this.f2k() case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  };

  /// `fragment34`
  late final f2m = () {
    if (this.pos case var from) {
      if (this.f1n() case var $?) {
        if (this.pos case var to) {
          if (this.buffer.substring(from, to) case var span) {
            return span;
          }
        }
      }
    }
  };

  /// `fragment35`
  late final f2n = () {
    var _mark = this._mark();
    if (this.apply(this.rg) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$18) case _?) {
      if (this.apply(this.rj)! case (var $1 && var $)) {
        if (this.matchPattern(_string.$21) case _?) {
          if ($1 case var $) {
            return "{" + $ + "}";
          }
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
  };

  /// `fragment36`
  late final f2o = () {
    if (this.f12() case var $?) {
      return $;
    }
  };

  /// `fragment37`
  late final f2p = () {
    if (this.apply(this.rk) case var _0?) {
      if ([_0] case (var $ && var _l1)) {
        for (;;) {
          var _mark = this._mark();
          if (this.f18() case _?) {
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
  };

  /// `fragment38`
  late final f2q = () {
    if (this.f18() case var $?) {
      return $;
    }
  };

  /// `fragment39`
  late final f2r = () {
    if (this.f18() case var $?) {
      return $;
    }
  };

  /// `fragment40`
  late final f2s = () {
    if (this.apply(this.r1i)! case _) {
      if (this.matchPattern(_string.$17) case var $1?) {
        if (this.apply(this.r1i)! case _) {
          return $1;
        }
      }
    }
  };

  /// `fragment41`
  late final f2t = () {
    if (this.f18() case var $?) {
      return $;
    }
  };

  /// `fragment42`
  late final f2u = () {
    if (this.apply(this.r1i)! case _) {
      if (this.matchPattern(_string.$5) case var $1?) {
        if (this.apply(this.r1i)! case _) {
          return $1;
        }
      }
    }
  };

  /// `fragment43`
  late final f2v = () {
    if (this.f18() case var $?) {
      return $;
    }
  };

  /// `fragment44`
  late final f2w = () {
    if (this.apply(this.r18) case var $?) {
      return $;
    }
  };

  /// `fragment45`
  late final f2x = () {
    if (this.apply(this.rk) case var $0?) {
      if (this.apply(this.r1i)! case _) {
        return $0;
      }
    }
  };

  /// `fragment46`
  late final f2y = () {
    var _mark = this._mark();
    if (this.matchPattern(_string.$51) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$8) case (var $0 && null)) {
      this._recover(_mark);
      if (this.matchPattern(_string.$32) case var $1?) {
        return ($0, $1);
      }
    }
  };

  /// `fragment47`
  late final f2z = () {
    if (this.apply(this.r18) case (var $0 && var identifier)?) {
      if (this.f2y() case _?) {
        var _mark = this._mark();
        if (this.apply(this.r1g) case null) {
          this._recover(_mark);
          return $0;
        }
      }
    }
  };

  /// `fragment48`
  late final f30 = () {
    var _mark = this._mark();
    if (this.matchPattern(_string.$6) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  };

  /// `fragment49`
  late final f31 = () {
    if (this.matchPattern(_string.$6) case _?) {
      var _mark = this._mark();
      if (this.f30() case var _0) {
        if ([if (_0 case var _0?) _0] case (var $1 && var _l1)) {
          if (_l1.isNotEmpty) {
            for (;;) {
              var _mark = this._mark();
              if (this.f30() case var _0?) {
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
            if ($1 case var $) {
              return $.join();
            }
          }
        }
      }
    }
  };

  /// `fragment50`
  late final f32 = () {
    var _mark = this._mark();
    if (this.matchPattern(_string.$6) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  };

  /// `fragment51`
  late final f33 = () {
    if (this.pos case var from) {
      if (this.f32() case var _0) {
        var _mark = this._mark();
        var _l1 = [if (_0 case var _0?) _0];
        if (_l1.isNotEmpty) {
          for (;;) {
            var _mark = this._mark();
            if (this.f32() case var _0?) {
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
  late final f34 = () {
    var _mark = this._mark();
    if (this.matchPattern(_string.$52) case var $?) {
      return Tag.rule;
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$53) case var $?) {
      return Tag.fragment;
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$54) case var $?) {
      return Tag.inline;
    }
  };

  /// `fragment53`
  late final f35 = () {
    var _mark = this._mark();
    if (this.apply(this.r1j) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$1) case var $0?) {
      this._recover(_mark);
      if (this.apply(this.r1k) case var $1?) {
        return ($0, $1);
      }
    }
  };

  /// `fragment54`
  late final f36 = () {
    if (this.matchPattern(_regexp.$1) case var $?) {
      return $;
    }
  };

  /// `fragment55`
  late final f37 = () {
    if (this.matchPattern(_regexp.$1) case var $?) {
      return $;
    }
  };

  /// `fragment56`
  late final f38 = () {
    var _mark = this._mark();
    if (this.f36() case var $0) {
      if (this.matchPattern(_regexp.$2) case var $1?) {
        if (this.f37() case var $2) {
          return ($0, $1, $2);
        }
      }
    }
    this._recover(_mark);
    if (this.pos case var $ when this.pos >= this.buffer.length) {
      return $;
    }
  };

  /// `fragment57`
  late final f39 = () {
    var _mark = this._mark();
    if (this.f38() case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  };

  /// `fragment58`
  late final f3a = () {
    var _mark = this._mark();
    if (this.matchPattern(_string.$55) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  };

  /// `fragment59`
  late final f3b = () {
    var _mark = this._mark();
    if (this.matchPattern(_string.$4) case _?) {
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $1) {
          if ($1 case var $) {
            return r"\" + $;
          }
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
  };

  /// `fragment60`
  late final f3c = () {
    if (this.f3b() case var _0?) {
      if ([_0] case (var $ && var _l1)) {
        for (;;) {
          var _mark = this._mark();
          if (this.f3b() case var _0?) {
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

  /// `fragment61`
  late final f3d = () {
    var _mark = this._mark();
    if (this.matchPattern(_string.$36) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  };

  /// `fragment62`
  late final f3e = () {
    var _mark = this._mark();
    if (this.matchPattern(_string.$38) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  };

  /// `fragment63`
  late final f3f = () {
    var _mark = this._mark();
    if (this.matchPattern(_string.$39) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  };

  /// `fragment64`
  late final f3g = () {
    var _mark = this._mark();
    if (this.matchPattern(_string.$40) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  };

  /// `fragment65`
  late final f3h = () {
    var _mark = this._mark();
    if (this.matchPattern(_string.$4) case _?) {
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $1) {
          return $1;
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$36) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  };

  /// `fragment66`
  late final f3i = () {
    var _mark = this._mark();
    if (this.matchPattern(_string.$4) case _?) {
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $1) {
          return $1;
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$38) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  };

  /// `fragment67`
  late final f3j = () {
    var _mark = this._mark();
    if (this.matchPattern(_string.$4) case _?) {
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $1) {
          return $1;
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
  };

  /// `fragment68`
  late final f3k = () {
    var _mark = this._mark();
    if (this.matchPattern(_string.$4) case _?) {
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $1) {
          return $1;
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$40) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  };

  /// `fragment69`
  late final f3l = () {
    var _mark = this._mark();
    if (this.matchPattern(_string.$47) case _?) {
      var _mark = this._mark();
      if (this.f3d() case var _0) {
        if ([if (_0 case var _0?) _0] case (var $1 && var _l1)) {
          if (_l1.isNotEmpty) {
            for (;;) {
              var _mark = this._mark();
              if (this.f3d() case var _0?) {
                _l1.add(_0);
                continue;
              }
              this._recover(_mark);
              break;
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
    this._recover(_mark);
    if (this.matchPattern(_string.$48) case _?) {
      var _mark = this._mark();
      if (this.f3e() case var _2) {
        if ([if (_2 case var _2?) _2] case (var $1 && var _l3)) {
          if (_l3.isNotEmpty) {
            for (;;) {
              var _mark = this._mark();
              if (this.f3e() case var _2?) {
                _l3.add(_2);
                continue;
              }
              this._recover(_mark);
              break;
            }
          } else {
            this._recover(_mark);
          }
          if (this.matchPattern(_string.$38) case _?) {
            if ($1 case var $) {
              return $.join();
            }
          }
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$49) case _?) {
      var _mark = this._mark();
      if (this.f3f() case var _4) {
        if ([if (_4 case var _4?) _4] case (var $1 && var _l5)) {
          if (_l5.isNotEmpty) {
            for (;;) {
              var _mark = this._mark();
              if (this.f3f() case var _4?) {
                _l5.add(_4);
                continue;
              }
              this._recover(_mark);
              break;
            }
          } else {
            this._recover(_mark);
          }
          if (this.matchPattern(_string.$39) case _?) {
            if ($1 case var $) {
              return $.join();
            }
          }
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$50) case _?) {
      var _mark = this._mark();
      if (this.f3g() case var _6) {
        if ([if (_6 case var _6?) _6] case (var $1 && var _l7)) {
          if (_l7.isNotEmpty) {
            for (;;) {
              var _mark = this._mark();
              if (this.f3g() case var _6?) {
                _l7.add(_6);
                continue;
              }
              this._recover(_mark);
              break;
            }
          } else {
            this._recover(_mark);
          }
          if (this.matchPattern(_string.$40) case _?) {
            if ($1 case var $) {
              return $.join();
            }
          }
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$36) case _?) {
      var _mark = this._mark();
      if (this.f3h() case var _8) {
        if ([if (_8 case var _8?) _8] case (var $1 && var _l9)) {
          if (_l9.isNotEmpty) {
            for (;;) {
              var _mark = this._mark();
              if (this.f3h() case var _8?) {
                _l9.add(_8);
                continue;
              }
              this._recover(_mark);
              break;
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
    this._recover(_mark);
    if (this.matchPattern(_string.$38) case _?) {
      var _mark = this._mark();
      if (this.f3i() case var _10) {
        if ([if (_10 case var _10?) _10] case (var $1 && var _l11)) {
          if (_l11.isNotEmpty) {
            for (;;) {
              var _mark = this._mark();
              if (this.f3i() case var _10?) {
                _l11.add(_10);
                continue;
              }
              this._recover(_mark);
              break;
            }
          } else {
            this._recover(_mark);
          }
          if (this.matchPattern(_string.$38) case _?) {
            if ($1 case var $) {
              return $.join();
            }
          }
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$39) case _?) {
      var _mark = this._mark();
      if (this.f3j() case var _12) {
        if ([if (_12 case var _12?) _12] case (var $1 && var _l13)) {
          if (_l13.isNotEmpty) {
            for (;;) {
              var _mark = this._mark();
              if (this.f3j() case var _12?) {
                _l13.add(_12);
                continue;
              }
              this._recover(_mark);
              break;
            }
          } else {
            this._recover(_mark);
          }
          if (this.matchPattern(_string.$39) case _?) {
            if ($1 case var $) {
              return $.join();
            }
          }
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$40) case _?) {
      var _mark = this._mark();
      if (this.f3k() case var _14) {
        if ([if (_14 case var _14?) _14] case (var $1 && var _l15)) {
          if (_l15.isNotEmpty) {
            for (;;) {
              var _mark = this._mark();
              if (this.f3k() case var _14?) {
                _l15.add(_14);
                continue;
              }
              this._recover(_mark);
              break;
            }
          } else {
            this._recover(_mark);
          }
          if (this.matchPattern(_string.$40) case _?) {
            if ($1 case var $) {
              return $.join();
            }
          }
        }
      }
    }
  };

  /// `fragment70`
  late final f3m = () {
    var _mark = this._mark();
    if (this.matchPattern(_string.$2) case var $?) {
      return {(32, 32)};
    }
    this._recover(_mark);
    if (this.f7() case var $?) {
      return {(48, 57)};
    }
    this._recover(_mark);
    if (this.f9() case var $?) {
      return {(64 + 1, 64 + 26), (96 + 1, 96 + 26)};
    }
    this._recover(_mark);
    if (this.fb() case var $?) {
      return {(9, 13), (32, 32)};
    }
    this._recover(_mark);
    if (this.fe() case var $?) {
      return {(10, 10)};
    }
    this._recover(_mark);
    if (this.ff() case var $?) {
      return {(13, 13)};
    }
    this._recover(_mark);
    if (this.fg() case var $?) {
      return {(9, 9)};
    }
    this._recover(_mark);
    if (this.f6() case var $?) {
      return {(92, 92)};
    }
    this._recover(_mark);
    if (this.f4() case var l?) {
      if (this.matchPattern(_string.$3) case _?) {
        if (this.f4() case var r?) {
          return {(l.codeUnitAt(0), r.codeUnitAt(0))};
        }
      }
    }
    this._recover(_mark);
    if (this.f4() case var $?) {
      return {($.codeUnitAt(0), $.codeUnitAt(0))};
    }
  };

  /// `fragment71`
  late final f3n = () {
    if (this.matchPattern(_string.$17) case _?) {
      if (this.f3m() case var _0?) {
        if ([_0] case (var $1 && var elements && var _l1)) {
          for (;;) {
            var _mark = this._mark();
            if (this.f3m() case var _0?) {
              _l1.add(_0);
              continue;
            }
            this._recover(_mark);
            break;
          }
          if (this.matchPattern(_string.$5) case _?) {
            return elements.expand((e) => e).toSet();
          }
        }
      }
    }
  };

  /// `fragment72`
  late final f3o = () {
    var _mark = this._mark();
    if (this.matchPattern(_string.$6) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  };

  /// `fragment73`
  late final f3p = () {
    if (this.pos case var from) {
      if (this.matchPattern(_string.$4) case _?) {
        if (this.matchPattern(_string.$4) case _?) {
          if (this.pos case var to) {
            if (this.buffer.substring(from, to) case var span) {
              return span;
            }
          }
        }
      }
    }
  };

  /// `fragment74`
  late final f3q = () {
    if (this.f3p() case var $0?) {
      if (this.apply(this.r1i)! case _) {
        return $0;
      }
    }
  };

  /// `fragment75`
  late final f3r = () {
    if (this.pos case var from) {
      if (this.matchPattern(_string.$4) case _?) {
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

  /// `fragment76`
  late final f3s = () {
    if (this.pos case var from) {
      if (this.matchPattern(_string.$4) case _?) {
        if (this.matchPattern(_string.$41) case _?) {
          if (this.pos case var to) {
            if (this.buffer.substring(from, to) case var span) {
              return span;
            }
          }
        }
      }
    }
  };

  /// `fragment77`
  late final f3t = () {
    if (this.pos case var from) {
      if (this.matchPattern(_string.$4) case _?) {
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

  /// `fragment78`
  late final f3u = () {
    if (this.pos case var from) {
      if (this.matchPattern(_string.$4) case _?) {
        if (this.matchPattern(_string.$42) case _?) {
          if (this.pos case var to) {
            if (this.buffer.substring(from, to) case var span) {
              return span;
            }
          }
        }
      }
    }
  };

  /// `fragment79`
  late final f3v = () {
    if (this.pos case var from) {
      if (this.matchPattern(_string.$4) case _?) {
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

  /// `fragment80`
  late final f3w = () {
    if (this.pos case var from) {
      if (this.matchPattern(_string.$4) case _?) {
        if (this.matchPattern(_string.$43) case _?) {
          if (this.pos case var to) {
            if (this.buffer.substring(from, to) case var span) {
              return span;
            }
          }
        }
      }
    }
  };

  /// `fragment81`
  late final f3x = () {
    if (this.pos case var from) {
      if (this.matchPattern(_string.$4) case _?) {
        if (this.matchPattern(_string.$46) case _?) {
          if (this.pos case var to) {
            if (this.buffer.substring(from, to) case var span) {
              return span;
            }
          }
        }
      }
    }
  };

  /// `fragment82`
  late final f3y = () {
    if (this.pos case var from) {
      if (this.matchPattern(_string.$4) case _?) {
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

  /// `fragment83`
  late final f3z = () {
    if (this.pos case var from) {
      if (this.matchPattern(_string.$4) case _?) {
        if (this.matchPattern(_string.$37) case _?) {
          if (this.pos case var to) {
            if (this.buffer.substring(from, to) case var span) {
              return span;
            }
          }
        }
      }
    }
  };

  /// `fragment84`
  late final f40 = () {
    if (this.pos case var from) {
      if (this.matchPattern(_string.$4) case _?) {
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

  /// `fragment85`
  late final f41 = () {
    if (this.pos case var from) {
      if (this.matchPattern(_string.$4) case _?) {
        if (this.matchPattern(_string.$44) case _?) {
          if (this.pos case var to) {
            if (this.buffer.substring(from, to) case var span) {
              return span;
            }
          }
        }
      }
    }
  };

  /// `fragment86`
  late final f42 = () {
    if (this.pos case var from) {
      if (this.matchPattern(_string.$4) case _?) {
        if (this.matchPattern(_string.$45) case _?) {
          if (this.pos case var to) {
            if (this.buffer.substring(from, to) case var span) {
              return span;
            }
          }
        }
      }
    }
  };

  /// `fragment87`
  late final f43 = () {
    if (this.f19() case var $?) {
      return $;
    }
  };

  /// `fragment88`
  late final f44 = () {
    if (this.apply(this.r1b) case var $?) {
      return $;
    }
  };

  /// `fragment89`
  late final f45 = () {
    if (this.apply(this.r1b) case var $?) {
      return $;
    }
  };

  /// `fragment90`
  late final f46 = () {
    if (this.f10() case var $?) {
      return $;
    }
  };

  /// `fragment91`
  late final f47 = () {
    if (this.apply(this.r1b) case var $?) {
      return $;
    }
  };

  /// `fragment92`
  late final f48 = () {
    if (this.apply(this.r1b) case var $?) {
      return $;
    }
  };

  /// `fragment93`
  late final f49 = () {
    if (this.f10() case var $?) {
      return $;
    }
  };

  /// `fragment94`
  late final f4a = () {
    if (this.apply(this.r1b) case var $?) {
      return $;
    }
  };

  /// `fragment95`
  late final f4b = () {
    if (this.apply(this.r13) case var $?) {
      return $;
    }
  };

  /// `fragment96`
  late final f4c = () {
    if (this.apply(this.r1b) case var $?) {
      return $;
    }
  };

  /// `fragment97`
  late final f4d = () {
    if (this.f10() case var $?) {
      return $;
    }
  };

  /// `fragment98`
  late final f4e = () {
    if (this.apply(this.r1b) case var $?) {
      return $;
    }
  };

  /// `fragment99`
  late final f4f = () {
    if (this.apply(this.r18) case var $?) {
      return $;
    }
  };

  /// `fragment100`
  late final f4g = () {
    if (this.apply(this.r1b) case var $?) {
      return $;
    }
  };

  /// `fragment101`
  late final f4h = () {
    if (this.apply(this.r13) case var $?) {
      return $;
    }
  };

  /// `fragment102`
  late final f4i = () {
    if (this.apply(this.r1b) case var $?) {
      return $;
    }
  };

  /// `fragment103`
  late final f4j = () {
    if (this.apply(this.r1b) case var $?) {
      return $;
    }
  };

  /// `fragment104`
  late final f4k = () {
    var _mark = this._mark();
    if (this.matchPattern(_string.$21) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$22) case var $?) {
      return $;
    }
  };

  /// `fragment105`
  late final f4l = () {
    var _mark = this._mark();
    if (this.apply(this.rg) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$18) case _?) {
      if (this.apply(this.rf)! case var $1) {
        if (this.matchPattern(_string.$21) case _?) {
          if ($1 case var $) {
            return "{" + $ + "}";
          }
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$19) case _?) {
      if (this.apply(this.rf)! case var $1) {
        if (this.matchPattern(_string.$20) case _?) {
          if ($1 case var $) {
            return "(" + $ + ")";
          }
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$17) case _?) {
      if (this.apply(this.rf)! case var $1) {
        if (this.matchPattern(_string.$5) case _?) {
          if ($1 case var $) {
            return "[" + $ + "]";
          }
        }
      }
    }
    this._recover(_mark);
    if (this.f4k() case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  };

  /// `fragment106`
  late final f4m = () {
    var _mark = this._mark();
    if (this.matchPattern(_string.$36) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  };

  /// `fragment107`
  late final f4n = () {
    var _mark = this._mark();
    if (this.matchPattern(_string.$38) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  };

  /// `fragment108`
  late final f4o = () {
    var _mark = this._mark();
    if (this.matchPattern(_string.$39) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  };

  /// `fragment109`
  late final f4p = () {
    var _mark = this._mark();
    if (this.matchPattern(_string.$40) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  };

  /// `fragment110`
  late final f4q = () {
    var _mark = this._mark();
    if (this.matchPattern(_string.$4) case _?) {
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $1) {
          return $1;
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$35) case var $0?) {
      this._recover(_mark);
      if (this.apply(this.ri) case var $1?) {
        return ($0, $1);
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$36) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  };

  /// `fragment111`
  late final f4r = () {
    var _mark = this._mark();
    if (this.matchPattern(_string.$4) case _?) {
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $1) {
          return $1;
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$35) case var $0?) {
      this._recover(_mark);
      if (this.apply(this.ri) case var $1?) {
        return ($0, $1);
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$38) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  };

  /// `fragment112`
  late final f4s = () {
    var _mark = this._mark();
    if (this.matchPattern(_string.$4) case _?) {
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $1) {
          return $1;
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$35) case var $0?) {
      this._recover(_mark);
      if (this.apply(this.ri) case var $1?) {
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
  };

  /// `fragment113`
  late final f4t = () {
    var _mark = this._mark();
    if (this.matchPattern(_string.$4) case _?) {
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $1) {
          return $1;
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$35) case var $0?) {
      this._recover(_mark);
      if (this.apply(this.ri) case var $1?) {
        return ($0, $1);
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$40) case null) {
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
      if (this.f1o() case var $1) {
        if (this.apply(this.r2) case var _0?) {
          if ([_0] case (var $2 && var _l1)) {
            for (;;) {
              var _mark = this._mark();
              if (this.apply(this.r1i)! case _) {
                if (this.apply(this.r2) case var _0?) {
                  _l1.add(_0);
                  continue;
                }
              }
              this._recover(_mark);
              break;
            }
            if (this.f1p() case _) {
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
    if (this.fw() case _?) {
      if (this.apply(this.r1i)! case _) {
        if (this.apply(this.rd)! case (var $2 && var code)) {
          if (this.apply(this.r1i)! case _) {
            if (this.fz() case _?) {
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
    if (this.f1f() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.f1g() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.f1h() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.f1i() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.f1j() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.f1k() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.f1l() case var $?) {
      return $;
    }
  }

  /// `global::choice`
  Node? r3() {
    if (this.f1q() case _) {
      if (this.apply(this.r4) case var _0?) {
        if ([_0] case (var $1 && var options && var _l1)) {
          for (;;) {
            var _mark = this._mark();
            if (this.fj() case _?) {
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
    if (this.apply(this.r5) case var sequence?) {
      if (this.f1r() case _?) {
        if (this.apply(this.r1i)! case _) {
          if (this.apply(this.re)! case var code) {
            if (this.apply(this.r1i)! case _) {
              return inlineAction(sequence, code);
            }
          }
        }
      }
    }
    this._recover(_mark);
    if (this.apply(this.r5) case var sequence?) {
      if (this.f1s() case _?) {
        if (this.apply(this.r1i)! case _) {
          if (this.apply(this.re)! case var code) {
            if (this.apply(this.r1i)! case _) {
              return inlineAction(sequence, code);
            }
          }
        }
      }
    }
    this._recover(_mark);
    if (this.apply(this.r5) case var sequence?) {
      if (this.fw() case _?) {
        if (this.apply(this.r1i)! case _) {
          if (this.apply(this.rc)! case var code) {
            if (this.apply(this.r1i)! case _) {
              if (this.fz() case _?) {
                return inlineBlockAction(sequence, code);
              }
            }
          }
        }
      }
    }
    this._recover(_mark);
    if (this.apply(this.r5) case var sequence?) {
      if (this.fx() case _?) {
        if (this.fy() case _?) {
          if (this.fw() case _?) {
            if (this.apply(this.r1i)! case _) {
              if (this.apply(this.rc)! case var code) {
                if (this.apply(this.r1i)! case _) {
                  if (this.fz() case _?) {
                    return inlineBlockAction(sequence, code);
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
          if (this.apply(this.r1i)! case _) {
            if (this.apply(this.r6) case var _0?) {
              _l1.add(_0);
              continue;
            }
          }
          this._recover(_mark);
          break;
        }
        if (this.f1u() case var chosen) {
          return body.length == 1 ? body.single : SequenceNode(body, chosenIndex: chosen);
        }
      }
    }
  }

  /// `global::dropped`
  Node? r6() {
    var _mark = this._mark();
    if (this.apply(this.r6) case var captured?) {
      if (this.fo() case _?) {
        if (this.apply(this.r8) case var dropped?) {
          return SequenceNode([captured, dropped], chosenIndex: 0);
        }
      }
    }
    this._recover(_mark);
    if (this.apply(this.r8) case var dropped?) {
      if (this.f1v() case _?) {
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
    if (this.apply(this.r18) case var identifier?) {
      if (this.matchPattern(_string.$61) case _?) {
        if (this.apply(this.r1i)! case _) {
          if (this.apply(this.r8) case var special?) {
            return NamedNode(identifier, special);
          }
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$61) case _?) {
      if (this.apply(this.r17) case (var $1 && var id)?) {
        if (this.f12() case _?) {
          var name = id.split(ParserGenerator.separator).last;
          return NamedNode(name, OptionalNode(ReferenceNode(id)));
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$61) case _?) {
      if (this.apply(this.r17) case (var $1 && var id)?) {
        if (this.f16() case _?) {
          var name = id.split(ParserGenerator.separator).last;
          return NamedNode(name, StarNode(ReferenceNode(id)));
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$61) case _?) {
      if (this.apply(this.r17) case (var $1 && var id)?) {
        if (this.f17() case _?) {
          var name = id.split(ParserGenerator.separator).last;

          return NamedNode(name, PlusNode(ReferenceNode(id)));
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$61) case _?) {
      if (this.apply(this.r17) case (var $1 && var id)?) {
        var name = id.split(ParserGenerator.separator).last;

        return NamedNode(name, ReferenceNode(id));
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$61) case _?) {
      if (this.apply(this.r8) case (var $1 && var node)?) {
        if ($1 case var $) {
          return NamedNode(r"$", node);
        }
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
      if (this.fl() case _?) {
        if (this.apply(this.rb) case var expr?) {
          if (this.f17() case _?) {
            if (this.f12() case _?) {
              return PlusSeparatedNode(sep, expr, isTrailingAllowed: true);
            }
          }
        }
      }
    }
    this._recover(_mark);
    if (this.apply(this.rb) case var sep?) {
      if (this.fl() case _?) {
        if (this.apply(this.rb) case var expr?) {
          if (this.f16() case _?) {
            if (this.f12() case _?) {
              return StarSeparatedNode(sep, expr, isTrailingAllowed: true);
            }
          }
        }
      }
    }
    this._recover(_mark);
    if (this.apply(this.rb) case var sep?) {
      if (this.fl() case _?) {
        if (this.apply(this.rb) case var expr?) {
          if (this.f17() case _?) {
            return PlusSeparatedNode(sep, expr, isTrailingAllowed: false);
          }
        }
      }
    }
    this._recover(_mark);
    if (this.apply(this.rb) case var sep?) {
      if (this.fl() case _?) {
        if (this.apply(this.rb) case var expr?) {
          if (this.f16() case _?) {
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
      if (this.f12() case _?) {
        if ($0 case var $) {
          return OptionalNode($);
        }
      }
    }
    this._recover(_mark);
    if (this.apply(this.r9) case var $0?) {
      if (this.f16() case _?) {
        if ($0 case var $) {
          return StarNode($);
        }
      }
    }
    this._recover(_mark);
    if (this.apply(this.r9) case var $0?) {
      if (this.f17() case _?) {
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
    if (this.apply(this.r1a) case var min?) {
      if (this.fl() case _?) {
        if (this.apply(this.r1a) case var max?) {
          if (this.apply(this.rb) case var body?) {
            return CountedNode(min, max, body);
          }
        }
      }
    }
    this._recover(_mark);
    if (this.apply(this.r1a) case var min?) {
      if (this.fl() case _?) {
        if (this.apply(this.rb) case var body?) {
          return CountedNode(min, null, body);
        }
      }
    }
    this._recover(_mark);
    if (this.apply(this.r1a) case var number?) {
      if (this.apply(this.rb) case var body?) {
        return CountedNode(number, number, body);
      }
    }
    this._recover(_mark);
    if (this.f1w() case _?) {
      if (this.apply(this.ra) case var $1?) {
        if ($1 case var $) {
          return ExceptNode($);
        }
      }
    }
    this._recover(_mark);
    if (this.f1x() case _?) {
      if (this.apply(this.ra) case var $1?) {
        if ($1 case var $) {
          return AndPredicateNode($);
        }
      }
    }
    this._recover(_mark);
    if (this.f1y() case _?) {
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

  /// `global::atom`
  Node? rb() {
    var _mark = this._mark();
    if (this.fx() case _?) {
      _mark.isCut = true;
      if (this.apply(this.r3) case (var $2 && var $)?) {
        if (this.fy() case _?) {
          return $2;
        }
      }
    }
    if (_mark.isCut)
      return null;
    else
      this._recover(_mark);
    if (this.fo() case null) {
      this._recover(_mark);
      if (this.fs() case _?) {
        _mark.isCut = true;
        if (this.apply(this.r3) case (var $3 && var $)?) {
          if (this.ft() case _?) {
            if ($3 case var $) {
              return FlatNode($);
            }
          }
        }
      }
    }
    if (_mark.isCut)
      return null;
    else
      this._recover(_mark);
    if (this.apply(this.r1i)! case _) {
      if (this.matchPattern(_string.$34) case var $1?) {
        if (this.apply(this.r1i)! case _) {
          return const StartOfInputNode();
        }
      }
    }
    this._recover(_mark);
    if (this.apply(this.r1c) case var $?) {
      return const StartOfInputNode();
    }
    this._recover(_mark);
    if (this.apply(this.r1i)! case _) {
      if (this.matchPattern(_string.$35) case var $1?) {
        if (this.apply(this.r1i)! case _) {
          return const EndOfInputNode();
        }
      }
    }
    this._recover(_mark);
    if (this.apply(this.r1d) case var $?) {
      return const EndOfInputNode();
    }
    this._recover(_mark);
    if (this.apply(this.r1i)! case _) {
      if (this.matchPattern(_string.$33) case var $1?) {
        if (this.apply(this.r1i)! case _) {
          return const EpsilonNode();
        }
      }
    }
    this._recover(_mark);
    if (this.apply(this.r1e) case var $?) {
      return const EpsilonNode();
    }
    this._recover(_mark);
    if (this.f1a() case var $?) {
      return const AnyCharacterNode();
    }
    this._recover(_mark);
    if (this.apply(this.r1f) case var $?) {
      return const AnyCharacterNode();
    }
    this._recover(_mark);
    if (this.apply(this.r1i)! case _) {
      if (this.matchPattern(_string.$7) case var $1?) {
        if (this.apply(this.r1i)! case _) {
          return const CutNode();
        }
      }
    }
    this._recover(_mark);
    if (this.apply(this.r1i)! case _) {
      if (this.matchPattern(_string.$13) case var $1?) {
        if (this.apply(this.r1i)! case _) {
          return const CutNode();
        }
      }
    }
    this._recover(_mark);
    if (this.f6() case var $?) {
      return const StringLiteralNode(r"\");
    }
    this._recover(_mark);
    if (this.f7() case var $?) {
      return SimpleRegExpEscapeNode.digit;
    }
    this._recover(_mark);
    if (this.f9() case var $?) {
      return SimpleRegExpEscapeNode.word;
    }
    this._recover(_mark);
    if (this.fb() case var $?) {
      return SimpleRegExpEscapeNode.whitespace;
    }
    this._recover(_mark);
    if (this.apply(this.r1i)! case _) {
      if (this.f1z() case (var $1 && var $)?) {
        if (this.apply(this.r1i)! case _) {
          return SimpleRegExpEscapeNode.notDigit;
        }
      }
    }
    this._recover(_mark);
    if (this.apply(this.r1i)! case _) {
      if (this.f20() case (var $1 && var $)?) {
        if (this.apply(this.r1i)! case _) {
          return SimpleRegExpEscapeNode.notWord;
        }
      }
    }
    this._recover(_mark);
    if (this.apply(this.r1i)! case _) {
      if (this.f21() case (var $1 && var $)?) {
        if (this.apply(this.r1i)! case _) {
          return SimpleRegExpEscapeNode.notWhitespace;
        }
      }
    }
    this._recover(_mark);
    if (this.fg() case var $?) {
      return SimpleRegExpEscapeNode.tab;
    }
    this._recover(_mark);
    if (this.fe() case var $?) {
      return SimpleRegExpEscapeNode.newline;
    }
    this._recover(_mark);
    if (this.ff() case var $?) {
      return SimpleRegExpEscapeNode.carriageReturn;
    }
    this._recover(_mark);
    if (this.apply(this.r1i)! case _) {
      if (this.f22() case (var $1 && var $)?) {
        if (this.apply(this.r1i)! case _) {
          return SimpleRegExpEscapeNode.formFeed;
        }
      }
    }
    this._recover(_mark);
    if (this.apply(this.r1i)! case _) {
      if (this.f23() case (var $1 && var $)?) {
        if (this.apply(this.r1i)! case _) {
          return SimpleRegExpEscapeNode.verticalTab;
        }
      }
    }
    this._recover(_mark);
    if (this.apply(this.r1i)! case _) {
      if (this.f24() case (var $1 && var $)?) {
        if (this.apply(this.r1i)! case _) {
          return SimpleRegExpEscapeNode.wordBoundary;
        }
      }
    }
    this._recover(_mark);
    if (this.apply(this.r1i)! case _) {
      if (this.f26() case var $1?) {
        if (this.apply(this.r1i)! case _) {
          if ($1 case var $) {
            return RangeNode($);
          }
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$1) case _?) {
      if (this.f28() case var $1?) {
        if (this.matchPattern(_string.$1) case _?) {
          if ($1 case var $) {
            return RegExpNode($);
          }
        }
      }
    }
    this._recover(_mark);
    if (this.apply(this.r1i)! case _) {
      if (this.f2h() case var $1?) {
        if (this.apply(this.r1i)! case _) {
          if ($1 case var $) {
            return StringLiteralNode($);
          }
        }
      }
    }
    this._recover(_mark);
    if (this.apply(this.r15) case var $?) {
      return ReferenceNode($);
    }
  }

  /// `global::code::curlyNotJoined`
  List<String> rc() {
    var _mark = this._mark();
    if (this.f1m() case var _0) {
      if ([if (_0 case var _0) _0] case var _l1) {
        if (_l1.isNotEmpty) {
          for (;;) {
            var _mark = this._mark();
            if (this.matchPattern(_string.$22) case _?) {
              if (this.f1m() case var _0) {
                _l1.add(_0);
                continue;
              }
            }
            this._recover(_mark);
            break;
          }
          var _mark = this._mark();
          if (this.matchPattern(_string.$22) case null) {
            this._recover(_mark);
          }
        } else {
          this._recover(_mark);
        }
        return _l1;
      }
    }
  }

  /// `global::code::curly`
  String rd() {
    var _mark = this._mark();
    if (this.f1m() case var _0) {
      if ([if (_0 case var _0) _0] case (var $ && var _l1)) {
        if ($.isNotEmpty) {
          for (;;) {
            var _mark = this._mark();
            if (this.matchPattern(_string.$22) case _?) {
              if (this.f1m() case var _0) {
                _l1.add(_0);
                continue;
              }
            }
            this._recover(_mark);
            break;
          }
          var _mark = this._mark();
          if (this.matchPattern(_string.$22) case null) {
            this._recover(_mark);
          }
        } else {
          this._recover(_mark);
        }
        return $.join(";");
      }
    }
  }

  /// `global::code::nl`
  String re() {
    var _mark = this._mark();
    if (this.f2j() case var _0) {
      if ([if (_0 case var _0?) _0] case (var $ && var _l1)) {
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
        return $.join();
      }
    }
  }

  /// `global::code::balanced`
  String rf() {
    var _mark = this._mark();
    if (this.f2l() case var _0) {
      if ([if (_0 case var _0?) _0] case (var $ && var _l1)) {
        if (_l1.isNotEmpty) {
          for (;;) {
            var _mark = this._mark();
            if (this.f2l() case var _0?) {
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
    if (this.f2m() case var _0?) {
      if ([_0] case (var $ && var _l1)) {
        for (;;) {
          var _mark = this._mark();
          if (this.apply(this.r1i)! case _) {
            if (this.f2m() case var _0?) {
              _l1.add(_0);
              continue;
            }
          }
          this._recover(_mark);
          break;
        }
        return $.join("");
      }
    }
  }

  /// `global::dart::literal::identifier`
  String? rh() {
    if (this.apply(this.r18) case var $?) {
      return $;
    }
  }

  /// `global::dart::literal::string::interpolation`
  late final ri = () {
    var _mark = this._mark();
    if (this.matchPattern(_string.$35) case var $0?) {
      if (this.matchPattern(_string.$18) case var $1?) {
        if (this.apply(this.rj)! case var $2) {
          if (this.matchPattern(_string.$21) case var $3?) {
            return ($0, $1, $2, $3);
          }
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$35) case var $0?) {
      if (this.apply(this.rh) case var $1?) {
        return ($0, $1);
      }
    }
  };

  /// `global::dart::literal::string::balanced`
  String rj() {
    var _mark = this._mark();
    if (this.f2n() case var _0) {
      if ([if (_0 case var _0?) _0] case (var $ && var _l1)) {
        if (_l1.isNotEmpty) {
          for (;;) {
            var _mark = this._mark();
            if (this.f2n() case var _0?) {
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

  /// `global::dart::type`
  late final rk = () {
    if (this.apply(this.r1i)! case _) {
      if (this.apply(this.rl) case (var $1 && var nullable)?) {
        if (this.apply(this.r1i)! case _) {
          return $1;
        }
      }
    }
  };

  /// `global::dart::type::nullable`
  String? rl() {
    if (this.apply(this.rm) case var nonNullable?) {
      if (this.f2o() case var question) {
        return "$nonNullable${question ?? ""}";
      }
    }
  }

  /// `global::dart::type::nonNullable`
  String? rm() {
    var _mark = this._mark();
    if (this.apply(this.rn) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.apply(this.ro) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.apply(this.rp) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.apply(this.rv) case var $?) {
      return $;
    }
  }

  /// `global::dart::type::nonNullable::function`
  String? rn() {
    if (this.apply(this.rl) case (var nullable && var $0)?) {
      if (this.apply(this.r1i)! case _) {
        if (this.matchPattern(_string.$62) case _?) {
          if (this.apply(this.r1i)! case _) {
            if (this.apply(this.rw) case (var fnParameters && var $4)?) {
              return "${$0} Function${$4}";
            }
          }
        }
      }
    }
  }

  /// `global::dart::type::nonNullable::generic`
  String? ro() {
    if (this.apply(this.rv) case var base?) {
      if (this.fs() case _?) {
        if (this.f2p() case var args?) {
          if (this.ft() case _?) {
            return "$base<$args>";
          }
        }
      }
    }
  }

  /// `global::dart::type::nonNullable::record`
  late final rp = () {
    var _mark = this._mark();
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
    this._recover(_mark);
    if (this.apply(this.rt) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.apply(this.ru) case var $?) {
      return $;
    }
  };

  /// `global::dart::type::nonNullable::record::all`
  String? rq() {
    if (this.fx() case _?) {
      if (this.apply(this.rz) case var positional?) {
        if (this.f18() case _?) {
          if (this.apply(this.ry) case var named?) {
            if (this.fy() case _?) {
              return "(" + positional + ", " + named + ")";
            }
          }
        }
      }
    }
  }

  /// `global::dart::type::nonNullable::record::singlePositional`
  String? rr() {
    if (this.fx() case _?) {
      if (this.apply(this.r11) case (var $1 && var field)?) {
        if (this.f18() case _?) {
          if (this.fy() case _?) {
            return "(" + field + "," + ")";
          }
        }
      }
    }
  }

  /// `global::dart::type::nonNullable::record::onlyPositional`
  String? rs() {
    if (this.fx() case _?) {
      if (this.apply(this.rz) case (var $1 && var positional)?) {
        if (this.f2q() case _) {
          if (this.fy() case _?) {
            return "(" + positional + ")";
          }
        }
      }
    }
  }

  /// `global::dart::type::nonNullable::record::onlyNamed`
  String? rt() {
    if (this.fx() case _?) {
      if (this.apply(this.ry) case (var $1 && var named)?) {
        if (this.fy() case _?) {
          return "(" + named + ")";
        }
      }
    }
  }

  /// `global::dart::type::nonNullable::record::empty`
  String? ru() {
    if (this.fx() case _?) {
      if (this.fy() case _?) {
        return "()";
      }
    }
  }

  /// `global::dart::type::nonNullable::base`
  String? rv() {
    if (this.apply(this.r18) case var _0?) {
      if ([_0] case (var $ && var _l1)) {
        for (;;) {
          var _mark = this._mark();
          if (this.f1a() case _?) {
            if (this.apply(this.r18) case var _0?) {
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

  /// `global::dart::type::fnParameters`
  String? rw() {
    var _mark = this._mark();
    if (this.fx() case _?) {
      if (this.apply(this.rz) case var positional?) {
        if (this.f18() case _?) {
          if (this.apply(this.ry) case var named?) {
            if (this.fy() case _?) {
              return "($positional, $named)";
            }
          }
        }
      }
    }
    this._recover(_mark);
    if (this.fx() case _?) {
      if (this.apply(this.rz) case var positional?) {
        if (this.f18() case _?) {
          if (this.apply(this.rx) case var optional?) {
            if (this.fy() case _?) {
              return "($positional, $optional)";
            }
          }
        }
      }
    }
    this._recover(_mark);
    if (this.fx() case _?) {
      if (this.apply(this.rz) case (var $1 && var positional)?) {
        if (this.f2r() case _) {
          if (this.fy() case _?) {
            return "($positional)";
          }
        }
      }
    }
    this._recover(_mark);
    if (this.fx() case _?) {
      if (this.apply(this.ry) case (var $1 && var named)?) {
        if (this.fy() case _?) {
          return "($named)";
        }
      }
    }
    this._recover(_mark);
    if (this.fx() case _?) {
      if (this.apply(this.rx) case (var $1 && var optional)?) {
        if (this.fy() case _?) {
          return "($optional)";
        }
      }
    }
    this._recover(_mark);
    if (this.fx() case _?) {
      if (this.fy() case _?) {
        return "()";
      }
    }
  }

  /// `global::dart::type::parameters::optional`
  String? rx() {
    if (this.f2s() case _?) {
      if (this.apply(this.rz) case (var $1 && var $)?) {
        if (this.f2t() case _) {
          if (this.f2u() case _?) {
            if ($1 case var $) {
              return "[" + $ + "]";
            }
          }
        }
      }
    }
  }

  /// `global::dart::type::parameters::named`
  String? ry() {
    if (this.fw() case _?) {
      if (this.apply(this.r10) case (var $1 && var $)?) {
        if (this.f2v() case _) {
          if (this.fz() case _?) {
            if ($1 case var $) {
              return "{" + $ + "}";
            }
          }
        }
      }
    }
  }

  /// `global::dart::type::fields::positional`
  String? rz() {
    if (this.apply(this.r11) case var car?) {
      if (this.f18() case _?) {
        var _mark = this._mark();
        if (this.apply(this.r11) case var _0) {
          if ([if (_0 case var _0?) _0] case (var cdr && var _l1)) {
            if (cdr.isNotEmpty) {
              for (;;) {
                var _mark = this._mark();
                if (this.f18() case _?) {
                  if (this.apply(this.r11) case var _0?) {
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
            return [car, ...cdr].join(", ");
          }
        }
      }
    }
  }

  /// `global::dart::type::fields::named`
  String? r10() {
    if (this.apply(this.r12) case var _0?) {
      if ([_0] case (var $ && var _l1)) {
        for (;;) {
          var _mark = this._mark();
          if (this.f18() case _?) {
            if (this.apply(this.r12) case var _0?) {
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
  String? r11() {
    if (this.apply(this.rk) case var $0?) {
      if (this.apply(this.r1i)! case _) {
        if (this.f2w() case var $2) {
          return "${$0} ${$2 ?? ""}".trimRight();
        }
      }
    }
  }

  /// `global::dart::type::field::named`
  String? r12() {
    if (this.apply(this.rk) case var $0?) {
      if (this.apply(this.r1i)! case _) {
        if (this.apply(this.r18) case var $2?) {
          return "${$0} ${$2}";
        }
      }
    }
  }

  /// `global::type`
  String? r13() {
    var _mark = this._mark();
    if (this.apply(this.r1i)! case _) {
      if (this.apply(this.r19) case var $1?) {
        if (this.apply(this.r1i)! case _) {
          return $1;
        }
      }
    }
    this._recover(_mark);
    if (this.apply(this.r1i)! case _) {
      if (this.f2x() case var $1?) {
        return $1;
      }
    }
  }

  /// `global::namespaceReference`
  String r14() {
    var _mark = this._mark();
    if (this.f2z() case var _0?) {
      if ([_0].nullable() case var _l1) {
        if (_l1 != null) {
          for (;;) {
            var _mark = this._mark();
            if (this.f2z() case var _0?) {
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
          return $.join(ParserGenerator.separator);
        }
      }
    }
    this._recover(_mark);
    if ('' case var $) {
      return $;
    }
  }

  /// `global::name`
  String? r15() {
    var _mark = this._mark();
    if (this.apply(this.r16) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.apply(this.r17) case var $?) {
      return $;
    }
  }

  /// `global::namespacedRaw`
  String? r16() {
    if (this.apply(this.r14)! case var $0) {
      if (this.f31() case var $1?) {
        return $0.isEmpty ? $1 : "${$0}${ParserGenerator.separator}${$1}";
      }
    }
  }

  /// `global::namespacedIdentifier`
  String? r17() {
    if (this.apply(this.r14)! case var $0) {
      if (this.apply(this.r18) case var $1?) {
        return $0.isEmpty ? $1 : "${$0}${ParserGenerator.separator}${$1}";
      }
    }
  }

  /// `global::identifier`
  String? r18() {
    if (this.pos case var from) {
      if (this.matchRange(_range.$2) case _?) {
        var _mark = this._mark();
        if (this.matchRange(_range.$1) case var _0) {
          if ([if (_0 case var _0?) _0] case var _l1) {
            if (_l1.isNotEmpty) {
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

  /// `global::raw`
  String? r19() {
    if (this.matchPattern(_string.$6) case _?) {
      if (this.f33() case var $1) {
        if (this.matchPattern(_string.$6) case _?) {
          return $1;
        }
      }
    }
  }

  /// `global::number`
  int? r1a() {
    if (this.matchPattern(_regexp.$3) case var _0?) {
      if ([_0] case (var $ && var _l1)) {
        for (;;) {
          var _mark = this._mark();
          if (this.matchPattern(_regexp.$3) case var _0?) {
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
  Tag? r1b() {
    if (this.apply(this.r1i)! case _) {
      if (this.matchPattern(_string.$14) case _?) {
        if (this.f34() case (var $2 && var _decorator)?) {
          if (this.apply(this.r1i)! case _) {
            return $2;
          }
        }
      }
    }
  }

  /// `global::kw::start`
  String? r1c() {
    if (this.apply(this.r1i)! case _) {
      if (this.matchPattern(_string.$63) case (var $1 && var $)?) {
        if (this.apply(this.r1i)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::kw::end`
  String? r1d() {
    if (this.apply(this.r1i)! case _) {
      if (this.matchPattern(_string.$64) case (var $1 && var $)?) {
        if (this.apply(this.r1i)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::kw::epsilon`
  String? r1e() {
    if (this.apply(this.r1i)! case _) {
      if (this.matchPattern(_string.$65) case (var $1 && var $)?) {
        if (this.apply(this.r1i)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::kw::any`
  String? r1f() {
    if (this.apply(this.r1i)! case _) {
      if (this.matchPattern(_string.$66) case (var $1 && var $)?) {
        if (this.apply(this.r1i)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::mac`
  String? r1g() {
    var _mark = this._mark();
    if (this.apply(this.r1h) case var $?) {
      return $;
    }
  }

  /// `global::mac::choice`
  String? r1h() {
    if (this.apply(this.r1i)! case _) {
      if (this.matchPattern(_string.$67) case var $1?) {
        if (this.apply(this.r1i)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::_`
  String r1i() {
    var _mark = this._mark();
    if (this.f35() case var _0) {
      if ([if (_0 case var _0?) _0] case var _l1) {
        if (_l1.isNotEmpty) {
          for (;;) {
            var _mark = this._mark();
            if (this.f35() case var _0?) {
              _l1.add(_0);
              continue;
            }
            this._recover(_mark);
            break;
          }
        } else {
          this._recover(_mark);
        }
        return "";
      }
    }
  }

  /// `global::whitespace`
  late final r1j = () {
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
        return "";
      }
    }
  };

  /// `global::comment`
  String? r1k() {
    var _mark = this._mark();
    if (this.apply(this.r1l) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.apply(this.r1m) case var $?) {
      return $;
    }
  }

  /// `global::comment::single`
  String? r1l() {
    if (this.matchPattern(_string.$68) case _?) {
      var _mark = this._mark();
      if (this.f39() case var _0) {
        if ([if (_0 case var _0?) _0] case var _l1) {
          if (_l1.isNotEmpty) {
            for (;;) {
              var _mark = this._mark();
              if (this.f39() case var _0?) {
                _l1.add(_0);
                continue;
              }
              this._recover(_mark);
              break;
            }
          } else {
            this._recover(_mark);
          }
          return "";
        }
      }
    }
  }

  /// `global::comment::multi`
  String? r1m() {
    if (this.matchPattern(_string.$69) case _?) {
      var _mark = this._mark();
      if (this.f3a() case var _0) {
        if ([if (_0 case var _0?) _0] case var _l1) {
          if (_l1.isNotEmpty) {
            for (;;) {
              var _mark = this._mark();
              if (this.f3a() case var _0?) {
                _l1.add(_0);
                continue;
              }
              this._recover(_mark);
              break;
            }
          } else {
            this._recover(_mark);
          }
          if (this.matchPattern(_string.$55) case _?) {
            return "";
          }
        }
      }
    }
  }
}

class _regexp {
  /// `/\r/`
  static final $1 = RegExp("\\r");

  /// `/\n/`
  static final $2 = RegExp("\\n");

  /// `/\d/`
  static final $3 = RegExp("\\d");

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

  /// `"#"`
  static const $7 = "#";

  /// `".."`
  static const $8 = "..";

  /// `"=>"`
  static const $9 = "=>";

  /// `"~>"`
  static const $10 = "~>";

  /// `"<~"`
  static const $11 = "<~";

  /// `"|>"`
  static const $12 = "|>";

  /// `"%"`
  static const $13 = "%";

  /// `"@"`
  static const $14 = "@";

  /// `"<"`
  static const $15 = "<";

  /// `">"`
  static const $16 = ">";

  /// `"["`
  static const $17 = "[";

  /// `"{"`
  static const $18 = "{";

  /// `"("`
  static const $19 = "(";

  /// `")"`
  static const $20 = ")";

  /// `"}"`
  static const $21 = "}";

  /// `";"`
  static const $22 = ";";

  /// `"="`
  static const $23 = "=";

  /// `"?"`
  static const $24 = "?";

  /// `"!"`
  static const $25 = "!";

  /// `"~"`
  static const $26 = "~";

  /// `"&"`
  static const $27 = "&";

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

  /// `"ε"`
  static const $33 = "ε";

  /// `"^"`
  static const $34 = "^";

  /// `"\$"`
  static const $35 = "\$";

  /// `"\"\"\""`
  static const $36 = "\"\"\"";

  /// `"r"`
  static const $37 = "r";

  /// `"'''"`
  static const $38 = "'''";

  /// `"\""`
  static const $39 = "\"";

  /// `"'"`
  static const $40 = "'";

  /// `"D"`
  static const $41 = "D";

  /// `"W"`
  static const $42 = "W";

  /// `"S"`
  static const $43 = "S";

  /// `"f"`
  static const $44 = "f";

  /// `"v"`
  static const $45 = "v";

  /// `"b"`
  static const $46 = "b";

  /// `"r\"\"\""`
  static const $47 = "r\"\"\"";

  /// `"r'''"`
  static const $48 = "r'''";

  /// `"r\""`
  static const $49 = "r\"";

  /// `"r'"`
  static const $50 = "r'";

  /// `"::"`
  static const $51 = "::";

  /// `"rule"`
  static const $52 = "rule";

  /// `"fragment"`
  static const $53 = "fragment";

  /// `"inline"`
  static const $54 = "inline";

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

  /// `"START"`
  static const $63 = "START";

  /// `"END"`
  static const $64 = "END";

  /// `"EPSILON"`
  static const $65 = "EPSILON";

  /// `"ANY"`
  static const $66 = "ANY";

  /// `"choice!"`
  static const $67 = "choice!";

  /// `"//"`
  static const $68 = "//";

  /// `"/*"`
  static const $69 = "/*";
}

class _range {
  /// `[a-zA-Z0-9_$]`
  static const $1 = {(97, 122), (65, 90), (48, 57), (95, 95), (36, 36)};

  /// `[a-zA-Z_$]`
  static const $2 = {(97, 122), (65, 90), (95, 95), (36, 36)};
}
