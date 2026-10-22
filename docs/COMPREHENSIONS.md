# List Comprehensions (توليد القوائم) in Madar Core

Madar introduces Python-style **List Comprehensions** (`[expr for var in source (if cond)?]`) natively at the parser and bytecode virtual machine levels.

---

## 1. Overview & Syntax

A list comprehension provides a concise, expressive way to construct new lists by mapping, filtering, or combining elements of an iterable sequence (such as ranges, lists, or strings).

### General Grammar

```
"[" Expr ("for" | "dour") Identifier "in" SourceExpr [ "if" CondExpr ]* "]"
```

> **Note on `dour` (دُر):** In Madar, you can use the Arabic-derived native keyword `dour` interchangeably with `for` in list comprehensions (`[x*x dour x in 1:N]`). See [DOUR Loops Documentation](DOUR_LOOPS.md) for full details.

It can also feature multiple (nested) `for` / `dour` clauses:

```
"[" Expr ("for" | "dour") Var1 "in" Source1 [ "if" Cond1 ]* ("for" | "dour") Var2 "in" Source2 [ "if" Cond2 ]* ... "]"
```

---

## 2. Basic List Comprehensions

You can transform elements directly into a new list:

```ring
# Identity mapping from a range
nums = [x for x in 1:5]
# Result: [1, 2, 3, 4, 5]

# Arithmetic transformations
squares = [x * x for x in 1:5]
# Result: [1, 4, 9, 16, 25]

doubled = [x * 2 for x in 1:5]
# Result: [2, 4, 6, 8, 10]
```

---

## 3. Filtering with `if`

You can append an optional `if` condition to keep only elements satisfying a predicate:

```ring
# Filtering even numbers
evens = [x for x in 1:10 if x % 2 = 0]
# Result: [2, 4, 6, 8, 10]

# Filtering with conditions
gt_five = [x * 10 for x in 1:8 if x > 5]
# Result: [60, 70, 80]

# Multiple chained if clauses (all must be true)
mid = [x for x in 1:10 if x > 3 if x < 8]
# Result: [4, 5, 6, 7]

# Compound conditions using 'and' / 'or'
mid_and = [x for x in 1:10 if x > 3 and x < 8]
# Result: [4, 5, 6, 7]
```

If no elements meet the condition, an empty list `[]` is returned:

```ring
empty = [x for x in 1:5 if x > 100]
# Result: [] (len = 0)
```

---

## 4. Iterating Over Existing Lists & Strings

Comprehensions work seamlessly across any iterable collection:

```ring
# List of strings
names = ["alice", "bob", "charlie", "david"]
uppers = [upper(n) for n in names]
# Result: ["ALICE", "BOB", "CHARLIE", "DAVID"]

# Filtered strings
long_names = [n for n in names if len(n) > 4]
# Result: ["alice", "charlie"]

# Characters of a string
chars = [c for c in "madar"]
# Result: ["m", "a", "d", "a", "r"]
```

---

## 5. Function Calls & Complex Projections

The projection expression can be any valid Ring/Madar expression, including functions, pairs, dictionaries, or f-strings:

```ring
func double_num(n) { return n * 2 }
func is_even(n) { return (n % 2) = 0 }

# Function call in projection & condition
evens_doubled = [double_num(x) for x in 1:10 if is_even(x)]
# Result: [4, 8, 12, 16, 20]

# Constructing lists of sub-lists
pairs = [[x, x * 10] for x in 1:3]
# Result: [[1, 10], [2, 20], [3, 30]]

# Using f-strings
labels = [f"item_{x}" for x in 1:3]
# Result: ["item_1", "item_2", "item_3"]

# Dictionaries / hash maps
dicts = [[:id = x, :val = x * 2] for x in 1:2]
# Result: [[:id = 1, :val = 2], [:id = 2, :val = 4]]
```

---

## 6. Multi-Variable (Nested `for`) Comprehensions

You can specify multiple `for` clauses to generate Cartesian products or permutations:

```ring
# Cartesian product
cartesian = [x + y for x in [1, 2] for y in [10, 20]]
# Result: [11, 21, 12, 22]

# Multi-for with filter
diag = [x * y for x in 1:3 for y in 1:3 if x = y]
# Result: [1, 4, 9]
```

---

## 7. Nested Comprehensions (2D Matrices)

Comprehensions can be nested inside other comprehensions:

```ring
matrix = [[r * c for c in 1:3] for r in 1:3]
# Result:
# [
#   [1, 2, 3],
#   [2, 4, 6],
#   [3, 6, 9]
# ]
```

---

## 8. Multi-Line Formatting

Comprehensions support clean multi-line formatting across line boundaries:

```ring
data = [
    x * 3
    for x in 1:10
    if x > 3
    if x < 8
]
# Result: [12, 15, 18, 21]
```

---

## 9. Slicing with Comprehensions

Since list comprehensions are first-class expressions, you can directly slice them:

```ring
top_three = [x * 10 for x in 1:10][1:3]
# Result: [10, 20, 30]
```

---

## 10. Backward Compatibility

Standard Ring lists `[1, 2, 3]`, empty lists `[]`, and list operations remain 100% backward compatible without any performance impact.
