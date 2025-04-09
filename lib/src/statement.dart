import "package:parser_peg/src/node.dart";
import "package:parser_peg/src/visitor/statement_visitor.dart";

enum Tag { rule, fragment, inline }

sealed class Statement {
  O acceptVisitor<O, I>(StatementVisitor<O, I> visitor, I parameters);
}

final class NamespaceStatement implements Statement {
  const NamespaceStatement(this.name, this.children, {required this.tag});
  const NamespaceStatement.predefined(this.name, this.children) : tag = null;

  final String? name;
  final List<Statement> children;
  final Tag? tag;

  @override
  O acceptVisitor<O, I>(StatementVisitor<O, I> visitor, I parameters) {
    return visitor.visitNamespaceStatement(this, parameters);
  }
}

final class DeclarationTypeStatement implements Statement {
  const DeclarationTypeStatement(this.type, this.names, {required this.tag});
  const DeclarationTypeStatement.predefined(this.names, {this.type = "String"}) : tag = null;

  final String? type;
  final List<String> names;
  final Tag? tag;

  @override
  O acceptVisitor<O, I>(StatementVisitor<O, I> visitor, I parameters) {
    return visitor.visitDeclarationTypeStatement(this, parameters);
  }
}

final class DeclarationStatement implements Statement {
  const DeclarationStatement(this.type, this.name, this.node, {required this.tag});
  const DeclarationStatement.predefined(this.name, this.node, {this.type = "String"}) : tag = null;

  final String? type;
  final String name;
  final Node node;
  final Tag? tag;

  @override
  O acceptVisitor<O, I>(StatementVisitor<O, I> visitor, I parameters) {
    return visitor.visitDeclarationStatement(this, parameters);
  }
}

final class HybridNamespaceStatement implements Statement {
  const HybridNamespaceStatement(
    this.type,
    this.name,
    this.children, {
    required this.outerTag,
    required this.innerTag,
  });
  const HybridNamespaceStatement.predefined(this.type, this.name, this.children)
    : outerTag = null,
      innerTag = null;

  final String? type;
  final String? name;
  final List<Statement> children;
  final Tag? outerTag;
  final Tag? innerTag;

  @override
  O acceptVisitor<O, I>(StatementVisitor<O, I> visitor, I parameters) {
    return visitor.visitHybridNamespaceStatement(this, parameters);
  }
}
