spring:
  datasource:
    url: jdbc:mysql://127.0.0.1:3306/mall?useUnicode=true&characterEncoding=utf-8&serverTimezone=Asia/Shanghai&useSSL=false&allowPublicKeyRetrieval=true
    username: mall
    password: ${MYSQL_PASSWORD}
  data:
    redis:
      host: 127.0.0.1
      port: 6379
      database: 0
      password: ${REDIS_PASSWORD}
      timeout: 3000ms
  boot:
    admin:
      client:
        enabled: false

minio:
  endpoint: http://127.0.0.1:9000
  public-endpoint: ${MINIO_PUBLIC_ENDPOINT}
  bucketName: mall
  accessKey: minioadmin
  secretKey: ${MINIO_PASSWORD}

logging:
  level:
    root: info
    com.macro.mall: info

logstash:
  host: 127.0.0.1
  enableInnerLog: false
