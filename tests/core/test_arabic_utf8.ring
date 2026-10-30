# =========================================================
# Madar Test Suite: Native Arabic & Unicode UTF-8 (ascii & char)
# Verifies multi-byte UTF-8 decoding in ascii() and encoding in char()
# =========================================================

load "../test_harness.ring"

suite("Madar Core - Native Arabic & Unicode UTF-8 (ascii & char)")

# 1. Backward Compatibility for 1-byte ASCII
assert_equal(65, ascii("A"), "ascii('A') returns 65")
assert_equal(97, ascii("a"), "ascii('a') returns 97")
assert_equal(48, ascii("0"), "ascii('0') returns 48")
assert_equal("A", char(65), "char(65) returns 'A'")
assert_equal("z", char(122), "char(122) returns 'z'")
assert_equal("A", char(ascii("A")), "char(ascii('A')) roundtrip")

# 2. Arabic Alphabet Letters (2-byte UTF-8, U+0600 - U+06FF)
assert_equal(1575, ascii("ا"), "ascii('ا') returns 1575 (Alif, 0x0627)")
assert_equal(1576, ascii("ب"), "ascii('ب') returns 1576 (Baa, 0x0628)")
assert_equal(1578, ascii("ت"), "ascii('ت') returns 1578 (Taa, 0x062A)")
assert_equal(1580, ascii("ج"), "ascii('ج') returns 1580 (Jeem, 0x062C)")
assert_equal(1583, ascii("د"), "ascii('د') returns 1583 (Dal, 0x062F)")
assert_equal(1585, ascii("ر"), "ascii('ر') returns 1585 (Raa, 0x0631)")
assert_equal(1605, ascii("م"), "ascii('م') returns 1605 (Meem, 0x0645)")
assert_equal(1610, ascii("ي"), "ascii('ي') returns 1610 (Yaa, 0x064A)")

# 3. Arabic Diacritics / Tashkeel
assert_equal(1614, ascii("َ"), "ascii(Fatha) returns 1614 (0x064E)")
assert_equal(1615, ascii("ُ"), "ascii(Damma) returns 1615 (0x064F)")
assert_equal(1616, ascii("ِ"), "ascii(Kasra) returns 1616 (0x0650)")
assert_equal(1618, ascii("ْ"), "ascii(Sukun) returns 1618 (0x0652)")
assert_equal(1617, ascii("ّ"), "ascii(Shadda) returns 1617 (0x0651)")

# 4. UTF-8 Encoding with char() for Arabic
assert_equal("ا", char(1575), "char(1575) returns 'ا'")
assert_equal("ب", char(1576), "char(1576) returns 'ب'")
assert_equal("د", char(1583), "char(1583) returns 'د'")
assert_equal("ر", char(1585), "char(1585) returns 'ر'")
assert_equal("م", char(1605), "char(1605) returns 'م'")

# 5. Word Construction with char()
cWord = char(1605) + char(1583) + char(1575) + char(1585)
assert_equal("مدار", cWord, "char(1605)+char(1583)+char(1575)+char(1585) produces 'مدار'")

cAlgeria = char(1575) + char(1604) + char(1580) + char(1586) + char(1575) + char(1574) + char(1585)
assert_equal("الجزائر", cAlgeria, "Word assembly produces 'الجزائر'")

# 6. Bijective Roundtrip Symmetry across Arabic Block
bAllSymmetric = true
for nCode = 1569 to 1610
	cCh = char(nCode)
	if ascii(cCh) != nCode
		bAllSymmetric = false
		exit
	ok
next
assert_true(bAllSymmetric, "Full Arabic alphabet (1569..1610) satisfies char(ascii(c)) == c roundtrip")

# 7. Multi-Byte UTF-8 (3-byte and 4-byte)
assert_equal("€", char(8364), "char(8364) generates 3-byte Euro symbol '€'")
assert_equal(8364, ascii("€"), "ascii('€') decodes 3-byte symbol to 8364")
assert_equal("🚀", char(128640), "char(128640) generates 4-byte Rocket emoji '🚀'")
assert_equal(128640, ascii("🚀"), "ascii('🚀') decodes 4-byte emoji to 128640")

test_summary()

