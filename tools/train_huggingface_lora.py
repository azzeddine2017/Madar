# ====================================================================
# Madar AI - Hugging Face LoRA Fine-Tuning Script
# Reference Baseline: Qwen2.5-Coder-1.5B on Ring Bilingual Dataset
# ====================================================================

import os
import sys
import argparse
import json
import torch
from datasets import Dataset
from transformers import (
    AutoModelForCausalLM,
    AutoTokenizer,
    BitsAndBytesConfig,
    TrainingArguments
)
from peft import LoraConfig, get_peft_model, prepare_model_for_kbit_training
from trl import SFTTrainer, SFTConfig

def parse_args():
    parser = argparse.ArgumentParser(description="Hugging Face LoRA Training for Madar Ring AI")
    parser.add_argument("--model_id", type=str, default="Qwen/Qwen2.5-Coder-1.5B-Instruct", help="Hugging Face Model ID")
    parser.add_argument("--dataset_path", type=str, default="data/ring_instruct_bilingual.jsonl", help="Path to bilingual dataset")
    parser.add_argument("--output_dir", type=str, default="adapters/qwen_coder_hf_lora", help="Output directory for LoRA adapters")
    parser.add_argument("--epochs", type=int, default=3, help="Number of training epochs")
    parser.add_argument("--batch_size", type=int, default=2, help="Per device batch size")
    parser.add_argument("--grad_accum", type=int, default=4, help="Gradient accumulation steps")
    parser.add_argument("--lr", type=float, default=5e-5, help="Peak learning rate")
    parser.add_argument("--max_seq_len", type=int, default=512, help="Maximum sequence length")
    parser.add_argument("--lora_rank", type=int, default=16, help="LoRA rank")
    parser.add_argument("--lora_alpha", type=int, default=16, help="LoRA alpha")
    parser.add_argument("--merge", action="store_true", help="Merge adapters into base model after training")
    return parser.parse_args()

def load_ring_dataset(cPath, oTokenizer):
    print(f">>> [1/5] Loading and formatting dataset: {cPath}")
    aRecords = []
    with open(cPath, "r", encoding="utf-8") as f:
        for line in f:
            if line.strip():
                aRecords.append(json.loads(line))
    
    print(f"    Loaded {len(aRecords)} samples from dataset.")

    # Convert to standard ChatML format
    formatted_data = []
    for item in aRecords:
        cInstruction = item.get("instruction", "")
        cInput = item.get("input", "")
        cOutput = item.get("output", "")
        
        cUserContent = cInstruction
        if cInput and cInput.strip():
            cUserContent += "\n" + cInput.strip()
            
        messages = [
            {"role": "system", "content": "You are an expert Ring programming assistant."},
            {"role": "user", "content": cUserContent},
            {"role": "assistant", "content": cOutput}
        ]
        
        formatted_data.append({"messages": messages})
        
    return Dataset.from_list(formatted_data)

def main():
    args = parse_args()
    print("=" * 68)
    print("  Madar AI - Hugging Face Official LoRA Fine-Tuner")
    print("=" * 68)
    print(f"  Model ID       : {args.model_id}")
    print(f"  Dataset        : {args.dataset_path}")
    print(f"  Epochs         : {args.epochs}")
    print(f"  Batch Size     : {args.batch_size} (Accum: {args.grad_accum})")
    print(f"  Learning Rate  : {args.lr}")
    print(f"  LoRA Rank      : {args.lora_rank} (Alpha: {args.lora_alpha})")
    print(f"  Output Dir     : {args.output_dir}")
    print("=" * 68)

    # 1. Tokenizer
    print("\n>>> [2/5] Loading Tokenizer...")
    tokenizer = AutoTokenizer.from_pretrained(args.model_id, trust_remote_code=True)
    if tokenizer.pad_token is None:
        tokenizer.pad_token = tokenizer.eos_token
    tokenizer.padding_side = "right"

    # 2. Dataset
    dataset = load_ring_dataset(args.dataset_path, tokenizer)

    # 3. Model with 4-bit QLoRA
    print("\n>>> [3/5] Loading Model in 4-bit NormalFloat (NF4)...")
    bnb_config = BitsAndBytesConfig(
        load_in_4bit=True,
        bnb_4bit_quant_type="nf4",
        bnb_4bit_compute_dtype=torch.float16,
        bnb_4bit_use_double_quant=True,
    )
    
    device_map = "auto" if torch.cuda.is_available() else None
    model = AutoModelForCausalLM.from_pretrained(
        args.model_id,
        quantization_config=bnb_config,
        device_map=device_map,
        trust_remote_code=True,
        torch_dtype=torch.float16
    )
    model.config.torch_dtype = torch.float16
    model = prepare_model_for_kbit_training(model)

    # 4. LoRA Configuration
    print("\n>>> [4/5] Initializing LoRA Adapters...")
    peft_config = LoraConfig(
        r=args.lora_rank,
        lora_alpha=args.lora_alpha,
        target_modules=["q_proj", "k_proj", "v_proj", "o_proj"],
        lora_dropout=0.05,
        bias="none",
        task_type="CAUSAL_LM"
    )
    model = get_peft_model(model, peft_config)

    # Ensure all LoRA layers and trainable parameters are float32 (fixes Tesla T4 GradScaler error)
    for name, module in model.named_modules():
        if "lora" in name.lower():
            module.to(torch.float32)
    for param in model.parameters():
        if param.requires_grad:
            param.data = param.data.float()

    model.print_trainable_parameters()

    training_args = SFTConfig(
        output_dir=args.output_dir,
        max_length=args.max_seq_len,
        num_train_epochs=args.epochs,
        per_device_train_batch_size=args.batch_size,
        gradient_accumulation_steps=args.grad_accum,
        learning_rate=args.lr,
        lr_scheduler_type="cosine",
        warmup_steps=20,
        logging_steps=10,
        save_strategy="steps",
        save_steps=200,
        save_total_limit=3,
        fp16=True,
        bf16=False,
        optim="paged_adamw_8bit",
        report_to="none"
    )

    trainer = SFTTrainer(
        model=model,
        train_dataset=dataset,
        args=training_args
    )

    print("\n>>> [5/5] Starting Hugging Face Training Loop...")
    train_result = trainer.train()

    print("\n" + "=" * 68)
    print("  Training Completed! Saving Final LoRA Adapters...")
    print("=" * 68)
    trainer.model.save_pretrained(args.output_dir)
    tokenizer.save_pretrained(args.output_dir)
    print(f"  Adapters saved to: {args.output_dir}")

    # Log metrics
    metrics = train_result.metrics
    trainer.log_metrics("train", metrics)
    trainer.save_metrics("train", metrics)

    # Optional merge
    if args.merge:
        print("\n>>> Merging LoRA adapters with base model...")
        del model
        torch.cuda.empty_cache()
        base_model = AutoModelForCausalLM.from_pretrained(
            args.model_id,
            torch_dtype=torch.float16,
            device_map="auto",
            trust_remote_code=True
        )
        from peft import PeftModel
        merged_model = PeftModel.from_pretrained(base_model, args.output_dir)
        merged_model = merged_model.merge_and_unload()
        merged_out = os.path.join(args.output_dir, "merged_model")
        merged_model.save_pretrained(merged_out)
        tokenizer.save_pretrained(merged_out)
        print(f"  Merged standalone model saved to: {merged_out}")

if __name__ == "__main__":
    main()

