// ignore_for_file: prefer_function_declarations_over_variables, always_specify_types, non_constant_identifier_names, unreachable_from_main, inference_failure_on_untyped_parameter, avoid_dynamic_calls, unused_element, body_might_complete_normally_nullable

import "dart:convert";
import "dart:io";

import "package:parser_peg/src/generator.dart";
import "package:parser_peg/src/parser/parser.dart";

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
}
