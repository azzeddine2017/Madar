/*
**  Madar - AI & Dynamic Programming Language
**  Ring JIT Subsystem (powered by SLJIT)
**  2026, Azzeddine Remmal / Madar Project
*/

#ifndef ring_jit_h
#define ring_jit_h

#include <stdint.h>

/* JIT Compiler Status and Capabilities */
typedef struct RingJIT {
    unsigned int lEnabled : 1;
    unsigned int lVerbose : 1;
    unsigned int nCompiledLoops;
    unsigned int nJITExecutions;
} RingJIT;

/* Public API */
RING_API void ring_jit_init(void *pRingState);
RING_API void ring_jit_destroy(void *pRingState);
RING_API int ring_jit_is_available(void);

/* Auto Loop JIT Subsystem */
#define RING_JIT_OP_NONE   0
#define RING_JIT_OP_SUM_SQ 1  /* dest += x * x  or  dest = dest + x * x */
#define RING_JIT_OP_SUM_X  2  /* dest += x      or  dest = dest + x */
#define RING_JIT_OP_INC    3  /* dest++         or  dest += 1 */

RING_API int ring_jit_try_execute_for_loop(void *pVMVoid, double nStart, double nEnd, double nStep, int nExitPC);
RING_API unsigned int ring_jit_get_auto_loops_count(void);

/* Test JIT Compilation: Computes sum of squares (1..N) purely in native machine code */
typedef int64_t (*ring_jit_sumsq_func)(int64_t nLimit);
RING_API ring_jit_sumsq_func ring_jit_compile_sumsq_test(void);
RING_API void ring_jit_free_func(void *pFunc);

#endif
