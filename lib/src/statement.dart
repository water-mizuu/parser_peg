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
  DeclarationStatement(this.entry, {required this.tag});

  final MapEntry<(String?, String), Node> entry;
  final Tag? tag;
}
