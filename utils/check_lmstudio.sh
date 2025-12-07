#!/bin/bash

MODEL_1_ID="openai/gpt-oss-20b"
MODEL_1_IDENTIFIER="openai/gpt-oss-20b"
MODEL_1_CONTEXT=64000

MODEL_2_ID="lm-kit/bge-m3-gguf/bge-m3-Q8_0.gguf"
MODEL_2_IDENTIFIER="text-embedding-bge-m3"
MODEL_2_CONTEXT=8192

# 1. 启动服务（如果没运行）
if ! lms status >/dev/null 2>&1; then
    echo "Starting LM Studio server..."
    lms server start >/dev/null 2>&1
    echo "Waiting for server to initialize..."
    sleep 10    # ← ★ 关键：等待服务完全就绪
fi

# 2. 获取已加载模型
LOADED_MODELS=$(lms ps 2>/dev/null)

# 3. 加载模型 1
if ! echo "$LOADED_MODELS" | grep -q "$MODEL_1_IDENTIFIER"; then
    echo "Loading model $MODEL_1_IDENTIFIER..."
    lms load "$MODEL_1_ID" \
        --context-length "$MODEL_1_CONTEXT" \
        --identifier "$MODEL_1_IDENTIFIER" \
        -y
fi

# 4. 加载模型 2
if ! echo "$LOADED_MODELS" | grep -q "$MODEL_2_IDENTIFIER"; then
    echo "Loading model $MODEL_2_IDENTIFIER..."
    lms load "$MODEL_2_ID" \
        --context-length "$MODEL_2_CONTEXT" \
        --identifier "$MODEL_2_IDENTIFIER" \
        -y
fi
