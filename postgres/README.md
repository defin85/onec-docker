# PostgreSQL Pro для 1С:Предприятие

Конфигурация **Postgres Pro Standard 16** оптимизированная для работы с **1С:Предприятие**.

## Особенности

✅ **Postgres Pro Standard 16** - специальная версия PostgreSQL с патчами от 1С
✅ **Расширения для 1С** - mchar, fulleq, fasttrun (создаются автоматически)
✅ **Локаль ru_RU.UTF-8** - правильная поддержка русского языка
✅ **Оптимизация для 1С** - настройки производительности

## Зачем Postgres Pro?

Обычный PostgreSQL **НЕ совместим** с 1С:Предприятие без специальных расширений:

```
❌ postgres:16-alpine  → ERROR: extension mchar is not available
✅ onec-postgres-pro:16 → Работает с 1С из коробки
```

**Расширения:**
- **mchar** - типы данных совместимые с MS SQL (ОБЯЗАТЕЛЬНО для 1С)
- **fulleq** - оптимизация сравнения строк
- **fasttrun** - ускорение операций усечения

## Быстрый старт

### Вариант 1: Использовать готовый образ (docker-compose)

```bash
# 1. Загрузить переменные окружения
source .onec.env

# 2. Собрать образ Postgres Pro (первый раз)
docker-compose build postgres

# 3. Запустить PostgreSQL + pgAdmin
docker-compose up -d postgres pgadmin
```

### Вариант 2: Собрать образ отдельно

```bash
# 1. Загрузить переменные окружения
source .onec.env

# 2. Собрать образ
./build-postgres.sh

# 3. Запустить
docker-compose up -d postgres pgadmin
```

## Проверка расширений

После запуска контейнера проверьте, что расширения созданы:

```bash
# Подключиться к контейнеру
docker-compose exec postgres psql -U postgres

# Проверить расширения
\dx

# Должны быть:
# mchar      | 1.0 | public | MCHAR and MVARCHAR types
# fulleq     | 1.0 | public | Full text equality operator
# fasttrun   | 1.0 | public | Fast truncate
```

## Подключение из 1С:Предприятие

**Параметры подключения:**
- Сервер СУБД: `postgres`
- Порт: `5432`
- База данных: `postgres` (или создайте свою)
- Пользователь: `postgres`
- Пароль: `changeme_strong_password` (из .onec.env)

**Создание базы для 1С:**
```sql
-- Через psql или pgAdmin
CREATE DATABASE onec_db
  WITH OWNER = postgres
  ENCODING = 'UTF8'
  LC_COLLATE = 'ru_RU.UTF-8'
  LC_CTYPE = 'ru_RU.UTF-8';

-- Подключиться к новой базе
\c onec_db

-- Создать расширения для 1С
CREATE EXTENSION IF NOT EXISTS mchar;
CREATE EXTENSION IF NOT EXISTS fulleq;
CREATE EXTENSION IF NOT EXISTS fasttrun;
```

## Доступ к pgAdmin

После запуска откройте:
- **URL:** http://localhost:5050
- **Email:** admin@example.com (см. .onec.env)
- **Password:** admin_strong_password (см. .onec.env)

Подключение к PostgreSQL уже настроено автоматически через `pgadmin-servers.json`.

## Управление данными

```bash
# Бэкап базы данных
docker-compose exec postgres pg_dump -U postgres postgres > backup.sql

# Восстановление из бэкапа
cat backup.sql | docker-compose exec -T postgres psql -U postgres

# Просмотр логов
docker-compose logs -f postgres
```

## Troubleshooting

### Проблема: ERROR: extension mchar is not available

**Причина:** Используется обычный PostgreSQL вместо Postgres Pro.

**Решение:**
```bash
# 1. Остановить контейнер
docker-compose down

# 2. Удалить старый volume (ВНИМАНИЕ: удалит данные!)
docker volume rm onec-docker_postgres_data

# 3. Пересобрать образ
docker-compose build postgres

# 4. Запустить заново
docker-compose up -d postgres
```

### Проблема: pg_isready not found

**Причина:** Путь к исполняемым файлам Postgres Pro не добавлен в PATH.

**Решение:** Проверьте, что в Dockerfile установлена переменная:
```dockerfile
ENV PATH=/opt/pgpro/std-16/bin:$PATH
```

### Проблема: locale ru_RU.UTF-8 not found

**Причина:** Локаль не установлена в образе.

**Решение:** Проверьте, что в Dockerfile выполняется:
```dockerfile
RUN localedef -i ru_RU -c -f UTF-8 -A /usr/share/locale/locale.alias ru_RU.UTF-8
```

## Структура файлов

```
postgres/
├── Dockerfile              - Сборка образа Postgres Pro 16
├── docker-entrypoint.sh    - Скрипт инициализации с расширениями 1С
├── README.md               - Эта документация
├── init-scripts/           - SQL-скрипты (выполняются при первом запуске)
└── pgadmin-servers.json    - Автоконфигурация pgAdmin
```

## Версии

- **Postgres Pro:** Standard 16
- **Расширения:** mchar 1.0, fulleq 1.0, fasttrun 1.0
- **Базовый образ:** debian:bookworm-slim
- **Локаль:** ru_RU.UTF-8

## Ссылки

- [Официальный сайт Postgres Pro](https://postgrespro.ru/)
- [Документация Postgres Pro 16](https://postgrespro.ru/docs/postgrespro/16/)
- [Расширение mchar](https://postgrespro.ru/docs/postgrespro/16/mchar)
- [1C + PostgreSQL](https://1c.postgres.ru/)

## Безопасность

⚠️ **ВАЖНО:** Измените пароли перед использованием в production!

```bash
# В .onec.env установите:
export POSTGRES_PASSWORD=ваш_сильный_пароль
export PGADMIN_DEFAULT_PASSWORD=другой_сильный_пароль
```

## Дополнительная настройка

Для production окружения рекомендуется:
1. Настроить `postgresql.conf` для 1С (shared_buffers, work_mem и т.д.)
2. Настроить `pg_hba.conf` для безопасного доступа
3. Включить репликацию и бэкапы
4. Мониторинг производительности

См. официальную документацию 1С и Postgres Pro для оптимальных настроек.
