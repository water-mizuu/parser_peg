// ignore_for_file: always_specify_types

import "dart:convert";

import "package:parser_peg/src/generator.dart";
import "package:parser_peg/src/node.dart";
import "package:parser_peg/src/visitor/node_visitor.dart";

typedef Parameters =
    ({
      /// This is a flag that indicates whether the node succeeds a null value.
      ///   This is essential as there are some predicates that allow null matching,
      ///   like `"hi"?`.
      bool isNullAllowed,

      /// This is a set of names that are used to name the result of a match.
      Set<String>? withNames,

      /// This is the inner code that is used to generate the result of a match.
      String? inner,

      /// This is a flag that indicates whether the node has been reported.
      bool reported,

      /// This is the name of the declaration that is used to generate the result of a match.
      String declarationName,
    });

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
      var innerParameters = (
        withNames: {names[index]},
        inner: body,
        isNullAllowed: isNullable.call(node, declarationName),
        reported: reported,
        declarationName: declarationName,
      );
      body = node.acceptParametrizedVisitor(this, innerParameters);
    }

    return body;
  }

  @override
  String visitChoiceNode(node, parameters) {
    var Parameters(:isNullAllowed, :withNames, :inner, :reported, :declarationName) = parameters;
    var buffer = [
      "if (this.pos case var mark) {",
      [
        for (var (i, child) in node.children.indexed) ...[
          if (i > 0) "this.pos = mark;",

          child.acceptParametrizedVisitor(this, (
            isNullAllowed: isNullAllowed,
            withNames: withNames,
            inner: inner,
            reported: reported,
            declarationName: declarationName,
          )), //
        ],
      ].join("\n").indent(),
      "}",
    ];

    return buffer.join("\n");
  }

  @override
  String visitCountedNode(node, parameters) {
    var Parameters(:withNames, :inner, :reported, :declarationName) = parameters;
    var variableName = "_${ruleId++}";
    var containerName = "_l${ruleId++}";

    if (node.min > 0) {
      var loopBody = node.child
          .acceptParametrizedVisitor(this, (
            withNames: {variableName},
            inner: "$containerName.add($variableName);\ncontinue;",
            isNullAllowed: isNullable(node.child, declarationName),
            reported: reported,
            declarationName: declarationName,
          ))
          .indent(4);

      var loopBuffer = StringBuffer();
      loopBuffer.writeln("if ([$variableName].asNullable() case var $containerName) {");
      loopBuffer.writeln("  if ($containerName != null) {");
      if (node.max == null) {
        loopBuffer.writeln("    for (;;) {");
      } else {
        loopBuffer.writeln("    while ($containerName.length < ${node.max}) {");
      }
      loopBuffer.writeln("      if (this.pos case var mark) {");
      loopBuffer.writeln(loopBody);
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

      return node.child.acceptParametrizedVisitor(this, (
        withNames: {variableName},
        inner: loopBuffer.toString(),
        isNullAllowed: isNullable(node.child, declarationName),
        reported: reported,
        declarationName: declarationName,
      ));
    } else {
      var loopBody = node.child
          .acceptParametrizedVisitor(this, (
            withNames: {variableName},
            inner: "$containerName.add($variableName);\ncontinue;",
            isNullAllowed: isNullable(node.child, declarationName),
            reported: reported,
            declarationName: declarationName,
          ))
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

      return node.child.acceptParametrizedVisitor(this, (
        withNames: {variableName},
        isNullAllowed: true,
        inner: loopBuffer.toString(),
        reported: reported,
        declarationName: declarationName,
      ));
    }
  }

  @override
  String visitPlusSeparatedNode(node, parameters) {
    var Parameters(:withNames, :inner, :reported, :declarationName) = parameters;
    var variableName = "_${ruleId++}";
    var containerName = "_l${ruleId++}";
    (withNames ??= {}).add(containerName);

    late var trailingBody = node.separator
        .acceptParametrizedVisitor(this, (
          isNullAllowed: true,
          withNames: {"null"},
          inner: "this.pos = mark;",
          reported: reported,
          declarationName: declarationName,
        ))
        .indent(2);
    var loopBody = node.separator
        .acceptParametrizedVisitor(this, (
          isNullAllowed: isNullable(node.separator, declarationName),
          withNames: {"_"},
          inner: node.child.acceptParametrizedVisitor(this, (
            withNames: {variableName},
            inner: "$containerName.add($variableName);\ncontinue;",
            isNullAllowed: isNullable(node.child, declarationName),
            reported: reported,
            declarationName: declarationName,
          )),
          reported: reported,
          declarationName: declarationName,
        ))
        .indent(3);
    var loopBuffer = StringBuffer();
    loopBuffer.writeln("if ([$variableName] case ${withNames.varNames}) {");
    loopBuffer.writeln("  for (;;) {");
    loopBuffer.writeln("    if (this.pos case var mark) {");
    loopBuffer.writeln(loopBody);
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

    return node.child.acceptParametrizedVisitor(this, (
      withNames: {variableName},
      inner: loopBuffer.toString(),
      isNullAllowed: isNullable(node.child, declarationName),
      reported: reported,
      declarationName: declarationName,
    ));
  }

  @override
  String visitStarSeparatedNode(node, parameters) {
    var Parameters(:withNames, :inner, :reported, :declarationName) = parameters;
    var variableName = "_${ruleId++}";
    var containerName = "_l${ruleId++}";
    (withNames ??= {}).add(containerName);

    var loopBody = node.separator
        .acceptParametrizedVisitor(this, (
          withNames: {"_"},
          inner: node.child.acceptParametrizedVisitor(this, (
            withNames: {variableName},
            inner: "$containerName.add($variableName);\ncontinue;",
            isNullAllowed: isNullable(node.child, declarationName),
            reported: reported,
            declarationName: declarationName,
          )),
          isNullAllowed: isNullable(node.separator, declarationName),
          reported: reported,
          declarationName: declarationName,
        ))
        .indent(5);
    var question = isNullable(node.child, declarationName) ? "" : "?";
    var loopBuffer = StringBuffer();
    loopBuffer.writeln(
      "if ([if ($variableName case var $variableName$question) $variableName] "
      "case ${withNames.varNames}) {",
    );
    loopBuffer.writeln("  if (${withNames.singleName}.isNotEmpty) {");
    loopBuffer.writeln("    for (;;) {");
    loopBuffer.writeln("      if (this.pos case var mark) {");
    loopBuffer.writeln(loopBody);
    loopBuffer.writeln("        this.pos = mark;");
    loopBuffer.writeln("        break;");
    loopBuffer.writeln("      }");
    loopBuffer.writeln("    }");
    if (!isNullable(node, declarationName) && node.isTrailingAllowed) {
      loopBuffer.writeln("    if (this.pos case var mark) {");
      loopBuffer.writeln(
        node.separator
            .acceptParametrizedVisitor(this, (
              isNullAllowed: true,
              withNames: {"null"},
              inner: "this.pos = mark;",
              reported: reported,
              declarationName: declarationName,
            ))
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
    fullBuffer.writeln("if (this.pos case var mark) {");
    fullBuffer.writeln(
      node.child.acceptParametrizedVisitor(this, (
        withNames: {variableName},
        isNullAllowed: true,
        inner: loopBuffer.toString(),
        reported: reported,
        declarationName: declarationName,
      )).indent(),
    );
    fullBuffer.writeln("}");

    return fullBuffer.toString();
  }

  @override
  String visitPlusNode(node, parameters) {
    var Parameters(:withNames, :inner, :reported, :declarationName) = parameters;
    var variableName = "_${ruleId++}";
    var containerName = "_l${ruleId++}";
    (withNames ??= {}).add(containerName);

    var loopBody = node.child
        .acceptParametrizedVisitor(this, (
          withNames: {variableName},
          inner: "$containerName.add($variableName);\ncontinue;",
          isNullAllowed: isNullable(node.child, declarationName),
          reported: reported,
          declarationName: declarationName,
        ))
        .indent(3);
    var loopBuffer = StringBuffer();
    loopBuffer.writeln("if ([$variableName] case ${withNames.varNames}) {");
    loopBuffer.writeln("  for (;;) {");
    loopBuffer.writeln("    if (this.pos case var mark) {");
    loopBuffer.writeln(loopBody);
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

    return node.child.acceptParametrizedVisitor(this, (
      withNames: {variableName},
      inner: loopBuffer.toString(),
      isNullAllowed: isNullable(node.child, declarationName),
      reported: reported,
      declarationName: declarationName,
    ));
  }

  @override
  String visitStarNode(node, parameters) {
    var Parameters(:withNames, :inner, :reported, :declarationName) = parameters;
    var variableName = "_${ruleId++}";
    var containerName = "_l${ruleId++}";
    (withNames ??= {}).add(containerName);

    var loopBody = node.child
        .acceptParametrizedVisitor(this, (
          withNames: {variableName},
          inner: "$containerName.add($variableName);\ncontinue;",
          isNullAllowed: isNullable(node.child, declarationName),
          reported: reported,
          declarationName: declarationName,
        ))
        .indent(4);
    var question = isNullable(node.child, declarationName) ? "" : "?";
    var loopBuffer = StringBuffer();
    loopBuffer.writeln(
      "if ([if ($variableName case var $variableName$question) $variableName] "
      "case ${withNames.varNames}) {",
    );
    loopBuffer.writeln("  if ($containerName.isNotEmpty) {");
    loopBuffer.writeln("    for (;;) {");
    loopBuffer.writeln("      if (this.pos case var mark) {");
    loopBuffer.writeln(loopBody);
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
    fullBuffer.writeln("if (this.pos case var mark) {");
    fullBuffer.writeln(
      node.child.acceptParametrizedVisitor(this, (
        withNames: <String>{variableName},
        isNullAllowed: true,
        inner: loopBuffer.toString(),
        reported: reported,
        declarationName: declarationName,
      )).indent(),
    );
    fullBuffer.writeln("}");

    return fullBuffer.toString();
  }

  @override
  String visitAndPredicateNode(node, parameters) {
    var Parameters(:withNames, :inner, :reported, :declarationName) = parameters;
    var buffer = [
      "if (this.pos case var mark) {",
      node.child.acceptParametrizedVisitor(this, (
        withNames: withNames,
        inner: "this.pos = mark;\n${inner ?? ""}",
        isNullAllowed: isNullable(node.child, declarationName),
        reported: reported,
        declarationName: declarationName,
      )).indent(),
      "}",
    ];

    return buffer.join("\n");
  }

  @override
  String visitNotPredicateNode(node, parameters) {
    var Parameters(:withNames, :inner, :reported, :declarationName) = parameters;
    var buffer = StringBuffer();

    buffer.writeln("if (this.pos case var mark) {");
    buffer.writeln(
      node.child.acceptParametrizedVisitor(this, (
        isNullAllowed: true,
        withNames: {...?withNames, "null"},
        inner: "this.pos = mark;\n${inner ?? "return null;"}",
        reported: reported,
        declarationName: declarationName,
      )).indent(),
    );
    buffer.writeln("}");

    return buffer.toString();
  }

  @override
  String visitOptionalNode(node, parameters) {
    var Parameters(:withNames, :inner, :reported, :declarationName) = parameters;
    return node.child.acceptParametrizedVisitor(this, (
      withNames: withNames,
      inner: inner,
      isNullAllowed: true,
      reported: reported,
      declarationName: declarationName,
    ));
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
    var Parameters(:isNullAllowed, :withNames, :inner, :reported, :declarationName) = parameters;
    return node.child.acceptParametrizedVisitor(this, (
      isNullAllowed: isNullAllowed,
      withNames: {...?withNames, node.name},
      inner: inner,
      reported: reported,
      declarationName: declarationName,
    ));
  }

  @override
  String visitActionNode(node, parameters) {
    var Parameters(:withNames, :reported, :declarationName) = parameters;

    if (node.action.contains(RegExp(r"\$(?![A-Za-z0-9_\$])"))) {
      (withNames ??= {}).add(r"$");
    }

    if (node.areIndicesProvided) {
      return (StringBuffer()
            ..writeln("if (this.pos case var from) {")
            ..writeln(
              node.child.acceptParametrizedVisitor(this, (
                withNames: withNames,
                inner:
                    (StringBuffer()
                          ..writeln("if (this.pos case var to) {")
                          ..writeln(node.action.indent())
                          ..writeln("}"))
                        .toString(),
                isNullAllowed: isNullable(node.child, declarationName),
                reported: reported,
                declarationName: declarationName,
              )).indent(),
            )
            ..writeln("}"))
          .toString();
    } else {
      return node.child.acceptParametrizedVisitor(this, (
        withNames: withNames,
        inner: node.action,
        isNullAllowed: isNullable(node.child, declarationName),
        reported: reported,
        declarationName: declarationName,
      ));
    }
  }

  @override
  String visitInlineActionNode(node, parameters) {
    var Parameters(:withNames, :reported, :declarationName) = parameters;

    if (node.action.contains(RegExp(r"\$(?![A-Za-z0-9_\$])"))) {
      (withNames ??= {}).add(r"$");
    }

    if (node.areIndicesProvided) {
      return (StringBuffer()
            ..writeln("if (this.pos case var from) {")
            ..writeln(
              node.child.acceptParametrizedVisitor(this, (
                withNames: withNames,
                inner:
                    (StringBuffer()
                          ..writeln("if (this.pos case var to) {")
                          ..writeln("  return ${node.action};")
                          ..writeln("}"))
                        .toString(),
                isNullAllowed: isNullable(node.child, declarationName),
                reported: reported,
                declarationName: declarationName,
              )).indent(),
            )
            ..writeln("}"))
          .toString();
    } else {
      return node.child.acceptParametrizedVisitor(this, (
        withNames: withNames,
        inner: "return ${node.action};",
        isNullAllowed: isNullable(node.child, declarationName),
        reported: reported,
        declarationName: declarationName,
      ));
    }
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
          "  if (this.buffer[this.pos] case $names) {",
          "    this.pos++;",
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
