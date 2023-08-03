// ignore_for_file: always_declare_return_types, always_put_control_body_on_new_line, always_specify_types, avoid_escaping_inner_quotes, avoid_redundant_argument_values, annotate_overrides, body_might_complete_normally_nullable, constant_pattern_never_matches_value_type, curly_braces_in_flow_control_structures, dead_code, directives_ordering, duplicate_ignore, inference_failure_on_function_return_type, constant_identifier_names, prefer_function_declarations_over_variables, prefer_interpolation_to_compose_strings, prefer_is_empty, no_leading_underscores_for_local_identifiers, non_constant_identifier_names, unnecessary_null_check_pattern, unnecessary_brace_in_string_interps, unnecessary_string_interpolations, unnecessary_this, unused_element, unused_import, prefer_double_quotes, unused_local_variable, unreachable_from_main, use_raw_strings, type_annotate_public_apis

// imports
// ignore_for_file: collection_methods_unrelated_type

import "dart:collection";
import "dart:math" as math;
// PREAMBLE
import"package:parser_peg/src/node.dart";
import"package:parser_peg/src/generator.dart";
import"package:parser_peg/src/statement.dart";

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
    if (pattern.matchAsPrefix(buffer, pos) case Match(:int start, :int end)) {
      this.pos = end;
      return buffer.substring(start, end);
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
    this._memo.clear();
    this._lrStack.clear();
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


  /// `global::literal::regexp`
  String? f0() {
    if (this.matchPattern(_string.$1) case _?) {
      if (this.f2b() case var $1?) {
        if (this.matchPattern(_string.$1) case _?) {
          return $1;
        }
      }
    }
  }

  /// `global::literal::string`
  String? f1() {
    if (this.f1g() case _?) {
      if (this.f2k() case var $1?) {
        if (this.f1g() case _?) {
          return $1;
        }
      }
    }
  }

  /// `global::literal::range`
  Node? f2() {
    if (this.f1g() case _?) {
      if (this.f3() case var $1?) {
        if (this.f1g() case _?) {
          return $1;
        }
      }
    }
  }

  /// `global::literal::range::main`
  Node? f3() {
    if (this.fw() case _?) {
      if (this.f4() case var _0?) {
        if ([_0] case (var elements && var _loop2)) {
          for (;;) {
            if (this.pos case var mark) {
              if (this.f1g() case _?) {
                if (this.f4() case var _0?) {
                  _loop2.add(_0);
                  continue;
                }
              }
              this.pos = mark;
              break;
            }
          }
          if (this.fv() case _?) {
            return RangeNode(elements.reduce((a, b) => a.union(b)));
          }
        }
      }
    }
  }

  /// `global::literal::range::element`
  Set<(int, int)>? f4() {
    if (this.pos case var mark) {
      if (this.f5() case var $?) {
        return $;
      }
      this.pos = mark;
      if (this.f6() case var l?) {
        if (this.matchPattern(_string.$2) case _?) {
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
  }

  /// `global::literal::range::escape`
  Set<(int, int)>? f5() {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$4) case var $0?) {
        if (this.matchPattern(_string.$3) case var $1?) {
          return {(48, 57)};
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$4) case var $0?) {
        if (this.matchPattern(_string.$5) case var $1?) {
          return {(64 + 1, 64 + 26), (96 + 1, 96 + 26)};
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$4) case var $0?) {
        if (this.matchPattern(_string.$6) case var $1?) {
          return {(9, 13), (32, 32)};
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$4) case var $0?) {
        if (this.matchPattern(_string.$7) case var $1?) {
          return {(0, 47), (58, 65535)};
        }
      }
    }
  }

  /// `global::literal::range::atom`
  String? f6() {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$4) case _?) {
        if (pos < buffer.length) {
          if (buffer[pos] case var $1) {
            pos++;
            return $1;
          }
        }
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.matchPattern(_string.$8) case (null)) {
          this.pos = mark;
          if (pos < buffer.length) {
            if (buffer[pos] case var $1) {
              pos++;
              return $1;
            }
          }
        }
      }
    }
  }

  /// `global::literal::raw`
  String? f7() {
    if (this.matchPattern(_string.$9) case _?) {
      if (this.pos case var mark) {
        if (this.f2l() case var _0) {
          if ([if (_0 case var _0?) _0] case (var inner && var _loop2)) {
            if (_loop2.isNotEmpty) {
              for (;;) {
                if (this.pos case var mark) {
                  if (this.f2l() case var _0?) {
                    _loop2.add(_0);
                    continue;
                  }
                  this.pos = mark;
                  break;
                }
              }
            } else {
              this.pos = mark;
            }
            if (this.matchPattern(_string.$9) case _?) {
              return inner.join();
            }
          }
        }
      }
    }
  }

  /// `global::type::fields::positional`
  String? f8() {
    if (this.fa() case var _0?) {
      if ([_0] case (var $ && var _loop2)) {
        for (;;) {
          if (this.pos case var mark) {
            if (this.f19() case _?) {
              if (this.fa() case var _0?) {
                _loop2.add(_0);
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

  /// `global::type::fields::named`
  String? f9() {
    if (this.fb() case var _0?) {
      if ([_0] case (var $ && var _loop2)) {
        for (;;) {
          if (this.pos case var mark) {
            if (this.f19() case _?) {
              if (this.fb() case var _0?) {
                _loop2.add(_0);
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

  /// `global::type::field::positional`
  String? fa() {
    if (this.apply(this.rq) case var $0?) {
      if (this.f1g() case var $1?) {
        if (this.fc() case var $2) {
          if (($0, $1, $2) case var $) {
            return "${$0} ${$2 ?? ""}".trimRight();
          }
        }
      }
    }
  }

  /// `global::type::field::named`
  String? fb() {
    if (this.apply(this.rq) case var $0?) {
      if (this.f1g() case var $1?) {
        if (this.fc() case var $2?) {
          if (($0, $1, $2) case var $) {
            return "${$0} ${$2}";
          }
        }
      }
    }
  }

  /// `global::identifier`
  String? fc() {
    if (this.matchRange(_range.$2) case var $0?) {
      if (this.pos case var mark) {
        if (this.matchRange(_range.$1) case var _0) {
          if ([if (_0 case var _0?) _0] case (var $1 && var _loop2)) {
            if (_loop2.isNotEmpty) {
              for (;;) {
                if (this.pos case var mark) {
                  if (this.matchRange(_range.$1) case var _0?) {
                    _loop2.add(_0);
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

  /// `global::raw`
  String? fd() {
    if (this.matchPattern(_string.$9) case _?) {
      if (this.pos case var mark) {
        if (this.f2m() case var _0) {
          if ([if (_0 case var _0?) _0] case (var inner && var _loop2)) {
            if (_loop2.isNotEmpty) {
              for (;;) {
                if (this.pos case var mark) {
                  if (this.f2m() case var _0?) {
                    _loop2.add(_0);
                    continue;
                  }
                  this.pos = mark;
                  break;
                }
              }
            } else {
              this.pos = mark;
            }
            if (this.matchPattern(_string.$9) case _?) {
              return inner.join();
            }
          }
        }
      }
    }
  }

  /// `global::number`
  int? fe() {
    if (matchPattern(_regexp.$1) case var _0?) {
      if ([_0] case (var $ && var _loop2)) {
        for (;;) {
          if (this.pos case var mark) {
            if (matchPattern(_regexp.$1) case var _0?) {
              _loop2.add(_0);
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

  /// `global::kw::decorator::rule`
  String? ff() {
    if (this.f1g() case _?) {
      if (this.matchPattern(_string.$10) case var $1?) {
        if (this.f1g() case _?) {
          return $1;
        }
      }
    }
  }

  /// `global::kw::decorator::fragment`
  String? fg() {
    if (this.f1g() case _?) {
      if (this.matchPattern(_string.$11) case var $1?) {
        if (this.f1g() case _?) {
          return $1;
        }
      }
    }
  }

  /// `global::kw::decorator::inline`
  String? fh() {
    if (this.f1g() case _?) {
      if (this.matchPattern(_string.$12) case var $1?) {
        if (this.f1g() case _?) {
          return $1;
        }
      }
    }
  }

  /// `global::kw::start`
  String? fi() {
    if (this.f1g() case _?) {
      if (this.matchPattern(_string.$13) case var $1?) {
        if (this.f1g() case _?) {
          return $1;
        }
      }
    }
  }

  /// `global::kw::end`
  String? fj() {
    if (this.f1g() case _?) {
      if (this.matchPattern(_string.$14) case var $1?) {
        if (this.f1g() case _?) {
          return $1;
        }
      }
    }
  }

  /// `global::kw::epsilon`
  String? fk() {
    if (this.f1g() case _?) {
      if (this.matchPattern(_string.$15) case var $1?) {
        if (this.f1g() case _?) {
          return $1;
        }
      }
    }
  }

  /// `global::kw::any`
  String? fl() {
    if (this.f1g() case _?) {
      if (this.matchPattern(_string.$16) case var $1?) {
        if (this.f1g() case _?) {
          return $1;
        }
      }
    }
  }

  /// `global::kw::var`
  String? fm() {
    if (this.f1g() case _?) {
      if (this.matchPattern(_string.$17) case var $1?) {
        if (this.f1g() case _?) {
          return $1;
        }
      }
    }
  }

  /// `global::mac::sep`
  String? fn() {
    if (this.f1g() case _?) {
      if (this.matchPattern(_string.$18) case var $1?) {
        if (this.f1g() case _?) {
          return $1;
        }
      }
    }
  }

  /// `global::regexEscape::backslash`
  String? fo() {
    if (this.f1g() case _?) {
      if (this.f2n() case var $1?) {
        if (this.f1g() case _?) {
          return $1;
        }
      }
    }
  }

  /// `global::regexEscape::digit`
  String? fp() {
    if (this.f1g() case _?) {
      if (this.f2o() case var $1?) {
        if (this.f1g() case _?) {
          return $1;
        }
      }
    }
  }

  /// `global::regexEscape::space`
  String? fq() {
    if (this.f1g() case _?) {
      if (this.f2p() case var $1?) {
        if (this.f1g() case _?) {
          return $1;
        }
      }
    }
  }

  /// `global::..`
  String? fr() {
    if (this.f1g() case _?) {
      if (this.matchPattern(_string.$19) case var $1?) {
        if (this.f1g() case _?) {
          return $1;
        }
      }
    }
  }

  /// `global::@`
  String? fs() {
    if (this.f1g() case _?) {
      if (this.matchPattern(_string.$20) case var $1?) {
        if (this.f1g() case _?) {
          return $1;
        }
      }
    }
  }

  /// `global::<`
  String? ft() {
    if (this.f1g() case _?) {
      if (this.matchPattern(_string.$21) case var $1?) {
        if (this.f1g() case _?) {
          return $1;
        }
      }
    }
  }

  /// `global::>`
  String? fu() {
    if (this.f1g() case _?) {
      if (this.matchPattern(_string.$22) case var $1?) {
        if (this.f1g() case _?) {
          return $1;
        }
      }
    }
  }

  /// `global::]`
  String? fv() {
    if (this.f1g() case _?) {
      if (this.matchPattern(_string.$8) case var $1?) {
        if (this.f1g() case _?) {
          return $1;
        }
      }
    }
  }

  /// `global::[`
  String? fw() {
    if (this.f1g() case _?) {
      if (this.matchPattern(_string.$23) case var $1?) {
        if (this.f1g() case _?) {
          return $1;
        }
      }
    }
  }

  /// `global::}`
  String? fx() {
    if (this.f1g() case _?) {
      if (this.matchPattern(_string.$24) case var $1?) {
        if (this.f1g() case _?) {
          return $1;
        }
      }
    }
  }

  /// `global::{`
  String? fy() {
    if (this.f1g() case _?) {
      if (this.matchPattern(_string.$25) case var $1?) {
        if (this.f1g() case _?) {
          return $1;
        }
      }
    }
  }

  /// `global::)`
  String? fz() {
    if (this.f1g() case _?) {
      if (this.matchPattern(_string.$26) case var $1?) {
        if (this.f1g() case _?) {
          return $1;
        }
      }
    }
  }

  /// `global::(`
  String? f10() {
    if (this.f1g() case _?) {
      if (this.matchPattern(_string.$27) case var $1?) {
        if (this.f1g() case _?) {
          return $1;
        }
      }
    }
  }

  /// `global::;`
  String? f11() {
    if (this.f1g() case _?) {
      if (this.matchPattern(_string.$28) case var $1?) {
        if (this.f1g() case _?) {
          return $1;
        }
      }
    }
  }

  /// `global::=`
  String? f12() {
    if (this.f1g() case _?) {
      if (this.matchPattern(_string.$29) case var $1?) {
        if (this.f1g() case _?) {
          return $1;
        }
      }
    }
  }

  /// `global::?`
  String? f13() {
    if (this.f1g() case _?) {
      if (this.matchPattern(_string.$30) case var $1?) {
        if (this.f1g() case _?) {
          return $1;
        }
      }
    }
  }

  /// `global::!`
  String? f14() {
    if (this.f1g() case _?) {
      if (this.matchPattern(_string.$31) case var $1?) {
        if (this.f1g() case _?) {
          return $1;
        }
      }
    }
  }

  /// `global::~`
  String? f15() {
    if (this.f1g() case _?) {
      if (this.matchPattern(_string.$32) case var $1?) {
        if (this.f1g() case _?) {
          return $1;
        }
      }
    }
  }

  /// `global::&`
  String? f16() {
    if (this.f1g() case _?) {
      if (this.matchPattern(_string.$33) case var $1?) {
        if (this.f1g() case _?) {
          return $1;
        }
      }
    }
  }

  /// `global::*`
  String? f17() {
    if (this.f1g() case _?) {
      if (this.matchPattern(_string.$34) case var $1?) {
        if (this.f1g() case _?) {
          return $1;
        }
      }
    }
  }

  /// `global::+`
  String? f18() {
    if (this.f1g() case _?) {
      if (this.matchPattern(_string.$35) case var $1?) {
        if (this.f1g() case _?) {
          return $1;
        }
      }
    }
  }

  /// `global::,`
  String? f19() {
    if (this.f1g() case _?) {
      if (this.matchPattern(_string.$36) case var $1?) {
        if (this.f1g() case _?) {
          return $1;
        }
      }
    }
  }

  /// `global:::`
  String? f1a() {
    if (this.f1g() case _?) {
      if (this.matchPattern(_string.$37) case var $1?) {
        if (this.f1g() case _?) {
          return $1;
        }
      }
    }
  }

  /// `global::|`
  String? f1b() {
    if (this.f1g() case _?) {
      if (this.matchPattern(_string.$38) case var $1?) {
        if (this.f1g() case _?) {
          return $1;
        }
      }
    }
  }

  /// `global::DOT`
  String? f1c() {
    if (this.f1g() case _?) {
      if (this.matchPattern(_string.$39) case var $1?) {
        if (this.f1g() case _?) {
          return $1;
        }
      }
    }
  }

  /// `global::EPSILON`
  String? f1d() {
    if (this.f1g() case _?) {
      if (this.matchPattern(_string.$40) case var $1?) {
        if (this.f1g() case _?) {
          return $1;
        }
      }
    }
  }

  /// `global::CARET`
  String? f1e() {
    if (this.f1g() case _?) {
      if (this.matchPattern(_string.$41) case var $1?) {
        if (this.f1g() case _?) {
          return $1;
        }
      }
    }
  }

  /// `global::DOLLAR`
  String? f1f() {
    if (this.f1g() case _?) {
      if (this.matchPattern(_string.$42) case var $1?) {
        if (this.f1g() case _?) {
          return $1;
        }
      }
    }
  }

  /// `global::_`
  String? f1g() {
    if (matchPattern(_regexp.$2) case var $?) {
      return "";
    }
  }

  /// `ROOT`
  ParserGenerator? f1h() {
    if (this.apply(this.r0) case var $?) {
      return $;
    }
  }

  /// `global::body`
  Node? f1i() {
    if (this.f12() case _?) {
      if (this.apply(this.r8) case var choice?) {
        if (this.f11() case _?) {
          return choice;
        }
      }
    }
  }

  /// `fragment0`
  late final f1j = () {
    if (this.fc() case var $0?) {
      if (this.matchPattern(_string.$43) case _?) {
        return $0;
      }
    }
  };

  /// `fragment1`
  late final f1k = () {
    if (this.fc() case var $0?) {
      if (this.matchPattern(_string.$43) case _?) {
        return $0;
      }
    }
  };

  /// `fragment2`
  late final f1l = () {
    if (this.fc() case var $0?) {
      if (this.matchPattern(_string.$43) case _?) {
        return $0;
      }
    }
  };

  /// `fragment3`
  late final f1m = () {
    if (this.pos case var mark) {
      if (this.f1l() case var _0) {
        if ([if (_0 case var _0?) _0] case (var $0 && var _loop2)) {
          if (_loop2.isNotEmpty) {
            for (;;) {
              if (this.pos case var mark) {
                if (this.f1l() case var _0?) {
                  _loop2.add(_0);
                  continue;
                }
                this.pos = mark;
                break;
              }
            }
          } else {
            this.pos = mark;
          }
          if (this.fc() case var $1?) {
            if (($0, $1) case var $) {
              return $0.isEmpty ? $1 :"${$0.join("::")}::${$1}";
            }
          }
        }
      }
    }
  };

  /// `fragment4`
  late final f1n = () {
    if (this.fc() case var $0?) {
      if (this.matchPattern(_string.$43) case _?) {
        return $0;
      }
    }
  };

  /// `fragment5`
  late final f1o = () {
    if (this.pos case var mark) {
      if (this.f1n() case var _0) {
        if ([if (_0 case var _0?) _0] case (var $0 && var _loop2)) {
          if (_loop2.isNotEmpty) {
            for (;;) {
              if (this.pos case var mark) {
                if (this.f1n() case var _0?) {
                  _loop2.add(_0);
                  continue;
                }
                this.pos = mark;
                break;
              }
            }
          } else {
            this.pos = mark;
          }
          if (this.fc() case var $1?) {
            if (($0, $1) case var $) {
              return $0.isEmpty ? $1 :"${$0.join("::")}::${$1}";
            }
          }
        }
      }
    }
  };

  /// `fragment6`
  late final f1p = () {
    if (this.fc() case var $0?) {
      if (this.matchPattern(_string.$43) case _?) {
        return $0;
      }
    }
  };

  /// `fragment7`
  late final f1q = () {
    if (this.pos case var mark) {
      if (this.f1p() case var _0) {
        if ([if (_0 case var _0?) _0] case (var $0 && var _loop2)) {
          if (_loop2.isNotEmpty) {
            for (;;) {
              if (this.pos case var mark) {
                if (this.f1p() case var _0?) {
                  _loop2.add(_0);
                  continue;
                }
                this.pos = mark;
                break;
              }
            }
          } else {
            this.pos = mark;
          }
          if (this.fc() case var $1?) {
            if (($0, $1) case var $) {
              return $0.isEmpty ? $1 :"${$0.join("::")}::${$1}";
            }
          }
        }
      }
    }
  };

  /// `fragment8`
  late final f1r = () {
    if (this.fc() case var $0?) {
      if (this.matchPattern(_string.$43) case _?) {
        return $0;
      }
    }
  };

  /// `fragment9`
  late final f1s = () {
    if (this.pos case var mark) {
      if (this.f1r() case var _0) {
        if ([if (_0 case var _0?) _0] case (var $0 && var _loop2)) {
          if (_loop2.isNotEmpty) {
            for (;;) {
              if (this.pos case var mark) {
                if (this.f1r() case var _0?) {
                  _loop2.add(_0);
                  continue;
                }
                this.pos = mark;
                break;
              }
            }
          } else {
            this.pos = mark;
          }
          if (this.fc() case var $1?) {
            if (($0, $1) case var $) {
              return $0.isEmpty ? $1 :"${$0.join("::")}::${$1}";
            }
          }
        }
      }
    }
  };

  /// `fragment10`
  late final f1t = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$9) case (null)) {
        this.pos = mark;
        if (pos < buffer.length) {
          if (buffer[pos] case var $1) {
            pos++;
            return $1;
          }
        }
      }
    }
  };

  /// `fragment11`
  late final f1u = () {
    if (this.pos case var mark) {
      if (this.apply(this.rk) case var $?) {
        return $;
      }
      this.pos = mark;
      if (this.matchPattern(_string.$25) case var $0?) {
        if (this.apply(this.rj)! case var $1) {
          if (this.matchPattern(_string.$24) case var $2?) {
            if ($1 case var $) {
              return "{"+ $ +"}";
            }
          }
        }
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.matchPattern(_string.$25) case (null)) {
          this.pos = mark;
          if (this.pos case var mark) {
            if (this.matchPattern(_string.$24) case (null)) {
              this.pos = mark;
              if (pos < buffer.length) {
                if (buffer[pos] case var $2) {
                  pos++;
                  return $2;
                }
              }
            }
          }
        }
      }
    }
  };

  /// `fragment12`
  late final f1v = () {
    if (this.pos case var from) {
      if (this.apply(this.rm) case var $?) {
        if (this.pos case var to) {
          return buffer.substring(from, to);
        }
      }
    }
  };

  /// `fragment13`
  late final f1w = () {
    if (this.pos case var from) {
      if (this.fc() case var $?) {
        if (this.pos case var to) {
          return this.buffer.substring(from, to);
        }
      }
    }
  };

  /// `fragment14`
  late final f1x = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$44) case (null)) {
        this.pos = mark;
        if (pos < buffer.length) {
          if (buffer[pos] case var $1) {
            pos++;
            return $1;
          }
        }
      }
    }
  };

  /// `fragment15`
  late final f1y = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$45) case (null)) {
        this.pos = mark;
        if (pos < buffer.length) {
          if (buffer[pos] case var $1) {
            pos++;
            return $1;
          }
        }
      }
    }
  };

  /// `fragment16`
  late final f1z = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$46) case (null)) {
        this.pos = mark;
        if (pos < buffer.length) {
          if (buffer[pos] case var $1) {
            pos++;
            return $1;
          }
        }
      }
    }
  };

  /// `fragment17`
  late final f20 = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$47) case (null)) {
        this.pos = mark;
        if (pos < buffer.length) {
          if (buffer[pos] case var $1) {
            pos++;
            return $1;
          }
        }
      }
    }
  };

  /// `fragment18`
  late final f21 = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$4) case _?) {
        if (pos < buffer.length) {
          if (buffer[pos] case var $1) {
            pos++;
            return $1;
          }
        }
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.matchPattern(_string.$42) case var $0?) {
          this.pos = mark;
          if (this.apply(this.rn) case var $1?) {
            return ($0, $1);
          }
        }
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.matchPattern(_string.$44) case (null)) {
          this.pos = mark;
          if (pos < buffer.length) {
            if (buffer[pos] case var $1) {
              pos++;
              return $1;
            }
          }
        }
      }
    }
  };

  /// `fragment19`
  late final f22 = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$4) case _?) {
        if (pos < buffer.length) {
          if (buffer[pos] case var $1) {
            pos++;
            return $1;
          }
        }
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.matchPattern(_string.$42) case var $0?) {
          this.pos = mark;
          if (this.apply(this.rn) case var $1?) {
            return ($0, $1);
          }
        }
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.matchPattern(_string.$45) case (null)) {
          this.pos = mark;
          if (pos < buffer.length) {
            if (buffer[pos] case var $1) {
              pos++;
              return $1;
            }
          }
        }
      }
    }
  };

  /// `fragment20`
  late final f23 = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$4) case _?) {
        if (pos < buffer.length) {
          if (buffer[pos] case var $1) {
            pos++;
            return $1;
          }
        }
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.matchPattern(_string.$42) case var $0?) {
          this.pos = mark;
          if (this.apply(this.rn) case var $1?) {
            return ($0, $1);
          }
        }
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.matchPattern(_string.$46) case (null)) {
          this.pos = mark;
          if (pos < buffer.length) {
            if (buffer[pos] case var $1) {
              pos++;
              return $1;
            }
          }
        }
      }
    }
  };

  /// `fragment21`
  late final f24 = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$4) case _?) {
        if (pos < buffer.length) {
          if (buffer[pos] case var $1) {
            pos++;
            return $1;
          }
        }
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.matchPattern(_string.$42) case var $0?) {
          this.pos = mark;
          if (this.apply(this.rn) case var $1?) {
            return ($0, $1);
          }
        }
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.matchPattern(_string.$47) case (null)) {
          this.pos = mark;
          if (pos < buffer.length) {
            if (buffer[pos] case var $1) {
              pos++;
              return $1;
            }
          }
        }
      }
    }
  };

  /// `fragment22`
  late final f25 = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$25) case _?) {
        if (this.apply(this.ro)! case var $1) {
          if (this.matchPattern(_string.$24) case _?) {
            return $1;
          }
        }
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.matchPattern(_string.$25) case (null)) {
          this.pos = mark;
          if (this.pos case var mark) {
            if (this.matchPattern(_string.$24) case (null)) {
              this.pos = mark;
              if (pos < buffer.length) {
                if (buffer[pos] case var $2) {
                  pos++;
                  return $2;
                }
              }
            }
          }
        }
      }
    }
  };

  /// `fragment23`
  late final f26 = () {
    if (this.pos case var mark) {
      if (this.apply(this.rt) case var $?) {
        return $;
      }
      this.pos = mark;
      if (this.apply(this.rs) case var $?) {
        return $;
      }
      this.pos = mark;
      if (this.apply(this.rv) case var $?) {
        return $;
      }
    }
  };

  /// `fragment24`
  late final f27 = () {
    if (this.fy() case _?) {
      if (this.f9() case var $1?) {
        if (this.fx() case _?) {
          return $1;
        }
      }
    }
  };

  /// `fragment25`
  late final f28 = () {
    if (this.fy() case _?) {
      if (this.f9() case var $1?) {
        if (this.fx() case _?) {
          return $1;
        }
      }
    }
  };

  /// `fragment26`
  late final f29 = () {
    if (this.f19() case _?) {
      if (this.fy() case _?) {
        if (this.f9() case var $2?) {
          if (this.fx() case _?) {
            return $2;
          }
        }
      }
    }
  };

  /// `fragment27`
  late final f2a = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$4) case var $0?) {
        if (pos < buffer.length) {
          if (buffer[pos] case var $1) {
            pos++;
            if ($1 case var $) {
              return r"\"+ $;
            }
          }
        }
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.matchPattern(_string.$1) case (null)) {
          this.pos = mark;
          if (pos < buffer.length) {
            if (buffer[pos] case var $1) {
              pos++;
              return $1;
            }
          }
        }
      }
    }
  };

  /// `fragment28`
  late final f2b = () {
    if (this.f2a() case var _0?) {
      if ([_0] case (var $ && var _loop2)) {
        for (;;) {
          if (this.pos case var mark) {
            if (this.f2a() case var _0?) {
              _loop2.add(_0);
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

  /// `fragment29`
  late final f2c = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$44) case (null)) {
        this.pos = mark;
        if (pos < buffer.length) {
          if (buffer[pos] case var $1) {
            pos++;
            return $1;
          }
        }
      }
    }
  };

  /// `fragment30`
  late final f2d = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$45) case (null)) {
        this.pos = mark;
        if (pos < buffer.length) {
          if (buffer[pos] case var $1) {
            pos++;
            return $1;
          }
        }
      }
    }
  };

  /// `fragment31`
  late final f2e = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$46) case (null)) {
        this.pos = mark;
        if (pos < buffer.length) {
          if (buffer[pos] case var $1) {
            pos++;
            return $1;
          }
        }
      }
    }
  };

  /// `fragment32`
  late final f2f = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$47) case (null)) {
        this.pos = mark;
        if (pos < buffer.length) {
          if (buffer[pos] case var $1) {
            pos++;
            return $1;
          }
        }
      }
    }
  };

  /// `fragment33`
  late final f2g = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$4) case _?) {
        if (pos < buffer.length) {
          if (buffer[pos] case var $1) {
            pos++;
            return $1;
          }
        }
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.matchPattern(_string.$44) case (null)) {
          this.pos = mark;
          if (pos < buffer.length) {
            if (buffer[pos] case var $1) {
              pos++;
              return $1;
            }
          }
        }
      }
    }
  };

  /// `fragment34`
  late final f2h = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$4) case _?) {
        if (pos < buffer.length) {
          if (buffer[pos] case var $1) {
            pos++;
            return $1;
          }
        }
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.matchPattern(_string.$45) case (null)) {
          this.pos = mark;
          if (pos < buffer.length) {
            if (buffer[pos] case var $1) {
              pos++;
              return $1;
            }
          }
        }
      }
    }
  };

  /// `fragment35`
  late final f2i = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$4) case _?) {
        if (pos < buffer.length) {
          if (buffer[pos] case var $1) {
            pos++;
            return $1;
          }
        }
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.matchPattern(_string.$46) case (null)) {
          this.pos = mark;
          if (pos < buffer.length) {
            if (buffer[pos] case var $1) {
              pos++;
              return $1;
            }
          }
        }
      }
    }
  };

  /// `fragment36`
  late final f2j = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$4) case _?) {
        if (pos < buffer.length) {
          if (buffer[pos] case var $1) {
            pos++;
            return $1;
          }
        }
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.matchPattern(_string.$47) case (null)) {
          this.pos = mark;
          if (pos < buffer.length) {
            if (buffer[pos] case var $1) {
              pos++;
              return $1;
            }
          }
        }
      }
    }
  };

  /// `fragment37`
  late final f2k = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$48) case _?) {
        if (this.pos case var mark) {
          if (this.f2c() case var _0) {
            if ([if (_0 case var _0?) _0] case (var body && var _loop2)) {
              if (_loop2.isNotEmpty) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.f2c() case var _0?) {
                      _loop2.add(_0);
                      continue;
                    }
                    this.pos = mark;
                    break;
                  }
                }
              } else {
                this.pos = mark;
              }
              if (this.matchPattern(_string.$44) case _?) {
                return body.join();
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$49) case _?) {
        if (this.pos case var mark) {
          if (this.f2d() case var _2) {
            if ([if (_2 case var _2?) _2] case (var body && var _loop4)) {
              if (_loop4.isNotEmpty) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.f2d() case var _2?) {
                      _loop4.add(_2);
                      continue;
                    }
                    this.pos = mark;
                    break;
                  }
                }
              } else {
                this.pos = mark;
              }
              if (this.matchPattern(_string.$45) case _?) {
                return body.join();
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$50) case _?) {
        if (this.pos case var mark) {
          if (this.f2e() case var _4) {
            if ([if (_4 case var _4?) _4] case (var body && var _loop6)) {
              if (_loop6.isNotEmpty) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.f2e() case var _4?) {
                      _loop6.add(_4);
                      continue;
                    }
                    this.pos = mark;
                    break;
                  }
                }
              } else {
                this.pos = mark;
              }
              if (this.matchPattern(_string.$46) case _?) {
                return body.join();
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$51) case _?) {
        if (this.pos case var mark) {
          if (this.f2f() case var _6) {
            if ([if (_6 case var _6?) _6] case (var body && var _loop8)) {
              if (_loop8.isNotEmpty) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.f2f() case var _6?) {
                      _loop8.add(_6);
                      continue;
                    }
                    this.pos = mark;
                    break;
                  }
                }
              } else {
                this.pos = mark;
              }
              if (this.matchPattern(_string.$47) case _?) {
                return body.join();
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$44) case _?) {
        if (this.pos case var mark) {
          if (this.f2g() case var _8) {
            if ([if (_8 case var _8?) _8] case (var body && var _loop10)) {
              if (_loop10.isNotEmpty) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.f2g() case var _8?) {
                      _loop10.add(_8);
                      continue;
                    }
                    this.pos = mark;
                    break;
                  }
                }
              } else {
                this.pos = mark;
              }
              if (this.matchPattern(_string.$44) case _?) {
                return body.join();
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$45) case _?) {
        if (this.pos case var mark) {
          if (this.f2h() case var _10) {
            if ([if (_10 case var _10?) _10] case (var body && var _loop12)) {
              if (_loop12.isNotEmpty) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.f2h() case var _10?) {
                      _loop12.add(_10);
                      continue;
                    }
                    this.pos = mark;
                    break;
                  }
                }
              } else {
                this.pos = mark;
              }
              if (this.matchPattern(_string.$45) case _?) {
                return body.join();
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$46) case _?) {
        if (this.pos case var mark) {
          if (this.f2i() case var _12) {
            if ([if (_12 case var _12?) _12] case (var body && var _loop14)) {
              if (_loop14.isNotEmpty) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.f2i() case var _12?) {
                      _loop14.add(_12);
                      continue;
                    }
                    this.pos = mark;
                    break;
                  }
                }
              } else {
                this.pos = mark;
              }
              if (this.matchPattern(_string.$46) case _?) {
                return body.join();
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$47) case _?) {
        if (this.pos case var mark) {
          if (this.f2j() case var _14) {
            if ([if (_14 case var _14?) _14] case (var body && var _loop16)) {
              if (_loop16.isNotEmpty) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.f2j() case var _14?) {
                      _loop16.add(_14);
                      continue;
                    }
                    this.pos = mark;
                    break;
                  }
                }
              } else {
                this.pos = mark;
              }
              if (this.matchPattern(_string.$47) case _?) {
                return body.join();
              }
            }
          }
        }
      }
    }
  };

  /// `fragment38`
  late final f2l = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$9) case (null)) {
        this.pos = mark;
        if (pos < buffer.length) {
          if (buffer[pos] case var $1) {
            pos++;
            return $1;
          }
        }
      }
    }
  };

  /// `fragment39`
  late final f2m = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$9) case (null)) {
        this.pos = mark;
        if (pos < buffer.length) {
          if (buffer[pos] case var $1) {
            pos++;
            return $1;
          }
        }
      }
    }
  };

  /// `fragment40`
  late final f2n = () {
    if (this.matchPattern(_string.$4) case var $0?) {
      if (this.matchPattern(_string.$4) case var $1?) {
        if ($1 case var $) {
          return r"\"+ $;
        }
      }
    }
  };

  /// `fragment41`
  late final f2o = () {
    if (this.matchPattern(_string.$4) case var $0?) {
      if (this.matchPattern(_string.$3) case var $1?) {
        if ($1 case var $) {
          return r"\"+ $;
        }
      }
    }
  };

  /// `fragment42`
  late final f2p = () {
    if (this.matchPattern(_string.$4) case var $0?) {
      if (this.matchPattern(_string.$6) case var $1?) {
        if ($1 case var $) {
          return r"\"+ $;
        }
      }
    }
  };

  /// `global::document`
  ParserGenerator? r0() {
    if (this.pos case _ when this.pos <= 0) {
      if (this.apply(this.r1) case var preamble) {
        if (this.apply(this.r2) case var _0?) {
          if ([_0] case (var statements && var _loop2)) {
            for (;;) {
              if (this.pos case var mark) {
                if (this.f1g() case _?) {
                  if (this.apply(this.r2) case var _0?) {
                    _loop2.add(_0);
                    continue;
                  }
                }
                this.pos = mark;
                break;
              }
            }
            if (this.pos case var mark) {
              if (this.f1g() case null) {
                this.pos = mark;
              }
            }
            if (this.pos case _ when this.pos >= this.buffer.length) {
              return ParserGenerator.fromParsed(preamble: preamble, statements: statements);
            }
          }
        }
      }
    }
  }

  /// `global::preamble`
  String? r1() {
    if (this.fy() case _?) {
      if (this.f1g() case _?) {
        if (this.apply(this.ri)! case var code) {
          if (this.f1g() case _?) {
            if (this.fx() case _?) {
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
      if (this.apply(this.r4) case var $?) {
        return $;
      }
      this.pos = mark;
      if (this.apply(this.r6) case var $?) {
        return $;
      }
      this.pos = mark;
      if (this.apply(this.r7) case var $?) {
        return $;
      }
      this.pos = mark;
      if (this.apply(this.r5) case var $?) {
        return $;
      }
    }
  }

  /// `global::name`
  String? r3() {
    if (this.pos case var mark) {
      if (this.pos case var mark) {
        if (this.f1j() case var _0) {
          if ([if (_0 case var _0?) _0] case (var $0 && var _loop2)) {
            if (_loop2.isNotEmpty) {
              for (;;) {
                if (this.pos case var mark) {
                  if (this.f1j() case var _0?) {
                    _loop2.add(_0);
                    continue;
                  }
                  this.pos = mark;
                  break;
                }
              }
            } else {
              this.pos = mark;
            }
            if (this.f7() case var $1?) {
              if (($0, $1) case var $) {
                return $0.isEmpty ? $1 :"${$0.join("::")}::${$1}";
              }
            }
          }
        }
      }

      this.pos = mark;
      if (this.pos case var mark) {
        if (this.f1k() case var _2) {
          if ([if (_2 case var _2?) _2] case (var $0 && var _loop4)) {
            if (_loop4.isNotEmpty) {
              for (;;) {
                if (this.pos case var mark) {
                  if (this.f1k() case var _2?) {
                    _loop4.add(_2);
                    continue;
                  }
                  this.pos = mark;
                  break;
                }
              }
            } else {
              this.pos = mark;
            }
            if (this.fc() case var $1?) {
              if (($0, $1) case var $) {
                return $0.isEmpty ? $1 :"${$0.join("::")}::${$1}";
              }
            }
          }
        }
      }
    }
  }

  /// `global::namespace`
  Statement? r4() {
    if (this.pos case var mark) {
      if (this.fg() case _?) {
        if (this.fc() case var name) {
          if (this.fy() case _?) {
            if (this.apply(this.r2) case var _0?) {
              if ([_0] case (var statements && var _loop2)) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.f1g() case _?) {
                      if (this.apply(this.r2) case var _0?) {
                        _loop2.add(_0);
                        continue;
                      }
                    }
                    this.pos = mark;
                    break;
                  }
                }
                if (this.fx() case _?) {
                  return NamespaceStatement(name, statements, tag: Tag.fragment);
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.ff() case _?) {
        if (this.fc() case var name) {
          if (this.fy() case _?) {
            if (this.apply(this.r2) case var _2?) {
              if ([_2] case (var statements && var _loop4)) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.f1g() case _?) {
                      if (this.apply(this.r2) case var _2?) {
                        _loop4.add(_2);
                        continue;
                      }
                    }
                    this.pos = mark;
                    break;
                  }
                }
                if (this.fx() case _?) {
                  return NamespaceStatement(name, statements, tag: Tag.rule);
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.fh() case _?) {
        if (this.fc() case var name) {
          if (this.fy() case _?) {
            if (this.apply(this.r2) case var _4?) {
              if ([_4] case (var statements && var _loop6)) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.f1g() case _?) {
                      if (this.apply(this.r2) case var _4?) {
                        _loop6.add(_4);
                        continue;
                      }
                    }
                    this.pos = mark;
                    break;
                  }
                }
                if (this.fx() case _?) {
                  return NamespaceStatement(name, statements, tag: Tag.inline);
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.fc() case var name) {
        if (this.fy() case _?) {
          if (this.apply(this.r2) case var _6?) {
            if ([_6] case (var statements && var _loop8)) {
              for (;;) {
                if (this.pos case var mark) {
                  if (this.f1g() case _?) {
                    if (this.apply(this.r2) case var _6?) {
                      _loop8.add(_6);
                      continue;
                    }
                  }
                  this.pos = mark;
                  break;
                }
              }
              if (this.fx() case _?) {
                return NamespaceStatement(name, statements, tag: null);
              }
            }
          }
        }
      }
    }
  }

  /// `global::rule`
  Statement? r5() {
    if (this.pos case var mark) {
      if (this.ff() case var $0) {
        if (this.fm() case _?) {
          if (this.apply(this.r3) case var name?) {
            if (this.f1i() case var body?) {
              return DeclarationStatement(null, name, body, tag: $0 == null ? null : Tag.rule);
            }
          }
        }
      }
      this.pos = mark;
      if (this.ff() case var $0) {
        if (this.apply(this.r3) case var name?) {
          if (this.f1i() case var body?) {
            return DeclarationStatement(null, name, body, tag: $0 == null ? null : Tag.rule);
          }
        }
      }
      this.pos = mark;
      if (this.ff() case var $0) {
        if (this.apply(this.rp) case var type?) {
          if (this.apply(this.r3) case var name?) {
            if (this.f1i() case var body?) {
              return DeclarationStatement(type, name, body, tag: $0 == null ? null : Tag.rule);
            }
          }
        }
      }
      this.pos = mark;
      if (this.ff() case var $0) {
        if (this.apply(this.r3) case var name?) {
          if (this.f1a() case _?) {
            if (this.apply(this.rp) case var type?) {
              if (this.f1i() case var body?) {
                return DeclarationStatement(type, name, body, tag: $0 == null ? null : Tag.rule);
              }
            }
          }
        }
      }
    }
  }

  /// `global::fragment`
  Statement? r6() {
    if (this.pos case var mark) {
      if (this.fg() case _?) {
        if (this.fm() case _?) {
          if (this.apply(this.r3) case var name?) {
            if (this.f1i() case var body?) {
              return DeclarationStatement(null, name, body, tag: Tag.fragment);
            }
          }
        }
      }
      this.pos = mark;
      if (this.fg() case _?) {
        if (this.apply(this.r3) case var name?) {
          if (this.f1i() case var body?) {
            return DeclarationStatement(null, name, body, tag: Tag.fragment);
          }
        }
      }
      this.pos = mark;
      if (this.fg() case _?) {
        if (this.apply(this.rp) case var type?) {
          if (this.apply(this.r3) case var name?) {
            if (this.f1i() case var body?) {
              return DeclarationStatement(type, name, body, tag: Tag.fragment);
            }
          }
        }
      }
      this.pos = mark;
      if (this.fg() case _?) {
        if (this.apply(this.r3) case var name?) {
          if (this.f1a() case _?) {
            if (this.apply(this.rp) case var type?) {
              if (this.f1i() case var body?) {
                return DeclarationStatement(type, name, body, tag: Tag.fragment);
              }
            }
          }
        }
      }
    }
  }

  /// `global::inline`
  Statement? r7() {
    if (this.pos case var mark) {
      if (this.fh() case _?) {
        if (this.fm() case _?) {
          if (this.apply(this.r3) case var name?) {
            if (this.f1i() case var body?) {
              return DeclarationStatement(null, name, body, tag: Tag.inline);
            }
          }
        }
      }
      this.pos = mark;
      if (this.fh() case _?) {
        if (this.apply(this.r3) case var name?) {
          if (this.f1i() case var body?) {
            return DeclarationStatement(null, name, body, tag: Tag.inline);
          }
        }
      }
      this.pos = mark;
      if (this.fh() case _?) {
        if (this.apply(this.rp) case var type?) {
          if (this.apply(this.r3) case var name?) {
            if (this.f1i() case var body?) {
              return DeclarationStatement(type, name, body, tag: Tag.inline);
            }
          }
        }
      }
      this.pos = mark;
      if (this.fh() case _?) {
        if (this.apply(this.r3) case var name?) {
          if (this.f1a() case _?) {
            if (this.apply(this.rp) case var type?) {
              if (this.f1i() case var body?) {
                return DeclarationStatement(type, name, body, tag: Tag.inline);
              }
            }
          }
        }
      }
    }
  }

  /// `global::choice`
  Node? r8() {
    if (this.f1b() case _) {
      if (this.apply(this.r9) case var _0?) {
        if ([_0] case (var options && var _loop2)) {
          for (;;) {
            if (this.pos case var mark) {
              if (this.f1b() case _?) {
                if (this.apply(this.r9) case var _0?) {
                  _loop2.add(_0);
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
  Node? r9() {
    if (this.pos case var mark) {
      if (this.pos case var from) {
        if (this.apply(this.ra) case var sequence?) {
          if (this.fy() case _?) {
            if (this.fx() case _?) {
              if (this.pos case var to) {
                return InlineActionNode(
                        sequence,"this.buffer.substring(from, to)",
                        areIndicesProvided: true,
                      );
              }
            }
          }
        }
      }

      this.pos = mark;
      if (this.pos case var from) {
        if (this.apply(this.ra) case var sequence?) {
          if (this.fy() case _?) {
            if (this.f1g() case _?) {
              if (this.apply(this.ri)! case var code) {
                if (this.f1g() case _?) {
                  if (this.fx() case _?) {
                    if (this.pos case var to) {
                      return InlineActionNode(
                              sequence,
                              code.trimRight(),
                              areIndicesProvided: code.contains(_regexps.from) && code.contains(_regexps.to),
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
        if (this.apply(this.ra) case var sequence?) {
          if (this.f10() case _?) {
            if (this.fz() case _?) {
              if (this.fy() case _?) {
                if (this.f1g() case _?) {
                  if (this.apply(this.ri)! case var code) {
                    if (this.f1g() case _?) {
                      if (this.fx() case _?) {
                        if (this.pos case var to) {
                          return ActionNode(
                                  sequence,
                                  code.trimRight(),
                                  areIndicesProvided: code.contains(_regexps.from) && code.contains(_regexps.to),
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
      if (this.apply(this.ra) case var $?) {
        return $;
      }
    }
  }

  /// `global::sequence`
  Node? ra() {
    if (this.pos case var mark) {
      if (this.apply(this.rb) case var _0?) {
        if ([_0] case (var body && var _loop2)) {
          for (;;) {
            if (this.pos case var mark) {
              if (this.f1g() case _?) {
                if (this.apply(this.rb) case var _0?) {
                  _loop2.add(_0);
                  continue;
                }
              }
              this.pos = mark;
              break;
            }
          }
          if (this.fs() case _?) {
            if (this.fe() case var number?) {
              return body.length == 1 ? body.single : SequenceNode(body, choose: number);
            }
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.rb) case var _2?) {
        if ([_2] case (var $ && var _loop4)) {
          for (;;) {
            if (this.pos case var mark) {
              if (this.f1g() case _?) {
                if (this.apply(this.rb) case var _2?) {
                  _loop4.add(_2);
                  continue;
                }
              }
              this.pos = mark;
              break;
            }
          }
          return $.length == 1 ? $.single : SequenceNode($, choose: null);
        }
      }
    }
  }

  /// `global::dropped`
  Node? rb() {
    if (this.apply(this.rc) case var $?) {
      return $;
    }
  }

  /// `global::labeled`
  Node? rc() {
    if (this.pos case var mark) {
      if (this.fc() case var identifier?) {
        if (this.matchPattern(_string.$37) case _?) {
          if (this.f1g() case _?) {
            if (this.apply(this.rd) case var separated?) {
              return NamedNode(identifier, separated);
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$37) case _?) {
        if (this.f1m() case var id?) {
          if (this.f13() case _?) {
            return switch ((id, id.split("::"))) {
                  (var ref, [..., var name]) => NamedNode(name, OptionalNode(ReferenceNode(ref))),
                  _ => null,
                };
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$37) case _?) {
        if (this.f1o() case var id?) {
          if (this.f17() case _?) {
            return switch ((id, id.split("::"))) {
                  (var ref, [..., var name]) => NamedNode(name, StarNode(ReferenceNode(ref))),
                  _ => null,
                };
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$37) case _?) {
        if (this.f1q() case var id?) {
          if (this.f18() case _?) {
            return switch ((id, id.split("::"))) {
                  (var ref, [..., var name]) => NamedNode(name, PlusNode(ReferenceNode(ref))),
                  _ => null,
                };
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$37) case _?) {
        if (this.f1s() case var id?) {
          return switch ((id, id.split("::"))) {
                (var ref, [..., var name]) => NamedNode(name, ReferenceNode(ref)),
                _ => null,
              };
        }
      }
      this.pos = mark;
      if (this.apply(this.rd) case var $?) {
        return $;
      }
    }
  }

  /// `global::separated`
  Node? rd() {
    if (this.pos case var mark) {
      if (this.fe() case var min?) {
        if (this.fr() case _?) {
          if (this.fe() case var max) {
            if (this.apply(this.rg) case var atom?) {
              return CountedNode(min, max, atom);
            }
          }
        }
      }
      this.pos = mark;
      if (this.fe() case var number?) {
        if (this.apply(this.rg) case var atom?) {
          return CountedNode(number, number, atom);
        }
      }
      this.pos = mark;
      if (this.apply(this.re) case var $?) {
        return $;
      }
    }
  }

  /// `global::postfix`
  Node? re() {
    if (this.pos case var mark) {
      if (this.apply(this.re) case var $0?) {
        if (this.f13() case var $1?) {
          if ($0 case var $) {
            return OptionalNode($);
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.re) case var $0?) {
        if (this.f17() case var $1?) {
          if ($0 case var $) {
            return StarNode($);
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.re) case var $0?) {
        if (this.f18() case var $1?) {
          if ($0 case var $) {
            return PlusNode($);
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.rf) case var $?) {
        return $;
      }
    }
  }

  /// `global::prefix`
  Node? rf() {
    if (this.pos case var mark) {
      if (this.f15() case var $0?) {
        if (this.apply(this.rf) case var $1?) {
          if ($1 case var $) {
            return SequenceNode([NotPredicateNode($), const AnyCharacterNode()], choose: 1);
          }
        }
      }
      this.pos = mark;
      if (this.f16() case var $0?) {
        if (this.apply(this.rf) case var $1?) {
          if ($1 case var $) {
            return AndPredicateNode($);
          }
        }
      }
      this.pos = mark;
      if (this.f14() case var $0?) {
        if (this.apply(this.rf) case var $1?) {
          if ($1 case var $) {
            return NotPredicateNode($);
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.rg) case var $?) {
        return $;
      }
    }
  }

  /// `global::atom`
  Node? rg() {
    if (this.pos case var mark) {
      if (this.apply(this.rg) case var sep?) {
        if (this.f1c() case _?) {
          if (this.fn() case _?) {
            if (this.fy() case _?) {
              if (this.apply(this.r8) case var body?) {
                if (this.fx() case _?) {
                  if (this.f18() case _?) {
                    if (this.f13() case _?) {
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
      if (this.apply(this.rg) case var sep?) {
        if (this.f1c() case _?) {
          if (this.fn() case _?) {
            if (this.fy() case _?) {
              if (this.apply(this.r8) case var body?) {
                if (this.fx() case _?) {
                  if (this.f18() case _?) {
                    return PlusSeparatedNode(sep, body, isTrailingAllowed: false);
                  }
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.rg) case var sep?) {
        if (this.f1c() case _?) {
          if (this.fn() case _?) {
            if (this.fy() case _?) {
              if (this.apply(this.r8) case var body?) {
                if (this.fx() case _?) {
                  if (this.f17() case _?) {
                    if (this.f13() case _?) {
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
      if (this.apply(this.rg) case var sep?) {
        if (this.f1c() case _?) {
          if (this.fn() case _?) {
            if (this.fy() case _?) {
              if (this.apply(this.r8) case var body?) {
                if (this.fx() case _?) {
                  if (this.f17() case _?) {
                    return StarSeparatedNode(sep, body, isTrailingAllowed: false);
                  }
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.rg) case var sep?) {
        if (this.f1c() case _?) {
          if (this.fn() case _?) {
            if (this.fy() case _?) {
              if (this.apply(this.r8) case var body?) {
                if (this.fx() case _?) {
                  return PlusSeparatedNode(sep, body, isTrailingAllowed: false);
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.fn() case _?) {
        if (this.f10() case _?) {
          if (this.f18() case _?) {
            if (this.f13() case _?) {
              if (this.fz() case _?) {
                if (this.fy() case _?) {
                  if (this.apply(this.rg) case var sep?) {
                    if (this.f1g() case _?) {
                      if (this.apply(this.rg) case var body?) {
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
        }
      }
      this.pos = mark;
      if (this.fn() case _?) {
        if (this.f10() case _?) {
          if (this.f17() case _?) {
            if (this.f13() case _?) {
              if (this.fz() case _?) {
                if (this.fy() case _?) {
                  if (this.apply(this.rg) case var sep?) {
                    if (this.f1g() case _?) {
                      if (this.apply(this.rg) case var body?) {
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
        }
      }
      this.pos = mark;
      if (this.fn() case _?) {
        if (this.f10() case _?) {
          if (this.f18() case _?) {
            if (this.fz() case _?) {
              if (this.fy() case _?) {
                if (this.apply(this.rg) case var sep?) {
                  if (this.f1g() case _?) {
                    if (this.apply(this.rg) case var body?) {
                      if (this.fx() case _?) {
                        return PlusSeparatedNode(sep, body, isTrailingAllowed: false);
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
      if (this.fn() case _?) {
        if (this.f10() case _?) {
          if (this.f17() case _?) {
            if (this.fz() case _?) {
              if (this.fy() case _?) {
                if (this.apply(this.rg) case var sep?) {
                  if (this.f1g() case _?) {
                    if (this.apply(this.rg) case var body?) {
                      if (this.fx() case _?) {
                        return StarSeparatedNode(sep, body, isTrailingAllowed: false);
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
      if (this.fn() case _?) {
        if (this.fy() case _?) {
          if (this.apply(this.rg) case var sep?) {
            if (this.f1g() case _?) {
              if (this.apply(this.rg) case var body?) {
                if (this.fx() case _?) {
                  return PlusSeparatedNode(sep, body, isTrailingAllowed: false);
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.f10() case _?) {
        if (this.apply(this.r8) case var $1?) {
          if (this.fz() case _?) {
            return $1;
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.rh) case var $?) {
        return $;
      }
      this.pos = mark;
      if (this.f2() case var $?) {
        return $;
      }
      this.pos = mark;
      if (this.f0() case var $?) {
        return RegExpNode(RegExp($));
      }
      this.pos = mark;
      if (this.f1() case var $?) {
        return StringLiteralNode($);
      }
      this.pos = mark;
      if (this.apply(this.r3) case var $?) {
        return ReferenceNode($);
      }
    }
  }

  /// `global::specialSymbol`
  Node? rh() {
    if (this.pos case var mark) {
      if (this.pos case var mark) {
        if (this.f1e() case var $?) {
          return const StartOfInputNode();
        }
        this.pos = mark;
        if (this.fi() case var $?) {
          return const StartOfInputNode();
        }
      }

      this.pos = mark;
      if (this.pos case var mark) {
        if (this.f1f() case var $?) {
          return const EndOfInputNode();
        }
        this.pos = mark;
        if (this.fj() case var $?) {
          return const EndOfInputNode();
        }
      }

      this.pos = mark;
      if (this.pos case var mark) {
        if (this.f1c() case var $?) {
          return const AnyCharacterNode();
        }
        this.pos = mark;
        if (this.fl() case var $?) {
          return const AnyCharacterNode();
        }
      }

      this.pos = mark;
      if (this.pos case var mark) {
        if (this.f1d() case var $?) {
          return const EpsilonNode();
        }
        this.pos = mark;
        if (this.fk() case var $?) {
          return const EpsilonNode();
        }
      }

      this.pos = mark;
      if (this.fo() case var $?) {
        return const StringLiteralNode(r"\");
      }
      this.pos = mark;
      if (this.fp() case var $?) {
        return SimpleRegExpEscapeNode.digit;
      }
      this.pos = mark;
      if (this.fq() case var $?) {
        return SimpleRegExpEscapeNode.whitespace;
      }
    }
  }

  /// `global::code::curly`
  String ri() {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$9) case _?) {
        if (this.pos case var mark) {
          if (this.f1t() case var _0) {
            if ([if (_0 case var _0?) _0] case (var inner && var _loop2)) {
              if (_loop2.isNotEmpty) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.f1t() case var _0?) {
                      _loop2.add(_0);
                      continue;
                    }
                    this.pos = mark;
                    break;
                  }
                }
              } else {
                this.pos = mark;
              }
              if (this.matchPattern(_string.$9) case _?) {
                return inner.join();
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.rj)! case var $) {
        return $;
      }
    }
  }

  /// `global::code::balanced`
  String rj() {
    if (this.pos case var mark) {
      if (this.f1u() case var _0) {
        if ([if (_0 case var _0?) _0] case (var code && var _loop2)) {
          if (_loop2.isNotEmpty) {
            for (;;) {
              if (this.pos case var mark) {
                if (this.f1u() case var _0?) {
                  _loop2.add(_0);
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
  String? rk() {
    if (this.f1g() case var $0?) {
      if (this.f1v() case var _0?) {
        if ([_0] case (var $1 && var _loop2)) {
          for (;;) {
            if (this.pos case var mark) {
              if (this.f1g() case _?) {
                if (this.f1v() case var _0?) {
                  _loop2.add(_0);
                  continue;
                }
              }
              this.pos = mark;
              break;
            }
          }
          if (this.f1g() case var $2?) {
            if ($1 case var $) {
              return $.join();
            }
          }
        }
      }
    }
  }

  /// `global::dart::literal::identifier`
  String? rl() {
    if (this.f1g() case _?) {
      if (this.f1w() case var $1?) {
        if (this.f1g() case _?) {
          return $1;
        }
      }
    }
  }

  /// `global::dart::literal::string::main`
  Object? rm() {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$52) case var $0?) {
        if (this.matchPattern(_string.$44) case var $1?) {
          if (this.pos case var mark) {
            if (this.f1x() case var _0) {
              if ([if (_0 case var _0?) _0] case (var $2 && var body && var _loop2)) {
                if (_loop2.isNotEmpty) {
                  for (;;) {
                    if (this.pos case var mark) {
                      if (this.f1x() case var _0?) {
                        _loop2.add(_0);
                        continue;
                      }
                      this.pos = mark;
                      break;
                    }
                  }
                } else {
                  this.pos = mark;
                }
                if (this.matchPattern(_string.$44) case var $3?) {
                  return ($0, $1, $2, $3);
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$52) case var $0?) {
        if (this.matchPattern(_string.$45) case var $1?) {
          if (this.pos case var mark) {
            if (this.f1y() case var _2) {
              if ([if (_2 case var _2?) _2] case (var $2 && var body && var _loop4)) {
                if (_loop4.isNotEmpty) {
                  for (;;) {
                    if (this.pos case var mark) {
                      if (this.f1y() case var _2?) {
                        _loop4.add(_2);
                        continue;
                      }
                      this.pos = mark;
                      break;
                    }
                  }
                } else {
                  this.pos = mark;
                }
                if (this.matchPattern(_string.$45) case var $3?) {
                  return ($0, $1, $2, $3);
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$52) case var $0?) {
        if (this.matchPattern(_string.$46) case var $1?) {
          if (this.pos case var mark) {
            if (this.f1z() case var _4) {
              if ([if (_4 case var _4?) _4] case (var $2 && var body && var _loop6)) {
                if (_loop6.isNotEmpty) {
                  for (;;) {
                    if (this.pos case var mark) {
                      if (this.f1z() case var _4?) {
                        _loop6.add(_4);
                        continue;
                      }
                      this.pos = mark;
                      break;
                    }
                  }
                } else {
                  this.pos = mark;
                }
                if (this.matchPattern(_string.$46) case var $3?) {
                  return ($0, $1, $2, $3);
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$52) case var $0?) {
        if (this.matchPattern(_string.$47) case var $1?) {
          if (this.pos case var mark) {
            if (this.f20() case var _6) {
              if ([if (_6 case var _6?) _6] case (var $2 && var body && var _loop8)) {
                if (_loop8.isNotEmpty) {
                  for (;;) {
                    if (this.pos case var mark) {
                      if (this.f20() case var _6?) {
                        _loop8.add(_6);
                        continue;
                      }
                      this.pos = mark;
                      break;
                    }
                  }
                } else {
                  this.pos = mark;
                }
                if (this.matchPattern(_string.$47) case var $3?) {
                  return ($0, $1, $2, $3);
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$44) case var $0?) {
        if (this.pos case var mark) {
          if (this.f21() case var _8) {
            if ([if (_8 case var _8?) _8] case (var $1 && var body && var _loop10)) {
              if (_loop10.isNotEmpty) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.f21() case var _8?) {
                      _loop10.add(_8);
                      continue;
                    }
                    this.pos = mark;
                    break;
                  }
                }
              } else {
                this.pos = mark;
              }
              if (this.matchPattern(_string.$44) case var $2?) {
                return ($0, $1, $2);
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$45) case var $0?) {
        if (this.pos case var mark) {
          if (this.f22() case var _10) {
            if ([if (_10 case var _10?) _10] case (var $1 && var body && var _loop12)) {
              if (_loop12.isNotEmpty) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.f22() case var _10?) {
                      _loop12.add(_10);
                      continue;
                    }
                    this.pos = mark;
                    break;
                  }
                }
              } else {
                this.pos = mark;
              }
              if (this.matchPattern(_string.$45) case var $2?) {
                return ($0, $1, $2);
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$46) case var $0?) {
        if (this.pos case var mark) {
          if (this.f23() case var _12) {
            if ([if (_12 case var _12?) _12] case (var $1 && var body && var _loop14)) {
              if (_loop14.isNotEmpty) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.f23() case var _12?) {
                      _loop14.add(_12);
                      continue;
                    }
                    this.pos = mark;
                    break;
                  }
                }
              } else {
                this.pos = mark;
              }
              if (this.matchPattern(_string.$46) case var $2?) {
                return ($0, $1, $2);
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$47) case var $0?) {
        if (this.pos case var mark) {
          if (this.f24() case var _14) {
            if ([if (_14 case var _14?) _14] case (var $1 && var body && var _loop16)) {
              if (_loop16.isNotEmpty) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.f24() case var _14?) {
                      _loop16.add(_14);
                      continue;
                    }
                    this.pos = mark;
                    break;
                  }
                }
              } else {
                this.pos = mark;
              }
              if (this.matchPattern(_string.$47) case var $2?) {
                return ($0, $1, $2);
              }
            }
          }
        }
      }
    }
  }

  /// `global::dart::literal::string::interpolation`
  Object? rn() {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$42) case var $0?) {
        if (this.matchPattern(_string.$25) case var $1?) {
          if (this.apply(this.ro)! case var $2) {
            if (this.matchPattern(_string.$24) case var $3?) {
              return ($0, $1, $2, $3);
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$42) case var $0?) {
        if (this.apply(this.rl) case var $1?) {
          return ($0, $1);
        }
      }
    }
  }

  /// `global::dart::literal::string::balanced`
  Object ro() {
    if (this.pos case var mark) {
      if (this.f25() case var _0) {
        if ([if (_0 case var _0?) _0] case (var code && var _loop2)) {
          if (_loop2.isNotEmpty) {
            for (;;) {
              if (this.pos case var mark) {
                if (this.f25() case var _0?) {
                  _loop2.add(_0);
                  continue;
                }
                this.pos = mark;
                break;
              }
            }
          } else {
            this.pos = mark;
          }
          return _loop2;
        }
      }
    }
  }

  /// `global::type::main`
  String? rp() {
    if (this.pos case var mark) {
      if (this.f1g() case _?) {
        if (this.fd() case var $1?) {
          if (this.f1g() case _?) {
            return $1;
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.rr) case var $?) {
        return $;
      }
    }
  }

  /// `global::type::nullable`
  String? rq() {
    if (this.f1g() case _?) {
      if (this.apply(this.rr) case var nonNullable?) {
        if (this.f1g() case _?) {
          if (this.f13() case var $3) {
            return $3 == null ?"$nonNullable":"$nonNullable?";
          }
        }
      }
    }
  }

  /// `global::type::nonNullable`
  String? rr() {
    if (this.f1g() case _?) {
      if (this.f26() case var $1?) {
        if (this.f1g() case _?) {
          return $1;
        }
      }
    }
  }

  /// `global::type::record`
  String? rs() {
    if (this.pos case var mark) {
      if (this.f10() case var $0?) {
        if (this.f27() case var $1) {
          if (this.fz() case var $2?) {
            return "("+ ($1 == null ?"":"{"+ $1 +"}") +")";
          }
        }
      }
      this.pos = mark;
      if (this.f10() case var $0?) {
        if (this.fa() case var $1?) {
          if (this.f19() case var $2?) {
            if (this.f28() case var $3) {
              if (this.fz() case var $4?) {
                return "("+ $1 +", "+ ($3 == null ?"":"{"+ $3 +"}") +")";
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.f10() case var $0?) {
        if (this.f8() case var $1?) {
          if (this.f29() case var $2) {
            if (this.fz() case var $3?) {
              return "("+ $1 + ($2 == null ?"":", {"+ $2 +"}") +")";
            }
          }
        }
      }
    }
  }

  /// `global::type::generic`
  String? rt() {
    if (this.apply(this.rv) case var base?) {
      if (this.ft() case _?) {
        if (this.apply(this.ru) case var arguments?) {
          if (this.fu() case _?) {
            return "$base<$arguments>";
          }
        }
      }
    }
  }

  /// `global::type::arguments`
  String? ru() {
    if (this.apply(this.rq) case var _0?) {
      if ([_0] case (var $ && var _loop2)) {
        for (;;) {
          if (this.pos case var mark) {
            if (this.f19() case _?) {
              if (this.apply(this.rq) case var _0?) {
                _loop2.add(_0);
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

  /// `global::type::base`
  String? rv() {
    if (this.fc() case var _0?) {
      if ([_0] case (var $ && var _loop2)) {
        for (;;) {
          if (this.pos case var mark) {
            if (this.f1c() case _?) {
              if (this.fc() case var _0?) {
                _loop2.add(_0);
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

  static final _regexp = (
    RegExp("\\d"),
    RegExp("(?:(?:\\s)|(?:\\/{2}.*(?:(?:\\r?\\n)|(?:\$))))*"),
  );
  static const _string = (
    "/",
    "-",
    "d",
    "\\",
    "w",
    "s",
    "D",
    "]",
    "`",
    "@rule",
    "@fragment",
    "@inline",
    "startOfInput",
    "endOfInput",
    "epsilon",
    "any",
    "var",
    "sep!",
    "..",
    "@",
    "<",
    ">",
    "[",
    "}",
    "{",
    ")",
    "(",
    ";",
    "=",
    "?",
    "!",
    "~",
    "&",
    "*",
    "+",
    ",",
    ":",
    "|",
    ".",
    "ε",
    "^",
    "\$",
    "::",
    "\"\"\"",
    "'''",
    "\"",
    "'",
    "r\"\"\"",
    "r'''",
    "r\"",
    "r'",
    "r",
  );
  static const _range = (
    { (97, 122), (65, 90), (48, 57), (95, 95), (36, 36) },
    { (97, 122), (65, 90), (95, 95), (36, 36) },
  );
}
