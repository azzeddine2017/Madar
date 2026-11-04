# File: extensions/ringtensor/tests/test_adam.ring

load "ringtensor.ring"

see "=== Testing Adam Optimizer Kernel ===" + nl

# Setup 1x1 params
W = tensor_init(1, 1)
tensor_fill(W, 0.5) # Initial Weight

Grad = tensor_init(1, 1)
tensor_fill(Grad, 0.1) # Gradient

M = tensor_init(1, 1) # Momentum
V = tensor_init(1, 1) # Velocity

# Hyperparams
LR = 0.01
B1 = 0.9
B2 = 0.999
Eps = 0.00000001
Time = 1

see "Old Weight: " + tensor_get(W, 1, 1) + nl

# Run Adam Update (C Function)
tensor_update_adam(W, Grad, M, V, LR, B1, B2, Eps, Time)

NewW = tensor_get(W, 1, 1)
see "New Weight: " + NewW + nl

if NewW != 0.5
    see "PASS: Weight updated successfully." + nl
else
    see "FAIL: Weight did not change." + nl
ok