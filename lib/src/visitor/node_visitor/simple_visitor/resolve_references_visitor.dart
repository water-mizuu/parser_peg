import "package:parser_peg/src/generator.dart";
import "package:parser_peg/src/node.dart";
import "package:parser_peg/src/visitor/node_visitor.dart";

/// This visitor traverses the parse tree and resolves all references to rules,
/// fragments, and inline actions. It replaces the nodes which are defaulted to [ReferenceNode]
/// to more appropriate nodes such as [FragmentNode].
class ResolveReferencesVisitor implements SimpleNodeVisitor<Node> {
  const ResolveReferencesVisitor(
    this.declarationName,
    this.prefixes,
    this.rules,
    this.fragments,
    this.inline,
  );

  final String declarationName;
  final List<String> prefixes;
  final Map<String, (String?, Node)> rules;
  final Map<String, (String?, Node)> fragments;
  final Map<String, (String?, Node)> inline;

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
    return SequenceNode([
      for (var sub in node.children) sub.acceptSimpleVisitor(this),
    ], chosenIndex: node.chosenIndex);
  }

  @override
  Node visitChoiceNode(ChoiceNode node) {
    return ChoiceNode([for (var sub in node.children) sub.acceptSimpleVisitor(this)]);
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

  Node resolveReference(String name) {
    for (int i = prefixes.length; i >= 0; --i) {
      var potentialName = [...prefixes.sublist(0, i), name].join(ParserGenerator.separator);
      switch (potentialName) {
        case String name when rules.containsKey(name):
          return ReferenceNode(name);
        case String name when inline.containsKey(name):
        case String name when fragments.containsKey(name):
          return FragmentNode(name);
      }
    }

    throw Exception("Unknown reference from $declarationName: $name");
  }

  @override
  Node visitReferenceNode(ReferenceNode node) {
    return resolveReference(node.ruleName);
  }

  @override
  Node visitFragmentNode(FragmentNode node) {
    throw UnsupportedError("At this stage of compilation, only reference nodes should exist.");
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
