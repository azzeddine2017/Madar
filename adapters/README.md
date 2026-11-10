# Madar AI Adapters Directory

This directory stores LoRA (Low-Rank Adaptation) adapter checkpoints generated during fine-tuning sessions using the Madar AI Trainer (`libraries/madar_ai/trainer/trainer.ring`).

## Structure

Adapters are stored in experiment-specific subfolders (e.g., `adapters/qwen_coder_lora/`):

- `adapter_config.json`: Hyperparameters, rank $r$, scaling factor $\alpha$, model dimensions, and target modules.
- `blk.<layer>.attn_q_lora_a.tensor`: LoRA $A$ matrices for target layers.
- `blk.<layer>.attn_q_lora_b.tensor`: LoRA $B$ matrices for target layers.
- `loss_history.csv`: Per-step and epoch loss tracking data.

## Loading Adapters

To attach trained adapters during inference or evaluation:

```ring
load "madar_ai.ring"

oModel = new RingModel("models/qwen2.5-coder-1.5b-instruct-q4_0.gguf", 1)
oModel.load_lora("adapters/qwen_coder_lora/final")
```
