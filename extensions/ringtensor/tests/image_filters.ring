load "ringml.ring"

/*
(Image Processing) 
Digital images are simply massive arrays of numbers (pixels).
If you have a 4K image (3840 x 2160), it contains 8.2 million pixels.
Processing it pixel by pixel in a script would be extremely slow.
In this example,
we will simulate Photoshop filters (Invert, Brightness, Blending) 
on ​​a massive image at lightning speed.
*/

# Out
/*
λ ring  image_filters.ring
============================================================
   High-Performance Image Processing (4K Simulation)
   Resolution: 3840x2160 (8294400 Pixels)
============================================================
[1] Loading 4K Image into Memory... Done (380.64 ms)
[2] Applying 'Negative' Filter... Done (56.18 ms)
[3] Adjusting Brightness (+20%) & Contrast (x1.5)... Done (87.03 ms)
[4] Blending with another Image (Watermark)... Done (565.10 ms)
*/

func main
    
    # 1. Setup Image Dimensions (4K Resolution)
    nWidth  = 3840
    nHeight = 2160
    oTime = new QalamChronos()
    
    see copy("=", 60) + nl
    see "   High-Performance Image Processing (4K Simulation)" + nl
    see "   Resolution: " + nWidth + "x" + nHeight + " (" + (nWidth*nHeight) + " Pixels)" + nl
    see copy("=", 60) + nl

    # ---------------------------------------------------------
    # 2. Load Image (Simulated)
    # ---------------------------------------------------------
    see "[1] Loading 4K Image into Memory..."
    oTime.reset()
    
    # Image A: Represents raw photo (Values 0.0 to 1.0)
    oImg = new Tensor(nHeight, nWidth)
    oImg.random() 
    
    see " Done (" + oTime.elapsed() + ")" + nl

    # ---------------------------------------------------------
    # 3. Filter: Invert Colors (Negative)
    # Formula: Pixel = 1.0 - Pixel
    # ---------------------------------------------------------
    see "[2] Applying 'Negative' Filter..."
    oTime.reset()
    
    # Create a white canvas (All 1.0)
    oWhite = new Tensor(nHeight, nWidth)
    oWhite.fill(1.0)
    
    # Subtraction (Vectorized)
    oNegative = oWhite
    oNegative.sub(oImg)
    
    see " Done (" + oTime.elapsed() + ")" + nl

    # ---------------------------------------------------------
    # 4. Filter: Brightness & Contrast
    # Formula: Pixel = (Pixel * Contrast) + Brightness
    # ---------------------------------------------------------
    see "[3] Adjusting Brightness (+20%) & Contrast (x1.5)..."
    oTime.reset()
    
    oProcessed = oImg.copy() # Copy original
    oProcessed.scalarMul(1.5) # Contrast
    oProcessed.addScalar(0.2) # Brightness
    
    see " Done (" + oTime.elapsed() + ")" + nl

    # ---------------------------------------------------------
    # 5. Filter: Image Blending (Alpha Compositing)
    # Formula: Result = (ImgA * 0.7) + (ImgB * 0.3)
    # ---------------------------------------------------------
    see "[4] Blending with another Image (Watermark)..."
    oTime.reset()
    
    # Generate second image (Noise/Texture)
    oWatermark = new Tensor(nHeight, nWidth)
    oWatermark.random()
    
    # Apply weights
    oImg.scalarMul(0.7)
    oWatermark.scalarMul(0.3)
    
    # Combine
    oFinal = oImg
    oFinal.add(oWatermark)
    
    see " Done (" + oTime.elapsed() + ")" + nl

