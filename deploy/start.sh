#!/usr/bin/env bash
# mall-swarm 一键启动脚本
# 位置：/opt/mall-swarm/start.sh
# 用法：sudo /opt/mall-swarm/start.sh

set -euo pipefail

BASE=/opt/mall-swarm
DEPLOY="$BASE/deploy"
ENV_FILE="$BASE/.env"

log()  { printf '\n[%s] %s\n' "$(date '+%F %T')" "$*"; }
fail() { printf '\n[ERROR] %s\n' "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || fail "请使用 root 运行：sudo $0"
[[ -f "$ENV_FILE" ]] || fail "缺少 $ENV_FILE"
[[ -f "$DEPLOY/docker-compose.yml" ]] || fail "缺少 $DEPLOY/docker-compose.yml"

set -a
# shellcheck disable=SC1091
source "$ENV_FILE"
set +a

command -v docker >/dev/null 2>&1 || fail "未安装 Docker"
command -v curl   >/dev/null 2>&1 || fail "未安装 curl"
command -v envsubst >/dev/null 2>&1 || fail "未安装 envsubst（apt install gettext-base）"

wait_container() {
  local name=$1
  local retries=${2:-60}
  local status
  printf '等待容器 %-14s ' "$name"
  for ((i = 1; i <= retries; i++)); do
    status=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$name" 2>/dev/null || echo missing)
    if [[ "$status" == "healthy" || "$status" == "running" ]]; then
      echo " OK"
      return 0
    fi
    printf '.'
    sleep 2
  done
  echo " 超时"
  docker logs --tail 30 "$name" 2>&1 || true
  return 1
}

wait_http() {
  local name=$1
  local url=$2
  local retries=${3:-90}
  printf '等待服务 %-14s ' "$name"
  for ((i = 1; i <= retries; i++)); do
    if curl -fsS --max-time 2 "$url" >/dev/null 2>&1; then
      echo " OK"
      return 0
    fi
    printf '.'
    sleep 2
  done
  echo " 超时"
  systemctl status "$name" --no-pager -l | tail -30 || true
  journalctl -u "$name" -n 50 --no-pager || true
  return 1
}

log "启动 Docker"
systemctl start docker
systemctl is-active --quiet docker || fail "Docker 启动失败"

cd "$DEPLOY"
mkdir -p data logs rendered
mkdir -p data/minio
chown -R 100:101 data/minio
mkdir -p /home/mall/logs/nacos
chown -R mall:mall /home/mall "$BASE/logs"

log "渲染 Nacos 配置"
for f in nacos/*.yaml.tpl; do
  name=$(basename "$f" .tpl)
  envsubst < "$f" > "rendered/$name"
done

log "启动中间件"
docker compose --env-file "$ENV_FILE" up -d

log "等待中间件健康"
wait_container mall-mysql 90
wait_container mall-redis 60
wait_container mall-nacos 90
wait_container mall-rabbitmq 60
wait_container mall-mongo 60
wait_container mall-minio 60

log "检查 MySQL 数据库"
docker exec mall-mysql mysql -uroot -p"$MYSQL_ROOT_PASSWORD" \
  -e "CREATE DATABASE IF NOT EXISTS mall DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" \
  >/dev/null 2>&1

TABLE_COUNT=$(docker exec mall-mysql mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -N -s \
  -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='mall';" 2>/dev/null || echo 0)

if [[ "$TABLE_COUNT" == "0" ]]; then
  [[ -f "$BASE/sql/mall.sql" ]] || fail "mall 库为空，且缺少 $BASE/sql/mall.sql"
  log "导入 mall.sql"
  docker exec -i mall-mysql mysql -uroot -p"$MYSQL_ROOT_PASSWORD" mall < "$BASE/sql/mall.sql"
else
  log "mall 库已有 $TABLE_COUNT 张表，跳过 SQL 导入"
fi

log "配置 RabbitMQ 权限"
docker exec mall-rabbitmq rabbitmqctl set_permissions -p /mall mall ".*" ".*" ".*" >/dev/null 2>&1 || true

log "发布 Nacos 配置"
for f in rendered/*.yaml; do
  data_id=$(basename "$f")
  result=$(curl -fsS -X POST "http://127.0.0.1:8848/nacos/v1/cs/configs" \
    --data-urlencode "dataId=$data_id" \
    --data-urlencode "group=DEFAULT_GROUP" \
    --data-urlencode "type=yaml" \
    --data-urlencode "content@$f")
  [[ "$result" == "true" ]] || fail "Nacos 配置发布失败：$data_id"
  echo "  $data_id -> $result"
done

log "启动 Java 服务（逐个启动，避免小内存机器启动峰值过高）"
start_service() {
  local unit=$1
  local port=$2
  echo "  -> $unit"
  systemctl reset-failed "$unit" 2>/dev/null || true
  systemctl start "$unit"
  wait_http "$unit" "http://127.0.0.1:${port}/actuator/health" 90
}

start_service mall-admin 8080
start_service mall-portal 8085
start_service mall-auth 8401
start_service mall-gateway 8201

log "启动 Nginx"
if command -v nginx >/dev/null 2>&1; then
  if [[ ! -f /etc/nginx/sites-available/mall.conf ]]; then
    cp nginx/mall.conf /etc/nginx/sites-available/mall.conf
    ln -sf /etc/nginx/sites-available/mall.conf /etc/nginx/sites-enabled/mall.conf
    rm -f /etc/nginx/sites-enabled/default
  fi
  nginx -t
  systemctl enable nginx >/dev/null 2>&1 || true
  systemctl restart nginx
else
  echo "  [WARN] 未安装 nginx，跳过前端代理启动"
fi

log "启动完成"
echo "管理端：http://100.125.54.127/"
echo "移动端：http://100.125.54.127/app/"
echo "统一认证：http://100.125.54.127/mall-auth/auth/login"
echo
systemctl --no-pager --lines=0 status mall-admin mall-portal mall-auth mall-gateway nginx | grep -E '●|Active:' || true
docker ps --format 'table {{.Names}}\t{{.Status}}'
