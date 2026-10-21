/*
** TinyMath Engine for AlQalam
** Compiles string formulas into Bytecode instructions.
*/

#ifndef TINY_MATH_H
#define TINY_MATH_H

#include <vector>
#include <string>
#include <stack>
#include <map>
#include <cmath>
#include <iostream>

// --- Opcodes ---
enum QOpCode {
    Q_OP_PUSH_VAL = 1,
    Q_OP_PUSH_X   = 2,
    Q_OP_ADD      = 3,
    Q_OP_SUB      = 4,
    Q_OP_MUL      = 5,
    Q_OP_DIV      = 6,
    Q_OP_POW      = 7,
    Q_OP_SIN      = 8,
    Q_OP_COS      = 9,
    Q_OP_TAN      = 10,
    Q_OP_ABS      = 11,
    Q_OP_RELU     = 12,
    Q_OP_SQRT     = 13,
    Q_OP_LOG      = 14,
    Q_OP_EXP      = 15
};

struct Instruction {
    int opcode;
    double value;
};

// --- Helper Maps ---
int get_precedence(int op) {
    if (op == Q_OP_ADD || op == Q_OP_SUB) return 1;
    if (op == Q_OP_MUL || op == Q_OP_DIV) return 2;
    if (op == Q_OP_POW) return 3;
    return 0; // Functions have highest precedence implicitly handled
}

// --- The Compiler Class ---
class FormulaCompiler {
public:
    std::vector<Instruction> program;
    std::stack<int> op_stack; // Store OpCodes

    void compile(const char* expr) {
        program.clear();
        while (!op_stack.empty()) op_stack.pop();

        std::string s = expr;
        size_t i = 0;

        while (i < s.length()) {
            char c = s[i];

            // 1. Skip Whitespace
            if (isspace(c)) { i++; continue; }

            // 2. Numbers
            if (isdigit(c) || c == '.') {
                size_t start = i;
                while (i < s.length() && (isdigit(s[i]) || s[i] == '.')) i++;
                double val = std::stod(s.substr(start, i - start));
                program.push_back({Q_OP_PUSH_VAL, val});
                continue;
            }

            // 3. Variable 'x'
            if (c == 'x') {
                program.push_back({Q_OP_PUSH_X, 0});
                i++; continue;
            }

            // 4. Functions & Operators
            if (isalpha(c)) {
                // Parse Function Name (sin, cos, etc.)
                size_t start = i;
                while (i < s.length() && isalpha(s[i])) i++;
                std::string func = s.substr(start, i - start);
                
                int op = 0;
                if (func == "sin") op = Q_OP_SIN;
                else if (func == "cos") op = Q_OP_COS;
                else if (func == "tan") op = Q_OP_TAN;
                else if (func == "abs") op = Q_OP_ABS;
                else if (func == "relu") op = Q_OP_RELU;
                else if (func == "sqrt") op = Q_OP_SQRT;
                else if (func == "log") op = Q_OP_LOG;
                else if (func == "exp") op = Q_OP_EXP;
                
                if (op > 0) op_stack.push(op);
                continue;
            }

            // 5. Operators
            int op = 0;
            if (c == '+') op = Q_OP_ADD;
            else if (c == '-') op = Q_OP_SUB;
            else if (c == '*') op = Q_OP_MUL;
            else if (c == '/') op = Q_OP_DIV;
            else if (c == '^') op = Q_OP_POW;

            if (op > 0) {
                while (!op_stack.empty() && op_stack.top() != '(' && 
                       get_precedence(op_stack.top()) >= get_precedence(op)) {
                    program.push_back({op_stack.top(), 0});
                    op_stack.pop();
                }
                op_stack.push(op);
                i++; continue;
            }

            // 6. Parentheses
            if (c == '(') {
                op_stack.push('(');
                i++; continue;
            }
            if (c == ')') {
                while (!op_stack.empty() && op_stack.top() != '(') {
                    program.push_back({op_stack.top(), 0});
                    op_stack.pop();
                }
                if (!op_stack.empty()) op_stack.pop(); // Pop '('
                
                // If token on top of stack is a function, pop it too
                if (!op_stack.empty() && op_stack.top() >= Q_OP_SIN) {
                    program.push_back({op_stack.top(), 0});
                    op_stack.pop();
                }
                i++; continue;
            }
            
            i++; // Skip unknown
        }

        while (!op_stack.empty()) {
            if (op_stack.top() != '(') program.push_back({op_stack.top(), 0});
            op_stack.pop();
        }
    }
};

#endif