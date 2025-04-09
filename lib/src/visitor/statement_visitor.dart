import "package:parser_peg/src/statement.dart";

abstract class StatementVisitor<O, I> {
  O visitNamespaceStatement(NamespaceStatement statement, I parameters);
  O visitDeclarationTypeStatement(DeclarationTypeStatement statement, I parameters);
  O visitDeclarationStatement(DeclarationStatement statement, I parameters);
  O visitHybridNamespaceStatement(HybridNamespaceStatement statement, I parameters);
}
