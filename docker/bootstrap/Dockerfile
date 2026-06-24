FROM alpine:3.20

WORKDIR /bootstrap

COPY docker /bootstrap/docker
COPY scripts /bootstrap/scripts

RUN chmod +x /bootstrap/scripts/*.sh

CMD ["sh"]