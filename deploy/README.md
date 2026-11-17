# mall-swarm 单机部署文档

> 部署时间：2026-11-17
> 服务器：`100.125.54.127`（Tailscale）
> 后端仓库：`https://github.com/onionandapple/mall-swarm`
> 管理端：`https://github.com/onionandapple/mall-admin-web`
> 移动端：`https://github.com/onionandapple/mall-app-web`

---

## 一、部署结果概览

### 1. 访问地址

| 入口 | 地址 | 说明 |
|---|---|---|
| 管理端 | `http://100.125.54.127/` | Vue3 + Element Plus 后台 |
| 移动端 H5 | `http://100.125.54.127/app/` | uni-app 构建的 H5 商城 |
| 统一认证 | `http://100.125.54.127/mall-auth/auth/login` | `mall-auth` 统一登录入口 |
| 网关 API | `http://100.125.54.127/mall-admin/`、`/mall-portal/` | 由 Nginx 反向代理到网关 |
| 图片直链 | `http://100.125.54.127:9000/mall/...` | MinIO，仅 Tailscale 可访问 |
| 网关健康检查 | `http://100.125.54.127/health` | 代理到网关 `/actuator/health` |

> 服务器目前只通过 Tailscale 暴露 80/443，建议继续使用 Tailscale 访问，不要直接把中间件端口暴露到公网。

### 2. 默认账号

| 系统 | 账号 | 密码 | 说明 |
|---|---|---|---|
| 管理端 | `admin` | `macro123` | SQL 内置管理员 |
| 管理端 | `macro` | `macro123` | SQL 内置管理员 |
| 移动端 | `test` | `123456` | SQL 内置会员 |

> 首次登录后请立即修改密码。数据库、Redis、RabbitMQ、MinIO 的密码在服务器 `/opt/mall-swarm/.env` 中，文件权限 `600`，不要提交到 Git。

### 3. 服务与端口

| 组件 | 端口 | 监听地址 | 说明 |
|---|---:|---|---|
| Nginx | 80 / 443 | `0.0.0.0` | 前端静态资源 + API 反向代理 |
| `mall-gateway` | 8201 | `127.0.0.1` | Spring Cloud Gateway |
| `mall-admin` | 8080 | `127.0.0.1` | 后台管理服务 |
| `mall-portal` | 8085 | `127.0.0.1` | 前台商城服务 |
| `mall-auth` | 8401 | `127.0.0.1` | 统一登录门面 |
| MySQL | 3306 | `127.0.0.1` | 数据库 `mall` |
| Redis | 6379 | `127.0.0.1` | 缓存 / Sa-Token 会话 |
| Nacos | 8848、9848、9849 | `127.0.0.1` | 注册中心 + 配置中心 |
| RabbitMQ | 5672、15672 | `127.0.0.1` | 消息队列 / 管理台 |
| MongoDB | 27017 | `127.0.0.1` | `mall-portal` 使用 |
| MinIO | 9000、9001 | `100.125.54.127` / `127.0.0.1` | 9000 图片直链，9001 控制台 |

---

## 二、服务器环境

| 项目 | 实际配置 |
|---|---|
| 系统 | Debian GNU/Linux 13 (trixie) |
| CPU | Intel i3-7020U，2 核 4 线程 |
| 内存 | 7.3 GiB |
| Swap | 7.5 GiB |
| 磁盘 | 238 GB SSD，根分区 227 GB |
| Java | OpenJDK 21.0.13（项目编译目标为 Java 17，可运行在 21） |
| Docker | 26.1.5 |
| Docker Compose | 2.26.1 |
| Nginx | 1.26.3 |
| Nacos | 2.5.1 单机模式 |
| MySQL | 8.0 |
| Redis | 7 |
| RabbitMQ | 3.13-management |
| MongoDB | 6 |
| MinIO | `alpine/minio:latest-release` |

### 网络与防火墙

- 通过 Tailscale 访问：`100.125.54.127`
- 局域网地址：`192.168.1.115` / `192.168.1.118`
- 公网只检测到 IPv6，没有公网 IPv4
- UFW 只放行：
  - `22/tcp`
  - `80/tcp`
  - `443/tcp`
  - `41641/udp`（Tailscale）
  - `9000/tcp`（仅 `tailscale0`）
  - `41958/tcp`（宝塔面板，仅 `tailscale0`）

所有 MySQL、Redis、Nacos、RabbitMQ、MongoDB、MinIO 管理端口都绑定 `127.0.0.1`，不会暴露到公网。

### Docker 镜像源

服务器无法直连 Docker Hub，已配置：

```json
{
  "registry-mirrors": [
    "https://docker.m.daocloud.io",
    "https://docker.1ms.run"
  ]
}
```

实际拉取镜像使用 `deploy/pull-images.sh`，通过 `docker.1ms.run` 拉取后打回官方标签。MinIO 使用 `docker.1ms.run/alpine/minio:latest-release`，因为 `minio/minio:latest` 在部分镜像源不可用。

---

## 三、项目结构

### 1. 本地目录

```text
D:\JavaProjectTortoise\mall-swarm\
├─ mall-swarm\                 # 后端（Spring Cloud Alibaba 微服务）
│  ├─ mall-common\             # 通用模块
│  ├─ mall-mbg\                # MyBatis Generator 生成模块
│  ├─ mall-gateway\            # 网关服务
│  ├─ mall-auth\               # 统一认证门面
│  ├─ mall-admin\              # 后台管理服务
│  ├─ mall-portal\             # 前台商城服务
│  ├─ mall-search\             # 搜索服务（本次未启动）
│  ├─ mall-monitor\            # 监控服务（本次未启动）
│  ├─ mall-demo\               # 测试服务（本次未启动）
│  ├─ config\                  # Nacos 配置参考
│  ├─ document\                # SQL、文档、部署参考
│  └─ deploy\                  # 本次新增的单机部署文件
├─ mall-admin-web\             # 管理端 Vue3 前端
├─ mall-app-web\               # 移动端 uni-app 前端
└─ 部署文档.md                  # 本文档
```

### 2. 后端模块关系

```text
mall-gateway :8201
   ├─ /mall-admin/**  -> mall-admin :8080
   ├─ /mall-auth/**   -> mall-auth :8401
   └─ /mall-portal/** -> mall-portal :8085

mall-auth
   ├─ Feign -> mall-admin  /admin/login
   └─ Feign -> mall-portal /sso/login

mall-admin  -> MySQL、Redis、MinIO、Nacos
mall-portal -> MySQL、MongoDB、Redis、RabbitMQ、Nacos
```

### 3. 请求链路

```text
浏览器
  ↓
Nginx :80
  ├─ /            -> /var/www/mall/admin 静态文件
  ├─ /app/        -> /var/www/mall/app 静态文件
  ├─ /mall-admin/ -> mall-gateway :8201 -> mall-admin :8080
  ├─ /mall-auth/  -> mall-gateway :8201 -> mall-auth :8401
  └─ /mall-portal/-> mall-gateway :8201 -> mall-portal :8085
```

前端生产环境 API 地址：

```text
mall-admin-web/.env.production:
VITE_BASE_SERVER_URL = /mall-admin

mall-app-web/.env.production:
VITE_API_BASE_URL = /mall-portal
```

---

## 四、本次对项目做的修改

### 1. 后端

| 文件 | 修改 | 原因 |
|---|---|---|
| `pom.xml` | 新增 `docker.skip=true`，并在 `docker-maven-plugin` 配置里加 `<skip>${docker.skip}</skip>` | 原生部署不需要构建 Docker 镜像，避免打包时连接不存在的远程 Docker |
| `mall-admin/.../MinioController.java` | 新增 `minio.public-endpoint`，返回图片 URL 时优先使用 | 后端连接 MinIO 用 `127.0.0.1`，浏览器访问用 Tailscale 地址 |
| `deploy/docker-compose.yml` | 新增中间件编排 | MySQL、Redis、Nacos、RabbitMQ、MongoDB、MinIO |
| `deploy/nacos/*.yaml.tpl` | 新增 Nacos 配置模板 | 通过 `envsubst` 注入服务器密码 |
| `deploy/systemd/*.service` | 新增 4 个 Java 服务单元 | 原生 JAR 运行、自动重启 |
| `deploy/nginx/mall.conf` | 新增 Nginx 配置 | 静态资源 + API 反向代理 |
| `deploy/deploy.sh` | 新增一键部署脚本 | 中间件、SQL、Nacos、systemd、Nginx |
| `deploy/pull-images.sh` | 新增镜像拉取脚本 | 绕过 Docker Hub 无法直连 |
| `deploy/logrotate/mall-swarm` | 新增日志轮转 | 防止日志无限增长 |

### 2. 前端

| 文件 | 修改 |
|---|---|
| `mall-admin-web/.env.production` | `VITE_BASE_SERVER_URL=/mall-admin` |
| `mall-app-web/.env.production` | `VITE_API_BASE_URL=/mall-portal` |

### 3. 没有修改的内容

- 没有修改任何业务逻辑；
- 没有修改数据库表结构；
- 没有修改前端页面代码；
- 没有修改网关路由、Sa-Token 鉴权规则。

### 4. 已推送的提交

| 仓库 | 提交 |
|---|---|
| `onionandapple/mall-swarm` | `4813b68` 部署适配：跳过 Docker 镜像构建、支持 MinIO 公网地址并补充单机部署文件 |
| `onionandapple/mall-swarm` | `e0bd8bb` 补充部署文档（`deploy/README.md`） |
| `onionandapple/mall-admin-web` | `57e7f4c` 部署适配：生产环境 API 走同源 `/mall-admin` 代理 |
| `onionandapple/mall-app-web` | `4292238` 部署适配：生产环境 API 走同源 `/mall-portal` 代理 |

---

## 五、部署基本流程

### 1. 本地构建后端

环境：JDK 17+、Maven 3.6+。

```bash
cd D:\JavaProjectTortoise\mall-swarm\mall-swarm

mvn clean package -DskipTests -Ddocker.skip=true \
  -pl mall-gateway,mall-auth,mall-admin,mall-portal -am
```

产物：

```text
mall-gateway/target/mall-gateway-1.0-SNAPSHOT.jar
mall-auth/target/mall-auth-1.0-SNAPSHOT.jar
mall-admin/target/mall-admin-1.0-SNAPSHOT.jar
mall-portal/target/mall-portal-1.0-SNAPSHOT.jar
```

> 本次因为 Tailscale 上传 400 MB JAR 太慢，改为把源码上传到服务器，在服务器上执行同样的 Maven 命令构建。两种方式产物一致。

### 2. 本地构建前端

环境：Node 20/22 LTS 推荐（本次使用 Node 26.5.0 也能构建成功）。

```bash
cd D:\JavaProjectTortoise\mall-swarm\mall-admin-web
npm ci --registry=https://registry.npmmirror.com
npm run build
# 产物：dist/

cd D:\JavaProjectTortoise\mall-swarm\mall-app-web
npm ci --registry=https://registry.npmmirror.com
npm run build:h5
# 产物：dist/build/h5/
```

### 3. 服务器准备

```bash
apt-get update
apt-get install -y docker.io docker-compose openjdk-21-jre-headless openjdk-21-jdk-headless nginx gettext-base curl
```

配置 Docker 镜像源：

```bash
mkdir -p /etc/docker
cat > /etc/docker/daemon.json <<'EOF'
{
  "registry-mirrors": ["https://docker.m.daocloud.io", "https://docker.1ms.run"],
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "3" }
}
EOF
systemctl enable --now docker
systemctl restart docker
```

### 4. 目录规划

```text
/opt/mall-swarm/
├─ .env                      # 服务器密码，权限 600
├─ mall-admin.jar
├─ mall-auth.jar
├─ mall-gateway.jar
├─ mall-portal.jar
├─ deploy/
│  ├─ docker-compose.yml
│  ├─ deploy.sh
│  ├─ pull-images.sh
│  ├─ nacos/
│  ├─ nginx/
│  ├─ systemd/
│  └─ logrotate/
├─ sql/mall.sql
└─ logs/

/var/www/mall/
├─ admin/                    # 管理端 dist
└─ app/                      # H5 dist
```

### 5. 拉取中间件镜像

```bash
/opt/mall-swarm/deploy/pull-images.sh
```

### 6. 配置服务器密码

```bash
cp /opt/mall-swarm/deploy/.env.example /opt/mall-swarm/.env
vi /opt/mall-swarm/.env
chmod 600 /opt/mall-swarm/.env
```

需要填写：

```text
MYSQL_ROOT_PASSWORD
MYSQL_PASSWORD
REDIS_PASSWORD
RABBITMQ_PASSWORD
MINIO_PASSWORD
MINIO_PUBLIC_ENDPOINT=http://100.125.54.127:9000
NACOS_AUTH_TOKEN
NACOS_AUTH_IDENTITY_KEY
NACOS_AUTH_IDENTITY_VALUE
```

### 7. 一键部署

```bash
cd /opt/mall-swarm
./deploy/deploy.sh
```

脚本会依次完成：

1. 渲染 Nacos 配置模板到 `deploy/rendered/`；
2. `docker compose up -d` 启动中间件；
3. 等待 MySQL、Nacos、RabbitMQ、MongoDB 健康；
4. 创建 `mall` 数据库并导入 `sql/mall.sql`（已有表则跳过）；
5. 配置 RabbitMQ `/mall` virtual host 权限；
6. 通过 Nacos API 发布 4 个配置；
7. 安装 systemd 服务，逐个启动 `mall-admin`、`mall-portal`、`mall-auth`、`mall-gateway`；
8. 配置并 reload Nginx。

### 8. 手动启动顺序

如果不用脚本，建议按以下顺序：

```bash
cd /opt/mall-swarm/deploy
docker compose --env-file /opt/mall-swarm/.env up -d

# MySQL / Nacos / RabbitMQ / MongoDB 健康后
systemctl start mall-admin
systemctl start mall-portal
systemctl start mall-auth
systemctl start mall-gateway

systemctl reload nginx
```

### 9. 验证

```bash
# 静态页面
curl -I http://127.0.0.1/
curl -I http://127.0.0.1/app/

# 服务健康
curl http://127.0.0.1:8080/actuator/health
curl http://127.0.0.1:8085/actuator/health
curl http://127.0.0.1:8401/actuator/health
curl http://127.0.0.1:8201/actuator/health

# 管理端登录（经过网关）
curl -X POST http://127.0.0.1:8201/mall-admin/admin/login \
  -H 'Content-Type: application/json' \
  -d '{"username":"admin","password":"macro123"}'

# 移动端登录（经过网关）
curl -X POST 'http://127.0.0.1:8201/mall-portal/sso/login?username=test&password=123456'

# 统一认证
curl -X POST 'http://127.0.0.1:8201/mall-auth/auth/login?clientId=admin-app&username=admin&password=macro123'
```

---

## 六、访问与管理入口

### 1. 页面访问

- 管理端：`http://100.125.54.127/#/login`
  - 账号：`admin`
  - 密码：`macro123`
- 移动端 H5：`http://100.125.54.127/app/`
  - 账号：`test`
  - 密码：`123456`

### 2. 统一认证接口

管理端：

```bash
curl -X POST 'http://100.125.54.127/mall-auth/auth/login?clientId=admin-app&username=admin&password=macro123'
```

移动端：

```bash
curl -X POST 'http://100.125.54.127/mall-auth/auth/login?clientId=portal-app&username=test&password=123456'
```

`clientId` 取值：

- `admin-app`：转发到 `mall-admin` 的 `/admin/login`
- `portal-app`：转发到 `mall-portal` 的 `/sso/login`

### 3. 中间件控制台（SSH 隧道）

这些端口只绑定 `127.0.0.1`，需要在本地建立 SSH 隧道：

```bash
# Nacos
ssh -i C:\Users\a1881\.ssh\x280_root_ed25519 \
  -L 8848:127.0.0.1:8848 root@100.125.54.127

# RabbitMQ
ssh -i C:\Users\a1881\.ssh\x280_root_ed25519 \
  -L 15672:127.0.0.1:15672 root@100.125.54.127

# MinIO 控制台
ssh -i C:\Users\a1881\.ssh\x280_root_ed25519 \
  -L 9001:127.0.0.1:9001 root@100.125.54.127
```

打开：

| 控制台 | 地址 | 账号 |
|---|---|---|
| Nacos | `http://127.0.0.1:8848/nacos/` | 未开启鉴权 |
| RabbitMQ | `http://127.0.0.1:15672/` | `mall` / 见 `/opt/mall-swarm/.env` |
| MinIO | `http://127.0.0.1:9001/` | `minioadmin` / 见 `/opt/mall-swarm/.env` |

### 4. MinIO 图片

上传图片后返回的 URL 形如：

```text
http://100.125.54.127:9000/mall/20261117/xxx.png
```

该地址只对 Tailscale 网络开放。如果以后换成域名/HTTPS，只需要修改 Nacos 配置里的：

```yaml
minio:
  public-endpoint: https://files.example.com
```

然后重启 `mall-admin`。

---

## 七、日常运维

### 1. 服务管理

```bash
systemctl status mall-admin mall-portal mall-auth mall-gateway
systemctl restart mall-admin
systemctl restart mall-portal
systemctl restart mall-auth
systemctl restart mall-gateway
systemctl status nginx
```

建议重启顺序：

```text
mall-admin -> mall-portal -> mall-auth -> mall-gateway
```

### 2. Docker 中间件

```bash
cd /opt/mall-swarm/deploy

docker compose --env-file /opt/mall-swarm/.env ps
docker compose --env-file /opt/mall-swarm/.env logs -f mysql
docker compose --env-file /opt/mall-swarm/.env restart nacos
docker compose --env-file /opt/mall-swarm/.env up -d
```

### 3. 日志

| 日志 | 路径 |
|---|---|
| 后端服务 | `/opt/mall-swarm/logs/mall-*.log` |
| systemd | `journalctl -u mall-admin -f` |
| Nginx | `/var/log/nginx/` |
| Docker 容器 | `docker logs mall-xxx` |
| Nacos 客户端 | `/home/mall/logs/nacos/` |

日志已配置 logrotate：

```text
/etc/logrotate.d/mall-swarm
```

每天轮转，保留 7 天，压缩。

### 4. Nacos 配置修改

Nacos 配置列表：

```text
mall-admin-dev.yaml
mall-gateway-dev.yaml
mall-portal-dev.yaml
mall-auth-dev.yaml
```

修改后需要重启对应服务，因为本次为了规避 Nacos 2.5.1 客户端频繁刷新日志，关闭了配置自动刷新：

```text
--spring.cloud.nacos.config.refresh-enabled=false
```

### 5. 备份

建议备份：

```text
/opt/mall-swarm/.env
/opt/mall-swarm/deploy/data/mysql
/opt/mall-swarm/deploy/data/mongo
/opt/mall-swarm/deploy/data/minio
/opt/mall-swarm/deploy/data/nacos
/etc/nginx/sites-available/mall.conf
/etc/systemd/system/mall-*.service
```

MySQL 逻辑备份：

```bash
source /opt/mall-swarm/.env
docker exec mall-mysql mysqldump -uroot -p"$MYSQL_ROOT_PASSWORD" mall > /opt/mall-swarm/mall-$(date +%F).sql
```

### 6. 更新发布

```bash
# 本地重新构建 JAR 和前端 dist
# 上传到服务器后
systemctl restart mall-admin
systemctl restart mall-portal
systemctl restart mall-auth
systemctl restart mall-gateway
systemctl reload nginx
```

前端更新只需要替换：

```text
/var/www/mall/admin/
/var/www/mall/app/
```

---

## 八、故障排查

| 现象 | 原因 | 解决 |
|---|---|---|
| Docker 拉取镜像超时 | Docker Hub 不可直连 | 使用 `deploy/pull-images.sh` 或配置镜像源 |
| Nacos 配置读取为空 | Nacos 2.4.3 与客户端 3.0.3 不兼容 | 使用 Nacos 2.5.1 |
| Nacos 3 管理 API 403 | Nacos 3 管理 API 需要鉴权 | 本次改用 Nacos 2.5.1，避免额外鉴权配置 |
| 后端日志疯狂刷 `data-received` | Nacos 2.5.1 刷新监听频繁触发 | systemd 增加 `--spring.cloud.nacos.config.refresh-enabled=false` |
| MySQL 报 `Public Key Retrieval is not allowed` | MySQL 8 认证插件 | JDBC URL 增加 `allowPublicKeyRetrieval=true` |
| MinIO 启动报 `file access denied` | 数据目录属主不对 | `chown -R 100:101 /opt/mall-swarm/deploy/data/minio` |
| MinIO 上传成功但图片打不开 | 返回了 `127.0.0.1:9000` | 配置 `minio.public-endpoint` 为 Tailscale 地址 |
| 前端 404 | Nginx root 或代理路径不对 | 检查 `/var/www/mall/admin`、`/app/` 和 `/mall-admin/` 代理 |
| 前端构建失败 | Node 版本过新/过旧 | 使用 Node 20/22 LTS |
| 登录接口 400 | curl 发送了非法 JSON 转义 | 使用正确的 JSON 文件或 `--data-binary @file` |
| 登录提示密码错误 | SQL 默认密码不是 123456 | 管理端使用 `admin/macro123`，移动端使用 `test/123456` |
| 8080/8085 端口冲突 | 与其他服务冲突 | 本项目服务只绑定 `127.0.0.1`，检查 `ss -lntp` |

---

## 九、资源占用

部署后实测（4 个 Java 服务 + 6 个中间件 + Nginx）：

```text
内存总量：7.3 GiB
已使用：约 4.9 GiB
可用：约 2.4 GiB
Swap：几乎未使用
```

主要进程 RSS：

| 进程 | 约 RSS |
|---|---:|
| `mall-admin` | 约 830 MB |
| `mall-portal` | 约 840 MB |
| `mall-gateway` | 约 630 MB |
| `mall-auth` | 约 560 MB |
| MySQL | 约 450 MB |
| MongoDB | 约 175 MB |
| RabbitMQ | 约 170 MB |
| MinIO | 约 160 MB |

CPU 在启动瞬间会到较高负载，稳定后空闲负载很低。不要在服务器上同时跑 Maven 构建、Jenkins、IDE。

---

## 十、安全建议

1. 所有中间件端口只绑定 `127.0.0.1`，不要改成 `0.0.0.0`。
2. UFW 只开放 22、80、443、41641，以及 Tailscale 网段的 9000/41958。
3. `/opt/mall-swarm/.env` 权限保持 `600`，不要提交到 Git。
4. 首次登录后修改 `admin`、`macro`、`test` 的密码。
5. 建议关闭 SSH 密码登录，只保留密钥登录。
6. 建议定期轮换数据库、Redis、RabbitMQ、MinIO 密码和 Nacos 身份密钥。
7. 如果需要公网访问，建议使用 Cloudflare Tunnel 或 IPv6 + DDNS，不要把 3306、8848、9200、15672 直接暴露。
8. Tailscale ACL 可以进一步限制哪些设备能访问 80/443/9000。

---

## 十一、当前限制

- 本次未启动 `mall-search` 和 Elasticsearch，商品搜索走 `mall-portal` 的数据库查询；如果以后需要 ES 搜索，需要额外约 1.5～2 GB 内存。
- 本次未启动 `mall-monitor` 和 `mall-demo`，不影响业务。
- Nacos 配置自动刷新已关闭；修改 Nacos 配置后需要重启对应服务。
- 当前通过 Tailscale 地址访问，未配置域名和 HTTPS。
