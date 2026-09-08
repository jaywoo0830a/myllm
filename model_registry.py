# Model registry for multi‑agent local AI system
# This file defines the models required by the PLAN.md specification.
# Each entry contains the slug (used for config files and server startup),
# the model name, quantisation, approximate size, role and number of instances.
# The values are based on the PLAN.md table.

MODEL_REGISTRY = {
    "parser": {
        "slug": "parser",
        "model_name": "Qwen2.5-7B-Instruct",
        "quant": "Q4_K_M",
        "size_gb": 5,
        "role": "작업 분배 Parser",
        "instances": 1,
    },
    "worker": {
        "slug": "worker",
        "model_name": "Phi-3.5-mini-instruct",
        "size_gb": 3,
        "role": "논리 일꾼",
        "instances": 4,  # up to 4 workers as needed
    },
    "coder": {
        "slug": "coder",
        "model_name": "Qwen2.5-Coder-7B-Instruct",
        "quant": "Q4_K_M",
        "size_gb": 5,
        "role": "코딩 일꾼",
        "instances": 2,
    },
    "reasoner": {
        "slug": "reasoner",
        "model_name": "DeepSeek-R1-Distill-Qwen-7B",
        "size_gb": 5,
        "role": "심화 추론가",
        "instances": 1,
    },
    "embedding": {
        "slug": "embedding",
        "model_name": "bge-small-en-v1.5",
        "size_gb": 0.5,
        "role": "임베딩 모델",
        "instances": 1,
    },
}
