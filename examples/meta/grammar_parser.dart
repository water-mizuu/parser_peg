// ignore_for_file: type=lint, body_might_complete_normally_nullable, unused_local_variable, inference_failure_on_function_return_type, unused_import, duplicate_ignore, unused_element, collection_methods_unrelated_type, unused_element, use_setters_to_change_properties

// imports
// ignore_for_file: avoid_positional_boolean_parameters, unnecessary_non_null_assertion, unnecessary_this, unused_element, use_setters_to_change_properties

// ignore: unused_shown_name
import "dart:collection" show DoubleLinkedQueue, HashMap, Queue;
import "dart:math" as math show Random;
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

  T? _applyLr<T extends Object>(_Rule<T> r, [int? p]) {
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

  T? _applyMemo<T extends Object>(_Rule<T> r, [int? p]) {
    p ??= this.pos;
    _Memo? m = _recall(r, p);
    if (m == null) {
      m = _memo[(r, p)] = _Memo(null, p);
      T? ans = r.call();
      m.pos = this.pos;
      m.ans = ans;

      return ans;
    } else {
      this.pos = m.pos;

      return m.ans as T?;
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
    var MapEntry(:key, :value) = failures.entries.last;
    var (int column, int row) = _columnRow(buffer, key);

    return "($column:$row): Expected the following: $value";
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
    _applyLr(start),
  ).$2;
  _Rule<R> get start;
}

extension<T extends Object> on T {
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
      if (this.f29() case var $1?) {
        if (this.matchPattern(_string.$1) case _?) {
          return $1;
        }
      }
    }
  }

  /// `global::literal::string`
  String? f1() {
    if (this._applyMemo(this.r2d)! case _) {
      if (this.f2i() case var $1?) {
        if (this._applyMemo(this.r2d)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::literal::range`
  Set<(int, int)>? f2() {
    if (this._applyMemo(this.r2d)! case _) {
      if (this.f2k() case var $1?) {
        if (this._applyMemo(this.r2d)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::literal::range::element`
  Set<(int, int)>? f3() {
    var _mark = this._mark();
    if (this.matchPattern(_string.$2) case var $?) {
      return {(32, 32)} ;
    }
    this._recover(_mark);
    if (this.f7() case var $?) {
      return {(48, 57)} ;
    }
    this._recover(_mark);
    if (this.f9() case var $?) {
      return {(64 + 1, 64 + 26), (96 + 1, 96 + 26)} ;
    }
    this._recover(_mark);
    if (this.fb() case var $?) {
      return {(9, 13), (32, 32)} ;
    }
    this._recover(_mark);
    if (this.fe() case var $?) {
      return {(10, 10)} ;
    }
    this._recover(_mark);
    if (this.ff() case var $?) {
      return {(13, 13)} ;
    }
    this._recover(_mark);
    if (this.fg() case var $?) {
      return {(9, 9)} ;
    }
    this._recover(_mark);
    if (this.f6() case var $?) {
      return {(92, 92)} ;
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
        if (this.f2l() case var _0) {
          if ([if (_0 case var _0?) _0] case (var $1 && var _l1)) {
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
            if (this.matchPattern(_string.$6) case _?) {
              if ($1 case var $) {
                return $.join() ;
              }
            }
          }
        }
    }
  }

  /// `global::regexEscape::backslash`
  String? f6() {
    if (this._applyMemo(this.r2d)! case _) {
      if (this.f2n() case var $1?) {
        return $1;
      }
    }
  }

  /// `global::regexEscape::digit`
  String? f7() {
    if (this._applyMemo(this.r2d)! case _) {
      if (this.f2o() case (var $1 && var $)?) {
        if (this._applyMemo(this.r2d)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::regexEscape::notDigit`
  String? f8() {
    if (this._applyMemo(this.r2d)! case _) {
      if (this.f2p() case (var $1 && var $)?) {
        if (this._applyMemo(this.r2d)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::regexEscape::word`
  String? f9() {
    if (this._applyMemo(this.r2d)! case _) {
      if (this.f2q() case (var $1 && var $)?) {
        if (this._applyMemo(this.r2d)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::regexEscape::notWord`
  String? fa() {
    if (this._applyMemo(this.r2d)! case _) {
      if (this.f2r() case (var $1 && var $)?) {
        if (this._applyMemo(this.r2d)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::regexEscape::whitespace`
  String? fb() {
    if (this._applyMemo(this.r2d)! case _) {
      if (this.f2s() case (var $1 && var $)?) {
        if (this._applyMemo(this.r2d)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::regexEscape::notWhitespace`
  String? fc() {
    if (this._applyMemo(this.r2d)! case _) {
      if (this.f2t() case (var $1 && var $)?) {
        if (this._applyMemo(this.r2d)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::regexEscape::wordBoundary`
  String? fd() {
    if (this._applyMemo(this.r2d)! case _) {
      if (this.f2u() case (var $1 && var $)?) {
        if (this._applyMemo(this.r2d)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::regexEscape::newline`
  String? fe() {
    if (this._applyMemo(this.r2d)! case _) {
      if (this.f2v() case (var $1 && var $)?) {
        if (this._applyMemo(this.r2d)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::regexEscape::carriageReturn`
  String? ff() {
    if (this._applyMemo(this.r2d)! case _) {
      if (this.f2w() case (var $1 && var $)?) {
        if (this._applyMemo(this.r2d)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::regexEscape::tab`
  String? fg() {
    if (this._applyMemo(this.r2d)! case _) {
      if (this.f2x() case (var $1 && var $)?) {
        if (this._applyMemo(this.r2d)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::regexEscape::formFeed`
  String? fh() {
    if (this._applyMemo(this.r2d)! case _) {
      if (this.f2y() case (var $1 && var $)?) {
        if (this._applyMemo(this.r2d)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::regexEscape::verticalTab`
  String? fi() {
    if (this._applyMemo(this.r2d)! case _) {
      if (this.f2z() case (var $1 && var $)?) {
        if (this._applyMemo(this.r2d)! case _) {
          return $1;
        }
      }
    }
  }

  /// `ROOT`
  ParserGenerator? fj() {
    if (this._applyLr(this.r0) case var $?) {
      return $;
    }
  }

  /// `global::untypedMacroChoice`
  HybridNamespaceStatement? fk() {
    if (this.f30() case var outer_decorator) {
      if (this._applyMemo(this.r18) case var name?) {
        if (this._applyMemo(this.r20) case _?) {
          if (this._applyMemo(this.r1h) case _?) {
            if (this.f31() case var inner_decorator) {
              if (this._applyMemo(this.r1v) case _?) {
                if (this._applyLr(this.r2) case var _0?) {
                  if ([_0] case (var statements && var _l1)) {
                    for (;;) {
                      var _mark = this._mark();
                      if (this._applyMemo(this.r2d)! case _) {
                        if (this._applyLr(this.r2) case var _0?) {
                          _l1.add(_0);
                          continue;
                        }
                      }
                      this._recover(_mark);
                      break;
                    }
                    if (this._applyMemo(this.r1y) case _?) {
                      if (this.f32() case _) {
                        return HybridNamespaceStatement(
                              null, name, statements,
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

  /// `global::typedMacroChoice`
  HybridNamespaceStatement? fl() {
    if (this.f33() case var outer_decorator) {
      if (this._applyLr(this.r13) case var type?) {
        if (this._applyMemo(this.r18) case var name?) {
          if (this._applyMemo(this.r20) case _?) {
            if (this._applyMemo(this.r1h) case _?) {
              if (this.f34() case var inner_decorator) {
                if (this._applyMemo(this.r1v) case _?) {
                  if (this._applyLr(this.r2) case var _0?) {
                    if ([_0] case (var statements && var _l1)) {
                      for (;;) {
                        var _mark = this._mark();
                        if (this._applyMemo(this.r2d)! case _) {
                          if (this._applyLr(this.r2) case var _0?) {
                            _l1.add(_0);
                            continue;
                          }
                        }
                        this._recover(_mark);
                        break;
                      }
                      if (this._applyMemo(this.r1y) case _?) {
                        if (this.f35() case _) {
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
  }

  /// `global::unnamedTypedMacroChoice`
  HybridNamespaceStatement? fm() {
    if (this.f36() case var outer_decorator) {
      if (this.f37() case var type) {
        if (this._applyMemo(this.r1w) case _?) {
          if (this._applyMemo(this.r1x) case _?) {
            if (this._applyMemo(this.r20) case _?) {
              if (this._applyMemo(this.r1h) case _?) {
                if (this.f38() case var inner_decorator) {
                  if (this._applyMemo(this.r1v) case _?) {
                    if (this._applyLr(this.r2) case var _0?) {
                      if ([_0] case (var statements && var _l1)) {
                        for (;;) {
                          var _mark = this._mark();
                          if (this._applyMemo(this.r2d)! case _) {
                            if (this._applyLr(this.r2) case var _0?) {
                              _l1.add(_0);
                              continue;
                            }
                          }
                          this._recover(_mark);
                          break;
                        }
                        if (this._applyMemo(this.r1y) case _?) {
                          if (this.f39() case _) {
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
  }

  /// `global::namespace`
  NamespaceStatement? fn() {
    if (this.f3a() case var decorator) {
      if (this.f3b() case var name) {
        if (this._applyMemo(this.r1v) case _?) {
          if (this._applyLr(this.r2) case var _0?) {
            if ([_0] case (var statements && var _l1)) {
              for (;;) {
                var _mark = this._mark();
                if (this._applyMemo(this.r2d)! case _) {
                  if (this._applyLr(this.r2) case var _0?) {
                    _l1.add(_0);
                    continue;
                  }
                }
                this._recover(_mark);
                break;
              }
              if (this._applyMemo(this.r1y) case _?) {
                return NamespaceStatement(name, statements, tag: decorator);
              }
            }
          }
        }
      }
    }
  }

  /// `global::typeDeclaration`
  DeclarationTypeStatement? fo() {
    if (this.f3c() case var decorator) {
      if (this.f3d() case var type) {
        if (this._applyMemo(this.r15) case var _0?) {
          if ([_0] case (var names && var _l1)) {
            for (;;) {
              var _mark = this._mark();
              if (this._applyMemo(this.r27) case _?) {
                if (this._applyMemo(this.r15) case var _0?) {
                  _l1.add(_0);
                  continue;
                }
              }
              this._recover(_mark);
              break;
            }
            if (this._applyMemo(this.r1z) case _?) {
              return DeclarationTypeStatement(type, names, tag: decorator);
            }
          }
        }
      }
    }
  }

  /// `global::typedRule`
  DeclarationStatement? fp() {
    if (this.f3e() case var decorator) {
      if (this._applyLr(this.r13) case var type?) {
        if (this._applyMemo(this.r15) case var name?) {
          if (this._applyMemo(this.r20) case _?) {
            if (this._applyLr(this.r3) case var body?) {
              if (this._applyMemo(this.r1z) case _?) {
                return DeclarationStatement(type, name, body, tag: decorator);
              }
            }
          }
        }
      }
    }
  }

  /// `global::untypedRule`
  DeclarationStatement? fq() {
    if (this.f3f() case var decorator) {
      if (this._applyMemo(this.r15) case var name?) {
        if (this._applyMemo(this.r20) case _?) {
          if (this._applyLr(this.r3) case var body?) {
            if (this._applyMemo(this.r1z) case _?) {
              return DeclarationStatement(null, name, body, tag: decorator);
            }
          }
        }
      }
    }
  }

  /// `global::code::_curly`
  String fr() {
    var _mark = this._mark();
      if (this.f3h() case var _0) {
        if ([if (_0 case var _0?) _0] case (var $ && var _l1)) {
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
          return $.join() ;
        }
      }
  }

  /// `global::dart::literal::string::body`
  Record? fs() {
    var _mark = this._mark();
    if (this.matchPattern(_string.$8) case var _2?) {
      if ([_2].nullable() case var _l3) {
        if (_l3 != null) {
          while (_l3.length < 1) {
            var _mark = this._mark();
            if (this.matchPattern(_string.$8) case var _2?) {
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
          if (this.matchPattern(_string.$7) case var $1?) {
            var _mark = this._mark();
              if (this.f3i() case var _0) {
                if ([if (_0 case var _0?) _0] case (var $2 && var _l1)) {
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
                  if (this.matchPattern(_string.$7) case var $3?) {
                    return ($0, $1, $2, $3);
                  }
                }
              }
          }
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$8) case var _6?) {
      if ([_6].nullable() case var _l7) {
        if (_l7 != null) {
          while (_l7.length < 1) {
            var _mark = this._mark();
            if (this.matchPattern(_string.$8) case var _6?) {
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
          if (this.matchPattern(_string.$9) case var $1?) {
            var _mark = this._mark();
              if (this.f3j() case var _4) {
                if ([if (_4 case var _4?) _4] case (var $2 && var _l5)) {
                  if (_l5.isNotEmpty) {
                    for (;;) {
                      var _mark = this._mark();
                      if (this.f3j() case var _4?) {
                        _l5.add(_4);
                        continue;
                      }
                      this._recover(_mark);
                      break;
                    }
                  } else {
                    this._recover(_mark);
                  }
                  if (this.matchPattern(_string.$9) case var $3?) {
                    return ($0, $1, $2, $3);
                  }
                }
              }
          }
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$8) case var _10?) {
      if ([_10].nullable() case var _l11) {
        if (_l11 != null) {
          while (_l11.length < 1) {
            var _mark = this._mark();
            if (this.matchPattern(_string.$8) case var _10?) {
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
          if (this.matchPattern(_string.$10) case var $1?) {
            var _mark = this._mark();
              if (this.f3k() case var _8) {
                if ([if (_8 case var _8?) _8] case (var $2 && var _l9)) {
                  if (_l9.isNotEmpty) {
                    for (;;) {
                      var _mark = this._mark();
                      if (this.f3k() case var _8?) {
                        _l9.add(_8);
                        continue;
                      }
                      this._recover(_mark);
                      break;
                    }
                  } else {
                    this._recover(_mark);
                  }
                  if (this.matchPattern(_string.$10) case var $3?) {
                    return ($0, $1, $2, $3);
                  }
                }
              }
          }
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$8) case var _14?) {
      if ([_14].nullable() case var _l15) {
        if (_l15 != null) {
          while (_l15.length < 1) {
            var _mark = this._mark();
            if (this.matchPattern(_string.$8) case var _14?) {
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
          if (this.matchPattern(_string.$11) case var $1?) {
            var _mark = this._mark();
              if (this.f3l() case var _12) {
                if ([if (_12 case var _12?) _12] case (var $2 && var _l13)) {
                  if (_l13.isNotEmpty) {
                    for (;;) {
                      var _mark = this._mark();
                      if (this.f3l() case var _12?) {
                        _l13.add(_12);
                        continue;
                      }
                      this._recover(_mark);
                      break;
                    }
                  } else {
                    this._recover(_mark);
                  }
                  if (this.matchPattern(_string.$11) case var $3?) {
                    return ($0, $1, $2, $3);
                  }
                }
              }
          }
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$7) case var $0?) {
      var _mark = this._mark();
        if (this.f3m() case var _16) {
          if ([if (_16 case var _16?) _16] case (var $1 && var _l17)) {
            if (_l17.isNotEmpty) {
              for (;;) {
                var _mark = this._mark();
                if (this.f3m() case var _16?) {
                  _l17.add(_16);
                  continue;
                }
                this._recover(_mark);
                break;
              }
            } else {
              this._recover(_mark);
            }
            if (this.matchPattern(_string.$7) case var $2?) {
              return ($0, $1, $2);
            }
          }
        }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$9) case var $0?) {
      var _mark = this._mark();
        if (this.f3n() case var _18) {
          if ([if (_18 case var _18?) _18] case (var $1 && var _l19)) {
            if (_l19.isNotEmpty) {
              for (;;) {
                var _mark = this._mark();
                if (this.f3n() case var _18?) {
                  _l19.add(_18);
                  continue;
                }
                this._recover(_mark);
                break;
              }
            } else {
              this._recover(_mark);
            }
            if (this.matchPattern(_string.$9) case var $2?) {
              return ($0, $1, $2);
            }
          }
        }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$10) case var $0?) {
      var _mark = this._mark();
        if (this.f3o() case var _20) {
          if ([if (_20 case var _20?) _20] case (var $1 && var _l21)) {
            if (_l21.isNotEmpty) {
              for (;;) {
                var _mark = this._mark();
                if (this.f3o() case var _20?) {
                  _l21.add(_20);
                  continue;
                }
                this._recover(_mark);
                break;
              }
            } else {
              this._recover(_mark);
            }
            if (this.matchPattern(_string.$10) case var $2?) {
              return ($0, $1, $2);
            }
          }
        }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$11) case var $0?) {
      var _mark = this._mark();
        if (this.f3p() case var _22) {
          if ([if (_22 case var _22?) _22] case (var $1 && var _l23)) {
            if (_l23.isNotEmpty) {
              for (;;) {
                var _mark = this._mark();
                if (this.f3p() case var _22?) {
                  _l23.add(_22);
                  continue;
                }
                this._recover(_mark);
                break;
              }
            } else {
              this._recover(_mark);
            }
            if (this.matchPattern(_string.$11) case var $2?) {
              return ($0, $1, $2);
            }
          }
        }
    }
  }

  /// `fragment0`
  String? ft() {
    if (this.r1() case var $?) {
      return $;
    }
  }

  /// `fragment1`
  String fu() {
    if (this._applyMemo(this.r2d)! case var $) {
      return $;
    }
  }

  /// `fragment2`
  String? fv() {
    if (this._applyMemo(this.r1i) case var $?) {
      return $;
    }
  }

  /// `fragment3`
  int? fw() {
    if (this.r1q() case _?) {
      if (this._applyMemo(this.r1a) case var $1?) {
        return $1;
      }
    }
  }

  /// `fragment4`
  String? fx() {
    if (this.pos case var from) {
      if (this.matchPattern(_string.$4) case _?) {
        if (this.matchPattern(_string.$12) case _?) {
          if (this.pos case var to) {
            if (this.buffer.substring(from, to) case var span) {
              return span;
            }
          }
        }
      }
    }
  }

  /// `fragment5`
  String? fy() {
    if (this.pos case var from) {
      if (this.matchPattern(_string.$4) case _?) {
        if (this.matchPattern(_string.$13) case _?) {
          if (this.pos case var to) {
            if (this.buffer.substring(from, to) case var span) {
              return span;
            }
          }
        }
      }
    }
  }

  /// `fragment6`
  String? fz() {
    if (this.pos case var from) {
      if (this.matchPattern(_string.$4) case _?) {
        if (this.matchPattern(_string.$14) case _?) {
          if (this.pos case var to) {
            if (this.buffer.substring(from, to) case var span) {
              return span;
            }
          }
        }
      }
    }
  }

  /// `fragment7`
  String? f10() {
    if (this.pos case var from) {
      if (this.matchPattern(_string.$4) case _?) {
        if (this.matchPattern(_string.$15) case _?) {
          if (this.pos case var to) {
            if (this.buffer.substring(from, to) case var span) {
              return span;
            }
          }
        }
      }
    }
  }

  /// `fragment8`
  String? f11() {
    if (this.pos case var from) {
      if (this.matchPattern(_string.$4) case _?) {
        if (this.matchPattern(_string.$16) case _?) {
          if (this.pos case var to) {
            if (this.buffer.substring(from, to) case var span) {
              return span;
            }
          }
        }
      }
    }
  }

  /// `fragment9`
  String? f12() {
    if (this.pos case var from) {
      if (this.matchPattern(_string.$4) case _?) {
        if (this.matchPattern(_string.$17) case _?) {
          if (this.pos case var to) {
            if (this.buffer.substring(from, to) case var span) {
              return span;
            }
          }
        }
      }
    }
  }

  /// `fragment10`
  Set<(int, int)>? f13() {
    var _mark = this._mark();
    if (this.matchPattern(_string.$2) case var $?) {
      return {(32, 32)} ;
    }
    this._recover(_mark);
    if (this.f7() case var $?) {
      return {(48, 57)} ;
    }
    this._recover(_mark);
    if (this.f9() case var $?) {
      return {(64 + 1, 64 + 26), (96 + 1, 96 + 26)} ;
    }
    this._recover(_mark);
    if (this.fb() case var $?) {
      return {(9, 13), (32, 32)} ;
    }
    this._recover(_mark);
    if (this.fe() case var $?) {
      return {(10, 10)} ;
    }
    this._recover(_mark);
    if (this.ff() case var $?) {
      return {(13, 13)} ;
    }
    this._recover(_mark);
    if (this.fg() case var $?) {
      return {(9, 9)} ;
    }
    this._recover(_mark);
    if (this.f6() case var $?) {
      return {(92, 92)} ;
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

  /// `fragment11`
  Set<(int, int)>? f14() {
    if (this.matchPattern(_string.$18) case _?) {
      if (this.f13() case var _0?) {
        if ([_0] case (var $1 && var elements && var _l1)) {
          for (;;) {
            var _mark = this._mark();
            if (this.f13() case var _0?) {
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
  }

  /// `fragment12`
  String? f15() {
    var _mark = this._mark();
    if (this.matchPattern(_string.$4) case _?) {
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $1) {
          if ($1 case var $) {
            return r"\" + $ ;
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
  }

  /// `fragment13`
  String? f16() {
    if (this.f15() case var _0?) {
      if ([_0] case (var $ && var _l1)) {
        for (;;) {
          var _mark = this._mark();
          if (this.f15() case var _0?) {
            _l1.add(_0);
            continue;
          }
          this._recover(_mark);
          break;
        }
        return $.join() ;
      }
    }
  }

  /// `fragment14`
  String? f17() {
    var _mark = this._mark();
    if (this.matchPattern(_string.$7) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  }

  /// `fragment15`
  String? f18() {
    var _mark = this._mark();
    if (this.matchPattern(_string.$9) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  }

  /// `fragment16`
  String? f19() {
    var _mark = this._mark();
    if (this.matchPattern(_string.$10) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  }

  /// `fragment17`
  String? f1a() {
    var _mark = this._mark();
    if (this.matchPattern(_string.$11) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  }

  /// `fragment18`
  String? f1b() {
    var _mark = this._mark();
    if (this.matchPattern(_string.$4) case _?) {
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $1) {
          return $1;
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$7) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  }

  /// `fragment19`
  String? f1c() {
    var _mark = this._mark();
    if (this.matchPattern(_string.$4) case _?) {
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $1) {
          return $1;
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$9) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  }

  /// `fragment20`
  String? f1d() {
    var _mark = this._mark();
    if (this.matchPattern(_string.$4) case _?) {
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $1) {
          return $1;
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$10) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  }

  /// `fragment21`
  String? f1e() {
    var _mark = this._mark();
    if (this.matchPattern(_string.$4) case _?) {
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $1) {
          return $1;
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$11) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  }

  /// `fragment22`
  String? f1f() {
    var _mark = this._mark();
    if (this.matchPattern(_string.$19) case _?) {
      var _mark = this._mark();
        if (this.f17() case var _0) {
          if ([if (_0 case var _0?) _0] case (var $1 && var _l1)) {
            if (_l1.isNotEmpty) {
              for (;;) {
                var _mark = this._mark();
                if (this.f17() case var _0?) {
                  _l1.add(_0);
                  continue;
                }
                this._recover(_mark);
                break;
              }
            } else {
              this._recover(_mark);
            }
            if (this.matchPattern(_string.$7) case _?) {
              if ($1 case var $) {
                return $.join() ;
              }
            }
          }
        }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$20) case _?) {
      var _mark = this._mark();
        if (this.f18() case var _2) {
          if ([if (_2 case var _2?) _2] case (var $1 && var _l3)) {
            if (_l3.isNotEmpty) {
              for (;;) {
                var _mark = this._mark();
                if (this.f18() case var _2?) {
                  _l3.add(_2);
                  continue;
                }
                this._recover(_mark);
                break;
              }
            } else {
              this._recover(_mark);
            }
            if (this.matchPattern(_string.$9) case _?) {
              if ($1 case var $) {
                return $.join() ;
              }
            }
          }
        }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$21) case _?) {
      var _mark = this._mark();
        if (this.f19() case var _4) {
          if ([if (_4 case var _4?) _4] case (var $1 && var _l5)) {
            if (_l5.isNotEmpty) {
              for (;;) {
                var _mark = this._mark();
                if (this.f19() case var _4?) {
                  _l5.add(_4);
                  continue;
                }
                this._recover(_mark);
                break;
              }
            } else {
              this._recover(_mark);
            }
            if (this.matchPattern(_string.$10) case _?) {
              if ($1 case var $) {
                return $.join() ;
              }
            }
          }
        }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$22) case _?) {
      var _mark = this._mark();
        if (this.f1a() case var _6) {
          if ([if (_6 case var _6?) _6] case (var $1 && var _l7)) {
            if (_l7.isNotEmpty) {
              for (;;) {
                var _mark = this._mark();
                if (this.f1a() case var _6?) {
                  _l7.add(_6);
                  continue;
                }
                this._recover(_mark);
                break;
              }
            } else {
              this._recover(_mark);
            }
            if (this.matchPattern(_string.$11) case _?) {
              if ($1 case var $) {
                return $.join() ;
              }
            }
          }
        }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$7) case _?) {
      var _mark = this._mark();
        if (this.f1b() case var _8) {
          if ([if (_8 case var _8?) _8] case (var $1 && var _l9)) {
            if (_l9.isNotEmpty) {
              for (;;) {
                var _mark = this._mark();
                if (this.f1b() case var _8?) {
                  _l9.add(_8);
                  continue;
                }
                this._recover(_mark);
                break;
              }
            } else {
              this._recover(_mark);
            }
            if (this.matchPattern(_string.$7) case _?) {
              if ($1 case var $) {
                return $.join() ;
              }
            }
          }
        }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$9) case _?) {
      var _mark = this._mark();
        if (this.f1c() case var _10) {
          if ([if (_10 case var _10?) _10] case (var $1 && var _l11)) {
            if (_l11.isNotEmpty) {
              for (;;) {
                var _mark = this._mark();
                if (this.f1c() case var _10?) {
                  _l11.add(_10);
                  continue;
                }
                this._recover(_mark);
                break;
              }
            } else {
              this._recover(_mark);
            }
            if (this.matchPattern(_string.$9) case _?) {
              if ($1 case var $) {
                return $.join() ;
              }
            }
          }
        }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$10) case _?) {
      var _mark = this._mark();
        if (this.f1d() case var _12) {
          if ([if (_12 case var _12?) _12] case (var $1 && var _l13)) {
            if (_l13.isNotEmpty) {
              for (;;) {
                var _mark = this._mark();
                if (this.f1d() case var _12?) {
                  _l13.add(_12);
                  continue;
                }
                this._recover(_mark);
                break;
              }
            } else {
              this._recover(_mark);
            }
            if (this.matchPattern(_string.$10) case _?) {
              if ($1 case var $) {
                return $.join() ;
              }
            }
          }
        }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$11) case _?) {
      var _mark = this._mark();
        if (this.f1e() case var _14) {
          if ([if (_14 case var _14?) _14] case (var $1 && var _l15)) {
            if (_l15.isNotEmpty) {
              for (;;) {
                var _mark = this._mark();
                if (this.f1e() case var _14?) {
                  _l15.add(_14);
                  continue;
                }
                this._recover(_mark);
                break;
              }
            } else {
              this._recover(_mark);
            }
            if (this.matchPattern(_string.$11) case _?) {
              if ($1 case var $) {
                return $.join() ;
              }
            }
          }
        }
    }
  }

  /// `fragment23`
  String? f1g() {
    var _mark = this._mark();
    if (this.matchPattern(_regexp.$1) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.matchPattern(_regexp.$2) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$23) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$24) case var $?) {
      return $;
    }
  }

  /// `fragment24`
  String? f1h() {
    var _mark = this._mark();
    if (this._applyMemo(this.rg) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$26) case _?) {
      if (this._applyMemo(this.rf)! case var $1) {
        if (this.matchPattern(_string.$25) case _?) {
          if ($1 case var $) {
            return "{" + $ + "}";
          }
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$27) case _?) {
      if (this._applyMemo(this.rf)! case var $1) {
        if (this.matchPattern(_string.$24) case _?) {
          if ($1 case var $) {
            return "(" + $ + ")";
          }
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$18) case _?) {
      if (this._applyMemo(this.rf)! case var $1) {
        if (this.matchPattern(_string.$5) case _?) {
          if ($1 case var $) {
            return "[" + $ + "]";
          }
        }
      }
    }
    this._recover(_mark);
    if (this.f1g() case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  }

  /// `fragment25`
  String? f1i() {
    var _mark = this._mark();
    if (this.matchPattern(_string.$25) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$24) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$5) case var $?) {
      return $;
    }
  }

  /// `fragment26`
  String? f1j() {
    var _mark = this._mark();
    if (this._applyMemo(this.rg) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$26) case _?) {
      if (this._applyMemo(this.rf)! case var $1) {
        if (this.matchPattern(_string.$25) case _?) {
          if ($1 case var $) {
            return "{" + $ + "}";
          }
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$27) case _?) {
      if (this._applyMemo(this.rf)! case var $1) {
        if (this.matchPattern(_string.$24) case _?) {
          if ($1 case var $) {
            return "(" + $ + ")";
          }
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$18) case _?) {
      if (this._applyMemo(this.rf)! case var $1) {
        if (this.matchPattern(_string.$5) case _?) {
          if ($1 case var $) {
            return "[" + $ + "]";
          }
        }
      }
    }
    this._recover(_mark);
    if (this.f1i() case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  }

  /// `fragment27`
  String? f1k() {
    if (this.pos case var from) {
      if (this.fs() case var $?) {
        if (this.pos case var to) {
          if (this.buffer.substring(from, to) case var span) {
            return span;
          }
        }
      }
    }
  }

  /// `fragment28`
  String? f1l() {
    var _mark = this._mark();
    if (this._applyMemo(this.rg) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$26) case _?) {
      if (this._applyMemo(this.rj)! case (var $1 && var $)) {
        if (this.matchPattern(_string.$25) case _?) {
          if ($1 case var $) {
            return "{" + $ + "}";
          }
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
  }

  /// `fragment29`
  String? f1m() {
    if (this._applyMemo(this.r21) case var $?) {
      return $;
    }
  }

  /// `fragment30`
  String? f1n() {
    if (this._applyLr(this.rk) case var _0?) {
      if ([_0] case (var $ && var _l1)) {
        for (;;) {
          var _mark = this._mark();
          if (this._applyMemo(this.r27) case _?) {
            if (this._applyLr(this.rk) case var _0?) {
              _l1.add(_0);
              continue;
            }
          }
          this._recover(_mark);
          break;
        }
        return $.join(", ") ;
      }
    }
  }

  /// `fragment31`
  String? f1o() {
    if (this._applyMemo(this.r27) case var $?) {
      return $;
    }
  }

  /// `fragment32`
  String? f1p() {
    if (this._applyMemo(this.r27) case var $?) {
      return $;
    }
  }

  /// `fragment33`
  String? f1q() {
    if (this._applyMemo(this.r27) case var $?) {
      return $;
    }
  }

  /// `fragment34`
  String? f1r() {
    if (this._applyMemo(this.r27) case var $?) {
      return $;
    }
  }

  /// `fragment35`
  String? f1s() {
    if (this._applyMemo(this.r18) case var $?) {
      return $;
    }
  }

  /// `fragment36`
  String? f1t() {
    if (this._applyLr(this.rk) case var $0?) {
      if (this._applyMemo(this.r2d)! case _) {
        return $0;
      }
    }
  }

  /// `fragment37`
  Object? f1u() {
    var _mark = this._mark();
    if (this.matchPattern(_string.$28) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$30) case (var $0 && null)) {
      this._recover(_mark);
      if (this.matchPattern(_string.$29) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `fragment38`
  String? f1v() {
    if (this._applyMemo(this.r18) case (var $0 && var identifier)?) {
      if (this.f1u() case _?) {
        var _mark = this._mark();
        if (this.r1g() case null) {
          this._recover(_mark);
          return $0;
        }
      }
    }
  }

  /// `fragment39`
  String? f1w() {
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

  /// `fragment40`
  String? f1x() {
    if (this.matchPattern(_string.$6) case _?) {
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
            if (this.matchPattern(_string.$6) case _?) {
              if ($1 case var $) {
                return $.join() ;
              }
            }
          }
        }
    }
  }

  /// `fragment41`
  String? f1y() {
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

  /// `fragment42`
  String f1z() {
    if (this.pos case var from) {
      if (this.f1y() case var _0) {
        var _mark = this._mark();
        var _l1 = [if (_0 case var _0?) _0];
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

  /// `fragment43`
  Tag? f20() {
    var _mark = this._mark();
    if (this.matchPattern(_string.$31) case var $?) {
      return Tag.rule;
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$32) case var $?) {
      return Tag.fragment;
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$33) case var $?) {
      return Tag.inline;
    }
  }

  /// `fragment44`
  String? f21() {
    if (this._applyMemo(this.r28) case var $?) {
      return $;
    }
  }

  /// `fragment45`
  Object? f22() {
    var _mark = this._mark();
    if (this.r2e() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$1) case var $0?) {
      this._recover(_mark);
      if (this.r2f() case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `fragment46`
  String? f23() {
    if (this.matchPattern(_regexp.$1) case var $?) {
      return $;
    }
  }

  /// `fragment47`
  String? f24() {
    if (this.matchPattern(_regexp.$1) case var $?) {
      return $;
    }
  }

  /// `fragment48`
  Object? f25() {
    var _mark = this._mark();
    if (this.f23() case var $0) {
      if (this.matchPattern(_regexp.$2) case var $1?) {
        if (this.f24() case var $2) {
          return ($0, $1, $2);
        }
      }
    }
    this._recover(_mark);
    if (this.pos case var $ when this.pos >= this.buffer.length) {
      return $;
    }
  }

  /// `fragment49`
  String? f26() {
    var _mark = this._mark();
    if (this.f25() case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  }

  /// `fragment50`
  String? f27() {
    var _mark = this._mark();
    if (this.matchPattern(_string.$34) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  }

  /// `fragment51`
  String? f28() {
    var _mark = this._mark();
    if (this.matchPattern(_string.$4) case _?) {
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $1) {
          if ($1 case var $) {
            return r"\" + $ ;
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
  }

  /// `fragment52`
  String? f29() {
    if (this.f28() case var _0?) {
      if ([_0] case (var $ && var _l1)) {
        for (;;) {
          var _mark = this._mark();
          if (this.f28() case var _0?) {
            _l1.add(_0);
            continue;
          }
          this._recover(_mark);
          break;
        }
        return $.join() ;
      }
    }
  }

  /// `fragment53`
  String? f2a() {
    var _mark = this._mark();
    if (this.matchPattern(_string.$7) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  }

  /// `fragment54`
  String? f2b() {
    var _mark = this._mark();
    if (this.matchPattern(_string.$9) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  }

  /// `fragment55`
  String? f2c() {
    var _mark = this._mark();
    if (this.matchPattern(_string.$10) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  }

  /// `fragment56`
  String? f2d() {
    var _mark = this._mark();
    if (this.matchPattern(_string.$11) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  }

  /// `fragment57`
  String? f2e() {
    var _mark = this._mark();
    if (this.matchPattern(_string.$4) case _?) {
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $1) {
          return $1;
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$7) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  }

  /// `fragment58`
  String? f2f() {
    var _mark = this._mark();
    if (this.matchPattern(_string.$4) case _?) {
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $1) {
          return $1;
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$9) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  }

  /// `fragment59`
  String? f2g() {
    var _mark = this._mark();
    if (this.matchPattern(_string.$4) case _?) {
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $1) {
          return $1;
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$10) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  }

  /// `fragment60`
  String? f2h() {
    var _mark = this._mark();
    if (this.matchPattern(_string.$4) case _?) {
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $1) {
          return $1;
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$11) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  }

  /// `fragment61`
  String? f2i() {
    var _mark = this._mark();
    if (this.matchPattern(_string.$19) case _?) {
      var _mark = this._mark();
        if (this.f2a() case var _0) {
          if ([if (_0 case var _0?) _0] case (var $1 && var _l1)) {
            if (_l1.isNotEmpty) {
              for (;;) {
                var _mark = this._mark();
                if (this.f2a() case var _0?) {
                  _l1.add(_0);
                  continue;
                }
                this._recover(_mark);
                break;
              }
            } else {
              this._recover(_mark);
            }
            if (this.matchPattern(_string.$7) case _?) {
              if ($1 case var $) {
                return $.join() ;
              }
            }
          }
        }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$20) case _?) {
      var _mark = this._mark();
        if (this.f2b() case var _2) {
          if ([if (_2 case var _2?) _2] case (var $1 && var _l3)) {
            if (_l3.isNotEmpty) {
              for (;;) {
                var _mark = this._mark();
                if (this.f2b() case var _2?) {
                  _l3.add(_2);
                  continue;
                }
                this._recover(_mark);
                break;
              }
            } else {
              this._recover(_mark);
            }
            if (this.matchPattern(_string.$9) case _?) {
              if ($1 case var $) {
                return $.join() ;
              }
            }
          }
        }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$21) case _?) {
      var _mark = this._mark();
        if (this.f2c() case var _4) {
          if ([if (_4 case var _4?) _4] case (var $1 && var _l5)) {
            if (_l5.isNotEmpty) {
              for (;;) {
                var _mark = this._mark();
                if (this.f2c() case var _4?) {
                  _l5.add(_4);
                  continue;
                }
                this._recover(_mark);
                break;
              }
            } else {
              this._recover(_mark);
            }
            if (this.matchPattern(_string.$10) case _?) {
              if ($1 case var $) {
                return $.join() ;
              }
            }
          }
        }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$22) case _?) {
      var _mark = this._mark();
        if (this.f2d() case var _6) {
          if ([if (_6 case var _6?) _6] case (var $1 && var _l7)) {
            if (_l7.isNotEmpty) {
              for (;;) {
                var _mark = this._mark();
                if (this.f2d() case var _6?) {
                  _l7.add(_6);
                  continue;
                }
                this._recover(_mark);
                break;
              }
            } else {
              this._recover(_mark);
            }
            if (this.matchPattern(_string.$11) case _?) {
              if ($1 case var $) {
                return $.join() ;
              }
            }
          }
        }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$7) case _?) {
      var _mark = this._mark();
        if (this.f2e() case var _8) {
          if ([if (_8 case var _8?) _8] case (var $1 && var _l9)) {
            if (_l9.isNotEmpty) {
              for (;;) {
                var _mark = this._mark();
                if (this.f2e() case var _8?) {
                  _l9.add(_8);
                  continue;
                }
                this._recover(_mark);
                break;
              }
            } else {
              this._recover(_mark);
            }
            if (this.matchPattern(_string.$7) case _?) {
              if ($1 case var $) {
                return $.join() ;
              }
            }
          }
        }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$9) case _?) {
      var _mark = this._mark();
        if (this.f2f() case var _10) {
          if ([if (_10 case var _10?) _10] case (var $1 && var _l11)) {
            if (_l11.isNotEmpty) {
              for (;;) {
                var _mark = this._mark();
                if (this.f2f() case var _10?) {
                  _l11.add(_10);
                  continue;
                }
                this._recover(_mark);
                break;
              }
            } else {
              this._recover(_mark);
            }
            if (this.matchPattern(_string.$9) case _?) {
              if ($1 case var $) {
                return $.join() ;
              }
            }
          }
        }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$10) case _?) {
      var _mark = this._mark();
        if (this.f2g() case var _12) {
          if ([if (_12 case var _12?) _12] case (var $1 && var _l13)) {
            if (_l13.isNotEmpty) {
              for (;;) {
                var _mark = this._mark();
                if (this.f2g() case var _12?) {
                  _l13.add(_12);
                  continue;
                }
                this._recover(_mark);
                break;
              }
            } else {
              this._recover(_mark);
            }
            if (this.matchPattern(_string.$10) case _?) {
              if ($1 case var $) {
                return $.join() ;
              }
            }
          }
        }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$11) case _?) {
      var _mark = this._mark();
        if (this.f2h() case var _14) {
          if ([if (_14 case var _14?) _14] case (var $1 && var _l15)) {
            if (_l15.isNotEmpty) {
              for (;;) {
                var _mark = this._mark();
                if (this.f2h() case var _14?) {
                  _l15.add(_14);
                  continue;
                }
                this._recover(_mark);
                break;
              }
            } else {
              this._recover(_mark);
            }
            if (this.matchPattern(_string.$11) case _?) {
              if ($1 case var $) {
                return $.join() ;
              }
            }
          }
        }
    }
  }

  /// `fragment62`
  Set<(int, int)>? f2j() {
    var _mark = this._mark();
    if (this.matchPattern(_string.$2) case var $?) {
      return {(32, 32)} ;
    }
    this._recover(_mark);
    if (this.f7() case var $?) {
      return {(48, 57)} ;
    }
    this._recover(_mark);
    if (this.f9() case var $?) {
      return {(64 + 1, 64 + 26), (96 + 1, 96 + 26)} ;
    }
    this._recover(_mark);
    if (this.fb() case var $?) {
      return {(9, 13), (32, 32)} ;
    }
    this._recover(_mark);
    if (this.fe() case var $?) {
      return {(10, 10)} ;
    }
    this._recover(_mark);
    if (this.ff() case var $?) {
      return {(13, 13)} ;
    }
    this._recover(_mark);
    if (this.fg() case var $?) {
      return {(9, 9)} ;
    }
    this._recover(_mark);
    if (this.f6() case var $?) {
      return {(92, 92)} ;
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

  /// `fragment63`
  Set<(int, int)>? f2k() {
    if (this.matchPattern(_string.$18) case _?) {
      if (this.f2j() case var _0?) {
        if ([_0] case (var $1 && var elements && var _l1)) {
          for (;;) {
            var _mark = this._mark();
            if (this.f2j() case var _0?) {
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
  }

  /// `fragment64`
  String? f2l() {
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
  String? f2m() {
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
  }

  /// `fragment66`
  String? f2n() {
    if (this.f2m() case var $0?) {
      if (this._applyMemo(this.r2d)! case _) {
        return $0;
      }
    }
  }

  /// `fragment67`
  String? f2o() {
    if (this.pos case var from) {
      if (this.matchPattern(_string.$4) case _?) {
        if (this.matchPattern(_string.$35) case _?) {
          if (this.pos case var to) {
            if (this.buffer.substring(from, to) case var span) {
              return span;
            }
          }
        }
      }
    }
  }

  /// `fragment68`
  String? f2p() {
    if (this.pos case var from) {
      if (this.matchPattern(_string.$4) case _?) {
        if (this.matchPattern(_string.$12) case _?) {
          if (this.pos case var to) {
            if (this.buffer.substring(from, to) case var span) {
              return span;
            }
          }
        }
      }
    }
  }

  /// `fragment69`
  String? f2q() {
    if (this.pos case var from) {
      if (this.matchPattern(_string.$4) case _?) {
        if (this.matchPattern(_string.$36) case _?) {
          if (this.pos case var to) {
            if (this.buffer.substring(from, to) case var span) {
              return span;
            }
          }
        }
      }
    }
  }

  /// `fragment70`
  String? f2r() {
    if (this.pos case var from) {
      if (this.matchPattern(_string.$4) case _?) {
        if (this.matchPattern(_string.$13) case _?) {
          if (this.pos case var to) {
            if (this.buffer.substring(from, to) case var span) {
              return span;
            }
          }
        }
      }
    }
  }

  /// `fragment71`
  String? f2s() {
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
  }

  /// `fragment72`
  String? f2t() {
    if (this.pos case var from) {
      if (this.matchPattern(_string.$4) case _?) {
        if (this.matchPattern(_string.$14) case _?) {
          if (this.pos case var to) {
            if (this.buffer.substring(from, to) case var span) {
              return span;
            }
          }
        }
      }
    }
  }

  /// `fragment73`
  String? f2u() {
    if (this.pos case var from) {
      if (this.matchPattern(_string.$4) case _?) {
        if (this.matchPattern(_string.$17) case _?) {
          if (this.pos case var to) {
            if (this.buffer.substring(from, to) case var span) {
              return span;
            }
          }
        }
      }
    }
  }

  /// `fragment74`
  String? f2v() {
    if (this.pos case var from) {
      if (this.matchPattern(_string.$4) case _?) {
        if (this.matchPattern(_string.$38) case _?) {
          if (this.pos case var to) {
            if (this.buffer.substring(from, to) case var span) {
              return span;
            }
          }
        }
      }
    }
  }

  /// `fragment75`
  String? f2w() {
    if (this.pos case var from) {
      if (this.matchPattern(_string.$4) case _?) {
        if (this.matchPattern(_string.$8) case _?) {
          if (this.pos case var to) {
            if (this.buffer.substring(from, to) case var span) {
              return span;
            }
          }
        }
      }
    }
  }

  /// `fragment76`
  String? f2x() {
    if (this.pos case var from) {
      if (this.matchPattern(_string.$4) case _?) {
        if (this.matchPattern(_string.$39) case _?) {
          if (this.pos case var to) {
            if (this.buffer.substring(from, to) case var span) {
              return span;
            }
          }
        }
      }
    }
  }

  /// `fragment77`
  String? f2y() {
    if (this.pos case var from) {
      if (this.matchPattern(_string.$4) case _?) {
        if (this.matchPattern(_string.$15) case _?) {
          if (this.pos case var to) {
            if (this.buffer.substring(from, to) case var span) {
              return span;
            }
          }
        }
      }
    }
  }

  /// `fragment78`
  String? f2z() {
    if (this.pos case var from) {
      if (this.matchPattern(_string.$4) case _?) {
        if (this.matchPattern(_string.$16) case _?) {
          if (this.pos case var to) {
            if (this.buffer.substring(from, to) case var span) {
              return span;
            }
          }
        }
      }
    }
  }

  /// `fragment79`
  Tag? f30() {
    if (this._applyMemo(this.r1b) case var $?) {
      return $;
    }
  }

  /// `fragment80`
  Tag? f31() {
    if (this._applyMemo(this.r1b) case var $?) {
      return $;
    }
  }

  /// `fragment81`
  String? f32() {
    if (this._applyMemo(this.r1z) case var $?) {
      return $;
    }
  }

  /// `fragment82`
  Tag? f33() {
    if (this._applyMemo(this.r1b) case var $?) {
      return $;
    }
  }

  /// `fragment83`
  Tag? f34() {
    if (this._applyMemo(this.r1b) case var $?) {
      return $;
    }
  }

  /// `fragment84`
  String? f35() {
    if (this._applyMemo(this.r1z) case var $?) {
      return $;
    }
  }

  /// `fragment85`
  Tag? f36() {
    if (this._applyMemo(this.r1b) case var $?) {
      return $;
    }
  }

  /// `fragment86`
  String? f37() {
    if (this._applyLr(this.r13) case var $?) {
      return $;
    }
  }

  /// `fragment87`
  Tag? f38() {
    if (this._applyMemo(this.r1b) case var $?) {
      return $;
    }
  }

  /// `fragment88`
  String? f39() {
    if (this._applyMemo(this.r1z) case var $?) {
      return $;
    }
  }

  /// `fragment89`
  Tag? f3a() {
    if (this._applyMemo(this.r1b) case var $?) {
      return $;
    }
  }

  /// `fragment90`
  String? f3b() {
    if (this._applyMemo(this.r18) case var $?) {
      return $;
    }
  }

  /// `fragment91`
  Tag? f3c() {
    if (this._applyMemo(this.r1b) case var $?) {
      return $;
    }
  }

  /// `fragment92`
  String? f3d() {
    if (this._applyLr(this.r13) case var $?) {
      return $;
    }
  }

  /// `fragment93`
  Tag? f3e() {
    if (this._applyMemo(this.r1b) case var $?) {
      return $;
    }
  }

  /// `fragment94`
  Tag? f3f() {
    if (this._applyMemo(this.r1b) case var $?) {
      return $;
    }
  }

  /// `fragment95`
  String? f3g() {
    var _mark = this._mark();
    if (this.matchPattern(_string.$25) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$23) case var $?) {
      return $;
    }
  }

  /// `fragment96`
  String? f3h() {
    var _mark = this._mark();
    if (this._applyMemo(this.rg) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$26) case _?) {
      if (this._applyMemo(this.rf)! case var $1) {
        if (this.matchPattern(_string.$25) case _?) {
          if ($1 case var $) {
            return "{" + $ + "}";
          }
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$27) case _?) {
      if (this._applyMemo(this.rf)! case var $1) {
        if (this.matchPattern(_string.$24) case _?) {
          if ($1 case var $) {
            return "(" + $ + ")";
          }
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$18) case _?) {
      if (this._applyMemo(this.rf)! case var $1) {
        if (this.matchPattern(_string.$5) case _?) {
          if ($1 case var $) {
            return "[" + $ + "]";
          }
        }
      }
    }
    this._recover(_mark);
    if (this.f3g() case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  }

  /// `fragment97`
  String? f3i() {
    var _mark = this._mark();
    if (this.matchPattern(_string.$7) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  }

  /// `fragment98`
  String? f3j() {
    var _mark = this._mark();
    if (this.matchPattern(_string.$9) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  }

  /// `fragment99`
  String? f3k() {
    var _mark = this._mark();
    if (this.matchPattern(_string.$10) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  }

  /// `fragment100`
  String? f3l() {
    var _mark = this._mark();
    if (this.matchPattern(_string.$11) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  }

  /// `fragment101`
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
    if (this.matchPattern(_string.$40) case var $0?) {
      this._recover(_mark);
      if (this._applyMemo(this.ri) case var $1?) {
        return ($0, $1);
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$7) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  }

  /// `fragment102`
  Object? f3n() {
    var _mark = this._mark();
    if (this.matchPattern(_string.$4) case _?) {
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $1) {
          return $1;
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$40) case var $0?) {
      this._recover(_mark);
      if (this._applyMemo(this.ri) case var $1?) {
        return ($0, $1);
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$9) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  }

  /// `fragment103`
  Object? f3o() {
    var _mark = this._mark();
    if (this.matchPattern(_string.$4) case _?) {
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $1) {
          return $1;
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$40) case var $0?) {
      this._recover(_mark);
      if (this._applyMemo(this.ri) case var $1?) {
        return ($0, $1);
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$10) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  }

  /// `fragment104`
  Object? f3p() {
    var _mark = this._mark();
    if (this.matchPattern(_string.$4) case _?) {
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $1) {
          return $1;
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$40) case var $0?) {
      this._recover(_mark);
      if (this._applyMemo(this.ri) case var $1?) {
        return ($0, $1);
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$11) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  }

  /// `global::document`
  ParserGenerator? r0() {
    if (this.pos <= 0) {
      if (this.ft() case var $1) {
        if (this._applyLr(this.r2) case var _0?) {
          if ([_0] case (var $2 && var _l1)) {
            for (;;) {
              var _mark = this._mark();
              if (this._applyMemo(this.r2d)! case _) {
                if (this._applyLr(this.r2) case var _0?) {
                  _l1.add(_0);
                  continue;
                }
              }
              this._recover(_mark);
              break;
            }
            if (this.fu() case _) {
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
    if (this._applyMemo(this.r1v) case _?) {
      if (this._applyMemo(this.r2d)! case _) {
        if (this.rd()! case (var $2 && var code)) {
          if (this._applyMemo(this.r2d)! case _) {
            if (this._applyMemo(this.r1y) case _?) {
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
    if (this.fn() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.fo() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.fp() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.fq() case var $?) {
      return $;
    }
  }

  /// `global::choice`
  Node? r3() {
    if (this.fv() case _) {
      if (this._applyLr(this.r4) case var _0?) {
        if ([_0] case (var $1 && var options && var _l1)) {
          for (;;) {
            var _mark = this._mark();
            if (this._applyMemo(this.r1i) case _?) {
              if (this._applyLr(this.r4) case var _0?) {
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
    if (this._applyLr(this.r5) case var sequence?) {
      if (this.r1o() case _?) {
        if (this._applyMemo(this.r2d)! case _) {
          if (this._applyMemo(this.re)! case var code) {
            if (this._applyMemo(this.r2d)! case _) {
              return inlineAction(sequence, code);
            }
          }
        }
      }
    }
    this._recover(_mark);
    if (this._applyLr(this.r5) case var sequence?) {
      if (this.r1l() case _?) {
        if (this._applyMemo(this.r2d)! case _) {
          if (this._applyMemo(this.re)! case var code) {
            if (this._applyMemo(this.r2d)! case _) {
              return inlineAction(sequence, code);
            }
          }
        }
      }
    }
    this._recover(_mark);
    if (this._applyLr(this.r5) case var sequence?) {
      if (this._applyMemo(this.r1v) case _?) {
        if (this._applyMemo(this.r2d)! case _) {
          if (this._applyMemo(this.rc)! case var code) {
            if (this._applyMemo(this.r2d)! case _) {
              if (this._applyMemo(this.r1y) case _?) {
                return inlineBlockAction(sequence, code);
              }
            }
          }
        }
      }
    }
    this._recover(_mark);
    if (this._applyLr(this.r5) case var sequence?) {
      if (this._applyMemo(this.r1w) case _?) {
        if (this._applyMemo(this.r1x) case _?) {
          if (this._applyMemo(this.r1v) case _?) {
            if (this._applyMemo(this.r2d)! case _) {
              if (this._applyMemo(this.rc)! case var code) {
                if (this._applyMemo(this.r2d)! case _) {
                  if (this._applyMemo(this.r1y) case _?) {
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
    if (this._applyLr(this.r5) case var $?) {
      return $;
    }
  }

  /// `global::sequence`
  Node? r5() {
    if (this._applyLr(this.r6) case var _0?) {
      if ([_0] case (var body && var _l1)) {
        for (;;) {
          var _mark = this._mark();
          if (this._applyMemo(this.r2d)! case _) {
            if (this._applyLr(this.r6) case var _0?) {
              _l1.add(_0);
              continue;
            }
          }
          this._recover(_mark);
          break;
        }
        if (this.fw() case var chosen) {
          return body.length == 1 ? body.single : SequenceNode(body, chosenIndex: chosen);
        }
      }
    }
  }

  /// `global::dropped`
  Node? r6() {
    var _mark = this._mark();
    if (this._applyLr(this.r6) case var captured?) {
      if (this._applyMemo(this.r1n) case _?) {
        if (this._applyLr(this.r8) case var dropped?) {
          return SequenceNode([captured, dropped], chosenIndex: 0) ;
        }
      }
    }
    this._recover(_mark);
    if (this._applyLr(this.r8) case var dropped?) {
      if (this.r1m() case _?) {
        if (this._applyLr(this.r6) case var captured?) {
          return SequenceNode([dropped, captured], chosenIndex: 1) ;
        }
      }
    }
    this._recover(_mark);
    if (this._applyLr(this.r7) case var $?) {
      return $;
    }
  }

  /// `global::labeled`
  Node? r7() {
    var _mark = this._mark();
    if (this._applyMemo(this.r18) case var identifier?) {
      if (this.matchPattern(_string.$41) case _?) {
        if (this._applyMemo(this.r2d)! case _) {
          if (this._applyLr(this.r8) case var special?) {
            return NamedNode(identifier, special)
                ;
          }
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$41) case _?) {
      if (this._applyMemo(this.r17) case (var $1 && var id)?) {
        if (this._applyMemo(this.r21) case _?) {
          var name = id.split(ParserGenerator.separator).last;return 

                NamedNode(name, OptionalNode(ReferenceNode(id)))
              ;
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$41) case _?) {
      if (this._applyMemo(this.r17) case (var $1 && var id)?) {
        if (this._applyMemo(this.r25) case _?) {
          var name = id.split(ParserGenerator.separator).last;return 

                NamedNode(name, StarNode(ReferenceNode(id)))
              ;
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$41) case _?) {
      if (this._applyMemo(this.r17) case (var $1 && var id)?) {
        if (this._applyMemo(this.r26) case _?) {
          var name = id.split(ParserGenerator.separator).last;

                return NamedNode(name, PlusNode(ReferenceNode(id)));
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$41) case _?) {
      if (this._applyMemo(this.r17) case (var $1 && var id)?) {
        var name = id.split(ParserGenerator.separator).last;

              return NamedNode(name, ReferenceNode(id));
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$41) case _?) {
      if (this._applyLr(this.r8) case (var $1 && var node)?) {
        if ($1 case var $) {
          return NamedNode(r"$", node) ;
        }
      }
    }
    this._recover(_mark);
    if (this._applyLr(this.r8) case var $?) {
      return $;
    }
  }

  /// `global::special`
  Node? r8() {
    var _mark = this._mark();
    if (this._applyMemo(this.rb) case var sep?) {
      if (this._applyMemo(this.r1k) case _?) {
        if (this._applyMemo(this.rb) case var expr?) {
          if (this._applyMemo(this.r26) case _?) {
            if (this._applyMemo(this.r21) case _?) {
              return PlusSeparatedNode(sep, expr, isTrailingAllowed: true);
            }
          }
        }
      }
    }
    this._recover(_mark);
    if (this._applyMemo(this.rb) case var sep?) {
      if (this._applyMemo(this.r1k) case _?) {
        if (this._applyMemo(this.rb) case var expr?) {
          if (this._applyMemo(this.r25) case _?) {
            if (this._applyMemo(this.r21) case _?) {
              return StarSeparatedNode(sep, expr, isTrailingAllowed: true);
            }
          }
        }
      }
    }
    this._recover(_mark);
    if (this._applyMemo(this.rb) case var sep?) {
      if (this._applyMemo(this.r1k) case _?) {
        if (this._applyMemo(this.rb) case var expr?) {
          if (this._applyMemo(this.r26) case _?) {
            return PlusSeparatedNode(sep, expr, isTrailingAllowed: false);
          }
        }
      }
    }
    this._recover(_mark);
    if (this._applyMemo(this.rb) case var sep?) {
      if (this._applyMemo(this.r1k) case _?) {
        if (this._applyMemo(this.rb) case var expr?) {
          if (this._applyMemo(this.r25) case _?) {
            return StarSeparatedNode(sep, expr, isTrailingAllowed: false);
          }
        }
      }
    }
    this._recover(_mark);
    if (this._applyLr(this.r9) case var $?) {
      return $;
    }
  }

  /// `global::postfix`
  Node? r9() {
    var _mark = this._mark();
    if (this._applyLr(this.r9) case var $0?) {
      if (this._applyMemo(this.r21) case _?) {
        if ($0 case var $) {
          return OptionalNode($);
        }
      }
    }
    this._recover(_mark);
    if (this._applyLr(this.r9) case var $0?) {
      if (this._applyMemo(this.r25) case _?) {
        if ($0 case var $) {
          return StarNode($);
        }
      }
    }
    this._recover(_mark);
    if (this._applyLr(this.r9) case var $0?) {
      if (this._applyMemo(this.r26) case _?) {
        if ($0 case var $) {
          return PlusNode($);
        }
      }
    }
    this._recover(_mark);
    if (this._applyMemo(this.ra) case var $?) {
      return $;
    }
  }

  /// `global::prefix`
  Node? ra() {
    var _mark = this._mark();
    if (this._applyMemo(this.r1a) case var min?) {
      if (this._applyMemo(this.r1k) case _?) {
        if (this._applyMemo(this.r1a) case var max?) {
          if (this._applyMemo(this.rb) case var body?) {
            return CountedNode(min, max, body);
          }
        }
      }
    }
    this._recover(_mark);
    if (this._applyMemo(this.r1a) case var min?) {
      if (this._applyMemo(this.r1k) case _?) {
        if (this._applyMemo(this.rb) case var body?) {
          return CountedNode(min, null, body);
        }
      }
    }
    this._recover(_mark);
    if (this._applyMemo(this.r1a) case var number?) {
      if (this._applyMemo(this.rb) case var body?) {
        return CountedNode(number, number, body);
      }
    }
    this._recover(_mark);
    if (this.r23() case _?) {
      if (this._applyMemo(this.ra) case var $1?) {
        if ($1 case var $) {
          return ExceptNode($);
        }
      }
    }
    this._recover(_mark);
    if (this.r24() case _?) {
      if (this._applyMemo(this.ra) case var $1?) {
        if ($1 case var $) {
          return AndPredicateNode($);
        }
      }
    }
    this._recover(_mark);
    if (this.r22() case _?) {
      if (this._applyMemo(this.ra) case var $1?) {
        if ($1 case var $) {
          return NotPredicateNode($);
        }
      }
    }
    this._recover(_mark);
    if (this._applyMemo(this.rb) case var $?) {
      return $;
    }
  }

  /// `global::atom`
  Node? rb() {
    var _mark = this._mark();
    if (this._applyMemo(this.r1w) case _?) {
      _mark.isCut = true;
      if (this._applyLr(this.r3) case (var $2 && var $)?) {
        if (this._applyMemo(this.r1x) case _?) {
          return $2;
        }
      }
    }
    if (_mark.isCut) return null; else this._recover(_mark);
    if (this._applyMemo(this.r1n) case null) {
      this._recover(_mark);
      if (this._applyMemo(this.r1r) case _?) {
        _mark.isCut = true;
        if (this._applyLr(this.r3) case (var $3 && var $)?) {
          if (this._applyMemo(this.r1s) case _?) {
            if ($3 case var $) {
              return FlatNode($);
            }
          }
        }
      }
    }
    if (_mark.isCut) return null; else this._recover(_mark);
    if (this.r2b() case var $?) {
      return const StartOfInputNode();
    }
    this._recover(_mark);
    if (this.r1c() case var $?) {
      return const StartOfInputNode();
    }
    this._recover(_mark);
    if (this.r2c() case var $?) {
      return const EndOfInputNode();
    }
    this._recover(_mark);
    if (this.r1d() case var $?) {
      return const EndOfInputNode();
    }
    this._recover(_mark);
    if (this.r2a() case var $?) {
      return const EpsilonNode();
    }
    this._recover(_mark);
    if (this.r1e() case var $?) {
      return const EpsilonNode();
    }
    this._recover(_mark);
    if (this._applyMemo(this.r29) case var $?) {
      return const AnyCharacterNode();
    }
    this._recover(_mark);
    if (this.r1f() case var $?) {
      return const AnyCharacterNode();
    }
    this._recover(_mark);
    if (this.r1j() case var $?) {
      return const CutNode();
    }
    this._recover(_mark);
    if (this.r1p() case var $?) {
      return const CutNode();
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
    if (this._applyMemo(this.r2d)! case _) {
      if (this.fx() case (var $1 && var $)?) {
        if (this._applyMemo(this.r2d)! case _) {
          return SimpleRegExpEscapeNode.notDigit;
        }
      }
    }
    this._recover(_mark);
    if (this._applyMemo(this.r2d)! case _) {
      if (this.fy() case (var $1 && var $)?) {
        if (this._applyMemo(this.r2d)! case _) {
          return SimpleRegExpEscapeNode.notWord;
        }
      }
    }
    this._recover(_mark);
    if (this._applyMemo(this.r2d)! case _) {
      if (this.fz() case (var $1 && var $)?) {
        if (this._applyMemo(this.r2d)! case _) {
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
    if (this._applyMemo(this.r2d)! case _) {
      if (this.f10() case (var $1 && var $)?) {
        if (this._applyMemo(this.r2d)! case _) {
          return SimpleRegExpEscapeNode.formFeed;
        }
      }
    }
    this._recover(_mark);
    if (this._applyMemo(this.r2d)! case _) {
      if (this.f11() case (var $1 && var $)?) {
        if (this._applyMemo(this.r2d)! case _) {
          return SimpleRegExpEscapeNode.verticalTab;
        }
      }
    }
    this._recover(_mark);
    if (this._applyMemo(this.r2d)! case _) {
      if (this.f12() case (var $1 && var $)?) {
        if (this._applyMemo(this.r2d)! case _) {
          return SimpleRegExpEscapeNode.wordBoundary;
        }
      }
    }
    this._recover(_mark);
    if (this._applyMemo(this.r2d)! case _) {
      if (this.f14() case var $1?) {
        if (this._applyMemo(this.r2d)! case _) {
          if ($1 case var $) {
            return RangeNode($);
          }
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$1) case _?) {
      if (this.f16() case var $1?) {
        if (this.matchPattern(_string.$1) case _?) {
          if ($1 case var $) {
            return RegExpNode($);
          }
        }
      }
    }
    this._recover(_mark);
    if (this._applyMemo(this.r2d)! case _) {
      if (this.f1f() case var $1?) {
        if (this._applyMemo(this.r2d)! case _) {
          if ($1 case var $) {
            return StringLiteralNode($);
          }
        }
      }
    }
    this._recover(_mark);
    if (this._applyMemo(this.r15) case var $?) {
      return ReferenceNode($);
    }
  }

  /// `global::code::curlyNotJoined`
  List<String> rc() {
    var _mark = this._mark();
    if (this.fr() case var _0) {
      if ([if (_0 case var _0) _0] case var _l1) {
        if (_l1.isNotEmpty) {
          for (;;) {
            var _mark = this._mark();
            if (this.matchPattern(_string.$23) case _?) {
              if (this.fr() case var _0) {
                _l1.add(_0);
                continue;
              }
            }
            this._recover(_mark);
            break;
          }
          var _mark = this._mark();
          if (this.matchPattern(_string.$23) case null) {
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
    if (this.fr() case var _0) {
      if ([if (_0 case var _0) _0] case (var $ && var _l1)) {
        if ($.isNotEmpty) {
          for (;;) {
            var _mark = this._mark();
            if (this.matchPattern(_string.$23) case _?) {
              if (this.fr() case var _0) {
                _l1.add(_0);
                continue;
              }
            }
            this._recover(_mark);
            break;
          }
          var _mark = this._mark();
          if (this.matchPattern(_string.$23) case null) {
            this._recover(_mark);
          }
        } else {
          this._recover(_mark);
        }
        return $.join(";") ;
      }
    }
  }

  /// `global::code::nl`
  String re() {
    var _mark = this._mark();
      if (this.f1h() case var _0) {
        if ([if (_0 case var _0?) _0] case (var $ && var _l1)) {
          if (_l1.isNotEmpty) {
            for (;;) {
              var _mark = this._mark();
              if (this.f1h() case var _0?) {
                _l1.add(_0);
                continue;
              }
              this._recover(_mark);
              break;
            }
          } else {
            this._recover(_mark);
          }
          return $.join() ;
        }
      }
  }

  /// `global::code::balanced`
  String rf() {
    var _mark = this._mark();
      if (this.f1j() case var _0) {
        if ([if (_0 case var _0?) _0] case (var $ && var _l1)) {
          if (_l1.isNotEmpty) {
            for (;;) {
              var _mark = this._mark();
              if (this.f1j() case var _0?) {
                _l1.add(_0);
                continue;
              }
              this._recover(_mark);
              break;
            }
          } else {
            this._recover(_mark);
          }
          return $.join() ;
        }
      }
  }

  /// `global::dart::literal::string`
  String? rg() {
    if (this.f1k() case var _0?) {
      if ([_0] case (var $ && var _l1)) {
        for (;;) {
          var _mark = this._mark();
          if (this._applyMemo(this.r2d)! case _) {
            if (this.f1k() case var _0?) {
              _l1.add(_0);
              continue;
            }
          }
          this._recover(_mark);
          break;
        }
        return $.join("") ;
      }
    }
  }

  /// `global::dart::literal::identifier`
  String? rh() {
    if (this._applyMemo(this.r18) case var $?) {
      return $;
    }
  }

  /// `global::dart::literal::string::interpolation`
  Record? ri() {
    var _mark = this._mark();
    if (this.matchPattern(_string.$40) case var $0?) {
      if (this.matchPattern(_string.$26) case var $1?) {
        if (this._applyMemo(this.rj)! case var $2) {
          if (this.matchPattern(_string.$25) case var $3?) {
            return ($0, $1, $2, $3);
          }
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$40) case var $0?) {
      if (this.rh() case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `global::dart::literal::string::balanced`
  String rj() {
    var _mark = this._mark();
      if (this.f1l() case var _0) {
        if ([if (_0 case var _0?) _0] case (var $ && var _l1)) {
          if (_l1.isNotEmpty) {
            for (;;) {
              var _mark = this._mark();
              if (this.f1l() case var _0?) {
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
  String? rk() {
    if (this._applyMemo(this.r2d)! case _) {
      if (this._applyLr(this.rl) case (var $1 && var nullable)?) {
        if (this._applyMemo(this.r2d)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::dart::type::nullable`
  String? rl() {
    if (this._applyLr(this.rm) case var nonNullable?) {
      if (this.f1m() case var question) {
        return "$nonNullable${question ?? ""}" ;
      }
    }
  }

  /// `global::dart::type::nonNullable`
  String? rm() {
    var _mark = this._mark();
    if (this._applyLr(this.rn) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.ro() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.rp() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this._applyMemo(this.rv) case var $?) {
      return $;
    }
  }

  /// `global::dart::type::nonNullable::function`
  String? rn() {
    if (this._applyLr(this.rl) case (var nullable && var $0)?) {
      if (this._applyMemo(this.r2d)! case _) {
        if (this.matchPattern(_string.$42) case _?) {
          if (this._applyMemo(this.r2d)! case _) {
            if (this.rw() case (var fnParameters && var $4)?) {
              return "${$0} Function${$4}" ;
            }
          }
        }
      }
    }
  }

  /// `global::dart::type::nonNullable::generic`
  String? ro() {
    if (this._applyMemo(this.rv) case var base?) {
      if (this._applyMemo(this.r1r) case _?) {
        if (this.f1n() case var args?) {
          if (this._applyMemo(this.r1s) case _?) {
            return "$base<$args>" ;
          }
        }
      }
    }
  }

  /// `global::dart::type::nonNullable::record`
  String? rp() {
    var _mark = this._mark();
    if (this.rq() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.rr() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.rs() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.rt() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.ru() case var $?) {
      return $;
    }
  }

  /// `global::dart::type::nonNullable::record::all`
  String? rq() {
    if (this._applyMemo(this.r1w) case _?) {
      if (this._applyLr(this.rz) case var positional?) {
        if (this._applyMemo(this.r27) case _?) {
          if (this._applyMemo(this.ry) case var named?) {
            if (this._applyMemo(this.r1x) case _?) {
              return "(" + positional + ", " + named + ")";
            }
          }
        }
      }
    }
  }

  /// `global::dart::type::nonNullable::record::singlePositional`
  String? rr() {
    if (this._applyMemo(this.r1w) case _?) {
      if (this._applyLr(this.r11) case (var $1 && var field)?) {
        if (this._applyMemo(this.r27) case _?) {
          if (this._applyMemo(this.r1x) case _?) {
            return "(" + field + "," + ")";
          }
        }
      }
    }
  }

  /// `global::dart::type::nonNullable::record::onlyPositional`
  String? rs() {
    if (this._applyMemo(this.r1w) case _?) {
      if (this._applyLr(this.rz) case (var $1 && var positional)?) {
        if (this.f1o() case _) {
          if (this._applyMemo(this.r1x) case _?) {
            return "(" + positional + ")";
          }
        }
      }
    }
  }

  /// `global::dart::type::nonNullable::record::onlyNamed`
  String? rt() {
    if (this._applyMemo(this.r1w) case _?) {
      if (this._applyMemo(this.ry) case (var $1 && var named)?) {
        if (this._applyMemo(this.r1x) case _?) {
          return "(" + named + ")";
        }
      }
    }
  }

  /// `global::dart::type::nonNullable::record::empty`
  String? ru() {
    if (this._applyMemo(this.r1w) case _?) {
      if (this._applyMemo(this.r1x) case _?) {
        return "()";
      }
    }
  }

  /// `global::dart::type::nonNullable::base`
  String? rv() {
    if (this._applyMemo(this.r18) case var _0?) {
      if ([_0] case (var $ && var _l1)) {
        for (;;) {
          var _mark = this._mark();
          if (this._applyMemo(this.r29) case _?) {
            if (this._applyMemo(this.r18) case var _0?) {
              _l1.add(_0);
              continue;
            }
          }
          this._recover(_mark);
          break;
        }
        return $.join(".") ;
      }
    }
  }

  /// `global::dart::type::fnParameters`
  String? rw() {
    var _mark = this._mark();
    if (this._applyMemo(this.r1w) case _?) {
      if (this._applyLr(this.rz) case var positional?) {
        if (this._applyMemo(this.r27) case _?) {
          if (this._applyMemo(this.ry) case var named?) {
            if (this._applyMemo(this.r1x) case _?) {
              return "($positional, $named)" ;
            }
          }
        }
      }
    }
    this._recover(_mark);
    if (this._applyMemo(this.r1w) case _?) {
      if (this._applyLr(this.rz) case var positional?) {
        if (this._applyMemo(this.r27) case _?) {
          if (this._applyMemo(this.rx) case var optional?) {
            if (this._applyMemo(this.r1x) case _?) {
              return "($positional, $optional)" ;
            }
          }
        }
      }
    }
    this._recover(_mark);
    if (this._applyMemo(this.r1w) case _?) {
      if (this._applyLr(this.rz) case (var $1 && var positional)?) {
        if (this.f1p() case _) {
          if (this._applyMemo(this.r1x) case _?) {
            return "($positional)" ;
          }
        }
      }
    }
    this._recover(_mark);
    if (this._applyMemo(this.r1w) case _?) {
      if (this._applyMemo(this.ry) case (var $1 && var named)?) {
        if (this._applyMemo(this.r1x) case _?) {
          return "($named)" ;
        }
      }
    }
    this._recover(_mark);
    if (this._applyMemo(this.r1w) case _?) {
      if (this._applyMemo(this.rx) case (var $1 && var optional)?) {
        if (this._applyMemo(this.r1x) case _?) {
          return "($optional)" ;
        }
      }
    }
    this._recover(_mark);
    if (this._applyMemo(this.r1w) case _?) {
      if (this._applyMemo(this.r1x) case _?) {
        return "()" ;
      }
    }
  }

  /// `global::dart::type::parameters::optional`
  String? rx() {
    if (this.r1t() case _?) {
      if (this._applyLr(this.rz) case (var $1 && var $)?) {
        if (this.f1q() case _) {
          if (this.r1u() case _?) {
            if ($1 case var $) {
              return "[" + $ + "]" ;
            }
          }
        }
      }
    }
  }

  /// `global::dart::type::parameters::named`
  String? ry() {
    if (this._applyMemo(this.r1v) case _?) {
      if (this._applyLr(this.r10) case (var $1 && var $)?) {
        if (this.f1r() case _) {
          if (this._applyMemo(this.r1y) case _?) {
            if ($1 case var $) {
              return "{" + $ + "}" ;
            }
          }
        }
      }
    }
  }

  /// `global::dart::type::fields::positional`
  String? rz() {
    if (this._applyLr(this.r11) case var car?) {
      if (this._applyMemo(this.r27) case _?) {
        var _mark = this._mark();
        if (this._applyLr(this.r11) case var _0) {
          if ([if (_0 case var _0?) _0] case (var cdr && var _l1)) {
            if (cdr.isNotEmpty) {
              for (;;) {
                var _mark = this._mark();
                if (this._applyMemo(this.r27) case _?) {
                  if (this._applyLr(this.r11) case var _0?) {
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
            return [car, ...cdr].join(", ") ;
          }
        }
      }
    }
  }

  /// `global::dart::type::fields::named`
  String? r10() {
    if (this._applyLr(this.r12) case var _0?) {
      if ([_0] case (var $ && var _l1)) {
        for (;;) {
          var _mark = this._mark();
          if (this._applyMemo(this.r27) case _?) {
            if (this._applyLr(this.r12) case var _0?) {
              _l1.add(_0);
              continue;
            }
          }
          this._recover(_mark);
          break;
        }
        return $.join(", ") ;
      }
    }
  }

  /// `global::dart::type::field::positional`
  String? r11() {
    if (this._applyLr(this.rk) case var $0?) {
      if (this._applyMemo(this.r2d)! case _) {
        if (this.f1s() case var $2) {
          return "${$0} ${$2 ?? ""}".trimRight() ;
        }
      }
    }
  }

  /// `global::dart::type::field::named`
  String? r12() {
    if (this._applyLr(this.rk) case var $0?) {
      if (this._applyMemo(this.r2d)! case _) {
        if (this._applyMemo(this.r18) case var $2?) {
          return "${$0} ${$2}" ;
        }
      }
    }
  }

  /// `global::type`
  String? r13() {
    var _mark = this._mark();
    if (this._applyMemo(this.r2d)! case _) {
      if (this.r19() case var $1?) {
        if (this._applyMemo(this.r2d)! case _) {
          return $1;
        }
      }
    }
    this._recover(_mark);
    if (this._applyMemo(this.r2d)! case _) {
      if (this.f1t() case var $1?) {
        return $1;
      }
    }
  }

  /// `global::namespaceReference`
  String r14() {
    var _mark = this._mark();
    if (this.f1v() case var _0?) {
      if ([_0].nullable() case var _l1) {
        if (_l1 != null) {
          for (;;) {
            var _mark = this._mark();
            if (this.f1v() case var _0?) {
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
    if (this.r16() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this._applyMemo(this.r17) case var $?) {
      return $;
    }
  }

  /// `global::namespacedRaw`
  String? r16() {
    if (this._applyMemo(this.r14)! case var $0) {
      if (this.f1x() case var $1?) {
        return $0.isEmpty ? $1 : "${$0}${ParserGenerator.separator}${$1}";
      }
    }
  }

  /// `global::namespacedIdentifier`
  String? r17() {
    if (this._applyMemo(this.r14)! case var $0) {
      if (this._applyMemo(this.r18) case var $1?) {
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
      if (this.f1z() case var $1) {
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
        return int.parse($.join()) ;
      }
    }
  }

  /// `global::kw::decorator`
  Tag? r1b() {
    if (this._applyMemo(this.r2d)! case _) {
      if (this.matchPattern(_string.$43) case _?) {
        if (this.f20() case (var $2 && var _decorator)?) {
          if (this._applyMemo(this.r2d)! case _) {
            return $2;
          }
        }
      }
    }
  }

  /// `global::kw::start`
  String? r1c() {
    if (this._applyMemo(this.r2d)! case _) {
      if (this.matchPattern(_string.$44) case (var $1 && var $)?) {
        if (this._applyMemo(this.r2d)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::kw::end`
  String? r1d() {
    if (this._applyMemo(this.r2d)! case _) {
      if (this.matchPattern(_string.$45) case (var $1 && var $)?) {
        if (this._applyMemo(this.r2d)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::kw::epsilon`
  String? r1e() {
    if (this._applyMemo(this.r2d)! case _) {
      if (this.matchPattern(_string.$46) case (var $1 && var $)?) {
        if (this._applyMemo(this.r2d)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::kw::any`
  String? r1f() {
    if (this._applyMemo(this.r2d)! case _) {
      if (this.matchPattern(_string.$47) case (var $1 && var $)?) {
        if (this._applyMemo(this.r2d)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::mac`
  String? r1g() {
    var _mark = this._mark();
    if (this._applyMemo(this.r1h) case var $?) {
      return $;
    }
  }

  /// `global::mac::choice`
  String? r1h() {
    if (this._applyMemo(this.r2d)! case _) {
      if (this.matchPattern(_string.$48) case var $1?) {
        if (this._applyMemo(this.r2d)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::CHOICE_OP`
  String? r1i() {
    if (this.pos case var from) {
      if (this._applyMemo(this.r28) case _?) {
        if (this.f21() case _) {
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
  String? r1j() {
    if (this._applyMemo(this.r2d)! case _) {
      if (this.matchPattern(_string.$49) case var $1?) {
        if (this._applyMemo(this.r2d)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::..`
  String? r1k() {
    if (this._applyMemo(this.r2d)! case _) {
      if (this.matchPattern(_string.$30) case var $1?) {
        if (this._applyMemo(this.r2d)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::=>`
  String? r1l() {
    if (this._applyMemo(this.r2d)! case _) {
      if (this.matchPattern(_string.$50) case var $1?) {
        if (this._applyMemo(this.r2d)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::~>`
  String? r1m() {
    if (this._applyMemo(this.r2d)! case _) {
      if (this.matchPattern(_string.$51) case var $1?) {
        if (this._applyMemo(this.r2d)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::<~`
  String? r1n() {
    if (this._applyMemo(this.r2d)! case _) {
      if (this.matchPattern(_string.$52) case var $1?) {
        if (this._applyMemo(this.r2d)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::|>`
  String? r1o() {
    if (this._applyMemo(this.r2d)! case _) {
      if (this.matchPattern(_string.$53) case var $1?) {
        if (this._applyMemo(this.r2d)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::%`
  String? r1p() {
    if (this._applyMemo(this.r2d)! case _) {
      if (this.matchPattern(_string.$54) case var $1?) {
        if (this._applyMemo(this.r2d)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::@`
  String? r1q() {
    if (this._applyMemo(this.r2d)! case _) {
      if (this.matchPattern(_string.$43) case var $1?) {
        if (this._applyMemo(this.r2d)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::<`
  String? r1r() {
    if (this._applyMemo(this.r2d)! case _) {
      if (this.matchPattern(_string.$55) case var $1?) {
        if (this._applyMemo(this.r2d)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::>`
  String? r1s() {
    if (this._applyMemo(this.r2d)! case _) {
      if (this.matchPattern(_string.$56) case var $1?) {
        if (this._applyMemo(this.r2d)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::[`
  String? r1t() {
    if (this._applyMemo(this.r2d)! case _) {
      if (this.matchPattern(_string.$18) case var $1?) {
        if (this._applyMemo(this.r2d)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::]`
  String? r1u() {
    if (this._applyMemo(this.r2d)! case _) {
      if (this.matchPattern(_string.$5) case var $1?) {
        if (this._applyMemo(this.r2d)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::{`
  String? r1v() {
    if (this._applyMemo(this.r2d)! case _) {
      if (this.matchPattern(_string.$26) case var $1?) {
        if (this._applyMemo(this.r2d)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::(`
  String? r1w() {
    if (this._applyMemo(this.r2d)! case _) {
      if (this.matchPattern(_string.$27) case var $1?) {
        if (this._applyMemo(this.r2d)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::)`
  String? r1x() {
    if (this._applyMemo(this.r2d)! case _) {
      if (this.matchPattern(_string.$24) case var $1?) {
        if (this._applyMemo(this.r2d)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::}`
  String? r1y() {
    if (this._applyMemo(this.r2d)! case _) {
      if (this.matchPattern(_string.$25) case var $1?) {
        if (this._applyMemo(this.r2d)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::;`
  String? r1z() {
    if (this._applyMemo(this.r2d)! case _) {
      if (this.matchPattern(_string.$23) case var $1?) {
        if (this._applyMemo(this.r2d)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::=`
  String? r20() {
    if (this._applyMemo(this.r2d)! case _) {
      if (this.matchPattern(_string.$57) case var $1?) {
        if (this._applyMemo(this.r2d)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::?`
  String? r21() {
    if (this._applyMemo(this.r2d)! case _) {
      if (this.matchPattern(_string.$58) case var $1?) {
        if (this._applyMemo(this.r2d)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::!`
  String? r22() {
    if (this._applyMemo(this.r2d)! case _) {
      if (this.matchPattern(_string.$59) case var $1?) {
        if (this._applyMemo(this.r2d)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::~`
  String? r23() {
    if (this._applyMemo(this.r2d)! case _) {
      if (this.matchPattern(_string.$60) case var $1?) {
        if (this._applyMemo(this.r2d)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::&`
  String? r24() {
    if (this._applyMemo(this.r2d)! case _) {
      if (this.matchPattern(_string.$61) case var $1?) {
        if (this._applyMemo(this.r2d)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::*`
  String? r25() {
    if (this._applyMemo(this.r2d)! case _) {
      if (this.matchPattern(_string.$62) case var $1?) {
        if (this._applyMemo(this.r2d)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::+`
  String? r26() {
    if (this._applyMemo(this.r2d)! case _) {
      if (this.matchPattern(_string.$63) case var $1?) {
        if (this._applyMemo(this.r2d)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::,`
  String? r27() {
    if (this._applyMemo(this.r2d)! case _) {
      if (this.matchPattern(_string.$64) case var $1?) {
        if (this._applyMemo(this.r2d)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::|`
  String? r28() {
    if (this._applyMemo(this.r2d)! case _) {
      if (this.matchPattern(_string.$65) case var $1?) {
        if (this._applyMemo(this.r2d)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::.`
  String? r29() {
    if (this._applyMemo(this.r2d)! case _) {
      if (this.matchPattern(_string.$29) case var $1?) {
        if (this._applyMemo(this.r2d)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::ε`
  String? r2a() {
    if (this._applyMemo(this.r2d)! case _) {
      if (this.matchPattern(_string.$66) case var $1?) {
        if (this._applyMemo(this.r2d)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::^`
  String? r2b() {
    if (this._applyMemo(this.r2d)! case _) {
      if (this.matchPattern(_string.$67) case var $1?) {
        if (this._applyMemo(this.r2d)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::$`
  String? r2c() {
    if (this._applyMemo(this.r2d)! case _) {
      if (this.matchPattern(_string.$40) case var $1?) {
        if (this._applyMemo(this.r2d)! case _) {
          return $1;
        }
      }
    }
  }

  /// `global::_`
  String r2d() {
    var _mark = this._mark();
      if (this.f22() case var _0) {
        if ([if (_0 case var _0?) _0] case var _l1) {
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
          return "";
        }
      }
  }

  /// `global::whitespace`
  String? r2e() {
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
  }

  /// `global::comment`
  String? r2f() {
    var _mark = this._mark();
    if (this.r2g() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.r2h() case var $?) {
      return $;
    }
  }

  /// `global::comment::single`
  String? r2g() {
    if (this.matchPattern(_string.$68) case _?) {
      var _mark = this._mark();
        if (this.f26() case var _0) {
          if ([if (_0 case var _0?) _0] case var _l1) {
            if (_l1.isNotEmpty) {
              for (;;) {
                var _mark = this._mark();
                if (this.f26() case var _0?) {
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
  String? r2h() {
    if (this.matchPattern(_string.$69) case _?) {
      var _mark = this._mark();
        if (this.f27() case var _0) {
          if ([if (_0 case var _0?) _0] case var _l1) {
            if (_l1.isNotEmpty) {
              for (;;) {
                var _mark = this._mark();
                if (this.f27() case var _0?) {
                  _l1.add(_0);
                  continue;
                }
                this._recover(_mark);
                break;
              }
            } else {
              this._recover(_mark);
            }
            if (this.matchPattern(_string.$34) case _?) {
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
  /// `"\"\"\""`
  static const $7 = "\"\"\"";
  /// `"r"`
  static const $8 = "r";
  /// `"'''"`
  static const $9 = "'''";
  /// `"\""`
  static const $10 = "\"";
  /// `"'"`
  static const $11 = "'";
  /// `"D"`
  static const $12 = "D";
  /// `"W"`
  static const $13 = "W";
  /// `"S"`
  static const $14 = "S";
  /// `"f"`
  static const $15 = "f";
  /// `"v"`
  static const $16 = "v";
  /// `"b"`
  static const $17 = "b";
  /// `"["`
  static const $18 = "[";
  /// `"r\"\"\""`
  static const $19 = "r\"\"\"";
  /// `"r'''"`
  static const $20 = "r'''";
  /// `"r\""`
  static const $21 = "r\"";
  /// `"r'"`
  static const $22 = "r'";
  /// `";"`
  static const $23 = ";";
  /// `")"`
  static const $24 = ")";
  /// `"}"`
  static const $25 = "}";
  /// `"{"`
  static const $26 = "{";
  /// `"("`
  static const $27 = "(";
  /// `"::"`
  static const $28 = "::";
  /// `"."`
  static const $29 = ".";
  /// `".."`
  static const $30 = "..";
  /// `"rule"`
  static const $31 = "rule";
  /// `"fragment"`
  static const $32 = "fragment";
  /// `"inline"`
  static const $33 = "inline";
  /// `"*/"`
  static const $34 = "*/";
  /// `"d"`
  static const $35 = "d";
  /// `"w"`
  static const $36 = "w";
  /// `"s"`
  static const $37 = "s";
  /// `"n"`
  static const $38 = "n";
  /// `"t"`
  static const $39 = "t";
  /// `"\$"`
  static const $40 = "\$";
  /// `":"`
  static const $41 = ":";
  /// `"Function"`
  static const $42 = "Function";
  /// `"@"`
  static const $43 = "@";
  /// `"START"`
  static const $44 = "START";
  /// `"END"`
  static const $45 = "END";
  /// `"EPSILON"`
  static const $46 = "EPSILON";
  /// `"ANY"`
  static const $47 = "ANY";
  /// `"choice!"`
  static const $48 = "choice!";
  /// `"#"`
  static const $49 = "#";
  /// `"=>"`
  static const $50 = "=>";
  /// `"~>"`
  static const $51 = "~>";
  /// `"<~"`
  static const $52 = "<~";
  /// `"|>"`
  static const $53 = "|>";
  /// `"%"`
  static const $54 = "%";
  /// `"<"`
  static const $55 = "<";
  /// `">"`
  static const $56 = ">";
  /// `"="`
  static const $57 = "=";
  /// `"?"`
  static const $58 = "?";
  /// `"!"`
  static const $59 = "!";
  /// `"~"`
  static const $60 = "~";
  /// `"&"`
  static const $61 = "&";
  /// `"*"`
  static const $62 = "*";
  /// `"+"`
  static const $63 = "+";
  /// `","`
  static const $64 = ",";
  /// `"|"`
  static const $65 = "|";
  /// `"ε"`
  static const $66 = "ε";
  /// `"^"`
  static const $67 = "^";
  /// `"//"`
  static const $68 = "//";
  /// `"/*"`
  static const $69 = "/*";
}
class _range {
  /// `[a-zA-Z0-9_$]`
  static const $1 = { (97, 122), (65, 90), (48, 57), (95, 95), (36, 36) };
  /// `[a-zA-Z_$]`
  static const $2 = { (97, 122), (65, 90), (95, 95), (36, 36) };
}
