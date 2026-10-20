# Formatted String Literals (f-strings) in Madar Core

Madar introduces Python-style formatted string literals (`f-strings`) natively at the Scanner and Lexer level. This feature enables intuitive expression interpolation inside string literals without runtime overhead or external libraries.

---

## 1. Syntax Overview

An `f-string` is defined by prefixing a string literal with `f` or `F` immediately before the opening quote:

```ring
# Double quotes
s1 = f"Hello {name}, your score is {score}!"

# Single quotes
s2 = f'User ID: {user_id}'

# Backticks
s3 = f`Path: {base_dir}/models`
```

Any valid Madar expression can be placed inside curly braces `{ ... }`:
- Variables: `f"{name}"`
- Arithmetic: `f"1 + 2 = {1 + 2}"`
- Expressions with precedence: `f"Result: {a * (b + c)}"`
- Function calls: `f"Length: {len(str)}"`
- List / Hash lookups: `f"Author: {book[:author]}"`
- Method calls: `f"Status: {obj.getStatus()}"`

---

## 2. Escaping Braces

To include a literal curly brace `{` or `}` inside an `f-string`, you can use either:

1. **Doubled Braces (Python style):**
   ```ring
   s = f"JSON template: {{ \"key\": \"{val}\" }}"
   # Output: JSON template: { "key": "value" }
   ```

2. **Backslash Escaping:**
   ```ring
   s = f"Literal \{brace\} with variable {val}"
   # Output: Literal {brace} with variable value
   ```

---

## 3. Nested f-strings

Madar supports up to 8 levels of nested `f-strings`:

```ring
status = "ready"
code = 200
msg = f"System Report: { f'Status is {status} (HTTP {code})' }"
see msg # System Report: Status is ready (HTTP 200)
```

---

## 4. Under the Hood: Scanner-Level Desugaring

Unlike higher-level interpreters that use regex or runtime `eval()`, Madar's `f-strings` are desugared directly at tokenization time into standard AST expression tokens:

An f-string like:
```ring
f"Count: {x}, Next: {x + 1}."
```

Is transformed by the scanner into the grouped token stream:
```ring
( "" + "Count: " + (x) + ", Next: " + (x + 1) + "." )
```

### Advantages of this Architecture:
1. **Zero Runtime Overhead:** No string formatting parser or runtime regex at execution time.
2. **Standard Operator Precedence:** The outer `( ... )` ensures the entire `f-string` behaves as a self-contained primary factor in expressions, conditions, and function arguments.
3. **Automatic Type Coercion:** Ring's VM addition operator automatically converts numbers and booleans into strings when concatenated with a string on the left operand.
4. **100% Backward Compatibility:** Standard string literals (`"..."`, `'...'`, `` `...` ``) remain completely unaffected.

---

## 5. Examples

```ring
# Simple greeting
name = "Madar"
see f"Welcome to {name}!" + nl

# Arithmetic calculations
price = 150
tax = 0.19
see f"Total price: {price * (1 + tax)} DZD" + nl

# Conditional statements
user = "admin"
if f"user_{user}" = "user_admin"
    see "Access granted." + nl
ok
```
