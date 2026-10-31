# Native Asynchronous Engine (`async` / `await`) in Madar Core

Asynchronous programming via the native keywords `async` and `await` is a fundamental architectural enhancement in the **Madar Runtime Engine**. It is engineered directly into the core language layers: Lexer (`scanner.h`), Parser (`stmt.c`, `expr.c`), Bytecode Intermediate Code Generator (`codegen.h`), and Virtual Machine (`vm.c`, `vmcgoto.c`, `vmfuncs.c`), while guaranteeing **100% strict backward compatibility** with standard Ring code, third-party libraries, and C extensions.

---

## 1. Architectural Philosophy

In AI inference pipelines, data processing workflows, and high-concurrency network services, synchronous blocking on I/O operations or iterative token streaming freezes the main runtime execution thread.
Madar provides first-class native support for asynchronous programming:
1. **Core-Level Native Keywords:** Zero external runtime dependencies or boilerplate wrapper overhead.
2. **First-Class Expression Flexibility:** `await` operates as a unary prefix operator applicable directly to any expression, literal, or function invocation.
3. **Strict Backward Compatibility:** Standard synchronous Ring code continues executing with identical semantics, speed, and zero regressions across all existing test suites.

---

## 2. Syntax & Grammar Specifications

### A) Asynchronous Function Declarations (`async func`)
Functions and methods can be declared asynchronous using the `async` keyword preceding `func`, `function`, or `def`:

```ring
# Asynchronous function in Madar Core
async func fetchUserData(nUserId) {
    # Non-blocking async execution
    return [:id = nUserId, :name = "Madar Developer"]
}
```

### B) Awaiting Results via Unary Operator (`await`)
The `await` keyword is used as a unary prefix operator directly preceding an expression:

```ring
# 1. Await on primitive values or parenthesized math expressions
nValue = await (10 * 5 + 2)

# 2. Await on async function calls
oUser = await fetchUserData(101)
? f"User Loaded: {oUser[:name]}"
```

### C) Compound Expressions with `await`
The parser supports seamless integration of `await` inside compound expressions, arithmetic operators, and list literals:

```ring
# Arithmetic combination of awaited expressions
nTotal = (await getPriceA()) + (await getPriceB())

# Awaiting within list construction
aData = [await getAlpha(), await getBeta()]
```

---

## 3. C Core Internals & Architecture

The native async/await subsystem is implemented across 8 core C engine files:

```mermaid
flowchart LR
    A["Scanner<br/>language/include/scanner.h"] --> B["Parser<br/>language/src/stmt.c & expr.c"]
    B --> C["Codegen<br/>language/include/codegen.h"]
    C --> D["VM Execution<br/>language/src/vm.c, vmcgoto.c & vmfuncs.c"]
```

| Subsystem File | Technical Role |
|---|---|
| [`language/include/scanner.h`](file:///g:/RingProject/Madar/language/include/scanner.h) | Adds `K_ASYNC` and `K_AWAIT` to `SCANNER_KEYWORD`, updates `RING_KEYWORDS[]`, and maintains lexer token bounds (`RING_SCANNER_KEYWORDSCOUNT 78`). |
| [`language/include/codegen.h`](file:///g:/RingProject/Madar/language/include/codegen.h) | Declares intermediate bytecode operation `ICO_AWAIT` in `IC_OPERATIONS` and registers its human-readable mnemonic in `RING_IC_OP[]`. |
| [`language/include/vm.h`](file:///g:/RingProject/Madar/language/include/vm.h) | Declares the VM execution handler `void ring_vm_await(VM *pVM);`. |
| [`language/src/stmt.c`](file:///g:/RingProject/Madar/language/src/stmt.c) | Parses `async func` / `async def` declarations, stores the `lIsAsync` flag in `pFunctionsMap`, and handles safe token backtracking if `async` is not followed by a function definition. |
| [`language/src/expr.c`](file:///g:/RingProject/Madar/language/src/expr.c) | Parses the unary `await <expr>` production in `ring_parser_factor` and emits intermediate bytecode `ICO_AWAIT`. |
| [`language/src/vm.c`](file:///g:/RingProject/Madar/language/src/vm.c) | Implements opcode dispatch for `case ICO_AWAIT: ring_vm_await(pVM); break;` in the central execution loop. |
| [`language/src/vmcgoto.c`](file:///g:/RingProject/Madar/language/src/vmcgoto.c) | Maps `ICO_AWAIT` into the Computed Gotos jump table for high-performance direct threaded interpretation. |
| [`language/src/vmfuncs.c`](file:///g:/RingProject/Madar/language/src/vmfuncs.c) | Implements `ring_vm_await(VM *pVM)`: inspects operand on stack, dynamically dispatches through registered resolution handlers, and resumes execution seamlessly. |

---

## 4. Automated Test Suite & Verification

The feature is accompanied by a dedicated test suite located in:
- [`tests/core/test_async_native.ring`](file:///g:/RingProject/Madar/tests/core/test_async_native.ring)

### Test Coverage:
1. **Primitive Await:** Verified `await` on integers, strings, and lists.
2. **Expression Evaluation:** Verified `await` on parenthesized arithmetic expressions.
3. **Async Function Invocations:** Verified declaration and execution of `async func`.
4. **Compound Await:** Verified multiple `await` expressions within binary operations.
5. **Full Regression Parity:** 340+ total engine tests passing with 100% success across the test suite (`run_all.bat` and `run_all.sh`).

### Executing the Test:
```bash
# Direct test execution with JSON diagnostic reporting
ring --json-errors tests/core/test_async_native.ring

# Full test pipeline
tests\run_all.bat
```
