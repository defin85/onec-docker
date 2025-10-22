#!/bin/bash

# Скрипт установки PostgreSQL от 1С из .deb пакетов
# Устанавливает пакеты в правильном порядке с учетом зависимостей

set -e

POSTGRES_VERSION=$1
DOWNLOADS_PATH=/tmp/downloads/AddCompPostgre/${POSTGRES_VERSION}

echo "==========================================="
echo "Установка PostgreSQL для 1С:Предприятие"
echo "==========================================="
echo "Версия: $POSTGRES_VERSION"
echo "Путь: $DOWNLOADS_PATH"
echo "==========================================="

cd "$DOWNLOADS_PATH"

# Проверка наличия пакетов
if ! ls *.deb 1> /dev/null 2>&1; then
    echo "❌ Ошибка: .deb пакеты не найдены в $DOWNLOADS_PATH"
    exit 1
fi

echo ""
echo "📦 Найденные пакеты:"
ls -1 *.deb

# Порядок установки PostgreSQL от 1С:
# 1. libpq5 (библиотеки PostgreSQL)
# 2. postgresql-client-XX (клиент PostgreSQL)
# 3. postgresql-XX (сервер PostgreSQL)
# 4. postgresql-contrib-XX (дополнительные модули, включая mchar, fulleq, fasttrun)

echo ""
echo "🔧 Установка пакетов в правильном порядке..."

# Функция установки пакета
install_package() {
    local pattern=$1
    local description=$2

    local packages=($(ls $pattern 2>/dev/null | sort))

    if [ ${#packages[@]} -eq 0 ]; then
        echo "⚠️  Пакет не найден: $pattern"
        return 1
    fi

    for pkg in "${packages[@]}"; do
        echo ""
        echo "📦 Установка: $(basename $pkg)"
        echo "   Описание: $description"
        dpkg -i "$pkg" || apt-get -f install -y
    done

    return 0
}

# 1. Установка libpq
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Шаг 1/4: Установка библиотек libpq"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
install_package "libpq*.deb" "PostgreSQL C client library"

# 2. Установка postgresql-common (если есть)
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Шаг 2/4: Установка postgresql-common"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
install_package "postgresql-common*.deb" "PostgreSQL common files" || echo "ℹ️  Пропущено (пакет отсутствует)"

# 3. Установка postgresql-client
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Шаг 3/4: Установка клиента PostgreSQL"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
install_package "postgresql-client-*.deb" "PostgreSQL client"

# 4. Установка postgresql-server
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Шаг 4/4: Установка сервера PostgreSQL"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
install_package "postgresql-[0-9]*.deb" "PostgreSQL server"

# 5. Установка postgresql-contrib (расширения для 1С)
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Дополнительно: Установка расширений (mchar, fulleq, fasttrun)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
install_package "postgresql-contrib-*.deb" "PostgreSQL contrib modules (includes 1C extensions)" || echo "⚠️  Расширения могут быть включены в основной пакет"

# 6. Исправление зависимостей (если были проблемы)
echo ""
echo "🔧 Проверка и исправление зависимостей..."
apt-get -f install -y

# 7. Проверка установки
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Проверка установки"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Поиск установленной версии PostgreSQL
PG_VERSION=$(ls -d /usr/lib/postgresql/*/ 2>/dev/null | head -1 | xargs basename)

if [ -z "$PG_VERSION" ]; then
    echo "⚠️  Внимание: Не удалось определить версию PostgreSQL"
    echo "Установленные пакеты:"
    dpkg -l | grep postgresql
else
    echo "✅ PostgreSQL версия: $PG_VERSION"
    echo "📂 Путь установки: /usr/lib/postgresql/$PG_VERSION/"

    # Проверка наличия исполняемых файлов
    if [ -f "/usr/lib/postgresql/$PG_VERSION/bin/postgres" ]; then
        echo "✅ Сервер: /usr/lib/postgresql/$PG_VERSION/bin/postgres"
    fi

    if [ -f "/usr/lib/postgresql/$PG_VERSION/bin/psql" ]; then
        echo "✅ Клиент: /usr/lib/postgresql/$PG_VERSION/bin/psql"
    fi

    # Проверка расширений для 1С
    local extensions_path="/usr/lib/postgresql/$PG_VERSION/lib"
    echo ""
    echo "🔍 Проверка расширений для 1С:"

    if [ -f "$extensions_path/mchar.so" ]; then
        echo "   ✅ mchar.so найден"
    else
        echo "   ⚠️  mchar.so не найден"
    fi

    if [ -f "$extensions_path/fulleq.so" ]; then
        echo "   ✅ fulleq.so найден"
    else
        echo "   ⚠️  fulleq.so не найден"
    fi

    if [ -f "$extensions_path/fasttrun.so" ]; then
        echo "   ✅ fasttrun.so найден"
    else
        echo "   ⚠️  fasttrun.so не найден"
    fi
fi

echo ""
echo "==========================================="
echo "✅ Установка PostgreSQL завершена"
echo "==========================================="
