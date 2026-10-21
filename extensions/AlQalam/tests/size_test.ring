load "ringml.ring"
oVec = new QalamVector(576)
oVec.write(1, 123.4)
oVec.write(576, 456.7)
see "Size is: " + oVec.size() + nl
see "Val 1: " + oVec.read(1) + nl
see "Val 576: " + oVec.read(576) + nl
