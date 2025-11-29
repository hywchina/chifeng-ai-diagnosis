#!/bin/bash

echo "============== LM Studio 自动检测脚本 v9 (macOS M Series) =============="

###############################################
# 配置默认模型（严格匹配）
###############################################
DEFAULT_LLM="openai/gpt-oss-120b (1 variant)"
DEFAULT_EMB="text-embedding-bge-m3"

###############################################
# 可选加载参数（可通过环境变量覆盖）
# 例如：
#   DEFAULT_GPU=1.0 DEFAULT_CONTEXT_LENGTH=8192 ./utils/check_lmstudio.sh
###############################################
DEFAULT_GPU=${DEFAULT_GPU:-1.0}
DEFAULT_CONTEXT_LENGTH=${DEFAULT_CONTEXT_LENGTH:-}

###############################################
# 1. 检查 Server 状态
###############################################
echo "▶ 检查 LM Studio Server..."
SERVER_STATUS=$(lms server status 2>&1)
if [[ "$SERVER_STATUS" =~ "not running" ]]; then
    echo "⚠️ Server 未运行 → 自动启动..."
    lms server start
    sleep 2
else
    echo "✅ Server 已运行"
fi

###############################################
# 2. 获取当前已加载模型状态
###############################################
echo ""
echo "🧠 检查当前已加载模型..."
PS_OUTPUT=$(lms ps)

# 初始化
LOADED_LLM=()
LOADED_EMB=()

# 从 lms ls 输出中提取 LLM/EMBEDDING 分区文本
LS_OUTPUT=$(lms ls)
LLM_SECTION=$(echo "$LS_OUTPUT" | awk '/^LLM/{flag=1;next}/^EMBEDDING/{flag=0}flag')
EMB_SECTION=$(echo "$LS_OUTPUT" | awk '/^EMBEDDING/{flag=1;next}flag')

# 判断某模型是否在指定分区（严格整行匹配前缀：模型名行以模型名为起始）
is_in_section() {
    local NAME="$1"
    local SECTION_TEXT="$2"
    echo "$SECTION_TEXT" | sed -E 's/[[:space:]]{2,}.*$//' | grep -Fxq "$NAME"
}

# 解析 lms ps：跳过表头，第二列为模型名；视为 LOADED
while read -r line; do
    # 跳过空行
    [[ -z "$line" ]] && continue
    # 跳过表头
    if [[ "$line" =~ ^IDENTIFIER[[:space:]]+MODEL[[:space:]]+STATUS ]]; then
        continue
    fi
    # 取第二列模型名（列以至少两个空格分隔）
    MODEL_NAME=$(echo "$line" | awk '{print $2}')
    [[ -z "$MODEL_NAME" ]] && continue
    STATUS="LOADED"
    if is_in_section "$MODEL_NAME" "$LLM_SECTION"; then
        LOADED_LLM+=("$MODEL_NAME:$STATUS")
    elif is_in_section "$MODEL_NAME" "$EMB_SECTION"; then
        LOADED_EMB+=("$MODEL_NAME:$STATUS")
    else
        # 未能归类的已加载模型，忽略或作为 LLM 显示
        LOADED_LLM+=("$MODEL_NAME:$STATUS")
    fi
done <<< "$PS_OUTPUT"

# 显示已加载模型
echo "📌 已加载 LLM："
if [[ ${#LOADED_LLM[@]} -eq 0 ]]; then
    echo "  - 无"
else
    for m in "${LOADED_LLM[@]}"; do echo "  - $m"; done
fi

echo "📌 已加载 Embedding："
if [[ ${#LOADED_EMB[@]} -eq 0 ]]; then
    echo "  - 无"
else
    for m in "${LOADED_EMB[@]}"; do echo "  - $m"; done
fi

###############################################
# 3. 列出本地模型
###############################################
LS_OUTPUT=$(lms ls)

# 辅助函数：检查模型是否存在本地
model_exists() {
    local MODEL="$1"
    # 严格匹配模型名（去除列信息，仅保留行首模型名）
    echo "$LS_OUTPUT" | sed -E 's/[[:space:]]{2,}.*$//' | grep -Fxq "$MODEL"
}

# 辅助函数：将展示名转换为 lms load 可接受的路径（去除展示用的 " (1 variant)" 后缀）
to_load_name() {
    local DISPLAY_NAME="$1"
    echo "$DISPLAY_NAME" | sed -E 's/[[:space:]]\(1 variant\)$//'
}

# 辅助函数：检查模型是否已加载
model_loaded() {
    local MODEL="$1"
    local ARR=("${!2}")
    for item in "${ARR[@]}"; do
        NAME=$(echo "$item" | cut -d: -f1)
        STATUS=$(echo "$item" | cut -d: -f2)
        if [[ "$NAME" == "$MODEL" ]] && [[ "$STATUS" == "LOADED" ]]; then
            return 0
        fi
    done
    return 1
}

###############################################
# 4. 加载默认 LLM（严格匹配）
###############################################
echo ""
echo "🔧 检查默认 LLM: $DEFAULT_LLM"
if model_loaded "$DEFAULT_LLM" LOADED_LLM[@]; then
    echo "✅ 默认 LLM 已加载，跳过"
else
    # 若已有其他 LLM 处于已加载状态，则避免切换，给予提示
    if [[ ${#LOADED_LLM[@]} -gt 0 ]]; then
        CURRENT_LLM_NAME=$(echo "${LOADED_LLM[0]}" | cut -d: -f1)
        if [[ "$CURRENT_LLM_NAME" != "$DEFAULT_LLM" ]]; then
            echo "⚠️ 已有其他 LLM 处于已加载状态：$CURRENT_LLM_NAME → 跳过自动切换"
            echo "👉 如需切换，请先执行: lms unload --all，然后加载: lms load \"$(to_load_name "$DEFAULT_LLM")\" --gpu=$DEFAULT_GPU ${DEFAULT_CONTEXT_LENGTH:+--context-length=$DEFAULT_CONTEXT_LENGTH} --identifier=default-llm"
            echo "ℹ️ 保持严格匹配：默认 LLM 显示名需与 \`lms ls\` 行首一致"
            # 跳过加载，避免交互式选择
        else
            echo "➡ 加载默认 LLM: $DEFAULT_LLM (gpu=$DEFAULT_GPU ${DEFAULT_CONTEXT_LENGTH:+context-length=$DEFAULT_CONTEXT_LENGTH})"
            lms load "$(to_load_name "$DEFAULT_LLM")" --gpu="$DEFAULT_GPU" ${DEFAULT_CONTEXT_LENGTH:+--context-length="$DEFAULT_CONTEXT_LENGTH"} --identifier="default-llm"
        fi
    elif model_exists "$DEFAULT_LLM"; then
        echo "➡ 加载默认 LLM: $DEFAULT_LLM (gpu=$DEFAULT_GPU ${DEFAULT_CONTEXT_LENGTH:+context-length=$DEFAULT_CONTEXT_LENGTH})"
        lms load "$(to_load_name "$DEFAULT_LLM")" --gpu="$DEFAULT_GPU" ${DEFAULT_CONTEXT_LENGTH:+--context-length="$DEFAULT_CONTEXT_LENGTH"} --identifier="default-llm"
    else
        echo "⚠️ 默认 LLM 不存在本地，请先下载或导入: $DEFAULT_LLM"
    fi
fi

###############################################
# 5. 加载默认 Embedding（严格匹配）
###############################################
echo ""
echo "🔧 检查默认 Embedding: $DEFAULT_EMB"
if model_loaded "$DEFAULT_EMB" LOADED_EMB[@]; then
    echo "✅ 默认 Embedding 已加载，跳过"
else
    # 若已有其他 Embedding 处于已加载状态，则避免切换，给予提示
    if [[ ${#LOADED_EMB[@]} -gt 0 ]]; then
        CURRENT_EMB_NAME=$(echo "${LOADED_EMB[0]}" | cut -d: -f1)
        if [[ "$CURRENT_EMB_NAME" != "$DEFAULT_EMB" ]]; then
            echo "⚠️ 已有其他 Embedding 处于已加载状态：$CURRENT_EMB_NAME → 跳过自动切换"
            echo "👉 如需切换，请先执行: lms unload --all，然后加载: lms load \"$(to_load_name "$DEFAULT_EMB")\" --gpu=$DEFAULT_GPU ${DEFAULT_CONTEXT_LENGTH:+--context-length=$DEFAULT_CONTEXT_LENGTH} --identifier=default-emb"
            echo "ℹ️ 保持严格匹配：默认 Embedding 显示名需与 \`lms ls\` 行首一致"
            # 跳过加载，避免交互式选择
        else
            echo "➡ 加载默认 Embedding: $DEFAULT_EMB (gpu=$DEFAULT_GPU ${DEFAULT_CONTEXT_LENGTH:+context-length=$DEFAULT_CONTEXT_LENGTH})"
            lms load "$(to_load_name "$DEFAULT_EMB")" --gpu="$DEFAULT_GPU" ${DEFAULT_CONTEXT_LENGTH:+--context-length="$DEFAULT_CONTEXT_LENGTH"} --identifier="default-emb"
        fi
    elif model_exists "$DEFAULT_EMB"; then
        echo "➡ 加载默认 Embedding: $DEFAULT_EMB (gpu=$DEFAULT_GPU ${DEFAULT_CONTEXT_LENGTH:+context-length=$DEFAULT_CONTEXT_LENGTH})"
        lms load "$(to_load_name "$DEFAULT_EMB")" --gpu="$DEFAULT_GPU" ${DEFAULT_CONTEXT_LENGTH:+--context-length="$DEFAULT_CONTEXT_LENGTH"} --identifier="default-emb"
    else
        echo "⚠️ 默认 Embedding 不存在本地，请先下载或导入: $DEFAULT_EMB"
    fi
fi

###############################################
# 6. 显示本地模型列表
###############################################
echo ""
echo "📦 本地模型列表："
lms ls

echo ""
echo "======================================================================="
