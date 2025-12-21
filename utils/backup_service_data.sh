#!/bin/bash

# 定义源数据文件夹和备份文件夹
SOURCE_DIR="/Users/ai_diagnosis/projects/chifeng-ai-diagnosis/service_data/ktem_app_data/"
BACKUP_DIR="/Users/ai_diagnosis/projects/chifeng-ai-diagnosis/.backups"
MAX_BACKUPS=180

# 创建备份文件夹（如果不存在）
mkdir -p "$BACKUP_DIR"

# 获取当前时间戳（精确到秒，避免同日多次备份重名）
CURRENT_TS=$(date +"%Y-%m-%d_%H-%M-%S")

BACKUP_FILE="$BACKUP_DIR/backup_$CURRENT_TS.tar.gz"
tar -czf "$BACKUP_FILE" -C "$SOURCE_DIR" .

# 保留最近 MAX_BACKUPS 份，删除更旧的备份
# 先按时间倒序（最新→最旧）列出所有备份文件
mapfile -t __ALL_BACKUPS < <(ls -1t "$BACKUP_DIR"/backup_*.tar.gz 2>/dev/null)
__COUNT=${#__ALL_BACKUPS[@]}
if [ "$__COUNT" -gt "$MAX_BACKUPS" ]; then
	__TO_DELETE_COUNT=$(( __COUNT - MAX_BACKUPS ))
	# 需要删除的为超出部分（数组从 MAX_BACKUPS 开始的是较旧的文件）
	__TO_DELETE=("${__ALL_BACKUPS[@]:$MAX_BACKUPS}")
	echo "备份数量 $__COUNT 超过上限 $MAX_BACKUPS，删除较旧的 $__TO_DELETE_COUNT 份备份。"
	rm -f "${__TO_DELETE[@]}"
fi

echo "备份完成：$BACKUP_FILE"