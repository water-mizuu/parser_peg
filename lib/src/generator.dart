// ignore_for_file: prefer_expression_function_bodies, noop_primitive_operations

import "dart:collection";
import "dart:convert";
import "dart:io";

import "package:parser_peg/src/node.dart";
import "package:parser_peg/src/statement.dart";
import "package:parser_peg/src/visitor/compiler_visitor/compiler_visitor.dart";
import "package:parser_peg/src/visitor/simple_visitor/can_inline_visitor.dart";
import "package:parser_peg/src/visitor/simple_visitor/rename_visitors.dart";
import "package:parser_peg/src/visitor/simple_visitor/resolve_references_visitor.dart";
import "package:parser_peg/src/visitor/simplifier_visitor/simplify_visitor.dart";

typedef DeclarationEntry = MapEntry<(String?, String), Node>;

final String base = File("lib/src/base.dart").readAsStringSync();
final List<String> splits = base.split(RegExp("(?:/// IMPORTS-SPLIT)|(?:/// TRIE-SPLIT)"));
final String importCode = splits[0].trim();
final String baseCode = splits[1].trim();
final String trieCode = splits[2].trim();

String encode(Object object) => jsonEncode(object).replaceAll(r"$", r"\$");

const List<String> ignores = <String>[
  "always_declare_return_types",
  "always_put_control_body_on_new_line",
  "always_specify_types",
  "avoid_escaping_inner_quotes",
  "avoid_redundant_argument_values",
  "annotate_overrides",
  "body_might_complete_normally_nullable",
  "constant_pattern_never_matches_value_type",
  "curly_braces_in_flow_control_structures",
  "dead_code",
  "directives_ordering",
  "duplicate_ignore",
  "inference_failure_on_function_return_type",
  "constant_identifier_names",
  "prefer_function_declarations_over_variables",
  "prefer_interpolation_to_compose_strings",
  "prefer_is_empty",
  "no_leading_underscores_for_local_identifiers",
  "non_constant_identifier_names",
  "unnecessary_null_check_pattern",
  "unnecessary_brace_in_string_interps",
  "unnecessary_string_interpolations",
  "unnecessary_this",
  "unused_element",
  "unused_import",
  "prefer_double_quotes",
  "unused_local_variable",
  "unreachable_from_main",
  "use_raw_strings",
  "type_annotate_public_apis",
];

final class ParserGenerator {
  ParserGenerator.fromParsed({required List<Statement> statements, required this.preamble}) {
    /// We add all the special nodes :)
    // predefined.forEach(statements.add);

    /// We add ALL the rules in advance.
    ///   Why? Because we need ALL the rules to be able to resolve references.
    for (Statement statement in statements) {
      addResolvedRules(statement, <String>["global"], null);
    }

    /// Resolve the references from inside namespaces.
    for (Statement statement in statements) {
      processStatement(statement, <String>["global"], null);
    }

    /// We simplify the rules to prepare for codegen.
    if (SimplifyVisitor() case SimplifyVisitor visitor) {
      for (var (String name, (String? type, Node node)) in inline.pairs) {
        inline[name] = (type, node.acceptSimplifierVisitor(visitor, 0));
      }
      for (var (String name, (String? type, Node node)) in rules.pairs) {
        rules[name] = (type, node.acceptSimplifierVisitor(visitor, 0));
      }
      for (var (String name, (String? type, Node node)) in fragments.pairs) {
        fragments[name] = (type, node.acceptSimplifierVisitor(visitor, 0));
      }

      /// Since the simplifier visitor can add new fragments, we need to add them.
      fragments.addAll(visitor.addedFragments);
    }

    /// We rename the rules and fragments.

    redirectId = 0;
    for (var (String name, (String? type, Node node)) in rules.pairs.toList()) {
      String simplifiedName = "r${(redirectId++).toRadixString(36)}";

      rules.remove(name);
      rules[simplifiedName] = (type, node);
      redirects[name] = simplifiedName;
      reverseRedirects[simplifiedName] = name;
    }
    redirectId = 0;
    for (var (String name, (String? type, Node node)) in fragments.pairs.toList()) {
      String simplifiedName = "f${(redirectId++).toRadixString(36)}";

      fragments.remove(name);
      fragments[simplifiedName] = (type, node);
      redirects[name] = simplifiedName;
      reverseRedirects[simplifiedName] = name;
    }
    redirectId = 0;
    for (var (String name, (String? type, Node node)) in inline.pairs.toList()) {
      String simplifiedName = "i${(redirectId++).toRadixString(36)}";

      inline.remove(name);
      inline[simplifiedName] = (type, node);
      redirects[name] = simplifiedName;
      reverseRedirects[simplifiedName] = name;
    }

    /// We rename the references.
    if (RenameDeclarationVisitor(redirects) case RenameDeclarationVisitor visitor) {
      for (var (String name, (String? type, Node node)) in inline.pairs) {
        inline[name] = (type, node.acceptSimpleVisitor(visitor));
      }
      for (var (String name, (String? type, Node node)) in rules.pairs) {
        rules[name] = (type, node.acceptSimpleVisitor(visitor));
      }
      for (var (String name, (String? type, Node node)) in fragments.pairs) {
        fragments[name] = (type, node.acceptSimpleVisitor(visitor));
      }
    }
  }

  static final List<Statement> predefined = <Statement>[
    NamespaceStatement(
      "std",
      <Statement>[
        const DeclarationStatement.predefined("any", AnyCharacterNode()),
        const DeclarationStatement.predefined("epsilon", EpsilonNode()),
        const DeclarationStatement.predefined("start", StartOfInputNode(), type: "int"),
        const DeclarationStatement.predefined("end", EndOfInputNode(), type: "int"),
        DeclarationStatement.predefined("digit", RegExpNode(RegExp(r"\d"))),
        DeclarationStatement.predefined("alpha", RegExpNode(RegExp("[a-zA-Z]"))),
        NamespaceStatement(
          "alpha",
          <Statement>[
            DeclarationStatement.predefined("lower", RegExpNode(RegExp("[a-z]"))),
            DeclarationStatement.predefined("upper", RegExpNode(RegExp("[A-Z]"))),
          ],
          tag: null,
        ),
      ],
      tag: Tag.rule,
    ),
  ];

  /// Adds the rules from [Statement]s to the [rules] and [fragments] maps.
  void addResolvedRules(Statement statement, List<String> prefix, Tag? tag) {
    switch (statement) {
      case DeclarationStatement(:String? type, :String name, :Node node, tag: Tag? declarationTag):
        String resolvedName = <String>[...prefix, name].join("::");
        switch (declarationTag ?? tag) {
          case Tag.inline when node.canBeInlined:
            inline[resolvedName] = (type, node);
          case Tag.inline:
          case Tag.fragment:
            fragments[resolvedName] = (type, node);
          case null:
          case Tag.rule:
            rules[resolvedName] = (type, node);
        }
      case NamespaceStatement(
          :String name,
          :List<Statement> children,
          tag: Tag? declaredTag,
        ):
        for (Statement sub in children) {
          addResolvedRules(sub, <String>[...prefix, name], declaredTag ?? tag);
        }
      case NamespaceStatement(
          name: null,
          :List<Statement> children,
          tag: Tag? declaredTag,
        ):
        for (Statement sub in children) {
          addResolvedRules(sub, prefix, declaredTag ?? tag);
        }
    }
  }

  void processStatement(Statement statement, List<String> prefixes, Tag? tag) {
    switch (statement) {
      case DeclarationStatement(:String? type, :String name, :Node node, tag: Tag? declarationTag):
        ResolveReferencesVisitor visitor = ResolveReferencesVisitor(prefixes, rules, fragments, inline);
        String resolvedName = <String>[...prefixes, name].join("::");
        Node resolvedNode = node.acceptSimpleVisitor(visitor);

        switch (declarationTag ?? tag) {
          case Tag.inline when node.canBeInlined:
            inline[resolvedName] = (type, resolvedNode);
          case Tag.inline:
          case Tag.fragment:
            fragments[resolvedName] = (type, resolvedNode);
          // Default tag is rule.
          case null:
          case Tag.rule:
            rules[resolvedName] = (type, resolvedNode);
        }
      case NamespaceStatement(:String name, :List<Statement> children, tag: Tag? declaredTag):
        for (Statement sub in children) {
          processStatement(sub, <String>[...prefixes, name], declaredTag ?? tag);
        }
      case NamespaceStatement(name: null, :List<Statement> children, tag: Tag? declaredTag):
        for (Statement sub in children) {
          processStatement(sub, prefixes, declaredTag ?? tag);
        }
    }
  }

  int redirectId = 0;
  final Map<String, String> redirects = <String, String>{};
  final Map<String, String> reverseRedirects = <String, String>{};
  final Map<String, (String?, Node)> rules = <String, (String?, Node)>{};
  final Map<String, (String?, Node)> fragments = <String, (String?, Node)>{};
  final Map<String, (String?, Node)> inline = <String, (String?, Node)>{};

  final String? preamble;

  String compile(String parserName, {String? start, String? type}) {
    String parserTypeString = type ?? rules.values.firstOrNull?.$1 ?? fragments.values.firstOrNull?.$1 ?? "Object";
    String parserStartRule = start ?? fixName(rules.keys.firstOrNull ?? fragments.keys.first);
    CompilerVisitor compilerVisitor = CompilerVisitor(isNullable: isNullable, fixName: fixName);
    StringBuffer fullBuffer = StringBuffer();

    fullBuffer.writeln("// ignore_for_file: ${ignores.join(", ")}");
    fullBuffer.writeln();

    fullBuffer.writeln("// imports");
    fullBuffer.writeln(importCode);
    if (preamble case String preamble?) {
      fullBuffer.writeln("// PREAMBLE");
      fullBuffer.writeln(preamble.unindent());
    }
    fullBuffer.writeln("// base.dart");
    fullBuffer.writeln(baseCode);
    fullBuffer.writeln();

    fullBuffer.writeln("// GENERATED CODE");

    fullBuffer.writeln("final class $parserName extends _PegParser<$parserTypeString> {");
    fullBuffer.writeln("  $parserName();");
    fullBuffer.writeln();
    fullBuffer.writeln("  @override");
    fullBuffer.writeln("  get start => $parserStartRule;");
    fullBuffer.writeln();

    for (var (String rawName, (String? type, Node node)) in fragments.pairs) {
      compilerVisitor.ruleId = 0;

      StringBuffer inner = StringBuffer();
      String displayName = reverseRedirects[rawName]!;
      String fragmentName = fixName(rawName);
      String body = node
          .acceptCompilerVisitor(
            compilerVisitor,
            isNullAllowed: isNullable(node, displayName),
            withNames: null,
            inner: null,
            reported: true,
            declarationName: displayName,
          )
          .indent();

      inner.writeln();
      inner.writeln("/// `$displayName`");
      if (type == null) {
        inner.writeln("late final $fragmentName = () {");
        inner.writeln(body);
        inner.writeln("};");
      } else {
        inner.writeln("$type${isNullable(node, fragmentName) ? "" : "?"} $fragmentName() {");
        inner.writeln(body);
        inner.writeln("}");
      }

      fullBuffer.writeln(inner.toString().indent());
    }

    for (var (String rawName, (String? type, Node node)) in rules.pairs) {
      compilerVisitor.ruleId = 0;

      StringBuffer inner = StringBuffer();
      String displayName = reverseRedirects[rawName]!;
      String ruleName = fixName(rawName);
      String body = node
          .acceptCompilerVisitor(
            compilerVisitor,
            isNullAllowed: isNullable(node, ruleName),
            withNames: null,
            inner: null,
            reported: true,
            declarationName: displayName,
          )
          .indent();

      inner.writeln();
      inner.writeln("/// `$displayName`");
      if (type == null) {
        inner.writeln("late final $ruleName = () {");
        inner.writeln(body);
        inner.writeln("};");
      } else {
        inner.writeln("$type${isNullable(node, ruleName) ? "" : "?"} $ruleName() {");
        inner.writeln(body);
        inner.writeln("}");
      }

      fullBuffer.writeln(inner.toString().indent());
    }

    fullBuffer.writeln();

    if (compilerVisitor.regexps.isNotEmpty) {
      fullBuffer.writeln("static final _regexp = (".indent());
      for (String regExp in compilerVisitor.regexps) {
        fullBuffer.writeln("RegExp(${encode(regExp)}),".indent(2));
      }
      fullBuffer.writeln(");".indent());
    }

    if (compilerVisitor.tries.isNotEmpty) {
      fullBuffer.writeln("static final _trie = (".indent());
      for (List<String> options in compilerVisitor.tries) {
        fullBuffer.writeln("Trie.from(${encode(options)}),".indent(2));
      }
      fullBuffer.writeln(");".indent());
    }

    if (compilerVisitor.strings.isNotEmpty) {
      fullBuffer.writeln("static const _string = (".indent());
      for (String string in compilerVisitor.strings) {
        fullBuffer.writeln("${encode(string)},".indent(2));
      }
      fullBuffer.writeln(");".indent());
    }

    if (compilerVisitor.ranges.isNotEmpty) {
      fullBuffer.writeln("static const _range = (".indent());
      for (Set<(int, int)> ranges in compilerVisitor.ranges) {
        fullBuffer.write("    ");
        fullBuffer.write("{");
        for (var (int i, (int low, int high)) in ranges.indexed) {
          fullBuffer.write("($low, $high)");

          if (i < ranges.length - 1) {
            fullBuffer.write(", ");
          }
        }
        fullBuffer.writeln("},");
      }
      fullBuffer.writeln(");".indent());
    }

    fullBuffer.writeln("}");

    if (compilerVisitor.tries.isNotEmpty) {
      fullBuffer.writeln(trieCode);
    }

    return fullBuffer.toString();
  }

  String fixName(String name) {
    if (name.split("") case ["`", ...List<String> inner, "`"]) {
      StringBuffer buffer = StringBuffer(r"$");

      for (var (int i, String character) in inner.indexed) {
        int unit = character.codeUnits.single;

        if (64 + 1 <= unit && unit <= 64 + 26 || 96 + 1 <= unit && unit <= 96 + 26) {
          buffer.write(character);
        } else {
          buffer.write(unit);
          if (i < inner.length - 1) {
            buffer.write("_");
          }
        }
      }

      return buffer.toString();
    }
    return name.replaceAll("-", "_");
  }

  final Expando<bool> _isNullable = Expando<bool>();

  /// Returns `true` if the node should pass even if the answer was null.
  bool isNullable(Node node, String ruleName) {
    return _isNullable[node] ??= switch (node) {
      SpecialSymbolNode() => false,
      EpsilonNode() => true,
      RangeNode() => false,
      TriePatternNode() => false,

      /// Absolutely false, because [matchPattern] is nullable.
      RegExpNode() => false,
      RegExpEscapeNode() => false,
      CountedNode() => node.min <= 0 || isNullable(node.child, ruleName),
      StringLiteralNode() => node.literal.isEmpty,
      SequenceNode() => (_isNullable[node] = true, node.children.every((Node node) => isNullable(node, ruleName))).$2,
      ChoiceNode() => (_isNullable[node] = false, node.children.any((Node node) => isNullable(node, ruleName))).$2,
      PlusSeparatedNode() => isNullable(node.child, ruleName) && isNullable(node.separator, ruleName),
      StarSeparatedNode() => true,
      PlusNode() => isNullable(node.child, ruleName),
      StarNode() => true,
      AndPredicateNode() => isNullable(node.child, ruleName),
      NotPredicateNode() => isNullable(node.child, ruleName),
      OptionalNode() => isNullable(node.child, ruleName),
      ReferenceNode() => isNullable(rules[node.ruleName]?.$2 ?? notFound(node.ruleName, Tag.rule, ruleName), ruleName),
      FragmentNode() =>
        isNullable(fragments[node.fragmentName]?.$2 ?? notFound(node.fragmentName, Tag.fragment, ruleName), ruleName),
      NamedNode() => isNullable(node.child, ruleName),
      ActionNode() => isNullable(node.child, ruleName),
      InlineActionNode() => isNullable(node.child, ruleName),
    };
  }
}

Never notFound(String name, Tag tag, [String? root]) {
  throw ArgumentError.value(name, "name", "$tag not found${root == null ? "" : " in $root"}");
}

extension IndentationExtension on String {
  String indent([int count = 1]) =>
      trimRight().split("\n").map((String v) => v.isEmpty ? v : "${"  " * count}$v").join("\n");
  String unindent() {
    if (isEmpty) {
      return this;
    }

    // Remove \r and \t
    String removed = trimRight().replaceAll("\r", "").replaceAll("\t", "    ");

    // Remove trailing right space.
    Iterable<String> lines = removed.split("\n").map((String line) => line.trimRight());

    // Unindent the string.
    int commonIndentation = lines //
        .where((String line) => line.isNotEmpty)
        .map((String line) => line.length - line.trimLeft().length)
        .reduce((int a, int b) => a < b ? a : b);

    Iterable<String> unindented = lines //
        .map((String line) => line.isEmpty ? line : line.substring(commonIndentation));

    return unindented.join("\n");
  }
}

extension NameShortcuts on Set<String>? {
  String get singleName => this == null ? r"$" : this!.first;
  String get varNames => switch (this) {
        null => r"var $",
        Set<String?>(length: 1, single: "null") => "null",
        Set<String?>(length: 1, single: "!null") => "!= null",
        Set<String?>(length: 1, single: String name) => "var $name",
        Set<String?> set =>
          "(${set.map((String? v) => v == "!null" ? "!= null" : v == "null" ? v : "var $v").join(" && ")})",
      };
}

extension MonadicTypeExtension<T extends Object> on T {
  O apply<O extends Object>(O Function(T) fn) => fn(this);
}

extension<K, V> on Map<K, V> {
  Iterable<(K, V)> get pairs => entries.map((MapEntry<K, V> v) => (v.key, v.value));
}
