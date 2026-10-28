load "ringregex.ring"
load "stdlib.ring"
/*
    File: practical_examples.ring
    Description: Practical examples using RegEx class
    Author: Azzeddine Remmal
    Version: 1.0
*/

# Example 1: Log File Analysis
? "Example 1: Log File Analysis"
? "========================="

# Sample log entries
logText = "
2024-01-20 10:15:30 [INFO] User login: john@example.com
2024-01-20 10:16:45 [ERROR] Database connection failed
2024-01-20 10:17:20 [INFO] User login: mary@example.com
2024-01-20 10:18:00 [WARNING] High memory usage detected
"

# Create regex pattern to parse log entries
regex = new RegEx("(\d{4}-\d{2}-\d{2}\s\d{2}:\d{2}:\d{2})\s\[(\w+)\]\s(.+)", 0)

# Check if pattern is valid
if NOT regex.isValid()
    ? "Error: Invalid regex pattern - " + regex.getError()
    return
ok

# Find all matches
matches = regex.findAll(logText)

if len(matches) = 0
    ? "No log entries found"
    return
ok

? "Log Analysis Results:"
for match in matches
    timestamp = match[2]  # First capturing group
    level = match[3]      # Second capturing group
    message = match[4]    # Third capturing group
    
    ? "Time: " + timestamp
    ? "Level: " + level
    ? "Message: " + message
    ? ""
next

# Example 2: CSV Parser
? nl + "Example 2: CSV Parser"
? "==================="

csvText = '
name,age,email
"John Smith",30,john@example.com
"Mary Jones",25,mary@example.com
"Bob Wilson",45,bob@example.com
'

regex = new RegEx('([^,\n"]+|"[^"]*")', 0)
lines = split(csvText, nl)

for line in lines
    if len(line) > 0
        matches = regex.findAll(line)
        for match in matches
            field = match[1]
            # Remove quotes if present
            field = substr(field, '"', '')
            ? "Field: " + field
        next
        ? ""
    ok
next

# Example 3: HTML Tag Parser
? nl + "Example 3: HTML Tag Parser"
? "======================="

# Simple HTML example
htmlText = "<h1>Welcome</h1><p>Hello World</p>"

# Basic HTML tag pattern - using simpler pattern
regex = new RegEx("<h1>([^<]+)</h1>", 0)

# Check if pattern is valid
if NOT regex.isValid()
    ? "Error: Invalid regex pattern - " + regex.getError()
    return
ok

matches = regex.findAll(htmlText)

if len(matches) = 0
    ? "No HTML elements found"
    return
ok

? "HTML Elements Found:"
for match in matches
    ? "Tag: h1"
    ? "Content: " + match[2]
    ? ""
next

# Now try to match paragraph
regex = new RegEx("<p>([^<]+)</p>", 0)

matches = regex.findAll(htmlText)
for match in matches
    ? "Tag: p"
    ? "Content: " + match[2]
    ? ""
next

# Example 4: HTML Text Extraction
? nl + "Example 4: HTML Text Extraction"
? "=========================="

# Sample HTML page
htmlPage = '
<!DOCTYPE html>
<html>
<head>
    <title>Welcome to My Website</title>
    <meta charset="UTF-8">
</head>
<body>
    <div class="header">
        <h1>Main Title</h1>
        <p class="subtitle">This is a subtitle</p>
    </div>
    <div class="content">
        <h2>Article Title</h2>
        <p>This is the first paragraph with some <b>bold text</b> and a <a href="https://example.com">link</a>.</p>
        <p>Another paragraph with <i>italic text</i> and some numbers: 123.</p>
        <ul>
            <li>First item</li>
            <li>Second item</li>
            <li>Third item</li>
        </ul>
    </div>
    <div class="footer">
        <p>&copy; 2025 My Website</p>
    </div>
</body>
</html>
'

# Extract all text between tags
regex = new RegEx(">([^<]+)<", 0)
matches = regex.findAll(htmlPage)

? "Extracted Text:"
for match in matches
    text = match[2]
    if len(trim(text)) > 0
        ? trim(text)
    ok
next

? nl + "Extracting Specific Elements:"

# Extract titles (h1, h2)
regex = new RegEx("<h[1-2][^>]*>([^<]+)</h[1-2]>", 0)
matches = regex.findAll(htmlPage)

? nl + "Titles Found:"
for match in matches
    ? "- " + match[2]
next

# Extract paragraphs
regex = new RegEx("<p[^>]*>([^<]+)[^>]*</p>", 0)
matches = regex.findAll(htmlPage)

? nl + "Paragraphs Found:"
for match in matches
    ? "- " + match[2]
next

# Extract list items
regex = new RegEx("<li>([^<]+)</li>", 0)
matches = regex.findAll(htmlPage)

? nl + "List Items Found:"
for match in matches
    ? "- " + match[2]
next
