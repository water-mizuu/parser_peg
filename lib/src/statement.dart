import "package:parser_peg/src/node.dart";

enum Tag { rule, fragment, inline }

sealed class Statement {}

final class NamespaceStatement implements Statement {
  const NamespaceStatement(this.name, this.children, {required this.tag});
  const NamespaceStatement.predefined(this.name, this.children) : tag = null;

  final String? name;
  final List<Statement> children;
  final Tag? tag;
}

final class DeclarationStatement implements Statement {
  const DeclarationStatement(this.type, this.names, this.node, {required this.tag});
  const DeclarationStatement.predefined(this.names, this.node, {this.type = "String"}) : tag = null;

  final String? type;
  final List<String> names;
  final Node node;
  final Tag? tag;
}
