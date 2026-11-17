#!/usr/bin/env bash
# mall-swarm 服务器端部署脚本
# 适用：Debian 13 + Docker + Java 21 + Nginx
# 运行前请确认 /opt/mall-swarm/.env、JAR、SQL、前端 dist 已上传。

set -euo pipefail

BASE=/opt/mall-swarm
DEPLOY="$BASE/deploy"

if [[ ! -f "$BASE/.env" ]]; then
  echo "缺少 $BASE/.env，请先从 deploy/.env.example 复制并修改"
  exit 1
fi

set -a
# shellcheck disable=SC1091
source "$BASE/.env"
set +a

cd "$DEPLOY"
mkdir -p data logs rendered
# MinIO 镜像以 uid=100/gid=101 运行，提前创建数据目录并授权
mkdir -p data/minio
chown -R 100:101 data/minio
# Nacos 客户端默认把日志写到 ${user.home}/logs/nacos
mkdir -p /home/mall/logs/nacos
chown -R mall:mall /home/mall /opt/mall-swarm/logs

echo "==> 渲染 Nacos 配置模板"
for f in nacos/*.yaml.tpl; do
  name=$(basename "$f" .tpl)
  envsubst < "$f" > "rendered/$name"
done

echo "==> 启动中间件"
docker compose --env-file "$BASE/.env" up -d

wait_for() {
  local name=$1
  local cmd=$2
  local retries=${3:-60}
  echo -n "等待 $name "
  for ((i = 1; i <= retries; i++)); do
    if eval "$cmd" >/dev/null 2>&1; then
      echo " OK"
      return 0
    fi
    echo -n "."
    sleep 3
  done
  echo " 超时"
  return 1
}

wait_for "MySQL" "docker exec mall-mysql mysqladmin ping -h127.0.0.1 -uroot -p\"$MYSQL_ROOT_PASSWORD\" --silent" 80
wait_for "Nacos" "curl -fsS http://127.0.0.1:8848/nacos/v1/console/health/readiness" 80
wait_for "RabbitMQ" "docker exec mall-rabbitmq rabbitmq-diagnostics -q ping" 60
wait_for "MongoDB" "docker exec mall-mongo mongosh --quiet --eval \"db.adminCommand('ping').ok\"" 60

echo "==> 初始化 MySQL 数据库和表"
docker exec mall-mysql mysql -uroot -p"$MYSQL_ROOT_PASSWORD" \
  -e "CREATE DATABASE IF NOT EXISTS mall DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"

TABLE_COUNT=$(docker exec mall-mysql mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -N -s \
  -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='mall';")
if [[ "$TABLE_COUNT" == "0" ]]; then
  echo "导入 mall.sql"
  docker exec -i mall-mysql mysql -uroot -p"$MYSQL_ROOT_PASSWORD" mall < "$BASE/sql/mall.sql"
else
  echo "mall 库已有 $TABLE_COUNT 张表，跳过 SQL 导入"
fi

echo "==> 配置 RabbitMQ 权限"
docker exec mall-rabbitmq rabbitmqctl set_permissions -p /mall mall ".*" ".*" ".*" || true

echo "==> 发布 Nacos 配置"
for f in rendered/*.yaml; do
  data_id=$(basename "$f")
  result=$(curl -fsS -X POST "http://127.0.0.1:8848/nacos/v1/cs/configs" \
    --data-urlencode "dataId=$data_id" \
    --data-urlencode "group=DEFAULT_GROUP" \
    --data-urlencode "type=yaml" \
    --data-urlencode "content@$f")
  echo "  $data_id -> $result"
  [[ "$result" == "true" ]] || { echo "Nacos 配置发布失败：$data_id"; exit 1; }
done

echo "==> 安装 systemd 服务"
cp -f systemd/*.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable mall-admin mall-portal mall-auth mall-gateway

# 逐个启动，避免 7.3G 内存机器启动瞬间 CPU/内存峰值过高
systemctl restart mall-admin
wait_for "mall-admin" "curl -fsS http://127.0.0.1:8080/actuator/health" 60
systemctl restart mall-portal
wait_for "mall-portal" "curl -fsS http://127.0.0.1:8085/actuator/health" 60
systemctl restart mall-auth
wait_for "mall-auth" "curl -fsS http://127.0.0.1:8401/actuator/health" 60
systemctl restart mall-gateway
wait_for "mall-gateway" "curl -fsS http://127.0.0.1:8201/actuator/health" 60

echo "==> 配置 Nginx"
if command -v nginx >/dev/null 2>&1; then
  cp -f nginx/mall.conf /etc/nginx/sites-available/mall.conf
  ln -sf /etc/nginx/sites-available/mall.conf /etc/nginx/sites-enabled/mall.conf
  rm -f /etc/nginx/sites-enabled/default
  nginx -t
  systemctl enable nginx >/dev/null 2>&1 || true
  systemctl reload nginx
fi

echo "==> 部署完成"
echo "管理端：http://100.125.54.127/"
echo "移动端：http://100.125.54.127/app/"
echo "统一登录：http://100.125.54.127/mall-auth/auth/login"
