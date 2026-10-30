# Compiler Feedback Loop & Contextual Diagnostics in Madar (مدار)

Madar Runtime provides an enterprise-grade diagnostic engine designed for both human software engineers and autonomous AI Agents (such as **Code Gear-1**). It features machine-actionable RFC 8259 JSON error reporting via `--json-errors` and contextual exception inspection inside `try ... catch` blocks via `cCatchError`.

---

## 1. Machine-Actionable Diagnostics (`--json-errors`)

### Activation
The diagnostic engine can be enabled in three distinct ways:

1. **CLI Flag (Script Execution):**
   ```bash
   ring --json-errors my_script.ring
   ```
2. **CLI Flag (Inline Evaluation):**
   ```bash
   ring --json-errors -e "return (10 * 20 + - * - 5)"
   ```
3. **Environment Variable (CI/CD & Subprocess Agent Harnesses):**
   ```bash
   export MADAR_JSON_ERRORS=1
   # Or on Windows PowerShell:
   $env:MADAR_JSON_ERRORS="1"
   ```

---

### RFC 8259 JSON Error Schema

When an error occurs during token scanning, parsing, or runtime execution, Madar emits a strictly formatted JSON payload directly to `stdout`:

```json
{
  "madar_error": {
    "status": "error",
    "stage": "parser | scanner | runtime | environment",
    "error_code": "C27 | R1 | S1 | TENSOR_ERR ...",
    "message": "Human-readable error description with standard code",
    "file": "path/to/script.ring | eval | runstring",
    "line": 15,
    "column": 26,
    "offending_token": "*",
    "source_snippet": "x = a + b * - * - c",
    "visual_marker": "            ^",
    "hint": "Context-aware explanation of why the defect occurred.",
    "suggested_fix": "Concrete, actionable instruction to correct the issue.",
    "call_stack": [
      {
        "function": "processData",
        "file": "pipeline.ring",
        "line": 42
      }
    ]
  }
}
```

---

### Key Capabilities

#### 1. In-Memory & `eval()` Snippet Reconstruction
When code fails inside `eval()` or an in-memory buffer (such as mathematical expressions executed by AI agent tools), Madar reconstructs the source line directly from the active scanner tokens (`pTokens`). The `source_snippet` is never blank (`""`), ensuring LLM agents have full visual context.

#### 2. Exact Column & Visual Marker (`^`)
Madar computes the 1-based character column offset (`column`) of the token that triggered the grammar violation or exception, rendering an aligned ASCII visual marker (`visual_marker`: `^`) pointing directly to the defect.

#### 3. Granular Error Codes Matrix
Rather than collapsing all syntax issues into a generic `P1`, Madar maps 100% of errors to Ring 1.27 specifications:

- **Compiler Errors (`C1` - `C31`):**
  - `C1`: Error in parameter list
  - `C3`: Unclosed control structure (`ok` is missing)
  - `C4`: Unclosed block (`end` is missing)
  - `C5`: Unclosed loop (`next` is missing)
  - `C8`: Unclosed parenthesis `)`
  - `C9`: Unclosed bracket `]`
  - `C11`: Error in expression operator (consecutive operators, dangling operator)
  - `C14`: Try missing `catch`
  - `C17`: Switch missing `off`
  - `C18`: Missing closing brace `}`
  - `C22`: Duplicate function definition
  - `C26`: Duplicate class definition
  - `C27`: General syntax error
  - `C28`: Expected expression operand

- **Scanner Errors (`S1` - `S3`):**
  - `S1`: Literal string not closed
  - `S2`: Multi-line comment not closed
  - `S3`: Formatted f-string literal not closed

- **Runtime Errors (`R1` - `R55`):**
  - `R1`: Divide by zero
  - `R2`: Array access (Index out of range)
  - `R3`: Function not defined
  - `R4`: Stack Overflow (infinite recursion)
  - `R11`: Class not found
  - `R14`: Method not found
  - `R19`: Calling function with fewer parameters
  - `R24`: Using uninitialized variable (includes Levenshtein distance suggestion)
  - `R50`: Object does not support operator overloading

- **Environment & Memory Safety (`E1` - `E18`):**
  - `E1`: Segmentation fault (SIGSEGV)
  - `E2`: Out of Memory
  - `E9`: Cannot open file

- **Native Tensors & GGML Engine (`TENSOR_ERR`):**
  - Element-wise shape mismatches
  - GEMM matrix multiplication dimension misalignment
  - Index bounds violations

---

## 2. Contextual Exception Catching (`cCatchError`)

### The Problem in Legacy Runtimes
In standard implementations, `try ... catch` blocks only populates `cCatchError` with the raw exception string:
```
Error (R1) : Can't divide by zero
```
Developers and AI agents receiving this string had zero context regarding:
- Which line failed?
- Which file contained the failure?

### Madar's Enhanced `cCatchError`
Madar automatically enriches `cCatchError` at runtime in `ring_vm_catch`:
```ring
try {
    x = 10 / 0
catch
    ? cCatchError
}
```

**Output:**
```
Line 2 Error (R1) : Can't divide by zero in main.ring
```

#### Formatting Guarantee:
```
Line <LineNumber> <ErrorMessage> in <FileName>
```

#### 100% Backward Compatibility:
Legacy code checking error types via substring matching remains completely unbroken:
```ring
try {
    # Risky operation
catch
    if substr(cCatchError, "Error (R1)") {
        ? "Recovered from division by zero"
    }
}
```

---

## 3. Comparison (Before vs. After)

### Scenario: AI Agent Tool Execution with Syntax Defect
Expression evaluated:
```ring
eval("return (1450 * 32 + 890 - * - (1450 * 3) + (890) .)")
```

#### Legacy Output:
```
{
  "madar_error": {
    "status": "error",
    "stage": "parser",
    "error_code": "P1",
    "message": "Error (C27) : Syntax Error!",
    "file": "eval",
    "line": 1,
    "source_snippet": "",
    "hint": "Review the syntax and ensure all expressions and identifiers are valid.",
    "call_stack": []
  }
}
eval errors count : 2
(Repeated multiple times with plain text breaking JSON parsing)
```

#### Madar Modern Output:
```json
{
  "madar_error": {
    "status": "error",
    "stage": "parser",
    "error_code": "C27",
    "message": "Error (C27) : Syntax Error!",
    "file": "eval",
    "line": 1,
    "column": 26,
    "offending_token": "*",
    "source_snippet": "return (1450 * 32 + 890 - * - (1450 * 3 ) + (890 ) . )",
    "visual_marker": "                         ^",
    "hint": "Syntax error: unexpected token or malformed grammar rule that violates Ring syntax.",
    "suggested_fix": "Inspect the token indicated by '^' and ensure correct operator and operand placement.",
    "call_stack": []
  }
}
```
*(Zero text leakage, 100% RFC 8259 parseable, visual pointer, and source line reconstructed).*

