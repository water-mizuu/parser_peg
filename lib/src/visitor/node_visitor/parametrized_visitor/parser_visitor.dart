// ignore_for_file: always_specify_types

import "dart:convert";

import "package:parser_peg/src/generator.dart";
import "package:parser_peg/src/node.dart";
import "package:parser_peg/src/visitor/node_visitor.dart";

class Parameters {
  const Parameters({
    required this.isNullAllowed,
    required this.withNames,
    required this.inner,
    required this.reported,
    required this.declarationName,
    required this.markSaved,
  });

  final bool isNullAllowed;
  final Set<String>? withNames;
  final String? inner;
  final bool reported;
  final String declarationName;
  final bool markSaved;
}

String encode(Object object) => jsonEncode(object).replaceAll(r"$", r"\$");

/// This visitor compiles the parser grammar into a Dart function.
class ParserCompilerVisitor implements ParametrizedNodeVisitor<String, Parameters> {
  ParserCompilerVisitor({required this.isNullable});

  bool Function(Node, String) isNullable;

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
  String visitEpsilonNode(node, parameters) {
    var Parameters(:isNullAllowed, :withNames, :inner) = parameters;
    var buffer = [
      "if ('' case ${withNames.varNames}${isNullAllowed ? "" : "?"}) {",
      if (inner != null) //
        inner.indent()
      else
        "return ${withNames.singleName};".indent(),
      "}",
    ];

    return buffer.join("\n");
  }

  @override
  String visitTriePatternNode(node, parameters) {
    var Parameters(:isNullAllowed, :withNames, :inner) = parameters;
    var key = jsonEncode(node.options);
    var id = trieIds[key] ??= (tries..add(node.options), ++trieId).$2;
    var buffer = [
      "if (this.matchTrie(_trie.\$$id) case ${withNames.varNames}${isNullAllowed ? "" : "?"}) {",
      if (inner != null) //
        inner.indent()
      else
        "return ${withNames.singleName};".indent(),
      "}",
    ];

    return buffer.join("\n");
  }

  @override
  String visitStringLiteralNode(node, parameters) {
    var Parameters(:isNullAllowed, :withNames, :inner) = parameters;
    var key = node.literal;
    var id = stringIds[key] ??= (strings..add(node.literal), ++stringId).$2;
    var buffer = [
      "if (this.matchPattern(_string.\$$id) case ${withNames.varNames}${isNullAllowed ? "" : "?"}) {",
      if (inner != null) //
        inner.indent()
      else
        "return ${withNames.singleName};".indent(),
      "}",
    ];
    return buffer.join("\n");
  }

  @override
  String visitRangeNode(node, parameters) {
    var Parameters(:isNullAllowed, :withNames, :inner) = parameters;
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
    var buffer = [
      "if (this.matchRange(_range.\$$id) case ${withNames.varNames}${isNullAllowed ? "" : "?"}) {",
      if (inner != null) //
        inner.indent()
      else
        "return ${withNames.singleName};".indent(),
      "}",
    ];

    return buffer.join("\n");
  }

  @override
  String visitRegExpNode(node, parameters) {
    var Parameters(:isNullAllowed, :withNames, :inner) = parameters;
    var key = node.value;
    var id = regexpIds[key] ??= (regexps..add(key), ++regexpId).$2;
    var buffer = [
      "if (matchPattern(_regexp.\$$id) case ${withNames.varNames}${isNullAllowed ? "" : "?"}) {",
      if (inner != null) //
        inner.indent()
      else
        "return ${withNames.singleName};".indent(),
      "}",
    ];

    return buffer.join("\n");
  }

  @override
  String visitRegExpEscapeNode(node, parameters) {
    var Parameters(:isNullAllowed, :withNames, :inner) = parameters;
    var pattern = node.pattern;
    var id = regexpIds[pattern] ??= (regexps..add(pattern), ++regexpId).$2;
    var buffer = [
      "if (matchPattern(_regexp.\$$id) case ${withNames.varNames}${isNullAllowed ? "" : "?"}) {",
      if (inner != null) //
        inner.indent()
      else
        "return ${withNames.singleName};".indent(),
      "}",
    ];

    return buffer.join("\n");
  }

  @override
  String visitSequenceNode(node, parameters) {
    var Parameters(:withNames, :inner, :reported, :declarationName) = parameters;

    /// This is a list of names that are used to name the result of a match.
    var names = [
      /// If the inner is null, take it easy.
      if (inner == null) ...[
        /// If there aren't any chosen items, then we name all of them.
        if (node.chosenIndex == null)
          for (var i = 0; i < node.children.length; ++i) "\$$i"
        /// If there is a chosen item, then just name that one.
        else
          for (var i = 0; i < node.children.length; ++i)
            if (node.chosenIndex == i) "\$$i" else "_",
      ]
      /// Since there is an inner, we must be more careful.
      else ...[
        for (var (i, child) in node.children.indexed)
          /// If a child is named, then obviously we name them as is.
          if (child case NamedNode(:String name))
            name //
          else ...[
            /// If we're not choosing anything, then we *MIGHT* need to use it.
            if (node.chosenIndex != null) ...[
              /// If we're not naming our result, then we *won't* need it.
              if (withNames == null)
                "_"
              /// Else, we just add a name.
              else
                "\$$i",
            ] else ...[
              /// If we're going to use this, then we need to name it.
              if (inner.contains(
                RegExp(
                  r"\$"
                  "$i"
                  r"\b",
                ),
              ))
                "\$$i"
              /// If we won't name our general result, then we won't need it.
              else if (withNames == null)
                "_"
              /// Else, we just add a name.
              else
                "\$$i",
            ],
          ],
      ],
    ];

    var lowestInner =
        inner ?? //
        node.chosenIndex?.apply((v) => "return \$$v;") ??
        names.join(", ").apply((v) => "return ($v);");

    var aliased = switch (withNames) {
      null => lowestInner,
      var withNames => switch (node.chosenIndex) {
        null =>
          "if ([${names.join(", ")}] case ${withNames.varNames}) {\n${lowestInner.indent()}\n}",
        var choose => "if (\$$choose case ${withNames.varNames}) {\n${lowestInner.indent()}\n}",
      },
    };

    var body = aliased;

    /// We essentially "wrap" the body by each node in the sequence in reverse.
    for (var (index, node) in node.children.indexed.toList().reversed) {
      var innerParameters = Parameters(
        withNames: {names[index]},
        inner: body,
        isNullAllowed: isNullable.call(node, declarationName),
        reported: reported,
        declarationName: declarationName,
        markSaved: false,
      );
      body = node.acceptParametrizedVisitor(this, innerParameters);
    }

    return body;
  }

  @override
  String visitChoiceNode(node, parameters) {
    var Parameters(:isNullAllowed, :withNames, :inner, :reported, :declarationName, :markSaved) =
        parameters;
    var buffer = [
      if (!markSaved) "if (this.pos case var mark) {",
      [
        for (var (i, child) in node.children.indexed) ...[
          if (i > 0) "this.pos = mark;",

          child.acceptParametrizedVisitor(
            this,
            Parameters(
              isNullAllowed: isNullAllowed,
              withNames: withNames,
              inner: inner,
              reported: reported,
              declarationName: declarationName,
              markSaved: true,
            ),
          ), //
        ],
      ].join("\n").indent(1, !markSaved),
      if (!markSaved) "}",
    ];

    return buffer.join("\n");
  }

  @override
  String visitCountedNode(node, parameters) {
    var Parameters(:withNames, :inner, :reported, :declarationName, :markSaved) = parameters;
    var variableName = "_${ruleId++}";
    var containerName = "_l${ruleId++}";

    if (node.min > 0) {
      var loopBuffer = StringBuffer();
      loopBuffer.writeln("if ([$variableName].asNullable() case var $containerName) {");
      loopBuffer.writeln("  if ($containerName != null) {");
      if (node.max == null) {
        loopBuffer.writeln("    for (;;) {");
      } else {
        loopBuffer.writeln("    while ($containerName.length < ${node.max}) {");
      }
      loopBuffer.writeln("      if (this.pos case var mark) {");
      loopBuffer.writeln(
        node.child
            .acceptParametrizedVisitor(
              this,
              Parameters(
                withNames: {variableName},
                inner: "$containerName.add($variableName);\ncontinue;",
                isNullAllowed: isNullable(node.child, declarationName),
                reported: reported,
                declarationName: declarationName,
                markSaved: true,
              ),
            )
            .indent(4),
      );
      loopBuffer.writeln("        this.pos = mark;");
      loopBuffer.writeln("        break;");
      loopBuffer.writeln("      }");
      loopBuffer.writeln("    }");
      if (node.min > 1) {
        loopBuffer.writeln("    if ($containerName.length < ${node.min}) {");
        loopBuffer.writeln("      $containerName = null;");
        loopBuffer.writeln("    }");
      }
      loopBuffer.writeln("  }");
      loopBuffer.writeln("  if ($containerName case ${withNames.varNames}) {");
      if (inner != null) {
        loopBuffer.writeln(inner.indent(2));
      } else {
        loopBuffer.writeln("    return $containerName;");
      }
      loopBuffer.writeln("  }");
      loopBuffer.writeln("}");

      return node.child.acceptParametrizedVisitor(
        this,
        Parameters(
          withNames: {variableName},
          inner: loopBuffer.toString(),
          isNullAllowed: isNullable(node.child, declarationName),
          reported: reported,
          declarationName: declarationName,
          markSaved: markSaved,
        ),
      );
    } else {
      var loopBody = node.child
          .acceptParametrizedVisitor(
            this,
            Parameters(
              withNames: {variableName},
              inner: "$containerName.add($variableName);\ncontinue;",
              isNullAllowed: isNullable(node.child, declarationName),
              reported: reported,
              declarationName: declarationName,
              markSaved: true,
            ),
          )
          .indent(5);
      var question = isNullable(node.child, declarationName) ? "" : "?";
      var loopBuffer = StringBuffer();
      loopBuffer.writeln("if (this.pos case var mark) {");
      loopBuffer.writeln(
        "  "
        "if ([if ($variableName case var $variableName$question) $variableName].asNullable() "
        "case var $containerName) {",
      );
      loopBuffer.writeln("    if ($containerName != null && $containerName.isNotEmpty) {");
      if (node.max == null) {
        loopBuffer.writeln("      for (;;) {");
      } else {
        loopBuffer.writeln("      while ($containerName.length < ${node.max}) {");
      }
      loopBuffer.writeln("        if (this.pos case var mark) {");
      loopBuffer.writeln(loopBody);
      loopBuffer.writeln("          this.pos = mark;");
      loopBuffer.writeln("          break;");
      loopBuffer.writeln("        }");
      loopBuffer.writeln("      }");
      loopBuffer.writeln("    } else {");
      loopBuffer.writeln("      this.pos = mark;");
      loopBuffer.writeln("    }");
      loopBuffer.writeln("    if ($containerName case ${withNames.varNames}) {");
      if (inner case var inner?) {
        loopBuffer.writeln(inner.indent(3));
      } else {
        loopBuffer.writeln("      return $containerName;");
      }
      loopBuffer.writeln("    }");
      loopBuffer.writeln("  }");
      loopBuffer.writeln("}");

      return node.child.acceptParametrizedVisitor(
        this,
        Parameters(
          withNames: {variableName},
          isNullAllowed: true,
          inner: loopBuffer.toString(),
          reported: reported,
          declarationName: declarationName,
          markSaved: markSaved,
        ),
      );
    }
  }

  @override
  String visitPlusSeparatedNode(node, parameters) {
    var Parameters(:withNames, :inner, :reported, :declarationName, :markSaved) = parameters;
    var variableName = "_${ruleId++}";
    var containerName = "_l${ruleId++}";
    (withNames ??= <String>{}).add(containerName);

    late var trailingBody = node.separator
        .acceptParametrizedVisitor(
          this,
          Parameters(
            isNullAllowed: true,
            withNames: {"null"},
            inner: "this.pos = mark;",
            reported: reported,
            declarationName: declarationName,
            markSaved: true,
          ),
        )
        .indent(2);
    var loopBuffer = StringBuffer();
    loopBuffer.writeln("if ([$variableName] case ${withNames.varNames}) {");
    loopBuffer.writeln("  for (;;) {");
    loopBuffer.writeln("    if (this.pos case var mark) {");
    loopBuffer.writeln(
      node.separator
          .acceptParametrizedVisitor(
            this,
            Parameters(
              isNullAllowed: isNullable(node.separator, declarationName),
              withNames: {"_"},
              inner: node.child.acceptParametrizedVisitor(
                this,
                Parameters(
                  withNames: {variableName},
                  inner: "$containerName.add($variableName);\ncontinue;",
                  isNullAllowed: isNullable(node.child, declarationName),
                  reported: reported,
                  declarationName: declarationName,
                  markSaved: false,
                ),
              ),
              reported: reported,
              declarationName: declarationName,
              markSaved: true,
            ),
          )
          .indent(3),
    );
    loopBuffer.writeln("      this.pos = mark;");
    loopBuffer.writeln("      break;");
    loopBuffer.writeln("    }");
    loopBuffer.writeln("  }");
    if (node.isTrailingAllowed) {
      loopBuffer.writeln("  if (this.pos case var mark) {");
      loopBuffer.writeln(trailingBody);
      loopBuffer.writeln("  }");
    }
    if (inner != null) {
      loopBuffer.writeln(inner.indent());
    } else {
      loopBuffer.writeln("return $containerName;".indent());
    }
    loopBuffer.writeln("}");

    return node.child.acceptParametrizedVisitor(
      this,
      Parameters(
        withNames: {variableName},
        inner: loopBuffer.toString(),
        isNullAllowed: isNullable(node.child, declarationName),
        reported: reported,
        declarationName: declarationName,
        markSaved: markSaved,
      ),
    );
  }

  @override
  String visitStarSeparatedNode(node, parameters) {
    var Parameters(:withNames, :inner, :reported, :declarationName, :markSaved) = parameters;
    var variableName = "_${ruleId++}";
    var containerName = "_l${ruleId++}";
    (withNames ??= <String>{}).add(containerName);

    var question = isNullable(node.child, declarationName) ? "" : "?";
    var loopBuffer = StringBuffer();
    loopBuffer.writeln(
      "if ([if ($variableName case var $variableName$question) $variableName] "
      "case ${withNames.varNames}) {",
    );
    loopBuffer.writeln("  if (${withNames.singleName}.isNotEmpty) {");
    loopBuffer.writeln("    for (;;) {");
    loopBuffer.writeln("      if (this.pos case var mark) {");
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
                  isNullAllowed: isNullable(node.child, declarationName),
                  reported: reported,
                  declarationName: declarationName,
                  markSaved: false,
                ),
              ),
              isNullAllowed: isNullable(node.separator, declarationName),
              reported: reported,
              declarationName: declarationName,
              markSaved: true,
            ),
          )
          .indent(5),
    );
    loopBuffer.writeln("        this.pos = mark;");
    loopBuffer.writeln("        break;");
    loopBuffer.writeln("      }");
    loopBuffer.writeln("    }");
    if (!isNullable(node, declarationName) && node.isTrailingAllowed) {
      loopBuffer.writeln("    if (this.pos case var mark) {");
      loopBuffer.writeln(
        node.separator
            .acceptParametrizedVisitor(
              this,
              Parameters(
                isNullAllowed: true,
                withNames: {"null"},
                inner: "this.pos = mark;",
                reported: reported,
                declarationName: declarationName,
                markSaved: true,
              ),
            )
            .indent(3),
      );
      loopBuffer.writeln("    }");
    }
    loopBuffer.writeln("  } else {");
    loopBuffer.writeln("    this.pos = mark;");
    loopBuffer.writeln("  }");
    if (inner case var inner?) {
      loopBuffer.writeln(inner.indent());
    } else {
      loopBuffer.writeln("  return $containerName;");
    }
    loopBuffer.writeln("}");

    var fullBuffer = StringBuffer();
    if (!markSaved) {
      fullBuffer.writeln("if (this.pos case var mark) {");
    }
    fullBuffer.writeln(
      node.child
          .acceptParametrizedVisitor(
            this,
            Parameters(
              withNames: {variableName},
              isNullAllowed: true,
              inner: loopBuffer.toString(),
              reported: reported,
              declarationName: declarationName,
              markSaved: true,
            ),
          )
          .indent(1, !markSaved),
    );
    if (!markSaved) {
      fullBuffer.writeln("}");
    }

    return fullBuffer.toString();
  }

  @override
  String visitPlusNode(node, parameters) {
    var Parameters(:withNames, :inner, :reported, :declarationName, :markSaved) = parameters;
    var variableName = "_${ruleId++}";
    var containerName = "_l${ruleId++}";
    (withNames ??= {}).add(containerName);

    var loopBuffer = StringBuffer();
    loopBuffer.writeln("if ([$variableName] case ${withNames.varNames}) {");
    loopBuffer.writeln("  for (;;) {");
    loopBuffer.writeln("    if (this.pos case var mark) {");
    loopBuffer.writeln(
      node.child
          .acceptParametrizedVisitor(
            this,
            Parameters(
              withNames: {variableName},
              inner: "$containerName.add($variableName);\ncontinue;",
              isNullAllowed: isNullable(node.child, declarationName),
              reported: reported,
              declarationName: declarationName,
              markSaved: true,
            ),
          )
          .indent(3),
    );
    loopBuffer.writeln("      this.pos = mark;");
    loopBuffer.writeln("      break;");
    loopBuffer.writeln("    }");
    loopBuffer.writeln("  }");
    if (inner != null) {
      loopBuffer.writeln(inner.indent());
    } else {
      loopBuffer.writeln("return $containerName;".indent());
    }
    loopBuffer.writeln("}");

    return node.child.acceptParametrizedVisitor(
      this,
      Parameters(
        withNames: {variableName},
        inner: loopBuffer.toString(),
        isNullAllowed: isNullable(node.child, declarationName),
        reported: reported,
        declarationName: declarationName,
        markSaved: markSaved,
      ),
    );
  }

  @override
  String visitStarNode(node, parameters) {
    var Parameters(:withNames, :inner, :reported, :declarationName, :markSaved) = parameters;
    var variableName = "_${ruleId++}";
    var containerName = "_l${ruleId++}";
    (withNames ??= {}).add(containerName);

    var question = isNullable(node.child, declarationName) ? "" : "?";
    var loopBuffer = StringBuffer();
    loopBuffer.writeln(
      "if ([if ($variableName case var $variableName$question) $variableName] "
      "case ${withNames.varNames}) {",
    );
    loopBuffer.writeln("  if ($containerName.isNotEmpty) {");
    loopBuffer.writeln("    for (;;) {");
    loopBuffer.writeln("      if (this.pos case var mark) {");
    loopBuffer.writeln(
      node.child
          .acceptParametrizedVisitor(
            this,
            Parameters(
              withNames: {variableName},
              inner: "$containerName.add($variableName);\ncontinue;",
              isNullAllowed: isNullable(node.child, declarationName),
              reported: reported,
              declarationName: declarationName,
              markSaved: true,
            ),
          )
          .indent(4),
    );
    loopBuffer.writeln("        this.pos = mark;");
    loopBuffer.writeln("        break;");
    loopBuffer.writeln("      }");
    loopBuffer.writeln("    }");
    loopBuffer.writeln("  } else {");
    loopBuffer.writeln("    this.pos = mark;");
    loopBuffer.writeln("  }");
    if (inner case var inner?) {
      loopBuffer.writeln(inner.indent());
    } else {
      loopBuffer.writeln("  return $containerName;");
    }
    loopBuffer.writeln("}");

    var fullBuffer = StringBuffer();
    if (!markSaved) {
      fullBuffer.writeln("if (this.pos case var mark) {");
    }
    fullBuffer.writeln(
      node.child
          .acceptParametrizedVisitor(
            this,
            Parameters(
              withNames: {variableName},
              isNullAllowed: true,
              inner: loopBuffer.toString(),
              reported: reported,
              declarationName: declarationName,
              markSaved: true,
            ),
          )
          .indent(1, !markSaved),
    );
    if (!markSaved) {
      fullBuffer.writeln("}");
    }

    return fullBuffer.toString();
  }

  @override
  String visitAndPredicateNode(node, parameters) {
    var Parameters(:withNames, :inner, :reported, :declarationName, :markSaved) = parameters;
    var buffer = [
      if (!markSaved) "if (this.pos case var mark) {",
      node.child
          .acceptParametrizedVisitor(
            this,
            Parameters(
              withNames: withNames,
              inner: "this.pos = mark;\n${inner ?? ""}",
              isNullAllowed: isNullable(node.child, declarationName),
              reported: reported,
              declarationName: declarationName,
              markSaved: true,
            ),
          )
          .indent(1, !markSaved),
      if (!markSaved) "}",
    ];

    return buffer.join("\n");
  }

  @override
  String visitNotPredicateNode(node, parameters) {
    var Parameters(:withNames, :inner, :reported, :declarationName, :markSaved) = parameters;
    var buffer = StringBuffer();

    if (!markSaved) {
      buffer.writeln("if (this.pos case var mark) {");
    }
    buffer.writeln(
      node.child
          .acceptParametrizedVisitor(
            this,
            Parameters(
              isNullAllowed: true,
              withNames: {...?withNames, "null"},
              inner: "this.pos = mark;\n${inner ?? "return null;"}",
              reported: reported,
              declarationName: declarationName,
              markSaved: true,
            ),
          )
          .indent(1, !markSaved),
    );

    if (!markSaved) {
      buffer.writeln("}");
    }

    return buffer.toString();
  }

  @override
  String visitOptionalNode(node, parameters) {
    var Parameters(:withNames, :inner, :reported, :declarationName, :markSaved) = parameters;
    return node.child.acceptParametrizedVisitor(
      this,
      Parameters(
        withNames: withNames,
        inner: inner,
        isNullAllowed: true,
        reported: reported,
        declarationName: declarationName,
        markSaved: markSaved,
      ),
    );
  }

  @override
  String visitExceptNode(node, parameters) {
    var Parameters(:withNames, :inner, :reported, :declarationName, :markSaved) = parameters;
    var buffer = StringBuffer();
    if (!markSaved) {
      buffer.writeln("if (this.pos case var mark) {");
    }
    buffer.writeln(
      node.child
          .acceptParametrizedVisitor(
            this,
            Parameters(
              isNullAllowed: true,
              withNames: {"null"},
              inner:
                  (StringBuffer()
                        ..writeln("this.pos = mark;")
                        ..writeln("if (this.pos < this.buffer.length) {")
                        ..writeAll(switch (withNames.varNames) {
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
              reported: reported,
              declarationName: declarationName,
              markSaved: true,
            ),
          )
          .indent(1, !markSaved),
    );

    if (!markSaved) {
      buffer.writeln("}");
    }

    return buffer.toString();
  }

  @override
  String visitReferenceNode(node, parameters) {
    var Parameters(:isNullAllowed, :withNames, :inner, :declarationName) = parameters;
    var ruleName = node.ruleName;
    var mark = isNullable(node, declarationName) ? "!" : "";

    var buffer = [
      "if (this.apply(this.$ruleName)${"$mark case ${withNames.varNames}${isNullAllowed ? "" : "?"}) {"}",
      if (inner != null) //
        inner.indent()
      else
        "return ${withNames.singleName};".indent(),
      "}",
    ];

    return buffer.join("\n");
  }

  @override
  String visitFragmentNode(node, parameters) {
    var Parameters(:isNullAllowed, :withNames, :inner) = parameters;
    var buffer = [
      "if (this.${node.fragmentName}() case ${withNames.varNames}${isNullAllowed ? "" : "?"}) {",
      if (inner != null) //
        inner.indent()
      else
        "return ${withNames.singleName};".indent(),
      "}",
    ];

    return buffer.join("\n");
  }

  @override
  String visitNamedNode(node, parameters) {
    var Parameters(:isNullAllowed, :withNames, :inner, :reported, :declarationName, :markSaved) =
        parameters;

    return node.child.acceptParametrizedVisitor(
      this,
      Parameters(
        isNullAllowed: isNullAllowed,
        withNames: {...?withNames, node.name},
        inner: inner,
        reported: reported,
        declarationName: declarationName,
        markSaved: markSaved,
      ),
    );
  }

  @override
  String visitActionNode(node, parameters) {
    var Parameters(:withNames, :reported, :declarationName, :markSaved) = parameters;

    if (node.action.contains(RegExp(r"\$(?![A-Za-z0-9_\$])"))) {
      (withNames ??= {}).add(r"$");
    }

    var inner = node.action;

    if (node.isSpanUsed) {
      inner =
          (StringBuffer()
                ..writeln("if (this.buffer.substring(from, to) case var ${withNames.varNames}) {")
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
        isNullAllowed: isNullable(node.child, declarationName),
        reported: reported,
        declarationName: declarationName,
        markSaved: markSaved,
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
    var Parameters(:withNames, :reported, :declarationName, :markSaved) = parameters;

    if (node.action.contains(RegExp(r"\$(?![A-Za-z0-9_\$])"))) {
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
        isNullAllowed: isNullable(node.child, declarationName),
        reported: reported,
        declarationName: declarationName,
        markSaved: markSaved,
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
    var buffer = switch (withNames.varNames) {
      "_" => [
        "if (this.pos <= 0) {",
        if (inner != null) //
          inner.indent()
        else
          "return this.pos;".indent(),
        "}",
      ],
      String names => [
        "if (this.pos case $names when this.pos <= 0) {",
        if (inner != null) //
          inner.indent()
        else
          "return ${withNames.singleName};".indent(),
        "}",
      ],
    };

    return buffer.join("\n");
  }

  @override
  String visitEndOfInputNode(node, parameters) {
    var Parameters(:withNames, :inner) = parameters;
    var buffer = switch (withNames.varNames) {
      "_" => [
        "if (this.pos >= this.buffer.length) {",
        if (inner != null) //
          inner.indent()
        else
          "return this.pos;".indent(),
        "}",
      ],
      String names => [
        "if (this.pos case $names when this.pos >= this.buffer.length) {",
        if (inner != null) //
          inner.indent()
        else
          "return ${withNames.singleName};".indent(),
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
      ...switch (withNames.varNames) {
        "_" => [
          "  this.pos++;",
          if (inner != null) //
            inner.indent()
          else
            "  return this.buffer[this.pos - 1];",
        ],
        String names => [
          "  if (this.buffer[this.pos++] case $names) {",
          if (inner != null) //
            inner.indent(2)
          else
            "    return ${withNames.singleName};",
          "  }",
        ],
      },
      "}",
    ];
    return buffer.join("\n");
  }
}
