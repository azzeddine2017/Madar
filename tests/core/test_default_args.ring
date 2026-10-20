# =========================================================
# Madar Core Test: Python-style Default Arguments
# =========================================================

load "../test_harness.ring"

suite("Madar Core - Python Default Arguments (func f(a, b=10))")

# --- 1. Basic Single Numeric Default ---

assert_equal(15, add_default(5), "Calling with default argument omitted (add_default(5))")
assert_equal(25, add_default(5, 20), "Calling with default argument overridden (add_default(5, 20))")

# --- 2. Multiple Default Arguments ---

assert_equal("localhost:8080:1:30", server_config("localhost"), "Multiple defaults - all omitted")
assert_equal("remote:443:1:30", server_config("remote", 443), "Multiple defaults - 1 provided, 2 defaults")
assert_equal("remote:443:0:30", server_config("remote", 443, 0), "Multiple defaults - 2 provided, 1 default")
assert_equal("remote:443:0:60", server_config("remote", 443, 0, 60), "Multiple defaults - all provided")

# --- 3. String and List Defaults ---

assert_equal("Hello Madar!", greet("Madar"), "String defaults - omitted")
assert_equal("Hi Madar!", greet("Madar", "Hi"), "String defaults - greeting overridden")
assert_equal("Welcome Madar?", greet("Madar", "Welcome", "?"), "String defaults - all overridden")

# --- 4. All Arguments Have Defaults (Zero-argument Call) ---

assert_equal("guest:viewer", default_user(), "All default arguments - called with 0 arguments")
assert_equal("admin:viewer", default_user("admin"), "All default arguments - called with 1 argument")
assert_equal("admin:root", default_user("admin", "root"), "All default arguments - called with 2 arguments")

# --- 5. Default Expression Referring to Prior Parameter ---

assert_equal(25, rect_area(5), "Default referencing prior parameter (square)")
assert_equal(50, rect_area(5, 10), "Default referencing prior parameter overridden (rectangle)")

# --- 6. Fresh Dynamic Evaluation (No Mutable Default Bug) ---


list1 = append_to_fresh_list("first")
list2 = append_to_fresh_list("second")
assert_equal(1, len(list1), "First call produces new list with 1 item")
assert_equal("first", list1[1], "First list contains expected item")
assert_equal(1, len(list2), "Second call gets fresh list (avoids Python mutable default bug)")
assert_equal("second", list2[1], "Second list contains expected item")

# --- 7. Anonymous Function with Default Arguments ---
calc = func(x, factor = 2, bias = 5) {
	return (x * factor) + bias
}

assert_equal(25, call calc(10), "Anonymous function with default arguments (all defaults)")
assert_equal(35, call calc(10, 3), "Anonymous function with 1 override")
assert_equal(31, call calc(10, 3, 1), "Anonymous function with all overrides")

# --- 8. Class Methods with Default Arguments ---

m = new MathHelper
assert_equal(20, m.multiply(4), "Class method with default argument omitted")
assert_equal(24, m.multiply(4, 6), "Class method with default argument provided")
assert_equal(19, m.power_offset(3), "Class method with multiple defaults (3^2 + 10)")
assert_equal(37, m.power_offset(3, 3), "Class method with 1 default (3^3 + 10)")
assert_equal(28, m.power_offset(3, 3, 1), "Class method with all arguments (3^3 + 1)")

# --- 9. Runtime Argument Count Introspection (argcount / paramcount) ---

counts1 = inspect_args(100)
assert_equal(1, counts1[1], "argcount() returns 1 when 1 argument is passed")
assert_equal(1, counts1[2], "paramcount() alias returns 1 when 1 argument is passed")

counts2 = inspect_args(100, 200)
assert_equal(2, counts2[1], "argcount() returns 2 when 2 arguments are passed")

counts3 = inspect_args(100, 200, 300)
assert_equal(3, counts3[1], "argcount() returns 3 when 3 arguments are passed")

# --- 10. Using 'def' Keyword (Python Syntax) ---

assert_equal(150, py_calculate(10), "def keyword function with defaults")
assert_equal(80, py_calculate(10, 3), "def keyword function with 1 override")

# --- 11. Complex Default Expression (Math & Builtins) ---

assert_equal(15, complex_defaults(1), "Complex default expressions (arithmetic and len())")

test_summary()

func add_default(a, b = 10)
	return a + b

func server_config(host, port = 8080, secure = 1, timeout = 30)
	return host + ":" + port + ":" + secure + ":" + timeout

func greet(name, greeting = "Hello", punctuation = "!")
	return greeting + " " + name + punctuation

func default_user(name = "guest", role = "viewer")
	return name + ":" + role

func rect_area(width, height = width)
	return width * height

func append_to_fresh_list(item, my_list = [])
	add(my_list, item)
	return my_list

func inspect_args(a, b = 10, c = 20)
	return [argcount(), paramcount()]

def py_calculate(base, mult = 10, add_val = 50)
	return (base * mult) + add_val

func complex_defaults(x, y = 2 * 3 + 4, z = len("test"))
	return x + y + z


class MathHelper
	func multiply(a, b = 5)
		return a * b

	func power_offset(x, p = 2, offset = 10)
		res = 1
		for i = 1 to p { res = res * x }
		return res + offset
