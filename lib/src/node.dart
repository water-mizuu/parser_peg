// ignore_for_file: use_to_and_as_if_applicable

import "package:parser_peg/src/visitor/node_visitor.dart";

sealed class Node {
  O acceptSimpleVisitor<O>(SimpleNodeVisitor<O> visitor);
  O acceptParametrizedVisitor<O, I>(ParametrizedNodeVisitor<O, I> visitor, I parameters);
}

sealed class AtomicNode implements Node {}

class EpsilonNode implements AtomicNode {
  const EpsilonNode();

  @override
  O acceptSimpleVisitor<O>(SimpleNodeVisitor<O> visitor) => visitor.visitEpsilonNode(this);

  @override
  O acceptParametrizedVisitor<O, I>(ParametrizedNodeVisitor<O, I> visitor, I parameters) =>
      visitor.visitEpsilonNode(this, parameters);
}

class TriePatternNode implements AtomicNode {
  const TriePatternNode(this.options);
  final List<String> options;

  @override
  O acceptSimpleVisitor<O>(SimpleNodeVisitor<O> visitor) => visitor.visitTriePatternNode(this);

  @override
  O acceptParametrizedVisitor<O, I>(ParametrizedNodeVisitor<O, I> visitor, I parameters) =>
      visitor.visitTriePatternNode(this, parameters);
}

class StringLiteralNode implements AtomicNode {
  const StringLiteralNode(this.literal);
  final String literal;

  @override
  O acceptSimpleVisitor<O>(SimpleNodeVisitor<O> visitor) => visitor.visitStringLiteralNode(this);

  @override
  O acceptParametrizedVisitor<O, I>(ParametrizedNodeVisitor<O, I> visitor, I parameters) =>
      visitor.visitStringLiteralNode(this, parameters);
}

class RangeNode implements AtomicNode {
  const RangeNode(this.ranges);
  final Set<(int, int)> ranges;

  @override
  O acceptSimpleVisitor<O>(SimpleNodeVisitor<O> visitor) => visitor.visitRangeNode(this);

  @override
  O acceptParametrizedVisitor<O, I>(ParametrizedNodeVisitor<O, I> visitor, I parameters) =>
      visitor.visitRangeNode(this, parameters);
}

class RegExpNode implements AtomicNode {
  const RegExpNode(this.value);
  final String value;

  @override
  O acceptSimpleVisitor<O>(SimpleNodeVisitor<O> visitor) => visitor.visitRegExpNode(this);

  @override
  O acceptParametrizedVisitor<O, I>(ParametrizedNodeVisitor<O, I> visitor, I parameters) =>
      visitor.visitRegExpNode(this, parameters);
}

abstract interface class RegExpEscapeNode implements AtomicNode {
  const RegExpEscapeNode(this.pattern);

  final String pattern;

  @override
  O acceptSimpleVisitor<O>(SimpleNodeVisitor<O> visitor) => visitor.visitRegExpEscapeNode(this);

  @override
  O acceptParametrizedVisitor<O, I>(ParametrizedNodeVisitor<O, I> visitor, I parameters) =>
      visitor.visitRegExpEscapeNode(this, parameters);
}

enum SimpleRegExpEscapeNode implements RegExpEscapeNode {
  digit(r"\d"),
  word(r"\w"),
  whitespace(r"\s"),

  /// Inverses
  notDigit(r"\D"),
  notWord(r"\W"),
  notWhitespace(r"\S"),

  /// Spaces
  tab(r"\t"),
  newline(r"\n"),
  carriageReturn(r"\r"),
  formFeed(r"\f"),
  verticalTab(r"\v");

  const SimpleRegExpEscapeNode(this.pattern);

  @override
  final String pattern;

  @override
  O acceptSimpleVisitor<O>(SimpleNodeVisitor<O> visitor) => visitor.visitRegExpEscapeNode(this);

  @override
  O acceptParametrizedVisitor<O, I>(ParametrizedNodeVisitor<O, I> visitor, I parameters) =>
      visitor.visitRegExpEscapeNode(this, parameters);
}

class SequenceNode implements Node {
  const SequenceNode(this.children, {required this.chosenIndex});

  final int? chosenIndex;
  final List<Node> children;

  @override
  O acceptSimpleVisitor<O>(SimpleNodeVisitor<O> visitor) => visitor.visitSequenceNode(this);

  @override
  O acceptParametrizedVisitor<O, I>(ParametrizedNodeVisitor<O, I> visitor, I parameters) =>
      visitor.visitSequenceNode(this, parameters);
}

class ChoiceNode implements Node {
  const ChoiceNode(this.children);

  final List<Node> children;

  @override
  O acceptSimpleVisitor<O>(SimpleNodeVisitor<O> visitor) => visitor.visitChoiceNode(this);

  @override
  O acceptParametrizedVisitor<O, I>(ParametrizedNodeVisitor<O, I> visitor, I parameters) =>
      visitor.visitChoiceNode(this, parameters);
}

class CountedNode implements Node {
  const CountedNode(this.min, this.max, this.child);

  final Node child;
  final int min;
  final int? max;

  @override
  O acceptSimpleVisitor<O>(SimpleNodeVisitor<O> visitor) => visitor.visitCountedNode(this);

  @override
  O acceptParametrizedVisitor<O, I>(ParametrizedNodeVisitor<O, I> visitor, I parameters) =>
      visitor.visitCountedNode(this, parameters);
}

class PlusSeparatedNode implements Node {
  const PlusSeparatedNode(this.separator, this.child, {required this.isTrailingAllowed});

  final Node separator;
  final Node child;
  final bool isTrailingAllowed;

  @override
  O acceptSimpleVisitor<O>(SimpleNodeVisitor<O> visitor) => visitor.visitPlusSeparatedNode(this);

  @override
  O acceptParametrizedVisitor<O, I>(ParametrizedNodeVisitor<O, I> visitor, I parameters) =>
      visitor.visitPlusSeparatedNode(this, parameters);
}

class StarSeparatedNode implements Node {
  const StarSeparatedNode(this.separator, this.child, {required this.isTrailingAllowed});

  final Node separator;
  final Node child;
  final bool isTrailingAllowed;

  @override
  O acceptSimpleVisitor<O>(SimpleNodeVisitor<O> visitor) => visitor.visitStarSeparatedNode(this);

  @override
  O acceptParametrizedVisitor<O, I>(ParametrizedNodeVisitor<O, I> visitor, I parameters) =>
      visitor.visitStarSeparatedNode(this, parameters);
}

class PlusNode implements Node {
  const PlusNode(this.child);
  final Node child;

  @override
  O acceptSimpleVisitor<O>(SimpleNodeVisitor<O> visitor) => visitor.visitPlusNode(this);

  @override
  O acceptParametrizedVisitor<O, I>(ParametrizedNodeVisitor<O, I> visitor, I parameters) =>
      visitor.visitPlusNode(this, parameters);
}

class StarNode implements Node {
  const StarNode(this.child);
  final Node child;

  @override
  O acceptSimpleVisitor<O>(SimpleNodeVisitor<O> visitor) => visitor.visitStarNode(this);

  @override
  O acceptParametrizedVisitor<O, I>(ParametrizedNodeVisitor<O, I> visitor, I parameters) =>
      visitor.visitStarNode(this, parameters);
}

class AndPredicateNode implements Node {
  const AndPredicateNode(this.child);
  final Node child;

  @override
  O acceptSimpleVisitor<O>(SimpleNodeVisitor<O> visitor) => visitor.visitAndPredicateNode(this);

  @override
  O acceptParametrizedVisitor<O, I>(ParametrizedNodeVisitor<O, I> visitor, I parameters) =>
      visitor.visitAndPredicateNode(this, parameters);
}

class NotPredicateNode implements Node {
  const NotPredicateNode(this.child);
  final Node child;

  @override
  O acceptSimpleVisitor<O>(SimpleNodeVisitor<O> visitor) => visitor.visitNotPredicateNode(this);

  @override
  O acceptParametrizedVisitor<O, I>(ParametrizedNodeVisitor<O, I> visitor, I parameters) =>
      visitor.visitNotPredicateNode(this, parameters);
}

class OptionalNode implements Node {
  const OptionalNode(this.child);
  final Node child;

  @override
  O acceptSimpleVisitor<O>(SimpleNodeVisitor<O> visitor) => visitor.visitOptionalNode(this);

  @override
  O acceptParametrizedVisitor<O, I>(ParametrizedNodeVisitor<O, I> visitor, I parameters) =>
      visitor.visitOptionalNode(this, parameters);
}

class ReferenceNode implements Node {
  const ReferenceNode(this.ruleName);
  final String ruleName;

  @override
  O acceptSimpleVisitor<O>(SimpleNodeVisitor<O> visitor) => visitor.visitReferenceNode(this);

  @override
  O acceptParametrizedVisitor<O, I>(ParametrizedNodeVisitor<O, I> visitor, I parameters) =>
      visitor.visitReferenceNode(this, parameters);
}

class FragmentNode implements Node {
  const FragmentNode(this.fragmentName);
  final String fragmentName;

  @override
  O acceptSimpleVisitor<O>(SimpleNodeVisitor<O> visitor) => visitor.visitFragmentNode(this);

  @override
  O acceptParametrizedVisitor<O, I>(ParametrizedNodeVisitor<O, I> visitor, I parameters) =>
      visitor.visitFragmentNode(this, parameters);
}

class NamedNode implements Node {
  const NamedNode(this.name, this.child);
  final Node child;
  final String name;

  @override
  O acceptSimpleVisitor<O>(SimpleNodeVisitor<O> visitor) => visitor.visitNamedNode(this);

  @override
  O acceptParametrizedVisitor<O, I>(ParametrizedNodeVisitor<O, I> visitor, I parameters) =>
      visitor.visitNamedNode(this, parameters);
}

class ActionNode implements Node {
  const ActionNode(this.child, this.action, {required this.areIndicesProvided});
  final Node child;
  final String action;
  final bool areIndicesProvided;

  @override
  O acceptSimpleVisitor<O>(SimpleNodeVisitor<O> visitor) => visitor.visitActionNode(this);

  @override
  O acceptParametrizedVisitor<O, I>(ParametrizedNodeVisitor<O, I> visitor, I parameters) =>
      visitor.visitActionNode(this, parameters);
}

class InlineActionNode implements Node {
  const InlineActionNode(this.child, this.action, {required this.areIndicesProvided});
  final Node child;
  final String action;
  final bool areIndicesProvided;

  @override
  O acceptSimpleVisitor<O>(SimpleNodeVisitor<O> visitor) => visitor.visitInlineActionNode(this);

  @override
  O acceptParametrizedVisitor<O, I>(ParametrizedNodeVisitor<O, I> visitor, I parameters) =>
      visitor.visitInlineActionNode(this, parameters);
}

sealed class SpecialSymbolNode implements AtomicNode {}

class StartOfInputNode implements SpecialSymbolNode {
  const StartOfInputNode();

  @override
  O acceptSimpleVisitor<O>(SimpleNodeVisitor<O> visitor) => visitor.visitStartOfInputNode(this);

  @override
  O acceptParametrizedVisitor<O, I>(ParametrizedNodeVisitor<O, I> visitor, I parameters) =>
      visitor.visitStartOfInputNode(this, parameters);
}

class EndOfInputNode implements SpecialSymbolNode {
  const EndOfInputNode();

  @override
  O acceptSimpleVisitor<O>(SimpleNodeVisitor<O> visitor) => visitor.visitEndOfInputNode(this);

  @override
  O acceptParametrizedVisitor<O, I>(ParametrizedNodeVisitor<O, I> visitor, I parameters) =>
      visitor.visitEndOfInputNode(this, parameters);
}

class AnyCharacterNode implements SpecialSymbolNode {
  const AnyCharacterNode();

  @override
  O acceptSimpleVisitor<O>(SimpleNodeVisitor<O> visitor) => visitor.visitAnyCharacterNode(this);

  @override
  O acceptParametrizedVisitor<O, I>(ParametrizedNodeVisitor<O, I> visitor, I parameters) =>
      visitor.visitAnyCharacterNode(this, parameters);
}
