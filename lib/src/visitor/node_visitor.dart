import "package:parser_peg/src/node.dart";

abstract class SimpleNodeVisitor<O> {
  O visitEpsilonNode(EpsilonNode node);
  O visitTriePatternNode(TriePatternNode node);
  O visitStringLiteralNode(StringLiteralNode node);
  O visitRangeNode(RangeNode node);
  O visitRegExpNode(RegExpNode node);
  O visitRegExpEscapeNode(RegExpEscapeNode node);
  O visitSequenceNode(SequenceNode node);
  O visitChoiceNode(ChoiceNode node);
  O visitCountedNode(CountedNode node);
  O visitPlusSeparatedNode(PlusSeparatedNode node);
  O visitStarSeparatedNode(StarSeparatedNode node);
  O visitPlusNode(PlusNode node);
  O visitStarNode(StarNode node);
  O visitAndPredicateNode(AndPredicateNode node);
  O visitNotPredicateNode(NotPredicateNode node);
  O visitOptionalNode(OptionalNode node);
  O visitExceptNode(ExceptNode node);
  O visitReferenceNode(ReferenceNode node);
  O visitFragmentNode(FragmentNode node);
  O visitNamedNode(NamedNode node);
  O visitActionNode(ActionNode node);
  O visitInlineActionNode(InlineActionNode node);
  O visitStartOfInputNode(StartOfInputNode node);
  O visitEndOfInputNode(EndOfInputNode node);
  O visitAnyCharacterNode(AnyCharacterNode node);
}

abstract class ParametrizedNodeVisitor<O, I> {
  O visitEpsilonNode(EpsilonNode node, I parameters);
  O visitTriePatternNode(TriePatternNode node, I parameters);
  O visitStringLiteralNode(StringLiteralNode node, I parameters);
  O visitRangeNode(RangeNode node, I parameters);
  O visitRegExpNode(RegExpNode node, I parameters);
  O visitRegExpEscapeNode(RegExpEscapeNode node, I parameters);
  O visitSequenceNode(SequenceNode node, I parameters);
  O visitChoiceNode(ChoiceNode node, I parameters);
  O visitCountedNode(CountedNode node, I parameters);
  O visitPlusSeparatedNode(PlusSeparatedNode node, I parameters);
  O visitStarSeparatedNode(StarSeparatedNode node, I parameters);
  O visitPlusNode(PlusNode node, I parameters);
  O visitStarNode(StarNode node, I parameters);
  O visitAndPredicateNode(AndPredicateNode node, I parameters);
  O visitNotPredicateNode(NotPredicateNode node, I parameters);
  O visitOptionalNode(OptionalNode node, I parameters);
  O visitExceptNode(ExceptNode node, I parameters);
  O visitReferenceNode(ReferenceNode node, I parameters);
  O visitFragmentNode(FragmentNode node, I parameters);
  O visitNamedNode(NamedNode node, I parameters);
  O visitActionNode(ActionNode node, I parameters);
  O visitInlineActionNode(InlineActionNode node, I parameters);
  O visitStartOfInputNode(StartOfInputNode node, I parameters);
  O visitEndOfInputNode(EndOfInputNode node, I parameters);
  O visitAnyCharacterNode(AnyCharacterNode node, I parameters);
}
