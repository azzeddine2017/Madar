# RingRegex Extension

A comprehensive regular expression library for the Ring programming language,
 built on top of the PCRE2 library for powerful and efficient regex operations.

## Features

- Full PCRE2 regular expression support
- Unicode support
- Case-insensitive matching
- Capturing groups and backreferences
- Pattern validation and error handling
- Convenient class-based interface

## Installation

. `ringpm install ringregex from Azzeddine2017 `

## Usage

### Direct Function Approach

For those who prefer a more direct approach, you can use the functions directly:

```ring
load "ringregex.ring"

# Create a new pattern
pattern = regex_new("(\w+),\s*(\w+)")  # matches "word, word"

# Test if text matches pattern
if regex_match(pattern, "John, Doe")
    ? "Match found!"
ok

# Get match positions (1-based indices)
positions = regex_match_positions(pattern, "John, Doe")
for pos in positions
    ? "Start: " + pos[1] + ", End: " + pos[2]
next

# Get all matches
matches = regex_match_all(pattern, "John, Doe, Jane, Smith")
for match in matches
    ? "Match: " + match
next

# Find all matches with groups
matches = regex_find_all(pattern, "John, Doe, Jane, Smith")
for i = 1 to len(matches) step 3
    ? "Full: " + matches[i]
    ? "First: " + matches[i+1]
    ? "Second: " + matches[i+2]
next

# Replace text
result = regex_replace(pattern, "John, Doe", "Ring")

# Replace with backreferences
result = regex_replace_with_refs(pattern, "John, Doe", "$2, $1", 0)

# Split text
parts = regex_split(pattern, "one, two, three")

# Get pattern information
info = regex_pattern_info(pattern)
? "Valid: " + info[1]
? "Groups: " + info[2]

# Get error message if pattern is invalid
error = regex_get_error(pattern)
```

### Available Functions

| Function | Description |
|----------|-------------|
| `regex_new(pattern, flags = 0)` | Create a new pattern with optional flags |
| `regex_match(pattern, text)` | Test if pattern matches anywhere in text |
| `regex_match_positions(pattern, text)` | Get positions of all matches (1-based) |
| `regex_match_all(pattern, text)` | Get all matching strings |
| `regex_find_all(pattern, text)` | Get all matches with capturing groups |
| `regex_replace(pattern, text, replacement)` | Replace all matches with string |
| `regex_replace_with_refs(pattern, text, replacement, options)` | Replace with backreference support |
| `regex_split(pattern, text)` | Split text using pattern as delimiter |
| `regex_pattern_info(pattern)` | Get pattern information |
| `regex_get_error(pattern)` | Get error message for invalid pattern |

### Class-based Approach (Recommended)

```ring
load "ringregex.ring"

# Create a new RegEx object
regex = new RegEx("(\w+),\s*(\w+)", 0)

# Test if text matches pattern
if regex.match("Hello, World")
    ? "Match found!"
ok

# Find all matches with capturing groups
matches = regex.findAll("John, Doe, Jane, Smith")
for match in matches
    ? "Full match: " + match[1]
    ? "First word: " + match[2]
    ? "Second word: " + match[3]
next

# Replace with backreferences
newText = regex.replaceWithRefs("John, Doe", "$2, $1", 0)  # Result: "Doe, John"

# Split text
parts = regex.split("one,two,three")
for part in parts ? part next

# Check pattern validity
if NOT regex.isValid()
    ? "Error: " + regex.getError()
ok
```

### Pattern Options

When creating a RegEx object, you can specify options as a second parameter:

```ring
# Case-insensitive matching
regex = new RegEx("hello", 1)  # 1 = case insensitive
if regex.match("HELLO")
    ? "Matched!"
ok
```

## Advanced Examples

### Email Validation
```ring
regex = new RegEx("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$", 0)
if regex.test("user@example.com")
    ? "Valid email"
ok
```

### HTML Tag Extraction
```ring
regex = new RegEx("<(\w+)>([^<]*)</\1>", 0)
matches = regex.findAll("<p>Hello</p><b>World</b>")
for match in matches
    ? "Tag: " + match[2]
    ? "Content: " + match[3]
next
```

### Unicode Support
```ring
regex = new RegEx("[\x{0600}-\x{06FF}]+", 0)  # Arabic text
if regex.match("مرحبا بالعالم")
    ? "Arabic text matched!"
ok
```

### URL Validation
```ring
regex = new RegEx("^(https?://)?([a-zA-Z0-9.-]+\.[a-zA-Z]{2,})(:\d+)?(/.*)?$", 0)
if regex.test("https://example.com:8080/path")
    ? "Valid URL"
ok
```

## API Reference

### RegEx Class Methods

| Method | Description |
|--------|-------------|
| `init(pattern, flags = 0)` | Initialize with pattern and flags (0 = default, 1 = case insensitive) |
| `isValid()` | Check if pattern is valid |
| `match(text)` | Test if pattern matches anywhere in text |
| `test(text)` | Test if pattern matches entire text |
| `getMatchPositions(text)` | Get positions of all matches |
| `getAllMatches(text)` | Get all matching strings |
| `findAll(text)` | Get all matches with capturing groups |
| `replace(text, replacement)` | Replace all matches with string |
| `replaceWithRefs(text, replacement, options)` | Replace with backreference support (options: 0 = global, 1 = single) |
| `split(text)` | Split text using pattern as delimiter |
| `getInfo()` | Get pattern information |
| `getError()` | Get last error message |
| `count(text)` | Count number of matches in text |

### Error Handling

The extension provides comprehensive error handling:

```ring
# Invalid pattern
regex = new RegEx("[a-z", 0)  # Missing closing bracket
if NOT regex.isValid()
    ? "Error: " + regex.getError()
ok

# Invalid backreference
regex = new RegEx("(\w+)", 0)
result = regex.replaceWithRefs("hello", "$2", 0)  # $2 doesn't exist
```

## Notes

- All indices in match positions are 1-based (Ring convention)
- Unicode patterns should use `\x{HHHH}` format instead of `\uHHHH`
- The extension automatically enables UTF-8 support
- Memory is managed automatically
  
## fix: enhancements with safety improvements and new features
- Fix critical memory management issues with proper cleanup handlers
- Fix matchAt() position-based matching logic
- Fix match_positions() implementation
- Add comprehensive null pointer validation
- Add support for PCRE2 multiline, dotall, and extended syntax flags
- Introduce new REGEX_* constants for flag configuration
- Add matchFirst() method for retrieving first match as string
- Enable PCRE2 JIT compilation for improved performance
- Enhance error handling with more descriptive messages
- Replace unsafe strncpy with memcpy for string operations
- Add getLastError() method for better error diagnostics
- Update test cases to reflect position-based indexing fixes
  
## License

This extension is released under the MIT License. See the LICENSE file for details.
