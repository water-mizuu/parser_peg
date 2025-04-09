import "dart:collection";
import "dart:convert";
import "dart:io";

import "package:parser_peg/src/node.dart";
import "package:parser_peg/src/statement.dart";
import "package:parser_peg/src/visitor/node_visitor/parametrized_visitor/parser_compiler_visitor.dart";
import "package:parser_peg/src/visitor/node_visitor/"
    "parametrized_visitor/simplify_visitor.dart";
import "package:parser_peg/src/visitor/node_visitor/"
    "simple_visitor/can_inline_visitor.dart";
import "package:parser_peg/src/visitor/node_visitor/"
    "simple_visitor/inline_visitor.dart";
import "package:parser_peg/src/visitor/node_visitor/"
    "simple_visitor/referenced_visitor.dart";
import "package:parser_peg/src/visitor/node_visitor/"
    "simple_visitor/remove_action_node_visitor.dart";
import "package:parser_peg/src/visitor/node_visitor/"
    "simple_visitor/remove_selection_visitor.dart";
import "package:parser_peg/src/visitor/node_visitor/"
    "simple_visitor/rename_visitors.dart";
import "package:parser_peg/src/visitor/node_visitor/"
    "simple_visitor/resolve_references_visitor.dart";
import "package:parser_peg/src/visitor/statement_visitor/"
    "statement_translator_visitor.dart";

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
  "unused_element",
  "collection_methods_unrelated_type",
  "unused_element",
  "use_setters_to_change_properties",
];

final class ParserGenerator {
  ParserGenerator.fromParsed({required this.statements, required this.preamble}) {
    var workingStatements = statements;

    /// We translate all hybrid namespaces to appropriate nodes.
    if (StatementTranslatorVisitor() case StatementTranslatorVisitor visitor) {
      workingStatements = [
        for (var statement in workingStatements) //
          ...statement.acceptVisitor(visitor, null),
      ];
    }

    /// We add all the special nodes :)
    workingStatements.insertAll(0, predefined);

    /// We add ALL the rules in advance.
    ///   Why? Because we need ALL the rules to be able to resolve references.
    ///
    /// This basically resolves all of the declarations in the grammar,
    ///   flattening the namespaces into a single map.
    for (var statement in workingStatements) {
      var stack = Queue<(Statement, List<String>, Tag?)>.from([
        (statement, ["global"], null),
      ]);

      while (stack.isNotEmpty) {
        var (statement, prefix, tag) = stack.removeLast();

        switch (statement) {
          /// If it is a declaration:
          ///   rule declaration, fragment declaration, inline declaration

          case DeclarationStatement(:var type, :var name, :var node, tag: var declaredTag):
            var realName = [...prefix, name].join(separator);
            var target = switch (declaredTag ?? tag) {
              Tag.inline => _inline,
              Tag.fragment => _fragments,
              Tag.rule || null => _rules,
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

          case DeclarationTypeStatement():
          case HybridNamespaceStatement():
            throw Error();
        }
      }
    }

    /// Resolve the references from inside namespaces.
    for (var statement in workingStatements) {
      var stack = Queue<(Statement, List<String>, Tag?)>.from([
        (statement, ["global"], null),
      ]);

      while (stack.isNotEmpty) {
        var (statement, prefixes, tag) = stack.removeLast();

        switch (statement) {
          case DeclarationStatement(:var type, :var name, :var node, tag: var declaredTag):
            var realName = [...prefixes, name].join(separator);
            var visitor = ResolveReferencesVisitor(realName, prefixes, _rules, _fragments, _inline);
            var resolvedNode = node.acceptSimpleVisitor(visitor);

            var target = switch (declaredTag ?? tag) {
              Tag.inline => _inline,
              Tag.fragment => _fragments,
              Tag.rule || null => _rules,
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

          case DeclarationTypeStatement():
          case HybridNamespaceStatement():
            throw Error();
        }
      }
    }

    /// Simple guard against fully inline declarations.
    if (_rules.isNotEmpty) {
      var (key, (type, _)) = _rules.pairs.first;

      _fragments[rootKey] = (type, ReferenceNode(key));
    } else if (_fragments.isNotEmpty) {
      var (key, (type, _)) = _fragments.pairs.first;

      _fragments[rootKey] = (type, FragmentNode(key));
    } else {
      if (_inline.isEmpty) {
        throw Exception("There are no declarations!");
      }

      /// Since there is no rule / fragment, we can add a fake rule.
      var (key, (type, _)) = _inline.pairs.first;

      _fragments[rootKey] = (type, FragmentNode(key));
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
      var rulesRefCount = {for (var rule in _rules.keys) rule: 0};
      var fragmentRefCount = {for (var fragment in _fragments.keys) fragment: 0};
      var inlineRefCount = {for (var inline in _inline.keys) inline: 0};

      var declarations = _fragments
          .pairs //
          .followedBy(_rules.pairs)
          .followedBy(_inline.pairs);

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
        if (count != 1 || _fragments[name] == null) {
          continue;
        }

        var (type, node) = _fragments[name]!;
        _inline[name] = (type, node);
        _fragments.remove(name);
      }

      /// Remove the unreferenced rules,
      for (var (name, count) in rulesRefCount.pairs) {
        if (name == rootKey || count > 0) {
          continue;
        }

        _rules.remove(name);
      }

      /// Remove the unreferenced fragments,
      for (var (name, count) in fragmentRefCount.pairs) {
        if (name == rootKey || count > 0) {
          continue;
        }

        _fragments.remove(name);
      }

      /// And the unused inline rules (optional, does not have any runtime bearing).
      for (var (name, count) in inlineRefCount.pairs) {
        if (name == rootKey || count > 0) {
          continue;
        }

        _inline.remove(name);
      }
    }

    /// We determine the inline-declared rules that can *actually* be inlined.
    ///   We shouldn't throw an error, because it may just be that a rule is
    ///   declared as inline, but it is not actually inline-able, like in a namespace.
    if (CanInlineVisitor(_rules, _fragments, _inline) case CanInlineVisitor visitor) {
      for (var (name, (type, node)) in _inline.pairs.toList()) {
        if (!visitor.canBeInlined(node)) {
          _inline.remove(name);
          _fragments[name] = (type, node);
        }
      }
    }

    /// We inline the rules that can be inlined.
    if (InlineVisitor(_inline) case InlineVisitor visitor) {
      bool runLoop;

      do {
        runLoop = false;
        for (var (name, (type, node)) in _rules.pairs.toList()) {
          var (hasChanged, resolvedNode) = visitor.inlineReferences(node);
          runLoop |= hasChanged;

          _rules[name] = (type, resolvedNode);
        }
        for (var (name, (type, node)) in _fragments.pairs.toList()) {
          var (hasChanged, resolvedNode) = visitor.inlineReferences(node);
          runLoop |= hasChanged;

          _fragments[name] = (type, resolvedNode);
        }
      } while (runLoop);
    }

    /// We simplify the rules to prepare for codegen.
    /// Basically, we limit the depth of each node in the tree.
    /// This allows us to have more simple code.
    if (ParametrizedSimplifyVisitor() case ParametrizedSimplifyVisitor visitor) {
      for (var (name, (type, node)) in _rules.pairs) {
        _rules[name] = (type, visitor.simplify(node));
      }
      for (var (name, (type, node)) in _fragments.pairs) {
        _fragments[name] = (type, visitor.simplify(node));
      }

      /// Since the simplifier visitor can add new fragments, we need to add them.
      _fragments.addAll(visitor.addedFragments);
    }

    /// We rename the rules and fragments.
    redirectId = 0;
    for (var (name, (type, node)) in _rules.pairs.toList()) {
      var simplifiedName = "r${(redirectId++).toRadixString(36)}";

      _rules.remove(name);
      _rules[simplifiedName] = (type, node);
      _renames[name] = simplifiedName;
      _reverseRenames[simplifiedName] = name;
    }
    redirectId = 0;
    for (var (name, (type, node)) in _fragments.pairs.toList()) {
      var simplifiedName = "f${(redirectId++).toRadixString(36)}";

      _fragments.remove(name);
      _fragments[simplifiedName] = (type, node);
      _renames[name] = simplifiedName;
      _reverseRenames[simplifiedName] = name;
    }

    /// We rename the references.
    if (RenameDeclarationVisitor(_renames) case RenameDeclarationVisitor visitor) {
      for (var (name, (type, node)) in _rules.pairs) {
        _rules[name] = (type, visitor.renameDeclarations(node));
      }
      for (var (name, (type, node)) in _fragments.pairs) {
        _fragments[name] = (type, visitor.renameDeclarations(node));
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
    NamespaceStatement("std", <Statement>[
      DeclarationStatement.predefined("any", AnyCharacterNode()),
      DeclarationStatement.predefined("epsilon", EpsilonNode()),
      DeclarationStatement.predefined("start", StartOfInputNode(), type: "int"),
      DeclarationStatement.predefined("end", EndOfInputNode(), type: "int"),
      DeclarationStatement.predefined("whitespace", RegExpNode(r"\s")),
      DeclarationStatement.predefined("digit", RegExpNode(r"\d")),
      DeclarationStatement.predefined("hex", RegExpNode("[0-9A-Fa-f]")),
      NamespaceStatement.predefined("hex", <Statement>[
        DeclarationStatement.predefined("lower", RegExpNode("[0-9a-f]")),
        DeclarationStatement.predefined("upper", RegExpNode("[0-9A-F]")),
      ]),
      DeclarationStatement.predefined("alpha", RegExpNode("[a-zA-Z]")),
      NamespaceStatement.predefined("alpha", <Statement>[
        DeclarationStatement.predefined("lower", RegExpNode("[a-z]")),
        DeclarationStatement.predefined("upper", RegExpNode("[A-Z]")),
      ]),
    ], tag: Tag.inline),
  ];

  int redirectId = 0;

  final String? preamble;
  final List<Statement> statements;
  final Map<String, String> _renames = <String, String>{};
  final Map<String, String> _reverseRenames = <String, String>{};
  final Map<String, (String?, Node)> _rules = <String, (String?, Node)>{};
  final Map<String, (String?, Node)> _fragments = <String, (String?, Node)>{};
  final Map<String, (String?, Node)> _inline = <String, (String?, Node)>{};

  String _compile(
    String parserName, {
    required Map<String, (String?, Node)> rules,
    required Map<String, (String?, Node)> fragments,
    String? start,
    String? type,
  }) {
    var parserTypeString =
        type ?? //
        rules.values.firstOrNull?.$1 ??
        fragments.values.firstOrNull?.$1 ??
        "Object";
    var parserStartRule =
        start ?? //
        rules.keys.firstOrNull ??
        fragments.keys.first;
    var fullBuffer = StringBuffer();

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

    fullBuffer.writeln("final class $parserName extends _PegParser<$parserTypeString> {");
    fullBuffer.writeln("  $parserName();");
    fullBuffer.writeln();
    fullBuffer.writeln("  @override");
    fullBuffer.writeln("  get start => $parserStartRule;");
    fullBuffer.writeln();

    if (ParserCompilerVisitor(isNullable: isNullable, reported: true)
        case ParserCompilerVisitor compilerVisitor) {
      for (var (rawName, (type, node)) in fragments.pairs) {
        compilerVisitor.ruleId = 0;

        var inner = StringBuffer();
        var displayName = _reverseRenames[rawName]!;
        var body =
            node
                .acceptParametrizedVisitor(
                  compilerVisitor,
                  Parameters(
                    isNullAllowed: isNullable(node, displayName),
                    withNames: null,
                    inner: null,
                    declarationName: displayName,
                    markSaved: false,
                  ),
                )
                .indent();

        inner.writeln();
        inner.writeln("/// `$displayName`");
        if (type == null) {
          inner.writeln("late final $rawName = () {");
          inner.writeln(body);
          inner.writeln("};");
        } else {
          inner.writeln("$type${isNullable(node, rawName) ? "" : "?"} $rawName() {");
          inner.writeln(body);
          inner.writeln("}");
        }

        fullBuffer.writeln(inner.toString().indent());
      }

      for (var (rawName, (type, node)) in rules.pairs) {
        compilerVisitor.ruleId = 0;

        var inner = StringBuffer();
        var displayName = _reverseRenames[rawName]!;
        var body =
            node
                .acceptParametrizedVisitor(
                  compilerVisitor,
                  Parameters(
                    isNullAllowed: isNullable(node, rawName),
                    withNames: null,
                    inner: null,
                    declarationName: displayName,
                    markSaved: false,
                  ),
                )
                .indent();

        inner.writeln();
        inner.writeln("/// `$displayName`");
        if (type == null) {
          inner.writeln("late final $rawName = () {");
          inner.writeln(body);
          inner.writeln("};");
        } else {
          inner.writeln("$type${isNullable(node, rawName) ? "" : "?"} $rawName() {");
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
        for (var ranges in compilerVisitor.ranges) {
          fullBuffer.write("    { ");
          for (var (i, (low, high)) in ranges.indexed) {
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

  String compileParserGenerator(String parserName, {String? start, String? type}) {
    return _compile(parserName, rules: _rules, fragments: _fragments, start: start, type: type);
  }

  String compileAstParserGenerator(String parserName, {String? start}) {
    RemoveActionNodeVisitor removeActionNodeVisitor = const RemoveActionNodeVisitor();
    Map<String, (String?, Node)> rules = <String, (String?, Node)>{
      for (var (String name, (_, Node node)) in _rules.pairs)
        name: ("Object", node.acceptSimpleVisitor(removeActionNodeVisitor)),
    };
    Map<String, (String?, Node)> fragments = <String, (String?, Node)>{
      for (var (String name, (_, Node node)) in _fragments.pairs)
        name: ("Object", node.acceptSimpleVisitor(removeActionNodeVisitor)),
    };

    return _compile(parserName, rules: rules, fragments: fragments, start: start, type: "Object");
  }

  String compileCstParserGenerator(String parserName, {String? start}) {
    var removeActionNodeVisitor = const RemoveActionNodeVisitor();
    var removeSelectionVisitor = const RemoveSelectionVisitor();

    var rules = <String, (String?, Node)>{
      for (var (name, (_, node)) in _rules.pairs)
        name: (
          "Object" as String?,
          InlineActionNode(
                NamedNode(
                  r"$",
                  node
                      .acceptSimpleVisitor(removeActionNodeVisitor)
                      .acceptSimpleVisitor(removeSelectionVisitor),
                ),
                r"$".wrappedName(_reverseRenames[name]!.unwrappedName),
                areIndicesProvided: false,
                isSpanUsed: false,
              )
              as Node,
        ),
    };
    var fragments = <String, (String?, Node)>{
      for (var (name, (_, node)) in _fragments.pairs)
        name: (
          "Object" as String?,
          InlineActionNode(
                NamedNode(
                  r"$",
                  node
                      .acceptSimpleVisitor(removeActionNodeVisitor)
                      .acceptSimpleVisitor(removeSelectionVisitor),
                ),
                r"$".wrappedName(_reverseRenames[name]!),
                areIndicesProvided: false,
                isSpanUsed: false,
              )
              as Node,
        ),
    };

    return _compile(
      //
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
      SequenceNode() =>
        (_isNullable[node] = true, node.children.every((node) => isNullable(node, ruleName))).$2,
      ChoiceNode() =>
        (_isNullable[node] = false, node.children.every((node) => isNullable(node, ruleName))).$2,
      PlusSeparatedNode() =>
        isNullable(node.child, ruleName) && isNullable(node.separator, ruleName),
      StarSeparatedNode() => true,
      PlusNode() => isNullable(node.child, ruleName),
      StarNode() => true,
      AndPredicateNode() => isNullable(node.child, ruleName),
      NotPredicateNode() => isNullable(node.child, ruleName),
      ExceptNode() => false,
      OptionalNode() => isNullable(node.child, ruleName),
      ReferenceNode() => isNullable(
        _rules[node.ruleName]?.$2 ?? notFound(node.ruleName, Tag.rule, ruleName),
        ruleName,
      ),
      FragmentNode() => isNullable(
        _fragments[node.fragmentName]?.$2 ??
            _inline[node.fragmentName]?.$2 ??
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
  throw ArgumentError.value(name, "name", "$tag not found${root == null ? "" : " in $root"}");
}

extension IndentationExtension on String {
  // ignore: avoid_positional_boolean_parameters
  String indent([int count = 1, bool shouldIndent = true]) =>
      shouldIndent
          ? trimRight().split("\n").map((v) => v.isEmpty ? v : "${"  " * count}$v").join("\n")
          : this;

  String unindent() {
    if (isEmpty) {
      return this;
    }

    // Remove \r and \t
    String removed = trimRight().replaceAll("\r", "").replaceAll("\t", "    ");

    // Remove trailing right space.
    Iterable<String> lines = removed.split("\n").map((line) => line.trimRight());

    // Unindent the string.
    int commonIndentation = lines //
        .where((line) => line.isNotEmpty)
        .map((line) => line.length - line.trimLeft().length)
        .reduce((a, b) => a < b ? a : b);

    String unindented = lines //
        .map((line) => line.isEmpty ? line : line.substring(commonIndentation))
        .join("\n");

    return unindented;
  }
}

extension NameShortcuts on Set<String>? {
  /// This gets a single name from the set.
  ///  If the set is null, it returns `$`.
  String get singleName => this == null ? r"$" : this!.first;

  String get statementVarNames => switch (this) {
    null => r"var $",
    Set<String>(length: 1, single: "_") => "_",
    Set<String>(length: 1, single: "null") => "null",
    Set<String>(length: 1, single: String name) => "var $name",
    Set<String> set => set //
        .where((v) => v != "_")
        .toList()
        .apply(
          (iter) => switch (iter) {
            List<String>(length: 1, :String single) => single,
            List<String>() => iter.join(" && ").apply((v) => "($v)"),
          },
        )
        .apply((v) => "var $v"),
  };
  String get caseVarNames => switch (this) {
    null => r"var $",
    Set<String>(length: 1, single: "_") => "_",
    Set<String>(length: 1, single: "null") => "null",
    Set<String>(length: 1, single: String name) => "var $name",
    Set<String> set => set //
        .where((v) => v != "_")
        .map((v) => v == "null" ? v : "var $v")
        .toList()
        .apply(
          (iter) => switch (iter) {
            List<String>(length: 1, :String single) => single,
            List<String>() => iter.join(" && ").apply((v) => "($v)"),
          },
        ),
  };
}

extension MonadicTypeExtension<T extends Object> on T {
  O apply<O extends Object>(O Function(T) fn) => fn(this);
}

extension<K, V> on Map<K, V> {
  Iterable<(K, V)> get pairs => entries.map((v) => (v.key, v.value));
}

extension on String {
  String wrappedName(String declarationName) => //
      declarationName.startsWith("fragment") //
          ? this
          : "(${encode("<${declarationName.unwrappedName}>")}, $this)";

  String get unwrappedName => startsWith("global::") ? substring(8) : this;
}
