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
```cmd
bin\ring.exe examples\ai\doc_search.ring
```

---

### 4. `simple_rag.ring` - Minimal Declarative RAG Script
The most clean and direct 4-step pipeline for RAG:
```ring
# 1. Open model
embed_model = model_open("models/qwen2.5-0.5b-instruct-q4_0.gguf")
llm         = embed_model

# 2. Extract query embedding
query_vector = embed_model.get_embedding("كيف أصلح خطأ الذاكرة؟")

# 3. Fast Vector Search using C Tensors
best_chunk = vector_search(query_vector, store)

# 4. Generate grounded answer
prompt = "<|im_start|>system" + nl + 
         "أجب بناءً على هذا المرجع فقط: " + best_chunk + "<|im_end|>" + nl +
         "<|im_start|>user" + nl + "كيف أصلح خطأ الذاكرة؟<|im_end|>" + nl +
         "<|im_start|>assistant" + nl

see llm.generateStream(prompt, 128)
```
Run:
```cmd
bin\ring.exe examples\ai\simple_rag.ring
```

