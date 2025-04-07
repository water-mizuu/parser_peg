// ignore_for_file: prefer_function_declarations_over_variables, always_specify_types, non_constant_identifier_names, unreachable_from_main, inference_failure_on_untyped_parameter, avoid_dynamic_calls, unused_element, body_might_complete_normally_nullable

import "dart:convert";
import "dart:io";

import "package:args/args.dart";
import "package:parser_peg/src/generator.dart";
import "package:parser_peg/src/parser/parser.dart";
import "package:path/path.dart" as path;

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

      for (var (int i, Object? object) in child.indexed) {
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
  if (arguments.isEmpty) {
    stdout.writeln("No arguments provided.");
    stdout.writeln("Usage: parser_peg <input_path> --output <output_file> --name <parser_name>");
    return;
  }
  // ignore: unnecessary_statements
  var argParser =
      ArgParser()
        ..addOption("output", abbr: "o", help: "Output file path")
        ..addOption("name", abbr: "n", help: "Parser name");

  var parsedArgs = argParser.parse(arguments.sublist(1));

  if (PegParser() case PegParser grammar) {
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

  // if (PegParserCst() case PegParserCst grammar) {
  //   var inputPath = parsedArgs["input"];
  //   assert(inputPath is String, "Input file path must be a string");

  //   if (readFile(inputPath as String) case String input) {
  //     switch (grammar.parse(input)) {
  //       case Object object:
  //         var tree = displayTree(object);

  //         File("bin/test.txt")
  //           ..createSync(recursive: true)
  //           ..writeAsStringSync(tree);
  //       case _:
  //         stdout.writeln(grammar.reportFailures());
  //     }
  //   }
  // }
}
