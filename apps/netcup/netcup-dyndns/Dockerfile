FROM php:8.3-cli

WORKDIR /app

RUN apt update && apt install -y git

RUN git clone https://github.com/stecklars/dynamic-dns-netcup-api.git . \
    && chmod u+x update.php

COPY config.php .

# required environment variables
ENV CUSTOMERNR=""
ENV APIPASSWORD=""
ENV APIKEY=""
ENV DOMAINLIST=""

CMD ["php", "update.php"]
