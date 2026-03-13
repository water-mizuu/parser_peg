import "dart:io";

import "package:args/args.dart";
import "package:dart_casing/dart_casing.dart";
import "package:parser_peg/src/generator.dart";
import "package:parser_peg/src/parser/grammar_parser.cst.dart";
import "package:path/path.dart" as path;

// import "package:parser_peg/src/parser/grammar_parser.dart";
import "../examples/meta/grammar_parser.dart";
import "helpers.dart";

void main(List<String> arguments) async {
  if (arguments.isEmpty) {
    stdout.writeln("No arguments provided.");
    stdout.writeln("Usage: parser_peg <input_path> --output <output_file> --name <parser_name>");
    return;
  }

  if (arguments case ["complete", ...var rest]) {
    await _buildParser(rest, complete: true);
  } else {
    await _buildParser(arguments);
  }
}

Future<void> _buildParser(List<String> arguments, {bool complete = false}) async {
  var argParser = ArgParser()
    ..addOption("output", abbr: "o", help: "Output file path")
    ..addOption("name", abbr: "n", help: "Parser name");

  var parsedArgs = argParser.parse(arguments.sublist(1));

  if (GrammarParser() case GrammarParser grammar) {
    String inputPath = arguments.first;
    String fileName = path.basenameWithoutExtension(inputPath);

    String input = readFile(inputPath);
    String name = (parsedArgs["name"] as String?) ?? Casing.pascalCase(fileName);
    switch (grammar.parse(input)) {
      case ParserGenerator generator:
        generator.setup(File(inputPath).path);
        stdout.writeln("Successfully parsed grammar!");
        stdout.writeln("Generating parser.");

        String outputPath = switch (parsedArgs["output"] as String?) {
          var output? => output,
          null => path.join(path.dirname(inputPath), "$fileName.dart"),
        };

        File(outputPath)
          ..createSync(recursive: true)
          ..writeAsStringSync(await generator.compileAnalyzedParserGenerator(name));

        if (complete) {
          String cstOutputPath = path.join(path.dirname(outputPath), "$fileName.cst.dart");
          File(cstOutputPath)
            ..createSync(recursive: true)
            ..writeAsStringSync(generator.compileCstParserGenerator(name));

          String astOutputPath = path.join(path.dirname(outputPath), "$fileName.ast.dart");
          File(astOutputPath)
            ..createSync(recursive: true)
            ..writeAsStringSync(generator.compileAstParserGenerator(name));

          if (CstGrammarParser() case CstGrammarParser cstGrammar) {
            String cstInput = readFile(inputPath);
            switch (cstGrammar.parse(cstInput)) {
              case Object result:
                File(path.join(path.dirname(cstOutputPath), "$fileName.txt"))
                  ..createSync(recursive: true)
                  ..writeAsStringSync(displayTree(result));
              case _:
                stdout.writeln(cstGrammar.reportFailures());
            }
          }
        }
      case _:
        stdout.writeln(grammar.reportFailures());
    }
  }
}
