# =========================================================
# Madar Test Suite: High-Resolution Hardware Monotonic Timers
# Verifies nanotime(), microtime(), perf_counter(), and Chronos
# =========================================================

load "../test_harness.ring"
load "chronos.ring"

suite("Madar Core - High-Resolution Hardware Timers & Chronos")

# 1. Existence and Type Checking
t_ns = nanotime()
assert_true(isnumber(t_ns), "nanotime() returns a number")
assert_true(t_ns > 0, "nanotime() > 0")

t_us = microtime()
assert_true(isnumber(t_us), "microtime() returns a number")
assert_true(t_us > 0, "microtime() > 0")

t_sec = perf_counter()
assert_true(isnumber(t_sec), "perf_counter() returns a number")
assert_true(t_sec > 0, "perf_counter() > 0")

t_hr = hrtime()
assert_true(isnumber(t_hr), "hrtime() returns a number")
assert_true(t_hr > 0, "hrtime() > 0")

# 2. Monotonicity (Time strictly moves forward)
t1 = nanotime()
nSum = 0
for i = 1 to 10000
	nSum += i
next
t2 = nanotime()
assert_true(t2 > t1, "nanotime() is strictly monotonic (t2 > t1)")
assert_true((t2 - t1) > 0, "Measured non-zero elapsed nanoseconds for 10k iterations")

# 3. Microsecond and Second Monotonicity
u1 = microtime()
for i = 1 to 10000
	nSum += i
next
u2 = microtime()
assert_true(u2 >= u1, "microtime() is monotonic (u2 >= u1)")

p1 = perf_counter()
for i = 1 to 10000
	nSum += i
next
p2 = perf_counter()
assert_true(p2 >= p1, "perf_counter() is monotonic (p2 >= p1)")

# 4. Consistency across units
snap_ns = nanotime()
snap_us = microtime()
snap_pc = perf_counter()

diff_us = (snap_ns / 1000.0) - snap_us
if diff_us < 0 diff_us = -diff_us ok
assert_true(diff_us < 50000.0, "nanotime() and microtime() are tightly aligned")

diff_sec = (snap_ns / 1000000000.0) - snap_pc
if diff_sec < 0 diff_sec = -diff_sec ok
assert_true(diff_sec < 0.05, "nanotime() and perf_counter() are tightly aligned")

# 5. Chronos OOP Stopwatch Class
oWatch = new Chronos()
assert_true(isobject(oWatch), "Chronos instance successfully created")
assert_true(oWatch.bIsRunning, "Chronos starts in running state")

for i = 1 to 5000
	nSum += i
next
nElapsedWatchNs = oWatch.elapsed_ns()
assert_true(nElapsedWatchNs > 0, "Chronos.elapsed_ns() > 0")
assert_true(oWatch.elapsed_us() > 0, "Chronos.elapsed_us() > 0")
assert_true(oWatch.elapsed_ms() >= 0, "Chronos.elapsed_ms() >= 0")
assert_true(oWatch.elapsed_sec() >= 0, "Chronos.elapsed_sec() >= 0")

nFinalNs = oWatch.stop()
assert_true(nFinalNs > 0, "Chronos.stop() returns positive duration")
assert_true(not oWatch.bIsRunning, "Chronos.bIsRunning is false after stop()")

# Format string output
cFormatted = oWatch.elapsed()
assert_true(len(cFormatted) > 0, "Chronos.elapsed() formatted string is non-empty")

test_summary()
