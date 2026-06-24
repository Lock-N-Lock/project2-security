# docker/fail2ban/Dockerfile
# 버전 및 os 체제 고정을 위한 커스텀 이미지

FROM alpine:3.20

RUN apk add --no-cache \
    fail2ban \
    iptables \
    ip6tables \
    bash \
    tzdata

CMD ["fail2ban-server", "-f", "-x", "-v", "-c", "/data"]