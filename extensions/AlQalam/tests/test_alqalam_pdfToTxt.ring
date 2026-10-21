load "ringml.ring"

? "----- Extracting text from pdf file ---" 
oReader = new QalamReader
cString = oReader.extractPDFText("1.pdf")
write("1.txt", cString)

? "----- Extract Done ------"
 