#!/bin/bash

# Скрипт сборки Docker образа PostgreSQL Pro 16 для 1С:Предприятие
# Включает расширения mchar, fulleq, fasttrun

set -e

# Загрузка переменных окружения
if [ -f .onec.env ]; then
    source .onec.env
fi

# Проверка обязательных переменных
: "${DOCKER_REGISTRY_URL:?Переменная DOCKER_REGISTRY_URL не установлена}"

# Опции сборки
NO_CACHE=${NO_CACHE:-false}
DOCKER_SYSTEM_PRUNE=${DOCKER_SYSTEM_PRUNE:-false}

# Версия PostgreSQL Pro
POSTGRES_PRO_VERSION=${POSTGRES_PRO_VERSION:-16}

# Имя образа
IMAGE_NAME="${DOCKER_REGISTRY_URL}/onec-postgres-pro"
IMAGE_TAG="${POSTGRES_PRO_VERSION}"

echo "============================================"
echo "Сборка PostgreSQL Pro для 1С:Предприятие"
echo "============================================"
echo "Образ: ${IMAGE_NAME}:${IMAGE_TAG}"
echo "Реестр: ${DOCKER_REGISTRY_URL}"
echo "============================================"

# Очистка системы Docker (опционально)
if [ "$DOCKER_SYSTEM_PRUNE" = "true" ]; then
    echo "🧹 Очистка системы Docker..."
    docker system prune -af --volumes
fi

# Параметры сборки
BUILD_ARGS=(
    "--file" "postgres/Dockerfile"
    "--tag" "${IMAGE_NAME}:${IMAGE_TAG}"
    "--tag" "${IMAGE_NAME}:latest"
)

# Добавление флага no-cache
if [ "$NO_CACHE" = "true" ]; then
    BUILD_ARGS+=("--no-cache")
fi

# Сборка образа
echo "🔨 Сборка образа..."
docker build "${BUILD_ARGS[@]}" postgres/

echo ""
echo "✅ Образ успешно собран!"
echo ""
echo "Проверка образа:"
docker images | grep onec-postgres-pro

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
echo "Сборка завершена!"
echo "============================================"
echo "Использование:"
echo "  docker run -d -p 5432:5432 \\"
echo "    -e POSTGRES_PASSWORD=changeme \\"
echo "    -v postgres_data:/var/lib/postgresql/data \\"
echo "    ${IMAGE_NAME}:${IMAGE_TAG}"
echo ""
