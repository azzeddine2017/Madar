# Madar Installation & Quickstart Guide 📦
# دليل تثبيت وتشغيل بيئة مدار (Madar 0.2.0-alpha)

[English Version Below](#english-guide)

---

## 🇸🇦 الدليل العربي

أهلاً بك في **مدار (Madar)** - بيئة التشغيل فائقة السرعة والمطورة لدعم نماذج الذكاء الاصطناعي والحسابات المتجهية والتراكيب اللغوية الحديثة.

---

### 1. المتطلبات الأساسية للنظام (System Requirements)
- **نظام التشغيل:** Windows 10 أو Windows 11 (64-bit).
- **المعالج (CPU):** معالج x64 يدعم تعليمات **AVX2** و **FMA** (معظم معالجات Intel Core الجيل الرابع فما فوق، أو AMD Ryzen).
- **الذاكرة العشوائية (RAM):**
  - للتشغيل الأساسي: 512 ميجابايت.
  - لتشغيل نماذج الذكاء الاصطناعي (0.5B إلى 1.5B): 2 إلى 4 جيجابايت.
  - لتشغيل نماذج 3B: 6 إلى 8 جيجابايت.

---

### 2. التثبيت السريع عبر الحزمة الجاهزة (Pre-built Release)

1. **فك الضغط:**
   قم بفك ضغط ملف `madar-0.2.0-alpha-windows-x64.zip` في أي مجلد تريده (مثلاً: `C:\Madar` أو `D:\Madar`).
2. **التشغيل الفوري (One-Click):**
   اضغط مرتين على ملف **`RingCMD.bat`** في المجلد الرئيسي لفتح موجه أوامر مجهز ببيئة مدار تلقائياً.
3. **(اختياري) إضافة مدار إلى مسار النظام (System PATH):**
   - افتح **إعدادات النظام المتقدمة** (Advanced System Settings) -> **متغيرات البيئة** (Environment Variables).
   - في خانة `Path`، أضف المسار الكامل لمجلد `bin` (مثال: `C:\Madar\bin`).
   - الآن يمكنك كتابة `ring` في أي موجه أوامر أو PowerShell.

---

### 3. تحميل نماذج الذكاء الاصطناعي (Download AI Models)

لتشغيل ميزات الذكاء الاصطناعي والوكيل الذكي، تحتاج لتحميل أحد النماذج المكممة بصيغة GGUF إلى مجلد `models/`:

#### الخيار أ: تحميل نموذج Qwen2.5-0.5B (خفيف وسريع جداً ~350MB):
```cmd
tools\download_model.bat
```

#### الخيار ب: تحميل نموذج DeepSeek-R1-Distill (مع التفكير المنطقي CoT ~1.1GB):
```cmd
tools\download_deepseek.bat
```

---

### 4. تجربة أمثلة الذكاء الاصطناعي (Run AI Examples)

#### 💬 1. الطرفية التفاعلية الشاملة للوكيل الذكي (Interactive Agent CLI):
يدمج الوكيل الذاتي مع أدوات النظام وقاعدة المعرفة والذاكرة المتجهية الدائمة:
```cmd
bin\ring.exe examples\ai\agent_chat.ring
```
**أوامر الطرفية:**
- `/remember <fact>` : حفظ حقيقة في الذاكرة الدائمة على القرص.
- `/recall <query>`   : استرجاع الذواكر بالتشابه الدلالي.
- `/learn <file>`    : استيعاب مستند كامل وتجزئته في قاعدة المعرفة.
- `/tools`           : استعراض جميع الأدوات البرمجية المسجلة.
- `/history`         : استعراض سجل المحادثة النشط.
- `/undo`            : التراجع عن آخر جولة حوارية.
- `exit`             : الخروج مع الحفظ التلقائي للذاكرة.

#### ⚡ 2. البث المباشر للرموز في الوقت الحقيقي (Real-Time Streaming):
توليد الكلمات فائق السرعة عبر محرك C المباشر:
```cmd
bin\ring.exe examples\ai\stream_demo.ring
```

#### 🧠 3. استرجاع المعرفة والذاكرة المتجهية (RAG & VectorStore):
```cmd
bin\ring.exe examples\ai\rag_demo.ring
bin\ring.exe examples\ai\agent_rag_demo.ring
```

#### 📊 4. معالجة الجداول السريعة (C-Accelerated DataFrames):
```cmd
bin\ring.exe examples\ai\dataframe_demo.ring
```

---

### 5. البناء من المصدر (Building From Source)

إذا كنت ترغب في إعادة بناء مدار من الشيفرة المصدرية باستخدام Microsoft Visual C++:

```cmd
:: افتح Native x64 Tools Command Prompt for VS
cd G:\RingProject\Madar

:: بناء المترجم ومحرك الذكاء الاصطناعي كاملاً مع AVX2
language\build\buildvc_x64.bat

:: أو بناء كافة الأدوات والامتدادات دفعة واحدة
tools\build_all.bat
```

---
---

<a name="english-guide"></a>
## 🇬🇧 English Guide

Welcome to **Madar** (مدار) - An AI-Native, High-Performance Dialect and Runtime for the Ring Ecosystem.

---

### 1. System Requirements
- **OS:** Windows 10 / 11 (64-bit).
- **CPU:** x64 processor with **AVX2** & **FMA** instruction set support (Intel Core 4th Gen+ or AMD Ryzen).
- **RAM:**
  - Runtime Core: ~512 MB.
  - LLM Inference (0.5B - 1.5B models): 2 to 4 GB.
  - LLM Inference (3B models): 6 to 8 GB.

---

### 2. Fast Installation (Pre-built Release)

1. **Extract Archive:**
   Extract `madar-0.2.0-alpha-windows-x64.zip` to your preferred directory (e.g., `C:\Madar`).
2. **Instant Shell:**
   Double-click **`RingCMD.bat`** in the root folder to launch an environment pre-configured with `bin\` in PATH.
3. **(Optional) Add to System PATH:**
   - Open **System Properties** -> **Environment Variables**.
   - Edit the `Path` variable under User or System variables, and append: `C:\Madar\bin`.
   - Open a fresh terminal and run: `ring -v` or `ring`.

---

### 3. Downloading Supported GGUF Models

Place any compatible GGUF quantized model into the `models/` directory, or use our automated fetchers:

```cmd
:: Download lightweight Qwen2.5 (Fast & low RAM)
tools\download_model.bat

:: Download DeepSeek-R1-Distill-1.5B (Chain-of-Thought reasoning)
tools\download_deepseek.bat
```

---

### 4. Running Verification Demos

#### 💬 1. Autonomous Agent CLI Terminal:
```cmd
bin\ring.exe examples\ai\agent_chat.ring
```

#### ⚡ 2. Real-Time Token Streaming:
```cmd
bin\ring.exe examples\ai\stream_demo.ring
```

#### 🧠 3. Persistent Vector Memory & RAG Demo:
```cmd
bin\ring.exe examples\ai\agent_rag_demo.ring
```

#### 📊 4. Fast C-Tensor DataFrames:
```cmd
bin\ring.exe examples\ai\dataframe_demo.ring
```

---

### 5. Building from Source

```cmd
:: Using Visual Studio 2022 (x64 Native Tools Command Prompt)
cd \path\to\Madar
language\build\buildvc_x64.bat

:: Run comprehensive automated test suite
tests\run_all.bat
```
