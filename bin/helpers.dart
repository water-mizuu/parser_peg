import "dart:async";
import "dart:convert";
import "dart:io";
import "dart:isolate";

import "package:parser_peg/src/parser/grammar_parser.dart";

String readFile(String path) => File(path).readAsStringSync().replaceAll("\r", "").trim();

String displayTree(
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

// ---------------------------------------------------------------------------
//  Utilities
// ---------------------------------------------------------------------------

String readGrammarFile(String relativePath) =>
    File(relativePath).readAsStringSync().replaceAll("\r", "").trim();

/// Compiles a `.dart_grammar` source into Dart code, spawns a **single**
/// isolate and returns a helper that can repeatedly invoke `parse()` on it.
///
/// The isolate listens on a [ReceivePort] and for every `String` message
/// it receives it calls `parser.parse(message)` and sends the JSON-encoded
/// result back.
///
/// Callers **must** call [IsolateParser.dispose] when finished.
Future<IsolateParser> spawnParser(String grammarSource, {String parserName = "TestParser"}) async {
  var grammar = GrammarParser();
  var generator = grammar.parse(grammarSource);
  if (generator == null) {
    throw StateError("Failed to parse grammar:\n${grammar.reportFailures()}");
  }

  var parserCode = await generator.compileAnalyzedParserGenerator(parserName);

  // Build a small driver program that keeps running, parsing each message
  // it receives via a SendPort.
  var driver =
      """
      import "dart:convert" show jsonEncode;
      import "dart:isolate" show ReceivePort, SendPort;

      $parserCode

      Object? _serialize(Object? v) {
        if (v == null) return null;
        if (v is num || v is bool || v is String) return v;
        if (v is List) return v.map(_serialize).toList();
        if (v is Map) return v.map((k, v) => MapEntry(k.toString(), _serialize(v)));
        return v.toString();
      }

      void main(List<String> _, SendPort initPort) {
        var receivePort = ReceivePort();
        initPort.send(receivePort.sendPort);

        var parser = $parserName();

        receivePort.listen((msg) {
          var [replyPort as SendPort, input as String] = msg as List;
          try {
            var result = parser.parse(input);

            if (result == null) {
              return replyPort.send(["fail", parser.reportFailures()]);
            } else {
              return replyPort.send(["ok", jsonEncode(_serialize(result))]);
            }
          } catch (e, st) {
            replyPort.send(["error", e.toString(), st.toString()]);
          }
        });
      }
      """;

  var uri = Uri.dataFromString(
    driver,
    mimeType: "application/dart",
    encoding: const SystemEncoding(),
    base64: true,
  );

  var initPort = ReceivePort();
  var onError = ReceivePort();
  // ignore: cancel_subscriptions
  var errSub = onError.listen((data) {
    // surface compile or runtime errors from the isolate
    throw StateError("Isolate error: $data");
  });

  var isolate = await Isolate.spawnUri(uri, [], initPort.sendPort, onError: onError.sendPort);

  var sendPort = await initPort.first as SendPort;

  return IsolateParser._(isolate, sendPort, onError, errSub);
}

class IsolateParser {
  IsolateParser._(this._isolate, this._sendPort, this._onError, this._errSub);

  final Isolate _isolate;
  final SendPort _sendPort;
  final ReceivePort _onError;
  final StreamSubscription<dynamic> _errSub;

  /// Sends [input] to the compiled parser and returns the JSON-decoded result.
  /// Returns `null` when the parser fails to match.
  Future<Object?> parse(String input) async {
    var reply = ReceivePort();
    _sendPort.send([reply.sendPort, input]);
    var response = await reply.first as List;
    if (response[0] == "error") {
      throw StateError("Parser runtime error: ${response[1]}\n${response[2]}");
    }
    var jsonStr = response[1] as String?;
    return jsonStr == null ? null : jsonDecode(jsonStr);
  }

  void dispose() {
    unawaited(_errSub.cancel());
    _onError.close();
    _isolate.kill(priority: Isolate.immediate);
  }
}
