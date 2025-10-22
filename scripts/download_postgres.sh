#!/bin/bash

# Скрипт скачивания PostgreSQL от 1С
# Использует yard для скачивания с releases.1c.ru
# Поддерживает локальные дистрибутивы из папки distr/

# Аргументы скрипта
ONEC_USERNAME=$1
ONEC_PASSWORD=$2
POSTGRES_VERSION=$3  # Формат: 17.5-11.1C

# Преобразование версии
POSTGRES_VERSION_DOTS=$POSTGRES_VERSION
POSTGRES_VERSION_UNDERSCORES=$(echo $POSTGRES_VERSION_DOTS | sed 's/[\.\-]/\_/g')
ESCAPED_VERSION=$(echo $POSTGRES_VERSION_DOTS | sed 's/[\.\-]/\\&/g')

FOLDER_NAME="AddCompPostgre"
DOWNLOADS_PATH=/tmp/downloads/${FOLDER_NAME}/${POSTGRES_VERSION}

echo "==========================================="
echo "Скачивание PostgreSQL для 1С:Предприятие"
echo "==========================================="
echo "Версия: $POSTGRES_VERSION"
echo "Путь загрузки: $DOWNLOADS_PATH"
echo "==========================================="

# Функция поиска локального дистрибутива
copy_local_distr() {
  found=1

  # Возможные имена файлов PostgreSQL от 1С
  # Примеры:
  # - postgresql_17.5-11.1C_amd64.deb.tar.gz
  # - AddCompPostgre_17_5_11_1C_Linux.tar.gz
  # - postgres-17.5-11.1C-linux-x64.tar.gz

  local patterns=(
    "postgresql*${POSTGRES_VERSION}*.tar.gz"
    "AddCompPostgre*${POSTGRES_VERSION}*.tar.gz"
    "postgres*${POSTGRES_VERSION}*.tar.gz"
    "postgresql*${POSTGRES_VERSION_UNDERSCORES}*.tar.gz"
    "AddCompPostgre*${POSTGRES_VERSION_UNDERSCORES}*.tar.gz"
  )

  for pattern in "${patterns[@]}"; do
    local matching_files=($(ls /distr/$pattern 2> /dev/null))
    if [ ${#matching_files[@]} -gt 0 ]; then
      local found_file=${matching_files[0]}
      echo "✅ Найден локальный дистрибутив: $(basename $found_file)"
      cp "$found_file" $DOWNLOADS_PATH/
      found=0
      break
    fi
  done

  if [ $found -eq 0 ]; then
    # Распаковка архива
    for file in $DOWNLOADS_PATH/*.tar.gz; do
      echo "📦 Распаковка: $(basename $file)"
      tar -xzf "$file" -C $DOWNLOADS_PATH
      rm -f "$file"
    done
  else
    echo "ℹ️  Локальный дистрибутив не найден в папке /distr"
  fi

  return $found
}

# Функция проверки наличия файлов после скачивания
check_files() {
  found=1

  # Проверяем наличие .deb файлов PostgreSQL
  if ls $DOWNLOADS_PATH/*.deb 1> /dev/null 2>&1; then
    echo "✅ Найдены .deb пакеты PostgreSQL"
    ls -lh $DOWNLOADS_PATH/*.deb
    found=0
  else
    echo "❌ .deb пакеты не найдены"
    echo "Содержимое каталога $DOWNLOADS_PATH:"
    ls -la $DOWNLOADS_PATH
  fi

  return $found
}

# Функция скачивания через yard
download_with_yard() {
  echo ""
  echo "📥 Попытка скачивания через yard..."

  # Фильтры для скачивания PostgreSQL от 1С
  # Примеры названий дистрибутивов на releases.1c.ru:
  # - "Дистрибутив СУБД PostgreSQL для Linux x86 (64-bit) одним архивом (DEB)"
  # - "PostgreSQL для Linux (DEB)"

  local APP_FILTER="Дополнительные компоненты для 1С:Предприятия 8"
  local DISTR_FILTERS=(
    "Дистрибутив СУБД PostgreSQL .* Linux .* \(DEB\)"
    "PostgreSQL .* Linux .* DEB"
    "СУБД PostgreSQL .* Linux"
  )

  for filter in "${DISTR_FILTERS[@]}"; do
    echo "Попытка с фильтром: $filter"

    yard releases -u "$ONEC_USERNAME" -p "$ONEC_PASSWORD" get \
      --nick "AddCompPostgre" \
      --version-filter "$ESCAPED_VERSION" \
      --path /tmp/downloads \
      --distr-filter "$filter" \
      --download-limit 1

    check_files
    local download_success=$?

    if [ $download_success -eq 0 ]; then
      echo "✅ Скачивание успешно завершено"
      return 0
    fi
  done

  echo "❌ Не удалось скачать дистрибутив ни с одним фильтром"
  return 1
}

# Основная логика
main() {
  # Создание директории для загрузок
  mkdir -p $DOWNLOADS_PATH
  rm -f $DOWNLOADS_PATH/.gitkeep
  chmod 777 -R /tmp

  # Сначала ищем локально
  copy_local_distr
  local local_found=$?

  if [ $local_found -eq 0 ]; then
    check_files
    local check_result=$?

    if [ $check_result -eq 0 ]; then
      echo ""
      echo "✅ Дистрибутив готов к установке"
      echo "Путь: $DOWNLOADS_PATH"
      return 0
    fi
  fi

  # Если локально не нашли - скачиваем
  if [ -z "$ONEC_USERNAME" ] || [ -z "$ONEC_PASSWORD" ]; then
    echo ""
    echo "❌ Ошибка: Не заданы учетные данные для releases.1c.ru"
    echo "Установите ONEC_USERNAME и ONEC_PASSWORD"
    echo "Или поместите дистрибутив в папку distr/"
    exit 1
  fi

  download_with_yard
  local download_result=$?

  if [ $download_result -ne 0 ]; then
    echo ""
    echo "❌ ОШИБКА: Не удалось найти дистрибутив PostgreSQL"
    echo ""
    echo "Возможные решения:"
    echo "1. Скачайте дистрибутив вручную:"
    echo "   https://releases.1c.ru/version_files?nick=AddCompPostgre&ver=${POSTGRES_VERSION}"
    echo "2. Поместите архив в папку distr/"
    echo "3. Проверьте версию: $POSTGRES_VERSION"
    echo "4. Проверьте учетные данные ONEC_USERNAME/ONEC_PASSWORD"
    exit 1
  fi

  echo ""
  echo "✅ Дистрибутив успешно подготовлен"
  return 0
}

# Запуск
main
