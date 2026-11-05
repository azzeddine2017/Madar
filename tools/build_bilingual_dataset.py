# Tools: Build Bilingual (Arabic / English) Ring Instruction Dataset
# Generates data/ring_instruct_bilingual.jsonl (1,460 samples)

import json
import re
import time
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed

SRC_FILE = "data/ring_instruct_dataset.jsonl"
OUT_FILE = "data/ring_instruct_bilingual.jsonl"

def translate_to_arabic(text: str) -> str:
    """Translates an English sentence/phrase to Arabic via public endpoint with retries."""
    if not text or not text.strip():
        return text
    clean_text = text.strip()
    for attempt in range(4):
        try:
            url = (
                "https://translate.googleapis.com/translate_a/single?client=gtx&sl=en&tl=ar&dt=t&q="
                + urllib.parse.quote(clean_text)
            )
            req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
            with urllib.request.urlopen(req, timeout=8) as resp:
                res = json.loads(resp.read().decode("utf-8"))
                translated = "".join([part[0] for part in res[0]])
                return refine_arabic_terms(translated)
        except Exception:
            time.sleep(0.5 * (attempt + 1))
    return clean_text

def refine_arabic_terms(text: str) -> str:
    """Polishes machine-translated phrases into standard Arabic programming terminology."""
    text = re.sub(r'\bوظيفة\b', 'دالة', text)
    text = re.sub(r'\bالوظيفة\b', 'الدالة', text)
    text = text.replace('رمز الرنين', 'كود رينج')
    text = text.replace('كود الرنين', 'كود رينج')
    text = text.replace('لغة الرنين', 'لغة رينج')
    text = text.replace('الرنين', 'رينج')
    text = text.replace('رنين', 'رينج')
    text = re.sub(r'\bفي Ring\b', 'في لغة رينج', text)
    text = re.sub(r'\bمع Ring\b', 'مع لغة رينج', text)
    text = re.sub(r'\bلـ Ring\b', 'للغة رينج', text)
    text = re.sub(r'\bRing\b', 'رينج', text)
    return text

def clean_english_record(item: dict) -> dict:
    """Cleans up scraping metadata artifacts from original English entry."""
    out = item.get("output", "")
    out_cleaned = re.sub(r'\tpair:[^\n]+', '', out)
    return {
        "instruction": item["instruction"].strip(),
        "input": "",
        "output": out_cleaned.strip()
    }

def translate_record_to_arabic(item: dict) -> dict:
    """Translates instruction and markdown prose while preserving code blocks verbatim."""
    inst = item["instruction"].strip()
    ar_inst = translate_to_arabic(inst)

    out = item.get("output", "")
    out_clean = re.sub(r'\tpair:[^\n]+', '', out)

    # Standardize markdown headers
    out_clean = out_clean.replace("### Syntax:", "### الصيغة البرمجية:")
    out_clean = out_clean.replace("### Code Example:", "### مثال الكود:")
    out_clean = out_clean.replace("### Output:", "### الناتج:")

    # Split output into code blocks and prose blocks
    parts = re.split(r'(```(?:ring)?[\s\S]*?```)', out_clean)
    trans_parts = []
    for p in parts:
        if p.startswith("```"):
            # Never translate code blocks!
            trans_parts.append(p)
        else:
            lines = p.split("\n")
            ar_lines = []
            for line in lines:
                stripped = line.strip()
                if not stripped or stripped.startswith("###"):
                    ar_lines.append(line)
                else:
                    ar_lines.append(translate_to_arabic(stripped))
            trans_parts.append("\n".join(ar_lines))

    ar_output = "".join(trans_parts).strip()
    return {
        "instruction": ar_inst,
        "input": "",
        "output": ar_output
    }

def main():
    print("=" * 65)
    print("  Building Bilingual (Arabic/English) Ring Instruction Dataset")
    print("=" * 65)

    with open(SRC_FILE, "r", encoding="utf-8") as f:
        raw_items = [json.loads(line, strict=False) for line in f]

    n_total = len(raw_items)
    print(f"Loaded {n_total} English samples from {SRC_FILE}")
    print("Translating instructions and markdown explanations into Arabic...")

    ar_results = [None] * n_total
    en_clean_results = [None] * n_total

    for idx, it in enumerate(raw_items):
        en_clean_results[idx] = clean_english_record(it)

    t0 = time.time()
    n_workers = 12

    def worker_task(i, item):
        return i, translate_record_to_arabic(item)

    with ThreadPoolExecutor(max_workers=n_workers) as executor:
        future_map = {executor.submit(worker_task, i, raw_items[i]): i for i in range(n_total)}
        completed = 0
        for fut in as_completed(future_map):
            idx, ar_rec = fut.result()
            ar_results[idx] = ar_rec
            completed += 1
            if completed % 50 == 0 or completed == n_total:
                elapsed = time.time() - t0
                rate = completed / elapsed
                print(f"  [{completed}/{n_total}] ({completed*100/n_total:.1f}%) in {elapsed:.1f}s (~{rate:.1f} items/s)")

    # Combine interleaved: English, Arabic, English, Arabic...
    bilingual_records = []
    for en_rec, ar_rec in zip(en_clean_results, ar_results):
        bilingual_records.append(en_rec)
        bilingual_records.append(ar_rec)

    print(f"\nWriting {len(bilingual_records)} bilingual pairs to {OUT_FILE}...")
    with open(OUT_FILE, "w", encoding="utf-8") as f_out:
        for rec in bilingual_records:
            f_out.write(json.dumps(rec, ensure_ascii=False) + "\n")

    t_total = time.time() - t0
    print(f"Done! Dataset compiled in {t_total:.1f}s.")
    print(f"Output: {OUT_FILE} ({len(bilingual_records)} samples)")

if __name__ == "__main__":
    main()
