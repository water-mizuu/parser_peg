import "package:parser_peg/src/node.dart";

enum Tag {
  rule,
  fragment,
}

sealed class Statement {}

final class NamespaceStatement implements Statement {
  NamespaceStatement(this.name, this.children, {required this.tag});

  final String? name;
  final List<Statement> children;
  final Tag? tag;
}

final class DeclarationStatement implements Statement {
  DeclarationStatement(this.type, this.name, this.node, {required this.tag});

  final String? type;
  final String name;
  final Node node;
  final Tag? tag;
}
