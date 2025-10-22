# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Обзор проекта

Репозиторий содержит конфигурации Docker для сборки образов с платформой 1С:Предприятие 8.3. Проект предоставляет контейнеризованные решения для различных компонентов 1С, включая серверы, клиенты, инструменты разработки и CI/CD агенты.

## Переменные окружения

Перед работой необходимо настроить переменные окружения:

```bash
# Для Linux
cp .onec.env.example .onec.env
source .onec.env

# Для Windows (GitBash)
copy .onec.env.bat.example env.bat
env.bat
```

Обязательные переменные:
- `ONEC_USERNAME` - учётная запись на http://releases.1c.ru
- `ONEC_PASSWORD` - пароль для учётной записи
- `ONEC_VERSION` - версия платформы 1С:Предприятие (формат: 8.3.x.xxxx)
- `DOCKER_REGISTRY_URL` - адрес Docker registry (примеры ниже)
- `EDT_VERSION` - версия EDT (для образов с EDT или замерами покрытия)
- `COVERAGE41C_VERSION` - версия Coverage41C (для coverage-агентов)
- `DEV1C_EXECUTOR_API_KEY` - токен API для скачивания 1С:Исполнитель
- `EXECUTOR_VERSION` - версия 1С:Исполнитель

### Настройка DOCKER_REGISTRY_URL

`DOCKER_REGISTRY_URL` - адрес хранилища Docker образов. Варианты значений:

**Для локальной работы без registry:**
```bash
export DOCKER_REGISTRY_URL=library
export DOCKER_LOGIN=
export DOCKER_PASSWORD=
```

**Для работы с Docker Hub:**
```bash
export DOCKER_REGISTRY_URL=docker.io/ваш_username
export DOCKER_LOGIN=ваш_username
export DOCKER_PASSWORD=ваш_пароль
```

**Для работы с приватным registry:**
```bash
export DOCKER_REGISTRY_URL=registry.mycompany.local:5000
export DOCKER_LOGIN=login
export DOCKER_PASSWORD=password
```

**Другие варианты:**
- GitLab: `registry.gitlab.com/username/project`
- GitHub: `ghcr.io/username`
- Azure: `myregistry.azurecr.io`
- AWS ECR: `123456789.dkr.ecr.us-east-1.amazonaws.com`

## Решение типичных проблем

### Проблема: "invalid tag" или "invalid reference format"

**Симптомы:**
```
ERROR: failed to build: invalid tag "/onec-server:": invalid reference format
```

**Причина:** Переменные окружения не загружены в текущую сессию терминала.

**Решение:**
```bash
# ВСЕГДА загружайте переменные перед сборкой
source .onec.env

# Проверьте, что переменные загружены
echo $ONEC_VERSION
echo $DOCKER_REGISTRY_URL

# Только после этого запускайте сборку
./build-server.sh
```

### Проблема: Docker login failed с DOCKER_REGISTRY_URL=library

**Симптомы:**
```
Error response from daemon: Get "https://library/v2/": ... no such host
Docker login failed
```

**Причина:** Значение `library` не является реальным Docker registry, а используется для локального хранения. Скрипт пытается выполнить `docker login` из-за заполненных `DOCKER_LOGIN` и `DOCKER_PASSWORD`.

**Решение:**
В файле `.onec.env` оставьте `DOCKER_LOGIN` и `DOCKER_PASSWORD` пустыми:
```bash
export DOCKER_REGISTRY_URL=library
export DOCKER_LOGIN=
export DOCKER_PASSWORD=
```

### Проблема: Docker push зависает или не выполняется

**Симптомы:**
Сборка завершается, но команда `docker push` зависает или выдает ошибку.

**Решение:**
Если работаете локально с `DOCKER_REGISTRY_URL=library`, это ожидаемое поведение. Образы создаются локально и не требуют push.

**Проверка созданных образов:**
```bash
docker images | grep onec
```

**Использование Makefile вместо скриптов** (без автоматического push):
```bash
source .onec.env
make server
make client
```

### Проблема: Отсутствуют BASE_IMAGE и BASE_TAG

**Симптомы:**
```
WARNING: Default value for ARG ${DOCKER_REGISTRY_URL}/${BASE_IMAGE}:${BASE_TAG} results in empty or invalid base image name
```

**Причина:** Некоторые Dockerfile требуют дополнительные аргументы для базового образа.

**Решение:**
Используйте готовые скрипты сборки вместо прямого вызова `docker build`:
```bash
# Правильно - используйте скрипты
./build-server.sh
./build-base-swarm-jenkins-agent.sh

# Неправильно - не хватает аргументов
docker build -f server/Dockerfile .
```

### Проблема: Ошибки скачивания дистрибутивов 1С

**Симптомы:**
Ошибки при скачивании с releases.1c.ru во время сборки образа.

**Решение 1 - Использование локальных дистрибутивов:**
1. Скачайте дистрибутивы вручную с https://releases.1c.ru
2. Поместите их в папку `distr/`
3. Скрипты автоматически обнаружат и используют локальные файлы

**Решение 2 - Проверка учетных данных:**
```bash
# Убедитесь, что логин и пароль корректны
echo $ONEC_USERNAME
echo $ONEC_PASSWORD
```

## Команды сборки

### Использование готовых дистрибутивов

Размещайте готовые дистрибутивы платформы в папке `distr/` - скрипты будут использовать их автоматически.

### Базовые образы (отдельные компоненты)

Используйте Makefile для сборки отдельных образов:

```bash
# Серверные компоненты
make server              # Сервер 1С
make server-nls         # Сервер с дополнительными языками
make crs                # Хранилище конфигурации

# Клиентские компоненты
make client             # Толстый клиент
make client-vnc         # Клиент с поддержкой VNC
make client-nls         # Клиент с дополнительными языками
make thin-client        # Тонкий клиент
make thin-client-nls    # Тонкий клиент с доп. языками

# Инструменты разработки
make oscript            # OneScript
make runner             # Vanessa Runner
make rac-gui            # RAC GUI
make gitsync            # GitSync

# Сборка EDT (только через скрипт)
./build-edt.sh

# Сборка 1С:Исполнитель (только через скрипт с безопасным пробросом секретов)
./build-executor.sh
```

### Jenkins агенты для CI/CD

#### Docker Swarm агенты

```bash
# Базовый агент
./build-base-swarm-jenkins-agent.sh

# Агент с замерами покрытия
./build-base-swarm-jenkins-coverage-agent.sh

# EDT агент для Swarm
./build-edt-swarm-agent.sh

# OneScript агент для Swarm
./build-oscript-swarm-agent.sh
```

#### Kubernetes агенты

```bash
# Базовый агент для k8s
./build-base-k8s-jenkins-agent.sh

# Агент с замерами покрытия для k8s
./build-base-k8s-jenkins-coverage-agent.sh

# EDT агент для k8s
./build-edt-k8s-agent.sh

# OneScript агент для k8s
./build-oscript-k8s-agent.sh
```

## Архитектура проекта

### Многослойная архитектура образов

Проект использует паттерн "наслаивания" образов друг на друга через переопределение аргументов сборки `BASE_IMAGE` и `BASE_TAG`. Последовательность сборки для различных целей описана в `Layers.md`.

Типичная последовательность наслаивания:
1. `client` или `client-vnc` (базовый слой с 1С)
2. `oscript` (добавление OneScript)
3. `jdk` (добавление Java)
4. `test-utils` (добавление инструментов тестирования)
5. `jenkins-agent` (финальный слой для CI/CD)

### Структура директорий

```
onec-docker/
├── client/              # Толстый клиент 1С
├── client-vnc/          # Клиент с VNC
├── server/              # Сервер 1С
├── thin-client/         # Тонкий клиент
├── crs/                 # Хранилище конфигурации
├── crs-apache/          # Хранилище с Apache
├── edt/                 # Enterprise Development Tools
├── executor/            # 1С:Исполнитель
├── oscript/             # OneScript runtime
├── oscript-utils/       # Утилиты OneScript
├── vanessa-runner/      # Фреймворк тестирования
├── test-utils/          # Утилиты тестирования
├── jdk/                 # Java Development Kit
├── jenkins-agent/       # Базовый Jenkins агент
├── k8s-jenkins-agent/   # Jenkins агент для Kubernetes
├── swarm-jenkins-agent/ # Jenkins агент для Docker Swarm
├── coverage41C/         # Инструменты замера покрытия
├── rac-gui/             # RAC графический интерфейс
├── gitsync/             # Синхронизация с Git
├── scripts/             # Вспомогательные скрипты
│   ├── download_yard.sh          # Скачивание через yard
│   ├── download_og.sh            # Скачивание через OneGet
│   ├── install_new.sh            # Установка 1С
│   ├── install.sh                # Установка (старый)
│   ├── create-symlink-to-current-1cv8.sh  # Создание симлинка
│   └── remove-dst-root-ca-x3.sh  # Удаление устаревшего CA
├── distr/               # Локальные дистрибутивы (не в git)
└── configs/             # Конфигурационные файлы
```

### Паттерны Dockerfile

1. **Multi-stage builds**: Используются для загрузки/сборки зависимостей
   - Стадия `downloader`: скачивание дистрибутивов 1С
   - Стадия `base`: установка и настройка
   - Финальная стадия: минимальный образ с необходимыми компонентами

2. **Стандартные build arguments**:
   ```dockerfile
   ARG DOCKER_REGISTRY_URL
   ARG BASE_IMAGE
   ARG BASE_TAG
   ARG ONEC_USERNAME
   ARG ONEC_PASSWORD
   ARG ONEC_VERSION
   ```

3. **Базовый образ через registry**:
   ```dockerfile
   FROM ${DOCKER_REGISTRY_URL}/${BASE_IMAGE}:${BASE_TAG}
   ```

### Скрипты загрузки дистрибутивов

- `download_yard.sh` - использует yard (OneScript) для загрузки через releases.1c.ru
- `download_og.sh` - использует oneget для загрузки
- Скрипты автоматически проверяют наличие локальных дистрибутивов в `/distr`

### Локализация и языки

- Базовая локаль: `ru_RU.UTF-8`
- Для многоязычной поддержки используйте `--build-arg nls_enabled=true`
- Документация и комментарии преимущественно на русском языке

## Особенности работы с 1С:Предприятие

### Версионирование

- Версии 1С следуют паттерну: `8.3.x.xxxx` (например, 8.3.18.1520)
- Различные компоненты могут требовать разные версии
- Проверяйте совместимость версий при обновлении

### Компоненты платформы

- **Server** (`rpms-64`, `server-nls-64`): серверная часть СУБД
- **Client** (`client-64`, `client-nls-64`): толстый клиент
- **Thin Client** (`thin-client-64`, `thin-client-nls-64`): тонкий клиент
- **CRS**: сервер хранилища конфигурации
- **RAC**: консоль удалённого администрирования

### Стандартные пути 1С

- `/opt/1cv8/` - установка платформы
- `/opt/1cv8/current/` - симлинк на текущую версию
- `/home/usr1cv8/.1cv8/` - пользовательские данные (volume)
- `/var/1cv8/` - данные сервера

### Пользователь и группа

- Пользователь: `usr1cv8` (UID: 999)
- Группа: `grp1cv8` (GID: 999)

## Использование nethasp.ini в Jenkins + Docker Swarm

Для работы с лицензиями HASP:

```bash
# Создать Docker config из файла nethasp.ini
docker config create nethasp.ini ./nethasp.ini

# В Jenkins настройках Docker Agent templates указать в параметре Configs:
# nethasp.ini:/opt/1cv8/current/conf/nethasp.ini
```

## PostgreSQL + pgAdmin

Проект использует официальные Docker образы PostgreSQL и pgAdmin для управления базами данных.

### Компоненты

- **PostgreSQL 16 (Alpine)**: `postgres:16-alpine` (~230 MB)
- **pgAdmin 4**: `dpage/pgadmin4:latest` (~450 MB)

### Быстрый старт

```bash
# Запустить PostgreSQL + pgAdmin
docker-compose up -d postgres pgadmin

# Доступ к pgAdmin: http://localhost:5050
# Email: admin@example.com (см. .onec.env)
# Password: admin_strong_password (см. .onec.env)
```

### Подключение из 1С:Предприятие

```
Сервер СУБД: postgres
Порт: 5432
База данных: onec_db (создаётся автоматически из init-scripts)
Пользователь: usr1cv8
Пароль: changeme_1c_password
```

### Настройка для 1С

PostgreSQL настроен с учётом требований 1С:Предприятие:
- Кодировка: UTF-8
- Локаль: ru_RU.UTF-8
- Аутентификация: scram-sha-256
- Оптимизация shared_buffers и work_mem

### Управление данными

```bash
# Бэкап
docker-compose exec postgres pg_dump -U postgres onec_db > backup.sql

# Восстановление
cat backup.sql | docker-compose exec -T postgres psql -U postgres onec_db
```

См. подробнее: [postgres/README.md](postgres/README.md)

## Безопасность

- **НИКОГДА** не коммитьте учётные данные (ONEC_USERNAME, ONEC_PASSWORD, токены API)
- Используйте build arguments для передачи секретов при сборке
- Для `build-executor.sh` используйте только скрипт (безопасный проброс секретов)
- Предоставляйте примеры конфигов с суффиксом `.example`

## Управление скриптами сборки

### Опции скриптов сборки

- `NO_CACHE=true` - сборка без использования кэша
- `DOCKER_SYSTEM_PRUNE=true` - очистка системы перед сборкой
- `PUSH_AGENT=false` - не отправлять образ агента в registry
- Скрипты автоматически выполняют `docker login` если заданы переменные `DOCKER_LOGIN` и `DOCKER_PASSWORD`

### Порядок выполнения build-скриптов

Скрипты автоматически собирают цепочку зависимых образов:
1. Базовый образ с необходимыми компонентами
2. Промежуточные слои (oscript, jdk, test-utils)
3. Финальный образ (jenkins-agent)

## Тестирование и отладка

### Запуск через docker-compose

```bash
docker-compose up
```

### VNC подключение

Образы с суффиксом `-vnc` поддерживают VNC для GUI доступа к 1С клиенту.

### Проверка сборки

После сборки проверьте:
- Корректность версии 1С: `/opt/1cv8/current/1cv8 --version`
- Наличие необходимых компонентов
- Работу локали: `locale`

### Запуск собранных образов

**Сервер 1С:**
```bash
docker run -d \
  -p 1540-1541:1540-1541 \
  -p 1545:1545 \
  -v onec-server-data:/home/usr1cv8/.1cv8 \
  -v onec-server-logs:/var/log/1C \
  --name onec-server \
  library/onec-server:8.3.27.1786
```

**Клиент 1С с VNC:**
```bash
docker run -d \
  -p 5900:5900 \
  -v onec-client-data:/home/usr1cv8/.1cv8 \
  --name onec-client-vnc \
  library/onec-client-vnc:8.3.27.1786
```

**Хранилище конфигурации:**
```bash
docker run -d \
  -p 1542:1542 \
  -v onec-crs-data:/home/usr1cv8/.1cv8 \
  --name onec-crs \
  library/onec-crs:8.3.27.1786
```

## Примечания к разработке

- Сохраняйте билингвальность: русский для 1С-специфики, английский для общих концепций
- Следуйте паттернам именования образов: `${DOCKER_REGISTRY_URL}/onec-<component>:${VERSION}`
- Тегируйте образы как конкретной версией, так и `latest`
- Минимизируйте количество слоёв в Dockerfile (объединяйте RUN команды)
- Документируйте требуемые volumes и порты
- Используйте `.PHONY` в Makefile для всех targets
