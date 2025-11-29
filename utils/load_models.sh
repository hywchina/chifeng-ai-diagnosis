#!/bin/bash

# ==============================
# 配置
# ==============================
LOG_DIR="/Users/ai_diagnosis/projects/chifeng-ai-diagnosis/service_data/cron_logs"
mkdir -p "$LOG_DIR"  # 如果目录不存在则创建

# 每天一个日志文件
LOG_FILE="$LOG_DIR/load_models-$(date +%F).log"

# 保留最近 N 天日志
KEEP_DAYS=30

# 将 stdout 和 stderr 重定向到日志文件
exec >> "$LOG_FILE" 2>&1

echo "===================="
echo "脚本执行时间: $(date)"
echo "===================="

# ==============================
# 自动清理旧日志
# ==============================
find "$LOG_DIR" -type f -name "load_models-*.log" -mtime +$KEEP_DAYS -exec rm -f {} \;

# ==============================
# 模型 JSON（超参数）
# ==============================
LLM_MODELS='[
  {
    "path": "openai/gpt-oss-20",
    "context_length": 128000,
    "identifier": "openai/gpt-oss-20b"
  },
  {
    "path": "openai/gpt-oss-120",
    "context_length": 128000,
    "identifier": "openai/gpt-oss-120b"
  }
]'

EMBEDDING_MODELS='[
  {
    "path": "lm-kit/bge-m3-gguf/bge-m3-Q8_0.gguf",
    "context_length": 8192,
    "identifier": "text-embedding-bge-m3"
  },
  {
    "path": "CompendiumLabs/bge-large-zh-v1.5-gguf/bge-large-zh-v1.5-q8_0.gguf",
    "context_length": 8192,
    "identifier": "text-embedding-bge-large-zh"
  }
]'

# ==============================
# 检查模型是否已加载
# ==============================
is_loaded() {
    local id="$1"
    if lms ps | grep -q "$id"; then
        return 0  # 已加载
    else
        return 1  # 未加载
    fi
}

# ==============================
# 遍历 JSON 加载模型
# ==============================
load_models_from_json() {
    local json_data="$1"
    echo "$json_data" | jq -c '.[]' | while read -r model; do
        path=$(echo "$model" | jq -r '.path')
        context_length=$(echo "$model" | jq -r '.context_length')
        identifier=$(echo "$model" | jq -r '.identifier')

        if is_loaded "$identifier"; then
            echo "模型 $identifier 已经加载，跳过..."
        else
            echo "加载模型 $identifier ..."
            lms load "$path" \
                --context-length "$context_length" \
                --identifier "$identifier" \
                -y
        fi
    done
}

# ==============================
# 主程序
# ==============================
echo "=== 加载 LLM 模型 ==="
load_models_from_json "$LLM_MODELS"

echo "=== 加载 Embedding 模型 ==="
load_models_from_json "$EMBEDDING_MODELS"

echo "完成！"
