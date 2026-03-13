import "package:parser_peg/src/statement.dart";
import "package:parser_peg/src/visitor/statement_visitor.dart";

/// Returns true if an import statement is included within the import AST.
class IsImportingVisitor implements StatementVisitor<bool, void> {
  const IsImportingVisitor();

  bool isImporting(Statement statement) => statement.acceptVisitor(this, null);

  @override
  bool visitDeclarationStatement(DeclarationStatement statement, void parameters) {
    return false;
  }

  @override
  bool visitDeclarationTypeStatement(DeclarationTypeStatement statement, void parameters) {
    return false;
  }

  @override
  bool visitImportStatement(ImportStatement statement, void parameters) {
    return true;
  }

  @override
  bool visitHybridNamespaceStatement(HybridNamespaceStatement statement, void parameters) {
    return statement.children.any((s) => s.acceptVisitor(this, null));
  }

  @override
  bool visitNamespaceStatement(NamespaceStatement statement, void parameters) {
    return statement.children.any((s) => s.acceptVisitor(this, null));
  }
}
