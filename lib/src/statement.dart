import "package:parser_peg/src/node.dart";

enum Tag {
  rule,
  fragment,
  inline,
}

sealed class Statement {}

final class NamespaceStatement implements Statement {
  const NamespaceStatement(this.name, this.children, {required this.tag});

  final String? name;
  final List<Statement> children;
  final Tag? tag;
}

final class DeclarationStatement implements Statement {
  const DeclarationStatement(this.type, this.name, this.node, {required this.tag});
  const DeclarationStatement.predefined(this.name, this.node, {this.type = "String"}) : tag = null;

  final String? type;
  final String name;
  final Node node;
  final Tag? tag;
}
