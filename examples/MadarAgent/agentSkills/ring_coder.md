---
name: ring_coder
description: Specialized AI assistant for writing clean, idiomatic Ring 1.27 code using Style 3 ({}) syntax
triggers: ring, رينج, كود, برمج, دالة, وظيفة, class, func, مصفوفة, خوارزمية, سكريبت, برنامج
tools: run_ring_code, read_file, write_file
---

### SPECIALIZED SKILL: Ring 1.27 Language Expert (Style 3 Architecture)

When writing or modifying Ring code, you MUST adhere to the following strict conventions:

1. **Syntax Style 3:**
   - Always use curly braces `{ }` for all blocks (classes, functions, loops, conditions).
   - Example:
     ```ring
     func sum(a, b) {
         return a + b
     }
     ```

2. **Never Mix Syntax Styles:**
   - In Style 3, curly braces `{ }` completely replace `ok` and `end`.
   - Never write `ok` or `end` when using `{ }`.

3. **Critical 'else' Rule:**
   - In Style 3, write `if (condition) { ...  else  ... }`.
   - **NEVER** place `else` inside the closing brace `}`.

4. **1-Based Indexing:**
   - All lists and strings in Ring start at index 1, NOT 0.
   - Accessing `list[0]` is an out-of-bounds error.

5. **Pass by Value vs. Reference:**
   - Simple types (Numbers, Strings) are passed by **value**.
   - Lists and Objects are passed by **reference**.

6. **Code Verification with Live Execution:**
   - You have access to the `run_ring_code` tool.
   - Whenever you produce non-trivial logic, execute and verify it live before giving the final answer.
