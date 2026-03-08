import "package:parser_peg/src/node.dart";
import "package:parser_peg/src/visitor/node_visitor.dart";

/// This visitor traverses the parse tree and inlines the tags that should be inlined,
///   such as fragment declarations that are used once, or
///   rules that are declared to be inlined.
class IsCutVisitor implements SimpleNodeVisitor<bool> {
  const IsCutVisitor();

  bool inlineReferences(Node root) => root.acceptSimpleVisitor(this);

  @override
  bool visitCutNode(CutNode node) => true;

  @override
  bool visitEpsilonNode(EpsilonNode node) {
    return false;
  }

  @override
  bool visitTriePatternNode(TriePatternNode node) {
    return false;
  }

  @override
  bool visitStringLiteralNode(StringLiteralNode node) {
    return false;
  }

  @override
  bool visitRangeNode(RangeNode node) {
    return false;
  }

  @override
  bool visitRegExpNode(RegExpNode node) {
    return false;
  }

  @override
  bool visitRegExpEscapeNode(RegExpEscapeNode node) {
    return false;
  }

  @override
  bool visitSequenceNode(SequenceNode node) {
    return node.children.any((child) => child.acceptSimpleVisitor(this));
  }

  @override
  bool visitChoiceNode(ChoiceNode node) {
    return node.children.any((child) => child.acceptSimpleVisitor(this));
  }

  @override
  bool visitCountedNode(CountedNode node) {
    return false;
  }

  @override
  bool visitPlusSeparatedNode(PlusSeparatedNode node) {
    return false;
  }

  @override
  bool visitStarSeparatedNode(StarSeparatedNode node) {
    return false;
  }

  @override
  bool visitPlusNode(PlusNode node) {
    return false;
  }

  @override
  bool visitStarNode(StarNode node) {
    return false;
  }

  @override
  bool visitAndPredicateNode(AndPredicateNode node) {
    return false;
  }

  @override
  bool visitNotPredicateNode(NotPredicateNode node) {
    return false;
  }

  @override
  bool visitOptionalNode(OptionalNode node) {
    return false;
  }

  @override
  bool visitExceptNode(ExceptNode node) {
    return false;
  }

  @override
  bool visitReferenceNode(ReferenceNode node) {
    return false;
  }

  @override
  bool visitFragmentNode(FragmentNode node) {
    return false;
  }

  @override
  bool visitNamedNode(NamedNode node) {
    return false;
  }

  @override
  bool visitActionNode(ActionNode node) {
    return node.child.acceptSimpleVisitor(this);
  }

  @override
  bool visitInlineActionNode(InlineActionNode node) {
    return node.child.acceptSimpleVisitor(this);
  }

  @override
  bool visitStartOfInputNode(StartOfInputNode node) {
    return false;
  }

  @override
  bool visitEndOfInputNode(EndOfInputNode node) {
    return false;
  }

  @override
  bool visitAnyCharacterNode(AnyCharacterNode node) {
    return false;
  }
}
