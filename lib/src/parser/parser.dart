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


  /// `global::name`
  String? f0() {
    if (this.pos case var mark) {
      if (this.pos case var mark) {
        if (this.f28() case var _0) {
          if ([if (_0 case var _0?) _0] case (var $0 && var _loop2)) {
            if (_loop2.isNotEmpty) {
              for (;;) {
                if (this.pos case var mark) {
                  if (this.f28() case var _0?) {
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
            if (this.f2() case var $1?) {
              if (($0, $1) case var $) {
                return $0.isEmpty ? $1 :"${$0.join("::")}::${$1}";
              }
            }
          }
        }
      }

      this.pos = mark;
      if (this.pos case var mark) {
        if (this.f29() case var _2) {
          if ([if (_2 case var _2?) _2] case (var $0 && var _loop4)) {
            if (_loop4.isNotEmpty) {
              for (;;) {
                if (this.pos case var mark) {
                  if (this.f29() case var _2?) {
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
            if (this.f1h() case var $1?) {
              if (($0, $1) case var $) {
                return $0.isEmpty ? $1 :"${$0.join("::")}::${$1}";
              }
            }
          }
        }
      }
    }
  }

  /// `global::body`
  Node? f1() {
    if (this.fr() case _?) {
      if (this.apply(this.r7) case var choice?) {
        if (this.fs() case _?) {
          return choice;
        }
      }
    }
  }

  /// `global::literal::raw`
  String? f2() {
    if (this.matchPattern(_string.$1) case _?) {
      if (this.pos case var mark) {
        if (this.f2a() case var _0) {
          if ([if (_0 case var _0?) _0] case (var inner && var _loop2)) {
            if (_loop2.isNotEmpty) {
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
            } else {
              this.pos = mark;
            }
            if (this.matchPattern(_string.$1) case _?) {
              return inner.join();
            }
          }
        }
      }
    }
  }

  /// `global::literal::range::atom`
  String? f3() {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$2) case _?) {
        if (pos < buffer.length) {
          if (buffer[pos] case var $1) {
            pos++;
            return $1;
          }
        }
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.matchPattern(_string.$3) case (null)) {
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

  /// `global::literal::range::escape`
  Set<(int, int)>? f4() {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$2) case var $0?) {
        if (this.matchPattern(_string.$4) case var $1?) {
          return {(48, 57)};
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$2) case var $0?) {
        if (this.matchPattern(_string.$5) case var $1?) {
          return {(64 + 1, 64 + 26), (96 + 1, 96 + 26)};
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$2) case var $0?) {
        if (this.matchPattern(_string.$6) case var $1?) {
          return {(9, 13), (32, 32)};
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$2) case var $0?) {
        if (this.matchPattern(_string.$7) case var $1?) {
          return {(0, 47), (58, 65535)};
        }
      }
    }
  }

  /// `global::literal::range::element`
  Set<(int, int)>? f5() {
    if (this.pos case var mark) {
      if (this.f4() case var $?) {
        return $;
      }
      this.pos = mark;
      if (this.f3() case var l?) {
        if (this.matchPattern(_string.$8) case _?) {
          if (this.f3() case var r?) {
            return {(l.codeUnitAt(0), r.codeUnitAt(0))};
          }
        }
      }
      this.pos = mark;
      if (this.f3() case var $?) {
        return {($.codeUnitAt(0), $.codeUnitAt(0))};
      }
    }
  }

  /// `global::literal::range::main`
  Node? f6() {
    if (this.fx() case _?) {
      if (this.f5() case var _0?) {
        if ([_0] case (var elements && var _loop2)) {
          for (;;) {
            if (this.pos case var mark) {
              if (this.fe() case _?) {
                if (this.f5() case var _0?) {
                  _loop2.add(_0);
                  continue;
                }
              }
              this.pos = mark;
              break;
            }
          }
          if (this.fy() case _?) {
            return RangeNode(elements.reduce((a, b) => a.union(b)));
          }
        }
      }
    }
  }

  /// `global::literal::range`
  Node? f7() {
    if (this.fe() case _?) {
      if (this.f6() case var $1?) {
        if (this.fe() case _?) {
          return $1;
        }
      }
    }
  }

  /// `global::literal::string`
  String? f8() {
    if (this.fe() case _?) {
      if (this.f2j() case var $1?) {
        if (this.fe() case _?) {
          return $1;
        }
      }
    }
  }

  /// `global::literal::regexp`
  String? f9() {
    if (this.matchPattern(_string.$9) case _?) {
      if (this.f2l() case var $1?) {
        if (this.matchPattern(_string.$9) case _?) {
          return $1;
        }
      }
    }
  }

  /// `global::type::field::named`
  String? fa() {
    if (this.apply(this.rt) case var $0?) {
      if (this.fe() case var $1?) {
        if (this.f1h() case var $2?) {
          if (($0, $1, $2) case var $) {
            return "${$0} ${$2}";
          }
        }
      }
    }
  }

  /// `global::type::field::positional`
  String? fb() {
    if (this.apply(this.rt) case var $0?) {
      if (this.fe() case var $1?) {
        if (this.f1h() case var $2) {
          if (($0, $1, $2) case var $) {
            return "${$0} ${$2 ?? ""}".trimRight();
          }
        }
      }
    }
  }

  /// `global::type::fields::named`
  String? fc() {
    if (this.fa() case var _0?) {
      if ([_0] case (var $ && var _loop2)) {
        for (;;) {
          if (this.pos case var mark) {
            if (this.fl() case _?) {
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

  /// `global::type::fields::positional`
  String? fd() {
    if (this.fb() case var _0?) {
      if ([_0] case (var $ && var _loop2)) {
        for (;;) {
          if (this.pos case var mark) {
            if (this.fl() case _?) {
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

  /// `global::_`
  String? fe() {
    if (matchPattern(_regexp.$1) case var $?) {
      return "";
    }
  }

  /// `global::DOLLAR`
  String? ff() {
    if (this.fe() case _?) {
      if (this.matchPattern(_string.$10) case var $1?) {
        if (this.fe() case _?) {
          return $1;
        }
      }
    }
  }

  /// `global::CARET`
  String? fg() {
    if (this.fe() case _?) {
      if (this.matchPattern(_string.$11) case var $1?) {
        if (this.fe() case _?) {
          return $1;
        }
      }
    }
  }

  /// `global::EPSILON`
  String? fh() {
    if (this.fe() case _?) {
      if (this.matchPattern(_string.$12) case var $1?) {
        if (this.fe() case _?) {
          return $1;
        }
      }
    }
  }

  /// `global::DOT`
  String? fi() {
    if (this.fe() case _?) {
      if (this.matchPattern(_string.$13) case var $1?) {
        if (this.fe() case _?) {
          return $1;
        }
      }
    }
  }

  /// `global::|`
  String? fj() {
    if (this.fe() case _?) {
      if (this.matchPattern(_string.$14) case var $1?) {
        if (this.fe() case _?) {
          return $1;
        }
      }
    }
  }

  /// `global:::`
  String? fk() {
    if (this.fe() case _?) {
      if (this.matchPattern(_string.$15) case var $1?) {
        if (this.fe() case _?) {
          return $1;
        }
      }
    }
  }

  /// `global::,`
  String? fl() {
    if (this.fe() case _?) {
      if (this.matchPattern(_string.$16) case var $1?) {
        if (this.fe() case _?) {
          return $1;
        }
      }
    }
  }

  /// `global::+`
  String? fm() {
    if (this.fe() case _?) {
      if (this.matchPattern(_string.$17) case var $1?) {
        if (this.fe() case _?) {
          return $1;
        }
      }
    }
  }

  /// `global::*`
  String? fn() {
    if (this.fe() case _?) {
      if (this.matchPattern(_string.$18) case var $1?) {
        if (this.fe() case _?) {
          return $1;
        }
      }
    }
  }

  /// `global::&`
  String? fo() {
    if (this.fe() case _?) {
      if (this.matchPattern(_string.$19) case var $1?) {
        if (this.fe() case _?) {
          return $1;
        }
      }
    }
  }

  /// `global::!`
  String? fp() {
    if (this.fe() case _?) {
      if (this.matchPattern(_string.$20) case var $1?) {
        if (this.fe() case _?) {
          return $1;
        }
      }
    }
  }

  /// `global::?`
  String? fq() {
    if (this.fe() case _?) {
      if (this.matchPattern(_string.$21) case var $1?) {
        if (this.fe() case _?) {
          return $1;
        }
      }
    }
  }

  /// `global::=`
  String? fr() {
    if (this.fe() case _?) {
      if (this.matchPattern(_string.$22) case var $1?) {
        if (this.fe() case _?) {
          return $1;
        }
      }
    }
  }

  /// `global::;`
  String? fs() {
    if (this.fe() case _?) {
      if (this.matchPattern(_string.$23) case var $1?) {
        if (this.fe() case _?) {
          return $1;
        }
      }
    }
  }

  /// `global::(`
  String? ft() {
    if (this.fe() case _?) {
      if (this.matchPattern(_string.$24) case var $1?) {
        if (this.fe() case _?) {
          return $1;
        }
      }
    }
  }

  /// `global::)`
  String? fu() {
    if (this.fe() case _?) {
      if (this.matchPattern(_string.$25) case var $1?) {
        if (this.fe() case _?) {
          return $1;
        }
      }
    }
  }

  /// `global::{`
  String? fv() {
    if (this.fe() case _?) {
      if (this.matchPattern(_string.$26) case var $1?) {
        if (this.fe() case _?) {
          return $1;
        }
      }
    }
  }

  /// `global::}`
  String? fw() {
    if (this.fe() case _?) {
      if (this.matchPattern(_string.$27) case var $1?) {
        if (this.fe() case _?) {
          return $1;
        }
      }
    }
  }

  /// `global::[`
  String? fx() {
    if (this.fe() case _?) {
      if (this.matchPattern(_string.$28) case var $1?) {
        if (this.fe() case _?) {
          return $1;
        }
      }
    }
  }

  /// `global::]`
  String? fy() {
    if (this.fe() case _?) {
      if (this.matchPattern(_string.$3) case var $1?) {
        if (this.fe() case _?) {
          return $1;
        }
      }
    }
  }

  /// `global::>`
  String? fz() {
    if (this.fe() case _?) {
      if (this.matchPattern(_string.$29) case var $1?) {
        if (this.fe() case _?) {
          return $1;
        }
      }
    }
  }

  /// `global::<`
  String? f10() {
    if (this.fe() case _?) {
      if (this.matchPattern(_string.$30) case var $1?) {
        if (this.fe() case _?) {
          return $1;
        }
      }
    }
  }

  /// `global::@`
  String? f11() {
    if (this.fe() case _?) {
      if (this.matchPattern(_string.$31) case var $1?) {
        if (this.fe() case _?) {
          return $1;
        }
      }
    }
  }

  /// `global::..`
  String? f12() {
    if (this.fe() case _?) {
      if (this.matchPattern(_string.$32) case var $1?) {
        if (this.fe() case _?) {
          return $1;
        }
      }
    }
  }

  /// `global::regexEscape::space`
  String? f13() {
    if (this.fe() case _?) {
      if (this.f2m() case var $1?) {
        if (this.fe() case _?) {
          return $1;
        }
      }
    }
  }

  /// `global::regexEscape::digit`
  String? f14() {
    if (this.fe() case _?) {
      if (this.f2n() case var $1?) {
        if (this.fe() case _?) {
          return $1;
        }
      }
    }
  }

  /// `global::regexEscape::backslash`
  String? f15() {
    if (this.fe() case _?) {
      if (this.f2o() case var $1?) {
        if (this.fe() case _?) {
          return $1;
        }
      }
    }
  }

  /// `global::mac::sep`
  String? f16() {
    if (this.fe() case _?) {
      if (this.matchPattern(_string.$33) case var $1?) {
        if (this.fe() case _?) {
          return $1;
        }
      }
    }
  }

  /// `global::kw::var`
  String? f17() {
    if (this.fe() case _?) {
      if (this.matchPattern(_string.$34) case var $1?) {
        if (this.fe() case _?) {
          return $1;
        }
      }
    }
  }

  /// `global::kw::any`
  String? f18() {
    if (this.fe() case _?) {
      if (this.matchPattern(_string.$35) case var $1?) {
        if (this.fe() case _?) {
          return $1;
        }
      }
    }
  }

  /// `global::kw::epsilon`
  String? f19() {
    if (this.fe() case _?) {
      if (this.matchPattern(_string.$36) case var $1?) {
        if (this.fe() case _?) {
          return $1;
        }
      }
    }
  }

  /// `global::kw::end`
  String? f1a() {
    if (this.fe() case _?) {
      if (this.matchPattern(_string.$37) case var $1?) {
        if (this.fe() case _?) {
          return $1;
        }
      }
    }
  }

  /// `global::kw::start`
  String? f1b() {
    if (this.fe() case _?) {
      if (this.matchPattern(_string.$38) case var $1?) {
        if (this.fe() case _?) {
          return $1;
        }
      }
    }
  }

  /// `global::kw::decorator::inline`
  String? f1c() {
    if (this.fe() case _?) {
      if (this.matchPattern(_string.$39) case var $1?) {
        if (this.fe() case _?) {
          return $1;
        }
      }
    }
  }

  /// `global::kw::decorator::fragment`
  String? f1d() {
    if (this.fe() case _?) {
      if (this.matchPattern(_string.$40) case var $1?) {
        if (this.fe() case _?) {
          return $1;
        }
      }
    }
  }

  /// `global::kw::decorator::rule`
  String? f1e() {
    if (this.fe() case _?) {
      if (this.matchPattern(_string.$41) case var $1?) {
        if (this.fe() case _?) {
          return $1;
        }
      }
    }
  }

  /// `global::number`
  int? f1f() {
    if (matchPattern(_regexp.$2) case var _0?) {
      if ([_0] case (var $ && var _loop2)) {
        for (;;) {
          if (this.pos case var mark) {
            if (matchPattern(_regexp.$2) case var _0?) {
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

  /// `global::raw`
  String? f1g() {
    if (this.matchPattern(_string.$1) case _?) {
      if (this.pos case var mark) {
        if (this.f2p() case var _0) {
          if ([if (_0 case var _0?) _0] case (var inner && var _loop2)) {
            if (_loop2.isNotEmpty) {
              for (;;) {
                if (this.pos case var mark) {
                  if (this.f2p() case var _0?) {
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
            if (this.matchPattern(_string.$1) case _?) {
              return inner.join();
            }
          }
        }
      }
    }
  }

  /// `global::identifier`
  String? f1h() {
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

  /// `ROOT`
  ParserGenerator? f1i() {
    if (this.apply(this.r0) case var $?) {
      return $;
    }
  }

  /// `fragment0`
  late final f1j = () {
    if (this.f1h() case var $0?) {
      if (this.matchPattern(_string.$42) case _?) {
        return $0;
      }
    }
  };

  /// `fragment1`
  late final f1k = () {
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
          if (this.f1h() case var $1?) {
            if (($0, $1) case var $) {
              return $0.isEmpty ? $1 :"${$0.join("::")}::${$1}";
            }
          }
        }
      }
    }
  };

  /// `fragment2`
  late final f1l = () {
    if (this.f1h() case var $0?) {
      if (this.matchPattern(_string.$42) case _?) {
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
          if (this.f1h() case var $1?) {
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
    if (this.f1h() case var $0?) {
      if (this.matchPattern(_string.$42) case _?) {
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
          if (this.f1h() case var $1?) {
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
    if (this.f1h() case var $0?) {
      if (this.matchPattern(_string.$42) case _?) {
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
          if (this.f1h() case var $1?) {
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
    if (this.pos case var mark) {
      if (this.apply(this.rn) case var $?) {
        return $;
      }
      this.pos = mark;
      if (this.matchPattern(_string.$26) case var $0?) {
        if (this.apply(this.rh)! case var $1) {
          if (this.matchPattern(_string.$27) case var $2?) {
            if ($1 case var $) {
              return "{"+ $ +"}";
            }
          }
        }
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.matchPattern(_string.$26) case (null)) {
          this.pos = mark;
          if (this.pos case var mark) {
            if (this.matchPattern(_string.$27) case (null)) {
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

  /// `fragment9`
  late final f1s = () {
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
  };

  /// `fragment10`
  late final f1t = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$26) case _?) {
        if (this.apply(this.rj)! case var $1) {
          if (this.matchPattern(_string.$27) case _?) {
            return $1;
          }
        }
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.matchPattern(_string.$26) case (null)) {
          this.pos = mark;
          if (this.pos case var mark) {
            if (this.matchPattern(_string.$27) case (null)) {
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

  /// `fragment11`
  late final f1u = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$43) case (null)) {
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

  /// `fragment12`
  late final f1v = () {
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

  /// `fragment13`
  late final f1w = () {
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

  /// `fragment14`
  late final f1x = () {
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

  /// `fragment15`
  late final f1y = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$2) case _?) {
        if (pos < buffer.length) {
          if (buffer[pos] case var $1) {
            pos++;
            return $1;
          }
        }
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.matchPattern(_string.$10) case var $0?) {
          this.pos = mark;
          if (this.apply(this.rk) case var $1?) {
            return ($0, $1);
          }
        }
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.matchPattern(_string.$43) case (null)) {
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

  /// `fragment16`
  late final f1z = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$2) case _?) {
        if (pos < buffer.length) {
          if (buffer[pos] case var $1) {
            pos++;
            return $1;
          }
        }
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.matchPattern(_string.$10) case var $0?) {
          this.pos = mark;
          if (this.apply(this.rk) case var $1?) {
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

  /// `fragment17`
  late final f20 = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$2) case _?) {
        if (pos < buffer.length) {
          if (buffer[pos] case var $1) {
            pos++;
            return $1;
          }
        }
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.matchPattern(_string.$10) case var $0?) {
          this.pos = mark;
          if (this.apply(this.rk) case var $1?) {
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

  /// `fragment18`
  late final f21 = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$2) case _?) {
        if (pos < buffer.length) {
          if (buffer[pos] case var $1) {
            pos++;
            return $1;
          }
        }
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.matchPattern(_string.$10) case var $0?) {
          this.pos = mark;
          if (this.apply(this.rk) case var $1?) {
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

  /// `fragment19`
  late final f22 = () {
    if (this.pos case var from) {
      if (this.f1h() case var $?) {
        if (this.pos case var to) {
          return this.buffer.substring(from, to);
        }
      }
    }
  };

  /// `fragment20`
  late final f23 = () {
    if (this.pos case var from) {
      if (this.apply(this.rl) case var $?) {
        if (this.pos case var to) {
          return buffer.substring(from, to);
        }
      }
    }
  };

  /// `fragment21`
  late final f24 = () {
    if (this.fv() case _?) {
      if (this.fc() case var $1?) {
        if (this.fw() case _?) {
          return $1;
        }
      }
    }
  };

  /// `fragment22`
  late final f25 = () {
    if (this.fv() case _?) {
      if (this.fc() case var $1?) {
        if (this.fw() case _?) {
          return $1;
        }
      }
    }
  };

  /// `fragment23`
  late final f26 = () {
    if (this.fl() case _?) {
      if (this.fv() case _?) {
        if (this.fc() case var $2?) {
          if (this.fw() case _?) {
            return $2;
          }
        }
      }
    }
  };

  /// `fragment24`
  late final f27 = () {
    if (this.pos case var mark) {
      if (this.apply(this.rq) case var $?) {
        return $;
      }
      this.pos = mark;
      if (this.apply(this.rr) case var $?) {
        return $;
      }
      this.pos = mark;
      if (this.apply(this.ro) case var $?) {
        return $;
      }
    }
  };

  /// `fragment25`
  late final f28 = () {
    if (this.f1h() case var $0?) {
      if (this.matchPattern(_string.$42) case _?) {
        return $0;
      }
    }
  };

  /// `fragment26`
  late final f29 = () {
    if (this.f1h() case var $0?) {
      if (this.matchPattern(_string.$42) case _?) {
        return $0;
      }
    }
  };

  /// `fragment27`
  late final f2a = () {
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
  };

  /// `fragment28`
  late final f2b = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$43) case (null)) {
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
      if (this.matchPattern(_string.$2) case _?) {
        if (pos < buffer.length) {
          if (buffer[pos] case var $1) {
            pos++;
            return $1;
          }
        }
      }
      this.pos = mark;
      if (this.pos case var mark) {
        if (this.matchPattern(_string.$43) case (null)) {
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

  /// `fragment33`
  late final f2g = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$2) case _?) {
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
      if (this.matchPattern(_string.$2) case _?) {
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
      if (this.matchPattern(_string.$2) case _?) {
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
      if (this.matchPattern(_string.$47) case _?) {
        if (this.pos case var mark) {
          if (this.f2b() case var _0) {
            if ([if (_0 case var _0?) _0] case (var body && var _loop2)) {
              if (_loop2.isNotEmpty) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.f2b() case var _0?) {
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
              if (this.matchPattern(_string.$43) case _?) {
                return body.join();
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$48) case _?) {
        if (this.pos case var mark) {
          if (this.f2c() case var _2) {
            if ([if (_2 case var _2?) _2] case (var body && var _loop4)) {
              if (_loop4.isNotEmpty) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.f2c() case var _2?) {
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
          if (this.f2d() case var _4) {
            if ([if (_4 case var _4?) _4] case (var body && var _loop6)) {
              if (_loop6.isNotEmpty) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.f2d() case var _4?) {
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
          if (this.f2e() case var _6) {
            if ([if (_6 case var _6?) _6] case (var body && var _loop8)) {
              if (_loop8.isNotEmpty) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.f2e() case var _6?) {
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
              if (this.matchPattern(_string.$46) case _?) {
                return body.join();
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$43) case _?) {
        if (this.pos case var mark) {
          if (this.f2f() case var _8) {
            if ([if (_8 case var _8?) _8] case (var body && var _loop10)) {
              if (_loop10.isNotEmpty) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.f2f() case var _8?) {
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
              if (this.matchPattern(_string.$43) case _?) {
                return body.join();
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$44) case _?) {
        if (this.pos case var mark) {
          if (this.f2g() case var _10) {
            if ([if (_10 case var _10?) _10] case (var body && var _loop12)) {
              if (_loop12.isNotEmpty) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.f2g() case var _10?) {
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
          if (this.f2h() case var _12) {
            if ([if (_12 case var _12?) _12] case (var body && var _loop14)) {
              if (_loop14.isNotEmpty) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.f2h() case var _12?) {
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
          if (this.f2i() case var _14) {
            if ([if (_14 case var _14?) _14] case (var body && var _loop16)) {
              if (_loop16.isNotEmpty) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.f2i() case var _14?) {
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
              if (this.matchPattern(_string.$46) case _?) {
                return body.join();
              }
            }
          }
        }
      }
    }
  };

  /// `fragment37`
  late final f2k = () {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$2) case var $0?) {
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
    }
  };

  /// `fragment38`
  late final f2l = () {
    if (this.f2k() case var _0?) {
      if ([_0] case (var $ && var _loop2)) {
        for (;;) {
          if (this.pos case var mark) {
            if (this.f2k() case var _0?) {
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

  /// `fragment39`
  late final f2m = () {
    if (this.matchPattern(_string.$2) case var $0?) {
      if (this.matchPattern(_string.$6) case var $1?) {
        if ($1 case var $) {
          return r"\"+ $;
        }
      }
    }
  };

  /// `fragment40`
  late final f2n = () {
    if (this.matchPattern(_string.$2) case var $0?) {
      if (this.matchPattern(_string.$4) case var $1?) {
        if ($1 case var $) {
          return r"\"+ $;
        }
      }
    }
  };

  /// `fragment41`
  late final f2o = () {
    if (this.matchPattern(_string.$2) case var $0?) {
      if (this.matchPattern(_string.$2) case var $1?) {
        if ($1 case var $) {
          return r"\"+ $;
        }
      }
    }
  };

  /// `fragment42`
  late final f2p = () {
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
  };

  /// `global::document`
  ParserGenerator? r0() {
    if (this.pos case _ when this.pos <= 0) {
      if (this.apply(this.r1) case var preamble) {
        if (this.apply(this.r2) case var _0?) {
          if ([_0] case (var statements && var _loop2)) {
            for (;;) {
              if (this.pos case var mark) {
                if (this.fe() case _?) {
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
              if (this.fe() case null) {
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
    if (this.fv() case _?) {
      if (this.fe() case _?) {
        if (this.apply(this.ri)! case var code) {
          if (this.fe() case _?) {
            if (this.fw() case _?) {
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
      if (this.apply(this.r5) case var $?) {
        return $;
      }
      this.pos = mark;
      if (this.apply(this.r6) case var $?) {
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
    if (this.pos case var mark) {
      if (this.f1d() case _?) {
        if (this.f1h() case var name) {
          if (this.fv() case _?) {
            if (this.apply(this.r2) case var _0?) {
              if ([_0] case (var statements && var _loop2)) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.fe() case _?) {
                      if (this.apply(this.r2) case var _0?) {
                        _loop2.add(_0);
                        continue;
                      }
                    }
                    this.pos = mark;
                    break;
                  }
                }
                if (this.fw() case _?) {
                  return NamespaceStatement(name, statements, tag: Tag.fragment);
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.f1e() case _?) {
        if (this.f1h() case var name) {
          if (this.fv() case _?) {
            if (this.apply(this.r2) case var _2?) {
              if ([_2] case (var statements && var _loop4)) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.fe() case _?) {
                      if (this.apply(this.r2) case var _2?) {
                        _loop4.add(_2);
                        continue;
                      }
                    }
                    this.pos = mark;
                    break;
                  }
                }
                if (this.fw() case _?) {
                  return NamespaceStatement(name, statements, tag: Tag.rule);
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.f1c() case _?) {
        if (this.f1h() case var name) {
          if (this.fv() case _?) {
            if (this.apply(this.r2) case var _4?) {
              if ([_4] case (var statements && var _loop6)) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.fe() case _?) {
                      if (this.apply(this.r2) case var _4?) {
                        _loop6.add(_4);
                        continue;
                      }
                    }
                    this.pos = mark;
                    break;
                  }
                }
                if (this.fw() case _?) {
                  return NamespaceStatement(name, statements, tag: Tag.inline);
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.f1h() case var name) {
        if (this.fv() case _?) {
          if (this.apply(this.r2) case var _6?) {
            if ([_6] case (var statements && var _loop8)) {
              for (;;) {
                if (this.pos case var mark) {
                  if (this.fe() case _?) {
                    if (this.apply(this.r2) case var _6?) {
                      _loop8.add(_6);
                      continue;
                    }
                  }
                  this.pos = mark;
                  break;
                }
              }
              if (this.fw() case _?) {
                return NamespaceStatement(name, statements, tag: null);
              }
            }
          }
        }
      }
    }
  }

  /// `global::rule`
  Statement? r4() {
    if (this.pos case var mark) {
      if (this.f1e() case var $0) {
        if (this.f17() case _?) {
          if (this.f0() case var name?) {
            if (this.f1() case var body?) {
              return DeclarationStatement(null, name, body, tag: $0 == null ? null : Tag.rule);
            }
          }
        }
      }
      this.pos = mark;
      if (this.f1e() case var $0) {
        if (this.f0() case var name?) {
          if (this.f1() case var body?) {
            return DeclarationStatement(null, name, body, tag: $0 == null ? null : Tag.rule);
          }
        }
      }
      this.pos = mark;
      if (this.f1e() case var $0) {
        if (this.apply(this.ru) case var type?) {
          if (this.f0() case var name?) {
            if (this.f1() case var body?) {
              return DeclarationStatement(type, name, body, tag: $0 == null ? null : Tag.rule);
            }
          }
        }
      }
      this.pos = mark;
      if (this.f1e() case var $0) {
        if (this.f0() case var name?) {
          if (this.fk() case _?) {
            if (this.apply(this.ru) case var type?) {
              if (this.f1() case var body?) {
                return DeclarationStatement(type, name, body, tag: $0 == null ? null : Tag.rule);
              }
            }
          }
        }
      }
    }
  }

  /// `global::fragment`
  Statement? r5() {
    if (this.pos case var mark) {
      if (this.f1d() case _?) {
        if (this.f17() case _?) {
          if (this.f0() case var name?) {
            if (this.f1() case var body?) {
              return DeclarationStatement(null, name, body, tag: Tag.fragment);
            }
          }
        }
      }
      this.pos = mark;
      if (this.f1d() case _?) {
        if (this.f0() case var name?) {
          if (this.f1() case var body?) {
            return DeclarationStatement(null, name, body, tag: Tag.fragment);
          }
        }
      }
      this.pos = mark;
      if (this.f1d() case _?) {
        if (this.apply(this.ru) case var type?) {
          if (this.f0() case var name?) {
            if (this.f1() case var body?) {
              return DeclarationStatement(type, name, body, tag: Tag.fragment);
            }
          }
        }
      }
      this.pos = mark;
      if (this.f1d() case _?) {
        if (this.f0() case var name?) {
          if (this.fk() case _?) {
            if (this.apply(this.ru) case var type?) {
              if (this.f1() case var body?) {
                return DeclarationStatement(type, name, body, tag: Tag.fragment);
              }
            }
          }
        }
      }
    }
  }

  /// `global::inline`
  Statement? r6() {
    if (this.pos case var mark) {
      if (this.f1c() case _?) {
        if (this.f17() case _?) {
          if (this.f0() case var name?) {
            if (this.f1() case var body?) {
              return DeclarationStatement(null, name, body, tag: Tag.inline);
            }
          }
        }
      }
      this.pos = mark;
      if (this.f1c() case _?) {
        if (this.f0() case var name?) {
          if (this.f1() case var body?) {
            return DeclarationStatement(null, name, body, tag: Tag.inline);
          }
        }
      }
      this.pos = mark;
      if (this.f1c() case _?) {
        if (this.apply(this.ru) case var type?) {
          if (this.f0() case var name?) {
            if (this.f1() case var body?) {
              return DeclarationStatement(type, name, body, tag: Tag.inline);
            }
          }
        }
      }
      this.pos = mark;
      if (this.f1c() case _?) {
        if (this.f0() case var name?) {
          if (this.fk() case _?) {
            if (this.apply(this.ru) case var type?) {
              if (this.f1() case var body?) {
                return DeclarationStatement(type, name, body, tag: Tag.inline);
              }
            }
          }
        }
      }
    }
  }

  /// `global::choice`
  Node? r7() {
    if (this.fj() case _) {
      if (this.apply(this.r8) case var _0?) {
        if ([_0] case (var options && var _loop2)) {
          for (;;) {
            if (this.pos case var mark) {
              if (this.fj() case _?) {
                if (this.apply(this.r8) case var _0?) {
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
  Node? r8() {
    if (this.pos case var mark) {
      if (this.pos case var from) {
        if (this.apply(this.r9) case var sequence?) {
          if (this.fv() case _?) {
            if (this.fw() case _?) {
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
        if (this.apply(this.r9) case var sequence?) {
          if (this.fv() case _?) {
            if (this.fe() case _?) {
              if (this.apply(this.ri)! case var code) {
                if (this.fe() case _?) {
                  if (this.fw() case _?) {
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
        if (this.apply(this.r9) case var sequence?) {
          if (this.ft() case _?) {
            if (this.fu() case _?) {
              if (this.fv() case _?) {
                if (this.fe() case _?) {
                  if (this.apply(this.ri)! case var code) {
                    if (this.fe() case _?) {
                      if (this.fw() case _?) {
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
      if (this.apply(this.r9) case var $?) {
        return $;
      }
    }
  }

  /// `global::sequence`
  Node? r9() {
    if (this.pos case var mark) {
      if (this.apply(this.ra) case var _0?) {
        if ([_0] case (var body && var _loop2)) {
          for (;;) {
            if (this.pos case var mark) {
              if (this.fe() case _?) {
                if (this.apply(this.ra) case var _0?) {
                  _loop2.add(_0);
                  continue;
                }
              }
              this.pos = mark;
              break;
            }
          }
          if (this.f11() case _?) {
            if (this.f1f() case var number?) {
              return body.length == 1 ? body.single : SequenceNode(body, choose: number);
            }
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.ra) case var _2?) {
        if ([_2] case (var $ && var _loop4)) {
          for (;;) {
            if (this.pos case var mark) {
              if (this.fe() case _?) {
                if (this.apply(this.ra) case var _2?) {
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
  Node? ra() {
    if (this.apply(this.rb) case var $?) {
      return $;
    }
  }

  /// `global::labeled`
  Node? rb() {
    if (this.pos case var mark) {
      if (this.f1h() case var identifier?) {
        if (this.matchPattern(_string.$15) case _?) {
          if (this.fe() case _?) {
            if (this.apply(this.rc) case var separated?) {
              return NamedNode(identifier, separated);
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$15) case _?) {
        if (this.f1k() case var id?) {
          if (this.fq() case _?) {
            return switch ((id, id.split("::"))) {
                  (var ref, [..., var name]) => NamedNode(name, OptionalNode(ReferenceNode(ref))),
                  _ => null,
                };
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$15) case _?) {
        if (this.f1m() case var id?) {
          if (this.fn() case _?) {
            return switch ((id, id.split("::"))) {
                  (var ref, [..., var name]) => NamedNode(name, StarNode(ReferenceNode(ref))),
                  _ => null,
                };
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$15) case _?) {
        if (this.f1o() case var id?) {
          if (this.fm() case _?) {
            return switch ((id, id.split("::"))) {
                  (var ref, [..., var name]) => NamedNode(name, PlusNode(ReferenceNode(ref))),
                  _ => null,
                };
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$15) case _?) {
        if (this.f1q() case var id?) {
          return switch ((id, id.split("::"))) {
                (var ref, [..., var name]) => NamedNode(name, ReferenceNode(ref)),
                _ => null,
              };
        }
      }
      this.pos = mark;
      if (this.apply(this.rc) case var $?) {
        return $;
      }
    }
  }

  /// `global::separated`
  Node? rc() {
    if (this.pos case var mark) {
      if (this.f1f() case var min?) {
        if (this.f12() case _?) {
          if (this.f1f() case var max) {
            if (this.apply(this.rf) case var atom?) {
              return CountedNode(min, max, atom);
            }
          }
        }
      }
      this.pos = mark;
      if (this.f1f() case var number?) {
        if (this.apply(this.rf) case var atom?) {
          return CountedNode(number, number, atom);
        }
      }
      this.pos = mark;
      if (this.apply(this.rf) case var sep?) {
        if (this.fi() case _?) {
          if (this.apply(this.rf) case var expr?) {
            if (this.fm() case _?) {
              if (this.fq() case var trailing) {
                return PlusSeparatedNode(sep, expr, isTrailingAllowed: trailing != null);
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.rf) case var sep?) {
        if (this.fi() case _?) {
          if (this.apply(this.rf) case var expr?) {
            if (this.fn() case _?) {
              if (this.fq() case var trailing) {
                return StarSeparatedNode(sep, expr, isTrailingAllowed: trailing != null);
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.rd) case var $?) {
        return $;
      }
    }
  }

  /// `global::postfix`
  Node? rd() {
    if (this.pos case var mark) {
      if (this.apply(this.rd) case var $0?) {
        if (this.fq() case var $1?) {
          if ($0 case var $) {
            return OptionalNode($);
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.rd) case var $0?) {
        if (this.fn() case var $1?) {
          if ($0 case var $) {
            return StarNode($);
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.rd) case var $0?) {
        if (this.fm() case var $1?) {
          if ($0 case var $) {
            return PlusNode($);
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.re) case var $?) {
        return $;
      }
    }
  }

  /// `global::prefix`
  Node? re() {
    if (this.pos case var mark) {
      if (this.fo() case var $0?) {
        if (this.apply(this.re) case var $1?) {
          if ($1 case var $) {
            return AndPredicateNode($);
          }
        }
      }
      this.pos = mark;
      if (this.fp() case var $0?) {
        if (this.apply(this.re) case var $1?) {
          if ($1 case var $) {
            return NotPredicateNode($);
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.rf) case var $?) {
        return $;
      }
    }
  }

  /// `global::atom`
  Node? rf() {
    if (this.pos case var mark) {
      if (this.apply(this.rf) case var sep?) {
        if (this.fi() case _?) {
          if (this.f16() case _?) {
            if (this.fv() case _?) {
              if (this.apply(this.r7) case var body?) {
                if (this.fw() case _?) {
                  if (this.fm() case _?) {
                    if (this.fq() case _?) {
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
      if (this.apply(this.rf) case var sep?) {
        if (this.fi() case _?) {
          if (this.f16() case _?) {
            if (this.fv() case _?) {
              if (this.apply(this.r7) case var body?) {
                if (this.fw() case _?) {
                  if (this.fm() case _?) {
                    return PlusSeparatedNode(sep, body, isTrailingAllowed: false);
                  }
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.rf) case var sep?) {
        if (this.fi() case _?) {
          if (this.f16() case _?) {
            if (this.fv() case _?) {
              if (this.apply(this.r7) case var body?) {
                if (this.fw() case _?) {
                  if (this.fn() case _?) {
                    if (this.fq() case _?) {
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
      if (this.apply(this.rf) case var sep?) {
        if (this.fi() case _?) {
          if (this.f16() case _?) {
            if (this.fv() case _?) {
              if (this.apply(this.r7) case var body?) {
                if (this.fw() case _?) {
                  if (this.fn() case _?) {
                    return StarSeparatedNode(sep, body, isTrailingAllowed: false);
                  }
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.rf) case var sep?) {
        if (this.fi() case _?) {
          if (this.f16() case _?) {
            if (this.fv() case _?) {
              if (this.apply(this.r7) case var body?) {
                if (this.fw() case _?) {
                  return PlusSeparatedNode(sep, body, isTrailingAllowed: false);
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.f16() case _?) {
        if (this.ft() case _?) {
          if (this.fm() case _?) {
            if (this.fq() case _?) {
              if (this.fu() case _?) {
                if (this.fv() case _?) {
                  if (this.apply(this.rf) case var sep?) {
                    if (this.fe() case _?) {
                      if (this.apply(this.rf) case var body?) {
                        if (this.fw() case _?) {
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
      if (this.f16() case _?) {
        if (this.ft() case _?) {
          if (this.fn() case _?) {
            if (this.fq() case _?) {
              if (this.fu() case _?) {
                if (this.fv() case _?) {
                  if (this.apply(this.rf) case var sep?) {
                    if (this.fe() case _?) {
                      if (this.apply(this.rf) case var body?) {
                        if (this.fw() case _?) {
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
      if (this.f16() case _?) {
        if (this.ft() case _?) {
          if (this.fm() case _?) {
            if (this.fu() case _?) {
              if (this.fv() case _?) {
                if (this.apply(this.rf) case var sep?) {
                  if (this.fe() case _?) {
                    if (this.apply(this.rf) case var body?) {
                      if (this.fw() case _?) {
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
      if (this.f16() case _?) {
        if (this.ft() case _?) {
          if (this.fn() case _?) {
            if (this.fu() case _?) {
              if (this.fv() case _?) {
                if (this.apply(this.rf) case var sep?) {
                  if (this.fe() case _?) {
                    if (this.apply(this.rf) case var body?) {
                      if (this.fw() case _?) {
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
      if (this.f16() case _?) {
        if (this.fv() case _?) {
          if (this.apply(this.rf) case var sep?) {
            if (this.fe() case _?) {
              if (this.apply(this.rf) case var body?) {
                if (this.fw() case _?) {
                  return PlusSeparatedNode(sep, body, isTrailingAllowed: false);
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.ft() case _?) {
        if (this.apply(this.r7) case var $1?) {
          if (this.fu() case _?) {
            return $1;
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.rg) case var $?) {
        return $;
      }
      this.pos = mark;
      if (this.f7() case var $?) {
        return $;
      }
      this.pos = mark;
      if (this.f9() case var $?) {
        return RegExpNode(RegExp($));
      }
      this.pos = mark;
      if (this.f8() case var $?) {
        return StringLiteralNode($);
      }
      this.pos = mark;
      if (this.f0() case var $?) {
        return ReferenceNode($);
      }
    }
  }

  /// `global::specialSymbol`
  Node? rg() {
    if (this.pos case var mark) {
      if (this.pos case var mark) {
        if (this.fg() case var $?) {
          return const StartOfInputNode();
        }
        this.pos = mark;
        if (this.f1b() case var $?) {
          return const StartOfInputNode();
        }
      }

      this.pos = mark;
      if (this.pos case var mark) {
        if (this.ff() case var $?) {
          return const EndOfInputNode();
        }
        this.pos = mark;
        if (this.f1a() case var $?) {
          return const EndOfInputNode();
        }
      }

      this.pos = mark;
      if (this.pos case var mark) {
        if (this.fi() case var $?) {
          return const AnyCharacterNode();
        }
        this.pos = mark;
        if (this.f18() case var $?) {
          return const AnyCharacterNode();
        }
      }

      this.pos = mark;
      if (this.pos case var mark) {
        if (this.fh() case var $?) {
          return const EpsilonNode();
        }
        this.pos = mark;
        if (this.f19() case var $?) {
          return const EpsilonNode();
        }
      }

      this.pos = mark;
      if (this.f15() case var $?) {
        return const StringLiteralNode(r"\");
      }
      this.pos = mark;
      if (this.f14() case var $?) {
        return SimpleRegExpEscapeNode.digit;
      }
      this.pos = mark;
      if (this.f13() case var $?) {
        return SimpleRegExpEscapeNode.whitespace;
      }
    }
  }

  /// `global::code::balanced`
  String rh() {
    if (this.pos case var mark) {
      if (this.f1r() case var _0) {
        if ([if (_0 case var _0?) _0] case (var code && var _loop2)) {
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
          return code.join();
        }
      }
    }
  }

  /// `global::code::curly`
  String ri() {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$1) case _?) {
        if (this.pos case var mark) {
          if (this.f1s() case var _0) {
            if ([if (_0 case var _0?) _0] case (var inner && var _loop2)) {
              if (_loop2.isNotEmpty) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.f1s() case var _0?) {
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
              if (this.matchPattern(_string.$1) case _?) {
                return inner.join();
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.rh)! case var $) {
        return $;
      }
    }
  }

  /// `global::dart::literal::string::balanced`
  Object rj() {
    if (this.pos case var mark) {
      if (this.f1t() case var _0) {
        if ([if (_0 case var _0?) _0] case (var code && var _loop2)) {
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
          return _loop2;
        }
      }
    }
  }

  /// `global::dart::literal::string::interpolation`
  Object? rk() {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$10) case var $0?) {
        if (this.matchPattern(_string.$26) case var $1?) {
          if (this.apply(this.rj)! case var $2) {
            if (this.matchPattern(_string.$27) case var $3?) {
              return ($0, $1, $2, $3);
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$10) case var $0?) {
        if (this.apply(this.rm) case var $1?) {
          return ($0, $1);
        }
      }
    }
  }

  /// `global::dart::literal::string::main`
  Object? rl() {
    if (this.pos case var mark) {
      if (this.matchPattern(_string.$51) case var $0?) {
        if (this.matchPattern(_string.$43) case var $1?) {
          if (this.pos case var mark) {
            if (this.f1u() case var _0) {
              if ([if (_0 case var _0?) _0] case (var $2 && var body && var _loop2)) {
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
                if (this.matchPattern(_string.$43) case var $3?) {
                  return ($0, $1, $2, $3);
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$51) case var $0?) {
        if (this.matchPattern(_string.$44) case var $1?) {
          if (this.pos case var mark) {
            if (this.f1v() case var _2) {
              if ([if (_2 case var _2?) _2] case (var $2 && var body && var _loop4)) {
                if (_loop4.isNotEmpty) {
                  for (;;) {
                    if (this.pos case var mark) {
                      if (this.f1v() case var _2?) {
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
                if (this.matchPattern(_string.$44) case var $3?) {
                  return ($0, $1, $2, $3);
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$51) case var $0?) {
        if (this.matchPattern(_string.$45) case var $1?) {
          if (this.pos case var mark) {
            if (this.f1w() case var _4) {
              if ([if (_4 case var _4?) _4] case (var $2 && var body && var _loop6)) {
                if (_loop6.isNotEmpty) {
                  for (;;) {
                    if (this.pos case var mark) {
                      if (this.f1w() case var _4?) {
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
                if (this.matchPattern(_string.$45) case var $3?) {
                  return ($0, $1, $2, $3);
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$51) case var $0?) {
        if (this.matchPattern(_string.$46) case var $1?) {
          if (this.pos case var mark) {
            if (this.f1x() case var _6) {
              if ([if (_6 case var _6?) _6] case (var $2 && var body && var _loop8)) {
                if (_loop8.isNotEmpty) {
                  for (;;) {
                    if (this.pos case var mark) {
                      if (this.f1x() case var _6?) {
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
                if (this.matchPattern(_string.$46) case var $3?) {
                  return ($0, $1, $2, $3);
                }
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$43) case var $0?) {
        if (this.pos case var mark) {
          if (this.f1y() case var _8) {
            if ([if (_8 case var _8?) _8] case (var $1 && var body && var _loop10)) {
              if (_loop10.isNotEmpty) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.f1y() case var _8?) {
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
              if (this.matchPattern(_string.$43) case var $2?) {
                return ($0, $1, $2);
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.matchPattern(_string.$44) case var $0?) {
        if (this.pos case var mark) {
          if (this.f1z() case var _10) {
            if ([if (_10 case var _10?) _10] case (var $1 && var body && var _loop12)) {
              if (_loop12.isNotEmpty) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.f1z() case var _10?) {
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
          if (this.f20() case var _12) {
            if ([if (_12 case var _12?) _12] case (var $1 && var body && var _loop14)) {
              if (_loop14.isNotEmpty) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.f20() case var _12?) {
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
          if (this.f21() case var _14) {
            if ([if (_14 case var _14?) _14] case (var $1 && var body && var _loop16)) {
              if (_loop16.isNotEmpty) {
                for (;;) {
                  if (this.pos case var mark) {
                    if (this.f21() case var _14?) {
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
              if (this.matchPattern(_string.$46) case var $2?) {
                return ($0, $1, $2);
              }
            }
          }
        }
      }
    }
  }

  /// `global::dart::literal::identifier`
  String? rm() {
    if (this.fe() case _?) {
      if (this.f22() case var $1?) {
        if (this.fe() case _?) {
          return $1;
        }
      }
    }
  }

  /// `global::dart::literal::string`
  String? rn() {
    if (this.fe() case var $0?) {
      if (this.f23() case var _0?) {
        if ([_0] case (var $1 && var _loop2)) {
          for (;;) {
            if (this.pos case var mark) {
              if (this.fe() case _?) {
                if (this.f23() case var _0?) {
                  _loop2.add(_0);
                  continue;
                }
              }
              this.pos = mark;
              break;
            }
          }
          if (this.fe() case var $2?) {
            if ($1 case var $) {
              return $.join();
            }
          }
        }
      }
    }
  }

  /// `global::type::base`
  String? ro() {
    if (this.f1h() case var _0?) {
      if ([_0] case (var $ && var _loop2)) {
        for (;;) {
          if (this.pos case var mark) {
            if (this.fi() case _?) {
              if (this.f1h() case var _0?) {
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

  /// `global::type::arguments`
  String? rp() {
    if (this.apply(this.rt) case var _0?) {
      if ([_0] case (var $ && var _loop2)) {
        for (;;) {
          if (this.pos case var mark) {
            if (this.fl() case _?) {
              if (this.apply(this.rt) case var _0?) {
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

  /// `global::type::generic`
  String? rq() {
    if (this.apply(this.ro) case var base?) {
      if (this.f10() case _?) {
        if (this.apply(this.rp) case var arguments?) {
          if (this.fz() case _?) {
            return "$base<$arguments>";
          }
        }
      }
    }
  }

  /// `global::type::record`
  String? rr() {
    if (this.pos case var mark) {
      if (this.ft() case var $0?) {
        if (this.f24() case var $1) {
          if (this.fu() case var $2?) {
            return "("+ ($1 == null ?"":"{"+ $1 +"}") +")";
          }
        }
      }
      this.pos = mark;
      if (this.ft() case var $0?) {
        if (this.fb() case var $1?) {
          if (this.fl() case var $2?) {
            if (this.f25() case var $3) {
              if (this.fu() case var $4?) {
                return "("+ $1 +", "+ ($3 == null ?"":"{"+ $3 +"}") +")";
              }
            }
          }
        }
      }
      this.pos = mark;
      if (this.ft() case var $0?) {
        if (this.fd() case var $1?) {
          if (this.f26() case var $2) {
            if (this.fu() case var $3?) {
              return "("+ $1 + ($2 == null ?"":", {"+ $2 +"}") +")";
            }
          }
        }
      }
    }
  }

  /// `global::type::nonNullable`
  String? rs() {
    if (this.fe() case _?) {
      if (this.f27() case var $1?) {
        if (this.fe() case _?) {
          return $1;
        }
      }
    }
  }

  /// `global::type::nullable`
  String? rt() {
    if (this.fe() case _?) {
      if (this.apply(this.rs) case var nonNullable?) {
        if (this.fe() case _?) {
          if (this.fq() case var $3) {
            return $3 == null ?"$nonNullable":"$nonNullable?";
          }
        }
      }
    }
  }

  /// `global::type::main`
  String? ru() {
    if (this.pos case var mark) {
      if (this.fe() case _?) {
        if (this.f1g() case var $1?) {
          if (this.fe() case _?) {
            return $1;
          }
        }
      }
      this.pos = mark;
      if (this.apply(this.rs) case var $?) {
        return $;
      }
    }
  }

  static final _regexp = (
    RegExp("(?:(?:\\s)|(?:\\/{2}.*(?:(?:\\r?\\n)|(?:\$))))*"),
    RegExp("\\d"),
  );
  static const _string = (
    "`",
    "\\",
    "]",
    "d",
    "w",
    "s",
    "D",
    "-",
    "/",
    "\$",
    "^",
    "ε",
    ".",
    "|",
    ":",
    ",",
    "+",
    "*",
    "&",
    "!",
    "?",
    "=",
    ";",
    "(",
    ")",
    "{",
    "}",
    "[",
    ">",
    "<",
    "@",
    "..",
    "sep!",
    "var",
    "any",
    "epsilon",
    "endOfInput",
    "startOfInput",
    "@inline",
    "@fragment",
    "@rule",
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
