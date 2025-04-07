// ignore_for_file: prefer_function_declarations_over_variables, always_specify_types, non_constant_identifier_names, unreachable_from_main, inference_failure_on_untyped_parameter, avoid_dynamic_calls, unused_element, body_might_complete_normally_nullable

import "dart:convert";
import "dart:io";
import "dart:isolate";

import "package:args/args.dart";
import "package:parser_peg/src/generator.dart";
import "package:path/path.dart" as path;

import "../parser.cst.dart";
import "../parser.dart";
import "../playground.dart";

String readFile(String path) => File(path).readAsStringSync().replaceAll("\r", "").trim();

String displayTree(
  Object? node, {
  String indent = "",
  bool isLast = true,
  bool shouldNotPrintIndent = false,
}) {
  var buffer = StringBuffer();
  String marker = isLast ? "└─" : "├─";
  String newIndent = "$indent${isLast ? "  " : "│ "}";

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
        buffer.write(displayTree(object, indent: newIndent, isLast: i == child.length - 1));
      }

    /// Iterables
    case Iterable<Object?> objects when objects.isEmpty:
      buffer.writeln("[]");
    case Iterable<Object?> objects when objects.length == 1:
      buffer.write("──");
      buffer.write(displayTree(objects.single, indent: newIndent, shouldNotPrintIndent: true));
    case (List<Object?>() || Set<Object?>()) && Iterable<Object?> objects:
      var list = objects.toList();

      buffer
        ..write("┬─")
        ..write(
          displayTree(list.first, indent: newIndent, isLast: false, shouldNotPrintIndent: true),
        );
      for (var (i, object) in list.indexed.skip(1)) {
        buffer.write(displayTree(object, indent: newIndent, isLast: i == objects.length - 1));
      }

    /// Maps
    ///   These are hacks.
    case Map<Object?, Object?> map when map.isEmpty:
      buffer.writeln("{}");

    case Map<Object?, Object?> map when map.length == 1:
      buffer.write(
        displayTree(
          map.entries.map((e) => [e.key, e.value]).single,
          indent: indent,
          isLast: isLast,
          shouldNotPrintIndent: true,
        ),
      );

    case Map<Object?, Object?> map:
      buffer.write(
        displayTree(
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
  _experiment();
  // if (arguments.isEmpty) {
  //   stdout.writeln("No arguments provided.");
  //   stdout.writeln("Usage: parser_peg <input_path> --output <output_file> --name <parser_name>");
  //   return;
  // }

  // if (arguments case ["test"]) {
  //   _testCompiler();
  // } else {
  //   _buildParser(arguments);
  // }
}

void _testCompiler() async {
  var parser = GrammarParser();
  var input = readFile("parser.dart_grammar");

  /// It must be able to parse the grammar first.
  if (parser.parse(input) case ParserGenerator generator) {
    var parserCode = generator.compileParserGenerator("GrammarParser");
    File("test.dart")
      ..createSync(recursive: true)
      ..writeAsStringSync(parserCode);

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
  // if (GrammarParser() case GrammarParser grammar) {
  //   var inputPath = "parser.dart_grammar";
  //   if (readFile(inputPath) case String input) {
  //     switch (grammar.parse(input)) {
  //       case ParserGenerator generator:
  //         stdout.writeln("Successfully parsed grammar!");
  //         stdout.writeln("Generating parser.");

  //         /// Default output file
  //         var parentPath = path.dirname(inputPath);
  //         var fileName = path.basenameWithoutExtension(inputPath);

  //         File(path.join(parentPath, "$fileName.dart"))
  //           ..createSync(recursive: true)
  //           ..writeAsStringSync(generator.compileParserGenerator("GrammarParser"));

  //         // File(path.join(parentPath, "$fileName.cst.dart"))
  //         //   ..createSync(recursive: true)
  //         //   ..writeAsStringSync(generator.compileCstParserGenerator("CstGrammarParser"));

  //       case _:
  //         stdout.writeln(grammar.reportFailures());
  //     }
  //   }
  // }

  if (MyParser() case MyParser grammar) {
    print(grammar.parse('"one"'));
  }

  if (GrammarParser() case GrammarParser grammar) {
    var inputPath = "playground.dart_grammar";
    var input = readFile(inputPath);

    switch (grammar.parse(input)) {
      case ParserGenerator generator:
        stdout.writeln("Successfully parsed grammar!");
        stdout.writeln("Generating parser.");

        /// Default output file
        var parentPath = path.dirname(inputPath);
        var fileName = path.basenameWithoutExtension(inputPath);

        File(path.join(parentPath, "$fileName.dart"))
          ..createSync(recursive: true)
          ..writeAsStringSync(generator.compileParserGenerator("MyParser"));
      case _:
        stdout.writeln(grammar.reportFailures());
    }
  }

  if (CstGrammarParser() case CstGrammarParser grammar) {
    var inputPath = "playground.dart_grammar";
    var input = readFile(inputPath);

    switch (grammar.parse(input)) {
      case Object result:
        stdout.writeln("Successfully parsed grammar!");
        stdout.writeln("Generating parser.");

        File("playground.txt")
          ..createSync(recursive: true)
          ..writeAsStringSync(displayTree(result));

      case _:
        stdout.writeln(grammar.reportFailures());
    }
  }
}

extension<K, V> on Map<K, V> {
  Iterable<(K, V)> get pairs => entries.map((e) => (e.key, e.value));
}

void _buildParser(List<String> arguments) {
  var argParser =
      ArgParser()
        ..addOption("output", abbr: "o", help: "Output file path")
        ..addOption("name", abbr: "n", help: "Parser name");

  var parsedArgs = argParser.parse(arguments.sublist(1));

  if (GrammarParser() case GrammarParser grammar) {
    var inputPath = arguments.first;
    if (readFile(inputPath) case String input) {
      var name = (parsedArgs["name"] as String?) ?? "Parser";
      switch (grammar.parse(input)) {
        case ParserGenerator generator:
          stdout.writeln("Successfully parsed grammar!");
          stdout.writeln("Generating parser.");

          if (parsedArgs["output"] case String output) {
            File(output)
              ..createSync(recursive: true)
              ..writeAsStringSync(generator.compileParserGenerator(name));
          } else {
            /// Default output file
            var parentPath = path.dirname(inputPath);
            var fileName = path.basenameWithoutExtension(inputPath);
            var outputPath = path.join(parentPath, "$fileName.dart");

            File(outputPath)
              ..createSync(recursive: true)
              ..writeAsStringSync(generator.compileParserGenerator(name));
          }
        case _:
          stdout.writeln(grammar.reportFailures());
      }
    }
  }
}
