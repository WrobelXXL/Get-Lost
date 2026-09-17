FROM alpine:3.20

RUN apk add --no-cache php82 \
    && ln -s /usr/bin/php82 /usr/bin/php

WORKDIR /var/www/html

COPY app/browser/ ./

ENV MAP_DATA_DIR=/data

EXPOSE 80

CMD ["php", "-S", "0.0.0.0:80", "-t", "/var/www/html"]
