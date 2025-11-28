#!/bin/bash

# 定义源数据文件夹和备份文件夹
SOURCE_DIR="/Users/ai_diagnosis/projects/chifeng-ai-diagnosis/service_data"
BACKUP_DIR="/Users/ai_diagnosis/projects/chifeng-ai-diagnosis/service_data/.backups"

# 创建备份文件夹（如果不存在）
mkdir -p "$BACKUP_DIR"

# 获取当前日期
CURRENT_DATE=$(date +"%Y-%m-%d")

# 创建备份
BACKUP_FILE="$BACKUP_DIR/backup_$CURRENT_DATE.tar.gz"
tar -czf "$BACKUP_FILE" -C "$SOURCE_DIR" .

# 删除超过180天的备份
find "$BACKUP_DIR" -type f -name "backup_*.tar.gz" -mtime +180 -exec rm {} \;

echo "备份完成：$BACKUP_FILE"


# # test
# crontab -e
# 0 2 * * * /bin/bash /Users/ai_diagnosis/projects/chifeng-ai-diagnosis/backup_service_data.sh