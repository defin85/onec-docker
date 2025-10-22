#!/usr/bin/env bash
set -Eeo pipefail

# Docker entrypoint для PostgreSQL от 1С
# Поддерживает автоматическое создание расширений mchar, fulleq, fasttrun

# Загрузка версии PostgreSQL
if [ -f /etc/pg_version.env ]; then
    . /etc/pg_version.env
    export PATH="/usr/lib/postgresql/$PG_MAJOR/bin:$PATH"
else
    # Попытка автоопределения
    PG_MAJOR=$(ls -d /usr/lib/postgresql/*/ 2>/dev/null | head -1 | xargs basename)
    if [ -n "$PG_MAJOR" ]; then
        export PATH="/usr/lib/postgresql/$PG_MAJOR/bin:$PATH"
    fi
fi

# usage: file_env VAR [DEFAULT]
file_env() {
	local var="$1"
	local fileVar="${var}_FILE"
	local def="${2:-}"
	if [ "${!var:-}" ] && [ "${!fileVar:-}" ]; then
		echo >&2 "error: both $var and $fileVar are set (but are exclusive)"
		exit 1
	fi
	local val="$def"
	if [ "${!var:-}" ]; then
		val="${!var}"
	elif [ "${!fileVar:-}" ]; then
		val="$(< "${!fileVar}")"
	fi
	export "$var"="$val"
	unset "$fileVar"
}

_is_sourced() {
	[ "${#BASH_SOURCE[@]}" -gt 1 ]
}

docker_create_db_directories() {
	local user; user="$(id -u)"

	mkdir -p "$PGDATA"
	chmod 700 "$PGDATA"

	mkdir -p /var/run/postgresql || :
	chmod 775 /var/run/postgresql || :

	if [ -n "$POSTGRES_INITDB_WALDIR" ]; then
		mkdir -p "$POSTGRES_INITDB_WALDIR"
		if [ "$user" = '0' ]; then
			find "$POSTGRES_INITDB_WALDIR" \! -user postgres -exec chown postgres '{}' +
		fi
		chmod 700 "$POSTGRES_INITDB_WALDIR"
	fi

	if [ "$user" = '0' ]; then
		find "$PGDATA" \! -user postgres -exec chown postgres '{}' +
		find /var/run/postgresql \! -user postgres -exec chown postgres '{}' +
	fi
}

docker_init_database_dir() {
	if ! getent passwd "$(id -u)" &> /dev/null && [ -e /usr/lib/libnss_wrapper.so ]; then
		export LD_PRELOAD='/usr/lib/libnss_wrapper.so'
		export NSS_WRAPPER_PASSWD="$(mktemp)"
		export NSS_WRAPPER_GROUP="$(mktemp)"
		echo "postgres:x:$(id -u):$(id -g):PostgreSQL:$PGDATA:/bin/false" > "$NSS_WRAPPER_PASSWD"
		echo "postgres:x:$(id -g):" > "$NSS_WRAPPER_GROUP"
	fi

	if [ -n "$POSTGRES_INITDB_WALDIR" ]; then
		set -- --waldir "$POSTGRES_INITDB_WALDIR" "$@"
	fi

	eval 'initdb --username="$POSTGRES_USER" --pwfile=<(echo "$POSTGRES_PASSWORD") '"$POSTGRES_INITDB_ARGS"' "$@"'

	if [ "${LD_PRELOAD:-}" = '/usr/lib/libnss_wrapper.so' ]; then
		rm -f "$NSS_WRAPPER_PASSWD" "$NSS_WRAPPER_GROUP"
		unset LD_PRELOAD NSS_WRAPPER_PASSWD NSS_WRAPPER_GROUP
	fi
}

docker_verify_minimum_env() {
	if [ "${#POSTGRES_PASSWORD}" -ge 100 ]; then
		cat >&2 <<-'EOWARN'

			WARNING: The supplied POSTGRES_PASSWORD is 100+ characters.
			This will not work if used via PGPASSWORD with "psql".

		EOWARN
	fi
	if [ -z "$POSTGRES_PASSWORD" ] && [ 'trust' != "$POSTGRES_HOST_AUTH_METHOD" ]; then
		cat >&2 <<-'EOE'
			Error: Database is uninitialized and superuser password is not specified.
			       You must specify POSTGRES_PASSWORD to a non-empty value for the
			       superuser. For example, "-e POSTGRES_PASSWORD=password" on "docker run".

			       You may also use "POSTGRES_HOST_AUTH_METHOD=trust" to allow all
			       connections without a password. This is *not* recommended.
		EOE
		exit 1
	fi
	if [ 'trust' = "$POSTGRES_HOST_AUTH_METHOD" ]; then
		cat >&2 <<-'EOWARN'
			********************************************************************************
			WARNING: POSTGRES_HOST_AUTH_METHOD has been set to "trust". This will allow
			         anyone with access to the Postgres port to access your database without
			         a password, even if POSTGRES_PASSWORD is set.
			********************************************************************************
		EOWARN
	fi
}

docker_process_init_files() {
	psql=( docker_process_sql )

	echo
	local f
	for f; do
		case "$f" in
			*.sh)
				if [ -x "$f" ]; then
					echo "$0: running $f"
					"$f"
				else
					echo "$0: sourcing $f"
					. "$f"
				fi
				;;
			*.sql)     echo "$0: running $f"; docker_process_sql -f "$f"; echo ;;
			*.sql.gz)  echo "$0: running $f"; gunzip -c "$f" | docker_process_sql; echo ;;
			*.sql.xz)  echo "$0: running $f"; xzcat "$f" | docker_process_sql; echo ;;
			*.sql.zst) echo "$0: running $f"; zstd -dc "$f" | docker_process_sql; echo ;;
			*)         echo "$0: ignoring $f" ;;
		esac
		echo
	done
}

docker_process_sql() {
	local query_runner=( psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --no-password )
	if [ -n "$POSTGRES_DB" ]; then
		query_runner+=( --dbname "$POSTGRES_DB" )
	fi

	"${query_runner[@]}" "$@"
}

docker_setup_db() {
	local dbAlreadyExists
	dbAlreadyExists="$(
		POSTGRES_DB= docker_process_sql --dbname postgres --set db="$POSTGRES_DB" --tuples-only <<-'EOSQL'
			SELECT 1 FROM pg_database WHERE datname = :'db' ;
		EOSQL
	)"
	if [ -z "$dbAlreadyExists" ]; then
		POSTGRES_DB= docker_process_sql --dbname postgres --set db="$POSTGRES_DB" <<-'EOSQL'
			CREATE DATABASE :"db" ;
		EOSQL
		echo
	fi
}

# Создание расширений для 1С:Предприятие
# ВАЖНО: Расширения от 1С включают mchar, fulleq, fasttrun
docker_setup_1c_extensions() {
	echo ""
	echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	echo "Создание расширений для 1С:Предприятие"
	echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

	# Список расширений для 1С
	local extensions=("mchar" "fulleq" "fasttrun")

	for ext in "${extensions[@]}"; do
		echo "Создание расширения: $ext"

		docker_process_sql --dbname "$POSTGRES_DB" <<-EOSQL || {
			echo "⚠️  Внимание: Не удалось создать расширение $ext"
			echo "   Расширение может отсутствовать в дистрибутиве PostgreSQL"
			continue
		}
			CREATE EXTENSION IF NOT EXISTS $ext;
		EOSQL

		echo "✅ Расширение $ext создано успешно"
	done

	echo ""
	echo "Проверка созданных расширений:"
	docker_process_sql --dbname "$POSTGRES_DB" <<-'EOSQL'
		SELECT extname, extversion FROM pg_extension WHERE extname IN ('mchar', 'fulleq', 'fasttrun');
	EOSQL

	echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

docker_setup_user() {
	if [ -n "$POSTGRES_USER" ] && [ "$POSTGRES_USER" != 'postgres' ]; then
		docker_process_sql --dbname postgres --set user="$POSTGRES_USER" <<-'EOSQL'
			CREATE ROLE :"user" LOGIN SUPERUSER PASSWORD :'POSTGRES_PASSWORD' ;
		EOSQL
	fi
}

docker_temp_server_start() {
	if [ "$1" = 'postgres' ]; then
		shift
	fi

	set -- "$@" -c listen_addresses='' -p "${PGPORT:-5432}"

	PGUSER="${PGUSER:-$POSTGRES_USER}" \
	pg_ctl -D "$PGDATA" \
		-o "$(printf '%q ' "$@")" \
		-w start
}

docker_temp_server_stop() {
	PGUSER="${PGUSER:-postgres}" \
	pg_ctl -D "$PGDATA" -m fast -w stop
}

_main() {
	if [ "${1:0:1}" = '-' ]; then
		set -- postgres "$@"
	fi

	if [ "$1" = 'postgres' ] && ! _is_sourced; then
		_main "$@"
	fi

	docker_create_db_directories
	if [ "$(id -u)" = '0' ]; then
		exec gosu postgres "$BASH_SOURCE" "$@"
	fi

	if [ ! -s "$PGDATA/PG_VERSION" ]; then
		ls /docker-entrypoint-initdb.d/ > /dev/null

		file_env 'POSTGRES_INITDB_ARGS'
		docker_verify_minimum_env

		docker_init_database_dir

		docker_temp_server_start "$@"

		docker_setup_user
		docker_setup_db

		# Создание расширений для 1С
		docker_setup_1c_extensions

		docker_process_init_files /docker-entrypoint-initdb.d/*

		docker_temp_server_stop
	else
		echo "PostgreSQL Database directory appears to contain a database; Skipping initialization"
	fi

	echo ""
	echo "✅ PostgreSQL для 1С:Предприятие готов к работе"
	echo "   Версия PostgreSQL: $PG_MAJOR"
	echo "   Расширения: mchar, fulleq, fasttrun"
	echo ""

	exec "$@"
}

# Default values
: "${POSTGRES_USER:=postgres}"
: "${POSTGRES_DB:=$POSTGRES_USER}"
: "${PGDATA:=/var/lib/postgresql/data}"

file_env 'POSTGRES_PASSWORD'
file_env 'POSTGRES_USER'
file_env 'POSTGRES_DB'
file_env 'POSTGRES_INITDB_ARGS'
file_env 'POSTGRES_INITDB_WALDIR' ''
file_env 'POSTGRES_HOST_AUTH_METHOD'
file_env 'PGDATA'

if ! _is_sourced; then
	_main "$@"
fi
