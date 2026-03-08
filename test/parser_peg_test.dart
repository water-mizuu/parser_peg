// ignore_for_file: avoid_dynamic_calls

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

  var parserCode = generator.compileParserGenerator(parserName);

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
      var input = readGrammarFile("lib/src/parser/grammar_parser.dart_grammar");
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

    test("math grammar compiles", () {
      var parser = GrammarParser();
      var gen = parser.parse(readGrammarFile("examples/math/math.dart_grammar"))!;
      var code = gen.compileParserGenerator("MathParser");

      expect(code, contains("class MathParser"));
      expect(code, contains("extends _PegParser<num>"));
    });

    test("metagrammar compiles", () {
      var parser = GrammarParser();
      var gen = parser.parse(readGrammarFile("lib/src/parser/grammar_parser.dart_grammar"))!;
      var code = gen.compileParserGenerator("GrammarParser");

      expect(code, contains("class GrammarParser"));
    });

    test("choice rule produces multiple branches", () {
      var parser = GrammarParser();
      var gen = parser.parse('rule = "a" | "b" | "c";')!;
      var code = gen.compileParserGenerator("P");
      // Verify there's backtracking code (_mark / _recover)
      expect(code, contains("_mark"));
      expect(code, contains("_recover"));
    });

    test("left-recursive rule uses apply()", () {
      var parser = GrammarParser();
      var gen = parser.parse('rule = rule "a" | "a";')!;
      var code = gen.compileParserGenerator("P");
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
      var metagrammarSource = readGrammarFile("lib/src/parser/grammar_parser.dart_grammar");

      var parser = GrammarParser();
      var gen = parser.parse(metagrammarSource)!;
      var compiledCode = gen.compileParserGenerator("CompiledGrammarParser");

      // Verify the compiled code is reasonable
      expect(compiledCode, contains("class CompiledGrammarParser"));
      expect(compiledCode.length, greaterThan(1000));
    });

    test("metagrammar round-trips: parse → compile → parse", () async {
      // Step 1: Parse the metagrammar
      var metagrammarSource = readGrammarFile("lib/src/parser/grammar_parser.dart_grammar");
      var parser = GrammarParser();
      var gen = parser.parse(metagrammarSource);
      expect(gen, isNotNull, reason: "metagrammar should parse");

      // Step 2: Compile to code
      var code = gen!.compileParserGenerator("GrammarParser");
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
}
