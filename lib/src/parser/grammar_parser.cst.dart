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
final class CstGrammarParser extends _PegParser<Object> {
  CstGrammarParser();

  @override
  get start => r0;


  /// `global::json::atom::number::digits`
  Object? f0() {
    if (this._mark() case var _mark) {
      if (this.f0() case var $0?) {
        if (this.f1() case var $1?) {
          if ([$0, $1] case var $) {
            return ("<json::atom::number::digits>", $);
          }
        }
      }
      this._recover(_mark);
      if (this.f1() case var $?) {
        return ("<json::atom::number::digits>", $);
      }
    }
  }

  /// `global::json::atom::number::digit`
  Object? f1() {
    if (this._mark() case var _mark) {
      if (this.matchPattern(_string.$1) case var $?) {
        return ("<json::atom::number::digit>", $);
      }

      this._recover(_mark);
      if (this.f2() case var $?) {
        return ("<json::atom::number::digit>", $);
      }
    }
  }

  /// `global::json::atom::number::onenine`
  Object? f2() {
    if (this._mark() case var _mark) {
      if (this.matchPattern(_string.$2) case var $?) {
        return ("<json::atom::number::onenine>", $);
      }

      this._recover(_mark);
      if (this.matchPattern(_string.$3) case var $?) {
        return ("<json::atom::number::onenine>", $);
      }

      this._recover(_mark);
      if (this.matchPattern(_string.$4) case var $?) {
        return ("<json::atom::number::onenine>", $);
      }

      this._recover(_mark);
      if (this.matchPattern(_string.$5) case var $?) {
        return ("<json::atom::number::onenine>", $);
      }

      this._recover(_mark);
      if (this.matchPattern(_string.$6) case var $?) {
        return ("<json::atom::number::onenine>", $);
      }

      this._recover(_mark);
      if (this.matchPattern(_string.$7) case var $?) {
        return ("<json::atom::number::onenine>", $);
      }

      this._recover(_mark);
      if (this.matchPattern(_string.$8) case var $?) {
        return ("<json::atom::number::onenine>", $);
      }

      this._recover(_mark);
      if (this.matchPattern(_string.$9) case var $?) {
        return ("<json::atom::number::onenine>", $);
      }

      this._recover(_mark);
      if (this.matchPattern(_string.$10) case var $?) {
        return ("<json::atom::number::onenine>", $);
      }
    }
  }

  /// `global::literal::range::atom`
  Object? f3() {
    if (this._mark() case var _mark) {
      if (this.matchPattern(_string.$11) case var $0?) {
        if (this.pos < this.buffer.length) {
          if (this.buffer[this.pos++] case var $1) {
            if ([$0, $1] case var $) {
              return ("<literal::range::atom>", $);
            }
          }
        }
      }

      this._recover(_mark);
      if (this.matchPattern(_string.$12) case null) {
        this._recover(_mark);
        if (this.pos < this.buffer.length) {
          if (this.buffer[this.pos++] case var $) {
            return ("<literal::range::atom>", $);
          }
        }
      }
    }
  }

  /// `global::type`
  Object? f4() {
    if (this._mark() case var _mark) {
      if (this.apply(this.ry) case var $0?) {
        if (this.f2g() case var $1?) {
          if (this.apply(this.ry) case var $2?) {
            if ([$0, $1, $2] case var $) {
              return ("<type>", $);
            }
          }
        }
      }
      this._recover(_mark);
      if (this.apply(this.rj) case var $?) {
        return ("<type>", $);
      }
    }
  }

  /// `global::namespaceReference`
  Object f5() {
    if (this._mark() case var _mark) {
      if (this.f2j() case var _0) {
        if ([if (_0 case var _0?) _0] case (var $ && var _l1)) {
          if (_l1.isNotEmpty) {
            for (;;) {
              if (this._mark() case var _mark) {
                if (this.f2j() case var _0?) {
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
          return ("<namespaceReference>", $);
        }
      }
    }
  }

  /// `global::name`
  Object? f6() {
    if (this._mark() case var _mark) {
      if (this.f5() case var $0) {
        if (this.f2l() case var $1?) {
          if ([$0, $1] case var $) {
            return ("<name>", $);
          }
        }
      }
      this._recover(_mark);
      if (this.f7() case var $?) {
        return ("<name>", $);
      }
    }
  }

  /// `global::namespacedIdentifier`
  Object? f7() {
    if (this.f5() case var $0) {
      if (this.f9() case var $1?) {
        if ([$0, $1] case var $) {
          return ("<namespacedIdentifier>", $);
        }
      }
    }
  }

  /// `global::body`
  Object? f8() {
    if (this.f2m() case var $0?) {
      if (this.apply(this.r3) case var choice?) {
        if (this.fy() case var $2?) {
          if ([$0, choice, $2] case var $) {
            return ("<body>", $);
          }
        }
      }
    }
  }

  /// `global::identifier`
  Object? f9() {
    if (this.matchPattern(_regexp.$1) case var $?) {
      return ("<identifier>", $);
    }
  }

  /// `global::number`
  Object? fa() {
    if (this.matchPattern(_regexp.$2) case var _0?) {
      if ([_0] case (var $ && var _l1)) {
        for (;;) {
          if (this._mark() case var _mark) {
            if (this.matchPattern(_regexp.$2) case var _0?) {
              _l1.add(_0);
              continue;
            }
            this._recover(_mark);
            break;
          }
        }
        return ("<number>", $);
      }
    }
  }

  /// `global::kw::decorator`
  Object? fb() {
    if (this._mark() case var _mark) {
      if (this.apply(this.ry) case var $0?) {
        if (this.matchPattern(_string.$13) case var $1?) {
          if (this.apply(this.ry) case var $2?) {
            if ([$0, $1, $2] case var $) {
              return ("<kw::decorator>", $);
            }
          }
        }
      }
      this._recover(_mark);
      if (this.apply(this.ry) case var $0?) {
        if (this.matchPattern(_string.$14) case var $1?) {
          if (this.apply(this.ry) case var $2?) {
            if ([$0, $1, $2] case var $) {
              return ("<kw::decorator>", $);
            }
          }
        }
      }
      this._recover(_mark);
      if (this.apply(this.ry) case var $0?) {
        if (this.matchPattern(_string.$15) case var $1?) {
          if (this.apply(this.ry) case var $2?) {
            if ([$0, $1, $2] case var $) {
              return ("<kw::decorator>", $);
            }
          }
        }
      }
    }
  }

  /// `global::kw::var`
  Object? fc() {
    if (this.apply(this.ry) case var $0?) {
      if (this.matchPattern(_string.$16) case var $1?) {
        if (this.apply(this.ry) case var $2?) {
          if ([$0, $1, $2] case var $) {
            return ("<kw::var>", $);
          }
        }
      }
    }
  }

  /// `global::mac::range`
  Object? fd() {
    if (this.apply(this.ry) case var $0?) {
      if (this.matchPattern(_string.$17) case var $1?) {
        if (this.apply(this.ry) case var $2?) {
          if ([$0, $1, $2] case var $) {
            return ("<mac::range>", $);
          }
        }
      }
    }
  }

  /// `global::mac::flat`
  Object? fe() {
    if (this.apply(this.ry) case var $0?) {
      if (this.matchPattern(_string.$18) case var $1?) {
        if (this.apply(this.ry) case var $2?) {
          if ([$0, $1, $2] case var $) {
            return ("<mac::flat>", $);
          }
        }
      }
    }
  }

  /// `global::mac::sep`
  Object? ff() {
    if (this.apply(this.ry) case var $0?) {
      if (this.matchPattern(_string.$19) case var $1?) {
        if (this.apply(this.ry) case var $2?) {
          if ([$0, $1, $2] case var $) {
            return ("<mac::sep>", $);
          }
        }
      }
    }
  }

  /// `global::mac::choice`
  Object? fg() {
    if (this.apply(this.ry) case var $0?) {
      if (this.matchPattern(_string.$20) case var $1?) {
        if (this.apply(this.ry) case var $2?) {
          if ([$0, $1, $2] case var $) {
            return ("<mac::choice>", $);
          }
        }
      }
    }
  }

  /// `global::regexEscape::backslash`
  Object? fh() {
    if (this.apply(this.ry) case var $0?) {
      if (this.f2n() case var $1?) {
        if (this.apply(this.ry) case var $2?) {
          if ([$0, $1, $2] case var $) {
            return ("<regexEscape::backslash>", $);
          }
        }
      }
    }
  }

  /// `global::regexEscape::digit`
  Object? fi() {
    if (this.apply(this.ry) case var $0?) {
      if (this.f2o() case var $1?) {
        if (this.apply(this.ry) case var $2?) {
          if ([$0, $1, $2] case var $) {
            return ("<regexEscape::digit>", $);
          }
        }
      }
    }
  }

  /// `global::regexEscape::word`
  Object? fj() {
    if (this.apply(this.ry) case var $0?) {
      if (this.f2p() case var $1?) {
        if (this.apply(this.ry) case var $2?) {
          if ([$0, $1, $2] case var $) {
            return ("<regexEscape::word>", $);
          }
        }
      }
    }
  }

  /// `global::regexEscape::whitespace`
  Object? fk() {
    if (this.apply(this.ry) case var $0?) {
      if (this.f2q() case var $1?) {
        if (this.apply(this.ry) case var $2?) {
          if ([$0, $1, $2] case var $) {
            return ("<regexEscape::whitespace>", $);
          }
        }
      }
    }
  }

  /// `global::regexEscape::notDigit`
  Object? fl() {
    if (this.apply(this.ry) case var $0?) {
      if (this.f2r() case var $1?) {
        if (this.apply(this.ry) case var $2?) {
          if ([$0, $1, $2] case var $) {
            return ("<regexEscape::notDigit>", $);
          }
        }
      }
    }
  }

  /// `global::regexEscape::notWord`
  Object? fm() {
    if (this.apply(this.ry) case var $0?) {
      if (this.f2s() case var $1?) {
        if (this.apply(this.ry) case var $2?) {
          if ([$0, $1, $2] case var $) {
            return ("<regexEscape::notWord>", $);
          }
        }
      }
    }
  }

  /// `global::regexEscape::notWhitespace`
  Object? fn() {
    if (this.apply(this.ry) case var $0?) {
      if (this.f2t() case var $1?) {
        if (this.apply(this.ry) case var $2?) {
          if ([$0, $1, $2] case var $) {
            return ("<regexEscape::notWhitespace>", $);
          }
        }
      }
    }
  }

  /// `global::regexEscape::newline`
  Object? fo() {
    if (this.apply(this.ry) case var $0?) {
      if (this.f2u() case var $1?) {
        if (this.apply(this.ry) case var $2?) {
          if ([$0, $1, $2] case var $) {
            return ("<regexEscape::newline>", $);
          }
        }
      }
    }
  }

  /// `global::regexEscape::carriageReturn`
  Object? fp() {
    if (this.apply(this.ry) case var $0?) {
      if (this.f2v() case var $1?) {
        if (this.apply(this.ry) case var $2?) {
          if ([$0, $1, $2] case var $) {
            return ("<regexEscape::carriageReturn>", $);
          }
        }
      }
    }
  }

  /// `global::regexEscape::tab`
  Object? fq() {
    if (this.apply(this.ry) case var $0?) {
      if (this.f2w() case var $1?) {
        if (this.apply(this.ry) case var $2?) {
          if ([$0, $1, $2] case var $) {
            return ("<regexEscape::tab>", $);
          }
        }
      }
    }
  }

  /// `global::regexEscape::formFeed`
  Object? fr() {
    if (this.apply(this.ry) case var $0?) {
      if (this.f2x() case var $1?) {
        if (this.apply(this.ry) case var $2?) {
          if ([$0, $1, $2] case var $) {
            return ("<regexEscape::formFeed>", $);
          }
        }
      }
    }
  }

  /// `global::regexEscape::verticalTab`
  Object? fs() {
    if (this.apply(this.ry) case var $0?) {
      if (this.f2y() case var $1?) {
        if (this.apply(this.ry) case var $2?) {
          if ([$0, $1, $2] case var $) {
            return ("<regexEscape::verticalTab>", $);
          }
        }
      }
    }
  }

  /// `global::..`
  Object? ft() {
    if (this.apply(this.ry) case var $0?) {
      if (this.matchPattern(_string.$21) case var $1?) {
        if (this.apply(this.ry) case var $2?) {
          if ([$0, $1, $2] case var $) {
            return ("<..>", $);
          }
        }
      }
    }
  }

  /// `global::}`
  Object? fu() {
    if (this.apply(this.ry) case var $0?) {
      if (this.matchPattern(_string.$22) case var $1?) {
        if (this.apply(this.ry) case var $2?) {
          if ([$0, $1, $2] case var $) {
            return ("<}>", $);
          }
        }
      }
    }
  }

  /// `global::{`
  Object? fv() {
    if (this.apply(this.ry) case var $0?) {
      if (this.matchPattern(_string.$23) case var $1?) {
        if (this.apply(this.ry) case var $2?) {
          if ([$0, $1, $2] case var $) {
            return ("<{>", $);
          }
        }
      }
    }
  }

  /// `global::)`
  Object? fw() {
    if (this.apply(this.ry) case var $0?) {
      if (this.matchPattern(_string.$24) case var $1?) {
        if (this.apply(this.ry) case var $2?) {
          if ([$0, $1, $2] case var $) {
            return ("<)>", $);
          }
        }
      }
    }
  }

  /// `global::(`
  Object? fx() {
    if (this.apply(this.ry) case var $0?) {
      if (this.matchPattern(_string.$25) case var $1?) {
        if (this.apply(this.ry) case var $2?) {
          if ([$0, $1, $2] case var $) {
            return ("<(>", $);
          }
        }
      }
    }
  }

  /// `global::;`
  Object? fy() {
    if (this.apply(this.ry) case var $0?) {
      if (this.matchPattern(_string.$26) case var $1?) {
        if (this.apply(this.ry) case var $2?) {
          if ([$0, $1, $2] case var $) {
            return ("<;>", $);
          }
        }
      }
    }
  }

  /// `global::=`
  Object? fz() {
    if (this.apply(this.ry) case var $0?) {
      if (this.matchPattern(_string.$27) case var $1?) {
        if (this.apply(this.ry) case var $2?) {
          if ([$0, $1, $2] case var $) {
            return ("<=>", $);
          }
        }
      }
    }
  }

  /// `global::?`
  Object? f10() {
    if (this.apply(this.ry) case var $0?) {
      if (this.matchPattern(_string.$28) case var $1?) {
        if (this.apply(this.ry) case var $2?) {
          if ([$0, $1, $2] case var $) {
            return ("<?>", $);
          }
        }
      }
    }
  }

  /// `global::*`
  Object? f11() {
    if (this.apply(this.ry) case var $0?) {
      if (this.matchPattern(_string.$29) case var $1?) {
        if (this.apply(this.ry) case var $2?) {
          if ([$0, $1, $2] case var $) {
            return ("<*>", $);
          }
        }
      }
    }
  }

  /// `global::+`
  Object? f12() {
    if (this.apply(this.ry) case var $0?) {
      if (this.matchPattern(_string.$30) case var $1?) {
        if (this.apply(this.ry) case var $2?) {
          if ([$0, $1, $2] case var $) {
            return ("<+>", $);
          }
        }
      }
    }
  }

  /// `global::,`
  Object? f13() {
    if (this.apply(this.ry) case var $0?) {
      if (this.matchPattern(_string.$31) case var $1?) {
        if (this.apply(this.ry) case var $2?) {
          if ([$0, $1, $2] case var $) {
            return ("<,>", $);
          }
        }
      }
    }
  }

  /// `global:::`
  Object? f14() {
    if (this.apply(this.ry) case var $0?) {
      if (this.matchPattern(_string.$32) case var $1?) {
        if (this.apply(this.ry) case var $2?) {
          if ([$0, $1, $2] case var $) {
            return ("<:>", $);
          }
        }
      }
    }
  }

  /// `global::|`
  Object? f15() {
    if (this.apply(this.ry) case var $0?) {
      if (this.matchPattern(_string.$33) case var $1?) {
        if (this.apply(this.ry) case var $2?) {
          if ([$0, $1, $2] case var $) {
            return ("<|>", $);
          }
        }
      }
    }
  }

  /// `global::.`
  Object? f16() {
    if (this.apply(this.ry) case var $0?) {
      if (this.matchPattern(_string.$34) case var $1?) {
        if (this.apply(this.ry) case var $2?) {
          if ([$0, $1, $2] case var $) {
            return ("<.>", $);
          }
        }
      }
    }
  }

  /// `ROOT`
  Object? f17() {
    if (this.apply(this.r0) case var $?) {
      return ("<ROOT>", $);
    }
  }

  /// `global::dart::literal::string::body`
  Object? f18() {
    if (this._mark() case var _mark) {
      if (this.matchPattern(_string.$36) case var _2?) {
        if ([_2].nullable() case var _l3) {
          if (_l3 != null) {
            while (_l3.length < 1) {
              if (this._mark() case var _mark) {
                if (this.matchPattern(_string.$36) case var _2?) {
                  _l3.add(_2);
                  continue;
                }
                this._recover(_mark);
                break;
              }
            }
          }
          if (_l3 case var $0) {
            if (this.matchPattern(_string.$35) case var $1?) {
              if (this._mark() case var _mark) {
                if (this.f2z() case var _0) {
                  if ([if (_0 case var _0?) _0] case (var $2 && var _l1)) {
                    if (_l1.isNotEmpty) {
                      for (;;) {
                        if (this._mark() case var _mark) {
                          if (this.f2z() case var _0?) {
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
                    if (this.matchPattern(_string.$35) case var $3?) {
                      if ([$0, $1, $2, $3] case var $) {
                        return ("<dart::literal::string::body>", $);
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
      if (this.matchPattern(_string.$36) case var _6?) {
        if ([_6].nullable() case var _l7) {
          if (_l7 != null) {
            while (_l7.length < 1) {
              if (this._mark() case var _mark) {
                if (this.matchPattern(_string.$36) case var _6?) {
                  _l7.add(_6);
                  continue;
                }
                this._recover(_mark);
                break;
              }
            }
          }
          if (_l7 case var $0) {
            if (this.matchPattern(_string.$37) case var $1?) {
              if (this._mark() case var _mark) {
                if (this.f30() case var _4) {
                  if ([if (_4 case var _4?) _4] case (var $2 && var _l5)) {
                    if (_l5.isNotEmpty) {
                      for (;;) {
                        if (this._mark() case var _mark) {
                          if (this.f30() case var _4?) {
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
                    if (this.matchPattern(_string.$37) case var $3?) {
                      if ([$0, $1, $2, $3] case var $) {
                        return ("<dart::literal::string::body>", $);
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
      if (this.matchPattern(_string.$36) case var _10?) {
        if ([_10].nullable() case var _l11) {
          if (_l11 != null) {
            while (_l11.length < 1) {
              if (this._mark() case var _mark) {
                if (this.matchPattern(_string.$36) case var _10?) {
                  _l11.add(_10);
                  continue;
                }
                this._recover(_mark);
                break;
              }
            }
          }
          if (_l11 case var $0) {
            if (this.matchPattern(_string.$38) case var $1?) {
              if (this._mark() case var _mark) {
                if (this.f31() case var _8) {
                  if ([if (_8 case var _8?) _8] case (var $2 && var _l9)) {
                    if (_l9.isNotEmpty) {
                      for (;;) {
                        if (this._mark() case var _mark) {
                          if (this.f31() case var _8?) {
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
                    if (this.matchPattern(_string.$38) case var $3?) {
                      if ([$0, $1, $2, $3] case var $) {
                        return ("<dart::literal::string::body>", $);
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
      if (this.matchPattern(_string.$36) case var _14?) {
        if ([_14].nullable() case var _l15) {
          if (_l15 != null) {
            while (_l15.length < 1) {
              if (this._mark() case var _mark) {
                if (this.matchPattern(_string.$36) case var _14?) {
                  _l15.add(_14);
                  continue;
                }
                this._recover(_mark);
                break;
              }
            }
          }
          if (_l15 case var $0) {
            if (this.matchPattern(_string.$39) case var $1?) {
              if (this._mark() case var _mark) {
                if (this.f32() case var _12) {
                  if ([if (_12 case var _12?) _12] case (var $2 && var _l13)) {
                    if (_l13.isNotEmpty) {
                      for (;;) {
                        if (this._mark() case var _mark) {
                          if (this.f32() case var _12?) {
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
                    if (this.matchPattern(_string.$39) case var $3?) {
                      if ([$0, $1, $2, $3] case var $) {
                        return ("<dart::literal::string::body>", $);
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
      if (this.matchPattern(_string.$35) case var $0?) {
        if (this._mark() case var _mark) {
          if (this.f33() case var _16) {
            if ([if (_16 case var _16?) _16] case (var $1 && var _l17)) {
              if (_l17.isNotEmpty) {
                for (;;) {
                  if (this._mark() case var _mark) {
                    if (this.f33() case var _16?) {
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
              if (this.matchPattern(_string.$35) case var $2?) {
                if ([$0, $1, $2] case var $) {
                  return ("<dart::literal::string::body>", $);
                }
              }
            }
          }
        }
      }

      this._recover(_mark);
      if (this.matchPattern(_string.$37) case var $0?) {
        if (this._mark() case var _mark) {
          if (this.f34() case var _18) {
            if ([if (_18 case var _18?) _18] case (var $1 && var _l19)) {
              if (_l19.isNotEmpty) {
                for (;;) {
                  if (this._mark() case var _mark) {
                    if (this.f34() case var _18?) {
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
              if (this.matchPattern(_string.$37) case var $2?) {
                if ([$0, $1, $2] case var $) {
                  return ("<dart::literal::string::body>", $);
                }
              }
            }
          }
        }
      }

      this._recover(_mark);
      if (this.matchPattern(_string.$38) case var $0?) {
        if (this._mark() case var _mark) {
          if (this.f35() case var _20) {
            if ([if (_20 case var _20?) _20] case (var $1 && var _l21)) {
              if (_l21.isNotEmpty) {
                for (;;) {
                  if (this._mark() case var _mark) {
                    if (this.f35() case var _20?) {
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
              if (this.matchPattern(_string.$38) case var $2?) {
                if ([$0, $1, $2] case var $) {
                  return ("<dart::literal::string::body>", $);
                }
              }
            }
          }
        }
      }

      this._recover(_mark);
      if (this.matchPattern(_string.$39) case var $0?) {
        if (this._mark() case var _mark) {
          if (this.f36() case var _22) {
            if ([if (_22 case var _22?) _22] case (var $1 && var _l23)) {
              if (_l23.isNotEmpty) {
                for (;;) {
                  if (this._mark() case var _mark) {
                    if (this.f36() case var _22?) {
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
              if (this.matchPattern(_string.$39) case var $2?) {
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
  Object? f19() {
    if (this._mark() case var _mark) {
      if (this.matchPattern(_string.$40) case var $0?) {
        if (this.matchPattern(_string.$23) case var $1?) {
          if (this.apply(this.ri)! case var $2) {
            if (this.matchPattern(_string.$22) case var $3?) {
              if ([$0, $1, $2, $3] case var $) {
                return ("<dart::literal::string::interpolation>", $);
              }
            }
          }
        }
      }

      this._recover(_mark);
      if (this.matchPattern(_string.$40) case var $0?) {
        if (this.apply(this.rh) case var $1?) {
          if ([$0, $1] case var $) {
            return ("<dart::literal::string::interpolation>", $);
          }
        }
      }
    }
  }

  /// `global::json::atom::number::number`
  Object? f1a() {
    if (this.f1b() case var $0?) {
      if (this.f1c() case var $1) {
        if (this.f1d() case var $2) {
          if ([$0, $1, $2] case var $) {
            return ("<json::atom::number::number>", $);
          }
        }
      }
    }
  }

  /// `global::json::atom::number::integer`
  Object? f1b() {
    if (this._mark() case var _mark) {
      if (this.f1() case var $?) {
        return ("<json::atom::number::integer>", $);
      }
      this._recover(_mark);
      if (this.f2() case var $0?) {
        if (this.f0() case var $1?) {
          if ([$0, $1] case var $) {
            return ("<json::atom::number::integer>", $);
          }
        }
      }
      this._recover(_mark);
      if (this.matchPattern(_string.$41) case var $0?) {
        if (this.f1() case var $1?) {
          if ([$0, $1] case var $) {
            return ("<json::atom::number::integer>", $);
          }
        }
      }

      this._recover(_mark);
      if (this.matchPattern(_string.$41) case var $0?) {
        if (this.f2() case var $1?) {
          if (this.f0() case var $2?) {
            if ([$0, $1, $2] case var $) {
              return ("<json::atom::number::integer>", $);
            }
          }
        }
      }
    }
  }

  /// `global::json::atom::number::fraction`
  Object f1c() {
    if (this._mark() case var _mark) {
      if (this.matchPattern(_string.$34) case var $0?) {
        if (this.f0() case var $1?) {
          if ([$0, $1] case var $) {
            return ("<json::atom::number::fraction>", $);
          }
        }
      }

      this._recover(_mark);
      if ('' case var $) {
        return ("<json::atom::number::fraction>", $);
      }
    }
  }

  /// `global::json::atom::number::exponent`
  Object f1d() {
    if (this._mark() case var _mark) {
      if (this.f37() case var $0?) {
        if (this.f38() case var $1) {
          if (this.f0() case var $2?) {
            if ([$0, $1, $2] case var $) {
              return ("<json::atom::number::exponent>", $);
            }
          }
        }
      }
      this._recover(_mark);
      if ('' case var $) {
        return ("<json::atom::number::exponent>", $);
      }
    }
  }

  /// `fragment0`
  Object? f1e() {
    if (this.f15() case var $0?) {
      if (this.f15() case var $1) {
        if ([$0, $1] case var $) {
          return $;
        }
      }
    }
  }

  /// `fragment1`
  Object? f1f() {
    if (this.f15() case var $0?) {
      if (this.f15() case var $1) {
        if ([$0, $1] case var $) {
          return $;
        }
      }
    }
  }

  /// `fragment2`
  Object? f1g() {
    if (this.apply(this.ry) case var $0?) {
      if (this.matchPattern(_string.$42) case var $1?) {
        if (this.apply(this.ry) case var $2?) {
          if ([$0, $1, $2] case var $) {
            return $;
          }
        }
      }
    }
  }

  /// `fragment3`
  Object? f1h() {
    if (this.apply(this.ry) case var $0?) {
      if (this.matchPattern(_string.$43) case var $1?) {
        if (this.apply(this.ry) case var $2?) {
          if ([$0, $1, $2] case var $) {
            return $;
          }
        }
      }
    }
  }

  /// `fragment4`
  Object? f1i() {
    if (this.f1h() case var $0?) {
      if (this.fa() case var $1?) {
        if ([$0, $1] case var $) {
          return $;
        }
      }
    }
  }

  /// `fragment5`
  Object? f1j() {
    if (this.apply(this.ry) case var $0?) {
      if (this.matchPattern(_string.$44) case var $1?) {
        if (this.apply(this.ry) case var $2?) {
          if ([$0, $1, $2] case var $) {
            return $;
          }
        }
      }
    }
  }

  /// `fragment6`
  Object? f1k() {
    if (this.apply(this.ry) case var $0?) {
      if (this.matchPattern(_string.$45) case var $1?) {
        if (this.apply(this.ry) case var $2?) {
          if ([$0, $1, $2] case var $) {
            return $;
          }
        }
      }
    }
  }

  /// `fragment7`
  Object? f1l() {
    if (this.apply(this.ry) case var $0?) {
      if (this.matchPattern(_string.$46) case var $1?) {
        if (this.apply(this.ry) case var $2?) {
          if ([$0, $1, $2] case var $) {
            return $;
          }
        }
      }
    }
  }

  /// `fragment8`
  Object? f1m() {
    if (this.apply(this.ry) case var $0?) {
      if (this.matchPattern(_string.$47) case var $1?) {
        if (this.apply(this.ry) case var $2?) {
          if ([$0, $1, $2] case var $) {
            return $;
          }
        }
      }
    }
  }

  /// `fragment9`
  Object? f1n() {
    if (this.apply(this.ry) case var $0?) {
      if (this.matchPattern(_string.$48) case var $1?) {
        if (this.apply(this.ry) case var $2?) {
          if ([$0, $1, $2] case var $) {
            return $;
          }
        }
      }
    }
  }

  /// `fragment10`
  Object? f1o() {
    if (this.apply(this.r3) case var $0?) {
      if (this.fw() case var $1?) {
        if ([$0, $1] case var $) {
          return $;
        }
      }
    }
  }

  /// `fragment11`
  Object? f1p() {
    if (this._mark() case var _mark) {
      if (this.matchPattern(_string.$49) case var $?) {
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
      if (this.fk() case var $?) {
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
      this._recover(_mark);
      if (this.fh() case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.f3() case var l?) {
        if (this.matchPattern(_string.$41) case var $1?) {
          if (this.f3() case var r?) {
            if ([l, $1, r] case var $) {
              return $;
            }
          }
        }
      }
      this._recover(_mark);
      if (this.f3() case var $?) {
        return $;
      }
    }
  }

  /// `fragment12`
  Object? f1q() {
    if (this.apply(this.ry) case var $0?) {
      if (this.matchPattern(_string.$50) case var $1?) {
        if (this.f1p() case var _0?) {
          if ([_0] case (var elements && var _l1)) {
            for (;;) {
              if (this._mark() case var _mark) {
                if (this.apply(this.ry) case _?) {
                  if (this.f1p() case var _0?) {
                    _l1.add(_0);
                    continue;
                  }
                }
                this._recover(_mark);
                break;
              }
            }
            if (this.matchPattern(_string.$12) case var $3?) {
              if (this.apply(this.ry) case var $4?) {
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

  /// `fragment13`
  Object? f1r() {
    if (this._mark() case var _mark) {
      if (this.matchPattern(_string.$11) case var $0?) {
        if (this.pos < this.buffer.length) {
          if (this.buffer[this.pos++] case var $1) {
            if ([$0, $1] case var $) {
              return $;
            }
          }
        }
      }

      this._recover(_mark);
      if (this.matchPattern(_string.$51) case null) {
        this._recover(_mark);
        if (this.pos < this.buffer.length) {
          if (this.buffer[this.pos++] case var $) {
            return $;
          }
        }
      }
    }
  }

  /// `fragment14`
  Object? f1s() {
    if (this.f1r() case var _0?) {
      if ([_0] case (var $ && var _l1)) {
        for (;;) {
          if (this._mark() case var _mark) {
            if (this.f1r() case var _0?) {
              _l1.add(_0);
              continue;
            }
            this._recover(_mark);
            break;
          }
        }
        return $;
      }
    }
  }

  /// `fragment15`
  Object? f1t() {
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

  /// `fragment16`
  Object? f1u() {
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

  /// `fragment17`
  Object? f1v() {
    if (this._mark() case var _mark) {
      if (this.matchPattern(_string.$38) case null) {
        this._recover(_mark);
        if (this.pos < this.buffer.length) {
          if (this.buffer[this.pos++] case var $) {
            return $;
          }
        }
      }
    }
  }

  /// `fragment18`
  Object? f1w() {
    if (this._mark() case var _mark) {
      if (this.matchPattern(_string.$39) case null) {
        this._recover(_mark);
        if (this.pos < this.buffer.length) {
          if (this.buffer[this.pos++] case var $) {
            return $;
          }
        }
      }
    }
  }

  /// `fragment19`
  Object? f1x() {
    if (this._mark() case var _mark) {
      if (this.matchPattern(_string.$11) case var $0?) {
        if (this.pos < this.buffer.length) {
          if (this.buffer[this.pos++] case var $1) {
            if ([$0, $1] case var $) {
              return $;
            }
          }
        }
      }

      this._recover(_mark);
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

  /// `fragment20`
  Object? f1y() {
    if (this._mark() case var _mark) {
      if (this.matchPattern(_string.$11) case var $0?) {
        if (this.pos < this.buffer.length) {
          if (this.buffer[this.pos++] case var $1) {
            if ([$0, $1] case var $) {
              return $;
            }
          }
        }
      }

      this._recover(_mark);
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

  /// `fragment21`
  Object? f1z() {
    if (this._mark() case var _mark) {
      if (this.matchPattern(_string.$11) case var $0?) {
        if (this.pos < this.buffer.length) {
          if (this.buffer[this.pos++] case var $1) {
            if ([$0, $1] case var $) {
              return $;
            }
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
    }
  }

  /// `fragment22`
  Object? f20() {
    if (this._mark() case var _mark) {
      if (this.matchPattern(_string.$11) case var $0?) {
        if (this.pos < this.buffer.length) {
          if (this.buffer[this.pos++] case var $1) {
            if ([$0, $1] case var $) {
              return $;
            }
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
  }

  /// `fragment23`
  Object? f21() {
    if (this._mark() case var _mark) {
      if (this.matchPattern(_string.$52) case var $0?) {
        if (this._mark() case var _mark) {
          if (this.f1t() case var _0) {
            if ([if (_0 case var _0?) _0] case (var $1 && var _l1)) {
              if (_l1.isNotEmpty) {
                for (;;) {
                  if (this._mark() case var _mark) {
                    if (this.f1t() case var _0?) {
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
              if (this.matchPattern(_string.$35) case var $2?) {
                if ([$0, $1, $2] case var $) {
                  return $;
                }
              }
            }
          }
        }
      }

      this._recover(_mark);
      if (this.matchPattern(_string.$53) case var $0?) {
        if (this._mark() case var _mark) {
          if (this.f1u() case var _2) {
            if ([if (_2 case var _2?) _2] case (var $1 && var _l3)) {
              if (_l3.isNotEmpty) {
                for (;;) {
                  if (this._mark() case var _mark) {
                    if (this.f1u() case var _2?) {
                      _l3.add(_2);
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
                if ([$0, $1, $2] case var $) {
                  return $;
                }
              }
            }
          }
        }
      }

      this._recover(_mark);
      if (this.matchPattern(_string.$54) case var $0?) {
        if (this._mark() case var _mark) {
          if (this.f1v() case var _4) {
            if ([if (_4 case var _4?) _4] case (var $1 && var _l5)) {
              if (_l5.isNotEmpty) {
                for (;;) {
                  if (this._mark() case var _mark) {
                    if (this.f1v() case var _4?) {
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
              if (this.matchPattern(_string.$38) case var $2?) {
                if ([$0, $1, $2] case var $) {
                  return $;
                }
              }
            }
          }
        }
      }

      this._recover(_mark);
      if (this.matchPattern(_string.$55) case var $0?) {
        if (this._mark() case var _mark) {
          if (this.f1w() case var _6) {
            if ([if (_6 case var _6?) _6] case (var $1 && var _l7)) {
              if (_l7.isNotEmpty) {
                for (;;) {
                  if (this._mark() case var _mark) {
                    if (this.f1w() case var _6?) {
                      _l7.add(_6);
                      continue;
                    }
                    this._recover(_mark);
                    break;
                  }
                }
              } else {
                this._recover(_mark);
              }
              if (this.matchPattern(_string.$39) case var $2?) {
                if ([$0, $1, $2] case var $) {
                  return $;
                }
              }
            }
          }
        }
      }

      this._recover(_mark);
      if (this.matchPattern(_string.$35) case var $0?) {
        if (this._mark() case var _mark) {
          if (this.f1x() case var _8) {
            if ([if (_8 case var _8?) _8] case (var $1 && var _l9)) {
              if (_l9.isNotEmpty) {
                for (;;) {
                  if (this._mark() case var _mark) {
                    if (this.f1x() case var _8?) {
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
              if (this.matchPattern(_string.$35) case var $2?) {
                if ([$0, $1, $2] case var $) {
                  return $;
                }
              }
            }
          }
        }
      }

      this._recover(_mark);
      if (this.matchPattern(_string.$37) case var $0?) {
        if (this._mark() case var _mark) {
          if (this.f1y() case var _10) {
            if ([if (_10 case var _10?) _10] case (var $1 && var _l11)) {
              if (_l11.isNotEmpty) {
                for (;;) {
                  if (this._mark() case var _mark) {
                    if (this.f1y() case var _10?) {
                      _l11.add(_10);
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
                if ([$0, $1, $2] case var $) {
                  return $;
                }
              }
            }
          }
        }
      }

      this._recover(_mark);
      if (this.matchPattern(_string.$38) case var $0?) {
        if (this._mark() case var _mark) {
          if (this.f1z() case var _12) {
            if ([if (_12 case var _12?) _12] case (var $1 && var _l13)) {
              if (_l13.isNotEmpty) {
                for (;;) {
                  if (this._mark() case var _mark) {
                    if (this.f1z() case var _12?) {
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
              if (this.matchPattern(_string.$38) case var $2?) {
                if ([$0, $1, $2] case var $) {
                  return $;
                }
              }
            }
          }
        }
      }

      this._recover(_mark);
      if (this.matchPattern(_string.$39) case var $0?) {
        if (this._mark() case var _mark) {
          if (this.f20() case var _14) {
            if ([if (_14 case var _14?) _14] case (var $1 && var _l15)) {
              if (_l15.isNotEmpty) {
                for (;;) {
                  if (this._mark() case var _mark) {
                    if (this.f20() case var _14?) {
                      _l15.add(_14);
                      continue;
                    }
                    this._recover(_mark);
                    break;
                  }
                }
              } else {
                this._recover(_mark);
              }
              if (this.matchPattern(_string.$39) case var $2?) {
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

  /// `fragment24`
  Object? f22() {
    if (this._mark() case var _mark) {
      if (this.matchPattern(_string.$56) case null) {
        this._recover(_mark);
        if (this.pos < this.buffer.length) {
          if (this.buffer[this.pos++] case var $) {
            return $;
          }
        }
      }
    }
  }

  /// `fragment25`
  Object? f23() {
    if (this._mark() case var _mark) {
      if (this.apply(this.rg) case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.matchPattern(_string.$23) case var $0?) {
        if (this.apply(this.rf)! case var $1) {
          if (this.matchPattern(_string.$22) case var $2?) {
            if ([$0, $1, $2] case var $) {
              return $;
            }
          }
        }
      }

      this._recover(_mark);
      if (this.matchPattern(_string.$25) case var $0?) {
        if (this.apply(this.rf)! case var $1) {
          if (this.matchPattern(_string.$24) case var $2?) {
            if ([$0, $1, $2] case var $) {
              return $;
            }
          }
        }
      }

      this._recover(_mark);
      if (this.matchPattern(_string.$50) case var $0?) {
        if (this.apply(this.rf)! case var $1) {
          if (this.matchPattern(_string.$12) case var $2?) {
            if ([$0, $1, $2] case var $) {
              return $;
            }
          }
        }
      }

      this._recover(_mark);
      if (this.matchPattern(_string.$22) case null) {
        this._recover(_mark);
        if (this.pos < this.buffer.length) {
          if (this.buffer[this.pos++] case var $) {
            return $;
          }
        }
      }
    }
  }

  /// `fragment26`
  Object? f24() {
    if (this._mark() case var _mark) {
      if (this.matchPattern(_string.$56) case null) {
        this._recover(_mark);
        if (this.pos < this.buffer.length) {
          if (this.buffer[this.pos++] case var $) {
            return $;
          }
        }
      }
    }
  }

  /// `fragment27`
  Object? f25() {
    if (this._mark() case var _mark) {
      if (this.matchPattern(_regexp.$3) case var $?) {
        return $;
      }

      this._recover(_mark);
      if (this.matchPattern(_string.$26) case var $?) {
        return $;
      }

      this._recover(_mark);
      if (this.matchPattern(_string.$24) case var $?) {
        return $;
      }
    }
  }

  /// `fragment28`
  Object? f26() {
    if (this._mark() case var _mark) {
      if (this.apply(this.rg) case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.matchPattern(_string.$23) case var $0?) {
        if (this.apply(this.rf)! case var $1) {
          if (this.matchPattern(_string.$22) case var $2?) {
            if ([$0, $1, $2] case var $) {
              return $;
            }
          }
        }
      }

      this._recover(_mark);
      if (this.matchPattern(_string.$25) case var $0?) {
        if (this.apply(this.rf)! case var $1) {
          if (this.matchPattern(_string.$24) case var $2?) {
            if ([$0, $1, $2] case var $) {
              return $;
            }
          }
        }
      }

      this._recover(_mark);
      if (this.matchPattern(_string.$50) case var $0?) {
        if (this.apply(this.rf)! case var $1) {
          if (this.matchPattern(_string.$12) case var $2?) {
            if ([$0, $1, $2] case var $) {
              return $;
            }
          }
        }
      }

      this._recover(_mark);
      if (this.f25() case null) {
        this._recover(_mark);
        if (this.pos < this.buffer.length) {
          if (this.buffer[this.pos++] case var $) {
            return $;
          }
        }
      }
    }
  }

  /// `fragment29`
  Object? f27() {
    if (this._mark() case var _mark) {
      if (this.matchPattern(_string.$22) case var $?) {
        return $;
      }

      this._recover(_mark);
      if (this.matchPattern(_string.$24) case var $?) {
        return $;
      }

      this._recover(_mark);
      if (this.matchPattern(_string.$12) case var $?) {
        return $;
      }
    }
  }

  /// `fragment30`
  Object? f28() {
    if (this._mark() case var _mark) {
      if (this.apply(this.rg) case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.matchPattern(_string.$23) case var $0?) {
        if (this.apply(this.rf)! case var $1) {
          if (this.matchPattern(_string.$22) case var $2?) {
            if ([$0, $1, $2] case var $) {
              return $;
            }
          }
        }
      }

      this._recover(_mark);
      if (this.matchPattern(_string.$25) case var $0?) {
        if (this.apply(this.rf)! case var $1) {
          if (this.matchPattern(_string.$24) case var $2?) {
            if ([$0, $1, $2] case var $) {
              return $;
            }
          }
        }
      }

      this._recover(_mark);
      if (this.matchPattern(_string.$50) case var $0?) {
        if (this.apply(this.rf)! case var $1) {
          if (this.matchPattern(_string.$12) case var $2?) {
            if ([$0, $1, $2] case var $) {
              return $;
            }
          }
        }
      }

      this._recover(_mark);
      if (this.f27() case null) {
        this._recover(_mark);
        if (this.pos < this.buffer.length) {
          if (this.buffer[this.pos++] case var $) {
            return $;
          }
        }
      }
    }
  }

  /// `fragment31`
  Object? f29() {
    if (this.f18() case var $?) {
      return $;
    }
  }

  /// `fragment32`
  Object? f2a() {
    if (this._mark() case var _mark) {
      if (this.apply(this.rg) case var $?) {
        return $;
      }
      this._recover(_mark);
      if (this.matchPattern(_string.$23) case var $0?) {
        if (this.apply(this.ri)! case var $1) {
          if (this.matchPattern(_string.$22) case var $2?) {
            if ([$0, $1, $2] case var $) {
              return $;
            }
          }
        }
      }

      this._recover(_mark);
      if (this.matchPattern(_string.$22) case null) {
        this._recover(_mark);
        if (this.pos < this.buffer.length) {
          if (this.buffer[this.pos++] case var $) {
            return $;
          }
        }
      }
    }
  }

  /// `fragment33`
  Object? f2b() {
    if (this.apply(this.ry) case var $0?) {
      if (this.matchPattern(_string.$57) case var $1?) {
        if (this.apply(this.ry) case var $2?) {
          if ([$0, $1, $2] case var $) {
            return $;
          }
        }
      }
    }
  }

  /// `fragment34`
  Object? f2c() {
    if (this.apply(this.ry) case var $0?) {
      if (this.matchPattern(_string.$58) case var $1?) {
        if (this.apply(this.ry) case var $2?) {
          if ([$0, $1, $2] case var $) {
            return $;
          }
        }
      }
    }
  }

  /// `fragment35`
  Object? f2d() {
    if (this.apply(this.ry) case var $0?) {
      if (this.matchPattern(_string.$50) case var $1?) {
        if (this.apply(this.ry) case var $2?) {
          if ([$0, $1, $2] case var $) {
            return $;
          }
        }
      }
    }
  }

  /// `fragment36`
  Object? f2e() {
    if (this.apply(this.ry) case var $0?) {
      if (this.matchPattern(_string.$12) case var $1?) {
        if (this.apply(this.ry) case var $2?) {
          if ([$0, $1, $2] case var $) {
            return $;
          }
        }
      }
    }
  }

  /// `fragment37`
  Object? f2f() {
    if (this._mark() case var _mark) {
      if (this.matchPattern(_string.$56) case null) {
        this._recover(_mark);
        if (this.pos < this.buffer.length) {
          if (this.buffer[this.pos++] case var $) {
            return $;
          }
        }
      }
    }
  }

  /// `fragment38`
  Object? f2g() {
    if (this.matchPattern(_string.$56) case var $0?) {
      if (this.f2f() case var _0) {
        if (this._mark() case var _mark) {
          var _l1 = [if (_0 case var _0?) _0];
          if (_l1.isNotEmpty) {
            for (;;) {
              if (this._mark() case var _mark) {
                if (this.f2f() case var _0?) {
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
          if (_l1 case var $1) {
            if (this.matchPattern(_string.$56) case var $2?) {
              if ([$0, $1, $2] case var $) {
                return $;
              }
            }
          }
        }
      }
    }
  }

  /// `fragment39`
  Object? f2h() {
    if (this._mark() case var _mark) {
      if (this.matchPattern(_string.$59) case var $?) {
        return $;
      }

      this._recover(_mark);
      if (this.matchPattern(_string.$21) case (var $0 && null)) {
        this._recover(_mark);
        if (this.matchPattern(_string.$34) case var $1?) {
          if ([$0, $1] case var $) {
            return $;
          }
        }
      }
    }
  }

  /// `fragment40`
  Object? f2i() {
    if (this._mark() case var _mark) {
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
      if (this.fg() case var $?) {
        return $;
      }
    }
  }

  /// `fragment41`
  Object? f2j() {
    if (this.f9() case var $0?) {
      if (this.f2h() case var $1?) {
        if (this._mark() case var _mark) {
          if (this.f2i() case (var $2 && null)) {
            this._recover(_mark);
            if ([$0, $1, $2] case var $) {
              return $;
            }
          }
        }
      }
    }
  }

  /// `fragment42`
  Object? f2k() {
    if (this._mark() case var _mark) {
      if (this.matchPattern(_string.$56) case null) {
        this._recover(_mark);
        if (this.pos < this.buffer.length) {
          if (this.buffer[this.pos++] case var $) {
            return $;
          }
        }
      }
    }
  }

  /// `fragment43`
  Object? f2l() {
    if (this.matchPattern(_string.$56) case var $0?) {
      if (this._mark() case var _mark) {
        if (this.f2k() case var _0) {
          if ([if (_0 case var _0?) _0] case (var $1 && var _l1)) {
            if (_l1.isNotEmpty) {
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
            } else {
              this._recover(_mark);
            }
            if (this.matchPattern(_string.$56) case var $2?) {
              if ([$0, $1, $2] case var $) {
                return $;
              }
            }
          }
        }
      }
    }
  }

  /// `fragment44`
  Object? f2m() {
    if (this._mark() case var _mark) {
      if (this.f14() case var $0) {
        if (this.fz() case var $1?) {
          if ([$0, $1] case var $) {
            return $;
          }
        }
      }
      this._recover(_mark);
      if (this.apply(this.ry) case var $0?) {
        if (this.matchPattern(_string.$60) case var $1?) {
          if (this.apply(this.ry) case var $2?) {
            if ([$0, $1, $2] case var $) {
              return $;
            }
          }
        }
      }
      this._recover(_mark);
      if (this.apply(this.ry) case var $0?) {
        if (this.matchPattern(_string.$61) case var $1?) {
          if (this.apply(this.ry) case var $2?) {
            if ([$0, $1, $2] case var $) {
              return $;
            }
          }
        }
      }
    }
  }

  /// `fragment45`
  Object? f2n() {
    if (this.matchPattern(_string.$11) case var $0?) {
      if (this.matchPattern(_string.$11) case var $1?) {
        if ([$0, $1] case var $) {
          return $;
        }
      }
    }
  }

  /// `fragment46`
  Object? f2o() {
    if (this.matchPattern(_string.$11) case var $0?) {
      if (this.matchPattern(_string.$62) case var $1?) {
        if ([$0, $1] case var $) {
          return $;
        }
      }
    }
  }

  /// `fragment47`
  Object? f2p() {
    if (this.matchPattern(_string.$11) case var $0?) {
      if (this.matchPattern(_string.$63) case var $1?) {
        if ([$0, $1] case var $) {
          return $;
        }
      }
    }
  }

  /// `fragment48`
  Object? f2q() {
    if (this.matchPattern(_string.$11) case var $0?) {
      if (this.matchPattern(_string.$64) case var $1?) {
        if ([$0, $1] case var $) {
          return $;
        }
      }
    }
  }

  /// `fragment49`
  Object? f2r() {
    if (this.matchPattern(_string.$11) case var $0?) {
      if (this.matchPattern(_string.$62) case var $1?) {
        if ([$0, $1] case var $) {
          return $;
        }
      }
    }
  }

  /// `fragment50`
  Object? f2s() {
    if (this.matchPattern(_string.$11) case var $0?) {
      if (this.matchPattern(_string.$63) case var $1?) {
        if ([$0, $1] case var $) {
          return $;
        }
      }
    }
  }

  /// `fragment51`
  Object? f2t() {
    if (this.matchPattern(_string.$11) case var $0?) {
      if (this.matchPattern(_string.$64) case var $1?) {
        if ([$0, $1] case var $) {
          return $;
        }
      }
    }
  }

  /// `fragment52`
  Object? f2u() {
    if (this.matchPattern(_string.$11) case var $0?) {
      if (this.matchPattern(_string.$65) case var $1?) {
        if ([$0, $1] case var $) {
          return $;
        }
      }
    }
  }

  /// `fragment53`
  Object? f2v() {
    if (this.matchPattern(_string.$11) case var $0?) {
      if (this.matchPattern(_string.$36) case var $1?) {
        if ([$0, $1] case var $) {
          return $;
        }
      }
    }
  }

  /// `fragment54`
  Object? f2w() {
    if (this.matchPattern(_string.$11) case var $0?) {
      if (this.matchPattern(_string.$66) case var $1?) {
        if ([$0, $1] case var $) {
          return $;
        }
      }
    }
  }

  /// `fragment55`
  Object? f2x() {
    if (this.matchPattern(_string.$11) case var $0?) {
      if (this.matchPattern(_string.$67) case var $1?) {
        if ([$0, $1] case var $) {
          return $;
        }
      }
    }
  }

  /// `fragment56`
  Object? f2y() {
    if (this.matchPattern(_string.$11) case var $0?) {
      if (this.matchPattern(_string.$68) case var $1?) {
        if ([$0, $1] case var $) {
          return $;
        }
      }
    }
  }

  /// `fragment57`
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

  /// `fragment58`
  Object? f30() {
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

  /// `fragment59`
  Object? f31() {
    if (this._mark() case var _mark) {
      if (this.matchPattern(_string.$38) case null) {
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
  Object? f32() {
    if (this._mark() case var _mark) {
      if (this.matchPattern(_string.$39) case null) {
        this._recover(_mark);
        if (this.pos < this.buffer.length) {
          if (this.buffer[this.pos++] case var $) {
            return $;
          }
        }
      }
    }
  }

  /// `fragment61`
  Object? f33() {
    if (this._mark() case var _mark) {
      if (this.matchPattern(_string.$11) case var $0?) {
        if (this.pos < this.buffer.length) {
          if (this.buffer[this.pos++] case var $1) {
            if ([$0, $1] case var $) {
              return $;
            }
          }
        }
      }

      this._recover(_mark);
      if (this.matchPattern(_string.$40) case var $0?) {
        this._recover(_mark);
        if (this.f19() case var $1?) {
          if ([$0, $1] case var $) {
            return $;
          }
        }
      }

      this._recover(_mark);
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

  /// `fragment62`
  Object? f34() {
    if (this._mark() case var _mark) {
      if (this.matchPattern(_string.$11) case var $0?) {
        if (this.pos < this.buffer.length) {
          if (this.buffer[this.pos++] case var $1) {
            if ([$0, $1] case var $) {
              return $;
            }
          }
        }
      }

      this._recover(_mark);
      if (this.matchPattern(_string.$40) case var $0?) {
        this._recover(_mark);
        if (this.f19() case var $1?) {
          if ([$0, $1] case var $) {
            return $;
          }
        }
      }

      this._recover(_mark);
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

  /// `fragment63`
  Object? f35() {
    if (this._mark() case var _mark) {
      if (this.matchPattern(_string.$11) case var $0?) {
        if (this.pos < this.buffer.length) {
          if (this.buffer[this.pos++] case var $1) {
            if ([$0, $1] case var $) {
              return $;
            }
          }
        }
      }

      this._recover(_mark);
      if (this.matchPattern(_string.$40) case var $0?) {
        this._recover(_mark);
        if (this.f19() case var $1?) {
          if ([$0, $1] case var $) {
            return $;
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
    }
  }

  /// `fragment64`
  Object? f36() {
    if (this._mark() case var _mark) {
      if (this.matchPattern(_string.$11) case var $0?) {
        if (this.pos < this.buffer.length) {
          if (this.buffer[this.pos++] case var $1) {
            if ([$0, $1] case var $) {
              return $;
            }
          }
        }
      }

      this._recover(_mark);
      if (this.matchPattern(_string.$40) case var $0?) {
        this._recover(_mark);
        if (this.f19() case var $1?) {
          if ([$0, $1] case var $) {
            return $;
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
  }

  /// `fragment65`
  Object? f37() {
    if (this._mark() case var _mark) {
      if (this.matchPattern(_string.$69) case var $?) {
        return $;
      }

      this._recover(_mark);
      if (this.matchPattern(_string.$70) case var $?) {
        return $;
      }
    }
  }

  /// `fragment66`
  Object f38() {
    if (this._mark() case var _mark) {
      if (this.matchPattern(_string.$30) case var $?) {
        return $;
      }

      this._recover(_mark);
      if (this.matchPattern(_string.$41) case var $?) {
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
      if (this.apply(this.r1) case var $1) {
        if (this.apply(this.r2) case var _0?) {
          if ([_0] case (var $2 && var _l1)) {
            for (;;) {
              if (this._mark() case var _mark) {
                if (this.apply(this.ry) case _?) {
                  if (this.apply(this.r2) case var _0?) {
                    _l1.add(_0);
                    continue;
                  }
                }
                this._recover(_mark);
                break;
              }
            }
            if (this.apply(this.ry) case var $3) {
              if (this.pos case var $4 when this.pos >= this.buffer.length) {
                if ([$0, $1, $2, $3, $4] case var $) {
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
    if (this.fv() case var $0?) {
      if (this.apply(this.ry) case var $1?) {
        if (this.apply(this.rd)! case var code) {
          if (this.apply(this.ry) case var $3?) {
            if (this.fu() case var $4?) {
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
    if (this._mark() case var _mark) {
      if (this.fb() case var outer_decorator) {
        if (this.f4() case var type) {
          if (this.f9() case var name?) {
            if (this.fz() case var $3?) {
              if (this.fg() case var $4?) {
                if (this.fb() case var inner_decorator) {
                  if (this.fv() case var $6?) {
                    if (this.apply(this.r2) case var _0?) {
                      if ([_0] case (var statements && var _l1)) {
                        for (;;) {
                          if (this._mark() case var _mark) {
                            if (this.apply(this.ry) case _?) {
                              if (this.apply(this.r2) case var _0?) {
                                _l1.add(_0);
                                continue;
                              }
                            }
                            this._recover(_mark);
                            break;
                          }
                        }
                        if (this.fu() case var $8?) {
                          if (this.fy() case var $9) {
                            if ([outer_decorator, type, name, $3, $4, inner_decorator, $6, statements, $8, $9] case var $) {
                              return ("<statement>", $);
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
      if (this.fb() case var outer_decorator) {
        if (this.f4() case var type) {
          if (this.fx() case var $2?) {
            if (this.fw() case var $3?) {
              if (this.fz() case var $4?) {
                if (this.fg() case var $5?) {
                  if (this.fb() case var inner_decorator) {
                    if (this.fv() case var $7?) {
                      if (this.apply(this.r2) case var _2?) {
                        if ([_2] case (var statements && var _l3)) {
                          for (;;) {
                            if (this._mark() case var _mark) {
                              if (this.apply(this.ry) case _?) {
                                if (this.apply(this.r2) case var _2?) {
                                  _l3.add(_2);
                                  continue;
                                }
                              }
                              this._recover(_mark);
                              break;
                            }
                          }
                          if (this.fu() case var $9?) {
                            if (this.fy() case var $10) {
                              if ([outer_decorator, type, $2, $3, $4, $5, inner_decorator, $7, statements, $9, $10] case var $) {
                                return ("<statement>", $);
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
      this._recover(_mark);
      if (this.fb() case var decorator) {
        if (this.f9() case var name) {
          if (this.fv() case var $2?) {
            if (this.apply(this.r2) case var _4?) {
              if ([_4] case (var statements && var _l5)) {
                for (;;) {
                  if (this._mark() case var _mark) {
                    if (this.apply(this.ry) case _?) {
                      if (this.apply(this.r2) case var _4?) {
                        _l5.add(_4);
                        continue;
                      }
                    }
                    this._recover(_mark);
                    break;
                  }
                }
                if (this.fu() case var $4?) {
                  if ([decorator, name, $2, statements, $4] case var $) {
                    return ("<statement>", $);
                  }
                }
              }
            }
          }
        }
      }
      this._recover(_mark);
      if (this.fb() case var decorator) {
        if (this.f4() case var type) {
          if (this.f6() case var _6?) {
            if ([_6] case (var names && var _l7)) {
              for (;;) {
                if (this._mark() case var _mark) {
                  if (this.f13() case _?) {
                    if (this.f6() case var _6?) {
                      _l7.add(_6);
                      continue;
                    }
                  }
                  this._recover(_mark);
                  break;
                }
              }
              if (this.fy() case var $3?) {
                if ([decorator, type, names, $3] case var $) {
                  return ("<statement>", $);
                }
              }
            }
          }
        }
      }
      this._recover(_mark);
      if (this.fb() case var decorator) {
        if (this.fc() case var $1) {
          if (this.f6() case var name?) {
            if (this.f14() case var $3?) {
              if (this.f4() case var type?) {
                if (this.fy() case var $5?) {
                  if ([decorator, $1, name, $3, type, $5] case var $) {
                    return ("<statement>", $);
                  }
                }
              }
            }
          }
        }
      }
      this._recover(_mark);
      if (this.fb() case var decorator) {
        if (this.fc() case var $1) {
          if (this.f6() case var name?) {
            if (this.f8() case var body?) {
              if ([decorator, $1, name, body] case var $) {
                return ("<statement>", $);
              }
            }
          }
        }
      }
      this._recover(_mark);
      if (this.fb() case var decorator) {
        if (this.f4() case var type?) {
          if (this.f6() case var name?) {
            if (this.f8() case var body?) {
              if ([decorator, type, name, body] case var $) {
                return ("<statement>", $);
              }
            }
          }
        }
      }
      this._recover(_mark);
      if (this.fb() case var decorator) {
        if (this.fc() case var $1) {
          if (this.f6() case var name?) {
            if (this.f14() case var $3?) {
              if (this.f4() case var type?) {
                if (this.f8() case var body?) {
                  if ([decorator, $1, name, $3, type, body] case var $) {
                    return ("<statement>", $);
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
  Object? r3() {
    if (this.f1e() case var $0) {
      if (this.apply(this.r4) case var _0?) {
        if ([_0] case (var options && var _l1)) {
          for (;;) {
            if (this._mark() case var _mark) {
              if (this.f1f() case _?) {
                if (this.apply(this.r4) case var _0?) {
                  _l1.add(_0);
                  continue;
                }
              }
              this._recover(_mark);
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
  Object? r4() {
    if (this._mark() case var _mark) {
      if (this.apply(this.r5) case var sequence?) {
        if (this.f1g() case var $1?) {
          if (this.apply(this.ry) case var $2?) {
            if (this.apply(this.re)! case var code) {
              if (this.apply(this.ry) case var $4?) {
                if ([sequence, $1, $2, code, $4] case var $) {
                  return ("<acted>", $);
                }
              }
            }
          }
        }
      }
      this._recover(_mark);
      if (this.apply(this.r5) case var sequence?) {
        if (this.fv() case var $1?) {
          if (this.apply(this.ry) case var $2?) {
            if (this.apply(this.rd)! case var code) {
              if (this.apply(this.ry) case var $4?) {
                if (this.fu() case var $5?) {
                  if ([sequence, $1, $2, code, $4, $5] case var $) {
                    return ("<acted>", $);
                  }
                }
              }
            }
          }
        }
      }
      this._recover(_mark);
      if (this.apply(this.r5) case var sequence?) {
        if (this.fx() case var $1?) {
          if (this.fw() case var $2?) {
            if (this.fv() case var $3?) {
              if (this.apply(this.ry) case var $4?) {
                if (this.apply(this.rd)! case var code) {
                  if (this.apply(this.ry) case var $6?) {
                    if (this.fu() case var $7?) {
                      if ([sequence, $1, $2, $3, $4, code, $6, $7] case var $) {
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
      this._recover(_mark);
      if (this.apply(this.r5) case var $?) {
        return ("<acted>", $);
      }
    }
  }

  /// `global::sequence`
  Object? r5() {
    if (this.apply(this.r6) case var _0?) {
      if ([_0] case (var body && var _l1)) {
        for (;;) {
          if (this._mark() case var _mark) {
            if (this.apply(this.ry) case _?) {
              if (this.apply(this.r6) case var _0?) {
                _l1.add(_0);
                continue;
              }
            }
            this._recover(_mark);
            break;
          }
        }
        if (this.f1i() case var chosen) {
          if ([body, chosen] case var $) {
            return ("<sequence>", $);
          }
        }
      }
    }
  }

  /// `global::dropped`
  Object? r6() {
    if (this._mark() case var _mark) {
      if (this.apply(this.r6) case var captured?) {
        if (this.f1j() case var $1?) {
          if (this.apply(this.r8) case var dropped?) {
            if ([captured, $1, dropped] case var $) {
              return ("<dropped>", $);
            }
          }
        }
      }
      this._recover(_mark);
      if (this.apply(this.r8) case var dropped?) {
        if (this.f1k() case var $1?) {
          if (this.apply(this.r6) case var captured?) {
            if ([dropped, $1, captured] case var $) {
              return ("<dropped>", $);
            }
          }
        }
      }
      this._recover(_mark);
      if (this.apply(this.r7) case var $?) {
        return ("<dropped>", $);
      }
    }
  }

  /// `global::labeled`
  Object? r7() {
    if (this._mark() case var _mark) {
      if (this.f9() case var identifier?) {
        if (this.matchPattern(_string.$32) case var $1?) {
          if (this.apply(this.ry) case var $2?) {
            if (this.apply(this.r8) case var special?) {
              if ([identifier, $1, $2, special] case var $) {
                return ("<labeled>", $);
              }
            }
          }
        }
      }
      this._recover(_mark);
      if (this.matchPattern(_string.$32) case var $0?) {
        if (this.f7() case var id?) {
          if (this.f10() case var $2?) {
            if ([$0, id, $2] case var $) {
              return ("<labeled>", $);
            }
          }
        }
      }

      this._recover(_mark);
      if (this.matchPattern(_string.$32) case var $0?) {
        if (this.f7() case var id?) {
          if (this.f11() case var $2?) {
            if ([$0, id, $2] case var $) {
              return ("<labeled>", $);
            }
          }
        }
      }

      this._recover(_mark);
      if (this.matchPattern(_string.$32) case var $0?) {
        if (this.f7() case var id?) {
          if (this.f12() case var $2?) {
            if ([$0, id, $2] case var $) {
              return ("<labeled>", $);
            }
          }
        }
      }

      this._recover(_mark);
      if (this.matchPattern(_string.$32) case var $0?) {
        if (this.f7() case var id?) {
          if ([$0, id] case var $) {
            return ("<labeled>", $);
          }
        }
      }

      this._recover(_mark);
      if (this.apply(this.r8) case var $?) {
        return ("<labeled>", $);
      }
    }
  }

  /// `global::special`
  Object? r8() {
    if (this._mark() case var _mark) {
      if (this.apply(this.rb) case var sep?) {
        if (this.ft() case var $1?) {
          if (this.apply(this.rb) case var expr?) {
            if (this.f12() case var $3?) {
              if (this.f10() case var $4?) {
                if ([sep, $1, expr, $3, $4] case var $) {
                  return ("<special>", $);
                }
              }
            }
          }
        }
      }
      this._recover(_mark);
      if (this.apply(this.rb) case var sep?) {
        if (this.ft() case var $1?) {
          if (this.apply(this.rb) case var expr?) {
            if (this.f11() case var $3?) {
              if (this.f10() case var $4?) {
                if ([sep, $1, expr, $3, $4] case var $) {
                  return ("<special>", $);
                }
              }
            }
          }
        }
      }
      this._recover(_mark);
      if (this.apply(this.rb) case var sep?) {
        if (this.ft() case var $1?) {
          if (this.apply(this.rb) case var expr?) {
            if (this.f12() case var $3?) {
              if ([sep, $1, expr, $3] case var $) {
                return ("<special>", $);
              }
            }
          }
        }
      }
      this._recover(_mark);
      if (this.apply(this.rb) case var sep?) {
        if (this.ft() case var $1?) {
          if (this.apply(this.rb) case var expr?) {
            if (this.f11() case var $3?) {
              if ([sep, $1, expr, $3] case var $) {
                return ("<special>", $);
              }
            }
          }
        }
      }
      this._recover(_mark);
      if (this.apply(this.r9) case var $?) {
        return ("<special>", $);
      }
    }
  }

  /// `global::postfix`
  Object? r9() {
    if (this._mark() case var _mark) {
      if (this.apply(this.r9) case var $0?) {
        if (this.f10() case var $1?) {
          if ([$0, $1] case var $) {
            return ("<postfix>", $);
          }
        }
      }
      this._recover(_mark);
      if (this.apply(this.r9) case var $0?) {
        if (this.f11() case var $1?) {
          if ([$0, $1] case var $) {
            return ("<postfix>", $);
          }
        }
      }
      this._recover(_mark);
      if (this.apply(this.r9) case var $0?) {
        if (this.f12() case var $1?) {
          if ([$0, $1] case var $) {
            return ("<postfix>", $);
          }
        }
      }
      this._recover(_mark);
      if (this.apply(this.ra) case var $?) {
        return ("<postfix>", $);
      }
    }
  }

  /// `global::prefix`
  Object? ra() {
    if (this._mark() case var _mark) {
      if (this.fa() case var min?) {
        if (this.ft() case var $1?) {
          if (this.fa() case var max) {
            if (this.apply(this.rc) case var body?) {
              if ([min, $1, max, body] case var $) {
                return ("<prefix>", $);
              }
            }
          }
        }
      }
      this._recover(_mark);
      if (this.fa() case var number?) {
        if (this.apply(this.rc) case var body?) {
          if ([number, body] case var $) {
            return ("<prefix>", $);
          }
        }
      }
      this._recover(_mark);
      if (this.f1l() case var $0?) {
        if (this.apply(this.ra) case var $1?) {
          if ([$0, $1] case var $) {
            return ("<prefix>", $);
          }
        }
      }
      this._recover(_mark);
      if (this.f1m() case var $0?) {
        if (this.apply(this.ra) case var $1?) {
          if ([$0, $1] case var $) {
            return ("<prefix>", $);
          }
        }
      }
      this._recover(_mark);
      if (this.f1n() case var $0?) {
        if (this.apply(this.ra) case var $1?) {
          if ([$0, $1] case var $) {
            return ("<prefix>", $);
          }
        }
      }
      this._recover(_mark);
      if (this.apply(this.rb) case var $?) {
        return ("<prefix>", $);
      }
    }
  }

  /// `global::call`
  Object? rb() {
    if (this._mark() case var _mark) {
      if (this.apply(this.rb) case var target?) {
        if (this.f16() case var $1?) {
          if (this.fe() case var $2?) {
            if (this.fx() case var $3?) {
              if (this.fw() case var $4?) {
                if ([target, $1, $2, $3, $4] case var $) {
                  return ("<call>", $);
                }
              }
            }
          }
        }
      }
      this._recover(_mark);
      if (this.apply(this.rb) case var target?) {
        if (this.f16() case var $1?) {
          if (this.fd() case var $2?) {
            if (this.fx() case var $3?) {
              if (this.fa() case var min?) {
                if (this.f13() case var $5?) {
                  if (this.fa() case var max?) {
                    if (this.fw() case var $7?) {
                      if ([target, $1, $2, $3, min, $5, max, $7] case var $) {
                        return ("<call>", $);
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
      if (this.apply(this.rb) case var target?) {
        if (this.f16() case var $1?) {
          if (this.fd() case var $2?) {
            if (this.fx() case var $3?) {
              if (this.fa() case var number?) {
                if (this.fw() case var $5?) {
                  if ([target, $1, $2, $3, number, $5] case var $) {
                    return ("<call>", $);
                  }
                }
              }
            }
          }
        }
      }
      this._recover(_mark);
      if (this.apply(this.rb) case var target?) {
        if (this.f16() case var $1?) {
          if (this.fd() case var $2?) {
            if (this.apply(this.ry) case var $3?) {
              if (this.fa() case var number?) {
                if (this.apply(this.ry) case var $5?) {
                  if ([target, $1, $2, $3, number, $5] case var $) {
                    return ("<call>", $);
                  }
                }
              }
            }
          }
        }
      }
      this._recover(_mark);
      if (this.apply(this.rb) case var sep?) {
        if (this.f16() case var $1?) {
          if (this.ff() case var $2?) {
            if (this.fx() case var $3?) {
              if (this.apply(this.r3) case var body?) {
                if (this.fw() case var $5?) {
                  if (this.f12() case var $6?) {
                    if (this.f10() case var $7?) {
                      if ([sep, $1, $2, $3, body, $5, $6, $7] case var $) {
                        return ("<call>", $);
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
      if (this.apply(this.rb) case var sep?) {
        if (this.f16() case var $1?) {
          if (this.ff() case var $2?) {
            if (this.fx() case var $3?) {
              if (this.apply(this.r3) case var body?) {
                if (this.fw() case var $5?) {
                  if (this.f11() case var $6?) {
                    if (this.f10() case var $7?) {
                      if ([sep, $1, $2, $3, body, $5, $6, $7] case var $) {
                        return ("<call>", $);
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
      if (this.apply(this.rb) case var sep?) {
        if (this.f16() case var $1?) {
          if (this.ff() case var $2?) {
            if (this.fx() case var $3?) {
              if (this.apply(this.r3) case var body?) {
                if (this.fw() case var $5?) {
                  if (this.f12() case var $6?) {
                    if ([sep, $1, $2, $3, body, $5, $6] case var $) {
                      return ("<call>", $);
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
        if (this.f16() case var $1?) {
          if (this.ff() case var $2?) {
            if (this.fx() case var $3?) {
              if (this.apply(this.r3) case var body?) {
                if (this.fw() case var $5?) {
                  if (this.f11() case var $6?) {
                    if ([sep, $1, $2, $3, body, $5, $6] case var $) {
                      return ("<call>", $);
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
        if (this.f16() case var $1?) {
          if (this.ff() case var $2?) {
            if (this.fx() case var $3?) {
              if (this.apply(this.r3) case var body?) {
                if (this.fw() case var $5?) {
                  if ([sep, $1, $2, $3, body, $5] case var $) {
                    return ("<call>", $);
                  }
                }
              }
            }
          }
        }
      }
      this._recover(_mark);
      if (this.apply(this.rb) case var sep?) {
        if (this.f16() case var $1?) {
          if (this.ff() case var $2?) {
            if (this.apply(this.ry) case var $3?) {
              if (this.apply(this.rc) case var body?) {
                if (this.apply(this.ry) case var $5?) {
                  if ([sep, $1, $2, $3, body, $5] case var $) {
                    return ("<call>", $);
                  }
                }
              }
            }
          }
        }
      }
      this._recover(_mark);
      if (this.apply(this.rc) case var $?) {
        return ("<call>", $);
      }
    }
  }

  /// `global::atom`
  Object? rc() {
    if (this._mark() case var _mark) {
      if (this.fx() case var $0?) {
        if (this.f1o() case var $1?) {
          if ([$0, $1] case var $) {
            return ("<atom>", $);
          }
        }
      }
      this._recover(_mark);
      if (this.apply(this.ry) case var $0?) {
        if (this.matchPattern(_string.$71) case var $1?) {
          if (this.apply(this.ry) case var $2?) {
            if ([$0, $1, $2] case var $) {
              return ("<atom>", $);
            }
          }
        }
      }
      this._recover(_mark);
      if (this.apply(this.ry) case var $0?) {
        if (this.matchPattern(_string.$40) case var $1?) {
          if (this.apply(this.ry) case var $2?) {
            if ([$0, $1, $2] case var $) {
              return ("<atom>", $);
            }
          }
        }
      }
      this._recover(_mark);
      if (this.f16() case var $?) {
        return ("<atom>", $);
      }
      this._recover(_mark);
      if (this.apply(this.ry) case var $0?) {
        if (this.matchPattern(_string.$72) case var $1?) {
          if (this.apply(this.ry) case var $2?) {
            if ([$0, $1, $2] case var $) {
              return ("<atom>", $);
            }
          }
        }
      }
      this._recover(_mark);
      if (this.fh() case var $?) {
        return ("<atom>", $);
      }
      this._recover(_mark);
      if (this.fi() case var $?) {
        return ("<atom>", $);
      }
      this._recover(_mark);
      if (this.fj() case var $?) {
        return ("<atom>", $);
      }
      this._recover(_mark);
      if (this.fk() case var $?) {
        return ("<atom>", $);
      }
      this._recover(_mark);
      if (this.fl() case var $?) {
        return ("<atom>", $);
      }
      this._recover(_mark);
      if (this.fm() case var $?) {
        return ("<atom>", $);
      }
      this._recover(_mark);
      if (this.fn() case var $?) {
        return ("<atom>", $);
      }
      this._recover(_mark);
      if (this.fq() case var $?) {
        return ("<atom>", $);
      }
      this._recover(_mark);
      if (this.fo() case var $?) {
        return ("<atom>", $);
      }
      this._recover(_mark);
      if (this.fp() case var $?) {
        return ("<atom>", $);
      }
      this._recover(_mark);
      if (this.fr() case var $?) {
        return ("<atom>", $);
      }
      this._recover(_mark);
      if (this.fs() case var $?) {
        return ("<atom>", $);
      }
      this._recover(_mark);
      if (this.apply(this.ry) case var $0?) {
        if (this.f1q() case var $1?) {
          if (this.apply(this.ry) case var $2?) {
            if ([$0, $1, $2] case var $) {
              return ("<atom>", $);
            }
          }
        }
      }
      this._recover(_mark);
      if (this.matchPattern(_string.$51) case var $0?) {
        if (this.f1s() case var $1?) {
          if (this.matchPattern(_string.$51) case var $2?) {
            if ([$0, $1, $2] case var $) {
              return ("<atom>", $);
            }
          }
        }
      }

      this._recover(_mark);
      if (this.apply(this.ry) case var $0?) {
        if (this.f21() case var $1?) {
          if (this.apply(this.ry) case var $2?) {
            if ([$0, $1, $2] case var $) {
              return ("<atom>", $);
            }
          }
        }
      }
      this._recover(_mark);
      if (this.f6() case var $?) {
        return ("<atom>", $);
      }
    }
  }

  /// `global::code::curly`
  Object rd() {
    if (this._mark() case var _mark) {
      if (this.matchPattern(_string.$56) case var $0?) {
        if (this._mark() case var _mark) {
          if (this.f22() case var _0) {
            if ([if (_0 case var _0?) _0] case (var $1 && var _l1)) {
              if (_l1.isNotEmpty) {
                for (;;) {
                  if (this._mark() case var _mark) {
                    if (this.f22() case var _0?) {
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
              if (this.matchPattern(_string.$56) case var $2?) {
                if ([$0, $1, $2] case var $) {
                  return ("<code::curly>", $);
                }
              }
            }
          }
        }
      }

      this._recover(_mark);
      if (this.f23() case var _2) {
        if ([if (_2 case var _2?) _2] case (var $ && var code && var _l3)) {
          if (_l3.isNotEmpty) {
            for (;;) {
              if (this._mark() case var _mark) {
                if (this.f23() case var _2?) {
                  _l3.add(_2);
                  continue;
                }
                this._recover(_mark);
                break;
              }
            }
          } else {
            this._recover(_mark);
          }
          return ("<code::curly>", $);
        }
      }
    }
  }

  /// `global::code::nl`
  Object re() {
    if (this._mark() case var _mark) {
      if (this.matchPattern(_string.$56) case var $0?) {
        if (this._mark() case var _mark) {
          if (this.f24() case var _0) {
            if ([if (_0 case var _0?) _0] case (var $1 && var _l1)) {
              if (_l1.isNotEmpty) {
                for (;;) {
                  if (this._mark() case var _mark) {
                    if (this.f24() case var _0?) {
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
              if (this.matchPattern(_string.$56) case var $2?) {
                if ([$0, $1, $2] case var $) {
                  return ("<code::nl>", $);
                }
              }
            }
          }
        }
      }

      this._recover(_mark);
      if (this.f26() case var _2) {
        if ([if (_2 case var _2?) _2] case (var $ && var _l3)) {
          if (_l3.isNotEmpty) {
            for (;;) {
              if (this._mark() case var _mark) {
                if (this.f26() case var _2?) {
                  _l3.add(_2);
                  continue;
                }
                this._recover(_mark);
                break;
              }
            }
          } else {
            this._recover(_mark);
          }
          return ("<code::nl>", $);
        }
      }
    }
  }

  /// `global::code::balanced`
  Object rf() {
    if (this._mark() case var _mark) {
      if (this.f28() case var _0) {
        if ([if (_0 case var _0?) _0] case (var $ && var _l1)) {
          if (_l1.isNotEmpty) {
            for (;;) {
              if (this._mark() case var _mark) {
                if (this.f28() case var _0?) {
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
          return ("<code::balanced>", $);
        }
      }
    }
  }

  /// `global::dart::literal::string`
  Object? rg() {
    if (this.f29() case var _0?) {
      if ([_0] case (var $ && var _l1)) {
        for (;;) {
          if (this._mark() case var _mark) {
            if (this.apply(this.ry) case _?) {
              if (this.f29() case var _0?) {
                _l1.add(_0);
                continue;
              }
            }
            this._recover(_mark);
            break;
          }
        }
        return ("<dart::literal::string>", $);
      }
    }
  }

  /// `global::dart::literal::identifier`
  Object? rh() {
    if (this.f9() case var $?) {
      return ("<dart::literal::identifier>", $);
    }
  }

  /// `global::dart::literal::string::balanced`
  Object ri() {
    if (this._mark() case var _mark) {
      if (this.f2a() case var _0) {
        if ([if (_0 case var _0?) _0] case (var $ && var _l1)) {
          if (_l1.isNotEmpty) {
            for (;;) {
              if (this._mark() case var _mark) {
                if (this.f2a() case var _0?) {
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
          return ("<dart::literal::string::balanced>", $);
        }
      }
    }
  }

  /// `global::dart::type::main`
  Object? rj() {
    if (this.apply(this.ry) case var $0?) {
      if (this.apply(this.rk) case var $1?) {
        if (this.apply(this.ry) case var $2?) {
          if ([$0, $1, $2] case var $) {
            return ("<dart::type::main>", $);
          }
        }
      }
    }
  }

  /// `global::dart::type::type`
  Object? rk() {
    if (this._mark() case var _mark) {
      if (this.apply(this.rk) case var type?) {
        if (this.apply(this.ry) case var $1?) {
          if (this.matchPattern(_string.$73) case var $2?) {
            if (this.apply(this.ry) case var $3?) {
              if (this.apply(this.ro) case var parameters?) {
                if (this.f10() case var $5) {
                  if ([type, $1, $2, $3, parameters, $5] case var $) {
                    return ("<dart::type::type>", $);
                  }
                }
              }
            }
          }
        }
      }
      this._recover(_mark);
      if (this.apply(this.rl) case var $?) {
        return ("<dart::type::type>", $);
      }
    }
  }

  /// `global::dart::type::nullable`
  Object? rl() {
    if (this._mark() case var _mark) {
      if (this.apply(this.rm) case var nonNullable?) {
        if (this.f10() case var $1?) {
          if ([nonNullable, $1] case var $) {
            return ("<dart::type::nullable>", $);
          }
        }
      }
      this._recover(_mark);
      if (this.apply(this.rm) case var $?) {
        return ("<dart::type::nullable>", $);
      }
    }
  }

  /// `global::dart::type::nonNullable`
  Object? rm() {
    if (this._mark() case var _mark) {
      if (this.apply(this.rp) case var $?) {
        return ("<dart::type::nonNullable>", $);
      }
      this._recover(_mark);
      if (this.apply(this.rn) case var $?) {
        return ("<dart::type::nonNullable>", $);
      }
      this._recover(_mark);
      if (this.apply(this.rr) case var $?) {
        return ("<dart::type::nonNullable>", $);
      }
    }
  }

  /// `global::dart::type::record`
  Object? rn() {
    if (this._mark() case var _mark) {
      if (this.fx() case var $0?) {
        if (this.apply(this.ru) case var positional?) {
          if (this.f13() case var $2?) {
            if (this.apply(this.rt) case var named?) {
              if (this.fw() case var $4?) {
                if ([$0, positional, $2, named, $4] case var $) {
                  return ("<dart::type::record>", $);
                }
              }
            }
          }
        }
      }
      this._recover(_mark);
      if (this.fx() case var $0?) {
        if (this.apply(this.ru) case var positional?) {
          if (this.f13() case var $2) {
            if (this.fw() case var $3?) {
              if ([$0, positional, $2, $3] case var $) {
                return ("<dart::type::record>", $);
              }
            }
          }
        }
      }
      this._recover(_mark);
      if (this.fx() case var $0?) {
        if (this.apply(this.rt) case var named?) {
          if (this.fw() case var $2?) {
            if ([$0, named, $2] case var $) {
              return ("<dart::type::record>", $);
            }
          }
        }
      }
      this._recover(_mark);
      if (this.fx() case var $0?) {
        if (this.fw() case var $1?) {
          if ([$0, $1] case var $) {
            return ("<dart::type::record>", $);
          }
        }
      }
    }
  }

  /// `global::dart::type::fn::parameters`
  Object? ro() {
    if (this._mark() case var _mark) {
      if (this.fx() case var $0?) {
        if (this.apply(this.ru) case var positional?) {
          if (this.f13() case var $2?) {
            if (this.apply(this.rt) case var named?) {
              if (this.fw() case var $4?) {
                if ([$0, positional, $2, named, $4] case var $) {
                  return ("<dart::type::fn::parameters>", $);
                }
              }
            }
          }
        }
      }
      this._recover(_mark);
      if (this.fx() case var $0?) {
        if (this.apply(this.ru) case var positional?) {
          if (this.f13() case var $2?) {
            if (this.apply(this.rs) case var optional?) {
              if (this.fw() case var $4?) {
                if ([$0, positional, $2, optional, $4] case var $) {
                  return ("<dart::type::fn::parameters>", $);
                }
              }
            }
          }
        }
      }
      this._recover(_mark);
      if (this.fx() case var $0?) {
        if (this.apply(this.ru) case var positional?) {
          if (this.f13() case var $2) {
            if (this.fw() case var $3?) {
              if ([$0, positional, $2, $3] case var $) {
                return ("<dart::type::fn::parameters>", $);
              }
            }
          }
        }
      }
      this._recover(_mark);
      if (this.fx() case var $0?) {
        if (this.apply(this.rt) case var named?) {
          if (this.fw() case var $2?) {
            if ([$0, named, $2] case var $) {
              return ("<dart::type::fn::parameters>", $);
            }
          }
        }
      }
      this._recover(_mark);
      if (this.fx() case var $0?) {
        if (this.apply(this.rs) case var optional?) {
          if (this.fw() case var $2?) {
            if ([$0, optional, $2] case var $) {
              return ("<dart::type::fn::parameters>", $);
            }
          }
        }
      }
      this._recover(_mark);
      if (this.fx() case var $0?) {
        if (this.fw() case var $1?) {
          if ([$0, $1] case var $) {
            return ("<dart::type::fn::parameters>", $);
          }
        }
      }
    }
  }

  /// `global::dart::type::generic`
  Object? rp() {
    if (this.apply(this.rr) case var base?) {
      if (this.f2b() case var $1?) {
        if (this.apply(this.rq) case var arguments?) {
          if (this.f2c() case var $3?) {
            if ([base, $1, arguments, $3] case var $) {
              return ("<dart::type::generic>", $);
            }
          }
        }
      }
    }
  }

  /// `global::dart::type::arguments`
  Object? rq() {
    if (this.apply(this.rk) case var _0?) {
      if ([_0] case (var $ && var _l1)) {
        for (;;) {
          if (this._mark() case var _mark) {
            if (this.f13() case _?) {
              if (this.apply(this.rk) case var _0?) {
                _l1.add(_0);
                continue;
              }
            }
            this._recover(_mark);
            break;
          }
        }
        return ("<dart::type::arguments>", $);
      }
    }
  }

  /// `global::dart::type::base`
  Object? rr() {
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
        return ("<dart::type::base>", $);
      }
    }
  }

  /// `global::dart::type::parameters::optional`
  Object? rs() {
    if (this.f2d() case var $0?) {
      if (this.apply(this.ru) case var $1?) {
        if (this.f13() case var $2) {
          if (this.f2e() case var $3?) {
            if ([$0, $1, $2, $3] case var $) {
              return ("<dart::type::parameters::optional>", $);
            }
          }
        }
      }
    }
  }

  /// `global::dart::type::parameters::named`
  Object? rt() {
    if (this.fv() case var $0?) {
      if (this.apply(this.rv) case var $1?) {
        if (this.f13() case var $2) {
          if (this.fu() case var $3?) {
            if ([$0, $1, $2, $3] case var $) {
              return ("<dart::type::parameters::named>", $);
            }
          }
        }
      }
    }
  }

  /// `global::dart::type::fields::positional`
  Object? ru() {
    if (this.apply(this.rw) case var _0?) {
      if ([_0] case (var $ && var _l1)) {
        for (;;) {
          if (this._mark() case var _mark) {
            if (this.f13() case _?) {
              if (this.apply(this.rw) case var _0?) {
                _l1.add(_0);
                continue;
              }
            }
            this._recover(_mark);
            break;
          }
        }
        return ("<dart::type::fields::positional>", $);
      }
    }
  }

  /// `global::dart::type::fields::named`
  Object? rv() {
    if (this.apply(this.rx) case var _0?) {
      if ([_0] case (var $ && var _l1)) {
        for (;;) {
          if (this._mark() case var _mark) {
            if (this.f13() case _?) {
              if (this.apply(this.rx) case var _0?) {
                _l1.add(_0);
                continue;
              }
            }
            this._recover(_mark);
            break;
          }
        }
        return ("<dart::type::fields::named>", $);
      }
    }
  }

  /// `global::dart::type::field::positional`
  Object? rw() {
    if (this.apply(this.rk) case var $0?) {
      if (this.apply(this.ry) case var $1?) {
        if (this.f9() case var $2) {
          if ([$0, $1, $2] case var $) {
            return ("<dart::type::field::positional>", $);
          }
        }
      }
    }
  }

  /// `global::dart::type::field::named`
  Object? rx() {
    if (this.apply(this.rk) case var $0?) {
      if (this.apply(this.ry) case var $1?) {
        if (this.f9() case var $2?) {
          if ([$0, $1, $2] case var $) {
            return ("<dart::type::field::named>", $);
          }
        }
      }
    }
  }

  /// `global::_`
  Object? ry() {
    if (this.matchPattern(_regexp.$4) case var $?) {
      return ("<_>", $);
    }
  }

  static final _regexp = (
    RegExp("[a-zA-Z_\$][a-zA-Z0-9_\$]*"),
    RegExp("\\d"),
    RegExp("\\n"),
    RegExp("((\\s+)|(\\/{2}((?!((\\r?\\n)|(\$))).)*(?=(\\r?\\n)|(\$)))|((\\/\\*((?!\\*\\/).)*\\*\\/)))*"),
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
    "-",
    "|>",
    "@",
    "<~",
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
    "E",
    "e",
    "^",
    "ε",
    "Function",
  );
}
