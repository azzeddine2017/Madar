# Default Arguments (القيم الافتراضية للمعاملات) in Madar Core

Madar natively supports Python-style **Default Arguments** in function, method, and anonymous function signatures.

---

## 1. Syntax Overview

You can define default values for any parameters by appending `= <Expression>` in the function parameter list:

```ring
# Using 'func'
func connect(host, port = 8080, timeout = 30)
    ? f"Connecting to {host}:{port} with timeout {timeout}s"

# Using 'def' (Python style)
def greet(name, greeting = "Hello", punctuation = "!")
    return greeting + " " + name + punctuation
```

### Supported Invocations:
```ring
connect("localhost")                  # port=8080, timeout=30
connect("api.example.com", 443)       # port=443,  timeout=30
connect("api.example.com", 443, 60)   # port=443,  timeout=60
```

---

## 2. All Arguments Defaulted (Zero-Argument Functions)

If all parameters have default values, the function can be invoked with zero arguments:

```ring
func make_user(name = "guest", role = "viewer")
    return [ :name = name, :role = role ]

u1 = make_user()             # [ :name = "guest", :role = "viewer" ]
u2 = make_user("admin")      # [ :name = "admin", :role = "viewer" ]
u3 = make_user("root", "su") # [ :name = "root", :role = "su" ]
```

---

## 3. Dynamic Runtime Evaluation (No Mutable Default Bug!)

In Python, default arguments are evaluated once at definition time, causing the famous shared mutable default bug:
```python
# In Python - BUG!
def append_item(x, lst=[]):
    lst.append(x)
    return lst
# append_item(1) -> [1]
# append_item(2) -> [1, 2] (Shared state!)
```

In **Madar**, default value expressions are evaluated **dynamically at call time** inside the function scope when the argument is omitted:

```ring
# In Madar - Clean & Safe!
func append_item(x, lst = [])
    add(lst, x)
    return lst

? append_item(1)  # [1]
? append_item(2)  # [2] (Fresh new list created each call!)
```

---

## 4. Referencing Preceding Parameters

Because default expressions evaluate dynamically at runtime after prior parameters are bound, later defaults can reference earlier parameters:

```ring
func calc_box(width, height = width, depth = 1)
    return width * height * depth

? calc_box(5)       # 5 * 5 * 1 = 25 (Square base)
? calc_box(5, 10)   # 5 * 10 * 1 = 50 (Rectangle base)
```

---

## 5. Anonymous Functions & Methods

Default arguments work seamlessly with anonymous functions and class methods:

### Anonymous Functions:
```ring
f = func(x, scale = 2, offset = 10) {
    return (x * scale) + offset
}

? call f(5)       # (5 * 2) + 10 = 20
? call f(5, 4)    # (5 * 4) + 10 = 30
```

### Class Methods:
```ring
client = new RequestClient
client.fetch("https://madar.org")

class RequestClient
    func fetch(url, retries = 3, secure = 1)
        ? f"Fetching {url} (Retries: {retries}, Secure: {secure})"
```

---

## 6. Argument Introspection: `argcount()` / `paramcount()`

Madar provides built-in reflection functions to determine the exact number of actual arguments supplied by the caller:

```ring
handle(1)       # Actual arguments passed: 1
handle(1, 2)    # Actual arguments passed: 2
handle(1, 2, 3) # Actual arguments passed: 3

func handle(a, b = 10, c = 20)
    ? f"Actual arguments passed: {argcount()}"
```

- `argcount()`: Returns the number of arguments supplied at the call site.
- `paramcount()`: Equivalent alias for `argcount()`.

---

## 7. Syntax & Validation Rules

1. **Ordering Rule:** Just like in Python, a non-default parameter cannot follow a parameter with a default value:
   ```ring
   func bad(a = 10, b)  # Compile-time error: Non-default parameter follows default parameter
   ```

2. **Minimum Arity Enforcement:** Calling a function with fewer arguments than required (minimum non-default arguments) results in `RING_VM_ERROR_LESSPARAMETERSCOUNT`:
   ```ring
   func need_two(a, b, c = 10)
   need_two(1)  # Error: Less than required parameters!
   ```

---

## 8. Virtual Machine Architecture

The feature is implemented in standard C99 with zero overhead on existing non-default functions:

1. **Intermediate Code Generation (`stmt.c`):**
   - When parsing default parameters, the parser emits:
     ```
     ICO_CHECKARG (reg1 = JumpLabel, reg2 = ParamIndex)
     [Load Address of Parameter]
     [Evaluate Default Expression]
     [ICO_ASSIGNMENT]
     [ICO_FREESTACK]
     JumpLabel:
     ```
   - `ICO_NEWFUNC` stores `nMinParaCount + 1` in `pByteCodeIR->nIntReg`.

2. **Function Entry Execution (`vmfuncs.c`):**
   - `ring_vm_newfunc` computes `nActualArgs = pVM->nSP - nSP` and stores it in `pFuncCall->nActualParaCount`.
   - If `nActualArgs < nMinParams`, it throws `RING_VM_ERROR_LESSPARAMETERSCOUNT`.
   - Supplied arguments are popped and bound to their names; unsupplied default parameters are initialized to `""`.

3. **Argument Check Opcode (`vmjump.c` & `vm.c`):**
   - When executing `ICO_CHECKARG`:
     ```c
     if (pFuncCall->nActualParaCount >= (unsigned int)RING_VM_IR_READIVALUE(RING_VM_IR_REG2)) {
         RING_VM_JUMP; /* Jump over the default value assignment */
     }
     ```
   - If the caller supplied this argument, the VM jumps past the default expression, preserving the passed value.
   - If omitted, execution falls through and assigns the evaluated default expression to the parameter.
