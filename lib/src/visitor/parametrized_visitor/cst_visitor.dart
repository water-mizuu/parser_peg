// ignore_for_file: always_specify_types

import "dart:convert";

import "package:parser_peg/src/generator.dart";
import "package:parser_peg/src/node.dart";
import "package:parser_peg/src/visitor/node_visitor.dart";

String encode(Object object) => jsonEncode(object).replaceAll(r"$", r"\$");

typedef Parameters = ({
  bool isNullAllowed,
  Set<String>? withNames,
  String? inner,
  bool reported,
  String declarationName,
});

class CstCompilerVisitor implements ParametrizedNodeVisitor<String, Parameters> {
  CstCompilerVisitor({required this.isNullable});

  bool Function(Node, String) isNullable;

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
    EpsilonNode node,
    Parameters parameters,
  ) {
    var (
      :bool isNullAllowed,
      :Set<String>? withNames,
      :String? inner,
      reported: bool _,
      :String declarationName,
    ) = parameters;

    List<String> buffer = <String>[
      "if ('' case ${withNames.varNames}${isNullAllowed ? "" : "?"}) {",
      if (inner != null) //
        inner.indent()
      else
        "return (${encode(declarationName)}, ${withNames.singleName});".indent(),
      "}",
    ];

    return buffer.join("\n");
  }

  @override
  String visitTriePatternNode(
    TriePatternNode node,
    Parameters parameters,
  ) {
    var (
      :bool isNullAllowed,
      :Set<String>? withNames,
      :String? inner,
      reported: bool _,
      :String declarationName,
    ) = parameters;
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
        "return (${encode(declarationName)}, ${withNames.singleName});".indent(),
      "}",
    ];

    return buffer.join("\n");
  }

  @override
  String visitStringLiteralNode(
    StringLiteralNode node,
    Parameters parameters,
  ) {
    var (
      :bool isNullAllowed,
      :Set<String>? withNames,
      :String? inner,
      reported: bool _,
      :String declarationName,
    ) = parameters;
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
        "return (${encode(declarationName)}, ${withNames.singleName});".indent(),
      "}",
    ];
    return buffer.join("\n");
  }

  @override
  String visitRangeNode(
    RangeNode node,
    Parameters parameters,
  ) {
    var (
      :bool isNullAllowed,
      :Set<String>? withNames,
      :String? inner,
      reported: bool _,
      :String declarationName,
    ) = parameters;
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
        "return (${encode(declarationName)}, ${withNames.singleName});".indent(),
      "}",
    ];

    return buffer.join("\n");
  }

  @override
  String visitRegExpNode(
    RegExpNode node,
    Parameters parameters,
  ) {
    var (
      :bool isNullAllowed,
      :Set<String>? withNames,
      :String? inner,
      reported: bool _,
      :String declarationName,
    ) = parameters;
    String key = node.value;
    int id = switch (regexpIds[key]) {
      int id => id,
      null => (regexps..add(key), regexpIds[key] = ++regexpId).$2,
    };
    List<String> buffer = <String>[
      "if (matchPattern(_regexp.\$$id) case ${withNames.varNames}${isNullAllowed ? "" : "?"}) {",
      if (inner != null) //
        inner.indent()
      else
        "return (${encode(declarationName)}, ${withNames.singleName});".indent(),
      "}",
    ];

    return buffer.join("\n");
  }

  @override
  String visitRegExpEscapeNode(
    RegExpEscapeNode node,
    Parameters parameters,
  ) {
    var (
      :bool isNullAllowed,
      :Set<String>? withNames,
      :String? inner,
      reported: bool _,
      :String declarationName,
    ) = parameters;
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
        "return (${encode(declarationName)}, ${withNames.singleName});".indent(),
      "}",
    ];

    return buffer.join("\n");
  }

  @override
  String visitSequenceNode(
    SequenceNode node,
    Parameters parameters,
  ) {
    var (
      isNullAllowed: bool _,
      :Set<String>? withNames,
      inner: String? _,
      :bool reported,
      :String declarationName,
    ) = parameters;
    List<String> names = <String>[
      for (int i = 0; i < node.children.length; ++i) "\$$i",
    ];
    String lowestInner = names //
        .join(", ")
        .apply((String v) => "return (${encode(declarationName)}, [$v]);");

    String aliased = switch (withNames) {
      null => lowestInner,
      Set<String> withNames => "if ((${names.join(", ")}) case ${withNames.varNames}) {\n${lowestInner.indent()}\n}"
    };

    String body = node.children.indexed.toList().reversed.fold(
      aliased,
      (String inner, (int, Node) pair) {
        var (int index, Node node) = pair;

        return node.acceptParametrizedVisitor(
          this,
          (
            withNames: <String>{names[index]},
            inner: inner,
            isNullAllowed: isNullable.call(node, declarationName),
            reported: reported,
            declarationName: declarationName,
          ),
        );
      },
    );

    return body;
  }

  @override
  String visitChoiceNode(
    ChoiceNode node,
    Parameters parameters,
  ) {
    var (
      :bool isNullAllowed,
      :Set<String>? withNames,
      :String? inner,
      :bool reported,
      :String declarationName,
    ) = parameters;
    StringBuffer buffer = StringBuffer();
    StringBuffer innerBuffer = StringBuffer();
    for (var (int i, Node child) in node.children.indexed) {
      if (i > 0) {
        innerBuffer.writeln("this.pos = mark;");
      }
      innerBuffer.writeln(
        child.acceptParametrizedVisitor(
          this,
          (
            isNullAllowed: isNullAllowed,
            withNames: withNames,
            inner: inner,
            reported: reported,
            declarationName: declarationName,
          ),
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
    CountedNode node,
    Parameters parameters,
  ) {
    var (
      isNullAllowed: bool _,
      :Set<String>? withNames,
      :String? inner,
      :bool reported,
      :String declarationName,
    ) = parameters;
    String variableName = "_${ruleId++}";
    String containerName = "_loop${++ruleId}";
    (withNames ??= <String>{}).add(containerName);

    if (node.min > 0) {
      String loopBody = node.child.acceptParametrizedVisitor(
        this,
        (
          withNames: <String>{variableName},
          inner: "$containerName.add($variableName);\ncontinue;",
          isNullAllowed: isNullable(node.child, declarationName),
          reported: reported,
          declarationName: declarationName,
        ),
      ).indent(3);
      StringBuffer loopBuffer = StringBuffer();
      loopBuffer.writeln("if ([$variableName] case ${withNames.varNames}) {");
      if (node.max == null) {
        loopBuffer.writeln("      for (;;) {");
      } else {
        loopBuffer.writeln("      while ($containerName.length < ${node.max}) {");
      }
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
          loopBuffer.writeln("return (${encode(declarationName)}, $containerName);".indent(2));
        }
        loopBuffer.writeln("  }");
      } else {
        if (inner != null) {
          loopBuffer.writeln(inner.indent());
        } else {
          loopBuffer.writeln("return (${encode(declarationName)}, $containerName);".indent());
        }
      }
      loopBuffer.writeln("}");

      return node.child.acceptParametrizedVisitor(
        this,
        (
          withNames: <String>{variableName},
          inner: loopBuffer.toString(),
          isNullAllowed: isNullable(node.child, declarationName),
          reported: reported,
          declarationName: declarationName,
        ),
      );
    } else {
      String loopBody = node.child.acceptParametrizedVisitor(
        this,
        (
          withNames: <String>{variableName},
          inner: "$containerName.add($variableName);\ncontinue;",
          isNullAllowed: isNullable(node.child, declarationName),
          reported: reported,
          declarationName: declarationName,
        ),
      ).indent(5);
      String question = isNullable(node.child, declarationName) ? "" : "?";
      StringBuffer loopBuffer = StringBuffer();
      loopBuffer.writeln("if (this.pos case var mark) {");
      loopBuffer.writeln(
        "  "
        "if (${"[if ($variableName case var $variableName$question) "}$variableName] "
        "case ${withNames.varNames}) {",
      );
      loopBuffer.writeln("    if ($containerName.isNotEmpty) {");
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
      if (inner case String inner) {
        loopBuffer.writeln(inner.indent(2));
      } else {
        loopBuffer.writeln("    return (${encode(declarationName)}, $containerName);");
      }
      loopBuffer.writeln("  }");
      loopBuffer.writeln("}");

      return node.child.acceptParametrizedVisitor(
        this,
        (
          withNames: <String>{variableName},
          isNullAllowed: true,
          inner: loopBuffer.toString(),
          reported: reported,
          declarationName: declarationName,
        ),
      );
    }
  }

  @override
  String visitPlusSeparatedNode(
    PlusSeparatedNode node,
    Parameters parameters,
  ) {
    var (
      isNullAllowed: bool _,
      :Set<String>? withNames,
      :String? inner,
      :bool reported,
      :String declarationName,
    ) = parameters;
    String variableName = "_${ruleId++}";
    String separatorName = "_${ruleId++}";
    String containerName = "_loop${++ruleId}";
    (withNames ??= <String>{}).add(containerName);

    String trailingBody = node.separator.acceptParametrizedVisitor(
      this,
      (
        isNullAllowed: true,
        withNames: <String>{"null"},
        inner: "this.pos = mark;",
        reported: reported,
        declarationName: declarationName,
      ),
    ).indent(2);
    String loopBody = node.separator.acceptParametrizedVisitor(
      this,
      (
        isNullAllowed: isNullable(node.separator, declarationName),
        withNames: <String>{separatorName},
        inner: node.child.acceptParametrizedVisitor(
          this,
          (
            withNames: <String>{variableName},
            inner: "$containerName.addAll([$separatorName, $variableName]);\ncontinue;",
            isNullAllowed: isNullable(node.child, declarationName),
            reported: reported,
            declarationName: declarationName,
          ),
        ),
        reported: reported,
        declarationName: declarationName,
      ),
    ).indent(3);
    StringBuffer loopBuffer = StringBuffer();
    loopBuffer.writeln("if (<Object>[$variableName] case ${withNames.varNames}) {");
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
      loopBuffer.writeln("return (${encode(declarationName)}, $containerName);".indent());
    }
    loopBuffer.writeln("}");

    return node.child.acceptParametrizedVisitor(
      this,
      (
        withNames: <String>{variableName},
        inner: loopBuffer.toString(),
        isNullAllowed: isNullable(node.child, declarationName),
        reported: reported,
        declarationName: declarationName,
      ),
    );
  }

  @override
  String visitStarSeparatedNode(
    StarSeparatedNode node,
    Parameters parameters,
  ) {
    var (
      isNullAllowed: bool _,
      :Set<String>? withNames,
      :String? inner,
      :bool reported,
      :String declarationName,
    ) = parameters;
    String variableName = "_${ruleId++}";
    String separatorName = "_${ruleId++}";
    String containerName = "_loop${++ruleId}";
    (withNames ??= <String>{}).add(containerName);

    String loopBody = node.separator.acceptParametrizedVisitor(
      this,
      (
        withNames: <String>{separatorName},
        inner: node.child.acceptParametrizedVisitor(
          this,
          (
            withNames: <String>{variableName},
            inner: "$containerName.addAll([$separatorName, $variableName]);\ncontinue;",
            isNullAllowed: isNullable(node.child, declarationName),
            reported: reported,
            declarationName: declarationName,
          ),
        ),
        isNullAllowed: isNullable(node.separator, declarationName),
        reported: reported,
        declarationName: declarationName,
      ),
    ).indent(5);
    String question = isNullable(node.child, declarationName) ? "" : "?";
    StringBuffer loopBuffer = StringBuffer();
    loopBuffer.writeln(
      "if (<Object>[if ($variableName case var $variableName$question) $variableName] "
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
        node.separator.acceptParametrizedVisitor(
          this,
          (
            isNullAllowed: true,
            withNames: <String>{"null"},
            inner: "this.pos = mark;",
            reported: reported,
            declarationName: declarationName,
          ),
        ).indent(3),
      );
      loopBuffer.writeln("    }");
    }
    loopBuffer.writeln("  } else {");
    loopBuffer.writeln("    this.pos = mark;");
    loopBuffer.writeln("  }");
    if (inner case String inner?) {
      loopBuffer.writeln(inner.indent());
    } else {
      loopBuffer.writeln("  return (${encode(declarationName)}, $containerName);");
    }
    loopBuffer.writeln("}");

    StringBuffer fullBuffer = StringBuffer();
    fullBuffer.writeln("if (this.pos case var mark) {");
    fullBuffer.writeln(
      node.child.acceptParametrizedVisitor(
        this,
        (
          withNames: <String>{variableName},
          isNullAllowed: true,
          inner: loopBuffer.toString(),
          reported: reported,
          declarationName: declarationName,
        ),
      ).indent(),
    );
    fullBuffer.writeln("}");

    return fullBuffer.toString();
  }

  @override
  String visitPlusNode(
    PlusNode node,
    Parameters parameters,
  ) {
    var (
      isNullAllowed: bool _,
      :Set<String>? withNames,
      :String? inner,
      :bool reported,
      :String declarationName,
    ) = parameters;
    String variableName = "_${ruleId++}";
    String containerName = "_loop${++ruleId}";
    (withNames ??= <String>{}).add(containerName);

    String loopBody = node.child.acceptParametrizedVisitor(
      this,
      (
        withNames: <String>{variableName},
        inner: "$containerName.add($variableName);\ncontinue;",
        isNullAllowed: isNullable(node.child, declarationName),
        reported: reported,
        declarationName: declarationName,
      ),
    ).indent(3);
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
      loopBuffer.writeln("return (${encode(declarationName)}, $containerName);".indent());
    }
    loopBuffer.writeln("}");

    return node.child.acceptParametrizedVisitor(
      this,
      (
        withNames: <String>{variableName},
        inner: loopBuffer.toString(),
        isNullAllowed: isNullable(node.child, declarationName),
        reported: reported,
        declarationName: declarationName,
      ),
    );
  }

  @override
  String visitStarNode(
    StarNode node,
    Parameters parameters,
  ) {
    var (
      isNullAllowed: bool _,
      :Set<String>? withNames,
      :String? inner,
      :bool reported,
      :String declarationName,
    ) = parameters;
    String variableName = "_${ruleId++}";
    String containerName = "_loop${++ruleId}";
    (withNames ??= <String>{}).add(containerName);

    String loopBody = node.child.acceptParametrizedVisitor(
      this,
      (
        withNames: <String>{variableName},
        inner: "$containerName.add($variableName);\ncontinue;",
        isNullAllowed: isNullable(node.child, declarationName),
        reported: reported,
        declarationName: declarationName,
      ),
    ).indent(4);
    String question = isNullable(node.child, declarationName) ? "" : "?";
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
      loopBuffer.writeln("  return (${encode(declarationName)}, $containerName);");
    }
    loopBuffer.writeln("}");

    StringBuffer fullBuffer = StringBuffer();
    fullBuffer.writeln("if (this.pos case var mark) {");
    fullBuffer.writeln(
      node.child.acceptParametrizedVisitor(
        this,
        (
          withNames: <String>{variableName},
          isNullAllowed: true,
          inner: loopBuffer.toString(),
          reported: reported,
          declarationName: declarationName,
        ),
      ).indent(),
    );
    fullBuffer.writeln("}");

    return fullBuffer.toString();
  }

  @override
  String visitAndPredicateNode(
    AndPredicateNode node,
    Parameters parameters,
  ) {
    var (
      isNullAllowed: bool _,
      :Set<String>? withNames,
      :String? inner,
      :bool reported,
      :String declarationName,
    ) = parameters;
    List<String> buffer = <String>[
      "if (this.pos case var mark) {",
      node.child.acceptParametrizedVisitor(
        this,
        (
          withNames: withNames,
          inner: "this.pos = mark;\n${inner ?? ""}",
          isNullAllowed: isNullable(node.child, declarationName),
          reported: reported,
          declarationName: declarationName,
        ),
      ).indent(),
      "}",
    ];

    return buffer.join("\n");
  }

  @override
  String visitNotPredicateNode(
    NotPredicateNode node,
    Parameters parameters,
  ) {
    var (
      isNullAllowed: bool _,
      :Set<String>? withNames,
      :String? inner,
      :bool reported,
      :String declarationName,
    ) = parameters;
    StringBuffer buffer = StringBuffer();

    buffer.writeln("if (this.pos case var mark) {");
    buffer.writeln(
      node.child.acceptParametrizedVisitor(
        this,
        (
          isNullAllowed: true,
          withNames: <String>{...withNames ?? <String>{}, "null"},
          inner: "this.pos = mark;\n${inner ?? "return (${encode(declarationName)}, null);"}",
          reported: reported,
          declarationName: declarationName,
        ),
      ).indent(),
    );
    buffer.writeln("}");

    return buffer.toString();
  }

  @override
  String visitOptionalNode(
    OptionalNode node,
    Parameters parameters,
  ) {
    var (
      isNullAllowed: bool _,
      :Set<String>? withNames,
      :String? inner,
      :bool reported,
      :String declarationName,
    ) = parameters;
    return node.child.acceptParametrizedVisitor(
      this,
      (
        withNames: withNames,
        inner: inner,
        isNullAllowed: true,
        reported: reported,
        declarationName: declarationName,
      ),
    );
  }

  @override
  String visitReferenceNode(
    ReferenceNode node,
    Parameters parameters,
  ) {
    var (
      :bool isNullAllowed,
      :Set<String>? withNames,
      :String? inner,
      reported: bool _,
      :String declarationName,
    ) = parameters;
    bool ruleIsNullable = isNullable(node, declarationName);
    String ruleName = node.ruleName;

    List<String> buffer = <String>[
      "if (this.apply(this.$ruleName)${ruleIsNullable ? "!" : ""} case ${withNames.varNames}${isNullAllowed ? "" : "?"}) {",
      if (inner != null) //
        inner.indent()
      else
        "return (${encode(declarationName)}, ${withNames.singleName});".indent(),
      "}",
    ];

    return buffer.join("\n");
  }

  @override
  String visitFragmentNode(
    FragmentNode node,
    Parameters parameters,
  ) {
    var (
      :bool isNullAllowed,
      :Set<String>? withNames,
      :String? inner,
      reported: bool _,
      :String declarationName,
    ) = parameters;
    String fragmentName = node.fragmentName;

    List<String> buffer = <String>[
      "if (this.$fragmentName() case ${withNames.varNames}${isNullAllowed ? "" : "?"}) {",
      if (inner != null) //
        inner.indent()
      else
        "return (${encode(declarationName)}, ${withNames.singleName});".indent(),
      "}",
    ];

    return buffer.join("\n");
  }

  @override
  String visitNamedNode(
    NamedNode node,
    Parameters parameters,
  ) {
    var (
      :bool isNullAllowed,
      :Set<String>? withNames,
      :String? inner,
      :bool reported,
      :String declarationName,
    ) = parameters;
    return node.child.acceptParametrizedVisitor(
      this,
      (
        isNullAllowed: isNullAllowed,
        withNames: withNames,
        inner: inner,
        reported: reported,
        declarationName: declarationName,
      ),
    );
  }

  @override
  String visitActionNode(
    ActionNode node,
    Parameters parameters,
  ) {
    var (
      isNullAllowed: bool _,
      :Set<String>? withNames,
      inner: String? _,
      :bool reported,
      :String declarationName,
    ) = parameters;
    return node.child.acceptParametrizedVisitor(
      this,
      (
        withNames: withNames,
        inner: null,
        isNullAllowed: isNullable(node.child, declarationName),
        reported: reported,
        declarationName: declarationName,
      ),
    );
  }

  @override
  String visitInlineActionNode(
    InlineActionNode node,
    Parameters parameters,
  ) {
    var (
      isNullAllowed: bool _,
      :Set<String>? withNames,
      inner: String? _,
      :bool reported,
      :String declarationName,
    ) = parameters;
    return node.child.acceptParametrizedVisitor(
      this,
      (
        withNames: withNames,
        inner: null,
        isNullAllowed: isNullable(node.child, declarationName),
        reported: reported,
        declarationName: declarationName,
      ),
    );
  }

  @override
  String visitStartOfInputNode(
    StartOfInputNode node,
    Parameters parameters,
  ) {
    var (
      isNullAllowed: bool _,
      :Set<String>? withNames,
      :String? inner,
      reported: bool _,
      :String declarationName,
    ) = parameters;
    List<String> buffer = switch (withNames.varNames) {
      "_" => <String>[
          "if (this.pos <= 0) {",
          if (inner != null) //
            inner.indent()
          else
            "return (${encode(declarationName)}, this.pos);".indent(),
          "}",
        ],
      String names => <String>[
          "if (this.pos case $names when this.pos <= 0) {",
          if (inner != null) //
            inner.indent()
          else
            "return (${encode(declarationName)}, ${withNames.singleName});".indent(),
          "}",
        ],
    };

    return buffer.join("\n");
  }

  @override
  String visitEndOfInputNode(
    EndOfInputNode node,
    Parameters parameters,
  ) {
    var (
      isNullAllowed: bool _,
      :Set<String>? withNames,
      :String? inner,
      reported: bool _,
      :String declarationName,
    ) = parameters;
    List<String> buffer = switch (withNames.varNames) {
      "_" => [
          "if (this.pos >= this.buffer.length) {",
          if (inner != null) //
            inner.indent()
          else
            "return (${encode(declarationName)}, this.pos);".indent(),
          "}",
        ],
      String names => <String>[
          "if (this.pos case $names when this.pos >= this.buffer.length) {",
          if (inner != null) //
            inner.indent()
          else
            "return (${encode(declarationName)}, ${withNames.singleName});".indent(),
          "}",
        ],
    };

    return buffer.join("\n");
  }

  @override
  String visitAnyCharacterNode(
    AnyCharacterNode node,
    Parameters parameters,
  ) {
    var (
      isNullAllowed: bool _,
      :Set<String>? withNames,
      :String? inner,
      reported: bool _,
      :String declarationName,
    ) = parameters;
    List<String> buffer = <String>[
      "if (pos < buffer.length) {",
      ...switch (withNames.varNames) {
        "_" => [
            "  pos++;",
            if (inner != null) //
              inner.indent()
            else
              "  return (${encode(declarationName)}, ${withNames.singleName});",
          ],
        String names => [
            "  if (buffer[pos] case $names) {",
            "    pos++;",
            if (inner != null) //
              inner.indent(2)
            else
              "    return ${withNames.singleName};",
            "  }",
          ]
      },
      "}",
    ];
    return buffer.join("\n");
  }
}
