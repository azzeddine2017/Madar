load "ringregex.ring"

/*
* Arabic Text Processing Examples
* This file demonstrates various Arabic text processing techniques using RingRegex
  Author: Azzeddine Remmal
  Version: 1.0
*/

? "مثال 1: التحقق من صحة النص العربي"
? "=============================="

# التحقق من وجود حروف عربية فقط
arabicText = "مرحباً بكم في لغة رينج"
regex = new RegEx("[ء-ي\s]+", 0)

if regex.match(arabicText)
    ? "النص يحتوي على حروف عربية فقط"
else
    ? "النص يحتوي على حروف غير عربية"
ok

? nl + "مثال 2: استخراج الكلمات العربية"
? "=============================="

mixedText = "Hello مرحباً Ring رينج World عالم!"
regex = new RegEx("[ء-ي]+", 0)
matches = regex.findAll(mixedText)

? "الكلمات العربية المستخرجة:"
for match in matches
    ? match[1]
next

? nl + "مثال 3: تنسيق الأرقام العربية"
? "=============================="

numbers = "٠١٢٣٤٥٦٧٨٩"

# Create number mapping
arabicNumbers = "٠١٢٣٤٥٦٧٨٩"
englishNumbers = "0123456789"

# Create regex pattern for all Arabic numbers
regex = new RegEx("[٠-٩]", 0)


# Convert all numbers at once
result = numbers
matches = regex.findAll(numbers)
for match in matches
    arabicNum = match[1]
    englishNum = convertArabicNumber(arabicNum)
    regex2 = new RegEx(arabicNum, 0)
    result = regex2.replace(result, englishNum)
next

? "الأرقام العربية: " + numbers
? "الأرقام الإنجليزية: " + result


? nl + "مثال 4: تنظيف النص العربي"
? "========================="

dirtyText = "هذا،   نص    عربي   مع   فراغات   زائدة!!!"
regex = new RegEx("\s+", 0)
cleanText = regex.replace(dirtyText, " ")

? "النص الأصلي: " + dirtyText
? "النص المنظف: " + cleanText

? nl + "مثال 5: استخراج الكلمات العربية من النص"
? "=============================="

mixedText = "Hello مرحباً Ring رينج World عالم!"
regex = new RegEx("[ء-ي]+", 0)
matches = regex.findAll(mixedText)

? "الكلمات العربية المستخرجة:"
for match in matches
    ? match[1]
next

# Function to convert Arabic number to English
func convertArabicNumber num
    pos = substr(arabicNumbers, num)
    if pos > 0
        return substr(englishNumbers, pos, 1)
    ok
    return num
