#!/usr/bin/env bash
set -Eeo pipefail

# Docker entrypoint script для Postgres Pro с поддержкой 1С:Предприятие
# Базируется на официальном entrypoint PostgreSQL с адаптацией для Postgres Pro

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

# check to see if this file is being run or sourced from another script
_is_sourced() {
	[ "${#BASH_SOURCE[@]}" -gt 1 ]
}

# used to create initial postgres directories and if run as root, ensure ownership to the "postgres" user
docker_create_db_directories() {
	local user; user="$(id -u)"

	mkdir -p "$PGDATA"
	chmod 700 "$PGDATA"

	# ignore failure since it will be fine when using the image provided directory;
	# see also https://github.com/docker-library/postgres/pull/289
	mkdir -p /var/run/postgresql || :
	chmod 775 /var/run/postgresql || :

	# Create the transaction log directory before initdb is run so the directory is owned by the correct user
	if [ -n "$POSTGRES_INITDB_WALDIR" ]; then
		mkdir -p "$POSTGRES_INITDB_WALDIR"
		if [ "$user" = '0' ]; then
			find "$POSTGRES_INITDB_WALDIR" \! -user postgres -exec chown postgres '{}' +
		fi
		chmod 700 "$POSTGRES_INITDB_WALDIR"
	fi

	# allow the container to be started with `--user`
	if [ "$user" = '0' ]; then
		find "$PGDATA" \! -user postgres -exec chown postgres '{}' +
		find /var/run/postgresql \! -user postgres -exec chown postgres '{}' +
	fi
}

# initialize empty PGDATA directory with new database via 'initdb'
# arguments to `initdb` can be passed via POSTGRES_INITDB_ARGS or as arguments to this function
# `initdb` automatically creates the "postgres", "template0", and "template1" dbnames
# this is also where the database user is created, specified by `POSTGRES_USER` env
docker_init_database_dir() {
	# "initdb" is particular about the current user existing in "/etc/passwd", so we use "nss_wrapper" to fake that if necessary
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

	# unset/cleanup "nss_wrapper" bits
	if [ "${LD_PRELOAD:-}" = '/usr/lib/libnss_wrapper.so' ]; then
		rm -f "$NSS_WRAPPER_PASSWD" "$NSS_WRAPPER_GROUP"
		unset LD_PRELOAD NSS_WRAPPER_PASSWD NSS_WRAPPER_GROUP
	fi
}

# print large warning if POSTGRES_PASSWORD is long
# error if both POSTGRES_PASSWORD is empty and POSTGRES_HOST_AUTH_METHOD is not 'trust'
# print large warning if POSTGRES_HOST_AUTH_METHOD is set to 'trust'
docker_verify_minimum_env() {
	if [ "${#POSTGRES_PASSWORD}" -ge 100 ]; then
		cat >&2 <<-'EOWARN'

			WARNING: The supplied POSTGRES_PASSWORD is 100+ characters.

			  This will not work if used via PGPASSWORD with "psql".

			  https://www.postgresql.org/message-id/flat/E1Rqxp2-0004Qt-PL%40wrigleys.postgresql.org (BUG #6412)
			  https://github.com/docker-library/postgres/issues/507

		EOWARN
	fi
	if [ -z "$POSTGRES_PASSWORD" ] && [ 'trust' != "$POSTGRES_HOST_AUTH_METHOD" ]; then
		# The - option suppresses leading tabs but *not* spaces. :)
		cat >&2 <<-'EOE'
			Error: Database is uninitialized and superuser password is not specified.
			       You must specify POSTGRES_PASSWORD to a non-empty value for the
			       superuser. For example, "-e POSTGRES_PASSWORD=password" on "docker run".

			       You may also use "POSTGRES_HOST_AUTH_METHOD=trust" to allow all
			       connections without a password. This is *not* recommended.

			       See PostgreSQL documentation about "trust":
			       https://www.postgresql.org/docs/current/auth-trust.html
		EOE
		exit 1
	fi
	if [ 'trust' = "$POSTGRES_HOST_AUTH_METHOD" ]; then
		cat >&2 <<-'EOWARN'
			********************************************************************************
			WARNING: POSTGRES_HOST_AUTH_METHOD has been set to "trust". This will allow
			         anyone with access to the Postgres port to access your database without
			         a password, even if POSTGRES_PASSWORD is set. See PostgreSQL
			         documentation about "trust":
			         https://www.postgresql.org/docs/current/auth-trust.html
			         In Docker's default configuration, this is effectively any other
			         container on the same system.

			         It is not recommended to use POSTGRES_HOST_AUTH_METHOD=trust. Replace
			         it with "-e POSTGRES_PASSWORD=password" instead to set a password in
			         "docker run".
			********************************************************************************
		EOWARN
	fi
}

# usage: docker_process_init_files [file [file [...]]]
#    ie: docker_process_init_files /always-initdb.d/*
# process initializer files, based on file extensions and permissions
docker_process_init_files() {
	# psql here for backwards compatibility "${psql[@]}"
	psql=( docker_process_sql )

	echo
	local f
	for f; do
		case "$f" in
			*.sh)
				# https://github.com/docker-library/postgres/issues/450#issuecomment-393167936
				# https://github.com/docker-library/postgres/pull/452
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

# Execute sql script, passed via stdin (or -f flag of pqsl)
docker_process_sql() {
	local query_runner=( psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --no-password )
	if [ -n "$POSTGRES_DB" ]; then
		query_runner+=( --dbname "$POSTGRES_DB" )
	fi

	"${query_runner[@]}" "$@"
}

# create initial database
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
docker_setup_1c_extensions() {
	echo "Creating 1C:Enterprise extensions..."
	docker_process_sql --dbname "$POSTGRES_DB" <<-'EOSQL'
		CREATE EXTENSION IF NOT EXISTS mchar;
		CREATE EXTENSION IF NOT EXISTS fulleq;
		CREATE EXTENSION IF NOT EXISTS fasttrun;
	EOSQL
	echo "1C:Enterprise extensions created successfully"
}

docker_setup_user() {
	if [ -n "$POSTGRES_USER" ] && [ "$POSTGRES_USER" != 'postgres' ]; then
		docker_process_sql --dbname postgres --set user="$POSTGRES_USER" <<-'EOSQL'
			CREATE ROLE :"user" LOGIN SUPERUSER PASSWORD :'POSTGRES_PASSWORD' ;
		EOSQL
	fi
}

# Starts a temporary server in the background
docker_temp_server_start() {
	if [ "$1" = 'postgres' ]; then
		shift
	fi

	# internal start of server in order to allow setup using psql client
	# does not listen on external TCP/IP and waits until start finishes
	set -- "$@" -c listen_addresses='' -p "${PGPORT:-5432}"

	PGUSER="${PGUSER:-$POSTGRES_USER}" \
	pg_ctl -D "$PGDATA" \
		-o "$(printf '%q ' "$@")" \
		-w start
}

# Stops the temporary server
docker_temp_server_stop() {
	PGUSER="${PGUSER:-postgres}" \
	pg_ctl -D "$PGDATA" -m fast -w stop
}

_main() {
	# if first arg looks like a flag, assume we want to run postgres server
	if [ "${1:0:1}" = '-' ]; then
		set -- postgres "$@"
	fi

	if [ "$1" = 'postgres' ] && ! _is_sourced; then
		_main "$@"
	fi

	# setup data directories and permissions (when run as root)
	docker_create_db_directories
	if [ "$(id -u)" = '0' ]; then
		# then restart script as postgres user
		exec gosu postgres "$BASH_SOURCE" "$@"
	fi

	# look specifically for PG_VERSION, as it is expected in the DB dir
	if [ ! -s "$PGDATA/PG_VERSION" ]; then
		# check dir permissions to reduce likelihood of half-initialized database
		ls /docker-entrypoint-initdb.d/ > /dev/null

		file_env 'POSTGRES_INITDB_ARGS'
		docker_verify_minimum_env

		# setup database
		docker_init_database_dir

		# start temp server for initialization
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

	exec "$@"
}

# setup default values
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
