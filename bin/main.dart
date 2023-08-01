// cspell:disable
import "dart:io";

import "package:parser_peg/src/generator.dart";
import "package:parser_peg/src/parser/parser.dart";

String readFile(String path) => File(path).readAsStringSync().replaceAll("\r", "").trim();

void main(List<String> arguments) {
  if (readFile("lib/src/parser/parser.dart_grammar") case String input) {
    if (PegParser() case PegParser grammar) {
      switch (grammar.parse(input)) {
        case ParserGenerator generator:
          File("lib/src/parser/parser.dart")
            ..createSync(recursive: true)
            ..writeAsStringSync(generator.compile("PegParser"));
          stdout.writeln("Successfully parsed grammar!");
        case _:
          stdout.writeln(grammar.reportFailures());
      }
    }
  }
  if (readFile("examples/playground/playground.dart_grammar") case String input) {
    if (PegParser() case PegParser grammar) {
      switch (grammar.parse(input)) {
        case ParserGenerator generator:
          File("examples/playground/playground.dart")
            ..createSync(recursive: true)
            ..writeAsStringSync(generator.compile("PlaygroundParser"));
          stdout.writeln("Successfully parsed grammar!");
        case _:
          stdout.writeln(grammar.reportFailures());
      }
    }
  }
}
