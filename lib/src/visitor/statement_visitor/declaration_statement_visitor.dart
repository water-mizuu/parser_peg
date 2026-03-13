import "package:parser_peg/src/statement.dart";
import "package:parser_peg/src/visitor/statement_visitor.dart";

/// Yields an iterable of all the declarations present in the grammar.
class DeclarationStatementVisitor
    implements StatementVisitor<Iterable<DeclarationStatement>, void> {
  const DeclarationStatementVisitor();

  @override
  Iterable<DeclarationStatement> visitDeclarationStatement(
    DeclarationStatement statement,
    void parameters,
  ) sync* {
    yield statement;
  }

  @override
  Iterable<DeclarationStatement> visitDeclarationTypeStatement(
    DeclarationTypeStatement statement,
    void parameters,
  ) sync* {}

  @override
  Iterable<DeclarationStatement> visitImportStatement(
    ImportStatement statement,
    void parameters,
  ) sync* {}

  @override
  Iterable<DeclarationStatement> visitHybridNamespaceStatement(
    HybridNamespaceStatement statement,
    void parameters,
  ) sync* {
    for (Statement child in statement.children) {
      yield* child.acceptVisitor(this, null);
    }
  }

  @override
  Iterable<DeclarationStatement> visitNamespaceStatement(
    NamespaceStatement statement,
    void parameters,
  ) sync* {
    for (Statement child in statement.children) {
      yield* child.acceptVisitor(this, null);
    }
  }
}
