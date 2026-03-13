import "dart:collection";
import "dart:convert";
import "dart:io";
import "dart:math";

import "package:analyzer/dart/analysis/analysis_context_collection.dart"
    show AnalysisContextCollection;
import "package:analyzer/dart/analysis/results.dart";
import "package:analyzer/dart/ast/ast.dart" hide Statement;
import "package:analyzer/dart/ast/visitor.dart";
import "package:analyzer/dart/element/type.dart";
import "package:analyzer/dart/element/type_system.dart";
import "package:parser_peg/src/node.dart";
import "package:parser_peg/src/parser/grammar_parser.dart";
import "package:parser_peg/src/statement.dart";
import "package:parser_peg/src/visitor/node_visitor/"
    "parametrized_visitor/parser_compiler_visitor.dart";
import "package:parser_peg/src/visitor/node_visitor/"
    "parametrized_visitor/simplify_visitor.dart";
import "package:parser_peg/src/visitor/node_visitor/"
    "simple_visitor/can_inline_visitor.dart";
import "package:parser_peg/src/visitor/node_visitor/"
    "simple_visitor/inline_visitor.dart";
import "package:parser_peg/src/visitor/node_visitor/simple_visitor/is_cut_visitor.dart";
import "package:parser_peg/src/visitor/node_visitor/simple_visitor/is_recursive_visitor.dart";
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
import "package:path/path.dart" as path;

/// A grammar rule entry mapping a [(namespace, name)] pair to its [Node].
///
/// The namespace component is `null` for top-level (global) declarations.
typedef DeclarationEntry = MapEntry<(String?, String), Node>;

/// The reserved rule name inserted as the synthetic entry point of the grammar.
///
/// A `ROOT` fragment is automatically created to delegate to the first
/// declared rule or fragment, giving the generator a unified starting node.
const String rootKey = "ROOT";

final String base = File("lib/src/base.dart").readAsStringSync();
final List<String> splits = base.split(RegExp("(?:/// IMPORTS-SPLIT)|(?:/// TRIE-SPLIT)"));
final String importCode = splits[0].trim();
final String baseCode = splits[1].trim();
final String trieCode = splits[2].trim();

/// JSON-encodes [object] and escapes `$` so the result is safe to embed
/// inside a Dart string literal.
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

/// Transforms parsed grammar [Statement]s into Dart parser source code.
///
/// Construct with [ParserGenerator.fromParsed] and then call one of the
/// three compile methods to produce the final Dart source string:
///
/// - [compileParserGenerator] — preserves semantic actions.
/// - [compileAstParserGenerator] — strips actions; returns an `Object` AST.
/// - [compileCstParserGenerator] — strips actions and selections; returns a
///   labelled CST.
///
/// During construction all optimization passes run eagerly: reference
/// resolution, dead-rule elimination, fragment inlining, tree simplification,
/// and short-name renaming.
final class ParserGenerator {
  /// Creates a [ParserGenerator] from the output of a grammar parser.
  ///
  /// [statements] is the ordered list of top-level grammar declarations
  /// produced by parsing a `.dart_grammar` file.
  /// [preamble] is an optional block of raw Dart source emitted verbatim
  /// before the generated parser class (useful for imports or type aliases
  /// that grammar action code depends on).
  ///
  /// All optimization passes run immediately inside this constructor.
  ParserGenerator.fromParsed({required this.statements, required this.preamble, this.workingPath});

  /// The delimiter used between namespace components in fully-qualified rule names.
  ///
  /// For example, the `lower` rule inside the `alpha` namespace is stored as
  /// `alpha::lower`.
  static const String separator = "::";

  /// Built-in grammar statements automatically prepended to every grammar.
  ///
  /// Defines two predefined namespaces:
  /// - `@inline std` — common character classes: `any`, `epsilon`, `start`,
  ///   `end`, `whitespace`, `digit`, `hex`, `alpha` (and their sub-rules).
  /// - `@fragment json.atom` — basic JSON value patterns: `null`, `true`,
  ///   `false`, `number`, and `string`.
  static const List<Statement> predefined = [
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
    NamespaceStatement("std", [
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
    NamespaceStatement("json", [
      NamespaceStatement.predefined("atom", [
        DeclarationStatement.predefined("null", StringLiteralNode("null")),
        DeclarationStatement.predefined("true", StringLiteralNode("true")),
        DeclarationStatement.predefined("false", StringLiteralNode("false")),
        DeclarationStatement.predefined("number", RegExpNode(r"-?\d+(\.\d+)?([eE][+-]?\d+)?")),

        // number
        //    integer fraction exponent

        // integer
        //    digit
        //    onenine digits
        //    '-' digit
        //    '-' onenine digits

        // digits
        //    digit
        //    digit digits

        // digit
        //    '0'
        //    onenine

        // onenine
        //    '1' . '9'

        // fraction
        //    ""
        //    '.' digits

        // exponent
        //    ""
        //    'E' sign digits
        //    'e' sign digits

        // sign
        //    ""
        //    '+'
        //    '-'
        NamespaceStatement(tag: Tag.fragment, "number", [
          DeclarationStatement.predefined("slow", ReferenceNode("number"), type: "Object"),
          DeclarationStatement.predefined(
            "number",
            SequenceNode([
              ReferenceNode("integer"),
              ReferenceNode("fraction"),
              ReferenceNode("exponent"),
            ], chosenIndex: null),
            type: "Object",
          ),
          DeclarationStatement.predefined(
            "integer",
            ChoiceNode([
              SequenceNode([ReferenceNode("onenine"), ReferenceNode("digits")], chosenIndex: null),
              ReferenceNode("digit"),
              SequenceNode([
                StringLiteralNode("-"),
                ReferenceNode("onenine"),
                ReferenceNode("digits"),
              ], chosenIndex: null),
              SequenceNode([StringLiteralNode("-"), ReferenceNode("digit")], chosenIndex: null),
            ]),
            type: "Object",
          ),
          DeclarationStatement.predefined(
            "digits",
            ChoiceNode([
              SequenceNode([ReferenceNode("digit"), ReferenceNode("digits")], chosenIndex: null),
              ReferenceNode("digit"),
            ]),
            type: "Object",
          ),
          DeclarationStatement.predefined(
            "digit",
            ChoiceNode([StringLiteralNode("0"), ReferenceNode("onenine")]),
            type: "Object",
          ),
          DeclarationStatement.predefined(
            "onenine",
            ChoiceNode([
              StringLiteralNode("1"),
              StringLiteralNode("2"),
              StringLiteralNode("3"),
              StringLiteralNode("4"),
              StringLiteralNode("5"),
              StringLiteralNode("6"),
              StringLiteralNode("7"),
              StringLiteralNode("8"),
              StringLiteralNode("9"),
            ]),
            type: "Object",
          ),
          DeclarationStatement.predefined(
            "fraction",
            ChoiceNode([
              SequenceNode([StringLiteralNode("."), ReferenceNode("digits")], chosenIndex: null),
              EpsilonNode(),
            ]),
            type: "Object",
          ),
          DeclarationStatement.predefined(
            "exponent",
            ChoiceNode([
              SequenceNode([
                ChoiceNode([StringLiteralNode("E"), StringLiteralNode("e")]),
                ReferenceNode("sign"),
                ReferenceNode("digits"),
              ], chosenIndex: null),
              EpsilonNode(),
            ]),
            type: "Object",
          ),
          DeclarationStatement.predefined(
            "sign",
            ChoiceNode([StringLiteralNode("+"), StringLiteralNode("-"), EpsilonNode()]),
            type: "Object",
          ),
        ]),
        DeclarationStatement.predefined("string", StringLiteralNode(r'"([^"\\]|\\.)*"')),
      ]),
    ], tag: Tag.fragment),
  ];

  /// Running counter used by the renaming pass to produce short, sequential
  /// identifiers for rules (`r0`, `r1`, …) and fragments (`f0`, `f1`, …).
  int redirectId = 0;

  /// Optional raw Dart source prepended verbatim to the generated parser file.
  ///
  /// Set via [ParserGenerator.fromParsed]. `null` means no preamble is emitted.
  final String? preamble;

  /// Working path of the parser. This is needed when imports are involved.
  String? workingPath;

  bool _isSetup = false;
  bool get isSetup => _isSetup;

  void setup([String? workingPath]) {
    this.workingPath = workingPath;
    List<Statement> workingStatements = statements;

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

    int importCounter = 0;
    Map<String, (String, Set<String>)> importedUrls = {};
    for (Statement statement in workingStatements) {
      var stack = Queue.of([
        (statement, ["global"], null as Tag?),
      ]);

      while (stack.isNotEmpty) {
        var (statement, prefix, tag) = stack.removeLast();

        switch (statement) {
          /// If it is a declaration:
          ///   rule declaration, fragment declaration, inline declaration
          case ImportStatement(path: var importPath, :var alias):
            if (workingPath == null) {
              print("Tried to import '$importPath', but a working directory was not given.");
              continue;
            }

            String workingDirectory = File(workingPath).parent.absolute.path;
            String importUrl = path.join(workingDirectory, importPath);
            print((workingDirectory, importPath));
            String resultingName = [...prefix, alias].join(separator);

            bool isAlreadyStitched = importedUrls.containsKey(importUrl);
            var (String canonicalPrefix, Set<String> aliases) =
                importedUrls //
                    .putIfAbsent(importUrl, () => ("__imp${importCounter++}__", {}));

            aliases.add(resultingName);

            if (isAlreadyStitched) {
              continue;
            }

            String file = File(importUrl).absolute.readAsStringSync();
            if (GrammarParser() case GrammarParser grammar) {
              switch (grammar.parse(file)) {
                case ParserGenerator generator:
                  stdout.writeln("Successfully parsed grammar!");
                  stdout.writeln("Generating parser.");

                  stack.addAll(
                    generator.statements.reversed.map((s) => (s, [canonicalPrefix], null as Tag?)),
                  );
                case _:
                  stdout.writeln(grammar.reportFailures());
              }
            }
          case DeclarationStatement(:var type, :var name, tag: var declaredTag):
            var realName = [...prefix, name].join(separator);
            var target = switch (declaredTag ?? tag) {
              Tag.inline => _inline,
              Tag.fragment => _fragments,
              Tag.rule || null => _rules,
            };

            target[realName] = (type, ReferenceNode(realName));
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
    ///
    /// This basically resolves all of the declarations in the grammar,
    ///   flattening the namespaces into a single map.
    for (Statement statement in workingStatements) {
      var stack = Queue.of([
        (statement, ["global"], null as Tag?),
      ]);

      while (stack.isNotEmpty) {
        var (statement, prefixes, tag) = stack.removeLast();

        switch (statement) {
          case ImportStatement():
            continue;
          case DeclarationStatement(:var type, :var name, :var node, tag: var declaredTag):
            var realName = [...prefixes, name].join(separator);
            var visitor = ResolveReferencesVisitor(realName, prefixes, _rules, _fragments, _inline);
            var resolvedNode = node.acceptSimpleVisitor(visitor);

            var target = switch (declaredTag ?? tag) {
              Tag.inline => _inline,
              Tag.fragment => _fragments,
              Tag.rule || null => _rules,
            };

            switch (target[realName]) {
              case (String? type, ReferenceNode(:var ruleName)) when ruleName == realName:
                target[realName] = (type, resolvedNode);
              case (String? type, Node existingNode):
                target[realName] = (
                  type,
                  switch (existingNode) {
                    ChoiceNode(:var children) => ChoiceNode([...children, resolvedNode]),
                    var other => ChoiceNode([other, resolvedNode]),
                  },
                );
              case _:
                target[realName] = (type, resolvedNode);
            }

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

    /// We do two things:
    ///   1. Inline fragments that are only called once.
    ///   2. Remove declarations that are not referenced anywhere.
    var referenceCounts = <(Tag, String), int>{
      for (var name in _rules.keys) (Tag.rule, name): 0,
      for (var name in _fragments.keys) (Tag.fragment, name): 0,
      for (var name in _inline.keys) (Tag.fragment, name): 0,

      (Tag.fragment, rootKey): 1,
    };
    if (const ReferencedVisitor() case ReferencedVisitor visitor) {
      var (_, rootRule) = _fragments[rootKey]!;
      var stack = Queue.of([rootRule]);
      var visited = <Node>{};

      /// Collect all of the reachable rules and fragments starting from the root rule.
      while (stack.isNotEmpty) {
        var node = stack.removeLast();
        if (visited.contains(node)) {
          continue;
        }

        visited.add(node);
        for (var (tag, name) in node.acceptSimpleVisitor(visitor)) {
          referenceCounts[(tag, name)] = referenceCounts[(tag, name)]! + 1;
          if (tag == Tag.rule) {
            if (_rules[name] case (_, var rule)) {
              stack.addLast(rule);
            } else {
              throw Exception("Rule '$name' not found.");
            }
          } else if (tag == Tag.fragment) {
            if (_fragments[name] case (_, var fragment)) {
              stack.addLast(fragment);
            } else if (_inline[name] case (_, var inline)) {
              stack.addLast(inline);
            } else {
              throw Exception("Fragment '$name' not found.");
            }
          }
        }
      }

      for (var (key && (tag, name), count) in referenceCounts.pairs.toSet()) {
        /// Remove the others that are not reachable.
        if (count == 0) {
          referenceCounts.remove(key);

          if (tag == Tag.rule) {
            _rules.remove(name);
          } else if (tag == Tag.fragment) {
            if (_fragments.containsKey(name)) {
              _fragments.remove(name);
            } else if (_inline.containsKey(name)) {
              _inline.remove(name);
            }
          }
        }

        /// Inline the fragments that are only called once.
        if (count == 1 && tag == Tag.fragment && _fragments[name] != null) {
          var (type, node) = _fragments[name]!;
          _inline[name] = (type, node);
        }
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

    /// Precompute which high-level rules contain cut nodes.
    ///   This is so that we can optimize the generated code later.
    if (const IsCutVisitor() case IsCutVisitor visitor) {
      for (var (name, (_, node)) in _rules.pairs) {
        _isCut[(Tag.rule, name)] = node.acceptSimpleVisitor(visitor);
      }
      for (var (name, (_, node)) in _fragments.pairs) {
        _isCut[(Tag.fragment, name)] = node.acceptSimpleVisitor(visitor);
      }
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

    /// We assign memoization levels to rules based on their usage.
    /// LR -> Left Recursive Rules
    /// Simple -> Non-left recursive rules / rules that are used more than once.
    /// None -> Rules that are used only once.
    for (var (name, (_, node)) in _rules.pairs) {
      if (IsLeftRecursiveVisitor(name, _rules, _fragments, _inline).isLeftRecursive(node)) {
        _memoLevels[name] = MemoizationLevel.lr;
      } else if ((referenceCounts[(Tag.rule, _reverseRenames[name])] ?? 0) > 1) {
        _memoLevels[name] = MemoizationLevel.simple;
      } else {
        _memoLevels[name] = MemoizationLevel.none;
      }
    }

    _isSetup = true;
  }

  /// The top-level grammar [Statement]s supplied at construction time.
  final List<Statement> statements;
  final Map<String, String> _renames = {};
  final Map<String, String> _reverseRenames = {};
  final Map<String, MemoizationLevel> _memoLevels = {};
  final Map<String, (String?, Node)> _rules = {};
  final Map<String, (String?, Node)> _fragments = {};
  final Map<String, (String?, Node)> _inline = {};
  final Map<(Tag, String), bool> _isCut = {};

  String _compile(
    String parserName, {
    required Map<String, (String?, Node)> rules,
    required Map<String, (String?, Node)> fragments,
    String? start,
    String? type,
    Map<String, DartType>? resolvedTypes,
  }) {
    if (!_isSetup) {
      setup();
    }

    var parserTypeString =
        type ?? //
        resolvedTypes?["ROOT"]?.getDisplayString() ??
        rules.values.firstOrNull?.$1 ??
        fragments.values.firstOrNull?.$1 ??
        "Object";
    parserTypeString = parserTypeString.trim();

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

    if (ParserCompilerVisitor(isPassIfNull: isPassIfNull, reported: true, memoLevels: _memoLevels)
        case ParserCompilerVisitor compilerVisitor) {
      for (var (rawName, (type, node)) in fragments.pairs) {
        type ??= resolvedTypes?[_reverseRenames[rawName]]?.getDisplayString();
        compilerVisitor.ruleId = 0;

        var inner = StringBuffer();
        var displayName = _reverseRenames[rawName]!;
        var isCut = _isCut[(Tag.fragment, displayName)] == true;
        var body = node
            .acceptParametrizedVisitor(
              compilerVisitor,
              Parameters(
                isPassIfNull: isPassIfNull(node, displayName),
                withNames: null,
                inner: null,
                declarationName: displayName,
                isMarked: false,
                isCuttable: false,
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
          inner.writeln(
            "$type${(type.endsWith("?")) || (isPassIfNull(node, rawName) && !isCut) ? "" : "?"} $rawName() {",
          );
          inner.writeln(body);
          inner.writeln("}");
        }

        fullBuffer.writeln(inner.toString().indent());
      }

      for (var (rawName, (type, node)) in rules.pairs) {
        type ??= resolvedTypes?[_reverseRenames[rawName]]?.getDisplayString();
        compilerVisitor.ruleId = 0;

        var inner = StringBuffer();
        var displayName = _reverseRenames[rawName]!;
        var isCut = _isCut[(Tag.rule, displayName)] == true;
        var body = node
            .acceptParametrizedVisitor(
              compilerVisitor,
              Parameters(
                isPassIfNull: isPassIfNull(node, rawName),
                withNames: null,
                inner: null,
                declarationName: displayName,
                isMarked: false,
                isCuttable: false,
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
          inner.writeln(
            "$type${(type.endsWith("?")) || (isPassIfNull(node, rawName) && !isCut) ? "" : "?"} $rawName() {",
          );
          inner.writeln(body);
          inner.writeln("}");
        }

        fullBuffer.writeln(inner.toString().indent());
      }

      fullBuffer
        ..writeln()
        ..writeln("}");

      if (compilerVisitor.regexps.isNotEmpty) {
        fullBuffer.writeln("class _regexp {");
        for (var (i, regExp) in compilerVisitor.regexps.indexed) {
          fullBuffer.writeln("  /// `/$regExp/`");
          fullBuffer.writeln("  static final \$${i + 1} = RegExp(${encode(regExp)});");
        }
        fullBuffer.writeln("}");
      }

      if (compilerVisitor.tries.isNotEmpty) {
        fullBuffer.writeln("class _trie {");
        for (var (i, options) in compilerVisitor.tries.indexed) {
          fullBuffer.writeln("  /// $options");
          fullBuffer.writeln("  final \$$i = Trie.from(${encode(options)});");
        }
        fullBuffer.writeln("}");
      }

      if (compilerVisitor.strings.isNotEmpty) {
        fullBuffer.writeln("class _string {");
        for (var (i, string) in compilerVisitor.strings.indexed) {
          fullBuffer.writeln("  /// `${encode(string)}`");
          fullBuffer.writeln("static const \$${i + 1} = ${encode(string)};".indent());
        }
        fullBuffer.writeln("}");
      }

      if (compilerVisitor.ranges.isNotEmpty) {
        fullBuffer.writeln("class _range {");
        for (var (i, ranges) in compilerVisitor.ranges.indexed) {
          fullBuffer.writeln(
            "  /// `[${ranges.map((r) => switch (r) {
              (var l, var r) when l == r => String.fromCharCode(l),
              (var l, var r) => "${String.fromCharCode(l)}-${String.fromCharCode(r)}",
            }).map((s) => s.trim()).join()}]`",
          );
          fullBuffer.write("  static const \$${i + 1} = { ");
          for (var (j, (low, high)) in ranges.indexed) {
            if (j > 0) {
              fullBuffer.write(", ");
            }

            fullBuffer.write("($low, $high)");
          }
          fullBuffer.writeln(" };");
        }
        fullBuffer.writeln("}");
      }

      if (compilerVisitor.tries.isNotEmpty) {
        fullBuffer.writeln(trieCode);
      }
    }

    /// If we don't want analysis, we just return the buffer as it is.
    return fullBuffer.toString();
  }

  Future<String> _compileAnalyzed(
    String parserName, {
    required Map<String, (String?, Node)> rules,
    required Map<String, (String?, Node)> fragments,
    String? start,
    Map<String, DartType>? resolvedTypes,
    Set<String>? triedConfigurations,
  }) async {
    /// Prepare a temp file for analysis.
    String compiled = _compile(
      parserName,
      rules: rules,
      fragments: fragments,
      start: start,
      resolvedTypes: resolvedTypes,
    );
    File tempFile = .new(path.join("lib", "temp", "hidden.compiled.dart"))
      ..createSync(recursive: true)
      ..writeAsStringSync(compiled);

    /// Get the analysis context available.
    AnalysisContextCollection collection = .new(includedPaths: [tempFile.absolute.path]);
    SomeResolvedUnitResult result = await collection
        .contextFor(tempFile.absolute.path)
        .currentSession
        .getResolvedUnit(tempFile.absolute.path);

    /// There is a compilation error within the code.
    if (result is! ResolvedUnitResult) {
      return "analysis error";
    }

    /// We look for the parser class, which is generated from the grammar.
    ClassDeclaration parser = result
        .unit
        .declarations //
        .whereType<ClassDeclaration>()
        .firstWhere((d) => d.namePart.typeName.lexeme == parserName);

    /// Resolve the return types as they are right now.
    _TypeResolutionVisitor visitor = .new(
      typeSystem: result.typeSystem,
      renames: _renames,
      reverseRenames: _reverseRenames,
    );
    parser.body.visitChildren(visitor);

    /// Start the next iteration's resolved-types map from whatever the
    /// analyzer cleanly resolved this round.
    Map<String, DartType> nextResolvedTypes = visitor.resolvedReturnTypes.toMap();
    Set<String> nextTriedConfigurations = triedConfigurations?.toSet() ?? {};

    bool hasInvalid = visitor.invalidReturnTypes.values.any((v) => v.isNotEmpty);
    bool hasImprovable = visitor.validReturnTypes.values.any((types) {
      // More than one type present and not all of them are Object/Object? —
      // meaning LUB landed on Object but a tighter common type may exist.
      if (types.length <= 1) {
        return false;
      }

      bool hasObject = types.any((t) => _topTypes.contains(t.getDisplayString()));
      bool hasConcrete = types.any((t) => !_topTypes.contains(t.getDisplayString()));

      return hasObject && hasConcrete;
    });

    /// If any rule still has invalid branches, ask the constraint solver
    /// whether a better type hypothesis exists for the stuck rules.
    if (hasInvalid || hasImprovable) {
      _TypeConstraintSolver solver = .new(
        typeSystem: result.typeSystem,
        validReturnTypes: visitor.validReturnTypes,
        invalidReturnTypes: visitor.invalidReturnTypes,
        rules: rules,
        fragments: fragments,
        reverseRenames: _reverseRenames,
      );

      if (solver.solve() case Map<String, DartType> hypotheses) {
        for (var (String key, DartType value) in hypotheses.pairs) {
          nextResolvedTypes[key] = value;
        }
      }
    }

    bool hasChanged =
        resolvedTypes == null ||
        nextResolvedTypes.length != resolvedTypes.length ||
        nextResolvedTypes.keys.any(
          (k) => resolvedTypes[k]?.getDisplayString() != nextResolvedTypes[k]?.getDisplayString(),
        );

    if (hasChanged) {
      List<(String, DartType)> resolvedTypePairs = nextResolvedTypes.pairs.toList()
        ..sort((a, b) => a.$1.compareTo(b.$1));

      String configuration = resolvedTypePairs
          .map((e) => "${e.$1}:${e.$2.getDisplayString()}")
          .join(";");

      /// We only check if it exists when it changed, as the fixed-point
      ///   algorithm gets confused if it stabilizes and thinks it is an oscillation.
      if (nextTriedConfigurations.contains(configuration)) {
        StringBuffer descriptionBuilder = .new();
        for (var (String name, DartType type) in nextResolvedTypes.pairs) {
          if (name == "ROOT") {
            continue;
          }

          if (type.getDisplayString() == resolvedTypes?[name]?.getDisplayString()) {
            continue;
          }

          String rule = (_reverseRenames[_renames[name] ?? name] ?? name).unwrappedName;

          String prev = resolvedTypes?[name]?.getDisplayString() ?? "unknown";
          String next = type.getDisplayString();

          descriptionBuilder.writeln("  '$rule': oscillates between '$prev' and '$next'");
        }
        String description = descriptionBuilder.toString();

        throw TypeParadoxException(
          "Type paradox detected — the following rules have contradictory "
          "type constraints that cannot be resolved:\n$description",
        );
      }

      nextTriedConfigurations.add(configuration);

      /// Do the iteration again.
      return _compileAnalyzed(
        parserName,
        rules: rules,
        fragments: fragments,
        start: start,
        resolvedTypes: nextResolvedTypes,
        triedConfigurations: nextTriedConfigurations,
      );
    } else {
      /// We try to delete the temp file
      try {
        tempFile.parent.deleteSync(recursive: true);
        return compiled;
      } finally {
        if (tempFile.parent.existsSync()) {
          tempFile.parent.deleteSync(recursive: true);
        }
      }
    }
  }

  Future<String> compileAnalyzedParserGenerator(String parserName, {String? start}) {
    return _compileAnalyzed(parserName, rules: _rules, fragments: _fragments, start: start);
  }

  /// Generates a full Dart parser class named [parserName].
  ///
  /// The generated class preserves every semantic action defined in the grammar.
  /// [start] overrides the first declared rule as the entry point.
  /// [type] overrides the inferred return type of the parser's `start` method.
  ///
  /// Returns the complete Dart source as a string, ready to be written to a file.
  String compileParserGenerator(String parserName, {String? start, String? type}) {
    return _compile(parserName, rules: _rules, fragments: _fragments, start: start, type: type);
  }

  /// Generates a Dart parser that produces an untyped Abstract Syntax Tree.
  ///
  /// All semantic action nodes are stripped; every parse rule returns `Object`.
  /// Useful as a starting point before adding typed action code, or for tooling
  /// that only needs the tree shape.
  /// [start] overrides the default entry rule.
  ///
  /// Returns the complete Dart source as a string.
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

  /// Generates a Dart parser that produces a Concrete Syntax Tree (CST).
  ///
  /// Semantic actions and ordered-choice selections are stripped; every matched
  /// sub-tree is wrapped with its display name, yielding a labelled tree that
  /// mirrors the grammar structure. Useful for syntax highlighting, source
  /// mapping, or other tasks that require the full parse context.
  /// [start] overrides the default entry rule.
  ///
  /// Returns the complete Dart source as a string.
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
      parserName, //
      rules: rules,
      fragments: fragments,
      start: start,
      type: "Object",
    );
  }

  final Expando<bool> _isNullable = Expando<bool>();

  /// Returns `true` if [node] can produce a successful match whose value is `null`.
  ///
  /// Used during code generation to decide whether the emitted method should
  /// have a nullable return type. Results are memoised in [_isNullable].
  /// Throws via [notFound] if a referenced rule or fragment cannot be resolved.
  bool isPassIfNull(Node node, String ruleName) {
    if (_isNullable[node] case bool isPassIfNull) {
      return isPassIfNull;
    }

    bool computed;
    if (node is SpecialSymbolNode) {
      computed = false;
    } else if (node is EpsilonNode) {
      computed = true;
    } else if (node is CutNode) {
      computed = true;
    } else if (node is RangeNode) {
      computed = false;
    } else if (node is TriePatternNode) {
      computed = false;
    } else if (node is RegExpNode) {
      /// Absolutely false, because [matchPattern] is nullable.
      computed = false;
    } else if (node is RegExpEscapeNode) {
      computed = false;
    } else if (node is CountedNode) {
      computed = node.min <= 0 || isPassIfNull(node.child, ruleName);
    } else if (node is StringLiteralNode) {
      computed = node.literal.isEmpty;
    } else if (node is SequenceNode) {
      _isNullable[node] = false;
      computed = node.children.every((node) => isPassIfNull(node, ruleName));
    } else if (node is ChoiceNode) {
      _isNullable[node] = false;
      computed = node.children.any((node) => isPassIfNull(node, ruleName));
    } else if (node is PlusSeparatedNode) {
      computed = isPassIfNull(node.child, ruleName) && isPassIfNull(node.separator, ruleName);
    } else if (node is StarSeparatedNode) {
      computed = true;
    } else if (node is PlusNode) {
      computed = isPassIfNull(node.child, ruleName);
    } else if (node is StarNode) {
      computed = true;
    } else if (node is AndPredicateNode) {
      computed = isPassIfNull(node.child, ruleName);
    } else if (node is NotPredicateNode) {
      computed = isPassIfNull(node.child, ruleName);
    } else if (node is ExceptNode) {
      computed = false;
    } else if (node is OptionalNode) {
      computed = true;
    } else if (node is ReferenceNode) {
      computed = isPassIfNull(
        _rules[node.ruleName]?.$2 ?? notFound(node.ruleName, Tag.rule, ruleName),
        ruleName,
      );
    } else if (node is FragmentNode) {
      computed = isPassIfNull(
        _fragments[node.fragmentName]?.$2 ??
            _inline[node.fragmentName]?.$2 ??
            notFound(node.fragmentName, Tag.fragment, ruleName),
        ruleName,
      );
    } else if (node is NamedNode) {
      computed = isPassIfNull(node.child, ruleName);
    } else if (node is ActionNode) {
      computed = isPassIfNull(node.child, ruleName);
    } else if (node is InlineActionNode) {
      computed = isPassIfNull(node.child, ruleName);
    } else {
      throw StateError("Unhandled node type: ${node.runtimeType}");
    }

    return _isNullable[node] = computed;
  }
}

Never notFound(String name, Tag tag, [String? root]) {
  throw ArgumentError.value(name, "name", "$tag not found${root == null ? "" : " in $root"}");
}

/// Indentation and de-indentation helpers for generated Dart source strings.
extension IndentationExtension on String {
  /// Indents every non-empty line by [count] levels of two spaces each.
  ///
  /// If [shouldIndent] is `false`, the string is returned unchanged.
  // ignore: avoid_positional_boolean_parameters
  String indent([int count = 1, bool shouldIndent = true]) => shouldIndent
      ? trimRight().split("\n").map((v) => v.isEmpty ? v : "${"  " * count}$v").join("\n")
      : this;

  /// Removes the common leading indentation shared by all non-empty lines.
  ///
  /// Also normalises `\r` characters and expands tabs to four spaces before
  /// computing the minimum indentation level.
  String unindent() {
    if (isEmpty) {
      return this;
    }

    // Remove \r and \t
    String removed = trimRight().replaceAll("\r", "").replaceAll("\t", "    ");

    // Remove trailing right space.
    Iterable<String> lines = removed.split("\n").map((line) => line.trimRight());

    // Unindent the string.
    int commonIndentation =
        lines //
            .where((line) => line.isNotEmpty)
            .map((line) => line.length - line.trimLeft().length)
            .reduce((a, b) => a < b ? a : b);

    String unindented =
        lines //
            .map((line) => line.isEmpty ? line : line.substring(commonIndentation))
            .join("\n");

    return unindented;
  }
}

/// Resolves a nullable set of binding names from a grammar action into Dart
/// variable-declaration and pattern-matching syntax.
extension NameShortcuts on Set<String>? {
  /// Returns a single representative binding name from the set.
  ///
  /// Returns `$` when the set is `null`, when the set is empty, or when every
  /// name is `_`. Otherwise returns the first non-`_` name.
  String get singleName => this == null ? r"$" : this!.where((v) => v != "_").firstOrNull ?? r"$";

  /// Returns a `var` declaration string for use in a statement context.
  ///
  /// - `null` → `var $`
  /// - `{"_"}` → `_` (discard)
  /// - `{"x"}` → `var x`
  /// - multiple non-`_` names → `var (x && y)`
  String get statementVarNames => switch (this) {
    null => r"var $",
    Set<String>(length: 1, single: "_") => "_",
    Set<String>(length: 1, single: "null") => "null",
    Set<String>(length: 1, single: String name) => "var $name",
    Set<String> set =>
      set //
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

  /// Returns a pattern-binding string for use inside a `case` clause.
  ///
  /// Similar to [statementVarNames] but prefixes each name individually with
  /// `var` rather than wrapping the whole declaration.
  String get caseVarNames => switch (this) {
    null => r"var $",
    Set<String>(length: 1, single: "_") => "_",
    Set<String>(length: 1, single: "null") => "null",
    Set<String>(length: 1, single: String name) => "var $name",
    Set<String> set =>
      set //
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

/// Adds a pipeline [apply] operation to every non-null value.
extension MonadicTypeExtension<T extends Object> on T {
  /// Passes `this` through [fn] and returns the result.
  ///
  /// Equivalent to `fn(this)`, but allows transformations to be chained
  /// inline without introducing intermediate local variables.
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

const Set<String> _topTypes = {"Object", "Object?", "dynamic"};

// ignore: unused_element
class _TypeResolutionVisitor extends RecursiveAstVisitor<void> {
  _TypeResolutionVisitor({
    required this.typeSystem,
    required this.renames,
    required this.reverseRenames,
  }) : resolvedReturnTypes = {},
       validReturnTypes = {},
       invalidReturnTypes = {};

  final TypeSystem typeSystem;
  final Map<String, String> renames;
  final Map<String, String> reverseRenames;
  final Map<String, DartType> resolvedReturnTypes;
  final Map<String, List<DartType>> validReturnTypes;
  final Map<String, List<DartType>> invalidReturnTypes;

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    String declaredName = node.name.lexeme;
    String? actualName = reverseRenames[declaredName];
    if (actualName == null) {
      return;
    }
    _resolve(actualName, node.body);
    super.visitMethodDeclaration(node);
  }

  @override
  void visitFieldDeclaration(FieldDeclaration node) {
    for (VariableDeclaration declaration in node.fields.variables) {
      String declaredName = declaration.name.lexeme;
      String? actualName = reverseRenames[declaredName];
      if (actualName == null) {
        return;
      }
      Expression expression = declaration.initializer!;
      if (expression is! FunctionExpression) {
        return;
      }
      _resolve(actualName, expression.body);
    }
    super.visitFieldDeclaration(node);
  }

  void _resolve(String originalName, FunctionBody functionBody) {
    _ReturnTypeCollector collector = .new();
    functionBody.accept(collector);
    List<DartType> types = collector.types;

    if (types.isEmpty) {
      throw StateError("Rule / Fragment $originalName has no return!");
    }

    var valid = types.where((t) => !t.getDisplayString().contains("InvalidType")).toList();
    var invalid = types.where((t) => t.getDisplayString().contains("InvalidType")).toList();

    validReturnTypes[originalName] = valid;
    invalidReturnTypes[originalName] = invalid;

    if (valid.isEmpty) {
      resolvedReturnTypes.remove(originalName);
    } else {
      resolvedReturnTypes[originalName] = valid.reduce(typeSystem.leastUpperBound);
    }

    // print((originalName, types, resolvedReturnTypes[originalName]));
  }
}

// ignore: unused_element
class _ReturnTypeCollector extends RecursiveAstVisitor<void> {
  final List<DartType> types = [];

  @override
  void visitReturnStatement(ReturnStatement node) {
    var t = node.expression?.staticType;
    if (t != null) {
      types.add(t);
    }

    super.visitReturnStatement(node);
  }
}

// ignore: unused_element
class _TypeConstraintSolver {
  const _TypeConstraintSolver({
    required this.typeSystem,
    required this.validReturnTypes,
    required this.invalidReturnTypes,
    required this.rules,
    required this.fragments,
    required this.reverseRenames,
  });

  final TypeSystem typeSystem;
  final Map<String, List<DartType>> validReturnTypes;
  final Map<String, List<DartType>> invalidReturnTypes;
  final Map<String, (String?, Node)> rules;
  final Map<String, (String?, Node)> fragments;
  final Map<String, String> reverseRenames;

  /// Returns an updated type map with better hypotheses for stuck SCCs,
  /// or `null` if no improvement is possible.
  Map<String, DartType>? solve() {
    /// If there are no invalid types, then we don't have to do anything.
    bool hasInvalid = invalidReturnTypes.values.any((v) => v.isNotEmpty);

    /// [hasImprovable] is important in cases where self reference cause bleeding
    ///   into Object. That is, in rules such as:
    ///
    /// ```
    /// expression = expression | \d+ { int.parse($) };
    /// ```
    ///
    /// It resolves
    bool hasImprovable = validReturnTypes.values.any((types) {
      // More than one type present and not all of them are Object/Object? —
      // meaning LUB landed on Object but a tighter common type may exist.
      if (types.length <= 1) {
        return false;
      }

      var hasObject = types.any((t) => _topTypes.contains(t.getDisplayString()));
      var hasConcrete = types.any((t) => !_topTypes.contains(t.getDisplayString()));

      return hasObject && hasConcrete;
    });

    if (!(hasInvalid || hasImprovable)) {
      return null;
    }

    var deps = _buildDependencyGraph();
    var sccs = _findStronglyConnectedComponents(deps);
    var result = <String, DartType>{};
    for (var component in sccs) {
      /// Process this SCC if any member has invalid branches OR has a mix of
      /// Object and concrete types — the latter means LUB silently widened to
      /// Object when a tighter type may exist (e.g. [Object, int] → Object,
      /// where the Object came from a self-reference typed too broadly).
      var hasInvalidInScc = component.any((r) => invalidReturnTypes[r]?.isNotEmpty ?? false);
      var hasImprovableInScc =
          _isSccSinglyRecursive(component, deps) &&
          component.any((r) {
            var types = validReturnTypes[r] ?? [];
            if (types.length <= 1) {
              return false;
            }

            var hasObject = types.any((t) => _topTypes.contains(t.getDisplayString()));
            var hasConcrete = types.any((t) => !_topTypes.contains(t.getDisplayString()));

            return hasObject && hasConcrete;
          });

      if (!hasInvalidInScc && !hasImprovableInScc) {
        continue;
      }

      // Gather every valid return type seen in this component.
      var candidates = [for (var r in component) ...?validReturnTypes[r]];
      var hypothesis = _mostSpecific(candidates);
      if (hypothesis == null) {
        continue;
      }

      for (var r in component) {
        var currentLub = validReturnTypes[r]?.fold<DartType?>(
          null,
          (prev, t) => prev == null ? t : typeSystem.leastUpperBound(prev, t),
        );

        // Only inject if the hypothesis is strictly more specific.
        var hypothesisStr = hypothesis.getDisplayString();
        var currentStr = currentLub?.getDisplayString();
        if (currentStr == null ||
            (typeSystem.isSubtypeOf(hypothesis, currentLub!) && hypothesisStr != currentStr)) {
          result[r] = hypothesis;
        }
      }
    }

    return result.isEmpty ? null : result;
  }

  Map<String, Set<String>> _buildDependencyGraph() {
    var deps = <String, Set<String>>{};

    for (var (rawName, (_, node)) in {...rules, ...fragments}.pairs) {
      var originalName = reverseRenames[rawName] ?? rawName;

      deps[originalName] = {
        for (final (_, refName) in node.acceptSimpleVisitor(const ReferencedVisitor()))
          if (reverseRenames.containsKey(refName)) reverseRenames[refName]!,
      };
    }

    return deps;
  }

  bool _isSccSinglyRecursive(Set<String> component, Map<String, Set<String>> deps) {
    if (component.length > 1) {
      return true;
    }
    // Single-node SCC: only recursive if the node references itself.
    String node = component.single;
    return deps[node]?.contains(node) ?? false;
  }

  List<Set<String>> _findStronglyConnectedComponents(Map<String, Set<String>> deps) {
    var index = <String, int>{};
    var lowlink = <String, int>{};
    var onStack = <String>{};
    var stack = <String>[];
    var sccs = <Set<String>>[];
    var counter = 0;

    void strongConnect(String v) {
      index[v] = lowlink[v] = counter++;
      stack.add(v);
      onStack.add(v);

      for (var w in deps[v] ?? const <String>{}) {
        if (!index.containsKey(w)) {
          strongConnect(w);
          lowlink[v] = min(lowlink[v]!, lowlink[w]!);
        } else if (onStack.contains(w)) {
          lowlink[v] = min(lowlink[v]!, index[w]!);
        }
      }

      if (lowlink[v] == index[v]) {
        var scc = <String>{};
        String w;
        do {
          w = stack.removeLast();
          onStack.remove(w);
          scc.add(w);
        } while (w != v);
        sccs.add(scc);
      }
    }

    for (var v in deps.keys) {
      if (!index.containsKey(v)) {
        strongConnect(v);
      }
    }

    return sccs;
  }

  /// Returns the most specific upper bound, without Object.
  DartType? _mostSpecific(List<DartType> types) {
    var concrete = types.where((t) => !_topTypes.contains(t.getDisplayString())).toList();
    if (concrete.isEmpty) {
      return null;
    }

    // LUB of the concrete types gives the tightest common ancestor.
    return concrete.reduce(typeSystem.leastUpperBound);
  }
}

class TypeParadoxException implements Exception {
  TypeParadoxException(this.message);
  final String message;

  @override
  String toString() => "TypeParadoxException: $message";
}

extension<K, V> on Map<K, V> {
  Map<K, V> toMap() => {...this};
}
