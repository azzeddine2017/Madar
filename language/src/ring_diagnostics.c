/*
**  Madar - High-Performance AI-Native Runtime
**  Compiler Feedback Loop & Structured AI-Agent Diagnostics (--json-errors)
**  Copyright (c) 2013-2026 Mahmoud Fayed <msfclipper@yahoo.com>
**  Comprehensive AI-Native Enhancements for Madar Runtime
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
  Source Snippet Extractor from Disk
================================================================================
*/

RING_API char *ring_diagnostics_get_snippet(const char *cFileName, int nTargetLine) {
	FILE *fp;
	char buffer[2048];
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
			l = strlen(buffer);
			while (l > 0 && (buffer[l - 1] == '\r' || buffer[l - 1] == '\n')) {
				buffer[l - 1] = '\0';
				l--;
			}
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
  In-Memory / Eval Line Reconstruction from Tokens
================================================================================
*/

static char *rebuild_line_from_tokens(Parser *pParser, int nTargetLine, int *pOutCol, char **ppOutToken) {
	if (!pParser || !pParser->pTokens) return NULL;
	List *pTokens = pParser->pTokens;
	int nTokens = ring_list_getsize(pTokens);
	if (nTokens == 0) return NULL;

	int curLine = 1;
	size_t cap = 512;
	size_t len = 0;
	char *buf = (char *)malloc(cap);
	if (!buf) return NULL;
	buf[0] = '\0';

	int foundActive = 0;
	int activeCol = 1;
	char *activeTokStr = NULL;

	for (int i = 1; i <= nTokens; i++) {
		List *pTok = ring_list_getlist(pTokens, i);
		int nType = ring_list_getint(pTok, RING_SCANNER_TOKENTYPE);
		const char *val = ring_list_getstring(pTok, RING_SCANNER_TOKENVALUE);

		if (nType == SCANNER_TOKEN_ENDLINE) {
			if (curLine == nTargetLine) break;
			curLine++;
			continue;
		}

		if (curLine == nTargetLine) {
			const char *displayVal = val;
			if (nType == SCANNER_TOKEN_KEYWORD && ring_list_getsize(pTok) >= RING_SCANNER_TOKENOPTIONALSTR) {
				const char *opt = ring_list_getstring(pTok, RING_SCANNER_TOKENOPTIONALSTR);
				if (opt && opt[0]) displayVal = opt;
			}

			if (i == (int)pParser->nActiveToken) {
				activeCol = (int)len + 1;
				activeTokStr = _strdup(displayVal ? displayVal : "");
				foundActive = 1;
			}

			size_t tokLen = displayVal ? strlen(displayVal) : 0;
			while (len + tokLen + 4 >= cap) {
				cap *= 2;
				char *newBuf = (char *)realloc(buf, cap);
				if (!newBuf) { free(buf); return NULL; }
				buf = newBuf;
			}

			if (len > 0 && buf[len - 1] != ' ' && buf[len - 1] != '(' && buf[len - 1] != '[' && buf[len - 1] != '{') {
				buf[len++] = ' ';
				buf[len] = '\0';
				if (i == (int)pParser->nActiveToken && !foundActive) {
					activeCol = (int)len + 1;
				}
			}

			if (displayVal) {
				strcpy(buf + len, displayVal);
				len += tokLen;
			}
		}
	}

	if (pOutCol) *pOutCol = activeCol;
	if (ppOutToken) *ppOutToken = activeTokStr ? activeTokStr : _strdup(pParser->cTokenText ? pParser->cTokenText : "");
	return buf;
}

/*
================================================================================
  Visual Marker Generator (e.g. "       ^")
================================================================================
*/

static char *generate_visual_marker(int nColumn) {
	if (nColumn < 1) nColumn = 1;
	char *marker = (char *)malloc(nColumn + 2);
	if (!marker) return _strdup("^");
	for (int i = 0; i < nColumn - 1; i++) {
		marker[i] = ' ';
	}
	marker[nColumn - 1] = '^';
	marker[nColumn] = '\0';
	return marker;
}

/*
================================================================================
  Extract Standard Error Code (C1..C31, S1..S3, R1..R55, E1..E18)
================================================================================
*/

static void extract_standard_code(const char *cMsg, const char *cStage, char *pOut, size_t nMax) {
	if (!pOut || nMax == 0) return;
	pOut[0] = '\0';

	if (cMsg) {
		const char *pStart = strstr(cMsg, "Error (");
		if (pStart) {
			pStart += 7;
			const char *pEnd = strchr(pStart, ')');
			if (pEnd && (size_t)(pEnd - pStart) < nMax) {
				size_t len = pEnd - pStart;
				strncpy(pOut, pStart, len);
				pOut[len] = '\0';
				return;
			}
		}
		if (strstr(cMsg, "Shapes must match") || strstr(cMsg, "tensor") || strstr(cMsg, "Tensor")) {
			strncpy(pOut, "TENSOR_ERR", nMax - 1);
			pOut[nMax - 1] = '\0';
			return;
		}
	}

	if (strcmp(cStage, "scanner") == 0) strncpy(pOut, "S1", nMax - 1);
	else if (strcmp(cStage, "parser") == 0) strncpy(pOut, "C27", nMax - 1);
	else if (strcmp(cStage, "runtime") == 0) strncpy(pOut, "R0", nMax - 1);
	else strncpy(pOut, "GENERIC", nMax - 1);
	pOut[nMax - 1] = '\0';
}

/*
================================================================================
  Intelligent AI Hint & Diagnostic Explanation Generator
================================================================================
*/

RING_API const char *ring_diagnostics_generate_hint(const char *cStage, const char *cCode, const char *cMsg, const char *cExtra) {
	if (!cCode) return "Inspect the source code at this location.";

	/* ---- Compiler Errors (C1 - C31) ---- */
	if (strcmp(cCode, "C1") == 0) return "Parameter lists in function definitions must contain valid variable identifiers separated by commas.";
	if (strcmp(cCode, "C2") == 0) return "Class name must be a valid, unquoted identifier.";
	if (strcmp(cCode, "C3") == 0) return "In Ring syntax, every 'if' control block must be closed with 'ok' or a closing brace '}'.";
	if (strcmp(cCode, "C4") == 0) return "Block definition (func, class, package) is missing its closing 'end' or '}'.";
	if (strcmp(cCode, "C5") == 0) return "In Ring syntax, every 'for' or 'dour' loop must end with 'next' or a closing brace '}'.";
	if (strcmp(cCode, "C6") == 0) return "Function name must be a valid identifier starting with a letter or underscore.";
	if (strcmp(cCode, "C7") == 0) return "Malformed list literal syntax. List elements must be valid expressions separated by commas or newlines.";
	if (strcmp(cCode, "C8") == 0) return "Unbalanced opening parenthesis '('. Ensure all opened parentheses are properly closed with ')'.";
	if (strcmp(cCode, "C9") == 0) return "Unbalanced opening bracket '['. Ensure all list literals and index expressions have a matching ']'.";
	if (strcmp(cCode, "C10") == 0) return "Inheritance clause 'from <ParentClass>' requires a valid parent class identifier.";
	if (strcmp(cCode, "C11") == 0) {
		if (cExtra && (strstr(cExtra, "**") || strstr(cExtra, "*") || strstr(cExtra, "/") || strstr(cExtra, "+") || strstr(cExtra, "-"))) {
			return "Consecutive or malformed operators detected. Arithmetic expressions require operands between operators.";
		}
		return "Invalid operator sequence or unexpected operator in expression.";
	}
	if (strcmp(cCode, "C12") == 0) return "Method or property was placed outside any class context. Encapsulate inside a class block.";
	if (strcmp(cCode, "C13") == 0) return "Identifier used as a variable name is invalid or a reserved keyword in this position.";
	if (strcmp(cCode, "C14") == 0) return "A 'try' block must be followed by a 'catch' block before closing.";
	if (strcmp(cCode, "C15") == 0) return "A 'try ... catch' structure must be terminated with 'done', 'end', or '}'.";
	if (strcmp(cCode, "C16") == 0) return "The 'switch' statement must be followed by a valid variable or expression to evaluate.";
	if (strcmp(cCode, "C17") == 0) return "A 'switch' block is missing its closing 'off' or '}' statement.";
	if (strcmp(cCode, "C18") == 0) return "Missing closing brace '}' for an opened block.";
	if (strcmp(cCode, "C19") == 0) return "Number literal exceeds numeric representation capacity (overflow).";
	if (strcmp(cCode, "C20") == 0) return "Package declaration requires a valid dot-separated package identifier.";
	if (strcmp(cCode, "C21") == 0) return "A 'do' loop requires 'again <condition>' to terminate.";
	if (strcmp(cCode, "C22") == 0) return "A function with this name has already been defined in the current scope or a loaded file.";
	if (strcmp(cCode, "C23") == 0) return "Attempting to invoke a number literal as a function (e.g. '123(...)'). Insert an operator if multiplication was intended.";
	if (strcmp(cCode, "C24") == 0) return "A class cannot inherit from itself (parent class name is identical to subclass name).";
	if (strcmp(cCode, "C25") == 0) return "Invalid reference syntax involving 'self' or 'this'.";
	if (strcmp(cCode, "C26") == 0) return "A class with this name is already defined in the current scope.";
	if (strcmp(cCode, "C27") == 0) {
		if (cExtra && strcmp(cExtra, ".") == 0) {
			return "Unexpected trailing dot '.' at the end of expression.";
		}
		return "Syntax error: unexpected token or malformed grammar rule that violates Ring syntax.";
	}
	if (strcmp(cCode, "C28") == 0) return "Expression expected: parser encountered an operator or statement expecting a value or variable.";
	if (strcmp(cCode, "C29") == 0) return "Anonymous function syntax requires braces or parameter specification: func(params) { ... }.";
	if (strcmp(cCode, "C30") == 0) return "Duplicate parameter name defined in the same function signature.";
	if (strcmp(cCode, "C31") == 0) return "Function call or grouping expression expected an opening parenthesis '('.";

	/* ---- Scanner Errors (S1 - S3) ---- */
	if (strcmp(cCode, "S1") == 0) return "String literal was not terminated. Add a matching closing quote (\", ', or `).";
	if (strcmp(cCode, "S2") == 0) return "Multi-line comment was not terminated. Add '*/' to close the comment.";
	if (strcmp(cCode, "S3") == 0) return "Formatted string literal f\"...\" is unclosed or contains unbalanced interpolation braces '{...}'.";

	/* ---- Runtime Errors (R1 - R55) ---- */
	if (strcmp(cCode, "R1") == 0) return "Division by zero encountered in numeric calculation.";
	if (strcmp(cCode, "R2") == 0) return "Array access index out of range. Note: Ring uses 1-based indexing (from 1 to len(list)).";
	if (strcmp(cCode, "R3") == 0) return "Function called without definition. The function does not exist in the active scope or loaded libraries.";
	if (strcmp(cCode, "R4") == 0) return "Call stack limit exceeded (Stack Overflow), typically caused by infinite recursion.";
	if (strcmp(cCode, "R5") == 0) return "Attempted to access an index on a variable that is not a list.";
	if (strcmp(cCode, "R6") == 0) return "A variable (L-value) is required for this operation, but received a constant or expression.";
	if (strcmp(cCode, "R7") == 0) return "Cannot assign more than one character to a single string index (str[i] = 'c').";
	if (strcmp(cCode, "R8") == 0) return "Operation requires a string variable, but a different data type was provided.";
	if (strcmp(cCode, "R9") == 0) return "The 'exit' command was executed outside of a loop.";
	if (strcmp(cCode, "R10") == 0) return "'exit N' specifies more loop levels than are currently active.";
	if (strcmp(cCode, "R11") == 0) return "Class definition was not found when attempting instantiation with 'new'.";
	if (strcmp(cCode, "R12") == 0) return "Property/attribute was not found in the target object.";
	if (strcmp(cCode, "R13") == 0) return "An object instance is required to access methods or properties, but the variable is not an object.";
	if (strcmp(cCode, "R14") == 0) return "Method called on the object is not defined in its class or parent classes.";
	if (strcmp(cCode, "R15") == 0) return "Parent class specified in inheritance clause 'from' was not found at runtime.";
	if (strcmp(cCode, "R16") == 0) return "Brace access syntax '{ ... }' was applied to an uninitialized or non-object variable.";
	if (strcmp(cCode, "R17") == 0) return "The 'super' keyword was called inside a class that does not inherit from any parent.";
	if (strcmp(cCode, "R18") == 0) return "Numeric calculation caused a numeric overflow.";
	if (strcmp(cCode, "R19") == 0) return "Function was called with fewer arguments than expected by its definition.";
	if (strcmp(cCode, "R20") == 0) return "Function was called with more arguments than expected by its definition.";
	if (strcmp(cCode, "R21") == 0) return "Operator cannot be applied between these incompatible data types.";
	if (strcmp(cCode, "R22") == 0) return "The 'loop' (continue) command was executed outside of a loop structure.";
	if (strcmp(cCode, "R23") == 0) return "'loop N' specifies more loop levels than are currently active.";
	if (strcmp(cCode, "R24") == 0) return "Variable was referenced before being assigned a value (uninitialized variable).";
	if (strcmp(cCode, "R25") == 0) return "Package specified in 'import' or package path was not found.";
	if (strcmp(cCode, "R26") == 0) return "Private method cannot be called from outside the class scope.";
	if (strcmp(cCode, "R27") == 0) return "Private attribute cannot be accessed from outside the class scope.";
	if (strcmp(cCode, "R28") == 0) return "Step value in for-loop must be a numeric integer or float.";
	if (strcmp(cCode, "R29") == 0) return "Boundary values in for-loop range must be numeric.";
	if (strcmp(cCode, "R30") == 0) return "Parent class name cannot be identical to child class name.";
	if (strcmp(cCode, "R31") == 0) return "Cannot destroy an object from within its own method using self reference.";
	if (strcmp(cCode, "R32") == 0) return "The 'call' command expects a variable containing a string function name.";
	if (strcmp(cCode, "R33") == 0) return "The 'decimals(n)' function requires n to be between 0 and 90.";
	if (strcmp(cCode, "R34") == 0) return "Left side of an assignment must be a valid variable or object property.";
	if (strcmp(cCode, "R35") == 0) return "Failed to open or create file (file I/O error). Check path and permissions.";
	if (strcmp(cCode, "R36") == 0) return "Specified column number exceeds the number of columns in the list/table.";
	if (strcmp(cCode, "R37") == 0) return "Command is not supported in the current execution context.";
	if (strcmp(cCode, "R38") == 0) return "Failed to load dynamic C extension library (DLL / SO). Check dependencies.";
	if (strcmp(cCode, "R42") == 0) return "Error encountered during dynamic code evaluation inside eval().";
	if (strcmp(cCode, "R45") == 0) return "List operation called on a non-list variable.";
	if (strcmp(cCode, "R48") == 0) return "Assertion condition evaluated to false.";
	if (strcmp(cCode, "R50") == 0) return "Object does not support operator overloading for this operator (missing 'operator' method).";
	if (strcmp(cCode, "R51") == 0) return "Value Error: invalid parameter value passed to internal operation.";
	if (strcmp(cCode, "R55") == 0) return "Mathematical calculation produced an invalid numeric value (NaN or Infinity).";

	/* ---- Environment Errors (E1 - E18) ---- */
	if (strcmp(cCode, "E1") == 0) return "Critical segmentation fault (SIGSEGV) encountered.";
	if (strcmp(cCode, "E2") == 0) return "System memory exhausted (Out of Memory).";
	if (strcmp(cCode, "E9") == 0) return "Cannot open source file from disk. Check file path.";
	if (strcmp(cCode, "E10") == 0) return "String buffer size limit exceeded.";
	if (strcmp(cCode, "E11") == 0) return "List capacity limit exceeded.";

	/* ---- Tensor & GGML Native Acceleration Errors ---- */
	if (strcmp(cCode, "TENSOR_ERR") == 0) {
		if (strstr(cMsg, "Shapes must match")) return "Element-wise tensor operations require identical tensor dimensions.";
		if (strstr(cMsg, "Incompatible matrix dimensions")) return "Matrix multiplication requires inner dimensions to match: (M x K) * (K x N) -> (M x N).";
		if (strstr(cMsg, "Indices out of bounds")) return "Tensor index exceeds bounds. Note: Madar tensors use 1-based indexing (from 1 to N).";
		return "Native tensor operation failed due to invalid dimensions or unsupported dtype.";
	}

	return "Review the syntax and ensure all expressions, variables, and keywords are valid.";
}

/*
================================================================================
  Intelligent AI Suggested Fix & Actionable Recipe Generator
================================================================================
*/

RING_API const char *ring_diagnostics_generate_fix(const char *cStage, const char *cCode, const char *cMsg, const char *cExtra) {
	if (!cCode) return "Verify code syntax against the Ring and Madar language references.";

	/* Compiler Fixes */
	if (strcmp(cCode, "C1") == 0) return "Ensure parameters are valid identifiers separated by commas: func f(a, b).";
	if (strcmp(cCode, "C2") == 0) return "Provide a clean alphanumeric class name: class MyClass.";
	if (strcmp(cCode, "C3") == 0) return "Add 'ok' or '}' at the end of the 'if' condition block.";
	if (strcmp(cCode, "C4") == 0) return "Add 'end' or '}' to close the active function or class block.";
	if (strcmp(cCode, "C5") == 0) return "Add 'next' or '}' at the end of the loop body.";
	if (strcmp(cCode, "C6") == 0) return "Provide a valid function identifier: func myFunc { ... }.";
	if (strcmp(cCode, "C7") == 0) return "Enclose list items in square brackets with commas or newlines: [1, 2, 3].";
	if (strcmp(cCode, "C8") == 0) return "Add a closing parenthesis ')' matching the open parenthesis.";
	if (strcmp(cCode, "C9") == 0) return "Add a closing bracket ']' matching the open bracket.";
	if (strcmp(cCode, "C10") == 0) return "Specify a valid class identifier after 'from': class SubClass from BaseClass.";
	if (strcmp(cCode, "C11") == 0) return "Remove the redundant operator or provide a valid operand between consecutive operators.";
	if (strcmp(cCode, "C12") == 0) return "Wrap the methods or properties inside 'class <Name> ... end'.";
	if (strcmp(cCode, "C13") == 0) return "Rename the variable to an identifier that does not conflict with Ring keywords.";
	if (strcmp(cCode, "C14") == 0) return "Add 'catch' followed by error handling code before closing the 'try' block.";
	if (strcmp(cCode, "C15") == 0) return "Add 'done', 'end', or '}' to close the 'try ... catch' block.";
	if (strcmp(cCode, "C16") == 0) return "Specify an expression to test after 'switch': switch x on 1 ... off.";
	if (strcmp(cCode, "C17") == 0) return "Add 'off' or '}' at the conclusion of the 'switch' block.";
	if (strcmp(cCode, "C18") == 0) return "Add a closing brace '}' to balance the opened code block.";
	if (strcmp(cCode, "C22") == 0) return "Rename the duplicate function or check for redundant 'load' statements.";
	if (strcmp(cCode, "C23") == 0) return "Add explicit '*' operator (e.g. '123 * (x + y)') or remove parentheses.";
	if (strcmp(cCode, "C26") == 0) return "Rename the duplicate class or verify that files are loaded only once.";
	if (strcmp(cCode, "C27") == 0) {
		if (cExtra && strcmp(cExtra, ".") == 0) {
			return "Remove the trailing dot '.' or complete the property access identifier.";
		}
		return "Inspect the token indicated by '^' and ensure correct operator and operand placement.";
	}
	if (strcmp(cCode, "C28") == 0) return "Supply the missing value, variable, or operand after the operator.";

	/* Scanner Fixes */
	if (strcmp(cCode, "S1") == 0) return "Add a matching quote (\", ', or `) to close the string.";
	if (strcmp(cCode, "S2") == 0) return "Add '*/' to terminate the multi-line comment.";
	if (strcmp(cCode, "S3") == 0) return "Close the f-string with matching quotes and ensure '{expr}' braces are balanced.";

	/* Runtime Fixes */
	if (strcmp(cCode, "R1") == 0) return "Add a guard check before division: if nDivisor != 0 { nRes = nVal / nDivisor }.";
	if (strcmp(cCode, "R2") == 0) return "Ensure 1 <= nIndex <= len(aList). Note that Ring lists are 1-based.";
	if (strcmp(cCode, "R3") == 0) return "Define the function or import its library using load '<library>.ring'.";
	if (strcmp(cCode, "R4") == 0) return "Ensure recursive function calls have a terminating base condition.";
	if (strcmp(cCode, "R11") == 0) return "Ensure the class is defined and the file defining it is loaded before 'new'.";
	if (strcmp(cCode, "R12") == 0) return "Check attribute spelling or define the property in the class definition.";
	if (strcmp(cCode, "R14") == 0) return "Implement the method in the class or check method spelling.";
	if (strcmp(cCode, "R19") == 0) return "Provide all required parameters or specify default arguments: func f(a, b = 10).";
	if (strcmp(cCode, "R24") == 0) return "Initialize the variable before referencing it (e.g. nVar = 0 or cVar = \"\").";
	if (strcmp(cCode, "R50") == 0) return "Add 'func operator cOp, vValue { ... }' to the class to enable operator overloading.";

	/* Tensor Fixes */
	if (strcmp(cCode, "TENSOR_ERR") == 0) {
		if (strstr(cMsg, "Shapes must match")) return "Use tensor_shape(t) to inspect dimensions, or tensor_reshape(t, dims) to align them.";
		if (strstr(cMsg, "Incompatible matrix dimensions")) return "Ensure operand A columns equal operand B rows for matrix multiplication.";
		if (strstr(cMsg, "Indices out of bounds")) return "Check tensor rank and bounds. Indices range from 1 to tensor_shape(t)[d].";
		return "Check tensor shapes and compatibility before executing operation.";
	}

	return "Refer to the error code and location marker to correct the syntax.";
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

	char stdCode[16];
	extract_standard_code(cMsg, "scanner", stdCode, sizeof(stdCode));
	if (cCode && cCode[0]) strncpy(stdCode, cCode, sizeof(stdCode) - 1);

	char *snippet = ring_diagnostics_get_snippet(cFile, nLine);
	int nCol = 1;
	char *marker = generate_visual_marker(nCol);

	char *escFile = ring_diagnostics_escape_json(cFile);
	char *escMsg = ring_diagnostics_escape_json(cMsg);
	char *escSnippet = ring_diagnostics_escape_json(snippet);
	char *escMarker = ring_diagnostics_escape_json(marker);

	const char *hint = ring_diagnostics_generate_hint("scanner", stdCode, cMsg, NULL);
	const char *fix = ring_diagnostics_generate_fix("scanner", stdCode, cMsg, NULL);
	char *escHint = ring_diagnostics_escape_json(hint);
	char *escFix = ring_diagnostics_escape_json(fix);

	printf("\n{\n");
	printf("  \"madar_error\": {\n");
	printf("    \"status\": \"error\",\n");
	printf("    \"stage\": \"scanner\",\n");
	printf("    \"error_code\": \"%s\",\n", stdCode);
	printf("    \"message\": \"%s\",\n", escMsg);
	printf("    \"file\": \"%s\",\n", escFile);
	printf("    \"line\": %d,\n", nLine);
	printf("    \"column\": %d,\n", nCol);
	printf("    \"offending_token\": \"\",\n");
	printf("    \"source_snippet\": \"%s\",\n", escSnippet);
	printf("    \"visual_marker\": \"%s\",\n", escMarker);
	printf("    \"hint\": \"%s\",\n", escHint);
	printf("    \"suggested_fix\": \"%s\",\n", escFix);
	printf("    \"call_stack\": []\n");
	printf("  }\n");
	printf("}\n\n");
	fflush(stdout);

	free(snippet);
	free(marker);
	free(escFile);
	free(escMsg);
	free(escSnippet);
	free(escMarker);
	free(escHint);
	free(escFix);
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

	char stdCode[16];
	extract_standard_code(cMsg, "parser", stdCode, sizeof(stdCode));
	if (cCode && cCode[0]) strncpy(stdCode, cCode, sizeof(stdCode) - 1);

	char *snippet = NULL;
	int nCol = 1;
	char *offendingToken = NULL;

	/* If file is 'eval' or cannot be opened on disk, rebuild snippet from pTokens */
	bool bIsEval = (cFile && (strcmp(cFile, "eval") == 0 || strcmp(cFile, "") == 0));
	if (bIsEval) {
		snippet = rebuild_line_from_tokens(pParser, nLine, &nCol, &offendingToken);
	} else {
		snippet = ring_diagnostics_get_snippet(cFile, nLine);
		if (!snippet || snippet[0] == '\0') {
			/* Fallback to in-memory tokens */
			if (snippet) free(snippet);
			snippet = rebuild_line_from_tokens(pParser, nLine, &nCol, &offendingToken);
		} else {
			/* Find column in snippet from active token */
			if (pParser->cTokenText && pParser->cTokenText[0]) {
				offendingToken = _strdup(pParser->cTokenText);
				char *pos = strstr(snippet, pParser->cTokenText);
				if (pos) {
					nCol = (int)(pos - snippet) + 1;
				}
			}
		}
	}

	if (!snippet) snippet = _strdup("");
	if (!offendingToken) offendingToken = _strdup(pParser->cTokenText ? pParser->cTokenText : "");

	char *marker = generate_visual_marker(nCol);

	char *escFile = ring_diagnostics_escape_json(cFile);
	char *escMsg = ring_diagnostics_escape_json(cMsg ? cMsg : "Syntax Error");
	char *escSnippet = ring_diagnostics_escape_json(snippet);
	char *escMarker = ring_diagnostics_escape_json(marker);
	char *escToken = ring_diagnostics_escape_json(offendingToken);

	const char *hint = ring_diagnostics_generate_hint("parser", stdCode, cMsg, offendingToken);
	const char *fix = ring_diagnostics_generate_fix("parser", stdCode, cMsg, offendingToken);
	char *escHint = ring_diagnostics_escape_json(hint);
	char *escFix = ring_diagnostics_escape_json(fix);

	printf("\n{\n");
	printf("  \"madar_error\": {\n");
	printf("    \"status\": \"error\",\n");
	printf("    \"stage\": \"parser\",\n");
	printf("    \"error_code\": \"%s\",\n", stdCode);
	printf("    \"message\": \"%s\",\n", escMsg);
	printf("    \"file\": \"%s\",\n", escFile);
	printf("    \"line\": %d,\n", nLine);
	printf("    \"column\": %d,\n", nCol);
	printf("    \"offending_token\": \"%s\",\n", escToken);
	printf("    \"source_snippet\": \"%s\",\n", escSnippet);
	printf("    \"visual_marker\": \"%s\",\n", escMarker);
	printf("    \"hint\": \"%s\",\n", escHint);
	printf("    \"suggested_fix\": \"%s\",\n", escFix);
	printf("    \"call_stack\": []\n");
	printf("  }\n");
	printf("}\n\n");
	fflush(stdout);

	free(snippet);
	free(offendingToken);
	free(marker);
	free(escFile);
	free(escMsg);
	free(escSnippet);
	free(escMarker);
	free(escToken);
	free(escHint);
	free(escFix);
}

/*
================================================================================
  Report Runtime Error (JSON)
================================================================================
*/

RING_API void ring_diagnostics_report_runtime_error(VM *pVM, const char *cMsg) {
	int nLine = (int)RING_VM_IR_GETLINENUMBER;
	const char *cFile = pVM->cFileName ? pVM->cFileName : "";

	char stdCode[16];
	extract_standard_code(cMsg, "runtime", stdCode, sizeof(stdCode));

	char *snippet = ring_diagnostics_get_snippet(cFile, nLine);
	int nCol = 1;
	char *marker = generate_visual_marker(nCol);

	char *escFile = ring_diagnostics_escape_json(cFile);
	char *escMsg = ring_diagnostics_escape_json(cMsg);
	char *escSnippet = ring_diagnostics_escape_json(snippet);
	char *escMarker = ring_diagnostics_escape_json(marker);

	const char *hint = ring_diagnostics_generate_hint("runtime", stdCode, cMsg, NULL);
	const char *fix = ring_diagnostics_generate_fix("runtime", stdCode, cMsg, NULL);
	char *escHint = ring_diagnostics_escape_json(hint);
	char *escFix = ring_diagnostics_escape_json(fix);

	printf("\n{\n");
	printf("  \"madar_error\": {\n");
	printf("    \"status\": \"error\",\n");
	printf("    \"stage\": \"runtime\",\n");
	printf("    \"error_code\": \"%s\",\n", stdCode);
	printf("    \"message\": \"%s\",\n", escMsg);
	printf("    \"file\": \"%s\",\n", escFile);
	printf("    \"line\": %d,\n", nLine);
	printf("    \"column\": %d,\n", nCol);
	printf("    \"offending_token\": \"\",\n");
	printf("    \"source_snippet\": \"%s\",\n", escSnippet);
	printf("    \"visual_marker\": \"%s\",\n", escMarker);
	printf("    \"hint\": \"%s\",\n", escHint);
	printf("    \"suggested_fix\": \"%s\",\n", escFix);
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
	free(marker);
	free(escFile);
	free(escMsg);
	free(escSnippet);
	free(escMarker);
	free(escHint);
	free(escFix);
}
