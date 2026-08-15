#!/usr/bin/env bash
# 美食足迹 · 菜库增量同步脚本（本地改完菜库后，一键同步到云端服务器）
# 用法：在本地执行（需先配置好 SSH 免密登录或输入密码）：
#   bash backend/deploy/sync_dishes.sh
# 作用：
#   1. 上传最新的 dishes_full.py 和 media/dishes/ 图片目录到服务器
#   2. 在服务器上执行 seed_dishes 更新数据库
#   3. 重启 Gunicorn 使改动生效
set -euo pipefail

# ============ 修改为你的服务器实际值 ============
SERVER_USER="root"                          # SSH 登录用户
SERVER_HOST="139.196.27.224"                # 服务器 IP 或域名
SERVER_APP_DIR="/opt/foodmap/app"           # 服务器上项目路径
SERVER_VENV="/opt/foodmap/venv"             # 服务器虚拟环境路径
# ================================================

LOCAL_BACKEND="backend"
LOCAL_DISHES_DATA="$LOCAL_BACKEND/foodmap/dishes_full.py"
LOCAL_DISHES_IMAGES="$LOCAL_BACKEND/media/dishes/"

echo "==> 1/4 上传菜库数据 dishes_full.py"
scp "$LOCAL_DISHES_DATA" "$SERVER_USER@$SERVER_HOST:$SERVER_APP_DIR/foodmap/dishes_full.py"

echo "==> 2/4 上传菜品图片 media/dishes/"
# 先确保服务器目录存在，再递归上传（保留本地结构）
ssh "$SERVER_USER@$SERVER_HOST" "mkdir -p $SERVER_APP_DIR/media/dishes"
scp -r "$LOCAL_DISHES_IMAGES"* "$SERVER_USER@$SERVER_HOST:$SERVER_APP_DIR/media/dishes/"

echo "==> 3/4 服务器上执行 seed_dishes 更新数据库"
ssh "$SERVER_USER@$SERVER_HOST" "cd $SERVER_APP_DIR && $SERVER_VENV/bin/python manage.py seed_dishes"

echo "==> 4/4 重启 Gunicorn 使改动生效"
ssh "$SERVER_USER@$SERVER_HOST" "systemctl restart foodmap"

echo ""
echo "同步完成！云端菜库已更新（75 道本地图版本）。"
echo "验证：curl -H 'X-Api-Token: clw-api-8f3k2j9h4g5d6s7a' https://你的域名/api/dish/today/"
