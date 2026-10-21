
# ✒️ AlQalam (The Pen)
**The High-Performance Native Bridge for Ring & Jabr**

---


## 📦 Installation
```bash
ringpm install AlQalam from Azzeddine2017
```
## 🛠️ Build Instructions

### Windows (Visual Studio)
Run the provided batch file. Ensure `Ring` libraries are linked.
```bat
buildvc.bat
```
*(Compiles with `/O2` optimization and `/openmp` support)*

### Linux / macOS (GCC)
```bash
g++ -shared -o libalqalam.so -O3 -fopenmp -fPIC alqalam.cpp -I $RING_INCLUDE -L $RING_LIB -lring
```

---
## ⚡ Performance Benchmarks

AlQalam is designed to obliterate overhead. By leveraging C++ `std::vector`, `std::unordered_map`, and OpenMP, it achieves orders of magnitude speedups compared to native execution.

**Stress Test (1 Million Items):**

| Operation | Ring Native | AlQalam | **Speedup** |
| :--- | :--- | :--- | :--- |
| **Vector Math** | 0.28s | < 0.0001s | **~271x Faster** |
| **Dictionary Search** | 2.41s | 0.03s | **~92x Faster** |
| **Batch String Build** | 0.02s | < 0.001s | **~19x Faster** |
| **Formula Execution** | N/A | **Nanoseconds** | **Instant** |

---

## 🚀 The Philosophy & Dictionary

AlQalam uses a **Rhetorical Naming Convention** to reflect its role as a creative tool. It moves away from dry technical terms to words that describe the *action* of data manipulation.

| Domain | Technical Term | **AlQalam Term** | Description |
| :--- | :--- | :--- | :--- |
| **Vector** | `push_back` | **`flow`** | Let data flow into the container endlessly. |
| | `fill` | **`flood`** | Instantly flood the memory with a single value. |
| | `scale` | **`amplify`** | Multiply the signal (values) by a factor. |
| | `add_scalar` | **`elevate`** | Raise the baseline of data (Add). |
| | `pointer` | **`toTensor`** | Transmute the vector into a RingTensor (Zero-Copy View). |
| | `calc` | **`transform`** | Apply a mathematical formula string to the vector. |
| **Ink** | `append` | **`inscribe`** | Etch text into the memory buffer. |
| | `toString` | **`reveal`** | Show what has been written. |
| | `clear` | **`wipe`** | Clean the slate for new work. |
| **Index** | `set` | **`define`** | Define a meaning (ID) for a word. |
| | `set_batch` | **`defineFromList`** | Load a list of words with optional transformation (Reverse). |
| | `intersection` | **`intersect`** | Generalized set intersection (Fast C++ Logic). |
| | `keys` | **`keys`** | Extract all known words as a Ring List. |
| | `get` | **`recall`** | Recall the meaning from memory (O(1)). |

---

## 💻 API & Usage Examples

### 1. QalamVector: The Numeric Stream
A dynamic array wrapper around `std::vector<double>`.

```ring
load "AlQalam.ring"

# Initialize with capacity for 1 Million items
oData = new QalamVector(1000000)

# 1. Basic Flow
oData.flow(10.5)
oData.write(1, 99.9)  # Update index 1
val = oData.read(1)   # Get index 1

# 2. Alchemy (Batch Math)
oData.flood(1.0)      # Set all to 1.0
oData.elevate(5.0)    # Add 5 -> [6.0, 6.0...]
oData.amplify(2.0)    # Mult 2 -> [12.0, 12.0...]

# 3. The Math Engine (Formula Compiler)
# Compiles string to bytecode and executes in parallel
oData.transform("x * 2 + sin(x)")
oData.transform("relu(x)")

# 4. Binary Persistence (Direct Disk I/O)
oData.saveBinary("memory_dump.bin")
oData.loadBinary("memory_dump.bin")

# 5. Bridge to RingTensor
# Converts to Tensor without copying memory
oTensor = oData.toTensor(1000, 1000)
```

### 2. QalamInk: The Text Builder
Used to construct massive datasets or generate text without memory fragmentation.

```ring
oInk = new QalamInk()

# Inscribe data instantly
oInk.inscribe("In the name of logic, ")
oInk.inscribe("we build the future.")

# Batch inscription (High throughput)
aLines = ["Line 1", "Line 2", "Line 3"]
oInk.inscribeBatch(aLines)

# Output
see oInk.reveal() 
oInk.wipe()
```

### 3. QalamIndex: The Memory Map
An O(1) Lookup table (`std::unordered_map`) for Tokenizers.

```ring
oMemory = new QalamIndex()

# Teaching
oMemory.define("hello", 5)
oMemory.define("world", 12)

# 1. Batch Teaching (Lightning Fast)
aWords = ["ring", "logic", "speed"]
oMemory.defineFromList(aWords, 1, 3, 0) # List, ID, MinLength, Transform(0=None, 1=Reverse)

# 2. Set Intersection (Generalized Logic)
# Find common items between two indices in C++ speed (O(n))
oOther = new QalamIndex()
oOther.define("ring", 1)
aCommon = oMemory.intersect(oOther) # ["ring"]

# 3. Keys Listing
aKeys = oMemory.keys()

# 4. Instant Recall
if oMemory.knows("hello")
    id = oMemory.recall("hello")
ok
```

### 4. QalamChronos: The Timekeeper
A nanosecond-precision timer for benchmarking.

```ring
oTimer = new QalamChronos()

oTimer.reset()
# ... heavy operation ...
see "Time elapsed: " + oTimer.elapsed() # e.g., "450 us"
```

---

## 🧪 Formula Engine Reference
The `transform` method supports a mini-language compiled to bytecode:

*   **Operators:** `+`, `-`, `*`, `/`, `^` (Power)
*   **Variable:** `x` (Current element value)
*   **Functions:** 
    *   `sin(x)`, `cos(x)`, `tan(x)`
    *   `sqrt(x)`, `abs(x)`
    *   `log(x)`, `exp(x)`
    *   `relu(x)` (Rectified Linear Unit: `max(0, x)`)

**Example:**
```ring
# Normalize: (x - mean) / std
oVec.transform("(x - 0.5) / 0.2")
```


