// ignore_for_file: prefer_function_declarations_over_variables, always_specify_types, non_constant_identifier_names, unreachable_from_main, inference_failure_on_untyped_parameter, avoid_dynamic_calls, unused_element, body_might_complete_normally_nullable

import "dart:convert";
import "dart:io";
import "dart:isolate";

import "package:args/args.dart";
import "package:dart_casing/dart_casing.dart";
import "package:parser_peg/src/generator.dart";
import "package:parser_peg/src/parser/grammar_parser.cst.dart";
import "package:parser_peg/src/parser/grammar_parser.dart";
import "package:path/path.dart" as path;

String readFile(String path) => File(path).readAsStringSync().replaceAll("\r", "").trim();

String displayTree(Object? node) => _displayTree(node);
String _displayTree(
  Object? node, {
  String indent = "",
  bool isLast = true,
  bool shouldNotPrintIndent = false,
}) {
  var buffer = StringBuffer();
  var marker = isLast ? "└─" : "├─";
  var newIndent = "$indent${isLast ? "  " : "│ "}";

  if (!shouldNotPrintIndent) {
    buffer
      ..write(indent)
      ..write(marker)
      ..write("");
  }

  switch (node) {
    case (String name, Object? child):
      buffer.writeln(name);
      if (child is! List) {
        child = [child];
      }

      for (var (i, object) in child.indexed) {
        buffer.write(_displayTree(object, indent: newIndent, isLast: i == child.length - 1));
      }

    /// Iterables
    case Iterable<Object?> objects when objects.isEmpty:
      buffer.writeln("[]");
    case Iterable<Object?> objects when objects.length == 1:
      buffer.write("──");
      buffer.write(_displayTree(objects.single, indent: newIndent, shouldNotPrintIndent: true));
    case (List<Object?>() || Set<Object?>()) && Iterable<Object?> objects:
      var list = objects.toList();

      buffer
        ..write("┬─")
        ..write(
          _displayTree(list.first, indent: newIndent, isLast: false, shouldNotPrintIndent: true),
        );
      for (var (i, object) in list.indexed.skip(1)) {
        buffer.write(_displayTree(object, indent: newIndent, isLast: i == objects.length - 1));
      }

    /// Maps
    ///   These are hacks.
    case Map<Object?, Object?> map when map.isEmpty:
      buffer.writeln("{}");

    case Map<Object?, Object?> map when map.length == 1:
      buffer.write(
        _displayTree(
          map.entries.map((e) => [e.key, e.value]).single,
          indent: indent,
          isLast: isLast,
          shouldNotPrintIndent: true,
        ),
      );

    case Map<Object?, Object?> map:
      buffer.write(
        _displayTree(
          map.entries.map((e) => [e.key, e.value]).toList(),
          indent: indent,
          isLast: isLast,
          shouldNotPrintIndent: true,
        ),
      );

    /// Strings
    case String string:
      buffer.writeln(jsonEncode(string));
    case _:
      buffer.writeln(node);
  }

  return buffer.toString();
}

void main(List<String> arguments) {
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
      """.unindent();

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
    const inputPath = "lib/src/parser/grammar_parser.dart_grammar";
    if (readFile(inputPath) case String input) {
      switch (grammar.parse(input)) {
        case ParserGenerator generator:
          stdout.writeln("Successfully parsed grammar!");
          stdout.writeln("Generating parser.");

          /// Default output file
          var parentPath = path.dirname(inputPath);
          var fileName = path.basenameWithoutExtension(inputPath);

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
    const inputPath = "lib/src/parser/grammar_parser.dart_grammar";
    var input = readFile(inputPath);
    var parentPath = path.dirname(inputPath);
    var fileName = path.basenameWithoutExtension(inputPath);

    switch (grammar.parse(input)) {
      case Object result:
        stdout.writeln("Successfully parsed grammar!");
        stdout.writeln("Generating parser.");

        File(path.join(parentPath, "$fileName.txt"))
          ..createSync(recursive: true)
          ..writeAsStringSync(_displayTree(result));

      case _:
        stdout.writeln(grammar.reportFailures());
    }
  }
}

extension<K, V> on Map<K, V> {
  Iterable<(K, V)> get pairs => entries.map((e) => (e.key, e.value));
}

void _buildParser(List<String> arguments, {bool complete = false}) {
  var argParser =
      ArgParser()
        ..addOption("output", abbr: "o", help: "Output file path")
        ..addOption("name", abbr: "n", help: "Parser name");

  var parsedArgs = argParser.parse(arguments.sublist(1));

  if (GrammarParser() case GrammarParser grammar) {
    var inputPath = arguments.first;
    var fileName = path.basenameWithoutExtension(inputPath);

    if (readFile(inputPath) case String input) {
      var name = (parsedArgs["name"] as String?) ?? Casing.pascalCase(fileName);
      switch (grammar.parse(input)) {
        case ParserGenerator generator:
          stdout.writeln("Successfully parsed grammar!");
          stdout.writeln("Generating parser.");

          var outputPath = switch (parsedArgs["output"] as String?) {
            var output? => output,
            null => path.join(path.dirname(inputPath), "$fileName.dart"),
          };

          File(outputPath)
            ..createSync(recursive: true)
            ..writeAsStringSync(generator.compileParserGenerator(name));

          if (complete) {
            var cstOutputPath = path.join(path.dirname(outputPath), "$fileName.cst.dart");
            File(cstOutputPath)
              ..createSync(recursive: true)
              ..writeAsStringSync(generator.compileCstParserGenerator(name));

            var astOutputPath = path.join(path.dirname(outputPath), "$fileName.ast.dart");
            File(astOutputPath)
              ..createSync(recursive: true)
              ..writeAsStringSync(generator.compileAstParserGenerator(name));

            if (CstGrammarParser() case CstGrammarParser cstGrammar) {
              var cstInput = readFile(inputPath);
              switch (cstGrammar.parse(cstInput)) {
                case Object result:
                  File(path.join(path.dirname(cstOutputPath), "$fileName.txt"))
                    ..createSync(recursive: true)
                    ..writeAsStringSync(_displayTree(result));
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
}
