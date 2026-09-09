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
        "model_name": "Qwen2.5-7B-Instruct",
        "quant": "Q4_K_M",
        "size_gb": 5,
        "role": "논리 일꾼",
        "instances": 1,  # 병렬은 CPU(대역폭 결합)에서 무의미 → 대표 1개만
    },
    "coder": {
        "slug": "coder",
        "model_name": "Qwen2.5-Coder-7B-Instruct",
        "quant": "Q4_K_M",
        "size_gb": 5,
        "role": "코딩 일꾼",
        "instances": 1,  # 병렬은 CPU(대역폭 결합)에서 무의미 → 대표 1개만
    },
    "reasoner": {
        "slug": "reasoner",
        "model_name": "DeepSeek-R1-Distill-Qwen-7B",
        "size_gb": 5,
        "role": "심화 추론가",
        "instances": 1,
    },
    "setter": {
        "slug": "setter",
        "model_name": "Qwen2.5-14B-Instruct",
        "quant": "Q5_K_M",
        "size_gb": 11,
        "role": "문제 생성기",
        "instances": 1,
        "on_demand": True,  # 14B — 다른 모델 내리고 단독 로드 (PLAN 동시로딩 전략)
    },
    "judge": {
        "slug": "judge",
        "model_name": "DeepSeek-R1-Distill-Qwen-14B",
        "quant": "Q5_K_M",
        "size_gb": 11,
        "role": "판사",
        "instances": 1,
        "on_demand": True,  # 14B — GBNF 로 {ok,code} 초경량 출력, 단독 로드
    },
    "embedding": {
        "slug": "embedding",
        "model_name": "bge-small-en-v1.5",
        "size_gb": 0.5,
        "role": "임베딩 모델",
        "instances": 1,
    },
}
