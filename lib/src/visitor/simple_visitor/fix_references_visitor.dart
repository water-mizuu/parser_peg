import "package:parser_peg/src/node.dart";
import "package:parser_peg/src/visitor/node_visitor.dart";

class FixReferencesVisitor implements SimpleNodeVisitor<Node> {
  const FixReferencesVisitor({
    required this.prefixes,
    required this.rules,
    required this.fragments,
  });

  final List<String> prefixes;
  final Map<String, (String?, Node)> rules;
  final Map<String, (String?, Node)> fragments;

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
    return SequenceNode(
      <Node>[for (Node child in node.children) child.acceptSimpleVisitor(this)],
      choose: node.choose,
    );
  }

  @override
  Node visitChoiceNode(ChoiceNode node) {
    return ChoiceNode(<Node>[for (Node child in node.children) child.acceptSimpleVisitor(this)]);
  }

  @override
  Node visitCountedNode(CountedNode node) {
    return CountedNode(
      node.min,
      node.max,
      node.child.acceptSimpleVisitor(this),
    );
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
  Node visitReferenceNode(ReferenceNode node) {
    /// We check if the reference exists.

    switch (node.ruleName.replaceAll("::", "__")) {
      case String safe when rules.containsKey(safe):
        return ReferenceNode(safe);
      case String safe when fragments.containsKey(safe):
        return FragmentNode(safe);
    }

    for (int i = prefixes.length; i >= 0; --i) {
      switch (<String>[
        ...prefixes.sublist(0, i),
        node.ruleName.replaceAll("::", "__"),
      ].join("__")) {
        case String name when rules.containsKey(name):
          return ReferenceNode(name);
        case String name when fragments.containsKey(name):
          return FragmentNode(name);
      }
    }

    return throw Exception("Unknown reference: ${node.ruleName}");
  }

  @override
  Node visitFragmentNode(FragmentNode node) {
    switch (node.fragmentName.replaceAll("::", "__")) {
      case String safe when rules.containsKey(safe):
        return ReferenceNode(safe);
      case String safe when fragments.containsKey(safe):
        return FragmentNode(safe);
    }

    for (int i = prefixes.length; i >= 0; --i) {
      switch (<String>[
        ...prefixes.sublist(0, i),
        node.fragmentName.replaceAll("::", "__"),
      ].join("__")) {
        case String name when rules.containsKey(name):
          return ReferenceNode(name);
        case String name when fragments.containsKey(name):
          return FragmentNode(name);
      }
    }

    return throw Exception("Unknown reference: ${node.fragmentName}");
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
    );
  }

  @override
  Node visitInlineActionNode(InlineActionNode node) {
    return InlineActionNode(
      node.child.acceptSimpleVisitor(this),
      node.action,
      areIndicesProvided: node.areIndicesProvided,
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
