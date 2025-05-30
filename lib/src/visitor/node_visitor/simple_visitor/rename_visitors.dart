import "package:parser_peg/src/node.dart";
import "package:parser_peg/src/visitor/node_visitor.dart";

/// This visitor traverses the parse tree and renames all rule and fragment
/// declarations according to the provided [redirects] map. It replaces the
/// names of the rules and fragments in the parse tree with their new names.
///
/// The [redirects] map should contain the original names as keys and the
/// new names as values. For example, if you want to rename a rule from
/// "oldName" to "newName", you would add an entry to the map like this:
/// ```dart
///   redirects["oldName"] = "newName";
/// ```
class RenameDeclarationVisitor implements SimpleNodeVisitor<Node> {
  const RenameDeclarationVisitor(this.redirects);

  final Map<String, String> redirects;

  Node renameDeclarations(Node node) => node.acceptSimpleVisitor(this);

  @override
  Node visitEpsilonNode(EpsilonNode node) {
    return node;
  }

  @override
  Node visitTriePatternNode(TriePatternNode node) {
    return node;
  }

  @override
  Node visitStringLiteralNode(StringLiteralNode node) {
    return node;
  }

  @override
  Node visitRangeNode(RangeNode node) {
    return node;
  }

  @override
  Node visitRegExpNode(RegExpNode node) {
    return node;
  }

  @override
  Node visitRegExpEscapeNode(RegExpEscapeNode node) {
    return node;
  }

  @override
  Node visitSequenceNode(SequenceNode node) {
    return SequenceNode(<Node>[
      for (Node child in node.children) child.acceptSimpleVisitor(this),
    ], chosenIndex: node.chosenIndex);
  }

  @override
  Node visitChoiceNode(ChoiceNode node) {
    return ChoiceNode(<Node>[for (Node child in node.children) child.acceptSimpleVisitor(this)]);
  }

  @override
  Node visitCountedNode(CountedNode node) {
    return CountedNode(node.min, node.max, node.child.acceptSimpleVisitor(this));
  }

  @override
  Node visitPlusSeparatedNode(PlusSeparatedNode node) {
    return PlusSeparatedNode(
      node.separator.acceptSimpleVisitor(this),
      node.child.acceptSimpleVisitor(this),
      isTrailingAllowed: node.isTrailingAllowed,
    );
  }

  @override
  Node visitStarSeparatedNode(StarSeparatedNode node) {
    return StarSeparatedNode(
      node.separator.acceptSimpleVisitor(this),
      node.child.acceptSimpleVisitor(this),
      isTrailingAllowed: node.isTrailingAllowed,
    );
  }

  @override
  Node visitPlusNode(PlusNode node) {
    return PlusNode(node.child.acceptSimpleVisitor(this));
  }

  @override
  Node visitStarNode(StarNode node) {
    return StarNode(node.child.acceptSimpleVisitor(this));
  }

  @override
  Node visitAndPredicateNode(AndPredicateNode node) {
    return AndPredicateNode(node.child.acceptSimpleVisitor(this));
  }

  @override
  Node visitNotPredicateNode(NotPredicateNode node) {
    return NotPredicateNode(node.child.acceptSimpleVisitor(this));
  }

  @override
  Node visitOptionalNode(OptionalNode node) {
    return OptionalNode(node.child.acceptSimpleVisitor(this));
  }

  @override
  Node visitExceptNode(ExceptNode node) {
    return ExceptNode(node.child.acceptSimpleVisitor(this));
  }

  @override
  Node visitReferenceNode(ReferenceNode node) {
    return ReferenceNode(redirects[node.ruleName] ?? node.ruleName);
  }

  @override
  Node visitFragmentNode(FragmentNode node) {
    return FragmentNode(redirects[node.fragmentName] ?? node.fragmentName);
  }

  @override
  Node visitNamedNode(NamedNode node) {
    return NamedNode(node.name, node.child.acceptSimpleVisitor(this));
  }

  @override
  Node visitActionNode(ActionNode node) {
    return ActionNode(
      node.child.acceptSimpleVisitor(this),
      node.action,
      areIndicesProvided: node.areIndicesProvided,
      isSpanUsed: node.isSpanUsed,
    );
  }

  @override
  Node visitInlineActionNode(InlineActionNode node) {
    return InlineActionNode(
      node.child.acceptSimpleVisitor(this),
      node.action,
      areIndicesProvided: node.areIndicesProvided,
      isSpanUsed: node.isSpanUsed,
    );
  }

  @override
  Node visitStartOfInputNode(StartOfInputNode node) {
    return node;
  }

  @override
  Node visitEndOfInputNode(EndOfInputNode node) {
    return node;
  }

  @override
  Node visitAnyCharacterNode(AnyCharacterNode node) {
    return node;
  }
}
