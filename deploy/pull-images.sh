#!/usr/bin/env bash
# 从国内镜像源拉取 mall-swarm 所需镜像，并打回官方标签。
# 说明：Docker Hub 在部分服务器上无法直连，所以显式使用镜像源。
set -euo pipefail

M=docker.1ms.run

pull() {
  local src="$1"
  local dst="$2"
  echo "==> $src"
  docker pull "$M/$src"
  docker tag "$M/$src" "$dst"
}

pull library/redis:7-alpine redis:7-alpine
pull library/mysql:8.0 mysql:8.0
pull library/rabbitmq:3.13-management rabbitmq:3.13-management
pull library/mongo:6 mongo:6
pull nacos/nacos-server:v2.5.1 nacos/nacos-server:v2.5.1
# minio/minio:latest 在部分镜像源上不可用，使用 alpine/minio 的同步版本
pull alpine/minio:latest-release minio/minio:latest

echo "全部镜像准备完成"
