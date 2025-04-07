import "package:parser_peg/src/node.dart";
import "package:parser_peg/src/statement.dart";
import "package:parser_peg/src/visitor/node_visitor.dart";

/// This visitor traverses the parse tree and collects all the referenced
/// declarations (rules and fragments) in the grammar. It is used to
/// determine the dependencies between rules and fragments, which is
/// important for generating the final grammar.
class ReferencedVisitor implements SimpleNodeVisitor<Iterable<(Tag, String)>> {
  const ReferencedVisitor();

  Iterable<(Tag, String)> referencedDeclarations(Node root) => root.acceptSimpleVisitor(this);

  @override
  Iterable<(Tag, String)> visitEpsilonNode(EpsilonNode node) sync* {}

  @override
  Iterable<(Tag, String)> visitTriePatternNode(TriePatternNode node) sync* {}

  @override
  Iterable<(Tag, String)> visitStringLiteralNode(StringLiteralNode node) sync* {}

  @override
  Iterable<(Tag, String)> visitRangeNode(RangeNode node) sync* {}

  @override
  Iterable<(Tag, String)> visitRegExpNode(RegExpNode node) sync* {}

  @override
  Iterable<(Tag, String)> visitRegExpEscapeNode(RegExpEscapeNode node) sync* {}

  @override
  Iterable<(Tag, String)> visitSequenceNode(SequenceNode node) sync* {
    for (Node sub in node.children) {
      yield* sub.acceptSimpleVisitor(this);
    }
  }

  @override
  Iterable<(Tag, String)> visitChoiceNode(ChoiceNode node) sync* {
    for (Node sub in node.children) {
      yield* sub.acceptSimpleVisitor(this);
    }
  }

  @override
  Iterable<(Tag, String)> visitCountedNode(CountedNode node) sync* {
    yield* node.child.acceptSimpleVisitor(this);
  }

  @override
  Iterable<(Tag, String)> visitPlusSeparatedNode(PlusSeparatedNode node) sync* {
    yield* node.separator.acceptSimpleVisitor(this);
    yield* node.child.acceptSimpleVisitor(this);
  }

  @override
  Iterable<(Tag, String)> visitStarSeparatedNode(StarSeparatedNode node) sync* {
    yield* node.separator.acceptSimpleVisitor(this);
    yield* node.child.acceptSimpleVisitor(this);
  }

  @override
  Iterable<(Tag, String)> visitPlusNode(PlusNode node) sync* {
    yield* node.child.acceptSimpleVisitor(this);
  }

  @override
  Iterable<(Tag, String)> visitStarNode(StarNode node) sync* {
    yield* node.child.acceptSimpleVisitor(this);
  }

  @override
  Iterable<(Tag, String)> visitAndPredicateNode(AndPredicateNode node) sync* {
    yield* node.child.acceptSimpleVisitor(this);
  }

  @override
  Iterable<(Tag, String)> visitNotPredicateNode(NotPredicateNode node) sync* {
    yield* node.child.acceptSimpleVisitor(this);
  }

  @override
  Iterable<(Tag, String)> visitOptionalNode(OptionalNode node) sync* {
    yield* node.child.acceptSimpleVisitor(this);
  }

  @override
  Iterable<(Tag, String)> visitReferenceNode(ReferenceNode node) sync* {
    yield (Tag.rule, node.ruleName);
  }

  @override
  Iterable<(Tag, String)> visitFragmentNode(FragmentNode node) sync* {
    yield (Tag.fragment, node.fragmentName);
  }

  @override
  Iterable<(Tag, String)> visitNamedNode(NamedNode node) sync* {
    yield* node.child.acceptSimpleVisitor(this);
  }

  @override
  Iterable<(Tag, String)> visitActionNode(ActionNode node) sync* {
    yield* node.child.acceptSimpleVisitor(this);
  }

  @override
  Iterable<(Tag, String)> visitInlineActionNode(InlineActionNode node) sync* {
    yield* node.child.acceptSimpleVisitor(this);
  }

  @override
  Iterable<(Tag, String)> visitStartOfInputNode(StartOfInputNode node) sync* {}

  @override
  Iterable<(Tag, String)> visitEndOfInputNode(EndOfInputNode node) sync* {}

  @override
  Iterable<(Tag, String)> visitAnyCharacterNode(AnyCharacterNode node) sync* {}
}
