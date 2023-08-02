import "package:parser_peg/src/node.dart";
import "package:parser_peg/src/visitor/node_visitor.dart";

class CanInlineVisitor implements SimpleNodeVisitor<bool> {
  const CanInlineVisitor();

  @override
  bool visitEpsilonNode(EpsilonNode node) {
    return true;
  }

  @override
  bool visitTriePatternNode(TriePatternNode node) {
    return true;
  }

  @override
  bool visitStringLiteralNode(StringLiteralNode node) {
    return true;
  }

  @override
  bool visitRangeNode(RangeNode node) {
    return true;
  }

  @override
  bool visitRegExpNode(RegExpNode node) {
    return true;
  }

  @override
  bool visitRegExpEscapeNode(RegExpEscapeNode node) {
    return true;
  }

  @override
  bool visitSequenceNode(SequenceNode node) {
    return node.children.every((Node child) => child.acceptSimpleVisitor(this));
  }

  @override
  bool visitChoiceNode(ChoiceNode node) {
    return node.children.every((Node child) => child.acceptSimpleVisitor(this));
  }

  @override
  bool visitCountedNode(CountedNode node) {
    return node.child.acceptSimpleVisitor(this);
  }

  @override
  bool visitPlusSeparatedNode(PlusSeparatedNode node) {
    return node.child.acceptSimpleVisitor(this);
  }

  @override
  bool visitStarSeparatedNode(StarSeparatedNode node) {
    return node.child.acceptSimpleVisitor(this);
  }

  @override
  bool visitPlusNode(PlusNode node) {
    return node.child.acceptSimpleVisitor(this);
  }

  @override
  bool visitStarNode(StarNode node) {
    return node.child.acceptSimpleVisitor(this);
  }

  @override
  bool visitAndPredicateNode(AndPredicateNode node) {
    return node.child.acceptSimpleVisitor(this);
  }

  @override
  bool visitNotPredicateNode(NotPredicateNode node) {
    return node.child.acceptSimpleVisitor(this);
  }

  @override
  bool visitOptionalNode(OptionalNode node) {
    return node.child.acceptSimpleVisitor(this);
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
    return node.child.acceptSimpleVisitor(this);
  }

  @override
  bool visitActionNode(ActionNode node) {
    return true;
  }

  @override
  bool visitInlineActionNode(InlineActionNode node) {
    return true;
  }

  @override
  bool visitStartOfInputNode(StartOfInputNode node) {
    return true;
  }

  @override
  bool visitEndOfInputNode(EndOfInputNode node) {
    return true;
  }

  @override
  bool visitAnyCharacterNode(AnyCharacterNode node) {
    return true;
  }
}

extension CanInlineExtension on Node {
  bool get canBeInlined => acceptSimpleVisitor(const CanInlineVisitor());
}
