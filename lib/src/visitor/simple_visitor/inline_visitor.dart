import "package:parser_peg/src/node.dart";
import "package:parser_peg/src/visitor/node_visitor.dart";

/// This visitor traverses the parse tree and inlines the tags that should be inlined,
///   such as fragment declarations that are used once, or
///   rules that are declared to be inlined.
class InlineVisitor implements SimpleNodeVisitor<(bool, Node)> {
  const InlineVisitor(this.inline);

  final Map<String, (String?, Node)> inline;

  (bool, Node) inlineReferences(Node root) => root.acceptSimpleVisitor(this);

  @override
  (bool, Node) visitEpsilonNode(EpsilonNode node) {
    return (false, node);
  }

  @override
  (bool, Node) visitTriePatternNode(TriePatternNode node) {
    return (false, node);
  }

  @override
  (bool, Node) visitStringLiteralNode(StringLiteralNode node) {
    return (false, node);
  }

  @override
  (bool, Node) visitRangeNode(RangeNode node) {
    return (false, node);
  }

  @override
  (bool, Node) visitRegExpNode(RegExpNode node) {
    return (false, node);
  }

  @override
  (bool, Node) visitRegExpEscapeNode(RegExpEscapeNode node) {
    return (false, node);
  }

  @override
  (bool, Node) visitSequenceNode(SequenceNode node) {
    var hasChanged = false;
    var children = <Node>[];
    for (var sub in node.children) {
      var (changed, node) = sub.acceptSimpleVisitor(this);
      hasChanged |= changed;

      children.add(node);
    }

    return (hasChanged, SequenceNode(children, chosenIndex: node.chosenIndex));
  }

  @override
  (bool, Node) visitChoiceNode(ChoiceNode node) {
    var hasChanged = false;
    var children = <Node>[];
    for (var sub in node.children) {
      var (changed, node) = sub.acceptSimpleVisitor(this);
      hasChanged |= changed;

      children.add(node);
    }

    return (hasChanged, ChoiceNode(children));
  }

  @override
  (bool, Node) visitCountedNode(CountedNode node) {
    var (changed, child) = node.child.acceptSimpleVisitor(this);

    return (changed, CountedNode(node.min, node.max, child));
  }

  @override
  (bool, Node) visitPlusSeparatedNode(PlusSeparatedNode node) {
    var (changed0, separator) = node.separator.acceptSimpleVisitor(this);
    var (changed1, child) = node.child.acceptSimpleVisitor(this);

    return (
      changed0 || changed1,
      PlusSeparatedNode(separator, child, isTrailingAllowed: node.isTrailingAllowed),
    );
  }

  @override
  (bool, Node) visitStarSeparatedNode(StarSeparatedNode node) {
    var (changed0, separator) = node.separator.acceptSimpleVisitor(this);
    var (changed1, child) = node.child.acceptSimpleVisitor(this);

    return (
      changed0 || changed1,
      StarSeparatedNode(separator, child, isTrailingAllowed: node.isTrailingAllowed),
    );
  }

  @override
  (bool, Node) visitPlusNode(PlusNode node) {
    var (changed, child) = node.child.acceptSimpleVisitor(this);

    return (changed, PlusNode(child));
  }

  @override
  (bool, Node) visitStarNode(StarNode node) {
    var (bool changed, Node child) = node.child.acceptSimpleVisitor(this);

    return (changed, StarNode(child));
  }

  @override
  (bool, Node) visitAndPredicateNode(AndPredicateNode node) {
    var (changed, child) = node.child.acceptSimpleVisitor(this);

    return (changed, AndPredicateNode(child));
  }

  @override
  (bool, Node) visitNotPredicateNode(NotPredicateNode node) {
    var (changed, child) = node.child.acceptSimpleVisitor(this);

    return (changed, NotPredicateNode(child));
  }

  @override
  (bool, Node) visitOptionalNode(OptionalNode node) {
    var (changed, child) = node.child.acceptSimpleVisitor(this);

    return (changed, OptionalNode(child));
  }

  @override
  (bool, Node) visitExceptNode(ExceptNode node) {
    var (changed, child) = node.child.acceptSimpleVisitor(this);

    return (changed, ExceptNode(child));
  }

  (bool, Node)? resolveReference(String name) {
    if (inline.containsKey(name)) {
      return (true, inline[name]!.$2);
    }
    return null;
  }

  @override
  (bool, Node) visitReferenceNode(ReferenceNode node) {
    return resolveReference(node.ruleName) ?? (false, node);
  }

  @override
  (bool, Node) visitFragmentNode(FragmentNode node) {
    return resolveReference(node.fragmentName) ?? (false, node);
  }

  @override
  (bool, Node) visitNamedNode(NamedNode node) {
    var (changed, child) = node.child.acceptSimpleVisitor(this);

    return (changed, NamedNode(node.name, child));
  }

  @override
  (bool, Node) visitActionNode(ActionNode node) {
    var (changed, child) = node.child.acceptSimpleVisitor(this);
    return (changed, ActionNode(child, node.action, areIndicesProvided: node.areIndicesProvided));
  }

  @override
  (bool, Node) visitInlineActionNode(InlineActionNode node) {
    var (changed, child) = node.child.acceptSimpleVisitor(this);
    return (
      changed,
      InlineActionNode(child, node.action, areIndicesProvided: node.areIndicesProvided),
    );
  }

  @override
  (bool, Node) visitStartOfInputNode(StartOfInputNode node) {
    return (false, node);
  }

  @override
  (bool, Node) visitEndOfInputNode(EndOfInputNode node) {
    return (false, node);
  }

  @override
  (bool, Node) visitAnyCharacterNode(AnyCharacterNode node) {
    return (false, node);
  }
}
