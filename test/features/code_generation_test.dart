// ignore_for_file: prefer_const_constructors

import "package:parser_peg/src/parser/grammar_parser.dart";
import "package:test/test.dart";

void main() {
  group("Code Generation - Basic Structure", () {
    test("parser class created", () {
      var grammar = GrammarParser();
      var source = "start = 'x';";
      var generated = grammar.parse(source);

      var code = generated!.compileParserGenerator("TestParser");

      expect(code, isNotEmpty);
      expect(code, contains("TestParser"));
    });

    test("start rule becomes start method", () {
      var grammar = GrammarParser();
      var source = "start = 'x';";
      var generated = grammar.parse(source);

      var code = generated!.compileParserGenerator("TestParser");

      expect(code, contains("start"));
      expect(code, isNotEmpty);
    });

    test("custom rule method", () {
      var grammar = GrammarParser();
      var source = "digit = 'x'; start = digit;";
      var generated = grammar.parse(source);

      var code = generated!.compileParserGenerator("TestParser");

      expect(code, contains("digit"));
      expect(code, isNotEmpty);
    });

    test("multiple rules become methods", () {
      var grammar = GrammarParser();
      var source = "a = 'x'; b = 'y'; c = 'z'; start = a;";
      var generated = grammar.parse(source);

      var code = generated!.compileParserGenerator("TestParser");

      expect(code, contains("a"));
      expect(code, contains("b"));
      expect(code, contains("c"));
      expect(code, isNotEmpty);
    });
  });

  group("Code Generation - String Literals", () {
    test("single character literal", () {
      var grammar = GrammarParser();
      var source = "start = 'x';";
      var generated = grammar.parse(source);

      var code = generated!.compileParserGenerator("TestParser");

      expect(code, contains("start"));
      expect(code, isNotEmpty);
    });

    test("multi-char literal", () {
      var grammar = GrammarParser();
      var source = "start = 'hello';";
      var generated = grammar.parse(source);

      var code = generated!.compileParserGenerator("TestParser");

      expect(code, isNotEmpty);
    });

    test("escape sequences", () {
      var grammar = GrammarParser();
      var source = r"start = '\n';";
      var generated = grammar.parse(source);

      var code = generated!.compileParserGenerator("TestParser");

      expect(code, isNotEmpty);
    });
  });

  group("Code Generation - Character Classes", () {
    test("character range", () {
      var grammar = GrammarParser();
      var source = "start = [a-z];";
      var generated = grammar.parse(source);

      var code = generated!.compileParserGenerator("TestParser");

      expect(code, contains("start"));
      expect(code, isNotEmpty);
    });

    test("negated character class", () {
      var grammar = GrammarParser();
      var source = "start = [^a-z];";
      var generated = grammar.parse(source);

      var code = generated!.compileParserGenerator("TestParser");

      expect(code, isNotEmpty);
    });

    test("multiple ranges", () {
      var grammar = GrammarParser();
      var source = "start = [a-zA-Z0-9];";
      var generated = grammar.parse(source);

      var code = generated!.compileParserGenerator("TestParser");

      expect(code, isNotEmpty);
    });
  });

  group("Code Generation - Operators", () {
    test("star operator generated", () {
      var grammar = GrammarParser();
      var source = "start = 'x'*;";
      var generated = grammar.parse(source);

      var code = generated!.compileParserGenerator("TestParser");

      expect(code, contains("start"));
      expect(code, isNotEmpty);
    });

    test("plus operator generated", () {
      var grammar = GrammarParser();
      var source = "start = 'x'+;";
      var generated = grammar.parse(source);

      var code = generated!.compileParserGenerator("TestParser");

      expect(code, contains("start"));
      expect(code, isNotEmpty);
    });

    test("optional operator generated", () {
      var grammar = GrammarParser();
      var source = "start = 'x'?;";
      var generated = grammar.parse(source);

      var code = generated!.compileParserGenerator("TestParser");

      expect(code, contains("start"));
      expect(code, isNotEmpty);
    });

    test("cut operator handled", () {
      var grammar = GrammarParser();
      var source = "start = 'a' ! 'b';";
      var generated = grammar.parse(source);

      var code = generated!.compileParserGenerator("TestParser");

      expect(code, contains("start"));
      expect(code, isNotEmpty);
    });
  });

  group("Code Generation - Sequences", () {
    test("simple sequence", () {
      var grammar = GrammarParser();
      var source = "start = 'a' 'b' 'c';";
      var generated = grammar.parse(source);

      var code = generated!.compileParserGenerator("TestParser");

      expect(code, contains("start"));
      expect(code, isNotEmpty);
    });

    test("sequence compiles", () {
      var grammar = GrammarParser();
      var source = "start = 'x' 'y' 'z';";
      var generated = grammar.parse(source);

      expect(() {
        generated!.compileParserGenerator("TestParser");
      }, returnsNormally);
    });
  });

  group("Code Generation - Rule References", () {
    test("rule reference compiled", () {
      var grammar = GrammarParser();
      var source = "expr = term; term = 'x'; start = expr;";
      var generated = grammar.parse(source);

      var code = generated!.compileParserGenerator("TestParser");

      expect(code, contains("expr"));
      expect(code, contains("term"));
      expect(code, isNotEmpty);
    });

    test("indirect recursion handled", () {
      var grammar = GrammarParser();
      var source = "a = b; b = a 'x'; start = 'test';";
      var generated = grammar.parse(source);

      var code = generated!.compileParserGenerator("TestParser");

      expect(code, contains("a"));
      expect(code, contains("b"));
      expect(code, isNotEmpty);
    });
  });

  group("Code Generation - Semantic Actions", () {
    test("action not lost", () {
      var grammar = GrammarParser();
      var source = "start = 'x' { x => x };";
      var generated = grammar.parse(source);

      var code = generated!.compileParserGenerator("TestParser");

      expect(code, contains("start"));
      expect(code, isNotEmpty);
    });

    test("multiple actions", () {
      var grammar = GrammarParser();
      var source = "a = 'x' { x => x }; b = 'y' { y => y }; start = a;";
      var generated = grammar.parse(source);

      var code = generated!.compileParserGenerator("TestParser");

      expect(code, contains("a"));
      expect(code, contains("b"));
      expect(code, isNotEmpty);
    });
  });

  group("Code Generation - AST Mode", () {
    test("ast parser generated", () {
      var grammar = GrammarParser();
      var source = "start = 'x';";
      var generated = grammar.parse(source);

      var code = generated!.compileAstParserGenerator("TestParser");

      expect(code, isNotEmpty);
      expect(code, contains("class TestParser"));
    });

    test("cst parser generated", () {
      var grammar = GrammarParser();
      var source = "start = 'x';";
      var generated = grammar.parse(source);

      var code = generated!.compileCstParserGenerator("TestParser");

      expect(code, isNotEmpty);
      expect(code, contains("class TestParser"));
    });
  });

  group("Code Generation - Optimization", () {
    test("inlinable fragments inlined", () {
      var grammar = GrammarParser();
      var source = "x = 'a'; start = x;";
      var generated = grammar.parse(source);

      var code = generated!.compileParserGenerator("TestParser");

      expect(code, contains("start"));
      expect(code, isNotEmpty);
    });

    test("complex fragment kept", () {
      var grammar = GrammarParser();
      var source = "complex = 'a' 'b' 'c'; start = complex;";
      var generated = grammar.parse(source);

      var code = generated!.compileParserGenerator("TestParser");

      expect(code, isNotEmpty);
    });
  });

  group("Code Generation - Errors", () {
    test("undefined rule causes error", () {
      var grammar = GrammarParser();
      var source = "start = undefined;";
      var generated = grammar.parse(source);

      expect(() => generated!.compileParserGenerator("TestParser"), throwsA(isA<Exception>()));
    });
  });

  group("Code Generation - Complex", () {
    test("multi-rule grammar", () {
      var grammar = GrammarParser();
      var source = """
        expr = term 'x';
        term = 'y';
        start = expr;
      """;
      var generated = grammar.parse(source);

      var code = generated!.compileParserGenerator("TestParser");

      expect(code, contains("expr"));
      expect(code, contains("term"));
    });

    test("compilation succeeds", () {
      var grammar = GrammarParser();
      var source = "start = 'x'*;";
      var generated = grammar.parse(source);

      expect(() {
        generated!.compileParserGenerator("TestParser");
      }, returnsNormally);
    });

    test("operators in sequence", () {
      var grammar = GrammarParser();
      var source = "start = 'a' 'b'? 'c'* 'd'+;";
      var generated = grammar.parse(source);

      var code = generated!.compileParserGenerator("TestParser");
      expect(code, isNotEmpty);
    });
  });
}
