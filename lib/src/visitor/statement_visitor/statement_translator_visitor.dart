import "package:parser_peg/src/generator.dart";
import "package:parser_peg/src/node.dart";
import "package:parser_peg/src/statement.dart";
import "package:parser_peg/src/visitor/statement_visitor.dart";

class StatementTranslatorVisitor implements StatementVisitor<List<Statement>, String?> {
  final Map<String, String> _declaredTypes = {};
  final Map<String, Tag> _declaredTags = {};

  @override
  List<Statement> visitDeclarationTypeStatement(DeclarationTypeStatement statement, String? type) {
    if (statement.type case var type?) {
      for (var name in statement.names) {
        _declaredTypes[name] = type;
      }
    }
    if (statement.tag case var tag?) {
      for (var name in statement.names) {
        _declaredTags[name] = tag;
      }
    }

    // We don't return anything here. Basically, treat the statement as metadata.
    return [];
  }

  @override
  List<Statement> visitDeclarationStatement(DeclarationStatement statement, String? type) {
    return [
      DeclarationStatement(
        statement.type ?? _declaredTypes[statement.name] ?? type,
        statement.name,
        statement.node,
        tag: statement.tag,
      ),
    ];
  }

  @override
  List<Statement> visitHybridNamespaceStatement(HybridNamespaceStatement statement, String? type) {
    return [
      /// If there is a name, then we create a new declaration statement.
      /// Else we just treat it as a statement statement with types.
      if (statement.name case var name?)
        DeclarationStatement(
          statement.type,
          name,
          ChoiceNode([
            for (var innerStatement in statement.children)
              if (innerStatement case DeclarationStatement())
                ReferenceNode([name, innerStatement.name].join(ParserGenerator.separator))
              else if (innerStatement case HybridNamespaceStatement())
                ReferenceNode([name, innerStatement.name].join(ParserGenerator.separator)),
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
