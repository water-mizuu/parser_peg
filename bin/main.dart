import "dart:convert";
import "dart:io";

import "package:parser_peg/src/generator.dart";
import "package:parser_peg/src/parser/parser.dart";
import "package:parser_peg/src/parser/parser_cst.dart";

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
  if (readFile("lib/src/parser/parser.dart_grammar") case String input) {
    if (PegParser() case PegParser grammar) {
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
  }

  if (readFile("lib/src/parser/parser.dart_grammar") case String input) {
    if (PegParserCst() case PegParserCst grammar) {
      File("bin/test.txt")
        ..createSync(recursive: true)
        ..writeAsStringSync(displayTree(grammar.parse(input), "", isLast: true));
    }
  }
}
