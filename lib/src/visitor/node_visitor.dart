import "package:parser_peg/src/node.dart";

/// A visitor interface for traversing the PEG grammar [Node] hierarchy
/// without any additional input parameters.
///
/// Implementors must provide a handler for every concrete [Node] subtype.
/// Each `visit*` method receives the specific node and returns a value of
/// type [O], allowing callers to fold or transform the AST into an
/// arbitrary result type.
///
/// Use [SimpleNodeVisitor] when the traversal is purely a function of the
/// node tree itself. If extra context needs to be threaded through the
/// traversal, use [ParametrizedNodeVisitor] instead.
///
/// Example — collecting all string literals used in a grammar:
/// ```dart
/// class LiteralCollector extends SimpleNodeVisitor<List<String>> {
///   @override
///   List<String> visitStringLiteralNode(StringLiteralNode node) => [node.literal];
///   // ...other visit methods return []
/// }
/// ```
abstract class SimpleNodeVisitor<O> {
  /// Visits an [EpsilonNode], which always succeeds while consuming no input.
  O visitEpsilonNode(EpsilonNode node);

  /// Visits a [TriePatternNode], which matches one of several string options
  /// using a trie for efficient dispatch.
  O visitTriePatternNode(TriePatternNode node);

  /// Visits a [StringLiteralNode], which matches an exact string literal.
  O visitStringLiteralNode(StringLiteralNode node);

  /// Visits a [RangeNode], which matches a single character within one or
  /// more Unicode code-point ranges.
  O visitRangeNode(RangeNode node);

  /// Visits a [RegExpNode], which matches input against a regular expression.
  O visitRegExpNode(RegExpNode node);

  /// Visits a [RegExpEscapeNode], which represents a regex escape sequence
  /// such as `\d`, `\w`, or `\s`.
  O visitRegExpEscapeNode(RegExpEscapeNode node);

  /// Visits a [SequenceNode], which matches all of its children in order.
  O visitSequenceNode(SequenceNode node);

  /// Visits a [ChoiceNode], which tries each alternative in order and
  /// succeeds with the first match (ordered choice `/`).
  O visitChoiceNode(ChoiceNode node);

  /// Visits a [CountedNode], which matches its child a specific number of
  /// times.
  O visitCountedNode(CountedNode node);

  /// Visits a [PlusSeparatedNode], which matches one or more repetitions of
  /// its child separated by a delimiter.
  O visitPlusSeparatedNode(PlusSeparatedNode node);

  /// Visits a [StarSeparatedNode], which matches zero or more repetitions of
  /// its child separated by a delimiter.
  O visitStarSeparatedNode(StarSeparatedNode node);

  /// Visits a [PlusNode], which matches one or more repetitions (`+`).
  O visitPlusNode(PlusNode node);

  /// Visits a [StarNode], which matches zero or more repetitions (`*`).
  O visitStarNode(StarNode node);

  /// Visits an [AndPredicateNode], which succeeds if its child matches but
  /// consumes no input (`&e`).
  O visitAndPredicateNode(AndPredicateNode node);

  /// Visits a [NotPredicateNode], which succeeds if its child does *not*
  /// match and consumes no input (`!e`).
  O visitNotPredicateNode(NotPredicateNode node);

  /// Visits an [OptionalNode], which matches its child zero or one time (`?`).
  O visitOptionalNode(OptionalNode node);

  /// Visits an [ExceptNode], which matches any single token that does *not*
  /// satisfy its child expression.
  O visitExceptNode(ExceptNode node);

  /// Visits a [ReferenceNode], which is a named reference to another grammar
  /// rule.
  O visitReferenceNode(ReferenceNode node);

  /// Visits a [FragmentNode], which is an inlined rule fragment that does not
  /// produce its own parse-tree node.
  O visitFragmentNode(FragmentNode node);

  /// Visits a [NamedNode], which attaches a label to a sub-expression so it
  /// can be referenced in actions.
  O visitNamedNode(NamedNode node);

  /// Visits an [ActionNode], which wraps an expression with a semantic action
  /// (a code block executed after a successful match).
  O visitActionNode(ActionNode node);

  /// Visits an [InlineActionNode], which is an action expressed inline within
  /// the grammar rule.
  O visitInlineActionNode(InlineActionNode node);

  /// Visits a [StartOfInputNode], which asserts that the current position is
  /// the start of the input.
  O visitStartOfInputNode(StartOfInputNode node);

  /// Visits an [EndOfInputNode], which asserts that the current position is
  /// the end of the input.
  O visitEndOfInputNode(EndOfInputNode node);

  /// Visits an [AnyCharacterNode], which matches any single character (`.`).
  O visitAnyCharacterNode(AnyCharacterNode node);
}

/// A visitor interface for traversing the PEG grammar [Node] hierarchy
/// with an additional input parameter of type [I] threaded through every
/// visit call.
///
/// This is the parametrised counterpart to [SimpleNodeVisitor]. Every
/// `visit*` method receives both the specific node and a value of type [I],
/// which can carry context needed during traversal (e.g., a symbol table,
/// indentation level, or compilation state). The methods return a value of
/// type [O].
///
/// Use [ParametrizedNodeVisitor] when the result of visiting a node depends
/// not only on the node itself but also on some external context that varies
/// during traversal. If no extra parameter is needed, prefer the simpler
/// [SimpleNodeVisitor].
abstract class ParametrizedNodeVisitor<O, I> {
  /// Visits an [EpsilonNode] with the given [parameters].
  O visitEpsilonNode(EpsilonNode node, I parameters);

  /// Visits a [TriePatternNode] with the given [parameters].
  O visitTriePatternNode(TriePatternNode node, I parameters);

  /// Visits a [StringLiteralNode] with the given [parameters].
  O visitStringLiteralNode(StringLiteralNode node, I parameters);

  /// Visits a [RangeNode] with the given [parameters].
  O visitRangeNode(RangeNode node, I parameters);

  /// Visits a [RegExpNode] with the given [parameters].
  O visitRegExpNode(RegExpNode node, I parameters);

  /// Visits a [RegExpEscapeNode] with the given [parameters].
  O visitRegExpEscapeNode(RegExpEscapeNode node, I parameters);

  /// Visits a [SequenceNode] with the given [parameters].
  O visitSequenceNode(SequenceNode node, I parameters);

  /// Visits a [ChoiceNode] with the given [parameters].
  O visitChoiceNode(ChoiceNode node, I parameters);

  /// Visits a [CountedNode] with the given [parameters].
  O visitCountedNode(CountedNode node, I parameters);

  /// Visits a [PlusSeparatedNode] with the given [parameters].
  O visitPlusSeparatedNode(PlusSeparatedNode node, I parameters);

  /// Visits a [StarSeparatedNode] with the given [parameters].
  O visitStarSeparatedNode(StarSeparatedNode node, I parameters);

  /// Visits a [PlusNode] with the given [parameters].
  O visitPlusNode(PlusNode node, I parameters);

  /// Visits a [StarNode] with the given [parameters].
  O visitStarNode(StarNode node, I parameters);

  /// Visits an [AndPredicateNode] with the given [parameters].
  O visitAndPredicateNode(AndPredicateNode node, I parameters);

  /// Visits a [NotPredicateNode] with the given [parameters].
  O visitNotPredicateNode(NotPredicateNode node, I parameters);

  /// Visits an [OptionalNode] with the given [parameters].
  O visitOptionalNode(OptionalNode node, I parameters);

  /// Visits an [ExceptNode] with the given [parameters].
  O visitExceptNode(ExceptNode node, I parameters);

  /// Visits a [ReferenceNode] with the given [parameters].
  O visitReferenceNode(ReferenceNode node, I parameters);

  /// Visits a [FragmentNode] with the given [parameters].
  O visitFragmentNode(FragmentNode node, I parameters);

  /// Visits a [NamedNode] with the given [parameters].
  O visitNamedNode(NamedNode node, I parameters);

  /// Visits an [ActionNode] with the given [parameters].
  O visitActionNode(ActionNode node, I parameters);

  /// Visits an [InlineActionNode] with the given [parameters].
  O visitInlineActionNode(InlineActionNode node, I parameters);

  /// Visits a [StartOfInputNode] with the given [parameters].
  O visitStartOfInputNode(StartOfInputNode node, I parameters);

  /// Visits an [EndOfInputNode] with the given [parameters].
  O visitEndOfInputNode(EndOfInputNode node, I parameters);

  /// Visits an [AnyCharacterNode] with the given [parameters].
  O visitAnyCharacterNode(AnyCharacterNode node, I parameters);
}
