import "package:parser_peg/src/node.dart";

enum Tag {
  rule,
  fragment,
  none,
}

sealed class Statement {}

final class NamespaceStatement implements Statement {
  NamespaceStatement(this.name, this.children, {required this.tag});

  final String name;
  final List<Statement> children;
  final Tag tag;
}

final class DeclarationStatement implements Statement {
  DeclarationStatement(this.entry, {required this.tag});

  final Tag tag;
  final MapEntry<(String?, String), Node> entry;
}
