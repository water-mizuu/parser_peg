import "package:parser_peg/src/node.dart";
import "package:parser_peg/src/visitor/node_visitor.dart";

class SimplifyVisitor implements SimplifierNodeVisitor<Node> {
  Node createFragment(Node node) {
    String name = "fragment${fragmentId++}";
    addedFragments[name] = (null, node);

    return FragmentNode(name);
  }

  final Map<String, (String?, Node)> addedFragments = <String, (String?, Node)>{};

  /// A unique identifier for each fragment.
  int fragmentId = 0;

  @override
  Node visitEpsilonNode(EpsilonNode node, int depth) {
    return node;
  }

  @override
  Node visitTriePatternNode(TriePatternNode node, int depth) {
    return node;
  }

  @override
  Node visitStringLiteralNode(StringLiteralNode node, int depth) {
    return node;
  }

  @override
  Node visitRangeNode(RangeNode node, int depth) {
    return node;
  }

  @override
  Node visitRegExpNode(RegExpNode node, int depth) {
    return node;
  }

  @override
  Node visitRegExpEscapeNode(RegExpEscapeNode node, int depth) {
    return node;
  }

  @override
  Node visitSequenceNode(SequenceNode node, int depth) {
    if (depth > 0) {
      return createFragment(
        SequenceNode(
          <Node>[
            for (Node child in node.children) //
              child.acceptSimplifierVisitor(this, 1),
          ],
          choose: node.choose,
        ),
      );
    } else {
      return SequenceNode(
        <Node>[
          for (Node child in node.children) //
            child.acceptSimplifierVisitor(this, depth + 1),
        ],
        choose: node.choose,
      );
    }
  }

  @override
  Node visitChoiceNode(ChoiceNode node, int depth) {
    List<StringLiteralNode> stringNodes = node.children.whereType<StringLiteralNode>().toList();
    if (stringNodes.length < 2) {
      if (depth > 0) {
        return createFragment(
          ChoiceNode(<Node>[for (Node child in node.children) child.acceptSimplifierVisitor(this, 0)]),
        );
      } else {
        return ChoiceNode(
          <Node>[for (Node child in node.children) child.acceptSimplifierVisitor(this, depth)],
        );
      }
    } else {
      List<String> strings = stringNodes //
          .map((StringLiteralNode node) => node.literal)
          .toList();
      List<Node> notStrings = node.children //
          .where((Node node) => node is! StringLiteralNode)
          .toList();

      if (notStrings.isEmpty) {
        return TriePatternNode(strings).acceptSimplifierVisitor(this, depth);
      } else {
        return ChoiceNode(<Node>[...notStrings, TriePatternNode(strings)]).acceptSimplifierVisitor(this, depth);
      }
    }
  }

  @override
  Node visitCountedNode(CountedNode node, int depth) {
    return CountedNode(
      node.min,
      node.max,
      node.child.acceptSimplifierVisitor(this, depth + 1),
    );
  }

  @override
  Node visitPlusSeparatedNode(PlusSeparatedNode node, int depth) {
    return PlusSeparatedNode(
      node.separator.acceptSimplifierVisitor(this, depth + 1),
      node.child.acceptSimplifierVisitor(this, depth + 1),
      isTrailingAllowed: node.isTrailingAllowed,
    );
  }

  @override
  Node visitStarSeparatedNode(StarSeparatedNode node, int depth) {
    return StarSeparatedNode(
      node.separator.acceptSimplifierVisitor(this, depth + 1),
      node.child.acceptSimplifierVisitor(this, depth + 1),
      isTrailingAllowed: node.isTrailingAllowed,
    );
  }

  @override
  Node visitPlusNode(PlusNode node, int depth) {
    return PlusNode(node.child.acceptSimplifierVisitor(this, depth + 1));
  }

  @override
  Node visitStarNode(StarNode node, int depth) {
    return StarNode(node.child.acceptSimplifierVisitor(this, depth + 1));
  }

  @override
  Node visitAndPredicateNode(AndPredicateNode node, int depth) {
    return AndPredicateNode(node.child.acceptSimplifierVisitor(this, depth));
  }

  @override
  Node visitNotPredicateNode(NotPredicateNode node, int depth) {
    return NotPredicateNode(node.child.acceptSimplifierVisitor(this, depth));
  }

  @override
  Node visitOptionalNode(OptionalNode node, int depth) {
    return OptionalNode(node.child.acceptSimplifierVisitor(this, depth));
  }

  @override
  Node visitReferenceNode(ReferenceNode node, int depth) {
    return node;
  }

  @override
  Node visitFragmentNode(FragmentNode node, int depth) {
    return node;
  }

  @override
  Node visitNamedNode(NamedNode node, int depth) {
    return NamedNode(node.name, node.child.acceptSimplifierVisitor(this, depth));
  }

  @override
  Node visitActionNode(ActionNode node, int depth) {
    if (depth > 0) {
      return createFragment(
        ActionNode(
          node.child.acceptSimplifierVisitor(this, 0),
          node.action,
          areIndicesProvided: node.areIndicesProvided,
        ),
      );
    } else {
      return ActionNode(
        node.child.acceptSimplifierVisitor(this, depth),
        node.action,
        areIndicesProvided: node.areIndicesProvided,
      );
    }
  }

  @override
  Node visitInlineActionNode(InlineActionNode node, int depth) {
    if (depth > 0) {
      return createFragment(
        InlineActionNode(
          node.child.acceptSimplifierVisitor(this, 0),
          node.action,
          areIndicesProvided: node.areIndicesProvided,
        ),
      );
    } else {
      return InlineActionNode(
        node.child.acceptSimplifierVisitor(this, depth),
        node.action,
        areIndicesProvided: node.areIndicesProvided,
      );
    }
  }

  @override
  Node visitStartOfInputNode(StartOfInputNode node, int depth) {
    return node;
  }

  @override
  Node visitEndOfInputNode(EndOfInputNode node, int depth) {
    return node;
  }

  @override
  Node visitAnyCharacterNode(AnyCharacterNode node, int depth) {
    return node;
  }
}
