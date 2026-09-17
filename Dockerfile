FROM alpine:3.20

RUN apk add --no-cache php82 \
    && ln -s /usr/bin/php82 /usr/bin/php

WORKDIR /var/www/html

COPY app/browser/ ./

# Default-Ordner mit den generierten Karten (siehe app/maze-gen);
# docker-compose.yml setzt das passend zum gemeinsamen Volume mit dem
# maze-gen-Service. Welches Level angezeigt wird, waehlt "?level=" in der
# URL (Default: Level 1).
ENV MAP_DATA_DIR=/data

EXPOSE 80

CMD ["php", "-S", "0.0.0.0:80", "-t", "/var/www/html"]
