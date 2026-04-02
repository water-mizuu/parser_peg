// ignore_for_file: prefer_const_constructors

import "package:parser_peg/src/parser/grammar_parser.dart";
import "package:test/test.dart";

void main() {
  group("Edge Cases - Basic", () {
    test("single character", () {
      var grammar = GrammarParser();
      var source = "start = 'x';";
      var generated = grammar.parse(source);
      expect(generated, isNotNull);
    });

    test("empty string", () {
      var grammar = GrammarParser();
      var source = "start = '';";
      var generated = grammar.parse(source);
      expect(generated, isNotNull);
    });

    test("character class single", () {
      var grammar = GrammarParser();
      var source = "start = [a];";
      var generated = grammar.parse(source);
      expect(generated, isNotNull);
    });

    test("character class range", () {
      var grammar = GrammarParser();
      var source = "start = [a-z];";
      var generated = grammar.parse(source);
      expect(generated, isNotNull);
    });

    test("multiple ranges", () {
      var grammar = GrammarParser();
      var source = "start = [a-zA-Z0-9_];";
      var generated = grammar.parse(source);
      expect(generated, isNotNull);
    });
  });

  group("Edge Cases - Operators", () {
    test("star zero or more", () {
      var grammar = GrammarParser();
      var source = "start = 'a'*;";
      var generated = grammar.parse(source);
      expect(generated, isNotNull);
    });

    test("plus one or more", () {
      var grammar = GrammarParser();
      var source = "start = 'a'+;";
      var generated = grammar.parse(source);
      expect(generated, isNotNull);
    });

    test("optional", () {
      var grammar = GrammarParser();
      var source = "start = 'a'?;";
      var generated = grammar.parse(source);
      expect(generated, isNotNull);
    });

    test("counted exact", () {
      var grammar = GrammarParser();
      var source = "start = 'a'{3};";
      var generated = grammar.parse(source);
      expect(generated, isNotNull);
    });

    test("counted range", () {
      var grammar = GrammarParser();
      var source = "start = 'a'{2,5};";
      var generated = grammar.parse(source);
      expect(generated, isNotNull);
    });

    test("and predicate", () {
      var grammar = GrammarParser();
      var source = "start = &'a' 'a';";
      var generated = grammar.parse(source);
      expect(generated, isNotNull);
    });

    test("not predicate", () {
      var grammar = GrammarParser();
      var source = "start = !'a' 'b';";
      var generated = grammar.parse(source);
      expect(generated, isNotNull);
    });

    test("cut operator", () {
      var grammar = GrammarParser();
      var source = "start = 'a' ! 'b';";
      var generated = grammar.parse(source);
      expect(generated, isNotNull);
    });
  });

  group("Edge Cases - Nesting", () {
    test("nested parentheses", () {
      var grammar = GrammarParser();
      var source = "start = ((('x')));";
      var generated = grammar.parse(source);
      expect(generated, isNotNull);
    });

    test("sequence in parentheses", () {
      var grammar = GrammarParser();
      var source = "start = ('a' 'b') 'c';";
      var generated = grammar.parse(source);
      expect(generated, isNotNull);
    });

    test("deeply nested", () {
      var grammar = GrammarParser();
      var source = "start = 'a' ('b' ('c' ('d' 'e')));";
      var generated = grammar.parse(source);
      expect(generated, isNotNull);
    });
  });

  group("Edge Cases - Whitespace & Escapes", () {
    test("whitespace chars", () {
      var grammar = GrammarParser();
      var source = "start = ' ';";
      var generated = grammar.parse(source);
      expect(generated, isNotNull);
    });

    test("backslash newline", () {
      var grammar = GrammarParser();
      var source = r"start = '\n';";
      var generated = grammar.parse(source);
      expect(generated, isNotNull);
    });

    test("backslash tab", () {
      var grammar = GrammarParser();
      var source = r"start = '\t';";
      var generated = grammar.parse(source);
      expect(generated, isNotNull);
    });

    test("literal backslash", () {
      var grammar = GrammarParser();
      var source = r"start = '\\';";
      var generated = grammar.parse(source);
      expect(generated, isNotNull);
    });
  });

  group("Edge Cases - RegExp", () {
    test("simple regexp", () {
      var grammar = GrammarParser();
      var source = "start = /[0-9]+/;";
      var generated = grammar.parse(source);
      expect(generated, isNotNull);
    });

    test("complex regexp", () {
      var grammar = GrammarParser();
      var source = "start = /[a-zA-Z_][a-zA-Z0-9_]*/;";
      var generated = grammar.parse(source);
      expect(generated, isNotNull);
    });

    test("any character", () {
      var grammar = GrammarParser();
      var source = "start = .;";
      var generated = grammar.parse(source);
      expect(generated, isNotNull);
    });
  });

  group("Edge Cases - Semantic Actions", () {
    test("simple action", () {
      var grammar = GrammarParser();
      var source = "start = 'x' { x => x };";
      var generated = grammar.parse(source);
      expect(generated, isNotNull);
    });

    test("action with method", () {
      var grammar = GrammarParser();
      var source = "start = 'x' { x => x };";
      var generated = grammar.parse(source);
      expect(generated, isNotNull);
    });

    test("named node", () {
      var grammar = GrammarParser();
      var source = "start = ~x:'a';";
      var generated = grammar.parse(source);
      expect(generated, isNotNull);
    });
  });

  group("Edge Cases - Large Grammars", () {
    test("many rules", () {
      var grammar = GrammarParser();
      var rules = StringBuffer();
      for (int i = 0; i < 30; i++) {
        rules.writeln("r$i = 'x$i';");
      }
      rules.write("start = r0;");

      var generated = grammar.parse(rules.toString());
      expect(generated, isNotNull);
    });

    test("long sequence", () {
      var grammar = GrammarParser();
      var items = List.generate(20, (i) => "'item$i'").join(" ");
      var source = "start = $items;";

      var generated = grammar.parse(source);
      expect(generated, isNotNull);
    });

    test("deeply nested rules", () {
      var grammar = GrammarParser();
      var source = StringBuffer();
      for (int i = 0; i < 15; i++) {
        if (i < 14) {
          source.writeln("r$i = r${i + 1};");
        } else {
          source.writeln("r$i = 'x';");
        }
      }
      source.write("start = r0;");

      var generated = grammar.parse(source.toString());
      expect(generated, isNotNull);
    });
  });

  group("Edge Cases - Error Handling", () {
    test("syntax error with unclosed paren", () {
      var grammar = GrammarParser();
      var source = "start = (unclosed;";

      var generated = grammar.parse(source);
      expect(generated, isNull, reason: "Should fail to parse");
    });

    test("missing start rule detected", () {
      var grammar = GrammarParser();
      var source = "other_rule = 'x';";

      var generated = grammar.parse(source);
      // Parser accepts grammars without start rule
      // Compiler also handles it (uses first rule or specific rules)
      expect(generated, isNotNull);
      if (generated != null) {
        var code = generated.compileParserGenerator("TestParser");
        expect(code, isNotEmpty);
      }
    });

    test("undefined reference throws", () {
      var grammar = GrammarParser();
      var source = "start = undefined_rule;";

      var generated = grammar.parse(source);

      if (generated != null) {
        expect(() => generated.compileParserGenerator("TestParser"), throwsA(isA<Exception>()));
      }
    });
  });
}
