load "ringml.ring"

/*
(Cryptography) - LWE System
Modern cryptography (especially post-quantum cryptography) relies entirely on lattices.

The most popular algorithm is LWE (Learning With Errors).

The mathematical concept:
B = A × S + E
A: Public key array.
S: Secret key vector.
E: Small random noise.

B: The resulting public key.

Without RingTensor, multiplying large arrays to generate keys is very time-consuming.
*/

# Output:
/*
λ ring  crypto_lwe.ring                                                 
============================================================            
   Post-Quantum Cryptography Simulation (LWE)                           
   Learning With Errors - Key Generation                                
============================================================            
[1] Generating Public Matrix A (2048x1024)...                           
 Done (106 ms)                                                          
[2] Generating Secret Key S...                                          
[3] Generating Error Noise E...                                         
[4] Computing Public Key B = (A * S) + E...                             
 Done (13.71 ms)                                                        
                                                                        
Key Generation Complete.                                                
Public Key Size: 2048 elements.                                         
Value Sample: 0.04                                                      
*/

func main

    oTime = new QalamChronos()
    ? copy("=", 60)
    ? "   Post-Quantum Cryptography Simulation (LWE)"
    ? "   Learning With Errors - Key Generation"
    ? copy("=", 60)

    # Configuration (Lattice Parameters)
    nDim    = 1024   # Dimension (Security Level)
    nSamples = 2048  # Public Matrix Height

    # ---------------------------------------------------------
    # 1. Generate Public Matrix (A)
    # Large random matrix visible to everyone
    # ---------------------------------------------------------
    ? "[1] Generating Public Matrix A ("+nSamples+"x"+nDim+")..."
    oTime.reset()
    
    oMatA = new Tensor(nSamples, nDim)
    oMatA.random() # Random values [0, 1] (In real crypto, integers mod q)
    
    ? " Done (" + oTime.elapsed() + ")"

    # ---------------------------------------------------------
    # 2. Generate Secret Key (S)
    # Small vector known only to owner
    # ---------------------------------------------------------
    ? "[2] Generating Secret Key S..."
    
    oSecretS = new Tensor(nDim, 1) # Column Vector
    oSecretS.random() 
    oSecretS.subScalar(0.5) # Center around 0
    oSecretS.scalarMul(0.1) # Make it "Small" (Short vector)

    # ---------------------------------------------------------
    # 3. Generate Error Term (E)
    # Tiny noise to hide the secret
    # ---------------------------------------------------------
    ? "[3] Generating Error Noise E..."
    
    oErrorE = new Tensor(nSamples, 1)
    oErrorE.random()
    oErrorE.subScalar(0.5)
    oErrorE.scalarMul(0.001) # Very small noise

    # ---------------------------------------------------------
    # 4. Compute Public Key (B)
    # Formula: B = (A * S) + E
    # This is the heavy operation!
    # ---------------------------------------------------------
    ? "[4] Computing Public Key B = (A * S) + E..."
    oTime.reset()
    
    # Step A: Matrix Multiply (Heavy)
    # (2048 x 1024) * (1024 x 1) -> (2048 x 1)
    oKeyB = oMatA.matmul(oSecretS)
    
    # Step B: Add Noise
    oKeyB.add(oErrorE)
    
    ? " Done (" + oTime.elapsed() + ")"
    
    # Verify Dimensions
    ? nl + "Key Generation Complete."
    ? "Public Key Size: " + oKeyB.nRows + " elements."
    ? "Value Sample: " + oKeyB.getVal(1,1)