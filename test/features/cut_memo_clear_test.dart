import "dart:io";

import "package:parser_peg/src/parser/grammar_parser.dart";
import "package:test/test.dart";

void main() {
  group("Cut Memoization Clearing", () {
    late GrammarParser parser;

    setUp(() {
      parser = GrammarParser();
    });

    test("cut clears memoization table", () async {
      var grammar = """
        {
          int count = 0;
        }
        @fragment start = a | b;
        a = memoized # "fail";
        b = memoized;
        memoized = "x" { count++; return count; };
        """;

      var gen = parser.parse(grammar)!;
      var parserSource = gen.compileParserGenerator("TestParser");

      var tempDir = Directory.systemTemp.createTempSync();
      var parserFile = File("${tempDir.path}/parser.dart");
      parserFile.writeAsStringSync(parserSource);

      var testFile = File("${tempDir.path}/test.dart");
      testFile.writeAsStringSync("""
import 'parser.dart';

void main() {
  var parser = TestParser();
  var result = parser.parse("x");
  print(result);
}
""");

      var processResult = Process.runSync("dart", [testFile.path]);
      if (processResult.exitCode != 0) {
        print(processResult.stderr);
      }
      if (processResult.stdout.trim() != "2") {
        print("Generated Source:\n$parserSource");
      }
      expect(processResult.stdout.trim(), equals("2"));

      tempDir.deleteSync(recursive: true);
    });

    test("cut does NOT clear memoization if not reached", () async {
      var grammar = """
{
int count = 0;
}
@fragment start = a | b;
a = "y" # "fail";
b = memoized;
memoized = "x" { count++; return count; };
""";

      var gen = parser.parse(grammar)!;
      var parserSource = gen.compileParserGenerator("TestParser");

      var tempDir = Directory.systemTemp.createTempSync();
      var parserFile = File("${tempDir.path}/parser.dart");
      parserFile.writeAsStringSync(parserSource);

      var testFile = File("${tempDir.path}/test.dart");
      testFile.writeAsStringSync("""
import 'parser.dart';

void main() {
  var parser = TestParser();
  var result = parser.parse("x");
  print(result);
}
""");

      var processResult = Process.runSync("dart", [testFile.path]);
      expect(processResult.stdout.trim(), equals("1"));

      tempDir.deleteSync(recursive: true);
    });
  });
}
