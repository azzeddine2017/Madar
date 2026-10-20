# =========================================================
# Madar Core Test: Python-style Formatted String Literals (f-strings)
# =========================================================

load "../test_harness.ring"

suite("Madar Core - Python f-strings (f'...' and f'...')")

# --- 1. Basic Variable Interpolation ---
name = "Madar"
version = "0.2.0"
s = f"Welcome to {name} v{version}!"
assert_equal("Welcome to Madar v0.2.0!", s, "Basic variable interpolation in double quotes")

# --- 2. Single-Quote and Backtick f-strings ---
city = "Algiers"
s2 = f'City: {city}'
assert_equal("City: Algiers", s2, "Single-quote f-string (f'...')")

s3 = f`Location: {city}`
assert_equal("Location: Algiers", s3, "Backtick f-string (f`...`)")

# --- 3. Arithmetic Expressions ---
a = 10
b = 20
s_math = f"Sum: {a + b}, Prod: {a * b}"
assert_equal("Sum: 30, Prod: 200", s_math, "Arithmetic expressions inside f-string")

s_calc = f"1 + 2 = {1 + 2}"
assert_equal("1 + 2 = 3", s_calc, "Literal constants arithmetic inside f-string")

# --- 4. Empty and Plain f-strings ---
s_empty = f""
assert_equal("", s_empty, 'Empty f-string f\"\"')

s_plain = f"No interpolations here"
assert_equal("No interpolations here", s_plain, "Plain text f-string")

# --- 5. Adjacent and Multi-Interpolations ---
first = "A"
second = "B"
s_adj = f"{first}{second}"
assert_equal("AB", s_adj, 'Adjacent interpolations without separators f\"{first}{second}\"')

s_multi = f"{first}-{second}-{a}"
assert_equal("A-B-10", s_multi, "Multiple separated interpolations")

# --- 6. Function Calls Inside Interpolations ---
msg = "hello world"
s_func = f"Length of '{msg}' is {len(msg)}"
assert_equal("Length of 'hello world' is 11", s_func, "Function call inside interpolation")

# --- 7. Numeric & Boolean Conversions ---
nScore = 99.5
lActive = 1
s_types = f"Score: {nScore}, Active: {lActive}"
assert_equal("Score: 99.50, Active: 1", s_types, "Number and boolean conversion to string")

# --- 8. Escaped Braces with {{ and }} ---
s_escape1 = f"Literal {{brace}}"
assert_equal("Literal {brace}", s_escape1, "Escaped braces using {{ and }}")

s_escape2 = f'JSON: {{ \"key\": \"{name}\" }}'
assert_equal('JSON: { \"key\": \"Madar\" }', s_escape2, "Escaped braces around variable in JSON-like structure")

# --- 9. Escaped Braces with \{ and \} ---
s_escape3 = f"Literal \{brace\}"
assert_equal("Literal {brace}", s_escape3, "Escaped braces using \\{ and \\}")

# --- 10. Inner Quotes and Hash-Map Lookup ---
user = [:name = "Zaid", :role = "Admin"]
s_hash = f"User {user[:name]} has role {user[:role]}"
assert_equal("User Zaid has role Admin", s_hash, "Hash-map lookup inside interpolation")

# --- 11. Nested f-strings ---
val = 42
s_nested = f"Outer: { f'Inner: {val}' }"
assert_equal("Outer: Inner: 42", s_nested, 'Nested f-string f\"Outer: { f"Inner: {val}" }\"')

# --- 12. f-string in Expressions & Conditions ---
status = "OK"
if f"Status: {status}" = "Status: OK"
	assert_true(true, "f-string equality comparison in if-condition")
else
	assert_true(false, "f-string equality comparison in if-condition")
ok

test_summary()
