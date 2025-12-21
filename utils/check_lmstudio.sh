#!/bin/bash

# 为 launchctl 环境补全 PATH，确保能找到 lms 可执行文件
export PATH="/Users/ai_diagnosis/.lmstudio/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

# 诊断输出：记录 PATH 与 lms 位置，帮助定位环境问题
echo "当前 PATH=$PATH"
if command -v lms >/dev/null 2>&1; then
    echo "已找到 lms: $(command -v lms)"
else
    echo "PATH 中未找到 LM Studio CLI (lms)"
fi
MODEL_1_ID="openai/gpt-oss-20b"
MODEL_1_IDENTIFIER="openai/gpt-oss-20b"
MODEL_1_CONTEXT=64000

MODEL_2_ID="lm-kit/bge-m3-gguf/bge-m3-Q8_0.gguf"
MODEL_2_IDENTIFIER="text-embedding-bge-m3"
MODEL_2_CONTEXT=8192

# 1. 启动服务（如果没运行）
if ! lms status >/dev/null 2>&1; then
    echo "启动 LM Studio 服务..."
    lms server start >/dev/null 2>&1
    echo "等待服务初始化..."
    sleep 10    # ← ★ 关键：等待服务完全就绪
fi

# 2. 获取已加载模型
LOADED_MODELS=$(lms ps 2>/dev/null)
# 3. 校验并加载模型，若 context 与期望不符则卸载后按设定重新加载
get_loaded_context() {
    # 从 lms ps 的表格输出中提取指定 identifier 的 context 列（倒序寻找数字）
    local ident="$1"
    echo "$LOADED_MODELS" | awk -v id="$ident" '
        NR >= 3 && $1 == id {
            for (i = NF; i >= 1; i--) {
                if ($i ~ /^[0-9]+$/) { print $i; break }
            }
        }
    '
}

ensure_model() {
    local model_id="$1" ident="$2" desired_ctx="$3"
    local current_ctx action_taken=""

    current_ctx=$(get_loaded_context "$ident")

    if [ -n "$current_ctx" ] && [ "$current_ctx" != "$desired_ctx" ]; then
        echo "模型 $ident 的上下文不一致 (当前=$current_ctx, 期望=$desired_ctx)，重新加载..."
        lms unload "$ident" >/dev/null 2>&1 || true
        action_taken="yes"
        current_ctx=""
    fi

    if [ -z "$current_ctx" ]; then
        echo "加载模型 $ident (id=$model_id, ctx=$desired_ctx)..."
        lms load "$model_id" \
            --context-length "$desired_ctx" \
            --identifier "$ident" \
            -y
        action_taken="yes"
    else
        echo "模型 $ident 已加载，context=$current_ctx"
    fi

    # 若有变更，刷新 LOADED_MODELS，供后续模型判断使用
    if [ -n "$action_taken" ]; then
        LOADED_MODELS=$(lms ps 2>/dev/null)
    fi
}

ensure_model "$MODEL_1_ID" "$MODEL_1_IDENTIFIER" "$MODEL_1_CONTEXT"
ensure_model "$MODEL_2_ID" "$MODEL_2_IDENTIFIER" "$MODEL_2_CONTEXT"
