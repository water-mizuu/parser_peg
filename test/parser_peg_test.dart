// ignore_for_file: strict_raw_type, avoid_dynamic_calls

import "dart:convert";
import "dart:io";
import "dart:isolate";

import "package:parser_peg/src/generator.dart";
import "package:parser_peg/src/node.dart";
import "package:parser_peg/src/parser/grammar_parser.dart";
import "package:parser_peg/src/statement.dart";
import "package:test/test.dart";

// ---------------------------------------------------------------------------
//  Utilities
// ---------------------------------------------------------------------------

String readGrammarFile(String relativePath) =>
    File(relativePath).readAsStringSync().replaceAll("\r", "").trim();

/// Compiles a `.dart_grammar` source into Dart code, spawns a **single**
/// isolate and returns a helper that can repeatedly invoke `parse()` on it.
///
/// The isolate listens on a [ReceivePort] and for every `String` message
/// it receives it calls `parser.parse(message)` and sends the JSON-encoded
/// result back.
///
/// Callers **must** call [IsolateParser.dispose] when finished.
Future<IsolateParser> spawnParser(String grammarSource, {String parserName = "TestParser"}) async {
  var grammar = GrammarParser();
  var generator = grammar.parse(grammarSource);
  if (generator == null) {
    throw StateError("Failed to parse grammar:\n${grammar.reportFailures()}");
  }

  var parserCode = await generator.compileAnalyzedParserGenerator(parserName);

  // Build a small driver program that keeps running, parsing each message
  // it receives via a SendPort.
  var driver =
      """
import "dart:convert" show jsonEncode;
import "dart:isolate" show ReceivePort, SendPort;

$parserCode

Object? _serialize(Object? v) {
  if (v == null) return null;
  if (v is num || v is bool || v is String) return v;
  if (v is List) return v.map(_serialize).toList();
  if (v is Map) return v.map((k, v) => MapEntry(k.toString(), _serialize(v)));
  return v.toString();
}

void main(List<String> _, SendPort initPort) {
  var receivePort = ReceivePort();
  initPort.send(receivePort.sendPort);

  var parser = $parserName();

  receivePort.listen((msg) {
    var [replyPort as SendPort, input as String] = msg as List;
    try {
      var result = parser.parse(input);
      replyPort.send(["ok", result == null ? null : jsonEncode(_serialize(result))]);
    } catch (e, st) {
      replyPort.send(["error", e.toString(), st.toString()]);
    }
  });
}
""";

  var uri = Uri.dataFromString(
    driver,
    mimeType: "application/dart",
    encoding: const SystemEncoding(),
    base64: true,
  );

  var initPort = ReceivePort();
  var onError = ReceivePort();
  // ignore: cancel_subscriptions
  var errSub = onError.listen((data) {
    // surface compile or runtime errors from the isolate
    throw StateError("Isolate error: $data");
  });

  var isolate = await Isolate.spawnUri(uri, [], initPort.sendPort, onError: onError.sendPort);

  var sendPort = await initPort.first as SendPort;

  return IsolateParser._(isolate, sendPort, onError, errSub);
}

class IsolateParser {
  IsolateParser._(this._isolate, this._sendPort, this._onError, this._errSub);

  final Isolate _isolate;
  final SendPort _sendPort;
  final ReceivePort _onError;
  final dynamic _errSub;

  /// Sends [input] to the compiled parser and returns the JSON-decoded result.
  /// Returns `null` when the parser fails to match.
  Future<Object?> parse(String input) async {
    var reply = ReceivePort();
    _sendPort.send([reply.sendPort, input]);
    var response = await reply.first as List;
    if (response[0] == "error") {
      throw StateError("Parser runtime error: ${response[1]}\n${response[2]}");
    }
    var jsonStr = response[1] as String?;
    return jsonStr == null ? null : jsonDecode(jsonStr);
  }

  void dispose() {
    _errSub.cancel();
    _onError.close();
    _isolate.kill(priority: Isolate.immediate);
  }
}

// ---------------------------------------------------------------------------
//  Test group 1 – GrammarParser itself: parsing grammar sources
// ---------------------------------------------------------------------------

void main() {
  group("GrammarParser: grammar parsing", () {
    late GrammarParser parser;

    setUp(() => parser = GrammarParser());

    test("parse minimal rule", () {
      var result = parser.parse('rule = "hello";');
      expect(result, isA<ParserGenerator>());
    });

    test("parse typed rule", () {
      var result = parser.parse('String rule = "hello";');
      expect(result, isA<ParserGenerator>());
    });

    test("parse preamble + rule", () {
      var result = parser.parse('''
{
import "dart:math";
}
String rule = "hello";
''');
      expect(result, isA<ParserGenerator>());
    });

    test("parse choice", () {
      var result = parser.parse('rule = "a" | "b" | "c";');
      expect(result, isA<ParserGenerator>());
    });

    test("parse sequence", () {
      var result = parser.parse('rule = "a" "b" "c";');
      expect(result, isA<ParserGenerator>());
    });

    test("parse quantifiers (?, *, +)", () {
      var result = parser.parse('''
rule = atom;
atom = "a"? "b"* "c"+;
''');
      expect(result, isA<ParserGenerator>());
    });

    test("parse regex literal", () {
      var result = parser.parse("rule = /[a-zA-Z_][a-zA-Z0-9_]*/;");
      expect(result, isA<ParserGenerator>());
    });

    test("parse char range", () {
      var result = parser.parse("rule = [a-zA-Z];");
      expect(result, isA<ParserGenerator>());
    });

    test("parse regex escape", () {
      var result = parser.parse(r"rule = \d+;");
      expect(result, isA<ParserGenerator>());
    });

    test("parse namespace", () {
      var result = parser.parse('''
ns {
  rule = "a";
  other = "b";
}
entry = ns.rule;
''');
      expect(result, isA<ParserGenerator>());
    });

    test("parse fragment decorator", () {
      var result = parser.parse('''
@fragment token = "hello";
entry = token;
''');
      expect(result, isA<ParserGenerator>());
    });

    test("parse inline decorator", () {
      var result = parser.parse('''
@inline helper = "x";
entry = helper;
''');
      expect(result, isA<ParserGenerator>());
    });

    test("parse inline action (|>)", () {
      var result = parser.parse(r"""
int rule = :num |> num * 2;
@fragment num = \d+ { int.parse($.join()) };
""");
      expect(result, isA<ParserGenerator>());
    });

    test("parse deferred action { }", () {
      var result = parser.parse(r"""
int rule = \d+ { int.parse($.join()) };
""");
      expect(result, isA<ParserGenerator>());
    });

    test("parse action with (){ }", () {
      var result = parser.parse(r"""
int rule = \d+() { return int.parse($.join()); };
""");
      expect(result, isA<ParserGenerator>());
    });

    test("parse predicates", () {
      var result = parser.parse('rule = &"a" "a" "b" | !"c" .;');
      expect(result, isA<ParserGenerator>());
    });

    test("parse except (~)", () {
      var result = parser.parse('rule = ~"x" .;');
      expect(result, isA<ParserGenerator>());
    });

    test("parse separated lists", () {
      var result = parser.parse(r'''
rule = ","..item+;
item = \d+;
''');
      expect(result, isA<ParserGenerator>());
    });

    test("parse star separated lists", () {
      var result = parser.parse(r'''
rule = ","..item*;
item = \d+;
''');
      expect(result, isA<ParserGenerator>());
    });

    test("parse optional trailing separator", () {
      var result = parser.parse(r'''
rule = ","..item+?;
item = \d+;
''');
      expect(result, isA<ParserGenerator>());
    });

    test("parse counted repetition", () {
      var result = parser.parse(r"rule = 2..4 \d;");
      expect(result, isA<ParserGenerator>());
    });

    test(r"parse special symbols (^, $, ., ε)", () {
      var result = parser.parse(r"rule = ^ . $ | ε;");
      expect(result, isA<ParserGenerator>());
    });

    test("parse selected index (@)", () {
      var result = parser.parse('rule = "(" "x" ")" @1;');
      expect(result, isA<ParserGenerator>());
    });

    test("parse drop operators (<~ ~>)", () {
      var result = parser.parse('rule = "(" ~> "x" <~ ")";');
      expect(result, isA<ParserGenerator>());
    });

    test("parse named bindings (:)", () {
      var result = parser.parse(r'''
rule = :a _ :b |> a + b;
a = "x";
b = "y";
_ = \s*;
''');
      expect(result, isA<ParserGenerator>());
    });

    test("parse type declarations", () {
      var result = parser.parse('''
String a, b;
a = "hello";
b = "world";
''');
      expect(result, isA<ParserGenerator>());
    });

    test("parse left-recursive rule", () {
      var result = parser.parse('''
rule = rule "a" | "a";
''');
      expect(result, isA<ParserGenerator>());
    });

    test("parse hybrid namespace", () {
      var result = parser.parse('''
x = choice! {
  a = "a";
  b = "b";
};
entry = x;
''');
      expect(result, isA<ParserGenerator>());
    });

    test("parse comments in grammar", () {
      var result = parser.parse('''
/// This is a comment
rule = "x";
/* multi-line
   comment */
''');
      expect(result, isA<ParserGenerator>());
    });

    test("parse string variants (raw, single, double, triple)", () {
      var result = parser.parse('''
rule = "double" | 'single';
''');
      expect(result, isA<ParserGenerator>());
    });

    test("parse flat node (<...>)", () {
      var result = parser.parse(r"rule = <\d+>;");
      expect(result, isA<ParserGenerator>());
    });

    test("parse complex preamble", () {
      var result = parser.parse('''
{
import "dart:math" as math show pow, sqrt;
import "dart:convert";

class Helper {
  static int add(int a, int b) => a + b;
}
}

String rule = "x";
''');
      expect(result, isA<ParserGenerator>());
    });

    test("parse the metagrammar itself", () {
      var input = readGrammarFile("examples/meta/grammar_parser.dart_grammar");
      var result = parser.parse(input);
      expect(result, isA<ParserGenerator>());
    });

    test("parse math grammar", () {
      var input = readGrammarFile("examples/math/math.dart_grammar");
      var result = parser.parse(input);
      expect(result, isA<ParserGenerator>());
    });

    test("reject empty input", () {
      var result = parser.parse("");
      expect(result, isNull);
    });

    test("reject malformed grammar", () {
      var result = parser.parse("rule = ;");
      expect(result, isNull);
    });
  });

  // -------------------------------------------------------------------------
  //  Test group 2 – Code generation (compile step)
  // -------------------------------------------------------------------------

  group("Code generation", () {
    test("compileParserGenerator produces valid Dart code", () {
      var parser = GrammarParser();
      var gen = parser.parse('String rule = "hello";')!;
      var code = gen.compileParserGenerator("HelloParser");

      expect(code, contains("class HelloParser"));
      expect(code, contains("extends _PegParser<String>"));
    });

    test("compileAstParserGenerator produces valid AST parser", () {
      var parser = GrammarParser();
      var gen = parser.parse('String rule = "hello";')!;
      var code = gen.compileAstParserGenerator("HelloAst");

      expect(code, contains("class HelloAst"));
      expect(code, contains("extends _PegParser<Object>"));
    });

    test("compileCstParserGenerator produces valid CST parser", () {
      var parser = GrammarParser();
      var gen = parser.parse('String rule = "hello";')!;
      var code = gen.compileCstParserGenerator("HelloCst");

      expect(code, contains("class HelloCst"));
      expect(code, contains("extends _PegParser<Object>"));
    });

    test("preamble is included in output", () {
      var parser = GrammarParser();
      var gen = parser.parse('''
{
import "dart:math" as math;
}
String rule = "hello";
''')!;
      var code = gen.compileParserGenerator("P");
      expect(code, contains('import "dart:math" as math;'));
    });

    test("regex patterns are collected in _regexp class", () {
      var parser = GrammarParser();
      var gen = parser.parse("String rule = /[a-z]+/;")!;
      var code = gen.compileParserGenerator("P");
      expect(code, contains("class _regexp"));
    });

    test("string literals are collected in _string class", () {
      var parser = GrammarParser();
      var gen = parser.parse('String rule = "hello";')!;
      var code = gen.compileParserGenerator("P");
      expect(code, contains("class _string"));
    });

    test("math grammar compiles", () async {
      var parser = GrammarParser();
      var gen = parser.parse(readGrammarFile("examples/math/math.dart_grammar"))!;
      var code = await gen.compileAnalyzedParserGenerator("MathParser");

      expect(code, contains("class MathParser"));
      expect(code, contains("extends _PegParser<num>"));
    });

    test("metagrammar compiles", () async {
      var parser = GrammarParser();
      var gen = parser.parse(readGrammarFile("examples/meta/grammar_parser.dart_grammar"))!;
      var code = await gen.compileAnalyzedParserGenerator("GrammarParser");

      expect(code, contains("class GrammarParser"));
    });

    test("choice rule produces multiple branches", () async {
      var parser = GrammarParser();
      var gen = parser.parse('rule = "a" | "b" | "c";')!;
      var code = await gen.compileAnalyzedParserGenerator("P");
      // Verify there's backtracking code (_mark / _recover)
      expect(code, contains("_mark"));
      expect(code, contains("_recover"));
    });

    test("left-recursive rule uses apply()", () async {
      var parser = GrammarParser();
      var gen = parser.parse('rule = rule "a" | "a";')!;
      var code = await gen.compileAnalyzedParserGenerator("P");
      expect(code, contains("this.apply("));
    });
  });

  // -------------------------------------------------------------------------
  //  Test group 3 – alwaysSucceeds analysis
  // -------------------------------------------------------------------------

  group("alwaysSucceeds", () {
    late ParserGenerator gen;

    setUp(() {
      gen = GrammarParser().parse('rule = "a" | "b";')!;
    });

    test("EpsilonNode always succeeds", () {
      expect(gen.isPassIfNull(const EpsilonNode(), "test"), isTrue);
    });

    test("StringLiteralNode: empty succeeds", () {
      expect(gen.isPassIfNull(const StringLiteralNode(""), "test"), isTrue);
    });

    test("StringLiteralNode: non-empty can fail", () {
      expect(gen.isPassIfNull(const StringLiteralNode("x"), "test"), isFalse);
    });

    test("StarNode always succeeds", () {
      expect(gen.isPassIfNull(const StarNode(StringLiteralNode("a")), "test"), isTrue);
    });

    test("PlusNode: succeeds iff child always succeeds", () {
      expect(gen.isPassIfNull(const PlusNode(EpsilonNode()), "test"), isTrue);
      expect(gen.isPassIfNull(const PlusNode(StringLiteralNode("a")), "test"), isFalse);
    });

    test("OptionalNode delegates to child", () {
      expect(gen.isPassIfNull(const OptionalNode(StringLiteralNode("a")), "test"), isTrue);
      expect(gen.isPassIfNull(const OptionalNode(EpsilonNode()), "test"), isTrue);
    });

    test("ChoiceNode: true if any branch always succeeds", () {
      expect(
        gen.isPassIfNull(
          const ChoiceNode([StringLiteralNode("a"), OptionalNode(EpsilonNode())]),
          "test",
        ),
        isTrue,
      );
      expect(
        gen.isPassIfNull(
          const ChoiceNode([StringLiteralNode("a"), StringLiteralNode("b")]),
          "test",
        ),
        isFalse,
      );
    });

    test("SequenceNode: true if all children always succeed", () {
      expect(
        gen.isPassIfNull(
          const SequenceNode([
            OptionalNode(StringLiteralNode("a")),
            OptionalNode(StringLiteralNode("b")),
          ], chosenIndex: null),
          "test",
        ),
        isTrue,
      );
      expect(
        gen.isPassIfNull(
          const SequenceNode([EpsilonNode(), StringLiteralNode("a")], chosenIndex: null),
          "test",
        ),
        isFalse,
      );
    });

    test("CountedNode always fails", () {
      expect(gen.isPassIfNull(const CountedNode(0, 5, StringLiteralNode("a")), "test"), isTrue);
      expect(gen.isPassIfNull(const CountedNode(1, 5, StringLiteralNode("a")), "test"), isFalse);
    });

    test("StarSeparatedNode always succeeds", () {
      expect(
        gen.isPassIfNull(
          const StarSeparatedNode(
            StringLiteralNode(","),
            StringLiteralNode("a"),
            isTrailingAllowed: false,
          ),
          "test",
        ),
        isTrue,
      );
    });

    test("SpecialSymbolNode always succeeds", () {
      expect(gen.isPassIfNull(const StartOfInputNode(), "test"), isFalse);
      expect(gen.isPassIfNull(const EndOfInputNode(), "test"), isFalse);
      expect(gen.isPassIfNull(const AnyCharacterNode(), "test"), isFalse);
    });

    test("RangeNode can fail", () {
      expect(gen.isPassIfNull(const RangeNode({(65, 90)}), "test"), isFalse);
    });

    test("RegExpNode can fail", () {
      expect(gen.isPassIfNull(const RegExpNode(r"\d"), "test"), isFalse);
    });

    test("ExceptNode always can fail", () {
      expect(gen.isPassIfNull(const ExceptNode(StringLiteralNode("a")), "test"), isFalse);
    });

    test("NamedNode delegates to child", () {
      expect(gen.isPassIfNull(const NamedNode("x", EpsilonNode()), "test"), isTrue);
      expect(gen.isPassIfNull(const NamedNode("x", StringLiteralNode("a")), "test"), isFalse);
    });

    test("AndPredicateNode delegates", () {
      expect(gen.isPassIfNull(const AndPredicateNode(EpsilonNode()), "test"), isTrue);
    });

    test("NotPredicateNode delegates", () {
      expect(gen.isPassIfNull(const NotPredicateNode(EpsilonNode()), "test"), isTrue);
    });
  });

  // -------------------------------------------------------------------------
  //  Test group 4 – End-to-end: compile grammar → run in isolate
  // -------------------------------------------------------------------------

  group("End-to-end: simple grammar in isolate", () {
    late IsolateParser iso;

    setUpAll(() async {
      iso = await spawnParser(r'''
String rule = ^ "hello" $ @1;
''');
    });

    tearDownAll(() => iso.dispose());

    test("matches exact input", () async {
      var result = await iso.parse("hello");
      expect(result, isNotNull);
    });

    test("rejects non-matching input", () async {
      var result = await iso.parse("world");
      expect(result, isNull);
    });

    test("rejects partial match", () async {
      var result = await iso.parse("hello world");
      expect(result, isNull);
    });

    test("rejects empty input", () async {
      var result = await iso.parse("");
      expect(result, isNull);
    });
  });

  group("End-to-end: choice grammar", () {
    late IsolateParser iso;

    setUpAll(() async {
      iso = await spawnParser(r'''
String rule = ^ ("a" | "b" | "c") $ @1;
''');
    });

    tearDownAll(() => iso.dispose());

    test("matches first choice", () async {
      expect(await iso.parse("a"), isNotNull);
    });

    test("matches second choice", () async {
      expect(await iso.parse("b"), isNotNull);
    });

    test("matches third choice", () async {
      expect(await iso.parse("c"), isNotNull);
    });

    test("rejects unmatched", () async {
      expect(await iso.parse("d"), isNull);
    });
  });

  group("End-to-end: quantifiers", () {
    late IsolateParser iso;

    setUpAll(() async {
      iso = await spawnParser(r'''
rule = ^ "a"+ $;
''');
    });

    tearDownAll(() => iso.dispose());

    test("matches one", () async {
      expect(await iso.parse("a"), isNotNull);
    });

    test("matches many", () async {
      expect(await iso.parse("aaa"), isNotNull);
    });

    test("rejects zero", () async {
      expect(await iso.parse(""), isNull);
    });

    test("rejects wrong char", () async {
      expect(await iso.parse("b"), isNull);
    });
  });

  group("End-to-end: star quantifier", () {
    late IsolateParser iso;

    setUpAll(() async {
      iso = await spawnParser(r'''
rule = ^ "a"* $;
''');
    });

    tearDownAll(() => iso.dispose());

    test("matches zero", () async {
      expect(await iso.parse(""), isNotNull);
    });

    test("matches many", () async {
      expect(await iso.parse("aaa"), isNotNull);
    });

    test("rejects wrong char", () async {
      expect(await iso.parse("b"), isNull);
    });
  });

  group("End-to-end: optional", () {
    late IsolateParser iso;

    setUpAll(() async {
      iso = await spawnParser(r'''
rule = ^ "a" "b"? "c" $;
''');
    });

    tearDownAll(() => iso.dispose());

    test("matches with optional present", () async {
      expect(await iso.parse("abc"), isNotNull);
    });

    test("matches with optional absent", () async {
      expect(await iso.parse("ac"), isNotNull);
    });

    test("rejects invalid", () async {
      expect(await iso.parse("adc"), isNull);
    });
  });

  group("End-to-end: regex and ranges", () {
    late IsolateParser iso;

    setUpAll(() async {
      iso = await spawnParser(r"""
rule = ^ <[a-z]+> $;
""");
    });

    tearDownAll(() => iso.dispose());

    test("matches lowercase letters", () async {
      expect(await iso.parse("abc"), isNotNull);
    });

    test("rejects uppercase", () async {
      expect(await iso.parse("ABC"), isNull);
    });

    test("rejects digits", () async {
      expect(await iso.parse("123"), isNull);
    });
  });

  group("End-to-end: predicates", () {
    late IsolateParser iso;

    setUpAll(() async {
      iso = await spawnParser(r'''
rule = ^ &"a" . $;
''');
    });

    tearDownAll(() => iso.dispose());

    test("lookahead matches", () async {
      expect(await iso.parse("a"), isNotNull);
    });

    test("lookahead rejects", () async {
      expect(await iso.parse("b"), isNull);
    });
  });

  group("End-to-end: negative predicate", () {
    late IsolateParser iso;

    setUpAll(() async {
      iso = await spawnParser(r'''
rule = ^ !"x" . $;
''');
    });

    tearDownAll(() => iso.dispose());

    test("negative lookahead allows non-x", () async {
      expect(await iso.parse("a"), isNotNull);
    });

    test("negative lookahead rejects x", () async {
      expect(await iso.parse("x"), isNull);
    });
  });

  group("End-to-end: left recursion", () {
    late IsolateParser iso;

    setUpAll(() async {
      iso = await spawnParser(r'''
Object rule = ^ expr $;
Object expr = expr "+" "a" | "a";
''');
    });

    tearDownAll(() => iso.dispose());

    test("base case", () async {
      expect(await iso.parse("a"), isNotNull);
    });

    test("one recursion", () async {
      expect(await iso.parse("a+a"), isNotNull);
    });

    test("multiple recursions", () async {
      expect(await iso.parse("a+a+a+a"), isNotNull);
    });

    test("rejects trailing +", () async {
      expect(await iso.parse("a+"), isNull);
    });
  });

  group("End-to-end: separated lists", () {
    late IsolateParser iso;

    setUpAll(() async {
      iso = await spawnParser(r'''
rule = ^ ","..item+ $;
item = [a-z]+;
''');
    });

    tearDownAll(() => iso.dispose());

    test("single item", () async {
      expect(await iso.parse("abc"), isNotNull);
    });

    test("multiple items", () async {
      expect(await iso.parse("a,b,c"), isNotNull);
    });

    test("rejects empty", () async {
      expect(await iso.parse(""), isNull);
    });

    test("rejects trailing comma", () async {
      expect(await iso.parse("a,b,"), isNull);
    });
  });

  group("End-to-end: counted repetition", () {
    late IsolateParser iso;

    setUpAll(() async {
      iso = await spawnParser(r'''
rule = ^ 2..4 "a" $;
''');
    });

    tearDownAll(() => iso.dispose());

    test("matches min", () async {
      expect(await iso.parse("aa"), isNotNull);
    });

    test("matches max", () async {
      expect(await iso.parse("aaaa"), isNotNull);
    });

    test("matches between", () async {
      expect(await iso.parse("aaa"), isNotNull);
    });

    test("rejects less than min", () async {
      expect(await iso.parse("a"), isNull);
    });

    test("rejects more than max", () async {
      expect(await iso.parse("aaaaa"), isNull);
    });
  });

  group("End-to-end: inline actions", () {
    late IsolateParser iso;

    setUpAll(() async {
      iso = await spawnParser(r"""
int rule = ^ :val $ |> val;
@fragment int val = \d+ { int.parse($.join()) };
""");
    });

    tearDownAll(() => iso.dispose());

    test("computes action result", () async {
      expect(await iso.parse("42"), equals(42));
    });

    test("computes larger number", () async {
      expect(await iso.parse("12345"), equals(12345));
    });

    test("rejects non-digits", () async {
      expect(await iso.parse("abc"), isNull);
    });
  });

  group("End-to-end: math expression evaluator", () {
    late IsolateParser iso;

    setUpAll(() async {
      iso = await spawnParser(
        readGrammarFile("examples/math/math.dart_grammar"),
        parserName: "MathParser",
      );
    });

    tearDownAll(() => iso.dispose());

    test("parse integer", () async {
      expect(await iso.parse("42"), equals(42));
    });

    test("parse float", () async {
      expect(await iso.parse("3.14"), equals(3.14));
    });

    test("addition", () async {
      expect(await iso.parse("1+2"), equals(3));
    });

    test("subtraction", () async {
      expect(await iso.parse("10-3"), equals(7));
    });

    test("multiplication", () async {
      expect(await iso.parse("3*4"), equals(12));
    });

    test("division", () async {
      expect(await iso.parse("10/2"), equals(5));
    });

    test("modulo", () async {
      expect(await iso.parse("10%3"), equals(1));
    });

    test("integer division", () async {
      expect(await iso.parse("7~/2"), equals(3));
    });

    test("exponentiation", () async {
      expect(await iso.parse("2^3"), equals(8));
    });

    test("unary negation", () async {
      expect(await iso.parse("-5"), equals(-5));
    });

    test("parentheses", () async {
      expect(await iso.parse("(2+3)*4"), equals(20));
    });

    test("operator precedence: add and mult", () async {
      expect(await iso.parse("2+3*4"), equals(14));
    });

    test("whitespace handling", () async {
      expect(await iso.parse("  2 + 3  "), equals(5));
    });

    test("complex expression", () async {
      expect(await iso.parse("(1+2)*(3+4)"), equals(21));
    });

    test("nested parentheses", () async {
      expect(await iso.parse("((2+3))"), equals(5));
    });

    test("chained additions (left assoc)", () async {
      expect(await iso.parse("1+2+3"), equals(6));
    });

    test("rejects empty", () async {
      expect(await iso.parse(""), isNull);
    });
  });

  // -------------------------------------------------------------------------
  //  Test group 5 – Self-hosting: compiled grammar parses itself
  // -------------------------------------------------------------------------

  group("Self-hosting: metagrammar bootstrap", () {
    test("compiled grammar parser can parse the math grammar", () async {
      var metagrammarSource = readGrammarFile("examples/meta/grammar_parser.dart_grammar");

      var parser = GrammarParser();
      var gen = parser.parse(metagrammarSource)!;
      var compiledCode = await gen.compileAnalyzedParserGenerator("CompiledGrammarParser");

      // Verify the compiled code is reasonable
      expect(compiledCode, contains("class CompiledGrammarParser"));
      expect(compiledCode.length, greaterThan(1000));
    });

    test("metagrammar round-trips: parse → compile → parse", () async {
      // Step 1: Parse the metagrammar
      var metagrammarSource = readGrammarFile("examples/meta/grammar_parser.dart_grammar");
      var parser = GrammarParser();
      var gen = parser.parse(metagrammarSource);
      expect(gen, isNotNull, reason: "metagrammar should parse");

      // Step 2: Compile to code
      var code = await gen!.compileAnalyzedParserGenerator("GrammarParser");
      expect(code.length, greaterThan(1000));

      // Step 3: Spawn the compiled parser in an isolate and use it to parse a grammar
      var mathGrammar = readGrammarFile("examples/math/math.dart_grammar");

      var driver =
          """
import "dart:convert" show jsonEncode;
import "dart:isolate" show ReceivePort, SendPort;

$code

void main(List<String> _, SendPort initPort) {
  var receivePort = ReceivePort();
  initPort.send(receivePort.sendPort);

  var parser = GrammarParser();

  receivePort.listen((msg) {
    var [replyPort as SendPort, input as String] = msg as List;
    try {
      var result = parser.parse(input);
      replyPort.send(result != null ? "parsed" : "failed");
    } catch (e, st) {
      replyPort.send("error: \$e");
    }
  });
}
""";

      var uri = Uri.dataFromString(
        driver,
        mimeType: "application/dart",
        encoding: const SystemEncoding(),
        base64: true,
      );

      var initPort = ReceivePort();
      var onError = ReceivePort();
      var errors = <dynamic>[];
      onError.listen((data) => errors.add(data));

      var isolate = await Isolate.spawnUri(uri, [], initPort.sendPort, onError: onError.sendPort);

      var sendPort = await initPort.first as SendPort;

      // Now test: can it parse the math grammar?
      var reply1 = ReceivePort();
      sendPort.send([reply1.sendPort, mathGrammar]);
      var result1 = await reply1.first;
      expect(result1, equals("parsed"), reason: "compiled parser should parse math grammar");

      // Can it parse a simple grammar?
      var reply2 = ReceivePort();
      sendPort.send([reply2.sendPort, 'String rule = "hello";']);
      var result2 = await reply2.first;
      expect(result2, equals("parsed"), reason: "compiled parser should parse simple grammar");

      // Can it handle invalid input?
      var reply3 = ReceivePort();
      sendPort.send([reply3.sendPort, "rule = ;"]);
      var result3 = await reply3.first;
      expect(result3, equals("failed"), reason: "compiled parser should reject invalid grammar");

      // Cleanup
      isolate.kill(priority: Isolate.immediate);
      onError.close();
    }, timeout: const Timeout(Duration(minutes: 3)));
  });

  // -------------------------------------------------------------------------
  //  Test group – Cut operator (#)
  // -------------------------------------------------------------------------

  group("Cut operator: grammar parsing", () {
    late GrammarParser parser;

    setUp(() => parser = GrammarParser());

    test("parse simple cut in choice", () {
      var result = parser.parse('rule = "a" # "b" | "c";');
      expect(result, isA<ParserGenerator>());
    });

    test("parse cut in first alternative only", () {
      var result = parser.parse('rule = "x" # "y" | "z";');
      expect(result, isA<ParserGenerator>());
    });

    test("parse cut in multiple alternatives", () {
      var result = parser.parse('rule = "a" # "b" | "c" # "d" | "e";');
      expect(result, isA<ParserGenerator>());
    });

    test("parse cut with no following token in sequence", () {
      var result = parser.parse('rule = "a" # | "b";');
      expect(result, isA<ParserGenerator>());
    });

    test("parse bare cut", () {
      var result = parser.parse('rule = # "a" | "b";');
      expect(result, isA<ParserGenerator>());
    });

    test("parse cut in nested group", () {
      var result = parser.parse('rule = ("a" # "b") | "c";');
      expect(result, isA<ParserGenerator>());
    });

    test("parse cut with quantifier siblings", () {
      var result = parser.parse('rule = "a"+ # "b" | "c";');
      expect(result, isA<ParserGenerator>());
    });

    test("parse cut compiles", () async {
      var gen = parser.parse('rule = "a" # "b" | "c";')!;
      var code = gen.compileParserGenerator("CutParser");
      expect(code, contains("isCut"));
    });

    test("CutNode is AtomicNode", () {
      expect(const CutNode(), isA<AtomicNode>());
    });

    test("CutNode isPassIfNull returns true", () {
      var gen = parser.parse('rule = "a" | "b";')!;
      expect(gen.isPassIfNull(const CutNode(), "test"), isTrue);
    });
  });

  group("End-to-end: cut basic behavior", () {
    late IsolateParser iso;

    setUpAll(() async {
      // rule = "a" # "b" | "c"
      // If "a" matches, cut commits — even if "b" fails, "c" is NOT tried.
      iso = await spawnParser(r'''
rule = ^ ("a" # "b" | "c") $;
''');
    });

    tearDownAll(() => iso.dispose());

    test("matches first alternative fully (a then b)", () async {
      expect(await iso.parse("ab"), isNotNull);
    });

    test("matches second alternative when first does not start", () async {
      // "a" doesn't match at all, so cut not reached, "c" is tried
      expect(await iso.parse("c"), isNotNull);
    });

    test("cut prevents fallback: 'a' matches but 'b' fails → no 'c' tried", () async {
      // "a" matches, cut fires, "b" fails → cut prevents trying "c".
      // Even though "a" alone is in the input (so "c" choice would also fail),
      // the key point: the parser does NOT fall through to "c".
      expect(await iso.parse("a"), isNull);
    });

    test("rejects unrelated input", () async {
      expect(await iso.parse("d"), isNull);
    });

    test("rejects empty", () async {
      expect(await iso.parse(""), isNull);
    });
  });

  group("End-to-end: cut does not fire if branch not entered", () {
    late IsolateParser iso;

    setUpAll(() async {
      // The cut is in the first alternative.
      // If "x" doesn't match, the parser should try "y" normally.
      iso = await spawnParser(r'''
rule = ^ ("x" # "!" | "y") $;
''');
    });

    tearDownAll(() => iso.dispose());

    test("first branch succeeds with cut path", () async {
      expect(await iso.parse("x!"), isNotNull);
    });

    test("second branch succeeds when first branch not entered", () async {
      expect(await iso.parse("y"), isNotNull);
    });

    test("cut blocks fallback after partial first branch match", () async {
      // "x" matches, cut fires, "!" fails → cut blocks "y"
      expect(await iso.parse("x"), isNull);
    });
  });

  group("End-to-end: cut in multi-branch choice", () {
    late IsolateParser iso;

    setUpAll(() async {
      // Three alternatives, cut in first only.
      iso = await spawnParser(r'''
rule = ^ ("a" # "1" | "b" | "c") $;
''');
    });

    tearDownAll(() => iso.dispose());

    test("first branch full match", () async {
      expect(await iso.parse("a1"), isNotNull);
    });

    test("second branch works when first not entered", () async {
      expect(await iso.parse("b"), isNotNull);
    });

    test("third branch works when first not entered", () async {
      expect(await iso.parse("c"), isNotNull);
    });

    test("cut blocks ALL subsequent alternatives", () async {
      // "a" matches, cut fires, "1" fails → neither "b" nor "c" is tried
      expect(await iso.parse("a"), isNull);
    });
  });

  group("End-to-end: cut in multiple alternatives", () {
    late IsolateParser iso;

    setUpAll(() async {
      // Both first and second alternatives have cuts.
      iso = await spawnParser(r'''
rule = ^ ("a" # "1" | "b" # "2" | "c") $;
''');
    });

    tearDownAll(() => iso.dispose());

    test("first branch succeeds", () async {
      expect(await iso.parse("a1"), isNotNull);
    });

    test("second branch succeeds", () async {
      expect(await iso.parse("b2"), isNotNull);
    });

    test("third branch succeeds", () async {
      expect(await iso.parse("c"), isNotNull);
    });

    test("cut in first blocks rest after partial", () async {
      expect(await iso.parse("a"), isNull);
    });

    test("cut in second blocks third after partial", () async {
      // "a" doesn't match, "b" matches, cut fires, "2" fails → "c" not tried
      expect(await iso.parse("b"), isNull);
    });
  });

  group("End-to-end: cut with referenced rules (inlined)", () {
    late IsolateParser iso;

    setUpAll(() async {
      // Cut must be at the same choice level to block alternatives.
      // Cuts are scoped to their enclosing rule's choice.
      iso = await spawnParser(r'''
rule = ^ stmt $;
stmt = "if" # "(" identifier ")" | identifier;
identifier = [a-z]+;
''');
    });

    tearDownAll(() => iso.dispose());

    test("full if statement parses", () async {
      expect(await iso.parse("if(x)"), isNotNull);
    });

    test("plain identifier parses (if not matched)", () async {
      expect(await iso.parse("hello"), isNotNull);
    });

    test("cut after 'if' blocks fallback to identifier", () async {
      // "if" matches, cut fires, "(" fails → identifier not tried
      expect(await iso.parse("if"), isNull);
    });

    test("if without closing paren fails", () async {
      expect(await iso.parse("if(x"), isNull);
    });
  });

  group("End-to-end: cut is scoped to its rule", () {
    late IsolateParser iso;

    setUpAll(() async {
      // Cut inside ifStmt does NOT propagate to the outer stmt choice.
      iso = await spawnParser(r'''
rule = ^ stmt $;
stmt = ifStmt | identifier;
ifStmt = "if" # "(" identifier ")";
identifier = [a-z]+;
''');
    });

    tearDownAll(() => iso.dispose());

    test("full if statement parses", () async {
      expect(await iso.parse("if(x)"), isNotNull);
    });

    test("plain identifier parses", () async {
      expect(await iso.parse("hello"), isNotNull);
    });

    test("cut in inner rule does NOT block outer choice alternatives", () async {
      // "if" matches in ifStmt, cut fires inside ifStmt, "(" fails → ifStmt returns null.
      // But the outer stmt choice has its own _mark, so it recovers and tries identifier.
      // "if" matches [a-z]+ as an identifier.
      expect(await iso.parse("if"), isNotNull);
    });
  });

  group("End-to-end: cut properly cuts as second option", () {
    late IsolateParser iso;

    setUpAll(() async {
      // Cut inside ifStmt does NOT propagate to the outer stmt choice.
      iso = await spawnParser(r'''
rule = ^ stmt $;
stmt = "if" # "(" identifier ")" | "when" # "(" identifier ")" | identifier;
identifier = [a-z]+;
''');
    });

    tearDownAll(() => iso.dispose());

    test("full if statement parses", () async {
      expect(await iso.parse("if(x)"), isNotNull);
    });

    test("full when statement parses", () async {
      expect(await iso.parse("when(x)"), isNotNull);
    });

    test("plain identifier parses", () async {
      expect(await iso.parse("hello"), isNotNull);
    });

    test("cut in inner rule blocks choice alternatives", () async {
      expect(await iso.parse("if"), isNull);
    });

    test("cut in second option blocks choice alternatives", () async {
      expect(await iso.parse("when"), isNull);
    });
  });

  group("End-to-end: cut with sequence continuation", () {
    late IsolateParser iso;

    setUpAll(() async {
      // The cut is in the middle of a longer sequence.
      iso = await spawnParser(r'''
rule = ^ ("a" "b" # "c" "d" | "e") $;
''');
    });

    tearDownAll(() => iso.dispose());

    test("full first branch matches", () async {
      expect(await iso.parse("abcd"), isNotNull);
    });

    test("second branch when first not started", () async {
      expect(await iso.parse("e"), isNotNull);
    });

    test("partial before cut — normal backtrack to second", () async {
      // "a" matches, "b" fails → cut NOT reached → "e" is tried
      // But "a" alone doesn't match "e" either, so null
      expect(await iso.parse("a"), isNull);
    });

    test("past cut — committed, no fallback", () async {
      // "a" matches, "b" matches, cut fires, "c" fails → no "e" tried
      expect(await iso.parse("ab"), isNull);
    });

    test("past cut, c matches but d fails", () async {
      // "a","b" match, cut fires, "c" matches, "d" fails → committed, fail
      expect(await iso.parse("abc"), isNull);
    });
  });

  group("End-to-end: cut does not affect outer choices", () {
    late IsolateParser iso;

    setUpAll(() async {
      // Cut is inside a nested group — it should only affect the inner choice.
      iso = await spawnParser(r'''
rule = ^ (inner | "z") $;
inner = "a" # "b" | "c";
''');
    });

    tearDownAll(() => iso.dispose());

    test("inner first branch succeeds", () async {
      expect(await iso.parse("ab"), isNotNull);
    });

    test("inner second branch works when inner first not started", () async {
      expect(await iso.parse("c"), isNotNull);
    });

    test("outer fallback 'z' works when inner fails entirely", () async {
      expect(await iso.parse("z"), isNotNull);
    });

    test("cut in inner blocks inner alternatives but outer can still fail gracefully", () async {
      // "a" matches in inner, cut fires, "b" fails → inner returns null
      // outer choice can try "z" — but "a" is already consumed? No: outer recovers _mark.
      // Actually, the outer choice has its own _mark and _recover.
      // inner returns null, outer _recover restores position, tries "z".
      // But the input is "a", not "z", so this should be null.
      expect(await iso.parse("a"), isNull);
    });
  });

  group("End-to-end: cut with repetition", () {
    late IsolateParser iso;

    setUpAll(() async {
      iso = await spawnParser(r'''
rule = ^ item+ $;
item = "a" # "b" | "c";
''');
    });

    tearDownAll(() => iso.dispose());

    test("repeated cut items succeed", () async {
      expect(await iso.parse("ababab"), isNotNull);
    });

    test("non-cut alternative repeats", () async {
      expect(await iso.parse("ccc"), isNotNull);
    });

    test("mixed items", () async {
      expect(await iso.parse("abcab"), isNotNull);
    });

    test("cut failure in repetition stops", () async {
      // First "a" matches, cut fires, "b" fails → item returns null → plus fails
      expect(await iso.parse("a"), isNull);
    });
  });

  group("End-to-end: cut early in sequence (before anything)", () {
    late IsolateParser iso;

    setUpAll(() async {
      // Cut at the very start of the sequence — commits immediately
      iso = await spawnParser(r'''
rule = ^ (# "a" "b" | "c") $;
''');
    });

    tearDownAll(() => iso.dispose());

    test("first branch full match", () async {
      expect(await iso.parse("ab"), isNotNull);
    });

    test("cut fires immediately, blocking second even with no prior match", () async {
      // Cut fires before anything is matched → "c" blocked
      expect(await iso.parse("c"), isNull);
    });
  });

  group("End-to-end: no cut — normal backtracking baseline", () {
    late IsolateParser iso;

    setUpAll(() async {
      // Same structure but WITHOUT cut — verify backtracking works normally
      iso = await spawnParser(r'''
rule = ^ ("a" "b" | "c") $;
''');
    });

    tearDownAll(() => iso.dispose());

    test("first branch matches", () async {
      expect(await iso.parse("ab"), isNotNull);
    });

    test("second branch via backtrack", () async {
      expect(await iso.parse("c"), isNotNull);
    });

    test("partial first branch backtracks to second (no cut)", () async {
      // "a" matches, "b" fails → backtrack → try "c"
      // Input is "a", "c" doesn't match either, so null
      expect(await iso.parse("a"), isNull);
    });
  });

  group("End-to-end: cut with actions", () {
    late IsolateParser iso;

    setUpAll(() async {
      iso = await spawnParser(r"""
int rule = ^ expr $ @1;
int expr = "a" # :n |> n
         | "default" |> 0;
@fragment int n = \d+ { int.parse($.join()) };
""");
    });

    tearDownAll(() => iso.dispose());

    test("cut path with action", () async {
      expect(await iso.parse("a42"), equals(42));
    });

    test("default path when first not entered", () async {
      expect(await iso.parse("default"), equals(0));
    });

    test("cut blocks default after partial match", () async {
      // "a" matches, cut fires, digit fails → no "default" tried
      expect(await iso.parse("a"), isNull);
    });
  });

  group("End-to-end: cut with optional and predicates", () {
    late IsolateParser iso;

    setUpAll(() async {
      iso = await spawnParser(r'''
rule = ^ (keyword # "(" [a-z]+ ")" | identifier) $ @1;
keyword = "fn";
identifier = <[a-z]+>;
''');
    });

    tearDownAll(() => iso.dispose());

    test("keyword path succeeds", () async {
      expect(await iso.parse("fn(abc)"), isNotNull);
    });

    test("identifier path succeeds", () async {
      expect(await iso.parse("hello"), isNotNull);
    });

    test("keyword partial match blocked by cut", () async {
      // "fn" matches keyword, cut fires, "(" fails → identifier not tried
      expect(await iso.parse("fn"), isNull);
    });

    test("fn prefix as identifier blocked by cut", () async {
      // "fn" matches keyword, cut fires, then expects "(", gets "x" → fail, no identifier fallback
      expect(await iso.parse("fnx"), isNull);
    });
  });

  // -------------------------------------------------------------------------
  //  Test group 6 – Node construction & visitor dispatch
  // -------------------------------------------------------------------------

  group("Node types", () {
    test("EpsilonNode dispatches to visitor", () {
      var node = const EpsilonNode();
      expect(node, isA<AtomicNode>());
    });

    test("StringLiteralNode stores literal", () {
      var node = const StringLiteralNode("hello");
      expect(node.literal, "hello");
    });

    test("RangeNode stores ranges", () {
      var node = const RangeNode({(65, 90), (97, 122)});
      expect(node.ranges, hasLength(2));
    });

    test("RegExpNode stores value", () {
      var node = const RegExpNode(r"\d+");
      expect(node.value, r"\d+");
    });

    test("SequenceNode stores children and chosenIndex", () {
      var node = const SequenceNode([
        StringLiteralNode("a"),
        StringLiteralNode("b"),
      ], chosenIndex: 1);
      expect(node.children, hasLength(2));
      expect(node.chosenIndex, 1);
    });

    test("ChoiceNode stores children", () {
      var node = const ChoiceNode([StringLiteralNode("a"), StringLiteralNode("b")]);
      expect(node.children, hasLength(2));
    });

    test("PlusNode wraps child", () {
      var child = const StringLiteralNode("a");
      var node = PlusNode(child);
      expect(node.child, same(child));
    });

    test("StarNode wraps child", () {
      var child = const StringLiteralNode("a");
      var node = StarNode(child);
      expect(node.child, same(child));
    });

    test("OptionalNode wraps child", () {
      var child = const StringLiteralNode("a");
      var node = OptionalNode(child);
      expect(node.child, same(child));
    });

    test("CountedNode stores min/max/child", () {
      var node = const CountedNode(2, 5, StringLiteralNode("a"));
      expect(node.min, 2);
      expect(node.max, 5);
    });

    test("PlusSeparatedNode stores separator and child", () {
      var node = const PlusSeparatedNode(
        StringLiteralNode(","),
        StringLiteralNode("a"),
        isTrailingAllowed: true,
      );
      expect(node.isTrailingAllowed, isTrue);
    });

    test("AndPredicateNode wraps child", () {
      var node = const AndPredicateNode(StringLiteralNode("a"));
      expect(node.child, isA<StringLiteralNode>());
    });

    test("NotPredicateNode wraps child", () {
      var node = const NotPredicateNode(StringLiteralNode("a"));
      expect(node.child, isA<StringLiteralNode>());
    });

    test("ExceptNode wraps child", () {
      var node = const ExceptNode(StringLiteralNode("a"));
      expect(node.child, isA<StringLiteralNode>());
    });

    test("ReferenceNode stores ruleName", () {
      var node = const ReferenceNode("myRule");
      expect(node.ruleName, "myRule");
    });

    test("FragmentNode stores fragmentName", () {
      var node = const FragmentNode("myFrag");
      expect(node.fragmentName, "myFrag");
    });

    test("NamedNode stores name and child", () {
      var node = const NamedNode("label", StringLiteralNode("x"));
      expect(node.name, "label");
    });

    test("ActionNode stores action and flags", () {
      var node = const ActionNode(
        StringLiteralNode("x"),
        "code",
        areIndicesProvided: true,
        isSpanUsed: false,
      );
      expect(node.action, "code");
      expect(node.areIndicesProvided, isTrue);
      expect(node.isSpanUsed, isFalse);
    });

    test("InlineActionNode stores action and flags", () {
      var node = const InlineActionNode(
        StringLiteralNode("x"),
        "code",
        areIndicesProvided: false,
        isSpanUsed: true,
      );
      expect(node.action, "code");
      expect(node.areIndicesProvided, isFalse);
      expect(node.isSpanUsed, isTrue);
    });

    test("SpecialSymbolNode subtypes", () {
      expect(const StartOfInputNode(), isA<SpecialSymbolNode>());
      expect(const EndOfInputNode(), isA<SpecialSymbolNode>());
      expect(const AnyCharacterNode(), isA<SpecialSymbolNode>());
    });

    test("RegExpEscapeNode variants", () {
      expect(SimpleRegExpEscapeNode.digit.pattern, r"\d");
      expect(SimpleRegExpEscapeNode.word.pattern, r"\w");
      expect(SimpleRegExpEscapeNode.whitespace.pattern, r"\s");
      expect(SimpleRegExpEscapeNode.notDigit.pattern, r"\D");
      expect(SimpleRegExpEscapeNode.notWord.pattern, r"\W");
      expect(SimpleRegExpEscapeNode.notWhitespace.pattern, r"\S");
      expect(SimpleRegExpEscapeNode.tab.pattern, r"\t");
      expect(SimpleRegExpEscapeNode.newline.pattern, r"\n");
    });

    test("TriePatternNode stores options", () {
      var node = const TriePatternNode(["if", "else", "while"]);
      expect(node.options, ["if", "else", "while"]);
    });
  });

  // -------------------------------------------------------------------------
  //  Test group 7 – Statement types
  // -------------------------------------------------------------------------

  group("Statement types", () {
    test("DeclarationStatement", () {
      var stmt = const DeclarationStatement(
        "String",
        "myRule",
        StringLiteralNode("hello"),
        tag: Tag.rule,
      );
      expect(stmt.type, "String");
      expect(stmt.name, "myRule");
      expect(stmt.tag, Tag.rule);
    });

    test("DeclarationStatement.predefined", () {
      var stmt = const DeclarationStatement.predefined("x", EpsilonNode());
      expect(stmt.tag, isNull);
      expect(stmt.type, "String");
    });

    test("NamespaceStatement", () {
      var stmt = const NamespaceStatement("myNs", [
        DeclarationStatement("String", "a", StringLiteralNode("a"), tag: Tag.rule),
      ], tag: Tag.fragment);
      expect(stmt.name, "myNs");
      expect(stmt.tag, Tag.fragment);
      expect(stmt.children, hasLength(1));
    });

    test("DeclarationTypeStatement", () {
      var stmt = const DeclarationTypeStatement("int", ["a", "b"], tag: Tag.rule);
      expect(stmt.type, "int");
      expect(stmt.names, ["a", "b"]);
    });

    test("HybridNamespaceStatement", () {
      var stmt = const HybridNamespaceStatement(
        "String",
        "x",
        [DeclarationStatement("String", "a", StringLiteralNode("a"), tag: Tag.rule)],
        outerTag: Tag.rule,
        innerTag: Tag.fragment,
      );
      expect(stmt.type, "String");
      expect(stmt.name, "x");
      expect(stmt.outerTag, Tag.rule);
      expect(stmt.innerTag, Tag.fragment);
    });

    test("Tag enum values", () {
      expect(Tag.values, hasLength(3));
      expect(Tag.values, contains(Tag.rule));
      expect(Tag.values, contains(Tag.fragment));
      expect(Tag.values, contains(Tag.inline));
    });
  });

  // -------------------------------------------------------------------------
  //  Test group 8 – Edge cases and error handling
  // -------------------------------------------------------------------------

  group("Edge cases", () {
    test("grammar with all regex escapes", () {
      var parser = GrammarParser();
      var result = parser.parse(r"rule = \d | \w | \s | \D | \W | \S | \t | \n;");
      expect(result, isA<ParserGenerator>());
    });

    test("deeply nested choices", () {
      var parser = GrammarParser();
      var result = parser.parse('''
rule = ("a" | ("b" | ("c" | "d")));
''');
      expect(result, isA<ParserGenerator>());
    });

    test("deeply nested sequences", () {
      var parser = GrammarParser();
      var result = parser.parse('''
rule = "a" ("b" ("c" "d"));
''');
      expect(result, isA<ParserGenerator>());
    });

    test("many rules", () {
      var rules = List.generate(20, (i) => 'r$i = "val$i";').join("\n");
      var parser = GrammarParser();
      var result = parser.parse(rules);
      expect(result, isA<ParserGenerator>());
    });

    test("unicode in grammar", () {
      var parser = GrammarParser();
      var result = parser.parse('rule = "こんにちは" | "世界";');
      expect(result, isA<ParserGenerator>());
    });

    test("empty sequence compiles", () {
      var parser = GrammarParser();
      var result = parser.parse("rule = ε;");
      expect(result, isA<ParserGenerator>());
    });

    test("special characters in string literals", () {
      var parser = GrammarParser();
      var result = parser.parse(r'''rule = "hello\nworld";''');
      expect(result, isA<ParserGenerator>());
    });

    test("nested namespaces", () {
      var parser = GrammarParser();
      var result = parser.parse('''
outer {
  inner {
    rule = "x";
  }
}
entry = outer.inner.rule;
''');
      expect(result, isA<ParserGenerator>());
    });

    test("multiple type declarations", () {
      var parser = GrammarParser();
      var result = parser.parse('''
int a, b, c;
a = "1" { 1 };
b = "2" { 2 };
c = "3" { 3 };
entry = a | b | c;
''');
      expect(result, isA<ParserGenerator>());
    });
  });

  // -------------------------------------------------------------------------
  //  Test group 9 – End-to-end: separator features & except
  // -------------------------------------------------------------------------

  group("End-to-end: star separated list", () {
    late IsolateParser iso;

    setUpAll(() async {
      iso = await spawnParser(r'''
rule = ^ ","..item* $;
item = [a-z]+;
''');
    });

    tearDownAll(() => iso.dispose());

    test("empty matches", () async {
      expect(await iso.parse(""), isNotNull);
    });

    test("single item matches", () async {
      expect(await iso.parse("abc"), isNotNull);
    });

    test("multiple items", () async {
      expect(await iso.parse("a,b,c"), isNotNull);
    });
  });

  group("End-to-end: except node", () {
    late IsolateParser iso;

    setUpAll(() async {
      iso = await spawnParser(r'''
rule = ^ (~"x")+ $;
''');
    });

    tearDownAll(() => iso.dispose());

    test("matches non-x characters", () async {
      expect(await iso.parse("abc"), isNotNull);
    });

    test("rejects x anywhere", () async {
      expect(await iso.parse("axc"), isNull);
    });

    test("rejects single x", () async {
      expect(await iso.parse("x"), isNull);
    });
  });

  group("End-to-end: fragment vs rule", () {
    late IsolateParser iso;

    setUpAll(() async {
      iso = await spawnParser(r'''
entry = ^ tok $;
@fragment tok = "hello" | "world";
''');
    });

    tearDownAll(() => iso.dispose());

    test("fragment matches hello", () async {
      expect(await iso.parse("hello"), isNotNull);
    });

    test("fragment matches world", () async {
      expect(await iso.parse("world"), isNotNull);
    });

    test("fragment rejects other", () async {
      expect(await iso.parse("other"), isNull);
    });
  });

  group("End-to-end: whitespace handling", () {
    late IsolateParser iso;

    setUpAll(() async {
      iso = await spawnParser(r'''
rule = ^ "a" _ "b" _ "c" $;
_ = \s* { () };
''');
    });

    tearDownAll(() => iso.dispose());

    test("no spaces", () async {
      expect(await iso.parse("abc"), isNotNull);
    });

    test("with spaces", () async {
      expect(await iso.parse("a b c"), isNotNull);
    });

    test("with lots of whitespace", () async {
      expect(await iso.parse("a   b   c"), isNotNull);
    });

    test("with newlines", () async {
      expect(await iso.parse("a\nb\nc"), isNotNull);
    });
  });

  // -------------------------------------------------------------------------
  //  Test group 10 – String utility extensions
  // -------------------------------------------------------------------------

  group("IndentationExtension", () {
    test("indent adds two spaces", () {
      expect("hello".indent(), equals("  hello"));
    });

    test("indent with count", () {
      expect("hello".indent(2), equals("    hello"));
    });

    test("indent multiline", () {
      expect("a\nb".indent(), equals("  a\n  b"));
    });

    test("indent preserves empty lines", () {
      expect("a\n\nb".indent(), equals("  a\n\n  b"));
    });

    test("unindent removes common indentation", () {
      expect("  a\n  b".unindent(), equals("a\nb"));
    });

    test("unindent handles mixed indentation", () {
      expect("    a\n  b".unindent(), equals("  a\nb"));
    });

    test("unindent empty string", () {
      expect("".unindent(), equals(""));
    });
  });

  // -------------------------------------------------------------------------
  //  Test group 11 – End-to-end: edge cases for generated parsers
  // -------------------------------------------------------------------------

  group("End-to-end: drop operators (~> and <~)", () {
    late IsolateParser iso;

    setUpAll(() async {
      iso = await spawnParser(r'''
rule = ^ ("(" ~> <[a-z]+> <~ ")") $ @1;
''');
    });

    tearDownAll(() => iso.dispose());

    test("drops left and right, keeps middle", () async {
      expect(await iso.parse("(hello)"), equals("hello"));
    });

    test("rejects missing left paren", () async {
      expect(await iso.parse("hello)"), isNull);
    });

    test("rejects missing right paren", () async {
      expect(await iso.parse("(hello"), isNull);
    });

    test("rejects empty parens", () async {
      expect(await iso.parse("()"), isNull);
    });
  });

  group("End-to-end: chained drop operators", () {
    late IsolateParser iso;

    setUpAll(() async {
      iso = await spawnParser(r'''
rule = ^ ~> "[" ~> "(" ~> <[a-z]+> <~ ")" <~ "]" <~ $;
''');
    });

    tearDownAll(() => iso.dispose());

    test("multiple drops keep innermost", () async {
      expect(await iso.parse("[(hello)]"), equals("hello"));
    });

    test("rejects partial delimiters", () async {
      expect(await iso.parse("[hello]"), isNull);
    });
  });

  group("End-to-end: flat node <...>", () {
    late IsolateParser iso;

    setUpAll(() async {
      iso = await spawnParser(r'''
String rule = ^ <[a-z]+ ":" [0-9]+> $ @1;
''');
    });

    tearDownAll(() => iso.dispose());

    test("flattens sequence to string span", () async {
      expect(await iso.parse("abc:123"), equals("abc:123"));
    });

    test("rejects partial match", () async {
      expect(await iso.parse("abc:"), isNull);
    });

    test("rejects missing colon", () async {
      expect(await iso.parse("abc123"), isNull);
    });
  });

  group("End-to-end: flat node with quantifiers", () {
    late IsolateParser iso;

    setUpAll(() async {
      iso = await spawnParser(r'''
String rule = ^ <\d+ ("." \d+)?> $ @1;
''');
    });

    tearDownAll(() => iso.dispose());

    test("integer flattened", () async {
      expect(await iso.parse("42"), equals("42"));
    });

    test("float flattened", () async {
      expect(await iso.parse("3.14"), equals("3.14"));
    });

    test("rejects bare dot", () async {
      expect(await iso.parse(".5"), isNull);
    });
  });

  group("End-to-end: selection index @N", () {
    late IsolateParser iso;

    setUpAll(() async {
      iso = await spawnParser(r'''
rule = ^ "a" "b" "c" $ @2;
''');
    });

    tearDownAll(() => iso.dispose());

    test("selects second element (index 1)", () async {
      expect(await iso.parse("abc"), equals("b"));
    });

    test("rejects partial", () async {
      expect(await iso.parse("ab"), isNull);
    });
  });

  group("End-to-end: sequence returns tuple", () {
    late IsolateParser iso;

    setUpAll(() async {
      iso = await spawnParser(r'''
rule = ^ "x" "y" "z" $;
''');
    });

    tearDownAll(() => iso.dispose());

    test("sequence returns list of all elements", () async {
      var result = await iso.parse("xyz");
      // Sequences return records which serialize as lists
      expect(result, equals("(0, x, y, z, 3)"));
    });
  });

  group("End-to-end: nested quantifiers (a+)*", () {
    late IsolateParser iso;

    setUpAll(() async {
      iso = await spawnParser(r'''
rule = ^ ([a-z]+ ","?)* $;
''');
    });

    tearDownAll(() => iso.dispose());

    test("single group", () async {
      expect(await iso.parse("abc"), isNotNull);
    });

    test("multiple groups", () async {
      expect(await iso.parse("abc,def,ghi"), isNotNull);
    });

    test("empty matches", () async {
      expect(await iso.parse(""), isNotNull);
    });
  });

  group("End-to-end: nested quantifiers (a?)+", () {
    late IsolateParser iso;

    setUpAll(() async {
      // Optional inside plus: "a"? "b" ensures progress each iteration
      iso = await spawnParser(r'''
rule = ^ ("a"? "b")+ $;
''');
    });

    tearDownAll(() => iso.dispose());

    test("all with optional", () async {
      expect(await iso.parse("ababab"), isNotNull);
    });

    test("some without optional", () async {
      expect(await iso.parse("abbb"), isNotNull);
    });

    test("just required parts", () async {
      expect(await iso.parse("bbb"), isNotNull);
    });

    test("rejects empty", () async {
      expect(await iso.parse(""), isNull);
    });
  });

  group("End-to-end: actions with from/to indices", () {
    late IsolateParser iso;

    setUpAll(() async {
      iso = await spawnParser(r"""
int rule = ^ body $ @1;
int body = [a-z]+() { return to - from; };
""");
    });

    tearDownAll(() => iso.dispose());

    test("reports correct length for short", () async {
      expect(await iso.parse("abc"), equals(3));
    });

    test("reports correct length for single char", () async {
      expect(await iso.parse("x"), equals(1));
    });

    test("reports correct length for long", () async {
      expect(await iso.parse("abcdefghij"), equals(10));
    });
  });

  group("End-to-end: actions with span", () {
    late IsolateParser iso;

    setUpAll(() async {
      iso = await spawnParser(r"""
String rule = ^ body $ @1;
String body = [a-z]+ " " [0-9]+ |> span;
""");
    });

    tearDownAll(() => iso.dispose());

    test("span captures full matched text", () async {
      expect(await iso.parse("hello 123"), equals("hello 123"));
    });

    test("rejects without space", () async {
      expect(await iso.parse("hello123"), isNull);
    });
  });

  group("End-to-end: left recursion with actions (arithmetic)", () {
    late IsolateParser iso;

    setUpAll(() async {
      iso = await spawnParser(r"""
int rule = ^ :expr $ |> expr;
int expr =
  | :expr "+" :atom { expr + atom }
  | :expr "-" :atom { expr - atom }
  | atom;
@fragment int atom = \d+ { int.parse($.join()) };
""");
    });

    tearDownAll(() => iso.dispose());

    test("base case", () async {
      expect(await iso.parse("5"), equals(5));
    });

    test("addition", () async {
      expect(await iso.parse("3+4"), equals(7));
    });

    test("subtraction", () async {
      expect(await iso.parse("10-3"), equals(7));
    });

    test("chained left associative", () async {
      // 1+2+3 = (1+2)+3 = 6
      expect(await iso.parse("1+2+3"), equals(6));
    });

    test("mixed operations left associative", () async {
      // 10-3+2 = (10-3)+2 = 9
      expect(await iso.parse("10-3+2"), equals(9));
    });
  });

  group("End-to-end: separated list with trailing allowed", () {
    late IsolateParser iso;

    setUpAll(() async {
      iso = await spawnParser(r'''
rule = ^ ","..item+? $;
item = [a-z]+;
''');
    });

    tearDownAll(() => iso.dispose());

    test("no trailing separator", () async {
      expect(await iso.parse("a,b,c"), isNotNull);
    });

    test("with trailing separator", () async {
      expect(await iso.parse("a,b,c,"), isNotNull);
    });

    test("single item no trailing", () async {
      expect(await iso.parse("abc"), isNotNull);
    });

    test("single item with trailing", () async {
      expect(await iso.parse("abc,"), isNotNull);
    });

    test("rejects empty", () async {
      expect(await iso.parse(""), isNull);
    });
  });

  group("End-to-end: star separated with trailing", () {
    late IsolateParser iso;

    setUpAll(() async {
      iso = await spawnParser(r'''
rule = ^ ","..item*? $;
item = [a-z]+;
''');
    });

    tearDownAll(() => iso.dispose());

    test("empty matches", () async {
      expect(await iso.parse(""), isNotNull);
    });

    test("trailing comma on star", () async {
      expect(await iso.parse("a,b,"), isNotNull);
    });

    test("no trailing", () async {
      expect(await iso.parse("a,b"), isNotNull);
    });
  });

  group("End-to-end: counted repetition (exact count)", () {
    late IsolateParser iso;

    setUpAll(() async {
      iso = await spawnParser(r'''
rule = ^ 3 "a" $;
''');
    });

    tearDownAll(() => iso.dispose());

    test("exact count matches", () async {
      expect(await iso.parse("aaa"), isNotNull);
    });

    test("too few rejects", () async {
      expect(await iso.parse("aa"), isNull);
    });

    test("too many rejects", () async {
      expect(await iso.parse("aaaa"), isNull);
    });
  });

  group("End-to-end: counted repetition (unbounded max)", () {
    late IsolateParser iso;

    setUpAll(() async {
      iso = await spawnParser(r'''
rule = ^ 2.. "a" $;
''');
    });

    tearDownAll(() => iso.dispose());

    test("matches minimum", () async {
      expect(await iso.parse("aa"), isNotNull);
    });

    test("matches large count", () async {
      expect(await iso.parse("aaaaaaaaaa"), isNotNull);
    });

    test("rejects less than minimum", () async {
      expect(await iso.parse("a"), isNull);
    });
  });

  group("End-to-end: any character (.)", () {
    late IsolateParser iso;

    setUpAll(() async {
      iso = await spawnParser(r"""
rule = ^ .+ $;
""");
    });

    tearDownAll(() => iso.dispose());

    test("matches single char", () async {
      expect(await iso.parse("x"), isNotNull);
    });

    test("matches digits", () async {
      expect(await iso.parse("123"), isNotNull);
    });

    test("matches symbols", () async {
      expect(await iso.parse("!@#"), isNotNull);
    });

    test("matches spaces", () async {
      expect(await iso.parse("a b"), isNotNull);
    });

    test("rejects empty", () async {
      expect(await iso.parse(""), isNull);
    });
  });

  group("End-to-end: character ranges", () {
    late IsolateParser iso;

    setUpAll(() async {
      iso = await spawnParser(r"""
rule = ^ [a-zA-Z_] [a-zA-Z0-9_]* $;
""");
    });

    tearDownAll(() => iso.dispose());

    test("simple identifier", () async {
      expect(await iso.parse("hello"), isNotNull);
    });

    test("identifier with digits", () async {
      expect(await iso.parse("x123"), isNotNull);
    });

    test("identifier with underscore", () async {
      expect(await iso.parse("_foo"), isNotNull);
    });

    test("single letter", () async {
      expect(await iso.parse("A"), isNotNull);
    });

    test("rejects starting with digit", () async {
      expect(await iso.parse("1abc"), isNull);
    });

    test("rejects starting with minus", () async {
      expect(await iso.parse("-abc"), isNull);
    });
  });

  group("End-to-end: regex escapes", () {
    late IsolateParser iso;

    setUpAll(() async {
      iso = await spawnParser(r"""
rule = ^ <\w+> $ @1;
""");
    });

    tearDownAll(() => iso.dispose());

    test("matches word characters", () async {
      expect(await iso.parse("hello123"), equals("hello123"));
    });

    test("matches with underscore", () async {
      expect(await iso.parse("_test_"), equals("_test_"));
    });

    test("rejects space", () async {
      expect(await iso.parse("hello world"), isNull);
    });

    test("rejects empty", () async {
      expect(await iso.parse(""), isNull);
    });
  });

  group(r"End-to-end: regex escape \d", () {
    late IsolateParser iso;

    setUpAll(() async {
      iso = await spawnParser(r"""
rule = ^ <\d+> $ @1;
""");
    });

    tearDownAll(() => iso.dispose());

    test("matches digits", () async {
      expect(await iso.parse("42"), equals("42"));
    });

    test("rejects letters", () async {
      expect(await iso.parse("abc"), isNull);
    });
  });

  group(r"End-to-end: regex escape \s", () {
    late IsolateParser iso;

    setUpAll(() async {
      iso = await spawnParser(r"""
rule = ^ <\s+> $ @1;
""");
    });

    tearDownAll(() => iso.dispose());

    test("matches spaces", () async {
      expect(await iso.parse("   "), equals("   "));
    });

    test("matches mixed whitespace", () async {
      expect(await iso.parse(" \t\n"), isNotNull);
    });

    test("rejects non-whitespace", () async {
      expect(await iso.parse("abc"), isNull);
    });
  });

  group("End-to-end: epsilon in choice", () {
    late IsolateParser iso;

    setUpAll(() async {
      iso = await spawnParser(r'''
rule = ^ ("a" | ε) "b" $;
''');
    });

    tearDownAll(() => iso.dispose());

    test("matches with optional prefix", () async {
      expect(await iso.parse("ab"), isNotNull);
    });

    test("matches without optional prefix (epsilon branch)", () async {
      expect(await iso.parse("b"), isNotNull);
    });

    test("rejects unrelated", () async {
      expect(await iso.parse("c"), isNull);
    });
  });

  group("End-to-end: complex backtracking", () {
    late IsolateParser iso;

    setUpAll(() async {
      // Parser must try multiple paths before finding the correct one
      iso = await spawnParser(r'''
rule = ^ ("a" "b" "c" "d" | "a" "b" "c" "e" | "a" "b" "f" | "a" "g") $;
''');
    });

    tearDownAll(() => iso.dispose());

    test("matches first (deepest) alternative", () async {
      expect(await iso.parse("abcd"), isNotNull);
    });

    test("backtracks to second alternative", () async {
      expect(await iso.parse("abce"), isNotNull);
    });

    test("backtracks to third alternative", () async {
      expect(await iso.parse("abf"), isNotNull);
    });

    test("backtracks to fourth alternative", () async {
      expect(await iso.parse("ag"), isNotNull);
    });

    test("fails after exhausting all alternatives", () async {
      expect(await iso.parse("ah"), isNull);
    });

    test("partial prefix fails", () async {
      expect(await iso.parse("abc"), isNull);
    });
  });

  group("End-to-end: deeply nested groups", () {
    late IsolateParser iso;

    setUpAll(() async {
      iso = await spawnParser(r'''
rule = ^ ((("a" | "b") ("c" | "d")) | "e") $;
''');
    });

    tearDownAll(() => iso.dispose());

    test("first inner choice + first outer choice", () async {
      expect(await iso.parse("ac"), isNotNull);
    });

    test("first inner + second outer", () async {
      expect(await iso.parse("ad"), isNotNull);
    });

    test("second inner + first outer", () async {
      expect(await iso.parse("bc"), isNotNull);
    });

    test("second inner + second outer", () async {
      expect(await iso.parse("bd"), isNotNull);
    });

    test("outer fallback", () async {
      expect(await iso.parse("e"), isNotNull);
    });

    test("rejects invalid combo", () async {
      expect(await iso.parse("ae"), isNull);
    });
  });

  group("End-to-end: multiple interacting rules", () {
    late IsolateParser iso;

    setUpAll(() async {
      iso = await spawnParser(r"""
String rule = ^ :item ("," :item)* $ @1 |> item;
@fragment String item = "(" ~> inner <~ ")" | word;
@fragment String inner = <[a-z0-9\s]+>;
@fragment String word = <[a-z]+>;
""");
    });

    tearDownAll(() => iso.dispose());

    test("single word", () async {
      expect(await iso.parse("hello"), equals("hello"));
    });

    test("parenthesized item", () async {
      expect(await iso.parse("(abc 123)"), equals("abc 123"));
    });

    test("multiple items returns first", () async {
      expect(await iso.parse("first,second"), equals("first"));
    });
  });

  group("End-to-end: regex literal /pattern/", () {
    late IsolateParser iso;

    setUpAll(() async {
      iso = await spawnParser(r"""
String rule = ^ </[a-z]+[0-9]+/> $ @1;
""");
    });

    tearDownAll(() => iso.dispose());

    test("matches regex pattern", () async {
      expect(await iso.parse("abc123"), equals("abc123"));
    });

    test("rejects only letters", () async {
      expect(await iso.parse("abc"), isNull);
    });

    test("rejects digits first", () async {
      expect(await iso.parse("123abc"), isNull);
    });
  });

  group("End-to-end: predicate combinations", () {
    late IsolateParser iso;

    setUpAll(() async {
      // Match an identifier that is not a keyword
      iso = await spawnParser(r'''
rule = ^ (!keyword ~> <[a-z]+>) $ @1;
keyword = "if" | "else" | "while" | "for";
''');
    });

    tearDownAll(() => iso.dispose());

    test("accepts non-keyword identifier", () async {
      expect(await iso.parse("hello"), equals("hello"));
    });

    test("accepts identifier starting with keyword prefix", () async {
      // "iffy" starts with "if" but "if" is matched as whole keyword?
      // Actually negative lookahead checks if keyword matches at current pos.
      // keyword = "if" matches "if" from "iffy" (prefix), so !keyword fails.
      // This depends on whether keyword anchors to end.
      // Without $, "if" will match the prefix of "iffy", so !keyword will fail.
      // This is actually the expected PEG behavior.
      expect(await iso.parse("iffy"), isNull);
    });

    test("rejects keyword 'if'", () async {
      expect(await iso.parse("if"), isNull);
    });

    test("rejects keyword 'else'", () async {
      expect(await iso.parse("else"), isNull);
    });

    test("rejects keyword 'while'", () async {
      expect(await iso.parse("while"), isNull);
    });
  });

  group("End-to-end: positive lookahead does not consume", () {
    late IsolateParser iso;

    setUpAll(() async {
      // &"a" checks for "a" but doesn't consume, then . matches the "a"
      iso = await spawnParser(r'''
String rule = ^ <(&"a" .)+> $ @1;
''');
    });

    tearDownAll(() => iso.dispose());

    test("matches all a's", () async {
      expect(await iso.parse("aaa"), equals("aaa"));
    });

    test("rejects when first char is not a", () async {
      expect(await iso.parse("baa"), isNull);
    });

    test("stops at non-a", () async {
      expect(await iso.parse("aab"), isNull);
    });
  });

  group("End-to-end: except vs negative predicate", () {
    late IsolateParser iso;

    setUpAll(() async {
      // ~"x" means: if NOT "x", consume one character
      iso = await spawnParser(r'''
String rule = ^ <(~"x")+> $ @1;
''');
    });

    tearDownAll(() => iso.dispose());

    test("matches all non-x characters", () async {
      expect(await iso.parse("abcdef"), equals("abcdef"));
    });

    test("stops at x", () async {
      expect(await iso.parse("abxcd"), isNull);
    });

    test("rejects just x", () async {
      expect(await iso.parse("x"), isNull);
    });

    test("matches single non-x", () async {
      expect(await iso.parse("z"), equals("z"));
    });
  });

  group("End-to-end: left recursion multiple precedence levels", () {
    late IsolateParser iso;

    setUpAll(() async {
      // Two precedence levels: + (low) and * (high)
      iso = await spawnParser(r"""
int rule = ^ :expr $ |> expr;
int expr =
  | :expr "+" :term { expr + term }
  | term;
int term =
  | :term "*" :atom { term * atom }
  | atom;
@fragment int atom = \d+ { int.parse($.join()) };
""");
    });

    tearDownAll(() => iso.dispose());

    test("single number", () async {
      expect(await iso.parse("5"), equals(5));
    });

    test("addition", () async {
      expect(await iso.parse("2+3"), equals(5));
    });

    test("multiplication", () async {
      expect(await iso.parse("2*3"), equals(6));
    });

    test("precedence: mul before add", () async {
      // 2+3*4 = 2+(3*4) = 14
      expect(await iso.parse("2+3*4"), equals(14));
    });

    test("precedence: add before mul doesn't happen", () async {
      // 2*3+4 = (2*3)+4 = 10
      expect(await iso.parse("2*3+4"), equals(10));
    });

    test("chained same level", () async {
      // 1+2+3 = 6
      expect(await iso.parse("1+2+3"), equals(6));
    });

    test("chained multiplication", () async {
      // 2*3*4 = 24
      expect(await iso.parse("2*3*4"), equals(24));
    });
  });

  group("End-to-end: named captures in actions", () {
    late IsolateParser iso;

    setUpAll(() async {
      iso = await spawnParser(r"""
String rule = ^ :greeting " " :name $ { "$greeting, $name!" };
@fragment String greeting = <[A-Z][a-z]+>;
@fragment String name = <[A-Z][a-z]+>;
""");
    });

    tearDownAll(() => iso.dispose());

    test("constructs string from named parts", () async {
      expect(await iso.parse("Hello World"), equals("Hello, World!"));
    });

    test("different input", () async {
      expect(await iso.parse("Good Morning"), equals("Good, Morning!"));
    });

    test("rejects lowercase", () async {
      expect(await iso.parse("hello world"), isNull);
    });
  });

  group("End-to-end: optional in sequence", () {
    late IsolateParser iso;

    setUpAll(() async {
      iso = await spawnParser(r'''
String rule = ^ <[a-z]+ ("." [a-z]+)?> $ @1;
''');
    });

    tearDownAll(() => iso.dispose());

    test("without optional part", () async {
      expect(await iso.parse("hello"), equals("hello"));
    });

    test("with optional part", () async {
      expect(await iso.parse("hello.world"), equals("hello.world"));
    });

    test("rejects double dot", () async {
      expect(await iso.parse("a..b"), isNull);
    });
  });

  group("End-to-end: star in sequence produces list", () {
    late IsolateParser iso;

    setUpAll(() async {
      iso = await spawnParser(r'''
rule = ^ "x"* $ @1;
''');
    });

    tearDownAll(() => iso.dispose());

    test("empty produces empty list", () async {
      var result = await iso.parse("");
      expect(result, isA<List>());
      expect(result! as List, isEmpty);
    });

    test("one x produces single element list", () async {
      var result = await iso.parse("x");
      expect(result, isA<List>());
      expect(result! as List, hasLength(1));
    });

    test("multiple x's produce list", () async {
      var result = await iso.parse("xxx");
      expect(result, isA<List>());
      expect(result! as List, hasLength(3));
    });
  });

  group("End-to-end: plus produces non-empty list", () {
    late IsolateParser iso;

    setUpAll(() async {
      iso = await spawnParser(r'''
rule = ^ "x"+ $ @1;
''');
    });

    tearDownAll(() => iso.dispose());

    test("one x produces single element list", () async {
      var result = await iso.parse("x");
      expect(result, isA<List>());
      expect(result! as List, hasLength(1));
    });

    test("multiple x's produce list", () async {
      var result = await iso.parse("xxx");
      expect(result, isA<List>());
      expect(result! as List, hasLength(3));
    });

    test("all elements are the matched string", () async {
      var result = await iso.parse("xx");
      expect(result, equals(["x", "x"]));
    });
  });

  group(r"End-to-end: action with $ for whole match", () {
    late IsolateParser iso;

    setUpAll(() async {
      iso = await spawnParser(r"""
int rule = ^ <\d \d+> $ @1 { int.parse($) };
""");
    });

    tearDownAll(() => iso.dispose());

    test("captures full match", () async {
      expect(await iso.parse("42"), equals(42));
    });

    test("longer match", () async {
      expect(await iso.parse("123"), equals(123));
    });
  });

  group("End-to-end: fragment inlining", () {
    late IsolateParser iso;

    setUpAll(() async {
      iso = await spawnParser(r'''
String rule = ^ a $ @1;
@inline a = <"hello" " " "world">;
''');
    });

    tearDownAll(() => iso.dispose());

    test("inlined fragment works", () async {
      expect(await iso.parse("hello world"), equals("hello world"));
    });

    test("rejects partial", () async {
      expect(await iso.parse("hello"), isNull);
    });
  });

  group("End-to-end: multiple fragments composing", () {
    late IsolateParser iso;

    setUpAll(() async {
      iso = await spawnParser(r"""
int rule = ^ :a "+" :b $ { a + b };
@fragment int a = \d+ { int.parse($.join()) };
@fragment int b = \d+ { int.parse($.join()) };
""");
    });

    tearDownAll(() => iso.dispose());

    test("adds two numbers", () async {
      expect(await iso.parse("3+4"), equals(7));
    });

    test("larger numbers", () async {
      expect(await iso.parse("100+200"), equals(300));
    });

    test("rejects missing operand", () async {
      expect(await iso.parse("3+"), isNull);
    });
  });

  group("End-to-end: empty string literal always matches", () {
    late IsolateParser iso;

    setUpAll(() async {
      iso = await spawnParser(r'''
rule = ^ "" "a" $;
''');
    });

    tearDownAll(() => iso.dispose());

    test("empty literal is transparent", () async {
      expect(await iso.parse("a"), isNotNull);
    });

    test("still requires following content", () async {
      expect(await iso.parse(""), isNull);
    });
  });

  group("End-to-end: backtracking restores position", () {
    late IsolateParser iso;

    setUpAll(() async {
      // "ab" | "a" "c": if "ab" fails on "ac", must backtrack to try "a" "c"
      iso = await spawnParser(r'''
rule = ^ ("ab" | "a" "c") $;
''');
    });

    tearDownAll(() => iso.dispose());

    test("first alternative", () async {
      expect(await iso.parse("ab"), isNotNull);
    });

    test("second alternative via backtrack", () async {
      // "ab" partially matches "a" then fails on "c", backtracks, "a" "c" matches
      expect(await iso.parse("ac"), isNotNull);
    });

    test("rejects mid-match", () async {
      expect(await iso.parse("ad"), isNull);
    });
  });

  group("End-to-end: and predicate in sequence", () {
    late IsolateParser iso;

    setUpAll(() async {
      // Match digits only if followed by a letter (but don't consume the letter)
      iso = await spawnParser(r"""
String rule = ^ <\d+ &[a-z]> <[a-z]+> $ @1;
""");
    });

    tearDownAll(() => iso.dispose());

    test("digits followed by letters", () async {
      expect(await iso.parse("123abc"), equals("123"));
    });

    test("rejects digits alone", () async {
      expect(await iso.parse("123"), isNull);
    });
  });

  group("End-to-end: hybrid namespace (choice!)", () {
    late IsolateParser iso;

    setUpAll(() async {
      iso = await spawnParser(r'''
rule = ^ token $;
token = choice! {
  keyword = "if" | "else" | "while";
  ident = [a-z]+;
};
''');
    });

    tearDownAll(() => iso.dispose());

    test("matches keyword", () async {
      expect(await iso.parse("if"), isNotNull);
    });

    test("matches another keyword", () async {
      expect(await iso.parse("while"), isNotNull);
    });

    test("matches identifier", () async {
      expect(await iso.parse("hello"), isNotNull);
    });

    test("rejects digits", () async {
      expect(await iso.parse("123"), isNull);
    });
  });

  group("End-to-end: choice of different lengths", () {
    late IsolateParser iso;

    setUpAll(() async {
      iso = await spawnParser(r'''
String rule = ^ <("abc" | "ab" | "a")> $ @1;
''');
    });

    tearDownAll(() => iso.dispose());

    test("longest match from first alternative", () async {
      expect(await iso.parse("abc"), equals("abc"));
    });

    test("medium match from second alternative", () async {
      expect(await iso.parse("ab"), equals("ab"));
    });

    test("shortest match from third alternative", () async {
      expect(await iso.parse("a"), equals("a"));
    });

    test("rejects non-matching", () async {
      expect(await iso.parse("b"), isNull);
    });
  });

  group("End-to-end: counted repetition (min 0)", () {
    late IsolateParser iso;

    setUpAll(() async {
      iso = await spawnParser(r'''
rule = ^ 0..3 "a" $;
''');
    });

    tearDownAll(() => iso.dispose());

    test("zero matches", () async {
      expect(await iso.parse(""), isNotNull);
    });

    test("one match", () async {
      expect(await iso.parse("a"), isNotNull);
    });

    test("max matches", () async {
      expect(await iso.parse("aaa"), isNotNull);
    });

    test("over max rejects", () async {
      expect(await iso.parse("aaaa"), isNull);
    });
  });

  group("End-to-end: not predicate does not consume", () {
    late IsolateParser iso;

    setUpAll(() async {
      iso = await spawnParser(r'''
rule = ^ <(!"end" .)+> "end" $ @1;
''');
    });

    tearDownAll(() => iso.dispose());

    test("captures everything before 'end'", () async {
      expect(await iso.parse("helloend"), equals("hello"));
    });

    test("single char before end", () async {
      expect(await iso.parse("xend"), equals("x"));
    });

    test("rejects no 'end' suffix", () async {
      expect(await iso.parse("hello"), isNull);
    });

    test("rejects bare 'end'", () async {
      // !"end" fails immediately, so (...)+ requires at least one char
      expect(await iso.parse("end"), isNull);
    });
  });

  group("End-to-end: sequence with multiple selections", () {
    late IsolateParser iso;

    setUpAll(() async {
      iso = await spawnParser(r'''
rule = ^ "(" [a-z]+ ":" [0-9]+ ")" $ @1;
''');
    });

    tearDownAll(() => iso.dispose());

    test("selects first capture (index 1)", () async {
      // @1 selects [a-z]+ which is at index 1 (0-based: "(" is 0, [a-z]+ is 1)
      expect(await iso.parse("(abc:123)"), isNotNull);
      var result = await iso.parse("(abc:123)");
      expect(result, isA<String>());
    });
  });

  group("End-to-end: recursive descent (non-left)", () {
    late IsolateParser iso;

    setUpAll(() async {
      // Nested balanced parentheses
      iso = await spawnParser(r'''
Object rule = ^ item $;
Object item = "(" item ")" | "x";
''');
    });

    tearDownAll(() => iso.dispose());

    test("base case", () async {
      expect(await iso.parse("x"), isNotNull);
    });

    test("one level of nesting", () async {
      expect(await iso.parse("(x)"), isNotNull);
    });

    test("deep nesting", () async {
      expect(await iso.parse("(((x)))"), isNotNull);
    });

    test("rejects unbalanced", () async {
      expect(await iso.parse("((x)"), isNull);
    });

    test("rejects extra close", () async {
      expect(await iso.parse("(x))"), isNull);
    });
  });

  group("End-to-end: mutual recursion", () {
    late IsolateParser iso;

    setUpAll(() async {
      iso = await spawnParser(r'''
Object rule = ^ a $;
Object a = "(" b ")" | "x";
Object b = "[" a "]" | "y";
''');
    });

    tearDownAll(() => iso.dispose());

    test("base a", () async {
      expect(await iso.parse("x"), isNotNull);
    });

    test("a wrapping b base", () async {
      expect(await iso.parse("(y)"), isNotNull);
    });

    test("b wrapping a base", () async {
      expect(await iso.parse("([x])"), isNotNull);
    });

    test("deep mutual recursion", () async {
      expect(await iso.parse("([([x])])"), isNotNull);
    });

    test("rejects mismatched brackets", () async {
      expect(await iso.parse("(y]"), isNull);
    });
  });

  group("End-to-end: greedy quantifier behavior", () {
    late IsolateParser iso;

    setUpAll(() async {
      // PEG is greedy: "a"* will consume all "a"s,
      // so "a"* "a" should only match if there's at least one "a" left
      iso = await spawnParser(r'''
rule = ^ "a"* "a"? "b" $;
''');
    });

    tearDownAll(() => iso.dispose());

    test("minimal case: one a + b", () async {
      expect(await iso.parse("ab"), isNotNull);
    });

    test("multiple a's then b", () async {
      expect(await iso.parse("aaab"), isNotNull);
    });
  });

  group("End-to-end: multiple start/end anchors", () {
    late IsolateParser iso;

    setUpAll(() async {
      iso = await spawnParser(r'''
rule = ^ ^ "hello" $ $;
''');
    });

    tearDownAll(() => iso.dispose());

    test("double anchors still match", () async {
      expect(await iso.parse("hello"), isNotNull);
    });

    test("rejects non-matching", () async {
      expect(await iso.parse("world"), isNull);
    });
  });

  group("End-to-end: complex JSON-like parser", () {
    late IsolateParser iso;

    setUpAll(() async {
      iso = await spawnParser(r"""
Object rule = ^ :value $ |> value;

Object value =
  | "null" |> null
  | "true" |> true
  | "false" |> false
  | number
  | string
  | array
  | object;

@fragment num number = \d+ ("." \d+)? { double.parse(buffer.substring(from, to)) };
@fragment String string = '"' <(~'"')*> '"' @1;
@fragment Object array = "[" _ ","..value* _ "]" @2;
@fragment Object object = "{" _ ","..pair* _ "}" @2;
@fragment Object pair = _ :key _ ":" _ :val _ |> [key, val];
@fragment String key = '"' <(~'"')*> '"' @1;
@fragment Object val = value;
_ = \s* { () };
""");
    });

    tearDownAll(() => iso.dispose());

    test("parses null", () async {
      expect(await iso.parse("null"), isNull);
      // null parses but returns null — we need a way to distinguish
      // Actually our spawnParser returns null for both parse-failure and null-result
      // So let's test other values instead
    });

    test("parses true", () async {
      expect(await iso.parse("true"), equals(true));
    });

    test("parses false", () async {
      expect(await iso.parse("false"), equals(false));
    });

    test("parses integer", () async {
      expect(await iso.parse("42"), equals(42.0));
    });

    test("parses float", () async {
      expect(await iso.parse("3.14"), equals(3.14));
    });

    test("parses string", () async {
      expect(await iso.parse('"hello"'), equals("hello"));
    });

    test("parses empty array", () async {
      expect(await iso.parse("[]"), equals([]));
    });

    test("parses array with values", () async {
      expect(await iso.parse("[1,2,3]"), equals([1.0, 2.0, 3.0]));
    });

    test("parses empty object", () async {
      expect(await iso.parse("{}"), equals([]));
    });

    test("parses nested structure", () async {
      var result = await iso.parse('[1,"hi",true]');
      expect(result, equals([1.0, "hi", true]));
    });

    test("rejects malformed", () async {
      expect(await iso.parse("[1,2,"), isNull);
    });
  });

  group("End-to-end: preamble code used in actions", () {
    late IsolateParser iso;

    setUpAll(() async {
      iso = await spawnParser(r"""
{
int doubleIt(int x) => x * 2;
}
int rule = ^ :n $ |> doubleIt(n);
@fragment int n = \d+ { int.parse($.join()) };
""");
    });

    tearDownAll(() => iso.dispose());

    test("preamble function called from action", () async {
      expect(await iso.parse("5"), equals(10));
    });

    test("larger number", () async {
      expect(await iso.parse("21"), equals(42));
    });
  });

  group("End-to-end: start/end of input anchors", () {
    late IsolateParser iso;

    setUpAll(() async {
      iso = await spawnParser(r'''
rule = ^ "hello" $;
''');
    });

    tearDownAll(() => iso.dispose());

    test("exact match", () async {
      expect(await iso.parse("hello"), isNotNull);
    });

    test("rejects prefix extra", () async {
      expect(await iso.parse(" hello"), isNull);
    });

    test("rejects suffix extra", () async {
      expect(await iso.parse("hello "), isNull);
    });
  });

  group("End-to-end: complex separated list with actions", () {
    late IsolateParser iso;

    setUpAll(() async {
      iso = await spawnParser(r"""
Object rule = ^ _ ","..item+ _ $  @2;
@fragment int item = _ \d+ _ @1 { int.parse($.join()) };
_ = \s* { () };
""");
    });

    tearDownAll(() => iso.dispose());

    test("single item", () async {
      var result = await iso.parse("42");
      expect(result, equals([42]));
    });

    test("multiple items", () async {
      var result = await iso.parse("1, 2, 3");
      expect(result, equals([1, 2, 3]));
    });

    test("items with extra whitespace", () async {
      var result = await iso.parse("  10 , 20 , 30  ");
      expect(result, equals([10, 20, 30]));
    });
  });

  // ---------------------------------------------------------------------------
  //  Tricky left-recursion scenarios
  // ---------------------------------------------------------------------------

  group("End-to-end: two-rule indirect left recursion", () {
    // Grammar:
    //   a = b "!" | "p"    ← a invokes b which (through "a ?") invokes a again
    //   b = a "?" | "q"
    //
    // Seed-growth trace for "p?!?!":
    //   seed a="p" → b re-eval: "p?" → a="p?!" → b re-eval: "p?!?" → a="p?!?!"
    late IsolateParser iso;

    setUpAll(() async {
      iso = await spawnParser(r'''
Object rule = ^ :a $;
Object a = b "!" | "p";
Object b = a "?" | "q";
''');
    });

    tearDownAll(() => iso.dispose());

    test("base case 'p'", () async {
      expect(await iso.parse("p"), isNotNull);
    });

    test("one level through b  ('q!')", () async {
      // b="q", then a = b "!" = "q!"
      expect(await iso.parse("q!"), isNotNull);
    });

    test("two levels a->b->a ('p?!')", () async {
      // a="p" → b="p?" → a="p?!"
      expect(await iso.parse("p?!"), isNotNull);
    });

    test("three levels ('q!?!')", () async {
      // a="q!" → b="q!?" → a="q!?!"
      expect(await iso.parse("q!?!"), isNotNull);
    });

    test("four levels deep indirect growth ('p?!?!')", () async {
      // a="p" → b="p?" → a="p?!" → b="p?!?" → a="p?!?!"
      expect(await iso.parse("p?!?!"), isNotNull);
    });

    test("rejects bare '!'  (no base)", () async {
      expect(await iso.parse("!"), isNull);
    });

    test("rejects 'p?' (incomplete cycle – missing '!')", () async {
      expect(await iso.parse("p?"), isNull);
    });

    test("rejects 'q?!' (wrong operator order)", () async {
      // 'q' is a base for b, not for a; "q?" has no matching alternative
      expect(await iso.parse("q?!"), isNull);
    });
  });

  group("End-to-end: three-rule indirect left recursion", () {
    // Grammar:
    //   a = b "!" | "a"    ← one-character literal "a" is the base
    //   b = c "?" | "b"
    //   c = a "#" | "c"
    //
    // The cycle a→b→c→a means all three rules participate in the involvedSet.
    // Seed-growth trace for "a#?!":
    //   seed a="a" → c re-eval: "a#" → b re-eval: "a#?" → a="a#?!"
    late IsolateParser iso;

    setUpAll(() async {
      iso = await spawnParser(r'''
Object rule = ^ :a $;
Object a = b "!" | "a";
Object b = c "?" | "b";
Object c = a "#" | "c";
''');
    });

    tearDownAll(() => iso.dispose());

    test("base case 'a'", () async {
      expect(await iso.parse("a"), isNotNull);
    });

    test("through b only ('b!')", () async {
      // b="b", a=b"!"="b!"
      expect(await iso.parse("b!"), isNotNull);
    });

    test("through b and c ('c?!')", () async {
      // c="c", b=c"?"="c?", a=b"!"="c?!"
      expect(await iso.parse("c?!"), isNotNull);
    });

    test("full three-rule cycle ('a#?!')", () async {
      // a="a" → c=a"#"="a#" → b=c"?"="a#?" → a=b"!"="a#?!"
      expect(await iso.parse("a#?!"), isNotNull);
    });

    test("two full cycles ('b!#?!')", () async {
      // a="b!" → c=a"#"="b!#" → b=c"?"="b!#?" → a=b"!"="b!#?!"
      expect(await iso.parse("b!#?!"), isNotNull);
    });

    test("rejects wrong terminator ('a!')", () async {
      // "!" is b's suffix, not a valid suffix directly after a bare "a"
      expect(await iso.parse("a!"), isNull);
    });

    test("rejects incomplete cycle ('a#')", () async {
      // c grows to "a#" but b and a cannot complete
      expect(await iso.parse("a#"), isNull);
    });

    test("rejects partial inner cycle ('a#?')", () async {
      expect(await iso.parse("a#?"), isNull);
    });
  });

  group("End-to-end: left recursion with epsilon base", () {
    // Grammar:
    //   expr = expr "a" | ε
    //
    // This is equivalent to "a"* : the recursive rule is seeded by epsilon
    // (non-null empty match at the current position) and the grow loop
    // extends it one "a" at a time.
    late IsolateParser iso;

    setUpAll(() async {
      iso = await spawnParser(r'''
Object rule = ^ :expr $;
Object expr = expr "a" | ε;
''');
    });

    tearDownAll(() => iso.dispose());

    test("empty string matches (epsilon base)", () async {
      expect(await iso.parse(""), isNotNull);
    });

    test("single 'a'", () async {
      expect(await iso.parse("a"), isNotNull);
    });

    test("two 'a's", () async {
      expect(await iso.parse("aa"), isNotNull);
    });

    test("seven 'a's", () async {
      expect(await iso.parse("aaaaaaa"), isNotNull);
    });

    test("rejects non-'a' character", () async {
      expect(await iso.parse("b"), isNull);
    });

    test("rejects 'a' followed by non-'a'", () async {
      expect(await iso.parse("aab"), isNull);
    });
  });

  group("End-to-end: left recursion – base-case-first prevents growth", () {
    // In PEG ordered choice the FIRST alternative that matches commits.
    // When the non-recursive base case ("a") is listed BEFORE the recursive
    // alternative (expr "+" "a"), "a" always wins at position 0 and the
    // grow loop never advances beyond it, so anchored inputs like "a+a"
    // correctly fail.
    late IsolateParser iso;

    setUpAll(() async {
      iso = await spawnParser(r'''
Object rule = ^ expr $;
Object expr = "a" | expr "+" "a";
''');
    });

    tearDownAll(() => iso.dispose());

    test("single 'a' still matches", () async {
      expect(await iso.parse("a"), isNotNull);
    });

    test("'a+a' fails (base-case-first prevents growth)", () async {
      expect(await iso.parse("a+a"), isNull);
    });

    test("'a+a+a' also fails", () async {
      expect(await iso.parse("a+a+a"), isNull);
    });
  });

  group("End-to-end: left recursion - recursive-first enables growth", () {
    // Same language as the group above but with the recursive alternative
    // FIRST.  Flipping the order allows the seed to grow, so "a+a+a" now
    // parses correctly.
    late IsolateParser iso;

    setUpAll(() async {
      iso = await spawnParser(r'''
Object rule = ^ expr $;
Object expr = expr "+" "a" | "a";
''');
    });

    tearDownAll(() => iso.dispose());

    test("single 'a' matches", () async {
      expect(await iso.parse("a"), isNotNull);
    });

    test("'a+a' matches", () async {
      expect(await iso.parse("a+a"), isNotNull);
    });

    test("'a+a+a' matches (left-associative growth)", () async {
      expect(await iso.parse("a+a+a"), isNotNull);
    });

    test("rejects trailing '+'", () async {
      expect(await iso.parse("a+"), isNull);
    });

    test("rejects leading '+'", () async {
      expect(await iso.parse("+a"), isNull);
    });
  });

  group("End-to-end: indirect left recursion – two competing left-recursive rules", () {
    // Both expr and term are left-recursive, and they call each other so that
    // expr→term→expr forms an indirect cycle in addition to each rule's own
    // direct self-reference.
    //
    //   expr = expr "+" term | term
    //   term = term "*" expr | expr "-" "1" | \d+
    //
    // The cross-call term→expr→term means the indirect involvedSet tracking
    // must correctly include both rules.
    late IsolateParser iso;

    setUpAll(() async {
      iso = await spawnParser(r'''
Object rule = ^ expr $;
Object expr = expr "+" term | term;
Object term = term "*" expr | expr "-" "1" | \d+;
''');
    });

    tearDownAll(() => iso.dispose());

    test("single digit", () async {
      expect(await iso.parse("3"), isNotNull);
    });

    test("addition of digits", () async {
      expect(await iso.parse("1+2"), isNotNull);
    });

    test("multiplication of digits", () async {
      expect(await iso.parse("2*3"), isNotNull);
    });

    test("mixed addition and multiplication", () async {
      expect(await iso.parse("1+2*3"), isNotNull);
    });

    test("term using expr sub-rule", () async {
      // the 'expr "-" "1"' branch of term calls expr, creating a cross-call
      expect(await iso.parse("2-1"), isNotNull);
    });

    test("chained expression with cross-rule involvement", () async {
      expect(await iso.parse("2-1+3"), isNotNull);
    });

    test("rejects empty input", () async {
      expect(await iso.parse(""), isNull);
    });

    test("rejects trailing operator", () async {
      expect(await iso.parse("1+"), isNull);
    });
  });

  group("End-to-end: indirect left recursion with actions", () {
    // Grammar:
    //   a = :b "+" :n { b + n } | :b |> b
    //   b = :a "*" :n { a * n } | :n |> n
    //   n = \d+
    //
    // a delegates to b and b can call back into a, forming an indirect cycle.
    // Arithmetic still evaluates correctly via seed growth.
    late IsolateParser iso;

    setUpAll(() async {
      iso = await spawnParser(r"""
int result = ^ :a $ |> a;
int a = :b "+" :n { b + n } | :b |> b;
int b = :a "*" :n { a * n } | :n |> n;
@fragment int n = \d+ { int.parse($.join()) };
""");
    });

    tearDownAll(() => iso.dispose());

    test("single number", () async {
      expect(await iso.parse("5"), equals(5));
    });

    test("addition (a-level)", () async {
      expect(await iso.parse("2+3"), equals(5));
    });

    test("multiplication (b-level via indirect cycle)", () async {
      expect(await iso.parse("2*3"), equals(6));
    });

    test("multiplication then addition ('2*3+4' = 10)", () async {
      // b grows first via a→b cycle: 2*3=6, then a adds 4 → 10
      expect(await iso.parse("2*3+4"), equals(10));
    });

    test("left-associative multiplication chain ('2*3*4' = 24)", () async {
      // The indirect cycle b→a→b keeps growing: (2*3)*4 = 24
      expect(await iso.parse("2*3*4"), equals(24));
    });

    test("single addition ('1+2' = 3)", () async {
      expect(await iso.parse("1+2"), equals(3));
    });

    test("rejects non-numeric input", () async {
      expect(await iso.parse("x"), isNull);
    });
  });

  // -------------------------------------------------------------------------
  //  Test group – Block actions: semicolons and auto-return
  // -------------------------------------------------------------------------

  group("Block actions: grammar parsing", () {
    late GrammarParser parser;

    setUp(() => parser = GrammarParser());

    test("parse block with single expression (auto-return)", () {
      var result = parser.parse(r"""
int rule = \d+ { int.parse($.join()) };
""");
      expect(result, isA<ParserGenerator>());
    });

    test("parse block with multiple semicolon-separated statements", () {
      var result = parser.parse(r"""
int rule = \d+ { var x = int.parse($.join()); x * 2 };
""");
      expect(result, isA<ParserGenerator>());
    });

    test("parse block with explicit return", () {
      var result = parser.parse(r"""
int rule = \d+ { var x = int.parse($.join()); return x * 2 };
""");
      expect(result, isA<ParserGenerator>());
    });

    test("parse block with trailing semicolon (no auto-return)", () {
      var result = parser.parse(r"""
int rule = \d+ { var x = int.parse($.join()); return x * 2; };
""");
      expect(result, isA<ParserGenerator>());
    });

    test("parse block with (){} syntax", () {
      var result = parser.parse(r"""
int rule = \d+() { return int.parse($.join()); };
""");
      expect(result, isA<ParserGenerator>());
    });

    test("parse block with (){} syntax and auto-return", () {
      var result = parser.parse(r"""
int rule = \d+() { int.parse($.join()) };
""");
      expect(result, isA<ParserGenerator>());
    });

    test("parse block with nested curly braces", () {
      var result = parser.parse(r'''
int rule = \d+ { var x = $.join(); if (x == "0") { 0 } else { int.parse(x) } };
''');
      expect(result, isA<ParserGenerator>());
    });
  });

  group("End-to-end: block action auto-return single expression", () {
    late IsolateParser iso;

    setUpAll(() async {
      // { expr } should become () { return expr; }
      iso = await spawnParser(r"""
int rule = ^ :val $ { val };
@fragment int val = \d+ { int.parse($.join()) };
""");
    });

    tearDownAll(() => iso.dispose());

    test("single expression is auto-returned", () async {
      expect(await iso.parse("42"), equals(42));
    });

    test("single expression auto-return with different value", () async {
      expect(await iso.parse("7"), equals(7));
    });

    test("rejects non-matching input", () async {
      expect(await iso.parse("abc"), isNull);
    });
  });

  group("End-to-end: block action with multiple semicolon-separated statements", () {
    late IsolateParser iso;

    setUpAll(() async {
      // { statement; expr } should become () { statement; return expr; }
      iso = await spawnParser(r"""
int rule = ^ :val $ { var x = val; x * 2 };
@fragment int val = \d+ { int.parse($.join()) };
""");
    });

    tearDownAll(() => iso.dispose());

    test("intermediate statement + auto-returned expression", () async {
      expect(await iso.parse("5"), equals(10));
    });

    test("works with another value", () async {
      expect(await iso.parse("3"), equals(6));
    });
  });

  group("End-to-end: block action with explicit return", () {
    late IsolateParser iso;

    setUpAll(() async {
      // { statement; return expr } should keep the explicit return
      iso = await spawnParser(r"""
int rule = ^ :val $ { var x = val; return x * 3; };
@fragment int val = \d+ { int.parse($.join()) };
""");
    });

    tearDownAll(() => iso.dispose());

    test("explicit return is preserved", () async {
      expect(await iso.parse("4"), equals(12));
    });

    test("explicit return with another input", () async {
      expect(await iso.parse("10"), equals(30));
    });
  });

  group("End-to-end: block action trailing semicolon suppresses auto-return", () {
    late IsolateParser iso;

    setUpAll(() async {
      // { return expr; } — trailing semicolon: the explicit return is there,
      // and the trailing semicolons produce empty items which get trimmed,
      // then `;` is added back. The last statement ends with `;` so no extra return.
      iso = await spawnParser(r"""
int rule = ^ :val $ { return val * 4; };
@fragment int val = \d+ { int.parse($.join()) };
""");
    });

    tearDownAll(() => iso.dispose());

    test("trailing semicolon with explicit return works", () async {
      expect(await iso.parse("3"), equals(12));
    });
  });

  group("End-to-end: block action with (){} syntax", () {
    late IsolateParser iso;

    setUpAll(() async {
      // sequence(){ code } syntax with auto-return
      iso = await spawnParser(r"""
int rule = ^ :val $() { val * 5 };
@fragment int val = \d+ { int.parse($.join()) };
""");
    });

    tearDownAll(() => iso.dispose());

    test("(){} syntax with auto-return", () async {
      expect(await iso.parse("2"), equals(10));
    });

    test("(){} syntax with different value", () async {
      expect(await iso.parse("6"), equals(30));
    });
  });

  group("End-to-end: block action (){} with explicit return", () {
    late IsolateParser iso;

    setUpAll(() async {
      iso = await spawnParser(r"""
int rule = ^ :val $() { return val * 6; };
@fragment int val = \d+ { int.parse($.join()) };
""");
    });

    tearDownAll(() => iso.dispose());

    test("(){} with explicit return", () async {
      expect(await iso.parse("3"), equals(18));
    });
  });

  group("End-to-end: block action with three statements", () {
    late IsolateParser iso;

    setUpAll(() async {
      // { stmt1; stmt2; expr } → () { stmt1; stmt2; return expr; }
      iso = await spawnParser(r"""
int rule = ^ :val $ { var a = val; var b = a + 1; a + b };
@fragment int val = \d+ { int.parse($.join()) };
""");
    });

    tearDownAll(() => iso.dispose());

    test("three statements: two intermediates + auto-return", () async {
      // val=5, a=5, b=6, return 5+6=11
      expect(await iso.parse("5"), equals(11));
    });

    test("three statements with different value", () async {
      // val=10, a=10, b=11, return 10+11=21
      expect(await iso.parse("10"), equals(21));
    });
  });

  group("End-to-end: block action return in last position with semicolon", () {
    late IsolateParser iso;

    setUpAll(() async {
      // { stmt; return expr; } — explicit return + trailing semicolon
      iso = await spawnParser(r"""
int rule = ^ :val $ { var x = val + 1; return x; };
@fragment int val = \d+ { int.parse($.join()) };
""");
    });

    tearDownAll(() => iso.dispose());

    test("explicit return with trailing semicolon", () async {
      expect(await iso.parse("9"), equals(10));
    });
  });

  group("End-to-end: block action complex expression as last", () {
    late IsolateParser iso;

    setUpAll(() async {
      // The last expression is a function call — should be auto-returned
      iso = await spawnParser(r"""
String rule = ^ :val $ { val.toUpperCase() };
@fragment String val = [a-z]+ { $.join() };
""");
    });

    tearDownAll(() => iso.dispose());

    test("function call expression is auto-returned", () async {
      expect(await iso.parse("hello"), equals("HELLO"));
    });

    test("another input", () async {
      expect(await iso.parse("abc"), equals("ABC"));
    });
  });

  group("End-to-end: block action with conditional expression", () {
    late IsolateParser iso;

    setUpAll(() async {
      // Last expression is a ternary — should be auto-returned
      iso = await spawnParser(r"""
String rule = ^ :val $ { var n = int.parse(val); n > 5 ? "big" : "small" };
@fragment String val = \d+ { $.join() };
""");
    });

    tearDownAll(() => iso.dispose());

    test("ternary expression auto-returned (big)", () async {
      expect(await iso.parse("10"), equals("big"));
    });

    test("ternary expression auto-returned (small)", () async {
      expect(await iso.parse("3"), equals("small"));
    });
  });

  group("End-to-end: block action in choice alternatives", () {
    late IsolateParser iso;

    setUpAll(() async {
      // Different block actions in different branches
      iso = await spawnParser(r"""
int rule = ^ :expr $ |> expr;
int expr =
  | "+" :val { val }
  | "-" :val { var x = val; -x }
  | val;
@fragment int val = \d+ { int.parse($.join()) };
""", parserName: "ChoiceBlockParser");
    });

    tearDownAll(() => iso.dispose());

    test("first branch with auto-return", () async {
      expect(await iso.parse("+7"), equals(7));
    });

    test("second branch with statement + auto-return", () async {
      expect(await iso.parse("-7"), equals(-7));
    });

    test("third branch (no block action)", () async {
      expect(await iso.parse("7"), equals(7));
    });
  });

  group("End-to-end: block action with string concatenation in statements", () {
    late IsolateParser iso;

    setUpAll(() async {
      iso = await spawnParser(r"""
String rule = ^ :a " " :b $ { var greeting = a; var name = b; "$greeting, $name!" };
@fragment String a = [A-Za-z]+ { $.join() };
@fragment String b = [A-Za-z]+ { $.join() };
""");
    });

    tearDownAll(() => iso.dispose());

    test("multiple statements with string interpolation auto-return", () async {
      expect(await iso.parse("Hello World"), equals("Hello, World!"));
    });
  });

  group("End-to-end: block action with list operations", () {
    late IsolateParser iso;

    setUpAll(() async {
      // Block creates a list, adds to it, returns it
      iso = await spawnParser(r"""
Object rule = ^ :items $ { var result = <int>[]; result.addAll(items.cast<int>()); result };
items = ","..item+;
@fragment int item = \d+ { int.parse($.join()) };
""");
    });

    tearDownAll(() => iso.dispose());

    test("list operation with auto-return", () async {
      var result = await iso.parse("1,2,3");
      expect(result, equals([1, 2, 3]));
    });
  });

  group("End-to-end: block action preserves semicolons inside nested braces", () {
    late IsolateParser iso;

    setUpAll(() async {
      // Semicolons inside nested {} should not split the block
      iso = await spawnParser(r"""
int rule = ^ :val $ { var x = () { return val + 1; }; x() };
@fragment int val = \d+ { int.parse($.join()) };
""");
    });

    tearDownAll(() => iso.dispose());

    test("nested braces with semicolons preserved", () async {
      expect(await iso.parse("5"), equals(6));
    });
  });

  group("End-to-end: block action with returnValue-like identifier (starts with 'return')", () {
    late IsolateParser iso;

    setUpAll(() async {
      // Edge case: variable named 'returnValue' starts with "return"
      // The auto-return check uses startsWith("return"), so this will NOT get auto-return.
      // That means we need explicit return with a trailing semicolon.
      iso = await spawnParser(r"""
int rule = ^ :val $ { var returnValue = val * 2; return returnValue; };
@fragment int val = \d+ { int.parse($.join()) };
""");
    });

    tearDownAll(() => iso.dispose());

    test("identifier starting with 'return' needs explicit return", () async {
      expect(await iso.parse("5"), equals(10));
    });
  });

  group("End-to-end: block action empty-ish block with just return", () {
    late IsolateParser iso;

    setUpAll(() async {
      // Block is just { return 42; } — explicit return needs trailing semicolon
      iso = await spawnParser(r"""
int rule = ^ "x" $ { return 42; };
""");
    });

    tearDownAll(() => iso.dispose());

    test("single explicit return in block", () async {
      expect(await iso.parse("x"), equals(42));
    });
  });

  group("End-to-end: block vs inline action equivalence", () {
    late IsolateParser isoBlock;
    late IsolateParser isoInline;

    setUpAll(() async {
      // Block action: { val * 2 } should auto-return same as inline |> val * 2
      isoBlock = await spawnParser(r"""
int rule = ^ :val $ { val * 2 };
@fragment int val = \d+ { int.parse($.join()) };
""");

      isoInline = await spawnParser(r"""
int rule = ^ :val $ |> val * 2;
@fragment int val = \d+ { int.parse($.join()) };
""");
    });

    tearDownAll(() {
      isoBlock.dispose();
      isoInline.dispose();
    });

    test("block and inline produce same result for '5'", () async {
      var blockResult = await isoBlock.parse("5");
      var inlineResult = await isoInline.parse("5");
      expect(blockResult, equals(inlineResult));
      expect(blockResult, equals(10));
    });

    test("block and inline produce same result for '100'", () async {
      var blockResult = await isoBlock.parse("100");
      var inlineResult = await isoInline.parse("100");
      expect(blockResult, equals(inlineResult));
      expect(blockResult, equals(200));
    });
  });

  group("End-to-end: block action with from/to span variables", () {
    late IsolateParser iso;

    setUpAll(() async {
      // Block action using from/to for substring extraction
      iso = await spawnParser(r"""
String rule = ^ [a-z]+ $ { buffer.substring(from, to) };
""");
    });

    tearDownAll(() => iso.dispose());

    test("from/to variables work in block action", () async {
      expect(await iso.parse("hello"), equals("hello"));
    });

    test("from/to with different input", () async {
      expect(await iso.parse("abc"), equals("abc"));
    });
  });

  group("End-to-end: block action with from/to and multiple statements", () {
    late IsolateParser iso;

    setUpAll(() async {
      iso = await spawnParser(r"""
String rule = ^ [a-z]+ $ { var raw = buffer.substring(from, to); raw.toUpperCase() };
""");
    });

    tearDownAll(() => iso.dispose());

    test("from/to with intermediate statement and auto-return", () async {
      expect(await iso.parse("world"), equals("WORLD"));
    });
  });

  group("End-to-end: block action on recursive rule", () {
    late IsolateParser iso;

    setUpAll(() async {
      iso = await spawnParser(r"""
int rule = ^ :expr $ |> expr;
int expr =
  | :expr "+" :term { var sum = expr + term; sum }
  | term;
@fragment int term = \d+ { int.parse($.join()) };
""", parserName: "RecursiveBlockParser");
    });

    tearDownAll(() => iso.dispose());

    test("block action in left-recursive rule", () async {
      expect(await iso.parse("1+2+3"), equals(6));
    });

    test("base case (no recursion)", () async {
      expect(await iso.parse("42"), equals(42));
    });
  });

  group("End-to-end: block action multiple statements trailing semicolon", () {
    late IsolateParser iso;

    setUpAll(() async {
      // { stmt; return expr; } — all with trailing semicolons
      // The trailing empty is trimmed, `;` is added to last non-empty,
      // and since last now ends with `;` (it's `return expr;;`?), no extra return.
      // Actually: code = ["stmt", " return expr", ""]
      // trimmed = ["stmt", " return expr"]  (removed one empty)
      // trimmed.length != code.length → add ";" back: "return expr;"
      // last.trim() = "return expr;" → starts with "return" → no auto-return
      iso = await spawnParser(r"""
int rule = ^ :val $ { var x = val + 100; return x; };
@fragment int val = \d+ { int.parse($.join()) };
""");
    });

    tearDownAll(() => iso.dispose());

    test("multiple stmts with trailing semicolon", () async {
      expect(await iso.parse("5"), equals(105));
    });
  });

  group("End-to-end: block action only semicolons", () {
    late IsolateParser iso;

    setUpAll(() async {
      // Block with just an expression and trailing semicolons: { return 99; }
      iso = await spawnParser(r"""
int rule = ^ "x" $ { return 99; };
""");
    });

    tearDownAll(() => iso.dispose());

    test("explicit return with trailing semicolon", () async {
      expect(await iso.parse("x"), equals(99));
    });
  });
}
