/*
**  Madar - High-Performance AI-Native Runtime
**  Compiler Feedback Loop & Structured AI-Agent Diagnostics (--json-errors)
*/

#ifndef ring_diagnostics_h
#define ring_diagnostics_h

#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

/* Forward declarations */
struct RingState;
struct VM;
struct Parser;
struct Scanner;

/* Diagnostics Entry Points */
RING_API void ring_diagnostics_init(struct RingState *pRingState);
RING_API bool ring_diagnostics_is_json_enabled(struct RingState *pRingState);

/* Error Reporting APIs */
RING_API void ring_diagnostics_report_scanner_error(struct Scanner *pScanner, const char *cCode, const char *cMsg, int nLine);
RING_API void ring_diagnostics_report_parser_error(struct Parser *pParser, const char *cCode, const char *cMsg);
RING_API void ring_diagnostics_report_runtime_error(struct VM *pVM, const char *cMsg);

/* Helper Utilities */
RING_API char *ring_diagnostics_get_snippet(const char *cFileName, int nTargetLine);
RING_API char *ring_diagnostics_escape_json(const char *cInput);
RING_API const char *ring_diagnostics_generate_hint(const char *cStage, const char *cCode, const char *cMsg, const char *cExtra);
RING_API const char *ring_diagnostics_generate_fix(const char *cStage, const char *cCode, const char *cMsg, const char *cExtra);

#endif /* ring_diagnostics_h */
