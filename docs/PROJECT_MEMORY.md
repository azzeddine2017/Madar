# Madar Project Memory & Architectural Registry

## 🏛️ Strategic Vision: From Conversational AI to Enterprise Decision Intelligence
Madar (مدار) is engineered as an ultra-fast, lightweight (< 4 MB runtime core), multi-modal cognitive and mathematical execution engine.

In addition to neural inference (`MadarAgent`, GGUF, LoRA, OpenCL GPU offloading), the **Decision Intelligence & Operations Research (OR)** pillar provides high-speed combinatorial optimization to solve industrial problems (Cutting Stock, Bin Packing, Vehicle Routing, Job Shop Scheduling).

---

## 📦 Decoupled Architecture Principles
1. **Zero-Coupling Boundary:**
   - Neural/LLM inference (`MadarAgent`, GGUF) is strictly decoupled from the mathematical optimization engine (`MadarOpt`).
   - `MadarOpt` has zero dependency on neural weights, GPU VRAM, or prompt text generation.
2. **Headless & Microservice Design:**
   - Industrial plants run headless solvers. Inputs are structured tables (CSV, JSON, SQL/ERP databases), and outputs are deterministic execution schedules (Gantt-compatible JSON, CSV cutting lists).
3. **Numerical Acceleration Rules:**
   - `dour` JIT (SLJIT) accelerates scalar arithmetic, numeric loop reductions, and continuous arrays.
   - Dynamic objects and strings remain in standard VM bytecode.
   - Inner calculation kernels are kept strictly numerical.

---

## 🔬 Milestones & Verified Benchmarks

### 1. `MadarOpt 0.1.0-alpha` (Cutting Stock & Bin Packing)
- **Module:** `libraries/madar_opt/`
- **Problem Formulation:** 1D Linear Cutting Stock with blade saw kerf compensation.
- **Solvers:**
  - `HeuristicCuttingSolver`: First-Fit Decreasing (FFD) and Best-Fit Decreasing (BFD).
  - `GeneticCuttingSolver`: Multi-generation evolutionary search with elitism, tournament selection, and Order Crossover (OX).
- **Industrial Benchmark Results:**
  - Work order: 80 parts, 173 linear meters of profile.
  - Manual naive baseline: 40 stock bars, 67 meters waste (27.92% scrap), Cost: $1,800 USD.
  - MadarOpt BFD / GA: 30 stock bars, 7 meters waste (3.89% scrap), Cost: $1,350 USD.
  - **Direct ROI: $450 USD saved and 60 meters of metal saved on a single order.**
  - **Latency:** BFD solver finished in **6 milliseconds**.



---

## ⚡ RingTensor vs 'dour' in Operations Research (Empirical Findings)

### 1. The Reality of 'dour' (Auto-JIT)
- **Strengths:** Excellent for pure scalar mathematical reductions without branching ($s += x \cdot x$).
- **Limitations:** Fails on combinatorial OR algorithms because any dynamic list indexing (`aList[i]`) or conditional branching (`if`) triggers a safe fallback to interpreted VM bytecode.

### 2. The Dominance of RingTensor (In-Core AVX2 SIMD)
- **Architecture:** Contiguous flat C memory (`float*`) with native matrix transformations and SIMD kernels.
- **Operations Research Application:** Batched candidate evaluation in Genetic Algorithms and Metaheuristics:
  - Formulated as matrix multiplication $Y = A \cdot w$ where $A \in \{0, 1\}^{M \times N}$ is the assignment matrix and $w \in \mathbb{R}^{N \times 1}$ is the demand vector.
  - Computes fill levels for all stock bars simultaneously via single hardware GEMM call.
- **Laboratory Benchmark (`benchmarks/benchmark_tensor_vs_list.ring`):**
  - Workload: 1,000 evaluations across 40 bars $\times$ 80 items (3,200,000 arithmetic operations).
  - Standard Ring List loops: **2,775.02 ms**
  - Madar Native RingTensor: **24.42 ms**
  - **Acceleration Factor: 113.64x FASTER** with identical mathematical checksum.


### 3. Production Ingestion & Headless CLI Engine
- **Module:** `libraries/madar_opt/io/` & `libraries/madar_opt/cli.ring`
- **Data Ingestion (`OptDataLoader`):** Ingests factory CSV work orders (`item_id, length, quantity`).
- **Plan Export (`OptPlanExporter`):**
  - Production shopfloor table: `cutting_plan.csv` with exact piece patterns, kerf allowance, and scrap ratios.
  - Machine-readable JSON: `cutting_plan.json` for ERP, MES, and CNC machines.
- **Verification Run:**
  - 106 pieces (193.9 meters) solved in **21.5 ms**.
  - Bars required: 34 (Theoretical lower bound: 33).
  - Total waste ratio: **4.95%**.


### 4. What-If Multi-Scenario Simulation Engine & Data Isolation Protocol
- **Module:** `libraries/madar_opt/core/scenario_engine.ring`, `io/decision_reporter.ring`
- **Data Directory Isolation:**
  - All input files strictly confined to: `libraries/madar_opt/data/inputs/`
  - All generated artifacts strictly confined to: `libraries/madar_opt/data/outputs/`
  - Zero scattered files in root or libraries directories.
- **Scenario Simulation Architecture:**
  - Evaluates competing supply, procurement, and physical constraint scenarios in parallel.
  - Automatically identifies:
    - **Recommended Winner** (Pareto-optimal solution).
    - **Cheapest Option** (Lowest total procurement cost USD).
    - **Greenest Option** (Minimum scrap waste percentage).
  - Emits side-by-side comparative table (`scenario_comparison.csv`) and executive C-suite report (`executive_decision_brief.json`).
- **Benchmark Performance:**
  - Evaluated 4 enterprise scenarios (106 parts, 193.9 meters) in **20.21 milliseconds** total.
  - Regression Test Suite: **7/7 Passed**.


### 5. Generalized Mathematical Modeler & Algebraic Optimization Engine
- **Module:** `libraries/madar_opt/modeler/`
- **Algebraic Modeler (`OptModel`, `OptVariable`, `OptConstraint`):**
  - Abstract mathematical programming modeling supporting continuous (`OPT_CONTINUOUS`), integer (`OPT_INTEGER`), and binary (`OPT_BINARY`) decision variables.
  - Linear constraint compilation into continuous `RingTensor` matrix structures ($A x \le b$, $A x \ge b$, $A x == b$).
- **Solvers Implemented:**
  - `OptSimplexSolver`: Canonical Two-Phase Simplex algorithm with artificial variables, handling general maximization and minimization in sub-millisecond execution.
  - `OptBranchBoundSolver`: Exact Branch-and-Bound algorithm for Mixed-Integer Linear Programming (MILP) and 0/1 combinatorial selection.
- **Verification Milestones (`tests/test_modeler.ring`):**
  1. Dantzig Product Mix LP (Maximization): $x_1^* = 2.0, x_2^* = 6.0, Z^* = 36.0$ in **665 us**.
  2. Two-Phase Diet LP (Minimization): $x_1^* = 3.0, x_2^* = 1.0, Z^* = 9.0$ in **422 us**.
  3. Discrete Knapsack MILP: $x_1^* = 2, x_2^* = 1, Z^* = 16.0$ in **4.6 ms**.
  4. Capital Budgeting Binary 0/1: $P_1 = 1, P_2 = 0, P_3 = 1, Z^* = 35.0$ in **1.01 ms**.
