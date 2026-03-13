import "dart:convert";

import "package:parser_peg/src/generator.dart";
import "package:parser_peg/src/node.dart";
import "package:parser_peg/src/visitor/node_visitor.dart";

/// Prints out the nodes in a parse-friendly manner.
class NodePrinterVisitor implements SimpleNodeVisitor<String> {
  const NodePrinterVisitor();

  @override
  String visitCutNode(CutNode node) => "#";

  @override
  String visitEpsilonNode(EpsilonNode node) => "ε";

  @override
  String visitTriePatternNode(TriePatternNode node) {
    if (node.options.isEmpty) {
      return "ε";
    }

    if (node.options.length == 1) {
      return printStringLiteral(node.options.single);
    }

    var body = node.options.map(printStringLiteral).join(" | ");
    return "($body)";
  }

  @override
  String visitStringLiteralNode(StringLiteralNode node) => printStringLiteral(node.literal);

  String printStringLiteral(String literal) => jsonEncode(literal);

  @override
  String visitRangeNode(RangeNode node) {
    var sorted = node.ranges.toList()..sort((a, b) => a.$1.compareTo(b.$1));
    var content = StringBuffer();
    for (var (start, end) in sorted) {
      if (start == end) {
        content.write(_escapeRangeChar(start));
      } else {
        content
          ..write(_escapeRangeChar(start))
          ..write("-")
          ..write(_escapeRangeChar(end));
      }
    }

    return "[$content]";
  }

  @override
  String visitRegExpNode(RegExpNode node) {
    var escaped = node.value.replaceAll(r"\", r"\\").replaceAll("/", r"\/");
    return "/$escaped/";
  }

  @override
  String visitRegExpEscapeNode(RegExpEscapeNode node) => node.pattern;

  @override
  String visitSequenceNode(SequenceNode node) {
    var body = node.children.map(_asSequenceItem).join(" ");
    if (node.chosenIndex case var chosen?) {
      return "$body @$chosen";
    }

    return body;
  }

  @override
  String visitChoiceNode(ChoiceNode node) {
    return node.children.map((c) => c.acceptSimpleVisitor(this)).join(" | ");
  }

  @override
  String visitCountedNode(CountedNode node) {
    var child = _asAtom(node.child);
    if (node.max case var max?) {
      return "${node.min}..$max$child";
    }

    return "${node.min}..$child";
  }

  @override
  String visitPlusSeparatedNode(PlusSeparatedNode node) {
    var suffix = node.isTrailingAllowed ? "+?" : "+";
    return "${_asAtom(node.separator)}..${_asAtom(node.child)}$suffix";
  }

  @override
  String visitStarSeparatedNode(StarSeparatedNode node) {
    var suffix = node.isTrailingAllowed ? "*?" : "*";
    return "${_asAtom(node.separator)}..${_asAtom(node.child)}$suffix";
  }

  @override
  String visitPlusNode(PlusNode node) => "${_asPostfixTarget(node.child)}+";

  @override
  String visitStarNode(StarNode node) => "${_asPostfixTarget(node.child)}*";

  @override
  String visitAndPredicateNode(AndPredicateNode node) => "&${_asPrefixTarget(node.child)}";

  @override
  String visitNotPredicateNode(NotPredicateNode node) => "!${_asPrefixTarget(node.child)}";

  @override
  String visitOptionalNode(OptionalNode node) => "${_asPostfixTarget(node.child)}?";

  @override
  String visitExceptNode(ExceptNode node) => "~${_asPrefixTarget(node.child)}";

  @override
  String visitReferenceNode(ReferenceNode node) =>
      node.ruleName.split(ParserGenerator.separator).join(".");

  @override
  String visitFragmentNode(FragmentNode node) =>
      node.fragmentName.split(ParserGenerator.separator).join(".");

  @override
  String visitNamedNode(NamedNode node) {
    return "${node.name}:${_asSpecial(node.child)}";
  }

  @override
  String visitActionNode(ActionNode node) {
    return "${_asActionTarget(node.child)} { ${node.action} }";
  }

  @override
  String visitInlineActionNode(InlineActionNode node) {
    return "${_asActionTarget(node.child)} |> ${node.action}";
  }

  @override
  String visitStartOfInputNode(StartOfInputNode node) => "^";

  @override
  String visitEndOfInputNode(EndOfInputNode node) => r"$";

  @override
  String visitAnyCharacterNode(AnyCharacterNode node) => ".";

  String _asActionTarget(Node node) {
    if (node is SequenceNode) {
      return node.acceptSimpleVisitor(this);
    }

    return "(${node.acceptSimpleVisitor(this)})";
  }

  String _asSequenceItem(Node node) {
    if (node is ChoiceNode) {
      return "(${node.acceptSimpleVisitor(this)})";
    }

    return node.acceptSimpleVisitor(this);
  }

  String _asSpecial(Node node) {
    if (node is PlusSeparatedNode ||
        node is StarSeparatedNode ||
        node is CountedNode ||
        node is PlusNode ||
        node is StarNode ||
        node is OptionalNode ||
        node is AndPredicateNode ||
        node is NotPredicateNode ||
        node is ExceptNode ||
        node is ReferenceNode ||
        node is FragmentNode ||
        node is NamedNode ||
        node is StringLiteralNode ||
        node is RangeNode ||
        node is RegExpNode ||
        node is RegExpEscapeNode ||
        node is EpsilonNode ||
        node is CutNode ||
        node is StartOfInputNode ||
        node is EndOfInputNode ||
        node is AnyCharacterNode ||
        node is TriePatternNode) {
      return node.acceptSimpleVisitor(this);
    }

    return "(${node.acceptSimpleVisitor(this)})";
  }

  String _asPostfixTarget(Node node) {
    if (node is ReferenceNode ||
        node is FragmentNode ||
        node is NamedNode ||
        node is StringLiteralNode ||
        node is RangeNode ||
        node is RegExpNode ||
        node is RegExpEscapeNode ||
        node is EpsilonNode ||
        node is CutNode ||
        node is StartOfInputNode ||
        node is EndOfInputNode ||
        node is AnyCharacterNode ||
        node is TriePatternNode) {
      return node.acceptSimpleVisitor(this);
    }

    return "(${node.acceptSimpleVisitor(this)})";
  }

  String _asPrefixTarget(Node node) {
    if (node is ReferenceNode ||
        node is FragmentNode ||
        node is NamedNode ||
        node is StringLiteralNode ||
        node is RangeNode ||
        node is RegExpNode ||
        node is RegExpEscapeNode ||
        node is EpsilonNode ||
        node is CutNode ||
        node is StartOfInputNode ||
        node is EndOfInputNode ||
        node is AnyCharacterNode ||
        node is TriePatternNode ||
        node is PlusNode ||
        node is StarNode ||
        node is OptionalNode) {
      return node.acceptSimpleVisitor(this);
    }

    return "(${node.acceptSimpleVisitor(this)})";
  }

  String _asAtom(Node node) {
    if (node is ReferenceNode ||
        node is FragmentNode ||
        node is NamedNode ||
        node is StringLiteralNode ||
        node is RangeNode ||
        node is RegExpNode ||
        node is RegExpEscapeNode ||
        node is EpsilonNode ||
        node is CutNode ||
        node is StartOfInputNode ||
        node is EndOfInputNode ||
        node is AnyCharacterNode ||
        node is TriePatternNode) {
      return node.acceptSimpleVisitor(this);
    }

    return "(${node.acceptSimpleVisitor(this)})";
  }

  String _escapeRangeChar(int codeUnit) {
    switch (codeUnit) {
      case 9:
        return r"\t";
      case 10:
        return r"\n";
      case 13:
        return r"\r";
      case 92:
        return r"\\";
      case 93:
        return r"\]";
      case 94:
        return r"\^";
      case 45:
        return r"\-";
      default:
        if (codeUnit < 32 || codeUnit > 126) {
          return r"\u"
              "{${codeUnit.toRadixString(16)}}";
        }
        return String.fromCharCode(codeUnit);
    }
  }
}
