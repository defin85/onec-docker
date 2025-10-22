#!/bin/bash

# Скрипт сборки Docker образа PostgreSQL от 1С для 1С:Предприятие
# Использует официальные дистрибутивы с releases.1c.ru
# Включает расширения mchar, fulleq, fasttrun

set -e

# Загрузка переменных окружения
if [ -f .onec.env ]; then
    source .onec.env
fi

# Проверка обязательных переменных
: "${DOCKER_REGISTRY_URL:?Переменная DOCKER_REGISTRY_URL не установлена}"
: "${POSTGRES_VERSION:?Переменная POSTGRES_VERSION не установлена}"

# Опции сборки
NO_CACHE=${NO_CACHE:-false}
DOCKER_SYSTEM_PRUNE=${DOCKER_SYSTEM_PRUNE:-false}

# Имя образа
IMAGE_NAME="${DOCKER_REGISTRY_URL}/onec-postgres-1c"
IMAGE_TAG="${POSTGRES_VERSION}"

echo "============================================"
echo "Сборка PostgreSQL от 1С для 1С:Предприятие"
echo "============================================"
echo "Образ: ${IMAGE_NAME}:${IMAGE_TAG}"
echo "Реестр: ${DOCKER_REGISTRY_URL}"
echo "Версия PostgreSQL: ${POSTGRES_VERSION}"
echo "============================================"

# Информация о дистрибутивах
echo ""
echo "ℹ️  Способы получения дистрибутива:"
echo "   1. Автоматически с releases.1c.ru (требуется ONEC_USERNAME/PASSWORD)"
echo "   2. Вручную поместить в папку distr/"
echo ""
echo "📥 Ссылка для скачивания:"
echo "   https://releases.1c.ru/version_files?nick=AddCompPostgre&ver=${POSTGRES_VERSION}"
echo ""

# Проверка локального дистрибутива
if ls distr/postgresql*${POSTGRES_VERSION}*.tar.gz 2>/dev/null || \
   ls distr/AddCompPostgre*${POSTGRES_VERSION}*.tar.gz 2>/dev/null || \
   ls distr/postgres*${POSTGRES_VERSION}*.tar.gz 2>/dev/null; then
    echo "✅ Найден локальный дистрибутив в папке distr/"
else
    echo "⚠️  Локальный дистрибутив не найден"
    if [ -z "$ONEC_USERNAME" ] || [ -z "$ONEC_PASSWORD" ]; then
        echo ""
        echo "❌ Ошибка: Не заданы учетные данные для releases.1c.ru"
        echo ""
        echo "Решение:"
        echo "1. Установите переменные: ONEC_USERNAME, ONEC_PASSWORD"
        echo "   export ONEC_USERNAME=ваш_логин"
        echo "   export ONEC_PASSWORD=ваш_пароль"
        echo ""
        echo "2. Или скачайте дистрибутив вручную:"
        echo "   https://releases.1c.ru/version_files?nick=AddCompPostgre&ver=${POSTGRES_VERSION}"
        echo "   И поместите в папку distr/"
        exit 1
    else
        echo "✅ Будет использовано автоматическое скачивание"
    fi
fi

# Очистка системы Docker (опционально)
if [ "$DOCKER_SYSTEM_PRUNE" = "true" ]; then
    echo ""
    echo "🧹 Очистка системы Docker..."
    docker system prune -af --volumes
fi

# Сборка базового образа (если еще не собран)
echo ""
echo "🔍 Проверка базового образа onec-client..."
if ! docker images "${DOCKER_REGISTRY_URL}/onec-client:${ONEC_VERSION}" | grep -q onec-client; then
    echo "⚠️  Базовый образ не найден. Сборка onec-client..."
    make client
fi

# Параметры сборки
BUILD_ARGS=(
    "--file" "postgres/Dockerfile.1c"
    "--tag" "${IMAGE_NAME}:${IMAGE_TAG}"
    "--tag" "${IMAGE_NAME}:latest"
    "--build-arg" "DOCKER_REGISTRY_URL=${DOCKER_REGISTRY_URL}"
    "--build-arg" "BASE_IMAGE=onec-client"
    "--build-arg" "BASE_TAG=${ONEC_VERSION}"
    "--build-arg" "POSTGRES_VERSION=${POSTGRES_VERSION}"
)

# Добавление учетных данных (если заданы)
if [ -n "$ONEC_USERNAME" ]; then
    BUILD_ARGS+=("--build-arg" "ONEC_USERNAME=${ONEC_USERNAME}")
fi

if [ -n "$ONEC_PASSWORD" ]; then
    BUILD_ARGS+=("--build-arg" "ONEC_PASSWORD=${ONEC_PASSWORD}")
fi

# Добавление флага no-cache
if [ "$NO_CACHE" = "true" ]; then
    BUILD_ARGS+=("--no-cache")
fi

# Сборка образа
echo ""
echo "🔨 Сборка образа PostgreSQL от 1С..."
docker build "${BUILD_ARGS[@]}" .

echo ""
echo "✅ Образ успешно собран!"
echo ""
echo "Проверка образа:"
docker images | grep onec-postgres-1c

# Docker login (если заданы учетные данные)
if [ -n "${DOCKER_LOGIN}" ] && [ -n "${DOCKER_PASSWORD}" ]; then
    echo ""
    echo "🔐 Выполнение docker login..."
    echo "${DOCKER_PASSWORD}" | docker login -u "${DOCKER_LOGIN}" --password-stdin "${DOCKER_REGISTRY_URL}"

    # Push образа
    echo "📤 Отправка образа в registry..."
    docker push "${IMAGE_NAME}:${IMAGE_TAG}"
    docker push "${IMAGE_NAME}:latest"

    echo "✅ Образ отправлен в registry!"
else
    echo ""
    echo "ℹ️  Docker login не выполнен (DOCKER_LOGIN/DOCKER_PASSWORD не заданы)"
    echo "ℹ️  Образ доступен только локально"
fi

echo ""
echo "============================================"
echo "✅ Сборка завершена!"
echo "============================================"
echo ""
echo "Использование:"
echo "  docker run -d -p 5432:5432 \\"
echo "    -e POSTGRES_PASSWORD=changeme \\"
echo "    -v postgres_data:/var/lib/postgresql/data \\"
echo "    ${IMAGE_NAME}:${IMAGE_TAG}"
echo ""
echo "Проверка расширений:"
echo "  docker exec -it контейнер psql -U postgres -c '\dx'"
echo ""
echo "Должны быть расширения:"
echo "  - mchar (MCHAR and MVARCHAR types)"
echo "  - fulleq (Full text equality operator)"
echo "  - fasttrun (Fast truncate)"
echo ""
