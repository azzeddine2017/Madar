# Madar AI - Local LLM & RAG Showcase Examples

This directory contains standalone examples demonstrating local LLM inference, embedding extraction, and RAG (Retrieval-Augmented Generation) in Madar using pure C99/Ring without external dependencies.

---

## Available Examples

### 1. `chat.ring` - Interactive Terminal Chat
Real-time conversational assistant:
- **Models:** Supports Qwen2.5 (0.5B / 3B) and DeepSeek-R1 (1.5B) GGUF models.
- **Features:** Streaming token generation, parameter tuning (`/tokens <N>`, `/temp <0.0-1.0>`), context memory reset (`reset`), and performance stats (tokens/sec).

```cmd
bin\ring.exe examples\ai\chat.ring qwen
```

---

### 2. `rag_demo.ring` - Local Semantic Search & Knowledge Assistant (RAG)
Factual question answering grounded in local knowledge bases with **zero hallucination**:
- **Leverages Madar Innovations:**
  - **Native Continuous Tensors (`RingTensor`):** Computes normalized $L_2$ embeddings directly from the LLM core.
  - **C-Speed Cosine Similarity:** Instantaneous vector matching (`tensor_cosine_similarity`).
  - **Advanced Language Syntax:** Utilizes f-strings, default arguments, list comprehensions, and negative list slicing (`aList[::-1]`).
- **Interactive Commands:**
  - Type any question (Arabic or English) to retrieve context and generate grounded answers.
  - `/search <text>`: Semantic search only without text generation.
  - `/add <fact>`: Dynamically add knowledge facts to vector memory on the fly.
  - `/file <filepath>`: Ingest an entire Markdown or text file into the vector database.
  - `/list`: Inspect all indexed chunks in memory.
  - `/clear`: Reset vector store.

```cmd
bin\ring.exe examples\ai\rag_demo.ring
```

---

### 3. `doc_search.ring` - CLI Semantic Document Search
A semantic equivalent of `grep` that searches files based on **meaning** rather than literal keyword matches:
- Index a document once and query it semantically.
- Fast, local, and private (no data leaves your machine).

```cmd
bin\ring.exe examples\ai\doc_search.ring README.md "كيف يعمل محرك الذكاء الاصطناعي؟"
```
Or run interactively:
```cmd
bin\ring.exe examples\ai\doc_search.ring
```
