import "package:parser_peg/src/generator.dart" show MonadicTypeExtension;
import "package:parser_peg/src/statement.dart";
import "package:parser_peg/src/visitor/node_visitor/simple_visitor/node_printer_visitor.dart";
import "package:parser_peg/src/visitor/statement_visitor.dart";

/// Prints out the equivalent of a statement which can be parsed back.
///   This is helpful in debugging the transformations of statements before
///   they get erased.
class StatementPrinterVisitor implements StatementVisitor<String, void> {
  const StatementPrinterVisitor();

  static const _indent = "  ";
  static const _nodePrinter = NodePrinterVisitor();

  @override
  String visitDeclarationTypeStatement(DeclarationTypeStatement statement, void _) {
    var parts = <String>[
      if (_explicitTag(statement.tag) case var tag && != "") tag,
      if (statement.type case var type?) type,
      statement.names.join(", "),
    ];

    return "${parts.join(" ")};";
  }

  @override
  String visitDeclarationStatement(DeclarationStatement statement, void _) {
    var parts = <String>[
      if (_explicitTag(statement.tag) case var tag && != "") tag,
      if (statement.type case var type?) type,
      statement.name,
      "=",
      statement.node.acceptSimpleVisitor(_nodePrinter),
    ];

    return "${parts.join(" ")};";
  }

  @override
  String visitHybridNamespaceStatement(HybridNamespaceStatement statement, void _) {
    var buffer = StringBuffer();

    if (statement.name case var name?) {
      var declarationHead = <String>[
        if (_explicitTag(statement.outerTag) case var tag && != "") tag,
        if (statement.type case var type?) type,
        name,
        "=",
        "choice!",
      ];
      buffer.writeln(declarationHead.join(" "));
    } else {
      var declarationHead = <String>[
        if (_explicitTag(statement.outerTag) case var tag && != "") tag,
        if (statement.type case var type?) type,
        "()",
        "=",
        "choice!",
      ];
      buffer.writeln(declarationHead.join(" "));
    }

    buffer.write(_explicitTag(statement.innerTag));
    buffer.writeln(" {");
    buffer.writeln(_printChildren(statement.children));
    buffer.write("}");

    return buffer.toString();
  }

  @override
  String visitNamespaceStatement(NamespaceStatement statement, void _) {
    var head = [
      if (_explicitTag(statement.tag) case var tag && != "") tag,
      if (statement.name case var name?) name,
      "{",
    ];
    var buffer = StringBuffer();
    buffer.writeln(head.join(" "));
    buffer.writeln(_printChildren(statement.children));
    buffer.write("}");

    return buffer.toString();
  }

  @override
  String visitImportStatement(ImportStatement statement, void _) {
    var alias = statement.alias == null ? "" : " as ${statement.alias}";

    return "import ${_nodePrinter.printStringLiteral(statement.path)}$alias;";
  }

  static String _explicitTag(Tag? tag) => tag?.apply((e) => "@${e.name}") ?? "";

  String _printChildren(List<Statement> children) {
    var result = children.map((s) => s.acceptVisitor(this, null)).join("\n");

    return result.split("\n").map((line) => line.isEmpty ? line : "$_indent$line").join("\n");
  }
}
