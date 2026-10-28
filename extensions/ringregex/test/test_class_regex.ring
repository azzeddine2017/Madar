load "ringregex.ring"
/*
    File: test_class_regex.ring
    Description: Examples demonstrating the usage of the RegEx class
    Author: Azzeddine Remmal
    Version: 1.0
    Class: RegEx
    Method: match(text)
    Method: match_positions(text)
    Method: match_all(text)
    Method: replace(text, replacement)
    Method: split(text)
    Method: is_valid()
    Method: pattern_info()
    Method: find_all(text)
    Method: replace_with_refs(text, replacement)
*/

# Example 1: Basic Pattern Matching
? "Example 1: Basic Pattern Matching"
? "============================="

regex = new RegEx("\d+", 0)  # matches one or more digits
text = "The number 19 is here"

if regex.match(text)
    ? "Found a number!"
    matches = regex.findAll(text)
    ? "Numbers found: " + len(matches)
    for match in matches
        ? "Number: " + match[1]  # First element is the full match
    next
ok

? nl + "Example 2: Case Insensitive Matching"
? "============================="

regex = new RegEx("hello", 1)  # 1 = case insensitive
? 'Matching "HELLO" case insensitive: ' + regex.match("HELLO")
? 'Matching "hello" case insensitive: ' + regex.match("hello")
? 'Matching "Hello World" case insensitive: ' + regex.match("Hello World")

? nl + "Example 3: Pattern Groups and References"
? "============================="

regex = new RegEx("(\w+),\s*(\w+)", 0)
text = "John, Doe"

if regex.match(text)
    matches = regex.findAll(text)
    ? "Number of matches: " + len(matches)
    if len(matches) > 0
        ? "Full match: " + matches[1][1]  # First match, full match
        if len(matches[1]) >= 3
            ? "First name: " + matches[1][2]  # First match, first group
            ? "Last name: " + matches[1][3]   # First match, second group
        ok
    ok
    
    # Test backreference replacement
    newText = regex.replaceWithRefs(text, "$2, $1", 0)
    ? "Swapped names: " + newText
ok

? nl + "Example 4: Email Validation"
? "============================="

regex = new RegEx("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$", 0)
? "Valid email: test@example.com -> " + regex.test("test@example.com")
? "Invalid email: invalid.email -> " + regex.test("invalid.email")
? "Valid email: another@domain.co.uk -> " + regex.test("another@domain.co.uk")

? nl + "Example 5: HTML Tag Extraction"
? "============================="

regex = new RegEx("<([a-z]+)>([^<]+)</\\1>", 0)
text = "<b>bold</b><i>italic</i>"
matches = regex.findAll(text)
? "Found " + len(matches) + " matches:"
for match in matches
    ? "Match: " + match[1]  # Full match
    if len(match) >= 3
        ? "  Tag: " + match[2]     # First group (tag name)
        ? "  Content: " + match[3]  # Second group (content)
    ok
next

? nl + "Example 6: Word Count"
? "============================="

regex = new RegEx("[A-Za-z]+", 0)
text = "The quick brown fox jumps over the lazy dog"
matches = regex.findAll(text)
? "Number of words: " + len(matches)
for i = 1 to len(matches)
    ? "Word " + i + ": " + matches[i][1]  # First element of each match
next

? nl + "Example 7: Phone Number Format Validation"
? "============================="

regex = new RegEx("^[0-9+]+$", 0)
? "Valid phone number: +1234567890 -> " + regex.test("+1234567890")
? "Invalid phone number: 123-456-7890 -> " + regex.test("123-456-7890")
? "Valid phone number: 12345 -> " + regex.test("12345")

? nl + "Example 8: URL Validation"
? "============================="

regex = new RegEx("^(https?://)?([a-zA-Z0-9][a-zA-Z0-9.-]*\.[a-zA-Z]{2,})(/[a-zA-Z0-9._/?%&=-]*)?$", 0)
? "Valid URL: https://example.com -> " + regex.test("https://example.com")
? "Valid URL: http://sub.domain.co.uk/path -> " + regex.test("http://sub.domain.co.uk/path")
? "Invalid URL: invalid url -> " + regex.test("invalid url")
? "Valid URL: example.com/path?q=1 -> " + regex.test("example.com/path?q=1")

? nl + "Example 9: Unicode Support"
? "============================="

regex = new RegEx("[\x{0600}-\x{06FF}]+", 0)  # Arabic text
? "Arabic text matched: مرحبا بالعالم -> " + regex.match("مرحبا بالعالم")
? "Mixed text matched: مرحبا World -> " + regex.match("مرحبا World")

? nl + "Example 10: Error Handling"
? "============================="

regex = new RegEx("(\w+)", 0)
? "Result with invalid backreference: " + regex.replaceWithRefs("hello", "$2", 0)

try
    regex = new RegEx("[a-z", 0)  # Invalid pattern
    ? "Pattern is valid (should not see this)"
catch
    ? "Error caught (expected): Invalid regex pattern"
done

? nl + "Example 11: Match At Position"
? "============================="

regex = new RegEx("\d+", 0)
text = "The number 123 and 456"

matches = regex.findAll(text)
? "Numbers found: " + len(matches)
for match in matches
    ? "Number: " + match[1]  # First element is the full match
next

pos_list = regex.getMatchPositions(text)
for i = 1 to len(pos_list)
    ? "Match " + i + ": Start at " + pos_list[i][1] + ", End at " + pos_list[i][2]
next

# Test matching at different positions
? "Text: " + text
? "Match at position 1: " + regex.matchAt(text, 1)    # Should be false
? "Match at position 11: " + regex.matchAt(text, 12)  # Should be true (123)
? "Match at position 19: " + regex.matchAt(text, 20)  # Should be true (456)
? "Match at position 15: " + regex.matchAt(text, 15)  # Should be false

# Test with invalid position
? "Match at position -1: " + regex.matchAt(text, -1)  # Should use position 1

# Test with invalid pattern
try
    regex = new RegEx("[a-z", 0)  # Invalid pattern
    regex.matchAt(text, 1)
    ? "Should not reach this line"
catch
    ? "Error caught (expected): Invalid regex pattern"
done
