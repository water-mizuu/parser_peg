import "package:parser_peg/src/node.dart";

sealed class Statement {
  Iterable<(MapEntry<(String?, String), Node>, {bool isFragment})> get entries;
}

final class NamespaceStatement implements Statement {
  NamespaceStatement(this.name, this.children);

  final String name;
  final List<Statement> children;

  @override
  Iterable<(MapEntry<(String?, String), Node>, {bool isFragment})> get entries sync* {
    for (Statement child in children) {
      for (var (
            MapEntry<(String?, String), Node>(key: (String? type, String subName), value: Node body),
            :bool isFragment
          ) in child.entries) {
        yield (MapEntry<(String?, String), Node>((type, "${name}__$subName"), body), isFragment: isFragment);
      }
    }
  }
}

final class DeclarationStatement implements Statement {
  DeclarationStatement(this.entry, {required this.isFragment});
  final MapEntry<(String?, String), Node> entry;
  final bool isFragment;

  @override
  List<(MapEntry<(String?, String), Node>, {bool isFragment})> get entries =>
      <(MapEntry<(String?, String), Node>, {bool isFragment})>[(entry, isFragment: isFragment)];
}
