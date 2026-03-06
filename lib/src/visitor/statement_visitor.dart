import "package:parser_peg/src/statement.dart";

/// A visitor interface for traversing the [Statement] hierarchy with an
/// additional input parameter of type [I] passed to every visit call.
///
/// Implementors must provide a handler for each concrete [Statement]
/// subtype. Each method receives the specific statement and a value of
/// type [I] (which may carry contextual information such as a type hint or
/// namespace prefix) and returns a value of type [O].
///
/// The four statement kinds map directly to the top-level grammar
/// constructs:
/// - [visitNamespaceStatement] — a named group that scopes a set of child
///   statements (e.g. a grammar section).
/// - [visitDeclarationTypeStatement] — a metadata statement that assigns
///   return types or tags to a set of named declarations without
///   themselves producing any rule output.
/// - [visitDeclarationStatement] — a single named rule or fragment
///   definition, optionally carrying a return type and tag.
/// - [visitHybridNamespaceStatement] — a combined namespace + declaration
///   that both groups child statements and introduces a top-level rule for
///   the namespace itself.
abstract class StatementVisitor<O, I> {
  /// Visits a [NamespaceStatement] with the given [parameters].
  O visitNamespaceStatement(NamespaceStatement statement, I parameters);

  /// Visits a [DeclarationTypeStatement] with the given [parameters].
  O visitDeclarationTypeStatement(DeclarationTypeStatement statement, I parameters);

  /// Visits a [DeclarationStatement] with the given [parameters].
  O visitDeclarationStatement(DeclarationStatement statement, I parameters);

  /// Visits a [HybridNamespaceStatement] with the given [parameters].
  O visitHybridNamespaceStatement(HybridNamespaceStatement statement, I parameters);
}
