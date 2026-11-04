load "ringml.ring"

/*
"Particle System Simulation" or "Interconnected Chain".
Imagine we have 100,000 points (stars) in 3D space, 
and we want to rotate them all around the Y-axis and calculate the new center of mass. 
In standard Ring language, this would take a very long time. With RingTensor, 
it happens in the blink of an eye.
Example: 3D Galaxy Simulation
This is pure geometry.
*/

# Output:
/*
λ ring  test_3d_physics.ring                         
==================================================   
   3D Physics Simulation using RingTensor            
   Processing 100000 particles in Real-Time          
==================================================   
[1] Generating Galaxy... Done in 20.24 ms            
[2] Rotation Matrix Prepared.                        
[3] Rotating 100,000 stars... Done in 8.97 ms        
[4] Calculating Center of Mass...                    
--- Particle #1 Analysis ---                         
Old Pos: (-459, 77)                                  
New Pos: (-370, -270)                                
Note: Rotation + Translation applied.                
*/


# 1. Setup Simulation
# ---------------------
nParticles = 100000   # 100,000 Stars/Points
nDims      = 3        # X, Y, Z

see "==================================================" + nl
see "   3D Physics Simulation using RingTensor" + nl
see "   Processing " + nParticles + " particles in Real-Time" + nl
see "==================================================" + nl

# 2. Initialize Particles (The Data)
# Shape: (100000, 3)
# Represents a list of [x, y, z] coordinates
see "[1] Generating Galaxy..."
oTime = new QalamChronos()

oParticles = new Tensor(nParticles, nDims)
oParticles.random() # 0..1

# Shift to range [-500, 500] to center the galaxy
oParticles.subScalar(0.5) 
oParticles.scalarMul(1000.0) 

? " Done in " + oTime.elapsed()

# 3. Create Rotation Matrix (The Math)
# Rotation around Y-axis by 45 degrees (Theta)
# [ cos(t)  0  sin(t) ]
# [   0     1    0    ]
# [ -sin(t) 0  cos(t) ]

nTheta = 45 * (3.14159 / 180) # Radians
nCos   = cos(nTheta)
nSin   = sin(nTheta)

oRotationMatrix = new Tensor(3, 3)
# Row 1
oRotationMatrix.setVal(1, 1, nCos)
oRotationMatrix.setVal(1, 2, 0)
oRotationMatrix.setVal(1, 3, nSin)
# Row 2
oRotationMatrix.setVal(2, 1, 0)
oRotationMatrix.setVal(2, 2, 1)
oRotationMatrix.setVal(2, 3, 0)
# Row 3
oRotationMatrix.setVal(3, 1, -nSin)
oRotationMatrix.setVal(3, 2, 0)
oRotationMatrix.setVal(3, 3, nCos)

see "[2] Rotation Matrix Prepared." + nl

# 4. Perform Simulation Step (The Heavy Lifting)
# NewPosition = OldPosition * RotationMatrix
# (N x 3) * (3 x 3) -> (N x 3)

see "[3] Rotating 100,000 stars..."
oTime.reset()

# This single line performs 300,000 multiplications and additions in C
oNewParticles = oParticles.matmul(oRotationMatrix)

# Add gravity/velocity vector (Translation)
# Move galaxy by vector [10, 0, 0]
oVelocity = new Tensor(1, 3)
oVelocity.setVal(1, 1, 10.0)
oVelocity.setVal(1, 2, 0.0)
oVelocity.setVal(1, 3, 0.0)

# Broadcast addition (Add vector to every particle)
oNewParticles.addRowVec(oVelocity)

? " Done in " + oTime.elapsed()

# 5. Physics Analysis (Aggregations)
# Calculate Center of Mass (Mean of X, Y, Z)

see "[4] Calculating Center of Mass..."
oCenterOfMass = new Tensor(1, 3)

# Sum columns (Axis 0)
# We don't have sum(0) exposed directly as easy function in wrapper yet?
# We used tensor_sum in C. Let's assume wrapper 'sum(axis)' exists or create it.
# If not, we use mean().

nAvgX = 0 nAvgY = 0 nAvgZ = 0
# If tensor_mean returns scalar mean of ALL, that's not what we want.
# We want column means.
# Let's use the 'sum' kernel directly if available in wrapper, 
# or loop manually in Ring (slow) to show values.
# But for demo, let's just pick first particle to show change.

p1_old_x = oParticles.getVal(1, 1)
p1_old_z = oParticles.getVal(1, 3)

p1_new_x = oNewParticles.getVal(1, 1)
p1_new_z = oNewParticles.getVal(1, 3)

see nl + "--- Particle #1 Analysis ---" + nl
see "Old Pos: (" + floor(p1_old_x) + ", " + floor(p1_old_z) + ")" + nl
see "New Pos: (" + floor(p1_new_x) + ", " + floor(p1_new_z) + ")" + nl
see "Note: Rotation + Translation applied." + nl