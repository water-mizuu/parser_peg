// ignore_for_file: type=lint, body_might_complete_normally_nullable, unused_local_variable, inference_failure_on_function_return_type, unused_import, duplicate_ignore, unused_element, collection_methods_unrelated_type, unused_element, use_setters_to_change_properties

// imports
// ignore_for_file: avoid_positional_boolean_parameters, unnecessary_non_null_assertion, unnecessary_this, unused_element, use_setters_to_change_properties

// ignore: unused_shown_name
import "dart:collection" show DoubleLinkedQueue, HashMap, Queue;
import "dart:math" as math show Random;
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

  void _clearMemo() {
    if (_lrStack.isEmpty) {
      this._memo.clear();
      this._patternMemo.clear();
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
final class Dart extends _PegParser<Record> {
  Dart();

  @override
  get start => f3o;


  /// `global::ABSTRACT`
  String? f0() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$1) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::AS`
  String? f1() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$2) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::ASSERT`
  String? f2() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$3) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::ASYNC`
  String? f3() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$4) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::AUGMENT`
  String? f4() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$5) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::AWAIT`
  String? f5() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$6) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::BASE`
  String? f6() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$7) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::BREAK`
  String? f7() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$8) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::CASE`
  String? f8() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$9) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::CATCH`
  String? f9() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$10) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::CLASS`
  String? fa() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$11) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::CONST`
  String? fb() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$12) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::CONTINUE`
  String? fc() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$13) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::COVARIANT`
  String? fd() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$14) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::DEFAULT`
  String? fe() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$15) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::DEFERRED`
  String? ff() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$16) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::DO`
  String? fg() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$17) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::DYNAMIC`
  String? fh() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$18) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::ELSE`
  String? fi() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$19) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::ENUM`
  String? fj() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$20) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::EXPORT`
  String? fk() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$21) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::EXTENDS`
  String? fl() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$22) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::EXTENSION`
  String? fm() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$23) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::EXTERNAL`
  String? fn() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$24) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::FACTORY`
  String? fo() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$25) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::FALSE`
  String? fp() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$26) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::FINAL`
  String? fq() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$27) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::FINALLY`
  String? fr() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$28) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::FOR`
  String? fs() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$29) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::FUNCTION`
  String? ft() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$30) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::GET`
  String? fu() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$31) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::HIDE`
  String? fv() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$32) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::IF`
  String? fw() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$33) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::IMPLEMENTS`
  String? fx() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$34) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::IMPORT`
  String? fy() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$35) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::IN`
  String? fz() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$36) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::INTERFACE`
  String? f10() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$37) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::IS`
  String? f11() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$38) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::LATE`
  String? f12() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$39) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::LIBRARY`
  String? f13() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$40) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::MIXIN`
  String? f14() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$41) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::NEW`
  String? f15() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$42) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::NULL`
  String? f16() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$43) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::OF`
  String? f17() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$44) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::ON`
  String? f18() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$45) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::OPERATOR`
  String? f19() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$46) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::PART`
  String? f1a() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$47) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::REQUIRED`
  String? f1b() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$48) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::RETHROW`
  String? f1c() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$49) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::RETURN`
  String? f1d() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$50) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::SEALED`
  String? f1e() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$51) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::SET`
  String? f1f() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$52) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::SHOW`
  String? f1g() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$53) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::STATIC`
  String? f1h() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$54) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::SUPER`
  String? f1i() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$55) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::SWITCH`
  String? f1j() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$56) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::SYNC`
  String? f1k() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$57) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::THIS`
  String? f1l() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$58) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::THROW`
  String? f1m() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$59) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::TRUE`
  String? f1n() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$60) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::TRY`
  String? f1o() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$61) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::TYPE`
  String? f1p() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$62) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::TYPEDEF`
  String? f1q() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$63) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::VAR`
  String? f1r() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$64) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::VOID`
  String? f1s() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$65) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::WHILE`
  String? f1t() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$66) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::WITH`
  String? f1u() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$67) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::YIELD`
  String? f1v() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$68) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::WHEN`
  String? f1w() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$69) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::L_PAREN`
  String? f1x() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$70) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::R_PAREN`
  String? f1y() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$71) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::L_SQUARE`
  String? f1z() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$72) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::R_SQUARE`
  String? f20() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$73) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::L_CURLY`
  String? f21() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$74) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::R_CURLY`
  String? f22() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$75) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::COMMA`
  String? f23() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$76) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::COLON`
  String? f24() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$77) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::SEMICOLON`
  String? f25() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$78) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::DOT`
  String? f26() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$79) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::QUESTION`
  String? f27() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$80) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::EQ`
  String? f28() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$81) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::GT`
  String? f29() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$82) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::LT`
  String? f2a() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$83) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::BANG`
  String? f2b() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$84) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::TILDE`
  String? f2c() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$85) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::PLUS`
  String? f2d() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$86) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::MINUS`
  String? f2e() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$87) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::STAR`
  String? f2f() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$88) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::SLASH`
  String? f2g() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$89) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::PERCENT`
  String? f2h() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$90) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::AMP`
  String? f2i() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$91) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::CARET`
  String? f2j() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$92) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::BAR`
  String? f2k() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$93) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::HASH`
  String? f2l() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$94) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::EQ_EQ`
  String? f2m() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$95) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::BANG_EQ`
  String? f2n() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$96) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::GT_EQ`
  String? f2o() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$97) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::LT_EQ`
  String? f2p() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$98) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::AMP_AMP`
  String? f2q() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$99) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::BAR_BAR`
  String? f2r() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$100) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::QUEST_QUEST`
  String? f2s() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$101) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::QUEST_QUEST_EQ`
  String? f2t() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$102) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::PLUS_EQ`
  String? f2u() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$103) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::MINUS_EQ`
  String? f2v() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$104) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::STAR_EQ`
  String? f2w() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$105) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::SLASH_EQ`
  String? f2x() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$106) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::PERCENT_EQ`
  String? f2y() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$107) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::TILDE_SLASH_EQ`
  String? f2z() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$108) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::LT_LT_EQ`
  String? f30() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$109) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::AMP_EQ`
  String? f31() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$110) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::CARET_EQ`
  String? f32() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$111) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::BAR_EQ`
  String? f33() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$112) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::PLUS_PLUS`
  String? f34() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$113) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::MINUS_MINUS`
  String? f35() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$114) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::LT_LT`
  String? f36() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$115) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::TILDE_SLASH`
  String? f37() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$116) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::DOT_DOT`
  String? f38() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$117) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::DOT_DOT_DOT`
  String? f39() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$118) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::QUEST_DOT_DOT`
  String? f3a() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$119) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::DOT_DOT_DOT_QUEST`
  String? f3b() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$120) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::ARROW`
  String? f3c() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$121) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::QUEST_DOT`
  String? f3d() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$122) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::NUMBER`
  String? f3e() {
    if (this.f3m() case _) {
      if (this.fds() case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::HEX_NUMBER`
  String? f3f() {
    if (this.f3m() case _) {
      if (this.fdy() case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::IDENTIFIER`
  String? f3g() {
    if (this.f3m() case _) {
      if (this.fe0() case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::FEFF`
  String? f3h() {
    if (this.matchPattern(_string.$123) case var $?) {
      return $;
    }
  }

  /// `global::SCRIPT_TAG`
  (String, List<String>)? f3i() {
    if (this.matchPattern(_string.$124) case var $0?) {
      if (this.fe2() case var $1) {
        return ($0, $1);
      }
    }
  }

  /// `global::stringLiteral`
  List<(String, List<Object>, String)>? f3j() {
    if (this.f3m() case _) {
      if (this.fek() case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::singleLineString`
  (String, List<Object>, String)? f3k() {
    var _mark = this._mark();
    if (this.matchPattern(_string.$126) case var $0?) {
      if (this.fem() case var $1) {
        if (this.matchPattern(_string.$125) case var $2?) {
          return ($0, $1, $2);
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$128) case var $0?) {
      if (this.feo() case var $1) {
        if (this.matchPattern(_string.$127) case var $2?) {
          return ($0, $1, $2);
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$125) case var $0?) {
      if (this.feq() case var $1) {
        if (this.matchPattern(_string.$125) case var $2?) {
          return ($0, $1, $2);
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$127) case var $0?) {
      if (this.fes() case var $1) {
        if (this.matchPattern(_string.$127) case var $2?) {
          return ($0, $1, $2);
        }
      }
    }
  }

  /// `global::multiLineString`
  (String, List<String>, String)? f3l() {
    var _mark = this._mark();
    if (this.matchPattern(_string.$130) case var $0?) {
      if (this.feu() case var $1) {
        if (this.matchPattern(_string.$129) case var $2?) {
          return ($0, $1, $2);
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$132) case var $0?) {
      if (this.few() case var $1) {
        if (this.matchPattern(_string.$131) case var $2?) {
          return ($0, $1, $2);
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$129) case var $0?) {
      if (this.fey() case var $1) {
        if (this.matchPattern(_string.$129) case var $2?) {
          return ($0, $1, $2);
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$131) case var $0?) {
      if (this.ff0() case var $1) {
        if (this.matchPattern(_string.$131) case var $2?) {
          return ($0, $1, $2);
        }
      }
    }
  }

  /// `global::_`
  List<Object> f3m() {
    var _mark = this._mark();
      if (this.ff6() case var _0) {
        if ([if (_0 case var _0?) _0] case var _l1) {
          if (_l1.isNotEmpty) {
            for (;;) {
              var _mark = this._mark();
              if (this.ff6() case var _0?) {
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

  /// `global::comment`
  Record? f3n() {
    var _mark = this._mark();
    if (this.matchPattern(_string.$133) case var $0?) {
      if (this.ff8() case var $1) {
        return ($0, $1);
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$135) case var $0?) {
      if (this.ffa() case var $1) {
        if (this.matchPattern(_string.$134) case var $2?) {
          return ($0, $1, $2);
        }
      }
    }
  }

  /// `ROOT`
  Record? f3o() {
    if (this.r0() case var $?) {
      return $;
    }
  }

  /// `fragment0`
  String? f3p() {
    if (this.matchPattern(_string.$123) case var $?) {
      return $;
    }
  }

  /// `fragment1`
  String? f3q() {
    var _mark = this._mark();
    if (this.matchRange(_range.$1) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  }

  /// `fragment2`
  List<String> f3r() {
    var _mark = this._mark();
      if (this.f3q() case var _0) {
        if ([if (_0 case var _0?) _0] case var _l1) {
          if (_l1.isNotEmpty) {
            for (;;) {
              var _mark = this._mark();
              if (this.f3q() case var _0?) {
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

  /// `fragment3`
  (String, List<String>)? f3s() {
    if (this.matchPattern(_string.$124) case var $0?) {
      if (this.f3r() case var $1) {
        return ($0, $1);
      }
    }
  }

  /// `fragment4`
  (List<(String, Object)>, Record, String)? f3t() {
    if (this.r47() case var $?) {
      return $;
    }
  }

  /// `fragment5`
  List<Record> f3u() {
    var _mark = this._mark();
      if (this._applyMemo(this.r4a) case var _0) {
        if ([if (_0 case var _0?) _0] case var _l1) {
          if (_l1.isNotEmpty) {
            for (;;) {
              var _mark = this._mark();
              if (this._applyMemo(this.r4a) case var _0?) {
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

  /// `fragment6`
  List<(List<(String, Object)>, String, (List<(String, List<Object>, String)>, List<(String, String, (List<String>, (String, List<(String, List<Object>, String)>)?), String, List<(String, List<Object>, String)>)>), String)> f3v() {
    var _mark = this._mark();
      if (this._applyMemo(this.r4g) case var _0) {
        if ([if (_0 case var _0?) _0] case var _l1) {
          if (_l1.isNotEmpty) {
            for (;;) {
              var _mark = this._mark();
              if (this._applyMemo(this.r4g) case var _0?) {
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

  /// `fragment7`
  (List<(String, Object)>, Record)? f3w() {
    if (this._applyMemo(this.r6)! case var $0) {
      if (this._applyMemo(this.r2) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `fragment8`
  List<(List<(String, Object)>, Record)> f3x() {
    var _mark = this._mark();
      if (this.f3w() case var _0) {
        if ([if (_0 case var _0?) _0] case var _l1) {
          if (_l1.isNotEmpty) {
            for (;;) {
              var _mark = this._mark();
              if (this.f3w() case var _0?) {
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

  /// `fragment9`
  String? f3y() {
    if (this.f4() case var $?) {
      return $;
    }
  }

  /// `fragment10`
  String? f3z() {
    if (this.f4() case var $?) {
      return $;
    }
  }

  /// `fragment11`
  String? f40() {
    if (this.f4() case var $?) {
      return $;
    }
  }

  /// `fragment12`
  String? f41() {
    if (this.f4() case var $?) {
      return $;
    }
  }

  /// `fragment13`
  String? f42() {
    if (this.f4() case var $?) {
      return $;
    }
  }

  /// `fragment14`
  String? f43() {
    if (this.f4() case var $?) {
      return $;
    }
  }

  /// `fragment15`
  Object? f44() {
    var _mark = this._mark();
    if (this._applyMemo(this.r34) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.f25() case var $?) {
      return $;
    }
  }

  /// `fragment16`
  String? f45() {
    if (this.f4() case var $?) {
      return $;
    }
  }

  /// `fragment17`
  Object? f46() {
    var _mark = this._mark();
    if (this._applyMemo(this.r34) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.f25() case var $?) {
      return $;
    }
  }

  /// `fragment18`
  String? f47() {
    if (this.f4() case var $?) {
      return $;
    }
  }

  /// `fragment19`
  Object? f48() {
    var _mark = this._mark();
    if (this._applyMemo(this.r34) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.f25() case var $?) {
      return $;
    }
  }

  /// `fragment20`
  String? f49() {
    if (this.f4() case var $?) {
      return $;
    }
  }

  /// `fragment21`
  String? f4a() {
    var _mark = this._mark();
    if (this.fq() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.fb() case var $?) {
      return $;
    }
  }

  /// `fragment22`
  Object? f4b() {
    if (this._applyMemo(this.re) case var $?) {
      return $;
    }
  }

  /// `fragment23`
  String? f4c() {
    if (this.f4() case var $?) {
      return $;
    }
  }

  /// `fragment24`
  Object? f4d() {
    if (this._applyMemo(this.re) case var $?) {
      return $;
    }
  }

  /// `fragment25`
  String? f4e() {
    if (this.f4() case var $?) {
      return $;
    }
  }

  /// `fragment26`
  String? f4f() {
    if (this.f12() case var $?) {
      return $;
    }
  }

  /// `fragment27`
  Object? f4g() {
    if (this._applyMemo(this.re) case var $?) {
      return $;
    }
  }

  /// `fragment28`
  (String, Object)? f4h() {
    if (this.matchPattern(_string.$136) case var $0?) {
      if (this.r7() case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `fragment29`
  (String, String)? f4i() {
    if (this.f26() case var $0?) {
      if (this._applyMemo(this.r9) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `fragment30`
  (String, String)? f4j() {
    if (this.f26() case var $0?) {
      if (this._applyMemo(this.rc) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `fragment31`
  String? f4k() {
    if (this.f27() case var $?) {
      return $;
    }
  }

  /// `fragment32`
  String? f4l() {
    if (this.f27() case var $?) {
      return $;
    }
  }

  /// `fragment33`
  String? f4m() {
    if (this.f27() case var $?) {
      return $;
    }
  }

  /// `fragment34`
  String? f4n() {
    if (this.f27() case var $?) {
      return $;
    }
  }

  /// `fragment35`
  String? f4o() {
    if (this.f27() case var $?) {
      return $;
    }
  }

  /// `fragment36`
  String? f4p() {
    if (this.f27() case var $?) {
      return $;
    }
  }

  /// `fragment37`
  (String, List<Object>, String)? f4q() {
    if (this._applyMemo(this.rj) case var $?) {
      return $;
    }
  }

  /// `fragment38`
  (String, String)? f4r() {
    if (this._applyMemo(this.rc) case var $0?) {
      if (this.f26() case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `fragment39`
  String? f4s() {
    if (this.f23() case var $?) {
      return $;
    }
  }

  /// `fragment40`
  String? f4t() {
    if (this._applyMemo(this.r7m) case var $?) {
      return $;
    }
  }

  /// `fragment41`
  List<(List<(String, Object)>, (Object, String))>? f4u() {
    if (this.rp() case var _0?) {
      if ([_0] case var _l1) {
        for (;;) {
          var _mark = this._mark();
          if (this.f23() case _?) {
            if (this.rp() case var _0?) {
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

  /// `fragment42`
  String? f4v() {
    if (this.f23() case var $?) {
      return $;
    }
  }

  /// `fragment43`
  Object? f4w() {
    if (this._applyMemo(this.rf) case var $?) {
      return $;
    }
  }

  /// `fragment44`
  String? f4x() {
    if (this.f27() case var $?) {
      return $;
    }
  }

  /// `fragment45`
  ((String, (String, List<(List<(String, Object)>, String, (String, (Record, String?))?)>, String)?, Record), String?)? f4y() {
    if (this._applyMemo(this.rt) case var $0?) {
      if (this.f4x() case var $1) {
        return ($0, $1);
      }
    }
  }

  /// `fragment46`
  List<((String, (String, List<(List<(String, Object)>, String, (String, (Record, String?))?)>, String)?, Record), String?)> f4z() {
    var _mark = this._mark();
      if (this.f4y() case var _0) {
        if ([if (_0 case var _0?) _0] case var _l1) {
          if (_l1.isNotEmpty) {
            for (;;) {
              var _mark = this._mark();
              if (this.f4y() case var _0?) {
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

  /// `fragment47`
  (String, List<(List<(String, Object)>, String, (String, (Record, String?))?)>, String)? f50() {
    if (this._applyMemo(this.r11) case var $?) {
      return $;
    }
  }

  /// `fragment48`
  String? f51() {
    if (this.f23() case var $?) {
      return $;
    }
  }

  /// `fragment49`
  Object? f52() {
    var _mark = this._mark();
    if (this._applyMemo(this.rq) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this._applyMemo(this.re) case var $?) {
      return $;
    }
  }

  /// `fragment50`
  List<(List<(String, Object)>, Object)>? f53() {
    if (this._applyMemo(this.rw) case var _0?) {
      if ([_0] case var _l1) {
        for (;;) {
          var _mark = this._mark();
          if (this.f23() case _?) {
            if (this._applyMemo(this.rw) case var _0?) {
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

  /// `fragment51`
  String? f54() {
    if (this.f23() case var $?) {
      return $;
    }
  }

  /// `fragment52`
  List<(List<(String, Object)>, String?, (Object, String))>? f55() {
    if (this.r10() case var _0?) {
      if ([_0] case var _l1) {
        for (;;) {
          var _mark = this._mark();
          if (this.f23() case _?) {
            if (this.r10() case var _0?) {
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

  /// `fragment53`
  String? f56() {
    if (this.f23() case var $?) {
      return $;
    }
  }

  /// `fragment54`
  String? f57() {
    if (this.f1b() case var $?) {
      return $;
    }
  }

  /// `fragment55`
  List<(List<(String, Object)>, String, (String, (Record, String?))?)>? f58() {
    if (this.r12() case var _0?) {
      if ([_0] case var _l1) {
        for (;;) {
          var _mark = this._mark();
          if (this.f23() case _?) {
            if (this.r12() case var _0?) {
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

  /// `fragment56`
  (String, (Record, String?))? f59() {
    if (this.fl() case var $0?) {
      if (this._applyMemo(this.rg) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `fragment57`
  String? f5a() {
    if (this.f4() case var $?) {
      return $;
    }
  }

  /// `fragment58`
  Object f5b() {
    var _mark = this._mark();
    if (this.r15() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this._applyMemo(this.r14)! case var $) {
      return $;
    }
  }

  /// `fragment59`
  Record? f5c() {
    if (this.r18() case var $?) {
      return $;
    }
  }

  /// `fragment60`
  (String, List<((String, Object?)?, Object?)>)? f5d() {
    if (this._applyMemo(this.r1a) case var $?) {
      return $;
    }
  }

  /// `fragment61`
  String? f5e() {
    if (this.f14() case var $?) {
      return $;
    }
  }

  /// `fragment62`
  String? f5f() {
    if (this.f0() case var $?) {
      return $;
    }
  }

  /// `fragment63`
  String? f5g() {
    var _mark = this._mark();
    if (this.f6() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.f10() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.fq() case var $?) {
      return $;
    }
  }

  /// `fragment64`
  String? f5h() {
    if (this.f0() case var $?) {
      return $;
    }
  }

  /// `fragment65`
  String? f5i() {
    if (this.f6() case var $?) {
      return $;
    }
  }

  /// `fragment66`
  (String, List<(List<(String, Object)>, String, (String, (Record, String?))?)>, String)? f5j() {
    if (this._applyMemo(this.r11) case var $?) {
      return $;
    }
  }

  /// `fragment67`
  (String, List<((String, Object?)?, Object?)>)? f5k() {
    if (this._applyMemo(this.r19) case var $?) {
      return $;
    }
  }

  /// `fragment68`
  String? f5l() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$67) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `fragment69`
  (String, List<((String, Object?)?, Object?)>)? f5m() {
    if (this._applyMemo(this.r1a) case var $?) {
      return $;
    }
  }

  /// `fragment70`
  String? f5n() {
    if (this.f4() case var $?) {
      return $;
    }
  }

  /// `fragment71`
  (List<(String, Object)>, String?, (Record, Object))? f5o() {
    if (this._applyMemo(this.r6)! case var $0) {
      if (this.f5n() case var $1) {
        if (this.r1g() case var $2?) {
          return ($0, $1, $2);
        }
      }
    }
  }

  /// `fragment72`
  String? f5p() {
    if (this.f1h() case var $?) {
      return $;
    }
  }

  /// `fragment73`
  String? f5q() {
    if (this.f1h() case var $?) {
      return $;
    }
  }

  /// `fragment74`
  String? f5r() {
    if (this.f1h() case var $?) {
      return $;
    }
  }

  /// `fragment75`
  String? f5s() {
    if (this.fn() case var $?) {
      return $;
    }
  }

  /// `fragment76`
  String? f5t() {
    if (this.fn() case var $?) {
      return $;
    }
  }

  /// `fragment77`
  String? f5u() {
    if (this.f1h() case var $?) {
      return $;
    }
  }

  /// `fragment78`
  String? f5v() {
    if (this.fn() case var $?) {
      return $;
    }
  }

  /// `fragment79`
  String? f5w() {
    if (this.f1h() case var $?) {
      return $;
    }
  }

  /// `fragment80`
  String? f5x() {
    if (this.fn() case var $?) {
      return $;
    }
  }

  /// `fragment81`
  String? f5y() {
    if (this.f1h() case var $?) {
      return $;
    }
  }

  /// `fragment82`
  String? f5z() {
    if (this.f1h() case var $?) {
      return $;
    }
  }

  /// `fragment83`
  (String?, Object)? f60() {
    var _mark = this._mark();
    if (this.f5z() case var $0) {
      if (this._applyMemo(this.r3) case var $1?) {
        return ($0, $1);
      }
    }
    this._recover(_mark);
    if (this.fd() case var $0?) {
      if (this._applyMemo(this.r4) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `fragment84`
  String? f61() {
    if (this.fn() case var $?) {
      return $;
    }
  }

  /// `fragment85`
  Object? f62() {
    var _mark = this._mark();
    if (this._applyMemo(this.r3) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.fd() case var $0?) {
      if (this._applyMemo(this.r4) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `fragment86`
  String? f63() {
    var _mark = this._mark();
    if (this.fq() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.fb() case var $?) {
      return $;
    }
  }

  /// `fragment87`
  Object? f64() {
    if (this._applyMemo(this.re) case var $?) {
      return $;
    }
  }

  /// `fragment88`
  Object? f65() {
    if (this._applyMemo(this.re) case var $?) {
      return $;
    }
  }

  /// `fragment89`
  String? f66() {
    if (this.f12() case var $?) {
      return $;
    }
  }

  /// `fragment90`
  Object? f67() {
    if (this._applyMemo(this.re) case var $?) {
      return $;
    }
  }

  /// `fragment91`
  String? f68() {
    if (this.f12() case var $?) {
      return $;
    }
  }

  /// `fragment92`
  String? f69() {
    if (this.f12() case var $?) {
      return $;
    }
  }

  /// `fragment93`
  Object? f6a() {
    if (this._applyMemo(this.re) case var $?) {
      return $;
    }
  }

  /// `fragment94`
  Object? f6b() {
    var _mark = this._mark();
    if (this.fq() case var $0?) {
      if (this.f6a() case var $1) {
        return ($0, $1);
      }
    }
    this._recover(_mark);
    if (this._applyMemo(this.r4) case var $?) {
      return $;
    }
  }

  /// `fragment95`
  Record? f6c() {
    var _mark = this._mark();
    if (this._applyMemo(this.r2a) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this._applyMemo(this.r26) case var $?) {
      return $;
    }
  }

  /// `fragment96`
  Record? f6d() {
    var _mark = this._mark();
    if (this._applyMemo(this.r2a) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this._applyMemo(this.r26) case var $?) {
      return $;
    }
  }

  /// `fragment97`
  Object? f6e() {
    if (this._applyMemo(this.re) case var $?) {
      return $;
    }
  }

  /// `fragment98`
  Object? f6f() {
    if (this._applyMemo(this.re) case var $?) {
      return $;
    }
  }

  /// `fragment99`
  Object? f6g() {
    if (this._applyMemo(this.re) case var $?) {
      return $;
    }
  }

  /// `fragment100`
  (String, Object?)? f6h() {
    var _mark = this._mark();
    if (this.r1r() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.r1s() case var $?) {
      return $;
    }
  }

  /// `fragment101`
  (String, String)? f6i() {
    if (this.f26() case var $0?) {
      if (this._applyMemo(this.r9) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `fragment102`
  String? f6j() {
    if (this._applyMemo(this.r7m) case var $?) {
      return $;
    }
  }

  /// `fragment103`
  String? f6k() {
    if (this.fb() case var $?) {
      return $;
    }
  }

  /// `fragment104`
  (String, String)? f6l() {
    if (this.f26() case var $0?) {
      if (this._applyMemo(this.r9) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `fragment105`
  (String, List<Record>)? f6m() {
    if (this._applyMemo(this.r26) case var $?) {
      return $;
    }
  }

  /// `fragment106`
  String? f6n() {
    if (this.f23() case var $?) {
      return $;
    }
  }

  /// `fragment107`
  String? f6o() {
    if (this.fd() case var $?) {
      return $;
    }
  }

  /// `fragment108`
  String? f6p() {
    var _mark = this._mark();
    if (this.f1r() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.fq() case var $?) {
      return $;
    }
  }

  /// `fragment109`
  Object? f6q() {
    if (this._applyMemo(this.re) case var $?) {
      return $;
    }
  }

  /// `fragment110`
  String? f6r() {
    if (this.f27() case var $?) {
      return $;
    }
  }

  /// `fragment111`
  String? f6s() {
    if (this.fd() case var $?) {
      return $;
    }
  }

  /// `fragment112`
  String? f6t() {
    var _mark = this._mark();
    if (this.f1r() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.fq() case var $?) {
      return $;
    }
  }

  /// `fragment113`
  Object? f6u() {
    if (this._applyMemo(this.re) case var $?) {
      return $;
    }
  }

  /// `fragment114`
  List<((List<(String, Object)>, Record), (String, Record)?)>? f6v() {
    if (this.r23() case var _0?) {
      if ([_0] case var _l1) {
        for (;;) {
          var _mark = this._mark();
          if (this.f23() case _?) {
            if (this.r23() case var _0?) {
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

  /// `fragment115`
  String? f6w() {
    if (this.f23() case var $?) {
      return $;
    }
  }

  /// `fragment116`
  (String, Record)? f6x() {
    if (this.f28() case var $0?) {
      if (this._applyMemo(this.r4n) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `fragment117`
  List<(List<(String, Object)>, String?, Record, (String, Record)?)>? f6y() {
    if (this.r25() case var _0?) {
      if ([_0] case var _l1) {
        for (;;) {
          var _mark = this._mark();
          if (this.f23() case _?) {
            if (this.r25() case var _0?) {
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

  /// `fragment118`
  String? f6z() {
    if (this.f23() case var $?) {
      return $;
    }
  }

  /// `fragment119`
  String? f70() {
    if (this.f1b() case var $?) {
      return $;
    }
  }

  /// `fragment120`
  (String, Record)? f71() {
    if (this.f28() case var $0?) {
      if (this._applyMemo(this.r4n) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `fragment121`
  List<Record>? f72() {
    if (this.r27() case var _0?) {
      if ([_0] case var _l1) {
        for (;;) {
          var _mark = this._mark();
          if (this.f23() case _?) {
            if (this.r27() case var _0?) {
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

  /// `fragment122`
  (String, String)? f73() {
    if (this.f1l() case var $0?) {
      if (this.f26() case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `fragment123`
  (String, String)? f74() {
    if (this.f26() case var $0?) {
      if (this._applyMemo(this.r9) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `fragment124`
  String? f75() {
    if (this.fb() case var $?) {
      return $;
    }
  }

  /// `fragment125`
  String? f76() {
    if (this.fb() case var $?) {
      return $;
    }
  }

  /// `fragment126`
  String? f77() {
    if (this._applyMemo(this.r7m) case var $?) {
      return $;
    }
  }

  /// `fragment127`
  String? f78() {
    if (this.f6() case var $?) {
      return $;
    }
  }

  /// `fragment128`
  (String, List<((String, Object?)?, Object?)>)? f79() {
    if (this.f18() case var $0?) {
      if (this._applyMemo(this.r1b) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `fragment129`
  (String, List<((String, Object?)?, Object?)>)? f7a() {
    if (this._applyMemo(this.r1a) case var $?) {
      return $;
    }
  }

  /// `fragment130`
  String? f7b() {
    if (this.f6() case var $?) {
      return $;
    }
  }

  /// `fragment131`
  (String, List<((String, Object?)?, Object?)>)? f7c() {
    if (this._applyMemo(this.r1a) case var $?) {
      return $;
    }
  }

  /// `fragment132`
  (String, List<((String, Object?)?, Object?)>)? f7d() {
    if (this._applyMemo(this.r1a) case var $?) {
      return $;
    }
  }

  /// `fragment133`
  (String, List<((String, Object?)?, Object?)>)? f7e() {
    if (this._applyMemo(this.r1a) case var $?) {
      return $;
    }
  }

  /// `fragment134`
  String? f7f() {
    if (this._applyMemo(this.rd) case var $?) {
      return $;
    }
  }

  /// `fragment135`
  (String, List<(List<(String, Object)>, String, (String, (Record, String?))?)>, String)? f7g() {
    if (this._applyMemo(this.r11) case var $?) {
      return $;
    }
  }

  /// `fragment136`
  (String, List<(List<(String, Object)>, String, (String, (Record, String?))?)>, String)? f7h() {
    if (this._applyMemo(this.r11) case var $?) {
      return $;
    }
  }

  /// `fragment137`
  String? f7i() {
    if (this.f4() case var $?) {
      return $;
    }
  }

  /// `fragment138`
  String? f7j() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$20) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `fragment139`
  (String, List<((String, Object?)?, Object?)>)? f7k() {
    if (this._applyMemo(this.r19) case var $?) {
      return $;
    }
  }

  /// `fragment140`
  (String, List<((String, Object?)?, Object?)>)? f7l() {
    if (this._applyMemo(this.r1a) case var $?) {
      return $;
    }
  }

  /// `fragment141`
  List<Record>? f7m() {
    if (this.r2l() case var _0?) {
      if ([_0] case var _l1) {
        for (;;) {
          var _mark = this._mark();
          if (this.f23() case _?) {
            if (this.r2l() case var _0?) {
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

  /// `fragment142`
  String? f7n() {
    if (this.f23() case var $?) {
      return $;
    }
  }

  /// `fragment143`
  (List<Record>, String?)? f7o() {
    if (this.f7m() case var $0?) {
      if (this.f7n() case var $1) {
        return ($0, $1);
      }
    }
  }

  /// `fragment144`
  (String, List<(List<(String, Object)>, String?, (Record, Object))>)? f7p() {
    if (this.f25() case var $0?) {
      if (this._applyMemo(this.r1f)! case var $1) {
        return ($0, $1);
      }
    }
  }

  /// `fragment145`
  String? f7q() {
    if (this.f4() case var $?) {
      return $;
    }
  }

  /// `fragment146`
  ((String, List<Object>, String)?, (String, (List<((String, String)?, Record)>, String?)?, String))? f7r() {
    if (this._applyMemo(this.r6m) case var $?) {
      return $;
    }
  }

  /// `fragment147`
  String? f7s() {
    if (this.f4() case var $?) {
      return $;
    }
  }

  /// `fragment148`
  (String, List<Object>, String)? f7t() {
    if (this._applyMemo(this.rj) case var $?) {
      return $;
    }
  }

  /// `fragment149`
  String? f7u() {
    if (this.f4() case var $?) {
      return $;
    }
  }

  /// `fragment150`
  String? f7v() {
    if (this.f4() case var $?) {
      return $;
    }
  }

  /// `fragment151`
  Object? f7w() {
    if (this._applyMemo(this.re) case var $?) {
      return $;
    }
  }

  /// `fragment152`
  (String, List<(List<(String, Object)>, String, (String, (Record, String?))?)>, String)? f7x() {
    if (this._applyMemo(this.r11) case var $?) {
      return $;
    }
  }

  /// `fragment153`
  String? f7y() {
    if (this.f23() case var $?) {
      return $;
    }
  }

  /// `fragment154`
  String? f7z() {
    if (this.fd() case var $?) {
      return $;
    }
  }

  /// `fragment155`
  Object? f80() {
    if (this._applyMemo(this.re) case var $?) {
      return $;
    }
  }

  /// `fragment156`
  String? f81() {
    if (this.f27() case var $?) {
      return $;
    }
  }

  /// `fragment157`
  String? f82() {
    if (this.fd() case var $?) {
      return $;
    }
  }

  /// `fragment158`
  Object? f83() {
    if (this._applyMemo(this.re) case var $?) {
      return $;
    }
  }

  /// `fragment159`
  Object? f84() {
    if (this._applyMemo(this.re) case var $?) {
      return $;
    }
  }

  /// `fragment160`
  String? f85() {
    if (this.f27() case var $?) {
      return $;
    }
  }

  /// `fragment161`
  (((String, List<(List<(String, Object)>, String, (String, (Record, String?))?)>, String)?, Record), String?)? f86() {
    if (this._applyMemo(this.r2q) case var $0?) {
      if (this.f85() case var $1) {
        return ($0, $1);
      }
    }
  }

  /// `fragment162`
  Object? f87() {
    if (this._applyMemo(this.re) case var $?) {
      return $;
    }
  }

  /// `fragment163`
  String? f88() {
    if (this.f27() case var $?) {
      return $;
    }
  }

  /// `fragment164`
  (((String, List<(List<(String, Object)>, String, (String, (Record, String?))?)>, String)?, Record), String?)? f89() {
    if (this._applyMemo(this.r2q) case var $0?) {
      if (this.f88() case var $1) {
        return ($0, $1);
      }
    }
  }

  /// `fragment165`
  List<((List<(String, Object)>, Record), (String, Record)?)>? f8a() {
    if (this.r31() case var _0?) {
      if ([_0] case var _l1) {
        for (;;) {
          var _mark = this._mark();
          if (this.f23() case _?) {
            if (this.r31() case var _0?) {
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

  /// `fragment166`
  String? f8b() {
    if (this.f23() case var $?) {
      return $;
    }
  }

  /// `fragment167`
  (String, Record)? f8c() {
    if (this.f28() case var $0?) {
      if (this._applyMemo(this.r4n) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `fragment168`
  List<(List<(String, Object)>, String?, Record, (String, Record)?)>? f8d() {
    if (this.r33() case var _0?) {
      if ([_0] case var _l1) {
        for (;;) {
          var _mark = this._mark();
          if (this.f23() case _?) {
            if (this.r33() case var _0?) {
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

  /// `fragment169`
  String? f8e() {
    if (this.f23() case var $?) {
      return $;
    }
  }

  /// `fragment170`
  String? f8f() {
    if (this.f1b() case var $?) {
      return $;
    }
  }

  /// `fragment171`
  (String, Record)? f8g() {
    if (this.f28() case var $0?) {
      if (this._applyMemo(this.r4n) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `fragment172`
  Object? f8h() {
    var _mark = this._mark();
    if (this.f3() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.f3() case var $0?) {
      if (this.f2f() case var $1?) {
        return ($0, $1);
      }
    }
    this._recover(_mark);
    if (this.f1k() case var $0?) {
      if (this.f2f() case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `fragment173`
  List<(String, String)> f8i() {
    var _mark = this._mark();
      if (this._applyMemo(this.r39) case var _0) {
        if ([if (_0 case var _0?) _0] case var _l1) {
          if (_l1.isNotEmpty) {
            for (;;) {
              var _mark = this._mark();
              if (this._applyMemo(this.r39) case var _0?) {
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

  /// `fragment174`
  Record? f8j() {
    if (this._applyMemo(this.r4n) case var $?) {
      return $;
    }
  }

  /// `fragment175`
  (String, Record)? f8k() {
    if (this.f28() case var $0?) {
      if (this._applyMemo(this.r4n) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `fragment176`
  (String, (String, (String, Record)?))? f8l() {
    if (this.f23() case var $0?) {
      if (this._applyMemo(this.r3f) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `fragment177`
  List<(String, (String, (String, Record)?))> f8m() {
    var _mark = this._mark();
      if (this.f8l() case var _0) {
        if ([if (_0 case var _0?) _0] case var _l1) {
          if (_l1.isNotEmpty) {
            for (;;) {
              var _mark = this._mark();
              if (this.f8l() case var _0?) {
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

  /// `fragment178`
  String? f8n() {
    if (this.fd() case var $?) {
      return $;
    }
  }

  /// `fragment179`
  String? f8o() {
    if (this.f12() case var $?) {
      return $;
    }
  }

  /// `fragment180`
  Object? f8p() {
    if (this._applyMemo(this.re) case var $?) {
      return $;
    }
  }

  /// `fragment181`
  Object? f8q() {
    if (this._applyMemo(this.re) case var $?) {
      return $;
    }
  }

  /// `fragment182`
  String? f8r() {
    if (this.f12() case var $?) {
      return $;
    }
  }

  /// `fragment183`
  (String, Record)? f8s() {
    if (this.f28() case var $0?) {
      if (this._applyMemo(this.r4n) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `fragment184`
  String? f8t() {
    var _mark = this._mark();
    if (this.fq() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.f1r() case var $?) {
      return $;
    }
  }

  /// `fragment185`
  (String, (List<(String, String)>, Record))? f8u() {
    if (this.fi() case var $0?) {
      if (this._applyMemo(this.r37) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `fragment186`
  (String, (((Object, List<(String, Object)>), List<(String, (Object, List<(String, Object)>))>), (String, Record)?))? f8v() {
    if (this.f8() case var $0?) {
      if (this._applyMemo(this.r7h) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `fragment187`
  String? f8w() {
    if (this.f5() case var $?) {
      return $;
    }
  }

  /// `fragment188`
  String? f8x() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$36) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `fragment189`
  Record? f8y() {
    if (this._applyMemo(this.r4n) case var $?) {
      return $;
    }
  }

  /// `fragment190`
  List<Record>? f8z() {
    if (this.r4p() case var $?) {
      return $;
    }
  }

  /// `fragment191`
  Record? f90() {
    if (this._applyMemo(this.r4n) case var $?) {
      return $;
    }
  }

  /// `fragment192`
  String? f91() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$17) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `fragment193`
  List<(List<(String, String)>, String, (((Object, List<(String, Object)>), List<(String, (Object, List<(String, Object)>))>), (String, Record)?), String, List<(List<(String, String)>, Record)>)> f92() {
    var _mark = this._mark();
      if (this.r3t() case var _0) {
        if ([if (_0 case var _0?) _0] case var _l1) {
          if (_l1.isNotEmpty) {
            for (;;) {
              var _mark = this._mark();
              if (this.r3t() case var _0?) {
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

  /// `fragment194`
  (List<(String, String)>, String, String, List<(List<(String, String)>, Record)>)? f93() {
    if (this.r3u() case var $?) {
      return $;
    }
  }

  /// `fragment195`
  List<(String, String)> f94() {
    var _mark = this._mark();
      if (this._applyMemo(this.r39) case var _0) {
        if ([if (_0 case var _0?) _0] case var _l1) {
          if (_l1.isNotEmpty) {
            for (;;) {
              var _mark = this._mark();
              if (this._applyMemo(this.r39) case var _0?) {
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

  /// `fragment196`
  List<(String, String)> f95() {
    var _mark = this._mark();
      if (this._applyMemo(this.r39) case var _0) {
        if ([if (_0 case var _0?) _0] case var _l1) {
          if (_l1.isNotEmpty) {
            for (;;) {
              var _mark = this._mark();
              if (this._applyMemo(this.r39) case var _0?) {
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

  /// `fragment197`
  String? f96() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$15) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `fragment198`
  String? f97() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$49) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `fragment199`
  String? f98() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$61) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `fragment200`
  List<Record>? f99() {
    if (this.r3x() case var _0?) {
      if ([_0] case var _l1) {
        for (;;) {
          var _mark = this._mark();
          if (this.r3x() case var _0?) {
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

  /// `fragment201`
  (String, (String, List<(List<(String, String)>, Record)>, String))? f9a() {
    if (this._applyMemo(this.r3z) case var $?) {
      return $;
    }
  }

  /// `fragment202`
  (Object, Record?)? f9b() {
    var _mark = this._mark();
    if (this.f99() case var $0?) {
      if (this.f9a() case var $1) {
        return ($0, $1);
      }
    }
    this._recover(_mark);
    if (this._applyMemo(this.r3z) case var $?) {
      return $;
    }
  }

  /// `fragment203`
  (String, String, String, (String, String)?, String)? f9c() {
    if (this._applyMemo(this.r3y) case var $?) {
      return $;
    }
  }

  /// `fragment204`
  String? f9d() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$10) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `fragment205`
  (String, String)? f9e() {
    if (this.f23() case var $0?) {
      if (this._applyMemo(this.r7m) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `fragment206`
  String? f9f() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$28) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `fragment207`
  String? f9g() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$50) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `fragment208`
  Record? f9h() {
    if (this._applyMemo(this.r4n) case var $?) {
      return $;
    }
  }

  /// `fragment209`
  String? f9i() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$8) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `fragment210`
  String? f9j() {
    if (this._applyMemo(this.r7m) case var $?) {
      return $;
    }
  }

  /// `fragment211`
  String? f9k() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$13) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `fragment212`
  String? f9l() {
    if (this._applyMemo(this.r7m) case var $?) {
      return $;
    }
  }

  /// `fragment213`
  String? f9m() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$3) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `fragment214`
  (String, Record)? f9n() {
    if (this.f23() case var $0?) {
      if (this._applyMemo(this.r4n) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `fragment215`
  String? f9o() {
    if (this.f23() case var $?) {
      return $;
    }
  }

  /// `fragment216`
  List<String>? f9p() {
    if (this._applyMemo(this.r49) case var $?) {
      return $;
    }
  }

  /// `fragment217`
  String? f9q() {
    if (this.ff() case var $?) {
      return $;
    }
  }

  /// `fragment218`
  (String?, String, String)? f9r() {
    if (this.f9q() case var $0) {
      if (this.f1() case var $1?) {
        if (this._applyMemo(this.rc) case var $2?) {
          return ($0, $1, $2);
        }
      }
    }
  }

  /// `fragment219`
  List<(String, List<String>)> f9s() {
    var _mark = this._mark();
      if (this._applyMemo(this.r4e) case var _0) {
        if ([if (_0 case var _0?) _0] case var _l1) {
          if (_l1.isNotEmpty) {
            for (;;) {
              var _mark = this._mark();
              if (this._applyMemo(this.r4e) case var _0?) {
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

  /// `fragment220`
  List<(String, List<String>)> f9t() {
    var _mark = this._mark();
      if (this._applyMemo(this.r4e) case var _0) {
        if ([if (_0 case var _0?) _0] case var _l1) {
          if (_l1.isNotEmpty) {
            for (;;) {
              var _mark = this._mark();
              if (this._applyMemo(this.r4e) case var _0?) {
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

  /// `fragment221`
  List<Record> f9u() {
    var _mark = this._mark();
      if (this._applyMemo(this.r4a) case var _0) {
        if ([if (_0 case var _0?) _0] case var _l1) {
          if (_l1.isNotEmpty) {
            for (;;) {
              var _mark = this._mark();
              if (this._applyMemo(this.r4a) case var _0?) {
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

  /// `fragment222`
  List<(List<(String, Object)>, String, (List<(String, List<Object>, String)>, List<(String, String, (List<String>, (String, List<(String, List<Object>, String)>)?), String, List<(String, List<Object>, String)>)>), String)> f9v() {
    var _mark = this._mark();
      if (this._applyMemo(this.r4g) case var _0) {
        if ([if (_0 case var _0?) _0] case var _l1) {
          if (_l1.isNotEmpty) {
            for (;;) {
              var _mark = this._mark();
              if (this._applyMemo(this.r4g) case var _0?) {
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

  /// `fragment223`
  (List<(String, Object)>, Record)? f9w() {
    if (this._applyMemo(this.r6)! case var $0) {
      if (this._applyMemo(this.r2) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `fragment224`
  List<(List<(String, Object)>, Record)> f9x() {
    var _mark = this._mark();
      if (this.f9w() case var _0) {
        if ([if (_0 case var _0?) _0] case var _l1) {
          if (_l1.isNotEmpty) {
            for (;;) {
              var _mark = this._mark();
              if (this.f9w() case var _0?) {
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

  /// `fragment225`
  List<(String, String, (List<String>, (String, List<(String, List<Object>, String)>)?), String, List<(String, List<Object>, String)>)> f9y() {
    var _mark = this._mark();
      if (this.r4l() case var _0) {
        if ([if (_0 case var _0?) _0] case var _l1) {
          if (_l1.isNotEmpty) {
            for (;;) {
              var _mark = this._mark();
              if (this.r4l() case var _0?) {
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

  /// `fragment226`
  (String, List<(String, List<Object>, String)>)? f9z() {
    if (this.f2m() case var $0?) {
      if (this.f3j() case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `fragment227`
  List<String> fa0() {
    var _mark = this._mark();
      if (this.matchPattern(_string.$137) case var _0) {
        if ([if (_0 case var _0?) _0] case var _l1) {
          if (_l1.isNotEmpty) {
            for (;;) {
              var _mark = this._mark();
              if (this.matchPattern(_string.$137) case var _0?) {
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

  /// `fragment228`
  (List<String>, String)? fa1() {
    if (this.fa0() case var $0) {
      if (this.matchRange(_range.$2) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `fragment229`
  List<(List<String>, String)> fa2() {
    var _mark = this._mark();
      if (this.fa1() case var _0) {
        if ([if (_0 case var _0?) _0] case var _l1) {
          if (_l1.isNotEmpty) {
            for (;;) {
              var _mark = this._mark();
              if (this.fa1() case var _0?) {
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

  /// `fragment230`
  (String, List<(List<String>, String)>)? fa3() {
    if (this.matchRange(_range.$2) case var $0?) {
      if (this.fa2() case var $1) {
        return ($0, $1);
      }
    }
  }

  /// `fragment231`
  List<String> fa4() {
    var _mark = this._mark();
      if (this.matchPattern(_string.$137) case var _0) {
        if ([if (_0 case var _0?) _0] case var _l1) {
          if (_l1.isNotEmpty) {
            for (;;) {
              var _mark = this._mark();
              if (this.matchPattern(_string.$137) case var _0?) {
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

  /// `fragment232`
  (List<String>, String)? fa5() {
    if (this.fa4() case var $0) {
      if (this.matchRange(_range.$2) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `fragment233`
  List<(List<String>, String)> fa6() {
    var _mark = this._mark();
      if (this.fa5() case var _0) {
        if ([if (_0 case var _0?) _0] case var _l1) {
          if (_l1.isNotEmpty) {
            for (;;) {
              var _mark = this._mark();
              if (this.fa5() case var _0?) {
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

  /// `fragment234`
  (String, List<(List<String>, String)>)? fa7() {
    if (this.matchRange(_range.$2) case var $0?) {
      if (this.fa6() case var $1) {
        return ($0, $1);
      }
    }
  }

  /// `fragment235`
  (String, (String, List<(List<String>, String)>))? fa8() {
    if (this.f26() case var $0?) {
      if (this.fa7() case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `fragment236`
  String? fa9() {
    if (this.matchRange(_range.$3) case var $?) {
      return $;
    }
  }

  /// `fragment237`
  List<String> faa() {
    var _mark = this._mark();
      if (this.matchPattern(_string.$137) case var _0) {
        if ([if (_0 case var _0?) _0] case var _l1) {
          if (_l1.isNotEmpty) {
            for (;;) {
              var _mark = this._mark();
              if (this.matchPattern(_string.$137) case var _0?) {
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

  /// `fragment238`
  (List<String>, String)? fab() {
    if (this.faa() case var $0) {
      if (this.matchRange(_range.$2) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `fragment239`
  List<(List<String>, String)> fac() {
    var _mark = this._mark();
      if (this.fab() case var _0) {
        if ([if (_0 case var _0?) _0] case var _l1) {
          if (_l1.isNotEmpty) {
            for (;;) {
              var _mark = this._mark();
              if (this.fab() case var _0?) {
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

  /// `fragment240`
  (String, List<(List<String>, String)>)? fad() {
    if (this.matchRange(_range.$2) case var $0?) {
      if (this.fac() case var $1) {
        return ($0, $1);
      }
    }
  }

  /// `fragment241`
  (String, String?, (String, List<(List<String>, String)>))? fae() {
    if (this.matchRange(_range.$4) case var $0?) {
      if (this.fa9() case var $1) {
        if (this.fad() case var $2?) {
          return ($0, $1, $2);
        }
      }
    }
  }

  /// `fragment242`
  String? faf() {
    if (this.pos case var from) {
      if (this.fa3() case _?) {
        if (this.fa8() case _) {
          if (this.fae() case _) {
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

  /// `fragment243`
  String? fag() {
    var _mark = this._mark();
    if (this.matchPattern(_string.$138) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$139) case var $?) {
      return $;
    }
  }

  /// `fragment244`
  List<String> fah() {
    var _mark = this._mark();
      if (this.matchPattern(_string.$137) case var _0) {
        if ([if (_0 case var _0?) _0] case var _l1) {
          if (_l1.isNotEmpty) {
            for (;;) {
              var _mark = this._mark();
              if (this.matchPattern(_string.$137) case var _0?) {
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

  /// `fragment245`
  (List<String>, String)? fai() {
    if (this.fah() case var $0) {
      if (this.matchRange(_range.$5) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `fragment246`
  List<(List<String>, String)> faj() {
    var _mark = this._mark();
      if (this.fai() case var _0) {
        if ([if (_0 case var _0?) _0] case var _l1) {
          if (_l1.isNotEmpty) {
            for (;;) {
              var _mark = this._mark();
              if (this.fai() case var _0?) {
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

  /// `fragment247`
  (String, List<(List<String>, String)>)? fak() {
    if (this.matchRange(_range.$5) case var $0?) {
      if (this.faj() case var $1) {
        return ($0, $1);
      }
    }
  }

  /// `fragment248`
  String? fal() {
    if (this.pos case var from) {
      if (this.fag() case _?) {
        if (this.fak() case _?) {
          if (this.pos case var to) {
            if (this.buffer.substring(from, to) case var span) {
              return span;
            }
          }
        }
      }
    }
  }

  /// `fragment249`
  String? fam() {
    if (this.fb() case var $?) {
      return $;
    }
  }

  /// `fragment250`
  (String, List<Object>, String)? fan() {
    if (this._applyMemo(this.rj) case var $?) {
      return $;
    }
  }

  /// `fragment251`
  List<Record>? fao() {
    if (this._applyMemo(this.r51) case var $?) {
      return $;
    }
  }

  /// `fragment252`
  String? fap() {
    if (this.fb() case var $?) {
      return $;
    }
  }

  /// `fragment253`
  (String, List<Object>, String)? faq() {
    if (this._applyMemo(this.rj) case var $?) {
      return $;
    }
  }

  /// `fragment254`
  List<Record>? far() {
    if (this._applyMemo(this.r51) case var $?) {
      return $;
    }
  }

  /// `fragment255`
  String? fas() {
    if (this.fb() case var $?) {
      return $;
    }
  }

  /// `fragment256`
  String? fat() {
    if (this.f23() case var $?) {
      return $;
    }
  }

  /// `fragment257`
  (String, ((String, String)?, Record))? fau() {
    if (this.f23() case var $0?) {
      if (this._applyMemo(this.r50) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `fragment258`
  List<(String, ((String, String)?, Record))>? fav() {
    if (this.fau() case var _0?) {
      if ([_0] case var _l1) {
        for (;;) {
          var _mark = this._mark();
          if (this.fau() case var _0?) {
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

  /// `fragment259`
  String? faw() {
    if (this.f23() case var $?) {
      return $;
    }
  }

  /// `fragment260`
  (String, String)? fax() {
    if (this._applyMemo(this.r39) case var $?) {
      return $;
    }
  }

  /// `fragment261`
  String? fay() {
    if (this.f27() case var $?) {
      return $;
    }
  }

  /// `fragment262`
  String? faz() {
    var _mark = this._mark();
    if (this.f39() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$120) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `fragment263`
  (String, Record)? fb0() {
    if (this.fi() case var $0?) {
      if (this._applyMemo(this.r52) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `fragment264`
  String? fb1() {
    if (this.f5() case var $?) {
      return $;
    }
  }

  /// `fragment265`
  (String, List<Object>, String)? fb2() {
    if (this._applyMemo(this.rj) case var $?) {
      return $;
    }
  }

  /// `fragment266`
  List<((((Object, List<(String, Object)>), List<(String, (Object, List<(String, Object)>))>), (String, Record)?), String, Record)>? fb3() {
    if (this.r5c() case var _0?) {
      if ([_0] case var _l1) {
        for (;;) {
          var _mark = this._mark();
          if (this.f23() case _?) {
            if (this.r5c() case var _0?) {
              _l1.add(_0);
              continue;
            }
          }
          this._recover(_mark);
          break;
        }
        var _mark = this._mark();
        if (this.f23() case null) {
          this._recover(_mark);
        }
        return _l1;
      }
    }
  }

  /// `fragment267`
  Object? fb4() {
    var _mark = this._mark();
    if (this.f3() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.f3() case var $0?) {
      if (this.f2f() case var $1?) {
        return ($0, $1);
      }
    }
    this._recover(_mark);
    if (this.f1k() case var $0?) {
      if (this.f2f() case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `fragment268`
  String? fb5() {
    if (this.f23() case var $?) {
      return $;
    }
  }

  /// `fragment269`
  (List<((String, String)?, Record)>, String?)? fb6() {
    if (this.r5p() case var $0?) {
      if (this.fb5() case var $1) {
        return ($0, $1);
      }
    }
  }

  /// `fragment270`
  (String, String)? fb7() {
    if (this._applyMemo(this.r39) case var $?) {
      return $;
    }
  }

  /// `fragment271`
  String? fb8() {
    var _mark = this._mark();
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$119) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
    this._recover(_mark);
    if (this.f38() case var $?) {
      return $;
    }
  }

  /// `fragment272`
  List<Object> fb9() {
    var _mark = this._mark();
      if (this._applyMemo(this.r6l) case var _0) {
        if ([if (_0 case var _0?) _0] case var _l1) {
          if (_l1.isNotEmpty) {
            for (;;) {
              var _mark = this._mark();
              if (this._applyMemo(this.r6l) case var _0?) {
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

  /// `fragment273`
  (Record, (Object, Record))? fba() {
    if (this._applyMemo(this.r6r) case var $0?) {
      if (this._applyMemo(this.r5v) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `fragment274`
  (String, Record, String, Record)? fbb() {
    if (this.f27() case var $0?) {
      if (this._applyMemo(this.r4o) case var $1?) {
        if (this.f24() case var $2?) {
          if (this._applyMemo(this.r4o) case var $3?) {
            return ($0, $1, $2, $3);
          }
        }
      }
    }
  }

  /// `fragment275`
  String? fbc() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$101) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `fragment276`
  (String, ((Record, List<(String, Record)>), List<(String, (Record, List<(String, Record)>))>))? fbd() {
    if (this.fbc() case var $0?) {
      if (this._applyMemo(this.r60) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `fragment277`
  List<(String, ((Record, List<(String, Record)>), List<(String, (Record, List<(String, Record)>))>))> fbe() {
    var _mark = this._mark();
      if (this.fbd() case var _0) {
        if ([if (_0 case var _0?) _0] case var _l1) {
          if (_l1.isNotEmpty) {
            for (;;) {
              var _mark = this._mark();
              if (this.fbd() case var _0?) {
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

  /// `fragment278`
  (String, (Record, List<(String, Record)>))? fbf() {
    if (this.f2r() case var $0?) {
      if (this._applyMemo(this.r61) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `fragment279`
  List<(String, (Record, List<(String, Record)>))> fbg() {
    var _mark = this._mark();
      if (this.fbf() case var _0) {
        if ([if (_0 case var _0?) _0] case var _l1) {
          if (_l1.isNotEmpty) {
            for (;;) {
              var _mark = this._mark();
              if (this.fbf() case var _0?) {
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

  /// `fragment280`
  (String, Record)? fbh() {
    if (this.f2q() case var $0?) {
      if (this._applyMemo(this.r62) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `fragment281`
  List<(String, Record)> fbi() {
    var _mark = this._mark();
      if (this.fbh() case var _0) {
        if ([if (_0 case var _0?) _0] case var _l1) {
          if (_l1.isNotEmpty) {
            for (;;) {
              var _mark = this._mark();
              if (this.fbh() case var _0?) {
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

  /// `fragment282`
  (String, Record)? fbj() {
    if (this._applyMemo(this.r63) case var $0?) {
      if (this._applyMemo(this.r64) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `fragment283`
  Record? fbk() {
    var _mark = this._mark();
    if (this.r7k() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.r7l() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this._applyMemo(this.r65) case var $0?) {
      if (this._applyMemo(this.r66) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `fragment284`
  (String, (Object, List<(String, (Object, List<(String, (Object, List<(Object, (Object, List<(String, (Object, List<(String, (Object, Object))>))>))>))>))>))? fbl() {
    if (this.f2k() case var $0?) {
      if (this._applyMemo(this.r67) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `fragment285`
  List<(String, (Object, List<(String, (Object, List<(String, (Object, List<(Object, (Object, List<(String, (Object, List<(String, (Object, Object))>))>))>))>))>))> fbm() {
    var _mark = this._mark();
      if (this.fbl() case var _0) {
        if ([if (_0 case var _0?) _0] case var _l1) {
          if (_l1.isNotEmpty) {
            for (;;) {
              var _mark = this._mark();
              if (this.fbl() case var _0?) {
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

  /// `fragment286`
  (String, (Object, List<(String, (Object, List<(String, (Object, List<(Object, (Object, List<(String, (Object, List<(String, (Object, Object))>))>))>))>))>))? fbn() {
    if (this.f2k() case var $0?) {
      if (this._applyMemo(this.r67) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `fragment287`
  List<(String, (Object, List<(String, (Object, List<(String, (Object, List<(Object, (Object, List<(String, (Object, List<(String, (Object, Object))>))>))>))>))>))>? fbo() {
    if (this.fbn() case var _0?) {
      if ([_0] case var _l1) {
        for (;;) {
          var _mark = this._mark();
          if (this.fbn() case var _0?) {
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

  /// `fragment288`
  (String, (Object, List<(String, (Object, List<(Object, (Object, List<(String, (Object, List<(String, (Object, Object))>))>))>))>))? fbp() {
    if (this.f2j() case var $0?) {
      if (this._applyMemo(this.r68) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `fragment289`
  List<(String, (Object, List<(String, (Object, List<(Object, (Object, List<(String, (Object, List<(String, (Object, Object))>))>))>))>))> fbq() {
    var _mark = this._mark();
      if (this.fbp() case var _0) {
        if ([if (_0 case var _0?) _0] case var _l1) {
          if (_l1.isNotEmpty) {
            for (;;) {
              var _mark = this._mark();
              if (this.fbp() case var _0?) {
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

  /// `fragment290`
  (String, (Object, List<(String, (Object, List<(Object, (Object, List<(String, (Object, List<(String, (Object, Object))>))>))>))>))? fbr() {
    if (this.f2j() case var $0?) {
      if (this._applyMemo(this.r68) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `fragment291`
  List<(String, (Object, List<(String, (Object, List<(Object, (Object, List<(String, (Object, List<(String, (Object, Object))>))>))>))>))>? fbs() {
    if (this.fbr() case var _0?) {
      if ([_0] case var _l1) {
        for (;;) {
          var _mark = this._mark();
          if (this.fbr() case var _0?) {
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

  /// `fragment292`
  (String, (Object, List<(Object, (Object, List<(String, (Object, List<(String, (Object, Object))>))>))>))? fbt() {
    if (this.f2i() case var $0?) {
      if (this._applyMemo(this.r6a) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `fragment293`
  List<(String, (Object, List<(Object, (Object, List<(String, (Object, List<(String, (Object, Object))>))>))>))> fbu() {
    var _mark = this._mark();
      if (this.fbt() case var _0) {
        if ([if (_0 case var _0?) _0] case var _l1) {
          if (_l1.isNotEmpty) {
            for (;;) {
              var _mark = this._mark();
              if (this.fbt() case var _0?) {
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

  /// `fragment294`
  (String, (Object, List<(Object, (Object, List<(String, (Object, List<(String, (Object, Object))>))>))>))? fbv() {
    if (this.f2i() case var $0?) {
      if (this._applyMemo(this.r6a) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `fragment295`
  List<(String, (Object, List<(Object, (Object, List<(String, (Object, List<(String, (Object, Object))>))>))>))>? fbw() {
    if (this.fbv() case var _0?) {
      if ([_0] case var _l1) {
        for (;;) {
          var _mark = this._mark();
          if (this.fbv() case var _0?) {
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

  /// `fragment296`
  (Object, (Object, List<(String, (Object, List<(String, (Object, Object))>))>))? fbx() {
    if (this._applyMemo(this.r6b) case var $0?) {
      if (this._applyMemo(this.r6c) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `fragment297`
  List<(Object, (Object, List<(String, (Object, List<(String, (Object, Object))>))>))> fby() {
    var _mark = this._mark();
      if (this.fbx() case var _0) {
        if ([if (_0 case var _0?) _0] case var _l1) {
          if (_l1.isNotEmpty) {
            for (;;) {
              var _mark = this._mark();
              if (this.fbx() case var _0?) {
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

  /// `fragment298`
  (Object, (Object, List<(String, (Object, List<(String, (Object, Object))>))>))? fbz() {
    if (this._applyMemo(this.r6b) case var $0?) {
      if (this._applyMemo(this.r6c) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `fragment299`
  List<(Object, (Object, List<(String, (Object, List<(String, (Object, Object))>))>))>? fc0() {
    if (this.fbz() case var _0?) {
      if ([_0] case var _l1) {
        for (;;) {
          var _mark = this._mark();
          if (this.fbz() case var _0?) {
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

  /// `fragment300`
  (String, (Object, List<(String, (Object, Object))>))? fc1() {
    if (this._applyMemo(this.r6d) case var $0?) {
      if (this._applyMemo(this.r6e) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `fragment301`
  List<(String, (Object, List<(String, (Object, Object))>))> fc2() {
    var _mark = this._mark();
      if (this.fc1() case var _0) {
        if ([if (_0 case var _0?) _0] case var _l1) {
          if (_l1.isNotEmpty) {
            for (;;) {
              var _mark = this._mark();
              if (this.fc1() case var _0?) {
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

  /// `fragment302`
  (String, (Object, List<(String, (Object, Object))>))? fc3() {
    if (this._applyMemo(this.r6d) case var $0?) {
      if (this._applyMemo(this.r6e) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `fragment303`
  List<(String, (Object, List<(String, (Object, Object))>))>? fc4() {
    if (this.fc3() case var _0?) {
      if ([_0] case var _l1) {
        for (;;) {
          var _mark = this._mark();
          if (this.fc3() case var _0?) {
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

  /// `fragment304`
  (String, (Object, Object))? fc5() {
    if (this._applyMemo(this.r6f) case var $0?) {
      if (this._applyMemo(this.r6g) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `fragment305`
  List<(String, (Object, Object))> fc6() {
    var _mark = this._mark();
      if (this.fc5() case var _0) {
        if ([if (_0 case var _0?) _0] case var _l1) {
          if (_l1.isNotEmpty) {
            for (;;) {
              var _mark = this._mark();
              if (this.fc5() case var _0?) {
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

  /// `fragment306`
  (String, (Object, Object))? fc7() {
    if (this._applyMemo(this.r6f) case var $0?) {
      if (this._applyMemo(this.r6g) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `fragment307`
  List<(String, (Object, Object))>? fc8() {
    if (this.fc7() case var _0?) {
      if ([_0] case var _l1) {
        for (;;) {
          var _mark = this._mark();
          if (this.fc7() case var _0?) {
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

  /// `fragment308`
  String? fc9() {
    var _mark = this._mark();
    if (this.f2e() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.f2c() case var $?) {
      return $;
    }
  }

  /// `fragment309`
  List<Object> fca() {
    var _mark = this._mark();
      if (this._applyMemo(this.r6l) case var _0) {
        if ([if (_0 case var _0?) _0] case var _l1) {
          if (_l1.isNotEmpty) {
            for (;;) {
              var _mark = this._mark();
              if (this._applyMemo(this.r6l) case var _0?) {
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

  /// `fragment310`
  (String, List<Object>, String)? fcb() {
    if (this._applyMemo(this.rj) case var $?) {
      return $;
    }
  }

  /// `fragment311`
  List<Object> fcc() {
    var _mark = this._mark();
      if (this._applyMemo(this.r6l) case var _0) {
        if ([if (_0 case var _0?) _0] case var _l1) {
          if (_l1.isNotEmpty) {
            for (;;) {
              var _mark = this._mark();
              if (this._applyMemo(this.r6l) case var _0?) {
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

  /// `fragment312`
  String? fcd() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$122) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `fragment313`
  List<Object> fce() {
    var _mark = this._mark();
      if (this._applyMemo(this.r6l) case var _0) {
        if ([if (_0 case var _0?) _0] case var _l1) {
          if (_l1.isNotEmpty) {
            for (;;) {
              var _mark = this._mark();
              if (this._applyMemo(this.r6l) case var _0?) {
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

  /// `fragment314`
  (String, (Object, List<(String, Object)>))? fcf() {
    if (this.f2r() case var $0?) {
      if (this._applyMemo(this.r6w) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `fragment315`
  List<(String, (Object, List<(String, Object)>))> fcg() {
    var _mark = this._mark();
      if (this.fcf() case var _0) {
        if ([if (_0 case var _0?) _0] case var _l1) {
          if (_l1.isNotEmpty) {
            for (;;) {
              var _mark = this._mark();
              if (this.fcf() case var _0?) {
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

  /// `fragment316`
  (String, Object)? fch() {
    if (this.f2q() case var $0?) {
      if (this._applyMemo(this.r6x) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `fragment317`
  List<(String, Object)> fci() {
    var _mark = this._mark();
      if (this.fch() case var _0) {
        if ([if (_0 case var _0?) _0] case var _l1) {
          if (_l1.isNotEmpty) {
            for (;;) {
              var _mark = this._mark();
              if (this.fch() case var _0?) {
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

  /// `fragment318`
  String? fcj() {
    var _mark = this._mark();
    if (this._applyMemo(this.r63) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this._applyMemo(this.r65) case var $?) {
      return $;
    }
  }

  /// `fragment319`
  String? fck() {
    if (this.f2e() case var $?) {
      return $;
    }
  }

  /// `fragment320`
  (String, List<Object>, String)? fcl() {
    if (this._applyMemo(this.rj) case var $?) {
      return $;
    }
  }

  /// `fragment321`
  List<Record>? fcm() {
    if (this._applyMemo(this.r51) case var $?) {
      return $;
    }
  }

  /// `fragment322`
  (String, List<Object>, String)? fcn() {
    if (this._applyMemo(this.rj) case var $?) {
      return $;
    }
  }

  /// `fragment323`
  List<Record>? fco() {
    if (this._applyMemo(this.r51) case var $?) {
      return $;
    }
  }

  /// `fragment324`
  String? fcp() {
    if (this.fq() case var $?) {
      return $;
    }
  }

  /// `fragment325`
  Object? fcq() {
    var _mark = this._mark();
    if (this.f1r() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.fq() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.fcp() case var $0) {
      if (this._applyMemo(this.re) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `fragment326`
  (String, List<Object>, String)? fcr() {
    if (this._applyMemo(this.rj) case var $?) {
      return $;
    }
  }

  /// `fragment327`
  (List<(Object, Object?)>, String?)? fcs() {
    if (this.r77() case var $?) {
      return $;
    }
  }

  /// `fragment328`
  List<(Object, Object?)>? fct() {
    if (this.r78() case var _0?) {
      if ([_0] case var _l1) {
        for (;;) {
          var _mark = this._mark();
          if (this.f23() case _?) {
            if (this.r78() case var _0?) {
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

  /// `fragment329`
  String? fcu() {
    if (this.f23() case var $?) {
      return $;
    }
  }

  /// `fragment330`
  ((Object, List<(String, Object)>), List<(String, (Object, List<(String, Object)>))>)? fcv() {
    if (this._applyMemo(this.r6u) case var $?) {
      return $;
    }
  }

  /// `fragment331`
  (String, List<Object>, String)? fcw() {
    if (this._applyMemo(this.rj) case var $?) {
      return $;
    }
  }

  /// `fragment332`
  (List<Object>, String?)? fcx() {
    if (this.r7b() case var $?) {
      return $;
    }
  }

  /// `fragment333`
  List<Object>? fcy() {
    if (this.r7c() case var _0?) {
      if ([_0] case var _l1) {
        for (;;) {
          var _mark = this._mark();
          if (this.f23() case _?) {
            if (this.r7c() case var _0?) {
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

  /// `fragment334`
  String? fcz() {
    if (this.f23() case var $?) {
      return $;
    }
  }

  /// `fragment335`
  (List<((String?, String)?, ((Object, List<(String, Object)>), List<(String, (Object, List<(String, Object)>))>))>, String?)? fd0() {
    if (this._applyMemo(this.r7e) case var $?) {
      return $;
    }
  }

  /// `fragment336`
  List<((String?, String)?, ((Object, List<(String, Object)>), List<(String, (Object, List<(String, Object)>))>))>? fd1() {
    if (this.r7f() case var _0?) {
      if ([_0] case var _l1) {
        for (;;) {
          var _mark = this._mark();
          if (this.f23() case _?) {
            if (this.r7f() case var _0?) {
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

  /// `fragment337`
  String? fd2() {
    if (this.f23() case var $?) {
      return $;
    }
  }

  /// `fragment338`
  String? fd3() {
    if (this._applyMemo(this.r7m) case var $?) {
      return $;
    }
  }

  /// `fragment339`
  (String?, String)? fd4() {
    if (this.fd3() case var $0) {
      if (this.f24() case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `fragment340`
  (String, List<Object>, String)? fd5() {
    if (this._applyMemo(this.rj) case var $?) {
      return $;
    }
  }

  /// `fragment341`
  ((String, Object?)?, Object?)? fd6() {
    var _mark = this._mark();
    if (this._applyMemo(this.rb) case var $0?) {
      if (this.fd5() case var $1) {
        return ($0, $1);
      }
    }
    this._recover(_mark);
    if (this._applyMemo(this.ri) case var $?) {
      return $;
    }
  }

  /// `fragment342`
  (List<((String?, String)?, ((Object, List<(String, Object)>), List<(String, (Object, List<(String, Object)>))>))>, String?)? fd7() {
    if (this._applyMemo(this.r7e) case var $?) {
      return $;
    }
  }

  /// `fragment343`
  (String, Record)? fd8() {
    if (this.f1w() case var $0?) {
      if (this._applyMemo(this.r4n) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `fragment344`
  String? fd9() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$38) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `fragment345`
  String? fda() {
    if (this.f2b() case var $?) {
      return $;
    }
  }

  /// `fragment346`
  String? fdb() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$94) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `fragment347`
  Object? fdc() {
    var _mark = this._mark();
    if (this._applyMemo(this.r1m) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this._applyMemo(this.r7m) case var _0?) {
      if ([_0] case var _l1) {
        for (;;) {
          var _mark = this._mark();
          if (this.f26() case _?) {
            if (this._applyMemo(this.r7m) case var _0?) {
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
    this._recover(_mark);
    if (this.f1s() case var $?) {
      return $;
    }
  }

  /// `fragment348`
  List<String> fdd() {
    var _mark = this._mark();
      if (this.matchPattern(_string.$137) case var _0) {
        if ([if (_0 case var _0?) _0] case var _l1) {
          if (_l1.isNotEmpty) {
            for (;;) {
              var _mark = this._mark();
              if (this.matchPattern(_string.$137) case var _0?) {
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

  /// `fragment349`
  (List<String>, String)? fde() {
    if (this.fdd() case var $0) {
      if (this.matchRange(_range.$2) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `fragment350`
  List<(List<String>, String)> fdf() {
    var _mark = this._mark();
      if (this.fde() case var _0) {
        if ([if (_0 case var _0?) _0] case var _l1) {
          if (_l1.isNotEmpty) {
            for (;;) {
              var _mark = this._mark();
              if (this.fde() case var _0?) {
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

  /// `fragment351`
  (String, List<(List<String>, String)>)? fdg() {
    if (this.matchRange(_range.$2) case var $0?) {
      if (this.fdf() case var $1) {
        return ($0, $1);
      }
    }
  }

  /// `fragment352`
  List<String> fdh() {
    var _mark = this._mark();
      if (this.matchPattern(_string.$137) case var _0) {
        if ([if (_0 case var _0?) _0] case var _l1) {
          if (_l1.isNotEmpty) {
            for (;;) {
              var _mark = this._mark();
              if (this.matchPattern(_string.$137) case var _0?) {
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

  /// `fragment353`
  (List<String>, String)? fdi() {
    if (this.fdh() case var $0) {
      if (this.matchRange(_range.$2) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `fragment354`
  List<(List<String>, String)> fdj() {
    var _mark = this._mark();
      if (this.fdi() case var _0) {
        if ([if (_0 case var _0?) _0] case var _l1) {
          if (_l1.isNotEmpty) {
            for (;;) {
              var _mark = this._mark();
              if (this.fdi() case var _0?) {
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

  /// `fragment355`
  (String, List<(List<String>, String)>)? fdk() {
    if (this.matchRange(_range.$2) case var $0?) {
      if (this.fdj() case var $1) {
        return ($0, $1);
      }
    }
  }

  /// `fragment356`
  (String, (String, List<(List<String>, String)>))? fdl() {
    if (this.f26() case var $0?) {
      if (this.fdk() case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `fragment357`
  String? fdm() {
    if (this.matchRange(_range.$3) case var $?) {
      return $;
    }
  }

  /// `fragment358`
  List<String> fdn() {
    var _mark = this._mark();
      if (this.matchPattern(_string.$137) case var _0) {
        if ([if (_0 case var _0?) _0] case var _l1) {
          if (_l1.isNotEmpty) {
            for (;;) {
              var _mark = this._mark();
              if (this.matchPattern(_string.$137) case var _0?) {
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

  /// `fragment359`
  (List<String>, String)? fdo() {
    if (this.fdn() case var $0) {
      if (this.matchRange(_range.$2) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `fragment360`
  List<(List<String>, String)> fdp() {
    var _mark = this._mark();
      if (this.fdo() case var _0) {
        if ([if (_0 case var _0?) _0] case var _l1) {
          if (_l1.isNotEmpty) {
            for (;;) {
              var _mark = this._mark();
              if (this.fdo() case var _0?) {
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

  /// `fragment361`
  (String, List<(List<String>, String)>)? fdq() {
    if (this.matchRange(_range.$2) case var $0?) {
      if (this.fdp() case var $1) {
        return ($0, $1);
      }
    }
  }

  /// `fragment362`
  (String, String?, (String, List<(List<String>, String)>))? fdr() {
    if (this.matchRange(_range.$4) case var $0?) {
      if (this.fdm() case var $1) {
        if (this.fdq() case var $2?) {
          return ($0, $1, $2);
        }
      }
    }
  }

  /// `fragment363`
  String? fds() {
    if (this.pos case var from) {
      if (this.fdg() case _?) {
        if (this.fdl() case _) {
          if (this.fdr() case _) {
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

  /// `fragment364`
  String? fdt() {
    var _mark = this._mark();
    if (this.matchPattern(_string.$138) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$139) case var $?) {
      return $;
    }
  }

  /// `fragment365`
  List<String> fdu() {
    var _mark = this._mark();
      if (this.matchPattern(_string.$137) case var _0) {
        if ([if (_0 case var _0?) _0] case var _l1) {
          if (_l1.isNotEmpty) {
            for (;;) {
              var _mark = this._mark();
              if (this.matchPattern(_string.$137) case var _0?) {
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

  /// `fragment366`
  (List<String>, String)? fdv() {
    if (this.fdu() case var $0) {
      if (this.matchRange(_range.$5) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `fragment367`
  List<(List<String>, String)> fdw() {
    var _mark = this._mark();
      if (this.fdv() case var _0) {
        if ([if (_0 case var _0?) _0] case var _l1) {
          if (_l1.isNotEmpty) {
            for (;;) {
              var _mark = this._mark();
              if (this.fdv() case var _0?) {
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

  /// `fragment368`
  (String, List<(List<String>, String)>)? fdx() {
    if (this.matchRange(_range.$5) case var $0?) {
      if (this.fdw() case var $1) {
        return ($0, $1);
      }
    }
  }

  /// `fragment369`
  String? fdy() {
    if (this.pos case var from) {
      if (this.fdt() case _?) {
        if (this.fdx() case _?) {
          if (this.pos case var to) {
            if (this.buffer.substring(from, to) case var span) {
              return span;
            }
          }
        }
      }
    }
  }

  /// `fragment370`
  List<String> fdz() {
    var _mark = this._mark();
      if (this.matchRange(_range.$6) case var _0) {
        if ([if (_0 case var _0?) _0] case var _l1) {
          if (_l1.isNotEmpty) {
            for (;;) {
              var _mark = this._mark();
              if (this.matchRange(_range.$6) case var _0?) {
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

  /// `fragment371`
  String? fe0() {
    if (this.pos case var from) {
      if (this.matchRange(_range.$7) case _?) {
        if (this.fdz() case _) {
          if (this.pos case var to) {
            if (this.buffer.substring(from, to) case var span) {
              return span;
            }
          }
        }
      }
    }
  }

  /// `fragment372`
  String? fe1() {
    var _mark = this._mark();
    if (this.matchRange(_range.$1) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  }

  /// `fragment373`
  List<String> fe2() {
    var _mark = this._mark();
      if (this.fe1() case var _0) {
        if ([if (_0 case var _0?) _0] case var _l1) {
          if (_l1.isNotEmpty) {
            for (;;) {
              var _mark = this._mark();
              if (this.fe1() case var _0?) {
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

  /// `fragment374`
  String? fe3() {
    var _mark = this._mark();
    if (this.matchRange(_range.$8) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  }

  /// `fragment375`
  List<String> fe4() {
    var _mark = this._mark();
      if (this.fe3() case var _0) {
        if ([if (_0 case var _0?) _0] case var _l1) {
          if (_l1.isNotEmpty) {
            for (;;) {
              var _mark = this._mark();
              if (this.fe3() case var _0?) {
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

  /// `fragment376`
  String? fe5() {
    var _mark = this._mark();
    if (this.matchRange(_range.$8) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  }

  /// `fragment377`
  List<String> fe6() {
    var _mark = this._mark();
      if (this.fe5() case var _0) {
        if ([if (_0 case var _0?) _0] case var _l1) {
          if (_l1.isNotEmpty) {
            for (;;) {
              var _mark = this._mark();
              if (this.fe5() case var _0?) {
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

  /// `fragment378`
  Object? fe7() {
    var _mark = this._mark();
    if (this.matchRange(_range.$9) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }

    this._recover(_mark);
    if (this.matchPattern(_string.$140) case var $0?) {
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $1) {
          return ($0, $1);
        }
      }
    }
  }

  /// `fragment379`
  List<Object> fe8() {
    var _mark = this._mark();
      if (this.fe7() case var _0) {
        if ([if (_0 case var _0?) _0] case var _l1) {
          if (_l1.isNotEmpty) {
            for (;;) {
              var _mark = this._mark();
              if (this.fe7() case var _0?) {
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

  /// `fragment380`
  Object? fe9() {
    var _mark = this._mark();
    if (this.matchRange(_range.$10) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }

    this._recover(_mark);
    if (this.matchPattern(_string.$140) case var $0?) {
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $1) {
          return ($0, $1);
        }
      }
    }
  }

  /// `fragment381`
  List<Object> fea() {
    var _mark = this._mark();
      if (this.fe9() case var _0) {
        if ([if (_0 case var _0?) _0] case var _l1) {
          if (_l1.isNotEmpty) {
            for (;;) {
              var _mark = this._mark();
              if (this.fe9() case var _0?) {
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

  /// `fragment382`
  String? feb() {
    var _mark = this._mark();
    if (this.matchPattern(_string.$129) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  }

  /// `fragment383`
  List<String> fec() {
    var _mark = this._mark();
      if (this.feb() case var _0) {
        if ([if (_0 case var _0?) _0] case var _l1) {
          if (_l1.isNotEmpty) {
            for (;;) {
              var _mark = this._mark();
              if (this.feb() case var _0?) {
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

  /// `fragment384`
  String? fed() {
    var _mark = this._mark();
    if (this.matchPattern(_string.$131) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  }

  /// `fragment385`
  List<String> fee() {
    var _mark = this._mark();
      if (this.fed() case var _0) {
        if ([if (_0 case var _0?) _0] case var _l1) {
          if (_l1.isNotEmpty) {
            for (;;) {
              var _mark = this._mark();
              if (this.fed() case var _0?) {
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

  /// `fragment386`
  String? fef() {
    var _mark = this._mark();
    if (this.matchPattern(_string.$129) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  }

  /// `fragment387`
  List<String> feg() {
    var _mark = this._mark();
      if (this.fef() case var _0) {
        if ([if (_0 case var _0?) _0] case var _l1) {
          if (_l1.isNotEmpty) {
            for (;;) {
              var _mark = this._mark();
              if (this.fef() case var _0?) {
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

  /// `fragment388`
  String? feh() {
    var _mark = this._mark();
    if (this.matchPattern(_string.$131) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  }

  /// `fragment389`
  List<String> fei() {
    var _mark = this._mark();
      if (this.feh() case var _0) {
        if ([if (_0 case var _0?) _0] case var _l1) {
          if (_l1.isNotEmpty) {
            for (;;) {
              var _mark = this._mark();
              if (this.feh() case var _0?) {
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

  /// `fragment390`
  (String, List<Object>, String)? fej() {
    var _mark = this._mark();
    if (this.matchPattern(_string.$126) case var $0?) {
      if (this.fe4() case var $1) {
        if (this.matchPattern(_string.$125) case var $2?) {
          return ($0, $1, $2);
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$128) case var $0?) {
      if (this.fe6() case var $1) {
        if (this.matchPattern(_string.$127) case var $2?) {
          return ($0, $1, $2);
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$125) case var $0?) {
      if (this.fe8() case var $1) {
        if (this.matchPattern(_string.$125) case var $2?) {
          return ($0, $1, $2);
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$127) case var $0?) {
      if (this.fea() case var $1) {
        if (this.matchPattern(_string.$127) case var $2?) {
          return ($0, $1, $2);
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$130) case var $0?) {
      if (this.fec() case var $1) {
        if (this.matchPattern(_string.$129) case var $2?) {
          return ($0, $1, $2);
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$132) case var $0?) {
      if (this.fee() case var $1) {
        if (this.matchPattern(_string.$131) case var $2?) {
          return ($0, $1, $2);
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$129) case var $0?) {
      if (this.feg() case var $1) {
        if (this.matchPattern(_string.$129) case var $2?) {
          return ($0, $1, $2);
        }
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$131) case var $0?) {
      if (this.fei() case var $1) {
        if (this.matchPattern(_string.$131) case var $2?) {
          return ($0, $1, $2);
        }
      }
    }
  }

  /// `fragment391`
  List<(String, List<Object>, String)>? fek() {
    if (this.fej() case var _0?) {
      if ([_0] case var _l1) {
        for (;;) {
          var _mark = this._mark();
          if (this.fej() case var _0?) {
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

  /// `fragment392`
  String? fel() {
    var _mark = this._mark();
    if (this.matchRange(_range.$8) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  }

  /// `fragment393`
  List<String> fem() {
    var _mark = this._mark();
      if (this.fel() case var _0) {
        if ([if (_0 case var _0?) _0] case var _l1) {
          if (_l1.isNotEmpty) {
            for (;;) {
              var _mark = this._mark();
              if (this.fel() case var _0?) {
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

  /// `fragment394`
  String? fen() {
    var _mark = this._mark();
    if (this.matchRange(_range.$8) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  }

  /// `fragment395`
  List<String> feo() {
    var _mark = this._mark();
      if (this.fen() case var _0) {
        if ([if (_0 case var _0?) _0] case var _l1) {
          if (_l1.isNotEmpty) {
            for (;;) {
              var _mark = this._mark();
              if (this.fen() case var _0?) {
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

  /// `fragment396`
  Object? fep() {
    var _mark = this._mark();
    if (this.matchRange(_range.$9) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }

    this._recover(_mark);
    if (this.matchPattern(_string.$140) case var $0?) {
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $1) {
          return ($0, $1);
        }
      }
    }
  }

  /// `fragment397`
  List<Object> feq() {
    var _mark = this._mark();
      if (this.fep() case var _0) {
        if ([if (_0 case var _0?) _0] case var _l1) {
          if (_l1.isNotEmpty) {
            for (;;) {
              var _mark = this._mark();
              if (this.fep() case var _0?) {
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

  /// `fragment398`
  Object? fer() {
    var _mark = this._mark();
    if (this.matchRange(_range.$10) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }

    this._recover(_mark);
    if (this.matchPattern(_string.$140) case var $0?) {
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $1) {
          return ($0, $1);
        }
      }
    }
  }

  /// `fragment399`
  List<Object> fes() {
    var _mark = this._mark();
      if (this.fer() case var _0) {
        if ([if (_0 case var _0?) _0] case var _l1) {
          if (_l1.isNotEmpty) {
            for (;;) {
              var _mark = this._mark();
              if (this.fer() case var _0?) {
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

  /// `fragment400`
  String? fet() {
    var _mark = this._mark();
    if (this.matchPattern(_string.$129) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  }

  /// `fragment401`
  List<String> feu() {
    var _mark = this._mark();
      if (this.fet() case var _0) {
        if ([if (_0 case var _0?) _0] case var _l1) {
          if (_l1.isNotEmpty) {
            for (;;) {
              var _mark = this._mark();
              if (this.fet() case var _0?) {
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

  /// `fragment402`
  String? fev() {
    var _mark = this._mark();
    if (this.matchPattern(_string.$131) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  }

  /// `fragment403`
  List<String> few() {
    var _mark = this._mark();
      if (this.fev() case var _0) {
        if ([if (_0 case var _0?) _0] case var _l1) {
          if (_l1.isNotEmpty) {
            for (;;) {
              var _mark = this._mark();
              if (this.fev() case var _0?) {
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

  /// `fragment404`
  String? fex() {
    var _mark = this._mark();
    if (this.matchPattern(_string.$129) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  }

  /// `fragment405`
  List<String> fey() {
    var _mark = this._mark();
      if (this.fex() case var _0) {
        if ([if (_0 case var _0?) _0] case var _l1) {
          if (_l1.isNotEmpty) {
            for (;;) {
              var _mark = this._mark();
              if (this.fex() case var _0?) {
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

  /// `fragment406`
  String? fez() {
    var _mark = this._mark();
    if (this.matchPattern(_string.$131) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  }

  /// `fragment407`
  List<String> ff0() {
    var _mark = this._mark();
      if (this.fez() case var _0) {
        if ([if (_0 case var _0?) _0] case var _l1) {
          if (_l1.isNotEmpty) {
            for (;;) {
              var _mark = this._mark();
              if (this.fez() case var _0?) {
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

  /// `fragment408`
  String? ff1() {
    var _mark = this._mark();
    if (this.matchRange(_range.$1) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  }

  /// `fragment409`
  List<String> ff2() {
    var _mark = this._mark();
      if (this.ff1() case var _0) {
        if ([if (_0 case var _0?) _0] case var _l1) {
          if (_l1.isNotEmpty) {
            for (;;) {
              var _mark = this._mark();
              if (this.ff1() case var _0?) {
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

  /// `fragment410`
  String? ff3() {
    var _mark = this._mark();
    if (this.matchPattern(_string.$134) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  }

  /// `fragment411`
  List<String> ff4() {
    var _mark = this._mark();
      if (this.ff3() case var _0) {
        if ([if (_0 case var _0?) _0] case var _l1) {
          if (_l1.isNotEmpty) {
            for (;;) {
              var _mark = this._mark();
              if (this.ff3() case var _0?) {
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

  /// `fragment412`
  Record? ff5() {
    var _mark = this._mark();
    if (this.matchPattern(_string.$133) case var $0?) {
      if (this.ff2() case var $1) {
        return ($0, $1);
      }
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$135) case var $0?) {
      if (this.ff4() case var $1) {
        if (this.matchPattern(_string.$134) case var $2?) {
          return ($0, $1, $2);
        }
      }
    }
  }

  /// `fragment413`
  Object? ff6() {
    var _mark = this._mark();
    if (this.matchPattern(_regexp.$1) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.matchPattern(_string.$89) case var $0?) {
      this._recover(_mark);
      if (this.ff5() case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `fragment414`
  String? ff7() {
    var _mark = this._mark();
    if (this.matchRange(_range.$1) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  }

  /// `fragment415`
  List<String> ff8() {
    var _mark = this._mark();
      if (this.ff7() case var _0) {
        if ([if (_0 case var _0?) _0] case var _l1) {
          if (_l1.isNotEmpty) {
            for (;;) {
              var _mark = this._mark();
              if (this.ff7() case var _0?) {
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

  /// `fragment416`
  String? ff9() {
    var _mark = this._mark();
    if (this.matchPattern(_string.$134) case null) {
      this._recover(_mark);
      if (this.pos < this.buffer.length) {
        if (this.buffer[this.pos++] case var $) {
          return $;
        }
      }
    }
  }

  /// `fragment417`
  List<String> ffa() {
    var _mark = this._mark();
      if (this.ff9() case var _0) {
        if ([if (_0 case var _0?) _0] case var _l1) {
          if (_l1.isNotEmpty) {
            for (;;) {
              var _mark = this._mark();
              if (this.ff9() case var _0?) {
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

  /// `global::dart::startSymbol`
  Record? r0() {
    var _mark = this._mark();
    if (this.r1() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.r4i() case var $?) {
      return $;
    }
  }

  /// `global::dart::libraryDeclaration`
  (String?, (String, List<String>)?, (List<(String, Object)>, Record, String)?, List<Record>, List<(List<(String, Object)>, String, (List<(String, List<Object>, String)>, List<(String, String, (List<String>, (String, List<(String, List<Object>, String)>)?), String, List<(String, List<Object>, String)>)>), String)>, List<(List<(String, Object)>, Record)>, int)? r1() {
    if (this.f3p() case var $0) {
      if (this.f3s() case var $1) {
        if (this.f3t() case var $2) {
          if (this.f3u() case var $3) {
            if (this.f3v() case var $4) {
              if (this.f3x() case var $5) {
                if (this.pos case var $6 when this.pos >= this.buffer.length) {
                  return ($0, $1, $2, $3, $4, $5, $6);
                }
              }
            }
          }
        }
      }
    }
  }

  /// `global::dart::topLevelDeclaration`
  Record? r2() {
    var _mark = this._mark();
    if (this.r13() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.r2g() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.r2h() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.r2i() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.r2j() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.r2m() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.f3y() case var $0) {
      if (this.fn() case var $1?) {
        if (this._applyMemo(this.r2p) case var $2?) {
          if (this.f25() case var $3?) {
            return ($0, $1, $2, $3);
          }
        }
      }
    }
    this._recover(_mark);
    if (this.f3z() case var $0) {
      if (this.fn() case var $1?) {
        if (this._applyMemo(this.r1o) case var $2?) {
          if (this.f25() case var $3?) {
            return ($0, $1, $2, $3);
          }
        }
      }
    }
    this._recover(_mark);
    if (this.f40() case var $0) {
      if (this.fn() case var $1?) {
        if (this._applyMemo(this.r1p) case var $2?) {
          if (this.f25() case var $3?) {
            return ($0, $1, $2, $3);
          }
        }
      }
    }
    this._recover(_mark);
    if (this.f41() case var $0) {
      if (this.fn() case var $1?) {
        if (this._applyMemo(this.r3) case var $2?) {
          if (this._applyMemo(this.r5) case var $3?) {
            if (this.f25() case var $4?) {
              return ($0, $1, $2, $3, $4);
            }
          }
        }
      }
    }
    this._recover(_mark);
    if (this.f42() case var $0) {
      if (this.f0() case var $1?) {
        if (this._applyMemo(this.r3) case var $2?) {
          if (this._applyMemo(this.r5) case var $3?) {
            if (this.f25() case var $4?) {
              return ($0, $1, $2, $3, $4);
            }
          }
        }
      }
    }
    this._recover(_mark);
    if (this.f43() case var $0) {
      if (this._applyMemo(this.r1o) case var $1?) {
        if (this.f44() case var $2?) {
          return ($0, $1, $2);
        }
      }
    }
    this._recover(_mark);
    if (this.f45() case var $0) {
      if (this._applyMemo(this.r1p) case var $1?) {
        if (this.f46() case var $2?) {
          return ($0, $1, $2);
        }
      }
    }
    this._recover(_mark);
    if (this.f47() case var $0) {
      if (this._applyMemo(this.r2p) case var $1?) {
        if (this.f48() case var $2?) {
          return ($0, $1, $2);
        }
      }
    }
    this._recover(_mark);
    if (this.f49() case var $0) {
      if (this.f4a() case var $1?) {
        if (this.f4b() case var $2) {
          if (this._applyMemo(this.r1j) case var $3?) {
            if (this.f25() case var $4?) {
              return ($0, $1, $2, $3, $4);
            }
          }
        }
      }
    }
    this._recover(_mark);
    if (this.f4c() case var $0) {
      if (this.f12() case var $1?) {
        if (this.fq() case var $2?) {
          if (this.f4d() case var $3) {
            if (this._applyMemo(this.r3g) case var $4?) {
              if (this.f25() case var $5?) {
                return ($0, $1, $2, $3, $4, $5);
              }
            }
          }
        }
      }
    }
    this._recover(_mark);
    if (this.f4e() case var $0) {
      if (this.f4f() case var $1) {
        if (this._applyMemo(this.r4) case var $2?) {
          if (this._applyMemo(this.r3g) case var $3?) {
            if (this.f25() case var $4?) {
              return ($0, $1, $2, $3, $4);
            }
          }
        }
      }
    }
  }

  /// `global::dart::finalVarOrType`
  Object? r3() {
    var _mark = this._mark();
    if (this.fq() case var $0?) {
      if (this.f4g() case var $1) {
        return ($0, $1);
      }
    }
    this._recover(_mark);
    if (this._applyMemo(this.r4) case var $?) {
      return $;
    }
  }

  /// `global::dart::varOrType`
  Object? r4() {
    var _mark = this._mark();
    if (this.f1r() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this._applyMemo(this.re) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.f1r() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this._applyMemo(this.re) case var $?) {
      return $;
    }
  }

  /// `global::dart::identifierList`
  List<String>? r5() {
    if (this._applyMemo(this.r7m) case var _0?) {
      if ([_0] case var _l1) {
        for (;;) {
          var _mark = this._mark();
          if (this.f23() case _?) {
            if (this._applyMemo(this.r7m) case var _0?) {
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

  /// `global::dart::metadata`
  List<(String, Object)> r6() {
    var _mark = this._mark();
      if (this.f4h() case var _0) {
        if ([if (_0 case var _0?) _0] case var _l1) {
          if (_l1.isNotEmpty) {
            for (;;) {
              var _mark = this._mark();
              if (this.f4h() case var _0?) {
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

  /// `global::dart::metadatum`
  Object? r7() {
    var _mark = this._mark();
    if (this._applyMemo(this.ra) case var $0?) {
      if (this._applyMemo(this.r5o) case var $1?) {
        return ($0, $1);
      }
    }
    this._recover(_mark);
    if (this._applyMemo(this.r7m) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this._applyMemo(this.r8) case var $?) {
      return $;
    }
  }

  /// `global::dart::qualifiedName`
  Record? r8() {
    var _mark = this._mark();
    if (this._applyMemo(this.rc) case var $0?) {
      if (this.f26() case var $1?) {
        if (this._applyMemo(this.r9) case var $2?) {
          return ($0, $1, $2);
        }
      }
    }
    this._recover(_mark);
    if (this._applyMemo(this.rc) case var $0?) {
      if (this.f26() case var $1?) {
        if (this._applyMemo(this.rc) case var $2?) {
          if (this.f26() case var $3?) {
            if (this._applyMemo(this.r9) case var $4?) {
              return ($0, $1, $2, $3, $4);
            }
          }
        }
      }
    }
  }

  /// `global::dart::identifierOrNew`
  String? r9() {
    var _mark = this._mark();
    if (this._applyMemo(this.r7m) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.f15() case var $?) {
      return $;
    }
  }

  /// `global::dart::constructorDesignation`
  Object? ra() {
    var _mark = this._mark();
    if (this._applyMemo(this.rc) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this._applyMemo(this.r8) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this._applyMemo(this.rb) case var $0?) {
      if (this._applyMemo(this.rj) case var $1?) {
        if (this.f4i() case var $2) {
          return ($0, $1, $2);
        }
      }
    }
  }

  /// `global::dart::typeName`
  (String, (String, String)?)? rb() {
    if (this._applyMemo(this.rc) case var $0?) {
      if (this.f4j() case var $1) {
        return ($0, $1);
      }
    }
  }

  /// `global::dart::typeIdentifier`
  String? rc() {
    var _mark = this._mark();
    if (this._applyMemo(this.rd) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.f1p() case var $?) {
      return $;
    }
  }

  /// `global::dart::typeIdentifierNotType`
  String? rd() {
    var _mark = this._mark();
    if (this.f3g() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.fh() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.f3() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.f6() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.fv() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.f17() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.f18() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.f1e() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.f1g() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.f1k() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.f1w() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.f5() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.f1v() case var $?) {
      return $;
    }
  }

  /// `global::dart::type`
  Object? re() {
    var _mark = this._mark();
    if (this._applyMemo(this.rr) case var $0?) {
      if (this.f4k() case var $1) {
        return ($0, $1);
      }
    }
    this._recover(_mark);
    if (this._applyMemo(this.rf) case var $?) {
      return $;
    }
  }

  /// `global::dart::typeNotFunction`
  Object? rf() {
    var _mark = this._mark();
    if (this._applyMemo(this.rh) case var $0?) {
      if (this.f4l() case var $1) {
        return ($0, $1);
      }
    }
    this._recover(_mark);
    if (this._applyMemo(this.rl) case var $0?) {
      if (this.f4m() case var $1) {
        return ($0, $1);
      }
    }
    this._recover(_mark);
    if (this.f1s() case var $?) {
      return $;
    }
  }

  /// `global::dart::typeNotVoid`
  (Record, String?)? rg() {
    var _mark = this._mark();
    if (this._applyMemo(this.rr) case var $0?) {
      if (this.f4n() case var $1) {
        return ($0, $1);
      }
    }
    this._recover(_mark);
    if (this._applyMemo(this.rl) case var $0?) {
      if (this.f4o() case var $1) {
        return ($0, $1);
      }
    }
    this._recover(_mark);
    if (this._applyMemo(this.rh) case var $0?) {
      if (this.f4p() case var $1) {
        return ($0, $1);
      }
    }
  }

  /// `global::dart::typeNotVoidNotFunction`
  ((String, Object?)?, Object?)? rh() {
    var _mark = this._mark();
    if (this._applyMemo(this.rb) case var $0?) {
      if (this.f4q() case var $1) {
        return ($0, $1);
      }
    }
    this._recover(_mark);
    if (this._applyMemo(this.ri) case var $?) {
      return $;
    }
  }

  /// `global::dart::typeNamedFunction`
  ((String, String)?, String)? ri() {
    if (this.f4r() case var $0) {
      if (this.ft() case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `global::dart::typeArguments`
  (String, List<Object>, String)? rj() {
    if (this.f2a() case var $0?) {
      if (this.rk() case var $1?) {
        if (this.f29() case var $2?) {
          return ($0, $1, $2);
        }
      }
    }
  }

  /// `global::dart::typeList`
  List<Object>? rk() {
    if (this._applyMemo(this.re) case var _0?) {
      if ([_0] case var _l1) {
        for (;;) {
          var _mark = this._mark();
          if (this.f23() case _?) {
            if (this._applyMemo(this.re) case var _0?) {
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

  /// `global::dart::recordType`
  Record? rl() {
    var _mark = this._mark();
    if (this.f1x() case var $0?) {
      if (this.f1y() case var $1?) {
        return ($0, $1);
      }
    }
    this._recover(_mark);
    if (this.f1x() case var $0?) {
      if (this._applyMemo(this.rm) case var $1?) {
        if (this.f23() case var $2?) {
          if (this._applyMemo(this.ro) case var $3?) {
            if (this.f1y() case var $4?) {
              return ($0, $1, $2, $3, $4);
            }
          }
        }
      }
    }
    this._recover(_mark);
    if (this.f1x() case var $0?) {
      if (this._applyMemo(this.rm) case var $1?) {
        if (this.f4s() case var $2) {
          if (this.f1y() case var $3?) {
            return ($0, $1, $2, $3);
          }
        }
      }
    }
    this._recover(_mark);
    if (this.f1x() case var $0?) {
      if (this._applyMemo(this.ro) case var $1?) {
        if (this.f1y() case var $2?) {
          return ($0, $1, $2);
        }
      }
    }
  }

  /// `global::dart::recordTypeFields`
  List<(List<(String, Object)>, Object, String?)>? rm() {
    if (this.rn() case var _0?) {
      if ([_0] case var _l1) {
        for (;;) {
          var _mark = this._mark();
          if (this.f23() case _?) {
            if (this.rn() case var _0?) {
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

  /// `global::dart::recordTypeField`
  (List<(String, Object)>, Object, String?)? rn() {
    if (this._applyMemo(this.r6)! case var $0) {
      if (this._applyMemo(this.re) case var $1?) {
        if (this.f4t() case var $2) {
          return ($0, $1, $2);
        }
      }
    }
  }

  /// `global::dart::recordTypeNamedFields`
  (String, List<(List<(String, Object)>, (Object, String))>, String?, String)? ro() {
    if (this.f21() case var $0?) {
      if (this.f4u() case var $1?) {
        if (this.f4v() case var $2) {
          if (this.f22() case var $3?) {
            return ($0, $1, $2, $3);
          }
        }
      }
    }
  }

  /// `global::dart::recordTypeNamedField`
  (List<(String, Object)>, (Object, String))? rp() {
    if (this._applyMemo(this.r6)! case var $0) {
      if (this._applyMemo(this.rq) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `global::dart::typedIdentifier`
  (Object, String)? rq() {
    if (this._applyMemo(this.re) case var $0?) {
      if (this._applyMemo(this.r7m) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `global::dart::functionType`
  (Object?, (List<((String, (String, List<(List<(String, Object)>, String, (String, (Record, String?))?)>, String)?, Record), String?)>, (String, (String, List<(List<(String, Object)>, String, (String, (Record, String?))?)>, String)?, Record)))? rr() {
    if (this.f4w() case var $0) {
      if (this.rs() case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `global::dart::functionTypeTails`
  (List<((String, (String, List<(List<(String, Object)>, String, (String, (Record, String?))?)>, String)?, Record), String?)>, (String, (String, List<(List<(String, Object)>, String, (String, (Record, String?))?)>, String)?, Record))? rs() {
    if (this.f4z() case var $0) {
      if (this._applyMemo(this.rt) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `global::dart::functionTypeTail`
  (String, (String, List<(List<(String, Object)>, String, (String, (Record, String?))?)>, String)?, Record)? rt() {
    if (this.ft() case var $0?) {
      if (this.f50() case var $1) {
        if (this.ru() case var $2?) {
          return ($0, $1, $2);
        }
      }
    }
  }

  /// `global::dart::parameterTypeList`
  Record? ru() {
    var _mark = this._mark();
    if (this.f1x() case var $0?) {
      if (this.f1y() case var $1?) {
        return ($0, $1);
      }
    }
    this._recover(_mark);
    if (this.f1x() case var $0?) {
      if (this._applyMemo(this.rv) case var $1?) {
        if (this.f23() case var $2?) {
          if (this._applyMemo(this.rx) case var $3?) {
            if (this.f1y() case var $4?) {
              return ($0, $1, $2, $3, $4);
            }
          }
        }
      }
    }
    this._recover(_mark);
    if (this.f1x() case var $0?) {
      if (this._applyMemo(this.rv) case var $1?) {
        if (this.f51() case var $2) {
          if (this.f1y() case var $3?) {
            return ($0, $1, $2, $3);
          }
        }
      }
    }
    this._recover(_mark);
    if (this.f1x() case var $0?) {
      if (this._applyMemo(this.rx) case var $1?) {
        if (this.f1y() case var $2?) {
          return ($0, $1, $2);
        }
      }
    }
  }

  /// `global::dart::normalParameterTypes`
  List<(List<(String, Object)>, Object)>? rv() {
    if (this._applyMemo(this.rw) case var _0?) {
      if ([_0] case var _l1) {
        for (;;) {
          var _mark = this._mark();
          if (this.f23() case _?) {
            if (this._applyMemo(this.rw) case var _0?) {
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

  /// `global::dart::normalParameterType`
  (List<(String, Object)>, Object)? rw() {
    if (this._applyMemo(this.r6)! case var $0) {
      if (this.f52() case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `global::dart::optionalParameterTypes`
  (String, List<Record>, String?, String)? rx() {
    var _mark = this._mark();
    if (this.ry() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.rz() case var $?) {
      return $;
    }
  }

  /// `global::dart::optionalPositionalParameterTypes`
  (String, List<(List<(String, Object)>, Object)>, String?, String)? ry() {
    if (this.f1z() case var $0?) {
      if (this.f53() case var $1?) {
        if (this.f54() case var $2) {
          if (this.f20() case var $3?) {
            return ($0, $1, $2, $3);
          }
        }
      }
    }
  }

  /// `global::dart::namedParameterTypes`
  (String, List<(List<(String, Object)>, String?, (Object, String))>, String?, String)? rz() {
    if (this.f21() case var $0?) {
      if (this.f55() case var $1?) {
        if (this.f56() case var $2) {
          if (this.f22() case var $3?) {
            return ($0, $1, $2, $3);
          }
        }
      }
    }
  }

  /// `global::dart::namedParameterType`
  (List<(String, Object)>, String?, (Object, String))? r10() {
    if (this._applyMemo(this.r6)! case var $0) {
      if (this.f57() case var $1) {
        if (this._applyMemo(this.rq) case var $2?) {
          return ($0, $1, $2);
        }
      }
    }
  }

  /// `global::dart::typeParameters`
  (String, List<(List<(String, Object)>, String, (String, (Record, String?))?)>, String)? r11() {
    if (this.f2a() case var $0?) {
      if (this.f58() case var $1?) {
        if (this.f29() case var $2?) {
          return ($0, $1, $2);
        }
      }
    }
  }

  /// `global::dart::typeParameter`
  (List<(String, Object)>, String, (String, (Record, String?))?)? r12() {
    if (this._applyMemo(this.r6)! case var $0) {
      if (this._applyMemo(this.rc) case var $1?) {
        if (this.f59() case var $2) {
          return ($0, $1, $2);
        }
      }
    }
  }

  /// `global::dart::classDeclaration`
  Record? r13() {
    var _mark = this._mark();
    if (this.f5a() case var $0) {
      if (this.f5b() case var $1) {
        if (this.fa() case var $2?) {
          if (this._applyMemo(this.r16) case var $3?) {
            if (this.f5c() case var $4) {
              if (this.f5d() case var $5) {
                if (this._applyMemo(this.r1e) case var $6?) {
                  return ($0, $1, $2, $3, $4, $5, $6);
                }
              }
            }
          }
        }
      }
    }
    this._recover(_mark);
    if (this._applyMemo(this.r14)! case var $0) {
      if (this.f5e() case var $1) {
        if (this.fa() case var $2?) {
          if (this.r1c() case var $3?) {
            return ($0, $1, $2, $3);
          }
        }
      }
    }
  }

  /// `global::dart::classModifiers`
  Object r14() {
    var _mark = this._mark();
    if (this.f1e() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.f5f() case var $0) {
      if (this.f5g() case var $1) {
        return ($0, $1);
      }
    }
  }

  /// `global::dart::mixinClassModifiers`
  (String?, String?, String)? r15() {
    if (this.f5h() case var $0) {
      if (this.f5i() case var $1) {
        if (this.f14() case var $2?) {
          return ($0, $1, $2);
        }
      }
    }
  }

  /// `global::dart::classNameMaybePrimary`
  Record? r16() {
    var _mark = this._mark();
    if (this._applyMemo(this.r1t) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this._applyMemo(this.r17) case var $?) {
      return $;
    }
  }

  /// `global::dart::typeWithParameters`
  (String, (String, List<(List<(String, Object)>, String, (String, (Record, String?))?)>, String)?)? r17() {
    if (this._applyMemo(this.rc) case var $0?) {
      if (this.f5j() case var $1) {
        return ($0, $1);
      }
    }
  }

  /// `global::dart::superclass`
  Record? r18() {
    var _mark = this._mark();
    if (this.fl() case var $0?) {
      if (this._applyMemo(this.rh) case var $1?) {
        if (this.f5k() case var $2) {
          return ($0, $1, $2);
        }
      }
    }
    this._recover(_mark);
    if (this._applyMemo(this.r19) case var $?) {
      return $;
    }
  }

  /// `global::dart::mixins`
  (String, List<((String, Object?)?, Object?)>)? r19() {
    if (this.f5l() case var $0?) {
      if (this._applyMemo(this.r1b) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `global::dart::interfaces`
  (String, List<((String, Object?)?, Object?)>)? r1a() {
    if (this.fx() case var $0?) {
      if (this._applyMemo(this.r1b) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `global::dart::typeNotVoidNotFunctionList`
  List<((String, Object?)?, Object?)>? r1b() {
    if (this._applyMemo(this.rh) case var _0?) {
      if ([_0] case var _l1) {
        for (;;) {
          var _mark = this._mark();
          if (this.f23() case _?) {
            if (this._applyMemo(this.rh) case var _0?) {
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

  /// `global::dart::mixinApplicationClass`
  ((String, (String, List<(List<(String, Object)>, String, (String, (Record, String?))?)>, String)?), String, (((String, Object?)?, Object?), (String, List<((String, Object?)?, Object?)>), (String, List<((String, Object?)?, Object?)>)?), String)? r1c() {
    if (this._applyMemo(this.r17) case var $0?) {
      if (this.f28() case var $1?) {
        if (this.r1d() case var $2?) {
          if (this.f25() case var $3?) {
            return ($0, $1, $2, $3);
          }
        }
      }
    }
  }

  /// `global::dart::mixinApplication`
  (((String, Object?)?, Object?), (String, List<((String, Object?)?, Object?)>), (String, List<((String, Object?)?, Object?)>)?)? r1d() {
    if (this._applyMemo(this.rh) case var $0?) {
      if (this._applyMemo(this.r19) case var $1?) {
        if (this.f5m() case var $2) {
          return ($0, $1, $2);
        }
      }
    }
  }

  /// `global::dart::memberedDeclarationBody`
  Object? r1e() {
    var _mark = this._mark();
    if (this.f21() case var $0?) {
      if (this._applyMemo(this.r1f)! case var $1) {
        if (this.f22() case var $2?) {
          return ($0, $1, $2);
        }
      }
    }
    this._recover(_mark);
    if (this.f25() case var $?) {
      return $;
    }
  }

  /// `global::dart::memberDeclarations`
  List<(List<(String, Object)>, String?, (Record, Object))> r1f() {
    var _mark = this._mark();
      if (this.f5o() case var _0) {
        if ([if (_0 case var _0?) _0] case var _l1) {
          if (_l1.isNotEmpty) {
            for (;;) {
              var _mark = this._mark();
              if (this.f5o() case var _0?) {
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

  /// `global::dart::memberDeclaration`
  (Record, Object)? r1g() {
    var _mark = this._mark();
    if (this.r1h() case var $0?) {
      if (this._applyMemo(this.r34) case var $1?) {
        return ($0, $1);
      }
    }
    this._recover(_mark);
    if (this.r1i() case var $0?) {
      if (this.f25() case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `global::dart::methodSignature`
  Record? r1h() {
    var _mark = this._mark();
    if (this._applyMemo(this.r1q) case var $0?) {
      if (this._applyMemo(this.r26) case var $1?) {
        return ($0, $1);
      }
    }
    this._recover(_mark);
    if (this._applyMemo(this.r2b) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.f5p() case var $0) {
      if (this._applyMemo(this.r2p) case var $1?) {
        return ($0, $1);
      }
    }
    this._recover(_mark);
    if (this.f5q() case var $0) {
      if (this._applyMemo(this.r1o) case var $1?) {
        return ($0, $1);
      }
    }
    this._recover(_mark);
    if (this.f5r() case var $0) {
      if (this._applyMemo(this.r1p) case var $1?) {
        return ($0, $1);
      }
    }
    this._recover(_mark);
    if (this._applyMemo(this.r1l) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this._applyMemo(this.r1q) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this._applyMemo(this.r1u) case var $?) {
      return $;
    }
  }

  /// `global::dart::declaration`
  Record? r1i() {
    var _mark = this._mark();
    if (this.f5s() case var $0) {
      if (this._applyMemo(this.r2b) case var $1?) {
        return ($0, $1);
      }
    }
    this._recover(_mark);
    if (this.fn() case var $0?) {
      if (this._applyMemo(this.r2f) case var $1?) {
        return ($0, $1);
      }
    }
    this._recover(_mark);
    if (this.fn() case var $0?) {
      if (this._applyMemo(this.r1q) case var $1?) {
        return ($0, $1);
      }
    }
    this._recover(_mark);
    if (this.f5t() case var $0) {
      if (this.f5u() case var $1) {
        if (this._applyMemo(this.r1o) case var $2?) {
          return ($0, $1, $2);
        }
      }
    }
    this._recover(_mark);
    if (this.f5v() case var $0) {
      if (this.f5w() case var $1) {
        if (this._applyMemo(this.r1p) case var $2?) {
          return ($0, $1, $2);
        }
      }
    }
    this._recover(_mark);
    if (this.f5x() case var $0) {
      if (this.f5y() case var $1) {
        if (this._applyMemo(this.r2p) case var $2?) {
          return ($0, $1, $2);
        }
      }
    }
    this._recover(_mark);
    if (this.fn() case var $0?) {
      if (this.f60() case var $1?) {
        if (this._applyMemo(this.r5) case var $2?) {
          return ($0, $1, $2);
        }
      }
    }
    this._recover(_mark);
    if (this.f61() case var $0) {
      if (this._applyMemo(this.r1l) case var $1?) {
        return ($0, $1);
      }
    }
    this._recover(_mark);
    if (this.f0() case var $0?) {
      if (this.f62() case var $1?) {
        if (this._applyMemo(this.r5) case var $2?) {
          return ($0, $1, $2);
        }
      }
    }
    this._recover(_mark);
    if (this.f1h() case var $0?) {
      if (this.f0() case var $1?) {
        if (this._applyMemo(this.r3) case var $2?) {
          if (this._applyMemo(this.r5) case var $3?) {
            return ($0, $1, $2, $3);
          }
        }
      }
    }
    this._recover(_mark);
    if (this.f1h() case var $0?) {
      if (this.f63() case var $1?) {
        if (this.f64() case var $2) {
          if (this._applyMemo(this.r1j) case var $3?) {
            return ($0, $1, $2, $3);
          }
        }
      }
    }
    this._recover(_mark);
    if (this.f1h() case var $0?) {
      if (this.f12() case var $1?) {
        if (this.fq() case var $2?) {
          if (this.f65() case var $3) {
            if (this._applyMemo(this.r3g) case var $4?) {
              return ($0, $1, $2, $3, $4);
            }
          }
        }
      }
    }
    this._recover(_mark);
    if (this.f1h() case var $0?) {
      if (this.f66() case var $1) {
        if (this._applyMemo(this.r4) case var $2?) {
          if (this._applyMemo(this.r3g) case var $3?) {
            return ($0, $1, $2, $3);
          }
        }
      }
    }
    this._recover(_mark);
    if (this.fd() case var $0?) {
      if (this.f12() case var $1?) {
        if (this.fq() case var $2?) {
          if (this.f67() case var $3) {
            if (this._applyMemo(this.r5) case var $4?) {
              return ($0, $1, $2, $3, $4);
            }
          }
        }
      }
    }
    this._recover(_mark);
    if (this.fd() case var $0?) {
      if (this.f68() case var $1) {
        if (this._applyMemo(this.r4) case var $2?) {
          if (this._applyMemo(this.r3g) case var $3?) {
            return ($0, $1, $2, $3);
          }
        }
      }
    }
    this._recover(_mark);
    if (this.f69() case var $0) {
      if (this.f6b() case var $1?) {
        if (this._applyMemo(this.r3g) case var $2?) {
          return ($0, $1, $2);
        }
      }
    }
    this._recover(_mark);
    if (this.r2e() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this._applyMemo(this.r2f) case var $0?) {
      if (this.f6c() case var $1) {
        return ($0, $1);
      }
    }
    this._recover(_mark);
    if (this._applyMemo(this.r1q) case var $0?) {
      if (this.f6d() case var $1) {
        return ($0, $1);
      }
    }
    this._recover(_mark);
    if (this._applyMemo(this.r1u) case var $?) {
      return $;
    }
  }

  /// `global::dart::staticFinalDeclarationList`
  List<(String, String, Record)>? r1j() {
    if (this.r1k() case var _0?) {
      if ([_0] case var _l1) {
        for (;;) {
          var _mark = this._mark();
          if (this.f23() case _?) {
            if (this.r1k() case var _0?) {
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

  /// `global::dart::staticFinalDeclaration`
  (String, String, Record)? r1k() {
    if (this._applyMemo(this.r7m) case var $0?) {
      if (this.f28() case var $1?) {
        if (this._applyMemo(this.r4n) case var $2?) {
          return ($0, $1, $2);
        }
      }
    }
  }

  /// `global::dart::operatorSignature`
  (Object?, String, Object, Record)? r1l() {
    if (this.f6e() case var $0) {
      if (this.f19() case var $1?) {
        if (this._applyMemo(this.r1m) case var $2?) {
          if (this._applyMemo(this.r2r) case var $3?) {
            return ($0, $1, $2, $3);
          }
        }
      }
    }
  }

  /// `global::dart::operator`
  Object? r1m() {
    var _mark = this._mark();
    if (this.f2c() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.r1n() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.f1z() case var $0?) {
      if (this.f20() case var $1?) {
        return ($0, $1);
      }
    }
    this._recover(_mark);
    if (this.f1z() case var $0?) {
      if (this.f20() case var $1?) {
        if (this.f28() case var $2?) {
          return ($0, $1, $2);
        }
      }
    }
  }

  /// `global::dart::binaryOperator`
  Object? r1n() {
    var _mark = this._mark();
    if (this._applyMemo(this.r6f) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this._applyMemo(this.r6d) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this._applyMemo(this.r6b) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this._applyMemo(this.r65) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.f2m() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.r69() case var $?) {
      return $;
    }
  }

  /// `global::dart::getterSignature`
  (Object?, String, String)? r1o() {
    if (this.f6f() case var $0) {
      if (this.fu() case var $1?) {
        if (this._applyMemo(this.r7m) case var $2?) {
          return ($0, $1, $2);
        }
      }
    }
  }

  /// `global::dart::setterSignature`
  (Object?, String, String, Record)? r1p() {
    if (this.f6g() case var $0) {
      if (this.f1f() case var $1?) {
        if (this._applyMemo(this.r7m) case var $2?) {
          if (this._applyMemo(this.r2r) case var $3?) {
            return ($0, $1, $2, $3);
          }
        }
      }
    }
  }

  /// `global::dart::constructorSignature`
  ((String, Object?), Record)? r1q() {
    if (this.f6h() case var $0?) {
      if (this._applyMemo(this.r2r) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `global::dart::constructorName`
  (String, (String, String)?)? r1r() {
    if (this._applyMemo(this.rc) case var $0?) {
      if (this.f6i() case var $1) {
        return ($0, $1);
      }
    }
  }

  /// `global::dart::constructorHead`
  (String, String?)? r1s() {
    if (this.f15() case var $0?) {
      if (this.f6j() case var $1) {
        return ($0, $1);
      }
    }
  }

  /// `global::dart::primaryConstructor`
  (String?, (String, (String, List<(List<(String, Object)>, String, (String, (Record, String?))?)>, String)?), (String, String)?, Record)? r1t() {
    if (this.f6k() case var $0) {
      if (this._applyMemo(this.r17) case var $1?) {
        if (this.f6l() case var $2) {
          if (this.r1v() case var $3?) {
            return ($0, $1, $2, $3);
          }
        }
      }
    }
  }

  /// `global::dart::primaryConstructorBodySignature`
  (String, (String, List<Record>)?)? r1u() {
    if (this.f1l() case var $0?) {
      if (this.f6m() case var $1) {
        return ($0, $1);
      }
    }
  }

  /// `global::dart::declaringParameterList`
  Record? r1v() {
    var _mark = this._mark();
    if (this.f1x() case var $0?) {
      if (this.f1y() case var $1?) {
        return ($0, $1);
      }
    }
    this._recover(_mark);
    if (this.f1x() case var $0?) {
      if (this._applyMemo(this.r1w) case var $1?) {
        if (this.f6n() case var $2) {
          if (this.f1y() case var $3?) {
            return ($0, $1, $2, $3);
          }
        }
      }
    }
    this._recover(_mark);
    if (this.f1x() case var $0?) {
      if (this._applyMemo(this.r1w) case var $1?) {
        if (this.f23() case var $2?) {
          if (this._applyMemo(this.r21) case var $3?) {
            if (this.f1y() case var $4?) {
              return ($0, $1, $2, $3, $4);
            }
          }
        }
      }
    }
    this._recover(_mark);
    if (this.f1x() case var $0?) {
      if (this._applyMemo(this.r21) case var $1?) {
        if (this.f1y() case var $2?) {
          return ($0, $1, $2);
        }
      }
    }
  }

  /// `global::dart::declaringFormalParameters`
  List<(List<(String, Object)>, Record)>? r1w() {
    if (this._applyMemo(this.r1x) case var _0?) {
      if ([_0] case var _l1) {
        for (;;) {
          var _mark = this._mark();
          if (this.f23() case _?) {
            if (this._applyMemo(this.r1x) case var _0?) {
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

  /// `global::dart::declaringFormalParameter`
  (List<(String, Object)>, Record)? r1x() {
    if (this._applyMemo(this.r6)! case var $0) {
      if (this._applyMemo(this.r1y) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `global::dart::declaringFormalParameterNoMetadata`
  Record? r1y() {
    var _mark = this._mark();
    if (this.r1z() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this._applyMemo(this.r2x) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.r20() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this._applyMemo(this.r2y) case var $?) {
      return $;
    }
  }

  /// `global::dart::declaringFunctionFormalParameter`
  (String?, String?, Object?, String, ((String, List<(List<(String, Object)>, String, (String, (Record, String?))?)>, String)?, Record), String?)? r1z() {
    if (this.f6o() case var $0) {
      if (this.f6p() case var $1) {
        if (this.f6q() case var $2) {
          if (this._applyMemo(this.r7m) case var $3?) {
            if (this._applyMemo(this.r2q) case var $4?) {
              if (this.f6r() case var $5) {
                return ($0, $1, $2, $3, $4, $5);
              }
            }
          }
        }
      }
    }
  }

  /// `global::dart::declaringSimpleFormalParameter`
  (String?, String?, Object?, String)? r20() {
    if (this.f6s() case var $0) {
      if (this.f6t() case var $1) {
        if (this.f6u() case var $2) {
          if (this._applyMemo(this.r7m) case var $3?) {
            return ($0, $1, $2, $3);
          }
        }
      }
    }
  }

  /// `global::dart::optionalOrNamedDeclaringFormalParameters`
  (String, List<Record>, String?, String)? r21() {
    var _mark = this._mark();
    if (this.r22() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.r24() case var $?) {
      return $;
    }
  }

  /// `global::dart::optionalPositionalDeclaringFormalParameters`
  (String, List<((List<(String, Object)>, Record), (String, Record)?)>, String?, String)? r22() {
    if (this.f1z() case var $0?) {
      if (this.f6v() case var $1?) {
        if (this.f6w() case var $2) {
          if (this.f20() case var $3?) {
            return ($0, $1, $2, $3);
          }
        }
      }
    }
  }

  /// `global::dart::defaultDeclaringFormalParameter`
  ((List<(String, Object)>, Record), (String, Record)?)? r23() {
    if (this._applyMemo(this.r1x) case var $0?) {
      if (this.f6x() case var $1) {
        return ($0, $1);
      }
    }
  }

  /// `global::dart::namedDeclaringFormalParameters`
  (String, List<(List<(String, Object)>, String?, Record, (String, Record)?)>, String?, String)? r24() {
    if (this.f21() case var $0?) {
      if (this.f6y() case var $1?) {
        if (this.f6z() case var $2) {
          if (this.f22() case var $3?) {
            return ($0, $1, $2, $3);
          }
        }
      }
    }
  }

  /// `global::dart::defaultDeclaringNamedParameter`
  (List<(String, Object)>, String?, Record, (String, Record)?)? r25() {
    if (this._applyMemo(this.r6)! case var $0) {
      if (this.f70() case var $1) {
        if (this._applyMemo(this.r1y) case var $2?) {
          if (this.f71() case var $3) {
            return ($0, $1, $2, $3);
          }
        }
      }
    }
  }

  /// `global::dart::initializers`
  (String, List<Record>)? r26() {
    if (this.f24() case var $0?) {
      if (this.f72() case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `global::dart::initializerListEntry`
  Record? r27() {
    var _mark = this._mark();
    if (this.f1i() case var $0?) {
      if (this._applyMemo(this.r5o) case var $1?) {
        return ($0, $1);
      }
    }
    this._recover(_mark);
    if (this.f1i() case var $0?) {
      if (this.f26() case var $1?) {
        if (this._applyMemo(this.r9) case var $2?) {
          if (this._applyMemo(this.r5o) case var $3?) {
            return ($0, $1, $2, $3);
          }
        }
      }
    }
    this._recover(_mark);
    if (this.r28() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this._applyMemo(this.r46) case var $?) {
      return $;
    }
  }

  /// `global::dart::fieldInitializer`
  ((String, String)?, String, String, Record)? r28() {
    if (this.f73() case var $0) {
      if (this._applyMemo(this.r7m) case var $1?) {
        if (this.f28() case var $2?) {
          if (this.r29() case var $3?) {
            return ($0, $1, $2, $3);
          }
        }
      }
    }
  }

  /// `global::dart::initializerExpression`
  Record? r29() {
    var _mark = this._mark();
    if (this._applyMemo(this.r5d) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this._applyMemo(this.r6o) case var $0?) {
      if (this._applyMemo(this.r5w) case var $1?) {
        if (this._applyMemo(this.r4n) case var $2?) {
          return ($0, $1, $2);
        }
      }
    }
    this._recover(_mark);
    if (this._applyMemo(this.r5y) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this._applyLr(this.r5r) case var $?) {
      return $;
    }
  }

  /// `global::dart::redirection`
  (String, String, (String, String)?, (String, (List<((String, String)?, Record)>, String?)?, String))? r2a() {
    if (this.f24() case var $0?) {
      if (this.f1l() case var $1?) {
        if (this.f74() case var $2) {
          if (this._applyMemo(this.r5o) case var $3?) {
            return ($0, $1, $2, $3);
          }
        }
      }
    }
  }

  /// `global::dart::factoryConstructorSignature`
  Record? r2b() {
    var _mark = this._mark();
    if (this.f75() case var $0) {
      if (this.fo() case var $1?) {
        if (this.r2c() case var $2?) {
          if (this._applyMemo(this.r2r) case var $3?) {
            return ($0, $1, $2, $3);
          }
        }
      }
    }
    this._recover(_mark);
    if (this.f76() case var $0) {
      if (this.r2d() case var $1?) {
        if (this._applyMemo(this.r2r) case var $2?) {
          return ($0, $1, $2);
        }
      }
    }
  }

  /// `global::dart::constructorTwoPartName`
  (String, String, String)? r2c() {
    if (this._applyMemo(this.rc) case var $0?) {
      if (this.f26() case var $1?) {
        if (this._applyMemo(this.r9) case var $2?) {
          return ($0, $1, $2);
        }
      }
    }
  }

  /// `global::dart::factoryConstructorHead`
  (String, String?)? r2d() {
    if (this.fo() case var $0?) {
      if (this.f77() case var $1) {
        return ($0, $1);
      }
    }
  }

  /// `global::dart::redirectingFactoryConstructorSignature`
  (Record, String, Object)? r2e() {
    if (this._applyMemo(this.r2b) case var $0?) {
      if (this.f28() case var $1?) {
        if (this._applyMemo(this.ra) case var $2?) {
          return ($0, $1, $2);
        }
      }
    }
  }

  /// `global::dart::constantConstructorSignature`
  (String, ((String, Object?), Record))? r2f() {
    if (this.fb() case var $0?) {
      if (this._applyMemo(this.r1q) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `global::dart::mixinDeclaration`
  (String?, String?, Object, (String, Object?)?, (String, List<((String, Object?)?, Object?)>)?, Object)? r2g() {
    var _mark = this._mark();
    if (this.f78() case var $0) {
      if (this.f14() case var $1?) {
        if (this._applyMemo(this.r17) case var $2?) {
          if (this.f79() case var $3) {
            if (this.f7a() case var $4) {
              if (this._applyMemo(this.r1e) case var $5?) {
                return ($0, $1, $2, $3, $4, $5);
              }
            }
          }
        }
      }
    }
    this._recover(_mark);
    if (this.f4() case var $0?) {
      if (this.f7b() case var $1) {
        if (this.f14() case var $2?) {
          if (this._applyMemo(this.r17) case var $3?) {
            if (this.f7c() case var $4) {
              if (this._applyMemo(this.r1e) case var $5?) {
                return ($0, $1, $2, $3, $4, $5);
              }
            }
          }
        }
      }
    }
  }

  /// `global::dart::extensionTypeDeclaration`
  Record? r2h() {
    var _mark = this._mark();
    if (this.fm() case var $0?) {
      if (this.f1p() case var $1?) {
        if (this._applyMemo(this.r1t) case var $2?) {
          if (this.f7d() case var $3) {
            if (this._applyMemo(this.r1e) case var $4?) {
              return ($0, $1, $2, $3, $4);
            }
          }
        }
      }
    }
    this._recover(_mark);
    if (this.f4() case var $0?) {
      if (this.fm() case var $1?) {
        if (this.f1p() case var $2?) {
          if (this._applyMemo(this.r17) case var $3?) {
            if (this.f7e() case var $4) {
              if (this._applyMemo(this.r1e) case var $5?) {
                return ($0, $1, $2, $3, $4, $5);
              }
            }
          }
        }
      }
    }
  }

  /// `global::dart::extensionDeclaration`
  Record? r2i() {
    var _mark = this._mark();
    if (this.fm() case var $0?) {
      if (this.f7f() case var $1) {
        if (this.f7g() case var $2) {
          if (this.f18() case var $3?) {
            if (this._applyMemo(this.re) case var $4?) {
              if (this._applyMemo(this.r1e) case var $5?) {
                return ($0, $1, $2, $3, $4, $5);
              }
            }
          }
        }
      }
    }
    this._recover(_mark);
    if (this.f4() case var $0?) {
      if (this.fm() case var $1?) {
        if (this._applyMemo(this.rd) case var $2?) {
          if (this.f7h() case var $3) {
            if (this._applyMemo(this.r1e) case var $4?) {
              return ($0, $1, $2, $3, $4);
            }
          }
        }
      }
    }
  }

  /// `global::dart::enumType`
  (String?, String, Record, (String, List<((String, Object?)?, Object?)>)?, (String, List<((String, Object?)?, Object?)>)?, Object)? r2j() {
    if (this.f7i() case var $0) {
      if (this.f7j() case var $1?) {
        if (this._applyMemo(this.r16) case var $2?) {
          if (this.f7k() case var $3) {
            if (this.f7l() case var $4) {
              if (this.r2k() case var $5?) {
                return ($0, $1, $2, $3, $4, $5);
              }
            }
          }
        }
      }
    }
  }

  /// `global::dart::enumBody`
  Object? r2k() {
    var _mark = this._mark();
    if (this.f21() case var $0?) {
      if (this.f7o() case var $1) {
        if (this.f7p() case var $2) {
          if (this.f22() case var $3?) {
            return ($0, $1, $2, $3);
          }
        }
      }
    }
    this._recover(_mark);
    if (this.f25() case var $?) {
      return $;
    }
  }

  /// `global::dart::enumEntry`
  Record? r2l() {
    var _mark = this._mark();
    if (this._applyMemo(this.r6)! case var $0) {
      if (this.f7q() case var $1) {
        if (this._applyMemo(this.r7m) case var $2?) {
          if (this.f7r() case var $3) {
            return ($0, $1, $2, $3);
          }
        }
      }
    }
    this._recover(_mark);
    if (this._applyMemo(this.r6)! case var $0) {
      if (this.f7s() case var $1) {
        if (this._applyMemo(this.r7m) case var $2?) {
          if (this.f7t() case var $3) {
            if (this.f26() case var $4?) {
              if (this._applyMemo(this.r9) case var $5?) {
                if (this._applyMemo(this.r5o) case var $6?) {
                  return ($0, $1, $2, $3, $4, $5, $6);
                }
              }
            }
          }
        }
      }
    }
  }

  /// `global::dart::typeAlias`
  Record? r2m() {
    var _mark = this._mark();
    if (this.f7u() case var $0) {
      if (this.f1q() case var $1?) {
        if (this._applyMemo(this.r17) case var $2?) {
          if (this.f28() case var $3?) {
            if (this._applyMemo(this.re) case var $4?) {
              if (this.f25() case var $5?) {
                return ($0, $1, $2, $3, $4, $5);
              }
            }
          }
        }
      }
    }
    this._recover(_mark);
    if (this.f7v() case var $0) {
      if (this.f1q() case var $1?) {
        if (this.r2n() case var $2?) {
          return ($0, $1, $2);
        }
      }
    }
  }

  /// `global::dart::functionTypeAlias`
  (Object, ((String, List<(List<(String, Object)>, String, (String, (Record, String?))?)>, String)?, Record), String)? r2n() {
    if (this.r2o() case var $0?) {
      if (this._applyMemo(this.r2q) case var $1?) {
        if (this.f25() case var $2?) {
          return ($0, $1, $2);
        }
      }
    }
  }

  /// `global::dart::functionPrefix`
  Object? r2o() {
    var _mark = this._mark();
    if (this._applyMemo(this.re) case var $0?) {
      if (this._applyMemo(this.r7m) case var $1?) {
        return ($0, $1);
      }
    }
    this._recover(_mark);
    if (this._applyMemo(this.r7m) case var $?) {
      return $;
    }
  }

  /// `global::dart::functionSignature`
  (Object?, String, ((String, List<(List<(String, Object)>, String, (String, (Record, String?))?)>, String)?, Record))? r2p() {
    if (this.f7w() case var $0) {
      if (this._applyMemo(this.r7m) case var $1?) {
        if (this._applyMemo(this.r2q) case var $2?) {
          return ($0, $1, $2);
        }
      }
    }
  }

  /// `global::dart::formalParameterPart`
  ((String, List<(List<(String, Object)>, String, (String, (Record, String?))?)>, String)?, Record)? r2q() {
    if (this.f7x() case var $0) {
      if (this._applyMemo(this.r2r) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `global::dart::formalParameterList`
  Record? r2r() {
    var _mark = this._mark();
    if (this.f1x() case var $0?) {
      if (this.f1y() case var $1?) {
        return ($0, $1);
      }
    }
    this._recover(_mark);
    if (this.f1x() case var $0?) {
      if (this._applyMemo(this.r2s) case var $1?) {
        if (this.f7y() case var $2) {
          if (this.f1y() case var $3?) {
            return ($0, $1, $2, $3);
          }
        }
      }
    }
    this._recover(_mark);
    if (this.f1x() case var $0?) {
      if (this._applyMemo(this.r2s) case var $1?) {
        if (this.f23() case var $2?) {
          if (this._applyMemo(this.r2z) case var $3?) {
            if (this.f1y() case var $4?) {
              return ($0, $1, $2, $3, $4);
            }
          }
        }
      }
    }
    this._recover(_mark);
    if (this.f1x() case var $0?) {
      if (this._applyMemo(this.r2z) case var $1?) {
        if (this.f1y() case var $2?) {
          return ($0, $1, $2);
        }
      }
    }
  }

  /// `global::dart::normalFormalParameters`
  List<(List<(String, Object)>, Record)>? r2s() {
    if (this._applyMemo(this.r2t) case var _0?) {
      if ([_0] case var _l1) {
        for (;;) {
          var _mark = this._mark();
          if (this.f23() case _?) {
            if (this._applyMemo(this.r2t) case var _0?) {
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

  /// `global::dart::normalFormalParameter`
  (List<(String, Object)>, Record)? r2t() {
    if (this._applyMemo(this.r6)! case var $0) {
      if (this._applyMemo(this.r2u) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `global::dart::normalFormalParameterNoMetadata`
  Record? r2u() {
    var _mark = this._mark();
    if (this.r2v() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this._applyMemo(this.r2x) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.r2w() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this._applyMemo(this.r2y) case var $?) {
      return $;
    }
  }

  /// `global::dart::functionFormalParameter`
  (String?, Object?, String, ((String, List<(List<(String, Object)>, String, (String, (Record, String?))?)>, String)?, Record), String?)? r2v() {
    if (this.f7z() case var $0) {
      if (this.f80() case var $1) {
        if (this._applyMemo(this.r7m) case var $2?) {
          if (this._applyMemo(this.r2q) case var $3?) {
            if (this.f81() case var $4) {
              return ($0, $1, $2, $3, $4);
            }
          }
        }
      }
    }
  }

  /// `global::dart::simpleFormalParameter`
  (String?, Object?, String)? r2w() {
    if (this.f82() case var $0) {
      if (this.f83() case var $1) {
        if (this._applyMemo(this.r7m) case var $2?) {
          return ($0, $1, $2);
        }
      }
    }
  }

  /// `global::dart::fieldFormalParameter`
  (Object?, String, String, String, (((String, List<(List<(String, Object)>, String, (String, (Record, String?))?)>, String)?, Record), String?)?)? r2x() {
    if (this.f84() case var $0) {
      if (this.f1l() case var $1?) {
        if (this.f26() case var $2?) {
          if (this._applyMemo(this.r7m) case var $3?) {
            if (this.f86() case var $4) {
              return ($0, $1, $2, $3, $4);
            }
          }
        }
      }
    }
  }

  /// `global::dart::superFormalParameter`
  (Object?, String, String, String, (((String, List<(List<(String, Object)>, String, (String, (Record, String?))?)>, String)?, Record), String?)?)? r2y() {
    if (this.f87() case var $0) {
      if (this.f1i() case var $1?) {
        if (this.f26() case var $2?) {
          if (this._applyMemo(this.r7m) case var $3?) {
            if (this.f89() case var $4) {
              return ($0, $1, $2, $3, $4);
            }
          }
        }
      }
    }
  }

  /// `global::dart::optionalOrNamedFormalParameters`
  (String, List<Record>, String?, String)? r2z() {
    var _mark = this._mark();
    if (this.r30() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.r32() case var $?) {
      return $;
    }
  }

  /// `global::dart::optionalPositionalFormalParameters`
  (String, List<((List<(String, Object)>, Record), (String, Record)?)>, String?, String)? r30() {
    if (this.f1z() case var $0?) {
      if (this.f8a() case var $1?) {
        if (this.f8b() case var $2) {
          if (this.f20() case var $3?) {
            return ($0, $1, $2, $3);
          }
        }
      }
    }
  }

  /// `global::dart::defaultFormalParameter`
  ((List<(String, Object)>, Record), (String, Record)?)? r31() {
    if (this._applyMemo(this.r2t) case var $0?) {
      if (this.f8c() case var $1) {
        return ($0, $1);
      }
    }
  }

  /// `global::dart::namedFormalParameters`
  (String, List<(List<(String, Object)>, String?, Record, (String, Record)?)>, String?, String)? r32() {
    if (this.f21() case var $0?) {
      if (this.f8d() case var $1?) {
        if (this.f8e() case var $2) {
          if (this.f22() case var $3?) {
            return ($0, $1, $2, $3);
          }
        }
      }
    }
  }

  /// `global::dart::defaultNamedParameter`
  (List<(String, Object)>, String?, Record, (String, Record)?)? r33() {
    if (this._applyMemo(this.r6)! case var $0) {
      if (this.f8f() case var $1) {
        if (this._applyMemo(this.r2u) case var $2?) {
          if (this.f8g() case var $3) {
            return ($0, $1, $2, $3);
          }
        }
      }
    }
  }

  /// `global::dart::functionBody`
  Record? r34() {
    var _mark = this._mark();
    if (this.f3c() case var $0?) {
      if (this._applyMemo(this.r4n) case var $1?) {
        if (this.f25() case var $2?) {
          return ($0, $1, $2);
        }
      }
    }
    this._recover(_mark);
    if (this._applyMemo(this.r35) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.f3() case var $0?) {
      if (this.f3c() case var $1?) {
        if (this._applyMemo(this.r4n) case var $2?) {
          if (this.f25() case var $3?) {
            return ($0, $1, $2, $3);
          }
        }
      }
    }
    this._recover(_mark);
    if (this.f8h() case var $0?) {
      if (this._applyMemo(this.r35) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `global::dart::block`
  (String, List<(List<(String, String)>, Record)>, String)? r35() {
    if (this.f21() case var $0?) {
      if (this._applyMemo(this.r36)! case var $1) {
        if (this.f22() case var $2?) {
          return ($0, $1, $2);
        }
      }
    }
  }

  /// `global::dart::statements`
  List<(List<(String, String)>, Record)> r36() {
    var _mark = this._mark();
      if (this._applyMemo(this.r37) case var _0) {
        if ([if (_0 case var _0?) _0] case var _l1) {
          if (_l1.isNotEmpty) {
            for (;;) {
              var _mark = this._mark();
              if (this._applyMemo(this.r37) case var _0?) {
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

  /// `global::dart::statement`
  (List<(String, String)>, Record)? r37() {
    if (this.f8i() case var $0) {
      if (this.r38() case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `global::dart::nonLabelledStatement`
  Record? r38() {
    var _mark = this._mark();
    if (this._applyMemo(this.r35) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this._applyMemo(this.r3b) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.r3m() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.r3q() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.r3r() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.r3s() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.r3k() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.r3v() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.r3w() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.r41() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.r42() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.r40() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.r3j() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.r45() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.r43() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.r44() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.r3a() case var $?) {
      return $;
    }
  }

  /// `global::dart::label`
  (String, String)? r39() {
    if (this._applyMemo(this.r7m) case var $0?) {
      if (this.f24() case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `global::dart::expressionStatement`
  (Record?, String)? r3a() {
    if (this.f8j() case var $0) {
      if (this.f25() case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `global::dart::localVariableDeclaration`
  (List<(String, Object)>, (Record, Object?, Object), String)? r3b() {
    var _mark = this._mark();
    if (this._applyMemo(this.r6)! case var $0) {
      if (this.r3c() case var $1?) {
        if (this.f25() case var $2?) {
          return ($0, $1, $2);
        }
      }
    }
    this._recover(_mark);
    if (this._applyMemo(this.r6)! case var $0) {
      if (this.r3h() case var $1?) {
        if (this.f25() case var $2?) {
          return ($0, $1, $2);
        }
      }
    }
  }

  /// `global::dart::initializedVariableDeclaration`
  ((String?, Record, String), (String, Record)?, List<(String, (String, (String, Record)?))>)? r3c() {
    if (this._applyMemo(this.r3d) case var $0?) {
      if (this.f8k() case var $1) {
        if (this.f8m() case var $2) {
          return ($0, $1, $2);
        }
      }
    }
  }

  /// `global::dart::declaredIdentifier`
  (String?, Record, String)? r3d() {
    if (this.f8n() case var $0) {
      if (this.r3e() case var $1?) {
        if (this._applyMemo(this.r7m) case var $2?) {
          return ($0, $1, $2);
        }
      }
    }
  }

  /// `global::dart::finalConstVarOrType`
  Record? r3e() {
    var _mark = this._mark();
    if (this.f8o() case var $0) {
      if (this.fq() case var $1?) {
        if (this.f8p() case var $2) {
          return ($0, $1, $2);
        }
      }
    }
    this._recover(_mark);
    if (this.fb() case var $0?) {
      if (this.f8q() case var $1) {
        return ($0, $1);
      }
    }
    this._recover(_mark);
    if (this.f8r() case var $0) {
      if (this._applyMemo(this.r4) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `global::dart::initializedIdentifier`
  (String, (String, Record)?)? r3f() {
    if (this._applyMemo(this.r7m) case var $0?) {
      if (this.f8s() case var $1) {
        return ($0, $1);
      }
    }
  }

  /// `global::dart::initializedIdentifierList`
  List<(String, (String, Record)?)>? r3g() {
    if (this._applyMemo(this.r3f) case var _0?) {
      if ([_0] case var _l1) {
        for (;;) {
          var _mark = this._mark();
          if (this.f23() case _?) {
            if (this._applyMemo(this.r3f) case var _0?) {
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

  /// `global::dart::patternVariableDeclaration`
  ((String, Record), String, Record)? r3h() {
    if (this._applyMemo(this.r3i) case var $0?) {
      if (this.f28() case var $1?) {
        if (this._applyMemo(this.r4n) case var $2?) {
          return ($0, $1, $2);
        }
      }
    }
  }

  /// `global::dart::outerPatternDeclarationPrefix`
  (String, Record)? r3i() {
    if (this.f8t() case var $0?) {
      if (this._applyMemo(this.r7j) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `global::dart::localFunctionDeclaration`
  (List<(String, Object)>, (Object?, String, ((String, List<(List<(String, Object)>, String, (String, (Record, String?))?)>, String)?, Record)), Record)? r3j() {
    if (this._applyMemo(this.r6)! case var $0) {
      if (this._applyMemo(this.r2p) case var $1?) {
        if (this._applyMemo(this.r34) case var $2?) {
          return ($0, $1, $2);
        }
      }
    }
  }

  /// `global::dart::ifStatement`
  ((String, String, Record, (String, (((Object, List<(String, Object)>), List<(String, (Object, List<(String, Object)>))>), (String, Record)?))?, String), (List<(String, String)>, Record), (String, (List<(String, String)>, Record))?)? r3k() {
    if (this._applyMemo(this.r3l) case var $0?) {
      if (this._applyMemo(this.r37) case var $1?) {
        if (this.f8u() case var $2) {
          return ($0, $1, $2);
        }
      }
    }
  }

  /// `global::dart::ifCondition`
  (String, String, Record, (String, (((Object, List<(String, Object)>), List<(String, (Object, List<(String, Object)>))>), (String, Record)?))?, String)? r3l() {
    if (this.fw() case var $0?) {
      if (this.f1x() case var $1?) {
        if (this._applyMemo(this.r4n) case var $2?) {
          if (this.f8v() case var $3) {
            if (this.f1y() case var $4?) {
              return ($0, $1, $2, $3, $4);
            }
          }
        }
      }
    }
  }

  /// `global::dart::forStatement`
  (String?, String, String, Record, String, (List<(String, String)>, Record))? r3m() {
    if (this.f8w() case var $0) {
      if (this.fs() case var $1?) {
        if (this.f1x() case var $2?) {
          if (this._applyMemo(this.r3n) case var $3?) {
            if (this.f1y() case var $4?) {
              if (this._applyMemo(this.r37) case var $5?) {
                return ($0, $1, $2, $3, $4, $5);
              }
            }
          }
        }
      }
    }
  }

  /// `global::dart::forLoopParts`
  Record? r3n() {
    var _mark = this._mark();
    if (this.r3o() case var $0?) {
      if (this.f8x() case var $1?) {
        if (this._applyMemo(this.r4n) case var $2?) {
          return ($0, $1, $2);
        }
      }
    }
    this._recover(_mark);
    if (this.r3p() case var $0?) {
      if (this.f8y() case var $1) {
        if (this.f25() case var $2?) {
          if (this.f8z() case var $3) {
            return ($0, $1, $2, $3);
          }
        }
      }
    }
  }

  /// `global::dart::forInLoopPrefix`
  Object? r3o() {
    var _mark = this._mark();
    if (this._applyMemo(this.r6)! case var $0) {
      if (this._applyMemo(this.r3d) case var $1?) {
        return ($0, $1);
      }
    }
    this._recover(_mark);
    if (this._applyMemo(this.r6)! case var $0) {
      if (this._applyMemo(this.r3i) case var $1?) {
        return ($0, $1);
      }
    }
    this._recover(_mark);
    if (this._applyMemo(this.r7m) case var $?) {
      return $;
    }
  }

  /// `global::dart::forInitializerStatement`
  Record? r3p() {
    var _mark = this._mark();
    if (this._applyMemo(this.r3b) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.f90() case var $0) {
      if (this.f25() case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `global::dart::whileStatement`
  (String, String, Record, String, (List<(String, String)>, Record))? r3q() {
    if (this.f1t() case var $0?) {
      if (this.f1x() case var $1?) {
        if (this._applyMemo(this.r4n) case var $2?) {
          if (this.f1y() case var $3?) {
            if (this._applyMemo(this.r37) case var $4?) {
              return ($0, $1, $2, $3, $4);
            }
          }
        }
      }
    }
  }

  /// `global::dart::doStatement`
  (String, (List<(String, String)>, Record), String, String, Record, String, String)? r3r() {
    if (this.f91() case var $0?) {
      if (this._applyMemo(this.r37) case var $1?) {
        if (this.f1t() case var $2?) {
          if (this.f1x() case var $3?) {
            if (this._applyMemo(this.r4n) case var $4?) {
              if (this.f1y() case var $5?) {
                if (this.f25() case var $6?) {
                  return ($0, $1, $2, $3, $4, $5, $6);
                }
              }
            }
          }
        }
      }
    }
  }

  /// `global::dart::switchStatement`
  (String, String, Record, String, String, List<(List<(String, String)>, String, (((Object, List<(String, Object)>), List<(String, (Object, List<(String, Object)>))>), (String, Record)?), String, List<(List<(String, String)>, Record)>)>, (List<(String, String)>, String, String, List<(List<(String, String)>, Record)>)?, String)? r3s() {
    if (this.f1j() case var $0?) {
      if (this.f1x() case var $1?) {
        if (this._applyMemo(this.r4n) case var $2?) {
          if (this.f1y() case var $3?) {
            if (this.f21() case var $4?) {
              if (this.f92() case var $5) {
                if (this.f93() case var $6) {
                  if (this.f22() case var $7?) {
                    return ($0, $1, $2, $3, $4, $5, $6, $7);
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  /// `global::dart::switchStatementCase`
  (List<(String, String)>, String, (((Object, List<(String, Object)>), List<(String, (Object, List<(String, Object)>))>), (String, Record)?), String, List<(List<(String, String)>, Record)>)? r3t() {
    if (this.f94() case var $0) {
      if (this.f8() case var $1?) {
        if (this._applyMemo(this.r7h) case var $2?) {
          if (this.f24() case var $3?) {
            if (this._applyMemo(this.r36)! case var $4) {
              return ($0, $1, $2, $3, $4);
            }
          }
        }
      }
    }
  }

  /// `global::dart::switchStatementDefault`
  (List<(String, String)>, String, String, List<(List<(String, String)>, Record)>)? r3u() {
    if (this.f95() case var $0) {
      if (this.f96() case var $1?) {
        if (this.f24() case var $2?) {
          if (this._applyMemo(this.r36)! case var $3) {
            return ($0, $1, $2, $3);
          }
        }
      }
    }
  }

  /// `global::dart::rethrowStatement`
  (String, String)? r3v() {
    if (this.f97() case var $0?) {
      if (this.f25() case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `global::dart::tryStatement`
  (String, (String, List<(List<(String, String)>, Record)>, String), (Object, Record?))? r3w() {
    if (this.f98() case var $0?) {
      if (this._applyMemo(this.r35) case var $1?) {
        if (this.f9b() case var $2?) {
          return ($0, $1, $2);
        }
      }
    }
  }

  /// `global::dart::onPart`
  Record? r3x() {
    var _mark = this._mark();
    if (this._applyMemo(this.r3y) case var $0?) {
      if (this._applyMemo(this.r35) case var $1?) {
        return ($0, $1);
      }
    }
    this._recover(_mark);
    if (this.f18() case var $0?) {
      if (this._applyMemo(this.rg) case var $1?) {
        if (this.f9c() case var $2) {
          if (this._applyMemo(this.r35) case var $3?) {
            return ($0, $1, $2, $3);
          }
        }
      }
    }
  }

  /// `global::dart::catchPart`
  (String, String, String, (String, String)?, String)? r3y() {
    if (this.f9d() case var $0?) {
      if (this.f1x() case var $1?) {
        if (this._applyMemo(this.r7m) case var $2?) {
          if (this.f9e() case var $3) {
            if (this.f1y() case var $4?) {
              return ($0, $1, $2, $3, $4);
            }
          }
        }
      }
    }
  }

  /// `global::dart::finallyPart`
  (String, (String, List<(List<(String, String)>, Record)>, String))? r3z() {
    if (this.f9f() case var $0?) {
      if (this._applyMemo(this.r35) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `global::dart::returnStatement`
  (String, Record?, String)? r40() {
    if (this.f9g() case var $0?) {
      if (this.f9h() case var $1) {
        if (this.f25() case var $2?) {
          return ($0, $1, $2);
        }
      }
    }
  }

  /// `global::dart::breakStatement`
  (String, String?, String)? r41() {
    if (this.f9i() case var $0?) {
      if (this.f9j() case var $1) {
        if (this.f25() case var $2?) {
          return ($0, $1, $2);
        }
      }
    }
  }

  /// `global::dart::continueStatement`
  (String, String?, String)? r42() {
    if (this.f9k() case var $0?) {
      if (this.f9l() case var $1) {
        if (this.f25() case var $2?) {
          return ($0, $1, $2);
        }
      }
    }
  }

  /// `global::dart::yieldStatement`
  (String, Record, String)? r43() {
    if (this.f1v() case var $0?) {
      if (this._applyMemo(this.r4n) case var $1?) {
        if (this.f25() case var $2?) {
          return ($0, $1, $2);
        }
      }
    }
  }

  /// `global::dart::yieldEachStatement`
  (String, String, Record, String)? r44() {
    if (this.f1v() case var $0?) {
      if (this.f2f() case var $1?) {
        if (this._applyMemo(this.r4n) case var $2?) {
          if (this.f25() case var $3?) {
            return ($0, $1, $2, $3);
          }
        }
      }
    }
  }

  /// `global::dart::assertStatement`
  ((String, String, Record, (String, Record)?, String?, String), String)? r45() {
    if (this._applyMemo(this.r46) case var $0?) {
      if (this.f25() case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `global::dart::assertion`
  (String, String, Record, (String, Record)?, String?, String)? r46() {
    if (this.f9m() case var $0?) {
      if (this.f1x() case var $1?) {
        if (this._applyMemo(this.r4n) case var $2?) {
          if (this.f9n() case var $3) {
            if (this.f9o() case var $4) {
              if (this.f1y() case var $5?) {
                return ($0, $1, $2, $3, $4, $5);
              }
            }
          }
        }
      }
    }
  }

  /// `global::dart::libraryName`
  (List<(String, Object)>, Record, String)? r47() {
    if (this._applyMemo(this.r6)! case var $0) {
      if (this.r48() case var $1?) {
        if (this.f25() case var $2?) {
          return ($0, $1, $2);
        }
      }
    }
  }

  /// `global::dart::libraryNameBody`
  Record? r48() {
    var _mark = this._mark();
    if (this.f13() case var $0?) {
      if (this.f9p() case var $1) {
        return ($0, $1);
      }
    }
    this._recover(_mark);
    if (this.f4() case var $0?) {
      if (this.f13() case var $1?) {
        if (this._applyMemo(this.r4j) case var $2?) {
          return ($0, $1, $2);
        }
      }
    }
  }

  /// `global::dart::dottedIdentifierList`
  List<String>? r49() {
    if (this._applyMemo(this.r7m) case var _0?) {
      if ([_0] case var _l1) {
        for (;;) {
          var _mark = this._mark();
          if (this.f26() case _?) {
            if (this._applyMemo(this.r7m) case var _0?) {
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

  /// `global::dart::importOrExport`
  Record? r4a() {
    var _mark = this._mark();
    if (this.r4b() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.r4c() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.r4f() case var $?) {
      return $;
    }
  }

  /// `global::dart::libraryImport`
  (List<(String, Object)>, (String, (List<(String, List<Object>, String)>, List<(String, String, (List<String>, (String, List<(String, List<Object>, String)>)?), String, List<(String, List<Object>, String)>)>), (String?, String, String)?, List<(String, List<String>)>, String))? r4b() {
    if (this._applyMemo(this.r6)! case var $0) {
      if (this.r4d() case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `global::dart::libraryAugmentImport`
  (List<(String, Object)>, String, String, List<(String, List<Object>, String)>, String)? r4c() {
    if (this._applyMemo(this.r6)! case var $0) {
      if (this.fy() case var $1?) {
        if (this.f4() case var $2?) {
          if (this._applyMemo(this.r4j) case var $3?) {
            if (this.f25() case var $4?) {
              return ($0, $1, $2, $3, $4);
            }
          }
        }
      }
    }
  }

  /// `global::dart::importSpecification`
  (String, (List<(String, List<Object>, String)>, List<(String, String, (List<String>, (String, List<(String, List<Object>, String)>)?), String, List<(String, List<Object>, String)>)>), (String?, String, String)?, List<(String, List<String>)>, String)? r4d() {
    if (this.fy() case var $0?) {
      if (this._applyMemo(this.r4k) case var $1?) {
        if (this.f9r() case var $2) {
          if (this.f9s() case var $3) {
            if (this.f25() case var $4?) {
              return ($0, $1, $2, $3, $4);
            }
          }
        }
      }
    }
  }

  /// `global::dart::combinator`
  (String, List<String>)? r4e() {
    var _mark = this._mark();
    if (this.f1g() case var $0?) {
      if (this._applyMemo(this.r5) case var $1?) {
        return ($0, $1);
      }
    }
    this._recover(_mark);
    if (this.fv() case var $0?) {
      if (this._applyMemo(this.r5) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `global::dart::libraryExport`
  (List<(String, Object)>, String, (List<(String, List<Object>, String)>, List<(String, String, (List<String>, (String, List<(String, List<Object>, String)>)?), String, List<(String, List<Object>, String)>)>), List<(String, List<String>)>, String)? r4f() {
    if (this._applyMemo(this.r6)! case var $0) {
      if (this.fk() case var $1?) {
        if (this._applyMemo(this.r4k) case var $2?) {
          if (this.f9t() case var $3) {
            if (this.f25() case var $4?) {
              return ($0, $1, $2, $3, $4);
            }
          }
        }
      }
    }
  }

  /// `global::dart::partDirective`
  (List<(String, Object)>, String, (List<(String, List<Object>, String)>, List<(String, String, (List<String>, (String, List<(String, List<Object>, String)>)?), String, List<(String, List<Object>, String)>)>), String)? r4g() {
    if (this._applyMemo(this.r6)! case var $0) {
      if (this.f1a() case var $1?) {
        if (this._applyMemo(this.r4k) case var $2?) {
          if (this.f25() case var $3?) {
            return ($0, $1, $2, $3);
          }
        }
      }
    }
  }

  /// `global::dart::partHeader`
  (List<(String, Object)>, String, String, List<(String, List<Object>, String)>, String)? r4h() {
    if (this._applyMemo(this.r6)! case var $0) {
      if (this.f1a() case var $1?) {
        if (this.f17() case var $2?) {
          if (this._applyMemo(this.r4j) case var $3?) {
            if (this.f25() case var $4?) {
              return ($0, $1, $2, $3, $4);
            }
          }
        }
      }
    }
  }

  /// `global::dart::partDeclaration`
  ((List<(String, Object)>, String, String, List<(String, List<Object>, String)>, String), List<Record>, List<(List<(String, Object)>, String, (List<(String, List<Object>, String)>, List<(String, String, (List<String>, (String, List<(String, List<Object>, String)>)?), String, List<(String, List<Object>, String)>)>), String)>, List<(List<(String, Object)>, Record)>, int)? r4i() {
    if (this.r4h() case var $0?) {
      if (this.f9u() case var $1) {
        if (this.f9v() case var $2) {
          if (this.f9x() case var $3) {
            if (this.pos case var $4 when this.pos >= this.buffer.length) {
              return ($0, $1, $2, $3, $4);
            }
          }
        }
      }
    }
  }

  /// `global::dart::uri`
  List<(String, List<Object>, String)>? r4j() {
    if (this.f3j() case var $?) {
      return $;
    }
  }

  /// `global::dart::configurableUri`
  (List<(String, List<Object>, String)>, List<(String, String, (List<String>, (String, List<(String, List<Object>, String)>)?), String, List<(String, List<Object>, String)>)>)? r4k() {
    if (this._applyMemo(this.r4j) case var $0?) {
      if (this.f9y() case var $1) {
        return ($0, $1);
      }
    }
  }

  /// `global::dart::configurationUri`
  (String, String, (List<String>, (String, List<(String, List<Object>, String)>)?), String, List<(String, List<Object>, String)>)? r4l() {
    if (this.fw() case var $0?) {
      if (this.f1x() case var $1?) {
        if (this.r4m() case var $2?) {
          if (this.f1y() case var $3?) {
            if (this._applyMemo(this.r4j) case var $4?) {
              return ($0, $1, $2, $3, $4);
            }
          }
        }
      }
    }
  }

  /// `global::dart::uriTest`
  (List<String>, (String, List<(String, List<Object>, String)>)?)? r4m() {
    if (this._applyMemo(this.r49) case var $0?) {
      if (this.f9z() case var $1) {
        return ($0, $1);
      }
    }
  }

  /// `global::dart::expression`
  Record? r4n() {
    var _mark = this._mark();
    if (this.r7i() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.r5f() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this._applyMemo(this.r5d) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this._applyMemo(this.r6o) case var $0?) {
      if (this._applyMemo(this.r5w) case var $1?) {
        if (this._applyMemo(this.r4n) case var $2?) {
          return ($0, $1, $2);
        }
      }
    }
    this._recover(_mark);
    if (this._applyMemo(this.r5y) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this._applyLr(this.r5r) case var $?) {
      return $;
    }
  }

  /// `global::dart::expressionWithoutCascade`
  Record? r4o() {
    var _mark = this._mark();
    if (this.r5h() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.r5e() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this._applyMemo(this.r6o) case var $0?) {
      if (this._applyMemo(this.r5w) case var $1?) {
        if (this._applyMemo(this.r4o) case var $2?) {
          return ($0, $1, $2);
        }
      }
    }
    this._recover(_mark);
    if (this._applyMemo(this.r5y) case var $?) {
      return $;
    }
  }

  /// `global::dart::expressionList`
  List<Record>? r4p() {
    if (this._applyMemo(this.r4n) case var _0?) {
      if ([_0] case var _l1) {
        for (;;) {
          var _mark = this._mark();
          if (this.f23() case _?) {
            if (this._applyMemo(this.r4n) case var _0?) {
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

  /// `global::dart::primary`
  Object? r4q() {
    var _mark = this._mark();
    if (this.r5l() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.f1i() case var $0?) {
      if (this._applyMemo(this.r6q) case var $1?) {
        return ($0, $1);
      }
    }
    this._recover(_mark);
    if (this.f1i() case var $0?) {
      if (this._applyMemo(this.r6m) case var $1?) {
        return ($0, $1);
      }
    }
    this._recover(_mark);
    if (this.r5j() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.r4s() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this._applyMemo(this.r7m) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.r5m() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this._applyMemo(this.r5n) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.r4r() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.f1x() case var $0?) {
      if (this._applyMemo(this.r4n) case var $1?) {
        if (this.f1y() case var $2?) {
          return ($0, $1, $2);
        }
      }
    }
    this._recover(_mark);
    if (this.r5a() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.r5b() case var $?) {
      return $;
    }
  }

  /// `global::dart::constructorInvocation`
  Record? r4r() {
    var _mark = this._mark();
    if (this._applyMemo(this.rb) case var $0?) {
      if (this._applyMemo(this.rj) case var $1?) {
        if (this.f26() case var $2?) {
          if (this.f15() case var $3?) {
            if (this._applyMemo(this.r5o) case var $4?) {
              return ($0, $1, $2, $3, $4);
            }
          }
        }
      }
    }
    this._recover(_mark);
    if (this._applyMemo(this.rb) case var $0?) {
      if (this.f26() case var $1?) {
        if (this.f15() case var $2?) {
          if (this._applyMemo(this.r5o) case var $3?) {
            return ($0, $1, $2, $3);
          }
        }
      }
    }
  }

  /// `global::dart::literal`
  Object? r4s() {
    var _mark = this._mark();
    if (this._applyMemo(this.r4t) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this._applyMemo(this.r4v) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this._applyMemo(this.r4u) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.f3j() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this._applyMemo(this.r7p) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.r4w() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.r4x() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.r4y() case var $?) {
      return $;
    }
  }

  /// `global::dart::nullLiteral`
  String? r4t() {
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$43) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::dart::numericLiteral`
  String? r4u() {
    var _mark = this._mark();
    if (this.f3m() case _) {
      if (this.faf() case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
    this._recover(_mark);
    if (this.f3m() case _) {
      if (this.fal() case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::dart::booleanLiteral`
  String? r4v() {
    var _mark = this._mark();
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$60) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
    this._recover(_mark);
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$26) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::dart::setOrMapLiteral`
  (String?, (String, List<Object>, String)?, String, List<Record>?, String)? r4w() {
    if (this.fam() case var $0) {
      if (this.fan() case var $1) {
        if (this.f21() case var $2?) {
          if (this.fao() case var $3) {
            if (this.f22() case var $4?) {
              return ($0, $1, $2, $3, $4);
            }
          }
        }
      }
    }
  }

  /// `global::dart::listLiteral`
  (String?, (String, List<Object>, String)?, String, List<Record>?, String)? r4x() {
    if (this.fap() case var $0) {
      if (this.faq() case var $1) {
        if (this.f1z() case var $2?) {
          if (this.far() case var $3) {
            if (this.f20() case var $4?) {
              return ($0, $1, $2, $3, $4);
            }
          }
        }
      }
    }
  }

  /// `global::dart::recordLiteral`
  (String?, Record)? r4y() {
    if (this.fas() case var $0) {
      if (this.r4z() case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `global::dart::recordLiteralNoConst`
  Record? r4z() {
    var _mark = this._mark();
    if (this.f1x() case var $0?) {
      if (this.f1y() case var $1?) {
        return ($0, $1);
      }
    }
    this._recover(_mark);
    if (this.f1x() case var $0?) {
      if (this._applyMemo(this.r4n) case var $1?) {
        if (this.f23() case var $2?) {
          if (this.f1y() case var $3?) {
            return ($0, $1, $2, $3);
          }
        }
      }
    }
    this._recover(_mark);
    if (this.f1x() case var $0?) {
      if (this._applyMemo(this.r39) case var $1?) {
        if (this._applyMemo(this.r4n) case var $2?) {
          if (this.fat() case var $3) {
            if (this.f1y() case var $4?) {
              return ($0, $1, $2, $3, $4);
            }
          }
        }
      }
    }
    this._recover(_mark);
    if (this.f1x() case var $0?) {
      if (this._applyMemo(this.r50) case var $1?) {
        if (this.fav() case var $2?) {
          if (this.faw() case var $3) {
            if (this.f1y() case var $4?) {
              return ($0, $1, $2, $3, $4);
            }
          }
        }
      }
    }
  }

  /// `global::dart::recordField`
  ((String, String)?, Record)? r50() {
    if (this.fax() case var $0) {
      if (this._applyMemo(this.r4n) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `global::dart::elements`
  List<Record>? r51() {
    if (this._applyMemo(this.r52) case var _0?) {
      if ([_0] case var _l1) {
        for (;;) {
          var _mark = this._mark();
          if (this.f23() case _?) {
            if (this._applyMemo(this.r52) case var _0?) {
              _l1.add(_0);
              continue;
            }
          }
          this._recover(_mark);
          break;
        }
        var _mark = this._mark();
        if (this.f23() case null) {
          this._recover(_mark);
        }
        return _l1;
      }
    }
  }

  /// `global::dart::element`
  Record? r52() {
    var _mark = this._mark();
    if (this.r53() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.r54() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.r55() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.r56() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.r57() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.r58() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.r59() case var $?) {
      return $;
    }
  }

  /// `global::dart::nullAwareExpressionElement`
  (String, Record)? r53() {
    if (this.f27() case var $0?) {
      if (this._applyMemo(this.r4n) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `global::dart::nullAwareMapElement`
  Record? r54() {
    var _mark = this._mark();
    if (this.f27() case var $0?) {
      if (this._applyMemo(this.r4n) case var $1?) {
        if (this.f24() case var $2?) {
          if (this.fay() case var $3) {
            if (this._applyMemo(this.r4n) case var $4?) {
              return ($0, $1, $2, $3, $4);
            }
          }
        }
      }
    }
    this._recover(_mark);
    if (this._applyMemo(this.r4n) case var $0?) {
      if (this.f24() case var $1?) {
        if (this.f27() case var $2?) {
          if (this._applyMemo(this.r4n) case var $3?) {
            return ($0, $1, $2, $3);
          }
        }
      }
    }
  }

  /// `global::dart::expressionElement`
  Record? r55() {
    if (this._applyMemo(this.r4n) case var $?) {
      return $;
    }
  }

  /// `global::dart::mapElement`
  (Record, String, Record)? r56() {
    if (this._applyMemo(this.r4n) case var $0?) {
      if (this.f24() case var $1?) {
        if (this._applyMemo(this.r4n) case var $2?) {
          return ($0, $1, $2);
        }
      }
    }
  }

  /// `global::dart::spreadElement`
  (String, Record)? r57() {
    if (this.faz() case var $0?) {
      if (this._applyMemo(this.r4n) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `global::dart::ifElement`
  ((String, String, Record, (String, (((Object, List<(String, Object)>), List<(String, (Object, List<(String, Object)>))>), (String, Record)?))?, String), Record, (String, Record)?)? r58() {
    if (this._applyMemo(this.r3l) case var $0?) {
      if (this._applyMemo(this.r52) case var $1?) {
        if (this.fb0() case var $2) {
          return ($0, $1, $2);
        }
      }
    }
  }

  /// `global::dart::forElement`
  (String?, String, String, Record, String, Record)? r59() {
    if (this.fb1() case var $0) {
      if (this.fs() case var $1?) {
        if (this.f1x() case var $2?) {
          if (this._applyMemo(this.r3n) case var $3?) {
            if (this.f1y() case var $4?) {
              if (this._applyMemo(this.r52) case var $5?) {
                return ($0, $1, $2, $3, $4, $5);
              }
            }
          }
        }
      }
    }
  }

  /// `global::dart::constructorTearoff`
  ((String, (String, String)?), (String, List<Object>, String)?, String, String)? r5a() {
    if (this._applyMemo(this.rb) case var $0?) {
      if (this.fb2() case var $1) {
        if (this.f26() case var $2?) {
          if (this.f15() case var $3?) {
            return ($0, $1, $2, $3);
          }
        }
      }
    }
  }

  /// `global::dart::switchExpression`
  (String, String, Record, String, String, List<((((Object, List<(String, Object)>), List<(String, (Object, List<(String, Object)>))>), (String, Record)?), String, Record)>?, String)? r5b() {
    if (this.f1j() case var $0?) {
      if (this.f1x() case var $1?) {
        if (this._applyMemo(this.r4n) case var $2?) {
          if (this.f1y() case var $3?) {
            if (this.f21() case var $4?) {
              if (this.fb3() case var $5) {
                if (this.f22() case var $6?) {
                  return ($0, $1, $2, $3, $4, $5, $6);
                }
              }
            }
          }
        }
      }
    }
  }

  /// `global::dart::switchExpressionCase`
  ((((Object, List<(String, Object)>), List<(String, (Object, List<(String, Object)>))>), (String, Record)?), String, Record)? r5c() {
    if (this._applyMemo(this.r7h) case var $0?) {
      if (this.f3c() case var $1?) {
        if (this._applyMemo(this.r4n) case var $2?) {
          return ($0, $1, $2);
        }
      }
    }
  }

  /// `global::dart::throwExpression`
  (String, Record)? r5d() {
    if (this.f1m() case var $0?) {
      if (this._applyMemo(this.r4n) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `global::dart::throwExpressionWithoutCascade`
  (String, Record)? r5e() {
    if (this.f1m() case var $0?) {
      if (this._applyMemo(this.r4o) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `global::dart::functionExpression`
  (((String, List<(List<(String, Object)>, String, (String, (Record, String?))?)>, String)?, Record), Record)? r5f() {
    if (this._applyMemo(this.r2q) case var $0?) {
      if (this.r5g() case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `global::dart::functionExpressionBody`
  Record? r5g() {
    var _mark = this._mark();
    if (this.f3c() case var $0?) {
      if (this._applyMemo(this.r4n) case var $1?) {
        return ($0, $1);
      }
    }
    this._recover(_mark);
    if (this.f3() case var $0?) {
      if (this.f3c() case var $1?) {
        if (this._applyMemo(this.r4n) case var $2?) {
          return ($0, $1, $2);
        }
      }
    }
  }

  /// `global::dart::functionExpressionWithoutCascade`
  (((String, List<(List<(String, Object)>, String, (String, (Record, String?))?)>, String)?, Record), Record)? r5h() {
    if (this._applyMemo(this.r2q) case var $0?) {
      if (this.r5i() case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `global::dart::functionExpressionWithoutCascadeBody`
  Record? r5i() {
    var _mark = this._mark();
    if (this.f3c() case var $0?) {
      if (this._applyMemo(this.r4o) case var $1?) {
        return ($0, $1);
      }
    }
    this._recover(_mark);
    if (this.f3() case var $0?) {
      if (this.f3c() case var $1?) {
        if (this._applyMemo(this.r4o) case var $2?) {
          return ($0, $1, $2);
        }
      }
    }
  }

  /// `global::dart::functionPrimary`
  (((String, List<(List<(String, Object)>, String, (String, (Record, String?))?)>, String)?, Record), Record)? r5j() {
    if (this._applyMemo(this.r2q) case var $0?) {
      if (this.r5k() case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `global::dart::functionPrimaryBody`
  Record? r5k() {
    var _mark = this._mark();
    if (this._applyMemo(this.r35) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.fb4() case var $0?) {
      if (this._applyMemo(this.r35) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `global::dart::thisExpression`
  String? r5l() {
    if (this.f1l() case var $?) {
      return $;
    }
  }

  /// `global::dart::newExpression`
  (String, Object, (String, (List<((String, String)?, Record)>, String?)?, String))? r5m() {
    if (this.f15() case var $0?) {
      if (this._applyMemo(this.ra) case var $1?) {
        if (this._applyMemo(this.r5o) case var $2?) {
          return ($0, $1, $2);
        }
      }
    }
  }

  /// `global::dart::constObjectExpression`
  (String, Object, (String, (List<((String, String)?, Record)>, String?)?, String))? r5n() {
    if (this.fb() case var $0?) {
      if (this._applyMemo(this.ra) case var $1?) {
        if (this._applyMemo(this.r5o) case var $2?) {
          return ($0, $1, $2);
        }
      }
    }
  }

  /// `global::dart::arguments`
  (String, (List<((String, String)?, Record)>, String?)?, String)? r5o() {
    if (this.f1x() case var $0?) {
      if (this.fb6() case var $1) {
        if (this.f1y() case var $2?) {
          return ($0, $1, $2);
        }
      }
    }
  }

  /// `global::dart::argumentList`
  List<((String, String)?, Record)>? r5p() {
    if (this.r5q() case var _0?) {
      if ([_0] case var _l1) {
        for (;;) {
          var _mark = this._mark();
          if (this.f23() case _?) {
            if (this.r5q() case var _0?) {
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

  /// `global::dart::argument`
  ((String, String)?, Record)? r5q() {
    if (this.fb7() case var $0) {
      if (this._applyMemo(this.r4n) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `global::dart::cascade`
  (Record, String, (Object, (Object, Record?)))? r5r() {
    var _mark = this._mark();
    if (this._applyLr(this.r5r) case var $0?) {
      if (this.f38() case var $1?) {
        if (this._applyMemo(this.r5s) case var $2?) {
          return ($0, $1, $2);
        }
      }
    }
    this._recover(_mark);
    if (this._applyMemo(this.r5y) case var $0?) {
      if (this.fb8() case var $1?) {
        if (this._applyMemo(this.r5s) case var $2?) {
          return ($0, $1, $2);
        }
      }
    }
  }

  /// `global::dart::cascadeSection`
  (Object, (Object, Record?))? r5s() {
    if (this.r5t() case var $0?) {
      if (this.r5u()! case var $1) {
        return ($0, $1);
      }
    }
  }

  /// `global::dart::cascadeSelector`
  Object? r5t() {
    var _mark = this._mark();
    if (this.f1z() case var $0?) {
      if (this._applyMemo(this.r4n) case var $1?) {
        if (this.f20() case var $2?) {
          return ($0, $1, $2);
        }
      }
    }
    this._recover(_mark);
    if (this._applyMemo(this.r7m) case var $?) {
      return $;
    }
  }

  /// `global::dart::cascadeSectionTail`
  (Object, Record?) r5u() {
    var _mark = this._mark();
    if (this._applyMemo(this.r5v) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.fb9() case var $0) {
      if (this.fba() case var $1) {
        return ($0, $1);
      }
    }
  }

  /// `global::dart::cascadeAssignment`
  (Object, Record)? r5v() {
    if (this._applyMemo(this.r5w) case var $0?) {
      if (this._applyMemo(this.r4o) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `global::dart::assignmentOperator`
  Object? r5w() {
    var _mark = this._mark();
    if (this.f28() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.r5x() case var $?) {
      return $;
    }
  }

  /// `global::dart::compoundAssignmentOperator`
  Object? r5x() {
    var _mark = this._mark();
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$105) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
    this._recover(_mark);
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$106) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
    this._recover(_mark);
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$108) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
    this._recover(_mark);
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$107) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
    this._recover(_mark);
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$103) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
    this._recover(_mark);
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$104) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
    this._recover(_mark);
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$109) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
    this._recover(_mark);
    if (this.f29() case var $0?) {
      if (this.f29() case var $1?) {
        if (this.f29() case var $2?) {
          if (this.f28() case var $3?) {
            return ($0, $1, $2, $3);
          }
        }
      }
    }
    this._recover(_mark);
    if (this.f29() case var $0?) {
      if (this.f29() case var $1?) {
        if (this.f28() case var $2?) {
          return ($0, $1, $2);
        }
      }
    }
    this._recover(_mark);
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$110) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
    this._recover(_mark);
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$111) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
    this._recover(_mark);
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$112) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
    this._recover(_mark);
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$102) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::dart::conditionalExpression`
  ((((Record, List<(String, Record)>), List<(String, (Record, List<(String, Record)>))>), List<(String, ((Record, List<(String, Record)>), List<(String, (Record, List<(String, Record)>))>))>), (String, Record, String, Record)?)? r5y() {
    if (this.r5z() case var $0?) {
      if (this.fbb() case var $1) {
        return ($0, $1);
      }
    }
  }

  /// `global::dart::ifNullExpression`
  (((Record, List<(String, Record)>), List<(String, (Record, List<(String, Record)>))>), List<(String, ((Record, List<(String, Record)>), List<(String, (Record, List<(String, Record)>))>))>)? r5z() {
    if (this._applyMemo(this.r60) case var $0?) {
      if (this.fbe() case var $1) {
        return ($0, $1);
      }
    }
  }

  /// `global::dart::logicalOrExpression`
  ((Record, List<(String, Record)>), List<(String, (Record, List<(String, Record)>))>)? r60() {
    if (this._applyMemo(this.r61) case var $0?) {
      if (this.fbg() case var $1) {
        return ($0, $1);
      }
    }
  }

  /// `global::dart::logicalAndExpression`
  (Record, List<(String, Record)>)? r61() {
    if (this._applyMemo(this.r62) case var $0?) {
      if (this.fbi() case var $1) {
        return ($0, $1);
      }
    }
  }

  /// `global::dart::equalityExpression`
  Record? r62() {
    var _mark = this._mark();
    if (this._applyMemo(this.r64) case var $0?) {
      if (this.fbj() case var $1) {
        return ($0, $1);
      }
    }
    this._recover(_mark);
    if (this.f1i() case var $0?) {
      if (this._applyMemo(this.r63) case var $1?) {
        if (this._applyMemo(this.r64) case var $2?) {
          return ($0, $1, $2);
        }
      }
    }
  }

  /// `global::dart::equalityOperator`
  String? r63() {
    var _mark = this._mark();
    if (this.f2m() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$96) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::dart::relationalExpression`
  Record? r64() {
    var _mark = this._mark();
    if (this._applyMemo(this.r66) case var $0?) {
      if (this.fbk() case var $1) {
        return ($0, $1);
      }
    }
    this._recover(_mark);
    if (this.f1i() case var $0?) {
      if (this._applyMemo(this.r65) case var $1?) {
        if (this._applyMemo(this.r66) case var $2?) {
          return ($0, $1, $2);
        }
      }
    }
  }

  /// `global::dart::relationalOperator`
  String? r65() {
    var _mark = this._mark();
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$97) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
    this._recover(_mark);
    if (this.f29() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$98) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
    this._recover(_mark);
    if (this.f2a() case var $?) {
      return $;
    }
  }

  /// `global::dart::bitwiseOrExpression`
  (Object, List<(String, (Object, List<(String, (Object, List<(String, (Object, List<(Object, (Object, List<(String, (Object, List<(String, (Object, Object))>))>))>))>))>))>)? r66() {
    var _mark = this._mark();
    if (this._applyMemo(this.r67) case var $0?) {
      if (this.fbm() case var $1) {
        return ($0, $1);
      }
    }
    this._recover(_mark);
    if (this.f1i() case var $0?) {
      if (this.fbo() case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `global::dart::bitwiseXorExpression`
  (Object, List<(String, (Object, List<(String, (Object, List<(Object, (Object, List<(String, (Object, List<(String, (Object, Object))>))>))>))>))>)? r67() {
    var _mark = this._mark();
    if (this._applyMemo(this.r68) case var $0?) {
      if (this.fbq() case var $1) {
        return ($0, $1);
      }
    }
    this._recover(_mark);
    if (this.f1i() case var $0?) {
      if (this.fbs() case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `global::dart::bitwiseAndExpression`
  (Object, List<(String, (Object, List<(Object, (Object, List<(String, (Object, List<(String, (Object, Object))>))>))>))>)? r68() {
    var _mark = this._mark();
    if (this._applyMemo(this.r6a) case var $0?) {
      if (this.fbu() case var $1) {
        return ($0, $1);
      }
    }
    this._recover(_mark);
    if (this.f1i() case var $0?) {
      if (this.fbw() case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `global::dart::bitwiseOperator`
  String? r69() {
    var _mark = this._mark();
    if (this.f2i() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.f2j() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.f2k() case var $?) {
      return $;
    }
  }

  /// `global::dart::shiftExpression`
  (Object, List<(Object, (Object, List<(String, (Object, List<(String, (Object, Object))>))>))>)? r6a() {
    var _mark = this._mark();
    if (this._applyMemo(this.r6c) case var $0?) {
      if (this.fby() case var $1) {
        return ($0, $1);
      }
    }
    this._recover(_mark);
    if (this.f1i() case var $0?) {
      if (this.fc0() case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `global::dart::shiftOperator`
  Object? r6b() {
    var _mark = this._mark();
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$115) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
    this._recover(_mark);
    if (this.f29() case var $0?) {
      if (this.f29() case var $1?) {
        if (this.f29() case var $2?) {
          return ($0, $1, $2);
        }
      }
    }
    this._recover(_mark);
    if (this.f29() case var $0?) {
      if (this.f29() case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `global::dart::additiveExpression`
  (Object, List<(String, (Object, List<(String, (Object, Object))>))>)? r6c() {
    var _mark = this._mark();
    if (this._applyMemo(this.r6e) case var $0?) {
      if (this.fc2() case var $1) {
        return ($0, $1);
      }
    }
    this._recover(_mark);
    if (this.f1i() case var $0?) {
      if (this.fc4() case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `global::dart::additiveOperator`
  String? r6d() {
    var _mark = this._mark();
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$86) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
    this._recover(_mark);
    if (this.f2e() case var $?) {
      return $;
    }
  }

  /// `global::dart::multiplicativeExpression`
  (Object, List<(String, (Object, Object))>)? r6e() {
    var _mark = this._mark();
    if (this._applyMemo(this.r6g) case var $0?) {
      if (this.fc6() case var $1) {
        return ($0, $1);
      }
    }
    this._recover(_mark);
    if (this.f1i() case var $0?) {
      if (this.fc8() case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `global::dart::multiplicativeOperator`
  String? r6f() {
    var _mark = this._mark();
    if (this.f2f() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$89) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
    this._recover(_mark);
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$90) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
    this._recover(_mark);
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$116) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::dart::unaryExpression`
  (Object, Object)? r6g() {
    var _mark = this._mark();
    if (this.r6h() case var $0?) {
      if (this._applyMemo(this.r6g) case var $1?) {
        return ($0, $1);
      }
    }
    this._recover(_mark);
    if (this.r6i() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.r6j() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.fc9() case var $0?) {
      if (this.f1i() case var $1?) {
        return ($0, $1);
      }
    }
    this._recover(_mark);
    if (this._applyMemo(this.r6n) case var $0?) {
      if (this._applyMemo(this.r6o) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `global::dart::prefixOperator`
  String? r6h() {
    var _mark = this._mark();
    if (this.f2e() case var $?) {
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

  /// `global::dart::awaitExpression`
  (String, (Object, Object))? r6i() {
    if (this.f5() case var $0?) {
      if (this._applyMemo(this.r6g) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `global::dart::postfixExpression`
  (Object, Object)? r6j() {
    var _mark = this._mark();
    if (this._applyMemo(this.r6o) case var $0?) {
      if (this.r6k() case var $1?) {
        return ($0, $1);
      }
    }
    this._recover(_mark);
    if (this._applyMemo(this.r4q) case var $0?) {
      if (this.fca() case var $1) {
        return ($0, $1);
      }
    }
    this._recover(_mark);
    if (this._applyMemo(this.r6s) case var $?) {
      return $;
    }
  }

  /// `global::dart::postfixOperator`
  String? r6k() {
    if (this._applyMemo(this.r6n) case var $?) {
      return $;
    }
  }

  /// `global::dart::selector`
  Object? r6l() {
    var _mark = this._mark();
    if (this.f2b() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this._applyMemo(this.r6r) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this._applyMemo(this.r6m) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this._applyMemo(this.rj) case var $?) {
      return $;
    }
  }

  /// `global::dart::argumentPart`
  ((String, List<Object>, String)?, (String, (List<((String, String)?, Record)>, String?)?, String))? r6m() {
    if (this.fcb() case var $0) {
      if (this._applyMemo(this.r5o) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `global::dart::incrementOperator`
  String? r6n() {
    var _mark = this._mark();
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$113) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
    this._recover(_mark);
    if (this.f3m() case _) {
      if (this.matchPattern(_string.$114) case var $1?) {
        if (this.f3m() case _) {
          return $1;
        }
      }
    }
  }

  /// `global::dart::assignableExpression`
  Object? r6o() {
    var _mark = this._mark();
    if (this.f1i() case var $0?) {
      if (this._applyMemo(this.r6q) case var $1?) {
        return ($0, $1);
      }
    }
    this._recover(_mark);
    if (this._applyMemo(this.r4q) case var $0?) {
      if (this.r6p() case var $1?) {
        return ($0, $1);
      }
    }
    this._recover(_mark);
    if (this._applyMemo(this.r7m) case var $?) {
      return $;
    }
  }

  /// `global::dart::assignableSelectorPart`
  (List<Object>, Record)? r6p() {
    if (this.fcc() case var $0) {
      if (this._applyMemo(this.r6r) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `global::dart::unconditionalAssignableSelector`
  Record? r6q() {
    var _mark = this._mark();
    if (this.f1z() case var $0?) {
      if (this._applyMemo(this.r4n) case var $1?) {
        if (this.f20() case var $2?) {
          return ($0, $1, $2);
        }
      }
    }
    this._recover(_mark);
    if (this.f26() case var $0?) {
      if (this._applyMemo(this.r7m) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `global::dart::assignableSelector`
  Record? r6r() {
    var _mark = this._mark();
    if (this._applyMemo(this.r6q) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.fcd() case var $0?) {
      if (this._applyMemo(this.r7m) case var $1?) {
        return ($0, $1);
      }
    }
    this._recover(_mark);
    if (this.f27() case var $0?) {
      if (this.f1z() case var $1?) {
        if (this._applyMemo(this.r4n) case var $2?) {
          if (this.f20() case var $3?) {
            return ($0, $1, $2, $3);
          }
        }
      }
    }
  }

  /// `global::dart::staticMemberShorthand`
  (Record, List<Object>)? r6s() {
    if (this.r6t() case var $0?) {
      if (this.fce() case var $1) {
        return ($0, $1);
      }
    }
  }

  /// `global::dart::staticMemberShorthandHead`
  Record? r6t() {
    var _mark = this._mark();
    if (this.f26() case var $0?) {
      if (this._applyMemo(this.r9) case var $1?) {
        return ($0, $1);
      }
    }
    this._recover(_mark);
    if (this.fb() case var $0?) {
      if (this.f26() case var $1?) {
        if (this._applyMemo(this.r9) case var $2?) {
          if (this._applyMemo(this.r5o) case var $3?) {
            return ($0, $1, $2, $3);
          }
        }
      }
    }
  }

  /// `global::dart::pattern`
  ((Object, List<(String, Object)>), List<(String, (Object, List<(String, Object)>))>)? r6u() {
    if (this.r6v() case var $?) {
      return $;
    }
  }

  /// `global::dart::logicalOrPattern`
  ((Object, List<(String, Object)>), List<(String, (Object, List<(String, Object)>))>)? r6v() {
    if (this._applyMemo(this.r6w) case var $0?) {
      if (this.fcg() case var $1) {
        return ($0, $1);
      }
    }
  }

  /// `global::dart::logicalAndPattern`
  (Object, List<(String, Object)>)? r6w() {
    if (this._applyMemo(this.r6x) case var $0?) {
      if (this.fci() case var $1) {
        return ($0, $1);
      }
    }
  }

  /// `global::dart::relationalPattern`
  Object? r6x() {
    var _mark = this._mark();
    if (this.fcj() case var $0?) {
      if (this._applyMemo(this.r66) case var $1?) {
        return ($0, $1);
      }
    }
    this._recover(_mark);
    if (this.r6y() case var $?) {
      return $;
    }
  }

  /// `global::dart::unaryPattern`
  Object? r6y() {
    var _mark = this._mark();
    if (this.r70() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.r71() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.r72() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this._applyMemo(this.r6z) case var $?) {
      return $;
    }
  }

  /// `global::dart::primaryPattern`
  Object? r6z() {
    var _mark = this._mark();
    if (this.r73() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.r74() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this._applyMemo(this.r75) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this._applyMemo(this.r76) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this._applyMemo(this.r7a) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this._applyMemo(this.r7d) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this._applyMemo(this.r7g) case var $?) {
      return $;
    }
  }

  /// `global::dart::castPattern`
  (Object, String, Object)? r70() {
    if (this._applyMemo(this.r6z) case var $0?) {
      if (this.f1() case var $1?) {
        if (this._applyMemo(this.re) case var $2?) {
          return ($0, $1, $2);
        }
      }
    }
  }

  /// `global::dart::nullCheckPattern`
  (Object, String)? r71() {
    if (this._applyMemo(this.r6z) case var $0?) {
      if (this.f27() case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `global::dart::nullAssertPattern`
  (Object, String)? r72() {
    if (this._applyMemo(this.r6z) case var $0?) {
      if (this.f2b() case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `global::dart::constantPattern`
  Object? r73() {
    var _mark = this._mark();
    if (this._applyMemo(this.r4v) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this._applyMemo(this.r4t) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.fck() case var $0) {
      if (this._applyMemo(this.r4u) case var $1?) {
        return ($0, $1);
      }
    }
    this._recover(_mark);
    if (this.f3j() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this._applyMemo(this.r7p) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this._applyMemo(this.r7m) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this._applyMemo(this.r8) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this._applyMemo(this.r5n) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.fb() case var $0?) {
      if (this.fcl() case var $1) {
        if (this.f1z() case var $2?) {
          if (this.fcm() case var $3) {
            if (this.f20() case var $4?) {
              return ($0, $1, $2, $3, $4);
            }
          }
        }
      }
    }
    this._recover(_mark);
    if (this.fb() case var $0?) {
      if (this.fcn() case var $1) {
        if (this.f21() case var $2?) {
          if (this.fco() case var $3) {
            if (this.f22() case var $4?) {
              return ($0, $1, $2, $3, $4);
            }
          }
        }
      }
    }
    this._recover(_mark);
    if (this.fb() case var $0?) {
      if (this.f1x() case var $1?) {
        if (this._applyMemo(this.r4n) case var $2?) {
          if (this.f1y() case var $3?) {
            return ($0, $1, $2, $3);
          }
        }
      }
    }
    this._recover(_mark);
    if (this._applyMemo(this.r6s) case var $?) {
      return $;
    }
  }

  /// `global::dart::variablePattern`
  (Object?, String)? r74() {
    if (this.fcq() case var $0) {
      if (this._applyMemo(this.r7m) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `global::dart::parenthesizedPattern`
  (String, ((Object, List<(String, Object)>), List<(String, (Object, List<(String, Object)>))>), String)? r75() {
    if (this.f1x() case var $0?) {
      if (this._applyMemo(this.r6u) case var $1?) {
        if (this.f1y() case var $2?) {
          return ($0, $1, $2);
        }
      }
    }
  }

  /// `global::dart::listPattern`
  ((String, List<Object>, String)?, String, (List<(Object, Object?)>, String?)?, String)? r76() {
    if (this.fcr() case var $0) {
      if (this.f1z() case var $1?) {
        if (this.fcs() case var $2) {
          if (this.f20() case var $3?) {
            return ($0, $1, $2, $3);
          }
        }
      }
    }
  }

  /// `global::dart::listPatternElements`
  (List<(Object, Object?)>, String?)? r77() {
    if (this.fct() case var $0?) {
      if (this.fcu() case var $1) {
        return ($0, $1);
      }
    }
  }

  /// `global::dart::listPatternElement`
  (Object, Object?)? r78() {
    var _mark = this._mark();
    if (this._applyMemo(this.r6u) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.r79() case var $?) {
      return $;
    }
  }

  /// `global::dart::restPattern`
  (String, ((Object, List<(String, Object)>), List<(String, (Object, List<(String, Object)>))>)?)? r79() {
    if (this.f39() case var $0?) {
      if (this.fcv() case var $1) {
        return ($0, $1);
      }
    }
  }

  /// `global::dart::mapPattern`
  ((String, List<Object>, String)?, String, (List<Object>, String?)?, String)? r7a() {
    if (this.fcw() case var $0) {
      if (this.f21() case var $1?) {
        if (this.fcx() case var $2) {
          if (this.f22() case var $3?) {
            return ($0, $1, $2, $3);
          }
        }
      }
    }
  }

  /// `global::dart::mapPatternEntries`
  (List<Object>, String?)? r7b() {
    if (this.fcy() case var $0?) {
      if (this.fcz() case var $1) {
        return ($0, $1);
      }
    }
  }

  /// `global::dart::mapPatternEntry`
  Object? r7c() {
    var _mark = this._mark();
    if (this._applyMemo(this.r4n) case var $0?) {
      if (this.f24() case var $1?) {
        if (this._applyMemo(this.r6u) case var $2?) {
          return ($0, $1, $2);
        }
      }
    }
    this._recover(_mark);
    if (this.f39() case var $?) {
      return $;
    }
  }

  /// `global::dart::recordPattern`
  (String, (List<((String?, String)?, ((Object, List<(String, Object)>), List<(String, (Object, List<(String, Object)>))>))>, String?)?, String)? r7d() {
    if (this.f1x() case var $0?) {
      if (this.fd0() case var $1) {
        if (this.f1y() case var $2?) {
          return ($0, $1, $2);
        }
      }
    }
  }

  /// `global::dart::patternFields`
  (List<((String?, String)?, ((Object, List<(String, Object)>), List<(String, (Object, List<(String, Object)>))>))>, String?)? r7e() {
    if (this.fd1() case var $0?) {
      if (this.fd2() case var $1) {
        return ($0, $1);
      }
    }
  }

  /// `global::dart::patternField`
  ((String?, String)?, ((Object, List<(String, Object)>), List<(String, (Object, List<(String, Object)>))>))? r7f() {
    if (this.fd4() case var $0) {
      if (this._applyMemo(this.r6u) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `global::dart::objectPattern`
  (((String, Object?)?, Object?), String, (List<((String?, String)?, ((Object, List<(String, Object)>), List<(String, (Object, List<(String, Object)>))>))>, String?)?, String)? r7g() {
    if (this.fd6() case var $0?) {
      if (this.f1x() case var $1?) {
        if (this.fd7() case var $2) {
          if (this.f1y() case var $3?) {
            return ($0, $1, $2, $3);
          }
        }
      }
    }
  }

  /// `global::dart::guardedPattern`
  (((Object, List<(String, Object)>), List<(String, (Object, List<(String, Object)>))>), (String, Record)?)? r7h() {
    if (this._applyMemo(this.r6u) case var $0?) {
      if (this.fd8() case var $1) {
        return ($0, $1);
      }
    }
  }

  /// `global::dart::patternAssignment`
  (Record, String, Record)? r7i() {
    if (this._applyMemo(this.r7j) case var $0?) {
      if (this.f28() case var $1?) {
        if (this._applyMemo(this.r4n) case var $2?) {
          return ($0, $1, $2);
        }
      }
    }
  }

  /// `global::dart::outerPattern`
  Record? r7j() {
    var _mark = this._mark();
    if (this._applyMemo(this.r75) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this._applyMemo(this.r76) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this._applyMemo(this.r7a) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this._applyMemo(this.r7d) case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this._applyMemo(this.r7g) case var $?) {
      return $;
    }
  }

  /// `global::dart::typeTest`
  (String, String?, (Record, String?))? r7k() {
    if (this.fd9() case var $0?) {
      if (this.fda() case var $1) {
        if (this._applyMemo(this.rg) case var $2?) {
          return ($0, $1, $2);
        }
      }
    }
  }

  /// `global::dart::typeCast`
  (String, (Record, String?))? r7l() {
    if (this.f1() case var $0?) {
      if (this._applyMemo(this.rg) case var $1?) {
        return ($0, $1);
      }
    }
  }

  /// `global::dart::identifier`
  String? r7m() {
    var _mark = this._mark();
    if (this.f3g() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.r7n() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.r7o() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.f5() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.f1v() case var $?) {
      return $;
    }
  }

  /// `global::dart::builtInIdentifier`
  String? r7n() {
    var _mark = this._mark();
    if (this.f0() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.f1() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.f4() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.fd() case var $?) {
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
    if (this.fk() case var $?) {
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
    if (this.ft() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.fu() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.fx() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.fy() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.f10() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.f12() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.f13() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.f19() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.f14() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.f1a() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.f1b() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.f1f() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.f1h() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.f1q() case var $?) {
      return $;
    }
  }

  /// `global::dart::otherIdentifier`
  String? r7o() {
    var _mark = this._mark();
    if (this.f3() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.f6() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.fv() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.f17() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.f18() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.f1e() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.f1g() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.f1k() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.f1p() case var $?) {
      return $;
    }
    this._recover(_mark);
    if (this.f1w() case var $?) {
      return $;
    }
  }

  /// `global::dart::symbolLiteral`
  (String, Object)? r7p() {
    if (this.fdb() case var $0?) {
      if (this.fdc() case var $1?) {
        return ($0, $1);
      }
    }
  }

}
class _regexp {
  /// `/\s/`
  static final $1 = RegExp("\\s");
}
class _string {
  /// `"abstract"`
  static const $1 = "abstract";
  /// `"as"`
  static const $2 = "as";
  /// `"assert"`
  static const $3 = "assert";
  /// `"async"`
  static const $4 = "async";
  /// `"augment"`
  static const $5 = "augment";
  /// `"await"`
  static const $6 = "await";
  /// `"base"`
  static const $7 = "base";
  /// `"break"`
  static const $8 = "break";
  /// `"case"`
  static const $9 = "case";
  /// `"catch"`
  static const $10 = "catch";
  /// `"class"`
  static const $11 = "class";
  /// `"const"`
  static const $12 = "const";
  /// `"continue"`
  static const $13 = "continue";
  /// `"covariant"`
  static const $14 = "covariant";
  /// `"default"`
  static const $15 = "default";
  /// `"deferred"`
  static const $16 = "deferred";
  /// `"do"`
  static const $17 = "do";
  /// `"dynamic"`
  static const $18 = "dynamic";
  /// `"else"`
  static const $19 = "else";
  /// `"enum"`
  static const $20 = "enum";
  /// `"export"`
  static const $21 = "export";
  /// `"extends"`
  static const $22 = "extends";
  /// `"extension"`
  static const $23 = "extension";
  /// `"external"`
  static const $24 = "external";
  /// `"factory"`
  static const $25 = "factory";
  /// `"false"`
  static const $26 = "false";
  /// `"final"`
  static const $27 = "final";
  /// `"finally"`
  static const $28 = "finally";
  /// `"for"`
  static const $29 = "for";
  /// `"Function"`
  static const $30 = "Function";
  /// `"get"`
  static const $31 = "get";
  /// `"hide"`
  static const $32 = "hide";
  /// `"if"`
  static const $33 = "if";
  /// `"implements"`
  static const $34 = "implements";
  /// `"import"`
  static const $35 = "import";
  /// `"in"`
  static const $36 = "in";
  /// `"interface"`
  static const $37 = "interface";
  /// `"is"`
  static const $38 = "is";
  /// `"late"`
  static const $39 = "late";
  /// `"library"`
  static const $40 = "library";
  /// `"mixin"`
  static const $41 = "mixin";
  /// `"new"`
  static const $42 = "new";
  /// `"null"`
  static const $43 = "null";
  /// `"of"`
  static const $44 = "of";
  /// `"on"`
  static const $45 = "on";
  /// `"operator"`
  static const $46 = "operator";
  /// `"part"`
  static const $47 = "part";
  /// `"required"`
  static const $48 = "required";
  /// `"rethrow"`
  static const $49 = "rethrow";
  /// `"return"`
  static const $50 = "return";
  /// `"sealed"`
  static const $51 = "sealed";
  /// `"set"`
  static const $52 = "set";
  /// `"show"`
  static const $53 = "show";
  /// `"static"`
  static const $54 = "static";
  /// `"super"`
  static const $55 = "super";
  /// `"switch"`
  static const $56 = "switch";
  /// `"sync"`
  static const $57 = "sync";
  /// `"this"`
  static const $58 = "this";
  /// `"throw"`
  static const $59 = "throw";
  /// `"true"`
  static const $60 = "true";
  /// `"try"`
  static const $61 = "try";
  /// `"type"`
  static const $62 = "type";
  /// `"typedef"`
  static const $63 = "typedef";
  /// `"var"`
  static const $64 = "var";
  /// `"void"`
  static const $65 = "void";
  /// `"while"`
  static const $66 = "while";
  /// `"with"`
  static const $67 = "with";
  /// `"yield"`
  static const $68 = "yield";
  /// `"when"`
  static const $69 = "when";
  /// `"("`
  static const $70 = "(";
  /// `")"`
  static const $71 = ")";
  /// `"["`
  static const $72 = "[";
  /// `"]"`
  static const $73 = "]";
  /// `"{"`
  static const $74 = "{";
  /// `"}"`
  static const $75 = "}";
  /// `","`
  static const $76 = ",";
  /// `":"`
  static const $77 = ":";
  /// `";"`
  static const $78 = ";";
  /// `"."`
  static const $79 = ".";
  /// `"?"`
  static const $80 = "?";
  /// `"="`
  static const $81 = "=";
  /// `">"`
  static const $82 = ">";
  /// `"<"`
  static const $83 = "<";
  /// `"!"`
  static const $84 = "!";
  /// `"~"`
  static const $85 = "~";
  /// `"+"`
  static const $86 = "+";
  /// `"-"`
  static const $87 = "-";
  /// `"*"`
  static const $88 = "*";
  /// `"/"`
  static const $89 = "/";
  /// `"%"`
  static const $90 = "%";
  /// `"&"`
  static const $91 = "&";
  /// `"^"`
  static const $92 = "^";
  /// `"|"`
  static const $93 = "|";
  /// `"#"`
  static const $94 = "#";
  /// `"=="`
  static const $95 = "==";
  /// `"!="`
  static const $96 = "!=";
  /// `">="`
  static const $97 = ">=";
  /// `"<="`
  static const $98 = "<=";
  /// `"&&"`
  static const $99 = "&&";
  /// `"||"`
  static const $100 = "||";
  /// `"??"`
  static const $101 = "??";
  /// `"??="`
  static const $102 = "??=";
  /// `"+="`
  static const $103 = "+=";
  /// `"-="`
  static const $104 = "-=";
  /// `"*="`
  static const $105 = "*=";
  /// `"/="`
  static const $106 = "/=";
  /// `"%="`
  static const $107 = "%=";
  /// `"~/="`
  static const $108 = "~/=";
  /// `"<<="`
  static const $109 = "<<=";
  /// `"&="`
  static const $110 = "&=";
  /// `"^="`
  static const $111 = "^=";
  /// `"|="`
  static const $112 = "|=";
  /// `"++"`
  static const $113 = "++";
  /// `"--"`
  static const $114 = "--";
  /// `"<<"`
  static const $115 = "<<";
  /// `"~/"`
  static const $116 = "~/";
  /// `".."`
  static const $117 = "..";
  /// `"..."`
  static const $118 = "...";
  /// `"?.."`
  static const $119 = "?..";
  /// `"...?"`
  static const $120 = "...?";
  /// `"=>"`
  static const $121 = "=>";
  /// `"?."`
  static const $122 = "?.";
  /// `"uFEFF"`
  static const $123 = "uFEFF";
  /// `"#!"`
  static const $124 = "#!";
  /// `"'"`
  static const $125 = "'";
  /// `"r'"`
  static const $126 = "r'";
  /// `"\""`
  static const $127 = "\"";
  /// `"r\""`
  static const $128 = "r\"";
  /// `"'''"`
  static const $129 = "'''";
  /// `"r'''"`
  static const $130 = "r'''";
  /// `"\"\"\""`
  static const $131 = "\"\"\"";
  /// `"r\"\"\""`
  static const $132 = "r\"\"\"";
  /// `"//"`
  static const $133 = "//";
  /// `"*/"`
  static const $134 = "*/";
  /// `"/*"`
  static const $135 = "/*";
  /// `"@"`
  static const $136 = "@";
  /// `"_"`
  static const $137 = "_";
  /// `"0x"`
  static const $138 = "0x";
  /// `"0X"`
  static const $139 = "0X";
  /// `"\\"`
  static const $140 = "\\";
}
class _range {
  /// `[]`
  static const $1 = { (13, 13), (10, 10) };
  /// `[0-9]`
  static const $2 = { (48, 57) };
  /// `[+-]`
  static const $3 = { (43, 43), (45, 45) };
  /// `[eE]`
  static const $4 = { (101, 101), (69, 69) };
  /// `[a-fA-F0-9]`
  static const $5 = { (97, 102), (65, 70), (48, 57) };
  /// `[a-zA-Z0-9_$]`
  static const $6 = { (97, 122), (65, 90), (48, 57), (95, 95), (36, 36) };
  /// `[a-zA-Z_$]`
  static const $7 = { (97, 122), (65, 90), (95, 95), (36, 36) };
  /// `[']`
  static const $8 = { (39, 39), (13, 13), (10, 10) };
  /// `['\$]`
  static const $9 = { (39, 39), (92, 92), (13, 13), (10, 10), (36, 36) };
  /// `['\"$]`
  static const $10 = { (39, 39), (92, 92), (34, 34), (13, 13), (10, 10), (36, 36) };
}
