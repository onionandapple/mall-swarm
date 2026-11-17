spring:
  datasource:
    url: jdbc:mysql://127.0.0.1:3306/mall?useUnicode=true&characterEncoding=utf-8&serverTimezone=Asia/Shanghai&useSSL=false&allowPublicKeyRetrieval=true
    username: mall
    password: ${MYSQL_PASSWORD}
  data:
    mongodb:
      host: 127.0.0.1
      port: 27017
      database: mall-port
    redis:
      host: 127.0.0.1
      port: 6379
      database: 0
      password: ${REDIS_PASSWORD}
      timeout: 3000ms
  rabbitmq:
    host: 127.0.0.1
    port: 5672
    virtual-host: /mall
    username: mall
    password: ${RABBITMQ_PASSWORD}
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

# 不接入支付宝，前端 VITE_USE_ALIPAY=false
alipay:
  gatewayUrl: https://openapi-sandbox.dl.alipaydev.com/gateway.do
  appId: your appId
  alipayPublicKey: your alipayPublicKey
  appPrivateKey: your appPrivateKey
  returnUrl: http://127.0.0.1/app/#/pages/money/paySuccess
  notifyUrl:
