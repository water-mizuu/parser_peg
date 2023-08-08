import "dart:convert";
import "dart:io";

import "package:parser_peg/src/generator.dart";
import "package:parser_peg/src/parser/parser.dart";

import "../examples/math/math.dart";
import "../examples/math/math_cst.dart";

String readFile(String path) => File(path).readAsStringSync().replaceAll("\r", "").trim();

String displayTree(Object? node, String indent, {required bool isLast}) {
  StringBuffer buffer = StringBuffer();
  String marker = isLast ? "└─" : "├─";

  buffer
    ..write(indent)
    ..write(marker)
    ..write("");

  if (node case (String name, Object? child)) {
    buffer.writeln(name);
    if (child is! List) {
      child = <Object?>[child];
    }
    String newIndent = "$indent${isLast ? "  " : "│ "}";

    for (var (int i, Object? object) in child.indexed) {
      buffer.write(displayTree(object, newIndent, isLast: i == child.length - 1));
    }
  } else if (node case List<Object?> objects) {
    buffer.writeln("┬─");
    String newIndent = "$indent${isLast ? "  " : "│ "}";
    for (var (int i, Object? object) in objects.indexed) {
      buffer.write(displayTree(object, newIndent, isLast: i == objects.length - 1));
    }
  } else if (node case String string) {
    buffer.writeln(jsonEncode(string));
  } else {
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
          File("lib/src/parser/parser_cst.dart")
            ..createSync(recursive: true)
            ..writeAsStringSync(generator.compileCst("PegParserCst"));
          File("lib/src/parser/parser.dart")
            ..createSync(recursive: true)
            ..writeAsStringSync(generator.compile("PegParser"));
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
            ..writeAsStringSync(generator.compileCst("MathParserCst"));
          File("examples/math/math.dart")
            ..createSync(recursive: true)
            ..writeAsStringSync(generator.compile("MathParser"));
        case _:
          stdout.writeln(grammar.reportFailures());
      }
    }
  }

  const String input = "-2^2^2";
  if (MathParserCst() case MathParserCst parser) {
    if (parser.parse(input) case Object tree) {
      stdout.writeln(displayTree(tree, "", isLast: true));
    }
  }

  if (MathParser() case MathParser parser) {
    if (parser.parse(input) case num result) {
      stdout.writeln(result);
    }
  }
}
