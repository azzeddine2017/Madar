# ====================================================================
# Madar AI - Advanced Production RAG Showcase
# Demonstrates:
#   1. Dense Embeddings using BGE-M3 (bge-m3-q4_0.gguf)
#   2. Decoupled Zero-RAM Storage (.vec, .idx, .meta)
#   3. Overlapping Semantic Chunking
#   4. Hybrid Search (BGE Dense Cosine + Lexical Overlap)
#   5. Context Budget Management (Lost-in-the-Middle Mitigation)
#   6. Grounded Factual Generation using Qwen2.5 / BitNet
# ====================================================================

load "stdlibcore.ring"
load "../../libraries/madar_ai/madar_ai.ring"
load "../../libraries/madar_ai/rag/init.ring"

func main()
    ? "===================================================================="
    ? "  Madar AI: Advanced Modular Decoupled RAG Pipeline"
    ? "===================================================================="

    cEmbedderPath = "models/bge-m3-q4_0.gguf"
    if !fexists(cEmbedderPath)
        cEmbedderPath = "../../models/bge-m3-q4_0.gguf"
    ok

    cGenPath = "models/qwen2.5-0.5b-instruct-q4_0.gguf"
    if !fexists(cGenPath)
        cGenPath = "../../models/qwen2.5-0.5b-instruct-q4_0.gguf"
    ok
    cDBPath       = "madar_production_rag"

    # Verify model files
    if !fexists(cEmbedderPath)
        ? "  [Error] BGE-M3 model not found at: " + cEmbedderPath
        return
    ok

    ? "  [1/4] Loading BGE-M3 Embedding Engine..."
    oEmbedder = new BgeModel(cEmbedderPath)
    oEmbedder.setThreads(4)

    ? "  [2/4] Loading Qwen2.5 Generative Model..."
    oGenerator = NULL
    if fexists(cGenPath)
        oGenerator = new QwenModel(cGenPath)
        oGenerator.setThreads(4)
        oGenerator.fTemp = 0.2 # Factual low temperature
    else
        ? "  [Notice] Generator model not found; running in retrieval-only mode."
    ok

    ? "  [3/4] Initializing Modular RAG Pipeline..."
    oRAG = new MadarRAG(oEmbedder, oGenerator, cDBPath)

    # ----------------------------------------------------------------
    # Knowledge Ingestion with Overlapping Chunks
    # ----------------------------------------------------------------
    ? "  [4/4] Ingesting Knowledge Base with Semantic Overlapping..."

    cKnowledge1 = "The Madar Runtime Engine is built from the ground up for high-performance AI inference in the Ring ecosystem. " +
                  "It features a native tensor engine with 64-byte alignment, AVX2 vectorization, and JIT compilation via SLJIT. " +
                  "Madar supports ternary 1.58-bit models (BitNet), 4-bit quantized LLMs (Q4_0), and dense embeddings (BGE-M3)."

    cKnowledge2 = "The Decoupled Vector Database architecture in Madar separates dense vectors (.vec) from document texts (.meta). " +
                  "By maintaining a compact binary offset index (.idx), the system performs O(1) direct disk seeks. " +
                  "This ensures zero RAM consumption for raw text corpus, allowing indexing of massive datasets on standard hardware."

    cKnowledge3 = "Abu Rayhan al-Biruni was a polymath from Khwarazm who lived during the Islamic Golden Age. " +
                  "He made pioneering contributions to geodesy, calculating the Earth's radius to within 1% of the modern value. " +
                  "He was also proficient in astronomy, mathematics, and wrote the renowned work Kitab al-Hind."

    oRAG.addText(cKnowledge1)
    oRAG.addText(cKnowledge2)
    oRAG.addText(cKnowledge3)

    ? f"   -> Successfully indexed knowledge chunks into '{cDBPath}' (.vec, .idx, .meta)"

    # ----------------------------------------------------------------
    # Benchmark Questions
    # ----------------------------------------------------------------
    aQuestions = [
        "How does the Decoupled Vector Database in Madar achieve zero RAM consumption for text?",
        "What did al-Biruni calculate, and how accurate was his calculation?",
        "What quantization architectures and models does the Madar Engine support?"
    ]

    for q in aQuestions
        ? nl + "===================================================================="
        ? "Query: " + q
        ? "--------------------------------------------------------------------"

        # 1. Retrieve top matching chunks
        aTopChunks = oRAG.retrieve(q, 2)
        ? "Retrieved Context (from SSD via fseek):"
        for i = 1 to len(aTopChunks)
            item = aTopChunks[i]
            ? f"  [{i}] Hybrid Score: {item[:score]} | Dense: {item[:dense]} | Lex: {item[:lex]}"
            ? '      \"' + item[:text] + '\"'
        next

        # 2. Answer generation
        if !isNull(oGenerator)
            ? nl + "Generated Answer (LLM Grounded Inference):"
            cAnswer = oRAG.ask(q, 2)
            ? cAnswer
        ok
    next

    # Clean up DB files after demo
    cleanupDB(cDBPath)
    ? nl + "===================================================================="
    ? "  Showcase Complete! Zero RAM Bloat, Fast AVX2 Retrieval & Grounded Generation."
    ? "===================================================================="

func cleanupDB(cDB)
    cVec  = cDB + ".vec"
    cIdx  = cDB + ".idx"
    cMeta = cDB + ".meta"
    if fexists(cVec)  remove(cVec)  ok
    if fexists(cIdx)  remove(cIdx)  ok
    if fexists(cMeta) remove(cMeta) ok