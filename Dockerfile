FROM alpine:3.20

RUN apk add --no-cache php82 \
    && ln -s /usr/bin/php82 /usr/bin/php

WORKDIR /var/www/html

COPY app/browser/ ./
# Coin-Spinanimation (coin-1..coin-9): Quelle liegt im Repo-Root unter
# public/coins (siehe README-Thumbnail daneben), muss aber im Docroot
# liegen, damit game.js/mapRenderer.js sie unter "coins/coin-N.png" laden
# kann.
COPY public/coins/ ./coins/

ENV MAP_DATA_DIR=/data

EXPOSE 80

CMD ["php", "-S", "0.0.0.0:80", "-t", "/var/www/html"]
