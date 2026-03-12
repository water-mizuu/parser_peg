// ignore_for_file: always_put_control_body_on_new_line

import "package:parser_peg/src/node.dart";
import "package:parser_peg/src/visitor/node_visitor.dart";

/// Determines whether a specific rule is (directly or indirectly) left-recursive.
///
/// A rule is left-recursive if it can invoke itself as the very first action
/// before consuming any input. This includes:
///   - Direct: `a = a 'x' | 'x'`
///   - Indirect: `a = b; b = a 'x' | 'x'`
///   - Through nullable prefixes: `a = ε a | 'x'`
///
/// [targetRule] is the rule name being tested. Any reference back to it
/// encountered in first position returns true.
///
/// [_visiting] tracks rules currently on the traversal stack. A cycle that
/// does not pass through [targetRule] returns false — it's someone else's
/// left recursion, not ours.
class IsLeftRecursiveVisitor implements SimpleNodeVisitor<bool> {
  IsLeftRecursiveVisitor(this.targetRule, this.rules, this.fragments, this.inline);

  bool isLeftRecursive(Node node) => node.acceptSimpleVisitor(this);

  final String targetRule;
  final Set<String> _visiting = {};
  final Map<String, (String?, Node)> rules;
  final Map<String, (String?, Node)> fragments;
  final Map<String, (String?, Node)> inline;

  // ── Terminals ─────────────────────────────────────────────────────────────

  @override
  bool visitCutNode(CutNode node) => false;

  @override
  bool visitEpsilonNode(EpsilonNode node) => false;

  @override
  bool visitTriePatternNode(TriePatternNode node) => false;

  @override
  bool visitStringLiteralNode(StringLiteralNode node) => false;

  @override
  bool visitRangeNode(RangeNode node) => false;

  @override
  bool visitRegExpNode(RegExpNode node) => false;

  @override
  bool visitRegExpEscapeNode(RegExpEscapeNode node) => false;

  @override
  bool visitStartOfInputNode(StartOfInputNode node) => false;

  @override
  bool visitEndOfInputNode(EndOfInputNode node) => false;

  @override
  bool visitAnyCharacterNode(AnyCharacterNode node) => false;

  // ── Composites ────────────────────────────────────────────────────────────

  @override
  bool visitSequenceNode(SequenceNode node) {
    // Walk the sequence left-to-right. A child in position i can only
    // introduce left recursion if all children before it are nullable
    // (i.e. they can be skipped without consuming input).
    for (var child in node.children) {
      if (child.acceptSimpleVisitor(this)) return true;
      if (!child.isNullable(this)) break;
    }
    return false;
  }

  @override
  bool visitChoiceNode(ChoiceNode node) =>
      node.children.any((child) => child.acceptSimpleVisitor(this));

  // ── Quantifiers ───────────────────────────────────────────────────────────

  @override
  bool visitCountedNode(CountedNode node) => node.child.acceptSimpleVisitor<bool>(this);

  @override
  bool visitPlusSeparatedNode(PlusSeparatedNode node) => node.child.acceptSimpleVisitor<bool>(this);

  @override
  bool visitStarSeparatedNode(StarSeparatedNode node) => node.child.acceptSimpleVisitor<bool>(this);

  @override
  bool visitPlusNode(PlusNode node) => node.child.acceptSimpleVisitor<bool>(this);

  @override
  bool visitStarNode(StarNode node) => node.child.acceptSimpleVisitor<bool>(this);

  @override
  bool visitOptionalNode(OptionalNode node) => node.child.acceptSimpleVisitor<bool>(this);

  // ── Predicates & wrappers ─────────────────────────────────────────────────

  @override
  bool visitAndPredicateNode(AndPredicateNode node) => node.child.acceptSimpleVisitor<bool>(this);

  @override
  bool visitNotPredicateNode(NotPredicateNode node) => node.child.acceptSimpleVisitor<bool>(this);

  @override
  bool visitExceptNode(ExceptNode node) => node.child.acceptSimpleVisitor<bool>(this);

  @override
  bool visitNamedNode(NamedNode node) => node.child.acceptSimpleVisitor<bool>(this);

  @override
  bool visitActionNode(ActionNode node) => node.child.acceptSimpleVisitor<bool>(this);

  @override
  bool visitInlineActionNode(InlineActionNode node) => node.child.acceptSimpleVisitor<bool>(this);

  // ── References ────────────────────────────────────────────────────────────

  @override
  bool visitReferenceNode(ReferenceNode node) {
    // Found the target rule in first position — this is a left-recursive path.
    if (node.ruleName == targetRule) return true;

    // Already visiting this rule on the current stack — it's a cycle that
    // doesn't involve targetRule, so it contributes no left recursion to us.
    if (!_visiting.add(node.ruleName)) return false;

    var body = rules[node.ruleName]?.$2;
    var result = body?.acceptSimpleVisitor<bool>(this) ?? false;

    _visiting.remove(node.ruleName);
    return result;
  }

  @override
  bool visitFragmentNode(FragmentNode node) {
    if (node.fragmentName == targetRule) return true;

    if (!_visiting.add(node.fragmentName)) return false;

    var body = fragments[node.fragmentName]?.$2 ?? inline[node.fragmentName]?.$2;
    var result = body?.acceptSimpleVisitor<bool>(this) ?? false;

    _visiting.remove(node.fragmentName);
    return result;
  }
}

/// A visitor that determines whether a given [Node] (and its entire subtree)
/// can be safely inlined at every call site.
///
/// A node is considered inlineable when it contains no unresolvable or
/// structurally complex references that would prevent code deduplication.
/// Atomic nodes (literals, ranges, regexp escapes, etc.) are always
/// inlineable. Composite nodes are inlineable only when every child is
/// inlineable. Rule and fragment references are inlineable when the rule
/// or fragment they resolve to is itself inlineable.
///
/// Results are memoised in an [_cache] [Expando] to avoid redundant
/// traversals, especially important for recursive or shared rule graphs.
class _IsNullableVisitor implements SimpleNodeVisitor<bool> {
  _IsNullableVisitor(this.rules, this.fragments, this.inline);

  final Expando<bool> _cache = Expando<bool>();
  final Map<String, (String?, Node)> rules;
  final Map<String, (String?, Node)> fragments;
  final Map<String, (String?, Node)> inline;

  @override
  bool visitCutNode(CutNode node) {
    return true;
  }

  @override
  bool visitEpsilonNode(EpsilonNode node) {
    return true;
  }

  @override
  bool visitTriePatternNode(TriePatternNode node) {
    if (_cache[node] case bool b) return b;

    return _cache[node] = node.options.isEmpty || node.options.any((o) => o.isEmpty);
  }

  @override
  bool visitStringLiteralNode(StringLiteralNode node) {
    if (_cache[node] case bool b) return b;

    return _cache[node] = node.literal.isEmpty;
  }

  @override
  bool visitRangeNode(RangeNode node) {
    if (_cache[node] case bool b) return b;

    return _cache[node] = false;
  }

  @override
  bool visitRegExpNode(RegExpNode node) {
    if (_cache[node] case bool b) return b;

    return _cache[node] = RegExp(node.value).hasMatch("");
  }

  @override
  bool visitRegExpEscapeNode(RegExpEscapeNode node) {
    if (_cache[node] case bool b) return b;

    return _cache[node] = RegExp(node.pattern).hasMatch("");
  }

  @override
  bool visitSequenceNode(SequenceNode node) {
    if (_cache[node] case bool b) return b;
    _cache[node] = true;
    return _cache[node] = node.children.every((child) => child.acceptSimpleVisitor<bool>(this));
  }

  @override
  bool visitChoiceNode(ChoiceNode node) {
    if (_cache[node] case bool b) return b;
    _cache[node] = false;
    return _cache[node] = node.children.any((child) => child.acceptSimpleVisitor<bool>(this));
  }

  @override
  bool visitCountedNode(CountedNode node) {
    if (_cache[node] case bool b) return b;

    return _cache[node] = node.min == 0 || node.child.acceptSimpleVisitor<bool>(this);
  }

  @override
  bool visitPlusSeparatedNode(PlusSeparatedNode node) {
    if (_cache[node] case bool b) return b;

    return _cache[node] = node.child.acceptSimpleVisitor<bool>(this);
  }

  @override
  bool visitStarSeparatedNode(StarSeparatedNode node) {
    if (_cache[node] case bool b) return b;

    return _cache[node] = true;
  }

  @override
  bool visitPlusNode(PlusNode node) {
    if (_cache[node] case bool b) return b;

    return _cache[node] = node.child.acceptSimpleVisitor<bool>(this);
  }

  @override
  bool visitStarNode(StarNode node) {
    if (_cache[node] case bool b) return b;

    return _cache[node] = true;
  }

  @override
  bool visitAndPredicateNode(AndPredicateNode node) {
    if (_cache[node] case bool b) return b;

    return _cache[node] = true;
  }

  @override
  bool visitNotPredicateNode(NotPredicateNode node) {
    if (_cache[node] case bool b) return b;

    return _cache[node] = true;
  }

  @override
  bool visitOptionalNode(OptionalNode node) {
    if (_cache[node] case bool b) return b;

    return _cache[node] = true;
  }

  @override
  bool visitExceptNode(ExceptNode node) {
    if (_cache[node] case bool b) return b;

    return _cache[node] = node.child.acceptSimpleVisitor<bool>(this);
  }

  @override
  bool visitReferenceNode(ReferenceNode node) {
    // Return early if this specific reference node has already been evaluated.
    if (_cache[node] case bool b) return b;

    var (_, resolvedNode) = rules[node.ruleName]!;

    return _cache[node] = resolvedNode.acceptSimpleVisitor<bool>(this);
  }

  @override
  bool visitFragmentNode(FragmentNode node) {
    // Return early if this specific reference node has already been evaluated.
    if (_cache[node] case bool b) return b;
    var (_, resolvedNode) = fragments[node.fragmentName] ?? inline[node.fragmentName]!;

    return _cache[node] = resolvedNode.acceptSimpleVisitor<bool>(this);
  }

  @override
  bool visitNamedNode(NamedNode node) {
    if (_cache[node] case bool b) return b;

    return _cache[node] = node.child.acceptSimpleVisitor<bool>(this);
  }

  @override
  bool visitActionNode(ActionNode node) {
    if (_cache[node] case bool b) return b;

    return _cache[node] = node.child.acceptSimpleVisitor<bool>(this);
  }

  @override
  bool visitInlineActionNode(InlineActionNode node) {
    if (_cache[node] case bool b) return b;

    return _cache[node] = node.child.acceptSimpleVisitor<bool>(this);
  }

  @override
  bool visitStartOfInputNode(StartOfInputNode node) {
    if (_cache[node] case bool b) return b;

    return _cache[node] = true;
  }

  @override
  bool visitEndOfInputNode(EndOfInputNode node) {
    if (_cache[node] case bool b) return b;

    return _cache[node] = true;
  }

  @override
  bool visitAnyCharacterNode(AnyCharacterNode node) {
    if (_cache[node] case bool b) return b;

    return _cache[node] = false;
  }
}

extension on Node {
  bool isNullable(IsLeftRecursiveVisitor visitor) =>
      acceptSimpleVisitor(_IsNullableVisitor(visitor.rules, visitor.fragments, visitor.inline));
}
