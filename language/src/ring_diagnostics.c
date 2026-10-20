/*
**  Madar - High-Performance AI-Native Runtime
**  Compiler Feedback Loop & Structured AI-Agent Diagnostics (--json-errors)
**  Copyright (c) 2013-2026 Mahmoud Fayed <msfclipper@yahoo.com>
**  AI-Native Enhancements for Madar Runtime
*/

#include "ring.h"

/*
================================================================================
  Levenshtein Distance for Fuzzy Identifier Suggestion
================================================================================
*/

static int levenshtein_distance(const char *s1, const char *s2) {
	int len1, len2, i, j;
	int d[65][65];
	len1 = (int)strlen(s1);
	len2 = (int)strlen(s2);
	if (len1 > 64 || len2 > 64) return 999;

	for (i = 0; i <= len1; i++) d[i][0] = i;
	for (j = 0; j <= len2; j++) d[0][j] = j;

	for (i = 1; i <= len1; i++) {
		for (j = 1; j <= len2; j++) {
			int cost = (tolower((unsigned char)s1[i - 1]) == tolower((unsigned char)s2[j - 1])) ? 0 : 1;
			int del = d[i - 1][j] + 1;
			int ins = d[i][j - 1] + 1;
			int sub = d[i - 1][j - 1] + cost;
			int min = del < ins ? del : ins;
			d[i][j] = min < sub ? min : sub;
		}
	}
	return d[len1][len2];
}

/*
================================================================================
  JSON String Escaper
================================================================================
*/

RING_API char *ring_diagnostics_escape_json(const char *cInput) {
	size_t len, allocSize, w, r;
	char *pOut;
	if (!cInput) return _strdup("");
	len = strlen(cInput);
	allocSize = len * 3 + 1;
	pOut = (char *)malloc(allocSize);
	if (!pOut) return _strdup("");

	w = 0;
	for (r = 0; r < len; r++) {
		unsigned char c = (unsigned char)cInput[r];
		if (c == '"') {
			pOut[w++] = '\\'; pOut[w++] = '"';
		} else if (c == '\\') {
			pOut[w++] = '\\'; pOut[w++] = '\\';
		} else if (c == '\n') {
			pOut[w++] = '\\'; pOut[w++] = 'n';
		} else if (c == '\r') {
			pOut[w++] = '\\'; pOut[w++] = 'r';
		} else if (c == '\t') {
			pOut[w++] = '\\'; pOut[w++] = 't';
		} else if (c >= 32 && c <= 126) {
			pOut[w++] = (char)c;
		} else {
			pOut[w++] = ' ';
		}
	}
	pOut[w] = '\0';
	return pOut;
}

/*
================================================================================
  Source Snippet Extractor
================================================================================
*/

RING_API char *ring_diagnostics_get_snippet(const char *cFileName, int nTargetLine) {
	FILE *fp;
	char buffer[1024];
	int curLine = 0;
	char *pResult = NULL;
	char *start;
	size_t l;

	if (!cFileName || nTargetLine <= 0) return _strdup("");
	fp = fopen(cFileName, "r");
	if (!fp) return _strdup("");

	while (fgets(buffer, sizeof(buffer), fp)) {
		curLine++;
		if (curLine == nTargetLine) {
			/* Trim trailing newline and carriage returns */
			l = strlen(buffer);
			while (l > 0 && (buffer[l - 1] == '\r' || buffer[l - 1] == '\n')) {
				buffer[l - 1] = '\0';
				l--;
			}
			/* Trim leading whitespace */
			start = buffer;
			while (*start == ' ' || *start == '\t') start++;
			pResult = _strdup(start);
			break;
		}
	}
	fclose(fp);
	return pResult ? pResult : _strdup("");
}

/*
================================================================================
  Intelligent AI Hint & Actionable Fix Generator
================================================================================
*/

RING_API const char *ring_diagnostics_generate_hint(const char *cStage, const char *cCode, const char *cMsg, const char *cExtra) {
	if (!cMsg) return "Inspect the source code at this location.";

	/* 1. Tensor Dimension & Math Errors */
	if (strstr(cMsg, "Shapes must match")) {
		return "Element-wise tensor operations require identical shapes. Use tensor_shape(t) to check dimensions, or tensor_reshape() to adapt shapes.";
	}
	if (strstr(cMsg, "Incompatible matrix dimensions")) {
		return "Matrix multiplication (matmul) requires the inner dimensions to match: (M x K) * (K x N) -> (M x N). Consider transposing or reshaping one of the operands.";
	}
	if (strstr(cMsg, "Indices out of bounds")) {
		return "Tensor index exceeds bounds. Note that in Madar/Ring, tensor indices are 1-based (ranging from 1 to N), not 0-based.";
	}

	/* 2. Uninitialized Variable */
	if (strstr(cMsg, "Using uninitialized variable") || (cCode && strcmp(cCode, "R24") == 0)) {
		return "Variable was referenced before being assigned. Check for typos or ensure the variable is defined and initialized earlier in the scope.";
	}

	/* 3. Function or Method Not Found */
	if (strstr(cMsg, "Calling Function that is not found") || (cCode && strcmp(cCode, "R2") == 0)) {
		return "Function was not found in the global functions map. If this function belongs to a library or extension, make sure to add: load '<module>.ring'.";
	}
	if (strstr(cMsg, "Calling Method that is not found") || (cCode && strcmp(cCode, "R3") == 0)) {
		return "Method is not defined in the class of the target object. Check class declaration or method spelling.";
	}

	/* 4. Arithmetic & Memory Safety */
	if (strstr(cMsg, "Division by zero") || (cCode && strcmp(cCode, "R11") == 0)) {
		return "Division by zero encountered. Add a guard check before dividing (e.g., if divisor != 0 ... ok).";
	}
	if (strstr(cMsg, "Stack Overflow") || (cCode && strcmp(cCode, "R14") == 0)) {
		return "Stack overflow: maximum recursion depth exceeded. Verify that recursive calls have a valid base case that terminates.";
	}
	if (strstr(cMsg, "NULL Pointer") || (cCode && strcmp(cCode, "R1") == 0)) {
		return "NULL pointer dereference. Ensure objects or resources are properly created before use.";
	}
	if (strstr(cMsg, "Substr Error") || (cCode && strcmp(cCode, "R28") == 0)) {
		return "List or string index out of range. Note that indices in Ring are 1-based (from 1 to len(item)).";
	}

	/* 5. Parser / Grammar Rule Errors */
	if (strstr(cMsg, "Missing 'ok'") || strstr(cMsg, "ok") != NULL) {
		return "In Ring syntax, every 'if' statement must end with 'ok'. Example: if condition ... ok.";
	}
	if (strstr(cMsg, "Missing 'next'") || strstr(cMsg, "next") != NULL) {
		return "In Ring syntax, every 'for' loop must end with 'next'. Example: for i = 1 to 10 ... next.";
	}
	if (strstr(cMsg, "Missing 'end'") || strstr(cMsg, "end") != NULL) {
		return "Block definition (func, class, package) is missing closing 'end' or '}'.";
	}
	if (strstr(cMsg, "Parentheses ')' is missing")) {
		return "Unbalanced opening parenthesis '('. Ensure all opened parentheses are properly closed with ')'.";
	}
	if (strstr(cMsg, "Brackets ']' is missing")) {
		return "Unbalanced opening bracket '['. Ensure all list literals and index expressions have a matching ']'.";
	}
	if (strstr(cMsg, "Literal not closed") || (cCode && strcmp(cCode, "S1") == 0)) {
		return "String literal was not terminated. Add a matching closing quote (\", ', or `).";
	}
	if (strstr(cMsg, "Unclosed comment") || (cCode && strcmp(cCode, "S2") == 0)) {
		return "Multi-line comment was not terminated. Add '*/' to close the comment.";
	}

	return "Review the syntax and ensure all expressions and identifiers are valid.";
}

/*
================================================================================
  Check if JSON Error Reporting is Enabled
================================================================================
*/

RING_API bool ring_diagnostics_is_json_enabled(RingState *pRingState) {
	if (pRingState && pRingState->lJSONErrors) return true;
	const char *env = getenv("MADAR_JSON_ERRORS");
	if (env && (strcmp(env, "1") == 0 || strcmp(env, "true") == 0)) return true;
	return false;
}

/*
================================================================================
  Report Scanner Error (JSON)
================================================================================
*/

RING_API void ring_diagnostics_report_scanner_error(Scanner *pScanner, const char *cCode, const char *cMsg, int nLine) {
	RingState *pRingState = pScanner->pRingState;
	const char *cFile = "";
	if (ring_list_getsize(pRingState->pRingFilesList) > 0) {
		cFile = ring_list_getstring(pRingState->pRingFilesList, ring_list_getsize(pRingState->pRingFilesList));
	}

	char *snippet = ring_diagnostics_get_snippet(cFile, nLine);
	char *escFile = ring_diagnostics_escape_json(cFile);
	char *escMsg = ring_diagnostics_escape_json(cMsg);
	char *escSnippet = ring_diagnostics_escape_json(snippet);
	const char *hint = ring_diagnostics_generate_hint("scanner", cCode, cMsg, NULL);
	char *escHint = ring_diagnostics_escape_json(hint);

	printf("\n{\n");
	printf("  \"madar_error\": {\n");
	printf("    \"status\": \"error\",\n");
	printf("    \"stage\": \"scanner\",\n");
	printf("    \"error_code\": \"%s\",\n", cCode ? cCode : "S1");
	printf("    \"message\": \"%s\",\n", escMsg);
	printf("    \"file\": \"%s\",\n", escFile);
	printf("    \"line\": %d,\n", nLine);
	printf("    \"source_snippet\": \"%s\",\n", escSnippet);
	printf("    \"hint\": \"%s\",\n", escHint);
	printf("    \"call_stack\": []\n");
	printf("  }\n");
	printf("}\n\n");
	fflush(stdout);

	free(snippet);
	free(escFile);
	free(escMsg);
	free(escSnippet);
	free(escHint);
}

/*
================================================================================
  Report Parser Error (JSON)
================================================================================
*/

RING_API void ring_diagnostics_report_parser_error(Parser *pParser, const char *cCode, const char *cMsg) {
	RingState *pRingState = pParser->pRingState;
	int nRingActiveFile = ring_list_getsize(pRingState->pRingFilesStack);
	const char *cFile = nRingActiveFile > 0 ? ring_list_getstring(pRingState->pRingFilesStack, nRingActiveFile) : "";
	int nLine = pParser->nLineNumber;

	char *snippet = ring_diagnostics_get_snippet(cFile, nLine);
	char *escFile = ring_diagnostics_escape_json(cFile);
	char *escMsg = ring_diagnostics_escape_json(cMsg ? cMsg : "Syntax Error");
	char *escSnippet = ring_diagnostics_escape_json(snippet);
	const char *hint = ring_diagnostics_generate_hint("parser", cCode, cMsg, NULL);
	char *escHint = ring_diagnostics_escape_json(hint);

	printf("\n{\n");
	printf("  \"madar_error\": {\n");
	printf("    \"status\": \"error\",\n");
	printf("    \"stage\": \"parser\",\n");
	printf("    \"error_code\": \"%s\",\n", cCode ? cCode : "P1");
	printf("    \"message\": \"%s\",\n", escMsg);
	printf("    \"file\": \"%s\",\n", escFile);
	printf("    \"line\": %d,\n", nLine);
	printf("    \"source_snippet\": \"%s\",\n", escSnippet);
	printf("    \"hint\": \"%s\",\n", escHint);
	printf("    \"call_stack\": []\n");
	printf("  }\n");
	printf("}\n\n");
	fflush(stdout);

	free(snippet);
	free(escFile);
	free(escMsg);
	free(escSnippet);
	free(escHint);
}

/*
================================================================================
  Report Runtime Error (JSON)
================================================================================
*/

RING_API void ring_diagnostics_report_runtime_error(VM *pVM, const char *cMsg) {
	int nLine = (int)RING_VM_IR_GETLINENUMBER;
	const char *cFile = pVM->cFileName ? pVM->cFileName : "";

	/* Extract Error Code from Message (e.g. "Error (R24): ...") */
	char cCode[16] = "R0";
	const char *pStart = strstr(cMsg, "Error (");
	if (pStart) {
		pStart += 7;
		const char *pEnd = strchr(pStart, ')');
		if (pEnd && (pEnd - pStart < 15)) {
			size_t cLen = pEnd - pStart;
			strncpy(cCode, pStart, cLen);
			cCode[cLen] = '\0';
		}
	} else if (strstr(cMsg, "Shapes must match") || strstr(cMsg, "tensor")) {
		strcpy(cCode, "TENSOR_ERR");
	}

	char *snippet = ring_diagnostics_get_snippet(cFile, nLine);
	char *escFile = ring_diagnostics_escape_json(cFile);
	char *escMsg = ring_diagnostics_escape_json(cMsg);
	char *escSnippet = ring_diagnostics_escape_json(snippet);
	const char *hint = ring_diagnostics_generate_hint("runtime", cCode, cMsg, NULL);
	char *escHint = ring_diagnostics_escape_json(hint);

	printf("\n{\n");
	printf("  \"madar_error\": {\n");
	printf("    \"status\": \"error\",\n");
	printf("    \"stage\": \"runtime\",\n");
	printf("    \"error_code\": \"%s\",\n", cCode);
	printf("    \"message\": \"%s\",\n", escMsg);
	printf("    \"file\": \"%s\",\n", escFile);
	printf("    \"line\": %d,\n", nLine);
	printf("    \"source_snippet\": \"%s\",\n", escSnippet);
	printf("    \"hint\": \"%s\",\n", escHint);
	printf("    \"call_stack\": [\n");

	bool firstFrame = true;
	int x;
	FuncCall *pFuncCall;
	const char *fName, *fFile;
	int fLine;
	char *escFName, *escFFile;

	for (x = RING_VM_FUNCCALLSCOUNT; x >= 1; x--) {
		pFuncCall = RING_VM_GETFUNCCALL(x);
		if (pFuncCall->nCallerPC == 0) continue;
		if (pFuncCall->nType == RING_FUNCTYPE_SCRIPT) {
			fName = pFuncCall->cName ? (const char *)pFuncCall->cName : "";
			fFile = pFuncCall->cNewFileName ? (const char *)pFuncCall->cNewFileName : "";
			fLine = pFuncCall->nLineNumber;

			escFName = ring_diagnostics_escape_json(fName);
			escFFile = ring_diagnostics_escape_json(fFile);

			if (!firstFrame) printf(",\n");
			printf("      {\"function\": \"%s\", \"file\": \"%s\", \"line\": %d}", escFName, escFFile, fLine);
			firstFrame = false;

			free(escFName);
			free(escFFile);
		}
	}

	printf("\n    ]\n");
	printf("  }\n");
	printf("}\n\n");
	fflush(stdout);

	free(snippet);
	free(escFile);
	free(escMsg);
	free(escSnippet);
	free(escHint);
}
