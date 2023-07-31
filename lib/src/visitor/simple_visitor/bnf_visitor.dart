import "dart:convert";

import "package:parser_peg/src/generator.dart";
import "package:parser_peg/src/node.dart";
import "package:parser_peg/src/visitor/node_visitor.dart";

class ImperativeVisitor implements SimpleNodeVisitor<String> {
  @override
  String visitEpsilonNode(EpsilonNode node) => "ε";

  @override
  String visitTriePatternNode(TriePatternNode node) => node.options.join(" | ");

  @override
  String visitStringLiteralNode(StringLiteralNode node) => jsonEncode(node.value);

  @override
  String visitRangeNode(RangeNode node) => "[${node.ranges.map(((int, int) v) => "${v.$1}-${v.$2}").join()}}]";

  @override
  String visitRegExpNode(RegExpNode node) => "/${node.value.pattern}/";

  @override
  String visitRegExpEscapeNode(RegExpEscapeNode node) => node.pattern;

  @override
  String visitSequenceNode(SequenceNode node) => node.children //
      .map((Node child) => child.acceptSimpleVisitor(this).delimit())
      .join(" ");

  @override
  String visitChoiceNode(ChoiceNode node) => node.children //
      .map((Node child) => child.acceptSimpleVisitor(this).delimit())
      .join(" | ");

  @override
  String visitCountedNode(CountedNode node) => "${node.min}..${node.max}"
      ".${node.child.acceptSimpleVisitor(this).delimit()}";
  // CountedNode(
  //       node.min,
  //       node.max,
  //       node.child.acceptSimpleVisitor(this),
  //     );

  @override
  String visitPlusSeparatedNode(PlusSeparatedNode node) => "${node.separator.acceptSimpleVisitor(this).delimit()}."
      "${node.child.acceptSimpleVisitor(this).delimit()}+"
      "${node.isTrailingAllowed ? "?" : ""}";

  @override
  String visitStarSeparatedNode(StarSeparatedNode node) => "${node.separator.acceptSimpleVisitor(this).delimit()}."
      "${node.child.acceptSimpleVisitor(this).delimit()}*"
      "${node.isTrailingAllowed ? "?" : ""}";

  @override
  String visitPlusNode(PlusNode node) => "${node.child.acceptSimpleVisitor(this).delimit()}+";

  @override
  String visitStarNode(StarNode node) => "${node.child.acceptSimpleVisitor(this).delimit()}*";

  @override
  String visitAndPredicateNode(AndPredicateNode node) => "&${node.child.acceptSimpleVisitor(this).delimit()}";

  @override
  String visitNotPredicateNode(NotPredicateNode node) => "!${node.child.acceptSimpleVisitor(this).delimit()}";

  @override
  String visitOptionalNode(OptionalNode node) => "${node.child.acceptSimpleVisitor(this).delimit()}?";

  @override
  String visitReferenceNode(ReferenceNode node) => node.ruleName;

  @override
  String visitFragmentNode(FragmentNode node) => node.fragmentName;

  @override
  String visitNamedNode(NamedNode node) => "${node.name}:${node.child.acceptSimpleVisitor(this).delimit()}";

  @override
  String visitActionNode(ActionNode node) =>
      "${node.child.acceptSimpleVisitor(this).delimit()} (){\n${node.action.indent()}\n}";

  @override
  String visitInlineActionNode(InlineActionNode node) =>
      "${node.child.acceptSimpleVisitor(this).delimit()} { ${node.action} }";

  @override
  String visitStartOfInputNode(StartOfInputNode node) => "^";

  @override
  String visitEndOfInputNode(EndOfInputNode node) => r"$";

  @override
  String visitAnyCharacterNode(AnyCharacterNode node) => ".";
}

extension on String {
  bool get isDelimited =>
      !contains(" ") ||
      <(String, String)>[
        for (var (String l, String r) in <(String, String)>[
          ("'", "'"),
          ('"', '"'),
          ("`", "`"),
          ("(", ")"),
          ("[", "]"),
          ("{", "}"),
          ("/", "/"),
        ]) ...<(String, String)>[
          (l, r),
          (l, "$r?"),
          (l, "$r+"),
          (l, "$r*"),
          ("&$l", r),
          ("!$l", r),
        ],
      ].any(((String, String) pair) => startsWith(pair.$1) && endsWith(pair.$2));

  String delimit() => isDelimited ? this : "($this)";
}
