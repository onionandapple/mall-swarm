spring:
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

logging:
  level:
    root: info
    com.macro.mall: info

logstash:
  host: 127.0.0.1
  enableInnerLog: false
