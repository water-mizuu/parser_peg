import "dart:convert";

import "package:parser_peg/src/generator.dart";
import "package:parser_peg/src/node.dart";
import "package:parser_peg/src/visitor/node_visitor.dart";

class SExpressionVisitor implements SimpleNodeVisitor<String> {
  @override
  String visitEpsilonNode(EpsilonNode node) => "(epsilon)";

  @override
  String visitTriePatternNode(TriePatternNode node) => "(trie ${node.options.join(" ")})";

  @override
  String visitStringLiteralNode(StringLiteralNode node) => "(string ${jsonEncode(node.literal)})";

  @override
  String visitRangeNode(RangeNode node) => "(range ${node.ranges.join(" ")}})";

  @override
  String visitRegExpNode(RegExpNode node) => "(regexp ${node.value})";

  @override
  String visitRegExpEscapeNode(RegExpEscapeNode node) => "(escape ${node.pattern})";

  @override
  String visitSequenceNode(SequenceNode node) => node.children //
      .map((Node child) => child.acceptSimpleVisitor(this))
      .join(" ")
      .apply((v) => "(sequence $v)");

  @override
  String visitChoiceNode(ChoiceNode node) => node.children //
      .map((Node child) => child.acceptSimpleVisitor(this))
      .join(" ")
      .apply((v) => "(choice $v)");

  @override
  String visitCountedNode(CountedNode node) => (
        node.min,
        node.max,
        node.child.acceptSimpleVisitor(this),
      ).apply((v) => "(counted ${v.$1} ${v.$2} ${v.$3})");

  @override
  String visitPlusSeparatedNode(PlusSeparatedNode node) => (
        node.separator.acceptSimpleVisitor(this),
        node.child.acceptSimpleVisitor(this),
        node.isTrailingAllowed
      ).apply((v) => "(plus-separated ${v.$1} ${v.$2} (:trailing ${v.$3}))");

  @override
  String visitStarSeparatedNode(StarSeparatedNode node) => (
        node.separator.acceptSimpleVisitor(this),
        node.child.acceptSimpleVisitor(this),
        node.isTrailingAllowed
      ).apply((v) => "(star-separated ${v.$1} (${v.$2}) (:trailing ${v.$3}))");

  @override
  String visitPlusNode(PlusNode node) =>
      node.child.acceptSimpleVisitor(this).apply((v) => "(plus $v)");

  @override
  String visitStarNode(StarNode node) =>
      node.child.acceptSimpleVisitor(this).apply((v) => "(star $v)");

  @override
  String visitAndPredicateNode(AndPredicateNode node) =>
      node.child.acceptSimpleVisitor(this).apply((v) => "(and-predicate $v)");

  @override
  String visitNotPredicateNode(NotPredicateNode node) =>
      node.child.acceptSimpleVisitor(this).apply((v) => "(not-predicate $v)");

  @override
  String visitOptionalNode(OptionalNode node) =>
      node.child.acceptSimpleVisitor(this).apply((v) => "(optional $v)");

  @override
  String visitReferenceNode(ReferenceNode node) => node.ruleName;

  @override
  String visitFragmentNode(FragmentNode node) => node.fragmentName;

  @override
  String visitNamedNode(NamedNode node) =>
      "(named ${jsonEncode(node.name)} ${node.child.acceptSimpleVisitor(this)})";

  @override
  String visitActionNode(ActionNode node) =>
      "(action ${node.child.acceptSimpleVisitor(this)} (){ ... })";

  @override
  String visitInlineActionNode(InlineActionNode node) =>
      "(action ${node.child.acceptSimpleVisitor(this)} { ... })";

  @override
  String visitStartOfInputNode(StartOfInputNode node) => "^";

  @override
  String visitEndOfInputNode(EndOfInputNode node) => r"$";

  @override
  String visitAnyCharacterNode(AnyCharacterNode node) => ".";
}
