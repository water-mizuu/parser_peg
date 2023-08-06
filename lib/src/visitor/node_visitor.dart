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
  O visitReferenceNode(ReferenceNode node);
  O visitFragmentNode(FragmentNode node);
  O visitNamedNode(NamedNode node);
  O visitActionNode(ActionNode node);
  O visitInlineActionNode(InlineActionNode node);
  O visitStartOfInputNode(StartOfInputNode node);
  O visitEndOfInputNode(EndOfInputNode node);
  O visitAnyCharacterNode(AnyCharacterNode node);
}

abstract class SimplifierNodeVisitor<O> {
  O visitEpsilonNode(EpsilonNode node, int depth);
  O visitTriePatternNode(TriePatternNode node, int depth);
  O visitStringLiteralNode(StringLiteralNode node, int depth);
  O visitRangeNode(RangeNode node, int depth);
  O visitRegExpNode(RegExpNode node, int depth);
  O visitRegExpEscapeNode(RegExpEscapeNode node, int depth);
  O visitSequenceNode(SequenceNode node, int depth);
  O visitChoiceNode(ChoiceNode node, int depth);
  O visitCountedNode(CountedNode node, int depth);
  O visitPlusSeparatedNode(PlusSeparatedNode node, int depth);
  O visitStarSeparatedNode(StarSeparatedNode node, int depth);
  O visitPlusNode(PlusNode node, int depth);
  O visitStarNode(StarNode node, int depth);
  O visitAndPredicateNode(AndPredicateNode node, int depth);
  O visitNotPredicateNode(NotPredicateNode node, int depth);
  O visitOptionalNode(OptionalNode node, int depth);
  O visitReferenceNode(ReferenceNode node, int depth);
  O visitFragmentNode(FragmentNode node, int depth);
  O visitNamedNode(NamedNode node, int depth);
  O visitActionNode(ActionNode node, int depth);
  O visitInlineActionNode(InlineActionNode node, int depth);
  O visitStartOfInputNode(StartOfInputNode node, int depth);
  O visitEndOfInputNode(EndOfInputNode node, int depth);
  O visitAnyCharacterNode(AnyCharacterNode node, int depth);
}

abstract class CodeGeneratorNodeVisitor<O, I> {
  O visitEpsilonNode(
    EpsilonNode node, {
    required bool isNullAllowed,
    required Set<String>? withNames,
    required I? inner,
    required bool reported,
    required String declarationName,
  });
  O visitTriePatternNode(
    TriePatternNode node, {
    required bool isNullAllowed,
    required Set<String>? withNames,
    required I? inner,
    required bool reported,
    required String declarationName,
  });
  O visitStringLiteralNode(
    StringLiteralNode node, {
    required bool isNullAllowed,
    required Set<String>? withNames,
    required I? inner,
    required bool reported,
    required String declarationName,
  });
  O visitRangeNode(
    RangeNode node, {
    required bool isNullAllowed,
    required Set<String>? withNames,
    required I? inner,
    required bool reported,
    required String declarationName,
  });
  O visitRegExpNode(
    RegExpNode node, {
    required bool isNullAllowed,
    required Set<String>? withNames,
    required I? inner,
    required bool reported,
    required String declarationName,
  });
  O visitRegExpEscapeNode(
    RegExpEscapeNode node, {
    required bool isNullAllowed,
    required Set<String>? withNames,
    required I? inner,
    required bool reported,
    required String declarationName,
  });
  O visitSequenceNode(
    SequenceNode node, {
    required bool isNullAllowed,
    required Set<String>? withNames,
    required I? inner,
    required bool reported,
    required String declarationName,
  });
  O visitChoiceNode(
    ChoiceNode node, {
    required bool isNullAllowed,
    required Set<String>? withNames,
    required I? inner,
    required bool reported,
    required String declarationName,
  });
  O visitCountedNode(
    CountedNode node, {
    required bool isNullAllowed,
    required Set<String>? withNames,
    required I? inner,
    required bool reported,
    required String declarationName,
  });
  O visitPlusSeparatedNode(
    PlusSeparatedNode node, {
    required bool isNullAllowed,
    required Set<String>? withNames,
    required I? inner,
    required bool reported,
    required String declarationName,
  });
  O visitStarSeparatedNode(
    StarSeparatedNode node, {
    required bool isNullAllowed,
    required Set<String>? withNames,
    required I? inner,
    required bool reported,
    required String declarationName,
  });
  O visitPlusNode(
    PlusNode node, {
    required bool isNullAllowed,
    required Set<String>? withNames,
    required I? inner,
    required bool reported,
    required String declarationName,
  });
  O visitStarNode(
    StarNode node, {
    required bool isNullAllowed,
    required Set<String>? withNames,
    required I? inner,
    required bool reported,
    required String declarationName,
  });
  O visitAndPredicateNode(
    AndPredicateNode node, {
    required bool isNullAllowed,
    required Set<String>? withNames,
    required I? inner,
    required bool reported,
    required String declarationName,
  });
  O visitNotPredicateNode(
    NotPredicateNode node, {
    required bool isNullAllowed,
    required Set<String>? withNames,
    required I? inner,
    required bool reported,
    required String declarationName,
  });
  O visitOptionalNode(
    OptionalNode node, {
    required bool isNullAllowed,
    required Set<String>? withNames,
    required I? inner,
    required bool reported,
    required String declarationName,
  });
  O visitReferenceNode(
    ReferenceNode node, {
    required bool isNullAllowed,
    required Set<String>? withNames,
    required I? inner,
    required bool reported,
    required String declarationName,
  });
  O visitFragmentNode(
    FragmentNode node, {
    required bool isNullAllowed,
    required Set<String>? withNames,
    required I? inner,
    required bool reported,
    required String declarationName,
  });
  O visitNamedNode(
    NamedNode node, {
    required bool isNullAllowed,
    required Set<String>? withNames,
    required I? inner,
    required bool reported,
    required String declarationName,
  });
  O visitActionNode(
    ActionNode node, {
    required bool isNullAllowed,
    required Set<String>? withNames,
    required I? inner,
    required bool reported,
    required String declarationName,
  });
  O visitInlineActionNode(
    InlineActionNode node, {
    required bool isNullAllowed,
    required Set<String>? withNames,
    required I? inner,
    required bool reported,
    required String declarationName,
  });
  O visitStartOfInputNode(
    StartOfInputNode node, {
    required bool isNullAllowed,
    required Set<String>? withNames,
    required I? inner,
    required bool reported,
    required String declarationName,
  });
  O visitEndOfInputNode(
    EndOfInputNode node, {
    required bool isNullAllowed,
    required Set<String>? withNames,
    required I? inner,
    required bool reported,
    required String declarationName,
  });
  O visitAnyCharacterNode(
    AnyCharacterNode node, {
    required bool isNullAllowed,
    required Set<String>? withNames,
    required I? inner,
    required bool reported,
    required String declarationName,
  });
}
