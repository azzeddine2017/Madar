# Advanced Slicing (التشريح المتقدم) in Madar Core

Madar introduces Python-style **Advanced Slicing** (`seq[start:stop:step]`) natively at the parser and bytecode virtual machine levels.

---

## 1. Syntax & Indexing Convention

Madar adopts **1-based inclusive indexing** for slicing, seamlessly preserving the native indexing rules of the Ring ecosystem and the range operator `1:3`:

- **1-based indexing:** The first element is at index `1`.
- **Inclusive range `[start:stop]`:** Both `start` and `stop` are included in the result.

```ring
s = "Hello World"
? s[1:5]    # "Hello" (Characters 1, 2, 3, 4, 5)

nums = [10, 20, 30, 40, 50]
? nums[1:3] # [10, 20, 30] (Items 1, 2, 3)
```

---

## 2. Omitting Bounds (`:`)

Any bound can be omitted:

- **`seq[:]`** : Full copy of the sequence (shallow copy for lists, duplicate for strings).
- **`seq[:stop]`** : From start (`1`) up to `stop`.
- **`seq[start:]`** : From `start` to the end of the sequence (`len(seq)`).

```ring
s = "Hello World"
? s[:5]   # "Hello"
? s[7:]   # "World"
? s[:]    # "Hello World"

nums = [10, 20, 30, 40, 50]
? nums[:2] # [10, 20]
? nums[3:] # [30, 40, 50]
```

---

## 3. Step / Stride (`step`)

You can specify a step interval by adding a second colon `:step`:

```ring
s = "Hello World"
? s[::2]     # "HloWrd"
? s[1:5:2]   # "Hlo"

nums = [10, 20, 30, 40, 50]
? nums[::2]     # [10, 30, 50]
? nums[1:5:2]   # [10, 30, 50]
```

---

## 4. Reverse Slicing (`step < 0`)

Negative steps allow traversing the sequence backwards, providing an instant idiom for reversing strings and lists:

```ring
s = "Hello World"
? s[::-1]     # "dlroW olleH"

nums = [10, 20, 30, 40, 50]
? nums[::-1]  # [50, 40, 30, 20, 10]

# Sub-slice in reverse:
? s[5:1:-1]   # "olleH"
```

When `step < 0`:
- Default `start` is the end of the sequence (`len(seq)`).
- Default `stop` is the beginning (`1`).

---

## 5. Negative Indexing

Madar supports negative indices both in **slices** and **single index lookups**:
- `-1` represents the last element (`len(seq)`).
- `-2` represents the second-to-last element (`len(seq) - 1`).

```ring
nums = [10, 20, 30, 40, 50]

# Single negative indexing:
? nums[-1]    # 50
? nums[-2]    # 40

# Negative index in slices:
? nums[-3:]   # [30, 40, 50]
? nums[1:-2]  # [10, 20, 30, 40]

s = "Hello World"
? s[-1]       # "d"
? s[-5:]      # "World"
```

---

## 6. Chained Slicing & Expressions

Slices can be chained or contain dynamic expressions:

```ring
# Expressions in slices:
a = 1
b = 3
? nums[a + 1 : b + 1] # [20, 30, 40]

# Chained slicing:
? "abcdefgh"[2:7][2:4] # "cd"
? nums[1:4][2:3]       # [20, 30]
```

---

## 7. 100% Backward Compatibility: Hash Lookups (`:symbol`)

In Ring, prefixing a single identifier with `:` denotes a string literal (e.g. `:name` is `"name"`), commonly used as hash map keys:

```ring
user = [
    :name = "Ali",
    :age = 25
]

# Fully preserved with zero conflict:
? user[:name] # "Ali"
? user[:age]  # 25
```

The Madar parser detects that `:name` followed immediately by `]` without a second colon is a single string literal lookup, preserving standard Ring code 100%.

---

## 8. Virtual Machine Architecture

1. **Opcode `ICO_SLICE` (`codegen.h`):**
   - Emitted by `ring_parser_mixer` when encountering slice syntax inside `[...]`.
   - Operand 1 encodes bit flags:
     - `RING_SLICE_HAS_START (1)`
     - `RING_SLICE_HAS_STOP  (2)`
     - `RING_SLICE_HAS_STEP  (4)`

2. **Execution Engine (`vmlists.c`):**
   - `ring_vm_slice(pVM)` pops operands (`step`, `stop`, `start`) according to the flags.
   - Inspects the target container (List, String, or Variable/Item pointer).
   - Normalizes bounds, negative indices, and clamps ranges safely.
   - Constructs and pushes a new sliced `List` (via `ring_vm_rangenewlist`) or `String` onto the VM stack.
