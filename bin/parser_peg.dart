import "dart:io";
import "dart:isolate";

import "package:args/args.dart";
import "package:dart_casing/dart_casing.dart";
import "package:parser_peg/src/generator.dart";
import "package:parser_peg/src/parser/grammar_parser.cst.dart";
import "package:parser_peg/src/parser/grammar_parser.dart";
import "package:path/path.dart" as path;

import "helpers.dart";

void main(List<String> arguments) async {
  if (arguments.isEmpty) {
    stdout.writeln("No arguments provided.");
    stdout.writeln("Usage: parser_peg <input_path> --output <output_file> --name <parser_name>");
    return;
  }

  if (arguments case ["experiment"]) {
    _experiment();
  } else if (arguments case ["test"]) {
    _testCompiler();
  } else if (arguments case ["complete", ...var rest]) {
    _buildParser(rest, complete: true);
  } else {
    _buildParser(arguments);
  }
}

void _testCompiler() async {
  var parser = GrammarParser();
  var input = readFile("parser.dart_grammar");

  /// It must be able to parse the grammar first.
  if (parser.parse(input) case ParserGenerator generator) {
    var parserCode = generator.compileParserGenerator("GrammarParser");
    var template =
        """
      import "dart:isolate" show SendPort;

      $parserCode

      void main(_, payload) {
        var [sendPort as SendPort, grammar as String] = payload;
        var parser = GrammarParser();

        if (parser.parse(grammar) case var generator?) {
          sendPort.send(true);
        } else {
          sendPort.send(false);
        }
      }
      """
            .unindent();

    var uri = Uri.dataFromString(
      template,
      mimeType: "application/dart",
      encoding: const SystemEncoding(),
      base64: true,
    );

    late Isolate isolate;
    var onError = ReceivePort();
    var onExit = ReceivePort();
    var listeningReceivePort = ReceivePort();
    onError.listen((data) {
      print((error: data));
    });
    onExit.listen((data) {
      onError.close();
      onExit.close();
      listeningReceivePort.close();
      isolate.kill();
    });

    listeningReceivePort.listen((message) async {
      print(message);
    });
    isolate = await Isolate.spawnUri(
      uri,
      [],
      [listeningReceivePort.sendPort, input],
      onError: onError.sendPort,
      onExit: onExit.sendPort,
    );
    File("test.dart")
      ..createSync(recursive: true)
      ..writeAsStringSync(parserCode);
  }
}

void _experiment() {
  if (GrammarParser() case GrammarParser grammar) {
    const String inputPath = "lib/src/parser/grammar_parser.dart_grammar";
    if (readFile(inputPath) case String input) {
      switch (grammar.parse(input)) {
        case ParserGenerator generator:
          stdout.writeln("Successfully parsed grammar!");
          stdout.writeln("Generating parser.");

          /// Default output file
          String parentPath = path.dirname(inputPath);
          String fileName = path.basenameWithoutExtension(inputPath);

          print("Compiling parser to $parentPath/$fileName.dart");
          File(path.join(parentPath, "$fileName.dart"))
            ..createSync(recursive: true)
            ..writeAsStringSync(generator.compileParserGenerator("GrammarParser"));
          print("Compiled parser to $parentPath/$fileName.dart");

          print("Compiling cst-parser to $parentPath/$fileName.cst.dart");
          File(path.join(parentPath, "$fileName.cst.dart"))
            ..createSync(recursive: true)
            ..writeAsStringSync(generator.compileCstParserGenerator("CstGrammarParser"));
          print("Compiled cst-parser to $parentPath/$fileName.cst.dart");

          print("Compiling cst-parser to $parentPath/$fileName.ast.dart");
          File(path.join(parentPath, "$fileName.ast.dart"))
            ..createSync(recursive: true)
            ..writeAsStringSync(generator.compileAstParserGenerator("AstGrammarParser"));
          print("Compiled ast-parser to $parentPath/$fileName.ast.dart");

        case _:
          stdout.writeln(grammar.reportFailures());
      }
    }
  }

  if (CstGrammarParser() case CstGrammarParser grammar) {
    const String inputPath = "lib/src/parser/grammar_parser.dart_grammar";
    String input = readFile(inputPath);
    String parentPath = path.dirname(inputPath);
    String fileName = path.basenameWithoutExtension(inputPath);

    switch (grammar.parse(input)) {
      case Object result:
        stdout.writeln("Successfully parsed grammar!");
        stdout.writeln("Generating parser.");

        File(path.join(parentPath, "$fileName.txt"))
          ..createSync(recursive: true)
          ..writeAsStringSync(displayTree(result));

      case _:
        stdout.writeln(grammar.reportFailures());
    }
  }
}

void _buildParser(List<String> arguments, {bool complete = false}) {
  var argParser = ArgParser()
    ..addOption("output", abbr: "o", help: "Output file path")
    ..addOption("name", abbr: "n", help: "Parser name");

  var parsedArgs = argParser.parse(arguments.sublist(1));

  if (GrammarParser() case GrammarParser grammar) {
    String inputPath = arguments.first;
    String fileName = path.basenameWithoutExtension(inputPath);

    String input = readFile(inputPath);
    String name = (parsedArgs["name"] as String?) ?? Casing.pascalCase(fileName);
    print("Hi");
    switch (grammar.parse(input)) {
      case ParserGenerator generator:
        stdout.writeln("Successfully parsed grammar!");
        stdout.writeln("Generating parser.");

        String outputPath = switch (parsedArgs["output"] as String?) {
          var output? => output,
          null => path.join(path.dirname(inputPath), "$fileName.dart"),
        };

        File(outputPath)
          ..createSync(recursive: true)
          ..writeAsStringSync(generator.compileParserGenerator(name));

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
