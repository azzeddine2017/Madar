# Load the regex extension 
if isWindows()
    LoadLib("ringregex.dll")
else
    LoadLib("bin/libringregex.so")
ok

/*
    Class: RegEx
    Description: A class that provides a high-level interface 
				 for regular expressions using PCRE2.
    Author: Azzeddine Remmal
    Version: 1.0
*/

# Regex flags constants
REGEX_CASELESS = 1
REGEX_MULTILINE = 2
REGEX_DOTALL = 4
REGEX_EXTENDED = 8


class RegEx

    # Pattern object returned by regex_new()
    pattern
    # Flags used when creating the pattern
    flags
    lastError = ""
    
    /*
        Function: init
        Description: Creates a new regex pattern with optional flags
        Parameters:
            cPattern [String] - The regular expression pattern
            nFlags [Number] -  nflags (0 = default, 1 = case insensitive)
        Returns: None
    */
    func init cPattern, nFlags
        if NOT isString(cPattern)
            lastError = "Pattern must be a string"
            raise("Error: " + lastError)
        ok
        if isNull(nFlags) nFlags = 0 ok
        flags = nFlags
        pattern = regex_new(cPattern, nFlags)
        if NOT isValid()
            lastError = getError()
            raise("Error: Invalid regex pattern - " + lastError)
        ok
        return self
    
    /*
        Function: isValid
        Description: Checks if the pattern is valid
        Returns: True if pattern is valid, False otherwise
    */
    func isValid
        if pattern = NULL return false ok
        return regex_pattern_info(pattern)[1] = 1
    
    /*
        Function: match
        Description: Tests if the pattern matches anywhere in the text
        Parameters:
            cText [String] - The text to search in
        Returns: True if a match is found, False otherwise
    */
    func match cText
        if NOT isValid() 
            raise("Error: Invalid regex pattern - " + getError())
            return false
        ok
        if NOT isString(cText)
            raise("Error: Text must be a string")
            return false
        ok
        return regex_match(pattern, cText)

    /*
        Function: matchFirst
        Description: Gets the first match in the text
        Parameters:
            cText [String] - The text to search in
        Returns: String of the first match or empty string if no match
    */
    func matchFirst cText
        if NOT isValid() 
            raise("Error: Invalid regex pattern - " + getError())
            return ""
        ok
        matches = getAllMatches(cText)
        if len(matches) > 0 and len(matches[1]) > 0
            return matches[1][1]  # Return the first full match
        ok
        return ""
    
    /*
        Function: matchAt
        Description: Tests if the pattern matches at a specific position
        Parameters:
            cText [String] - The text to search in
            nPos [Number] - The position to start matching from (1-based)
        Returns: True if a match is found at the position, False otherwise
    */
    func matchAt cText, nPos
        if NOT isValid() 
            raise("Error: Invalid regex pattern - " + getError())
            return false
        ok
        if NOT isString(cText)
            raise("Error: Text must be a string")
            return false
        ok
        if NOT isNumber(nPos)
            raise("Error: Position must be a number")
            return false
        ok
        if nPos <= 0 nPos = 1 ok
        
        # Get substring from the position
        cSubText = substr(cText, nPos)
        if len(cSubText) = 0 return false ok
        
        # Match on the substring
        pos_list = regex_match_positions(pattern, cSubText)
        if islist(pos_list) and len(pos_list) > 0 and islist(pos_list[1]) and len(pos_list[1]) >= 2
            # check that there is a match at the start of the substring
            if pos_list[1][1] = 1
                # Match found at the specified position
                return true
            else
                # Match found, but not at the specified position
                return false
            ok
        else
            # No match found at the specified position
            return false
        ok

    /*
        Function: getMatchPositions
        Description: Gets the positions of all matches
        Parameters:
            cText [String] - The text to search in
        Returns: List of lists containing start and end positions
    */
    func getMatchPositions cText
        if NOT isValid() 
            raise("Error: Invalid regex pattern - " + getError())
            return []
        ok
        if NOT isString(cText)
            raise("Error: Text must be a string")
            return []
        ok
        return regex_match_positions(pattern, cText)
    
    /*
        Function: getAllMatches
        Description: Gets all non-overlapping matches in the text
        Parameters:
            cText [String] - The text to search in
        Returns: List of matched strings
    */
    func getAllMatches cText
        if NOT isValid() 
            raise("Error: Invalid regex pattern - " + getError())
            return []
        ok
        if NOT isString(cText)
            raise("Error: Text must be a string")
            return []
        ok
        matches = regex_find_all(pattern, cText)
        if type(matches) = "LIST"
            return matches
        ok
        return []
    
    /*
        Function: findAll
        Description: Finds all matches in the text and returns them as a list
        Parameters:
            cText [String] - The text to search in
        Returns: List of matches, where each match is a list containing:
                - The full match at index 1
                - Any capturing groups at subsequent indices
    */
    func findAll cText
        if NOT isValid() 
            raise("Error: Invalid regex pattern - " + getError())
            return []
        ok
        if NOT isString(cText)
            raise("Error: Text must be a string")
            return []
        ok
        matches = regex_find_all(pattern, cText)
        if type(matches) = "LIST"
            return matches
        ok
        return []
    
    /*
        Function: replace
        Description: Replaces all matches with a new string
        Parameters:
            cText [String] - The text to perform replacements in
            cReplacement [String] - The replacement string
        Returns: The text with all matches replaced
    */
    func replace cText, cReplacement
        if NOT isValid() 
            raise("Error: Invalid regex pattern - " + getError())
            return cText
        ok
        if NOT isString(cText) OR NOT isString(cReplacement)
            raise("Error: Text and replacement must be strings")
            return cText
        ok
        return regex_replace(pattern, cText, cReplacement)
    
    /*
        Function: replaceWithRefs
        Description: Replaces matches with support for backreferences
        Parameters:
            cText [String] - The text to perform replacements in
            cReplacement [String] - The replacement string with backreferences
            nOptions [Number] - Options (0 = global replace, 1 = single replace)
        Returns: The text with matches replaced
    */
    func replaceWithRefs cText, cReplacement, nOptions
        if NOT isValid() 
            raise("Error: Invalid regex pattern - " + getError())
            return cText
        ok
        if NOT isString(cText) OR NOT isString(cReplacement)
            raise("Error: Text and replacement must be strings")
            return cText
        ok
        if NOT isNumber(nOptions)
            raise("Error: Options must be a number (0 or 1)")
            return cText
        ok
        return regex_replace_with_refs(pattern, cText, cReplacement, nOptions)
    
    /*
        Function: split
        Description: Splits text using the pattern as delimiter
        Parameters:
            cText [String] - The text to split
        Returns: List of strings
    */
    func split cText
        if NOT isValid() 
            raise("Error: Invalid regex pattern - " + getError())
            return [cText]
        ok
        if NOT isString(cText)
            raise("Error: Text must be a string")
            return [cText]
        ok
        return regex_split(pattern, cText)
    
    /*
        Function: test
        Description: Tests if the entire text matches the pattern
        Parameters:
            cText [String] - The text to test
        Returns: True if the entire text matches, False otherwise
    */
    func test cText
        return match(cText)
    
    /*
        Function: count
        Description: Counts the number of matches in the text
        Parameters:
            cText [String] - The text to count matches in
        Returns: Number of matches found
    */
    func count cText
        if NOT isValid() 
            raise("Error: Invalid regex pattern - " + getError())
            return 0
        ok
        if NOT isString(cText)
            raise("Error: Text must be a string")
            return 0
        ok
        return len(getAllMatches(cText))
    
    /*
        Function: getInfo
        Description: Gets information about the pattern
        Returns: List containing pattern options and minimum match length
    */
    func getInfo
        if NOT isValid() 
            raise("Error: Invalid regex pattern - " + getError())
            return []
        ok
        return regex_pattern_info(pattern)
    
    /*
        Function: getError
        Description: Gets the last error message
        Returns: String containing the error message
    */
    func getError
        return regex_get_error(pattern)
    
    func getLastError
        return lastError
    
