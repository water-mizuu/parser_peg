// ignore_for_file: always_put_control_body_on_new_line

import "package:parser_peg/src/node.dart";
import "package:parser_peg/src/visitor/node_visitor.dart";

class CanInlineVisitor implements SimpleNodeVisitor<bool> {
  CanInlineVisitor(this.rules, this.fragments, this.inline);

  bool canBeInlined(Node node) => node.acceptSimpleVisitor<bool>(this);

  final Expando<bool> _cache = Expando<bool>();
  final Map<String, (String?, Node)> rules;
  final Map<String, (String?, Node)> fragments;
  final Map<String, (String?, Node)> inline;

  @override
  bool visitIndentNode(IndentNode node) {
    if (_cache[node] case bool b) return b;

    return _cache[node] = true;
  }

  @override
  bool visitDedentNode(DedentNode node) {
    if (_cache[node] case bool b) return b;

    return _cache[node] = true;
  }

  @override
  bool visitSamedentNode(SamedentNode node) {
    if (_cache[node] case bool b) return b;

    return _cache[node] = true;
  }

  @override
  bool visitEpsilonNode(EpsilonNode node) {
    if (_cache[node] case bool b) return b;

    return _cache[node] = true;
  }

  @override
  bool visitTriePatternNode(TriePatternNode node) {
    if (_cache[node] case bool b) return b;

    return _cache[node] = true;
  }

  @override
  bool visitStringLiteralNode(StringLiteralNode node) {
    if (_cache[node] case bool b) return b;

    return _cache[node] = true;
  }

  @override
  bool visitRangeNode(RangeNode node) {
    if (_cache[node] case bool b) return b;

    return _cache[node] = true;
  }

  @override
  bool visitRegExpNode(RegExpNode node) {
    if (_cache[node] case bool b) return b;

    return _cache[node] = true;
  }

  @override
  bool visitRegExpEscapeNode(RegExpEscapeNode node) {
    if (_cache[node] case bool b) return b;

    return _cache[node] = true;
  }

  @override
  bool visitSequenceNode(SequenceNode node) {
    if (_cache[node] case bool b) return b;

    return _cache[node] = node.children.every((child) => child.acceptSimpleVisitor<bool>(this));
  }

  @override
  bool visitChoiceNode(ChoiceNode node) {
    if (_cache[node] case bool b) return b;

    return _cache[node] = node.children.every((child) => child.acceptSimpleVisitor<bool>(this));
  }

  @override
  bool visitCountedNode(CountedNode node) {
    if (_cache[node] case bool b) return b;

    return _cache[node] = node.child.acceptSimpleVisitor<bool>(this);
  }

  @override
  bool visitPlusSeparatedNode(PlusSeparatedNode node) {
    if (_cache[node] case bool b) return b;

    return _cache[node] = node.child.acceptSimpleVisitor<bool>(this);
  }

  @override
  bool visitStarSeparatedNode(StarSeparatedNode node) {
    if (_cache[node] case bool b) return b;

    return _cache[node] = node.child.acceptSimpleVisitor<bool>(this);
  }

  @override
  bool visitPlusNode(PlusNode node) {
    if (_cache[node] case bool b) return b;

    return _cache[node] = node.child.acceptSimpleVisitor<bool>(this);
  }

  @override
  bool visitStarNode(StarNode node) {
    if (_cache[node] case bool b) return b;

    return _cache[node] = node.child.acceptSimpleVisitor<bool>(this);
  }

  @override
  bool visitAndPredicateNode(AndPredicateNode node) {
    if (_cache[node] case bool b) return b;

    return _cache[node] = node.child.acceptSimpleVisitor<bool>(this);
  }

  @override
  bool visitNotPredicateNode(NotPredicateNode node) {
    if (_cache[node] case bool b) return b;

    return _cache[node] = node.child.acceptSimpleVisitor<bool>(this);
  }

  @override
  bool visitOptionalNode(OptionalNode node) {
    if (_cache[node] case bool b) return b;

    return _cache[node] = node.child.acceptSimpleVisitor<bool>(this);
  }


  @override
  bool visitExceptNode(ExceptNode node) {
    if (_cache[node] case bool b) return b;

    return _cache[node] = node.child.acceptSimpleVisitor<bool>(this);
  }

  @override
  bool visitReferenceNode(ReferenceNode node) {
    if (_cache[node] case bool b) return b;

    _cache[node] = false;
    _cache[node] = rules[node.ruleName]!.$2.acceptSimpleVisitor<bool>(this);

    return _cache[node]!;
  }

  @override
  bool visitFragmentNode(FragmentNode node) {
    if (_cache[node] case bool b) return b;

    _cache[node] = false;
    _cache[node] =
        fragments[node.fragmentName]?.$2.acceptSimpleVisitor<bool>(this) ??
        inline[node.fragmentName]?.$2.acceptSimpleVisitor<bool>(this) ??
        false;

    return _cache[node]!;
  }

  @override
  bool visitNamedNode(NamedNode node) {
    if (_cache[node] case bool b) return b;

    return _cache[node] = node.child.acceptSimpleVisitor<bool>(this);
  }

  @override
  bool visitActionNode(ActionNode node) {
    if (_cache[node] case bool b) return b;

    return _cache[node] = node.child.acceptSimpleVisitor<bool>(this);
  }

  @override
  bool visitInlineActionNode(InlineActionNode node) {
    if (_cache[node] case bool b) return b;

    return _cache[node] = node.child.acceptSimpleVisitor<bool>(this);
  }

  @override
  bool visitStartOfInputNode(StartOfInputNode node) {
    if (_cache[node] case bool b) return b;

    return _cache[node] = true;
  }

  @override
  bool visitEndOfInputNode(EndOfInputNode node) {
    if (_cache[node] case bool b) return b;

    return _cache[node] = true;
  }

  @override
  bool visitAnyCharacterNode(AnyCharacterNode node) {
    if (_cache[node] case bool b) return b;

    return _cache[node] = true;
  }
}
