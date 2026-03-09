// ignore_for_file: always_specify_types

import "dart:convert";

import "package:parser_peg/src/generator.dart";
import "package:parser_peg/src/node.dart";
import "package:parser_peg/src/visitor/node_visitor.dart";
import "package:parser_peg/src/visitor/node_visitor/simple_visitor/is_cut_visitor.dart";

/// Compilation parameters threaded through a [ParserCompilerVisitor]
/// traversal.
///
/// Each field controls a different aspect of how the code for a single
/// grammar node is emitted:
///
/// - [isPassIfNull] — when `true`, the generated code may produce a
///   nullable value (e.g., inside an optional branch). When `false`, a
///   `null` result should be treated as a parse failure.
/// - [withNames] — if non-null, the set of named capture labels that the
///   generated code must bind so that semantic actions can reference them.
/// - [inner] — an optional Dart expression string to be embedded inside
///   the generated code, typically used to pass a continuation or inner
///   action body.
/// - [declarationName] — the name of the top-level rule or fragment
///   currently being compiled, used to generate locally unique identifiers.
/// - [isMarked] — when `true`, the generated code should save and restore
///   the parser position around the node (needed for backtracking).
class Parameters {
  const Parameters({
    required this.isPassIfNull,
    required this.withNames,
    required this.inner,
    required this.declarationName,
    required this.isMarked,
    required this.isCuttable,
  });

  final bool isPassIfNull;
  final Set<String>? withNames;
  final String? inner;
  final String declarationName;
  final bool isMarked;
  final bool isCuttable;
}

String encode(Object object) => jsonEncode(object).replaceAll(r"$", r"\$");

/// This visitor compiles the parser grammar into a Dart function.
class ParserCompilerVisitor implements ParametrizedNodeVisitor<String, Parameters> {
  ParserCompilerVisitor({required this.isPassIfNull, required this.reported});

  final bool Function(Node, String) isPassIfNull;
  final bool reported;

  int ruleId = 0;

  /// These are used to generate unique names for the regexps.
  final Map<String, int> regexpIds = <String, int>{};

  /// These are used to store all the RegExp strings.
  final List<String> regexps = <String>[];
  int regexpId = 0;

  /// These are used to generate unique names for the tries.
  final Map<String, int> trieIds = <String, int>{};

  /// These are used to store all the (to-built) tries.
  final List<List<String>> tries = <List<String>>[];
  int trieId = 0;

  /// These are used to generate unique names for the strings.
  final Map<String, int> stringIds = <String, int>{};

  /// These are used to store all the strings.
  final List<String> strings = <String>[];
  int stringId = 0;

  /// These are used to generate unique names for the ranges.
  final Map<String, int> rangeIds = <String, int>{};

  /// These are used to store all the ranges.
  final List<Set<(int, int)>> ranges = <Set<(int, int)>>[];
  int rangeId = 0;

  @override
  String visitCutNode(node, parameters) {
    StringBuffer buffer = StringBuffer();
    if (parameters.isCuttable) {
      buffer.writeln("_mark.isCut = true;");
    }
    buffer.writeln(parameters.inner ?? "return null;");

    return buffer.toString().wrap("if (null case ${parameters.withNames.caseVarNames}) {", "}");
  }

  @override
  String visitEpsilonNode(node, parameters) {
    var Parameters(isPassIfNull: isNullAllowed, :withNames, :inner) = parameters;
    var body = inner ?? "return ${withNames.singleName};";
    return body.wrap("if ('' case ${withNames.caseVarNames}) {", "}");
  }

  @override
  String visitTriePatternNode(node, parameters) {
    var Parameters(isPassIfNull: isNullAllowed, :withNames, :inner) = parameters;
    var key = jsonEncode(node.options);
    var id = trieIds[key] ??= (tries..add(node.options), ++trieId).$2;
    var questionMark = isNullAllowed ? "" : "?";
    var name = withNames.caseVarNames + questionMark;

    var body = inner ?? "return ${withNames.singleName};";
    return body.wrap("if (this.matchTrie(_trie.\$$id) case $name) {", "}");
  }

  @override
  String visitStringLiteralNode(node, parameters) {
    /// Matches a literal string against the input.
    ///
    /// It assigns a unique ID to each distinct string literal to allow for efficient lookup
    /// via the `_string` table in the generated parser.
    var Parameters(isPassIfNull: isNullAllowed, :withNames, :inner) = parameters;
    var key = node.literal;
    var id = stringIds[key] ??= (strings..add(node.literal), ++stringId).$2;
    var questionMark = isNullAllowed ? "" : "?";
    var name = withNames.caseVarNames + questionMark;

    var body = inner ?? "return ${withNames.singleName};";
    return body.wrap("if (this.matchPattern(_string.\$$id) case $name) {", "}");
  }

  @override
  String visitRangeNode(node, parameters) {
    /// Matches a character range (e.g., [a-z]) against the input.
    ///
    /// The range is flattened into a canonical string key and assigned a unique ID
    /// for lookup via the `_range` table.
    var Parameters(isPassIfNull: isNullAllowed, :withNames, :inner) = parameters;
    var key = node
        .ranges //
        .map(
          (v) => switch (v) {
            (var l, var r) when l == r => "$l",
            (var l, var r) => "$l-$r",
          },
        )
        .join(",");

    var id = rangeIds[key] ??= (ranges..add(node.ranges), ++rangeId).$2;
    var questionMark = isNullAllowed ? "" : "?";
    var name = withNames.caseVarNames + questionMark;

    var body = inner ?? "return ${withNames.singleName};";

    return body.wrap("if (this.matchRange(_range.\$$id) case $name) {", "}");
  }

  @override
  String visitRegExpNode(node, parameters) {
    /// Matches a regular expression against the input using `matchPattern`.
    ///
    /// Unique regex patterns are tracked and indexed in the `_regexp` table.
    var Parameters(isPassIfNull: isNullAllowed, :withNames, :inner) = parameters;
    var key = node.value;
    var id = regexpIds[key] ??= (regexps..add(key), ++regexpId).$2;
    var questionMark = isNullAllowed ? "" : "?";
    var name = withNames.caseVarNames + questionMark;

    var body = inner ?? "return ${withNames.singleName};";

    return body.wrap("if (this.matchPattern(_regexp.\$$id) case $name) {", "}");
  }

  @override
  String visitRegExpEscapeNode(node, parameters) {
    /// Matches a pre-defined regex escape sequence (like \d or \w).
    ///
    /// These are treated similarly to `RegExpNode` and sharing the `_regexp` lookup table.
    var Parameters(isPassIfNull: isNullAllowed, :withNames, :inner) = parameters;
    var pattern = node.pattern;
    var id = regexpIds[pattern] ??= (regexps..add(pattern), ++regexpId).$2;

    var questionMark = isNullAllowed ? "" : "?";
    var name = withNames.caseVarNames + questionMark;

    var body = inner ?? "return ${withNames.singleName};";

    return body.wrap("if (this.matchPattern(_regexp.\$$id) case $name) {", "}");
  }

  @override
  String visitSequenceNode(node, parameters) {
    /// Compiles a sequence of nodes (e.g., `A B C`).
    ///
    /// It handles:
    /// 1. Determining which nodes in the sequence need to be bound to variables.
    /// 2. Handling the `$` marker for selective result returning.
    /// 3. Recursively wrapping each node's generated code such that the next node in the sequence
    ///    only runs if the previous one succeeded.
    var Parameters(:withNames, :inner, :declarationName, :isMarked, :isCuttable) = parameters;

    var chosenIndex = node.chosenIndex;
    for (var (i, child) in node.children.indexed) {
      if (child case NamedNode(name: r"$")) {
        chosenIndex = i;
        break;
      }
    }

    var names = List.generate(node.children.length, (_) => {"_"});
    if (chosenIndex case var index?) {
      names[index].add("\$$index");
    } else if (inner == null) {
      /// If the inner is null, take it easy.
      ///   this just means that we expose all of them.
      ///   Also, there are no actions, so we don't need to worry about
      ///   naming them.

      for (var i = 0; i < names.length; ++i) {
        names[i].add("\$$i");
      }
    } else {
      for (var (i, child) in node.children.indexed) {
        if (child case NamedNode(:String name)) {
          /// If the node is named, then we just use the name.
          names[i].add(name);
        }

        if (withNames != null || inner.contains(RegExp("\\\$$i\\b"))) {
          /// If [withNames] is not null, (this whole sequence) has been named,
          ///   then we need to name the node.
          ///
          /// If the [inner] contains a reference to this node, then we need to
          ///   name it.
          names[i].add("\$$i");
        }
      }
    }

    var body =
        inner ?? //
        chosenIndex?.apply((v) => "return \$$v;") ??
        names.map((s) => s.singleName).join(", ").apply((v) => "return ($v);");

    if (withNames != null) {
      /// Since we have a name ordered by our parent, we need to expose
      ///   it to our [inner].

      var leftHand = switch (chosenIndex) {
        null => "[${names.map((s) => s.singleName).join(", ")}]",
        var choose => "\$$choose",
      };

      body = body.wrap("if ($leftHand case ${withNames.caseVarNames}) {", "}");
    }

    /// We essentially "wrap" the body by each node in the sequence in reverse.
    for (var (index, node) in node.children.indexed.toList().reversed) {
      var innerParameters = Parameters(
        withNames: names[index],
        inner: body,
        isPassIfNull: isPassIfNull(node, declarationName),
        declarationName: declarationName,
        isMarked: index == 0 && isMarked,
        isCuttable: isCuttable,
      );
      body = node.acceptParametrizedVisitor(this, innerParameters);
    }

    return body;
  }

  @override
  String visitChoiceNode(node, parameters) {
    var Parameters(
      isPassIfNull: isNullAllowed,
      :withNames,
      :inner,
      :declarationName,
      isMarked: markSaved,
    ) = parameters;

    // IsCutVisitor
    var body = [
      for (var (i, child) in node.children.indexed) ...[
        child.acceptParametrizedVisitor(
          this,
          Parameters(
            isPassIfNull: isPassIfNull(child, declarationName),
            withNames: withNames,
            inner: inner,
            declarationName: declarationName,
            isMarked: true,
            isCuttable: true,
          ),
        ),
        if (i < node.children.length - 1) ...[
          if (child.acceptSimpleVisitor(const IsCutVisitor()))
            "if (_mark.isCut) return null; else this._recover(_mark);"
          else
            "this._recover(_mark);",
        ],
      ],
    ].join("\n");
    if (!markSaved) {
      body = body.prepend("var _mark = this._mark();");
    }

    return body;
  }

  @override
  String visitCountedNode(node, parameters) {
    var Parameters(:withNames, :inner, :declarationName, isMarked: markSaved) = parameters;
    var variableName = "_${ruleId++}";
    var containerName = "_l${ruleId++}";

    /// If the node min is less than zero,
    ///   then we can structure the code to allow to pass without
    ///   parsing anything.
    if (node.min <= 0) {
      var question = isPassIfNull(node.child, declarationName) ? "" : "?";
      var loopIterationBody = node.child
          .acceptParametrizedVisitor(
            this,
            Parameters(
              withNames: {variableName},
              inner: "$containerName.add($variableName);\ncontinue;",
              isPassIfNull: isPassIfNull(node.child, declarationName),
              declarationName: declarationName,
              isMarked: true,
              isCuttable: false,
            ),
          )
          .append("this._recover(_mark);")
          .append("break;")
          .prepend("var _mark = this._mark();")
          .wrap(
            (node.max == null) //
                ? "for (;;) {"
                : "while ($containerName.length < ${node.max}) {",
            "}",
          )
          .wrap(
            "if ($containerName.isNotEmpty) {", //
            "} else {\n  this._recover(_mark);\n}",
          )
          .prepend(
            "var $containerName = [if "
            "($variableName case "
            "var $variableName$question) "
            "$variableName];",
          )
          .append(
            (inner ?? "return $containerName").wrap(
              "if ($containerName case ${withNames.caseVarNames}) {",
              "}",
            ),
          )
          .prepend("var _mark = this._mark();");

      return node.child.acceptParametrizedVisitor(
        this,
        Parameters(
          withNames: {variableName},
          isPassIfNull: true,
          inner: loopIterationBody,
          declarationName: declarationName,
          isMarked: markSaved,
          isCuttable: false,
        ),
      );
    } else {
      var loopIterationBody = node.child
          .acceptParametrizedVisitor(
            this,
            Parameters(
              withNames: {variableName},
              inner: "$containerName.add($variableName);\ncontinue;",
              isPassIfNull: isPassIfNull(node.child, declarationName),
              declarationName: declarationName,
              isMarked: true,
              isCuttable: false,
            ),
          )
          .append("this._recover(_mark);")
          .append("break;")
          .prepend("var _mark = this._mark();")
          .wrap(
            (node.max == null) //
                ? "for (;;) {"
                : "while ($containerName.length < ${node.max}) {",
            "}",
          )
          .append("$containerName = null;".wrap("if ($containerName.length < ${node.min}) {", "}"))
          .wrap("if ($containerName != null) {", "}")
          .append(
            (inner ?? "return $containerName;").wrap(
              "if ($containerName case ${withNames.caseVarNames}?) {",
              "}",
            ),
          )
          .wrap("if ([$variableName].nullable() case var $containerName) {", "}");

      return node.child.acceptParametrizedVisitor(
        this,
        Parameters(
          withNames: {variableName},
          inner: loopIterationBody,
          isPassIfNull: isPassIfNull(node.child, declarationName),
          declarationName: declarationName,
          isMarked: markSaved,
          isCuttable: false,
        ),
      );
    }
  }

  @override
  String visitPlusSeparatedNode(node, parameters) {
    var Parameters(:withNames, :inner, :declarationName, isMarked: markSaved) = parameters;
    var variableName = "_${ruleId++}";
    var containerName = "_l${ruleId++}";
    (withNames ??= <String>{}).add(containerName);

    var loopBuffer = StringBuffer();
    loopBuffer.writeln("if ([$variableName] case ${withNames.caseVarNames}) {");
    loopBuffer.writeln("  for (;;) {");
    loopBuffer.writeln("    var _mark = this._mark();");
    loopBuffer.writeln(
      node.separator
          .acceptParametrizedVisitor(
            this,
            Parameters(
              isPassIfNull: isPassIfNull(node.separator, declarationName),
              withNames: {"_"},
              inner: node.child.acceptParametrizedVisitor(
                this,
                Parameters(
                  withNames: {variableName},
                  inner: "$containerName.add($variableName);\ncontinue;",
                  isPassIfNull: isPassIfNull(node.child, declarationName),
                  declarationName: declarationName,
                  isMarked: false,
                  isCuttable: false,
                ),
              ),
              declarationName: declarationName,
              isMarked: true,
              isCuttable: false,
            ),
          )
          .indent(2),
    );
    loopBuffer.writeln("    this._recover(_mark);");
    loopBuffer.writeln("    break;");
    loopBuffer.writeln("  }");
    if (node.isTrailingAllowed) {
      loopBuffer.writeln("  var _mark = this._mark();");
      loopBuffer.writeln(
        node.separator
            .acceptParametrizedVisitor(
              this,
              Parameters(
                isPassIfNull: true,
                withNames: {"null"},
                inner: "this._recover(_mark);",
                declarationName: declarationName,
                isMarked: true,
                isCuttable: false,
              ),
            )
            .indent(),
      );
    }
    loopBuffer.writeln(inner?.indent() ?? "return $containerName;".indent());
    loopBuffer.writeln("}");

    return node.child.acceptParametrizedVisitor(
      this,
      Parameters(
        withNames: {variableName},
        inner: loopBuffer.toString(),
        isPassIfNull: isPassIfNull(node.child, declarationName),
        declarationName: declarationName,
        isMarked: markSaved,
        isCuttable: false,
      ),
    );
  }

  @override
  String visitStarSeparatedNode(node, parameters) {
    var Parameters(:withNames, :inner, :declarationName, isMarked: markSaved) = parameters;
    var variableName = "_${ruleId++}";
    var containerName = "_l${ruleId++}";
    (withNames ??= <String>{}).add(containerName);

    var question = isPassIfNull(node.child, declarationName) ? "" : "?";
    var loopBuffer = StringBuffer();
    loopBuffer.writeln(
      "if ([if ($variableName case var $variableName$question) $variableName] "
      "case ${withNames.caseVarNames}) {",
    );
    loopBuffer.writeln("  if (${withNames.singleName}.isNotEmpty) {");
    loopBuffer.writeln("    for (;;) {");
    loopBuffer.writeln("      var _mark = this._mark();");
    loopBuffer.writeln(
      node.separator
          .acceptParametrizedVisitor(
            this,
            Parameters(
              withNames: {"_"},
              inner: node.child.acceptParametrizedVisitor(
                this,
                Parameters(
                  withNames: {variableName},
                  inner: "$containerName.add($variableName);\ncontinue;",
                  isPassIfNull: isPassIfNull(node.child, declarationName),
                  declarationName: declarationName,
                  isMarked: false,
                  isCuttable: false,
                ),
              ),
              isPassIfNull: isPassIfNull(node.separator, declarationName),
              declarationName: declarationName,
              isMarked: true,
              isCuttable: false,
            ),
          )
          .indent(4),
    );
    loopBuffer.writeln("      this._recover(_mark);");
    loopBuffer.writeln("      break;");
    loopBuffer.writeln("    }");

    if (node.isTrailingAllowed) {
      loopBuffer.writeln("    var _mark = this._mark();");
      loopBuffer.writeln(
        node.separator
            .acceptParametrizedVisitor(
              this,
              Parameters(
                isPassIfNull: true,
                withNames: {"null"},
                inner: "this._recover(_mark);",
                declarationName: declarationName,
                isMarked: true,
                isCuttable: false,
              ),
            )
            .indent(2),
      );
    }
    loopBuffer.writeln("  } else {");
    loopBuffer.writeln("    this._recover(_mark);");
    loopBuffer.writeln("  }");
    if (inner case var inner?) {
      loopBuffer.writeln(inner.indent());
    } else {
      loopBuffer.writeln("  return $containerName;");
    }
    loopBuffer.writeln("}");

    var fullBuffer = node.child.acceptParametrizedVisitor(
      this,
      Parameters(
        withNames: {variableName},
        isPassIfNull: true,
        inner: loopBuffer.toString(),
        declarationName: declarationName,
        isMarked: true,
        isCuttable: false,
      ),
    );

    if (!markSaved) {
      fullBuffer = fullBuffer.prepend("var _mark = this._mark();");
    }

    return fullBuffer;
  }

  @override
  String visitPlusNode(node, parameters) {
    var Parameters(:withNames, :inner, :declarationName, isMarked: markSaved) = parameters;
    var variableName = "_${ruleId++}";
    var containerName = "_l${ruleId++}";
    (withNames ??= {}).add(containerName);

    var loopBuffer = StringBuffer();
    loopBuffer
      ..writeln("if ([$variableName] case ${withNames.caseVarNames}) {")
      ..writeln("  for (;;) {")
      ..writeln("    var _mark = this._mark();")
      ..writeln(
        node.child
            .acceptParametrizedVisitor(
              this,
              Parameters(
                withNames: {variableName},
                inner: "$containerName.add($variableName);\ncontinue;",
                isPassIfNull: isPassIfNull(node.child, declarationName),
                declarationName: declarationName,
                isMarked: true,
                isCuttable: false,
              ),
            )
            .indent(2),
      )
      ..writeln("    this._recover(_mark);")
      ..writeln("    break;")
      ..writeln("  }")
      ..writeln(inner?.indent() ?? "return $containerName;".indent())
      ..writeln("}");

    return node.child.acceptParametrizedVisitor(
      this,
      Parameters(
        withNames: {variableName},
        inner: loopBuffer.toString(),
        isPassIfNull: isPassIfNull(node.child, declarationName),
        declarationName: declarationName,
        isMarked: markSaved,
        isCuttable: false,
      ),
    );
  }

  @override
  String visitStarNode(node, parameters) {
    var Parameters(:withNames, :inner, :declarationName, isMarked: markSaved) = parameters;
    var variableName = "_${ruleId++}";
    var containerName = "_l${ruleId++}";
    (withNames ??= {}).add(containerName);

    var question = isPassIfNull(node.child, declarationName) ? "" : "?";
    var loopBuffer = StringBuffer();
    loopBuffer
      ..writeln(
        "if ([if ($variableName case var $variableName$question) $variableName] "
        "case ${withNames.caseVarNames}) {",
      )
      ..writeln("  if ($containerName.isNotEmpty) {")
      ..writeln("    for (;;) {")
      ..writeln("      var _mark = this._mark();")
      ..writeln(
        node.child
            .acceptParametrizedVisitor(
              this,
              Parameters(
                withNames: {variableName},
                inner: "$containerName.add($variableName);\ncontinue;",
                isPassIfNull: isPassIfNull(node.child, declarationName),
                declarationName: declarationName,
                isMarked: true,
                isCuttable: false,
              ),
            )
            .indent(3),
      )
      ..writeln("      this._recover(_mark);")
      ..writeln("      break;")
      ..writeln("    }")
      ..writeln("  } else {")
      ..writeln("    this._recover(_mark);")
      ..writeln("  }")
      ..writeln(inner?.indent() ?? "  return $containerName;")
      ..writeln("}");

    var fullBuffer = StringBuffer();
    if (!markSaved) {
      fullBuffer.writeln("var _mark = this._mark();");
    }
    fullBuffer.writeln(
      node.child
          .acceptParametrizedVisitor(
            this,
            Parameters(
              withNames: {variableName},
              isPassIfNull: true,
              inner: loopBuffer.toString(),
              declarationName: declarationName,
              isMarked: true,
              isCuttable: false,
            ),
          )
          .indent(1, !markSaved),
    );

    return fullBuffer.toString();
  }

  @override
  String visitAndPredicateNode(node, parameters) {
    var Parameters(:withNames, :inner, :declarationName, isMarked: markSaved) = parameters;
    var buffer = [
      if (!markSaved) "var _mark = this._mark();",
      node.child.acceptParametrizedVisitor(
        this,
        Parameters(
          withNames: withNames,
          inner: "this._recover(_mark);\n${inner ?? ""}",
          isPassIfNull: isPassIfNull(node.child, declarationName),
          declarationName: declarationName,
          isMarked: true,
          isCuttable: false,
        ),
      ),
    ];

    return buffer.join("\n");
  }

  @override
  String visitNotPredicateNode(node, parameters) {
    var Parameters(:withNames, :inner, :declarationName, isMarked: markSaved) = parameters;
    var buffer = StringBuffer();

    if (!markSaved) {
      buffer.writeln("var _mark = this._mark();");
    }
    buffer.writeln(
      node.child.acceptParametrizedVisitor(
        this,
        Parameters(
          isPassIfNull: true,
          withNames: {...?withNames, "null"},
          inner: "this._recover(_mark);\n${inner ?? "return null;"}",
          declarationName: declarationName,
          isMarked: true,
          isCuttable: false,
        ),
      ),
    );

    return buffer.toString();
  }

  @override
  String visitOptionalNode(node, parameters) {
    var Parameters(:withNames, :inner, :declarationName, isMarked: markSaved) = parameters;
    return node.child.acceptParametrizedVisitor(
      this,
      Parameters(
        withNames: withNames,
        inner: inner,
        isPassIfNull: true,
        declarationName: declarationName,
        isMarked: markSaved,
        isCuttable: false,
      ),
    );
  }

  @override
  String visitExceptNode(node, parameters) {
    var Parameters(:withNames, :inner, :declarationName, isMarked: markSaved) = parameters;
    var buffer = StringBuffer();
    if (!markSaved) {
      buffer.writeln("var _mark = this._mark();");
    }
    buffer.writeln(
      node.child.acceptParametrizedVisitor(
        this,
        Parameters(
          isPassIfNull: true,
          withNames: {"null"},
          inner:
              (StringBuffer()
                    ..writeln("this._recover(_mark);")
                    ..writeln("if (this.pos < this.buffer.length) {")
                    ..writeAll(switch (withNames.caseVarNames) {
                      "_" => [
                        "  this.pos++;",
                        inner?.indent() ?? "  return this.buffer[this.pos - 1];",
                        "",
                      ],
                      var names => [
                        "  if (this.buffer[this.pos++] case $names) {",
                        inner?.indent(2) ?? "    return ${withNames.singleName};",
                        "  }",
                        "",
                      ],
                    }, "\n")
                    ..writeln("}"))
                  .toString(),
          declarationName: declarationName,
          isMarked: true,
          isCuttable: false,
        ),
      ),
    );

    return buffer.toString();
  }

  @override
  String visitReferenceNode(node, parameters) {
    var Parameters(isPassIfNull: isNullAllowed, :withNames, :inner, :declarationName) = parameters;
    var ruleName = node.ruleName;
    var mark = isPassIfNull(node, declarationName) ? "!" : "";
    var questionMark = isNullAllowed ? "" : "?";

    var buffer = [
      "if (this.apply(this.$ruleName)$mark case ${withNames.caseVarNames}$questionMark) {",
      inner?.indent() ?? "return ${withNames.singleName};".indent(),
      "}",
    ];

    return buffer.join("\n");
  }

  @override
  String visitFragmentNode(node, parameters) {
    var Parameters(isPassIfNull: isNullAllowed, :withNames, :inner) = parameters;
    var buffer = [
      "if (this.${node.fragmentName}() case ${withNames.caseVarNames}${isNullAllowed ? "" : "?"}) {",
      inner?.indent() ?? "return ${withNames.singleName};".indent(),
      "}",
    ];

    return buffer.join("\n");
  }

  @override
  String visitNamedNode(node, parameters) {
    var Parameters(
      isPassIfNull: isNullAllowed,
      :withNames,
      :inner,
      :declarationName,
      isMarked: markSaved,
    ) = parameters;

    return node.child.acceptParametrizedVisitor(
      this,
      Parameters(
        isPassIfNull: isNullAllowed,
        withNames: {...?withNames, node.name},
        inner: inner,
        declarationName: declarationName,
        isMarked: markSaved,
        isCuttable: false,
      ),
    );
  }

  @override
  String visitActionNode(node, parameters) {
    var Parameters(:withNames, :declarationName, isMarked: markSaved) = parameters;

    if (node.action.contains(RegExp(r"\b\$(?![A-Za-z0-9_\$\{])"))) {
      (withNames ??= {}).add(r"$");
    }

    var inner = node.action;
    if (node.isSpanUsed) {
      inner =
          (StringBuffer()
                ..writeln(
                  "if (this.buffer.substring(from, to) case var ${withNames.caseVarNames}) {",
                )
                ..writeln(inner.indent())
                ..writeln("}"))
              .toString();
    }

    if (node.areIndicesProvided || node.isSpanUsed) {
      inner =
          (StringBuffer()
                ..writeln("if (this.pos case var to) {")
                ..writeln(inner.indent())
                ..writeln("}"))
              .toString();
    }

    var body = node.child.acceptParametrizedVisitor(
      this,
      Parameters(
        withNames: withNames,
        inner: inner,
        isPassIfNull: isPassIfNull(node.child, declarationName),
        declarationName: declarationName,
        isMarked: markSaved,
        isCuttable: false,
      ),
    );

    if (node.areIndicesProvided || node.isSpanUsed) {
      body =
          (StringBuffer()
                ..writeln("if (this.pos case var from) {")
                ..writeln(body.indent())
                ..writeln("}"))
              .toString();
    }

    return body;
  }

  @override
  String visitInlineActionNode(node, parameters) {
    var Parameters(:withNames, :declarationName, isMarked: markSaved) = parameters;

    if (node.action.contains(RegExp(r"\$(?![A-Za-z0-9_\$\{])"))) {
      (withNames ??= {}).add(r"$");
    }

    var inner = "return ${node.action};";

    if (node.isSpanUsed) {
      inner =
          (StringBuffer()
                ..writeln("if (this.buffer.substring(from, to) case var span) {")
                ..writeln(inner.indent())
                ..writeln("}"))
              .toString();
    }

    if (node.areIndicesProvided || node.isSpanUsed) {
      inner =
          (StringBuffer()
                ..writeln("if (this.pos case var to) {")
                ..writeln(inner.indent())
                ..writeln("}"))
              .toString();
    }

    var body = node.child.acceptParametrizedVisitor(
      this,
      Parameters(
        withNames: withNames,
        inner: inner,
        isPassIfNull: isPassIfNull(node.child, declarationName),
        declarationName: declarationName,
        isMarked: markSaved,
        isCuttable: false,
      ),
    );

    if (node.areIndicesProvided || node.isSpanUsed) {
      body =
          (StringBuffer()
                ..writeln("if (this.pos case var from) {")
                ..writeln(body.indent())
                ..writeln("}"))
              .toString();
    }

    return body;
  }

  @override
  String visitStartOfInputNode(node, parameters) {
    var Parameters(:withNames, :inner) = parameters;
    var buffer = switch (withNames.caseVarNames) {
      "_" => ["if (this.pos <= 0) {", inner?.indent() ?? "return this.pos".indent(), "}"],
      String names => [
        "if (this.pos case $names && <= 0) {",
        inner?.indent() ?? "return ${withNames.singleName}".indent(),
        "}",
      ],
    };

    return buffer.join("\n");
  }

  @override
  String visitEndOfInputNode(node, parameters) {
    var Parameters(:withNames, :inner) = parameters;
    var buffer = switch (withNames.caseVarNames) {
      "_" => [
        "if (this.pos >= this.buffer.length) {",
        inner?.indent() ?? "return this.pos;".indent(),
        "}",
      ],
      String names => [
        "if (this.pos case $names when this.pos >= this.buffer.length) {",
        inner?.indent() ?? "return ${withNames.singleName};".indent(),
        "}",
      ],
    };

    return buffer.join("\n");
  }

  @override
  String visitAnyCharacterNode(node, parameters) {
    var Parameters(:withNames, :inner) = parameters;
    var buffer = [
      "if (this.pos < this.buffer.length) {",
      ...switch (withNames.caseVarNames) {
        "_" => ["  this.pos++;", inner?.indent() ?? "  return this.buffer[this.pos - 1];"],
        String names => [
          "  if (this.buffer[this.pos++] case $names) {",
          inner?.indent(2) ?? "    return ${withNames.singleName};",
          "  }",
        ],
      },
      "}",
    ];
    return buffer.join("\n");
  }
}

extension WrapString on String {
  String wrap(String top, String bottom) =>
      (StringBuffer()
            ..writeln(top)
            ..writeln(indent())
            ..write(bottom))
          .toString();

  String append(String body) =>
      (StringBuffer()
            ..writeln(this)
            ..write(body))
          .toString();

  String prepend(String body) =>
      (StringBuffer()
            ..writeln(body)
            ..write(this))
          .toString();
}
