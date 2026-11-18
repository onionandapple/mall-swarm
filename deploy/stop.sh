#!/usr/bin/env bash
# mall-swarm 一键停止脚本
# 位置：/opt/mall-swarm/stop.sh
# 用法：
#   sudo /opt/mall-swarm/stop.sh              # 停止 Java 服务 + 中间件 + Nginx
#   sudo /opt/mall-swarm/stop.sh --apps-only  # 只停止 Java 服务，保留中间件和 Nginx

set -euo pipefail

BASE=/opt/mall-swarm
DEPLOY="$BASE/deploy"
ENV_FILE="$BASE/.env"
APPS_ONLY=false

if [[ "${1:-}" == "--apps-only" ]]; then
  APPS_ONLY=true
elif [[ -n "${1:-}" ]]; then
  echo "用法：$0 [--apps-only]" >&2
  exit 1
fi

log()  { printf '\n[%s] %s\n' "$(date '+%F %T')" "$*"; }
fail() { printf '\n[ERROR] %s\n' "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || fail "请使用 root 运行：sudo $0"
[[ -f "$ENV_FILE" ]] || fail "缺少 $ENV_FILE"

log "停止 Java 服务（按依赖倒序）"
# 先停网关，再停认证/业务服务，最后停 admin
for unit in mall-gateway mall-auth mall-portal mall-admin; do
  echo "  -> $unit"
  systemctl stop "$unit" 2>/dev/null || true
  # Java 进程收到 SIGTERM 后可能以非 0 退出，清理 failed 状态，避免下次启动被误判
  systemctl reset-failed "$unit" 2>/dev/null || true
done

if $APPS_ONLY; then
  log "已停止 Java 服务（中间件和 Nginx 保持不变）"
  systemctl --no-pager --lines=0 status mall-admin mall-portal mall-auth mall-gateway | grep -E '●|Active:' || true
  exit 0
fi

log "停止 Nginx"
systemctl stop nginx 2>/dev/null || true

log "停止 Docker 中间件"
if ! docker info >/dev/null 2>&1; then
  echo "  [WARN] Docker 未运行，跳过中间件停止"
elif [[ -f "$DEPLOY/docker-compose.yml" ]]; then
  cd "$DEPLOY"
  docker compose --env-file "$ENV_FILE" stop
else
  echo "  [WARN] 缺少 $DEPLOY/docker-compose.yml，跳过中间件停止"
fi

log "停止完成"
echo
systemctl --no-pager --lines=0 status mall-admin mall-portal mall-auth mall-gateway nginx | grep -E '●|Active:' || true
docker ps -a --format 'table {{.Names}}\t{{.Status}}' 2>/dev/null || true
