#include "ring.h"
#define PCRE2_CODE_UNIT_WIDTH 8
#include <pcre2.h>
#include <string.h>
#include <stdlib.h>

// Structure to store compiled regex pattern
typedef struct {
    pcre2_code *regex;
    int is_valid;
    char *error_message;
} RegexPattern;

void ring_regex_pattern_delete(void *pRingState, void *ptr)
{
    RegexPattern *pattern = (RegexPattern *)ptr;
    if (pattern->is_valid) {
        pcre2_code_free(pattern->regex);
    }
    if (pattern->error_message) {
        free(pattern->error_message);
    }
    free(pattern);
}

// Function to create a new regex pattern
RING_FUNC(ring_regex_new)
{
    RegexPattern *pattern;
    const char *regex_str;
    int error_code;
    size_t error_offset;
    uint32_t options = 0;  // Default options
    PCRE2_UCHAR error_buffer[256];
    
    if (RING_API_PARACOUNT < 1) {
        RING_API_ERROR(RING_API_MISS1PARA);
        return;
    }
    
    if (!RING_API_ISSTRING(1)) {
        RING_API_ERROR(RING_API_BADPARATYPE);
        return;
    }

    // Get the regex pattern string
    regex_str = RING_API_GETSTRING(1);
    
    // Check for optional flags parameter
    if (RING_API_PARACOUNT > 1 && RING_API_ISNUMBER(2)) {
        int flags = (int)RING_API_GETNUMBER(2);
        if (flags & 1) options |= PCRE2_CASELESS;  // Case insensitive
        if (flags & 2) options |= PCRE2_MULTILINE;     // Multiline mode
        if (flags & 4) options |= PCRE2_DOTALL;        // Dot matches newline
        if (flags & 8) options |= PCRE2_EXTENDED;      // Extended syntax
    }
    
    // Add UTF-8 support by default
    options |= PCRE2_UTF;
    
    // Allocate memory for the pattern structure
    pattern = (RegexPattern *)malloc(sizeof(RegexPattern));
    if (!pattern) {
        RING_API_ERROR("Memory allocation failed");
        return;
    }
    
    pattern->is_valid = 0;
    pattern->error_message = NULL;
    
    // Compile the regex pattern
    pattern->regex = pcre2_compile(
        (PCRE2_SPTR)regex_str,
        PCRE2_ZERO_TERMINATED,
        options,
        &error_code,
        &error_offset,
        NULL
    );

    if (pattern->regex != NULL) {
        pattern->is_valid = 1;
        // Enable JIT compilation for better performance
        pcre2_jit_compile(pattern->regex, PCRE2_JIT_COMPLETE);
        // JIT compilation failure is not fatal, just less optimal
    } else {
        // Get the error message
        pcre2_get_error_message(error_code, error_buffer, sizeof(error_buffer));
        pattern->error_message = strdup((char *)error_buffer);
    }
    
    // Register cleanup function
    RING_API_RETMANAGEDCPOINTER(pattern, "RegexPattern", ring_regex_pattern_delete);
}

// Function to get last error message
RING_FUNC(ring_regex_get_error)
{
    RegexPattern *pattern;
    
    if (RING_API_PARACOUNT != 1) {
        RING_API_ERROR(RING_API_MISS1PARA);
        return;
    }
    
    if (!RING_API_ISPOINTER(1)) {
        RING_API_ERROR(RING_API_BADPARATYPE);
        return;
    }
    
    pattern = (RegexPattern *)RING_API_GETCPOINTER(1, "RegexPattern");
    if (!pattern) {
        RING_API_ERROR("Invalid regex pattern pointer");
        return;
    }
    
    if (pattern->error_message) {
        RING_API_RETSTRING(pattern->error_message);
    } else {
        RING_API_RETSTRING("");
    }
}

// Function to match a string against a pattern
RING_FUNC(ring_regex_match)
{
    RegexPattern *pattern;
    const char *text;
    pcre2_match_data *match_data;
    int rc;
    
    if (RING_API_PARACOUNT != 2) {
        RING_API_ERROR(RING_API_MISS2PARA);
        return;
    }
    
    if (!RING_API_ISPOINTER(1) || !RING_API_ISSTRING(2)) {
        RING_API_ERROR(RING_API_BADPARATYPE);
        return;
    }
    
    pattern = (RegexPattern *)RING_API_GETCPOINTER(1, "RegexPattern");
    if (!pattern) {
        RING_API_ERROR("Invalid regex pattern pointer");
        return;
    }
    text = RING_API_GETSTRING(2);
    
    if (!pattern->is_valid) {
        RING_API_ERROR("Invalid regex pattern");
        return;
    }
    
    match_data = pcre2_match_data_create_from_pattern(pattern->regex, NULL);
    rc = pcre2_match(
        pattern->regex,
        (PCRE2_SPTR)text,
        strlen(text),
        0,
        0,
        match_data,
        NULL
    );
    
    pcre2_match_data_free(match_data);
    RING_API_RETNUMBER(rc >= 0);
}

// Function to get match positions
RING_FUNC(ring_regex_match_positions)
{
    RegexPattern *pattern;
    const char *text;
    pcre2_match_data *match_data;
    PCRE2_SIZE *ovector;
    int rc, start_offset = 0;
    size_t text_len;
    List *pList;
    
    if (RING_API_PARACOUNT != 2) {
        RING_API_ERROR(RING_API_MISS2PARA);
        return;
    }
    
    if (!RING_API_ISPOINTER(1) || !RING_API_ISSTRING(2)) {
        RING_API_ERROR(RING_API_BADPARATYPE);
        return;
    }
    
    pattern = (RegexPattern *)RING_API_GETCPOINTER(1, "RegexPattern");
    if (!pattern) {
        RING_API_ERROR("Invalid regex pattern pointer");
        return;
    }
    
    text = RING_API_GETSTRING(2);
    text_len = strlen(text);
    
    if (!pattern->is_valid) {
        RING_API_ERROR("Invalid regex pattern");
        return;
    }
    
    pList = ring_list_new(0);
    match_data = pcre2_match_data_create_from_pattern(pattern->regex, NULL);
    
    while (start_offset < text_len) {
        rc = pcre2_match(
            pattern->regex,
            (PCRE2_SPTR)text,
            text_len,
            start_offset,
            0,
            match_data,
            NULL
        );
        
        if (rc < 0) break;
        
        ovector = pcre2_get_ovector_pointer(match_data);
        
        // Add all capturing groups for this match
        for (int i = 0; i < rc; i++) {
            List *pSubList = ring_list_newlist(pList);
            ring_list_adddouble(pSubList, (double)(ovector[2*i] + 1));  // Convert to 1-based index
            ring_list_adddouble(pSubList, (double)(ovector[2*i+1] + 1));  // Convert to 1-based index
        }
        
        // Move past this match
        start_offset = ovector[1];
        if (ovector[0] == ovector[1]) {
            if (start_offset >= text_len) break;
            start_offset++;
        }
    }
    
    pcre2_match_data_free(match_data);
    RING_API_RETLIST(pList);
}

// Function to extract matched substrings
RING_FUNC(ring_regex_match_all)
{
    RegexPattern *pattern;
    const char *text;
    pcre2_match_data *match_data;
    PCRE2_SIZE *ovector;
    int rc, i;
    List *pList;
    char *substring;
    
    if (RING_API_PARACOUNT != 2) {
        RING_API_ERROR(RING_API_MISS2PARA);
        return;
    }
    
    if (!RING_API_ISPOINTER(1) || !RING_API_ISSTRING(2)) {
        RING_API_ERROR(RING_API_BADPARATYPE);
        return;
    }
    
    pattern = (RegexPattern *)RING_API_GETCPOINTER(1, "RegexPattern");
    if (!pattern) {
        RING_API_ERROR("Invalid regex pattern pointer");
        return;
    }
    
    text = RING_API_GETSTRING(2);
    
    if (!pattern->is_valid) {
        RING_API_ERROR("Invalid regex pattern");
        return;
    }
    
    match_data = pcre2_match_data_create_from_pattern(pattern->regex, NULL);
    rc = pcre2_match(
        pattern->regex,
        (PCRE2_SPTR)text,
        strlen(text),
        0,
        0,
        match_data,
        NULL
    );
    
    pList = ring_list_new(0);
    
    if (rc > 0) {
        ovector = pcre2_get_ovector_pointer(match_data);
        for (i = 0; i < rc; i++) {
            int length = ovector[2*i+1] - ovector[2*i];
            substring = (char *)malloc(length + 1);
            if (!substring) {
                pcre2_match_data_free(match_data);
                RING_API_ERROR("Memory allocation failed");
                return;
            }
            memcpy(substring, text + ovector[2*i], length);
            substring[length] = '\0';
            ring_list_addstring2(pList, substring, length);
            free(substring);
        }
    }
    
    pcre2_match_data_free(match_data);
    RING_API_RETLIST(pList);
}

// Function to replace matches with a new string
RING_FUNC(ring_regex_replace)
{
    RegexPattern *pattern;
    const char *text, *replacement;
    pcre2_match_data *match_data;
    PCRE2_SIZE outlength;
    char *result;
    int rc;
    
    if (RING_API_PARACOUNT != 3) {
        RING_API_ERROR(RING_API_MISS3PARA);
        return;
    }
    
    if (!RING_API_ISPOINTER(1) || !RING_API_ISSTRING(2) || !RING_API_ISSTRING(3)) {
        RING_API_ERROR(RING_API_BADPARATYPE);
        return;
    }
    
    pattern = (RegexPattern *)RING_API_GETCPOINTER(1, "RegexPattern");
    if (!pattern) {
        RING_API_ERROR("Invalid regex pattern pointer");
        return;
    }
    
    text = RING_API_GETSTRING(2);
    replacement = RING_API_GETSTRING(3);
    
    if (!pattern->is_valid) {
        RING_API_ERROR("Invalid regex pattern");
        return;
    }
    
    match_data = pcre2_match_data_create_from_pattern(pattern->regex, NULL);
    
    // Allocate a reasonably large buffer
    outlength = strlen(text) * 2 + strlen(replacement) + 1;
    result = (char *)malloc(outlength);
    
    if (!result) {
        pcre2_match_data_free(match_data);
        RING_API_ERROR("Memory allocation failed");
        return;
    }
        
        rc = pcre2_substitute(
            pattern->regex,
            (PCRE2_SPTR)text,
            strlen(text),
            0,
            PCRE2_SUBSTITUTE_GLOBAL,
            match_data,
            NULL,
            (PCRE2_SPTR)replacement,
            strlen(replacement),
        (PCRE2_UCHAR *)result,
        &outlength
    );
    
    pcre2_match_data_free(match_data);
    
    if (rc >= 0) {
        result[outlength] = '\0';
        RING_API_RETSTRING(result);
    } else {
        free(result);
        RING_API_ERROR("Replacement failed");
    }
}

// Function to split string using regex as delimiter
RING_FUNC(ring_regex_split)
{
    RegexPattern *pattern;
    const char *text;
    pcre2_match_data *match_data;
    PCRE2_SIZE *ovector;
    List *pList;
    int rc, last_end = 0;
    size_t text_len;
    char *substring;
    
    if (RING_API_PARACOUNT != 2) {
        RING_API_ERROR(RING_API_MISS2PARA);
        return;
    }
    
    if (!RING_API_ISPOINTER(1) || !RING_API_ISSTRING(2)) {
        RING_API_ERROR(RING_API_BADPARATYPE);
        return;
    }
    
    pattern = (RegexPattern *)RING_API_GETCPOINTER(1, "RegexPattern");
    if (!pattern) {
        RING_API_ERROR("Invalid regex pattern pointer");
        return;
    }
    
    text = RING_API_GETSTRING(2);
    text_len = strlen(text);
    
    if (!pattern->is_valid) {
        RING_API_ERROR("Invalid regex pattern");
        return;
    }
    
    pList = ring_list_new(0);
    match_data = pcre2_match_data_create_from_pattern(pattern->regex, NULL);
    
    while (1) {
        rc = pcre2_match(
            pattern->regex,
            (PCRE2_SPTR)text,
            text_len,
            last_end,
            0,
            match_data,
            NULL
        );
        
        if (rc < 0) break;
        
        ovector = pcre2_get_ovector_pointer(match_data);
        
        // Add text before the match
        if (ovector[0] > last_end) {
            int length = ovector[0] - last_end;
            substring = (char *)malloc(length + 1);
            if (!substring) {
                pcre2_match_data_free(match_data);
                RING_API_ERROR("Memory allocation failed");
                return;
            }
            memcpy(substring, text + last_end, length);
            substring[length] = '\0';
            ring_list_addstring2(pList, substring, length);
            free(substring);
        }
        
        last_end = ovector[1];
        
        if (ovector[0] == ovector[1]) {
            if (last_end >= text_len) break;
            last_end++;
        }
    }
    
    // Add remaining text
    if (last_end < text_len) {
        int length = text_len - last_end;
        substring = (char *)malloc(length + 1);
        if (!substring) {
            pcre2_match_data_free(match_data);
            RING_API_ERROR("Memory allocation failed");
            return;
        }
        memcpy(substring, text + last_end, length);
        substring[length] = '\0';
        ring_list_addstring2(pList, substring, length);
        free(substring);
    }
    
    pcre2_match_data_free(match_data);
    RING_API_RETLIST(pList);
}

// Function to validate a regex pattern without compiling it
RING_FUNC(ring_regex_is_valid)
{
    const char *regex_str;
    int error_code;
    size_t error_offset;
    pcre2_code *temp_regex;
    
    if (RING_API_PARACOUNT != 1) {
        RING_API_ERROR(RING_API_MISS1PARA);
        return;
    }
    
    if (!RING_API_ISSTRING(1)) {
        RING_API_ERROR(RING_API_BADPARATYPE);
        return;
    }
    
    regex_str = RING_API_GETSTRING(1);
    
    temp_regex = pcre2_compile(
        (PCRE2_SPTR)regex_str,
        PCRE2_ZERO_TERMINATED,
        0,
        &error_code,
        &error_offset,
        NULL
    );
    
    if (temp_regex != NULL) {
        pcre2_code_free(temp_regex);
        RING_API_RETNUMBER(1);
    } else {
        RING_API_RETNUMBER(0);
    }
}

// Function to get pattern information
RING_FUNC(ring_regex_pattern_info)
{
    RegexPattern *pattern;
    uint32_t capture_count;
    int rc;
    List *pList;
    
    if (RING_API_PARACOUNT != 1) {
        RING_API_ERROR(RING_API_MISS1PARA);
        return;
    }
    
    if (!RING_API_ISPOINTER(1)) {
        RING_API_ERROR(RING_API_BADPARATYPE);
        return;
    }
    
    pattern = (RegexPattern *)RING_API_GETCPOINTER(1, "RegexPattern");
    if (!pattern) {
        RING_API_ERROR("Invalid regex pattern pointer");
        return;
    }

    pList = ring_list_new(0);
    ring_list_adddouble(pList, pattern->is_valid);
    
    if (pattern->is_valid) {
        rc = pcre2_pattern_info(pattern->regex, PCRE2_INFO_CAPTURECOUNT, &capture_count);
        if (rc == 0) {
            ring_list_adddouble(pList, capture_count);
        } else {
            ring_list_adddouble(pList, 0);
        }
    } else {
        ring_list_adddouble(pList, 0);
    }
    
    RING_API_RETLIST(pList);
}

// Function to find all matches with iteration
RING_FUNC(ring_regex_find_all)
{
    RegexPattern *pattern;
    const char *text;
    pcre2_match_data *match_data;
    PCRE2_SIZE *ovector;
    int rc, start_offset = 0;
    size_t text_len;
    List *pList;
    char *substring;
    
    if (RING_API_PARACOUNT != 2) {
        RING_API_ERROR(RING_API_MISS2PARA);
        return;
    }
    
    if (!RING_API_ISPOINTER(1) || !RING_API_ISSTRING(2)) {
        RING_API_ERROR(RING_API_BADPARATYPE);
        return;
    }
    
    pattern = (RegexPattern *)RING_API_GETCPOINTER(1, "RegexPattern");
    if (!pattern) {
        RING_API_ERROR("Invalid regex pattern pointer");
        return;
    }
    
    text = RING_API_GETSTRING(2);
    text_len = strlen(text);
    
    if (!pattern->is_valid) {
        RING_API_ERROR("Invalid regex pattern");
        return;
    }
    
    pList = ring_list_new(0);
    match_data = pcre2_match_data_create_from_pattern(pattern->regex, NULL);
    
    while (start_offset < text_len) {
        rc = pcre2_match(
            pattern->regex,
            (PCRE2_SPTR)text,
            text_len,
            start_offset,
            0,
            match_data,
            NULL
        );
        
        if (rc < 0) break;
        
        ovector = pcre2_get_ovector_pointer(match_data);
        
        // Add the match and all capturing groups
        List *pMatchList = ring_list_newlist(pList);
        for (int i = 0; i < rc; i++) {
            int length = ovector[2*i+1] - ovector[2*i];
            substring = (char *)malloc(length + 1);
            if (!substring) {
                pcre2_match_data_free(match_data);
                RING_API_ERROR("Memory allocation failed");
                return;
            }
            memcpy(substring, text + ovector[2*i], length);
            substring[length] = '\0';
            ring_list_addstring(pMatchList, substring);
            free(substring);
        }
        
        // Move past this match
        start_offset = ovector[1];
        if (ovector[0] == ovector[1]) {
            if (start_offset >= text_len) break;
            start_offset++;
        }
    }
    
    pcre2_match_data_free(match_data);
    RING_API_RETLIST(pList);
}

// Function to replace matches with backreferences
RING_FUNC(ring_regex_replace_with_refs)
{
    RegexPattern *pattern;
    const char *text, *replacement;
    pcre2_match_data *match_data;
    PCRE2_SIZE outlength;
    char *result;
    int rc, options;
    
    if (RING_API_PARACOUNT != 4) {
        RING_API_ERROR(RING_API_MISS4PARA);
        return;
    }
    
    if (!RING_API_ISPOINTER(1) || !RING_API_ISSTRING(2) || !RING_API_ISSTRING(3) || !RING_API_ISNUMBER(4)) {
        RING_API_ERROR(RING_API_BADPARATYPE);
        return;
    }
    
    pattern = (RegexPattern *)RING_API_GETCPOINTER(1, "RegexPattern");
    if (!pattern) {
        RING_API_ERROR("Invalid regex pattern pointer");
        return;
    }
    
    text = RING_API_GETSTRING(2);
    replacement = RING_API_GETSTRING(3);
    options = (int)RING_API_GETNUMBER(4);
    
    if (!pattern->is_valid) {
        RING_API_ERROR("Invalid regex pattern");
        return;
    }
    
    match_data = pcre2_match_data_create_from_pattern(pattern->regex, NULL);
    
    // Allocate a reasonably large buffer
    outlength = strlen(text) * 2 + strlen(replacement) + 1;
    result = (char *)malloc(outlength);
    
    if (!result) {
        pcre2_match_data_free(match_data);
        RING_API_ERROR("Memory allocation failed");
        return;
    }
    
    rc = pcre2_substitute(
        pattern->regex,
        (PCRE2_SPTR)text,
        strlen(text),
        0,
        options ? 0 : PCRE2_SUBSTITUTE_GLOBAL,
        match_data,
        NULL,
        (PCRE2_SPTR)replacement,
        strlen(replacement),
        (PCRE2_UCHAR *)result,
        &outlength
    );
    
    pcre2_match_data_free(match_data);
    
    if (rc >= 0) {
        result[outlength] = '\0';
        RING_API_RETSTRING(result);
    } else {
        free(result);
        RING_API_RETSTRING(text);  // Return original text if replacement fails
    }
}

RING_API void ringlib_init(RingState *pRingState)
{
    ring_vm_funcregister("regex_new", ring_regex_new);
    ring_vm_funcregister("regex_match", ring_regex_match);
    ring_vm_funcregister("regex_match_positions", ring_regex_match_positions);
    ring_vm_funcregister("regex_match_all", ring_regex_match_all);
    ring_vm_funcregister("regex_replace", ring_regex_replace);
    ring_vm_funcregister("regex_split", ring_regex_split);
    ring_vm_funcregister("regex_is_valid", ring_regex_is_valid);
    ring_vm_funcregister("regex_pattern_info", ring_regex_pattern_info);
    ring_vm_funcregister("regex_find_all", ring_regex_find_all);
    ring_vm_funcregister("regex_replace_with_refs", ring_regex_replace_with_refs);
    ring_vm_funcregister("regex_get_error", ring_regex_get_error);
    ring_vm_funcregister("RegexPattern", NULL);
}
