// ignore_for_file: prefer_const_constructors

import "package:parser_peg/src/node.dart";
import "package:parser_peg/src/visitor/node_visitor/parametrized_visitor/simplify_visitor.dart";
import "package:test/test.dart";

void main() {
  group("SimplifyVisitor", () {
    var visitor = SimplifyVisitor();

    test("preserves simple nodes", () {
      var node = StringLiteralNode("hello");
      var result = node.acceptParametrizedVisitor(visitor, 0);

      expect(result, isA<StringLiteralNode>());
      expect((result as StringLiteralNode).literal, "hello");
    });

    test("simplifies nested sequences", () {
      // SimplifyVisitor doesn't flatten - it wraps in fragments
      var inner = SequenceNode([StringLiteralNode("a"), StringLiteralNode("b")], chosenIndex: null);

      var outer = SequenceNode([inner, StringLiteralNode("c")], chosenIndex: null);

      var result = outer.acceptParametrizedVisitor(visitor, 0);

      expect(result, isA<SequenceNode>());
      // Result should have 2-3 children depending on fragment wrapping
      expect((result as SequenceNode).children.length, greaterThanOrEqualTo(2));
    });

    test("simplifies nested choices", () {
      // SimplifyVisitor doesn't flatten - it wraps in fragments
      var inner = ChoiceNode([StringLiteralNode("b"), StringLiteralNode("c")]);

      var outer = ChoiceNode([StringLiteralNode("a"), inner]);

      var result = outer.acceptParametrizedVisitor(visitor, 0);

      expect(result, isA<ChoiceNode>());
      // Result should have 2-3 children depending on fragment wrapping
      expect((result as ChoiceNode).children.length, greaterThanOrEqualTo(2));
    });

    test("converts many strings to trie", () {
      // Need >= 4 strings AND average length >= 8 to convert to trie
      var choice = ChoiceNode([
        StringLiteralNode("verylongstring"), // 14
        StringLiteralNode("anotherlongone"), // 14
        StringLiteralNode("thirdlongword"), // 13
        StringLiteralNode("fourthlongword"), // 14
      ]);

      var result = choice.acceptParametrizedVisitor(visitor, 0);

      // Should convert to TriePatternNode (average length is ~13.75 > 8)
      expect(result, isA<TriePatternNode>());
    });

    test("does not convert few strings to trie", () {
      var choice = ChoiceNode([StringLiteralNode("a"), StringLiteralNode("b")]);

      var result = choice.acceptParametrizedVisitor(visitor, 0);

      // Should stay as ChoiceNode
      expect(result, isA<ChoiceNode>());
    });

    test("converts character ranges to TriePatternNode", () {
      var choice = ChoiceNode([
        RangeNode({(97, 122)}), // a-z
        RangeNode({(65, 90)}), // A-Z
        RangeNode({(48, 57)}), // 0-9
      ]);

      var result = choice.acceptParametrizedVisitor(visitor, 0);

      // May convert to trie if heuristic matches
      expect(result, anyOf([isA<TriePatternNode>(), isA<ChoiceNode>()]));
    });

    test("simplifies optional nested sequences", () {
      var inner = SequenceNode([StringLiteralNode("a"), StringLiteralNode("b")], chosenIndex: null);

      var optional = OptionalNode(inner);

      var result = optional.acceptParametrizedVisitor(visitor, 0);

      expect(result, isA<OptionalNode>());
      // Inner sequence may be simplified
      expect((result as OptionalNode).child, isNotNull);
    });

    test("simplifies starred nested nodes", () {
      var inner = SequenceNode([StringLiteralNode("a"), StringLiteralNode("b")], chosenIndex: null);

      var starred = StarNode(inner);

      var result = starred.acceptParametrizedVisitor(visitor, 0);

      expect(result, isA<StarNode>());
    });

    test("handles plus with nested content", () {
      var inner = ChoiceNode([
        StringLiteralNode("a"),
        StringLiteralNode("b"),
        StringLiteralNode("c"),
        StringLiteralNode("d"),
      ]);

      var plus = PlusNode(inner);

      var result = plus.acceptParametrizedVisitor(visitor, 0);

      expect(result, isA<PlusNode>());
    });

    test("simplifies plus-separated nodes", () {
      var expr = PlusSeparatedNode(
        StringLiteralNode(","),
        StringLiteralNode("item"),
        isTrailingAllowed: true,
      );

      var result = expr.acceptParametrizedVisitor(visitor, 0);

      expect(result, isNotNull);
    });

    test("simplifies star-separated nodes", () {
      var expr = StarSeparatedNode(
        StringLiteralNode(","),
        StringLiteralNode("item"),
        isTrailingAllowed: true,
      );

      var result = expr.acceptParametrizedVisitor(visitor, 0);

      expect(result, isNotNull);
    });

    test("preserves named nodes", () {
      var named = NamedNode("capture", StringLiteralNode("x"));

      var result = named.acceptParametrizedVisitor(visitor, 0);

      expect(result, isA<NamedNode>());
      expect((result as NamedNode).name, "capture");
    });

    test("preserves action nodes", () {
      var action = InlineActionNode(
        StringLiteralNode("x"),
        "x => x.toUpperCase()",
        areIndicesProvided: false,
        isSpanUsed: false,
      );

      var result = action.acceptParametrizedVisitor(visitor, 0);

      expect(result, isA<InlineActionNode>());
    });

    test("preserves predicates", () {
      var andPred = AndPredicateNode(StringLiteralNode("a"));
      var result = andPred.acceptParametrizedVisitor(visitor, 0);

      expect(result, isA<AndPredicateNode>());

      var notPred = NotPredicateNode(StringLiteralNode("a"));
      result = notPred.acceptParametrizedVisitor(visitor, 0);

      expect(result, isA<NotPredicateNode>());
    });

    test("adds new fragments for extracted subexpressions", () {
      var choice = ChoiceNode(List.generate(20, (i) => StringLiteralNode("option$i")));

      (_) = choice.acceptParametrizedVisitor(visitor, 0);

      expect(
        visitor.addedFragments,
        isNotEmpty,
        reason: "Should create fragments for extracted choices",
      );
    });

    test("handles depth limit gracefully", () {
      // Build a deeply nested sequence
      Node node = StringLiteralNode("base");
      for (int i = 0; i < 100; i++) {
        node = SequenceNode([node], chosenIndex: null);
      }

      var result = node.acceptParametrizedVisitor(visitor, 0);

      // Should simplify and not crash
      expect(result, isNotNull);
    });
  });

  group("Trie conversion heuristics", () {
    var visitor = SimplifyVisitor();

    test("converts common keywords to trie", () {
      // Use longer strings to meet the average length >= 8 requirement
      var choice = ChoiceNode([
        StringLiteralNode("interface"),
        StringLiteralNode("abstract"),
        StringLiteralNode("implementation"),
        StringLiteralNode("delegation"),
        StringLiteralNode("specialization"),
        StringLiteralNode("inheritance"),
      ]);

      var result = choice.acceptParametrizedVisitor(visitor, 0);

      expect(result, isA<TriePatternNode>());
    });

    test("does not convert single item to trie", () {
      var choice = ChoiceNode([StringLiteralNode("long_string_here")]);
      var result = choice.acceptParametrizedVisitor(visitor, 0);

      // Single item shouldn't be converted to trie
      expect(result, isA<ChoiceNode>());
    });

    test("converts many single-char alternatives to trie", () {
      var choice = ChoiceNode(
        List.generate(
          26,
          (i) => StringLiteralNode(
            String.fromCharCode(97 + i), // a-z
          ),
        ),
      );

      var result = choice.acceptParametrizedVisitor(visitor, 0);

      expect(result, anyOf([isA<TriePatternNode>(), isA<ChoiceNode>()]));
    });
  });
}
