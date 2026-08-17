#!/usr/bin/env bash
# 每日备份脚本：测试/正式两个 MySQL 库 + 两套 media 照片 + 配置文件，保留最近 14 份
# 用法：crontab -e 添加一行
#   0 3 * * * /opt/foodmap/app/deploy/backup.sh >> /opt/foodmap/logs/backup.log 2>&1
set -euo pipefail

APP_DIR="/opt/foodmap/app"
PROD_DIR="/opt/foodmap-prod"
BACKUP_DIR="/opt/foodmap/backups"
DATE=$(date +%Y%m%d_%H%M%S)
KEEP=14

# MySQL 连接参数与 config.ini 保持一致（此处从配置读取）
DB_HOST=$(grep -m1 '^db_host=' "$APP_DIR/config/config.ini" | cut -d= -f2)
DB_PORT=$(grep -m1 '^db_port=' "$APP_DIR/config/config.ini" | cut -d= -f2)
DB_USER=$(grep -m1 '^db_user=' "$APP_DIR/config/config.ini" | cut -d= -f2)
DB_PASSWORD=$(grep -m1 '^db_password=' "$APP_DIR/config/config.ini" | cut -d= -f2)

mkdir -p "$BACKUP_DIR"
TARGET="$BACKUP_DIR/backup_$DATE"
mkdir -p "$TARGET"

echo "[$(date '+%F %T')] 开始备份"

# 1. 数据库（测试库 + 正式库）
MYSQL_PWD="$DB_PASSWORD" mysqldump -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" \
    --single-transaction --no-tablespaces --default-character-set=utf8mb4 foodmap > "$TARGET/db_test.sql"
MYSQL_PWD="$DB_PASSWORD" mysqldump -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" \
    --single-transaction --no-tablespaces --default-character-set=utf8mb4 foodmap_prod > "$TARGET/db_prod.sql"

# 2. 用户上传的照片（两套环境；服务器未装 rsync，用 cp -a）
cp -a "$APP_DIR/media/." "$TARGET/media_test/"
cp -a "$PROD_DIR/media/." "$TARGET/media_prod/"

# 3. 密钥配置（含高德/DeepSeek Key，备份加密后另存，勿随仓库提交）
cp "$APP_DIR/config/config.ini" "$TARGET/config_test.ini"
cp "$PROD_DIR/config/config.ini" "$TARGET/config_prod.ini"

# 4. 打包并清理（只保留最近 KEEP 份）
tar -czf "$BACKUP_DIR/backup_$DATE.tar.gz" -C "$BACKUP_DIR" "backup_$DATE"
rm -rf "$TARGET"
ls -1t "$BACKUP_DIR"/backup_*.tar.gz | tail -n +$((KEEP + 1)) | xargs -r rm -f

echo "[$(date '+%F %T')] 备份完成：$BACKUP_DIR/backup_$DATE.tar.gz"
