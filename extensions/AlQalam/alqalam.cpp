/*
** AlQalam Extension
*/

extern "C" {
    #include "ring.h"
}

#include <vector>
#include <string>
#include <string_view>
#include <unordered_map>
#include <algorithm>
#include <cstring>
#include <cstdio>
#include <cmath>
#include <chrono> 
#include <cctype>
#include "tiny_math.hpp"

#ifdef _OPENMP
#include <omp.h>
#endif


// --- Structures ---
struct QalamTimer { std::chrono::high_resolution_clock::time_point start_time;};
struct QalamVector { std::vector<double> data; size_t nReservedSize = 0; };
struct QalamInk    { std::string text; };

/* ====================================================================
** Upgrade 5: Transparent Hash/Comparator for Heterogeneous Lookup
** ====================================================================
** BEFORE: Every map.find() / map.count() call with const char* created
**         a temporary std::string (heap alloc + copy) just for the lookup.
**         In a tokenizer processing millions of words, this sums up to
**         millions of unnecessary allocations.
**
** AFTER:  The transparent hash (with is_transparent tag) allows the
**         unordered_map to accept std::string_view directly in find/count,
**         computing the hash WITHOUT constructing a std::string.
**         On Broadwell i3, this eliminates ~1 cache miss per lookup
**         (the miss that would've been caused by the heap allocation).
** ==================================================================== */
struct StringHash {
    using is_transparent = void;  /* Enables heterogeneous lookup */
    
    size_t operator()(const std::string& s)    const { return std::hash<std::string_view>{}(s); }
    size_t operator()(std::string_view sv)      const { return std::hash<std::string_view>{}(sv); }
    size_t operator()(const char* cs)           const { return std::hash<std::string_view>{}(cs); }
};

/* QalamIndex now uses transparent hash + std::equal_to<> (C++14)
** std::equal_to<> (void specialization) compares any compatible types
** without requiring conversion to std::string. */
struct QalamIndex  { std::unordered_map<std::string, double, StringHash, std::equal_to<>> map; };

struct QalamFormulaWrapper { std::vector<Instruction> program; };

// --- Destructors ---
void qvector_free(void *pState, void *pPointer) { delete (QalamVector *)pPointer; }
void qink_free(void *pState, void *pPointer)    { delete (QalamInk *)pPointer; }
void qindex_free(void *pState, void *pPointer)  { delete (QalamIndex *)pPointer; }
void qtimer_free(void *pState, void *pPointer) { delete (QalamTimer *)pPointer; }
void qformula_free(void *pState, void *pPointer) { delete (QalamFormulaWrapper *)pPointer; }

// --- PDF Extraction Helper ---
// Strictly use pdftotext.exe for high-quality extraction for Jibrail project.
std::string extract_pdf_basic(const char* filename) {
    // Get the directory of the current DLL to find pdftotext.exe nearby
    char dllPath[MAX_PATH];
    GetModuleFileNameA(GetModuleHandleA("alqalam.dll"), dllPath, MAX_PATH);
    std::string exePath = dllPath;
    size_t lastBackslash = exePath.find_last_of("\\/");
    if (lastBackslash != std::string::npos) {
        exePath = exePath.substr(0, lastBackslash + 1) + "pdftotext.exe";
    } else {
        exePath = "pdftotext.exe"; // Fallback to PATH
    }

    std::string cmd = "\"\"" + exePath + "\" -enc UTF-8 -nopgbrk \"";
    cmd += filename;
    cmd += "\" -\"";

    std::string result;
    FILE* pipe = _popen(cmd.c_str(), "r");
    if (pipe) {
        char pipe_buffer[4096];
        while (fgets(pipe_buffer, sizeof(pipe_buffer), pipe) != NULL) {
            result += pipe_buffer;
        }
        _pclose(pipe);
    }

    // Whitespace normalization for Jibrail Vector DB
    std::string cleaned;
    bool lastWasSpace = true;
    for(size_t k = 0; k < result.length(); k++) {
        unsigned char c = (unsigned char)result[k];
        if (c <= 32) {
            if (!lastWasSpace) { 
                cleaned += (c == '\n' ? '\n' : ' '); 
                lastWasSpace = true; 
            }
        } else {
            cleaned += (char)c;
            lastWasSpace = false;
        }
    }
    return cleaned;
}


extern "C" {

    // ==========================================
    // 1. QalamChronos (Time Lord)
    // ==========================================
    
    // Init: timer.init()
    RING_FUNC(qalam_timer_init) {
        QalamTimer *p = new QalamTimer();
        p->start_time = std::chrono::high_resolution_clock::now();
        RING_API_RETMANAGEDCPOINTER(p, "QalamTimer", qtimer_free);
    }
    // Reset: timer.reset()
    RING_FUNC(qalam_timer_reset) {
        QalamTimer *p = (QalamTimer*)RING_API_GETCPOINTER(1, "QalamTimer");
        if(p) p->start_time = std::chrono::high_resolution_clock::now();
    }
    // Elapsed: timer.elapsed_ns()
    RING_FUNC(qalam_timer_elapsed_ns) {
        QalamTimer *p = (QalamTimer*)RING_API_GETCPOINTER(1, "QalamTimer");
        if(!p) { RING_API_RETNUMBER(0.0); return; }
        
        auto now = std::chrono::high_resolution_clock::now();
        auto dur = std::chrono::duration_cast<std::chrono::nanoseconds>(now - p->start_time).count();
        
        // Return as double (Ring doesn't have int64)
        RING_API_RETNUMBER((double)dur);
    }

    // ==========================================
    // 2. QalamVector Controls (Edit & Manage)
    // ==========================================
    RING_FUNC(qalam_vector_init) {
        // Simple Init without Try/Catch
        QalamVector *p = new QalamVector();
        if (RING_API_PARACOUNT == 1) {
            int n = (int)RING_API_GETNUMBER(1);
            if(n > 0) {
                p->data.resize(n, 0.0); 
                p->nReservedSize = n;
            }
        }
        RING_API_RETMANAGEDCPOINTER(p, "QalamVector", qvector_free);
    }
    
    // Add Value: vec.append(val)
    RING_FUNC(qalam_vector_add) {
        QalamVector *p = (QalamVector*)RING_API_GETCPOINTER(1, "QalamVector");
        if(p) p->data.push_back(RING_API_GETNUMBER(2));
    }

    // Get Value: val = vec[i]
    RING_FUNC(qalam_vector_get) {
        QalamVector *p = (QalamVector*)RING_API_GETCPOINTER(1, "QalamVector");
        int idx = (int)RING_API_GETNUMBER(2) - 1;
        if (p && idx >= 0 && idx < p->data.size()) {
            RING_API_RETNUMBER(p->data[idx]);
        } else {
            RING_API_RETNUMBER(0.0);
        }
    }

    // Size: n = vec.size()
    RING_FUNC(qalam_vector_size) {
        QalamVector *p = (QalamVector*)RING_API_GETCPOINTER(1, "QalamVector");
        RING_API_RETNUMBER(p ? (double)p->data.size() : 0.0);
    }

    // Run Loop: vec.run_loop(op, val)
    RING_FUNC(qalam_vector_run_loop) {
        QalamVector *p = (QalamVector*)RING_API_GETCPOINTER(1, "QalamVector");
        if (!p) return;
        int nOp = (int)RING_API_GETNUMBER(2);
        double nVal = RING_API_GETNUMBER(3);
        if (p->data.size() == 0 && p->nReservedSize > 0) {
            p->data.resize(p->nReservedSize, 0.0);
        }
        size_t n = p->data.size();
        double* ptr = p->data.data();
        size_t i;
        
        if (nOp == 1) std::fill(p->data.begin(), p->data.end(), nVal);
        else if (nOp == 2) for(i=0; i<n; i++) ptr[i] += nVal;
        else if (nOp == 3) for(i=0; i<n; i++) ptr[i] *= nVal;
    }

    // Get Pointer: ptr = vec.get_ptr()
    RING_FUNC(qalam_vector_get_ptr) {
        QalamVector *p = (QalamVector*)RING_API_GETCPOINTER(1, "QalamVector");
        RING_API_RETNUMBER(p ? (double)(size_t)p->data.data() : 0.0);
    }

    // Set Value: vec[i] = val (Correction/Edit)
    RING_FUNC(qalam_vector_set) {
        QalamVector *p = (QalamVector*)RING_API_GETCPOINTER(1, "QalamVector");
        int idx = (int)RING_API_GETNUMBER(2) - 1; // 1-based to 0-based
        double val = RING_API_GETNUMBER(3);
        
        if (p && idx >= 0 && idx < p->data.size()) {
            p->data[idx] = val;
        }
    }

    // Clear: Remove all items (Reset)
    RING_FUNC(qalam_vector_clear) {
        QalamVector *p = (QalamVector*)RING_API_GETCPOINTER(1, "QalamVector");
        if(p) p->data.clear();
    }

    // Reserve: Pre-allocate memory (Optimization)
    RING_FUNC(qalam_vector_reserve) {
        QalamVector *p = (QalamVector*)RING_API_GETCPOINTER(1, "QalamVector");
        int n = (int)RING_API_GETNUMBER(2);
        if(p && n > 0) p->data.reserve(n);
    }
    
    // Resize: Force size change (fill with zeros if expanding)
    RING_FUNC(qalam_vector_resize) {
        QalamVector *p = (QalamVector*)RING_API_GETCPOINTER(1, "QalamVector");
        int n = (int)RING_API_GETNUMBER(2);
        if(p && n >= 0) p->data.resize(n, 0.0);
    }
    
    // Load Data Directly from Memory Address (Pointer)
    RING_FUNC(qalam_vector_load_from_ptr) {
        QalamVector *p = (QalamVector*)RING_API_GETCPOINTER(1, "QalamVector");
        size_t nAddr   = (size_t)RING_API_GETNUMBER(2); // Memory address from the tensor
        int nCount     = (int)RING_API_GETNUMBER(3);    // Number of elements to copy

        double *pSrc = (double *)nAddr;

        if (p && pSrc && nCount > 0) {
            // Securing space in the pen
            p->data.resize(nCount);
            
            //Direct memory copying (Zero-Copy Transfer)
            memcpy(p->data.data(), pSrc, nCount * sizeof(double));
        }
    }

    // Append Data Directly from Memory Address (Pointer)
    RING_FUNC(qalam_vector_append_from_ptr) {
        QalamVector *p = (QalamVector*)RING_API_GETCPOINTER(1, "QalamVector");
        size_t nAddr   = (size_t)RING_API_GETNUMBER(2); // Memory address from the tensor
        int nCount     = (int)RING_API_GETNUMBER(3);    // Number of elements to copy

        double *pSrc = (double *)nAddr;

        if (p && pSrc && nCount > 0) {
            // Direct memory copying (Zero-Copy Transfer)
            p->data.insert(p->data.end(), pSrc, pSrc + nCount);
        }
    }

    // =============================================================
    // 1. THE SUPER LOOP (Process)
    // =============================================================
    /*
        Modes:
        10: CLIP (min, max)
        11: THRESHOLD_REPLACE (limit, val) -> if x < limit then x = val
        20: SUM_RANGE (start, end)
        30: FIND_FIRST_GT (val) -> returns index
    */
    RING_FUNC(qalam_vector_copy) {
        if (RING_API_PARACOUNT != 2) return;
        QalamVector *pSrc = (QalamVector*)RING_API_GETCPOINTER(1, "QalamVector");
        QalamVector *pDst = (QalamVector*)RING_API_GETCPOINTER(2, "QalamVector");
        if (!pSrc || !pDst) return;
        
        size_t n = pSrc->data.size();
        pDst->data.resize(n);
        std::copy(pSrc->data.begin(), pSrc->data.end(), pDst->data.begin());
    }

    /*
    ** Function: qalam_vector_copy_segment
    ** Description: Rapid memory transfer within a single processor strike (Memcpy Zero-Copy)
    ** Params: 1. Target Vector, 2. Source Vector, 3. Target Offset
    */
    RING_FUNC(qalam_vector_copy_segment) {
        if (RING_API_PARACOUNT != 3) {
            RING_API_ERROR("copySegment requires 3 params: Target, Source, Offset");
            return;
        }
        QalamVector *pDst = (QalamVector*)RING_API_GETCPOINTER(1, "QalamVector");
        QalamVector *pSrc = (QalamVector*)RING_API_GETCPOINTER(2, "QalamVector");
        int nOffset = (int)RING_API_GETNUMBER(3);

        if (pDst && pSrc && nOffset >= 0) {
            size_t nSrcSize = pSrc->data.size();
            // Ensure target has enough capacity
            if (nOffset + nSrcSize > pDst->data.size()) {
                pDst->data.resize(nOffset + nSrcSize, 0.0);
            }
            // Rapid Memcpy (Zero-Copy)
            memcpy(pDst->data.data() + nOffset, pSrc->data.data(), nSrcSize * sizeof(double));
        }
    }

    RING_FUNC(qalam_vector_process) {
        QalamVector *p = (QalamVector*)RING_API_GETCPOINTER(1, "QalamVector");
        if (!p) return;

        int nMode = (int)RING_API_GETNUMBER(2);
        double p1 = (RING_API_PARACOUNT >= 3) ? RING_API_GETNUMBER(3) : 0.0;
        double p2 = (RING_API_PARACOUNT >= 4) ? RING_API_GETNUMBER(4) : 0.0;
        double p3 = (RING_API_PARACOUNT >= 5) ? RING_API_GETNUMBER(5) : 0.0;
        if (p->data.size() == 0 && p->nReservedSize > 0) {
            p->data.resize(p->nReservedSize, 0.0);
        }
        size_t n = p->data.size();
        double* ptr = p->data.data();
        size_t i;

        switch (nMode) {
            // --- Transformations (In-Place) ---
            case 10: // CLIP (min, max)
                #pragma omp parallel for
                for(i=0; i<n; i++) {
                    if (ptr[i] < p1) ptr[i] = p1;
                    else if (ptr[i] > p2) ptr[i] = p2;
                }
                break;

            case 11: // THRESHOLD (if < p1, set to p2)
                #pragma omp parallel for
                for(i=0; i<n; i++) {
                    if (ptr[i] < p1) ptr[i] = p2;
                }
                break;

            case 12: // SCALE_ADD (x = x * p1 + p2)
                #pragma omp parallel for
                for(i=0; i<n; i++) ptr[i] = ptr[i] * p1 + p2;
                break;

            // --- Aggregations (Return Value) ---
            case 20: // SUM RANGE (start=p1, count=p2)
            {
                size_t start = (size_t)p1 - 1;
                size_t count = (size_t)p2;
                if (start + count > n) count = n - start;
                double sum = 0;
                // #pragma omp parallel for reduction(+:sum) // Overhead usually too high for simple sums
                for(i=0; i<count; i++) sum += ptr[start + i];
                RING_API_RETNUMBER(sum);
                return; // Return early
            }

            // --- Search (Return Index) ---
            case 30: // FIND_FIRST_GT (val=p1)
                for(i=0; i<n; i++) {
                    if (ptr[i] > p1) {
                        RING_API_RETNUMBER((double)(i + 1));
                        return;
                    }
                }
                RING_API_RETNUMBER(0.0);
                return;
            // --- Advanced Matching Operations (Quantum Vector) ---
            case 40: // DOT_PRODUCT with Raw Double Array Pointer
            {
                double* targetPtr = (double*)(size_t)p1;
                if (!targetPtr) { RING_API_RETNUMBER(0.0); return; }
                double dot = 0.0;
                for (i = 0; i < n; i++) dot += ptr[i] * targetPtr[i];
                RING_API_RETNUMBER(dot);
                return;
            }
            case 41: // L2_NORM
            {
                double norm = 0.0;
                #pragma omp parallel for reduction(+:norm)
                for (i = 0; i < n; i++) norm += ptr[i] * ptr[i];
                RING_API_RETNUMBER(sqrt(norm + 1e-12));
                return;
            }
            case 42: // ADD (Vector += p1_Pointer)
            {
                double* targetPtr = (double*)(size_t)p1;
                if (!targetPtr) return;
                #pragma omp parallel for
                for (i = 0; i < n; i++) ptr[i] += targetPtr[i];
                return;
            }
            case 43: // IN-PLACE NORMALISE
            {
                double norm = 0.0;
                #pragma omp parallel for reduction(+:norm)
                for (i = 0; i < n; i++) norm += ptr[i] * ptr[i];
                norm = sqrt(norm + 1e-12);
                #pragma omp parallel for
                for (i = 0; i < n; i++) ptr[i] /= norm;
                return;
            }
            case 44: // IN-PLACE ROTATE (shift=p1)
            {
                int shift = (int)p1;
                if (n == 0 || shift == 0) return;
                shift = (shift % (int)n + (int)n) % (int)n; // Handling negative shifts
                std::vector<double> temp(n);
                std::copy(ptr, ptr + n, temp.begin());
                for (i = 0; i < n; i++) {
                    ptr[i] = temp[(i + shift) % n];
                }
                return;
            }
        }
    }

    // =============================================================
    // 2. DIRECT I/O (Disk Speed)
    // =============================================================

    RING_FUNC(qalam_vector_save_binary) {
        QalamVector *p = (QalamVector*)RING_API_GETCPOINTER(1, "QalamVector");
        const char *cFile = RING_API_GETSTRING(2);
        if(!p) return;

        FILE *fp = fopen(cFile, "wb");
        if (!fp) { RING_API_ERROR("Cannot open file for writing"); return; }

        // Header: Size (size_t is 8 bytes on x64)
        size_t size = p->data.size();
        fwrite(&size, sizeof(size_t), 1, fp);

        // Body: Data
        fwrite(p->data.data(), sizeof(double), size, fp);
        fclose(fp);
    }

    RING_FUNC(qalam_vector_load_binary) {
        QalamVector *p = (QalamVector*)RING_API_GETCPOINTER(1, "QalamVector");
        const char *cFile = RING_API_GETSTRING(2);
        if(!p) return;

        FILE *fp = fopen(cFile, "rb");
        if (!fp) { RING_API_ERROR("Cannot open file for reading"); return; }

        size_t size;
        if(fread(&size, sizeof(size_t), 1, fp) == 1) {
            p->data.resize(size);
            fread(p->data.data(), sizeof(double), size, fp);
        }
        fclose(fp);
    }
     
    /* 
** Function: qalam_vector_stream
** Description: It reads a data block from a binary file directly into vector memory.
** Params: 1. Vector, 2. Path, 3. Offset, 4. Count, 5. Mode ("load" or "upload")
*/
RING_FUNC(qalam_vector_stream) {
    if (RING_API_PARACOUNT != 5) {
        RING_API_ERROR("stream requires 5 params: Vector, Path, Offset, Count, Mode");
        return;
    }

    QalamVector *p = (QalamVector*)RING_API_GETCPOINTER(1, "QalamVector");
    const char* cPath = RING_API_GETSTRING(2);
    long long nOffset = (long long)RING_API_GETNUMBER(3);
    int nCount        = (int)RING_API_GETNUMBER(4);
    const char* cMode = RING_API_GETSTRING(5); // "load" or "upload"

    if (!p || !cPath) return;

    // Determine the file mode: "rb" for reading, "rb+" for appending without truncation
    const char* fileMode = (strcmp(cMode, "load") == 0) ? "rb" : "rb+";
    
    // If upload and file doesn't exist, open it in "wb" mode first to create it
    FILE* fp = fopen(cPath, fileMode);
    if (!fp && strcmp(cMode, "upload") == 0) {
        fp = fopen(cPath, "wb");
    }

    if (!fp) {
        RING_API_ERROR("Streamer: File access error!");
        return;
    }

    // Jump to the desired location in the file (Supports files >4GB)
    #ifdef _WIN32
        _fseeki64(fp, nOffset * sizeof(double), SEEK_SET);
    #else
        fseeko(fp, nOffset * sizeof(double), SEEK_SET);
    #endif

    if (strcmp(cMode, "load") == 0) {
        // --- Load mode ---
        p->data.resize(nCount);
        fread(p->data.data(), sizeof(double), nCount, fp);
    } 
    else if (strcmp(cMode, "upload") == 0) {
        // --- Upload mode ---
        // Write the current vector content to the specified location in the file
        if (p->data.size() < nCount) nCount = p->data.size();
        fwrite(p->data.data(), sizeof(double), nCount, fp);
    }

    fclose(fp);
    RING_API_RETNUMBER((double)nCount);
}

    // =============================================================
    // 3. MATRIX-FREE CONJUGATE GRADIENT (TDVP / SR) 
    // solves S * x = F efficiently for massive NQS architectures
    // S = (O^T * O)/B + reg * I
    // =============================================================
    
    // Internal Helper: Matrix-Free Vector Product (S * v)
    static void apply_s_matrix(const double* O, const double* v, double* out, int B, int N, double reg) {
        // temp array of size B
        std::vector<double> temp(B, 0.0);
        
        // 1. temp = O * v
        #pragma omp parallel for
        for (int i = 0; i < B; i++) {
            double sum = 0;
            for (int j = 0; j < N; j++) {
                sum += O[i * N + j] * v[j];
            }
            temp[i] = sum;
        }

        // 2. out = O^T * temp / B + reg * v
        double scale = 1.0 / B;
        #pragma omp parallel for
        for (int j = 0; j < N; j++) {
            double sum = 0;
            for (int i = 0; i < B; i++) {
                sum += O[i * N + j] * temp[i];
            }
            out[j] = sum * scale + reg * v[j];
        }
    }
    /*
    ** Solve S * x = F using Conjugate Gradient
    ** O: Jacobian matrix (B x N)
    ** F: Force vector (N)
    ** x: Result vector (N)
    ** B: Batch size
    ** N: Number of parameters
    ** max_iter: Max CG iterations
    ** reg: Regularization parameter
    ** tol: Tolerance for convergence
    */
    RING_FUNC(qalam_solver_cg_tdvp) {
        if (RING_API_PARACOUNT < 8) {
            RING_API_ERROR("qalam_solver_cg_tdvp requires 8 params");
            return;
        }
        
        double* O = (double*)(size_t)RING_API_GETNUMBER(1); // Jacobian matrix (B x N)
        double* F = (double*)(size_t)RING_API_GETNUMBER(2); // Force vector (N)
        double* x = (double*)(size_t)RING_API_GETNUMBER(3); // Result vector (N)
        int B = (int)RING_API_GETNUMBER(4);                 // Batch size
        int N = (int)RING_API_GETNUMBER(5);                 // Number of parameters
        int max_iter = (int)RING_API_GETNUMBER(6);          // Max CG iterations
        double tol = RING_API_GETNUMBER(7);                 // Tolerance
        double reg = RING_API_GETNUMBER(8);                 // Regularization (Diagonal shift)

        std::vector<double> r(N);
        std::vector<double> p(N);
        std::vector<double> Ap(N);
        
        // Initial state x = 0
        memset(x, 0, N * sizeof(double));
        
        // r = F - S*x = F (since x = 0)
        memcpy(r.data(), F, N * sizeof(double));
        memcpy(p.data(), F, N * sizeof(double));

        double rsold = 0;
        #pragma omp parallel for reduction(+:rsold)
        for (int i = 0; i < N; i++) rsold += r[i] * r[i];

        int iter = 0;
        for (iter = 0; iter < max_iter; iter++) {
            apply_s_matrix(O, p.data(), Ap.data(), B, N, reg);

            double pAp = 0;
            #pragma omp parallel for reduction(+:pAp)
            for (int i = 0; i < N; i++) pAp += p[i] * Ap[i];

            double alpha = pAp > 1e-15 ? rsold / pAp : 0.0;

            double rsnew = 0;
            #pragma omp parallel for reduction(+:rsnew)
            for (int i = 0; i < N; i++) {
                x[i] += alpha * p[i];
                r[i] -= alpha * Ap[i];
                rsnew += r[i] * r[i];
            }

            if (sqrt(rsnew) < tol) break;

            double p_scale = rsnew / rsold;
            #pragma omp parallel for
            for (int i = 0; i < N; i++) {
                p[i] = r[i] + p_scale * p[i];
            }
            rsold = rsnew;
        }

        RING_API_RETNUMBER((double)iter);
    }

    // ==========================================
    // 2. QalamInk Controls (String Builder)
    // ==========================================
    
    RING_FUNC(qalam_ink_init) {
        QalamInk *p = new QalamInk();
        // Removed reserve() to be safe, std::string handles it fine
        RING_API_RETMANAGEDCPOINTER(p, "QalamInk", qink_free);
    }
    
    // Append: ink.append(str)
    RING_FUNC(qalam_ink_append) {
        // Ignore type check for safety (Trust the pointer)
        RING_API_IGNORECPOINTERTYPE;
        
        if (!RING_API_ISCPOINTER(1)) {
            RING_API_ERROR("Ink Append: Param 1 is not a pointer");
            return;
        }

        QalamInk *p = (QalamInk*)RING_API_GETCPOINTER(1, "QalamInk");
        
        if (!p) {
            RING_API_ERROR("Ink Append: Pointer is NULL");
            return;
        }

        if (RING_API_ISSTRING(2)) {
            const char* s = RING_API_GETSTRING(2);
            int len = RING_API_GETSTRINGSIZE(2);
            try {
                p->text.append(s, len);
            } catch(...) {
                RING_API_ERROR("Ink Append: C++ Exception");
            }
        }
    }
    
    // Get: str = ink.get()
    RING_FUNC(qalam_ink_get) {
        RING_API_IGNORECPOINTERTYPE;
        QalamInk *p = (QalamInk*)RING_API_GETCPOINTER(1, "QalamInk");
        if (p) RING_API_RETSTRING(p->text.c_str());
    }
    
    // Clear: ink.clear()
    RING_FUNC(qalam_ink_clear) {
        RING_API_IGNORECPOINTERTYPE;
        QalamInk *p = (QalamInk*)RING_API_GETCPOINTER(1, "QalamInk");
        if (p) p->text.clear();
    }

    /*
    ** Batch Append 
    ** Appends a list of strings in one go inside C++.
    */
    RING_FUNC(qalam_ink_append_batch) {
        QalamInk *p = (QalamInk*)RING_API_GETCPOINTER(1, "QalamInk");
        if (!p) return;

        if (!RING_API_ISLIST(2)) {
            RING_API_ERROR("Param 2 must be a List");
            return;
        }

        List *pList = RING_API_GETLIST(2);
        int nSize = ring_list_getsize(pList);

        // Loop inside C++ (Zero Overhead)
        for(int i = 1; i <= nSize; i++) {
            if (ring_list_isstring(pList, i)) {
                // Get raw string pointer and size directly
                char *cStr = ring_list_getstring(pList, i);
                int nLen = ring_list_getstringsize(pList, i);
                
                // Direct append
                p->text.append(cStr, nLen);
            }
        }
    }
    // Size: n = ink.size()
    RING_FUNC(qalam_ink_size) {
        QalamInk *p = (QalamInk*)RING_API_GETCPOINTER(1, "QalamInk");
        RING_API_RETNUMBER(p ? (double)p->text.size() : 0.0);
    }

    
    // ==========================================
    // 3. QalamIndex Controls (Map)
    // ==========================================
    
    RING_FUNC(qalam_index_init) {
        QalamIndex *p = new QalamIndex();
        RING_API_RETMANAGEDCPOINTER(p, "QalamIndex", qindex_free);
    }
    
    /* Upgrade 5: Set uses operator[] which still needs std::string for insertion.
    ** This is unavoidable (insertion requires owning the key).
    ** But lookups below are now zero-alloc via string_view. */
    RING_FUNC(qalam_index_set) {
        QalamIndex *p = (QalamIndex*)RING_API_GETCPOINTER(1, "QalamIndex");
        if(p) p->map[std::string(RING_API_GETSTRING(2))] = RING_API_GETNUMBER(3);
    }
    
    /* Upgrade 5: find() now takes string_view directly (zero-alloc lookup).
    ** The transparent StringHash computes hash on the view, and std::equal_to<>
    ** compares std::string == std::string_view without conversion. */
    RING_FUNC(qalam_index_get) {
        QalamIndex *p = (QalamIndex*)RING_API_GETCPOINTER(1, "QalamIndex");
        if(!p) { RING_API_RETNUMBER(0.0); return; }
        
        std::string_view key(RING_API_GETSTRING(2));
        auto it = p->map.find(key);
        RING_API_RETNUMBER(it != p->map.end() ? it->second : 0.0);
    }

    // Get: val = key.get(index)
    RING_FUNC(qalam_key_get) {
    QalamIndex *p = (QalamIndex*)RING_API_GETCPOINTER(1, "QalamIndex");
    if(!p) { 
        RING_API_RETSTRING(""); 
        return; 
    }
    
    double nTargetID = RING_API_GETNUMBER(2);
    
    // Reverse search using auto iterator
    for (auto it = p->map.begin(); it != p->map.end(); ++it) {
            if (it->second == nTargetID) {
                RING_API_RETSTRING(it->first.c_str());
                return;
            }
        }
        
        RING_API_RETSTRING(""); 
    }
    
    // Size: n = index.size()
    RING_FUNC(qalam_index_size) {
        QalamIndex *p = (QalamIndex*)RING_API_GETCPOINTER(1, "QalamIndex");
        RING_API_RETNUMBER(p ? (double)p->map.size() : 0.0);
    }

    /* Upgrade 5: count() now takes string_view (zero-alloc existence check).
    ** No std::string construction needed — string_view wraps the
    ** existing const char* from RING_API_GETSTRING in-place. */
    RING_FUNC(qalam_index_exists) {
        QalamIndex *p = (QalamIndex*)RING_API_GETCPOINTER(1, "QalamIndex");
        std::string_view key(RING_API_GETSTRING(2));
        if (p && p->map.count(key)) {
            RING_API_RETNUMBER(1.0);
        } else {
            RING_API_RETNUMBER(0.0);
        }
    }

    /*
    ** Batch Define (The Fast Indexer)
    ** Defines multiple keys from a list in one go.
    ** Params: 1. Index, 2. List, 3. Value (default 1), 4. Min Length (default 4), 5. Transform (0=None, 1=Reverse)
    */
    RING_FUNC(qalam_index_define_from_list) {
        QalamIndex *p = (QalamIndex*)RING_API_GETCPOINTER(1, "QalamIndex");
        if (!p) return;

        if (!RING_API_ISLIST(2)) {
            RING_API_ERROR("Param 2 must be a List");
            return;
        }

        List *pList = RING_API_GETLIST(2);
        int nSize = ring_list_getsize(pList);
        double nValue = (RING_API_PARACOUNT >= 3) ? RING_API_GETNUMBER(3) : 1.0;
        int nMinLen = (RING_API_PARACOUNT >= 4) ? (int)RING_API_GETNUMBER(4) : 0;
        int nTransform = (RING_API_PARACOUNT >= 5) ? (int)RING_API_GETNUMBER(5) : 0;

        // Pre-allocate map if possible
        if (nSize > 1000) p->map.reserve(p->map.size() + nSize);

        for(int i = 1; i <= nSize; i++) {
            if (ring_list_isstring(pList, i)) {
                char *cStr = ring_list_getstring(pList, i);
                int nLen = ring_list_getstringsize(pList, i);
                if (nLen > nMinLen) {
                    std::string word(cStr, nLen);
                    if (nTransform == 1) {
                        std::reverse(word.begin(), word.end());
                    }
                    p->map[word] = nValue;
                }
            }
        }
    }

    /*
    ** Fast Key Listing
    ** Returns all keys in the index as a List.
    */
    RING_FUNC(qalam_index_keys) {
        QalamIndex *p = (QalamIndex*)RING_API_GETCPOINTER(1, "QalamIndex");
        if (!p) return;

        List *pList = RING_API_NEWLIST;
        for (auto it = p->map.begin(); it != p->map.end(); ++it) {
            ring_list_addstring(pList, it->first.c_str());
        }
        RING_API_RETLIST(pList);
    }

    /*
    ** Set Intersection (Generalized)
    ** Upgrade 5: Uses count() with string_view from iterator->first.
    ** Since the key from map iteration is already std::string, and our
    ** transparent hash accepts it natively, no extra alloc occurs.
    */
    RING_FUNC(qalam_index_intersect) {
        QalamIndex *p1 = (QalamIndex*)RING_API_GETCPOINTER(1, "QalamIndex");
        QalamIndex *p2 = (QalamIndex*)RING_API_GETCPOINTER(2, "QalamIndex");
        if (!p1 || !p2) return;

        List *pResult = RING_API_NEWLIST;
        
        /* Iterate over the smaller map for performance */
        if (p1->map.size() > p2->map.size()) {
            QalamIndex *temp = p1;
            p1 = p2;
            p2 = temp;
        }

        for (auto it = p1->map.begin(); it != p1->map.end(); ++it) {
            /* string_view lookup in the other map — zero alloc */
            if (p2->map.count(std::string_view(it->first))) {
                ring_list_addstring(pResult, it->first.c_str());
            }
        }
        RING_API_RETLIST(pResult);
    }


    // =============================================================
    // 2. DIRECT I/O (Disk Speed)
    // =============================================================

    RING_FUNC(qalam_index_save_binary) {
        QalamIndex *p = (QalamIndex*)RING_API_GETCPOINTER(1, "QalamIndex");
        const char *cFile = RING_API_GETSTRING(2);
        if(!p) return;

        FILE *fp = fopen(cFile, "wb");
        if (!fp) { RING_API_ERROR("Cannot open file for writing"); return; }

        size_t nCount = p->map.size();
        fwrite(&nCount, sizeof(size_t), 1, fp);

        // [token, id]
        for (auto it = p->map.begin(); it != p->map.end(); ++it) {
            const std::string& token = it->first;
            double id = it->second;

            size_t nLen = token.length();
            fwrite(&nLen, sizeof(size_t), 1, fp);
            fwrite(token.c_str(), 1, nLen, fp);
            fwrite(&id, sizeof(double), 1, fp);
        }

        fclose(fp);
    }
    // ============================================================
    // 2. Load the Map (Index) from a binary file
    // Format: [Total Count] then for each element: [Text Length][Text][Number]
    // ============================================================
    RING_FUNC(qalam_index_load_binary) {
        QalamIndex *p = (QalamIndex*)RING_API_GETCPOINTER(1, "QalamIndex");
        const char *cFile = RING_API_GETSTRING(2);
        if(!p) return;

        FILE *fp = fopen(cFile, "rb");
        if (!fp) { RING_API_ERROR("Cannot open file for reading"); return; }

        // 1. Read the total number of items
        size_t nCount;
        if(fread(&nCount, sizeof(size_t), 1, fp) != 1) { fclose(fp); return; }

        p->map.clear();
        // Reserve space for faster insertion
        p->map.reserve(nCount);

        for (size_t i = 0; i < nCount; ++i) {
            // 1. Read the text length
            size_t nLen;
            fread(&nLen, sizeof(size_t), 1, fp);

            // 2. Read the text (using temporary buffer)
            std::string token(nLen, ' ');
            fread(&token[0], 1, nLen, fp);

            // 3. Read the associated number (ID)
            double id;
            fread(&id, sizeof(double), 1, fp);

            // 4. Insert into the map
            p->map[token] = id;
        }

        fclose(fp);
    }
    
    // ==========================================
    // 4. Formula Engine
    // ==========================================

    RING_FUNC(qalam_formula_init) {
        QalamFormulaWrapper *p = new QalamFormulaWrapper();
        if (RING_API_PARACOUNT >= 1 && RING_API_ISSTRING(1)) {
            // Use the compiler logic
            FormulaCompiler compiler;
            compiler.compile(RING_API_GETSTRING(1));
            p->program = compiler.program; // Copy instructions
        }
        RING_API_RETMANAGEDCPOINTER(p, "QalamFormula", qformula_free);
    }

    /*
    ** Apply Formula: vec[i] = formula(vec[i])
    ** High-Performance Stack Machine inside OpenMP Loop
    */
    RING_FUNC(qalam_formula_apply) {
        QalamFormulaWrapper *pF = (QalamFormulaWrapper*)RING_API_GETCPOINTER(1, "QalamFormula");
        QalamVector  *pV = (QalamVector*)RING_API_GETCPOINTER(2, "QalamVector");
        
        if (!pF || !pV) return;
        if (pV->data.size() == 0 && pV->nReservedSize > 0) {
            pV->data.resize(pV->nReservedSize, 0.0);
        }
        size_t n = pV->data.size();
        double* data = pV->data.data();
        size_t i;
        
        const Instruction* prog = pF->program.data();
        size_t prog_len = pF->program.size();

        #pragma omp parallel for if(n > 5000) private(i)
        for (i = 0; i < n; i++) {
            double stack[16]; 
            int sp = 0;
            double x = data[i];
            
            for (size_t k = 0; k < prog_len; k++) {
                const Instruction& inst = prog[k];
                
                switch (inst.opcode) {
                    // Arithmetic
                    case Q_OP_PUSH_VAL: stack[sp++] = inst.value; break;
                    case Q_OP_PUSH_X:   stack[sp++] = x; break;
                    case Q_OP_ADD:      sp--; stack[sp-1] += stack[sp]; break;
                    case Q_OP_SUB:      sp--; stack[sp-1] -= stack[sp]; break;
                    case Q_OP_MUL:      sp--; stack[sp-1] *= stack[sp]; break;
                    case Q_OP_DIV:      sp--; stack[sp-1] /= stack[sp]; break;
                    case Q_OP_POW:      sp--; stack[sp-1] = pow(stack[sp-1], stack[sp]); break;
                    
                    // Functions (Unary Operations)
                    // They take 1 item from stack and replace it
                    case Q_OP_SIN:  stack[sp-1] = sin(stack[sp-1]); break;
                    case Q_OP_COS:  stack[sp-1] = cos(stack[sp-1]); break;
                    case Q_OP_TAN:  stack[sp-1] = tan(stack[sp-1]); break;
                    case Q_OP_ABS:  stack[sp-1] = fabs(stack[sp-1]); break;
                    case Q_OP_SQRT: stack[sp-1] = sqrt(stack[sp-1]); break;
                    case Q_OP_LOG:  stack[sp-1] = log(stack[sp-1]); break;
                    case Q_OP_EXP:  stack[sp-1] = exp(stack[sp-1]); break;
                    case Q_OP_RELU: 
                        if (stack[sp-1] < 0) stack[sp-1] = 0; 
                        break;
                }
            }
            
            if (sp > 0) data[i] = stack[0];
        }
    }

    // ==========================================
    // 5. PDF Extraction (Quick & Light)
    // ==========================================
    RING_FUNC(qalam_pdf_extract_text) {
        if (RING_API_PARACOUNT != 1 || !RING_API_ISSTRING(1)) {
            RING_API_ERROR("extract_pdf_text requires 1 string parameter (file path)");
            return;
        }
        const char* cFile = RING_API_GETSTRING(1);
        std::string text = extract_pdf_basic(cFile);
        RING_API_RETSTRING(text.c_str());
    }

    // ==========================================
    // 6. QalamLibInit (Init)
    // ==========================================
    
    RING_LIBINIT {
        // Timer
        RING_API_REGISTER("qalam_timer_init", qalam_timer_init);
        RING_API_REGISTER("qalam_timer_reset", qalam_timer_reset);
        RING_API_REGISTER("qalam_timer_elapsed_ns", qalam_timer_elapsed_ns);

        // Vector
        RING_API_REGISTER("qalam_vector_init", qalam_vector_init);
        RING_API_REGISTER("qalam_vector_add", qalam_vector_add);
        RING_API_REGISTER("qalam_vector_get", qalam_vector_get);
        RING_API_REGISTER("qalam_vector_size", qalam_vector_size);
        RING_API_REGISTER("qalam_vector_run_loop", qalam_vector_run_loop);
        RING_API_REGISTER("qalam_vector_get_ptr", qalam_vector_get_ptr);
        RING_API_REGISTER("qalam_vector_set", qalam_vector_set);
        RING_API_REGISTER("qalam_vector_clear", qalam_vector_clear);
        RING_API_REGISTER("qalam_vector_reserve", qalam_vector_reserve);
        RING_API_REGISTER("qalam_vector_resize", qalam_vector_resize);
        RING_API_REGISTER("qalam_vector_load_from_ptr", qalam_vector_load_from_ptr);
        RING_API_REGISTER("qalam_vector_append_from_ptr", qalam_vector_append_from_ptr);
        RING_API_REGISTER("qalam_vector_copy_segment", qalam_vector_copy_segment);
        RING_API_REGISTER("qalam_vector_stream", qalam_vector_stream);

        RING_API_REGISTER("qalam_vector_process", qalam_vector_process);
        RING_API_REGISTER("qalam_vector_copy", qalam_vector_copy);
        RING_API_REGISTER("qalam_vector_save_binary", qalam_vector_save_binary);
        RING_API_REGISTER("qalam_vector_load_binary", qalam_vector_load_binary);
       
        // Ink
        RING_API_REGISTER("qalam_ink_init", qalam_ink_init);
        RING_API_REGISTER("qalam_ink_append", qalam_ink_append);
        RING_API_REGISTER("qalam_ink_get", qalam_ink_get);
        RING_API_REGISTER("qalam_ink_clear", qalam_ink_clear);
        RING_API_REGISTER("qalam_ink_append_batch", qalam_ink_append_batch);
        RING_API_REGISTER("qalam_ink_size", qalam_ink_size);

        // Index
        RING_API_REGISTER("qalam_index_init", qalam_index_init);
        RING_API_REGISTER("qalam_index_set", qalam_index_set);
        RING_API_REGISTER("qalam_index_get", qalam_index_get);
        RING_API_REGISTER("qalam_key_get", qalam_key_get);
        RING_API_REGISTER("qalam_index_exists", qalam_index_exists);
        RING_API_REGISTER("qalam_index_size", qalam_index_size);
        RING_API_REGISTER("qalam_index_save_binary", qalam_index_save_binary);
        RING_API_REGISTER("qalam_index_load_binary", qalam_index_load_binary);
        RING_API_REGISTER("qalam_index_define_from_list", qalam_index_define_from_list);
        RING_API_REGISTER("qalam_index_keys", qalam_index_keys);
        RING_API_REGISTER("qalam_index_intersect", qalam_index_intersect);

        // Formula
        RING_API_REGISTER("qalam_formula_init", qalam_formula_init);
        RING_API_REGISTER("qalam_formula_apply", qalam_formula_apply);
        
        // PDF
        RING_API_REGISTER("qalam_pdf_extract_text", qalam_pdf_extract_text);

        RING_API_REGISTER("qalam_solver_cg_tdvp", qalam_solver_cg_tdvp);
    }
}