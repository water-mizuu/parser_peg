import "dart:collection";
import "dart:convert";
import "dart:io";

import "package:parser_peg/src/node.dart";
import "package:parser_peg/src/statement.dart";
import "package:parser_peg/src/visitor/parametrized_visitor/parser_visitor.dart";
import "package:parser_peg/src/visitor/parametrized_visitor/simplify_visitor.dart";
import "package:parser_peg/src/visitor/simple_visitor/can_inline_visitor.dart";
import "package:parser_peg/src/visitor/simple_visitor/inline_visitor.dart";
import "package:parser_peg/src/visitor/simple_visitor/referenced_visitor.dart";
import "package:parser_peg/src/visitor/simple_visitor/remove_action_node_visitor.dart";
import "package:parser_peg/src/visitor/simple_visitor/rename_visitors.dart";
import "package:parser_peg/src/visitor/simple_visitor/resolve_references_visitor.dart";

typedef DeclarationEntry = MapEntry<(String?, String), Node>;

const String rootKey = "ROOT";

final String base = File("lib/src/base.dart").readAsStringSync();
final List<String> splits = base.split(RegExp("(?:/// IMPORTS-SPLIT)|(?:/// TRIE-SPLIT)"));
final String importCode = splits[0].trim();
final String baseCode = splits[1].trim();
final String trieCode = splits[2].trim();

String encode(Object object) => jsonEncode(object).replaceAll(r"$", r"\$");

const List<String> ignores = [
  "type=lint",
  "body_might_complete_normally_nullable",
  "unused_local_variable",
  "inference_failure_on_function_return_type",
  "unused_import",
  "duplicate_ignore",
];
// const List<String> ignores = <String>[
//   "always_declare_return_types",
//   "always_put_control_body_on_new_line",
//   "always_specify_types",
//   "avoid_escaping_inner_quotes",
//   "avoid_redundant_argument_values",
//   "annotate_overrides",
//   "body_might_complete_normally_nullable",
//   "constant_pattern_never_matches_value_type",
//   "curly_braces_in_flow_control_structures",
//   "dead_code",
//   "directives_ordering",
//   "duplicate_ignore",
//   "inference_failure_on_function_return_type",
//   "constant_identifier_names",
//   "prefer_function_declarations_over_variables",
//   "prefer_interpolation_to_compose_strings",
//   "prefer_is_empty",
//   "no_leading_underscores_for_local_identifiers",
//   "non_constant_identifier_names",
//   "unnecessary_null_check_pattern",
//   "unnecessary_brace_in_string_interps",
//   "unnecessary_string_interpolations",
//   "unnecessary_this",
//   "unused_element",
//   "unused_import",
//   "prefer_double_quotes",
//   "unused_local_variable",
//   "unreachable_from_main",
//   "use_raw_strings",
//   "type_annotate_public_apis",
// ];

final class ParserGenerator {
  ParserGenerator.fromParsed({
    required List<Statement> statements,
    required this.preamble,
  }) {
    /// We add all the special nodes :)
    statements.insertAll(0, predefined);

    /// We add ALL the rules in advance.
    ///   Why? Because we need ALL the rules to be able to resolve references.
    ///
    /// This basically resolves all of the declarations in the grammar,
    ///   flattening the namespaces into a single map.
    for (var statement in statements) {
      var stack = Queue<(Statement, List<String>, Tag?)>() //
        ..add((statement, ["global"], null));

      while (stack.isNotEmpty) {
        var (statement, prefix, tag) = stack.removeLast();

        switch (statement) {
          /// If it is a declaration:
          ///   rule declaration, fragment declaration, inline declaration
          case DeclarationStatement(:var type, :var name, :var node, tag: var declaredTag):
            var realName = [...prefix, name].join(separator);
            var target = switch (declaredTag ?? tag) {
              Tag.inline => inline,
              Tag.fragment => fragments,
              Tag.rule || null => rules,
            };

            target[realName] = (type, node);

          case NamespaceStatement(:var name?, :var children, tag: var declaredTag):
            for (var sub in children.reversed) {
              stack.addLast((sub, [...prefix, name], declaredTag ?? tag));
            }
          case NamespaceStatement(name: null, :var children, tag: var declaredTag):
            for (var sub in children.reversed) {
              stack.addLast((sub, prefix, declaredTag ?? tag));
            }
        }
      }
    }

    /// Resolve the references from inside namespaces.
    for (var statement in statements) {
      var stack = Queue<(Statement, List<String>, Tag?)>() //
        ..addLast((statement, ["global"], null));

      while (stack.isNotEmpty) {
        var (statement, prefixes, tag) = stack.removeLast();

        switch (statement) {
          case DeclarationStatement(:var type, :var name, :var node, tag: var declaredTag):
            var realName = [...prefixes, name].join(separator);
            var visitor = ResolveReferencesVisitor(realName, prefixes, rules, fragments, inline);
            var resolvedNode = node.acceptSimpleVisitor(visitor);

            var target = switch (declaredTag ?? tag) {
              Tag.inline => inline,
              Tag.fragment => fragments,
              Tag.rule || null => rules,
            };
            target[realName] = (type, resolvedNode);
          case NamespaceStatement(:var name?, :var children, tag: var declaredTag):
            for (var sub in children.reversed) {
              stack.addLast((sub, [...prefixes, name], declaredTag ?? tag));
            }
          case NamespaceStatement(name: null, :var children, tag: var declaredTag):
            for (var sub in children.reversed) {
              stack.addLast((sub, prefixes, declaredTag ?? tag));
            }
        }
      }
    }

    /// Simple guard against fully inline declarations.
    if (rules.isNotEmpty) {
      var (key, (type, _)) = rules.pairs.first;

      fragments[rootKey] = (type, ReferenceNode(key));
    } else if (fragments.isNotEmpty) {
      var (key, (type, _)) = fragments.pairs.first;

      fragments[rootKey] = (type, FragmentNode(key));
    } else {
      if (inline.isEmpty) {
        throw Exception("There are no declarations!");
      }

      /// Since there is no rule / fragment, we can add a fake rule.
      var (key, (type, _)) = inline.pairs.first;

      fragments[rootKey] = (type, FragmentNode(key));
    }

    /// We determine two things.
    ///   1. Which `fragment` rule can be inlined with the following condition:
    ///     - It is only called once. (It is an exclusive fragment.)
    ///   2. Which declarations can be removed with the following condition:
    ///     - It is not referenced anywhere.
    ///
    /// Subsequently, we inline the fragments that can be inlined,
    ///   and remove the declarations that can be removed.
    ///
    /// NOTE: This does not break the correctness of the grammar, since
    ///   recursive fragments can't be inlined as determined by the next visitor.
    if (const ReferencedVisitor() case var visitor) {
      var rulesRefCount = {for (var rule in rules.keys) rule: 0};
      var fragmentRefCount = {for (var fragment in fragments.keys) fragment: 0};
      var inlineRefCount = {for (var inline in inline.keys) inline: 0};

      var declarations = fragments.pairs //
          .followedBy(rules.pairs)
          .followedBy(inline.pairs);

      var refCount = {for (var (name, _) in declarations) name: 0};

      /// We count the references to each declaration (rule, fragment, inline).
      for (var (_, (_, node)) in declarations) {
        for (var (tag, name) in node.acceptSimpleVisitor(visitor)) {
          assert(tag != Tag.inline, "Inline tags should not be here.");
          if (tag == Tag.rule) {
            /// Since it is a rule, we just have to increment its count in the rulesRefCount.
            rulesRefCount[name] = rulesRefCount[name]! + 1;
            continue;
          }

          /// From here, we know that it is a fragment.
          refCount[name] = refCount[name]! + 1;

          assert(
            fragmentRefCount.containsKey(name) ^ inlineRefCount.containsKey(name),
            "The fragment '$name' should be in either the fragments or the inline, but not both.",
          );
          if (fragmentRefCount[name] case int count) {
            fragmentRefCount[name] = count + 1;
          } else if (inlineRefCount[name] case int count) {
            inlineRefCount[name] = count + 1;
          }
        }
      }

      /// Then, if the refCount of a fragment is 1, we choose to inline it.
      for (var (name, count) in refCount.pairs) {
        if (count != 1 || fragments[name] == null) {
          continue;
        }

        var (type, node) = fragments[name]!;
        inline[name] = (type, node);
        fragments.remove(name);
      }

      /// Remove the unreferenced rules,
      for (var (name, count) in rulesRefCount.pairs) {
        if (name == rootKey || count > 0) {
          continue;
        }

        rules.remove(name);
      }

      /// Remove the unreferenced fragments,
      for (var (name, count) in fragmentRefCount.pairs) {
        if (name == rootKey || count > 0) {
          continue;
        }

        fragments.remove(name);
      }

      /// And the unused inline rules (optional, does not have any runtime bearing).
      for (var (name, count) in inlineRefCount.pairs) {
        if (name == rootKey || count > 0) {
          continue;
        }

        inline.remove(name);
      }
    }

    /// We determine the inline-declared rules that can *actually* be inlined.
    ///   We shouldn't throw an error, because it may just be that a rule is
    ///   declared as inline, but it is not actually inline-able, like in a namespace.
    if (CanInlineVisitor(rules, fragments, inline) case CanInlineVisitor visitor) {
      for (var (name, (type, node)) in inline.pairs.toList()) {
        if (!visitor.canBeInlined(node)) {
          inline.remove(name);
          fragments[name] = (type, node);
        }
      }
    }

    /// We inline the rules that can be inlined.
    if (InlineVisitor(inline) case InlineVisitor visitor) {
      bool runLoop;

      do {
        runLoop = false;
        for (var (name, (type, node)) in rules.pairs.toList()) {
          var (hasChanged, resolvedNode) = visitor.inlineReferences(node);
          runLoop |= hasChanged;

          rules[name] = (type, resolvedNode);
        }
        for (var (name, (type, node)) in fragments.pairs.toList()) {
          var (hasChanged, resolvedNode) = visitor.inlineReferences(node);
          runLoop |= hasChanged;

          fragments[name] = (type, resolvedNode);
        }
      } while (runLoop);
    }

    /// We simplify the rules to prepare for codegen.
    /// Basically, we limit the depth of each node in the tree.
    /// This allows us to have more simple code.
    if (ParametrizedSimplifyVisitor() case ParametrizedSimplifyVisitor visitor) {
      for (var (name, (type, node)) in rules.pairs) {
        rules[name] = (type, visitor.simplify(node));
      }
      for (var (name, (type, node)) in fragments.pairs) {
        fragments[name] = (type, visitor.simplify(node));
      }

      /// Since the simplifier visitor can add new fragments, we need to add them.
      fragments.addAll(visitor.addedFragments);
    }

    /// We rename the rules and fragments.
    redirectId = 0;
    for (var (name, (type, node)) in rules.pairs.toList()) {
      var simplifiedName = "r${(redirectId++).toRadixString(36)}";

      rules.remove(name);
      rules[simplifiedName] = (type, node);
      renames[name] = simplifiedName;
      reverseRenames[simplifiedName] = name;
    }
    redirectId = 0;
    for (var (name, (type, node)) in fragments.pairs.toList()) {
      var simplifiedName = "f${(redirectId++).toRadixString(36)}";

      fragments.remove(name);
      fragments[simplifiedName] = (type, node);
      renames[name] = simplifiedName;
      reverseRenames[simplifiedName] = name;
    }

    /// We rename the references.
    if (RenameDeclarationVisitor(renames) case RenameDeclarationVisitor visitor) {
      for (var (name, (type, node)) in rules.pairs) {
        rules[name] = (type, visitor.renameDeclarations(node));
      }
      for (var (name, (type, node)) in fragments.pairs) {
        fragments[name] = (type, visitor.renameDeclarations(node));
      }
    }
  }

  static const String separator = "::";
  static const List<Statement> predefined = <Statement>[
    /// @inline std {
    ///   any = .;
    ///   epsilon = ε;
    ///   start = ^;
    ///   end = $;
    ///   whitespace = /\s/;
    ///   digit = /\d/;
    ///   hex = /[0-9A-Fa-f]/;
    ///   alpha = /[a-zA-Z]/;
    ///   alpha {
    ///     lower = /[a-z]/;
    ///     upper = /[A-Z]/;
    ///   }
    /// }
    NamespaceStatement(
      "std",
      <Statement>[
        DeclarationStatement.predefined("any", AnyCharacterNode()),
        DeclarationStatement.predefined("epsilon", EpsilonNode()),
        DeclarationStatement.predefined(
          "start",
          StartOfInputNode(),
          type: "int",
        ),
        DeclarationStatement.predefined("end", EndOfInputNode(), type: "int"),
        DeclarationStatement.predefined("whitespace", RegExpNode(r"\s")),
        DeclarationStatement.predefined("digit", RegExpNode(r"\d")),
        DeclarationStatement.predefined("hex", RegExpNode("[0-9A-Fa-f]")),
        NamespaceStatement.predefined(
          "hex",
          <Statement>[
            DeclarationStatement.predefined("lower", RegExpNode("[0-9a-f]")),
            DeclarationStatement.predefined("upper", RegExpNode("[0-9A-F]")),
          ],
        ),
        DeclarationStatement.predefined("alpha", RegExpNode("[a-zA-Z]")),
        NamespaceStatement.predefined(
          "alpha",
          <Statement>[
            DeclarationStatement.predefined("lower", RegExpNode("[a-z]")),
            DeclarationStatement.predefined("upper", RegExpNode("[A-Z]")),
          ],
        ),
      ],
      tag: Tag.inline,
    ),
  ];

  int redirectId = 0;

  final Map<String, String> renames = <String, String>{};
  final Map<String, String> reverseRenames = <String, String>{};
  final Map<String, (String?, Node)> rules = <String, (String?, Node)>{};
  final Map<String, (String?, Node)> fragments = <String, (String?, Node)>{};
  final Map<String, (String?, Node)> inline = <String, (String?, Node)>{};

  final String? preamble;

  String _compile(
    String parserName, {
    required Map<String, (String?, Node)> rules,
    required Map<String, (String?, Node)> fragments,
    String? start,
    String? type,
  }) {
    String parserTypeString =
        type ?? rules.values.firstOrNull?.$1 ?? fragments.values.firstOrNull?.$1 ?? "Object";
    String parserStartRule = start ?? rules.keys.firstOrNull ?? fragments.keys.first;
    StringBuffer fullBuffer = StringBuffer();

    fullBuffer.writeln("// ignore_for_file: ${ignores.join(", ")}");
    fullBuffer.writeln();

    fullBuffer.writeln("// imports");
    fullBuffer.writeln(importCode);
    if (preamble?.unindent() case String preamble?) {
      fullBuffer.writeln("// PREAMBLE");

      // TODO: Find a way to get dart to analyze this preamble.
      fullBuffer.writeln(preamble);
    }
    fullBuffer.writeln("// base.dart");
    fullBuffer.writeln(baseCode);
    fullBuffer.writeln();

    fullBuffer.writeln("// GENERATED CODE");

    fullBuffer.writeln(
      "final class $parserName extends _PegParser<$parserTypeString> {",
    );
    fullBuffer.writeln("  $parserName();");
    fullBuffer.writeln();
    fullBuffer.writeln("  @override");
    fullBuffer.writeln("  get start => $parserStartRule;");
    fullBuffer.writeln();

    if (ParserCompilerVisitor(isNullable: isNullable) case ParserCompilerVisitor compilerVisitor) {
      for (var (rawName, (type, node)) in fragments.pairs) {
        compilerVisitor.ruleId = 0;

        var inner = StringBuffer();
        var displayName = reverseRenames[rawName]!;
        var body = node.acceptParametrizedVisitor(
          compilerVisitor,
          (
            isNullAllowed: isNullable(node, displayName),
            withNames: null as Set<String>?,
            inner: null,
            reported: true,
            declarationName: displayName,
          ),
        ).indent();

        inner.writeln();
        inner.writeln("/// `$displayName`");
        if (type == null) {
          inner.writeln("late final $rawName = () {");
          inner.writeln(body);
          inner.writeln("};");
        } else {
          inner.writeln(
            "$type${isNullable(node, rawName) ? "" : "?"} $rawName() {",
          );
          inner.writeln(body);
          inner.writeln("}");
        }

        fullBuffer.writeln(inner.toString().indent());
      }

      for (var (rawName, (type, node)) in rules.pairs) {
        compilerVisitor.ruleId = 0;

        var inner = StringBuffer();
        var displayName = reverseRenames[rawName]!;
        var body = node.acceptParametrizedVisitor(
          compilerVisitor,
          (
            isNullAllowed: isNullable(node, rawName),
            withNames: null,
            inner: null,
            reported: true,
            declarationName: displayName,
          ),
        ).indent();

        inner.writeln();
        inner.writeln("/// `$displayName`");
        if (type == null) {
          inner.writeln("late final $rawName = () {");
          inner.writeln(body);
          inner.writeln("};");
        } else {
          inner.writeln(
            "$type${isNullable(node, rawName) ? "" : "?"} $rawName() {",
          );
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
          fullBuffer.write("    { ");
          for (var (int i, (int low, int high)) in ranges.indexed) {
            fullBuffer.write("($low, $high)");

            if (i < ranges.length - 1) {
              fullBuffer.write(", ");
            }
          }
          fullBuffer.writeln(" },");
        }
        fullBuffer.writeln(");".indent());
      }

      fullBuffer.writeln("}");

      if (compilerVisitor.tries.isNotEmpty) {
        fullBuffer.writeln(trieCode);
      }
    }

    return fullBuffer.toString();
  }

  String compileParserGenerator(
    String parserName, {
    String? start,
    String? type,
  }) {
    return _compile(
      parserName,
      rules: rules,
      fragments: fragments,
      start: start,
      type: type,
    );
  }

  String compileAstParserGenerator(String parserName, {String? start}) {
    RemoveActionNodeVisitor removeActionNodeVisitor = const RemoveActionNodeVisitor();
    Map<String, (String?, Node)> rules = <String, (String?, Node)>{
      for (var (String name, (_, Node node)) in this.rules.pairs)
        name: (
          "Object",
          node.acceptSimpleVisitor(removeActionNodeVisitor),
        ),
    };
    Map<String, (String?, Node)> fragments = <String, (String?, Node)>{
      for (var (String name, (_, Node node)) in this.fragments.pairs)
        name: (
          "Object",
          node.acceptSimpleVisitor(removeActionNodeVisitor),
        ),
    };

    return _compile(
      parserName,
      rules: rules,
      fragments: fragments,
      start: start,
      type: "Object",
    );
  }

  String compileCstParserGenerator(String parserName, {String? start}) {
    RemoveActionNodeVisitor removeActionNodeVisitor = const RemoveActionNodeVisitor();
    Map<String, (String?, Node)> rules = <String, (String?, Node)>{
      for (var (String name, (_, Node node)) in this.rules.pairs)
        name: (
          "Object",
          InlineActionNode(
            NamedNode(r"$", node.acceptSimpleVisitor(removeActionNodeVisitor)),
            r"$".wrappedName(reverseRenames[name]!.unwrappedName),
            areIndicesProvided: false,
          )
        ),
    };
    Map<String, (String?, Node)> fragments = <String, (String?, Node)>{
      for (var (String name, (_, Node node)) in this.fragments.pairs)
        name: (
          "Object",
          InlineActionNode(
            NamedNode(r"$", node.acceptSimpleVisitor(removeActionNodeVisitor)),
            r"$".wrappedName(reverseRenames[name]!),
            areIndicesProvided: false,
          )
        ),
    };

    return _compile(
      parserName,
      rules: rules,
      fragments: fragments,
      start: start,
      type: "Object",
    );
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
      SequenceNode() => (
          _isNullable[node] = true,
          node.children.every((Node node) => isNullable(node, ruleName))
        ).$2,
      ChoiceNode() => (
          _isNullable[node] = false,
          node.children.any((Node node) => isNullable(node, ruleName))
        ).$2,
      PlusSeparatedNode() =>
        isNullable(node.child, ruleName) && isNullable(node.separator, ruleName),
      StarSeparatedNode() => true,
      PlusNode() => isNullable(node.child, ruleName),
      StarNode() => true,
      AndPredicateNode() => isNullable(node.child, ruleName),
      NotPredicateNode() => isNullable(node.child, ruleName),
      OptionalNode() => isNullable(node.child, ruleName),
      ReferenceNode() => isNullable(
          rules[node.ruleName]?.$2 ?? notFound(node.ruleName, Tag.rule, ruleName),
          ruleName,
        ),
      FragmentNode() => isNullable(
          fragments[node.fragmentName]?.$2 ??
              inline[node.fragmentName]?.$2 ??
              notFound(node.fragmentName, Tag.fragment, ruleName),
          ruleName,
        ),
      NamedNode() => isNullable(node.child, ruleName),
      ActionNode() => isNullable(node.child, ruleName),
      InlineActionNode() => isNullable(node.child, ruleName),
    };
  }
}

Never notFound(String name, Tag tag, [String? root]) {
  throw ArgumentError.value(
    name,
    "name",
    "$tag not found${root == null ? "" : " in $root"}",
  );
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

    String unindented = lines //
        .map(
          (String line) => line.isEmpty ? line : line.substring(commonIndentation),
        )
        .join("\n");

    return unindented;
  }
}

extension NameShortcuts on Set<String>? {
  /// This gets a single name from the set.
  ///  If the set is null, it returns `$`.
  String get singleName => this == null ? r"$" : this!.first;
  String get varNames => switch (this) {
        null => r"var $",
        Set<String>(length: 1, single: "_") => "_",
        Set<String>(length: 1, single: "null") => "null",
        Set<String>(length: 1, single: String name) => "var $name",
        Set<String> set => set //
            .where((String v) => v != "_")
            .map((String v) => v == "null" ? v : "var $v")
            .toList()
            .apply(
              (List<String> iter) => switch (iter) {
                List<String>(length: 1, :String single) => single,
                List<String>() => iter.join(" && ").apply((String v) => "($v)")
              },
            )
      };
}

extension MonadicTypeExtension<T extends Object> on T {
  O apply<O extends Object>(O Function(T) fn) => fn(this);
}

extension<K, V> on Map<K, V> {
  Iterable<(K, V)> get pairs => entries.map((MapEntry<K, V> v) => (v.key, v.value));
}

extension on String {
  String wrappedName(String declarationName) => //
      declarationName.startsWith("fragment") //
          ? this
          : "(${encode("<${declarationName.unwrappedName}>")}, $this)";

  String get unwrappedName => startsWith("global::") ? substring(8) : this;
}
