import "dart:convert";
import "dart:io";

import "package:parser_peg/src/generator.dart";
import "package:parser_peg/src/parser/parser.dart";
import "package:parser_peg/src/parser/parser_ast.dart";
import "package:parser_peg/src/parser/parser_cst.dart";

String readFile(String path) => File(path).readAsStringSync().replaceAll("\r", "").trim();

String displayTree(Object? node, String indent, {required bool isLast}) {
  StringBuffer buffer = StringBuffer();
  String marker = isLast ? "└─" : "├─";
  String newIndent = "$indent${isLast ? "  " : "│ "}";

  buffer
    ..write(indent)
    ..write(marker)
    ..write("");

  switch (node) {
    case (String name, Object? child):
      buffer.writeln(name);
      if (child is! List) {
        child = <Object?>[child];
      }

      for (var (int i, Object? object) in child.indexed) {
        buffer.write(displayTree(object, newIndent, isLast: i == child.length - 1));
      }
    case List<Object?> objects:
      buffer.writeln("┐");
      for (var (int i, Object? object) in objects.indexed) {
        buffer.write(displayTree(object, newIndent, isLast: i == objects.length - 1));
      }
    case String string:
      buffer.writeln(jsonEncode(string));
    case _:
      buffer.writeln(node);
  }

  return buffer.toString();
}

void main(List<String> arguments) {
  if (PegParser() case PegParser grammar) {
    if (readFile("lib/src/parser/parser.dart_grammar") case String input) {
      switch (grammar.parse(input)) {
        case ParserGenerator generator:
          stdout.writeln("Successfully parsed grammar!");

          stdout.writeln("Generating CST parser.");
          File("lib/src/parser/parser_cst.dart")
            ..createSync(recursive: true)
            ..writeAsStringSync(generator.compileCstParserGenerator("PegParserCst"));
          stdout.writeln("Generating AST parser.");
          File("lib/src/parser/parser_ast.dart")
            ..createSync(recursive: true)
            ..writeAsStringSync(generator.compileAstParserGenerator("PegParserAst"));
          stdout.writeln("Generating parser.");
          File("lib/src/parser/parser.dart")
            ..createSync(recursive: true)
            ..writeAsStringSync(generator.compileParserGenerator("PegParser"));
        case _:
          stdout.writeln(grammar.reportFailures());
      }
    }

    if (readFile("examples/math/math.dart_grammar") case String input) {
      switch (grammar.parse(input)) {
        case ParserGenerator generator:
          stdout.writeln("Successfully parsed grammar!");
          File("examples/math/math_cst.dart")
            ..createSync(recursive: true)
            ..writeAsStringSync(generator.compileCstParserGenerator("MathParserCst"));
          File("examples/math/math.dart")
            ..createSync(recursive: true)
            ..writeAsStringSync(generator.compileParserGenerator("MathParser"));
        case _:
          stdout.writeln(grammar.reportFailures());
      }
    }
  }

  if (readFile("bin/playground.dart_grammar") case String input) {
    if (PegParser() case PegParser grammar) {
      switch (grammar.parse(input)) {
        case ParserGenerator generator:
          stdout.writeln("Successfully parsed grammar!");
          File("bin/playground.dart")
            ..createSync(recursive: true)
            ..writeAsStringSync(generator.compileParserGenerator("Playground"));
      }
    }
    if (PegParserAst() case PegParserAst grammar) {
      switch (grammar.parse(input)) {
        case Object node:
          stdout.writeln(node);
      }
    }
    if (PegParserCst() case PegParserCst grammar) {
      switch (grammar.parse(input)) {
        case Object node:
          stdout.writeln(displayTree(node, "", isLast: true));
      }
    }
  }
}
