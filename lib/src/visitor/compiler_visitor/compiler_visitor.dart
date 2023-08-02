import "dart:convert";

import "package:parser_peg/src/generator.dart";
import "package:parser_peg/src/node.dart";
import "package:parser_peg/src/visitor/node_visitor.dart";

String encode(Object object) => jsonEncode(object).replaceAll(r"$", r"\$");

class CompilerVisitor implements CompilerNodeVisitor<String, String> {
  CompilerVisitor({
    required this.isNullable,
    required this.fixName,
  });

  bool Function(Node) isNullable;
  String Function(String) fixName;

  int ruleId = 0;

  final Map<String, int> regexpIds = <String, int>{};
  final List<String> regexps = <String>[];
  int regexpId = 0;

  final Map<String, int> trieIds = <String, int>{};
  final List<List<String>> tries = <List<String>>[];
  int trieId = 0;

  final Map<String, int> stringIds = <String, int>{};
  final List<String> strings = <String>[];
  int stringId = 0;

  final Map<String, int> rangeIds = <String, int>{};
  final List<Set<(int, int)>> ranges = <Set<(int, int)>>[];
  int rangeId = 0;

  @override
  String visitEpsilonNode(
    EpsilonNode node, {
    required bool isNullAllowed,
    required Set<String>? withNames,
    required String? inner,
    required bool reported,
  }) {
    List<String> buffer = <String>[
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
  String visitTriePatternNode(
    TriePatternNode node, {
    required bool isNullAllowed,
    required Set<String>? withNames,
    required String? inner,
    required bool reported,
  }) {
    String key = jsonEncode(node.options);
    int id = switch (trieIds[key]) {
      int id => id,
      null => (tries..add(node.options), trieIds[key] = ++trieId).$2,
    };

    List<String> buffer = <String>[
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
  String visitStringLiteralNode(
    StringLiteralNode node, {
    required bool isNullAllowed,
    required Set<String>? withNames,
    required String? inner,
    required bool reported,
  }) {
    String key = node.literal;
    int id = switch (stringIds[key]) {
      int id => id,
      null => (strings..add(node.literal), stringIds[key] = ++stringId).$2,
    };

    List<String> buffer = <String>[
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
  String visitRangeNode(
    RangeNode node, {
    required bool isNullAllowed,
    required Set<String>? withNames,
    required String? inner,
    required bool reported,
  }) {
    String key = node.ranges //
        .map(
          ((int, int) v) => switch (v) {
            (int l, int r) when l == r => "$l",
            (int l, int r) => "$l-$r",
          },
        )
        .join(",");
    int id = switch (rangeIds[key]) {
      int id => id,
      null => (ranges..add(node.ranges), rangeIds[key] = ++rangeId).$2,
    };
    List<String> buffer = <String>[
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
  String visitRegExpNode(
    RegExpNode node, {
    required bool isNullAllowed,
    required Set<String>? withNames,
    required String? inner,
    required bool reported,
  }) {
    String key = node.value.pattern;
    int id = switch (regexpIds[key]) {
      int id => id,
      null => (regexps..add(key), regexpIds[key] = ++regexpId).$2,
    };
    List<String> buffer = <String>[
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
  String visitRegExpEscapeNode(
    RegExpEscapeNode node, {
    required bool isNullAllowed,
    required Set<String>? withNames,
    required String? inner,
    required bool reported,
  }) {
    String pattern = node.pattern;
    int id = switch (regexpIds[pattern]) {
      int id => id,
      null => (regexps..add(pattern), regexpIds[pattern] = ++regexpId).$2,
    };
    List<String> buffer = <String>[
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
  String visitSequenceNode(
    SequenceNode node, {
    required bool isNullAllowed,
    required Set<String>? withNames,
    required String? inner,
    required bool reported,
  }) {
    List<String> names = <String>[for (int i = 0; i < node.children.length; ++i) "\$$i"];
    String lowestInner = inner ?? //
        node.choose?.apply((int v) => "return \$$v;") ??
        names.join(", ").apply((String v) => "return ($v);");

    String aliased = switch (withNames) {
      null => lowestInner,
      Set<String> withNames => switch (node.choose) {
          null => "if ((${names.join(", ")}) case ${withNames.varNames}) {\n${lowestInner.indent()}\n}",
          int choose => "if (\$$choose case ${withNames.varNames}) {\n${lowestInner.indent()}\n}"
        },
    };

    String body = node.children.indexed.toList().reversed.fold(
          aliased,
          (String inner, (int, Node) pair) => pair.$2.acceptCompilerVisitor(
            this,
            withNames: <String>{"\$${pair.$1}"},
            inner: inner,
            isNullAllowed: isNullable.call(pair.$2),
            reported: reported,
          ),
        );

    return body;
  }

  @override
  String visitChoiceNode(
    ChoiceNode node, {
    required bool isNullAllowed,
    required Set<String>? withNames,
    required String? inner,
    required bool reported,
  }) {
    StringBuffer buffer = StringBuffer();
    StringBuffer innerBuffer = StringBuffer();
    for (var (int i, Node child) in node.children.indexed) {
      if (i > 0) {
        innerBuffer.writeln("this.pos = mark;");
      }
      innerBuffer.writeln(
        child.acceptCompilerVisitor(
          this,
          isNullAllowed: isNullAllowed,
          withNames: withNames,
          inner: inner,
          reported: reported,
        ),
      );
    }

    buffer.writeln("if (this.pos case var mark) {");
    buffer.writeln(innerBuffer.toString().indent());
    buffer.writeln("}");

    return buffer.toString();
  }

  @override
  String visitCountedNode(
    CountedNode node, {
    required bool isNullAllowed,
    required Set<String>? withNames,
    required String? inner,
    required bool reported,
  }) {
    String variableName = "_${ruleId++}";
    String containerName = "_loop${++ruleId}";
    (withNames ??= <String>{}).add(containerName);

    if (node.min > 0) {
      String loopBody = node.child
          .acceptCompilerVisitor(
            this,
            withNames: <String>{variableName},
            inner: "$containerName.add($variableName);\ncontinue;",
            isNullAllowed: isNullable(node.child),
            reported: reported,
          )
          .indent(3);
      StringBuffer loopBuffer = StringBuffer();
      loopBuffer.writeln("if ([$variableName] case ${withNames.varNames}) {");
      loopBuffer.writeln("  while (${node.max == null ? "true" : "$containerName.length < ${node.max}"}) {");
      loopBuffer.writeln("    if (this.pos case var mark) {");
      loopBuffer.writeln(loopBody);
      loopBuffer.writeln("      this.pos = mark;");
      loopBuffer.writeln("      break;");
      loopBuffer.writeln("    }");
      loopBuffer.writeln("  }");
      if (node.min > 1) {
        loopBuffer.writeln("  if ($containerName.length >= ${node.min}) {");
        if (inner != null) {
          loopBuffer.writeln(inner.indent(2));
        } else {
          loopBuffer.writeln("return $containerName;".indent(2));
        }
        loopBuffer.writeln("  }");
      } else {
        if (inner != null) {
          loopBuffer.writeln(inner.indent());
        } else {
          loopBuffer.writeln("return $containerName;".indent());
        }
      }
      loopBuffer.writeln("}");

      return node.child.acceptCompilerVisitor(
        this,
        withNames: <String>{variableName},
        inner: loopBuffer.toString(),
        isNullAllowed: isNullable(node.child),
        reported: reported,
      );
    } else {
      String loopBody = node.child
          .acceptCompilerVisitor(
            this,
            withNames: <String>{variableName},
            inner: "$containerName.add($variableName);\ncontinue;",
            isNullAllowed: isNullable(node.child),
            reported: reported,
          )
          .indent(5);
      String question = isNullable(node.child) ? "" : "?";
      StringBuffer loopBuffer = StringBuffer();
      loopBuffer.writeln("if (this.pos case var mark) {");
      loopBuffer.writeln(
        "  "
        "if (${"[if ($variableName case var $variableName$question) "}$variableName] "
        "case ${withNames.varNames}) {",
      );
      loopBuffer.writeln("    if ($containerName.isNotEmpty) {");
      loopBuffer.writeln("      while (${node.max == null ? "true" : "$containerName.length < ${node.max}"}) {");
      loopBuffer.writeln("        if (this.pos case var mark) {");
      loopBuffer.writeln(loopBody);
      loopBuffer.writeln("          this.pos = mark;");
      loopBuffer.writeln("          break;");
      loopBuffer.writeln("        }");
      loopBuffer.writeln("      }");
      loopBuffer.writeln("    } else {");
      loopBuffer.writeln("      this.pos = mark;");
      loopBuffer.writeln("    }");
      if (inner case String inner) {
        loopBuffer.writeln(inner.indent(2));
      } else {
        loopBuffer.writeln("    return $containerName;");
      }
      loopBuffer.writeln("  }");
      loopBuffer.writeln("}");

      return node.child.acceptCompilerVisitor(
        this,
        withNames: <String>{variableName},
        isNullAllowed: true,
        inner: loopBuffer.toString(),
        reported: reported,
      );
    }
  }

  @override
  String visitPlusSeparatedNode(
    PlusSeparatedNode node, {
    required bool isNullAllowed,
    required Set<String>? withNames,
    required String? inner,
    required bool reported,
  }) {
    String variableName = "_${ruleId++}";
    String containerName = "_loop${++ruleId}";
    (withNames ??= <String>{}).add(containerName);

    String trailingBody = node.separator
        .acceptCompilerVisitor(
          this,
          isNullAllowed: true,
          withNames: <String>{"null"},
          inner: "this.pos = mark;",
          reported: reported,
        )
        .indent(2);
    String loopBody = node.separator
        .acceptCompilerVisitor(
          this,
          isNullAllowed: isNullable(node.separator),
          withNames: <String>{"_"},
          inner: node.child.acceptCompilerVisitor(
            this,
            withNames: <String>{variableName},
            inner: "$containerName.add($variableName);\ncontinue;",
            isNullAllowed: isNullable(node.child),
            reported: reported,
          ),
          reported: reported,
        )
        .indent(3);
    StringBuffer loopBuffer = StringBuffer();
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

    return node.child.acceptCompilerVisitor(
      this,
      withNames: <String>{variableName},
      inner: loopBuffer.toString(),
      isNullAllowed: isNullable(node.child),
      reported: reported,
    );
  }

  @override
  String visitStarSeparatedNode(
    StarSeparatedNode node, {
    required bool isNullAllowed,
    required Set<String>? withNames,
    required String? inner,
    required bool reported,
  }) {
    String variableName = "_${ruleId++}";
    String containerName = "_loop${++ruleId}";
    (withNames ??= <String>{}).add(containerName);

    String loopBody = node.separator
        .acceptCompilerVisitor(
          this,
          withNames: <String>{"_"},
          inner: node.child.acceptCompilerVisitor(
            this,
            withNames: <String>{variableName},
            inner: "$containerName.add($variableName);\ncontinue;",
            isNullAllowed: isNullable(node.child),
            reported: reported,
          ),
          isNullAllowed: isNullable(node.separator),
          reported: reported,
        )
        .indent(5);
    String question = isNullable(node.child) ? "" : "?";
    StringBuffer loopBuffer = StringBuffer();
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
    if (!isNullable(node) && node.isTrailingAllowed) {
      loopBuffer.writeln("    if (this.pos case var mark) {");
      loopBuffer.writeln(
        node.separator
            .acceptCompilerVisitor(
              this,
              isNullAllowed: true,
              withNames: <String>{"null"},
              inner: "this.pos = mark;",
              reported: reported,
            )
            .indent(3),
      );
      loopBuffer.writeln("    }");
    }
    loopBuffer.writeln("  } else {");
    loopBuffer.writeln("    this.pos = mark;");
    loopBuffer.writeln("  }");
    if (inner case String inner?) {
      loopBuffer.writeln(inner.indent());
    } else {
      loopBuffer.writeln("  return $containerName;");
    }
    loopBuffer.writeln("}");

    StringBuffer fullBuffer = StringBuffer();
    fullBuffer.writeln("if (this.pos case var mark) {");
    fullBuffer.writeln(
      node.child
          .acceptCompilerVisitor(
            this,
            withNames: <String>{variableName},
            isNullAllowed: true,
            inner: loopBuffer.toString(),
            reported: reported,
          )
          .indent(),
    );
    fullBuffer.writeln("}");

    return fullBuffer.toString();
  }

  @override
  String visitPlusNode(
    PlusNode node, {
    required bool isNullAllowed,
    required Set<String>? withNames,
    required String? inner,
    required bool reported,
  }) {
    String variableName = "_${ruleId++}";
    String containerName = "_loop${++ruleId}";
    (withNames ??= <String>{}).add(containerName);

    String loopBody = node.child
        .acceptCompilerVisitor(
          this,
          withNames: <String>{variableName},
          inner: "$containerName.add($variableName);\ncontinue;",
          isNullAllowed: isNullable(node.child),
          reported: reported,
        )
        .indent(3);
    StringBuffer loopBuffer = StringBuffer();
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

    return node.child.acceptCompilerVisitor(
      this,
      withNames: <String>{variableName},
      inner: loopBuffer.toString(),
      isNullAllowed: isNullable(node.child),
      reported: reported,
    );
  }

  @override
  String visitStarNode(
    StarNode node, {
    required bool isNullAllowed,
    required Set<String>? withNames,
    required String? inner,
    required bool reported,
  }) {
    String variableName = "_${ruleId++}";
    String containerName = "_loop${++ruleId}";
    (withNames ??= <String>{}).add(containerName);

    String loopBody = node.child
        .acceptCompilerVisitor(
          this,
          withNames: <String>{variableName},
          inner: "$containerName.add($variableName);\ncontinue;",
          isNullAllowed: isNullable(node.child),
          reported: reported,
        )
        .indent(4);
    String question = isNullable(node.child) ? "" : "?";
    StringBuffer loopBuffer = StringBuffer();
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
    if (inner case String inner?) {
      loopBuffer.writeln(inner.indent());
    } else {
      loopBuffer.writeln("  return $containerName;");
    }
    loopBuffer.writeln("}");

    StringBuffer fullBuffer = StringBuffer();
    fullBuffer.writeln("if (this.pos case var mark) {");
    fullBuffer.writeln(
      node.child
          .acceptCompilerVisitor(
            this,
            withNames: <String>{variableName},
            isNullAllowed: true,
            inner: loopBuffer.toString(),
            reported: reported,
          )
          .indent(),
    );
    fullBuffer.writeln("}");

    return fullBuffer.toString();
  }

  @override
  String visitAndPredicateNode(
    AndPredicateNode node, {
    required bool isNullAllowed,
    required Set<String>? withNames,
    required String? inner,
    required bool reported,
  }) {
    List<String> buffer = <String>[
      "if (this.pos case var mark) {",
      node.child
          .acceptCompilerVisitor(
            this,
            withNames: withNames,
            inner: "this.pos = mark;\n${inner ?? ""}",
            isNullAllowed: isNullable(node.child),
            reported: reported,
          )
          .indent(),
      "}",
    ];

    return buffer.join("\n");
  }

  @override
  String visitNotPredicateNode(
    NotPredicateNode node, {
    required bool isNullAllowed,
    required Set<String>? withNames,
    required String? inner,
    required bool reported,
  }) {
    StringBuffer buffer = StringBuffer();

    buffer.writeln("if (this.pos case var mark) {");
    buffer.writeln(
      node.child
          .acceptCompilerVisitor(
            this,
            isNullAllowed: true,
            withNames: <String>{...withNames ?? <String>{}, "null"},
            inner: "this.pos = mark;\n${inner ?? "return null;"}",
            reported: reported,
          )
          .indent(),
    );
    buffer.writeln("}");

    return buffer.toString();
  }

  @override
  String visitOptionalNode(
    OptionalNode node, {
    required bool isNullAllowed,
    required Set<String>? withNames,
    required String? inner,
    required bool reported,
  }) {
    return node.child.acceptCompilerVisitor(
      this,
      withNames: withNames,
      inner: inner,
      isNullAllowed: true,
      reported: reported,
    );
  }

  @override
  String visitReferenceNode(
    ReferenceNode node, {
    required bool isNullAllowed,
    required Set<String>? withNames,
    required String? inner,
    required bool reported,
  }) {
    bool ruleIsNullable = isNullable(node);
    String ruleName = fixName(node.ruleName);

    List<String> buffer = <String>[
      "if (this.apply(this.$ruleName)${ruleIsNullable ? "!" : ""} case ${withNames.varNames}${isNullAllowed ? "" : "?"}) {",
      if (inner != null) //
        inner.indent()
      else
        "return ${withNames.singleName};".indent(),
      "}",
    ];

    return buffer.join("\n");
  }

  @override
  String visitFragmentNode(
    FragmentNode node, {
    required bool isNullAllowed,
    required Set<String>? withNames,
    required String? inner,
    required bool reported,
  }) {
    String fragmentName = fixName(node.fragmentName);

    List<String> buffer = <String>[
      "if (this.$fragmentName() case ${withNames.varNames}${isNullAllowed ? "" : "?"}) {",
      if (inner != null) //
        inner.indent()
      else
        "return ${withNames.singleName};".indent(),
      "}",
    ];

    return buffer.join("\n");
  }

  @override
  String visitNamedNode(
    NamedNode node, {
    required bool isNullAllowed,
    required Set<String>? withNames,
    required String? inner,
    required bool reported,
  }) {
    return node.child.acceptCompilerVisitor(
      this,
      isNullAllowed: isNullAllowed,
      withNames: <String>{...withNames ?? <String>{}, node.name},
      inner: inner,
      reported: reported,
    );
  }

  @override
  String visitActionNode(
    ActionNode node, {
    required bool isNullAllowed,
    required Set<String>? withNames,
    required String? inner,
    required bool reported,
  }) {
    if (node.action.contains(RegExp(r"\$(?![A-Za-z0-9_\$])"))) {
      (withNames ??= <String>{}).add(r"$");
    }

    if (node.areIndicesProvided) {
      StringBuffer buffer = StringBuffer();
      buffer.writeln("if (this.pos case var from) {");
      buffer.writeln(
        node.child
            .acceptCompilerVisitor(
              this,
              withNames: withNames,
              inner: (StringBuffer()
                    ..writeln("if (this.pos case var to) {")
                    ..writeln(node.action.indent())
                    ..writeln("}"))
                  .toString(),
              isNullAllowed: isNullable(node.child),
              reported: reported,
            )
            .indent(),
      );
      buffer.writeln("}");

      return buffer.toString();
    } else {
      return node.child.acceptCompilerVisitor(
        this,
        withNames: withNames,
        inner: node.action,
        isNullAllowed: isNullable(node.child),
        reported: reported,
      );
    }
  }

  @override
  String visitInlineActionNode(
    InlineActionNode node, {
    required bool isNullAllowed,
    required Set<String>? withNames,
    required String? inner,
    required bool reported,
  }) {
    if (node.action.contains(RegExp(r"\$(?![A-Za-z0-9_\$])"))) {
      (withNames ??= <String>{}).add(r"$");
    }
    if (node.areIndicesProvided) {
      StringBuffer buffer = StringBuffer();
      buffer.writeln("if (this.pos case var from) {");
      buffer.writeln(
        node.child
            .acceptCompilerVisitor(
              this,
              withNames: withNames,
              inner: (StringBuffer()
                    ..writeln("if (this.pos case var to) {")
                    ..writeln("  return ${node.action};")
                    ..writeln("}"))
                  .toString(),
              isNullAllowed: isNullable(node.child),
              reported: reported,
            )
            .indent(),
      );
      buffer.writeln("}");

      return buffer.toString();
    } else {
      return node.child.acceptCompilerVisitor(
        this,
        withNames: withNames,
        inner: "return ${node.action};",
        isNullAllowed: isNullable(node.child),
        reported: reported,
      );
    }
  }

  @override
  String visitStartOfInputNode(
    StartOfInputNode node, {
    required bool isNullAllowed,
    required Set<String>? withNames,
    required String? inner,
    required bool reported,
  }) {
    List<String> buffer = <String>[
      "if (this.pos case ${withNames.varNames} when this.pos <= 0) {",
      if (inner != null) //
        inner.indent()
      else
        "return ${withNames.singleName};".indent(),
      "}",
    ];

    return buffer.join("\n");
  }

  @override
  String visitEndOfInputNode(
    EndOfInputNode node, {
    required bool isNullAllowed,
    required Set<String>? withNames,
    required String? inner,
    required bool reported,
  }) {
    List<String> buffer = <String>[
      "if (this.pos case ${withNames.varNames} when this.pos >= this.buffer.length) {",
      if (inner != null) //
        inner.indent()
      else
        "return ${withNames.singleName};".indent(),
      "}",
    ];

    return buffer.join("\n");
  }

  @override
  String visitAnyCharacterNode(
    AnyCharacterNode node, {
    required bool isNullAllowed,
    required Set<String>? withNames,
    required String? inner,
    required bool reported,
  }) {
    List<String> buffer = <String>[
      "if (pos < buffer.length) {",
      "  if (buffer[pos] case ${withNames.varNames}) {",
      "    pos++;",
      if (inner != null) //
        inner.indent()
      else
        "    return ${withNames.singleName};",
      "  }",
      "}",
    ];
    return buffer.join("\n");
  }
}
