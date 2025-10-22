# Dockerfile для PostgreSQL Pro с поддержкой 1С:Предприятие
# Включает расширения mchar, fulleq, fasttrun, необходимые для работы 1С
# Базируется на Debian и использует официальный репозиторий Postgres Pro

FROM debian:bookworm-slim

LABEL maintainer="onec-docker project"
LABEL description="Postgres Pro Standard 16 with 1C:Enterprise support (mchar, fulleq, fasttrun)"
LABEL version="16"

# Переменные окружения
ENV PG_MAJOR=16
ENV PGDATA=/var/lib/postgresql/data
ENV LANG=ru_RU.UTF-8
ENV LC_ALL=ru_RU.UTF-8

# Создание пользователя postgres
RUN groupadd -r postgres --gid=999 && \
    useradd -r -g postgres --uid=999 --home-dir=/var/lib/postgresql --shell=/bin/bash postgres && \
    mkdir -p /var/lib/postgresql && \
    chown -R postgres:postgres /var/lib/postgresql

# Установка необходимых пакетов и настройка локали
RUN apt-get update && apt-get install -y \
    ca-certificates \
    locales \
    wget \
    gnupg2 \
    gosu \
    && rm -rf /var/lib/apt/lists/* \
    && localedef -i ru_RU -c -f UTF-8 -A /usr/share/locale/locale.alias ru_RU.UTF-8

# Добавление репозитория Postgres Pro
RUN wget --quiet -O - https://repo.postgrespro.ru/pgpro-16/keys/pgpro-repo-add.sh | bash

# Установка Postgres Pro Standard 16 с contrib модулями
RUN apt-get update && apt-get install -y \
    postgrespro-std-16 \
    postgrespro-std-16-contrib \
    && rm -rf /var/lib/apt/lists/*

# Создание директории для данных
RUN mkdir -p "$PGDATA" && \
    chown -R postgres:postgres "$PGDATA" && \
    chmod 700 "$PGDATA"

# Создание директории для сокета
RUN mkdir -p /var/run/postgresql && \
    chown -R postgres:postgres /var/run/postgresql && \
    chmod 775 /var/run/postgresql

# Копирование скриптов инициализации
COPY docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh && \
    ln -s /usr/local/bin/docker-entrypoint.sh /

# Создание директории для init scripts
RUN mkdir -p /docker-entrypoint-initdb.d

# Expose порта PostgreSQL
EXPOSE 5432

# Переключение на пользователя postgres
USER postgres

# Установка пути к исполняемым файлам Postgres Pro
ENV PATH=/opt/pgpro/std-$PG_MAJOR/bin:$PATH

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["postgres"]
