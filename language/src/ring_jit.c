/*
**  Madar - AI & Dynamic Programming Language
**  Ring JIT Subsystem (powered by SLJIT)
**  2026, Azzeddine Remmal / Madar Project
*/

#include "ring.h"
#include "ring_jit.h"

/* Embed the SLJIT single-translation-unit engine */
#include "sljit_src/sljitLir.c"

static int s_lJITAvailable = 1;
static unsigned int s_nAutoJITLoopsCount = 0;

typedef int64_t (*ring_jit_kernel_fn)(int64_t nInitial, int64_t nStart, int64_t nEnd, int64_t nStep);

static ring_jit_kernel_fn s_pKernelSumSq = NULL;
static ring_jit_kernel_fn s_pKernelSumX  = NULL;
static ring_jit_kernel_fn s_pKernelInc   = NULL;

RING_API void ring_jit_init(void *pRingState) {
    (void)pRingState;
    s_lJITAvailable = 1;
}

RING_API void ring_jit_destroy(void *pRingState) {
    (void)pRingState;
    if (s_pKernelSumSq) {
        sljit_free_code((void *)s_pKernelSumSq, NULL);
        s_pKernelSumSq = NULL;
    }
    if (s_pKernelSumX) {
        sljit_free_code((void *)s_pKernelSumX, NULL);
        s_pKernelSumX = NULL;
    }
    if (s_pKernelInc) {
        sljit_free_code((void *)s_pKernelInc, NULL);
        s_pKernelInc = NULL;
    }
}

RING_API int ring_jit_is_available(void) {
    return s_lJITAvailable;
}

RING_API unsigned int ring_jit_get_auto_loops_count(void) {
    return s_nAutoJITLoopsCount;
}

/*
**  Compile a native machine code kernel for tight loop execution:
**  int64_t kernel(int64_t nInitial, int64_t nStart, int64_t nEnd, int64_t nStep)
*/
static ring_jit_kernel_fn ring_jit_compile_kernel(int nOpType) {
    struct sljit_compiler *C;
    struct sljit_label *loop_start;
    struct sljit_label *loop_end;
    struct sljit_jump *out_jump;
    struct sljit_jump *back_jump;
    void *code;

    C = sljit_create_compiler(NULL);
    if (!C) return NULL;

    /*
    ** Function Entry:
    ** Return type: Word (64-bit int)
    ** Arg 1: nInitial (in SLJIT_S0)
    ** Arg 2: nStart   (in SLJIT_S1)
    ** Arg 3: nEnd     (in SLJIT_S2)
    ** Arg 4: nStep    (in SLJIT_S3)
    ** Scratches: 3 (R0 = sum, R1 = x, R2 = temp product)
    ** Saveds: 4 (S0..S3)
    */
    sljit_emit_enter(C, 0, SLJIT_ARGS4(W, W, W, W, W), 3, 4, 0);

    /* sum (R0) = nInitial (S0) */
    sljit_emit_op1(C, SLJIT_MOV, SLJIT_R0, 0, SLJIT_S0, 0);

    /* x (R1) = nStart (S1) */
    sljit_emit_op1(C, SLJIT_MOV, SLJIT_R1, 0, SLJIT_S1, 0);

    /* loop_start: */
    loop_start = sljit_emit_label(C);

    /* if (x > nEnd) goto loop_end */
    out_jump = sljit_emit_cmp(C, SLJIT_SIG_GREATER, SLJIT_R1, 0, SLJIT_S2, 0);

    if (nOpType == RING_JIT_OP_SUM_SQ) {
        /* R2 = x * x */
        sljit_emit_op2(C, SLJIT_MUL, SLJIT_R2, 0, SLJIT_R1, 0, SLJIT_R1, 0);
        /* sum (R0) += R2 */
        sljit_emit_op2(C, SLJIT_ADD, SLJIT_R0, 0, SLJIT_R0, 0, SLJIT_R2, 0);
    } else if (nOpType == RING_JIT_OP_SUM_X) {
        /* sum (R0) += x (R1) */
        sljit_emit_op2(C, SLJIT_ADD, SLJIT_R0, 0, SLJIT_R0, 0, SLJIT_R1, 0);
    } else if (nOpType == RING_JIT_OP_INC) {
        /* sum (R0) += 1 */
        sljit_emit_op2(C, SLJIT_ADD, SLJIT_R0, 0, SLJIT_R0, 0, SLJIT_IMM, 1);
    }

    /* x (R1) += nStep (S3) */
    sljit_emit_op2(C, SLJIT_ADD, SLJIT_R1, 0, SLJIT_R1, 0, SLJIT_S3, 0);

    /* goto loop_start */
    back_jump = sljit_emit_jump(C, SLJIT_JUMP);
    sljit_set_label(back_jump, loop_start);

    /* loop_end: */
    loop_end = sljit_emit_label(C);
    sljit_set_label(out_jump, loop_end);

    /* return sum (R0) */
    sljit_emit_return(C, SLJIT_MOV, SLJIT_R0, 0);

    code = sljit_generate_code(C, 0, NULL);
    sljit_free_compiler(C);
    return (ring_jit_kernel_fn)code;
}

static int ring_jit_streq(const char *s1, const char *s2) {
    if (!s1 || !s2) return 0;
    while (*s1 && *s2) {
        char c1 = (*s1 >= 'A' && *s1 <= 'Z') ? (*s1 + 32) : *s1;
        char c2 = (*s2 >= 'A' && *s2 <= 'Z') ? (*s2 + 32) : *s2;
        if (c1 != c2) return 0;
        s1++;
        s2++;
    }
    return (*s1 == '\0' && *s2 == '\0');
}

/*
**  Auto Loop JIT: Analyze bytecode between nStartPC and nExitPC.
**  If it matches a known hot numeric pattern, compile and execute on CPU directly!
*/
RING_API int ring_jit_try_execute_for_loop(void *pVMVoid, double nStart, double nEnd, double nStep, int nExitPC) {
    VM *pVM = (VM *)pVMVoid;
    int nStartPC = pVM->nPC;
    int nIncPC = 0;
    const char *cLoopVar = NULL;
    const char *cDestVar = NULL;
    int nOpType = RING_JIT_OP_NONE;
    int aOps[32];
    const char *aStrings[32];
    int aInts[32];
    int nOpCount = 0;
    int pc, op;
    List *pVarDest = NULL;
    List *pVarLoop = NULL;
    Item *pItemDest, *pItemLoop;
    ring_jit_kernel_fn pKernel = NULL;
    int64_t nInitial, iStart, iEnd, iStep, nResult;

    if (!s_lJITAvailable) return 0;
    if (nStep != 1.0) return 0;
    /* Find the loop increment instruction: ICO_INCJUMP (or performance-optimized variants) */
    for (pc = nStartPC; pc < nExitPC; pc++) {
        op = pVM->pByteCode[pc - 1].nOPCode;
        if (op == ICO_INCJUMP || op == ICO_INCPJUMP || op == ICO_INCPJUMPSTEP1 ||
            op == ICO_INCLPJUMP || op == ICO_INCLPJUMPSTEP1) {
            nIncPC = pc;
            cLoopVar = (pVM->pByteCode[pc - 1].nReg1Type == RING_VM_REGTYPE_STRING) ? pVM->pByteCode[pc - 1].aReg[0].pString : NULL;
            break;
        }
    }
    if (!nIncPC || !cLoopVar) return 0;
    /* Candidate loop must be a small flat basic block (<= 20 instructions) */
    if ((nIncPC - nStartPC) > 20 || (nIncPC <= nStartPC)) return 0;

    /* Scan instructions inside loop body */
    for (pc = nStartPC; pc < nIncPC; pc++) {
        op = pVM->pByteCode[pc - 1].nOPCode;
        if (op == ICO_NEWLINE || op == ICO_NOOP || op == ICO_NEWLABEL) continue;
        /* Bail out immediately if any call, jump, or complex dynamic control flow is encountered */
        if (op == ICO_CALL || op == ICO_LOADFUNC || op == ICO_LOADFUNCP || op == ICO_LOADMETHOD ||
            op == ICO_JUMP || op == ICO_JUMPZERO || op == ICO_JUMPONE || op == ICO_JUMPFOR ||
            op == ICO_RETURN || op == ICO_RETNULL || op == ICO_RETFROMEVAL ||
            op == ICO_LOOP || op == ICO_EXIT || op == ICO_BYE || op == ICO_NEWOBJ) {
            return 0;
        }
        if (nOpCount >= 28) return 0;
        aOps[nOpCount] = op;
        if ((op == ICO_LOADADDRESS || op == ICO_LOADAFIRST || op == ICO_LOADAPUSHV || op == ICO_PUSHPLOCAL || op == ICO_PUSHP) &&
            (pVM->pByteCode[pc - 1].nReg1Type == RING_VM_REGTYPE_STRING)) {
            aStrings[nOpCount] = pVM->pByteCode[pc - 1].aReg[0].pString;
        } else {
            aStrings[nOpCount] = NULL;
        }
        aInts[nOpCount] = pVM->pByteCode[pc - 1].aReg[0].iNumber;
        nOpCount++;
    }

    /* Semantic Loop Pattern Analyzer */
    if (nOpCount == 3 && (aOps[0] == ICO_LOADADDRESS || aOps[0] == ICO_LOADAFIRST) && aOps[1] == ICO_PLUSPLUS && aOps[2] == ICO_FREESTACK) {
        cDestVar = aStrings[0];
        nOpType = RING_JIT_OP_INC;
    } else if (nOpCount >= 4 && (aOps[0] == ICO_LOADADDRESS || aOps[0] == ICO_LOADAFIRST) && aOps[1] == ICO_ASSIGNMENTPOINTER) {
        cDestVar = aStrings[0];
        int nAssignIdx = -1;
        for (int i = 2; i < nOpCount; i++) {
            if (aOps[i] == ICO_ASSIGNMENT) {
                nAssignIdx = i;
                break;
            }
        }
        if (nAssignIdx >= 3 && (nAssignIdx + 1 < nOpCount) && aOps[nAssignIdx + 1] == ICO_FREESTACK) {
            int nLoadsOfLoop = 0;
            int nLoadsOfDest = 0;
            int nMulOps = 0;
            int nSumOps = 0;
            int nOtherOps = 0;
            int lHasPlusEqual = 0;

            for (int i = 2; i < nAssignIdx; i++) {
                int o = aOps[i];
                if (o == ICO_LOADADDRESS || o == ICO_LOADAPUSHV || o == ICO_PUSHPLOCAL || o == ICO_PUSHP) {
                    if (aStrings[i] && ring_jit_streq(aStrings[i], cLoopVar)) {
                        nLoadsOfLoop++;
                    } else if (aStrings[i] && ring_jit_streq(aStrings[i], cDestVar)) {
                        nLoadsOfDest++;
                    } else {
                        nOtherOps++;
                    }
                } else if (o == ICO_PUSHV) {
                    /* stack value evaluation */
                } else if (o == ICO_BEFOREEQUAL) {
                    if (aInts[i] == OP_PLUSEQUAL) {
                        lHasPlusEqual = 1;
                    } else if (aInts[i] == OP_EQUAL) {
                        /* ignore plain equal */
                    } else {
                        nOtherOps++;
                    }
                } else if (o == ICO_MUL || o == ICO_MULN) {
                    nMulOps++;
                } else if (o == ICO_SUM) {
                    nSumOps++;
                } else {
                    nOtherOps++;
                }
            }

            if (nOtherOps == 0) {
                if (lHasPlusEqual) {
                    if (nLoadsOfDest == 0 && nLoadsOfLoop == 2 && nMulOps == 1 && nSumOps == 0) {
                        nOpType = RING_JIT_OP_SUM_SQ;
                    } else if (nLoadsOfDest == 0 && nLoadsOfLoop == 1 && nMulOps == 0 && nSumOps == 0) {
                        nOpType = RING_JIT_OP_SUM_X;
                    }
                } else {
                    if (nLoadsOfDest == 1 && nLoadsOfLoop == 2 && nMulOps == 1 && nSumOps == 1) {
                        nOpType = RING_JIT_OP_SUM_SQ;
                    } else if (nLoadsOfDest == 1 && nLoadsOfLoop == 1 && nMulOps == 0 && nSumOps == 1) {
                        nOpType = RING_JIT_OP_SUM_X;
                    }
                }
            }
        }
    }

    if (nOpType == RING_JIT_OP_NONE || !cDestVar) return 0;

    /* Resolve VM variables */
    if (ring_vm_findvar(pVM, cDestVar)) {
        pVarDest = (List *)RING_VM_STACK_READP;
        RING_VM_STACK_POP;
    }
    if (ring_vm_findvar(pVM, cLoopVar)) {
        pVarLoop = (List *)RING_VM_STACK_READP;
        RING_VM_STACK_POP;
    }

    if (!pVarDest || !pVarLoop) return 0;
    if (!RING_VAR_ISNUMBER(pVarDest) || !RING_VAR_ISNUMBER(pVarLoop)) return 0;

    pItemDest = RING_VAR_ITEM_VALUE(pVarDest);
    pItemLoop = RING_VAR_ITEM_VALUE(pVarLoop);

    /* Get or compile native JIT kernel */
    if (nOpType == RING_JIT_OP_SUM_SQ) {
        if (!s_pKernelSumSq) s_pKernelSumSq = ring_jit_compile_kernel(RING_JIT_OP_SUM_SQ);
        pKernel = s_pKernelSumSq;
    } else if (nOpType == RING_JIT_OP_SUM_X) {
        if (!s_pKernelSumX) s_pKernelSumX = ring_jit_compile_kernel(RING_JIT_OP_SUM_X);
        pKernel = s_pKernelSumX;
    } else if (nOpType == RING_JIT_OP_INC) {
        if (!s_pKernelInc) s_pKernelInc = ring_jit_compile_kernel(RING_JIT_OP_INC);
        pKernel = s_pKernelInc;
    }

    if (!pKernel) return 0;

    /* Run native machine code directly on CPU hardware */
    nInitial = (int64_t)ring_item_getdouble(pItemDest);
    iStart = (int64_t)nStart;
    iEnd = (int64_t)nEnd;
    iStep = (int64_t)nStep;

    nResult = pKernel(nInitial, iStart, iEnd, iStep);

    /* Synchronize VM memory */
    ring_item_setdouble_gc(pVM->pRingState, pItemDest, (double)nResult);
    ring_item_setdouble_gc(pVM->pRingState, pItemLoop, (double)(iEnd + iStep));

    s_nAutoJITLoopsCount++;
    return 1;
}

/* Benchmark test function (jit_sumsq) */
RING_API ring_jit_sumsq_func ring_jit_compile_sumsq_test(void) {
    struct sljit_compiler *C;
    struct sljit_label *loop_start;
    struct sljit_label *loop_end;
    struct sljit_jump *out_jump;
    struct sljit_jump *back_jump;
    void *code;

    C = sljit_create_compiler(NULL);
    if (!C) return NULL;

    sljit_emit_enter(C, 0, SLJIT_ARGS1(W, W), 3, 1, 0);

    /* sum (R0) = 0 */
    sljit_emit_op1(C, SLJIT_MOV, SLJIT_R0, 0, SLJIT_IMM, 0);

    /* x (R1) = 1 */
    sljit_emit_op1(C, SLJIT_MOV, SLJIT_R1, 0, SLJIT_IMM, 1);

    /* loop_start: */
    loop_start = sljit_emit_label(C);

    /* if (x > nLimit) goto loop_end */
    out_jump = sljit_emit_cmp(C, SLJIT_SIG_GREATER, SLJIT_R1, 0, SLJIT_S0, 0);

    /* R2 = x * x */
    sljit_emit_op2(C, SLJIT_MUL, SLJIT_R2, 0, SLJIT_R1, 0, SLJIT_R1, 0);

    /* sum (R0) += R2 */
    sljit_emit_op2(C, SLJIT_ADD, SLJIT_R0, 0, SLJIT_R0, 0, SLJIT_R2, 0);

    /* x (R1) += 1 */
    sljit_emit_op2(C, SLJIT_ADD, SLJIT_R1, 0, SLJIT_R1, 0, SLJIT_IMM, 1);

    /* goto loop_start */
    back_jump = sljit_emit_jump(C, SLJIT_JUMP);
    sljit_set_label(back_jump, loop_start);

    /* loop_end: */
    loop_end = sljit_emit_label(C);
    sljit_set_label(out_jump, loop_end);

    /* return sum (R0) */
    sljit_emit_return(C, SLJIT_MOV, SLJIT_R0, 0);

    code = sljit_generate_code(C, 0, NULL);
    sljit_free_compiler(C);
    return (ring_jit_sumsq_func)code;
}

RING_API void ring_jit_free_func(void *pFunc) {
    if (pFunc) {
        sljit_free_code(pFunc, NULL);
    }
}
