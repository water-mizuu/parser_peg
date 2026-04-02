// ignore_for_file: prefer_const_constructors

import "package:parser_peg/src/node.dart";
import "package:parser_peg/src/statement.dart";
import "package:parser_peg/src/visitor/node_visitor/simple_visitor/can_inline_visitor.dart";
import "package:parser_peg/src/visitor/node_visitor/simple_visitor/inline_visitor.dart";
import "package:parser_peg/src/visitor/node_visitor/simple_visitor/is_cut_visitor.dart";
import "package:parser_peg/src/visitor/node_visitor/simple_visitor/node_printer_visitor.dart";
import "package:parser_peg/src/visitor/node_visitor/simple_visitor/referenced_visitor.dart";
import "package:parser_peg/src/visitor/node_visitor/simple_visitor/remove_action_node_visitor.dart";
import "package:parser_peg/src/visitor/node_visitor/simple_visitor/remove_selection_visitor.dart";
import "package:test/test.dart";

void main() {
  group("RemoveActionNodeVisitor", () {
    const visitor = RemoveActionNodeVisitor();

    test("preserves basic terminals", () {
      expect(EpsilonNode().acceptSimpleVisitor(visitor), isA<EpsilonNode>());
      expect(AnyCharacterNode().acceptSimpleVisitor(visitor), isA<AnyCharacterNode>());
    });

    test("strips InlineActionNode to inner content", () {
      var action = InlineActionNode(
        StringLiteralNode("hello"),
        "x => x.toUpperCase()",
        areIndicesProvided: false,
        isSpanUsed: false,
      );
      var result = action.acceptSimpleVisitor(visitor);
      expect(result, isA<StringLiteralNode>());
    });

    test("preserves structure through nested nodes", () {
      var sequence = SequenceNode([
        StringLiteralNode("a"),
        InlineActionNode(
          StringLiteralNode("b"),
          "x => x",
          areIndicesProvided: false,
          isSpanUsed: false,
        ),
        StringLiteralNode("c"),
      ], chosenIndex: null);

      var result = sequence.acceptSimpleVisitor(visitor);
      expect(result, isA<SequenceNode>());
      expect((result as SequenceNode).children, hasLength(3));
    });

    test("handles choice nodes with actions", () {
      var choice = ChoiceNode([
        InlineActionNode(
          StringLiteralNode("a"),
          "x => x",
          areIndicesProvided: false,
          isSpanUsed: false,
        ),
        InlineActionNode(
          StringLiteralNode("b"),
          "x => x",
          areIndicesProvided: false,
          isSpanUsed: false,
        ),
      ]);

      var result = choice.acceptSimpleVisitor(visitor);
      expect(result, isA<ChoiceNode>());
    });
  });

  group("IsCutVisitor", () {
    const visitor = IsCutVisitor();

    test("detects cut node", () {
      expect(CutNode().acceptSimpleVisitor(visitor), isTrue);
    });

    test("non-cut terminals return false", () {
      expect(EpsilonNode().acceptSimpleVisitor(visitor), isFalse);
      expect(StringLiteralNode("x").acceptSimpleVisitor(visitor), isFalse);
      expect(AnyCharacterNode().acceptSimpleVisitor(visitor), isFalse);
    });

    test("cut in sequence", () {
      var sequence = SequenceNode([
        StringLiteralNode("a"),
        CutNode(),
        StringLiteralNode("b"),
      ], chosenIndex: null);

      expect(sequence.acceptSimpleVisitor(visitor), isTrue);
    });

    test("no cut in sequence", () {
      var sequence = SequenceNode([
        StringLiteralNode("a"),
        StringLiteralNode("b"),
      ], chosenIndex: null);

      expect(sequence.acceptSimpleVisitor(visitor), isFalse);
    });

    test("cut in choice alternative", () {
      var choice = ChoiceNode([StringLiteralNode("a"), CutNode()]);

      expect(choice.acceptSimpleVisitor(visitor), isTrue);
    });
  });

  group("CanInlineVisitor", () {
    var visitor = CanInlineVisitor({}, {}, {});

    test("simple terminals are inlineable", () {
      expect(visitor.canBeInlined(StringLiteralNode("x")), isTrue);
      expect(visitor.canBeInlined(EpsilonNode()), isTrue);
      expect(visitor.canBeInlined(AnyCharacterNode()), isTrue);
    });

    test("simple sequences are inlineable", () {
      var sequence = SequenceNode([
        StringLiteralNode("a"),
        StringLiteralNode("b"),
      ], chosenIndex: null);

      expect(visitor.canBeInlined(sequence), isTrue);
    });

    test("starred nodes are inlineable", () {
      var starred = StarNode(StringLiteralNode("a"));
      expect(visitor.canBeInlined(starred), isTrue);
    });

    test("optional nodes are inlineable", () {
      var optional = OptionalNode(StringLiteralNode("a"));
      expect(visitor.canBeInlined(optional), isTrue);
    });

    test("plus nodes with simple content are inlineable", () {
      var plus = PlusNode(StringLiteralNode("a"));
      expect(visitor.canBeInlined(plus), isTrue);
    });

    test("choice nodes with simple children are inlineable", () {
      var localVisitor = CanInlineVisitor({}, {}, {});
      var choice = ChoiceNode([StringLiteralNode("a"), StringLiteralNode("b")]);

      expect(localVisitor.canBeInlined(choice), isTrue);
    });

    test("reference nodes to inlineable rules are inlineable", () {
      var visitor = CanInlineVisitor({"rule": (null, StringLiteralNode("x"))}, {}, {});

      var reference = ReferenceNode("rule");
      expect(visitor.canBeInlined(reference), isTrue);
    });
  });

  group("RemoveSelectionVisitor", () {
    const visitor = RemoveSelectionVisitor();

    test("preserves non-selection nodes", () {
      var node = StringLiteralNode("hello");
      var result = node.acceptSimpleVisitor(visitor);
      expect(result, isA<StringLiteralNode>());
    });

    test("removes selection from named node", () {
      var named = NamedNode("capture", StringLiteralNode("x"));
      var result = named.acceptSimpleVisitor(visitor);
      expect(result, isA<NamedNode>());
      expect((result as NamedNode).name, "capture");
      expect(result.child, isA<StringLiteralNode>());
    });

    test("preserves structure in sequences", () {
      var sequence = SequenceNode([
        NamedNode("a", StringLiteralNode("x")),
        NamedNode("b", StringLiteralNode("y")),
      ], chosenIndex: 0);

      var result = sequence.acceptSimpleVisitor(visitor);
      expect(result, isA<SequenceNode>());
      expect((result as SequenceNode).chosenIndex, isNull);
    });

    test("removes choice selection", () {
      var choice = ChoiceNode([
        StringLiteralNode("a"),
        StringLiteralNode("b"),
        StringLiteralNode("c"),
      ]);

      var result = choice.acceptSimpleVisitor(visitor);
      expect(result, isA<ChoiceNode>());
    });
  });

  group("ReferencedVisitor", () {
    const visitor = ReferencedVisitor();

    test("extracts rule references", () {
      var reference = ReferenceNode("myRule");
      var result = reference.acceptSimpleVisitor(visitor).toList();

      expect(result, contains((Tag.rule, "myRule")));
    });

    test("extracts fragment references", () {
      var fragment = FragmentNode("myFragment");
      var result = fragment.acceptSimpleVisitor(visitor).toList();

      expect(result, contains((Tag.fragment, "myFragment")));
    });

    test("finds all references in sequence", () {
      var sequence = SequenceNode([
        ReferenceNode("rule1"),
        ReferenceNode("rule2"),
        FragmentNode("frag1"),
      ], chosenIndex: null);

      var result = sequence.acceptSimpleVisitor(visitor).toList();

      expect(result, contains((Tag.rule, "rule1")));
      expect(result, contains((Tag.rule, "rule2")));
      expect(result, contains((Tag.fragment, "frag1")));
    });

    test("finds references in choice", () {
      var choice = ChoiceNode([ReferenceNode("a"), ReferenceNode("b"), ReferenceNode("c")]);

      var result = choice.acceptSimpleVisitor(visitor).toList();

      expect(result, hasLength(3));
      expect(result.where((r) => r.$2 == "a"), isNotEmpty);
    });

    test("no references in string literal", () {
      var result = StringLiteralNode("hello").acceptSimpleVisitor(visitor).toList();
      expect(result, isEmpty);
    });
  });

  group("NodePrinterVisitor", () {
    const visitor = NodePrinterVisitor();

    test("prints string literals", () {
      var result = StringLiteralNode("hello").acceptSimpleVisitor(visitor);
      expect(result, contains("hello"));
    });

    test("prints epsilon", () {
      var result = EpsilonNode().acceptSimpleVisitor(visitor);
      expect(result, isNotEmpty);
    });

    test("prints any character", () {
      var result = AnyCharacterNode().acceptSimpleVisitor(visitor);
      expect(result, contains("."));
    });

    test("prints sequence", () {
      var sequence = SequenceNode([
        StringLiteralNode("a"),
        StringLiteralNode("b"),
      ], chosenIndex: null);

      var result = sequence.acceptSimpleVisitor(visitor);
      expect(result, contains("a"));
      expect(result, contains("b"));
    });

    test("prints choice", () {
      var choice = ChoiceNode([StringLiteralNode("a"), StringLiteralNode("b")]);

      var result = choice.acceptSimpleVisitor(visitor);
      expect(result, anyOf([contains("/"), contains("|")]));
    });
  });

  group("InlineVisitor", () {
    test("inlines single fragment reference", () {
      var visitor = InlineVisitor({"frag": (null, StringLiteralNode("x"))});

      var reference = FragmentNode("frag");
      var (changed, result) = reference.acceptSimpleVisitor(visitor);

      expect(changed, isTrue);
      expect(result, isA<StringLiteralNode>());
    });

    test("leaves non-inlineable fragments alone", () {
      var visitor = InlineVisitor({});
      var reference = FragmentNode("external");
      var (changed, result) = reference.acceptSimpleVisitor(visitor);

      expect(changed, isFalse);
      expect(result, isA<FragmentNode>());
    });

    test("inlines in sequence", () {
      var visitor = InlineVisitor({"a": (null, StringLiteralNode("A"))});

      var sequence = SequenceNode([FragmentNode("a"), StringLiteralNode("B")], chosenIndex: null);

      var (changed, result) = sequence.acceptSimpleVisitor(visitor);
      expect(changed, isTrue);
    });
  });
}
