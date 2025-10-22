# Миграция на Postgres Pro 16

## Проблема

При попытке подключить 1С:Предприятие к обычному PostgreSQL возникает ошибка:

```
Ошибка СУБД: 0A000: ERROR: extension mchar is not available
DETAIL: Could not open extension control file /usr/local/share/postgresql/extension/mchar.control : No such file or directory.
HINT: The extension must first be installed on the system where PostgreSQL is running
```

**Причина:** Обычный PostgreSQL не содержит расширения mchar, fulleq, fasttrun, которые **ОБЯЗАТЕЛЬНЫ** для работы 1С:Предприятие.

## Решение

Заменить обычный PostgreSQL на **Postgres Pro** - специальную версию с патчами от 1С.

## Что было сделано

### 1. Создан Dockerfile для Postgres Pro 16

**Файл:** `postgres/Dockerfile`

**Особенности:**
- Базируется на `debian:bookworm-slim`
- Добавляет официальный репозиторий Postgres Pro
- Устанавливает `postgrespro-std-16` и `postgrespro-std-16-contrib`
- Настраивает локаль `ru_RU.UTF-8`
- Создает пользователя postgres (uid=999, gid=999)

### 2. Создан docker-entrypoint.sh

**Файл:** `postgres/docker-entrypoint.sh`

**Особенности:**
- Инициализация базы данных
- **Автоматическое создание расширений** для 1С:
  - `CREATE EXTENSION IF NOT EXISTS mchar;`
  - `CREATE EXTENSION IF NOT EXISTS fulleq;`
  - `CREATE EXTENSION IF NOT EXISTS fasttrun;`
- Выполнение init-scripts из `/docker-entrypoint-initdb.d/`
- Совместимость с переменными окружения PostgreSQL

### 3. Создан скрипт сборки

**Файл:** `build-postgres.sh`

**Использование:**
```bash
source .onec.env
./build-postgres.sh
```

### 4. Обновлен docker-compose.yml

**Изменения:**
```yaml
# Было:
image: postgres:16-alpine

# Стало:
image: ${DOCKER_REGISTRY_URL}/onec-postgres-pro:16
build:
  context: ./postgres
  dockerfile: Dockerfile
```

### 5. Обновлена документация

**Файл:** `postgres/README.md` - полная документация по использованию

## Пошаговая миграция

### Шаг 1: Резервное копирование данных (если есть)

```bash
# Если у вас уже есть данные в старом PostgreSQL
docker-compose exec postgres pg_dumpall -U postgres > backup_all.sql
```

### Шаг 2: Остановка и удаление старых контейнеров

```bash
# Остановить все сервисы
docker-compose down

# Удалить старый volume PostgreSQL (ВНИМАНИЕ: удалит данные!)
docker volume rm onec-docker_postgres_data
```

### Шаг 3: Сборка нового образа

```bash
# Загрузить переменные окружения
source .onec.env

# Вариант 1: Через docker-compose
docker-compose build postgres

# Вариант 2: Через скрипт
./build-postgres.sh
```

### Шаг 4: Запуск нового контейнера

```bash
# Запустить PostgreSQL Pro
docker-compose up -d postgres

# Проверить логи
docker-compose logs -f postgres
```

### Шаг 5: Проверка расширений

```bash
# Подключиться к контейнеру
docker-compose exec postgres psql -U postgres

# Проверить расширения
\dx

# Должны быть:
# mchar      | 1.0 | public | MCHAR and MVARCHAR types
# fulleq     | 1.0 | public | Full text equality operator
# fasttrun   | 1.0 | public | Fast truncate

# Выйти
\q
```

### Шаг 6: Восстановление данных (если делали backup)

```bash
# Восстановить данные
cat backup_all.sql | docker-compose exec -T postgres psql -U postgres
```

### Шаг 7: Тест подключения из 1С

Создайте новую информационную базу в 1С:Предприятие:

**Параметры:**
- Тип СУБД: PostgreSQL
- Сервер: localhost (или postgres если из Docker)
- Порт: 5432
- База данных: onec_db (создайте через pgAdmin)
- Пользователь: postgres
- Пароль: changeme_strong_password

## Проверка успешности миграции

### 1. Проверка версии PostgreSQL

```bash
docker-compose exec postgres psql -U postgres -c "SELECT version();"
```

Должно содержать: **Postgres Pro**

### 2. Проверка расширений

```bash
docker-compose exec postgres psql -U postgres -c "\dx"
```

Должны быть: **mchar**, **fulleq**, **fasttrun**

### 3. Проверка локали

```bash
docker-compose exec postgres psql -U postgres -c "SHOW lc_collate; SHOW lc_ctype;"
```

Должно быть: **ru_RU.UTF-8**

### 4. Тест создания базы для 1С

```bash
docker-compose exec postgres psql -U postgres -c "
CREATE DATABASE test_1c
  WITH OWNER = postgres
  ENCODING = 'UTF8'
  LC_COLLATE = 'ru_RU.UTF-8'
  LC_CTYPE = 'ru_RU.UTF-8';
"

# Подключиться к новой базе и создать расширения
docker-compose exec postgres psql -U postgres -d test_1c -c "
CREATE EXTENSION IF NOT EXISTS mchar;
CREATE EXTENSION IF NOT EXISTS fulleq;
CREATE EXTENSION IF NOT EXISTS fasttrun;
"

# Проверить расширения
docker-compose exec postgres psql -U postgres -d test_1c -c "\dx"
```

## Troubleshooting

### Проблема: Сборка не удаётся - не может скачать пакеты

**Причина:** Проблемы с доступом к repo.postgrespro.ru

**Решение:**
1. Проверьте интернет-соединение
2. Проверьте, что не блокируется файрволлом
3. Попробуйте позже (возможно временные проблемы с репозиторием)

### Проблема: docker-entrypoint.sh не запускается

**Причина:** Скрипт не имеет прав на выполнение

**Решение:**
```dockerfile
# В Dockerfile должно быть:
COPY docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh
```

### Проблема: pg_isready not found в healthcheck

**Причина:** PATH не включает /opt/pgpro/std-16/bin

**Решение:**
```dockerfile
# В Dockerfile должно быть:
ENV PATH=/opt/pgpro/std-16/bin:$PATH
```

### Проблема: Расширения не создаются автоматически

**Причина:** Функция `docker_setup_1c_extensions` не вызывается

**Решение:** Проверьте, что в `docker-entrypoint.sh` в функции `_main` есть вызов:
```bash
docker_setup_1c_extensions
```

## Откат на обычный PostgreSQL (если нужно)

Если по какой-то причине нужно вернуться к обычному PostgreSQL:

```bash
# 1. Остановить контейнеры
docker-compose down

# 2. В docker-compose.yml изменить обратно:
#    image: postgres:16-alpine
#    # Удалить build: секцию

# 3. Удалить volume
docker volume rm onec-docker_postgres_data

# 4. Запустить заново
docker-compose up -d postgres
```

**ВНИМАНИЕ:** После отката 1С снова не сможет подключиться из-за отсутствия mchar!

## Дополнительная информация

- [Postgres Pro Standard 16 Документация](https://postgrespro.ru/docs/postgrespro/16/)
- [Расширение mchar](https://postgrespro.ru/docs/postgrespro/16/mchar)
- [1C + PostgreSQL](https://1c.postgres.ru/)
- [Infostart: Распространённые ошибки PostgreSQL для 1С](https://infostart.ru/1c/articles/1872745/)

## Поддержка

При возникновении проблем:
1. Проверьте логи: `docker-compose logs postgres`
2. Проверьте документацию: `postgres/README.md`
3. Создайте issue в репозитории проекта
