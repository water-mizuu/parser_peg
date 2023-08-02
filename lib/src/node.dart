// ignore_for_file: use_to_and_as_if_applicable

import "package:parser_peg/src/visitor/node_visitor.dart";

sealed class Node {
  O acceptSimpleVisitor<O>(SimpleNodeVisitor<O> visitor);
  O acceptSimplifierVisitor<O>(SimplifierNodeVisitor<O> visitor, int depth);
  O acceptCompilerVisitor<O, I>(
    CompilerNodeVisitor<O, I> visitor, {
    required bool isNullAllowed,
    required Set<String>? withNames,
    required I? inner,
    required bool reported,
  });

  Iterable<Node> get children;
}

sealed class AtomicNode implements Node {}

class EpsilonNode implements AtomicNode {
  const EpsilonNode();

  @override
  Iterable<Node> get children => <Node>[];

  @override
  O acceptSimpleVisitor<O>(SimpleNodeVisitor<O> visitor) => visitor.visitEpsilonNode(this);

  @override
  O acceptSimplifierVisitor<O>(SimplifierNodeVisitor<O> visitor, int depth) => visitor.visitEpsilonNode(this, depth);

  @override
  O acceptCompilerVisitor<O, I>(
    CompilerNodeVisitor<O, I> visitor, {
    required bool isNullAllowed,
    required Set<String>? withNames,
    required I? inner,
    required bool reported,
  }) =>
      visitor.visitEpsilonNode(
        this,
        isNullAllowed: isNullAllowed,
        withNames: withNames,
        inner: inner,
        reported: reported,
      );
}

class TriePatternNode implements AtomicNode {
  const TriePatternNode(this.options);
  final List<String> options;

  @override
  Iterable<Node> get children => <Node>[];

  @override
  O acceptSimpleVisitor<O>(SimpleNodeVisitor<O> visitor) => visitor.visitTriePatternNode(this);

  @override
  O acceptSimplifierVisitor<O>(SimplifierNodeVisitor<O> visitor, int depth) =>
      visitor.visitTriePatternNode(this, depth);

  @override
  O acceptCompilerVisitor<O, I>(
    CompilerNodeVisitor<O, I> visitor, {
    required bool isNullAllowed,
    required Set<String>? withNames,
    required I? inner,
    required bool reported,
  }) =>
      visitor.visitTriePatternNode(
        this,
        isNullAllowed: isNullAllowed,
        withNames: withNames,
        inner: inner,
        reported: reported,
      );
}

class StringLiteralNode implements AtomicNode {
  const StringLiteralNode(this.literal);
  final String literal;

  @override
  Iterable<Node> get children => <Node>[];

  @override
  O acceptSimpleVisitor<O>(SimpleNodeVisitor<O> visitor) => visitor.visitStringLiteralNode(this);

  @override
  O acceptSimplifierVisitor<O>(SimplifierNodeVisitor<O> visitor, int depth) =>
      visitor.visitStringLiteralNode(this, depth);

  @override
  O acceptCompilerVisitor<O, I>(
    CompilerNodeVisitor<O, I> visitor, {
    required bool isNullAllowed,
    required Set<String>? withNames,
    required I? inner,
    required bool reported,
  }) =>
      visitor.visitStringLiteralNode(
        this,
        isNullAllowed: isNullAllowed,
        withNames: withNames,
        inner: inner,
        reported: reported,
      );
}

class RangeNode implements AtomicNode {
  const RangeNode(this.ranges);
  final Set<(int, int)> ranges;

  @override
  Iterable<Node> get children => <Node>[];

  @override
  O acceptSimpleVisitor<O>(SimpleNodeVisitor<O> visitor) => visitor.visitRangeNode(this);

  @override
  O acceptSimplifierVisitor<O>(SimplifierNodeVisitor<O> visitor, int depth) => visitor.visitRangeNode(this, depth);

  @override
  O acceptCompilerVisitor<O, I>(
    CompilerNodeVisitor<O, I> visitor, {
    required bool isNullAllowed,
    required Set<String>? withNames,
    required I? inner,
    required bool reported,
  }) =>
      visitor.visitRangeNode(
        this,
        isNullAllowed: isNullAllowed,
        withNames: withNames,
        inner: inner,
        reported: reported,
      );
}

class RegExpNode implements AtomicNode {
  const RegExpNode(this.value);
  final RegExp value;

  @override
  Iterable<Node> get children => <Node>[];

  @override
  O acceptSimpleVisitor<O>(SimpleNodeVisitor<O> visitor) => visitor.visitRegExpNode(this);

  @override
  O acceptSimplifierVisitor<O>(SimplifierNodeVisitor<O> visitor, int depth) => visitor.visitRegExpNode(this, depth);

  @override
  O acceptCompilerVisitor<O, I>(
    CompilerNodeVisitor<O, I> visitor, {
    required bool isNullAllowed,
    required Set<String>? withNames,
    required I? inner,
    required bool reported,
  }) =>
      visitor.visitRegExpNode(
        this,
        isNullAllowed: isNullAllowed,
        withNames: withNames,
        inner: inner,
        reported: reported,
      );
}

abstract interface class RegExpEscapeNode implements AtomicNode {
  const RegExpEscapeNode(this.pattern);

  final String pattern;

  @override
  O acceptSimpleVisitor<O>(SimpleNodeVisitor<O> visitor) => visitor.visitRegExpEscapeNode(this);

  @override
  O acceptCompilerVisitor<O, I>(
    CompilerNodeVisitor<O, I> visitor, {
    required bool isNullAllowed,
    required Set<String>? withNames,
    required I? inner,
    required bool reported,
  }) =>
      visitor.visitRegExpEscapeNode(
        this,
        isNullAllowed: isNullAllowed,
        withNames: withNames,
        inner: inner,
        reported: reported,
      );

  @override
  O acceptSimplifierVisitor<O>(SimplifierNodeVisitor<O> visitor, int depth) =>
      visitor.visitRegExpEscapeNode(this, depth);

  @override
  Iterable<Node> get children => <Node>[];
}

enum SimpleRegExpEscapeNode implements RegExpEscapeNode {
  digit(r"\d"),
  word(r"\w"),
  whitespace(r"\s"),

  /// Inverses
  notDigit(r"\D"),
  notWord(r"\W"),
  notWhitespace(r"\S"),

  /// Spaces
  tab(r"\t"),
  newLine(r"\n"),
  carriageReturn(r"\r"),
  formFeed(r"\f"),
  verticalTab(r"\v"),
  ;

  const SimpleRegExpEscapeNode(this.pattern);
  @override
  final String pattern;

  @override
  O acceptSimpleVisitor<O>(SimpleNodeVisitor<O> visitor) => visitor.visitRegExpEscapeNode(this);

  @override
  O acceptCompilerVisitor<O, I>(
    CompilerNodeVisitor<O, I> visitor, {
    required bool isNullAllowed,
    required Set<String>? withNames,
    required I? inner,
    required bool reported,
  }) =>
      visitor.visitRegExpEscapeNode(
        this,
        isNullAllowed: isNullAllowed,
        withNames: withNames,
        inner: inner,
        reported: reported,
      );

  @override
  O acceptSimplifierVisitor<O>(SimplifierNodeVisitor<O> visitor, int depth) =>
      visitor.visitRegExpEscapeNode(this, depth);

  @override
  Iterable<Node> get children => <Node>[];
}

class SequenceNode implements Node {
  const SequenceNode(this.children, {required this.choose});

  final int? choose;

  @override
  final List<Node> children;

  @override
  O acceptSimpleVisitor<O>(SimpleNodeVisitor<O> visitor) => visitor.visitSequenceNode(this);

  @override
  O acceptSimplifierVisitor<O>(SimplifierNodeVisitor<O> visitor, int depth) => visitor.visitSequenceNode(this, depth);

  @override
  O acceptCompilerVisitor<O, I>(
    CompilerNodeVisitor<O, I> visitor, {
    required bool isNullAllowed,
    required Set<String>? withNames,
    required I? inner,
    required bool reported,
  }) =>
      visitor.visitSequenceNode(
        this,
        isNullAllowed: isNullAllowed,
        withNames: withNames,
        inner: inner,
        reported: reported,
      );
}

class ChoiceNode implements Node {
  const ChoiceNode(this.children);

  @override
  final List<Node> children;

  @override
  O acceptSimpleVisitor<O>(SimpleNodeVisitor<O> visitor) => visitor.visitChoiceNode(this);

  @override
  O acceptSimplifierVisitor<O>(SimplifierNodeVisitor<O> visitor, int depth) => visitor.visitChoiceNode(this, depth);

  @override
  O acceptCompilerVisitor<O, I>(
    CompilerNodeVisitor<O, I> visitor, {
    required bool isNullAllowed,
    required Set<String>? withNames,
    required I? inner,
    required bool reported,
  }) =>
      visitor.visitChoiceNode(
        this,
        isNullAllowed: isNullAllowed,
        withNames: withNames,
        inner: inner,
        reported: reported,
      );
}

class CountedNode implements Node {
  const CountedNode(this.min, this.max, this.child);

  final Node child;
  final int min;
  final int? max;

  @override
  O acceptSimpleVisitor<O>(SimpleNodeVisitor<O> visitor) => visitor.visitCountedNode(this);

  @override
  O acceptSimplifierVisitor<O>(SimplifierNodeVisitor<O> visitor, int depth) => visitor.visitCountedNode(this, depth);

  @override
  O acceptCompilerVisitor<O, I>(
    CompilerNodeVisitor<O, I> visitor, {
    required bool isNullAllowed,
    required Set<String>? withNames,
    required I? inner,
    required bool reported,
  }) =>
      visitor.visitCountedNode(
        this,
        isNullAllowed: isNullAllowed,
        withNames: withNames,
        inner: inner,
        reported: reported,
      );

  @override
  Iterable<Node> get children => <Node>[child];
}

class PlusSeparatedNode implements Node {
  const PlusSeparatedNode(this.separator, this.child, {required this.isTrailingAllowed});

  final Node separator;
  final Node child;
  final bool isTrailingAllowed;

  @override
  O acceptSimpleVisitor<O>(SimpleNodeVisitor<O> visitor) => visitor.visitPlusSeparatedNode(this);

  @override
  O acceptSimplifierVisitor<O>(SimplifierNodeVisitor<O> visitor, int depth) =>
      visitor.visitPlusSeparatedNode(this, depth);

  @override
  O acceptCompilerVisitor<O, I>(
    CompilerNodeVisitor<O, I> visitor, {
    required bool isNullAllowed,
    required Set<String>? withNames,
    required I? inner,
    required bool reported,
  }) =>
      visitor.visitPlusSeparatedNode(
        this,
        isNullAllowed: isNullAllowed,
        withNames: withNames,
        inner: inner,
        reported: reported,
      );

  @override
  Iterable<Node> get children => <Node>[separator, child];
}

class StarSeparatedNode implements Node {
  const StarSeparatedNode(this.separator, this.child, {required this.isTrailingAllowed});

  final Node separator;
  final Node child;
  final bool isTrailingAllowed;

  @override
  O acceptSimpleVisitor<O>(SimpleNodeVisitor<O> visitor) => visitor.visitStarSeparatedNode(this);

  @override
  O acceptSimplifierVisitor<O>(SimplifierNodeVisitor<O> visitor, int depth) =>
      visitor.visitStarSeparatedNode(this, depth);

  @override
  O acceptCompilerVisitor<O, I>(
    CompilerNodeVisitor<O, I> visitor, {
    required bool isNullAllowed,
    required Set<String>? withNames,
    required I? inner,
    required bool reported,
  }) =>
      visitor.visitStarSeparatedNode(
        this,
        isNullAllowed: isNullAllowed,
        withNames: withNames,
        inner: inner,
        reported: reported,
      );

  @override
  Iterable<Node> get children => <Node>[separator, child];
}

class PlusNode implements Node {
  const PlusNode(this.child);
  final Node child;

  @override
  Iterable<Node> get children => <Node>[child];

  @override
  O acceptSimpleVisitor<O>(SimpleNodeVisitor<O> visitor) => visitor.visitPlusNode(this);

  @override
  O acceptSimplifierVisitor<O>(SimplifierNodeVisitor<O> visitor, int depth) => visitor.visitPlusNode(this, depth);

  @override
  O acceptCompilerVisitor<O, I>(
    CompilerNodeVisitor<O, I> visitor, {
    required bool isNullAllowed,
    required Set<String>? withNames,
    required I? inner,
    required bool reported,
  }) =>
      visitor.visitPlusNode(
        this,
        isNullAllowed: isNullAllowed,
        withNames: withNames,
        inner: inner,
        reported: reported,
      );
}

class StarNode implements Node {
  const StarNode(this.child);
  final Node child;

  @override
  Iterable<Node> get children => <Node>[child];

  @override
  O acceptSimpleVisitor<O>(SimpleNodeVisitor<O> visitor) => visitor.visitStarNode(this);

  @override
  O acceptSimplifierVisitor<O>(SimplifierNodeVisitor<O> visitor, int depth) => visitor.visitStarNode(this, depth);

  @override
  O acceptCompilerVisitor<O, I>(
    CompilerNodeVisitor<O, I> visitor, {
    required bool isNullAllowed,
    required Set<String>? withNames,
    required I? inner,
    required bool reported,
  }) =>
      visitor.visitStarNode(
        this,
        isNullAllowed: isNullAllowed,
        withNames: withNames,
        inner: inner,
        reported: reported,
      );
}

class AndPredicateNode implements Node {
  const AndPredicateNode(this.child);
  final Node child;

  @override
  Iterable<Node> get children => <Node>[child];

  @override
  O acceptSimpleVisitor<O>(SimpleNodeVisitor<O> visitor) => visitor.visitAndPredicateNode(this);

  @override
  O acceptSimplifierVisitor<O>(SimplifierNodeVisitor<O> visitor, int depth) =>
      visitor.visitAndPredicateNode(this, depth);

  @override
  O acceptCompilerVisitor<O, I>(
    CompilerNodeVisitor<O, I> visitor, {
    required bool isNullAllowed,
    required Set<String>? withNames,
    required I? inner,
    required bool reported,
  }) =>
      visitor.visitAndPredicateNode(
        this,
        isNullAllowed: isNullAllowed,
        withNames: withNames,
        inner: inner,
        reported: reported,
      );
}

class NotPredicateNode implements Node {
  const NotPredicateNode(this.child);
  final Node child;

  @override
  Iterable<Node> get children => <Node>[child];

  @override
  O acceptSimpleVisitor<O>(SimpleNodeVisitor<O> visitor) => visitor.visitNotPredicateNode(this);

  @override
  O acceptSimplifierVisitor<O>(SimplifierNodeVisitor<O> visitor, int depth) =>
      visitor.visitNotPredicateNode(this, depth);

  @override
  O acceptCompilerVisitor<O, I>(
    CompilerNodeVisitor<O, I> visitor, {
    required bool isNullAllowed,
    required Set<String>? withNames,
    required I? inner,
    required bool reported,
  }) =>
      visitor.visitNotPredicateNode(
        this,
        isNullAllowed: isNullAllowed,
        withNames: withNames,
        inner: inner,
        reported: reported,
      );
}

class OptionalNode implements Node {
  const OptionalNode(this.child);
  final Node child;

  @override
  Iterable<Node> get children => <Node>[child];

  @override
  O acceptSimpleVisitor<O>(SimpleNodeVisitor<O> visitor) => visitor.visitOptionalNode(this);

  @override
  O acceptSimplifierVisitor<O>(SimplifierNodeVisitor<O> visitor, int depth) => visitor.visitOptionalNode(this, depth);

  @override
  O acceptCompilerVisitor<O, I>(
    CompilerNodeVisitor<O, I> visitor, {
    required bool isNullAllowed,
    required Set<String>? withNames,
    required I? inner,
    required bool reported,
  }) =>
      visitor.visitOptionalNode(
        this,
        isNullAllowed: isNullAllowed,
        withNames: withNames,
        inner: inner,
        reported: reported,
      );
}

class ReferenceNode implements Node {
  const ReferenceNode(this.ruleName);
  final String ruleName;

  @override
  Iterable<Node> get children => <Node>[];

  @override
  O acceptSimpleVisitor<O>(SimpleNodeVisitor<O> visitor) => visitor.visitReferenceNode(this);

  @override
  O acceptSimplifierVisitor<O>(SimplifierNodeVisitor<O> visitor, int depth) => visitor.visitReferenceNode(this, depth);

  @override
  O acceptCompilerVisitor<O, I>(
    CompilerNodeVisitor<O, I> visitor, {
    required bool isNullAllowed,
    required Set<String>? withNames,
    required I? inner,
    required bool reported,
  }) =>
      visitor.visitReferenceNode(
        this,
        isNullAllowed: isNullAllowed,
        withNames: withNames,
        inner: inner,
        reported: reported,
      );
}

class FragmentNode implements Node {
  const FragmentNode(this.fragmentName);
  final String fragmentName;

  @override
  Iterable<Node> get children => <Node>[];

  @override
  O acceptSimpleVisitor<O>(SimpleNodeVisitor<O> visitor) => visitor.visitFragmentNode(this);

  @override
  O acceptSimplifierVisitor<O>(SimplifierNodeVisitor<O> visitor, int depth) => visitor.visitFragmentNode(this, depth);

  @override
  O acceptCompilerVisitor<O, I>(
    CompilerNodeVisitor<O, I> visitor, {
    required bool isNullAllowed,
    required Set<String>? withNames,
    required I? inner,
    required bool reported,
  }) =>
      visitor.visitFragmentNode(
        this,
        isNullAllowed: isNullAllowed,
        withNames: withNames,
        inner: inner,
        reported: reported,
      );
}

class NamedNode implements Node {
  const NamedNode(this.name, this.child);
  final Node child;
  final String name;

  @override
  Iterable<Node> get children => <Node>[child];

  @override
  O acceptSimpleVisitor<O>(SimpleNodeVisitor<O> visitor) => visitor.visitNamedNode(this);

  @override
  O acceptSimplifierVisitor<O>(SimplifierNodeVisitor<O> visitor, int depth) => visitor.visitNamedNode(this, depth);

  @override
  O acceptCompilerVisitor<O, I>(
    CompilerNodeVisitor<O, I> visitor, {
    required bool isNullAllowed,
    required Set<String>? withNames,
    required I? inner,
    required bool reported,
  }) =>
      visitor.visitNamedNode(
        this,
        isNullAllowed: isNullAllowed,
        withNames: withNames,
        inner: inner,
        reported: reported,
      );
}

class ActionNode implements Node {
  const ActionNode(this.child, this.action, {required this.areIndicesProvided});
  final Node child;
  final String action;
  final bool areIndicesProvided;

  @override
  Iterable<Node> get children => <Node>[child];

  @override
  O acceptSimpleVisitor<O>(SimpleNodeVisitor<O> visitor) => visitor.visitActionNode(this);

  @override
  O acceptSimplifierVisitor<O>(SimplifierNodeVisitor<O> visitor, int depth) => visitor.visitActionNode(this, depth);

  @override
  O acceptCompilerVisitor<O, I>(
    CompilerNodeVisitor<O, I> visitor, {
    required bool isNullAllowed,
    required Set<String>? withNames,
    required I? inner,
    required bool reported,
  }) =>
      visitor.visitActionNode(
        this,
        isNullAllowed: isNullAllowed,
        withNames: withNames,
        inner: inner,
        reported: reported,
      );
}

class InlineActionNode implements Node {
  const InlineActionNode(this.child, this.action, {required this.areIndicesProvided});
  final Node child;
  final String action;
  final bool areIndicesProvided;

  @override
  Iterable<Node> get children => <Node>[child];

  @override
  O acceptSimpleVisitor<O>(SimpleNodeVisitor<O> visitor) => visitor.visitInlineActionNode(this);

  @override
  O acceptSimplifierVisitor<O>(SimplifierNodeVisitor<O> visitor, int depth) =>
      visitor.visitInlineActionNode(this, depth);

  @override
  O acceptCompilerVisitor<O, I>(
    CompilerNodeVisitor<O, I> visitor, {
    required bool isNullAllowed,
    required Set<String>? withNames,
    required I? inner,
    required bool reported,
  }) =>
      visitor.visitInlineActionNode(
        this,
        isNullAllowed: isNullAllowed,
        withNames: withNames,
        inner: inner,
        reported: reported,
      );
}

sealed class SpecialSymbolNode implements AtomicNode {}

class StartOfInputNode implements SpecialSymbolNode {
  const StartOfInputNode();

  @override
  Iterable<Node> get children => <Node>[];

  @override
  O acceptSimpleVisitor<O>(SimpleNodeVisitor<O> visitor) => visitor.visitStartOfInputNode(this);

  @override
  O acceptSimplifierVisitor<O>(SimplifierNodeVisitor<O> visitor, int depth) =>
      visitor.visitStartOfInputNode(this, depth);

  @override
  O acceptCompilerVisitor<O, I>(
    CompilerNodeVisitor<O, I> visitor, {
    required bool isNullAllowed,
    required Set<String>? withNames,
    required I? inner,
    required bool reported,
  }) =>
      visitor.visitStartOfInputNode(
        this,
        isNullAllowed: isNullAllowed,
        withNames: withNames,
        inner: inner,
        reported: reported,
      );
}

class EndOfInputNode implements SpecialSymbolNode {
  const EndOfInputNode();

  @override
  Iterable<Node> get children => <Node>[];

  @override
  O acceptSimpleVisitor<O>(SimpleNodeVisitor<O> visitor) => visitor.visitEndOfInputNode(this);

  @override
  O acceptSimplifierVisitor<O>(SimplifierNodeVisitor<O> visitor, int depth) => visitor.visitEndOfInputNode(this, depth);

  @override
  O acceptCompilerVisitor<O, I>(
    CompilerNodeVisitor<O, I> visitor, {
    required bool isNullAllowed,
    required Set<String>? withNames,
    required I? inner,
    required bool reported,
  }) =>
      visitor.visitEndOfInputNode(
        this,
        isNullAllowed: isNullAllowed,
        withNames: withNames,
        inner: inner,
        reported: reported,
      );
}

class AnyCharacterNode implements SpecialSymbolNode {
  const AnyCharacterNode();

  @override
  Iterable<Node> get children => <Node>[];

  @override
  O acceptSimpleVisitor<O>(SimpleNodeVisitor<O> visitor) => visitor.visitAnyCharacterNode(this);

  @override
  O acceptSimplifierVisitor<O>(SimplifierNodeVisitor<O> visitor, int depth) =>
      visitor.visitAnyCharacterNode(this, depth);

  @override
  O acceptCompilerVisitor<O, I>(
    CompilerNodeVisitor<O, I> visitor, {
    required bool isNullAllowed,
    required Set<String>? withNames,
    required I? inner,
    required bool reported,
  }) =>
      visitor.visitAnyCharacterNode(
        this,
        isNullAllowed: isNullAllowed,
        withNames: withNames,
        inner: inner,
        reported: reported,
      );
}
