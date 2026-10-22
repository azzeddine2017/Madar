# Madar 'DOUR' Loops & Auto-JIT Engine

The **`dour`** keyword is an exclusive high-performance innovation in **Madar**, engineered as an accelerated alternative to traditional `for` loops. It unlocks transparent, on-the-fly **Auto-JIT (Just-In-Time) native machine code compilation** via **SLJIT**, delivering execution speeds comparable to compiled C.

---

## 1. Why `dour` Was the Solution

In traditional interpreted environments, developers often face an architectural trade-off:
1. **Strict Backward Compatibility:** Preserving standard virtual machine semantics to guarantee existing codebases and test suites execute without regression.
2. **Maximum Hardware Performance:** Executing tight numerical loops, reductions, and arithmetic algorithms at bare-metal CPU speeds.

**`dour`** resolves this dilemma with an opt-in dual execution model:
- **`for`**: Executes through the standard bytecode interpreter, maintaining 100% Ring compatibility.
- **`dour`**: Instructs the compiler to emit a specialized opcode flag (`lIsDour = 1`). At runtime, the VM engages the **Madar Auto-JIT Engine**, compiles the loop into native machine instructions (`x86_64` / `ARM64`) in executable memory, and executes directly on the processor.

---

## 2. Syntax & Usage

The `dour` keyword shares the familiar, clean loop syntax of `for`:

### A. Numerical Range Loops

```ring
# Sum of squares computed natively with Auto-JIT
nSum = 0
dour x = 1 to 1000000
    nSum += (x * x)
next

see "Sum = " + nSum + nl
```

Full support for step increments:
```ring
dour i = 10 to 1 step -1
    see i + nl
next
```

### B. High-Speed List Comprehensions

`dour` can be used interchangeably with `for` inside list comprehensions:

```ring
# List comprehension powered by dour
squares = [x * x dour x in 1:10000]

# List comprehension with filtering
evens = [x * 2 dour x in 1:5000 if x % 2 = 0]
```

---

## 3. Technical Architecture & Execution Pipeline

```
       +-----------------------+
       |   Source Code         |
       |  "dour x = 1 to N"    |
       +-----------+-----------+
                   |
            (Lexer / Parser)
                   |
                   v
       +-----------------------+
       | Token: K_DOUR         |
       | Emit: ICO_JUMPFOR     |
       | Operand[1] = 1 (DOUR) |
       +-----------+-----------+
                   |
           (VM Execution)
                   |
                   v
    +-----------------------------+
    | ring_vm_jumpfor:            |
    | Is lIsDour == 1?            |
    +--------------+--------------+
                   |
          YES      |      NO
         +---------+---------+
         |                   |
         v                   v
+------------------+  +-------------------+
|  Madar Auto-JIT  |  | Standard Ring VM  |
|  Compile Native  |  | Bytecode Loop     |
|  Machine Code    |  | Interpreter       |
|  (SLJIT Engine)  |  +-------------------+
+------------------+
```

1. **Compilation Phase (`language/src/stmt.c`):**
   When `ring_parser_iskeyword(pParser, K_DOUR)` matches, the parser sets `lIsDour = 1` and appends an integer flag operand `1` to `ICO_JUMPFOR`.
2. **Virtual Machine Dispatch (`language/src/vmjump.c`):**
   `ring_vm_jumpfor` inspects operand 2. If `lIsDour == 1`, step is unit (`1.0`), and range length exceeds the threshold ($\ge 50$), it invokes:
   ```c
   ring_jit_try_execute_for_loop(pVM, nStart, nEnd, nStep, nExitPC);
   ```
3. **Machine Code Generation (`language/src/ring_jit.c` via SLJIT):**
   The engine generates native CPU instructions for accumulator registers, loop conditions, and arithmetic operations, executes the native routine in executable memory, updates the VM state upon completion, and advances the instruction pointer directly to `nExitPC`.

---

## 4. Benchmark Performance Comparison

Measured using the official project benchmark suite (`tests/test_loop_speed.ring`) for $N = 20,000$ iterations:

| Loop Pattern / Technique | Execution Mode | Elapsed Time | Speed Multiplier |
| :--- | :--- | :--- | :--- |
| **Standard Ring `for`** | Bytecode Interpreter | **~14.5 ms** | 1x (Baseline) |
| **Standard `while` loop** | Bytecode Interpreter | **~18.2 ms** | 0.8x |
| **Madar `dour` Loop** | **Auto-JIT (Native CPU Code)** | **~2.1 ms** | **~7x faster** |
| **Native SLJIT Kernel** | Handcrafted Native Kernel | **~0.15 ms** | **~90x faster** |

---

## 5. Runtime Introspection APIs

Madar provides built-in functions to verify JIT availability and monitor acceleration metrics:

```ring
# Verify JIT engine status on host architecture
if jit_available()
    see "Madar JIT Engine is ACTIVE!" + nl
ok

# Check count of loops natively executed by Auto-JIT
dour x = 1 to 50000
    s += x
next
see "Total JIT loops executed: " + jit_autoloops() + nl
```

---

## 6. Summary

The introduction of **`dour`** provides a clean, principled solution for loop performance in Madar:
- Grants developers explicit control: standard interpreted compatibility with `for`, or bare-metal execution with `dour`.
- Accelerates numerical computing, machine learning, data processing, and list comprehensions without breaking existing ecosystem code.
