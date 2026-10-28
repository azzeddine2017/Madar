load "ringregex.ring"

/*
    File: test_function_regex.ring
    Description: Examples demonstrating the usage of the RegEx functions
    Author: Azzeddine Remmal
    Version: 1.0
    regex_new
    regex_match
    regex_match_positions
    regex_match_all
    regex_replace
    regex_split
    regex_is_valid
    regex_pattern_info
    regex_find_all
    regex_replace_with_refs
*/

? "Testing RingRegex Extension"
? "=========================="

? nl + "Test 1: Basic Pattern Matching"
pattern = regex_new("World")
if regex_match(pattern, "Hello, World!")
    ? "Match found!"
else
    ? "No match"
ok
if regex_match(pattern, "Hello, Ring!")
    ? "Match found!"
else
    ? "No match"
ok
# Test empty string
if regex_match(pattern, "")
    ? "Match found!"
else
    ? "No match"
ok

? nl + "Test 2: Match Positions"
pattern = regex_new("o(.+?)o")
text = "Hello, World! How are you?"
positions = regex_match_positions(pattern, text)
? "Match positions for 'o(.+?)o':"
if islist(positions)
    for pos in positions
        if islist(pos) and len(pos) >= 2
            ? "Start: " + pos[1] + ", End: " + pos[2]
        ok
    next
else
    ? "No matches found"
ok
# Test with no matches
positions = regex_match_positions(pattern, "Hi!")
? "Matches found: " + len(positions)

? nl + "Test 3: Match All (Capturing Groups)"
pattern = regex_new("(\w+),\s*(\w+)")
text = "Hello, World! Ring, Language! Test, Case!"
matches = regex_match_all(pattern, text)
? "Matches for '(\w+),\s*(\w+)':"
for match in matches
    ? match
next
# Test with no capturing groups
pattern = regex_new("\w+")
matches = regex_match_all(pattern, "Hello World")
? "Simple matches count: " + len(matches)

? nl + "Test 4: Replace"
pattern = regex_new("Ring", 1)  # REG_ICASE = 1
text = "Ring is great! Ring is awesome!"
result = regex_replace(pattern, text, "RingRegex")
? "Replace 'Ring' with 'RingRegex':"
? result
# Test replace with empty string
result = regex_replace(pattern, text, "")
? "Replace 'Ring' with empty string:"
? result

? nl + "Test 5: Split"
pattern = regex_new("[,\s]+")
text = "Ring,is,a great,programming    language"
parts = regex_split(pattern, text)
? "Split text by commas and whitespace:"
for part in parts
    ? part
next
# Test split with empty parts
text = ",,Ring,,Lang,,"
parts = regex_split(pattern, text)
? "Split with empty parts count: " + len(parts)

? nl + "Test 6: Advanced Pattern with Flags"
# Case insensitive matching using REG_ICASE flag
pattern = regex_new("ring", 1)  # REG_ICASE = 1
? "Case insensitive match:"
if regex_match(pattern, "RING is awesome")
    ? "Match found!"
else
    ? "No match"
ok
if regex_match(pattern, "RiNg is great")
    ? "Match found!"
else
    ? "No match"
ok
# Test with multiple flags
pattern = regex_new("^ring$", 1)  # REG_ICASE with start/end anchors
if regex_match(pattern, "RING")
    ? "Exact match found!"
else
    ? "No exact match"
ok

? nl + "Test 7: Find All Matches"
pattern = regex_new("\d+")  # Match one or more digits
text = "I am 25 years old and I have 3 cats and 2 dogs"
matches = regex_find_all(pattern, text)
? "Numbers in text:"
for match in matches
    ? match
next
# Test overlapping patterns
pattern = regex_new("(\w+)(?:\s+\1)+")  # Find repeated words
text = "hello hello world world"
matches = regex_find_all(pattern, text)
? "Repeated words:"
for match in matches
    ? match
next

? nl + "Test 8: Pattern Information"
pattern = regex_new("(\w+)@(\w+)\.(\w+)")
info = regex_pattern_info(pattern)
? "Pattern Information:"
? "Valid: " + info[1]
? "Capturing Groups: " + info[2]
# Test complex pattern
pattern = regex_new("(?:https?://)?(?:www\.)?(\w+\.\w+)(?:/\S*)?")
info = regex_pattern_info(pattern)
? "URL Pattern Groups: " + info[2]

? nl + "Test 9: Error Handling"
pattern = regex_new("(invalid[regex")  # Invalid pattern
? "Error message: " + regex_get_error(pattern)
# Test unmatched parenthesis
pattern = regex_new("((test)")
? "Unmatched parenthesis error: " + regex_get_error(pattern)
# Test invalid character class
pattern = regex_new("[a-")
? "Invalid character class error: " + regex_get_error(pattern)

? nl + "Test 10: Unicode Support"
pattern = regex_new("[\x{0600}-\x{06FF}]+")  # Arabic characters
text = "مرحبا بالعالم"
if regex_match(pattern, text)
    ? "Arabic text matched!"
else
    ? "Arabic text not matched"
ok
# Test mixed scripts
pattern = regex_new("[\x{0600}-\x{06FF}]+\s+\w+")
text = "مرحبا World"
if regex_match(pattern, text)
    ? "Mixed script matched!"
else
    ? "Mixed script not matched"
ok

? nl + "Test 11: Complex Patterns"
# Email validation
pattern = regex_new("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$")
emails = ["test@example.com", "invalid@", "user.name@domain.co.uk"]
for email in emails
    if regex_match(pattern, email)
        ? "Email " + email + " is valid"
    else
        ? "Email " + email + " is invalid"
    ok
next

# URL validation
pattern = regex_new("^(https?://)?([a-zA-Z0-9.-]+\.[a-zA-Z]{2,})(/.*)?$")
urls = ["https://example.com", "invalid url", "domain.com/path?query=1"]
for url in urls
    if regex_match(pattern, url)
        ? "URL " + url + " is valid"
    else
        ? "URL " + url + " is invalid"
    ok
next
