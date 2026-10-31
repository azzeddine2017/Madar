---
name: ring_coder
description: Specialized AI assistant for writing clean, idiomatic Ring 1.27 code using Style 3 ({}) syntax
triggers: ring, رينج, كود, برمج, دالة, وظيفة, class, func, مصفوفة, خوارزمية, سكريبت, برنامج
tools: run_ring_code, read_file, write_file
---

## Fast Built-in Cheatsheet (Instant Lookup)

| Category | Functions |
|---|---|
| **I/O & Print** | `? expr` (print + nl), `see expr` / `put expr` (no nl), `give var` / `get var` (input) |
| **Strings** | `len(s)`, `lower(s)`, `upper(s)`, `trim(s)`, `left(s, n)`, `right(s, n)`, `substr(s, find, rep)`, `str2list(s)`, `list2str(a)`, `strcmp(s1, s2)` |
| **Lists (1-based)**| `len(a)`, `add(a, v)`, `del(a, idx)`, `insert(a, idx, v)`, `find(a, v)`, `sort(a)`, `reverse(a)`, `binarysearch(a, v)`, `list(rows, cols)` |
| **Types & Casts** | `type(v)`, `isstring(v)`, `isnumber(v)`, `islist(v)`, `isobject(v)`, `number(s)`, `string(n)`, `decimals(n)` |
| **Files & OS** | `read(file)`, `write(file, data)`, `fexists(path)`, `direxists(path)`, `dir(path)`, `remove(file)`, `rename(old, new)`, `sysargv`, `system(cmd)`, `eval(code)` |

---

## Coding Standard — Style 3 (Brace-Style `{}`)

**Write all new Ring code in brace-style `{}` by default.**

### Naming Conventions (Prefixes)
- `c`: Strings (`cName`, `cFilePath`)
- `n`: Numbers / Counts (`nCount`, `nIndex`, `nPort`)
- `a`: Lists / Arrays / Hashes (`aItems`, `aParams`)
- `o`: Objects (`oPlayer`, `oApp`)
- `b`: Booleans / Flags (`bIsActive`, `bFound`)
- `p`: Pointers / Low-level handles (`pHandle`)

### 1. Conditionals — `else` / `elseif` INSIDE the closing `}`
```ring
if condition {
    # block
else
    # block
}

if condition {
    # block
elseif condition2
    # block
else
    # block
}
```
> ⚠️ **CRITICAL TRAP:** NEVER write `} else {`. In Ring's parser, closing `}` before `else` detaches it from the `if`, producing **Runtime Error R24** (`Using uninitialized variable: else`).

### 2. Loops
```ring
for i = 1 to 10 step 2 {
    # block
}

for item in aList {
    # block
}

while condition {
    # block
}
```

### 3. Functions & Methods
```ring
func calculateTotal aItems {
    if type(aItems) != "LIST" {
        raise("Error: Expected list parameter")
    }
    nTotal = 0
    for nVal in aItems {
        nTotal += nVal
    }
    return nTotal
}
```
> Lists and objects are passed **by reference** automatically.

### 4. Classes & Declarative Object Instantiation
```ring
class Player {
    name  = "Guest"
    score = 0

    func init cName, nScore {
        this.name  = cName
        this.score = nScore
    }

    func display {
        ? "Player: " + this.name + " | Score: " + this.score
    }

    private
    id = 0
}

# Declarative initialization
oPlayer = new Player {
    name  = "Hero"
    score = 100
    display()
}
```

### 5. Error Handling (`try / catch / done`)
```ring
try {
    # risky operation
catch
    see "Error caught: " + cCatchError + nl
}
done
```
> In brace-style, `try { ... } catch ... }` MUST conclude with the `done` keyword.

---

## Critical Ring Execution Rules

1. **NO `func main()` Entry Point Requirement:**
   - Top-level statements execute from top to bottom.
   - All top-level code **must** precede any `func` or `class` definitions.
   - Code written after a `func` is swallowed into that function body and will not run on startup.
2. **Lists and Strings are 1-Indexed:**
   - `aList[1]` is the first element; `aList[0]` throws **Runtime Error R2**.
   - `cStr[1]` is the first character.
3. **`new Class()` vs `new Class`:**
   - `new Class()` (with parentheses) **always** invokes `func init`.
   - `new Class` (without parentheses) **never** invokes `func init` (leaves attributes at default values).
   - If a class has no `init`, calling `new Class()` throws **Runtime Error R3**.
4. **Case-Insensitivity & Keyword Collisions:**
   - Ring identifiers are case-insensitive (`oR` is the keyword `or`).
   - Never name variables `or`, `and`, `not`, `call`, `done`, `ok`, `step`.
5. **Loading Files vs Packages:**
   - Use `load "file.ring"` for script files and extensions.
   - Use `import PackageName` for packages.

---

## Verification & Dry-Run Protocol

Before executing or finalizing Ring code, verify using the Ring CLI:

```bash
# 1. Syntax & compilation check only (no execution)
ring script.ring -norun

# 2. Token stream inspection
ring script.ring -tokens

# 3. GUI safe test (timeout after 4s, exit 124 = success)
timeout 4 ring gui_script.ring
```
