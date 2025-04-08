import "package:parser_peg/src/generator.dart";
import "package:parser_peg/src/node.dart";
import "package:parser_peg/src/statement.dart";
import "package:parser_peg/src/visitor/statement_visitor.dart";

class StatementTranslatorVisitor implements StatementVisitor<List<Statement>, String?> {
  @override
  List<Statement> visitDeclarationStatement(DeclarationStatement statement, String? type) {
    return [
      DeclarationStatement(
        statement.type ?? type,
        statement.names,
        statement.node,
        tag: statement.tag,
      ),
    ];
  }

  @override
  List<Statement> visitHybridNamespaceStatement(HybridNamespaceStatement statement, String? type) {
    return [
      DeclarationStatement(
        statement.type,
        [statement.name],
        ChoiceNode([
          for (var innerStatement in statement.children)
            if (innerStatement case DeclarationStatement(:var names))
              ReferenceNode([statement.name, names.first].join(ParserGenerator.separator))
            else if (innerStatement case HybridNamespaceStatement(:var name))
              ReferenceNode([statement.name, name].join(ParserGenerator.separator)),
        ]),
        tag: statement.outerTag,
      ),
      NamespaceStatement(
        statement.name,
        statement.children.expand((s) => s.acceptVisitor(this, statement.type ?? type)).toList(),
        tag: statement.innerTag,
      ),
    ];
  }

  @override
  List<Statement> visitNamespaceStatement(NamespaceStatement statement, String? type) {
    return [
      NamespaceStatement(
        statement.name,
        statement.children.expand((s) => s.acceptVisitor(this, type)).toList(),
        tag: statement.tag,
      ),
    ];
  }
}
