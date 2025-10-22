# Сравнение подходов к PostgreSQL для 1С

## Два варианта решения

В проекте доступно **два способа** получить PostgreSQL с поддержкой расширений для 1С:

### 1. **Postgres Pro** (Dockerfile)
Использует репозиторий Postgres Professional

### 2. **PostgreSQL от 1С** (Dockerfile.1c)
Использует официальные дистрибутивы 1С с releases.1c.ru

---

## Подробное сравнение

| Характеристика | Postgres Pro<br/>(Dockerfile) | PostgreSQL от 1С<br/>(Dockerfile.1c) |
|----------------|-------------------------------|--------------------------------------|
| **Источник** | postgrespro.ru репозиторий | releases.1c.ru дистрибутивы |
| **Скачивание** | Автоматическое (apt) | Через yard или вручную |
| **Учетные данные** | Не требуются | ONEC_USERNAME/PASSWORD |
| **Локальные дистрибутивы** | Не поддерживаются | Поддерживаются (distr/) |
| **Версия PostgreSQL** | 16 (фиксированная) | Любая доступная от 1С |
| **Расширения** | mchar, fulleq, fasttrun | mchar, fulleq, fasttrun |
| **Паттерн сборки** | Простой (single-stage) | Multi-stage (как платформа 1С) |
| **Размер образа** | ~400 MB | ~500 MB |
| **Поддержка 1С** | Официальная (Postgres Pro) | Официальная (1С) |
| **Обновления** | Через apt upgrade | Ручное обновление дистрибутивов |

---

## Плюсы и минусы

### Postgres Pro (Dockerfile)

**✅ Плюсы:**
- Простая сборка (без учетных данных)
- Автоматические обновления через apt
- Проверенный вариант (Postgres Professional)
- Быстрая сборка
- Не нужно скачивать дистрибутивы

**❌ Минусы:**
- Фиксированная версия PostgreSQL 16
- Зависимость от доступности repo.postgrespro.ru
- Сложнее откатиться на старую версию
- Не соответствует паттерну проекта (multi-stage build)

---

### PostgreSQL от 1С (Dockerfile.1c)

**✅ Плюсы:**
- **Точно такой же подход**, как для платформы 1С
- Поддержка **любых версий** PostgreSQL от 1С
- **Локальные дистрибутивы** (distr/) - работает offline
- Полный контроль версий
- **Единый стиль** сборки в проекте
- Официальные дистрибутивы от 1С

**❌ Минусы:**
- Требуется ITS подписка (ONEC_USERNAME/PASSWORD)
- Более сложная сборка (multi-stage)
- Дольше собирается (скачивание + установка)
- Нужно вручную обновлять дистрибутивы

---

## Когда использовать какой вариант

### Используйте **Postgres Pro** (Dockerfile), если:

✅ Вам нужно **быстро** начать работу
✅ У вас **нет** ITS подписки
✅ Вам подходит PostgreSQL 16
✅ Вы хотите автоматические обновления
✅ Вы работаете с интернетом постоянно

**Команды:**
```bash
source .onec.env
docker-compose build postgres
docker-compose up -d postgres
```

---

### Используйте **PostgreSQL от 1С** (Dockerfile.1c), если:

✅ Вам нужна **конкретная версия** PostgreSQL
✅ У вас **есть** ITS подписка (ONEC_USERNAME/PASSWORD)
✅ Вы хотите **локальные дистрибутивы** (offline режим)
✅ Вы хотите **единый стиль** с остальным проектом
✅ Вам важна **официальная** поддержка от 1С
✅ Вы работаете в **корпоративной** среде с контролем версий

**Команды:**
```bash
# Вариант 1: Автоматическое скачивание
source .onec.env
export POSTGRES_VERSION=17.5-11.1C
./build-postgres-1c.sh

# Вариант 2: Локальный дистрибутив
# 1. Скачать с https://releases.1c.ru/version_files?nick=AddCompPostgre&ver=17.5-11.1C
# 2. Поместить в distr/
# 3. Запустить сборку
./build-postgres-1c.sh
```

---

## Рекомендации по выбору

### Для разработки и тестирования

**→ Используйте Postgres Pro (Dockerfile)**

Быстро, просто, не требует учетных данных. Идеально для локальной разработки.

### Для production и корпоративного использования

**→ Используйте PostgreSQL от 1С (Dockerfile.1c)**

Полный контроль версий, локальные дистрибутивы, официальная поддержка от 1С.

### Для CI/CD

**→ Postgres Pro** - если версия 16 подходит
**→ PostgreSQL от 1С** - если нужны специфичные версии или offline сборка

---

## Миграция между вариантами

### С Postgres Pro → PostgreSQL от 1С

```bash
# 1. Backup данных
docker-compose exec postgres pg_dumpall -U postgres > backup.sql

# 2. Остановить контейнер
docker-compose down

# 3. Удалить volume
docker volume rm onec-docker_postgres_data

# 4. Собрать PostgreSQL от 1С
export POSTGRES_VERSION=17.5-11.1C
./build-postgres-1c.sh

# 5. Обновить docker-compose.yml
#    image: ${DOCKER_REGISTRY_URL}/onec-postgres-1c:${POSTGRES_VERSION}

# 6. Запустить
docker-compose up -d postgres

# 7. Восстановить данные
cat backup.sql | docker-compose exec -T postgres psql -U postgres
```

### С PostgreSQL от 1С → Postgres Pro

```bash
# Аналогично, но:
# - docker-compose build postgres (вместо ./build-postgres-1c.sh)
# - В docker-compose.yml: image: ${DOCKER_REGISTRY_URL}/onec-postgres-pro:16
```

---

## Совместимость с 1С:Предприятие

**Оба варианта полностью совместимы** с 1С:Предприятие и включают необходимые расширения:

- ✅ **mchar** - типы данных MCHAR и MVARCHAR
- ✅ **fulleq** - оптимизация сравнения строк
- ✅ **fasttrun** - ускорение операций усечения

**Проверка расширений:**
```bash
docker exec -it onec-postgres psql -U postgres -c "\dx"
```

---

## Структура файлов проекта

```
postgres/
├── Dockerfile              ← Postgres Pro (простой)
├── Dockerfile.1c           ← PostgreSQL от 1С (полный)
├── docker-entrypoint.sh    ← Entrypoint для Postgres Pro
├── docker-entrypoint-1c.sh ← Entrypoint для PostgreSQL от 1С
├── README.md               ← Документация Postgres Pro
├── COMPARISON.md           ← Этот файл
├── MIGRATION.md            ← Инструкции по миграции
└── init-scripts/           ← Общие init скрипты

scripts/
├── download_postgres.sh    ← Скачивание PostgreSQL от 1С
└── install_postgres.sh     ← Установка PostgreSQL от 1С

Корень проекта:
├── build-postgres.sh       ← Сборка Postgres Pro
└── build-postgres-1c.sh    ← Сборка PostgreSQL от 1С
```

---

## FAQ

### Можно ли использовать оба варианта одновременно?

Да, но для разных контейнеров. Нельзя смешивать в одном контейнере.

### Какой вариант официально рекомендует 1С?

1С рекомендует свои дистрибутивы (Dockerfile.1c), но Postgres Pro также официально поддерживается.

### Можно ли обновить PostgreSQL без пересборки образа?

**Postgres Pro:** Да, через `apt upgrade` внутри контейнера
**PostgreSQL от 1С:** Нет, нужна пересборка с новым дистрибутивом

### Какие версии PostgreSQL доступны?

**Postgres Pro:** 16
**PostgreSQL от 1С:** Зависит от доступности на releases.1c.ru (обычно 10-17)

### Нужна ли лицензия для PostgreSQL?

Нет, PostgreSQL - свободное ПО. Но для скачивания дистрибутивов от 1С нужна ITS подписка.

---

## Дополнительная информация

- **Postgres Pro документация:** https://postgrespro.ru/docs/postgrespro/16/
- **1С + PostgreSQL:** https://1c.postgres.ru/
- **releases.1c.ru PostgreSQL:** https://releases.1c.ru/project/AddCompPostgre
- **Infostart PostgreSQL:** https://infostart.ru/1c/articles/1872745/

---

## Выводы

**Для большинства случаев:** Начните с **Postgres Pro** (быстро и просто)

**Для production:** Переходите на **PostgreSQL от 1С** (контроль и официальная поддержка)

**Оба варианта работают** и полностью совместимы с 1С:Предприятие! 🎉
