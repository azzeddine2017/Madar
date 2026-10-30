# Madar AI - Local LLM & RAG Showcase Examples (أمثلة مدار للذكاء الاصطناعي)

This directory contains production-ready showcase examples demonstrating local LLM inference, embedding extraction, RAG (Retrieval-Augmented Generation), DataFrame analytics, and autonomous tool-calling agents in Madar using pure C99/Ring without external dependencies.

---

## 🌟 Available Examples

### 1. `stream_demo.ring` - Real-Time Token Streaming & Generator Pipeline
Demonstrates 4 distinct levels of high-speed streaming:
- **Direct Terminal Streaming:** Low-level C zero-latency token streaming to stdout.
- **Callback Streaming:** Ring function interceptor callback receiving token chunks in real-time.
- **Generator Loop:** Low-level `prefill()` and autoregressive `step()` loops.
- **Agent Streaming:** Real-time tool-calling autonomous agent streaming.
- **Chronos Telemetry:** Microsecond-precision generation metrics and throughput (tokens/sec).

```cmd
bin\ring.exe examples\ai\stream_demo.ring
```

---

### 2. `bge_rag_demo.ring` - Dual-Model High-Precision RAG (BGE-M3 + Qwen)
The gold standard for production RAG pipelines:
- **BGE-M3 (1024-dim):** Produces dense, normalized vector representations with supreme semantic accuracy.
- **C-Tensor Cosine Similarity:** Microsecond-level vector search without Python or LangChain.
- **Qwen Generation:** Deterministic answering grounded strictly in retrieved context chunks.

```cmd
bin\ring.exe examples\ai\bge_rag_demo.ring
```

---

### 3. `chat.ring` - Interactive Terminal Chat Assistant
Real-time conversational assistant:
- **Models:** Seamlessly runs Qwen2.5 (0.5B / 1.5B / 3B) or DeepSeek-R1 (1.5B / 7B) with automatic multi-path discovery.
- **Interactive Directives:** Streaming token generation, `/tokens <N>`, `/temp <0.0-1.0>`, `/gpu on|off`, and `/reset`.
- **Chronos Stats:** Accurate tokens/sec throughput and generation duration.

```cmd
bin\ring.exe examples\ai\chat.ring
bin\ring.exe examples\ai\chat.ring qwen
bin\ring.exe examples\ai\chat.ring deepseek
```

---

### 4. `doc_search.ring` - CLI Semantic Document Search
A semantic equivalent of `grep` that searches files based on **meaning** rather than literal keyword matches:
- Fast, local, and private (no data leaves your machine).
- Robust CLI argument parsing (supports `--json-errors` and custom flags transparently).
- Automatic streaming synthesis answering questions from the top matching section.

```cmd
bin\ring.exe examples\ai\doc_search.ring README.md "كيف يعمل محرك الذكاء الاصطناعي؟"
bin\ring.exe examples\ai\doc_search.ring docs\ARCHITECTURE.md "JIT"
```

---

### 5. `dataframe_demo.ring` - High-Speed C-Tensor Table Analytics
Demonstrates Madar's zero-copy contiguous memory table engine:
- Ingests CSV files into continuous C-allocated memory buffers in microseconds.
- Native statistical calculations (`mean`, `max`, `describe`).
- Fast vector-style boolean filtering (`df.filter("salary", ">", 4500)`).

```cmd
bin\ring.exe examples\ai\dataframe_demo.ring
```

---

### 6. `agent_demo.ring` - Autonomous Function Calling & Tools
Demonstrates the Madar AIAgent autonomous reasoning loop:
- Registers custom Ring functions as callable tools (`currency_rate`, `calc`, `get_time`, DataFrame analytics).
- Automatically plans and executes tools in response to user queries.

```cmd
bin\ring.exe examples\ai\agent_demo.ring
```

---

### 7. `agent_rag_demo.ring` - Autonomous Agent with Long-Term Episodic Memory
- Long-term vector memory (`agent.remember(...)` & `agent.recall(...)`).
- Persistent binary memory caching on disk (`.bin`).
- Dynamic memory injection into prompt context.

```cmd
bin\ring.exe examples\ai\agent_rag_demo.ring
```

---

### 8. `simple_rag.ring` - Minimal Declarative RAG Script
The most clean and direct 4-step pipeline for RAG:
```cmd
bin\ring.exe examples\ai\simple_rag.ring
```

---

### 9. `qalam_rag.ring` - Hybrid Search & Vector Persistence (Madar + AlQalam)
The ultimate showcase combining **Madar C Core** with **AlQalam C++17**:
- **PDF Extraction:** Index raw PDF manuals via `QalamReader`.
- **Hybrid Search:** Combines continuous tensor semantic similarity (70%) with lexical keyword matching (30%).
- **Binary Persistence:** Caches vector stores on disk (`.bin`) and reloads thousands of embeddings in microseconds.

```cmd
bin\ring.exe examples\ai\qalam_rag.ring
```
