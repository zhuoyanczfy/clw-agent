#!/usr/bin/env bash
# 美食足迹 · 服务器一键部署脚本（Ubuntu 22.04）
# 用法：以 root 执行前先修改下方配置，然后：
#   bash deploy.sh
# 注意：假设代码已放在 /opt/foodmap/app（git clone 或 rsync），config.ini 已配置好
set -euo pipefail

# ============ 修改为你的实际值 ============
DOMAIN="你的域名"                # 例如 foodmap.example.com（已解析到本机 IP）
APP_DIR="/opt/foodmap/app"
VENV_DIR="/opt/foodmap/venv"
APP_USER="foodmap"
DB_NAME="foodmap"
DB_USER="foodmap"
DB_PASSWORD="改成强密码"
# ==========================================

echo "==> 1/8 安装系统依赖"
apt-get update
apt-get install -y nginx python3-venv mysql-server certbot python3-certbot-nginx

echo "==> 2/8 创建运行用户与目录"
id -u "$APP_USER" &>/dev/null || useradd -m -s /bin/bash "$APP_USER"
mkdir -p /opt/foodmap/logs "$APP_DIR" "$VENV_DIR"
chown -R "$APP_USER":"$APP_USER" /opt/foodmap

echo "==> 3/8 创建 Python 虚拟环境并安装依赖"
sudo -u "$APP_USER" python3 -m venv "$VENV_DIR"
"$VENV_DIR/bin/pip" install -r "$APP_DIR/requirements.txt"

echo "==> 4/8 初始化 MySQL（建库建用户）"
mysql <<SQL
CREATE DATABASE IF NOT EXISTS $DB_NAME DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASSWORD';
GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';
FLUSH PRIVILEGES;
SQL

echo "==> 5/8 Django 迁移 + 静态文件"
cd "$APP_DIR"
sudo -u "$APP_USER" env PYTHONIOENCODING=utf-8 "$VENV_DIR/bin/python" manage.py migrate
sudo -u "$APP_USER" env PYTHONIOENCODING=utf-8 "$VENV_DIR/bin/python" manage.py collectstatic --noinput

echo "==> 6/8 安装 Gunicorn systemd 服务"
cp deploy/gunicorn.service /etc/systemd/system/foodmap.service
systemctl daemon-reload
systemctl enable --now foodmap

echo "==> 7/8 配置 Nginx"
sed "s/你的域名/$DOMAIN/g" "$APP_DIR/deploy/nginx.conf" > /etc/nginx/sites-available/foodmap.conf
ln -sf /etc/nginx/sites-available/foodmap.conf /etc/nginx/sites-enabled/foodmap.conf
rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl reload nginx

echo "==> 8/8 签发 HTTPS 证书（Let's Encrypt）"
certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos -m "admin@$DOMAIN" --redirect

echo ""
echo "部署完成！访问 https://$DOMAIN"
echo "后续操作："
echo "  1. 导入旧数据：本地 python manage.py dumpdata --exclude auth.permission --exclude contenttypes > data.json，"
echo "     上传到 $APP_DIR 后执行 $VENV_DIR/bin/python manage.py loaddata data.json（并把 media/ 目录同步过去）"
echo "  2. 创建管理员：$VENV_DIR/bin/python manage.py createsuperuser"
echo "  3. 高德控制台把本机公网 IP 加入 MAP_KEY 白名单"
