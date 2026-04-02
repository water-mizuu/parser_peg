# parser_peg

A powerful **PEG-based Parser Generator** for Dart, designed to generate fast, accurate parsing code directly from grammar specifications.

Inspired by [Peggy.js](https://github.com/peggyjs/peggy.git) and [Python Pegen](https://github.com/we-like-parsers/pegen).

## Overview

`parser_peg` is a parser generator that transforms `.dart_grammar` files into optimized Dart parsing code. It leverages **Parsing Expression Grammars (PEGs)** to define language syntax and automatically generates parsers with support for:

- **Multiple output formats**: AST (Abstract Syntax Tree), CST (Concrete Syntax Tree), and analyzed parsers
- **Code generation**: Direct Dart code generation with optimization
- **Visitor pattern**: Support for both simple and parametrized visitors to traverse and transform parse trees
- **Grammar composition**: Import and reuse grammar rules across multiple files
- **Named scopes**: Organize rules into hierarchical namespaces
- **Action expressions**: Embed Dart code within grammar rules for semantic actions
- **Advanced optimization**: Dead code elimination, rule inlining, and cut handling

## Installation

### Prerequisites

- Dart SDK >=3.11.0

### Setup

1. Clone the repository:

   ```bash
   git clone <repository-url>
   cd parser_peg
   ```

2. Install dependencies:

   ```bash
   dart pub get
   ```

3. Build the executable:
   ```bash
   dart compile aot-snapshot bin/parser_peg.dart -o bin/parser_peg.aot
   ```

## Quick Start

### Create a Grammar File

Create a file named `math.dart_grammar`:

```
{
import "dart:math" as math show pow;
}

rule = ^ _ :expr _ $ { expr };

expr =
  | :expr _ "+" _ :term { expr + term }
  | :expr _ "-" _ :term { expr - term }
  | term;

term =
  | "-" _ :term            { -term }
  | :term _ "*" _ :factor  { term * factor }
  | factor;

factor = "(" _ :expr _ ")" { expr } | number;

@fragment
number = \d+ { int.parse(buffer.substring(from, to)) };

_ = \s* { () };
```

### Generate Parser

```bash
# Generate analyzed parser
dart bin/parser_peg.dart math.dart_grammar --name MathParser

# Generate all output formats (AST, CST, and analyzed)
dart bin/parser_peg.dart math.dart_grammar --output math_parser.dart --name MathParser complete
```

### Use the Generated Parser

```dart
import 'math_parser.dart';

void main() {
  var parser = MathParser();
  var result = parser.parse("2 + 3 * 4");
  print(result); // Output: 14
}
```

## Grammar Syntax

### Basic Elements

- **Literal strings**: `"hello"` matches the exact string
- **Character classes**: `\d` (digits), `\w` (word chars), `\s` (whitespace)
- **Quantifiers**:
  - `*` (zero or more)
  - `+` (one or more)
  - `?` (optional)
- **Alternation**: `|` chooses one of multiple options
- **Grouping**: `( ... )` for grouping expressions
- **Anchors**: `^` (start of input), `$` (end of input)

### Named Rules

```
identifier = [a-zA-Z_][a-zA-Z0-9_]*;
number = \d+;
```

### Named Captures

Use `:name` to capture matched content:

```
rule = :left "+" :right { left + right };
```

### Action Expressions

Embed Dart code to transform matched content:

```
number = \d+ { int.parse(buffer.substring(from, to)) };
value = "true" { true } | "false" { false };
```

### Fragments

Mark rules as fragments (not memoized):

```
@fragment
spacing = \s*;
```

### Grammar Imports

Compose grammars by importing other grammar files:

```
import "numbers.dart_grammar" as num;
import "operators.dart_grammar";

expr = :left _ operator.plus _ :right { left + right };
```

### Named Scopes

Organize rules hierarchically:

```
expression {
  add = :a "+" :b { a + b };
  mul = :a "*" :b { a * b };
}

top_level = expression.add;
```

## Project Structure

```
lib/src/
├── base.dart                 # Core base classes
├── generator.dart            # Parser code generator
├── node.dart                 # AST node definitions
├── statement.dart            # Grammar statements
├── parser/
│   ├── grammar_parser.dart   # Grammar syntax parser
│   ├── grammar_parser.cst.dart  # CST parser
│   └── grammar_parser.ast.dart  # AST parser
└── visitor/
    ├── node_visitor/         # Tree traversal visitors
    └── statement_visitor/    # Grammar statement processors

examples/                      # Example grammars and usage
test/                         # Unit and integration tests
```

## Commands

### Generate Analyzed Parser (Default)

```bash
dart bin/parser_peg.dart <input.dart_grammar> -o <output.dart> -n <ParserName>
```

**Options:**

- `-o, --output`: Output file path (default: same directory, `.dart` extension)
- `-n, --name`: Generated parser class name (default: PascalCase of filename)

### Generate All Parser Types

```bash
dart bin/parser_peg.dart <input.dart_grammar> --output <output.dart> complete
```

Generates three files:

- `<output>.dart` - Analyzed parser
- `<output>.ast.dart` - AST parser
- `<output>.cst.dart` - CST parser

## Examples

See the [examples/](examples/) directory for complete working examples:

- **math/**: Simple arithmetic expression calculator
- **importing/**: Grammar composition across multiple files
- **importing_2/**: Advanced multi-file grammar patterns
- **playground/**: Experimental features and patterns

## Contributing

Contributions are welcome! Please ensure:

1. All tests pass: `dart test`
2. Code follows Dart style guide
3. New features include tests
4. Grammar examples are documented

## License

[Add license information]
